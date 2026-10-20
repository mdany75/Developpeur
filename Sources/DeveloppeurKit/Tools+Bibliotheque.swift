import Foundation

/// La Bibliothèque : recherche, note, drapeau, libellé, textes et mots-clés, collections, copies
/// virtuelles, photo montrée dans Lightroom. Les écritures gardent une étape par photo, que
/// undo_last et revert_to_original défont (sauf la création d'une copie virtuelle ou d'une
/// collection).
extension ToolHandler {
    static let flags: [(name: String, module: String)] = [("pick", "retenue"), ("reject", "rejetee"), ("none", "aucun")]
    static let colorLabels: [(name: String, module: String)] = [
        ("red", "rouge"), ("yellow", "jaune"), ("green", "vert"), ("blue", "bleu"), ("purple", "violet"), ("none", "aucun"),
    ]
    static let fileFormats = ["RAW", "DNG", "JPG", "TIFF", "HEIC", "PSD", "VIDEO"]
    static let searchSorts: [(name: String, module: String)] = [("date", "date"), ("date_desc", "date_desc"), ("rating", "note"), ("none", "aucun")]
    /// Vues de show_photo : celles de la Bibliothèque, et l'avant/après du module Développement.
    static let showViews: [(name: String, module: String)] = [
        ("loupe", "loupe"), ("grid", "grille"), ("compare", "comparer"), ("survey", "ensemble"), ("before_after", "avant_apres"),
    ]
    static let defaultSearchLimit = 50
    static let maxSearchLimit = 500
    /// Écrire sur plusieurs centaines de photos, ou chercher dans un grand catalogue, prend du temps.
    static let libraryTimeout: TimeInterval = 180
    /// Champs IPTC que set_metadata écrit un à un : nom du paramètre, clé de Lightroom, description.
    static let iptcFields: [(name: String, key: String, description: String)] = [
        ("headline", "headline", "Gros titre (un résumé publiable)."),
        ("event", "event", "Événement (« Vacances en Gaspésie 2026 »)."),
        ("persons_shown", "personShown", "Personnes montrées, séparées par des virgules."),
        ("sublocation", "location", "Lieu précis (parc, rue, salle)."),
        ("city", "city", "Ville."),
        ("state", "stateProvince", "Province ou État."),
        ("country", "country", "Pays."),
        ("country_code", "isoCountryCode", "Code ISO du pays, 2 ou 3 lettres (CA)."),
        ("creator", "creator", "Créateur (photographe)."),
    ]
    /// Critères d'un filtre de la Bibliothèque (show_photo).
    static let filterFlags: [(name: String, module: String)] = [("pick", "retenue"), ("reject", "rejetee"), ("unflagged", "aucun")]

    /// Critères de recherche, communs à find_photos et aux collections dynamiques.
    var searchCriteriaProperties: [(String, JSONValue)] {
        [
            ("text", prop("string", "Mots cherchés dans tous les champs (nom de fichier, titre, légende, mots-clés…), tous présents.")),
            ("keyword", prop("string", "Mot-clé posé sur la photo (son nom).")),
            ("without_keywords", prop("boolean", "true = seulement les photos sans aucun mot-clé.")),
            ("rating_min", prop("integer", "Note minimale (0 à 5).")),
            ("rating_max", prop("integer", "Note maximale (0 à 5).")),
            ("flag", enumProp(Self.flags.map(\.name), "Drapeau : pick = retenue, reject = rejetée, none = sans drapeau.")),
            ("color_label", enumProp(Self.colorLabels.map(\.name), "Libellé de couleur (none = sans libellé).")),
            ("camera", prop("string", "Modèle d'appareil exact, tel que list_selection le donne (par exemple « X-H2S »).")),
            ("lens", prop("string", "Objectif exact, tel que list_selection le donne.")),
            ("iso_min", prop("integer", "Sensibilité minimale.")),
            ("iso_max", prop("integer", "Sensibilité maximale.")),
            ("file_format", enumProp(Self.fileFormats, "Format du fichier.")),
            ("last_days", prop("integer", "Prises de vue des N derniers jours.")),
            ("edited_by_claude", prop("boolean", "true = seulement les photos retouchées par Claude ; false = seulement les autres.")),
        ]
    }

