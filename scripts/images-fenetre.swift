// images-fenetre.swift — dessine les images de la fenêtre Claude (fenêtre B) d'après la maquette
// « B · Conversation claire » : rayons des coins et tracés SVG de ses icônes, avec CoreGraphics et
// CoreText, en un jeu par apparence (claire et sombre). Tout vient de Dispositions.lua, que
// scripts/gabarits.lua écrit en JSON sur l'entrée standard : les tailles en points
// (Dispositions.IMAGES), et pour chaque apparence le dossier de ses images et sa palette
// (Dispositions.APPARENCES, Dispositions.PALETTES : la palette claire est celle de la maquette).
// Chaque image est un seul PNG en 2x (2 × la taille en points, 144 ppp), icônes d'image_name
// comprises, sans paire 1x et @2x : Lightroom l'affiche à sa taille en points (constaté le
// 21 octobre 2026). Écrit <module>/<dossier>/<nom>.png (images/ en claire, images/sombre/ en
// sombre) et rien d'autre, après avoir tout vérifié (un dessin par image, des tailles positives,
// chaque couleur dans chaque palette, en RRGGBB, des dossiers sous le module) ; une image d'un de
// ces dossiers absente de Dispositions.IMAGES est signalée, jamais effacée, sauf l'image « aucun
// aperçu » (`vide` des gabarits), rangée là par scripts/images-vides.swift. Les essais de la
// fenêtre (Tests/Lua/Fenetre/essais-images.lua) vérifient chaque fichier des deux jeux : présence,
// taille en pixels et 144 ppp.
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

// Ce qu'écrit scripts/gabarits.lua (Dispositions.gabarits) : les tailles en points
// (Dispositions.IMAGES), puis le dossier et la palette de chaque apparence.
struct Taille: Decodable {
    let largeur: CGFloat
    let hauteur: CGFloat
}
struct Apparence: Decodable {
    let dossier: String
    let couleurs: [String: String]
}
// L'image « aucun aperçu » (Dispositions.nomImageVide), rangée avec les images de chaque
// apparence mais dessinée par scripts/images-vides.swift : jamais signalée comme une image de trop.
struct Vide: Decodable {
    let nom: String
}
struct Gabarits: Decodable {
    let images: [String: Taille]
    let apparences: [String: Apparence]
    let vide: Vide?
}
let entree = FileHandle.standardInput.readDataToEndOfFile()
guard !entree.isEmpty else {
    echec("rien sur l'entrée standard : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift <module>")
}
let gabarits: Gabarits
do {
    gabarits = try JSONDecoder().decode(Gabarits.self, from: entree)
} catch {
    echec("gabarits illisibles (JSON de scripts/gabarits.lua attendu) : \(error)")
}
let tailles = gabarits.images

// Couleurs -----------------------------------------------------------------------------------------

// Une couleur de palette : six chiffres hexadécimaux ASCII (RRGGBB), vérifiés avant tout dessin.
// Pas Character.isHexDigit : il accepte aussi les chiffres pleine chasse (« １ »), que hex() ne lit
// pas (UInt32(_:radix:) rend nil), et l'image tomberait en cours d'écriture, un jeu déjà écrit.
func estHex(_ s: String) -> Bool {
    s.utf8.count == 6 && s.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
}

