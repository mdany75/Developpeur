import CoreGraphics
import Foundation
import Vision

/// L'éclairage d'un aperçu, lu sur ses tons presque neutres (des gris dans la réalité, qui prennent
/// la couleur de la lumière) : leur dominante (médiane de a* et b*) par zone tonale (ombres, tons
/// moyens, hautes lumières) et par case d'une grille 3 × 3. Deux groupes de cases de couleurs
/// différentes disent un éclairage mixte (une lampe et une fenêtre dans la même pièce). Les visages
/// sont mis à part : leur peau, et la lumière autour d'eux, sans la peau.
public struct MesureEclairage: Equatable {
    /// Dominante d'une zone : médianes de a* et b* de ses tons presque neutres (à 0,05 près,
    /// `Eclairage.Histogramme`).
    public struct Dominante: Equatable {
        public var a: Double
        public var b: Double
        /// Part de la zone en tons presque neutres, en % (de la case, de l'image pour une zone
        /// tonale, de l'anneau autour d'un visage).
        public var part: Double
        public var pixels: Int
    }

    /// Peau d'un visage : médianes de L*, a* et b* au milieu du visage.
    public struct Peau: Equatable {
        public var l: Double
        public var a: Double
        public var b: Double
        /// atan2(b*, a*), en degrés.
        public var teinte: Double
    }

    /// Point neutre de l'image : médianes de a* et b* de ses tons peu saturés, c'est-à-dire sa
    /// dominante globale (la balance des blancs) ; les tons presque neutres se prennent autour de lui.
    public struct Neutre: Equatable {
        public var a: Double
        public var b: Double
    }

    public struct Visage: Equatable {
        /// Rang du visage dans la liste donnée à la mesure (`vision.visages` de view_photo, du plus
        /// large au plus petit) : les visages trop petits ou au-delà de `Eclairage.maxVisages` ne
        /// sont pas mesurés, et la liste de la mesure peut être plus courte.
        public var index: Int = 0
        /// Cadre de Vision (fractions de l'image, depuis le haut gauche).
        public var cadre: CGRect
        public var peau: Peau?
        /// Lumière qui l'éclaire : tons neutres autour du visage, sans la peau ; ou ceux de sa case.
        public var lumiere: Dominante?
        /// « anneau » (autour du visage) ou « case » (sa case de la grille) ; nil sans lumière lue.
        public var source: String?
        /// Le groupe de lumière le plus proche (0 : le plus chaud ou le plus magenta).
        public var groupe: Int?
    }

    /// Un groupe de cases éclairées par la même lumière.
    public struct Groupe: Equatable {
        /// Cases de la grille (0 à 8, ligne par ligne depuis le haut gauche).
        public var cases: [Int]
        /// Moyenne des médianes des cases, pondérée par leurs pixels neutres.
        public var a: Double
        public var b: Double
        /// Part des tons neutres lus, en %.
        public var poids: Double
    }

    /// Ombres (L* de 15 à 40), tons moyens (40 à 70), hautes lumières (70 à 95) ; nil : trop peu de
    /// tons neutres.
    public var tonales: [Dominante?]
    /// Les 9 cases, ligne par ligne depuis le haut gauche ; nil : case illisible.
    public var regions: [Dominante?]
    /// Deux groupes de lumière (le plus chaud d'abord, ou le plus magenta si l'écart tient surtout
    /// à a*), ou aucun.
    public var groupes: [Groupe]
    /// Distance a*b* entre les deux groupes.
    public var ecartRegions: Double?
    /// Distance a*b* entre les ombres et les hautes lumières.
    public var ecartTonal: Double?
    public var visages: [Visage]
    /// Lumière des visages (moyenne pondérée par leur largeur) ou du sujet (zone d'intérêt).
    public var lumiereSujet: Dominante?
    /// « visages » ou « zone d'intérêt ».
    public var sujetSource: String?
    /// Écart a*b* au centre (`centre`) des tons presque neutres de cette mesure.
    public var borne: Double
    /// Point neutre de l'image : médianes de ses tons peu saturés (sa dominante globale).
    public var neutre = Neutre(a: 0, b: 0)
    /// Centre des tons presque neutres : le gris, ou le point neutre ramené vers lui de
    /// `Eclairage.toleranceNeutre` (`Eclairage.centrer`).
    public var centre = Neutre(a: 0, b: 0)

    public var mixte: Bool { (ecartRegions ?? 0) >= Eclairage.seuilMixte }

    /// L'écart entre les deux groupes tient surtout à a* (vert-magenta) plutôt qu'à b* (bleu-jaune).
    var axeMagenta: Bool {
        guard groupes.count == 2 else { return false }
        return abs(groupes[0].a - groupes[1].a) > abs(groupes[0].b - groupes[1].b)
    }

    /// Noms des deux lumières : la première, puis la seconde.
    var nomsLumieres: (String, String) { axeMagenta ? ("plus magenta", "plus verte") : ("plus chaude", "plus froide") }

    public var lecture: String {
        guard regions.compactMap({ $0 }).count >= Eclairage.casesMin else {
            return "trop peu de tons neutres par zone pour lire l'éclairage"
        }
        guard groupes.count == 2, let ecart = ecartRegions else {
            return "une zone porte presque tous les tons neutres : l'éclairage ne se compare pas d'une zone à l'autre"
        }
        let e = Eclairage.texte
        guard mixte else {
            return "une seule lumière (écart entre zones \(e(ecart, 1)), sous \(Eclairage.nombre(Eclairage.seuilMixte)))"
        }
        let (premiere, seconde) = nomsLumieres
        let g0 = groupes[0], g1 = groupes[1]
        var texte = "éclairage mixte : \(premiere) \(Eclairage.nommer(g0.cases)) (a* \(e(g0.a, 0)), b* \(e(g0.b, 0))), "
            + "\(seconde) \(Eclairage.nommer(g1.cases)) (a* \(e(g1.a, 0)), b* \(e(g1.b, 0))) ; écart \(e(ecart, 1))"
        let groupesDesVisages = Set(visages.compactMap(\.groupe))
        if groupesDesVisages.count == 2 {
            texte += " ; visages dans les deux lumières"
        } else if let groupe = groupesDesVisages.first {
            texte += " ; visages dans la lumière \(groupe == 0 ? premiere : seconde)"
        }
        return texte
    }

    /// Les ombres d'une autre couleur que les hautes lumières (une lumière d'appoint, ou une
    /// dominante des seules ombres) ; nil sous `Eclairage.seuilTonal`.
    public var lectureTonale: String? {
        guard let ecart = ecartTonal, ecart >= Eclairage.seuilTonal,
              let ombres = tonales[0], let hautes = tonales[2] else { return nil }
        let e = Eclairage.texte
        let parA = abs(ombres.a - hautes.a) > abs(ombres.b - hautes.b)
        let sens: String
        if parA {
            sens = "ombres \(ombres.a < hautes.a ? "plus vertes" : "plus magenta") que les hautes lumières (a* \(e(ombres.a, 0)) contre \(e(hautes.a, 0)))"
        } else {
            sens = "ombres \(ombres.b < hautes.b ? "plus froides" : "plus chaudes") que les hautes lumières (b* \(e(ombres.b, 0)) contre \(e(hautes.b, 0)))"
        }
        return sens + " : lumière d'appoint d'une autre couleur, ou dominante des ombres (ShadowTint, Color Grading des ombres)"
    }

