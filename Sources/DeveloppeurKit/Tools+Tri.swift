import CoreGraphics
import Foundation

/// Trier une séance : `cull_photos` (photos floues ou ratées, rafales et la meilleure de chacune,
/// ordre de lecture, plafonds de note mesurés, proposition de rejet) et `contact_sheet` (planche
/// contact numérotée, de quoi juger l'Impact d'une sortie sur 20 à 30 vignettes). Les deux
/// travaillent sur les vignettes du cache d'aperçus de Lightroom (commande vignettes), sans
/// exporter chaque photo ; une photo sans vignette est rendue comme un aperçu.
extension ToolHandler {
    static let maxCulledPhotos = 500
    static let thumbnailsPerCommand = 25
    static let cullThumbnailSize = Detail.side
    /// Une planche de 20 à 30 vignettes : le standard de notation y cherche les photos vues en premier.
    static let maxContactSheet = 30
    static let contactSheetThumbnailSize = 512
    /// Une vignette plus petite que ce grand côté ne suffit pas aux seuils de netteté (relevés à 1024 px).
    static let minimumCullSide = 900
    /// La netteté d'une vignette du cache, ramenée à celle d'un aperçu exporté, sur laquelle les
    /// seuils ont été relevés : relevé le 17 octobre 2026 sur les six photos d'essai (aperçus du
    /// cache de 1720 px, réduits à 1024), de 0,84 à 0,93 fois la netteté de l'aperçu exporté
    /// (moyenne 0,88) ; le bruit est le même (0,83 à 1,15 fois).
    static let thumbnailSharpnessFactor = 1.13
    /// Photos mesurées en même temps (Vision, netteté).
    static let parallelMeasures = 2

    var cullDefinitions: [JSONValue] {
        let series: [(String, JSONValue)] = [
            ("photo_ids", listProp("integer", "Photos à trier (champ « id »), dans l'ordre voulu.")),
            ("selection", prop("boolean", "true = les photos sélectionnées dans Lightroom (toutes celles du film fixe si rien n'est sélectionné).")),
            ("collection", prop("string", "Une collection entière, par son nom, « Ensemble > Nom » ou son identifiant (manage_collections, action list), triée par date de prise de vue.")),
            ("folder", prop("string", "Un dossier entier, par son chemin complet (sans ses sous-dossiers), trié par date de prise de vue.")),
        ]
        return [
            tool("cull_photos",
                 "Trie une séance (jusqu'à \(Self.maxCulledPhotos) photos) sur les vignettes du cache d'aperçus de Lightroom, sans rien changer : photos floues ou ratées (netteté, mise au point manquée au point AF lu dans les RAW et JPEG Fujifilm, yeux fermés ou plissés, presque noires, brûlées), rafales (photos consécutives semblables, prises coup sur coup) et piles de Lightroom, avec la meilleure de chacune, ordre de lecture (classement : netteté et note esthétique, pas une note), plafonds de note mesurés (plafonds : le plancher technique du standard de notation, qui borne la note sans la donner ; propose_ratings les fait respecter) et proposition de rejet (flag reject, pour un défaut majeur). Aucune étoile : elles se proposent par propose_ratings, après avoir regardé les photos. Présenter les rejets à l'utilisateur, puis, après son accord, les poser avec set_metadata ; undo_last les défait. Avec keywords, des mots-clés proposés par Vision, en français. Long sur une grande séance : la progression se suit photo par photo.",
                 properties: series + [
                    ("keywords", prop("boolean", "true = proposer aussi des mots-clés par photo (Vision, traduits en français), à poser avec set_metadata après accord.")),
                    ("details", prop("boolean", "true = une ligne de mesures par photo (ordre de lecture, plafond, défauts, point AF, mots-clés).")),
                 ],
                 required: []),
            tool("contact_sheet",
                 "Planche contact : une seule image de \(Self.maxContactSheet) vignettes au plus, numérotées, avec le nom de chaque fichier, pour voir une série d'un coup d'œil (choisir, comparer, harmoniser, juger l'Impact sur 20 à 30 vignettes) en bien moins de jetons qu'une image par photo. Vignettes du cache d'aperçus de Lightroom (elles peuvent dater d'avant la dernière retouche : la netteté et la finition se jugent par view_photo) ; légende : numéro, id, fichier, note, drapeau (au-delà de 20 vignettes, les noms se lisent mal sur l'image : la légende fait foi). Pour la suite d'une sélection ou d'une collection : offset, et les numéros continuent d'une planche à l'autre.",
                 properties: series + [
                    ("offset", prop("integer", "Avec selection, collection ou folder : photos à sauter (planche suivante : offset + \(Self.maxContactSheet)).")),
                    ("columns", prop("integer", "Colonnes (défaut : 2 jusqu'à 4 photos, 3 jusqu'à 9, 4 jusqu'à 16, 5 jusqu'à 25, puis 6).")),
                 ],
                 required: []),
        ]
    }

