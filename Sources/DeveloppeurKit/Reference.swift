import CoreGraphics
import Foundation

/// Étalonnage d'après une photo de référence du catalogue (`match_look`, 1.6) : la signature de son
/// rendu (tons, couleur réelle de chaque zone tonale, saturation), l'écart avec une photo, et sa
/// traduction en réglages que Lightroom accepte (constaté avant le code, 1er novembre 2026 :
/// `SplitToning*` pour la teinte et la saturation des ombres et des hautes lumières, `ColorGrade*`
/// pour les tons moyens ; `ColorGradeShadowHue` et ses semblables sont refusés).
///
/// La couleur d'une zone se lit sur tous ses pixels peu saturés (C* < `chromaZone`, autour du gris),
/// pas sur ses seuls tons presque neutres : un rendu marqué (ombres sarcelle, hautes lumières
/// orange) pousse justement les gris au-delà de la borne d'`Eclairage` (12), qui écarterait ce qu'il
/// faut copier. Les couleurs vives des objets (C* au-delà) restent hors de la mesure : une forêt
/// ne verdit pas les ombres d'une plage. Pur, sans Lightroom : `Tools+Reference` le branche.
///
/// Les pentes (teinte de Lightroom → angle a*b*, a*b* par point de saturation, Vibrance par unité de
/// chroma) sont PROVISOIRES, choisies hors de Lightroom : à relever par `--etalonnage --balayage` sur
/// une copie d'Essais (docs/SPEC.md, Étalonnage d'après une référence, À constater). La passe 2
/// corrige d'après ce que la passe 1 a montré.
public enum Reference {
    /// Les zones tonales, dans l'ordre, et leurs noms dans le résultat.
    static let zones = ["ombres", "tons_moyens", "hautes_lumieres"]
    /// Les clés de l'étalonnage de chaque zone (teinte, saturation), celles que Lightroom accepte.
    static let clesZones: [(teinte: String, saturation: String)] = [
        ("SplitToningShadowHue", "SplitToningShadowSaturation"),
        ("ColorGradeMidtoneHue", "ColorGradeMidtoneSat"),
        ("SplitToningHighlightHue", "SplitToningHighlightSaturation"),
    ]
    /// Les réglages lus sur chaque photo avant de calculer les valeurs finales (écriture absolue).
    static let clesLues = ["Exposure2012", "Contrast2012", "Vibrance", "Temperature", "Tint",
                                  "ColorGradeBlending", "SplitToningBalance", "ColorGradeGlobalSat"]
        + clesZones.flatMap { [$0.teinte, $0.saturation] }
    /// L* des zones : celles d'`Eclairage.limitesTonales` (< 40, 40 à 70, > 70), entre `lumineuxMin`
    /// et `lumineuxMax` (plus sombre ou plus clair, la couleur ne se lit pas).
    static let limites = Eclairage.limitesTonales
    static let lumineuxMin = 8.0, lumineuxMax = 97.0
    /// C* sous lequel un pixel dit la couleur de sa zone. PROVISOIRE (choisi hors de Lightroom) : à
    /// relever par `--etalonnage` sur de vraies références (bornes 12 à 45).
    static let chromaZone = 30.0
    /// Bornes du relevé de la signature.
    static let bornesReleve: [Double] = [12, 20, 30, 45]
    /// Une zone se lit à partir de cette part de l'image (en %) et de ce nombre de pixels.
    static let partMinZone = 3.0
    static let pixelsMinZone = 150
    /// Bande noire d'un photogramme : ligne ou colonne du bord dont aucun pixel ne passe L* 3 ; un
    /// quart du côté au plus.
    static let seuilBandeNoire = 3.0
    /// C* à partir duquel un pixel compte dans la répartition par bande de la TSL.
    static let chromaBandes = 15.0
    /// Distance entre les répartitions par bande (0 à 100 %) au-delà de laquelle les scènes
    /// diffèrent : la saturation ne se copie pas. PROVISOIRE.
    static let seuilScenes = 60.0
    /// Écart a*b* d'une zone (ou distance) sous lequel rien ne se corrige : celui de match_series.
    static let seuilZone = ToolHandler.seuilDominante
    /// Saturation de l'étalonnage par zone, au plus (40 avec strong_dose_requested). PROVISOIRE : une
    /// borne propre à match_look, pas un plafond de `DevelopCatalogue.plafondsDose` (qui jugerait aussi
    /// les recettes de styles d'apply_settings).
    static let saturationMax = 25.0, saturationMaxForte = 40.0
    /// Vibrance changée au plus par passe.
    static let vibranceMaxPasse = 20.0
    /// Part de l'écart à combler, par défaut et bornes.
    static let forceDefaut = 0.6, forces = 0.25...1.0

