import CoreGraphics
import Foundation
import ImageIO

/// Netteté et bruit d'un aperçu, mesurés sur sa luminance : de quoi juger la mise au point
/// (zone la plus nette, photo floue) et doser la réduction du bruit. Sur l'aperçu entier, la
/// mesure se fait à `Detail.side` px de grand côté ; sur un zoom, en pleine résolution.
public struct DetailMeasurements: Equatable {
    /// Netteté des 9 zones (3 × 3, ligne par ligne depuis le haut gauche) : 95e centile de la
    /// valeur absolue du laplacien, en niveaux sur 255.
    public var zones: [Double]
    /// Bruit : écart type du résidu (pixel moins la moyenne de ses voisins) dans les aplats, en
    /// niveaux sur 255 ; `shadowNoise` dans les aplats sombres seulement.
    public var noise: Double
    public var shadowNoise: Double?
    /// Grand côté de l'image mesurée, en pixels.
    public var side: Int
    /// Mesure d'un zoom à 100 % (view_photo avec region) : les chiffres servent à comparer deux
    /// zooms de la même photo ; les lectures (« floue probable », « bruit fort ») tiennent aux seuils
    /// relevés sur un aperçu entier réduit à `Detail.side` px et ne valent pas à cette échelle (un
    /// contour net réduit six fois donne un laplacien bien plus haut qu'à 100 % ; le bruit, l'inverse).
    public var zoom = false

    static let zoneNames = ["en haut à gauche", "en haut", "en haut à droite", "à gauche", "au centre",
                            "à droite", "en bas à gauche", "en bas", "en bas à droite"]

    public var sharpest: Double { zones.max() ?? 0 }
    public var medianSharpness: Double { zones.sorted()[zones.count / 2] }
    public var sharpestZone: String { Self.zoneNames[zones.indices.max { zones[$0] < zones[$1] } ?? 4] }

    /// Seuils de netteté relevés sur des aperçus de 1024 px : une photo nette donne de 45 à 150
    /// selon son contenu, un léger flou (gaussien de rayon 1,5 px) de 12 à 26, un flou marqué moins
    /// de 6. Sous `seuilFlou`, floue probable ; à partir de `seuilNet`, nette. Repris par le tri
    /// (`PhotoTriee.defautsMesures`), les plafonds de note (`Notation.plafond`) et le bilan.
    static let seuilFlou = 15.0, seuilNet = 35.0

    public var sharpnessReading: String {
        switch sharpest {
        case ..<Self.seuilFlou: return "floue probable : aucune zone nette"
        case ..<Self.seuilNet: return "douce : peu de détails nets (flou léger, ou sujet sans texture)"
        default: return "nette \(sharpestZone)"
        }
    }

    /// Seuils de bruit relevés à 1024 px : une image propre donne de 0,2 à 0,5, des ombres relevées
    /// vers 1. À partir de `bruitVisible`, il se voit ; à partir de `bruitFort`, la photo se
    /// débruite, et se note après.
    static let bruitVisible = 0.6, bruitFort = 1.5

