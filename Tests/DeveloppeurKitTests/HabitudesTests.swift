import XCTest
@testable import DeveloppeurKit

/// Les habitudes en chiffres (1.6, remember_style avec habits) : attribution Claude ou Dany, écarts à
/// la valeur neutre, seuils (photos, jours, part touchée, sens, dispersion), tranches d'ISO, photos
/// écartées, phrases, et la lecture par lots en lecture seule, sans rien écrire au guide.
final class HabitudesTests: XCTestCase {
    typealias P = Habitudes.Photo

    /// Une photo RAW de X-H2S, prise le jour `jour` (1 à 28 d'octobre 2026).
    func photo(_ id: Int, _ valeurs: [String: JSONValue], jour: Int = 1, iso: Double = 400, appareil: String = "X-H2S",
               raw: Bool = true, claude: Set<String> = [], reprises: Set<String> = []) -> P {
        P(id: id, appareil: appareil, iso: iso, jour: String(format: "2026-10-%02d", jour), raw: raw, valeurs: valeurs,
          claude: claude, reprises: reprises, copie: nil)
    }

    /// `n` photos sur `jours` jours, avec les valeurs que donne `valeurs(i)`.
    func serie(_ n: Int, jours: Int = 10, iso: Double = 400, _ valeurs: (Int) -> [String: JSONValue]) -> [P] {
        (0..<n).map { photo($0 + 1, valeurs($0), jour: 1 + $0 % jours, iso: iso) }
    }

    // MARK: Statistiques

    func testQuantilesInterpoles() {
        XCTAssertEqual(Habitudes.quantile([1, 2, 3], 0.5), 2)
        XCTAssertEqual(Habitudes.quantile([1, 2, 3, 4], 0.5), 2.5, "n pair : entre les deux du milieu")
        XCTAssertEqual(Habitudes.quantile([0, 10, 20, 30, 40], 0.25), 10)
        XCTAssertEqual(Habitudes.quantile([5], 0.75), 5)
        XCTAssertEqual(Habitudes.quantile([], 0.5), 0)
    }

    func testAttributionClaudeEtDany() {
        let sansMemoire = photo(1, ["Highlights2012": -30])
        XCTAssertTrue(Habitudes.deDany(sansMemoire, "Highlights2012"), "sans mémoire de Claude, tout est à Dany")
        let touchee = photo(2, ["Highlights2012": -30, "Shadows2012": 20], claude: ["Highlights2012"])
        XCTAssertFalse(Habitudes.deDany(touchee, "Highlights2012"), "une clé de Claude est écartée")
        XCTAssertTrue(Habitudes.deDany(touchee, "Shadows2012"), "une clé que Claude n'a pas touchée reste à Dany")
        let reprise = photo(3, ["Highlights2012": -30], claude: ["Highlights2012"], reprises: ["Highlights2012"])
        XCTAssertTrue(Habitudes.deDany(reprise, "Highlights2012"), "reprise à la main : à Dany")
        // Les masques de Claude (clé #MaskGroupBasedCorrections, rendue par le module) ne font pas une
        // photo retouchée par Dany.
        let masquesDeClaude = photo(4, ["#MaskGroupBasedCorrections": 2], claude: ["#MaskGroupBasedCorrections"])
        XCTAssertEqual(Habitudes.ecartee(masquesDeClaude), "sans_retouche")
        XCTAssertEqual(Habitudes.valeursDeClaude([touchee, masquesDeClaude]), 2)
    }

    func testEcartALaValeurNeutreSelonLeFormat() {
        // Netteté 40 sur un RAW : la valeur par défaut, pas une habitude ; sur un JPEG, si.
        XCTAssertEqual(Habitudes.neutre("Sharpness", raw: true), 40)
        XCTAssertEqual(Habitudes.neutre("Sharpness", raw: false), 0)
        XCTAssertEqual(Habitudes.neutre("SharpenRadius", raw: true), 1)
        let raws = serie(30) { _ in ["Sharpness": 40, "Highlights2012": -20] }
        let s = try! XCTUnwrap(Habitudes.statistique("Sharpness", raws))
        XCTAssertEqual(s.photos, 30)
        XCTAssertEqual(s.touchees, 0, "40 sur un RAW n'est pas touché")
        let rayon = try! XCTUnwrap(Habitudes.statistique("SharpenRadius", serie(30) { _ in ["SharpenRadius": 1.2] }))
        XCTAssertEqual(rayon.mediane, 0.2, accuracy: 1e-9, "écart à 1, pas la valeur")
    }