    // MARK: Signature

    /// La couleur d'une zone tonale : médianes de a* et b* de ses pixels peu saturés.
    struct Zone: Equatable {
        var a: Double
        var b: Double
        /// Part de l'image lue dans cette zone, en %.
        var part: Double
        var pixels: Int
    }

    /// Le rendu d'une image.
    struct Signature: Equatable {
        /// Centiles de L* : 5, 25, 50, 75 et 95.
        var centiles: [Int: Double]
        /// Ombres, tons moyens, hautes lumières (nil : pas assez de pixels peu saturés).
        var zones: [Zone?]
        var chromaMediane: Double
        var chromaP90: Double
        /// Chroma médiane des seuls pixels colorés (C* ≥ `chromaZone`, ceux que la couleur des zones
        /// laisse de côté) : la saturation des objets, que l'étalonnage ne fait presque pas bouger
        /// (il teinte les gris). nil : trop peu de couleurs vives pour la lire.
        var chromaCouleurs: Double?
        /// Part des pixels colorés (C* ≥ `chromaBandes`) par bande de la TSL, en %.
        var bandes: [Double]
        var remarques: [String]

        var mediane: Double { centiles[50] ?? 50 }
        var contraste: Double { (centiles[95] ?? 0) - (centiles[5] ?? 0) }
    }

    /// La signature d'une image (un aperçu décodé, réduit à `Measurements.maxSide` px, dessiné en sRGB :
    /// une image en P3 est convertie). `visages` : cadres de Vision (fractions, depuis le haut gauche),
    /// écartés des zones et de la chroma (la peau ne guide pas l'étalonnage).
    static func lire(_ image: CGImage, visages: [CGRect] = [], chromaZone: Double = chromaZone) -> Signature? {
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        guard let rgba = Measurements.rgba(reduite) else { return nil }
        return lire(rgba: rgba, largeur: reduite.width, hauteur: reduite.height, visages: visages, chromaZone: chromaZone)
    }

