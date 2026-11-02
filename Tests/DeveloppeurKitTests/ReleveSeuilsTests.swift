import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Le relevé des seuils provisoires (1.6, `--mesures`) : tirage des lots dans suivi.json, collecte
/// des vignettes par le faux module (lots de 10 à 20, JPEG temporaires retirés, notes de Claude
/// repérées au journal), mesure sans Lightroom et résumé. Jamais le vrai Lightroom.
final class ReleveSeuilsTests: XCTestCase {
    // MARK: Aides

    static func entree(_ id: Int, _ appareil: String, iso: Double, le: String = "2024-07-12 10:00", note: Int? = nil,
                       genre: String = "paysage", cherches: [String] = ["sous_exposition", "ciel_brule"], defauts: [String] = [],
                       retouchee: Bool = false, copies: [Int] = []) -> (String, JSONValue) {
        let vues: [JSONValue] = [["id": .number(Double(id)), "copie_virtuelle": false]]
            + copies.map { ["id": .number(Double($0)), "copie_virtuelle": true] }
        var objet: [String: JSONValue] = [
            "original": .number(Double(id)), "fichier": .string("F\(id).RAF"), "uuid": .string("uuid-\(id)"), "vues": .array(vues),
            "prise_de_vue": ["le": .string(le), "appareil": .string(appareil), "iso": .number(iso)],
            "retouchee_par_claude": .bool(retouchee),
            "analyse": ["regles": 1, "cherches": .array(cherches.map(JSONValue.string)), "defauts": .array(defauts.map(JSONValue.string)),
                        "genre": .string(genre)],
        ]
        if let note { objet["note"] = .number(Double(note)) }
        return ("\(id)", .object(objet))
    }

    static func suivi(_ entrees: [(String, JSONValue)], autre: [(String, JSONValue)]? = nil) -> JSONValue {
        var catalogues: [String: JSONValue] = ["/Volumes/Photos/Catalogue.lrcat": ["photos": .object(Dictionary(uniqueKeysWithValues: entrees))]]
        if let autre { catalogues["/Users/dany/Pictures/Ancien.lrcat"] = ["photos": .object(Dictionary(uniqueKeysWithValues: autre))] }
        return ["format": 1, "catalogues": .object(catalogues)]
    }

    static func lightroomInterdit() -> LightroomServing {
        XCTFail("cette sous-commande ne doit jamais parler au module")
        return FakeLightroom()
    }

    // MARK: Échantillons

    func testLesEchantillonsTirentLesTroisBoitiersEtEcartentLeReste() throws {
        var entrees: [(String, JSONValue)] = []
        for i in 1...5 { entrees.append(Self.entree(i, "X-H2S", iso: 160)) }
        for i in 6...8 { entrees.append(Self.entree(i, "X-T4", iso: 1000)) }
        entrees.append(Self.entree(9, "FUJIFILM X-T4", iso: 1250))
        for i in 10...11 { entrees.append(Self.entree(i, "X-T20", iso: 3200)) }
        for i in 12...13 { entrees.append(Self.entree(i, "iPhone 12", iso: 2000)) }
        entrees.append(Self.entree(14, "X-H2S", iso: 160, retouchee: true))
        let lots = ReleveSeuils.echantillons(Self.suivi(entrees), graine: 7)
        XCTAssertEqual(lots.map(\.nom), ["A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8"])
        let a1 = try XCTUnwrap(lots.first)
        let groupes = Dictionary(grouping: a1.photos, by: \.groupe).mapValues(\.count)
        XCTAssertEqual(groupes["X-T4 ISO 800-1599"], 4, "le X-T4, « FUJIFILM X-T4 » compris (critique du plan)")
        XCTAssertEqual(groupes["X-H2S ISO moins de 800"], 5)
        XCTAssertEqual(groupes["X-T20 ISO 3200-6399"], 2)
        let tous = Set(lots.flatMap { $0.photos.map(\.photo.id) })
        XCTAssertFalse(tous.contains(12) || tous.contains(13), "un autre appareil que les trois boîtiers n'entre pas")
        XCTAssertFalse(tous.contains(14), "une photo retouchée par Claude n'entre pas")
        for lot in lots { XCTAssertEqual(Set(lot.photos.map(\.photo.id)).count, lot.photos.count, "une photo une fois par lot (\(lot.nom))") }
        // Reproductible : la même graine, le même ordre.
        let encore = ReleveSeuils.echantillons(Self.suivi(entrees), graine: 7)
        XCTAssertEqual(encore.map { $0.photos.map(\.photo.id) }, lots.map { $0.photos.map(\.photo.id) })
    }

