import Foundation

/// Rendu reproductible (1.3.5) : à la fin de chaque retouche, les réglages principaux de la photo
/// sont gardés, et une seconde retouche de la même photo, faite après un retour à l'origine
/// (revert_to_original, une entrée « retour » de plus au journal), s'y compare : un écart au-delà
/// des seuils se signale. Un style qui change d'un jour à l'autre n'est pas un style. La fin d'une
/// retouche était photo_lesson ; depuis la 1.3.6 (la leçon retirée), c'est le view_photo avec
/// compare = before_claude que les invites et les consignes demandent en dernier
/// (`ToolHandler.noterLeRendu`). Gardés dans `rendus.json` ; seul `serve()` en donne un (ni
/// `--call`, ni la recette, ni les tests, qui passent un fichier temporaire).
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

    /// Garde le rendu d'une retouche et le compare à la fin de la retouche précédente de la même
    /// photo. Une photo garde un rendu par série (une retouche, de son retour à l'origine au
    /// suivant), le dernier de chacune, dans l'ordre : plus de retours au journal que le dernier
    /// gardé, une nouvelle série commence ; autant (ou moins : le journal ne garde que ses
    /// 200 dernières entrées), la même série a continué et son nouveau rendu remplace le dernier.
    /// Dans les deux cas, le rendu se compare au dernier de la série d'avant, gardé tant qu'une
    /// nouvelle série n'a pas commencé : un before_claude demandé en cours de retouche ne prend pas
    /// la place de la fin de la précédente, et chaque before_claude de la série, le dernier
    /// compris, dit l'écart du rendu courant. Rien à comparer pour la première série d'une photo.
    /// Un fichier d'avant la 1.3.6 se relit tel quel : il gardait déjà le dernier rendu de chaque
    /// série.
    func noter(_ rendu: Rendu) throws -> JSONValue? {
        var registre = lire()
        let cle = String(rendu.photo)
        var liste = registre[cle] ?? []
        if let dernier = liste.last, rendu.retours <= dernier.retours { liste.removeLast() }
        let comparaison = liste.last.map { Self.comparer($0, rendu) }
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
            : "Loin de la retouche précédente de cette photo (\(date)) : \(tropGrands.joined(separator: ", ")). Si la retouche n'est pas finie, rejuger à sa fin ; sinon, le dire à l'utilisateur (un style qui change d'un jour à l'autre n'est pas un style) et lui demander laquelle des deux suit son goût (et son guide de style)."
        var resultat: [String: JSONValue] = ["precedente": .string(date), "ecarts": .array(ecarts), "lecture": .string(lecture),
                                             "reproductible": .bool(tropGrands.isEmpty)]
        if !tropGrands.isEmpty { resultat["trop_grands"] = .array(tropGrands.map(JSONValue.string)) }
        return .object(resultat)
    }
}

extension ToolHandler {
    /// Le journal d'une photo, pour compter ses retours à l'origine : quelques entrées à lire.
    static let journalRenduTimeout: TimeInterval = 30

    /// Le rendu de fin de retouche d'une photo (view_photo avec compare = before_claude), d'après la
    /// réponse brute de la commande apercu : ses réglages à plat (l'état actuel, relu après le
    /// retour de la comparaison) et son profil. Gardé à la place du rendu d'avant de la même
    /// retouche, puis comparé à la fin de la retouche précédente de la même photo, celle d'avant
    /// son dernier retour à l'origine (`RegistreRendus.noter`) : les retours (entrées « retour »)
    /// se comptent au journal de la photo (commande journal, lecture seule). Nil sans photo
    /// identifiée ni réglage lu, si le journal ou le registre échoue (l'outil réussit quand même),
    /// ou quand il n'y a rien à comparer (la première retouche de la photo).
    func noterLeRendu(apercu: JSONValue, registre: RegistreRendus, quand: Date = Date()) -> JSONValue? {
        guard let id = apercu["photo"]?["id"]?.int else { return nil }
        var reglages: [String: Double] = [:]
        for cle in RegistreRendus.cles { if let valeur = apercu["reglages"]?[cle]?.double { reglages[cle] = valeur } }
        guard !reglages.isEmpty,
              let journal = try? lightroom.send("journal", ["photos": [.number(Double(id))]], timeout: Self.journalRenduTimeout) else { return nil }
        let photos = journal["photos"]?.array ?? []
        let entrees = (photos.first { $0["photo"]?["id"]?.int == id } ?? photos.first)?["entrees"]?.array ?? []
        let retours = entrees.filter { $0["type"]?.string == "retour" }.count
        let rendu = RegistreRendus.Rendu(photo: id, le: quand, reglages: reglages, profil: apercu["profil"]?.string, retours: retours)
        return (try? registre.noter(rendu)) ?? nil
    }
}
