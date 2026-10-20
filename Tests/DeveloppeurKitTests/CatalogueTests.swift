import XCTest
@testable import DeveloppeurKit

final class CatalogueTests: XCTestCase {
    func testKeysAreUniqueAndRangesAreSane() {
        let keys = DevelopCatalogue.keys
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertEqual(keys.count, 124)
        for setting in DevelopCatalogue.all {
            XCTAssertLessThan(setting.min, setting.max, setting.key)
            XCTAssertFalse(setting.label.isEmpty, setting.key)
        }
        XCTAssertEqual(DevelopCatalogue.groups.first, "Balance des blancs")
        XCTAssertEqual(DevelopCatalogue.groups.last, "Calibrage de l'appareil")
        XCTAssertTrue(DevelopCatalogue.groups.contains("Noir et blanc"))
        XCTAssertEqual(DevelopCatalogue.booleanKeys, ["ConvertToGrayscale"])
        XCTAssertTrue(DevelopCatalogue.setting("ConvertToGrayscale")?.isSwitch ?? false)
        XCTAssertTrue(DevelopCatalogue.setting("PostCropVignetteStyle")?.isWhole ?? false)
        XCTAssertEqual(DevelopCatalogue.setting("GrayMixerAqua")?.label, "Mélangeur noir et blanc : bleu-vert")
        XCTAssertEqual(DevelopCatalogue.setting("DefringePurpleAmount")?.max, 20)
        XCTAssertEqual(DevelopCatalogue.setting("HueAdjustmentAqua")?.label, "TSL : teinte bleu-vert")
        XCTAssertTrue(DevelopCatalogue.setting("LensProfileEnable")?.isSwitch ?? false)
        XCTAssertTrue(DevelopCatalogue.setting("PerspectiveUpright")?.isWhole ?? false)
        XCTAssertFalse(DevelopCatalogue.setting("PerspectiveUpright")?.isSwitch ?? true)
        XCTAssertEqual(DevelopCatalogue.setting("ParametricShadowSplit")?.range, [10, 70])
        XCTAssertEqual(DevelopCatalogue.setting("ParametricHighlightSplit")?.neutral, 75)
        XCTAssertEqual(DevelopCatalogue.setting("CurveRefineSaturation")?.neutral, 100)
        // Des valeurs neutres (25, 50, 75, 100) que Lightroom range toujours : view_photo ne les montre pas.
        let shown = ToolHandler.grouped(["ParametricShadowSplit": 25, "ParametricMidtoneSplit": 40, "CurveRefineSaturation": 100,
                                         "PerspectiveScale": 100, "Exposure2012": 0], onlyChanged: true)
        XCTAssertEqual(shown, ["Courbe des tonalités": ["ParametricMidtoneSplit": 40]])
        // Valeurs par défaut de Lightroom relevées sur une copie jamais retouchée (rayon 1, détail 25,
        // détail du bruit 50…) : cachées ; la netteté 40 et le bruit couleur 25 seulement sur un RAW ;
        // le groupe HDR seulement en mode HDR.
        XCTAssertEqual(DevelopCatalogue.setting("SharpenRadius")?.neutral, 1)
        XCTAssertEqual(DevelopCatalogue.setting("DefringePurpleHueHi")?.neutral, 70)
        let defauts: [String: JSONValue] = ["SharpenRadius": 1, "SharpenDetail": 25, "ColorNoiseReductionDetail": 50, "GrainSize": 25,
                                            "Sharpness": 40, "ColorNoiseReduction": 25, "HDRMaxValue": 2.3, "HDREditMode": 0, "Vibrance": 12]
        XCTAssertEqual(ToolHandler.grouped(defauts, onlyChanged: true, raw: true), ["Présence": ["Vibrance": 12]])
        XCTAssertEqual(ToolHandler.grouped(defauts, onlyChanged: true), ["Présence": ["Vibrance": 12], "Détail": ["Sharpness": 40, "ColorNoiseReduction": 25]])
        var hdr = defauts
        hdr["HDREditMode"] = 1
        XCTAssertEqual(ToolHandler.grouped(hdr, onlyChanged: true, raw: true)["HDR"], ["HDREditMode": 1, "HDRMaxValue": 2.3])
        XCTAssertNil(DevelopCatalogue.setting("CropAngle"), "le recadrage passe par le paramètre crop")
        XCTAssertNil(DevelopCatalogue.setting(DevelopCatalogue.profileKey), "le profil passe par le paramètre profile")
    }

    func testProfiles() {
        let names = DevelopCatalogue.profiles.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(names.first, "Adobe Standard")
        XCTAssertNil(DevelopCatalogue.profile("Adobe Standard")?.make)
        XCTAssertEqual(DevelopCatalogue.profile("Camera CLASSIC CHROME")?.make, "FUJIFILM")
        XCTAssertNil(DevelopCatalogue.profile("Adobe Color"), "profil à base de Look : pas proposé")
        XCTAssertEqual(DevelopCatalogue.profile("camera pro neg. std")?.name, "Camera Pro Neg Std", "par une variante, sans la casse")
        let all = DevelopCatalogue.profiles.flatMap { [$0.name] + $0.variants }.map { $0.lowercased() }
        XCTAssertEqual(Set(all).count, all.count, "aucun nom ni variante partagé entre deux profils")
    }

    func testRangesAndLabelsForPlugin() {
        XCTAssertEqual(DevelopCatalogue.ranges(for: ["Exposure2012", "Inconnu"]), ["Exposure2012": [-5, 5]])
        XCTAssertEqual(DevelopCatalogue.labels(for: ["Dehaze", "CameraProfile", "CropAngle", "Inconnu"]),
                       ["Dehaze": "Correction du voile", "CameraProfile": "Profil", "CropAngle": "Recadrage : angle"])
        XCTAssertEqual(DevelopCatalogue.label(for: "MaskGroupBasedCorrections"), "Masques")
        XCTAssertEqual(DevelopCatalogue.label(for: "ToneCurvePV2012Blue"), "Courbe par points (bleu)")
        XCTAssertEqual(DevelopCatalogue.label(for: "Look"), "Profil (Look)")
    }

    func testFormat() {
        XCTAssertEqual(DevelopCatalogue.format(2), "2")
        XCTAssertEqual(DevelopCatalogue.format(-40), "-40")
        XCTAssertEqual(DevelopCatalogue.format(0.35), "0.35")
        XCTAssertEqual(DevelopCatalogue.format(0.5), "0.5")
    }
}
