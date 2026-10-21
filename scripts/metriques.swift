// metriques.swift — mesure la chasse des caractères dans les polices de la fenêtre Claude (celles
// que Fenetre.lua donne à Lightroom : la police du système, '<system>' et '<system/bold>', aux
// tailles de la maquette de la fenêtre B, et Menlo 11) et écrit Metriques.lua, qui sert à couper
// les lignes du fil et des cartes à la bonne largeur.
//
// Lightroom rend '<system>' et '<system/bold>' par la police du système de macOS, à la taille
// donnée (constaté le 21 octobre 2026, D9, en 13, 12 et 11) ; la largeur de son encre fait 1 à 2
// points de moins que la chasse mesurée ici (approches des bords) : la chasse reste juste.
//
// Usage : swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua

import AppKit

// Clé de Metriques, nom écrit pour Lightroom, taille, gras ; Menlo par son nom.
let polices: [(cle: String, nom: String, taille: CGFloat, gras: Bool)] = [
    ("texte", "<system>", 13, false),
    ("texte12", "<system>", 12, false),
    ("petit", "<system>", 11, false),
    ("gras", "<system/bold>", 13, true),
    ("gras12", "<system/bold>", 12, true),
    ("titre", "<system/bold>", 16, true),
    ("mono", "Menlo", 11, false),
]

var caracteres: [String] = []
for code in 32...126 { caracteres.append(String(UnicodeScalar(code)!)) }
for code in 160...255 { caracteres.append(String(UnicodeScalar(code)!)) }
caracteres += ["’", "‘", "“", "”", "«", "»", "—", "–", "…", "•", "✓", "✕", "●", "○", "›", "▲", "▼", "▣", "ⓘ",
               "€", "œ", "Œ", "→", "←", "↑", "↓", "·", "≈", "≤", "≥", "−", "\u{202F}", "\u{2009}",
               "★", "☆", "⚑", "＋", "⊗", "⤢"]

func echapper(_ c: String) -> String {
    switch c {
    case "\\": return "\\\\"
    case "\"": return "\\\""
    default: return c
    }
}

func police(_ p: (cle: String, nom: String, taille: CGFloat, gras: Bool)) -> NSFont? {
    if p.nom.hasPrefix("<system") {
        return p.gras ? NSFont.boldSystemFont(ofSize: p.taille) : NSFont.systemFont(ofSize: p.taille)
    }
    return NSFont(name: p.nom, size: p.taille)
}

print("-- Metriques.lua : chasse des caractères (points) dans les polices de la fenêtre Claude, mesurée")
print("-- par scripts/metriques.swift (ne pas modifier à la main). Un caractère absent compte comme « M ».")
print("-- `nom` : le nom écrit pour Lightroom ('<system>', '<system/bold>' : la police du système).")
print("return {")
for p in polices {
    guard let font = police(p) else {
        FileHandle.standardError.write("Police introuvable : \(p.nom)\n".data(using: .utf8)!)
        exit(1)
    }
    print("    \(p.cle) = {")
    print("        nom = \"\(p.nom)\", taille = \(Int(p.taille)), hauteur = \(String(format: "%.2f", font.ascender - font.descender + font.leading)),")
    var ligne = "        chasse = {"
    for c in caracteres {
        let largeur = (c as NSString).size(withAttributes: [.font: font]).width
        ligne += " [\"\(echapper(c))\"] = \(String(format: "%.2f", largeur)),"
    }
    print(ligne + " },")
    print("    },")
}
print("}")
