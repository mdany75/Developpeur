import ColorSync
import Foundation
import XCTest
@testable import DeveloppeurKit

/// L'écran nommé (1.2) : lecture des profils ICC, classement, textes et JSON. Tests purs, sur les
/// profils du système et des copies dans un dossier temporaire ; la lecture des vrais écrans n'est
/// éprouvée que pour l'absence de plantage, sans aucune valeur attendue. Ni le ToolHandler ni
/// get_status ici (lot du connecteur).
final class EcranTests: XCTestCase {
    static let systeme = "/System/Library/ColorSync/Profiles/"
    static let displayP3 = URL(fileURLWithPath: systeme + "Display P3.icc")
    static let sRGB = URL(fileURLWithPath: systeme + "sRGB Profile.icc")

    var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("ecran-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dossier)
    }

    /// Une copie d'un profil, avec des balises ajoutées (`ColorSyncProfileSetTag`) et, au besoin, un
    /// autre créateur écrit dans les octets 80 à 83 (pas par l'en-tête de ColorSync, qui les
    /// inverserait : constaté) ; l'empreinte (octets 84 à 99) est remise à zéro.
    func profilFabrique(depuis source: URL, balises: [String: Data] = [:], createur: String? = nil, nom: String) throws -> URL {
        let donnees = try Data(contentsOf: source)
        let original = try XCTUnwrap(ColorSyncProfileCreate(donnees as CFData, nil)?.takeRetainedValue())
        let copie = try XCTUnwrap(ColorSyncProfileCreateMutableCopy(original)?.takeRetainedValue())
        for (signature, contenu) in balises {
            ColorSyncProfileSetTag(copie, signature as CFString, contenu as CFData)
        }
        var octets = [UInt8](try XCTUnwrap(ColorSyncProfileCopyData(copie, nil)?.takeRetainedValue() as Data?))
        if let createur {
            octets.replaceSubrange(80..<84, with: Array(createur.utf8))
            octets.replaceSubrange(84..<100, with: [UInt8](repeating: 0, count: 16))
        }
        let url = dossier.appendingPathComponent(nom)
        try Data(octets).write(to: url)
        return url
    }

    /// Une balise vcgt (courbes de la carte graphique) : une formule gamma 1, de 0 à 1 par canal.
    static var vcgt: Data {
        var octets = Array("vcgt".utf8) + [0, 0, 0, 0] + [0, 0, 0, 1]
        for _ in 0..<3 {
            octets += [0, 1, 0, 0] + [0, 0, 0, 0] + [0, 1, 0, 0]
        }
        return Data(octets)
    }

    /// Une balise de type text (cprt).
    static func texteICC(_ texte: String) -> Data {
        Data(Array("text".utf8) + [0, 0, 0, 0] + Array(texte.utf8) + [0])
    }

    func lire(_ url: URL) throws -> Ecran.Profil {
        try XCTUnwrap(Ecran.profil(icc: try Data(contentsOf: url), url: url))
    }

    // MARK: - En-tête

    func testEnteteLuDansLesOctets() throws {
        let p3 = try lire(Self.displayP3)
        XCTAssertEqual(p3.createur, "appl")
        XCTAssertEqual(p3.cmm, "appl")
        XCTAssertEqual(p3.nom, "Display P3")
        XCTAssertEqual(p3.chemin, Self.displayP3.path)
        XCTAssertNotNil(p3.date)
        let srgb = try lire(Self.sRGB)
        XCTAssertEqual(srgb.cmm, "Lino")
        XCTAssertEqual(srgb.createur, "HP", "« HP  » sans ses espaces")
        XCTAssertEqual(srgb.date, Ecran.Jour(annee: 1998, mois: 2, jour: 9))
        // ColorSyncProfileCopyHeader rend les signatures à l'envers (constaté) : lire l'en-tête par
        // lui ferait de tout profil d'Apple un profil étranger.
        let donnees = try Data(contentsOf: Self.displayP3)
        let profil = try XCTUnwrap(ColorSyncProfileCreate(donnees as CFData, nil)?.takeRetainedValue())
        let entete = try XCTUnwrap(ColorSyncProfileCopyHeader(profil)?.takeRetainedValue() as Data?)
        XCTAssertEqual(String(bytes: [UInt8](entete)[80..<84], encoding: .isoLatin1), "lppa")
        // Trop court, ou sans « acsp » : pas un profil.
        XCTAssertNil(Ecran.profil(icc: donnees.prefix(131), url: nil))
        var faux = [UInt8](donnees)
        faux.replaceSubrange(36..<40, with: Array("xxxx".utf8))
        XCTAssertNil(Ecran.profil(icc: Data(faux), url: nil))
    }

