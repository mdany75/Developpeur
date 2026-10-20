import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Version 1.1 : le standard de notation, les plafonds mesurés par cull_photos, et propose_ratings
/// (notes proposées rangées par le module, hors du catalogue ; jamais 5 étoiles).
final class NotationTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Standard

    func testTheStandardIsTheSourceTextAndNeverOffersFiveStars() {
        let standard = Notation.standard
        XCTAssertTrue(standard.hasPrefix("# Standard de notation\n\nUne étoile dit un niveau de qualité, et rien d'autre."))
        XCTAssertTrue(standard.hasSuffix("3 » et une « presque 3 », de même entre 3 et 4, par genre."))
        for titre in ["## Les notes", "## Les critères, du plus lourd au plus léger", "## Selon le genre",
                      "## Les passes, une question à la fois", "## Ce que valent les mesures", "## Photos étalons"] {
            XCTAssertTrue(standard.contains("\n\(titre)\n"), titre)
        }
        XCTAssertTrue(standard.contains("l'utilisateur seul : Claude ne propose jamais 5 ★."))
        XCTAssertTrue(standard.contains("Netteté (moins de 15 : floue ; 15 à 35 : douce ; plus de 35 : nette)"))
        XCTAssertFalse(standard.contains("    "), "pas d'indentation du code Swift dans le texte")
        XCTAssertEqual(Notation.noteMaximale, 4)
        for mot in ["photoshop", "expand_photo", "firefly", "agrandissement", "galerie", "gallery", "concours", "mariage", "crédit adobe"] {
            XCTAssertFalse(standard.lowercased().contains(mot), mot)
        }
    }

    // MARK: Plafonds

    func photo(nettete: Double = 60, bruit: Double = 0.3) -> PhotoTriee {
        var p = PhotoTriee(id: 1, fichier: "DSCF1.RAF")
        p.detail = DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: bruit, shadowNoise: nil, side: 1024)
        return p
    }

    func testCeilingsFollowTheStandard() throws {
        // Sans défaut : 4, jamais 5.
        let nette = try XCTUnwrap(Notation.plafond(photo(), doublon: false))
        XCTAssertEqual(nette, Notation.Plafond(note: 4, raison: "aucun défaut mesuré : 4 au plus (5 : l'utilisateur seul)", rejet: false, aVerifier: false))
        // Floue : défaut majeur, rejet proposé.
        let floue = try XCTUnwrap(Notation.plafond(photo(nettete: 8), doublon: false))
        XCTAssertEqual(floue.note, 0)
        XCTAssertTrue(floue.rejet)
        XCTAssertTrue(floue.raison.hasPrefix("floue"))
        // Douce (15 à 35) : un défaut visible seulement à 100 %.
        let douce = try XCTUnwrap(Notation.plafond(photo(nettete: 24), doublon: false))
        XCTAssertEqual(douce.note, 3)
        XCTAssertFalse(douce.rejet)
        XCTAssertTrue(douce.raison.contains("douce (netteté 24"), douce.raison)
        // Mise au point manquée au point AF, nette ailleurs : rejet ; signalée par l'appareil : 3.
        var manquee = photo()
        manquee.af = .init(point: CGPoint(x: 0.3, y: 0.3), nettete: 8, avertissement: false)
        XCTAssertEqual(Notation.plafond(manquee, doublon: false)?.note, 0)
        XCTAssertEqual(Notation.plafond(manquee, doublon: false)?.rejet, true)
        var signalee = photo()
        signalee.af = .init(point: CGPoint(x: 0.3, y: 0.3), nettete: 20, avertissement: true)
        let parAppareil = try XCTUnwrap(Notation.plafond(signalee, doublon: false))
        XCTAssertEqual(parAppareil.note, 3)
        XCTAssertFalse(parAppareil.raison.contains("douce"), "un seul motif pour la même netteté")
        // Yeux fermés du sujet : rejet.
        var yeux = photo()
        yeux.vision = VisionReport(faces: [VisionReport.Face(box: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3), pupils: [], eyeWidth: nil,
                                                             quality: 0.5, eyeOpenness: 0.05)], aesthetics: nil, utility: false, salientArea: nil)
        XCTAssertEqual(Notation.plafond(yeux, doublon: false)?.note, 0)
        // Capture ou document selon Vision : 1.
        var document = photo()
        document.vision = VisionReport(faces: [], aesthetics: nil, utility: true, salientArea: nil)
        XCTAssertEqual(Notation.plafond(document, doublon: false)?.note, 1)
        // Pas la meilleure de sa rafale : 3 (un 4 est la meilleure vue de son moment).
        XCTAssertEqual(Notation.plafond(photo(), doublon: true)?.note, 3)
        // Vignette illisible : rien de mesuré, pas de plafond.
        var illisible = PhotoTriee(id: 2, fichier: "DSCF2.RAF")
        illisible.erreur = "pas de vignette"
        XCTAssertNil(Notation.plafond(illisible, doublon: false))
    }

    /// Presque noire ou brûlée : 2 et à vérifier, plus de rejet (rattrapable, surtout en RAW).
    func testExposureDefectsAreCheckedNotRejected() throws {
        var noire = photo()
        noire.mesures = Measurements.analyze(try XCTUnwrap(PreviewImages.image(TestSupport.jpeg(red: 4, green: 4, blue: 4))))
        noire.format = "RAW"
        let plafond = try XCTUnwrap(Notation.plafond(noire, doublon: false))
        XCTAssertEqual(plafond.note, 2)
        XCTAssertTrue(plafond.aVerifier)
        XCTAssertFalse(plafond.rejet)
        XCTAssertTrue(plafond.raison.contains("presque noire"))
        XCTAssertTrue(plafond.raison.contains("rattrapable par la retouche (RAW)"), plafond.raison)
        var brulee = photo()
        brulee.mesures = Measurements.analyze(try XCTUnwrap(PreviewImages.image(TestSupport.jpeg(red: 255, green: 255, blue: 255))))
        brulee.format = "JPG"
        let jpeg = try XCTUnwrap(Notation.plafond(brulee, doublon: false))
        XCTAssertEqual(jpeg.note, 2)
        XCTAssertTrue(jpeg.raison.contains("brûlée"))
        XCTAssertTrue(jpeg.raison.contains("à vérifier après la retouche"), jpeg.raison)
    }

    /// Bruit fort (plus de 1,5) : la photo se note après le débruitage ; à vérifier, sans plafond.
    func testStrongNoiseAsksToRateAfterDenoising() throws {
        let bruitee = try XCTUnwrap(Notation.plafond(photo(bruit: 1.8), doublon: false))
        XCTAssertEqual(bruitee.note, 4)
        XCTAssertTrue(bruitee.aVerifier)
        XCTAssertTrue(bruitee.raison.contains("après le débruitage"))
        XCTAssertFalse(try XCTUnwrap(Notation.plafond(photo(bruit: 1.2), doublon: false)).aVerifier)
        let bilan = Tri.bilan([{ var p = photo(bruit: 1.8); p.id = 7; return p }()])
        XCTAssertEqual(bilan["plafonds"]?["7"]?["a_verifier"]?.bool, true)
        XCTAssertEqual(bilan["plafonds"]?["7"]?["note_max"]?.int, 4)
    }

    // MARK: propose_ratings

    func proposition(_ id: Int, rating: Int? = nil, flag: String? = nil, aVerifier: Bool? = nil,
                     criteres: [String: JSONValue]? = nil, raison: String = "Nette, bien composée, sans plus.") -> JSONValue {
        var item: [String: JSONValue] = [
            "photo_id": .number(Double(id)), "reason": .string(raison),
            "criteria": .object(criteres ?? ["impact": "Moment ordinaire.", "qualities": "Lumière douce, sujet clair.", "technical_floor": "Nette (52)."]),
        ]
        if let rating { item["rating"] = .number(Double(rating)) }
        if let flag { item["flag"] = .string(flag) }
        if let aVerifier { item["to_check"] = .bool(aVerifier) }
        return .object(item)
    }

    func testProposeRatingsIsAReadOnlyToolWithATitle() throws {
        XCTAssertTrue(ToolHandler.toolNames.contains("propose_ratings"))
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "propose_ratings" })
        XCTAssertEqual(definition["title"]?.string, "Proposer des notes")
        XCTAssertEqual(definition["annotations"]?["readOnlyHint"]?.bool, true, "rien n'est écrit dans le catalogue")
        XCTAssertNotNil(definition["outputSchema"])
        let element = try XCTUnwrap(definition["inputSchema"]?["properties"]?["ratings"]?["items"])
        XCTAssertEqual(element["additionalProperties"]?.bool, false)
        XCTAssertEqual(element["properties"]?["criteria"]?["required"], ["impact", "qualities", "technical_floor"])
        let description = definition["description"]?.string ?? ""
        XCTAssertTrue(description.contains("Jamais 5 étoiles"))
        XCTAssertTrue(description.contains("read_standard"))
    }

    func testReadStandardReturnsItWithoutSendingAnything() throws {
        let result = tools.call(name: "propose_ratings", arguments: ["read_standard": true])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try JSONCoding.parse(result.text)["standard"]?.string, Notation.standard)
        XCTAssertEqual(result.structured?["standard"]?.string, Notation.standard)
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est rangé")
    }

    func testProposalsGoToTheModuleInOneCommandAndTheAnswerIsReturnedAsIs() throws {
        let reponse: JSONValue = ["seance": "s-12", "propositions": [["photo": 12, "fichier": "DSCF12.RAF", "note_avant": 0, "drapeau_avant": "aucun", "etat": "proposee"],
                                                                    ["photo": 13, "fichier": "DSCF13.RAF", "note_avant": 2, "drapeau_avant": "aucun", "etat": "proposee"]],
                                  "refusees": [["photo": 99, "raison": "photo introuvable"]]]
        fake.replies["notation"] = reponse
        let criteres: [String: JSONValue] = ["impact": "Le regard arrête l'œil.", "qualities": "Lumière de côté, fond calme.",
                                             "technical_floor": "Nette au point AF (61).", "finish": "Peau naturelle."]
        let result = tools.call(name: "propose_ratings", arguments: [
            "ratings": [proposition(12, rating: 3, criteres: criteres), proposition(13, flag: "reject", aVerifier: true)],
            "pass": 2, "session": " s-12 ",
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["notation"], "une seule commande")
        let params = fake.lastParams
        XCTAssertEqual(params["action"]?.string, "proposer")
        XCTAssertEqual(params["seance"]?.string, "s-12")
        XCTAssertEqual(params["passe"]?.int, 2)
        let propositions = try XCTUnwrap(params["propositions"]?.array)
        XCTAssertEqual(propositions.count, 2)
        XCTAssertEqual(propositions[0], ["photo": 12, "note": 3, "drapeau": "aucun",
                                         "criteres": ["impact": "Le regard arrête l'œil.", "qualites": "Lumière de côté, fond calme.",
                                                      "plancher": "Nette au point AF (61).", "finition": "Peau naturelle."],
                                         "raison": "Nette, bien composée, sans plus.", "a_verifier": false])
        XCTAssertEqual(propositions[1]["drapeau"]?.string, "rejetee", "rejet : l'orthographe qu'attend le module")
        XCTAssertEqual(propositions[1]["note"]?.int, 0)
        XCTAssertEqual(propositions[1]["a_verifier"]?.bool, true)
        XCTAssertNil(propositions[1]["criteres"]?["finition"], "Finition facultative")
        XCTAssertNil(propositions[0]["plafond"], "pas de tri : pas de plafond connu")
        XCTAssertEqual(try JSONCoding.parse(result.text), reponse, "la réponse du module, telle quelle")
        XCTAssertEqual(result.structured, reponse)

        // Sans passe ni séance : le module prend la séance ouverte ; avec read_standard, le standard en plus.
        _ = tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(12, rating: 2)], "read_standard": true])
        XCTAssertNil(fake.lastParams["passe"])
        XCTAssertNil(fake.lastParams["seance"])
        XCTAssertEqual(fake.calls.count, 2)
    }

    func testFiveStarsAreRefusedWithoutSendingAnything() {
        for note in [5, 6] {
            let result = tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(12, rating: 2), proposition(13, rating: note)]])
            XCTAssertTrue(result.isError)
            XCTAssertTrue(result.text.contains("Claude ne propose jamais 5 étoiles : c'est à l'utilisateur."), result.text)
            XCTAssertTrue(result.text.contains("ratings[1]"), result.text)
            XCTAssertTrue(result.text.contains("Rien n'a été rangé"))
        }
        XCTAssertTrue(fake.calls.isEmpty, "aucune proposition rangée, même la bonne")
    }

    /// parametresInconnus ne voit que le premier niveau : une clé inconnue dans une proposition (ou
    /// dans ses critères) est refusée à la main, avec la bonne clé quand elle s'en rapproche.
    func testUnknownNestedKeysAreRefused() {
        let note = tools.call(name: "propose_ratings", arguments: ["ratings": [["photo_id": 12, "note": 3, "reason": "x",
                                                                               "criteria": ["impact": "a", "qualities": "b", "technical_floor": "c"]]]])
        XCTAssertTrue(note.isError)
        XCTAssertTrue(note.text.contains("note (ici : « rating »)"), note.text)
        let critere = tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(12, rating: 3, criteres: [
            "impact": "a", "qualites": "b", "technical_floor": "c"])]])
        XCTAssertTrue(critere.isError)
        XCTAssertTrue(critere.text.contains("qualites (ici : « qualities »)"), critere.text)
        XCTAssertTrue(tools.call(name: "propose_ratings", arguments: ["rating": 3]).text.contains("Paramètres inconnus"), "premier niveau")
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testOtherInvalidProposalsAreRefusedWithoutSendingAnything() {
        let long = String(repeating: "é", count: 201)
        for (arguments, attendu) in [
            ([:], "« ratings »"),
            (["ratings": []], "read_standard = true donne le standard"),
            (["ratings": "12:3"], "doit être une liste"),
            (["ratings": [proposition(12, rating: 3, flag: "reject")]], "pas les deux"),
            (["ratings": [proposition(12)]], "rating (de 0 à 4) ou flag reject"),
            (["ratings": [proposition(12, flag: "pick")]], "seulement reject"),
            (["ratings": [proposition(12, rating: -1)]], "va de 0 à 4"),
            (["ratings": [.object(proposition(12, rating: 3).object!.merging(["rating": 2.5]) { $1 })]], "nombre entier"),
            (["ratings": [proposition(12, rating: 3, criteres: ["impact": "a", "qualities": " ", "technical_floor": "c"])]], "« criteria.qualities » vide"),
            (["ratings": [proposition(12, rating: 3, criteres: ["impact": "a", "qualities": "b"])]], "« criteria.technical_floor » vide"),
            (["ratings": [proposition(12, rating: 3, criteres: ["impact": .string(long), "qualities": "b", "technical_floor": "c"])]],
             "trop long (201 caractères, 200 au plus)"),
            (["ratings": [proposition(12, rating: 3, criteres: ["impact": "a", "qualities": "b", "technical_floor": "c", "finish": .string(long)])]],
             "« criteria.finish » trop long"),
            (["ratings": [proposition(12, rating: 3, raison: " ")]], "« reason »"),
            (["ratings": [proposition(12, rating: 3, raison: String(repeating: "a", count: 301))]], "trop longue (301 caractères, 300 au plus)"),
            (["ratings": [.object(proposition(12, rating: 3).object!.merging(["to_check": "oui"]) { $1 })]], "« to_check »"),
            (["ratings": [proposition(12, rating: 3), proposition(12, rating: 2)]], "photo 12 proposée deux fois"),
            (["ratings": [proposition(12, rating: 3)], "pass": 5], "« pass »"),
            (["ratings": [proposition(12, rating: 3)], "session": ""], "« session »"),
        ] as [([String: JSONValue], String)] {
            let result = tools.call(name: "propose_ratings", arguments: arguments)
            XCTAssertTrue(result.isError, "\(arguments)")
            XCTAssertTrue(result.text.contains(attendu), "« \(attendu) » absent de : \(result.text)")
        }
        // Toutes les erreurs d'un appel sont dites ensemble.
        let deux = tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(1, rating: 5), proposition(2, rating: 3, flag: "reject")]])
        XCTAssertTrue(deux.text.contains("ratings[0]") && deux.text.contains("ratings[1]"), deux.text)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    /// Le plafond mesuré par le dernier cull_photos de la photo borne la note proposée : refus
    /// au-dessus, sauf un défaut voulu, à vérifier ; le plafond part avec la proposition.
    func testRatingAboveTheMeasuredCeilingIsRefused() throws {
        let nette = TriTests.damier()
        let unie = TestSupport.jpeg(red: 120, green: 120, blue: 120, width: 1200, height: 800)
        var floues: Set<Int> = [3]
        fake.onSend = { [unowned fake] command, params in
            guard let fake, command == "vignettes" else { return }
            let ids = (params["photos"]?.array ?? []).compactMap(\.int)
            fake.replies["vignettes"] = ["photos": .array(ids.map { id in
                ["id": .number(Double(id)), "fichier": .string("DSCF\(id).RAF"), "drapeau": "aucun",
                 "vignette": .string(TestSupport.previewFile(floues.contains(id) ? unie : nette))]
            })]
        }
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["photo_ids": [3]]).isError)
        XCTAssertEqual(tools.dernierTri[3]?.note, 0)
        fake.calls = []

        let refus = tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(3, rating: 1)]])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("au-dessus du plafond mesuré par cull_photos (0 : floue"), refus.text)
        XCTAssertTrue(refus.text.contains("to_check = true"))
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est rangé")

        for permise in [proposition(3, rating: 0), proposition(3, flag: "reject"), proposition(3, rating: 1, aVerifier: true)] {
            let result = tools.call(name: "propose_ratings", arguments: ["ratings": [permise]])
            XCTAssertFalse(result.isError, result.text)
            XCTAssertEqual(fake.lastParams["propositions"]?.array?.first?["plafond"]?.int, 0, "le plafond part avec la proposition")
        }

        // Un nouveau tri remplace le plafond de la photo (retouchée, ou mieux vue).
        floues = []
        XCTAssertFalse(tools.call(name: "cull_photos", arguments: ["photo_ids": [3]]).isError)
        XCTAssertEqual(tools.dernierTri[3]?.note, 4)
        XCTAssertFalse(tools.call(name: "propose_ratings", arguments: ["ratings": [proposition(3, rating: 4)]]).isError)
    }
}
