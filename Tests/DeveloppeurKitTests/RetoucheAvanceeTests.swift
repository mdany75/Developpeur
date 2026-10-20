import XCTest
@testable import DeveloppeurKit

/// Version 1.9 (pistes de la 2.1) : suppression des reflets, plage de couleurs et de profondeur,
/// objet désigné par un rectangle, couleurs ponctuelles dans un masque.
final class RetoucheAvanceeTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: remove_distractions

    func testRemoveDistractionsSendsReflections() throws {
        fake.replies["supprimer"] = ["resultats": [["changements": [["cle": "Suppression.reflets", "avant": 0, "apres": 80]]]]]
        let result = tools.call(name: "remove_distractions", arguments: ["photo_id": 7, "reflections": ["amount": 79.6, "quality": "best"],
                                                                         "step_name": "vitrine", "reason": "Reflets de vitre.", "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        let sent = try XCTUnwrap(fake.calls.last)
        XCTAssertEqual(sent.command, "supprimer")
        XCTAssertGreaterThanOrEqual(sent.timeout, 600, "le module attend la fin du calcul")
        XCTAssertEqual(sent.params["reflets"]?["actif"]?.bool, true)
        XCTAssertEqual(sent.params["reflets"]?["intensite"]?.double, 80)
        XCTAssertEqual(sent.params["reflets"]?["qualite"]?.string, "best")
        XCTAssertEqual(sent.params["photo"]?.int, 7)
        XCTAssertEqual(sent.params["etape"]?.string, "vitrine")
        XCTAssertEqual(sent.params["confirme"]?.bool, true)
        XCTAssertTrue(result.text.contains("Reflets supprimés (intensité)"), "libellé du changement")

        XCTAssertFalse(tools.call(name: "remove_distractions", arguments: ["reflections": ["remove": false], "step_name": "rendre"]).isError)
        XCTAssertEqual(fake.lastParams["reflets"]?["actif"]?.bool, false)
        XCTAssertNil(fake.lastParams["reflets"]?["intensite"])
    }

    func testRemoveDistractionsRejectsInvalidRequests() {
        let count = fake.calls.count
        XCTAssertTrue(tools.call(name: "remove_distractions", arguments: ["step_name": "x"]).isError)
        XCTAssertTrue(tools.call(name: "remove_distractions", arguments: ["reflections": ["amount": 0], "step_name": "x"]).isError)
        XCTAssertTrue(tools.call(name: "remove_distractions", arguments: ["reflections": ["quality": "max"], "step_name": "x"]).isError)
        XCTAssertEqual(fake.calls.count, count)
    }

    // MARK: Masques

    func testObjectBoxIsSentAsARectangle() throws {
        let result = tools.call(name: "add_mask", arguments: ["step_name": "objet", "masks": [[
            "kind": "object", "box": ["x": 0.4, "y": 0.14, "width": 0.7, "height": 0.62], "adjustments": ["Exposure": -1]]]])
        XCTAssertFalse(result.isError, result.text)
        let masque = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array?.first)
        XCTAssertEqual(masque["type"]?.string, "objet")
        XCTAssertEqual(masque["rectangle"]?["x"]?.double, 0.4)
        XCTAssertEqual(masque["rectangle"]?["largeur"]?.double ?? 0, 0.6, accuracy: 1e-9, "le cadre reste dans l'image")
        XCTAssertNil(masque["traits"])
        // Avec des traits en plus, le cadre devient un trait comme avant.
        _ = tools.call(name: "add_mask", arguments: ["step_name": "objet", "masks": [[
            "kind": "object", "box": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2],
            "strokes": [["points": [[0.15, 0.15], [0.2, 0.2]]]], "adjustments": ["Exposure": -1]]]])
        let mixte = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array?.first)
        XCTAssertNil(mixte["rectangle"])
        XCTAssertEqual(mixte["traits"]?.array?.count, 2)
    }

    func testColorRangeSamplesTheColorOnThePreview() throws {
        // Aperçu : moitié gauche bleu ciel, moitié droite rouge.
        var pixels = [UInt8](repeating: 255, count: 200 * 100 * 4)
        for y in 0..<100 {
            for x in 0..<200 {
                let i = (y * 200 + x) * 4
                (pixels[i], pixels[i + 1], pixels[i + 2]) = x < 100 ? (142, 195, 242) : (200, 40, 30)
            }
        }
        let image = TriTests.encode(pixels, width: 200, height: 100)
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" { fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image))] }
        }
        let result = tools.call(name: "add_mask", arguments: ["photo_ids": [9], "step_name": "ciel", "masks": [[
            "kind": "color", "samples": [[0.25, 0.5], [0.75, 0.5]], "color_range": 30, "adjustments": ["Exposure": -0.3]]]])
        XCTAssertFalse(result.isError, result.text)
        let apercu = try XCTUnwrap(fake.calls.first { $0.command == "apercu" })
        XCTAssertEqual(apercu.params["photo"]?.int, 9)
        XCTAssertEqual(apercu.params["taille"]?.int, Detail.side)
        let masque = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array?.first)
        XCTAssertEqual(masque["type"]?.string, "couleur")
        XCTAssertEqual(masque["etendue"]?.double ?? 0, 0.3, accuracy: 1e-9)
        let prelevements = try XCTUnwrap(masque["prelevements"]?.array)
        let ciel = try XCTUnwrap(prelevements[0]["modele"]?.array?.compactMap(\.double))
        // Relevé dans l'étalonnage : bleu ciel (142, 195, 242) → 0,765 0,409 0,211.
        XCTAssertEqual(ciel[0], 0.765, accuracy: 0.01)
        XCTAssertEqual(ciel[1], 0.409, accuracy: 0.01)
        XCTAssertEqual(ciel[2], 0.211, accuracy: 0.01)
        let rouge = try XCTUnwrap(prelevements[1]["modele"]?.array?.compactMap(\.double))
        XCTAssertGreaterThan(rouge[1], 0.8, "rouge : a* fort")
        XCTAssertTrue(ToolHandler.positionne(masque), "positions à recaler")

        XCTAssertTrue(tools.call(name: "add_mask", arguments: ["photo_ids": [1, 2], "step_name": "x", "masks": [[
            "kind": "color", "samples": [[0.5, 0.5]], "adjustments": ["Exposure": -0.3]]]]).text.contains("une seule photo"))
        XCTAssertTrue(tools.call(name: "add_mask", arguments: ["step_name": "x", "masks": [[
            "kind": "color", "adjustments": ["Exposure": -0.3]]]]).isError, "il faut prélever une couleur")
    }

    func testColorModelIsLabAroundNeutral() {
        let gris = ModeleCouleur.modele(128, 128, 128)
        XCTAssertEqual(gris[1], 0.5, accuracy: 0.005, "neutre : a* = 0")
        XCTAssertEqual(gris[2], 0.5, accuracy: 0.005, "neutre : b* = 0")
        XCTAssertEqual(ModeleCouleur.modele(255, 255, 255)[0], 1, accuracy: 0.001)
        let jaune = ModeleCouleur.modele(240, 220, 20)
        XCTAssertGreaterThan(jaune[2], 0.9, "jaune : b* fort")
    }

    func testDepthRangeMask() throws {
        let result = tools.call(name: "add_mask", arguments: ["step_name": "premier plan", "masks": [[
            "kind": "depth", "min": 0, "max": 35, "adjustments": ["Exposure": -0.5]]]])
        XCTAssertFalse(result.isError, result.text)
        let masque = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array?.first)
        XCTAssertEqual(masque["type"]?.string, "profondeur")
        XCTAssertEqual(masque["max"]?.double ?? 0, 0.35, accuracy: 1e-9)
        XCTAssertEqual(masque["fondu"]?.double ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(masque["nom"]?.string, "Claude · Plage de profondeur")
        XCTAssertTrue(tools.call(name: "add_mask", arguments: ["step_name": "x", "masks": [[
            "kind": "depth", "min": 50, "max": 20, "adjustments": ["Exposure": -0.5]]]]).isError)
    }

    func testPointColorsInsideAMask() throws {
        let result = tools.call(name: "add_mask", arguments: ["step_name": "robe", "masks": [[
            "kind": "subject", "point_colors": [["hue": 340, "saturation": 60, "luminance": 50, "hue_shift": 20, "variance": -30]]]]])
        XCTAssertFalse(result.isError, result.text)
        let masque = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array?.first)
        let couleur = try XCTUnwrap(masque["couleurs_ponctuelles"]?.array?.first)
        // Teinte source en sixièmes de tour (0 à 6, référence du SDK et relevé du 17 octobre 2026).
        XCTAssertEqual(couleur["SrcHue"]?.double ?? 0, 340.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(couleur["Variance"]?.double ?? 0, -0.3, accuracy: 1e-9)
        XCTAssertEqual(couleur["HueShift"]?.double ?? 0, 0.2, accuracy: 1e-9)
        XCTAssertNotNil(couleur["HueRange"]?["LowerFull"])
        XCTAssertTrue(tools.call(name: "add_mask", arguments: ["step_name": "x", "masks": [[
            "kind": "subject", "point_colors": [["hue": 400, "saturation": 60, "luminance": 50]]]]]).isError)
    }

    /// Serveur et module de versions différentes (installation partielle) : dit une fois, et par get_status.
    func testVersionMismatchIsSaidOnce() throws {
        fake.moduleVersion = "1.9"
        fake.replies["etat"] = ["version_module": "1.9", "module": "Développeur"]
        tools.versionServeur = "2.0"
        let statut = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)
        XCTAssertEqual(statut["version_serveur"]?.string, "2.0")
        XCTAssertTrue(statut["avertissement_version"]?.string?.contains("version 2.0") == true)

        let autre = ToolHandler(lightroom: fake)
        autre.versionServeur = "2.0"
        fake.replies["selection"] = ["total": 0, "photos": []]
        XCTAssertTrue(autre.call(name: "list_selection", arguments: [:]).text.contains("module de Lightroom en version 1.9"))
        XCTAssertFalse(autre.call(name: "list_selection", arguments: [:]).text.contains("Attention"), "une fois par session")

        let pareil = ToolHandler(lightroom: fake)
        pareil.versionServeur = "1.9"
        XCTAssertFalse(pareil.call(name: "list_selection", arguments: [:]).text.contains("Attention"))
    }

    func testToolAnnotations() {
        let definitions = tools.definitions
        func annotations(_ name: String) -> JSONValue? { definitions.first { $0["name"]?.string == name }?["annotations"] }
        XCTAssertEqual(annotations("view_photo")?["readOnlyHint"]?.bool, true)
        XCTAssertEqual(annotations("cull_photos")?["readOnlyHint"]?.bool, true, "le tri ne change rien")
        XCTAssertEqual(annotations("apply_settings")?["readOnlyHint"]?.bool, false)
        XCTAssertEqual(annotations("revert_to_original")?["destructiveHint"]?.bool, true)
        XCTAssertEqual(annotations("set_metadata")?["destructiveHint"]?.bool, false)
        XCTAssertEqual(annotations("contact_sheet")?["title"]?.string, "Planche contact")
        XCTAssertEqual(annotations("propose_ratings")?["title"]?.string, "Proposer des notes")
        XCTAssertEqual(annotations("propose_ratings")?["readOnlyHint"]?.bool, true, "des propositions, hors du catalogue")
        for definition in definitions {
            XCTAssertNotNil(definition["title"]?.string, "titre pour \(definition["name"]?.string ?? "?")")
        }
    }

    // MARK: Mode HDR (2.1)

    func testHDRSettingsAreSentWithTheirRanges() throws {
        let result = tools.call(name: "apply_settings", arguments: ["step_name": "hdr", "settings": [
            "HDREditMode": 1, "HDRMaxValue": 3, "SDRBrightness": 20, "SDRBlend": -10]])
        XCTAssertFalse(result.isError, result.text)
        let sent = try XCTUnwrap(fake.calls.last { $0.command == "appliquer" })
        XCTAssertEqual(sent.params["reglages"]?["HDREditMode"]?.int, 1)
        XCTAssertEqual(sent.params["plages"]?["SDRBrightness"]?.array?.compactMap(\.double), [-100, 100])
        XCTAssertEqual(sent.params["plages"]?["HDRMaxValue"]?.array?.compactMap(\.double), [0, 8])
        XCTAssertEqual(DevelopCatalogue.label(for: "SDRBlend"), "Aperçu SDR : saturation des hautes lumières")
        XCTAssertTrue(tools.call(name: "apply_settings", arguments: ["step_name": "hdr", "settings": ["HDREditMode": 2]]).isError)
    }

    func testRecentSettingsAreRefusedOnAnOlderLightroom() throws {
        fake.replies["etat"] = ["lightroom": "12.4"]
        let refus = tools.call(name: "apply_settings", arguments: ["step_name": "hdr", "settings": ["HDREditMode": 1, "Exposure2012": 0.2]])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("HDREditMode (depuis la 13.0)"), refus.text)
        XCTAssertFalse(fake.commands.contains("appliquer"))
        XCTAssertTrue(tools.call(name: "apply_settings", arguments: ["step_name": "x", "point_colors": [["hue": 30, "saturation": 50, "luminance": 50]]]).text.contains("point_colors"))
        XCTAssertFalse(tools.call(name: "apply_settings", arguments: ["step_name": "lumière", "settings": ["Exposure2012": 0.2, "Texture": 10]]).isError,
                       "la Texture date de la 8.3")
        XCTAssertEqual(fake.calls.filter { $0.command == "etat" }.count, 1, "la version se lit une fois")
        XCTAssertTrue(ToolHandler.versionInferieure("12.4", "13.0"))
        XCTAssertFalse(ToolHandler.versionInferieure("15.6", "13.0"))
        XCTAssertFalse(ToolHandler.versionInferieure("13.0.1", "13.0"))
    }

    func testNewToolsAreListed() {
        let names = tools.definitions.compactMap { $0["name"]?.string }
        for name in ["cull_photos", "contact_sheet", "remove_distractions"] {
            XCTAssertTrue(names.contains(name), name)
        }
    }
}
