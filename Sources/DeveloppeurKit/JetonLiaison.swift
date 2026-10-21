import Foundation

/// Jeton privé de la liaison (liaison fermée, 1.2). Le module Lightroom le tire au hasard à chaque
/// démarrage de la liaison et l'écrit dans `~/Library/Application Support/Developpeur/liaison.jeton`
/// (64 chiffres hexadécimaux, droits 600) ; `LightroomBridge` le relit à chaque connexion et le
/// met dans chaque ligne. Le serveur ne crée jamais ce fichier, et ne rend jamais la valeur du
/// jeton : ni journal, ni configuration, ni réponse.
public enum JetonLiaison {
    /// Nom du fichier, le même que `Liaison.FICHIER_JETON` du module.
    public static let nomFichier = "liaison.jeton"
    /// Un fichier plus gros n'est pas lu : ce n'est pas un jeton.
    static let tailleMax = 1024

    /// Le fichier que le module écrit, à côté de l'exécutable installé.
    public static func fichierParDefaut(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Developpeur/\(nomFichier)")
    }

    /// Le jeton rangé dans le fichier : exactement 64 chiffres hexadécimaux en minuscules, blancs
    /// du bout retirés (le module finit par un saut de ligne). nil : fichier absent, illisible,
    /// trop gros ou mal formé, ou autre chose qu'un fichier ordinaire (le module le range par mv :
    /// ni lien, ni dossier, ni tube nommé) : genre et taille se vérifient avant la lecture, qui ne
    /// charge jamais un gros fichier.
    public static func lire(_ url: URL) -> String? {
        guard let attributs = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributs[.type] as? FileAttributeType == .typeRegular,
              let taille = (attributs[.size] as? NSNumber)?.intValue, taille <= tailleMax,
              let data = try? Data(contentsOf: url), data.count <= tailleMax,
              let texte = String(data: data, encoding: .utf8) else { return nil }
        let jeton = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard jeton.utf8.count == 64, jeton.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return jeton
    }

    /// L'état du fichier pour `--status`, sans jamais la valeur du jeton.
    public static func etat(_ url: URL) -> String {
        let chemin = url.path
        guard FileManager.default.fileExists(atPath: chemin) else {
            return "absent (\(chemin)) : le module 1.2 le crée en démarrant la liaison"
        }
        guard lire(url) != nil,
              let droits = (try? FileManager.default.attributesOfItem(atPath: chemin))?[.posixPermissions] as? NSNumber else {
            return "illisible ou mal formé (\(chemin)) : relancer la liaison dans Lightroom"
        }
        let permissions = droits.intValue
        if permissions & 0o077 == 0 {
            return "présent, lisible par vous seul"
        }
        return "présent, mais lisible par d'autres comptes (droits \(String(permissions & 0o777, radix: 8))) : "
            + "relancer la liaison dans Lightroom, qui le réécrit en 600"
    }
}
