import CoreGraphics
import Foundation

/// Composition lue (1.3) : le cadre de recadrage vu dans l'image entière, non recadrée, et le cadre
/// que propose read_composition (horizon droit et sur un tiers, sujet sur un tiers avec de l'espace
/// devant lui, le plus grand possible). Sans Vision ni SDK : testé tel quel.
///
/// Repère : l'image entière telle qu'elle s'affiche (orientation comprise), points de 0 à 1 depuis
/// le coin haut gauche. Les calculs se font dans un repère d'aspect A (largeur A, hauteur 1, y vers
/// le bas), où un cadre de centre C, de largeur w et de ratio r (hauteur h = w / r), tourné de θ
/// (crop.angle), a pour axes e1 = (cos θ, sin θ) et e2 = (−sin θ, cos θ) : un point (u, v) du cadre
/// (de 0 à 1, l'image recadrée que montre view_photo) est en C + (u − ½)·w·e1 + (v − ½)·h·e2. C'est
/// la convention de cadreDansZone (Recadrage.lua) : un angle positif tourne le cadre dans le sens
/// horaire sur l'image entière, et l'image recadrée dans le sens antihoraire (son côté droit monte).
public enum Composition {
    /// Écart à une ligne des tiers (ou au centre) sous lequel la lecture dit « sur le tiers » ; et
    /// distance au bord sous laquelle le sujet « touche presque » le bord. Provisoires (à relever).
    public static let seuilLecture = 0.06
    /// Inclinaison sous laquelle l'horizon ne se voit pas penché (degrés), comme pour measure_angle.
    public static let seuilInclinaison = 0.5
    /// Lacet d'un visage (radians) sous lequel il est « de face » : provisoire. Constaté sur ce Mac
    /// (révision 3 de Vision) : les observations de VNDetectFaceLandmarksRequest portent le lacet,
    /// le même que VNDetectFaceRectanglesRequest, par pas de π/4 (0 et −π/2 relevés).
    public static let seuilLacet = 0.26
    /// Signe du lacet de Vision pour un visage tourné vers la droite de l'image : à constater sur
    /// des portraits (un visage tourné relevé dans Lightroom) ; +1 en attendant.
    public static let signeLacet = 1.0
    /// Marge du sujet dans le cadre, en part du cadre.
    public static let margeSujet = 0.03
    /// Le cadre proposé est réduit de 0,2 % : arrondis du module (taille au dix-millième, angle au
    /// centième) sans que Lightroom le resserre ni que le module le dise « réduit ».
    public static let margeArrondis = 0.998

    // MARK: Le cadre

    public struct Cadre: Equatable {
        /// Centre, de 0 à 1 dans l'image entière.
        public var centreX: Double
        public var centreY: Double
        /// Largeur du cadre, en part de la largeur de l'image entière.
        public var largeur: Double
        /// Largeur sur hauteur du cadre.
        public var ratio: Double
        /// Degrés, convention de crop.angle.
        public var angle: Double

        public init(centreX: Double, centreY: Double, largeur: Double, ratio: Double, angle: Double) {
            self.centreX = centreX
            self.centreY = centreY
            self.largeur = largeur
            self.ratio = ratio
            self.angle = angle
        }

        /// Un cadre du module (`cadre_actuel` de la commande apercu avec entier, `cadre_propose` de
        /// essayer avec entier : Recadrage.lire, largeur en pixels de l'image affichée) et les
        /// dimensions de l'image affichée entière ({largeur, hauteur} en pixels). Nil s'il manque
        /// quelque chose.
        public init?(module: JSONValue?, dimensions: JSONValue?) {
            guard let module, let dimensions,
                  let ratio = module["ratio"]?.double, let angle = module["angle"]?.double,
                  let x = module["centre_x"]?.double, let y = module["centre_y"]?.double,
                  let pixels = module["largeur"]?.double, let largeurImage = dimensions["largeur"]?.double,
                  [ratio, angle, x, y, pixels, largeurImage].allSatisfy(\.isFinite),
                  ratio > 0, pixels > 0, largeurImage > 0 else { return nil }
            self.init(centreX: x, centreY: y, largeur: pixels / largeurImage, ratio: ratio, angle: angle)
        }
    }