    func testA2PrendLesBienNoteesA6LesJourneesA8LesSuites() throws {
        var entrees: [(String, JSONValue)] = []
        entrees.append(Self.entree(1, "X-H2S", iso: 400, note: 4, defauts: ["sous_exposition"]))
        entrees.append(Self.entree(2, "X-H2S", iso: 4000, defauts: ["sous_exposition"]))
        entrees.append(Self.entree(3, "X-H2S", iso: 400))
        // Une journée de 40 photos du X-H2S, une de 39.
        for i in 0..<40 { entrees.append(Self.entree(100 + i, "X-H2S", iso: 200, le: String(format: "2023-05-01 %02d:%02d", 8 + i / 60, i % 60))) }
        for i in 0..<39 { entrees.append(Self.entree(200 + i, "X-H2S", iso: 200, le: String(format: "2023-05-02 %02d:%02d", 8, i))) }
        // Une suite de portraits (10 h 00, 10 h 01, 10 h 03), puis deux photos seules à 10 h 10 et 10 h 11.
        for (i, minute) in ["10:00", "10:01", "10:03", "10:10", "10:11"].enumerated() {
            entrees.append(Self.entree(300 + i, "X-T4", iso: 800, le: "2022-08-20 \(minute)", genre: "portrait"))
        }
        let lots = ReleveSeuils.echantillons(Self.suivi(entrees), graine: 1)
        let a2 = try XCTUnwrap(lots.first { $0.nom == "A2" })
        XCTAssertEqual(a2.photos.first { $0.photo.id == 1 }?.groupe, "signalée, 3 étoiles ou plus")
        XCTAssertEqual(a2.photos.first { $0.photo.id == 2 }?.groupe, "signalée, X-H2S ISO 3200-6399")
        XCTAssertEqual(a2.photos.first { $0.photo.id == 3 }?.groupe, "non signalée")
        let a6 = try XCTUnwrap(lots.first { $0.nom == "A6" })
        XCTAssertEqual(Set(a6.photos.map(\.groupe)), ["jour 2023-05-01"], "une journée de moins de 40 photos n'est pas tirée")
        XCTAssertEqual(a6.photos.count, 40)
        let a8 = try XCTUnwrap(lots.first { $0.nom == "A8" })
        XCTAssertEqual(a8.photos.map(\.photo.id), [300, 301, 302], "trois photos à 2 min au plus l'une de l'autre ; deux ne font pas une suite")
    }

    func testLesEchantillonsSEcriventSansLeModule() throws {
        let dossier = TestSupport.temporaryDirectory()
        let fichier = dossier.appendingPathComponent("suivi.json")
        try Data(JSONCoding.line(Self.suivi([Self.entree(1, "X-H2S", iso: 3200)])).utf8).write(to: fichier)
        let sortie = ReleveSeuils.commande(["--echantillons", fichier.path, dossier.appendingPathComponent("releve").path, "--graine", "3"],
                                           lightroom: Self.lightroomInterdit)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        let lot = try JSONCoding.parse(Data(contentsOf: dossier.appendingPathComponent("releve/lots/A1.json")))
        XCTAssertEqual(lot["photos"]?.array?.first?["id"]?.int, 1)
        XCTAssertEqual(lot["photos"]?.array?.first?["groupe"]?.string, "X-H2S ISO 3200-6399")
        XCTAssertEqual(lot["graine"]?.int, 3)
        let texte = try String(contentsOf: dossier.appendingPathComponent("releve/echantillons.txt"), encoding: .utf8)
        XCTAssertTrue(texte.contains("moins de 30 : le seuil resterait provisoire"), texte)
    }

    // MARK: Collecte

