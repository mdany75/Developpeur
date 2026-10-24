import Foundation
import ImageIO

/// Livraison : `export_photos` (fichiers livrés par la LrExportSession du module, jamais
/// d'écrasement), pour l'écran, le web, le partage ou l'impression : formats récents et sortie
/// HDR, poids maximal, filigrane, renommage, réimportation, livraisons types lues dans les
/// services Disque dur, dossier choisi dans une fenêtre, noms exacts, aperçus dynamiques ; la
/// fenêtre d'exportation de Lightroom en dernier recours.
extension ToolHandler {
    /// Photos par commande du module : la progression avance et l'annulation se vérifie entre deux lots.
    static let photosPerExport = 10
    static let photosPerSmartPreviewBatch = 25
    static let maxExportedPhotos = 500
    static let exportTimeout: TimeInterval = 900

    /// Une livraison type : les réglages d'un service de publication « Disque dur » de
    /// l'utilisateur (lus dans Lightroom), ou, sans ces services, l'un des deux profils par défaut.
    /// Chaque réglage donné à l'appel l'emporte.
    struct ProfilLivraison {
        var nom: String
        var description: String
        var dossierHabituel: String?
        var reglages: [String: JSONValue]
        var service: Int?
        var remarques: [String] = []
    }

    /// Profils par défaut, quand Lightroom ne donne aucun service Disque dur : ceux des deux services
    /// de l'utilisateur relus le 18 octobre 2026 (2.3) : JPEG qualité 100, sRGB, sans netteté de
    /// sortie, toutes les métadonnées sans lieu ni personnes ; 5 mégapixels pour l'un.
    static let profilsParDefaut: [ProfilLivraison] = [
        ProfilLivraison(nom: "web_5mp", description: "Web et écrans : JPEG qualité 100, sRGB, 5 mégapixels, sans netteté de sortie",
                        dossierHabituel: nil,
                        reglages: ["format": "JPEG", "qualite": 100, "espace": "sRGB", "taille": ["type": "megapixels", "valeur": 5],
                                   "metadonnees": "all", "sans_lieu": true]),
        ProfilLivraison(nom: "pleine_qualite", description: "Pleine qualité : JPEG qualité 100, sRGB, pleine résolution, sans netteté de sortie",
                        dossierHabituel: nil,
                        reglages: ["format": "JPEG", "qualite": 100, "espace": "sRGB", "metadonnees": "all", "sans_lieu": true]),
    ]

    static let exportFormats: [(name: String, module: String)] = [
        ("jpeg", "JPEG"), ("jxl", "JXL"), ("avif", "AVIF"), ("tiff", "TIFF"), ("png", "PNG"), ("psd", "PSD"),
        ("dng", "DNG"), ("original", "ORIGINAL"),
    ]
    static let colorSpaces: [(name: String, module: String)] = [
        ("srgb", "sRGB"), ("adobe_rgb", "AdobeRGB"), ("display_p3", "DisplayP3"), ("prophoto_rgb", "ProPhotoRGB"), ("rec2020", "Rec2020"),
    ]
    /// Espaces de la sortie HDR (relevés dans AgExportSettings de Lightroom Classic 15.6) : HDR
    /// Rec. 709, HDR P3, HDR Rec. 2020 (pas en JPEG).
    static let hdrColorSpaces: [(name: String, module: String)] = [
        ("srgb", "sRGB_hdr"), ("display_p3", "p3_hdr"), ("rec2020", "Rec2020_hdr"),
    ]
    static let metadataOptions: [(name: String, module: String)] = [
        ("all", "all"), ("copyright_only", "copyrightOnly"), ("copyright_contact", "copyrightAndContactOnly"),
        ("all_except_camera_raw", "allExceptCameraRawInfo"), ("all_except_camera", "allExceptCameraInfo"),
    ]
    static let sharpeningMedia = ["screen", "matte", "glossy"]
    /// Résolution d'un tirage par défaut (pixels par pouce), et ses bornes.
    static let tiragePpp = 300, tiragePppPermis = 240...600

    /// Un tirage (`print`) : le grand côté en pixels d'après le format en centimètres et la
    /// résolution, et le papier.
    static func tirage(_ objet: [String: JSONValue]) throws -> (grandCote: Int, ppp: Int, papier: String, cm: (Double, Double)) {
        guard let texte = objet["size"]?.string else { throw LightroomError.invalid("« print.size » : le format en centimètres, « 20x30 ».") }
        let nombres = texte.lowercased().replacingOccurrences(of: ",", with: ".")
            .split(whereSeparator: { "x×* ".contains($0) }).compactMap { Double($0.replacingOccurrences(of: "cm", with: "")) }
        guard nombres.count == 2, nombres.allSatisfy({ (5...200).contains($0) }) else {
            throw LightroomError.invalid("« print.size » : largeur x hauteur en centimètres, de 5 à 200 (« 20x30 »).")
        }
        let ppp = objet["ppi"]?.int ?? tiragePpp
        guard tiragePppPermis.contains(ppp) else { throw LightroomError.invalid("« print.ppi » : de \(tiragePppPermis.lowerBound) à \(tiragePppPermis.upperBound).") }
        let papier = objet["paper"]?.string ?? "glossy"
        guard ["matte", "glossy"].contains(papier) else { throw LightroomError.invalid("« print.paper » : matte ou glossy.") }
        let grandCote = min(20000, Int((max(nombres[0], nombres[1]) / 2.54 * Double(ppp)).rounded()))
        return (grandCote, ppp, papier, (nombres[0], nombres[1]))
    }
    static let sharpeningAmounts = ["low", "standard", "high"]
    /// Filigrane simple des droits d'auteur de la photo (identifiant de Lightroom).
    static let simpleCopyrightWatermark = "<simpleCopyrightWatermark>"