func hex(_ s: String) -> CGColor {
    let v = UInt32(s, radix: 16)!
    let r = CGFloat((v >> 16) & 0xFF) / 255, g = CGFloat((v >> 8) & 0xFF) / 255, b = CGFloat(v & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

// La palette d'une apparence (Dispositions.PALETTES), lue par clé quand les dessins se préparent :
// une clé absente est notée (manquantes), pour refuser avant d'écrire quoi que ce soit.
final class Palette {
    let valeurs: [String: String]
    private(set) var manquantes: Set<String> = []
    init(_ valeurs: [String: String]) { self.valeurs = valeurs }
    subscript(_ cle: String) -> String {
        if let v = valeurs[cle] { return v }
        manquantes.insert(cle)
        return "000000"
    }
}

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
func ecrire(_ img: CGImage, _ nom: String, dans dossier: URL) {
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

// L'étoile des notes réduite à `echelle`, son centre (12, 12) posé en (cx, cy).
func etoile(_ cx: CGFloat, _ cy: CGFloat, _ echelle: CGFloat) -> CGPath {
    var t = CGAffineTransform(translationX: cx - 12 * echelle, y: cy - 12 * echelle).scaledBy(x: echelle, y: echelle)
    return ETOILE.copy(using: &t) ?? ETOILE
}

// L'étincelle de l'IA (quatre branches courbes), en haut à droite d'une boîte de 24.
let ETINCELLE = trace("M20.5 0.6C20.9 3.2 21.4 3.7 24 4.1C21.4 4.5 20.9 5 20.5 7.6C20.1 5 19.6 4.5 17 4.1C19.6 3.7 20.1 3.2 20.5 0.6Z")

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

// Plusieurs dessins l'un sur l'autre, chacun dans son propre état du contexte (une icône à deux
// couleurs : l'image, puis l'étincelle).
func ensemble(_ morceaux: [Dessin]) -> Dessin {
    return { ctx, l, h in
        for m in morceaux {
            ctx.saveGState()
            m(ctx, l, h)
            ctx.restoreGState()
        }
    }
}

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

// Un segment des onglets Aperçu | Focus | Proposition | Note | Suivi (le contrôle de la maquette, coupé
// segment par segment) : fond `fondSegment` et texte `texte` 12 (en claire, blanc et #1D1D1F), ou,
// choisi, fond `bleuBouton` et texte `blanc` gras (600) 12 ; bord `bordSegment` en haut et en bas,
// coins de 6 au bout gauche du premier et au bout droit du dernier ; un filet `filetSegment` au
// bord droit de chacun sauf le dernier, gardé sous le segment choisi (la maquette garde les filets
// de ses voisins). Les couleurs se lisent dans la palette ici, pas au dessin.
func segment(_ titre: String, premier: Bool, dernier: Bool, actif: Bool, _ p: Palette) -> Dessin {
    let fond = actif ? p["bleuBouton"] : p["fondSegment"], encre = actif ? p["blanc"] : p["texte"]
    let filet = p["filetSegment"], bord = p["bordSegment"]
    return { ctx, l, h in
        let r: CGFloat = 6, deborde: CGFloat = 20
        // Ce qui dépasse de l'image (coins d'un bout qui n'est pas arrondi) est coupé.
        let x0 = premier ? 0 : -deborde, x1 = dernier ? l : l + deborde
        carte(ctx, CGRect(x: x0, y: 0, width: x1 - x0, height: h), rayon: r, fond: fond, bord: nil)
        if !dernier {
            ctx.setFillColor(hex(filet))
            ctx.fill(CGRect(x: l - 1, y: 1, width: 1, height: h - 2))
        }
        ctx.addPath(CGPath(roundedRect: CGRect(x: x0 + 0.5, y: 0.5, width: x1 - x0 - 1, height: h - 1),
                           cornerWidth: r - 0.5, cornerHeight: r - 0.5, transform: nil))
        ctx.setStrokeColor(hex(bord))
        ctx.setLineWidth(1)
        ctx.strokePath()
        let police = actif ? NSFont.systemFont(ofSize: 12, weight: .semibold) : NSFont.systemFont(ofSize: 12)
        texte(ctx, titre, police, encre, cx: l / 2, cy: h / 2)
    }
}

// Le panneau de la colonne droite : la bande du haut (12 points, sous la moitié des segments qui
// chevauchent son bord) reste transparente.
let BANDE_PANNEAU: CGFloat = 12

// Les dessins d'une apparence, couleurs lues dans sa palette (clés de Dispositions.PALETTES) au
// moment de les préparer : une couleur absente est notée par la palette avant tout dessin. Les
// valeurs entre parenthèses sont celles de la palette claire (la maquette).
func dessins(_ p: Palette) -> [String: Dessin] {
    var d: [String: Dessin] = [:]

    // Le panneau (blanc, bord #C9C9C9, coins de 7), sous sa bande transparente.
    let fondPanneau = p["fondPanneau"], bordPanneau = p["bordPanneau"]
    d["panneau"] = { ctx, l, h in
        carte(ctx, CGRect(x: 0, y: BANDE_PANNEAU, width: l, height: h - BANDE_PANNEAU), rayon: 7, fond: fondPanneau,
              bord: bordPanneau)
    }

    // Les fonds des cartes (#FAFAFA, bord #D9D9D9), coins de 6.
    for nom in ["carte-note", "carte-proposition", "carte-etape", "carte-focus", "carte-suivi"] {
        d[nom] = pleine(fond: p["fondCarte"], bord: p["bordCarte"], rayon: 6)
    }

    // Les segments, dans l'ordre de la maquette (Focus après Aperçu : demandé par Dany le 22 octobre 2026 ;
    // Suivi, le carnet de progrès, le dernier, à la place de Leçon au correctif 1.3.6).
    let segments = [("apercu", "Aperçu"), ("focus", "Focus"), ("proposition", "Proposition"), ("note", "Note"),
                    ("suivi", "Suivi")]
    for (i, (cle, titre)) in segments.enumerated() {
        let premier = i == 0, dernier = i == segments.count - 1
        d["seg-" + cle] = segment(titre, premier: premier, dernier: dernier, actif: false, p)
        d["seg-" + cle + "-actif"] = segment(titre, premier: premier, dernier: dernier, actif: true, p)
    }

    // (Le fond de la conversation choisie et la loupe du champ Rechercher sont retirés avec le volet
    // au correctif 1.3.6.)

    // Les pastilles des voyants : le vert de la maquette (#2DA44E), l'orange et le rouge des voyants
    // de la 1.2, et le gris du contour.
    for (nom, couleur) in [("vert", p["pastille"]), ("orange", p["orange"]), ("rouge", p["rouge"]), ("gris", p["contour"])] {
        d["pastille-" + nom] = { ctx, l, h in
            ctx.setFillColor(hex(couleur))
            ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: l, height: h))
        }
    }

    // Le bouton bleu (#0A64D8, bord #0A5BC4, coins de 6), sans texte : Lightroom pose le titre
    // par-dessus. Enfoncé, plus foncé ; inactif, éteint.
    d["bouton-bleu"] = pleine(fond: p["bleuBouton"], bord: p["bordBleu"], rayon: 6)
    d["bouton-bleu-presse"] = pleine(fond: p["bleuPresse"], bord: p["bordBleu"], rayon: 6)
    d["bouton-bleu-inactif"] = pleine(fond: p["bleuInactif"], bord: p["bordBleuInactif"], rayon: 6)

    // Les étoiles : pleines en ambre (remplies et bordées), vides au trait du contour.
    d["etoile24-pleine"] = icone(boite: B24, couleur: p["ambre"], trait: 1.5, traits: [ETOILE], pleins: [ETOILE])
    d["etoile24-vide"] = icone(boite: B24, couleur: p["contour"], trait: 1.4, traits: [ETOILE])
    d["etoile12-pleine"] = icone(boite: B24, couleur: p["ambre"], trait: 1.5, traits: [ETOILE], pleins: [ETOILE])
    d["etoile12-vide"] = icone(boite: B24, couleur: p["contour"], trait: 1.8, traits: [ETOILE])

    // La rangée des passes (coche-10, chevron-passe) et la ligne du plafond (avertissement) de la
    // carte Note sont retirées depuis le correctif 1.3.2 (demandé par Dany le 22 octobre 2026).

    // Les icônes des boutons sans titre (#1D1D1F) : 📎 et 📋 de la saisie, ▲ ▼ de la barre du fil.
    d["trombone"] = icone(boite: B16, couleur: p["texte"], trait: 1.4, traits: [
        trace("M13 7.5l-5.3 5.3a3 3 0 0 1-4.2-4.2l5.6-5.6a2 2 0 0 1 2.8 2.8l-5.5 5.5a1 1 0 0 1-1.4-1.4l4.9-4.9"),
    ])
    d["presse-papiers"] = icone(boite: B16, couleur: p["texte"], trait: 1.4, bouts: .butt, traits: [
        rect(3.5, 3, 9, 11, rx: 1.5), rect(6, 1.8, 4, 2.6, rx: 0.8),
    ])
    d["chevron-haut"] = icone(boite: B16, couleur: p["texte"], trait: 1.6, traits: [trace("M4 10l4-4 4 4")])
    d["chevron-bas"] = icone(boite: B16, couleur: p["texte"], trait: 1.6, traits: [trace("M4 6l4 4 4-4")])

    // Les boutons de la Demande rapide, à gauche du champ (demandés par Dany le 24 octobre 2026) : trois
    // étoiles ambre (noter) ; une photo et un portrait à l'encre du texte, chacun avec l'étincelle
    // orange de l'IA en haut à droite (Retouche pro, Portrait).
    let etoiles = [etoile(5.2, 14.2, 0.32), etoile(12, 10.6, 0.4), etoile(18.8, 14.2, 0.32)]
    d["rapide-noter"] = icone(boite: B24, couleur: p["ambre"], trait: 1.2, traits: etoiles, pleins: etoiles)
    let cadrePhoto = rect(2, 7, 15, 12.5, rx: 2)
    let etincelle = icone(boite: B24, couleur: p["orange"], trait: 0.8, traits: [ETINCELLE], pleins: [ETINCELLE])
    d["rapide-retouche"] = ensemble([
        icone(boite: B24, couleur: p["texte"], trait: 1.4, traits: [
            cadrePhoto, trace("M4 17.5l3.8-4.5 3 3.2 2-2 3.2 3.3"), cercle(13, 10.6, 1.3),
        ]),
        etincelle,
    ])
    d["rapide-portrait"] = ensemble([
        icone(boite: B24, couleur: p["texte"], trait: 1.4, traits: [
            cadrePhoto, cercle(9.5, 11.6, 2.4), trace("M5.2 19.5C5.2 16.6 7.1 15 9.5 15C11.9 15 13.8 16.6 13.8 19.5"),
        ]),
        etincelle,
    ])

    return d
}

// Vérifications, avant d'écrire quoi que ce soit ------------------------------------------------------

// Toutes les tailles doivent être positives.
for (nom, t) in tailles.sorted(by: { $0.key < $1.key }) where !(t.largeur > 0 && t.hauteur > 0) {
    echec("taille invalide pour \(nom) : \(t.largeur) × \(t.hauteur)")
}

// Au moins une apparence ; chacune a son dossier, sous le module (relatif, sans « .. »), à elle
// seule, et des couleurs en RRGGBB.
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
    for (cle, valeur) in a.couleurs.sorted(by: { $0.key < $1.key }) where !estHex(valeur) {
        echec("couleur invalide dans la palette \(nom) : \(cle) = « \(valeur) » (RRGGBB attendu)")
    }
}

