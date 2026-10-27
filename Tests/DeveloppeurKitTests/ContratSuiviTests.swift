import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import DeveloppeurKit

/// Le contrat du Suivi (correctif 1.3.7) entre le module (Releve.lua, FenetreSuivi.lua) et le
/// connecteur (`--analyser`, `--graphiques`), figé dans Tests/Contrats/suivi.json : ses `regles`
/// disent ce que les deux côtés appliquent, ses `exemples` en découlent exactement. Ici :
/// `--graphiques` sur le relevé et le carnet d'exemple rend exactement les sorties des cinq exemples
/// (les clés données pour un exemple « partiel ») et des PNG de 2 × la taille demandée ; les refus de
/// tout l'appel rendent exactement leur ligne ; `--analyser` se vérifie sur des vignettes fabriquées
/// par sa forme (clés, types, codes cherchés selon l'ISO, retouchee et la taille) et ses refus.
/// Côté Lua, essais-suivi.lua lit le même fichier. Tout passe par des fichiers temporaires : jamais le
/// vrai relevé de l'utilisateur.
final class ContratSuiviTests: XCTestCase {
    static let fichier = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Contrats").appendingPathComponent("suivi.json")

    var dossier: URL!

    override func setUpWithError() throws {
        dossier = FileManager.default.temporaryDirectory.appendingPathComponent("contrat-suivi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dossier)
    }

    // MARK: Aides

    func contrat() throws -> JSONValue {
        try JSONCoding.parse(String(contentsOf: Self.fichier, encoding: .utf8))
    }

    func objet(_ valeur: JSONValue?, _ quoi: String) throws -> [String: JSONValue] {
        try XCTUnwrap(valeur?.object, "contrat : \(quoi) manque")
    }

    func exemple(_ nom: String) throws -> [String: JSONValue] {
        try objet(try contrat()["exemples"]?[nom], "exemples.\(nom)")
    }

    /// Les commentaires `_note` retirés, partout.
    static func sansNotes(_ valeur: JSONValue) -> JSONValue {
        switch valeur {
        case .object(let objet):
            return .object(objet.filter { $0.key != "_note" }.mapValues(sansNotes))
        case .array(let liste):
            return .array(liste.map(sansNotes))
        default:
            return valeur
        }
    }

    /// Les textes à remplacer (<suivi.json>, <dossier>, <lot>…) par leurs chemins d'essai.
    static func remplacer(_ valeur: JSONValue, _ textes: [String: String]) -> JSONValue {
        switch valeur {
        case .string(var texte):
            for (motif, chemin) in textes { texte = texte.replacingOccurrences(of: motif, with: chemin) }
            return .string(texte)
        case .object(let objet):
            return .object(objet.mapValues { remplacer($0, textes) })
        case .array(let liste):
            return .array(liste.map { remplacer($0, textes) })
        default:
            return valeur
        }
    }

    /// `change` posé sur `base`, objet par objet (entree_change des refus).
    static func fusionner(_ base: JSONValue, _ change: JSONValue) -> JSONValue {
        guard case .object(var objet) = base, case .object(let ajouts) = change else { return change }
        for (cle, valeur) in ajouts { objet[cle] = objet[cle].map { fusionner($0, valeur) } ?? valeur }
        return .object(objet)
    }

    /// Écrit le relevé et le carnet d'exemple (avec leurs `_note` : un lecteur les ignore) ; rend les
    /// textes à remplacer de l'entrée.
    func ecrireRegistreEtCarnet() throws -> [String: String] {
        let suivi = dossier.appendingPathComponent("suivi.json"), carnet = dossier.appendingPathComponent("carnet.json")
        try JSONCoding.line(try XCTUnwrap(exemple("registre")["fichier"])).write(to: suivi, atomically: true, encoding: .utf8)
        try JSONCoding.line(try XCTUnwrap(exemple("carnet")["fichier"])).write(to: carnet, atomically: true, encoding: .utf8)
        return ["<suivi.json>": suivi.path, "<carnet.json>": carnet.path]
    }

    /// Compare clé par clé (un message par écart), puis en entier.
    func memeObjet(_ obtenu: JSONValue, _ attendu: JSONValue, _ quoi: String, file: StaticString = #filePath, line: UInt = #line) {
        if let a = obtenu.object, let b = attendu.object {
            XCTAssertEqual(Set(a.keys), Set(b.keys), "\(quoi) : clés", file: file, line: line)
            for (cle, valeur) in b where a[cle] != valeur {
                if let sous = a[cle], sous.object != nil, valeur.object != nil {
                    memeObjet(sous, valeur, "\(quoi).\(cle)", file: file, line: line)
                } else if let liste = a[cle]?.array, let attendue = valeur.array, liste.count == attendue.count {
                    for (i, (x, y)) in zip(liste, attendue).enumerated() where x != y {
                        XCTFail("\(quoi).\(cle)[\(i + 1)] : \(JSONCoding.line(x)) au lieu de \(JSONCoding.line(y))", file: file, line: line)
                    }
                } else {
                    XCTFail("\(quoi).\(cle) : \(a[cle].map(JSONCoding.line) ?? "absent") au lieu de \(JSONCoding.line(valeur))",
                            file: file, line: line)
                }
            }
        } else {
            XCTAssertEqual(obtenu, attendu, quoi, file: file, line: line)
        }
    }

    /// Un PNG de 2 × la taille demandée, pas d'une seule couleur (des barres sur le fond).
    func verifierImage(_ chemin: String, largeur: Int, hauteur: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let donnees = try XCTUnwrap(FileManager.default.contents(atPath: chemin), "\(chemin) manque", file: file, line: line)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(donnees as CFData, nil), file: file, line: line)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png", chemin, file: file, line: line)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), file: file, line: line)
        XCTAssertEqual(image.width, 2 * largeur, chemin, file: file, line: line)
        XCTAssertEqual(image.height, 2 * hauteur, chemin, file: file, line: line)
        let pixels = try XCTUnwrap(Measurements.rgba(image), file: file, line: line)
        var couleurs = Set<UInt32>()
        for i in stride(from: 0, to: pixels.count, by: 4 * 97) {
            couleurs.insert(UInt32(pixels[i]) << 16 | UInt32(pixels[i + 1]) << 8 | UInt32(pixels[i + 2]))
            if couleurs.count > 2 { break }
        }
        XCTAssertGreaterThan(couleurs.count, 1, "\(chemin) : une seule couleur", file: file, line: line)
    }

