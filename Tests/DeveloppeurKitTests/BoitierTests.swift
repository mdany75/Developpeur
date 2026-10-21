import Foundation
import XCTest
@testable import DeveloppeurKit

/// Fichiers Fujifilm fabriqués octet par octet : un RAF (en-tête, JPEG incorporé) ou un JPEG de
/// l'appareil, dont l'Exif porte les dimensions, la MakerNote de Fujifilm et d'autres entrées.
/// Les valeurs de plus de 4 octets (rationnels, MakerNote) sont rangées après leur IFD.
enum FichierFujifilm {
    /// Une entrée d'IFD : tag, type TIFF et valeurs (un rationnel : numérateur puis dénominateur).
    struct Entree {
        var tag: Int
        var type: Int
        var valeurs: [Int]
    }

    static func court(_ tag: Int, _ valeurs: Int...) -> Entree { Entree(tag: tag, type: 3, valeurs: valeurs) }
    static func long(_ tag: Int, _ valeurs: Int...) -> Entree { Entree(tag: tag, type: 4, valeurs: valeurs) }
    static func sshort(_ tag: Int, _ valeurs: Int...) -> Entree { Entree(tag: tag, type: 8, valeurs: valeurs) }
    static func slong(_ tag: Int, _ valeurs: Int...) -> Entree { Entree(tag: tag, type: 9, valeurs: valeurs) }
    static func rationnel(_ tag: Int, _ n: Int, _ d: Int) -> Entree { Entree(tag: tag, type: 5, valeurs: [n, d]) }
    static func srationnel(_ tag: Int, _ n: Int, _ d: Int) -> Entree { Entree(tag: tag, type: 10, valeurs: [n, d]) }
    static func texte(_ tag: Int, _ texte: String) -> Entree { Entree(tag: tag, type: 2, valeurs: Array(texte.utf8).map(Int.init)) }

    /// Le point de mise au point (FocusPixel), l'avertissement (FocusWarning) et deux visages.
    static func point(x: Int, y: Int, avertissement: Int = 0) -> [Entree] {
        [court(0x1023, x, y), court(0x1301, avertissement), court(0x4100, 2)]
    }

    /// Octets d'un terme de chaque type (un rationnel : deux termes de 4 octets).
    static let tailles: [Int: Int] = [1: 1, 2: 1, 3: 2, 4: 4, 5: 4, 6: 1, 7: 1, 8: 2, 9: 4, 10: 4]

    static func octets(_ valeur: Int, _ taille: Int, petit: Bool) -> [UInt8] {
        let bits = UInt64(bitPattern: Int64(valeur))
        let premiers = (0..<taille).map { UInt8(truncatingIfNeeded: bits >> UInt64(8 * $0)) }
        return petit ? premiers : premiers.reversed()
    }

    /// Un IFD qui commence à `debut` (positions comptées depuis le début des données), suivi des
    /// valeurs de plus de 4 octets.
    static func ifd(_ entrees: [Entree], debut: Int, petit: Bool) -> [UInt8] {
        var tete = octets(entrees.count, 2, petit: petit)
        var suite: [UInt8] = []
        let finIFD = debut + 2 + 12 * entrees.count + 4
        for entree in entrees.sorted(by: { $0.tag < $1.tag }) {
            let valeur = entree.valeurs.flatMap { octets($0, tailles[entree.type] ?? 1, petit: petit) }
            let nombre = [5, 10].contains(entree.type) ? entree.valeurs.count / 2 : entree.valeurs.count
            tete += octets(entree.tag, 2, petit: petit) + octets(entree.type, 2, petit: petit) + octets(nombre, 4, petit: petit)
            if valeur.count <= 4 {
                tete += valeur + [UInt8](repeating: 0, count: 4 - valeur.count)
            } else {
                tete += octets(finIFD + suite.count, 4, petit: petit)
                suite += valeur
            }
        }
        return tete + octets(0, 4, petit: petit) + suite
    }

    /// MakerNote de Fujifilm : « FUJIFILM », position de l'IFD (12), entrées petit-boutistes.
    static func note(_ entrees: [Entree]) -> [UInt8] {
        Array("FUJIFILM".utf8) + octets(12, 4, petit: true) + ifd(entrees, debut: 12, petit: true)
    }

