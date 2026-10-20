import XCTest
@testable import DeveloppeurKit

/// Outils de la Bibliothèque : ce que le serveur envoie au module, et ce qu'il refuse avant.
final class BibliothequeTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary())
    }

    // MARK: set_metadata

    func testSetMetadataTranslatesValuesForThePlugin() throws {
        fake.replies["metadonnees"] = ["resultats": [["photo": ["id": 12], "changements": [["cle": "note", "avant": 0, "apres": 4]]]]]
        let result = tools.call(name: "set_metadata", arguments: [
            "rating": 4, "flag": "pick", "color_label": "red", "title": "Lac au matin", "caption": "",
            "add_keywords": ["Lieux > Canada > Montréal", "Paysage"], "remove_keywords": "Hiver",
            "photo_ids": [12, 13], "reason": "Meilleures de la série.", "confirm": true,
        ])
        XCTAssertFalse(result.isError, result.text)
        let call = try XCTUnwrap(fake.calls.last)
        XCTAssertEqual(call.command, "metadonnees")
        XCTAssertEqual(call.params["note"], 4)
        XCTAssertEqual(call.params["drapeau"]?.string, "retenue")
        XCTAssertEqual(call.params["libelle"]?.string, "rouge")
        XCTAssertEqual(call.params["titre"]?.string, "Lac au matin")
        XCTAssertEqual(call.params["legende"]?.string, "", "un texte vide efface la légende")
        XCTAssertNil(call.params["droits"])
        XCTAssertEqual(call.params["ajouter"], ["Lieux > Canada > Montréal", "Paysage"])
        XCTAssertEqual(call.params["retirer"], ["Hiver"])
        XCTAssertEqual(call.params["photos"], [12, 13])
        XCTAssertEqual(call.params["etape"]?.string, "classement")
        XCTAssertEqual(call.params["raison"]?.string, "Meilleures de la série.")
        XCTAssertEqual(call.params["confirme"]?.bool, true)
        let reply = try JSONCoding.parse(result.text)
        XCTAssertEqual(reply["resultats"]?.array?.first?["changements"]?.array?.first?["libelle"]?.string, "Note")
    }

    /// 1.1 : Claude ne propose jamais 5 étoiles (propose_ratings), mais l'utilisateur peut les lui
    /// demander : set_metadata les pose toujours.
    func testSetMetadataStillSetsFiveStarsWhenAsked() {
        let result = tools.call(name: "set_metadata", arguments: ["rating": 5, "photo_ids": [12], "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["note"], 5)
        let refus = tools.call(name: "propose_ratings", arguments: ["ratings": [["photo_id": 12, "rating": 5, "reason": "x",
                                                                                "criteria": ["impact": "a", "qualities": "b", "technical_floor": "c"]]]])
        XCTAssertTrue(refus.isError)
        XCTAssertEqual(fake.commands, ["metadonnees"])
    }

    func testSetMetadataRefusesInvalidOrEmptyRequests() {
        for (arguments, expected) in [
            ([:], "Rien à changer"),
            (["rating": 7], "« rating » doit être entre 0 et 5"),
            (["flag": "keep"], "« flag » invalide"),
            (["color_label": "orange"], "« color_label » invalide"),
            (["add_keywords": ["Lac", ""]], "mot-clé vide"),
        ] as [([String: JSONValue], String)] {
            let result = tools.call(name: "set_metadata", arguments: arguments)
            XCTAssertTrue(result.isError, "\(arguments)")
            XCTAssertTrue(result.text.contains(expected), result.text)
        }
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est envoyé au module")
    }

    // MARK: find_photos

    func testFindPhotosTranslatesCriteria() throws {
        let result = tools.call(name: "find_photos", arguments: [
            "text": "brume", "keyword": "Lac", "rating_min": 3, "flag": "pick", "color_label": "green", "camera": "X-H2S",
            "iso_max": 800, "file_format": "raw", "last_days": 30, "date_from": "2026-07-01", "folder": "/Volumes/Photos/2026",
            "include_subfolders": false, "collection": "Sélection", "edited_by_claude": false, "virtual_copies": "exclude",
            "sort": "rating", "include_keywords": true, "limit": 900, "offset": 50,
        ])
        XCTAssertFalse(result.isError, result.text)
        let params = fake.lastParams
        XCTAssertEqual(fake.commands, ["chercher"])
        XCTAssertEqual(params["texte"]?.string, "brume")
        XCTAssertEqual(params["mots_cles"]?.string, "Lac")
        XCTAssertEqual(params["note_min"], 3)
        XCTAssertEqual(params["drapeau"]?.string, "retenue")
        XCTAssertEqual(params["libelle"]?.string, "vert")
        XCTAssertEqual(params["appareil"]?.string, "X-H2S")
        XCTAssertEqual(params["iso_max"], 800)
        XCTAssertEqual(params["format"]?.string, "RAW")
        XCTAssertEqual(params["depuis_jours"], 30)
        XCTAssertEqual(params["date_debut"]?.string, "2026-07-01")
        XCTAssertEqual(params["dossier"]?.string, "/Volumes/Photos/2026")
        XCTAssertEqual(params["sous_dossiers"]?.bool, false)
        XCTAssertEqual(params["collection"]?.string, "Sélection")
        XCTAssertEqual(params["retouchee_par_claude"]?.bool, false)
        XCTAssertEqual(params["copies_virtuelles"]?.string, "exclure")
        XCTAssertEqual(params["tri"]?.string, "note")
        XCTAssertEqual(params["mots_cles_details"]?.bool, true)
        XCTAssertEqual(params["limite"], 500, "plafonné")
        XCTAssertEqual(params["decalage"], 50)
    }

    func testFindPhotosKeepsACollectionIdAsANumberAndNeedsACriterion() {
        _ = tools.call(name: "find_photos", arguments: ["collection": 42])
        XCTAssertEqual(fake.lastParams["collection"], 42)
        let empty = tools.call(name: "find_photos", arguments: ["limit": 10])
        XCTAssertTrue(empty.isError)
        XCTAssertTrue(empty.text.contains("Aucun critère"), empty.text)
        let wrong = tools.call(name: "find_photos", arguments: ["file_format": "GIF"])
        XCTAssertTrue(wrong.text.contains("« file_format » invalide"), wrong.text)
    }

    // MARK: manage_collections

    func testManageCollectionsCreatesASmartCollectionFromASearch() throws {
        let result = tools.call(name: "manage_collections", arguments: [
            "action": "create", "name": "Cinq étoiles", "search": ["rating_min": 5, "color_label": "red"], "confirm": true,
        ])
        XCTAssertFalse(result.isError, result.text)
        let params = fake.lastParams
        XCTAssertEqual(params["action"]?.string, "creer")
        XCTAssertEqual(params["nom"]?.string, "Cinq étoiles")
        XCTAssertEqual(params["recherche"]?["note_min"], 5)
        XCTAssertEqual(params["recherche"]?["libelle"]?.string, "rouge")
        XCTAssertNil(params["ensemble"], "l'ensemble « Claude » est le défaut du module")
        XCTAssertNil(params["photos"], "créée sans photos : pas la photo active par défaut")
        XCTAssertNil(params["selection"])
    }

    func testManageCollectionsAddsTheSelectionToACollection() {
        _ = tools.call(name: "manage_collections", arguments: ["action": "add", "collection": "Claude > Choix", "selection": true, "step_name": "tri"])
        XCTAssertEqual(fake.lastParams["action"]?.string, "ajouter")
        XCTAssertEqual(fake.lastParams["collection"]?.string, "Claude > Choix")
        XCTAssertEqual(fake.lastParams["selection"]?.bool, true)
        XCTAssertEqual(fake.lastParams["etape"]?.string, "tri")
        _ = tools.call(name: "manage_collections", arguments: ["action": "list"])
        XCTAssertEqual(fake.lastParams, ["action": "lister"])
        for (arguments, expected) in [
            (["action": "delete"], "« action »"),
            (["action": "create"], "« name »"),
            (["action": "remove"], "« collection »"),
        ] as [([String: JSONValue], String)] {
            let result = tools.call(name: "manage_collections", arguments: arguments)
            XCTAssertTrue(result.isError && result.text.contains(expected), result.text)
        }
    }

    // MARK: create_virtual_copy, show_photo, list_keywords

    func testCreateVirtualCopyAndShowPhoto() {
        _ = tools.call(name: "create_virtual_copy", arguments: ["photo_ids": [7], "name": "Noir et blanc"])
        XCTAssertEqual(fake.lastParams, ["photos": [7], "nom": "Noir et blanc", "afficher": false, "confirme": false])
        _ = tools.call(name: "show_photo", arguments: ["photo_ids": [7, 8], "module": "develop", "view": "compare"])
        XCTAssertEqual(fake.lastParams, ["photos": [7, 8], "module": "developpement", "vue": "comparer"])
        _ = tools.call(name: "show_photo", arguments: ["photo_ids": [7], "view": "before_after"])
        XCTAssertEqual(fake.lastParams, ["photos": [7], "vue": "avant_apres"])
        _ = tools.call(name: "show_photo", arguments: ["photo_ids": [7, 8, 9], "view": "survey"])
        XCTAssertEqual(fake.lastParams["vue"], "ensemble")
        let wrongView = tools.call(name: "show_photo", arguments: ["photo_ids": [7], "view": "before"])
        XCTAssertTrue(wrongView.isError && wrongView.text.contains("before_after"), wrongView.text)
        let missing = tools.call(name: "show_photo", arguments: [:])
        XCTAssertTrue(missing.isError && missing.text.contains("photo_ids"), missing.text)
        _ = tools.call(name: "list_keywords", arguments: ["query": "canada"])
        XCTAssertEqual(fake.lastParams, ["filtre": "canada", "limite": 200])
    }

    // MARK: Définitions et journal

    func testLibraryToolsAreListedWithTheirSearchCriteria() throws {
        let names = tools.definitions.compactMap { $0["name"]?.string }
        for name in ["find_photos", "set_metadata", "list_keywords", "manage_collections", "create_virtual_copy", "show_photo"] {
            XCTAssertTrue(names.contains(name), name)
        }
        let collections = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "manage_collections" })
        let search = collections["inputSchema"]?["properties"]?["search"]?["properties"]
        XCTAssertNotNil(search?["rating_min"])
        XCTAssertNotNil(search?["edited_by_claude"])
        XCTAssertNil(search?["date_from"], "Lightroom ne cherche pas lui-même les dates exactes")
    }

    func testJournalLabelsLibraryChanges() {
        let markdown = ToolHandler.journalMarkdown([
            ["photo": ["fichier": "DSC_0412.NEF", "id": 1], "entrees": [
                ["date": "2026-10-17 10:00", "etape": "Claude · tri", "changements": [
                    ["cle": "drapeau", "avant": "aucun", "apres": "retenue"],
                    ["cle": "mots_cles", "avant": "1 mot-clé", "apres": "+ Lieux > Canada"],
                ]],
            ]],
        ], date: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(markdown.contains("- Drapeau : aucun → retenue"), markdown)
        XCTAssertTrue(markdown.contains("- Mots-clés : 1 mot-clé → + Lieux > Canada"), markdown)
    }
}