    var deliveryDefinitions: [JSONValue] {
        [
            tool("export_photos",
                 "Exporte des photos en fichiers (écran, web, partage, impression, archive), développées comme dans Lightroom (même moteur que son exportation), dans un dossier choisi par l'utilisateur ; un fichier qui existe déjà n'est jamais écrasé (le nouveau reçoit « -2 »). Ne change pas les photos. list = true d'abord : livraisons types (les services Disque dur de l'utilisateur), modèles de noms, filigranes, paramètres prédéfinis de métadonnées, dossiers récents ; avec filename_template et des photos, les noms exacts que Lightroom calculera. choose_folder = true : l'utilisateur désigne le dossier dans une fenêtre. Formats : JPEG, JPEG XL, AVIF, TIFF, PNG, PSD, DNG, original ; hdr = true pour une sortie HDR (photos en mode HDR) ; max_size_kb (JPEG) ; watermark ; reimport remet les fichiers dans le catalogue (stack : empilés avec l'original, dans son dossier ; undo_last ne les retire pas). Droits d'auteur : set_metadata avant. Autres usages, au lieu d'exporter : smart_previews (aperçus dynamiques, pour travailler le disque des originaux débranché ; une livraison s'en sert jusqu'à 2560 px), open_dialog (fenêtre d'exportation de Lightroom). Mode « Proposer d'abord » : dire ce qui serait fait, attendre l'accord, puis confirm = true. Longue série : par lots de \(Self.photosPerExport).",
                 properties: [
                    ("list", prop("boolean", "true = seulement lister (voir la description) ; avec filename_template : les noms exacts.")),
                    ("photo_ids", listProp("integer", "Photos visées (champ « id »). Défaut : la photo active.")),
                    ("selection", prop("boolean", "true = les photos sélectionnées dans Lightroom.")),
                    ("collection", prop("string", "Une collection : son nom, « Ensemble > Nom » ou son identifiant.")),
                    ("folder_source", prop("string", "Les photos d'un dossier du catalogue : son chemin complet.")),
                    ("folder", prop("string", "Dossier de livraison, chemin complet (créé s'il n'existe pas, si son parent existe). Exigé pour exporter, sauf reimport = stack.")),
                    ("choose_folder", prop("boolean", "true = ouvrir dans Lightroom une fenêtre où l'utilisateur choisit le dossier ; renvoie son chemin (à passer ensuite dans folder).")),
                    ("subfolder", prop("string", "Sous-dossier à créer dans folder (facultatif).")),
                    ("profile", prop("string", "Livraison type, par son nom (list = true : un service Disque dur de l'utilisateur) ; les réglages donnés l'emportent.")),
                    ("format", enumProp(Self.exportFormats.map(\.name), "Format (défaut jpeg) ; jxl = JPEG XL ; original = le fichier d'origine tel quel.")),
                    ("quality", prop("integer", "Qualité JPEG, JPEG XL ou AVIF, de 0 à 100 (défaut 80).")),
                    ("lossless", prop("boolean", "JPEG XL : true = sans perte.")),
                    ("color_space", enumProp(Self.colorSpaces.map(\.name), "Espace colorimétrique (défaut srgb ; en HDR : srgb, display_p3 par défaut, ou rec2020, pas en JPEG).")),
                    ("hdr", prop("boolean", "true = sortie HDR (case « Sortie HDR » de Lightroom), pour les photos en mode HDR (HDREditMode) : JPEG (avec carte de gain), JPEG XL, AVIF, PNG, TIFF, PSD.")),
                    ("maximize_compatibility", prop("boolean", "HDR en AVIF, JPEG XL ou TIFF : true (défaut) = image SDR et carte de gain, lisible partout ; false = HDR seul. Le JPEG HDR a toujours sa carte de gain.")),
                    ("bit_depth", prop("integer", "TIFF, PNG, PSD, JPEG XL : 8 ou 16 bits (défaut 8) ; 32 en HDR (TIFF, PSD). JPEG : 8, AVIF : 10, imposés.")),
                    ("max_size_kb", prop("integer", "JPEG : poids maximal du fichier en Ko (courriel, sites qui limitent le poids) ; Lightroom baisse la qualité au besoin.")),
                    ("long_edge", prop("integer", "Grand côté en pixels (sinon pleine résolution).")),
                    ("short_edge", prop("integer", "Petit côté en pixels.")),
                    ("megapixels", prop("number", "Taille en mégapixels (5 = environ 2740 × 1830 pour un 3:2).")),
                    ("print", objectProp("Un tirage (1.3.5) : size, le format en cm (« 20x30 », « 30x45 », « 13x18 »…), donne le grand côté à ppi (défaut \(Self.tiragePpp), de 240 à 600) ; paper, matte ou glossy (défaut), la netteté de sortie de ce papier. long_edge et sharpening donnés à part l'emportent. Un tirage sort souvent plus sombre et plus doux que l'écran : avant, sur une copie virtuelle « tirage », remonter un peu les ombres (Shadows +5 à +10), si la photo le demande. Le profil du laboratoire se choisit dans la fenêtre d'exportation de Lightroom (open_dialog) : un module ne peut pas le poser.", [
                        "size": prop("string", "Format en centimètres, largeur x hauteur : « 20x30 »."),
                        "ppi": prop("integer", "Résolution en pixels par pouce (défaut \(Self.tiragePpp))."),
                        "paper": enumProp(["matte", "glossy"], "Papier : mat ou brillant (défaut glossy)."),
                    ])),
                    ("sharpening", objectProp("Netteté de sortie ; {\"media\": \"none\"} la retire.", [
                        "media": enumProp(Self.sharpeningMedia + ["none"], "screen (écran), matte (papier mat), glossy (papier brillant), none."),
                        "amount": enumProp(Self.sharpeningAmounts, "Intensité (défaut standard)."),
                    ])),
                    ("watermark", prop("string", "Filigrane : « copyright » (droits d'auteur de la photo, en texte) ou le nom d'un filigrane de l'utilisateur (list = true) ; « none » le retire.")),
                    ("metadata", enumProp(Self.metadataOptions.map(\.name), "Métadonnées incluses (défaut all).")),
                    ("remove_location", prop("boolean", "true (défaut) = retirer le lieu (GPS) des fichiers.")),
                    ("filename_template", prop("string", "Modèle de noms de fichiers de Lightroom, par son nom (list = true), par exemple « Date - Nom du fichier ». Défaut : le nom du fichier d'origine.")),
                    ("custom_text", prop("string", "Texte personnalisé des modèles « Nom personnalisé… » (par exemple le nom de la séance).")),
                    ("start_number", prop("integer", "Premier numéro des modèles à séquence (défaut 1).")),
                    ("reimport", enumProp(["catalog", "stack"], "Remettre les fichiers livrés dans le catalogue : catalog (depuis folder) ou stack (dans le dossier de l'original, empilés avec lui ; folder inutile). Ils y restent : undo_last ne les retire pas.")),
                    ("smart_previews", enumProp(["build", "delete"], "Au lieu d'exporter : build = créer les aperçus dynamiques de ces photos (avant de partir sans le disque des originaux) ; delete = les retirer (au retour, pour la place ; jamais si l'original manque).")),
                    ("open_dialog", prop("boolean", "true = ouvrir la fenêtre d'exportation de Lightroom pour ces photos (l'utilisateur choisit et termine).")),
                 ] + writeProperties,
                 required: []),
        ]
    }

