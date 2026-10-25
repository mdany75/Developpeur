import CoreGraphics
import Foundation
import ImageIO
@testable import DeveloppeurKit

/// Faux module Lightroom pour les tests des outils : note chaque commande et renvoie la
/// réponse préparée (ou lève l'erreur préparée).
final class FakeLightroom: LightroomServing {
    struct Call {
        var command: String
        var params: [String: JSONValue]
        var timeout: TimeInterval
    }

    /// Les outils appellent le module depuis la file du serveur, les tests lisent depuis le leur.
    private let verrou = NSLock()
    private var appels: [Call] = []
    var calls: [Call] {
        get { verrou.lock(); defer { verrou.unlock() }; return appels }
        set { verrou.lock(); appels = newValue; verrou.unlock() }
    }
    var replies: [String: JSONValue] = [:]
    var errors: [String: Error] = [:]
    /// Appelé avant de répondre (par exemple pour écrire le fichier d'aperçu).
    var onSend: ((String, [String: JSONValue]) -> Void)?
    /// Version que le module donnerait au ping (nil : module d'avant la 2.0).
    var moduleVersion: String?

    /// Commandes notées à part, pour que les tests des outils voient les mêmes commandes qu'avant
    /// elles : la barre de progression de Lightroom (« progression »), et le registre de la 1.3
    /// rangé hors du catalogue, le carnet de progrès (« carnet » ; la leçon de la photo, « lecon »,
    /// est retirée en 1.3.6). Une réponse ou une erreur préparée vaut pour elles aussi ; `onSend` ne
    /// les voit pas (préparer leur réponse dans `replies` avant l'appel).
    static let commandesAPart: Set<String> = ["progression", "carnet"]
    private var notesAPart: [String: [[String: JSONValue]]] = [:]
    private func aPart(_ command: String) -> [[String: JSONValue]] {
        verrou.lock(); defer { verrou.unlock() }; return notesAPart[command] ?? []
    }
    var progressions: [[String: JSONValue]] { aPart("progression") }
    var carnets: [[String: JSONValue]] { aPart("carnet") }

    func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue {
        verrou.lock()
        if Self.commandesAPart.contains(command) {
            notesAPart[command, default: []].append(params)
            verrou.unlock()
            if let error = errors[command] { throw error }
            return replies[command] ?? [:]
        }
        appels.append(Call(command: command, params: params, timeout: timeout))
        verrou.unlock()
        onSend?(command, params)
        if let error = errors[command] { throw error }
        return replies[command] ?? [:]
    }

    var lastParams: [String: JSONValue] { calls.last?.params ?? [:] }
    var commands: [String] { calls.map(\.command) }
}

enum TestSupport {
    static func makeServer(_ lightroom: LightroomServing, guide: GuideStyle? = nil) -> MCPServer {
        let guideStyle = guide ?? GuideStyle(fichier: temporaryDirectory().appendingPathComponent("guide-de-style.md"))
        return MCPServer(name: "test", version: "0.0", instructions: "consignes", tools: ToolHandler(lightroom: lightroom, guideStyle: guideStyle))
    }

