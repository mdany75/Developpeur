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
        let (url, _) = try PresetXMP.write(name: "Été / doux", settings: ["Exposure2012": 0.2], folder: folder)
        XCTAssertEqual(url.lastPathComponent, "Été - doux.xmp")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