    /// Que faire d'un éclairage mixte : dit dans le résultat même, au moment où la mesure le justifie.
    var conseil: String {
        let debut = "Éclairage mixte, à confirmer à l'œil (un mur coloré n'est pas une lumière) : le dire à l'utilisateur. "
        let suite = "puis l'autre zone par un masque (add_mask : dégradé linéaire ou radial, ou objet, sur les cases nommées ; "
            + "Temperature et Tint locaux contre son écart), ou gardée chaude si c'est une lampe. "
        if sujetSource == "visages" {
            return debut + "Balance des blancs sur la lumière des visages (balance_proposee, ou white_balance_point sur un gris près d'eux) ; "
                + suite + "Vérifier par view_photo : ecart_regions baisse, la peau reste naturelle."
        }
        return debut + "Balance des blancs sur la lumière du sujet (balance_proposee, d'après la zone d'intérêt de Vision ; sinon la lumière la plus étendue) ; "
            + suite + "Vérifier par view_photo : ecart_regions baisse."
    }

    var base: String {
        let f = Eclairage.nombre, e = Eclairage.texte
        return "Tons presque neutres : à moins de \(f(borne)) en a*b* du gris, ou du point neutre de l'image (a* \(e(neutre.a, 1)), "
            + "b* \(e(neutre.b, 1)) : médiane de ses tons peu saturés) quand une dominante globale l'en écarte de plus de "
            + "\(f(Eclairage.toleranceNeutre)) (centre ici : a* \(e(centre.a, 1)), b* \(e(centre.b, 1))) ; L* \(f(Eclairage.lumineuxMin)) à "
            + "\(f(Eclairage.lumineuxMax)), sans visages ni pixels écrêtés, aperçu réduit à \(Measurements.maxSide) px. Médianes par zone "
            + "tonale (L* < \(f(Eclairage.limitesTonales[0])), \(f(Eclairage.limitesTonales[0])) à \(f(Eclairage.limitesTonales[1])), "
            + "> \(f(Eclairage.limitesTonales[1]))) et par case 3 × 3 (lue à partir de \(f(PhotoMeasurements.partNeutreMin)) % de tons "
            + "neutres). ecart_regions : distance a*b* entre les deux groupes de cases les plus différents (chacun au moins "
            + "\(f(Eclairage.partMinGroupe)) % des tons neutres lus) ; mixte à partir de \(f(Eclairage.seuilMixte)) (relevé le "
            + "20 octobre 2026). Visages : peau, et lumière autour (sans la peau)."
    }

    /// view_photo › mesures › eclairage. La forme courte (avant/après, proposition, série) garde la
    /// lecture, l'écart et les zones tonales. La grille, les groupes, la balance, le conseil et la
    /// base ne partent que si l'éclairage est mixte (view_photo s'appelle souvent : une photo à une
    /// seule lumière n'en reçoit que la lecture, les zones tonales et ses visages).
    public func json(balance: (temperature: Double, tint: Double)?, court: Bool = false) -> JSONValue {
        func r(_ value: Double) -> JSONValue { .number((value * 10).rounded() / 10) }
        var objet: [String: JSONValue] = ["lecture": .string(lecture), "mixte": .bool(mixte)]
        if let ecartRegions { objet["ecart_regions"] = r(ecartRegions) }
        var zones: [String: JSONValue] = [:]
        for (index, nom) in ["ombres", "tons_moyens", "hautes_lumieres"].enumerated() {
            if let zone = tonales[index] {
                zones[nom] = ["a": r(zone.a), "b": r(zone.b), "part_pct": r(zone.part)]
            } else {
                zones[nom] = "trop peu de tons neutres"
            }
        }
        objet["zones_tonales"] = .object(zones)
        if let lectureTonale { objet["lecture_tonale"] = .string(lectureTonale) }
        guard !court else { return .object(objet) }

        let (premiere, seconde) = nomsLumieres
        if !visages.isEmpty {
            objet["visages"] = .array(visages.map { visage in
                // Le rang dans vision.visages : la liste de la mesure peut en sauter (trop petits).
                var item: [String: JSONValue] = ["index_vision": .number(Double(visage.index))]
                if let peau = visage.peau {
                    item["peau"] = ["L": r(peau.l), "a": r(peau.a), "b": r(peau.b), "teinte_deg": .number(peau.teinte.rounded())]
                }
                if let lumiere = visage.lumiere {
                    item["lumiere"] = ["a": r(lumiere.a), "b": r(lumiere.b)]
                    item["lumiere_mesuree"] = .string(visage.source == "anneau" ? "autour du visage" : "dans sa case")
                } else {
                    item["lumiere_mesuree"] = "trop peu de tons neutres autour"
                }
                if mixte, let groupe = visage.groupe { item["dans_la_lumiere"] = .string(groupe == 0 ? premiere : seconde) }
                return .object(item)
            })
        }
        if mixte {
            objet["regions_3x3"] = .array(stride(from: 0, to: 9, by: 3).map { ligne in
                .array(regions[ligne..<ligne + 3].map { $0.map { ["a": r($0.a), "b": r($0.b)] } ?? .null })
            })
            objet["groupes"] = .array(groupes.enumerated().map { index, groupe in
                ["lumiere": .string(index == 0 ? premiere : seconde), "zones": .string(Eclairage.nommer(groupe.cases)),
                 "a": r(groupe.a), "b": r(groupe.b), "part_pct": r(groupe.poids)]
            })
            if let balance, lumiereSujet != nil {
                objet["balance_proposee"] = [
                    "Temperature": .number(balance.temperature),
                    "Tint": .number(balance.tint),
                    "sur": .string(sujetSource == "visages" ? "lumière des visages" : "lumière du sujet (zone d'intérêt)"),
                    "remarque": "ordre de grandeur, d'après les pentes de match_series ; à vérifier par view_photo",
                ]
            }
            objet["conseil"] = .string(conseil)
            objet["base"] = .string(base)
        }
        return .object(objet)
    }
}