    func testUnePhraseQuandToutTient() throws {
        let photos = serie(40) { i in ["Highlights2012": .number(Double(-30 - i % 10))] }
        let s = try XCTUnwrap(Habitudes.statistique("Highlights2012", photos))
        XCTAssertEqual(s.touche, 1)
        XCTAssertEqual(s.memeSens, 1)
        XCTAssertEqual(s.jours, 10)
        XCTAssertTrue(s.manque.isEmpty, "\(s.manque)")
        let p = try XCTUnwrap(Habitudes.phrase(s, appareil: "X-H2S", note: 4))
        XCTAssertEqual(p.rubrique, "tone")
        XCTAssertTrue(p.constat.hasPrefix("Sur tes X-H2S notées 4 ★ et plus (40 photos, 10 jours de prise de vue), tu baisses Hautes lumières sur 100 %"), p.constat)
        XCTAssertTrue(p.constat.contains("de −35 en médiane (de −37 à −32 pour la moitié)"), p.constat)
        XCTAssertEqual(p.phrase, "X-H2S : Hautes lumières plus bas, autour de −35.")
    }

    func testPasDePhraseSousLesSeuils() throws {
        // 19 photos : trop peu.
        let peu = try XCTUnwrap(Habitudes.statistique("Highlights2012", serie(19) { _ in ["Highlights2012": -30] }))
        XCTAssertEqual(peu.manque, ["photos"])
        // Une rafale synchronisée : 60 photos du même jour.
        let rafale = try XCTUnwrap(Habitudes.statistique("Highlights2012", serie(60, jours: 1) { _ in ["Highlights2012": -30] }))
        XCTAssertEqual(rafale.manque, ["jours"])
        XCTAssertNil(Habitudes.phrase(rafale, appareil: "X-H2S", note: 4))
        // Dans les deux sens.
        let deuxSens = try XCTUnwrap(Habitudes.statistique("Highlights2012", serie(40) { i in ["Highlights2012": i % 2 == 0 ? -30 : 30] }))
        XCTAssertTrue(deuxSens.manque.contains("sens"))
        // Dispersé : de −5 à −95.
        let disperse = try XCTUnwrap(Habitudes.statistique("Highlights2012", serie(40) { i in ["Highlights2012": i % 2 == 0 ? -5 : -95] }))
        XCTAssertEqual(disperse.manque, ["dispersion"])
        // Rarement touché : 10 sur 40.
        let rare = try XCTUnwrap(Habitudes.statistique("Dehaze", serie(40) { i in ["Dehaze": i < 10 ? 15 : 0] }))
        XCTAssertEqual(rare.manque, ["touche"])
    }

    func testBruitParTrancheDISO() {
        let basses = serie(50, iso: 400) { _ in ["LuminanceSmoothing": 0, "Highlights2012": -20] }
        let hautes = (0..<20).map { photo(100 + $0, ["LuminanceSmoothing": 35, "Highlights2012": -20], jour: 1 + $0 % 8, iso: 6400) }
        let analyse = Habitudes.analyser(basses + hautes, trouvees: 70, note: 4)
        let groupe = analyse.groupes[0]
        XCTAssertEqual(groupe.parISO.map(\.tranche.libelle), ["≤ 800", "> 3 200"])
        let bruit = analyse.phrases.first { $0.phrase.contains("Réduction du bruit : luminance") }
        XCTAssertEqual(bruit?.phrase, "X-H2S (au-delà de ISO 3 200) : Réduction du bruit : luminance plus haut, autour de +35.")
        XCTAssertEqual(analyse.phrases.filter { $0.phrase.contains("Hautes lumières") }.count, 1, "une phrase pour tout l'appareil, pas une par tranche")
    }

