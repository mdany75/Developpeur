import Foundation

/// Le dossier commun (1.7) : Dany passe d'un Mac à l'autre avec le SSD « Photos », et veut
/// retrouver sur chacun le même travail (guide de style, conversations, Suivi, carnet, notation,
/// index du sens, modèles…). Le module écrit, depuis le Gestionnaire de modules externes, un
/// pointeur LOCAL `~/Library/Application Support/Developpeur/dossier-commun.json`
/// (`{"format":1,"dossier":"<chemin absolu>"}`) ; le serveur le lit seulement, à chaque accès (Dany
/// peut le changer pendant que le serveur tourne : rien n'est gardé en mémoire).
///
/// - Pointeur absent, illisible, d'un autre format ou sans `dossier` absolu non vide : pas de dossier
///   commun, tout reste dans la racine locale, comme avant.
/// - Dossier commun réglé et présent : c'est la racine des données (`elementsCommuns`).
/// - Dossier commun réglé mais absent (SSD débranché) : JAMAIS de repli sur la racine locale (deux
///   versions divergeraient) : `racine()` refuse avec `DossierCommunIntrouvable`, rien n'est lu ni
///   écrit ailleurs.
///
/// Restent toujours locaux (jamais par ce type) : l'exécutable, le jeton de la liaison,
/// connecteur.json, consignes.md, Sessions, Atelier, Temporaire, le pointeur lui-même, les journaux
/// et tout ce qui touche Fibo (`Fibo.racine`).
///
/// Les tests passent une racine locale et un pointeur temporaires ; jamais les vrais.
public struct DossierDonnees: Equatable {
    /// La racine locale : `~/Library/Application Support/Developpeur`.
    public let racineLocale: URL
    /// Le pointeur, dans la racine locale par défaut.
    public let pointeur: URL

    public static let nomPointeur = "dossier-commun.json"
    /// Le seul format du pointeur que ce serveur lit.
    public static let formatPointeur = 1

    /// Les éléments de la racine des données (contrat du dossier commun, point 3). Un nom qui finit
    /// par « * » désigne tous ceux qui commencent ainsi (`suivi-illisible-<date>.json`…).
    public static let elementsCommuns = [
        "guide-de-style.md", "Conversations", "suivi.json", "suivi.journal", "suivi-illisible-*",
        "carnet.json", "carnet-illisible-*", "notation.json", "mes-demandes.json", "mes-demandes-illisible-*",
        "invites.json",
        "publication.json", "consommation.json", "rendus.json", "Etapes", "Index", "Modeles", "Claude Code",
    ]

