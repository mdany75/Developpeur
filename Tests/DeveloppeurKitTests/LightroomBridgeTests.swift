import Darwin
import XCTest
@testable import DeveloppeurKit

/// Faux module Lightroom sur de vraies prises TCP locales, comme LrSocket : une prise reçoit
/// les commandes, l'autre renvoie les réponses ; après une coupure, il se remet à écouter.
final class FakePlugin {
    let requestPort: UInt16
    let replyPort: UInt16
    /// Lignes à renvoyer pour une commande reçue.
    var handler: (JSONValue) -> [String] = { request in
        [JSONCoding.line(["id": request["id"] ?? .null, "result": ["pong": true]])]
    }

    private let requestListener: Int32
    private let replyListener: Int32
    private let lock = NSLock()
    private var requestConnection: Int32 = -1
    private var replyConnection: Int32 = -1
    private var stopped = false
    private var receivedCommands: [String] = []
    private var receivedTokens: [String?] = []
    private var receivedLines: [String] = []
    private var expectedToken: String?

    /// Liaison fermée (1.2) : le jeton que le module attend (nil : module d'avant la 1.2, qui
    /// accepte tout). Une ligne qui ne le porte pas reçoit le refus du module (`code: "jeton"`),
    /// sans passer par `handler`.
    var jetonAttendu: String? {
        get { lock.lock(); defer { lock.unlock() }; return expectedToken }
        set { lock.lock(); expectedToken = newValue; lock.unlock() }
    }
    /// Appelé à chaque refus, avant la réponse (la liaison réécrit son fichier, par exemple).
    var surRefus: (() -> Void)?

    /// Jeton de chaque ligne reçue (nil : sans clé `jeton`).
    var jetonsRecus: [String?] {
        lock.lock(); defer { lock.unlock() }
        return receivedTokens
    }

    /// Lignes reçues, telles quelles.
    var lignesRecues: [String] {
        lock.lock(); defer { lock.unlock() }
        return receivedLines
    }

    /// Ports libres choisis par le système, ou ports imposés (pour reprendre ceux d'un faux module arrêté).
    init(requestPort: UInt16 = 0, replyPort: UInt16 = 0) throws {
        (requestListener, self.requestPort) = try Self.listen(port: requestPort)
        (replyListener, self.replyPort) = try Self.listen(port: replyPort)
        Thread { [weak self] in self?.run() }.start()
    }

    var received: [String] {
        lock.lock(); defer { lock.unlock() }
        return receivedCommands
    }

    /// Ferme les connexions en cours (Lightroom relancé, liaison redémarrée).
    func dropConnections() {
        lock.lock(); defer { lock.unlock() }
        if requestConnection >= 0 { shutdown(requestConnection, SHUT_RDWR) }
        if replyConnection >= 0 { shutdown(replyConnection, SHUT_RDWR) }
    }

    func stop() {
        lock.lock()
        if stopped { lock.unlock(); return }
        stopped = true
        lock.unlock()
        dropConnections()
        shutdown(requestListener, SHUT_RDWR)
        shutdown(replyListener, SHUT_RDWR)
        close(requestListener)
        close(replyListener)
    }

