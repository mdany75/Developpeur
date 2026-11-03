import CoreGraphics
import Foundation

/// Les points chauds d'une photo (1.3.4) : les zones claires hors du sujet qui peuvent voler l'œil
/// (une fenêtre, une nappe blanche, un panneau), et depuis la 1.6.6 les zones nettement plus
/// saturées que le sujet (un parasol rouge derrière un portrait), `maxZones` au plus, données par `view_photo` sur
/// l'aperçu entier et jamais corrigées d'office. Fonctions pures, sur l'aperçu réduit à
/// `Measurements.maxSide` et les visages et la zone d'intérêt de Vision.
public enum PointsChauds {
    /// Zones données, au plus.
    static let maxZones = 5
    /// Cases de la grille sur le grand côté.
    static let grille = 24
    /// Une case est chaude si son L* moyen dépasse la médiane de l'image de `ecartMediane` et
    /// atteint au moins `lMin`. Provisoires, choisis hors de Lightroom : à relever sur de vraies
    /// photos (une fenêtre dans un intérieur, une nappe, un ciel blanc derrière un portrait).
    static let ecartMediane = 20.0, lMin = 70.0
    /// Part de l'image (%) d'une zone : en dessous, un reflet ponctuel ; au-dessus, un fond clair
    /// (un ciel) plutôt qu'un point qui vole l'œil. Provisoires.
    static let partMin = 0.3, partMax = 20.0
    /// Zones saturées (1.6.6, comparaison aslanoov `attention_check.py` et LrC-AVG, 2 nov. 2026) :
    /// une case l'est si son C* moyen dépasse de `ecartChroma` celui du sujet (cases des visages et
    /// de la zone d'intérêt ; sans sujet, la médiane de C* de l'image) et atteint au moins `cMin`.
    /// Provisoires, choisis par Claude hors de Lightroom : à relever sur de vraies photos.
    static let ecartChroma = 25.0, cMin = 35.0
    /// Part d'une zone dans le sujet (visages, zone d'intérêt) au-delà de laquelle elle est le sujet.
    static let recouvrementSujet = 0.3
    /// Une zone d'intérêt plus grande que cette part de l'image ne désigne pas de sujet (comme
    /// `Composition.zoneInteretMax`).
    static let zoneInteretMax = 0.5

    struct Zone: Equatable {
        var boite: CGRect
        var lMoyen: Double
        /// Écart à la médiane de L* (zone claire) ou au C* du sujet (zone saturée).
        var ecart: Double
        var part: Double
        /// C* moyen d'une zone saturée ; nil pour une zone claire.
        var chroma: Double? = nil
        /// Zone saturée mesurée contre le sujet (sinon contre la médiane de C* de l'image).
        var contreSujet = false
    }

    /// La grille des L* moyens de l'image réduite à `Measurements.maxSide`, et la médiane de L* de
    /// tous ses pixels : ce que `trouver` lit avant de choisir ses cases (extrait pour le relevé des
    /// seuils, `ReleveSeuils`, qui rejoue d'autres seuils sur la même grille).
    struct Grille: Equatable {
        var colonnes: Int
        var lignes: Int
        /// L* moyen de chaque case, ligne par ligne depuis le haut gauche.
        var moyennes: [Double]
        var mediane: Double
        /// C* moyen de chaque case, et la médiane de C* de tous les pixels (zones saturées).
        var chromas: [Double] = []
        var medianeChroma = 0.0
    }

    static func lireGrille(_ image: CGImage) -> Grille? {
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        let largeur = reduite.width, hauteur = reduite.height
        guard largeur > 0, hauteur > 0, let pixels = Measurements.rgba(reduite) else { return nil }
        let colonnes = largeur >= hauteur ? grille : max(1, Int((Double(grille) * Double(largeur) / Double(hauteur)).rounded()))
        let lignes = largeur >= hauteur ? max(1, Int((Double(grille) * Double(hauteur) / Double(largeur)).rounded())) : grille
        var somme = [Double](repeating: 0, count: colonnes * lignes), nombre = [Int](repeating: 0, count: colonnes * lignes)
        var sommeC = [Double](repeating: 0, count: colonnes * lignes)
        var tous: [Double] = [], tousC: [Double] = []
        tous.reserveCapacity(largeur * hauteur)
        tousC.reserveCapacity(largeur * hauteur)
        for y in 0..<hauteur {
            for x in 0..<largeur {
                let i = (y * largeur + x) * 4
                let lab = Measurements.lab(pixels[i], pixels[i + 1], pixels[i + 2])
                let l = min(max(lab.l, 0), 100), chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
                let c = min(colonnes - 1, x * colonnes / largeur) + min(lignes - 1, y * lignes / hauteur) * colonnes
                somme[c] += l
                sommeC[c] += chroma
                nombre[c] += 1
                tous.append(l)
                tousC.append(chroma)
            }
        }
        tous.sort()
        tousC.sort()
        let moyennes = somme.indices.map { nombre[$0] > 0 ? somme[$0] / Double(nombre[$0]) : 0 }
        let chromas = sommeC.indices.map { nombre[$0] > 0 ? sommeC[$0] / Double(nombre[$0]) : 0 }
        return Grille(colonnes: colonnes, lignes: lignes, moyennes: moyennes, mediane: tous[tous.count / 2],
                      chromas: chromas, medianeChroma: tousC[tousC.count / 2])
    }

