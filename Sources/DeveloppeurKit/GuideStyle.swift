import Foundation

/// Guide de style personnel : les goûts de l'utilisateur en retouche (profils préférés, contraste,
/// saturation, rendu des peaux, noir et blanc, grain…), dans un fichier Markdown qu'il peut ouvrir
/// et modifier lui-même : `guide-de-style.md` de la racine des données (`DossierDonnees` : le dossier
/// commun s'il est réglé, sinon `~/Library/Application Support/Developpeur`), relue à chaque accès.
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

    public static let nomFichier = "guide-de-style.md"

    /// Un fichier donné (essais), ou le guide de la racine des données, cherchée à chaque accès.
    private let fixe: URL?
    private let donnees: DossierDonnees

    /// Un fichier fixe (essais).
    public init(fichier: URL) {
        fixe = fichier
        donnees = DossierDonnees()
    }

    /// Le guide de la racine des données (le dossier commun s'il est réglé).
    public init(donnees: DossierDonnees = DossierDonnees()) {
        fixe = nil
        self.donnees = donnees
    }

    /// Le fichier du guide ; refus si le dossier commun réglé est introuvable.
    public func fichier() throws -> URL {
        if let fixe { return fixe }
        return try donnees.url(Self.nomFichier)
    }

    /// Le guide, ou nil s'il n'existe pas encore (ou est vide) ; refus si le dossier commun réglé
    /// est introuvable (jamais le guide d'un autre dossier).
    public func lire() throws -> String? {
        let fichier = try self.fichier()
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
        let fichier = try self.fichier()
        var lignes = (try lire() ?? Self.entete).components(separatedBy: "\n")
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
    /// Dossier commun introuvable : la note qui le dit, à la place du guide.
    public func pourInvite() -> String? {
        let lu: String?
        do { lu = try lire() } catch { return "(Guide de style indisponible : \(error.localizedDescription))" }
        guard let texte = lu else { return nil }
        guard texte.count > Self.tailleInvite else { return texte }
        return String(texte.prefix(Self.tailleInvite)) + "\n\n(Guide coupé ici ; le reste : ressource developpeur://guide-de-style.)"
    }
}