    private static func listen(port: UInt16) throws -> (Int32, UInt16) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic -> Bool in
                bind(fd, generic, length) == 0 && Darwin.listen(fd, 4) == 0 && getsockname(fd, generic, &length) == 0
            }
        }
        guard bound else { throw LightroomError.unreachable("écoute impossible") }
        return (fd, UInt16(bigEndian: address.sin_port))
    }

    private func run() {
        while true {
            lock.lock(); let isStopped = stopped; lock.unlock()
            if isStopped { return }
            // Le client se connecte d'abord aux réponses, puis aux commandes.
            let reply = accept(replyListener, nil, nil)
            let request = accept(requestListener, nil, nil)
            guard reply >= 0, request >= 0 else { return }
            var yes: Int32 = 1
            setsockopt(reply, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            lock.lock(); requestConnection = request; replyConnection = reply; lock.unlock()
            serve(request: request, reply: reply)
            lock.lock(); requestConnection = -1; replyConnection = -1; lock.unlock()
            close(request)
            close(reply)
        }
    }

    private func serve(request: Int32, reply: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let message = try? JSONCoding.parse(line) else { continue }
                lock.lock()
                receivedCommands.append(message["command"]?.string ?? "?")
                receivedTokens.append(message.object?["jeton"].map { $0.string ?? JSONCoding.line($0) })
                receivedLines.append(line)
                let attendu = expectedToken
                lock.unlock()
                let answers: [String]
                if let attendu = attendu, message["jeton"]?.string != attendu {
                    surRefus?()
                    answers = [JSONCoding.line(["id": message["id"] ?? .null, "code": "jeton",
                                                "error": "Liaison fermée : le jeton de cette commande n'est pas celui de la liaison ; rien n'a été fait."])]
                } else {
                    answers = handler(message)
                }
                for answer in answers {
                    let bytes = Array((answer + "\n").utf8)
                    _ = bytes.withUnsafeBufferPointer { send(reply, $0.baseAddress, $0.count, 0) }
                }
            }
            let count = recv(request, &chunk, chunk.count, 0)
            if count <= 0 { return }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}

final class LightroomBridgeTests: XCTestCase {
    var plugin: FakePlugin!

    override func setUpWithError() throws {
        plugin = try FakePlugin()
    }

    override func tearDown() {
        plugin.stop()
    }

    private func makeBridge() -> LightroomBridge {
        LightroomBridge(requestPort: plugin.requestPort, replyPort: plugin.replyPort)
    }

    private func answer(_ request: JSONValue, _ result: JSONValue) -> String {
        JSONCoding.line(["id": request["id"] ?? .null, "result": result])
    }

    /// La photo active a changé dans Lightroom : le module le dit avec sa réponse suivante.
    func testEventsCarriedByARepliedCommandReachTheServer() throws {
        plugin.handler = { request in
            if request["command"]?.string == "ping" { return [self.answer(request, ["pong": true])] }
            return [JSONCoding.line(["id": request["id"] ?? .null, "result": ["ok": true], "evenements": ["photo_active": true]])]
        }
        var recus: [JSONValue] = []
        let verrou = NSLock()
        LightroomBridge.surEvenements = { evenement in verrou.lock(); recus.append(evenement); verrou.unlock() }
        defer { LightroomBridge.surEvenements = nil }
        XCTAssertEqual(try makeBridge().send("etat", [:], timeout: 5)["ok"]?.bool, true)
        verrou.lock(); defer { verrou.unlock() }
        XCTAssertEqual(recus.last?["photo_active"]?.bool, true)
    }

    func testPingThenCommandRoundTrip() throws {
        plugin.handler = { request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "etat": return [self.answer(request, ["lightroom": "15.0", "echo": request["params"]?["x"] ?? .null])]
            default: return []
            }
        }
        let bridge = makeBridge()
        let state = try bridge.send("etat", ["x": "é ✓"], timeout: 5)
        XCTAssertEqual(state["lightroom"]?.string, "15.0")
        XCTAssertEqual(state["echo"]?.string, "é ✓")
        XCTAssertEqual(plugin.received, ["ping", "etat"])
        XCTAssertFalse(bridge.isConnected, "connexion fermée après chaque commande")

