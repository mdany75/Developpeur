import Foundation

/// Retouche globale : `apply_settings`, sa proposition visuelle `preview_settings`, et
/// `enhance_photo` (débruitage, détails bruts, super résolution, calculés par Lightroom).
extension ToolHandler {
    /// Préréglages de balance des blancs de Lightroom (seuls « as_shot » et « auto » existent
    /// pour un JPEG).
    static let whiteBalances: [(name: String, lightroom: String)] = [
        ("as_shot", "As Shot"), ("auto", "Auto"), ("daylight", "Daylight"), ("cloudy", "Cloudy"),
        ("shade", "Shade"), ("tungsten", "Tungsten"), ("fluorescent", "Fluorescent"), ("flash", "Flash"),
    ]
    static let maxPointColors = 8
    static let maxCurvePoints = 16

    /// Paramètres de retouche globale, communs à apply_settings et preview_settings.
    var developProperties: [(String, JSONValue)] {
        var settingProps: [String: JSONValue] = [:]
        for setting in DevelopCatalogue.all {
            let range: String
            switch setting.key {
            case DevelopCatalogue.temperatureKey: range = "RAW : 2000 à 50000 K ; JPEG, TIFF, HEIC : −100 à +100"
            case DevelopCatalogue.tintKey: range = "RAW : −150 à +150 ; JPEG, TIFF, HEIC : −100 à +100"
            default: range = "\(DevelopCatalogue.format(setting.min)) à \(DevelopCatalogue.format(setting.max))"
            }
            settingProps[setting.key] = prop("number", "\(setting.label) (\(range))")
        }
        let dcp = DevelopCatalogue.profiles
            .map { "« \($0.name) » (\($0.description)\($0.make.map { ", appareils \($0) seulement" } ?? ""))" }
            .joined(separator: " ; ")
        let point: JSONValue = ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2]
        let curve: JSONValue = [
            "type": "array", "items": point, "minItems": 2, "maxItems": .number(Double(Self.maxCurvePoints)),
            "description": "Points [entrée, sortie] de 0 à 255, entrée croissante ; [[0,0],[255,255]] = linéaire.",
        ]
        let pointColor = objectProp("Une couleur à modifier, désignée par sa teinte, sa saturation et sa luminosité d'origine.", Self.pointColorProperties,
                                    required: ["hue", "saturation", "luminance"])
        let line = objectProp("Un repère : deux points sur une ligne qui doit être verticale ou horizontale, dans l'image telle que la montre view_photo.", [
            "x1": prop("number", "Premier point, depuis la gauche (0 à 1)."), "y1": prop("number", "Premier point, depuis le haut (0 à 1)."),
            "x2": prop("number", "Second point (0 à 1)."), "y2": prop("number", "Second point (0 à 1)."),
        ], required: ["x1", "y1", "x2", "y2"])
        let point2D: JSONValue = ["type": "array", "items": ["type": "number"], "minItems": 2, "maxItems": 2]
        let refineStroke = objectProp("Un trait du pinceau d'affinage.", [
            "points": ["type": "array", "items": point2D, "minItems": 1, "maxItems": .number(Double(Self.maxStrokePoints)),
                       "description": "Points [x, y] de 0 à 1, dans l'image telle que la montre view_photo, dans l'ordre du trait."],
            "size": prop("number", "Rayon du pinceau, en part de la largeur de l'image (0,001 à 0,2 ; défaut 0,02)."),
            "feather": prop("number", "Contour progressif, de 0 à 100 (défaut 100)."),
            "flow": prop("number", "Flux, de 1 à 100 (défaut 100)."),
        ], required: ["points"])