public enum Eclairage {
    /// Écart a*b* d'un ton presque neutre au centre (`centrer` : le gris, ou le point neutre de
    /// l'image). Relevé le
    /// 20 octobre 2026 (`--eclairage`, 8 copies « Essai », bornes de 12 à 30) : à 12, seul le
    /// portrait mixte ressort (écart 9,8 ; les autres de 2,2 à 7,1) ; à 15 et au-delà, des objets
    /// colorés pris pour des gris (ciel bleu, bouteille orange, plante, mur jaune) font de faux
    /// mixtes. La borne était alors absolue (C* < 12) : sous une autre balance (3 200 K, ou ±30 en
    /// relatif), plus aucune case ne se lisait (0 sur 9 pour le portrait). Prise autour du gris, ou
    /// du point neutre de l'image quand une dominante globale l'en écarte (`centrer`), elle se lit
    /// encore sous une autre balance.
    public static let chromaMax = 12.0
    /// Écart a*b* entre les deux groupes de lumière à partir duquel l'éclairage est mixte. Relevé
    /// le 20 octobre 2026 (même relevé) : le portrait, à deux lumières (fenêtres et éclairage
    /// chaud), à 9,8 ; les photos à une seule lumière de 2,2 à 7,1.
    public static let seuilMixte = 8.0
    /// Borne de chroma large des tons peu saturés dont la médiane donne le point neutre de l'image :
    /// les gris d'une photo à la balance très décalée (3 200 K sur une scène de jour) y restent.
    static let borneNeutreGlobal = 40.0
    /// Écart a*b* au gris jusqu'auquel le point neutre de l'image est celui d'une photo balancée
    /// (les couleurs de la scène l'en écartent : sable, intérieur chaud) : les tons presque neutres
    /// se prennent alors autour du gris, comme au relevé. Au-delà (une dominante globale), leur
    /// centre suit le point neutre, à cette distance près. Mesuré le 21 octobre 2026 sur cinq
    /// aperçus du relevé, lus en fichiers : point neutre de 3 à 11,2 du gris à la balance de la
    /// photo ; centré sur lui sans tolérance, le portrait perdait son éclairage mixte (9,9 → 4,8) et
    /// l'intérieur à la lampe en gagnait un (7,3 → 9,4) ; avec 10, les écarts du relevé restent à
    /// 0,1 près, et sur ces cinq aperçus, à leur balance et sous sept dominantes simulées (gains en
    /// lumière linéaire), 38 lectures sur 40 gardent au moins 7 cases sur 9 (30 sur 40 autour du
    /// gris seul). Le verdict sous une forte dominante reste fragile (la mesure a*b* elle-même varie,
    /// même sur les mêmes pixels). Limite connue : une dominante qui rapproche du gris la lumière
    /// majoritaire (le portrait, à lumière chaude majoritaire, sous une balance trop froide) laisse
    /// le point neutre près du gris, et l'autre lumière sort de la borne : l'éclairage se lit
    /// simple (portrait sous trois dominantes froides simulées : 3,4 à 4,5). Relu le 21 octobre
    /// 2026 sur les mêmes aperçus : aucun autre centre essayé (gris seul, point neutre sans
    /// tolérance, milieu des quartiles ou des déciles, avec ou sans tolérance) ne tient mieux à la
    /// fois la balance de la photo et les dominantes. Provisoire : à relever dans Lightroom
    /// (`--eclairage --essai`, 3 200 et 6 500 K, ±30 en relatif).
    static let toleranceNeutre = 10.0
    /// Écart a*b* entre ombres et hautes lumières à partir duquel il se lit. Provisoire, à relever.
    public static let seuilTonal = 8.0
    /// Part des tons neutres lus que doit porter chaque groupe, en % : une seule case colorée (un
    /// mur beige) ne fait pas un groupe. Provisoire, à relever (15 si une vraie lumière pèse moins).
    public static let partMinGroupe = 20.0
    /// Une case se lit à partir de `PhotoMeasurements.partNeutreMin` % de tons neutres, comme la
    /// dominante de view_photo (`castReading`). Pixels neutres au moins pour lire une case.
    static let pixelsMinCase = 200
    /// Cases lues au moins pour comparer les lumières.
    static let casesMin = 3
    /// Part de l'image en tons neutres pour lire une zone tonale, en %.
    static let partMinTonale = 2.0
    /// L* d'un ton presque neutre (plus sombre ou plus clair, sa couleur ne se lit pas).
    static let lumineuxMin = 15.0
    static let lumineuxMax = 95.0
    /// Limites des zones tonales en L* : ombres, tons moyens, hautes lumières.
    static let limitesTonales = [40.0, 70.0]
    /// Pixel écarté s'il a une composante écrêtée (≥ 250) ou bouchée (≤ 5).
    static let composanteMax: UInt8 = 250
    static let composanteMin: UInt8 = 5
    /// Largeur minimale d'un visage mesuré (part de la largeur de l'image), et visages mesurés au plus.
    static let visageMin = 0.04
    static let maxVisages = 4
    /// Cadre d'un visage agrandi de 10 % de sa taille de chaque côté : la peau ne tire pas les
    /// cases ni les zones tonales vers le chaud.
    static let margeVisage = 0.1
    /// Peau : L* de 25 à 92, C* de 6 à 50, pixels non écrêtés.
    static let peauLumineux = 25.0...92.0
    static let peauChroma = 6.0...50.0
    /// Pixels de peau au moins pour la lire. Provisoire, à relever (visages de 53709912 et
    /// 53709833).
    static let pixelsMinPeau = 20
    /// Pixels de l'anneau à moins de cette distance a*b* de la peau (cou, mains) : écartés.
    static let distancePeau = 10.0
    /// Anneau lu à partir de 100 px et 3 % de tons neutres ; sinon la case du visage.
    static let pixelsMinAnneau = 100
    static let partMinAnneau = 3.0
    /// Pixels neutres au moins dans la zone d'intérêt pour y lire la lumière du sujet.
    static let pixelsMinSujet = 100

    /// Mesure une image (un aperçu décodé) : réduite à `Measurements.maxSide` px, comme les
    /// mesures de view_photo. `visages` et `sujet` : cadres de Vision (fractions de l'image, depuis
    /// le haut gauche), visages du plus large au plus petit. Nil si l'image est illisible.
    public static func mesurer(_ image: CGImage, visages: [CGRect] = [], sujet: CGRect? = nil,
                               chromaMax: Double = Eclairage.chromaMax) -> MesureEclairage? {
        guard let pixels = pixelsLab(image) else { return nil }
        return mesurer(pixels, visages: visages, sujet: sujet, chromaMax: chromaMax)
    }

    /// Mesure des pixels RGBA 8 bits (sRGB, ligne 0 en haut), sans réduction.
    static func mesurer(rgba: [UInt8], width: Int, height: Int, visages: [CGRect] = [], sujet: CGRect? = nil,
                        chromaMax: Double = Eclairage.chromaMax) -> MesureEclairage? {
        guard let pixels = PixelsLab(rgba: rgba, largeur: width, hauteur: height) else { return nil }
        return mesurer(pixels, visages: visages, sujet: sujet, chromaMax: chromaMax)
    }

    /// Les pixels d'une image en L*a*b*, réduite à `Measurements.maxSide` px.
    static func pixelsLab(_ image: CGImage) -> PixelsLab? {
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        guard let rgba = Measurements.rgba(reduite) else { return nil }
        return PixelsLab(rgba: rgba, largeur: reduite.width, hauteur: reduite.height)
    }

    /// Pixels convertis une fois en L*a*b* (D65, comme `Measurements.lab`) : le relevé les mesure
    /// à plusieurs bornes de chroma.
    struct PixelsLab {
        var largeur: Int
        var hauteur: Int
        var l: [Double]
        var a: [Double]
        var b: [Double]
        var chroma: [Double]
        /// Une composante écrêtée ou bouchée : écarté des tons neutres.
        var ecarte: [Bool]
        /// Une composante écrêtée : écarté de la peau.
        var ecrete: [Bool]

