import CoreGraphics
import Foundation
import ImageIO

/// Mesures objectives d'un aperçu rendu par Lightroom (JPEG sRGB, après développement) :
/// luminosité en L* (0 noir, 100 blanc), écrêtage, contraste et couleur. Calculées sur une
/// réduction de l'aperçu, pour que Claude appuie son diagnostic sur des chiffres.
public struct PhotoMeasurements: Equatable {
    public var meanL: Double
    /// Centiles de L* : 1, 5, 25, 50, 75, 95 et 99.
    public var percentilesL: [Int: Double]
    /// Part des pixels par tranche de 10 en L*, en %.
    public var histogramL: [Double]
    /// Part des pixels dont au moins une composante est saturée (≥ 254), en %.
    public var clippedHighlights: Double
    /// Part des pixels blancs purs (trois composantes ≥ 254), en %.
    public var pureWhite: Double
    /// Part des pixels bouchés (trois composantes ≤ 2), en %.
    public var crushedShadows: Double
    /// Part des pixels saturés dans chaque canal (rouge, vert, bleu ≥ 254), en % : un rouge ou un
    /// ciel peut être brûlé dans un seul canal sans que la luminance le montre.
    public var clippedChannels: [Double]
    public var meanChroma: Double
    /// Part des pixels très saturés (C* > `chromaTresSaturee`), en %.
    public var saturatedShare: Double
    /// Moyenne de a* et b* sur les tons presque neutres (C* < 15), et leur part en %.
    public var neutralA: Double
    public var neutralB: Double
    public var neutralShare: Double
    public var pixelCount: Int

    public var medianL: Double { percentilesL[50] ?? meanL }
    public var contrast: Double { (percentilesL[95] ?? 0) - (percentilesL[5] ?? 0) }

    /// Part des tons neutres (en %) en dessous de laquelle la dominante ne se juge pas : repris par
    /// `Measurements.compare` et le bilan de view_photo.
    static let partNeutreMin = 3.0
    /// Moyenne de a* ou b* des tons neutres au-delà de laquelle la dominante est légère, puis nette.
    static let dominanteLegere = 2.0, dominanteNette = 6.0
    /// C* au-delà duquel un pixel compte comme très saturé (`saturatedShare`).
    static let chromaTresSaturee = 60.0

    /// Lecture de la dominante, d'après les tons neutres.
    public var castReading: String {
        guard neutralShare >= Self.partNeutreMin else { return "trop peu de tons neutres pour juger la dominante" }
        let legere = Self.dominanteLegere, nette = Self.dominanteNette
        var parts: [String] = []
        if neutralB > legere { parts.append(neutralB > nette ? "nettement chaude (jaune)" : "légèrement chaude (jaune)") }
        if neutralB < -legere { parts.append(neutralB < -nette ? "nettement froide (bleue)" : "légèrement froide (bleue)") }
        if neutralA > legere { parts.append(neutralA > nette ? "nettement magenta" : "légèrement magenta") }
        if neutralA < -legere { parts.append(neutralA < -nette ? "nettement verte" : "légèrement verte") }
        return parts.isEmpty ? "neutre" : "dominante " + parts.joined(separator: " et ")
    }

    public var json: JSONValue {
        func r(_ value: Double) -> JSONValue { .number((value * 10).rounded() / 10) }
        var luminosity: [String: JSONValue] = ["moyenne": r(meanL)]
        for (centile, value) in percentilesL { luminosity[centile == 50 ? "mediane" : "p\(centile)"] = r(value) }
        return [
            "luminosite_L": .object(luminosity),
            "histogramme_L_pct": .array(histogramL.map(r)),
            "contraste_p95_moins_p5": r(contrast),
            "ecretage_pct": [
                "hautes_lumieres": r(clippedHighlights),
                "blanc_pur": r(pureWhite),
                "ombres_bouchees": r(crushedShadows),
                "par_canal": ["rouge": r(clippedChannels[0]), "vert": r(clippedChannels[1]), "bleu": r(clippedChannels[2])],
            ],
            "couleur": [
                "chroma_moyenne": r(meanChroma),
                "tres_saturee_pct": r(saturatedShare),
                "tons_neutres": [
                    "part_pct": r(neutralShare),
                    "a": r(neutralA),
                    "b": r(neutralB),
                    "lecture": .string(castReading),
                ],
            ],
            "base": .string("Aperçu sRGB rendu par Lightroom, réduit à \(Measurements.maxSide) px. L* : 0 noir, 100 blanc ; histogramme par tranches de 10. a* : vert (−) à magenta (+) ; b* : bleu (−) à jaune (+)."),
        ]
    }
}

public enum Measurements {
    /// Grand côté de la réduction analysée.
    public static let maxSide = 512

    /// Écart de chroma moyenne (C*) sous lequel un changement de saturation ne se voit pas :
    /// `compare` (analyze_photos) et le bilan de view_photo.
    static let seuilChroma = 3.0