    func callCull(_ name: String, _ args: Arguments) throws -> ToolResult? {
        switch name {
        case "cull_photos": return json(try cullPhotos(args))
        case "contact_sheet": return try contactSheet(args)
        default: return nil
        }
    }

    /// Les photos d'une série : photo_ids, la sélection de Lightroom ou une collection, dans
    /// l'ordre de Lightroom ; au plus `maximum` après `decalage`. Renvoie aussi le total.
    func seriesPhotos(_ args: Arguments, maximum: Int, decalage: Int = 0) throws -> (ids: [Int], total: Int) {
        if let ids = try args.intList("photo_ids"), !ids.isEmpty {
            guard ids.count <= maximum else { throw LightroomError.invalid("Au plus \(maximum) photos par appel.") }
            return (ids, ids.count)
        }
        var reponse: JSONValue
        if args.has("collection") || args.has("folder") {
            var params: [String: JSONValue] = ["limite": .number(Double(maximum)), "tri": "date", "decalage": .number(Double(decalage))]
            if let dossier = args.string("folder")?.trimmingCharacters(in: .whitespaces), !dossier.isEmpty {
                params["dossier"] = .string(dossier)
                params["sous_dossiers"] = false
            } else if let id = args.int("collection") { params["collection"] = .number(Double(id)) }
            else if let nom = args.string("collection")?.trimmingCharacters(in: .whitespaces), !nom.isEmpty { params["collection"] = .string(nom) }
            else { throw LightroomError.invalid("« collection » : son nom, « Ensemble > Nom » ou son identifiant ; « folder » : le chemin complet du dossier.") }
            reponse = try lightroom.send("chercher", params, timeout: Self.libraryTimeout)
            let ids = (reponse["photos"]?.array ?? []).compactMap { $0["id"]?.int }
            return (ids, reponse["total"]?.int ?? ids.count)
        }
        guard args.bool("selection") == true else {
            throw LightroomError.invalid("Photos à traiter : photo_ids, selection = true, collection ou folder.")
        }
        reponse = try lightroom.send("selection", ["limite": .number(Double(Self.maxSelectionLimit))], timeout: 60)
        let toutes = (reponse["photos"]?.array ?? []).compactMap { $0["id"]?.int }
        let total = reponse["total"]?.int ?? toutes.count
        guard decalage > 0 || total <= maximum else {
            throw LightroomError.invalid("\(total) photos sélectionnées : au plus \(maximum) par appel. Réduire la sélection ou donner photo_ids.")
        }
        return (Array(toutes.dropFirst(decalage).prefix(maximum)), total)
    }

    /// Une photo de la série, avec sa vignette (ou nil) et ce qu'en dit le module.
    struct Vignette {
        var id: Int
        var description: JSONValue
        var image: CGImage?
        var depuisCache: Bool
        var erreur: String?
    }