        init?(rgba: [UInt8], largeur: Int, hauteur: Int) {
            let nombre = largeur * hauteur
            guard largeur > 0, hauteur > 0, rgba.count >= nombre * 4 else { return nil }
            self.largeur = largeur
            self.hauteur = hauteur
            l = [Double](repeating: 0, count: nombre)
            a = l
            b = l
            chroma = l
            ecarte = [Bool](repeating: false, count: nombre)
            ecrete = ecarte
            for i in 0..<nombre {
                let rouge = rgba[i * 4], vert = rgba[i * 4 + 1], bleu = rgba[i * 4 + 2]
                let haut = max(rouge, vert, bleu), bas = min(rouge, vert, bleu)
                ecrete[i] = haut >= Eclairage.composanteMax
                ecarte[i] = ecrete[i] || bas <= Eclairage.composanteMin
                let lab = Measurements.lab(rouge, vert, bleu)
                l[i] = lab.l
                a[i] = lab.a
                b[i] = lab.b
                chroma[i] = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            }
        }

        /// Un pixel lisible (ni écrêté ni bouché, L* de 15 à 95) à moins de `borne` en a*b* du point
        /// `centre`.
        func neutre(_ i: Int, _ borne: Double, _ centre: MesureEclairage.Neutre) -> Bool {
            !ecarte[i] && l[i] >= Eclairage.lumineuxMin && l[i] <= Eclairage.lumineuxMax
                && hypot(a[i] - centre.a, b[i] - centre.b) < borne
        }

        /// Pixels d'un cadre (fractions de l'image, depuis le haut gauche), bornés à l'image ; nil
        /// pour un cadre vide, hors de l'image ou non fini. Les fractions sont bornées avant la
        /// conversion en entier, qui planterait sur un cadre infini (`CGRect.null`) ou démesuré.
        func plage(_ cadre: CGRect) -> (x: Range<Int>, y: Range<Int>)? {
            guard Eclairage.fini(cadre) else { return nil }
            func borne(_ part: CGFloat) -> Double { min(max(Double(part), 0), 1) }
            let x0 = Int((borne(cadre.minX) * Double(largeur)).rounded(.down))
            let x1 = Int((borne(cadre.maxX) * Double(largeur)).rounded(.up))
            let y0 = Int((borne(cadre.minY) * Double(hauteur)).rounded(.down))
            let y1 = Int((borne(cadre.maxY) * Double(hauteur)).rounded(.up))
            guard x1 > x0, y1 > y0 else { return nil }
            return (x0..<x1, y0..<y1)
        }
    }

    /// Médiane (l'élément du milieu une fois trié, comme la netteté de `Detail`) : pour la peau,
    /// dont la zone est petite.
    static func mediane(_ valeurs: [Double]) -> Double {
        let triees = valeurs.sorted()
        return triees.isEmpty ? 0 : triees[triees.count / 2]
    }

    /// Médianes de a* et b* de tons neutres par histogramme, à `pas` près : trier chaque case
    /// coûtait 27 ms par aperçu (mesuré le 20 octobre 2026 en version optimisée, sur 512 px), un
    /// histogramme quelques-unes.
    struct Histogramme {
        static let pas = 0.05
        /// Valeurs de centre − borne à centre + borne, sur chaque axe : celles d'un ton à moins de
        /// la borne du centre.
        let borne: Double
        let centre: MesureEclairage.Neutre
        var classesA: [Int]
        var classesB: [Int]
        private(set) var nombre = 0

        init(borne: Double, centre: MesureEclairage.Neutre = .init(a: 0, b: 0)) {
            self.borne = borne
            self.centre = centre
            classesA = [Int](repeating: 0, count: Int((2 * borne / Self.pas).rounded(.up)) + 1)
            classesB = classesA
        }

        mutating func ajouter(_ a: Double, _ b: Double) {
            classesA[classe(a - centre.a)] += 1
            classesB[classe(b - centre.b)] += 1
            nombre += 1
        }

        func classe(_ ecart: Double) -> Int {
            min(classesA.count - 1, max(0, Int(((ecart + borne) / Self.pas).rounded(.down))))
        }

        /// La classe de l'élément de rang nombre / 2 (comme `mediane`), à son centre.
        func mediane(_ classes: [Int], autour origine: Double) -> Double {
            var cumul = 0
            for (rang, n) in classes.enumerated() {
                cumul += n
                if cumul > nombre / 2 { return origine - borne + (Double(rang) + 0.5) * Self.pas }
            }
            return origine
        }

        var a: Double { mediane(classesA, autour: centre.a) }
        var b: Double { mediane(classesB, autour: centre.b) }
    }

    /// Le point neutre de l'image : médianes de a* et b* de ses pixels lisibles peu saturés
    /// (C* < `borneNeutreGlobal`), hors des visages ; puis, affinées, celles des pixels à moins de
    /// deux fois `borne` de ce premier point (les couleurs franches entrées par la borne large n'y
    /// tirent plus). (0, 0) sans pixel lisible.
    static func pointNeutre(_ p: PixelsLab, exclus: [Bool], borne: Double) -> MesureEclairage.Neutre {
        var point = MesureEclairage.Neutre(a: 0, b: 0)
        for rayon in [borneNeutreGlobal, 2 * borne] {
            var histogramme = Histogramme(borne: rayon, centre: point)
            for i in 0..<(p.largeur * p.hauteur) where !exclus[i] && p.neutre(i, rayon, point) {
                histogramme.ajouter(p.a[i], p.b[i])
            }
            guard histogramme.nombre > 0 else { break }
            point = MesureEclairage.Neutre(a: histogramme.a, b: histogramme.b)
        }
        return point
    }

    /// Le centre des tons presque neutres : le gris tant que le point neutre de l'image en reste à
    /// `toleranceNeutre` près ; sinon le point neutre ramené de cette distance vers le gris.
    static func centrer(_ neutre: MesureEclairage.Neutre) -> MesureEclairage.Neutre {
        let distance = hypot(neutre.a, neutre.b)
        guard distance > toleranceNeutre else { return MesureEclairage.Neutre(a: 0, b: 0) }
        let part = 1 - toleranceNeutre / distance
        return MesureEclairage.Neutre(a: neutre.a * part, b: neutre.b * part)
    }

    static func agrandi(_ cadre: CGRect) -> CGRect {
        cadre.insetBy(dx: -cadre.width * CGFloat(margeVisage), dy: -cadre.height * CGFloat(margeVisage))
    }

    /// Un cadre utilisable : fini et non vide (ni `CGRect.null`, ni NaN).
    static func fini(_ cadre: CGRect) -> Bool {
        !cadre.isNull && !cadre.isInfinite
            && [cadre.minX, cadre.minY, cadre.width, cadre.height].allSatisfy { $0.isFinite }
            && cadre.width > 0 && cadre.height > 0
    }

