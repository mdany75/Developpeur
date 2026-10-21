import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Éclairage mixte (`Eclairage.swift`) : dominante des tons neutres par case et par zone tonale,
/// visages à part, balance proposée, et le relevé (`--eclairage`) face au faux module. Images de
/// synthèse seulement ; les couleurs se choisissent d'après les constantes (provisoires, à relever).
final class EclairageTests: XCTestCase {
    typealias Couleur = (UInt8, UInt8, UInt8)

    /// Lampe (chaude) et fenêtre (froide), à 7 du gris chacune (b* +7,3 et −7,3) : presque neutres
    /// sous la borne de 12, même quand le point neutre de l'image se tire vers l'une d'elles.
    static let lampe: Couleur = (140, 134, 122)
    static let fenetre: Couleur = (116, 122, 134)
    static let gris: Couleur = (120, 120, 120)

    /// Une dominante globale, comme un changement de balance des blancs : chaque composante
    /// multipliée en lumière linéaire (sRGB).
    static func dominante(_ c: Couleur, _ gains: (Double, Double, Double)) -> Couleur {
        func lineaire(_ v: UInt8) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> UInt8 {
            let x = min(max(l, 0), 1)
            return UInt8(((x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055) * 255).rounded())
        }
        return (srgb(lineaire(c.0) * gains.0), srgb(lineaire(c.1) * gains.1), srgb(lineaire(c.2) * gains.2))
    }

    /// Une balance bien plus froide que la lumière (3 200 K sur une scène de jour), et moins forte.
    static let froide = (0.72, 0.97, 1.55), unPeuFroide = (0.82, 0.98, 1.3)

    /// Image de synthèse sans compression : chaque pixel prend la couleur donnée pour (x, y), depuis
    /// le coin haut gauche.
    static func image(width: Int = 300, height: Int = 200, _ couleur: (Int, Int) -> Couleur) -> CGImage {
        TestSupport.imagePixels(width: width, height: height, couleur)
    }

    static func lab(_ c: Couleur) -> (l: Double, a: Double, b: Double) { Measurements.lab(c.0, c.1, c.2) }

    /// Écart a*b* entre deux couleurs.
    static func ecart(_ c1: Couleur, _ c2: Couleur) -> Double {
        let l1 = lab(c1), l2 = lab(c2)
        return hypot(l1.a - l2.a, l1.b - l2.b)
    }

    /// Une couleur proche du gris 120, plus jaune, dont l'écart a*b* au gris vaut à peu près `cible`.
    static func couleur(ecart cible: Double) -> Couleur {
        var meilleure = gris, erreur = Double.infinity
        for rouge in 120...140 {
            for bleu in stride(from: 120, through: 60, by: -1) {
                let c: Couleur = (UInt8(rouge), 120, UInt8(bleu))
                let valeur = lab(c)
                let e = abs(ecart(c, gris) - cible) + 0.1 * abs(valeur.a)
                if e < erreur { erreur = e; meilleure = c }
            }
        }
        return meilleure
    }

    /// Le tiers gauche d'une couleur, le reste d'une autre (bornes des cases de la grille).
    static func tiersGauche(_ gauche: Couleur, reste: Couleur, width: Int = 300, height: Int = 200) -> CGImage {
        image(width: width, height: height) { x, _ in x < width / 3 ? gauche : reste }
    }

    // MARK: - Mesure