    var iptcProperty: JSONValue {
        objectProp("Champs IPTC à écrire (texte vide = l'effacer) ; undo_last remet ceux d'avant.",
                   Dictionary(uniqueKeysWithValues: Self.iptcFields.map { ($0.name, prop("string", $0.description)) }))
    }

    var libraryDefinitions: [JSONValue] {
        let search = searchCriteriaProperties
        return [
            tool("find_photos",
                 "Cherche des photos dans tout le catalogue Lightroom (pas seulement la sélection) : texte, mot-clé, note, drapeau, libellé de couleur, appareil, objectif, ISO, format, dates, dossier, collection, retouchées ou non par Claude, exportées ou jamais. Les critères se cumulent. Renvoie le nombre total et une page de photos (id, fichier, prise de vue, note, drapeau, libellé, pile de Lightroom), triées par date de prise de vue. Les identifiants servent aux autres outils (photo_ids).",
                 properties: search + [
                    ("date_from", prop("string", "Prises de vue depuis ce jour inclus (AAAA-MM-JJ).")),
                    ("date_to", prop("string", "Prises de vue jusqu'à ce jour inclus (AAAA-MM-JJ).")),
                    ("folder", prop("string", "Dossier, par son chemin complet (sous-dossiers compris, sauf include_subfolders = false).")),
                    ("include_subfolders", prop("boolean", "Avec folder : chercher aussi dans les sous-dossiers (défaut : oui).")),
                    ("collection", prop("string", "Collection, par son nom, « Ensemble > Nom » ou son identifiant (manage_collections, action list).")),
                    ("virtual_copies", enumProp(["only", "exclude"], "only = seulement les copies virtuelles ; exclude = sans elles.")),
                    ("exported", prop("boolean", "false = seulement les photos jamais exportées (retenues à exporter : flag pick et exported false) ; true = seulement celles déjà exportées. Avec un autre critère. D'après Lightroom ; un aperçu de Claude ne compte pas comme une exportation.")),
                    ("sort", enumProp(Self.searchSorts.map(\.name), "Ordre : date (défaut), date_desc, rating (meilleures d'abord) ou none.")),
                    ("include_keywords", prop("boolean", "true = donner aussi les mots-clés de chaque photo.")),
                    ("limit", prop("integer", "Photos par page (défaut \(Self.defaultSearchLimit), maximum \(Self.maxSearchLimit)).")),
                    ("offset", prop("integer", "Photos à sauter (page suivante : offset + limit).")),
                 ],
                 required: []),
            tool("set_metadata",
                 "Classe des photos dans la Bibliothèque : note, drapeau, libellé de couleur, titre, légende, droits d'auteur, texte alternatif et description longue (accessibilité : rédigés d'après view_photo, ils partent à l'exportation), champs IPTC (lieu, événement, personnes), position GPS (donnée, ou celle d'une photo de téléphone prise au même moment : gps_from), mots-clés à ajouter ou retirer, paramètre prédéfini de métadonnées. Un mot-clé se donne par son nom ou son chemin (« Lieux > Canada > Montréal ») : un mot-clé existant est réutilisé, un nouveau est créé à cet endroit (un mot de Vision reçoit son nom anglais en synonyme) ; un nom ambigu demande le chemin (list_keywords). Une étape « Claude · <step_name> » par photo, que undo_last et revert_to_original défont. Trier une série est une écriture : en mode « Proposer d'abord », présenter les changements, puis rappeler avec confirm.",
                 properties: [
                    ("rating", prop("integer", "Note de 0 (sans note) à 5 (5 : à la demande de l'utilisateur ; des notes proposées passent par propose_ratings).")),
                    ("flag", enumProp(Self.flags.map(\.name), "Drapeau : pick = retenue, reject = rejetée, none = l'enlever.")),
                    ("color_label", enumProp(Self.colorLabels.map(\.name), "Libellé de couleur (none = l'enlever).")),
                    ("title", prop("string", "Titre (texte vide = l'effacer).")),
                    ("caption", prop("string", "Légende (texte vide = l'effacer).")),
                    ("copyright", prop("string", "Droits d'auteur (texte vide = les effacer).")),
                    ("metadata_preset", prop("string", "Paramètre prédéfini de métadonnées de l'utilisateur (droits d'auteur, créateur, contact…), par son nom (export_photos avec list = true) ; undo_last remet les champs d'avant. Pas dans le même appel que iptc.")),
                    ("alt_text", prop("string", "Texte alternatif : ce que montre la photo, en une ou deux phrases (texte vide = l'effacer).")),
                    ("extended_description", prop("string", "Description longue (accessibilité), quand le texte alternatif ne suffit pas.")),
                    ("iptc", iptcProperty),
                    ("gps", objectProp("Position à poser (degrés décimaux) ; retirée à l'exportation par défaut (export_photos, remove_location).",
                                       ["latitude": prop("number", "De −90 à 90."), "longitude": prop("number", "De −180 à 180."),
                                        "altitude": prop("number", "Mètres."), "direction": prop("number", "Direction de la prise de vue, de 0 à 360 degrés.")],
                                       required: ["latitude", "longitude"])),
                    ("gps_from", objectProp("Géolocaliser d'après des photos qui ont une position (le téléphone, à la même séance) : chaque photo prend celle de la référence prise au plus près dans le temps.",
                                            ["photo_ids": listProp("integer", "Photos de référence (find_photos : même jour, appareil du téléphone)."),
                                             "max_gap_minutes": prop("integer", "Écart maximal (défaut 30 min) : au-delà, la photo garde sa position."),
                                             "camera_clock_offset_minutes": prop("integer", "Minutes à ajouter à l'heure de l'appareil pour retrouver celle du téléphone (horloge restée à l'heure d'hiver : 60).")],
                                            required: ["photo_ids"])),
                    ("remove_gps", prop("boolean", "true = retirer la position.")),
                    ("add_keywords", listProp("string", "Mots-clés à ajouter, par nom ou chemin « Parent > Enfant ».")),
                    ("remove_keywords", listProp("string", "Mots-clés à retirer de ces photos, par nom ou chemin.")),
                 ] + writeProperties + targetProperties,
                 required: []),
            tool("list_keywords",
                 "Liste les mots-clés du catalogue, avec leur chemin dans la hiérarchie et leur nombre de photos : pour réutiliser ceux qui existent avant d'en créer.",
                 properties: [
                    ("query", prop("string", "Texte à chercher dans le chemin du mot-clé.")),
                    ("limit", prop("integer", "Nombre maximal de mots-clés (défaut 200).")),
                 ],
                 required: []),
            tool("manage_collections",
                 "Collections et mots-clés de Lightroom : list (toutes les collections, avec leur identifiant, leur ensemble et leur nombre de photos) ; create (dans l'ensemble « Claude » par défaut ; avec photo_ids ou selection, ces photos y sont ajoutées ; avec search, une collection dynamique) ; add et remove (des photos d'une collection ordinaire) ; rename, move (vers collection_set) et edit_search (critères d'une collection dynamique) ; edit_keyword (renommer un mot-clé, new_name, ou changer ses synonymes). Ajouter et retirer gardent une étape par photo, que undo_last défait ; une collection créée reste ; renommer, déplacer et changer des critères ne s'annulent pas par undo_last (la réponse donne l'état d'avant). Rien n'est jamais supprimé. Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [
                    ("action", enumProp(["list", "create", "add", "remove", "rename", "move", "edit_search", "edit_keyword"], "Ce qu'il faut faire.")),
                    ("name", prop("string", "Pour create : le nom de la collection.")),
                    ("new_name", prop("string", "Pour rename et edit_keyword : le nouveau nom.")),
                    ("collection_set", prop("string", "Pour create et move : l'ensemble de collections, par son chemin « A > B », créé au besoin (défaut « Claude » ; texte vide = à la racine).")),
                    ("collection", prop("string", "Pour add, remove, rename, move et edit_search : la collection, par son nom, « Ensemble > Nom » ou son identifiant.")),
                    ("search", objectProp("Pour create et edit_search : les critères d'une collection dynamique (ceux de find_photos que Lightroom cherche lui-même).",
                                          Dictionary(uniqueKeysWithValues: search))),
                    ("keyword", prop("string", "Pour edit_keyword : le mot-clé, par nom ou chemin.")),
                    ("synonyms", listProp("string", "Pour edit_keyword : ses synonymes (remplacent ceux d'avant ; liste vide = aucun).")),
                 ] + writeProperties + targetProperties,
                 required: ["action"]),
            tool("create_virtual_copy",
                 "Crée une copie virtuelle nommée de chaque photo visée, pour essayer une interprétation sans toucher à l'original (ou en comparer plusieurs). Renvoie l'identifiant de chaque copie. Ne s'annule pas par undo_last : la copie se supprime dans Lightroom. Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [
                    ("name", prop("string", "Nom de la copie (défaut « Claude »), affiché dans Lightroom à côté du nom du fichier.")),
                    ("show", prop("boolean", "true = sélectionner les copies dans Lightroom ; sinon la sélection d'avant est remise.")),
                    ("confirm", prop("boolean", "true = l'utilisateur a approuvé (exigé en mode « Proposer d'abord »).")),
                 ] + targetProperties,
                 required: []),
            tool("show_photo",
                 "Montre des photos dans Lightroom : les sélectionne et les affiche dans la Bibliothèque (loupe, grille, comparaison de deux photos, ensemble de plusieurs) ou le module Développement, avant/après compris (pour finir une retouche en la montrant dans Lightroom). L'« Avant » de Lightroom est l'état à l'importation, pas l'état d'avant Claude (view_photo avec compare = before_claude le montre). Une photo hors du film fixe fait afficher son dossier. Sans photo_ids : un dossier ou une collection en grille, avec un filtre de la Bibliothèque (le résultat d'un tri : filter flag pick, rating_min) ; restore_filter remet le filtre d'avant Claude (à faire avant de retoucher une photo que le filtre cache). Ne change rien aux photos.",
                 properties: [
                    ("photo_ids", listProp("integer", "Photos à montrer (champ « id »).")),
                    ("folder", prop("string", "Sans photo_ids : le dossier à afficher, par son chemin complet.")),
                    ("collection", prop("string", "Sans photo_ids : la collection à afficher, par son nom, « Ensemble > Nom » ou son identifiant.")),
                    ("filter", objectProp("Filtre de la Bibliothèque à poser (attributs) ; {} = filtres coupés.",
                                          ["flag": enumProp(Self.filterFlags.map(\.name), "Drapeau."),
                                           "rating_min": prop("integer", "Note minimale (0 à 5)."),
                                           "color_label": enumProp(Self.colorLabels.map(\.name), "Libellé de couleur (none = sans libellé)."),
                                           "text": prop("string", "Texte cherché dans tous les champs.")])),
                    ("filter_preset", prop("string", "Paramètre prédéfini de filtre de l'utilisateur, par son nom.")),
                    ("restore_filter", prop("boolean", "true = remettre le filtre d'avant le premier changement de Claude.")),
                    ("module", enumProp(["library", "develop"], "Module de Lightroom (défaut library).")),
                    ("view", enumProp(Self.showViews.map(\.name), "loupe, grid, compare (deux photos), survey (plusieurs côte à côte) : vues de la Bibliothèque (défaut : loupe pour une photo, grille pour plusieurs) ; before_after : avant/après dans le module Développement.")),
                 ],
                 required: []),
        ]
    }

    // MARK: Exécution

    func callLibrary(_ name: String, _ args: Arguments) throws -> ToolResult? {
        switch name {
        case "find_photos": return json(try findPhotos(args))
        case "set_metadata": return json(try setMetadata(args))
        case "list_keywords": return json(try listKeywords(args))
        case "manage_collections": return json(try manageCollections(args))
        case "create_virtual_copy": return json(try createVirtualCopy(args))
        case "show_photo": return json(try showPhoto(args))
        default: return nil
        }
    }

    /// Une valeur énumérée, traduite pour le module.
    private func enumValue(_ args: Arguments, _ key: String, _ values: [(name: String, module: String)]) throws -> JSONValue? {
        guard let text = args.string(key) else {
            if args.has(key) { throw LightroomError.invalid("« \(key) » doit être un texte.") }
            return nil
        }
        guard let value = values.first(where: { $0.name == text }) else {
            throw LightroomError.invalid("« \(key) » invalide : \(text). Valeurs possibles : \(values.map(\.name).joined(separator: ", ")).")
        }
        return .string(value.module)
    }

    private func intValue(_ args: Arguments, _ key: String, range: ClosedRange<Int>? = nil) throws -> JSONValue? {
        guard args.has(key) else { return nil }
        guard let value = args.int(key) else { throw LightroomError.invalid("« \(key) » doit être un nombre entier.") }
        if let range, !range.contains(value) {
            throw LightroomError.invalid("« \(key) » doit être entre \(range.lowerBound) et \(range.upperBound).")
        }
        return .number(Double(value))
    }

    /// Les critères de recherche, tels que les attend le module (commande « chercher »).
    func searchCriteria(_ args: Arguments) throws -> [String: JSONValue] {
        var criteria: [String: JSONValue] = [:]
        for (key, moduleKey) in [("text", "texte"), ("keyword", "mots_cles"), ("camera", "appareil"), ("lens", "objectif")] {
            if let text = args.string(key)?.trimmingCharacters(in: .whitespaces), !text.isEmpty { criteria[moduleKey] = .string(text) }
        }
        for (key, moduleKey, range) in [("rating_min", "note_min", 0...5), ("rating_max", "note_max", 0...5),
                                        ("iso_min", "iso_min", 0...10_000_000), ("iso_max", "iso_max", 0...10_000_000),
                                        ("last_days", "depuis_jours", 1...100_000)] {
            if let value = try intValue(args, key, range: range) { criteria[moduleKey] = value }
        }
        if let flag = try enumValue(args, "flag", Self.flags) { criteria["drapeau"] = flag }
        if let label = try enumValue(args, "color_label", Self.colorLabels) { criteria["libelle"] = label }
        if let format = args.string("file_format") {
            guard Self.fileFormats.contains(format.uppercased()) else {
                throw LightroomError.invalid("« file_format » invalide : \(format). Valeurs possibles : \(Self.fileFormats.joined(separator: ", ")).")
            }
            criteria["format"] = .string(format.uppercased())
        }
        if args.bool("without_keywords") == true { criteria["sans_mots_cles"] = true }
        if let edited = args.bool("edited_by_claude") { criteria["retouchee_par_claude"] = .bool(edited) }
        return criteria
    }

    private func findPhotos(_ args: Arguments) throws -> JSONValue {
        var params = try searchCriteria(args)
        for (key, moduleKey) in [("date_from", "date_debut"), ("date_to", "date_fin"), ("folder", "dossier"), ("collection", "collection")] {
            if let text = args.string(key)?.trimmingCharacters(in: .whitespaces), !text.isEmpty { params[moduleKey] = .string(text) }
            else if key == "collection", let id = args.int(key) { params[moduleKey] = .number(Double(id)) }
        }
        if let subfolders = args.bool("include_subfolders") { params["sous_dossiers"] = .bool(subfolders) }
        if let copies = args.string("virtual_copies") {
            guard let value = ["only": "seulement", "exclude": "exclure"][copies] else {
                throw LightroomError.invalid("« virtual_copies » invalide : only ou exclude.")
            }
            params["copies_virtuelles"] = .string(value)
        }
        if let sort = try enumValue(args, "sort", Self.searchSorts) { params["tri"] = sort }
        if args.bool("include_keywords") == true { params["mots_cles_details"] = true }
        if let exported = args.bool("exported") { params["exportee"] = .bool(exported) }
        if params.isEmpty { throw LightroomError.invalid("Aucun critère de recherche.") }
        let limit = try intValue(args, "limit", range: 1...Int.max)?.int ?? Self.defaultSearchLimit
        params["limite"] = .number(Double(min(limit, Self.maxSearchLimit)))
        if let offset = try intValue(args, "offset", range: 0...Int.max) { params["decalage"] = offset }
        return try lightroom.send("chercher", params, timeout: Self.libraryTimeout)
    }

    private func setMetadata(_ args: Arguments) throws -> JSONValue {
        var params = writeParameters(args, defaultStep: "classement").merging(try targets(args)) { $1 }
        var changes = 0
        if let rating = try intValue(args, "rating", range: 0...5) { params["note"] = rating; changes += 1 }
        if let flag = try enumValue(args, "flag", Self.flags) { params["drapeau"] = flag; changes += 1 }
        if let label = try enumValue(args, "color_label", Self.colorLabels) { params["libelle"] = label; changes += 1 }
        for (key, moduleKey) in [("title", "titre"), ("caption", "legende"), ("copyright", "droits")] where args.has(key) {
            guard let text = args.string(key) else { throw LightroomError.invalid("« \(key) » doit être un texte.") }
            params[moduleKey] = .string(text)
            changes += 1
        }
        for (key, moduleKey) in [("add_keywords", "ajouter"), ("remove_keywords", "retirer")] where args.has(key) {
            let words = try keywordList(args, key)
            if !words.isEmpty { params[moduleKey] = .array(words.map(JSONValue.string)); changes += 1 }
        }
        // Un mot-clé créé d'après Vision reçoit son nom anglais en synonyme.
        var synonymes: [String: JSONValue] = [:]
        for word in (params["ajouter"]?.array ?? []).compactMap(\.string) {
            let dernier = word.split(whereSeparator: { ">›|".contains($0) }).last.map(String.init) ?? word
            let anglais = MotsClesVision.synonymesAnglais(dernier)
            if !anglais.isEmpty { synonymes[word] = .array(anglais.map(JSONValue.string)) }
        }
        if !synonymes.isEmpty { params["synonymes"] = .object(synonymes) }
        if let preset = args.string("metadata_preset")?.trimmingCharacters(in: .whitespaces), !preset.isEmpty {
            params["preset_metadonnees"] = .string(preset)
            changes += 1
        }
        var iptc: [String: JSONValue] = [:]
        for (key, moduleKey) in [("alt_text", "altTextAccessibility"), ("extended_description", "extDescrAccessibility")] where args.has(key) {
            guard let text = args.string(key) else { throw LightroomError.invalid("« \(key) » doit être un texte.") }
            iptc[moduleKey] = .string(text)
        }
        if let fields = args.object("iptc") {
            for (name, value) in fields {
                guard let field = Self.iptcFields.first(where: { $0.name == name }) else {
                    throw LightroomError.invalid("Champ IPTC inconnu : \(name). Champs : \(Self.iptcFields.map(\.name).joined(separator: ", ")).")
                }
                guard let text = value.string else { throw LightroomError.invalid("« iptc.\(name) » doit être un texte.") }
                iptc[field.key] = .string(text)
            }
        }
        if !iptc.isEmpty { params["iptc"] = .object(iptc); changes += 1 }
        let gpsDemandes = ["gps", "gps_from", "remove_gps"].filter { args.has($0) && args.bool($0) != false }
        guard gpsDemandes.count <= 1 else { throw LightroomError.invalid("Une seule demande de position : gps, gps_from ou remove_gps.") }
        if let gps = args.object("gps") {
            let g = Arguments(raw: gps)
            guard let lat = g.double("latitude"), let lon = g.double("longitude") else {
                throw LightroomError.invalid("« gps » : latitude et longitude en degrés décimaux.")
            }
            var position: [String: JSONValue] = ["latitude": .number(lat), "longitude": .number(lon)]
            if let altitude = g.double("altitude") { position["altitude"] = .number(altitude) }
            if let direction = g.double("direction") { position["direction"] = .number(direction) }
            params["gps"] = .object(position)
            changes += 1
        } else if let from = args.object("gps_from") {
            let g = Arguments(raw: from)
            guard let ids = try g.intList("photo_ids"), !ids.isEmpty else { throw LightroomError.invalid("« gps_from.photo_ids » : les photos de référence.") }
            var depuis: [String: JSONValue] = ["photos": .array(ids.map { .number(Double($0)) })]
            if let ecart = g.int("max_gap_minutes") {
                guard ecart > 0 else { throw LightroomError.invalid("« max_gap_minutes » doit être positif.") }
                depuis["ecart_max"] = .number(Double(ecart))
            }
            if let decalage = g.int("camera_clock_offset_minutes") { depuis["decalage"] = .number(Double(decalage)) }
            params["gps_depuis"] = .object(depuis)
            changes += 1
        } else if args.bool("remove_gps") == true {
            params["gps"] = "aucune"
            changes += 1
        }
        guard changes > 0 else {
            throw LightroomError.invalid("Rien à changer : rating, flag, color_label, title, caption, copyright, alt_text, extended_description, iptc, gps, gps_from, remove_gps, add_keywords, remove_keywords ou metadata_preset.")
        }
        return Self.withLabels(try lightroom.send("metadonnees", params, timeout: Self.libraryTimeout))
    }

    private func keywordList(_ args: Arguments, _ key: String, allowEmpty: Bool = false) throws -> [String] {
        if let single = args.string(key) { return [single] }
        guard let items = args.array(key) else { throw LightroomError.invalid("« \(key) » doit être une liste de mots-clés.") }
        if allowEmpty, items.isEmpty { return [] }
        return try items.map { item in
            guard let text = item.string?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
                throw LightroomError.invalid("« \(key) » contient un mot-clé vide ou invalide.")
            }
            return text
        }
    }

    private func listKeywords(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = ["limite": .number(Double(max(1, args.int("limit") ?? 200)))]
        if let query = args.string("query"), !query.isEmpty { params["filtre"] = .string(query) }
        return try lightroom.send("motsCles", params, timeout: 60)
    }

    private func manageCollections(_ args: Arguments) throws -> JSONValue {
        let actions = ["list": "lister", "create": "creer", "add": "ajouter", "remove": "retirer", "rename": "renommer",
                       "move": "deplacer", "edit_search": "criteres", "edit_keyword": "mot_cle"]
        guard let actionName = args.string("action"), let action = actions[actionName] else {
            throw LightroomError.invalid("« action » : list, create, add, remove, rename, move, edit_search ou edit_keyword.")
        }
        if action == "lister" { return try lightroom.send("collections", ["action": "lister"], timeout: 60) }
        var params = writeParameters(args, defaultStep: "collection")
        params["action"] = .string(action)
        switch action {
        case "creer":
            guard let name = args.string("name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                throw LightroomError.invalid("« name » : le nom de la collection à créer.")
            }
            params["nom"] = .string(name)
            if let set = args.string("collection_set") { params["ensemble"] = .string(set.trimmingCharacters(in: .whitespaces)) }
            if let search = args.object("search") {
                let criteria = try searchCriteria(Arguments(raw: search))
                guard !criteria.isEmpty else { throw LightroomError.invalid("« search » ne contient aucun critère.") }
                params["recherche"] = .object(criteria)
            }
            // Créée vide, sauf si des photos sont nommées : pas la photo active par défaut.
            if args.has("photo_ids") || args.bool("selection") == true {
                params.merge(try targets(args)) { $1 }
            }
        case "mot_cle":
            guard let keyword = args.string("keyword")?.trimmingCharacters(in: .whitespaces), !keyword.isEmpty else {
                throw LightroomError.invalid("« keyword » : le mot-clé à changer.")
            }
            params["mot_cle"] = .string(keyword)
            if let name = args.string("new_name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty { params["nouveau_nom"] = .string(name) }
            if args.has("synonyms") { params["synonymes"] = .array(try keywordList(args, "synonyms", allowEmpty: true).map(JSONValue.string)) }
            guard params["nouveau_nom"] != nil || params["synonymes"] != nil else {
                throw LightroomError.invalid("edit_keyword : new_name ou synonyms.")
            }
        case "renommer", "deplacer", "criteres":
            params["collection"] = try collectionDesignation(args)
            if action == "renommer" {
                guard let name = args.string("new_name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                    throw LightroomError.invalid("« new_name » : le nouveau nom de la collection.")
                }
                params["nouveau_nom"] = .string(name)
            } else if action == "deplacer" {
                if let set = args.string("collection_set") { params["ensemble"] = .string(set.trimmingCharacters(in: .whitespaces)) }
            } else {
                guard let search = args.object("search") else { throw LightroomError.invalid("« search » : les nouveaux critères.") }
                let criteria = try searchCriteria(Arguments(raw: search))
                guard !criteria.isEmpty else { throw LightroomError.invalid("« search » ne contient aucun critère.") }
                params["recherche"] = .object(criteria)
            }
        default:
            params["collection"] = try collectionDesignation(args)
            params.merge(try targets(args)) { $1 }
        }
        return Self.withLabels(try lightroom.send("collections", params, timeout: Self.libraryTimeout))
    }

    private func collectionDesignation(_ args: Arguments) throws -> JSONValue {
        if let id = args.int("collection") { return .number(Double(id)) }
        if let name = args.string("collection")?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return .string(name) }
        throw LightroomError.invalid("« collection » : la collection, par son nom ou son identifiant.")
    }

    private func createVirtualCopy(_ args: Arguments) throws -> JSONValue {
        var params = try targets(args)
        if let name = args.string("name")?.trimmingCharacters(in: .whitespaces), !name.isEmpty { params["nom"] = .string(String(name.prefix(60))) }
        params["afficher"] = .bool(args.bool("show") ?? false)
        params["confirme"] = .bool(args.bool("confirm") ?? false)
        return try lightroom.send("copieVirtuelle", params, timeout: 60)
    }

    private func showPhoto(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = [:]
        let filtres = ["filter", "filter_preset", "restore_filter"].filter { args.has($0) && args.bool($0) != false }
        guard filtres.count <= 1 else { throw LightroomError.invalid("Un seul de filter, filter_preset ou restore_filter.") }
        if let filter = args.object("filter") {
            if filter.isEmpty {
                params["filtre"] = "aucun"
            } else {
                let f = Arguments(raw: filter)
                var criteres: [String: JSONValue] = [:]
                if let flag = try enumValue(f, "flag", Self.filterFlags) { criteres["drapeau"] = flag }
                if let note = try intValue(f, "rating_min", range: 0...5) { criteres["note_min"] = note }
                if let label = try enumValue(f, "color_label", Self.colorLabels) { criteres["libelle"] = label }
                if let text = f.string("text"), !text.isEmpty { criteres["texte"] = .string(text) }
                params["filtre"] = .object(criteres)
            }
        } else if let preset = args.string("filter_preset")?.trimmingCharacters(in: .whitespaces), !preset.isEmpty {
            params["filtre_preset"] = .string(preset)
        } else if args.bool("restore_filter") == true {
            params["remettre_filtre"] = true
        }
        if let ids = try args.intList("photo_ids"), !ids.isEmpty {
            params["photos"] = .array(ids.map { .number(Double($0)) })
        } else {
            if let folder = args.string("folder")?.trimmingCharacters(in: .whitespaces), !folder.isEmpty {
                params["source_dossier"] = .string(folder)
            } else if args.has("collection") {
                params["source_collection"] = try collectionDesignation(args)
            }
            guard params["source_dossier"] != nil || params["source_collection"] != nil || !filtres.isEmpty else {
                throw LightroomError.invalid("« photo_ids » : les photos à montrer ; ou folder, collection, filter, filter_preset, restore_filter.")
            }
        }
        if let module = args.string("module") {
            guard let value = ["library": "bibliotheque", "develop": "developpement"][module] else {
                throw LightroomError.invalid("« module » : library ou develop.")
            }
            params["module"] = .string(value)
        }
        if let view = args.string("view") {
            guard let value = Self.showViews.first(where: { $0.name == view })?.module else {
                throw LightroomError.invalid("« view » : \(Self.showViews.map(\.name).joined(separator: ", ")).")
            }
            params["vue"] = .string(value)
        }
        return try lightroom.send("montrer", params, timeout: 30)
    }
}
