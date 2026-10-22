import XCTest
@testable import DeveloppeurKit

/// Version 1.3, « Pourquoi ? » côté connecteur : l'identifiant de chaque étape (`etape_id`) passe
/// tel quel du module à Claude ; une série (`match_series`) demande au module de ne pas garder
/// l'avant/après de ses étapes (`sans_avant_apres`) ; aucun outil ne force cette capture
/// (`avant_apres` vient de la recette seulement) ; la commande `etapes` se rejoue après une coupure.
final class PourquoiTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: etape_id

    func testApplySettingsPassesTheStepIdOfTheModuleThrough() throws {
        fake.replies["appliquer"] = ["mode": "appliquer directement", "resultats": [[
            "photo": ["id": 1, "fichier": "DSCF1595.RAF"], "etape": "Claude · passe 1 : balance", "etape_id": "30A5C7E1-1B2F-3",
            "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.5]], "remarques": [],
        ]]]
        let resultat = tools.call(name: "apply_settings", arguments: ["settings": ["Exposure2012": 0.5], "step_name": "passe 1 : balance",
                                                                       "reason": "Ciel sombre."])
        XCTAssertFalse(resultat.isError, resultat.text)
        let photo = try XCTUnwrap(JSONCoding.parse(resultat.text)["resultats"]?.array?.first)
        XCTAssertEqual(photo["etape_id"]?.string, "30A5C7E1-1B2F-3", "l'id de l'étape arrive à Claude et à la fenêtre")
        XCTAssertEqual(photo["changements"]?.array?.first?["libelle"]?.string, DevelopCatalogue.label(for: "Exposure2012"),
                       "les libellés s'ajoutent toujours")
    }

    /// 1.3.1 : preview_settings accepte reason, comme apply_settings (Claude l'y joignait 3 fois sur 4,
    /// et l'appel était refusé) : une description à elle, qui ne promet pas le journal ; une
    /// proposition n'écrit rien, la raison ne part pas au module (ni étape ni journal) et revient dans
    /// la réponse, à redonner à apply_settings.
    func testPreviewSettingsAcceptsTheReasonWithoutSendingIt() throws {
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "preview_settings" })
        XCTAssertEqual(definition["inputSchema"]?["properties"]?["reason"]?["description"]?.string, ToolHandler.descriptionRaisonProposition)
        XCTAssertLessThanOrEqual(ToolHandler.descriptionRaisonProposition.count, ToolHandler.longueurRaisonDecrite)
        XCTAssertFalse(ToolHandler.descriptionRaisonProposition.contains("export_journal"), "une proposition ne va pas au journal")
        fake.onSend = { [unowned fake] command, _ in
            guard command == "essayer" else { return }
            fake?.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120))),
                                        "photo": ["id": 1, "fichier": "DSCF1595.RAF"], "etape": "Claude · essai",
                                        "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.5]], "mode": "proposer d'abord"]
        }
        let resultat = tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.5], "step_name": "passe 1",
                                                                         "reason": "  Ciel sombre : l'exposition remonte.  "])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertFalse(resultat.text.contains("Paramètres inconnus"), resultat.text)
        XCTAssertEqual(fake.commands, ["essayer"])
        XCTAssertNil(fake.lastParams["raison"], "une proposition n'est pas une étape : rien au module")
        XCTAssertNil(fake.lastParams["reason"])
        let info = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(info["raison"]?.string, "Ciel sombre : l'exposition remonte.")
        XCTAssertTrue(info["raison_lecture"]?.string?.contains("apply_settings (reason)") == true, resultat.text)
        // Sans reason (ou vide), rien de plus dans la réponse.
        let sans = try JSONCoding.parse(tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.5], "reason": " "]).text)
        XCTAssertNil(sans["raison"])
        XCTAssertNil(sans["raison_lecture"])
    }

    func testUndoLastPassesTheUndoneStepIdThrough() throws {
        fake.replies["annuler"] = ["resultats": [["photo": ["id": 1, "fichier": "DSCF1595.RAF"], "annulee": true,
                                                  "etape": "Claude · passe 1", "etape_id": "30A5C7E1-1B2F-3"]]]
        let resultat = tools.call(name: "undo_last", arguments: [:])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(try JSONCoding.parse(resultat.text)["resultats"]?.array?.first?["etape_id"]?.string, "30A5C7E1-1B2F-3")
    }

    // MARK: Séries

    /// Chaque écriture d'une série porte sans_avant_apres : la photo active d'une série n'est pas
    /// capturée deux fois, et l'aperçu de mesure qui suit n'attend pas une capture.
    func testMatchSeriesAsksNoBeforeAfterForEachWrite() throws {
        var images: [Int: (UInt8, UInt8, UInt8)] = [1: (128, 128, 128), 2: (100, 102, 116)]
        var temperature = 5000.0
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu", let id = params["photo"]?.int, let c = images[id] {
                fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: c.0, green: c.1, blue: c.2))),
                                           "photo": ["fichier": .string("P\(id).RAF")], "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                                           "reglages": ["Temperature": .number(temperature), "Tint": 0]]
            }
            if command == "appliquer" {
                let passe = fake?.calls.filter { $0.command == "appliquer" }.count ?? 0
                images[2] = passe == 1 ? (118, 119, 124) : (128, 128, 128)
                temperature += params["reglages"]?["Temperature"]?.double ?? 0
            }
        }
        let resultat = tools.call(name: "match_series", arguments: ["reference_id": 1, "photo_ids": [2], "confirm": true, "step_name": "série"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2)
        for ecriture in ecritures {
            XCTAssertEqual(ecriture.params["sans_avant_apres"]?.bool, true, "pas d'avant/après pour une étape de série")
            XCTAssertNil(ecriture.params["avant_apres"])
        }
        // Les aperçus de mesure restent des aperçus ordinaires : leur image peut servir de vue.
        for apercu in fake.calls.filter({ $0.command == "apercu" }) {
            XCTAssertNil(apercu.params["sans_avant_apres"])
        }
    }

    func testMatchSeriesByExifAsksNoBeforeAfterEither() throws {
        let exif: [Int: (Double, Double, Double, Double)] = [1: (4, 1.0 / 250, 400, 0.3), 2: (4, 1.0 / 500, 400, 0)]
        fake.onSend = { [unowned fake] command, params in
            if command == "reglages", let id = params["photo"]?.int, let e = exif[id] {
                fake?.replies["reglages"] = ["photo": ["fichier": .string("P\(id).RAF")], "reglages": ["Exposure2012": .number(e.3)],
                                             "prise_de_vue": ["ouverture": .number(e.0), "vitesse": .number(e.1), "iso": .number(e.2)]]
            }
        }
        let resultat = tools.call(name: "match_series", arguments: ["reference_id": 1, "photo_ids": [2], "by": "exif", "confirm": true])
        XCTAssertFalse(resultat.isError, resultat.text)
        let ecriture = try XCTUnwrap(fake.calls.last { $0.command == "appliquer" })
        XCTAssertEqual(ecriture.params["sans_avant_apres"]?.bool, true)
    }

    // MARK: Aucun outil ne force la capture

    /// avant_apres (capture forcée, même hors de la photo active) vient de la recette seulement ;
    /// sans_avant_apres, de match_series seulement : ni l'un ni l'autre n'est un paramètre d'outil.
    func testNoToolOffersToForceOrSkipTheBeforeAfter() throws {
        for outil in tools.definitions {
            let proprietes = outil["inputSchema"]?["properties"]?.object ?? [:]
            XCTAssertNil(proprietes["avant_apres"], outil["name"]?.string ?? "?")
            XCTAssertNil(proprietes["sans_avant_apres"], outil["name"]?.string ?? "?")
        }
        let refus = tools.call(name: "apply_settings", arguments: ["settings": ["Exposure2012": 0.5], "step_name": "x", "avant_apres": true])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("Paramètres inconnus"), refus.text)
        XCTAssertFalse(fake.commands.contains("appliquer"), "rien n'est envoyé au module")
    }

    /// La commande etapes ne fait que lire : rejouée après une coupure de la liaison.
    func testTheStepsCommandIsReplayedAfterACut() {
        XCTAssertTrue(LightroomBridge.lectures.contains("etapes"))
    }
}
