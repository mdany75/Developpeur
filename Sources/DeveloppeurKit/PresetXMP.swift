import Foundation

/// Écrit un paramètre prédéfini de développement au format XMP de Camera Raw, comme ceux
/// d'Adobe : Lightroom Classic lit les paramètres prédéfinis de l'utilisateur dans
/// ~/Library/Application Support/Adobe/CameraRaw/Settings et les montre au lancement suivant.
/// (Ceux qu'un module externe crée par le SDK restent invisibles dans le panneau.)
public enum PresetXMP {
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Adobe/CameraRaw/Settings/Claude")
    }

    /// Ce qui ne s'écrit pas dans un paramètre prédéfini (masques, taches, couleurs ponctuelles).
    static let unsupported: Set<String> = ["MaskGroupBasedCorrections", "RetouchAreas", "RetouchInfo", "RedEyeInfo", "PointColors"]

    /// Écrit le fichier et renvoie son chemin, avec les clés laissées de côté.
    public static func write(name: String, settings: [String: JSONValue], folder: URL = defaultFolder,
                             uuid: String = PresetXMP.newUUID()) throws -> (url: URL, skipped: [String]) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileName = name.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        let url = folder.appendingPathComponent(fileName).appendingPathExtension("xmp")
        let (text, skipped) = document(name: name, settings: settings, uuid: uuid)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return (url, skipped)
    }

    public static func newUUID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    static func document(name: String, settings: [String: JSONValue], uuid: String) -> (text: String, skipped: [String]) {
        var skipped: [String] = []
        var attributes: [(String, String)] = [
            ("PresetType", "Normal"), ("Cluster", ""), ("UUID", uuid), ("SupportsAmount", "False"),
            ("SupportsColor", "True"), ("SupportsMonochrome", "True"), ("SupportsHighDynamicRange", "True"),
            ("SupportsNormalDynamicRange", "True"), ("SupportsSceneReferred", "True"), ("SupportsOutputReferred", "True"),
            ("RequiresRGBTables", "False"), ("CameraModelRestriction", ""), ("Copyright", ""), ("ContactInfo", ""),
            ("Version", "16.4"), ("ProcessVersion", settings["ProcessVersion"]?.string ?? "15.4"), ("HasSettings", "True"),
        ]
        var elements: [String] = [
            alt("Name", name), alt("ShortName", name), alt("SortName", name), alt("Group", "Claude"),
            alt("Description", "Créé par Développeur."),
        ]
        let crop = ["CropLeft", "CropTop", "CropRight", "CropBottom"].compactMap { settings[$0]?.double }
        if crop.count == 4, crop != [0, 0, 1, 1] || (settings["CropAngle"]?.double ?? 0) != 0 {
            attributes.append(("HasCrop", "True"))
        }
        for key in settings.keys.sorted() where key != "ProcessVersion" {
            let value = settings[key]!
            if unsupported.contains(key) {
                skipped.append(key)
            } else if key == "Look" {
                if let look = value.object, !look.isEmpty { elements.append(lookElement(look)) }
            } else if key.hasPrefix("ToneCurvePV2012"), let points = value.array {
                elements.append(curve(key, points))
            } else if let scalar = scalar(value) {
                attributes.append((key, scalar))
            } else {
                skipped.append(key)
            }
        }
        let attributeText = attributes.map { "   crs:\($0.0)=\"\(escape($0.1))\"" }.joined(separator: "\n")
        let text = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Développeur">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
        \(attributeText)>
        \(elements.joined(separator: "\n"))
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>

        """
        return (text, skipped)
    }

    static func scalar(_ value: JSONValue) -> String? {
        if let bool = value.bool { return bool ? "True" : "False" }
        if let number = value.double { return DevelopCatalogue.format(number) }
        if let string = value.string { return string }
        return nil
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func alt(_ key: String, _ text: String) -> String {
        "   <crs:\(key)>\n    <rdf:Alt>\n     <rdf:li xml:lang=\"x-default\">\(escape(text))</rdf:li>\n    </rdf:Alt>\n   </crs:\(key)>"
    }

    private static func curve(_ key: String, _ values: [JSONValue]) -> String {
        let numbers = values.compactMap(\.double)
        var items: [String] = []
        var index = 0
        while index + 1 < numbers.count {
            items.append("     <rdf:li>\(DevelopCatalogue.format(numbers[index])), \(DevelopCatalogue.format(numbers[index + 1]))</rdf:li>")
            index += 2
        }
        return "   <crs:\(key)>\n    <rdf:Seq>\n\(items.joined(separator: "\n"))\n    </rdf:Seq>\n   </crs:\(key)>"
    }

    /// La Look du profil, comme dans les fichiers XMP de Camera Raw : nom, intensité, UUID, puis
    /// ses paramètres dans une description imbriquée.
    private static func lookElement(_ look: [String: JSONValue]) -> String {
        var attributes: [String] = []
        for key in ["Name", "Amount", "UUID", "SupportsAmount", "SupportsMonochrome", "SupportsOutputReferred", "Copyright"] {
            if let value = look[key], let text = scalar(value) { attributes.append("crs:\(key)=\"\(escape(text))\"") }
        }
        var parameterAttributes: [String] = []
        var curves: [String] = []
        for (key, value) in (look["Parameters"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            if key.hasPrefix("ToneCurvePV2012"), let points = value.array {
                curves.append(curve(key, points).replacingOccurrences(of: "\n", with: "\n    "))
            } else if let text = scalar(value) {
                parameterAttributes.append("crs:\(key)=\"\(escape(text))\"")
            }
        }
        let group = look["Group"]?["x-default"]?.string ?? "Profiles"
        return """
           <crs:Look>
            <rdf:Description \(attributes.joined(separator: " "))>
             <crs:Group>
              <rdf:Alt>
               <rdf:li xml:lang="x-default">\(escape(group))</rdf:li>
              </rdf:Alt>
             </crs:Group>
             <crs:Parameters>
              <rdf:Description \(parameterAttributes.joined(separator: " "))>
        \(curves.joined(separator: "\n"))
              </rdf:Description>
             </crs:Parameters>
            </rdf:Description>
           </crs:Look>
        """
    }
}
