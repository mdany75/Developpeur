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

    /// Seuils relevés sur des aperçus de 1024 px : une photo nette donne de 45 à 150 selon son
    /// contenu, un léger flou (gaussien de rayon 1,5 px) de 12 à 26, un flou marqué moins de 6.
    public var sharpnessReading: String {
        switch sharpest {
        case ..<15: return "floue probable : aucune zone nette"
        case ..<35: return "douce : peu de détails nets (flou léger, ou sujet sans texture)"
        default: return "nette \(sharpestZone)"
        }
    }

    /// Au-delà, le bruit est fort (relevé à 1024 px) : la photo se débruite, et se note après.
    static let bruitFort = 1.5

    /// Seuils relevés à 1024 px : une image propre donne de 0,2 à 0,5, des ombres relevées vers 1.
    public var noiseReading: String {
        let level = max(noise, shadowNoise ?? 0)
        switch level {
        case ..<0.6: return "faible"
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
            "base_detail": .string("Luminance à \(side) px de grand côté. Netteté : 95e centile du laplacien par zone (moins de 15 : flou probable ; plus de 35 : net). Bruit : écart type du résidu dans les aplats, en niveaux sur 255 (moins de 0,6 : faible)."),
        ]
    }
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
        return Double(values[min(values.count - 1, Int(Double(values.count) * 0.95))])
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
