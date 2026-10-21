// images-fenetre.swift — dessine les images de la fenêtre Claude (fenêtre B) d'après la maquette
// « B · Conversation claire » : couleurs, rayons des coins et tracés SVG de ses icônes, avec
// CoreGraphics et CoreText. Les tailles en points viennent de Dispositions.IMAGES, leur seule source,
// que scripts/gabarits.lua écrit en JSON sur l'entrée standard. Chaque image est un seul PNG en 2x
// (2 × la taille en points, 144 ppp), icônes d'image_name comprises, sans paire 1x et @2x :
// Lightroom l'affiche à sa taille en points (constaté le 21 octobre 2026). Écrit
// <module>/images/<nom>.png et rien d'autre ; une image de images/ absente de Dispositions.IMAGES
// est signalée, jamais effacée. Les essais de la fenêtre (Tests/Lua/Fenetre/essais-images.lua)
// vérifient chaque fichier : présence, taille en pixels et 144 ppp.
//
// Usage : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func echec(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift <dossier du module .lrplugin>\n".data(using: .utf8)!)
    exit(2)
}
let module = URL(fileURLWithPath: CommandLine.arguments[1])
let dossier = module.appendingPathComponent("images")

// Les tailles en points (Dispositions.IMAGES).
struct Taille: Decodable {
    let largeur: CGFloat
    let hauteur: CGFloat
}
let entree = FileHandle.standardInput.readDataToEndOfFile()
guard !entree.isEmpty else {
    echec("rien sur l'entrée standard : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift <module>")
}
let tailles: [String: Taille]
do {
    tailles = try JSONDecoder().decode([String: Taille].self, from: entree)
} catch {
    echec("tailles illisibles (JSON de scripts/gabarits.lua attendu) : \(error)")
}

// Couleurs -----------------------------------------------------------------------------------------

func hex(_ s: String) -> CGColor {
    let v = UInt32(s, radix: 16)!
    let r = CGFloat((v >> 16) & 0xFF) / 255, g = CGFloat((v >> 8) & 0xFF) / 255, b = CGFloat(v & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

let TEXTE = "1D1D1F", BLEU = "0A64D8", BORD_BLEU = "0A5BC4", AMBRE = "A86200", GRIS_ETOILE = "8A8A8A"

// Contexte et écriture ------------------------------------------------------------------------------

// Un contexte en points, origine en haut à gauche (comme le SVG de la maquette), en 2x.
let ECHELLE: CGFloat = 2

func contexte(_ l: CGFloat, _ h: CGFloat) -> CGContext {
    let lp = Int((l * ECHELLE).rounded()), hp = Int((h * ECHELLE).rounded())
    guard let ctx = CGContext(data: nil, width: lp, height: hp, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        echec("contexte impossible : \(l) × \(h)")
    }
    ctx.translateBy(x: 0, y: CGFloat(hp))
    ctx.scaleBy(x: ECHELLE, y: -ECHELLE)
    ctx.setShouldAntialias(true)
    return ctx
}

// Écrit l'image à 72 × ECHELLE ppp : Lightroom l'affiche alors à sa taille en points.
func ecrire(_ img: CGImage, _ nom: String) {
    let url = dossier.appendingPathComponent(nom + ".png")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        echec("écriture impossible : \(url.path)")
    }
    let ppp = 72 * ECHELLE
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyDPIWidth: ppp, kCGImagePropertyDPIHeight: ppp] as CFDictionary)
    if !CGImageDestinationFinalize(dest) {
        echec("écriture impossible : \(url.path)")
    }
}

// Tracés SVG (M L H V C A Z, absolus et relatifs ; arcs circulaires seulement) ------------------------

func nombres(_ s: Substring) -> [CGFloat] {
    var r: [CGFloat] = []
    var courant = ""
    func pousser() {
        if !courant.isEmpty, let v = Double(courant) { r.append(CGFloat(v)) }
        courant = ""
    }
    for c in s {
        if c == "-" {
            if courant.last != "e" { pousser() }
            courant.append(c)
        } else if c == "." {
            if courant.contains(".") { pousser() }
            courant.append(c)
        } else if c.isNumber || c == "e" {
            courant.append(c)
        } else {
            pousser()
        }
    }
    pousser()
    return r
}

