import XCTest
@testable import DeveloppeurKit

/// Le dossier commun (1.7, DossierDonnees.swift) : le pointeur local lu à chaque accès, la racine des
/// données, le refus quand le dossier commun réglé est introuvable (jamais de repli sur ce Mac), le
/// rebasage des chemins enregistrés, et les outils qui s'en servent. Tout dans un dossier temporaire :
/// jamais le vrai pointeur ni les vrais dossiers de Dany.
final class DossierDonneesTests: XCTestCase {
    var racineLocale: URL!
    var commun: URL!
    var donnees: DossierDonnees!

    override func setUp() {
        let base = TestSupport.temporaryDirectory()
        racineLocale = base.appendingPathComponent("local/Developpeur", isDirectory: true)
        commun = base.appendingPathComponent("Photos/Développeur commun", isDirectory: true)
        try? FileManager.default.createDirectory(at: racineLocale, withIntermediateDirectories: true)
        donnees = DossierDonnees(racineLocale: racineLocale)
    }

    func ecrirePointeur(_ texte: String) throws {
        try texte.write(to: donnees.pointeur, atomically: true, encoding: .utf8)
    }

    func pointer(_ dossier: URL) throws {
        try ecrirePointeur(JSONCoding.line(["format": 1, "dossier": .string(dossier.path)]))
    }

    /// Tous les fichiers sous un dossier (chemins relatifs).
    func contenu(_ dossier: URL) -> [String] {
        (FileManager.default.subpaths(atPath: dossier.path) ?? []).sorted()
    }

    // MARK: Pointeur et racine

    func testSansPointeurLaRacineEstLocale() throws {
        XCTAssertEqual(donnees.pointeur.lastPathComponent, "dossier-commun.json")
        XCTAssertEqual(donnees.pointeur.deletingLastPathComponent().path, racineLocale.path, "le pointeur est local")
        XCTAssertEqual(donnees.etat(), .local(racineLocale))
        XCTAssertEqual(try donnees.racine(), racineLocale)
        XCTAssertEqual(try donnees.url("guide-de-style.md"), racineLocale.appendingPathComponent("guide-de-style.md"))
    }

    func testPointeurValideDonneLeDossierCommun() throws {
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        try pointer(commun)
        XCTAssertEqual(donnees.etat(), .commun(commun.standardizedFileURL))
        XCTAssertEqual(try donnees.racine().path, commun.path)
        XCTAssertEqual(try Sens.racineIndex(donnees).path, commun.appendingPathComponent("Index").path)
        XCTAssertEqual(try Sens.dossierModeles(donnees).path, commun.appendingPathComponent("Modeles").path)
    }

    func testPointeurReluAChaqueAcces() throws {
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        XCTAssertEqual(try donnees.racine(), racineLocale)
        try pointer(commun)
        XCTAssertEqual(try donnees.racine().path, commun.path, "changé pendant que le serveur tourne : suivi tout de suite")
        try FileManager.default.removeItem(at: donnees.pointeur)
        XCTAssertEqual(try donnees.racine(), racineLocale, "« Revenir au dossier de ce Mac »")
    }

    func testPointeurIllisibleOuIncompletRestentLocaux() throws {
        for texte in ["pas du JSON", "{}", #"{"format":1}"#, #"{"format":1,"dossier":""}"#, #"{"format":1,"dossier":"   "}"#,
                      #"{"format":1,"dossier":"relatif/a/rien"}"#, #"{"format":2,"dossier":"/Volumes/Photos/X"}"#, #"{"format":1,"dossier":42}"#] {
            try ecrirePointeur(texte)
            XCTAssertEqual(donnees.etat(), .local(racineLocale), texte)
        }
        // Un dossier à la place du fichier : pas un pointeur.
        try FileManager.default.removeItem(at: donnees.pointeur)
        try FileManager.default.createDirectory(at: donnees.pointeur, withIntermediateDirectories: true)
        XCTAssertEqual(donnees.etat(), .local(racineLocale))
    }

