import Darwin
import Foundation

public enum LightroomError: Error, LocalizedError, Equatable {
    /// Lightroom fermé, ou liaison du module arrêtée.
    case unreachable(String)
    /// Lightroom n'a pas répondu à temps.
    case timeout(String)
    /// Le module a refusé ou échoué (message en français, à montrer tel quel).
    case plugin(String)
    /// Argument d'outil invalide.
    case invalid(String)
    /// La liaison a été coupée en plein échange (Lightroom relancé, module rechargé).
    case interrupted(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let message), .timeout(let message), .plugin(let message), .invalid(let message), .interrupted(let message):
            return message
        }
    }
}

/// Ce que les outils attendent du module Lightroom : une commande, un résultat JSON.
/// `LightroomBridge` en est l'implémentation réelle ; les tests en fournissent une fausse.
public protocol LightroomServing: AnyObject {
    func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue
    /// Version du module, lue à la dernière connexion (nil : inconnue, module d'avant la 2.0).
    var moduleVersion: String? { get }
}

public extension LightroomServing {
    var moduleVersion: String? { nil }
}

/// Client TCP du module « Développeur ». Le module écoute sur 127.0.0.1 avec deux
/// prises `LrSocket` à sens unique : l'une reçoit les commandes (`requestPort`), l'autre renvoie
/// les réponses (`replyPort`). Chaque message est une ligne JSON :
///   commande → `{"id": 7, "jeton": "<64 chiffres hexadécimaux>", "commande_id": "<UUID>", "command": "apercu", "params": {…}}`
///   réponse  ← `{"id": 7, "result": {…}}` ou `{"id": 7, "error": "message"}`
///   refus    ← `{"id": 7, "error": "Liaison fermée : …", "code": "jeton"}`
///   arrêt    ← `{"id": 7, "error": "Arrêtée par l'utilisateur …", "code": "arret"}` (croix de la
///              barre d'une commande longue : `CommandeArretee`, jamais reprise)
/// Une connexion par commande, fermée aussitôt après : `LrSocket` ne sert qu'un client à la fois,
/// et Claude Desktop comme chaque session de Claude Code lancent leur propre serveur. Entre deux
/// connexions, le module rouvre sa prise des réponses : un refus bref est donc retenté.
///
/// Liaison fermée (1.2) : le jeton privé que le module écrit à chaque démarrage de la liaison
/// (`JetonLiaison`) est relu à chaque connexion et part dans chaque ligne, ping compris. Un refus
/// du jeton (liaison redémarrée entre la lecture et le ping) fait relire le fichier une fois. Sans
/// fichier, aucune clé `jeton` : un module d'avant la 1.2 accepte la ligne comme avant. Le jeton
/// n'est jamais journalisé.
///
/// Ne plus perdre une réponse : chaque commande, sauf `ping`, part avec un `commande_id` (UUID tiré
/// pour elle), sous lequel le module garde sa réponse (les 20 dernières, 10 minutes). Quand elle
/// n'arrive pas (délai dépassé, liaison coupée), et que la commande écrit ou coûte
/// (`reprendLaReponse`), le serveur la redemande par la commande système `reprendre`, avec le jeton,
/// au lieu de la relancer : une écriture n'est jamais rejouée. Sans réponse gardée (jamais reçue,
/// module rechargé, module d'avant la reprise), ou faite sans réponse gardée (trop grosse), une
/// lecture se rejoue comme avant, une écriture rend son erreur ; une écriture encore en cours
/// rend « tourne encore… ne pas la relancer ».
public final class LightroomBridge: LightroomServing {
    public static let defaultRequestPort: UInt16 = 54770
    public static let defaultReplyPort: UInt16 = 54771