    func exportPhotos(_ args: Arguments) throws -> JSONValue {
        if args.bool("list") == true { return try deliveryOptions(args) }
        if args.bool("choose_folder") == true { return try chooseDeliveryFolder(args) }
        let ids = try deliveryPhotos(args)
        if let apercus = args.string("smart_previews") {
            guard apercus == "build" || apercus == "delete" else { throw LightroomError.invalid("« smart_previews » : build ou delete.") }
            return try buildSmartPreviews(ids, retirer: apercus == "delete")
        }
        if args.bool("open_dialog") == true {
            return try lightroom.send("fenetreExport", ["photos": .array(ids.map { .number(Double($0)) })], timeout: 60)
        }
        let (reglages, resume, profil) = try deliverySettings(args)
        let empiler = reglages["reimporter"]?.string == "pile"
        var commun: [String: JSONValue] = ["reglages": .object(reglages)]
        if empiler {
            guard !args.has("subfolder") else { throw LightroomError.invalid("reimport = stack : les fichiers vont dans le dossier de chaque original (Lightroom n'empile que là) ; pas de subfolder.") }
        } else {
            guard let dossier = args.string("folder")?.trimmingCharacters(in: .whitespaces), dossier.hasPrefix("/") else {
                throw LightroomError.invalid("« folder » : le chemin complet du dossier de livraison, choisi par l'utilisateur (choose_folder = true lui ouvre une fenêtre)\(profil?.dossierHabituel.map { " ; dossier habituel pour « \(profil!.nom) » : « \($0) »" } ?? "").")
            }
            commun["dossier"] = .string(dossier)
        }
        if let sous = args.string("subfolder")?.trimmingCharacters(in: .whitespaces), !sous.isEmpty {
            guard !sous.contains("/") else { throw LightroomError.invalid("« subfolder » : un seul nom de dossier, sans « / ».") }
            commun["sous_dossier"] = .string(sous)
        }
        var parLot = Self.photosPerExport
        var modele: FilenameTemplate?
        if let nom = args.string("filename_template") {
            modele = try filenameTemplates.template(named: nom)
            commun["jetons"] = .string(modele!.tokens)
            if modele!.needsCustomText {
                guard let texte = args.string("custom_text")?.trimmingCharacters(in: .whitespaces), !texte.isEmpty else {
                    throw LightroomError.invalid("Le modèle « \(modele!.name) » demande un texte personnalisé : custom_text (par exemple le nom de la séance).")
                }
                commun["texte_perso"] = .string(texte)
            }
            // Un numéro « x sur y » compte les photos de la session : une seule session.
            if modele!.countsTotal {
                guard ids.count <= 200 else { throw LightroomError.invalid("Le modèle « \(modele!.name) » numérote « x sur y » : au plus 200 photos d'un coup.") }
                parLot = ids.count
            }
        }
        let depart = max(args.int("start_number") ?? 1, 1)
        commun["confirme"] = .bool(args.bool("confirm") ?? false)

        var fichiers: [JSONValue] = [], echecs: [JSONValue] = [], reimportees: [JSONValue] = []
        var octets = 0.0
        var depuisApercus = 0
        var lourds: [String] = []
        let limiteOctets = reglages["poids_max_ko"]?.double.map { $0 * 1024 }
        var dossierLivre = commun["dossier"]?.string
        avancer(0, sur: ids.count, "Livraison de \(ids.count) photo\(ids.count > 1 ? "s" : "")", titre: "livraison")
        for debut in stride(from: 0, to: ids.count, by: parLot) {
            try contexte.verifier()
            let lot = Array(ids[debut..<min(debut + parLot, ids.count)])
            var params = commun
            params["photos"] = .array(lot.map { .number(Double($0)) })
            params["sequence"] = .number(Double(depart + debut))
            params["suite"] = .bool(debut > 0)
            let reponse = try lightroom.send("exporter", params, timeout: Self.exportTimeout)
            if dossierLivre == nil { dossierLivre = reponse["dossier"]?.string }
            for item in reponse["fichiers"]?.array ?? [] {
                if let chemin = item["chemin"]?.string {
                    octets += item["octets"]?.double ?? 0
                    if let limiteOctets, let taille = item["octets"]?.double, taille > limiteOctets {
                        lourds.append("\(URL(fileURLWithPath: chemin).lastPathComponent) : \(Int((taille / 1024).rounded())) Ko")
                    }
                    var fichier: [String: JSONValue] = ["photo": item["photo"]?["fichier"] ?? .null, "fichier": .string(chemin)]
                    if item["depuis_apercu_dynamique"]?.bool == true {
                        fichier["depuis_apercu_dynamique"] = true
                        depuisApercus += 1
                    }
                    fichiers.append(.object(fichier))
                    if let id = item["reimportee"]?.int { reimportees.append(["fichier": .string(chemin), "id": .number(Double(id))]) }
                } else {
                    echecs.append(["photo": item["photo"]?["fichier"] ?? .null, "raison": item["erreur"] ?? .null])
                }
            }
            avancer(min(debut + lot.count, ids.count), sur: ids.count, "Livraison : \(min(debut + lot.count, ids.count)) sur \(ids.count)", titre: "livraison")
        }
        var resultat: [String: JSONValue] = [
            "dossier": .string(empiler ? "le dossier de chaque original" : (dossierLivre ?? "") + (commun["sous_dossier"]?.string.map { "/" + $0 } ?? "")),
            "livrees": .number(Double(fichiers.count)),
            "reglages": .string(resume),
            "taille_totale_mo": .number((octets / 1_048_576 * 10).rounded() / 10),
            "fichiers": .array(Array(fichiers.prefix(50))),
            "jamais_d_ecrasement": "Un nom déjà pris garde son fichier : le nouveau reçoit « -2 », « -3 »…",
        ]
        if fichiers.count > 50 { resultat["fichiers_non_listes"] = .number(Double(fichiers.count - 50)) }
        if !echecs.isEmpty { resultat["echecs"] = .array(echecs) }
        if let profil { resultat["profil"] = .string(profil.nom) }
        if let modele { resultat["modele_noms"] = .string(modele.name) }
        if depuisApercus > 0 {
            resultat["depuis_apercus_dynamiques"] = .string("\(depuisApercus) photo\(depuisApercus > 1 ? "s" : "") livrée\(depuisApercus > 1 ? "s" : "") depuis l'aperçu dynamique (original débranché).")
        }
        if reglages["reimporter"] != nil {
            resultat["reimportees"] = .array(reimportees)
            resultat["a_savoir"] = .string("Fichiers ajoutés au catalogue\(empiler ? ", empilés avec leur original" : "") : ils y restent (undo_last ne les retire pas ; Photo › Retirer du catalogue, à la main).")
        }
        if let limite = reglages["poids_max_ko"]?.double, !lourds.isEmpty {
            resultat["au_dessus_du_poids"] = .string("\(lourds.count) fichier\(lourds.count > 1 ? "s" : "") au-dessus de \(Int(limite)) Ko (\(lourds.prefix(5).joined(separator: ", "))) : Lightroom livre alors le plus petit fichier possible à cette taille ; réduire long_edge pour tenir la limite.")
        }
        if let premier = fichiers.first?["fichier"]?.string, let lecture = Self.lectureFichier(premier) {
            resultat["premier_fichier"] = .object(lecture)
        }
        return .object(resultat)
    }

    /// Les photos à livrer : celles demandées, ou la photo active.
    func deliveryPhotos(_ args: Arguments) throws -> [Int] {
        var series = args.raw
        if let dossier = args.string("folder_source") { series["folder"] = .string(dossier) } else { series.removeValue(forKey: "folder") }
        let cibles = Arguments(raw: series)
        if cibles.has("photo_ids") || cibles.bool("selection") == true || cibles.has("collection") || cibles.has("folder") {
            let (ids, total) = try seriesPhotos(cibles, maximum: Self.maxExportedPhotos)
            guard total <= Self.maxExportedPhotos else {
                throw LightroomError.invalid("\(total) photos : au plus \(Self.maxExportedPhotos) par livraison. Livrer en plusieurs fois.")
            }
            guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à livrer.") }
            return ids
        }
        guard let active = try lightroom.send("etat", [:], timeout: 10)["photo_active"]?["id"]?.int else {
            throw LightroomError.invalid("Aucune photo active : donner photo_ids, selection, collection ou folder_source.")
        }
        return [active]
    }

