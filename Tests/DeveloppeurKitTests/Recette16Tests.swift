import Foundation
import XCTest
@testable import DeveloppeurKit

/// Un module simulé pour la recette de Lightroom Classic 16 (Recette+16.swift) : réglages, masques
/// et étapes d'une copie d'essai, et un rendu de synthèse (un gris, éclairci par la Lueur, assombri
/// le long d'un trait de pinceau). Il imite ce que Lightroom 16.0 fait (docs/SPEC.md, Lightroom
/// Classic 16) : style de la Lueur gardé seulement si Glow > 0, valeurs entières. Des écarts
/// réglables (trait courbé sous la Projection, étalonnage local perdu, Lueur sans effet au rendu)
/// vérifient que chaque étape les dit.
final class ModuleRecette16: LightroomServing {
    let id = 7
    var version = "16.0"
    var reglages: [String: Double] = ["Exposure2012": 0, "Temperature": 5000, "Tint": 10, "Glow": 0, "GlowStyle": 1, "ReshapeAmount": 0]
    var masques: [(nom: String, locaux: [String: Double], traits: [JSONValue])] = []
    var memoire: [(reglages: [String: Double], masques: [(nom: String, locaux: [String: Double], traits: [JSONValue])])] = []
    var commandes: [(nom: String, params: [String: JSONValue])] = []
    // Écarts réglables.
    var traitCourbe = false
    var etalonnageLocalPerdu = false
    var lueurSansEffet = false
    static let largeur = 600, hauteur = 400

    func noms(_ commande: String) -> Int { commandes.filter { $0.nom == commande }.count }

    func image() -> Data {
        let glow = lueurSansEffet ? 0 : reglages["Glow"] ?? 0
        let traits = masques.flatMap { masque in masque.traits.map { (masque.locaux["LocalExposure2012"] ?? 0, $0) } }
        return TestSupport.jpegPixels(width: Self.largeur, height: Self.hauteur) { px, py in
            let x = (Double(px) + 0.5) / Double(Self.largeur), y = (Double(py) + 0.5) / Double(Self.hauteur)
            var v = 110 + glow * 0.4
            for (exposition, trait) in traits where exposition != 0 {
                let points = (trait["points"]?.array ?? []).compactMap { p -> (Double, Double)? in
                    guard let a = p.array, a.count == 2, let px = a[0].double, let py = a[1].double else { return nil }
                    return (px, py)
                }
                guard let debut = points.first, let fin = points.last, x >= debut.0, x <= fin.0 else { continue }
                // Sans recalage, la Projection courbe le trait (constaté : 0,17 au centre, 0,24 aux bords).
                var centre = debut.1
                if traitCourbe, (reglages["ReshapeAmount"] ?? 0) > 0 { centre += -0.03 + 0.09 * pow(2 * x - 1, 2) }
                let rayon = (trait["rayon"]?.double ?? 0.02) * Double(Self.largeur) / Double(Self.hauteur)
                if abs(y - centre) <= rayon { v *= pow(2, exposition) }
            }
            let n = UInt8(max(0, min(255, v.rounded())))
            return (n, n, n)
        }
    }

    var masquesJSON: JSONValue {
        .array(masques.map { ["nom": .string($0.nom), "composants": [], "actif": true, "intensite": 1,
                              "reglages_locaux": .object($0.locaux.mapValues { .number($0) })] })
    }

