import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Deux lectures de view_photo de la 1.3.4 : la nature de l'écrêtage (luminance ou gamme) et les
/// points chauds (zones claires hors du sujet).
final class EcretageEtPointsChaudsTests: XCTestCase {
    /// Une image de synthèse : `couleur(x, y)` pour chaque pixel (x et y de 0 à 1 depuis le coin haut gauche).
    static func image(largeur: Int = 300, hauteur: Int = 200, _ couleur: (Double, Double) -> (UInt8, UInt8, UInt8)) -> CGImage {
        let data = TestSupport.jpegPixels(width: largeur, height: hauteur) { px, py in
            couleur((Double(px) + 0.5) / Double(largeur), (Double(py) + 0.5) / Double(hauteur))
        }
        return PreviewImages.image(data)!
    }

    func testUnRougeBruleParLaGammeSeCorrigeParLaTSL() throws {
        // Des fleurs rouges saturées sur un fond moyen : un canal à 255, les autres bas.
        let fleurs = Self.image { x, _ in x < 0.3 ? (255, 30, 40) : (110, 120, 100) }
        let mesures = try XCTUnwrap(Measurements.analyze(fleurs))
        XCTAssertGreaterThan(mesures.clippedGamut, 20)
        XCTAssertEqual(mesures.gamutBand, "rouge")
        let nature = try XCTUnwrap(mesures.natureEcretage)
        XCTAssertTrue(nature["lecture"]?.string?.hasPrefix("par la gamme (rouge)") == true, nature["lecture"]?.string ?? "")
        XCTAssertEqual(nature["bande_tsl"], "rouge")
        XCTAssertNotNil(mesures.json["ecretage_nature"])
    }

    func testUnCielBlancBruleParLaLuminanceSeCorrigeParLesHautesLumieres() throws {
        let ciel = Self.image { _, y in y < 0.3 ? (255, 255, 255) : (110, 120, 100) }
        let mesures = try XCTUnwrap(Measurements.analyze(ciel))
        XCTAssertEqual(mesures.clippedGamut, 0)
        let nature = try XCTUnwrap(mesures.natureEcretage)
        XCTAssertTrue(nature["lecture"]?.string?.hasPrefix("par la luminance") == true)
        XCTAssertNil(nature["bande_tsl"])
    }

    func testRienAEcreterRienADire() throws {
        let sombre = Self.image { _, _ in (90, 100, 80) }
        let mesures = try XCTUnwrap(Measurements.analyze(sombre))
        XCTAssertNil(mesures.natureEcretage)
        XCTAssertNil(mesures.json["ecretage_nature"])
    }

    func testLesBandesDeLaTSL() {
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(255, 0, 0)].nom, "rouge")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(255, 128, 0)].nom, "orange")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(255, 255, 0)].nom, "jaune")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(0, 255, 0)].nom, "vert")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(0, 255, 255)].nom, "aqua")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(0, 0, 255)].nom, "bleu")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(255, 0, 255)].nom, "magenta")
        XCTAssertEqual(PhotoMeasurements.bandes[PhotoMeasurements.bande(250, 10, 30)].nom, "rouge", "un rouge qui tire vers le magenta reste rouge")
    }

    func testLesPointsChaudsHorsDuSujet() {
        // Un intérieur moyen : une fenêtre claire en haut à droite, une nappe claire en bas à gauche,
        // et un visage clair au centre (le sujet), écarté.
        let interieur = Self.image { x, y in
            if x > 0.75, y < 0.25 { return (245, 245, 240) }
            if x < 0.3, y > 0.8 { return (225, 225, 220) }
            if x > 0.42, x < 0.58, y > 0.35, y < 0.6 { return (240, 230, 220) }
            return (90, 85, 80)
        }
        let visage = CGRect(x: 0.4, y: 0.33, width: 0.2, height: 0.3)
        let zones = PointsChauds.trouver(interieur, sujet: [visage])
        XCTAssertEqual(zones.count, 2, "la fenêtre et la nappe, pas le visage")
        XCTAssertEqual(PointsChauds.ou(zones[0].boite), "en haut à droite", "la fenêtre d'abord : plus claire et plus grande")
        XCTAssertEqual(PointsChauds.ou(zones[1].boite), "en bas à gauche")
        XCTAssertGreaterThan(zones[0].ecart, PointsChauds.ecartMediane)
        // Sans sujet donné, le visage clair compte aussi.
        XCTAssertEqual(PointsChauds.trouver(interieur, sujet: []).count, 3)
        // Une zone d'intérêt trop grande ne désigne pas de sujet.
        XCTAssertEqual(PointsChauds.trouver(interieur, sujet: [CGRect(x: 0, y: 0, width: 0.9, height: 0.9)]).count, 3)
        let json = PointsChauds.json(zones)
        XCTAssertEqual(json?["zones"]?.array?.count, 2)
        XCTAssertTrue(json?["lecture"]?.string?.contains("Rien n'est corrigé d'office") == true)
    }

    func testUnFondClairOuUnPetitRefletNeSontPasDesPointsChauds() {
        // Un grand ciel clair (plus de 20 % de l'image) et un reflet minuscule.
        let paysage = Self.image { x, y in
            if y < 0.45 { return (235, 238, 240) }
            if x > 0.5, x < 0.51, y > 0.7, y < 0.71 { return (255, 255, 255) }
            return (80, 90, 60)
        }
        XCTAssertTrue(PointsChauds.trouver(paysage, sujet: []).isEmpty)
        XCTAssertNil(PointsChauds.json([]))
        // Une image uniforme : rien.
        XCTAssertTrue(PointsChauds.trouver(Self.image { _, _ in (128, 128, 128) }, sujet: []).isEmpty)
    }
}