    /// Les livraisons types : les services Disque dur de l'utilisateur (leurs réglages, lus dans
    /// Lightroom), sinon les profils par défaut.
    func profilsLivraison(services: [JSONValue]? = nil) throws -> [ProfilLivraison] {
        let liste = try services ?? (lightroom.send("livraison", [:], timeout: 60)["services_publication"]?.array ?? [])
        let lus = liste.compactMap(Self.profilService)
        return lus.isEmpty ? Self.profilsParDefaut : lus
    }

    /// Les réglages d'un service Disque dur (clés de l'exportation de Lightroom), en réglages de
    /// livraison ; nil pour un autre service ou un format que le connecteur ne livre pas.
    static func profilService(_ service: JSONValue) -> ProfilLivraison? {
        guard let r = service["reglages"]?.object, let nom = service["nom"]?.string else { return nil }
        let format = r["LR_format"]?.string ?? "JPEG"
        guard exportFormats.contains(where: { $0.module == format }) else { return nil }
        var reglages: [String: JSONValue] = ["format": .string(format)]
        var remarques: [String] = []
        let cleQualite = ["JPEG": "LR_jpeg_quality", "JXL": "LR_jxl_quality", "AVIF": "LR_avif_quality"][format]
        if let cle = cleQualite, let qualite = r[cle]?.double { reglages["qualite"] = .number((qualite * 100).rounded()) }
        if format == "JXL", r["LR_jxl_losslessQuality"]?.bool == true { reglages["sans_perte"] = true }
        let hdr = r["LR_enableHDRDisplay"]?.bool == true
        if let espace = r["LR_export_colorSpace"]?.string {
            if hdr, hdrColorSpaces.contains(where: { $0.module == espace }) {
                reglages["hdr"] = true
                reglages["espace"] = .string(espace)
                if let compatibilite = r["LR_maximumCompatibility"]?.bool { reglages["compatibilite"] = .bool(compatibilite) }
            } else if colorSpaces.contains(where: { $0.module == espace }) {
                reglages["espace"] = .string(espace)
            } else {
                remarques.append("Espace « \(espace) » du service : sRGB à la place.")
                reglages["espace"] = "sRGB"
            }
        }
        if let profondeur = r["LR_export_bitDepth"]?.int, profondeur == 16 || profondeur == 32 { reglages["profondeur"] = .number(Double(profondeur)) }
        if r["LR_size_doConstrain"]?.bool == true {
            let largeur = r["LR_size_maxWidth"]?.double ?? 0, hauteur = r["LR_size_maxHeight"]?.double ?? 0
            switch r["LR_size_resizeType"]?.string {
            case "megapixels":
                if let mp = r["LR_size_megapixels"]?.double { reglages["taille"] = ["type": "megapixels", "valeur": .number(mp)] }
            case "longEdge":
                reglages["taille"] = ["type": "longEdge", "valeur": .number(max(largeur, hauteur))]
            case "shortEdge":
                reglages["taille"] = ["type": "shortEdge", "valeur": .number(max(largeur, hauteur))]
            case let type?:
                if max(largeur, hauteur) > 0 {
                    reglages["taille"] = ["type": "longEdge", "valeur": .number(max(largeur, hauteur))]
                    remarques.append("Taille « \(type) » du service : grand côté \(Int(max(largeur, hauteur))) px à la place.")
                }
            default: break
            }
        }
        if r["LR_outputSharpeningOn"]?.bool == true, let support = r["LR_outputSharpeningMedia"]?.string, sharpeningMedia.contains(support) {
            reglages["nettete"] = ["support": .string(support), "niveau": .number(r["LR_outputSharpeningLevel"]?.double ?? 2)]
        }
        if let option = r["LR_embeddedMetadataOption"]?.string, metadataOptions.contains(where: { $0.module == option }) {
            reglages["metadonnees"] = .string(option)
        } else {
            reglages["metadonnees"] = "all"
        }
        reglages["sans_lieu"] = .bool(r["LR_removeLocationMetadata"]?.bool ?? true)
        if format == "JPEG", r["LR_jpeg_useLimitSize"]?.bool == true, let limite = r["LR_jpeg_limitSize"]?.double, limite > 0 {
            reglages["poids_max_ko"] = .number(limite)
        }
        if r["LR_useWatermark"]?.bool == true, let filigrane = r["LR_watermarking_id"]?.string, !filigrane.isEmpty {
            reglages["filigrane"] = .string(filigrane)
        }
        if format == "ORIGINAL" || format == "DNG" {
            for cle in ["qualite", "taille", "nettete", "espace", "profondeur", "hdr", "compatibilite", "filigrane"] { reglages.removeValue(forKey: cle) }
        }
        var profil = ProfilLivraison(nom: nom, description: resumeLivraison(reglages), dossierHabituel: r["LR_export_destinationPathPrefix"]?.string,
                                     reglages: reglages, service: service["id"]?.int)
        profil.remarques = remarques
        return profil
    }

