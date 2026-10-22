import CoreGraphics
import Foundation
import XCTest
@testable import DeveloppeurKit

/// L'onglet Focus de la fenêtre Claude (22 octobre 2026) : les cadres de la mise au point dans
/// l'image affichée, leur dessin sur la vignette, et `mcp-developpeur --focus` (Focus.marquer).
final class FocusTests: XCTestCase {
    typealias F = FichierFujifilm

    /// DSCF2402 lue dans un fichier fabriqué de ses valeurs (BoitierTests.dscf2402).
    func dscf2402() throws -> MiseAuPointBoitier {
        let raf = TestSupport.temporaryDirectory().appendingPathComponent("DSCF2402.RAF")
        try F.fichier(note: BoitierTests.dscf2402).write(to: raf)
        return try XCTUnwrap(LectureBoitier.lire(fichier: raf)?.miseAuPoint)
    }

    /// Le cadre d'après ses coins : gauche, haut, droite, bas.
    func bornes(_ cadre: Focus.Cadre) -> (Double, Double, Double, Double) {
        let xs = cadre.coins.map { Double($0.x) }, ys = cadre.coins.map { Double($0.y) }
        return (xs.min()!, ys.min()!, xs.max()!, ys.max()!)
    }

    func testCadresDeDSCF2402DansLImageAffichee() throws {
        let m = try dscf2402()
        let g = GeometriePhoto(largeur: 6240, hauteur: 4160, orientation: "AB")
        let (cadres, dansLeCadre) = Focus.cadres(m, geometrie: g)
        XCTAssertEqual(dansLeCadre, true)
        XCTAssertEqual(cadres.map(\.genre), [.pointAF, .sujet, .sujet, .sujet, .sujet], "le point AF d'abord, puis les quatre sujets")
        XCTAssertEqual(cadres.map(\.nom), ["point AF", "tête", "visage", "œil gauche", "œil droit"])
        // Le point de taille 6 : une case de la grille (1/13 du grand côté), centrée sur FocusPixel.
        let (g0, h0, d0, b0) = bornes(cadres[0])
        XCTAssertEqual((g0 + d0) / 2, 1665.0 / 4416, accuracy: 1e-9)
        XCTAssertEqual((h0 + b0) / 2, 845.0 / 2944, accuracy: 1e-9)
        XCTAssertEqual(d0 - g0, 1.0 / 13, accuracy: 1e-9)
        XCTAssertEqual((b0 - h0) * 2944, 4416.0 / 13, accuracy: 1e-6, "carré, en pixels")
        // L'œil droit, à ses positions.
        let (g4, h4, d4, b4) = bornes(cadres[4])
        XCTAssertEqual(g4, 1635.0 / 4416, accuracy: 1e-9)
        XCTAssertEqual(h4, 767.0 / 2944, accuracy: 1e-9)
        XCTAssertEqual(d4, 1716.0 / 4416, accuracy: 1e-9)
        XCTAssertEqual(b4, 848.0 / 2944, accuracy: 1e-9)

        // Photo tournée d'un quart de tour (BC) : chaque coin passe par GeometriePhoto.versApercu,
        // comme le point de --marquer-af.
        let tournee = GeometriePhoto(largeur: 4160, hauteur: 6240, orientation: "BC")
        let (cadresTournes, _) = Focus.cadres(m, geometrie: tournee)
        let attendu = tournee.versApercu(x: 1665.0 / 4416, y: 845.0 / 2944)
        let (gt, ht, dt, bt) = bornes(cadresTournes[0])
        XCTAssertEqual((gt + dt) / 2, Double(attendu.x), accuracy: 1e-9)
        XCTAssertEqual((ht + bt) / 2, Double(attendu.y), accuracy: 1e-9)

        // Un cadre qui laisse la tête dehors (la moitié droite) : seuls les cadres visibles restent,
        // et le point AF est dit hors du cadre.
        let droite = GeometriePhoto(largeur: 6240, hauteur: 4160, orientation: "AB", cadre: (0.6, 0, 1, 1, 0))
        let (restants, dedans) = Focus.cadres(m, geometrie: droite)
        XCTAssertEqual(dedans, false)
        XCTAssertTrue(restants.isEmpty, "\(restants.map(\.nom))")
        XCTAssertEqual(m.lignesMiseAuPoint(horsDuCadre: true).first, MiseAuPointBoitier.Ligne("Points de mise au point", "lus, hors du cadre actuel"))
    }

