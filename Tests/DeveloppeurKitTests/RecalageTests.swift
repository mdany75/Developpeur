import CoreGraphics
import Foundation
import XCTest
@testable import DeveloppeurKit

/// Recalage de la géométrie sur des images de synthèse : une texture sans motif répété, vue telle
/// quelle (image d'origine) et à travers une déformation connue (image corrigée).
final class RecalageTests: XCTestCase {
    /// Texture de bruit à plusieurs échelles, interpolée : la même en tout point réel.
    struct Texture {
        let grilles: [(pas: Double, valeurs: [Double], n: Int)]

        init(graine: UInt64) {
            var etat = graine
            func hasard() -> Double {
                etat = etat &* 6364136223846793005 &+ 1442695040888963407
                return Double(etat >> 33) / Double(1 << 31)
            }
            grilles = [(9.0, 70.0), (23.0, 60.0), (61.0, 50.0)].map { pas, amplitude in
                let n = Int(2000 / pas) + 3
                return (pas, (0..<(n * n)).map { _ in hasard() * amplitude }, n)
            }
        }

        func valeur(_ x: Double, _ y: Double) -> Double {
            var somme = 30.0
            for g in grilles {
                let fx = max(0, x / g.pas + 1), fy = max(0, y / g.pas + 1)
                let i = min(Int(fx), g.n - 2), j = min(Int(fy), g.n - 2)
                let a = fx - Double(i), b = fy - Double(j)
                somme += g.valeurs[j * g.n + i] * (1 - a) * (1 - b) + g.valeurs[j * g.n + i + 1] * a * (1 - b)
                    + g.valeurs[(j + 1) * g.n + i] * (1 - a) * b + g.valeurs[(j + 1) * g.n + i + 1] * a * b
            }
            return somme
        }
    }

