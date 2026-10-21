import CoreGraphics
import Foundation
import Vision

/// Voir et mesurer : `view_photo` (aperçu, zoom sur une zone, avant/après, mesures, netteté et
/// bruit, Vision), `measure_angle` (angle d'une ligne, pour redresser), `analyze_photos` (mesures
/// d'une série, écarts avec une référence, photos semblables) et `get_settings`.
extension ToolHandler {
    /// Taille des aperçus d'analyse : celle où les seuils de netteté et de bruit ont été relevés.
    static let analysisSize = Detail.side
    static let maxAnalyzedPhotos = 30

    var analysisDefinitions: [JSONValue] {
        [
            tool("view_photo",
                 "Montre la photo telle qu'elle est développée en ce moment (aperçu JPEG rendu par Lightroom avec les réglages actuels), avec ses données de prise de vue, ses réglages non nuls et des mesures objectives : luminosité L*, centiles, écrêtage (aussi par canal), contraste, dominante des tons neutres, netteté par zone et bruit ; et ce que voit Vision (visages et pupilles, qualité des visages, note esthétique, zone d'intérêt). À appeler avant de retoucher, puis après chaque passe. Mesures sur un JPEG sRGB (une couleur hors du sRGB y paraît écrêtée) ; en HDR (HDREditMode), le rendu SDR : le HDR ne se voit pas. « a_savoir » (calculs IA en attente) : le dire. « evaluation » : la note de Claude gardée pour la photo (pas encore évaluée, à vérifier, acceptée…). region = zoom à 100 % sur une zone (netteté et bruit en pleine résolution, taches) ; compare = avant/après côte à côte.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("size", prop("integer", "Grand côté de l'aperçu en pixels (défaut \(Self.defaultPreviewSize), de \(Self.previewSizes.lowerBound) à \(Self.previewSizes.upperBound)).")),
                    ("region", objectProp("Zone à voir en pleine résolution (zoom 100 %, réduit si elle dépasse \(PreviewImages.maxSide) px), en fractions de l'image affichée.", [
                        "x": prop("number", "Bord gauche (0 à 1)."),
                        "y": prop("number", "Bord haut (0 à 1)."),
                        "width": prop("number", "Largeur (0 à 1)."),
                        "height": prop("number", "Hauteur (0 à 1)."),
                    ], required: ["x", "y", "width", "height"])),
                    ("compare", enumProp(["before_claude", "previous_step"], "Avant/après côte à côte : before_claude = l'état d'avant la première retouche de Claude ; previous_step = avant la dernière retouche. L'Historique de Lightroom garde deux étapes « Claude · comparaison » (l'état d'avant, puis l'état actuel remis) : la photo revient telle qu'elle était.")),
                    ("af_point", prop("boolean", "true = le point de mise au point de l'appareil dessiné sur l'image ou le zoom (region) : carré vert, rouge si l'appareil l'a signalé manqué (fichiers Fujifilm seulement). Pour noter, ou montrer la mise au point. Sans lui, point_af le donne en chiffres (avec la netteté autour ; sur un zoom, dans_la_zone) ; l'utilisateur peut le vouloir dessiné en tout temps.")),
                 ],
                 required: []),
            tool("measure_angle",
                 "Mesure l'angle exact d'une ligne qui devrait être horizontale ou verticale (horizon, crête d'une chute, ligne de toit, arête d'un bâtiment, poteau), pour redresser au dixième de degré : donner deux points sur la ligne, dans l'image telle que la montre view_photo ; le serveur affine l'angle sur le contour le long du segment. Choisir une ligne vraiment droite dans la réalité, pas une ligne de perspective (rambarde, route qui fuit). Renvoie l'inclinaison et l'angle de recadrage qui la corrige (crop.angle d'apply_settings).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("x1", prop("number", "Premier point de la ligne, depuis la gauche (0 à 1).")),
                    ("y1", prop("number", "Premier point, depuis le haut (0 à 1).")),
                    ("x2", prop("number", "Second point, depuis la gauche (0 à 1).")),
                    ("y2", prop("number", "Second point, depuis le haut (0 à 1).")),
                 ],
                 required: ["x1", "y1", "x2", "y2"]),
            tool("analyze_photos",
                 "Mesures objectives de plusieurs photos sans les afficher (luminosité L*, contraste, écrêtage, dominante, saturation, netteté, bruit, visages, note esthétique), pour juger, trier ou harmoniser une série. Repère les photos semblables (rafales, quasi-doublons) et la meilleure de chaque groupe. Avec reference_id : écarts de chaque photo avec la référence et indications pour s'en rapprocher (l'exposition en IL ; pour la couleur et le contraste, un sens à vérifier).",
                 properties: targetProperties + [
                    ("reference_id", prop("integer", "Photo de référence (correspondance de couleur et d'exposition).")),
                 ],
                 required: []),
            tool("get_settings",
                 "Donne tous les réglages de développement actuels d'une photo, groupés comme dans le module Développement, avec l'échelle de la température, le profil, le recadrage, les courbes par points, les masques, les couleurs ponctuelles, les retouches de taches, et son classement dans la Bibliothèque (note, drapeau, libellé, titre, mots-clés).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("all_keys", prop("boolean", "true = ajoute « tous_les_reglages » : tout ce que Lightroom range pour la photo, même les réglages que ce serveur ne connaît pas encore (pour explorer un outil de Lightroom appliqué à la main).")),
                 ], required: []),
        ]
    }

    func viewPhoto(_ args: Arguments) throws -> ToolResult {
        let requested = args.int("size") ?? Self.defaultPreviewSize
        let size = min(max(requested, Self.previewSizes.lowerBound), Self.previewSizes.upperBound)
        var params: [String: JSONValue] = [
            "taille": .number(Double(size)),
            "cles": .array(DevelopCatalogue.keys.map(JSONValue.string)),
        ]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }

        var region: CGRect?
        if let object = args.object("region") {
            func part(_ key: String) throws -> Double {
                guard let value = object[key]?.double, (0...1).contains(value) else {
                    throw LightroomError.invalid("« region.\(key) » va de 0 à 1.")
                }
                return value
            }
            let rect = CGRect(x: try part("x"), y: try part("y"), width: try part("width"), height: try part("height"))
            guard rect.width > 0.005, rect.height > 0.005, rect.maxX <= 1.0001, rect.maxY <= 1.0001 else {
                throw LightroomError.invalid("« region » doit tenir dans l'image (x + width ≤ 1, y + height ≤ 1).")
            }
            region = rect
            params["taille"] = 0
        }
        let compare = args.string("compare")
        if let compare {
            guard ["before_claude", "previous_step"].contains(compare) else {
                throw LightroomError.invalid("« compare » vaut before_claude ou previous_step.")
            }
            guard region == nil else { throw LightroomError.invalid("« compare » et « region » ne vont pas ensemble.") }
            params["comparer"] = .string(compare == "before_claude" ? "avantClaude" : "etapePrecedente")
        }
        // Le point de mise au point, sur l'aperçu entier ou un zoom (pas un avant/après).
        if compare == nil { params["point_af"] = true }

        let result = try lightroom.send("apercu", params, timeout: region == nil ? 120 : 240)
        var image = try Self.readPreview(result["chemin"]?.string)
        var info = result.object ?? [:]
        info.removeValue(forKey: "chemin")
        info.removeValue(forKey: "chemin_avant")
        // Ce qui sert au point de mise au point, pas à Claude.
        let afToujours = info.removeValue(forKey: "point_af_toujours")?.bool == true
        if var photo = info["photo"]?.object {
            photo.removeValue(forKey: "chemin_original")
            photo.removeValue(forKey: "geometrie")
            photo.removeValue(forKey: "marque")
            info["photo"] = .object(photo)
        }
        if let settings = result["reglages"]?.object {
            let raw = result["echelle_temperature"]?.string?.hasPrefix("kelvins") == true
            info["reglages"] = Self.grouped(settings, onlyChanged: true, raw: raw)
        }
        Self.describeProcessVersion(&info)

        if let region {
            guard let piece = PreviewImages.crop(image, region: region) else {
                throw LightroomError.plugin("Zone trop petite ou aperçu illisible.")
            }
            image = piece.data
            info["zoom"] = [
                "pourcentage": .number(Double(piece.zoom)),
                "pixels": .string("\(piece.width) × \(piece.height)"),
                "zone": ["x": .number(region.minX), "y": .number(region.minY), "width": .number(region.width), "height": .number(region.height)],
            ]
            if let measures = Measurements.analyze(piece.data) {
                var detail = Detail.analyze(piece.data, maxSide: PreviewImages.maxSide)
                detail?.zoom = true
                info["mesures_zone"] = Self.merged(measures.json, detail?.json)
            }
            // Sur un zoom aussi (demandé par Dany le 20 octobre 2026 : un zoom pour voir la mise au
            // point ne la montrait pas) : le point dans l'image entière, et dans la zone s'il y tombe.
            if let af = Self.pointAF(result["photo"], lecteur: lecteurAF) {
                let local = CGPoint(x: (af.point.x - region.minX) / region.width, y: (af.point.y - region.minY) / region.height)
                let dedans = (0...1).contains(local.x) && (0...1).contains(local.y)
                var point = Self.pointAFJSON(af.point, avertissement: af.avertissement)
                point["dans_la_zone"] = .bool(dedans)
                if dedans, let decodee = PreviewImages.image(piece.data) {
                    if let nettete = Detail.nettete(decodee, autour: local) { point["nettete"] = .number((nettete * 10).rounded() / 10) }
                    if args.bool("af_point") == true || afToujours, let marquee = PreviewImages.marquerPoint(decodee, local, manque: af.avertissement) {
                        image = marquee
                        point["carre"] = .string(af.avertissement ? "rouge, sur le zoom" : "vert, sur le zoom")
                    }
                }
                info["point_af"] = .object(point)
            }
        } else if compare != nil {
            let before = try Self.readPreview(result["chemin_avant"]?.string)
            if let measures = Measurements.analyze(before) { info["mesures_avant"] = measures.json }
            if let measures = Measurements.analyze(image) { info["mesures"] = measures.json }
            image = PreviewImages.sideBySide(before, image) ?? image
            info["image"] = "À gauche avant, à droite maintenant."
        } else if let decodee = PreviewImages.image(image) {
            // Un seul décodage du JPEG pour les mesures, le détail et Vision.
            if let measures = Measurements.analyzeScaled(decodee) {
                info["mesures"] = Self.merged(measures.json, Detail.analyze(PreviewImages.scaled(decodee, maxSide: Detail.side))?.json)
            }
            if let vision = VisionAnalysis.analyze(decodee) { info["vision"] = vision.json }
            info["taille_apercu"] = .number(Double(size))
            // Le point de mise au point de l'appareil (Fujifilm) : toujours en chiffres, en carré
            // sur l'image avec af_point (pour noter) ou si l'utilisateur le veut en tout temps
            // (préférence du module). Les mesures sont prises avant le carré.
            if let af = Self.pointAF(result["photo"], lecteur: lecteurAF) {
                var point = Self.pointAFJSON(af.point, avertissement: af.avertissement)
                if let nettete = Detail.nettete(decodee, autour: af.point) { point["nettete"] = .number((nettete * 10).rounded() / 10) }
                if args.bool("af_point") == true || afToujours, let marquee = PreviewImages.marquerPoint(decodee, af.point, manque: af.avertissement) {
                    image = marquee
                    point["carre"] = .string(af.avertissement ? "rouge, sur l'image" : "vert, sur l'image")
                }
                info["point_af"] = .object(point)
            }
        }
        return ToolResult(content: [Self.imageContent(image), .text(JSONCoding.pretty(.object(info)))])
    }

    /// Le point de mise au point dans l'image affichée entière (de 0 à 1), et l'avertissement de
    /// l'appareil.
    static func pointAFJSON(_ point: CGPoint, avertissement: Bool) -> [String: JSONValue] {
        var json: [String: JSONValue] = ["x": .number((Double(point.x) * 1000).rounded() / 1000),
                                         "y": .number((Double(point.y) * 1000).rounded() / 1000)]
        if avertissement { json["appareil"] = "mise au point signalée manquée" }
        return json
    }

    /// Les clés de `extra` ajoutées à l'objet `base`.
    static func merged(_ base: JSONValue, _ extra: JSONValue?) -> JSONValue {
        guard var object = base.object else { return base }
        for (key, value) in extra?.object ?? [:] { object[key] = value }
        return .object(object)
    }

    func measureAngle(_ args: Arguments) throws -> JSONValue {
        func coordinate(_ key: String) throws -> Double {
            guard let value = args.double(key), (0...1).contains(value) else {
                throw LightroomError.invalid("« \(key) » va de 0 à 1 (fraction de l'image affichée).")
            }
            return value
        }
        let from = CGPoint(x: try coordinate("x1"), y: try coordinate("y1"))
        let to = CGPoint(x: try coordinate("x2"), y: try coordinate("y2"))
        var params: [String: JSONValue] = ["taille": .number(Double(Self.defaultPreviewSize)), "cles": []]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        let result = try lightroom.send("apercu", params, timeout: 120)
        let data = try Self.readPreview(result["chemin"]?.string)
        guard let line = LineAngle.measure(data, from: from, to: to) else {
            throw LightroomError.invalid("Segment trop court : choisir deux points éloignés sur la ligne (au moins un cinquième de l'image).")
        }
        func r(_ value: Double, _ step: Double = 0.05) -> JSONValue { .number((value / step).rounded() * step) }
        let current = result["recadrage"]?["angle"]?.double ?? 0
        let proposed = current + line.correction
        var output: [String: JSONValue] = [
            "photo": result["photo"] ?? .null,
            "ligne": .string(line.vertical ? "verticale" : "horizontale"),
            "angle_d_apres_les_points": r(line.pointsAngle),
            "inclinaison": r(line.tilt),
            "angle_de_recadrage_actuel": r(current),
            "crop_angle": r(proposed),
            "base": .string("Degrés. Inclinaison positive : la ligne tourne dans le sens antihoraire (une horizontale monte vers la droite). crop_angle = l'angle de recadrage qui la met d'aplomb : apply_settings avec crop {\"angle\": crop_angle}, en redonnant aspect, size, center_x et center_y si la photo est recadrée. Sous 0,5°, l'inclinaison ne se voit pas."),
        ]
        if let refined = line.refinedAngle {
            output["angle_mesure"] = r(refined)
            output["mesure"] = .string("affinée sur \(line.edgePoints) points du contour (écart moyen \(DevelopCatalogue.format(((line.residual ?? 0) * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")) px)")
        } else {
            output["mesure"] = .string("d'après les deux points seulement : aucun contour net le long du segment, vérifier par un zoom")
        }
        return .object(output)
    }

    func analyzePhotos(_ args: Arguments) throws -> JSONValue {
        var ids = try args.intList("photo_ids") ?? []
        var nonMesurees = 0
        if ids.isEmpty {
            let limit = Self.maxAnalyzedPhotos
            let selection = try lightroom.send(args.bool("selection") == true ? "selection" : "etat",
                                               args.bool("selection") == true ? ["limite": .number(Double(limit))] : [:], timeout: 30)
            if let photos = selection["photos"]?.array {
                ids = photos.compactMap { $0["id"]?.int }
                // Une sélection plus longue que la limite : les photos laissées de côté sont dites.
                nonMesurees = max(0, (selection["total"]?.int ?? ids.count) - ids.count)
            } else if let active = selection["photo_active"]?["id"]?.int {
                ids = [active]
            }
        }
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à mesurer : donner photo_ids ou selection = true.") }
        guard ids.count <= Self.maxAnalyzedPhotos else {
            throw LightroomError.invalid("Au plus \(Self.maxAnalyzedPhotos) photos par appel.")
        }

        // Un seul décodage du JPEG par photo, pour les mesures, le détail, Vision et l'empreinte.
        func measure(_ id: Int) throws -> (description: JSONValue, measures: PhotoMeasurements, image: CGImage) {
            let result = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(Self.analysisSize)), "cles": []], timeout: 120)
            let data = try Self.readPreview(result["chemin"]?.string)
            guard let image = PreviewImages.image(data), let measures = Measurements.analyzeScaled(image) else {
                throw LightroomError.plugin("Aperçu illisible pour la photo \(id).")
            }
            return (result["photo"] ?? .object(["id": .number(Double(id))]), measures, image)
        }

        var reference: (description: JSONValue, measures: PhotoMeasurements, image: CGImage)?
        if let referenceID = args.int("reference_id") { reference = try measure(referenceID) }
        var photos: [JSONValue] = []
        var candidates: [SeriesCandidate] = []
        for id in ids {
            let (description, measures, image) = try measure(id)
            var item: [String: JSONValue] = [
                "id": .number(Double(id)),
                "fichier": description["fichier"] ?? .null,
                "mesures": measures.json,
            ]
            let detail = Detail.analyze(PreviewImages.scaled(image, maxSide: Detail.side))
            if let detail {
                item["nettete"] = ["max": .number((detail.sharpest * 10).rounded() / 10), "lecture": .string(detail.sharpnessReading)]
                item["bruit"] = ["aplats": .number((detail.noise * 100).rounded() / 100), "lecture": .string(detail.noiseReading)]
            }
            let vision = VisionAnalysis.analyze(image)
            if let vision {
                var summary: [String: JSONValue] = ["visages": .number(Double(vision.faces.count))]
                if let best = vision.faces.compactMap(\.quality).max() { summary["qualite_visage_max"] = .number((best * 100).rounded() / 100) }
                if let aesthetics = vision.aesthetics { summary["esthetique"] = .number((aesthetics * 100).rounded() / 100) }
                item["vision"] = .object(summary)
            }
            candidates.append(SeriesCandidate(id: id, detail: detail, vision: vision, featurePrint: VisionAnalysis.featurePrint(image)))
            if let reference, id != args.int("reference_id") {
                item["ecart_avec_reference"] = Measurements.compare(measures, toReference: reference.measures)
            }
            photos.append(.object(item))
        }
        var result: [String: JSONValue] = ["photos": .array(photos)]
        if nonMesurees > 0 {
            result["photos_non_mesurees"] = .number(Double(nonMesurees))
            result["remarque"] = .string("\(nonMesurees) photo(s) de la sélection non mesurée(s) : au plus \(Self.maxAnalyzedPhotos) par appel ; les mesurer par photo_ids, par lots.")
        }
        if let reference {
            result["reference"] = ["fichier": reference.description["fichier"] ?? .null, "mesures": reference.measures.json]
        }
        if candidates.count > 1 {
            let groups = VisionAnalysis.groups(candidates.map(\.featurePrint))
            result["photos_semblables"] = .array(groups.map { members in
                let best = members.max { candidates[$0].score < candidates[$1].score } ?? members[0]
                return [
                    "photos": .array(members.map { .number(Double(candidates[$0].id)) }),
                    "meilleure": .number(Double(candidates[best].id)),
                    "pourquoi": .string(candidates[best].reason),
                ]
            })
            result["base_semblables"] = .string("Photos semblables : même scène d'après Vision (rafale, quasi-doublon, même photo recadrée). « meilleure » : la plus nette, au meilleur visage et à la meilleure note esthétique ; à confirmer à l'œil avant de trier.")
        }
        return .object(result)
    }

    /// Une photo d'une série, pour choisir la meilleure d'un groupe de photos semblables.
    struct SeriesCandidate {
        var id: Int
        var detail: DetailMeasurements?
        var vision: VisionReport?
        var featurePrint: VNFeaturePrintObservation?

        /// Une photo floue passe derrière ; puis la note esthétique (à demi-poids, comme l'ordre de
        /// lecture du tri) et la qualité du meilleur visage, qui départage des photos semblables
        /// (même sujet) : comme `PhotoTriee.scoreDansGroupe`.
        var score: Double {
            let sharp = min((detail?.sharpest ?? 0) / 60, 1)
            let face = vision?.faces.compactMap(\.quality).max() ?? 0
            return sharp + Tri.poidsEsthetique * (vision?.aesthetics ?? 0) + 0.5 * face
        }

        var reason: String {
            var parts: [String] = []
            if let detail { parts.append("netteté \(DevelopCatalogue.format((detail.sharpest).rounded()))") }
            if let face = vision?.faces.compactMap(\.quality).max() { parts.append("visage \(DevelopCatalogue.format((face * 100).rounded() / 100))") }
            if let aesthetics = vision?.aesthetics { parts.append("note esthétique \(DevelopCatalogue.format((aesthetics * 100).rounded() / 100))") }
            return parts.isEmpty ? "aucune mesure" : parts.joined(separator: ", ")
        }
    }

    func getSettings(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = ["cles": .array(DevelopCatalogue.keys.map(JSONValue.string)), "details": true]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        if args.bool("all_keys") == true { params["toutes"] = true }
        var result = try lightroom.send("reglages", params, timeout: 30).object ?? [:]
        if let settings = result["reglages"]?.object {
            result["reglages"] = Self.grouped(settings, onlyChanged: false)
        }
        if let all = result.removeValue(forKey: "tous") {
            result["tous_les_reglages"] = all
        }
        Self.describeProcessVersion(&result)
        return .object(result)
    }

    /// « 11.0 » → « version 5 (11.0) », et ce qu'il faut savoir d'une version ancienne.
    static func describeProcessVersion(_ info: inout [String: JSONValue]) {
        guard let value = info["version_processus"]?.string, let version = DevelopCatalogue.processVersion(value) else { return }
        info["version_processus"] = .string("version \(version) (\(value))")
        let current = DevelopCatalogue.currentProcessVersion.version
        guard version < current else { return }
        info["version_processus_ancienne"] = .string(version < 3
            ? "Version \(version) (2003 ou 2010) : les réglages *2012 et les outils récents ne s'y appliquent pas ; la mettre à jour à la main dans Lightroom (Paramètres › Mettre à jour vers la version de processus actuelle), en comparant : un module ne peut pas convertir ses curseurs."
            : "Version \(version) : process_version = \(current) la met à jour (rendu qui peut changer nettement : preview_settings d'abord, puis l'accord de l'utilisateur).")
    }
}