    /// RAF (ou JPEG de l'appareil) : Exif grand-boutiste par défaut (comme le fichier d'essai du
    /// point de mise au point), IFD0 → IFD Exif (dimensions, entrées données, MakerNote).
    static func fichier(note entreesNote: [Entree], exif: [Entree] = [], largeur: Int? = 4416, hauteur: Int? = 2944,
                        raf: Bool = true, exifPetit: Bool = false) -> Data {
        let petit = exifPetit
        var entrees = exif
        if let largeur { entrees.append(long(0xA002, largeur)) }
        if let hauteur { entrees.append(long(0xA003, hauteur)) }
        entrees.append(Entree(tag: 0x927C, type: 7, valeurs: note(entreesNote).map(Int.init)))
        let exifIFD = 8 + 2 + 12 + 4
        let tiff = Array((petit ? "II" : "MM").utf8) + octets(42, 2, petit: petit) + octets(8, 4, petit: petit)
            + ifd([long(0x8769, exifIFD)], debut: 8, petit: petit) + ifd(entrees, debut: exifIFD, petit: petit)
        let segment = Array("Exif".utf8) + [0, 0] + tiff
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1] + octets(segment.count + 2, 2, petit: false) + segment + [0xFF, 0xD9]
        guard raf else { return Data(jpeg) }
        var fichier = Array("FUJIFILMCCD-RAW 0201FF169501X-H2S".utf8)
        fichier += [UInt8](repeating: 0, count: 84 - fichier.count)
        fichier += octets(100, 4, petit: false) + octets(jpeg.count, 4, petit: false)
        fichier += [UInt8](repeating: 0, count: 100 - fichier.count)
        return Data(fichier + jpeg)
    }

    /// Position du début de la MakerNote dans un fichier fabriqué.
    static func debutNote(_ fichier: Data) -> Int? {
        fichier.range(of: Data(Array("FUJIFILM".utf8) + [12, 0, 0, 0]))?.lowerBound
    }
}

/// Lecture du boîtier (Boitier.swift) et intention de la prise de vue (IntentionBoitier.swift).
final class BoitierTests: XCTestCase {
    typealias F = FichierFujifilm

    /// Réglages d'une photo prise en CLASSIC CHROME, DR auto (200 %), tons clairs +1, tons foncés
    /// −1, −2/3 IL en priorité à l'ouverture, les tons rangés dans le type donné.
    static func reglages(tons type: Int) -> (note: [F.Entree], exif: [F.Entree]) {
        (F.point(x: 2488, y: 1052) + [F.court(0x1401, 0x600), F.court(0x1402, 0), F.court(0x140b, 200),
                                      F.Entree(tag: 0x1041, type: type, valeurs: [-16]), F.Entree(tag: 0x1040, type: type, valeurs: [16])],
         [F.srationnel(0x9204, -2, 3), F.court(0x8822, 3)])
    }

    func testIntentionIsReadFromAFujifilmRAF() throws {
        let dossier = TestSupport.temporaryDirectory()
        // Tons en SLONG (int32s chez exiftool) dans un RAF à l'Exif grand-boutiste, puis en LONG dans
        // un JPEG à l'Exif petit-boutiste : même lecture.
        for (type, raf, petit) in [(9, true, false), (4, false, true)] {
            let fichier = dossier.appendingPathComponent(raf ? "DSCF0001.RAF" : "DSCF0001.JPG")
            let r = Self.reglages(tons: type)
            try F.fichier(note: r.note, exif: r.exif, raf: raf, exifPetit: petit).write(to: fichier)
            let lecture = try XCTUnwrap(LectureBoitier.lire(fichier: fichier), "type \(type)")
            let intention = try XCTUnwrap(lecture.intention)
            XCTAssertEqual(intention.nomSimulation, "CLASSIC CHROME")
            XCTAssertEqual(intention.profilSimulation, "Camera CLASSIC CHROME")
            XCTAssertEqual(intention.plageDynamique?.pourcent, 200)
            XCTAssertEqual(intention.plageDynamique?.auto, true)
            XCTAssertEqual(intention.tonsClairs, 1, "HighlightTone −16 : +1 (type \(type))")
            XCTAssertEqual(intention.tonsFonces, -1, "ShadowTone 16 : −1 (type \(type))")
            XCTAssertEqual(try XCTUnwrap(intention.compensation), -2.0 / 3, accuracy: 1e-3)
            XCTAssertEqual(intention.mode, "priorité à l'ouverture")
            XCTAssertFalse(intention.noirEtBlanc)
            // Le point de mise au point vient de la même lecture.
            XCTAssertEqual(try XCTUnwrap(lecture.point?.x), 2488.0 / 4416, accuracy: 1e-9)
            XCTAssertEqual(PointAF.lire(fichier: fichier), lecture.point)
        }
    }