    public static let unreachableMessage = """
    Lightroom Classic ne répond pas. Ouvrir Lightroom Classic et vérifier que la liaison avec Claude est \
    démarrée (Fichier › Module externe - Extras › Démarrer la liaison avec Claude). Si le module n'apparaît pas, \
    activer « Développeur IA pour Lightroom » dans Fichier › Gestionnaire de modules externes.
    """
    /// La connexion est acceptée mais le module ne répond pas au `ping` : sa prise ne sert qu'un
    /// client à la fois, et une autre session de Claude (Claude Desktop, une autre session Claude
    /// Code) lui fait sans doute faire une longue commande. Ce n'est pas « Lightroom fermé ».
    public static let busyMessage = """
    La liaison avec Lightroom Classic est occupée : le module accepte la connexion mais ne répond pas au ping. \
    Une autre session de Claude (Claude Desktop ou une autre session Claude Code) lui fait sans doute faire une longue \
    commande (débruitage, livraison, aperçu), ou Lightroom attend une réponse dans une fenêtre. Réessayer dans un instant ; \
    rien n'a été fait.
    """
    /// Le module refuse la commande faute du bon jeton, et le fichier du jeton manque ou est mal
    /// formé : la liaison doit le réécrire.
    public static let jetonIntrouvableMessage = """
    Le module de Lightroom demande le jeton de la liaison, mais le fichier « liaison.jeton » est introuvable ou \
    illisible (~/Library/Application Support/Developpeur/) : rien n'a été fait. Relancer la liaison dans Lightroom \
    (Fichier › Module externe - Extras › Arrêter, puis Démarrer la liaison avec Claude) : elle le réécrit.
    """

    public let host: String
    public let requestPort: UInt16
    public let replyPort: UInt16
    /// Fichier du jeton de la liaison, relu à chaque connexion ; nil (par défaut, et dans les
    /// tests) : aucun jeton envoyé. Seul `fromEnvironment` pointe le vrai fichier.
    public let fichierJeton: URL?

    /// Durée pendant laquelle un refus de connexion est retenté (le module rouvre ses prises).
    public var refusalRetryWindow: TimeInterval = 3
    /// Délai de la poignée de main (`ping`) ; le module attend jusqu'à 3 s sa prise des réponses.
    public var handshakeTimeout: TimeInterval = 4
    /// Journal détaillé (`DEVELOPPEUR_VERBOSE=1`) : durée de chaque commande du module.
    public var journal: ((String) -> Void)?
    /// Commandes qui ne changent rien : reprises une fois, après une seconde, si la liaison est
    /// coupée en plein échange (une écriture ne se reprend pas : elle a peut-être été faite). Les
    /// commandes de la 1.3 : etapes (images des étapes, lues) en est ; carnet n'en est pas, car il
    /// écrit carnet.json (constater, retirer) : rejoué, il le réécrirait. habitudes (1.6) ne fait que
    /// lire. taches (1.6.6) ne fait que lire.
    public static let lectures: Set<String> = ["etat", "selection", "reglages", "apercu", "vignettes", "chercher", "motsCles",
                                               "presets", "journal", "diagnostic", "livraison", "etapes", "habitudes", "taches"]
    public var delaiReprise: TimeInterval = 1
    /// Lectures qui coûtent (rendus, vignettes, recherche dans tout le catalogue) : leur réponse
    /// perdue se redemande au module avant de les relancer.
    public static let lecturesCouteuses: Set<String> = ["apercu", "vignettes", "chercher"]
    /// Délai d'une demande de reprise (le module la sert de sa mémoire, sans attendre Lightroom).
    public var delaiRepriseReponse: TimeInterval = 3
    /// Après une coupure, combien de temps redemander une réponse que le module dit en cours.
    public var attenteReprise: TimeInterval = 30
    /// Entre deux demandes d'une réponse en cours.
    public var intervalleReprise: TimeInterval = 1

    /// Vrai si la réponse perdue de cette commande se redemande au module (`reprendre`) : toute
    /// commande qui n'est pas une lecture (une écriture ne se rejoue jamais), et les lectures
    /// coûteuses.
    public static func reprendLaReponse(_ command: String) -> Bool {
        guard command != "ping", command != "reprendre" else { return false }
        return !lectures.contains(command) || lecturesCouteuses.contains(command)
    }

    /// La commande a été faite, mais le module n'a pas gardé sa réponse (trop grosse) : rien n'est relancé.
    public static func reponseNonGardeeMessage(_ command: String) -> String {
        """
        La commande « \(command) » a été faite dans Lightroom, mais sa réponse s'est perdue en route et le module \
        ne l'a pas gardée (trop grosse) : ne pas la relancer ; relire la photo (view_photo, get_settings) pour voir où elle en est.
        """
    }

    /// La commande qui écrit tourne encore dans Lightroom quand la reprise s'arrête : rien n'est
    /// relancé, elle finira seule.
    public static func encoreEnCoursMessage(_ command: String) -> String {
        """
        La commande « \(command) » tourne encore dans Lightroom (il est occupé) : ne pas la relancer, elle finira \
        seule ; relire la photo dans un moment (view_photo, get_settings) pour voir où elle en est.
        """
    }

