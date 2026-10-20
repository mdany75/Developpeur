import Foundation

/// Erreur JSON-RPC 2.0.
public struct JSONRPCError: Error, Equatable {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603

    public var code: Int
    public var message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// Serveur MCP minimal : négociation `initialize`, `ping`, `tools/list`, `tools/call`,
/// `prompts/list` et `prompts/get`, sur des messages JSON-RPC 2.0 d'une ligne chacun.
///
/// Les appels d'outils passent par une file (`FileOutils`) : un seul à la fois vers Lightroom, sur
/// un fil à part, et une réponse d'attente passé `toolBudget` quand le client ne suit pas la
/// progression (Claude Desktop abandonne au bout de 60 s). `notifications/cancelled` arrête
/// l'appel nommé entre deux photos d'une série, et sa réponse ne part pas.
public final class MCPServer {
    public static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    public let name: String
    /// Nom affiché (`serverInfo.title`, spécification MCP 2025-06-18) ; `name` reste l'identifiant.
    public let title: String?
    public let version: String
    public let instructions: String
    private let tools: ToolHandler
    private let file = FileOutils()
    /// Appels d'outils attendus, par identifiant de requête (`JSONCoding.line` de l'id), pour
    /// `notifications/cancelled`.
    private var attendus: [String: FileOutils.Appel] = [:]
    private let verrouAttendus = NSLock()
    /// Envoie un message du serveur hors réponse (notification de progression), depuis n'importe
    /// quel fil : l'appelant le sérialise avec les réponses. Sans lui, aucune progression.
    public var notifier: ((JSONValue) -> Void)?
    /// Intervalle des notifications de progression d'un appel d'outil.
    public var progressInterval: TimeInterval = 5
    /// Limite d'un appel d'outil dont la requête ne porte pas de jeton de progression, sous les
    /// 60 s de Claude Desktop (qui n'en donne pas) ; avec un jeton (Claude Code), le serveur envoie
    /// la progression et attend la fin.
    public var toolBudget: TimeInterval = 50

    /// Ressources que le client suit (`resources/subscribe`).
    private var abonnements: Set<String> = []
    private let verrouAbonnements = NSLock()
    /// La photo active a changé dans Lightroom et aucun client ne suit sa ressource (Claude Desktop
    /// ne s'abonne pas : constaté en 2.3) : dit une fois, avec le résultat d'outil suivant.
    private var photoActiveEnAttente: String?

    public init(name: String, title: String? = nil, version: String, instructions: String, tools: ToolHandler) {
        self.name = name
        self.title = title
        self.version = version
        self.instructions = instructions
        self.tools = tools
        LightroomBridge.surEvenements = { [weak self] evenements in self?.evenementModule(evenements) }
    }

    /// Le module a signalé un changement (avec une réponse) : la photo active a changé, la ressource
    /// de son aperçu aussi, pour un client qui la suit.
    public func evenementModule(_ evenements: JSONValue) {
        guard evenements["photo_active"]?.bool == true else { return }
        let uri = ToolHandler.ressourceApercuActif
        verrouAbonnements.lock()
        let suivie = abonnements.contains(uri)
        if !suivie {
            var texte = "À savoir : la photo active a changé dans Lightroom depuis l'appel précédent"
            if let fichier = evenements["fichier"]?.string { texte += " : « \(fichier) »" }
            if let id = evenements["id"]?.int { texte += " (id \(id))" }
            photoActiveEnAttente = texte + ". Sans photo_id, les outils visent celle-là."
        }
        verrouAbonnements.unlock()
        if suivie {
            notifier?(["jsonrpc": "2.0", "method": "notifications/resources/updated", "params": ["uri": .string(uri)]])
        }
    }

    /// Le changement de photo active gardé pour le résultat d'outil suivant, une seule fois. Pas pour
    /// show_photo, qui l'a changée lui-même.
    func photoActiveAnnoncee(pour outil: String) -> String? {
        verrouAbonnements.lock()
        defer { verrouAbonnements.unlock() }
        let texte = photoActiveEnAttente
        photoActiveEnAttente = nil
        return outil == "show_photo" ? nil : texte
    }

    /// Réponse à un message : aucune (notification), tout de suite, ou à la fin d'un appel d'outil.
    enum Reponse {
        case aucune
        case immediate(JSONValue)
        /// Nil : l'appel a été annulé, rien ne part.
        case differee(() -> JSONValue?)
    }

    /// Traite une ligne reçue ; renvoie la ligne à répondre, ou `nil` pour une notification.
    /// Attend la fin d'un appel d'outil (ou sa limite).
    public func handle(line: String) -> String? {
        switch traiter(line: line) {
        case .aucune: return nil
        case .immediate(let reponse): return JSONCoding.line(reponse)
        case .differee(let attendre): return attendre().map(JSONCoding.line)
        }
    }

