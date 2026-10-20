// images-vides.swift — dessine les images « aucun aperçu » de la fenêtre (une par taille de
// fenêtre), au fond des vignettes (2B2B2B), en PNG à 72 ppp : le SDK de Lightroom affiche une
// image à sa taille en points.
//
// Usage : swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin

import AppKit

let dossier = CommandLine.arguments.dropFirst().first ?? "."
for cote in [230, 270, 320] {
    let taille = NSSize(width: cote, height: cote)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cote, pixelsHigh: cote, bitsPerSample: 8,
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
    let hauteur: CGFloat = 80
    texte.draw(in: NSRect(x: 10, y: (CGFloat(cote) - hauteur) / 2, width: CGFloat(cote) - 20, height: hauteur), withAttributes: attributs)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: dossier).appendingPathComponent("vide-\(cote).png"))
}
