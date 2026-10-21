import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Découpe et assemblage des aperçus : zoom sur une zone, avant/après côte à côte.
public enum PreviewImages {
    /// Grand côté maximal d'une image envoyée à Claude (au-delà, Claude la réduit).
    public static let maxSide = 1600

    public static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    public static func jpeg(_ image: CGImage, quality: Double = 0.88) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Réduit une image pour que son grand côté ne dépasse pas `maxSide`.
    public static func scaled(_ image: CGImage, maxSide: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxSide else { return image }
        let factor = Double(maxSide) / Double(longest)
        let width = max(1, Int((Double(image.width) * factor).rounded()))
        let height = max(1, Int((Double(image.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Zone d'une image en pleine résolution : `region` en fractions (x, y depuis le coin haut
    /// gauche). Renvoie le JPEG, ses dimensions et le zoom obtenu (100 % = un pixel pour un pixel).
    public static func crop(_ data: Data, region: CGRect, maxSide: Int = maxSide) -> (data: Data, width: Int, height: Int, zoom: Int)? {
        guard let full = image(data) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        let rect = CGRect(x: region.minX * Double(full.width), y: region.minY * Double(full.height),
                          width: region.width * Double(full.width), height: region.height * Double(full.height))
            .integral.intersection(bounds)
        guard rect.width >= 8, rect.height >= 8, let piece = full.cropping(to: rect) else { return nil }
        let result = scaled(piece, maxSide: maxSide)
        guard let jpeg = jpeg(result, quality: 0.9) else { return nil }
        let zoom = Int((Double(result.width) / Double(piece.width) * 100).rounded())
        return (jpeg, result.width, result.height, zoom)
    }

    /// L'image avec un carré autour d'un point (de 0 à 1 depuis le coin haut gauche) : le point de
    /// mise au point de l'appareil, vert, ou rouge si l'appareil l'a signalé manqué, comme le carré
    /// AF d'un boîtier. Côté du carré : 6 % du petit côté ; un liseré sombre le garde visible sur un
    /// fond clair.
    public static func marquerPoint(_ source: CGImage, _ point: CGPoint, manque: Bool) -> Data? {
        let image = scaled(source, maxSide: maxSide)
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let cote = max(16, Double(min(width, height)) * 0.06)
        let trait = max(2, cote / 14)
        // Le repère de CoreGraphics part du bas.
        let cx = Double(point.x) * Double(width), cy = (1 - Double(point.y)) * Double(height)
        let carre = CGRect(x: cx - cote / 2, y: cy - cote / 2, width: cote, height: cote)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        context.setLineWidth(trait + 2)
        context.stroke(carre)
        context.setStrokeColor(manque ? CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1) : CGColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1))
        context.setLineWidth(trait)
        context.stroke(carre)
        guard let marquee = context.makeImage() else { return nil }
        return jpeg(marquee)
    }

    /// Deux images côte à côte, à la même hauteur, séparées d'une bande blanche.
    public static func sideBySide(_ left: Data, _ right: Data, maxSide: Int = maxSide) -> Data? {
        guard let first = image(left), let second = image(right) else { return nil }
        let height = min(first.height, second.height)
        let widthOf = { (image: CGImage) in Int((Double(image.width) * Double(height) / Double(image.height)).rounded()) }
        let gap = max(4, height / 100)
        let width = widthOf(first) + gap + widthOf(second)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(first, in: CGRect(x: 0, y: 0, width: widthOf(first), height: height))
        context.draw(second, in: CGRect(x: widthOf(first) + gap, y: 0, width: widthOf(second), height: height))
        guard let combined = context.makeImage() else { return nil }
        return jpeg(scaled(combined, maxSide: maxSide))
    }

    /// Colonnes d'une planche contact de `nombre` vignettes : 2 jusqu'à 4, 3 jusqu'à 9, 4 jusqu'à
    /// 16, 5 jusqu'à 25, puis 6 (30 vignettes en 6 × 5).
    public static func colonnesPlanche(_ nombre: Int) -> Int {
        nombre <= 4 ? 2 : nombre <= 9 ? 3 : nombre <= 16 ? 4 : nombre <= 25 ? 5 : 6
    }

    /// Planche contact : les vignettes en grille, sur fond gris foncé comme la grille de Lightroom,
    /// chacune dans une case 3:2, numérotée (de `premierNumero` à la suite, dans l'ordre donné : les
    /// numéros continuent d'une planche à l'autre) et légendée de son nom de fichier (coupé au
    /// milieu s'il est trop long). Grand côté au plus `maxSide`. Une vignette absente laisse sa
    /// case vide, numéro et nom compris.
    public static func planche(_ vignettes: [(image: CGImage?, legende: String)], colonnes demandees: Int? = nil,
                               premierNumero: Int = 1, maxSide: Int = maxSide) -> Data? {
        guard !vignettes.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let colonnes = max(1, min(demandees ?? colonnesPlanche(vignettes.count), vignettes.count))
        let lignes = (vignettes.count + colonnes - 1) / colonnes
        // Dessinée à 1600 px de large, puis réduite si elle dépasse maxSide en hauteur.
        let largeur = 1600.0
        let marge = 16.0
        let caseL = (largeur - marge * Double(colonnes + 1)) / Double(colonnes)
        let imageH = caseL * 2 / 3
        let texteH = max(20, (caseL * 0.08).rounded())
        let caseH = imageH + texteH
        let hauteur = Double(lignes) * caseH + marge * Double(lignes + 1)
        guard let context = CGContext(data: nil, width: Int(largeur), height: Int(hauteur), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(red: 0.13, green: 0.13, blue: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: largeur, height: hauteur))
        let blanc = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let gris = CGColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1)
        for (index, vignette) in vignettes.enumerated() {
            let colonne = index % colonnes, ligne = index / colonnes
            let x = marge + Double(colonne) * (caseL + marge)
            // Repère de CoreGraphics : depuis le bas.
            let haut = hauteur - marge - Double(ligne) * (caseH + marge)
            let zone = CGRect(x: x, y: haut - imageH, width: caseL, height: imageH)
            context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(zone)
            if let image = vignette.image {
                let echelle = min(zone.width / Double(image.width), zone.height / Double(image.height))
                let w = Double(image.width) * echelle, h = Double(image.height) * echelle
                context.draw(image, in: CGRect(x: zone.midX - w / 2, y: zone.midY - h / 2, width: w, height: h))
            }
            // Numéro dans une pastille, en haut à gauche de la case, élargie pour deux ou trois chiffres.
            let numero = premierNumero + index
            let tailleNumero = max(18, (caseL * 0.07).rounded())
            let pastille = CGRect(x: x + 6, y: haut - 6 - tailleNumero * 1.5,
                                  width: tailleNumero * (numero >= 100 ? 2.7 : numero >= 10 ? 2.1 : 1.5), height: tailleNumero * 1.5)
            context.setFillColor(CGColor(red: 0.85, green: 0.33, blue: 0.1, alpha: 0.95))
            context.addPath(CGPath(roundedRect: pastille, cornerWidth: tailleNumero * 0.4, cornerHeight: tailleNumero * 0.4, transform: nil))
            context.fillPath()
            texte("\(numero)", dans: context, centreX: pastille.midX, baseY: pastille.minY + tailleNumero * 0.38,
                  taille: tailleNumero, gras: true, couleur: blanc, largeurMax: pastille.width)
            texte(vignette.legende, dans: context, centreX: x + caseL / 2, baseY: haut - imageH - texteH * 0.78,
                  taille: texteH * 0.62, gras: false, couleur: gris, largeurMax: caseL - 8)
        }
        guard let image = context.makeImage() else { return nil }
        return jpeg(scaled(image, maxSide: maxSide), quality: 0.85)
    }

    /// Une ligne de texte centrée, coupée au milieu (« … ») si elle dépasse `largeurMax`.
    static func texte(_ chaine: String, dans context: CGContext, centreX: Double, baseY: Double, taille: Double,
                      gras: Bool, couleur: CGColor, largeurMax: Double) {
        let police = CTFontCreateWithName((gras ? "Helvetica-Bold" : "Helvetica") as CFString, taille, nil)
        let attributs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): police,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): couleur,
        ]
        var ligne = CTLineCreateWithAttributedString(NSAttributedString(string: chaine, attributes: attributs))
        if CTLineGetTypographicBounds(ligne, nil, nil, nil) > largeurMax {
            let points = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributs))
            ligne = CTLineCreateTruncatedLine(ligne, largeurMax, .middle, points) ?? ligne
        }
        let largeur = CTLineGetTypographicBounds(ligne, nil, nil, nil)
        context.textPosition = CGPoint(x: centreX - largeur / 2, y: baseY)
        CTLineDraw(ligne, context)
    }
}
