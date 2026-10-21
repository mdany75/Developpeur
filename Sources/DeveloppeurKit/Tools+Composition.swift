import CoreGraphics
import Foundation

/// La composition lue (1.3) : sur l'image entière, non recadrée, l'horizon, le sujet, son regard et
/// leur place par rapport aux tiers, puis un cadre proposé, jamais appliqué ici (preview_settings le
/// montre, apply_settings le pose après l'accord). Une photo recadrée est rendue sans son cadre le
/// temps de la lecture, puis remise telle quelle (deux étapes « Claude · composition » de
/// l'Historique), d'où sa place dans readOnlyTools, comme view_photo avec compare. Les positions
/// données (horizon, subject) sont celles de l'image que montre view_photo, recadrée : elles passent
/// dans l'image entière par Composition.versImageEntiere, d'après le cadre actuel que le module lit
/// (cadre_actuel). L'horizon se mesure sur l'image entière (LineAngle : angle absolu), le sujet est
/// celui de Vision (visages, puis zone d'intérêt) ou celui donné ; Composition.proposer calcule le
/// cadre. Réponse sans image : preview_settings le montre, dessiné sur l'image entière. Un horizon
/// penché de 0,5° ou plus sur une géométrie intacte va au carnet de progrès (Carnet.constatHorizon),
/// comme celui de measure_angle.
extension ToolHandler {
    /// Taille du cadre (size, min_size), en part du plus grand cadre possible.
    static let tailleCadreComposition = 0.5...1.0
    static let tailleMinCompositionDefaut = 0.75