    func testPhotosEcarteesAvantToutCalcul() {
        var video = photo(1, [:]); video.video = true
        var essai = photo(2, ["Highlights2012": -30]); essai.essai = true
        var copie = photo(3, ["Highlights2012": -30]); copie.virtuelle = true; copie.copie = "Claude"
        let ancien = photo(4, ["Highlights2012": -30, "ProcessVersion": "5.7"])
        let actuel = photo(5, ["Highlights2012": -30, "ProcessVersion": "15.4"])
        let telleQuelle = photo(6, ["Highlights2012": 0, "LensProfileEnable": 1, "WhiteBalance": "As Shot"])
        var copieDeDany = photo(7, ["Highlights2012": -30]); copieDeDany.virtuelle = true; copieDeDany.copie = "Copie 1"
        let analyse = Habitudes.analyser([video, essai, copie, ancien, actuel, telleQuelle, copieDeDany], trouvees: 7, note: 4)
        XCTAssertEqual(analyse.ecartees, ["videos": 1, "essais": 1, "copies_claude": 1, "ancien_processus": 1, "sans_retouche": 1])
        XCTAssertEqual(analyse.groupes.first?.photos.map(\.id), [5, 7])
    }

    func testTeinteDUnRawNonMesureeNiRetouche() {
        // Un RAW noté sans retouche, balance « Telle quelle » : Lightroom rend la teinte du boîtier
        // (+6 à +12), pas 0. Ni une retouche, ni une habitude.
        let raws = serie(30, jours: 6) { i in ["Tint": .number(Double(6 + i % 7)), "WhiteBalance": "As Shot", "ProcessVersion": "15.4"] }
        let analyse = Habitudes.analyser(raws, trouvees: 30, note: 4)
        XCTAssertEqual(analyse.ecartees, ["sans_retouche": 30])
        XCTAssertTrue(analyse.phrases.isEmpty)
        XCTAssertNil(Habitudes.statistique("Tint", raws), "la teinte d'un RAW ne se mesure pas")
        // Mêlée à une vraie retouche, elle ne fait pas de phrase non plus.
        let retouches = serie(30, jours: 6) { i in ["Tint": .number(Double(6 + i % 7)), "Highlights2012": -30] }
        XCTAssertFalse(Habitudes.analyser(retouches, trouvees: 30, note: 4).phrases.contains { $0.phrase.contains("Teinte") })
        // Hors RAW, la teinte est relative (0 = telle quelle) : elle se mesure.
        let jpeg = (0..<30).map { photo($0 + 1, ["Tint": 8, "Highlights2012": -30], jour: 1 + $0 % 6, raw: false) }
        XCTAssertEqual(Habitudes.statistique("Tint", jpeg)?.touchees, 30)
        // Mais seule, elle ne fait pas une photo retouchée (la balance ne compte pas).
        XCTAssertEqual(Habitudes.ecartee(photo(99, ["Tint": 8], raw: false)), "sans_retouche")
    }

