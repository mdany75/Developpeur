import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Un faux BioCLIP (jamais le vrai modèle) : une image donne sa couleur moyenne (comme FauxEncodeur),
/// une phrase l'axe de son nom scientifique (rouge, vert, bleu), sinon le quatrième.
final class FauxBioCLIP: EncodeurSens {
    let modele = Especes.nomModele
    let dimension = 4
    var textes: [String] = []
    var images = 0
    let couleur = FauxEncodeur()

    func vecteur(image: CGImage) throws -> [Float] {
        images += 1
        return try couleur.vecteur(image: image)
    }

    func vecteur(texte: String) throws -> [Float] {
        textes.append(texte)
        if texte.contains("Cardinalis") { return [1, 0, 0, 0] }
        if texte.contains("Acer") { return [0, 1, 0, 0] }
        if texte.contains("Cyanocitta") { return [0, 0, 1, 0] }
        return [0, 0, 0, 1]
    }
}

/// Une fausse porte (MobileCLIP) : une image bleue ne montre « rien de vivant ».
final class FaussePorte: EncodeurSens {
    let modele = Sens.nomModele
    let dimension = 2
    func vecteur(image: CGImage) throws -> [Float] {
        let v = try FauxEncodeur().vecteur(image: image)
        return v[2] > 0.8 ? [0, 1] : [1, 0]
    }
    func vecteur(texte: String) throws -> [Float] {
        Especes.porteNature.contains(texte) ? [1, 0] : [0, 1]
    }
}

final class EspecesTests: XCTestCase {
    static let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var dossier: URL!

    static let petiteListe = """
    # essai
    oiseau\tCardinal rouge\tCardinalis cardinalis
    arbre\tÉrable à sucre\tAcer saccharum
    oiseau\tGeai bleu\tCyanocitta cristata
    champignon\tAmanite tue-mouches\tAmanita muscaria
    """