// Un arc de cercle SVG (rx = ry, sans rotation), de (x1, y1) à (x2, y2), passé au centre.
func arc(_ p: CGMutablePath, _ x1: CGFloat, _ y1: CGFloat, _ rayon: CGFloat, _ grand: Bool, _ sens: Bool,
         _ x2: CGFloat, _ y2: CGFloat) {
    var r = rayon
    let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
    let lambda = (dx * dx + dy * dy) / (r * r)
    if lambda > 1 { r *= sqrt(lambda) }
    let signe: CGFloat = (grand != sens) ? 1 : -1
    let num = max(0, r * r * r * r - r * r * dy * dy - r * r * dx * dx)
    let den = r * r * dy * dy + r * r * dx * dx
    let coef = den == 0 ? 0 : signe * sqrt(num / den)
    let cxp = coef * dy, cyp = -coef * dx
    let cx = cxp + (x1 + x2) / 2, cy = cyp + (y1 + y2) / 2
    let a1 = atan2((dy - cyp) / r, (dx - cxp) / r)
    let a2 = atan2((-dy - cyp) / r, (-dx - cxp) / r)
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: a1, endAngle: a2, clockwise: !sens)
}

func trace(_ d: String) -> CGPath {
    let p = CGMutablePath()
    var x: CGFloat = 0, y: CGFloat = 0, sx: CGFloat = 0, sy: CGFloat = 0
    var i = d.startIndex
    while i < d.endIndex {
        let cmd = d[i]
        guard cmd.isLetter && cmd != "e" else { i = d.index(after: i); continue }
        var j = d.index(after: i)
        while j < d.endIndex && !(d[j].isLetter && d[j] != "e") { j = d.index(after: j) }
        let n = nombres(d[d.index(after: i)..<j])
        let rel = cmd.isLowercase
        switch cmd.uppercased() {
        case "M":
            var k = 0
            while k + 1 < n.count {
                x = (rel ? x : 0) + n[k]; y = (rel ? y : 0) + n[k + 1]
                if k == 0 { p.move(to: CGPoint(x: x, y: y)); sx = x; sy = y } else { p.addLine(to: CGPoint(x: x, y: y)) }
                k += 2
            }
        case "L":
            var k = 0
            while k + 1 < n.count {
                x = (rel ? x : 0) + n[k]; y = (rel ? y : 0) + n[k + 1]
                p.addLine(to: CGPoint(x: x, y: y)); k += 2
            }
        case "H":
            for v in n { x = (rel ? x : 0) + v; p.addLine(to: CGPoint(x: x, y: y)) }
        case "V":
            for v in n { y = (rel ? y : 0) + v; p.addLine(to: CGPoint(x: x, y: y)) }
        case "C":
            var k = 0
            while k + 5 < n.count {
                let bx = rel ? x : 0, by = rel ? y : 0
                p.addCurve(to: CGPoint(x: bx + n[k + 4], y: by + n[k + 5]),
                           control1: CGPoint(x: bx + n[k], y: by + n[k + 1]),
                           control2: CGPoint(x: bx + n[k + 2], y: by + n[k + 3]))
                x = bx + n[k + 4]; y = by + n[k + 5]; k += 6
            }
        case "A":
            var k = 0
            while k + 6 < n.count {
                let x2 = (rel ? x : 0) + n[k + 5], y2 = (rel ? y : 0) + n[k + 6]
                arc(p, x, y, n[k], n[k + 3] != 0, n[k + 4] != 0, x2, y2)
                x = x2; y = y2; k += 7
            }
        case "Z":
            p.closeSubpath(); x = sx; y = sy
        default:
            echec("commande SVG inconnue : \(cmd) dans « \(d) »")
        }
        i = j
    }
    return p
}

// Les formes SVG simples de la maquette : <circle> et <rect rx>.
func cercle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
}

func rect(_ x: CGFloat, _ y: CGFloat, _ l: CGFloat, _ h: CGFloat, rx: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: l, height: h), cornerWidth: rx, cornerHeight: rx, transform: nil)
}