    /// Version que le module a donnée à la dernière poignée de main (`ping`).
    public private(set) var moduleVersion: String?

    private var requestSocket: Int32 = -1
    private var replySocket: Int32 = -1
    private var buffer = Data()
    private var nextID = 1
    /// Jeton lu à la connexion en cours (nil : pas de fichier, ou fichier illisible).
    private var jetonCourant: String?

    /// Refus du jeton par le module (`code: "jeton"`) : traité par `connect`, qui relit le fichier
    /// une fois, puis montré comme une erreur du module.
    private struct RefusJeton: Error {
        let message: String
    }

    public init(host: String = "127.0.0.1",
                requestPort: UInt16 = LightroomBridge.defaultRequestPort,
                replyPort: UInt16 = LightroomBridge.defaultReplyPort,
                fichierJeton: URL? = nil) {
        self.host = host
        self.requestPort = requestPort
        self.replyPort = replyPort
        self.fichierJeton = fichierJeton
    }

    /// Ports donnés par `DEVELOPPEUR_PORT` (commandes ; les réponses sur le port suivant), et
    /// journal sur stderr avec `DEVELOPPEUR_VERBOSE=1`. Le jeton vient du fichier que le module
    /// écrit (`JetonLiaison.fichierParDefaut`) : serveur de Claude Desktop, de Claude Code, de la
    /// fenêtre Claude, `--call` et la recette ont le même, sans réglage.
    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> LightroomBridge {
        let bridge: LightroomBridge
        if let text = environment["DEVELOPPEUR_PORT"], let port = UInt16(text), port < UInt16.max {
            bridge = LightroomBridge(requestPort: port, replyPort: port + 1, fichierJeton: JetonLiaison.fichierParDefaut())
        } else {
            bridge = LightroomBridge(fichierJeton: JetonLiaison.fichierParDefaut())
        }
        if environment["DEVELOPPEUR_VERBOSE"] == "1" {
            bridge.journal = { FileHandle.standardError.write(Data("[mcp-developpeur] \($0)\n".utf8)) }
        }
        return bridge
    }

    deinit {
        disconnect()
    }

    public var isConnected: Bool { requestSocket >= 0 && replySocket >= 0 }

    /// Ce que le module signale avec une réponse (`evenements` : la photo active a changé), pour le
    /// serveur MCP (ressources suivies). Un seul destinataire par processus.
    private static let verrouEvenements = NSLock()
    private static var destinataire: ((JSONValue) -> Void)?
    public static var surEvenements: ((JSONValue) -> Void)? {
        get { verrouEvenements.lock(); defer { verrouEvenements.unlock() }; return destinataire }
        set { verrouEvenements.lock(); destinataire = newValue; verrouEvenements.unlock() }
    }
    static func signalerEvenements(_ evenements: JSONValue) { surEvenements?(evenements) }

    public func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue {
        let started = Date()
        defer { journal?(String(format: "commande « %@ » : %.2f s", command, Date().timeIntervalSince(started))) }
        let commandeID = command == "ping" ? nil : UUID().uuidString
        do {
            return try envoyer(command, params, commandeID: commandeID, timeout: timeout)
        } catch let erreur as LightroomError {
            let coupure: Bool
            switch erreur {
            case .interrupted: coupure = true
            case .timeout: coupure = false
            default: throw erreur
            }
            // D'abord la réponse gardée par le module : rien n'est refait.
            if let commandeID, Self.reprendLaReponse(command),
               let reprise = try reprendre(commandeID, command, attente: coupure ? attenteReprise : 0) {
                return reprise
            }
            guard coupure, Self.lectures.contains(command), case .interrupted(let message) = erreur else { throw erreur }
            journal?("liaison coupée pendant « \(command) » : relancée")
            Thread.sleep(forTimeInterval: delaiReprise)
            do {
                return try envoyer(command, params, commandeID: UUID().uuidString, timeout: timeout)
            } catch {
                throw LightroomError.interrupted(message)
            }
        }
    }