    /// La taille du cadre AF selon le mode : zone de 5 × 5 cases ; large / suivi, le carré de 6 %
    /// du petit côté ; un point sans taille lue aussi.
    func testTailleDuCadreSelonLeModeAF() {
        let zone = MiseAuPointBoitier(largeur: 4416, hauteur: 2944, pixel: [2208, 1472], reglagesAF: 0x00A50101)
        let (lz, hz) = Focus.tailleCadreAF(zone, largeur: 4416, hauteur: 2944)
        XCTAssertEqual(lz, 5 * 4416.0 / 13, accuracy: 1e-9)
        XCTAssertEqual(hz, 5 * 4416.0 / 13, accuracy: 1e-9)
        let large = MiseAuPointBoitier(largeur: 4416, hauteur: 2944, pixel: [2208, 1472], reglagesAF: 0x0201)
        let (ll, hl) = Focus.tailleCadreAF(large, largeur: 4416, hauteur: 2944)
        XCTAssertEqual(ll, 0.06 * 2944, accuracy: 1e-9)
        XCTAssertEqual(hl, ll)
        let petit = MiseAuPointBoitier(largeur: 4416, hauteur: 2944, pixel: [2208, 1472], reglagesAF: 0x1001)
        XCTAssertEqual(Focus.tailleCadreAF(petit, largeur: 4416, hauteur: 2944).0, 4416.0 / 13 / 6, accuracy: 1e-9, "taille 1 : 1/6 de case")
        let ancien = MiseAuPointBoitier(largeur: 4416, hauteur: 2944, pixel: [2208, 1472], modeAF: 1)
        XCTAssertEqual(Focus.tailleCadreAF(ancien, largeur: 4416, hauteur: 2944).0, 0.06 * 2944, accuracy: 1e-9, "point sans taille lue")
        // Sans point : pas de cadre AF, les sujets seuls.
        let sansPoint = MiseAuPointBoitier(largeur: 4416, hauteur: 2944, visages: 1, positionsVisages: [100, 100, 300, 300])
        let (cadres, dedans) = Focus.cadres(sansPoint, geometrie: GeometriePhoto(largeur: 6240, hauteur: 4160, orientation: "AB"))
        XCTAssertNil(dedans)
        XCTAssertEqual(cadres.map(\.nom), ["visage"])
    }

