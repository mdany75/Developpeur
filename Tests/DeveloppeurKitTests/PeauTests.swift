import XCTest
@testable import DeveloppeurKit

/// La peau dosée comme Adobe (Peau.swift) : les effets intégrés, la dose effective dite à Claude, et
/// le garde-fou d'add_mask qui refuse une peau trop lisse sans demande, avant tout envoi au module.
final class PeauTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake, lookProfiles: TestSupport.lookLibrary(),
                            presetFolder: TestSupport.temporaryDirectory().appendingPathComponent("Claude"),
                            localEffects: TestSupport.localEffects())
    }

    private func masque(_ masque: [String: JSONValue], preview: Bool = false) -> ToolResult {
        var arguments: [String: JSONValue] = ["masks": [.object(masque)], "step_name": "peau"]
        if preview { arguments["preview"] = true }
        return tools.call(name: "add_mask", arguments: arguments)
    }

    private func dossier(_ fichiers: [String: String]) -> URL {
        let racine = TestSupport.temporaryDirectory().appendingPathComponent("Local Adjustment Presets")
        try? FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        for (nom, texte) in fichiers {
            try? texte.write(to: racine.appendingPathComponent(nom), atomically: true, encoding: .utf8)
        }
        return racine
    }

    private func effet(_ internalName: String, _ valeurs: String) -> String {
        "s = {\n\tid = \"938a4e17\",\n\tinternalName = \"\(internalName)\",\n\ttitle = ZSTR \"$$$/AgDevelop/Localized/Preset/X=\(internalName)\",\n"
            + "\ttype = \"LocalizedAdjustmentPreset\",\n\tvalue = {\n\(valeurs)\n\t},\n\tversion = 0,\n}\n"
    }

    // MARK: Effets intégrés

    func testEffetsIntegresDeLaPeau() throws {
        // Sans aucun fichier : les deux doses d'Adobe, sous leur nom français.
        let vide = LocalEffectLibrary(folders: [dossier([:])]).effects
        XCTAssertEqual(vide.map(\.name), ["Peau du visage lisse", "Adoucir la peau (Lite)"])
        XCTAssertEqual(vide[0].internalName, "Smooth Facial Skin")
        XCTAssertEqual(vide[0].locaux, ["LocalTexture": -0.2, "LocalClarity2012": -0.1], "relevé dans Smooth Face.xmp")
        XCTAssertEqual(vide[1].internalName, "Soften Skin (Lite)")
        XCTAssertEqual(vide[1].locaux, ["LocalTexture": -0.35, "LocalClarity2012": -0.15], "relevé dans SoftenSkin(Lite).lrtemplate")

        // L'effet de l'utilisateur (même nom anglais) l'emporte, avec ses valeurs, et n'est pas répété.
        let fichier = effet("Soften Skin (Lite)", "\t\tclarity2012 = -0.12,\n\t\ttexture = -0.3,")
        let bibliotheque = LocalEffectLibrary(folders: [dossier(["Adoucir la peau (Lite).lrtemplate": fichier])])
        let effets = bibliotheque.effects
        XCTAssertEqual(effets.map(\.name), ["Adoucir la peau (Lite)", "Peau du visage lisse"])
        XCTAssertEqual(effets[0].locaux, ["LocalTexture": -0.3, "LocalClarity2012": -0.12], "les valeurs du fichier")
        // Un effet de l'utilisateur au nom français, sans nom anglais, l'emporte aussi.
        let maison = LocalEffectLibrary(folders: [dossier(["Peau du visage lisse.lrtemplate":
            "s = {\n\ttitle = \"Peau du visage lisse\",\n\ttype = \"LocalizedAdjustmentPreset\",\n\tvalue = {\n\t\ttexture = -0.1,\n\t},\n}\n"])])
        XCTAssertEqual(maison.effects.filter { $0.matches("Peau du visage lisse") }.map(\.locaux), [["LocalTexture": -0.1]])

        // Reconnus par leur nom français ou anglais, sans la casse ni les accents.
        let tous = LocalEffectLibrary(folders: [dossier([:])])
        for nom in ["Smooth Facial Skin", "peau du visage lisse", "PEAU DU VISAGE LISSÉ"] {
            XCTAssertEqual(tous.effect(named: nom)?.name, "Peau du visage lisse", nom)
        }
        for nom in ["Soften Skin (Lite)", "adoucir la peau (lite)"] {
            XCTAssertEqual(tous.effect(named: nom)?.name, "Adoucir la peau (Lite)", nom)
        }
        XCTAssertNil(tous.effect(named: "Soften Skin"), "« Adoucir la peau » n'est pas intégré : son fichier vient de Lightroom")
    }

    /// Les doses intégrées sont celles des fichiers d'Adobe (lecture seule de l'application ; sans
    /// Lightroom, comme sur GitHub, le test est sauté).
    func testDosesSuiventAdobe() throws {
        let app = LookProfileLibrary.lightroomApp
        let smooth = app + "/Contents/Resources/Settings/Premium/Adaptive - Portrait/Smooth Face.xmp"
        guard FileManager.default.fileExists(atPath: smooth) else { throw XCTSkip("Lightroom Classic absent de ce Mac") }
        let xmp = try String(contentsOfFile: smooth, encoding: .utf8)
        func valeur(_ cle: String) -> Double? {
            guard let plage = xmp.range(of: "crs:\(cle)=\"[^\"]*\"", options: .regularExpression) else { return nil }
            return Double(xmp[plage].split(separator: "\"")[1])
        }
        XCTAssertEqual(valeur("LocalTexture"), Peau.effetsIntegres[0].locaux["LocalTexture"])
        XCTAssertEqual(valeur("LocalClarity2012"), Peau.effetsIntegres[0].locaux["LocalClarity2012"])
        XCTAssertEqual(valeur("MaskSubType"), Double(try XCTUnwrap(ToolHandler.aiMasks["person_part/face_skin"]).subtype),
                       "sur la peau du visage, comme person_part face_skin")
        XCTAssertEqual(valeur("MaskSubCategoryID"), ToolHandler.aiMasks["person_part/face_skin"]?.category.map { Double($0) })

        let presets = app + "/Contents/PlugIns/Develop.lrmodule/Contents/Resources/localized_presets/"
        let lite = try XCTUnwrap(LocalEffectLibrary.parse(try String(contentsOfFile: presets + "SoftenSkin(Lite).lrtemplate", encoding: .utf8), name: "x"))
        XCTAssertEqual(lite.internalName, Peau.effetsIntegres[1].internalName)
        XCTAssertEqual(lite.locaux, Peau.effetsIntegres[1].locaux)
        let forte = try XCTUnwrap(LocalEffectLibrary.parse(try String(contentsOfFile: presets + "SoftenSkin.lrtemplate", encoding: .utf8), name: "x"))
        XCTAssertEqual(forte.locaux, Peau.locaux(Peau.forte), "« Adoucir la peau », que le dosage cite")
    }

    // MARK: Dose effective

    func testAddMaskPoseLaDoseParDefaut() throws {
        let result = masque(["kind": "person_part", "part": "face_skin", "effect": "Peau du visage lisse", "amount": 50])
        XCTAssertFalse(result.isError, result.text)
        let envoye = try XCTUnwrap(fake.lastParams["masques"]?.array?.first)
        XCTAssertEqual(fake.calls.last?.command, "masquer")
        XCTAssertEqual(envoye["locaux"]?["LocalTexture"]?.double, -0.2)
        XCTAssertEqual(envoye["locaux"]?["LocalClarity2012"]?.double, -0.1)
        XCTAssertEqual(envoye["quantite"]?.double, 0.5)
        XCTAssertEqual(envoye["nom"]?.string, "Claude · Peau du visage lisse")
        XCTAssertEqual(envoye["categorie"]?.int, 2, "la peau du visage, comme Smooth Face.xmp")
        XCTAssertTrue(result.text.contains("Effet « Peau du visage lisse » : texture −20, clarté −10 ; à 50 % : texture −10, clarté −5."), result.text)
        XCTAssertFalse(result.text.contains("au-dessus de la dose par défaut"), result.text)
        XCTAssertNil(envoye["smoothing_requested"], "le drapeau reste au serveur")

        // Par son nom anglais, à 100 % : la dose entière, sans dose réduite ni remarque.
        let entiere = masque(["kind": "person_part", "part": "face_skin", "effect": "Smooth Facial Skin"])
        XCTAssertFalse(entiere.isError, entiere.text)
        XCTAssertTrue(entiere.text.contains("Effet « Peau du visage lisse » : texture −20, clarté −10."), entiere.text)
        XCTAssertFalse(entiere.text.contains("Peau (masque 1)"), entiere.text)
    }

    func testRemarqueAuDessusDuDefaut() throws {
        let lite = masque(["kind": "person_part", "part": "face_skin", "effect": "Soften Skin (Lite)"])
        XCTAssertFalse(lite.isError, lite.text)
        XCTAssertTrue(lite.text.contains("Peau (masque 1) : texture −35, clarté −15, au-dessus de la dose par défaut « Peau du visage lisse »"), lite.text)
        XCTAssertEqual(fake.lastParams["masques"]?.array?.first?["locaux"]?["LocalTexture"]?.double, -0.35)

        // À moitié, la dose Lite reste sous le défaut : pas de remarque.
        let moitie = masque(["kind": "person_part", "part": "body_skin", "effect": "Adoucir la peau (Lite)", "amount": 50])
        XCTAssertFalse(moitie.isError, moitie.text)
        XCTAssertFalse(moitie.text.contains("au-dessus de la dose par défaut"), moitie.text)
        XCTAssertTrue(moitie.text.contains("à 50 % : texture −17,5, clarté −7,5"), moitie.text)

        // Le deuxième masque est nommé par son numéro ; un masque hors de la peau n'a pas de remarque.
        let deux = tools.call(name: "add_mask", arguments: ["step_name": "portrait", "masks": [
            ["kind": "sky", "adjustments": ["Clarity": -40]],
            ["kind": "person_part", "part": "face_skin", "adjustments": ["Texture": -30]],
        ]])
        XCTAssertFalse(deux.isError, deux.text)
        XCTAssertTrue(deux.text.contains("Peau (masque 2) : texture −30, au-dessus"), deux.text)
        XCTAssertFalse(deux.text.contains("Peau (masque 1)"), deux.text)
    }

    // MARK: Garde-fou

    func testAddMaskRefuseUnePeauTropLisseSansDemande() throws {
        let refuses: [(String, [String: JSONValue])] = [
            ("clarté du visage", ["kind": "person_part", "part": "face_skin", "adjustments": ["Clarity": -100]]),
            ("texture du corps", ["kind": "person_part", "part": "body_skin", "adjustments": ["Texture": -50]]),
            ("une personne précise", ["kind": "person", "person": 1, "part": "face_skin", "adjustments": ["Clarity": -40]]),
            ("intersection avec la peau", ["kind": "radial", "center_x": 0.5, "center_y": 0.4, "radius_x": 0.2, "adjustments": ["Clarity": -50],
                                           "combine": [["mode": "intersect", "kind": "person_part", "part": "face_skin"]]]),
            ("ajout de la peau", ["kind": "subject", "adjustments": ["Texture": -40],
                                  "combine": [["mode": "add", "kind": "person_part", "part": "body_skin"]]]),
            // Soustraire la peau inversée, c'est l'intersecter (la description d'invert le dit).
            ("soustraction de la peau inversée", ["kind": "subject", "adjustments": ["Clarity": -50],
                                                  "combine": [["mode": "subtract", "kind": "person_part", "part": "face_skin", "invert": true]]]),
            ("netteté négative", ["kind": "person_part", "part": "face_skin", "adjustments": ["Sharpness": -10]]),
            ("intensité comprise", ["kind": "person_part", "part": "face_skin", "adjustments": ["Texture": -71], "amount": 50]),
            // L'effet et ses réglages remplacés comptent ensemble : clarté −30 au lieu de −10.
            ("effet renforcé", ["kind": "person_part", "part": "face_skin", "effect": "Peau du visage lisse", "adjustments": ["Clarity": -30]]),
            ("drapeau à false", ["kind": "person_part", "part": "face_skin", "adjustments": ["Clarity": -20], "smoothing_requested": false]),
        ]
        for (cas, donne) in refuses {
            for preview in [false, true] {
                fake.calls = []
                let refus = masque(donne, preview: preview)
                XCTAssertTrue(refus.isError, "\(cas) : \(refus.text)")
                XCTAssertTrue(refus.text.contains("smoothing_requested") && refus.text.contains("« Peau du visage lisse »"), refus.text)
                XCTAssertTrue(refus.text.contains("« masks[0] » : peau lissée au-delà de la dose « Adoucir la peau (Lite) »"), refus.text)
                XCTAssertTrue(fake.calls.isEmpty, "\(cas) : rien n'est envoyé au module (\(fake.commands))")
            }
        }
        // Le refus dit ce qui dépasse, et seulement cela.
        let detail = masque(["kind": "person_part", "part": "face_skin", "adjustments": ["Clarity": -100, "Texture": -20]])
        XCTAssertTrue(detail.text.contains("ici clarté −100)"), detail.text)
        let moitie = masque(["kind": "person_part", "part": "face_skin", "adjustments": ["Texture": -71], "amount": 50])
        XCTAssertTrue(moitie.text.contains("ici texture −35,5)"), moitie.text)
        // Un masque refusé parmi d'autres : aucun n'est posé.
        fake.calls = []
        let lot = tools.call(name: "add_mask", arguments: ["step_name": "portrait", "masks": [
            ["kind": "sky", "adjustments": ["Exposure": -0.3]],
            ["kind": "person_part", "part": "face_skin", "adjustments": ["Clarity": -60]],
        ]])
        XCTAssertTrue(lot.isError && lot.text.contains("« masks[1] »"), lot.text)
        XCTAssertTrue(fake.calls.isEmpty, fake.commands.joined(separator: ", "))

        let acceptes: [(String, [String: JSONValue])] = [
            ("hors de la peau", ["kind": "sky", "adjustments": ["Clarity": -100]]),
            ("peau soustraite", ["kind": "subject", "adjustments": ["Clarity": -50],
                                 "combine": [["mode": "subtract", "kind": "person_part", "part": "face_skin"]]]),
            ("peau inversée", ["kind": "person_part", "part": "face_skin", "invert": true, "adjustments": ["Clarity": -50]]),
            ("intersection d'une peau inversée", ["kind": "subject", "adjustments": ["Clarity": -50],
                                                  "combine": [["mode": "intersect", "kind": "person_part", "part": "face_skin", "invert": true]]]),
            ("cheveux", ["kind": "person_part", "part": "hair", "adjustments": ["Texture": -60]]),
            ("à la limite", ["kind": "person_part", "part": "face_skin", "adjustments": ["Texture": -70], "amount": 50]),
            ("netteté positive", ["kind": "person_part", "part": "face_skin", "adjustments": ["Sharpness": 20, "Texture": -10]]),
            ("débruitage de la peau", ["kind": "person_part", "part": "face_skin", "adjustments": ["Noise": 40]]),
        ]
        for (cas, donne) in acceptes {
            fake.calls = []
            let accepte = masque(donne)
            XCTAssertFalse(accepte.isError, "\(cas) : \(accepte.text)")
            XCTAssertEqual(fake.commands, ["masquer"], cas)
        }

        // À la demande de l'utilisateur (smoothing_requested) : posé, avec la dose dite.
        fake.calls = []
        let demandee = masque(["kind": "person_part", "part": "face_skin", "adjustments": ["Clarity": -100, "Sharpness": 25],
                               "smoothing_requested": true])
        XCTAssertFalse(demandee.isError, demandee.text)
        XCTAssertEqual(fake.commands, ["masquer"])
        XCTAssertTrue(demandee.text.contains("Peau (masque 1) : clarté −100, au-delà de la dose « Adoucir la peau (Lite) », à la demande de l'utilisateur (smoothing_requested)"),
                      demandee.text)
        XCTAssertNil(fake.lastParams["masques"]?.array?.first?["smoothing_requested"])
    }

    func testCalculsDeLaDose() {
        let dose = Peau.dose(["LocalTexture": -0.7, "LocalClarity2012": -0.1, "LocalSharpness": 0.25, "LocalExposure2012": 0.1], quantite: 0.5)
        XCTAssertEqual(dose.texture, -35, accuracy: 1e-9)
        XCTAssertEqual(dose.clarte, -5, accuracy: 1e-9)
        XCTAssertEqual(dose.nettete, 12.5, accuracy: 1e-9)
        XCTAssertEqual(Peau.dose([:], quantite: 1), Peau.Dose(texture: 0, clarte: 0), "sans réglage de la peau : aucune dose")
        XCTAssertNil(Peau.depassement(Peau.Dose(texture: -70 * 0.01 * 0.5 * 100, clarte: -30 * 0.01 * 0.5 * 100)), "pile à la limite")
        XCTAssertNil(Peau.depassement(Peau.lite), "la dose Lite passe")
        XCTAssertNil(Peau.depassement(Peau.Dose(texture: -35.000000000001, clarte: -15)), "à la marge près")
        XCTAssertEqual(Peau.depassement(Peau.Dose(texture: -36, clarte: -15, nettete: -2)), "texture −36, netteté −2")
        XCTAssertTrue(Peau.auDessusDuDefaut(Peau.Dose(texture: -20, clarte: -12)))
        XCTAssertFalse(Peau.auDessusDuDefaut(Peau.parDefaut))
        XCTAssertEqual(Peau.chiffres(Peau.forte), "clarté −100, netteté +25")
        // La dose réduite d'un effet : tout suit l'intensité, sauf la teinte d'une couleur (un angle).
        XCTAssertEqual(ToolHandler.describe(["LocalTexture": -0.35, "LocalToningHue": 30, "LocalToningSaturation": 0.1], facteur: 0.5),
                       "texture −17,5, couleur : teinte 30, couleur : saturation +5")
        XCTAssertTrue(Peau.surLaPeau(["kind": "person", "person": 2, "part": "body_skin"]))
        XCTAssertFalse(Peau.surLaPeau(["kind": "person", "person": 2]), "personne entière : pas couverte")
        XCTAssertFalse(Peau.surLaPeau(["kind": "subject", "combine": [["mode": "subtract", "kind": "person_part", "part": "face_skin"]]]))
        XCTAssertTrue(Peau.surLaPeau(["kind": "subject", "combine": [["mode": "subtract", "kind": "person", "person": 1, "part": "face_skin", "invert": true]]]),
                      "A − non B = A ∩ B, comme Locaux.combiner")
        XCTAssertFalse(Peau.surLaPeau(["kind": "subject", "combine": [["mode": "add", "kind": "person_part", "part": "face_skin", "invert": true]]]),
                       "ajouter tout sauf la peau ne lisse pas la peau")
        XCTAssertTrue(Peau.surLaPeau(["kind": "person_part", "part": "face_skin", "combine": [["mode": "subtract", "kind": "radial"]]]),
                      "la peau du visage, moins une zone : toujours la peau")
    }

    // MARK: Ce que Claude lit

    /// Le dosage est dit dans la définition d'add_mask (les invites et la fenêtre le reprennent ailleurs).
    func testLaDescriptionDAddMaskPorteLeDosage() throws {
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"] == "add_mask" })
        let masque = try XCTUnwrap(definition["inputSchema"]?["properties"]?["masks"]?["items"]?["properties"])
        let effet = try XCTUnwrap(masque["effect"]?["description"]?.string)
        XCTAssertTrue(effet.hasSuffix(Peau.dosage), effet)
        XCTAssertTrue(effet.contains("« Peau du visage lisse » (Smooth Facial Skin)"), "l'effet intégré est proposé")
        let drapeau = try XCTUnwrap(masque["smoothing_requested"])
        XCTAssertEqual(drapeau["type"]?.string, "boolean")
        XCTAssertTrue(drapeau["description"]?.string?.contains("Jamais de toi-même") == true)
        XCTAssertNil(definition["inputSchema"]?["properties"]?["masks"]?["items"]?["properties"]?["combine"]?["items"]?["properties"]?["smoothing_requested"],
                     "le drapeau est celui du masque, pas d'un composant")
        // Les chiffres viennent de Peau : la dose par défaut, la dose Lite, la moitié.
        for texte in ["texture −20, clarté −10", "texture −35, clarté −15", "amount 50 pour un homme ou une personne âgée",
                      "rien pour un enfant", "un masque par personne", "clarté −100"] {
            XCTAssertTrue(Peau.dosage.contains(texte), texte)
        }
        XCTAssertTrue(Peau.demandeDescription.contains("texture −35 ou clarté −15"), Peau.demandeDescription)
    }
}