    /// Traite une ligne reçue sans attendre : un appel d'outil prend sa place dans la file tout de
    /// suite, et sa réponse part par `respond` depuis un autre fil quand il a fini (ou à sa limite).
    public func receive(line: String, respond: @escaping (String) -> Void) {
        switch traiter(line: line) {
        case .aucune: break
        case .immediate(let reponse): respond(JSONCoding.line(reponse))
        case .differee(let attendre): DispatchQueue.global().async { if let reponse = attendre() { respond(JSONCoding.line(reponse)) } }
        }
    }

    public func handle(message: JSONValue) -> JSONValue? {
        switch traiter(message: message) {
        case .aucune: return nil
        case .immediate(let reponse): return reponse
        case .differee(let attendre): return attendre()
        }
    }

    func traiter(line: String) -> Reponse {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .aucune }
        do {
            return traiter(message: try JSONCoding.parse(trimmed))
        } catch {
            return .immediate(Self.errorResponse(id: .null, code: JSONRPCError.parseError, message: "JSON illisible"))
        }
    }

    func traiter(message: JSONValue) -> Reponse {
        guard case .object = message, let method = message["method"]?.string else {
            return .immediate(Self.errorResponse(id: message["id"] ?? .null, code: JSONRPCError.invalidRequest,
                                                 message: "Requête JSON-RPC invalide"))
        }
        let id = message["id"]
        let params = message["params"] ?? .object([:])

        if method == "notifications/cancelled" {
            annuler(params["requestId"])
            return .aucune
        }
        if method.hasPrefix("notifications/") {
            return .aucune
        }
        guard let requestID = id, !requestID.isNull else {
            // Requête sans identifiant : rien à répondre.
            return .aucune
        }
        if method == "resources/read" {
            guard let uri = params["uri"]?.string else {
                return .immediate(Self.errorResponse(id: requestID, code: JSONRPCError.invalidParams, message: "Paramètre « uri » manquant"))
            }
            return lectureRessource(uri, id: requestID)
        }
        if method == "tools/call" {
            guard let toolName = params["name"]?.string else {
                return .immediate(Self.errorResponse(id: requestID, code: JSONRPCError.invalidParams, message: "Paramètre « name » manquant"))
            }
            // Un outil inconnu est une erreur de protocole (spécification MCP), pas un résultat d'outil.
            guard ToolHandler.toolNames.contains(toolName) else {
                return .immediate(Self.errorResponse(id: requestID, code: JSONRPCError.invalidParams, message: "Outil inconnu : \(toolName)"))
            }
            return appelOutil(toolName, arguments: params["arguments"]?.object ?? [:],
                              jeton: params["_meta"]?["progressToken"], id: requestID)
        }

        do {
            let result = try dispatch(method: method, params: params)
            return .immediate(["jsonrpc": "2.0", "id": requestID, "result": result])
        } catch let error as JSONRPCError {
            return .immediate(Self.errorResponse(id: requestID, code: error.code, message: error.message))
        } catch {
            return .immediate(Self.errorResponse(id: requestID, code: JSONRPCError.internalError, message: error.localizedDescription))
        }
    }

