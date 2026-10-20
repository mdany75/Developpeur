// metriques.swift — mesure la chasse des caractères dans les polices du fil de la fenêtre
// (celles que Fenetre.lua donne à Lightroom) et écrit Metriques.lua, qui sert à couper les
// lignes du fil à la bonne largeur.
//
// Usage : swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua

import AppKit

let polices: [(cle: String, nom: String, taille: CGFloat)] = [
    ("texte", "Helvetica Neue", 13),
    ("gras", "Helvetica Neue Bold", 13),
    ("mono", "Menlo", 11),
]

var caracteres: [String] = []
for code in 32...126 { caracteres.append(String(UnicodeScalar(code)!)) }
for code in 160...255 { caracteres.append(String(UnicodeScalar(code)!)) }
caracteres += ["’", "‘", "“", "”", "«", "»", "—", "–", "…", "•", "✓", "✕", "●", "○", "›", "▲", "▼", "▣", "ⓘ",
               "€", "œ", "Œ", "→", "←", "↑", "↓", "·", "≈", "≤", "≥", "−", "\u{202F}", "\u{2009}"]

func echapper(_ c: String) -> String {
    switch c {
    case "\\": return "\\\\"
    case "\"": return "\\\""
    default: return c
    }
}

print("-- Metriques.lua : chasse des caractères (points) dans les polices du fil, mesurée par")
print("-- scripts/metriques.swift (ne pas modifier à la main). Un caractère absent compte comme « M ».")
print("return {")
for police in polices {
    guard let font = NSFont(name: police.nom, size: police.taille) else {
        FileHandle.standardError.write("Police introuvable : \(police.nom)\n".data(using: .utf8)!)
        exit(1)
    }
    print("    \(police.cle) = {")
    print("        nom = \"\(police.nom)\", taille = \(Int(police.taille)), hauteur = \(String(format: "%.2f", font.ascender - font.descender + font.leading)),")
    var ligne = "        chasse = {"
    for c in caracteres {
        let largeur = (c as NSString).size(withAttributes: [.font: font]).width
        ligne += " [\"\(echapper(c))\"] = \(String(format: "%.2f", largeur)),"
    }
    print(ligne + " },")
    print("    },")
}
print("}")