    /// Le faux module : chaque commande vignettes écrit ses JPEG dans son propre dossier temporaire,
    /// comme Vignettes.lua ; la photo 5 n'a pas de vignette ; la note de la photo 2 vient de Claude.
    static func fauxModule(temporaire: URL) -> FakeLightroom {
        let lightroom = FakeLightroom()
        lightroom.onSend = { [unowned lightroom] commande, params in
            let ids = (params["photos"]?.array ?? []).compactMap(\.int)
            if commande == "vignettes" {
                let dossier = temporaire.appendingPathComponent("vignettes-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
                let photos: [JSONValue] = ids.map { id in
                    var item: [String: JSONValue] = [
                        "id": .number(Double(id)), "fichier": .string("XH2S\(id).RAF"), "appareil": "X-H2S",
                        "date": .string(String(format: "2026-10-21 14:%02d:%02d", id / 60, id % 60)),
                        "sensibilite": 3200, "note": 4, "retouchee_par_claude": false,
                        "prise_de_vue": ["ouverture": 4, "vitesse": 0.005, "compensation": -0.67, "flash": false],
                    ]
                    if id == 5 {
                        item["erreur"] = "Lightroom n'a pas rendu de vignette"
                    } else if id == 7 {
                        // Un portrait de X-H2S (4160 × 6240 affiché) dont Lightroom rend la vignette
                        // couchée, sans balise d'orientation (XH2S0407.RAF, constat du 25 oct. 2026) :
                        // le tiers gauche du fichier, rouge, est le haut de la photo.
                        let fichier = dossier.appendingPathComponent("\(id).jpg")
                        try? TestSupport.jpegPixels(width: 72, height: 48) { x, _ in x < 24 ? (230, 20, 20) : (100, 100, 100) }.write(to: fichier)
                        item["vignette"] = .string(fichier.path)
                        item["geometrie"] = ["largeur": 4160, "hauteur": 6240, "orientation": "BC"]
                    } else {
                        let fichier = dossier.appendingPathComponent("\(id).jpg")
                        try? TestSupport.jpeg(red: 120, green: 110, blue: 100, width: 64, height: 48).write(to: fichier)
                        item["vignette"] = .string(fichier.path)
                    }
                    return .object(item)
                }
                lightroom.replies["vignettes"] = ["taille": params["taille"] ?? .null, "dossier": .string(dossier.path), "photos": .array(photos)]
            } else if commande == "journal" {
                lightroom.replies["journal"] = ["photos": .array(ids.map { id in
                    // 2 et 101 (une copie virtuelle) : notes posées par Claude.
                    let entrees: [JSONValue] = id == 2 || id == 101
                        ? [["type": "classement", "etape": "Claude · notation", "changements": [["cle": "note", "avant": 0, "apres": 4]]]]
                        : (id == 3 ? [["type": "retouche", "changements": [["cle": "Exposure2012", "avant": 0, "apres": 0.3]]]] : [])
                    return ["photo": ["id": .number(Double(id))], "entrees": .array(entrees)]
                })]
            }
        }
        return lightroom
    }

    func testLaCollecteDemandeParLotsCopieEtRetireLesJPEGTemporaires() throws {
        let racine = TestSupport.temporaryDirectory()
        let temporaire = racine.appendingPathComponent("module")
        let lightroom = Self.fauxModule(temporaire: temporaire)
        let lot: JSONValue = ["lot": "A1", "photos": .array((1...23).map { ["id": .number(Double($0)), "groupe": "X-H2S ISO 3200-6399"] })]
        let fichierLot = racine.appendingPathComponent("A1.json")
        try Data(JSONCoding.line(lot).utf8).write(to: fichierLot)
        let dossier = racine.appendingPathComponent("A1")
        let sortie = ReleveSeuils.commande(["--collecter", fichierLot.path, dossier.path, "--par", "10"], lightroom: { lightroom })
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))

        let vignettes = lightroom.calls.filter { $0.command == "vignettes" }
        XCTAssertEqual(vignettes.map { $0.params["photos"]?.array?.count ?? 0 }, [10, 10, 3], "des lots de 10 à 20, pas 50")
        XCTAssertTrue(vignettes.allSatisfy { $0.params["taille"]?.int == 1024 }, "1 024 px par défaut")
        XCTAssertEqual(Set(lightroom.commands), ["vignettes", "journal"], "deux lectures, rien d'écrit")
        XCTAssertTrue(lightroom.commands.allSatisfy(LightroomBridge.lectures.contains))
        // Les JPEG temporaires du module sont retirés, avec leurs dossiers vides.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaire.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dossier.appendingPathComponent("vignettes/1024/1.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dossier.appendingPathComponent("vignettes/1024/5.jpg").path))

        let lignes = try ReleveSeuils.lireLignes(dossier.appendingPathComponent("catalogue.jsonl"))
        XCTAssertEqual(lignes.count, 23)
        let parId = Dictionary(uniqueKeysWithValues: lignes.compactMap { l in l["id"]?.int.map { ($0, l) } })
        XCTAssertEqual(parId[2]?["note_par_claude"]?.bool, true, "la note posée par Claude se lit au journal")
        XCTAssertEqual(parId[3]?["note_par_claude"]?.bool, false, "une retouche n'est pas une note")
        XCTAssertEqual(parId[1]?["compensation"]?.double, -0.67, "la compensation vient du catalogue")
        XCTAssertEqual(parId[1]?["flash"]?.bool, false)
        XCTAssertEqual(parId[1]?["date_secondes"]?.bool, true, "l'heure exacte, à la seconde")
        XCTAssertEqual(parId[1]?["iso"]?.double, 3200)
        XCTAssertEqual(parId[1]?["groupe"]?.string, "X-H2S ISO 3200-6399")
        XCTAssertNotNil(parId[1]?["lumiere_il"]?.double)
        XCTAssertEqual(parId[1]?["cote"]?.int, 64)
        XCTAssertNotNil(parId[5]?["erreur"])
        XCTAssertNil(parId[5]?["vignette"])

