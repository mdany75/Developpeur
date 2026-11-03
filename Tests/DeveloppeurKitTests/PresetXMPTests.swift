import XCTest
@testable import DeveloppeurKit

final class PresetXMPTests: XCTestCase {
    func testDocumentFollowsCameraRawPresets() throws {
        let settings: [String: JSONValue] = [
            "Exposure2012": 0.35, "Contrast2012": -10, "ConvertToGrayscale": false, "WhiteBalance": "Custom",
            "CameraProfile": "Camera CLASSIC CHROME", "ToneCurvePV2012": [0, 12, 128, 120, 255, 255], "ToneCurveName2012": "Custom",
            "CropLeft": 0.1, "CropTop": 0, "CropRight": 0.9, "CropBottom": 1, "CropAngle": 0,
            "MaskGroupBasedCorrections": [["What": "Correction"]], "Look": [:], "ProcessVersion": "15.4",
        ]
        let (text, skipped) = PresetXMP.document(name: "Ciel & mer", settings: settings, uuid: "ABC")
        XCTAssertEqual(skipped, ["MaskGroupBasedCorrections"])
        XCTAssertTrue(text.contains("crs:PresetType=\"Normal\""))
        XCTAssertTrue(text.contains("crs:UUID=\"ABC\""))
        XCTAssertTrue(text.contains("crs:Exposure2012=\"0.35\""))
        XCTAssertTrue(text.contains("crs:Contrast2012=\"-10\""))
        XCTAssertTrue(text.contains("crs:ConvertToGrayscale=\"False\""))
        XCTAssertTrue(text.contains("crs:CameraProfile=\"Camera CLASSIC CHROME\""))
        XCTAssertTrue(text.contains("crs:HasCrop=\"True\""))
        XCTAssertTrue(text.contains("crs:ProcessVersion=\"15.4\""))
        XCTAssertTrue(text.contains("<rdf:li>128, 120</rdf:li>"))
        XCTAssertTrue(text.contains("Ciel &amp; mer"), "nom échappé en XML")
        XCTAssertFalse(text.contains("<crs:Look>"), "Look vide : rien")

        // Le fichier se relit comme un XMP valide, avec la Look imbriquée.
        let look: JSONValue = ["Name": "Adobe Color", "UUID": "B95", "Amount": 1, "SupportsAmount": false,
                               "Group": ["x-default": "Profiles"],
                               "Parameters": ["CameraProfile": "Adobe Standard", "LookTable": "E109", "ToneCurvePV2012": [0, 0, 22, 16, 255, 255],
                                              "AILook": [:]]]
        let (withLook, _) = PresetXMP.document(name: "Avec profil", settings: ["Look": look], uuid: "DEF")
        XCTAssertTrue(withLook.contains("crs:Name=\"Adobe Color\""))
        XCTAssertTrue(withLook.contains("crs:LookTable=\"E109\""))
        XCTAssertTrue(withLook.contains("<rdf:li>22, 16</rdf:li>"))
        let parser = XMLParser(data: Data(withLook.utf8))
        XCTAssertTrue(parser.parse(), "XML bien formé : \(parser.parserError?.localizedDescription ?? "")")
    }

    func testWriteCreatesTheFolderAndAFileName() throws {
        let folder = TestSupport.temporaryDirectory().appendingPathComponent("Settings/Claude")
        let (url, _, _, _) = try PresetXMP.write(name: "Été / doux", settings: ["Exposure2012": 0.2], folder: folder)
        XCTAssertEqual(url.lastPathComponent, "Été - doux.xmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Comparaison Automaat (2 nov. 2026) : un paramètre prédéfini du même nom s'écrasait sans le
    /// dire. Le nouveau prend « Nom (2) », l'ancien reste intact ; replace seul le remplace.
    func testWriteKeepsAPresetOfTheSameName() throws {
        let folder = TestSupport.temporaryDirectory().appendingPathComponent("Settings/Claude")
        let first = try PresetXMP.write(name: "Doux", settings: ["Exposure2012": 0.2], folder: folder)
        let second = try PresetXMP.write(name: "Doux", settings: ["Exposure2012": 0.5], folder: folder)
        let third = try PresetXMP.write(name: "Doux", settings: ["Exposure2012": 0.7], folder: folder)
        XCTAssertEqual(first.name, "Doux")
        XCTAssertEqual(second.name, "Doux (2)")
        XCTAssertEqual(third.url.lastPathComponent, "Doux (3).xmp")
        XCTAssertTrue(try String(contentsOf: first.url, encoding: .utf8).contains("crs:Exposure2012=\"0.2\""), "l'ancien est intact")
        XCTAssertTrue(try String(contentsOf: second.url, encoding: .utf8).contains("Doux (2)"), "le nom affiché suit le fichier")

        let replaced = try PresetXMP.write(name: "Doux", settings: ["Exposure2012": 0.9], folder: folder, replace: true)
        XCTAssertEqual(replaced.url, first.url)
        XCTAssertTrue(try String(contentsOf: first.url, encoding: .utf8).contains("crs:Exposure2012=\"0.9\""))
        XCTAssertNil(replaced.occupe)
        XCTAssertEqual(second.occupe, "Doux")
    }

    /// Revue du 2 nov. 2026 : « Été / doux » et « Été - doux » donnent le même fichier ; replace ne
    /// remplace que le paramètre de ce nom affiché, et un nom trop long en octets se raccourcit.
    func testWriteComparesDisplayedNames() throws {
        let folder = TestSupport.temporaryDirectory().appendingPathComponent("Settings/Claude")
        let slash = try PresetXMP.write(name: "Été / doux & \"vif\"", settings: ["Exposure2012": 0.2], folder: folder)
        XCTAssertEqual(PresetXMP.displayedName(slash.url), "Été / doux & \"vif\"", "nom affiché relu, échappement défait")
        let dash = try PresetXMP.write(name: "Été - doux & \"vif\"", settings: ["Exposure2012": 0.5], folder: folder, replace: true)
        XCTAssertEqual(dash.name, "Été - doux & \"vif\" (2)", "un autre paramètre occupait le fichier : gardé")
        XCTAssertEqual(dash.occupe, "Été / doux & \"vif\"")
        XCTAssertTrue(try String(contentsOf: slash.url, encoding: .utf8).contains("crs:Exposure2012=\"0.2\""))

        let long = String(repeating: "é", count: 200)
        let written = try PresetXMP.write(name: long, settings: ["Exposure2012": 0.2], folder: folder)
        XCTAssertLessThanOrEqual(written.name.utf8.count, PresetXMP.maxNameBytes)
        let again = try PresetXMP.write(name: long, settings: ["Exposure2012": 0.2], folder: folder)
        XCTAssertTrue(again.name.hasSuffix(" (2)"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: again.url.path))
    }
}
