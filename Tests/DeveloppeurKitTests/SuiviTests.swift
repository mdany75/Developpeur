import CoreGraphics
import Foundation
import XCTest
@testable import DeveloppeurKit

/// Le Suivi (correctif 1.3.7), côté connecteur, au-delà des exemples du contrat (ContratSuiviTests) :
/// textes, tranches, dates, périodes et « Tout », créneaux fixes, défaut le plus fréquent, objectifs
/// « Autres », carnet absent ou illisible, relevé absent, refus des arguments, codes cherchés selon
/// les visages, l'ISO et la taille, temps borné de --analyser. Tout passe par des fichiers
/// temporaires : jamais le vrai relevé de l'utilisateur, jamais Lightroom.
final class SuiviTests: XCTestCase {
    var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("suivi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dossier)
    }

    // MARK: Aides

    static let catalogue = "/essai/Catalogue.lrcat"
    static let tailles: JSONValue = [
        "photos_par_mois": ["largeur": 620, "hauteur": 150], "focales": ["largeur": 300, "hauteur": 130],
        "iso": ["largeur": 300, "hauteur": 130], "heures": ["largeur": 620, "hauteur": 120],
        "objectifs": ["largeur": 300, "hauteur": 170], "notes": ["largeur": 300, "hauteur": 170],
        "genres": ["largeur": 620, "hauteur": 190], "defauts_frequents": ["largeur": 620, "hauteur": 180],
        "evolution_defaut": ["largeur": 620, "hauteur": 140],
    ]
    static let claire: JSONValue = ["fond": "ECECEC", "texte": "1D1D1F", "gris": "6B6B6B", "filet": "C9C9C9", "barre": "0A64D8", "accent": "E0800D"]
    static let s4 = ["sous_exposition", "surexposition", "ciel_brule", "flou"]

    /// Une entrée du relevé (format 1), comme Releve.lua l'écrit.
    func photo(_ id: Int, prise: String? = "2026-11-08 17:42", ajout: String = "2026-11-10 09:00", objectif: String? = "XF23mmF2 R WR",
               focale: Double? = 23, iso: Double? = 400, note: Double = 0, drapeau: String = "aucun", retouchee: Bool = false,
               cherches: [String]? = s4,
               defauts: [String] = [], abandonnee: Bool = false, uuid: String? = nil, genre: String? = nil) -> (String, JSONValue) {
        var prisDeVue: [String: JSONValue] = [:]
        if let prise { prisDeVue["le"] = .string(prise) }
        if let objectif { prisDeVue["objectif"] = .string(objectif) }
        if let focale { prisDeVue["focale"] = .number(focale) }
        if let iso { prisDeVue["iso"] = .number(iso) }
        var entree: [String: JSONValue] = [
            "original": .number(Double(id)), "uuid": .string(uuid ?? "UUID-\(id)"), "fichier": .string("P\(id).RAF"),
            "ajout": 1_794_000_000, "ajout_le": .string(ajout), "vu": 1_794_000_000, "vues": [],
            "prise_de_vue": .object(prisDeVue), "note": .number(note), "drapeau": .string(drapeau),
            "retouchee_par_claude": .bool(retouchee), "classement_le": 1_794_000_000,
        ]
        if let cherches {
            var analyse: [String: JSONValue] = ["le": 1_794_000_060, "regles": 1, "cherches": .array(cherches.map(JSONValue.string)),
                                                "defauts": .array(defauts.map(JSONValue.string))]
            if let genre {
                analyse["genre"] = .string(genre)
                analyse["regles_genre"] = 1
            }
            entree["analyse"] = .object(analyse)
        } else if abandonnee {
            entree["analyse"] = ["le": 1_794_000_060, "erreur": "vignette_petite", "essais": 3, "abandonnee": true]
        }
        return (String(id), .object(entree))
    }

    /// Écrit un relevé (ou un fichier quelconque) et rend son chemin.
    func ecrire(_ photos: [(String, JSONValue)], format: Int = 1, nom: String = "suivi.json") throws -> String {
        let racine: JSONValue = ["format": .number(Double(format)),
                                 "catalogues": [Self.catalogue: ["photos": .object(Dictionary(uniqueKeysWithValues: photos))]]]
        let chemin = dossier.appendingPathComponent(nom).path
        try JSONCoding.line(racine).write(toFile: chemin, atomically: true, encoding: .utf8)
        return chemin
    }

    /// L'entrée de `--graphiques` : par défaut, l'année qui finit le 20 novembre 2026 (celle que la
    /// fenêtre Suivi montre d'abord) ; `debut` nil : depuis la première photo.
    func entree(suivi: String, carnet: String? = nil, debut: String? = "2025-11-20", fin: String = "2026-11-20", defaut: String? = nil,
                change: [String: JSONValue] = [:]) -> String {
        var objet: [String: JSONValue] = ["suivi": .string(suivi), "catalogue": .string(Self.catalogue), "fin": .string(fin),
                                          "apparence": "claire", "couleurs": Self.claire, "tailles": Self.tailles]
        if let debut { objet["debut"] = .string(debut) }
        if let carnet { objet["carnet"] = .string(carnet) }
        if let defaut { objet["defaut"] = .string(defaut) }
        for (cle, valeur) in change { objet[cle] = valeur }
        return JSONCoding.line(.object(objet))
    }

    /// `--graphiques` sur un relevé ; la réponse doit être ok.
    func graphiques(_ photos: [(String, JSONValue)], debut: String? = "2025-11-20", fin: String = "2026-11-20", defaut: String? = nil,
                    carnet: String? = nil, file: StaticString = #filePath, line: UInt = #line) throws -> JSONValue {
        let suivi = try ecrire(photos)
        let reponse = Suivi.graphiques(entree(suivi: suivi, carnet: carnet, debut: debut, fin: fin, defaut: defaut),
                                       dossier: dossier.appendingPathComponent("png-\(UUID().uuidString)").path)
        XCTAssertEqual(reponse.code, 0, JSONCoding.line(reponse.ligne), file: file, line: line)
        return reponse.ligne
    }

    func barres(_ sortie: JSONValue, _ graphique: String) -> [JSONValue] { sortie["graphiques"]?[graphique]?["barres"]?.array ?? [] }
    func creneaux(_ sortie: JSONValue, _ graphique: String) -> [Int] {
        (sortie["graphiques"]?[graphique]?["creneaux"]?.array ?? []).compactMap { $0["barre"]?.int }
    }

    // MARK: Textes, tranches, dates

