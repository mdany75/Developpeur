import CoreGraphics
import ImageIO
import XCTest
@testable import DeveloppeurKit

/// Composition lue (1.3) : le modèle du cadre (passage de l'image de view_photo à l'image entière,
/// plus grand cadre, cadre proposé, règles lâchées), le dessin du cadre proposé, read_composition et
/// la surimpression de preview_settings, face au faux module.
final class CompositionTests: XCTestCase {
    var fake: FakeLightroom!
    var tools: ToolHandler!

    override func setUp() {
        fake = FakeLightroom()
        tools = ToolHandler(lightroom: fake)
    }

    // MARK: Le modèle du cadre

    func testVersImageEntiereEtRetour() throws {
        let p = CGPoint(x: 0.3, y: 0.7)
        XCTAssertEqual(Composition.versImageEntiere(p, cadre: nil, aspect: 1.5), p, "l'identité sans cadre")
        XCTAssertEqual(Composition.depuisImageEntiere(p, cadre: nil, aspect: 1.5), p)

        let moitie = Composition.Cadre(centreX: 0.5, centreY: 0.5, largeur: 0.5, ratio: 1.5, angle: 0)
        let haut = Composition.versImageEntiere(.zero, cadre: moitie, aspect: 1.5)
        XCTAssertEqual(Double(haut.x), 0.25, accuracy: 1e-12)
        XCTAssertEqual(Double(haut.y), 0.25, accuracy: 1e-12)
        let bas = Composition.versImageEntiere(CGPoint(x: 1, y: 1), cadre: moitie, aspect: 1.5)
        XCTAssertEqual(Double(bas.x), 0.75, accuracy: 1e-12)
        XCTAssertEqual(Double(bas.y), 0.75, accuracy: 1e-12)

        let tourne = Composition.Cadre(centreX: 0.45, centreY: 0.55, largeur: 0.6, ratio: 1.25, angle: 2)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: 0.3, y: 0.8), CGPoint(x: 1, y: 0.5), CGPoint(x: 0.71, y: 0.13)] {
            let retour = Composition.depuisImageEntiere(Composition.versImageEntiere(point, cadre: tourne, aspect: 1.5), cadre: tourne, aspect: 1.5)
            XCTAssertEqual(Double(retour.x), Double(point.x), accuracy: 1e-9)
            XCTAssertEqual(Double(retour.y), Double(point.y), accuracy: 1e-9)
        }
    }

    /// Les coins suivent la formule de cadreDansZone (Recadrage.lua), en pixels de l'image affichée :
    /// px = x + a·w·cos − b·h·sin, py = y + a·w·sin + b·h·cos.
    func testLesCoinsSuiventCadreDansZone() throws {
        let largeurImage = 1500.0, hauteurImage = 1000.0
        let cadre = Composition.Cadre(centreX: 0.45, centreY: 0.55, largeur: 0.6, ratio: 1.25, angle: 2)
        let x = cadre.centreX * largeurImage, y = cadre.centreY * hauteurImage
        let w = cadre.largeur * largeurImage, h = w / cadre.ratio
        let c = cos(2 * Double.pi / 180), s = sin(2 * Double.pi / 180)
        let attendus = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)].map { a, b in
            ((x + a * w * c - b * h * s) / largeurImage, (y + a * w * s + b * h * c) / hauteurImage)
        }
        let coins = Composition.coins(cadre, aspect: largeurImage / hauteurImage)
        XCTAssertEqual(coins.count, 4)
        for (coin, attendu) in zip(coins, attendus) {
            XCTAssertEqual(Double(coin.x), attendu.0, accuracy: 1e-12)
            XCTAssertEqual(Double(coin.y), attendu.1, accuracy: 1e-12)
        }
        // Un angle positif tourne le cadre dans le sens horaire sur l'image : son côté droit descend.
        XCTAssertGreaterThan(Double(coins[1].y), Double(coins[0].y))
    }

    /// Valeurs de Recadrage.calculer (puis Recadrage.lire), relevées avec le module dans LuaJIT : le
    /// plus grand cadre sans zone, en part de la largeur d'une image 3:2.
    func testPlusGrandeLargeurCommeLeModule() {
        let attendues: [(ratio: Double, angle: Double, largeur: Double)] = [
            (1.5, 0, 1.0), (1.5, 2, 0.950805), (1.5, -3, 0.928390),
            (0.8, 0, 0.533334), (0.8, 2, 0.519154), (0.8, -3, 0.512576),
        ]
        for cas in attendues {
            XCTAssertEqual(Composition.plusGrandeLargeur(ratio: cas.ratio, angle: cas.angle, aspect: 1.5), cas.largeur, accuracy: 2e-6,
                           "ratio \(cas.ratio), angle \(cas.angle)")
        }
    }

    /// Un cadre relu par le module (Recadrage.lire d'une demande 4:5, angle 2, taille 0,7, centre_x
    /// 0,4 sur une image de 6240 × 4160) redonne cette demande comme crop.
    func testLeCadreDuModuleRedonneSaDemande() throws {
        let module: JSONValue = ["ratio": 0.800001, "angle": 2, "centre_x": 0.4, "centre_y": 0.5, "largeur": .number(0.363409 * 6240)]
        let dimensions: JSONValue = ["largeur": 6240, "hauteur": 4160]
        let cadre = try XCTUnwrap(Composition.Cadre(module: module, dimensions: dimensions))
        XCTAssertEqual(cadre.largeur, 0.363409, accuracy: 1e-9)
        let crop = Composition.crop(cadre, aspectImage: 1.5)
        XCTAssertEqual(crop["aspect"]?.string, "4:5")
        XCTAssertEqual(try XCTUnwrap(crop["size"]?.double), 0.7, accuracy: 0.0005)
        XCTAssertEqual(crop["angle"]?.double, 2)
        XCTAssertEqual(crop["center_x"]?.double, 0.4)
        XCTAssertEqual(crop["center_y"]?.double, 0.5)
        XCTAssertNil(Composition.Cadre(module: module, dimensions: nil), "sans dimensions, pas de cadre")
        XCTAssertNil(Composition.Cadre(module: ["ratio": 1.5], dimensions: dimensions))
        XCTAssertEqual(Composition.resume(cadre, aspectImage: 1.5), "4:5, redressé de 2°, 36 % de la largeur gardée")
    }

    // MARK: Le cadre proposé

    func coinsDansLImage(_ cadre: Composition.Cadre, aspect: Double, file: StaticString = #filePath, line: UInt = #line) {
        for coin in Composition.coins(cadre, aspect: aspect) {
            XCTAssertTrue((-1e-6...1.000001).contains(Double(coin.x)) && (-1e-6...1.000001).contains(Double(coin.y)),
                          "coin hors de l'image : \(coin)", file: file, line: line)
        }
    }

    func testLHorizonTombeSurLeTiers() throws {
        let aspect = 1.5, wmax = Composition.plusGrandeLargeur(ratio: 1.5, angle: 0, aspect: aspect)
        let horizon = CGPoint(x: 0.5, y: 0.5)
        let bas = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: .init(horizon: (horizon, 2.0 / 3)))
        XCTAssertEqual(Double(Composition.depuisImageEntiere(horizon, cadre: bas.cadre, aspect: aspect).y), 2.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(bas.tenues, ["horizon sur le tiers du bas"])
        XCTAssertTrue(bas.lachees.isEmpty)
        coinsDansLImage(bas.cadre, aspect: aspect)
        XCTAssertGreaterThanOrEqual(bas.cadre.largeur, Composition.margeArrondis * 0.75 * wmax - 1e-9)
        // La marge des arrondis : le cadre ne touche pas le haut de l'image (les arrondis du module ne
        // le font pas sortir, Lightroom ne le resserre pas).
        let hautDuCadre = Composition.coins(bas.cadre, aspect: aspect).map { Double($0.y) }.min() ?? 0
        XCTAssertGreaterThan(hautDuCadre, 0.0005)
        XCTAssertLessThan(hautDuCadre, 0.002)

        let haut = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: .init(horizon: (horizon, 1.0 / 3)))
        XCTAssertEqual(Double(Composition.depuisImageEntiere(horizon, cadre: haut.cadre, aspect: aspect).y), 1.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(haut.tenues, ["horizon sur le tiers du haut"])
        coinsDansLImage(haut.cadre, aspect: aspect)

        // Tourné : l'horizon reste sur le tiers du cadre tourné.
        let penche = Composition.proposer(aspect: aspect, ratio: 1.5, angle: -2, regles: .init(horizon: (CGPoint(x: 0.5, y: 0.55), 2.0 / 3)))
        XCTAssertEqual(penche.cadre.angle, -2)
        XCTAssertEqual(Double(Composition.depuisImageEntiere(CGPoint(x: 0.5, y: 0.55), cadre: penche.cadre, aspect: aspect).y), 2.0 / 3, accuracy: 1e-6)
        coinsDansLImage(penche.cadre, aspect: aspect)
    }

    func testLeSujetQuiRegardeADroiteVaSurLeTiersGauche() throws {
        let aspect = 1.5
        let sujet = CGRect(x: 0.45, y: 0.4, width: 0.1, height: 0.2)
        let regles = Composition.Regles(horizon: (CGPoint(x: 0.5, y: 0.5), 2.0 / 3), sujet: sujet, sujetX: 1.0 / 3, regard: 1)
        let proposition = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: regles)
        let centre = Composition.depuisImageEntiere(CGPoint(x: sujet.midX, y: sujet.midY), cadre: proposition.cadre, aspect: aspect)
        XCTAssertEqual(Double(centre.x), 1.0 / 3, accuracy: 1e-6)
        XCTAssertEqual(proposition.tenues, ["horizon sur le tiers du bas", "sujet sur le tiers gauche, de l'espace devant lui", "sujet entier dans le cadre"])
        XCTAssertTrue(proposition.lachees.isEmpty)
        coinsDansLImage(proposition.cadre, aspect: aspect)
    }

    /// Partout : les quatre coins dans l'image, au moins tailleMin du plus grand cadre (moins la
    /// marge des arrondis), et l'angle au centième.
    func testLesCadresProposesTiennentDansLImage() {
        let aspect = 1.5
        for angle in [-3.0, 0, 2.517] {
            for ratio in [1.5, 0.8, 1.0] {
                for horizonY in [0.3, 0.55, 0.8] {
                    for sujet in [nil, CGRect(x: 0.2, y: 0.3, width: 0.15, height: 0.2), CGRect(x: 0.7, y: 0.5, width: 0.2, height: 0.3)] {
                        let regles = Composition.Regles(horizon: (CGPoint(x: 0.5, y: horizonY), 2.0 / 3), sujet: sujet,
                                                        sujetX: sujet.map { $0.midX < 0.5 ? 1.0 / 3 : 2.0 / 3 }, tailleMin: 0.6)
                        let p = Composition.proposer(aspect: aspect, ratio: ratio, angle: angle, regles: regles)
                        coinsDansLImage(p.cadre, aspect: aspect)
                        let wmax = Composition.plusGrandeLargeur(ratio: ratio, angle: p.cadre.angle, aspect: aspect)
                        XCTAssertGreaterThanOrEqual(p.cadre.largeur, Composition.margeArrondis * 0.6 * wmax - 1e-9)
                        XCTAssertLessThanOrEqual(p.cadre.largeur, wmax * Composition.margeArrondis + 1e-9)
                        XCTAssertEqual(p.cadre.angle, (angle * 100).rounded() / 100)
                    }
                }
            }
        }
    }

    func testUnSujetColleAuBordLacheLaRegleEtLeDit() {
        let aspect = 1.5
        let sujet = CGRect(x: 0, y: 0.4, width: 0.08, height: 0.2)
        let regles = Composition.Regles(horizon: (CGPoint(x: 0.5, y: 0.5), 2.0 / 3), sujet: sujet, sujetX: 2.0 / 3, regard: -1)
        let p = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: regles)
        XCTAssertEqual(p.tenues, ["horizon sur le tiers du bas"])
        XCTAssertEqual(p.lachees, ["sujet sur le tiers droit, de l'espace devant lui", "sujet entier dans le cadre (il est coupé)"])
        coinsDansLImage(p.cadre, aspect: aspect)
        XCTAssertEqual(Double(Composition.depuisImageEntiere(CGPoint(x: 0.5, y: 0.5), cadre: p.cadre, aspect: aspect).y), 2.0 / 3, accuracy: 1e-6,
                       "l'horizon reste sur le tiers")

        // Sans horizon non plus : le plus grand cadre centré, toutes les règles dites lâchées.
        let seul = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0,
                                        regles: .init(sujet: sujet, sujetX: 2.0 / 3, sujetY: (0.5, 1.0 / 3), regard: -1))
        XCTAssertEqual(seul.cadre.centreX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(seul.lachees.first, "sujet sur le tiers droit, de l'espace devant lui")
        XCTAssertTrue(seul.lachees.contains("sujet sur le tiers haut"))
        coinsDansLImage(seul.cadre, aspect: aspect)
    }

    /// Un sujet décentré qui ne tient pas sur son tiers se centre avant d'être lâché.
    func testLeSujetSeCentreAvantDEtreLache() {
        let aspect = 1.5
        // Sujet large, au milieu : sur un tiers, il dépasserait du cadre ; centré, il tient.
        let sujet = CGRect(x: 0.2, y: 0.3, width: 0.6, height: 0.3)
        let p = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0,
                                     regles: .init(horizon: (CGPoint(x: 0.5, y: 0.5), 2.0 / 3), sujet: sujet, sujetX: 1.0 / 3))
        XCTAssertEqual(p.tenues, ["horizon sur le tiers du bas", "sujet centré", "sujet entier dans le cadre"])
        XCTAssertEqual(p.lachees, ["sujet sur le tiers gauche"])
        let centre = Composition.depuisImageEntiere(CGPoint(x: sujet.midX, y: sujet.midY), cadre: p.cadre, aspect: aspect)
        XCTAssertEqual(Double(centre.x), 0.5, accuracy: 1e-6)
    }

    func testUneTailleImposeeEstRespectee() {
        let aspect = 1.5, wmax = Composition.plusGrandeLargeur(ratio: 1.5, angle: 0, aspect: aspect)
        let libre = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: .init(taille: 0.8))
        XCTAssertEqual(libre.cadre.largeur, 0.8 * wmax, accuracy: 1e-9)
        let horizon = CGPoint(x: 0.5, y: 0.5)
        let avecHorizon = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: .init(horizon: (horizon, 2.0 / 3), taille: 0.6))
        XCTAssertEqual(avecHorizon.cadre.largeur, 0.6 * wmax, accuracy: 1e-9)
        XCTAssertEqual(Double(Composition.depuisImageEntiere(horizon, cadre: avecHorizon.cadre, aspect: aspect).y), 2.0 / 3, accuracy: 1e-6)
        // Toute l'image : la marge des arrondis seule.
        let entiere = Composition.proposer(aspect: aspect, ratio: 1.5, angle: 0, regles: .init(taille: 1))
        XCTAssertEqual(entiere.cadre.largeur, Composition.margeArrondis * wmax, accuracy: 1e-9)
    }

    /// Le crop proposé va tel quel dans preview_settings et apply_settings (cropParameter).
    func testLeCropEstAccepteParApplySettings() throws {
        let aspect = 1.5
        for (angle, ratio, texte) in [(-2.0, 1.5, "original"), (3.27, 0.8, "4:5"), (0, 1.0, "1:1")] {
            let p = Composition.proposer(aspect: aspect, ratio: ratio, angle: angle,
                                         regles: .init(horizon: (CGPoint(x: 0.5, y: 0.6), 2.0 / 3), sujet: CGRect(x: 0.6, y: 0.3, width: 0.1, height: 0.2), sujetX: 2.0 / 3))
            let crop = Composition.crop(p.cadre, aspectImage: aspect, aspect: texte)
            XCTAssertEqual(crop["aspect"]?.string, texte)
            let module = try XCTUnwrap(tools.cropParameter(Arguments(raw: ["crop": crop])))
            XCTAssertEqual(module["angle"]?.double, (angle * 100).rounded() / 100)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(module["taille"]?.double), ToolHandler.cropSizeRange.lowerBound)
            XCTAssertLessThanOrEqual(try XCTUnwrap(module["taille"]?.double), 1)
            XCTAssertNotNil(module["centre_x"])
            if texte == "original" { XCTAssertNil(module["ratio"]) } else { XCTAssertEqual(try XCTUnwrap(module["ratio"]?.double), ratio, accuracy: 1e-9) }
        }
    }

    // MARK: Textes

    func testFormatsEtResume() {
        XCTAssertEqual(Composition.texteRatio(1.5), "3:2")
        XCTAssertEqual(Composition.texteRatio(0.8), "4:5")
        XCTAssertEqual(Composition.texteRatio(16.0 / 9), "16:9")
        XCTAssertEqual(Composition.texteRatio(1), "1:1")
        XCTAssertEqual(Composition.texteRatio(4032.0 / 3024), "4:3")
        XCTAssertEqual(Composition.texteRatio(1.52), "1,52:1")
        XCTAssertEqual(Composition.resume(.init(centreX: 0.5, centreY: 0.5, largeur: 0.82, ratio: 1.5, angle: -1.38), aspectImage: 1.5),
                       "3:2 (format d'origine), redressé de 1,4°, 82 % de la largeur gardée")
        XCTAssertEqual(Composition.resume(.init(centreX: 0.5, centreY: 0.5, largeur: 0.5, ratio: 0.8, angle: 0), aspectImage: 1.5),
                       "4:5, 50 % de la largeur gardée")
        XCTAssertTrue(Composition.presqueIdentique(.init(centreX: 0.5, centreY: 0.5, largeur: 0.998, ratio: 1.5, angle: 0), nil, aspectImage: 1.5))
        XCTAssertFalse(Composition.presqueIdentique(.init(centreX: 0.55, centreY: 0.5, largeur: 0.8, ratio: 1.5, angle: 0), nil, aspectImage: 1.5))
    }

    func testRegardDuLacet() {
        XCTAssertNil(Composition.regard(yaw: nil))
        XCTAssertNil(Composition.regard(yaw: 0.1), "de face sous le seuil")
        XCTAssertEqual(Composition.regard(yaw: 0.5 * Composition.signeLacet), 1)
        XCTAssertEqual(Composition.regard(yaw: -0.5 * Composition.signeLacet), -1)
    }

    func testLaLectureDitCeQuiCloche() {
        let lecture = Composition.lecture(.init(inclinaison: -1.38, hauteurHorizon: 0.51, sujet: CGRect(x: 0.45, y: 0.3, width: 0.1, height: 0.2),
                                                nomSujet: "le visage", regard: 1, regardLu: false))
        XCTAssertEqual(lecture, ["L'horizon penche de 1,4° (le côté droit plus bas).",
                                 "Il coupe la photo en deux : sur un tiers, le ciel ou le premier plan prend la place.",
                                 "Le visage est au centre et regarde vers la droite : peu d'espace devant lui."])
        let bord = Composition.lecture(.init(sujet: CGRect(x: 0.02, y: 0.4, width: 0.2, height: 0.2), regard: -1, regardLu: true))
        XCTAssertEqual(bord, ["Le sujet est à gauche et regarde vers la gauche (lu par Vision, à vérifier à l'œil) : peu d'espace devant lui.",
                              "Le sujet touche presque le bord gauche."])
        XCTAssertEqual(Composition.lecture(.init(inclinaison: 0.2, hauteurHorizon: 0.66)), ["L'horizon est droit.", "Il est sur le tiers du bas."])
        XCTAssertEqual(Composition.lecture(.init(inclinaison: 0.8)), ["L'horizon penche de 0,8° (le côté droit plus haut)."])
        XCTAssertTrue(Composition.lecture(.init()).first?.hasPrefix("Ni horizon donné ni sujet trouvé") == true)
        XCTAssertEqual(Composition.lecture(.init(sujet: CGRect(x: 0.01, y: 0.02, width: 0.98, height: 0.97))).last,
                       "Le sujet remplit presque toute la photo.")
    }

    // MARK: Le dessin

    /// Gris uni de la taille donnée.
    static func gris(_ niveau: UInt8, largeur: Int = 1344, hauteur: Int = 896) -> CGImage {
        TestSupport.imagePixels(width: largeur, height: hauteur) { _, _ in (niveau, niveau, niveau) }
    }

    /// Luminance (0 à 255) d'un pixel (x, y depuis le coin haut gauche).
    static func niveau(_ image: CGImage, _ x: Int, _ y: Int) -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { tampon in
            let context = CGContext(data: tampon.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return 0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])
    }

    func testLeCadreProposeEstDessine() throws {
        let coins = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        let data = try XCTUnwrap(PreviewImages.cadrePropose(Self.gris(128), coins: coins))
        let image = try XCTUnwrap(PreviewImages.image(data))
        XCTAssertEqual(image.width, 1344)
        XCTAssertEqual(image.height, 896)
        XCTAssertLessThanOrEqual(Self.niveau(image, 60, 40), 0.55 * 128, "hors-cadre assombri")
        XCTAssertEqual(Self.niveau(image, 672, 448), 128, accuracy: 6, "milieu du cadre inchangé")
        // La ligne des tiers verticale de gauche : x = 0,2 + 0,6 / 3 = 0,4.
        XCTAssertGreaterThan(Self.niveau(image, Int(0.4 * 1344), 300), 160, "tiers plus clair")
        // Le côté haut du cadre : des tirets blancs et des creux sombres, en alternance.
        let ligne = Int(0.2 * 896)
        let niveaux = stride(from: Int(0.25 * 1344), to: Int(0.75 * 1344), by: 2).map { Self.niveau(image, $0, ligne) }
        let clairs = niveaux.filter { $0 > 200 }.count, sombres = niveaux.filter { $0 < 90 }.count
        XCTAssertGreaterThan(clairs, niveaux.count / 4, "tirets blancs")
        XCTAssertGreaterThan(sombres, niveaux.count / 4, "creux sombres")
        var alternances = 0
        for (a, b) in zip(niveaux, niveaux.dropFirst()) where (a > 200) != (b > 200) { alternances += 1 }
        XCTAssertGreaterThan(alternances, 10, "pointillés")

        let grande = try XCTUnwrap(PreviewImages.image(try XCTUnwrap(PreviewImages.cadrePropose(Self.gris(128, largeur: 2400, hauteur: 1600), coins: coins))))
        XCTAssertLessThanOrEqual(max(grande.width, grande.height), PreviewImages.maxSide)
        XCTAssertNil(PreviewImages.cadrePropose(Self.gris(128), coins: Array(coins.prefix(3))))
    }

    // MARK: read_composition

    /// Le faux module rend l'image entière : l'horizon de synthèse qui monte de 2° vers la droite.
    func repondreApercu(_ reponse: [String: JSONValue], image: Data = AnalyseTests.tiltedHorizon(degrees: 2)) {
        fake.onSend = { [unowned fake] command, _ in
            guard command == "apercu" else { return }
            var objet = reponse
            objet["chemin"] = .string(TestSupport.previewFile(image))
            fake!.replies["apercu"] = .object(objet)
        }
    }

    static let entiere: [String: JSONValue] = ["image_entiere": true, "dimensions": ["largeur": 6240, "hauteur": 4160],
                                               "photo": ["id": 3, "fichier": "DSCF1595.RAF"], "recadrage": ["angle": 0, "recadree": false]]

    func testReadCompositionLitLImageEntiere() throws {
        repondreApercu(Self.entiere)
        let result = tools.call(name: "read_composition", arguments: ["photo_id": 3, "horizon": ["x1": 0.1, "y1": 0.5482, "x2": 0.9, "y2": 0.5056]])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertFalse(result.porteUneImage, "aucune image : preview_settings montre le cadre")
        XCTAssertEqual(fake.commands, ["apercu"])
        XCTAssertEqual(fake.lastParams["entier"]?.bool, true)
        XCTAssertEqual(fake.lastParams["taille"]?.int, 1344)
        XCTAssertEqual(fake.lastParams["cles"]?.array?.count, 0)
        XCTAssertEqual(fake.lastParams["photo"]?.int, 3)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(try XCTUnwrap(info["horizon"]?["inclinaison"]?.double), 2, accuracy: 0.1)
        let angle = try XCTUnwrap(info["crop"]?["angle"]?.double)
        XCTAssertEqual(angle, -2, accuracy: 0.1, "une horizontale qui monte à droite se corrige dans le sens horaire")
        XCTAssertEqual(info["horizon"]?["angle_de_recadrage_actuel"]?.double, 0)
        XCTAssertEqual(info["cadre_actuel"]?.string, "aucun")
        XCTAssertEqual(info["crop"]?["aspect"]?.string, "original")
        XCTAssertEqual(info["image_entiere"]?["largeur"]?.int, 6240)
        let lecture = info["lecture"]?.array?.compactMap(\.string) ?? []
        XCTAssertTrue(lecture.contains { $0.contains("penche") }, "\(lecture)")
        XCTAssertTrue(info["cadre_propose"]?["regles_tenues"]?.array?.first?.string?.hasPrefix("horizon droit (redressé de 2") == true)
        XCTAssertNotNil(info["rien_n_est_applique"])

        // Le crop met l'horizon sur le tiers du bas du cadre proposé.
        let crop = try XCTUnwrap(info["crop"])
        let largeur = try XCTUnwrap(crop["size"]?.double) * Composition.plusGrandeLargeur(ratio: 1.5, angle: angle, aspect: 1.5)
        let cadre = Composition.Cadre(centreX: try XCTUnwrap(crop["center_x"]?.double), centreY: try XCTUnwrap(crop["center_y"]?.double),
                                      largeur: largeur, ratio: 1.5, angle: angle)
        let milieu = CGPoint(x: 0.5, y: (0.5482 + 0.5056) / 2)
        XCTAssertEqual(Double(Composition.depuisImageEntiere(milieu, cadre: cadre, aspect: 1.5).y), 2.0 / 3, accuracy: 0.01)
        coinsDansLImage(cadre, aspect: 1.5)
    }

    /// Une photo recadrée et tournée : les points donnés dans la vue recadrée (celle de view_photo)
    /// sont ramenés dans l'image entière. Sans ce passage, l'horizon serait lu à la hauteur qu'il a
    /// dans la vue, et le cadre proposé le placerait mal.
    func testLesPointsDeLaVueRecadreeSontRamenes() throws {
        var reponse = Self.entiere
        reponse["cadre_actuel"] = ["ratio": 1.5, "angle": -2, "centre_x": 0.5, "centre_y": 0.5, "largeur": .number(0.8 * 6240)]
        reponse["recadrage"] = ["angle": -2, "recadree": true]
        repondreApercu(reponse)
        // L'horizon de synthèse passe en y = (896 − 400 − x·tan 2°) / 896 ; au milieu de l'image :
        let yMilieu = (496 - 672 * tan(2 * Double.pi / 180)) / 896
        // Dans la vue recadrée (cadre 0,8 de la largeur, tourné de −2°), il est droit, à cette hauteur :
        let v = 0.5 + (yMilieu - 0.5) * cos(2 * Double.pi / 180) / 0.8
        let result = tools.call(name: "read_composition", arguments: ["horizon": ["x1": 0.1, "y1": .number(v), "x2": 0.9, "y2": .number(v)]])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(try XCTUnwrap(info["horizon"]?["inclinaison"]?.double), 2, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(info["crop"]?["angle"]?.double), -2, accuracy: 0.1)
        XCTAssertEqual(info["horizon"]?["angle_de_recadrage_actuel"]?.double, -2)
        XCTAssertEqual(try XCTUnwrap(info["horizon"]?["hauteur_dans_le_cadre_actuel"]?.double), v, accuracy: 0.002)
        XCTAssertEqual(try XCTUnwrap(info["horizon"]?["hauteur"]?.double), yMilieu, accuracy: 0.002)
        XCTAssertEqual(info["cadre_actuel"]?["angle"]?.double, -2)
        XCTAssertEqual(try XCTUnwrap(info["cadre_actuel"]?["size"]?.double), 0.8 / Composition.plusGrandeLargeur(ratio: 1.5, angle: -2, aspect: 1.5), accuracy: 1e-3)
        XCTAssertTrue(info["cadre_actuel"]?["resume"]?.string?.contains("redressé de 2°") == true)
    }

    /// Un horizon déjà droit sur l'image entière : l'angle actuel reste s'il le garde droit (moins de
    /// 0,5° d'écart), sinon le cadre proposé n'est plus tourné.
    func testUnHorizonDejaDroitGardeOuRetireLAngle() throws {
        // tiltedHorizon(degrees: 0) : l'horizon est à plat, en y = (896 − 400) / 896.
        let y = 496.0 / 896
        func lire(angleActuel: Double) throws -> JSONValue {
            let largeur = Composition.plusGrandeLargeur(ratio: 1.5, angle: angleActuel, aspect: 1.5)
            let cadre = Composition.Cadre(centreX: 0.5, centreY: 0.5, largeur: largeur, ratio: 1.5, angle: angleActuel)
            var reponse = Self.entiere
            reponse["cadre_actuel"] = ["ratio": 1.5, "angle": .number(angleActuel), "centre_x": 0.5, "centre_y": 0.5, "largeur": .number(largeur * 6240)]
            reponse["a_savoir"] = "calculs IA en attente"
            repondreApercu(reponse, image: AnalyseTests.tiltedHorizon(degrees: 0))
            // Les deux points, vus dans l'image recadrée et tournée.
            let a = Composition.depuisImageEntiere(CGPoint(x: 0.15, y: y), cadre: cadre, aspect: 1.5)
            let b = Composition.depuisImageEntiere(CGPoint(x: 0.85, y: y), cadre: cadre, aspect: 1.5)
            let result = tools.call(name: "read_composition", arguments: ["horizon": ["x1": .number(Double(a.x)), "y1": .number(Double(a.y)),
                                                                                     "x2": .number(Double(b.x)), "y2": .number(Double(b.y))]])
            XCTAssertFalse(result.isError, result.text)
            return try JSONCoding.parse(result.text)
        }
        let leger = try lire(angleActuel: -0.3)
        XCTAssertEqual(try XCTUnwrap(leger["horizon"]?["inclinaison"]?.double), 0, accuracy: 0.1)
        XCTAssertEqual(leger["crop"]?["angle"]?.double, -0.3, "l'angle actuel le garde droit : il reste")
        XCTAssertEqual(leger["cadre_propose"]?["regles_tenues"]?.array?.first?.string, "horizon droit")
        XCTAssertEqual(leger["a_savoir"]?.string, "calculs IA en attente", "les remarques du module suivent")
        let tourne = try lire(angleActuel: 1.5)
        XCTAssertEqual(tourne["crop"]?["angle"]?.double, 0, "l'angle actuel pencherait l'horizon : retiré")
        XCTAssertTrue(tourne["lecture"]?.array?.first?.string == "L'horizon est droit.")
    }

    func testReadCompositionRefuseCeQuIlNeConnaitPas() throws {
        let essais: [([String: JSONValue], String)] = [
            (["horizon": ["x1": 0.1, "y1": 0.5, "x2": 0.9, "y2": 0.5, "z": 1]], "« horizon » : clés inconnues : z"),
            (["horizon": ["x": 0.1, "y1": 0.5, "x2": 0.9, "y2": 0.5]], "x (ici : « x1 »)"),
            (["horizon": ["x1": 1.5, "y1": 0.5, "x2": 0.9, "y2": 0.5]], "« horizon.x1 » va de 0 à 1"),
            (["subject": ["x": 0.1, "y": 0.2, "w": 0.2, "h": 0.3]], "w (ici : « width »)"),
            (["subject": ["x": 0.9, "y": 0.2, "width": 0.2, "height": 0.3]], "doit tenir dans l'image"),
            (["facing": "up"], "« facing » vaut left, right, none"),
            (["subject_place": "edge"], "« subject_place » vaut third, center"),
            (["horizon_third": "middle"], "« horizon_third » vaut lower, upper"),
            (["size": 0.3], "« size » va de 0,5 à 1"),
            (["min_size": 1.2], "« min_size » va de 0,5 à 1"),
            (["aspect": "carré"], "« aspect » s'écrit comme « 4:5 »"),
            (["photo_ids": [1]], "Paramètres inconnus pour read_composition : photo_ids (ici : « photo_id »)"),
        ]
        for (arguments, attendu) in essais {
            let result = tools.call(name: "read_composition", arguments: arguments)
            XCTAssertTrue(result.isError, "\(arguments)")
            XCTAssertTrue(result.text.contains(attendu), result.text)
        }
        XCTAssertTrue(fake.calls.isEmpty, "rien n'est envoyé au module : \(fake.commands)")
    }

    /// Un module d'avant la 1.3 ignore entier et rend l'image recadrée : refusée, son fichier effacé.
    func testUnModuleQuiNeRendPasLImageEntiereEstRefuse() throws {
        let chemin = TestSupport.previewFile(TestSupport.jpeg(red: 90, green: 90, blue: 90))
        fake.replies["apercu"] = ["chemin": .string(chemin), "photo": ["id": 3]]
        let result = tools.call(name: "read_composition", arguments: [:])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("n'a pas rendu l'image entière"), result.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chemin), "aperçu effacé")

        // Un cadre actuel sans dimensions ne se lit pas : rien n'est deviné.
        repondreApercu(["image_entiere": true, "cadre_actuel": ["ratio": 1.5, "angle": 0, "centre_x": 0.5, "centre_y": 0.5, "largeur": 3000]])
        let sansDimensions = tools.call(name: "read_composition", arguments: [:])
        XCTAssertTrue(sansDimensions.isError)
        XCTAssertTrue(sansDimensions.text.contains("Cadre actuel de la photo illisible"), sansDimensions.text)
    }

    /// Un visage tourné vers la droite (lacet de Vision) va sur le tiers gauche, les yeux sur le
    /// tiers haut ; facing prime sur le lacet.
    func testLeRegardPlaceLeSujetEtFacingPrime() throws {
        let visage = VisionReport.Face(box: CGRect(x: 0.45, y: 0.325, width: 0.1, height: 0.15),
                                       pupils: [CGPoint(x: 0.48, y: 0.38), CGPoint(x: 0.52, y: 0.38)],
                                       eyeWidth: nil, quality: nil, eyeOpenness: nil, yaw: 0.6 * Composition.signeLacet)
        let rapport = VisionReport(faces: [visage], aesthetics: nil, utility: nil, salientArea: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
        func lire(_ arguments: [String: JSONValue]) throws -> JSONValue {
            fake.calls = []
            repondreApercu(Self.entiere, image: TestSupport.jpeg(red: 120, green: 120, blue: 120, width: 1344, height: 896))
            return try tools.readComposition(Arguments(raw: arguments), vision: { _ in rapport })
        }
        func place(_ info: JSONValue) throws -> CGPoint {
            let crop = try XCTUnwrap(info["crop"])
            let cadre = Composition.Cadre(centreX: try XCTUnwrap(crop["center_x"]?.double), centreY: try XCTUnwrap(crop["center_y"]?.double),
                                          largeur: try XCTUnwrap(crop["size"]?.double) * Composition.plusGrandeLargeur(ratio: 1.5, angle: 0, aspect: 1.5),
                                          ratio: 1.5, angle: try XCTUnwrap(crop["angle"]?.double))
            return Composition.depuisImageEntiere(CGPoint(x: 0.5, y: 0.38), cadre: cadre, aspect: 1.5)
        }
        let lu = try lire([:])
        XCTAssertEqual(lu["sujet"]?["source"]?.string, "visages")
        XCTAssertEqual(lu["sujet"]?["regard"]?.string, "vers la droite de l'image (lu par Vision, à vérifier)")
        XCTAssertEqual(Double(try place(lu).x), 1.0 / 3, accuracy: 0.01, "regard vers la droite : sur le tiers gauche")
        XCTAssertEqual(Double(try place(lu).y), 1.0 / 3, accuracy: 0.01, "les yeux sur le tiers haut")
        XCTAssertTrue(lu["cadre_propose"]?["regles_tenues"]?.array?.contains("yeux sur le tiers haut") == true, "\(lu)")
        XCTAssertTrue(lu["lecture"]?.array?.contains { $0.string?.hasPrefix("Le visage est au centre et regarde vers la droite (lu par Vision") == true } == true)

        let impose = try lire(["facing": "left"])
        XCTAssertEqual(impose["sujet"]?["regard"]?.string, "vers la gauche de l'image (facing)")
        XCTAssertEqual(Double(try place(impose).x), 2.0 / 3, accuracy: 0.01, "facing prime sur le lacet")

        let centre = try lire(["subject_place": "center"])
        XCTAssertEqual(Double(try place(centre).x), 0.5, accuracy: 0.01)

        // Un sujet donné passe avant les visages.
        let donne = try lire(["subject": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2]])
        XCTAssertEqual(donne["sujet"]?["source"]?.string, "donne")
        XCTAssertNil(donne["sujet"]?["regard"], "le lacet d'un visage ne vaut pas pour un sujet donné")
    }

    // MARK: preview_settings, surimpression

    /// L'essai du faux module avec un recadrage : l'image recadrée (claire), l'image entière (grise)
    /// et le cadre que Lightroom a gardé (les deux tiers du milieu).
    func repondreEssai(cadre: JSONValue? = ["ratio": 1.5, "angle": 0, "centre_x": 0.5, "centre_y": 0.5, "largeur": 4160],
                       actuel: Bool = false) -> (recadree: String, entiere: String) {
        let recadree = TestSupport.previewFile(TestSupport.jpeg(red: 200, green: 200, blue: 200, width: 896, height: 597))
        let entiere = TestSupport.previewFile(PreviewImages.jpeg(Self.gris(128), quality: 1)!)
        var reponse: [String: JSONValue] = ["chemin": .string(recadree), "chemin_entier": .string(entiere),
                                            "dimensions": ["largeur": 6240, "hauteur": 4160], "photo": ["id": 3],
                                            "changements": [["cle": "CropLeft", "avant": 0, "apres": 0.1667]]]
        if let cadre { reponse["cadre_propose"] = cadre }
        if actuel { reponse["chemin_actuel"] = .string(TestSupport.previewFile(TestSupport.jpeg(red: 90, green: 90, blue: 90))) }
        fake.replies["essayer"] = .object(reponse)
        return (recadree, entiere)
    }

    func testPreviewSettingsDessineLeCadreSurLImageEntiere() throws {
        let fichiers = repondreEssai()
        let result = tools.call(name: "preview_settings", arguments: ["crop": ["aspect": "3:2", "size": 0.667], "photo_id": 3, "step_name": "cadre"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.calls.last?.command, "essayer")
        XCTAssertEqual(fake.lastParams["entier"]?.bool, true)
        XCTAssertNotNil(fake.lastParams["recadrage"])
        guard case .image(let base64, _) = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("image attendue") }
        XCTAssertEqual(result.content.filter { if case .image = $0 { return true }; return false }.count, 1, "une seule image")
        XCTAssertEqual(image.width, 1344, "aux dimensions de l'image entière")
        XCTAssertEqual(image.height, 896)
        XCTAssertLessThanOrEqual(Self.niveau(image, 40, 40), 0.55 * 128, "hors-cadre assombri")
        XCTAssertEqual(Self.niveau(image, 672, 448), 128, accuracy: 8, "milieu du cadre inchangé")
        // Le cadre va de 1/6 à 5/6 de la largeur : son tiers gauche est à 1/6 + 2/9.
        XCTAssertGreaterThan(Self.niveau(image, Int((1.0 / 6 + 2.0 / 9) * 1344), 300), 160, "tiers plus clair")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["resume_cadre"]?.string, "3:2 (format d'origine), 67 % de la largeur gardée")
        XCTAssertEqual(try XCTUnwrap(info["cadre_propose"]?["largeur"]?.double), 0.667, accuracy: 0.001)
        XCTAssertNil(info["chemin_entier"])
        XCTAssertNil(info["dimensions"])
        XCTAssertTrue(info["image"]?.string?.hasPrefix("L'image entière : le cadre proposé en pointillés") == true)
        // Les mesures restent celles de l'image recadrée (claire), pas de l'image entière (grise).
        XCTAssertGreaterThan(try XCTUnwrap(info["mesures_proposition"]?["luminosite_L"]?["moyenne"]?.double), 75)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichiers.recadree), "aperçus effacés")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichiers.entiere))
    }

    func testPreviewSettingsSansSurimpression() throws {
        for arguments: [String: JSONValue] in [["settings": ["Exposure2012": 0.3]], ["crop": ["reset": true]],
                                                ["crop": ["angle": -1.2], "overlay": false]] {
            fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 9, green: 9, blue: 9)))]
            let result = tools.call(name: "preview_settings", arguments: arguments)
            XCTAssertFalse(result.isError, result.text)
            XCTAssertEqual(fake.calls.last?.command, "essayer")
            XCTAssertNil(fake.lastParams["entier"], "\(arguments)")
            XCTAssertNil(try JSONCoding.parse(result.text)["resume_cadre"])
        }
        fake.replies["essayer"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 9, green: 9, blue: 9)))]
        let avecCadre = tools.call(name: "preview_settings", arguments: ["crop": ["angle": -1.2]])
        XCTAssertEqual(fake.lastParams["entier"]?.bool, true, "overlay vaut true par défaut")
        XCTAssertFalse(avecCadre.isError, avecCadre.text)
    }

    func testPreviewSettingsCompareAvecLeCadre() throws {
        _ = repondreEssai(actuel: true)
        let result = tools.call(name: "preview_settings", arguments: ["crop": ["aspect": "3:2", "size": 0.667], "compare": true])
        XCTAssertFalse(result.isError, result.text)
        guard case .image(let base64, _) = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("image attendue") }
        XCTAssertEqual(image.width, 300 + 4 + 300, "l'état actuel et l'image entière dessinée, côte à côte")
        let info = try JSONCoding.parse(result.text)
        XCTAssertTrue(info["image"]?.string?.contains("à droite l'image entière avec le cadre proposé") == true)
        XCTAssertNotNil(info["bilan"], "le bilan reste mesuré sur l'image recadrée")
        XCTAssertNotNil(info["resume_cadre"])
    }

    /// Sans cadre gardé (ou illisible), l'image recadrée reste montrée, la raison dite, et l'image
    /// entière effacée quand même.
    func testSansCadreGardeLaPropositionResteMontree() throws {
        let fichiers = repondreEssai(cadre: nil)
        let result = tools.call(name: "preview_settings", arguments: ["crop": ["angle": 0.5]])
        XCTAssertFalse(result.isError, result.text)
        guard case .image(let base64, _) = result.content.first, let image = PreviewImages.image(Data(base64Encoded: base64)!) else {
            return XCTFail("image attendue")
        }
        XCTAssertEqual(image.width, 896, "l'image recadrée")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["remarque_cadre"]?.string, "Lightroom n'a gardé aucun recadrage : l'image montre la proposition.")
        XCTAssertNil(info["resume_cadre"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fichiers.entiere))

        _ = repondreEssai(cadre: ["ratio": 1.5])
        let illisible = try JSONCoding.parse(tools.call(name: "preview_settings", arguments: ["crop": ["angle": 0.5]]).text)
        XCTAssertEqual(illisible["remarque_cadre"]?.string, "Cadre gardé par Lightroom illisible : l'image montre la proposition recadrée.")
        XCTAssertNil(illisible["cadre_propose"], "pas de cadre en chiffres faux")
    }
}
