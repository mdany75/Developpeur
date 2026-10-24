import Foundation

/// Rendu reproductible (1.3.5) : à la fin de chaque retouche (photo_lesson), les réglages
/// principaux de la photo sont gardés, et une seconde retouche de la même photo, faite après un
/// retour à l'origine (revert_to_original, une entrée « retour » de plus au journal), s'y compare :
/// un écart au-delà des seuils se signale. Un style qui change d'un jour à l'autre n'est pas un
/// style. Gardés dans `rendus.json` ; seul `serve()` en donne un (ni `--call`, ni la recette, ni
/// les tests, qui passent un fichier temporaire).
public struct RegistreRendus {
    public let fichier: URL

    public init(fichier: URL = RegistreRendus.fichierParDefaut) { self.fichier = fichier }

    public static var fichierParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Developpeur/rendus.json")
    }

    /// Les réglages comparés, et l'écart au-delà duquel deux rendus ne se ressemblent plus.
    /// Provisoires : à relever sur une photo retouchée deux fois.
    static let seuils: [(cle: String, ecart: Double)] = [
        ("Exposure2012", 0.3), ("Contrast2012", 15), ("Highlights2012", 20), ("Shadows2012", 20), ("Whites2012", 15),
        ("Blacks2012", 15), ("Temperature", 8), ("Tint", 8), ("Vibrance", 15), ("Saturation", 10), ("Clarity2012", 15),
        ("Dehaze", 10), ("Texture", 15),
    ]
    /// La température d'un RAW est en kelvins (au-delà de 1000) : son seuil.
    static let seuilKelvins = 400.0
    static var cles: [String] { seuils.map(\.cle) }
    /// Rendus gardés par photo, et photos au plus.
    static let parPhoto = 3, maxPhotos = 2000

    public struct Rendu: Codable, Equatable {
        var photo: Int
        var le: Date
        var reglages: [String: Double]
        var profil: String?
        /// Retours à l'origine au journal de la photo quand le rendu a été gardé.
        var retours: Int
    }

    func lire() -> [String: [Rendu]] {
        guard let data = try? Data(contentsOf: fichier) else { return [:] }
        let lecteur = JSONDecoder()
        lecteur.dateDecodingStrategy = .iso8601
        return (try? lecteur.decode([String: [Rendu]].self, from: data)) ?? [:]
    }

    func ecrire(_ registre: [String: [Rendu]]) throws {
        let ecrivain = JSONEncoder()
        ecrivain.dateEncodingStrategy = .iso8601
        ecrivain.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ecrivain.encode(registre).write(to: fichier, options: .atomic)
    }

    /// Garde le rendu de fin de retouche ; le compare au précédent de la même photo si une
    /// nouvelle retouche est partie de l'origine depuis (plus de retours au journal). Le même
    /// nombre de retours : la même retouche, qui a continué, remplace son rendu sans comparaison.
    func noter(_ rendu: Rendu) throws -> JSONValue? {
        var registre = lire()
        let cle = String(rendu.photo)
        var liste = registre[cle] ?? []
        var comparaison: JSONValue?
        if let precedent = liste.last {
            if rendu.retours > precedent.retours { comparaison = Self.comparer(precedent, rendu) } else { liste.removeLast() }
        }
        liste.append(rendu)
        registre[cle] = Array(liste.suffix(Self.parPhoto))
        if registre.count > Self.maxPhotos {
            let anciennes = registre.sorted { ($0.value.last?.le ?? .distantPast) < ($1.value.last?.le ?? .distantPast) }
                .prefix(registre.count - Self.maxPhotos).map(\.key)
            for vieille in anciennes { registre.removeValue(forKey: vieille) }
        }
        try ecrire(registre)
        return comparaison
    }

    /// Les écarts entre deux rendus de la même photo, et ceux qui passent leur seuil.
    static func comparer(_ avant: Rendu, _ apres: Rendu) -> JSONValue {
        var ecarts: [JSONValue] = [], tropGrands: [String] = []
        for (cle, seuil) in seuils {
            guard let a = avant.reglages[cle], let b = apres.reglages[cle] else { continue }
            let limite = cle == "Temperature" && a > 1000 && b > 1000 ? seuilKelvins : seuil
            let ecart = b - a
            guard abs(ecart) > 0.0001 else { continue }
            let libelle = DevelopCatalogue.label(for: cle) ?? cle
            ecarts.append(["reglage": .string(cle), "avant": .number(a), "maintenant": .number(b),
                           "ecart": .number((ecart * 100).rounded() / 100), "seuil": .number(limite)])
            if abs(ecart) > limite { tropGrands.append("\(libelle) \(Bilan.nombre(ecart, signe: true, decimales: abs(ecart) < 1 ? 2 : 0))") }
        }
        if let p1 = avant.profil, let p2 = apres.profil, p1 != p2 { tropGrands.append("profil « \(p1) » → « \(p2) »") }
        let date = Sauvegardes.texte(avant.le)
        let lecture = tropGrands.isEmpty
            ? "Proche de la retouche précédente de cette photo (\(date)) : écarts sous les seuils, le rendu se reproduit."
            : "Loin de la retouche précédente de cette photo (\(date)) : \(tropGrands.joined(separator: ", ")). Le dire à l'utilisateur : un style qui change d'un jour à l'autre n'est pas un style ; lui demander laquelle des deux suit son goût (et son guide de style)."
        var resultat: [String: JSONValue] = ["precedente": .string(date), "ecarts": .array(ecarts), "lecture": .string(lecture),
                                             "reproductible": .bool(tropGrands.isEmpty)]
        if !tropGrands.isEmpty { resultat["trop_grands"] = .array(tropGrands.map(JSONValue.string)) }
        return .object(resultat)
    }
}
