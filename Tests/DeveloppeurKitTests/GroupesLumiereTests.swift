import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// 1.4, « Une sortie entière » : les groupes de lumière (`GroupesLumiere`, `match_series` avec
/// `groups`), le témoin du teint (`Teint`) et le tri d'une sortie par tranches (`cull_photos` avec
/// `offset`).
final class GroupesLumiereTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    private func call(_ name: String, _ arguments: [String: JSONValue]) -> ToolResult {
        tools.call(name: name, arguments: arguments)
    }

    static let depart = Date(timeIntervalSince1970: 1_750_000_000)

    /// Une photo à `minutes` du départ, à f/`ouverture`, `vitesse` s et ISO `iso`.
    static func prise(_ id: Int, minutes: Double, ouverture: Double = 8, vitesse: Double = 1.0 / 250, iso: Double = 200,
                      compensation: Double? = nil, flash: Bool? = false) -> GroupesLumiere.Prise {
        GroupesLumiere.Prise(id: id, fichier: "DSCF\(id).RAF", date: depart.addingTimeInterval(minutes * 60), ouverture: ouverture,
                             vitesse: vitesse, iso: iso, compensation: compensation, flash: flash)
    }

    static func ids(_ groupes: [GroupesLumiere.Groupe], _ prises: [GroupesLumiere.Prise]) -> [[Int]] {
        groupes.map { $0.membres.map { prises[$0].id } }
    }

    // MARK: La lumière de la scène

    func testLaLumiereDeLaSceneSeCalculeDeLExposition() throws {
        // f/8, 1/250 s, ISO 200 : log2(64 × 250) − 1 = 12,97.
        let prise = Self.prise(1, minutes: 0)
        XCTAssertEqual(try XCTUnwrap(prise.lumiere), log2(64.0 * 250) - 1, accuracy: 1e-9)
        // Une photo éclaircie d'une IL : la scène n'a pas changé.
        let eclaircie = Self.prise(2, minutes: 0, vitesse: 1.0 / 125, compensation: 1)
        XCTAssertEqual(try XCTUnwrap(eclaircie.lumiere), try XCTUnwrap(prise.lumiere), accuracy: 1e-9)
        XCTAssertNil(GroupesLumiere.Prise(id: 3, fichier: "x", ouverture: 8, vitesse: nil, iso: 200).lumiere)
        XCTAssertNil(GroupesLumiere.Prise(id: 3, fichier: "x", ouverture: 0, vitesse: 0.01, iso: 200).lumiere)
        XCTAssertEqual(GroupesLumiere.nomLumiere(15), "plein jour")
        XCTAssertEqual(GroupesLumiere.nomLumiere(12), "ombre ou ciel couvert")
        XCTAssertEqual(GroupesLumiere.nomLumiere(6), "intérieur")
        XCTAssertEqual(GroupesLumiere.nomLumiere(2), "intérieur sombre, ou nuit")
    }

    // MARK: Les coupures

    func testLeMuseeLaPlageEtLeSouper() {
        // Le musée (IL 7 environ), la plage en plein soleil (IL 15) une heure plus tard, le souper au
        // flash le soir.
        let prises = [
            Self.prise(1, minutes: 0, ouverture: 2.8, vitesse: 1.0 / 60, iso: 3200),
            Self.prise(2, minutes: 2, ouverture: 2.8, vitesse: 1.0 / 50, iso: 3200),
            Self.prise(3, minutes: 5, ouverture: 2.8, vitesse: 1.0 / 60, iso: 2500),
            Self.prise(4, minutes: 70, ouverture: 11, vitesse: 1.0 / 500, iso: 160),
            Self.prise(5, minutes: 71, ouverture: 11, vitesse: 1.0 / 640, iso: 160),
            Self.prise(6, minutes: 400, ouverture: 4, vitesse: 1.0 / 125, iso: 800, flash: true),
            Self.prise(7, minutes: 402, ouverture: 4, vitesse: 1.0 / 125, iso: 800, flash: true),
        ]
        let groupes = GroupesLumiere.former(prises) { _, _ in nil }
        XCTAssertEqual(Self.ids(groupes, prises), [[1, 2, 3], [4, 5], [6, 7]])
        XCTAssertEqual(groupes[0].coupure, .debut)
        guard case .lumiere(let ecart) = groupes[1].coupure else { return XCTFail("\(groupes[1].coupure)") }
        XCTAssertGreaterThan(ecart, 6, "la plage est bien plus claire que le musée")
        XCTAssertEqual(groupes[2].coupure, .flash(allume: true))
        XCTAssertEqual(groupes[2].coupure.texte, "le flash éclaire à partir d'ici")
    }

    func testUnePauseCoupeSaufAuMemeLieuDansLHeure() {
        let prises = [Self.prise(1, minutes: 0), Self.prise(2, minutes: 1), Self.prise(3, minutes: 40), Self.prise(4, minutes: 41),
                      Self.prise(5, minutes: 150)]
        // Sans empreintes : la pause de 39 min coupe.
        let sans = GroupesLumiere.former(prises) { _, _ in nil }
        XCTAssertEqual(Self.ids(sans, prises), [[1, 2], [3, 4], [5]])
        XCTAssertEqual(sans[1].coupure, .pause(39 * 60))
        XCTAssertEqual(sans[1].coupure.texte, "pause de 39 min")
        // La photo 3 ressemble à la 2 : le même lieu après le repas, le même groupe. Après 1 h 49,
        // même au même lieu, la lumière a pu changer : la 5 commence un groupe.
        let lieu = GroupesLumiere.former(prises) { _, _ in 0.3 }
        XCTAssertEqual(Self.ids(lieu, prises), [[1, 2, 3, 4], [5]])
        XCTAssertEqual(lieu[1].coupure.texte, "pause de 1 h 49")
        // Une ressemblance trop faible (deux photos différentes) ne rapproche pas.
        XCTAssertEqual(Self.ids(GroupesLumiere.former(prises) { _, _ in 0.9 }, prises), [[1, 2], [3, 4], [5]])
    }

    func testUneLumiereQuiBaissePeuAPeuResteUnGroupe() {
        // Un coucher de soleil : une demi-IL de moins toutes les 3 minutes, sur 30 minutes (5 IL en
        // tout), sans pause : la médiane des dernières photos suit.
        let prises = (0..<11).map { i in Self.prise(i + 1, minutes: Double(i) * 3, vitesse: 1.0 / 250 * pow(2, Double(i) / 2)) }
        XCTAssertEqual(GroupesLumiere.former(prises) { _, _ in nil }.count, 1)
        // L'ombre d'un arbre, 3 IL plus sombre, d'un coup : une autre lumière ; puis retour au soleil.
        let ombre = [Self.prise(1, minutes: 0), Self.prise(2, minutes: 1), Self.prise(3, minutes: 2, vitesse: 1.0 / 30),
                     Self.prise(4, minutes: 3, vitesse: 1.0 / 30), Self.prise(5, minutes: 4)]
        XCTAssertEqual(Self.ids(GroupesLumiere.former(ombre) { _, _ in nil }, ombre), [[1, 2], [3, 4], [5]])
        // Une IL et demie d'écart (un contre-jour exposé autrement) ne coupe pas.
        let contre = [Self.prise(1, minutes: 0), Self.prise(2, minutes: 1, vitesse: 1.0 / 90), Self.prise(3, minutes: 2)]
        XCTAssertEqual(GroupesLumiere.former(contre) { _, _ in nil }.count, 1)
    }

    func testAuFlashLaSceneNeSeComparePasEtLeFlashInconnuNeCoupePas() {
        // Au flash, une vitesse de synchro et une ouverture qui changent ne disent rien de la scène.
        let flash = [Self.prise(1, minutes: 0, ouverture: 4, vitesse: 1.0 / 250, iso: 200, flash: true),
                     Self.prise(2, minutes: 1, ouverture: 2, vitesse: 1.0 / 30, iso: 3200, flash: true)]
        XCTAssertEqual(GroupesLumiere.former(flash) { _, _ in nil }.count, 1)
        // Un flash inconnu (nil) ne coupe pas.
        let inconnu = [Self.prise(1, minutes: 0, flash: nil), Self.prise(2, minutes: 1, flash: false), Self.prise(3, minutes: 2, flash: nil)]
        XCTAssertEqual(GroupesLumiere.former(inconnu) { _, _ in nil }.count, 1)
        // Ni ne cache un changement : deux boîtiers mêlés, l'un qui ne dit pas son flash.
        let meles = [Self.prise(1, minutes: 0, flash: false), Self.prise(2, minutes: 1, flash: nil),
                     Self.prise(3, minutes: 2, flash: true), Self.prise(4, minutes: 3, flash: true)]
        let groupes = GroupesLumiere.former(meles) { _, _ in nil }
        XCTAssertEqual(Self.ids(groupes, meles), [[1, 2], [3, 4]])
        XCTAssertEqual(groupes[1].coupure, .flash(allume: true))
        XCTAssertEqual(GroupesLumiere.Coupure.flash(allume: false).texte, "plus de flash à partir d'ici")
    }

    func testLesPhotosSansDateViennentApresEtDeuxBoitiersRestentEnsemble() {
        var prises = [Self.prise(3, minutes: 2), Self.prise(1, minutes: 0), Self.prise(2, minutes: 1)]
        prises.append(GroupesLumiere.Prise(id: 9, fichier: "scan.tif"))
        prises.append(GroupesLumiere.Prise(id: 8, fichier: "scan2.tif"))
        let groupes = GroupesLumiere.former(prises) { _, _ in nil }
        XCTAssertEqual(Self.ids(groupes, prises), [[1, 2, 3], [9, 8]], "dans l'ordre de prise de vue, puis l'ordre donné")
        XCTAssertEqual(groupes[1].coupure, .sansDate)
        XCTAssertEqual(groupes[1].coupure.texte, "photos sans date de prise de vue")
        XCTAssertEqual(GroupesLumiere.duree(3 * 3600), "3 h")
        XCTAssertEqual(GroupesLumiere.duree(65 * 60), "1 h 05")
    }

    // MARK: La référence proposée

    static func triee(_ id: Int, nettete: Double, visage: Bool = false, floue: Bool = false) -> PhotoTriee {
        var photo = PhotoTriee(id: id, fichier: "DSCF\(id).RAF")
        photo.detail = DetailMeasurements(zones: [floue ? 5 : nettete], noise: 0.3, shadowNoise: nil, side: 1024)
        photo.vision = VisionReport(faces: visage ? [VisionReport.Face(box: CGRect(x: 0.4, y: 0.2, width: 0.12, height: 0.16), pupils: [],
                                                                     eyeWidth: nil, quality: nil, eyeOpenness: nil)] : [],
                                    aesthetics: 0, utility: false, salientArea: nil)
        return photo
    }

    func testLaReferenceProposee() throws {
        let photos = [Self.triee(1, nettete: 50), Self.triee(2, nettete: 30, visage: true), Self.triee(3, nettete: 60, floue: true),
                      Self.triee(4, nettete: 20)]
        // Un visage d'abord : le témoin du teint.
        let visage = try XCTUnwrap(GroupesLumiere.reference([0, 1, 2, 3], photos: photos, retouchees: []))
        XCTAssertEqual(photos[visage.index].id, 2)
        XCTAssertTrue(visage.pourquoi.contains("visage"), visage.pourquoi)
        // Sans visage : la mieux classée, jamais la floue.
        let sans = try XCTUnwrap(GroupesLumiere.reference([0, 2, 3], photos: photos, retouchees: []))
        XCTAssertEqual(photos[sans.index].id, 1)
        XCTAssertTrue(sans.pourquoi.contains("à retoucher d'abord"))
        // Une photo déjà retouchée par Claude l'emporte : elle a déjà le rendu du groupe.
        let deja = try XCTUnwrap(GroupesLumiere.reference([0, 1, 2, 3], photos: photos, retouchees: [4]))
        XCTAssertEqual(photos[deja.index].id, 4)
        XCTAssertTrue(deja.pourquoi.hasPrefix("déjà retouchée par Claude"))
        // Toutes floues : la meilleure quand même, dite à confirmer.
        let floues = try XCTUnwrap(GroupesLumiere.reference([2], photos: photos, retouchees: []))
        XCTAssertTrue(floues.pourquoi.contains("à confirmer à l'œil"))
        XCTAssertNil(GroupesLumiere.reference([], photos: photos, retouchees: []))
    }

    // MARK: Le témoin du teint

    /// Une image grise de 1 000 × 800 avec, dans `visage` (fractions), la peau d'une couleur donnée.
    static func imageAvecPeau(_ visage: CGRect, couleur: (UInt8, UInt8, UInt8)) -> CGImage {
        TestSupport.imagePixels(width: 1000, height: 800) { x, y in
            let fx = Double(x) / 1000, fy = Double(y) / 800
            return visage.contains(CGPoint(x: fx, y: fy)) ? couleur : (128, 128, 128)
        }
    }

    func testLaPeauSeLitAuMilieuDuVisageAPleineResolution() throws {
        let visage = CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.15)
        let rosee = Self.imageAvecPeau(visage, couleur: (226, 170, 150))
        let peau = try XCTUnwrap(Teint.mesurer(rosee, visages: [visage]))
        let attendu = Measurements.lab(226, 170, 150)
        XCTAssertEqual(peau.a, attendu.a, accuracy: 0.6)
        XCTAssertEqual(peau.b, attendu.b, accuracy: 0.6)
        XCTAssertEqual(peau.l, attendu.l, accuracy: 0.6)
        XCTAssertGreaterThanOrEqual(peau.pixels, Teint.pixelsMin)
        XCTAssertGreaterThan(peau.teinte, 20)
        XCTAssertLessThan(peau.teinte, 80)
        // Le plus grand visage compte, un trop petit (sous 4 % de largeur) se tait.
        XCTAssertNil(Teint.mesurer(rosee, visages: [CGRect(x: 0.4, y: 0.3, width: 0.03, height: 0.04)]))
        XCTAssertNil(Teint.mesurer(rosee, visages: []))
        // Un gris (pas de chroma) n'est pas une peau.
        XCTAssertNil(Teint.mesurer(Self.imageAvecPeau(visage, couleur: (128, 128, 128)), visages: [visage]))
        // Une image sans visage pour Vision : rien.
        XCTAssertNil(Teint.lire(rosee))
    }

    func testLEcartEtLAlerteDuTeint() throws {
        let reference = Teint.Mesure(l: 70, a: 14, b: 20, pixels: 300)
        let proche = Teint.Mesure(l: 68, a: 15, b: 21, pixels: 300)
        let loin = Teint.Mesure(l: 68, a: 14, b: 28, pixels: 300)
        XCTAssertEqual(Teint.ecart(proche, reference), hypot(1, 1), accuracy: 1e-9)
        XCTAssertFalse(Teint.alerte(avant: 1.4, apres: 4.9), "sous l'écart visible")
        XCTAssertFalse(Teint.alerte(avant: 6, apres: 7), "déjà loin avant : l'harmonisation ne l'a pas éloignée de 2")
        XCTAssertTrue(Teint.alerte(avant: 1.4, apres: 8))
        let temoin = try XCTUnwrap(Teint.json(reference: reference, avant: proche, apres: loin))
        XCTAssertEqual(temoin["ecart_avant"]?.double ?? 0, 1.4, accuracy: 0.05)
        XCTAssertEqual(temoin["ecart_apres"]?.double ?? 0, 8, accuracy: 0.05)
        XCTAssertTrue(temoin["a_verifier"]?.string?.contains("view_photo avec region sur le visage") == true)
        XCTAssertNil(Teint.json(reference: reference, avant: proche, apres: proche)?["a_verifier"])
        XCTAssertNil(Teint.json(reference: nil, avant: proche, apres: nil), "sans peau sur la référence, pas de témoin")
        XCTAssertEqual(Teint.json(reference: reference, avant: nil, apres: nil)?["lu"]?.bool, false)
        XCTAssertEqual(Teint.jsonReference(nil)["lu"]?.bool, false)
        XCTAssertEqual(Teint.jsonReference(reference)["teinte_deg"]?.int, Int((atan2(20.0, 14.0) * 180 / .pi).rounded()))
    }

    func testSansVisageSurLaReferenceAucunTemoin() throws {
        // Un aperçu neuf à chaque commande : le connecteur efface celui qu'il a lu.
        let gris = TestSupport.jpeg(red: 128, green: 128, blue: 128)
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            fake?.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(gris)), "photo": ["fichier": "P.RAF"],
                                       "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 0]]
        }
        let resultat = call("match_series", ["reference_id": 1, "photo_ids": [2, 3]])
        XCTAssertFalse(resultat.isError, resultat.text)
        let plan = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(plan["reference"]?["teint"]?["lu"]?.bool, false)
        XCTAssertTrue(plan["reference"]?["teint"]?["pourquoi"]?.string?.contains("pas de témoin du teint") == true)
        for ligne in plan["photos"]?.array ?? [] { XCTAssertNil(ligne["teint"], "pas de Vision de plus sans visage sur la référence") }
        XCTAssertNil(plan["a_verifier"])
        XCTAssertFalse(fake.commands.contains("appliquer"))
    }

    // MARK: match_series avec groups

    /// Faux module : la commande vignettes décrit chaque photo comme le module 1.4 (date, sensibilité,
    /// prise de vue en nombres), avec une vignette nette.
    func preparerSortie(_ descriptions: [Int: [String: JSONValue]]) {
        let nette = TriTests.damier()
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["photos": .array(ids.map { id in
                    var item: [String: JSONValue] = ["id": .number(Double(id)), "fichier": .string("DSCF\(id).RAF"), "note": 0, "drapeau": "aucun",
                                                     "vignette": .string(TestSupport.previewFile(nette))]
                    for (cle, valeur) in descriptions[id] ?? [:] { item[cle] = valeur }
                    return .object(item)
                })]
            }
        }
    }

    static func description(minutes: Int, vitesse: Double, iso: Double = 200, flash: Bool = false, retouchee: Bool = false) -> [String: JSONValue] {
        let date = Date(timeIntervalSince1970: 1_750_000_000 + Double(minutes) * 60)
        let lecteur = DateFormatter()
        lecteur.locale = Locale(identifier: "en_US_POSIX")
        lecteur.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return ["date": .string(lecteur.string(from: date)), "sensibilite": .number(iso), "retouchee_par_claude": .bool(retouchee),
                "prise_de_vue": ["ouverture": 8, "vitesse": .number(vitesse), "flash": .bool(flash)],
                // Une géométrie et un original Fujifilm : jamais ouverts pour les groupes.
                "marque": "FUJIFILM", "chemin_original": "/nulle/part/DSCF.RAF",
                "geometrie": ["largeur": 6240, "hauteur": 4160, "orientation": "AB"]]
    }

    func testLesGroupesDUneSortieSansRienChanger() throws {
        preparerSortie([
            1: Self.description(minutes: 0, vitesse: 1.0 / 250),
            2: Self.description(minutes: 1, vitesse: 1.0 / 250, retouchee: true),
            3: Self.description(minutes: 2, vitesse: 1.0 / 320),
            4: Self.description(minutes: 3, vitesse: 1.0 / 8, iso: 3200),
            5: Self.description(minutes: 4, vitesse: 1.0 / 10, iso: 3200),
            6: Self.description(minutes: 300, vitesse: 1.0 / 125, flash: true),
        ])
        let result = call("match_series", ["groups": true, "photo_ids": [1, 2, 3, 4, 5, 6]])
        XCTAssertFalse(result.isError, result.text)
        let plan = try JSONCoding.parse(result.text)
        XCTAssertEqual(plan["photos_analysees"]?.int, 6)
        let groupes = try XCTUnwrap(plan["groupes"]?.array)
        XCTAssertEqual(groupes.map { $0["photos"]?.array?.compactMap(\.int) ?? [] }, [[1, 2, 3], [4, 5]])
        XCTAssertEqual(groupes[0]["reference_proposee"]?["id"]?.int, 2, "déjà retouchée par Claude")
        XCTAssertEqual(groupes[0]["lumiere"]?.string?.hasPrefix("ombre ou ciel couvert"), true, groupes[0]["lumiere"]?.string ?? "")
        XCTAssertEqual(groupes[1]["iso"]?.string, "ISO 3200")
        XCTAssertTrue(groupes[1]["commence"]?.string?.hasPrefix("lumière de la scène plus faible") == true)
        XCTAssertNotNil(groupes[1]["reference_proposee"]?["id"]?.int)
        XCTAssertEqual(plan["photos_seules"]?.array?.first?["id"]?.int, 6)
        XCTAssertEqual(plan["photos_seules"]?.array?.first?["pourquoi"]?.string,
                       "seule sous sa lumière (le flash éclaire à partir d'ici ; dernière photo de la série) : à retoucher seule, rien à harmoniser")
        XCTAssertNotNil(plan["rien_n_est_applique"])
        XCTAssertTrue(plan["suite"]?.string?.contains("match_series avec reference_id") == true)
        XCTAssertEqual(fake.commands.filter { $0 != "vignettes" }, [], "rien d'autre que les vignettes : ni écriture ni aperçu")
    }

    func testLesGroupesRefusentUneReferenceEtVeulentUneSortie() {
        let avec = call("match_series", ["groups": true, "reference_id": 1, "photo_ids": [2, 3]])
        XCTAssertTrue(avec.isError)
        XCTAssertTrue(avec.text.contains("sans reference_id"), avec.text)
        let sans = call("match_series", ["groups": true])
        XCTAssertTrue(sans.isError)
        XCTAssertTrue(sans.text.contains("Photos de la sortie"), sans.text)
        let aucune = call("match_series", ["photo_ids": [2, 3]])
        XCTAssertTrue(aucune.isError)
        XCTAssertTrue(aucune.text.contains("groups = true"), aucune.text)
        XCTAssertTrue(fake.commands.isEmpty)
    }

    func testUnGrosGroupeSHarmoniseParLots() throws {
        var descriptions: [Int: [String: JSONValue]] = [:]
        for id in 1...62 { descriptions[id] = Self.description(minutes: id / 10, vitesse: 1.0 / 250) }
        preparerSortie(descriptions)
        let plan = try JSONCoding.parse(call("match_series", ["groups": true, "photo_ids": .array((1...62).map { .number(Double($0)) })]).text)
        let groupe = try XCTUnwrap(plan["groupes"]?.array?.first)
        XCTAssertEqual(groupe["nombre"]?.int, 62)
        XCTAssertTrue(groupe["lots"]?.string?.hasPrefix("61 photos à harmoniser : 2 appels de match_series") == true, groupe["lots"]?.string ?? "")
    }

    func testLaDescriptionDeMatchSeriesDitLesGroupes() throws {
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "match_series" })
        XCTAssertTrue(outil["description"]?.string?.contains("groups = true") == true)
        XCTAssertNotNil(outil["inputSchema"]?["properties"]?["groups"])
        XCTAssertEqual(outil["inputSchema"]?["required"]?.array ?? [], [], "reference_id n'est plus requis : groups s'en passe")
        XCTAssertTrue(Prompts.harmoniserSerie.render([:]).contains("match_series avec groups = true"))
    }

    func testLaRecetteGroupeLesPhotosDEssaiSansRienEcrire() throws {
        preparerSortie([5: Self.description(minutes: 0, vitesse: 1.0 / 250), 6: Self.description(minutes: 1, vitesse: 1.0 / 250, flash: true)])
        let recette = Recette(lightroom: fake)
        try recette.sequenceLumiere([5, 6, 5])
        XCTAssertTrue(recette.reussie, recette.etapes.map(\.detail).joined(separator: " | "))
        let etape = try XCTUnwrap(recette.etapes.last)
        XCTAssertEqual(etape.nom, "groupes de lumière (match_series, groups), rien d'écrit")
        XCTAssertEqual(etape.photo, "sortie 5, 6", "chaque photo une fois")
        XCTAssertTrue(etape.detail.contains("0 groupe(s), 2 photo(s) seule(s)"), etape.detail)
        XCTAssertTrue(etape.detail.contains("prise de vue lue sur 2 photo(s) sur 2, flash : non, oui"), etape.detail)
        XCTAssertFalse(fake.commands.contains("appliquer"))
        // Une seule photo : pas d'étape.
        let seule = Recette(lightroom: fake)
        try seule.sequenceLumiere([5])
        XCTAssertTrue(seule.etapes.isEmpty)
    }

    // MARK: Le tri d'une sortie entière

    func testLeTriDUneSortieParTranches() throws {
        XCTAssertEqual(ToolHandler.maxCulledPhotos, 1_000)
        XCTAssertEqual(ToolHandler.maxCulledDetails, 500)
        XCTAssertEqual(ToolHandler.maxPhotosSortie, 2_000)
        let nette = TriTests.damier()
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "selection" {
                let decalage = params["decalage"]?.int ?? 0
                fake.replies["selection"] = ["total": 2_003, "decalage": .number(Double(decalage)),
                                             "photos": .array((0..<3).map { ["id": .number(Double(decalage + $0 + 1)), "fichier": "P"] })]
            } else if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P", "note": 0, "drapeau": "aucun",
                                                                          "vignette": .string(TestSupport.previewFile(nette))] })]
            }
        }
        // Une sélection plus longue que la borne n'est plus refusée : la tranche, puis la suite dite.
        let premiere = try JSONCoding.parse(call("cull_photos", ["selection": true]).text)
        let selection = try XCTUnwrap(fake.calls.first { $0.command == "selection" })
        XCTAssertEqual(selection.params["limite"]?.int, 1_000)
        XCTAssertEqual(selection.params["decalage"]?.int, 0)
        XCTAssertEqual(premiere["photos_analysees"]?.int, 3)
        XCTAssertTrue(premiere["photos_non_triees"]?.string?.contains("offset = 3") == true, premiere["photos_non_triees"]?.string ?? "")
        // La tranche suivante : le module décrit à partir du décalage.
        let suite = try JSONCoding.parse(call("cull_photos", ["selection": true, "offset": 2_000]).text)
        XCTAssertEqual(fake.calls.last { $0.command == "selection" }?.params["decalage"]?.int, 2_000)
        XCTAssertEqual(fake.calls.last { $0.command == "vignettes" }?.params["photos"]?.array?.compactMap(\.int), [2001, 2002, 2003])
        XCTAssertNil(suite["photos_non_triees"], "la dernière tranche : rien de plus")
    }

    func testUnModuleDAvantSeRedemandeAssezLoin() throws {
        // Un module d'avant décrit la sélection depuis le début, au plus `limite` photos.
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "selection" {
                let limite = params["limite"]?.int ?? 50
                fake.replies["selection"] = ["total": 600, "photos": .array((1...min(600, limite)).map { ["id": .number(Double($0)), "fichier": "P"] })]
            } else if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P"] })]
            }
        }
        _ = call("contact_sheet", ["selection": true, "offset": 520])
        let demandes = fake.calls.filter { $0.command == "selection" }
        XCTAssertEqual(demandes.map { $0.params["limite"]?.int }, [500, 1_020], "redemandée assez loin pour atteindre la tranche")
        XCTAssertEqual(fake.calls.filter { $0.command == "vignettes" }.flatMap { $0.params["photos"]?.array?.compactMap(\.int) ?? [] }, Array(521...550))
    }

    func testUnModuleDAvantDecritLeDebutDeLaSelection() throws {
        // Sans decalage dans la réponse, le connecteur saute lui-même les premières photos.
        fake.replies["selection"] = ["total": 40, "photos": .array((1...40).map { ["id": .number(Double($0)), "fichier": "P"] })]
        _ = call("contact_sheet", ["selection": true, "offset": 30])
        XCTAssertEqual(fake.calls.first { $0.command == "vignettes" }?.params["photos"]?.array?.compactMap(\.int), Array(31...40))
    }

    // MARK: Une grande série se note planche par planche (26 octobre 2026)

    /// Le tri de 951 photos faisait 147 000 caractères, dont 80 % de plafonds, une ligne par photo :
    /// Claude Code dans la fenêtre le rangeait dans un fichier qu'il ne pouvait pas lire.
    func testUneGrandeSerieDitSesPlafondsParMotif() throws {
        func photo(_ id: Int, nettete: Double = 60, bruit: Double = 0.3) -> PhotoTriee {
            var p = PhotoTriee(id: id, fichier: "P\(id).RAF")
            p.detail = DetailMeasurements(zones: Array(repeating: nettete, count: 9), noise: bruit, shadowNoise: nil, side: 1024)
            return p
        }
        let douces = (1...60).map { photo($0, nettete: 20 + Double($0 % 10)) }
        let bruitees = (61...100).map { photo($0, bruit: 1.6 + Double($0 % 4) / 10) }
        let nettes = (101...150).map { photo($0) }
        let bilan = Tri.bilan(douces + bruitees + nettes)
        XCTAssertNil(bilan["plafonds"], "au-delà de \(Tri.plafondsParPhotoMax) photos, plus une ligne par photo")
        let motifs = try XCTUnwrap(bilan["plafonds_par_motif"]?.array)
        XCTAssertEqual(motifs.count, 2, JSONCoding.line(.array(motifs)))
        XCTAssertEqual(motifs[0]["note_max"]?.int, 2)
        XCTAssertEqual(motifs[0]["pourquoi"]?.string, "douce (netteté sous 35)")
        XCTAssertEqual(motifs[0]["nombre"]?.int, 60)
        XCTAssertEqual(motifs[0]["photos"]?.array?.compactMap(\.int), Array(1...60))
        XCTAssertNil(motifs[0]["a_verifier"])
        XCTAssertEqual(motifs[1]["note_max"]?.int, 5)
        XCTAssertEqual(motifs[1]["a_verifier"]?.bool, true)
        XCTAssertEqual(motifs[1]["pourquoi"]?.string, "bruit fort : à noter après le débruitage (enhance_photo)")
        XCTAssertEqual(motifs[1]["photos"]?.array?.compactMap(\.int), Array(61...100))
        // Une petite séance garde la raison de chaque photo, mesures comprises.
        let petite = Tri.bilan(Array(douces.prefix(3)))
        XCTAssertTrue(petite["plafonds"]?["1"]?["pourquoi"]?.string?.contains("douce (netteté 21") == true)
        XCTAssertNil(petite["plafonds_par_motif"])
        // Le plafond posé reste celui de chaque photo (propose_ratings le fait respecter).
        XCTAssertEqual(Tri.plafonds(douces + bruitees + nettes)[1]?.note, 2)
    }

    /// La première planche d'une grande sélection : refusée sans offset jusqu'au 26 octobre 2026.
    func testLaPlancheDUneGrandeSelectionCommenceSansOffset() throws {
        let nette = TriTests.damier()
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "selection" {
                let decalage = params["decalage"]?.int ?? 0, limite = params["limite"]?.int ?? 50
                let ids = Array((decalage + 1)...min(951, decalage + limite))
                fake.replies["selection"] = ["total": 951, "decalage": .number(Double(decalage)),
                                             "photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P"] })]
            } else if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P", "note": 0, "drapeau": "aucun",
                                                                          "vignette": .string(TestSupport.previewFile(nette))] })]
            }
        }
        let premiere = call("contact_sheet", ["selection": true])
        XCTAssertFalse(premiere.isError, premiere.text)
        XCTAssertEqual(fake.calls.filter { $0.command == "vignettes" }.flatMap { $0.params["photos"]?.array?.compactMap(\.int) ?? [] }, Array(1...30))
        XCTAssertTrue(premiere.text.contains("921 photo(s) de plus : rappeler avec offset = 30"), premiere.text)
        let derniere = call("contact_sheet", ["selection": true, "offset": 930])
        XCTAssertFalse(derniere.isError, derniere.text)
        XCTAssertFalse(derniere.text.contains("de plus"), "la dernière planche : rien de plus")
        XCTAssertEqual(fake.calls.last { $0.command == "vignettes" }?.params["photos"]?.array?.compactMap(\.int), Array(931...951))
    }

    /// Les vidéos écartées comptent dans l'offset de la suite (sans elles, des photos revenaient
    /// d'une planche à l'autre), et une tranche faite de vidéos seulement donne la suite au lieu
    /// d'arrêter le parcours (relecture du 26 octobre 2026).
    func testLaPlancheSauteLesVideosSansRemontrerDePhotos() throws {
        let nette = TriTests.damier()
        let videos = Set([15, 100] + Array(31...60))
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "selection" {
                let decalage = params["decalage"]?.int ?? 0, limite = params["limite"]?.int ?? 50
                let ids = Array((decalage + 1)...min(100, decalage + limite))
                fake.replies["selection"] = ["total": 100, "decalage": .number(Double(decalage)),
                                             "photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P", "video": .bool(videos.contains($0))] })]
            } else if command == "vignettes" {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["vignettes"] = ["photos": .array(ids.map { ["id": .number(Double($0)), "fichier": "P", "note": 0, "drapeau": "aucun",
                                                                          "vignette": .string(TestSupport.previewFile(nette))] })]
            }
        }
        func vignettes(depuis debut: Int) -> [Int] {
            fake.calls.dropFirst(debut).filter { $0.command == "vignettes" }.flatMap { $0.params["photos"]?.array?.compactMap(\.int) ?? [] }
        }
        let premiere = call("contact_sheet", ["selection": true])
        XCTAssertFalse(premiere.isError, premiere.text)
        XCTAssertEqual(vignettes(depuis: 0), (1...30).filter { $0 != 15 })
        XCTAssertTrue(premiere.text.contains("70 photo(s) de plus : rappeler avec offset = 30"), premiere.text)
        XCTAssertTrue(premiere.text.contains("1 vidéo(s) écartée(s)"), premiere.text)
        // Les positions de la planche, vidéos comprises, pour la ligne d'état de la fenêtre.
        let info = try JSONCoding.parse(premiere.text)
        XCTAssertEqual(info["planche"]?["premiere"]?.int, 1)
        XCTAssertEqual(info["planche"]?["derniere"]?.int, 30)
        XCTAssertEqual(info["planche"]?["sur"]?.int, 100)
        // Trente vidéos d'affilée : pas d'erreur, la suite.
        var avant = fake.calls.count
        let videosSeules = call("contact_sheet", ["selection": true, "offset": 30])
        XCTAssertFalse(videosSeules.isError, videosSeules.text)
        XCTAssertTrue(videosSeules.text.contains("rappeler avec offset = 60"), videosSeules.text)
        XCTAssertEqual(vignettes(depuis: avant), [], "aucune vignette à demander")
        // La dernière tranche finit sur une vidéo : rien de plus à demander.
        avant = fake.calls.count
        let derniere = call("contact_sheet", ["selection": true, "offset": 90])
        XCTAssertFalse(derniere.isError, derniere.text)
        XCTAssertEqual(vignettes(depuis: avant), Array(91...99))
        XCTAssertFalse(derniere.text.contains("de plus"), derniere.text)
        // Une liste de photos donnée n'a ni planche ni suite.
        let liste = call("contact_sheet", ["photo_ids": [1, 2, 3]])
        XCTAssertNil(try JSONCoding.parse(liste.text)["planche"])
    }
}