    func testDebruitageDeLightroomNiMesureNiRetouche() throws {
        // Constaté dans Lightroom 15.6 le 2 novembre 2026 : le débruitage (Améliorer › Débruiter, sur
        // le RAF ou dans un DNG « -Bruit » d'avant) met Réduction du bruit : couleur à 0. Sur 523
        // X-H2S notées 4 ★, 313 à 0 (toutes débruitées) : « tu baisses Réduction du bruit : couleur
        // de −25 » était le débruitage, pas une habitude.
        let debruitees = serie(30, jours: 6) { _ in ["ColorNoiseReduction": 0, "ProcessVersion": "15.4"] }
        XCTAssertTrue(Habitudes.debruitee(debruitees[0]))
        XCTAssertEqual(Habitudes.analyser(debruitees, trouvees: 30, note: 4).ecartees, ["sans_retouche": 30],
                       "le débruitage seul n'est pas une retouche")
        XCTAssertNil(Habitudes.statistique("ColorNoiseReduction", debruitees))
        let retouchees = serie(30, jours: 6) { _ in ["ColorNoiseReduction": 0, "Highlights2012": -30] }
        XCTAssertFalse(Habitudes.analyser(retouchees, trouvees: 30, note: 4).phrases.contains { $0.phrase.contains("bruit : couleur") })
        // Une valeur montée à la main reste mesurée ; hors RAW, 0 est la valeur neutre.
        let montees = serie(30, jours: 6) { _ in ["ColorNoiseReduction": 40] }
        XCTAssertEqual(try XCTUnwrap(Habitudes.statistique("ColorNoiseReduction", montees)).touchees, 30)
        XCTAssertFalse(Habitudes.debruitee(photo(1, ["ColorNoiseReduction": 0], raw: false)))
    }

    func testRecadrageLuParSesClesEtAttribue() {
        let cadre: [String: JSONValue] = ["CropLeft": 0.05, "CropTop": 0, "CropRight": 0.95, "CropBottom": 1, "CropAngle": 0]
        let redresse: [String: JSONValue] = ["CropLeft": 0.02, "CropTop": 0.02, "CropRight": 0.98, "CropBottom": 0.98, "CropAngle": 1.2]
        let neutre: [String: JSONValue] = ["CropLeft": 0, "CropTop": 0, "CropRight": 1, "CropBottom": 1, "CropAngle": 0]
        XCTAssertTrue(Habitudes.cles.contains("CropAngle"))
        XCTAssertFalse(Habitudes.cles.contains("HasCrop"), "HasCrop n'est jamais rangée par Claude")
        // Un recadrage seul de Dany : une retouche.
        XCTAssertNil(Habitudes.ecartee(photo(1, cadre)))
        XCTAssertEqual(Habitudes.recadree(photo(2, neutre)), false)
        XCTAssertNil(Habitudes.recadree(photo(3, [:])))
        // Un redressement de Claude (crop.angle : avantClaude a CropAngle, Lightroom change les bords) :
        // pas à Dany, la photo reste sans retouche.
        let deClaude = photo(4, redresse, claude: ["CropAngle"])
        XCTAssertEqual(Habitudes.recadree(deClaude), false)
        XCTAssertEqual(Habitudes.ecartee(deClaude), "sans_retouche")
        // Repris à la main par Dany depuis : à lui.
        XCTAssertEqual(Habitudes.recadree(photo(5, redresse, claude: ["CropAngle"], reprises: ["CropLeft"])), true)
        // La part « recadrees » ne compte pas les recadrages de Claude.
        let photos = (0..<10).map { i in
            photo(10 + i, redresse.merging(["Highlights2012": -30]) { a, _ in a }, jour: 1 + i, claude: i < 8 ? ["CropAngle", "CropLeft"] : [])
        }
        let json = Habitudes.json(Habitudes.analyser(photos, trouvees: 10, note: 4), note: 4)
        XCTAssertEqual(json["groupes"]?.array?.first?["recadrees"]?.double ?? -1, 0.2, accuracy: 1e-9)
    }

    func testAuPlusHuitPhrasesLesPlusFortesDAbord() {
        let cles = ["Highlights2012", "Shadows2012", "Whites2012", "Blacks2012", "Contrast2012", "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation"]
        let photos = serie(40) { i in
            var v: [String: JSONValue] = [:]
            for (k, cle) in cles.enumerated() { v[cle] = i < 40 - k ? 20 : 0 }
            return v
        }
        let phrases = Habitudes.analyser(photos, trouvees: 40, note: 4).phrases
        XCTAssertEqual(phrases.count, 8)
        XCTAssertTrue(phrases[0].phrase.contains("Hautes lumières"), "touché partout : la plus forte")
        XCTAssertFalse(phrases.contains { $0.phrase.contains("Saturation") }, "la plus faible est coupée")
    }