    /// Plancher de texture autour du point de mise au point (`Detail.autour`) : en dessous, la zone
    /// n'a pas assez de détail pour juger la mise au point (sable lisse, ciel uni, mur), et la
    /// netteté au point n'en dit rien ; la mise au point est « non jugée ». Relevé le 21 octobre 2026
    /// (mesures de la 1.3, Lightroom Classic 15.6) sur les vues de 1 344 px des huit copies d'Essais,
    /// mesurées comme ici (les 81 blocs du carré), le carré vert du point AF effacé d'abord
    /// (interpolé entre ses bords ; vérifié sur une vue de la dune sans carré : 11,6 des deux façons) :
    /// - le point sur du sable lisse (netteté 12,6, la voiture et la dune nettes) : texture 11,2 à
    ///   11,6, sous le plancher : la fausse « mise au point manquée » est écartée ;
    /// - le point sur un nuage (53709534, netteté 6,6, toute la scène nette) : texture 23,6 à 24,1,
    ///   au-dessus du plancher, donc jugé ; sa fausse « mise au point manquée » n'est plus qu'un
    ///   doute (`textureDouteuse` : 2, à vérifier, sans rejet). Un plancher plus haut ne l'écarte pas
    ///   sans écarter aussi un petit visage, net (53709579 : 25,8 à 28,4) ou flouté de 1 à 3 px à
    ///   1 024 px (21,3 à 27,2 : une vraie mise au point manquée, à garder jugée) ; le bord d'un
    ///   nuage a autant de texture qu'un petit sujet flou (un autre indice que la texture le
    ///   départagerait) ;
    /// - les autres points (visages, sujets) : 28,4 à 64,6 nets, 21,3 au moins floutés.
    /// (Une première mesure, sur les seuls blocs que le carré ne touchait pas, n'en gardait qu'un :
    /// 12,9 et 14,4 ; elle ne valait pas.) À relever sur d'autres photos (ciel uni, mur, neige)
    /// avant de le changer.
    static let textureMin = 18.0
    /// Texture faible autour du point AF, au-dessus du plancher : la mise au point manquée y reste
    /// un doute (le bord d'un nuage, 23,6 à 24,1, a autant de texture qu'un petit visage flou, 21,3
    /// à 27,2 ; les sujets nets relevés le 21 octobre 2026 vont de 28,4 à 64,6, sauf le petit visage
    /// net de 53709579, de 25,8 à 28,4). De `textureMin` à cette valeur, une mise au point manquée
    /// plafonne à 2, à vérifier par un zoom à 100 %, sans rejet proposé (`Notation.plafond`), et le
    /// carnet ne la compte pas : une mesure douteuse ne propose pas de jeter une photo. Choisi par
    /// Claude le 21 octobre 2026 sur ces seuls relevés (huit copies d'Essais) : à relever encore.
    static let textureDouteuse = 30.0

    public var noiseReading: String {
        let level = max(noise, shadowNoise ?? 0)
        switch level {
        case ..<Self.bruitVisible: return "faible"
        case ..<Self.bruitFort: return "visible, surtout dans les ombres : à vérifier par un zoom à 100 %"
        default: return "fort : réduction du bruit à prévoir (vérifier par un zoom à 100 %)"
        }
    }

    public var json: JSONValue {
        func r(_ value: Double) -> JSONValue { .number((value * 10).rounded() / 10) }
        func r2(_ value: Double) -> JSONValue { .number((value * 100).rounded() / 100) }
        var noiseObject: [String: JSONValue] = ["aplats": r2(noise)]
        if let shadowNoise { noiseObject["ombres"] = r2(shadowNoise) }
        var nettete: [String: JSONValue] = [
            "max": r(sharpest),
            "mediane": r(medianSharpness),
            "zone_la_plus_nette": .string(sharpestZone),
            "zones_3x3": .array(stride(from: 0, to: 9, by: 3).map { row in .array(zones[row..<row + 3].map(r)) }),
        ]
        if zoom {
            return [
                "nettete": .object(nettete),
                "bruit": .object(noiseObject),
                "base_detail": .string("Zoom à 100 % (\(side) px de grand côté) : chiffres bruts, à comparer entre deux zooms de la même photo (avant et après) ; les seuils de lecture (flou probable, bruit fort) sont relevés sur l'aperçu entier réduit à \(Detail.side) px et ne s'appliquent pas ici. Juger la netteté et le grain à l'œil sur l'image."),
            ]
        }
        nettete["lecture"] = .string(sharpnessReading)
        noiseObject["lecture"] = .string(noiseReading)
        return [
            "nettete": .object(nettete),
            "bruit": .object(noiseObject),
            "base_detail": .string("Luminance à \(side) px de grand côté. Netteté : 95e centile du laplacien par zone (moins de \(Bilan.nombre(Self.seuilFlou, decimales: 0)) : flou probable ; plus de \(Bilan.nombre(Self.seuilNet, decimales: 0)) : net). Bruit : écart type du résidu dans les aplats, en niveaux sur 255 (moins de \(Bilan.nombre(Self.bruitVisible)) : faible)."),
        ]
    }
}

