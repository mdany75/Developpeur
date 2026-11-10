import XCTest
@testable import DeveloppeurKit

/// 1.8 : les réglages de Lightroom Classic 16.0, constatés le 10 novembre 2026 sur des copies
/// d'Essais (docs/SPEC.md, Lightroom Classic 16) : Lueur et Projection globales, étalonnage et lueur
/// dans un masque ; refusés avant la 16.0.
final class Version18Tests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: name, arguments: arguments)
    }

    private var envoi: [String: JSONValue]? { fake.calls.last { $0.command == "appliquer" }?.params }

    /// Bornes et défauts relevés dans Lightroom : une valeur hors bornes y est remise au défaut, le
    /// serveur doit donc la ramener lui-même dans la plage.
    func testLueurEtProjectionAvecLeursBornes() throws {
        fake.replies["etat"] = ["lightroom": "16.0"]
        let attendu: [String: (Double, Double, Double)] = [
            "Glow": (0, 100, 0), "GlowStyle": (0, 4, 1), "GlowRange": (0, 100, 50), "GlowSpread": (0, 100, 50),
            "GlowWarmth": (-100, 100, 0), "GlowDirection": (-180, 180, 0), "GlowDirectionalSoftness": (0, 100, 50),
            "ReshapeAmount": (0, 100, 0),
        ]
        for (cle, (mini, maxi, neutre)) in attendu {
            let reglage = try XCTUnwrap(DevelopCatalogue.setting(cle), cle)
            XCTAssertEqual(reglage.min, mini, cle)
            XCTAssertEqual(reglage.max, maxi, cle)
            XCTAssertEqual(reglage.neutral, neutre, cle)
            XCTAssertEqual(reglage.since, "16.0", cle)
            XCTAssertTrue(reglage.isWhole, "\(cle) : Lightroom arrondit à l'entier")
        }
        XCTAssertEqual(DevelopCatalogue.setting("ReshapeAmount")?.group, "Transformation")
        XCTAssertEqual(DevelopCatalogue.setting("Glow")?.group, "Effets")

        let result = call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 150, "GlowStyle": 2, "GlowWarmth": -20, "ReshapeAmount": 40]])
        XCTAssertFalse(result.isError, result.text)
        let reglages = try XCTUnwrap(envoi?["reglages"])
        XCTAssertEqual(reglages["Glow"]?.double, 100, "150 ramené à 100 avant l'envoi")
        XCTAssertEqual(reglages["GlowStyle"]?.double, 2)
        XCTAssertEqual(reglages["ReshapeAmount"]?.double, 40)
        XCTAssertEqual(envoi?["plages"]?["GlowWarmth"]?.array?.compactMap(\.double), [-100, 100])
        XCTAssertTrue(result.text.contains("Glow"), result.text)
    }

    func testLueurEtProjectionRefuseesAvantLaSeize() {
        fake.replies["etat"] = ["lightroom": "15.6"]
        let refus = call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30, "ReshapeAmount": 20, "Exposure2012": 0.1]])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("Glow (depuis la 16.0)"), refus.text)
        XCTAssertTrue(refus.text.contains("ReshapeAmount (depuis la 16.0)"), refus.text)
        XCTAssertFalse(fake.commands.contains("appliquer"), "rien d'envoyé : la 15.6 ignorerait ces clés")
    }

    /// Un masque sur toute l'image rend comme le même étalonnage global : même échelle, en entiers ;
    /// la lueur d'un masque se range de 0 à 1.
    func testEtalonnageEtLueurDansUnMasque() throws {
        fake.replies["etat"] = ["lightroom": "16.0"]
        let result = call("add_mask", ["step_name": "ciel froid", "masks": [["kind": "sky", "adjustments": [
            "ColorGradeShadowHue": 220, "ColorGradeShadowSat": 25, "ColorGradeHighlightLum": -10, "ColorGradeBalance": 15, "Glow": 40]]]])
        XCTAssertFalse(result.isError, result.text)
        let locaux = try XCTUnwrap(fake.lastParams["masques"]?.array?.first?["locaux"])
        XCTAssertEqual(locaux["LocalColorGradeShadowHue"]?.double, 220)
        XCTAssertEqual(locaux["LocalColorGradeShadowSat"]?.double, 25)
        XCTAssertEqual(locaux["LocalColorGradeHighlightLum"]?.double, -10)
        XCTAssertEqual(locaux["LocalColorGradeBalance"]?.double, 15)
        XCTAssertEqual(locaux["LocalGlow"]?.double ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "sky", "adjustments": ["ColorGradeShadowHue": 400]]]]).isError,
                      "une teinte va de 0 à 359")
        XCTAssertTrue(call("add_mask", ["step_name": "x", "masks": [["kind": "sky", "adjustments": ["Glow": -10]]]]).isError,
                      "une lueur négative n'a aucun effet dans Lightroom : refusée")
    }

    func testEtalonnageDUnMasqueRefuseAvantLaSeize() {
        fake.replies["etat"] = ["lightroom": "15.6"]
        let refus = call("add_mask", ["step_name": "x", "masks": [["kind": "sky", "adjustments": ["ColorGradeGlobalSat": 20, "Exposure": 0.1]]]])
        XCTAssertTrue(refus.isError)
        XCTAssertTrue(refus.text.contains("ColorGradeGlobalSat (depuis la 16.0)"), refus.text)
        XCTAssertFalse(fake.commands.contains("masquer"))
        XCTAssertFalse(call("add_mask", ["step_name": "x", "masks": [["kind": "sky", "adjustments": ["Exposure": 0.1]]]]).isError,
                       "les anciens réglages locaux passent toujours")
    }

    /// L'intensité d'un masque ne change pas un angle : les teintes de l'étalonnage restent telles quelles.
    func testDescriptionDesTeintesDUnMasque() {
        let texte = ToolHandler.describe(["LocalColorGradeShadowHue": 220, "LocalColorGradeShadowSat": 40], facteur: 0.5)
        XCTAssertTrue(texte.contains("teinte des ombres 220"), texte)
        XCTAssertTrue(texte.contains("saturation des ombres +20"), texte)
    }

    /// La Projection déforme l'image après coup, comme Upright : constaté le 10 novembre 2026, un trait
    /// de pinceau posé droit à 0,2 de la hauteur se courbe (0,17 au centre, 0,24 au bord) sous la
    /// Projection 100. Elle compte donc dans la géométrie que la commande apercu doit rendre.
    func testProjectionDansLaGeometrie() {
        XCTAssertTrue(Carnet.clesGeometrie.contains("ReshapeAmount"))
        XCTAssertTrue(ToolHandler.changeGeometrie(["reglages": ["ReshapeAmount": 40]]),
                      "un recadrage dans la même retouche ne se fie pas à la grille d'avant la Projection")
        XCTAssertFalse(ToolHandler.changeGeometrie(["reglages": ["Glow": 40]]))
        let avant: JSONValue = ["photo": ["geometrie": ["largeur": 6000]], "reglages": ["ReshapeAmount": 0]]
        let apres: JSONValue = ["photo": ["geometrie": ["largeur": 6000]], "reglages": ["ReshapeAmount": 60]]
        XCTAssertNotEqual(Bilan.cadre(avant), Bilan.cadre(apres), "le bilan ne compare pas des pixels déplacés par la Projection")
    }

    // MARK: Finitions relevées par la revue de la 1.8

    /// Constaté le 10 novembre 2026 : GlowStyle n'est gardé que si Glow est au-dessus de 0.
    func testStyleDeLueurSansQuantiteDitUneRemarque() {
        fake.replies["etat"] = ["lightroom": "16.0"]
        let seul = call("apply_settings", ["step_name": "lueur", "settings": ["GlowStyle": 2, "GlowWarmth": 20]])
        XCTAssertFalse(seul.isError, seul.text)
        XCTAssertTrue(seul.text.contains("Le style de la Lueur n'est gardé que si sa quantité (Glow) est au-dessus de 0"), seul.text)
        XCTAssertTrue(seul.text.contains("GlowStyle, GlowWarmth sans Glow dans cet appel"), seul.text)
        let aZero = call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 0, "GlowStyle": 2]])
        XCTAssertTrue(aZero.text.contains("avec Glow à 0"), aZero.text)
        let avecQuantite = call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30, "GlowStyle": 2]])
        XCTAssertFalse(avecQuantite.text.contains("n'est gardé que si"), avecQuantite.text)
        XCTAssertFalse(call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30]]).text.contains("n'est gardé que si"))
        // La quantité de la photo, d'après la réponse du module (Glow relatif) : au-dessus de 0, rien à dire.
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 1], "changements": [["cle": "Glow", "avant": 30, "apres": 40]]]]]
        let relatif = call("apply_settings", ["step_name": "lueur", "relative": true, "settings": ["Glow": 10, "GlowStyle": 1]])
        XCTAssertFalse(relatif.text.contains("n'est gardé que si"), relatif.text)
        fake.replies["appliquer"] = ["resultats": [["photo": ["id": 1], "changements": [["cle": "Glow", "avant": 10, "apres": 0]]]]]
        let retiree = call("apply_settings", ["step_name": "lueur", "relative": true, "settings": ["Glow": -10, "GlowStyle": 1]])
        XCTAssertTrue(retiree.text.contains("n'est gardé que si"), retiree.text)
    }

    /// Constaté : l'étalonnage d'un masque se range en entiers (0,5 devient 1) ; le serveur l'arrondit
    /// de même, sans toucher aux autres réglages locaux.
    func testEtalonnageDUnMasqueArrondiALEntier() throws {
        fake.replies["etat"] = ["lightroom": "16.0"]
        let result = call("add_mask", ["step_name": "x", "masks": [["kind": "sky", "adjustments": [
            "ColorGradeShadowSat": 0.5, "ColorGradeShadowHue": 220.4, "ColorGradeMidtoneLum": -10.6, "Exposure": 0.25, "Glow": 40.5]]]])
        XCTAssertFalse(result.isError, result.text)
        let locaux = try XCTUnwrap(fake.lastParams["masques"]?.array?.first?["locaux"])
        XCTAssertEqual(locaux["LocalColorGradeShadowSat"]?.double, 1)
        XCTAssertEqual(locaux["LocalColorGradeShadowHue"]?.double, 220)
        XCTAssertEqual(locaux["LocalColorGradeMidtoneLum"]?.double, -11)
        XCTAssertEqual(locaux["LocalExposure2012"]?.double ?? 0, 0.0625, accuracy: 1e-9, "l'exposition garde son échelle, sans arrondi")
        XCTAssertEqual(locaux["LocalGlow"]?.double ?? 0, 0.405, accuracy: 1e-9, "la lueur d'un masque va de 0 à 1 : pas arrondie")
    }

    /// Lightroom mis à jour pendant une session : la version gardée en mémoire (15.6) est relue avant
    /// de refuser un réglage de la 16.0 ; une réponse du module qui en donne une autre la remplace.
    func testVersionDeLightroomRelueApresUneMiseAJour() {
        fake.replies["etat"] = ["lightroom": "15.6"]
        XCTAssertTrue(call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30]]).isError)
        XCTAssertEqual(tools.versionLightroom, "15.6")
        // Relue tout de suite : pas de seconde lecture (la version se lit une fois par minute au plus).
        XCTAssertTrue(call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30]]).isError)
        XCTAssertEqual(fake.commands.filter { $0 == "etat" }.count, 1)
        // Une minute plus tard, Lightroom relancé en 16.0 : relue avant le refus, la Lueur passe.
        tools.versionLightroomLue = Date().addingTimeInterval(-ToolHandler.relectureVersion - 1)
        fake.replies["etat"] = ["lightroom": "16.0"]
        let apres = call("apply_settings", ["step_name": "lueur", "settings": ["Glow": 30]])
        XCTAssertFalse(apres.isError, apres.text)
        XCTAssertEqual(tools.versionLightroom, "16.0")
        XCTAssertTrue(fake.commands.contains("appliquer"))

        // Une réponse d'écriture qui donne la version la garde aussi.
        fake.replies["appliquer"] = ["lightroom": "16.1", "resultats": []]
        _ = call("apply_settings", ["step_name": "x", "settings": ["Exposure2012": 0.1]])
        XCTAssertEqual(tools.versionLightroom, "16.1")
        // Toujours en 15.6 après relecture : refusé, sans rien envoyer.
        tools.versionLightroom = "15.6"
        tools.versionLightroomLue = .distantPast
        fake.replies["etat"] = ["lightroom": "15.6"]
        fake.calls = []
        XCTAssertTrue(call("apply_settings", ["step_name": "x", "settings": ["Glow": 30]]).isError)
        XCTAssertFalse(fake.commands.contains("appliquer"))
        XCTAssertEqual(fake.commands, ["etat"], "relue une fois avant le refus")
    }

    func testDescriptionsDisentLesNouveautes() throws {
        let definitions = tools.definitions
        let applique = try XCTUnwrap(definitions.first { $0["name"] == "apply_settings" }?["description"]?.string)
        XCTAssertTrue(applique.contains("Lueur (Glow…"), applique)
        XCTAssertTrue(applique.contains("Projection (ReshapeAmount"), applique)
        let taches = try XCTUnwrap(definitions.first { $0["name"] == "retouch_spots" }?["description"]?.string)
        XCTAssertTrue(taches.contains("Supprimer › Imperfections"), taches)
    }
}