    func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue {
        commandes.append((command, params))
        switch command {
        case "etat":
            return ["lightroom": .string(version), "photo_active": ["id": .number(Double(id))]]
        case "reglages":
            var r: [String: JSONValue] = ["photo": ["id": .number(Double(id)), "fichier": "DSCF1595.RAF (Essai)", "copie_virtuelle": true],
                                          "reglages": .object(reglages.mapValues { .number($0) }), "masques": masquesJSON,
                                          "profil": "Adobe Color", "recadrage": ["angle": 0], "balance_des_blancs": "As Shot",
                                          "classement": ["note": 0]]
            if params["toutes"]?.bool == true { r["tous"] = .object(reglages.mapValues { .number($0) }) }
            return .object(r)
        case "apercu":
            return ["photo": ["id": .number(Double(id)), "fichier": "DSCF1595.RAF (Essai)"], "reglages": .object(reglages.mapValues { .number($0) }),
                    "recadrage": ["angle": 0], "chemin": .string(TestSupport.previewFile(image()))]
        case "geometrie":
            return ["photos": [["photo": .number(Double(id)), "active": false]]]
        case "appliquer":
            memoire.append((reglages, masques))
            var changements: [JSONValue] = []
            for (cle, valeur) in params["reglages"]?.object ?? [:] {
                guard let x = valeur.double else { continue }
                changements.append(["cle": .string(cle), "avant": .number(reglages[cle] ?? 0), "apres": .number(x)])
                reglages[cle] = x.rounded()
            }
            // Le style de la Lueur n'est gardé que si sa quantité est au-dessus de 0.
            if (reglages["Glow"] ?? 0) <= 0 { reglages["GlowStyle"] = 1 }
            return ["resultats": [["photo": ["id": .number(Double(id))], "etape": "Claude · recette", "changements": .array(changements), "remarques": []]]]
        case "masquer":
            memoire.append((reglages, masques))
            for masque in params["masques"]?.array ?? [] {
                var locaux = (masque["locaux"]?.object ?? [:]).compactMapValues(\.double)
                if etalonnageLocalPerdu { locaux = locaux.filter { !$0.key.hasPrefix("LocalColorGrade") } }
                masques.append((masque["nom"]?.string ?? "masque", locaux, masque["traits"]?.array ?? []))
            }
            return ["lightroom": .string(version), "resultats": [["photo": ["id": .number(Double(id))], "changements": [["cle": "MaskGroupBasedCorrections"]], "remarques": []]]]
        case "annuler":
            guard let derniere = memoire.popLast() else { return ["resultats": [["annulee": false]]] }
            (reglages, masques) = derniere
            return ["resultats": [["photo": ["id": .number(Double(id))], "annulee": true, "changements": []]]]
        default:
            return [:]
        }
    }
}

/// La recette de Lightroom Classic 16 face au module simulé : chaque étape réussit sur un module
/// juste, dit l'écart d'un module fautif, se défait, et se saute avec sa raison avant la 16.0.
final class Recette16Tests: XCTestCase {
    func details(_ recette: Recette) -> String { recette.etapes.map { "\($0.nom) : \($0.detail)" }.joined(separator: " | ") }

    func testLueurEtEtalonnageLocalReussissentPuisSontDefaits() throws {
        let module = ModuleRecette16()
        let depart = module.reglages
        let recette = Recette(lightroom: module)
        try recette.sequenceLightroom16(7, "RAW 7")
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertEqual(recette.etapes.map(\.nom), ["Lueur (Glow 40, style 2) relue en entiers, rendu changé, annulée",
                                                   "étalonnage dans un masque radial (ombres 220, 30), relu en entiers, annulé"])
        XCTAssertTrue(recette.etapes[0].detail.contains("Glow 40 et GlowStyle 2 relus"), recette.etapes[0].detail)
        XCTAssertTrue(recette.etapes[1].detail.contains("LocalColorGradeShadowHue 220"), recette.etapes[1].detail)
        let lueur = try XCTUnwrap(module.commandes.first { $0.nom == "appliquer" }?.params["reglages"])
        XCTAssertEqual(lueur["Glow"]?.double, 40)
        XCTAssertEqual(lueur["GlowStyle"]?.double, 2)
        let radial = try XCTUnwrap(module.commandes.first { $0.nom == "masquer" }?.params["masques"]?.array?.first)
        XCTAssertEqual(radial["type"]?.string, "radial")
        XCTAssertEqual(radial["locaux"]?["LocalColorGradeShadowHue"]?.double, 220)
        XCTAssertEqual(radial["locaux"]?["LocalColorGradeShadowSat"]?.double, 30)
        XCTAssertEqual(module.noms("annuler"), 2)
        XCTAssertEqual(module.reglages, depart)
        XCTAssertTrue(module.masques.isEmpty)
    }

    func testLueurSansEffetAuRenduOuEtalonnagePerduSeDisent() {
        let sansEffet = ModuleRecette16()
        sansEffet.lueurSansEffet = true
        let recette = Recette(lightroom: sansEffet)
        XCTAssertThrowsError(try recette.sequenceLightroom16(7, "RAW 7"))
        XCTAssertTrue(recette.etapes.first?.detail.contains("rendu inchangé par la Lueur") == true, details(recette))
        XCTAssertEqual(sansEffet.reglages["Glow"], 0, "annulée avant le verdict")

        let perdu = ModuleRecette16()
        perdu.etalonnageLocalPerdu = true
        let autre = Recette(lightroom: perdu)
        XCTAssertThrowsError(try autre.sequenceLightroom16(7, "RAW 7"))
        XCTAssertEqual(autre.etapes.map(\.reussie), [true, false])
        XCTAssertTrue(autre.etapes[1].detail.contains("au lieu de LocalColorGradeShadowHue 220"), details(autre))
        XCTAssertTrue(perdu.masques.isEmpty, "le masque est annulé avant le verdict")
    }