/// Netteté et texture autour du point de mise au point, mesurées dans le même carré (`Detail.autour`).
public struct MesureAutour: Equatable {
    /// 95e centile du laplacien : la netteté au point.
    public var nettete: Double
    /// 75e centile de l'écart entre blocs voisins de 8 × 8 px (moyennes) : le détail à une échelle
    /// que le flou d'une mise au point manquée efface peu.
    public var texture: Double
}

public enum Detail {
    /// Grand côté de la mesure sur un aperçu entier : les seuils de lecture valent à cette taille.
    public static let side = 1024

    /// Mesure un JPEG (ou toute image lisible par ImageIO), réduit à `maxSide` px s'il est plus grand.
    public static func analyze(_ data: Data, maxSide: Int = side) -> DetailMeasurements? {
        guard let image = PreviewImages.image(data) else { return nil }
        return analyze(PreviewImages.scaled(image, maxSide: maxSide))
    }

    public static func analyze(_ image: CGImage) -> DetailMeasurements? {
        guard let (width, height, values) = luminance(image), width >= 24, height >= 24 else { return nil }
        return analyze(luminance: values, width: width, height: height)
    }

    /// Netteté autour d'un point de l'image (0 à 1 depuis le coin haut gauche) : 95e centile du
    /// laplacien dans un carré dont le côté vaut `cote` × le petit côté, mesuré comme les zones, à
    /// `side` px de grand côté (mêmes seuils de lecture). Pour juger la mise au point là où
    /// l'appareil l'a faite. Nil si le point sort de l'image.
    public static func nettete(_ image: CGImage, autour point: CGPoint, cote: Double = 0.12) -> Double? {
        autour(image, point: point, cote: cote)?.nettete
    }

    /// Côté des blocs de la texture (`autour`), en pixels à `side` px de grand côté.
    static let blocTexture = 8

