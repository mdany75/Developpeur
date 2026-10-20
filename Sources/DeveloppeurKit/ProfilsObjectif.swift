import Foundation

/// Un profil d'objectif de Camera Raw (fichier .lcp, XMP) : ce que Lightroom range quand on le
/// choisit à la main (relevé le 17 octobre 2026 dans Lightroom Classic 15.6) : `LensProfileName` =
/// `ProfileName` du fichier (« Adobe (Fujifilm FUJINON 55mm f/1.8 M42) »), `LensProfileFilename` =
/// le nom du fichier, `LensProfileSetup = Custom`.
public struct LensProfile: Equatable {
    public var name: String
    public var lens: String
    public var make: String
    /// Profil pour les RAW (`CameraRawProfile`), sinon pour les JPEG.
    public var raw: Bool
    public var fileName: String
}

/// Les profils d'objectif installés : ceux livrés avec Lightroom, ceux de Camera Raw et ceux de
/// l'utilisateur (Lens Profile Creator), lus une fois ; un même fichier n'est compté qu'une fois
/// (l'utilisateur d'abord).
public final class LensProfileLibrary {
    let folders: [URL]
    private var cache: [LensProfile]?

    public static var defaultFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Adobe/CameraRaw/LensProfiles/1.0"),
            URL(fileURLWithPath: "/Library/Application Support/Adobe/CameraRaw/LensProfiles/1.0"),
            URL(fileURLWithPath: "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app/Contents/Resources/LensProfiles/1.0"),
        ]
    }

    public init(folders: [URL] = LensProfileLibrary.defaultFolders) {
        self.folders = folders
    }

    public var profiles: [LensProfile] {
        if let cache { return cache }
        var seen = Set<String>(), list: [LensProfile] = []
        let manager = FileManager.default
        for folder in folders {
            guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lcp" {
                let fileName = url.lastPathComponent
                guard !seen.contains(fileName.lowercased()), let profile = Self.read(url) else { continue }
                seen.insert(fileName.lowercased())
                list.append(profile)
            }
        }
        cache = list.sorted { ($0.make, $0.lens, $0.name) < ($1.make, $1.lens, $1.name) }
        return cache!
    }

    /// Lit l'en-tête d'un fichier .lcp : marque, objectif, nom du profil, RAW ou non. Les attributs
    /// se répètent pour chaque focale ; le premier suffit.
    static func read(_ url: URL) -> LensProfile? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        func value(_ key: String) -> String? {
            for pattern in ["stCamera:\(key)=\"([^\"]*)\"", "<stCamera:\(key)>([^<]*)</stCamera:\(key)>"] {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let inner = Range(match.range(at: 1), in: text) else { continue }
                return String(text[inner]).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            }
            return nil
        }
        guard let name = value("ProfileName") else { return nil }
        return LensProfile(name: name, lens: value("LensPrettyName") ?? value("Lens") ?? name, make: value("Make") ?? "",
                           raw: value("CameraRawProfile")?.lowercased() == "true", fileName: url.lastPathComponent)
    }

    /// Le profil désigné par son nom (ProfileName), son objectif ou son fichier, sans la casse ; pour
    /// une photo RAW ou non, celui de ce genre d'abord. Plusieurs : nil et les noms en double.
    public func find(_ text: String, raw: Bool?) -> (profile: LensProfile?, ambiguous: [String]) {
        let wanted = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let byName = profiles.filter { $0.name.lowercased() == wanted || $0.fileName.lowercased() == wanted }
        let candidates = byName.isEmpty ? profiles.filter { $0.lens.lowercased() == wanted } : byName
        let fitting = raw.map { kind in candidates.filter { $0.raw == kind } } ?? candidates
        let pool = fitting.isEmpty ? candidates : fitting
        if pool.count == 1 { return (pool[0], []) }
        if pool.count > 1, Set(pool.map(\.name)).count == 1 { return (pool[0], []) }
        return (nil, pool.map { "\($0.name) (\($0.fileName))" })
    }

    /// Profils dont la marque, l'objectif ou le nom contient le texte cherché.
    public func search(_ query: String, limit: Int = 40) -> [LensProfile] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return Array(profiles.filter { profile in
            let text = "\(profile.make) \(profile.lens) \(profile.name)".lowercased()
            return words.allSatisfy { text.contains($0) }
        }.prefix(limit))
    }
}