    /// L'appel prend sa place dans la file dès son arrivée ; la limite part de là. Le client qui
    /// donne un jeton de progression reçoit un battement tant qu'il attend, arrêté avant la
    /// réponse, et pas de limite.
    private func appelOutil(_ toolName: String, arguments: [String: JSONValue], jeton: JSONValue?, id: JSONValue) -> Reponse {
        let jeton = jeton.flatMap { $0.isNull ? nil : $0 }
        let limite = jeton == nil ? Date().addingTimeInterval(toolBudget) : nil
        let appel = file.soumettre(nom: toolName, arguments: arguments) { [tools] contexte in
            tools.call(name: toolName, arguments: arguments, contexte: contexte)
        }
        let cle = JSONCoding.line(id)
        verrouAttendus.lock(); attendus[cle] = appel; verrouAttendus.unlock()
        return .differee { [self] in
            let progression = jeton.flatMap { jeton in
                notifier.map { Progression(jeton: jeton, intervalle: progressInterval, envoyer: $0) }
            }
            if let progression {
                appel.contexte.observer { fait, total, message in progression.avancer(fait: fait, total: total, message: message) }
            }
            var result = file.attendre(appel, jusqua: limite)
            if let annonce = photoActiveAnnoncee(pour: toolName) {
                result.content.append(.text(annonce))
            }
            appel.contexte.observer(nil)
            progression?.arreter()
            verrouAttendus.lock(); attendus[cle] = nil; verrouAttendus.unlock()
            // Annulé par le client : pas de réponse (spécification MCP).
            if appel.contexte.annule { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": Self.resultatOutil(toolName, result)]
        }
    }

    /// Lecture d'une ressource : par la file des outils (l'aperçu passe par Lightroom), avec la même
    /// limite qu'un appel d'outil sans jeton de progression.
    private func lectureRessource(_ uri: String, id: JSONValue) -> Reponse {
        let limite = Date().addingTimeInterval(toolBudget)
        let appel = file.soumettre(nom: "resources/read", arguments: ["uri": .string(uri)]) { [tools] _ in
            tools.lireRessource(uri)
        }
        return .differee { [self] in
            let result = file.attendre(appel, jusqua: limite)
            guard !result.isError, let contents = result.structured else {
                return Self.errorResponse(id: id, code: -32002, message: result.text.isEmpty ? "Ressource illisible : \(uri)" : result.text)
            }
            return ["jsonrpc": "2.0", "id": id, "result": contents]
        }
    }

    /// Le résultat d'un appel d'outil, avec `structuredContent` quand l'outil déclare un
    /// `outputSchema` : le client l'exige pour toute réponse qui n'est pas une erreur, réponse
    /// d'attente comprise (elle porte alors son texte).
    static func resultatOutil(_ toolName: String, _ result: ToolResult) -> JSONValue {
        var reponse: [String: JSONValue] = ["content": .array(result.content.map(\.json)), "isError": .bool(result.isError)]
        if ToolHandler.outputSchemas[toolName] != nil, !result.isError {
            reponse["structuredContent"] = result.structured ?? ["message": .string(result.text)]
        } else if let structured = result.structured {
            reponse["structuredContent"] = structured
        }
        return .object(reponse)
    }

    /// `notifications/cancelled` : l'appel d'outil encore attendu sous cet identifiant s'arrête.
    private func annuler(_ requestID: JSONValue?) {
        guard let requestID, !requestID.isNull else { return }
        verrouAttendus.lock()
        let appel = attendus[JSONCoding.line(requestID)]
        verrouAttendus.unlock()
        if let appel { file.annuler(appel) }
    }

    private func dispatch(method: String, params: JSONValue) throws -> JSONValue {
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.string ?? ""
            let negotiated = Self.supportedProtocolVersions.contains(requested)
                ? requested : Self.supportedProtocolVersions[0]
            var serverInfo: [String: JSONValue] = ["name": .string(name), "version": .string(version)]
            if let title { serverInfo["title"] = .string(title) }
            return [
                "protocolVersion": .string(negotiated),
                "capabilities": ["tools": ["listChanged": false], "prompts": ["listChanged": false], "resources": ["listChanged": false, "subscribe": true]],
                "serverInfo": .object(serverInfo),
                "instructions": .string(instructions),
            ]
        case "ping":
            return [:]
        case "resources/list":
            return ["resources": .array(tools.resources)]
        case "resources/subscribe", "resources/unsubscribe":
            guard let uri = params["uri"]?.string else {
                throw JSONRPCError(code: JSONRPCError.invalidParams, message: "Paramètre « uri » manquant")
            }
            verrouAbonnements.lock()
            if method == "resources/subscribe" { abonnements.insert(uri) } else { abonnements.remove(uri) }
            verrouAbonnements.unlock()
            return [:]
        case "resources/templates/list":
            return ["resourceTemplates": .array(tools.resourceTemplates)]
        case "tools/list":
            return ["tools": .array(tools.definitions)]
        case "prompts/list":
            return ["prompts": .array(Prompts.all.map(\.definition))]
        case "prompts/get":
            guard let promptName = params["name"]?.string else {
                throw JSONRPCError(code: JSONRPCError.invalidParams, message: "Paramètre « name » manquant")
            }
            guard let prompt = Prompts.all.first(where: { $0.name == promptName }) else {
                throw JSONRPCError(code: JSONRPCError.invalidParams, message: "Invite inconnue : \(promptName)")
            }
            var arguments: [String: String] = [:]
            for (key, value) in params["arguments"]?.object ?? [:] {
                if let text = value.string { arguments[key] = text }
            }
            return [
                "description": .string(prompt.description),
                "messages": [["role": "user", "content": ["type": "text", "text": .string(Prompts.texte(prompt, arguments, guide: tools.guideStyle.pourInvite()))]]],
            ]
        default:
            throw JSONRPCError(code: JSONRPCError.methodNotFound, message: "Méthode inconnue : \(method)")
        }
    }

    private static func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }
}
