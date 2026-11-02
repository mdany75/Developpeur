import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Étalonnage d'après une photo de référence (match_look, 1.6) : signature, traduction, passes
/// mesurées sur un faux rendu (jamais le vrai Lightroom), peau, relevé.
final class ReferenceTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
        tools.detecterVisages = { _ in [] }
    }

    // MARK: Images de synthèse en L*a*b*

    /// sRGB 8 bits d'un L*a*b* (D65), borné.
    static func srgb(_ l: Double, _ a: Double, _ b: Double) -> (UInt8, UInt8, UInt8) {
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        func inv(_ t: Double) -> Double { t * t * t > 0.008856 ? t * t * t : (t - 16.0 / 116) / 7.787 }
        let x = inv(fx) * 0.95047, y = inv(fy), z = inv(fz) * 1.08883
        let rl = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let gl = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        func g(_ c: Double) -> UInt8 {
            let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(max(c, 0), 1 / 2.4) - 0.055
            return UInt8(min(max(v * 255, 0), 255).rounded())
        }
        return (g(rl), g(gl), g(bl))
    }

    /// Un dégradé de L* 12 à 92 de gauche à droite, chaque zone tonale décalée en a*b*.
    static func degrade(ombres: Reference.Vecteur = .zero, moyens: Reference.Vecteur = .zero, hautes: Reference.Vecteur = .zero,
                        exposition: Double = 0, bandes: Int = 0, peau: CGRect? = nil, largeur: Int = 300, hauteur: Int = 200)
        -> (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        { x, y in
            if y < bandes || y >= hauteur - bandes { return (0, 0, 0) }
            let l = min(max(12 + 80 * Double(x) / Double(largeur - 1) + exposition, 0), 100)
            let decalage = l < 40 ? ombres : (l < 70 ? moyens : hautes)
            if let peau, peau.contains(CGPoint(x: (Double(x) + 0.5) / Double(largeur), y: (Double(y) + 0.5) / Double(hauteur))) {
                // Une peau (L* 62), décalée comme les tons moyens.
                return srgb(62, 14 + moyens.a, 18 + moyens.b)
            }
            return srgb(l, decalage.a, decalage.b)
        }
    }

    static func signature(_ couleur: (Int, Int) -> (UInt8, UInt8, UInt8), visages: [CGRect] = []) -> Reference.Signature {
        Reference.lire(TestSupport.imagePixels(couleur), visages: visages)!
    }

    // MARK: Signature

    func testSignatureLitLaCouleurReelleDeChaqueZone() throws {
        let s = Self.signature(Self.degrade(ombres: .init(a: -6, b: -8), hautes: .init(a: 5, b: 12)))
        let ombres = try XCTUnwrap(s.zones[0]), moyens = try XCTUnwrap(s.zones[1]), hautes = try XCTUnwrap(s.zones[2])
        XCTAssertEqual(ombres.a, -6, accuracy: 1)
        XCTAssertEqual(ombres.b, -8, accuracy: 1)
        XCTAssertEqual(moyens.a, 0, accuracy: 1)
        XCTAssertEqual(hautes.b, 12, accuracy: 1)
        XCTAssertGreaterThan(s.centiles[95] ?? 0, s.centiles[5] ?? 100)
    }

    /// Critique du plan (bloquant) : la mesure d'Eclairage ne lit que les tons presque neutres (C* <
    /// 12) ; des ombres de chroma 15 doivent donner leur couleur, pas « non lue ».
    func testDesOmbresDeChroma15DonnentLeurCouleur() throws {
        let s = Self.signature(Self.degrade(ombres: .init(a: -9, b: -12)))
        let ombres = try XCTUnwrap(s.zones[0], "des ombres sarcelle de chroma 15 se lisent")
        XCTAssertEqual(hypot(ombres.a, ombres.b), 15, accuracy: 1.5)
        XCTAssertGreaterThan(hypot(ombres.a, ombres.b), Eclairage.chromaMax)
    }

    func testLesCouleursVivesDesObjetsNeGuidentPasLaZone() throws {
        // La moitié haute : un vert vif (C* ≈ 57) ; le bas : le dégradé gris.
        let gris = Self.degrade()
        let s = Self.signature { x, y in y < 100 ? Self.srgb(55, -45, 35) : gris(x, y) }
        let moyens = try XCTUnwrap(s.zones[1])
        XCTAssertEqual(moyens.a, 0, accuracy: 1, "le vert vif reste hors de la couleur de la zone")
        XCTAssertGreaterThan(s.bandes[3], 80, "mais compte dans la répartition par bande (vert)")
    }

    func testLesBandesNoiresDUnPhotogrammeSontEcartees() {
        let avec = Self.signature(Self.degrade(bandes: 25))
        let sans = Self.signature(Self.degrade())
        XCTAssertTrue(avec.remarques.contains { $0.hasPrefix("bandes noires") })
        XCTAssertEqual(avec.centiles[5] ?? 0, sans.centiles[5] ?? 0, accuracy: 1.5, "les bandes ne tirent pas les ombres vers le noir")
        XCTAssertFalse(sans.remarques.contains { $0.hasPrefix("bandes noires") })
    }

    func testLesVisagesSontEcartesDeLaZone() throws {
        let visage = CGRect(x: 0.4, y: 0.1, width: 0.3, height: 0.8)
        let couleur = Self.degrade(peau: visage)
        let avec = try XCTUnwrap(Self.signature(couleur).zones[1])
        let sans = try XCTUnwrap(Self.signature(couleur, visages: [visage]).zones[1])
        XCTAssertGreaterThan(avec.b, 2, "la peau tire les tons moyens vers le chaud")
        XCTAssertEqual(sans.b, 0, accuracy: 1, "visage écarté")
    }

    // MARK: Traduction

    func ecart(_ zones: [Reference.Vecteur?], exposition: Double = 0, contraste: Double = 0, chroma: Double = 0, scenes: Double = 0) -> Reference.Ecart {
        Reference.Ecart(exposition: exposition, contraste: contraste, zones: zones, chroma: chroma, scenes: scenes)
    }
    let neutre = Reference.Etat(reglages: [:], raw: false)

    func testLesTeintesDeLightroomEtLesAnglesLabSeRepondent() {
        for teinte in stride(from: 0.0, to: 360, by: 15) {
            XCTAssertEqual(Reference.teinteLightroom(angle: Reference.angleLab(teinte: teinte)), teinte, accuracy: 0.01, "\(teinte)")
        }
        XCTAssertEqual(Reference.angleLab(teinte: 0), 40, accuracy: 0.01)
    }

    func testUnEcartNulNeDonneAucunReglage() {
        let (reglages, _) = Reference.traduire(ecart([.zero, .zero, .zero]), etat: neutre, options: .init(), pentes: .init())
        XCTAssertTrue(reglages.isEmpty)
    }

    func testOmbresFroidesEtHautesLumieresChaudes() throws {
        let (reglages, _) = Reference.traduire(ecart([.init(a: -4, b: -6), .zero, .init(a: 4, b: 6)]), etat: neutre, options: .init(), pentes: .init())
        let ombres = try XCTUnwrap(reglages["SplitToningShadowHue"]), hautes = try XCTUnwrap(reglages["SplitToningHighlightHue"])
        XCTAssertTrue((150...260).contains(ombres), "ombres bleu-vert : \(ombres)")
        XCTAssertTrue((0...70).contains(hautes), "hautes lumières orange : \(hautes)")
        // 0,6 × 7,2 / 0,2 ≈ 22.
        XCTAssertEqual(reglages["SplitToningShadowSaturation"] ?? 0, 22, accuracy: 1)
        XCTAssertNil(reglages["ColorGradeMidtoneSat"], "tons moyens au milieu : rien")
        XCTAssertNil(reglages["ColorGradeShadowHue"], "la clé que Lightroom refuse n'est jamais écrite")
        let (fort, _) = Reference.traduire(ecart([.init(a: -2, b: -3), .zero, .init(a: 2, b: 3)]), etat: neutre, options: { var o = Reference.Options(); o.force = 1; return o }(), pentes: .init())
        XCTAssertEqual(fort["SplitToningShadowSaturation"] ?? 0, 18, accuracy: 1, "strength 1 : 3,6 / 0,2")
        // Écriture absolue : la valeur finale part de l'étalonnage déjà posé (même teinte : la saturation s'ajoute).
        let posee = Reference.Etat(reglages: ["SplitToningShadowHue": ombres, "SplitToningShadowSaturation": 10], raw: false)
        let (ensuite, _) = Reference.traduire(ecart([.init(a: -4, b: -6), .zero, .init(a: 4, b: 6)]), etat: posee, options: .init(), pentes: .init())
        XCTAssertEqual(ensuite["SplitToningShadowSaturation"] ?? 0, 32 > Reference.saturationMax ? Reference.saturationMax : 32, accuracy: 1)
    }

    /// Critique du plan (important) : sans white_balance, un écart égal dans les trois zones (une
    /// dominante de toute l'image) ne donne aucun réglage.
    func testLaPartCommuneEstLaBalanceCopieeSeulementSurDemande() {
        let commun = ecart([.init(a: 3, b: 5), .init(a: 3, b: 5), .init(a: 3, b: 5)])
        XCTAssertTrue(Reference.traduire(commun, etat: neutre, options: .init(), pentes: .init()).reglages.isEmpty)
        var options = Reference.Options()
        options.balance = true
        let (balance, _) = Reference.traduire(commun, etat: Reference.Etat(reglages: ["Temperature": 5000, "Tint": 0], raw: true), options: options, pentes: .init())
        XCTAssertGreaterThan(balance["Temperature"] ?? 0, 5000, "plus jaune : réchauffer")
        XCTAssertNil(balance["ColorGradeGlobalHue"], "jamais par l'étalonnage global")
        XCTAssertNil(Reference.distance(ecart([.init(a: 3, b: 5), nil, nil]), balance: false), "une seule zone : pas de partage")
    }

    func testVibranceBorneeEtJamaisSaturation() {
        let etat = Reference.Etat(reglages: ["Vibrance": 25], raw: false)
        let (reglages, limites) = Reference.traduire(ecart([nil, nil, nil], chroma: 20), etat: etat, options: .init(), pentes: .init())
        XCTAssertEqual(reglages["Vibrance"], 30, "le plafond de dose")
        XCTAssertTrue(limites.contains { $0.contains("plafond de dose") })
        XCTAssertNil(reglages["Saturation"])
        var forte = Reference.Options()
        forte.doseForte = true
        XCTAssertEqual(Reference.traduire(ecart([nil, nil, nil], chroma: 20), etat: etat, options: forte, pentes: .init()).reglages["Vibrance"], 45,
                       "20 au plus par passe, au-delà du plafond sur demande")
        let (scenes, notes) = Reference.traduire(ecart([nil, nil, nil], chroma: 20, scenes: 80), etat: etat, options: .init(), pentes: .init())
        XCTAssertNil(scenes["Vibrance"], "scènes différentes : la saturation ne se copie pas")
        XCTAssertTrue(notes.contains { $0.contains("scènes diffèrent") })
    }

    func testSaturationDeLEtalonnageBornee() {
        let grand = ecart([.init(a: -20, b: -20), .zero, .init(a: 20, b: 20)])
        let (reglages, limites) = Reference.traduire(grand, etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(reglages["SplitToningShadowSaturation"], Reference.saturationMax)
        XCTAssertTrue(limites.contains { $0.contains("arrêtée à 25") })
        var forte = Reference.Options()
        forte.doseForte = true
        XCTAssertEqual(Reference.traduire(grand, etat: neutre, options: forte, pentes: .init()).reglages["SplitToningShadowSaturation"], Reference.saturationMaxForte)
    }

    func testTonsParExpositionEtContrasteSeulement() {
        let (reglages, _) = Reference.traduire(ecart([nil, nil, nil], exposition: 0.5, contraste: 5), etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(reglages["Exposure2012"] ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(reglages["Contrast2012"] ?? 0, 16, accuracy: 1, "5,3 × 5 × 0,6")
        let (grand, limites) = Reference.traduire(ecart([nil, nil, nil], contraste: 20), etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(grand["Contrast2012"], ToolHandler.maxContrastePasse)
        XCTAssertTrue(limites.contains { $0.hasPrefix("Contraste changé de 30 au plus") })
        XCTAssertEqual(Set(reglages.keys), ["Exposure2012", "Contrast2012"], "ni courbe ni autre réglage pour les tons")
    }

    // MARK: L'outil, sur un faux rendu

    /// Le faux module : la photo 1 (référence) a des ombres sarcelle et des hautes lumières orange ;
    /// la photo 2, grise, se rend d'après ses réglages, avec un gain réel de `gainReel` a*b* par point
    /// de saturation (le modèle de match_look en suppose 0,2 : la passe 2 corrige).
    func brancherRendu(gainReel: Double = 0.3, reference: [Reference.Vecteur] = [.init(a: -3, b: -4), .zero, .init(a: 3, b: 4)],
                       peau: CGRect? = nil) -> () -> [String: Double] {
        var etat: [String: Double] = [:]
        let verrou = NSLock()
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "apercu", let id = params["photo"]?.int {
                verrou.lock(); let reglages = etat; verrou.unlock()
                let couleur: (Int, Int) -> (UInt8, UInt8, UInt8)
                if id == 1 {
                    couleur = Self.degrade(ombres: reference[0], moyens: reference[1], hautes: reference[2], peau: peau)
                } else {
                    func v(_ z: Int) -> Reference.Vecteur {
                        let cles = Reference.clesZones[z]
                        return Reference.vecteur(teinte: reglages[cles.teinte] ?? 0, saturation: reglages[cles.saturation] ?? 0, gain: gainReel)
                    }
                    couleur = Self.degrade(ombres: v(0), moyens: v(1), hautes: v(2), exposition: 10 * (reglages["Exposure2012"] ?? 0), peau: peau)
                }
                var lus: [String: JSONValue] = [:]
                for (cle, valeur) in reglages { lus[cle] = .number(valeur) }
                fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpegPixels(couleur))),
                                          "photo": ["id": .number(Double(id)), "fichier": .string("P\(id).RAF")],
                                          "echelle_temperature": "relative (JPEG : −100 à +100)", "reglages": id == 2 ? .object(lus) : [:]]
            }
            if command == "appliquer" {
                XCTAssertEqual(params["relatif"]?.bool, false, "valeurs finales, en absolu")
                verrou.lock()
                for (cle, valeur) in params["reglages"]?.object ?? [:] { etat[cle] = valeur.double }
                verrou.unlock()
                fake.replies["appliquer"] = ["resultats": [["photo": ["id": 2], "etape_id": .null]]]
            }
        }
        return { verrou.lock(); defer { verrou.unlock() }; return etat }
    }

    func appel(_ arguments: [String: JSONValue]) throws -> JSONValue {
        let resultat = tools.call(name: "match_look", arguments: arguments)
        XCTAssertFalse(resultat.isError, resultat.text)
        return try JSONCoding.parse(resultat.text)
    }

    func testSansConfirmLePlanSeulement() throws {
        _ = brancherRendu()
        let plan = try appel(["reference_id": 1, "photo_id": 2])
        XCTAssertFalse(fake.commands.contains("appliquer"), "sans accord : rien d'écrit")
        let ligne = try XCTUnwrap(plan["photos"]?.array?.first)
        XCTAssertNotNil(ligne["reglages_proposes"]?["SplitToningShadowHue"])
        XCTAssertNotNil(ligne["ecart_avant"]?["ombres"]?["a"])
        XCTAssertNotNil(plan["rien_n_est_applique"])
        XCTAssertNotNil(plan["reference"]?["signature"]?["ombres"])
        XCTAssertEqual(fake.calls.first?.params["cles"]?.array?.contains("SplitToningShadowSaturation"), true, "les réglages actuels sont lus")
    }

    func testDeuxPassesMesureesEnEcritureAbsolueUneEtapeChacune() throws {
        let etat = brancherRendu()
        let fait = try appel(["reference_id": 1, "photo_ids": [1, 2], "confirm": true, "step_name": "rendu du lac", "strength": 1])
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2, "une seconde passe sur l'écart restant (le gain réel diffère du modèle)")
        XCTAssertEqual(ecritures.map { $0.params["etape"]?.string }, ["rendu du lac : passe 1", "rendu du lac : passe 2"])
        XCTAssertTrue(ecritures.allSatisfy { $0.params["sans_avant_apres"]?.bool == true && $0.params["confirme"]?.bool == true })
        XCTAssertEqual(ecritures[0].params["photos"]?.array?.first?.int, 2, "la référence est écartée")
        let ligne = try XCTUnwrap(fait["photos"]?.array?.first)
        XCTAssertEqual(ligne["etapes"]?.array?.count, 2)
        let avant = try XCTUnwrap(ligne["ecart_avant"]?["distance"]?.double), apres = try XCTUnwrap(ligne["ecart_apres"]?["distance"]?.double)
        XCTAssertLessThan(apres, avant / 3, "la photo s'est rapprochée de la référence")
        XCTAssertGreaterThan(ligne["rapproche_pct"]?.double ?? 0, 60)
        // Le gain réel (0,3) est plus fort que le modèle (0,2) : la passe 2 baisse la saturation.
        let s1 = try XCTUnwrap(ecritures[0].params["reglages"]?["SplitToningShadowSaturation"]?.double)
        XCTAssertLessThan(etat()["SplitToningShadowSaturation"] ?? 99, s1)
    }

    func testUnePhotoDejaProcheNestPasTouchee() throws {
        _ = brancherRendu(reference: [.zero, .zero, .zero])
        let fait = try appel(["reference_id": 1, "photo_id": 2, "confirm": true])
        XCTAssertFalse(fake.commands.contains("appliquer"))
        XCTAssertNotNil(fait["photos"]?.array?.first?["reglages"]?.string)
    }

    /// La peau protégée : la passe 1 déplace la peau de plus de `Teint.ecartVisible` ; la passe 2
    /// rend la moitié du changement des tons moyens, et le résultat le fait vérifier.
    func testLaPeauQuiBougeReduitLesTonsMoyens() throws {
        let visage = CGRect(x: 0.4, y: 0.2, width: 0.3, height: 0.6)
        tools.detecterVisages = { _ in [visage] }
        _ = brancherRendu(gainReel: 0.3, reference: [.zero, .init(a: 12, b: -15), .zero], peau: visage)
        let fait = try appel(["reference_id": 1, "photo_id": 2, "confirm": true, "strength": 1, "adjust": ["color_grading"]])
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2)
        let s1 = try XCTUnwrap(ecritures[0].params["reglages"]?["ColorGradeMidtoneSat"]?.double)
        let s2 = try XCTUnwrap(ecritures[1].params["reglages"]?["ColorGradeMidtoneSat"]?.double)
        XCTAssertEqual(s2, (s1 / 2).rounded(), accuracy: 1, "la moitié du changement")
        let ligne = try XCTUnwrap(fait["photos"]?.array?.first)
        XCTAssertNotNil(ligne["teint"]?["a_verifier"])
        XCTAssertNotNil(fait["a_verifier"])
        // Sans protect_skin : ni visages ni témoin.
        fake.calls = []
        _ = brancherRendu(gainReel: 0.3, reference: [.zero, .init(a: 12, b: -15), .zero], peau: visage)
        let libre = try appel(["reference_id": 1, "photo_id": 2, "adjust": ["color_grading"], "protect_skin": false])
        XCTAssertNil(libre["photos"]?.array?.first?["teint"])
    }

    func testArgumentsRefuses() {
        _ = brancherRendu()
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["photo_id": 2]).isError, "reference_id exigé")
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["reference_id": 1, "photo_id": 2, "adjust": ["curve"]]).isError)
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["reference_id": 1, "photo_id": 2, "strength": 2]).isError)
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["reference_id": 1, "photo_id": 1]).isError, "la référence elle-même")
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["reference_id": 1, "reference_file": "/tmp/x.jpg"]).isError,
                      "pas de fichier externe dans la 1.6")
        XCTAssertFalse(fake.commands.contains("appliquer"))
    }

    func testDescriptionEssentielEnTete() throws {
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "match_look" })
        let description = try XCTUnwrap(definition["description"]?.string)
        XCTAssertTrue(description.hasPrefix("Donne à une photo le rendu d'une photo de référence du catalogue (reference_id)"))
        XCTAssertLessThanOrEqual(description.utf16.count, 1400)
        XCTAssertEqual(definition["annotations"]?["readOnlyHint"]?.bool, false)
        let serie = try XCTUnwrap(tools.definitions.first { $0["name"]?.string == "match_series" }?["description"]?.string)
        XCTAssertTrue(serie.contains("match_look"))
    }

    // MARK: Relevé (--etalonnage)

    func testLeReleveEnLectureSeuleEtLeBalayageSurUneCopieSeulement() throws {
        var copie = false
        fake.onSend = { [unowned fake] command, _ in
            guard let fake else { return }
            switch command {
            case "apercu", "essayer":
                fake.replies[command] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpegPixels(Self.degrade()))),
                                         "photo": ["id": 5, "fichier": "P5.RAF"]]
            case "reglages":
                fake.replies["reglages"] = ["photo": ["id": 5, "copie_virtuelle": .bool(copie)], "reglages": [:]]
            default: break
            }
        }
        let lecture = Reference.releve(lightroom: fake, ids: [5], fichiers: [], balayage: false, visages: { _ in [] })
        XCTAssertEqual(lecture.filter { $0.hasPrefix("  C* < ") }.count, Reference.bornesReleve.count)
        XCTAssertFalse(fake.commands.contains("essayer"), "lecture seule")
        let refus = Reference.releve(lightroom: fake, ids: [5], fichiers: [], balayage: true, visages: { _ in [] })
        XCTAssertTrue(refus.contains { $0.hasPrefix("✘ 5 : balayage seulement sur une copie virtuelle") })
        XCTAssertFalse(fake.commands.contains("essayer"), "un original : aucun rendu")
        copie = true
        let lignes = Reference.releve(lightroom: fake, ids: [5], fichiers: [], balayage: true, visages: { _ in [] })
        XCTAssertEqual(fake.commands.filter { $0 == "essayer" }.count, Reference.balayage.count)
        XCTAssertEqual(Reference.balayage.count, 29)
        XCTAssertTrue(lignes.contains { $0.hasPrefix("Résumé de 5") })
    }
}
