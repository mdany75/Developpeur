import Foundation

/// Dernière version publiée sur GitHub (dépôt public mdany75/Developpeur), pour que `--status`
/// signale une mise à jour. La question passe par `gh`, déjà connecté au compte. Sans `gh`, sans
/// connexion ou sans réponse rapide, `--status` n'en dit rien.
public enum MiseAJour {
    public static let depot = "mdany75/Developpeur"
    public static let pageDerniere = "https://github.com/\(depot)/releases/latest"

    /// Lance `gh` avec ces arguments et rend sa sortie, ou nil (absent, échec, délai dépassé).
    public typealias Gh = (_ arguments: [String]) -> String?

    /// Numéro de la dernière Release (« 1.5 » pour le tag v1.5), ou nil.
    public static func derniereVersion(gh: Gh = lancerGh) -> String? {
        guard let sortie = gh(["release", "view", "--repo", depot, "--json", "tagName", "--jq", ".tagName"]) else {
            return nil
        }
        let tag = sortie.trimmingCharacters(in: .whitespacesAndNewlines)
        let numero = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return composantes(numero) == nil ? nil : numero
    }

    /// Ligne « Mise à jour » de `--status`, ou nil quand GitHub n'a pas répondu.
    public static func ligne(installee: String, derniere: String?) -> String? {
        guard let derniere, composantes(installee) != nil else { return nil }
        if plusRecente(derniere, que: installee) {
            return "Mise à jour : la \(derniere) est publiée (\(pageDerniere))"
        }
        if plusRecente(installee, que: derniere) {
            return "Mise à jour : aucune, la dernière publiée est la \(derniere)"
        }
        return "Mise à jour : aucune, la \(derniere) est la dernière publiée"
    }

    /// Compare deux numéros (« 1.4 », « 1.4.1 », « 1.10 ») composante par composante.
    public static func plusRecente(_ a: String, que b: String) -> Bool {
        guard let x = composantes(a), let y = composantes(b) else { return false }
        for i in 0..<max(x.count, y.count) {
            let u = i < x.count ? x[i] : 0, v = i < y.count ? y[i] : 0
            if u != v { return u > v }
        }
        return false
    }

    static func composantes(_ numero: String) -> [Int]? {
        let parties = numero.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parties.isEmpty, parties.allSatisfy({ ($0 ?? -1) >= 0 }) else { return nil }
        return parties.compactMap { $0 }
    }

    /// `gh` du PATH ou de Homebrew, limité à quelques secondes pour ne pas retenir `--status`.
    public static func lancerGh(_ arguments: [String]) -> String? {
        let dossiers = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        guard let chemin = dossiers.map({ "\($0)/gh" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: chemin)
        process.arguments = arguments
        let sortie = Pipe()
        process.standardOutput = sortie
        process.standardError = FileHandle.nullDevice
        let fini = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in fini.signal() }
        do { try process.run() } catch { return nil }
        guard fini.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: sortie.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
