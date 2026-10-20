import CoreGraphics
import Foundation

/// Modèle d'une couleur prélevée pour une plage de couleurs (`PointModels` d'un masque
/// `Mask/RangeMask` de Type 1) : trois valeurs de 0 à 1, puis la position du prélèvement.
/// `cr_range_mask` de Camera Raw calcule ses limites en Lab (`ComputeLabLimits`, `LabMin`,
/// `LabMax`). Étalonné le 17 octobre 2026 dans Lightroom Classic 15.6 sur une photo d'essai (ciel
/// bleu, érable rouge, feuillage, herbe), en faisant varier chaque valeur et en mesurant les zones
/// assombries : la première suit la clarté (L*/100), la deuxième l'axe vert-rouge et la troisième
/// l'axe bleu-jaune, neutres à 0,5 ; une échelle de 100 pour a* et b* (0,5 + a*/100) sélectionne
/// le ciel et l'érable chacun sans le reste (60 serre davantage les couleurs peu saturées, 128 à
/// 200 les couleurs saturées). Un modèle approché, mesuré sur le rendu sRGB : la sélection se
/// vérifie sur l'aperçu. Voir docs/SPEC.md, Plage de couleurs.
public enum ModeleCouleur {
    /// Lab D50 (adaptation de Bradford) d'une couleur sRGB de 0 à 255.
    public static func lab(_ r: Double, _ g: Double, _ b: Double) -> (l: Double, a: Double, b: Double) {
        func lineaire(_ c: Double) -> Double {
            let v = c / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let (rl, gl, bl) = (lineaire(r), lineaire(g), lineaire(b))
        // sRGB → XYZ D50 (matrice de Bradford, comme ColorSync et Camera Raw).
        let x = 0.4360747 * rl + 0.3850649 * gl + 0.1430804 * bl
        let y = 0.2225045 * rl + 0.7168786 * gl + 0.0606169 * bl
        let z = 0.0139322 * rl + 0.0971045 * gl + 0.7141733 * bl
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let (fx, fy, fz) = (f(x / 0.96422), f(y), f(z / 0.82521))
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// Échelle des axes a* et b* dans le modèle (0,5 = neutre).
    public static let echelleAB = 100.0

    /// Les trois valeurs du modèle : L*/100, puis a* et b* autour de 0,5.
    public static func modele(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
        let (l, a, bb) = lab(r, g, b)
        func borne(_ v: Double) -> Double { min(max(v, 0), 1) }
        return [borne(l / 100), borne(0.5 + a / echelleAB), borne(0.5 + bb / echelleAB)]
    }

    /// Couleur moyenne d'une zone carrée de l'image, centrée en (x, y) (0 à 1), de `cote` px.
    public static func moyenne(_ image: CGImage, x: Double, y: Double, cote: Int = 7) -> (Double, Double, Double)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, (0...1).contains(x), (0...1).contains(y),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let dessine = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard dessine else { return nil }
        let cx = min(w - 1, Int(x * Double(w))), cy = min(h - 1, Int(y * Double(h)))
        let demi = cote / 2
        var somme = (0.0, 0.0, 0.0), n = 0.0
        for py in max(0, cy - demi)...min(h - 1, cy + demi) {
            for px in max(0, cx - demi)...min(w - 1, cx + demi) {
                let i = (py * w + px) * 4
                somme.0 += Double(pixels[i]); somme.1 += Double(pixels[i + 1]); somme.2 += Double(pixels[i + 2])
                n += 1
            }
        }
        return n > 0 ? (somme.0 / n, somme.1 / n, somme.2 / n) : nil
    }
}
