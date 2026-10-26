import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// Le dessin des graphiques du Suivi (correctif 1.3.7), en PNG 2x, par CoreGraphics comme
/// `PreviewImages` : Lightroom ne trace pas de graphique, la fenêtre Suivi montre ces images
/// (f:picture avec width et height) et pose ses calques sur les créneaux que rend `--graphiques`.
/// Sobre : le fond des fenêtres (fondDroite), des barres arrondies au bout, une grille discrète (la
/// moitié et le haut de l'échelle, en pointillés), la ligne de base au filet, les libellés en
/// français dessous ou à gauche (réduits de 10 à 7 points, la même taille pour tout le graphique,
/// puis coupés « … »), les valeurs au-dessus
/// ou dans la colonne de droite (aucune pour une barre à 0). Le titre et la note ne sont pas
/// dessinés : la fenêtre les écrit (`titre`, `note` de la sortie). Les rectangles des barres sont
/// ceux de la sortie (`Suivi.placer`), au point près.
extension Suivi {
    /// Pixels par point : les images se montrent nettes sur un écran Retina.
    static let echelleDessin = 2
    /// Le rayon du bout arrondi d'une barre, en points (moins pour une barre plus fine).
    static let rayonBarre = 3.0
    static let tailleLibelle = 10.0, tailleLibelleMin = 7.0, tailleValeur = 9.0, tailleVide = 11.0

    static func police(_ taille: Double, grasse: Bool = false) -> CTFont {
        CTFontCreateUIFontForLanguage(grasse ? .emphasizedSystem : .system, taille, nil)
            ?? CTFontCreateWithName((grasse ? "Helvetica-Bold" : "Helvetica") as CFString, taille, nil)
    }

