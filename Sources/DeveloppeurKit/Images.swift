import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Découpe et assemblage des aperçus : zoom sur une zone, avant/après côte à côte, cadre proposé
/// dessiné sur l'image entière.
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

    /// Épaisseur du cadre proposé, en part du grand côté de l'image : gardée après le relevé du
    /// 21 octobre 2026 (cadre pointillé lisible réduit à 320 px, comme dans l'aperçu de la fenêtre).
    static let traitCadrePart = 0.004
    /// Épaisseur des lignes des tiers (le trait clair ; le liseré sombre dessous en fait le double),
    /// en part du grand côté. Relevé le 21 octobre 2026 : à 0,25 %, réduites à 320 px, les tiers
    /// étaient pâles sur un fond clair (le sable de la dune d'essai) ; 0,35 %, sans changer le
    /// liseré sombre (il donne déjà le contraste sur fond clair, le trait clair sur fond sombre).
    static let traitTiersPart = 0.0035

    /// L'image entière avec un cadre proposé (preview_settings avec crop, 1.3) : le hors-cadre
    /// assombri, les lignes des tiers dans le cadre, tournées avec lui, et le cadre en pointillés
    /// blancs sur un trait sombre. `coins` : haut gauche, haut droit, bas droit, bas gauche, de 0 à 1
    /// depuis le coin haut gauche (Composition.coins). Épaisseurs proportionnelles au grand côté
    /// (cadre `traitCadrePart`, tiers `traitTiersPart`), pour rester lisibles réduites à 320 px dans
    /// la fenêtre Claude.
    public static func cadrePropose(_ source: CGImage, coins: [CGPoint]) -> Data? {
        guard coins.count == 4 else { return nil }
        let image = scaled(source, maxSide: maxSide)
        let width = image.width, height = image.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Le repère de CoreGraphics part du bas.
        let p = coins.map { CGPoint(x: Double($0.x) * Double(width), y: (1 - Double($0.y)) * Double(height)) }
        let grand = Double(max(width, height))

        // Hors-cadre assombri : le rectangle de l'image moins le cadre (pair-impair).
        context.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        context.addLines(between: p)
        context.closePath()
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
        context.fillPath(using: .evenOdd)

        func entre(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: Double(a.x) + (Double(b.x) - Double(a.x)) * t, y: Double(a.y) + (Double(b.y) - Double(a.y)) * t)
        }
        func tracer(_ segments: [(CGPoint, CGPoint)]) {
            for (a, b) in segments {
                context.move(to: a)
                context.addLine(to: b)
            }
            context.strokePath()
        }
        // Les tiers : deux lignes dans chaque sens, d'un côté du cadre à l'autre.
        var tiers: [(CGPoint, CGPoint)] = []
        for t in [1.0 / 3, 2.0 / 3] {
            tiers.append((entre(p[0], p[1], t), entre(p[3], p[2], t)))
            tiers.append((entre(p[0], p[3], t), entre(p[1], p[2], t)))
        }
        let traitTiers = max(1.5, grand * traitTiersPart)
        context.setLineCap(.butt)
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45))
        context.setLineWidth(traitTiers * 2)
        tracer(tiers)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        context.setLineWidth(traitTiers)
        tracer(tiers)

        // Le cadre : un trait sombre continu, puis les pointillés blancs (tiret ≈ côté / 40).
        let traitCadre = max(2, grand * traitCadrePart)
        let cote = max(hypot(Double(p[1].x - p[0].x), Double(p[1].y - p[0].y)), hypot(Double(p[3].x - p[0].x), Double(p[3].y - p[0].y)))
        let tiret = max(4, cote / 40)
        context.setLineJoin(.miter)
        context.addLines(between: p)
        context.closePath()
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        context.setLineWidth(traitCadre * 2)
        context.strokePath()
        context.addLines(between: p)
        context.closePath()
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(traitCadre)
        context.setLineDash(phase: 0, lengths: [tiret, tiret])
        context.strokePath()
        guard let dessinee = context.makeImage() else { return nil }
        return jpeg(dessinee)
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
