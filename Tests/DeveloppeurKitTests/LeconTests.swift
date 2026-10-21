import XCTest
@testable import DeveloppeurKit

/// La leçon de la photo (1.3) : l'outil photo_lesson (Tools+Lecon) et sa partie pure (Lecon) :
/// trois points validés avant tout envoi, corrections nettes tirées du journal, indices à seuils
/// provisoires, faits, remarques, texte et forme envoyée au module. Par FakeLightroom : aucune
/// vraie photo, aucun vrai registre.
final class LeconTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Aides

    /// Trois points valides, dans le désordre (composition d'abord).
    func points(lumiere: [String: JSONValue]? = nil, couleur: [String: JSONValue]? = nil,
                composition: [String: JSONValue]? = nil) -> JSONValue {
        .array([
            .object(composition ?? ["axis": "composition", "missing": "L'horizon penchait de 1,8°.",
                                    "at_capture": "Afficher le niveau électronique du viseur.", "defects": ["tilted_horizon"]]),
            .object(lumiere ?? ["axis": "light", "missing": "Le ciel était brûlé : 3 % des pixels écrêtés au départ.",
                                "at_capture": "Exposer pour le ciel : −2/3 IL de compensation.", "defects": ["blown_highlights"]]),
            .object(couleur ?? ["axis": "color", "at_capture": "Balance des blancs juste à la prise de vue : à refaire.", "defects": []]),
        ])
    }

    func changement(_ cle: String, _ avant: JSONValue, _ apres: JSONValue) -> JSONValue {
        ["cle": .string(cle), "avant": avant, "apres": apres]
    }

    func entree(_ type: String, _ etape: String, _ changements: [JSONValue] = [], id: JSONValue? = nil) -> JSONValue {
        var objet: [String: JSONValue] = ["type": .string(type), "etape": .string(etape), "changements": .array(changements),
                                          "date": "2026-10-21 10:00"]
        if let id { objet["etape_id"] = id }
        return .object(objet)
    }

    /// La réponse du module à journal avec detaille : une photo décrite en entier et ses entrées.
    func repondreJournal(_ entrees: [JSONValue], id: Int = 53636309, fichier: String = "DSCF4961.RAF") {
        fake.replies["journal"] = ["photos": [[
            "photo": ["id": .number(Double(id)), "fichier": .string(fichier), "copie_virtuelle": false, "appareil": "X-H2S",
                      "objectif": "XF16-55mmF2.8 R LM WR", "iso": "ISO 400", "vitesse": "1/250 s", "ouverture": "ƒ/8,0",
                      "focale": "23 mm", "date": "2026-06-30 18:42:10", "format": "RAW",
                      "prise_de_vue_plus": ["compensation": "-0,7 IL", "flash": "Le flash ne s'est pas déclenché"]],
            "entrees": .array(entrees),
        ]]]
    }

    func mesures(hautes: Double = 0, ombres: Double = 0, a: Double = 0, b: Double = 0, part: Double = 30,
                 mediane: Double = 50) -> PhotoMeasurements {
        PhotoMeasurements(meanL: mediane, percentilesL: [1: 5, 5: 10, 25: mediane, 50: mediane, 75: mediane, 95: 90, 99: 95],
                          histogramL: [Double](repeating: 10, count: 10), clippedHighlights: hautes, pureWhite: 0,
                          crushedShadows: ombres, clippedChannels: [0, 0, 0], meanChroma: 12, saturatedShare: 0,
                          neutralA: a, neutralB: b, neutralShare: part, pixelCount: 512 * 341)
    }

    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func vue(_ mesures: PhotoMeasurements, photo: Int = 53636309, fichier: String = "DSCF4961.RAF", apres secondes: Double = 0,
             taille: Int = 1344, etapes: Int? = 0) -> Bilan.Vue {
        Bilan.Vue(photo: photo, fichier: fichier, quand: t0.addingTimeInterval(secondes), taille: taille, cadre: "cadre", etat: "état",
                  etapes: etapes, derniereEtape: nil, mesures: mesures, detail: nil, neutres: nil, iaEnAttente: false,
                  corrections: nil, grain: 0)
    }

    func appeler(_ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: "photo_lesson", arguments: arguments)
    }

    func cles(_ indices: [Lecon.Indice]) -> [String] { indices.map(\.defaut.cle) }

    // MARK: L'outil

    /// 36 outils (avec read_composition), photo_lesson à la fin, en lecture seule, avec son titre.
    func testLessonToolIsListedReadOnlyWithItsTitle() throws {
        XCTAssertEqual(ToolHandler.toolNames.count, 36)
        XCTAssertEqual(ToolHandler.toolNames.last, "photo_lesson")
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "photo_lesson" })
        XCTAssertEqual(definition["title"]?.string, "Leçon de la photo")
        XCTAssertEqual(definition["annotations"]?["readOnlyHint"]?.bool, true)
        XCTAssertNil(definition["annotations"]?["destructiveHint"])
    }

    /// La description tient en 1 200 caractères, et chaque moitié de point en 140.
    func testLessonDescriptionStaysShort() throws {
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "photo_lesson" })
        let description = try XCTUnwrap(definition["description"]?.string)
        XCTAssertLessThanOrEqual(description.count, 1200, "\(description.count) caractères")
        XCTAssertEqual(ToolHandler.longueurPointLecon, Lecon.longueurPoint)
        XCTAssertEqual(Lecon.longueurPoint, 140)
    }

    /// Sans points ni read_facts, un refus qui explique les trois points ; points avec read_facts,
    /// un refus aussi ; rien n'est envoyé.
    func testLessonWithoutPointsIsRefusedAndSendsNothing() {
        let sans = appeler([:])
        XCTAssertTrue(sans.isError)
        XCTAssertTrue(sans.text.contains("light, color et composition"), sans.text)
        XCTAssertTrue(sans.text.contains("read_facts = true"), sans.text)
        XCTAssertTrue(appeler(["read_facts": false]).isError)
        let deux = appeler(["points": points(), "read_facts": true])
        XCTAssertTrue(deux.isError)
        XCTAssertTrue(deux.text.contains("sans points"), deux.text)
        XCTAssertTrue(appeler(["points": points(), "photo_id": "sept"]).isError)
        XCTAssertTrue(appeler(["points": ["axis": "light"]]).isError, "points doit être une liste")
        XCTAssertTrue(fake.calls.isEmpty, "\(fake.commands)")
        XCTAssertTrue(fake.lecons.isEmpty)
    }

    /// Exactement trois points, chaque axe une fois, at_capture non vide, moitiés de 140 caractères
    /// au plus : sinon une erreur d'outil, et rien n'est envoyé (ni journal ni lecon).
    func testLessonNeedsTheThreeAxesOnce() throws {
        repondreJournal([])
        let lumiere: [String: JSONValue] = ["axis": "light", "at_capture": "Compensation +1/3 IL."]
        let deuxPoints: JSONValue = .array(Array(points().array!.prefix(2)))
        let enDouble = points(couleur: ["axis": "light", "at_capture": "Encore la lumière."])
        let inconnu = points(couleur: ["axis": "colour", "at_capture": "x"])
        let enFrancais = points(couleur: ["axis": "couleur", "at_capture": "x"])
        let vide = points(lumiere: ["axis": "light", "at_capture": "   \n "])
        let sansCapture = points(lumiere: ["axis": "light", "missing": "Trop sombre."])
        let long = points(lumiere: ["axis": "light", "missing": .string(String(repeating: "é", count: 141)), "at_capture": "x"])
        let longCapture = points(lumiere: ["axis": "light", "at_capture": .string(String(repeating: "a", count: 141))])
        let pasUnTexte = points(lumiere: ["axis": "light", "at_capture": 3])
        let cas: [(JSONValue, String)] = [
            (deuxPoints, "trois points, un par axe"), (enDouble, "l'axe « light » est donné deux fois"),
            (inconnu, "axe inconnu « colour »"), (enFrancais, "axe inconnu « couleur » (ici : « color »)"),
            (vide, "« at_capture » manque"), (sansCapture, "« at_capture » manque"),
            (long, "« missing » trop long (141 caractères, 140 au plus)"), (longCapture, "« at_capture » trop long"),
            (pasUnTexte, "« at_capture » : un texte"),
        ]
        for (donnes, attendu) in cas {
            let resultat = appeler(["points": donnes])
            XCTAssertTrue(resultat.isError, attendu)
            XCTAssertTrue(resultat.text.contains(attendu), "\(attendu) ≠ \(resultat.text)")
            XCTAssertTrue(resultat.text.contains("Rien n'a été rangé"), resultat.text)
        }
        XCTAssertTrue(fake.calls.isEmpty, "\(fake.commands)")
        XCTAssertTrue(fake.lecons.isEmpty)

        // 140 caractères tout juste : accepté ; les blancs sont ramenés à une espace.
        let juste = points(lumiere: lumiere.merging(["missing": .string(String(repeating: "é", count: 140))]) { $1 })
        XCTAssertFalse(appeler(["points": juste]).isError)
        let propres = try Lecon.points(points(lumiere: ["axis": "light", "at_capture": "  Exposer\n pour   le ciel. "]).array!)
        XCTAssertEqual(propres.map(\.axe), [.lumiere, .couleur, .composition], "rendus dans l'ordre des axes")
        XCTAssertEqual(propres[0].priseDeVue, "Exposer pour le ciel.")
        XCTAssertNil(propres[0].manque, "missing absent : rien ne manquait")
        XCTAssertNil(try Lecon.points(points(lumiere: ["axis": "light", "missing": "", "at_capture": "x"]).array!)[0].manque)
    }

    /// Une clé inconnue d'un point est refusée à la main, avec son nom proche (parametresInconnus
    /// ne voit que le premier niveau).
    func testUnknownPointKeyIsRefusedWithItsNearName() {
        let resultat = appeler(["points": points(lumiere: ["axe": "light", "at_capture": "x"])])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(resultat.text.contains("axe (ici : « axis »)"), resultat.text)
        let autre = appeler(["points": points(couleur: ["axis": "color", "prise_de_vue": "x", "at_capture": "y"])])
        XCTAssertTrue(autre.text.contains("prise_de_vue (ici : « at_capture »)"), autre.text)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    /// Un défaut nommé est connu et de l'axe de son point.
    func testDefectMustBelongToItsAxis() {
        let horsAxe = appeler(["points": points(lumiere: ["axis": "light", "at_capture": "x", "defects": ["tilted_horizon"]])])
        XCTAssertTrue(horsAxe.isError)
        XCTAssertTrue(horsAxe.text.contains("« tilted_horizon » est un défaut de l'axe composition, pas de light"), horsAxe.text)
        XCTAssertTrue(horsAxe.text.contains("underexposed"), "les défauts de l'axe sont rappelés")
        let inconnu = appeler(["points": points(lumiere: ["axis": "light", "at_capture": "x", "defects": ["sous_exposition"]])])
        XCTAssertTrue(inconnu.text.contains("défaut inconnu \"sous_exposition\""), inconnu.text)
        XCTAssertTrue(appeler(["points": points(lumiere: ["axis": "light", "at_capture": "x", "defects": "noise"])]).isError)
        XCTAssertTrue(fake.calls.isEmpty)
        // Un défaut donné deux fois ne compte qu'une fois.
        let doubles = try? Lecon.points(points(lumiere: ["axis": "light", "at_capture": "x", "defects": ["noise", "noise", "blur"]]).array!)
        XCTAssertEqual(doubles?[0].defauts.map(\.cle), ["noise", "blur"])
    }

    // MARK: Corrections nettes

    /// retouche, retouche, annulation « passe 2 », classement, retour, retouche : seule la dernière
    /// compte, avec son avant et son après.
    func testNetCorrectionsSkipUndoneStepsAndRevert() {
        let journal: [JSONValue] = [
            entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0, 0.6)]),
            entree("retouche", "Claude · passe 2", [changement("Contrast2012", 0, 20)]),
            entree("annulation", "Annulation de « Claude · passe 2 »"),
            entree("classement", "Claude · note", [changement("note", 0, 3)]),
            entree("retour", "Retour à l'état d'avant Claude"),
            entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0.1, 0.4), changement("Vibrance", 0, 15)]),
        ]
        let nettes = Lecon.correctionsNettes(journal)
        XCTAssertEqual(nettes.map(\.cle), ["Exposure2012", "Vibrance"])
        XCTAssertEqual(nettes[0].avant, 0.1)
        XCTAssertEqual(nettes[0].apres, 0.4)
        XCTAssertFalse(nettes[0].exercice)

        // Sans le retour : passe 1 et la retouche suivante s'enchaînent (premier avant, dernier
        // après) ; la passe 2 annulée n'y est pas ; un classement n'est pas une correction.
        var sansRetour = journal
        sansRetour.remove(at: 4)
        let enchainees = Lecon.correctionsNettes(sansRetour)
        XCTAssertEqual(enchainees.map(\.cle), ["Exposure2012", "Vibrance"])
        XCTAssertEqual(enchainees[0].avant, 0)
        XCTAssertEqual(enchainees[0].apres, 0.4)
    }

    /// L'annulation retire l'entrée de même etape_id quand il existe, sinon celle de son nom entre
    /// « », sinon la dernière ; une clé revenue à sa valeur d'avant n'est pas une correction.
    func testUndoMatchesTheStepIdThenItsName() {
        let parId = Lecon.correctionsNettes([
            entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0, 0.5)], id: "e1"),
            entree("retouche", "Claude · passe 1", [changement("Shadows2012", 0, 30)], id: "e2"),
            entree("annulation", "Annulation de « Claude · passe 1 »", id: "e1"),
        ])
        XCTAssertEqual(parId.map(\.cle), ["Shadows2012"], "l'identifiant l'emporte sur le nom")
        let idNombre = Lecon.correctionsNettes([
            entree("retouche", "a", [changement("Exposure2012", 0, 0.5)], id: 12),
            entree("retouche", "b", [changement("Shadows2012", 0, 30)], id: 13),
            entree("annulation", "Annulation de « b »", id: 12),
        ])
        XCTAssertEqual(idNombre.map(\.cle), ["Shadows2012"])
        let parNom = Lecon.correctionsNettes([
            entree("retouche", "Claude · passe « 1 »", [changement("Exposure2012", 0, 0.5)]),
            entree("retouche", "Claude · passe 2", [changement("Shadows2012", 0, 30)]),
            entree("annulation", "Annulation de « Claude · passe « 1 » »"),
        ])
        XCTAssertEqual(parNom.map(\.cle), ["Shadows2012"], "le nom entre les premiers « et les derniers »")
        let derniere = Lecon.correctionsNettes([
            entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0, 0.5)]),
            entree("retouche", "Claude · passe 2", [changement("Shadows2012", 0, 30)]),
            entree("annulation", "Annulation"),
        ])
        XCTAssertEqual(derniere.map(\.cle), ["Exposure2012"])
        let revenue = Lecon.correctionsNettes([
            entree("retouche", "a", [changement("Exposure2012", 0, 0.5), changement("Profil", "Adobe Color", "Classic Neg")]),
            entree("retouche", "b", [changement("Exposure2012", 0.5, 0.0000001)]),
            .string("pas une entrée"), ["type": "inconnu"],
        ])
        XCTAssertEqual(revenue.map(\.cle), ["Profil"], "l'exposition est revenue à 0")
        XCTAssertEqual(Lecon.etapeAnnulee("Annulation de « Claude · passe 2 »"), "Claude · passe 2")
        XCTAssertNil(Lecon.etapeAnnulee("Annulation de «  »"))
    }

    /// Une entrée « exercice » (Je le fais) : la version de Claude, jamais appliquée ; aucune
    /// annulation ne la défait ; une valeur appliquée avant elle reste dite.
    func testExerciseCountsAsClaudesVersionNeverApplied() {
        let passe1 = entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0, 0.3)])
        let exercice = entree("exercice", "Claude · je le fais", [changement("Exposure2012", 0.3, 0.8), changement("Dehaze", 0, 12)])
        let nettes = Lecon.correctionsNettes([passe1, exercice])
        XCTAssertEqual(nettes.map(\.cle), ["Exposure2012", "Dehaze"])
        XCTAssertEqual(nettes[0], Lecon.Correction(cle: "Exposure2012", avant: 0, apres: 0.8, exercice: true, appliquee: 0.3))
        XCTAssertEqual(nettes[1], Lecon.Correction(cle: "Dehaze", avant: 0, apres: 12, exercice: true, appliquee: nil))

        // Une annulation sans nom retrouvé défait la dernière étape appliquée, jamais l'exercice.
        let annulee = Lecon.correctionsNettes([passe1, exercice, entree("annulation", "Annulation de « Claude · je le fais »")])
        XCTAssertEqual(annulee.map(\.cle), ["Exposure2012", "Dehaze"])
        XCTAssertEqual(annulee[0].avant, 0.3, "la passe 1 est défaite")
        XCTAssertNil(annulee[0].appliquee)
        XCTAssertTrue(annulee.allSatisfy(\.exercice))

        // Claude applique ensuite sa version : appliquée, plus un exercice.
        let appliquee = Lecon.correctionsNettes([passe1, exercice, entree("retouche", "Claude · ma version", [changement("Exposure2012", 0.3, 0.8)])])
        XCTAssertEqual(appliquee[0], Lecon.Correction(cle: "Exposure2012", avant: 0, apres: 0.8))
        XCTAssertTrue(appliquee[1].exercice)
        // Un retour vide aussi l'exercice.
        XCTAssertTrue(Lecon.correctionsNettes([passe1, exercice, entree("retour", "Retour à l'état d'avant Claude")]).isEmpty)
    }

    // MARK: Indices

    /// Exposition +1,1, CropAngle −1,8, Temperature 5 600 → 5 000 et Highlights −60 avec un départ
    /// écrêté à 3 % donnent leurs quatre indices ; juste sous chaque seuil, aucun.
    func testIndicesFromClaudesCorrections() {
        let depart = vue(mesures(hautes: 3))
        let corrections = [
            Lecon.Correction(cle: "Exposure2012", avant: 0, apres: 1.1),
            Lecon.Correction(cle: "CropAngle", avant: 0, apres: -1.8),
            Lecon.Correction(cle: "Temperature", avant: 5600, apres: 5000),
            Lecon.Correction(cle: "Highlights2012", avant: 0, apres: -60),
        ]
        let indices = Lecon.indices(corrections: corrections, depart: depart)
        XCTAssertEqual(cles(indices), ["tilted_horizon", "underexposed", "blown_highlights", "color_cast"], "ordre de PriseDeVue")
        let preuves = Dictionary(uniqueKeysWithValues: indices.map { ($0.defaut.cle, $0.preuve) })
        XCTAssertEqual(preuves["underexposed"], "Exposition +1,10 IL (0,00 → 1,10)")
        XCTAssertEqual(preuves["tilted_horizon"], "Recadrage : angle −1,8° (0,0 → −1,8)")
        XCTAssertEqual(preuves["color_cast"], "Température −600 K (5600 → 5000)")
        XCTAssertEqual(preuves["blown_highlights"], "Hautes lumières −60 (0 → −60) ; au départ, 3,0 % de hautes lumières écrêtées")

        let sous = [
            Lecon.Correction(cle: "Exposure2012", avant: 0, apres: 0.49),
            Lecon.Correction(cle: "CropAngle", avant: 0, apres: -0.49),
            Lecon.Correction(cle: "Temperature", avant: 5600, apres: 5201),
            Lecon.Correction(cle: "Highlights2012", avant: 0, apres: -39),
            Lecon.Correction(cle: "Whites2012", avant: 0, apres: -29),
            Lecon.Correction(cle: "Shadows2012", avant: 0, apres: 39),
            Lecon.Correction(cle: "Blacks2012", avant: 0, apres: 24),
            Lecon.Correction(cle: "Dehaze", avant: 0, apres: 9),
            Lecon.Correction(cle: "LuminanceSmoothing", avant: 0, apres: 19),
            Lecon.Correction(cle: "Tint", avant: 5, apres: 14),
            Lecon.Correction(cle: "PerspectiveVertical", avant: 0, apres: -9),
        ]
        XCTAssertEqual(cles(Lecon.indices(corrections: sous, depart: vue(mesures(hautes: 3, ombres: 5)))), [])
        XCTAssertEqual(cles(Lecon.indices(corrections: [Lecon.Correction(cle: "Exposure2012", avant: 0.2, apres: -0.3)], depart: nil)),
                       ["overexposed"])
    }

    /// Température relative d'un JPEG (sous 1 000) : 10 suffisent ; en kelvins, 400.
    func testTemperatureScaleOfAJpeg() {
        XCTAssertEqual(cles(Lecon.indices(corrections: [Lecon.Correction(cle: "Temperature", avant: 0, apres: 10)], depart: nil)), ["color_cast"])
        XCTAssertEqual(cles(Lecon.indices(corrections: [Lecon.Correction(cle: "Temperature", avant: 0, apres: -9)], depart: nil)), [])
        XCTAssertEqual(cles(Lecon.indices(corrections: [Lecon.Correction(cle: "Temperature", avant: 5000, apres: 5399)], depart: nil)), [])
        XCTAssertEqual(cles(Lecon.indices(corrections: [Lecon.Correction(cle: "Tint", avant: 0, apres: -10)], depart: nil)), ["color_cast"])
    }

    /// Les hautes lumières et les ombres ne comptent que si la vue de départ les montre (ou s'il n'y
    /// en a pas) ; la dominante de départ ne compte que sur une photo pas encore retouchée.
    func testDepartureGatesHighlightsShadowsAndCast() {
        let hautes = [Lecon.Correction(cle: "Whites2012", avant: 0, apres: -30)]
        XCTAssertEqual(cles(Lecon.indices(corrections: hautes, depart: vue(mesures(hautes: 0.4)))), [])
        XCTAssertEqual(cles(Lecon.indices(corrections: hautes, depart: vue(mesures(hautes: 0.5)))), ["blown_highlights"])
        let sansDepart = Lecon.indices(corrections: hautes, depart: nil)
        XCTAssertEqual(cles(sansDepart), ["blown_highlights"])
        XCTAssertTrue(sansDepart[0].preuve.contains("sans vue de départ mesurée"), sansDepart[0].preuve)

        let ombres = [Lecon.Correction(cle: "Shadows2012", avant: 0, apres: 40), Lecon.Correction(cle: "Blacks2012", avant: 0, apres: 25)]
        XCTAssertEqual(cles(Lecon.indices(corrections: ombres, depart: vue(mesures(ombres: 1.9)))), [])
        let bouchees = Lecon.indices(corrections: ombres, depart: vue(mesures(ombres: 2)))
        XCTAssertEqual(cles(bouchees), ["crushed_shadows"])
        XCTAssertTrue(bouchees[0].preuve.hasPrefix("Ombres +40 (0 → 40) ; Noirs +25 (0 → 25) ; au départ, 2,0 %"), bouchees[0].preuve)

        XCTAssertEqual(cles(Lecon.indices(corrections: [], depart: vue(mesures(b: 6.5)))), ["color_cast"])
        XCTAssertEqual(cles(Lecon.indices(corrections: [], depart: vue(mesures(b: 5.9)))), [])
        XCTAssertEqual(cles(Lecon.indices(corrections: [], depart: vue(mesures(a: -7), etapes: 2))), [], "déjà retouchée : pas l'état de la prise de vue")
        XCTAssertEqual(cles(Lecon.indices(corrections: [], depart: vue(mesures(a: -7, part: 2)))), [], "trop peu de tons neutres")
    }

    /// Voile, bruit (débruitage lancé ou lissage), verticales (Upright posé ou perspective) et
    /// cadrage (cadre resserré sans rotation ni Upright).
    func testOtherMeasuredDefects() {
        func indices(_ corrections: [Lecon.Correction]) -> [String] { cles(Lecon.indices(corrections: corrections, depart: nil)) }
        XCTAssertEqual(indices([Lecon.Correction(cle: "Dehaze", avant: 0, apres: 10)]), ["flat_light"])
        XCTAssertEqual(indices([Lecon.Correction(cle: "Amelioration.denoise", avant: 0, apres: 35)]), ["noise"])
        XCTAssertEqual(indices([Lecon.Correction(cle: "Amelioration.denoise", avant: 35, apres: 50)]), [], "déjà actif")
        XCTAssertEqual(indices([Lecon.Correction(cle: "LuminanceSmoothing", avant: 0, apres: 20)]), ["noise"])
        XCTAssertEqual(indices([Lecon.Correction(cle: "PerspectiveUpright", avant: 0, apres: 5)]), ["converging_verticals"])
        XCTAssertEqual(indices([Lecon.Correction(cle: "PerspectiveUpright", avant: 3, apres: 5)]), [])
        XCTAssertEqual(indices([Lecon.Correction(cle: "PerspectiveVertical", avant: 0, apres: -10)]), ["converging_verticals"])
        let cadre = [Lecon.Correction(cle: "CropLeft", avant: 0, apres: 0.1), Lecon.Correction(cle: "CropRight", avant: 1, apres: 0.9)]
        XCTAssertEqual(indices(cadre), ["loose_framing"], "80 % de l'image")
        let preuve = Lecon.indices(corrections: cadre, depart: nil).first?.preuve
        XCTAssertEqual(preuve, "cadre resserré par Claude à 80 % de l'image (avant : 100 %)")
        XCTAssertEqual(indices([Lecon.Correction(cle: "CropLeft", avant: 0, apres: 0.07), Lecon.Correction(cle: "CropRight", avant: 1, apres: 0.93)]),
                       [], "86 % : sous le seuil")
        XCTAssertEqual(indices(cadre + [Lecon.Correction(cle: "CropAngle", avant: 0, apres: 1.2)]), ["tilted_horizon"], "resserré par la rotation")
        XCTAssertEqual(indices(cadre + [Lecon.Correction(cle: "PerspectiveUpright", avant: 0, apres: 1)]), ["converging_verticals"])
        XCTAssertEqual(indices([Lecon.Correction(cle: "CropLeft", avant: 0.2, apres: 0.1)]), [], "cadre élargi")
        XCTAssertEqual(indices([Lecon.Correction(cle: "Exposure2012", avant: "x", apres: .array([]))]), [], "valeurs illisibles")
    }

    // MARK: L'outil, de bout en bout

    /// Les commandes journal (photos [id], detaille vrai) puis lecon (action garder, clés
    /// françaises, points dans l'ordre des axes) ; un indice que la leçon ne nomme pas donne une
    /// remarque ; texte, faits et réponse du module.
    func testLessonGoesToTheModuleWithFactsAndRemarks() throws {
        repondreJournal([
            entree("retouche", "Claude · passe 1", [changement("Exposure2012", 0, 1.1), changement("CropAngle", 0, -1.8),
                                                     changement("Highlights2012", 0, -60), changement("ToneCurvePV2012", .array([0, 0]), .array([0, 10]))]),
        ])
        fake.replies["lecon"] = ["photo": 53636309, "original": 53636309, "fichier": "DSCF4961.RAF", "rangee": true, "remplacee": true,
                                 "mois": "2026-06", "prise_le": "2026-06-30 18:42"]
        let resultat = appeler(["photo_id": 53636309, "points": points()])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try XCTUnwrap(resultat.structured)

        XCTAssertEqual(fake.commands, ["journal"])
        XCTAssertEqual(fake.calls[0].params["photos"], [53636309])
        XCTAssertEqual(fake.calls[0].params["detaille"], true)
        XCTAssertEqual(fake.calls[0].timeout, 60)
        XCTAssertEqual(fake.lecons.count, 1)
        let envoi = fake.lecons[0]
        XCTAssertEqual(envoi["action"], "garder")
        XCTAssertEqual(envoi["photo"], 53636309)
        let envoyes = try XCTUnwrap(envoi["lecon"]?["points"]?.array)
        XCTAssertEqual(envoyes.map { $0["axe"]?.string }, ["lumiere", "couleur", "composition"])
        XCTAssertEqual(envoyes[0]["manque"], "Le ciel était brûlé : 3 % des pixels écrêtés au départ.")
        XCTAssertEqual(envoyes[0]["defauts"], [["code": "ciel_brule", "libelle": "Ciel ou haut de l'image brûlé"]])
        XCTAssertNil(envoyes[1]["manque"], "rien ne manquait")
        XCTAssertEqual(envoyes[1]["defauts"], [])
        XCTAssertEqual(envoyes[2]["prise_de_vue"], "Afficher le niveau électronique du viseur.")
        let indices = try XCTUnwrap(envoi["lecon"]?["indices"]?.array)
        XCTAssertEqual(indices.map { $0["code"]?.string }, ["horizon_penche", "sous_exposition", "ciel_brule"])
        XCTAssertEqual(indices[1]["axe"], "lumiere")

        XCTAssertEqual(reponse["lecon"], ["photo": 53636309, "fichier": "DSCF4961.RAF", "rangee": true, "remplacee": true,
                                          "mois": "2026-06", "prise_le": "2026-06-30 18:42"])
        let texte = try XCTUnwrap(reponse["texte"]?.string)
        XCTAssertTrue(texte.hasPrefix("Leçon de la photo · DSCF4961.RAF"), texte)
        XCTAssertTrue(texte.contains("- Lumière — Ce qui manquait : Le ciel était brûlé"), texte)
        XCTAssertTrue(texte.contains("- Couleur — Rien ne manquait. À refaire : Balance des blancs juste"), texte)
        XCTAssertLessThan(try XCTUnwrap(texte.range(of: "Lumière")).lowerBound, try XCTUnwrap(texte.range(of: "Composition")).lowerBound)
        // La sous-exposition mesurée n'est pas nommée : une remarque, sans refus.
        let remarques = reponse["remarques"]?.array?.compactMap(\.string) ?? []
        XCTAssertEqual(remarques.count, 1, "\(remarques)")
        XCTAssertTrue(remarques[0].hasPrefix("Mesuré : Exposition +1,10 IL"), remarques[0])
        XCTAssertTrue(remarques[0].contains("la leçon ne nomme pas « Photo sous-exposée » (underexposed)"), remarques[0])

        let faits = try XCTUnwrap(reponse["faits"])
        XCTAssertEqual(faits["prise_de_vue"]?["iso"], "ISO 400")
        XCTAssertEqual(faits["prise_de_vue"]?["prise_de_vue_plus"]?["compensation"], "-0,7 IL")
        let corrections = faits["corrections"]?.array ?? []
        XCTAssertEqual(corrections.map { $0["cle"]?.string }, ["Exposure2012", "CropAngle", "Highlights2012"], "valeurs simples seulement")
        XCTAssertEqual(corrections[0]["libelle"], "Exposition")
        XCTAssertEqual(corrections[0]["apres"], 1.1)
        XCTAssertEqual(faits["indices"]?.array?.map { $0["defect"]?.string }, ["tilted_horizon", "underexposed", "blown_highlights"])
        XCTAssertTrue(faits["depart"]?.string?.hasPrefix("aucune vue mesurée") == true, "pas de view_photo dans ce processus")
        XCTAssertTrue(faits["seuils"]?.string?.hasPrefix("provisoires") == true)
    }

    /// read_facts : les faits seuls ; seule la commande journal part, rien n'est rangé.
    func testReadFactsStoresNothing() throws {
        repondreJournal([entree("retouche", "Claude · passe 1", [changement("Temperature", 5600, 5000)])])
        let resultat = appeler(["read_facts": true])
        XCTAssertFalse(resultat.isError, resultat.text)
        XCTAssertEqual(fake.commands, ["journal"])
        XCTAssertNil(fake.calls[0].params["photos"], "la photo active")
        XCTAssertEqual(fake.calls[0].params["detaille"], true)
        XCTAssertTrue(fake.lecons.isEmpty)
        let reponse = try XCTUnwrap(resultat.structured)
        XCTAssertEqual(reponse["rangee"], false)
        XCTAssertEqual(reponse["photo"], ["id": 53636309, "fichier": "DSCF4961.RAF"])
        XCTAssertNil(reponse["lecon"])
        XCTAssertEqual(reponse["faits"]?["indices"]?.array?.map { $0["defect"]?.string }, ["color_cast"])
    }

    /// Le départ est la plus ancienne vue mesurée de la session pour cette photo, toutes tailles
    /// confondues ; une vue d'un autre fichier sous le même identifiant est ignorée.
    func testDepartureComesFromTheFirstViewOfTheSession() throws {
        let id = 53636309
        tools.vuesMesurees[Bilan.Cle(photo: id, taille: 1344)] = Bilan.Suivi(depart: vue(mesures(hautes: 0.1), apres: 60),
                                                                             precedente: vue(mesures(), apres: 300))
        tools.vuesMesurees[Bilan.Cle(photo: id, taille: 2048)] = Bilan.Suivi(depart: vue(mesures(hautes: 3), apres: 10, taille: 2048, etapes: 0),
                                                                             precedente: vue(mesures(), apres: 200, taille: 2048))
        tools.vuesMesurees[Bilan.Cle(photo: id, taille: 512)] = Bilan.Suivi(depart: vue(mesures(), fichier: "AUTRE.RAF", apres: 0, taille: 512),
                                                                            precedente: vue(mesures(), fichier: "AUTRE.RAF", taille: 512))
        tools.vuesMesurees[Bilan.Cle(photo: 1, taille: 1344)] = Bilan.Suivi(depart: vue(mesures(), photo: 1, apres: -50),
                                                                            precedente: vue(mesures(), photo: 1))
        XCTAssertEqual(tools.departDeLaSession(photo: id, fichier: "DSCF4961.RAF")?.taille, 2048)
        XCTAssertEqual(tools.departDeLaSession(photo: id, fichier: "AUTRE.RAF")?.taille, 512)
        XCTAssertNil(tools.departDeLaSession(photo: 2, fichier: "DSCF4961.RAF"))

        repondreJournal([entree("retouche", "Claude · passe 1", [changement("Highlights2012", 0, -50)])])
        let reponse = try XCTUnwrap(appeler(["read_facts": true]).structured)
        let depart = try XCTUnwrap(reponse["faits"]?["depart"])
        XCTAssertTrue(depart["vue"]?.string?.hasPrefix("premier view_photo de la session, à 2048 px") == true, "\(depart)")
        XCTAssertEqual(depart["hautes_lumieres_ecretees_pct"], 3)
        XCTAssertEqual(depart["etapes_claude"], "aucune : la photo telle qu'elle était avant Claude")
        // Le départ écrêté (3 %, celui de 2048 px) confirme l'indice ; celui de 1344 px (0,1 %) non.
        XCTAssertEqual(reponse["faits"]?["indices"]?.array?.map { $0["defect"]?.string }, ["blown_highlights"])
    }

    /// Un module d'avant la 1.3 (« Commande inconnue : lecon ») : la leçon et ses faits sont rendus,
    /// rangee faux, une remarque dit de relancer Lightroom ; jamais une erreur d'outil. Une autre
    /// erreur du rangement de même, avec sa raison.
    func testOldModuleWithoutLessonCommandStillGivesTheLesson() throws {
        repondreJournal([])
        fake.errors["lecon"] = LightroomError.plugin("Commande inconnue : lecon")
        let resultat = appeler(["points": points()])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try XCTUnwrap(resultat.structured)
        XCTAssertEqual(reponse["lecon"]?["rangee"], false)
        XCTAssertEqual(reponse["lecon"]?["remplacee"], false)
        XCTAssertNil(reponse["lecon"]?["mois"])
        XCTAssertNotNil(reponse["texte"]?.string)
        let remarques = reponse["remarques"]?.array?.compactMap(\.string) ?? []
        XCTAssertTrue(remarques.contains { $0.contains("Quitter puis relancer Lightroom") && $0.contains("module d'avant la 1.3") }, "\(remarques)")
        XCTAssertEqual(fake.lecons.count, 1)

        fake.errors["lecon"] = LightroomError.timeout("Lightroom n'a pas répondu.")
        let autre = appeler(["points": points()])
        XCTAssertFalse(autre.isError)
        XCTAssertTrue(autre.text.contains("Leçon non rangée dans le carnet (carnet.json) : Lightroom n'a pas répondu."), autre.text)

        // Une remarque du module (carnet.json non écrit) est reprise.
        fake.errors["lecon"] = nil
        fake.replies["lecon"] = ["rangee": true, "remarque": "Leçon gardée pour cette session, carnet.json non écrit : disque plein"]
        let gardee = try XCTUnwrap(appeler(["points": points()]).structured)
        XCTAssertEqual(gardee["lecon"]?["rangee"], true)
        XCTAssertTrue(gardee["remarques"]?.array?.contains("Leçon gardée pour cette session, carnet.json non écrit : disque plein") == true)
    }

    /// Une erreur du journal (photo introuvable) est une erreur d'outil : rien n'est rangé.
    func testJournalErrorIsAToolError() {
        fake.errors["journal"] = LightroomError.plugin("Aucune photo n'a l'identifiant 9 dans le catalogue ouvert.")
        let resultat = appeler(["photo_id": 9, "points": points()])
        XCTAssertTrue(resultat.isError)
        XCTAssertTrue(fake.lecons.isEmpty)
        fake.errors["journal"] = nil
        fake.replies["journal"] = ["photos": []]
        XCTAssertTrue(appeler(["points": points()]).isError)
        XCTAssertTrue(fake.lecons.isEmpty)
    }

    /// Faits : un exercice est dit, avec sa valeur appliquée ; sans correction, la lecture le dit ;
    /// un départ déjà retouché le dit aussi.
    func testFactsSayExerciseAndDeparture() {
        let corrections = [Lecon.Correction(cle: "Exposure2012", avant: 0, apres: 0.8, exercice: true, appliquee: 0.3)]
        let faits = Lecon.faits(photo: ["id": 1, "fichier": "A.RAF", "iso": "ISO 100", "prise_de_vue_plus": [:]], corrections: corrections,
                                depart: vue(mesures(), etapes: 2), indices: [], maintenant: t0.addingTimeInterval(125))
        XCTAssertEqual(faits["corrections"]?.array?.first?["exercice"], true)
        XCTAssertEqual(faits["corrections"]?.array?.first?["appliquee"], 0.3)
        XCTAssertTrue(faits["corrections_lecture"]?.string?.contains("jamais appliquée") == true)
        XCTAssertNil(faits["prise_de_vue"]?["prise_de_vue_plus"], "vide : pas de prise_de_vue_plus")
        XCTAssertEqual(faits["depart"]?["vue"], "premier view_photo de la session, à 1344 px, il y a 2 min 05 s")
        XCTAssertEqual(faits["depart"]?["etapes_claude"], "2 déjà : la vue n'est pas l'état d'origine")
        let vides = Lecon.faits(photo: ["id": 1], corrections: [], depart: nil, indices: [])
        XCTAssertTrue(vides["corrections_lecture"]?.string?.hasPrefix("aucune correction de Claude") == true)
    }

    // MARK: Le contrat avec le module

    /// La forme envoyée au module (lecon garder), telle que l'essai de la liaison la range
    /// (Tests/Lua/Liaison/essais-lecon.lua, même texte JSON) ; preuves et libellés sous les bornes
    /// du module (Carnet.lua : 400 et 200 octets).
    static let contratModule = #"{"points":[{"axe":"lumiere","manque":"Le ciel était brûlé : 3 % des pixels écrêtés au départ.","prise_de_vue":"Exposer pour le ciel : −2/3 IL de compensation.","defauts":[{"code":"ciel_brule","libelle":"Ciel ou haut de l'image brûlé"}]},{"axe":"couleur","prise_de_vue":"Balance des blancs juste à la prise de vue : à refaire.","defauts":[]},{"axe":"composition","manque":"L'horizon penchait de 1,8°.","prise_de_vue":"Afficher le niveau électronique du viseur.","defauts":[{"code":"horizon_penche","libelle":"Horizon ou ligne penchée"}]}],"indices":[{"code":"horizon_penche","axe":"composition","libelle":"Horizon ou ligne penchée","preuve":"Recadrage : angle −1,8° (0,0 → −1,8)"}]}"#

    func testWhatGoesToTheModuleMatchesTheLiaisonEssay() throws {
        let points = try Lecon.points(points().array!)
        let indices = Lecon.indices(corrections: [Lecon.Correction(cle: "CropAngle", avant: 0, apres: -1.8)], depart: nil)
        XCTAssertEqual(Lecon.pourLeModule(points: points, indices: indices), try JSONCoding.parse(Self.contratModule))

        // Toutes les preuves possibles tiennent dans les bornes du module.
        let toutes = Lecon.indices(corrections: [
            Lecon.Correction(cle: "Exposure2012", avant: -4.99, apres: 5), Lecon.Correction(cle: "Highlights2012", avant: 100, apres: -100),
            Lecon.Correction(cle: "Whites2012", avant: 100, apres: -100), Lecon.Correction(cle: "Shadows2012", avant: -100, apres: 100),
            Lecon.Correction(cle: "Blacks2012", avant: -100, apres: 100), Lecon.Correction(cle: "Dehaze", avant: -100, apres: 100),
            Lecon.Correction(cle: "Amelioration.denoise", avant: 0, apres: 100), Lecon.Correction(cle: "LuminanceSmoothing", avant: 0, apres: 100),
            Lecon.Correction(cle: "Temperature", avant: 2000, apres: 50000), Lecon.Correction(cle: "Tint", avant: -150, apres: 150),
            Lecon.Correction(cle: "CropAngle", avant: -45, apres: 45), Lecon.Correction(cle: "PerspectiveUpright", avant: 0, apres: 5),
            Lecon.Correction(cle: "PerspectiveVertical", avant: -100, apres: 100),
        ], depart: vue(mesures(hautes: 99.9, ombres: 99.9, a: -128, b: 127)))
        // Tous les indices, sauf la surexposition (l'exposition est remontée) et le cadrage (la
        // rotation resserre le cadre d'elle-même).
        XCTAssertEqual(cles(toutes), ["tilted_horizon", "converging_verticals", "underexposed", "blown_highlights", "crushed_shadows",
                                      "flat_light", "noise", "color_cast"])
        for indice in toutes {
            XCTAssertLessThanOrEqual(indice.preuve.utf8.count, 400, indice.preuve)
            XCTAssertLessThanOrEqual(indice.defaut.libelle.utf8.count, 200)
        }
        // 140 caractères accentués tiennent dans les 600 octets d'une moitié.
        XCTAssertLessThanOrEqual(String(repeating: "é", count: Lecon.longueurPoint).utf8.count * 2, 600)
    }

    // MARK: Les invites

    /// La leçon finit les invites de retouche d'une photo (Prompts.Lecon.phrase, seule copie), pas
    /// celles d'une série, d'un tri, d'une notation ni d'une livraison.
    func testRetouchPromptsEndWithTheLesson() {
        for prompt in [Prompts.retouchePro, Prompts.portrait, Prompts.paysage, Prompts.noirEtBlanc, Prompts.nuitIsoEleve] {
            XCTAssertTrue(prompt.render([:]).contains(Prompts.Lecon.phrase), prompt.name)
        }
        for prompt in [Prompts.harmoniserSerie, Prompts.triSeance, Prompts.noter, Prompts.partage] {
            XCTAssertFalse(prompt.render([:]).contains("photo_lesson"), prompt.name)
        }
    }
}