    static func ligne(_ texte: String, taille: Double, couleur: CGColor, grasse: Bool = false) -> CTLine {
        let attributs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): police(taille, grasse: grasse),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): couleur,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: texte, attributes: attributs))
    }

    static func largeur(_ ligne: CTLine) -> Double { CTLineGetTypographicBounds(ligne, nil, nil, nil) }

    /// La taille des libellés d'un graphique, la même pour tous (des tailles mêlées font désordre) :
    /// de `tailleLibelle` à `tailleLibelleMin` points, la plus grande où tiennent tous ceux qui
    /// tiennent à la plus petite ; les autres seront coupés « … » (`libelleAjuste`).
    static func tailleDesLibelles(_ libelles: [(texte: String, largeurMax: Double)]) -> Double {
        let noir = CGColor(gray: 0, alpha: 1)
        func tient(_ libelle: (texte: String, largeurMax: Double), _ taille: Double) -> Bool {
            largeur(ligne(libelle.texte, taille: taille, couleur: noir)) <= libelle.largeurMax
        }
        let tenables = libelles.filter { tient($0, tailleLibelleMin) }
        var taille = tailleLibelle
        while taille > tailleLibelleMin, !tenables.allSatisfy({ tient($0, taille) }) { taille -= 1 }
        return taille
    }

    /// Un libellé à sa taille, coupé « … » s'il ne tient pas dans `largeurMax`.
    static func libelleAjuste(_ texte: String, largeurMax: Double, taille: Double, couleur: CGColor) -> CTLine {
        let entiere = ligne(texte, taille: taille, couleur: couleur)
        guard largeur(entiere) > largeurMax else { return entiere }
        let points = ligne("…", taille: taille, couleur: couleur)
        return CTLineCreateTruncatedLine(entiere, max(1, largeurMax), .end, points) ?? entiere
    }

    /// Dessine une ligne de texte : `x` son bord gauche, `milieuY` le milieu de ses capitales, dans
    /// le repère de CoreGraphics (en points, depuis le bas).
    static func ecrire(_ ligne: CTLine, x: Double, milieuY: Double, dans contexte: CGContext) {
        var ascendante: CGFloat = 0, descendante: CGFloat = 0
        CTLineGetTypographicBounds(ligne, &ascendante, &descendante, nil)
        contexte.textPosition = CGPoint(x: x, y: milieuY - (Double(ascendante) - Double(descendante)) / 2)
        CTLineDraw(ligne, contexte)
    }

    /// Une barre pleine, arrondie au bout (en haut d'une barre verticale, à droite d'une horizontale),
    /// carrée à sa base.
    static func barre(_ rect: CGRect, verticale: Bool, couleur: CGColor, dans contexte: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let rayon = min(rayonBarre, Double(rect.width) / 2, Double(rect.height) / 2)
        contexte.setFillColor(couleur)
        contexte.addPath(CGPath(roundedRect: rect, cornerWidth: rayon, cornerHeight: rayon, transform: nil))
        contexte.fillPath()
        let base = verticale
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rayon, Double(rect.height)))
            : CGRect(x: rect.minX, y: rect.minY, width: min(rayon, Double(rect.width)), height: rect.height)
        contexte.fill(base)
    }

    /// Dessine le graphique et l'écrit en PNG de 2 × largeur par 2 × hauteur pixels ; faux si le
    /// dessin ou l'écriture échoue.
    static func dessiner(_ g: Graphique, couleurs: [String: String], vers fichier: URL) -> Bool {
        func couleur(_ cle: String) -> CGColor { couleurs[cle].flatMap(couleurHex) ?? CGColor(gray: 0.5, alpha: 1) }
        let L = Double(g.largeur), H = Double(g.hauteur)
        guard let espace = CGColorSpace(name: CGColorSpace.sRGB),
              let contexte = CGContext(data: nil, width: g.largeur * echelleDessin, height: g.hauteur * echelleDessin, bitsPerComponent: 8,
                                       bytesPerRow: 0, space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        contexte.scaleBy(x: CGFloat(echelleDessin), y: CGFloat(echelleDessin))
        contexte.setShouldAntialias(true)
        contexte.textMatrix = .identity
        // Le repère des rectangles part du haut ; celui de CoreGraphics, du bas.
        func cg(_ r: Rect) -> CGRect { CGRect(x: Double(r.x), y: H - Double(r.y) - Double(r.hauteur), width: Double(r.largeur), height: Double(r.hauteur)) }
        func trait(_ de: CGPoint, _ a: CGPoint, epaisseur: Double, pointilles: Bool) {
            contexte.saveGState()
            contexte.setStrokeColor(couleur("filet"))
            contexte.setLineWidth(epaisseur)
            if pointilles { contexte.setLineDash(phase: 0, lengths: [2, 2]) }
            contexte.move(to: de)
            contexte.addLine(to: a)
            contexte.strokePath()
            contexte.restoreGState()
        }

        contexte.setFillColor(couleur("fond"))
        contexte.fill(CGRect(x: 0, y: 0, width: L, height: H))
        let texte = couleur("texte"), gris = couleur("gris")

        switch g.definition.orientation {
        case .verticale:
            let T = Double(traceVertical(g.hauteur))
            let base = H - (16 + T)
            if g.echelle > 0 {
                for part in [0.5, 1.0] {
                    let y = base + T * part
                    trait(CGPoint(x: 8, y: y), CGPoint(x: L - 8, y: y), epaisseur: 0.5, pointilles: true)
                }
            }
            trait(CGPoint(x: 8, y: base), CGPoint(x: L - 8, y: base), epaisseur: 1, pointilles: false)
            let taille = tailleDesLibelles(g.barres.map { ($0.libelle, Double($0.zone.largeur) - 2) })
            for b in g.barres where b.zone.largeur > 0 {
                let zone = cg(b.zone)
                barre(cg(b.rect), verticale: true, couleur: couleur(b.couleur), dans: contexte)
                if b.valeur > 0 {
                    let valeur = ligne(b.texte, taille: tailleValeur, couleur: gris)
                    ecrire(valeur, x: Double(zone.midX) - largeur(valeur) / 2, milieuY: H - Double(b.rect.y) + 7, dans: contexte)
                }
                let libelle = libelleAjuste(b.libelle, largeurMax: Double(zone.width) - 2, taille: taille, couleur: texte)
                ecrire(libelle, x: Double(zone.midX) - largeur(libelle) / 2, milieuY: base - 10, dans: contexte)
            }
        case .horizontale:
            let colonne = Double(colonneLibelles(g.largeur))
            let x0 = colonne + 4, B = L - 52 - x0
            if g.echelle > 0 {
                for part in [0.5, 1.0] {
                    let x = x0 + B * part
                    trait(CGPoint(x: x, y: 4), CGPoint(x: x, y: H - 4), epaisseur: 0.5, pointilles: true)
                }
            }
            trait(CGPoint(x: x0, y: 4), CGPoint(x: x0, y: H - 4), epaisseur: 1, pointilles: false)
            let taille = tailleDesLibelles(g.barres.map { ($0.libelle, colonne - 6) })
            for b in g.barres where b.zone.hauteur > 0 {
                let zone = cg(b.zone)
                barre(cg(b.rect), verticale: false, couleur: couleur(b.couleur), dans: contexte)
                let libelle = libelleAjuste(b.libelle, largeurMax: colonne - 6, taille: taille, couleur: texte)
                ecrire(libelle, x: 4, milieuY: Double(zone.midY), dans: contexte)
                if b.valeur > 0 {
                    let valeur = ligne(b.texte, taille: tailleValeur, couleur: gris)
                    ecrire(valeur, x: L - 46, milieuY: Double(zone.midY), dans: contexte)
                }
            }
        }
        if g.vide {
            let message = ligne(g.texteVide, taille: tailleVide, couleur: gris)
            ecrire(message, x: L / 2 - largeur(message) / 2, milieuY: H / 2, dans: contexte)
        }

        guard let image = contexte.makeImage(),
              let destination = CGImageDestinationCreateWithURL(fichier as CFURL, "public.png" as CFString, 1, nil) else { return false }
        let dpi = Double(72 * echelleDessin)
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