    // MARK: Les règles reprises telles quelles

    /// Les huit codes, dans l'ordre de PriseDeVue, leur partage entre l'analyse et le carnet, et le
    /// nouveau code yeux_fermes tel que le contrat le décrit.
    func testCodes() throws {
        let codes = try XCTUnwrap(contrat()["regles"]?["codes"])
        XCTAssertEqual(codes["comptes"]?.array?.compactMap(\.string), Suivi.codes)
        XCTAssertEqual(codes["analyser"]?.array?.compactMap(\.string), Suivi.codesAnalyse)
        XCTAssertEqual(codes["carnet"]?.array?.compactMap(\.string), Suivi.codesCarnet)
        let nouveau = try objet(codes["nouveau_code"], "nouveau_code")
        let defaut = try XCTUnwrap(PriseDeVue.defaut(code: try XCTUnwrap(nouveau["code"]?.string)))
        XCTAssertEqual(defaut.domaine.code, nouveau["domaine"]?.string)
        XCTAssertEqual(defaut.libelle, nouveau["libelle"]?.string)
        XCTAssertEqual(defaut.conseil, nouveau["conseil"]?.string)
        XCTAssertEqual(defaut.mesure, nouveau["mesure"]?.bool)
        // Juste après mise_au_point.
        let tous = PriseDeVue.defauts.map(\.code)
        XCTAssertEqual(tous.firstIndex(of: "yeux_fermes"), try XCTUnwrap(tous.firstIndex(of: "mise_au_point")) + 1)
    }

