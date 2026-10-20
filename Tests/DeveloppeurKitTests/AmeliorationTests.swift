import XCTest
@testable import DeveloppeurKit

/// Version 1.5 : traitements calculés par Lightroom (`enhance_photo`) et masques combinés.
final class AmeliorationTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: name, arguments: arguments)
    }

    // MARK: enhance_photo

    func testEnhancePhotoSendsTreatmentsInCatalogueOrder() throws {
        let result = call("enhance_photo", ["photo_id": 3, "super_resolution": true, "denoise": 35.4,
                                            "step_name": "nuit", "reason": "ISO 12800.", "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        let sent = try XCTUnwrap(fake.calls.last)
        XCTAssertEqual(sent.command, "ameliorer")
        XCTAssertGreaterThanOrEqual(sent.timeout, 600, "le module attend la fin de chaque calcul")
        let requests = try XCTUnwrap(sent.params["ameliorations"]?.array)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0]["nom"]?.string, "denoise")
        XCTAssertEqual(requests[0]["actif"]?.bool, true)
        XCTAssertEqual(requests[0]["intensite"]?.double, 35, "intensité entière, comme le curseur de Lightroom")
        XCTAssertEqual(requests[1]["nom"]?.string, "superRes")
        XCTAssertEqual(requests[1]["actif"]?.bool, true)
        XCTAssertNil(requests[1]["intensite"])
        XCTAssertEqual(sent.params["photo"]?.int, 3)
        XCTAssertEqual(sent.params["etape"]?.string, "nuit")
        XCTAssertEqual(sent.params["raison"]?.string, "ISO 12800.")
        XCTAssertEqual(sent.params["confirme"]?.bool, true)
        XCTAssertEqual(sent.params["libelles"]?["Amelioration.denoise"]?.string, "Débruitage IA")
        XCTAssertEqual(sent.params["libelles"]?["Amelioration.superRes"]?.string, "Super résolution")

        _ = call("enhance_photo", ["denoise": 0, "raw_details": false, "step_name": "sans"])
        let removals = try XCTUnwrap(fake.lastParams["ameliorations"]?.array)
        XCTAssertEqual(removals[0]["actif"]?.bool, false, "0 retire le débruitage")
        XCTAssertNil(removals[0]["intensite"])
        XCTAssertEqual(removals[1]["nom"]?.string, "rawDetails")
        XCTAssertEqual(removals[1]["actif"]?.bool, false)
        XCTAssertNil(fake.lastParams["photo"], "défaut : la photo active")
    }

    func testEnhancePhotoRejectsInvalidRequests() {
        let count = fake.calls.count
        XCTAssertTrue(call("enhance_photo", ["step_name": "rien"]).isError)
        XCTAssertTrue(call("enhance_photo", ["denoise": 150, "step_name": "x"]).isError)
        XCTAssertTrue(call("enhance_photo", ["denoise": 0.4, "step_name": "x"]).isError)
        XCTAssertTrue(call("enhance_photo", ["super_resolution": "oui", "step_name": "x"]).isError)
        XCTAssertEqual(fake.calls.count, count, "rien n'est envoyé à Lightroom")
    }

    func testEnhancePhotoLabelsTheChanges() throws {
        fake.replies["ameliorer"] = ["mode": "appliquer directement", "resultats": [[
            "photo": ["id": 3, "fichier": "XH2S0001.RAF"],
            "changements": [["cle": "Amelioration.denoise", "avant": 0, "apres": 35]],
            "remarques": ["Lightroom ne permet pas la super résolution sur cette photo."],
            "amelioration": ["denoise": true, "denoiseAmount": 35],
        ]]]
        let result = try JSONCoding.parse(call("enhance_photo", ["denoise": 35, "step_name": "nuit"]).text)
        let change = try XCTUnwrap(result["resultats"]?.array?.first?["changements"]?.array?.first)
        XCTAssertEqual(change["libelle"]?.string, "Débruitage IA")
    }

    func testEnhanceKeysAndLabelsComeFromTheCatalogue() {
        XCTAssertEqual(DevelopCatalogue.enhancements.map(\.lightroom), ["denoise", "rawDetails", "superRes"])
        XCTAssertEqual(DevelopCatalogue.label(for: "Amelioration.rawDetails"), "Détails bruts")
        XCTAssertNotNil(DevelopCatalogue.label(for: "Amelioration"))
        let schema = tools.definitions.first { $0["name"]?.string == "enhance_photo" }?["inputSchema"]?["properties"]?.object
        XCTAssertEqual(Set(schema?.keys.filter { !["photo_id", "step_name", "reason", "confirm"].contains($0) } ?? []),
                       Set(DevelopCatalogue.enhancements.map(\.parameter)))
    }

    /// Défaire un débruitage relance un calcul de Lightroom : 60 s ne suffisaient pas.
    func testUndoAndRevertWaitForLightroomToRecompute() {
        _ = call("undo_last", ["photo_ids": [3]])
        XCTAssertEqual(fake.calls.last?.command, "annuler")
        XCTAssertGreaterThanOrEqual(fake.calls.last?.timeout ?? 0, 600)
        _ = call("revert_to_original", ["photo_ids": [3]])
        XCTAssertEqual(fake.calls.last?.command, "revenir")
        XCTAssertGreaterThanOrEqual(fake.calls.last?.timeout ?? 0, 600)
    }

    // MARK: Masques combinés

    func testAddMaskCombinesAreas() throws {
        let result = call("add_mask", [
            "masks": [[
                "kind": "sky", "adjustments": ["Exposure": -0.3], "name": "Ciel sans bâtiment",
                "combine": [
                    ["mode": "subtract", "kind": "landscape", "part": "architecture"],
                    ["mode": "intersect", "kind": "luminance", "min": 70, "max": 100, "invert": true],
                    ["mode": "add", "kind": "radial", "center_x": 0.2, "center_y": 0.2, "radius_x": 0.1],
                ],
            ]],
            "step_name": "ciel",
        ])
        XCTAssertFalse(result.isError, result.text)
        let mask = try XCTUnwrap(fake.lastParams["masques"]?.array?.first)
        XCTAssertEqual(mask["nom"]?.string, "Claude · Ciel sans bâtiment")
        XCTAssertEqual(mask["soustype"]?.int, 2)
        let components = try XCTUnwrap(mask["composants"]?.array)
        XCTAssertEqual(components.count, 3)
        XCTAssertEqual(components[0]["mode"]?.string, "soustraire")
        XCTAssertEqual(components[0]["type"]?.string, "ia")
        XCTAssertEqual(components[0]["categorie"]?.int, 50001)
        XCTAssertEqual(components[0]["nom"]?.string, "Architecture")
        XCTAssertEqual(components[0]["inverser"]?.bool, false)
        XCTAssertNil(components[0]["locaux"], "les réglages appartiennent au masque, pas au composant")
        XCTAssertEqual(components[1]["mode"]?.string, "intersecter")
        XCTAssertEqual(components[1]["min"]?.double, 0.7)
        XCTAssertEqual(components[1]["inverser"]?.bool, true)
        XCTAssertEqual(components[2]["mode"]?.string, "ajouter")
        XCTAssertEqual(components[2]["type"]?.string, "radial")
        XCTAssertEqual(components[2]["fondu"]?.double, 50)
    }

    func testAddMaskRejectsBadCombinations() {
        let count = fake.calls.count
        let bad: [JSONValue] = [
            [],
            [["kind": "subject"]],
            [["mode": "xor", "kind": "subject"]],
            [["mode": "subtract", "kind": "linear", "from_x": 0.5]],
            [["mode": "subtract", "kind": "landscape"]],
            .array(Array(repeating: ["mode": "add", "kind": "subject"], count: ToolHandler.maxCombined + 1)),
        ]
        for combine in bad {
            let result = call("add_mask", ["masks": [["kind": "sky", "adjustments": ["Exposure": -0.3], "combine": combine]], "step_name": "x"])
            XCTAssertTrue(result.isError, "\(combine)")
        }
        let path = call("add_mask", ["masks": [["kind": "sky", "adjustments": ["Exposure": -0.3],
                                                "combine": [["mode": "subtract", "kind": "linear", "from_x": 0.5]]]], "step_name": "x"])
        XCTAssertTrue(path.text.contains("masks[0].combine[0]"), path.text)
        XCTAssertEqual(fake.calls.count, count)
    }

    // MARK: Outils exposés et consignes

    /// measure_angle était défini en 1.4 mais absent de toolNames : Claude ne le voyait pas.
    func testEveryDefinedToolIsExposed() {
        let defined = tools.allDefinitions.compactMap { $0["name"]?.string }
        XCTAssertEqual(Set(defined), Set(ToolHandler.toolNames))
        XCTAssertTrue(ToolHandler.toolNames.contains("measure_angle"))
        XCTAssertTrue(ToolHandler.toolNames.contains("enhance_photo"))
    }

    func testInstructionsNoLongerSayDenoiseIsOutOfReach() {
        XCTAssertFalse(ServerInfo.instructions.contains("réduction du bruit et super résolution par IA"))
        XCTAssertTrue(ServerInfo.instructions.contains("enhance_photo"))
        XCTAssertTrue(ServerInfo.instructions.contains("combine"))
    }
}