    /// JPEG uni de la couleur donnée (composantes de 0 à 255).
    static func jpeg(red: UInt8, green: UInt8, blue: UInt8, width: Int = 300, height: Int = 200) -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = red
            pixels[i * 4 + 1] = green
            pixels[i * 4 + 2] = blue
            pixels[i * 4 + 3] = 255
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    /// Image sRGB sans compression dont chaque pixel prend la couleur donnée pour (x, y), depuis le
    /// coin haut gauche : un aperçu de synthèse à plusieurs zones (deux lumières, un visage…).
    static func imagePixels(width: Int = 300, height: Int = 200, _ couleur: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                (pixels[i], pixels[i + 1], pixels[i + 2]) = couleur(x, y)
            }
        }
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }!
    }

    /// La même image en JPEG, comme les aperçus du module.
    static func jpegPixels(width: Int = 300, height: Int = 200, quality: Double = 1.0,
                           _ couleur: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8)) -> Data {
        PreviewImages.jpeg(imagePixels(width: width, height: height, couleur), quality: quality)!
    }

    /// Écrit un aperçu dans son propre dossier temporaire, comme le module, et renvoie son chemin.
    static func previewFile(_ data: Data) -> String {
        let folder = temporaryDirectory().appendingPathComponent("apercu-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("photo.jpg")
        try? data.write(to: file)
        return file.path
    }

    /// Fichier XMP de profil à base de Look, comme ceux de Lightroom.
    static func lookXMP(name: String, uuid: String, restriction: String = "", amount: Bool = false, grayscale: Bool = false,
                        cameraProfile: String? = "Adobe Standard", extra: String = "") -> String {
        let name = name.replacingOccurrences(of: "&", with: "&amp;")
        let base = cameraProfile.map { "crs:CameraProfile=\"\($0)\" " } ?? ""
        return """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           crs:PresetType="Look" crs:UUID="\(uuid)" crs:SupportsAmount="\(amount ? "True" : "False")"
           crs:SupportsMonochrome="False" crs:SupportsOutputReferred="False"
           crs:CameraModelRestriction="\(restriction)" crs:Copyright="© Adobe" crs:Version="10.3"
           crs:ProcessVersion="10.0" crs:ConvertToGrayscale="\(grayscale ? "True" : "False")"
           \(base)crs:LookTable="E1095149FDB39D7A057BAB208837E2E1" \(extra)
           crs:Table_E1095149FDB39D7A057BAB208837E2E1="données" crs:HasSettings="True">
           <crs:Name><rdf:Alt><rdf:li xml:lang="x-default">\(name)</rdf:li></rdf:Alt></crs:Name>
           <crs:Group><rdf:Alt><rdf:li xml:lang="x-default">Profiles</rdf:li></rdf:Alt></crs:Group>
           <crs:ToneCurvePV2012><rdf:Seq><rdf:li>0, 0</rdf:li><rdf:li>22, 16</rdf:li><rdf:li>255, 255</rdf:li></rdf:Seq></crs:ToneCurvePV2012>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """
    }

    /// Bibliothèque de profils d'essai : Adobe Color, une simulation par appareil, un profil créatif,
    /// un profil adaptatif et un profil installé par l'utilisateur.
    static func lookLibrary() -> LookProfileLibrary {
        let root = temporaryDirectory()
        let profiles = root.appendingPathComponent("Profiles")
        let user = root.appendingPathComponent("Utilisateur")
        let files: [(URL, String)] = [
            (profiles.appendingPathComponent("Adobe Raw/Adobe Color.xmp"), lookXMP(name: "Adobe Color", uuid: "B952C231111CD8E0ECCF14B86BAA7077")),
            (profiles.appendingPathComponent("Adobe Raw/Adobe Monochrome.xmp"), lookXMP(name: "Adobe Monochrome", uuid: "0D5D0F0B", grayscale: true)),
            (profiles.appendingPathComponent("Camera/Fujifilm/X-H2S/Classic Neg.xmp"), lookXMP(name: "Camera CLASSIC Neg", uuid: "3930CB63", restriction: "Fujifilm X-H2S")),
            (profiles.appendingPathComponent("Camera/Fujifilm/X-T5/Classic Neg.xmp"), lookXMP(name: "Camera CLASSIC Neg", uuid: "4040AA00", restriction: "Fujifilm X-T5")),
            (profiles.appendingPathComponent("B&W/BW 01.xmp"), lookXMP(name: "B&W 01", uuid: "AAAA0001", amount: true, grayscale: true,
                extra: "crs:RGBTable=\"5B2F\" crs:RGBTableAmount=\"0.5\"")),
            (profiles.appendingPathComponent("Adaptive/Adaptive Color.xmp"), lookXMP(name: "Adaptive Color", uuid: "226E6263ED94405B973B41F5A6E67BE9", amount: true,
                cameraProfile: nil, extra: "crs:Cluster=\"Adobe\" crs:ProfileGainTableMap=\"100\" crs:RGBTables=\"100\"")),
            (user.appendingPathComponent("Mon profil.xmp"), lookXMP(name: "Mon profil", uuid: "CCCC0001", amount: true)),
            (user.appendingPathComponent("Preset.xmp"), "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" crs:PresetType=\"Normal\" crs:UUID=\"DDDD\"/></rdf:RDF></x:xmpmeta>"),
        ]
        for (url, text) in files {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        return LookProfileLibrary(folders: [(profiles, nil), (user, "Profils installés")])
    }

    /// Effets locaux d'essai : deux de l'utilisateur (dont le blanchiment des dents, sous son nom
    /// français), et ceux livrés avec Lightroom, dont le même blanchiment, à ne pas répéter.
    static func localEffects() -> LocalEffectLibrary {
        let root = temporaryDirectory()
        let user = root.appendingPathComponent("Local Adjustment Presets")
        let app = root.appendingPathComponent("localized_presets")
        func template(_ internalName: String?, _ values: String) -> String {
            "s = {\n\tid = \"5D68DBAD\",\n" + (internalName.map { "\tinternalName = \"\($0)\",\n\ttitle = ZSTR \"$$$/AgDevelop/Localized/Preset/X=\($0)\",\n" } ?? "\ttitle = \"Mon effet\",\n")
                + "\ttype = \"LocalizedAdjustmentPreset\",\n\tvalue = {\n\(values)\n\t},\n\tversion = 1,\n}\n"
        }
        let teeth = template("Teeth Whitening", "\t\tclarity = 0,\n\t\texposure = 0.1034480035305,\n\t\texposure2012 = 0.10000000149012,\n\t\tsaturation = -0.60000002384186,\n\t\ttoningHue = 233,\n\t\ttoningSaturation = 0,")
        let files: [(URL, String)] = [
            (user.appendingPathComponent("Blanchissement des dents.lrtemplate"), teeth),
            (user.appendingPathComponent("Peau douce maison.lrtemplate"), template(nil, "\t\ttexture = -0.35,\n\t\tclarity2012 = -0.15,\n\t\ttoningHue = 30,\n\t\ttoningSaturation = 0.1,")),
            (user.appendingPathComponent("Notes.txt"), "pas un effet"),
            (app.appendingPathComponent("TeethWhitening.lrtemplate"), teeth),
            (app.appendingPathComponent("IrisEnhance.lrtemplate"), template("Iris Enhance", "\t\tclarity2012 = 0.10000000149012,\n\t\texposure2012 = 0.087499998509884,\n\t\tsaturation = 0.40000000596046,")),
        ]
        for (url, text) in files {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        return LocalEffectLibrary(folders: [user, app])
    }

    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-developpeur-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