// L'étoile des notes (polygone de la maquette, boîte de 24).
let ETOILE = trace("M12 2.6L14.76 8.8L21.51 9.51L16.47 14.05L17.88 20.69L12 17.3L6.12 20.69L7.53 14.05L2.49 9.51L9.24 8.8Z")

// Dessins -------------------------------------------------------------------------------------------

// Un dessin reçoit le contexte en points et la taille de l'image en points (Dispositions.IMAGES) :
// il s'y ajuste, pour qu'une taille recalée n'ait qu'à relancer ce script.
typealias Dessin = (CGContext, CGFloat, CGFloat) -> Void

// Une icône de la maquette : ses tracés dans la boîte `boite` (viewBox), réduits à la taille de
// l'image en gardant les proportions, centrés (preserveAspectRatio par défaut du SVG). `pleins` se
// remplissent avant le trait, comme en SVG ; le trait est en unités de la boîte.
func icone(boite: CGSize, couleur: String, trait: CGFloat, bouts: CGLineCap = .round, jointures: CGLineJoin = .round,
           traits: [CGPath], pleins: [CGPath] = []) -> Dessin {
    return { ctx, l, h in
        let s = min(l / boite.width, h / boite.height)
        ctx.translateBy(x: (l - boite.width * s) / 2, y: (h - boite.height * s) / 2)
        ctx.scaleBy(x: s, y: s)
        ctx.setFillColor(hex(couleur))
        ctx.setStrokeColor(hex(couleur))
        ctx.setLineWidth(trait)
        ctx.setLineCap(bouts)
        ctx.setLineJoin(jointures)
        for p in pleins {
            ctx.addPath(p)
            ctx.fillPath()
        }
        for p in traits {
            ctx.addPath(p)
            ctx.strokePath()
        }
    }
}

let B16 = CGSize(width: 16, height: 16), B24 = CGSize(width: 24, height: 24)

// Remplit et borde un rectangle arrondi (bord de 1 point, à l'intérieur).
func carte(_ ctx: CGContext, _ cadre: CGRect, rayon r: CGFloat, fond: String, bord: String?) {
    ctx.addPath(CGPath(roundedRect: cadre, cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.setFillColor(hex(fond))
    ctx.fillPath()
    if let bord {
        let dedans = cadre.insetBy(dx: 0.5, dy: 0.5), rd = max(0, r - 0.5)
        ctx.addPath(CGPath(roundedRect: dedans, cornerWidth: rd, cornerHeight: rd, transform: nil))
        ctx.setStrokeColor(hex(bord))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
}

func pleine(fond: String, bord: String?, rayon: CGFloat) -> Dessin {
    return { ctx, l, h in carte(ctx, CGRect(x: 0, y: 0, width: l, height: h), rayon: rayon, fond: fond, bord: bord) }
}

// Texte (CoreText) centré sur un point, dans le repère en points de l'image.
func texte(_ ctx: CGContext, _ s: String, _ police: NSFont, _ couleur: String, cx: CGFloat, cy: CGFloat) {
    let attributs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): police as CTFont,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): hex(couleur),
    ]
    let ligne = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attributs))
    var montee: CGFloat = 0, descente: CGFloat = 0, interligne: CGFloat = 0
    let largeur = CGFloat(CTLineGetTypographicBounds(ligne, &montee, &descente, &interligne))
    ctx.saveGState()
    ctx.translateBy(x: cx - largeur / 2, y: cy + (montee - descente) / 2)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(ligne, ctx)
    ctx.restoreGState()
}