    func testTextes() {
        XCTAssertEqual(Suivi.milliers(0), "0")
        XCTAssertEqual(Suivi.milliers(1284), "1 284")
        XCTAssertEqual(Suivi.milliers(1_234_567), "1 234 567")
        XCTAssertEqual(Suivi.photos(0), "0 photo")
        XCTAssertEqual(Suivi.photos(1), "1 photo")
        XCTAssertEqual(Suivi.photos(1284), "1 284 photos")
        XCTAssertEqual(Suivi.textePourcentage(0, sur: 0), "—")
        XCTAssertEqual(Suivi.textePourcentage(0, sur: 5), "0 %")
        XCTAssertEqual(Suivi.textePourcentage(1, sur: 200), "< 1 %")
        XCTAssertEqual(Suivi.textePourcentage(1, sur: 3), "33 %")
        XCTAssertEqual(Suivi.textePourcentage(2, sur: 3), "67 %")
        XCTAssertEqual(Suivi.textePourcentage(1, sur: 8), "13 %", "12,5 : demi vers le haut")
        XCTAssertEqual(Suivi.valeurPourcentage(1, sur: 3), 33.3)
        XCTAssertEqual(Suivi.valeurPourcentage(2, sur: 3), 66.7)
        XCTAssertEqual(Suivi.valeurPourcentage(1, sur: 16), 6.3, "6,25 : demi vers le haut")
        XCTAssertEqual(Suivi.valeurPourcentage(3, sur: 0), 0)
        XCTAssertEqual(Suivi.noteSans(1, "sans ISO lu"), "1 photo sans ISO lu n'y est pas.")
        XCTAssertEqual(Suivi.noteSans(2, "sans ISO lu"), "2 photos sans ISO lu n'y sont pas.")
    }

    func testTranches() {
        func focale(_ mm: Double) -> String { Suivi.tranchesFocales[Suivi.tranche(Double(Suivi.arrondi(mm)), Suivi.tranchesFocales)].libelle }
        XCTAssertEqual(focale(6.765), "≤ 15", "un iPhone")
        XCTAssertEqual(focale(15.4), "≤ 15")
        XCTAssertEqual(focale(15.5), "≤ 23", "arrondie au mm, demi vers le haut")
        XCTAssertEqual(focale(300), "≤ 300")
        XCTAssertEqual(focale(301), "> 300")
        func iso(_ valeur: Double) -> String { Suivi.tranchesISO[Suivi.tranche(valeur, Suivi.tranchesISO)].libelle }
        XCTAssertEqual(iso(100), "≤ 200")
        XCTAssertEqual(iso(1600), "≤ 1 600")
        XCTAssertEqual(iso(1601), "≤ 3 200")
        XCTAssertEqual(iso(12800), "≤ 12 800")
        XCTAssertEqual(iso(25600), "> 12 800")
    }

    func testDates() {
        XCTAssertEqual(Suivi.DateLocale("2026-11-08 17:42"), Suivi.DateLocale(annee: 2026, mois: 11, jour: 8, heure: 17))
        XCTAssertEqual(Suivi.DateLocale("2026-11-08")?.heure, nil)
        XCTAssertEqual(Suivi.DateLocale("2026-11-08")?.rangMois, 2026 * 12 + 10)
        XCTAssertNil(Suivi.DateLocale("2026-13-08 10:00"))
        XCTAssertNil(Suivi.DateLocale("2026/11/08"))
        XCTAssertNil(Suivi.DateLocale(""))
        XCTAssertNil(Suivi.DateLocale(nil))
    }

    // MARK: Périodes

    /// Un relevé absent : vide, rien n'est refusé ; tuiles et graphiques le disent, les images se
    /// dessinent quand même (« Aucune photo », « Aucun défaut »).
    func testReleveAbsent() throws {
        let png = dossier.appendingPathComponent("vide").path
        let reponse = Suivi.graphiques(entree(suivi: dossier.appendingPathComponent("absent.json").path), dossier: png)
        XCTAssertEqual(reponse.code, 0, JSONCoding.line(reponse.ligne))
        let sortie = reponse.ligne
        XCTAssertEqual(sortie["photos"]?.int, 0)
        XCTAssertEqual(sortie["periode"], ["debut": "2025-11-20", "fin": "2026-11-20", "libelle": "du 20 novembre 2025 au 20 novembre 2026",
                                           "par": "mois", "depuis_le_debut": false])
        let tuiles = try XCTUnwrap(sortie["tuiles"]?.array)
        XCTAssertEqual(tuiles[0]["detail"]?.string, "aucune photo dans la période")
        XCTAssertEqual(tuiles[1]["detail"]?.string, "—")
        XCTAssertEqual(tuiles[3]["texte"]?.string, "—")
        XCTAssertEqual(tuiles[3]["detail"]?.string, "aucune photo analysée")
        XCTAssertNil(tuiles[3]["code"])
        XCTAssertNil(sortie["defaut_suivi"])
        for cle in Suivi.graphiques {
            XCTAssertEqual(sortie["graphiques"]?[cle]?["vide"], true, cle)
            XCTAssertTrue(FileManager.default.fileExists(atPath: "\(png)/\(cle).png"), cle)
        }
        let evolution = try XCTUnwrap(sortie["graphiques"]?["evolution_defaut"])
        XCTAssertEqual(evolution["titre"]?.string, "Évolution d'un défaut")
        XCTAssertEqual(evolution["note"]?.string, "Aucun défaut trouvé dans la période.")
        XCTAssertEqual(barres(sortie, "evolution_defaut").count, 13, "treize mois touchés : de novembre à novembre")
        XCTAssertEqual(barres(sortie, "objectifs").count, 0)
        XCTAssertEqual(creneaux(sortie, "objectifs"), [Int](repeating: 0, count: 8))
    }