    /// Les corrections de Tiff : tailles des types signés, valeurs signées, rationnels.
    func testSignedAndRationalEntries() throws {
        let note = F.note([
            F.slong(0x1040, -64), F.long(0x1041, -8),
            F.sshort(0x9000, -1, 2, -3),
            F.srationnel(0x9001, -1, 1), F.rationnel(0x9002, -2, 3), F.srationnel(0x9003, 1, 0),
            F.court(0x9004, 0xFFF0), F.long(0x9005, 160), F.texte(0x9006, "ab"),
            F.rationnel(0x9007, 1000, 1),
        ])
        let ifd = try XCTUnwrap(LectureBoitier.Tiff(donnees: Data(note), petit: true).ifd(at: 12))
        let ombres = try XCTUnwrap(ifd[0x1040])
        XCTAssertEqual(ombres.signe, -64, "et non 4294967232")
        XCTAssertEqual(ombres.entier, 4_294_967_232, "lu sans signe : le motif des bits")
        XCTAssertEqual(IntentionBoitier.ton(ombres), 4)
        XCTAssertEqual(IntentionBoitier.ton(ifd[0x1041]), 0.5, "LONG −8 : un demi-cran")
        // Un SSHORT de 3 valeurs (6 octets) est rangé à son adresse, pas dans l'entrée.
        XCTAssertEqual(ifd[0x9000]?.signes(3), [-1, 2, -3])
        XCTAssertEqual(ifd[0x9000]?.entiers(3), [65535, 2, 65533])
        XCTAssertEqual(ifd[0x9001]?.rationnel(), -1)
        XCTAssertEqual(try XCTUnwrap(ifd[0x9002]?.rationnel()), 4_294_967_294.0 / 3, accuracy: 1, "RATIONAL : sans signe")
        XCTAssertEqual(try XCTUnwrap(IntentionBoitier.compensation(ifd[0x9002])), -2.0 / 3, accuracy: 1e-9,
                       "la compensation se lit signée, comme exiftool")
        XCTAssertNil(ifd[0x9003]?.rationnel(), "dénominateur nul")
        XCTAssertNil(IntentionBoitier.compensation(ifd[0x9007]), "1000 IL : pas une compensation")
        // Un ton rangé dans un autre type : un SHORT se relit sur 16 bits, une valeur hors des
        // crans de l'appareil ou un texte ne donnent rien.
        XCTAssertEqual(IntentionBoitier.ton(ifd[0x9004]), 1)
        XCTAssertNil(IntentionBoitier.ton(ifd[0x9005]), "−10 crans")
        XCTAssertNil(IntentionBoitier.ton(ifd[0x9006]))
        XCTAssertNil(IntentionBoitier.ton(nil))
        // Un réglage rangé en texte ou en octets indéfinis n'est pas lu.
        XCTAssertNil(IntentionBoitier.entier(ifd[0x9006]))
        XCTAssertEqual(IntentionBoitier.entier(ifd[0x9004]), 0xFFF0)

        // Dans un fichier : FilmMode en octets indéfinis (0x600 rangé 00 06) ne donne pas PROVIA.
        let dossier = TestSupport.temporaryDirectory()
        let raf = dossier.appendingPathComponent("DSCF0006.RAF")
        try F.fichier(note: F.point(x: 10, y: 10) + [F.Entree(tag: 0x1401, type: 7, valeurs: [0x00, 0x06])]).write(to: raf)
        XCTAssertNil(LectureBoitier.lire(fichier: raf)?.intention)
        XCTAssertNotNil(LectureBoitier.lire(fichier: raf)?.point)
    }