    func testDossierCommunAbsentRefuseSansRepli() throws {
        try pointer(commun) // jamais créé : le SSD débranché
        XCTAssertEqual(donnees.etat(), .communAbsent(commun.standardizedFileURL))
        XCTAssertThrowsError(try donnees.racine()) { erreur in
            XCTAssertEqual(erreur.localizedDescription,
                           "Le dossier commun (\(commun.path)) est introuvable : branchez le SSD qui le contient, ou réglez un autre dossier "
                           + "dans Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom.")
        }
        XCTAssertThrowsError(try Sens.racineIndex(donnees))
        XCTAssertEqual(Sens.trouver(donnees: donnees).manquants, [DossierDonnees.texteIntrouvable(commun.path)])
        XCTAssertEqual(Especes.trouver(donnees: donnees).manquants, [DossierDonnees.texteIntrouvable(commun.path)])
    }

    // MARK: Rebasage

    func testRebasageDesCheminsEnregistres() {
        let racine = URL(fileURLWithPath: "/Volumes/Photos/Commun", isDirectory: true)
        XCTAssertEqual(DossierDonnees.rebaser("/Users/danymenard/Library/Application Support/Developpeur/Conversations/12/conversation.json", sur: racine),
                       "/Volumes/Photos/Commun/Conversations/12/conversation.json")
        XCTAssertEqual(DossierDonnees.rebaser("/Users/autre/Library/Application Support/Developpeur/Etapes/a/b.jpg", sur: racine),
                       "/Volumes/Photos/Commun/Etapes/a/b.jpg", "un autre nom d'utilisateur")
        XCTAssertEqual(DossierDonnees.rebaser("/Users/d/Library/Application Support/Developpeur/suivi-illisible-1700.json", sur: racine),
                       "/Volumes/Photos/Commun/suivi-illisible-1700.json")
        XCTAssertEqual(DossierDonnees.rebaser("/Users/d/Library/Application Support/Developpeur/Claude Code/abc.jsonl", sur: racine),
                       "/Volumes/Photos/Commun/Claude Code/abc.jsonl")
        // Ce qui reste local ne bouge pas.
        for local in ["/Users/d/Library/Application Support/Developpeur/Atelier/x", "/Users/d/Library/Application Support/Developpeur/liaison.jeton",
                      "/Users/d/Library/Application Support/Developpeur/Sessions/1", "/Users/d/Library/Application Support/Developpeur/dossier-commun.json",
                      "/Volumes/Photos/Lightroom/Catalogue.lrcat", "/Users/d/Library/Application Support/Developpeur/IndexAutre"] {
            XCTAssertEqual(DossierDonnees.rebaser(local, sur: racine), local)
        }
    }

    func testRebasageSurLaRacineActuelle() throws {
        let chemin = "/Users/autre/Library/Application Support/Developpeur/Etapes/1.jpg"
        XCTAssertEqual(try donnees.rebaser(chemin), racineLocale.appendingPathComponent("Etapes/1.jpg").path)
        try pointer(commun)
        XCTAssertThrowsError(try donnees.rebaser(chemin), "dossier commun absent : jamais rebasé sur ce Mac")
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        XCTAssertEqual(try donnees.rebaser(chemin), commun.appendingPathComponent("Etapes/1.jpg").path)
    }

    // MARK: Guide de style, rendus

