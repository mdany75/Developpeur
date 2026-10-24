import CoreGraphics
import Foundation

/// Les points chauds d'une photo (1.3.4) : les zones claires hors du sujet qui peuvent voler l'œil
/// (une fenêtre, une nappe blanche, un panneau), `maxZones` au plus, données par `view_photo` sur
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
    /// Part d'une zone dans le sujet (visages, zone d'intérêt) au-delà de laquelle elle est le sujet.
    static let recouvrementSujet = 0.3
    /// Une zone d'intérêt plus grande que cette part de l'image ne désigne pas de sujet (comme
    /// `Composition.zoneInteretMax`).
    static let zoneInteretMax = 0.5

    struct Zone: Equatable {
        var boite: CGRect
        var lMoyen: Double
        var ecart: Double
        var part: Double
    }

    /// Les zones claires hors du sujet, de la plus forte à la plus faible (écart à la médiane fois
    /// surface). `sujet` : les cadres des visages et la zone d'intérêt, de 0 à 1 depuis le coin haut
    /// gauche.
    static func trouver(_ image: CGImage, sujet: [CGRect]) -> [Zone] {
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        let largeur = reduite.width, hauteur = reduite.height
        guard largeur > 0, hauteur > 0, let pixels = Measurements.rgba(reduite) else { return [] }
        let colonnes = largeur >= hauteur ? grille : max(1, Int((Double(grille) * Double(largeur) / Double(hauteur)).rounded()))
        let lignes = largeur >= hauteur ? max(1, Int((Double(grille) * Double(hauteur) / Double(largeur)).rounded())) : grille
        var somme = [Double](repeating: 0, count: colonnes * lignes), nombre = [Int](repeating: 0, count: colonnes * lignes)
        var tous: [Double] = []
        tous.reserveCapacity(largeur * hauteur)
        for y in 0..<hauteur {
            for x in 0..<largeur {
                let i = (y * largeur + x) * 4
                let l = min(max(Measurements.lab(pixels[i], pixels[i + 1], pixels[i + 2]).l, 0), 100)
                let c = min(colonnes - 1, x * colonnes / largeur) + min(lignes - 1, y * lignes / hauteur) * colonnes
                somme[c] += l
                nombre[c] += 1
                tous.append(l)
            }
        }
        tous.sort()
        let mediane = tous[tous.count / 2]
        let seuil = max(lMin, mediane + ecartMediane)
        let moyennes = somme.indices.map { nombre[$0] > 0 ? somme[$0] / Double(nombre[$0]) : 0 }
        var chaude = moyennes.map { $0 >= seuil }
        let interet = sujet.filter { $0.width * $0.height <= zoneInteretMax }
        var zones: [Zone] = []
        for depart in chaude.indices where chaude[depart] {
            // Les cases chaudes voisines (4-connexité) forment une zone.
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
            let dansLeSujet = interet.map { boite.intersection($0) }.filter { !$0.isNull }
                .map { $0.width * $0.height }.max() ?? 0
            guard dansLeSujet < recouvrementSujet * boite.width * boite.height else { continue }
            let lMoyen = membres.map { moyennes[$0] }.reduce(0, +) / Double(membres.count)
            zones.append(Zone(boite: boite, lMoyen: lMoyen, ecart: lMoyen - mediane, part: part))
        }
        return Array(zones.sorted { $0.ecart * $0.part > $1.ecart * $1.part }.prefix(maxZones))
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
                ["ou": .string(ou(zone.boite)), "x": r(zone.boite.minX), "y": r(zone.boite.minY),
                 "largeur": r(zone.boite.width), "hauteur": r(zone.boite.height),
                 "L_moyen": r1(zone.lMoyen), "au_dessus_de_la_mediane": r1(zone.ecart), "part_pct": r1(zone.part)]
            }),
            "lecture": "Zones claires hors du sujet (visages, zone d'intérêt), de la plus forte à la plus faible : elles peuvent voler l'œil. Rien n'est corrigé d'office : les montrer, puis les assombrir (add_mask : radial, pinceau ou objet) seulement si elles distraient vraiment, et le dire.",
        ]
    }
}
