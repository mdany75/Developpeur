import XCTest
@testable import DeveloppeurKit

/// Le correctif 1.3.5 : sauvegardes dites par get_status, vidéos écartées, rafales par boîtier,
/// sortie « tirage », apprendre des corrections, rendu reproductible (gardé depuis la 1.3.6 au
/// view_photo avec compare = before_claude, la leçon de la photo retirée).
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
        XCTAssertNil(try registre.noter(rendu(0.6, retours: 0)), "la même retouche qui continue : remplacée, sans retouche d'avant à comparer")
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

    /// Un rendu de la photo 7, daté (le jour et l'heure disent à quel rendu gardé il s'est comparé).
    private func renduDuJour(_ exposition: Double, retours: Int, le jour: String) -> RegistreRendus.Rendu {
        .init(photo: 7, le: Sauvegardes.dateDossier(jour)!, reglages: ["Exposure2012": exposition], profil: "Classic Chrome", retours: retours)
    }

    /// 1.3.6 : un before_claude demandé en cours de retouche (« montre-moi l'avant/après ») ne prend
    /// pas la place de la fin de la retouche d'avant. Dans la même série (autant de retours), chaque
    /// rendu remplace le dernier de la série et se compare encore à la fin de la série d'avant : la
    /// vraie fin de la retouche est comparée, et la réponse dit l'écart du rendu courant.
    func testUneRetoucheQuiContinueSeCompareEncoreALaPrecedente() throws {
        let registre = RegistreRendus(fichier: TestSupport.temporaryDirectory().appendingPathComponent("rendus.json"))
        XCTAssertNil(try registre.noter(renduDuJour(0.3, retours: 0, le: "2026-10-20 1000")), "la première retouche : rien à comparer")
        // Repartie de l'origine ; après la passe 1, un avant/après : comparé à la retouche d'avant.
        let enCours = try XCTUnwrap(registre.noter(renduDuJour(1.0, retours: 1, le: "2026-10-21 0900")))
        XCTAssertEqual(enCours["reproductible"], false)
        XCTAssertEqual(enCours["precedente"]?.string, Sauvegardes.texte(Sauvegardes.dateDossier("2026-10-20 1000")!))
        XCTAssertTrue(enCours["lecture"]?.string?.contains("rejuger à sa fin") == true, enCours["lecture"]?.string ?? "")
        // La fin de la même retouche (pas de retour de plus) : comparée encore à la retouche d'avant,
        // jamais au rendu de la passe 1 qu'elle remplace.
        let fin = try XCTUnwrap(registre.noter(renduDuJour(0.5, retours: 1, le: "2026-10-21 0930")), "la vraie fin de retouche est comparée")
        XCTAssertEqual(fin["reproductible"], true, "0,2 IL de la retouche d'avant : sous le seuil")
        XCTAssertEqual(fin["precedente"]?.string, Sauvegardes.texte(Sauvegardes.dateDossier("2026-10-20 1000")!))
        let ecart = try XCTUnwrap(fin["ecarts"]?.array?.first)
        XCTAssertEqual(ecart["avant"]?.double, 0.3)
        XCTAssertEqual(ecart["maintenant"]?.double, 0.5, "l'écart du rendu courant")
        let gardes = try XCTUnwrap(registre.lire()["7"])
        XCTAssertEqual(gardes.map { $0.reglages["Exposure2012"] }, [0.3, 0.5], "la retouche d'avant gardée, la passe 1 remplacée")
        XCTAssertEqual(gardes.map(\.retours), [0, 1])
    }

    /// Un nouveau retour à l'origine : la série d'avant devient la dernière finie, celle à laquelle
    /// chaque rendu de la nouvelle série se compare ; trois séries gardées au plus.
    func testUnNouveauRetourFaitDeLaSerieDAvantLaDerniereFinie() throws {
        let registre = RegistreRendus(fichier: TestSupport.temporaryDirectory().appendingPathComponent("rendus.json"))
        _ = try registre.noter(renduDuJour(0.3, retours: 0, le: "2026-10-20 1000"))
        _ = try registre.noter(renduDuJour(1.0, retours: 1, le: "2026-10-21 0900"))
        _ = try registre.noter(renduDuJour(0.5, retours: 1, le: "2026-10-21 0930"))
        let finSerie1 = Sauvegardes.texte(Sauvegardes.dateDossier("2026-10-21 0930")!)
        // Le deuxième retour : comparé à la fin de la série 1 (0,5 IL), plus à la première retouche.
        let debut = try XCTUnwrap(registre.noter(renduDuJour(0.6, retours: 2, le: "2026-10-22 0800")))
        XCTAssertEqual(debut["precedente"]?.string, finSerie1)
        XCTAssertEqual(debut["reproductible"], true, "0,1 IL de la fin de la série 1")
        let suite = try XCTUnwrap(registre.noter(renduDuJour(1.5, retours: 2, le: "2026-10-22 0830")))
        XCTAssertEqual(suite["precedente"]?.string, finSerie1, "la série 2 continue : toujours la fin de la série 1")
        XCTAssertEqual(suite["reproductible"], false, "1 IL de la fin de la série 1")
        XCTAssertEqual(try XCTUnwrap(registre.lire()["7"]).map { $0.reglages["Exposure2012"] }, [0.3, 0.5, 1.5])
        // Un troisième retour : la série 2 est la dernière finie ; la première retouche sort (trois au plus).
        let troisieme = try XCTUnwrap(registre.noter(renduDuJour(1.4, retours: 3, le: "2026-10-23 0800")))
        XCTAssertEqual(troisieme["precedente"]?.string, Sauvegardes.texte(Sauvegardes.dateDossier("2026-10-22 0830")!))
        XCTAssertEqual(troisieme["reproductible"], true)
        let gardes = try XCTUnwrap(registre.lire()["7"])
        XCTAssertEqual(gardes.count, RegistreRendus.parPhoto)
        XCTAssertEqual(gardes.map { $0.reglages["Exposure2012"] }, [0.5, 1.5, 1.4])
        // Moins de retours que le dernier gardé (le journal ne garde que ses 200 dernières entrées) :
        // la même série a continué, comparée encore à la série 2.
        let tronque = try XCTUnwrap(registre.noter(renduDuJour(1.45, retours: 1, le: "2026-10-23 0900")))
        XCTAssertEqual(tronque["precedente"]?.string, Sauvegardes.texte(Sauvegardes.dateDossier("2026-10-22 0830")!))
        XCTAssertEqual(try XCTUnwrap(registre.lire()["7"]).map { $0.reglages["Exposure2012"] }, [0.5, 1.5, 1.45])
    }

    /// Un rendus.json d'avant la 1.3.6 (le même format : le dernier rendu de chaque série, profil
    /// parfois absent) se relit tel quel et sert de série d'avant ; 2 000 photos gardées au plus,
    /// les plus anciennes retirées d'abord.
    func testUnRegistreDAvantLa136SeRelit() throws {
        let fichier = TestSupport.temporaryDirectory().appendingPathComponent("rendus.json")
        try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("""
        {"7":[{"le":"2026-10-20T14:00:00Z","photo":7,"profil":"Classic Chrome","reglages":{"Exposure2012":0.3,"Temperature":5500},"retours":0},\
        {"le":"2026-10-21T14:00:00Z","photo":7,"reglages":{"Exposure2012":0.4},"retours":1}],\
        "8":[{"le":"2026-10-19T09:30:00Z","photo":8,"reglages":{"Contrast2012":10},"retours":2}]}
        """.utf8).write(to: fichier)
        let registre = RegistreRendus(fichier: fichier)
        let relu = registre.lire()
        XCTAssertEqual(relu.keys.sorted(), ["7", "8"])
        XCTAssertEqual(relu["7"]?.count, 2)
        XCTAssertNil(relu["7"]?.last?.profil, "un profil absent se relit")
        // La photo 7 continue sa série 1 : le rendu d'avant de la série est remplacé, la série 0 sert.
        let suite = try XCTUnwrap(registre.noter(.init(photo: 7, le: Date(), reglages: ["Exposure2012": 0.45, "Temperature": 5600],
                                                       profil: "Classic Chrome", retours: 1)))
        XCTAssertEqual(suite["precedente"]?.string, Sauvegardes.texte(ISO8601DateFormatter().date(from: "2026-10-20T14:00:00Z")!))
        XCTAssertEqual(suite["reproductible"], true)
        XCTAssertEqual(registre.lire()["7"]?.map(\.retours), [0, 1])
        // La photo 8 repart de l'origine : comparée au rendu d'avant.
        let nouvelle = try XCTUnwrap(registre.noter(.init(photo: 8, le: Date(), reglages: ["Contrast2012": 40], profil: nil, retours: 3)))
        XCTAssertEqual(nouvelle["reproductible"], false, "30 points de contraste : au-delà de 15")
        XCTAssertEqual(registre.lire()["8"]?.count, 2)

        // 2 000 photos au plus : la plus ancienne sort quand une autre arrive.
        var registrePlein: [String: [RegistreRendus.Rendu]] = [:]
        let depart = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        for photo in 1...RegistreRendus.maxPhotos {
            registrePlein[String(photo)] = [.init(photo: photo, le: depart.addingTimeInterval(Double(photo) * 60), reglages: ["Exposure2012": 0], profil: nil, retours: 0)]
        }
        try registre.ecrire(registrePlein)
        XCTAssertNil(try registre.noter(.init(photo: 9999, le: Date(), reglages: ["Exposure2012": 0.2], profil: nil, retours: 0)))
        let apres = registre.lire()
        XCTAssertEqual(apres.count, RegistreRendus.maxPhotos)
        XCTAssertNil(apres["1"], "la plus ancienne retirée")
        XCTAssertNotNil(apres["2"])
        XCTAssertNotNil(apres["9999"])
    }

    /// Le rendu de fin de retouche se garde au view_photo avec compare = before_claude (1.3.6 : il
    /// suivait photo_lesson, retiré), d'après les réglages et le profil de la réponse d'apercu, les
    /// retours comptés au journal de la photo ; seulement avec un registre (serve() : ni les tests, ni
    /// --call, ni la recette n'en ont), jamais avec previous_step ni sur un aperçu simple. Comparé à
    /// la fin de la retouche d'avant le dernier retour à l'origine, à chaque before_claude de la
    /// retouche qui suit (`RegistreRendus.noter`).
    func testLeRenduSeGardeAuViewPhotoAvantClaude() throws {
        let fichier = TestSupport.temporaryDirectory().appendingPathComponent("rendus.json")
        var reglages: [String: JSONValue] = ["Exposure2012": 0.3, "Temperature": 5500, "Contrast2012": 10, "Sharpness": 40]
        var journal: [JSONValue] = [["type": "retouche", "etape": "Claude · passe 1"]]
        let module: FakeLightroom = fake
        module.onSend = { [unowned module] commande, params in
            switch commande {
            case "apercu":
                var reponse: [String: JSONValue] = [
                    "chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 140, green: 140, blue: 140))),
                    "photo": ["id": 7, "fichier": "DSCF0001.RAF"], "reglages": .object(reglages), "profil": "Classic Chrome",
                    "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                ]
                if params["comparer"] != nil {
                    reponse["chemin_avant"] = .string(TestSupport.previewFile(TestSupport.jpeg(red: 100, green: 100, blue: 100)))
                }
                module.replies["apercu"] = .object(reponse)
            case "journal":
                module.replies["journal"] = ["photos": [["photo": ["id": 7, "fichier": "DSCF0001.RAF"], "entrees": .array(journal)]]]
            default:
                break
            }
        }
        func voir(_ arguments: [String: JSONValue]) throws -> JSONValue {
            let resultat = tools.call(name: "view_photo", arguments: arguments)
            XCTAssertFalse(resultat.isError, resultat.text)
            return try JSONCoding.parse(resultat.text)
        }

        // Sans registre : rien n'est gardé, pas de commande journal.
        XCTAssertNil(try voir(["compare": "before_claude"])["rendu_reproductible"])
        XCTAssertEqual(fake.commands, ["apercu"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichier.path))

        let registre = RegistreRendus(fichier: fichier)
        tools.registreRendus = registre
        // Ni previous_step (pas la fin d'une retouche) ni un aperçu simple.
        fake.calls = []
        _ = try voir(["compare": "previous_step"])
        _ = try voir([:])
        XCTAssertEqual(fake.commands, ["apercu", "apercu"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichier.path))

        // La première fin de retouche : gardée (réglages comparés et profil), rien à comparer.
        fake.calls = []
        XCTAssertNil(try voir(["compare": "before_claude", "photo_id": 7])["rendu_reproductible"])
        XCTAssertEqual(fake.commands, ["apercu", "journal"])
        XCTAssertEqual(fake.lastParams["photos"], [7], "le journal de cette photo seulement")
        var gardes = try XCTUnwrap(registre.lire()["7"])
        XCTAssertEqual(gardes.count, 1)
        XCTAssertEqual(gardes[0].reglages, ["Exposure2012": 0.3, "Temperature": 5500, "Contrast2012": 10], "seulement les réglages comparés")
        XCTAssertEqual(gardes[0].profil, "Classic Chrome")
        XCTAssertEqual(gardes[0].retours, 0)

        // La même retouche qui continue (pas de retour de plus) : remplacée, sans comparaison.
        reglages["Exposure2012"] = 0.5
        XCTAssertNil(try voir(["compare": "before_claude"])["rendu_reproductible"])
        gardes = try XCTUnwrap(registre.lire()["7"])
        XCTAssertEqual(gardes.count, 1)
        XCTAssertEqual(gardes[0].reglages["Exposure2012"], 0.5)

        // Repartie de l'origine (une entrée « retour » de plus) : comparée à la précédente.
        journal.append(["type": "retour"])
        reglages["Exposure2012"] = 1.4
        let loin = try XCTUnwrap(try voir(["compare": "before_claude"])["rendu_reproductible"])
        XCTAssertEqual(loin["reproductible"], false)
        XCTAssertTrue((loin["trop_grands"]?.array ?? []).contains { $0.string?.contains("+0,9") == true }, JSONCoding.line(loin))
        XCTAssertEqual(registre.lire()["7"]?.count, 2)

        // Cette retouche continue (un autre before_claude, sans retour de plus) : son rendu remplace
        // celui d'avant, et se compare encore à la fin de la retouche précédente (0,5 IL).
        reglages["Exposure2012"] = 0.6
        let encore = try XCTUnwrap(try voir(["compare": "before_claude"])["rendu_reproductible"], "la fin de la retouche est comparée")
        XCTAssertEqual(encore["reproductible"], true, JSONCoding.line(encore))
        gardes = try XCTUnwrap(registre.lire()["7"])
        XCTAssertEqual(gardes.map { $0.reglages["Exposure2012"] }, [0.5, 0.6])

        // Un journal en erreur : l'outil réussit quand même, sans rendu, et rien ne change.
        fake.errors["journal"] = LightroomError.plugin("journal illisible")
        journal.append(["type": "retour"])
        XCTAssertNil(try voir(["compare": "before_claude"])["rendu_reproductible"])
        XCTAssertEqual(registre.lire()["7"]?.count, 2)
    }
}