    func testMeasNEstPasUneSonde() throws {
        let copie = dossier.appendingPathComponent("sRGB copie.icc")
        try FileManager.default.copyItem(at: Self.sRGB, to: copie)
        let profil = try lire(copie)
        XCTAssertTrue(profil.tags.isSuperset(of: ["meas", "dmnd", "dmdd"]), "\(profil.tags)")
        XCTAssertNil(profil.logiciel)
        let classe = Ecran.classer(profil, origine: .personnalise)
        XCTAssertEqual(classe, .personnalise, "meas n'est pas l'indice d'une sonde")
        XCTAssertNil(classe.mesure)
        // Les profils du système, choisis pour l'écran : standard, non mesurés.
        for url in [Self.displayP3, Self.sRGB] {
            let standard = Ecran.classer(try lire(url), origine: .personnalise)
            XCTAssertEqual(standard, .standard, url.lastPathComponent)
            XCTAssertEqual(standard.mesure, false)
        }
    }

    func testSondeReconnue() throws {
        // vcgt avec un créateur autre qu'Apple (ArgyllCMS écrit « argl ») : une sonde.
        let argyll = try lire(try profilFabrique(depuis: Self.displayP3, balises: ["vcgt": Self.vcgt], createur: "argl", nom: "Argyll.icc"))
        XCTAssertEqual(argyll.createur, "argl")
        XCTAssertTrue(argyll.tags.contains("vcgt"))
        let sonde = Ecran.classer(argyll, origine: .personnalise)
        XCTAssertEqual(sonde, .sonde)
        XCTAssertEqual(sonde.mesure, true)
        // Sans vcgt, mais un logiciel de sonde nommé dans le profil : DisplayCAL avant ArgyllCMS.
        let cal = try lire(try profilFabrique(depuis: Self.displayP3,
                                              balises: ["cprt": Self.texteICC("Created with DisplayCAL 3.8 and ArgyllCMS")],
                                              nom: "DisplayCAL.icc"))
        XCTAssertFalse(cal.tags.contains("vcgt"))
        XCTAssertEqual(cal.logiciel, "DisplayCAL")
        XCTAssertEqual(Ecran.classer(cal, origine: .personnalise), .sonde)
        XCTAssertEqual(Ecran.classer(cal, origine: .inconnue), .sonde)
        // vcgt d'Apple : l'assistant d'étalonnage, fait à l'œil, non mesuré.
        let oeil = try lire(try profilFabrique(depuis: Self.displayP3, balises: ["vcgt": Self.vcgt], nom: "Oeil.icc"))
        XCTAssertEqual(oeil.createur, "appl")
        let classe = Ecran.classer(oeil, origine: .personnalise)
        XCTAssertEqual(classe, .oeil)
        XCTAssertEqual(classe.mesure, false)
        // Un profil d'usine n'est jamais « mesuré », quel que soit son contenu.
        XCTAssertEqual(Ecran.classer(argyll, origine: .usine), .usine)
        XCTAssertEqual(Ecran.classer(nil, origine: .usine), .usine)
        XCTAssertEqual(Ecran.classer(nil, origine: .inconnue), .inconnu)
    }

