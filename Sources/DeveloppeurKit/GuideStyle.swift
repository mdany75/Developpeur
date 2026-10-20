import Foundation

/// Guide de style personnel : les goûts de l'utilisateur en retouche (profils préférés, contraste,
/// saturation, rendu des peaux, noir et blanc, grain…), dans un fichier Markdown qu'il peut ouvrir
/// et modifier lui-même : `~/Library/Application Support/Developpeur/guide-de-style.md`.
/// L'invite `retouche_pro` l'inclut, une ressource MCP le rend lisible, et `remember_style` y ajoute
/// une préférence apprise en conversation, seulement après l'accord de l'utilisateur.
public struct GuideStyle {
    /// Rubriques du guide : nom pour Claude, titre dans le fichier.
    public static let rubriques: [(nom: String, titre: String)] = [
        ("profiles", "Profils"), ("tone", "Lumière et contraste"), ("color", "Couleurs et saturation"),
        ("skin", "Peaux et portraits"), ("black_and_white", "Noir et blanc"), ("grain", "Grain et texture"),
        ("crop", "Recadrage"), ("export", "Livraison"), ("other", "Autres préférences"),
    ]
    /// Taille au-delà de laquelle le guide est coupé dans une invite (il reste entier dans le fichier).
    public static let tailleInvite = 6000

    public let fichier: URL

    public init(fichier: URL = GuideStyle.fichierParDefaut) {
        self.fichier = fichier
    }

    public static var fichierParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Developpeur/guide-de-style.md")
    }

    /// Le guide, ou nil s'il n'existe pas encore (ou est vide).
    public func lire() -> String? {
        guard let texte = try? String(contentsOf: fichier, encoding: .utf8),
              !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return texte
    }

    static let entete = """
    # Guide de style

    Mes goûts en retouche, que Claude suit dans Lightroom Classic (MCP-Développeur). Je peux modifier ce
    fichier à la main ; Claude n'y ajoute une préférence qu'avec mon accord.

    """

    /// Ajoute une préférence sous sa rubrique (créée au besoin), datée ; renvoie le guide entier.
    @discardableResult
    public func ajouter(_ preference: String, rubrique nom: String, date: Date = Date()) throws -> String {
        let texte = preference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { throw LightroomError.invalid("« preference » : la préférence, en une phrase.") }
        guard let rubrique = Self.rubriques.first(where: { $0.nom == nom }) else {
            throw LightroomError.invalid("« category » : \(Self.rubriques.map(\.nom).joined(separator: ", ")).")
        }
        let jour = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
        let ligne = "- \(texte.replacingOccurrences(of: "\n", with: " ")) _(ajouté le \(jour))_"
        var lignes = (lire() ?? Self.entete).components(separatedBy: "\n")
        let titre = "## " + rubrique.titre
        if let debut = lignes.firstIndex(of: titre) {
            // À la fin de la rubrique, avant la suivante.
            var fin = debut + 1
            while fin < lignes.count, !lignes[fin].hasPrefix("## ") { fin += 1 }
            while fin > debut + 1, lignes[fin - 1].trimmingCharacters(in: .whitespaces).isEmpty { fin -= 1 }
            lignes.insert(ligne, at: fin)
        } else {
            while let derniere = lignes.last, derniere.trimmingCharacters(in: .whitespaces).isEmpty { lignes.removeLast() }
            lignes += ["", titre, "", ligne]
        }
        let resultat = lignes.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        try resultat.write(to: fichier, atomically: true, encoding: .utf8)
        return resultat
    }

    /// Le guide pour une invite : entier, ou coupé avec une note.
    public func pourInvite() -> String? {
        guard let texte = lire() else { return nil }
        guard texte.count > Self.tailleInvite else { return texte }
        return String(texte.prefix(Self.tailleInvite)) + "\n\n(Guide coupé ici ; le reste : ressource developpeur://guide-de-style.)"
    }
}
