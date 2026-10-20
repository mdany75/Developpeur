import CoreGraphics
import XCTest
@testable import DeveloppeurKit

final class MesuresTests: XCTestCase {
    func testUniformGrayIsNeutralMidtone() throws {
        let measures = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 119, green: 119, blue: 119)))
        XCTAssertEqual(measures.meanL, 50, accuracy: 1.5, "gris sRGB 119 ≈ L* 50")
        XCTAssertEqual(measures.medianL, measures.meanL, accuracy: 0.6)
        XCTAssertEqual(measures.clippedHighlights, 0)
        XCTAssertEqual(measures.crushedShadows, 0)
        XCTAssertEqual(measures.contrast, 0, accuracy: 0.5)
        XCTAssertEqual(measures.neutralShare, 100, accuracy: 0.1)
        XCTAssertEqual(measures.castReading, "neutre")
        XCTAssertEqual(measures.histogramL.reduce(0, +), 100, accuracy: 0.01)
        XCTAssertEqual(measures.histogramL[5], 100, accuracy: 0.01, "tranche 50 à 60")

        let json = measures.json
        XCTAssertNotNil(json["luminosite_L"]?["mediane"])
        XCTAssertEqual(json["couleur"]?["tons_neutres"]?["lecture"]?.string, "neutre")
    }

    func testClippingAndCast() throws {
        let white = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 255, green: 255, blue: 255)))
        XCTAssertEqual(white.clippedHighlights, 100, accuracy: 0.1)
        XCTAssertEqual(white.pureWhite, 100, accuracy: 0.1)

        let black = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 0, green: 0, blue: 0)))
        XCTAssertEqual(black.crushedShadows, 100, accuracy: 0.1)

        let warm = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 140, green: 128, blue: 105)))
        XCTAssertGreaterThan(warm.neutralB, 6)
        XCTAssertTrue(warm.castReading.contains("chaude"), warm.castReading)

        let saturated = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 230, green: 20, blue: 20)))
        XCTAssertEqual(saturated.saturatedShare, 100, accuracy: 0.1)
        XCTAssertEqual(saturated.neutralShare, 0)
        XCTAssertEqual(saturated.castReading, "trop peu de tons neutres pour juger la dominante")

        XCTAssertNil(Measurements.analyze(Data([1, 2, 3])))
    }

    func testCompareWithReference() throws {
        let dark = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 60, green: 60, blue: 60)))
        let reference = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 119, green: 119, blue: 119)))
        let gap = Measurements.compare(dark, toReference: reference)
        let exposure = try XCTUnwrap(gap["exposition_IL"]?.double)
        XCTAssertEqual(exposure, 2.05, accuracy: 0.1, "gris sRGB 60 → 119 : luminance linéaire multipliée par 4, environ +2 IL")
        XCTAssertTrue(gap["indications"]?.array?.first?.string?.hasPrefix("Exposure2012 : environ +") ?? false)

        let cool = try XCTUnwrap(Measurements.analyze(TestSupport.jpeg(red: 105, green: 120, blue: 140)))
        let warmer = Measurements.compare(cool, toReference: reference)
        XCTAssertTrue(warmer["indications"]?.array?.contains("Temperature : réchauffer (vers le jaune)") ?? false, "\(warmer)")

        let same = Measurements.compare(reference, toReference: reference)
        XCTAssertEqual(same["indications"], ["Déjà proche de la référence."])
    }

    func testCropAndSideBySide() throws {
        let image = TestSupport.jpeg(red: 100, green: 150, blue: 200, width: 4000, height: 3000)
        let piece = try XCTUnwrap(PreviewImages.crop(image, region: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)))
        XCTAssertEqual(piece.width, 1000)
        XCTAssertEqual(piece.height, 750)
        XCTAssertEqual(piece.zoom, 100, "zone plus petite que 1600 px : pixel pour pixel")

        let large = try XCTUnwrap(PreviewImages.crop(image, region: CGRect(x: 0, y: 0, width: 1, height: 1)))
        XCTAssertEqual(large.width, PreviewImages.maxSide)
        XCTAssertEqual(large.zoom, 40)
        XCTAssertNil(PreviewImages.crop(image, region: CGRect(x: 0.5, y: 0.5, width: 0.001, height: 0.001)))

        let left = TestSupport.jpeg(red: 0, green: 0, blue: 0, width: 300, height: 200)
        let right = TestSupport.jpeg(red: 255, green: 255, blue: 255, width: 150, height: 100)
        let both = try XCTUnwrap(PreviewImages.sideBySide(left, right))
        let combined = try XCTUnwrap(PreviewImages.image(both))
        XCTAssertEqual(combined.height, 100, "même hauteur : la plus petite")
        XCTAssertEqual(combined.width, 150 + 4 + 150)
    }
}