    func testGuideDeStyleLuEtEcritDansLeDossierCommun() throws {
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        try "# Guide de style\n\n## Profils\n\n- Classic Chrome\n".write(to: commun.appendingPathComponent("guide-de-style.md"), atomically: true, encoding: .utf8)
        try "# Guide local\n".write(to: racineLocale.appendingPathComponent("guide-de-style.md"), atomically: true, encoding: .utf8)
        let guide = GuideStyle(donnees: donnees)
        XCTAssertEqual(try guide.lire(), "# Guide local\n", "sans pointeur : celui de ce Mac")
        try pointer(commun)
        XCTAssertTrue(try XCTUnwrap(guide.lire()).contains("Classic Chrome"), "le même guide sur les deux Mac")
        let tools = ToolHandler(lightroom: FakeLightroom(), guideStyle: guide)
        let lu = try JSONCoding.parse(tools.call(name: "remember_style", arguments: ["read": true]).text)
        XCTAssertEqual(lu["fichier"]?.string, commun.appendingPathComponent("guide-de-style.md").path)
        XCTAssertFalse(tools.call(name: "remember_style", arguments: ["preference": "Noirs denses", "category": "tone", "confirm": true]).isError)
        XCTAssertTrue(try String(contentsOf: commun.appendingPathComponent("guide-de-style.md"), encoding: .utf8).contains("Noirs denses"))
        XCTAssertEqual(try String(contentsOf: racineLocale.appendingPathComponent("guide-de-style.md"), encoding: .utf8), "# Guide local\n",
                       "le guide de ce Mac n'est pas touché")
    }

    func testGuideDeStyleRefuseQuandLeDossierCommunManque() throws {
        try "# Guide local\n".write(to: racineLocale.appendingPathComponent("guide-de-style.md"), atomically: true, encoding: .utf8)
        try pointer(commun)
        let avant = contenu(racineLocale.deletingLastPathComponent().deletingLastPathComponent())
        let tools = ToolHandler(lightroom: FakeLightroom(), guideStyle: GuideStyle(donnees: donnees))
        let lecture = tools.call(name: "remember_style", arguments: ["read": true])
        XCTAssertTrue(lecture.isError)
        XCTAssertTrue(lecture.text.contains("Le dossier commun (\(commun.path)) est introuvable"), lecture.text)
        let ajout = tools.call(name: "remember_style", arguments: ["preference": "Noirs denses", "category": "tone", "confirm": true])
        XCTAssertTrue(ajout.isError)
        XCTAssertTrue(ajout.text.contains("branchez le SSD"), ajout.text)
        XCTAssertEqual(contenu(racineLocale.deletingLastPathComponent().deletingLastPathComponent()), avant, "rien écrit nulle part")
        XCTAssertFalse(FileManager.default.fileExists(atPath: commun.path), "le dossier commun n'est pas recréé")
        // La ressource le dit aussi, et l'invite porte la note à la place du guide.
        XCTAssertTrue(tools.lireRessource(ToolHandler.ressourceGuide).isError)
        XCTAssertTrue(try XCTUnwrap(GuideStyle(donnees: donnees).pourInvite()).contains("introuvable"))
    }

    func testRendusDansLaRacineDesDonneesEtRefusSansDossierCommun() throws {
        try pointer(commun)
        let registre = RegistreRendus(donnees: donnees)
        let rendu = RegistreRendus.Rendu(photo: 7, le: Date(), reglages: ["Exposure2012": 0.3], profil: nil, retours: 0)
        XCTAssertThrowsError(try registre.noter(rendu)) { XCTAssertTrue($0 is DossierDonnees.DossierCommunIntrouvable) }
        XCTAssertEqual(contenu(racineLocale), ["dossier-commun.json"], "rien gardé sur ce Mac à la place")
        XCTAssertFalse(FileManager.default.fileExists(atPath: commun.path))
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        _ = try registre.noter(rendu)
        XCTAssertTrue(FileManager.default.fileExists(atPath: commun.appendingPathComponent("rendus.json").path))
        XCTAssertEqual(registre.lire()["7"]?.count, 1)
    }

    // MARK: Recherche par le sens

