import XCTest
@testable import DeveloppeurKit

/// File des appels d'outils (FileOutils, MCPServer) : réponse d'attente sous les 60 s de Claude
/// Desktop, résultat gardé pour le même appel, une commande à la fois vers Lightroom, progression
/// pour le client qui donne un jeton (Claude Code).
final class FileOutilsTests: XCTestCase {
    private func call(_ server: MCPServer, _ line: String) throws -> JSONValue {
        try JSONCoding.parse(XCTUnwrap(server.handle(line: line)))
    }

    private func toolLine(id: Int, _ name: String, _ arguments: String = "{}", meta: String? = nil) -> String {
        let extra = meta.map { #","_meta":\#($0)"# } ?? ""
        return #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)\#(extra)}}"#
    }

    private func texts(_ response: JSONValue) -> String {
        (response["result"]?["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n")
    }

    private func hasImage(_ response: JSONValue) -> Bool {
        (response["result"]?["content"]?.array ?? []).contains { $0["type"]?.string == "image" }
    }

    /// Aperçu de masques IA dont la commande `essayer` attend `porte` (5 s au plus) ; chaque essai
    /// rend un nouveau fichier, comme le module.
    private func slowPreview(_ porte: DispatchSemaphore) -> FakeLightroom {
        let fake = FakeLightroom()
        let image = TestSupport.jpeg(red: 90, green: 120, blue: 160)
        fake.onSend = { [unowned fake] command, _ in
            guard command == "essayer" else { return }
            _ = porte.wait(timeout: .now() + 5)
            fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(image))]
        }
        return fake
    }

    private let maskPreview = #"{"masks":[{"kind":"sky","adjustments":{"Exposure":-0.3}},{"kind":"landscape","part":"water","adjustments":{"Highlights":-20}}],"preview":true,"size":1600,"step_name":"retouches locales"}"#

    /// Constaté le 16 octobre 2026 : un aperçu de quatre masques IA a dépassé les 60 s de Claude
    /// Desktop, qui a abandonné l'appel (« Request timed out ») puis relancé le serveur ; le module,
    /// lui, l'a mené à terme. Le serveur répond avant sa limite, garde le résultat pour le même
    /// appel, et ne lance rien d'autre vers Lightroom en attendant.
    func testLongPreviewAnswersBeforeLimitAndKeepsResultForTheSameCall() throws {
        let porte = DispatchSemaphore(value: 0)
        let fake = slowPreview(porte)
        let server = TestSupport.makeServer(fake)
        server.toolBudget = 0.3

        let debut = Date()
        let first = try call(server, toolLine(id: 1, "add_mask", maskPreview))
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2, "réponse d'attente à la limite, pas à la fin du rendu")
        XCTAssertEqual(first["id"]?.int, 1)
        XCTAssertEqual(first["result"]?["isError"]?.bool, false)
        XCTAssertFalse(hasImage(first))
        XCTAssertTrue(texts(first).contains("« add_mask » n'est pas fini"), texts(first))
        XCTAssertTrue(texts(first).contains("mêmes arguments"))

        // Une autre commande n'est pas lancée tant que Lightroom travaille : elle ne part jamais.
        let other = try call(server, toolLine(id: 2, "get_status"))
        XCTAssertEqual(other["result"]?["isError"]?.bool, true)
        XCTAssertTrue(texts(other).contains("« get_status » n'a pas été lancé"), texts(other))
        XCTAssertTrue(texts(other).contains("« add_mask »"))

        // Le rendu finit : le même appel reçoit son résultat, sans nouvel essai.
        porte.signal()
        let again = try call(server, toolLine(id: 3, "add_mask", maskPreview))
        XCTAssertEqual(again["id"]?.int, 3)
        XCTAssertTrue(hasImage(again))
        XCTAssertTrue(texts(again).contains("rien_n_est_applique"))
        XCTAssertTrue(texts(again).contains("Résultat de l'appel précédent de add_mask"), texts(again))
        XCTAssertEqual(fake.commands.filter { $0 == "essayer" }.count, 1)
        XCTAssertFalse(fake.commands.contains("etat"), "l'appel abandonné avant de commencer ne part pas")

