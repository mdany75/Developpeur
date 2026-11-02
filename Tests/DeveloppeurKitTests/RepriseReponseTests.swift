import Foundation
import XCTest
@testable import DeveloppeurKit

/// Ne plus perdre une réponse : chaque commande sauf `ping` part avec un `commande_id` ; quand sa
/// réponse n'arrive pas (liaison coupée, délai dépassé) et que la commande écrit ou coûte, le
/// serveur la redemande au module (`reprendre`) au lieu de la relancer. Faux module TCP
/// (`FakePlugin`) qui imite la mémoire de `Liaison.lua` : les réponses gardées par identifiant.
final class RepriseReponseTests: XCTestCase {
    var plugin: FakePlugin!
    /// Réponses gardées par le faux module (`commande_id` → objet `{result}` ou `{error, code}`),
    /// et identifiants en cours ; lus et écrits sur le fil du faux module seulement, sous `verrou`.
    private var gardees: [String: JSONValue] = [:]
    private var enCours: Set<String> = []
    private let verrou = NSLock()

    override func setUpWithError() throws {
        plugin = try FakePlugin()
    }

    override func tearDown() {
        plugin.stop()
    }

    private func makeBridge(jeton: URL? = nil) -> LightroomBridge {
        let bridge = LightroomBridge(requestPort: plugin.requestPort, replyPort: plugin.replyPort, fichierJeton: jeton)
        bridge.delaiReprise = 0.05
        bridge.intervalleReprise = 0.05
        bridge.attenteReprise = 2
        return bridge
    }

    private func answer(_ request: JSONValue, _ result: JSONValue) -> String {
        JSONCoding.line(["id": request["id"] ?? .null, "result": result])
    }

    /// Réponse du faux module à `reprendre`, comme `Liaison.reprendre`.
    private func repondreReprise(_ request: JSONValue) -> String {
        let cle = request["params"]?["commande_id"]?.string ?? ""
        verrou.lock(); defer { verrou.unlock() }
        if let gardee = gardees[cle] {
            return answer(request, ["trouve": true, "commande": "?", "reponse": gardee])
        }
        return answer(request, ["trouve": false, "en_cours": .bool(enCours.contains(cle))])
    }

    private func garder(_ request: JSONValue, _ reponse: JSONValue) {
        guard let cle = request["commande_id"]?.string else { return }
        verrou.lock(); gardees[cle] = reponse; verrou.unlock()
    }

    private func lignes(_ commande: String) -> [JSONValue] {
        plugin.lignesRecues.compactMap { try? JSONCoding.parse($0) }.filter { $0["command"]?.string == commande }
    }