    /// Mesure un JPEG (ou toute image lisible par ImageIO). Nil si l'image est illisible.
    public static func analyze(_ data: Data) -> PhotoMeasurements? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return analyze(image)
    }

    /// Mesure une image déjà décodée, réduite à `maxSide` px comme un JPEG lu par `analyze(_:)`.
    public static func analyzeScaled(_ image: CGImage) -> PhotoMeasurements? {
        analyze(PreviewImages.scaled(image, maxSide: maxSide))
    }

    /// Dominante des tons neutres suivie d'une mesure à l'autre : les pixels presque neutres de la
    /// première mesure (`masque` nil) restent ceux des suivantes. Une sélection refaite à chaque fois
    /// fausse la mesure quand la balance change : les pixels qui se colorent en sortent (constaté le
    /// 17 octobre 2026 sur un RAW d'essai : +600 K laissaient b* à 12,2 → 12,3, la part neutre
    /// tombant de 40 % à 8 % ; suivis, ils donnaient 12,2 → 16,7). Nil si l'image est illisible ou
    /// si la taille a changé.
    public struct NeutresSuivis {
        public var a: Double
        public var b: Double
        public var part: Double
        public var masque: [Bool]
    }

    public static func neutres(_ data: Data, masque: [Bool]? = nil) -> NeutresSuivis? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let pixels = rgba(image) else { return nil }
        return neutres(pixels: pixels, count: image.width * image.height, masque: masque)
    }

    /// Les mêmes tons neutres sur une image déjà décodée (view_photo), réduite comme par
    /// `analyzeScaled` : deux vues de même cadre ont alors le même nombre de pixels, et le masque
    /// de l'une sert à l'autre (bilan d'une passe à l'autre).
    public static func neutres(_ image: CGImage, masque: [Bool]? = nil) -> NeutresSuivis? {
        let reduite = PreviewImages.scaled(image, maxSide: maxSide)
        guard let pixels = rgba(reduite) else { return nil }
        return neutres(pixels: pixels, count: reduite.width * reduite.height, masque: masque)
    }

    private static func neutres(pixels: [UInt8], count: Int, masque: [Bool]?) -> NeutresSuivis? {
        guard count > 0, pixels.count >= count * 4 else { return nil }
        if let masque, masque.count != count { return nil }
        var choisis = masque ?? [Bool](repeating: false, count: count)
        var sommeA = 0.0, sommeB = 0.0, nombre = 0
        for i in 0..<count {
            let (l, a, b) = lab(pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2])
            if masque == nil {
                choisis[i] = (a * a + b * b).squareRoot() < 15 && l > 15 && l < 95
            }
            if choisis[i] {
                sommeA += a
                sommeB += b
                nombre += 1
            }
        }
        guard nombre > 0 else { return NeutresSuivis(a: 0, b: 0, part: 0, masque: choisis) }
        return NeutresSuivis(a: sommeA / Double(nombre), b: sommeB / Double(nombre), part: Double(nombre) * 100 / Double(count), masque: choisis)
    }

    static func rgba(_ image: CGImage) -> [UInt8]? {
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
        return drawn ? pixels : nil
    }

    public static func analyze(_ image: CGImage) -> PhotoMeasurements? {
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
        return analyze(rgba: pixels, count: width * height)
    }

    /// sRGB 8 bits → valeur linéaire.
    private static let linear: [Double] = (0...255).map { value in
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func f(_ t: Double) -> Double {
        t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116.0
    }

    /// L*a*b* (D65) d'un pixel sRGB.
    static func lab(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> (l: Double, a: Double, b: Double) {
        let r = linear[Int(red)], g = linear[Int(green)], b = linear[Int(blue)]
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Mesures de pixels RGBA 8 bits (l'alpha est ignoré).
    static func analyze(rgba pixels: [UInt8], count: Int) -> PhotoMeasurements? {
        guard count > 0, pixels.count >= count * 4 else { return nil }
        var fine = [Int](repeating: 0, count: 1001)
        var bins = [Int](repeating: 0, count: 10)
        var sumL = 0.0, sumChroma = 0.0, sumA = 0.0, sumB = 0.0
        var clipped = 0, white = 0, crushed = 0, saturated = 0, neutral = 0
        var channels = [0, 0, 0]
        for i in 0..<count {
            let red = pixels[i * 4], green = pixels[i * 4 + 1], blue = pixels[i * 4 + 2]
            let high = max(red, green, blue), low = min(red, green, blue)
            if high >= 254 { clipped += 1 }
            if red >= 254 { channels[0] += 1 }
            if green >= 254 { channels[1] += 1 }
            if blue >= 254 { channels[2] += 1 }
            if low >= 254 { white += 1 }
            if high <= 2 { crushed += 1 }
            let (l, a, b) = lab(red, green, blue)
            let lightness = min(max(l, 0), 100)
            let chroma = (a * a + b * b).squareRoot()
            sumL += lightness
            sumChroma += chroma
            fine[Int((lightness * 10).rounded())] += 1
            bins[min(Int(lightness / 10), 9)] += 1
            if chroma > PhotoMeasurements.chromaTresSaturee { saturated += 1 }
            if chroma < 15, lightness > 15, lightness < 95 {
                neutral += 1
                sumA += a
                sumB += b
            }
        }
        let total = Double(count)
        var percentiles: [Int: Double] = [:]
        for centile in [1, 5, 25, 50, 75, 95, 99] {
            let target = total * Double(centile) / 100
            var cumulative = 0
            for (index, n) in fine.enumerated() {
                cumulative += n
                if Double(cumulative) >= target {
                    percentiles[centile] = Double(index) / 10
                    break
                }
            }
        }
        return PhotoMeasurements(
            meanL: sumL / total,
            percentilesL: percentiles,
            histogramL: bins.map { Double($0) / total * 100 },
            clippedHighlights: Double(clipped) / total * 100,
            pureWhite: Double(white) / total * 100,
            crushedShadows: Double(crushed) / total * 100,
            clippedChannels: channels.map { Double($0) / total * 100 },
            meanChroma: sumChroma / total,
            saturatedShare: Double(saturated) / total * 100,
            neutralA: neutral > 0 ? sumA / Double(neutral) : 0,
            neutralB: neutral > 0 ? sumB / Double(neutral) : 0,
            neutralShare: Double(neutral) / total * 100,
            pixelCount: count)
    }

    /// Luminance relative (0 à 1) d'une valeur de L*.
    static func luminance(_ l: Double) -> Double {
        let fy = (l + 16) / 116
        return fy > 0.206893 ? fy * fy * fy : (fy - 16.0 / 116.0) / 7.787
    }

    /// Écart d'exposition de `avant` à `apres`, en IL : log2 du rapport des luminances médianes,
    /// borné à ±3 (non arrondi). Le même pour analyze_photos et le bilan de view_photo.
    static func ecartIL(_ avant: PhotoMeasurements, _ apres: PhotoMeasurements) -> Double {
        let y0 = max(luminance(avant.medianL), 0.0005), y1 = max(luminance(apres.medianL), 0.0005)
        return min(max(log2(y1 / y0), -3), 3)
    }

    /// Écarts d'une photo avec une photo de référence, et ce qu'il faudrait changer pour s'en
    /// rapprocher. Seule l'exposition se chiffre de façon fiable (en IL, par la luminance
    /// médiane) ; le reste donne un sens et un ordre de grandeur, à vérifier à l'œil. Seuils de
    /// visibilité : ceux de match_series (`ToolHandler.seuilExposition`, `seuilDominante`,
    /// `seuilContraste`), et `seuilChroma`.
    public static func compare(_ photo: PhotoMeasurements, toReference reference: PhotoMeasurements) -> JSONValue {
        func r(_ value: Double, _ step: Double = 0.1) -> JSONValue { .number((value / step).rounded() * step) }
        let exposure = ecartIL(photo, reference)
        let deltaA = reference.neutralA - photo.neutralA
        let deltaB = reference.neutralB - photo.neutralB
        let deltaContrast = reference.contrast - photo.contrast
        let deltaChroma = reference.meanChroma - photo.meanChroma

        var hints: [JSONValue] = []
        if abs(exposure) >= ToolHandler.seuilExposition {
            hints.append(.string("Exposure2012 : environ \(exposure > 0 ? "+" : "")\(DevelopCatalogue.format((exposure * 20).rounded() / 20)) IL (en relatif)"))
        }
        if photo.neutralShare >= PhotoMeasurements.partNeutreMin, reference.neutralShare >= PhotoMeasurements.partNeutreMin {
            if abs(deltaB) >= ToolHandler.seuilDominante { hints.append(.string(deltaB > 0 ? "Temperature : réchauffer (vers le jaune)" : "Temperature : refroidir (vers le bleu)")) }
            if abs(deltaA) >= ToolHandler.seuilDominante { hints.append(.string(deltaA > 0 ? "Tint : vers le magenta" : "Tint : vers le vert")) }
        }
        if abs(deltaContrast) >= ToolHandler.seuilContraste { hints.append(.string(deltaContrast > 0 ? "Contraste : plus de contraste (ou Blancs + / Noirs −)" : "Contraste : moins de contraste")) }
        if abs(deltaChroma) >= seuilChroma { hints.append(.string(deltaChroma > 0 ? "Couleur : plus saturée (Vibrance +)" : "Couleur : moins saturée (Vibrance −)")) }
        if hints.isEmpty { hints.append(.string("Déjà proche de la référence.")) }

        return [
            "exposition_IL": r(exposure, 0.05),
            "mediane_L": r(reference.medianL - photo.medianL),
            "contraste": r(deltaContrast),
            "dominante_a": r(deltaA),
            "dominante_b": r(deltaB),
            "chroma_moyenne": r(deltaChroma),
            "indications": .array(hints),
            "base": "Écarts « référence moins photo » ; seule l'exposition est chiffrée, le reste indique un sens à vérifier sur l'aperçu.",
        ]
    }
}