    /// Les réglages de la livraison (profil puis réglages donnés), un résumé lisible et le profil.
    func deliverySettings(_ args: Arguments) throws -> ([String: JSONValue], String, ProfilLivraison?) {
        var profil: ProfilLivraison?
        if let nom = args.string("profile")?.trimmingCharacters(in: .whitespaces) {
            let profils = try profilsLivraison()
            guard let trouve = profils.first(where: { $0.nom.lowercased() == nom.lowercased() || $0.service.map(String.init) == nom }) else {
                throw LightroomError.invalid("« profile » : \(profils.map { "« \($0.nom) »" }.joined(separator: ", ")).")
            }
            profil = trouve
        }
        var r = profil?.reglages ?? ["format": "JPEG", "qualite": 80, "espace": "sRGB", "metadonnees": "all", "sans_lieu": true]
        func choix(_ key: String, _ values: [(name: String, module: String)]) throws -> String? {
            guard let text = args.string(key) else { return nil }
            guard let value = values.first(where: { $0.name == text }) else {
                throw LightroomError.invalid("« \(key) » : \(values.map(\.name).joined(separator: ", ")).")
            }
            return value.module
        }
        if let format = try choix("format", Self.exportFormats) {
            if format != r["format"]?.string {
                // Un autre format que celui du profil : sa qualité et ses options propres ne suivent pas.
                for cle in ["sans_perte", "poids_max_ko", "compatibilite"] { r.removeValue(forKey: cle) }
            }
            r["format"] = .string(format)
        }
        let format = r["format"]?.string ?? "JPEG"
        let rendu = format != "ORIGINAL" && format != "DNG"
        if let hdr = args.bool("hdr") {
            if hdr {
                guard rendu else { throw LightroomError.invalid("« hdr » : pas pour l'original ni le DNG (aucun rendu).") }
                r["hdr"] = true
            } else {
                r.removeValue(forKey: "hdr")
                r.removeValue(forKey: "compatibilite")
            }
        }
        let hdr = r["hdr"]?.bool == true && rendu
        if let nom = args.string("color_space") {
            if hdr {
                guard let espace = Self.hdrColorSpaces.first(where: { $0.name == nom }) else {
                    throw LightroomError.invalid("« color_space » en HDR : srgb (HDR Rec. 709), display_p3 (HDR P3) ou rec2020 (HDR Rec. 2020).")
                }
                r["espace"] = .string(espace.module)
            } else {
                r["espace"] = .string(try choix("color_space", Self.colorSpaces)!)
            }
        } else if hdr, let espace = r["espace"]?.string, !Self.hdrColorSpaces.contains(where: { $0.module == espace }) {
            // L'espace SDR du profil passe en HDR : HDR P3 (le plus courant des écrans HDR), ou HDR
            // Rec. 2020 pour un profil en Rec. 2020 (pas en JPEG).
            r["espace"] = .string(espace == "Rec2020" && format != "JPEG" ? "Rec2020_hdr" : "p3_hdr")
        } else if !hdr, let espace = r["espace"]?.string, Self.hdrColorSpaces.contains(where: { $0.module == espace }) {
            r["espace"] = .string(["sRGB_hdr": "sRGB", "Rec2020_hdr": "Rec2020"][espace] ?? "DisplayP3")
        }
        if hdr, format == "JPEG", r["espace"]?.string == "Rec2020_hdr" {
            throw LightroomError.invalid("HDR Rec. 2020 : pas en JPEG (Lightroom ne l'offre pas) ; srgb ou display_p3, ou un autre format (avif, jxl).")
        }
        if let compatibilite = args.bool("maximize_compatibility") {
            guard hdr, ["AVIF", "JXL", "TIFF"].contains(format) else {
                throw LightroomError.invalid("« maximize_compatibility » : sortie HDR en AVIF, JPEG XL ou TIFF seulement (le JPEG HDR a toujours sa carte de gain).")
            }
            r["compatibilite"] = .bool(compatibilite)
        }
        if let metadonnees = try choix("metadata", Self.metadataOptions) { r["metadonnees"] = .string(metadonnees) }
        if let qualite = args.int("quality") {
            guard (0...100).contains(qualite) else { throw LightroomError.invalid("« quality » : de 0 à 100.") }
            guard ["JPEG", "JXL", "AVIF"].contains(format) else { throw LightroomError.invalid("« quality » : JPEG, JPEG XL ou AVIF seulement.") }
            r["qualite"] = .number(Double(qualite))
        }
        if let sansPerte = args.bool("lossless") {
            guard format == "JXL" else { throw LightroomError.invalid("« lossless » : JPEG XL seulement (format = jxl).") }
            r["sans_perte"] = .bool(sansPerte)
        }
        if let profondeur = args.int("bit_depth") {
            switch (profondeur, format) {
            case (8, "TIFF"), (8, "PNG"), (8, "PSD"), (8, "JXL"), (16, "TIFF"), (16, "PNG"), (16, "PSD"), (16, "JXL"):
                guard !(hdr && profondeur == 8) else { throw LightroomError.invalid("« bit_depth » : 16 ou 32 bits en HDR (8 bits, c'est le JPEG).") }
                r["profondeur"] = .number(Double(profondeur))
            case (32, "TIFF"), (32, "PSD"):
                guard hdr else { throw LightroomError.invalid("« bit_depth » 32 : sortie HDR seulement (hdr = true).") }
                r["profondeur"] = 32
            default:
                throw LightroomError.invalid("« bit_depth » : 8 ou 16 pour TIFF, PNG, PSD, JPEG XL ; 32 en HDR pour TIFF ou PSD. JPEG : 8 et AVIF : 10, imposés.")
            }
        }
        if let poids = args.int("max_size_kb") {
            guard format == "JPEG" else { throw LightroomError.invalid("« max_size_kb » : JPEG seulement (« Limiter la taille du fichier » de Lightroom).") }
            guard (10...1_000_000).contains(poids) else { throw LightroomError.invalid("« max_size_kb » : de 10 à 1 000 000 Ko.") }
            r["poids_max_ko"] = .number(Double(poids))
        }
        if let nom = args.string("watermark")?.trimmingCharacters(in: .whitespaces) {
            if ["none", "aucun", ""].contains(nom.lowercased()) {
                r.removeValue(forKey: "filigrane")
            } else {
                guard rendu else { throw LightroomError.invalid("« watermark » : pas pour l'original ni le DNG.") }
                r["filigrane"] = .string(try filigranes.identifiant(nom))
            }
        }
        if let reimport = args.string("reimport") {
            guard reimport == "catalog" || reimport == "stack" else { throw LightroomError.invalid("« reimport » : catalog ou stack.") }
            r["reimporter"] = .string(reimport == "stack" ? "pile" : "catalogue")
        }
        if let lieu = args.bool("remove_location") { r["sans_lieu"] = .bool(lieu) }
        let tailles = [("long_edge", "longEdge"), ("short_edge", "shortEdge"), ("megapixels", "megapixels")].filter { args.has($0.0) }
        guard tailles.count <= 1 else { throw LightroomError.invalid("Une seule taille : long_edge, short_edge ou megapixels.") }
        if let (cle, type) = tailles.first {
            guard let valeur = args.double(cle), valeur > 0 else { throw LightroomError.invalid("« \(cle) » doit être positif.") }
            if type != "megapixels", !(200...20000).contains(valeur) { throw LightroomError.invalid("« \(cle) » : de 200 à 20000 pixels.") }
            if type == "megapixels", !(0.1...200).contains(valeur) { throw LightroomError.invalid("« megapixels » : de 0,1 à 200.") }
            r["taille"] = ["type": .string(type), "valeur": .number(valeur)]
        }
        if let nettete = args.object("sharpening") {
            let support = nettete["media"]?.string ?? "screen"
            if support == "none" {
                r.removeValue(forKey: "nettete")
            } else {
                guard Self.sharpeningMedia.contains(support) else { throw LightroomError.invalid("« sharpening.media » : screen, matte, glossy ou none.") }
                let intensite = nettete["amount"]?.string ?? "standard"
                guard let niveau = Self.sharpeningAmounts.firstIndex(of: intensite) else {
                    throw LightroomError.invalid("« sharpening.amount » : low, standard ou high.")
                }
                r["nettete"] = ["support": .string(support), "niveau": .number(Double(niveau + 1))]
            }
        }
        // Un tirage (1.3.5) : le format en centimètres donne le grand côté à la résolution voulue,
        // et la netteté de sortie suit le papier ; une taille ou une netteté données à part
        // l'emportent.
        if let tirage = args.object("print") {
            let t = try Self.tirage(tirage)
            if tailles.isEmpty { r["taille"] = ["type": "longEdge", "valeur": .number(Double(t.grandCote))] }
            r["resolution"] = .number(Double(t.ppp))
            if args.object("sharpening") == nil { r["nettete"] = ["support": .string(t.papier), "niveau": 2] }
        }
        if !rendu {
            for cle in ["qualite", "taille", "nettete", "espace", "profondeur", "hdr", "compatibilite", "filigrane", "poids_max_ko", "sans_perte", "resolution"] {
                r.removeValue(forKey: cle)
            }
        }
        if !["JPEG", "JXL", "AVIF"].contains(format) { r.removeValue(forKey: "qualite") }
        if format != "JPEG" { r.removeValue(forKey: "poids_max_ko") }
        return (r, Self.resumeLivraison(r, filigranes: filigranes), profil)
    }

