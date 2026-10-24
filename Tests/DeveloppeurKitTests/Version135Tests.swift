import XCTest
@testable import DeveloppeurKit

/// Le correctif 1.3.5 : sauvegardes dites par get_status, vidéos écartées, rafales par boîtier,
/// sortie « tirage », apprendre des corrections, rendu reproductible.
final class Version135Tests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
        let dossier = TestSupport.temporaryDirectory()
        tools.filenameTemplates = FilenameTemplates(folder: dossier.appendingPathComponent("Filename Templates"))
        tools.preferencesLightroom = dossier.appendingPathComponent("absent.plist")
    }

    // MARK: Sauvegarde dite avant une série

    func testLaDerniereSauvegardeDuCatalogue() {
        let maintenant = Sauvegardes.dateDossier("2026-10-23 2100")!
        var dossierLu: URL?
        let trouvee = Sauvegardes.catalogue(chemin: "/Volumes/Photos/Lightroom/Lightroom Catalog.lrcat", maintenant: maintenant) { dossier in
            dossierLu = dossier
            return ["2026-10-20 2135", "2026-10-21 0900", ".DS_Store", "autre"]
        }
        XCTAssertEqual(dossierLu?.path, "/Volumes/Photos/Lightroom/Backups", "le dossier Backups à côté du catalogue")
        XCTAssertEqual(trouvee["trouvee"], true)
        XCTAssertEqual(trouvee["derniere"]?.string, "2026-10-21 09:00")
        XCTAssertEqual(trouvee["nombre"]?.int, 2)
        XCTAssertEqual(trouvee["il_y_a"]?.string, "il y a 2 jours", "60 heures")
        let absent = Sauvegardes.catalogue(chemin: "/Volumes/Photos/x.lrcat", maintenant: maintenant) { _ in nil }
        XCTAssertEqual(absent["trouvee"], false)
        XCTAssertNotNil(absent["remarque"])
        XCTAssertEqual(Sauvegardes.catalogue(chemin: "/a/b.lrcat", maintenant: maintenant) { _ in ["autre"] }["trouvee"], false)
    }

    func testTimeMachineEtLeVolumeDuCatalogue() {
        let maintenant = Sauvegardes.dateDossier("2026-10-24 0100")!
        let plist: [String: Any] = ["AutoBackup": 1, "Destinations": [["LastKnownVolumeName": "Backup",
                                                                        "SnapshotDates": [Sauvegardes.dateDossier("2026-10-23 2000")!, Sauvegardes.dateDossier("2026-10-24 0000")!]]]]
        var demande: String?
        let exclu = Sauvegardes.timeMachine(plist: plist, cheminCatalogue: "/Volumes/Photos/Lightroom/c.lrcat", maintenant: maintenant) { chemin in
            demande = chemin
            return true
        }
        XCTAssertEqual(demande, "/Volumes/Photos", "le volume du catalogue, pas le catalogue")
        XCTAssertEqual(exclu["configuree"], true)
        XCTAssertEqual(exclu["automatique"], true)
        XCTAssertEqual(exclu["derniere"]?.string, "2026-10-24 00:00")
        XCTAssertEqual(exclu["destination"]?.string, "Backup")
        XCTAssertEqual(exclu["volume_du_catalogue"]?.string, "Photos")
        XCTAssertEqual(exclu["volume_dans_time_machine"], false)
        XCTAssertTrue(exclu["remarque"]?.string?.contains("sans rien régler") == true)
        let interne = Sauvegardes.timeMachine(plist: plist, cheminCatalogue: "/Users/x/Pictures/c.lrcat", maintenant: maintenant) { _ in false }
        XCTAssertEqual(interne["volume_du_catalogue"]?.string, "disque du Mac")
        XCTAssertEqual(interne["volume_dans_time_machine"], true)
        XCTAssertEqual(Sauvegardes.timeMachine(plist: [:], cheminCatalogue: "/x.lrcat", maintenant: maintenant) { _ in nil }["configuree"], false)
        // Préférences illisibles (le connecteur lancé depuis Lightroom, constaté le 23 octobre 2026) :
        // tmutil dit la destination et le volume.
        let repli = Sauvegardes.timeMachine(plist: nil, cheminCatalogue: "/Volumes/Photos/c.lrcat", maintenant: maintenant,
                                            exclu: { _ in true }, destinations: { ["Backup"] })
        XCTAssertEqual(repli["preferences_lues"], false)
        XCTAssertEqual(repli["configuree"], true)
        XCTAssertEqual(repli["destination"]?.string, "Backup")
        XCTAssertEqual(repli["volume_dans_time_machine"], false)
        XCTAssertNotNil(repli["a_savoir"])
        XCTAssertEqual(Sauvegardes.timeMachine(plist: nil, cheminCatalogue: "/x.lrcat", maintenant: maintenant,
                                               exclu: { _ in nil }, destinations: { [] })["configuree"], false)
        XCTAssertEqual(Sauvegardes.nomsDestinations("=====\nName          : Backup\nKind          : Network\nID            : AF\n"), ["Backup"])
        let pasLu = Sauvegardes.timeMachine(plist: plist, cheminCatalogue: "/Volumes/Photos/c.lrcat", maintenant: maintenant) { _ in nil }
        XCTAssertEqual(pasLu["volume_dans_time_machine"], .null)
    }

    func testGetStatusDitLesSauvegardesSansLeCheminDuCatalogue() throws {
        fake.replies["etat"] = ["module": "Développeur", "version_module": .string(ServerInfo.version), "catalogue": "Lightroom Catalog.lrcat",
                                "chemin_catalogue": "/Volumes/Photos/Lightroom Catalog.lrcat"]
        var lu: String?
        tools.lireSauvegardes = { chemin in lu = chemin; return ["catalogue": ["trouvee": false]] }
        let reponse = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)
        XCTAssertEqual(lu, "/Volumes/Photos/Lightroom Catalog.lrcat")
        XCTAssertNil(reponse["chemin_catalogue"], "le chemin ne va pas à Claude")
        XCTAssertNotNil(reponse["sauvegardes"])
        // Par défaut (les tests, la recette), rien n'est lu.
        let defaut = try JSONCoding.parse(ToolHandler(lightroom: fake).call(name: "get_status", arguments: [:]).text)
        XCTAssertNil(defaut["sauvegardes"])
        XCTAssertNil(defaut["chemin_catalogue"])
    }

    // MARK: Vidéos écartées, rafales par boîtier

    func testLesVideosDUneCollectionSontEcarteesEtComptees() throws {
        fake.replies["chercher"] = ["total": 3, "photos": [["id": 1, "format": "RAW"], ["id": 2, "format": "VIDEO", "video": true], ["id": 3, "format": "JPG"]]]
        let serie = try tools.seriesPhotosSansVideos(Arguments(raw: ["collection": "Sortie"]), maximum: 10)
        XCTAssertEqual(serie.ids, [1, 3])
        XCTAssertEqual(serie.videos, 1)
        XCTAssertEqual(try tools.seriesPhotos(Arguments(raw: ["collection": "Sortie"]), maximum: 10).ids, [1, 3])
        XCTAssertTrue(ToolHandler.estVideo(["format": "video"]))
        XCTAssertFalse(ToolHandler.estVideo(["format": "RAW"]))
        // Le tri d'une collection qui n'a que des vidéos le dit.
        fake.replies["chercher"] = ["total": 1, "photos": [["id": 2, "format": "VIDEO"]]]
        let tri = tools.call(name: "cull_photos", arguments: ["collection": "Sortie"])
        XCTAssertTrue(tri.isError)
        XCTAssertTrue(tri.text.contains("1 vidéo(s)"), tri.text)
    }

    func testDeuxBoitiersNeFormentPasUneRafale() {
        var a = PhotoTriee(id: 1, fichier: "a"), b = PhotoTriee(id: 2, fichier: "b")
        a.boitier = "1234"; b.boitier = "5678"
        XCTAssertFalse(Tri.memeRafale(a, b))
    }

    // MARK: Préparer un tirage

    func testUnTirageDonneLaTailleLaResolutionEtLaNettete() throws {
        let t = try ToolHandler.tirage(["size": "20x30"])
        XCTAssertEqual(t.grandCote, 3543, "30 cm à 300 ppp")
        XCTAssertEqual(t.ppp, 300)
        XCTAssertEqual(t.papier, "glossy")
        XCTAssertEqual(try ToolHandler.tirage(["size": "30 × 45", "ppi": 240, "paper": "matte"]).grandCote, 4252)
        XCTAssertThrowsError(try ToolHandler.tirage(["size": "grand"]))
        XCTAssertThrowsError(try ToolHandler.tirage(["size": "20x30", "ppi": 1000]))
        XCTAssertThrowsError(try ToolHandler.tirage(["size": "20x30", "paper": "toile"]))

        fake.onSend = { [unowned fake] command, params in
            guard command == "exporter" else { return }
            fake?.replies["exporter"] = ["dossier": "/Volumes/Photos/Tirages", "fichiers": .array((params["photos"]?.array ?? []).map { ["photo": ["id": $0]] })]
        }
        let result = tools.call(name: "export_photos", arguments: ["photo_ids": [5], "folder": "/Volumes/Photos/Tirages", "format": "tiff",
                                                                    "print": ["size": "20x30", "paper": "matte"], "confirm": true])
        XCTAssertFalse(result.isError, result.text)
        let reglages = try XCTUnwrap(fake.calls.first { $0.command == "exporter" }?.params["reglages"])
        XCTAssertEqual(reglages["taille"]?["type"]?.string, "longEdge")
        XCTAssertEqual(reglages["taille"]?["valeur"]?.int, 3543)
        XCTAssertEqual(reglages["resolution"]?.int, 300)
        XCTAssertEqual(reglages["nettete"]?["support"]?.string, "matte")
        XCTAssertEqual(reglages["nettete"]?["niveau"]?.int, 2)
        // Une taille donnée à part l'emporte.
        fake.calls.removeAll()
        _ = tools.call(name: "export_photos", arguments: ["photo_ids": [5], "folder": "/Volumes/Photos/Tirages", "long_edge": 2000,
                                                          "print": ["size": "20x30"], "confirm": true])
        XCTAssertEqual(fake.calls.first { $0.command == "exporter" }?.params["reglages"]?["taille"]?["valeur"]?.int, 2000)
    }

    // MARK: Apprendre de tes corrections

    func testUneRegleSeulementSiFrequenteEtConstante() {
        func r(_ cle: String, _ ecart: Double) -> Apprentissage.Reprise { .init(cle: cle, claude: 10, maintenant: 10 + ecart) }
        let parPhoto: [[Apprentissage.Reprise]] = [
            [r("Dehaze", -8), r("Contrast2012", 10)],
            [r("Dehaze", -6), r("Contrast2012", -10)],
            [r("Dehaze", -10), r("Contrast2012", 5), r("Vibrance", 5)],
            [r("Texture", 3)],
        ]
        let regles = Apprentissage.regles(parPhoto)
        XCTAssertEqual(regles.map(\.cle), ["Dehaze"], "le contraste change de sens, la vibrance est trop rare")
        XCTAssertEqual(regles[0].photos, 3)
        XCTAssertEqual(regles[0].sur, 4)
        XCTAssertEqual(regles[0].moyenne, -8, accuracy: 1e-9)
        XCTAssertEqual(regles[0].rubrique, "tone")
        XCTAssertEqual(Apprentissage.rubrique("Temperature"), "color")
        XCTAssertEqual(Apprentissage.rubrique("GrainAmount"), "grain")
        XCTAssertTrue(Apprentissage.regles([]).isEmpty)
    }

    func testRememberStyleApprendDesReprisesSansRienEcrire() throws {
        let guide = GuideStyle(fichier: TestSupport.temporaryDirectory().appendingPathComponent("guide-de-style.md"))
        tools = ToolHandler(lightroom: fake, guideStyle: guide)
        fake.onSend = { [unowned fake] command, params in
            guard command == "reglages", let id = params["photo"]?.int else { return }
            fake?.replies["reglages"] = id == 4 ? ["reglages": [:]]
                : ["corrections_utilisateur": ["changements": [["cle": "Dehaze", "claude": 12, "maintenant": .number(Double(12 - 2 * id))]]]]
        }
        let reponse = try JSONCoding.parse(tools.call(name: "remember_style", arguments: ["learn": true, "photo_ids": [1, 2, 3, 4]]).text)
        XCTAssertEqual(reponse["photos_lues"]?.int, 4)
        XCTAssertEqual(reponse["photos_reprises"]?.int, 3)
        let regle = try XCTUnwrap(reponse["regles"]?.array?.first)
        XCTAssertEqual(regle["reglage"]?.string, "Dehaze")
        XCTAssertTrue(regle["constat"]?.string?.hasPrefix("Tu baisses") == true, regle["constat"]?.string ?? "")
        XCTAssertNotNil(regle["phrase_proposee"])
        XCTAssertNil(guide.lire(), "rien n'est ajouté au guide sans accord")
        XCTAssertFalse(fake.commands.contains { $0 != "reglages" }, "des lectures seulement")
        // Sans série, la demande est refusée.
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["learn": true]).isError)
    }

    // MARK: Rendu reproductible

    func testUnRenduSeCompareSeulementApresUnRetourALOrigine() throws {
        let registre = RegistreRendus(fichier: TestSupport.temporaryDirectory().appendingPathComponent("rendus.json"))
        func rendu(_ exposition: Double, temperature: Double = 5500, retours: Int, profil: String = "Classic Chrome") -> RegistreRendus.Rendu {
            .init(photo: 7, le: Sauvegardes.dateDossier("2026-10-20 1000")!, reglages: ["Exposure2012": exposition, "Temperature": temperature], profil: profil, retours: retours)
        }
        XCTAssertNil(try registre.noter(rendu(0.3, retours: 0)), "le premier rendu : rien à comparer")
        XCTAssertNil(try registre.noter(rendu(0.6, retours: 0)), "la même retouche qui continue : remplacée, pas comparée")
        XCTAssertEqual(registre.lire()["7"]?.count, 1)
        let proche = try XCTUnwrap(registre.noter(rendu(0.7, temperature: 5800, retours: 1)))
        XCTAssertEqual(proche["reproductible"], true, "0,1 IL et 300 K : sous les seuils")
        let loin = try XCTUnwrap(registre.noter(rendu(1.3, temperature: 6400, retours: 2, profil: "Velvia")))
        XCTAssertEqual(loin["reproductible"], false)
        let trop = (loin["trop_grands"]?.array ?? []).compactMap(\.string)
        XCTAssertEqual(trop.count, 3, "\(trop)")
        XCTAssertTrue(trop.contains { $0.contains("Velvia") })
        XCTAssertTrue(loin["lecture"]?.string?.contains("n'est pas un style") == true)
        XCTAssertEqual(registre.lire()["7"]?.count, RegistreRendus.parPhoto, "trois rendus gardés au plus")
    }
}