    /// Les huit graphiques, leurs créneaux fixes (76), les tranches, les couleurs et les tailles.
    func testGraphiquesTranchesEtCouleurs() throws {
        let regles = try XCTUnwrap(contrat()["regles"])
        let liste = try objet(regles["graphiques"]?["liste"], "graphiques.liste")
        XCTAssertEqual(Set(liste.keys), Set(Suivi.graphiques))
        for (cle, attendu) in liste {
            let definition = try XCTUnwrap(Suivi.definitions[cle], cle)
            XCTAssertEqual(definition.orientation.rawValue, attendu["orientation"]?.string, cle)
            XCTAssertEqual(definition.maxBarres, attendu["max_barres"]?.int, cle)
            XCTAssertEqual(definition.unite, attendu["unite"]?.string, cle)
            XCTAssertEqual(definition.etale, attendu["etale"]?.bool, cle)
        }
        XCTAssertEqual(Suivi.graphiques.compactMap { Suivi.definitions[$0]?.maxBarres }.reduce(0, +), 87, "87 calques")
        for (nom, tranches) in [("focales", Suivi.tranchesFocales), ("iso", Suivi.tranchesISO)] {
            let attendues = try XCTUnwrap(regles["tranches"]?[nom]?["liste"]?.array, nom)
            XCTAssertEqual(attendues.count, tranches.count, nom)
            for (tranche, attendue) in zip(tranches, attendues) {
                XCTAssertEqual(tranche.jusqua, attendue["jusqua"]?.double, nom)
                XCTAssertEqual(tranche.libelle, attendue["libelle"]?.string, nom)
                XCTAssertEqual(tranche.detail, attendue["detail"]?.string, nom)
            }
        }
        XCTAssertEqual(Set(try objet(regles["couleurs"]?["cles"], "couleurs.cles").keys), Set(Suivi.clesCouleurs))
        for apparence in ["claire", "sombre"] {
            for (cle, hex) in try objet(regles["couleurs"]?[apparence], apparence) {
                XCTAssertNotNil(Suivi.couleurHex(try XCTUnwrap(hex.string)), "\(apparence).\(cle)")
            }
        }
        XCTAssertEqual(Suivi.tranchesISO[3].jusqua, Carnet.isoEleve, "« ≤ 1 600 » : la borne du bruit")
        XCTAssertEqual(Suivi.maxPhotosAnalyse, 20)
        XCTAssertEqual(ToolHandler.minimumCullSide, 900)
        XCTAssertEqual(try exemple("analyser")["sortie"]?["regles"]?.int, Suivi.reglesAnalyse)
    }

    // MARK: --graphiques

    func verifierGraphiques(_ nom: String) throws {
        let exemple = try exemple(nom)
        var textes = try ecrireRegistreEtCarnet()
        let sortie = dossier.appendingPathComponent("graphiques-\(nom)").path
        textes["<dossier>"] = sortie
        let entree = Self.remplacer(try XCTUnwrap(exemple["entree"]), textes)
        let reponse = Suivi.graphiques(JSONCoding.line(entree), dossier: sortie)
        XCTAssertEqual(reponse.code, 0, JSONCoding.line(reponse.ligne))
        let attendue = Self.remplacer(Self.sansNotes(try XCTUnwrap(exemple["sortie"])), textes)
        let obtenus = try objet(reponse.ligne["graphiques"], "graphiques de la réponse")
        XCTAssertEqual(Set(obtenus.keys), Set(Suivi.graphiques), "les huit graphiques, même pour un exemple partiel")
        if exemple["partiel"]?.bool == true {
            for (cle, valeur) in try objet(attendue, "sortie") where cle != "graphiques" {
                memeObjet(reponse.ligne[cle] ?? .null, valeur, "\(nom).\(cle)")
            }
            for (cle, valeur) in try objet(attendue["graphiques"], "sortie.graphiques") {
                memeObjet(obtenus[cle] ?? .null, valeur, "\(nom).graphiques.\(cle)")
            }
        } else {
            memeObjet(reponse.ligne, attendue, nom)
            XCTAssertEqual(reponse.ligne, attendue, nom)
        }
        // Les huit PNG, en 2x, chacun dans le fichier que dit la réponse.
        for (cle, graphique) in obtenus {
            let chemin = try XCTUnwrap(graphique["fichier"]?.string)
            XCTAssertEqual(chemin, "\(sortie)/\(cle).png")
            try verifierImage(chemin, largeur: try XCTUnwrap(graphique["largeur"]?.int), hauteur: try XCTUnwrap(graphique["hauteur"]?.int))
        }
    }

    func testGraphiquesUnAn() throws { try verifierGraphiques("graphiques_un_an") }
    func testGraphiquesTreizeMois() throws { try verifierGraphiques("graphiques_treize_mois") }
    func testGraphiquesTroisMois() throws { try verifierGraphiques("graphiques_trois_mois") }
    func testGraphiquesDepuisLeDebut() throws { try verifierGraphiques("graphiques_depuis_le_debut") }
    func testGraphiquesTrimestres() throws { try verifierGraphiques("graphiques_trimestres") }

