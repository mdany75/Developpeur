import XCTest
@testable import DeveloppeurKit

/// `--especes-essai` (EssaiEspeces) : les sources de `--sens-essai`, en lecture seule, la planche à
/// juger et les seuils tirés du jugement. Faux BioCLIP et fausse porte, jamais le vrai modèle.
final class EssaiEspecesTests: XCTestCase {
    var dossier: URL!

    override func setUp() {
        dossier = TestSupport.temporaryDirectory().appendingPathComponent("essai-especes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dossier)
    }

    func classeur(porte: EncodeurSens? = FaussePorte()) throws -> ClasseurEspeces {
        try ClasseurEspeces.ouvrir(liste: try Especes.Liste(contenu: EspecesTests.petiteListe), encodeur: FauxBioCLIP(),
                                   cache: dossier.appendingPathComponent("cache"), empreinteModele: "m", porte: porte)
    }

    func testLEssaiSurUnDossierDImagesEtSaPlanche() throws {
        let images = dossier.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try TestSupport.jpeg(red: 230, green: 20, blue: 20).write(to: images.appendingPathComponent("a.jpg"))
        try TestSupport.jpeg(red: 20, green: 20, blue: 230).write(to: images.appendingPathComponent("b<x>.jpg"))
        try Data("pas une image".utf8).write(to: images.appendingPathComponent("c.jpg"))
        let essai = EssaiEspeces(lightroom: nil, classeur: try classeur())
        let r = try essai.lancer(source: .images(images), cible: .groupe(Especes.groupe(nom: "oiseau")!), planche: images)
        let lignes = try XCTUnwrap(r["images"]?.array)
        XCTAssertEqual(lignes.count, 3)
        let rouge = try XCTUnwrap(lignes.first { $0["fichier"] == "a.jpg" })
        XCTAssertEqual(rouge["espece"]?["nom"], "Cardinal rouge")
        XCTAssertEqual(try XCTUnwrap(rouge["scores"]?["porte"]?.double), 1, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(rouge["scores"]?["bioclip"]?.double), 0.9)
        XCTAssertGreaterThan(try XCTUnwrap(rouge["scores"]?["ecart"]?.double), 0.8, "écart de la 1re à la 2e")
        XCTAssertNotNil(rouge["score_cherche"], "avec --espece")
        let bleue = try XCTUnwrap(lignes.first { $0["fichier"] == "b<x>.jpg" })
        XCTAssertLessThan(try XCTUnwrap(bleue["scores"]?["porte"]?.double), 0.5, "la porte : rien de vivant")
        XCTAssertNotNil(lignes.first { $0["fichier"] == "c.jpg" }?["erreur"])

        // La planche : une case par photo lue, la vignette dedans, les boutons et le JSON à copier.
        let chemin = try XCTUnwrap(r["planche"]?.string)
        XCTAssertEqual(chemin, images.appendingPathComponent(EssaiEspeces.nomPlanche).path)
        let html = try String(contentsOfFile: chemin, encoding: .utf8)
        XCTAssertEqual(html.components(separatedBy: "<figure class=\"case\"").count - 1, 2)
        XCTAssertEqual(html.components(separatedBy: "data:image/jpeg;base64,").count - 1, 2)
        XCTAssertTrue(html.contains("Cardinal rouge"))
        XCTAssertTrue(html.contains(">Juste</button>") && html.contains(">Faux</button>"))
        XCTAssertTrue(html.contains("Copier le jugement") && html.contains("--jugement"))
        XCTAssertTrue(html.contains("b&lt;x&gt;.jpg"), "le nom de fichier échappé")
        XCTAssertFalse(html.contains("b<x>.jpg\">") || html.contains(">b<x>.jpg<"))
        // Les données de la page : porte, score et écart de chaque photo.
        let debut = try XCTUnwrap(html.range(of: "const PHOTOS = "))
        let fin = try XCTUnwrap(html.range(of: ";\n", range: debut.upperBound..<html.endIndex))
        let donnees = try JSONCoding.parse(String(html[debut.upperBound..<fin.lowerBound]).replacingOccurrences(of: "<\\/", with: "</"))
        XCTAssertEqual(donnees.array?.count, 2)
        XCTAssertEqual(donnees.array?.first?["espece"], "Cardinal rouge")
        XCTAssertNotNil(donnees.array?.first?["porte"]?.double)
    }

    func testLEssaiDansLightroomNeLitQueDesVignettesDe512() throws {
        let lightroom = FakeLightroom()
        let vignette = dossier.appendingPathComponent("v.jpg")
        try TestSupport.jpeg(red: 230, green: 20, blue: 20).write(to: vignette)
        lightroom.replies["chercher"] = ["photos": [["id": 11, "fichier": "A.RAF"], ["id": 12, "fichier": "V.MOV", "video": true]]]
        lightroom.replies["vignettes"] = ["photos": [["id": 11, "fichier": "A.RAF", "vignette": .string(vignette.path)]]]
        var appels = 0
        lightroom.onSend = { commande, _ in
            if commande == "chercher" {
                appels += 1
                if appels > 1 { lightroom.replies["chercher"] = ["photos": []] }
            }
        }
        let planche = dossier.appendingPathComponent("planche")
        let r = try EssaiEspeces(lightroom: lightroom, classeur: try classeur()).lancer(source: .collection("Développeur › Essais"), planche: planche)
        XCTAssertEqual(r["images"]?.array?.count, 1, "la vidéo sautée")
        XCTAssertEqual(r["images"]?.array?.first?["fichier"], "A.RAF")
        XCTAssertEqual(Set(lightroom.commands), ["chercher", "vignettes"], "des lectures seulement")
        XCTAssertTrue(lightroom.commands.allSatisfy { LightroomBridge.lectures.contains($0) })
        XCTAssertEqual(lightroom.calls.first?.params["collection"], "Développeur › Essais")
        XCTAssertEqual(lightroom.calls.first { $0.command == "vignettes" }?.params["taille"]?.int, Especes.tailleVignette)
        XCTAssertTrue(FileManager.default.fileExists(atPath: planche.appendingPathComponent(EssaiEspeces.nomPlanche).path))
        // Une source du catalogue sans Lightroom : refusée, en nommant l'option.
        XCTAssertThrowsError(try EssaiEspeces(lightroom: nil, classeur: try classeur()).lancer(source: .ids([1]))) { erreur in
            XCTAssertTrue(erreur.localizedDescription.contains("--especes-essai"))
        }
    }

    func testLesSeuilsDApresLeJugement() throws {
        // Score : justes à 0,9, 0,8, 0,7 et 0,4 ; faux à 0,6, 0,5 et 0,3. Le meilleur seuil est 0,65
        // (3 justes gardés, 3 faux écartés), contre 3 et 1 au seuil provisoire 0,5.
        // Porte : séparation nette (justes ≥ 0,9, faux ≤ 0,2). Écart : sans faux mesuré, pas jugé.
        func j(_ score: Double, _ porte: Double, _ juste: Bool, ecart: Double? = nil) -> JSONValue {
            ["id": 1, "score": .number(score), "porte": .number(porte), "ecart": ecart.map(JSONValue.number) ?? .null, "juste": .bool(juste)]
        }
        let jugement: JSONValue = ["modele": "BioCLIP-2", "jugements": [
            j(0.9, 0.95, true, ecart: 0.8), j(0.8, 0.9, true, ecart: 0.7), j(0.7, 0.92, true), j(0.4, 0.97, true),
            j(0.6, 0.2, false), j(0.5, 0.1, false), j(0.3, 0.15, false),
            ["id": 9, "score": 0.99],  // pas jugée
        ]]
        let r = EssaiEspeces.seuils(jugement)
        XCTAssertEqual(r["jugees"], 7)
        XCTAssertEqual(r["justes"], 4)
        XCTAssertEqual(r["faux"], 3)
        let score = try XCTUnwrap(r["mesures"]?["score"])
        XCTAssertEqual(try XCTUnwrap(score["seuil"]?.double), 0.65, accuracy: 0.001)
        XCTAssertEqual(score["justes_gardes"], 3)
        XCTAssertEqual(score["faux_ecartes"], 3)
        XCTAssertEqual(score["separation_nette"], false)
        XCTAssertEqual(score["provisoire"]?["justes_gardes"], 3)
        XCTAssertEqual(score["provisoire"]?["faux_ecartes"], 1, "0,5 atteint le seuil : gardé")
        let porte = try XCTUnwrap(r["mesures"]?["porte"])
        XCTAssertEqual(porte["separation_nette"], true)
        XCTAssertEqual(porte["exactitude"], 1)
        XCTAssertNotNil(r["mesures"]?["ecart"]?["remarque"])
        XCTAssertEqual(r["la_plus_separatrice"], "porte")
        let resume = try XCTUnwrap(r["resume"]?.string)
        XCTAssertTrue(resume.contains("score BioCLIP : seuil 0,65, garde 3 justes sur 4 et écarte 3 faux sur 3"), resume)
        // La seule liste marche aussi ; sans faux, pas de seuil.
        XCTAssertEqual(EssaiEspeces.seuils(jugement["jugements"]!)["jugees"], 7)
        XCTAssertNotNil(EssaiEspeces.seuils(["jugements": [j(0.9, 0.9, true)]])["remarque"])
    }
}
