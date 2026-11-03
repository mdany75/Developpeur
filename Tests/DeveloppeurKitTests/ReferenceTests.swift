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
                // Une peau pâle (L* 62, C* 16 : sous chromaZone, elle tirerait la zone), décalée comme les tons moyens.
                return srgb(62, 10 + moyens.a, 13 + moyens.b)
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

    /// Revue (important) : une ombre sarcelle profonde a son rouge à 0 bien avant L* 20 ; écarter
    /// les pixels dont une composante est au noir ferait lire la couleur des ombres sur leur seule
    /// partie claire. Ici la teinte monte vers le noir (la plus forte à L* 8) : la médiane lue est
    /// celle de toute la zone.
    func testLesOmbresProfondesTeinteesComptent() throws {
        let s = Self.signature { x, _ in
            let l = 8 + 84 * Double(x) / 299
            guard l < 40 else { return Self.srgb(l, 0, 0) }
            let k = (40 - l) / 32
            return Self.srgb(l, -10 * k, -13 * k)
        }
        let ombres = try XCTUnwrap(s.zones[0])
        // Médiane de k sur la zone : 0,5.
        XCTAssertEqual(ombres.a, -5, accuracy: 0.5, "les ombres profondes, où la teinte est la plus forte, comptent")
        XCTAssertEqual(ombres.b, -6.5, accuracy: 0.5)
        // Le noir bouché (les trois composantes à 0) reste écarté.
        let noir = Self.signature { x, y in y < 100 ? (0, 0, 0) : Self.srgb(8 + 84 * Double(x) / 299, 0, 0) }
        XCTAssertEqual(noir.zones[0]?.pixels ?? 0, Self.signature { x, _ in Self.srgb(8 + 84 * Double(x) / 299, 0, 0) }.zones[0].map { $0.pixels / 2 } ?? -1,
                       accuracy: 2)
    }

    /// Revue (important) : l'étalonnage de la référence teinte les gris et fait monter la chroma
    /// médiane de toute l'image ; la saturation se lit sur les seuls pixels colorés, sinon la
    /// Vibrance copierait une seconde fois ce que l'étalonnage copie déjà.
    func testLEtalonnageDeLaReferenceNeDonnePasDeVibrance() {
        let grise = Self.degrade(), etalonnee = Self.degrade(ombres: .init(a: -3, b: -4), hautes: .init(a: 3, b: 4))
        let neutre = Reference.Etat(reglages: [:], raw: false)
        // Sans couleurs vives : la saturation ne se compare pas.
        let seule = Reference.ecart(photo: Self.signature(grise), reference: Self.signature(etalonnee))
        XCTAssertNil(seule.chroma)
        XCTAssertNil(Reference.traduire(seule, etat: neutre, options: .init(), pentes: .init()).reglages["Vibrance"])
        // Avec un même vert vif sur les deux : l'étalonnage seul ne donne aucune Vibrance.
        func avecVert(_ fond: @escaping (Int, Int) -> (UInt8, UInt8, UInt8), chroma: Double) -> (Int, Int) -> (UInt8, UInt8, UInt8) {
            { x, y in y < 100 ? Self.srgb(55, -chroma * 0.79, chroma * 0.61) : fond(x, y) }
        }
        let meme = Reference.ecart(photo: Self.signature(avecVert(grise, chroma: 57)), reference: Self.signature(avecVert(etalonnee, chroma: 57)))
        XCTAssertEqual(meme.chroma ?? 99, 0, accuracy: 0.5)
        let (reglages, _) = Reference.traduire(meme, etat: neutre, options: .init(), pentes: .init())
        XCTAssertNil(reglages["Vibrance"], "la référence n'a que de l'étalonnage")
        XCTAssertNotNil(reglages["SplitToningShadowHue"])
        // Un vert plus vif sur la référence : la Vibrance monte.
        let plus = Reference.ecart(photo: Self.signature(avecVert(grise, chroma: 40)), reference: Self.signature(avecVert(etalonnee, chroma: 57)))
        XCTAssertGreaterThan(Reference.traduire(plus, etat: neutre, options: .init(), pentes: .init()).reglages["Vibrance"] ?? 0, 0)
    }

    func testLesCouleursVivesDesObjetsNeGuidentPasLaZone() throws {
        // La moitié haute : un vert vif (C* ≈ 57) ; le bas : le dégradé gris.
        let gris = Self.degrade()
        let s = Self.signature { x, y in y < 100 ? Self.srgb(55, -45, 35) : gris(x, y) }
        let moyens = try XCTUnwrap(s.zones[1])
        XCTAssertEqual(moyens.a, 0, accuracy: 1, "le vert vif reste hors de la couleur de la zone")
        XCTAssertGreaterThan(s.bandes[3], 80, "mais compte dans la répartition par bande (vert)")
    }

    /// Constaté le 2 novembre 2026 (`--etalonnage`, un paysage d'automne de Dany) : à C* < 30, le
    /// feuillage orange des ombres (C* 20 à 30) tirait leur b* de −8 à +4 ; à 20, il reste dehors.
    func testUnFeuillageTerneNeTirePasLesOmbres() throws {
        let gris = Self.degrade()
        let s = Self.signature { x, y in
            let l = 12 + 80 * Double(x) / 299
            // Un tiers de la hauteur : un feuillage orange terne (C* ≈ 25) dans les ombres.
            return l < 40 && y < 70 ? Self.srgb(l, 12, 22) : gris(x, y)
        }
        let ombres = try XCTUnwrap(s.zones[0])
        XCTAssertEqual(ombres.b, 0, accuracy: 1, "le feuillage (C* 25) reste hors de la couleur des ombres")
        XCTAssertLessThan(Reference.chromaZone, hypot(12, 22))
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
        // Ancres relevées le 2 novembre 2026 (balayage) : le rouge de Lightroom (0) tombe à 10° en a*b*.
        XCTAssertEqual(Reference.angleLab(teinte: 0), 10, accuracy: 0.01)
        XCTAssertEqual(Reference.angleLab(teinte: 200), 221, accuracy: 0.01, "191 + 20/60 × 90")
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
        // 0,6 × 7,2 / 0,41 ≈ 11 (gain relevé des ombres).
        XCTAssertEqual(reglages["SplitToningShadowSaturation"] ?? 0, 0.6 * hypot(4, 6) / Reference.gainDepart[0], accuracy: 1)
        XCTAssertNil(reglages["ColorGradeMidtoneSat"], "tons moyens au milieu : rien")
        XCTAssertNil(reglages["ColorGradeShadowHue"], "la clé que Lightroom refuse n'est jamais écrite")
        let (fort, _) = Reference.traduire(ecart([.init(a: -2, b: -3), .zero, .init(a: 2, b: 3)]), etat: neutre, options: { var o = Reference.Options(); o.force = 1; return o }(), pentes: .init())
        XCTAssertEqual(fort["SplitToningShadowSaturation"] ?? 0, hypot(2, 3) / Reference.gainDepart[0], accuracy: 1, "strength 1 : 3,6 / 0,41")
        // Écriture absolue : la valeur finale part de l'étalonnage déjà posé (même teinte : la saturation s'ajoute).
        let posee = Reference.Etat(reglages: ["SplitToningShadowHue": ombres, "SplitToningShadowSaturation": 10], raw: false)
        let (ensuite, _) = Reference.traduire(ecart([.init(a: -4, b: -6), .zero, .init(a: 4, b: 6)]), etat: posee, options: .init(), pentes: .init())
        let somme = 10 + 0.6 * hypot(4, 6) / Reference.gainDepart[0]
        XCTAssertEqual(ensuite["SplitToningShadowSaturation"] ?? 0, min(somme, Reference.saturationMax), accuracy: 1)
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

    /// Revue (bloquant) : une référence aux seules ombres froides. La part commune n'est pas la
    /// moyenne des zones : les tons moyens et les hautes lumières, pareils sur les deux photos, ne
    /// reçoivent aucun étalonnage (avec la moyenne, ils prenaient la couleur complémentaire).
    func testUneSeuleZoneTeinteeNeTouchePasLesAutres() throws {
        let seule = ecart([.init(a: -3, b: -6), .zero, .zero])
        let (reglages, _) = Reference.traduire(seule, etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(Set(reglages.keys), ["SplitToningShadowHue", "SplitToningShadowSaturation"], "\(reglages)")
        XCTAssertEqual(Reference.commune(seule.zones), .zero)
        XCTAssertEqual(Reference.distance(seule, balance: false) ?? 0, hypot(3, 6) / 3, accuracy: 0.01, "les deux autres zones ne comptent pas d'écart")
        // De même pour des tons moyens seuls, et deux zones lues dont les tons moyens.
        XCTAssertEqual(Set(Reference.traduire(ecart([.zero, .init(a: 6, b: -8), .zero]), etat: neutre, options: .init(), pentes: .init()).reglages.keys),
                       ["ColorGradeMidtoneHue", "ColorGradeMidtoneSat"])
        XCTAssertEqual(Set(Reference.traduire(ecart([.init(a: -3, b: -6), .zero, nil]), etat: neutre, options: .init(), pentes: .init()).reglages.keys),
                       ["SplitToningShadowHue", "SplitToningShadowSaturation"])
        // Une dominante commune plus une zone à part : la balance est la dominante.
        XCTAssertEqual(Reference.commune([.init(a: 2, b: 3), .init(a: 2, b: 3), .init(a: -5, b: -4)]), .init(a: 2, b: 3))
        // Sur l'outil : rien d'écrit sur les tons moyens ni les hautes lumières.
        _ = brancherRendu(reference: [.init(a: -3, b: -6), .zero, .zero])
        let plan = try appel(["reference_id": 1, "photo_id": 2])
        let proposes = try XCTUnwrap(plan["photos"]?.array?.first?["reglages_proposes"]?.object)
        XCTAssertNil(proposes["ColorGradeMidtoneSat"])
        XCTAssertNil(proposes["SplitToningHighlightSaturation"])
        XCTAssertNotNil(proposes["SplitToningShadowSaturation"])
    }

    /// Revue (important) : un étalonnage déjà posé au-delà de la borne (copy_settings depuis la
    /// référence, un paramètre prédéfini) n'est pas coupé à 25 ; il peut baisser librement.
    func testUnEtalonnageDejaFortNestPasCoupe() {
        let etat = Reference.Etat(reglages: ["SplitToningShadowHue": 200, "SplitToningShadowSaturation": 50], raw: false)
        let angle = Reference.angleLab(teinte: 200) * .pi / 180
        let direction = Reference.Vecteur(a: cos(angle), b: sin(angle))
        let (pareil, _) = Reference.traduire(ecart([2 * direction, .zero, .zero]), etat: etat, options: .init(), pentes: .init())
        XCTAssertGreaterThanOrEqual(pareil["SplitToningShadowSaturation"] ?? 50, 50, "ni coupé à 25 ni augmenté au-delà")
        XCTAssertLessThanOrEqual(pareil["SplitToningShadowSaturation"] ?? 50, 50)
        let (moins, _) = Reference.traduire(ecart([-10 * direction, .zero, .zero]), etat: etat, options: .init(), pentes: .init())
        let g = Reference.gainDepart[0]
        XCTAssertEqual(moins["SplitToningShadowSaturation"] ?? 0, (50 * g - 6) / g, accuracy: 1, "baisser : libre (50 × 0,41 − 6 a*b*, soit 35)")
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

    /// Constaté le 2 novembre 2026 (balayage, X-H2S) : −30 de Vibrance ôte 5 à 7 de chroma aux couleurs
    /// vives, +30 n'en ajoute que 1,4 à 1,9. La pente de départ suit le sens voulu.
    func testLaVibranceMonteEtBaisseSelonSaPente() {
        let (monte, _) = Reference.traduire(ecart([nil, nil, nil], chroma: 3), etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(monte["Vibrance"] ?? 0, Reference.vibranceMaxPasse, "3 de chroma en plus : 0,6 × 3 × 18 ≈ 32, borné à 20 par passe")
        let (baisse, _) = Reference.traduire(ecart([nil, nil, nil], chroma: -3), etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(baisse["Vibrance"] ?? 0, (-3 * 0.6 * Reference.vibranceParChromaBaisse).rounded(), "3 de chroma en moins : −0,6 × 3 × 6 ≈ −11")
        // Une pente observée à la passe 1 remplace celle du départ.
        var observees = Reference.Pentes()
        observees.vibranceParChroma = 4
        XCTAssertEqual(Reference.traduire(ecart([nil, nil, nil], chroma: 3), etat: neutre, options: .init(), pentes: observees).reglages["Vibrance"],
                       (3 * 0.6 * 4).rounded())
    }

    /// Constaté le 2 novembre 2026 (portrait d'après un pont d'automne) : l'étalonnage de la passe 1
    /// rapproche les répartitions par bande (79 % → 65 %) ; la passe 2 juge les scènes sur l'écart du
    /// départ et ne copie pas la saturation que la passe 1 avait écartée.
    func testLaPasse2JugeLesScenesAuDepart() {
        let avant = ecart([nil, nil, nil], chroma: -12, scenes: 79), reste = ecart([nil, nil, nil], chroma: 3, scenes: 65)
        let vise = Reference.ecartVise(reste: reste, avant: avant, force: 0.6)
        XCTAssertEqual(vise.scenes, 79)
        XCTAssertNil(Reference.traduire(vise, etat: neutre, options: .init(), pentes: .init()).reglages["Vibrance"])
        // Scènes proches (relevé : même sortie, 3 à 68 %) sous le seuil, forêt contre plage (91 %) au-dessus.
        XCTAssertLessThan(68, Reference.seuilScenes)
        XCTAssertGreaterThan(76, Reference.seuilScenes)
    }

    /// Relevé du 2 novembre 2026 : l'écart dit la distance des scènes (scenes_pct), pour que l'essai réel la lise.
    func testLEcartDitLaDistanceDesScenes() {
        let json = Reference.ecartJSON(ecart([.zero, .zero, .zero], scenes: 43.4), balance: false)
        XCTAssertEqual(json["scenes_pct"]?.double, 43)
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

    /// Constaté le 2 novembre 2026 dans Lightroom (dune claire contre remise de diplôme sur rideau
    /// noir, scènes à 34 %) : match_look avait posé Exposure2012 +1,8. L'exposition change de
    /// `expositionMax` au plus en tout, depuis la valeur de départ, et la limite le dit.
    func testExpositionBorneeEnToutDepuisLeDepart() {
        XCTAssertEqual(Reference.expositionMax, 0.5)
        let clair = ecart([nil, nil, nil], exposition: 3)
        let (reglages, limites) = Reference.traduire(clair, etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(reglages["Exposure2012"] ?? 0, 0.5, accuracy: 0.001, "et non +1,8")
        XCTAssertTrue(limites.contains("Exposition changée de 0,5 IL au plus : l'écart de clarté vient aussi de la scène ; demander l'exposition à part si voulu."), "\(limites)")
        let sombre = Reference.traduire(ecart([nil, nil, nil], exposition: -3), etat: .init(reglages: ["Exposure2012": 0.4], raw: false),
                                        options: .init(), pentes: .init())
        XCTAssertEqual(sombre.reglages["Exposure2012"] ?? 0, -0.1, accuracy: 0.001, "depuis sa valeur de départ (0,4)")
        // La passe 2 part de la passe 1 (+0,5) : rien de plus au-delà du départ (0).
        let passe2 = Reference.traduire(clair, etat: .init(reglages: ["Exposure2012": 0.5], raw: false), options: .init(), pentes: .init(), depart: neutre)
        XCTAssertNil(passe2.reglages["Exposure2012"])
        XCTAssertTrue(passe2.limites.contains { $0.hasPrefix("Exposition changée de 0,5 IL au plus") })
        // Un petit écart passe sans limite.
        let petit = Reference.traduire(ecart([nil, nil, nil], exposition: 0.5), etat: neutre, options: .init(), pentes: .init())
        XCTAssertFalse(petit.limites.contains { $0.hasPrefix("Exposition") })
    }

    /// Revue du 2 novembre 2026 : le contraste était borné à 30 par passe, donc 60 sur deux passes ;
    /// il l'est maintenant en tout, depuis la valeur de départ.
    func testContrasteBorneEnToutSurLesDeuxPasses() {
        let plat = ecart([nil, nil, nil], contraste: -20)
        let passe1 = Reference.traduire(plat, etat: neutre, options: .init(), pentes: .init())
        XCTAssertEqual(passe1.reglages["Contrast2012"], -30)
        let passe2 = Reference.traduire(plat, etat: .init(reglages: ["Contrast2012": -30], raw: false), options: .init(), pentes: .init(), depart: neutre)
        XCTAssertNil(passe2.reglages["Contrast2012"], "pas −60")
        XCTAssertTrue(passe2.limites.contains("Contraste changé de 30 au plus en tout (les deux passes comprises) : l'écart de tons vient aussi de la scène."))
        // Revenir vers le départ reste libre.
        let retour = Reference.traduire(ecart([nil, nil, nil], contraste: 5), etat: .init(reglages: ["Contrast2012": -30], raw: false),
                                        options: .init(), pentes: .init(), depart: neutre)
        XCTAssertEqual(retour.reglages["Contrast2012"] ?? 0, -14, accuracy: 1)
    }

    // MARK: L'outil, sur un faux rendu

    /// Le faux module : la photo 1 (référence) a des ombres sarcelle et des hautes lumières orange ;
    /// la photo 2, grise, se rend d'après ses réglages, avec un gain réel de `gainReel` a*b* par point
    /// de saturation (plus fort que le modèle de match_look, `Reference.gainDepart` : la passe 2 corrige).
    func brancherRendu(gainReel: Double = 0.6, reference: [Reference.Vecteur] = [.init(a: -3, b: -4), .zero, .init(a: 3, b: 4)],
                       peau: CGRect? = nil, clarteReference: Double = 0, clartePhoto: Double = 0,
                       effetExposition: Double = 10) -> () -> [String: Double] {
        var etat: [String: Double] = [:]
        let verrou = NSLock()
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "apercu", let id = params["photo"]?.int {
                verrou.lock(); let reglages = etat; verrou.unlock()
                let couleur: (Int, Int) -> (UInt8, UInt8, UInt8)
                if id == 1 {
                    couleur = Self.degrade(ombres: reference[0], moyens: reference[1], hautes: reference[2], exposition: clarteReference, peau: peau)
                } else {
                    func v(_ z: Int) -> Reference.Vecteur {
                        let cles = Reference.clesZones[z]
                        return Reference.vecteur(teinte: reglages[cles.teinte] ?? 0, saturation: reglages[cles.saturation] ?? 0, gain: gainReel)
                    }
                    couleur = Self.degrade(ombres: v(0), moyens: v(1), hautes: v(2), exposition: clartePhoto + effetExposition * (reglages["Exposure2012"] ?? 0), peau: peau)
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
        // Le gain réel (0,6) est plus fort que le modèle (0,41 aux ombres) : la passe 2 baisse la saturation.
        let s1 = try XCTUnwrap(ecritures[0].params["reglages"]?["SplitToningShadowSaturation"]?.double)
        XCTAssertLessThan(etat()["SplitToningShadowSaturation"] ?? 99, s1)
    }

    /// Simulation du constat du 2 novembre 2026 dans Lightroom : une référence très claire (dune de
    /// sable, étalonnage sarcelle et orange) et une photo sombre (rideau noir), dont l'exposition rend
    /// peu (la passe 2 voudrait pousser encore) et dont le contraste ne se rend pas (la passe 2 le
    /// voudrait encore). Sur les deux passes : l'exposition change de 0,5 IL au plus, le contraste de
    /// 30, et les limites le disent.
    func testUneSceneTresDifferenteNeCopiePasSonExposition() throws {
        let etat = brancherRendu(clarteReference: 25, clartePhoto: -10, effetExposition: 3)
        let fait = try appel(["reference_id": 1, "photo_id": 2, "confirm": true, "strength": 1])
        let ecritures = fake.calls.filter { $0.command == "appliquer" }
        XCTAssertEqual(ecritures.count, 2)
        let ligne = try XCTUnwrap(fait["photos"]?.array?.first)
        XCTAssertGreaterThan(ligne["ecart_avant"]?["exposition_IL"]?.double ?? 0, 1, "la référence est bien plus claire")
        XCTAssertLessThan(ligne["ecart_avant"]?["scenes_pct"]?.double ?? 100, Reference.seuilScenes, "le garde-fou des scènes ne joue pas")
        for ecriture in ecritures {
            if let e = ecriture.params["reglages"]?["Exposure2012"]?.double { XCTAssertLessThanOrEqual(abs(e), 0.5 + 1e-9) }
            if let c = ecriture.params["reglages"]?["Contrast2012"]?.double { XCTAssertLessThanOrEqual(abs(c), 30) }
        }
        XCTAssertEqual(etat()["Exposure2012"] ?? 0, 0.5, accuracy: 0.001, "et non +1,8")
        XCTAssertGreaterThanOrEqual(etat()["Contrast2012"] ?? 0, -30, "et non −60")
        let limites = ligne["limites"]?.array?.compactMap(\.string) ?? []
        XCTAssertTrue(limites.contains { $0.hasPrefix("Exposition changée de 0,5 IL au plus") }, "\(limites)")
    }

    func testUnePhotoDejaProcheNestPasTouchee() throws {
        _ = brancherRendu(reference: [.zero, .zero, .zero])
        let fait = try appel(["reference_id": 1, "photo_id": 2, "confirm": true])
        XCTAssertFalse(fake.commands.contains("appliquer"))
        XCTAssertNotNil(fait["photos"]?.array?.first?["reglages"]?.string)
    }

    /// La peau protégée : la passe 1 déplace la peau de plus de `Teint.deplacementVisible` ; la passe 2
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

    /// Revue (important) : une photo en erreur ne fait pas échouer la série ; les étapes déjà écrites
    /// sur les autres sont rendues (photos[].etapes), et la suite est traitée.
    func testUnePhotoEnErreurNArretePasLesAutres() throws {
        _ = brancherRendu()
        let base = fake.onSend
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "apercu", params["photo"]?.int == 3 {
                fake.errors["apercu"] = LightroomError.plugin("Lightroom n'a pas pu rendre l'aperçu.")
            } else {
                if command == "apercu" { fake.errors["apercu"] = nil }
                base?(command, params)
            }
        }
        let fait = try appel(["reference_id": 1, "photo_ids": [2, 3, 4], "confirm": true])
        let lignes = try XCTUnwrap(fait["photos"]?.array)
        XCTAssertEqual(lignes.compactMap { $0["id"]?.int }, [2, 3, 4])
        XCTAssertEqual(lignes[0]["etapes"]?.array?.count, 2, "les étapes de la photo 2 sont dites")
        XCTAssertNotNil(lignes[1]["erreur"]?.string)
        XCTAssertNil(lignes[1]["etapes"])
        XCTAssertNil(lignes[2]["erreur"], "la photo 4 est traitée")
        // La seule photo demandée en erreur, sans rien d'écrit : l'erreur, comme avant.
        XCTAssertTrue(tools.call(name: "match_look", arguments: ["reference_id": 1, "photo_id": 3, "confirm": true]).isError)
    }

    func testUnArretDansLightroomRendLeResultatPartiel() throws {
        _ = brancherRendu()
        let base = fake.onSend
        fake.onSend = { [unowned fake] command, params in
            guard let fake else { return }
            if command == "apercu", params["photo"]?.int == 3 {
                fake.errors["apercu"] = CommandeArretee(message: "Arrêtée par l'utilisateur.")
            } else {
                base?(command, params)
            }
        }
        let fait = try appel(["reference_id": 1, "photo_ids": [2, 3, 4], "confirm": true])
        let lignes = try XCTUnwrap(fait["photos"]?.array)
        XCTAssertEqual(lignes.compactMap { $0["id"]?.int }, [2], "la photo 4 n'est pas partie")
        XCTAssertEqual(lignes[0]["etapes"]?.array?.count, 2)
        XCTAssertTrue(fait["arrete"]?.string?.contains("2 photo(s) non traitée(s)") == true, fait["arrete"]?.string ?? "")
    }

    /// Revue (important) : des photo_ids ne sont pas décrits par la série ; une vidéo s'écarte par
    /// la lecture des vignettes, avant tout aperçu et toute écriture.
    func testLesVideosDePhotoIdsSontEcartees() throws {
        _ = brancherRendu()
        fake.replies["vignettes"] = ["photos": [["id": 3, "format": "VIDEO"], ["id": 2, "format": "RAW"]]]
        let fait = try appel(["reference_id": 1, "photo_ids": [2, 3]])
        XCTAssertFalse(fake.calls.contains { $0.command == "apercu" && $0.params["photo"]?.int == 3 })
        XCTAssertEqual(fait["photos"]?.array?.compactMap { $0["id"]?.int }, [2])
        XCTAssertNotNil(fait["videos_ecartees"])
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
