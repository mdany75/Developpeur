// images-vides.swift — dessine les images « aucun aperçu » de la fenêtre Claude, une par cadre
// d'aperçu de Dispositions.TAILLES (carrés de la Conversation claire et du Panneau, cadre 3:2 de
// l'Atelier : vide-320.png, vide-720x480.png), au fond des vignettes (2B2B2B), en PNG à 72 ppp :
// le SDK de Lightroom affiche une image à sa taille en points. Les essais de la fenêtre vérifient
// qu'il y en a une pour chaque disposition.
//
// Usage : swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin

import AppKit

let dossier = CommandLine.arguments.dropFirst().first ?? "."

// Largeur et hauteur de chaque cadre ; un carré garde son nom d'origine (vide-320.png).
let cadres: [(Int, Int)] = [
    (200, 200),     // Panneau
    (320, 320),     // Conversation claire
    (720, 480),     // Atelier
]

for (largeur, hauteur) in cadres {
    let taille = NSSize(width: largeur, height: hauteur)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: largeur, pixelsHigh: hauteur, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
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