    func testUneSeuleLumiereNEstPasMixte() throws {
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.image { _, _ in (119, 119, 119) }))
        XCTAssertFalse(mesure.mixte)
        XCTAssertEqual(mesure.regions.compactMap { $0 }.count, 9)
        XCTAssertEqual(try XCTUnwrap(mesure.ecartRegions), 0, accuracy: 0.01)
        XCTAssertTrue(mesure.lecture.hasPrefix("une seule lumière"), mesure.lecture)
        let json = mesure.json(balance: (5000, 0))
        XCTAssertEqual(json["mixte"], false)
        XCTAssertNil(json["groupes"], "une seule lumière : ni groupes ni grille ni conseil")
        XCTAssertNil(json["regions_3x3"])
        XCTAssertNil(json["conseil"])
        XCTAssertNil(json["balance_proposee"])
        XCTAssertNil(json["base"], "une seule lumière : la lecture et les zones tonales seulement (view_photo s'appelle souvent)")
        XCTAssertNotNil(json["zones_tonales"])
        XCTAssertEqual(mesure.centre, MesureEclairage.Neutre(a: 0, b: 0), "une photo balancée : les tons neutres autour du gris")
    }

    func testDominanteUniformeNEstPasMixte() throws {
        let chaude: Couleur = (132, 124, 108)
        let image = Self.image { _, _ in chaude }
        let globale = try XCTUnwrap(Measurements.analyze(image))
        XCTAssertTrue(globale.castReading.contains("chaude"), "la photo est chaude : \(globale.castReading)")
        let mesure = try XCTUnwrap(Eclairage.mesurer(image))
        XCTAssertFalse(mesure.mixte, "une dominante globale n'est pas un éclairage mixte")
        XCTAssertLessThan(try XCTUnwrap(mesure.ecartRegions), 1)
        XCTAssertEqual(try XCTUnwrap(mesure.tonales[1]).b, Self.lab(chaude).b, accuracy: Eclairage.Histogramme.pas)
    }

    func testLampeAGaucheFenetreADroiteEstMixte() throws {
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(Self.lampe, reste: Self.fenetre)))
        XCTAssertTrue(mesure.mixte)
        XCTAssertEqual(mesure.groupes.map(\.cases), [[0, 3, 6], [1, 2, 4, 5, 7, 8]], "la lampe (plus chaude) d'abord")
        XCTAssertEqual(try XCTUnwrap(mesure.ecartRegions), Self.ecart(Self.lampe, Self.fenetre), accuracy: 0.5)
        XCTAssertEqual(mesure.groupes[0].poids, 100.0 / 3, accuracy: 1)
        XCTAssertTrue(mesure.lecture.hasPrefix("éclairage mixte"), mesure.lecture)
        XCTAssertTrue(mesure.lecture.contains("plus chaude tiers gauche"), mesure.lecture)
        XCTAssertTrue(mesure.lecture.contains("plus froide tiers du milieu, tiers droit"), mesure.lecture)

        let json = mesure.json(balance: (4300, 3))
        XCTAssertEqual(json["mixte"], true)
        XCTAssertEqual(json["regions_3x3"]?.array?.count, 3)
        XCTAssertEqual(json["regions_3x3"]?.array?.first?.array?.count, 3)
        XCTAssertEqual(json["groupes"]?.array?.first?["zones"], "tiers gauche")
        XCTAssertEqual(json["groupes"]?.array?.first?["lumiere"], "plus chaude")
        XCTAssertTrue(json["conseil"]?.string?.contains("à confirmer à l'œil") == true)
        XCTAssertTrue(json["conseil"]?.string?.contains("zone d'intérêt") == true, "sans visage : la lumière du sujet")
        XCTAssertNil(json["balance_proposee"], "sans visage ni zone d'intérêt : pas de lumière du sujet")
        let base = try XCTUnwrap(json["base"]?.string, "éclairage mixte : la base dit comment lire les chiffres")
        XCTAssertTrue(base.contains("à moins de 12 en a*b* du gris, ou du point neutre de l'image"), base)
        XCTAssertTrue(base.contains("mixte à partir de 8 (relevé le 20 octobre 2026)"), base)
        XCTAssertTrue(base.contains("lue à partir de 3 % de tons neutres"), "la part de PhotoMeasurements.partNeutreMin")
    }

    func testFormeCourteSansGrilleNiConseil() throws {
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(Self.lampe, reste: Self.fenetre)))
        let court = try XCTUnwrap(mesure.json(balance: (4300, 3), court: true).object)
        XCTAssertEqual(Set(court.keys).subtracting(["lecture", "mixte", "ecart_regions", "zones_tonales", "lecture_tonale"]), [],
                       "forme courte : lecture, mixte, écart et zones tonales seulement")
        XCTAssertEqual(court["mixte"], true)
        XCTAssertNotNil(court["ecart_regions"])
        XCTAssertNotNil(court["zones_tonales"]?["tons_moyens"]?["b"])
    }

    /// Sans `partMinGroupe`, la case colorée seule ferait un groupe d'un écart au-dessus du seuil.
    func testUneCaseColoreeNeFaitPasUnGroupe() throws {
        let beige = Self.couleur(ecart: 1.25 * Eclairage.seuilMixte)
        XCTAssertGreaterThan(Self.ecart(beige, Self.gris), Eclairage.seuilMixte, "seule, la case dépasserait le seuil")
        XCTAssertLessThan(hypot(Self.lab(beige).a, Self.lab(beige).b), Eclairage.chromaMax, "le beige reste presque neutre")
        XCTAssertLessThan(100.0 / 9, Eclairage.partMinGroupe, "une case seule pèse moins qu'un groupe")
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.image { x, y in x >= 200 && y >= 133 ? beige : Self.gris }))
        XCTAssertEqual(mesure.regions[8].map { $0.b } ?? 0, Self.lab(beige).b, accuracy: Eclairage.Histogramme.pas)
        XCTAssertFalse(mesure.mixte, "un mur beige n'est pas une lumière")
        XCTAssertTrue(mesure.groupes.allSatisfy { $0.cases.count >= 2 }, "aucun groupe d'une seule case")
        XCTAssertLessThan(try XCTUnwrap(mesure.ecartRegions), Eclairage.seuilMixte)
    }

    func testLeSeuilDecide() throws {
        let seuil = Eclairage.seuilMixte
        let dessus = Self.couleur(ecart: seuil + 0.4), dessous = Self.couleur(ecart: seuil - 0.4)
        let ecartDessus = Self.ecart(dessus, Self.gris), ecartDessous = Self.ecart(dessous, Self.gris)
        XCTAssertTrue(ecartDessus > seuil + 0.1 && ecartDessus < seuil + 1, "\(ecartDessus)")
        XCTAssertTrue(ecartDessous < seuil - 0.1 && ecartDessous > seuil - 1, "\(ecartDessous)")
        for (couleur, attendu) in [(dessus, ecartDessus), (dessous, ecartDessous)] {
            let mesure = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(Self.gris, reste: couleur)))
            XCTAssertEqual(try XCTUnwrap(mesure.ecartRegions), attendu, accuracy: 0.05)
            XCTAssertEqual(mesure.mixte, attendu >= seuil, "écart \(attendu) pour un seuil de \(seuil)")
        }
    }

    /// Un visage de peau claire (presque neutre), une lumière froide autour, un fond chaud : la peau
    /// se lit à part, la lumière autour du visage aussi, et la case du visage n'est pas tirée vers
    /// la peau (sans l'exclusion des cadres, la peau y ferait les deux tiers des tons neutres).
    func testVisagesAPart() throws {
        // Deux lumières plus éloignées que lampe et fenêtre (b* +9 et −9) : l'anneau ne couvre qu'une
        // partie des cases qu'il touche, et l'écart entre groupes s'y dilue.
        let peau: Couleur = (190, 170, 160), chaude: Couleur = (143, 136, 121), froide: Couleur = (114, 122, 137)
        let largeur = 480, hauteur = 320
        let cadre = CGRect(x: 0.39, y: 0.335, width: 0.22, height: 0.33)
        let anneau = CGRect(x: cadre.minX - 0.75 * cadre.width, y: cadre.minY - 0.25 * cadre.height,
                            width: 2.5 * cadre.width, height: 2.75 * cadre.height)
        let image = Self.image(width: largeur, height: hauteur) { x, y in
            let point = CGPoint(x: (Double(x) + 0.5) / Double(largeur), y: (Double(y) + 0.5) / Double(hauteur))
            if cadre.contains(point) { return peau }
            return anneau.contains(point) ? froide : chaude
        }
        XCTAssertLessThan(hypot(Self.lab(peau).a, Self.lab(peau).b), Eclairage.chromaMax, "la peau passerait pour un ton neutre")
        XCTAssertGreaterThan(Self.ecart(peau, froide), Eclairage.distancePeau, "la lumière autour n'est pas prise pour la peau")

        let mesure = try XCTUnwrap(Eclairage.mesurer(image, visages: [cadre]))
        let visage = try XCTUnwrap(mesure.visages.first)
        let teinte = atan2(Self.lab(peau).b, Self.lab(peau).a) * 180 / .pi
        XCTAssertEqual(try XCTUnwrap(visage.peau).teinte, teinte, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(visage.peau).l, Self.lab(peau).l, accuracy: 0.5)
        XCTAssertEqual(visage.source, "anneau")
        XCTAssertEqual(try XCTUnwrap(visage.lumiere).b, Self.lab(froide).b, accuracy: 1)
        let centre = try XCTUnwrap(mesure.regions[4], "la case du visage se lit encore autour de lui")
        XCTAssertEqual(centre.b, Self.lab(froide).b, accuracy: 1, "la case du visage n'est pas tirée vers la peau")
        XCTAssertEqual(mesure.sujetSource, "visages")
        XCTAssertEqual(try XCTUnwrap(mesure.lumiereSujet).b, Self.lab(froide).b, accuracy: 1)
        // La lumière froide autour du visage, le fond chaud : deux lumières, le visage dans la froide.
        XCTAssertTrue(mesure.mixte, mesure.lecture)
        XCTAssertEqual(visage.groupe, 1, "le groupe de la lumière plus froide (le second)")
        XCTAssertTrue(mesure.lecture.hasSuffix("visages dans la lumière plus froide"), mesure.lecture)

        let json = mesure.json(balance: nil)
        XCTAssertEqual(json["visages"]?.array?.first?["lumiere_mesuree"], "autour du visage")
        XCTAssertNotNil(json["visages"]?.array?.first?["peau"]?["teinte_deg"])
        XCTAssertEqual(json["visages"]?.array?.first?["dans_la_lumiere"], "plus froide")
        XCTAssertTrue(json["conseil"]?.string?.contains("lumière des visages") == true)
        XCTAssertFalse(json["conseil"]?.string?.contains("zone d'intérêt") == true)
    }

    /// Un cadre non fini (CGRect.null, NaN) ou démesuré ne fait pas planter la mesure : sans la
    /// garde, la conversion des positions en entiers s'arrête sur une erreur fatale.
    func testUnCadreNonFiniNeFaitPasPlanter() throws {
        let image = Self.tiersGauche(Self.lampe, reste: Self.fenetre)
        let cadres = [CGRect.null, CGRect(x: .nan, y: 0.2, width: 0.2, height: 0.2),
                      CGRect(x: .infinity, y: 0.2, width: 0.2, height: 0.2), CGRect(x: 1e300, y: 0.2, width: 0.2, height: 0.2)]
        let mesure = try XCTUnwrap(Eclairage.mesurer(image, visages: cadres, sujet: .null))
        XCTAssertTrue(mesure.mixte, "les cases se lisent comme sans visage")
        XCTAssertEqual(mesure.visages.count, 1, "seul le cadre fini (même hors de l'image) reste")
        XCTAssertEqual(mesure.visages.first?.source, "case", "hors de l'image : ni peau ni anneau, la case la plus proche")
        XCTAssertNil(mesure.visages.first?.peau)
        XCTAssertFalse(Eclairage.fini(CGRect(x: 0.1, y: 0.1, width: 0, height: 0.2)), "un cadre vide n'est pas mesuré")
    }

    /// Assez de cases lues, mais aucune partition ne laisse `partMinGroupe` % de chaque côté.
    func testUneZonePortePresqueTout() {
        let lue = MesureEclairage.Dominante(a: 0, b: 0, part: 50, pixels: 1000)
        let mesure = MesureEclairage(tonales: [nil, lue, nil], regions: [lue, lue, lue] + [MesureEclairage.Dominante?](repeating: nil, count: 6),
                                     groupes: [], ecartRegions: nil, ecartTonal: nil, visages: [], lumiereSujet: nil,
                                     sujetSource: nil, borne: Eclairage.chromaMax)
        XCTAssertFalse(mesure.mixte)
        XCTAssertTrue(mesure.lecture.hasPrefix("une zone porte presque tous les tons neutres"), mesure.lecture)
        XCTAssertNil(mesure.json(balance: (5000, 0))["conseil"])
    }

    /// Sans tons neutres autour du visage, sa lumière est celle de sa case.
    func testSansAnneauLaCaseDuVisage() throws {
        let peau: Couleur = (190, 170, 160)
        let cadre = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.15)
        let largeur = 480, hauteur = 320
        let image = Self.image(width: largeur, height: hauteur) { x, y in
            let point = CGPoint(x: (Double(x) + 0.5) / Double(largeur), y: (Double(y) + 0.5) / Double(hauteur))
            return cadre.contains(point) ? peau : Self.lampe
        }
        // Autour du visage, la même couleur que la peau à moins de `distancePeau` : écartée (cou, mains).
        XCTAssertLessThan(Self.ecart(peau, Self.lampe), Eclairage.distancePeau)
        let visage = try XCTUnwrap(Eclairage.mesurer(image, visages: [cadre])?.visages.first)
        XCTAssertEqual(visage.source, "case")
        XCTAssertEqual(try XCTUnwrap(visage.lumiere).b, Self.lab(Self.lampe).b, accuracy: 1)
    }

    func testUnPetitVisageNEstPasMesure() throws {
        let image = Self.image { _, _ in Self.gris }
        let mesure = try XCTUnwrap(Eclairage.mesurer(image, visages: [CGRect(x: 0.5, y: 0.5, width: Eclairage.visageMin / 2, height: 0.03)]))
        XCTAssertTrue(mesure.visages.isEmpty)
    }

    func testLaZoneDInteretSansVisage() throws {
        let image = Self.tiersGauche(Self.lampe, reste: Self.fenetre)
        let mesure = try XCTUnwrap(Eclairage.mesurer(image, sujet: CGRect(x: 0.6, y: 0.2, width: 0.3, height: 0.6)))
        XCTAssertEqual(mesure.sujetSource, "zone d'intérêt")
        XCTAssertEqual(try XCTUnwrap(mesure.lumiereSujet).b, Self.lab(Self.fenetre).b, accuracy: 0.5)
        let json = mesure.json(balance: (6100, -2))
        XCTAssertEqual(json["balance_proposee"]?["Temperature"], 6100)
        XCTAssertEqual(json["balance_proposee"]?["sur"], "lumière du sujet (zone d'intérêt)")
    }

    func testZonesTonales() throws {
        let ombres: Couleur = (40, 44, 56), hautes: Couleur = (228, 220, 206)
        // Une colonne sur trois dans les ombres : chaque case garde la même mesure (pas de mixte).
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.image { x, _ in x % 3 == 0 ? ombres : hautes }))
        XCTAssertEqual(try XCTUnwrap(mesure.tonales[0]).b, Self.lab(ombres).b, accuracy: Eclairage.Histogramme.pas)
        XCTAssertNil(mesure.tonales[1])
        XCTAssertEqual(try XCTUnwrap(mesure.tonales[2]).b, Self.lab(hautes).b, accuracy: Eclairage.Histogramme.pas)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(mesure.ecartTonal), Eclairage.seuilTonal)
        let lecture = try XCTUnwrap(mesure.lectureTonale)
        XCTAssertTrue(lecture.contains("ombres plus froides"), lecture)
        XCTAssertTrue(lecture.contains("ShadowTint"), lecture)
        XCTAssertFalse(mesure.mixte, "l'écart tonal est une lecture à part")
        XCTAssertEqual(mesure.json(balance: nil, court: true)["lecture_tonale"]?.string, lecture)
        XCTAssertEqual(mesure.json(balance: nil)["zones_tonales"]?["tons_moyens"], "trop peu de tons neutres")
    }

    func testPixelsEcretesEtBouchesEcartes() throws {
        let damier = Self.image { x, y in (x / 8 + y / 8) % 2 == 0 ? (0, 0, 0) : (255, 255, 255) }
        let mesure = try XCTUnwrap(Eclairage.mesurer(damier))
        XCTAssertTrue(mesure.regions.allSatisfy { $0 == nil })
        XCTAssertTrue(mesure.tonales.allSatisfy { $0 == nil })
        XCTAssertNil(mesure.ecartRegions)
        XCTAssertFalse(mesure.mixte)
        XCTAssertTrue(mesure.lecture.hasPrefix("trop peu de tons neutres par zone"), mesure.lecture)
        XCTAssertNotNil(mesure.json(balance: nil)["zones_tonales"])
    }

    func testUnGrandAperçuEstReduitA512() throws {
        let grande = Self.tiersGauche(Self.lampe, reste: Self.fenetre, width: 1344, height: 896)
        XCTAssertEqual(Eclairage.pixelsLab(grande)?.largeur, Measurements.maxSide)
        XCTAssertTrue(try XCTUnwrap(Eclairage.mesurer(grande)).mixte)
    }

    func testSeparerExigeDeuxVraisGroupes() {
        // Une case porte presque tous les tons neutres : aucune partition ne laisse 20 % de chaque côté.
        XCTAssertNil(Eclairage.separer([(0, 0, 0, 90), (1, 0, 20, 5), (2, 0, -20, 5)]))
        let deux = Eclairage.separer([(0, 0, 10, 30), (1, 0, 10, 20), (2, 0, -10, 25), (3, 0, -10, 25)])
        XCTAssertEqual(deux?.groupes.map(\.cases), [[0, 1], [2, 3]])
        XCTAssertEqual(deux?.ecart ?? 0, 20, accuracy: 1e-9)
        XCTAssertEqual(deux?.groupes[0].poids ?? 0, 50, accuracy: 1e-9)
    }

    func testHistogrammeDonneLaMedianeAuPasPres() {
        var histogramme = Eclairage.Histogramme(borne: 20)
        for (a, b) in [(1.0, -3.0), (2.0, 4.0), (3.0, 5.0), (10.0, -19.99), (-19.99, 19.99)] { histogramme.ajouter(a, b) }
        XCTAssertEqual(histogramme.nombre, 5)
        XCTAssertEqual(histogramme.a, Eclairage.mediane([1, 2, 3, 10, -19.99]), accuracy: Eclairage.Histogramme.pas)
        XCTAssertEqual(histogramme.b, Eclairage.mediane([-3, 4, 5, -19.99, 19.99]), accuracy: Eclairage.Histogramme.pas)
        histogramme.ajouter(25, -25)
        XCTAssertEqual(histogramme.nombre, 6, "une valeur hors des bornes compte dans la classe extrême")
    }

    func testNommer() {
        XCTAssertEqual(Eclairage.nommer([0, 3, 6]), "tiers gauche")
        XCTAssertEqual(Eclairage.nommer([1, 2, 4, 5, 7, 8]), "tiers du milieu, tiers droit")
        XCTAssertEqual(Eclairage.nommer([6, 7, 8]), "tiers du bas")
        XCTAssertEqual(Eclairage.nommer([3, 4, 5]), "bande du milieu")
        XCTAssertEqual(Eclairage.nommer([0, 3, 6, 7, 8]), "tiers gauche, tiers du bas")
        XCTAssertEqual(Eclairage.nommer([4, 0]), "en haut à gauche, au centre")
    }

    /// Un écart qui tient surtout à a* (néon vert, lumière magenta) : les lumières se disent « plus
    /// magenta » et « plus verte », la plus magenta d'abord.
    func testLectureMagentaOuVerte() throws {
        let magenta: Couleur = (136, 114, 124), vert: Couleur = (110, 128, 118)
        XCTAssertGreaterThan(abs(Self.lab(magenta).a - Self.lab(vert).a), abs(Self.lab(magenta).b - Self.lab(vert).b))
        XCTAssertGreaterThanOrEqual(Self.ecart(magenta, vert), Eclairage.seuilMixte)
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(vert, reste: magenta)))
        XCTAssertTrue(mesure.mixte)
        XCTAssertEqual(mesure.groupes.first?.cases, [1, 2, 4, 5, 7, 8])
        XCTAssertTrue(mesure.lecture.contains("plus magenta tiers du milieu, tiers droit"), mesure.lecture)
        XCTAssertTrue(mesure.lecture.contains("plus verte tiers gauche"), mesure.lecture)
        XCTAssertEqual(mesure.json(balance: nil)["groupes"]?.array?.last?["lumiere"], "plus verte")
    }

    /// view_photo s'appelle souvent : une seule lumière tient en quelques lignes ; la grille, les
    /// groupes, le conseil et la base ne viennent qu'avec un éclairage mixte.
    func testLEclairageResteCourtSansEclairageMixte() throws {
        let simple = try XCTUnwrap(Eclairage.mesurer(Self.image { _, _ in Self.gris })).json(balance: nil)
        XCTAssertLessThan(JSONCoding.line(simple).count, 400, JSONCoding.line(simple))
        let mixte = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(Self.lampe, reste: Self.fenetre))).json(balance: (4300, 3))
        XCTAssertLessThan(JSONCoding.line(mixte).count, 2600, JSONCoding.line(mixte))
    }

    // MARK: - Point neutre de l'image (une dominante globale)

    /// Relevé du 20 octobre 2026 : sous une autre balance (3 200 K), la borne absolue (C* < 12) ne
    /// lisait plus aucune case. Autour du point neutre de l'image, deux lumières restent mixtes et
    /// une seule lumière reste simple, avec le même écart à 25 % près.
    func testUneDominanteGlobaleNeChangePasLeVerdict() throws {
        let deux = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(Self.lampe, reste: Self.fenetre)))
        let une = try XCTUnwrap(Eclairage.mesurer(Self.image { _, _ in Self.gris }))
        XCTAssertTrue(deux.mixte)
        XCTAssertFalse(une.mixte)
        let ecart = try XCTUnwrap(deux.ecartRegions)
        for (nom, gains) in [("froide", Self.froide), ("un peu froide", Self.unPeuFroide)] {
            let lampe = Self.dominante(Self.lampe, gains), fenetre = Self.dominante(Self.fenetre, gains), gris = Self.dominante(Self.gris, gains)
            // La dominante pousse les tons neutres au-delà de la borne autour du gris : sans le point
            // neutre de l'image, la fenêtre (les deux tiers) et le gris ne se liraient plus.
            XCTAssertGreaterThan(hypot(Self.lab(fenetre).a, Self.lab(fenetre).b), Eclairage.chromaMax, nom)
            if nom == "froide" {
                XCTAssertGreaterThan(hypot(Self.lab(gris).a, Self.lab(gris).b), Eclairage.chromaMax, "le gris non plus")
            }

            let mixte = try XCTUnwrap(Eclairage.mesurer(Self.tiersGauche(lampe, reste: fenetre)))
            XCTAssertTrue(mixte.mixte, "\(nom) : deux lumières restent mixtes (\(mixte.lecture))")
            XCTAssertEqual(mixte.regions.compactMap { $0 }.count, 9, nom)
            XCTAssertEqual(try XCTUnwrap(mixte.ecartRegions), ecart, accuracy: 0.25 * ecart, "\(nom) : le même écart à 25 % près")
            XCTAssertEqual(mixte.groupes.first?.cases, [0, 3, 6], "\(nom) : la lampe reste la plus chaude")
            XCTAssertLessThan(mixte.neutre.b, -Eclairage.toleranceNeutre, "\(nom) : le point neutre suit la dominante")
            XCTAssertLessThan(mixte.centre.b, 0, nom)

            let simple = try XCTUnwrap(Eclairage.mesurer(Self.image { _, _ in gris }))
            XCTAssertFalse(simple.mixte, nom)
            XCTAssertTrue(simple.lecture.hasPrefix("une seule lumière"), "\(nom) : les cases se lisent encore (\(simple.lecture))")
            XCTAssertLessThan(try XCTUnwrap(simple.ecartRegions), 1, nom)
            // La dominante elle-même se lit toujours en absolu (la lumière des zones, pour la balance).
            XCTAssertEqual(try XCTUnwrap(simple.tonales[1]).b, Self.lab(gris).b, accuracy: 0.1, nom)
        }
    }

    /// Une photo balancée dont la scène tire le point neutre (sable, intérieur chaud) : à moins de
    /// `toleranceNeutre` du gris, les tons neutres se prennent autour du gris, comme au relevé.
    func testLePointNeutreDUnePhotoBalanceeResteAuGris() throws {
        let sable: Couleur = (142, 134, 120)
        XCTAssertLessThan(hypot(Self.lab(sable).a, Self.lab(sable).b), Eclairage.toleranceNeutre)
        let mesure = try XCTUnwrap(Eclairage.mesurer(Self.image { x, _ in x < 200 ? sable : Self.gris }))
        XCTAssertEqual(mesure.neutre.b, Self.lab(sable).b, accuracy: 0.1, "le point neutre : la médiane (le sable, les deux tiers)")
        XCTAssertEqual(mesure.centre, MesureEclairage.Neutre(a: 0, b: 0), "mais les tons neutres se prennent autour du gris")
        // Au-delà de la tolérance, le centre suit le point neutre, à cette distance près.
        let centre = Eclairage.centrer(MesureEclairage.Neutre(a: 0, b: -25))
        XCTAssertEqual(centre.b, -25 + Eclairage.toleranceNeutre, accuracy: 1e-9)
        XCTAssertEqual(centre.a, 0, accuracy: 1e-9)
        XCTAssertEqual(Eclairage.centrer(MesureEclairage.Neutre(a: 3, b: 4)), MesureEclairage.Neutre(a: 0, b: 0))
    }

    /// Les visages de la mesure gardent leur rang dans vision.visages : un cadre non fini, ou trop
    /// petit, n'en décale pas la lecture.
    func testLesVisagesGardentLeurRangDansVision() throws {
        let image = Self.tiersGauche(Self.lampe, reste: Self.fenetre)
        let grand = CGRect(x: 0.5, y: 0.3, width: 0.15, height: 0.2), petit = CGRect(x: 0.1, y: 0.1, width: 0.02, height: 0.03)
        let mesure = try XCTUnwrap(Eclairage.mesurer(image, visages: [CGRect.null, grand, petit, grand.offsetBy(dx: -0.3, dy: 0)]))
        XCTAssertEqual(mesure.visages.map(\.index), [1, 3], "le cadre non fini (0) et le trop petit (2) sont sautés")
        let json = mesure.json(balance: nil)
        XCTAssertEqual(json["visages"]?.array?.map { $0["index_vision"]?.int }, [1, 3])
    }

    // MARK: - Balance proposée (Tools+Balance)

    static func mesureMixte(lumiere: MesureEclairage.Dominante?, ecart: Double = Eclairage.seuilMixte + 5) -> MesureEclairage {
        MesureEclairage(tonales: [nil, nil, nil], regions: [MesureEclairage.Dominante?](repeating: nil, count: 9),
                        groupes: [.init(cases: [0, 3, 6], a: 2, b: 12, poids: 40), .init(cases: [1, 2, 4, 5, 7, 8], a: 0, b: -6, poids: 60)],
                        ecartRegions: ecart, ecartTonal: nil, visages: [], lumiereSujet: lumiere,
                        sujetSource: lumiere == nil ? nil : "visages", borne: Eclairage.chromaMax)
    }

    func testBalanceProposeeRefroiditUneLumiereChaude() throws {
        let chaude = MesureEclairage.Dominante(a: 2, b: 12, part: 50, pixels: 1000)
        let mesure = Self.mesureMixte(lumiere: chaude)
        XCTAssertTrue(mesure.mixte)
        let raw: JSONValue = ["echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 10]]
        let kelvins = try XCTUnwrap(ToolHandler.balanceProposee(mesure, reponse: raw))
        XCTAssertLessThan(kelvins.temperature, 5000, "une lumière chaude se refroidit")
        XCTAssertEqual(kelvins.temperature, ToolHandler.balancePourPoint(.init(l: 50, a: 2, b: 12, ecretes: 0), raw: true, temperature: 5000, tint: 10).temperature,
                       "les mêmes pentes que white_balance_point")
        let relative: JSONValue = ["echelle_temperature": "relative (JPEG, TIFF : −100 à +100)", "reglages": ["Temperature": 0, "Tint": 0]]
        XCTAssertLessThan(try XCTUnwrap(ToolHandler.balanceProposee(mesure, reponse: relative)).temperature, 0)

        XCTAssertNil(ToolHandler.balanceProposee(Self.mesureMixte(lumiere: chaude, ecart: Eclairage.seuilMixte - 1), reponse: raw), "pas mixte")
        XCTAssertNil(ToolHandler.balanceProposee(Self.mesureMixte(lumiere: nil), reponse: raw), "sans lumière du sujet")
        XCTAssertNil(ToolHandler.balanceProposee(mesure, reponse: ["echelle_temperature": "kelvins (RAW : 2000 à 50000)"]),
                     "sans Temperature lue, pas de balance")

        let json = mesure.json(balance: kelvins)
        XCTAssertEqual(json["balance_proposee"]?["Temperature"]?.double, kelvins.temperature)
        XCTAssertEqual(json["balance_proposee"]?["sur"], "lumière des visages")
        XCTAssertNotNil(json["balance_proposee"]?["remarque"])
    }

    // MARK: - Relevé (`--eclairage`)

    /// Aperçu de synthèse à deux lumières, encodé en JPEG comme ceux du module.
    static func apercuMixte() -> Data {
        TestSupport.jpegPixels(width: 600, height: 400) { x, _ in x < 200 ? lampe : fenetre }
    }

    func testReleveLitSansRienEcrire() throws {
        let fake = FakeLightroom()
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" {
                fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(Self.apercuMixte())),
                                          "photo": ["id": 7, "fichier": "ESSAI.RAF"],
                                          "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                                          "reglages": ["Temperature": 5000, "Tint": 0]]
            }
        }
        var vues: [String] = []
        let lignes = Eclairage.releve(lightroom: fake, ids: [7], fichiers: [], essai: nil) { vues.append($0) }
        XCTAssertEqual(lignes, vues, "chaque ligne part aussi dès qu'elle est prête")
        XCTAssertEqual(fake.commands, ["apercu"], "lecture seule : un aperçu, rien d'autre")
        XCTAssertEqual(fake.lastParams["photo"], 7)
        XCTAssertEqual(fake.lastParams["taille"]?.int, ToolHandler.defaultPreviewSize, "la taille de view_photo")
        XCTAssertFalse(lignes.contains { $0.hasPrefix("✘") }, lignes.joined(separator: "\n"))
        XCTAssertTrue(lignes.contains { $0.contains("ESSAI.RAF") && $0.contains("Temperature 5000") })
        // Les scènes de Vision (ou, si Vision échoue sur la machine d'essai, qu'elles n'ont pas été lues).
        XCTAssertTrue(lignes.contains { $0.contains("Vision :") && ($0.contains("scène : interior_room") || $0.contains("scène non lue")) },
                      lignes.joined(separator: "\n"))
        for borne in Eclairage.bornesReleve {
            XCTAssertTrue(lignes.contains { $0.hasPrefix("  borne \(Eclairage.nombre(borne)) :") }, "borne \(borne)")
        }
        let actuelle = try XCTUnwrap(lignes.first { $0.hasPrefix("  borne \(Eclairage.nombre(Eclairage.chromaMax)) :") })
        XCTAssertTrue(actuelle.contains("(mixte)") && actuelle.contains(" ms"), actuelle)
        XCTAssertTrue(actuelle.contains("point neutre a* ") && actuelle.contains("centre a* "), "le relevé donne le centre des tons neutres")
        XCTAssertTrue(lignes.contains { $0.contains("groupes : plus chaude tiers gauche") })
        XCTAssertTrue(lignes.contains { $0.hasPrefix("Résumé") })
        XCTAssertEqual(lignes.filter { $0.hasPrefix("7\t") }.count, Eclairage.bornesReleve.count)
    }

    func testReleveSousUnEssaiSurUneCopieVirtuelle() throws {
        let fake = FakeLightroom()
        fake.replies["reglages"] = ["photo": ["id": 7, "fichier": "ESSAI.RAF (Essai)", "copie_virtuelle": true],
                                    "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 0]]
        fake.onSend = { [unowned fake] command, _ in
            if command == "essayer" {
                fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(Self.apercuMixte())), "photo": ["id": 7],
                                           "changements": [["cle": "Temperature", "avant": 5000, "apres": 3200]]]
            }
        }
        let lignes = Eclairage.releve(lightroom: fake, ids: [7], fichiers: [], essai: ["settings": ["Temperature": 3200]])
        XCTAssertEqual(fake.commands, ["reglages", "essayer"])
        XCTAssertEqual(fake.lastParams["reglages"]?["Temperature"], 3200)
        XCTAssertEqual(fake.lastParams["photo"], 7)
        XCTAssertFalse(lignes.contains { $0.hasPrefix("✘") }, lignes.joined(separator: "\n"))
        XCTAssertTrue(lignes.contains { $0.contains("essai : Temperature 5000 → 3200") && $0.contains("Temperature 3200") },
                      lignes.joined(separator: "\n"))
    }

    /// La balance de l'aperçu sous un essai : celle de l'essai, ajoutée à celle de la photo s'il est
    /// relatif ; inconnue s'il la fait calculer (pas de balance qui neutralise le sujet).
    func testBalanceDeLEssai() throws {
        func fake() -> FakeLightroom {
            let fake = FakeLightroom()
            fake.replies["reglages"] = ["photo": ["id": 7, "fichier": "ESSAI.RAF (Essai)", "copie_virtuelle": true],
                                        "echelle_temperature": "kelvins (RAW : 2000 à 50000)", "reglages": ["Temperature": 5000, "Tint": 4]]
            fake.onSend = { [unowned fake] command, _ in
                if command == "essayer" {
                    fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(Self.apercuMixte())), "photo": ["id": 7]]
                }
            }
            return fake
        }
        let relative = try Eclairage.apercu(id: 7, lightroom: fake(), essai: ["relative": true, "settings": ["Temperature": 300]])
        XCTAssertEqual(relative.reponse?["reglages"]?["Temperature"], 5300)
        XCTAssertEqual(relative.reponse?["reglages"]?["Tint"], 4, "la teinte de la photo reste")
        XCTAssertEqual(relative.reponse?["echelle_temperature"], "kelvins (RAW : 2000 à 50000)")
        let absolue = try Eclairage.apercu(id: 7, lightroom: fake(), essai: ["settings": ["Temperature": 3200, "Tint": -5]])
        XCTAssertEqual(absolue.reponse?["reglages"]?["Temperature"], 3200)
        XCTAssertEqual(absolue.reponse?["reglages"]?["Tint"], -5)
        let automatique = try Eclairage.apercu(id: 7, lightroom: fake(), essai: ["white_balance": "auto"])
        XCTAssertNil(automatique.reponse, "balance calculée par Lightroom : inconnue")
        let prereglee = try Eclairage.apercu(id: 7, lightroom: fake(), essai: ["preset": "Chaud", "settings": ["Temperature": 3200]])
        XCTAssertNil(prereglee.reponse, "un paramètre prédéfini peut changer la teinte")
    }

    func testReleveRefuseLEssaiSurUnOriginal() {
        let fake = FakeLightroom()
        fake.replies["reglages"] = ["photo": ["id": 7, "fichier": "DSCF0001.RAF", "copie_virtuelle": false]]
        let lignes = Eclairage.releve(lightroom: fake, ids: [7], fichiers: [], essai: ["settings": ["Temperature": 3200]])
        XCTAssertEqual(fake.commands, ["reglages"], "rien n'est essayé sur un original")
        XCTAssertTrue(lignes.contains { $0.hasPrefix("✘ 7 : --essai seulement sur une copie virtuelle") }, lignes.joined(separator: "\n"))
    }

    func testReleveDUnFichierSansLightroom() throws {
        let fake = FakeLightroom()
        let fichier = TestSupport.temporaryDirectory().appendingPathComponent("interieur.jpg")
        try Self.apercuMixte().write(to: fichier)
        let lignes = Eclairage.releve(lightroom: fake, ids: [], fichiers: [fichier], essai: nil)
        XCTAssertTrue(fake.commands.isEmpty)
        XCTAssertTrue(lignes.contains { $0.contains("interieur.jpg") && $0.contains("sans Lightroom") })
        XCTAssertEqual(lignes.filter { $0.hasPrefix("interieur.jpg\t") }.count, Eclairage.bornesReleve.count)
    }

    func testReleveContinueApresUnEchec() throws {
        let fake = FakeLightroom()
        fake.errors["apercu"] = LightroomError.plugin("Photo introuvable : 9.")
        let fichier = TestSupport.temporaryDirectory().appendingPathComponent("autre.jpg")
        try Self.apercuMixte().write(to: fichier)
        let lignes = Eclairage.releve(lightroom: fake, ids: [9], fichiers: [fichier], essai: nil)
        XCTAssertTrue(lignes.contains { $0.hasPrefix("✘ 9 : ") && $0.contains("introuvable") })
        XCTAssertTrue(lignes.contains { $0.hasPrefix("autre.jpg\t") }, "les autres photos sont mesurées")
    }
}
