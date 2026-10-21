import XCTest
@testable import DeveloppeurKit

/// Fichier du jeton de la liaison (liaison fermée, 1.2) : lecture et état, dans un dossier
/// temporaire ; aucun test ne lit le vrai ~/Library.
final class JetonLiaisonTests: XCTestCase {
    private let jeton = String(repeating: "0123456789abcdef", count: 4)

    private func fichier(_ contenu: String?) throws -> URL {
        let url = TestSupport.temporaryDirectory().appendingPathComponent(JetonLiaison.nomFichier)
        if let contenu = contenu {
            try Data(contenu.utf8).write(to: url)
        }
        return url
    }

    private func droits(_ url: URL, _ valeur: Int) throws {
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: valeur)], ofItemAtPath: url.path)
    }

    func testFichierParDefaut() {
        let home = URL(fileURLWithPath: "/Users/essai")
        XCTAssertEqual(JetonLiaison.fichierParDefaut(home: home).path,
                       "/Users/essai/Library/Application Support/Developpeur/liaison.jeton")
        XCTAssertEqual(JetonLiaison.fichierParDefaut(home: home).deletingLastPathComponent(),
                       ClaudeRegistration.installedExecutable(home: home).deletingLastPathComponent(),
                       "à côté de l'exécutable installé")
    }

    func testLireAccepteSoixanteQuatreChiffresHexadecimaux() throws {
        XCTAssertEqual(JetonLiaison.lire(try fichier(jeton)), jeton, "sans saut de ligne")
        XCTAssertEqual(JetonLiaison.lire(try fichier(jeton + "\n")), jeton, "avec le saut de ligne du module")
    }

    func testLireRefuseCeQuiNEstPasUnJeton() throws {
        let refuses: [String] = [
            String(jeton.dropLast()),            // 63 caractères
            jeton + "0",                          // 65
            jeton.uppercased(),                   // majuscules
            String(jeton.dropLast()) + "g",       // hors hexadécimal
            String(jeton.dropLast()) + "é",
            "",                                   // vide
            jeton + String(repeating: " ", count: 1024), // plus de 1 Ko
        ]
        for contenu in refuses {
            XCTAssertNil(JetonLiaison.lire(try fichier(contenu)), "« \(contenu.prefix(70)) »")
        }
        XCTAssertNil(JetonLiaison.lire(try fichier(nil)), "absent")
    }

    /// Le module range un fichier ordinaire (mv) : un dossier, un lien ou un tube nommé à sa place
    /// ne se lit pas. Le tube se lit à part, borné à 2 s : sa lecture ne doit jamais bloquer le
    /// serveur.
    func testLireRefuseCeQuiNEstPasUnFichierOrdinaire() throws {
        let dossier = try fichier(nil)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        XCTAssertNil(JetonLiaison.lire(dossier), "dossier")

        let cible = TestSupport.temporaryDirectory().appendingPathComponent("ailleurs")
        try Data((jeton + "\n").utf8).write(to: cible)
        let lien = try fichier(nil)
        try FileManager.default.createSymbolicLink(at: lien, withDestinationURL: cible)
        XCTAssertEqual(JetonLiaison.lire(cible), jeton, "la cible elle-même se lit")
        XCTAssertNil(JetonLiaison.lire(lien), "lien symbolique")

        let tube = try fichier(nil)
        XCTAssertEqual(mkfifo(tube.path, 0o600), 0)
        let verrou = NSLock()
        var lu: String? = "pas encore lu"
        var etat = ""
        let fini = expectation(description: "lecture du tube nommé")
        DispatchQueue.global().async {
            let resultat = (JetonLiaison.lire(tube), JetonLiaison.etat(tube))
            verrou.lock(); (lu, etat) = resultat; verrou.unlock()
            fini.fulfill()
        }
        wait(for: [fini], timeout: 2)
        verrou.lock(); defer { verrou.unlock() }
        XCTAssertNil(lu, "tube nommé")
        XCTAssertTrue(etat.hasPrefix("illisible ou mal formé ("), etat)
    }

    func testEtatSansJamaisLaValeur() throws {
        let absent = try fichier(nil)
        XCTAssertTrue(JetonLiaison.etat(absent).hasPrefix("absent ("), JetonLiaison.etat(absent))
        XCTAssertTrue(JetonLiaison.etat(absent).contains(absent.path))

        let prive = try fichier(jeton + "\n")
        try droits(prive, 0o600)
        XCTAssertEqual(JetonLiaison.etat(prive), "présent, lisible par vous seul")

        let ouvert = try fichier(jeton + "\n")
        try droits(ouvert, 0o644)
        XCTAssertTrue(JetonLiaison.etat(ouvert).hasPrefix("présent, mais lisible par d'autres comptes (droits 644)"),
                      JetonLiaison.etat(ouvert))

        let malForme = try fichier("pas un jeton")
        XCTAssertTrue(JetonLiaison.etat(malForme).hasPrefix("illisible ou mal formé ("), JetonLiaison.etat(malForme))

        for url in [prive, ouvert] {
            XCTAssertFalse(JetonLiaison.etat(url).contains(jeton))
            XCTAssertFalse(JetonLiaison.etat(url).contains(String(jeton.prefix(16))))
        }
    }

    /// Le module écrit le fichier, le serveur le lit, uninstall.sh le retire : même nom, même dossier.
    func testModuleServeurEtDesinstallationDAccord() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let liaison = try String(contentsOf: racine.appendingPathComponent("Lightroom/Developpeur.lrplugin/Liaison.lua"), encoding: .utf8)
        XCTAssertTrue(liaison.contains("FICHIER_JETON = '\(JetonLiaison.nomFichier)'"))
        XCTAssertTrue(liaison.contains("{ 'Library', 'Application Support', 'Developpeur' }"))
        let desinstallation = try String(contentsOf: racine.appendingPathComponent("uninstall.sh"), encoding: .utf8)
        XCTAssertTrue(desinstallation.contains("\"${DEST_DIR}/\(JetonLiaison.nomFichier)\""))
        XCTAssertTrue(desinstallation.contains("\"${DEST_DIR}/\(JetonLiaison.nomFichier).nouveau\""))
    }
}
