import XCTest
@testable import DeveloppeurKit

/// Ligne « Mise à jour » de --status, avec un faux gh : les tests ne parlent jamais à GitHub.
final class MiseAJourTests: XCTestCase {
    func testComparaisonDesNumeros() {
        XCTAssertTrue(MiseAJour.plusRecente("1.5", que: "1.4"))
        XCTAssertTrue(MiseAJour.plusRecente("1.10", que: "1.9"))
        XCTAssertTrue(MiseAJour.plusRecente("1.4.1", que: "1.4"))
        XCTAssertTrue(MiseAJour.plusRecente("2.0", que: "1.9.9"))
        XCTAssertFalse(MiseAJour.plusRecente("1.4", que: "1.4.0"))
        XCTAssertFalse(MiseAJour.plusRecente("1.4", que: "1.5"))
        XCTAssertFalse(MiseAJour.plusRecente("dev", que: "1.4"))
        XCTAssertFalse(MiseAJour.plusRecente("1.5", que: "dev"))
    }

    func testDerniereVersionDemandeeAGh() {
        var recu: [String] = []
        let version = MiseAJour.derniereVersion { arguments in
            recu = arguments
            return "v1.5\n"
        }
        XCTAssertEqual(version, "1.5")
        XCTAssertEqual(Array(recu.prefix(2)), ["release", "view"])
        XCTAssertTrue(recu.contains(MiseAJour.depot))
    }

    func testSansReponseDeGhRienNEstSignale() {
        XCTAssertNil(MiseAJour.derniereVersion { _ in nil })
        XCTAssertNil(MiseAJour.derniereVersion { _ in "release not found\n" })
        XCTAssertNil(MiseAJour.ligne(installee: "1.4", derniere: nil))
        XCTAssertNil(MiseAJour.ligne(installee: "dev", derniere: "1.5"))
    }

    func testLigneDeStatus() {
        let nouvelle = MiseAJour.ligne(installee: "1.4", derniere: "1.5")
        XCTAssertEqual(nouvelle, "Mise à jour : la 1.5 est publiée (\(MiseAJour.pageDerniere))")
        XCTAssertEqual(MiseAJour.ligne(installee: "1.4", derniere: "1.4"),
                       "Mise à jour : aucune, la 1.4 est la dernière publiée")
        XCTAssertEqual(MiseAJour.ligne(installee: "1.5", derniere: "1.4"),
                       "Mise à jour : aucune, la dernière publiée est la 1.4")
    }
}