    static func mesurer(_ p: PixelsLab, visages: [CGRect], sujet: CGRect?, chromaMax: Double) -> MesureEclairage {
        // Un cadre non fini ne se mesure pas (et ferait planter la conversion des positions). Chaque
        // visage garde son rang dans la liste donnée (vision.visages).
        let rangs = visages.indices.filter { fini(visages[$0]) }
        let cadres = rangs.map { visages[$0] }
        let sujet = sujet.flatMap { fini($0) ? $0 : nil }
        let w = p.largeur, h = p.hauteur, total = w * h
        // Les visages (agrandis) hors des cases et des zones tonales.
        var exclus = [Bool](repeating: false, count: total)
        for cadre in cadres {
            guard let zone = p.plage(agrandi(cadre)) else { continue }
            for y in zone.y { for x in zone.x { exclus[y * w + x] = true } }
        }
        // Les tons presque neutres se prennent autour du gris, ou du point neutre de l'image quand
        // une dominante globale l'en éloigne (`centrer`) : elle ne les fait pas sortir de la borne.
        let pointNeutre = pointNeutre(p, exclus: exclus, borne: chromaMax)
        let neutre = centrer(pointNeutre)
        // Cases de la grille : bornes zx · w / 3, comme `Detail`.
        let colonne = (0..<w).map { x in x < w / 3 ? 0 : (x < 2 * w / 3 ? 1 : 2) }
        let ligne = (0..<h).map { y in y < h / 3 ? 0 : (y < 2 * h / 3 ? 1 : 2) }
        var cases = [Histogramme](repeating: Histogramme(borne: chromaMax, centre: neutre), count: 9)
        var tons = [Histogramme](repeating: Histogramme(borne: chromaMax, centre: neutre), count: 3)
        var pixelsCase = [Int](repeating: 0, count: 9)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard !exclus[i] else { continue }
                let k = ligne[y] * 3 + colonne[x]
                pixelsCase[k] += 1
                guard p.neutre(i, chromaMax, neutre) else { continue }
                cases[k].ajouter(p.a[i], p.b[i])
                let t = p.l[i] < limitesTonales[0] ? 0 : (p.l[i] < limitesTonales[1] ? 1 : 2)
                tons[t].ajouter(p.a[i], p.b[i])
            }
        }
        let regions: [MesureEclairage.Dominante?] = (0..<9).map { k in
            let n = cases[k].nombre
            guard n >= pixelsMinCase, pixelsCase[k] > 0 else { return nil }
            let part = Double(n) * 100 / Double(pixelsCase[k])
            guard part >= PhotoMeasurements.partNeutreMin else { return nil }
            return MesureEclairage.Dominante(a: cases[k].a, b: cases[k].b, part: part, pixels: n)
        }
        let tonales: [MesureEclairage.Dominante?] = (0..<3).map { t in
            let n = tons[t].nombre
            let part = Double(n) * 100 / Double(total)
            guard n > 0, part >= partMinTonale else { return nil }
            return MesureEclairage.Dominante(a: tons[t].a, b: tons[t].b, part: part, pixels: n)
        }
        var ecartTonal: Double?
        if let ombres = tonales[0], let hautes = tonales[2] {
            ecartTonal = hypot(hautes.a - ombres.a, hautes.b - ombres.b)
        }

        // Deux groupes de lumière, le plus chaud (ou le plus magenta) d'abord.
        var groupes: [MesureEclairage.Groupe] = []
        var ecartRegions: Double?
        let lues = regions.enumerated().compactMap { index, region in
            region.map { (index: index, a: $0.a, b: $0.b, poids: Double($0.pixels)) }
        }
        if lues.count >= casesMin, let separation = separer(lues) {
            groupes = separation.groupes
            ecartRegions = separation.ecart
            let parA = abs(groupes[0].a - groupes[1].a) > abs(groupes[0].b - groupes[1].b)
            let inverses = parA ? groupes[0].a < groupes[1].a : groupes[0].b < groupes[1].b
            if inverses { groupes.swapAt(0, 1) }
        }

        // Visages : la peau au milieu du visage, la lumière autour.
        var visages: [MesureEclairage.Visage] = []
        for (rang, cadre) in zip(rangs, cadres).filter({ Double($0.1.width) >= visageMin }).prefix(maxVisages) {
            var visage = MesureEclairage.Visage(index: rang, cadre: cadre)
            let interieur = CGRect(x: cadre.minX + 0.25 * cadre.width, y: cadre.minY + 0.45 * cadre.height,
                                   width: 0.5 * cadre.width, height: 0.4 * cadre.height)
            if let zone = p.plage(interieur) {
                var ls: [Double] = [], as_: [Double] = [], bs: [Double] = []
                for y in zone.y {
                    for x in zone.x {
                        let i = y * w + x
                        guard !p.ecrete[i], peauLumineux.contains(p.l[i]), peauChroma.contains(p.chroma[i]) else { continue }
                        ls.append(p.l[i]); as_.append(p.a[i]); bs.append(p.b[i])
                    }
                }
                if ls.count >= pixelsMinPeau {
                    let a = mediane(as_), b = mediane(bs)
                    visage.peau = MesureEclairage.Peau(l: mediane(ls), a: a, b: b, teinte: atan2(b, a) * 180 / .pi)
                }
            }
            let anneau = CGRect(x: cadre.minX - 0.75 * cadre.width, y: cadre.minY - 0.25 * cadre.height,
                                width: 2.5 * cadre.width, height: 2.75 * cadre.height)
            if let zone = p.plage(anneau) {
                var autour = Histogramme(borne: chromaMax, centre: neutre), dedans = 0
                for y in zone.y {
                    for x in zone.x {
                        let i = y * w + x
                        guard !exclus[i] else { continue }
                        dedans += 1
                        guard p.neutre(i, chromaMax, neutre) else { continue }
                        if let peau = visage.peau, hypot(p.a[i] - peau.a, p.b[i] - peau.b) < distancePeau { continue }
                        autour.ajouter(p.a[i], p.b[i])
                    }
                }
                let part = dedans > 0 ? Double(autour.nombre) * 100 / Double(dedans) : 0
                if autour.nombre >= pixelsMinAnneau, part >= partMinAnneau {
                    visage.lumiere = MesureEclairage.Dominante(a: autour.a, b: autour.b, part: part, pixels: autour.nombre)
                    visage.source = "anneau"
                }
            }
            if visage.lumiere == nil {
                let cx = min(w - 1, Int(min(max(Double(cadre.midX), 0), 1) * Double(w)))
                let cy = min(h - 1, Int(min(max(Double(cadre.midY), 0), 1) * Double(h)))
                if let region = regions[ligne[cy] * 3 + colonne[cx]] {
                    visage.lumiere = region
                    visage.source = "case"
                }
            }
            if let lumiere = visage.lumiere, groupes.count == 2 {
                let d0 = hypot(lumiere.a - groupes[0].a, lumiere.b - groupes[0].b)
                let d1 = hypot(lumiere.a - groupes[1].a, lumiere.b - groupes[1].b)
                visage.groupe = d0 <= d1 ? 0 : 1
            }
            visages.append(visage)
        }

        // La lumière du sujet : celle des visages, sinon celle de la zone d'intérêt.
        var lumiereSujet: MesureEclairage.Dominante?
        var sujetSource: String?
        let eclaires = visages.compactMap { visage in visage.lumiere.map { (lumiere: $0, poids: Double(visage.cadre.width)) } }
        if !eclaires.isEmpty {
            let somme = eclaires.reduce(0) { $0 + $1.poids }
            lumiereSujet = MesureEclairage.Dominante(
                a: eclaires.reduce(0) { $0 + $1.lumiere.a * $1.poids } / somme,
                b: eclaires.reduce(0) { $0 + $1.lumiere.b * $1.poids } / somme,
                part: eclaires.reduce(0) { $0 + $1.lumiere.part * $1.poids } / somme,
                pixels: eclaires.reduce(0) { $0 + $1.lumiere.pixels })
            sujetSource = "visages"
        } else if let sujet, let zone = p.plage(sujet) {
            var neutres = Histogramme(borne: chromaMax, centre: neutre), dedans = 0
            for y in zone.y {
                for x in zone.x {
                    let i = y * w + x
                    guard !exclus[i] else { continue }
                    dedans += 1
                    if p.neutre(i, chromaMax, neutre) { neutres.ajouter(p.a[i], p.b[i]) }
                }
            }
            if neutres.nombre >= pixelsMinSujet {
                lumiereSujet = MesureEclairage.Dominante(a: neutres.a, b: neutres.b, part: Double(neutres.nombre) * 100 / Double(dedans),
                                                         pixels: neutres.nombre)
                sujetSource = "zone d'intérêt"
            }
        }

        return MesureEclairage(tonales: tonales, regions: regions, groupes: groupes, ecartRegions: ecartRegions, ecartTonal: ecartTonal,
                               visages: visages, lumiereSujet: lumiereSujet, sujetSource: sujetSource, borne: chromaMax,
                               neutre: pointNeutre, centre: neutre)
    }

    /// Partage les cases lues en deux groupes de lumière : de toutes les partitions en deux (255 au
    /// plus pour 9 cases), celle qui maximise wG · wD · |μG − μD|² (la variance entre groupes), où μ
    /// est la moyenne des médianes pondérée par les pixels neutres et w la part de chaque groupe.
    /// Chaque groupe porte au moins `partMinGroupe` % des tons neutres lus. Nil si aucune
    /// partition ne le permet (une case porte presque tout).
    static func separer(_ cases: [(index: Int, a: Double, b: Double, poids: Double)]) -> (groupes: [MesureEclairage.Groupe], ecart: Double)? {
        let n = cases.count
        let total = cases.reduce(0) { $0 + $1.poids }
        guard n >= 2, total > 0 else { return nil }
        var meilleur: (score: Double, masque: Int)?
        // La dernière case reste dans le second groupe : chaque partition n'est vue qu'une fois.
        for masque in 1..<(1 << (n - 1)) {
            var poidsG = 0.0, sommeAG = 0.0, sommeBG = 0.0
            var poidsD = 0.0, sommeAD = 0.0, sommeBD = 0.0
            for (rang, item) in cases.enumerated() {
                if masque & (1 << rang) != 0 {
                    poidsG += item.poids; sommeAG += item.a * item.poids; sommeBG += item.b * item.poids
                } else {
                    poidsD += item.poids; sommeAD += item.a * item.poids; sommeBD += item.b * item.poids
                }
            }
            let wG = poidsG / total, wD = poidsD / total
            guard wG * 100 >= partMinGroupe, wD * 100 >= partMinGroupe else { continue }
            let da = sommeAG / poidsG - sommeAD / poidsD, db = sommeBG / poidsG - sommeBD / poidsD
            let score = wG * wD * (da * da + db * db)
            if score > (meilleur?.score ?? -1) { meilleur = (score, masque) }
        }
        guard let masque = meilleur?.masque else { return nil }
        func groupe(_ dedans: Bool) -> MesureEclairage.Groupe {
            let membres = cases.enumerated().filter { (masque & (1 << $0.offset) != 0) == dedans }.map(\.element)
            let poids = membres.reduce(0) { $0 + $1.poids }
            return MesureEclairage.Groupe(cases: membres.map(\.index).sorted(),
                                          a: membres.reduce(0) { $0 + $1.a * $1.poids } / poids,
                                          b: membres.reduce(0) { $0 + $1.b * $1.poids } / poids,
                                          poids: poids * 100 / total)
        }
        let g = groupe(true), d = groupe(false)
        return ([g, d], hypot(g.a - d.a, g.b - d.b))
    }

    /// Nom d'un groupe de cases : une colonne entière devient un tiers (gauche, du milieu, droit),
    /// une ligne entière un tiers du haut, la bande du milieu ou le tiers du bas ; les autres cases
    /// gardent leur nom de zone (`DetailMeasurements.zoneNames`).
    static func nommer(_ cases: [Int]) -> String {
        let ensemble = Set(cases)
        var noms: [String] = []
        var couvertes = Set<Int>()
        for (colonne, nom) in ["tiers gauche", "tiers du milieu", "tiers droit"].enumerated() {
            let membres = [colonne, colonne + 3, colonne + 6]
            if membres.allSatisfy(ensemble.contains) { noms.append(nom); couvertes.formUnion(membres) }
        }
        for (ligne, nom) in ["tiers du haut", "bande du milieu", "tiers du bas"].enumerated() {
            let membres = [ligne * 3, ligne * 3 + 1, ligne * 3 + 2]
            if membres.allSatisfy(ensemble.contains) { noms.append(nom); couvertes.formUnion(membres) }
        }
        for index in cases.sorted() where !couvertes.contains(index) && DetailMeasurements.zoneNames.indices.contains(index) {
            noms.append(DetailMeasurements.zoneNames[index])
        }
        return noms.joined(separator: ", ")
    }

    /// Un nombre mesuré en français (virgule, vrai signe moins), à `decimales` chiffres.
    static func texte(_ valeur: Double, _ decimales: Int) -> String {
        var texte = String(format: "%.\(decimales)f", valeur)
        if texte.hasPrefix("-"), Double(texte) == 0 { texte.removeFirst() }
        return texte.replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: "-", with: "−")
    }

    /// Une constante en français, sans zéros inutiles (8 ; 8,5).
    static func nombre(_ valeur: Double) -> String {
        DevelopCatalogue.format(valeur).replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: "-", with: "−")
    }
}

