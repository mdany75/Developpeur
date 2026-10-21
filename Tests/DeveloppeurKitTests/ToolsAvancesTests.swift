import XCTest
@testable import DeveloppeurKit

/// Outils ajoutés en 1.2 : retouche globale étendue, retouches locales, mesures, profils à base
/// de Look, paramètres prédéfinis, copie, proposition visuelle et journal.
final class ToolsAvancesTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var presetFolder: URL!

    override func setUp() {
        fake = FakeLightroom()
        presetFolder = TestSupport.temporaryDirectory().appendingPathComponent("Claude")
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary(), presetFolder: presetFolder,
                            localEffects: TestSupport.localEffects())
    }

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: name, arguments: arguments)
    }

    // MARK: apply_settings étendu

    func testApplyCurvesPointColorsBalanceAutoTonePresetAndReason() throws {
        let result = call("apply_settings", [
            "settings": ["ConvertToGrayscale": 1, "GrayMixerBlue": -30],
            "tone_curve": ["rgb": [[255, 255], [0, 12], [128, 120]], "blue": [[0, 0], [255, 240]]],
            "point_colors": [["hue": 30, "saturation": 40, "luminance": 60, "hue_shift": -10, "range": 70]],
            "white_balance": "auto",
            "auto_tone": true,
            "preset": "Mes presets/Été",
            "step_name": "noir et blanc",
            "reason": "La lumière plate se prête au noir et blanc.",
        ])
        XCTAssertFalse(result.isError, result.text)
        let params = fake.lastParams
        XCTAssertEqual(fake.calls.last?.command, "appliquer")
        XCTAssertEqual(params["booleens"], ["ConvertToGrayscale"])
        XCTAssertEqual(params["courbes"]?["ToneCurvePV2012"], [0, 12, 128, 120, 255, 255], "points triés, à plat")
        XCTAssertEqual(params["courbes"]?["ToneCurvePV2012Blue"], [0, 0, 255, 240])
        let color = try XCTUnwrap(params["couleurs_ponctuelles"]?.array?.first)
        XCTAssertEqual(try XCTUnwrap(color["SrcHue"]?.double), 0.5, accuracy: 1e-9, "30° = un demi-sixième de tour")
        XCTAssertEqual(color["Variance"]?.double, 0)
        XCTAssertEqual(color["SrcSat"]?.double, 0.4)
        XCTAssertEqual(color["HueShift"]?.double, -0.1)
        XCTAssertEqual(color["RangeAmount"]?.double, 0.7)
        XCTAssertEqual(color["SatScale"]?.double, 0)
        XCTAssertEqual(params["balance"]?.string, "Auto")
        XCTAssertEqual(params["auto_ton"]?.bool, true)
        XCTAssertEqual(params["preset"]?.string, "Mes presets/Été")
        XCTAssertEqual(params["raison"]?.string, "La lumière plate se prête au noir et blanc.")
        XCTAssertEqual(params["libelles"]?["ToneCurvePV2012Blue"]?.string, "Courbe par points (bleu)")
        XCTAssertEqual(params["libelles"]?["AutoTone"]?.string, "Tonalité automatique")
        XCTAssertEqual(params["looks_traitement"]?["monochrome"]?["Name"]?.string, "Adobe Monochrome", "pour passer en noir et blanc sous Adobe Color")
        XCTAssertEqual(params["looks_traitement"]?["couleur"]?["Name"]?.string, "Adobe Color")

        _ = call("apply_settings", ["settings": ["Exposure2012": 0.2], "step_name": "x"])
        XCTAssertNil(fake.lastParams["looks_traitement"], "seulement avec ConvertToGrayscale")
    }

    func testApplyLensBlurBokehShapeAndCatEye() throws {
        let result = call("apply_settings", ["lens_blur": ["bokeh": "ring", "cat_eye": 30], "step_name": "bokeh"])
        XCTAssertFalse(result.isError, result.text)
        let blur = try XCTUnwrap(fake.lastParams["flou_objectif"])
        XCTAssertEqual(blur["oeil_de_chat"]?.double, 30)
        XCTAssertEqual(blur["bokeh"]?["nom"]?.string, "anneau (objectif catadioptrique)")
        XCTAssertEqual(blur["bokeh"]?["champs"], ["BokehShape": 1, "BokehShapeDetail": 3, "BokehAspect": 0, "BokehRotation": 0,
                                                   "SphericalAberration": 25, "CatEyeScale": 100])
        XCTAssertEqual(DevelopCatalogue.bokehShapes.first { $0.parameter == "anamorphic" }?.fields["BokehAspect"], -100)
        let wrong = call("apply_settings", ["lens_blur": ["bokeh": "hexagon"], "step_name": "bokeh"])
        XCTAssertTrue(wrong.isError && wrong.text.contains("soap_bubble"), wrong.text)
    }

    func testProcessVersionIsShownFirstThenApplied() throws {
        let refused = call("apply_settings", ["process_version": 6, "step_name": "version"])
        XCTAssertTrue(refused.isError && refused.text.contains("preview_settings"), refused.text)
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est envoyé sans accord")
        XCTAssertTrue(call("apply_settings", ["process_version": 5, "confirm": true, "step_name": "version"]).isError)
        let result = call("apply_settings", ["process_version": 6, "confirm": true, "step_name": "version"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["version_processus"]?["valeur"]?.string, "15.4")
        XCTAssertEqual(fake.lastParams["version_processus"]?["noms"]?["11.0"]?.string, "version 5")

        fake.replies["reglages"] = ["version_processus": "11.0", "reglages": [:]]
        let settings = call("get_settings", [:]).text
        XCTAssertTrue(settings.contains("version 5 (11.0)") && settings.contains("process_version = 6"), settings)
        fake.replies["reglages"] = ["version_processus": "15.4", "reglages": [:]]
        XCTAssertFalse(call("get_settings", [:]).text.contains("version_processus_ancienne"))
    }

    func testApplyValidatesCurvesColorsAndBalance() {
        let count = fake.calls.count
        let cases: [[String: JSONValue]] = [
            ["tone_curve": ["rgb": [[0, 0]]]],
            ["tone_curve": ["rgb": [[0, 0], [0, 10]]]],
            ["tone_curve": ["luma": [[0, 0], [255, 255]]]],
            ["tone_curve": ["rgb": [[0, 0], [300, 255]]]],
            ["point_colors": [["hue": 400, "saturation": 10, "luminance": 10]]],
            ["point_colors": [["hue": 40]]],
            ["white_balance": "lune"],
            ["profile": "Inconnu"],
            ["profile": "Adobe Color", "profile_amount": 250],
        ]
        for arguments in cases {
            var args = arguments
            args["step_name"] = "x"
            XCTAssertTrue(call("apply_settings", args).isError, "\(arguments)")
        }
        XCTAssertEqual(fake.calls.count, count, "rien ne doit partir vers Lightroom")
        XCTAssertTrue(call("apply_settings", ["profile": "Inconnu", "step_name": "x"]).text.hasPrefix("Profil inconnu : \"Inconnu\"."))
    }

    func testApplyLookProfiles() throws {
        let classicNeg = call("apply_settings", ["profile": "Camera CLASSIC Neg", "profile_amount": 80, "step_name": "x"])
        XCTAssertFalse(classicNeg.isError, classicNeg.text)
        let look = try XCTUnwrap(fake.lastParams["profil_look"])
        XCTAssertEqual(look["nom"]?.string, "Camera CLASSIC Neg")
        XCTAssertEqual(look["candidats"]?.array?.count, 2, "un par appareil")
        XCTAssertEqual(look["candidats"]?.array?.first?["raw_seulement"]?.bool, true)
        XCTAssertEqual(look["candidats"]?.array?.first?["look"]?["Parameters"]?["LookTable"]?.string, "E1095149FDB39D7A057BAB208837E2E1")
        XCTAssertNil(look["intensite"], "intensité non réglable")
        XCTAssertTrue(classicNeg.text.contains("profile_amount ignoré"), classicNeg.text)
        XCTAssertNil(fake.lastParams["profil"])

        _ = call("apply_settings", ["profile": "B&W 01", "profile_amount": 150, "step_name": "x"])
        XCTAssertEqual(fake.lastParams["profil_look"]?["intensite"]?.double, 1.5)
        XCTAssertEqual(fake.lastParams["profil_look"]?["candidats"]?.array?.first?["raw_seulement"]?.bool, false, "profil créatif : tous les fichiers")

        // Profil adaptatif : la Look et ce qui l'accompagne dans un paramètre prédéfini du module.
        _ = call("apply_settings", ["profile": "Adaptive Color", "step_name": "x"])
        let adaptive = try XCTUnwrap(fake.lastParams["profil_look"]?["candidats"]?.array?.first)
        XCTAssertEqual(adaptive["raw_seulement"]?.bool, true)
        XCTAssertEqual(adaptive["look"]?["isAdobeAdaptive"]?.bool, true)
        XCTAssertEqual(adaptive["par_preset"], ["CameraProfile": "Adobe Standard", "AILook": ["Active": true]])
        XCTAssertNil(look["candidats"]?.array?.first?["par_preset"], "pas pour les autres profils")

        _ = call("apply_settings", ["profile": "Camera Velvia/Vivid", "step_name": "x"])
        XCTAssertEqual(fake.lastParams["profil"]?.string, "Camera Velvia/Vivid", "profil d'appareil : par son nom")
        XCTAssertNil(fake.lastParams["profil_look"])
    }

    // MARK: Retouches locales

    func testAddMaskConvertsAdjustmentsAndGeometry() throws {
        let result = call("add_mask", [
            "masks": [
                ["kind": "sky", "adjustments": ["Exposure": -0.6, "Dehaze": 15, "Temperature": -8]],
                ["kind": "person_part", "part": "face_skin", "adjustments": ["Texture": -20], "amount": 60],
                ["kind": "landscape", "part": "water", "invert": true, "adjustments": ["Saturation": 10]],
                ["kind": "linear", "from_x": 0.5, "from_y": 0, "to_x": 0.5, "to_y": 0.4, "adjustments": ["Exposure": -1]],
                ["kind": "radial", "center_x": 0.4, "center_y": 0.5, "radius_x": 0.2, "adjustments": ["Exposure": 0.3], "name": "Visage"],
                ["kind": "luminance", "min": 70, "max": 100, "adjustments": ["Highlights": -30, "ToningHue": 210, "ToningSaturation": 20]],
            ],
            "step_name": "masques", "reason": "Ciel trop clair.", "photo_ids": [5],
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.last?.command, "masquer")
        let masks = try XCTUnwrap(fake.lastParams["masques"]?.array)
        XCTAssertEqual(masks.count, 6)

        XCTAssertEqual(masks[0]["type"]?.string, "ia")
        XCTAssertEqual(masks[0]["soustype"]?.int, 2)
        XCTAssertEqual(masks[0]["locaux"]?["LocalExposure2012"]?.double, -0.15, "−0,6 IL sur l'échelle ±4")
        XCTAssertEqual(masks[0]["locaux"]?["LocalDehaze"]?.double, 0.15)
        XCTAssertEqual(masks[0]["nom"]?.string, "Claude · Ciel")
        XCTAssertEqual(masks[0]["quantite"]?.double, 1)

        XCTAssertEqual(masks[1]["soustype"]?.int, 3)
        XCTAssertEqual(masks[1]["categorie"]?.int, 2)
        XCTAssertEqual(masks[1]["quantite"]?.double, 0.6)
        XCTAssertEqual(masks[2]["categorie"]?.int, 50007)
        XCTAssertEqual(masks[2]["inverser"]?.bool, true)

        XCTAssertEqual(masks[3]["type"]?.string, "lineaire")
        XCTAssertEqual(masks[3]["de_y"]?.double, 0)
        XCTAssertEqual(masks[3]["a_y"]?.double, 0.4)
        XCTAssertEqual(masks[4]["type"]?.string, "radial")
        XCTAssertNil(masks[4]["rayon_y"], "défaut : un cercle, calculé par le module")
        XCTAssertEqual(masks[4]["fondu"]?.double, 50)
        XCTAssertEqual(masks[4]["nom"]?.string, "Claude · Visage")
        XCTAssertEqual(masks[5]["min"]?.double, 0.7)
        XCTAssertEqual(masks[5]["fondu"]?.double, 0.1)
        XCTAssertEqual(masks[5]["locaux"]?["LocalToningHue"]?.double, 210)
        XCTAssertEqual(masks[5]["locaux"]?["LocalToningSaturation"]?.double, 0.2)

        XCTAssertEqual(fake.lastParams["photos"], [5])
        XCTAssertEqual(fake.lastParams["raison"]?.string, "Ciel trop clair.")
        XCTAssertEqual(fake.lastParams["etape"]?.string, "masques")
    }

    func testAddMaskPosesALightroomLocalEffect() throws {
        let effects = TestSupport.localEffects().effects
        XCTAssertEqual(effects.map(\.name), ["Blanchissement des dents", "Peau douce maison", "Iris Enhance",
                                             "Peau du visage lisse", "Adoucir la peau (Lite)"],
                       "le blanchiment livré avec Lightroom n'est pas répété ; la dose d'Adobe pour la peau vient en dernier")
        XCTAssertEqual(effects[0].locaux, ["LocalExposure2012": 0.1, "LocalSaturation": -0.6],
                       "sans les clés d'avant 2012 ni une teinte sans saturation")
        XCTAssertEqual(effects[1].locaux["LocalToningHue"], 30)

        let result = call("add_mask", [
            "masks": [
                ["kind": "person_part", "part": "teeth", "effect": "teeth whitening", "amount": 70],
                ["kind": "person_part", "part": "iris_pupil", "effect": "Iris Enhance", "adjustments": ["Saturation": 20]],
            ],
            "step_name": "portrait",
        ])
        XCTAssertFalse(result.isError, result.text)
        let masks = try XCTUnwrap(fake.lastParams["masques"]?.array)
        XCTAssertEqual(masks[0]["locaux"]?["LocalExposure2012"]?.double, 0.1)
        XCTAssertEqual(masks[0]["locaux"]?["LocalSaturation"]?.double, -0.6)
        XCTAssertEqual(masks[0]["quantite"]?.double, 0.7, "amount réduit l'intensité de l'effet")
        XCTAssertEqual(masks[0]["nom"]?.string, "Claude · Blanchissement des dents")
        XCTAssertEqual(masks[1]["locaux"]?["LocalSaturation"]?.double, 0.2, "adjustments remplace le réglage de l'effet")
        XCTAssertEqual(masks[1]["locaux"]?["LocalClarity2012"]?.double, 0.1)
        XCTAssertTrue(result.text.contains("Effet « Blanchissement des dents » : exposition +0,4 IL, saturation −60 ; à 70 % : exposition +0,28 IL, saturation −42."),
                      result.text)
        XCTAssertTrue(result.text.contains("Effet « Iris Enhance » : exposition +0,35 IL, clarté +10, saturation +40."),
                      "à 100 % : l'effet seul, sans dose réduite")

        let unknown = call("add_mask", ["masks": [["kind": "subject", "effect": "Peau de pêche"]], "step_name": "x"])
        XCTAssertTrue(unknown.isError && unknown.text.contains("Blanchissement des dents"), unknown.text)
        let description = try XCTUnwrap(tools.definitions.first { $0["name"] == "add_mask" })
        XCTAssertTrue(JSONCoding.line(description).contains("Peau douce maison"))
    }

    /// La méthode du tireur (Prompts.Tireur) en un seul add_mask : grande zone claire par un dégradé
    /// linéaire sans le sujet, sujet éclairci par un radial, bords assombris par un radial inversé.
    /// Les doses de la méthode passent, et le module reçoit les trois masques dans une seule étape.
    func testTireurMasksGoToTheModuleInOneStep() throws {
        let result = call("add_mask", [
            "masks": [
                ["kind": "linear", "from_x": 0.5, "from_y": 0, "to_x": 0.5, "to_y": 0.45, "adjustments": ["Exposure": -0.5],
                 "combine": [["mode": "subtract", "kind": "subject"]]],
                ["kind": "radial", "center_x": 0.45, "center_y": 0.4, "radius_x": 0.2, "feather": 90, "adjustments": ["Exposure": 0.3]],
                ["kind": "radial", "center_x": 0.45, "center_y": 0.4, "radius_x": 0.7, "radius_y": 0.7, "feather": 80, "invert": true,
                 "adjustments": ["Exposure": -0.3]],
            ],
            "step_name": .string(Prompts.Tireur.nomEtape), "reason": "Mener l'œil au visage.", "photo_ids": [5],
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.filter { $0.command == "masquer" }.count, 1, "une seule étape")
        let masks = try XCTUnwrap(fake.lastParams["masques"]?.array)
        XCTAssertEqual(masks.count, 3)
        XCTAssertEqual(masks[0]["type"]?.string, "lineaire")
        XCTAssertEqual(masks[0]["composants"]?.array?.first?["mode"]?.string, "soustraire", "le sujet retiré du dégradé")
        XCTAssertEqual(masks[0]["locaux"]?["LocalExposure2012"]?.double ?? 0, -0.125, accuracy: 1e-9)
        XCTAssertEqual(masks[1]["locaux"]?["LocalExposure2012"]?.double ?? 0, 0.075, accuracy: 1e-9)
        XCTAssertEqual(masks[1]["fondu"]?.double, 90)
        XCTAssertEqual(masks[1]["inverser"]?.bool, false)
        XCTAssertEqual(masks[2]["type"]?.string, "radial")
        XCTAssertEqual(masks[2]["locaux"]?["LocalExposure2012"]?.double ?? 0, -0.075, accuracy: 1e-9)
        XCTAssertEqual(masks[2]["fondu"]?.double, 80)
        XCTAssertEqual(masks[2]["inverser"]?.bool, true, "les bords : l'extérieur de l'ellipse")
        XCTAssertEqual(masks[2]["rayon_y"]?.double, 0.7)
        XCTAssertEqual(fake.lastParams["etape"]?.string, "éclaircir et assombrir")
        XCTAssertEqual(fake.lastParams["photos"], [5])
    }

    func testAddMaskWithLocalCurveGrainAndHue() throws {
        let result = call("add_mask", ["masks": [["kind": "sky", "adjustments": ["Grain": 25, "Hue": 90],
                                                  "tone_curve": ["rgb": [[0, 10], [255, 245]], "blue": [[0, 0], [128, 140], [255, 255]]]]],
                                       "step_name": "ciel"])
        XCTAssertFalse(result.isError, result.text)
        let locaux = try XCTUnwrap(fake.lastParams["masques"]?.array?.first?["locaux"])
        XCTAssertEqual(locaux["LocalGrain"]?.double, 0.25)
        XCTAssertEqual(locaux["LocalHue"]?.double ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(locaux["MainCurve"], ["0,10", "255,245"], "comme Lightroom range une courbe locale")
        XCTAssertEqual(locaux["BlueCurve"], ["0,0", "128,140", "255,255"])
        // Une courbe seule suffit ; un canal inconnu non.
        XCTAssertFalse(call("add_mask", ["masks": [["kind": "sky", "tone_curve": ["rgb": [[0, 0], [255, 230]]]]], "step_name": "x"]).isError)
        XCTAssertTrue(call("add_mask", ["masks": [["kind": "sky", "tone_curve": ["luma": [[0, 0], [255, 230]]]]], "step_name": "x"]).isError)
    }

    func testAddMaskBrushStrokesAndObject() throws {
        let result = call("add_mask", ["masks": [
            ["kind": "brush", "strokes": [["points": [[0.2, 0.5], [0.4, 0.52]], "size": 0.03, "feather": 60, "flow": 50]],
             "auto_mask": true, "adjustments": ["Exposure": -0.3], "name": "Assombrir le mur"],
            ["kind": "object", "box": ["x": 0.5, "y": 0.2, "width": 0.1, "height": 0.4], "adjustments": ["Exposure": 0.2]],
        ], "step_name": "dodge and burn"])
        XCTAssertFalse(result.isError, result.text)
        let masks = try XCTUnwrap(fake.lastParams["masques"]?.array)
        XCTAssertEqual(masks[0]["type"]?.string, "pinceau")
        XCTAssertEqual(masks[0]["auto"]?.bool, true)
        let trait = try XCTUnwrap(masks[0]["traits"]?.array?.first)
        XCTAssertEqual(trait["points"], [[0.2, 0.5], [0.4, 0.52]])
        XCTAssertEqual(trait["rayon"]?.double, 0.03)
        XCTAssertEqual(trait["durete"]?.double ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(trait["flux"]?.double, 0.5)
        XCTAssertEqual(masks[1]["type"]?.string, "objet")
        XCTAssertEqual(masks[1]["nom"]?.string, "Claude · Objet")
        // Constaté le 17 octobre 2026 : le cadre en rectangle (Mask/Polygon) sélectionne l'objet entier.
        XCTAssertEqual(masks[1]["rectangle"]?["x"]?.double, 0.5)
        XCTAssertEqual(masks[1]["rectangle"]?["hauteur"]?.double, 0.4)
        XCTAssertNil(masks[1]["traits"])
        // Avec des traits, le cadre devient un trait fin dans sa longueur.
        let geste = ToolHandler.boxStroke(x: 0.5, y: 0.2, width: 0.1, height: 0.4)
        XCTAssertEqual(geste["points"]?.array?.first?.array?.first?.double ?? 0, 0.55, accuracy: 1e-9, "dans la longueur du cadre, au milieu")
        XCTAssertEqual(geste["points"]?.array?.first?.array?.last?.double ?? 0, 0.3, accuracy: 1e-9, "de 25 %…")
        XCTAssertEqual(geste["points"]?.array?.last?.array?.last?.double ?? 0, 0.5, accuracy: 1e-9, "… à 75 %")
        XCTAssertEqual(geste["rayon"]?.double ?? 0, 0.01, accuracy: 1e-9, "un trait fin")
        XCTAssertTrue(fake.commands.contains("geometrie"), "traits et objets se recalent sur la géométrie")
        XCTAssertTrue(call("add_mask", ["masks": [["kind": "brush", "adjustments": ["Exposure": 1]]], "step_name": "x"]).isError, "un pinceau sans trait")
        XCTAssertTrue(call("add_mask", ["masks": [["kind": "object", "adjustments": ["Exposure": 1]]], "step_name": "x"]).isError, "un objet sans cadre ni trait")
    }

    func testAddMaskDoesNotDoubleClaudePrefix() throws {
        let names: [(JSONValue?, String)] = [
            ("Claude · Ciel", "Claude · Ciel"),
            ("Ciel bleu", "Claude · Ciel bleu"),
            ("  claude·Nuages ", "Claude · Nuages"),
            ("Claude · Claude · Ciel", "Claude · Ciel"),
            ("Claude · ", "Claude · Ciel"),
            (nil, "Claude · Ciel"),
        ]
        for (given, expected) in names {
            var mask: [String: JSONValue] = ["kind": "sky", "adjustments": ["Exposure": -0.3]]
            if let given { mask["name"] = given }
            let result = call("add_mask", ["masks": [.object(mask)], "step_name": "ciel"])
            XCTAssertFalse(result.isError, result.text)
            XCTAssertEqual(fake.lastParams["masques"]?.array?.first?["nom"]?.string, expected, "\(String(describing: given))")
        }
    }

    func testAddMaskRejectsIncompleteMasks() {
        let count = fake.calls.count
        let bad: [JSONValue] = [
            ["kind": "person_part", "adjustments": ["Exposure": 0.2]],
            ["kind": "sky", "adjustments": [:]],
            ["kind": "sky", "adjustments": ["Luminosité": 10]],
            ["kind": "sky", "adjustments": ["Exposure": 5]],
            ["kind": "linear", "from_x": 0.5, "adjustments": ["Exposure": -1]],
            ["kind": "luminance", "min": 80, "max": 20, "adjustments": ["Exposure": -1]],
            ["kind": "pinceau", "adjustments": ["Exposure": -1]],
        ]
        for mask in bad {
            XCTAssertTrue(call("add_mask", ["masks": [mask], "step_name": "x"]).isError, "\(mask)")
        }
        XCTAssertTrue(call("add_mask", ["masks": [], "step_name": "x"]).isError)
        XCTAssertEqual(fake.calls.count, count)
    }

    func testRetouchSpotsAndRedEyes() throws {
        let result = call("retouch_spots", [
            "spots": [["x": 0.2, "y": 0.1, "radius": 0.01], ["x": 0.8, "y": 0.2, "radius": 0.02, "source_x": 0.7, "source_y": 0.2, "mode": "clone"]],
            "red_eyes": [["x": 0.45, "y": 0.4, "radius": 0.005]],
            "photo_id": 9, "step_name": "poussières",
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.last?.command, "retoucher")
        let spots = try XCTUnwrap(fake.lastParams["taches"]?.array)
        XCTAssertEqual(spots[0]["rayon"]?.double, 0.01)
        XCTAssertEqual(spots[0]["mode"]?.string, "heal")
        XCTAssertNil(spots[0]["source_x"])
        XCTAssertEqual(spots[0]["fondu"]?.double, 0.43)
        XCTAssertEqual(spots[1]["mode"]?.string, "clone")
        XCTAssertEqual(spots[1]["source_x"]?.double, 0.7)
        XCTAssertEqual(fake.lastParams["yeux"]?.array?.first?["pupille"]?.double, 0.5)
        XCTAssertEqual(fake.lastParams["photo"]?.int, 9)

        _ = call("retouch_spots", ["spots": [["x": 0.5, "y": 0.5, "radius": 0.03, "mode": "remove"]], "step_name": "supprimer"])
        XCTAssertEqual(fake.lastParams["taches"]?.array?.first?["mode"]?.string, "remove")
        _ = call("retouch_spots", ["spots": [["x": 0.5, "y": 0.5, "radius": 0.03, "mode": "generative"]], "step_name": "x"])
        XCTAssertEqual(fake.lastParams["taches"]?.array?.first?["mode"]?.string, "heal", "jamais de suppression générative")

        XCTAssertTrue(call("retouch_spots", ["step_name": "x"]).isError)
        XCTAssertTrue(call("retouch_spots", ["spots": [["x": 0.2, "y": 0.1, "radius": 0.5]], "step_name": "x"]).isError)
        XCTAssertTrue(call("retouch_spots", ["spots": [["x": 0.2, "y": 0.1, "radius": 0.01, "source_x": 0.3]], "step_name": "x"]).isError)
    }

    // MARK: Proposition visuelle

    func testPreviewSettingsRendersAndComparesWithoutApplying() throws {
        let current = TestSupport.previewFile(TestSupport.jpeg(red: 80, green: 80, blue: 80))
        let proposed = TestSupport.previewFile(TestSupport.jpeg(red: 140, green: 140, blue: 140))
        fake.replies["essayer"] = ["chemin": .string(proposed), "chemin_actuel": .string(current),
                                   "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.8]], "remarques": []]
        let result = call("preview_settings", ["settings": ["Exposure2012": 0.8], "compare": true, "photo_id": 3])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.last?.command, "essayer")
        XCTAssertEqual(fake.lastParams["action"]?.string, "appliquer")
        XCTAssertEqual(fake.lastParams["comparer"]?.bool, true)
        XCTAssertEqual(fake.lastParams["photo"]?.int, 3)
        XCTAssertNil(fake.lastParams["confirme"], "une proposition ne demande pas d'accord")
        guard case .image(let base64, _) = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("image attendue") }
        XCTAssertEqual(image.width, 300 + 4 + 300, "côte à côte")
        let info = try JSONCoding.parse(result.text)
        XCTAssertNotNil(info["mesures_proposition"])
        XCTAssertNotNil(info["mesures_actuelles"])
        XCTAssertEqual(info["changements"]?.array?.first?["libelle"]?.string, "Exposition")
        XCTAssertFalse(FileManager.default.fileExists(atPath: proposed), "aperçus effacés")
        XCTAssertFalse(FileManager.default.fileExists(atPath: current))

        fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 1, green: 2, blue: 3)))]
        let mask = call("add_mask", ["masks": [["kind": "sky", "adjustments": ["Exposure": -0.5]]], "step_name": "ciel", "preview": true])
        XCTAssertFalse(mask.isError, mask.text)
        XCTAssertEqual(fake.calls.last?.command, "essayer")
        XCTAssertEqual(fake.lastParams["action"]?.string, "masquer")
    }

    // MARK: Voir et mesurer

    func testViewPhotoZoomOnRegion() throws {
        fake.onSend = { [unowned self] command, params in
            guard command == "apercu" else { return }
            XCTAssertEqual(params["taille"]?.int, 0, "pleine résolution")
            fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 90, green: 90, blue: 90, width: 4000, height: 3000)))]
        }
        let result = call("view_photo", ["region": ["x": 0.5, "y": 0.5, "width": 0.2, "height": 0.2]])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["zoom"]?["pourcentage"]?.int, 100)
        XCTAssertEqual(info["zoom"]?["pixels"]?.string, "800 × 600")
        XCTAssertNotNil(info["mesures_zone"])

        XCTAssertTrue(call("view_photo", ["region": ["x": 0.9, "y": 0, "width": 0.5, "height": 0.5]]).isError, "hors de l'image")
        XCTAssertTrue(call("view_photo", ["region": ["x": 0, "y": 0, "width": 0.5, "height": 0.5], "compare": "before_claude"]).isError)
    }

    func testViewPhotoCompareBeforeAndAfter() throws {
        fake.replies["apercu"] = [
            "chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 150, green: 150, blue: 150))),
            "chemin_avant": .string(TestSupport.previewFile(TestSupport.jpeg(red: 90, green: 90, blue: 90))),
        ]
        let result = call("view_photo", ["compare": "before_claude"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["comparer"]?.string, "avantClaude")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["image"]?.string, "À gauche avant, à droite maintenant.")
        let before = try XCTUnwrap(info["mesures_avant"]?["luminosite_L"]?["moyenne"]?.double)
        let after = try XCTUnwrap(info["mesures"]?["luminosite_L"]?["moyenne"]?.double)
        XCTAssertLessThan(before, after)
        XCTAssertNil(info["chemin_avant"])
    }

    func testAnalyzePhotosAgainstReference() throws {
        let grays: [Int: UInt8] = [1: 119, 2: 60, 3: 119]
        fake.onSend = { [unowned self] command, params in
            guard command == "apercu", let id = params["photo"]?.int, let gray = grays[id] else { return }
            XCTAssertEqual(params["taille"]?.int, ToolHandler.analysisSize)
            fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: gray, green: gray, blue: gray))),
                                      "photo": ["id": .number(Double(id)), "fichier": .string("P\(id).RAF")]]
        }
        let result = call("analyze_photos", ["photo_ids": [2, 3], "reference_id": 1])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["reference"]?["fichier"]?.string, "P1.RAF")
        let photos = try XCTUnwrap(info["photos"]?.array)
        XCTAssertEqual(photos.count, 2)
        XCTAssertGreaterThan(photos[0]["ecart_avec_reference"]?["exposition_IL"]?.double ?? 0, 0.9)
        XCTAssertEqual(photos[1]["ecart_avec_reference"]?["indications"], ["Déjà proche de la référence."])

        XCTAssertTrue(call("analyze_photos", ["photo_ids": .array((1...31).map { .number(Double($0)) })]).isError)
    }

    // MARK: Profils, paramètres prédéfinis, copie, journal

    func testListProfilesForTheCameraOfThePhoto() throws {
        fake.replies["reglages"] = ["appareil": ["marque": "FUJIFILM", "modele": "X-H2S"]]
        let info = try JSONCoding.parse(call("list_profiles", ["photo_id": 4]).text)
        XCTAssertEqual(info["appareil"]?.string, "FUJIFILM X-H2S")
        XCTAssertEqual(info["profils_look"]?["Camera"], ["Camera CLASSIC Neg"], "une seule fois, pour cet appareil")
        XCTAssertEqual(info["profils_look"]?["B&W"], ["B&W 01 (intensité réglable)"])
        XCTAssertEqual(info["profils_appareil"]?.array?.count, DevelopCatalogue.profiles.count)

        fake.replies["reglages"] = ["appareil": ["marque": "NIKON CORPORATION", "modele": "NIKON Z 6"]]
        let nikon = try JSONCoding.parse(call("list_profiles", [:]).text)
        XCTAssertNil(nikon["profils_look"]?["Camera"])
        XCTAssertEqual(nikon["profils_appareil"]?.array?.count, 1, "Adobe Standard seulement")
    }

    func testPresetsAndCopySettings() throws {
        _ = call("list_presets", ["query": "été", "limit": 5000])
        XCTAssertEqual(fake.lastParams["filtre"]?.string, "été")
        XCTAssertEqual(fake.lastParams["limite"]?.int, 1000)

        fake.replies["creerPreset"] = [
            "reglages": ["Exposure2012": 0.3, "Vibrance": 20, "ProcessVersion": "15.4", "PointColors": [["SrcHue": 0.1]],
                         "ToneCurvePV2012": [0, 10, 255, 255], "Look": ["Name": "Adobe Color", "UUID": "B95", "Amount": 1,
                                                                        "Parameters": ["CameraProfile": "Adobe Standard"]]],
            "source": ["id": 4, "fichier": "XH2S0320.RAF"],
        ]
        // include_masks n'existe pas pour save_preset : refusé, plutôt qu'ignoré.
        XCTAssertTrue(call("save_preset", ["name": "Bateau gris", "include_masks": true]).text.contains("Paramètres inconnus pour save_preset : include_masks"))
        let saved = call("save_preset", ["name": "Bateau gris", "groups": ["Tonalité", "présence"]])
        XCTAssertFalse(saved.isError, saved.text)
        XCTAssertEqual(fake.calls.last?.command, "creerPreset")
        let keys = try XCTUnwrap(fake.lastParams["cles"]?.array?.compactMap(\.string))
        XCTAssertTrue(keys.contains("Exposure2012") && keys.contains("Vibrance"))
        XCTAssertFalse(keys.contains("Temperature"))
        XCTAssertEqual(fake.lastParams["inclure"]?["masques"]?.bool, false, "un paramètre prédéfini XMP ne porte pas de masques")
        XCTAssertEqual(fake.lastParams["inclure"]?["profil"]?.bool, true)
        let info = try JSONCoding.parse(saved.text)
        let file = try XCTUnwrap(info["fichier"]?.string)
        XCTAssertEqual(URL(fileURLWithPath: file).deletingLastPathComponent().lastPathComponent, "Claude")
        XCTAssertEqual(info["laisses_de_cote"], ["PointColors"])
        let xmp = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertTrue(xmp.contains("crs:Exposure2012=\"0.3\""))
        XCTAssertTrue(xmp.contains("<rdf:li xml:lang=\"x-default\">Bateau gris</rdf:li>"))
        XCTAssertTrue(xmp.contains("<crs:Look>"))
        XCTAssertTrue(call("save_preset", ["name": " "]).isError)
        XCTAssertTrue(call("save_preset", ["name": "x", "groups": ["Couleurs"]]).isError)

        _ = call("copy_settings", ["source_id": 1, "selection": true, "include_crop": true, "reason": "Même lumière."])
        XCTAssertEqual(fake.calls.last?.command, "copier")
        XCTAssertEqual(fake.lastParams["source"]?.int, 1)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.count, DevelopCatalogue.keys.count)
        XCTAssertEqual(fake.lastParams["inclure"]?["recadrage"]?.bool, true)
        XCTAssertEqual(fake.lastParams["inclure"]?["masques"]?.bool, false)
        XCTAssertEqual(fake.lastParams["raison"]?.string, "Même lumière.")
        XCTAssertTrue(call("copy_settings", ["source_id": 1]).isError, "photos visées obligatoires")
    }

    func testExportJournalAsMarkdownAndFile() throws {
        fake.replies["journal"] = ["photos": [[
            "photo": ["id": 7, "fichier": "XH2S0001.RAF"],
            "entrees": [
                ["date": "2026-10-16 10:12", "etape": "Claude · passe 1", "raison": "Photo sombre.",
                 "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.35], ["cle": "CameraProfile", "avant": "Adobe Color", "apres": "Camera Velvia/Vivid"]]],
                ["date": "2026-10-16 10:20", "etape": "Annulation de « Claude · passe 1 »", "changements": [], "note": "Réglages remis : Exposure2012"],
                ["date": "2026-10-16 10:25", "etape": "Claude · passe 1 bis", "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.2]],
                 "note": "Profil « Camera PRO Neg. Hi » non appliqué : Lightroom ne l'a pas gardé (relu : « Adobe Standard »)."],
            ],
        ]]]
        let folder = TestSupport.temporaryDirectory()
        let file = folder.appendingPathComponent("Journal.md")
        let result = call("export_journal", ["save_to": .string(file.path)])
        XCTAssertFalse(result.isError, result.text)
        let markdown = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(markdown.contains("## XH2S0001.RAF (id 7)"))
        XCTAssertTrue(markdown.contains("### 2026-10-16 10:12 — Claude · passe 1"))
        XCTAssertTrue(markdown.contains("Pourquoi : Photo sombre."))
        XCTAssertTrue(markdown.contains("- Exposition : 0 → 0,35"))
        XCTAssertTrue(markdown.contains("- Profil : Adobe Color → Camera Velvia/Vivid"))
        XCTAssertTrue(markdown.contains("- Réglages remis : Exposure2012"))
        XCTAssertTrue(markdown.contains("- Exposition : 0 → 0,2\n- Profil « Camera PRO Neg. Hi » non appliqué"), "remarque d'une retouche, après ses changements")
        XCTAssertEqual(try JSONCoding.parse(result.text)["fichier"]?.string, file.path)
        // Jamais d'écrasement : le second journal est renommé.
        let second = call("export_journal", ["save_to": .string(file.path)])
        XCTAssertEqual(try JSONCoding.parse(second.text)["fichier"]?.string, folder.appendingPathComponent("Journal 2.md").path)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), markdown, "le premier fichier est intact")

        XCTAssertTrue(call("export_journal", ["save_to": "/dossier/qui/n/existe/pas/j.md"]).isError)
    }

    func testEveryToolIsDefinedOnceInOrder() {
        let names = tools.definitions.compactMap { $0["name"]?.string }
        XCTAssertEqual(names, ToolHandler.toolNames)
        XCTAssertEqual(Set(names).count, names.count)
    }
}