    /// Une date d'après le jour de fin (horloge de l'appareil fausse, ou une fin choisie) : hors de la
    /// période, comme une date d'avant le jour de début ; le jour de début et celui de fin sont
    /// compris, à toute heure ; une photo sans date du tout n'est d'aucune période.
    func testPhotoApresLaFin() throws {
        let photos = [photo(1, prise: "2026-11-21 08:00"), photo(2, prise: "2026-11-20 23:59"), photo(3, prise: nil, ajout: "pas une date"),
                      photo(4, prise: "2026-03-01 00:10"), photo(5, prise: "2026-02-28 23:59")]
        var sortie = try graphiques(photos, debut: nil)
        XCTAssertEqual(sortie["photos"]?.int, 3, "ni le 21 novembre, ni la photo sans date")
        XCTAssertEqual(barres(sortie, "photos_par_mois").last?["ids"], [2])
        sortie = try graphiques(photos, debut: "2026-03-01")
        XCTAssertEqual(sortie["photos"]?.int, 2, "le 1er mars et le 20 novembre")
        XCTAssertEqual(sortie["periode"]?["libelle"]?.string, "du 1er mars 2026 au 20 novembre 2026")
        XCTAssertEqual(barres(sortie, "photos_par_mois").map { $0["libelle"]?.string ?? "" },
                       ["mars 2026", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov."])
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "mars 2026 · 1 photo", "dès le 1er : le mois entier")
        sortie = try graphiques(photos, debut: "2026-11-20")
        XCTAssertEqual(sortie["periode"]?["libelle"]?.string, "le 20 novembre 2026")
        XCTAssertEqual(sortie["photos"]?.int, 1)
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "novembre 2026, le 20 · 1 photo")
        sortie = try graphiques(photos, debut: "2026-11-03")
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "novembre 2026, du 3 au 20 · 1 photo")
        sortie = try graphiques(photos, debut: "2026-03-01", fin: "2026-11-01")
        XCTAssertEqual(barres(sortie, "photos_par_mois").last?["detail"]?.string, "novembre 2026, le 1er · 0 photo",
                       "le seul 1er novembre : « le 1er », pas « jusqu'au 1er »")
        sortie = try graphiques(photos, debut: "2026-03-01", fin: "2026-11-02")
        XCTAssertEqual(barres(sortie, "photos_par_mois").last?["detail"]?.string, "novembre 2026, jusqu'au 2 · 0 photo")
        // Un seul jour au bord d'un mois : « le 1er », « le 30 », « le 29 » (février bissextile).
        for (jourSeul, attendu) in [("2026-11-01", "novembre 2026, le 1er"), ("2026-11-30", "novembre 2026, le 30"),
                                    ("2028-02-29", "février 2028, le 29")] {
            sortie = try graphiques(photos, debut: jourSeul, fin: jourSeul)
            XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "\(attendu) · 0 photo", jourSeul)
        }
        // Une première colonne couverte seulement sur son dernier jour.
        sortie = try graphiques(photos, debut: "2025-10-31", fin: "2026-10-20")
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "octobre 2025, le 31 · 0 photo")
    }

    /// Une année comptée d'un jour au même jour de l'année suivante touche treize mois : treize
    /// colonnes, une par créneau ; une période plus longue, mais de treize trimestres au plus, se
    /// montre par trimestre (« T1 2024 », « janvier à mars 2024 »).
    func testMoisEtTrimestres() throws {
        let photos = [photo(1, prise: "2025-11-20 10:00"), photo(2, prise: "2025-11-19 10:00"), photo(3, prise: "2024-02-10 10:00", defauts: ["flou"]),
                      photo(4, prise: "2026-11-20 10:00")]
        var sortie = try graphiques(photos)
        let mois = barres(sortie, "photos_par_mois")
        XCTAssertEqual(mois.count, 13)
        XCTAssertEqual(mois.first?["detail"]?.string, "novembre 2025, à partir du 20 · 1 photo", "le 19 novembre est avant le début")
        XCTAssertEqual(mois.last?["detail"]?.string, "novembre 2026, jusqu'au 20 · 1 photo")
        XCTAssertEqual(mois.map { $0["libelle"]?.string ?? "" },
                       ["nov. 2025", "déc.", "janv. 2026", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov."],
                       "l'année au premier mois et à janvier : novembre revient")
        XCTAssertEqual(creneaux(sortie, "photos_par_mois"), Array(1...13))
        XCTAssertEqual(sortie["graphiques"]?["photos_par_mois"]?["titre"]?.string, "Photos par mois")
        sortie = try graphiques(photos, debut: "2024-01-01", defaut: "flou")
        XCTAssertEqual(sortie["periode"]?["par"]?.string, "trimestre")
        let trimestres = barres(sortie, "photos_par_mois")
        XCTAssertEqual(trimestres.count, 12)
        XCTAssertEqual(trimestres.first?["libelle"]?.string, "T1 2024")
        XCTAssertEqual(trimestres.first?["detail"]?.string, "janvier à mars 2024 · 1 photo")
        XCTAssertEqual(trimestres.last?["libelle"]?.string, "T4 2026")
        XCTAssertEqual(trimestres.last?["detail"]?.string, "octobre à décembre 2026, jusqu'au 20 novembre · 1 photo")
        XCTAssertEqual(trimestres[7]["ids"], [1, 2], "T4 2025 : les 19 et 20 novembre 2025")
        XCTAssertEqual(sortie["graphiques"]?["photos_par_mois"]?["titre"]?.string, "Photos par trimestre")
        XCTAssertEqual(sortie["graphiques"]?["evolution_defaut"]?["titre"]?.string, "Photo floue ou bougée, trimestre par trimestre")
        XCTAssertEqual(creneaux(sortie, "photos_par_mois"), Array(1...12) + [0], "douze barres sur treize créneaux : la dernière place vide")
    }

    /// Un relevé lisible (JSON valide, format 1) dont des nombres sortent de la plage d'Int, abîmé ou
    /// édité à la main : jamais de plantage (« Double value cannot be converted to Int », ni ligne ni
    /// code 1 : la fenêtre Suivi ne dessinait plus rien). La valeur est ignorée et la réponse ok : une
    /// focale ou un ISO à 1e20 comptent « sans focale lue », « sans ISO lu » ; une note à ±1e20 est
    /// ramenée de 0 à 5 ; une entrée sans clé numérique à l'original 1e30 est ignorée.
    func testReleveAuxNombresHorsDePlage() throws {
        func changer(_ photo: (String, JSONValue), cle: String? = nil, _ change: (inout [String: JSONValue]) -> Void) -> (String, JSONValue) {
            guard case .object(var objet) = photo.1 else { return photo }
            change(&objet)
            return (cle ?? photo.0, .object(objet))
        }
        let sortie = try graphiques([
            photo(5001, focale: 1e20),
            photo(5002, iso: 1e20),
            changer(photo(5003)) { $0["note"] = .number(1e20) },
            changer(photo(5004)) { $0["note"] = .number(-1e20) },
            changer(photo(5005), cle: "abc") { $0["original"] = .number(1e30) },
            changer(photo(5006), cle: "def") { $0["original"] = .number(4.5) },
        ])
        XCTAssertEqual(sortie["photos"]?.int, 4, "les clés « abc » (original 1e30) et « def » (4,5) : ignorées")
        XCTAssertEqual(sortie["graphiques"]?["focales"]?["sans_valeur"]?.int, 1)
        XCTAssertEqual(sortie["graphiques"]?["focales"]?["note"]?.string, "1 photo sans focale lue n'y est pas.")
        XCTAssertEqual(sortie["graphiques"]?["iso"]?["sans_valeur"]?.int, 1)
        XCTAssertEqual(sortie["graphiques"]?["iso"]?["note"]?.string, "1 photo sans ISO lu n'y est pas.")
        let tuiles = try XCTUnwrap(sortie["tuiles"]?.array)
        XCTAssertEqual(tuiles[2]["cle"]?.string, "notees_4_plus")
        XCTAssertEqual(tuiles[2]["valeur"]?.int, 1, "la note à 1e20 ramenée à 5, celle à −1e20 à 0")
        // Une focale ou un ISO nul ou négatif n'est pas une valeur lue non plus ; une focale juste sous
        // la borne se range encore.
        XCTAssertNil(Suivi.plausible(0))
        XCTAssertNil(Suivi.plausible(-23))
        XCTAssertNil(Suivi.plausible(.infinity))
        XCTAssertEqual(Suivi.plausible(999_999), 999_999)
        XCTAssertEqual(Suivi.noteBornee(4.9), 4)
        XCTAssertEqual(Suivi.noteBornee(nil), 0)
        // L'arrondi ne plante jamais.
        XCTAssertEqual(Suivi.arrondi(1e300), Int.max)
        XCTAssertEqual(Suivi.arrondi(-1e300), Int.min)
        XCTAssertEqual(Suivi.arrondi(.nan), 0)
        XCTAssertEqual(Suivi.arrondi(2.5), 3)
        // Un nombre du JSON hors de la plage d'Int n'est pas un entier (2^63 plantait JSONValue.int).
        XCTAssertNil(JSONValue.number(9_223_372_036_854_775_808).int)
        XCTAssertNil(JSONValue.number(-1e300).int)
        XCTAssertNil(JSONValue.number(2.5).int)
        XCTAssertEqual(JSONValue.number(-9_223_372_036_854_775_808).int, Int.min)
        XCTAssertEqual(JSONValue.number(42).int, 42)
    }

    /// Depuis la première photo, sans photo datée : du jour d'ajout de la photo au jour de fin, mois
    /// par mois (deux colonnes de six créneaux) ; sans photo du tout, le mois de la fin seul.
    func testDepuisLeDebutSansPhotoDatee() throws {
        let sortie = try graphiques([photo(1, prise: nil, ajout: "2026-10-02 10:00")], debut: nil)
        XCTAssertEqual(sortie["periode"], ["debut": "2026-10-02", "fin": "2026-11-20",
                                           "libelle": "depuis la première photo, le 2 octobre 2026, jusqu'au 20 novembre 2026",
                                           "par": "mois", "depuis_le_debut": true])
        XCTAssertEqual(sortie["sans_date"]?.int, 1)
        XCTAssertEqual(barres(sortie, "photos_par_mois").compactMap { $0["libelle"]?.string }, ["oct. 2026", "nov."])
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "octobre 2026 · 0 photo",
                       "sans début, la première colonne n'est pas dite en partie")
        XCTAssertEqual(creneaux(sortie, "photos_par_mois"), [Int](repeating: 1, count: 6) + [Int](repeating: 2, count: 6) + [0])
        let vide = try graphiques([], debut: nil)
        XCTAssertEqual(vide["periode"]?["libelle"]?.string, "jusqu'au 20 novembre 2026")
        XCTAssertEqual(barres(vide, "photos_par_mois").compactMap { $0["libelle"]?.string }, ["nov. 2026"])
        XCTAssertEqual(sortie["graphiques"]?["photos_par_mois"]?["note"]?.string, "1 photo sans date de prise de vue n'y est pas.")
        XCTAssertEqual(sortie["graphiques"]?["heures"]?["sans_valeur"]?.int, 1)
        XCTAssertEqual(barres(sortie, "objectifs").first?["libelle"]?.string, "XF23mmF2 R WR", "l'objectif compte, lui")
    }

    /// Cinq années (plus de treize trimestres) : deux créneaux chacune, à partir du deuxième ; le
    /// premier et les deux derniers restent vides. Les rectangles des créneaux, eux, ne changent pas
    /// avec les barres.
    func testCinqAnnees() throws {
        let sortie = try graphiques([photo(1, prise: "2022-05-01 10:00", defauts: ["flou"]), photo(2, prise: "2026-05-01 10:00")], debut: nil)
        XCTAssertEqual(barres(sortie, "photos_par_mois").compactMap { $0["libelle"]?.string }, ["2022", "2023", "2024", "2025", "2026"])
        XCTAssertEqual(creneaux(sortie, "photos_par_mois"), [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 0, 0])
        XCTAssertEqual(sortie["graphiques"]?["photos_par_mois"]?["titre"]?.string, "Photos par année")
        XCTAssertEqual(sortie["graphiques"]?["evolution_defaut"]?["titre"]?.string, "Photo floue ou bougée, année par année")
        let douze = try graphiques([photo(1)])
        func rectangles(_ s: JSONValue, _ g: String) -> [JSONValue] {
            (s["graphiques"]?[g]?["creneaux"]?.array ?? []).map { creneau in
                .object((creneau.object ?? [:]).filter { $0.key != "barre" })
            }
        }
        for cle in Suivi.graphiques {
            XCTAssertEqual(rectangles(sortie, cle), rectangles(douze, cle), "\(cle) : les créneaux ne dépendent que de la taille")
            XCTAssertEqual(rectangles(sortie, cle).count, Suivi.definitions[cle]?.maxBarres, cle)
        }
    }

    /// Treize années tiennent, une par colonne ; au-delà, « < A » réunit les années d'avant les douze
    /// dernières.
    func testPlusDeTreizeAnnees() throws {
        let treize = try graphiques([photo(1, prise: "2014-05-01 10:00"), photo(2, prise: "2026-01-01 10:00")], debut: nil)
        XCTAssertEqual(barres(treize, "photos_par_mois").first?["libelle"]?.string, "2014")
        XCTAssertEqual(barres(treize, "photos_par_mois").count, 13)
        let sortie = try graphiques([photo(1, prise: "2012-05-01 10:00"), photo(2, prise: "2014-07-01 10:00"),
                                     photo(3, prise: "2015-01-01 10:00"), photo(4, prise: "2026-01-01 10:00")], debut: nil)
        let libelles = barres(sortie, "photos_par_mois").compactMap { $0["libelle"]?.string }
        XCTAssertEqual(libelles.count, 13)
        XCTAssertEqual(libelles.first, "< 2015")
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["ids"], [1, 2])
        XCTAssertEqual(barres(sortie, "photos_par_mois").first?["detail"]?.string, "avant 2015 · 2 photos")
        XCTAssertEqual(libelles[1], "2015")
    }

    // MARK: Défauts

    /// Le défaut le plus fréquent doit être cherché sur au moins cinq photos ; sinon, le plus haut
    /// parmi ceux trouvés une fois.
    func testDefautLePlusFrequent() throws {
        // Le flou : 1 photo sur 6 (17 %) ; le bruit : 2 sur 2 (100 %), mais sur trop peu de photos.
        var photos = (1...6).map { photo($0, cherches: Self.s4, defauts: $0 == 1 ? ["flou"] : []) }
        photos[1] = photo(2, iso: 3200, cherches: ["sous_exposition", "surexposition", "ciel_brule", "bruit", "flou"], defauts: ["bruit"])
        photos[2] = photo(3, iso: 3200, cherches: ["sous_exposition", "surexposition", "ciel_brule", "bruit", "flou"], defauts: ["bruit"])
        var sortie = try graphiques(photos)
        XCTAssertEqual(sortie["defaut_suivi"], ["code": "flou", "libelle": "Photo floue ou bougée", "choisi": false])
        XCTAssertEqual(sortie["tuiles"]?.array?.last?["detail"]?.string, "Photo floue ou bougée · 1 photo sur 6")
        // Le graphique les range quand même au pourcentage : le bruit en tête, le flou en accent.
        XCTAssertEqual(barres(sortie, "defauts_frequents").first?["libelle"]?.string, "Bruit fort (ISO élevé)")
        XCTAssertEqual(barres(sortie, "defauts_frequents").first { $0["libelle"]?.string == "Photo floue ou bougée" }?["couleur"], "accent")
        // Aucun code cherché sur cinq photos : le plus haut des codes trouvés.
        sortie = try graphiques(Array(photos.prefix(3)))
        XCTAssertEqual(sortie["defaut_suivi"]?["code"]?.string, "bruit")
        // Aucun défaut trouvé : « Aucun », sans défaut suivi ni code.
        sortie = try graphiques((1...3).map { photo($0) })
        XCTAssertEqual(sortie["tuiles"]?.array?.last?["texte"]?.string, "Aucun")
        XCTAssertEqual(sortie["tuiles"]?.array?.last?["detail"]?.string, "aucun défaut trouvé sur les 3 photos analysées")
        XCTAssertNil(sortie["defaut_suivi"])
        XCTAssertEqual(sortie["graphiques"]?["evolution_defaut"]?["vide"], true)
    }

    /// Un défaut choisi, cherché sur aucune photo : suivi quand même, ses colonnes le disent.
    func testDefautChoisiJamaisCherche() throws {
        let sortie = try graphiques([photo(1, defauts: ["flou"])], defaut: "horizon_penche")
        XCTAssertEqual(sortie["defaut_suivi"], ["code": "horizon_penche", "libelle": "Horizon ou ligne penchée", "choisi": true])
        let evolution = barres(sortie, "evolution_defaut")
        XCTAssertTrue(evolution.allSatisfy { $0["texte"]?.string == "—" && $0["sur"]?.int == 0 && $0["couleur"]?.string == "accent" })
        XCTAssertEqual(evolution.last?["detail"]?.string, "novembre 2026, jusqu'au 20 · défaut cherché sur aucune photo")
        XCTAssertEqual(sortie["graphiques"]?["evolution_defaut"]?["vide"], true)
        XCTAssertEqual(sortie["graphiques"]?["evolution_defaut"]?["titre"]?.string, "Horizon ou ligne penchée, mois par mois")
        // Une photo abandonnée ou en file n'est cherchée pour aucun code de l'analyse.
        let autre = try graphiques([photo(1, cherches: nil, abandonnee: true), photo(2, cherches: nil)])
        XCTAssertEqual(autre["analyse"], ["analysees": 0, "en_attente": 1, "en_echec": 1])
        // La tuile « Photos analysées » (1.4) : aucune analysée, et le reste dit dessous.
        XCTAssertEqual(autre["tuiles"]?.array?.first?["titre"]?.string, "Photos analysées")
        XCTAssertEqual(autre["tuiles"]?.array?.first?["valeur"]?.int, 0)
        XCTAssertEqual(autre["tuiles"]?.array?.first?["detail"]?.string, "sur 2 photos · 1 en cours d'analyse · 1 non analysée")
        XCTAssertTrue((autre["defauts"]?.array ?? []).allSatisfy { $0["sur"]?.int == 0 })
    }

    /// Plus de huit objectifs : les sept premiers, puis « Autres », qui réunit le reste, ids compris.
    func testObjectifsAutres() throws {
        let photos = (1...9).map { photo($0, objectif: "Objectif \($0)") } + [photo(10, objectif: "Objectif 1")]
        let sortie = try graphiques(photos)
        let objectifs = barres(sortie, "objectifs")
        XCTAssertEqual(objectifs.count, 8)
        XCTAssertEqual(objectifs.first?["libelle"]?.string, "Objectif 1")
        XCTAssertEqual(objectifs.first?["ids"], [1, 10])
        XCTAssertEqual(objectifs.last?["libelle"]?.string, "Autres")
        XCTAssertEqual(objectifs.last?["detail"]?.string, "2 autres objectifs · 2 photos")
        XCTAssertEqual(objectifs.last?["ids"], [8, 9])
        XCTAssertEqual(creneaux(sortie, "objectifs"), Array(1...8))
    }

    /// Le graphique des genres (correctif 1.3.8) : un genre par barre, ceux qui ont des photos, par
    /// nombre décroissant puis dans l'ordre des genres, « Autre » toujours en dernier ; le détail en %
    /// des photos classées ; une photo sans genre (en file, abandonnée, analysée avant le genre, ou d'un
    /// code inconnu) n'y est pas, et la note le dit ; sans genre, vide.
    func testGenres() throws {
        let photos = [photo(1, genre: "autre"), photo(2, genre: "autre"), photo(3, genre: "autre"), photo(4, genre: "paysage"),
                      photo(5, genre: "paysage"), photo(6, genre: "portrait"), photo(7, genre: "sport"), photo(8, genre: "famille"),
                      photo(9), photo(10, cherches: nil), photo(11, cherches: nil, abandonnee: true), photo(12, genre: "inconnu")]
        let sortie = try graphiques(photos)
        let genres = barres(sortie, "genres")
        XCTAssertEqual(genres.compactMap { $0["libelle"]?.string }, ["Paysage", "Sport", "Famille et groupes", "Portrait", "Autre"],
                       "par nombre, puis l'ordre des genres ; Autre en dernier même plus nombreux")
        XCTAssertEqual(genres.first?["detail"]?.string, "Paysage · 2 photos (25 %)")
        XCTAssertEqual(genres.last?["detail"]?.string, "Autre · 3 photos (38 %)")
        XCTAssertEqual(genres.first?["ids"], [4, 5])
        XCTAssertEqual(genres.last?["ids"], [1, 2, 3])
        let graphique = try XCTUnwrap(sortie["graphiques"]?["genres"])
        XCTAssertEqual(graphique["titre"]?.string, "Genres de photos")
        XCTAssertEqual(graphique["orientation"]?.string, "horizontale")
        XCTAssertEqual(graphique["max_barres"]?.int, 11)
        XCTAssertEqual(graphique["sans_valeur"]?.int, 4, "en file, abandonnée, sans genre, code inconnu")
        XCTAssertEqual(graphique["note"]?.string,
                       "Lu sur la vignette par Vision (Apple) : une tendance. 3 photos pas encore classées · 1 non analysée.",
                       "l'abandonnée ne sera jamais classée : dite à part, comme la tuile")
        XCTAssertEqual(creneaux(sortie, "genres"), [1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0])
        let seule = try graphiques([photo(1, genre: "macro")])
        XCTAssertEqual(seule["graphiques"]?["genres"]?["note"]?.string, "Lu sur la vignette par Vision (Apple) : une tendance, pas un classement sûr.")
        XCTAssertEqual(barres(seule, "genres").first?["detail"]?.string, "Macro et gros plans · 1 photo (100 %)")
        let une = try graphiques([photo(1, genre: "macro"), photo(2)])
        XCTAssertEqual(une["graphiques"]?["genres"]?["note"]?.string, "Lu sur la vignette par Vision (Apple) : une tendance. 1 photo pas encore classée.")
        let sans = try graphiques([photo(1), photo(2)])
        XCTAssertEqual(sans["graphiques"]?["genres"]?["vide"], true)
        XCTAssertEqual(barres(sans, "genres").count, 0)
        XCTAssertEqual(try graphiques([])["graphiques"]?["genres"]?["vide"], true)
        let abandonnees = try graphiques([photo(1, cherches: nil, abandonnee: true), photo(2, cherches: nil, abandonnee: true)])
        XCTAssertEqual(abandonnees["graphiques"]?["genres"]?["note"]?.string,
                       "Lu sur la vignette par Vision (Apple) : une tendance. 2 non analysées.")
        // Le texte d'un graphique vide : « Pas encore classées » s'il y a des photos dans la période,
        // « Aucune photo » sinon, comme les autres graphiques.
        func texteVide(_ photos: [(String, JSONValue)]) throws -> String? {
            let entree = try Suivi.lireEntree(entree(suivi: try ecrire(photos)))
            let lus = try Suivi.lireReleve(entree.suivi, catalogue: entree.catalogue)
            return Suivi.calculer(entree, photos: lus, remarques: [], dossier: dossier.path).graphiques.first { $0.cle == "genres" }?.texteVide
        }
        XCTAssertEqual(try texteVide([photo(1), photo(2)]), "Pas encore classées")
        XCTAssertEqual(try texteVide([]), "Aucune photo")
        XCTAssertEqual(try texteVide([photo(1, prise: "2019-05-01 10:00")]), "Aucune photo", "une photo hors de la période")
        // Tous les genres à la fois : onze barres, autant que de créneaux.
        let tous = try graphiques(Genre.codes.enumerated().map { photo($0.offset + 1, genre: $0.element) })
        XCTAssertEqual(barres(tous, "genres").count, 11)
        XCTAssertEqual(barres(tous, "genres").compactMap { $0["libelle"]?.string }, Genre.liste.map(\.libelle), "à égalité : l'ordre des genres")
    }

    /// Les notes (correctif 1.3.8) : six barres de 0 ★ (pas encore notée) à 5 ★, la note de la
    /// famille bornée et tronquée comme le module la relit ; une photo rejetée compte à sa note, et la
    /// note du graphique le dit (au singulier, au pluriel) ; sans photo, le graphique est vide.
    func testNotes() throws {
        let photos = [photo(1, note: 5), photo(2, note: 4, drapeau: "retenue"), photo(3, note: 4.9), photo(4, note: 0, drapeau: "rejetee"),
                      photo(5, note: 1e20), photo(6, note: -3), photo(7, note: 2, drapeau: "rejetee")]
        let sortie = try graphiques(photos)
        let notes = barres(sortie, "notes")
        XCTAssertEqual(notes.map { $0["libelle"]?.string ?? "" }, ["0 ★", "1 ★", "2 ★", "3 ★", "4 ★", "5 ★"])
        XCTAssertEqual(notes.map { $0["ids"] ?? .null }, [[4, 6], [], [7], [], [2, 3], [1, 5]])
        XCTAssertEqual(notes[0]["detail"]?.string, "0 ★, pas encore notée · 2 photos")
        XCTAssertEqual(notes[5]["detail"]?.string, "5 ★ · 2 photos")
        XCTAssertEqual(notes[1]["detail"]?.string, "1 ★ · 0 photo")
        XCTAssertEqual(creneaux(sortie, "notes"), Array(1...6))
        let graphique = try XCTUnwrap(sortie["graphiques"]?["notes"])
        XCTAssertEqual(graphique["titre"]?.string, "Notes")
        XCTAssertEqual(graphique["note"]?.string, "Dont 2 rejetées (drapeau), comptées à leur note.")
        XCTAssertEqual(graphique["vide"], false)
        XCTAssertEqual(graphique["orientation"]?.string, "verticale")
        XCTAssertEqual(sortie["tuiles"]?.array?[2]["valeur"]?.int, 4, "la tuile « Notées 4 ★ ou plus » : les deux dernières barres")
        let une = try graphiques([photo(1, note: 3, drapeau: "rejetee"), photo(2, note: 3)])
        XCTAssertEqual(une["graphiques"]?["notes"]?["note"]?.string, "Dont 1 rejetée (drapeau), comptée à sa note.")
        XCTAssertNil(try graphiques([photo(1, note: 3)])["graphiques"]?["notes"]?["note"], "rien à dire sans rejet")
        XCTAssertEqual(try graphiques([])["graphiques"]?["notes"]?["vide"], true)
    }

    // MARK: Le carnet

    /// Carnet absent : l'analyse seule, sans remarque ; illisible : de même, avec la remarque ; un
    /// autre uuid : ignoré ; le même : l'horizon mesuré par Claude compte, et l'emporte sur l'analyse.
    func testCarnet() throws {
        let photos = [photo(1, defauts: ["flou"]), photo(2)]
        var sortie = try graphiques(photos, carnet: dossier.appendingPathComponent("absent.json").path)
        XCTAssertEqual(sortie["remarques"], [])
        XCTAssertEqual(sortie["defauts"]?.array?.first?["sur"]?.int, 0, "l'horizon ne vient que du carnet")

        let illisible = dossier.appendingPathComponent("carnet-illisible.json")
        try "{ pas du JSON".write(to: illisible, atomically: true, encoding: .utf8)
        sortie = try graphiques(photos, carnet: illisible.path)
        XCTAssertEqual(sortie["remarques"], [.string(Suivi.carnetIllisible)])
        XCTAssertEqual(sortie["defauts"]?.array?.first?["sur"]?.int, 0)

        let carnet: JSONValue = ["format": 1, "catalogues": [Self.catalogue: ["photos": [
            "1": ["photo": 1, "uuid": "UUID-1", "vue": ["cherches": ["flou", "horizon_penche"], "defauts": []],
                  "angle": ["code": "horizon_penche", "inclinaison": 1.2]],
            "2": ["photo": 2, "uuid": "UNE-AUTRE", "angle": ["code": "horizon_penche"]],
            "3": ["photo": 3, "uuid": "UUID-3", "angle": ["code": "horizon_penche"]],
        ]]]]
        let chemin = dossier.appendingPathComponent("carnet.json")
        try JSONCoding.line(carnet).write(to: chemin, atomically: true, encoding: .utf8)
        sortie = try graphiques(photos, carnet: chemin.path)
        let defauts = try XCTUnwrap(sortie["defauts"]?.array)
        XCTAssertEqual(defauts[0]["code"]?.string, "horizon_penche")
        XCTAssertEqual(defauts[0]["n"]?.int, 1)
        XCTAssertEqual(defauts[0]["sur"]?.int, 1, "l'autre uuid ne compte pas, ni une entrée absente du relevé")
        let flou = try XCTUnwrap(defauts.first { $0["code"]?.string == "flou" })
        XCTAssertEqual(flou["n"]?.int, 0, "le carnet a cherché le flou de la photo 1 sans le trouver : il l'emporte")
        XCTAssertEqual(flou["sur"]?.int, 2)
    }

    // MARK: Les refus

    func testRefusDesArguments() throws {
        let suivi = try ecrire([photo(1)])
        let png = dossier.appendingPathComponent("refus").path
        func refus(_ texte: String) -> Suivi.Reponse { Suivi.graphiques(texte, dossier: png) }
        let cas: [(String, String, String)] = [
            ("pas du JSON", "arguments", "Arguments de --graphiques : le JSON ne se lit pas (un objet attendu, comme graphiques.entree du contrat)."),
            (entree(suivi: suivi, change: ["fin": "20/11/2026"]), "arguments",
             "Arguments de --graphiques : fin est le dernier jour de la période, AAAA-MM-JJ, à l'heure locale."),
            (entree(suivi: suivi, change: ["fin": "2026-02-29"]), "arguments",
             "Arguments de --graphiques : fin est le dernier jour de la période, AAAA-MM-JJ, à l'heure locale."),
            (entree(suivi: suivi, change: ["debut": "2026-04-31"]), "arguments",
             "Arguments de --graphiques : debut, facultatif, est le premier jour de la période, AAAA-MM-JJ, à l'heure locale."),
            (entree(suivi: suivi, change: ["debut": "2026-11-21"]), "arguments", "Arguments de --graphiques : debut ne vient pas après fin."),
            (entree(suivi: suivi, change: ["apparence": "auto"]), "arguments", "Arguments de --graphiques : apparence vaut claire ou sombre."),
            (entree(suivi: suivi, change: ["fin": "0000-01-05"]), "arguments",
             "Arguments de --graphiques : fin est le dernier jour de la période, AAAA-MM-JJ, à l'heure locale."),
            (entree(suivi: suivi, change: ["tailles": ["focales": ["largeur": 300, "hauteur": 130]]]), "arguments",
             "Arguments de --graphiques : tailles.photos_par_mois va de 120 × 80 à 1 200 × 600 points."),
            (entree(suivi: suivi, change: ["catalogue": 3]), "arguments", "Arguments de --graphiques : catalogue est le chemin du catalogue ouvert."),
            (entree(suivi: suivi, change: ["defaut": 3]), "arguments", "Arguments de --graphiques : defaut, facultatif, est l'un des huit codes comptés."),
        ]
        for (texte, raison, attendu) in cas {
            let reponse = refus(texte)
            XCTAssertEqual(reponse.code, 1, attendu)
            XCTAssertEqual(reponse.ligne, ["ok": false, "raison": .string(raison), "texte": .string(attendu)])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: png), "rien n'est écrit")
        // Un dossier qui ne se crée pas : sous un fichier.
        let fichier = dossier.appendingPathComponent("un-fichier")
        try "x".write(to: fichier, atomically: true, encoding: .utf8)
        let reponse = Suivi.graphiques(entree(suivi: suivi), dossier: fichier.appendingPathComponent("png").path)
        XCTAssertEqual(reponse.code, 1)
        XCTAssertEqual(reponse.ligne["raison"]?.string, "dossier")
    }

    func testRefusDAnalyser() {
        func refus(_ texte: String) -> String? {
            let reponse = Suivi.analyser(texte) { _ in .null }
            XCTAssertEqual(reponse.code, 1, texte)
            XCTAssertEqual(reponse.ligne["raison"]?.string, "arguments", texte)
            return reponse.ligne["texte"]?.string
        }
        XCTAssertEqual(refus("{"), "Arguments de --analyser : le JSON ne se lit pas (un objet { photos: [ … ] } attendu).")
        XCTAssertEqual(refus("{\"photos\": []}"), "Arguments de --analyser : photos est un tableau de 1 à 20 photos.")
        XCTAssertEqual(refus("{\"photos\": [{\"id\": 1, \"vignette\": \"/a.jpg\", \"iso\": \"400\"}]}"),
                       "Arguments de --analyser : photos[1].iso est un nombre (absent : inconnu).")
        XCTAssertEqual(refus("{\"photos\": [{\"id\": 1, \"vignette\": \"/a.jpg\"}, {\"id\": 2, \"vignette\": \"/b.jpg\", \"cache\": 1}]}"),
                       "Arguments de --analyser : photos[2].cache est un booléen.")
        XCTAssertEqual(refus("{\"photos\": [{\"id\": 1.5, \"vignette\": \"/a.jpg\"}]}"),
                       "Arguments de --analyser : photos[1].id est un nombre (l'id de l'original).")
        XCTAssertEqual(refus("{\"photos\": [{\"id\": 1}]}"),
                       "Arguments de --analyser : photos[1].vignette est le chemin d'un JPEG (la vignette, déjà redressée).")
    }

    // MARK: --analyser

    /// Les codes cherchés et trouvés d'une vignette mesurée : les yeux seulement sur un sujet dont
    /// les yeux se lisent, le bruit seulement à ISO élevé et à 1 024 px, la surexposition au-delà de
    /// 35 % de blanc pur, et seulement le flou et les yeux sur une photo retouchée par Claude.
    func testCodesCherchesEtTrouves() {
        func mesures(blanc: Double = 0) -> PhotoMeasurements {
            PhotoMeasurements(meanL: 50, percentilesL: [1: 5, 5: 10, 25: 40, 50: 50, 75: 60, 95: 90, 99: 95],
                              histogramL: [Double](repeating: 10, count: 10), clippedHighlights: 0, pureWhite: blanc,
                              crushedShadows: 0, clippedChannels: [0, 0, 0], meanChroma: 12, saturatedShare: 0,
                              neutralA: 0, neutralB: 0, neutralShare: 30, pixelCount: 512 * 341)
        }
        func detail(nettete: Double = 60, bruit: Double = 2, side: Int = 1024) -> DetailMeasurements {
            DetailMeasurements(zones: [Double](repeating: nettete, count: 9), noise: bruit, shadowNoise: nil, side: side)
        }
        func visage(_ largeur: Double, _ ouverture: Double?) -> VisionReport.Face {
            VisionReport.Face(box: CGRect(x: 0.3, y: 0.2, width: largeur, height: largeur), pupils: [], eyeWidth: nil, quality: nil,
                              eyeOpenness: ouverture)
        }
        func vision(_ visages: [VisionReport.Face]) -> VisionReport { VisionReport(faces: visages, aesthetics: nil, utility: nil, salientArea: nil) }
        let gris = TestSupport.imagePixels(width: 300, height: 300) { _, _ in (120, 120, 120) }
        func codes(mesures m: PhotoMeasurements? = nil, detail d: DetailMeasurements? = nil, vision v: VisionReport? = nil, iso: Double? = 400,
                   retouchee: Bool = false) -> (cherches: [String], defauts: [String]) {
            Suivi.codesTrouves(mesures: m ?? mesures(), detail: d ?? detail(), reduite: gris, vision: v, iso: iso, retouchee: retouchee)
        }
        XCTAssertEqual(codes().cherches, ["sous_exposition", "surexposition", "ciel_brule", "flou"])
        XCTAssertEqual(codes().defauts, [])
        XCTAssertEqual(codes(iso: 1600).cherches, ["sous_exposition", "surexposition", "ciel_brule", "bruit", "flou"])
        XCTAssertEqual(codes(iso: 1600).defauts, ["bruit"], "bruit de 2 : au-delà de 1,5")
        XCTAssertFalse(codes(iso: 1599).cherches.contains("bruit"))
        XCTAssertFalse(codes(iso: nil).cherches.contains("bruit"), "ISO inconnu")
        XCTAssertEqual(codes(detail: detail(side: 950), iso: 3200).cherches, ["sous_exposition", "surexposition", "ciel_brule"], "sous 1 024 px")
        XCTAssertEqual(codes(detail: detail(nettete: 10)).defauts, ["flou"])
        XCTAssertEqual(codes(mesures: mesures(blanc: 36)).defauts, ["surexposition"])
        XCTAssertEqual(codes(mesures: mesures(blanc: 35)).defauts, [], "35 % : pas encore brûlée")
        // Les yeux.
        XCTAssertFalse(codes(vision: vision([])).cherches.contains("yeux_fermes"), "sans visage")
        XCTAssertFalse(codes(vision: vision([visage(0.3, nil)])).cherches.contains("yeux_fermes"), "yeux trop petits pour se lire")
        XCTAssertEqual(codes(vision: vision([visage(0.3, 0.05)])).defauts, ["yeux_fermes"])
        XCTAssertEqual(codes(vision: vision([visage(0.3, 0.3)])).cherches.last, "yeux_fermes")
        XCTAssertEqual(codes(vision: vision([visage(0.3, 0.3)])).defauts, [])
        XCTAssertEqual(codes(vision: vision([visage(0.3, 0.3), visage(0.1, 0.05)])).defauts, [], "un petit visage au fond n'est pas un sujet")
        // Retouchée par Claude : le flou et les yeux seulement.
        let retouchee = codes(mesures: mesures(blanc: 50), detail: detail(nettete: 10), vision: vision([visage(0.3, 0.05)]), iso: 6400,
                              retouchee: true)
        XCTAssertEqual(retouchee.cherches, ["flou", "yeux_fermes"])
        XCTAssertEqual(retouchee.defauts, ["flou", "yeux_fermes"])
    }

    /// Une vignette illisible, ou de 900 à 1 023 px : la raison, ou ni flou ni bruit.
    func testAnalyserVignettes() throws {
        let illisible = dossier.appendingPathComponent("illisible.jpg")
        try Data("pas une image".utf8).write(to: illisible)
        let moyenne = dossier.appendingPathComponent("moyenne.jpg")
        try ContratSuiviTests.vignette(largeur: 950, hauteur: 633).write(to: moyenne)
        let entree: JSONValue = ["photos": [["id": 1, "vignette": .string(illisible.path), "cache": true],
                                            ["id": 2, "vignette": .string(moyenne.path), "iso": 3200, "cache": true]]]
        let reponse = Suivi.analyser(JSONCoding.line(entree))
        XCTAssertEqual(reponse.code, 0)
        let photos = try XCTUnwrap(reponse.ligne["photos"]?.array)
        XCTAssertEqual(photos[0], ["id": 1, "raison": "vignette_illisible", "texte": .string("Vignette illisible : \(illisible.path) n'est pas une image.")])
        XCTAssertEqual(photos[1]["cherches"], ["sous_exposition", "surexposition", "ciel_brule"], "les seuils de netteté et de bruit valent à 1 024 px")
        XCTAssertEqual(photos[1]["mesures"]?["cote"]?.int, 950)
    }

    /// Une mesure trop longue n'empêche pas la ligne de partir : sa photo a la raison `delai`.
    func testAnalyserTempsBorneParPhoto() throws {
        let entree: JSONValue = ["photos": .array((1...4).map { ["id": .number(Double($0)), "vignette": "/nulle/part.jpg"] })]
        let debut = Date()
        let reponse = Suivi.analyser(JSONCoding.line(entree), delaiParPhoto: 0.3, delaiTotal: 10) { photo in
            if photo.id == 2 { Thread.sleep(forTimeInterval: 3) }
            return ["id": .number(Double(photo.id)), "cherches": [], "defauts": [], "mesures": [:]]
        }
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2.5)
        let photos = try XCTUnwrap(reponse.ligne["photos"]?.array)
        XCTAssertEqual(photos.compactMap { $0["id"]?.int }, [1, 2, 3, 4])
        XCTAssertEqual(photos.map { $0["raison"]?.string }, [nil, "delai", nil, nil])
    }

    /// Et l'appel entier : les photos pas finies, ou pas commencées, à temps ont la raison `delai`.
    func testAnalyserTempsBorneEnTout() throws {
        let entree: JSONValue = ["photos": .array((1...6).map { ["id": .number(Double($0)), "vignette": "/nulle/part.jpg"] })]
        let debut = Date()
        let reponse = Suivi.analyser(JSONCoding.line(entree), delaiParPhoto: 10, delaiTotal: 1) { photo in
            Thread.sleep(forTimeInterval: [3, 4].contains(photo.id) ? 3 : photo.id <= 2 ? 0.1 : 0.5)
            return ["id": .number(Double(photo.id)), "cherches": [], "defauts": [], "mesures": [:]]
        }
        XCTAssertLessThan(Date().timeIntervalSince(debut), 2.5)
        let photos = try XCTUnwrap(reponse.ligne["photos"]?.array)
        XCTAssertEqual(photos.map { $0["raison"]?.string }, [nil, nil, "delai", "delai", "delai", "delai"])
    }

    // MARK: Les fichiers de l'utilisateur

    /// Aucun chemin par défaut : le Suivi du connecteur ne lit que les fichiers que la commande
    /// nomme (jamais le vrai suivi.json ni le vrai carnet.json de l'utilisateur).
    func testAucunCheminParDefaut() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DeveloppeurKit")
        for nom in ["Suivi.swift", "SuiviGraphiques.swift", "SuiviDessin.swift"] {
            let texte = try String(contentsOf: sources.appendingPathComponent(nom), encoding: .utf8)
            for interdit in ["Application Support", "homeDirectoryForCurrentUser", "NSHomeDirectory", "LightroomBridge"] {
                XCTAssertFalse(texte.contains(interdit), "\(nom) : \(interdit)")
            }
        }
    }
}