// MARK: - Relevé (`mcp-developpeur --eclairage`)

extension Eclairage {
    /// Bornes essayées par le relevé (écart a*b* au centre des tons presque neutres).
    public static let bornesReleve: [Double] = [12, 15, 20, 25, 30]
    /// Étiquettes de scène de Vision relevées (`VNClassifyImageRequest`) : pour un garde-fou
    /// d'extérieur, si le relevé l'impose (soleil et ombre bleue).
    static let scenesReleve = ["interior_room", "outdoor", "sky"]

    /// Passe les commandes au module et garde le JPEG d'une proposition (commande « essayer »)
    /// avant que preview_settings ne l'efface : le relevé mesure l'aperçu tel que Lightroom l'a
    /// rendu, sans la recompression de l'image envoyée à Claude.
    private final class Capture: LightroomServing {
        let lightroom: LightroomServing
        var apercu: Data?
        init(_ lightroom: LightroomServing) { self.lightroom = lightroom }
        var moduleVersion: String? { lightroom.moduleVersion }
        func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue {
            let reponse = try lightroom.send(command, params, timeout: timeout)
            if command == "essayer", let chemin = reponse["chemin"]?.string {
                apercu = try? Data(contentsOf: URL(fileURLWithPath: chemin))
            }
            return reponse
        }
    }