// Un segment des onglets Aperçu | Proposition | Note | Leçon (le contrôle de la maquette, coupé
// segment par segment) : fond blanc et texte #1D1D1F 12, ou, choisi, fond #0A64D8 et texte blanc
// gras (600) 12 ; bord #B5B5B5 en haut et en bas, coins de 6 au bout gauche du premier et au bout
// droit du dernier ; un filet #D0D0D0 au bord droit de chacun sauf le dernier, gardé sous le segment
// choisi (la maquette garde les filets de ses voisins).
func segment(_ titre: String, premier: Bool, dernier: Bool, actif: Bool) -> Dessin {
    return { ctx, l, h in
        let r: CGFloat = 6, deborde: CGFloat = 20
        // Ce qui dépasse de l'image (coins d'un bout qui n'est pas arrondi) est coupé.
        let x0 = premier ? 0 : -deborde, x1 = dernier ? l : l + deborde
        carte(ctx, CGRect(x: x0, y: 0, width: x1 - x0, height: h), rayon: r, fond: actif ? BLEU : "FFFFFF", bord: nil)
        if !dernier {
            ctx.setFillColor(hex("D0D0D0"))
            ctx.fill(CGRect(x: l - 1, y: 1, width: 1, height: h - 2))
        }
        ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + 0.5, y: 0.5, width: x1 - x0 - 1, height: h - 1),
                           cornerWidth: r - 0.5, cornerHeight: r - 0.5, transform: nil))
        ctx.setStrokeColor(hex("B5B5B5"))
        ctx.setLineWidth(1)
        ctx.strokePath()
        let police = actif ? NSFont.systemFont(ofSize: 12, weight: .semibold) : NSFont.systemFont(ofSize: 12)
        texte(ctx, titre, police, actif ? "FFFFFF" : TEXTE, cx: l / 2, cy: h / 2)
    }
}

var dessins: [String: Dessin] = [:]

// Le panneau de la colonne droite : la bande du haut (12 points, sous la moitié des segments qui
// chevauchent son bord) reste transparente, puis le panneau blanc, bord #C9C9C9, coins de 7.
let BANDE_PANNEAU: CGFloat = 12
dessins["panneau"] = { ctx, l, h in
    carte(ctx, CGRect(x: 0, y: BANDE_PANNEAU, width: l, height: h - BANDE_PANNEAU), rayon: 7, fond: "FFFFFF", bord: "C9C9C9")
}

// Les fonds des cartes : #FAFAFA, bord #D9D9D9, coins de 6.
for nom in ["carte-note", "carte-proposition", "carte-etape", "carte-lecon"] {
    dessins[nom] = pleine(fond: "FAFAFA", bord: "D9D9D9", rayon: 6)
}

// Les segments, dans l'ordre de la maquette.
let segments = [("apercu", "Aperçu"), ("proposition", "Proposition"), ("note", "Note"), ("lecon", "Leçon")]
for (i, (cle, titre)) in segments.enumerated() {
    let premier = i == 0, dernier = i == segments.count - 1
    dessins["seg-" + cle] = segment(titre, premier: premier, dernier: dernier, actif: false)
    dessins["seg-" + cle + "-actif"] = segment(titre, premier: premier, dernier: dernier, actif: true)
}

// Le fond de la conversation choisie : #DADADA, coins de 5, sans bord.
dessins["selection"] = pleine(fond: "DADADA", bord: nil, rayon: 5)

// Les pastilles des voyants : le vert de la maquette, l'orange et le rouge des voyants de la 1.2,
// et un gris neutre.
for (nom, couleur) in [("vert", "2DA44E"), ("orange", "E0800D"), ("rouge", "D12E2E"), ("gris", "8A8A8A")] {
    dessins["pastille-" + nom] = { ctx, l, h in
        ctx.setFillColor(hex(couleur))
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: l, height: h))
    }
}

// Le bouton bleu (#0A64D8, bord #0A5BC4, coins de 6), sans texte : Lightroom pose le titre blanc
// par-dessus. Enfoncé, plus foncé ; inactif, pâli.
dessins["bouton-bleu"] = pleine(fond: BLEU, bord: BORD_BLEU, rayon: 6)
dessins["bouton-bleu-presse"] = pleine(fond: "084A9E", bord: BORD_BLEU, rayon: 6)
dessins["bouton-bleu-inactif"] = pleine(fond: "9DBDEB", bord: "88AEE2", rayon: 6)

// Les étoiles : pleines en ambre (remplies et bordées), vides au trait gris.
dessins["etoile24-pleine"] = icone(boite: B24, couleur: AMBRE, trait: 1.5, traits: [ETOILE], pleins: [ETOILE])
dessins["etoile24-vide"] = icone(boite: B24, couleur: GRIS_ETOILE, trait: 1.4, traits: [ETOILE])
dessins["etoile12-pleine"] = icone(boite: B24, couleur: AMBRE, trait: 1.5, traits: [ETOILE], pleins: [ETOILE])
dessins["etoile12-vide"] = icone(boite: B24, couleur: GRIS_ETOILE, trait: 1.8, traits: [ETOILE])