    /// Redemande au module la réponse perdue de la commande `commandeID` (`reprendre`). Rend son
    /// résultat, lève son erreur, ou nil si le module ne l'a pas (jamais reçue, oubliée, module
    /// rechargé, module d'avant la reprise, Lightroom injoignable). Une commande que le module dit
    /// en cours est redemandée pendant `attente` secondes ; encore en cours ensuite, une écriture
    /// lève `encoreEnCoursMessage` (relancée, elle se ferait deux fois), une lecture rend nil. Une
    /// réponse faite mais non gardée (`indisponible`) : erreur pour une écriture, nil pour une
    /// lecture, que `send` relance comme avant. Ne relance jamais la commande.
    private func reprendre(_ commandeID: String, _ command: String, attente: TimeInterval) throws -> JSONValue? {
        let fin = Date().addingTimeInterval(attente)
        while true {
            let reponse: JSONValue
            do {
                reponse = try envoyer("reprendre", ["commande_id": .string(commandeID)], commandeID: nil, timeout: delaiRepriseReponse)
            } catch {
                journal?("reprise de « \(command) » impossible : \(error.localizedDescription)")
                return nil
            }
            if reponse["trouve"]?.bool == true {
                journal?("réponse de « \(command) » reprise au module")
                if reponse["indisponible"]?.string != nil {
                    // Une lecture se relance sans risque (la recherche de 1 000 photos dépasse 64 Ko).
                    if Self.lectures.contains(command) { return nil }
                    throw LightroomError.plugin(Self.reponseNonGardeeMessage(command))
                }
                let gardee = reponse["reponse"] ?? .null
                if let error = gardee["error"], !error.isNull {
                    let texte = error.string ?? JSONCoding.line(error)
                    if gardee["code"]?.string == "arret" { throw CommandeArretee(message: texte) }
                    throw LightroomError.plugin(texte)
                }
                return gardee["result"] ?? .null
            }
            guard reponse["en_cours"]?.bool == true else { return nil }
            guard Date() < fin else {
                if Self.lectures.contains(command) { return nil }
                // `.timeout` : partie sans réponse, peut-être faite (`peutEtreExecutee`).
                throw LightroomError.timeout(Self.encoreEnCoursMessage(command))
            }
            Thread.sleep(forTimeInterval: intervalleReprise)
        }
    }

    private func envoyer(_ command: String, _ params: [String: JSONValue], commandeID: String?, timeout: TimeInterval) throws -> JSONValue {
        try connect()
        defer { disconnect() }
        do {
            return try exchange(command, params, commandeID: commandeID, timeout: timeout)
        } catch let refus as RefusJeton {
            // Le ping est passé avec ce jeton : la liaison a redémarré entre les deux. Rien n'a été fait.
            throw LightroomError.plugin(refus.message)
        }
    }

    public func disconnect() {
        if requestSocket >= 0 { close(requestSocket) }
        if replySocket >= 0 { close(replySocket) }
        requestSocket = -1
        replySocket = -1
        buffer.removeAll()
    }

    // MARK: Connexion

