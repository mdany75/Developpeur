import Foundation

/// Guide de style personnel (`remember_style`) et ressources MCP : le guide, le standard de
/// notation, l'aperçu et le journal d'une photo. La lecture d'une ressource qui touche Lightroom
/// passe par la file des outils, comme un appel d'outil (MCPServer).
extension ToolHandler {
    var styleDefinitions: [JSONValue] {
        [
            tool("remember_style",
                 "Guide de style personnel de l'utilisateur (ses goûts en retouche : profils, contraste, couleurs, peaux, noir et blanc, grain, recadrage, livraison), dans un fichier Markdown qu'il peut modifier lui-même, inclus dans l'invite retouche_pro. read = le lire avant de retoucher ; preference = y ajouter une préférence apprise en conversation (« il aime les noirs denses », « jamais de vignetage »), seulement après l'accord explicite de l'utilisateur sur la phrase exacte (confirm = true). learn = ce qu'il corrige chez Claude ; habits = ce qu'il fait seul sur ses belles photos (lecture seule, phrases à lui proposer).",
                 properties: [
                    ("read", prop("boolean", "true = lire le guide (sans rien ajouter).")),
                    ("preference", prop("string", "La préférence à ajouter, en une phrase, telle que l'utilisateur l'a approuvée.")),
                    ("category", enumProp(GuideStyle.rubriques.map(\.nom), "Rubrique : \(GuideStyle.rubriques.map { "\($0.nom) (\($0.titre.lowercased()))" }.joined(separator: ", ")).")),
                    ("confirm", prop("boolean", "true = l'utilisateur a approuvé cette phrase (exigé pour ajouter).")),
                    ("learn", prop("boolean", "true = apprendre de ses corrections (1.3.5) : ses reprises à la main depuis la dernière retouche de Claude, lues sur une série (photo_ids, selection, collection ou folder ; \(Apprentissage.maxPhotos) photos au plus) ; une règle n'est proposée que si elle revient souvent et dans le même sens, et rien n'est ajouté sans son accord.")),
                    ("habits", prop("boolean", "true = ses habitudes en chiffres (1.6), en lecture seule : les réglages de ses photos notées (rating_min, 4 ★ par défaut) d'une collection, d'un dossier (sous-dossiers compris) ou d'un appareil (camera), sans ce que Claude y a fait ; médianes par appareil et tranche d'ISO, et au plus \(Habitudes.maxPhrases) phrases à lui proposer. \(Habitudes.maxPhotos) photos au plus par appel. Long : rappeler avec les mêmes arguments tant que la réponse dit « pas fini » ; les autres outils attendent.")),
                    ("rating_min", prop("integer", "Avec habits : note minimale, de 1 à 5 (défaut 4).")),
                    ("camera", prop("string", "Avec habits : le modèle d'appareil, comme find_photos.")),
                    ("date_from", prop("string", "Avec habits : prises de vue depuis ce jour (AAAA-MM-JJ) ; refusé au-delà de 5000 photos trouvées.")),
                    ("date_to", prop("string", "Avec habits : prises de vue jusqu'à ce jour inclus (AAAA-MM-JJ).")),
                    ("collection", prop("string", "Avec learn ou habits : une collection, par son nom ou son identifiant.")),
                    ("folder", prop("string", "Avec learn ou habits : un dossier, par son chemin complet.")),
                 ] + targetProperties,
                 required: []),
        ]
    }

