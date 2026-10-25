import XCTest
@testable import DeveloppeurKit

/// La dominante de toute l'image (24 octobre 2026, signalée par Dany : Retouche pro laissait bleu
/// un portrait à l'ombre des feuillus) : le point neutre de l'image dit dans view_photo, la balance
/// qui le ramène au gris, et le bilan qui ne prend pas sa correction pour une dominante accentuée.
final class DominanteGlobaleTests: XCTestCase {
    func mesures(a: Double = 0, b: Double = 0, part: Double = 10, point: MesureEclairage.Neutre? = nil) -> PhotoMeasurements {
        var m = PhotoMeasurements(meanL: 40, percentilesL: [1: 5, 5: 7, 25: 20, 50: 33, 75: 48, 95: 67, 99: 82],
                                  histogramL: [Double](repeating: 10, count: 10), clippedHighlights: 0, pureWhite: 0,
                                  crushedShadows: 0, clippedChannels: [0, 0, 0], meanChroma: 27, saturatedShare: 4,
                                  neutralA: a, neutralB: b, neutralShare: part, pixelCount: 512 * 341)
        m.pointNeutre = point
        return m
    }

    /// Les tons presque neutres ne disent qu'une dominante légère ; le point neutre, la vraie.
    func testLaDominanteDeToutelImageEstDiteEtLesTonsNeutresYRenvoient() throws {
        let photo = mesures(a: -3, b: -3.1, point: MesureEclairage.Neutre(a: 3.4, b: -17.7))
        let couleur = try XCTUnwrap(photo.json["couleur"])
        let globale = try XCTUnwrap(couleur["dominante_globale"])
        XCTAssertEqual(globale["b"]?.double, -17.7)
        XCTAssertTrue(globale["lecture"]?.string?.hasPrefix("toute l'image tire au bleu et un peu au magenta") == true,
                      globale["lecture"]?.string ?? "")
        XCTAssertTrue(couleur["tons_neutres"]?["lecture"]?.string?.hasSuffix("sous-estimée : voir dominante_globale") == true)

        // Un point neutre près du gris (une photo balancée, des couleurs de la scène) : rien de plus.
        for point in [MesureEclairage.Neutre(a: 3, b: 6), nil] {
            let balancee = mesures(a: 1, b: 2, point: point)
            XCTAssertNil(balancee.dominanteGlobale)
            XCTAssertNil(balancee.json["couleur"]?["dominante_globale"])
            XCTAssertEqual(balancee.json["couleur"]?["tons_neutres"]?["lecture"]?.string, balancee.castReading)
        }
    }

    /// La balance proposée réchauffe une image bleue, et le conseil ne part qu'avec une dominante.
    func testLaBalanceProposeeEtLeConseilSuiventLaDominante() throws {
        let photo = mesures(point: MesureEclairage.Neutre(a: 3.4, b: -17.7))
        let reponse: JSONValue = ["echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5150, "Tint": 34]]
        let balance = try XCTUnwrap(ToolHandler.balanceGlobale(photo, reponse: reponse))
        XCTAssertGreaterThan(balance.temperature, 6500, "bleue : nettement plus chaude")
        XCTAssertLessThan(balance.tint, 34, "un peu magenta : moins de teinte")
        let json = ToolHandler.conseilDominanteGlobale(photo.json, balance: balance)
        let globale = try XCTUnwrap(json["couleur"]?["dominante_globale"])
        XCTAssertEqual(globale["balance_proposee"]?["Temperature"]?.double, balance.temperature)
        XCTAssertTrue(globale["conseil"]?.string?.contains("white_balance_point") == true)

        let balancee = mesures(point: MesureEclairage.Neutre(a: 2, b: 4))
        XCTAssertNil(ToolHandler.balanceGlobale(balancee, reponse: reponse))
        XCTAssertEqual(ToolHandler.conseilDominanteGlobale(balancee.json, balance: nil), balancee.json)
    }

    /// Corriger une forte dominante fait prendre aux tons suivis la couleur de leur objet : à
    /// vérifier, pas une « regression » ; sans point neutre (ou s'il ne se rapproche pas du gris),
    /// la règle d'avant reste.
    func testUneDominanteCorrigeeNEstPasUneDominanteAccentuee() {
        let avant = mesures(b: -1, part: 10, point: MesureEclairage.Neutre(a: 3.4, b: -17.7))
        let apres = mesures(b: 5, part: 10, point: MesureEclairage.Neutre(a: 2.9, b: 2.1))
        let corrigee = Bilan.comparer(avant: avant, apres: apres, detailAvant: nil, detailApres: nil, neutresAvant: nil,
                                      neutresApres: nil, suivis: false, cadreChange: false, grainAjoute: false)
        XCTAssertTrue(corrigee.regressions.isEmpty, corrigee.regressions.map(\.texte).joined())
        XCTAssertTrue(corrigee.aVerifier.contains { $0.contains("toute l'image se rapproche du neutre") }, corrigee.aVerifier.joined())
        XCTAssertNotNil(corrigee.ecarts["dominante_globale"])

        for (point0, point1) in [(MesureEclairage.Neutre?.none, MesureEclairage.Neutre?.none),
                                 (MesureEclairage.Neutre(a: 1, b: 2), MesureEclairage.Neutre(a: 1, b: 8))] {
            let sans = Bilan.comparer(avant: mesures(b: -1, point: point0), apres: mesures(b: 5, point: point1), detailAvant: nil,
                                      detailApres: nil, neutresAvant: nil, neutresApres: nil, suivis: false, cadreChange: false,
                                      grainAjoute: false)
            XCTAssertEqual(sans.regressions.map(\.defaut), [.dominante])
        }
    }
}