    /// Ouvre les deux prises puis vérifie la liaison par un `ping`. Un refus est retenté pendant
    /// `refusalRetryWindow` ; une poignée de main ratée (connexion acceptée trop tard, ou coupée
    /// pendant que le module rouvre sa prise des réponses) est retentée une fois. Le jeton est relu
    /// ici, à chaque connexion ; refusé, il est relu une seule fois de plus, s'il a changé.
    private func connect() throws {
        disconnect()
        jetonCourant = fichierJeton.flatMap(JetonLiaison.lire)
        var jetonRelu = false
        let refusalDeadline = Date().addingTimeInterval(refusalRetryWindow)
        var failedHandshakes = 0
        var silences = 0
        while true {
            do {
                // La prise des réponses d'abord : le module doit pouvoir répondre à la première commande.
                replySocket = try Self.openSocket(host: host, port: replyPort)
                requestSocket = try Self.openSocket(host: host, port: requestPort)
            } catch {
                disconnect()
                guard Date() < refusalDeadline else { throw LightroomError.unreachable(Self.unreachableMessage) }
                Thread.sleep(forTimeInterval: 0.2)
                continue
            }
            do {
                let pong = try exchange("ping", [:], timeout: handshakeTimeout)
                guard pong["pong"]?.bool == true else {
                    throw LightroomError.plugin("Le port \(requestPort) répond, mais ce n'est pas le module Développeur IA pour Lightroom.")
                }
                moduleVersion = pong["version"]?.string
                return
            } catch let refus as RefusJeton {
                disconnect()
                let neuf = fichierJeton.flatMap(JetonLiaison.lire)
                // La liaison a redémarré entre la lecture et le ping : son nouveau jeton, une fois.
                if !jetonRelu, let neuf = neuf, neuf != jetonCourant {
                    jetonRelu = true
                    jetonCourant = neuf
                    journal?("jeton de la liaison renouvelé : relu")
                    continue
                }
                if fichierJeton != nil, neuf == nil {
                    throw LightroomError.plugin(Self.jetonIntrouvableMessage)
                }
                throw LightroomError.plugin(refus.message)
            } catch {
                disconnect()
                if case LightroomError.plugin = error { throw error }
                if case LightroomError.timeout = error { silences += 1 }
                failedHandshakes += 1
                // Deux pings sans réponse sur une connexion acceptée : la liaison est tenue par une
                // autre session ; une connexion coupée pendant la poignée de main : Lightroom part ou
                // le module rouvre ses prises.
                guard failedHandshakes < 2 else {
                    throw LightroomError.unreachable(silences == failedHandshakes ? Self.busyMessage : Self.unreachableMessage)
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
    }

    private static func openSocket(host: String, port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LightroomError.unreachable("Impossible d'ouvrir une prise réseau (errno \(errno)).") }
        var yes: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        // Écrire vers une prise fermée ne doit pas tuer le serveur (SIGPIPE).
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, size)
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, size)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close(fd)
            throw LightroomError.unreachable("Adresse invalide : \(host)")
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            throw LightroomError.unreachable(unreachableMessage)
        }
        return fd
    }

    // MARK: Échange

    private func exchange(_ command: String, _ params: [String: JSONValue], commandeID: String? = nil,
                          timeout: TimeInterval) throws -> JSONValue {
        let id = nextID
        nextID += 1
        var message: [String: JSONValue] = ["id": .number(Double(id)), "command": .string(command), "params": .object(params)]
        if let jeton = jetonCourant {
            message["jeton"] = .string(jeton)
        }
        if let commandeID {
            message["commande_id"] = .string(commandeID)
        }
        try write(JSONCoding.line(.object(message)) + "\n")

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let line = try readLine(until: deadline, command: command)
            guard let reply = try? JSONCoding.parse(line), reply["id"]?.int == id else {
                continue // réponse d'une commande précédente arrivée trop tard
            }
            if let evenements = reply["evenements"], !evenements.isNull {
                Self.signalerEvenements(evenements)
            }
            if let error = reply["error"], !error.isNull {
                let texte = error.string ?? JSONCoding.line(error)
                if reply["code"]?.string == "jeton" {
                    throw RefusJeton(message: texte)
                }
                // Arrêtée par l'utilisateur (croix de la barre « Claude » de Lightroom) : jamais reprise.
                if reply["code"]?.string == "arret" {
                    throw CommandeArretee(message: texte)
                }
                throw LightroomError.plugin(texte)
            }
            return reply["result"] ?? .null
        }
    }

    private func write(_ text: String) throws {
        let data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            let written = data[offset...].withUnsafeBufferPointer { Darwin.send(requestSocket, $0.baseAddress, $0.count, 0) }
            if written < 0 {
                if errno == EINTR { continue }
                disconnect()
                throw LightroomError.unreachable(Self.unreachableMessage)
            }
            offset += written
        }
    }

    private func readLine(until deadline: Date, command: String) throws -> String {
        while true {
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                return text
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw LightroomError.timeout("Lightroom n'a pas répondu à temps (commande « \(command) »). Il est peut-être occupé (export, import, fenêtre ouverte) : réessayer dans un instant.")
            }
            var descriptor = pollfd(fd: replySocket, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining, 3600) * 1000))
            if ready < 0 {
                if errno == EINTR { continue }
                disconnect()
                throw LightroomError.unreachable(Self.unreachableMessage)
            }
            if ready == 0 { continue }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let count = recv(replySocket, &chunk, chunk.count, 0)
            if count <= 0 {
                if count < 0, errno == EINTR { continue }
                disconnect()
                throw LightroomError.interrupted("La liaison avec Lightroom a été coupée pendant la commande « \(command) ». Vérifier dans Lightroom si elle a été appliquée (panneau Historique) avant de la relancer.")
            }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}
