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

    func testDescriptionsDisentLesNouveautes() throws {
        let definitions = tools.definitions
        let applique = try XCTUnwrap(definitions.first { $0["name"] == "apply_settings" }?["description"]?.string)
        XCTAssertTrue(applique.contains("Lueur (Glow…"), applique)
        XCTAssertTrue(applique.contains("Projection (ReshapeAmount"), applique)
        let taches = try XCTUnwrap(definitions.first { $0["name"] == "retouch_spots" }?["description"]?.string)
        XCTAssertTrue(taches.contains("Supprimer › Imperfections"), taches)
    }
}
