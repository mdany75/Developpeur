import Foundation

/// Guide de style personnel (`remember_style`) et ressources MCP : le guide, le standard de
/// notation, l'aperçu et le journal d'une photo. La lecture d'une ressource qui touche Lightroom
/// passe par la file des outils, comme un appel d'outil (MCPServer).
extension ToolHandler {
    var styleDefinitions: [JSONValue] {
        [
            tool("remember_style",
                 "Guide de style personnel de l'utilisateur (ses goûts en retouche : profils, contraste, couleurs, peaux, noir et blanc, grain, recadrage, livraison), dans un fichier Markdown qu'il peut modifier lui-même, inclus dans l'invite retouche_pro. read = le lire avant de retoucher ; preference = y ajouter une préférence apprise en conversation (« il aime les noirs denses », « jamais de vignetage »), seulement après l'accord explicite de l'utilisateur sur la phrase exacte (confirm = true).",
                 properties: [
                    ("read", prop("boolean", "true = lire le guide (sans rien ajouter).")),
                    ("preference", prop("string", "La préférence à ajouter, en une phrase, telle que l'utilisateur l'a approuvée.")),
                    ("category", enumProp(GuideStyle.rubriques.map(\.nom), "Rubrique : \(GuideStyle.rubriques.map { "\($0.nom) (\($0.titre.lowercased()))" }.joined(separator: ", ")).")),
                    ("confirm", prop("boolean", "true = l'utilisateur a approuvé cette phrase (exigé pour ajouter).")),
                 ],
                 required: []),
        ]
    }

    func rememberStyle(_ args: Arguments) throws -> JSONValue {
        if let preference = args.string("preference") {
            guard args.bool("confirm") == true else {
                throw LightroomError.invalid("Rien n'a été ajouté : proposer la phrase à l'utilisateur, attendre son accord, puis rappeler remember_style avec confirm = true.")
            }
            let guide = try guideStyle.ajouter(preference, rubrique: args.string("category") ?? "other")
            return ["ajoute": .string(preference), "fichier": .string(guideStyle.fichier.path), "guide": .string(guide)]
        }
        guard let guide = guideStyle.lire() else {
            return ["guide": .null, "fichier": .string(guideStyle.fichier.path),
                    "a_savoir": "Pas encore de guide de style : il se remplit avec remember_style, après l'accord de l'utilisateur, ou à la main dans ce fichier."]
        }
        return ["guide": .string(guide), "fichier": .string(guideStyle.fichier.path)]
    }

    // MARK: Ressources

    static let ressourceGuide = "developpeur://guide-de-style"
    static let ressourceNotation = "developpeur://notation"
    static let ressourceApercuActif = "developpeur://photo/active/apercu"

    /// Ressources fixes (`resources/list`).
    public var resources: [JSONValue] {
        [
            ["uri": .string(Self.ressourceGuide), "name": "guide-de-style", "title": "Guide de style",
             "description": "Les goûts de l'utilisateur en retouche (remember_style).", "mimeType": "text/markdown"],
            ["uri": .string(Self.ressourceNotation), "name": "standard-de-notation", "title": "Standard de notation",
             "description": "Ce que vaut chaque note, de 1 à 5 étoiles, et comment noter une sortie (propose_ratings).", "mimeType": "text/markdown"],
            ["uri": .string(Self.ressourceApercuActif), "name": "apercu-photo-active", "title": "Aperçu de la photo active",
             "description": "La photo active de Lightroom, telle qu'elle est développée (JPEG de 1344 px).", "mimeType": "image/jpeg"],
        ]
    }

    /// Modèles de ressources (`resources/templates/list`).
    public var resourceTemplates: [JSONValue] {
        [
            ["uriTemplate": "developpeur://photo/{id}/apercu", "name": "apercu-photo", "title": "Aperçu d'une photo",
             "description": "Une photo du catalogue (id de list_selection ou find_photos), telle qu'elle est développée.", "mimeType": "image/jpeg"],
            ["uriTemplate": "developpeur://photo/{id}/journal", "name": "journal-photo", "title": "Journal des retouches d'une photo",
             "description": "Ce que Claude a changé sur cette photo, avec ses raisons (comme export_journal).", "mimeType": "text/markdown"],
        ]
    }

    /// Lit une ressource : `structured` = `{contents: [...]}`, ou une erreur.
    public func lireRessource(_ uri: String) -> ToolResult {
        do {
            let contents: [JSONValue]
            if uri == Self.ressourceGuide {
                let texte = guideStyle.lire() ?? "# Guide de style\n\nPas encore de préférence enregistrée.\n"
                contents = [["uri": .string(uri), "mimeType": "text/markdown", "text": .string(texte)]]
            } else if uri == Self.ressourceNotation {
                contents = [["uri": .string(uri), "mimeType": "text/markdown", "text": .string(Notation.standard)]]
            } else if let (id, quoi) = Self.photoDeRessource(uri) {
                switch quoi {
                case "apercu":
                    var params: [String: JSONValue] = ["taille": .number(Double(Self.defaultPreviewSize)), "cles": []]
                    if let id { params["photo"] = .number(Double(id)) }
                    let apercu = try lightroom.send("apercu", params, timeout: 120)
                    let data = Self.compact(try Self.readPreview(apercu["chemin"]?.string), maxBytes: Self.maxPreviewBytes)
                    contents = [["uri": .string(uri), "mimeType": "image/jpeg", "blob": .string(data.base64EncodedString())]]
                case "journal":
                    guard let id else { throw LightroomError.invalid("Ressource inconnue : \(uri)") }
                    let journal = try lightroom.send("journal", ["photos": [.number(Double(id))]], timeout: 60)
                    contents = [["uri": .string(uri), "mimeType": "text/markdown",
                                 "text": .string(Self.journalMarkdown(journal["photos"]?.array ?? [], date: Date()))]]
                default:
                    throw LightroomError.invalid("Ressource inconnue : \(uri)")
                }
            } else {
                throw LightroomError.invalid("Ressource inconnue : \(uri)")
            }
            return ToolResult(content: [], structured: ["contents": .array(contents)])
        } catch {
            return ToolResult(text: error.localizedDescription, isError: true)
        }
    }

    /// « developpeur://photo/12/apercu » → (12, "apercu") ; « …/active/apercu » → (nil, "apercu").
    static func photoDeRessource(_ uri: String) -> (Int?, String)? {
        let prefixe = "developpeur://photo/"
        guard uri.hasPrefix(prefixe) else { return nil }
        let parties = uri.dropFirst(prefixe.count).split(separator: "/").map(String.init)
        guard parties.count == 2 else { return nil }
        if parties[0] == "active" { return (nil, parties[1]) }
        guard let id = Int(parties[0]) else { return nil }
        return (id, parties[1])
    }
}
