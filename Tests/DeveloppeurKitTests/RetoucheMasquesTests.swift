import XCTest
@testable import DeveloppeurKit

/// Pistes 2.3 (retouche globale) et 2.4 (masques et flou d'objectif) : paramètres de retouche,
/// balance sur un point neutre, profils d'objectif, expositions d'après la prise de vue, masque
/// d'une personne, contour d'un masque IA, edit_mask, Upright exact copié, poussière retirée.
final class RetoucheMasquesTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!
    var lentilles: LensProfileLibrary!

    override func setUp() {
        fake = FakeLightroom()
        lentilles = Self.bibliothequeObjectifs()
        tools = ToolHandler(lightroom: fake, lensProfiles: lentilles)
    }

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: name, arguments: arguments)
    }

    /// Un aperçu gris pour la commande « apercu » (lu une fois par appel d'outil).
    private func donnerApercu() {
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 128, green: 128, blue: 128))), "photo": ["id": 1]]
    }

    /// Deux profils d'objectif comme ceux de Lightroom (même nom, un pour les RAW, un pour les JPEG),
    /// et un autre objectif.
    static func bibliothequeObjectifs() -> LensProfileLibrary {
        let dossier = TestSupport.temporaryDirectory().appendingPathComponent("LensProfiles/1.0/Fujifilm")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        func lcp(_ nom: String, _ objectif: String, raw: Bool) -> String {
            """
            <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:stCamera="http://ns.adobe.com/photoshop/1.0/camera-profile"><photoshop:CameraProfiles><rdf:Seq><rdf:li>
            <rdf:Description stCamera:Author="Adobe (www.adobe.com)" stCamera:Make="Fujifilm" stCamera:CameraRawProfile="\(raw ? "True" : "False")"
             stCamera:Lens="55mm f1.8" stCamera:LensPrettyName="\(objectif)" stCamera:ProfileName="\(nom)" stCamera:FocusDistance="3"/>
            </rdf:li></rdf:Seq></photoshop:CameraProfiles></rdf:Description></rdf:RDF></x:xmpmeta>
            """
        }
        let fichiers = [
            ("Fujifilm (Fujifilm FUJINON 55mm f1.8 M42) - RAW.lcp", lcp("Adobe (Fujifilm FUJINON 55mm f/1.8 M42)", "Fujifilm FUJINON 55mm f/1.8 M42", raw: true)),
            ("Fujifilm (Fujifilm FUJINON 55mm f1.8 M42).lcp", lcp("Adobe (Fujifilm FUJINON 55mm f/1.8 M42)", "Fujifilm FUJINON 55mm f/1.8 M42", raw: false)),
            ("Fujifilm (XF18-55mm) - RAW.lcp", lcp("Adobe (Fujifilm XF18-55mm F2.8-4 R LM OIS)", "Fujifilm XF18-55mm F2.8-4 R LM OIS", raw: true)),
        ]
        for (nom, texte) in fichiers {
            try? texte.write(to: dossier.appendingPathComponent(nom), atomically: true, encoding: .utf8)
        }
        return LensProfileLibrary(folders: [dossier.deletingLastPathComponent()])
    }

    // MARK: 2.3 Retouche globale

    func testApplyNewGlobalParametersReachTheModule() throws {
        let result = call("apply_settings", [
            "preset": "Mes presets/Été", "preset_amount": 49.6, "auto_gray_mix": true, "settings": ["ConvertToGrayscale": 1],
            "lens_profile": "Adobe (Fujifilm FUJINON 55mm f/1.8 M42)", "rotate": "left", "snapshot": "Claude · avant la passe 2",
            "lens_blur": ["amount": 30,
                          "refine": [["mode": "sharp", "strokes": [["points": [[0.3, 0.1], [0.6, 0.1]], "size": 0.08]]]]],
            "step_name": "essai",
        ])
        XCTAssertFalse(result.isError, result.text)
        let params = try XCTUnwrap(fake.calls.last { $0.command == "appliquer" }?.params)
        XCTAssertEqual(params["quantite_preset"]?.double, 50)
        XCTAssertEqual(params["melange_nb_auto"]?.bool, true)
        XCTAssertEqual(params["profil_objectif"]?["nom"]?.string, "Adobe (Fujifilm FUJINON 55mm f/1.8 M42)")
        XCTAssertEqual(params["profil_objectif"]?["fichier"]?.string, "Fujifilm (Fujifilm FUJINON 55mm f1.8 M42) - RAW.lcp", "le fichier des RAW d'abord")
        XCTAssertEqual(params["profil_objectif"]?["fichier_non_raw"]?.string, "Fujifilm (Fujifilm FUJINON 55mm f1.8 M42).lcp", "et celui des JPEG")
        XCTAssertEqual(params["rotation"]?.string, "gauche")
        XCTAssertEqual(params["instantane_avant"]?.string, "avant la passe 2", "le préfixe n'est pas doublé")
        let flou = try XCTUnwrap(params["flou_objectif"])
        XCTAssertEqual(flou["affinage"]?.array?.first?["mode"]?.string, "net")
        XCTAssertEqual(flou["affinage"]?.array?.first?["traits"]?.array?.first?["rayon"]?.double, 0.08)
        XCTAssertEqual(params["libelles"]?["AutoGrayscaleMix"]?.string, "Mélange noir et blanc automatique")
        XCTAssertEqual(params["libelles"]?["Rotation"]?.string, "Rotation (orientation)")
        XCTAssertGreaterThanOrEqual(fake.calls.last { $0.command == "appliquer" }?.timeout ?? 0, 300, "une rotation attend Lightroom")
        XCTAssertTrue(fake.commands.contains("geometrie"), "le pinceau du flou donne des positions : recalées")

        XCTAssertFalse(call("apply_settings", ["lens_profile": "auto", "step_name": "x"]).isError)
        XCTAssertEqual(fake.lastParams["profil_objectif"]?["auto"]?.bool, true)
        let inconnu = call("apply_settings", ["lens_profile": "Helios 44-2", "step_name": "x"])
        XCTAssertTrue(inconnu.isError && inconnu.text.contains("list_profiles"), inconnu.text)
        XCTAssertTrue(call("apply_settings", ["preset": "Été", "preset_amount": 250, "step_name": "x"]).isError)
        XCTAssertTrue(call("apply_settings", ["rotate": "up", "step_name": "x"]).isError)
        let seule = call("apply_settings", ["preset_amount": 50, "settings": ["Exposure2012": 0.1], "step_name": "x"])
        XCTAssertTrue(seule.text.contains("preset_amount ignoré"), seule.text)
    }

    func testUprightGuidesAreCheckedAndRecalaged() throws {
        let trop = call("apply_settings", ["upright_guides": [["x1": 0.2, "y1": 0.1, "x2": 0.2, "y2": 0.9]], "step_name": "x"])
        XCTAssertTrue(trop.isError && trop.text.contains("de 2 à 4"), trop.text)
        let courte = call("apply_settings", ["upright_guides": [["x1": 0.2, "y1": 0.1, "x2": 0.2, "y2": 0.12], ["x1": 0.8, "y1": 0.1, "x2": 0.8, "y2": 0.9]],
                                             "step_name": "x"])
        XCTAssertTrue(courte.isError && courte.text.contains("trop courte"), courte.text)
        let result = call("apply_settings", ["upright_guides": [["x1": 0.18, "y1": 0.02, "x2": 0.18, "y2": 0.56], ["x1": 0.76, "y1": 0.03, "x2": 0.76, "y2": 0.87]],
                                             "step_name": "verticales"])
        XCTAssertFalse(result.isError, result.text)
        let params = try XCTUnwrap(fake.calls.last { $0.command == "appliquer" }?.params)
        XCTAssertEqual(params["reperes"]?.array?.count, 2)
        XCTAssertEqual(params["reperes"]?.array?.first?["y2"]?.double, 0.56)
        XCTAssertNotNil(params["libelles"]?["UprightFourSegments"])
        XCTAssertTrue(fake.commands.contains("geometrie"))
    }

    func testPointColorVarianceAndHueInSixths() throws {
        _ = call("apply_settings", ["point_colors": [["hue": 270, "saturation": 18, "luminance": 57, "variance": 40]], "step_name": "x"])
        let couleur = try XCTUnwrap(fake.lastParams["couleurs_ponctuelles"]?.array?.first)
        XCTAssertEqual(couleur["SrcHue"]?.double ?? 0, 4.5, accuracy: 1e-9, "270° : 4,5 sixièmes de tour")
        XCTAssertEqual(couleur["Variance"]?.double ?? 0, 0.4, accuracy: 1e-9, "constaté : 40 → 0,4")
        XCTAssertTrue(call("apply_settings", ["point_colors": [["hue": 270, "saturation": 18, "luminance": 57, "variance": 140]], "step_name": "x"]).isError)
    }

    func testWhiteBalancePointNeutralizesTheGreyThenMeasuresAgain() throws {
        // Un gris chaud (b* positif) sur un RAW à 5000 K ; après la première passe, presque neutre.
        var gris: (UInt8, UInt8, UInt8) = (140, 128, 104)
        var temperature = 5000.0, teinte = 0.0
        fake.onSend = { [unowned fake] command, params in
            if command == "apercu" {
                fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: gris.0, green: gris.1, blue: gris.2))),
                                           "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                                           "reglages": ["Temperature": .number(temperature), "Tint": .number(teinte)]]
            }
            if command == "appliquer" {
                temperature = params["reglages"]?["Temperature"]?.double ?? temperature
                teinte = params["reglages"]?["Tint"]?.double ?? teinte
                let passe = fake?.calls.filter { $0.command == "appliquer" }.count ?? 0
                gris = passe == 1 ? (130, 128, 122) : (128, 128, 128)
            }
        }
        let result = call("apply_settings", ["white_balance_point": ["x": 0.5, "y": 0.5], "photo_ids": [4], "step_name": "balance"])
        XCTAssertFalse(result.isError, result.text)
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2, "une seconde passe sur l'écart restant")
        let premiere = try XCTUnwrap(ecritures.first?.params["reglages"])
        XCTAssertLessThan(premiere["Temperature"]?.double ?? 9999, 5000, "un gris jaune : refroidir (moins de kelvins)")
        XCTAssertEqual(ecritures.first?.params["relatif"]?.bool, false)
        XCTAssertEqual(ecritures[1].params["etape"]?.string, "balance : balance, passe 2")
        let rapport = try XCTUnwrap(try JSONCoding.parse(result.text)["balance_point"])
        XCTAssertGreaterThan(rapport["mesure_avant"]?["b"]?.double ?? 0, 10)
        XCTAssertEqual(rapport["apres"]?["b"]?.double ?? 99, 0, accuracy: 0.5)

        // Une couleur franche, un blanc brûlé : refusés ; plusieurs photos : refusé.
        gris = (200, 60, 60)
        XCTAssertTrue(call("apply_settings", ["white_balance_point": ["x": 0.5, "y": 0.5], "step_name": "x"]).text.contains("n'est pas un gris"))
        gris = (255, 255, 255)
        XCTAssertTrue(call("apply_settings", ["white_balance_point": ["x": 0.5, "y": 0.5], "step_name": "x"]).text.contains("brûlé"))
        XCTAssertTrue(call("apply_settings", ["white_balance_point": ["x": 0.5, "y": 0.5], "photo_ids": [1, 2], "step_name": "x"]).isError)
        XCTAssertTrue(call("apply_settings", ["white_balance_point": ["x": 0.5, "y": 0.5], "settings": ["Temperature": 5000], "step_name": "x"]).isError)
    }

    func testWhiteBalanceForAPointOnAJpegIsRelative() {
        let point = ToolHandler.PointNeutre(l: 50, a: 0, b: 11.6, ecretes: 0)
        let (temperature, tint) = ToolHandler.balancePourPoint(point, raw: false, temperature: 10, tint: 0)
        XCTAssertEqual(temperature, -7, accuracy: 2, "+20 montaient b* de 11,6 : environ −17 depuis +10")
        XCTAssertGreaterThan(tint, 0)
    }

    func testMatchSeriesByExifReproducesTotalExposures() throws {
        // Référence à f/4, 1/250 s, ISO 400, Exposure2012 +0,3 ; photo 2 à f/4, 1/500 s : une IL de moins.
        let exif: [Int: (Double, Double, Double, Double)] = [1: (4, 1.0 / 250, 400, 0.3), 2: (4, 1.0 / 500, 400, 0), 3: (5.6, 1.0 / 250, 800, 0.3)]
        fake.onSend = { [unowned fake] command, params in
            if command == "reglages", let id = params["photo"]?.int, let e = exif[id] {
                fake?.replies["reglages"] = ["photo": ["fichier": .string("P\(id).RAF")], "reglages": ["Exposure2012": .number(e.3)],
                                             "prise_de_vue": ["ouverture": .number(e.0), "vitesse": .number(e.1), "iso": .number(e.2)]]
            }
        }
        let plan = try JSONCoding.parse(call("match_series", ["reference_id": 1, "photo_ids": [2, 3], "by": "exif"]).text)
        XCTAssertFalse(fake.commands.contains("appliquer"))
        let lignes = try XCTUnwrap(plan["photos"]?.array)
        XCTAssertEqual(lignes[0]["ecart_IL"]?.double ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(lignes[0]["Exposure2012"]?["propose"]?.double ?? 0, 1.3, accuracy: 0.01)
        XCTAssertEqual(lignes[1]["ecart_IL"]?.double ?? 9, 0, accuracy: 0.03, "f/5,6 et ISO 800 : la même lumière à 1/250 s")
        _ = call("match_series", ["reference_id": 1, "photo_ids": [2], "by": "exif", "confirm": true, "step_name": "bracketing"])
        let ecriture = try XCTUnwrap(fake.calls.last { $0.command == "appliquer" })
        XCTAssertEqual(ecriture.params["reglages"]?["Exposure2012"]?.double ?? 0, 1.3, accuracy: 0.01)
        XCTAssertEqual(ecriture.params["relatif"]?.bool, false)
        XCTAssertEqual(ToolHandler.vitesseTexte(1.0 / 250), "1/250 s")
    }

    func testListLensProfilesAndFindThem() throws {
        let liste = try JSONCoding.parse(call("list_profiles", ["lens": "fujinon 55"]).text)
        XCTAssertEqual(liste["total"]?.int, 2)
        XCTAssertEqual(liste["profils_objectif"]?.array?.first?["nom"]?.string, "Adobe (Fujifilm FUJINON 55mm f/1.8 M42)")
        XCTAssertEqual(lentilles.find("Fujifilm XF18-55mm F2.8-4 R LM OIS", raw: true).profile?.fileName, "Fujifilm (XF18-55mm) - RAW.lcp",
                       "par l'objectif aussi")
        XCTAssertEqual(lentilles.find("Adobe (Fujifilm FUJINON 55mm f/1.8 M42)", raw: false).profile?.raw, false)
    }

    // MARK: 2.4 Masques et flou d'objectif

    func testPersonMaskByNumberPointAndPart() throws {
        // Trois personnes pour Vision, de gauche à droite (dans l'aperçu).
        tools.detecterPersonnes = { _ in [CGRect(x: 0.2, y: 0.3, width: 0.15, height: 0.7), CGRect(x: 0.36, y: 0.32, width: 0.1, height: 0.68),
                                          CGRect(x: 0.47, y: 0.33, width: 0.11, height: 0.67)] }
        donnerApercu()
        let result = call("add_mask", ["step_name": "groupe", "masks": [
            ["kind": "person", "person": 2, "adjustments": ["Exposure": 0.2]],
            ["kind": "person", "person_at": [0.52, 0.4], "part": "hair", "refine": ["feather": 50, "edge": -20], "adjustments": ["Saturation": -10]],
        ]])
        XCTAssertFalse(result.isError, result.text)
        let masques = try XCTUnwrap(fake.calls.last { $0.command == "masquer" }?.params["masques"]?.array)
        XCTAssertEqual(masques[0]["type"]?.string, "personne")
        XCTAssertEqual(masques[0]["numero"]?.int, 2)
        XCTAssertEqual(masques[0]["categorie"]?.int, 20036)
        XCTAssertEqual(masques[0]["nom"]?.string, "Claude · Personne 2")
        XCTAssertEqual(masques[0]["cadres"]?.array?.count, 3, "les cadres de toutes les personnes, que Lightroom exige")
        XCTAssertEqual(masques[0]["cadres"]?.array?[1]["Left"]?.double, 0.36)
        XCTAssertEqual(masques[1]["categorie"]?.int, 5)
        XCTAssertEqual(masques[1]["x"]?.double, 0.52)
        XCTAssertEqual(masques[1]["numero"]?.int, 3, "la personne dont le cadre contient le point")
        XCTAssertEqual(masques[1]["affinage"]?["contour"]?.double ?? 0, 1.92, accuracy: 0.01, "constaté : 50 → 1,92")
        XCTAssertEqual(masques[1]["affinage"]?["decalage"]?.double, -2)
        XCTAssertTrue(fake.commands.contains("geometrie"), "un point sur la personne : recalé")
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "person", "adjustments": ["Exposure": 0.2]]]]).text.contains("person_at"))
        donnerApercu()
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "person", "person": 4, "adjustments": ["Exposure": 0.2]]]]).text
            .contains("Vision ne trouve que 3 personnes"))
        tools.detecterPersonnes = { _ in [] }
        donnerApercu()
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "person", "person": 1, "adjustments": ["Exposure": 0.2]]]]).text
            .contains("à la main (Masquage › Personnes)"))
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "linear", "from_x": 0, "from_y": 0, "to_x": 0, "to_y": 1,
                                                                   "refine": ["feather": 10], "adjustments": ["Exposure": 0.2]]]]).text.contains("seuls les masques IA"))
        XCTAssertEqual(ToolHandler.featherRadius(100), 10)
        XCTAssertEqual(ToolHandler.featherRadius(25), 0.354, accuracy: 0.02)
        XCTAssertEqual(ToolHandler.edgeShift(27), 2.7, accuracy: 1e-9)
        // Relevé le 18 octobre 2026 : contour progressif 30 rangé 0,568887, contour −10 rangé −1.
        let liste = ToolHandler.contourEnCurseurs(["masques": [["composants": [["contour_progressif": 0.568887, "contour": -1]]]]])
        XCTAssertEqual(liste["masques"]?.array?[0]["composants"]?.array?[0]["contour_progressif"]?.double, 30)
        XCTAssertEqual(liste["masques"]?.array?[0]["composants"]?.array?[0]["contour"]?.double, -10)
    }

    func testRefineNeedsLightroom155() {
        fake.replies["etat"] = ["lightroom": "15.4"]
        let refus = call("add_mask", ["step_name": "x", "masks": [["kind": "subject", "refine": ["edge": 10], "adjustments": ["Exposure": 0.2]]]])
        XCTAssertTrue(refus.isError && refus.text.contains("refine (depuis la 15.5)"), refus.text)
        XCTAssertTrue(call("edit_mask", ["action": "refine", "mask": 1, "feather": 20, "step_name": "x"]).isError)
    }

    func testEditMaskActions() throws {
        fake.replies["masques"] = ["masques": [["numero": 1, "nom": "Claude · Ciel"]]]
        XCTAssertFalse(call("edit_mask", [:]).isError)
        XCTAssertEqual(fake.lastParams["action"]?.string, "lister")
        XCTAssertNil(fake.lastParams["etape"], "lister n'écrit rien")
        _ = call("edit_mask", ["action": "hide", "mask": "Claude · Ciel", "step_name": "sans ciel", "confirm": true])
        XCTAssertEqual(fake.lastParams["action"]?.string, "masquer")
        XCTAssertEqual(fake.lastParams["masque"]?.string, "Claude · Ciel")
        XCTAssertEqual(fake.lastParams["confirme"]?.bool, true)
        _ = call("edit_mask", ["action": "duplicate", "mask": 2, "invert": true, "name": "Claude · Sol", "step_name": "x"])
        XCTAssertEqual(fake.lastParams["masque"]?.int, 2)
        XCTAssertEqual(fake.lastParams["inverser"]?.bool, true)
        XCTAssertEqual(fake.lastParams["nom"]?.string, "Sol")
        _ = call("edit_mask", ["action": "refine", "mask": 1, "feather": 50, "edge": 50, "step_name": "x"])
        XCTAssertEqual(fake.lastParams["contour"]?.double ?? 0, 1.92, accuracy: 0.01)
        XCTAssertEqual(fake.lastParams["decalage"]?.double, 5)
        _ = call("edit_mask", ["action": "remove_empty", "step_name": "x"])
        XCTAssertEqual(fake.lastParams["action"]?.string, "retirer_vides")
        XCTAssertTrue(call("edit_mask", ["action": "remove", "step_name": "x"]).text.contains("« mask »"))
        XCTAssertTrue(call("edit_mask", ["action": "erase", "mask": 1]).isError)
        XCTAssertTrue(call("edit_mask", ["action": "refine", "mask": 1, "step_name": "x"]).isError)
    }

    func testCopyUprightExactAndRemoveDustOnly() throws {
        _ = call("copy_settings", ["source_id": 1, "photo_ids": [2, 3], "include_upright_exact": true, "step_name": "série"])
        let inclure = try XCTUnwrap(fake.calls.last { $0.command == "copier" }?.params["inclure"])
        XCTAssertEqual(inclure["upright_exact"]?.bool, true)
        XCTAssertNil(inclure["poussiere"], "constaté : copiée par un module, la poussière colle les taches de la source")
        _ = call("copy_settings", ["source_id": 1, "photo_ids": [2], "step_name": "x"])
        XCTAssertEqual(fake.lastParams["inclure"]?["upright_exact"]?.bool, false, "pas par défaut")

        let result = call("remove_distractions", ["dust": ["remove": false], "photo_id": 7, "step_name": "sans poussière"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["poussiere"]?["actif"]?.bool, false)
        XCTAssertNil(fake.lastParams["reflets"])
        let lancer = call("remove_distractions", ["dust": [:], "photo_id": 7, "step_name": "poussière"])
        XCTAssertTrue(lancer.isError)
        XCTAssertTrue(lancer.text.contains("Copier puis Coller de Lightroom"), "la poussière d'une série se fait à la main")
        XCTAssertTrue(call("remove_distractions", ["dust": ["remove": false], "reflections": [:], "step_name": "x"]).isError)
        XCTAssertTrue(call("remove_distractions", ["step_name": "x"]).isError)
    }

    func testNewToolEditMaskIsListed() {
        let names = tools.definitions.compactMap { $0["name"]?.string }
        XCTAssertTrue(names.contains("edit_mask"))
        XCTAssertEqual(names.count, ToolHandler.toolNames.count)
        XCTAssertEqual(names.count, 34)
    }
}