// Les dessins de chaque apparence : toute couleur lue dans la palette, toute image avec son dessin.
var parApparence: [String: [String: Dessin]] = [:]
for nom in noms {
    let palette = Palette(gabarits.apparences[nom]!.couleurs)
    let d = dessins(palette)
    if !palette.manquantes.isEmpty {
        echec("couleur absente de la palette \(nom) : \(palette.manquantes.sorted().joined(separator: ", ")) (Dispositions.PALETTES)")
    }
    let inconnues = tailles.keys.filter { d[$0] == nil }.sorted()
    if !inconnues.isEmpty {
        echec("aucun dessin pour : \(inconnues.joined(separator: ", ")) (à ajouter dans scripts/images-fenetre.swift)")
    }
    parApparence[nom] = d
}

// Écriture --------------------------------------------------------------------------------------------

var ecrits: [String] = []
for nom in noms {
    let a = gabarits.apparences[nom]!
    let dossier = module.appendingPathComponent(a.dossier)
    do {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    } catch {
        echec("dossier impossible : \(dossier.path) (\(error))")
    }
    let d = parApparence[nom]!
    for image in tailles.keys.sorted() {
        let t = tailles[image]!
        let ctx = contexte(t.largeur, t.hauteur)
        d[image]!(ctx, t.largeur, t.hauteur)
        guard let rendu = ctx.makeImage() else { echec("image impossible : \(nom) › \(image)") }
        ecrire(rendu, image, dans: dossier)
    }
    ecrits.append("\(a.dossier) (\(nom))")
}

for image in (parApparence[noms[0]] ?? [:]).keys.sorted() where tailles[image] == nil {
    FileHandle.standardError.write("dessin sans taille dans Dispositions.IMAGES, non écrit : \(image)\n".data(using: .utf8)!)
}
for nom in noms {
    let a = gabarits.apparences[nom]!
    let dossier = module.appendingPathComponent(a.dossier)
    let presentes = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
    for fichier in presentes.sorted() where fichier.hasSuffix(".png") && tailles[String(fichier.dropLast(4))] == nil
        && String(fichier.dropLast(4)) != gabarits.vide?.nom {
        FileHandle.standardError.write("image absente de Dispositions.IMAGES, à retirer : \(a.dossier)/\(fichier)\n".data(using: .utf8)!)
    }
}
print("\(tailles.count) images écrites par apparence : \(ecrits.joined(separator: ", ")), dans \(module.path)")
