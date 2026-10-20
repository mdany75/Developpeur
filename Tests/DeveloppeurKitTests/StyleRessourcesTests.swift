import XCTest
@testable import DeveloppeurKit

/// Version 2.0 : guide de style personnel, ressources MCP, sorties structurées.
final class StyleRessourcesTests: XCTestCase {
    var fake: FakeLightroom!
    var guide: GuideStyle!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        guide = GuideStyle(fichier: TestSupport.temporaryDirectory().appendingPathComponent("guide-de-style.md"))
        tools = ToolHandler(lightroom: fake, guideStyle: guide)
    }

    private func call(_ server: MCPServer, _ line: String) throws -> JSONValue {
        try JSONCoding.parse(XCTUnwrap(server.handle(line: line)))
    }

    // MARK: Guide de style

    func testRememberStyleNeedsTheUsersAgreementAndFilesUnderItsCategory() throws {
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["preference": "Noirs denses"]).isError, "pas sans accord")
        XCTAssertNil(guide.lire())
        let lu = try JSONCoding.parse(tools.call(name: "remember_style", arguments: ["read": true]).text)
        XCTAssertTrue(lu["a_savoir"]?.string?.contains("Pas encore") == true)

        let date = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
        try guide.ajouter("Noirs denses, contraste marqué", rubrique: "tone", date: date)
        XCTAssertFalse(tools.call(name: "remember_style", arguments: ["preference": "Jamais de vignetage", "category": "other", "confirm": true]).isError)
        try guide.ajouter("Peaux chaudes, jamais orangées", rubrique: "skin", date: date)
        try guide.ajouter("Ombres jamais bouchées", rubrique: "tone", date: date)
        let texte = try XCTUnwrap(guide.lire())
        XCTAssertTrue(texte.hasPrefix("# Guide de style"))
        let lumiere = try XCTUnwrap(texte.range(of: "## Lumière et contraste"))
        let peaux = try XCTUnwrap(texte.range(of: "## Peaux et portraits"))
        let ombres = try XCTUnwrap(texte.range(of: "Ombres jamais bouchées"))
        XCTAssertTrue(lumiere.upperBound < ombres.lowerBound && ombres.lowerBound < peaux.lowerBound, "rangée sous sa rubrique :\n\(texte)")
        XCTAssertTrue(texte.contains("- Noirs denses, contraste marqué _(ajouté le 2026-10-18)_"))
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["preference": "x", "category": "ciel", "confirm": true]).isError)
    }

    func testRetouchePromptCarriesTheStyleGuide() throws {
        let server = TestSupport.makeServer(fake, guide: guide)
        let sans = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"prompts/get","params":{"name":"retouche_pro"}}"#)
        XCTAssertFalse(sans["result"]?["messages"]?.array?.first?["content"]?["text"]?.string?.contains("Guide de style") ?? true)
        try guide.ajouter("Profil Camera CLASSIC Chrome pour la rue", rubrique: "profiles")
        let avec = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"prompts/get","params":{"name":"retouche_pro"}}"#)
        let texte = avec["result"]?["messages"]?.array?.first?["content"]?["text"]?.string ?? ""
        XCTAssertTrue(texte.contains("Guide de style de l'utilisateur"))
        XCTAssertTrue(texte.contains("CLASSIC Chrome pour la rue"))
    }

    // MARK: Ressources

    func testResourcesAreListedAndRead() throws {
        let image = TestSupport.jpeg(red: 40, green: 90, blue: 150)
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" { fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image))] }
        }
        fake.replies["journal"] = ["photos": [["photo": ["id": 7, "fichier": "DSCF7.RAF"], "entrees": [["date": "2026-10-18 10:00", "etape": "Claude · passe 1", "raison": "Sous-exposée.", "changements": []]]]]]
        try guide.ajouter("Grain fin sur le noir et blanc", rubrique: "grain")
        let server = TestSupport.makeServer(fake, guide: guide)
        let init_ = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        XCTAssertNotNil(init_["result"]?["capabilities"]?["resources"])
        let liste = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"resources/list"}"#)
        XCTAssertEqual(liste["result"]?["resources"]?.array?.compactMap { $0["uri"]?.string }, ["developpeur://guide-de-style", "developpeur://photo/active/apercu"])
        let modeles = try call(server, #"{"jsonrpc":"2.0","id":3,"method":"resources/templates/list"}"#)
        XCTAssertEqual(modeles["result"]?["resourceTemplates"]?.array?.count, 2)

        let lu = try call(server, #"{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"developpeur://guide-de-style"}}"#)
        XCTAssertTrue(lu["result"]?["contents"]?.array?.first?["text"]?.string?.contains("Grain fin") == true)
        let apercu = try call(server, #"{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"developpeur://photo/12/apercu"}}"#)
        let contenu = try XCTUnwrap(apercu["result"]?["contents"]?.array?.first)
        XCTAssertEqual(contenu["mimeType"]?.string, "image/jpeg")
        XCTAssertNotNil(Data(base64Encoded: contenu["blob"]?.string ?? ""))
        XCTAssertEqual(fake.calls.last { $0.command == "apercu" }?.params["photo"]?.int, 12)
        let journal = try call(server, #"{"jsonrpc":"2.0","id":6,"method":"resources/read","params":{"uri":"developpeur://photo/7/journal"}}"#)
        XCTAssertTrue(journal["result"]?["contents"]?.array?.first?["text"]?.string?.contains("Sous-exposée.") == true)
        let inconnue = try call(server, #"{"jsonrpc":"2.0","id":7,"method":"resources/read","params":{"uri":"developpeur://ailleurs"}}"#)
        XCTAssertEqual(inconnue["error"]?["code"]?.int, -32002)
    }

    func testSubscribedClientsHearThatTheActivePhotoChanged() throws {
        let server = TestSupport.makeServer(fake, guide: guide)
        var notifications: [JSONValue] = []
        server.notifier = { notifications.append($0) }
        let init_ = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)
        XCTAssertEqual(init_["result"]?["capabilities"]?["resources"]?["subscribe"]?.bool, true)
        server.evenementModule(["photo_active": true])
        XCTAssertTrue(notifications.isEmpty, "personne ne suit la ressource")
        _ = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"resources/subscribe","params":{"uri":"developpeur://photo/active/apercu"}}"#)
        server.evenementModule(["photo_active": true])
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?["method"]?.string, "notifications/resources/updated")
        XCTAssertEqual(notifications.first?["params"]?["uri"]?.string, "developpeur://photo/active/apercu")
        _ = try call(server, #"{"jsonrpc":"2.0","id":3,"method":"resources/unsubscribe","params":{"uri":"developpeur://photo/active/apercu"}}"#)
        server.evenementModule(["photo_active": true])
        XCTAssertEqual(notifications.count, 1)
    }

    /// Constaté en 2.3 : Claude Desktop ne s'abonne à aucune ressource. Le changement de photo active
    /// est alors dit une fois, avec le résultat d'outil suivant (pas après show_photo, qui l'a fait).
    func testUnsubscribedClientsHearTheActivePhotoChangeInTheNextToolResult() throws {
        let server = TestSupport.makeServer(fake, guide: guide)
        server.evenementModule(["photo_active": true, "id": 42, "fichier": "DSCF4306.RAF (Copie 1)"])
        let premier = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_status","arguments":{}}}"#)
        let textes = premier["result"]?["content"]?.array?.compactMap { $0["text"]?.string } ?? []
        XCTAssertTrue(textes.contains { $0.contains("la photo active a changé") && $0.contains("DSCF4306.RAF (Copie 1)") && $0.contains("id 42") }, "\(textes)")
        let second = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_status","arguments":{}}}"#)
        XCTAssertFalse((second["result"]?["content"]?.array ?? []).contains { $0["text"]?.string?.contains("photo active a changé") == true }, "une seule fois")
        server.evenementModule(["photo_active": true, "id": 43])
        XCTAssertNil(server.photoActiveAnnoncee(pour: "show_photo"), "show_photo l'a changée lui-même")
        XCTAssertNil(server.photoActiveAnnoncee(pour: "get_status"), "et l'annonce est consommée")
    }

    // MARK: Sorties structurées

    func testStructuredOutputForToolsWithASchema() throws {
        fake.replies["selection"] = ["total": 1, "renvoyees": 1, "photos": [["id": 3, "fichier": "DSCF3.RAF"]]]
        let server = TestSupport.makeServer(fake, guide: guide)
        let liste = try call(server, #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        let outils = liste["result"]?["tools"]?.array ?? []
        let selection = try XCTUnwrap(outils.first { $0["name"]?.string == "list_selection" })
        XCTAssertEqual(selection["outputSchema"]?["type"]?.string, "object")
        XCTAssertNil(outils.first { $0["name"]?.string == "view_photo" }?["outputSchema"], "pas de schéma pour une image")

        let reponse = try call(server, #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_selection","arguments":{}}}"#)
        XCTAssertEqual(reponse["result"]?["structuredContent"]?["total"]?.int, 1)
        XCTAssertTrue(reponse["result"]?["content"]?.array?.first?["text"]?.string?.contains("DSCF3.RAF") == true, "le texte JSON reste")

        // Une réponse d'attente porte aussi un contenu structuré (le client l'exige).
        fake.onSend = { _, _ in Thread.sleep(forTimeInterval: 0.6) }
        server.toolBudget = 0.2
        let attente = try call(server, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_selection","arguments":{"limit":5}}}"#)
        XCTAssertTrue(attente["result"]?["structuredContent"]?["message"]?.string?.contains("n'est pas fini") == true)
    }
}