    func testLogicielDansUnTexteUTF16() {
        // Une balise mluc (UTF-16 gros-boutiste) : les octets nuls retirés, le texte se lit.
        var octets: [UInt8] = Array("mluc".utf8) + [0, 0, 0, 0]
        for unite in "Calibrite PROFILER".utf16 {
            octets += [UInt8(unite >> 8), UInt8(unite & 0xFF)]
        }
        XCTAssertEqual(Ecran.logicielDeSonde(Data(octets)), "Calibrite")
        XCTAssertEqual(Ecran.logicielDeSonde(Data("Made with i1 Profiler".utf8)), "i1Profiler")
        XCTAssertEqual(Ecran.logicielDeSonde(Data("SpyderX".utf8)), "Datacolor Spyder")
        XCTAssertNil(Ecran.logicielDeSonde(Data("Copyright Apple Inc., 2022".utf8)))
    }

    func testOrigine() {
        XCTAssertEqual(Ecran.cleUsine, "FactoryProfiles")
        XCTAssertEqual(Ecran.clePersonnalises, "CustomProfiles")
        XCTAssertEqual(Ecran.cleURL, "DeviceProfileURL")
        XCTAssertEqual(Ecran.cleDescription, "DeviceDescription")
        // La forme relevée le 20 octobre 2026 (Odyssey G85SD en HDMI).
        let usine = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Displays/Odyssey G85SD-60EC80AD.icc")
        let modeSD = URL(fileURLWithPath: "/System/Library/CoreServices/Resources/Profiles/SD 170M-A.icc")
        let perso = URL(fileURLWithPath: "/Users/essai/Library/ColorSync/Profiles/Mesure.icc")
        let appareil: [String: Any] = [
            "DeviceDescription": "Odyssey G85SD",
            "FactoryProfiles": [
                "HDMI HD": ["DeviceModeDescription": "HDMI HD", "DeviceProfileURL": usine as NSURL],
                "HDMI SD": ["DeviceModeDescription": "HDMI SD", "DeviceProfileURL": modeSD],
                "DeviceDefaultProfileID": "HDMI HD",
            ] as [String: Any],
            "CustomProfiles": ["1": perso as NSURL, "2": NSNull()] as [String: Any],
        ]
        XCTAssertEqual(Ecran.origine(url: usine, appareil: appareil), .usine)
        XCTAssertEqual(Ecran.origine(url: modeSD, appareil: appareil), .usine, "mode d'usine qui vise un profil du système")
        XCTAssertEqual(Ecran.origine(url: URL(fileURLWithPath: "/Library/ColorSync/Profiles/Displays/Autre-1234.icc"), appareil: nil),
                       .usine, "profil tiré de l'EDID, absent du dictionnaire")
        XCTAssertEqual(Ecran.origine(url: perso, appareil: appareil), .personnalise)
        XCTAssertEqual(Ecran.origine(url: URL(fileURLWithPath: "/Users/essai/Bureau/autre.icc"), appareil: appareil), .inconnue)
        XCTAssertEqual(Ecran.origine(url: nil, appareil: appareil), .inconnue)
        XCTAssertEqual(Ecran.origine(url: perso, appareil: nil), .inconnue)
    }

    // MARK: - Textes et JSON

    static let odyssey = Ecran.Affichage(
        id: 3, nom: "Odyssey G85SD", principal: true, gamutLarge: true,
        profil: Ecran.Profil(nom: "Odyssey G85SD", chemin: "/Library/ColorSync/Profiles/Displays/Odyssey G85SD-60EC80AD.icc",
                             createur: "appl", cmm: "appl", date: Ecran.Jour(annee: 2026, mois: 10, jour: 20),
                             tags: ["desc", "cprt"]),
        etalonnage: .usine)