    public static var racineLocaleParDefaut: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Developpeur", isDirectory: true)
    }

    public init(racineLocale: URL = DossierDonnees.racineLocaleParDefaut, pointeur: URL? = nil) {
        self.racineLocale = racineLocale
        self.pointeur = pointeur ?? racineLocale.appendingPathComponent(Self.nomPointeur)
    }

    // MARK: État

    public enum Etat: Equatable {
        /// Pas de dossier commun : la racine locale.
        case local(URL)
        /// Le dossier commun, présent.
        case commun(URL)
        /// Le dossier commun réglé, mais introuvable (SSD débranché, dossier renommé).
        case communAbsent(URL)
    }

    /// Le dossier commun réglé dans le pointeur (nil : pas de dossier commun). Lu à chaque appel.
    public func dossierCommunRegle() -> URL? {
        guard let attributs = try? FileManager.default.attributesOfItem(atPath: pointeur.path),
              attributs[.type] as? FileAttributeType == .typeRegular,
              let taille = (attributs[.size] as? NSNumber)?.intValue, taille <= 64 * 1024,
              let data = try? Data(contentsOf: pointeur),
              let objet = (try? JSONCoding.parse(String(decoding: data, as: UTF8.self)))?.object else { return nil }
        if let format = objet["format"] {
            guard format.int == Self.formatPointeur else { return nil }
        }
        guard let chemin = objet["dossier"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chemin.isEmpty, chemin.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: chemin, isDirectory: true).standardizedFileURL
    }

    /// L'état, lu à chaque appel.
    public func etat() -> Etat {
        guard let commun = dossierCommunRegle() else { return .local(racineLocale) }
        var dossier: ObjCBool = false
        guard FileManager.default.fileExists(atPath: commun.path, isDirectory: &dossier), dossier.boolValue else {
            return .communAbsent(commun)
        }
        return .commun(commun)
    }

    /// Refus quand le dossier commun réglé est introuvable : le texte du contrat (point 5).
    public struct DossierCommunIntrouvable: Error, LocalizedError, Equatable {
        public let chemin: String
        public var errorDescription: String? { DossierDonnees.texteIntrouvable(chemin) }
    }

    public static func texteIntrouvable(_ chemin: String) -> String {
        "Le dossier commun (\(chemin)) est introuvable : branchez le SSD qui le contient, ou réglez un autre dossier "
            + "dans Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom."
    }

    /// La racine des données : le dossier commun présent, sinon la racine locale ; refus si le
    /// dossier commun réglé est introuvable (jamais de repli sur la racine locale).
    public func racine() throws -> URL {
        switch etat() {
        case .local(let url), .commun(let url): return url
        case .communAbsent(let url): throw DossierCommunIntrouvable(chemin: url.path)
        }
    }

    /// Un élément de la racine des données (`guide-de-style.md`, `Index`…).
    public func url(_ nom: String, dossier: Bool = false) throws -> URL {
        try racine().appendingPathComponent(nom, isDirectory: dossier)
    }

    // MARK: Rebasage

    /// Le repère des chemins enregistrés dans la racine locale d'un Mac (le nom d'utilisateur peut
    /// différer d'un Mac à l'autre).
    static let repereLocal = "/Library/Application Support/Developpeur/"

    /// Un nom de premier niveau fait-il partie des éléments communs ?
    public static func estCommun(_ nom: String) -> Bool {
        elementsCommuns.contains { motif in
            motif.hasSuffix("*") ? nom.hasPrefix(String(motif.dropLast())) : nom == motif
        }
    }

    /// Point 6 du contrat : un chemin enregistré qui contient « /Library/Application Support/Developpeur/ »
    /// suivi d'un élément commun est ramené sur `racine` ; tout autre chemin reste tel quel.
    public static func rebaser(_ chemin: String, sur racine: URL) -> String {
        guard let plage = chemin.range(of: repereLocal, options: .backwards) else { return chemin }
        let reste = String(chemin[plage.upperBound...])
        guard let premier = reste.split(separator: "/", omittingEmptySubsequences: false).first,
              estCommun(String(premier)) else { return chemin }
        return racine.appendingPathComponent(reste).path
    }

    /// Le rebasage sur la racine des données actuelle (refus si le dossier commun est introuvable).
    public func rebaser(_ chemin: String) throws -> String {
        Self.rebaser(chemin, sur: try racine())
    }

    // MARK: Pour get_status et --status

    /// Le bloc `dossier_commun` de get_status.
    public func etatJSON() -> JSONValue {
        switch etat() {
        case .local(let url):
            return ["regle": false, "racine_des_donnees": .string(url.path),
                    "remarque": "Pas de dossier commun : les données restent sur ce Mac (réglage dans le Gestionnaire de modules externes)."]
        case .commun(let url):
            return ["regle": true, "chemin": .string(url.path), "present": true, "racine_des_donnees": .string(url.path)]
        case .communAbsent(let url):
            return ["regle": true, "chemin": .string(url.path), "present": false,
                    "erreur": .string(Self.texteIntrouvable(url.path))]
        }
    }

    /// La ligne de `--status`.
    public func ligneStatut() -> String {
        switch etat() {
        case .local(let url): return "Dossier commun : aucun (données sur ce Mac, \(url.path))"
        case .commun(let url): return "Dossier commun : \(url.path) (présent)"
        case .communAbsent(let url): return "Dossier commun : \(url.path) (ABSENT) ; " + Self.texteIntrouvable(url.path)
        }
    }
}