    func testIntentionWithoutFocusPoint() throws {
        let dossier = TestSupport.temporaryDirectory()
        let raf = dossier.appendingPathComponent("DSCF0003.RAF")
        try F.fichier(note: F.point(x: 0, y: 0) + [F.court(0x1401, 0x700)]).write(to: raf)
        let lecture = try XCTUnwrap(LectureBoitier.lire(fichier: raf), "un point (0, 0) n'empêche plus l'intention")
        XCTAssertNil(lecture.point)
        XCTAssertEqual(lecture.intention?.nomSimulation, "ETERNA/Cinema")
        XCTAssertNil(PointAF.lire(fichier: raf))
        // Sans les dimensions de l'Exif : pas de point, l'intention reste.
        try F.fichier(note: F.point(x: 100, y: 200) + [F.court(0x1401, 0)], largeur: nil, hauteur: nil).write(to: raf)
        XCTAssertNil(LectureBoitier.lire(fichier: raf)?.point)
        XCTAssertEqual(LectureBoitier.lire(fichier: raf)?.intention?.nomSimulation, "PROVIA/Standard")
        // Ni point ni réglage lu : rien.
        try F.fichier(note: F.point(x: 0, y: 0)).write(to: raf)
        XCTAssertNil(LectureBoitier.lire(fichier: raf))
    }

    func testMonochromeSimulationComesFromSaturation() throws {
        let acros = IntentionBoitier(saturation: 0x501)
        XCTAssertEqual(acros.nomSimulation, "ACROS, filtre rouge")
        XCTAssertEqual(acros.profilSimulation, "Camera ACROS+R Filter")
        XCTAssertTrue(acros.noirEtBlanc)
        XCTAssertNil(acros.couleur)
        let sepia = IntentionBoitier(saturation: 0x310)
        XCTAssertEqual(sepia.nomSimulation, "Sépia")
        XCTAssertEqual(sepia.profilSimulation, "Camera Sepia")
        XCTAssertFalse(IntentionBoitier(simulation: 0x600, saturation: 0x8000).noirEtBlanc)
        XCTAssertNil(IntentionBoitier(simulation: 0x600, saturation: 0x8000).couleur, "0x8000 : la couleur de la simulation")
        XCTAssertFalse(IntentionBoitier(saturation: 0x80).noirEtBlanc)
        XCTAssertEqual(IntentionBoitier(saturation: 0x80).couleur, 1)
        XCTAssertEqual(IntentionBoitier(saturation: 0x4c0).couleur, -3)
        // La saturation ne range une simulation qu'en noir et blanc : elle l'emporte sur FilmMode.
        XCTAssertEqual(IntentionBoitier(simulation: 0, saturation: 0x500).nomSimulation, "ACROS")
        // Lue dans un fichier sans FilmMode.
        let dossier = TestSupport.temporaryDirectory()
        let raf = dossier.appendingPathComponent("DSCF0004.RAF")
        try F.fichier(note: F.point(x: 10, y: 10) + [F.court(0x1003, 0x302)]).write(to: raf)
        XCTAssertEqual(LectureBoitier.lire(fichier: raf)?.intention?.profilSimulation, "Camera Monochrome+Ye Filter")
    }

    /// Chaque profil DCP des tables est un nom du catalogue tel quel (pas une variante comme
    /// « Camera PRO Neg. Hi », introuvable sur un X-H2S) ; les autres sont les quatre Look relevés.
    func testSimulationProfileNamesMatchTheCatalogue() {
        let profils = IntentionBoitier.simulations.values.compactMap { $0.profil } + IntentionBoitier.monochromes.values.map { $0.profil }
        var looks = Set<String>()
        for profil in profils {
            if let catalogue = DevelopCatalogue.profile(profil) {
                XCTAssertEqual(catalogue.name, profil, "le nom du catalogue, pas une variante")
            } else {
                looks.insert(profil)
            }
        }
        XCTAssertEqual(looks, ["Camera CLASSIC Neg", "Camera BLEACH BYPASS", "Camera NOSTALGIC Neg", "Camera Sepia"])
        XCTAssertNil(IntentionBoitier.simulations[0x100]?.profil, "Studio Portrait : pas de profil")
    }