    /// Vignettes des photos, par lots de `thumbnailsPerCommand` ; une photo sans vignette assez
    /// grande est rendue comme un aperçu (`repli`). `traiter` reçoit chaque lot ; l'annulation se
    /// vérifie entre deux lots, la progression avance à chacun.
    func thumbnails(_ ids: [Int], taille: Int, minimum: Int, message: String,
                    traiter: ([Vignette]) throws -> Void) throws {
        var faites = 0
        avancer(0, sur: ids.count, message, titre: ids.count > Self.thumbnailsPerCommand ? message : nil)
        for debut in stride(from: 0, to: ids.count, by: Self.thumbnailsPerCommand) {
            try contexte.verifier()
            let lot = Array(ids[debut..<min(debut + Self.thumbnailsPerCommand, ids.count)])
            let reponse = try lightroom.send("vignettes", ["photos": .array(lot.map { .number(Double($0)) }), "taille": .number(Double(taille))],
                                             timeout: 120)
            var vignettes: [Vignette] = []
            for item in reponse["photos"]?.array ?? [] {
                guard let id = item["id"]?.int else { continue }
                var vignette = Vignette(id: id, description: item, image: nil, depuisCache: true, erreur: item["erreur"]?.string)
                if let chemin = item["vignette"]?.string, let data = try? Self.readPreview(chemin), let image = PreviewImages.image(data),
                   max(image.width, image.height) >= minimum {
                    vignette.image = image
                }
                vignettes.append(vignette)
            }
            for index in vignettes.indices where vignettes[index].image == nil {
                try contexte.verifier()
                // Repli : un aperçu exporté, comme analyze_photos.
                do {
                    let apercu = try lightroom.send("apercu", ["photo": .number(Double(vignettes[index].id)), "taille": .number(Double(taille)), "cles": []],
                                                    timeout: 120)
                    let data = try Self.readPreview(apercu["chemin"]?.string)
                    vignettes[index].image = PreviewImages.image(data)
                    vignettes[index].depuisCache = false
                    vignettes[index].erreur = nil
                } catch let erreur as AppelAnnule {
                    throw erreur
                } catch {
                    vignettes[index].erreur = vignettes[index].erreur ?? error.localizedDescription
                }
            }
            try traiter(vignettes)
            faites += lot.count
            avancer(faites, sur: ids.count, message, titre: ids.count > Self.thumbnailsPerCommand ? message : nil)
        }
    }