    /// Une couleur lue à un pixel de l'image (x, y depuis le coin haut gauche).
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = context.data!.load(fromByteOffset: (y * image.width + x) * 4, as: UInt32.self)
        return (Int(p & 0xFF), Int((p >> 8) & 0xFF), Int((p >> 16) & 0xFF))
    }

    /// Le cadre AF en rouge, entier ; un sujet en coins jaunes : le milieu de ses côtés reste la
    /// photo.
    func testDessinDesCadres() throws {
        let gris = try XCTUnwrap(PreviewImages.image(TestSupport.jpeg(red: 128, green: 128, blue: 128, width: 1000, height: 600)))
        func cadre(_ genre: Focus.Cadre.Genre, _ g: Double, _ h: Double, _ d: Double, _ b: Double) -> Focus.Cadre {
            Focus.Cadre(genre: genre, nom: "", coins: [CGPoint(x: g, y: h), CGPoint(x: d, y: h), CGPoint(x: d, y: b), CGPoint(x: g, y: b)])
        }
        let donnees = try XCTUnwrap(PreviewImages.marquerFocus(gris, cadres: [cadre(.sujet, 0.1, 0.1, 0.5, 0.9), cadre(.pointAF, 0.6, 0.4, 0.8, 0.6)]))
        let image = try XCTUnwrap(PreviewImages.image(donnees))
        XCTAssertEqual(image.width, 1000)
        // Couleurs lues dans un JPEG (couleur sous-échantillonnée) : des écarts, pas des valeurs.
        func rouge(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > p.g + 60 && p.r > p.b + 60 }
        func jaune(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > p.b + 60 && p.g > p.b + 50 && abs(p.r - p.g) < 70 }
        func photo(_ p: (r: Int, g: Int, b: Int)) -> Bool { abs(p.r - 128) < 12 && abs(p.g - 128) < 12 && abs(p.b - 128) < 12 }
        XCTAssertTrue(rouge(Self.pixel(image, 700, 240)), "le haut du cadre AF : \(Self.pixel(image, 700, 240))")
        XCTAssertTrue(rouge(Self.pixel(image, 700, 300)), "le point au centre")
        XCTAssertTrue(photo(Self.pixel(image, 650, 300)), "l'intérieur du cadre AF reste la photo")
        XCTAssertTrue(jaune(Self.pixel(image, 120, 60)), "un coin du sujet : \(Self.pixel(image, 120, 60))")
        XCTAssertTrue(photo(Self.pixel(image, 300, 60)), "le milieu du haut du sujet n'est pas tracé : \(Self.pixel(image, 300, 60))")
        // Un cadre minuscule grandit jusqu'au côté minimal.
        let minuscule = try XCTUnwrap(PreviewImages.image(try XCTUnwrap(PreviewImages.marquerFocus(gris, cadres: [cadre(.pointAF, 0.5, 0.5, 0.501, 0.501)]))))
        XCTAssertTrue(rouge(Self.pixel(minuscule, 500 - 6, 300)), "le bord gauche à 6 pixels du centre : \(Self.pixel(minuscule, 494, 300))")
    }

    /// `mcp-developpeur --focus` : la vignette marquée et la ligne JSON des valeurs ; sans géométrie,
    /// les valeurs seules ; rien de lu, nil (code 1).
    func testCommandeFocusDeLaFenetre() throws {
        let dossier = TestSupport.temporaryDirectory()
        let entree = dossier.appendingPathComponent("vignette.jpg"), sortie = dossier.appendingPathComponent("vignette-focus.jpg")
        try TestSupport.jpeg(red: 90, green: 120, blue: 150, width: 600, height: 400).write(to: entree)
        let m = try dscf2402()
        let lecteur = LecteurBoitier(delai: 1) { _ in LectureBoitier(point: nil, intention: nil, miseAuPoint: m) }
        let original = URL(fileURLWithPath: "/Volumes/Photos/DSCF2402.RAF")
        let json = try XCTUnwrap(Focus.marquer(original: original, geometrie: ["largeur": 6240, "hauteur": 4160, "orientation": "AB"],
                                               entree: entree, sortie: sortie, lecteur: lecteur))
        XCTAssertEqual(json["lue"]?.bool, true)
        XCTAssertEqual(json["dessinee"]?.bool, true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sortie.path))
        XCTAssertEqual(json["cadres"]?["point_af"]?.int, 1)
        XCTAssertEqual(json["cadres"]?["sujets"]?.int, 4)
        XCTAssertEqual(try XCTUnwrap(json["point_af"]?["x"]?.double), 0.377, accuracy: 0.001)
        XCTAssertEqual(json["point_af"]?["dans_le_cadre"]?.bool, true)
        let lignes = try XCTUnwrap(json["mise_au_point"]?.array).map { $0.array?.compactMap(\.string) ?? [] }
        XCTAssertEqual(lignes.first, ["Points de mise au point", "lus"])
        XCTAssertTrue(lignes.contains(["Priorité AF-S", "Déclenchement"]), "\(lignes)")
        XCTAssertEqual(json["prise_de_vue"]?.array?.count, 2)
        XCTAssertEqual(json["image"]?.array?.count, 0)
        // Sans géométrie lisible : les valeurs, sans dessin.
        let sansDessin = try XCTUnwrap(Focus.marquer(original: original, geometrie: nil, entree: entree,
                                                     sortie: dossier.appendingPathComponent("rien.jpg"), lecteur: lecteur))
        XCTAssertEqual(sansDessin["dessinee"]?.bool, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dossier.appendingPathComponent("rien.jpg").path))
        XCTAssertEqual(sansDessin["mise_au_point"]?.array?.count, 8)
        // Rien de lu (autre marque, original qui ne s'ouvre pas à temps) : nil.
        XCTAssertNil(Focus.marquer(original: original, geometrie: ["largeur": 6240, "hauteur": 4160], entree: entree,
                                   sortie: dossier.appendingPathComponent("nil.jpg"), lecteur: LecteurBoitier(delai: 1) { _ in nil }))
        // Une lecture sans mise au point (intention seule) : « non lus », sans cadre.
        let intention = try XCTUnwrap(Focus.marquer(original: original, geometrie: ["largeur": 6240, "hauteur": 4160], entree: entree,
                                                    sortie: dossier.appendingPathComponent("int.jpg"),
                                                    lecteur: LecteurBoitier(delai: 1) { _ in LectureBoitier(intention: IntentionBoitier(simulation: 0)) }))
        XCTAssertEqual(intention["mise_au_point"]?.array?.first?.array?.compactMap(\.string), ["Points de mise au point", "non lus"])
        XCTAssertEqual(intention["cadres"]?["point_af"]?.int, 0)
    }

    /// `mcp-developpeur --focus` sans rien de lu dit pourquoi (`Focus.lire`) : l'original qui ne
    /// s'ouvre pas à temps (« delai »), absent (« introuvable »), ou ouvert sans rien que la lecture
    /// sache lire, comme un HEIF de l'appareil (« illisible ») ; lu, la ligne de `marquer`.
    func testCommandeFocusDitPourquoiRienNEstLu() throws {
        let dossier = TestSupport.temporaryDirectory()
        let entree = dossier.appendingPathComponent("vignette.jpg"), sortie = dossier.appendingPathComponent("vignette-focus.jpg")
        try TestSupport.jpeg(red: 90, green: 120, blue: 150, width: 600, height: 400).write(to: entree)
        let heif = dossier.appendingPathComponent("DSCF0001.HIF")
        try Data("pas un fichier Fujifilm lisible".utf8).write(to: heif)
        let geometrie: JSONValue = ["largeur": 6240, "hauteur": 4160, "orientation": "AB"]
        // Ouvert à temps, rien de lisible.
        let illisible = Focus.lire(original: heif, geometrie: geometrie, entree: entree, sortie: sortie,
                                   lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertEqual(illisible["lue"]?.bool, false)
        XCTAssertEqual(illisible["raison"]?.string, "illisible")
        // Pas de fichier à ce chemin.
        let absent = Focus.lire(original: dossier.appendingPathComponent("absent.RAF"), geometrie: geometrie, entree: entree, sortie: sortie,
                                lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertEqual(absent["raison"]?.string, "introuvable")
        // Une ouverture qui ne finit pas à temps (macOS qui fait attendre open()) : le délai, même si
        // le fichier existe.
        let lent = Focus.lire(original: heif, geometrie: geometrie, entree: entree, sortie: sortie,
                              lecteur: LecteurBoitier(delai: 0.05) { _ in Thread.sleep(forTimeInterval: 1); return nil })
        XCTAssertEqual(lent["raison"]?.string, "delai")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sortie.path), "rien de dessiné")
        // Lu : la ligne de marquer, sans raison.
        let m = try dscf2402()
        let lue = Focus.lire(original: heif, geometrie: geometrie, entree: entree, sortie: sortie,
                             lecteur: LecteurBoitier(delai: 1) { _ in LectureBoitier(point: nil, intention: nil, miseAuPoint: m) })
        XCTAssertEqual(lue["lue"]?.bool, true)
        XCTAssertNil(lue["raison"])
        XCTAssertEqual(lue["dessinee"]?.bool, true)
    }

    /// `--boitier` donne la mise au point en détail et les nouvelles valeurs sous les noms d'exiftool.
    func testBoitierDonneLaMiseAuPoint() throws {
        let raf = TestSupport.temporaryDirectory().appendingPathComponent("DSCF2402.RAF")
        try F.fichier(note: BoitierTests.dscf2402 + [F.court(0x1401, 0)], exif: [F.court(0x8822, 1)]).write(to: raf)
        let json = try XCTUnwrap(Recette.lectureBoitier(raf, looks: LookProfileLibrary(folders: [])))
        let lignes = try XCTUnwrap(json["mise_au_point"]?["mise_au_point"]?.array).compactMap(\.string)
        XCTAssertEqual(lignes[4], "Taille du point AF : 6")
        XCTAssertEqual(json["mise_au_point"]?["prise_de_vue"]?.array?.first?.string, "Stabilisation : Capteur, active (mode 1, en continu)")
        let valeurs = try XCTUnwrap(json["valeurs_lues"])
        XCTAssertEqual(valeurs["FilmMode (0x1401)"]?.int, 0, "l'intention reste")
        XCTAssertEqual(valeurs["AFAreaPointSize (0x102d)"]?.int, 6)
        XCTAssertEqual(valeurs["FocusPixel (0x1023)"]?.array?.compactMap(\.int), [1665, 845])
        XCTAssertEqual(valeurs["DriveMode (0x1103)"]?.int, 0)
        // La mise au point seule (ni point ni intention) se lit aussi.
        try F.fichier(note: [F.court(0x1422, 2, 1, 0)]).write(to: raf)
        let seule = try XCTUnwrap(Recette.lectureBoitier(raf, looks: LookProfileLibrary(folders: [])))
        XCTAssertNil(seule["intention_boitier"])
        XCTAssertEqual(seule["valeurs_lues"]?["ImageStabilization (0x1422)"]?.array?.count, 3)
    }
}