        // Le résultat ne sert qu'une fois : rappelé de nouveau, l'aperçu est refait.
        porte.signal()
        let fresh = try call(server, toolLine(id: 4, "add_mask", maskPreview))
        XCTAssertTrue(hasImage(fresh))
        XCTAssertFalse(texts(fresh).contains("Résultat de l'appel précédent"))
        XCTAssertEqual(fake.commands.filter { $0 == "essayer" }.count, 2)
    }

    /// Une autre commande lancée entre-temps peut changer la photo : le résultat gardé ne vaut plus.
    func testKeptResultIsDroppedWhenAnotherCommandRuns() throws {
        let porte = DispatchSemaphore(value: 0)
        let fake = slowPreview(porte)
        let server = TestSupport.makeServer(fake)
        server.toolBudget = 0.3

        _ = try call(server, toolLine(id: 1, "add_mask", maskPreview))
        porte.signal()
        server.toolBudget = 5
        let status = try call(server, toolLine(id: 2, "get_status"))
        XCTAssertEqual(status["result"]?["isError"]?.bool, false, "lancé une fois le rendu fini")
        porte.signal()
        let again = try call(server, toolLine(id: 3, "add_mask", maskPreview))
        XCTAssertFalse(texts(again).contains("Résultat de l'appel précédent"))
        XCTAssertEqual(fake.commands, ["essayer", "etat", "essayer"])
    }

    /// Claude Code donne un jeton de progression et relance sa garde d'inactivité à chaque
    /// notification : le serveur en envoie tant que l'outil travaille, aucune après la réponse,
    /// et attend la fin sans réponse d'attente.
    func testProgressTokenGetsNotificationsAndNoLimit() throws {
        let fake = FakeLightroom()
        fake.replies["etat"] = ["module": "Développeur"]
        fake.onSend = { _, _ in Thread.sleep(forTimeInterval: 0.5) }
        let server = TestSupport.makeServer(fake)
        server.toolBudget = 0.1
        server.progressInterval = 0.1
        let verrou = NSLock()
        var notifications: [JSONValue] = []
        server.notifier = { verrou.lock(); notifications.append($0); verrou.unlock() }

        let response = try call(server, toolLine(id: 9, "get_status", meta: #"{"progressToken":"jeton-9"}"#))
        XCTAssertEqual(response["result"]?["isError"]?.bool, false)
        XCTAssertTrue(texts(response).contains("Développeur"), "pas de réponse d'attente avec un jeton")

        verrou.lock()
        let recues = notifications
        verrou.unlock()
        XCTAssertGreaterThanOrEqual(recues.count, 2)
        XCTAssertEqual(Set(recues.compactMap { $0["method"]?.string }), ["notifications/progress"])
        XCTAssertEqual(Set(recues.compactMap { $0["params"]?["progressToken"]?.string }), ["jeton-9"])
        let progression = recues.compactMap { $0["params"]?["progress"]?.double }
        XCTAssertEqual(progression, progression.sorted())
        XCTAssertEqual(Set(progression).count, progression.count, "progression strictement croissante")

        Thread.sleep(forTimeInterval: 0.3)
        verrou.lock()
        XCTAssertEqual(notifications.count, recues.count, "aucune notification après la réponse")
        verrou.unlock()

        // Sans jeton (Claude Desktop) : pas de notification.
        verrou.lock(); notifications = []; verrou.unlock()
        server.toolBudget = 5
        _ = try call(server, toolLine(id: 10, "get_status"))
        verrou.lock()
        XCTAssertTrue(notifications.isEmpty)
        verrou.unlock()
    }

    /// Le serveur lit sans arrêt : ping répond pendant un appel, et les commandes vont au module
    /// une à la fois, dans l'ordre d'arrivée (le module traite chacune dans sa propre tâche).
    func testCommandsReachLightroomOneAtATimeInArrivalOrder() {
        let fake = FakeLightroom()
        let verrou = NSLock()
        var actives = 0, maximum = 0
        var ordre: [Int] = []
        fake.onSend = { _, _ in
            verrou.lock(); actives += 1; maximum = max(maximum, actives); verrou.unlock()
            Thread.sleep(forTimeInterval: 0.15)
            verrou.lock(); actives -= 1; verrou.unlock()
        }
        let server = TestSupport.makeServer(fake)
        let fini = expectation(description: "réponses")
        fini.expectedFulfillmentCount = 4
        let respond: (String) -> Void = { line in
            let id = (try? JSONCoding.parse(line))?["id"]?.int ?? -1
            verrou.lock(); ordre.append(id); verrou.unlock()
            fini.fulfill()
        }
        server.receive(line: toolLine(id: 1, "get_status"), respond: respond)
        server.receive(line: toolLine(id: 2, "list_selection"), respond: respond)
        server.receive(line: toolLine(id: 3, "list_presets"), respond: respond)
        server.receive(line: #"{"jsonrpc":"2.0","id":4,"method":"ping"}"#, respond: respond)
        wait(for: [fini], timeout: 5)

        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(fake.commands, ["etat", "selection", "presets"])
        verrou.lock()
        XCTAssertEqual(ordre, [4, 1, 2, 3])
        verrou.unlock()
    }

    func testDurationText() {
        XCTAssertEqual(FileOutils.duree(50.2), "50 s")
        XCTAssertEqual(FileOutils.duree(72), "1 min 12 s")
        XCTAssertEqual(FileOutils.duree(125), "2 min 05 s")
    }
}