    func testRechercheParLeSensRefuseQuandLeDossierCommunManque() throws {
        try pointer(commun)
        let fake = FakeLightroom()
        fake.replies["etat"] = ["chemin_catalogue": "/C.lrcat"]
        let tools = ToolHandler(lightroom: fake)
        tools.sens = Suivi.IndexeurSens(donnees: donnees) { FauxEncodeur() }
        let resultat = tools.call(name: "find_photos", arguments: ["query": "a dog"])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("Le dossier commun (\(commun.path)) est introuvable"), resultat.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: commun.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: racineLocale.appendingPathComponent("Index").path), "aucun index sur ce Mac à la place")
        // --sens-etat : l'erreur, sans regles_sens.
        let etat = Suivi.etatSens(#"{"catalogue": "/C.lrcat"}"#, fichiers: (nil, Sens.trouver(donnees: donnees).manquants), donnees: donnees)
        XCTAssertNil(etat.ligne["regles_sens"])
        XCTAssertEqual(etat.ligne["manquants"]?.array?.first?.string, DossierDonnees.texteIntrouvable(commun.path))
    }

    func testIndexeurSensSuitLaRacineDesDonnees() throws {
        let sens = Suivi.IndexeurSens(donnees: donnees) { FauxEncodeur() }
        XCTAssertEqual(try sens.racine.path, racineLocale.appendingPathComponent("Index").path)
        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        try pointer(commun)
        XCTAssertEqual(try sens.racine.path, commun.appendingPathComponent("Index").path)
        XCTAssertEqual(try Suivi.IndexeurSens(racine: racineLocale) { FauxEncodeur() }.racine, racineLocale, "racine fixe des essais")
    }

    // MARK: get_status et --status

    func testGetStatusDitLEtatDuDossierCommun() throws {
        let fake = FakeLightroom()
        fake.replies["etat"] = ["module": "Développeur"]
        let tools = ToolHandler(lightroom: fake)
        XCTAssertNil(try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)["dossier_commun"],
                     "par défaut, le vrai pointeur n'est jamais lu")
        tools.dossierDonnees = donnees
        var bloc = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)["dossier_commun"]
        XCTAssertEqual(bloc?["regle"], false)
        XCTAssertEqual(bloc?["racine_des_donnees"]?.string, racineLocale.path)

        try pointer(commun)
        bloc = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)["dossier_commun"]
        XCTAssertEqual(bloc?["regle"], true)
        XCTAssertEqual(bloc?["present"], false)
        XCTAssertEqual(bloc?["chemin"]?.string, commun.path)
        XCTAssertEqual(bloc?["erreur"]?.string, DossierDonnees.texteIntrouvable(commun.path))
        XCTAssertTrue(donnees.ligneStatut().contains("ABSENT"))

        try FileManager.default.createDirectory(at: commun, withIntermediateDirectories: true)
        bloc = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)["dossier_commun"]
        XCTAssertEqual(bloc?["present"], true)
        XCTAssertEqual(bloc?["racine_des_donnees"]?.string, commun.path)
        XCTAssertEqual(donnees.ligneStatut(), "Dossier commun : \(commun.path) (présent)")
    }

    /// Le contrat avec le module : les éléments communs, et ceux qui restent locaux.
    func testElementsCommunsDuContrat() {
        for nom in ["guide-de-style.md", "Conversations", "suivi.json", "suivi.journal", "suivi-illisible-12.json", "carnet.json",
                    "carnet-illisible-3.json", "notation.json", "mes-demandes.json", "mes-demandes-illisible-4.json", "publication.json",
                    "consommation.json", "rendus.json", "Etapes", "Index", "Modeles", "Claude Code"] {
            XCTAssertTrue(DossierDonnees.estCommun(nom), nom)
        }
        for nom in ["mcp-developpeur", "liaison.jeton", "liaison.jeton.nouveau", "connecteur.json", "consignes.md", "Sessions",
                    "Atelier", "Temporaire", "dossier-commun.json", "Fibo"] {
            XCTAssertFalse(DossierDonnees.estCommun(nom), nom)
        }
    }
}
