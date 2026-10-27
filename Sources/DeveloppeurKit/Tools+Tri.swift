import CoreGraphics
import Foundation

/// Trier une séance : `cull_photos` (photos floues ou ratées, rafales et la meilleure de chacune,
/// ordre de lecture, plafonds de note mesurés, proposition de rejet) et `contact_sheet` (planche
/// contact numérotée, de quoi juger l'Impact d'une sortie sur 20 à 30 vignettes). Les deux
/// travaillent sur les vignettes du cache d'aperçus de Lightroom (commande vignettes), sans
/// exporter chaque photo ; une photo sans vignette est rendue comme un aperçu.
extension ToolHandler {
    /// Une sortie par tranches (1.4) : 500 jusqu'au correctif 1.3.8. Pas plus : la réponse d'un tri
    /// de 2 000 photos toutes floues pèserait 0,9 Mo, texte et forme structurée (mesuré le
    /// 26 octobre 2026), au bord de ce que Claude Desktop accepte ; 1 000 en font 0,45.
    static let maxCulledPhotos = 1_000
    /// Avec `details` (une ligne par photo, deux fois plus lourde), la tranche de toujours.
    static let maxCulledDetails = 500
    /// Les groupes de lumière d'une sortie entière (`match_series` avec `groups`, 1.4) : leur
    /// réponse est petite (les identifiants des groupes).
    static let maxPhotosSortie = 2_000
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
    /// (moyenne 0,88) ; le bruit est le même (0,83 à 1,15 fois). Gardé après le relevé du 21 octobre
    /// 2026 (cull_photos contre --constats sur six copies d'Essais) : le tri donne de 11 à 23 % de plus
    /// que l'aperçu de 1 344 px, au point AF comme au plus net, mais les deux classent pareil (mêmes
    /// photos sous 15 et au-dessus de 35) ; une baisse d'environ 15 % les rapprocherait, à relever sur
    /// plus de photos avant de le changer.
    static let thumbnailSharpnessFactor = 1.13
    /// Photos mesurées en même temps (Vision, netteté).
    static let parallelMeasures = 2