    var compositionDefinitions: [JSONValue] {
        let point = { (texte: String) in self.prop("number", texte) }
        let virgule = { (valeur: Double) in Self.format(valeur).replacingOccurrences(of: ".", with: ",") }
        return [
            tool("read_composition",
                 "Lit la composition de la photo sur l'image entière, non recadrée (une photo recadrée est rendue sans son cadre le temps de la lecture : deux étapes « Claude · composition » dans l'Historique, la photo revient telle quelle) : inclinaison et hauteur de l'horizon (deux points sur lui dans l'image que montre view_photo ; le serveur affine l'angle), sujet (visages et zone d'intérêt de Vision, ou subject), sens du regard, place de chacun par rapport aux tiers. Propose un cadre : horizon droit et sur un tiers, sujet sur un tiers avec de l'espace devant lui, le plus grand possible (au moins min_size). Rien n'est appliqué : montrer ce crop tel quel par preview_settings (image entière, cadre en pointillés), sans compare, attendre l'accord, puis apply_settings avec le même crop. « lecture » : ce qui cloche, en mots simples, à dire à l'utilisateur pour qu'il cadre mieux à la prise de vue.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("horizon", objectProp("L'horizon, ou une ligne qui devrait être horizontale : deux points sur lui, dans l'image que montre view_photo (de 0 à 1 depuis le coin haut gauche).", [
                        "x1": point("Premier point, depuis la gauche (0 à 1)."),
                        "y1": point("Premier point, depuis le haut (0 à 1)."),
                        "x2": point("Second point, depuis la gauche (0 à 1)."),
                        "y2": point("Second point, depuis le haut (0 à 1)."),
                    ], required: ["x1", "y1", "x2", "y2"])),
                    ("horizon_third", enumProp(["lower", "upper"], "Ligne des tiers où poser l'horizon : lower (défaut), celle du bas, deux tiers de ciel ; upper, celle du haut, quand le premier plan compte plus que le ciel.")),
                    ("subject", objectProp("Le sujet, quand ce n'est ni un visage ni la zone d'intérêt de Vision : son cadre dans l'image que montre view_photo (de 0 à 1).", [
                        "x": point("Bord gauche du sujet (0 à 1)."),
                        "y": point("Bord haut du sujet (0 à 1)."),
                        "width": point("Largeur du sujet (0 à 1)."),
                        "height": point("Hauteur du sujet (0 à 1)."),
                    ], required: ["x", "y", "width", "height"])),
                    ("facing", enumProp(["left", "right", "none"], "Vers où regarde ou avance le sujet dans l'image (none : de face) ; l'espace se laisse devant lui. Prime sur le regard lu par Vision.")),
                    ("subject_place", enumProp(["third", "center"], "third (défaut) : le sujet sur un tiers ; center : centré, pour une symétrie voulue.")),
                    ("aspect", prop("string", "Format du cadre proposé, comme crop.aspect d'apply_settings : « original » (défaut), « 1:1 », « 4:5 », « 3:2 »…")),
                    ("size", prop("number", "Taille imposée du cadre, en part du plus grand cadre possible (de \(virgule(Self.tailleCadreComposition.lowerBound)) à 1).")),
                    ("min_size", prop("number", "Taille la plus petite permise au cadre proposé, en part du plus grand possible (de \(virgule(Self.tailleCadreComposition.lowerBound)) à 1, défaut \(virgule(Self.tailleMinCompositionDefaut))).")),
                 ],
                 required: []),
        ]
    }

    /// Clés de horizon et de subject, vérifiées à la main : parametresInconnus ne voit que le premier
    /// niveau des arguments.
    static let clesHorizon = ["x1", "y1", "x2", "y2"]
    static let clesHorizonProches = ["x": "x1", "y": "y1", "start_x": "x1", "start_y": "y1", "end_x": "x2", "end_y": "y2"]
    static let clesSujet = ["x", "y", "width", "height"]
    static let clesSujetProches = ["w": "width", "h": "height", "largeur": "width", "hauteur": "height", "left": "x", "top": "y",
                                   "x1": "x", "y1": "y"]
    /// Part de l'aire du plus grand visage au-dessus de laquelle un visage compte dans le sujet.
    static let partVisageSujet = 0.25

    /// Le segment de l'horizon donné (dans l'image que montre view_photo), vérifié.
    static func horizonDonne(_ args: Arguments) throws -> (CGPoint, CGPoint)? {
        guard let brut = args.raw["horizon"], !brut.isNull else { return nil }
        guard let objet = brut.object else {
            throw LightroomError.invalid("« horizon » : {\"x1\": 0.1, \"y1\": 0.52, \"x2\": 0.9, \"y2\": 0.48}, deux points sur la ligne dans l'image que montre view_photo.")
        }
        let inconnues = objet.keys.filter { !clesHorizon.contains($0) }.sorted()
        guard inconnues.isEmpty else {
            throw LightroomError.invalid("« horizon » : clés inconnues : \(nommer(inconnues, clesHorizonProches)). Rien n'a été lu. Clés acceptées : \(clesHorizon.joined(separator: ", ")).")
        }
        func valeur(_ cle: String) throws -> Double {
            guard let nombre = objet[cle]?.double, nombre.isFinite, (0...1).contains(nombre) else {
                throw LightroomError.invalid("« horizon.\(cle) » va de 0 à 1 (fraction de l'image que montre view_photo).")
            }
            return nombre
        }
        return (CGPoint(x: try valeur("x1"), y: try valeur("y1")), CGPoint(x: try valeur("x2"), y: try valeur("y2")))
    }

    /// Le cadre du sujet donné (dans l'image que montre view_photo), vérifié.
    static func sujetDonne(_ args: Arguments) throws -> CGRect? {
        guard let brut = args.raw["subject"], !brut.isNull else { return nil }
        guard let objet = brut.object else {
            throw LightroomError.invalid("« subject » : {\"x\": 0.3, \"y\": 0.2, \"width\": 0.2, \"height\": 0.4}, le cadre du sujet dans l'image que montre view_photo.")
        }
        let inconnues = objet.keys.filter { !clesSujet.contains($0) }.sorted()
        guard inconnues.isEmpty else {
            throw LightroomError.invalid("« subject » : clés inconnues : \(nommer(inconnues, clesSujetProches)). Rien n'a été lu. Clés acceptées : \(clesSujet.joined(separator: ", ")).")
        }
        func valeur(_ cle: String) throws -> Double {
            guard let nombre = objet[cle]?.double, nombre.isFinite, (0...1).contains(nombre) else {
                throw LightroomError.invalid("« subject.\(cle) » va de 0 à 1 (fraction de l'image que montre view_photo).")
            }
            return nombre
        }
        let cadre = CGRect(x: try valeur("x"), y: try valeur("y"), width: try valeur("width"), height: try valeur("height"))
        guard cadre.width > 0.005, cadre.height > 0.005, cadre.maxX <= 1.0001, cadre.maxY <= 1.0001 else {
            throw LightroomError.invalid("« subject » doit tenir dans l'image (x + width ≤ 1, y + height ≤ 1).")
        }
        return cadre
    }

    static func choix(_ args: Arguments, _ cle: String, _ valeurs: [String], defaut: String?) throws -> String? {
        guard let brut = args.raw[cle], !brut.isNull else { return defaut }
        guard let texte = brut.string, valeurs.contains(texte) else {
            throw LightroomError.invalid("« \(cle) » vaut \(valeurs.joined(separator: ", ")).")
        }
        return texte
    }

    static func tailleComposition(_ args: Arguments, _ cle: String) throws -> Double? {
        guard args.has(cle) else { return nil }
        guard let nombre = args.double(cle), nombre.isFinite, tailleCadreComposition.contains(nombre) else {
            throw LightroomError.invalid("« \(cle) » va de \(format(tailleCadreComposition.lowerBound).replacingOccurrences(of: ".", with: ",")) à 1 (part du plus grand cadre possible).")
        }
        return nombre
    }

    /// Lit la composition sur l'image entière et propose un cadre (voir Composition.swift). Rien
    /// n'est appliqué ; le module rend l'image sans son cadre le temps de la lecture, puis la remet.
    /// `vision` : l'analyse de Vision (les tests la remplacent).
    func readComposition(_ args: Arguments, vision: (CGImage) -> VisionReport? = { VisionAnalysis.analyze($0) }) throws -> JSONValue {
        // Tout est vérifié avant d'envoyer quoi que ce soit au module.
        let segment = try Self.horizonDonne(args)
        let sujetDonne = try Self.sujetDonne(args)
        let tiers = try Self.choix(args, "horizon_third", ["lower", "upper"], defaut: "lower")
        let facing = try Self.choix(args, "facing", ["left", "right", "none"], defaut: nil)
        let place = try Self.choix(args, "subject_place", ["third", "center"], defaut: "third")
        var texteFormat: String?
        if let brut = args.raw["aspect"], !brut.isNull {
            guard let texte = brut.string else {
                throw LightroomError.invalid("« aspect » s'écrit comme « 4:5 », « 16:9 » ou « original ».")
            }
            texteFormat = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var ratioDemande: Double?
        if let texteFormat {
            do {
                ratioDemande = try Self.aspectRatio(texteFormat)
            } catch {
                throw LightroomError.invalid("« aspect » s'écrit comme « 4:5 », « 16:9 » ou « original » (reçu : « \(texteFormat) »).")
            }
        }
        let taille = try Self.tailleComposition(args, "size")
        let tailleMin = try Self.tailleComposition(args, "min_size") ?? Self.tailleMinCompositionDefaut

        // L'image entière, non recadrée (commande apercu avec entier : le module retire le cadre le
        // temps du rendu, puis le remet), et le cadre actuel vu dans cette image. Avec un horizon
        // qui peut aller au carnet, les réglages de la géométrie : Upright et la perspective restent
        // dans l'image entière, et une ligne qu'ils ont redressée ne dit plus la prise de vue.
        var params: [String: JSONValue] = ["taille": .number(Double(Self.defaultPreviewSize)),
                                           "cles": segment == nil ? [] : clesDeLaLigne, "entier": true]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        let result = try lightroom.send("apercu", params, timeout: 120)
        let data = try Self.readPreview(result["chemin"]?.string)
        guard result["image_entiere"]?.bool == true else {
            throw LightroomError.plugin("Le module de Lightroom n'a pas rendu l'image entière (module d'une version antérieure : relancer Lightroom après l'installation) ; rien n'a été lu.")
        }
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("Image entière illisible : rien n'a été lu.") }
        let dimensions = result["dimensions"]
        let aspect: Double
        if let largeur = dimensions?["largeur"]?.double, let hauteur = dimensions?["hauteur"]?.double, largeur > 0, hauteur > 0 {
            aspect = largeur / hauteur
        } else {
            aspect = Double(image.width) / Double(image.height)
        }
        var cadreActuel: Composition.Cadre?
        if let brut = result["cadre_actuel"], !brut.isNull {
            guard let cadre = Composition.Cadre(module: brut, dimensions: dimensions) else {
                throw LightroomError.plugin("Cadre actuel de la photo illisible (dimensions manquantes) : rien n'a été lu.")
            }
            cadreActuel = cadre
        }
        let angleActuel = cadreActuel?.angle ?? result["recadrage"]?["angle"]?.double ?? 0
        func borne(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(Double(p.x), 0), 1), y: min(max(Double(p.y), 0), 1)) }
        func versEntiere(_ p: CGPoint) -> CGPoint { borne(Composition.versImageEntiere(p, cadre: cadreActuel, aspect: aspect)) }

        // L'horizon, mesuré sur l'image entière : l'angle est absolu.
        var horizon: (milieu: CGPoint, mesure: LineMeasurement)?
        if let (a, b) = segment {
            let pa = versEntiere(a), pb = versEntiere(b)
            guard let (w, h, v) = Detail.luminance(image),
                  let ligne = LineAngle.measure(luminance: v, width: w, height: h, from: pa, to: pb) else {
                throw LightroomError.invalid("« horizon » : segment trop court ; choisir deux points éloignés sur la ligne (au moins un cinquième de l'image).")
            }
            guard !ligne.vertical else {
                throw LightroomError.invalid("« horizon » attend une ligne presque horizontale (pour une verticale, measure_angle).")
            }
            horizon = (CGPoint(x: (Double(pa.x) + Double(pb.x)) / 2, y: (Double(pa.y) + Double(pb.y)) / 2), ligne)
        }
        // Angle du cadre proposé : celui qui met l'horizon d'aplomb s'il penche ; sinon l'angle
        // actuel s'il le garde droit, ou aucun.
        var angle = angleActuel
        if let t = horizon?.mesure.tilt {
            if abs(t) >= Composition.seuilInclinaison {
                angle = -t
            } else if abs(t + angleActuel) >= Composition.seuilInclinaison {
                angle = 0
            }
        }
        angle = (min(max(angle, Self.cropAngleRange.lowerBound), Self.cropAngleRange.upperBound) * 100).rounded() / 100

        // Le sujet : celui donné, sinon les visages, sinon la zone d'intérêt de Vision (appelée
        // seulement sans sujet donné). Le regard n'est dit que s'il est connu : facing, ou le lacet
        // que Vision donne pour le visage principal.
        let rapport = sujetDonne == nil ? vision(image) : nil
        var sujet: CGRect?, source: String?, nomSujet = "le sujet"
        var regard: Int?, regardLu = false, regardConnu = false, hauteurYeux: Double?
        if let donne = sujetDonne {
            let coins = [CGPoint(x: donne.minX, y: donne.minY), CGPoint(x: donne.maxX, y: donne.minY),
                         CGPoint(x: donne.maxX, y: donne.maxY), CGPoint(x: donne.minX, y: donne.maxY)].map(versEntiere)
            let xs = coins.map { Double($0.x) }, ys = coins.map { Double($0.y) }
            sujet = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            source = "donne"
        } else if let visages = rapport?.faces, let principal = visages.max(by: { $0.box.width * $0.box.height < $1.box.width * $1.box.height }) {
            let aire = Double(principal.box.width * principal.box.height)
            let retenus = visages.filter { Double($0.box.width * $0.box.height) >= Self.partVisageSujet * aire }
            sujet = retenus.dropFirst().reduce(retenus[0].box) { $0.union($1.box) }
            source = "visages"
            nomSujet = retenus.count > 1 ? "les visages" : "le visage"
            regard = Composition.regard(yaw: principal.yaw)
            regardLu = regard != nil
            regardConnu = principal.yaw?.isFinite == true
            if !principal.pupils.isEmpty { hauteurYeux = principal.pupils.map { Double($0.y) }.reduce(0, +) / Double(principal.pupils.count) }
        } else if let zone = rapport?.salientArea {
            sujet = zone
            source = "zone_d_interet"
        }
        if let facing {
            regard = ["right": 1, "left": -1][facing]
            regardLu = false
            regardConnu = true
        }

        var regles = Composition.Regles(sujet: sujet, regard: regard, tailleMin: tailleMin, taille: taille)
        if let horizon { regles.horizon = (horizon.milieu, tiers == "upper" ? 1.0 / 3 : 2.0 / 3) }
        if let sujet {
            if place == "center" {
                regles.sujetX = 0.5
            } else if let regard {
                regles.sujetX = regard > 0 ? 1.0 / 3 : 2.0 / 3
            } else {
                regles.sujetX = Double(sujet.midX) <= 0.5 ? 1.0 / 3 : 2.0 / 3
            }
            if horizon == nil {
                if let hauteurYeux {
                    regles.sujetY = (hauteurYeux, 1.0 / 3)
                    regles.yeux = true
                } else {
                    regles.sujetY = (Double(sujet.midY), Double(sujet.midY) <= 0.5 ? 1.0 / 3 : 2.0 / 3)
                }
            }
        }
        let proposition = Composition.proposer(aspect: aspect, ratio: ratioDemande ?? aspect, angle: angle, regles: regles)
        let crop = Composition.crop(proposition.cadre, aspectImage: aspect, aspect: ratioDemande == nil ? "original" : texteFormat)

        func r(_ valeur: Double, _ facteur: Double = 1000) -> JSONValue { .number((valeur * facteur).rounded() / facteur) }
        let largeurImage = dimensions?["largeur"] ?? .number(Double(image.width))
        let hauteurImage = dimensions?["hauteur"] ?? .number(Double(image.height))
        // Hauteur de l'horizon dans le cadre actuel (la vue de view_photo), s'il y en a un.
        let hauteurDansCadre = cadreActuel.flatMap { cadre in
            horizon.map { Double(Composition.depuisImageEntiere($0.milieu, cadre: cadre, aspect: aspect).y) }
        }
        var reponse: [String: JSONValue] = [
            "photo": result["photo"] ?? .null,
            "image_entiere": ["largeur": largeurImage, "hauteur": hauteurImage],
            "lecture": .array(Composition.lecture(Composition.Lu(
                inclinaison: horizon?.mesure.tilt, hauteurHorizon: horizon.map { Double($0.milieu.y) }, sujet: sujet,
                nomSujet: nomSujet, regard: regard, regardLu: regardLu,
                angleActuel: cadreActuel?.angle, hauteurDansCadreActuel: hauteurDansCadre)).map(JSONValue.string)),
            "crop": crop,
            "rien_n_est_applique": "La photo est inchangée : crop n'est qu'une proposition, à montrer par preview_settings puis à appliquer après l'accord.",
            "base": .string("Positions de 0 à 1 dans l'image entière, non recadrée, depuis le coin haut gauche. Inclinaison positive : l'horizon monte vers la droite. crop : tel quel dans preview_settings (crop), sans compare, puis apply_settings avec le même crop après l'accord. Seuils de la lecture et regard lu par Vision : provisoires."),
        ]
        if let cadreActuel {
            var actuel = Composition.crop(cadreActuel, aspectImage: aspect).object ?? [:]
            actuel["resume"] = .string(Composition.resume(cadreActuel, aspectImage: aspect))
            reponse["cadre_actuel"] = .object(actuel)
        } else {
            reponse["cadre_actuel"] = "aucun"
        }
        var tenues = proposition.tenues
        if let t = horizon?.mesure.tilt {
            tenues.insert(abs(t) >= Composition.seuilInclinaison ? "horizon droit (redressé de \(Composition.decimal(abs(t), 10))°)" : "horizon droit", at: 0)
        }
        var cadrePropose: [String: JSONValue] = [
            "resume": .string(Composition.resume(proposition.cadre, aspectImage: aspect)),
            "largeur_gardee": .string("\(Int((min(proposition.cadre.largeur, 1) * 100).rounded())) %"),
            "regles_tenues": .array(tenues.map(JSONValue.string)),
            "regles_lachees": .array(proposition.lachees.map(JSONValue.string)),
        ]
        if Composition.presqueIdentique(proposition.cadre, cadreActuel, aspectImage: aspect) {
            cadrePropose["conseil"] = "Presque le cadre actuel : rien à gagner, ne pas le proposer."
        }
        reponse["cadre_propose"] = .object(cadrePropose)
        if let horizon {
            let ligne = horizon.mesure
            var objet: [String: JSONValue] = [
                "inclinaison": r(ligne.tilt, 100),
                "angle_de_recadrage": r(angle, 100),
                "angle_de_recadrage_actuel": r(angleActuel, 100),
                "hauteur": r(Double(horizon.milieu.y)),
            ]
            if let hauteurDansCadre { objet["hauteur_dans_le_cadre_actuel"] = r(hauteurDansCadre) }
            if ligne.refinedAngle != nil {
                objet["mesure"] = .string("affinée sur \(ligne.edgePoints) points du contour (écart moyen \(Composition.decimal(ligne.residual ?? 0, 10)) px)")
            } else {
                objet["mesure"] = "d'après les deux points seulement : aucun contour net le long du segment"
            }
            reponse["horizon"] = .object(objet)
            // Le carnet de progrès (1.3) : l'inclinaison sur l'image entière, si la géométrie est
            // intacte (ni recadrage tourné, ni Upright, ni perspective, ni distorsion manuelle).
            if let constat = noterLAngle(apercu: result, tilt: ligne.tilt, vertical: ligne.vertical, angleActuel: angleActuel,
                                         source: "read_composition") {
                reponse["constats_prise_de_vue"] = [.string(constat)]
            }
        }
        if let sujet, let source {
            var objet: [String: JSONValue] = [
                "source": .string(source),
                "cadre": ["x": r(Double(sujet.minX)), "y": r(Double(sujet.minY)), "width": r(Double(sujet.width)), "height": r(Double(sujet.height))],
                "centre": ["x": r(Double(sujet.midX)), "y": r(Double(sujet.midY))],
            ]
            if regardConnu {
                let sens = regard.map { $0 > 0 ? "vers la droite de l'image" : "vers la gauche de l'image" } ?? "de face"
                objet["regard"] = .string(sens + (facing != nil ? " (facing)" : " (lu par Vision, à vérifier)"))
            }
            reponse["sujet"] = .object(objet)
        }
        for cle in ["a_savoir", "original"] where result[cle] != nil { reponse[cle] = result[cle] }
        return .object(reponse)
    }
}