// La rangée des passes : la coche verte d'une passe faite, le chevron entre deux passes.
dessins["coche-10"] = icone(boite: B16, couleur: "1F7A35", trait: 2.2, traits: [trace("M3.5 8.5l3 3 6-7")])
dessins["chevron-passe"] = icone(boite: CGSize(width: 8, height: 10), couleur: GRIS_ETOILE, trait: 1.4,
                                 traits: [trace("M2 1.5L6 5l-4 3.5")])

// La ligne du plafond : le triangle ambre et son point (rempli et bordé, comme le cercle de la
// maquette, qui hérite du trait).
dessins["avertissement"] = icone(boite: B16, couleur: AMBRE, trait: 1.5,
                                 traits: [trace("M8 2.2l6.3 11.1H1.7z"), trace("M8 6.3v3.4"), cercle(8, 11.4, 0.5)],
                                 pleins: [cercle(8, 11.4, 0.5)])

// La loupe devant le champ Rechercher (bouts arrondis, jointures par défaut).
dessins["loupe"] = icone(boite: B16, couleur: "6B6B6B", trait: 1.6, jointures: .miter,
                         traits: [cercle(7, 7, 4.3), trace("M10.2 10.2l3.3 3.3")])

// Les icônes des boutons sans titre : 📎 et 📋 de la saisie, ▲ ▼ de la barre du fil.
dessins["trombone"] = icone(boite: B16, couleur: TEXTE, trait: 1.4, traits: [
    trace("M13 7.5l-5.3 5.3a3 3 0 0 1-4.2-4.2l5.6-5.6a2 2 0 0 1 2.8 2.8l-5.5 5.5a1 1 0 0 1-1.4-1.4l4.9-4.9"),
])
dessins["presse-papiers"] = icone(boite: B16, couleur: TEXTE, trait: 1.4, bouts: .butt, traits: [
    rect(3.5, 3, 9, 11, rx: 1.5), rect(6, 1.8, 4, 2.6, rx: 0.8),
])
dessins["chevron-haut"] = icone(boite: B16, couleur: TEXTE, trait: 1.6, traits: [trace("M4 10l4-4 4 4")])
dessins["chevron-bas"] = icone(boite: B16, couleur: TEXTE, trait: 1.6, traits: [trace("M4 6l4 4 4-4")])

// Écriture --------------------------------------------------------------------------------------------

// Toutes les tailles doivent avoir leur dessin, avant d'écrire quoi que ce soit.
let inconnues = tailles.keys.filter { dessins[$0] == nil }.sorted()
if !inconnues.isEmpty {
    echec("aucun dessin pour : \(inconnues.joined(separator: ", ")) (à ajouter dans scripts/images-fenetre.swift)")
}
for (nom, t) in tailles where !(t.largeur > 0 && t.hauteur > 0) {
    echec("taille invalide pour \(nom) : \(t.largeur) × \(t.hauteur)")
}

do {
    try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
} catch {
    echec("dossier impossible : \(dossier.path) (\(error))")
}
for nom in tailles.keys.sorted() {
    let t = tailles[nom]!
    let ctx = contexte(t.largeur, t.hauteur)
    dessins[nom]!(ctx, t.largeur, t.hauteur)
    guard let image = ctx.makeImage() else { echec("image impossible : \(nom)") }
    ecrire(image, nom)
}

for nom in dessins.keys.sorted() where tailles[nom] == nil {
    FileHandle.standardError.write("dessin sans taille dans Dispositions.IMAGES, non écrit : \(nom)\n".data(using: .utf8)!)
}
let presentes = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
for fichier in presentes.sorted() where fichier.hasSuffix(".png") && tailles[String(fichier.dropLast(4))] == nil {
    FileHandle.standardError.write("image absente de Dispositions.IMAGES, à retirer : images/\(fichier)\n".data(using: .utf8)!)
}
print("\(tailles.count) images écrites dans \(dossier.path)")
