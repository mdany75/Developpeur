import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Version 2.4 : yeux fermés et piles au tri, texte alternatif, champs IPTC, position GPS,
/// photos jamais exportées, collections et mots-clés réorganisés, filtre de la Bibliothèque,
/// barre de progression de Lightroom, sauvegarde du catalogue.
final class Version24Tests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Yeux fermés

    func testEyeOpennessIsMeasuredAlongTheEyeEvenWhenTheFaceIsTilted() throws {
        // Un œil de 40 px de large et 12 px de haut, puis le même tourné de 30°.
        let oeil = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 6), CGPoint(x: 20, y: 6), CGPoint(x: 30, y: 5),
                    CGPoint(x: 40, y: 0), CGPoint(x: 30, y: -6), CGPoint(x: 20, y: -6), CGPoint(x: 10, y: -5)]
        XCTAssertEqual(try XCTUnwrap(VisionAnalysis.openness(oeil)), 0.3, accuracy: 0.001)
        let angle = Double.pi / 6
        let tourne = oeil.map { CGPoint(x: $0.x * cos(angle) - $0.y * sin(angle), y: $0.x * sin(angle) + $0.y * cos(angle)) }
        XCTAssertEqual(try XCTUnwrap(VisionAnalysis.openness(tourne)), 0.3, accuracy: 0.001)
        // Trop petit pour être lu.
        XCTAssertNil(VisionAnalysis.openness(oeil.map { CGPoint(x: $0.x / 5, y: $0.y / 5) }))
    }

    func testClosedEyesOnASubjectAreADefectButNotOnASmallFaceBehind() {
        func visage(_ largeur: Double, _ ouverture: Double?) -> VisionReport.Face {
            VisionReport.Face(box: CGRect(x: 0.1, y: 0.1, width: largeur, height: largeur), pupils: [], eyeWidth: nil, quality: 0.5,
                              eyeOpenness: ouverture)
        }
        var photo = PhotoTriee(id: 1, fichier: "DSCF1.RAF")
        photo.detail = DetailMeasurements(zones: Array(repeating: 60, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
        photo.vision = VisionReport(faces: [visage(0.3, 0.06)], aesthetics: 0.4, utility: false, salientArea: nil)
        XCTAssertEqual(photo.defauts, ["yeux fermés ou plissés (ouverture 0,06)"])
        photo.vision = VisionReport(faces: [visage(0.3, 0.25), visage(0.1, 0.05)], aesthetics: 0.4, utility: false, salientArea: nil)
        XCTAssertTrue(photo.defauts.isEmpty, "un petit visage à l'arrière ne compte pas")
        photo.vision = VisionReport(faces: [visage(0.3, 0.25), visage(0.25, 0.08), visage(0.2, nil)], aesthetics: 0.4, utility: false,
                                    salientArea: nil)
        XCTAssertEqual(photo.defauts, ["yeux fermés ou plissés : 1 visage sur 2"], "un visage aux yeux illisibles n'est pas compté")
        XCTAssertEqual(VisionReport.Face(box: .zero, pupils: [], eyeWidth: nil, quality: nil, eyeOpenness: 0.2).eyesClosed, false)
    }

    // MARK: Piles

    func testOnlyOnePhotoIsProposedPerStack() {
        func photo(_ id: Int, nettete: Double, pile: Int?, secondes: Double) -> PhotoTriee {
            var p = PhotoTriee(id: id, fichier: "DSCF\(id).RAF")
            p.detail = DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: 0.3, shadowNoise: nil, side: 1024)
            p.pile = pile
            p.date = Date(timeIntervalSince1970: secondes)
            return p
        }
        // Une pile de trois photos prises à une minute d'intervalle (pas une rafale), et deux photos seules.
        let photos = [photo(1, nettete: 40, pile: 1, secondes: 0), photo(2, nettete: 60, pile: 1, secondes: 60),
                      photo(3, nettete: 50, pile: 1, secondes: 120), photo(4, nettete: 55, pile: nil, secondes: 600),
                      photo(5, nettete: 45, pile: nil, secondes: 900)]
        let bilan = Tri.bilan(photos)
        let piles = bilan["piles"]?.array ?? []
        XCTAssertEqual(piles.count, 1)
        XCTAssertEqual(piles.first?["meilleure"]?.int, 2)
        XCTAssertEqual(piles.first?["dessus"]?.int, 1)
        XCTAssertEqual(bilan["rafales"]?.array?.count, 0)
        let retenues = (bilan["propositions"]?.array ?? []).first { $0["flag"]?.string == "pick" }?["photo_ids"]?.array?.compactMap(\.int) ?? []
        XCTAssertEqual(retenues.filter { [1, 2, 3].contains($0) }, [2], "une seule photo de la pile")
    }

    // MARK: set_metadata

    func testAltTextIptcAndGpsGoToTheModule() throws {
        let result = tools.call(name: "set_metadata", arguments: [
            "alt_text": "Deux érables au bord du lac.", "extended_description": "",
            "iptc": ["city": "Montréal", "persons_shown": "Samuel, Léa", "country_code": "CA"],
            "gps": ["latitude": 45.5, "longitude": -73.56, "altitude": 30],
        ])
        XCTAssertFalse(result.isError, result.text)
        let params = fake.lastParams
        XCTAssertEqual(fake.commands, ["metadonnees"])
        XCTAssertEqual(params["iptc"]?["altTextAccessibility"]?.string, "Deux érables au bord du lac.")
        XCTAssertEqual(params["iptc"]?["extDescrAccessibility"]?.string, "", "un texte vide efface")
        XCTAssertEqual(params["iptc"]?["personShown"]?.string, "Samuel, Léa")
        XCTAssertEqual(params["iptc"]?["isoCountryCode"]?.string, "CA")
        XCTAssertEqual(params["gps"]?["latitude"]?.double, 45.5)
        XCTAssertEqual(params["gps"]?["altitude"]?.double, 30)

        _ = tools.call(name: "set_metadata", arguments: ["photo_ids": [1, 2], "gps_from": ["photo_ids": [9], "camera_clock_offset_minutes": 60]])
        XCTAssertEqual(fake.lastParams["gps_depuis"]?["photos"]?.array?.compactMap(\.int), [9])
        XCTAssertEqual(fake.lastParams["gps_depuis"]?["decalage"]?.int, 60)
        _ = tools.call(name: "set_metadata", arguments: ["remove_gps": true])
        XCTAssertEqual(fake.lastParams["gps"]?.string, "aucune")

        XCTAssertTrue(tools.call(name: "set_metadata", arguments: ["iptc": ["ville": "Laval"]]).isError)
        XCTAssertTrue(tools.call(name: "set_metadata", arguments: ["gps": ["latitude": 45.5]]).isError)
        XCTAssertTrue(tools.call(name: "set_metadata", arguments: ["remove_gps": true, "gps": ["latitude": 1, "longitude": 2]]).isError)
        XCTAssertEqual(fake.commands.count, 3, "rien ne part pour une demande invalide")
    }

    func testANewVisionKeywordGetsItsEnglishLabelAsSynonym() {
        XCTAssertTrue(MotsClesVision.synonymesAnglais("chien").contains("dog"))
        _ = tools.call(name: "set_metadata", arguments: ["add_keywords": ["Animaux > chien", "Vacances 2025"]])
        let synonymes = fake.lastParams["synonymes"]?.object ?? [:]
        XCTAssertTrue(synonymes["Animaux > chien"]?.array?.compactMap(\.string).contains("dog") == true)
        XCTAssertNil(synonymes["Vacances 2025"])
    }

    func testEternaGoesWithTheModelsWhereLightroomRendersAdobeStandard() {
        _ = tools.call(name: "apply_settings", arguments: ["profile": "Camera ETERNA/Cinema"])
        XCTAssertEqual(fake.lastParams["profil_absent_sur"]?.array?.compactMap(\.string), ["X-T20"])
        _ = tools.call(name: "apply_settings", arguments: ["profile": "Camera PROVIA/Standard"])
        XCTAssertNil(fake.lastParams["profil_absent_sur"])
    }

    func testFindNeverExportedPicks() {
        _ = tools.call(name: "find_photos", arguments: ["flag": "pick", "exported": false])
        XCTAssertEqual(fake.lastParams["exportee"]?.bool, false)
        XCTAssertEqual(fake.lastParams["drapeau"]?.string, "retenue")
    }

    // MARK: Collections, mots-clés, filtre

    func testCollectionsAreRenamedMovedAndRefiltered() {
        _ = tools.call(name: "manage_collections", arguments: ["action": "rename", "collection": "Sélection", "new_name": "Sélection finale"])
        XCTAssertEqual(fake.lastParams["action"]?.string, "renommer")
        XCTAssertEqual(fake.lastParams["nouveau_nom"]?.string, "Sélection finale")
        _ = tools.call(name: "manage_collections", arguments: ["action": "move", "collection": 12, "collection_set": "Voyages > 2026"])
        XCTAssertEqual(fake.lastParams["collection"]?.int, 12)
        XCTAssertEqual(fake.lastParams["ensemble"]?.string, "Voyages > 2026")
        _ = tools.call(name: "manage_collections", arguments: ["action": "edit_search", "collection": "Meilleures", "search": ["rating_min": 5]])
        XCTAssertEqual(fake.lastParams["recherche"]?["note_min"]?.int, 5)
        _ = tools.call(name: "manage_collections", arguments: ["action": "edit_keyword", "keyword": "chien", "synonyms": []])
        XCTAssertEqual(fake.lastParams["synonymes"]?.array?.count, 0, "liste vide : plus de synonymes")
        XCTAssertTrue(tools.call(name: "manage_collections", arguments: ["action": "rename", "collection": "Sélection"]).isError)
        XCTAssertTrue(tools.call(name: "manage_collections", arguments: ["action": "edit_keyword", "keyword": "chien"]).isError)
    }

    func testShowPhotoSetsALibraryFilterOnAFolder() {
        let result = tools.call(name: "show_photo", arguments: ["folder": "/Volumes/Photos/Gaspesie", "filter": ["flag": "pick", "rating_min": 3]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["source_dossier"]?.string, "/Volumes/Photos/Gaspesie")
        XCTAssertEqual(fake.lastParams["filtre"]?["drapeau"]?.string, "retenue")
        XCTAssertEqual(fake.lastParams["filtre"]?["note_min"]?.int, 3)
        XCTAssertNil(fake.lastParams["photos"])
        _ = tools.call(name: "show_photo", arguments: ["filter": [:]])
        XCTAssertEqual(fake.lastParams["filtre"]?.string, "aucun")
        _ = tools.call(name: "show_photo", arguments: ["restore_filter": true])
        XCTAssertEqual(fake.lastParams["remettre_filtre"]?.bool, true)
        XCTAssertTrue(tools.call(name: "show_photo", arguments: [:]).isError, "rien à montrer")
        XCTAssertTrue(tools.call(name: "show_photo", arguments: ["filter_preset": "Retenues", "restore_filter": true]).isError)
    }

    // MARK: Sauvegarde, progression

    func testStatusCanRequestACatalogBackup() {
        _ = tools.call(name: "get_status", arguments: ["request_backup": true])
        XCTAssertEqual(fake.lastParams["sauvegarde"]?.bool, true)
        _ = tools.call(name: "get_status", arguments: [:])
        XCTAssertNil(fake.lastParams["sauvegarde"])
        XCTAssertEqual(ToolHandler.annotations("get_status")["readOnlyHint"]?.bool, false, "il peut demander une sauvegarde")
        XCTAssertEqual(ToolHandler.annotations("view_photo")["readOnlyHint"]?.bool, true)
    }

    func testLongSeriesShowsALightroomProgressBarThatTheUserCanStop() throws {
        let tri = TriTests()
        tri.fake = fake
        tri.tools = tools
        tri.preparerVignettes()
        fake.replies["progression"] = ["annulee": false]
        var result = tools.call(name: "cull_photos", arguments: ["photo_ids": .array((1...30).map { .number(Double($0)) })])
        XCTAssertFalse(result.isError, result.text)
        let barres = fake.progressions
        XCTAssertEqual(barres.first?["titre"]?.string, "tri des photos")
        XCTAssertEqual(barres.first?["total"]?.int, 30)
        XCTAssertEqual(barres.last?["fin"]?.bool, true, "la barre se ferme à la fin de l'appel")
        XCTAssertEqual(Set(barres.compactMap { $0["id"]?.string }).count, 1, "une seule barre")

        // La croix de la barre, cliquée pendant le premier lot : le lot suivant ne part pas.
        fake.calls = []
        let suite = fake.onSend
        fake.onSend = { [unowned fake] command, params in
            suite?(command, params)
            if command == "vignettes" { fake?.replies["progression"] = ["annulee": true] }
        }
        result = tools.call(name: "cull_photos", arguments: ["photo_ids": .array((1...60).map { .number(Double($0)) })])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Arrêté dans Lightroom"), result.text)
        XCTAssertEqual(fake.calls.filter { $0.command == "vignettes" }.count, 1)

        fake.onSend = suite
        // Une petite série n'ouvre pas de barre.
        let avant = fake.progressions.count
        fake.replies["progression"] = ["annulee": false]
        _ = tools.call(name: "cull_photos", arguments: ["photo_ids": [1, 2, 3]])
        XCTAssertEqual(fake.progressions.count, avant)
    }

    func testInstructionsLeaveRoomUnderTheLimit() {
        XCTAssertLessThanOrEqual(ServerInfo.instructions.utf16.count, ServerInfo.instructionsLimit - 300,
                                 "de la marge pour la prochaine consigne")
    }
}
