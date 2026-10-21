import XCTest
@testable import DeveloppeurKit

final class MCPServerTests: XCTestCase {
    var fake: FakeLightroom!
    var server: MCPServer!

    override func setUp() {
        fake = FakeLightroom()
        server = TestSupport.makeServer(fake)
    }

    private func call(_ line: String) throws -> JSONValue {
        try JSONCoding.parse(XCTUnwrap(server.handle(line: line)))
    }

    func testInitializeNegotiatesVersionAndAnnouncesPrompts() throws {
        let response = try call(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#)
        XCTAssertEqual(response["id"]?.int, 1)
        XCTAssertEqual(response["result"]?["protocolVersion"]?.string, "2025-03-26")
        XCTAssertEqual(response["result"]?["serverInfo"]?["name"]?.string, "test")
        XCTAssertNotNil(response["result"]?["capabilities"]?["tools"])
        XCTAssertNotNil(response["result"]?["capabilities"]?["prompts"])
        XCTAssertEqual(response["result"]?["instructions"]?.string, "consignes")

        let unknown = try call(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#)
        XCTAssertEqual(unknown["result"]?["protocolVersion"]?.string, MCPServer.supportedProtocolVersions[0])
    }

    /// Un seul connecteur, MCP-Développeur : son identifiant, son nom affiché (`title`, MCP
    /// 2025-06-18), et rien de Photoshop ni de l'agrandissement génératif dans ce qu'il annonce.
    func testServerIsMCPDeveloppeurWithoutPhotoshop() throws {
        XCTAssertEqual(ServerInfo.name, "MCP-Developpeur")
        XCTAssertEqual(ServerInfo.name, ClaudeRegistration.serverKey, "le nom du serveur est sa clé d'inscription")
        XCTAssertEqual(ServerInfo.title, "MCP-Développeur")
        let serveur = MCPServer(name: ServerInfo.name, title: ServerInfo.title, version: "1.0", instructions: ServerInfo.instructions,
                                tools: ToolHandler(lightroom: fake))
        let reponse = try JSONCoding.parse(XCTUnwrap(serveur.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#)))
        XCTAssertEqual(reponse["result"]?["serverInfo"]?["name"]?.string, "MCP-Developpeur")
        XCTAssertEqual(reponse["result"]?["serverInfo"]?["title"]?.string, "MCP-Développeur")
        XCTAssertEqual(reponse["result"]?["serverInfo"]?["version"]?.string, "1.0")
        XCTAssertNil(try call(#"{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}"#)["result"]?["serverInfo"]?["title"], "sans titre donné, pas de title")

        let outils = try call(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)["result"]?["tools"]?.array ?? []
        XCTAssertEqual(outils.count, 34)
        XCTAssertFalse(ToolHandler.toolNames.contains("expand_photo"))
        let refus = try call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"expand_photo","arguments":{}}}"#)
        XCTAssertEqual(refus["error"]?["code"]?.int, JSONRPCError.invalidParams, "outil inconnu")
        let invites = (try call(#"{"jsonrpc":"2.0","id":5,"method":"prompts/list"}"#)["result"]?["prompts"]?.array ?? []).compactMap { $0["name"]?.string }
        XCTAssertEqual(invites, ["retouche_pro", "harmoniser_serie", "tri_seance", "noter", "portrait", "paysage", "noir_et_blanc", "nuit_iso_eleve", "partage"])
        let annonce = (ServerInfo.instructions + JSONCoding.line(.array(outils))
            + Prompts.all.map { Prompts.texte($0, [:], guide: nil) + $0.description }.joined()).lowercased()
        for mot in ["photoshop", "expand_photo", "firefly", "agrandissement", "galerie", "gallery", "concours", "mariage", "crédit adobe"] {
            XCTAssertFalse(annonce.contains(mot), "« \(mot) » reste dans les consignes, les outils ou les invites")
        }
        XCTAssertTrue(ServerInfo.instructions.contains("photographe amateur"))
    }

    func testNotificationsGetNoResponse() {
        XCTAssertNil(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
        XCTAssertNil(server.handle(line: ""))
    }

    func testToolsListHasEveryToolWithSchema() throws {
        let response = try call(#"{"jsonrpc":"2.0","id":3,"method":"tools/list"}"#)
        let tools = try XCTUnwrap(response["result"]?["tools"]?.array)
        XCTAssertEqual(tools.compactMap { $0["name"]?.string }, ToolHandler.toolNames)
        for tool in tools {
            XCTAssertEqual(tool["inputSchema"]?["type"]?.string, "object")
            XCTAssertFalse(tool["description"]?.string?.isEmpty ?? true)
        }
        let apply = try XCTUnwrap(tools.first { $0["name"]?.string == "apply_settings" })
        let settings = try XCTUnwrap(apply["inputSchema"]?["properties"]?["settings"]?["properties"]?.object)
        XCTAssertEqual(Set(settings.keys), Set(DevelopCatalogue.keys))
    }

    func testToolCallReturnsTextAndErrorFlag() throws {
        fake.replies["etat"] = ["module": "Développeur"]
        let ok = try call(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_status","arguments":{}}}"#)
        XCTAssertEqual(ok["result"]?["isError"]?.bool, false)
        XCTAssertTrue(ok["result"]?["content"]?.array?.first?["text"]?.string?.contains("Développeur") ?? false)

        fake.errors["etat"] = LightroomError.unreachable("Lightroom Classic ne répond pas.")
        let failed = try call(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_status","arguments":{}}}"#)
        XCTAssertEqual(failed["result"]?["isError"]?.bool, true)
        XCTAssertEqual(failed["result"]?["content"]?.array?.first?["text"]?.string, "Lightroom Classic ne répond pas.")
    }

    func testPromptsListAndGet() throws {
        let list = try call(#"{"jsonrpc":"2.0","id":6,"method":"prompts/list"}"#)
        let names = try XCTUnwrap(list["result"]?["prompts"]?.array).compactMap { $0["name"]?.string }
        XCTAssertEqual(names, ["retouche_pro", "harmoniser_serie", "tri_seance", "noter", "portrait", "paysage", "noir_et_blanc", "nuit_iso_eleve", "partage"])

        let prompt = try call(#"{"jsonrpc":"2.0","id":7,"method":"prompts/get","params":{"name":"retouche_pro","arguments":{"style":"chaud et doux"}}}"#)
        let message = try XCTUnwrap(prompt["result"]?["messages"]?.array?.first)
        XCTAssertEqual(message["role"]?.string, "user")
        let text = try XCTUnwrap(message["content"]?["text"]?.string)
        XCTAssertTrue(text.contains("Rendu voulu : chaud et doux."))
        XCTAssertTrue(text.contains("view_photo"))

        let plain = try call(#"{"jsonrpc":"2.0","id":8,"method":"prompts/get","params":{"name":"harmoniser_serie"}}"#)
        XCTAssertTrue(plain["result"]?["messages"]?.array?.first?["content"]?["text"]?.string?.contains("naturel") ?? false)

        let unknown = try call(#"{"jsonrpc":"2.0","id":9,"method":"prompts/get","params":{"name":"inconnue"}}"#)
        XCTAssertEqual(unknown["error"]?["code"]?.int, JSONRPCError.invalidParams)
    }

    func testCorrectivePassesOnlyOnAFoundDefectAndAtMostTwo() {
        let retouche = Prompts.retouchePro.render([:])
        XCTAssertTrue(retouche.contains("passe corrective ciblée sur ce seul défaut"))
        XCTAssertTrue(retouche.contains("Deux passes correctives au plus"))
        XCTAssertTrue(retouche.contains("Pas de passe corrective sans défaut constaté"))
        XCTAssertTrue(Prompts.harmoniserSerie.render([:]).contains("au plus deux passes correctives, seulement sur un défaut constaté"))
        XCTAssertTrue(ServerInfo.instructions.contains("passe corrective ciblée sur ce seul défaut"))
        XCTAssertTrue(ServerInfo.instructions.contains("deux au plus"))
        XCTAssertTrue(ServerInfo.instructions.contains("jamais de passe sans défaut constaté"))
    }

    /// 1.1 : noter passe par propose_ratings, selon le standard, jamais 5 étoiles ; l'invite noter
    /// porte le standard (la fenêtre Claude ne lit pas les ressources) et ne retouche rien.
    func testRatingIsAnnouncedInInstructionsAndThePrompt() throws {
        XCTAssertTrue(ServerInfo.instructions.contains("noter : propose_ratings (standard developpeur://notation ; apply = true s'il demande de noter ; 5 ★ : set_metadata, sur sa demande) ;"))
        // 20 octobre 2026 : ce que l'utilisateur demande clairement, Claude le fait.
        XCTAssertTrue(ServerInfo.instructions.contains("Ce qu'il demande clairement, le faire"))
        let reponse = try call(#"{"jsonrpc":"2.0","id":1,"method":"prompts/get","params":{"name":"noter","arguments":{"photos":"la collection Été","passe":"3"}}}"#)
        let texte = try XCTUnwrap(reponse["result"]?["messages"]?.array?.first?["content"]?["text"]?.string)
        XCTAssertTrue(texte.contains("Photos : la collection Été."))
        XCTAssertTrue(texte.contains("pass = 3 dans propose_ratings"))
        XCTAssertTrue(texte.hasSuffix(Notation.standard), "le standard, en entier, à la fin")
        for etape in ["cull_photos", "contact_sheet par planches de 24 à 30", "view_photo", "propose_ratings", "Jamais 5 étoiles",
                      "Jamais set_metadata pour une note sans sa demande"] {
            XCTAssertTrue(texte.contains(etape), etape)
        }
        XCTAssertFalse(Prompts.noter.avecGuide, "noter ne retouche pas")
        XCTAssertTrue(Prompts.noter.render(["passe": "4"]).contains("ne propose rien"))
        XCTAssertTrue(Prompts.noter.render([:]).contains("Toutes les passes"))
        XCTAssertTrue(Prompts.noter.render(["passe": "revoir les 3 étoiles"]).contains("Passe : revoir les 3 étoiles."))
        XCTAssertEqual(Prompts.noter.arguments.map(\.name), ["photos", "passe"])
    }

    func testInstructionsFitWhatClaudeCodeKeeps() {
        // Claude Code coupe les consignes à 4096 caractères (comptés en UTF-16, comme en JavaScript).
        XCTAssertLessThanOrEqual(ServerInfo.instructions.utf16.count, ServerInfo.instructionsLimit)
        XCTAssertTrue(ServerInfo.instructions.hasSuffix("fusions HDR et panorama."), "la fin des consignes reste lisible")
    }

    /// Ce que l'aide d'Adobe enseigne sur l'ordre et l'usage des outils (docs/aide-adobe-developpement.md) :
    /// dans les consignes, ou dans la description de l'outil qu'il concerne (depuis la 2.4, pour
    /// garder les consignes sous la limite de Claude Code).
    func testInstructionsFollowAdobeHelp() {
        let consignes = ServerInfo.instructions + JSONCoding.line(.array(ToolHandler(lightroom: FakeLightroom()).definitions))
        for attendu in [
            "corrections d'objectif puis Upright",
            "Profil adaptatif (RAW) : en premier, sans tonalité automatique",
            "après des taches ou un flou", "« remarques » dit s'il est recalculé", "dents, iris, peau : add_mask avec effect",
            "restée dans les seules ombres se corrige par ShadowTint, pas par Tint",
            "touche toutes les couleurs semblables", "pour un seul objet, un masque",
            "Parametric… à 0 ne prouve pas une courbe droite", "ToneCurvePV2012",
            "avant netteté, masques IA et retouch_spots",
            "Contraindre le recadrage", "coins vides", "un cadre demandé alors que la géométrie est déjà posée", "au centre et à la taille demandés",
            "JPEG sRGB", "le HDR ne se voit pas",
            "Reflets d'une vitre : remove_distractions, avant toute autre retouche", "Personnes", "Poussière ; série : Copier puis Coller de Lightroom", "suppression générative",
            "cull_photos", "contact_sheet", "set_metadata après accord",
            "champ plat", "fusions HDR et panorama", "en HDR (HDREditMode), le rendu SDR", "yeux fermés ou plissés",
            "request_backup", "ne pas l'annoncer comme appliqué",
            "corrections_utilisateur", "proposer de les retenir",
        ] {
            XCTAssertTrue(consignes.contains(attendu), "consignes sans « \(attendu) »")
        }
    }

    func testPromptsFollowAdobeHelp() {
        let retouche = Prompts.retouchePro.render([:])
        for attendu in [
            "Des reflets de vitre se retirent en premier, avant toute autre retouche (remove_distractions)",
            "un profil adaptatif, Adaptive Color ou Adaptive B&W, se pose ici, sans auto_tone", "soit crop.angle",
            "jamais les deux dans la même passe", "measure_angle de nouveau avant tout crop.angle",
            "le module coche « Contraindre le recadrage »", "pour recadrer, fais-le dans un appel suivant", "vérifie qu'aucun coin vide ne reste",
            "pour un seul objet, plutôt un masque", "ShadowTint, pas Tint", "relis d'abord ToneCurvePV2012",
            "enhance_photo) d'abord, avant la netteté, les masques et les taches de l'étape 7", "pas de LuminanceSmoothing par-dessus",
            "ce qui reste à faire à la main",
        ] {
            XCTAssertTrue(retouche.contains(attendu), "retouche_pro sans « \(attendu) »")
        }
        let serie = Prompts.harmoniserSerie.render([:])
        XCTAssertTrue(serie.contains("les yeux fermés"))
        XCTAssertTrue(serie.contains("match_series avec confirm = true"), "harmoniser_serie passe par match_series")
        XCTAssertTrue(Prompts.paysage.render([:]).contains("soit Upright si des verticales penchent, soit l'horizon redressé"))
        XCTAssertTrue(serie.contains("contact_sheet"))
        XCTAssertTrue(serie.contains("cull_photos"))
        XCTAssertTrue(serie.contains("Lightroom recalcule pour chaque photo"))
        XCTAssertTrue(serie.contains("Lightroom resserre le cadre de chacune"))
        XCTAssertTrue(serie.contains("Suppression des distractions › Poussière"))
    }

    func testUnknownMethodAndBadJSON() throws {
        let unknown = try call(#"{"jsonrpc":"2.0","id":10,"method":"sampling/createMessage"}"#)
        XCTAssertEqual(unknown["error"]?["code"]?.int, JSONRPCError.methodNotFound)
        // Un outil inconnu est une erreur de protocole, pas un résultat d'outil.
        let outil = try call(#"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"inconnu","arguments":{}}}"#)
        XCTAssertEqual(outil["error"]?["code"]?.int, JSONRPCError.invalidParams)
        let bad = try call("{pas du json")
        XCTAssertEqual(bad["error"]?["code"]?.int, JSONRPCError.parseError)
    }
}