    /// Dans le repère d'aspect A.
    struct Vecteur {
        var x: Double
        var y: Double
        func scalaire(_ autre: Vecteur) -> Double { x * autre.x + y * autre.y }
    }

    static func axes(_ angle: Double) -> (e1: Vecteur, e2: Vecteur) {
        let t = angle * .pi / 180
        return (Vecteur(x: cos(t), y: sin(t)), Vecteur(x: -sin(t), y: cos(t)))
    }

    /// Un point de l'image recadrée (celle que montre view_photo, de 0 à 1) dans l'image entière ;
    /// l'identité sans cadre.
    public static func versImageEntiere(_ p: CGPoint, cadre: Cadre?, aspect: Double) -> CGPoint {
        guard let cadre else { return p }
        let (e1, e2) = axes(cadre.angle)
        let w = cadre.largeur * aspect, h = w / cadre.ratio
        let a = (Double(p.x) - 0.5) * w, b = (Double(p.y) - 0.5) * h
        let x = cadre.centreX * aspect + a * e1.x + b * e2.x
        let y = cadre.centreY + a * e1.y + b * e2.y
        return CGPoint(x: x / aspect, y: y)
    }

    /// L'inverse : un point de l'image entière dans l'image recadrée (hors de 0…1 s'il est coupé).
    public static func depuisImageEntiere(_ q: CGPoint, cadre: Cadre?, aspect: Double) -> CGPoint {
        guard let cadre else { return q }
        let (e1, e2) = axes(cadre.angle)
        let w = cadre.largeur * aspect, h = w / cadre.ratio
        let d = Vecteur(x: (Double(q.x) - cadre.centreX) * aspect, y: Double(q.y) - cadre.centreY)
        return CGPoint(x: d.scalaire(e1) / w + 0.5, y: d.scalaire(e2) / h + 0.5)
    }

