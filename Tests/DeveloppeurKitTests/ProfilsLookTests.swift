import XCTest
@testable import DeveloppeurKit

final class ProfilsLookTests: XCTestCase {
    func testParseBuildsTheLookAsTheCatalogueStoresIt() throws {
        let xmp = TestSupport.lookXMP(name: "Adobe Color", uuid: "B952C231111CD8E0ECCF14B86BAA7077")
        let profile = try XCTUnwrap(LookProfileLibrary.parse(Data(xmp.utf8), folder: "Adobe Raw"))
        XCTAssertEqual(profile.name, "Adobe Color")
        XCTAssertEqual(profile.folder, "Adobe Raw")
        XCTAssertEqual(profile.uuid, "B952C231111CD8E0ECCF14B86BAA7077")
        XCTAssertFalse(profile.supportsAmount)
        XCTAssertFalse(profile.monochrome)

        let look = profile.look
        XCTAssertEqual(look["Name"]?.string, "Adobe Color")
        XCTAssertEqual(look["Amount"]?.double, 1)
        XCTAssertEqual(look["Group"]?["x-default"]?.string, "Profiles")
        XCTAssertEqual(look["Copyright"]?.string, "© Adobe")
        XCTAssertEqual(look["SupportsAmount"]?.bool, false)
        let parameters = try XCTUnwrap(look["Parameters"]?.object)
        XCTAssertEqual(parameters["CameraProfile"]?.string, "Adobe Standard")
        XCTAssertEqual(parameters["LookTable"]?.string, "E1095149FDB39D7A057BAB208837E2E1")
        XCTAssertEqual(parameters["ProcessVersion"]?.string, "10.0", "version en texte, comme dans le catalogue")
        XCTAssertEqual(parameters["ConvertToGrayscale"]?.bool, false)
        XCTAssertEqual(parameters["ToneCurvePV2012"], [0, 0, 22, 16, 255, 255], "courbe à plat")
        XCTAssertNil(parameters["Table_E1095149FDB39D7A057BAB208837E2E1"], "les données de table restent dans le fichier")
        XCTAssertNil(parameters["UUID"])
        XCTAssertNil(parameters["PresetType"])

        let normal = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\"><rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\"><rdf:Description xmlns:crs=\"http://ns.adobe.com/camera-raw-settings/1.0/\" crs:PresetType=\"Normal\" crs:UUID=\"A\"/></rdf:RDF></x:xmpmeta>"
        XCTAssertNil(LookProfileLibrary.parse(Data(normal.utf8), folder: "x"), "un paramètre prédéfini n'est pas un profil")
        XCTAssertNil(LookProfileLibrary.parse(Data("pas du xml".utf8), folder: "x"))
    }

    func testLibraryScansFoldersAndGroupsCandidates() {
        let library = TestSupport.lookLibrary()
        let names = library.profiles.map(\.name)
        XCTAssertEqual(names.sorted(), ["Adaptive Color", "Adobe Color", "Adobe Monochrome", "B&W 01", "Camera CLASSIC Neg", "Camera CLASSIC Neg", "Mon profil"])
        XCTAssertEqual(library.profiles.first { $0.name == "B&W 01" }?.folder, "B&W")
        XCTAssertTrue(library.profiles.first { $0.name == "B&W 01" }?.monochrome ?? false)
        XCTAssertEqual(library.profiles.first { $0.name == "Mon profil" }?.folder, "Profils installés")

        let classicNeg = library.candidates(named: "camera classic neg")
        XCTAssertEqual(classicNeg.count, 2, "un fichier par appareil")
        XCTAssertEqual(Set(classicNeg.map(\.cameraRestriction)), ["Fujifilm X-H2S", "Fujifilm X-T5"])
        XCTAssertTrue(library.candidates(named: "Inconnu").isEmpty)
    }

    /// Constaté dans Lightroom Classic 15.6 : posé à la main, Adaptive Color range sa Look avec
    /// isAdobeAdaptive, Cluster, RGBTables et ProfileGainTableMap (nombres), sur Adobe Standard.
    func testAdaptiveProfileIsPreparedForLightroomToCalculate() throws {
        let library = TestSupport.lookLibrary()
        let adaptive = try XCTUnwrap(library.candidates(named: "Adaptive Color").first)
        XCTAssertEqual(adaptive.folder, "Adaptive")
        XCTAssertEqual(adaptive.look["isAdobeAdaptive"]?.bool, true, "sans lui, Lightroom ne le calcule jamais")
        XCTAssertEqual(adaptive.look["Cluster"]?.string, "Adobe")
        let parameters = try XCTUnwrap(adaptive.look["Parameters"]?.object)
        XCTAssertEqual(parameters["RGBTables"]?.double, 100, "un nombre : en texte, Lightroom l'écarte")
        XCTAssertEqual(parameters["ProfileGainTableMap"]?.double, 100)
        XCTAssertNil(parameters["CameraProfile"], "pas de profil de base dans le fichier")
        XCTAssertEqual(adaptive.adaptivePreset, ["CameraProfile": "Adobe Standard", "AILook": ["Active": true]])

        let creative = try XCTUnwrap(library.candidates(named: "B&W 01").first)
        XCTAssertNil(creative.look["isAdobeAdaptive"])
        XCTAssertNil(creative.adaptivePreset)
        let creativeParameters = try XCTUnwrap(creative.look["Parameters"]?.object)
        XCTAssertEqual(creativeParameters["RGBTableAmount"]?.double, 0.5, "un nombre")
        XCTAssertEqual(creativeParameters["RGBTable"]?.string, "5B2F", "une empreinte reste du texte")
        XCTAssertEqual(creativeParameters["Version"]?.string, "10.3")
    }

    func testRestrictionMatching() {
        XCTAssertTrue(LookProfile.restriction("", matchesMake: nil, model: nil), "sans restriction : tous")
        XCTAssertTrue(LookProfile.restriction("Fujifilm X-H2S", matchesMake: "FUJIFILM", model: "X-H2S"))
        XCTAssertFalse(LookProfile.restriction("Fujifilm X-H2S", matchesMake: "FUJIFILM", model: "X-H2"))
        XCTAssertFalse(LookProfile.restriction("Fujifilm X-H2S", matchesMake: "NIKON CORPORATION", model: "X-H2S"))
        XCTAssertFalse(LookProfile.restriction("Fujifilm X-H2S", matchesMake: "FUJIFILM", model: nil))
        XCTAssertTrue(LookProfile.restriction("Fujifilm X-T5", matchesMake: nil, model: "x-t5"))
    }
}