        // Nouvelle connexion, nouveau ping.
        _ = try bridge.send("etat", [:], timeout: 5)
        XCTAssertEqual(plugin.received, ["ping", "etat", "ping", "etat"])
    }

    func testLateRepliesAreSkippedAndErrorsSurface() throws {
        plugin.handler = { request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "appliquer":
                // Une réponse périmée (autre id) arrive avant la bonne, qui est une erreur.
                return [JSONCoding.line(["id": 999, "result": [:]]),
                        JSONCoding.line(["id": request["id"] ?? .null, "error": "Mode « Proposer d'abord » actif"])]
            default: return []
            }
        }
        let bridge = makeBridge()
        XCTAssertThrowsError(try bridge.send("appliquer", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? LightroomError, .plugin("Mode « Proposer d'abord » actif"))
        }
    }

    func testTimeoutClosesConnection() throws {
        plugin.handler = { request in
            request["command"]?.string == "ping" ? [self.answer(request, ["pong": true])] : []
        }
        let bridge = makeBridge()
        XCTAssertThrowsError(try bridge.send("apercu", [:], timeout: 0.3)) { error in
            guard case LightroomError.timeout = error else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(bridge.isConnected)
    }

    func testLostHandshakeIsRetriedOnce() throws {
        // Comme Lightroom quand sa prise des réponses est encore accrochée à l'ancien client.
        var pings = 0
        plugin.handler = { request in
            guard request["command"]?.string == "ping" else { return [self.answer(request, ["ok": true])] }
            pings += 1
            return pings == 1 ? [] : [self.answer(request, ["pong": true])]
        }
        let bridge = makeBridge()
        bridge.handshakeTimeout = 0.3
        XCTAssertEqual(try bridge.send("etat", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertEqual(plugin.received, ["ping", "ping", "etat"])
    }

    func testSilentPluginMeansBusyLinkNotClosedLightroom() throws {
        // Connexion acceptée, aucune réponse au ping : une autre session de Claude tient la liaison.
        plugin.handler = { _ in [] }
        let bridge = makeBridge()
        bridge.handshakeTimeout = 0.3
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 5)) { error in
            XCTAssertEqual(error.localizedDescription, LightroomBridge.busyMessage)
        }
    }

    func testRefusalIsRetriedWhileThePluginReopens() throws {
        let ports = (plugin.requestPort, plugin.replyPort)
        plugin.stop()
        var reopened: FakePlugin?
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            reopened = try? FakePlugin(requestPort: ports.0, replyPort: ports.1)
        }
        let bridge = LightroomBridge(requestPort: ports.0, replyPort: ports.1)
        bridge.refusalRetryWindow = 3
        let pong = try bridge.send("ping", [:], timeout: 5)
        XCTAssertEqual(pong["pong"]?.bool, true)
        reopened?.stop()
    }

    func testReconnectsAfterLightroomDropsTheLink() throws {
        let bridge = makeBridge()
        _ = try bridge.send("ping", [:], timeout: 5)
        plugin.dropConnections()
        Thread.sleep(forTimeInterval: 0.2)
        let pong = try bridge.send("ping", [:], timeout: 5)
        XCTAssertEqual(pong["pong"]?.bool, true)
        XCTAssertEqual(plugin.received, ["ping", "ping", "ping", "ping"], "ping de connexion + commande, deux fois")
    }

    func testUnreachableWhenNothingListens() {
        plugin.stop()
        let bridge = makeBridge()
        bridge.refusalRetryWindow = 0.3
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 1)) { error in
            XCTAssertEqual(error as? LightroomError, .unreachable(LightroomBridge.unreachableMessage))
        }
        XCTAssertFalse(bridge.isConnected)
    }

    /// Une lecture coupée en plein échange (Lightroom relancé, module rechargé) est reprise une fois.
    func testReadCommandIsRetriedAfterACutLink() throws {
        var lectures = 0
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reglages":
                lectures += 1
                if lectures == 1 { self.plugin.dropConnections(); return [] }
                return [self.answer(request, ["reglages": ["Exposure2012": 0.5]])]
            default:
                self.plugin.dropConnections()
                return []
            }
        }
        let bridge = makeBridge()
        bridge.delaiReprise = 0.1
        XCTAssertEqual(try bridge.send("reglages", [:], timeout: 5)["reglages"]?["Exposure2012"]?.double, 0.5)
        XCTAssertEqual(plugin.received, ["ping", "reglages", "ping", "reglages"])

        // Une écriture ne se reprend pas : elle a peut-être été faite.
        XCTAssertThrowsError(try bridge.send("appliquer", [:], timeout: 5)) { error in
            guard case LightroomError.interrupted(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Historique"))
        }
        XCTAssertEqual(plugin.received.filter { $0 == "appliquer" }.count, 1)
    }

    /// Après un délai dépassé, la commande suivante passe par une nouvelle connexion.
    func testTimeoutThenNextCommandWorks() throws {
        var premiere = true
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "apercu":
                if premiere { premiere = false; return [] }
                return [self.answer(request, ["chemin": "/tmp/x.jpg"])]
            default: return []
            }
        }
        let bridge = makeBridge()
        XCTAssertThrowsError(try bridge.send("apercu", [:], timeout: 0.3))
        XCTAssertEqual(try bridge.send("apercu", [:], timeout: 5)["chemin"]?.string, "/tmp/x.jpg")
    }

    /// Le module donne sa version au ping : le serveur la compare à la sienne.
    func testModuleVersionFromHandshake() throws {
        plugin.handler = { [unowned self] request in
            [self.answer(request, request["command"]?.string == "ping" ? ["pong": true, "version": "1.9"] : ["ok": true])]
        }
        let bridge = makeBridge()
        XCTAssertNil(bridge.moduleVersion)
        _ = try bridge.send("etat", [:], timeout: 5)
        XCTAssertEqual(bridge.moduleVersion, "1.9")
    }

    func testPortsFromEnvironment() {
        let bridge = LightroomBridge.fromEnvironment(["DEVELOPPEUR_PORT": "60000"])
        XCTAssertEqual(bridge.requestPort, 60000)
        XCTAssertEqual(bridge.replyPort, 60001)
        XCTAssertEqual(LightroomBridge.fromEnvironment([:]).requestPort, LightroomBridge.defaultRequestPort)
        // Seul fromEnvironment pointe le vrai fichier du jeton (sans le lire ici : aucun envoi).
        XCTAssertEqual(bridge.fichierJeton, JetonLiaison.fichierParDefaut())
        XCTAssertEqual(LightroomBridge.fromEnvironment([:]).fichierJeton, JetonLiaison.fichierParDefaut())
        XCTAssertNil(LightroomBridge(requestPort: 1, replyPort: 2).fichierJeton, "les tests ne lisent jamais le vrai jeton")
    }

    // MARK: Liaison fermée (1.2)

    private let jetonA = String(repeating: "a1", count: 32)
    private let jetonB = String(repeating: "b2", count: 32)

    /// Un fichier du jeton dans un dossier temporaire, jamais le vrai.
    private func fichierJeton(_ contenu: String?) throws -> URL {
        let url = TestSupport.temporaryDirectory().appendingPathComponent(JetonLiaison.nomFichier)
        if let contenu = contenu {
            try Data(contenu.utf8).write(to: url)
        }
        return url
    }

    private func makeBridge(jeton url: URL) -> LightroomBridge {
        LightroomBridge(requestPort: plugin.requestPort, replyPort: plugin.replyPort, fichierJeton: url)
    }

    private func repondreEtat() {
        plugin.handler = { [unowned self] request in
            [self.answer(request, request["command"]?.string == "ping" ? ["pong": true] : ["ok": true])]
        }
    }

    func testJetonPartAvecLePingEtLaCommande() throws {
        repondreEtat()
        plugin.jetonAttendu = jetonA
        let bridge = makeBridge(jeton: try fichierJeton(jetonA + "\n"))
        XCTAssertEqual(try bridge.send("etat", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertEqual(plugin.jetonsRecus, [jetonA, jetonA])
        XCTAssertEqual(plugin.received, ["ping", "etat"])
    }

    func testJetonReluAChaqueConnexion() throws {
        repondreEtat()
        let url = try fichierJeton(jetonA)
        plugin.jetonAttendu = jetonA
        let bridge = makeBridge(jeton: url)
        _ = try bridge.send("etat", [:], timeout: 5)
        // La liaison redémarre : un nouveau jeton, que la connexion suivante relit.
        try Data((jetonB + "\n").utf8).write(to: url)
        plugin.jetonAttendu = jetonB
        _ = try bridge.send("etat", [:], timeout: 5)
        XCTAssertEqual(plugin.jetonsRecus, [jetonA, jetonA, jetonB, jetonB])
    }

    func testJetonRenouveleEntreLectureEtPing() throws {
        repondreEtat()
        let url = try fichierJeton(jetonA)
        plugin.jetonAttendu = jetonB
        plugin.surRefus = { try? Data((self.jetonB + "\n").utf8).write(to: url) }
        let bridge = makeBridge(jeton: url)
        var journal: [String] = []
        bridge.journal = { journal.append($0) }
        XCTAssertEqual(try bridge.send("etat", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertEqual(plugin.received, ["ping", "ping", "etat"])
        XCTAssertEqual(plugin.jetonsRecus, [jetonA, jetonB, jetonB])
        XCTAssertTrue(journal.contains("jeton de la liaison renouvelé : relu"))
    }

    func testMauvaisJetonRefuseSansBoucle() throws {
        repondreEtat()
        plugin.jetonAttendu = jetonB
        let bridge = makeBridge(jeton: try fichierJeton(jetonA))
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 5)) { error in
            guard case LightroomError.plugin(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Liaison fermée"), message)
        }
        XCTAssertEqual(plugin.received, ["ping"], "aucune commande envoyée, une seule tentative")
        XCTAssertFalse(bridge.isConnected)
    }

    func testFichierAbsentFaceAuModuleFerme() throws {
        repondreEtat()
        plugin.jetonAttendu = jetonB
        let bridge = makeBridge(jeton: try fichierJeton(nil))
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? LightroomError, .plugin(LightroomBridge.jetonIntrouvableMessage))
        }
        XCTAssertEqual(plugin.received, ["ping"])
        // Un fichier mal formé vaut un fichier absent.
        let bridgeMalForme = makeBridge(jeton: try fichierJeton(jetonA.uppercased()))
        XCTAssertThrowsError(try bridgeMalForme.send("etat", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? LightroomError, .plugin(LightroomBridge.jetonIntrouvableMessage))
        }
    }

    /// Un serveur neuf face à un module 1.1.1 : pas de fichier, aucune clé `jeton`, accepté comme avant.
    func testSansFichierAncienModuleAccepte() throws {
        repondreEtat()
        let bridge = makeBridge(jeton: try fichierJeton(nil))
        XCTAssertEqual(try bridge.send("etat", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertEqual(plugin.jetonsRecus, [nil, nil])
        XCTAssertFalse(plugin.lignesRecues.contains { $0.contains("jeton") }, "aucune clé jeton")
    }

    /// La liaison redémarre entre le ping et la commande : la commande refusée n'est pas reprise.
    func testCommandeRefuseeApresLePing() throws {
        plugin.handler = { [unowned self] request in
            if request["command"]?.string == "ping" {
                self.plugin.jetonAttendu = self.jetonB
                return [self.answer(request, ["pong": true])]
            }
            return [self.answer(request, ["ok": true])]
        }
        plugin.jetonAttendu = jetonA
        let bridge = makeBridge(jeton: try fichierJeton(jetonA))
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 5)) { error in
            guard case LightroomError.plugin(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Liaison fermée"), message)
        }
        XCTAssertEqual(plugin.received, ["ping", "etat"])
    }

    func testJetonJamaisDansLeJournal() throws {
        repondreEtat()
        let url = try fichierJeton(jetonA)
        plugin.jetonAttendu = jetonB
        plugin.surRefus = { try? Data(self.jetonB.utf8).write(to: url) }
        let bridge = makeBridge(jeton: url)
        var journal: [String] = []
        bridge.journal = { journal.append($0) }
        _ = try bridge.send("etat", [:], timeout: 5)
        plugin.surRefus = nil
        plugin.jetonAttendu = String(repeating: "c3", count: 32)
        var messageErreur = ""
        XCTAssertThrowsError(try bridge.send("etat", [:], timeout: 5)) { messageErreur = $0.localizedDescription }
        XCTAssertFalse(journal.isEmpty)
        for jeton in [jetonA, jetonB] {
            for morceau in [jeton, String(jeton.prefix(32)), String(jeton.suffix(32))] {
                XCTAssertFalse(journal.contains { $0.contains(morceau) }, "journal")
                XCTAssertFalse(messageErreur.contains(morceau), "message d'erreur")
            }
        }
    }
}
