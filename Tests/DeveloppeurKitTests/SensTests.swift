import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Un faux encodeur (jamais le vrai MobileCLIP) : une image donne sa couleur moyenne (rouge, vert,
/// bleu, et un peu d'une quatrième composante), un texte l'axe de son mot (« red », « green »,
/// « blue », sinon le quatrième).
final class FauxEncodeur: EncodeurSens {
    let modele: String
    let dimension = 4
    var textes: [String] = []
    var images = 0
    /// Le temps d'une image (une empreinte en retard).
    var attenteImage: TimeInterval = 0
    init(modele: String = Sens.nomModele) { self.modele = modele }

    func vecteur(image: CGImage) throws -> [Float] {
        images += 1
        if attenteImage > 0 { Thread.sleep(forTimeInterval: attenteImage) }
        var pixel = [UInt8](repeating: 0, count: 4)
        let contexte = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        contexte.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Sens.normaliser([Float(pixel[0]), Float(pixel[1]), Float(pixel[2]), 10])
    }

    func vecteur(texte: String) throws -> [Float] {
        textes.append(texte)
        if texte.contains("red") { return [1, 0, 0, 0] }
        if texte.contains("green") { return [0, 1, 0, 0] }
        if texte.contains("blue") { return [0, 0, 1, 0] }
        return [0, 0, 0, 1]
    }
}

final class SensTests: XCTestCase {
    var dossier: URL!

    override func setUp() {
        dossier = TestSupport.temporaryDirectory().appendingPathComponent("sens-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dossier)
    }

    // MARK: Index

    func testLIndexRangeClasseEtRelit() throws {
        let index = try IndexSens(ecrire: dossier.appendingPathComponent("i"), modele: "m", dimension: 4, catalogue: "/C.lrcat")
        try index.ranger(uuid: "u1", id: 1, jour: "2019-07-14 18:30", vecteur: Sens.normaliser([1, 0, 0, 0]))
        try index.ranger(uuid: "u2", id: 2, jour: nil, vecteur: Sens.normaliser([0.8, 0.6, 0, 0]))
        try index.ranger(uuid: "u3", id: 3, jour: "2020-01-01", vecteur: Sens.normaliser([0, 0, 1, 0]))
        XCTAssertEqual(index.nombre, 3)
        XCTAssertEqual(index.lignes().map(\.jour), ["2019-07-14", nil, "2020-01-01"], "le jour seul")
        let classees = index.classer([1, 0, 0, 0])
        XCTAssertEqual(classees.map(\.ligne.id), [1, 2, 3])
        XCTAssertEqual(classees[0].score, 1, accuracy: 0.001)
        XCTAssertEqual(classees[1].score, 0.8, accuracy: 0.001, "en 16 bits, au millième")
        XCTAssertEqual(try XCTUnwrap(index.vecteur(id: 2))[1], 0.6, accuracy: 0.001)
        // Relu par un autre lecteur.
        let lu = try XCTUnwrap(IndexSens(lire: dossier.appendingPathComponent("i")))
        XCTAssertEqual(lu.modele, "m")
        XCTAssertEqual(lu.dimension, 4)
        XCTAssertEqual(lu.nombre, 3)
        XCTAssertEqual(lu.meta["catalogue"], "/C.lrcat")
        XCTAssertEqual(lu.classer([0, 0, 1, 0]).first?.ligne.id, 3)
        XCTAssertNotNil(lu.derniere)
    }

    func testLaMemePhotoGardeSaPlaceEtUneAutreSousLeMemeIdSort() throws {
        let index = try IndexSens(ecrire: dossier, modele: "m", dimension: 4)
        try index.ranger(uuid: "u1", id: 1, jour: nil, vecteur: [1, 0, 0, 0])
        try index.ranger(uuid: "u2", id: 2, jour: nil, vecteur: [0, 1, 0, 0])
        try index.ranger(uuid: "u1", id: 1, jour: "2021-05-05", vecteur: [0, 0, 1, 0])
        XCTAssertEqual(index.nombre, 2)
        XCTAssertEqual(index.lignes().first { $0.uuid == "u1" }?.rang, 0, "sa place gardée")
        XCTAssertEqual(index.classer([0, 0, 1, 0]).first?.ligne.id, 1, "son vecteur remplacé")
        // Une autre photo sous l'id 2 (l'ancienne retirée du catalogue) : l'ancienne sort.
        try index.ranger(uuid: "u9", id: 2, jour: nil, vecteur: [0, 0, 0, 1])
        XCTAssertEqual(index.lignes().filter { $0.id == 2 }.map(\.uuid), ["u9"])
        XCTAssertThrowsError(try index.ranger(uuid: "u5", id: 5, jour: nil, vecteur: [1, 0]), "une autre dimension")
    }

    func testUnIndexDUnAutreModeleSeRefait() throws {
        let a = try IndexSens(ecrire: dossier, modele: "ancien", dimension: 4)
        try a.ranger(uuid: "u1", id: 1, jour: nil, vecteur: [1, 0, 0, 0])
        let b = try IndexSens(ecrire: dossier, modele: "nouveau", dimension: 4)
        XCTAssertEqual(b.nombre, 0)
        XCTAssertNil(IndexSens(lire: dossier.appendingPathComponent("absent")))
    }

    func testLeDossierDUnCatalogue() {
        let racine = URL(fileURLWithPath: "/r")
        XCTAssertEqual(IndexSens.dossier(catalogue: "/A.lrcat", racine: racine), IndexSens.dossier(catalogue: "/A.lrcat", racine: racine))
        XCTAssertNotEqual(IndexSens.dossier(catalogue: "/A.lrcat", racine: racine), IndexSens.dossier(catalogue: "/B.lrcat", racine: racine))
        XCTAssertEqual(Sens.empreinte(catalogue: "/A.lrcat").count, 24)
    }

    // MARK: Fichiers du modèle

    func testLesFichiersDuModele() throws {
        let fm = FileManager.default
        let modeles = dossier.appendingPathComponent("Modeles"), cache = dossier.appendingPathComponent("hub")
        var trouves = Sens.trouver(modeles: modeles, cache: cache)
        XCTAssertNil(trouves.fichiers)
        XCTAssertEqual(trouves.manquants.count, 3)
        let instantane = cache.appendingPathComponent("models--apple--coreml-mobileclip/snapshots/abc")
        for nom in ["mobileclip_s2_image.mlpackage", "mobileclip_s2_text.mlpackage"] {
            try fm.createDirectory(at: instantane.appendingPathComponent(nom), withIntermediateDirectories: true)
        }
        trouves = Sens.trouver(modeles: modeles, cache: cache)
        XCTAssertNil(trouves.fichiers, "le vocabulaire manque")
        XCTAssertEqual(trouves.manquants.count, 1)
        try fm.createDirectory(at: modeles, withIntermediateDirectories: true)
        fm.createFile(atPath: modeles.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz").path, contents: Data([0]))
        trouves = Sens.trouver(modeles: modeles, cache: cache)
        XCTAssertEqual(trouves.fichiers?.image.lastPathComponent, "mobileclip_s2_image.mlpackage")
        // Une copie compilée passe avant le paquet.
        try fm.createDirectory(at: modeles.appendingPathComponent("mobileclip_s2_image.mlmodelc"), withIntermediateDirectories: true)
        XCTAssertEqual(Sens.trouver(modeles: modeles, cache: cache).fichiers?.image.lastPathComponent, "mobileclip_s2_image.mlmodelc")
    }

    // MARK: --analyser et --sens-etat

    func vignette(_ nom: String, rouge: UInt8, vert: UInt8, bleu: UInt8) throws -> String {
        let chemin = dossier.appendingPathComponent(nom)
        try TestSupport.jpeg(red: rouge, green: vert, blue: bleu, width: 1024, height: 683).write(to: chemin)
        return chemin.path
    }

    func testAnalyserRangeLEmpreinteDansLIndexDuCatalogue() throws {
        let rouge = try vignette("1.jpg", rouge: 230, vert: 20, bleu: 20)
        let bleu = try vignette("2.jpg", rouge: 20, vert: 20, bleu: 230)
        let encodeur = FauxEncodeur()
        let sens = Suivi.IndexeurSens(racine: dossier) { encodeur }
        var mesurees: [Int] = []
        let mesurer: (Suivi.AAnalyser) -> JSONValue = { p in
            mesurees.append(p.id)
            return ["id": .number(Double(p.id)), "cherches": [], "defauts": [], "genre": "autre", "mesures": [:]]
        }
        let entree: JSONValue = ["catalogue": "/Volumes/Photos/C.lrcat", "photos": [
            ["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1", "date": "2019-07-14 18:30"],
            ["id": 2, "vignette": .string(bleu), "cache": true, "uuid": "U2", "sens_seul": true],
            ["id": 3, "vignette": .string(bleu), "cache": true],
        ]]
        let reponse = Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer, sens: sens)
        XCTAssertEqual(reponse.code, 0)
        XCTAssertEqual(reponse.ligne["regles_sens"]?.int, Sens.regles)
        let photos = try XCTUnwrap(reponse.ligne["photos"]?.array)
        XCTAssertEqual(photos[0]["sens"], true)
        XCTAssertEqual(photos[0]["genre"], "autre", "l'analyse entière")
        XCTAssertEqual(photos[1], ["id": 2, "sens": true], "l'empreinte seule")
        XCTAssertNil(photos[2]["sens"], "sans uuid : pas d'empreinte")
        XCTAssertEqual(mesurees.sorted(), [1, 3], "sens_seul : aucune mesure")
        let index = try XCTUnwrap(IndexSens(lire: IndexSens.dossier(catalogue: "/Volumes/Photos/C.lrcat", racine: dossier)))
        XCTAssertEqual(index.nombre, 2)
        XCTAssertEqual(index.lignes().first { $0.id == 1 }?.jour, "2019-07-14")
        XCTAssertEqual(index.classer(try encodeur.vecteur(texte: "red")).first?.ligne.id, 1)
        XCTAssertEqual(index.classer(try encodeur.vecteur(texte: "blue")).first?.ligne.id, 2)
    }

    func testAnalyserSansSensResteCeluiDAvant() throws {
        let rouge = try vignette("1.jpg", rouge: 230, vert: 20, bleu: 20)
        let mesurer: (Suivi.AAnalyser) -> JSONValue = { p in ["id": .number(Double(p.id)), "cherches": [], "defauts": [], "genre": "autre", "mesures": [:]] }
        let entree: JSONValue = ["catalogue": "/C.lrcat", "photos": [
            ["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1"],
            ["id": 2, "vignette": .string(rouge), "cache": true, "uuid": "U2", "sens_seul": true],
        ]]
        // Sans le modèle : ni regles_sens ni sens ; l'empreinte seule a sa raison.
        var reponse = Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer)
        XCTAssertEqual(Set(reponse.ligne.object?.keys.map { $0 } ?? []), ["ok", "regles", "regles_genre", "photos"])
        XCTAssertNil(reponse.ligne["photos"]?.array?.first?["sens"])
        XCTAssertEqual(reponse.ligne["photos"]?.array?.last?["raison"], "sens_absent")
        // Avec le modèle mais sans catalogue : de même.
        let sansCatalogue: JSONValue = ["photos": [["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1"]]]
        reponse = Suivi.analyser(JSONCoding.line(sansCatalogue), mesurer: mesurer, sens: Suivi.IndexeurSens(racine: dossier) { FauxEncodeur() })
        XCTAssertNil(reponse.ligne["regles_sens"])
        // Un encodeur qui ne s'ouvre pas : ni regles_sens (le module n'en demande plus de la séance, au
        // lieu de remettre toute la bibliothèque en file à chaque séance), ni raison par photo
        // analysée ; l'erreur dite dans la ligne ; l'empreinte seule a sa raison.
        reponse = Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer,
                                 sens: Suivi.IndexeurSens(racine: dossier) { throw LightroomError.invalid("modèle cassé") })
        XCTAssertNil(reponse.ligne["regles_sens"], "pas annoncé sans encodeur")
        XCTAssertNil(reponse.ligne["index_sens"])
        XCTAssertEqual(reponse.ligne["sens_erreur"], "modèle cassé")
        XCTAssertNil(reponse.ligne["photos"]?.array?.first?["sens_raison"])
        XCTAssertEqual(reponse.ligne["photos"]?.array?.first?["genre"], "autre", "les défauts mesurés quand même")
        XCTAssertEqual(reponse.ligne["photos"]?.array?.last?["raison"], "sens")
        // Les types de l'entrée.
        reponse = Suivi.analyser(#"{"catalogue": 3, "photos": [{"id": 1, "vignette": "/x.jpg"}]}"#, mesurer: mesurer)
        XCTAssertEqual(reponse.code, 1)
        reponse = Suivi.analyser(#"{"photos": [{"id": 1, "vignette": "/x.jpg", "uuid": 4}]}"#, mesurer: mesurer)
        XCTAssertEqual(reponse.code, 1)
    }

    func testLOuvertureDuModeleSeFaitHorsDuDelaiDesPhotos() throws {
        let rouge = try vignette("1.jpg", rouge: 230, vert: 20, bleu: 20)
        let mesurer: (Suivi.AAnalyser) -> JSONValue = { p in ["id": .number(Double(p.id)), "cherches": [], "defauts": [], "genre": "autre", "mesures": [:]] }
        let entree: JSONValue = ["catalogue": "/C.lrcat", "photos": [
            ["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1"],
            ["id": 2, "vignette": .string(rouge), "cache": true, "uuid": "U2"],
        ]]
        // Une ouverture (chargement du modèle) plus longue que le délai d'une photo : les photos ne la paient pas.
        let lent = Suivi.IndexeurSens(racine: dossier) { Thread.sleep(forTimeInterval: 0.6); return FauxEncodeur() }
        var reponse = Suivi.analyser(JSONCoding.line(entree), delaiParPhoto: 0.3, delaiTotal: 5, delaiOuverture: 3, mesurer: mesurer, sens: lent)
        XCTAssertEqual(reponse.ligne["regles_sens"]?.int, Sens.regles)
        for photo in try XCTUnwrap(reponse.ligne["photos"]?.array) {
            XCTAssertNil(photo["raison"], "\(photo)")
            XCTAssertEqual(photo["sens"], true)
        }
        // Plus longue que son propre délai : sans l'empreinte, ni regles_sens ; les défauts mesurés.
        let tropLent = Suivi.IndexeurSens(racine: dossier) { Thread.sleep(forTimeInterval: 1); return FauxEncodeur() }
        reponse = Suivi.analyser(JSONCoding.line(entree), delaiParPhoto: 0.3, delaiTotal: 5, delaiOuverture: 0.1, mesurer: mesurer, sens: tropLent)
        XCTAssertNil(reponse.ligne["regles_sens"])
        XCTAssertTrue(reponse.ligne["sens_erreur"]?.string?.contains("ne s'est pas ouvert") == true)
        XCTAssertEqual(reponse.ligne["photos"]?.array?.compactMap { $0["genre"]?.string }, ["autre", "autre"])
    }

    func testUneEmpreinteEnRetardNeFaitPasPerdreLesDefauts() throws {
        let rouge = try vignette("1.jpg", rouge: 230, vert: 20, bleu: 20)
        let mesurer: (Suivi.AAnalyser) -> JSONValue = { p in ["id": .number(Double(p.id)), "cherches": ["flou"], "defauts": ["flou"], "genre": "autre", "mesures": [:]] }
        let encodeur = FauxEncodeur()
        encodeur.attenteImage = 0.8
        let entree: JSONValue = ["catalogue": "/C.lrcat", "photos": [["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1"]]]
        let reponse = Suivi.analyser(JSONCoding.line(entree), delaiParPhoto: 0.3, delaiTotal: 5, mesurer: mesurer,
                                     sens: Suivi.IndexeurSens(racine: dossier) { encodeur })
        let photo = try XCTUnwrap(reponse.ligne["photos"]?.array?.first)
        XCTAssertNil(photo["raison"], "les défauts gardés : \(photo)")
        XCTAssertEqual(photo["defauts"], ["flou"])
        XCTAssertEqual(photo["sens_raison"], "delai", "seule l'empreinte manque")
        XCTAssertNil(photo["sens"])
    }

    func testLaGenerationDeLIndex() throws {
        let rouge = try vignette("1.jpg", rouge: 230, vert: 20, bleu: 20)
        let mesurer: (Suivi.AAnalyser) -> JSONValue = { p in ["id": .number(Double(p.id)), "cherches": [], "defauts": [], "genre": "autre", "mesures": [:]] }
        let entree: JSONValue = ["catalogue": "/C.lrcat", "photos": [["id": 1, "vignette": .string(rouge), "cache": true, "uuid": "U1"]]]
        let sens = Suivi.IndexeurSens(racine: dossier) { FauxEncodeur() }
        let premiere = try XCTUnwrap(Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer, sens: sens).ligne["index_sens"]?.string)
        XCTAssertEqual(Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer, sens: sens).ligne["index_sens"]?.string, premiere, "la même tant que l'index reste")
        let url = URL(fileURLWithPath: "/x")
        let fichiers = Sens.Fichiers(image: url, texte: url, vocabulaire: url, modeles: url)
        XCTAssertEqual(Suivi.etatSens(#"{"catalogue": "/C.lrcat"}"#, fichiers: (fichiers, []), racine: dossier).ligne["generation"]?.string, premiere)
        // L'index effacé (de la place faite) : --sens-etat ne rend plus de génération, et le suivant en tire une autre.
        let dossierIndex = IndexSens.dossier(catalogue: "/C.lrcat", racine: dossier)
        try FileManager.default.removeItem(at: dossierIndex)
        XCTAssertNil(Suivi.etatSens(#"{"catalogue": "/C.lrcat"}"#, fichiers: (fichiers, []), racine: dossier).ligne["generation"])
        let deuxieme = try XCTUnwrap(Suivi.analyser(JSONCoding.line(entree), mesurer: mesurer, sens: sens).ligne["index_sens"]?.string)
        XCTAssertNotEqual(deuxieme, premiere)
        // Un index refait pour un autre modèle : une autre génération.
        let autre = try IndexSens(ecrire: dossierIndex, modele: "autre", dimension: 4)
        XCTAssertNotEqual(autre.generation, deuxieme)
        XCTAssertNotNil(autre.generation)
    }

    func testUnIndexIllisibleSeRefaitANeuf() throws {
        let dossierIndex = dossier.appendingPathComponent("i")
        let index = try IndexSens(ecrire: dossierIndex, modele: "m", dimension: 4)
        try index.ranger(uuid: "u1", id: 1, jour: nil, vecteur: [1, 0, 0, 0])
        let avant = try XCTUnwrap(index.generation)
        // La base abîmée.
        try Data(repeating: 0x5A, count: 4096).write(to: dossierIndex.appendingPathComponent("index.sqlite"))
        try? FileManager.default.removeItem(at: dossierIndex.appendingPathComponent("index.sqlite-wal"))
        try? FileManager.default.removeItem(at: dossierIndex.appendingPathComponent("index.sqlite-shm"))
        let refait = try IndexSens(ecrire: dossierIndex, modele: "m", dimension: 4)
        XCTAssertEqual(refait.nombre, 0)
        XCTAssertNotEqual(refait.generation, avant)
        try refait.ranger(uuid: "u1", id: 1, jour: nil, vecteur: [1, 0, 0, 0])
        XCTAssertEqual(refait.classer([1, 0, 0, 0]).first?.ligne.id, 1)
        // Les vecteurs effacés à côté de leurs lignes : refait aussi.
        let generation = refait.generation
        try FileManager.default.removeItem(at: dossierIndex.appendingPathComponent("vecteurs.f16"))
        let sansVecteurs = try IndexSens(ecrire: dossierIndex, modele: "m", dimension: 4)
        XCTAssertEqual(sansVecteurs.nombre, 0)
        XCTAssertNotEqual(sansVecteurs.generation, generation)
        // Un index sain garde sa génération.
        try sansVecteurs.ranger(uuid: "u2", id: 2, jour: nil, vecteur: [0, 1, 0, 0])
        XCTAssertEqual(try IndexSens(ecrire: dossierIndex, modele: "m", dimension: 4).generation, sansVecteurs.generation)
    }

    func testSensEtatNAnnonceQuUnModeleCompileQuiSOuvre() throws {
        let paquet = URL(fileURLWithPath: "/x/mobileclip_s2_image.mlpackage")
        let url = URL(fileURLWithPath: "/x")
        // Pas encore compilé : le module lance --compiler-sens ; rien d'annoncé.
        let aCompiler = Suivi.etatSens("{}", fichiers: (Sens.Fichiers(image: paquet, texte: paquet, vocabulaire: url, modeles: url), []), racine: dossier)
        XCTAssertNil(aCompiler.ligne["regles_sens"])
        XCTAssertEqual(aCompiler.ligne["a_compiler"], true)
        XCTAssertFalse(Sens.Fichiers(image: paquet, texte: paquet, vocabulaire: url, modeles: url).imageCompilee)
        // Compilé mais qui ne s'ouvre pas : l'erreur, sans regles_sens.
        let compile = URL(fileURLWithPath: "/x/mobileclip_s2_image.mlmodelc")
        let fichiers = Sens.Fichiers(image: compile, texte: paquet, vocabulaire: url, modeles: url)
        let casse = Suivi.etatSens("{}", fichiers: (fichiers, []), racine: dossier) { throw LightroomError.invalid("compilation refusée") }
        XCTAssertNil(casse.ligne["regles_sens"])
        XCTAssertEqual(casse.ligne["erreur"], "compilation refusée")
        // Qui s'ouvre : annoncé.
        XCTAssertEqual(Suivi.etatSens("{}", fichiers: (fichiers, []), racine: dossier) { FauxEncodeur() }.ligne["regles_sens"]?.int, Sens.regles)
    }

    func testSensEtat() throws {
        let manque = Suivi.etatSens(#"{"catalogue": "/C.lrcat"}"#, fichiers: (nil, ["vocabulaire"]), racine: dossier)
        XCTAssertNil(manque.ligne["regles_sens"])
        XCTAssertEqual(manque.ligne["manquants"], ["vocabulaire"])
        let url = URL(fileURLWithPath: "/x")
        let index = try IndexSens(ecrire: IndexSens.dossier(catalogue: "/C.lrcat", racine: dossier), modele: Sens.nomModele, dimension: 4)
        try index.ranger(uuid: "u", id: 1, jour: nil, vecteur: [1, 0, 0, 0])
        let pret = Suivi.etatSens(#"{"catalogue": "/C.lrcat"}"#, fichiers: (Sens.Fichiers(image: url, texte: url, vocabulaire: url, modeles: url), []),
                                  racine: dossier)
        XCTAssertEqual(pret.ligne["regles_sens"]?.int, Sens.regles)
        XCTAssertEqual(pret.ligne["indexees"]?.int, 1)
        XCTAssertEqual(pret.code, 0)
    }

    // MARK: find_photos

    /// Un catalogue de cinq photos indexées : 1 rouge (2019), 2 rouge foncé (2021), 3 verte, 4 bleue,
    /// 5 grise.
    func outils(_ lightroom: FakeLightroom, encodeur: FauxEncodeur = FauxEncodeur()) throws -> ToolHandler {
        let index = try IndexSens(ecrire: IndexSens.dossier(catalogue: "/C.lrcat", racine: dossier), modele: Sens.nomModele, dimension: 4)
        try index.ranger(uuid: "u1", id: 1, jour: "2019-07-14 18:30", vecteur: Sens.normaliser([1, 0, 0, 0.1]))
        try index.ranger(uuid: "u2", id: 2, jour: "2021-03-01 10:00", vecteur: Sens.normaliser([0.9, 0.1, 0, 0.1]))
        try index.ranger(uuid: "u3", id: 3, jour: "2019-08-01 09:00", vecteur: Sens.normaliser([0, 1, 0, 0.1]))
        try index.ranger(uuid: "u4", id: 4, jour: nil, vecteur: Sens.normaliser([0, 0, 1, 0.1]))
        try index.ranger(uuid: "u5", id: 5, jour: "2019-07-15 12:00", vecteur: Sens.normaliser([0.3, 0.3, 0.3, 0.1]))
        lightroom.replies["etat"] = ["chemin_catalogue": "/C.lrcat", "lightroom": "15.6"]
        lightroom.onSend = { commande, params in
            guard commande == "chercher" else { return }
            let ids = (params["parmi"]?.array ?? []).compactMap(\.int)
            lightroom.replies["chercher"] = ["parmi": true, "total": .number(Double(ids.count)), "decalage": 0, "renvoyees": .number(Double(ids.count)),
                                            "photos": .array(ids.map { ["id": .number(Double($0)), "fichier": .string("P\($0).RAF")] }), "remarques": []]
        }
        let tools = ToolHandler(lightroom: lightroom)
        tools.sens = Suivi.IndexeurSens(racine: dossier) { encodeur }
        return tools
    }

    func chercher(_ lightroom: FakeLightroom) -> [[String: JSONValue]] {
        lightroom.calls.filter { $0.command == "chercher" }.map(\.params)
    }

    func testQueryClasseParPertinenceEtPasseLesMieuxClasseesAuModule() throws {
        let lightroom = FakeLightroom()
        let encodeur = FauxEncodeur()
        let tools = try outils(lightroom, encodeur: encodeur)
        let result = tools.call(name: "find_photos", arguments: ["query": "a red barn", "rating_min": 3])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(encodeur.textes, ["a red barn"], "la phrase telle quelle")
        let params = try XCTUnwrap(chercher(lightroom).last)
        let parmi = try XCTUnwrap(params["parmi"]?.array).compactMap(\.int)
        XCTAssertEqual(parmi.first, 1, "la plus pertinente d'abord")
        XCTAssertEqual(Array(parmi.prefix(2)), [1, 2])
        XCTAssertFalse(parmi.contains(4), "la bleue, sous le seuil de pertinence")
        XCTAssertEqual(params["note_min"], 3, "les autres critères au module")
        XCTAssertEqual(params["tri"], "aucun", "l'ordre de la pertinence")
        let structure = try XCTUnwrap(result.structured)
        let photos = try XCTUnwrap(structure["photos"]?.array)
        XCTAssertEqual(photos.first?["pertinence"], 1)
        XCTAssertLessThan(try XCTUnwrap(photos.last?["pertinence"]?.double), 1)
        XCTAssertNil(structure["parmi"], "la clé du module reste entre eux")
        XCTAssertEqual(structure["recherche_par_le_sens"]?["photos_indexees"], 5)
        XCTAssertEqual(structure["recherche_par_le_sens"]?["modele"]?.string, Sens.nomModele)
        // L'encodeur s'ouvre une fois par processus.
        _ = tools.call(name: "find_photos", arguments: ["query": "green"])
        XCTAssertEqual(chercher(lightroom).last?["parmi"]?.array?.first?.int, 3)
    }

    func testLesDatesSeFiltrentDApresLIndexSansLesEnvoyerAuModule() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        let result = tools.call(name: "find_photos", arguments: ["query": "red", "date_from": "2019-01-01", "date_to": "2019-12-31"])
        XCTAssertFalse(result.isError, result.text)
        let params = try XCTUnwrap(chercher(lightroom).last)
        XCTAssertNil(params["date_debut"], "le module refuserait un filtre de date seul")
        XCTAssertNil(params["date_fin"])
        let parmi = try XCTUnwrap(params["parmi"]?.array).compactMap(\.int)
        XCTAssertTrue(parmi.contains(1))
        XCTAssertFalse(parmi.contains(2), "prise en 2021")
        XCTAssertFalse(parmi.contains(4), "sans date")
        XCTAssertTrue(tools.call(name: "find_photos", arguments: ["query": "red", "date_from": "juillet"]).isError)
    }

    func testSimilarToEcarteLaPhotoEtPasseParSonOriginal() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        var result = tools.call(name: "find_photos", arguments: ["similar_to": 1])
        XCTAssertFalse(result.isError, result.text)
        var parmi = try XCTUnwrap(chercher(lightroom).last?["parmi"]?.array).compactMap(\.int)
        XCTAssertEqual(parmi.first, 2, "la plus semblable, sans elle-même")
        XCTAssertFalse(parmi.contains(1))
        // Une copie virtuelle (hors de l'index) : son original, demandé au module.
        lightroom.calls = []
        lightroom.onSend = { commande, params in
            guard commande == "chercher" else { return }
            if params["originaux"] == true {
                lightroom.replies["chercher"] = ["parmi": true, "total": 1, "photos": [["id": 3]]]
            } else {
                let ids = (params["parmi"]?.array ?? []).compactMap(\.int)
                lightroom.replies["chercher"] = ["parmi": true, "total": .number(Double(ids.count)), "photos": .array(ids.map { ["id": .number(Double($0))] })]
            }
        }
        result = tools.call(name: "find_photos", arguments: ["similar_to": 90])
        XCTAssertFalse(result.isError, result.text)
        let appels = chercher(lightroom)
        XCTAssertEqual(appels.first?["parmi"], [90])
        XCTAssertEqual(appels.first?["originaux"], true)
        parmi = try XCTUnwrap(appels.last?["parmi"]?.array).compactMap(\.int)
        XCTAssertFalse(parmi.contains(3), "l'original écarté aussi")
        // Une photo que le Suivi n'a pas analysée.
        lightroom.onSend = { commande, _ in
            if commande == "chercher" { lightroom.replies["chercher"] = ["parmi": true, "total": 1, "photos": [["id": 77]]] }
        }
        result = tools.call(name: "find_photos", arguments: ["similar_to": 77])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("pas encore dans l'index"), result.text)
    }

    func testLesRefus() throws {
        // Sans recherche par le sens : refusé avant tout envoi.
        let seul = FakeLightroom()
        var result = ToolHandler(lightroom: seul).call(name: "find_photos", arguments: ["query": "a dog"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("pas installée"), result.text)
        XCTAssertEqual(seul.commands, [])
        // Index vide pour ce catalogue.
        let vide = FakeLightroom()
        vide.replies["etat"] = ["chemin_catalogue": "/Autre.lrcat"]
        let tools = ToolHandler(lightroom: vide)
        tools.sens = Suivi.IndexeurSens(racine: dossier) { FauxEncodeur() }
        result = tools.call(name: "find_photos", arguments: ["query": "a dog"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Aucune photo indexée"), result.text)
        XCTAssertEqual(vide.commands, ["etat"])
        // Les arguments.
        let lightroom = FakeLightroom()
        let avec = try outils(lightroom)
        XCTAssertTrue(avec.call(name: "find_photos", arguments: ["query": "  "]).isError)
        XCTAssertTrue(avec.call(name: "find_photos", arguments: ["query": "red", "similar_to": 1]).isError)
        XCTAssertTrue(avec.call(name: "find_photos", arguments: ["rating_min": 3, "sort": "relevance"]).isError, "relevance sans query")
        XCTAssertFalse(avec.call(name: "find_photos", arguments: ["query": "red", "sort": "relevance"]).isError)
        // Un autre modèle dans l'index.
        let autre = try outils(FakeLightroom(), encodeur: FauxEncodeur(modele: "autre"))
        XCTAssertTrue(autre.call(name: "find_photos", arguments: ["query": "red"]).text.contains("autre modèle"))
        // Un module d'avant la 1.6 (parmi ignoré).
        let ancien = FakeLightroom()
        let vieux = try outils(ancien)
        ancien.onSend = { commande, _ in
            if commande == "chercher" { ancien.replies["chercher"] = ["total": 9, "photos": []] }
        }
        result = vieux.call(name: "find_photos", arguments: ["query": "red"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("même version"), result.text)
    }

    func testLesCandidatesPassentParTranchesJusquaRemplirLaPage() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        tools.trancheSens = 1
        // Une collection qui ne garde que la photo 2, classée deuxième (au-delà de la première tranche).
        lightroom.onSend = { commande, params in
            guard commande == "chercher" else { return }
            let ids = (params["parmi"]?.array ?? []).compactMap(\.int).filter { $0 == 2 }
            lightroom.replies["chercher"] = ["parmi": true, "total": .number(Double(ids.count)), "decalage": 0, "renvoyees": .number(Double(ids.count)),
                                            "photos": .array(ids.map { ["id": .number(Double($0))] }), "remarques": []]
        }
        let result = tools.call(name: "find_photos", arguments: ["query": "red", "collection": "Chalet 2015"])
        XCTAssertFalse(result.isError, result.text)
        let structure = try XCTUnwrap(result.structured)
        XCTAssertEqual(structure["photos"]?.array?.compactMap { $0["id"]?.int }, [2], "trouvée dans la deuxième tranche")
        XCTAssertEqual(structure["total"], 1)
        let appels = chercher(lightroom)
        XCTAssertEqual(appels.map { $0["parmi"]?.array?.compactMap(\.int) ?? [] }, [[1], [2]])
        XCTAssertEqual(appels.last?["collection"], "Chalet 2015")
        // La page remplie dès la première tranche : la suite n'est pas lue, le total est un minimum.
        // (Le module compte toutes les photos gardées et rend la page d'après decalage et limite.)
        lightroom.calls = []
        lightroom.onSend = { commande, params in
            guard commande == "chercher" else { return }
            let ids = (params["parmi"]?.array ?? []).compactMap(\.int)
            let page = ids.dropFirst(params["decalage"]?.int ?? 0).prefix(params["limite"]?.int ?? 50)
            lightroom.replies["chercher"] = ["parmi": true, "total": .number(Double(ids.count)), "photos": .array(page.map { ["id": .number(Double($0))] })]
        }
        let page = tools.call(name: "find_photos", arguments: ["query": "red", "limit": 1])
        XCTAssertEqual(chercher(lightroom).count, 1)
        XCTAssertTrue(page.text.contains("au moins 1"), page.text)
        // La suite (offset 1) : la deuxième tranche donne la deuxième photo.
        lightroom.calls = []
        let suite = tools.call(name: "find_photos", arguments: ["query": "red", "limit": 1, "offset": 1])
        XCTAssertEqual(suite.structured?["photos"]?.array?.compactMap { $0["id"]?.int }, [2])
        XCTAssertEqual(chercher(lightroom).last?["decalage"], 0, "décalage pris dans les tranches déjà lues")
    }

    func testSansQueryRienNeChange() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        _ = tools.call(name: "find_photos", arguments: ["rating_min": 3, "date_from": "2019-01-01"])
        XCTAssertEqual(lightroom.commands, ["chercher"], "ni etat ni index")
        XCTAssertNil(lightroom.lastParams["parmi"])
        XCTAssertEqual(lightroom.lastParams["date_debut"], "2019-01-01")
    }

    func testLaDescriptionDeFindPhotos() throws {
        let definition = try XCTUnwrap(ToolHandler(lightroom: FakeLightroom()).definitions.first { $0["name"] == "find_photos" })
        let description = try XCTUnwrap(definition["description"]?.string)
        XCTAssertTrue(description.contains("vue Personnes"), "les personnes : leur nom en keyword")
        XCTAssertLessThanOrEqual(description.utf16.count, 1000, "\(description.utf16.count)")
        let proprietes = try XCTUnwrap(definition["inputSchema"]?["properties"]?.object)
        XCTAssertTrue(try XCTUnwrap(proprietes["query"]?["description"]?.string).contains("en anglais"))
        XCTAssertNotNil(proprietes["similar_to"])
        XCTAssertTrue(try XCTUnwrap(proprietes["sort"]?["enum"]?.array).contains("relevance"))
        // Les collections dynamiques n'ont pas la recherche par le sens (Lightroom ne la connaît pas).
        let collections = try XCTUnwrap(ToolHandler(lightroom: FakeLightroom()).definitions.first { $0["name"] == "manage_collections" })
        XCTAssertNil(collections["inputSchema"]?["properties"]?["search"]?["properties"]?["query"])
    }

    // MARK: get_status

    func testGetStatusDitLEtatDeLIndex() throws {
        let lightroom = FakeLightroom()
        let tools = try outils(lightroom)
        let result = tools.call(name: "get_status", arguments: [:])
        let bloc = try XCTUnwrap(result.structured?["recherche_par_le_sens"] ?? (try? JSONCoding.parse(result.text))?["recherche_par_le_sens"])
        XCTAssertEqual(bloc["photos_indexees"], 5)
        XCTAssertEqual(bloc["installee"], true)
        XCTAssertNotNil(bloc["derniere_empreinte"])
        XCTAssertFalse(result.text.contains("/C.lrcat"), "le chemin du catalogue ne part pas chez Claude")
        // Sans recherche par le sens (les essais, un connecteur sans modèle posé) : rien.
        let sans = FakeLightroom()
        sans.replies["etat"] = ["chemin_catalogue": "/C.lrcat"]
        XCTAssertFalse(ToolHandler(lightroom: sans).call(name: "get_status", arguments: [:]).text.contains("recherche_par_le_sens"))
        // Modèle absent : dit, avec ce qui manque.
        tools.sens = Suivi.IndexeurSens(racine: dossier, manquants: { ["vocabulaire"] }) { FauxEncodeur() }
        let manque = try XCTUnwrap(try JSONCoding.parse(tools.call(name: "get_status", arguments: [:]).text)["recherche_par_le_sens"])
        XCTAssertEqual(manque["installee"], false)
        XCTAssertEqual(manque["manquants"], ["vocabulaire"])
    }

    // MARK: --sens-essai

    func testLEssaiSurUnDossierDImages() throws {
        let images = dossier.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try TestSupport.jpeg(red: 230, green: 10, blue: 10).write(to: images.appendingPathComponent("a.jpg"))
        try TestSupport.jpeg(red: 10, green: 10, blue: 230).write(to: images.appendingPathComponent("b.jpg"))
        try TestSupport.jpeg(red: 200, green: 30, blue: 30).write(to: images.appendingPathComponent("c.jpg"))
        let essai = EssaiSens(lightroom: nil, encodeur: FauxEncodeur(), dossier: dossier.appendingPathComponent("index"))
        let r = try essai.lancer(source: .images(images), nombre: 200, requetes: ["red", "blue"])
        XCTAssertEqual(r["indexees"], 3)
        let requetes = try XCTUnwrap(r["requetes"]?.array)
        XCTAssertEqual(requetes.count, 2)
        XCTAssertEqual(requetes[0]["telle_quelle"]?["premieres"]?.array?.first?["fichier"], "a.jpg")
        XCTAssertNotNil(requetes[0]["avec_prefixe"]?["premieres"], "avec « a photo of »")
        XCTAssertEqual(requetes[1]["telle_quelle"]?["premieres"]?.array?.first?["fichier"], "b.jpg")
        XCTAssertEqual(r["semblables"]?["classement"]?["premieres"]?.array?.first?["fichier"], "c.jpg", "a.jpg ressemble à c.jpg")
    }

    func testLEssaiDansLightroomNeLitQue() throws {
        let lightroom = FakeLightroom()
        let vignette = try vignette("v.jpg", rouge: 200, vert: 20, bleu: 20)
        lightroom.replies["chercher"] = ["photos": [["id": 11, "fichier": "A.RAF"], ["id": 12, "fichier": "V.MOV", "video": true]]]
        lightroom.replies["vignettes"] = ["photos": [["id": 11, "vignette": .string(vignette)]]]
        var appels = 0
        lightroom.onSend = { commande, _ in
            if commande == "chercher" {
                appels += 1
                if appels > 1 { lightroom.replies["chercher"] = ["photos": []] }
            }
        }
        let essai = EssaiSens(lightroom: lightroom, encodeur: FauxEncodeur(), dossier: dossier.appendingPathComponent("index"))
        let r = try essai.lancer(source: .collection("Développeur › Essais"), nombre: 200, requetes: ["red"])
        XCTAssertEqual(r["indexees"], 1, "la vidéo sautée")
        XCTAssertEqual(Set(lightroom.commands), ["chercher", "vignettes"], "des lectures seulement")
        XCTAssertTrue(lightroom.commands.allSatisfy { LightroomBridge.lectures.contains($0) })
        XCTAssertEqual(lightroom.calls.first?.params["collection"], "Développeur › Essais")
    }
}
