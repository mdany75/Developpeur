import Foundation

/// Un profil à base de « Look » (Adobe Color, CLASSIC Neg., profils créatifs, profils installés
/// par l'utilisateur) : un fichier XMP de type « Look » qui pose une table de couleur sur un
/// profil de base. `look` est la table que Lightroom range dans `Look` (constaté dans le
/// catalogue : nom, UUID, intensité, groupe, puis les paramètres du fichier ; les données des
/// tables, `crs:Table_…`, restent dans le fichier : Lightroom les retrouve par leur empreinte).
public struct LookProfile: Equatable {
    public var name: String
    /// Dossier d'origine : Adobe Raw, Camera, Artistic, B&W, Modern, Vintage, Adaptive ou
    /// « Profils installés ».
    public var folder: String
    public var uuid: String
    /// Appareil auquel le profil est réservé (« Fujifilm X-H2S »), vide pour tous.
    public var cameraRestriction: String
    public var supportsAmount: Bool
    public var monochrome: Bool
    public var look: JSONValue

    /// Profil adaptatif (dossier Adaptive) : ce qui accompagne sa Look dans un paramètre prédéfini
    /// du module, le chemin où Lightroom le calcule (`AILook`) ; nil pour les autres profils. Le
    /// profil de base est celui que Lightroom pose quand on le choisit à la main.
    public var adaptivePreset: JSONValue? {
        folder == "Adaptive" ? ["CameraProfile": "Adobe Standard", "AILook": ["Active": true]] : nil
    }

    /// Le profil convient-il à cet appareil ? Sans restriction : à tous.
    public func matches(make: String?, model: String?) -> Bool {
        LookProfile.restriction(cameraRestriction, matchesMake: make, model: model)
    }

    /// « Fujifilm X-H2S » convient à FUJIFILM X-H2S (même règle que dans le module Lightroom).
    public static func restriction(_ restriction: String, matchesMake make: String?, model: String?) -> Bool {
        let wanted = restriction.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return true }
        guard let model = model?.trimmingCharacters(in: .whitespaces).lowercased(), !model.isEmpty else { return false }
        let brand = (make ?? "").lowercased().split(separator: " ").first.map(String.init) ?? ""
        return wanted == model || (wanted.hasSuffix(" " + model) && (brand.isEmpty || wanted.hasPrefix(brand)))
    }
}

/// Les profils à base de Look installés sur ce Mac, lus une fois puis gardés en mémoire.
public final class LookProfileLibrary {
    public static let lightroomApp = "/Applications/Adobe Lightroom Classic/Adobe Lightroom Classic.app"