    static func image(_ largeur: Int, _ hauteur: Int, _ valeur: (Double, Double) -> Double) -> CGImage {
        var octets = [UInt8](repeating: 0, count: largeur * hauteur)
        for y in 0..<hauteur {
            for x in 0..<largeur {
                octets[y * largeur + x] = UInt8(min(max(valeur(Double(x) + 0.5, Double(y) + 0.5), 0), 255))
            }
        }
        return octets.withUnsafeMutableBytes { tampon in
            CGContext(data: tampon.baseAddress, width: largeur, height: hauteur, bitsPerComponent: 8, bytesPerRow: largeur,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
        }
    }

    /// Déformation connue : position dans l'image d'origine du pixel (x, y) de l'image corrigée.
    static func deformation(_ x: Double, _ y: Double, largeur: Double, hauteur: Double) -> (Double, Double) {
        // Perspective légère (comme Upright), puis distorsion radiale (comme un profil d'objectif).
        let w = 1 + 0.00002 * x - 0.00001 * y
        let px = (1.01 * x + 0.015 * y - 6) / w, py = (0.005 * x + 0.99 * y + 4) / w
        let unite = max(largeur, hauteur) / 2
        let dx = (px - largeur / 2) / unite, dy = (py - hauteur / 2) / unite
        let f = 1 + 0.025 * (dx * dx + dy * dy)
        return (largeur / 2 + dx * f * unite, hauteur / 2 + dy * f * unite)
    }

    func testRetrouveUneDeformationConnue() throws {
        let (w, h) = (1200, 800)
        let texture = Texture(graine: 42)
        let origine = Self.image(w, h) { texture.valeur($0, $1) }
        let corrigee = Self.image(w, h) { x, y in
            let (ox, oy) = Self.deformation(x, y, largeur: Double(w), hauteur: Double(h))
            return texture.valeur(ox, oy)
        }
        let resultat = try XCTUnwrap(Recalage.calculer(corrigee: corrigee, origine: origine))
        XCTAssertGreaterThan(resultat.zonesFiables, resultat.zonesEssayees / 2)
        var pire = 0.0
        for (u, v) in [(0.05, 0.5), (0.95, 0.5), (0.5, 0.05), (0.1, 0.9), (0.9, 0.1), (0.5, 0.5), (0.33, 0.66)] {
            let (ox, oy) = Self.deformation(u * Double(w), v * Double(h), largeur: Double(w), hauteur: Double(h))
            let trouve = resultat.grille.point(u, v)
            pire = max(pire, hypot(trouve.x * Double(w) - ox, trouve.y * Double(h) - oy))
        }
        XCTAssertLessThan(pire, 0.4, "écart au modèle connu, en pixels")
        // Les bords bougent de plus d'1 % : de quoi manquer une poussière sans recalage.
        XCTAssertGreaterThan(resultat.ecartMax, 0.01)
        // Écarts du modèle (--recalage) : le plus grand ne passe pas sous la moyenne ; près des bords,
        // ni au-dessus du plus grand ; tous sous le pixel sur ce modèle connu.
        XCTAssertGreaterThanOrEqual(resultat.residuMax, resultat.residu)
        XCTAssertLessThanOrEqual(resultat.residuBords, resultat.residuMax)
        XCTAssertGreaterThan(resultat.residuBords, 0, "des zones près des bords sont mesurées")
        XCTAssertLessThan(resultat.residuMax * Double(w), 1)
    }

    func testMemeImageSansDeplacement() throws {
        let texture = Texture(graine: 7)
        let image = Self.image(900, 600) { texture.valeur($0, $1) }
        let resultat = try XCTUnwrap(Recalage.calculer(corrigee: image, origine: image))
        XCTAssertLessThan(resultat.ecartMax * 900, 0.3)
    }

    func testImageUnieImpossibleARecaler() {
        let unie = Self.image(900, 600) { _, _ in 128 }
        XCTAssertNil(Recalage.calculer(corrigee: unie, origine: unie))
    }

    func testMoitieUnieLeModeleTientEncore() throws {
        // Un ciel uni sur la moitié haute : le modèle physique s'étend sans zone fiable là-haut.
        let (w, h) = (1200, 800)
        let texture = Texture(graine: 3)
        func scene(_ x: Double, _ y: Double) -> Double { y < 380 ? 200 : texture.valeur(x, y) }
        let origine = Self.image(w, h, scene)
        let corrigee = Self.image(w, h) { x, y in
            let (ox, oy) = Self.deformation(x, y, largeur: Double(w), hauteur: Double(h))
            return scene(ox, oy)
        }
        let resultat = try XCTUnwrap(Recalage.calculer(corrigee: corrigee, origine: origine))
        for (u, v) in [(0.05, 0.6), (0.95, 0.8), (0.5, 0.9)] {
            let (ox, oy) = Self.deformation(u * Double(w), v * Double(h), largeur: Double(w), hauteur: Double(h))
            let trouve = resultat.grille.point(u, v)
            XCTAssertLessThan(hypot(trouve.x * Double(w) - ox, trouve.y * Double(h) - oy), 1.5, "(\(u), \(v))")
        }
    }

    func testGrilleInterpoleCommeLeModule() {
        let grille = Recalage.Grille(colonnes: 2, lignes: 2, x: [0.0, 1.0, 0.1, 1.1], y: [0.0, 0.0, 1.0, 1.0])
        let p = grille.point(0.5, 0.5)
        XCTAssertEqual(p.x, 0.55, accuracy: 1e-12)
        XCTAssertEqual(p.y, 0.5, accuracy: 1e-12)
        XCTAssertEqual(grille.point(-1, 2).x, 0.1, accuracy: 1e-12, "bornée au cadre")
    }
}

/// Le recalage dans les outils : géométrie demandée au module, rendus lus une fois, grille gardée
/// pour la même géométrie, remarques quand le recalage est impossible.
final class RecalageOutilsTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var empreinte = "e1"
    var uni = false
    var transformation = false

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary(),
                            presetFolder: TestSupport.temporaryDirectory().appendingPathComponent("Claude"))
        let texture = RecalageTests.Texture(graine: 11)
        fake.onSend = { [unowned self] command, params in
            guard command == "geometrie" else { return }
            var info: [String: JSONValue] = ["photo": 4, "active": true, "transformation": .bool(self.transformation),
                                             "empreinte": .string(self.empreinte)]
            if params["rendre"]?.bool == true {
                // Image corrigée : l'origine vue 6 px plus à droite.
                let origine = RecalageTests.image(600, 400) { self.uni ? 120 : texture.valeur($0, $1) }
                let corrigee = RecalageTests.image(600, 400) { self.uni ? 120 : texture.valeur($0 + 6, $1) }
                info["chemin_corrige"] = .string(TestSupport.previewFile(PreviewImages.jpeg(corrigee, quality: 0.95)!))
                info["chemin_origine"] = .string(TestSupport.previewFile(PreviewImages.jpeg(origine, quality: 0.95)!))
            }
            self.fake.replies["geometrie"] = ["photos": [.object(info)]]
        }
    }

    private func spots() -> ToolResult {
        tools.call(name: "retouch_spots", arguments: ["spots": [["x": 0.5, "y": 0.5, "radius": 0.01]], "photo_id": 4, "step_name": "poussières"])
    }

    func testGrilleCalculeeUneFoisPuisGardee() throws {
        XCTAssertFalse(spots().isError)
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "geometrie", "retoucher"])
        XCTAssertEqual(fake.calls[0].params["photo"]?.int, 4)
        XCTAssertEqual(fake.calls[1].params["rendre"]?.bool, true)
        XCTAssertEqual(fake.calls[1].params["taille"]?.int, ToolHandler.tailleRecalage)
        let grille = try XCTUnwrap(fake.lastParams["recalages"]?["4"])
        XCTAssertEqual(grille["empreinte"]?.string, "e1")
        XCTAssertEqual(grille["colonnes"]?.int, Recalage.colonnes)
        // Le centre de l'image corrigée correspond à 6 px plus à droite dans l'origine.
        let milieu = (Recalage.lignes / 2) * Recalage.colonnes + Recalage.colonnes / 2
        let x = try XCTUnwrap(grille["x"]?.array?[milieu].double)
        XCTAssertEqual(x * 600 - 300, 6, accuracy: 0.5)

        fake.calls = []
        XCTAssertFalse(spots().isError)
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "retoucher"], "même géométrie : grille gardée")

        empreinte = "e2"
        fake.calls = []
        XCTAssertFalse(spots().isError)
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "geometrie", "retoucher"], "géométrie changée : nouveau calcul")
    }

    func testImageUniformeRemarqueEtPasDeGrille() throws {
        uni = true
        let result = spots()
        XCTAssertFalse(result.isError)
        XCTAssertNil(fake.lastParams["recalages"])
        XCTAssertTrue(result.text.contains("trop uniforme"), result.text)
        fake.calls = []
        _ = spots()
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "retoucher"], "l'échec aussi est gardé")
    }

    /// Constaté dans Lightroom Classic 15.6 : Upright laisse des coins vides dans le cadre, et
    /// « Contraindre le recadrage » les retire en déplaçant au besoin le cadre. Un recadrage demandé
    /// dans la même retouche qu'Upright se place ensuite sur la grille de la nouvelle géométrie, au
    /// centre demandé, et complète l'étape de la retouche.
    func testUprightPuisRecadrageSurLaNouvelleGeometrie() throws {
        transformation = true
        fake.replies["appliquer"] = ["resultats": [[
            "photo": ["id": 4], "etape": "Claude · géométrie", "a_recadrer": true, "etape_ecrite": true,
            "changements": [["cle": "PerspectiveUpright", "avant": 0, "apres": 2], ["cle": "CropConstrainToWarp", "avant": 0, "apres": 1],
                            ["cle": "CropLeft", "avant": 0, "apres": 0]],
            "remarques": [],
        ]]]
        fake.replies["recadrer"] = ["resultats": [[
            "photo": ["id": 4], "changements": [["cle": "CropLeft", "avant": 0, "apres": 0.04], ["cle": "CropTop", "avant": 0, "apres": 0.01]],
            "remarques": ["Cadre resserré sur l'image redressée (Upright, perspective) pour n'y laisser aucun coin vide : 91 % de la largeur de l'image."],
        ]]]
        let result = tools.call(name: "apply_settings", arguments: ["settings": ["PerspectiveUpright": 2], "crop": ["aspect": "1:1", "center_x": 0.6],
                                                                    "photo_ids": [4], "step_name": "géométrie", "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["appliquer", "geometrie", "geometrie", "recadrer"], "Upright dans la retouche : pas de grille avant")
        let demande = fake.lastParams
        XCTAssertEqual(demande["photos"], [4])
        XCTAssertEqual(demande["completer"], [4], "l'étape écrite est complétée")
        XCTAssertEqual(demande["etape"]?.string, "Claude · géométrie")
        XCTAssertEqual(demande["confirme"]?.bool, true)
        XCTAssertEqual(demande["recadrage"]?["centre_x"]?.double, 0.6, "le cadre demandé, centre compris")
        XCTAssertEqual(fake.calls[0].params["libelles"]?["CropConstrainToWarp"]?.string, "Recadrage : contraindre à l'image (sans coins vides)")
        XCTAssertEqual(demande["recalages"]?["4"]?["empreinte"]?.string, "e1")
        let reponse = try JSONCoding.parse(result.text)
        let photo = try XCTUnwrap(reponse["resultats"]?.array?.first)
        XCTAssertNil(photo["a_recadrer"])
        XCTAssertNil(photo["etape_ecrite"])
        let cles = (photo["changements"]?.array ?? []).compactMap { $0["cle"]?.string }
        XCTAssertEqual(cles, ["PerspectiveUpright", "CropConstrainToWarp", "CropLeft", "CropTop"], "les changements du cadre remplacent ceux de la retouche")
        XCTAssertEqual(photo["changements"]?.array?[2]["apres"]?.double, 0.04)
        XCTAssertEqual(photo["changements"]?.array?[2]["libelle"]?.string, "Recadrage : bord gauche")
        XCTAssertEqual(photo["changements"]?.array?[1]["libelle"]?.string, "Recadrage : contraindre à l'image (sans coins vides)")

        // Upright seul : Lightroom resserre le cadre lui-même, pas de seconde commande.
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 4], "etape": "Claude · géométrie", "changements": []]]]
        fake.calls = []
        _ = tools.call(name: "apply_settings", arguments: ["settings": ["PerspectiveUpright": 2], "photo_ids": [4], "step_name": "géométrie"])
        XCTAssertEqual(fake.commands, ["appliquer"])
        XCTAssertTrue(photo["remarques"]?.array?.first?.string?.hasPrefix("Cadre resserré") == true)
    }

    func testRecadrageDemandeSurUneGeometrieConnue() throws {
        // Profil d'objectif seul : pas de coin vide, rien à rendre.
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 4], "changements": []]]]
        _ = tools.call(name: "apply_settings", arguments: ["crop": ["aspect": "4:5"], "photo_ids": [4], "step_name": "cadre"])
        XCTAssertEqual(fake.commands, ["geometrie", "appliquer"])
        XCTAssertNil(fake.lastParams["recalages"])

        // Upright déjà posé : la grille part avec la retouche, le module calcule le cadre du premier coup.
        transformation = true
        fake.calls = []
        _ = tools.call(name: "apply_settings", arguments: ["crop": ["aspect": "4:5"], "photo_ids": [4], "step_name": "cadre"])
        XCTAssertEqual(fake.commands, ["geometrie", "geometrie", "appliquer"])
        XCTAssertEqual(fake.lastParams["recalages"]?["4"]?["empreinte"]?.string, "e1")
        XCTAssertEqual(fake.lastParams["recadrage"]?["ratio"]?.double, 0.8)

        // Upright et recadrage dans la même retouche : la grille vient après, si le module la demande.
        fake.calls = []
        _ = tools.call(name: "apply_settings", arguments: ["crop": ["aspect": "4:5"], "settings": ["PerspectiveUpright": 1],
                                                           "photo_ids": [4], "step_name": "cadre"])
        XCTAssertEqual(fake.commands, ["appliquer"])
        // Un recadrage retiré n'a pas besoin de grille.
        fake.calls = []
        _ = tools.call(name: "apply_settings", arguments: ["crop": ["reset": true], "photo_ids": [4], "step_name": "cadre"])
        XCTAssertEqual(fake.commands, ["appliquer"])
        // La proposition aussi reçoit la grille.
        fake.calls = []
        fake.onSend = { [unowned self, previous = fake.onSend] command, params in
            previous?(command, params)
            if command == "essayer" { self.fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 90, green: 90, blue: 90)))] }
        }
        let essai = tools.call(name: "preview_settings", arguments: ["crop": ["aspect": "1:1"], "photo_id": 4])
        XCTAssertFalse(essai.isError, essai.text)
        XCTAssertEqual(fake.commands, ["geometrie", "essayer"], "grille gardée")
        XCTAssertEqual(fake.lastParams["recalages"]?["4"]?["empreinte"]?.string, "e1")
        XCTAssertEqual(fake.lastParams["photo"]?.int, 4)
    }

    func testRecadrageNonPlaceRemarque() throws {
        transformation = true
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 4], "etape": "Claude · cadre", "a_recadrer": true, "etape_ecrite": true]]]
        fake.errors["recadrer"] = LightroomError.invalid("Lightroom est occupé")
        let result = tools.call(name: "apply_settings", arguments: ["settings": ["PerspectiveVertical": -10], "crop": ["aspect": "4:5"],
                                                                    "photo_ids": [4], "step_name": "cadre"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["appliquer", "geometrie", "geometrie", "recadrer"])
        XCTAssertTrue(result.text.contains("Recadrage demandé non placé"), result.text)
        XCTAssertFalse(result.text.contains("a_recadrer"))
    }

    func testMasquesSansPositionNiPhotoSansCorrection() throws {
        let ia = tools.call(name: "add_mask", arguments: ["masks": [["kind": "sky", "adjustments": ["Exposure": -0.3]]], "step_name": "ciel"])
        XCTAssertFalse(ia.isError, ia.text)
        XCTAssertEqual(fake.calls.map(\.command), ["masquer"], "masque IA : rien à recaler")

        fake.calls = []
        _ = tools.call(name: "add_mask", arguments: ["masks": [["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 0.1,
                                                                "adjustments": ["Exposure": -0.3]]],
                                                     "photo_ids": [4], "step_name": "rond"])
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "geometrie", "masquer"])
        XCTAssertEqual(fake.calls[0].params["photos"]?.array?.first?.int, 4)
        XCTAssertNotNil(fake.lastParams["recalages"]?["4"])

        fake.onSend = nil
        fake.replies["geometrie"] = ["photos": [["photo": 5, "active": false]]]
        fake.calls = []
        _ = tools.call(name: "retouch_spots", arguments: ["spots": [["x": 0.5, "y": 0.5, "radius": 0.01]], "photo_id": 5, "step_name": "x"])
        XCTAssertEqual(fake.calls.map(\.command), ["geometrie", "retoucher"])
        XCTAssertNil(fake.lastParams["recalages"])
    }
}