    override func setUp() {
        dossier = TestSupport.temporaryDirectory().appendingPathComponent("especes-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dossier)
    }

    // MARK: La liste du dépôt

    func testLaListeDuDepot() throws {
        let fichier = Self.racine.appendingPathComponent("Resources/especes/especes.tsv")
        let liste = try Especes.Liste(fichier: fichier)
        XCTAssertGreaterThan(liste.especes.count, 3000)
        XCTAssertGreaterThan(liste.especes.count, 3800)
        var latins = Set<String>(), noms = Set<String>()
        for e in liste.especes {
            XCTAssertTrue(Especes.groupesDeBase.contains(e.groupe), e.groupe)
            XCTAssertFalse(e.nom.isEmpty, e.latin)
            // Le nom scientifique : un genre en majuscule, puis au moins une épithète (ou un hybride ×).
            XCTAssertNotNil(e.latin.range(of: #"^[A-Z][a-zë]+( ×)? [a-z×][a-z\-]+( .+)?$"#, options: .regularExpression), e.latin)
            XCTAssertFalse(e.latin.contains("'"), "pas de cultivar : \(e.latin)")
            XCTAssertTrue(latins.insert(Especes.cle(e.latin)).inserted, "nom scientifique en double : \(e.latin)")
            XCTAssertTrue(noms.insert(Especes.cle(e.nom)).inserted, "nom français en double : \(e.nom)")
        }
        // Un nom français qui serait le nom scientifique d'une autre espèce (« Oryx beïsa » est le sien).
        let parLatin = Dictionary(liste.especes.enumerated().map { (Especes.cle($0.element.latin), $0.offset) }, uniquingKeysWith: { a, _ in a })
        for (i, e) in liste.especes.enumerated() {
            if let autre = parLatin[Especes.cle(e.nom)] { XCTAssertEqual(autre, i, "\(e.nom) est le nom scientifique d'une autre espèce") }
        }
        // Chaque groupe de base a ses espèces.
        for groupe in Especes.groupesDeBase {
            XCTAssertFalse(liste.especes.filter { $0.groupe == groupe }.isEmpty, groupe)
        }
        // Quelques espèces que Dany photographie, et leur nom.
        for (demande, latin) in [("Cardinal rouge", "Cardinalis cardinalis"), ("mesange a tete noire", "Poecile atricapillus"),
                                 ("Haliaeetus leucocephalus", "Haliaeetus leucocephalus"), ("Monarque", "Danaus plexippus"),
                                 ("érable à sucre", "Acer saccharum"), ("Trille blanc", "Trillium grandiflorum")] {
            guard case .espece(let i)? = liste.resoudre(demande) else { return XCTFail(demande) }
            XCTAssertEqual(liste.especes[i].latin, latin, demande)
        }
    }

    func testLaListeRefuseUneLigneMalFormee() {
        XCTAssertThrowsError(try Especes.Liste(contenu: "oiseau\tCardinal rouge\n"))
        XCTAssertThrowsError(try Especes.Liste(contenu: "dinosaure\tT. rex\tTyrannosaurus rex\n"), "groupe inconnu")
        XCTAssertEqual(try Especes.Liste(contenu: "# rien\n\n").especes.count, 0)
    }

    func testResoudreUneEspeceOuUnGroupe() throws {
        let liste = try Especes.Liste(contenu: Self.petiteListe)
        XCTAssertEqual(liste.resoudre("cardinal ROUGE"), .espece(0), "sans casse")
        XCTAssertEqual(liste.resoudre("Erable a sucre"), .espece(1), "sans accents")
        XCTAssertEqual(liste.resoudre("acer  saccharum"), .espece(1), "le nom scientifique, espaces uniformes")
        XCTAssertEqual(liste.resoudre("Amanite tue mouches"), .espece(3), "le trait d'union comme une espace")
        XCTAssertEqual(liste.resoudre("oiseaux"), .groupe(Especes.groupe(nom: "oiseau")!))
        XCTAssertEqual(liste.resoudre("birds"), .groupe(Especes.groupe(nom: "oiseau")!), "en anglais")
        XCTAssertNil(liste.resoudre("licorne"))
        XCTAssertEqual(liste.suggestions("cardinal"), ["Cardinal rouge (Cardinalis cardinalis)"])
        XCTAssertEqual(liste.indices(Especes.groupe(nom: "oiseau")!), [0, 2])
        XCTAssertEqual(liste.indices(Especes.groupe(nom: "plante")!), [1], "plante réunit fleur, arbre, arbuste")
        // Chaque groupe porte une phrase anglaise pour l'index du sens.
        for g in Especes.groupes { XCTAssertTrue(g.phrase.hasPrefix("a photo of "), g.nom) }
    }

    // MARK: Fichiers, cache et classement

    func testLesFichiersDuModele() throws {
        var trouves = Especes.trouver(modeles: dossier)
        XCTAssertNil(trouves.fichiers)
        XCTAssertEqual(trouves.manquants.count, 4)
        let fm = FileManager.default
        for nom in ["bioclip2_image.mlmodelc", "bioclip2_text.mlmodelc"] {
            try fm.createDirectory(at: dossier.appendingPathComponent(nom), withIntermediateDirectories: true)
        }
        fm.createFile(atPath: dossier.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz").path, contents: Data([0]))
        trouves = Especes.trouver(modeles: dossier)
        XCTAssertEqual(trouves.manquants.count, 1, "la liste manque")
        fm.createFile(atPath: dossier.appendingPathComponent("especes.tsv").path, contents: Data(Self.petiteListe.utf8))
        let fichiers = try XCTUnwrap(Especes.trouver(modeles: dossier).fichiers)
        XCTAssertEqual(fichiers.cache.deletingLastPathComponent().path, dossier.path)
        XCTAssertEqual(fichiers.sens.texte.lastPathComponent, "bioclip2_text.mlmodelc")
    }

    func testLesVecteursDeLaListeSeGardentEtSeRefont() throws {
        let cache = dossier.appendingPathComponent("Modeles/bioclip2_especes.cache")
        let liste = try Especes.Liste(contenu: Self.petiteListe)
        let encodeur = FauxBioCLIP()
        let premier = try Especes.vecteursTexte(liste: liste, encodeur: encodeur, cache: cache, empreinteModele: "m1")
        XCTAssertFalse(premier.depuisLeCache)
        XCTAssertEqual(encodeur.textes, liste.especes.map(Especes.phrase))
        XCTAssertEqual(encodeur.textes.first, "a photo of Cardinalis cardinalis.", "le nom scientifique dans le gabarit")
        XCTAssertEqual(premier.matrice.count, 4 * 4)
        // Relu : aucun calcul, les mêmes nombres (au 16 bits près).
        encodeur.textes = []
        let relu = try Especes.vecteursTexte(liste: liste, encodeur: encodeur, cache: cache, empreinteModele: "m1")
        XCTAssertTrue(relu.depuisLeCache)
        XCTAssertTrue(encodeur.textes.isEmpty)
        for (a, b) in zip(premier.matrice, relu.matrice) { XCTAssertEqual(a, b, accuracy: 0.001) }
        // Un autre modèle ou une autre liste : refaits.
        XCTAssertFalse(try Especes.vecteursTexte(liste: liste, encodeur: encodeur, cache: cache, empreinteModele: "m2").depuisLeCache)
        let autre = try Especes.Liste(contenu: Self.petiteListe + "\nfleur\tPissenlit\tTaraxacum officinale\n")
        let refait = try Especes.vecteursTexte(liste: autre, encodeur: encodeur, cache: cache, empreinteModele: "m2")
        XCTAssertFalse(refait.depuisLeCache)
        XCTAssertEqual(refait.matrice.count, 5 * 4)
        // Un fichier abîmé se refait sans erreur.
        try Data("abîmé".utf8).write(to: cache)
        XCTAssertFalse(try Especes.vecteursTexte(liste: autre, encodeur: encodeur, cache: cache, empreinteModele: "m2").depuisLeCache)
    }

    func testLEmpreinteDuModeleSuitSesFichiers() throws {
        let modele = dossier.appendingPathComponent("m.mlmodelc/weights")
        try FileManager.default.createDirectory(at: modele, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: modele.appendingPathComponent("weight.bin"))
        let avant = Especes.empreinteModele(modele.deletingLastPathComponent())
        XCTAssertEqual(avant, Especes.empreinteModele(modele.deletingLastPathComponent()))
        try Data("abc".utf8).write(to: modele.appendingPathComponent("weight.bin"))
        XCTAssertNotEqual(avant, Especes.empreinteModele(modele.deletingLastPathComponent()))
    }

    func classeur(porte: EncodeurSens? = nil) throws -> ClasseurEspeces {
        try ClasseurEspeces.ouvrir(liste: try Especes.Liste(contenu: Self.petiteListe), encodeur: FauxBioCLIP(),
                                   cache: dossier.appendingPathComponent("cache"), empreinteModele: "m", porte: porte)
    }

    func image(rouge: UInt8, vert: UInt8, bleu: UInt8) throws -> CGImage {
        try XCTUnwrap(PreviewImages.image(TestSupport.jpeg(red: rouge, green: vert, blue: bleu)))
    }

    func testLeClassementDUneImage() throws {
        let c = try classeur()
        let rouge = try c.classer(image: try image(rouge: 230, vert: 20, bleu: 20))
        XCTAssertEqual(rouge.probabilites.reduce(0, +), 1, accuracy: 1e-6)
        XCTAssertEqual(rouge.meilleures(1).first?.indice, 0, "le cardinal")
        XCTAssertGreaterThan(try XCTUnwrap(rouge.meilleures(1).first?.probabilite), 0.9)
        XCTAssertNil(rouge.nature, "sans porte")
        let bloc = c.json(rouge)
        XCTAssertEqual(bloc["trouvee"], true)
        XCTAssertEqual(bloc["nom"], "Cardinal rouge")
        XCTAssertEqual(bloc["latin"], "Cardinalis cardinalis")
        XCTAssertEqual(bloc["groupe"], "oiseau")
        // Un groupe : la somme de ses espèces.
        XCTAssertGreaterThan(rouge.somme(c.liste.indices(Especes.groupe(nom: "oiseau")!)), 0.9)
        // Une image grise : tout se partage, rien ne passe le seuil.
        let grise = try c.classer(image: try image(rouge: 128, vert: 128, bleu: 128))
        let incertaine = c.json(grise)
        XCTAssertEqual(incertaine["trouvee"], false)
        XCTAssertNotNil(incertaine["plus_proches"])
        XCTAssertTrue(incertaine["remarque"]?.string?.contains("pas proposer") == true)
    }

    func testLaPorteEcarteUneImageSansAnimalNiPlante() throws {
        let c = try classeur(porte: FaussePorte())
        let rouge = try c.classer(image: try image(rouge: 230, vert: 20, bleu: 20))
        XCTAssertEqual(try XCTUnwrap(rouge.nature), 1, accuracy: 0.01)
        XCTAssertEqual(c.json(rouge)["trouvee"], true)
        // Bleue : le geai bleu pour BioCLIP, mais « rien de vivant » pour la porte.
        let bleue = try c.classer(image: try image(rouge: 20, vert: 20, bleu: 230))
        XCTAssertEqual(bleue.meilleures(1).first?.indice, 2)
        XCTAssertFalse(bleue.vivant)
        let bloc = c.json(bleue)
        XCTAssertEqual(bloc["trouvee"], false)
        XCTAssertNil(bloc["nom"])
    }

    // MARK: Outils

    /// `totalSansParmi` : le total que rendent les autres critères seuls (sinon les 4 photos).
    func outils(_ lightroom: FakeLightroom, avecIndex: Bool = true, porte: EncodeurSens? = nil, totalSansParmi: Int? = nil) throws -> ToolHandler {
        let tools = ToolHandler(lightroom: lightroom)
        let c = try classeur(porte: porte)
        tools.especes = ToolHandler.MoteurEspeces { c }
        lightroom.replies["etat"] = ["chemin_catalogue": "/C.lrcat"]
        if avecIndex {
            let index = try IndexSens(ecrire: IndexSens.dossier(catalogue: "/C.lrcat", racine: dossier), modele: Sens.nomModele, dimension: 4)
            for id in 1...4 { try index.ranger(uuid: "u\(id)", id: id, jour: "2020-0\(id)-01", vecteur: Sens.normaliser([1, 0, 0, Float(id) * 0.1])) }
            tools.sens = Suivi.IndexeurSens(racine: dossier) { FauxEncodeur() }
        }
        // Les vignettes : 1 rouge (cardinal), 2 verte (érable), 3 bleue (geai), 4 rouge.
        let couleurs: [Int: (UInt8, UInt8, UInt8)] = [1: (230, 20, 20), 2: (20, 230, 20), 3: (20, 20, 230), 4: (220, 30, 30)]
        lightroom.onSend = { [dossier] commande, params in
            switch commande {
            case "chercher":
                let ids = (params["parmi"]?.array ?? [1, 2, 3, 4]).compactMap(\.int)
                let total = params["parmi"] == nil ? (totalSansParmi ?? ids.count) : ids.count
                var reponse: [String: JSONValue] = ["total": .number(Double(total)),
                                                   "photos": .array(ids.map { ["id": .number(Double($0)), "fichier": .string("P\($0).RAF")] })]
                if params["parmi"] != nil { reponse["parmi"] = true }
                lightroom.replies["chercher"] = .object(reponse)
            case "vignettes":
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                lightroom.replies["vignettes"] = ["photos": .array(ids.map { id in
                    let fichier = dossier!.appendingPathComponent("v\(id)-\(UUID().uuidString).jpg")
                    let c = couleurs[id] ?? (128, 128, 128)
                    try? TestSupport.jpeg(red: c.0, green: c.1, blue: c.2).write(to: fichier)
                    return ["id": .number(Double(id)), "vignette": .string(fichier.path)]
                })]
            default: break
            }
        }
        return tools
    }

    func testFindPhotosParEspeceAvecLIndexDuSens() throws {
        let lightroom = FakeLightroom()
        // Les autres critères gardent trop de photos : l'index les classe.
        let tools = try outils(lightroom, totalSansParmi: 5000)
        let result = tools.call(name: "find_photos", arguments: ["species": "Cardinal rouge", "rating_min": 2, "date_from": "2020-02-01"])
        XCTAssertFalse(result.isError, result.text)
        let appels = lightroom.calls.filter { $0.command == "chercher" }
        XCTAssertEqual(appels.count, 2, "les autres critères seuls, puis parmi l'index")
        XCTAssertNil(appels[0].params["parmi"])
        let chercher = appels[1].params
        XCTAssertEqual(chercher["note_min"], 2, "les autres critères au module")
        XCTAssertEqual(chercher["limite"]?.int, Especes.candidatsMax)
        XCTAssertNil(chercher["date_debut"], "les dates filtrées d'après l'index")
        XCTAssertEqual(Set(try XCTUnwrap(chercher["parmi"]?.array).compactMap(\.int)), [2, 3, 4], "la photo 1 est d'avant la date")
        let vignettes = try XCTUnwrap(lightroom.calls.first { $0.command == "vignettes" }?.params)
        XCTAssertEqual(vignettes["taille"]?.int, Especes.tailleVignette)
        let structure = try XCTUnwrap(result.structured)
        let photos = try XCTUnwrap(structure["photos"]?.array)
        XCTAssertEqual(photos.compactMap { $0["id"]?.int }, [4], "seul le rouge est un cardinal")
        XCTAssertEqual(photos.first?["espece"]?["nom"], "Cardinal rouge")
        XCTAssertNotNil(photos.first?["score"])
        XCTAssertEqual(structure["total"], 1)
        XCTAssertEqual(structure["especes"]?["examinees"], 3)
        XCTAssertNil(structure["parmi"])
        let remarques = (structure["remarques"]?.array ?? []).compactMap(\.string)
        XCTAssertTrue(remarques.contains { $0.contains("pas encore vues") && $0.contains("5000 photos des autres critères") }, "\(remarques)")
        XCTAssertTrue(remarques.contains { $0.contains("MobileCLIP") }, "sans porte, la réponse le dit : \(remarques)")
        XCTAssertEqual(structure["especes"]?["porte"], false)
        XCTAssertFalse(result.text.contains("/C.lrcat"), "le chemin du catalogue ne part pas chez Claude")
        // Les vignettes lues sont effacées.
        let restantes = try FileManager.default.contentsOfDirectory(atPath: dossier.path).filter { $0.hasSuffix(".jpg") }
        XCTAssertTrue(restantes.isEmpty, "\(restantes)")
        // Rien n'est écrit.
        XCTAssertTrue(lightroom.commands.allSatisfy { ["etat", "chercher", "vignettes"].contains($0) }, "\(lightroom.commands)")
    }

    /// Constat de relecture : avec l'index, une collection de peu de photos était limitée aux 2 000
    /// photos indexées les plus proches du groupe dans tout le catalogue ; ses photos pas encore
    /// analysées n'étaient jamais examinées. Toutes le sont désormais, sans l'index.
    func testUneCollectionDePeuDePhotosEstExamineeEntiere() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        let result = tools.call(name: "find_photos", arguments: ["species": "oiseau", "collection": "Costa Rica"])
        XCTAssertFalse(result.isError, result.text)
        let appels = lightroom.calls.filter { $0.command == "chercher" }
        XCTAssertEqual(appels.count, 1)
        XCTAssertNil(appels[0].params["parmi"], "pas de présélection par l'index")
        XCTAssertEqual(result.structured?["especes"]?["examinees"], 4)
        XCTAssertFalse(lightroom.commands.contains("etat"), "l'index n'est pas ouvert")
    }

    /// Sans autre critère, l'index classe tout le catalogue et la réponse dit que les photos pas
    /// encore analysées ne sont pas examinées.
    func testSansAutreCritereLIndexDitCeQuIlNeVoitPas() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom, porte: FaussePorte())
        let result = tools.call(name: "find_photos", arguments: ["species": "oiseau"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(Set(try XCTUnwrap(lightroom.calls.first { $0.command == "chercher" }?.params["parmi"]?.array).compactMap(\.int)), [1, 2, 3, 4])
        let remarques = (result.structured?["remarques"]?.array ?? []).compactMap(\.string)
        XCTAssertTrue(remarques.contains { $0.contains("pas encore vues") && $0.contains("4 dans l'index") }, "\(remarques)")
        XCTAssertFalse(remarques.contains { $0.contains("MobileCLIP") }, "avec la porte, rien à dire")
        XCTAssertEqual(result.structured?["especes"]?["porte"], true)
    }

    func testLInvertebreSeChercheAussiParLesEscargots() {
        let groupe = Especes.groupe(nom: "invertébré")!
        XCTAssertTrue(groupe.phrases.contains("a photo of a sea creature"))
        XCTAssertTrue(groupe.phrases.contains("a photo of a snail"))
        XCTAssertTrue(groupe.phrases.contains("a photo of an insect"))
    }

    func testFindPhotosParGroupeSansIndexDemandeUnAutreCritere() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom, avecIndex: false)
        let refus = tools.call(name: "find_photos", arguments: ["species": "oiseau"])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("autre critère"), refus.text)
        XCTAssertFalse(lightroom.commands.contains("vignettes"))
        let result = tools.call(name: "find_photos", arguments: ["species": "oiseaux", "collection": "Vacances"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertNil(lightroom.calls.last { $0.command == "chercher" }?.params["parmi"])
        XCTAssertEqual(lightroom.calls.last { $0.command == "chercher" }?.params["collection"], "Vacances")
        let ids = try XCTUnwrap(result.structured?["photos"]?.array).compactMap { $0["id"]?.int }
        XCTAssertEqual(Set(ids), [1, 3, 4], "cardinaux et geai : des oiseaux ; l'érable non")
    }

    func testLaPorteEcarteDesPhotosDeLaRecherche() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom, avecIndex: false, porte: FaussePorte())
        let result = tools.call(name: "find_photos", arguments: ["species": "oiseau", "folder": "/P"])
        let ids = try XCTUnwrap(result.structured?["photos"]?.array).compactMap { $0["id"]?.int }
        XCTAssertEqual(Set(ids), [1, 4], "la bleue : rien de vivant pour la porte")
    }