    func testLightroomProfileForTheCamera() {
        let looks = TestSupport.lookLibrary()
        let classicNeg = IntentionBoitier(simulation: 0x800)
        XCTAssertEqual(classicNeg.profilLightroom(marque: "FUJIFILM", modele: "X-H2S", looks: looks), "Camera CLASSIC Neg")
        XCTAssertNil(classicNeg.profilLightroom(marque: "FUJIFILM", modele: "X-T20", looks: looks), "pas de Look pour cet appareil")
        let eterna = IntentionBoitier(simulation: 0x700)
        XCTAssertEqual(eterna.profilLightroom(marque: "FUJIFILM", modele: "X-H2S", looks: looks), "Camera ETERNA/Cinema")
        XCTAssertNil(eterna.profilLightroom(marque: "FUJIFILM", modele: "X-T20", looks: looks), "rendu comme Adobe Standard (missingOn)")
        XCTAssertEqual(IntentionBoitier(simulation: 0x501).profilLightroom(marque: "FUJIFILM", modele: "X-H2S", looks: looks), "Camera Pro Neg Hi")
        XCTAssertNil(IntentionBoitier(simulation: 0x100).profilLightroom(marque: "FUJIFILM", modele: "X-H2S", looks: looks))
        XCTAssertNil(IntentionBoitier(compensation: -1).profilLightroom(marque: "FUJIFILM", modele: "X-H2S", looks: looks))
    }