    static let mesure = Ecran.Affichage(
        id: 4, nom: "ColorEdge CS2400S", principal: true,
        profil: Ecran.Profil(nom: "CS2400S D65", chemin: "/Users/essai/Library/ColorSync/Profiles/CS2400S.icc",
                             createur: "argl", date: Ecran.Jour(annee: 2026, mois: 3, jour: 3), tags: ["vcgt"],
                             logiciel: "DisplayCAL"),
        etalonnage: .sonde)

    static let perso = Ecran.Affichage(
        id: 5, nom: "DELL U2723QE", principal: true,
        profil: Ecran.Profil(nom: "Mon profil", chemin: "/Users/essai/Library/ColorSync/Profiles/Mon profil.icc",
                             createur: "lcms", date: Ecran.Jour(annee: 2025, mois: 1, jour: 1)),
        etalonnage: .personnalise)

    func testTextesEtRemarque() throws {
        let usine = Ecran.texte(Self.odyssey)
        XCTAssertEqual(usine, "Odyssey G85SD · profil d'usine, non mesuré sur ce Mac")
        XCTAssertFalse(usine.contains("2026"), "pas de date pour un profil d'usine (celle du branchement)")
        XCTAssertEqual(Ecran.texte(Self.mesure), "ColorEdge CS2400S · profil mesuré par une sonde (DisplayCAL), du 3 mars 2026")
        XCTAssertTrue(Ecran.texte(Self.perso).contains("profil personnalisé « Mon profil », sans trace d'une sonde"))
        var standard = Self.perso
        standard.profil?.nom = "sRGB IEC61966-2.1"
        standard.etalonnage = .standard
        XCTAssertTrue(Ecran.texte(standard).contains("profil standard du système « sRGB IEC61966-2.1 », non mesuré"))
        var oeil = Self.perso
        oeil.etalonnage = .oeil
        XCTAssertTrue(Ecran.texte(oeil).contains("profil fait à l'œil (assistant d'Apple), non mesuré"))
        var illisible = Self.perso
        illisible.profil = nil
        illisible.etalonnage = .inconnu
        XCTAssertEqual(Ecran.texte(illisible), "DELL U2723QE · profil illisible")
        XCTAssertEqual(Ecran.dateEnMots(Ecran.Jour(annee: 2022, mois: 1, jour: 1)), "1er janvier 2022")
        XCTAssertEqual(Ecran.dateEnMots(Ecran.Jour(annee: 2026, mois: 8, jour: 15)), "15 août 2026")

        // La remarque : nil pour un écran mesuré ; sinon elle nomme l'écran et la peau, les couleurs.
        XCTAssertNil(Ecran.remarque(Self.mesure))
        let remarque = try XCTUnwrap(Ecran.remarque(Self.odyssey))
        XCTAssertTrue(remarque.hasPrefix("Écran principal de l'utilisateur : Odyssey G85SD, profil d'usine, non mesuré sur ce Mac."), remarque)
        XCTAssertTrue(remarque.contains("peau, couleurs") && remarque.contains("n'est pas étalonné"), remarque)
        XCTAssertTrue(remarque.utf16.count < 300, "\(remarque.utf16.count) caractères")
        let doute = try XCTUnwrap(Ecran.remarque(Self.perso))
        XCTAssertTrue(doute.contains("peau, couleurs") && doute.contains("lui demander si son écran est étalonné"), doute)

        // Le détail de la fenêtre : l'écran, son profil, puis le conseil ; un autre écran en plus.
        let detail = Ecran.detail(Ecran.Etat(principal: Self.odyssey, autres: [Self.perso]))
        XCTAssertTrue(detail.hasPrefix("Écran principal : Odyssey G85SD (gamut large).\n"
            + "Profil de couleur : « Odyssey G85SD », le profil d'usine de l'écran, non mesuré sur ce Mac."), detail)
        XCTAssertTrue(detail.contains("Autre écran : DELL U2723QE · profil personnalisé"), detail)
        XCTAssertTrue(detail.contains("Réglages Système › Moniteurs › Profil de couleur"), detail)
        XCTAssertTrue(detail.contains("Night Shift"), detail)
        let detailMesure = Ecran.detail(Ecran.Etat(principal: Self.mesure))
        XCTAssertTrue(detailMesure.contains("mesuré par une sonde (DisplayCAL), profil du 3 mars 2026."), detailMesure)
        XCTAssertTrue(detailMesure.contains("vous la jugez sur un écran étalonné"), detailMesure)
        XCTAssertFalse(detailMesure.contains("Night Shift"))
    }

