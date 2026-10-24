import CoreGraphics
import Foundation

/// Carte d'un masque (1.3.4) : où il porte, lu sur un rendu témoin. Le serveur fait rendre la photo
/// avec ce seul masque, son effet remplacé par un témoin fort (`temoin`), et compare ce rendu à
/// l'état actuel rendu par la même commande : hors du masque, les deux rendus sont les mêmes pixels.
/// Puis les alertes : un masque presque vide, presque total, qui déborde sur un visage, ou qui
/// semble inversé. Fonctions pures ; les rendus et Vision sont à `ToolHandler.cartesDesMasques`.
public enum CarteMasque {
    /// Masques cartographiés par appel, au plus (un rendu chacun).
    static let maxMasques = 4
    /// L'effet témoin, aux clés d'une correction de masque : +1,5 IL (pour les tons sombres et
    /// moyens) et une température plus froide (pour les blancs, que l'exposition ne change plus).
    static let temoin: [String: JSONValue] = ["LocalExposure2012": .number(0.375), "LocalTemperature": .number(-0.4)]
    /// Écart d'un canal (sur 255) à partir duquel un pixel compte dans le masque. Hors du masque,
    /// les deux rendus sont identiques ; les blocs JPEG au bord du masque bougent de 1 à 3.
    static let seuilEcart = 6
    /// Part de l'image (%) sous laquelle le masque est presque vide, au-delà de laquelle il est
    /// presque total. Provisoires : à relever sur de vrais masques.
    static let partVide = 0.5, partTotale = 95.0
    /// Part d'un visage couverte au-delà de laquelle un masque qui ne vise pas une personne déborde
    /// sur lui. Provisoire.
    static let debordVisage = 0.25
    /// Un ciel dont le centre de gravité tombe plus bas que cette hauteur (0 en haut, 1 en bas)
    /// semble inversé. Provisoire.
    static let cielBas = 0.6
    /// Un sujet ou une personne qui ne couvre pas cette part des visages, mais plus de
    /// `sujetLarge` de l'image, semble inversé. Provisoires.
    static let sujetVisages = 0.2, sujetLarge = 40.0

    /// Le masque à rendre en témoin : le même masque (zone, composants, inversion), à pleine
    /// intensité, avec l'effet témoin seul (ni effet, ni courbe, ni couleurs ponctuelles).
    static func masqueTemoin(_ masque: JSONValue) -> JSONValue {
        guard var objet = masque.object else { return masque }
        objet["locaux"] = .object(temoin)
        objet["quantite"] = .number(1)
        objet.removeValue(forKey: "couleurs_ponctuelles")
        objet["nom"] = .string("Claude · carte du masque")
        return .object(objet)
    }

    /// Les pixels du masque : ceux où un canal s'écarte d'au moins `seuilEcart` entre l'état actuel
    /// et le témoin, réduits à `Measurements.maxSide`. Nil si les images n'ont pas la même taille.
    static func pixels(actuel: CGImage, temoin: CGImage) -> (masque: [Bool], largeur: Int, hauteur: Int)? {
        let a = PreviewImages.scaled(actuel, maxSide: Measurements.maxSide)
        let t = PreviewImages.scaled(temoin, maxSide: Measurements.maxSide)
        guard a.width == t.width, a.height == t.height,
              let pa = Measurements.rgba(a), let pt = Measurements.rgba(t) else { return nil }
        let nombre = a.width * a.height
        var masque = [Bool](repeating: false, count: nombre)
        for i in 0..<nombre {
            for c in 0..<3 where abs(Int(pa[i * 4 + c]) - Int(pt[i * 4 + c])) >= seuilEcart {
                masque[i] = true
                break
            }
        }
        return (masque, a.width, a.height)
    }

    /// Ce qu'une carte dit : la part de l'image couverte, la zone (cadre des pixels couverts, de 0 à
    /// 1 depuis le coin haut gauche), le centre de gravité, et la part couverte de chaque visage.
    struct Lecture: Equatable {
        var part: Double
        var zone: CGRect?
        var centre: CGPoint?
        var visages: [Double]
    }

