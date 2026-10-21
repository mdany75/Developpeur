import XCTest
@testable import DeveloppeurKit

/// Le vocabulaire des défauts de la prise de vue (1.3), seule liste de la leçon de la photo et du
/// carnet de progrès, et les définitions des deux outils qui le reprennent (read_composition,
/// photo_lesson), dont la longueur de la description est gardée.
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

    func testCodesEtClesUniques() {
        let defauts = PriseDeVue.defauts
        XCTAssertEqual(defauts.map(\.code), Self.codes)
        XCTAssertEqual(Set(defauts.map(\.cle)).count, defauts.count, "une clé anglaise par défaut")
        XCTAssertTrue(Set(defauts.map(\.code)).isDisjoint(with: defauts.map(\.cle)), "codes français et clés anglaises distincts")
        for defaut in defauts {
            XCTAssertNotNil(defaut.code.range(of: "^[a-z_]+$", options: .regularExpression), defaut.code)
            XCTAssertNotNil(defaut.cle.range(of: "^[a-z_]+$", options: .regularExpression), defaut.cle)
            XCTAssertEqual(PriseDeVue.defaut(code: defaut.code), defaut)
            XCTAssertEqual(PriseDeVue.defaut(cle: defaut.cle), defaut)
        }
        XCTAssertNil(PriseDeVue.defaut(code: "horizon"), "un seul code pour l'horizon penché")
        XCTAssertEqual(PriseDeVue.defaut(cle: "tilted_horizon")?.code, "horizon_penche")
        XCTAssertEqual(PriseDeVue.defaut(cle: "missed_focus")?.code, "mise_au_point")
    }

    /// Trois axes pour la leçon, quatre domaines pour le carnet : la netteté (flou, mise au point,
    /// bruit) a son domaine, mais passe sous Lumière dans la leçon.
    func testAxesEtDomaines() {
        XCTAssertEqual(PriseDeVue.Axe.allCases.map(\.cle), ["light", "color", "composition"])
        XCTAssertEqual(PriseDeVue.Axe.allCases.map(\.code), ["lumiere", "couleur", "composition"])
        XCTAssertEqual(PriseDeVue.Axe.allCases.map(\.nom), ["Lumière", "Couleur", "Composition"])
        XCTAssertEqual(PriseDeVue.Axe(cle: "color"), .couleur)
        XCTAssertNil(PriseDeVue.Axe(cle: "couleur"), "la clé de l'outil est anglaise")
        XCTAssertEqual(PriseDeVue.Domaine.allCases.map(\.code), ["lumiere", "nettete", "couleur", "composition"])
        XCTAssertEqual(Set(PriseDeVue.defauts.map(\.domaine)), Set(PriseDeVue.Domaine.allCases), "chaque domaine sert")
        for axe in PriseDeVue.Axe.allCases {
            XCTAssertFalse(PriseDeVue.cles(axe: axe).isEmpty, axe.nom)
        }
        XCTAssertEqual(PriseDeVue.cles(axe: .couleur), ["color_cast", "mixed_light", "dull_colors"])
        XCTAssertEqual(PriseDeVue.cles(axe: .composition),
                       ["tilted_horizon", "converging_verticals", "loose_framing", "centered_subject", "cluttered_edges"])
        let nettete = PriseDeVue.defauts.filter { $0.domaine == .nettete }
        XCTAssertEqual(nettete.map(\.code), ["bruit", "flou", "mise_au_point"])
        XCTAssertTrue(nettete.allSatisfy { $0.axe == .lumiere })
        for defaut in PriseDeVue.defauts where defaut.domaine != .nettete {
            XCTAssertEqual(defaut.axe.code, defaut.domaine.code, "\(defaut.code) : même axe et même domaine")
        }
    }

    /// Le carnet ne compte d'après une mesure que six défauts ; les autres ne viennent que des leçons.
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
    /// à craindre côté Lua (des textes, des booléens).
    func testVocabulaireEnvoyeAuModule() throws {
        let vocabulaire = try XCTUnwrap(PriseDeVue.vocabulaire.array)
        XCTAssertEqual(vocabulaire.compactMap { $0["code"]?.string }, Self.codes)
        let ciel = try XCTUnwrap(vocabulaire.first { $0["code"]?.string == "ciel_brule" })
        XCTAssertEqual(Set(ciel.object?.keys.map { $0 } ?? []), ["code", "cle", "axe", "domaine", "libelle", "conseil", "mesure"])
        XCTAssertEqual(ciel["cle"]?.string, "blown_highlights")
        XCTAssertEqual(ciel["axe"]?.string, "lumiere")
        XCTAssertEqual(ciel["domaine"]?.string, "lumiere")
        XCTAssertEqual(ciel["mesure"]?.bool, true)
        XCTAssertEqual(vocabulaire.first { $0["code"]?.string == "bruit" }?["domaine"]?.string, "nettete")
        XCTAssertEqual(vocabulaire.first { $0["code"]?.string == "dominante" }?["mesure"]?.bool, false)
    }

    // MARK: Les deux outils qui le reprennent

    /// photo_lesson tire ses axes et l'enum de ses défauts de PriseDeVue ; sa description tient en
    /// 1 200 caractères et dit où la leçon est rangée.
    func testPhotoLessonSuitLeVocabulaire() throws {
        let lecon = try definition("photo_lesson")
        let description = try XCTUnwrap(lecon["description"]?.string)
        XCTAssertLessThanOrEqual(description.count, 1200, "photo_lesson : \(description.count) caractères")
        for attendu in ["lumière, couleur et composition", "missing", "at_capture", "carnet.json", "read_facts", "en dernier",
                        "intention_boitier", "read_composition", "pas après une proposition seule (rien d'appliqué)"] {
            XCTAssertTrue(description.contains(attendu), "photo_lesson sans « \(attendu) »")
        }
        // Une retouche qui finit par une proposition de cadre a sa leçon : seule une proposition
        // sans rien d'appliqué n'en a pas (synthèse de la 1.3, fin de retouche).
        XCTAssertTrue(description.contains("en dernier, après le résumé de sa retouche et la proposition de cadre éventuelle"))
        XCTAssertFalse(description.contains("proposition seulement montrée"), "ambigu : la proposition de cadre en est une")
        let proprietes = try XCTUnwrap(lecon["inputSchema"]?["properties"]?.object)
        XCTAssertEqual(Set(proprietes.keys), ["photo_id", "points", "read_facts"])
        XCTAssertEqual(lecon["inputSchema"]?["required"], [], "rien d'exigé : read_facts seul, ou points")
        XCTAssertEqual(proprietes["points"]?["minItems"], 3, "exactement trois points")
        XCTAssertEqual(proprietes["points"]?["maxItems"], 3)
        let point = try XCTUnwrap(proprietes["points"]?["items"])
        XCTAssertEqual(Set(point["properties"]?.object?.keys.map { $0 } ?? []), ["axis", "missing", "at_capture", "defects"])
        XCTAssertEqual(point["required"], ["axis", "at_capture"])
        XCTAssertEqual(point["properties"]?["axis"]?["enum"], ["light", "color", "composition"])
        XCTAssertEqual(point["properties"]?["defects"]?["items"]?["enum"]?.array?.compactMap(\.string), PriseDeVue.defauts.map(\.cle))
        let defects = try XCTUnwrap(point["properties"]?["defects"]?["description"]?.string)
        XCTAssertTrue(defects.contains("composition : tilted_horizon, converging_verticals"), defects)
        XCTAssertTrue(point["properties"]?["missing"]?["description"]?.string?.contains("\(ToolHandler.longueurPointLecon) caractères au plus") == true)
    }

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
