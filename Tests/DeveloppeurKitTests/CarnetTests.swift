import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Version 1.3 : le carnet de progrès, côté connecteur (Carnet.swift) : défauts de la prise de vue
/// mesurés sur une vue entière et sur une ligne, envoyés au module (commande carnet constater) par
/// view_photo, measure_angle et read_composition ; le carnet en Markdown (export_journal avec
/// notebook) ; le relevé `--constats`, en lecture seule. Jamais le vrai Lightroom : FakeLightroom.
final class CarnetTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Aides

    func mesures(mediane: Double = 50, p95: Double = 90) -> PhotoMeasurements {
        PhotoMeasurements(meanL: mediane, percentilesL: [1: 5, 5: 10, 25: mediane, 50: mediane, 75: mediane, 95: p95, 99: p95],
                          histogramL: [Double](repeating: 10, count: 10), clippedHighlights: 0, pureWhite: 0,
                          crushedShadows: 0, clippedChannels: [0, 0, 0], meanChroma: 12, saturatedShare: 0,
                          neutralA: 0, neutralB: 0, neutralShare: 30, pixelCount: 512 * 341)
    }

    func detail(nettete: Double = 60, bruit: Double = 0.3, ombres: Double? = nil, side: Int = 1024) -> DetailMeasurements {
        DetailMeasurements(zones: [Double](repeating: nettete * 0.8, count: 8) + [nettete], noise: bruit, shadowNoise: ombres, side: side)
    }

    /// Image de 300 × 300 : `blancs` lignes de blanc pur depuis le haut (ou le bas), gris ailleurs.
    func image(blancs: Int, enBas: Bool = false) -> CGImage {
        TestSupport.imagePixels(width: 300, height: 300) { _, y in
            let blanc = enBas ? y >= 300 - blancs : y < blancs
            return blanc ? (255, 255, 255) : (120, 120, 120)
        }
    }

    func vue(mesures: PhotoMeasurements? = nil, detail: DetailMeasurements? = nil, reduite: CGImage? = nil,
             af: PhotoTriee.MiseAuPoint? = nil, intention: IntentionBoitier? = nil, intacte: Bool = true) -> Carnet.Vue {
        Carnet.constatsVue(mesures: mesures ?? self.mesures(), detail: detail ?? self.detail(), reduite: reduite ?? image(blancs: 0),
                           af: af, intention: intention, geometrieIntacte: intacte)
    }

    func codes(_ vue: Carnet.Vue) -> [String] { vue.defauts.map(\.code) }

    /// Les règles de la commande carnet constater du module (Carnet.lua, vueValide et
    /// vocabulaireValide), reprises ici : ce que le connecteur envoie doit les tenir.
    func verifierPourLeModule(_ params: [String: JSONValue], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(params["action"]?.string, "constater", file: file, line: line)
        XCTAssertNotNil(params["photo"]?.int, "photo obligatoire", file: file, line: line)
        XCTAssertEqual(params["vocabulaire"], PriseDeVue.vocabulaire, file: file, line: line)
        let vocabulaire = params["vocabulaire"]?.array ?? []
        XCTAssertLessThanOrEqual(vocabulaire.count, 40, file: file, line: line)
        let connus = Set(vocabulaire.compactMap { $0["code"]?.string })
        XCTAssertEqual(connus.count, vocabulaire.count, "codes uniques", file: file, line: line)
        XCTAssertTrue((params["vue"] == nil) != (params["angle"] == nil), "vue ou angle, l'un ou l'autre", file: file, line: line)
        func codeValide(_ code: String?) -> Bool {
            guard let code, code.range(of: "^[a-z_]+$", options: .regularExpression) != nil else { return false }
            return connus.contains(code)
        }
        if let vue = params["vue"] {
            let cherches = vue["cherches"]?.array?.compactMap(\.string) ?? []
            XCTAssertFalse(cherches.isEmpty, file: file, line: line)
            XCTAssertLessThanOrEqual(cherches.count, 12, file: file, line: line)
            XCTAssertTrue(cherches.allSatisfy(codeValide), "\(cherches)", file: file, line: line)
            for defaut in vue["defauts"]?.array ?? [] {
                XCTAssertTrue(cherches.contains(defaut["code"]?.string ?? ""), "un défaut trouvé est cherché", file: file, line: line)
                if let mesure = defaut["mesure"] { XCTAssertTrue(mesure.double?.isFinite == true, file: file, line: line) }
                XCTAssertLessThanOrEqual(defaut["texte"]?.string?.utf8.count ?? 0, 200, file: file, line: line)
            }
        }
        if let angle = params["angle"] {
            XCTAssertTrue(angle["inclinaison"]?.double?.isFinite == true, file: file, line: line)
            XCTAssertTrue(codeValide(angle["code"]?.string), file: file, line: line)
            XCTAssertNotNil(angle["source"]?.string, file: file, line: line)
        }
    }

    /// Réponse « apercu » du module pour view_photo (entier, avec point_af) : la photo 7, ses
    /// étapes de Claude, son angle de recadrage et ses réglages de géométrie.
    func repondreApercu(_ image: Data, etapes: Int? = 0, angle: Double = 0, reglages: [String: JSONValue] = [:],
                        photo: JSONValue = ["id": 7, "fichier": "DSCF2402.RAF"], extra: [String: JSONValue] = [:]) {
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            var objet: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(image)), "photo": photo,
                                              "recadrage": ["recadree": false, "angle": .number(angle)], "reglages": .object(reglages)]
            if let etapes { objet["etapes_claude"] = ["nombre": .number(Double(etapes)), "derniere": .null] }
            for (cle, valeur) in extra { objet[cle] = valeur }
            fake!.replies["apercu"] = .object(objet)
        }
    }

    /// Un aperçu sombre (sous-exposé) et sans détail (flou), de la taille de view_photo.
    static let sombre = TestSupport.jpeg(red: 40, green: 40, blue: 40, width: 1344, height: 896)

    // MARK: Constats d'une vue

    func testUneImageSombreSansPartieClaireEstSousExposeeSaufVoulueSombre() {
        let sombre = mesures(mediane: 19.4, p95: 62)
        var v = vue(mesures: sombre)
        XCTAssertEqual(codes(v), ["sous_exposition"])
        XCTAssertEqual(v.defauts.first?.texte, "sous-exposée : L* médian 19,4, aucune partie claire (95e centile 62,0)")
        XCTAssertEqual(v.defauts.first?.mesure, 19.4)
        // Voulue sombre au boîtier : compensation de −1 IL, ou scène de nuit ; cherchée quand même.
        v = vue(mesures: sombre, intention: IntentionBoitier(compensation: -1))
        XCTAssertEqual(codes(v), [])
        XCTAssertTrue(v.cherches.contains("sous_exposition"))
        XCTAssertEqual(codes(vue(mesures: sombre, intention: IntentionBoitier(compensation: -0.6))), [], "à −0,6 IL : voulue")
        XCTAssertEqual(codes(vue(mesures: sombre, intention: IntentionBoitier(compensation: -0.3))), ["sous_exposition"])
        XCTAssertEqual(codes(vue(mesures: sombre, intention: IntentionBoitier(scene: 0x300))), [], "scène de nuit reconnue")
        XCTAssertEqual(codes(vue(mesures: sombre, intention: IntentionBoitier(modeImage: 0x5))), [], "mode scène de nuit choisi")
        // Les bornes : médiane et 95e centile strictement sous les seuils.
        XCTAssertEqual(codes(vue(mesures: mesures(mediane: 28, p95: 62))), [])
        XCTAssertEqual(codes(vue(mesures: mesures(mediane: 27.9, p95: 79.9))), ["sous_exposition"])
        XCTAssertEqual(codes(vue(mesures: mesures(mediane: 20, p95: 80))), [], "une partie claire : pas sous-exposée")
    }

    func testLeCielBruleSeCompteSurLeTiersHaut() throws {
        // 300 × 300 : le tiers haut fait 100 lignes ; 5 lignes blanches = 5 %.
        XCTAssertEqual(try XCTUnwrap(Carnet.blancPurHaut(image(blancs: 5))), 5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Carnet.blancPurHaut(image(blancs: 5, enBas: true))), 0, "le blanc du bas ne compte pas")
        var v = vue(reduite: image(blancs: 5))
        XCTAssertEqual(codes(v), ["ciel_brule"])
        XCTAssertEqual(v.defauts.first?.texte, "ciel ou haut de l'image brûlé : 5,0 % du tiers haut en blanc pur")
        v = vue(reduite: image(blancs: 5, enBas: true))
        XCTAssertEqual(codes(v), [])
        XCTAssertTrue(v.cherches.contains("ciel_brule"))
        XCTAssertEqual(codes(vue(reduite: image(blancs: 3))), [], "3 % : au seuil, pas au-delà")
        XCTAssertEqual(codes(vue(reduite: image(blancs: 4))), ["ciel_brule"])
        // Un blanc presque pur (253) ne compte pas, comme pureWhite.
        let presque = TestSupport.imagePixels(width: 300, height: 300) { _, y in y < 50 ? (253, 255, 255) : (120, 120, 120) }
        XCTAssertEqual(try XCTUnwrap(Carnet.blancPurHaut(presque)), 0)
    }

    func testFlouMiseAuPointEtBruitReprennentLesSeuilsRelevés() throws {
        var v = vue(detail: detail(nettete: 10))
        XCTAssertEqual(codes(v), ["flou"])
        XCTAssertEqual(v.defauts.first?.texte, "floue : aucune zone nette (netteté 10)")
        XCTAssertFalse(v.cherches.contains("mise_au_point"), "sans point de mise au point lu, la mise au point n'est pas cherchée")

        let af = PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.3, y: 0.3), nettete: 8, avertissement: false)
        v = vue(detail: detail(nettete: 40), af: af)
        XCTAssertEqual(codes(v), ["mise_au_point"])
        XCTAssertEqual(v.defauts.first?.mesure, 8)
        XCTAssertTrue(v.cherches.contains("mise_au_point"))
        // Signalée manquée par l'appareil, et pas nette au point : mise_au_point aussi.
        v = vue(detail: detail(nettete: 30), af: PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.3, y: 0.3), nettete: 20, avertissement: true))
        XCTAssertEqual(codes(v), ["mise_au_point"])
        XCTAssertEqual(v.defauts.first?.texte, "mise au point signalée manquée par l'appareil")
        XCTAssertEqual(codes(vue(detail: detail(nettete: 60), af: PhotoTriee.MiseAuPoint(point: .zero, nettete: 50, avertissement: true))), [])
        // Floue partout, point lu : la règle ne peut pas dire la mise au point manquée ; elle n'entre
        // pas dans la base (sinon une photo floue la compterait réussie).
        v = vue(detail: detail(nettete: 6), af: PhotoTriee.MiseAuPoint(point: .zero, nettete: 4, avertissement: true))
        XCTAssertEqual(codes(v), ["flou"])
        XCTAssertFalse(v.cherches.contains("mise_au_point"), "\(v.cherches)")
        XCTAssertTrue(v.cherches.contains("flou"))

        // Relevé le 21 octobre 2026 : le point AF sur du sable lisse (12,6, texture 11,6) disait la
        // mise au point manquée sur une photo nette. Sous le plancher de texture, elle n'est ni trouvée
        // ni cherchée (non jugée) ; signalée par l'appareil, elle se cherche encore. Le nuage du même
        // relevé (6,6, texture 23,6) est au-dessus du plancher : son faux constat reste (limite connue,
        // DetailMeasurements.textureMin).
        let sable = PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.5, y: 0.395), nettete: 12.6, avertissement: false, texture: 11.6)
        v = vue(detail: detail(nettete: 37.4), af: sable)
        XCTAssertEqual(codes(v), [])
        XCTAssertFalse(v.cherches.contains("mise_au_point"), "non jugée : \(v.cherches)")
        XCTAssertTrue(v.cherches.contains("flou"))
        let nuage = PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.5, y: 0.5), nettete: 6.6, avertissement: false, texture: 23.6)
        XCTAssertEqual(codes(vue(detail: detail(nettete: 171.9), af: nuage)), ["mise_au_point"], "limite connue")
        let texture = PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.5, y: 0.5), nettete: 6.6, avertissement: false, texture: 30)
        XCTAssertEqual(codes(vue(detail: detail(nettete: 171.9), af: texture)), ["mise_au_point"], "de la texture : jugée")
        let signalee = PhotoTriee.MiseAuPoint(point: CGPoint(x: 0.5, y: 0.5), nettete: 6.6, avertissement: true, texture: 10)
        v = vue(detail: detail(nettete: 30), af: signalee)
        XCTAssertEqual(codes(v), ["mise_au_point"])
        XCTAssertTrue(v.cherches.contains("mise_au_point"))

        v = vue(detail: detail(bruit: 1.6))
        XCTAssertEqual(codes(v), ["bruit"])
        XCTAssertEqual(v.defauts.first?.texte, "bruit fort : 1,60 (seuil 1,5)")
        XCTAssertEqual(codes(vue(detail: detail(bruit: 0.4, ombres: 1.5))), ["bruit"], "le bruit des ombres compte, comme la lecture de view_photo")
        XCTAssertEqual(codes(vue(detail: detail(bruit: 1.49))), [])
        // La mesure part au centième (le bruit se lit à deux décimales).
        let bruit = vue(detail: detail(bruit: 1.523)).json["defauts"]?.array?.first
        XCTAssertEqual(bruit?["code"]?.string, "bruit")
        XCTAssertEqual(try XCTUnwrap(bruit?["mesure"]?.double), 1.52, accuracy: 1e-9)

        // Sous 1 024 px (aperçu de 512), les seuils ne valent pas : ni netteté, ni bruit cherchés.
        v = vue(detail: detail(nettete: 5, bruit: 2, side: 512), af: af)
        XCTAssertEqual(codes(v), [])
        XCTAssertEqual(v.cherches, ["horizon_penche", "sous_exposition", "ciel_brule"])
    }

    func testCherchesEtTrouvesSuiventLOrdreDePriseDeVue() {
        // Nette ailleurs (40), floue au point lu (4) : mise au point manquée, les six cherchés.
        let v = vue(mesures: mesures(mediane: 15, p95: 40), detail: detail(nettete: 40, bruit: 2), reduite: image(blancs: 20),
                    af: PhotoTriee.MiseAuPoint(point: .zero, nettete: 4, avertissement: true))
        XCTAssertEqual(v.cherches, PriseDeVue.mesures.map(\.code))
        XCTAssertEqual(codes(v), ["sous_exposition", "ciel_brule", "bruit", "mise_au_point"])
        // Sans géométrie intacte, l'horizon n'est pas cherché (la base compterait droite une photo redressée).
        XCTAssertFalse(vue(intacte: false).cherches.contains("horizon_penche"))
        XCTAssertEqual(vue().cherches.first, "horizon_penche")
        // Aucune mesure : seul l'horizon reste cherché.
        let rien = Carnet.constatsVue(mesures: nil, detail: nil, reduite: nil, af: nil, intention: nil, geometrieIntacte: false)
        XCTAssertTrue(rien.cherches.isEmpty)
        // La forme que le module attend.
        let json = v.json
        XCTAssertEqual(json["cherches"]?.array?.count, 6)
        XCTAssertEqual(json["defauts"]?.array?.first?["code"]?.string, "sous_exposition")
        XCTAssertEqual(json["defauts"]?.array?.first?["mesure"]?.double, 15)
        XCTAssertEqual(v.textes.count, 4)
    }

    func testLesTextesSontCourtsEtPourUnAmateur() {
        let v = vue(mesures: mesures(mediane: 15, p95: 40), detail: detail(nettete: 5, bruit: 12.345), reduite: image(blancs: 100))
        var textes = v.textes
        textes.append(Carnet.constatHorizon(tilt: -12.34, vertical: false, angleActuel: 0, reglages: nil)?.texte ?? "")
        textes += [ToolHandler.descriptionJournal, ToolHandler.descriptionCarnet]
        for texte in textes {
            XCTAssertLessThanOrEqual(texte.utf8.count, texte.hasPrefix("Journal") || texte.hasPrefix("true") ? 1000 : 200, texte)
            for mot in ["photoshop", "galerie", "gallery", "concours", "client", "mariage"] {
                XCTAssertFalse(texte.lowercased().contains(mot), "« \(mot) » : \(texte)")
            }
        }
        // Un texte trop long est coupé sur un caractère entier.
        let long = Carnet.borner(String(repeating: "é", count: 150))
        XCTAssertLessThanOrEqual(long.utf8.count, 200)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertEqual(Carnet.borner("court"), "court")
    }

    // MARK: Ligne penchée

    func testConstatHorizon() throws {
        XCTAssertNil(Carnet.constatHorizon(tilt: 0.4, vertical: false, angleActuel: 0, reglages: nil), "sous 0,5° : ne se voit pas")
        let penche = try XCTUnwrap(Carnet.constatHorizon(tilt: 0.6, vertical: false, angleActuel: 0, reglages: nil))
        XCTAssertEqual(penche.code, "horizon_penche")
        XCTAssertEqual(penche.mesure, 0.6)
        XCTAssertEqual(penche.texte, "horizon ou ligne penchée de 0,6° (monte vers la droite)")
        XCTAssertEqual(Carnet.constatHorizon(tilt: -0.5, vertical: false, angleActuel: 0, reglages: nil)?.texte,
                       "horizon ou ligne penchée de 0,5° (descend vers la droite)")
        XCTAssertNil(Carnet.constatHorizon(tilt: 3, vertical: true, angleActuel: 0, reglages: nil), "une verticale ne compte pas")
        XCTAssertNil(Carnet.constatHorizon(tilt: 1.5, vertical: false, angleActuel: 1.2, reglages: nil), "déjà redressée")
        XCTAssertNil(Carnet.constatHorizon(tilt: 1.5, vertical: false, angleActuel: -0.01, reglages: nil))
        XCTAssertNotNil(Carnet.constatHorizon(tilt: 1.5, vertical: false, angleActuel: 0.004, reglages: nil), "reste d'un cadre calculé")
        XCTAssertNil(Carnet.constatHorizon(tilt: .nan, vertical: false, angleActuel: 0, reglages: nil))
        XCTAssertEqual(Carnet.angleJSON(penche, source: "measure_angle"),
                       ["inclinaison": 0.6, "code": "horizon_penche", "source": "measure_angle"])
    }

    func testLaGeometrieIntacteSuitLeModule() {
        XCTAssertTrue(Carnet.geometrieIntacte(reglages: nil, angleRecadrage: 0))
        XCTAssertTrue(Carnet.geometrieIntacte(reglages: ["PerspectiveUpright": 0, "PerspectiveScale": 100, "Exposure2012": 1], angleRecadrage: 0))
        for (cle, valeur) in [("PerspectiveUpright", 1.0), ("PerspectiveVertical", -10), ("PerspectiveHorizontal", 3), ("PerspectiveRotate", 0.5),
                              ("PerspectiveAspect", 5), ("PerspectiveScale", 105), ("PerspectiveX", 2), ("PerspectiveY", -2),
                              ("LensManualDistortionAmount", 4)] {
            XCTAssertFalse(Carnet.geometrieIntacte(reglages: [cle: .number(valeur)], angleRecadrage: 0), cle)
        }
        XCTAssertFalse(Carnet.geometrieIntacte(reglages: nil, angleRecadrage: 0.005))
        XCTAssertEqual(Set(Carnet.clesGeometrie).count, 9)
        XCTAssertTrue(Carnet.clesGeometrie.allSatisfy { DevelopCatalogue.setting($0) != nil }, "des réglages du catalogue")
        XCTAssertNil(Carnet.constatHorizon(tilt: 2, vertical: false, angleActuel: 0, reglages: ["PerspectiveUpright": 2]))
    }

    // MARK: view_photo

    func testViewPhotoNoteLaVueDUnePhotoPasEncoreRetouchee() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true, "constat": "vue"]
        repondreApercu(Self.sombre)
        let result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.carnets.count, 1)
        let params = try XCTUnwrap(fake.carnets.first)
        verifierPourLeModule(params)
        XCTAssertEqual(params["photo"]?.int, 7, "la photo mesurée, celle de la réponse")
        let cherches = params["vue"]?["cherches"]?.array?.compactMap(\.string) ?? []
        XCTAssertEqual(cherches, ["horizon_penche", "sous_exposition", "ciel_brule", "bruit", "flou"])
        let trouves = params["vue"]?["defauts"]?.array?.compactMap { $0["code"]?.string } ?? []
        XCTAssertEqual(trouves, ["sous_exposition", "flou"])
        let info = try JSONCoding.parse(result.text)
        let constats = info["constats_prise_de_vue"]?.array?.compactMap(\.string) ?? []
        XCTAssertEqual(constats.count, 2)
        XCTAssertTrue(constats[0].hasPrefix("sous-exposée : L* médian"), "\(constats)")
        XCTAssertTrue(constats[1].hasPrefix("floue"), "\(constats)")
        XCTAssertEqual(fake.commands, ["apercu"], "le carnet est noté à part, rien d'autre au module")
    }

    func testViewPhotoNeDitLesConstatsQueSiLeModuleLesANotes() throws {
        tools.noterAuCarnet = true
        repondreApercu(Self.sombre)
        // Refusée par le module (photo d'essai, case décochée, copie d'une photo retouchée) : rien dit.
        fake.replies["carnet"] = ["note": false, "motif": "essai", "raison": "Photo d'essai"]
        var result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.carnets.count, 1)
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
        // Une réponse sans « note » n'est pas une note.
        fake.replies["carnet"] = ["constat": "vue"]
        result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
        XCTAssertEqual(fake.carnets.count, 2)
        // Un module 1.2 (commande inconnue) : view_photo réussit quand même, sans constat.
        fake.errors["carnet"] = LightroomError.plugin("Commande inconnue : carnet")
        result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertNotNil(try JSONCoding.parse(result.text)["mesures"])
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
        XCTAssertEqual(fake.carnets.count, 3)
        // Note acceptée sans défaut trouvé : rien à dire.
        fake.errors["carnet"] = nil
        fake.replies["carnet"] = ["note": true]
        repondreApercu(TriTests.damierLocal(cx: 0.5, cy: 0.5, cote: 0.3))
        result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertEqual(fake.carnets.last?["vue"]?["defauts"]?.array?.count, 0)
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
    }

    func testViewPhotoNeNoteRienApresClaudeNiSansLeServeur() throws {
        fake.replies["carnet"] = ["note": true]
        // Le serveur des tests (et de --call, et de la recette) ne note pas au carnet.
        repondreApercu(Self.sombre)
        var info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
        XCTAssertTrue(fake.carnets.isEmpty)
        XCTAssertNil(info["constats_prise_de_vue"])

        tools.noterAuCarnet = true
        // Une photo déjà retouchée par Claude, ou un module qui ne dit pas les étapes.
        for etapes in [2, nil] as [Int?] {
            repondreApercu(Self.sombre, etapes: etapes)
            info = try JSONCoding.parse(tools.call(name: "view_photo", arguments: [:]).text)
            XCTAssertNil(info["constats_prise_de_vue"])
        }
        // Une photo sans identifiant dans la réponse.
        repondreApercu(Self.sombre, photo: ["fichier": "DSCF2402.RAF"])
        _ = tools.call(name: "view_photo", arguments: [:])
        // Un zoom ou un avant/après : pas une vue entière.
        repondreApercu(Self.sombre)
        _ = tools.call(name: "view_photo", arguments: ["region": ["x": 0, "y": 0, "width": 0.5, "height": 0.5]])
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            fake!.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(Self.sombre)), "chemin_avant": .string(TestSupport.previewFile(Self.sombre)),
                                       "photo": ["id": 7, "fichier": "DSCF2402.RAF"], "etapes_claude": ["nombre": 0]]
        }
        _ = tools.call(name: "view_photo", arguments: ["compare": "before_claude"])
        XCTAssertTrue(fake.carnets.isEmpty, "\(fake.carnets)")
    }

    /// Après « Je le fais » (ou des étapes défaites, puis des réglages faits à la main), la photo n'a
    /// pas d'étape de Claude mais n'est plus telle que prise : corrections_utilisateur le dit, et sa
    /// vue ne remplace pas celle d'avant. Une réponse sans corrections (null) note comme avant.
    func testViewPhotoNeNotePasUnePhotoChangeeALaMain() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true]
        let corrections: JSONValue = ["etape": "Claude · je le fais",
                                      "changements": [["cle": "Exposure2012", "claude": 0, "maintenant": 0.7]]]
        repondreApercu(Self.sombre, extra: ["corrections_utilisateur": corrections])
        let result = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(fake.carnets.isEmpty, "\(fake.carnets)")
        let info = try JSONCoding.parse(result.text)
        XCTAssertNil(info["constats_prise_de_vue"])
        XCTAssertNotNil(info["corrections_utilisateur"], "toujours dit à Claude")
        repondreApercu(Self.sombre, extra: ["corrections_utilisateur": .null])
        _ = tools.call(name: "view_photo", arguments: [:])
        XCTAssertEqual(fake.carnets.count, 1)
        // Calculs IA en attente au rendu : l'image ne montre pas l'état de la photo, rien n'est noté.
        repondreApercu(Self.sombre, extra: ["a_savoir": "Lightroom n'avait pas fini de calculer les réglages IA de cette photo."])
        let enAttente = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(enAttente.isError, enAttente.text)
        XCTAssertEqual(fake.carnets.count, 1, "\(fake.carnets)")
        XCTAssertNil(try JSONCoding.parse(enAttente.text)["constats_prise_de_vue"])
        // Le relevé le dit aussi.
        repondreApercu(Self.sombre, extra: ["corrections_utilisateur": corrections])
        let lignes = Carnet.releve(lightroom: fake, ids: [7], fichiers: [], lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertTrue(lignes.contains { $0.contains("changée à la main depuis Claude (view_photo ne la noterait pas)") }, "\(lignes)")
        XCTAssertFalse(lignes.contains { $0.contains("calculs IA en attente") }, "\(lignes)")
        repondreApercu(Self.sombre, extra: ["a_savoir": "Lightroom n'avait pas fini de calculer les réglages IA de cette photo."])
        let releveEnAttente = Carnet.releve(lightroom: fake, ids: [7], fichiers: [], lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertTrue(releveEnAttente.contains { $0.hasSuffix("étapes de Claude : aucune, mais calculs IA en attente au rendu (view_photo ne la noterait pas)") },
                      "\(releveEnAttente)")
    }

    func testViewPhotoNeChercheLHorizonQueSurUneGeometrieIntacte() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true]
        repondreApercu(Self.sombre, reglages: ["PerspectiveUpright": 1, "PerspectiveScale": 100])
        _ = tools.call(name: "view_photo", arguments: [:])
        repondreApercu(Self.sombre, angle: 1.4)
        _ = tools.call(name: "view_photo", arguments: [:])
        repondreApercu(Self.sombre, reglages: ["PerspectiveUpright": 0, "PerspectiveScale": 100, "LensManualDistortionAmount": 0])
        _ = tools.call(name: "view_photo", arguments: [:])
        let cherches = fake.carnets.map { $0["vue"]?["cherches"]?.array?.compactMap(\.string) ?? [] }
        XCTAssertEqual(cherches.map { $0.contains("horizon_penche") }, [false, false, true])
        fake.carnets.forEach { verifierPourLeModule($0) }
    }

    /// Le point de mise au point lu (Fujifilm) : la mise au point est cherchée, et mesurée avant le
    /// carré qu'af_point dessine.
    func testViewPhotoCompteLaMiseAuPointManqueeAvantLeCarre() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true]
        // Net en haut à gauche seulement ; l'appareil a fait la mise au point en bas à droite, sur un
        // sujet flou qui a de la texture (sur un gris uni, elle ne se jugerait pas : plus bas).
        repondreApercu(TriTests.damierLocalEtSujetFlou(cx: 0.25, cy: 0.3, cote: 0.2, fx: 0.75, fy: 0.7),
                       photo: ["id": 7, "fichier": "DSCF2402.RAF", "marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF2402.RAF",
                               "geometrie": ["largeur": 1200, "hauteur": 800, "orientation": "AB"]])
        tools.lecteurBoitier = LecteurBoitier(delai: 1) { _ in
            LectureBoitier(point: PointAF(x: 0.75, y: 0.7, avertissement: false, visages: nil))
        }
        let result = tools.call(name: "view_photo", arguments: ["af_point": true])
        XCTAssertFalse(result.isError, result.text)
        let params = try XCTUnwrap(fake.carnets.first)
        verifierPourLeModule(params)
        XCTAssertTrue(params["vue"]?["cherches"]?.array?.contains("mise_au_point") == true)
        XCTAssertEqual(params["vue"]?["defauts"]?.array?.compactMap { $0["code"]?.string }, ["mise_au_point"])
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["point_af"]?["carre"]?.string, "vert, sur l'image")
        XCTAssertTrue(info["constats_prise_de_vue"]?.array?.first?.string?.hasPrefix("mise au point manquée") == true)
        // La netteté au point, mesurée une fois, est la même dans point_af et dans le constat.
        XCTAssertEqual(info["point_af"]?["nettete"]?.double, params["vue"]?["defauts"]?.array?.first?["mesure"]?.double)
        XCTAssertNil(info["point_af"]?["mise_au_point"])

        // Le point sur un gris uni (un ciel, du sable lisse : relevé le 21 octobre 2026) : non jugée,
        // ni cherchée au carnet ; view_photo le dit dans point_af.
        let dejaNotees = fake.carnets.count
        repondreApercu(TriTests.damierLocal(cx: 0.25, cy: 0.3, cote: 0.2),
                       photo: ["id": 8, "fichier": "DSCF1595.RAF", "marque": "FUJIFILM", "chemin_original": "/Volumes/Photos/DSCF1595.RAF",
                               "geometrie": ["largeur": 1200, "hauteur": 800, "orientation": "AB"]])
        let uni = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(uni.isError, uni.text)
        XCTAssertEqual(fake.carnets.count, dejaNotees + 1)
        let vueUni = try XCTUnwrap(fake.carnets.last?["vue"])
        XCTAssertFalse(vueUni["cherches"]?.array?.contains("mise_au_point") == true, JSONCoding.line(vueUni))
        XCTAssertEqual(vueUni["defauts"]?.array?.count, 0)
        let infoUni = try JSONCoding.parse(uni.text)
        XCTAssertTrue(infoUni["point_af"]?["mise_au_point"]?.string?.hasPrefix("non jugée : zone sans texture") == true, uni.text)
        XCTAssertNil(infoUni["constats_prise_de_vue"])
    }

    // MARK: measure_angle et read_composition

    func repondreLigne(_ image: Data, angle: Double = 0, reglages: [String: JSONValue] = [:], extra: [String: JSONValue] = [:]) {
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            var objet: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(image)), "photo": ["id": 3, "fichier": "A.RAF"],
                                              "recadrage": ["angle": .number(angle), "recadree": .bool(angle != 0)], "reglages": .object(reglages)]
            for (cle, valeur) in extra { objet[cle] = valeur }
            fake!.replies["apercu"] = .object(objet)
        }
    }

    let horizon: [String: JSONValue] = ["photo_id": 3, "x1": 0.1, "y1": 0.5482, "x2": 0.9, "y2": 0.5056]

    func testMeasureAngleNoteUneHorizontalePencheeSurUneGeometrieIntacte() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true, "constat": "angle"]
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2))
        let result = tools.call(name: "measure_angle", arguments: horizon)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.compactMap(\.string), Carnet.clesGeometrie, "la géométrie demandée")
        let params = try XCTUnwrap(fake.carnets.first)
        verifierPourLeModule(params)
        XCTAssertEqual(params["photo"]?.int, 3)
        XCTAssertEqual(try XCTUnwrap(params["angle"]?["inclinaison"]?.double), 2, accuracy: 0.1)
        XCTAssertEqual(params["angle"]?["code"]?.string, "horizon_penche")
        XCTAssertEqual(params["angle"]?["source"]?.string, "measure_angle")
        let info = try JSONCoding.parse(result.text)
        XCTAssertTrue(info["constats_prise_de_vue"]?.array?.first?.string?.hasPrefix("horizon ou ligne penchée de 2") == true, result.text)

        // Rien pour une ligne presque droite, une photo déjà redressée ou passée par Upright.
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 0.2))
        _ = tools.call(name: "measure_angle", arguments: ["photo_id": 3, "x1": 0.1, "y1": 0.5513, "x2": 0.9, "y2": 0.5491])
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2), angle: 1)
        _ = tools.call(name: "measure_angle", arguments: horizon)
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2), reglages: ["PerspectiveUpright": 1])
        _ = tools.call(name: "measure_angle", arguments: horizon)
        XCTAssertEqual(fake.carnets.count, 1, "\(fake.carnets)")

        // Refusé par le module, ou module 1.2 : measure_angle réussit, sans constat.
        fake.replies["carnet"] = ["note": false, "motif": "geometrie"]
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2))
        var autre = tools.call(name: "measure_angle", arguments: horizon)
        XCTAssertNil(try JSONCoding.parse(autre.text)["constats_prise_de_vue"])
        fake.errors["carnet"] = LightroomError.plugin("Commande inconnue : carnet")
        autre = tools.call(name: "measure_angle", arguments: horizon)
        XCTAssertFalse(autre.isError, autre.text)
        XCTAssertNil(try JSONCoding.parse(autre.text)["constats_prise_de_vue"])
        XCTAssertEqual(fake.carnets.count, 3)
    }

    func testMeasureAngleSansLeServeurNeDemandeNiNeNoteRien() throws {
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2))
        let result = tools.call(name: "measure_angle", arguments: horizon)
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.count, 0)
        XCTAssertTrue(fake.carnets.isEmpty)
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
    }

    func testReadCompositionNoteLHorizonDeLImageEntiere() throws {
        tools.noterAuCarnet = true
        fake.replies["carnet"] = ["note": true, "constat": "angle"]
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2), extra: CompositionTests.entiere)
        var result = tools.call(name: "read_composition", arguments: ["photo_id": 3, "horizon": ["x1": 0.1, "y1": 0.5482, "x2": 0.9, "y2": 0.5056]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["entier"]?.bool, true)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.compactMap(\.string), Carnet.clesGeometrie)
        let params = try XCTUnwrap(fake.carnets.first)
        verifierPourLeModule(params)
        XCTAssertEqual(params["angle"]?["source"]?.string, "read_composition")
        XCTAssertEqual(try XCTUnwrap(params["angle"]?["inclinaison"]?.double), 2, accuracy: 0.1)
        XCTAssertNotNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])

        // Upright reste dans l'image entière : pas de constat.
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2), reglages: ["PerspectiveUpright": 3], extra: CompositionTests.entiere)
        result = tools.call(name: "read_composition", arguments: ["photo_id": 3, "horizon": ["x1": 0.1, "y1": 0.5482, "x2": 0.9, "y2": 0.5056]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertNil(try JSONCoding.parse(result.text)["constats_prise_de_vue"])
        // Sans horizon, ni clés de géométrie ni constat.
        repondreLigne(AnalyseTests.tiltedHorizon(degrees: 2), extra: CompositionTests.entiere)
        result = tools.call(name: "read_composition", arguments: ["photo_id": 3, "subject": ["x": 0.3, "y": 0.3, "width": 0.2, "height": 0.2]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.count, 0)
        XCTAssertEqual(fake.carnets.count, 1)
    }

    // MARK: export_journal avec notebook

    static let resume: JSONValue = [
        "le": 1_790_000_000, "vide": false, "photos": 12, "periode": "de juin à octobre 2026",
        "note": "Défauts de la prise de vue mesurés par Claude sur 12 photos, par mois de prise de vue (de juin à octobre 2026). Seules les photos montrées à Claude comptent, pas toute la sortie.",
        "titres": ["carnet": "Carnet de progrès", "defaut": "Défaut", "progresse": "Ce qui progresse", "recule": "Ce qui recule",
                   "a_travailler": "À travailler à la prochaine sortie"],
        "mois": [
            ["cle": "2026-09", "annee": 2026, "numero": 9, "nom": "septembre", "court": "sept.", "libelle": "septembre 2026", "photos": 5, "recent": true],
            ["cle": "2026-10", "annee": 2026, "numero": 10, "nom": "octobre", "court": "oct.", "libelle": "octobre 2026", "photos": 7, "recent": true],
        ],
        "defauts": [
            ["code": "sous_exposition", "libelle": "Photo sous-exposée", "domaine": "lumiere",
             "par_mois": [["n": 1, "sur": 5], ["n": 3, "sur": 7]], "n": 4, "sur": 12, "taux": 33],
            ["code": "mise_au_point", "libelle": "Mise au point à côté", "domaine": "nettete",
             "par_mois": [["n": 0, "sur": 0], ["n": 1, "sur": 2]], "n": 1, "sur": 2, "taux": 50],
        ],
        "progresse": [["code": "flou", "libelle": "Photo floue ou bougée", "texte": "Photo floue ou bougée : 40 % des photos de juin à août 2026, 8 % en septembre et octobre 2026."]],
        "recule": [],
        "a_travailler": [["code": "sous_exposition", "libelle": "Photo sous-exposée", "n": 4, "sur": 12, "taux": 33,
                          "texte": "Photo sous-exposée : 4 photos sur 12 (33 %) en septembre et octobre 2026.",
                          "conseil": "Monter la compensation.", "prise_de_vue": "À la prise de vue : Monter la compensation."]],
    ]

    func testExportJournalDonneLeCarnetDeProgres() throws {
        fake.replies["carnet"] = ["catalogue": "Photos.lrcat", "nombre": 12, "photos": [["photo": 1, "lecons": [:]]], "resume": Self.resume]
        let result = tools.call(name: "export_journal", arguments: ["notebook": true])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.carnets.map { $0["action"]?.string }, ["lire"])
        XCTAssertEqual(fake.carnets.first?["resume"]?.bool, true)
        XCTAssertTrue(fake.calls.isEmpty, "pas de commande journal : \(fake.commands)")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["catalogue"]?.string, "Photos.lrcat")
        XCTAssertNil(info["photos"], "ni les entrées ni leurs leçons")
        XCTAssertEqual(info["carnet"]?["photos"]?.int, 12)
        let markdown = try XCTUnwrap(info["markdown"]?.string)
        XCTAssertTrue(markdown.hasPrefix("# Carnet de progrès\n\nDéfauts de la prise de vue mesurés par Claude sur 12 photos"), markdown)
        XCTAssertTrue(markdown.contains("| Défaut | sept. | oct. |\n| --- | --- | --- |"), markdown)
        XCTAssertTrue(markdown.contains("| Photo sous-exposée | 1/5 | 3/7 |"), markdown)
        XCTAssertTrue(markdown.contains("| Mise au point à côté | — | 1/2 |"), markdown)
        XCTAssertTrue(markdown.contains("## Ce qui progresse\n\n- Photo floue ou bougée : 40 %"), markdown)
        XCTAssertFalse(markdown.contains("Ce qui recule"), "une section vide n'est pas écrite")
        XCTAssertTrue(markdown.contains("## À travailler à la prochaine sortie\n\n- Photo sous-exposée : 4 photos sur 12 (33 %) en septembre et octobre 2026. À la prise de vue : Monter la compensation."), markdown)
        XCTAssertNil(info["remarque"])
        // photo_ids n'y sert pas : dit.
        let avecPhotos = try JSONCoding.parse(tools.call(name: "export_journal", arguments: ["notebook": true, "photo_ids": [4]]).text)
        XCTAssertNotNil(avecPhotos["remarque"]?.string)
        let avecSelection = try JSONCoding.parse(tools.call(name: "export_journal", arguments: ["notebook": true, "selection": true]).text)
        XCTAssertNotNil(avecSelection["remarque"]?.string)
        // selection = false ne vise rien de plus que la photo active : rien à dire.
        let sansSelection = try JSONCoding.parse(tools.call(name: "export_journal", arguments: ["notebook": true, "selection": false]).text)
        XCTAssertNil(sansSelection["remarque"])
    }

    func testExportJournalEcritLeCarnetSansEcraser() throws {
        fake.replies["carnet"] = ["catalogue": "Photos.lrcat", "nombre": 12, "photos": [], "resume": Self.resume]
        let dossier = TestSupport.temporaryDirectory()
        let fichier = dossier.appendingPathComponent("Carnet.md")
        let premier = try JSONCoding.parse(tools.call(name: "export_journal", arguments: ["notebook": true, "save_to": .string(fichier.path)]).text)
        XCTAssertEqual(premier["fichier"]?.string, fichier.path)
        let texte = try String(contentsOf: fichier, encoding: .utf8)
        XCTAssertEqual(texte, premier["markdown"]?.string)
        let second = try JSONCoding.parse(tools.call(name: "export_journal", arguments: ["notebook": true, "save_to": .string(fichier.path)]).text)
        XCTAssertEqual(second["fichier"]?.string, dossier.appendingPathComponent("Carnet 2.md").path)
        XCTAssertEqual(try String(contentsOf: fichier, encoding: .utf8), texte, "le premier fichier est intact")
    }

    func testExportJournalSansNotebookResteLeJournal() throws {
        fake.replies["journal"] = ["photos": []]
        let result = tools.call(name: "export_journal", arguments: ["notebook": false])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["journal"])
        XCTAssertTrue(fake.carnets.isEmpty)
        XCTAssertTrue(try JSONCoding.parse(result.text)["markdown"]?.string?.hasPrefix("# Journal des retouches de Claude") == true)
    }

    func testExportJournalDitQuUnModule12NeConnaitPasLeCarnet() {
        fake.errors["carnet"] = LightroomError.plugin("Commande inconnue : carnet")
        var result = tools.call(name: "export_journal", arguments: ["notebook": true])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("ne connaît pas encore le carnet de progrès"), result.text)
        fake.errors["carnet"] = nil
        fake.replies["carnet"] = ["catalogue": "Photos.lrcat", "nombre": 0, "photos": []]
        result = tools.call(name: "export_journal", arguments: ["notebook": true])
        XCTAssertTrue(result.isError, "sans résumé")
    }

    func testLeCarnetVideOuSurDeuxAnnees() {
        let vide: JSONValue = ["vide": true, "photos": 0, "mois": [], "defauts": [], "progresse": [], "recule": [], "a_travailler": [],
                               "titres": ["carnet": "Carnet de progrès"], "note": "Le carnet se remplit tout seul : …"]
        XCTAssertEqual(Carnet.markdown(vide), "# Carnet de progrès\n\nLe carnet se remplit tout seul : …")

        let deuxAnnees: JSONValue = [
            "vide": false, "photos": 3, "note": "Note.", "remarque": "Seulement 3 photos : le carnet dira plus après quelques sorties.",
            "aucune_tendance": "Pas encore de tendance.", "rien_a_travailler": "Aucun défaut ne revient.",
            "titres": ["carnet": "Carnet de progrès", "defaut": "Défaut", "progresse": "Ce qui progresse",
                       "a_travailler": "À travailler à la prochaine sortie"],
            "mois": [["cle": "2025-12", "annee": 2025, "court": "déc."], ["cle": "2026-01", "annee": 2026, "court": "janv."]],
            "defauts": [["libelle": "Bruit | fort", "par_mois": [["n": 1, "sur": 2], ["n": 0, "sur": 1]]]],
            "progresse": [], "recule": [], "a_travailler": [],
        ]
        XCTAssertEqual(Carnet.markdown(deuxAnnees), """
        # Carnet de progrès

        Note.

        Seulement 3 photos : le carnet dira plus après quelques sorties.

        | Défaut | déc. 2025 | janv. 2026 |
        | --- | --- | --- |
        | Bruit \\| fort | 1/2 | 0/1 |

        ## Ce qui progresse

        Pas encore de tendance.

        ## À travailler à la prochaine sortie

        Aucun défaut ne revient.
        """)
    }

    /// Ce qui recule seulement : sa section, sans « pas encore de tendance » (il y en a une), même
    /// si le résumé le portait.
    func testCeQuiReculeSansCeQuiProgresse() {
        var resume = Self.resume.object ?? [:]
        resume["progresse"] = []
        resume["recule"] = [["code": "bruit", "texte": "Bruit fort (ISO élevé) : 10 % des photos de mai à juillet 2026, 40 % en août et septembre 2026."]]
        resume["aucune_tendance"] = "Pas encore de tendance."
        let markdown = Carnet.markdown(.object(resume))
        XCTAssertTrue(markdown.contains("## Ce qui recule\n\n- Bruit fort (ISO élevé) : 10 %"), markdown)
        XCTAssertFalse(markdown.contains("## Ce qui progresse"), markdown)
        XCTAssertFalse(markdown.contains("Pas encore de tendance."), markdown)
    }

    func testLaDescriptionDExportJournalResteCourte() throws {
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "export_journal" })
        let description = try XCTUnwrap(definition["description"]?.string)
        let notebook = try XCTUnwrap(definition["inputSchema"]?["properties"]?["notebook"]?["description"]?.string)
        XCTAssertEqual(definition["inputSchema"]?["properties"]?["notebook"]?["type"]?.string, "boolean")
        XCTAssertLessThanOrEqual(description.count + notebook.count, 450, "\(description.count) + \(notebook.count)")
        XCTAssertTrue(description.contains("carnet de progrès"))
        XCTAssertEqual(ToolHandler.annotations("export_journal")["readOnlyHint"]?.bool, true)
    }

    // MARK: Relevé (--constats)

    func testLeReleveNeNoteRienAuCarnet() throws {
        repondreApercu(Self.sombre, reglages: ["PerspectiveUpright": 0])
        let fichier = TestSupport.temporaryDirectory().appendingPathComponent("ciel.jpg")
        try TestSupport.jpegPixels(width: 600, height: 400) { _, y in y < 60 ? (255, 255, 255) : (110, 120, 130) }.write(to: fichier)
        let lignes = Carnet.releve(lightroom: fake, ids: [7, 8], fichiers: [fichier],
                                   lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertTrue(fake.carnets.isEmpty, "lecture seule : rien n'est noté")
        let apercu = try XCTUnwrap(fake.calls.first { $0.command == "apercu" })
        XCTAssertEqual(apercu.params["point_af"]?.bool, true)
        XCTAssertEqual(apercu.params["taille"]?.int, 1344)
        XCTAssertEqual(apercu.params["cles"]?.array?.compactMap(\.string), Carnet.clesGeometrie)
        let texte = lignes.joined(separator: "\n")
        XCTAssertTrue(texte.contains("■ DSCF2402.RAF (id 7)"), texte)
        XCTAssertTrue(texte.contains("étapes de Claude : aucune (view_photo la noterait)"), texte)
        XCTAssertTrue(texte.contains("Retenus : sous-exposée"), texte)
        XCTAssertTrue(texte.contains("■ ciel.jpg"), texte)
        XCTAssertTrue(texte.contains("Retenus : ciel ou haut de l'image brûlé :"), texte)
        XCTAssertTrue(lignes.contains { $0.hasPrefix("ciel.jpg\t") }, "une ligne de résumé par photo")
        XCTAssertEqual(lignes.filter { $0.hasPrefix("✘") }.count, 0)
        // Une photo que le module ne rend pas : une ligne en échec, les autres continuent.
        fake.onSend = nil
        fake.errors["apercu"] = LightroomError.plugin("Photo introuvable : 9.")
        let echec = Carnet.releve(lightroom: fake, ids: [9], fichiers: [fichier], lecteur: LecteurBoitier(delai: 1) { _ in nil })
        XCTAssertTrue(echec.contains { $0.hasPrefix("✘ 9 : Photo introuvable") }, "\(echec)")
        XCTAssertTrue(echec.contains { $0.hasPrefix("■ ciel.jpg") })
    }
}