    func testNombresALaFrancaise() {
        XCTAssertEqual(Habitudes.signe(-35), "−35")
        XCTAssertEqual(Habitudes.signe(0.35), "+0,35")
        XCTAssertEqual(Habitudes.signe(2.5), "+2,5")
        XCTAssertEqual(Habitudes.signe(0), "0")
        XCTAssertEqual(Habitudes.libelle("Sharpness"), "Netteté : gain", "sans la parenthèse des défauts")
    }

    func testReponsePlafonnee() throws {
        // Six appareils, quatre tranches d'ISO, tous les réglages touchés : la réponse reste courte.
        var photos: [P] = []
        for (a, appareil) in ["X-H2S", "X-T20", "X100V", "iPhone", "Z 6", "EOS R"].enumerated() {
            for i in 0..<200 {
                var v: [String: JSONValue] = [:]
                for (k, cle) in Habitudes.clesNumeriques.enumerated() { v[cle] = .number(Double(10 + (i + k) % 5)) }
                v["CameraProfile"] = .string("Camera Profil \(i % 30)")
                photos.append(photo(a * 1000 + i, v, jour: 1 + i % 20, iso: [200, 1000, 2000, 8000][i % 4], appareil: appareil))
            }
        }
        let json = Habitudes.json(Habitudes.analyser(photos, trouvees: 1200, note: 4), note: 4)
        let taille = JSONCoding.line(json).utf8.count
        XCTAssertLessThanOrEqual(taille, 18_000, "\(taille) octets : environ 5 000 jetons au pire, loin des 25 000 de Claude Code")
        XCTAssertEqual(json["groupes"]?.array?.count, 4)
        XCTAssertEqual(json["autres_appareils"]?.array?.count, 2)
        XCTAssertLessThanOrEqual(json["phrases"]?.array?.count ?? 99, 8)
    }

    // MARK: L'outil

    /// Un faux module : `total` photos notées ; chaque lecture rend les photos demandées, Highlights
    /// baissées par Dany, Shadows touchées par Claude.
    func fauxModule(_ fake: FakeLightroom, total: Int) {
        fake.onSend = { [unowned fake] command, params in
            guard command == "habitudes" else { return }
            if params["mode"]?.string == "liste" {
                fake.replies["habitudes"] = ["total": .number(Double(total)),
                                             "photos": .array((1...total).prefix(5000).map { .number(Double($0)) })]
            } else {
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                fake.replies["habitudes"] = ["photos": .array(ids.map { id in
                    ["id": .number(Double(id)), "appareil": "X-H2S", "iso": 640, "jour": .string(String(format: "2026-09-%02d", 1 + id % 12)),
                     "format": "RAW", "virtuelle": false, "essai": false, "video": false,
                     "valeurs": ["Highlights2012": -40, "Shadows2012": 50, "Sharpness": 40, "ProcessVersion": "15.4"],
                     "claude": ["Shadows2012"], "reprises": [], "memoire_autre": false]
                })]
            }
        }
    }

    func testRememberStyleHabitsLitParLotsSansRienEcrire() throws {
        let fake = FakeLightroom()
        let guide = GuideStyle(fichier: TestSupport.temporaryDirectory().appendingPathComponent("guide-de-style.md"))
        _ = try guide.ajouter("Jamais de vignetage", rubrique: "other")
        let avant = try guide.lire()
        let tools = ToolHandler(lightroom: fake, guideStyle: guide)
        fauxModule(fake, total: 600)
        let resultat = tools.call(name: "remember_style", arguments: ["habits": true, "camera": "X-H2S"])
        XCTAssertFalse(resultat.isError, resultat.text)
        let reponse = try JSONCoding.parse(resultat.text)
        XCTAssertEqual(fake.calls.filter { $0.command == "habitudes" }.map { $0.params["mode"]?.string }, ["liste", "lire", "lire", "lire"],
                       "600 photos : trois lots de 250 au plus")
        XCTAssertEqual(fake.calls.first?.params["note_min"]?.int, 4)
        XCTAssertEqual(fake.calls.first?.params["appareil"]?.string, "X-H2S")
        XCTAssertTrue(fake.calls.dropFirst().allSatisfy { ($0.params["photos"]?.array?.count ?? 0) <= 250 })
        XCTAssertEqual(Set(fake.commands), ["habitudes"], "des lectures seulement")
        XCTAssertEqual(reponse["photos_lues"]?.int, 600)
        XCTAssertEqual(reponse["valeurs_de_claude_ecartees"]?.int, 600, "les ombres de Claude")
        let phrases = try XCTUnwrap(reponse["phrases"]?.array)
        XCTAssertEqual(phrases.count, 1, "les hautes lumières seulement : les ombres sont de Claude, la netteté au défaut")
        XCTAssertTrue(phrases[0]["phrase_proposee"]?.string?.contains("Hautes lumières") == true)
        XCTAssertEqual(try guide.lire(), avant, "le guide n'est pas modifié")
        XCTAssertNotNil(reponse["regle_de_lecture"])
    }

