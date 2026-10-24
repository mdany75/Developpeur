import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// La carte du masque (1.3.4) : un rendu témoin par masque, comparé à l'état actuel, dit où il
/// porte ; les alertes viennent de cette lecture.
final class CarteMasqueTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    /// Une carte de synthèse : les pixels où `dedans` est vrai.
    static func carte(largeur: Int = 100, hauteur: Int = 100, _ dedans: (Double, Double) -> Bool) -> [Bool] {
        (0..<(largeur * hauteur)).map { i in dedans((Double(i % largeur) + 0.5) / Double(largeur), (Double(i / largeur) + 0.5) / Double(hauteur)) }
    }

    func testLaLectureDitLaPartLaZoneEtLesVisagesCouverts() {
        let hautDeLImage = Self.carte { _, y in y < 0.3 }
        let visage = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2)
        let lecture = CarteMasque.lire(hautDeLImage, largeur: 100, hauteur: 100, visages: [visage])
        XCTAssertEqual(lecture.part, 30, accuracy: 0.01)
        XCTAssertEqual(lecture.zone?.minY ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(lecture.zone?.height ?? 0, 0.3, accuracy: 0.01)
        XCTAssertEqual(lecture.centre?.y ?? 0, 0.15, accuracy: 0.01)
        XCTAssertEqual(lecture.visages[0], 0.5, accuracy: 0.01, "la moitié haute du visage")
        let vide = CarteMasque.lire(Self.carte { _, _ in false }, largeur: 100, hauteur: 100, visages: [])
        XCTAssertEqual(vide.part, 0)
        XCTAssertNil(vide.zone)
    }

    func testLesAlertes() {
        let visage = CGRect(x: 0.4, y: 0.2, width: 0.2, height: 0.2)
        func alertes(_ dedans: @escaping (Double, Double) -> Bool, masque: JSONValue, genre: String?, visages: [CGRect] = [visage]) -> [String] {
            let lecture = CarteMasque.lire(Self.carte(dedans), largeur: 100, hauteur: 100, visages: visages)
            return CarteMasque.alertes(lecture, masque: masque, genre: genre)
        }
        let ciel: JSONValue = ["type": "ia", "inverser": false]
        // Un ciel qui déborde sur le visage.
        let debord = alertes({ _, y in y < 0.3 }, masque: ciel, genre: "sky")
        XCTAssertEqual(debord.count, 1)
        XCTAssertTrue(debord[0].hasPrefix("déborde sur un visage : visage 1 à 50 %"), debord[0])
        // Un ciel en bas de l'image, loin du visage : semble inversé.
        XCTAssertTrue(alertes({ _, y in y > 0.7 }, masque: ciel, genre: "sky").contains { $0.hasPrefix("semble inversé") })
        // Inversé exprès : pas d'alerte d'inversion.
        XCTAssertTrue(alertes({ _, y in y > 0.7 }, masque: ["type": "ia", "inverser": true], genre: "sky").isEmpty)
        // Presque vide : une seule alerte, rien d'autre ne se juge.
        let vide = alertes({ x, y in x < 0.05 && y < 0.05 }, masque: ciel, genre: "sky")
        XCTAssertEqual(vide.count, 1)
        XCTAssertTrue(vide[0].hasPrefix("presque vide"), vide[0])
        // Presque total.
        XCTAssertTrue(alertes({ _, _ in true }, masque: ciel, genre: "background", visages: []).contains { $0.hasPrefix("presque total") })
        // Un masque qui vise une personne ne déborde pas sur un visage ; un radial non inversé non plus.
        XCTAssertTrue(alertes({ _, y in y < 0.5 }, masque: ["type": "personne"], genre: "person").isEmpty)
        XCTAssertTrue(alertes({ _, y in y < 0.5 }, masque: ["type": "radial", "inverser": false], genre: "radial").isEmpty)
        // Un radial inversé (les bords) qui mange le visage : il déborde.
        XCTAssertTrue(alertes({ _, y in y < 0.5 }, masque: ["type": "radial", "inverser": true], genre: "radial").contains { $0.hasPrefix("déborde") })
        // Un sujet qui couvre tout sauf les visages : semble inversé.
        XCTAssertTrue(alertes({ x, y in !(x > 0.35 && x < 0.65 && y > 0.15 && y < 0.45) }, masque: ciel, genre: "subject")
            .contains { $0.hasPrefix("semble inversé") })
    }

    func testLeTemoinGardeLaZoneEtRemplaceLEffet() {
        let masque: JSONValue = ["type": "radial", "centre_x": 0.5, "inverser": true, "quantite": 0.5,
                                 "locaux": ["LocalTexture": -0.2], "couleurs_ponctuelles": ["x"], "nom": "Claude · Peau"]
        let temoin = CarteMasque.masqueTemoin(masque)
        XCTAssertEqual(temoin["type"], "radial")
        XCTAssertEqual(temoin["centre_x"], 0.5)
        XCTAssertEqual(temoin["inverser"], true)
        XCTAssertEqual(temoin["quantite"], 1)
        XCTAssertEqual(temoin["locaux"], .object(CarteMasque.temoin))
        XCTAssertNil(temoin["couleurs_ponctuelles"])
    }

    /// add_mask avec mask_map : un rendu témoin par masque (l'état actuel avec le premier
    /// seulement), puis les masques posés ; la carte et ses alertes dans la réponse, son image en tête.
    func testAddMaskAvecLaCarteDesMasques() throws {
        fake.onSend = { [unowned fake] command, params in
            guard command == "essayer" else { return }
            var reponse: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(AnalyseTests.rendreMasque(params)))]
            if params["comparer"]?.bool == true {
                var actuel = params
                actuel["masques"] = .array([])
                reponse["chemin_actuel"] = .string(TestSupport.previewFile(AnalyseTests.rendreMasque(actuel)))
            }
            fake!.replies["essayer"] = .object(reponse)
        }
        let result = tools.call(name: "add_mask", arguments: [
            "masks": [["kind": "linear", "from_x": 0.5, "from_y": 0, "to_x": 0.5, "to_y": 0.4, "adjustments": ["Exposure": -0.5]],
                      ["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 0.2, "radius_y": 0.2, "feather": 0,
                       "adjustments": ["Exposure": 0.3]]],
            "step_name": "éclaircir et assombrir", "mask_map": true,
        ])
        XCTAssertFalse(result.isError, result.text)
        let essais = fake.calls.filter { $0.command == "essayer" }
        XCTAssertEqual(essais.count, 2, "un rendu témoin par masque")
        XCTAssertEqual(essais.map { $0.params["comparer"]?.bool }, [true, false], "l'état actuel une seule fois")
        XCTAssertEqual(essais[0].params["masques"]?.array?.count, 1)
        XCTAssertEqual(essais[0].params["masques"]?.array?.first?["locaux"], .object(CarteMasque.temoin))
        XCTAssertEqual(fake.commands.last, "masquer", "les masques posés après les cartes")
        XCTAssertEqual(fake.calls.last?.params["masques"]?.array?.first?["locaux"]?["LocalExposure2012"], .number(-0.125), "les vrais réglages")
        if case .image = result.content.first {} else { XCTFail("l'image de la carte en tête") }
        let carte = try XCTUnwrap(JSONCoding.parse(result.text)["carte_des_masques"])
        let masques = try XCTUnwrap(carte["masques"]?.array)
        XCTAssertEqual(masques.count, 2)
        let lineaire = try XCTUnwrap(masques[0]["part_de_l_image_pct"]?.double)
        XCTAssertGreaterThan(lineaire, 10)
        XCTAssertLessThan(lineaire, 60)
        XCTAssertLessThan(masques[0]["zone"]?["y"]?.double ?? 1, 0.05, "le dégradé part du haut")
        let radial = try XCTUnwrap(masques[1]["part_de_l_image_pct"]?.double)
        XCTAssertGreaterThan(radial, 5)
        XCTAssertLessThan(radial, 25)
        XCTAssertNotNil(carte["image"])

        // Sans mask_map : aucun rendu témoin.
        fake.calls.removeAll()
        let sans = tools.call(name: "add_mask", arguments: [
            "masks": [["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 0.2, "radius_y": 0.2, "adjustments": ["Exposure": 0.3]]],
            "step_name": "sujet",
        ])
        XCTAssertFalse(sans.isError, sans.text)
        XCTAssertFalse(fake.commands.contains("essayer"))
        XCTAssertNil(try JSONCoding.parse(sans.text)["carte_des_masques"])
    }

    func testLaCarteNeVautQuePourUneSeulePhoto() {
        let result = tools.call(name: "add_mask", arguments: [
            "masks": [["kind": "sky", "adjustments": ["Exposure": -0.3]]], "step_name": "ciel", "mask_map": true, "selection": true,
        ])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("mask_map"), result.text)
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est envoyé")
    }
}