    func testProjectionTraitDroitAuCentreEtAuxBords() throws {
        let module = ModuleRecette16()
        let depart = module.reglages
        let recette = Recette(lightroom: module)
        try recette.etapeProjection(7, "JPEG 7")
        XCTAssertTrue(recette.reussie, details(recette))
        let detail = try XCTUnwrap(recette.etapes.first?.detail)
        XCTAssertTrue(detail.contains("bord gauche 0.2") && detail.contains("centre 0.2") && detail.contains("bord droit 0.2"), detail)
        let projection = try XCTUnwrap(module.commandes.first { $0.nom == "appliquer" }?.params["reglages"])
        XCTAssertEqual(projection["ReshapeAmount"]?.double, 100)
        let trait = try XCTUnwrap(module.commandes.first { $0.nom == "masquer" }?.params["masques"]?.array?.first?["traits"]?.array?.first)
        XCTAssertEqual(trait["rayon"]?.double, 0.01)
        XCTAssertEqual(trait["durete"]?.double, 1)
        XCTAssertEqual(trait["points"]?.array?.compactMap { $0.array?.last?.double }, [0.2, 0.2])
        XCTAssertEqual(module.noms("annuler"), 2)
        XCTAssertEqual(module.reglages, depart)
        XCTAssertTrue(module.masques.isEmpty)
    }

    /// Le constat de la 1.7 (0,170 au centre, 0,236 aux bords) : un trait courbé fait échouer l'étape.
    func testProjectionTraitCourbeSeDit() {
        let module = ModuleRecette16()
        module.traitCourbe = true
        let recette = Recette(lightroom: module)
        XCTAssertThrowsError(try recette.etapeProjection(7, "JPEG 7"))
        let detail = recette.etapes.first?.detail ?? ""
        XCTAssertTrue(detail.contains("trait courbé sous la Projection"), detail)
        XCTAssertTrue(detail.contains("bord gauche à") && detail.contains("centre à 0.17") && detail.contains("bord droit à"), detail)
        XCTAssertEqual(module.reglages["ReshapeAmount"], 0, "tout est annulé avant le verdict")
        XCTAssertTrue(module.masques.isEmpty)
    }

    func testAvantLaSeizeLesEtapesSontSauteesAvecLeurRaison() throws {
        let module = ModuleRecette16()
        module.version = "15.6"
        let recette = Recette(lightroom: module)
        try recette.sequenceLightroom16(7, "RAW 7")
        try recette.etapeProjection(7, "JPEG 7")
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertEqual(recette.etapes.count, 3)
        for etape in recette.etapes {
            XCTAssertTrue(etape.detail.hasPrefix("sautée : Lightroom Classic 15.6"), etape.detail)
        }
        XCTAssertFalse(module.commandes.contains { ["appliquer", "masquer", "annuler"].contains($0.nom) }, "rien d'écrit")
        XCTAssertEqual(Recette.raisonDeSauter16(""), "sautée : version de Lightroom Classic illisible (get_status)")
        XCTAssertNil(Recette.raisonDeSauter16("16.1"))
    }

    /// Les colonnes de la mesure de la bande : un trait limité au bord gauche ne se voit pas au centre.
    func testBandeAssombrieDansDesColonnes() throws {
        let avant = TestSupport.jpegPixels(width: 200, height: 100) { _, _ in (120, 120, 120) }
        let apres = TestSupport.jpegPixels(width: 200, height: 100) { x, y in
            (x < 40 && (18...22).contains(y)) || (x >= 40 && (48...52).contains(y)) ? (30, 30, 30) : (120, 120, 120)
        }
        let gauche = try XCTUnwrap(Recette.bandeAssombrie(avant: avant, apres: apres, colonnes: 0.04...0.14))
        let centre = try XCTUnwrap(Recette.bandeAssombrie(avant: avant, apres: apres, colonnes: 0.45...0.55))
        XCTAssertEqual(gauche.centre, 0.205, accuracy: 0.02)
        XCTAssertEqual(centre.centre, 0.505, accuracy: 0.02)
    }

    /// Les deux séquences appellent la recette de la 16, à la fin.
    func testLesSequencesRAWEtJPEGAppellentLaRecette16() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: racine.appendingPathComponent("Sources/DeveloppeurKit/Recette.swift"), encoding: .utf8)
        func corps(_ debut: String) throws -> String {
            let d = try XCTUnwrap(source.range(of: debut))
            let f = try XCTUnwrap(source.range(of: "\n    }\n", range: d.upperBound..<source.endIndex))
            return String(source[d.upperBound..<f.lowerBound])
        }
        XCTAssertTrue(try corps("func sequenceRAW(").hasSuffix("try sequenceLightroom16(id, photo)"))
        XCTAssertTrue(try corps("func sequenceJPEG(").hasSuffix("try etapeProjection(id, photo)"))
    }
}