    func testRememberStyleHabitsAuPlus5000EtSansCibleRefuse() throws {
        let fake = FakeLightroom()
        let tools = ToolHandler(lightroom: fake, guideStyle: GuideStyle(fichier: TestSupport.temporaryDirectory().appendingPathComponent("g.md")))
        fauxModule(fake, total: 7000)
        let reponse = try JSONCoding.parse(tools.call(name: "remember_style", arguments: ["habits": true, "collection": "Voyage", "rating_min": 5]).text)
        XCTAssertEqual(reponse["photos_trouvees"]?.int, 7000)
        XCTAssertEqual(reponse["photos_lues"]?.int, 5000)
        XCTAssertNotNil(reponse["echantillon"])
        XCTAssertEqual(fake.calls.first?.params["limite"]?.int, 5000)
        XCTAssertEqual(fake.calls.first?.params["note_min"]?.int, 5)
        XCTAssertEqual(fake.calls.first?.params["collection"]?.string, "Voyage")
        fake.calls = []
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["habits": true]).isError, "sans cible : tout le catalogue")
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["habits": true, "photo_ids": [1]]).isError)
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["habits": true, "camera": "X-H2S", "rating_min": 6]).isError)
        XCTAssertTrue(fake.calls.isEmpty, "refusé avant tout envoi")
    }

    func testRememberStyleHabitsSArreteALAnnulation() {
        let fake = FakeLightroom()
        let tools = ToolHandler(lightroom: fake, guideStyle: GuideStyle(fichier: TestSupport.temporaryDirectory().appendingPathComponent("g.md")))
        fauxModule(fake, total: 600)
        let contexte = ContexteAppel()
        let suite = fake.onSend
        fake.onSend = { command, params in
            suite?(command, params)
            if params["mode"]?.string == "lire" { contexte.annuler() }
        }
        XCTAssertTrue(tools.call(name: "remember_style", arguments: ["habits": true, "camera": "X-H2S"], contexte: contexte).isError)
        XCTAssertEqual(fake.calls.filter { $0.params["mode"]?.string == "lire" }.count, 1, "la suite ne part pas")
    }

    func testDescriptionDeRememberStyle() throws {
        let tools = ToolHandler(lightroom: FakeLightroom())
        let outil = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "remember_style" })
        let description = try XCTUnwrap(outil["description"]?.string)
        XCTAssertLessThanOrEqual(description.count, 700, "\(description.count) caractères")
        XCTAssertTrue(description.hasPrefix("Guide de style personnel"))
        let habits = try XCTUnwrap(outil["inputSchema"]?["properties"]?["habits"]?["description"]?.string)
        XCTAssertLessThanOrEqual(habits.count, 500, "\(habits.count) caractères")
        XCTAssertTrue(habits.hasPrefix("true = ses habitudes en chiffres"))
        for attendu in ["lecture seule", "pas fini", "5000"] { XCTAssertTrue(habits.contains(attendu), attendu) }
        XCTAssertTrue(outil["inputSchema"]?["properties"]?["collection"]?["description"]?.string?.contains("habits") == true)
    }
}