        // Relancée, la collecte ne redemande que la photo sans vignette.
        let encore = ReleveSeuils.commande(["--collecter", fichierLot.path, dossier.path, "--par", "10"], lightroom: { lightroom })
        XCTAssertEqual(encore.code, 0)
        XCTAssertEqual(lightroom.calls.filter { $0.command == "vignettes" }.last?.params["photos"]?.array?.compactMap(\.int), [5])
        let entrees = try ReleveSeuils.lireCatalogue(dossier)
        XCTAssertEqual(entrees.count, 22, "chaque photo une fois, la dernière ligne avec vignette l'emporte")
    }

    func testLaCollecteSArreteQuandLeModuleNeRepondPlus() throws {
        let racine = TestSupport.temporaryDirectory()
        let lightroom = FakeLightroom()
        lightroom.errors["vignettes"] = LightroomError.invalid("Liaison fermée")
        let fichierLot = racine.appendingPathComponent("lot.json")
        try Data(JSONCoding.line(["lot": "A2", "photos": .array((1...80).map { .number(Double($0)) })]).utf8).write(to: fichierLot)
        let sortie = ReleveSeuils.commande(["--collecter", fichierLot.path, racine.appendingPathComponent("A2").path, "--par", "20"],
                                           lightroom: { lightroom })
        XCTAssertEqual(sortie.code, 1)
        XCTAssertEqual(lightroom.calls.filter { $0.command == "vignettes" }.count, ReleveSeuils.echecsDeSuiteMax)
    }

    func testLaTailleDesLotsEstBornee() {
        for par in ["5", "25"] {
            let sortie = ReleveSeuils.commande(["--collecter", "/n/existe/pas.json", "/tmp/rien", "--par", par], lightroom: Self.lightroomInterdit)
            XCTAssertEqual(sortie.code, 2, "--par \(par)")
        }
        XCTAssertEqual(ReleveSeuils.commande(["--collecter", "a", "b", "--taille", "4096"], lightroom: Self.lightroomInterdit).code, 2)
        XCTAssertEqual(ReleveSeuils.commande(["--inconnue"], lightroom: Self.lightroomInterdit).code, 2)
    }

    func testUneNoteDeClaudeSeLitAuJournal() {
        XCTAssertTrue(ReleveSeuils.noteParClaude([["type": "classement", "changements": [["cle": "note", "avant": 0, "apres": 3]]]]))
        XCTAssertFalse(ReleveSeuils.noteParClaude([["type": "classement", "changements": [["cle": "mots_cles", "avant": "—", "apres": "été"]]]]))
        XCTAssertFalse(ReleveSeuils.noteParClaude([["type": "retouche", "changements": [["cle": "note"]]]]))
        XCTAssertFalse(ReleveSeuils.noteParClaude([]))
    }

    /// Écrit un lot et lance la collecte avec le faux module.
    static func collecte(_ photos: [JSONValue], lightroom: FakeLightroom, racine: URL) throws -> (sortie: ReleveSeuils.Sortie, lignes: [Int: JSONValue], dossier: URL) {
        let fichierLot = racine.appendingPathComponent("lot.json")
        try Data(JSONCoding.line(["lot": "A2", "photos": .array(photos)]).utf8).write(to: fichierLot)
        let dossier = racine.appendingPathComponent("A2")
        let sortie = ReleveSeuils.commande(["--collecter", fichierLot.path, dossier.path, "--par", "10"], lightroom: { lightroom })
        let lignes = try ReleveSeuils.lireLignes(dossier.appendingPathComponent("catalogue.jsonl"))
        return (sortie, Dictionary(lignes.compactMap { l in l["id"]?.int.map { ($0, l) } }, uniquingKeysWith: { _, b in b }), dossier)
    }

    /// Revue du relevé : le Suivi tourne chaque vignette couchée avant son analyse
    /// (Images.redresser) ; la collecte aussi, sinon le relevé ne mesure pas la même image.
    func testUneVignetteCoucheeEstRemiseALEndroitCommeAuSuivi() throws {
        let racine = TestSupport.temporaryDirectory()
        let lightroom = Self.fauxModule(temporaire: racine.appendingPathComponent("module"))
        let (sortie, lignes, dossier) = try Self.collecte([["id": 7, "groupe": "signalée"], ["id": 1, "groupe": "signalée"]], lightroom: lightroom, racine: racine)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        XCTAssertEqual(lignes[7]?["quart_de_tour"]?.int, 90)
        XCTAssertNil(lignes[1]?["quart_de_tour"], "sans géométrie, rien ne tourne")
        let donnees = try Data(contentsOf: dossier.appendingPathComponent("vignettes/1024/7.jpg"))
        let image = try XCTUnwrap(PreviewImages.image(donnees))
        XCTAssertEqual([image.width, image.height], [48, 72], "debout, comme la photo affichée")
        guard image.width == 48, image.height == 72 else { return }
        let pixels = try XCTUnwrap(Measurements.rgba(image))
        func rouge(_ x: Int, _ y: Int) -> Bool { pixels[(y * image.width + x) * 4] > 180 && pixels[(y * image.width + x) * 4 + 1] < 80 }
        XCTAssertTrue(rouge(24, 8), "le tiers gauche du fichier est en haut (quart de tour dans le sens des aiguilles, sips -r 90)")
        XCTAssertFalse(rouge(24, 60))
        XCTAssertTrue(sortie.lignes.contains { $0.contains("1 remise(s) à l'endroit") }, sortie.lignes.joined(separator: "\n"))
    }

    func testLeQuartManquantSuitImagesRotationManquante() {
        let debout: JSONValue = ["largeur": 4160, "hauteur": 6240, "orientation": "BC"]
        XCTAssertEqual(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: debout), 90)
        XCTAssertNil(ReleveSeuils.quartManquant(largeur: 683, hauteur: 1024, geometrie: debout), "déjà à l'endroit")
        XCTAssertEqual(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: ["largeur": 4160, "hauteur": 6240, "orientation": "DA"]), 270)
        XCTAssertNil(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: ["largeur": 4160, "hauteur": 6240, "orientation": "AB"]),
                     "pas de quart de tour")
        XCTAssertNil(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: ["largeur": 4160, "hauteur": 6240, "orientation": "CD"]),
                     "un demi-tour ne se voit pas aux proportions")
        XCTAssertNil(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: nil))
        // Un portrait recadré en paysage : debout à son cadre, la vignette reste.
        // (Le cadre est dans le repère du fichier, couché : sa largeur est la hauteur affichée.)
        let recadre: JSONValue = ["largeur": 4160, "hauteur": 6240, "orientation": "BC",
                                  "cadre": ["CropLeft": 0, "CropTop": 0, "CropRight": 0.444, "CropBottom": 1]]
        XCTAssertNil(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: recadre))
        // Une vignette d'avant un recadrage en 4:5, couchée à la photo entière : elle se tourne.
        let quatreCinq: JSONValue = ["largeur": 4160, "hauteur": 6240, "orientation": "BC",
                                     "cadre": ["CropLeft": 0, "CropTop": 0, "CropRight": 0.833, "CropBottom": 1]]
        XCTAssertEqual(ReleveSeuils.quartManquant(largeur: 1024, hauteur: 683, geometrie: quatreCinq), 90)
    }

    /// Revue du relevé : un id introuvable fait échouer `journal` en entier (Photos.photoParId) ;
    /// les autres photos se redemandent famille par famille, et celle qui échoue encore reste
    /// d'auteur inconnu, jamais « note de Dany ».
    func testUnJournalEnEchecSeRedemandeParFamilleEtLaisseLaNoteInconnue() throws {
        let racine = TestSupport.temporaryDirectory()
        let lightroom = Self.fauxModule(temporaire: racine.appendingPathComponent("module"))
        let suite = lightroom.onSend
        lightroom.onSend = { [unowned lightroom] commande, params in
            suite?(commande, params)
            let ids = (params["photos"]?.array ?? []).compactMap(\.int)
            lightroom.errors["journal"] = commande == "journal" && ids.contains(4)
                ? LightroomError.plugin("Aucune photo n'a l'identifiant 4 dans le catalogue ouvert.") : nil
        }
        let (sortie, lignes, _) = try Self.collecte([1, 2, 3, 4].map { ["id": .number(Double($0)), "groupe": "signalée"] }, lightroom: lightroom, racine: racine)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        XCTAssertEqual(lignes[2]?["note_par_claude"]?.bool, true, "redemandée seule, la note de Claude se lit encore")
        XCTAssertEqual(lignes[1]?["note_par_claude"]?.bool, false)
        XCTAssertNil(lignes[4]?["note_par_claude"], "inconnue, pas faux")
        XCTAssertNotNil(lignes[4]?["journal_erreur"])
        XCTAssertNotNil(lignes[4]?["vignette"], "la vignette se garde : seule la note est inconnue")
        XCTAssertEqual(lightroom.calls.filter { $0.command == "journal" }.map { $0.params["photos"]?.array?.count ?? 0 }, [4, 1, 1, 1, 1])
        XCTAssertTrue(sortie.lignes.contains { $0.contains("1 note(s) d'auteur inconnu") }, sortie.lignes.joined(separator: "\n"))

        // Le journal entièrement en échec : aucune note n'est prise pour une note de Dany.
        let autre = TestSupport.temporaryDirectory()
        let enPanne = Self.fauxModule(temporaire: autre.appendingPathComponent("module"))
        enPanne.errors["journal"] = LightroomError.invalid("délai dépassé")
        let (sortie2, lignes2, _) = try Self.collecte([1, 2].map { ["id": .number(Double($0))] }, lightroom: enPanne, racine: autre)
        XCTAssertEqual(sortie2.code, 0)
        XCTAssertTrue(lignes2.values.allSatisfy { $0["note_par_claude"] == nil && $0["journal_erreur"] != nil })
    }

    /// Revue du relevé : la note de suivi.json est celle de la famille (copies virtuelles comprises) ;
    /// la collecte lit donc le journal des copies aussi, et garde note_suivi et note_famille.
    func testLaNoteSeLitSurLaFamille() throws {
        let racine = TestSupport.temporaryDirectory()
        let lightroom = Self.fauxModule(temporaire: racine.appendingPathComponent("module"))
        let (sortie, lignes, _) = try Self.collecte([["id": 1, "copies": [101], "note_suivi": 4], ["id": 3, "note_suivi": 5]],
                                                    lightroom: lightroom, racine: racine)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        XCTAssertEqual(lightroom.calls.first { $0.command == "journal" }?.params["photos"]?.array?.compactMap(\.int), [1, 101, 3])
        XCTAssertEqual(lignes[1]?["note_par_claude"]?.bool, true, "la note posée par Claude sur une copie compte pour la famille")
        XCTAssertEqual(lignes[3]?["note_suivi"]?.int, 5)
        XCTAssertEqual(lignes[3]?["note_famille"]?.int, 5, "la plus haute de la famille, comme au tirage")
        XCTAssertEqual(lignes[3]?["note"]?.int, 4, "celle de l'original, gardée à part")
    }

    /// Revue du relevé : un id qui désigne une autre photo (lot d'un autre catalogue) n'est ni copié
    /// ni rangé dans le groupe du lot.
    func testUnIdDUneAutrePhotoEstEnErreur() throws {
        let racine = TestSupport.temporaryDirectory()
        let temporaire = racine.appendingPathComponent("module")
        let lightroom = Self.fauxModule(temporaire: temporaire)
        let (sortie, lignes, dossier) = try Self.collecte([["id": 1, "fichier": "DSCF4123.RAF", "groupe": "X-T20 ISO 6400 et plus"],
                                                           ["id": 2, "fichier": "xh2s2.raf"]], lightroom: lightroom, racine: racine)
        XCTAssertEqual(sortie.code, 0)
        XCTAssertTrue(lignes[1]?["erreur"]?.string?.contains("autre photo") == true, "\(String(describing: lignes[1]))")
        XCTAssertNil(lignes[1]?["vignette"])
        XCTAssertNil(lignes[1]?["iso"], "ni la description de l'autre photo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dossier.appendingPathComponent("vignettes/1024/1.jpg").path))
        XCTAssertNotNil(lignes[2]?["vignette"], "le nom du fichier se compare sans la casse")
        XCTAssertEqual(lightroom.calls.first { $0.command == "journal" }?.params["photos"]?.array?.compactMap(\.int), [2])
        let restes = FileManager.default.enumerator(atPath: temporaire.path)?.compactMap { $0 as? String }.filter { $0.hasSuffix(".jpg") }
        XCTAssertEqual(restes, [], "le JPEG temporaire de l'autre photo est retiré aussi")
    }

    /// Revue du relevé : les catalogues de suivi.json ne se mêlent pas (leurs ids se recouvrent).
    func testLesEchantillonsNeMelentPasLesCatalogues() throws {
        let dossier = TestSupport.temporaryDirectory()
        let fichier = dossier.appendingPathComponent("suivi.json")
        let suivi = Self.suivi([Self.entree(1, "X-H2S", iso: 160, copies: [11])], autre: [Self.entree(2, "X-T20", iso: 6400)])
        try Data(JSONCoding.line(suivi).utf8).write(to: fichier)
        let refus = ReleveSeuils.commande(["--echantillons", fichier.path, dossier.appendingPathComponent("r").path], lightroom: Self.lightroomInterdit)
        XCTAssertEqual(refus.code, 2)
        XCTAssertTrue(refus.lignes.first?.contains("--catalogue") == true, refus.lignes.joined(separator: "\n"))
        XCTAssertEqual(ReleveSeuils.commande(["--echantillons", fichier.path, dossier.appendingPathComponent("r").path, "--catalogue", "/n/existe/pas.lrcat"],
                                             lightroom: Self.lightroomInterdit).code, 2)
        let sortie = ReleveSeuils.commande(["--echantillons", fichier.path, dossier.appendingPathComponent("r").path,
                                            "--catalogue", "/Volumes/Photos/Catalogue.lrcat"], lightroom: Self.lightroomInterdit)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        let lot = try JSONCoding.parse(Data(contentsOf: dossier.appendingPathComponent("r/lots/A1.json")))
        XCTAssertEqual(lot["catalogue"]?.string, "/Volumes/Photos/Catalogue.lrcat")
        XCTAssertEqual(lot["photos"]?.array?.compactMap { $0["id"]?.int }, [1], "rien de l'autre catalogue")
        let photo = try XCTUnwrap(lot["photos"]?.array?.first)
        XCTAssertEqual(photo["uuid"]?.string, "uuid-1")
        XCTAssertEqual(photo["fichier"]?.string, "F1.RAF")
        XCTAssertEqual(photo["copies"]?.array?.compactMap(\.int), [11])
        XCTAssertTrue(ReleveSeuils.candidates(suivi).isEmpty, "deux catalogues sans choix : aucune candidate")
    }

    /// Revue du relevé : le résumé ne compte une note pour Dany que si le journal a été lu, et lit
    /// la note de la famille, comme le tirage.
    func testLeResumeEcarteLesNotesDAuteurInconnu() {
        func ligne(_ id: Int, note: Int, suivi noteSuivi: Int? = nil, parClaude: Bool?) -> [String: JSONValue] {
            var l: [String: JSONValue] = ["id": .number(Double(id)), "lot": "A2", "groupe": "signalée", "note": .number(Double(note)),
                                          "note_famille": .number(Double(max(note, noteSuivi ?? 0))),
                                          "suivi": ["mesures": ["bruit": 0.4, "mediane_l": 40], "cherches": [], "defauts": []]]
            if let noteSuivi { l["note_suivi"] = .number(Double(noteSuivi)) }
            if let parClaude { l["note_par_claude"] = .bool(parClaude) }
            return l
        }
        let resume = ReleveSeuils.resumer([ligne(1, note: 4, parClaude: false), ligne(2, note: 4, parClaude: nil),
                                           ligne(3, note: 0, suivi: 4, parClaude: false), ligne(4, note: 5, parClaude: true),
                                           ligne(5, note: 4, parClaude: nil)], paires: []).json
        XCTAssertEqual(resume["notees_3_etoiles_par_dany"]?["n"]?.int, 2, "1, et 3 (copie notée 4 par Dany) ; ni 2 ni 5 (inconnues) ni 4 (Claude)")
        XCTAssertEqual(resume["notes_inconnues"]?.int, 2)
        XCTAssertEqual(resume["notes_autres_que_suivi"]?.int, 1)
    }

    // MARK: Mesure

    static func fleurs() -> Data {
        TestSupport.jpegPixels(width: 1000, height: 700) { x, _ in x < 300 ? (255, 30, 40) : (110, 120, 100) }
    }

    static func interieur() -> Data {
        TestSupport.jpegPixels(width: 1000, height: 700) { x, y in
            if x > 750, y < 175 { return (245, 245, 240) }
            return (90, 85, 80)
        }
    }

    func testLaMesureEcritSesFichiersSansLeModule() throws {
        let dossier = TestSupport.temporaryDirectory()
        try FileManager.default.createDirectory(at: dossier.appendingPathComponent("vignettes/1024"), withIntermediateDirectories: true)
        try Self.fleurs().write(to: dossier.appendingPathComponent("vignettes/1024/1.jpg"))
        try Self.interieur().write(to: dossier.appendingPathComponent("vignettes/1024/2.jpg"))
        let lignes: [JSONValue] = [
            ["id": 1, "lot": "A6", "groupe": "jour 2026-10-21", "appareil": "X-H2S", "iso": 400, "date": "2026-10-21 14:00:00",
             "ouverture": 4, "vitesse": 0.01, "flash": false, "note": 4, "note_par_claude": true, "retouchee_par_claude": false,
             "vignette": "vignettes/1024/1.jpg", "taille": 1024, "duree_lot_s": 3.5],
            ["id": 2, "lot": "A6", "groupe": "jour 2026-10-21", "appareil": "X-H2S", "iso": 400, "date": "2026-10-21 14:00:10",
             "ouverture": 4, "vitesse": 0.005, "flash": false, "note": 3, "note_par_claude": false, "retouchee_par_claude": false,
             "vignette": "vignettes/1024/2.jpg", "taille": 1024, "duree_lot_s": 3.5],
        ]
        try Data(lignes.map { JSONCoding.line($0) + "\n" }.joined().utf8).write(to: dossier.appendingPathComponent("catalogue.jsonl"))
        let sortie = ReleveSeuils.commande(["--mesurer", dossier.path], lightroom: Self.lightroomInterdit)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        for nom in ["mesures.jsonl", "mesures.csv", "paires.csv", "resume.txt", "resume.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dossier.appendingPathComponent(nom).path), nom)
        }
        let mesures = try ReleveSeuils.lireLignes(dossier.appendingPathComponent("mesures.jsonl"))
        XCTAssertEqual(mesures.count, 2)
        XCTAssertEqual(mesures[0]["ecretage"]?["nature"]?.string, "gamme", "un rouge saturé écrêté par la gamme")
        XCTAssertNotNil(mesures[0]["ecretage"]?["gamme_rejouee_pct"]?["bas220_c30"])
        XCTAssertNotNil(mesures[0]["suivi"]?["mesures"]?["bruit"], "les mesures du Suivi, telles quelles")
        XCTAssertGreaterThanOrEqual(mesures[1]["points_chauds"]?["zones"]?.int ?? 0, 1, "la fenêtre claire")
        XCTAssertNotNil(mesures[1]["points_chauds"]?["grille"]?["moyennes"], "la grille, pour rejouer d'autres seuils")
        XCTAssertNotNil(mesures[0]["groupe_lumiere"]?["numero"])

        let paires = try String(contentsOf: dossier.appendingPathComponent("paires.csv"), encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(paires.count, 2, "l'en-tête et une paire")
        XCTAssertTrue(paires[1].hasPrefix("jour 2026-10-21,1,2,10,1,0,0,"), String(paires[1]))

        let resume = try JSONCoding.parse(Data(contentsOf: dossier.appendingPathComponent("resume.json")))
        XCTAssertEqual(resume["notes_par_claude"]?.int, 1)
        XCTAssertEqual(resume["notees_3_etoiles_par_dany"]?["n"]?.int, 1, "la note de Claude est écartée")
        XCTAssertEqual(resume["dates_a_la_seconde"]?.int, 2)
        XCTAssertNotNil(resume["par_groupe"]?["jour 2026-10-21"])
        XCTAssertNotNil(resume["par_appareil_et_iso"]?["X-H2S ISO moins de 800"])
        let csv = try String(contentsOf: dossier.appendingPathComponent("mesures.csv"), encoding: .utf8)
        XCTAssertTrue(csv.hasPrefix("id,lot,groupe,fichier,appareil,iso,tranche_iso,"))
    }

    func testDesFichiersSeMesurentSansCatalogue() throws {
        let dossier = TestSupport.temporaryDirectory()
        let fichier = dossier.appendingPathComponent("fleurs.jpg")
        try Self.fleurs().write(to: fichier)
        let sortie = ReleveSeuils.commande(["--fichiers", dossier.appendingPathComponent("sortie").path, fichier.path],
                                           lightroom: Self.lightroomInterdit)
        XCTAssertEqual(sortie.code, 0, sortie.lignes.joined(separator: "\n"))
        let mesures = try ReleveSeuils.lireLignes(dossier.appendingPathComponent("sortie/mesures.jsonl"))
        XCTAssertEqual(mesures.first?["ecretage"]?["nature"]?.string, "gamme")
    }

    // MARK: Fonctions rejouées

    func testLaGrilleDesPointsChaudsDonneLesMemesZones() throws {
        let image = EcretageEtPointsChaudsTests.image { x, y in
            if x > 0.75, y < 0.25 { return (245, 245, 240) }
            if x < 0.3, y > 0.8 { return (225, 225, 220) }
            return (90, 85, 80)
        }
        let grille = try XCTUnwrap(PointsChauds.lireGrille(image))
        XCTAssertEqual(PointsChauds.zones(grille, sujet: []), PointsChauds.trouver(image, sujet: []), "trouver ne change pas")
        XCTAssertEqual(PointsChauds.zones(grille, sujet: []).count, 2)
        // L* minimal au-dessus de la nappe (L* vers 90) : la fenêtre seule.
        XCTAssertEqual(PointsChauds.zones(grille, sujet: [], lMin: 93).count, 1)
    }

    func testLaGammeRejoueeRetrouveLaMesureActuelle() throws {
        let image = try XCTUnwrap(PreviewImages.image(Self.fleurs()))
        let mesures = try XCTUnwrap(Measurements.analyze(PreviewImages.scaled(image, maxSide: Measurements.maxSide)))
        let rejouee = ReleveSeuils.gammeRejouee(image)
        XCTAssertEqual(try XCTUnwrap(rejouee["bas220_c30"]), mesures.clippedGamut, accuracy: 0.01)
        XCTAssertEqual(rejouee.count, ReleveSeuils.basesGamme.count * ReleveSeuils.chromasGamme.count)
    }

    func testCentilesEtChampsCSV() {
        XCTAssertEqual(ReleveSeuils.centile([5, 1, 3, 2, 4], 50), 3)
        XCTAssertEqual(ReleveSeuils.centile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90), 9)
        XCTAssertNil(ReleveSeuils.centile([], 50))
        XCTAssertEqual(ReleveSeuils.champ(.string("a, b")), "\"a, b\"")
        XCTAssertEqual(ReleveSeuils.champ(.number(3)), "3")
        XCTAssertEqual(ReleveSeuils.champ(.array(["flou", "bruit"])), "flou|bruit")
        XCTAssertEqual(ReleveSeuils.tranche(1599), "800-1599")
        XCTAssertEqual(ReleveSeuils.tranche(6400), "6400 et plus")
    }
}