    /// Les refus de tout l'appel : une seule ligne, code 1, aucun PNG écrit.
    func testRefusDeGraphiques() throws {
        let textes = try ecrireRegistreEtCarnet()
        let base = Self.remplacer(try XCTUnwrap(exemple("graphiques_un_an")["entree"]), textes)
        let refus = try exemple("graphiques_refus")
        for (nom, cas) in refus where nom != "_note" && cas["entree_change"] != nil {
            let sortie = dossier.appendingPathComponent("refus-\(nom)").path
            let reponse = Suivi.graphiques(JSONCoding.line(Self.fusionner(base, try XCTUnwrap(cas["entree_change"]))), dossier: sortie)
            XCTAssertEqual(reponse.code, 1, nom)
            XCTAssertEqual(reponse.ligne, Self.sansNotes(try XCTUnwrap(cas["sortie"])), nom)
            XCTAssertFalse(FileManager.default.fileExists(atPath: sortie), "\(nom) : rien n'est écrit")
        }
        // suivi.json tronqué, puis d'un format 2.
        let attendue = Self.sansNotes(try XCTUnwrap(refus["suivi_illisible"]?["sortie"]))
        let suivi = try XCTUnwrap(textes["<suivi.json>"])
        let complet = try String(contentsOfFile: suivi, encoding: .utf8)
        for (cas, contenu) in [("tronqué", String(complet.prefix(300))),
                               ("format 2", complet.replacingOccurrences(of: "\"format\":1", with: "\"format\":2"))] {
            XCTAssertNotEqual(contenu, complet, cas)
            try contenu.write(toFile: suivi, atomically: true, encoding: .utf8)
            let sortie = dossier.appendingPathComponent("illisible").path
            let reponse = Suivi.graphiques(JSONCoding.line(base), dossier: sortie)
            XCTAssertEqual(reponse.code, 1, cas)
            XCTAssertEqual(reponse.ligne, attendue, cas)
            XCTAssertFalse(FileManager.default.fileExists(atPath: sortie), "\(cas) : rien n'est dessiné")
        }
    }

    // MARK: --analyser

    /// Une vignette fabriquée : un damier net (des carrés de 6 px, deux gris) sous `blanc` × la
    /// hauteur de blanc pur depuis le haut ; `sombre` assombrit le damier.
    static func vignette(largeur: Int, hauteur: Int, blanc: Double = 0, sombre: Bool = false) -> Data {
        let limite = Int(Double(hauteur) * blanc)
        let (a, b): (UInt8, UInt8) = sombre ? (12, 70) : (70, 190)
        return TestSupport.jpegPixels(width: largeur, height: hauteur, quality: 0.95) { x, y in
            if y < limite { return (255, 255, 255) }
            let v = ((x / 6) + (y / 6)) % 2 == 0 ? a : b
            return (v, v, v)
        }
    }