    func cullPhotos(_ args: Arguments) throws -> JSONValue {
        let debut = Date()
        let (ids, total) = try seriesPhotos(args, maximum: Self.maxCulledPhotos)
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à trier.") }
        let motsCles = args.bool("keywords") == true
        let pointsAF = LecteurPointsAF()
        var photos: [PhotoTriee] = []
        var depuisCache = 0, rendues = 0
        try thumbnails(ids, taille: Self.cullThumbnailSize, minimum: Self.minimumCullSide, message: "tri des photos") { lot in
            depuisCache += lot.filter { $0.image != nil && $0.depuisCache }.count
            rendues += lot.filter { $0.image != nil && !$0.depuisCache }.count
            // Les mesures, deux photos à la fois au plus : Vision limite ses propres tâches
            // parallèles, et 25 analyses lancées ensemble par concurrentPerform l'ont bloqué
            // (constaté le 17 octobre 2026 : tous les fils attendaient sa file).
            var mesurees = [PhotoTriee?](repeating: nil, count: lot.count)
            let verrou = NSLock()
            let file = OperationQueue()
            file.maxConcurrentOperationCount = Self.parallelMeasures
            for i in lot.indices {
                file.addOperation {
                    let photo = Self.mesurer(lot[i], motsCles: motsCles, pointsAF: pointsAF)
                    verrou.lock(); mesurees[i] = photo; verrou.unlock()
                }
            }
            file.waitUntilAllOperationsAreFinished()
            photos += mesurees.compactMap { $0 }
        }
        var bilan = Tri.bilan(photos, details: args.bool("details") == true).object ?? [:]
        // Les plafonds de ce tri remplacent ceux d'un tri précédent des mêmes photos (propose_ratings).
        let plafonds = Tri.plafonds(photos)
        for photo in photos { dernierTri[photo.id] = plafonds[photo.id] }
        if total > ids.count {
            bilan["photos_non_triees"] = .string("\(total - ids.count) photo(s) de plus dans la série : au plus \(Self.maxCulledPhotos) par appel.")
        }
        if let bloque = pointsAF.bloque {
            bilan["points_af"] = .string("L'original « \(bloque.lastPathComponent) » ne s'est pas ouvert en 2 s : points AF non lus pour la suite de la série (netteté mesurée dans la zone la plus nette). Volume débranché, ou macOS demande à l'utilisateur d'autoriser l'accès au volume (fenêtre à accepter, puis relancer le tri).")
        }
        bilan["vignettes"] = ["cache_de_lightroom": .number(Double(depuisCache)), "apercus_rendus": .number(Double(rendues)),
                              "duree": .string(FileOutils.duree(Date().timeIntervalSince(debut)))]
        bilan["base"] = .string("Mesures sur les vignettes du cache d'aperçus de Lightroom, réduites à \(Detail.side) px (celles d'une photo retouchée depuis peuvent dater d'avant) ; une photo sans vignette assez grande est rendue comme un aperçu. Netteté : 95e centile du laplacien, ramenée à l'échelle d'un aperçu exporté (moins de 15 floue, plus de 35 nette), au point AF de l'appareil quand le fichier le donne (Fujifilm), sinon dans la zone la plus nette. Yeux : fermés ou plissés si l'œil le plus ouvert d'un sujet (visage d'au moins la moitié du plus grand) a une ouverture sous \(DevelopCatalogue.format(VisionAnalysis.closedEyesThreshold)) (hauteur sur largeur du contour de Vision), seulement pour un visage assez grand ; à confirmer par un zoom. Rafales : photos consécutives où Vision voit la même scène, prises à moins de 4 s d'intervalle ; piles : celles de Lightroom, la meilleure de chacune nommée. Classement (ordre) : un ordre de lecture (netteté, note esthétique de Vision à demi-poids), pas une note. Plafonds, d'après le standard de notation (propose_ratings avec read_standard, ou developpeur://notation) : défaut majeur (floue, mise au point manquée, yeux fermés) 0 et rejet proposé ; douce ou mise au point signalée manquée par l'appareil 3 ; presque noire ou brûlée 2, à vérifier (rattrapable par la retouche) ; capture ou document selon Vision 1 ; pas la meilleure de sa rafale ou de sa pile 3 ; sinon \(Notation.noteMaximale) (5 : l'utilisateur seul) ; bruit fort : à noter après le débruitage. Un plafond borne la note, il ne la donne pas ; les étoiles se proposent par propose_ratings. Rejets à présenter à l'utilisateur, puis à poser après accord avec set_metadata (photo_ids et flag reject) ; une photo qui porte déjà un drapeau ou une note n'est pas proposée. À confirmer à l'œil (contact_sheet, view_photo).")
        return .object(bilan)
    }

