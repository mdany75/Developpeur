import Foundation

/// Retouches locales : masques (`add_mask`), taches et yeux rouges (`retouch_spots`). Les
/// positions se donnent dans l'image telle que la montre view_photo (recadrée, tournée), de 0 à
/// 1 depuis le coin haut gauche ; le module les ramène dans le repère du fichier.
extension ToolHandler {
    /// Réglages locaux : nom pour Claude, clé Lightroom, plage pour Claude et facteur vers
    /// l'échelle de Lightroom (−1 à +1 pour presque tous, constaté dans le catalogue).
    static let localAdjustments: [(name: String, key: String, range: ClosedRange<Double>, scale: Double, label: String)] = [
        ("Exposure", "LocalExposure2012", -4...4, 0.25, "exposition en IL"),
        ("Contrast", "LocalContrast2012", -100...100, 0.01, "contraste"),
        ("Highlights", "LocalHighlights2012", -100...100, 0.01, "hautes lumières"),
        ("Shadows", "LocalShadows2012", -100...100, 0.01, "ombres"),
        ("Whites", "LocalWhites2012", -100...100, 0.01, "blancs"),
        ("Blacks", "LocalBlacks2012", -100...100, 0.01, "noirs"),
        ("Texture", "LocalTexture", -100...100, 0.01, "texture"),
        ("Clarity", "LocalClarity2012", -100...100, 0.01, "clarté"),
        ("Dehaze", "LocalDehaze", -100...100, 0.01, "correction du voile"),
        ("Temperature", "LocalTemperature", -100...100, 0.01, "température"),
        ("Tint", "LocalTint", -100...100, 0.01, "teinte"),
        ("Saturation", "LocalSaturation", -100...100, 0.01, "saturation"),
        ("Sharpness", "LocalSharpness", -100...100, 0.01, "netteté"),
        ("Noise", "LocalLuminanceNoise", -100...100, 0.01, "réduction du bruit"),
        ("Moire", "LocalMoire", -100...100, 0.01, "moiré"),
        ("Defringe", "LocalDefringe", -100...100, 0.01, "franges"),
        ("ToningHue", "LocalToningHue", 0...360, 1, "couleur : teinte en degrés"),
        ("ToningSaturation", "LocalToningSaturation", 0...100, 0.01, "couleur : saturation"),
        // Réglages locaux récents, relevés dans Lightroom Classic 15.6 (DevelopLocalizedCommon : rangés
        // de −1 à +1, curseur ×100 pour le grain, ±180° pour la teinte).
        ("Hue", "LocalHue", -180...180, 1.0 / 180, "teinte : décalage en degrés"),
        ("Grain", "LocalGrain", -100...100, 0.01, "grain"),
    ]
    /// Courbe locale par canal : clé de la correction (relevé : un tableau de textes « x,y »).
    static let localCurveKeys: [(channel: String, key: String)] = [("rgb", "MainCurve"), ("red", "RedCurve"), ("green", "GreenCurve"), ("blue", "BlueCurve")]

    /// Masques IA : sous-type et catégorie de Lightroom (relevés dans le catalogue et dans les
    /// paramètres prédéfinis adaptatifs d'Adobe), et nom donné au masque.
    static let aiMasks: [String: (subtype: Int, category: Int?, name: String)] = [
        "subject": (1, nil, "Sujet"),
        "sky": (2, nil, "Ciel"),
        "background": (0, 22, "Arrière-plan"),
        "person_part/face_skin": (3, 2, "Peau du visage"),
        "person_part/iris_pupil": (3, 3, "Iris et pupille"),
        "person_part/body_skin": (3, 4, "Peau du corps"),
        "person_part/hair": (3, 5, "Cheveux"),
        "person_part/lips": (3, 6, "Lèvres"),
        "person_part/facial_hair": (3, 7, "Poils du visage"),
        "person_part/eye_sclera": (3, 8, "Sclère de l'œil"),
        "person_part/eyebrows": (3, 9, "Sourcils"),
        "person_part/clothes": (3, 11, "Vêtements"),
        "person_part/teeth": (3, 12, "Dents"),
        "landscape/architecture": (0, 50001, "Architecture"),
        "landscape/mountains": (0, 50002, "Montagnes"),
        "landscape/artificial_ground": (0, 50003, "Sol artificiel"),
        "landscape/natural_ground": (0, 50004, "Sol naturel"),
        "landscape/vegetation": (0, 50005, "Végétation"),
        "landscape/sky": (0, 50006, "Ciel (paysage)"),
        "landscape/water": (0, 50007, "Eau"),
        "landscape/snow": (0, 50008, "Neige"),
    ]
    static let maxMasks = 6
    /// Composants combinés au premier dans un même masque (en plus de lui).
    static let maxCombined = 4
    /// Modes d'un composant combiné : nom pour Claude, nom pour le module (voir Locaux.combiner).
    static let combineModes: [(name: String, module: String)] = [("add", "ajouter"), ("subtract", "soustraire"), ("intersect", "intersecter")]
    static let maskKinds = ["subject", "sky", "background", "person", "person_part", "landscape", "object", "linear", "radial", "luminance", "color", "depth", "brush"]
    /// Une personne entière (masque Personnes, relevé le 17 octobre 2026) : catégorie 20036.
    static let wholePersonCategory = 20036

    /// Contour progressif d'un masque IA (affinage, Lightroom Classic 15.5) : le curseur de 0 à 100
    /// se range en rayon, Feather. Relevé le 17 octobre 2026 sur un masque fait à la main : 25 → 0,354,
    /// 50 → 1,920, 77 → 5,306, 100 → 10 ; 10 × (curseur/100)^2,381 passe par 50 et 100, et à 2 % près
    /// par les autres (le curseur glissé à la main n'était pas pile sur l'entier affiché).
    static func featherRadius(_ slider: Double) -> Double {
        (10 * pow(min(max(slider, 0), 100) / 100, 2.381) * 1_000_000).rounded() / 1_000_000
    }

    /// Contour (Edge) : le curseur de −50 à +50, rangé divisé par 10 (EdgeShift ; relevé : 50 → 5,
    /// 27 → 2,68, −50 → −5).
    static func edgeShift(_ slider: Double) -> Double {
        min(max(slider, -50), 50) / 10
    }