    /// Dossiers lus, avec le nom de groupe à donner aux profils de chacun (nil : le premier
    /// sous-dossier, comme « Adobe Raw » ou « Camera »).
    public static var defaultFolders: [(url: URL, group: String?)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            (URL(fileURLWithPath: lightroomApp + "/Contents/Resources/Settings/Adobe/Profiles"), nil),
            (URL(fileURLWithPath: "/Library/Application Support/Adobe/CameraRaw/Settings/Adobe/Profiles"), nil),
            (home.appendingPathComponent("Library/Application Support/Adobe/CameraRaw/Settings"), "Profils installés"),
        ]
    }

    private let folders: [(url: URL, group: String?)]
    private var cache: [LookProfile]?
    private let lock = NSLock()

    public init(folders: [(url: URL, group: String?)] = LookProfileLibrary.defaultFolders) {
        self.folders = folders
    }

    public var profiles: [LookProfile] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        var seen = Set<String>()
        var list: [LookProfile] = []
        let fileManager = FileManager.default
        for folder in folders {
            // Chemins résolus des deux côtés : un dossier temporaire passe par un lien (/var → /private/var).
            let base = folder.url.resolvingSymlinksInPath().path
            guard let walker = fileManager.enumerator(at: folder.url, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension.lowercased() == "xmp" {
                guard let data = try? Data(contentsOf: url) else { continue }
                let path = url.resolvingSymlinksInPath().path
                let relative = (path.hasPrefix(base) ? path.dropFirst(base.count) : Substring(path)).split(separator: "/")
                let group = folder.group ?? (relative.count > 1 ? String(relative[0]) : "Profils")
                guard let profile = LookProfileLibrary.parse(data, folder: group) else { continue }
                if seen.insert(profile.uuid + "|" + profile.cameraRestriction).inserted {
                    list.append(profile)
                }
            }
        }
        list.sort { ($0.folder, $0.name, $0.cameraRestriction) < ($1.folder, $1.name, $1.cameraRestriction) }
        cache = list
        return list
    }

    /// Les profils de ce nom (un par appareil pour les simulations réservées à un appareil).
    public func candidates(named name: String) -> [LookProfile] {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return profiles.filter { $0.name.lowercased() == wanted }
    }

    // MARK: Lecture d'un fichier XMP

    /// Attributs qui décrivent le profil lui-même et ne vont pas dans `Parameters`.
    private static let descriptive: Set<String> = [
        "PresetType", "Cluster", "UUID", "SupportsAmount", "SupportsColor", "SupportsMonochrome",
        "SupportsHighDynamicRange", "SupportsNormalDynamicRange", "SupportsSceneReferred",
        "SupportsOutputReferred", "CameraModelRestriction", "Copyright", "ContactInfo", "HasSettings",
        "RequiresRGBTables", "Name", "ShortName", "SortName", "Group", "Description",
    ]

    /// Lit un fichier XMP de profil ; nil si ce n'est pas un profil à base de Look.
    public static func parse(_ data: Data, folder: String) -> LookProfile? {
        let reader = XMPReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), reader.attributes["PresetType"] == "Look",
              let name = reader.texts["Name"], !name.isEmpty,
              let uuid = reader.attributes["UUID"], !uuid.isEmpty else { return nil }

        var parameters: [String: JSONValue] = [:]
        for (key, value) in reader.attributes where !descriptive.contains(key) && !key.hasPrefix("Table_") {
            parameters[key] = convert(key, value)
        }
        for (key, points) in reader.curves { parameters[key] = .array(points.map(JSONValue.number)) }

        let flag = { (key: String) in reader.attributes[key]?.lowercased() == "true" }
        var look: JSONValue = [
            "Name": .string(name),
            "UUID": .string(uuid),
            "Amount": 1,
            "Copyright": .string(reader.attributes["Copyright"] ?? ""),
            "Group": ["x-default": .string(reader.texts["Group"] ?? "Profiles")],
            "SupportsAmount": .bool(flag("SupportsAmount")),
            "SupportsMonochrome": .bool(flag("SupportsMonochrome")),
            "SupportsOutputReferred": .bool(flag("SupportsOutputReferred")),
            "Parameters": .object(parameters),
        ]
        // Profil adaptatif : la Look telle que Lightroom la range quand on le choisit à la main.
        // Sans isAdobeAdaptive, Lightroom ne marque pas la photo « à mettre à jour » et ne le
        // calcule jamais (constaté dans Lightroom Classic 15.6).
        if folder == "Adaptive", case .object(var fields) = look {
            fields["isAdobeAdaptive"] = true
            fields["Cluster"] = .string(reader.attributes["Cluster"] ?? "Adobe")
            look = .object(fields)
        }
        return LookProfile(name: name, folder: folder, uuid: uuid,
                           cameraRestriction: reader.attributes["CameraModelRestriction"] ?? "",
                           supportsAmount: flag("SupportsAmount"),
                           monochrome: parameters["ConvertToGrayscale"]?.bool ?? false,
                           look: look)
    }

    /// Valeur d'un attribut : booléen, nombre, ou texte pour les versions, noms et empreintes
    /// (`CameraProfile`, `LookTable`, `RGBTable`). `RGBTables`, `ProfileGainTableMap` (profils
    /// adaptatifs) et `RGBTableAmount` (profils créatifs) sont des nombres : en texte, Lightroom
    /// les écarte de la Look (constaté dans Lightroom Classic 15.6 sur Adaptive Color).
    private static func convert(_ key: String, _ value: String) -> JSONValue {
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: break
        }
        let textual = key == "CameraProfile" || key.hasSuffix("Table")
            || ["Version", "Digest", "Name", "Mode", "Setup"].contains(where: { key.contains($0) })
        if !textual, let number = Double(value.trimmingCharacters(in: .whitespaces)) {
            return .number(number)
        }
        return .string(value)
    }
}

/// Lecteur minimal des fichiers XMP de profil : attributs `crs:` de la description, textes par
/// défaut des propriétés à langues (`crs:Name`, `crs:Group`), et courbes (`crs:ToneCurvePV2012…`).
private final class XMPReader: NSObject, XMLParserDelegate {
    var attributes: [String: String] = [:]
    var texts: [String: String] = [:]
    var curves: [String: [Double]] = [:]

    private var property: String?
    private var defaultLanguage = false
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if name == "rdf:Description" {
            for (key, value) in attributeDict where key.hasPrefix("crs:") {
                attributes[String(key.dropFirst(4))] = value
            }
        } else if name.hasPrefix("crs:") {
            property = String(name.dropFirst(4))
        } else if name == "rdf:li" {
            text = ""
            defaultLanguage = attributeDict["xml:lang"] == "x-default"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "rdf:li", let property {
            if property.hasPrefix("ToneCurvePV2012") {
                let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                curves[property, default: []] += values
            } else if defaultLanguage {
                texts[property] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if name.hasPrefix("crs:"), String(name.dropFirst(4)) == property {
            property = nil
        }
    }
}