    /// Les mesures d'une vignette : netteté, exposition, Vision, empreinte, point AF, mots-clés.
    static func mesurer(_ vignette: Vignette, motsCles: Bool, pointsAF: LecteurPointsAF = LecteurPointsAF()) -> PhotoTriee {
        let description = vignette.description
        var photo = PhotoTriee(id: vignette.id, fichier: description["fichier"]?.string ?? "photo \(vignette.id)")
        photo.date = Tri.date(description["date"]?.string)
        photo.note = description["note"]?.int
        photo.drapeau = description["drapeau"]?.string
        photo.format = description["format"]?.string
        photo.pile = description["pile"]?["dessus"]?.int
        guard let source = vignette.image else {
            photo.erreur = vignette.erreur ?? "pas de vignette"
            return photo
        }
        let image = PreviewImages.scaled(source, maxSide: Detail.side)
        let facteur = vignette.depuisCache ? thumbnailSharpnessFactor : 1
        photo.detail = Detail.analyze(image).map { detail in
            var ramenee = detail
            ramenee.zones = detail.zones.map { $0 * facteur }
            return ramenee
        }
        photo.mesures = Measurements.analyze(image)
        photo.vision = VisionAnalysis.analyze(image)
        photo.empreinte = VisionAnalysis.featurePrint(image)
        // Le point AF n'est rangé que par Fujifilm : l'original des autres marques n'est pas ouvert.
        let fujifilm = (description["marque"]?.string?.uppercased().contains("FUJIFILM") ?? false)
            || (description["chemin_original"]?.string?.lowercased().hasSuffix(".raf") ?? false)
        if fujifilm, let chemin = description["chemin_original"]?.string, let geometrie = GeometriePhoto(description["geometrie"]),
           let af = pointsAF.lire(URL(fileURLWithPath: chemin)) {
            let point = geometrie.versApercu(x: af.x, y: af.y)
            if (0...1).contains(point.x), (0...1).contains(point.y) {
                photo.af = .init(point: point, nettete: Detail.nettete(image, autour: point).map { $0 * facteur }, avertissement: af.avertissement)
            }
        }
        if motsCles { photo.motsCles = MotsClesVision.proposer(image) }
        return photo
    }

    func contactSheet(_ args: Arguments) throws -> ToolResult {
        let decalage = max(0, args.int("offset") ?? 0)
        let (ids, total) = try seriesPhotos(args, maximum: Self.maxContactSheet, decalage: decalage)
        // Numéros suivis d'une planche à l'autre : la photo 13 d'une sélection porte 13 sur la
        // deuxième planche (photo_ids : la liste donnée, numérotée depuis 1).
        let premier = (try args.intList("photo_ids"))?.isEmpty == false ? 1 : decalage + 1
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo pour la planche.") }
        if let colonnes = args.int("columns"), !(1...6).contains(colonnes) {
            throw LightroomError.invalid("« columns » va de 1 à 6.")
        }
        var vignettes: [Vignette] = []
        try thumbnails(ids, taille: Self.contactSheetThumbnailSize, minimum: 128, message: "planche contact") { vignettes += $0 }
        guard let image = PreviewImages.planche(vignettes.map { ($0.image, $0.description["fichier"]?.string ?? "photo \($0.id)") },
                                                colonnes: args.int("columns"), premierNumero: premier) else {
            throw LightroomError.plugin("Planche contact impossible à dessiner.")
        }
        var legende: [JSONValue] = []
        for (index, vignette) in vignettes.enumerated() {
            var item: [String: JSONValue] = ["numero": .number(Double(premier + index)), "id": .number(Double(vignette.id))]
            for cle in ["fichier", "note", "drapeau", "libelle", "date"] {
                if let valeur = vignette.description[cle], !valeur.isNull { item[cle] = valeur }
            }
            if vignette.image == nil { item["vignette"] = .string("absente : \(vignette.erreur ?? "Lightroom n'en a pas rendu")") }
            legende.append(.object(item))
        }
        var info: [String: JSONValue] = ["photos": .array(legende),
                                         "base": "Vignettes du cache d'aperçus de Lightroom : elles peuvent dater d'avant la dernière retouche (view_photo montre l'état actuel)."]
        if decalage + ids.count < total {
            info["suite"] = .string("\(total - decalage - ids.count) photo(s) de plus : rappeler avec offset = \(decalage + ids.count).")
        }
        // Recompressée au besoin : Claude Desktop refuse une réponse d'environ 1 Mo.
        return ToolResult(content: [Self.imageContent(image), .text(JSONCoding.pretty(.object(info)))])
    }
}