    func rememberStyle(_ args: Arguments) throws -> JSONValue {
        if args.bool("learn") == true { return try apprendreDesCorrections(args) }
        if args.bool("habits") == true { return try releverHabitudes(args) }
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

    /// Les reprises à la main d'une série (commande `reglages` par photo, `corrections_utilisateur`),
    /// puis les règles d'`Apprentissage`. Rien n'est écrit.
    func apprendreDesCorrections(_ args: Arguments) throws -> JSONValue {
        guard Self.serieDonnee(args) else {
            throw LightroomError.invalid("« learn » : la série à lire, photo_ids, selection = true, collection ou folder.")
        }
        let serie = try seriesPhotosSansVideos(args, maximum: Apprentissage.maxPhotos)
        guard !serie.ids.isEmpty else { throw LightroomError.invalid("Aucune photo à lire.") }
        var parPhoto: [[Apprentissage.Reprise]] = []
        avancer(0, sur: serie.ids.count, "Lecture des reprises", titre: serie.ids.count > 20 ? "reprises à la main" : nil)
        for (index, id) in serie.ids.enumerated() {
            try contexte.verifier()
            let reponse = try lightroom.send("reglages", ["photo": .number(Double(id)), "cles": ["Exposure2012"]], timeout: 30)
            let reprises = Apprentissage.reprises(reponse["corrections_utilisateur"])
            if !reprises.isEmpty { parPhoto.append(reprises) }
            avancer(index + 1, sur: serie.ids.count, "Lecture des reprises", titre: serie.ids.count > 20 ? "reprises à la main" : nil)
        }
        return Apprentissage.json(Apprentissage.regles(parPhoto), lues: serie.ids.count, reprises: parPhoto.count, videos: serie.videos)
    }

    // MARK: Habitudes

    /// Les habitudes de l'utilisateur (1.6) : la liste des photos notées (commande `habitudes
    /// liste`), puis leurs réglages par lots (`habitudes lire`), l'annulation vérifiée et la
    /// progression avancée entre deux lots. Rien n'est écrit, ni au catalogue ni au guide. Un appel
    /// plus long que 50 s passe par la réponse d'attente de FileOutils : le rappel le reprend.
    func releverHabitudes(_ args: Arguments, detaille: Bool = false) throws -> JSONValue {
        let (photos, trouvees, note) = try lireHabitudes(args)
        return Habitudes.json(Habitudes.analyser(photos, trouvees: trouvees, note: note), note: note, detaille: detaille)
    }

    func lireHabitudes(_ args: Arguments) throws -> (photos: [Habitudes.Photo], trouvees: Int, note: Int) {
        if args.has("photo_ids") || args.has("selection") {
            throw LightroomError.invalid("« habits » : une collection, un dossier (folder) ou un appareil (camera), pas photo_ids ni selection.")
        }
        var params: [String: JSONValue] = ["mode": "liste", "limite": .number(Double(Habitudes.maxPhotos))]
        var note = 4
        if args.has("rating_min") {
            guard let n = args.int("rating_min"), (1...5).contains(n) else {
                throw LightroomError.invalid("« rating_min » : une note entière de 1 à 5.")
            }
            note = n
        }
        params["note_min"] = .number(Double(note))
        if let camera = args.string("camera")?.trimmingCharacters(in: .whitespaces), !camera.isEmpty { params["appareil"] = .string(camera) }
        if let dossier = args.string("folder")?.trimmingCharacters(in: .whitespaces), !dossier.isEmpty { params["dossier"] = .string(dossier) }
        if let id = args.int("collection") { params["collection"] = .number(Double(id)) }
        else if let nom = args.string("collection")?.trimmingCharacters(in: .whitespaces), !nom.isEmpty { params["collection"] = .string(nom) }
        for (cle, cleModule) in [("date_from", "date_debut"), ("date_to", "date_fin")] {
            if let texte = args.string(cle)?.trimmingCharacters(in: .whitespaces), !texte.isEmpty { params[cleModule] = .string(texte) }
        }
        guard params["appareil"] != nil || params["dossier"] != nil || params["collection"] != nil else {
            throw LightroomError.invalid("« habits » : préciser une collection, un dossier (folder) ou un appareil (camera) ; sans cela, tout le catalogue.")
        }
        let liste = try lightroom.send("habitudes", params, timeout: Self.libraryTimeout)
        let ids = Array((liste["photos"]?.array ?? []).compactMap(\.int).prefix(Habitudes.maxPhotos))
        let trouvees = liste["total"]?.int ?? ids.count
        var photos: [Habitudes.Photo] = []
        let titre = ids.count > Habitudes.lot ? "habitudes" : nil
        avancer(0, sur: ids.count, "Lecture des réglages", titre: titre)
        for debut in stride(from: 0, to: ids.count, by: Habitudes.lot) {
            try contexte.verifier()
            let lot = Array(ids[debut..<min(debut + Habitudes.lot, ids.count)])
            let reponse = try lightroom.send("habitudes", ["mode": "lire", "photos": .array(lot.map { .number(Double($0)) }),
                                                           "cles": .array(Habitudes.cles.map(JSONValue.string))], timeout: 120)
            photos += (reponse["photos"]?.array ?? []).compactMap(Habitudes.photo)
            avancer(min(debut + Habitudes.lot, ids.count), sur: ids.count, "Lecture des réglages", titre: titre)
        }
        return (photos, trouvees, note)
    }

    /// Le relevé des seuils (`--habitudes`, développement) : la même lecture, sans plafond, avec
    /// chaque statistique et les seuils qu'elle manque. Rien n'est écrit.
    public func releveHabitudes(_ arguments: [String: JSONValue]) -> ToolResult {
        do {
            return ToolResult(text: JSONCoding.pretty(try releverHabitudes(Arguments(raw: arguments), detaille: true)))
        } catch {
            return ToolResult(text: error.localizedDescription, isError: true)
        }
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

    /// Lit une ressource : `structured` = `{contents: [...]}`, ou une erreur. Par le pont lui-même
    /// (`pont`), jamais par `LiaisonArretable` : une lecture de ressource n'est pas un appel d'outil,
    /// et l'arrêt d'un appel par la croix d'une barre de Lightroom ne la bloque pas.
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
                    let apercu = try pont.send("apercu", params, timeout: 120)
                    let data = Self.compact(try Self.readPreview(apercu["chemin"]?.string), maxBytes: Self.maxPreviewBytes)
                    contents = [["uri": .string(uri), "mimeType": "image/jpeg", "blob": .string(data.base64EncodedString())]]
                case "journal":
                    guard let id else { throw LightroomError.invalid("Ressource inconnue : \(uri)") }
                    let journal = try pont.send("journal", ["photos": [.number(Double(id))]], timeout: 60)
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