    func testJSON() throws {
        let etat = Ecran.Etat(principal: Self.odyssey, autres: [Self.perso])
        guard case .object(let simple) = Ecran.json(etat) else { return XCTFail("objet attendu") }
        let principal = try XCTUnwrap(simple["principal"]?.object)
        XCTAssertEqual(principal["nom"]?.string, "Odyssey G85SD")
        XCTAssertEqual(principal["etalonnage"]?.string, "usine")
        XCTAssertEqual(principal["mesure"]?.bool, false)
        XCTAssertEqual(principal["gamut_large"]?.bool, true)
        XCTAssertEqual(principal["integre"]?.bool, false)
        XCTAssertEqual(principal["profil"]?.string, "Odyssey G85SD")
        XCTAssertEqual(principal["texte"]?.string, Ecran.texte(Self.odyssey))
        XCTAssertNil(principal["date_profil"], "jamais la date d'un profil d'usine")
        XCTAssertNil(principal["chemin"], "le chemin ne part pas chez Claude")
        XCTAssertNil(simple["detail"])
        let autre = try XCTUnwrap(simple["autres"]?.array?.first?.object)
        XCTAssertEqual(autre["mesure"]?.isNull, true, "on ne sait pas : null")
        XCTAssertEqual(autre["date_profil"]?.string, "2025-01-01")
        XCTAssertFalse(JSONCoding.line(Ecran.json(etat)).contains("/Users/"), "aucun chemin")
        // Avec le détail (--ecran, pour la fenêtre Claude) : les chemins et le texte de la boîte.
        guard case .object(let complet) = Ecran.json(etat, detail: true) else { return XCTFail("objet attendu") }
        XCTAssertEqual(complet["principal"]?.object?["chemin"]?.string, "/Library/ColorSync/Profiles/Displays/Odyssey G85SD-60EC80AD.icc")
        XCTAssertEqual(complet["detail"]?.string, Ecran.detail(etat))
        let sonde = try XCTUnwrap(Ecran.json(Ecran.Etat(principal: Self.mesure)).object?["principal"]?.object)
        XCTAssertEqual(sonde["mesure"]?.bool, true)
        XCTAssertEqual(sonde["logiciel"]?.string, "DisplayCAL")
        XCTAssertEqual(sonde["date_profil"]?.string, "2026-03-03")
    }

    // MARK: - Lecture réelle

    /// Les vrais écrans (le Mac, ou le macOS de GitHub, avec un écran virtuel ou sans écran) : la
    /// lecture finit vite et ne plante pas ; aucune valeur précise n'est attendue.
    func testLectureReelleSansPlantage() {
        let debut = Date()
        let etat = Ecran.lire()
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2)
        guard let etat else { return }
        XCTAssertFalse(etat.principal.nom.isEmpty)
        XCTAssertTrue(etat.principal.principal)
        XCTAssertTrue(Ecran.Etalonnage.allCases.contains(etat.principal.etalonnage))
        XCTAssertFalse(Ecran.texte(etat.principal).isEmpty)
        XCTAssertFalse(Ecran.detail(etat).isEmpty)
        for autre in etat.autres {
            XCTAssertFalse(autre.principal)
        }
    }
}
