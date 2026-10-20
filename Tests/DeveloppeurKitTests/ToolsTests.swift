import ImageIO
import XCTest
@testable import DeveloppeurKit

final class ToolsTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary())
    }

    // MARK: apply_settings

    func testApplySendsValuesRangesAndLabelsForActivePhoto() throws {
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 12, "fichier": "DSC_0412.NEF"],
                                                    "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.35]]]]]
        let result = tools.call(name: "apply_settings", arguments: [
            "settings": ["Exposure2012": 0.35, "Highlights2012": -40],
            "step_name": "passe 1 : lumière et couleur",
        ])
        XCTAssertFalse(result.isError, result.text)

        let call = try XCTUnwrap(fake.calls.last)
        XCTAssertEqual(call.command, "appliquer")
        XCTAssertEqual(call.params["reglages"], ["Exposure2012": 0.35, "Highlights2012": -40])
        XCTAssertEqual(call.params["plages"]?["Exposure2012"], [-5, 5])
        XCTAssertEqual(call.params["libelles"]?["Highlights2012"]?.string, "Hautes lumières")
        XCTAssertEqual(call.params["etape"]?.string, "passe 1 : lumière et couleur")
        XCTAssertEqual(call.params["relatif"]?.bool, false)
        XCTAssertEqual(call.params["confirme"]?.bool, false)
        XCTAssertNil(call.params["photos"])
        XCTAssertNil(call.params["selection"])

        // Le libellé français est ajouté à chaque changement.
        let reply = try JSONCoding.parse(result.text)
        XCTAssertEqual(reply["resultats"]?.array?.first?["changements"]?.array?.first?["libelle"]?.string, "Exposition")
    }

    func testApplyClampsAbsoluteValuesButLeavesTemperatureToThePlugin() throws {
        let result = tools.call(name: "apply_settings", arguments: [
            "settings": ["Shadows2012": 140, "Temperature": 5650, "Tint": 12],
            "step_name": "test",
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["reglages"], ["Shadows2012": 100, "Temperature": 5650, "Tint": 12])
        XCTAssertTrue(result.text.contains("Shadows2012 : 140 ramené à 100"), result.text)
    }

    func testApplyRelativeIsNotClampedHere() {
        _ = tools.call(name: "apply_settings", arguments: [
            "settings": ["SplitToningShadowSaturation": -10, "Exposure2012": 0.3],
            "step_name": "série", "relative": true, "selection": true, "confirm": true,
        ])
        XCTAssertEqual(fake.lastParams["reglages"], ["SplitToningShadowSaturation": -10, "Exposure2012": 0.3])
        XCTAssertEqual(fake.lastParams["relatif"]?.bool, true)
        XCTAssertEqual(fake.lastParams["selection"]?.bool, true)
        XCTAssertEqual(fake.lastParams["confirme"]?.bool, true)
    }

    func testApplyTargetsPhotoIDs() {
        _ = tools.call(name: "apply_settings", arguments: [
            "settings": ["Vibrance": 12], "step_name": "x", "photo_ids": [3, "7"], "selection": true,
        ])
        XCTAssertEqual(fake.lastParams["photos"], [3, 7])
        XCTAssertNil(fake.lastParams["selection"])
    }

    func testUnknownTopLevelParametersAreRefused() {
        // photo_id à un outil à photo_ids visait la photo active sans un mot.
        let mal = tools.call(name: "apply_settings", arguments: ["settings": ["Vibrance": 12], "step_name": "x", "photo_id": 7])
        XCTAssertTrue(mal.isError)
        XCTAssertTrue(mal.text.contains("Paramètres inconnus pour apply_settings : photo_id (ici : « photo_ids »)"), mal.text)
        XCTAssertNil(fake.lastParams["reglages"], "rien n'est parti vers le module")
        let inverse = tools.call(name: "view_photo", arguments: ["photo_ids": [7]])
        XCTAssertTrue(inverse.isError && inverse.text.contains("photo_ids (ici : « photo_id »)"), inverse.text)
        XCTAssertFalse(tools.call(name: "apply_settings", arguments: ["settings": ["Vibrance": 12], "step_name": "x", "photo_ids": [7]]).isError)
    }

    func testApplyRejectsUnknownKeysBadValuesAndBadSwitches() {
        let unknown = tools.call(name: "apply_settings", arguments: ["settings": ["Exposure": 1], "step_name": "x"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("Réglages inconnus : Exposure."), unknown.text)

        let text = tools.call(name: "apply_settings", arguments: ["settings": ["Vibrance": "beaucoup"], "step_name": "x"])
        XCTAssertTrue(text.isError)

        let empty = tools.call(name: "apply_settings", arguments: ["settings": [:], "step_name": "x"])
        XCTAssertTrue(empty.isError)

        let switchValue = tools.call(name: "apply_settings", arguments: ["settings": ["LensProfileEnable": 0.5], "step_name": "x"])
        XCTAssertTrue(switchValue.isError)

        let badIDs = tools.call(name: "apply_settings", arguments: ["settings": ["Vibrance": 5], "step_name": "x", "photo_ids": ["abc"]])
        XCTAssertTrue(badIDs.isError)
        XCTAssertTrue(fake.calls.isEmpty, "rien ne doit partir vers Lightroom")
    }

    func testApplyProfileAlone() throws {
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 4], "changements": [["cle": "CameraProfile", "avant": "Adobe Color", "apres": "Camera Velvia/Vivid"]]]]]
        let result = tools.call(name: "apply_settings", arguments: ["profile": "camera velvia/vivid", "step_name": "profil"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["profil"]?.string, "Camera Velvia/Vivid", "nom exact de Lightroom")
        XCTAssertEqual(fake.lastParams["profil_marque"]?.string, "FUJIFILM")
        XCTAssertEqual(fake.lastParams["reglages"], [:])
        XCTAssertEqual(fake.lastParams["libelles"]?["CameraProfile"]?.string, "Profil")
        XCTAssertNil(fake.lastParams["recadrage"])
        let reply = try JSONCoding.parse(result.text)
        XCTAssertEqual(reply["resultats"]?.array?.first?["changements"]?.array?.first?["libelle"]?.string, "Profil")

        XCTAssertNil(fake.lastParams["profil_variantes"], "une seule orthographe")

        _ = tools.call(name: "apply_settings", arguments: ["profile": "Adobe Standard", "settings": ["Vibrance": 10], "step_name": "x"])
        XCTAssertNil(fake.lastParams["profil_marque"], "Adobe Standard : toutes marques")

        // L'ancienne orthographe désigne le même profil ; le module essaie l'autre si Lightroom ne
        // garde pas la première.
        _ = tools.call(name: "apply_settings", arguments: ["profile": "Camera PRO Neg. Hi", "step_name": "x"])
        XCTAssertEqual(fake.lastParams["profil"]?.string, "Camera Pro Neg Hi", "le nom que Lightroom range pour un X-H2S")
        XCTAssertEqual(fake.lastParams["profil_variantes"], ["Camera PRO Neg. Hi"])
        _ = tools.call(name: "apply_settings", arguments: ["profile": "Camera MONOCHROME+Ye FILTER", "step_name": "x"])
        XCTAssertEqual(fake.lastParams["profil"]?.string, "Camera Monochrome+Ye Filter")

        let unknown = tools.call(name: "apply_settings", arguments: ["profile": "Adobe Couleur", "step_name": "x"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.hasPrefix("Profil inconnu : \"Adobe Couleur\"."), unknown.text)
    }

    func testApplyCropDefaultsAspectAndReset() throws {
        _ = tools.call(name: "apply_settings", arguments: ["crop": ["angle": -1.2], "step_name": "horizon"])
        XCTAssertEqual(fake.lastParams["recadrage"], ["angle": -1.2, "taille": 1], "sans centre donné : le module le place")
        XCTAssertEqual(fake.lastParams["libelles"]?["CropLeft"]?.string, "Recadrage : bord gauche")

        _ = tools.call(name: "apply_settings", arguments: ["crop": ["aspect": "4:5", "size": 0.9, "center_x": 0.4], "step_name": "x"])
        XCTAssertEqual(fake.lastParams["recadrage"]?["ratio"]?.double, 0.8)
        XCTAssertEqual(fake.lastParams["recadrage"]?["taille"]?.double, 0.9)
        XCTAssertEqual(fake.lastParams["recadrage"]?["centre_x"]?.double, 0.4)
        XCTAssertNil(fake.lastParams["recadrage"]?["centre_y"], "seul l'axe donné est fixé")

        _ = tools.call(name: "apply_settings", arguments: ["crop": ["aspect": "original"], "step_name": "x"])
        XCTAssertNil(fake.lastParams["recadrage"]?["ratio"], "original : ratio de la photo, calculé par le module")

        _ = tools.call(name: "apply_settings", arguments: ["crop": ["reset": true], "step_name": "x"])
        XCTAssertEqual(fake.lastParams["recadrage"], ["retirer": true])

        XCTAssertEqual(try ToolHandler.aspectRatio("16x9"), 16.0 / 9.0)
        XCTAssertEqual(try ToolHandler.aspectRatio(" 1,91 : 1 "), 1.91)
        XCTAssertNil(try ToolHandler.aspectRatio("Original"))
        XCTAssertThrowsError(try ToolHandler.aspectRatio("carré"))
        XCTAssertThrowsError(try ToolHandler.aspectRatio("1:0"))
        XCTAssertThrowsError(try ToolHandler.aspectRatio("50:1"), "hors de la plage 0,1 à 10")
    }

    func testApplyRejectsBadCropAndWholeValues() {
        let count = fake.calls.count
        for crop: JSONValue in [["angle": 60], ["size": 0], ["center_x": 1.5], ["aspect": 4], ["zoom": 2], "4:5"] {
            let result = tools.call(name: "apply_settings", arguments: ["crop": crop, "step_name": "x"])
            XCTAssertTrue(result.isError, "\(crop)")
        }
        let upright = tools.call(name: "apply_settings", arguments: ["settings": ["PerspectiveUpright": 1.5], "step_name": "x"])
        XCTAssertTrue(upright.isError)
        XCTAssertTrue(upright.text.contains("nombre entier"), upright.text)
        let nothing = tools.call(name: "apply_settings", arguments: ["step_name": "x"])
        XCTAssertTrue(nothing.isError)
        XCTAssertTrue(nothing.text.hasPrefix("Rien à appliquer"), nothing.text)
        XCTAssertEqual(fake.calls.count, count, "rien ne doit partir vers Lightroom")

        _ = tools.call(name: "apply_settings", arguments: ["settings": ["PerspectiveUpright": 7], "step_name": "x"])
        XCTAssertEqual(fake.lastParams["reglages"], ["PerspectiveUpright": 4], "entier hors plage : ramené")
    }

    func testApplyPassesPluginRefusalThrough() {
        fake.errors["appliquer"] = LightroomError.plugin("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été appliqué.")
        let result = tools.call(name: "apply_settings", arguments: ["settings": ["Vibrance": 10], "step_name": "x"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.hasPrefix("Mode « Proposer d'abord »"))
    }

    // MARK: view_photo

    func testViewPhotoReturnsImageThenRemovesPreview() throws {
        let folder = TestSupport.temporaryDirectory().appendingPathComponent("apercu-12")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("DSC_0412.jpg")
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02])
        try jpeg.write(to: file)
        fake.replies["apercu"] = [
            "chemin": .string(file.path),
            "photo": ["id": 12, "fichier": "DSC_0412.NEF"],
            "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
            "reglages": ["Temperature": 5200, "Exposure2012": 0, "Vibrance": 12, "Sharpness": 40],
        ]

        let result = tools.call(name: "view_photo", arguments: ["photo_id": 12, "size": 5000])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(result.content.first, .image(base64: jpeg.base64EncodedString(), mimeType: "image/jpeg"))

        XCTAssertEqual(fake.lastParams["photo"]?.int, 12)
        XCTAssertEqual(fake.lastParams["taille"]?.int, ToolHandler.previewSizes.upperBound)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.count, DevelopCatalogue.all.count)

        let info = try JSONCoding.parse(result.text)
        XCTAssertNil(info["chemin"])
        XCTAssertEqual(info["reglages"]?["Présence"]?["Vibrance"]?.int, 12)
        XCTAssertNil(info["reglages"]?["Tonalité"], "les réglages nuls sont omis")
        XCTAssertEqual(info["reglages"]?["Balance des blancs"]?["Temperature"]?.int, 5200)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "l'aperçu est effacé après lecture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "son dossier aussi")
    }

    func testCompactRecompressesHeavyPreviews() throws {
        // Image de bruit (peu compressible), encodée en qualité maximale.
        let width = 900, height = 600
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 42
        for i in pixels.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            pixels[i] = UInt8(truncatingIfNeeded: seed >> 24)
        }
        let image = try XCTUnwrap(pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        })
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = encoded as Data

        let light = ToolHandler.compact(original, maxBytes: original.count + 1)
        XCTAssertEqual(light, original, "assez léger : inchangé")

        let compacted = ToolHandler.compact(original, maxBytes: original.count / 3)
        XCTAssertLessThan(compacted.count, original.count)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(compacted as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, width, "mêmes dimensions")

        XCTAssertEqual(ToolHandler.compact(Data([1, 2, 3]), maxBytes: 1), Data([1, 2, 3]), "illisible : inchangé")
    }

    func testViewPhotoWithoutPreviewIsAnError() {
        fake.replies["apercu"] = ["photo": ["id": 1]]
        let missing = tools.call(name: "view_photo", arguments: [:])
        XCTAssertTrue(missing.isError)

        fake.replies["apercu"] = ["chemin": "/chemin/qui/n/existe/pas.jpg"]
        let unreadable = tools.call(name: "view_photo", arguments: [:])
        XCTAssertTrue(unreadable.isError)
        XCTAssertTrue(unreadable.text.hasPrefix("Aperçu illisible"))
    }

    // MARK: Autres outils

    func testGetSettingsGroupsEveryValue() throws {
        fake.replies["reglages"] = ["reglages": ["Exposure2012": 0, "HueAdjustmentRed": -5, "LensProfileEnable": 1]]
        let result = tools.call(name: "get_settings", arguments: ["photo_id": "8"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["photo"]?.int, 8)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["reglages"]?["Tonalité"]?["Exposure2012"]?.int, 0)
        XCTAssertEqual(info["reglages"]?["TSL"]?["HueAdjustmentRed"]?.int, -5)
        XCTAssertEqual(info["reglages"]?["Optique"]?["LensProfileEnable"]?.int, 1)
    }

    func testListSelectionLimitAndUndoRevertTargets() {
        _ = tools.call(name: "list_selection", arguments: ["limit": 10_000])
        XCTAssertEqual(fake.lastParams["limite"]?.int, ToolHandler.maxSelectionLimit)
        XCTAssertTrue(tools.call(name: "list_selection", arguments: ["limit": 0]).isError)

        _ = tools.call(name: "undo_last", arguments: ["photo_ids": [4]])
        XCTAssertEqual(fake.calls.last?.command, "annuler")
        XCTAssertEqual(fake.lastParams["photos"], [4])

        _ = tools.call(name: "revert_to_original", arguments: ["selection": true])
        XCTAssertEqual(fake.calls.last?.command, "revenir")
        XCTAssertEqual(fake.lastParams["selection"]?.bool, true)
    }

    func testUnknownTool() {
        XCTAssertTrue(tools.call(name: "crop_photo", arguments: [:]).isError)
    }
}