    static func lire(rgba: [UInt8], largeur: Int, hauteur: Int, visages: [CGRect] = [], chromaZone: Double = chromaZone) -> Signature? {
        let nombre = largeur * hauteur
        guard largeur > 0, hauteur > 0, rgba.count >= nombre * 4 else { return nil }
        var l = [Double](repeating: 0, count: nombre), a = l, b = l
        for i in 0..<nombre {
            let lab = Measurements.lab(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2])
            (l[i], a[i], b[i]) = (lab.l, lab.a, lab.b)
        }
        var remarques: [String] = []
        let cadre = cadreUtile(l: l, largeur: largeur, hauteur: hauteur)
        if cadre != (0, largeur, 0, hauteur) { remarques.append("bandes noires du bord écartées") }
        let exclus = visages.map { v in
            v.insetBy(dx: -Eclairage.margeVisage * v.width, dy: -Eclairage.margeVisage * v.height)
        }
        if !exclus.isEmpty { remarques.append("visages écartés de la couleur des zones") }
        var tons: [Double] = [], chromas: [Double] = [], vives: [Double] = []
        var parZone: [[(Double, Double)]] = [[], [], []]
        var bandes = [Int](repeating: 0, count: PhotoMeasurements.bandes.count), colores = 0
        for y in cadre.y0..<cadre.y1 {
            for x in cadre.x0..<cadre.x1 {
                let i = y * largeur + x
                tons.append(l[i])
                let fx = (Double(x) + 0.5) / Double(largeur), fy = (Double(y) + 0.5) / Double(hauteur)
                if exclus.contains(where: { $0.contains(CGPoint(x: fx, y: fy)) }) { continue }
                let rouge = rgba[i * 4], vert = rgba[i * 4 + 1], bleu = rgba[i * 4 + 2]
                // Écrêtés : une composante au blanc, ou les trois au noir. Pas une seule au noir : une
                // ombre profonde teintée (sarcelle) a son rouge à 0 bien avant L* 20, et l'écarter
                // ferait lire la couleur des ombres sur leur seule partie claire.
                guard max(rouge, vert, bleu) < Eclairage.composanteMax, max(rouge, vert, bleu) > Eclairage.composanteMin,
                      l[i] >= lumineuxMin, l[i] <= lumineuxMax else { continue }
                let chroma = hypot(a[i], b[i])
                chromas.append(chroma)
                if chroma >= chromaBandes {
                    bandes[PhotoMeasurements.bande(rouge, vert, bleu)] += 1
                    colores += 1
                }
                guard chroma < chromaZone else { vives.append(chroma); continue }
                let zone = l[i] < limites[0] ? 0 : (l[i] < limites[1] ? 1 : 2)
                parZone[zone].append((a[i], b[i]))
            }
        }
        guard !tons.isEmpty else { return nil }
        tons.sort()
        chromas.sort()
        vives.sort()
        func centile(_ triees: [Double], _ p: Double) -> Double {
            guard !triees.isEmpty else { return 0 }
            return triees[min(triees.count - 1, max(0, Int((p / 100 * Double(triees.count - 1)).rounded())))]
        }
        var centiles: [Int: Double] = [:]
        for p in [5, 25, 50, 75, 95] { centiles[p] = centile(tons, Double(p)) }
        let total = Double(tons.count)
        let zones: [Zone?] = parZone.enumerated().map { index, valeurs in
            let part = Double(valeurs.count) * 100 / total
            guard valeurs.count >= pixelsMinZone, part >= partMinZone else { return nil }
            return Zone(a: Eclairage.mediane(valeurs.map(\.0)), b: Eclairage.mediane(valeurs.map(\.1)), part: part, pixels: valeurs.count)
        }
        let colorees = vives.count >= pixelsMinZone && Double(vives.count) * 100 / total >= partMinZone
        if !colorees { remarques.append("trop peu de couleurs vives : saturation non lue") }
        for (index, zone) in zones.enumerated() where zone == nil {
            remarques.append("\(nomZone(index)) : pas assez de pixels peu saturés, couleur non lue")
        }
        return Signature(centiles: centiles, zones: zones, chromaMediane: centile(chromas, 50), chromaP90: centile(chromas, 90),
                         chromaCouleurs: colorees ? centile(vives, 50) : nil,
                         bandes: bandes.map { colores > 0 ? Double($0) * 100 / Double(colores) : 0 }, remarques: remarques)
    }

    /// Le cadre sans les bandes noires du bord (lignes et colonnes dont aucun pixel ne passe
    /// `seuilBandeNoire`), un quart du côté au plus de chaque bord : (x0, x1, y0, y1), bornes hautes exclues.
    static func cadreUtile(l: [Double], largeur: Int, hauteur: Int) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
        func ligneNoire(_ y: Int, _ x0: Int, _ x1: Int) -> Bool { (x0..<x1).allSatisfy { l[y * largeur + $0] < seuilBandeNoire } }
        func colonneNoire(_ x: Int, _ y0: Int, _ y1: Int) -> Bool { (y0..<y1).allSatisfy { l[$0 * largeur + x] < seuilBandeNoire } }
        var y0 = 0, y1 = hauteur, x0 = 0, x1 = largeur
        while y0 < hauteur / 4, ligneNoire(y0, 0, largeur) { y0 += 1 }
        while y1 > hauteur - hauteur / 4, ligneNoire(y1 - 1, 0, largeur) { y1 -= 1 }
        while x0 < largeur / 4, colonneNoire(x0, y0, y1) { x0 += 1 }
        while x1 > largeur - largeur / 4, colonneNoire(x1 - 1, y0, y1) { x1 -= 1 }
        // Une image toute noire n'a pas de cadre utile à part : on la garde entière.
        guard y1 > y0, x1 > x0 else { return (0, largeur, 0, hauteur) }
        return (x0, x1, y0, y1)
    }

    static func nomZone(_ index: Int) -> String { ["ombres", "tons moyens", "hautes lumières"][index] }

    /// Distance entre deux répartitions par bande : 0 (mêmes couleurs) à 100 %.
    static func distanceBandes(_ p: [Double], _ q: [Double]) -> Double {
        zip(p, q).reduce(0) { $0 + abs($1.0 - $1.1) } / 2
    }

    // MARK: Écart

    /// Écart « référence moins photo ».
    struct Ecart: Equatable {
        var exposition: Double
        var contraste: Double
        /// Écart a*b* de chaque zone (nil si l'une des deux images ne la lit pas).
        var zones: [Vecteur?]
        /// Écart de chroma des pixels colorés (nil si l'une des deux images ne la lit pas).
        var chroma: Double?
        var scenes: Double
    }

    struct Vecteur: Equatable {
        var a: Double
        var b: Double
        init(a: Double, b: Double) { self.a = a; self.b = b }
        var norme: Double { hypot(a, b) }
        static func + (u: Vecteur, v: Vecteur) -> Vecteur { Vecteur(a: u.a + v.a, b: u.b + v.b) }
        static func - (u: Vecteur, v: Vecteur) -> Vecteur { Vecteur(a: u.a - v.a, b: u.b - v.b) }
        static func * (k: Double, v: Vecteur) -> Vecteur { Vecteur(a: k * v.a, b: k * v.b) }
        static let zero = Vecteur(a: 0, b: 0)
    }

    static func ecart(photo: Signature, reference: Signature) -> Ecart {
        let y = max(Measurements.luminance(photo.mediane), 0.0005), yRef = max(Measurements.luminance(reference.mediane), 0.0005)
        let zones: [Vecteur?] = (0..<3).map { z in
            guard let p = photo.zones[z], let r = reference.zones[z] else { return nil }
            return Vecteur(a: r.a - p.a, b: r.b - p.b)
        }
        return Ecart(exposition: min(max(log2(yRef / y), -3), 3), contraste: reference.contraste - photo.contraste, zones: zones,
                     chroma: reference.chromaCouleurs.flatMap { r in photo.chromaCouleurs.map { r - $0 } }, scenes: distanceBandes(photo.bandes, reference.bandes))
    }

    /// L'écart qu'une passe suivante doit encore combler pour atteindre `force` de l'écart du départ :
    /// ce qui reste, moins la part laissée exprès (1 − force) de l'écart du départ.
    static func ecartVise(reste: Ecart, avant: Ecart, force: Double) -> Ecart {
        let laisse = 1 - force
        return Ecart(exposition: reste.exposition - laisse * avant.exposition, contraste: reste.contraste - laisse * avant.contraste,
                     zones: (0..<3).map { z in
                         guard let r = reste.zones[z] else { return nil }
                         return r - laisse * (avant.zones[z] ?? .zero)
                     },
                     chroma: reste.chroma.map { $0 - laisse * (avant.chroma ?? 0) }, scenes: reste.scenes)
    }

    /// La part commune aux zones lues : une dominante de toute l'image, donc la balance. Pas leur
    /// moyenne : une seule zone teintée (des ombres froides seules) déplacerait la moyenne, et les
    /// deux autres zones, pourtant pareilles sur les deux photos, recevraient la couleur
    /// complémentaire. Trois zones lues : la médiane de a* et de b* (une zone à part ne la déplace
    /// pas) ; deux, dont les tons moyens : les tons moyens ; les ombres et les hautes lumières seules :
    /// leur moyenne (le partage reste ambigu) ; une seule : elle-même.
    static func commune(_ zones: [Vecteur?]) -> Vecteur? {
        let lues = zones.compactMap { $0 }
        switch lues.count {
        case 0: return nil
        case 3:
            func mediane(_ v: [Double]) -> Double { v.sorted()[1] }
            return Vecteur(a: mediane(lues.map(\.a)), b: mediane(lues.map(\.b)))
        default:
            if lues.count == 2, zones.count == 3, let moyens = zones[1] { return moyens }
            return (1 / Double(lues.count)) * lues.reduce(.zero, +)
        }
    }

    /// L'écart de chaque zone sans la part commune : le partage entre les zones, ce que l'étalonnage
    /// copie. Une seule zone lue n'a pas de partage : rien.
    static func relatives(_ zones: [Vecteur?]) -> [Vecteur?] {
        guard zones.compactMap({ $0 }).count >= 2, let c = commune(zones) else { return [nil, nil, nil] }
        return zones.map { $0.map { $0 - c } }
    }

    /// Distance de couleur : moyenne des écarts a*b* des zones, sans la part commune (avec elle si la
    /// balance se copie). nil sans zones comparables.
    static func distance(_ ecart: Ecart, balance: Bool) -> Double? {
        let zones = (balance ? ecart.zones : relatives(ecart.zones)).compactMap { $0 }
        guard !zones.isEmpty else { return nil }
        return zones.reduce(0) { $0 + $1.norme } / Double(zones.count)
    }

    // MARK: Traduction

    /// Teinte de Lightroom (0 à 360, roue de l'étalonnage) → angle a*b* (degrés). Ancres PROVISOIRES :
    /// les angles L*a*b* des primaires et secondaires sRGB (rouge 40°, jaune 102°, vert 136°, cyan
    /// 196°, bleu 306°, magenta 328°) ; à relever par `--etalonnage --balayage`.
    static let ancresTeinte: [(lightroom: Double, lab: Double)] = [
        (0, 40), (60, 102), (120, 136), (180, 196), (240, 306), (300, 328), (360, 400),
    ]
    /// a*b* gagné dans sa zone par point de saturation de l'étalonnage, par zone. PROVISOIRE.
    static let gainDepart = [0.2, 0.2, 0.2]
    /// Vibrance par unité de chroma médiane. PROVISOIRE.
    static let vibranceParChromaDepart = 2.0

    static func angleLab(teinte: Double) -> Double {
        let h = teinte.truncatingRemainder(dividingBy: 360) + (teinte < 0 ? 360 : 0)
        for (u, v) in zip(ancresTeinte, ancresTeinte.dropFirst()) where h >= u.lightroom && h <= v.lightroom {
            let t = (h - u.lightroom) / (v.lightroom - u.lightroom)
            return (u.lab + t * (v.lab - u.lab)).truncatingRemainder(dividingBy: 360)
        }
        return ancresTeinte[0].lab
    }

    static func teinteLightroom(angle: Double) -> Double {
        var h = angle.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        if h < ancresTeinte[0].lab { h += 360 }
        for (u, v) in zip(ancresTeinte, ancresTeinte.dropFirst()) where h >= u.lab && h <= v.lab {
            let t = (h - u.lab) / (v.lab - u.lab)
            return (u.lightroom + t * (v.lightroom - u.lightroom)).truncatingRemainder(dividingBy: 360)
        }
        return 0
    }

    /// Le décalage a*b* qu'une teinte et une saturation de l'étalonnage donnent à leur zone (modèle).
    static func vecteur(teinte: Double, saturation: Double, gain: Double) -> Vecteur {
        let angle = angleLab(teinte: teinte) * .pi / 180
        return Vecteur(a: gain * saturation * cos(angle), b: gain * saturation * sin(angle))
    }

    /// Les pentes d'une photo : départ provisoire, puis corrigées d'après la passe 1.
    struct Pentes: Equatable {
        var gain = Reference.gainDepart
        var vibranceParChroma = Reference.vibranceParChromaDepart
        var serie = ToolHandler.PentesSerie()
        init() {}
    }

    /// Ce que l'on copie et comment.
    struct Options: Equatable {
        var tons = true
        var etalonnage = true
        var saturation = true
        var balance = false
        var force = Reference.forceDefaut
        var doseForte = false
        init() {}
    }

    /// La photo telle qu'elle est : réglages actuels, balance (RAW en kelvins ou relative).
    struct Etat {
        var reglages: [String: Double]
        var raw: Bool
        func valeur(_ cle: String) -> Double { reglages[cle] ?? (cle == "ColorGradeBlending" ? 50 : 0) }
    }

    /// Les valeurs finales (absolues) pour un écart, seulement celles qui changent, et les limites dites.
    static func traduire(_ ecart: Ecart, etat: Etat, options: Options, pentes: Pentes) -> (reglages: [String: Double], limites: [String]) {
        var finales: [String: Double] = [:], limites: [String] = []
        let k = options.force
        if options.tons {
            if abs(ecart.exposition) >= ToolHandler.seuilExposition {
                let delta = min(max(ecart.exposition * pentes.serie.expositionParIL * k, -2), 2)
                finales["Exposure2012"] = (min(max(etat.valeur("Exposure2012") + delta, -5), 5) * 20).rounded() / 20
            }
            if abs(ecart.contraste) >= ToolHandler.seuilContraste {
                let voulu = pentes.serie.contrasteParL * ecart.contraste * k
                let delta = min(max(voulu, -ToolHandler.maxContrastePasse), ToolHandler.maxContrastePasse)
                if abs(voulu) > ToolHandler.maxContrastePasse {
                    limites.append("Contraste changé de \(Int(ToolHandler.maxContrastePasse)) au plus par passe : l'écart de tons vient aussi de la scène.")
                }
                finales["Contrast2012"] = min(max(etat.valeur("Contrast2012") + delta, -100), 100).rounded()
            }
        }
        if options.etalonnage {
            if etat.valeur("ColorGradeBlending") != 50 || etat.valeur("SplitToningBalance") != 0 {
                limites.append("Fusion ou Équilibre de l'étalonnage hors de 50 et 0 : le premier calcul vise moins juste, la passe 2 mesurée corrige.")
            }
            let maxSat = options.doseForte ? saturationMaxForte : saturationMax
            for (z, ecartZone) in relatives(ecart.zones).enumerated() {
                guard let ecartZone, ecartZone.norme >= seuilZone else { continue }
                let cles = clesZones[z], gain = max(pentes.gain[z], 0.01)
                let actuel = vecteur(teinte: etat.valeur(cles.teinte), saturation: etat.valeur(cles.saturation), gain: gain)
                let vise = actuel + k * ecartZone
                var saturation = vise.norme / gain
                // La borne ne coupe pas un étalonnage déjà posé au-delà (celui de l'utilisateur, ou
                // copié de la référence) : jamais plus que max(borne, valeur actuelle), baisser libre.
                let borne = max(maxSat, etat.valeur(cles.saturation))
                if saturation > borne {
                    limites.append("Saturation des \(nomZone(z)) arrêtée à \(Int(borne))\(borne > maxSat ? " (sa valeur actuelle : match_look ne l'augmente pas au-delà de \(Int(maxSat)))" : (options.doseForte ? "" : " (borne de match_look ; 40 avec strong_dose_requested, sur demande)")).")
                    saturation = borne
                }
                let teinte = teinteLightroom(angle: atan2(vise.b, vise.a) * 180 / .pi).rounded()
                finales[cles.teinte] = teinte >= 360 ? 0 : teinte
                finales[cles.saturation] = saturation.rounded()
            }
        }
        if options.balance, let c = commune(ecart.zones), c.norme >= seuilZone {
            let p = pentes.serie, cible = k * c
            if etat.raw {
                let kelvins = etat.valeur("Temperature")
                if kelvins > 0 {
                    let mired = 1_000_000 / kelvins + p.miredA * cible.a + p.miredB * cible.b
                    finales["Temperature"] = min(max(1_000_000 / max(mired, 20), 2000), 50000).rounded()
                    finales["Tint"] = min(max(etat.valeur("Tint") + p.tintA * cible.a + p.tintB * cible.b, -150), 150).rounded()
                } else {
                    limites.append("Balance gardée : la température de ce RAW n'a pas pu être lue.")
                }
            } else {
                finales["Temperature"] = min(max(etat.valeur("Temperature") + p.jpegTempA * cible.a + p.jpegTempB * cible.b, -100), 100).rounded()
                finales["Tint"] = min(max(etat.valeur("Tint") + p.jpegTintA * cible.a + p.jpegTintB * cible.b, -100), 100).rounded()
            }
        }
        if options.saturation {
            if ecart.scenes > seuilScenes {
                limites.append("Les couleurs des deux scènes diffèrent (\(Int(ecart.scenes.rounded())) % de répartition par bande) : la saturation n'est pas copiée.")
            } else if let chroma = ecart.chroma, abs(chroma) >= Measurements.seuilChroma {
                let actuelle = etat.valeur("Vibrance")
                let delta = min(max(chroma * pentes.vibranceParChroma * k, -vibranceMaxPasse), vibranceMaxPasse)
                var finale = min(max(actuelle + delta, -100), 100)
                let plafond = DevelopCatalogue.plafondsDose.first { $0.key == "Vibrance" }?.max ?? 30
                if !options.doseForte, abs(finale) > plafond, abs(finale) > abs(actuelle) {
                    finale = (finale > 0 ? 1 : -1) * max(plafond, abs(actuelle))
                    limites.append("Vibrance arrêtée à \(Int(plafond)) (plafond de dose) : strong_dose_requested seulement sur demande.")
                }
                finales["Vibrance"] = finale.rounded()
            }
        }
        return (finales.filter { $0.value != etat.valeur($0.key) }, limites)
    }

    /// Pentes corrigées d'après une passe : pour chaque zone, la part du décalage voulu (modèle) que
    /// la mesure a montrée, bornée de ¼ à 4 fois le départ ; la Vibrance de même.
    static func pentesObservees(_ pentes: Pentes, avant: Etat, apres: [String: Double], mesureAvant: Signature,
                                       mesureApres: Signature) -> Pentes {
        var nouvelles = pentes
        let voulus: [Vecteur?] = (0..<3).map { z in
            let cles = clesZones[z]
            guard apres[cles.teinte] != nil || apres[cles.saturation] != nil else { return nil }
            let gain = pentes.gain[z]
            let v0 = vecteur(teinte: avant.valeur(cles.teinte), saturation: avant.valeur(cles.saturation), gain: gain)
            let v1 = vecteur(teinte: apres[cles.teinte] ?? avant.valeur(cles.teinte), saturation: apres[cles.saturation] ?? avant.valeur(cles.saturation), gain: gain)
            return v1 - v0
        }
        let observes: [Vecteur?] = (0..<3).map { z in
            guard let p = mesureAvant.zones[z], let q = mesureApres.zones[z] else { return nil }
            return Vecteur(a: q.a - p.a, b: q.b - p.b)
        }
        // Sans la part commune des deux côtés : une balance changée dans la même passe ne compte pas.
        let voulusRel = voulus.map { $0 ?? .zero }, observesRel = relatives(observes)
        let cv = commune(voulusRel) ?? .zero
        for z in 0..<3 {
            guard voulus[z] != nil, let observe = observesRel[z] else { continue }
            let voulu = voulusRel[z] - cv
            let norme2 = voulu.a * voulu.a + voulu.b * voulu.b
            guard norme2 >= 1 else { continue }
            let rapport = (observe.a * voulu.a + observe.b * voulu.b) / norme2
            guard rapport > 0 else { continue }
            nouvelles.gain[z] = min(max(pentes.gain[z] * rapport, gainDepart[z] / 4), gainDepart[z] * 4)
        }
        // La Vibrance, sur la chroma des seuls pixels colorés : un étalonnage changé dans la même passe
        // teinte les gris, pas eux (sinon toute la chroma gagnée irait au compte de la Vibrance).
        if let v1 = apres["Vibrance"], let c0 = mesureAvant.chromaCouleurs, let c1 = mesureApres.chromaCouleurs {
            let curseur = v1 - avant.valeur("Vibrance"), mesure = c1 - c0
            if abs(mesure) >= 0.5, curseur / mesure > 0 {
                nouvelles.vibranceParChroma = min(max(curseur / mesure, vibranceParChromaDepart / 4), vibranceParChromaDepart * 4)
            }
        }
        return nouvelles
    }

    // MARK: JSON

    static func arrondi(_ valeur: Double, _ decimales: Int = 1) -> JSONValue {
        let f = pow(10, Double(decimales))
        return .number((valeur * f).rounded() / f)
    }

    static func signatureJSON(_ s: Signature) -> JSONValue {
        var tons: [String: JSONValue] = [:]
        for p in [5, 25, 50, 75, 95] { tons["P\(p)"] = arrondi(s.centiles[p] ?? 0) }
        var objet: [String: JSONValue] = ["tons_L": .object(tons), "chroma_mediane": arrondi(s.chromaMediane), "chroma_P90": arrondi(s.chromaP90),
                                          "chroma_couleurs_vives": s.chromaCouleurs.map { arrondi($0) } ?? "non lue"]
        for (z, nom) in zones.enumerated() {
            objet[nom] = s.zones[z].map { ["a": arrondi($0.a), "b": arrondi($0.b), "part_pct": arrondi($0.part, 0)] } ?? "non lue"
        }
        let dominantes = s.bandes.enumerated().filter { $0.element >= 10 }.sorted { $0.element > $1.element }
            .map { JSONValue.string("\(PhotoMeasurements.bandes[$0.offset].nom) \(Int($0.element.rounded())) %") }
        if !dominantes.isEmpty { objet["bandes_dominantes"] = .array(dominantes) }
        if !s.remarques.isEmpty { objet["remarques"] = .array(s.remarques.map(JSONValue.string)) }
        return .object(objet)
    }

    static func ecartJSON(_ e: Ecart, balance: Bool) -> JSONValue {
        var objet: [String: JSONValue] = ["exposition_IL": .number((e.exposition * 20).rounded() / 20), "contraste": arrondi(e.contraste),
                                          "chroma": e.chroma.map { arrondi($0) } ?? "non comparée"]
        let rel = balance ? e.zones : relatives(e.zones)
        for (z, nom) in zones.enumerated() {
            objet[nom] = rel[z].map { ["a": arrondi($0.a), "b": arrondi($0.b)] } ?? "non comparée"
        }
        if !balance, let c = commune(e.zones) {
            objet["commune"] = ["a": arrondi(c.a), "b": arrondi(c.b), "lecture": "part commune aux zones (balance) : copiée seulement avec adjust white_balance"]
        }
        objet["distance"] = distance(e, balance: balance).map { arrondi($0) } ?? "pas de zones comparables"
        return .object(objet)
    }
}
