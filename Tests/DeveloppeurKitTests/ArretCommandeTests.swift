import XCTest
@testable import DeveloppeurKit

/// Arrêt d'une commande longue par la croix de sa barre « Claude : <nom> » dans Lightroom : le
/// module répond `code: "arret"` ; le serveur rend son message tel quel à Claude, ne la reprend
/// jamais, n'envoie plus rien d'autre dans le même appel, et la file des outils ne la refait pas.
final class ArretCommandeTests: XCTestCase {
    private let message = "Arrêtée par l'utilisateur (croix de la barre « Claude » de Lightroom) : rien d'autre n'a été fait."

    func testLeCodeArretDuModuleDevientCommandeArreteeSansReprise() throws {
        let plugin = try FakePlugin()
        defer { plugin.stop() }
        plugin.handler = { [message] request in
            if request["command"]?.string == "ping" {
                return [JSONCoding.line(["id": request["id"] ?? .null, "result": ["pong": true]])]
            }
            return [JSONCoding.line(["id": request["id"] ?? .null, "error": .string(message), "code": "arret"])]
        }
        let bridge = LightroomBridge(requestPort: plugin.requestPort, replyPort: plugin.replyPort)
        bridge.delaiReprise = 0.05
        XCTAssertThrowsError(try bridge.send("apercu", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? CommandeArretee, CommandeArretee(message: message))
            XCTAssertEqual(error.localizedDescription, message, "le message du module, tel quel")
        }
        XCTAssertEqual(plugin.received, ["ping", "apercu"], "une lecture arrêtée n'est pas reprise")
    }

    func testApresUnArretRienDAutreNePartDansLeMemeAppel() throws {
        let fake = FakeLightroom()
        fake.errors["apercu"] = CommandeArretee(message: message)
        let liaison = LiaisonArretable(fake)
        var arrets = 0
        liaison.surArret = { arrets += 1 }
        XCTAssertThrowsError(try liaison.send("apercu", [:], timeout: 5))
        XCTAssertThrowsError(try liaison.send("vignettes", [:], timeout: 5)) { error in
            XCTAssertEqual(error.localizedDescription, LiaisonArretable.suiteArretee)
        }
        XCTAssertEqual(fake.commands, ["apercu"], "la commande suivante n'est pas partie")
        XCTAssertNoThrow(try liaison.send("progression", ["fin": true], timeout: 5), "la barre d'une série se ferme quand même")
        XCTAssertEqual(arrets, 1)
        XCTAssertEqual(liaison.arretDeLAppel?.message, message)
        liaison.reprendre()
        XCTAssertNoThrow(try liaison.send("vignettes", [:], timeout: 5), "un nouvel appel repart")
        XCTAssertNil(liaison.arretDeLAppel)
    }

    func testLOutilRendLeMessageDArretTelQuelEtLaCroixTardiveEstDite() throws {
        let fake = FakeLightroom()
        let outils = ToolHandler(lightroom: fake)
        fake.errors["annuler"] = CommandeArretee(message: message)
        let arrete = outils.call(name: "undo_last", arguments: [:])
        XCTAssertTrue(arrete.isError)
        XCTAssertEqual(arrete.text, message, "rendu tel quel, sans rien d'ajouté")

        fake.errors["annuler"] = nil
        let tardif = "Arrêt demandé par la croix de la barre « Claude » quand la commande ne pouvait plus s'arrêter : elle a été faite en entier."
        fake.replies["annuler"] = ["annulee": true, "arret_demande": .string(tardif)]
        let fait = outils.call(name: "undo_last", arguments: [:])
        XCTAssertFalse(fait.isError)
        XCTAssertTrue(fait.text.contains("faite en entier"), fait.text)

        fake.replies["annuler"] = ["annulee": true]
        let suivant = outils.call(name: "undo_last", arguments: [:])
        XCTAssertFalse(suivant.text.contains("Arrêt"), "l'arrêt ne vaut que pour son appel")
        XCTAssertEqual(fake.commands.filter { $0 == "annuler" }.count, 3)
    }

    func testUneSerieSArreteAuPremierArretDUneCommande() throws {
        let fake = FakeLightroom()
        let outils = ToolHandler(lightroom: fake)
        let contexte = ContexteAppel()
        outils.contexte = contexte
        outils.arretable.reprendre()
        outils.arretable.surArret = { contexte.arreterDansLightroom() }
        fake.errors["apercu"] = CommandeArretee(message: message)
        XCTAssertThrowsError(try outils.lightroom.send("apercu", [:], timeout: 5))
        XCTAssertThrowsError(try contexte.verifier()) { error in
            XCTAssertTrue(error is ArretDansLightroom, "la série ne passe pas à la photo suivante")
        }
    }

