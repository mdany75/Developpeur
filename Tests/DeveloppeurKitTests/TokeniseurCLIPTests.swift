import XCTest
@testable import DeveloppeurKit

/// Le tokeniseur BPE de CLIP (recherche par le sens, 1.6) : les jetons de vingt phrases connues
/// (Tests/Contrats/jetons-clip.json, calculés par une seconde implémentation), sur le vocabulaire du
/// dépôt (Resources/clip), jamais celui de l'utilisateur.
final class TokeniseurCLIPTests: XCTestCase {
    static let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let vocabulaire = racine.appendingPathComponent("Resources/clip/bpe_simple_vocab_16e6.txt.gz")
    static var partage: TokeniseurCLIP?

    func tokeniseur() throws -> TokeniseurCLIP {
        if let t = Self.partage { return t }
        let t = try TokeniseurCLIP(vocabulaire: Self.vocabulaire)
        Self.partage = t
        return t
    }

    func testLesPhrasesConnues() throws {
        let t = try tokeniseur()
        let contrat = try JSONCoding.parse(String(contentsOf: Self.racine.appendingPathComponent("Tests/Contrats/jetons-clip.json"), encoding: .utf8))
        let phrases = try XCTUnwrap(contrat["phrases"]?.array)
        XCTAssertGreaterThanOrEqual(phrases.count, 20)
        for phrase in phrases {
            let texte = try XCTUnwrap(phrase["texte"]?.string)
            let attendus = try XCTUnwrap(phrase["jetons"]?.array).compactMap { $0.int.map(Int32.init) }
            let jetons = t.jetons(texte)
            XCTAssertEqual(jetons.count, TokeniseurCLIP.longueur, texte)
            XCTAssertEqual(jetons.filter { $0 != 0 }, attendus, texte)
            XCTAssertEqual(Array(jetons.dropFirst(attendus.count)), Array(repeating: 0, count: TokeniseurCLIP.longueur - attendus.count), "des zéros ensuite")
        }
    }

    func testLesJetonsSusDeCLIP() throws {
        // Connus hors de ce dépôt (open_clip, et l'exemple de CLIP).
        XCTAssertEqual(try tokeniseur().jetons("a photo of a cat").prefix(7), [49406, 320, 1125, 539, 320, 2368, 49407])
        XCTAssertEqual(try tokeniseur().jetons("A PHOTO OF A DOG").prefix(7), [49406, 320, 1125, 539, 320, 1929, 49407], "en minuscules")
    }

    func testUnTexteTropLongEstCoupeEtFini() throws {
        let jetons = try tokeniseur().jetons(String(repeating: "beach ", count: 200))
        XCTAssertEqual(jetons.count, 77)
        XCTAssertEqual(jetons.first, TokeniseurCLIP.debut)
        XCTAssertEqual(jetons.last, TokeniseurCLIP.fin)
        XCTAssertFalse(jetons.contains(0))
    }

    func testUnVocabulaireTronqueEstRefuse() {
        XCTAssertThrowsError(try TokeniseurCLIP(texte: "#version: 0.2\ni n\n"))
    }

    func testLeNettoyage() {
        XCTAssertEqual(TokeniseurCLIP.nettoyer("  Fish &amp;amp; Chips\t\n"), "fish & chips")
        XCTAssertEqual(TokeniseurCLIP.nettoyer("Cafe\u{301}"), "café", "forme NFC")
    }
}