    /// Les coins du cadre dans l'image entière : haut gauche, haut droit, bas droit, bas gauche.
    public static func coins(_ cadre: Cadre, aspect: Double) -> [CGPoint] {
        [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
            .map { versImageEntiere($0, cadre: cadre, aspect: aspect) }
    }

    /// Boîte englobante d'un cadre de largeur 1 et de hauteur 1 / ratio, tourné de l'angle.
    static func boite(ratio: Double, angle: Double) -> (bx: Double, by: Double) {
        let t = abs(angle) * .pi / 180
        return (cos(t) + sin(t) / ratio, sin(t) + cos(t) / ratio)
    }

    /// Largeur du plus grand cadre de ce ratio et de cet angle dans l'image entière, en part de sa
    /// largeur : la variable `maximum` de Recadrage.calculer (sans zone), divisée par la largeur.
    public static func plusGrandeLargeur(ratio: Double, angle: Double, aspect: Double) -> Double {
        let (bx, by) = boite(ratio: ratio, angle: angle)
        return min(aspect / bx, 1 / by) / aspect
    }

    // MARK: Le cadre proposé

    /// Ce que le cadre proposé doit tenir. Positions dans l'image entière (de 0 à 1).
    public struct Regles {
        /// Un point de l'horizon et la ligne du cadre où le poser (2/3 : le tiers du bas ; 1/3 : du haut).
        public var horizon: (point: CGPoint, ligne: Double)?
        /// Le sujet ; son centre se place sur `sujetX` (part de la largeur du cadre).
        public var sujet: CGRect?
        public var sujetX: Double?
        /// Sans horizon : la hauteur `y` (pupilles, ou centre du sujet) posée sur la ligne `ligne`.
        public var sujetY: (y: Double, ligne: Double)?
        /// Regard du sujet (+1 vers la droite de l'image, −1 vers la gauche), pour dire l'espace devant.
        public var regard: Int?
        /// `sujetY` vient des pupilles.
        public var yeux = false
        public var marge = Composition.margeSujet
        public var tailleMin = ToolHandler.tailleMinCompositionDefaut
        /// Taille imposée, en part du plus grand cadre.
        public var taille: Double?

        init(horizon: (point: CGPoint, ligne: Double)? = nil, sujet: CGRect? = nil, sujetX: Double? = nil,
             sujetY: (y: Double, ligne: Double)? = nil, regard: Int? = nil, yeux: Bool = false,
             tailleMin: Double = ToolHandler.tailleMinCompositionDefaut, taille: Double? = nil) {
            self.horizon = horizon
            self.sujet = sujet
            self.sujetX = sujetX
            self.sujetY = sujetY
            self.regard = regard
            self.yeux = yeux
            self.tailleMin = tailleMin
            self.taille = taille
        }
    }

    public struct Proposition {
        public var cadre: Cadre
        public var tenues: [String]
        public var lachees: [String]
    }

    /// Les règles tenues par un essai de placement.
    struct Placement {
        var horizon: (point: CGPoint, ligne: Double)?
        var sujetX: Double?
        var sujetY: (y: Double, ligne: Double)?
        var interieur = false
        var tenues: [String] = []
        var lachees: [String] = []
    }

    static func texteHorizon(_ ligne: Double) -> String {
        ligne > 0.5 ? "horizon sur le tiers du bas" : "horizon sur le tiers du haut"
    }

    static func texteSujetX(_ x: Double, regard: Int?) -> String {
        if abs(x - 0.5) < 1e-9 { return "sujet centré" }
        let texte = "sujet sur le tiers \(x < 0.5 ? "gauche" : "droit")"
        // Regard vers la droite et sujet à gauche (ou l'inverse) : l'espace est devant lui.
        if let regard, regard != 0, (regard > 0) == (x < 0.5) { return texte + ", de l'espace devant lui" }
        return texte
    }

    static func texteSujetY(_ ligne: Double, yeux: Bool) -> String {
        if abs(ligne - 0.5) < 1e-9 { return yeux ? "yeux à mi-hauteur" : "sujet centré en hauteur" }
        return "\(yeux ? "yeux" : "sujet") sur le tiers \(ligne < 0.5 ? "haut" : "bas")"
    }

    static let sujetEntier = "sujet entier dans le cadre"

    /// Le cadre proposé, et les règles tenues et lâchées. Chaque contrainte est affine en w (la
    /// largeur du cadre dans le repère d'aspect A) : le centre C(w) = α·e1 + β·e2, avec
    /// β = P·e2 − (ligne − ½)·w / ratio pour l'horizon (ou la hauteur du sujet) et
    /// α = S·e1 − (sujetX − ½)·w pour le sujet ; la boîte englobante du cadre tient dans l'image
    /// (la règle du module sans zone) et les coins du sujet restent à `marge` des bords du cadre.
    /// On prend la plus grande w permise (au moins tailleMin du plus grand cadre), ou la taille
    /// imposée. Sans solution, on lâche dans l'ordre : le sujet sur le tiers, puis le sujet centré,
    /// puis l'horizon sur le tiers (le plus grand cadre centré, à cet angle).
    public static func proposer(aspect: Double, ratio: Double, angle: Double, regles: Regles) -> Proposition {
        // L'angle comme le module le pose : au centième.
        let angle = (min(max(angle, ToolHandler.cropAngleRange.lowerBound), ToolHandler.cropAngleRange.upperBound) * 100).rounded() / 100
        let wmax = plusGrandeLargeur(ratio: ratio, angle: angle, aspect: aspect) * aspect
        var essais: [Placement] = []
        if regles.sujet != nil {
            let sx = regles.sujetX ?? 0.5
            let texteX = texteSujetX(sx, regard: regles.regard)
            let auTiers = abs(sx - 0.5) > 1e-9
            if let horizon = regles.horizon {
                let h = texteHorizon(horizon.ligne)
                essais.append(Placement(horizon: horizon, sujetX: sx, interieur: true, tenues: [h, texteX, sujetEntier]))
                if auTiers {
                    essais.append(Placement(horizon: horizon, sujetX: 0.5, interieur: true, tenues: [h, "sujet centré", sujetEntier], lachees: [texteX]))
                }
                essais.append(Placement(horizon: horizon, tenues: [h], lachees: [texteX]))
                essais.append(Placement(lachees: [h, texteX]))
            } else if let sy = regles.sujetY {
                let texteY = texteSujetY(sy.ligne, yeux: regles.yeux)
                essais.append(Placement(sujetX: sx, sujetY: sy, interieur: true, tenues: [texteX, texteY, sujetEntier]))
                if auTiers {
                    essais.append(Placement(sujetX: 0.5, sujetY: sy, interieur: true, tenues: ["sujet centré", texteY, sujetEntier], lachees: [texteX]))
                }
                if abs(sy.ligne - 0.5) > 1e-9 {
                    essais.append(Placement(sujetX: 0.5, sujetY: (sy.y, 0.5), interieur: true,
                                            tenues: ["sujet centré", texteSujetY(0.5, yeux: regles.yeux), sujetEntier],
                                            lachees: auTiers ? [texteX, texteY] : [texteY]))
                }
                essais.append(Placement(lachees: [texteX, texteY]))
            } else {
                // Ni horizon ni hauteur voulue : le cadre se centre en hauteur sur l'image.
                essais.append(Placement(sujetX: sx, interieur: true, tenues: [texteX, sujetEntier]))
                if auTiers {
                    essais.append(Placement(sujetX: 0.5, interieur: true, tenues: ["sujet centré", sujetEntier], lachees: [texteX]))
                }
                essais.append(Placement(lachees: [texteX]))
            }
        } else if let horizon = regles.horizon {
            let h = texteHorizon(horizon.ligne)
            essais.append(Placement(horizon: horizon, tenues: [h]))
            essais.append(Placement(lachees: [h]))
        } else {
            essais.append(Placement())
        }
        for essai in essais {
            guard let solution = resoudre(aspect: aspect, ratio: ratio, angle: angle, sujet: regles.sujet, marge: regles.marge, placement: essai),
                  let w = choisir(bas: solution.bas, haut: solution.haut, wmax: wmax, regles: regles) else { continue }
            let centre = solution.centre(w)
            let cadre = Cadre(centreX: centre.x / aspect, centreY: centre.y, largeur: w / aspect, ratio: ratio, angle: angle)
            var tenues = essai.tenues, lachees = essai.lachees
            // Sans règle du sujet, il peut être entier ou coupé : le dire.
            if !essai.interieur, let sujet = regles.sujet {
                if contient(cadre, sujet, aspect: aspect) { tenues.append(sujetEntier) } else { lachees.append(sujetEntier + " (il est coupé)") }
            }
            return Proposition(cadre: cadre, tenues: tenues, lachees: lachees)
        }
        // Le dernier essai (le plus grand cadre centré) tient toujours ; par sûreté :
        let w = (regles.taille.map { min($0, margeArrondis) } ?? margeArrondis) * wmax
        return Proposition(cadre: Cadre(centreX: 0.5, centreY: 0.5, largeur: w / aspect, ratio: ratio, angle: angle),
                           tenues: [], lachees: essais.last?.lachees ?? [])
    }

    /// Intervalle des largeurs permises par un placement, et le centre en fonction de la largeur
    /// (repère d'aspect A). Nil sans solution.
    static func resoudre(aspect a: Double, ratio: Double, angle: Double, sujet: CGRect?, marge: Double,
                         placement: Placement) -> (bas: Double, haut: Double, centre: (Double) -> Vecteur)? {
        let (e1, e2) = axes(angle)
        let milieu = Vecteur(x: a / 2, y: 0.5)
        var alpha0 = milieu.scalaire(e1), alpha1 = 0.0
        var beta0 = milieu.scalaire(e2), beta1 = 0.0
        let centreSujet = sujet.map { Vecteur(x: Double($0.midX) * a, y: Double($0.midY)) }
        if let horizon = placement.horizon {
            beta0 = Vecteur(x: Double(horizon.point.x) * a, y: Double(horizon.point.y)).scalaire(e2)
            beta1 = -(horizon.ligne - 0.5) / ratio
        } else if let sy = placement.sujetY, let s = centreSujet {
            beta0 = Vecteur(x: s.x, y: sy.y).scalaire(e2)
            beta1 = -(sy.ligne - 0.5) / ratio
        }
        if let sx = placement.sujetX, let s = centreSujet {
            alpha0 = s.scalaire(e1)
            alpha1 = -(sx - 0.5)
        }
        // C(w) = (α0 + α1·w)·e1 + (β0 + β1·w)·e2.
        let cx0 = alpha0 * e1.x + beta0 * e2.x, cx1 = alpha1 * e1.x + beta1 * e2.x
        let cy0 = alpha0 * e1.y + beta0 * e2.y, cy1 = alpha1 * e1.y + beta1 * e2.y
        let (bx, by) = boite(ratio: ratio, angle: angle)
        // Chaque contrainte : c + d·w ≥ 0.
        var contraintes: [(c: Double, d: Double)] = [
            (cx0, cx1 - bx / 2), (a - cx0, -cx1 - bx / 2),
            (cy0, cy1 - by / 2), (1 - cy0, -cy1 - by / 2),
        ]
        if placement.interieur, let sujet {
            let m = 0.5 - marge
            let points = [(sujet.minX, sujet.minY), (sujet.maxX, sujet.minY), (sujet.maxX, sujet.maxY), (sujet.minX, sujet.maxY)]
            for (x, y) in points {
                let k = Vecteur(x: Double(x) * a, y: Double(y))
                let k1 = k.scalaire(e1), k2 = k.scalaire(e2)
                contraintes.append((k1 - alpha0, -alpha1 + m))
                contraintes.append((alpha0 - k1, alpha1 + m))
                contraintes.append((k2 - beta0, -beta1 + m / ratio))
                contraintes.append((beta0 - k2, beta1 + m / ratio))
            }
        }
        var bas = 1e-6, haut = Double.infinity
        for (c, d) in contraintes {
            if abs(d) < 1e-12 {
                if c < -1e-12 { return nil }
                continue
            }
            let borne = -c / d
            if d > 0 { bas = max(bas, borne) } else { haut = min(haut, borne) }
        }
        guard haut.isFinite, haut >= bas else { return nil }
        return (bas, haut, { w in Vecteur(x: cx0 + cx1 * w, y: cy0 + cy1 * w) })
    }

    /// La largeur retenue dans [bas, haut] : la plus grande (au moins tailleMin du plus grand
    /// cadre), réduite de la marge des arrondis ; ou la taille imposée.
    static func choisir(bas: Double, haut: Double, wmax: Double, regles: Regles) -> Double? {
        let haut = min(haut, wmax)
        guard haut >= bas else { return nil }
        if let taille = regles.taille {
            let voulu = taille * wmax
            guard voulu >= bas * (1 - 1e-9), voulu <= haut * (1 + 1e-9) else { return nil }
            return max(bas, min(voulu, haut * margeArrondis))
        }
        // La marge des arrondis passe avant tailleMin : un cadre tout juste assez grand perd 0,2 %.
        let mini = max(bas, regles.tailleMin * wmax)
        guard haut >= mini * (1 - 1e-9) else { return nil }
        return max(bas, haut * margeArrondis)
    }

    /// Le rectangle (image entière) est-il tout entier dans le cadre ?
    static func contient(_ cadre: Cadre, _ rect: CGRect, aspect: Double) -> Bool {
        [(rect.minX, rect.minY), (rect.maxX, rect.minY), (rect.maxX, rect.maxY), (rect.minX, rect.maxY)].allSatisfy { x, y in
            let p = depuisImageEntiere(CGPoint(x: x, y: y), cadre: cadre, aspect: aspect)
            return (-1e-6...1.000001).contains(Double(p.x)) && (-1e-6...1.000001).contains(Double(p.y))
        }
    }

    // MARK: Textes et chiffres

    /// Le cadre comme crop d'apply_settings et de preview_settings (cropParameter l'accepte tel
    /// quel) : format (« original » ou celui demandé), angle au centième, taille au dix-millième (en
    /// part du plus grand cadre de ce format à cet angle), centre au dix-millième.
    public static func crop(_ cadre: Cadre, aspectImage: Double, aspect: String? = nil) -> JSONValue {
        let maximum = plusGrandeLargeur(ratio: cadre.ratio, angle: cadre.angle, aspect: aspectImage)
        func r(_ valeur: Double, _ facteur: Double) -> JSONValue { .number((valeur * facteur).rounded() / facteur) }
        return [
            "aspect": .string(aspect ?? texteFormat(cadre.ratio, aspectImage: aspectImage)),
            "angle": r(cadre.angle, 100),
            "size": r(min(1, cadre.largeur / maximum), 10_000),
            "center_x": r(cadre.centreX, 10_000),
            "center_y": r(cadre.centreY, 10_000),
        ]
    }

    /// « original » si le cadre a le format de l'image, sinon « 4:5 », « 16:9 », « 1,52:1 »…
    static func texteFormat(_ ratio: Double, aspectImage: Double) -> String {
        abs(ratio - aspectImage) <= 0.005 * aspectImage ? "original" : texteRatio(ratio)
    }

    /// « 3:2 », « 4:5 », « 16:9 » (à 0,5 % près, dénominateur de 1 à 10), sinon « 1,52:1 ».
    static func texteRatio(_ ratio: Double) -> String {
        for denominateur in 1...10 {
            let numerateur = (ratio * Double(denominateur)).rounded()
            if numerateur >= 1, abs(numerateur / Double(denominateur) - ratio) <= 0.005 * ratio {
                return "\(Int(numerateur)):\(denominateur)"
            }
        }
        return "\(decimal(ratio, 100)):1"
    }

    static func decimal(_ valeur: Double, _ facteur: Double) -> String {
        DevelopCatalogue.format((valeur * facteur).rounded() / facteur).replacingOccurrences(of: ".", with: ",")
    }

    /// « 3:2 (format d'origine), redressé de 1,4°, 82 % de la largeur gardée ».
    public static func resume(_ cadre: Cadre, aspectImage: Double) -> String {
        var parties = [texteRatio(cadre.ratio) + (abs(cadre.ratio - aspectImage) <= 0.005 * aspectImage ? " (format d'origine)" : "")]
        if abs(cadre.angle) >= 0.05 { parties.append("redressé de \(decimal(abs(cadre.angle), 10))°") }
        parties.append("\(Int((min(cadre.largeur, 1) * 100).rounded())) % de la largeur gardée")
        return parties.joined(separator: ", ")
    }

    /// Le cadre proposé ne change presque rien au cadre actuel (ou à l'image entière, sans cadre).
    public static func presqueIdentique(_ propose: Cadre, _ actuel: Cadre?, aspectImage: Double) -> Bool {
        let reference = actuel ?? Cadre(centreX: 0.5, centreY: 0.5, largeur: 1, ratio: aspectImage, angle: 0)
        return abs(propose.centreX - reference.centreX) < 0.01 && abs(propose.centreY - reference.centreY) < 0.01
            && abs(propose.largeur - reference.largeur) < 0.02 && abs(propose.angle - reference.angle) < 0.2
            && abs(propose.ratio - reference.ratio) <= 0.01 * reference.ratio
    }

    /// Sens du regard d'après le lacet d'un visage (Vision) : +1 vers la droite de l'image, −1 vers
    /// la gauche, nil de face (sous `seuilLacet`) ou sans lacet.
    public static func regard(yaw: Double?) -> Int? {
        guard let yaw, yaw.isFinite, abs(yaw) >= seuilLacet else { return nil }
        return yaw * signeLacet > 0 ? 1 : -1
    }

    // MARK: Lecture

    /// Ce que read_composition a lu, pour les phrases de la lecture. Positions dans l'image lue
    /// (l'image entière, telle qu'elle a été prise).
    public struct Lu {
        /// Inclinaison de l'horizon en degrés (positive : il monte vers la droite).
        public var inclinaison: Double?
        /// Hauteur de l'horizon (0 en haut, 1 en bas).
        public var hauteurHorizon: Double?
        public var sujet: CGRect?
        /// « le visage », « les visages », « le sujet ».
        public var nomSujet = "le sujet"
        public var regard: Int?
        /// Le regard vient du lacet lu par Vision (provisoire), pas de facing.
        public var regardLu = false
    }

    /// Ce qui cloche (ou tient), en phrases simples, à dire à l'utilisateur pour qu'il cadre mieux à
    /// la prise de vue. Seuils provisoires (`seuilLecture`).
    public static func lecture(_ lu: Lu) -> [String] {
        var phrases: [String] = []
        let s = seuilLecture
        if let t = lu.inclinaison {
            if abs(t) >= seuilInclinaison {
                phrases.append("L'horizon penche de \(decimal(abs(t), 10))° (le côté droit plus \(t > 0 ? "haut" : "bas")).")
            } else {
                phrases.append("L'horizon est droit.")
            }
        }
        if let y = lu.hauteurHorizon {
            if abs(y - 0.5) < s {
                phrases.append("Il coupe la photo en deux : sur un tiers, le ciel ou le premier plan prend la place.")
            } else if abs(y - 2.0 / 3) < s {
                phrases.append("Il est sur le tiers du bas.")
            } else if abs(y - 1.0 / 3) < s {
                phrases.append("Il est sur le tiers du haut.")
            } else {
                phrases.append("Il passe à \(Int((y * 100).rounded())) % de la hauteur, depuis le haut.")
            }
        }
        if let sujet = lu.sujet {
            let x = Double(sujet.midX)
            let place: String
            if abs(x - 0.5) < s { place = "au centre" }
            else if abs(x - 1.0 / 3) < s { place = "sur le tiers gauche" }
            else if abs(x - 2.0 / 3) < s { place = "sur le tiers droit" }
            else { place = x < 0.5 ? "à gauche" : "à droite" }
            let verbe = lu.nomSujet.hasPrefix("les ") ? "sont" : "est"
            let regarde = lu.nomSujet.hasPrefix("les ") ? "regardent" : "regarde"
            var phrase = "\(lu.nomSujet.prefix(1).uppercased())\(lu.nomSujet.dropFirst()) \(verbe) \(place)"
            if let regard = lu.regard, regard != 0 {
                phrase += " et \(regarde) vers la \(regard > 0 ? "droite" : "gauche")"
                if lu.regardLu { phrase += " (lu par Vision, à vérifier à l'œil)" }
                let devant = regard > 0 ? 1 - x : x
                phrase += devant < 0.6 ? " : peu d'espace devant lui" : " : de l'espace devant lui"
            }
            phrases.append(phrase + ".")
            var bords: [String] = []
            if Double(sujet.minX) < s { bords.append("le bord gauche") }
            if Double(sujet.maxX) > 1 - s { bords.append("le bord droit") }
            if Double(sujet.minY) < s { bords.append("le haut") }
            if Double(sujet.maxY) > 1 - s { bords.append("le bas") }
            if bords.count >= 3 {
                phrases.append("Le sujet remplit presque toute la photo.")
            } else if !bords.isEmpty {
                phrases.append("Le sujet touche presque \(bords.joined(separator: " et ")).")
            }
        }
        if phrases.isEmpty {
            phrases.append("Ni horizon donné ni sujet trouvé : rien à lire. Donner horizon (deux points) ou subject.")
        }
        return phrases
    }
}