    /// Arrêtée après la limite de 50 s : le même appel répété reçoit l'arrêt gardé, sans relancer
    /// la commande dans Lightroom.
    func testLaFileNeRejouePasUneCommandeArretee() throws {
        let porte = DispatchSemaphore(value: 0)
        let fake = FakeLightroom()
        fake.errors["annuler"] = CommandeArretee(message: message)
        fake.onSend = { command, _ in
            if command == "annuler" { _ = porte.wait(timeout: .now() + 5) }
        }
        let server = TestSupport.makeServer(fake)
        server.toolBudget = 0.3
        let ligne = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"undo_last","arguments":{}}}"#
        let premier = try JSONCoding.parse(XCTUnwrap(server.handle(line: ligne)))
        XCTAssertTrue(JSONCoding.line(premier).contains("n'est pas fini"))
        porte.signal()
        server.toolBudget = 5
        let encore = try JSONCoding.parse(XCTUnwrap(server.handle(line: ligne.replacingOccurrences(of: #""id":1"#, with: #""id":2"#))))
        let texte = (encore["result"]?["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
        XCTAssertEqual(encore["result"]?["isError"]?.bool, true)
        XCTAssertTrue(texte.contains(message), texte)
        XCTAssertEqual(fake.commands.filter { $0 == "annuler" }.count, 1, "jamais relancée")
    }

    /// Revue : l'arrêt d'un appel ne bloquait pas que lui. Une ressource lue ensuite
    /// (developpeur://photo/active/apercu, le journal) atteint le module, et ce qui envoie hors
    /// d'un appel (la recette) aussi : l'arrêt se remet à zéro à la fin de l'appel.
    func testApresUnAppelArreteLesRessourcesEtLaRecetteAtteignentLeModule() throws {
        let fake = FakeLightroom()
        let outils = ToolHandler(lightroom: fake)
        fake.errors["apercu"] = CommandeArretee(message: message)
        XCTAssertTrue(outils.call(name: "view_photo", arguments: [:]).isError)
        fake.errors["apercu"] = nil
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120)))]
        fake.replies["journal"] = ["photos": []]
        let avant = fake.commands.count
        let apercu = outils.lireRessource("developpeur://photo/active/apercu")
        XCTAssertFalse(apercu.isError, apercu.text)
        XCTAssertFalse(outils.lireRessource("developpeur://photo/7/journal").isError)
        XCTAssertEqual(Array(fake.commands.dropFirst(avant)), ["apercu", "journal"], "les deux lectures sont parties")
        XCTAssertNil(outils.arretable.arretDeLAppel, "l'arrêt ne survit pas à son appel")
        XCTAssertNoThrow(try outils.lightroom.send("reglages", [:], timeout: 5), "la recette envoie comme avant")
    }

    /// Revue : compare_variants arrêté pendant une variante dit les instantanés des variantes déjà
    /// rangées, que Claude ne connaîtrait pas sinon.
    func testCompareVariantsArreteDitLesInstantanesDejaRanges() throws {
        let fake = FakeLightroom()
        let outils = ToolHandler(lightroom: fake)
        let arret = message
        fake.onSend = { [unowned fake] command, params in
            if command == "essayer" || command == "apercu" {
                fake.replies[command] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120))),
                                         "instantane": params["instantane"]?.string.map { .string("Claude · variante " + $0) } ?? .null]
            }
            fake.errors["essayer"] = params["instantane"]?.string == "chaude" ? CommandeArretee(message: arret) : nil
        }
        let result = outils.call(name: "compare_variants", arguments: ["photo_id": 5, "variants": [
            ["name": "naturelle", "settings": ["Exposure2012": 0.2]],
            ["name": "chaude", "settings": ["Temperature": 6500]],
            ["name": "froide", "settings": ["Temperature": 4500]],
        ]])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.hasPrefix(message), result.text)
        XCTAssertTrue(result.text.contains("« Claude · variante naturelle »"), result.text)
        XCTAssertTrue(result.text.contains("choose_variant"), result.text)
        XCTAssertEqual(fake.commands, ["apercu", "essayer", "essayer"], "la troisième variante n'est pas partie")
        XCTAssertFalse(result.text.contains("Arrêté par l'utilisateur dans Lightroom pendant cet appel"), "le message n'est pas doublé")
    }
}