    static func resumeLivraison(_ r: [String: JSONValue], filigranes: FiligranesUtilisateur? = nil) -> String {
        var parties: [String] = []
        let format = r["format"]?.string ?? "JPEG"
        let noms = ["ORIGINAL": "fichier d'origine", "JXL": "JPEG XL"]
        parties.append(noms[format] ?? format)
        if r["hdr"]?.bool == true {
            let compatibilite = format == "JPEG" || (r["compatibilite"]?.bool ?? true) && ["AVIF", "JXL"].contains(format)
            parties.append("HDR" + (compatibilite ? " avec carte de gain" : ""))
        }
        if format == "JXL", r["sans_perte"]?.bool == true {
            parties.append("sans perte")
        } else if ["JPEG", "JXL", "AVIF"].contains(format), let qualite = r["qualite"]?.double {
            parties.append("qualité \(Int(qualite))")
        }
        if let poids = r["poids_max_ko"]?.double { parties.append("\(Int(poids)) Ko au plus") }
        if let espace = r["espace"]?.string {
            let espaces = ["sRGB_hdr": "HDR Rec. 709", "p3_hdr": "HDR P3", "Rec2020_hdr": "HDR Rec. 2020", "Rec2020": "Rec. 2020"]
            parties.append(espaces[espace] ?? espace)
        }
        if let profondeur = r["profondeur"]?.double { parties.append("\(Int(profondeur)) bits") }
        if let taille = r["taille"]?.object, let valeur = taille["valeur"]?.double {
            switch taille["type"]?.string {
            case "megapixels": parties.append("\(DevelopCatalogue.format(valeur)) mégapixels")
            case "shortEdge": parties.append("petit côté \(Int(valeur)) px")
            default: parties.append("grand côté \(Int(valeur)) px")
            }
            if let ppp = r["resolution"]?.int { parties.append("\(ppp) ppp") }
        } else if format != "ORIGINAL", format != "DNG" {
            parties.append("pleine résolution")
        }
        if let nettete = r["nettete"]?.object, let support = nettete["support"]?.string {
            let supports = ["screen": "écran", "matte": "papier mat", "glossy": "papier brillant"]
            let niveaux = [1: "faible", 2: "standard", 3: "forte"]
            parties.append("netteté \(supports[support] ?? support) \(niveaux[nettete["niveau"]?.int ?? 2] ?? "")")
        }
        if let filigrane = r["filigrane"]?.string {
            parties.append(filigrane == simpleCopyrightWatermark ? "filigrane des droits d'auteur"
                           : "filigrane « \(filigranes?.nom(filigrane) ?? filigrane) »")
        }
        let metadonnees = ["all": "toutes les métadonnées", "copyrightOnly": "droits d'auteur seulement", "copyrightAndContactOnly": "droits d'auteur et contact",
                           "allExceptCameraRawInfo": "tout sauf Camera Raw", "allExceptCameraInfo": "tout sauf l'appareil et Camera Raw"]
        parties.append(metadonnees[r["metadonnees"]?.string ?? "all"] ?? "toutes les métadonnées")
        if r["sans_lieu"]?.bool != false { parties.append("sans le lieu") }
        switch r["reimporter"]?.string {
        case "pile": parties.append("réimportés et empilés avec l'original")
        case "catalogue": parties.append("réimportés dans le catalogue")
        default: break
        }
        return parties.joined(separator: ", ")
    }

    /// Livraisons types, modèles de noms, filigranes, paramètres prédéfinis de métadonnées et
    /// dossiers récents ; avec filename_template et des photos, les noms exacts.
    func deliveryOptions(_ args: Arguments) throws -> JSONValue {
        if let nom = args.string("filename_template") { return try filenamePreview(nom, args) }
        let options = try lightroom.send("livraison", [:], timeout: 60)
        let modeles = filenameTemplates.all()
        var noms: [JSONValue] = modeles.map { modele in
            var item: [String: JSONValue] = ["nom": .string(modele.name), "jetons": .string(modele.tokens)]
            if modele.needsCustomText { item["texte_perso"] = "exigé (custom_text)" }
            if modele.usesSequence { item["sequence"] = "numéro de départ : start_number" }
            return .object(item)
        }
        let connus = Set(modeles.map(\.name))
        for item in options["modeles_noms"]?.array ?? [] {
            if let nom = item["nom"]?.string, !connus.contains(nom), !FilenameTemplates.ignored(nom) {
                noms.append(["nom": .string(nom), "remarque": "Modèle illisible pour le serveur : à choisir dans la fenêtre d'exportation (open_dialog)."])
            }
        }
        // Les services de publication ne servent qu'aux livraisons types (réglages des services Disque dur).
        let profils = try profilsLivraison(services: options["services_publication"]?.array ?? [])
        return [
            "profils": .array(profils.map { profil in
                var item: [String: JSONValue] = ["nom": .string(profil.nom), "reglages": .string(profil.description)]
                if let dossier = profil.dossierHabituel { item["dossier_habituel"] = .string(dossier) }
                if let service = profil.service { item["service"] = .number(Double(service)) } else { item["remarque"] = "Profil par défaut : aucun service Disque dur lu dans Lightroom." }
                if !profil.remarques.isEmpty { item["remarques"] = .array(profil.remarques.map(JSONValue.string)) }
                return .object(item)
            }),
            "modeles_noms": .array(noms),
            "filigranes": .array([["nom": "copyright", "description": "Filigrane simple : les droits d'auteur de la photo, en texte"]]
                + filigranes.all().map { ["nom": .string($0.nom), "description": .string($0.description)] }),
            "presets_metadonnees": options["presets_metadonnees"] ?? [],
            "dossiers_recents": .array(Self.recentExportFolders(preferences: preferencesLightroom).map(JSONValue.string)),
            "a_savoir": "Le dossier se choisit avec l'utilisateur (choose_folder = true : une fenêtre). Droits d'auteur : set_metadata (copyright ou metadata_preset) avant l'exportation. Noms exacts : list = true avec filename_template et les photos.",
        ]
    }

    /// Les noms que Lightroom calculera avec un modèle (photo:getNameViaPreset), et ceux déjà pris
    /// dans le dossier de livraison (Lightroom y ajoutera « -2 »).
    func filenamePreview(_ nom: String, _ args: Arguments) throws -> JSONValue {
        let ids = try deliveryPhotos(args)
        var params: [String: JSONValue] = ["photos": .array(ids.prefix(20).map { .number(Double($0)) }), "modele": .string(nom),
                                           "sequence": .number(Double(max(args.int("start_number") ?? 1, 1)))]
        if let texte = args.string("custom_text") { params["texte_perso"] = .string(texte) }
        let reponse = try lightroom.send("nomsFichiers", params, timeout: 60)
        let suffixe = ["JPEG": "jpg", "JXL": "jxl", "AVIF": "avif", "TIFF": "tif", "PNG": "png", "PSD": "psd", "DNG": "dng"][
            Self.exportFormats.first { $0.name == (args.string("format") ?? "jpeg") }?.module ?? "JPEG"]
        let dossier = args.string("folder").map { URL(fileURLWithPath: $0) }
        let noms: [JSONValue] = (reponse["noms"]?.array ?? []).map { item in
            var ligne: [String: JSONValue] = ["photo": item["photo"]?["fichier"] ?? .null]
            if let base = item["nom"]?.string {
                let fichier = suffixe.map { "\(base).\($0)" } ?? base
                ligne["nom"] = .string(fichier)
                if let dossier, FileManager.default.fileExists(atPath: dossier.appendingPathComponent(fichier).path) {
                    ligne["deja_pris"] = "Ce nom existe dans le dossier : Lightroom donnera « -2 » au nouveau fichier."
                }
            } else {
                ligne["erreur"] = item["erreur"] ?? .null
            }
            return .object(ligne)
        }
        var resultat: [String: JSONValue] = ["modele": reponse["modele"] ?? .string(nom), "noms": .array(noms),
                                             "a_savoir": .string("Noms calculés par Lightroom (getNameViaPreset)\(suffixe == nil ? "" : ", extension du format choisi").")]
        if ids.count > 20 { resultat["photos_non_listees"] = .number(Double(ids.count - 20)) }
        return .object(resultat)
    }