    var cullDefinitions: [JSONValue] {
        // Les cibles d'une série. Le tri prend la photo active sans cible (1.3.1 : dans la fenêtre
        // Claude, la note d'abord de la photo active l'oubliait) ; la planche contact non : une
        // planche d'une seule photo ne montre pas une série, il faut dire laquelle.
        func series(_ photos: String) -> [(String, JSONValue)] {
            [
                ("photo_ids", listProp("integer", photos)),
                ("selection", prop("boolean", "true = les photos sélectionnées dans Lightroom (toutes celles du film fixe si rien n'est sélectionné).")),
                ("collection", prop("string", "Une collection entière, par son nom, « Ensemble > Nom » ou son identifiant (manage_collections, action list), triée par date de prise de vue.")),
                ("folder", prop("string", "Un dossier entier, par son chemin complet (sans ses sous-dossiers), trié par date de prise de vue.")),
            ]
        }
        return [
            tool("cull_photos",
                 "Trie une séance ou une sortie entière (jusqu'à \(Self.maxCulledPhotos) photos par appel ; la suite par offset ; \(Self.maxCulledDetails) avec details) sur les vignettes du cache d'aperçus de Lightroom, sans rien changer : photos floues ou ratées (netteté, mise au point manquée au point AF lu dans les RAW et JPEG Fujifilm, yeux fermés ou plissés, presque noires, brûlées), rafales (photos consécutives semblables, prises coup sur coup) et piles de Lightroom, avec la meilleure de chacune, ordre de lecture (classement : netteté et note esthétique, pas une note), plafonds de note mesurés (plafonds : le plancher technique du standard de notation, qui borne la note sans la donner ; propose_ratings les fait respecter) et proposition de rejet (flag reject, pour un défaut majeur). Aucune étoile : elles se proposent par propose_ratings, après avoir regardé les photos. Présenter les rejets à l'utilisateur, puis, après son accord, les poser avec set_metadata ; undo_last les défait. Avec keywords, des mots-clés proposés par Vision, en français. Long sur une grande séance : la progression se suit photo par photo. Sans photo_ids, selection, collection ni folder : la photo active de Lightroom.",
                 properties: series("Photos à trier (champ « id »), dans l'ordre voulu. Défaut : la photo active de Lightroom.") + [
                    ("keywords", prop("boolean", "true = proposer aussi des mots-clés par photo (Vision, traduits en français), à poser avec set_metadata après accord.")),
                    ("details", prop("boolean", "true = une ligne de mesures par photo (ordre de lecture, plafond, défauts, point AF, mots-clés).")),
                    ("offset", prop("integer", "Avec selection, collection ou folder : photos à sauter (la tranche suivante d'une grande sortie : l'offset que donne photos_non_triees).")),
                 ],
                 required: []),
            tool("contact_sheet",
                 "Planche contact : une seule image de \(Self.maxContactSheet) vignettes au plus, numérotées, avec le nom de chaque fichier, pour voir une série d'un coup d'œil (choisir, comparer, harmoniser, juger l'Impact sur 20 à 30 vignettes) en bien moins de jetons qu'une image par photo. Vignettes du cache d'aperçus de Lightroom (elles peuvent dater d'avant la dernière retouche : la netteté et la finition se jugent par view_photo) ; légende : numéro, id, fichier, note, drapeau (au-delà de 20 vignettes, les noms se lisent mal sur l'image : la légende fait foi). Une sélection, une collection ou un dossier plus longs se montrent planche par planche (« suite » dit l'offset suivant), les numéros continuant d'une planche à l'autre ; une grande série se note ainsi, propose_ratings après chaque planche.",
                 properties: series("Photos de la planche (champ « id »), dans l'ordre voulu ; ou selection, collection ou folder (pas de défaut : une planche montre une série).") + [
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
        let serie = try seriesPhotosSansVideos(args, maximum: maximum, decalage: decalage)
        return (serie.ids, serie.total)
    }

    /// Une vidéo, d'après la description du module (`video`, ou `format` VIDEO).
    static func estVideo(_ description: JSONValue) -> Bool {
        description["video"]?.bool == true || description["format"]?.string?.uppercased() == "VIDEO"
    }

    /// La même série sans ses vidéos (1.3.5) : le tri, la série et la livraison les sautent et
    /// disent combien. Elles se lisent dans les descriptions d'une collection, d'un dossier ou de la
    /// sélection ; des photo_ids ne sont pas décrits ici (le tri les écarte à la lecture des
    /// vignettes, la livraison dans le module). `parTranches` (le tri, 1.4) : une sélection plus
    /// longue que `maximum` se prend par tranches au lieu d'être refusée ; le total dit la suite.
    func seriesPhotosSansVideos(_ args: Arguments, maximum: Int, decalage: Int = 0,
                                parTranches: Bool = false) throws -> (ids: [Int], total: Int, videos: Int) {
        if let ids = try args.intList("photo_ids"), !ids.isEmpty {
            guard ids.count <= maximum else { throw LightroomError.invalid("Au plus \(maximum) photos par appel.") }
            return (ids, ids.count, 0)
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
            let decrites = reponse["photos"]?.array ?? []
            let ids = decrites.filter { !Self.estVideo($0) }.compactMap { $0["id"]?.int }
            return (ids, reponse["total"]?.int ?? decrites.count, decrites.filter(Self.estVideo).count)
        }
        guard args.bool("selection") == true else {
            throw LightroomError.invalid("Photos à traiter : photo_ids, selection = true, collection ou folder.")
        }
        // Le module décrit la tranche demandée (1.4 : decalage, et autant de photos que la série en
        // prend, au-delà de la limite de list_selection) ; un module d'avant, qui ne connaît pas
        // decalage, décrit le début de la sélection : la réponse le dit (decalage absent).
        let tranche = max(maximum, Self.maxSelectionLimit)
        reponse = try lightroom.send("selection", ["limite": .number(Double(tranche)), "decalage": .number(Double(decalage))],
                                     timeout: Self.libraryTimeout)
        var dejaDecalee = reponse["decalage"]?.int == decalage
        // Un module d'avant n'a décrit que le début : il faut l'en redemander assez pour atteindre
        // la tranche voulue (une seule fois).
        if !dejaDecalee, decalage > 0, (reponse["photos"]?.array ?? []).count < decalage + maximum,
           (reponse["total"]?.int ?? 0) > (reponse["photos"]?.array ?? []).count {
            reponse = try lightroom.send("selection", ["limite": .number(Double(decalage + tranche)), "decalage": .number(Double(decalage))],
                                         timeout: Self.libraryTimeout)
            dejaDecalee = reponse["decalage"]?.int == decalage
        }
        let decrites = Array((reponse["photos"]?.array ?? []).dropFirst(dejaDecalee ? 0 : decalage).prefix(maximum))
        let total = reponse["total"]?.int ?? (reponse["photos"]?.array ?? []).count
        guard parTranches || decalage > 0 || total <= maximum else {
            throw LightroomError.invalid("\(total) photos sélectionnées : au plus \(maximum) par appel. Réduire la sélection ou donner photo_ids.")
        }
        return (decrites.filter { !Self.estVideo($0) }.compactMap { $0["id"]?.int }, total, decrites.filter(Self.estVideo).count)
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

    /// Une cible de série est-elle donnée (photo_ids non vide, selection = true, collection ou
    /// folder) ? Un photo_ids invalide compte : seriesPhotos dit pourquoi.
    static func serieDonnee(_ args: Arguments) -> Bool {
        do {
            if let ids = try args.intList("photo_ids"), !ids.isEmpty { return true }
        } catch {
            return true
        }
        return args.bool("selection") == true || args.has("collection") || args.has("folder")
    }

    func cullPhotos(_ args: Arguments) throws -> JSONValue {
        let debut = Date()
        let ids: [Int], total: Int
        var videos = 0
        // Une sortie de plus de maxCulledPhotos photos se trie par tranches (1.4) : offset.
        let maximumTri = args.bool("details") == true ? Self.maxCulledDetails : Self.maxCulledPhotos
        let photoIds = (try? args.intList("photo_ids")) ?? nil
        let decalage = (photoIds?.isEmpty ?? true) ? max(0, args.int("offset") ?? 0) : 0
        if Self.serieDonnee(args) {
            (ids, total, videos) = try seriesPhotosSansVideos(args, maximum: maximumTri, decalage: decalage, parTranches: true)
        } else {
            // Sans cible, la photo active de Lightroom, comme les autres outils (la note d'abord d'une
            // photo dans la fenêtre Claude) ; sans photo active, le refus de toujours.
            guard let active = try lightroom.send("etat", [:], timeout: 10)["photo_active"]?["id"]?.int else {
                throw LightroomError.invalid("Photos à traiter : photo_ids, selection = true, collection ou folder (aucune photo active dans Lightroom).")
            }
            (ids, total) = ([active], 1)
        }
        guard !ids.isEmpty else {
            throw LightroomError.invalid(videos > 0 ? "Aucune photo à trier : \(videos) vidéo(s), que le tri ne juge pas." : "Aucune photo à trier.")
        }
        let motsCles = args.bool("keywords") == true
        let pointsAF = LecteurBoitier()
        var photos: [PhotoTriee] = []
        var depuisCache = 0, rendues = 0
        try thumbnails(ids, taille: Self.cullThumbnailSize, minimum: Self.minimumCullSide, message: "tri des photos") { tout in
            // Une vidéo donnée par photo_ids se voit ici, à sa description : écartée, comptée.
            let lot = tout.filter { !Self.estVideo($0.description) }
            videos += tout.count - lot.count
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
        let suite = total - decalage - ids.count - videos
        if suite > 0 {
            bilan["photos_non_triees"] = .string("\(suite) photo(s) de plus dans la série : au plus \(maximumTri) par appel ; la tranche suivante : offset = \(decalage + ids.count + videos).")
        }
        if videos > 0 {
            bilan["videos_ecartees"] = .string("\(videos) vidéo(s) écartée(s) : le tri ne juge que les photos.")
        }
        if let bloque = pointsAF.bloque {
            bilan["points_af"] = .string("L'original « \(bloque.lastPathComponent) » ne s'est pas ouvert en 2 s : points AF non lus pour la suite de la série (netteté mesurée dans la zone la plus nette). Volume débranché, ou macOS demande à l'utilisateur d'autoriser l'accès au volume (fenêtre à accepter, puis relancer le tri).")
        }
        bilan["vignettes"] = ["cache_de_lightroom": .number(Double(depuisCache)), "apercus_rendus": .number(Double(rendues)),
                              "duree": .string(FileOutils.duree(Date().timeIntervalSince(debut)))]
        bilan["base"] = .string("Mesures sur les vignettes du cache d'aperçus de Lightroom, réduites à \(Detail.side) px (celles d'une photo retouchée depuis peuvent dater d'avant) ; une photo sans vignette assez grande est rendue comme un aperçu. Netteté : 95e centile du laplacien, ramenée à l'échelle d'un aperçu exporté (moins de 15 floue, plus de 35 nette), au point AF de l'appareil quand le fichier le donne (Fujifilm), sinon dans la zone la plus nette. Yeux : fermés ou plissés si l'œil le plus ouvert d'un sujet (visage d'au moins la moitié du plus grand) a une ouverture sous \(DevelopCatalogue.format(VisionAnalysis.closedEyesThreshold)) (hauteur sur largeur du contour de Vision), seulement pour un visage assez grand ; à confirmer par un zoom. Rafales : photos consécutives où Vision voit la même scène, prises à moins de 4 s d'intervalle ; piles : celles de Lightroom, la meilleure de chacune nommée. Classement (ordre) : un ordre de lecture (netteté, note esthétique de Vision à demi-poids), pas une note. Plafonds, d'après le standard de notation (propose_ratings avec read_standard, ou developpeur://notation) : défaut majeur (floue, mise au point manquée, yeux fermés) 0 et rejet proposé ; douce ou mise au point signalée manquée par l'appareil 2 ; presque noire ou brûlée 1, à vérifier (rattrapable par la retouche) ; capture ou document selon Vision 1 ; pas la meilleure de sa rafale ou de sa pile 2 ; sans défaut, pas de plafond (\(Notation.noteMaximale)) ; bruit fort : à noter après le débruitage. Au-delà de \(Tri.plafondsParPhotoMax) photos, plafonds_par_motif à la place de plafonds : les photos de chaque plafond, regroupées par motif, sans les mesures de chacune. Un plafond borne la note, il ne la donne pas ; les étoiles se proposent par propose_ratings. Rejets à présenter à l'utilisateur, puis à poser après accord avec set_metadata (photo_ids et flag reject) ; une photo qui porte déjà un drapeau ou une note n'est pas proposée. À confirmer à l'œil (contact_sheet, view_photo).")
        return .object(bilan)
    }

    /// Les mesures d'une vignette : netteté, exposition, Vision, empreinte, point AF, mots-clés.
    static func mesurer(_ vignette: Vignette, motsCles: Bool, pointsAF: LecteurBoitier = LecteurBoitier()) -> PhotoTriee {
        let description = vignette.description
        var photo = PhotoTriee(id: vignette.id, fichier: description["fichier"]?.string ?? "photo \(vignette.id)")
        photo.date = Tri.date(description["date"]?.string)
        photo.note = description["note"]?.int
        photo.drapeau = description["drapeau"]?.string
        photo.format = description["format"]?.string
        photo.pile = description["pile"]?["dessus"]?.int
        photo.boitier = description["serie_boitier"]?.string
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
        if let af = Self.pointAF(description, lecteur: pointsAF) {
            photo.af = .mesuree(image, point: af.point, avertissement: af.avertissement, facteur: facteur)
        }
        if motsCles { photo.motsCles = MotsClesVision.proposer(image) }
        return photo
    }

    /// Point de mise au point de l'appareil dans l'image affichée (de 0 à 1 depuis le coin haut
    /// gauche), et l'avertissement de l'appareil, d'après une description qui porte
    /// `chemin_original` et `geometrie` (Vignettes.decrireVignette du module). Fujifilm seulement :
    /// l'original des autres marques n'est pas ouvert. Nil si le point sort du cadre.
    static func pointAF(_ description: JSONValue?, lecteur: LecteurBoitier) -> (point: CGPoint, avertissement: Bool)? {
        // Sans géométrie, pas de point à placer : l'original n'est pas ouvert.
        guard GeometriePhoto(description?["geometrie"]) != nil else { return nil }
        return pointAF(lectureBoitier(description, lecteur: lecteur), description: description)
    }

    /// Ce que dit l'original d'une photo Fujifilm (point AF et intention), d'une seule ouverture,
    /// d'après une description qui porte `chemin_original` ; nil pour les autres marques, dont
    /// l'original n'est pas ouvert.
    static func lectureBoitier(_ description: JSONValue?, lecteur: LecteurBoitier) -> LectureBoitier? {
        let fujifilm = (description?["marque"]?.string?.uppercased().contains("FUJIFILM") ?? false)
            || (description?["chemin_original"]?.string?.lowercased().hasSuffix(".raf") ?? false)
        guard fujifilm, let chemin = description?["chemin_original"]?.string else { return nil }
        return lecteur.lire(URL(fileURLWithPath: chemin))
    }

    /// Le point de mise au point d'une lecture déjà faite, placé dans l'image affichée d'après la
    /// `geometrie` de la description ; nil sans point ou hors du cadre.
    static func pointAF(_ lecture: LectureBoitier?, description: JSONValue?) -> (point: CGPoint, avertissement: Bool)? {
        guard let af = lecture?.point, let geometrie = GeometriePhoto(description?["geometrie"]) else { return nil }
        let point = geometrie.versApercu(x: af.x, y: af.y)
        guard (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        return (point, af.avertissement)
    }

    /// Le cadre AF de l'onglet Focus (Focus.cadres, genre pointAF) d'une lecture déjà faite, dans
    /// l'image affichée, pour le dessiner comme lui (PreviewImages.marquerFocus) ; vide sans cadre lu
    /// (demandé par Dany le 22 octobre 2026 : le même cadre rouge partout dans la fenêtre Claude).
    static func cadresAF(_ lecture: LectureBoitier?, description: JSONValue?) -> [Focus.Cadre] {
        guard let m = lecture?.miseAuPoint, let g = GeometriePhoto(description?["geometrie"]) else { return [] }
        return Focus.cadres(m, geometrie: g).cadres.filter { $0.genre == .pointAF }
    }

    func contactSheet(_ args: Arguments) throws -> ToolResult {
        let decalage = max(0, args.int("offset") ?? 0)
        // Une sélection plus longue que la planche se montre planche par planche, comme une
        // collection : la première sans offset (refusée jusqu'au 26 octobre 2026), la suite dite.
        let serie = try seriesPhotosSansVideos(args, maximum: Self.maxContactSheet, decalage: decalage, parTranches: true)
        let (ids, total) = (serie.ids, serie.total)
        let liste = (try args.intList("photo_ids"))?.isEmpty == false
        // Numéros suivis d'une planche à l'autre : la photo 13 d'une sélection porte 13 sur la
        // deuxième planche (photo_ids : la liste donnée, numérotée depuis 1).
        let premier = liste ? 1 : decalage + 1
        // La tranche suivante commence après les vidéos écartées de celle-ci (sans elles, « suite »
        // remontrait des photos ; relecture du 26 octobre 2026).
        let suivant = decalage + ids.count + serie.videos
        guard !ids.isEmpty else {
            // Une tranche faite de vidéos seulement : la suite, pas une erreur qui arrêterait le
            // parcours d'une grande série.
            guard !liste, serie.videos > 0, suivant < total else { throw LightroomError.invalid("Aucune photo pour la planche.") }
            return json(["planche": ["premiere": .number(Double(decalage + 1)), "derniere": .number(Double(suivant)), "sur": .number(Double(total))],
                         "videos_ecartees": .string("\(serie.videos) vidéo(s) écartée(s) : aucune photo dans cette tranche."),
                         "suite": .string("\(total - suivant) photo(s) de plus : rappeler avec offset = \(suivant).")])
        }
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
        // Où en est le parcours de la série (positions, vidéos comprises) : la ligne d'état de la
        // fenêtre Claude le dit pendant que Claude note la planche.
        if !liste {
            info["planche"] = ["premiere": .number(Double(decalage + 1)), "derniere": .number(Double(suivant)), "sur": .number(Double(total))]
        }
        if serie.videos > 0 {
            info["videos_ecartees"] = .string("\(serie.videos) vidéo(s) écartée(s) de la planche.")
        }
        if suivant < total {
            info["suite"] = .string("\(total - suivant) photo(s) de plus : rappeler avec offset = \(suivant).")
        }
        // Recompressée au besoin : Claude Desktop refuse une réponse d'environ 1 Mo.
        return ToolResult(content: [Self.imageContent(image), .text(JSONCoding.pretty(.object(info)))])
    }
}