    /// Une photo à mesurer : son aperçu et ce qu'il faut pour la balance proposée.
    struct AMesurer {
        var nom: String
        var entete: String
        var image: CGImage
        /// Réponse au format de la commande « apercu » (echelle_temperature, reglages), ou nil.
        var reponse: JSONValue?
    }

    /// Relevé de l'éclairage mixte, pour fixer les constantes : chaque photo (aperçu de 1344 px
    /// demandé au module par la commande « apercu », comme view_photo, en lecture seule ; ou fichier
    /// JPEG lu sans Lightroom) est mesurée à chaque borne de `bornesReleve`, avec ce que voit Vision
    /// (visages, zone d'intérêt, scène). Avec `essai` (arguments de preview_settings : une autre
    /// balance), l'aperçu est celui de la proposition : la photo est remise comme avant, mais
    /// l'Historique garde deux étapes « Claude · essai » ; refusé hors d'une copie virtuelle. Chaque
    /// ligne part aussi dans `sortie` dès qu'elle est prête. Une ligne qui commence par « ✘ » dit une
    /// photo non mesurée.
    @discardableResult
    public static func releve(lightroom: LightroomServing, ids: [Int], fichiers: [URL], essai: [String: JSONValue]?,
                              sortie: (String) -> Void = { _ in }) -> [String] {
        var lignes: [String] = []
        func dire(_ ligne: String) { lignes.append(ligne); sortie(ligne) }
        var resume: [String] = []
        let e = texte

        dire("Relevé de l'éclairage : bornes (écart a*b* au centre : le gris, ou le point neutre de l'image) \(bornesReleve.map(nombre).joined(separator: ", ")) "
            + "(actuelle \(nombre(chromaMax))) ; seuil d'éclairage mixte \(nombre(seuilMixte)) ; seuil tonal \(nombre(seuilTonal)) et part "
            + "d'un groupe \(nombre(partMinGroupe)) % (provisoires)"
            + (essai.map { " ; essai : \(JSONCoding.line(.object($0)))" } ?? " ; lecture seule"))
        if essai != nil, ids.isEmpty { dire("(l'essai ne vaut que pour les photos de Lightroom : les fichiers sont mesurés tels quels)") }

        // Une photo à la fois : demandée (ou lue), puis mesurée.
        let sources: [(nom: String, charger: () throws -> AMesurer)] =
            ids.map { id in ("\(id)", { try apercu(id: id, lightroom: lightroom, essai: essai) }) }
            + fichiers.map { fichier in (fichier.lastPathComponent, { try lire(fichier) }) }
        for source in sources {
            let photo: AMesurer
            do {
                photo = try source.charger()
            } catch {
                dire("✘ \(source.nom) : \(error.localizedDescription)")
                continue
            }
            dire("")
            dire("■ " + photo.entete)
            let vision = VisionAnalysis.analyze(photo.image)
            let cadres = vision?.faces.map(\.box) ?? []
            let largeurs = cadres.map { e(Double($0.width), 2) }.joined(separator: ", ")
            var ligneVision = "  Vision : \(cadres.count) visage(s)" + (cadres.isEmpty ? "" : " (largeurs \(largeurs))")
            if let zone = vision?.salientArea {
                ligneVision += " ; zone d'intérêt x \(e(Double(zone.minX), 2)) y \(e(Double(zone.minY), 2)) l \(e(Double(zone.width), 2)) h \(e(Double(zone.height), 2))"
            }
            if let scenes = scene(photo.image) {
                ligneVision += " ; scène : " + scenes.map { "\($0.0) \(e($0.1, 2))" }.joined(separator: " · ")
            } else {
                ligneVision += " ; scène non lue (Vision)"
            }
            dire(ligneVision)

            guard let pixels = pixelsLab(photo.image) else {
                dire("✘ \(photo.nom) : pixels illisibles")
                continue
            }
            // La durée de la mesure entière (réduction, conversion, statistiques), à la borne actuelle.
            let debut = Date()
            _ = mesurer(photo.image, visages: cadres, sujet: vision?.salientArea)
            let duree = Date().timeIntervalSince(debut) * 1000

            for borne in bornesReleve {
                let mesure = mesurer(pixels, visages: cadres, sujet: vision?.salientArea, chromaMax: borne)
                for ligne in lignesReleve(mesure, reponse: photo.reponse, duree: borne == chromaMax ? duree : nil) { dire(ligne) }
                let sujet = mesure.lumiereSujet.map { "a* \(e($0.a, 1)) b* \(e($0.b, 1))" } ?? "—"
                resume.append([photo.nom, nombre(borne), "\(mesure.regions.compactMap { $0 }.count)/9",
                               mesure.ecartRegions.map { e($0, 1) } ?? "—", mesure.ecartTonal.map { e($0, 1) } ?? "—",
                               mesure.mixte ? "mixte" : "non", mesure.groupes.map { nommer($0.cases) }.joined(separator: " | "), sujet]
                    .joined(separator: "\t"))
            }
        }

        if !resume.isEmpty {
            dire("")
            dire("Résumé (photo, borne, cases lues, ecart_regions, ecart_tonal, mixte au seuil actuel, groupes, lumière du sujet) :")
            for ligne in resume { dire(ligne) }
        }
        return lignes
    }