    func testLecture() throws {
        func lignes(_ intention: IntentionBoitier, raw: Bool = true, profil: String? = nil, actuel: String? = nil) -> String {
            intention.lecture(raw: raw, profil: profil, profilActuel: actuel).joined(separator: "\n")
        }
        let sombre = lignes(IntentionBoitier(compensation: -1))
        XCTAssertTrue(sombre.hasPrefix("Compensation −1 IL"), sombre)
        XCTAssertTrue(sombre.contains("voulue plus sombre") && sombre.contains("Exposure2012"), sombre)
        XCTAssertFalse(lignes(IntentionBoitier(compensation: -1.0 / 3)).contains("Compensation"), "−1/3 IL ne dit rien")
        XCTAssertFalse(lignes(IntentionBoitier(compensation: 1.0 / 3)).contains("Compensation"))
        XCTAssertTrue(lignes(IntentionBoitier(compensation: 1)).contains("voulue plus claire"))
        XCTAssertTrue(lignes(IntentionBoitier(programme: 1)).contains("réglée à la main"))
        XCTAssertTrue(lignes(IntentionBoitier(compensation: 0, programme: 1)).contains("réglée à la main"))
        XCTAssertFalse(lignes(IntentionBoitier(compensation: -1, programme: 1)).contains("réglée à la main"), "la compensation le dit déjà")
        XCTAssertTrue(lignes(IntentionBoitier(modeImage: 0x5)).contains("nuit"))
        XCTAssertTrue(lignes(IntentionBoitier(scene: 0x300)).contains("nuit"))
        XCTAssertFalse(lignes(IntentionBoitier(modeImage: 0x6)).contains("nuit"))

        let chrome = IntentionBoitier(simulation: 0x600)
        XCTAssertTrue(lignes(chrome, profil: "Camera CLASSIC CHROME", actuel: "Adobe Color").contains("partir du profil « Camera CLASSIC CHROME »"))
        XCTAssertTrue(lignes(chrome, profil: "Camera CLASSIC CHROME", actuel: "Camera Classic Chrome").contains("Le profil actuel est la simulation"),
                      "même profil, à la casse près")
        XCTAssertTrue(lignes(IntentionBoitier(simulation: 0xa00)).contains("NOSTALGIC Neg., sans profil Lightroom"))
        let jpeg = lignes(chrome, raw: false, profil: "Camera CLASSIC CHROME")
        XCTAssertTrue(jpeg.contains("JPEG de l'appareil : la simulation « CLASSIC CHROME »"), jpeg)
        XCTAssertFalse(jpeg.contains("partir du profil"), "un JPEG ne reçoit pas de profil")

        let dr400 = IntentionBoitier(reglagePlage: 1, plageDeveloppement: 400)
        XCTAssertTrue(lignes(dr400).contains("DR400") && lignes(dr400).contains("2 IL plus bas"), lignes(dr400))
        XCTAssertFalse(lignes(dr400, raw: false).contains("Plage dynamique"), "un JPEG porte déjà la plage")
        XCTAssertFalse(lignes(IntentionBoitier(reglagePlage: 0, plageAuto: 100)).contains("Plage dynamique"))
        XCTAssertTrue(lignes(IntentionBoitier(reglagePlage: 0x200)).contains("1 1/3 IL plus bas"), "DR230 des anciens boîtiers")

        XCTAssertFalse(lignes(IntentionBoitier(simulation: 0, tonsClairs: 0, tonsFonces: 0)).contains("Tons"))
        XCTAssertTrue(lignes(IntentionBoitier(tonsClairs: 1, tonsFonces: -1)).contains("tons clairs +1, tons foncés −1"))
        XCTAssertTrue(lignes(IntentionBoitier(tonsFonces: 0.5)).contains("Tons choisis au boîtier : tons foncés +0,5 "))
        XCTAssertTrue(lignes(IntentionBoitier(balance: 0x2)).contains("priorité à l'ambiance"))
        XCTAssertTrue(lignes(IntentionBoitier(balance: 0x1)).contains("priorité au blanc"))
        XCTAssertTrue(lignes(IntentionBoitier(priorite: 0, prioriteAuto: 2)).contains("Priorité à la plage dynamique (forte)"))
        XCTAssertFalse(lignes(IntentionBoitier(priorite: 1, prioriteFixe: 0)).contains("Priorité"), "niveau 0 : désactivée")
        XCTAssertTrue(IntentionBoitier(programme: 3).lecture(raw: true, profil: nil, profilActuel: nil).isEmpty)

        XCTAssertEqual(IntentionBoitier.texteIL(-0.667), "−2/3")
        XCTAssertEqual(IntentionBoitier.texteIL(1.333), "+1 1/3")
        XCTAssertEqual(IntentionBoitier.texteIL(-1), "−1")
        XCTAssertEqual(IntentionBoitier.texteIL(0.1), "0")
        XCTAssertEqual(IntentionBoitier.texteIL(2, signe: false), "2")
        XCTAssertEqual(IntentionBoitier.cran(-0.5), "−0,5")
        XCTAssertEqual(IntentionBoitier.cran(1), "+1")
        XCTAssertEqual(IntentionBoitier.cran(-1.5), "−1,5")
    }