    /// Fenêtre de choix du dossier dans Lightroom : son chemin, ou « en attente » tant que
    /// l'utilisateur n'a pas choisi.
    func chooseDeliveryFolder(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = [:]
        if let depart = args.string("folder") { params["depart"] = .string(depart) }
        let reponse = try lightroom.send("choisirDossier", params, timeout: 60)
        if let dossier = reponse["dossier"]?.string {
            return ["dossier": .string(dossier), "a_savoir": "Dossier choisi par l'utilisateur : le passer dans folder."]
        }
        if reponse["annule"]?.bool == true {
            return ["annule": true, "a_savoir": "L'utilisateur a fermé la fenêtre sans choisir de dossier : lui demander où livrer."]
        }
        return ["en_attente": true,
                "a_savoir": "La fenêtre « Dossier de livraison (Claude) » est ouverte dans Lightroom Classic : l'utilisateur y choisit le dossier (Lightroom doit être au premier plan pour la voir). Rappeler export_photos avec choose_folder = true pour lire son choix."]
    }

    /// Aperçus dynamiques des photos, créés ou retirés, par lots (Lightroom montre sa barre de
    /// progression).
    func buildSmartPreviews(_ ids: [Int], retirer: Bool = false) throws -> JSONValue {
        var bilan: [String: [JSONValue]] = ["crees": [], "existants": [], "echecs": [], "sans_original": [], "retires": [], "absents": []]
        var taille = 0.0
        avancer(0, sur: ids.count, "Aperçus dynamiques de \(ids.count) photo\(ids.count > 1 ? "s" : "")", titre: "aperçus dynamiques")
        for debut in stride(from: 0, to: ids.count, by: Self.photosPerSmartPreviewBatch) {
            try contexte.verifier()
            let lot = Array(ids[debut..<min(debut + Self.photosPerSmartPreviewBatch, ids.count)])
            var params: [String: JSONValue] = ["photos": .array(lot.map { .number(Double($0)) })]
            if retirer { params["retirer"] = true }
            let reponse = try lightroom.send("apercusDynamiques", params, timeout: Self.exportTimeout)
            for cle in bilan.keys { bilan[cle]! += reponse[cle]?.array ?? [] }
            taille += reponse["taille_mo"]?.double ?? 0
            avancer(debut + lot.count, sur: ids.count, "Aperçus dynamiques : \(debut + lot.count) sur \(ids.count)", titre: "aperçus dynamiques")
        }
        var resultat: [String: JSONValue] = ["photos": .number(Double(ids.count))]
        if retirer {
            resultat["a_savoir"] = "Aperçus dynamiques retirés : Lightroom ne montre plus ces photos sans leur original. Ceux des photos dont l'original manque sont gardés (sans_original)."
        } else {
            resultat["taille_mo"] = .number((taille * 10).rounded() / 10)
            resultat["a_savoir"] = "Le disque débranché, Lightroom montre, développe et livre ces photos depuis leur aperçu dynamique (2560 px de grand côté au plus) : view_photo, cull_photos, export_photos avec long_edge ≤ 2560."
        }
        for (cle, liste) in bilan where !liste.isEmpty { resultat[cle] = .array(Array(liste.prefix(100))) }
        return .object(resultat)
    }

    /// Dossiers de livraison récents de l'exportation de Lightroom (ses préférences), qui existent.
    static func recentExportFolders(preferences: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.adobe.LightroomClassicCC7.plist")) -> [String] {
        guard let data = try? Data(contentsOf: preferences),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let texte = plist["AgMRUPopupList_AgExport_destinationFolderPathPrefix"] as? String,
              let expression = try? NSRegularExpression(pattern: "\"((?:[^\"\\\\]|\\\\.)*)\"") else { return [] }
        let range = NSRange(texte.startIndex..., in: texte)
        return expression.matches(in: texte, range: range).compactMap { match in
            Range(match.range(at: 1), in: texte).map { String(texte[$0]) }
        }.filter { FileManager.default.fileExists(atPath: $0) }
    }

    /// Largeur et hauteur d'une image livrée (sans la décoder).
    static func dimensions(_ chemin: String) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: chemin) as CFURL, nil),
              let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let largeur = proprietes[kCGImagePropertyPixelWidth] as? Int,
              let hauteur = proprietes[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (largeur, hauteur)
    }

    /// Le fichier livré relu par ImageIO : dimensions, profondeur, profil, et s'il est HDR (fonction
    /// de transfert PQ ou HLG, ou carte de gain).
    static func lectureFichier(_ chemin: String) -> [String: JSONValue]? {
        let url = URL(fileURLWithPath: chemin)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let proprietes = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let largeur = proprietes[kCGImagePropertyPixelWidth] as? Int,
              let hauteur = proprietes[kCGImagePropertyPixelHeight] as? Int else { return nil }
        var lecture: [String: JSONValue] = [
            "dimensions": .string("\(largeur) × \(hauteur) px (\(DevelopCatalogue.format((Double(largeur * hauteur) / 100_000).rounded() / 10).replacingOccurrences(of: ".", with: ",")) Mpx)"),
        ]
        if let octets = (try? FileManager.default.attributesOfItem(atPath: chemin))?[.size] as? Int {
            lecture["poids_ko"] = .number(Double((octets + 512) / 1024))
        }
        if let profondeur = proprietes[kCGImagePropertyDepth] as? Int { lecture["profondeur"] = .number(Double(profondeur)) }
        if let profil = proprietes[kCGImagePropertyProfileName] as? String { lecture["profil"] = .string(profil) }
        var hdr: [String] = []
        if let image = CGImageSourceCreateImageAtIndex(source, 0, nil), let espace = image.colorSpace {
            if CGColorSpaceUsesITUR_2100TF(espace) {
                hdr.append("fonction de transfert HDR (PQ ou HLG)")
            } else if CGColorSpaceUsesExtendedRange(espace) || (image.bitmapInfo.contains(.floatComponents) && (proprietes[kCGImagePropertyDepth] as? Int ?? 0) >= 32) {
                hdr.append("virgule flottante, plage étendue")
            }
        }
        if CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil {
            hdr.append("carte de gain (Apple)")
        }
        if #available(macOS 15.0, *), CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil {
            hdr.append("carte de gain ISO 21496-1")
        }
        // ImageIO ne lit pas la carte de gain d'un JPEG XL (constaté en 2.5) : sa boîte « jhgm ».
        if url.pathExtension.lowercased() == "jxl", let donnees = try? Data(contentsOf: url, options: .mappedIfSafe),
           donnees.range(of: Data("jhgm".utf8)) != nil {
            hdr.append("carte de gain (boîte jhgm du JPEG XL)")
        }
        lecture["hdr"] = hdr.isEmpty ? false : .string(hdr.joined(separator: ", "))
        return lecture
    }
}