    /// Les zones claires hors du sujet, de la plus forte à la plus faible (écart à la médiane fois
    /// surface). `sujet` : les cadres des visages et la zone d'intérêt, de 0 à 1 depuis le coin haut
    /// gauche ; `visages` : les cadres des visages seuls, d'où les bustes des zones saturées.
    static func trouver(_ image: CGImage, sujet: [CGRect], visages: [CGRect] = []) -> [Zone] {
        guard let grille = lireGrille(image) else { return [] }
        let claires = zones(grille, sujet: sujet)
        let saturees = zonesSaturees(grille, sujet: sujet, bustes: visages.map(buste))
        // Claires d'abord (la mesure relevée), puis les saturées, `maxZones` en tout.
        return Array((claires + saturees).prefix(maxZones))
    }

    /// Les zones d'une grille sous ces seuils (ceux de `trouver` par défaut ; d'autres pour le relevé).
    static func zones(_ grille: Grille, sujet: [CGRect], ecartMediane: Double = ecartMediane, lMin: Double = lMin,
                      partMin: Double = partMin, partMax: Double = partMax) -> [Zone] {
        let mediane = grille.mediane
        let seuil = max(lMin, mediane + ecartMediane)
        let zones = groupes(grille, chaude: grille.moyennes.map { $0 >= seuil }, sujet: sujet, partMin: partMin, partMax: partMax)
            .map { boite, membres, part -> Zone in
                let lMoyen = membres.map { grille.moyennes[$0] }.reduce(0, +) / Double(membres.count)
                return Zone(boite: boite, lMoyen: lMoyen, ecart: lMoyen - mediane, part: part)
            }
        return Array(zones.sorted { $0.ecart * $0.part > $1.ecart * $1.part }.prefix(maxZones))
    }

    /// Le buste sous un visage (une largeur de visage de chaque côté, trois hauteurs dessous) : le
    /// vêtement du sujet en fait partie, jamais une zone qui vole l'œil (revue du 2 nov. 2026 : un
    /// pull vif d'un portrait serré sortait en zone saturée). Gardé quelle que soit sa taille.
    static func buste(_ visage: CGRect) -> CGRect {
        let gauche = max(0, visage.minX - visage.width), droite = min(1, visage.maxX + visage.width)
        let bas = min(1, visage.maxY + 3 * visage.height)
        return CGRect(x: gauche, y: visage.minY, width: droite - gauche, height: bas - visage.minY)
    }

    /// Les zones nettement plus saturées que le sujet, hors du sujet, des bustes et des zones claires
    /// (une case claire et saturée reste une zone claire), de la plus forte à la plus faible. Un fond
    /// saturé étendu (un ciel bleu vu entre des arbres, en morceaux) n'en donne aucune : comme
    /// `partMax` pour un grand ciel clair, mais sur toutes les cases saturées ensemble. D'autres seuils
    /// que ceux de `trouver` : pour le relevé (`ReleveSeuils`, zones candidates de la planche).
    static func zonesSaturees(_ grille: Grille, sujet: [CGRect], bustes: [CGRect] = [],
                              ecartChroma: Double = ecartChroma, cMin: Double = cMin) -> [Zone] {
        guard grille.chromas.count == grille.moyennes.count, !grille.chromas.isEmpty else { return [] }
        let interet = sujet.filter { $0.width * $0.height <= zoneInteretMax } + bustes
        let dansLeSujet = grille.chromas.indices.filter { c in
            let centre = CGPoint(x: (Double(c % grille.colonnes) + 0.5) / Double(grille.colonnes),
                                 y: (Double(c / grille.colonnes) + 0.5) / Double(grille.lignes))
            return interet.contains { $0.contains(centre) }
        }
        let reference = dansLeSujet.isEmpty ? grille.medianeChroma
            : dansLeSujet.map { grille.chromas[$0] }.reduce(0, +) / Double(dansLeSujet.count)
        let seuilL = max(lMin, grille.mediane + ecartMediane), seuilC = max(cMin, reference + ecartChroma)
        let chaude = grille.chromas.indices.map { grille.chromas[$0] >= seuilC && grille.moyennes[$0] < seuilL }
        let partTotale = Double(chaude.filter { $0 }.count) * 100 / Double(chaude.count)
        guard partTotale <= partMax else { return [] }
        let zones = groupes(grille, chaude: chaude, sujet: sujet, entiers: bustes, partMin: partMin, partMax: partMax)
            .map { boite, membres, part -> Zone in
                let n = Double(membres.count)
                let chroma = membres.map { grille.chromas[$0] }.reduce(0, +) / n
                return Zone(boite: boite, lMoyen: membres.map { grille.moyennes[$0] }.reduce(0, +) / n,
                            ecart: chroma - reference, part: part, chroma: chroma, contreSujet: !dansLeSujet.isEmpty)
            }
        return Array(zones.sorted { $0.ecart * $0.part > $1.ecart * $1.part }.prefix(maxZones))
    }