    /// Netteté et texture autour d'un point, dans le carré de `nettete` (même lecture de la
    /// luminance). La texture : 75e centile de l'écart entre blocs voisins de `blocTexture` px
    /// (|droite − gauche| + |bas − haut| des moyennes des blocs), en niveaux sur 255. Un contour
    /// isolé (bord d'un nuage) ne la fait pas monter ; un sujet flou garde la sienne
    /// (`DetailMeasurements.textureMin`). Nil si le point sort de l'image ; texture 0 si le carré
    /// est trop petit pour deux blocs.
    public static func autour(_ image: CGImage, point: CGPoint, cote: Double = 0.12) -> MesureAutour? {
        guard (0...1).contains(point.x), (0...1).contains(point.y),
              let (w, h, v) = luminance(PreviewImages.scaled(image, maxSide: side)), w >= 24, h >= 24 else { return nil }
        let demi = max(4, Int(Double(min(w, h)) * cote / 2))
        let cx = Int(point.x * Double(w)), cy = Int(point.y * Double(h))
        let x0 = max(1, cx - demi), x1 = min(w - 2, cx + demi), y0 = max(1, cy - demi), y1 = min(h - 2, cy + demi)
        guard x1 > x0 + 4, y1 > y0 + 4 else { return nil }
        var values: [Float] = []
        values.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                let i = y * w + x
                values.append(abs(4 * v[i] - v[i - 1] - v[i + 1] - v[i - w] - v[i + w]))
            }
        }
        values.sort()
        let nettete = Double(values[min(values.count - 1, Int(Double(values.count) * 0.95))])

        let b = blocTexture
        func bloc(_ x: Int, _ y: Int) -> Float {
            var somme: Float = 0
            for yy in y..<(y + b) {
                for xx in x..<(x + b) { somme += v[yy * w + xx] }
            }
            return somme / Float(b * b)
        }
        var ecarts: [Float] = []
        var by = y0
        while by + 2 * b <= y1 + 1 {
            var bx = x0
            while bx + 2 * b <= x1 + 1 {
                let ici = bloc(bx, by)
                ecarts.append(abs(bloc(bx + b, by) - ici) + abs(bloc(bx, by + b) - ici))
                bx += b
            }
            by += b
        }
        ecarts.sort()
        let texture = ecarts.isEmpty ? 0 : Double(ecarts[min(ecarts.count - 1, Int(Double(ecarts.count) * 0.75))])
        return MesureAutour(nettete: nettete, texture: texture)
    }

    /// Luminance (0 à 255) d'une image.
    static func luminance(_ image: CGImage) -> (Int, Int, [Float])? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var values = [Float](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            values[i] = 0.2126 * Float(pixels[i * 4]) + 0.7152 * Float(pixels[i * 4 + 1]) + 0.0722 * Float(pixels[i * 4 + 2])
        }
        return (width, height, values)
    }

    static func analyze(luminance v: [Float], width w: Int, height h: Int) -> DetailMeasurements {
        // Laplacien à 4 voisins.
        var laplacian = [Float](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                laplacian[i] = abs(4 * v[i] - v[i - 1] - v[i + 1] - v[i - w] - v[i + w])
            }
        }
        var zones: [Double] = []
        for zy in 0..<3 {
            for zx in 0..<3 {
                var values: [Float] = []
                for y in max(1, zy * h / 3)..<min(h - 1, (zy + 1) * h / 3) {
                    for x in max(1, zx * w / 3)..<min(w - 1, (zx + 1) * w / 3) {
                        values.append(laplacian[y * w + x])
                    }
                }
                values.sort()
                zones.append(values.isEmpty ? 0 : Double(values[min(values.count - 1, Int(Double(values.count) * 0.95))]))
            }
        }

        // Bruit : blocs de 16 × 16, classés par énergie de gradient ; les 10 % les plus calmes
        // sont des aplats, où le résidu est du bruit plutôt que du détail.
        struct Block { var energy: Double; var deviation: Double; var mean: Double }
        var blocks: [Block] = []
        let size = 16
        var by = 1
        while by + size < h - 1 {
            var bx = 1
            while bx + size < w - 1 {
                var energy = 0.0, sum = 0.0, sumSquares = 0.0, level = 0.0
                for y in by..<(by + size) {
                    for x in bx..<(bx + size) {
                        let i = y * w + x
                        let neighbours = v[i - w - 1] + v[i - w] + v[i - w + 1] + v[i - 1] + v[i] + v[i + 1] + v[i + w - 1] + v[i + w] + v[i + w + 1]
                        let residual = Double(v[i] - neighbours / 9)
                        sum += residual
                        sumSquares += residual * residual
                        level += Double(v[i])
                        energy += Double(abs(v[i + 1] - v[i - 1]) + abs(v[i + w] - v[i - w]))
                    }
                }
                let n = Double(size * size)
                let variance = max(0, sumSquares / n - (sum / n) * (sum / n))
                blocks.append(Block(energy: energy / n, deviation: variance.squareRoot(), mean: level / n))
                bx += size
            }
            by += size
        }
        func calmNoise(_ candidates: [Block]) -> Double? {
            guard candidates.count >= 5 else { return nil }
            let calm = candidates.sorted { $0.energy < $1.energy }.prefix(max(5, candidates.count / 10)).map(\.deviation).sorted()
            return calm[calm.count / 2]
        }
        // Les aplats saturés (ciel blanc, noirs bouchés) n'ont pas de bruit visible : écartés.
        let usable = blocks.filter { $0.mean > 8 && $0.mean < 247 }
        let noise = calmNoise(usable) ?? 0
        let shadowNoise = calmNoise(usable.filter { $0.mean < 64 })
        return DetailMeasurements(zones: zones, noise: noise, shadowNoise: shadowNoise, side: max(w, h))
    }
}