    func testIntentionJSON() throws {
        let intention = IntentionBoitier(simulation: 0x600, saturation: 0x80, reglagePlage: 0, plageAuto: 200, priorite: 0, prioriteAuto: 1,
                                         tonsClairs: 1, tonsFonces: 0, balance: 0x2, modeImage: 0x5, compensation: -2.0 / 3, programme: 3)
        let raw = intention.json(raw: true, profil: "Camera CLASSIC CHROME", profilActuel: "Adobe Color")
        XCTAssertEqual(raw["simulation"]?.string, "CLASSIC CHROME")
        XCTAssertEqual(raw["profil"]?.string, "Camera CLASSIC CHROME")
        XCTAssertEqual(raw["couleur"]?.double, 1)
        XCTAssertEqual(raw["plage_dynamique"]?.string, "DR200 (auto)")
        XCTAssertEqual(raw["priorite_plage_dynamique"]?.string, "faible (auto)")
        XCTAssertEqual(raw["tons_clairs"]?.double, 1)
        XCTAssertNil(raw["tons_fonces"], "0 : rien à dire")
        XCTAssertEqual(raw["compensation"]?.double, -0.67)
        XCTAssertEqual(raw["mode"]?.string, "priorité à l'ouverture")
        XCTAssertEqual(raw["balance"]?.string, "Auto, priorité à l'ambiance")
        XCTAssertEqual(raw["scene"]?.string, "nuit")
        let lecture = try XCTUnwrap(raw["lecture"]?.array).compactMap(\.string)
        XCTAssertTrue(lecture.contains { $0.hasPrefix("Compensation −2/3 IL") })
        XCTAssertTrue(lecture.contains { $0.contains("partir du profil") })

        let jpeg = intention.json(raw: false, profil: "Camera CLASSIC CHROME", profilActuel: nil)
        XCTAssertNil(jpeg["profil"], "un JPEG ne reçoit pas de profil")
        XCTAssertNil(IntentionBoitier(saturation: 0x501).json(raw: true, profil: nil, profilActuel: nil)["couleur"], "noir et blanc")
        XCTAssertEqual(IntentionBoitier(reglagePlage: 1, plageDeveloppement: 400).json(raw: true, profil: nil, profilActuel: nil)["plage_dynamique"]?.string,
                       "DR400 (réglée)")
        XCTAssertNil(IntentionBoitier(programme: 3).json(raw: true, profil: nil, profilActuel: nil)["lecture"], "pas de lecture vide")
    }

    func testNotFujifilmOrUnreadable() throws {
        let dossier = TestSupport.temporaryDirectory()
        let autre = dossier.appendingPathComponent("IMG.JPG")
        try TestSupport.jpeg(red: 1, green: 2, blue: 3).write(to: autre)
        XCTAssertNil(LectureBoitier.lire(fichier: autre), "pas de MakerNote de Fujifilm")
        XCTAssertNil(LectureBoitier.lire(fichier: dossier.appendingPathComponent("absent.RAF")))

        let r = Self.reglages(tons: 9)
        let complet = F.fichier(note: r.note, exif: r.exif)
        let debut = try XCTUnwrap(F.debutNote(complet))
        let raf = dossier.appendingPathComponent("DSCF0005.RAF")
        // Coupé avant l'IFD de la MakerNote, dans son en-tête, puis dans l'en-tête du RAF : rien.
        for coupe in [debut + 13, debut + 4, 90] {
            try complet.prefix(coupe).write(to: raf)
            XCTAssertNil(LectureBoitier.lire(fichier: raf), "coupé à \(coupe)")
        }
        // Coupé dans l'IFD de la MakerNote : ses entrées manquent, l'Exif d'avant elle reste lu.
        try complet.prefix(debut + 16).write(to: raf)
        let partielle = try XCTUnwrap(LectureBoitier.lire(fichier: raf))
        XCTAssertNil(partielle.point)
        XCTAssertNil(partielle.intention?.nomSimulation)
        XCTAssertEqual(partielle.intention?.mode, "priorité à l'ouverture")
        // Un RAF dont le JPEG incorporé serait au-delà de la fin.
        var loin = complet
        loin.replaceSubrange(84..<88, with: [0, 0x10, 0, 0])
        try loin.write(to: raf)
        XCTAssertNil(LectureBoitier.lire(fichier: raf))
        try Data(repeating: 0xFF, count: 200).write(to: raf)
        XCTAssertNil(LectureBoitier.lire(fichier: raf))
        XCTAssertNil(LecteurBoitier(delai: 1).lire(raf))
    }

    /// La description de view_photo dit ce qu'est « intention_boitier » et qu'il faut la suivre.
    func testViewPhotoDescriptionNamesTheIntention() throws {
        let tools = ToolHandler(lightroom: FakeLightroom())
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "view_photo" })
        let description = try XCTUnwrap(outil["description"]?.string)
        XCTAssertTrue(description.contains("« intention_boitier » (fichiers Fujifilm, lue dans l'original)"))
        XCTAssertTrue(description.contains("une nuit voulue sombre reste sombre"))
        XCTAssertTrue(description.contains("choisie). region = zoom à 100 %"), "la phrase suivante reste entière")
    }
}
