// images-vides.swift — dessine l'image « aucun aperçu » de la fenêtre Claude, au cadre d'aperçu,
// au fond des vignettes (2B2B2B) : le carré de 320 de Dispositions.TAILLES (vide-320.png, en PNG à
// 72 ppp), gardé jusqu'au lot B3 de la fenêtre B, et le cadre 3:2 de la fenêtre B, 330 × 220 points
// (vide-330x220.png), en 2x : 660 × 440 pixels à 144 ppp, que le SDK de Lightroom affiche à sa
// taille en points, comme les images de scripts/images-fenetre.swift. Les essais de la fenêtre
// vérifient qu'elles existent, à ces dimensions.
//
// Usage : swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin

import AppKit

let dossier = CommandLine.arguments.dropFirst().first ?? "."

// Largeur et hauteur de chaque cadre en points, et son échelle (pixels par point) ; un carré garde
// son nom d'origine (vide-320.png).
let cadres: [(Int, Int, Int)] = [
    (320, 320, 1),     // Conversation claire, jusqu'au lot B3
    (330, 220, 2),     // fenêtre B : l'aperçu commun aux quatre onglets
]

for (largeur, hauteur, echelle) in cadres {
    let taille = NSSize(width: largeur, height: hauteur)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: largeur * echelle, pixelsHigh: hauteur * echelle,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
    // La taille en points : le dessin se fait en points, à l'échelle des pixels.
    rep.size = taille
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(red: 0x2B / 255.0, green: 0x2B / 255.0, blue: 0x2B / 255.0, alpha: 1).setFill()
    NSRect(origin: .zero, size: taille).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Helvetica Neue", size: 13) ?? NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor(white: 0.62, alpha: 1),
        .paragraphStyle: style,
    ]
    let texte = "Aucun aperçu pour l'instant\n\nLes images que Claude regarde\ns'affichent ici." as NSString
    let boite: CGFloat = 80
    texte.draw(in: NSRect(x: 10, y: (CGFloat(hauteur) - boite) / 2, width: CGFloat(largeur) - 20, height: boite), withAttributes: attributs)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let nom = largeur == hauteur ? "vide-\(largeur).png" : "vide-\(largeur)x\(hauteur).png"
    try png.write(to: URL(fileURLWithPath: dossier).appendingPathComponent(nom))
}