/// Un filigrane de l'utilisateur (Édition › Modifier les filigranes de Lightroom), lu dans son
/// fichier de `Watermarks` : un modèle de Lightroom (`id`, `title`, `value.items` : textes et
/// images ; relevé dans AgWatermarkingData de Lightroom Classic 15.6, type « WatermarkingPreset »).
public struct Filigrane: Equatable {
    public var id: String
    public var nom: String
    public var description: String
}

public struct FiligranesUtilisateur {
    public let folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Watermarks")) {
        self.folder = folder
    }

    public func all() -> [Filigrane] {
        let fichiers = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return fichiers.filter { $0.pathExtension == "lrtemplate" }.compactMap { url in
            guard let texte = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self.lire(texte, nomFichier: url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.nom < $1.nom }
    }

    /// `id = "…"` et `title = "…"` (ou `ZSTR "$$$/…=Titre"`) du modèle ; ses textes, ou « image ».
    static func lire(_ texte: String, nomFichier: String) -> Filigrane? {
        func valeur(_ cle: String) -> String? {
            guard let expression = try? NSRegularExpression(pattern: "(?m)^\\s*\(cle)\\s*=\\s*(?:ZSTR\\s*)?\"((?:[^\"\\\\]|\\\\.)*)\""),
                  let match = expression.firstMatch(in: texte, range: NSRange(texte.startIndex..., in: texte)),
                  let range = Range(match.range(at: 1), in: texte) else { return nil }
            var trouve = String(texte[range]).replacingOccurrences(of: "\\\"", with: "\"")
            if trouve.hasPrefix("$$$/"), let egal = trouve.firstIndex(of: "=") { trouve = String(trouve[trouve.index(after: egal)...]) }
            return trouve
        }
        guard let id = valeur("id"), !id.isEmpty else { return nil }
        var textes: [String] = []
        if let expression = try? NSRegularExpression(pattern: "(?m)^\\s*text\\s*=\\s*\"((?:[^\"\\\\]|\\\\.)*)\"") {
            for match in expression.matches(in: texte, range: NSRange(texte.startIndex..., in: texte)) {
                if let range = Range(match.range(at: 1), in: texte) { textes.append(String(texte[range])) }
            }
        }
        let image = texte.contains("kind = \"image\"")
        let description = textes.isEmpty ? (image ? "image" : "filigrane") : "texte « \(textes.joined(separator: " / ")) »" + (image ? " et image" : "")
        return Filigrane(id: id, nom: valeur("title") ?? nomFichier, description: description)
    }

    /// L'identifiant de Lightroom d'un filigrane donné par son nom (ou son identifiant).
    func identifiant(_ nom: String) throws -> String {
        let voulu = nom.lowercased()
        if ["copyright", "droits", "droits d'auteur", ToolHandler.simpleCopyrightWatermark.lowercased()].contains(voulu) {
            return ToolHandler.simpleCopyrightWatermark
        }
        let filigranes = all()
        guard let filigrane = filigranes.first(where: { $0.nom.lowercased() == voulu || $0.id.lowercased() == voulu }) else {
            throw LightroomError.invalid("Filigrane introuvable : « \(nom) ». Offerts : « copyright »\(filigranes.map { ", « \($0.nom) »" }.joined()).")
        }
        return filigrane.id
    }

    func nom(_ id: String) -> String? { all().first { $0.id == id }?.nom }
}

/// Un modèle de noms de fichiers de Lightroom (Bibliothèque › Modifier les noms de fichiers), lu
/// dans son fichier `.lrtemplate` : la suite de jetons (`{ value = "date_YYYYMMDD" }`) et de textes
/// que Lightroom range sous `deflated`, rendue en jetons d'exportation (`{{date_YYYYMMDD}}-…`).
public struct FilenameTemplate: Equatable {
    public var name: String
    public var tokens: String

    var needsCustomText: Bool { tokens.contains("{{custom_token}}") }
    var usesSequence: Bool { tokens.contains("naming_sequenceNumber") }
    var countsTotal: Bool { tokens.contains("naming_sequenceTotal") }
}

public struct FilenameTemplates {
    public let folder: URL

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Adobe/Lightroom/Filename Templates")) {
        self.folder = folder
    }

    /// Les modèles lisibles, par nom (celui du fichier, tel que Lightroom l'affiche). Ceux de la
    /// prise de vue (jeton du nom de la session, pour la capture en mode connecté) n'en sont pas.
    public func all() -> [FilenameTemplate] {
        let fichiers = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return fichiers.filter { $0.pathExtension == "lrtemplate" }.compactMap { url in
            guard let texte = try? String(contentsOf: url, encoding: .utf8), let tokens = Self.tokens(texte),
                  !tokens.contains("shoot_custom_token") else { return nil }
            return FilenameTemplate(name: url.deletingPathExtension().lastPathComponent, tokens: tokens)
        }.sorted { $0.name < $1.name }
    }

    static func ignored(_ nom: String) -> Bool {
        nom.contains("prise de vue") || nom.contains("session") || nom.contains("Shoot") || nom.contains("Session")
    }

    func template(named nom: String) throws -> FilenameTemplate {
        let modeles = all()
        let voulu = nom.trimmingCharacters(in: .whitespaces).lowercased()
        guard let modele = modeles.first(where: { $0.name.lowercased() == voulu }) else {
            throw LightroomError.invalid("Modèle de noms introuvable : « \(nom) ». Offerts : \(modeles.map { "« \($0.name) »" }.joined(separator: ", ")).")
        }
        return modele
    }

    /// `deflated = { { { value = "a" }, "-", { value = "b" }, name = …` → « {{a}}-{{b}} ».
    static func tokens(_ texte: String) -> String? {
        guard let debut = texte.range(of: "deflated"), let fin = texte.range(of: "name =", range: debut.upperBound..<texte.endIndex),
              let expression = try? NSRegularExpression(pattern: #"\{\s*value\s*=\s*"([^"]*)"\s*,?\s*\}|"((?:[^"\\]|\\.)*)"\s*,"#) else { return nil }
        let morceau = String(texte[debut.upperBound..<fin.lowerBound])
        var resultat = ""
        for match in expression.matches(in: morceau, range: NSRange(morceau.startIndex..., in: morceau)) {
            if let jeton = Range(match.range(at: 1), in: morceau) {
                resultat += "{{\(morceau[jeton])}}"
            } else if let litteral = Range(match.range(at: 2), in: morceau) {
                var texte = String(morceau[litteral]).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
                // Texte traduit (ZSTR "$$$/…= of ") : sa valeur anglaise, après le signe égal.
                if texte.hasPrefix("$$$/"), let egal = texte.firstIndex(of: "=") { texte = String(texte[texte.index(after: egal)...]) }
                resultat += texte
            }
        }
        return resultat.isEmpty ? nil : resultat
    }
}