    /// Un fichier JPEG (ou toute image lisible par ImageIO), mesuré sans Lightroom.
    static func lire(_ fichier: URL) throws -> AMesurer {
        let data = try Data(contentsOf: fichier)
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("image illisible") }
        return AMesurer(nom: fichier.lastPathComponent, entete: "\(fichier.lastPathComponent) · \(image.width) × \(image.height) (fichier, sans Lightroom)",
                        image: image, reponse: nil)
    }

    /// L'aperçu d'une photo de Lightroom : celui de la commande « apercu » (lecture seule), ou celui
    /// d'une proposition par preview_settings.
    static func apercu(id: Int, lightroom: LightroomServing, essai: [String: JSONValue]?) throws -> AMesurer {
        let e = texte
        func balanceLue(_ reponse: JSONValue) -> String {
            let raw = reponse["echelle_temperature"]?.string?.hasPrefix("kelvins") == true
            let temperature = reponse["reglages"]?["Temperature"]?.double.map { e($0, 0) } ?? "?"
            let tint = reponse["reglages"]?["Tint"]?.double.map { e($0, 0) } ?? "?"
            return "\(raw ? "RAW" : "JPEG ou autre (balance relative)"), Temperature \(temperature), Tint \(tint)"
        }
        guard let essai else {
            let reponse = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(ToolHandler.defaultPreviewSize)),
                                                        "cles": ["Temperature", "Tint"]], timeout: 120)
            let data = try ToolHandler.readPreview(reponse["chemin"]?.string)
            guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("aperçu illisible") }
            let fichier = reponse["photo"]?["fichier"]?.string ?? "?"
            return AMesurer(nom: "\(id)", entete: "\(id) · \(fichier) · \(balanceLue(reponse)) · aperçu \(image.width) × \(image.height)",
                            image: image, reponse: reponse)
        }
        // Une proposition écrit le temps d'un rendu : copies virtuelles seulement (celles de
        // « Développeur › Essais »).
        let lue = try lightroom.send("reglages", ["photo": .number(Double(id)), "cles": ["Temperature", "Tint"]], timeout: 30)
        guard lue["photo"]?["copie_virtuelle"]?.bool == true else {
            throw LightroomError.invalid("--essai seulement sur une copie virtuelle (les copies d'essai de « Développeur › Essais ») : c'est un original")
        }
        let capture = Capture(lightroom)
        var arguments = essai
        arguments["photo_id"] = .number(Double(id))
        arguments.removeValue(forKey: "photo_ids")
        arguments.removeValue(forKey: "selection")
        let resultat = ToolHandler(lightroom: capture).call(name: "preview_settings", arguments: arguments)
        var texte = "", images: [Data] = []
        for bloc in resultat.content {
            switch bloc {
            case .text(let t): texte += t
            case .image(let base64, _): if let data = Data(base64Encoded: base64) { images.append(data) }
            }
        }
        if resultat.isError { throw LightroomError.plugin(texte) }
        guard let data = capture.apercu ?? images.first, let image = PreviewImages.image(data) else {
            throw LightroomError.plugin("aperçu de la proposition illisible")
        }
        // La balance de l'aperçu : celle de l'essai, sur celle de la photo. Inconnue si l'essai la
        // fait calculer (white_balance, white_balance_point) ou peut la changer (un paramètre
        // prédéfini, posé avant les réglages) : pas de balance qui neutralise la lumière du sujet.
        var reglages = lue["reglages"]?.object ?? [:]
        let relative = essai["relative"]?.bool == true
        var balanceConnue = ["white_balance", "white_balance_point", "preset"].allSatisfy { essai[$0] == nil }
        for cle in ["Temperature", "Tint"] {
            guard let valeur = essai["settings"]?[cle]?.double else { continue }
            if relative {
                guard let actuelle = reglages[cle]?.double else { balanceConnue = false; continue }
                reglages[cle] = .number(actuelle + valeur)
            } else {
                reglages[cle] = .number(valeur)
            }
        }
        var reponse = lue.object ?? [:]
        reponse["reglages"] = .object(reglages)
        let changements = (try? JSONCoding.parse(texte))?["changements"]?.array?.compactMap { changement -> String? in
            guard let cle = changement["cle"]?.string else { return nil }
            return "\(cle) \(changement["avant"].map(JSONCoding.line) ?? "?") → \(changement["apres"].map(JSONCoding.line) ?? "?")"
        } ?? []
        let fichier = lue["photo"]?["fichier"]?.string ?? "?"
        return AMesurer(nom: "\(id)", entete: "\(id) · \(fichier) · essai : \(changements.isEmpty ? "rien ne change" : changements.joined(separator: ", "))"
                            + " · \(balanceLue(.object(reponse))) · aperçu \(image.width) × \(image.height)",
                        image: image, reponse: balanceConnue ? .object(reponse) : nil)
    }

    /// Confiance de Vision pour les scènes de `scenesReleve` ; nil si Vision échoue.
    static func scene(_ image: CGImage) -> [(String, Double)]? {
        let requete = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([requete])) != nil else { return nil }
        var confiances: [String: Double] = [:]
        for observation in requete.results ?? [] { confiances[observation.identifier] = Double(observation.confidence) }
        return scenesReleve.map { ($0, confiances[$0] ?? 0) }
    }

    /// Les lignes d'une mesure à une borne.
    static func lignesReleve(_ mesure: MesureEclairage, reponse: JSONValue?, duree: Double?) -> [String] {
        let e = texte
        func dominante(_ d: MesureEclairage.Dominante?) -> String {
            d.map { "a* \(e($0.a, 1)) b* \(e($0.b, 1)) (\(e($0.part, 0)) %)" } ?? "—"
        }
        let lues = mesure.regions.compactMap { $0 }.count
        var lignes: [String] = []
        var tete = "  borne \(nombre(mesure.borne)) : \(lues)/9 cases lues ; ecart_regions \(mesure.ecartRegions.map { e($0, 1) } ?? "—")"
            + (mesure.mixte ? " (mixte)" : "") + " ; ecart_tonal \(mesure.ecartTonal.map { e($0, 1) } ?? "—")"
            + " ; point neutre a* \(e(mesure.neutre.a, 1)) b* \(e(mesure.neutre.b, 1)), centre a* \(e(mesure.centre.a, 1)) b* \(e(mesure.centre.b, 1))"
        if let duree { tete += " ; mesure en \(e(duree, 0)) ms" }
        lignes.append(tete)
        lignes.append("    cases : " + stride(from: 0, to: 9, by: 3).map { ligne in
            (ligne..<ligne + 3).map { k in
                mesure.regions[k].map { "\(e($0.a, 1))/\(e($0.b, 1))/\(e($0.part, 0)) %" } ?? "—"
            }.joined(separator: " | ")
        }.joined(separator: " ‖ ") + " (a*/b*/part neutre, ligne par ligne)")
        if mesure.groupes.count == 2 {
            let (premiere, seconde) = mesure.nomsLumieres
            lignes.append("    groupes : " + mesure.groupes.enumerated().map { index, g in
                "\(index == 0 ? premiere : seconde) \(nommer(g.cases)) (a* \(e(g.a, 1)), b* \(e(g.b, 1)), \(e(g.poids, 0)) %)"
            }.joined(separator: " ; "))
        }
        lignes.append("    zones tonales : ombres \(dominante(mesure.tonales[0])) · tons moyens \(dominante(mesure.tonales[1])) · hautes lumières \(dominante(mesure.tonales[2]))")
        for (index, visage) in mesure.visages.enumerated() {
            let peau = visage.peau.map { "peau L* \(e($0.l, 0)) a* \(e($0.a, 1)) b* \(e($0.b, 1)) teinte \(e($0.teinte, 0))°" } ?? "peau non lue"
            let lumiere = visage.lumiere.map { "lumière a* \(e($0.a, 1)) b* \(e($0.b, 1)) (\(visage.source ?? "?")\(visage.groupe.map { ", groupe \($0 + 1)" } ?? ""))" }
                ?? "lumière non lue"
            lignes.append("    visage \(index + 1) : \(peau) ; \(lumiere)")
        }
        if let sujet = mesure.lumiereSujet {
            var ligne = "    lumière du sujet (\(mesure.sujetSource ?? "?")) : a* \(e(sujet.a, 1)) b* \(e(sujet.b, 1))"
            if let reponse, let balance = ToolHandler.balancePourLumiere(sujet, reponse: reponse) {
                ligne += " ; balance qui la neutralise : Temperature \(e(balance.temperature, 0)), Tint \(e(balance.tint, 0))"
            }
            lignes.append(ligne)
        }
        lignes.append("    lecture : " + mesure.lecture)
        if let tonale = mesure.lectureTonale { lignes.append("    lecture tonale : " + tonale) }
        return lignes
    }
}