    static func lire(_ masque: [Bool], largeur: Int, hauteur: Int, visages: [CGRect]) -> Lecture {
        let nombre = largeur * hauteur
        guard nombre > 0, masque.count == nombre else { return Lecture(part: 0, zone: nil, centre: nil, visages: visages.map { _ in 0 }) }
        var compte = 0, sx = 0.0, sy = 0.0
        var minX = largeur, minY = hauteur, maxX = -1, maxY = -1
        for y in 0..<hauteur {
            for x in 0..<largeur where masque[y * largeur + x] {
                compte += 1
                sx += Double(x)
                sy += Double(y)
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let parVisage = visages.map { boite -> Double in
            let x0 = max(0, Int((boite.minX * Double(largeur)).rounded(.down))), x1 = min(largeur, Int((boite.maxX * Double(largeur)).rounded(.up)))
            let y0 = max(0, Int((boite.minY * Double(hauteur)).rounded(.down))), y1 = min(hauteur, Int((boite.maxY * Double(hauteur)).rounded(.up)))
            guard x1 > x0, y1 > y0 else { return 0 }
            var dedans = 0
            for y in y0..<y1 { for x in x0..<x1 where masque[y * largeur + x] { dedans += 1 } }
            return Double(dedans) / Double((x1 - x0) * (y1 - y0))
        }
        guard compte > 0 else { return Lecture(part: 0, zone: nil, centre: nil, visages: parVisage) }
        let l = Double(largeur), h = Double(hauteur)
        return Lecture(part: Double(compte) * 100 / Double(nombre),
                       zone: CGRect(x: Double(minX) / l, y: Double(minY) / h, width: Double(maxX - minX + 1) / l, height: Double(maxY - minY + 1) / h),
                       centre: CGPoint(x: (sx / Double(compte) + 0.5) / l, y: (sy / Double(compte) + 0.5) / h),
                       visages: parVisage)
    }

    /// Le genre d'un masque, tel que le module le reçoit : « ia » avec son sous-type, « personne »,
    /// « radial », « lineaire »… Une personne ou une partie de personne vise les visages ; un radial
    /// non inversé aussi (le sujet éclairci).
    static func viseUnePersonne(_ masque: JSONValue, genre: String?) -> Bool {
        switch masque["type"]?.string {
        case "personne": return true
        case "radial": return masque["inverser"]?.bool != true
        default: return ["subject", "person_part"].contains(genre ?? "")
        }
    }

    /// Les alertes d'une carte. `genre` : le kind donné à add_mask (« sky », « subject »…).
    static func alertes(_ lecture: Lecture, masque: JSONValue, genre: String?) -> [String] {
        var alertes: [String] = []
        if lecture.part < partVide {
            alertes.append("presque vide : il ne touche que \(pourcent(lecture.part)) de l'image (Lightroom n'y a peut-être rien trouvé)")
            return alertes
        }
        if lecture.part > partTotale {
            alertes.append("presque total : il couvre \(pourcent(lecture.part)) de l'image (inversé, ou trop large ?)")
        }
        let inverse = masque["inverser"]?.bool == true
        if !viseUnePersonne(masque, genre: genre) {
            let touches = lecture.visages.enumerated().filter { $0.element >= debordVisage }
            if !touches.isEmpty {
                let liste = touches.map { "visage \($0.offset + 1) à \(pourcent($0.element * 100))" }.joined(separator: ", ")
                alertes.append("déborde sur un visage : \(liste) (à retirer du masque, par combine en soustraction, ou à vérifier par un zoom)")
            }
        }
        if !inverse, genre == "sky", let centre = lecture.centre, centre.y > cielBas {
            alertes.append("semble inversé : le ciel porte surtout dans le bas de l'image (centre à \(pourcent(centre.y * 100)) de la hauteur)")
        }
        if !inverse, ["subject", "person"].contains(genre ?? ""), !lecture.visages.isEmpty,
           (lecture.visages.max() ?? 0) < sujetVisages, lecture.part > sujetLarge {
            alertes.append("semble inversé : il couvre \(pourcent(lecture.part)) de l'image, mais presque rien des visages")
        }
        return alertes
    }

    /// « 12 % », à la française.
    static func pourcent(_ valeur: Double) -> String { Bilan.nombre(valeur, decimales: valeur < 10 ? 1 : 0) + " %" }

    /// Ce que la réponse en dit, pour un masque.
    static func json(_ lecture: Lecture, numero: Int, nom: String?, alertes: [String]) -> JSONValue {
        func r(_ valeur: Double) -> JSONValue { .number((valeur * 1000).rounded() / 1000) }
        var item: [String: JSONValue] = ["masque": .number(Double(numero)), "part_de_l_image_pct": .number((lecture.part * 10).rounded() / 10)]
        if let nom { item["nom"] = .string(nom) }
        if let zone = lecture.zone {
            item["zone"] = ["x": r(zone.minX), "y": r(zone.minY), "largeur": r(zone.width), "hauteur": r(zone.height)]
        }
        if !lecture.visages.isEmpty {
            item["visages_couverts_pct"] = .array(lecture.visages.map { .number(($0 * 1000).rounded() / 10) })
        }
        item["alertes"] = .array(alertes.map(JSONValue.string))
        return .object(item)
    }

    /// Les couleurs de la carte, une par masque.
    static let couleurs: [(UInt8, UInt8, UInt8)] = [(230, 40, 40), (40, 120, 240), (30, 190, 80), (240, 200, 20)]

    /// L'image de la carte : l'état actuel, chaque masque teinté de sa couleur (rouge, bleu, vert,
    /// jaune, dans l'ordre des masques), le reste assombri.
    static func dessiner(actuel: CGImage, cartes: [[Bool]], largeur: Int, hauteur: Int) -> Data? {
        let base = PreviewImages.scaled(actuel, maxSide: Measurements.maxSide)
        guard base.width == largeur, base.height == hauteur, var pixels = Measurements.rgba(base),
              let espace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        for i in 0..<(largeur * hauteur) {
            let couvrants = cartes.indices.filter { cartes[$0].count > i && cartes[$0][i] }
            if couvrants.isEmpty {
                for c in 0..<3 { pixels[i * 4 + c] = UInt8(Double(pixels[i * 4 + c]) * 0.45) }
                continue
            }
            var teinte = (0.0, 0.0, 0.0)
            for k in couvrants {
                let couleur = couleurs[k % couleurs.count]
                teinte.0 += Double(couleur.0); teinte.1 += Double(couleur.1); teinte.2 += Double(couleur.2)
            }
            let n = Double(couvrants.count)
            let melange = [teinte.0 / n, teinte.1 / n, teinte.2 / n]
            for c in 0..<3 { pixels[i * 4 + c] = UInt8(min(255, (Double(pixels[i * 4 + c]) * 0.5 + melange[c] * 0.5).rounded())) }
        }
        let image = pixels.withUnsafeMutableBytes { tampon -> CGImage? in
            CGContext(data: tampon.baseAddress, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: largeur * 4,
                      space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        return image.flatMap { PreviewImages.jpeg($0) }
    }
}
