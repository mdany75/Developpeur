import Foundation

/// Réglages de développement à plat, une clé par ligne, triées (`mcp-developpeur --dump`) : deux
/// relevés se comparent avec diff, par exemple avant et après une opération faite à la main dans
/// Lightroom (c'est ainsi qu'on lit ce qu'un outil range).
public enum ReglagesAPlat {
    public static func lignes(_ valeur: JSONValue) -> [String] {
        var resultat: [String] = []
        aplatir(valeur, chemin: "", dans: &resultat)
        return resultat.sorted()
    }

    private static func aplatir(_ valeur: JSONValue, chemin: String, dans resultat: inout [String]) {
        if let objet = valeur.object {
            if objet.isEmpty { resultat.append("\(chemin) = {}") }
            for (cle, sous) in objet { aplatir(sous, chemin: chemin.isEmpty ? cle : "\(chemin).\(cle)", dans: &resultat) }
        } else if let liste = valeur.array {
            if liste.isEmpty { resultat.append("\(chemin) = []") }
            // Rang sur trois chiffres : le tri garde l'ordre de la liste.
            for (index, sous) in liste.enumerated() { aplatir(sous, chemin: String(format: "%@.%03d", chemin, index + 1), dans: &resultat) }
        } else {
            resultat.append("\(chemin) = \(texte(valeur))")
        }
    }

    private static func texte(_ valeur: JSONValue) -> String {
        // Toute la précision : un écart minime entre deux relevés doit se voir.
        if let nombre = valeur.double { return nombre.rounded() == nombre && abs(nombre) < 1e15 ? String(Int64(nombre)) : "\(nombre)" }
        if let chaine = valeur.string { return chaine }
        if let booleen = valeur.bool { return booleen ? "true" : "false" }
        return "null"
    }
}