    /// Les curseurs d'un contour rangé (inverse de featherRadius et edgeShift), pour la liste des
    /// masques de edit_mask : contour_progressif de 0 à 100, contour de −50 à +50.
    static func contourEnCurseurs(_ reponse: JSONValue) -> JSONValue {
        guard var objet = reponse.object, let masques = objet["masques"]?.array else { return reponse }
        objet["masques"] = .array(masques.map { masque in
            guard var m = masque.object, let composants = m["composants"]?.array else { return masque }
            m["composants"] = .array(composants.map { composant in
                guard var c = composant.object else { return composant }
                if let rayon = c["contour_progressif"]?.double {
                    c["contour_progressif"] = .number((100 * pow(min(max(rayon, 0), 10) / 10, 1 / 2.381)).rounded())
                }
                if let decalage = c["contour"]?.double {
                    c["contour"] = .number((decalage * 10).rounded())
                }
                return .object(c)
            })
            return .object(m)
        })
        return .object(objet)
    }
    /// Couleurs prélevées au plus dans une plage de couleurs (comme Lightroom, Maj-clic).
    static let maxColorSamples = 5
    /// Objet désigné par box : un rectangle (Mask/Polygon), comme le mode rectangle de l'outil
    /// Objets ; constaté le 17 octobre 2026 qu'il sélectionne l'objet entier (voir docs/SPEC.md).
    static let objectBoxAsRectangle = true
    static let maxStrokes = 20
    static let maxStrokePoints = 200
    static let maxSpots = 60
    static let maxRedEyes = 10

