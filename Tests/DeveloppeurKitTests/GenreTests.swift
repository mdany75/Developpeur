import CoreGraphics
import Vision
import XCTest
@testable import DeveloppeurKit

/// Le genre d'une photo (correctif 1.3.8) : les règles de `Genre.classer`, pures, sur des indices
/// faits à la main d'après le relevé du 26 octobre 2026 (les étiquettes et les visages que Vision a
/// donnés pour des vignettes de photos de Dany), et la liste du contrat.
final class GenreTests: XCTestCase {
    typealias Indices = Genre.Indices

    func testListeEtLibelles() {
        XCTAssertEqual(Genre.codes, ["sport", "evenement", "famille", "portrait", "macro", "animaux", "nourriture", "vehicules", "ville",
                                     "paysage", "autre"])
        XCTAssertEqual(Set(Genre.codes).count, Genre.codes.count, "chaque code une fois")
        XCTAssertEqual(Genre.libelle("famille"), "Famille et groupes")
        XCTAssertEqual(Genre.libelle("autre"), "Autre")
        XCTAssertEqual(Genre.libelle("inconnu"), "inconnu")
        XCTAssertEqual(Genre.codes.last, "autre")
    }

    func testContrat() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Contrats/suivi.json")
        let contrat = try JSONCoding.parse(String(contentsOf: url, encoding: .utf8))
        let liste = try XCTUnwrap(contrat["regles"]?["analyser"]?["genres"]?["liste"]?.array)
        XCTAssertEqual(liste.map { $0.array?.first?.string ?? "" }, Genre.codes)
        XCTAssertEqual(liste.map { $0.array?.last?.string ?? "" }, Genre.liste.map(\.libelle))
    }

    func testObjectifMacro() {
        XCTAssertTrue(Genre.estMacro("XF80mmF2.8 R LM OIS WR Macro"))
        XCTAssertTrue(Genre.estMacro("Fujifilm Fujinon XF80mmF2.8 R LM OIS WR MACRO"))
        XCTAssertFalse(Genre.estMacro("XF56mmF1.2 R"))
        XCTAssertFalse(Genre.estMacro(nil))
    }

    /// Les cas du relevé : ce que Vision a dit, et le genre que l'œil donnait.
    func testReleveDuVingtSixOctobre() {
        // 50105466 : un garçon qui court sur un terrain de soccer.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sport": 0.91, "soccer": 0.9, "people": 0.44], visages: [0.063], corps: [0.288])), "sport")
        // 53281759 : le terrain le soir, joueuses au loin : sport à 0,52 à pleine taille, 0,4 à 1 024 px.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["outdoor": 0.96, "grass": 0.92, "sport": 0.42, "people": 0.77])), "sport")
        // 45985001 : un visage en gros plan.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.75, "adult": 0.75], visages: [0.539], corps: [0.983])), "portrait")
        // 43177511 : une jeune femme en pied sur une dune.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["adult": 0.81, "people": 0.81, "sky": 0.13], visages: [0.117], corps: [0.146])), "portrait")
        // 53766722 : en pied sur la plage, le visage petit : le corps fait le portrait.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.9, "lake": 0.7], visages: [0.05], corps: [0.117])), "portrait")
        // 53448216 : un groupe sur le traversier.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.96, "fence": 0.88, "lake": 0.77], visages: [0.083, 0.082, 0.08],
                                             corps: [0.107, 0.099, 0.092])), "famille")
        // 53736204 : un couple, deux visages de même taille.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.9, "foliage": 0.89], visages: [0.205, 0.191], corps: [0.314, 0.242])),
                       "famille")
        // 53733089 : deux personnes de dos, sans visage.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.92, "grass": 0.86], corps: [0.271, 0.207])), "famille")
        // 53580454 : un chien noir, que les étiquettes ne voient presque pas (0,16) ; VNRecognizeAnimalsRequest, si.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["grass": 0.89, "leash": 0.61, "dog": 0.16, "animal": 0.16],
                                             animauxVus: [.init(confiance: 0.63, surface: 0.364)])), "animaux")
        // 46956988 : une tortue.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["animal": 0.84, "reptile": 0.84, "grass": 0.68])), "animaux")
        // 53740151 : un avion de chasse dans le ciel ; 52126554 : un hélicoptère (0,87 contre le ciel à 0,88).
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["aircraft": 0.9, "vehicle": 0.9, "sky": 0.72])), "vehicules")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sky": 0.88, "vehicle": 0.87, "helicopter": 0.87])), "vehicules")
        // 53448416 : un voilier au loin, sous le pont de Québec : le pont l'emporte (le bateau à 0,70 contre 0,92).
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["bridge": 0.92, "sky": 0.9, "lake": 0.75, "boat": 0.7, "vehicle": 0.7])), "ville")
        // 53626762 : un bateau à moteur sur le fleuve (0,62 contre le ciel à 0,82) : un paysage.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sky": 0.82, "lake": 0.73, "vehicle": 0.62, "speedboat": 0.62])), "paysage")
        // 49285094 : le Château Frontenac et la foule, sans visage lu.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sky": 0.85, "people": 0.81, "crowd": 0.69, "building": 0.52, "castle": 0.52])),
                       "ville")
        // 49325329 : la mer.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sky": 0.99, "ocean": 0.77, "water_body": 0.77])), "paysage")
        // 53709677 : une remise de diplôme devant des ballons.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.92, "balloon": 0.89], visages: [0.114], corps: [0.212])), "evenement")
        // 52123884 : le flanc d'un avion de près, que Vision lit mal : autre.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["vehicle": 0.27, "aircraft": 0.27, "document": 0.15])), "autre")
    }

    /// Ce que le relevé n'avait pas : macro, nourriture ; et l'ordre des règles.
    func testMacroNourritureEtOrdre() {
        // Un insecte de près, une fleur seule, un objectif macro sans personne.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["insect": 0.7, "butterfly": 0.6, "plant": 0.5])), "macro")
        // Une fleur de près, comme Vision la rend (« plant » et « foliage » à la confiance de la fleur :
        // la rose et le tournesol de /Library/User Pictures, relecture du 26 octobre 2026).
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["flower": 0.94, "plant": 0.94, "rose": 0.94])), "macro")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["flower": 0.95, "plant": 0.95, "sunflower": 0.95, "foliage": 0.6])), "macro")
        // Le pissenlit donne aussi « food » (herb) à la même confiance : une fleur, pas de la nourriture.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["dandelion": 0.93, "food": 0.93, "herb": 0.93, "plant": 0.93])), "macro")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["flower": 0.7, "plant": 0.7, "sky": 0.8, "grass": 0.75])), "paysage",
                       "un champ de fleurs")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["flower": 0.65, "plant": 0.65, "tree": 0.6])), "paysage", "un jardin et son arbre")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["structure": 0.3], objectifMacro: true)), "macro")
        // L'objectif macro, avec une personne : un portrait (l'XF80 sert aussi au portrait).
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["people": 0.9], visages: [0.3], objectifMacro: true)), "portrait")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["food": 0.8, "dessert": 0.7, "table": 0.4])), "nourriture")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["food": 0.8, "fruit": 0.8, "plant": 0.3])), "nourriture", "un fruit")
        // Le sport passe avant les personnes ; la fête aussi.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sport": 0.6], visages: [0.3, 0.29])), "sport")
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["wedding": 0.7], visages: [0.2, 0.19])), "evenement")
        // Un second visage bien plus petit (un passant) : un portrait, pas un groupe.
        XCTAssertEqual(Genre.classer(Indices(visages: [0.3, 0.06])), "portrait")
        // Des visages minuscules (une foule au loin) : ni portrait ni groupe.
        XCTAssertEqual(Genre.classer(Indices(etiquettes: ["sky": 0.7], visages: [0.03, 0.03, 0.02])), "paysage")
        // Rien de sûr : autre.
        XCTAssertEqual(Genre.classer(Indices()), "autre")
        // Les indices se trient eux-mêmes (le plus grand d'abord).
        XCTAssertEqual(Indices(visages: [0.06, 0.3]).visages, [0.3, 0.06])
    }

    /// Chaque étiquette des ensembles existe parmi celles de Vision (une étiquette inconnue ne compterait
    /// jamais : « prairie », retirée).
    func testEtiquettesDeVision() throws {
        let connues = Set(try VNClassifyImageRequest().supportedIdentifiers())
        XCTAssertGreaterThan(connues.count, 1000)
        for (nom, ensemble) in [("sport", Genre.sport), ("evenement", Genre.evenement), ("animaux", Genre.animaux),
                                ("insectes", Genre.insectes), ("nourriture", Genre.nourriture), ("fleurs", Genre.fleurs),
                                ("vehicules", Genre.vehicules), ("ville", Genre.ville), ("nature", Genre.nature)] {
            XCTAssertEqual(ensemble.subtracting(connues), [], nom)
        }
        XCTAssertFalse(Genre.sceneAutourDUneFleur.contains("plant"))
        XCTAssertFalse(Genre.sceneAutourDUneFleur.contains("foliage"))
    }

    /// Un visage à l'envers (le devant d'une voiture, au roulis −π) n'est pas une personne.
    func testVisagesALEnvers() {
        func visage(_ hauteur: CGFloat, roulis: Double?) -> VisionReport.Face {
            VisionReport.Face(box: CGRect(x: 0.4, y: 0.3, width: hauteur * 0.7, height: hauteur), pupils: [], eyeWidth: nil, quality: nil,
                              eyeOpenness: nil, yaw: nil, roll: roulis)
        }
        let rapport = VisionReport(faces: [visage(0.2, roulis: -Double.pi), visage(0.12, roulis: 0.1), visage(0.1, roulis: nil)],
                                   aesthetics: nil, utility: nil, salientArea: nil)
        XCTAssertEqual(Genre.visages(rapport).map(\.height), [0.12, 0.1], "le visage à l'envers écarté")
        XCTAssertEqual(Genre.visages(nil), [])
        let voiture = VisionReport(faces: [visage(0.2, roulis: Double.pi)], aesthetics: nil, utility: nil, salientArea: nil)
        let indices = Indices(etiquettes: ["car": 0.8, "vehicle": 0.8, "sky": 0.5], visages: Genre.visages(voiture).map { Double($0.height) })
        XCTAssertEqual(Genre.classer(indices), "vehicules", "ni portrait ni famille")
    }

    func testPrincipales() {
        XCTAssertEqual(Genre.principales(["a": 0.2, "b": 0.9, "c": 0.5, "d": 0.5]), ["b", "c", "d"])
        XCTAssertEqual(Genre.principales([:]), [])
    }

    /// Vision sur une image unie : des indices sans plantage, et un genre de la liste.
    func testLireUneImageUnie() throws {
        let contexte = try XCTUnwrap(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        contexte.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        contexte.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let image = try XCTUnwrap(contexte.makeImage())
        let indices = Genre.lire(image, visages: [], objectif: "XF80mmF2.8 R LM OIS WR Macro")
        XCTAssertTrue(indices.objectifMacro)
        XCTAssertTrue(indices.visages.isEmpty)
        XCTAssertTrue(Genre.codes.contains(Genre.classer(indices)))
    }
}