    func testUneEspeceInconnueEstRefuseeAvecDesNomsProches() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        let result = tools.call(name: "find_photos", arguments: ["species": "Cardinal"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Cardinal rouge (Cardinalis cardinalis)"), result.text)
        XCTAssertFalse(lightroom.commands.contains("chercher"))
        XCTAssertTrue(tools.call(name: "find_photos", arguments: ["species": "oiseau", "query": "bird"]).isError, "pas avec query")
    }

    func testSansLeModeleToutMarcheCommeAvant() throws {
        let lightroom = FakeLightroom()
        lightroom.replies["etat"] = ["chemin_catalogue": "/C.lrcat"]
        let tools = ToolHandler(lightroom: lightroom)
        let refus = tools.call(name: "find_photos", arguments: ["species": "oiseau", "rating_min": 3])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("BioCLIP 2 absent"), refus.text)
        XCTAssertTrue(lightroom.commands.isEmpty, "rien ne part")
        // get_status : rien sans moteur ; avec un moteur sans modèle, ce qui manque.
        XCTAssertFalse(tools.call(name: "get_status", arguments: [:]).text.contains("\"especes\""))
        tools.especes = ToolHandler.MoteurEspeces(manquants: { ["bioclip2_image.mlmodelc"] }) { throw LightroomError.invalid("absent") }
        let etat = try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)
        XCTAssertEqual(etat["especes"]?["installee"], false)
        XCTAssertEqual(etat["especes"]?["manquants"], ["bioclip2_image.mlmodelc"])
        // Une recherche sans species ne touche pas aux espèces.
        _ = tools.call(name: "find_photos", arguments: ["rating_min": 3])
        XCTAssertNil(lightroom.lastParams["parmi"])
    }

    func testViewPhotoDitLEspeceSurDemande() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom, avecIndex: false)
        func apercu() throws {
            let fichier = dossier.appendingPathComponent("apercu-\(UUID().uuidString).jpg")
            try TestSupport.jpeg(red: 230, green: 20, blue: 20, width: 600, height: 400).write(to: fichier)
            lightroom.replies["apercu"] = ["chemin": .string(fichier.path), "photo": ["id": 7, "fichier": "P7.JPG"]]
        }
        try apercu()
        let sans = try JSONCoding.parse(tools.call(name: "view_photo", arguments: ["photo_id": 7]).text)
        XCTAssertNil(sans["espece"], "seulement sur demande")
        try apercu()
        let avec = try JSONCoding.parse(tools.call(name: "view_photo", arguments: ["photo_id": 7, "species": true]).text)
        XCTAssertEqual(avec["espece"]?["nom"], "Cardinal rouge")
        XCTAssertEqual(avec["espece"]?["modele"], .string(Especes.nomModele))
        XCTAssertTrue(avec["espece"]?["remarque"]?.string?.contains("accord") == true)
        // Constat de relecture : l'aperçu 3:2 n'est lu que sur son carré central, et la réponse le dit.
        XCTAssertEqual(avec["espece"]?["lu_sur"], "carré central")
        XCTAssertTrue(avec["espece"]?["remarque"]?.string?.contains("region") == true)
        XCTAssertTrue(avec["espece"]?["remarque"]?.string?.contains("MobileCLIP") == true, "sans porte, dit")
        // Sans le modèle : dit, sans erreur.
        tools.especes = nil
        try apercu()
        let absent = tools.call(name: "view_photo", arguments: ["photo_id": 7, "species": true])
        XCTAssertFalse(absent.isError)
        XCTAssertEqual(try JSONCoding.parse(absent.text)["espece"]?["trouvee"], false)
    }

    // MARK: Descriptions

    func testLesDescriptionsRestentCourtes() throws {
        let definitions = ToolHandler(lightroom: FakeLightroom()).definitions
        let find = try XCTUnwrap(definitions.first { $0["name"] == "find_photos" })
        let species = try XCTUnwrap(find["inputSchema"]?["properties"]?["species"]?["description"]?.string)
        XCTAssertLessThanOrEqual(species.utf16.count, 450, "\(species.utf16.count)")
        XCTAssertTrue(species.contains("provisoires"))
        XCTAssertTrue(try XCTUnwrap(find["description"]?.string).contains("species"))
        let vue = try XCTUnwrap(definitions.first { $0["name"] == "view_photo" })
        let especeVue = try XCTUnwrap(vue["inputSchema"]?["properties"]?["species"]?["description"]?.string)
        XCTAssertLessThanOrEqual(especeVue.utf16.count, 350, "\(especeVue.utf16.count)")
        XCTAssertTrue(especeVue.contains("accord"), "un mot-clé d'espèce seulement avec l'accord")
        // Les collections dynamiques n'ont pas les espèces (Lightroom ne les connaît pas).
        let collections = try XCTUnwrap(definitions.first { $0["name"] == "manage_collections" })
        XCTAssertNil(collections["inputSchema"]?["properties"]?["search"]?["properties"]?["species"])
    }

    /// Le tokeniseur de BioCLIP 2 est celui de CLIP (constaté par scripts/preparer-bioclip.sh, qui a
    /// écrit Tests/Contrats/jetons-bioclip.json avec open_clip) : TokeniseurCLIP rend les mêmes jetons.
    func testLeTokeniseurDeBioCLIPEstCeluiDeCLIP() throws {
        let t = try TokeniseurCLIP(vocabulaire: Self.racine.appendingPathComponent("Resources/clip/bpe_simple_vocab_16e6.txt.gz"))
        let contrat = try JSONCoding.parse(String(contentsOf: Self.racine.appendingPathComponent("Tests/Contrats/jetons-bioclip.json"), encoding: .utf8))
        let phrases = try XCTUnwrap(contrat["phrases"]?.array)
        XCTAssertGreaterThanOrEqual(phrases.count, 8)
        for phrase in phrases {
            let texte = try XCTUnwrap(phrase["texte"]?.string)
            let attendus = try XCTUnwrap(phrase["jetons"]?.array).compactMap { $0.int.map(Int32.init) }
            XCTAssertEqual(t.jetons(texte).filter { $0 != 0 }, attendus, texte)
        }
    }
}