    /// Le lot de l'exemple, sur des vignettes fabriquées : la forme de la réponse, les codes cherchés
    /// selon l'ISO, retouchee et la taille, et les raisons telles que le contrat les écrit.
    func testAnalyserLeLotDeLExemple() throws {
        let exemple = try exemple("analyser")
        let lot = dossier.appendingPathComponent("lot")
        try FileManager.default.createDirectory(at: lot, withIntermediateDirectories: true)
        let vignettes: [Int: Data] = [
            4302: Self.vignette(largeur: 1200, hauteur: 800),
            4303: Self.vignette(largeur: 1200, hauteur: 800, sombre: true),
            4304: Self.vignette(largeur: 1024, hauteur: 683, blanc: 0.6),
            4306: Self.vignette(largeur: 1200, hauteur: 800),
            4307: Self.vignette(largeur: 256, hauteur: 171),
        ]
        for (id, donnees) in vignettes { try donnees.write(to: lot.appendingPathComponent("\(id).jpg")) }
        let textes = ["<lot>": lot.path]
        let entree = Self.remplacer(try XCTUnwrap(exemple["entree"]), textes)
        let reponse = Suivi.analyser(JSONCoding.line(entree))
        XCTAssertEqual(reponse.code, 0, JSONCoding.line(reponse.ligne))
        XCTAssertEqual(reponse.ligne["ok"], true)
        XCTAssertEqual(reponse.ligne["regles"]?.int, 1)
        XCTAssertEqual(reponse.ligne["regles_genre"]?.int, Genre.regles)
        XCTAssertEqual(reponse.ligne["regles_genre"], try XCTUnwrap(exemple["sortie"]?["regles_genre"]), "les règles du genre du contrat")
        XCTAssertEqual(Set(reponse.ligne.object?.keys.map { $0 } ?? []), ["ok", "regles", "regles_genre", "photos"])
        let photos = try XCTUnwrap(reponse.ligne["photos"]?.array)
        let attendues = try XCTUnwrap(Self.remplacer(try XCTUnwrap(exemple["sortie"]), textes)["photos"]?.array)
        XCTAssertEqual(photos.compactMap { $0["id"]?.int }, attendues.compactMap { $0["id"]?.int }, "une par photo, dans le même ordre")
        let clesMesures = Set(try objet(try contrat()["regles"]?["analyser"]?["mesures"], "analyser.mesures").keys.filter { $0 != "_note" })
        let ordre = Suivi.codes
        for (photo, attendue) in zip(photos, attendues) {
            let id = try XCTUnwrap(photo["id"]?.int)
            if attendue["raison"] != nil {
                XCTAssertEqual(photo, attendue, "\(id) : la raison et son texte, tels quels")
                continue
            }
            XCTAssertEqual(Set(photo.object?.keys.map { $0 } ?? []), ["id", "cherches", "defauts", "genre", "mesures"], "\(id)")
            // Le genre : un code de la liste du contrat (un damier n'a ni visage ni scène : sa valeur
            // dépend de Vision, seule sa forme se vérifie).
            XCTAssertTrue(Genre.codes.contains(try XCTUnwrap(photo["genre"]?.string)), "\(id) : un genre de la liste")
            XCTAssertEqual(Set(attendue.object?.keys.map { $0 } ?? []), ["id", "cherches", "defauts", "genre", "mesures"], "\(id) : le contrat")
            let cherches = try XCTUnwrap(photo["cherches"]?.array).compactMap(\.string)
            let defauts = try XCTUnwrap(photo["defauts"]?.array).compactMap(\.string)
            XCTAssertTrue(Set(defauts).isSubset(of: Set(cherches)), "\(id) : un défaut trouvé est cherché")
            XCTAssertEqual(cherches, ordre.filter(cherches.contains), "\(id) : dans l'ordre des codes")
            XCTAssertEqual(defauts, ordre.filter(defauts.contains), "\(id)")
            let mesures = try XCTUnwrap(photo["mesures"]?.object, "\(id)")
            XCTAssertTrue(Set(mesures.keys).isSubset(of: clesMesures), "\(id) : \(mesures.keys.sorted())")
            for cle in ["cote", "mediane_l", "p95_l", "blanc_pur", "blanc_pur_haut", "nettete", "bruit", "visages"] {
                XCTAssertNotNil(mesures[cle]?.double, "\(id) : \(cle)")
            }
            // Pas de visage sur un damier : les yeux ne se cherchent pas (codesTrouves les essaie, SuiviTests).
            XCTAssertFalse(cherches.contains("yeux_fermes"), "\(id)")
            switch id {
            case 4302:
                XCTAssertEqual(cherches, ["sous_exposition", "surexposition", "ciel_brule", "flou"], "ISO 250 : pas de bruit")
                XCTAssertEqual(mesures["cote"]?.int, 1200)
            case 4303:
                XCTAssertEqual(cherches, ["sous_exposition", "surexposition", "ciel_brule", "bruit", "flou"], "ISO 5 000 : le bruit")
            case 4304:
                XCTAssertEqual(cherches, ["sous_exposition", "surexposition", "ciel_brule", "flou"], "ISO inconnu : pas de bruit")
                XCTAssertEqual(photo["genre"], "macro", "l'objectif macro du contrat, sans personne")
                XCTAssertTrue(defauts.contains("surexposition"), "60 % de blanc pur : brûlée")
                XCTAssertTrue(defauts.contains("ciel_brule"), "le tiers haut blanc")
                XCTAssertEqual(mesures["cote"]?.int, 1024)
            case 4306:
                XCTAssertEqual(cherches, ["flou"], "retouchée par Claude : le flou et les yeux seulement")
            default:
                XCTFail("photo inattendue \(id)")
            }
        }
    }

    /// Les refus de tout l'appel : une seule ligne, code 1, aucune photo mesurée.
    func testRefusDAnalyser() throws {
        let refus = try exemple("analyser_refus")
        var mesurees = 0
        let compter: (Suivi.AAnalyser) -> JSONValue = { _ in mesurees += 1; return .null }
        let trop = JSONValue.object(["photos": .array((1...25).map { ["id": .number(Double($0)), "vignette": "/nulle/part.jpg", "cache": true] })])
        var reponse = Suivi.analyser(JSONCoding.line(trop), mesurer: compter)
        XCTAssertEqual(reponse.code, 1)
        XCTAssertEqual(reponse.ligne, refus["trop_de_photos"]?["sortie"])
        reponse = Suivi.analyser(JSONCoding.line(try XCTUnwrap(refus["arguments"]?["entree"])), mesurer: compter)
        XCTAssertEqual(reponse.code, 1)
        XCTAssertEqual(reponse.ligne, refus["arguments"]?["sortie"])
        XCTAssertEqual(mesurees, 0)
    }
}