    /// Une écriture dont la réponse se perd (liaison coupée) : son résultat est repris, et elle
    /// n'est jamais relancée. Sans la reprise, l'appel échouait (« coupée pendant la commande »).
    func testUneEcritureCoupeeSeReprendSansEtreRejouee() throws {
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.repondreReprise(request)]
            case "appliquer":
                // Faite, réponse gardée, puis la liaison se coupe avant qu'elle parte.
                self.garder(request, ["result": ["changement": "Exposure2012"]])
                self.plugin.dropConnections()
                return []
            default: return []
            }
        }
        let resultat = try makeBridge().send("appliquer", ["reglages": ["Exposure2012": 0.5]], timeout: 5)
        XCTAssertEqual(resultat["changement"]?.string, "Exposure2012")
        XCTAssertEqual(plugin.received.filter { $0 == "appliquer" }.count, 1, "jamais rejouée")
        let appliquer = try XCTUnwrap(lignes("appliquer").first)
        let reprise = try XCTUnwrap(lignes("reprendre").first)
        XCTAssertNotNil(appliquer["commande_id"]?.string)
        XCTAssertEqual(reprise["params"]?["commande_id"]?.string, appliquer["commande_id"]?.string)
    }

    /// Délai dépassé : une seule demande de reprise, et la réponse gardée revient.
    func testUneEcritureEnRetardSeReprend() throws {
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.repondreReprise(request)]
            case "metadonnees":
                self.garder(request, ["result": ["ok": true]])
                return [] // la réponse n'arrive pas à temps
            default: return []
            }
        }
        XCTAssertEqual(try makeBridge().send("metadonnees", [:], timeout: 0.3)["ok"]?.bool, true)
        XCTAssertEqual(plugin.received.filter { $0 == "metadonnees" }.count, 1)
        XCTAssertEqual(plugin.received.filter { $0 == "reprendre" }.count, 1)
    }

    /// Une commande que le module dit encore en cours est redemandée jusqu'à sa fin.
    func testUneCommandeEnCoursEstRedemandee() throws {
        var demandes = 0
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre":
                demandes += 1
                if demandes == 3, let cle = request["params"]?["commande_id"]?.string {
                    self.verrou.lock(); self.enCours.remove(cle); self.gardees[cle] = ["result": ["fini": true]]; self.verrou.unlock()
                }
                return [self.repondreReprise(request)]
            case "masquer":
                if let cle = request["commande_id"]?.string { self.verrou.lock(); self.enCours.insert(cle); self.verrou.unlock() }
                self.plugin.dropConnections()
                return []
            default: return []
            }
        }
        XCTAssertEqual(try makeBridge().send("masquer", [:], timeout: 5)["fini"]?.bool, true)
        XCTAssertEqual(plugin.received.filter { $0 == "reprendre" }.count, 3)
        XCTAssertEqual(plugin.received.filter { $0 == "masquer" }.count, 1)
    }

    /// L'erreur gardée revient telle quelle ; un arrêt par la croix reste un arrêt.
    func testUneErreurGardeeRevientTelleQuelle() throws {
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.repondreReprise(request)]
            case "retoucher":
                self.garder(request, ["error": "Aucune photo active."])
            case "ameliorer":
                self.garder(request, ["error": "Arrêtée par l'utilisateur.", "code": "arret"])
            default: break
            }
            self.plugin.dropConnections()
            return []
        }
        let bridge = makeBridge()
        XCTAssertThrowsError(try bridge.send("retoucher", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? LightroomError, .plugin("Aucune photo active."))
        }
        XCTAssertThrowsError(try bridge.send("ameliorer", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? CommandeArretee, CommandeArretee(message: "Arrêtée par l'utilisateur."))
        }
    }

    /// Sans réponse gardée (module rechargé, ou d'avant la reprise : « Commande inconnue »), une
    /// écriture rend son erreur d'origine et n'est jamais relancée.
    func testSansReponseGardeeUneEcritureNEstPasRelancee() throws {
        var ancienModule = false
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre":
                if ancienModule { return [JSONCoding.line(["id": request["id"] ?? .null, "error": "Commande inconnue : reprendre"])] }
                return [self.repondreReprise(request)]
            default:
                self.plugin.dropConnections()
                return []
            }
        }
        let bridge = makeBridge()
        for ancien in [false, true] {
            ancienModule = ancien
            XCTAssertThrowsError(try bridge.send("copier", [:], timeout: 5)) { error in
                guard case LightroomError.interrupted(let message) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(message.contains("Historique"))
            }
        }
        XCTAssertEqual(plugin.received.filter { $0 == "copier" }.count, 2, "une fois par appel, jamais relancée")
    }

    /// Une réponse trop grosse pour être gardée : la commande est faite, rien n'est relancé.
    func testUneReponseNonGardeeLeDitSansRelancer() throws {
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.answer(request, ["trouve": true, "commande": "appliquer", "indisponible": "taille", "octets": 70000])]
            default:
                self.plugin.dropConnections()
                return []
            }
        }
        XCTAssertThrowsError(try makeBridge().send("appliquer", [:], timeout: 5)) { error in
            XCTAssertEqual(error as? LightroomError, .plugin(LightroomBridge.reponseNonGardeeMessage("appliquer")))
        }
        XCTAssertEqual(plugin.received.filter { $0 == "appliquer" }.count, 1)
    }

    /// Une lecture coûteuse (aperçu) se reprend d'abord ; une lecture simple se relance comme
    /// avant, sans reprise ; une lecture coûteuse sans réponse gardée se relance aussi.
    func testLecturesCouteusesRepriseesLecturesSimplesRelancees() throws {
        var apercus = 0
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.repondreReprise(request)]
            case "apercu":
                apercus += 1
                if apercus == 1 {
                    self.garder(request, ["result": ["chemin": "/tmp/a.jpg"]])
                    self.plugin.dropConnections()
                    return []
                }
                if apercus == 2 { self.plugin.dropConnections(); return [] }
                return [self.answer(request, ["chemin": "/tmp/b.jpg"])]
            case "reglages":
                if self.plugin.received.filter({ $0 == "reglages" }).count == 1 { self.plugin.dropConnections(); return [] }
                return [self.answer(request, ["ok": true])]
            default: return []
            }
        }
        let bridge = makeBridge()
        XCTAssertEqual(try bridge.send("apercu", [:], timeout: 5)["chemin"]?.string, "/tmp/a.jpg")
        XCTAssertEqual(apercus, 1, "repris, pas rendu une seconde fois")
        XCTAssertEqual(try bridge.send("apercu", [:], timeout: 5)["chemin"]?.string, "/tmp/b.jpg", "rien de gardé : relancé")
        let avant = plugin.received.filter { $0 == "reprendre" }.count
        XCTAssertEqual(try bridge.send("reglages", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertEqual(plugin.received.filter { $0 == "reprendre" }.count, avant, "une lecture simple ne se reprend pas")
        XCTAssertFalse(LightroomBridge.reprendLaReponse("ping"))
        XCTAssertFalse(LightroomBridge.reprendLaReponse("etat"))
        XCTAssertTrue(LightroomBridge.reprendLaReponse("importerGeneree"))
        XCTAssertTrue(LightroomBridge.reprendLaReponse("vignettes"))
    }

    /// Chaque commande sauf ping porte son propre identifiant ; la reprise porte le jeton comme
    /// toute autre ligne.
    func testIdentifiantsEtJetonDeLaReprise() throws {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("reprise-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        let jeton = String(repeating: "c4", count: 32)
        let fichier = dossier.appendingPathComponent("liaison.jeton")
        try (jeton + "\n").write(to: fichier, atomically: true, encoding: .utf8)
        plugin.jetonAttendu = jeton
        plugin.handler = { [unowned self] request in
            switch request["command"]?.string {
            case "ping": return [self.answer(request, ["pong": true])]
            case "reprendre": return [self.repondreReprise(request)]
            case "etat": return [self.answer(request, ["ok": true])]
            default:
                self.garder(request, ["result": ["ok": true]])
                self.plugin.dropConnections()
                return []
            }
        }
        let bridge = makeBridge(jeton: fichier)
        _ = try bridge.send("etat", [:], timeout: 5)
        _ = try bridge.send("etat", [:], timeout: 5)
        XCTAssertEqual(try bridge.send("collections", [:], timeout: 5)["ok"]?.bool, true)
        XCTAssertTrue(lignes("ping").allSatisfy { $0["commande_id"] == nil }, "le ping n'en porte pas")
        let ids = lignes("etat").compactMap { $0["commande_id"]?.string }
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids.first, ids.last, "un identifiant par commande")
        XCTAssertTrue(ids.allSatisfy { UUID(uuidString: $0) != nil })
        let reprise = try XCTUnwrap(lignes("reprendre").first)
        XCTAssertEqual(reprise["jeton"]?.string, jeton)
        XCTAssertNil(reprise["commande_id"], "la reprise elle-même n'est pas gardée")
    }
}