    var localDefinitions: [JSONValue] {
        var adjustments: [String: JSONValue] = [:]
        for item in Self.localAdjustments {
            adjustments[item.name] = prop("number", "\(item.label.prefix(1).uppercased() + item.label.dropFirst()) (\(Self.format(item.range.lowerBound)) à \(Self.format(item.range.upperBound)))")
        }
        let personParts = Self.aiMasks.keys.filter { $0.hasPrefix("person_part/") }.map { String($0.dropFirst(12)) }.sorted()
        let landscapeParts = Self.aiMasks.keys.filter { $0.hasPrefix("landscape/") }.map { String($0.dropFirst(10)) }.sorted()
        // Ce qui décrit une zone, pour un masque comme pour un composant combiné.
        let area: [String: JSONValue] = [
            "kind": enumProp(Self.maskKinds,
                             "subject, sky, background, person_part, landscape : masques IA calculés par Lightroom ; person : une personne précise (ou l'une de ses parties, avec part), désignée par person ou person_at ; person_part : les parties de toutes les personnes ; object : sélection d'objet par IA, d'après box (son cadre) ou strokes passés sur l'objet ; linear : dégradé linéaire ; radial : dégradé radial ; luminance : plage de luminance ; color : plage de couleurs, d'après samples (couleurs prélevées dans l'image) ; depth : plage de profondeur (photo Portrait d'un iPhone, qui porte une carte de profondeur) ; brush : pinceau, le long de strokes (éclaircir et assombrir à la main)."),
            "part": enumProp(personParts + landscapeParts, "Pour person et person_part : \(personParts.joined(separator: ", ")) (sans part, person prend la personne entière). Pour landscape : \(landscapeParts.joined(separator: ", "))."),
            "person": prop("integer", "Pour person : son numéro dans Lightroom (Personne 1, 2… : de gauche à droite)."),
            "person_at": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2,
                          "description": "Pour person : un point [x, y] sur elle (son visage, que donne Vision dans view_photo), dans l'image telle que la montre view_photo ; le module vérifie après le calcul que le masque porte sur la personne de ce point."],
            "refine": objectProp("Contour d'un masque IA (affinage de Lightroom 15.5) : adoucir ou durcir son bord.", [
                "feather": prop("number", "Contour progressif, de 0 (net) à 100 (très adouci)."),
                "edge": prop("number", "Contour, de −50 (bord resserré vers l'intérieur) à +50 (élargi)."),
            ]),
            "from_x": prop("number", "Dégradé linéaire : point où l'effet est entier (0 à 1, peut sortir de l'image)."),
            "from_y": prop("number", "Dégradé linéaire : point où l'effet est entier."),
            "to_x": prop("number", "Dégradé linéaire : point où l'effet est nul."),
            "to_y": prop("number", "Dégradé linéaire : point où l'effet est nul."),
            "center_x": prop("number", "Dégradé radial : centre (0 à 1)."),
            "center_y": prop("number", "Dégradé radial : centre (0 à 1)."),
            "radius_x": prop("number", "Dégradé radial : demi-largeur, en part de la largeur de l'image (0,01 à 2)."),
            "radius_y": prop("number", "Dégradé radial : demi-hauteur, en part de la hauteur de l'image (défaut : un cercle)."),
            "angle": prop("number", "Dégradé radial : rotation en degrés (défaut 0)."),
            "feather": prop("number", "Contour progressif, de 0 à 100 (dégradé radial : défaut 50 ; plage de luminance ou de profondeur : défaut 10)."),
            "min": prop("number", "Plage de luminance : bas de la plage, de 0 (noir) à 100 (blanc). Plage de profondeur : de 0 (le plus proche) à 100 (le plus loin)."),
            "max": prop("number", "Plage de luminance ou de profondeur : haut de la plage, de 0 à 100."),
            "samples": ["type": "array", "minItems": 1, "maxItems": .number(Double(Self.maxColorSamples)),
                        "items": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2],
                        "description": "Plage de couleurs : les points [x, y] (0 à 1, dans l'image telle que la montre view_photo) où prélever la couleur à garder, comme la pipette de Lightroom ; sur un aplat de la couleur, pas sur un bord."],
            "color_range": prop("number", "Plage de couleurs : étendue des couleurs gardées autour de celles prélevées, de 0 (étroite) à 100 (large) ; défaut 50."),
            "strokes": ["type": "array", "minItems": 1, "maxItems": .number(Double(Self.maxStrokes)),
                        "description": "Pinceau (brush) ou objet (object) : des traits, chacun une ligne brisée dans l'image telle que la montre view_photo. Pour un objet, des traits passés sur lui suffisent ; pour éclaircir ou assombrir, suivre la zone au plus près, vérifié ensuite par un zoom.",
                        "items": objectProp("Un trait de pinceau.", [
                            "points": ["type": "array", "items": ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2],
                                       "minItems": 1, "maxItems": .number(Double(Self.maxStrokePoints)), "description": "Points [x, y] de 0 à 1, dans l'ordre du trait."],
                            "size": prop("number", "Rayon du pinceau, en part de la largeur de l'image (0,001 à 0,2 ; défaut 0,02)."),
                            "feather": prop("number", "Contour progressif, de 0 (net) à 100 (défaut 100)."),
                            "flow": prop("number", "Flux, de 1 à 100 (défaut 100)."),
                        ], required: ["points"])],
            "box": objectProp("Objet : le cadre serré autour de l'objet, dans l'image telle que la montre view_photo ; un trait fin le traverse au milieu, dans sa longueur (il doit tomber sur l'objet). Pour un objet de forme irrégulière, plutôt strokes : un trait fin (size 0,005 à 0,01) posé sur lui seul.", [
                "x": prop("number", "Bord gauche (0 à 1)."), "y": prop("number", "Bord haut (0 à 1)."),
                "width": prop("number", "Largeur (0 à 1)."), "height": prop("number", "Hauteur (0 à 1)."),
            ], required: ["x", "y", "width", "height"]),
            "auto_mask": prop("boolean", "Pinceau : masquage automatique (le trait s'arrête aux contours ; défaut false)."),
        ]
        var componentProperties = area
        componentProperties["mode"] = enumProp(Self.combineModes.map(\.name),
                                               "add : ajouter cette zone au masque ; subtract : la retirer ; intersect : ne garder que ce qui est aussi dans cette zone.")
        componentProperties["invert"] = prop("boolean", "true = inverser ce composant avant de le combiner (subtract d'une zone inversée = intersect).")
        let component = objectProp("Un composant combiné au masque : une zone, décrite comme un masque, sans réglages.", componentProperties,
                                   required: ["mode", "kind"])
        var maskProperties = area
        maskProperties["invert"] = prop("boolean", "true = inverser le masque (par exemple tout sauf le sujet ; pour un dégradé radial, l'extérieur). Avec combine, seulement le premier composant (kind).")
        maskProperties["amount"] = prop("number", "Intensité du masque, de 0 à 100 (défaut 100).")
        maskProperties["name"] = prop("string", "Nom du masque, que Lightroom affiche précédé de « Claude · » (défaut : le type, par exemple « Claude · Ciel »).")
        maskProperties["adjustments"] = ["type": "object", "properties": .object(adjustments), "additionalProperties": false,
                                         "description": "Réglages locaux, sur l'échelle des curseurs du panneau Masque : {\"Exposure\": -0.4, \"Clarity\": 15}. Avec effect, ils s'ajoutent à ceux de l'effet (ou les remplacent, réglage par réglage)."]
        let effects = localEffects.effects
        maskProperties["effect"] = prop("string", "Effet local de Lightroom (menu Effet du panneau Masque), posé sur ce masque à la place de réglages faits à la main : \(effects.isEmpty ? "aucun trouvé sur ce Mac" : effects.map { "« \($0.name) »" + ($0.internalName.isEmpty || $0.internalName == $0.name ? "" : " (\($0.internalName))") }.joined(separator: ", ")). Sur la bonne partie : dents (person_part teeth), iris (iris_pupil), peau (face_skin, body_skin) ; amount en réduit l'intensité.")
        let point: JSONValue = ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2]
        let curve: JSONValue = ["type": "array", "items": point, "minItems": 2, "maxItems": .number(Double(Self.maxCurvePoints)),
                                "description": "Points [entrée, sortie] de 0 à 255, entrée croissante."]
        maskProperties["point_colors"] = ["type": "array", "maxItems": .number(Double(Self.maxPointColors)),
                                          "items": objectProp("Une couleur à modifier dans le masque, comme point_colors d'apply_settings.", Self.pointColorProperties,
                                                              required: ["hue", "saturation", "luminance"]),
                                          "description": "Couleur ponctuelle dans le masque seulement (Point Color du panneau Masque) : une couleur d'un seul objet, sans toucher ailleurs (avec le masque de l'objet)."]
        maskProperties["tone_curve"] = objectProp("Courbe des tonalités du masque, par canal (comme tone_curve d'apply_settings, dans le masque seulement).",
                                                  ["rgb": curve, "red": curve, "green": curve, "blue": curve])
        maskProperties["combine"] = ["type": "array", "items": component, "minItems": 1, "maxItems": .number(Double(Self.maxCombined)),
                                     "description": "Masque combiné : d'autres zones ajoutées, soustraites ou intersectées avec la première (kind), dans l'ordre. Le ciel sans le bâtiment : kind sky, combine [{\"mode\": \"subtract\", \"kind\": \"landscape\", \"part\": \"architecture\"}] ; le sujet limité aux hautes lumières : kind subject, combine [{\"mode\": \"intersect\", \"kind\": \"luminance\", \"min\": 70, \"max\": 100}]."]
        let mask = objectProp("Un masque et ses réglages locaux (adjustments, ou un effet de Lightroom, effect).", maskProperties, required: ["kind"])
        let spot = objectProp("Une tache à effacer.", [
            "x": prop("number", "Centre de la tache (0 à 1, depuis la gauche)."),
            "y": prop("number", "Centre de la tache (0 à 1, depuis le haut)."),
            "radius": prop("number", "Rayon, en part de la largeur de l'image (0,002 à 0,2)."),
            "source_x": prop("number", "Zone source (défaut : à côté, vers le centre de l'image)."),
            "source_y": prop("number", "Zone source."),
            "mode": enumProp(["heal", "clone", "remove"], "heal = corriger (défaut), clone = dupliquer, remove = supprimer (outil Supprimer sans IA générative : Lightroom remplit la zone d'après ce qui l'entoure, sans source à donner ; pour un objet plus gros qu'une poussière)."),
            "feather": prop("number", "Contour progressif, de 0 à 100 (défaut 43)."),
        ], required: ["x", "y", "radius"])
        let eye = objectProp("Un œil rouge à corriger.", [
            "x": prop("number", "Centre de la pupille (0 à 1), vu dans un zoom."),
            "y": prop("number", "Centre de la pupille (0 à 1), vu dans un zoom."),
            "radius": prop("number", "Rayon de la pupille, en part de la largeur de l'image."),
            "pupil_size": prop("number", "Taille de la pupille corrigée, de 0 à 100 (défaut 50)."),
            "darken": prop("number", "Assombrissement, de 0 à 100 (défaut 50)."),
        ], required: ["x", "y", "radius"])
        let previewProperties: [(String, JSONValue)] = [
            ("preview", prop("boolean", "true = proposition visuelle seulement (comme preview_settings) : rien n'est gardé.")),
            ("compare", prop("boolean", "Avec preview : état actuel et proposition côte à côte.")),
            ("size", prop("integer", "Avec preview : grand côté de l'aperçu (défaut \(Self.defaultPreviewSize)).")),
        ]
        return [
            tool("add_mask",
                 "Ajoute des masques avec leurs réglages locaux, en une étape « Claude · <step_name> » : masques IA (sujet, ciel, arrière-plan, parties d'une personne, éléments de paysage, objet désigné par un cadre ou un trait) que Lightroom calcule pour chaque photo, dégradés linéaires et radiaux, plage de luminance, pinceau (dodge and burn, le long de traits), et masques combinés (combine : ajouter, soustraire ou intersecter d'autres zones, par exemple le ciel sans le bâtiment). Les positions se donnent dans l'image telle que la montre view_photo ; le serveur recale celles des dégradés, des traits et des objets sur la correction d'objectif, Upright et la perspective. Effets de Lightroom (effect), courbe du masque (tone_curve). Les masques déjà présents restent ; undo_last retire ceux de l'étape. Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [("masks", ["type": "array", "items": mask, "minItems": 1, "maxItems": .number(Double(Self.maxMasks)),
                                         "description": "Masques à ajouter."])] + writeProperties + targetProperties + previewProperties,
                 required: ["masks", "step_name"]),
            tool("edit_mask",
                 "Reprend un masque de la photo sans défaire toute l'étape qui l'a posé : list (ses masques, numérotés, avec leurs composants : IA calculé ou non, personne, contour), hide et show (l'œil du panneau Masques), remove, duplicate (une copie avec les mêmes réglages locaux ; invert = le reste de l'image), refine (contour d'un masque IA : feather, edge), recompute (Lightroom recalcule un masque IA mal posé, comme « Tout mettre à jour »), remove_empty (les masques IA qui n'ont rien trouvé). Chaque écriture est une étape « Claude · <step_name> » que undo_last défait. Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("action", enumProp(Self.maskActions.map(\.name), "Ce qu'il faut faire (défaut : list).")),
                    ("mask", ["type": ["string", "integer"], "description": "Le masque : son numéro dans list (à partir de 1) ou son nom (« Claude · Ciel » ou « Ciel »)."]),
                    ("invert", prop("boolean", "duplicate : inverser la copie (le reste de l'image).")),
                    ("name", prop("string", "duplicate : nom de la copie (défaut : le nom d'origine suivi de « (copie) »).")),
                    ("feather", prop("number", "refine : contour progressif, de 0 à 100.")),
                    ("edge", prop("number", "refine : contour, de −50 à +50.")),
                 ] + writeProperties,
                 required: []),
            tool("retouch_spots",
                 "Efface des taches (poussières du capteur, petits défauts) et corrige des yeux rouges sur une photo, en une étape « Claude · <step_name> ». Positions dans l'image telle que la montre view_photo ; pour viser juste, regarder d'abord la zone avec view_photo et region (zoom). Yeux rouges : seulement des pupilles rouges vues dans un zoom (sur une pupille sombre, la correction grise l'iris et la paupière), au centre de la pupille vu dans le zoom (Vision peut s'en écarter de quelques pixels sur des yeux plissés), au rayon que donne Vision, puis vérifier par un zoom. Le serveur recale les positions sur la correction d'objectif, Upright et la perspective (deux rendus de plus la première fois). Les retouches déjà présentes restent. Respecte le mode « Proposer d'abord » (confirm).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("spots", ["type": "array", "items": spot, "maxItems": .number(Double(Self.maxSpots)), "description": "Taches à effacer."]),
                    ("red_eyes", ["type": "array", "items": eye, "maxItems": .number(Double(Self.maxRedEyes)), "description": "Yeux rouges à corriger."]),
                 ] + writeProperties + previewProperties,
                 required: ["step_name"]),
        ]
    }

    /// Actions d'edit_mask : nom pour Claude, pour le module, et si elles désignent un masque.
    static let maskActions: [(name: String, module: String, needsMask: Bool)] = [
        ("list", "lister", false), ("hide", "masquer", true), ("show", "afficher", true), ("remove", "retirer", true),
        ("duplicate", "dupliquer", true), ("refine", "affiner", true), ("recompute", "recalculer", true), ("remove_empty", "retirer_vides", false),
    ]

    // MARK: Exécution

    func editMask(_ args: Arguments) throws -> JSONValue {
        let wanted = args.string("action") ?? "list"
        guard let action = Self.maskActions.first(where: { $0.name == wanted }) else {
            throw LightroomError.invalid("« action » : \(Self.maskActions.map(\.name).joined(separator: ", ")).")
        }
        var params: [String: JSONValue] = ["action": .string(action.module)]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        if action.needsMask {
            if let number = args.raw["mask"]?.int {
                params["masque"] = .number(Double(number))
            } else if let name = args.string("mask")?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                params["masque"] = .string(name)
            } else {
                throw LightroomError.invalid("« mask » : le numéro du masque (edit_mask avec list) ou son nom.")
            }
        }
        switch action.name {
        case "duplicate":
            params["inverser"] = .bool(args.bool("invert") ?? false)
            if let name = args.string("name").map(Self.withoutClaudePrefix), !name.isEmpty { params["nom"] = .string(String(name.prefix(40))) }
        case "refine":
            guard args.has("feather") || args.has("edge") else {
                throw LightroomError.invalid("« refine » : feather (0 à 100) ou edge (−50 à +50).")
            }
            try verifierVersion([("refine", "15.5")])
            if args.has("feather") {
                guard let feather = args.double("feather"), (0...100).contains(feather) else { throw LightroomError.invalid("« feather » va de 0 à 100.") }
                params["contour"] = .number(Self.featherRadius(feather))
            }
            if args.has("edge") {
                guard let edge = args.double("edge"), (-50...50).contains(edge) else { throw LightroomError.invalid("« edge » va de −50 à +50.") }
                params["decalage"] = .number(Self.edgeShift(edge))
            }
        default:
            break
        }
        if action.name != "list" {
            params.merge(writeParameters(args, defaultStep: "masques")) { _, new in new }
            params["libelles"] = DevelopCatalogue.labels(for: ["MaskGroupBasedCorrections"])
        }
        return Self.withLabels(Self.contourEnCurseurs(try lightroom.send("masques", params, timeout: 120)))
    }

    func addMask(_ args: Arguments) throws -> ToolResult {
        guard let list = args.array("masks"), (1...Self.maxMasks).contains(list.count) else {
            throw LightroomError.invalid("« masks » : de 1 à \(Self.maxMasks) masques.")
        }
        var masks = try list.enumerated().map { try maskParameter($1, index: $0) }
        if masks.contains(where: Self.affine) {
            try verifierVersion([("refine", "15.5")])
        }
        if masks.contains(where: Self.aDesCouleurs) || masks.contains(where: Self.aDesPersonnes) {
            masks = try prelever(masks, args)
        }
        var params: [String: JSONValue] = ["masques": .array(masks), "libelles": DevelopCatalogue.labels(for: ["MaskGroupBasedCorrections"])]
        // Ce que pose chaque effet local, sur l'échelle des curseurs.
        var effectNotes: [JSONValue] = []
        for item in list {
            if let text = item["effect"]?.string, let effect = localEffects.effect(named: text) {
                effectNotes.append(.string("Effet « \(effect.name) » : \(Self.describe(effect))."))
            }
        }
        var cible = try targets(args)
        if args.bool("preview") == true {
            guard args.bool("selection") != true, (try args.intList("photo_ids") ?? []).count <= 1 else {
                throw LightroomError.invalid("« preview » montre une seule photo : donner un seul photo_ids (ou la photo active), pas selection.")
            }
            cible = [:]
            if let id = try args.intList("photo_ids")?.first { cible["photo"] = .number(Double(id)) }
        }
        // Dégradés : positions à recaler sur la correction d'objectif et la perspective.
        var notes = effectNotes
        if masks.contains(where: Self.positionne) {
            let (grilles, remarques) = recalages(cible)
            params["recalages"] = grilles
            notes += remarques
        }
        params.merge(cible) { _, new in new }
        if args.bool("preview") == true {
            params["action"] = "masquer"
            params["etape"] = .string(args.string("step_name") ?? "masques")
            return try preview(params, args: args, notes: notes)
        }
        params.merge(writeParameters(args, defaultStep: "masques")) { _, new in new }
        return json(Self.withLabels(try lightroom.send("masquer", params, timeout: 180), notes: notes))
    }

    func retouchSpots(_ args: Arguments) throws -> ToolResult {
        let spots = args.array("spots") ?? []
        let eyes = args.array("red_eyes") ?? []
        guard !spots.isEmpty || !eyes.isEmpty else {
            throw LightroomError.invalid("Rien à retoucher : donner spots ou red_eyes.")
        }
        guard spots.count <= Self.maxSpots, eyes.count <= Self.maxRedEyes else {
            throw LightroomError.invalid("Au plus \(Self.maxSpots) taches et \(Self.maxRedEyes) yeux par appel.")
        }
        var params: [String: JSONValue] = [
            "taches": .array(try spots.enumerated().map { try spotParameter($1, index: $0) }),
            "yeux": .array(try eyes.enumerated().map { try redEyeParameter($1, index: $0) }),
            "libelles": DevelopCatalogue.labels(for: ["RetouchAreas", "RedEyeInfo"]),
        ]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        let (grilles, notes) = recalages(params["photo"].map { ["photo": $0] } ?? [:])
        params["recalages"] = grilles
        if args.bool("preview") == true {
            params["action"] = "retoucher"
            params["etape"] = .string(args.string("step_name") ?? "taches")
            return try preview(params, args: args, notes: notes)
        }
        params.merge(writeParameters(args, defaultStep: "taches")) { _, new in new }
        return json(Self.withLabels(try lightroom.send("retoucher", params, timeout: 120), notes: notes))
    }

    /// Les réglages d'un effet local, sur l'échelle des curseurs : « exposition +0,4 IL, saturation −60 ».
    static func describe(_ effect: LocalEffect) -> String {
        let parts = localAdjustments.compactMap { item -> String? in
            guard let value = effect.locaux[item.key] else { return nil }
            let shown = (value / item.scale * 100).rounded() / 100
            let text = (shown > 0 && item.name != "ToningHue" ? "+" : "") + format(shown).replacingOccurrences(of: ".", with: ",")
            let label = item.label.replacingOccurrences(of: " en IL", with: "").replacingOccurrences(of: " en degrés", with: "")
            return "\(label) \(text)\(item.name == "Exposure" ? " IL" : "")"
        }
        return parts.isEmpty ? "aucun réglage" : parts.joined(separator: ", ")
    }

    /// Un masque (ou l'un de ses composants) est-il une plage de couleurs ?
    static func aDesCouleurs(_ masque: JSONValue) -> Bool {
        ([masque] + (masque["composants"]?.array ?? [])).contains { $0["type"]?.string == "couleur" }
    }

    /// Le modèle de chaque couleur prélevée, mesuré sur l'aperçu de la photo (moyenne de 7 × 7 px à
    /// 1024 px de grand côté). Une plage de couleurs se prélève sur une seule photo.
    func prelever(_ masks: [JSONValue], _ args: Arguments) throws -> [JSONValue] {
        let ids = try args.intList("photo_ids") ?? []
        guard ids.count <= 1, args.bool("selection") != true else {
            throw LightroomError.invalid("Une plage de couleurs se prélève sur une seule photo : donner un seul photo_ids (ou la photo active).")
        }
        var params: [String: JSONValue] = ["taille": .number(Double(Detail.side)), "cles": []]
        if let id = ids.first { params["photo"] = .number(Double(id)) }
        let apercu = try lightroom.send("apercu", params, timeout: 120)
        guard let image = PreviewImages.image(try Self.readPreview(apercu["chemin"]?.string)) else {
            throw LightroomError.plugin("Aperçu illisible : couleur ou personnes impossibles à relever.")
        }
        var personnes: [CGRect]?
        func avecModeles(_ zone: JSONValue) throws -> JSONValue {
            if zone["type"]?.string == "personne" {
                if personnes == nil { personnes = detecterPersonnes(image) }
                return try Self.avecCadres(zone, personnes ?? [])
            }
            guard var objet = zone.object, objet["type"]?.string == "couleur", let points = objet["prelevements"]?.array else { return zone }
            objet["prelevements"] = .array(try points.map { point in
                guard let x = point["x"]?.double, let y = point["y"]?.double,
                      let (r, g, b) = ModeleCouleur.moyenne(image, x: x, y: y) else {
                    throw LightroomError.invalid("Couleur impossible à prélever en \(JSONCoding.line(point)).")
                }
                let modele = ModeleCouleur.modele(r, g, b)
                return ["x": .number(x), "y": .number(y), "modele": .array(modele.map(JSONValue.number))]
            })
            return .object(objet)
        }
        return try masks.map { masque in
            var objet = try avecModeles(masque).object ?? [:]
            if let composants = objet["composants"]?.array { objet["composants"] = .array(try composants.map(avecModeles)) }
            return .object(objet)
        }
    }

    /// Un masque (ou l'un de ses composants) a-t-il une position dans l'image : dégradé linéaire
    /// ou radial, pinceau, objet, personne précise (ses cadres) ? Les autres masques IA et la plage
    /// de luminance n'en ont pas.
    static func positionne(_ masque: JSONValue) -> Bool {
        ([masque] + (masque["composants"]?.array ?? [])).contains { zone in
            ["lineaire", "radial", "pinceau", "objet", "couleur", "personne"].contains(zone["type"]?.string)
        }
    }

    static func aDesPersonnes(_ masque: JSONValue) -> Bool {
        ([masque] + (masque["composants"]?.array ?? [])).contains { $0["type"]?.string == "personne" }
    }

    /// Masque d'une personne précise : Lightroom ne le calcule que s'il porte aussi les cadres de
    /// toutes les personnes (InstanceBounds), dans l'ordre des numéros ; sans eux, il retire
    /// InstanceIDs et calcule autre chose (constaté le 18 octobre 2026 : un seul cadre, ou deux
    /// cadres de toute l'image, ne suffisent pas ; six cadres approchés de 0,02 donnent le même
    /// masque qu'à la main). Les cadres viennent de Vision, sur l'aperçu ; un point donné choisit
    /// la personne dont le cadre le contient (le plus petit), ou la plus proche.
    static func avecCadres(_ zone: JSONValue, _ personnes: [CGRect]) throws -> JSONValue {
        guard var objet = zone.object else { return zone }
        guard !personnes.isEmpty else {
            throw LightroomError.invalid("Vision ne trouve personne sur cette photo : un masque d'une personne précise se fait alors à la main (Masquage › Personnes), ou person_part pour toutes.")
        }
        if let x = objet["x"]?.double, let y = objet["y"]?.double {
            let point = CGPoint(x: x, y: y)
            let dedans = personnes.indices.filter { personnes[$0].contains(point) }
            let choisie = dedans.min { personnes[$0].width * personnes[$0].height < personnes[$1].width * personnes[$1].height }
                ?? personnes.indices.min { hypot(personnes[$0].midX - x, personnes[$0].midY - y) < hypot(personnes[$1].midX - x, personnes[$1].midY - y) }!
            objet["numero"] = .number(Double(choisie + 1))
        }
        let numero = objet["numero"]?.int ?? 1
        guard numero <= personnes.count else {
            throw LightroomError.invalid("Personne \(numero) : Vision ne trouve que \(personnes.count) personne\(personnes.count > 1 ? "s" : "") sur cette photo (numérotées de gauche à droite).")
        }
        func r(_ v: CGFloat) -> JSONValue { .number((Double(v) * 1_000_000).rounded() / 1_000_000) }
        objet["cadres"] = .array(personnes.map { ["Left": r($0.minX), "Top": r($0.minY), "Right": r($0.maxX), "Bottom": r($0.maxY)] })
        // Une seule personne : Lightroom range son masque sans numéro ni cadres (constaté le
        // 20 octobre 2026 sur un portrait : fait à la main, et envoyé ainsi, même masque) ; les
        // cadres servent encore au module à vérifier où il l'a calculé.
        if personnes.count == 1 {
            objet["seule"] = true
        }
        return .object(objet)
    }

    /// Un masque (ou l'un de ses composants) a-t-il un contour à affiner (Lightroom 15.5) ?
    static func affine(_ masque: JSONValue) -> Bool {
        ([masque] + (masque["composants"]?.array ?? [])).contains { $0["affinage"] != nil }
    }

    // MARK: Vérification des paramètres

    private func number(_ object: [String: JSONValue], _ key: String, _ range: ClosedRange<Double>, _ path: String,
                        default fallback: Double? = nil) throws -> Double? {
        guard let raw = object[key], !raw.isNull else { return fallback }
        guard let value = raw.double, value.isFinite, range.contains(value) else {
            throw LightroomError.invalid("« \(path).\(key) » va de \(Self.format(range.lowerBound)) à \(Self.format(range.upperBound)).")
        }
        return value
    }

    private func required(_ object: [String: JSONValue], _ key: String, _ range: ClosedRange<Double>, _ path: String) throws -> Double {
        guard let value = try number(object, key, range, path) else {
            throw LightroomError.invalid("« \(path).\(key) » manque.")
        }
        return value
    }

    func maskParameter(_ value: JSONValue, index: Int) throws -> JSONValue {
        let path = "masks[\(index)]"
        guard let mask = value.object, let kind = mask["kind"]?.string else {
            throw LightroomError.invalid("« \(path) » doit être un objet avec kind et adjustments.")
        }
        var locals: [String: JSONValue] = [:]
        var effectName: String?
        if let raw = mask["effect"], !raw.isNull {
            guard let text = raw.string, let effect = localEffects.effect(named: text) else {
                let names = localEffects.effects.map(\.name)
                throw LightroomError.invalid("« \(path).effect » : effet local inconnu \(JSONCoding.line(raw)) (\(names.isEmpty ? "aucun effet trouvé sur ce Mac" : names.joined(separator: ", "))).")
            }
            for (key, value) in effect.locaux { locals[key] = .number(value) }
            effectName = effect.name
        }
        let adjustments = mask["adjustments"]?.object ?? [:]
        if let raw = mask["tone_curve"], !raw.isNull {
            guard let channels = raw.object, !channels.isEmpty else {
                throw LightroomError.invalid("« \(path).tone_curve » doit être un objet par canal, par exemple {\"rgb\": [[0,0],[64,56],[192,202],[255,255]]}.")
            }
            for (channel, points) in channels {
                guard let key = Self.localCurveKeys.first(where: { $0.channel == channel })?.key else {
                    throw LightroomError.invalid("« \(path).tone_curve » : canal inconnu « \(channel) » (rgb, red, green ou blue).")
                }
                let pairs = try Self.curvePoints(points, path: "\(path).tone_curve.\(channel)")
                locals[key] = .array(pairs.map { .string("\(Int($0.0)),\(Int($0.1))") })
            }
        }
        var colors: JSONValue?
        if let raw = mask["point_colors"], !raw.isNull {
            colors = try pointColors(raw, path: "\(path).point_colors")
            if colors?.array?.isEmpty == true { colors = nil }
        }
        guard !adjustments.isEmpty || effectName != nil || colors != nil || locals.keys.contains(where: { $0.hasSuffix("Curve") }) else {
            throw LightroomError.invalid("« \(path).adjustments » : au moins un réglage local, par exemple {\"Exposure\": -0.4} (ou un effet, effect, une courbe, tone_curve, ou des couleurs ponctuelles, point_colors).")
        }
        for (name, raw) in adjustments {
            guard let item = Self.localAdjustments.first(where: { $0.name == name }) else {
                throw LightroomError.invalid("« \(path).adjustments » : réglage inconnu « \(name) » (\(Self.localAdjustments.map(\.name).joined(separator: ", "))).")
            }
            guard let number = raw.double, item.range.contains(number) else {
                throw LightroomError.invalid("« \(path).adjustments.\(name) » va de \(Self.format(item.range.lowerBound)) à \(Self.format(item.range.upperBound)).")
            }
            locals[item.key] = .number(number * item.scale)
        }

        var (result, name) = try areaParameter(mask, kind: kind, path: path)
        result["locaux"] = .object(locals)
        if let colors { result["couleurs_ponctuelles"] = colors }
        result["inverser"] = .bool(mask["invert"]?.bool ?? false)
        result["quantite"] = .number((try number(mask, "amount", 0...100, path, default: 100) ?? 100) / 100)
        if let effectName { name = effectName }
        if let given = mask["name"]?.string.map(Self.withoutClaudePrefix), !given.isEmpty {
            name = given
        }
        result["nom"] = .string("Claude · " + String(name.prefix(40)))
        if let combine = mask["combine"], !combine.isNull {
            guard let list = combine.array, (1...Self.maxCombined).contains(list.count) else {
                throw LightroomError.invalid("« \(path).combine » : de 1 à \(Self.maxCombined) composants.")
            }
            result["composants"] = .array(try list.enumerated().map { try combinedParameter($1, path: "\(path).combine[\($0)]") })
        }
        return .object(result)
    }

    /// Un composant combiné au premier : sa zone, son mode et son inversion.
    func combinedParameter(_ value: JSONValue, path: String) throws -> JSONValue {
        guard let component = value.object, let kind = component["kind"]?.string else {
            throw LightroomError.invalid("« \(path) » doit être un objet avec mode et kind.")
        }
        guard let mode = Self.combineModes.first(where: { $0.name == component["mode"]?.string }) else {
            throw LightroomError.invalid("« \(path).mode » : \(Self.combineModes.map(\.name).joined(separator: ", ")).")
        }
        var (result, name) = try areaParameter(component, kind: kind, path: path)
        result["mode"] = .string(mode.module)
        result["inverser"] = .bool(component["invert"]?.bool ?? false)
        result["nom"] = .string(name)
        return .object(result)
    }

    /// La zone d'un masque ou d'un composant, telle que l'attend le module, et son nom par défaut.
    func areaParameter(_ mask: [String: JSONValue], kind: String, path: String) throws -> ([String: JSONValue], String) {
        var result: [String: JSONValue] = [:]
        let name: String
        switch kind {
        case "person":
            // Une personne précise (relevé le 17 octobre 2026 : sous-type 0, catégorie 20036 pour la
            // personne entière, ou celle d'une partie ; InstanceIDs = le numéro moins un).
            let number = mask["person"]?.int
            var at: (Double, Double)?
            if let raw = mask["person_at"], !raw.isNull {
                guard let xy = raw.array, xy.count == 2, let x = xy[0].double, let y = xy[1].double, (0...1).contains(x), (0...1).contains(y) else {
                    throw LightroomError.invalid("« \(path).person_at » : [x, y], de 0 à 1.")
                }
                at = (x, y)
            }
            guard number != nil || at != nil else {
                throw LightroomError.invalid("« \(path) » : person (son numéro dans Lightroom : Personne 1, 2… de gauche à droite) ou person_at [x, y] (un point sur elle, par exemple son visage d'après view_photo).")
            }
            if let number, !(1...30).contains(number) {
                throw LightroomError.invalid("« \(path).person » va de 1 à 30.")
            }
            result["type"] = "personne"
            result["numero"] = .number(Double(number ?? 1))
            if let at {
                result["x"] = .number(at.0)
                result["y"] = .number(at.1)
            }
            var label = number.map { "Personne \($0)" } ?? "Personne désignée"
            if let part = mask["part"]?.string {
                guard let ai = Self.aiMasks["person_part/" + part] else {
                    let parts = Self.aiMasks.keys.filter { $0.hasPrefix("person_part/") }.map { String($0.dropFirst(12)) }.sorted()
                    throw LightroomError.invalid("« \(path).part » : pour person, \(parts.joined(separator: ", ")).")
                }
                result["categorie"] = .number(Double(ai.category ?? Self.wholePersonCategory))
                label += " - " + ai.name
            } else {
                result["categorie"] = .number(Double(Self.wholePersonCategory))
            }
            name = label
        case "subject", "sky", "background", "person_part", "landscape":
            var key = kind
            if kind == "person_part" || kind == "landscape" {
                guard let part = mask["part"]?.string, Self.aiMasks[kind + "/" + part] != nil else {
                    let parts = Self.aiMasks.keys.filter { $0.hasPrefix(kind + "/") }.map { String($0.dropFirst(kind.count + 1)) }.sorted()
                    throw LightroomError.invalid("« \(path).part » : pour \(kind), \(parts.joined(separator: ", ")).")
                }
                key += "/" + part
            }
            let ai = Self.aiMasks[key]!
            result["type"] = "ia"
            result["soustype"] = .number(Double(ai.subtype))
            if let category = ai.category { result["categorie"] = .number(Double(category)) }
            name = ai.name
        case "linear":
            result["type"] = "lineaire"
            for (from, to) in [("from_x", "de_x"), ("from_y", "de_y"), ("to_x", "a_x"), ("to_y", "a_y")] {
                result[to] = .number(try required(mask, from, -1...2, path))
            }
            name = "Dégradé linéaire"
        case "radial":
            result["type"] = "radial"
            result["centre_x"] = .number(try required(mask, "center_x", -0.5...1.5, path))
            result["centre_y"] = .number(try required(mask, "center_y", -0.5...1.5, path))
            result["rayon_x"] = .number(try required(mask, "radius_x", 0.01...2, path))
            if let ry = try number(mask, "radius_y", 0.01...2, path) { result["rayon_y"] = .number(ry) }
            result["angle"] = .number(try number(mask, "angle", -180...180, path, default: 0) ?? 0)
            result["fondu"] = .number(try number(mask, "feather", 0...100, path, default: 50) ?? 50)
            name = "Dégradé radial"
        case "luminance":
            let low = try required(mask, "min", 0...100, path), high = try required(mask, "max", 0...100, path)
            guard low < high else { throw LightroomError.invalid("« \(path) » : min doit être plus petit que max.") }
            result["type"] = "luminance"
            result["min"] = .number(low / 100)
            result["max"] = .number(high / 100)
            result["fondu"] = .number((try number(mask, "feather", 0...100, path, default: 10) ?? 10) / 100)
            name = "Plage de luminance"
        case "color":
            guard let raw = mask["samples"]?.array, (1...Self.maxColorSamples).contains(raw.count) else {
                throw LightroomError.invalid("« \(path).samples » : de 1 à \(Self.maxColorSamples) points [x, y] où prélever la couleur.")
            }
            result["type"] = "couleur"
            result["prelevements"] = .array(try raw.map { point in
                guard let xy = point.array, xy.count == 2, let x = xy[0].double, let y = xy[1].double, (0...1).contains(x), (0...1).contains(y) else {
                    throw LightroomError.invalid("« \(path).samples » : chaque point est [x, y], de 0 à 1.")
                }
                return ["x": .number(x), "y": .number(y)]
            })
            result["etendue"] = .number((try number(mask, "color_range", 0...100, path, default: 50) ?? 50) / 100)
            name = "Plage de couleurs"
        case "depth":
            let low = try required(mask, "min", 0...100, path), high = try required(mask, "max", 0...100, path)
            guard low < high else { throw LightroomError.invalid("« \(path) » : min doit être plus petit que max.") }
            result["type"] = "profondeur"
            result["min"] = .number(low / 100)
            result["max"] = .number(high / 100)
            result["fondu"] = .number((try number(mask, "feather", 0...100, path, default: 10) ?? 10) / 100)
            name = "Plage de profondeur"
        case "brush":
            result["type"] = "pinceau"
            result["traits"] = .array(try strokesParameter(mask, path: path, required: true))
            result["auto"] = .bool(mask["auto_mask"]?.bool ?? false)
            name = "Pinceau"
        case "object":
            result["type"] = "objet"
            var traits = try strokesParameter(mask, path: path, required: false)
            if let raw = mask["box"], !raw.isNull {
                guard let box = raw.object else { throw LightroomError.invalid("« \(path).box » : {x, y, width, height}.") }
                let x = try required(box, "x", 0...1, path + ".box"), y = try required(box, "y", 0...1, path + ".box")
                let width = try required(box, "width", 0.005...1, path + ".box"), height = try required(box, "height", 0.005...1, path + ".box")
                if Self.objectBoxAsRectangle && traits.isEmpty {
                    result["rectangle"] = ["x": .number(x), "y": .number(y), "largeur": .number(min(width, 1 - x)), "hauteur": .number(min(height, 1 - y))]
                } else {
                    traits.append(Self.boxStroke(x: x, y: y, width: width, height: height))
                }
            }
            guard !traits.isEmpty || result["rectangle"] != nil else {
                throw LightroomError.invalid("« \(path) » : un objet se désigne par box (son cadre) ou strokes (des traits passés sur lui).")
            }
            if !traits.isEmpty { result["traits"] = .array(traits) }
            name = "Objet"
        default:
            throw LightroomError.invalid("« \(path).kind » : \(Self.maskKinds.joined(separator: ", ")).")
        }
        if let raw = mask["refine"], !raw.isNull {
            result["affinage"] = try refineParameter(raw, kind: kind, path: path + ".refine")
        }
        return (result, name)
    }

    /// Le contour d'un masque IA (refine), converti pour Lightroom : {contour, decalage}.
    func refineParameter(_ raw: JSONValue, kind: String, path: String) throws -> JSONValue {
        guard ["subject", "sky", "background", "person", "person_part", "landscape", "object"].contains(kind) else {
            throw LightroomError.invalid("« \(path) » : seuls les masques IA (sujet, ciel, arrière-plan, personnes, paysage, objet) ont un contour à affiner.")
        }
        guard let refine = raw.object, refine["feather"] != nil || refine["edge"] != nil else {
            throw LightroomError.invalid("« \(path) » : {feather (0 à 100), edge (−50 à +50)}.")
        }
        var result: [String: JSONValue] = [:]
        if let feather = try number(refine, "feather", 0...100, path) { result["contour"] = .number(Self.featherRadius(feather)) }
        if let edge = try number(refine, "edge", -50...50, path) { result["decalage"] = .number(Self.edgeShift(edge)) }
        return .object(result)
    }

    /// Les traits d'un pinceau ou d'un objet, tels que les attend le module : points, rayon (part de
    /// la largeur de l'image), dureté (1 − contour progressif) et flux, de 0 à 1.
    func strokesParameter(_ mask: [String: JSONValue], path: String, required needed: Bool) throws -> [JSONValue] {
        guard let raw = mask["strokes"], !raw.isNull else {
            if needed { throw LightroomError.invalid("« \(path).strokes » : au moins un trait {points: [[x, y], …]}.") }
            return []
        }
        guard let list = raw.array, (1...Self.maxStrokes).contains(list.count) else {
            throw LightroomError.invalid("« \(path).strokes » : de 1 à \(Self.maxStrokes) traits.")
        }
        return try list.enumerated().map { index, item in
            let where_ = "\(path).strokes[\(index)]"
            guard let stroke = item.object, let points = stroke["points"]?.array, (1...Self.maxStrokePoints).contains(points.count) else {
                throw LightroomError.invalid("« \(where_).points » : de 1 à \(Self.maxStrokePoints) points [x, y].")
            }
            let pairs: [JSONValue] = try points.map { point in
                guard let xy = point.array, xy.count == 2, let x = xy[0].double, let y = xy[1].double, (0...1).contains(x), (0...1).contains(y) else {
                    throw LightroomError.invalid("« \(where_).points » : chaque point est [x, y], de 0 à 1.")
                }
                return [.number(x), .number(y)]
            }
            return [
                "points": .array(pairs),
                "rayon": .number(try number(stroke, "size", 0.001...0.2, where_, default: 0.02) ?? 0.02),
                "durete": .number(1 - (try number(stroke, "feather", 0...100, where_, default: 100) ?? 100) / 100),
                "flux": .number((try number(stroke, "flow", 1...100, where_, default: 100) ?? 100) / 100),
            ]
        }
    }

    /// Le trait qui désigne l'objet d'un cadre : fin, dans sa longueur, de 25 % à 75 %, au milieu.
    /// Constaté dans Lightroom Classic 15.6 (17 octobre 2026) : un trait de rayon 0,05 au milieu d'un
    /// cadre qui prenait aussi le fond n'a rien donné (ErrorReason 1) ; un trait fin (0,007, comme
    /// celui d'un masque Objets fait à la main) le long d'une coque de bateau l'a sélectionnée.
    static func boxStroke(x: Double, y: Double, width: Double, height: Double) -> JSONValue {
        let horizontal = width >= height
        let cx = x + width / 2, cy = y + height / 2
        let points: [JSONValue] = horizontal
            ? [[.number(x + width * 0.25), .number(cy)], [.number(x + width * 0.75), .number(cy)]]
            : [[.number(cx), .number(y + height * 0.25)], [.number(cx), .number(y + height * 0.75)]]
        // Petite dimension en part de la largeur de l'image (supposée 3:2 au plus large).
        let radius = max(0.003, min(0.01, (horizontal ? height / 1.5 : width) / 8))
        return ["points": .array(points), "rayon": .number(radius), "durete": 1, "flux": 1]
    }

    /// Nom donné sans le préfixe « Claude · », que le serveur ajoute lui-même : « Claude · Ciel »,
    /// ou « Claude · Claude · Ciel » relu d'un masque de la version 1.3, donne « Ciel ».
    static func withoutClaudePrefix(_ name: String) -> String {
        var rest = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while let range = rest.range(of: #"^claude\s*·\s*"#, options: [.regularExpression, .caseInsensitive]) {
            rest.removeSubrange(range)
        }
        return rest
    }

    func spotParameter(_ value: JSONValue, index: Int) throws -> JSONValue {
        let path = "spots[\(index)]"
        guard let spot = value.object else { throw LightroomError.invalid("« \(path) » doit être un objet {x, y, radius}.") }
        var result: [String: JSONValue] = [
            "x": .number(try required(spot, "x", 0...1, path)),
            "y": .number(try required(spot, "y", 0...1, path)),
            "rayon": .number(try required(spot, "radius", 0.002...0.2, path)),
            "fondu": .number((try number(spot, "feather", 0...100, path, default: 43) ?? 43) / 100),
            "mode": .string(["clone", "remove"].contains(spot["mode"]?.string ?? "") ? spot["mode"]!.string! : "heal"),
        ]
        if spot["source_x"] != nil || spot["source_y"] != nil {
            result["source_x"] = .number(try required(spot, "source_x", 0...1, path))
            result["source_y"] = .number(try required(spot, "source_y", 0...1, path))
        }
        return .object(result)
    }

    func redEyeParameter(_ value: JSONValue, index: Int) throws -> JSONValue {
        let path = "red_eyes[\(index)]"
        guard let eye = value.object else { throw LightroomError.invalid("« \(path) » doit être un objet {x, y, radius}.") }
        return [
            "x": .number(try required(eye, "x", 0...1, path)),
            "y": .number(try required(eye, "y", 0...1, path)),
            "rayon": .number(try required(eye, "radius", 0.001...0.1, path)),
            "pupille": .number((try number(eye, "pupil_size", 0...100, path, default: 50) ?? 50) / 100),
            "assombrir": .number((try number(eye, "darken", 0...100, path, default: 50) ?? 50) / 100),
        ]
    }
}