        return [
            ("settings", ["type": "object", "properties": .object(settingProps), "additionalProperties": false,
                          "description": "Réglages globaux, par leur nom Lightroom : {\"Exposure2012\": 0.35, \"Highlights2012\": -40}. ConvertToGrayscale = 1 passe en noir et blanc (mélange par GrayMixer…)."]),
            ("profile", prop("string", "Profil de rendu, appliqué avant les autres réglages. Profils d'appareil (RAW) : \(dcp). Ou tout profil à base de Look installé, par son nom : « Adobe Color », « Adobe Landscape », « Camera CLASSIC Neg », « Artistic 01 »… (voir list_profiles). Si Lightroom ne le garde pas, « remarques » le dit : ne pas l'annoncer comme appliqué. Profil adaptatif (RAW) : en premier, sans tonalité automatique ; après des taches ou un flou, « remarques » dit s'il est recalculé.")),
            ("profile_amount", prop("number", "Intensité du profil en %, de 0 à 200 (défaut 100), pour les profils qui l'acceptent (profils créatifs).")),
            ("crop", objectProp("Recadrage et redressement, calculés par le module dans l'image telle qu'elle s'affiche : le plus grand cadre au ratio demandé, tourné de l'angle demandé, sans bord vide. Avec Upright, la perspective ou la distorsion manuelle, le module coche « Contraindre le recadrage » : Lightroom resserre le cadre pour n'y laisser aucun coin vide, quitte à le déplacer (« remarques » le dit) ; un cadre demandé alors que la géométrie est déjà posée se calcule sans coins vides, au centre et à la taille demandés (le serveur les situe sur deux rendus la première fois ; sans centre donné, le cadre se décale au besoin). {\"angle\": -1.2} redresse sans changer le ratio ; {\"aspect\": \"4:5\", \"center_x\": 0.45} recadre ; {\"reset\": true} enlève le recadrage. Chaque appel remplace le recadrage précédent.", [
                "aspect": prop("string", "Ratio largeur:hauteur de l'image affichée : « original » (défaut), « 1:1 », « 4:5 », « 3:2 », « 16:9 »…"),
                "angle": prop("number", "Rotation en degrés, de \(Self.format(Self.cropAngleRange.lowerBound)) à +\(Self.format(Self.cropAngleRange.upperBound)) (défaut 0) : un angle positif fait tourner l'image dans le sens antihoraire (son côté droit monte)."),
                "size": prop("number", "Taille du cadre, de \(Self.format(Self.cropSizeRange.lowerBound)) à 1 : part du plus grand cadre possible, sans coin vide (défaut 1)."),
                "center_x": prop("number", "Centre du cadre, de 0 (bord gauche) à 1 (bord droit) ; défaut 0,5 (ou ce qu'il faut pour éviter les coins vides). Le cadre rétrécit s'il ne tient pas."),
                "center_y": prop("number", "Centre du cadre, de 0 (haut) à 1 (bas) ; défaut 0,5 (ou ce qu'il faut pour éviter les coins vides)."),
                "reset": prop("boolean", "true = enlever le recadrage et l'angle."),
            ])),
            ("tone_curve", objectProp("Courbe des tonalités par points, par canal ; chaque canal donné remplace sa courbe : relire ToneCurvePV2012 (get_settings) d'abord (Parametric… à 0 ne prouve pas une courbe droite). Courbe en S douce : {\"rgb\": [[0,0],[64,56],[192,202],[255,255]]} ; noirs relevés « mat » : {\"rgb\": [[0,20],[255,255]]}.", [
                "rgb": curve, "red": curve, "green": curve, "blue": curve,
            ])),
            ("point_colors", ["type": "array", "items": pointColor, "maxItems": .number(Double(Self.maxPointColors)),
                              "description": "Couleur ponctuelle (Point Color) : remplace toutes les couleurs ponctuelles de la photo ; [] les retire."]),
            ("white_balance", enumProp(Self.whiteBalances.map(\.name), "Préréglage de balance des blancs de Lightroom (« auto » : balance automatique). Pour un JPEG : as_shot ou auto seulement.")),
            ("auto_tone", prop("boolean", "true = tonalité automatique de Lightroom (exposition, contraste, hautes lumières, ombres, blancs, noirs…), comme point de départ.")),
            ("lens_blur", objectProp("Flou d'objectif de Lightroom (RAW comme JPEG) : fond flou calculé d'après une carte de profondeur que Lightroom estime par IA, comme un objectif lumineux. Sans near ni far, la mise au point se fait sur le sujet que détecte Lightroom. Sur un flou déjà posé, ce qui n'est pas donné reste tel quel ({\"bokeh\": \"ring\"} change seulement la forme). {\"remove\": true} le désactive. À vérifier avec view_photo : un sujet mal détouré se voit vite (cheveux, contours).", [
                "amount": prop("number", "Intensité du flou, de 0 à 100 (défaut 50 ; 20 à 40 reste naturel)."),
                "near": prop("number", "Début de la zone nette en profondeur, de 0 (au plus près) à 100 (au loin) ; avec far."),
                "far": prop("number", "Fin de la zone nette en profondeur, de 0 à 100 ; avec near."),
                "highlights": prop("number", "Éclat des points lumineux du bokeh, de 0 à 100 (défaut 50)."),
                "bokeh": enumProp(DevelopCatalogue.bokehShapes.map(\.parameter), "Forme du bokeh (des points lumineux flous) : " + DevelopCatalogue.bokehShapes.map { "\($0.parameter) = \($0.label)" }.joined(separator: ", ") + " (défaut circle)."),
                "cat_eye": prop("number", "Effet « œil de chat » (bokeh qui tourbillonne vers les bords, comme un objectif ancien), de 0 à 100 (défaut 0)."),
                "focus": enumProp(["subject"], "subject = revenir à la mise au point sur le sujet que détecte Lightroom (après near et far)."),
                "refine": ["type": "array", "maxItems": 10,
                           "items": objectProp("Pinceau d'affinage du flou : des traits qui corrigent la carte de profondeur (cheveux, bords mal détourés).", [
                               "mode": enumProp(["sharp", "blur"], "sharp = rendre net (Net), blur = flouter (Flou)."),
                               "strokes": ["type": "array", "items": refineStroke, "minItems": 1, "maxItems": .number(Double(Self.maxStrokes))],
                           ], required: ["mode", "strokes"]),
                           "description": "Pinceau d'affinage (Net ou Flou), ajouté aux traits déjà posés ; vérifier ensuite par un zoom."],
                "remove": prop("boolean", "true = désactiver le flou d'objectif."),
            ])),
            ("preset", prop("string", "Paramètre prédéfini de Lightroom à appliquer avant les autres réglages : son nom (list_presets), « Dossier/Nom » si le nom existe dans plusieurs dossiers, ou son UUID.")),
            ("preset_amount", prop("number", "Quantité du paramètre prédéfini (preset), de 0 à 200 % (défaut 100), comme le curseur Quantité de Lightroom.")),
            ("auto_gray_mix", prop("boolean", "true = mélange noir et blanc automatique de Lightroom (bouton Auto du panneau Noir et blanc), sur une photo en noir et blanc (ou avec ConvertToGrayscale = 1).")),
            ("lens_profile", prop("string", "Profil d'objectif à imposer (objectif manuel, adapté ou mal reconnu) : son nom (« Adobe (Fujifilm FUJINON 55mm f/1.8 M42) »), son objectif ou son fichier .lcp (list_profiles avec lens) ; « auto » = profil par défaut de Lightroom. Upright actif : Lightroom le refait sur l'image corrigée.")),
            ("upright_guides", ["type": "array", "items": line, "minItems": 2, "maxItems": 4,
                                "description": "Upright avec repères (mode Guidé) : 2 à 4 lignes vraiment verticales ou horizontales dans la réalité (arêtes de bâtiment, poteaux, horizon), à redresser, positions mesurées dans view_photo. Le module les pose, mais Lightroom ne calcule la transformation qu'au clic de l'utilisateur sur « Mettre à jour » (panneau Transformation, section Upright) : le lui demander (show_photo en Développement), puis view_photo. Lightroom resserre ensuite le cadre (« Contraindre le recadrage »)."]),
            ("rotate", enumProp(["left", "right", "180"], "Rotation d'un quart de tour (photo couchée) : left = vers la gauche, right = vers la droite, 180 = demi-tour. undo_last la défait. Pas montrée par preview_settings.")),
            ("snapshot", prop("string", "Nom d'un instantané pris avant cette retouche (panneau Instantanés, « Claude · <nom> »), comme Adobe le conseille avant un gros changement ; un aussi, de lui-même, avant process_version.")),
            ("white_balance_point", objectProp("Balance des blancs sur un point neutre (comme la pipette de Lightroom) : un gris ou un blanc qui doit être neutre, dans l'image telle que la montre view_photo. Le serveur mesure sa dominante sur l'aperçu et en tire Temperature et Tint ; avec apply_settings, une seconde passe mesurée corrige l'écart qui reste. Une seule photo.", [
                "x": prop("number", "Depuis la gauche (0 à 1)."), "y": prop("number", "Depuis le haut (0 à 1)."),
            ], required: ["x", "y"])),
            ("process_version", prop("integer", "Version de processus : \(DevelopCatalogue.currentProcessVersion.version) (l'actuelle) met à jour une photo d'une version ancienne (3 à 5 ; get_settings et view_photo la signalent). Le rendu peut changer nettement : toujours le montrer d'abord (preview_settings), et apply_settings exige confirm = true. Un instantané « Claude · avant version de processus » est pris avant. Une photo en version 1 ou 2 (2003, 2010) se met à jour à la main dans Lightroom : un module ne peut pas convertir ses curseurs.")),
            ("relative", prop("boolean", "true = les valeurs de settings s'ajoutent aux valeurs actuelles (sans effet sur le reste).")),
        ]
    }

    /// Une couleur ponctuelle (apply_settings et add_mask).
    static var pointColorProperties: [String: JSONValue] {
        func prop(_ type: String, _ description: String) -> JSONValue { ["type": .string(type), "description": .string(description)] }
        return [
            "hue": prop("number", "Teinte d'origine en degrés (0 rouge, 30 orange, 60 jaune, 120 vert, 180 cyan, 240 bleu, 300 magenta)."),
            "saturation": prop("number", "Saturation d'origine, de 0 à 100."),
            "luminance": prop("number", "Luminosité d'origine, de 0 à 100."),
            "hue_shift": prop("number", "Décalage de teinte, de −100 à +100 (défaut 0)."),
            "saturation_shift": prop("number", "Saturation, de −100 à +100 (défaut 0)."),
            "luminance_shift": prop("number", "Luminosité, de −100 à +100 (défaut 0)."),
            "variance": prop("number", "Variance, de −100 à +100 (défaut 0) : négative, les couleurs touchées se rapprochent (uniformise une peau) ; positive, elles s'écartent."),
            "range": prop("number", "Étendue des couleurs touchées, de 0 à 100 (défaut 50)."),
        ]
    }

    var developDefinitions: [JSONValue] {
        [
            tool("apply_settings",
                 "Applique une retouche globale en une étape du panneau Historique nommée « Claude · <step_name> » : réglages, profil, recadrage, courbe par points, couleur ponctuelle, balance des blancs ou tonalité automatique, flou d'objectif, paramètre prédéfini. L'état d'avant Claude est mémorisé. Valeurs absolues par défaut ; relative = true ajoute les valeurs de settings aux valeurs actuelles (utile pour décaler une série). Les valeurs hors plage sont ramenées dans la plage et signalées. Si le module est en mode « Proposer d'abord », il refuse sans confirm = true : montrer alors les valeurs (ou preview_settings) à l'utilisateur, attendre son accord, puis rappeler avec confirm = true.",
                 properties: developProperties + writeProperties + targetProperties,
                 required: ["step_name"]),
            tool("preview_settings",
                 "Proposition visuelle : montre le rendu d'une retouche (mêmes paramètres qu'apply_settings) sans la garder. Le module l'applique, rend l'aperçu, puis remet la photo comme avant : rien n'est mémorisé, mais l'Historique de Lightroom garde deux étapes « Claude · essai ». Permis en mode « Proposer d'abord » : c'est la façon de montrer une proposition avant de demander l'accord. Avec compare : « bilan » de l'état actuel à la proposition (mêmes règles que view_photo : une « regression » se corrige dans la proposition avant de l'appliquer).",
                 properties: developProperties + [
                    ("photo_id", photoIDProperty),
                    ("step_name", prop("string", "Nom court de la proposition.")),
                    ("compare", prop("boolean", "true = l'état actuel (à gauche) et la proposition (à droite) côte à côte.")),
                    ("size", prop("integer", "Grand côté de l'aperçu en pixels (défaut \(Self.defaultPreviewSize), de \(Self.previewSizes.lowerBound) à \(Self.previewSizes.upperBound)).")),
                 ],
                 required: []),
            tool("enhance_photo",
                 "Lance sur une photo les traitements que Lightroom calcule lui-même (panneau Amélioration) et qu'aucun réglage ne pose : débruitage IA, détails bruts, super résolution. Lightroom affiche la photo dans le module Développement le temps du calcul (de quelques secondes à une minute par traitement), puis la vue d'avant est remise. L'étape « Claude · <step_name> » va au journal ; undo_last et revert_to_original défont le traitement. Lightroom refuse ce qui ne s'applique pas à la photo et en donne la raison (remarques). Pas de proposition visuelle : en mode « Proposer d'abord », décrire le traitement, attendre l'accord de l'utilisateur, puis rappeler avec confirm = true. Vérifier ensuite par un zoom à 100 % (view_photo avec region).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("denoise", prop("number", "Débruitage IA : intensité de \(Self.format(DevelopCatalogue.denoiseAmountRange.lowerBound)) à \(Self.format(DevelopCatalogue.denoiseAmountRange.upperBound)) (Lightroom propose \(Self.format(DevelopCatalogue.defaultDenoiseAmount))) ; 0 = retirer le débruitage.")),
                    ("raw_details", prop("boolean", "Détails bruts (dématriçage plus fin des RAW) : true l'active, false le retire.")),
                    ("super_resolution", prop("boolean", "Super résolution : true double la largeur et la hauteur de l'image, false la retire.")),
                 ] + writeProperties,
                 required: ["step_name"]),
            tool("remove_distractions",
                 "Supprime les reflets d'une vitre (Suppression des distractions › Reflets), calculés par Lightroom sur ce Mac, par ses modèles IA ; retire une suppression de la poussière du capteur (› Poussière). Reflets : dans le module Développement, où il affiche la photo le temps du calcul (de quelques secondes à une minute), puis remet la vue d'avant ; à faire avant toute autre retouche (aide d'Adobe), sur une photo prise derrière une vitre. Poussière : Lightroom ne la cherche que dans son interface (constaté : un module ne peut ni la lancer, ni la faire refaire sur une autre photo) : la proposer à la main, Supprimer › Poussière sur une photo, puis pour une série Copier et Coller de Lightroom avec la case Poussière (il la refait pour chaque photo). L'étape « Claude · <step_name> » va au journal ; undo_last et revert_to_original la défont. Les passants (› Personnes) passent par le remplissage génératif d'Adobe : à proposer de faire à la main. Pas de proposition visuelle : en mode « Proposer d'abord », décrire le traitement, attendre l'accord, puis rappeler avec confirm = true. Vérifier ensuite avec view_photo (un zoom sur le ciel pour la poussière).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("reflections", objectProp("Suppression des reflets ; {\"remove\": false} les rend.", [
                        "remove": prop("boolean", "true (défaut) = supprimer les reflets ; false = les rendre."),
                        "amount": prop("number", "Intensité, de 1 à 100 (défaut de Lightroom : 100) ; sur des reflets déjà supprimés, change seulement l'intensité."),
                        "quality": enumProp(["preview", "standard", "best"], "Qualité du calcul (défaut : celle de Lightroom, standard) : best est plus lent."),
                    ])),
                    ("dust", objectProp("{\"remove\": false} retire la suppression de la poussière du capteur (faite à la main dans Lightroom).", [
                        "remove": prop("boolean", "false = retirer la suppression de la poussière."),
                    ])),
                 ] + writeProperties,
                 required: ["step_name"]),
        ]
    }

    // MARK: Exécution

    func removeDistractions(_ args: Arguments) throws -> JSONValue {
        if let dust = args.object("dust") {
            guard !args.has("reflections") else {
                throw LightroomError.invalid("Reflets et poussière : un appel chacun.")
            }
            guard dust["remove"]?.bool == false else {
                throw LightroomError.invalid("Poussière : Lightroom ne la cherche que dans son interface (Développement › Supprimer › Poussière) ; un module ne peut pas la lancer. La proposer à la main ; pour une série, Copier puis Coller de Lightroom avec la case Poussière, qui la refait pour chaque photo. « dust » : {\"remove\": false} la retire.")
            }
            var params: [String: JSONValue] = ["poussiere": ["actif": false],
                                               "libelles": DevelopCatalogue.labels(for: ["Suppression.poussiere"])]
            if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
            params.merge(writeParameters(args, defaultStep: "poussière")) { _, new in new }
            return Self.withLabels(try lightroom.send("supprimer", params, timeout: 300))
        }
        guard let reflections = args.object("reflections") else {
            throw LightroomError.invalid("« reflections » : {\"remove\": true, \"amount\": 80}, ou « dust » : {\"remove\": false} (la poussière et les passants se font à la main dans Lightroom).")
        }
        var reflets: [String: JSONValue] = ["actif": .bool(reflections["remove"]?.bool ?? true)]
        if let raw = reflections["amount"], !raw.isNull {
            guard let amount = raw.double, (1...100).contains(amount) else {
                throw LightroomError.invalid("« reflections.amount » va de 1 à 100.")
            }
            reflets["intensite"] = .number(amount.rounded())
        }
        if let raw = reflections["quality"], !raw.isNull {
            guard let quality = raw.string, ["preview", "standard", "best"].contains(quality) else {
                throw LightroomError.invalid("« reflections.quality » : preview, standard ou best.")
            }
            reflets["qualite"] = .string(quality)
        }
        var params: [String: JSONValue] = ["reflets": .object(reflets)]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        params.merge(writeParameters(args, defaultStep: "reflets")) { _, new in new }
        // Le module attend la fin du calcul (trois minutes au plus).
        return Self.withLabels(try lightroom.send("supprimer", params, timeout: 660))
    }

    func applySettings(_ args: Arguments) throws -> JSONValue {
        // Le rendu peut changer nettement : la mise à jour se montre d'abord, en tout mode.
        if args.has("process_version"), args.bool("confirm") != true {
            throw LightroomError.invalid("« process_version » change le rendu de la photo : le montrer d'abord (preview_settings avec process_version), attendre l'accord de l'utilisateur, puis rappeler apply_settings avec confirm = true.")
        }
        var args = args
        var balance: BalancePoint?
        if args.has("white_balance_point") {
            (args, balance) = try balanceSurPoint(args)
        }
        var (develop, notes) = try developParameters(args)
        let cible = try targets(args)
        notes += recalagesDuRecadrage(&develop, cible: cible)
        notes += recalagesDesPositions(&develop, cible: cible)
        var params = cible
        params.merge(develop) { _, new in new }
        params.merge(writeParameters(args, defaultStep: "retouche")) { _, new in new }
        // Une rotation attend que Lightroom ait tourné la photo.
        let delai: TimeInterval = develop["rotation"] != nil ? 300 : 180
        var reponse = recadrerApres(try lightroom.send("appliquer", params, timeout: delai), params, notes: &notes)
        if let balance, var objet = reponse.object {
            objet["balance_point"] = secondePasseBalance(balance, args: args)
            reponse = .object(objet)
        }
        return Self.withLabels(reponse, notes: notes)
    }

    /// Grilles pour les positions données dans l'aperçu (repères d'Upright, pinceau d'affinage du flou
    /// d'objectif) : le module les ramène dans le repère du fichier, correction d'objectif comprise.
    func recalagesDesPositions(_ params: inout [String: JSONValue], cible: [String: JSONValue]) -> [JSONValue] {
        let flou = params["flou_objectif"]?.object ?? [:]
        guard params["reperes"] != nil || flou["affinage"] != nil else { return [] }
        let (grilles, remarques) = recalages(cible)
        if let grilles {
            var toutes = params["recalages"]?.object ?? [:]
            for (cle, valeur) in grilles.object ?? [:] { toutes[cle] = valeur }
            params["recalages"] = .object(toutes)
        }
        return remarques
    }

    /// Débruitage, détails bruts, super résolution (commande « ameliorer » du module), dans l'ordre
    /// du catalogue.
    func enhancePhoto(_ args: Arguments) throws -> JSONValue {
        var requests: [JSONValue] = []
        for enhancement in DevelopCatalogue.enhancements where args.has(enhancement.parameter) {
            var request: [String: JSONValue] = ["nom": .string(enhancement.lightroom)]
            if enhancement.parameter == "denoise" {
                let range = DevelopCatalogue.denoiseAmountRange
                guard let amount = args.double("denoise"), amount == 0 || range.contains(amount) else {
                    throw LightroomError.invalid("« denoise » : une intensité de \(Self.format(range.lowerBound)) à \(Self.format(range.upperBound)), ou 0 pour retirer le débruitage.")
                }
                request["actif"] = .bool(amount > 0)
                if amount > 0 { request["intensite"] = .number(amount.rounded()) }
            } else {
                guard let on = args.bool(enhancement.parameter) else {
                    throw LightroomError.invalid("« \(enhancement.parameter) » : true pour l'activer, false pour le retirer.")
                }
                request["actif"] = .bool(on)
            }
            requests.append(.object(request))
        }
        guard !requests.isEmpty else {
            throw LightroomError.invalid("Rien à lancer : donner \(DevelopCatalogue.enhancements.map(\.parameter).joined(separator: ", ")).")
        }
        var params: [String: JSONValue] = [
            "ameliorations": .array(requests),
            "libelles": DevelopCatalogue.labels(for: DevelopCatalogue.enhancements.map(\.changeKey)),
        ]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        params.merge(writeParameters(args, defaultStep: "amélioration")) { _, new in new }
        // Le module attend la fin de chaque calcul (trois minutes au plus chacun).
        return Self.withLabels(try lightroom.send("ameliorer", params, timeout: 660))
    }

    func previewSettings(_ args: Arguments) throws -> ToolResult {
        var args = args
        var balance: BalancePoint?
        if args.has("white_balance_point") {
            (args, balance) = try balanceSurPoint(args)
        }
        var (develop, notes) = try developParameters(args)
        if let balance {
            notes.append(.string("Balance du point neutre : a* \(Self.format((balance.avant.a * 10).rounded() / 10)), b* \(Self.format((balance.avant.b * 10).rounded() / 10)) mesurés ; Temperature et Tint proposés d'après les pentes relevées (apply_settings remesure et corrige l'écart qui reste)."))
        }
        let cible: [String: JSONValue] = args.int("photo_id").map { ["photo": .number(Double($0))] } ?? [:]
        notes += recalagesDuRecadrage(&develop, cible: cible)
        notes += recalagesDesPositions(&develop, cible: cible)
        var params = develop
        params["action"] = "appliquer"
        params["etape"] = .string((args.string("step_name") ?? "").isEmpty ? "proposition" : String(args.string("step_name")!.prefix(60)))
        params.merge(cible) { _, new in new }
        return try preview(params, args: args, notes: notes)
    }

    /// Rend une proposition (commande « essayer » du module) : l'image, côte à côte avec l'état
    /// actuel si demandé, et ce qui changerait.
    func preview(_ params: [String: JSONValue], args: Arguments, notes: [JSONValue]) throws -> ToolResult {
        var params = params
        let size = min(max(args.int("size") ?? Self.defaultPreviewSize, Self.previewSizes.lowerBound), Self.previewSizes.upperBound)
        let compare = args.bool("compare") ?? false
        params["taille"] = .number(Double(size))
        params["comparer"] = .bool(compare)

        let result = try lightroom.send("essayer", params, timeout: 240)
        let proposed = try Self.readPreview(result["chemin"]?.string)
        var image = proposed
        var info = Self.labelChanges(Self.withLabels(result, notes: notes)).object ?? [:]
        info.removeValue(forKey: "chemin")
        info.removeValue(forKey: "chemin_actuel")
        // Mesurées comme l'aperçu de view_photo (un décodage, réduction à 512 px), avec la forme
        // courte de l'éclairage : une balance ou un masque proposés se voient à l'écart entre zones.
        // Ni netteté ni bruit : une proposition ne se compare qu'à l'état actuel rendu par la même
        // commande, jamais à une vue gardée par le bilan de view_photo.
        let proposition = Self.mesurerImage(proposed, detail: false)
        if compare {
            let current = try Self.readPreview(result["chemin_actuel"]?.string)
            image = PreviewImages.sideBySide(current, proposed) ?? proposed
            info["image"] = "À gauche l'état actuel, à droite la proposition."
            let actuel = Self.mesurerImage(current, detail: false)
            if let actuel { info["mesures_actuelles"] = actuel.json }
            if let actuel, let proposition {
                info["bilan"] = Bilan.avantApres(
                    avant: actuel.mesures, apres: proposition.mesures, detailAvant: nil, detailApres: nil,
                    depuis: "l'état actuel : la proposition n'est pas appliquée",
                    conseil: "Une « regression » se corrige dans la proposition avant de l'appliquer.",
                    grainAjoute: Self.grainAjoute(result["changements"]),
                    cadreChange: actuel.largeur != proposition.largeur || actuel.hauteur != proposition.hauteur)
            }
        }
        if let proposition { info["mesures_proposition"] = proposition.json }
        info["rien_n_est_applique"] = "La photo a été remise comme avant ; apply_settings applique la proposition."
        return ToolResult(content: [Self.imageContent(image), .text(JSONCoding.pretty(.object(info)))])
    }

    /// La proposition ajoute du grain (GrainAmount en hausse) : un bruit en hausse est alors voulu.
    static func grainAjoute(_ changements: JSONValue?) -> Bool {
        (changements?.array ?? []).contains { changement in
            guard changement["cle"]?.string == "GrainAmount", let apres = changement["apres"]?.double else { return false }
            return apres > (changement["avant"]?.double ?? 0)
        }
    }

    /// Les paramètres de retouche globale, vérifiés, sous la forme qu'attend le module, et les
    /// remarques du serveur (valeurs ramenées dans leur plage, intensité ignorée…).
    func developParameters(_ args: Arguments) throws -> (params: [String: JSONValue], notes: [JSONValue]) {
        let raw = args.object("settings") ?? [:]
        let relative = args.bool("relative") ?? false
        var notes: [JSONValue] = []
        var params: [String: JSONValue] = [:]
        var labelled: [String] = []

        let unknown = raw.keys.filter { DevelopCatalogue.setting($0) == nil }.sorted()
        guard unknown.isEmpty else {
            throw LightroomError.invalid("Réglages inconnus : \(unknown.joined(separator: ", ")). Réglages pris en charge : \(DevelopCatalogue.keys.joined(separator: ", ")).")
        }
        var values: [String: JSONValue] = [:]
        for key in raw.keys.sorted() {
            let setting = DevelopCatalogue.setting(key)!
            guard let value = raw[key]?.double, value.isFinite else {
                throw LightroomError.invalid("La valeur de \(key) doit être un nombre.")
            }
            var adjusted = value
            if setting.isSwitch, !relative, value != 0, value != 1 {
                throw LightroomError.invalid("\(key) vaut 0 (désactivé) ou 1 (activé).")
            }
            if setting.isWhole, value.rounded() != value {
                throw LightroomError.invalid("\(key) attend un nombre entier, de \(DevelopCatalogue.format(setting.min)) à \(DevelopCatalogue.format(setting.max)).")
            }
            if !relative {
                // La plage de la température et de la teinte dépend de la photo : le module la vérifie.
                if key != DevelopCatalogue.temperatureKey, key != DevelopCatalogue.tintKey {
                    adjusted = min(max(value, setting.min), setting.max)
                }
                if adjusted != value {
                    notes.append(.string("\(key) : \(DevelopCatalogue.format(value)) ramené à \(DevelopCatalogue.format(adjusted)) (plage \(DevelopCatalogue.format(setting.min)) à \(DevelopCatalogue.format(setting.max)))."))
                }
            }
            values[key] = .number(adjusted)
        }
        params["reglages"] = .object(values)
        labelled += values.keys
        let booleans = values.keys.filter { DevelopCatalogue.setting($0)?.isBoolean == true }.sorted()
        if !booleans.isEmpty { params["booleens"] = .array(booleans.map(JSONValue.string)) }
        if values["ConvertToGrayscale"] != nil {
            // Sous une Look couleur, Lightroom n'applique pas le noir et blanc : le module passe à
            // Adobe Monochrome (et revient à Adobe Color), comme l'interface de Lightroom.
            let look = { (name: String) in self.lookProfiles.candidates(named: name).first { $0.cameraRestriction.isEmpty }?.look }
            var looks: [String: JSONValue] = [:]
            if let monochrome = look("Adobe Monochrome") { looks["monochrome"] = monochrome }
            if let color = look("Adobe Color") { looks["couleur"] = color }
            if !looks.isEmpty { params["looks_traitement"] = .object(looks) }
        }

        if let profile = try profileParameters(args, notes: &notes) {
            params.merge(profile) { _, new in new }
            labelled.append(DevelopCatalogue.profileKey)
        }
        if let crop = try cropParameter(args) {
            params["recadrage"] = crop
            labelled += DevelopCatalogue.cropKeys
        }
        if params["recadrage"] != nil || values.keys.contains(where: { $0.hasPrefix("Perspective") || $0.hasPrefix("Lens") }) {
            labelled += DevelopCatalogue.cropKeys + [DevelopCatalogue.constrainCropKey]
        }
        if let curves = try toneCurveParameter(args) {
            params["courbes"] = curves
            labelled += curves.object?.keys.map { $0 } ?? []
        }
        if let colors = try pointColorsParameter(args) {
            params["couleurs_ponctuelles"] = colors
            labelled.append("PointColors")
        }
        if let balance = args.string("white_balance") {
            guard let preset = Self.whiteBalances.first(where: { $0.name == balance.lowercased() }) else {
                throw LightroomError.invalid("« white_balance » vaut \(Self.whiteBalances.map(\.name).joined(separator: ", ")).")
            }
            params["balance"] = .string(preset.lightroom)
            labelled.append("WhiteBalance")
        }
        if args.bool("auto_tone") == true {
            params["auto_ton"] = true
            labelled.append("AutoTone")
        }
        if let blur = args.object("lens_blur") {
            var demande: [String: JSONValue] = [:]
            for (key, local, range) in [("amount", "intensite", 0.0...100.0), ("near", "proche", 0.0...100.0),
                                        ("far", "loin", 0.0...100.0), ("highlights", "eclat", 0.0...100.0),
                                        ("cat_eye", "oeil_de_chat", 0.0...100.0)] {
                guard let value = blur[key] else { continue }
                guard let number = value.double, range.contains(number) else {
                    throw LightroomError.invalid("« lens_blur.\(key) » va de 0 à 100.")
                }
                demande[local] = .number(number)
            }
            if let name = blur["bokeh"], !name.isNull {
                guard let shape = DevelopCatalogue.bokehShapes.first(where: { $0.parameter == name.string }) else {
                    throw LightroomError.invalid("« lens_blur.bokeh » : \(DevelopCatalogue.bokehShapes.map(\.parameter).joined(separator: ", ")).")
                }
                demande["bokeh"] = ["nom": .string(shape.label), "champs": .object(shape.fields.mapValues(JSONValue.number))]
            }
            guard (demande["proche"] == nil) == (demande["loin"] == nil) else {
                throw LightroomError.invalid("« lens_blur » : donner near et far ensemble (zone nette), ou aucun des deux (mise au point sur le sujet).")
            }
            if let focus = blur["focus"]?.string {
                guard focus == "subject" else { throw LightroomError.invalid("« lens_blur.focus » : subject.") }
                demande["sujet"] = true
            }
            if let raw = blur["refine"], !raw.isNull {
                guard let list = raw.array, (1...10).contains(list.count) else {
                    throw LightroomError.invalid("« lens_blur.refine » : de 1 à 10 groupes {mode, strokes}.")
                }
                demande["affinage"] = .array(try list.enumerated().map { index, item in
                    let path = "lens_blur.refine[\(index)]"
                    guard let groupe = item.object, let mode = groupe["mode"]?.string, ["sharp", "blur"].contains(mode) else {
                        throw LightroomError.invalid("« \(path).mode » : sharp ou blur.")
                    }
                    return ["mode": .string(mode == "sharp" ? "net" : "flou"),
                            "traits": .array(try strokesParameter(groupe, path: path, required: true))]
                })
                labelled.append("DepthBasedCorrections")
            }
            if blur["remove"]?.bool == true { demande = ["retirer": true] }
            params["flou_objectif"] = .object(demande)
            labelled.append("LensBlur")
        }
        if let preset = args.string("preset")?.trimmingCharacters(in: .whitespacesAndNewlines), !preset.isEmpty {
            params["preset"] = .string(preset)
            labelled.append("Preset")
            if args.has("preset_amount") {
                guard let amount = args.double("preset_amount"), (0...200).contains(amount) else {
                    throw LightroomError.invalid("« preset_amount » va de 0 à 200 (%).")
                }
                params["quantite_preset"] = .number(amount.rounded())
            }
        } else if args.has("preset_amount") {
            notes.append("preset_amount ignoré : il accompagne preset.")
        }
        if args.bool("auto_gray_mix") == true {
            params["melange_nb_auto"] = true
            labelled += ["AutoGrayscaleMix"] + DevelopCatalogue.all.filter { $0.key.hasPrefix("GrayMixer") }.map(\.key)
        }
        if let text = args.string("lens_profile")?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            params["profil_objectif"] = try lensProfileParameter(text)
            labelled += ["LensProfileName", "LensProfileEnable"]
        }
        if let raw = args.array("upright_guides") {
            guard (2...4).contains(raw.count) else {
                throw LightroomError.invalid("« upright_guides » : de 2 à 4 lignes, comme le mode Guidé de Lightroom.")
            }
            params["reperes"] = .array(try raw.enumerated().map { index, item in
                let path = "upright_guides[\(index)]"
                guard let ligne = item.object else { throw LightroomError.invalid("« \(path) » : {x1, y1, x2, y2}.") }
                var resultat: [String: JSONValue] = [:]
                for key in ["x1", "y1", "x2", "y2"] {
                    guard let value = ligne[key]?.double, (0...1).contains(value) else {
                        throw LightroomError.invalid("« \(path).\(key) » va de 0 à 1.")
                    }
                    resultat[key] = .number(value)
                }
                let dx = (resultat["x2"]!.double! - resultat["x1"]!.double!), dy = (resultat["y2"]!.double! - resultat["y1"]!.double!)
                guard (dx * dx + dy * dy).squareRoot() >= 0.05 else {
                    throw LightroomError.invalid("« \(path) » : ligne trop courte ; deux points éloignés sur la ligne (au moins un vingtième de l'image).")
                }
                return .object(resultat)
            })
            labelled += ["PerspectiveUpright", "UprightFourSegments"] + DevelopCatalogue.cropKeys + [DevelopCatalogue.constrainCropKey]
        }
        if let rotate = args.string("rotate") {
            guard let sens = ["left": "gauche", "right": "droite", "180": "demi"][rotate] else {
                throw LightroomError.invalid("« rotate » : left, right ou 180.")
            }
            params["rotation"] = .string(sens)
            labelled.append("Rotation")
        }
        if let name = args.string("snapshot").map(Self.withoutClaudePrefix), !name.isEmpty {
            params["instantane_avant"] = .string(String(name.prefix(50)))
        }
        if args.has("process_version") {
            let current = DevelopCatalogue.currentProcessVersion
            guard args.int("process_version") == current.version else {
                throw LightroomError.invalid("« process_version » : seulement \(current.version), la version actuelle.")
            }
            var names: [String: JSONValue] = [:]
            for item in DevelopCatalogue.processVersions { names[item.value] = .string("version \(item.version)") }
            params["version_processus"] = ["valeur": .string(current.value), "nom": .string("version \(current.version)"),
                                           "noms": .object(names), "anciennes": ["5.0", "5.7"]]
            labelled.append("ProcessVersion")
        }

        let asked = !values.isEmpty || ["profile", "crop", "tone_curve", "point_colors", "white_balance", "preset", "lens_blur", "process_version",
                                        "lens_profile", "upright_guides", "rotate"].contains(where: args.has)
            || args.bool("auto_tone") == true || args.bool("auto_gray_mix") == true
        guard asked else {
            throw LightroomError.invalid("Rien à appliquer : donner settings (au moins un réglage, par exemple {\"Exposure2012\": 0.3}), profile, crop, tone_curve, point_colors, white_balance, white_balance_point, auto_tone, auto_gray_mix, lens_blur, lens_profile, upright_guides, rotate, preset ou process_version.")
        }
        var recents: [(String, String)] = values.keys.sorted().compactMap { key in DevelopCatalogue.setting(key)?.since.map { (key, $0) } }
        if args.has("point_colors") { recents.append(("point_colors", "13.0")) }
        if args.has("lens_blur") { recents.append(("lens_blur", "13.0")) }
        try verifierVersion(recents)
        params["plages"] = DevelopCatalogue.ranges(for: Array(values.keys))
        params["libelles"] = DevelopCatalogue.labels(for: labelled)
        params["relatif"] = .bool(relative)
        return (params, notes)
    }

    /// Le profil d'objectif demandé, sous la forme qu'attend le module : {auto} ou {nom, fichier,
    /// fichier_non_raw?} (Lightroom a souvent deux fichiers du même nom, pour les RAW et les JPEG ;
    /// le module prend celui qui convient à la photo).
    func lensProfileParameter(_ text: String) throws -> JSONValue {
        if ["auto", "défaut", "par défaut", "default"].contains(text.lowercased()) {
            return ["auto": true]
        }
        let (rawProfile, ambiguous) = lensProfiles.find(text, raw: true)
        guard let profile = rawProfile else {
            if !ambiguous.isEmpty {
                throw LightroomError.invalid("« lens_profile » : plusieurs profils pour « \(text) » : \(ambiguous.prefix(8).joined(separator: " ; ")). Donner le nom exact ou le fichier.")
            }
            let proches = lensProfiles.search(text, limit: 6).map(\.name)
            throw LightroomError.invalid("« lens_profile » : aucun profil d'objectif « \(text) »" + (proches.isEmpty ? "" : " (proches : \(proches.joined(separator: " ; ")))")
                + ". Voir list_profiles avec lens.")
        }
        var result: [String: JSONValue] = ["nom": .string(profile.name), "fichier": .string(profile.fileName)]
        if let other = lensProfiles.profiles.first(where: { $0.name == profile.name && $0.raw != profile.raw }) {
            result[profile.raw ? "fichier_non_raw" : "fichier_raw"] = .string(other.fileName)
        }
        return .object(result)
    }

    /// Refuse un réglage que cette version de Lightroom ne connaît pas (il serait ignoré sans erreur).
    /// Version inconnue (module ancien, faux module) : rien n'est refusé.
    func verifierVersion(_ recents: [(cle: String, depuis: String)]) throws {
        guard !recents.isEmpty else { return }
        if versionLightroom == nil {
            versionLightroom = (try? lightroom.send("etat", [:], timeout: 10))?["lightroom"]?.string ?? ""
        }
        guard let version = versionLightroom, !version.isEmpty else { return }
        let trop = recents.filter { Self.versionInferieure(version, $0.depuis) }
        guard trop.isEmpty else {
            throw LightroomError.invalid("Lightroom Classic \(version) ne connaît pas encore : " + trop.map { "\($0.cle) (depuis la \($0.depuis))" }.joined(separator: ", ")
                + ". Rien n'a été appliqué : retirer ces réglages, ou mettre Lightroom à jour.")
        }
    }

    /// « 12.4 » < « 13.0 » (comparaison par numéros).
    static func versionInferieure(_ version: String, _ minimum: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let b = minimum.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// Le profil demandé : profil d'appareil (par son nom seul) ou profil à base de Look (avec
    /// la Look de chaque fichier de ce nom, un par appareil pour les simulations réservées).
    func profileParameters(_ args: Arguments, notes: inout [JSONValue]) throws -> [String: JSONValue]? {
        guard let value = args.raw["profile"], !value.isNull else {
            if args.has("profile_amount") {
                notes.append("profile_amount ignoré : il accompagne profile.")
            }
            return nil
        }
        let name = value.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let amount = args.raw["profile_amount"]?.double
        if let amount, !(0...200).contains(amount) {
            throw LightroomError.invalid("« profile_amount » va de 0 à 200 (%).")
        }
        if let profile = DevelopCatalogue.profile(name) {
            if amount != nil { notes.append(.string("profile_amount ignoré : « \(profile.name) » n'a pas d'intensité réglable.")) }
            var params: [String: JSONValue] = ["profil": .string(profile.name)]
            if let make = profile.make { params["profil_marque"] = .string(make) }
            if !profile.variants.isEmpty { params["profil_variantes"] = .array(profile.variants.map(JSONValue.string)) }
            if !profile.missingOn.isEmpty { params["profil_absent_sur"] = .array(profile.missingOn.map(JSONValue.string)) }
            return params
        }
        let candidates = lookProfiles.candidates(named: name)
        guard let first = candidates.first else {
            throw LightroomError.invalid("Profil inconnu : \(JSONCoding.line(value)). Voir list_profiles pour les profils installés ; profils d'appareil : \(DevelopCatalogue.profiles.map(\.name).joined(separator: ", ")).")
        }
        var look: [String: JSONValue] = [
            "nom": .string(first.name),
            "candidats": .array(candidates.map { profile in
                var candidate: [String: JSONValue] = [
                    "restriction": .string(profile.cameraRestriction),
                    "raw_seulement": .bool(["Adobe Raw", "Camera", "Adaptive"].contains(profile.folder) || !profile.cameraRestriction.isEmpty),
                    "look": profile.look,
                ]
                if let preset = profile.adaptivePreset { candidate["par_preset"] = preset }
                return .object(candidate)
            }),
        ]
        if let amount {
            if first.supportsAmount {
                look["intensite"] = .number(amount / 100)
            } else {
                notes.append(.string("profile_amount ignoré : « \(first.name) » n'a pas d'intensité réglable."))
            }
        }
        return ["profil_look": .object(look)]
    }

    /// Le recadrage demandé, vérifié, sous la forme qu'attend le module :
    /// {ratio?, angle, taille, centre_x?, centre_y?} ou {retirer = true}. Sans ratio : celui de la photo.
    func cropParameter(_ args: Arguments) throws -> JSONValue? {
        guard let value = args.raw["crop"], !value.isNull else { return nil }
        guard let crop = value.object else {
            throw LightroomError.invalid("« crop » doit être un objet, par exemple {\"angle\": -1.2} ou {\"aspect\": \"4:5\"}.")
        }
        let known: Set = ["aspect", "angle", "size", "center_x", "center_y", "reset"]
        let unknown = crop.keys.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw LightroomError.invalid("« crop » : paramètres inconnus : \(unknown.joined(separator: ", ")). Paramètres pris en charge : aspect, angle, size, center_x, center_y, reset.")
        }
        if crop["reset"]?.bool == true {
            return ["retirer": true]
        }

        func number(_ key: String, _ range: ClosedRange<Double>, default fallback: Double) throws -> Double {
            guard let item = crop[key], !item.isNull else { return fallback }
            guard let number = item.double, number.isFinite, range.contains(number) else {
                throw LightroomError.invalid("« crop.\(key) » doit être un nombre de \(Self.format(range.lowerBound)) à \(Self.format(range.upperBound)).")
            }
            return number
        }

        var result: [String: JSONValue] = [
            "angle": .number(try number("angle", Self.cropAngleRange, default: 0)),
            "taille": .number(try number("size", Self.cropSizeRange, default: 1)),
        ]
        // Sans centre donné, le module garde le milieu de l'image, sauf si des coins vides
        // (Upright, perspective) l'obligent à décaler le cadre.
        for (key, local) in [("center_x", "centre_x"), ("center_y", "centre_y")] where crop[key] != nil && crop[key]?.isNull == false {
            result[local] = .number(try number(key, 0...1, default: 0.5))
        }
        if let aspect = crop["aspect"], !aspect.isNull {
            guard let text = aspect.string else {
                throw LightroomError.invalid("« crop.aspect » s'écrit comme « 4:5 », « 16:9 » ou « original ».")
            }
            if let ratio = try Self.aspectRatio(text) { result["ratio"] = .number(ratio) }
        }
        return .object(result)
    }

    /// « 4:5 », « 16x9 », « 1,91:1 » → largeur ÷ hauteur ; « original » → nil.
    static func aspectRatio(_ text: String) throws -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["", "original", "originale", "origine", "d'origine", "as shot"].contains(cleaned) { return nil }
        let parts = cleaned.replacingOccurrences(of: ",", with: ".")
            .split(whereSeparator: { ":x×/".contains($0) })
            .map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let width = parts[0], let height = parts[1], width > 0, height > 0,
              cropAspectRange.contains(width / height) else {
            throw LightroomError.invalid("« crop.aspect » s'écrit comme « 4:5 », « 16:9 » ou « original » (reçu : « \(text) »).")
        }
        return width / height
    }

    /// Les courbes par points demandées, en listes plates [x1, y1, x2, y2…] comme les range
    /// Lightroom, par clé (ToneCurvePV2012, ToneCurvePV2012Red…).
    func toneCurveParameter(_ args: Arguments) throws -> JSONValue? {
        guard let value = args.raw["tone_curve"], !value.isNull else { return nil }
        guard let channels = value.object, !channels.isEmpty else {
            throw LightroomError.invalid("« tone_curve » doit être un objet par canal, par exemple {\"rgb\": [[0,0],[64,56],[192,202],[255,255]]}.")
        }
        var curves: [String: JSONValue] = [:]
        for (channel, points) in channels {
            guard let key = DevelopCatalogue.curveKeys.first(where: { $0.channel == channel })?.key else {
                throw LightroomError.invalid("« tone_curve » : canal inconnu « \(channel) » (rgb, red, green ou blue).")
            }
            let pairs = try Self.curvePoints(points, path: "tone_curve.\(channel)")
            curves[key] = .array(pairs.flatMap { [JSONValue.number($0.0), .number($0.1)] })
        }
        return .object(curves)
    }

    /// Les points [entrée, sortie] d'une courbe, de 0 à 255, arrondis et triés, sans entrée en double.
    static func curvePoints(_ points: JSONValue, path: String) throws -> [(Double, Double)] {
        guard let list = points.array, (2...maxCurvePoints).contains(list.count) else {
            throw LightroomError.invalid("« \(path) » : de 2 à \(maxCurvePoints) points [entrée, sortie].")
        }
        var pairs: [(Double, Double)] = []
        for point in list {
            guard let xy = point.array, xy.count == 2, let x = xy[0].double, let y = xy[1].double,
                  (0...255).contains(x), (0...255).contains(y) else {
                throw LightroomError.invalid("« \(path) » : chaque point est [entrée, sortie], de 0 à 255.")
            }
            pairs.append((x.rounded(), y.rounded()))
        }
        pairs.sort { $0.0 < $1.0 }
        for index in 1..<pairs.count where pairs[index].0 <= pairs[index - 1].0 {
            throw LightroomError.invalid("« \(path) » : deux points ont la même entrée (\(DevelopCatalogue.format(pairs[index].0))).")
        }
        return pairs
    }

    /// Les couleurs ponctuelles demandées, sous la forme que Lightroom range dans PointColors
    /// (constaté dans le catalogue : couleur source et décalages de 0 à 1 ou de −1 à 1).
    func pointColorsParameter(_ args: Arguments) throws -> JSONValue? {
        guard let value = args.raw["point_colors"], !value.isNull else { return nil }
        return try pointColors(value, path: "point_colors")
    }

    /// Une liste de couleurs ponctuelles (photo entière, ou dans un masque : mêmes champs, que le
    /// module écrit en textes de 19 nombres dans LocalPointColors).
    func pointColors(_ value: JSONValue, path: String) throws -> JSONValue {
        guard let list = value.array, list.count <= Self.maxPointColors else {
            throw LightroomError.invalid("« \(path) » : une liste d'au plus \(Self.maxPointColors) couleurs ; [] les retire.")
        }
        return .array(try list.enumerated().map { index, item in
            guard let color = item.object else {
                throw LightroomError.invalid("« \(path)[\(index)] » doit être un objet {hue, saturation, luminance, …}.")
            }
            func number(_ key: String, _ range: ClosedRange<Double>, default fallback: Double?) throws -> Double {
                guard let raw = color[key], !raw.isNull else {
                    if let fallback { return fallback }
                    throw LightroomError.invalid("« \(path)[\(index)].\(key) » manque.")
                }
                guard let number = raw.double, range.contains(number) else {
                    throw LightroomError.invalid("« \(path)[\(index)].\(key) » va de \(Self.format(range.lowerBound)) à \(Self.format(range.upperBound)).")
                }
                return number
            }
            let hue = try number("hue", 0...360, default: nil)
            let full: JSONValue = ["LowerNone": 0, "LowerFull": 0, "UpperFull": 1, "UpperNone": 1]
            // La teinte source se range de 0 à 6, en sixièmes de tour (60° par unité) : la référence
            // du SDK le dit (addPointColorSwatch, « Values from 0 to 6 »), la validation de Lightroom
            // Classic 15.6 la borne ainsi (DevelopPointColorUtils), et une couleur prélevée à la main
            // sur une robe lavande s'y est rangée à 4,66. Jusqu'à la 2.0, le serveur écrivait hue/360 :
            // une couleur bleue (240°) visait l'orange (40°). Variance : le curseur de −100 à +100,
            // rangé de −1 à +1 (constaté : 40 → 0,4).
            return [
                "SrcHue": .number(hue.truncatingRemainder(dividingBy: 360) / 60),
                "SrcSat": .number(try number("saturation", 0...100, default: nil) / 100),
                "SrcLum": .number(try number("luminance", 0...100, default: nil) / 100),
                "HueShift": .number(try number("hue_shift", -100...100, default: 0) / 100),
                "SatScale": .number(try number("saturation_shift", -100...100, default: 0) / 100),
                "LumScale": .number(try number("luminance_shift", -100...100, default: 0) / 100),
                "RangeAmount": .number(try number("range", 0...100, default: 50) / 100),
                "HueRange": ["LowerNone": 0, "LowerFull": 0.33, "UpperFull": 0.67, "UpperNone": 1],
                "SatRange": full,
                "LumRange": full,
                "Variance": .number(try number("variance", -100...100, default: 0) / 100),
            ]
        })
    }
}