    /// Les cases marquées voisines (4-connexité) regroupées en zones, gardées si leur part de
    /// l'image est entre `partMin` et `partMax` et qu'elles débordent assez du sujet (`entiers` :
    /// des cadres du sujet gardés quelle que soit leur taille, les bustes).
    static func groupes(_ grille: Grille, chaude marquees: [Bool], sujet: [CGRect], entiers: [CGRect] = [],
                        partMin: Double, partMax: Double) -> [(boite: CGRect, membres: [Int], part: Double)] {
        let colonnes = grille.colonnes, lignes = grille.lignes
        var chaude = marquees
        let interet = sujet.filter { $0.width * $0.height <= zoneInteretMax } + entiers
        var resultat: [(boite: CGRect, membres: [Int], part: Double)] = []
        for depart in chaude.indices where chaude[depart] {
            var pile = [depart], membres: [Int] = []
            chaude[depart] = false
            while let c = pile.popLast() {
                membres.append(c)
                let x = c % colonnes, y = c / colonnes
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < colonnes, ny < lignes else { continue }
                    let n = ny * colonnes + nx
                    if chaude[n] { chaude[n] = false; pile.append(n) }
                }
            }
            let xs = membres.map { $0 % colonnes }, ys = membres.map { $0 / colonnes }
            let boite = CGRect(x: Double(xs.min()!) / Double(colonnes), y: Double(ys.min()!) / Double(lignes),
                               width: Double(xs.max()! - xs.min()! + 1) / Double(colonnes), height: Double(ys.max()! - ys.min()! + 1) / Double(lignes))
            let part = Double(membres.count) * 100 / Double(colonnes * lignes)
            guard part >= partMin, part <= partMax else { continue }
            let recouvre = interet.map { boite.intersection($0) }.filter { !$0.isNull }
                .map { $0.width * $0.height }.max() ?? 0
            guard recouvre < recouvrementSujet * boite.width * boite.height else { continue }
            resultat.append((boite, membres, part))
        }
        return resultat
    }

    /// Où est une zone, en mots : « en haut à gauche », « au milieu à droite »…
    static func ou(_ boite: CGRect) -> String {
        let haut = boite.midY < 1.0 / 3 ? "en haut" : (boite.midY > 2.0 / 3 ? "en bas" : "au milieu")
        let cote = boite.midX < 1.0 / 3 ? "à gauche" : (boite.midX > 2.0 / 3 ? "à droite" : "au centre")
        return haut == "au milieu" && cote == "au centre" ? "au centre" : "\(haut) \(cote)"
    }

    static func json(_ zones: [Zone]) -> JSONValue? {
        guard !zones.isEmpty else { return nil }
        func r(_ valeur: Double) -> JSONValue { .number((valeur * 1000).rounded() / 1000) }
        func r1(_ valeur: Double) -> JSONValue { .number((valeur * 10).rounded() / 10) }
        return [
            "zones": .array(zones.map { zone in
                var objet: [String: JSONValue] = [
                    "ou": .string(ou(zone.boite)), "x": r(zone.boite.minX), "y": r(zone.boite.minY),
                    "largeur": r(zone.boite.width), "hauteur": r(zone.boite.height),
                    "L_moyen": r1(zone.lMoyen), "part_pct": r1(zone.part)]
                if let chroma = zone.chroma {
                    objet["sorte"] = "saturée"
                    objet["C_moyen"] = r1(chroma)
                    objet[zone.contreSujet ? "au_dessus_du_sujet" : "au_dessus_de_la_mediane_C"] = r1(zone.ecart)
                } else {
                    objet["sorte"] = "claire"
                    objet["au_dessus_de_la_mediane"] = r1(zone.ecart)
                }
                return .object(objet)
            }),
            "lecture": "Zones hors du sujet (visages, zone d'intérêt) qui peuvent voler l'œil : claires d'abord, puis nettement plus saturées que le sujet (sans sujet : que la médiane de l'image ; seuils provisoires). Rien n'est corrigé d'office : les montrer, puis les assombrir ou les désaturer (add_mask : radial, pinceau ou objet) seulement si elles distraient vraiment, et le dire.",
        ]
    }
}
