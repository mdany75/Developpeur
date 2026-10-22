// images-vides.swift — dessine l'image « aucun aperçu » de la fenêtre Claude (fenêtre B), au cadre
// 3:2 de l'aperçu commun aux cinq onglets (498 × 332 points), une par apparence (claire et
// sombre), du fond et du texte de sa palette (`fondApercu`, `texteApercu`). Tout vient de
// Dispositions.lua, que scripts/gabarits.lua écrit en JSON sur l'entrée standard : le cadre et le
// nom de l'image (`vide`, Dispositions.nomImageVide), le dossier et la palette de chaque apparence
// (Dispositions.APPARENCES, Dispositions.PALETTES). Chaque image est un seul PNG en 2x (996 × 664
// pixels à 144 ppp), que le SDK de Lightroom affiche à sa taille en points, comme celles de
// scripts/images-fenetre.swift ; elle va dans le dossier des images de son apparence
// (images/vide-498x332.png, images/sombre/vide-498x332.png : Dispositions.imageVide). Tout est
// vérifié avant d'écrire quoi que ce soit (un cadre positif, des dossiers sous le module, les deux
// couleurs dans chaque palette, en RRGGBB). Les essais de la fenêtre (essais-images.lua) vérifient
// les deux fichiers : présence, taille en pixels, 144 ppp, la sombre autre que la claire.
//
// Usage : luajit scripts/gabarits.lua | swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin

import AppKit
import Foundation

func echec(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage : luajit scripts/gabarits.lua | swift scripts/images-vides.swift <dossier du module .lrplugin>\n".data(using: .utf8)!)
    exit(2)
}
let module = URL(fileURLWithPath: CommandLine.arguments[1])

// Ce qu'écrit scripts/gabarits.lua (Dispositions.gabarits) : ici, le cadre de l'image et chaque
// apparence (les tailles des autres images ne servent pas).
struct Vide: Decodable {
    let nom: String
    let largeur: CGFloat
    let hauteur: CGFloat
}
struct Apparence: Decodable {
    let dossier: String
    let couleurs: [String: String]
}
struct Gabarits: Decodable {
    let vide: Vide
    let apparences: [String: Apparence]
}
let entree = FileHandle.standardInput.readDataToEndOfFile()
guard !entree.isEmpty else {
    echec("rien sur l'entrée standard : luajit scripts/gabarits.lua | swift scripts/images-vides.swift <module>")
}
let gabarits: Gabarits
do {
    gabarits = try JSONDecoder().decode(Gabarits.self, from: entree)
} catch {
    echec("gabarits illisibles (JSON de scripts/gabarits.lua attendu) : \(error)")
}

// Six chiffres hexadécimaux ASCII (pas Character.isHexDigit, qui accepte les chiffres pleine chasse).
func estHex(_ s: String) -> Bool {
    s.utf8.count == 6 && s.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
}

func couleur(_ s: String) -> NSColor {
    let v = UInt32(s, radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

// Vérifications, avant d'écrire quoi que ce soit ------------------------------------------------

let vide = gabarits.vide
if !(vide.largeur > 0 && vide.hauteur > 0) {
    echec("cadre invalide pour \(vide.nom) : \(vide.largeur) × \(vide.hauteur)")
}
if vide.nom.isEmpty || vide.nom.contains("/") || vide.nom.hasPrefix(".") {
    echec("nom invalide pour l'image « aucun aperçu » : « \(vide.nom) »")
}
let noms = gabarits.apparences.keys.sorted()
if noms.isEmpty {
    echec("aucune apparence dans les gabarits (Dispositions.APPARENCES)")
}
var dossiersVus: [String: String] = [:]
for nom in noms {
    let a = gabarits.apparences[nom]!
    let morceaux = a.dossier.split(separator: "/", omittingEmptySubsequences: false)
    if a.dossier.isEmpty || a.dossier.hasPrefix("/") || morceaux.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) {
        echec("dossier invalide pour l'apparence \(nom) : « \(a.dossier) » (relatif au module, sans « .. »)")
    }
    if let autre = dossiersVus[a.dossier] {
        echec("dossier « \(a.dossier) » commun aux apparences \(autre) et \(nom)")
    }
    dossiersVus[a.dossier] = nom
    for cle in ["fondApercu", "texteApercu"] {
        guard let valeur = a.couleurs[cle] else {
            echec("couleur absente de la palette \(nom) : \(cle) (Dispositions.PALETTES)")
        }
        if !estHex(valeur) {
            echec("couleur invalide dans la palette \(nom) : \(cle) = « \(valeur) » (RRGGBB attendu)")
        }
    }
}

// Écriture ------------------------------------------------------------------------------------------

// Le dessin en points, à l'échelle de 2 pixels par point ; 144 ppp dans le PNG (la taille en
// points de la représentation), comme les images de scripts/images-fenetre.swift.
let ECHELLE = 2
var ecrits: [String] = []
for nom in noms {
    let a = gabarits.apparences[nom]!
    let taille = NSSize(width: vide.largeur, height: vide.hauteur)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(vide.largeur) * ECHELLE,
                                     pixelsHigh: Int(vide.hauteur) * ECHELLE, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                     bitsPerPixel: 0) else { echec("image impossible : \(nom)") }
    rep.size = taille
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    couleur(a.couleurs["fondApercu"]!).setFill()
    NSRect(origin: .zero, size: taille).fill()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Helvetica Neue", size: 13) ?? NSFont.systemFont(ofSize: 13),
        .foregroundColor: couleur(a.couleurs["texteApercu"]!),
        .paragraphStyle: style,
    ]
    let texte = "Aucun aperçu pour l'instant\n\nLes images que Claude regarde\ns'affichent ici." as NSString
    let boite: CGFloat = 80
    texte.draw(in: NSRect(x: 10, y: (vide.hauteur - boite) / 2, width: vide.largeur - 20, height: boite), withAttributes: attributs)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { echec("PNG impossible : \(nom)") }
    let dossier = module.appendingPathComponent(a.dossier)
    do {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        try png.write(to: dossier.appendingPathComponent(vide.nom + ".png"))
    } catch {
        echec("écriture impossible dans \(dossier.path) : \(error)")
    }
    ecrits.append("\(a.dossier)/\(vide.nom).png (\(nom))")
}
print("image « aucun aperçu » écrite : \(ecrits.joined(separator: ", ")), dans \(module.path)")
