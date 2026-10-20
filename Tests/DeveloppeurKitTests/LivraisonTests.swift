import XCTest
@testable import DeveloppeurKit

/// Version 2.0 : livraison (export_photos), variantes en instantanés, harmonisation chiffrée.
final class LivraisonTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var modeles: URL!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
        modeles = TestSupport.temporaryDirectory().appendingPathComponent("Filename Templates")
        try? FileManager.default.createDirectory(at: modeles, withIntermediateDirectories: true)
        tools.filenameTemplates = FilenameTemplates(folder: modeles)
        tools.preferencesLightroom = modeles.appendingPathComponent("absent.plist")
        modele("Date - Nom du fichier", [#"{ value = "date_YYYYMMDD", }"#, #""-","#, #"{ value = "image_name", }"#])
        modele("Nom personnalisé - Séquence", [#"{ value = "custom_token", }"#, #""-","#, #"{ value = "naming_sequenceNumber_3Digits", }"#])
        modele("Nom de la session - Séquence", [#"{ value = "shoot_custom_token", }"#, #""-","#, #"{ value = "naming_sequenceNumber_3Digits", }"#])
    }

    /// Un modèle de noms comme ceux de Lightroom (`deflated`, un élément par ligne).
    private func modele(_ nom: String, _ elements: [String]) {
        let texte = "s = {\n\tdeflated = {\n\t\t{\n" + elements.map { "\t\t\t\($0)\n" }.joined()
            + "\t\t\tname = \"x\",\n\t\t\tpresetType = \"Naming\",\n\t\t},\n\t\t\"AgTokenPresets\",\n\t},\n}\n"
        try? texte.write(to: modeles.appendingPathComponent(nom + ".lrtemplate"), atomically: true, encoding: .utf8)
    }

    private func livrer(_ arguments: [String: JSONValue]) -> ToolResult {
        fake.onSend = { [unowned fake] command, params in
            guard command == "exporter" else { return }
            let fichiers: [JSONValue] = (params["photos"]?.array ?? []).compactMap(\.int).map { id in
                id == 13 ? ["photo": ["id": .number(Double(id)), "fichier": "DSCF13.RAF"], "erreur": "original introuvable"]
                    : ["photo": ["id": .number(Double(id)), "fichier": .string("DSCF\(id).RAF")], "chemin": .string("/Volumes/Photos/Web/DSCF\(id).jpg"), "octets": 1_048_576]
            }
            fake?.replies["exporter"] = ["dossier": "/Volumes/Photos/Web", "fichiers": .array(fichiers)]
        }
        return tools.call(name: "export_photos", arguments: arguments)
    }

    // MARK: export_photos

    func testExportInBatchesWithProfileAndOverrides() throws {
        let ids: [JSONValue] = (1...13).map { .number(Double($0)) }
        let result = livrer(["photo_ids": .array(ids), "folder": "/Volumes/Photos/Web", "profile": "web_5mp", "quality": 70,
                             "filename_template": "nom personnalisé - séquence", "custom_text": "Gaspesie", "start_number": 5, "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        let lots = fake.calls.filter { $0.command == "exporter" }
        XCTAssertEqual(lots.count, 2, "lots de \(ToolHandler.photosPerExport)")
        XCTAssertEqual(lots[0].params["photos"]?.array?.count, 10)
        XCTAssertEqual(lots[0].params["sequence"]?.int, 5)
        XCTAssertEqual(lots[1].params["sequence"]?.int, 15, "la numérotation continue d'un lot à l'autre")
        XCTAssertEqual(lots[0].params["suite"]?.bool, false)
        XCTAssertEqual(lots[1].params["suite"]?.bool, true)
        XCTAssertEqual(lots[0].params["confirme"]?.bool, true)
        XCTAssertEqual(lots[0].params["jetons"]?.string, "{{custom_token}}-{{naming_sequenceNumber_3Digits}}")
        XCTAssertEqual(lots[0].params["texte_perso"]?.string, "Gaspesie")
        let reglages = try XCTUnwrap(lots[0].params["reglages"])
        XCTAssertEqual(reglages["qualite"]?.int, 70, "le réglage donné l'emporte sur le profil")
        XCTAssertEqual(reglages["taille"]?["type"]?.string, "megapixels")
        XCTAssertEqual(reglages["taille"]?["valeur"]?.double, 5)
        XCTAssertNil(reglages["nettete"], "pas de netteté de sortie, comme le service « Lightroom Export 5 Megapixels » de l'utilisateur")
        XCTAssertEqual(ToolHandler.profilsParDefaut.first?.reglages["qualite"]?.int, 100, "qualité 100, relue dans ses services de publication")
        XCTAssertGreaterThanOrEqual(lots[0].timeout, 600)
        let reponse = try JSONCoding.parse(result.text)
        XCTAssertEqual(reponse["livrees"]?.int, 12)
        XCTAssertEqual(reponse["echecs"]?.array?.first?["raison"]?.string, "original introuvable")
        XCTAssertEqual(reponse["taille_totale_mo"]?.double, 12)
        XCTAssertTrue(reponse["reglages"]?.string?.contains("qualité 70, sRGB, 5 mégapixels") == true, reponse["reglages"]?.string ?? "")
        XCTAssertEqual(reponse["profil"]?.string, "web_5mp")
    }

    func testExportValidation() {
        let count = fake.calls.count
        XCTAssertTrue(livrer(["photo_ids": [1], "profile": "pleine_qualite"]).text.contains("choose_folder"), "la fenêtre de choix est rappelée")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "long_edge": 2048, "megapixels": 5]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "filename_template": "Nom personnalisé - Séquence"]).text.contains("custom_text"))
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "filename_template": "Nom de la session - Séquence"]).text.contains("introuvable"),
                      "les modèles de la prise de vue ne s'exportent pas")
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "quality": 120]).isError)
        XCTAssertTrue(livrer(["photo_ids": [1], "folder": "/x", "subfolder": "a/b"]).isError)
        XCTAssertEqual(fake.calls.filter { $0.command == "exporter" }.count, count)
    }

    func testOriginalFormatDropsRenderingSettingsAndActivePhotoIsDefault() throws {
        fake.replies["etat"] = ["photo_active": ["id": 42]]
        XCTAssertFalse(livrer(["folder": "/Volumes/Photos/Originaux", "format": "original", "profile": "web_5mp"]).isError)
        let lot = try XCTUnwrap(fake.calls.last { $0.command == "exporter" })
        XCTAssertEqual(lot.params["photos"]?.array?.first?.int, 42)
        XCTAssertEqual(lot.params["reglages"]?["format"]?.string, "ORIGINAL")
        XCTAssertNil(lot.params["reglages"]?["taille"])
        XCTAssertNil(lot.params["reglages"]?["qualite"])
    }

    func testListAndDialog() throws {
        fake.replies["livraison"] = ["modeles_noms": [["nom": "Date - Nom du fichier"], ["nom": "Modèle maison"]],
                                     "presets_metadonnees": [["nom": "Droits Dany", "id": "uuid"]],
                                     "services_publication": [["nom": "Flickr", "collections": [["id": 7, "nom": "Vacances"]]]]]
        let liste = try JSONCoding.parse(tools.call(name: "export_photos", arguments: ["list": true]).text)
        XCTAssertEqual(liste["profils"]?.array?.map { $0["nom"]?.string }, ["web_5mp", "pleine_qualite"])
        let noms = liste["modeles_noms"]?.array ?? []
        XCTAssertEqual(noms.first { $0["nom"]?.string == "Date - Nom du fichier" }?["jetons"]?.string, "{{date_YYYYMMDD}}-{{image_name}}")
        XCTAssertNotNil(noms.first { $0["nom"]?.string == "Modèle maison" }?["remarque"], "un modèle sans fichier lisible est dit")
        XCTAssertNil(noms.first { $0["nom"]?.string == "Nom de la session - Séquence" })
        XCTAssertNil(liste["services_publication"], "ni services de publication ni leurs collections dans la liste")
        XCTAssertEqual(liste["presets_metadonnees"]?.array?.first?["nom"]?.string, "Droits Dany")

        _ = tools.call(name: "export_photos", arguments: ["photo_ids": [1, 2], "open_dialog": true])
        XCTAssertEqual(fake.calls.last?.command, "fenetreExport")
        XCTAssertEqual(fake.lastParams["photos"]?.array?.count, 2)
    }

    func testFilenameTemplateTokens() {
        let texte = """
        s = {
        \tdeflated = {
        \t\t{
        \t\t\t{
        \t\t\t\tvalue = "custom_token",
        \t\t\t},
        \t\t\t" (",
        \t\t\t{
        \t\t\t\tvalue = "naming_sequenceNumber_1Digit",
        \t\t\t},
        \t\t\t")",
        \t\t\tname = "Custom Name (x of y)",
        """
        XCTAssertEqual(FilenameTemplates.tokens(texte), "{{custom_token}} ({{naming_sequenceNumber_1Digit}})")
    }

    func testRecentExportFoldersFromLightroomPreferences() throws {
        let dossier = TestSupport.temporaryDirectory().appendingPathComponent("Export 5 MP")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let plist = modeles.appendingPathComponent("prefs.plist")
        let valeur = "s = {\n\t\"\(dossier.path)\",\n\t\"/Volumes/Absent/Export\",\n}\n"
        try PropertyListSerialization.data(fromPropertyList: ["AgMRUPopupList_AgExport_destinationFolderPathPrefix": valeur], format: .binary, options: 0)
            .write(to: plist)
        XCTAssertEqual(ToolHandler.recentExportFolders(preferences: plist), [dossier.path], "seulement ceux qui existent")
    }

    // MARK: Variantes

    func testCompareVariantsRendersEachAsASnapshotOnASheet() throws {
        fake.onSend = { [unowned fake] command, params in
            let couleur: UInt8 = params["instantane"]?.string == "chaude" ? 200 : 120
            if command == "essayer" || command == "apercu" {
                fake?.replies[command] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: couleur, green: 120, blue: 120))),
                                          "instantane": params["instantane"]?.string.map { .string("Claude · " + $0) } ?? .null,
                                          "changements": [["cle": "Temperature", "avant": 5200, "apres": 6500]]]
            }
        }
        let result = tools.call(name: "compare_variants", arguments: ["photo_id": 5, "variants": [
            ["name": "naturelle", "settings": ["Exposure2012": 0.2]],
            ["name": "chaude", "settings": ["Temperature": 6500, "Vibrance": 10]],
        ]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["apercu", "essayer", "essayer"])
        let essais = fake.calls.filter { $0.command == "essayer" }
        XCTAssertEqual(essais.map { $0.params["instantane"]?.string }, ["naturelle", "chaude"])
        XCTAssertEqual(essais[1].params["reglages"]?["Temperature"]?.double, 6500)
        XCTAssertEqual(essais[1].params["photo"]?.int, 5)
        guard case .image = result.content.first else { return XCTFail("planche attendue") }
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["variantes"]?.array?[1]["instantane"]?.string, "Claude · chaude")
        XCTAssertEqual(info["variantes"]?.array?[1]["numero"]?.int, 3, "case 1 : l'état actuel")
        XCTAssertEqual(info["variantes"]?.array?[1]["changements"]?.array?.first?["libelle"]?.string, DevelopCatalogue.label(for: "Temperature"))

        XCTAssertTrue(tools.call(name: "compare_variants", arguments: ["variants": [["name": "seule", "settings": ["Exposure2012": 0.2]]]]).isError)
        XCTAssertTrue(tools.call(name: "compare_variants", arguments: ["variants": [["name": "a", "settings": ["Exposure2012": 0.2]],
                                                                                   ["name": "A", "settings": ["Exposure2012": 0.1]]]]).isError)
    }

    func testChooseVariant() {
        _ = tools.call(name: "choose_variant", arguments: ["photo_id": 5, "name": "chaude", "delete_others": true, "confirm": true])
        XCTAssertEqual(fake.calls.last?.command, "variantes")
        XCTAssertEqual(fake.lastParams["action"]?.string, "choisir")
        XCTAssertEqual(fake.lastParams["nom"]?.string, "chaude")
        XCTAssertEqual(fake.lastParams["effacer_autres"]?.bool, true)
        XCTAssertEqual(fake.lastParams["etape"]?.string, "variante chaude")
        XCTAssertEqual(fake.lastParams["confirme"]?.bool, true)
        _ = tools.call(name: "choose_variant", arguments: ["action": "delete", "names": ["naturelle"]])
        XCTAssertEqual(fake.lastParams["action"]?.string, "effacer")
        XCTAssertEqual(fake.lastParams["noms"]?.array?.first?.string, "naturelle")
        XCTAssertTrue(tools.call(name: "choose_variant", arguments: [:]).isError, "il faut nommer la variante")
    }

    // MARK: match_series

    func testMatchSeriesPlansThenCorrectsTwiceAndMeasuresAgain() throws {
        // Référence : gris moyen neutre ; photo 2 : plus sombre et plus froide (RAW à 5000 K).
        var images: [Int: (UInt8, UInt8, UInt8)] = [1: (128, 128, 128), 2: (100, 102, 116)]
        var temperature = 5000.0
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu", let id = params["photo"]?.int, let c = images[id] {
                fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: c.0, green: c.1, blue: c.2))),
                                           "photo": ["fichier": .string("P\(id).RAF")], "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                                           "reglages": ["Temperature": .number(temperature), "Tint": 0]]
            }
            if command == "appliquer" {
                // Première passe : à moitié du chemin ; seconde : la référence.
                let passe = fake?.calls.filter { $0.command == "appliquer" }.count ?? 0
                images[2] = passe == 1 ? (118, 119, 124) : (128, 128, 128)
                temperature += params["reglages"]?["Temperature"]?.double ?? 0
            }
        }
        let plan = try JSONCoding.parse(tools.call(name: "match_series", arguments: ["reference_id": 1, "photo_ids": [1, 2]]).text)
        XCTAssertFalse(fake.commands.contains("appliquer"), "sans accord : le plan seulement")
        let ligne = try XCTUnwrap(plan["photos"]?.array?.first)
        XCTAssertEqual(ligne["id"]?.int, 2, "la référence est écartée")
        let proposee = try XCTUnwrap(ligne["correction_proposee"])
        XCTAssertGreaterThan(proposee["Exposure2012"]?.double ?? 0, 0.3, "plus claire")
        XCTAssertGreaterThan(proposee["Temperature"]?.double ?? 0, 100, "réchauffer (kelvins en plus)")
        XCTAssertNotNil(plan["rien_n_est_applique"])

        let fait = try JSONCoding.parse(tools.call(name: "match_series", arguments: ["reference_id": 1, "photo_ids": [2], "confirm": true,
                                                                                    "step_name": "série du lac"]).text)
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2, "une seconde passe sur l'écart restant")
        XCTAssertEqual(ecritures[0].params["relatif"]?.bool, true)
        XCTAssertEqual(ecritures[0].params["etape"]?.string, "série du lac : passe 1")
        XCTAssertEqual(ecritures[1].params["etape"]?.string, "série du lac : passe 2")
        XCTAssertEqual(ecritures[0].params["confirme"]?.bool, true)
        let apres = try XCTUnwrap(fait["photos"]?.array?.first?["ecart_apres"])
        XCTAssertEqual(apres["exposition_IL"]?.double ?? 1, 0, accuracy: 0.06)
        XCTAssertEqual(fait["photos"]?.array?.first?["etapes"]?.array?.count, 2)
    }

    /// Constaté le 17 octobre 2026 : refaite à chaque mesure, la sélection des tons neutres perd les
    /// pixels qui se colorent ; suivis, ils disent de combien la balance a bougé.
    func testNeutralTonesAreTrackedFromOneMeasureToTheNext() throws {
        func image(gauche: (UInt8, UInt8, UInt8)) -> Data {
            var pixels = [UInt8](repeating: 255, count: 200 * 100 * 4)
            for y in 0..<100 {
                for x in 0..<200 {
                    let i = (y * 200 + x) * 4
                    (pixels[i], pixels[i + 1], pixels[i + 2]) = x < 100 ? gauche : (200, 30, 30)
                }
            }
            return TriTests.encode(pixels, width: 200, height: 100)
        }
        let avant = try XCTUnwrap(Measurements.neutres(image(gauche: (128, 128, 128))))
        XCTAssertEqual(avant.part, 50, accuracy: 2)
        XCTAssertEqual(avant.b, 0, accuracy: 1)
        let rechauffee = image(gauche: (150, 128, 95))
        let suivis = try XCTUnwrap(Measurements.neutres(rechauffee, masque: avant.masque))
        XCTAssertGreaterThan(suivis.b, 18, "les mêmes pixels, devenus jaunes")
        let refaits = try XCTUnwrap(Measurements.neutres(rechauffee))
        XCTAssertLessThan(refaits.part, 5, "une sélection refaite les perd")
        XCTAssertNil(Measurements.neutres(TestSupport.jpeg(red: 1, green: 1, blue: 1), masque: avant.masque), "une autre taille : pas de suivi")
    }

    func testMatchSeriesSolvesTintAndTemperatureTogether() {
        let mesures = Measurements.analyze(TestSupport.jpeg(red: 120, green: 120, blue: 120))!
        let raw = ToolHandler.PhotoSerie(id: 1, fichier: .null, raw: true, temperature: 5000, mesures: mesures)
        // Plus jaune voulu (b* +4,5) : réchauffer d'environ 560 K, la Teinte compense son effet sur a*.
        let (chaud, _) = ToolHandler.correction(.init(exposition: 0, a: 0, b: 4.5, contraste: 0), photo: raw,
                                               dimensions: ["white_balance"], pentes: .init())
        XCTAssertEqual(chaud["Temperature"] ?? 0, 400, accuracy: 120)
        XCTAssertLessThan(chaud["Tint"] ?? 0, 0)
        // Plus magenta voulu (a* +2,4) : Teinte d'environ +8, et la Température compense b*.
        let (magenta, _) = ToolHandler.correction(.init(exposition: 0, a: 2.4, b: 0, contraste: 0), photo: raw,
                                                 dimensions: ["white_balance"], pentes: .init())
        XCTAssertEqual(magenta["Tint"] ?? 0, 8, accuracy: 1)
        let jpeg = ToolHandler.PhotoSerie(id: 2, fichier: .null, raw: false, temperature: 0, mesures: mesures)
        let (jaune, _) = ToolHandler.correction(.init(exposition: 0, a: 0, b: 11.6, contraste: 0), photo: jpeg,
                                               dimensions: ["white_balance"], pentes: .init())
        XCTAssertEqual(jaune["Temperature"] ?? 0, 17, accuracy: 2, "+20 montaient b* de 11,6 (et a* un peu)")
    }

    func testMatchSeriesContrastSlopeFollowsWhatThePhotoShowed() {
        let mesures = Measurements.analyze(TestSupport.jpeg(red: 120, green: 120, blue: 120))!
        var apres = mesures
        apres.percentilesL[95] = (mesures.percentilesL[95] ?? 0) + 3
        let avant = ToolHandler.PhotoSerie(id: 1, fichier: .null, raw: false, temperature: 0, mesures: mesures)
        let ensuite = ToolHandler.PhotoSerie(id: 1, fichier: .null, raw: false, temperature: 0, mesures: apres)
        let pentes = ToolHandler.pentesObservees(.init(), appliquee: ["Contrast2012": 30], avant: avant, apres: ensuite)
        XCTAssertEqual(pentes.contrasteParL, 10, accuracy: 1e-9, "30 de contraste pour 3 d'écart")
        let contraire = ToolHandler.pentesObservees(.init(), appliquee: ["Contrast2012": -30], avant: avant, apres: ensuite)
        XCTAssertEqual(contraire.contrasteParL, ToolHandler.PentesSerie().contrasteParL, "un sens contraire ne change pas la pente")
    }

    func testNewPromptsUseTheNewTools() {
        func texte(_ nom: String, _ arguments: [String: String] = [:]) -> String {
            Prompts.texte(Prompts.all.first { $0.name == nom }!, arguments, guide: "- Noirs denses")
        }
        XCTAssertTrue(texte("tri_seance", ["photos": "la collection Vacances", "garder": "30 %"]).contains("cull_photos"))
        XCTAssertTrue(texte("tri_seance", ["garder": "30 %"]).contains("À garder : 30 % (dans une collection"))
        XCTAssertFalse(texte("tri_seance").contains("Guide de style"), "le tri ne retouche pas")
        // 1.1 : le tri suit le standard de notation ; plus de 4 ou 5 étoiles à proposer, plus de pick.
        XCTAssertFalse(texte("tri_seance").contains("4 ou 5 étoiles"))
        XCTAssertFalse(texte("tri_seance").contains("pick"))
        XCTAssertTrue(texte("tri_seance").contains("propose_ratings"))
        XCTAssertTrue(texte("tri_seance").contains("5 étoiles restent à l'utilisateur"))
        XCTAssertFalse(texte("noter").contains("Guide de style"), "noter ne retouche pas")
        XCTAssertTrue(texte("harmoniser_serie").contains("(\(ToolHandler.maxContactSheet) par planche)"))
        XCTAssertTrue(texte("portrait").contains("face_skin"))
        XCTAssertTrue(texte("portrait").contains("Guide de style de l'utilisateur"))
        XCTAssertTrue(texte("paysage").contains("measure_angle"))
        XCTAssertTrue(texte("noir_et_blanc").contains("GrayMixer"))
        XCTAssertTrue(texte("nuit_iso_eleve").contains("enhance_photo"))
        XCTAssertTrue(texte("partage", ["destination": "Instagram"]).contains("Destination : Instagram."))
        XCTAssertTrue(texte("partage").contains("export_photos avec list = true"))
        XCTAssertTrue(texte("partage").contains("Instagram"))
        XCTAssertTrue(texte("partage").contains("Guide de style de l'utilisateur"))
        let outils = Set(ToolHandler.toolNames)
        for prompt in Prompts.all {
            let mots = Prompts.texte(prompt, [:], guide: nil).split { !$0.isLetter && $0 != "_" }.map(String.init)
            for mot in mots where mot.contains("_") && (mot.hasSuffix("_photos") || mot.hasSuffix("_settings") || mot.hasPrefix("view_") || mot.hasPrefix("add_")) {
                XCTAssertTrue(outils.contains(mot) || ["before_claude"].contains(mot), "\(prompt.name) nomme un outil inconnu : \(mot)")
            }
        }
    }

    func testFlatSettingsForDiff() {
        let lignes = ReglagesAPlat.lignes(["Exposure2012": 0.35, "WhiteBalance": "Custom", "Masques": [["Nom": "Ciel", "Valeur": 1], ["Nom": "Sujet"]],
                                           "Vide": [], "Actif": true])
        XCTAssertEqual(lignes, ["Actif = true", "Exposure2012 = 0.35", "Masques.001.Nom = Ciel", "Masques.001.Valeur = 1",
                                "Masques.002.Nom = Sujet", "Vide = []", "WhiteBalance = Custom"])
    }

    func testNewToolsAreListedWithTitles() {
        let definitions = tools.definitions
        for name in ["export_photos", "compare_variants", "choose_variant", "match_series"] {
            XCTAssertNotNil(definitions.first { $0["name"]?.string == name }?["title"]?.string, name)
        }
    }
}
