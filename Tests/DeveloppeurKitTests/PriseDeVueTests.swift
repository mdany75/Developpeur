import XCTest
@testable import DeveloppeurKit

/// Le vocabulaire des défauts de la prise de vue (1.3), seule liste du carnet de progrès (la leçon
/// de la photo, qui le reprenait aussi, est retirée en 1.3.6), et la définition de read_composition,
/// dont la longueur de la description est gardée.
final class PriseDeVueTests: XCTestCase {
    /// Les seize codes, dans l'ordre du carnet.
    static let codes = [
        "horizon_penche", "verticales_fuyantes", "cadrage_large", "sujet_centre", "bords_encombres",
        "sous_exposition", "surexposition", "ciel_brule", "ombres_bouchees", "contraste_plat",
        "bruit", "flou", "mise_au_point", "dominante", "eclairage_mixte", "couleurs_ternes",
    ]
    static let motsInterdits = ["photoshop", "galerie", "gallery", "concours", "client", "mariage", "firefly", "agrandissement",
                                "crédit adobe", "expand_photo"]

    private func definition(_ nom: String) throws -> JSONValue {
        try XCTUnwrap(ToolHandler(lightroom: FakeLightroom()).definitions.first { $0["name"]?.string == nom }, nom)
    }

    func testCodesUniques() {
        let defauts = PriseDeVue.defauts
        XCTAssertEqual(defauts.map(\.code), Self.codes)
        XCTAssertEqual(Set(defauts.map(\.code)).count, defauts.count, "un code par défaut")
        for defaut in defauts {
            XCTAssertNotNil(defaut.code.range(of: "^[a-z_]+$", options: .regularExpression), defaut.code)
            XCTAssertEqual(PriseDeVue.defaut(code: defaut.code), defaut)
        }
        XCTAssertNil(PriseDeVue.defaut(code: "horizon"), "un seul code pour l'horizon penché")
    }

    /// Quatre domaines pour le carnet : la netteté (flou, mise au point, bruit) a le sien.
    func testDomaines() {
        XCTAssertEqual(PriseDeVue.Domaine.allCases.map(\.code), ["lumiere", "nettete", "couleur", "composition"])
        XCTAssertEqual(PriseDeVue.Domaine.allCases.map(\.nom), ["Lumière", "Netteté", "Couleur", "Composition"])
        XCTAssertEqual(Set(PriseDeVue.defauts.map(\.domaine)), Set(PriseDeVue.Domaine.allCases), "chaque domaine sert")
        XCTAssertEqual(PriseDeVue.defauts.filter { $0.domaine == .nettete }.map(\.code), ["bruit", "flou", "mise_au_point"])
        XCTAssertEqual(PriseDeVue.defauts.filter { $0.domaine == .couleur }.map(\.code), ["dominante", "eclairage_mixte", "couleurs_ternes"])
    }

    /// Le carnet ne compte d'après une mesure que six défauts ; les autres venaient des leçons
    /// (retirées en 1.3.6) et restent dans la liste.
    func testSixDefautsMesures() {
        XCTAssertEqual(PriseDeVue.mesures.map(\.code), ["horizon_penche", "sous_exposition", "ciel_brule", "bruit", "flou", "mise_au_point"])
        XCTAssertEqual(PriseDeVue.defauts.filter { !$0.mesure }.count, 10)
    }

    func testTextesCourtsEtPourUnAmateur() {
        for defaut in PriseDeVue.defauts {
            XCTAssertFalse(defaut.libelle.isEmpty, defaut.code)
            XCTAssertLessThanOrEqual(defaut.libelle.count, PriseDeVue.longueurLibelle, defaut.libelle)
            XCTAssertLessThanOrEqual(defaut.conseil.count, PriseDeVue.longueurConseil, "\(defaut.code) : \(defaut.conseil.count) caractères")
            XCTAssertTrue(defaut.conseil.hasSuffix("."), defaut.conseil)
            XCTAssertEqual(defaut.libelle.first?.isUppercase, true, defaut.libelle)
        }
        XCTAssertEqual(Set(PriseDeVue.defauts.map(\.libelle)).count, PriseDeVue.defauts.count, "un libellé par défaut")
        let tout = JSONCoding.line(PriseDeVue.vocabulaire).lowercased()
        for mot in Self.motsInterdits {
            XCTAssertFalse(tout.contains(mot), "« \(mot) » dans le vocabulaire")
        }
    }

    /// Le JSON envoyé au module : un tableau dans l'ordre de la liste, codes français, sans métatable
    /// à craindre côté Lua (des textes, des booléens) ; ni clé anglaise ni axe (1.3.6 : ils ne
    /// servaient qu'à la leçon, et le module les tient pour facultatifs).
    func testVocabulaireEnvoyeAuModule() throws {
        let vocabulaire = try XCTUnwrap(PriseDeVue.vocabulaire.array)
        XCTAssertEqual(vocabulaire.compactMap { $0["code"]?.string }, Self.codes)
        let ciel = try XCTUnwrap(vocabulaire.first { $0["code"]?.string == "ciel_brule" })
        XCTAssertEqual(Set(ciel.object?.keys.map { $0 } ?? []), ["code", "domaine", "libelle", "conseil", "mesure"])
        XCTAssertEqual(ciel["domaine"]?.string, "lumiere")
        XCTAssertEqual(ciel["mesure"]?.bool, true)
        XCTAssertEqual(vocabulaire.first { $0["code"]?.string == "bruit" }?["domaine"]?.string, "nettete")
        XCTAssertEqual(vocabulaire.first { $0["code"]?.string == "dominante" }?["mesure"]?.bool, false)
    }

    // MARK: L'outil qui le reprend

    /// read_composition : sa description tient en 1 000 caractères et dit les étapes temporaires
    /// « Claude · composition », et que rien n'est appliqué.
    func testReadCompositionDecrit() throws {
        let composition = try definition("read_composition")
        let description = try XCTUnwrap(composition["description"]?.string)
        XCTAssertLessThanOrEqual(description.count, 1000, "read_composition : \(description.count) caractères")
        for attendu in ["image entière", "« Claude · composition »", "la photo revient telle quelle", "Rien n'est appliqué",
                        "preview_settings", "attendre l'accord", "apply_settings avec le même crop", "à la prise de vue"] {
            XCTAssertTrue(description.contains(attendu), "read_composition sans « \(attendu) »")
        }
        let proprietes = try XCTUnwrap(composition["inputSchema"]?["properties"]?.object)
        XCTAssertEqual(Set(proprietes.keys), ["photo_id", "horizon", "horizon_third", "subject", "facing", "subject_place", "aspect",
                                              "size", "min_size"])
        XCTAssertEqual(proprietes["horizon"]?["required"], ["x1", "y1", "x2", "y2"])
        XCTAssertEqual(proprietes["horizon"]?["additionalProperties"], false)
        XCTAssertEqual(proprietes["subject"]?["required"], ["x", "y", "width", "height"])
        XCTAssertEqual(proprietes["horizon_third"]?["enum"], ["lower", "upper"])
        XCTAssertEqual(proprietes["facing"]?["enum"], ["left", "right", "none"])
        XCTAssertEqual(proprietes["subject_place"]?["enum"], ["third", "center"])
        XCTAssertTrue(proprietes["min_size"]?["description"]?.string?.contains("de 0,5 à 1, défaut 0,75") == true,
                      proprietes["min_size"]?["description"]?.string ?? "")
    }
}
