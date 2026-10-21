import CoreGraphics
import XCTest
@testable import DeveloppeurKit

/// Version 1.2 : bilan chiffré d'une passe à l'autre (`Bilan`), en fonctions pures, et les seuils
/// nommés qu'il reprend. Les essais qui passent par view_photo et preview_settings viennent avec
/// leur branchement dans les outils.
final class BilanTests: XCTestCase {
    // MARK: Aides

    /// Mesures construites à la main : seules comptent celles que le bilan compare.
    func mesures(mediane: Double = 50, p5: Double = 10, p95: Double = 90, hautes: Double = 0, blanc: Double = 0,
                 ombres: Double = 0, canaux: [Double] = [0, 0, 0], chroma: Double = 12, saturee: Double = 0,
                 a: Double = 0, b: Double = 0, part: Double = 30) -> PhotoMeasurements {
        PhotoMeasurements(meanL: mediane, percentilesL: [1: p5, 5: p5, 25: mediane, 50: mediane, 75: mediane, 95: p95, 99: p95],
                          histogramL: [Double](repeating: 10, count: 10), clippedHighlights: hautes, pureWhite: blanc,
                          crushedShadows: ombres, clippedChannels: canaux, meanChroma: chroma, saturatedShare: saturee,
                          neutralA: a, neutralB: b, neutralShare: part, pixelCount: 512 * 341)
    }

    func detail(nettete: Double, bruit: Double, ombres: Double? = nil, side: Int = 1024) -> DetailMeasurements {
        DetailMeasurements(zones: [Double](repeating: nettete * 0.8, count: 8) + [nettete], noise: bruit, shadowNoise: ombres, side: side)
    }

    let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func vue(_ mesures: PhotoMeasurements, detail: DetailMeasurements? = nil, apres secondes: Double = 0, taille: Int = 1344,
             cadre: String = "cadre", etat: String = "état 1", etapes: Int? = 1, derniere: String? = "Claude · passe 1",
             neutres: Measurements.NeutresSuivis? = nil, ia: Bool = false, corrections: String? = nil, grain: Double = 0) -> Bilan.Vue {
        Bilan.Vue(photo: 7, fichier: "DSCF2402.RAF", quand: t0.addingTimeInterval(secondes), taille: taille, cadre: cadre, etat: etat,
                  etapes: etapes, derniereEtape: derniere, mesures: mesures, detail: detail, neutres: neutres,
                  iaEnAttente: ia, corrections: corrections, grain: grain)
    }

    func comparer(_ avant: PhotoMeasurements, _ apres: PhotoMeasurements, detailAvant: DetailMeasurements? = nil,
                  detailApres: DetailMeasurements? = nil, cadreChange: Bool = false, grain: Bool = false) -> Bilan.Comparaison {
        Bilan.comparer(avant: avant, apres: apres, detailAvant: detailAvant, detailApres: detailApres,
                       neutresAvant: nil, neutresApres: nil, suivis: false, cadreChange: cadreChange, grainAjoute: grain)
    }

    /// Le bilan d'une deuxième vue, comparée à la première (aussi le départ).
    func bilan(_ avant: Bilan.Vue, _ apres: Bilan.Vue, suivi: Measurements.NeutresSuivis? = nil) -> JSONValue {
        Bilan.session(precedente: avant, depart: avant, maintenant: apres, suiviPrecedente: suivi, suiviDepart: suivi,
                      date: apres.quand)
    }

    func textes(_ valeur: JSONValue?) -> [String] { valeur?.array?.compactMap(\.string) ?? [] }

    /// L* qui donne `il` IL de plus que `l` (luminance relative multipliée par 2^il).
    func clarte(_ l: Double, plus il: Double) -> Double { 116 * cbrt(Measurements.luminance(l) * pow(2, il)) - 16 }

    /// Réponse « apercu » du module, avec la géométrie que donne point_af.
    func apercu(hauteur: Int = 4160, upright: Double = 0, exposition: Double = 0, angle: Double = 0,
                etapes: JSONValue? = ["nombre": 1, "derniere": "Claude · passe 1"], extra: [String: JSONValue] = [:]) -> JSONValue {
        var reglages: [String: JSONValue] = ["Exposure2012": .number(exposition), "PerspectiveUpright": .number(upright),
                                             "LensProfileVignettingScale": 100]
        for (cle, valeur) in extra { reglages[cle] = valeur }
        var objet: [String: JSONValue] = [
            "photo": ["id": 7, "fichier": "DSCF2402.RAF",
                      "geometrie": ["largeur": 6240, "hauteur": .number(Double(hauteur)), "orientation": "AB"]],
            "recadrage": ["recadree": false, "angle": .number(angle)],
            "reglages": .object(reglages),
            "profil": "Classic Chrome",
        ]
        if let etapes { objet["etapes_claude"] = etapes }
        return .object(objet)
    }

    // MARK: Seuils nommés

    func testNamedThresholdsKeepTheirValues() {
        XCTAssertEqual(DetailMeasurements.seuilFlou, 15)
        XCTAssertEqual(DetailMeasurements.seuilNet, 35)
        XCTAssertEqual(DetailMeasurements.bruitVisible, 0.6)
        XCTAssertEqual(DetailMeasurements.bruitFort, 1.5)
        XCTAssertEqual(Measurements.seuilChroma, 3)
        XCTAssertEqual(PhotoMeasurements.partNeutreMin, 3)
        XCTAssertEqual(PhotoMeasurements.dominanteLegere, 2)
        XCTAssertEqual(PhotoMeasurements.dominanteNette, 6)
        XCTAssertEqual(PhotoMeasurements.chromaTresSaturee, 60)
        // Les seuils de visibilité du bilan sont ceux de match_series.
        XCTAssertEqual(Bilan.seuilExposition, 0.1)
        XCTAssertEqual(Bilan.seuilContraste, 4)
        XCTAssertEqual(Bilan.seuilDominante, 1.5)
        XCTAssertEqual(Bilan.seuilChroma, 3)

        // Les textes qui les citent n'ont pas changé.
        let base = detail(nettete: 50, bruit: 0.3).json["base_detail"]?.string ?? ""
        XCTAssertTrue(base.contains("moins de 15 : flou probable ; plus de 35 : net"), base)
        XCTAssertTrue(base.contains("moins de 0,6 : faible"), base)
        XCTAssertEqual(detail(nettete: 14.9, bruit: 0.59).sharpnessReading, "floue probable : aucune zone nette")
        XCTAssertEqual(detail(nettete: 14.9, bruit: 0.59).noiseReading, "faible")
        XCTAssertTrue(detail(nettete: 35, bruit: 0.6).sharpnessReading.hasPrefix("nette"))
        XCTAssertTrue(detail(nettete: 35, bruit: 0.6).noiseReading.hasPrefix("visible"))
        var douce = PhotoTriee(id: 1, fichier: "a.jpg")
        douce.detail = detail(nettete: 30, bruit: 0.3)
        XCTAssertEqual(Notation.plafond(douce, doublon: false)?.raison, "douce (netteté 30 ; nette à partir de 35)")
        XCTAssertEqual(mesures(b: 2.1, part: 3).castReading, "dominante légèrement chaude (jaune)")
        XCTAssertEqual(mesures(b: 6.1, part: 3).castReading, "dominante nettement chaude (jaune)")
        XCTAssertEqual(mesures(b: 6.1, part: 2.9).castReading, "trop peu de tons neutres pour juger la dominante")
    }

    func testFrenchNumbers() {
        XCTAssertEqual(Bilan.nombre(2.6), "2,6")
        XCTAssertEqual(Bilan.nombre(2.2, signe: true), "+2,2")
        XCTAssertEqual(Bilan.nombre(-0.3), "−0,3")
        XCTAssertEqual(Bilan.nombre(-0.3, signe: true), "−0,3")
        XCTAssertEqual(Bilan.nombre(-0.04, signe: true), "0,0", "pas de « −0,0 »")
        XCTAssertEqual(Bilan.nombre(42), "42,0")
        XCTAssertEqual(Bilan.nombre(0.45, decimales: 2), "0,45")
        XCTAssertEqual(Bilan.nombre(35, decimales: 0), "35")
    }

    // MARK: Tons neutres sur une image décodée

    func testNeutralsOfADecodedImageAreTrackedLikeTheJPEGOnes() throws {
        func image(gauche: (UInt8, UInt8, UInt8), largeur: Int = 1024, hauteur: Int = 512) -> Data {
            var pixels = [UInt8](repeating: 255, count: largeur * hauteur * 4)
            for y in 0..<hauteur {
                for x in 0..<largeur {
                    let i = (y * largeur + x) * 4
                    (pixels[i], pixels[i + 1], pixels[i + 2]) = x < largeur / 2 ? gauche : (200, 30, 30)
                }
            }
            return TriTests.encode(pixels, width: largeur, height: hauteur)
        }
        let grise = try XCTUnwrap(PreviewImages.image(image(gauche: (128, 128, 128))))
        let avant = try XCTUnwrap(Measurements.neutres(grise))
        XCTAssertEqual(avant.masque.count, 512 * 256, "réduite à Measurements.maxSide, comme analyzeScaled")
        XCTAssertEqual(avant.part, 50, accuracy: 2)
        XCTAssertEqual(avant.b, 0, accuracy: 1)
        let parJPEG = try XCTUnwrap(Measurements.neutres(image(gauche: (128, 128, 128))))
        XCTAssertEqual(parJPEG.masque.count, avant.masque.count, "même réduction que le JPEG lu par ImageIO")
        XCTAssertEqual(parJPEG.part, avant.part, accuracy: 1)

        let rechauffee = try XCTUnwrap(PreviewImages.image(image(gauche: (150, 128, 95))))
        let suivis = try XCTUnwrap(Measurements.neutres(rechauffee, masque: avant.masque))
        XCTAssertGreaterThan(suivis.b, 18, "les mêmes pixels, devenus jaunes")
        XCTAssertEqual(suivis.part, avant.part, accuracy: 0.01)
        XCTAssertLessThan(try XCTUnwrap(Measurements.neutres(rechauffee)).part, 5, "une sélection refaite les perd")
        // Un aperçu plus grand de même cadre se réduit au même nombre de pixels.
        let grande = try XCTUnwrap(PreviewImages.image(image(gauche: (128, 128, 128), largeur: 2048, hauteur: 1024)))
        XCTAssertNotNil(Measurements.neutres(grande, masque: avant.masque))
        // Un autre cadre, non.
        let autre = try XCTUnwrap(PreviewImages.image(image(gauche: (128, 128, 128), largeur: 1024, hauteur: 768)))
        XCTAssertNil(Measurements.neutres(autre, masque: avant.masque))
    }

    // MARK: Régressions

    func testHighlightClippingIsARegression() {
        let brulee = comparer(mesures(hautes: 0.4), mesures(hautes: 2.6))
        XCTAssertEqual(brulee.regressions.map(\.texte), ["hautes lumières écrêtées : 0,4 → 2,6 % (+2,2 points)"])
        XCTAssertEqual(brulee.regressions.first?.defaut, .ecretage)
        XCTAssertEqual(brulee.ecarts["hautes_lumieres_pct"]?["ecart"]?.double ?? 0, 2.2, accuracy: 0.001)

        let peu = comparer(mesures(hautes: 0.4), mesures(hautes: 0.8))
        XCTAssertTrue(peu.regressions.isEmpty, "sous 1 % : visible, pas une régression")
        XCTAssertNotNil(peu.ecarts["hautes_lumieres_pct"])
        XCTAssertTrue(comparer(mesures(hautes: 0.4), mesures(hautes: 0.6)).sansEcart.contains("hautes_lumieres_pct"))
        // Une part déjà forte doit monter de moitié.
        XCTAssertTrue(comparer(mesures(hautes: 4), mesures(hautes: 5.5)).regressions.isEmpty)
        XCTAssertEqual(comparer(mesures(hautes: 4), mesures(hautes: 6.1)).regressions.count, 1)

        let ombres = comparer(mesures(ombres: 0.2), mesures(ombres: 1.8))
        XCTAssertEqual(ombres.regressions.map(\.texte), ["ombres bouchées : 0,2 → 1,8 %"])
        XCTAssertTrue(comparer(mesures(ombres: 0.2), mesures(ombres: 0.6)).regressions.isEmpty)

        let canal = comparer(mesures(hautes: 3, canaux: [0.8, 0.5, 0]), mesures(hautes: 3.2, canaux: [4.1, 0.6, 0]))
        XCTAssertEqual(canal.regressions.map(\.texte), ["canal rouge écrêté : 0,8 → 4,1 % (couleur poussée hors du sRGB ou brûlée)"])
        XCTAssertEqual(canal.ecarts["canal_ecrete"]?["canal"], "rouge")
        let lesDeux = comparer(mesures(hautes: 0.4, canaux: [0.4, 0, 0]), mesures(hautes: 4.5, canaux: [4.5, 0, 0]))
        XCTAssertEqual(lesDeux.regressions.map(\.defaut), [.ecretage], "le canal ne se redit pas sous l'écrêtage")

        let saturees = comparer(mesures(saturee: 3.1), mesures(saturee: 7.4))
        XCTAssertEqual(saturees.regressions.map(\.texte), ["couleurs très saturées (C* > 60) : 3,1 → 7,4 % des pixels"])
        XCTAssertTrue(comparer(mesures(saturee: 3.1), mesures(saturee: 4.5)).regressions.isEmpty)

        let rien = comparer(mesures(), mesures())
        XCTAssertTrue(rien.ecarts.isEmpty && rien.regressions.isEmpty && rien.aVerifier.isEmpty)
        XCTAssertEqual(Set(rien.sansEcart), ["exposition", "contraste", "hautes_lumieres_pct", "blanc_pur_pct", "ombres_bouchees_pct",
                                              "canal_ecrete", "dominante_a", "dominante_b", "chroma_moyenne", "tres_saturee_pct"])
    }

    func testUndoDoesNotReportARegression() {
        let avant = vue(mesures(hautes: 0.4), etapes: 2, derniere: "Claude · passe 2")
        let defaite = bilan(avant, vue(mesures(hautes: 2.6), apres: 30, etapes: 1, derniere: "Claude · passe 1"))
        XCTAssertNil(defaite["regression"], "\(defaite)")
        XCTAssertNil(defaite["conseil"])
        XCTAssertEqual(defaite["etapes_claude"], "1 de moins : retouche défaite (undo_last ou revert_to_original)")
        XCTAssertTrue(textes(defaite["a_verifier"]).contains("revenu après l'annulation : hautes lumières écrêtées : 0,4 → 2,6 % (+2,2 points)"),
                      "\(defaite)")

        // Une passe de plus : la même hausse est une régression, avec le conseil.
        let passe = bilan(avant, vue(mesures(hautes: 2.6), apres: 30, etapes: 3, derniere: "Claude · passe 3 : ciel"))
        XCTAssertEqual(textes(passe["regression"]), ["hautes lumières écrêtées : 0,4 → 2,6 % (+2,2 points)"])
        XCTAssertEqual(passe["etapes_claude"], "1 de plus (dernière : « Claude · passe 3 : ciel »)")
        XCTAssertTrue(passe["conseil"]?.string?.contains("undo_last") ?? false)

        // Calcul IA en attente sur l'un des rendus : à vérifier aussi.
        let ia = bilan(vue(mesures(hautes: 0.4), ia: true), vue(mesures(hautes: 2.6), apres: 30, etapes: 2))
        XCTAssertNil(ia["regression"])
        XCTAssertTrue(textes(ia["a_verifier"]).contains { $0.hasPrefix("calcul IA en attente sur l'un des rendus : hautes lumières") })
    }

    func testSharpnessCrossingAndDenoise() {
        let douce = comparer(mesures(), mesures(), detailAvant: detail(nettete: 42, bruit: 0.4), detailApres: detail(nettete: 31, bruit: 0.4))
        XCTAssertEqual(douce.regressions.map(\.texte), ["netteté passée de nette à douce : 42,0 → 31,0 (seuil 35)"])
        XCTAssertEqual(douce.ecarts["nettete_max"]?["lecture"], "nette → douce")
        XCTAssertTrue(douce.sansEcart.contains("bruit"))

        let debruitee = comparer(mesures(), mesures(), detailAvant: detail(nettete: 42, bruit: 1.8), detailApres: detail(nettete: 31, bruit: 0.9))
        XCTAssertTrue(debruitee.regressions.isEmpty, "\(debruitee.regressions)")
        XCTAssertEqual(debruitee.aVerifier.count, 1)
        XCTAssertTrue(debruitee.aVerifier[0].contains("débruitage"), debruitee.aVerifier[0])
        XCTAssertEqual(debruitee.ecarts["bruit"]?["lecture"], "fort → visible")

        XCTAssertTrue(comparer(mesures(), mesures(), detailAvant: detail(nettete: 36, bruit: 0.4),
                               detailApres: detail(nettete: 34, bruit: 0.4)).regressions.isEmpty, "une baisse de moins de 3")
        XCTAssertEqual(comparer(mesures(), mesures(), detailAvant: detail(nettete: 20, bruit: 0.4),
                                detailApres: detail(nettete: 10, bruit: 0.4)).regressions.map(\.texte),
                       ["netteté passée de douce à floue : 20,0 → 10,0 (seuil 15)"])
        // Mesurées à des tailles différentes, ou cadre changé : rien n'est comparé.
        let autreTaille = comparer(mesures(), mesures(), detailAvant: detail(nettete: 42, bruit: 0.4),
                                   detailApres: detail(nettete: 31, bruit: 0.4, side: 800))
        XCTAssertTrue(autreTaille.regressions.isEmpty)
        XCTAssertNil(autreTaille.ecarts["nettete_max"])
        XCTAssertFalse(autreTaille.sansEcart.contains("nettete_max"))
        XCTAssertTrue(comparer(mesures(), mesures(), detailAvant: detail(nettete: 42, bruit: 0.4),
                               detailApres: detail(nettete: 31, bruit: 0.4), cadreChange: true).regressions.isEmpty)

        // Des aperçus de tailles différentes : pas de netteté ni de bruit, et une remarque.
        let session = bilan(vue(mesures(), detail: detail(nettete: 42, bruit: 0.4)),
                            vue(mesures(), detail: detail(nettete: 31, bruit: 0.4), apres: 20, taille: 2048, etapes: 2))
        XCTAssertNil(session["ecarts"]?["nettete_max"])
        XCTAssertNil(session["regression"])
        XCTAssertFalse(textes(session["sans_ecart_visible"]).contains("nettete_max"))
        XCTAssertTrue(textes(session["remarques"]).contains("taille d'aperçu différente (1344 → 2048) : netteté et bruit non comparés"),
                      "\(session)")
    }

    func testNoiseCrossingAndGrain() {
        let bruitee = comparer(mesures(), mesures(), detailAvant: detail(nettete: 50, bruit: 0.45), detailApres: detail(nettete: 50, bruit: 0.72))
        XCTAssertEqual(bruitee.regressions.map(\.texte), ["bruit passé de faible à visible : 0,45 → 0,72 (seuil 0,6)"])
        XCTAssertEqual(bruitee.regressions.first?.defaut, .bruit)
        XCTAssertEqual(bruitee.ecarts["bruit"]?["ecart"]?.double ?? 0, 0.27, accuracy: 0.001)
        XCTAssertTrue(comparer(mesures(), mesures(), detailAvant: detail(nettete: 50, bruit: 0.55),
                               detailApres: detail(nettete: 50, bruit: 0.62)).regressions.isEmpty, "une hausse de moins de 0,1")
        XCTAssertEqual(comparer(mesures(), mesures(), detailAvant: detail(nettete: 50, bruit: 1.2),
                                detailApres: detail(nettete: 50, bruit: 1.6)).regressions.map(\.texte),
                       ["bruit passé de visible à fort : 1,20 → 1,60 (seuil 1,5)"])
        XCTAssertEqual(comparer(mesures(), mesures(), detailAvant: detail(nettete: 50, bruit: 0.3, ombres: 0.5),
                                detailApres: detail(nettete: 50, bruit: 0.3, ombres: 0.9)).regressions.count, 1,
                       "le bruit des ombres compte")

        // Le grain ajouté entre les deux vues : la hausse est à vérifier, pas une régression.
        let grain = bilan(vue(mesures(), detail: detail(nettete: 50, bruit: 0.45)),
                          vue(mesures(), detail: detail(nettete: 50, bruit: 0.72), apres: 20, etapes: 2, grain: 25))
        XCTAssertNil(grain["regression"], "\(grain)")
        XCTAssertTrue(textes(grain["a_verifier"]).contains { $0.contains("grain ajouté") }, "\(grain)")
    }

    // MARK: À vérifier

    func testCastFlipIsToVerify() {
        let inversee = comparer(mesures(b: 4.1, part: 20), mesures(b: -2.6, part: 20))
        XCTAssertTrue(inversee.regressions.isEmpty)
        XCTAssertEqual(inversee.aVerifier, ["dominante passée de chaude (b* +4,1) à froide (b* −2,6) sur les tons neutres : correction dépassée ?"])
        XCTAssertEqual(inversee.ecarts["dominante_b"]?["suivie"], false)

        // Sur les mêmes tons neutres, suivis d'une vue à l'autre.
        let masque = [Bool](repeating: true, count: 4)
        let suivie = Bilan.comparer(avant: mesures(b: 9, part: 20), apres: mesures(b: 9, part: 20), detailAvant: nil, detailApres: nil,
                                    neutresAvant: .init(a: 0, b: 4.1, part: 20, masque: masque),
                                    neutresApres: .init(a: 0, b: -2.6, part: 20, masque: masque),
                                    suivis: true, cadreChange: false, grainAjoute: false)
        XCTAssertEqual(suivie.aVerifier, ["dominante passée de chaude (b* +4,1) à froide (b* −2,6) sur les mêmes tons neutres : correction dépassée ?"])
        XCTAssertEqual(suivie.ecarts["dominante_b"]?["suivie"], true)
        XCTAssertEqual(suivie.ecarts["dominante_b"]?["ecart"]?.double ?? 0, -6.7, accuracy: 0.001)

        XCTAssertEqual(comparer(mesures(a: -2.5, part: 20), mesures(a: 3, part: 20)).aVerifier,
                       ["dominante passée de verte (a* −2,5) à magenta (a* +3,0) sur les tons neutres : correction dépassée ?"])
        XCTAssertTrue(comparer(mesures(b: 1.5, part: 20), mesures(b: -2.6, part: 20)).aVerifier.isEmpty, "légère d'un seul côté")
        let sansNeutres = comparer(mesures(b: 4.1, part: 2), mesures(b: -2.6, part: 20))
        XCTAssertTrue(sansNeutres.aVerifier.isEmpty)
        XCTAssertNil(sansNeutres.ecarts["dominante_b"])
        XCTAssertEqual(sansNeutres.remarques, ["dominante non comparée : moins de 3 % de tons neutres"])
    }

    func testBackAndForthAcrossPasses() throws {
        let l1 = 50.0, l2 = clarte(l1, plus: 0.5), l3 = clarte(l2, plus: -0.3)
        let premiere = vue(mesures(mediane: l1), etapes: 1)
        let deuxieme = vue(mesures(mediane: l2), apres: 60, etapes: 2, derniere: "Claude · passe 2")
        let troisieme = vue(mesures(mediane: l3), apres: 185, etapes: 3, derniere: "Claude · passe 3")

        let b2 = Bilan.session(precedente: premiere, depart: premiere, maintenant: deuxieme, suiviPrecedente: nil, suiviDepart: nil, date: deuxieme.quand)
        XCTAssertEqual(b2["ecarts"]?["exposition"]?["IL"]?.double ?? 0, 0.5, accuracy: 0.001)
        XCTAssertNil(b2["depuis_le_debut"], "le départ est la vue précédente")
        XCTAssertNil(b2["a_verifier"])
        XCTAssertEqual(b2["depuis"], "le view_photo précédent de cette photo, il y a 1 min 00 s")

        let b3 = Bilan.session(precedente: deuxieme, depart: premiere, maintenant: troisieme, suiviPrecedente: nil, suiviDepart: nil, date: troisieme.quand)
        XCTAssertTrue(textes(b3["a_verifier"]).contains("aller-retour de l'exposition : +0,50 IL à la passe précédente, −0,30 IL depuis : des réglages empilés font dériver la photo"),
                      "\(b3)")
        let debut = try XCTUnwrap(b3["depuis_le_debut"])
        XCTAssertEqual(debut["depuis"], "le premier view_photo de la session, il y a 3 min 05 s")
        XCTAssertEqual(debut["ecarts"]?["exposition"]?["IL"]?.double ?? 0, 0.2, accuracy: 0.001)

        // Dominante b* sur les tons neutres suivis : +1,9 à la passe précédente, −1,8 depuis.
        let masque = [Bool](repeating: true, count: 4)
        let p = vue(mesures(), neutres: .init(a: 0, b: 0, part: 30, masque: masque))
        let q = vue(mesures(), apres: 60, etapes: 2, derniere: "Claude · passe 2", neutres: .init(a: 0, b: 2.0, part: 30, masque: masque))
        let r = vue(mesures(), apres: 120, etapes: 3, derniere: "Claude · passe 3")
        let couleur = Bilan.session(precedente: q, depart: p, maintenant: r, suiviPrecedente: .init(a: 0, b: 0.2, part: 30, masque: masque),
                                    suiviDepart: .init(a: 0, b: 0.1, part: 30, masque: masque), date: r.quand)
        XCTAssertTrue(textes(couleur["a_verifier"]).contains { $0.hasPrefix("aller-retour de la dominante (b*) : +1,9 à la passe précédente, −1,8 depuis") },
                      "\(couleur)")
        // Une dérive dans le même sens n'est pas un aller-retour.
        let monte = vue(mesures(mediane: clarte(l2, plus: 0.3)), apres: 185, etapes: 3)
        XCTAssertTrue(textes(Bilan.session(precedente: deuxieme, depart: premiere, maintenant: monte, suiviPrecedente: nil,
                                           suiviDepart: nil, date: monte.quand)["a_verifier"]).isEmpty)
        // Une annulation ramène la passe précédente en arrière : ce n'est pas un aller-retour.
        let defaite = vue(mesures(mediane: l1), apres: 185, etapes: 1)
        let annulee = Bilan.session(precedente: deuxieme, depart: premiere, maintenant: defaite, suiviPrecedente: nil,
                                    suiviDepart: nil, date: defaite.quand)
        XCTAssertEqual(annulee["etapes_claude"], "1 de moins : retouche défaite (undo_last ou revert_to_original)")
        XCTAssertNotNil(annulee["ecarts"]?["exposition"])
        XCTAssertFalse(textes(annulee["a_verifier"]).contains { $0.hasPrefix("aller-retour") }, "\(annulee)")
    }

    func testSlowDriftShowsSinceTheStart() {
        // Trois petites passes : aucune n'écrête assez, leur somme si.
        let depart = vue(mesures(hautes: 0.4), etapes: 1)
        let precedente = vue(mesures(hautes: 0.8), apres: 60, etapes: 2)
        let maintenant = vue(mesures(hautes: 1.2), apres: 120, etapes: 3)
        let b = Bilan.session(precedente: precedente, depart: depart, maintenant: maintenant, suiviPrecedente: nil, suiviDepart: nil, date: maintenant.quand)
        XCTAssertNil(b["regression"])
        XCTAssertEqual(textes(b["depuis_le_debut"]?["regression"]), ["hautes lumières écrêtées : 0,4 → 1,2 % (+0,8 point)"])
        XCTAssertNotNil(b["conseil"])
        // Déjà signalée à la vue précédente : pas redite.
        let forte = vue(mesures(hautes: 3), apres: 120, etapes: 3)
        let b2 = Bilan.session(precedente: precedente, depart: depart, maintenant: forte, suiviPrecedente: nil, suiviDepart: nil, date: forte.quand)
        XCTAssertEqual(textes(b2["regression"]).count, 1)
        XCTAssertNil(b2["depuis_le_debut"]?["regression"])
    }

    func testWhiteCornersAfterGeometryChange() throws {
        let avant = apercu(upright: 0)
        let apres = apercu(hauteur: 3900, upright: 2, etapes: ["nombre": 2, "derniere": "Claude · passe 1 : géométrie"])
        XCTAssertNotEqual(Bilan.cadre(avant), Bilan.cadre(apres))
        let v1 = try XCTUnwrap(Bilan.Vue(apercu: avant, quand: t0, taille: 1344, mesures: mesures(), detail: detail(nettete: 50, bruit: 0.3), neutres: nil))
        let v2 = try XCTUnwrap(Bilan.Vue(apercu: apres, quand: t0.addingTimeInterval(40), taille: 1344, mesures: mesures(hautes: 6.2, blanc: 6),
                                         detail: detail(nettete: 30, bruit: 0.3), neutres: nil))
        let b = bilan(v1, v2)
        XCTAssertNil(b["regression"], "\(b)")
        XCTAssertTrue(textes(b["a_verifier"]).contains { $0.contains("coins vides possibles (Upright, perspective)") }, "\(b)")
        XCTAssertTrue(textes(b["remarques"]).contains { $0.hasPrefix("cadre changé") })
        XCTAssertNil(b["ecarts"]?["nettete_max"], "netteté non comparée après un changement de cadre")

        // Sans changement de cadre, le même blanc pur est une régression.
        var v3 = v2
        v3.cadre = v1.cadre
        XCTAssertEqual(textes(bilan(v1, v3)["regression"]).first, "hautes lumières écrêtées : 0,0 → 6,2 % (+6,2 points)")
        // Cadre changé, mais une hausse que le blanc pur n'explique pas : une régression aussi.
        var v4 = v2
        v4.mesures = mesures(hautes: 6.2, blanc: 1)
        XCTAssertEqual(textes(bilan(v1, v4)["regression"]).count, 1)
    }

    // MARK: Même état, empreintes

    func testSameStateTwice() throws {
        let reponse = apercu()
        let image = TestSupport.jpeg(red: 120, green: 110, blue: 100, width: 600, height: 400)
        let m = try XCTUnwrap(Measurements.analyze(image))
        let d = Detail.analyze(image)
        let v1 = try XCTUnwrap(Bilan.Vue(apercu: reponse, quand: t0, taille: 1344, mesures: m, detail: d, neutres: nil))
        let v2 = try XCTUnwrap(Bilan.Vue(apercu: reponse, quand: t0.addingTimeInterval(5), taille: 1344, mesures: m, detail: d, neutres: nil))
        let b = bilan(v1, v2)
        XCTAssertEqual(b["meme_etat"], "Rien n'a changé depuis le view_photo précédent (réglages, profil, cadre et étapes de Claude identiques).")
        XCTAssertEqual(b["etapes_claude"], "aucune nouvelle")
        XCTAssertNil(b["ecarts"])
        XCTAssertNil(b["regression"])
        XCTAssertNil(b["base"])

        // Mêmes réglages et étapes, mais l'image a changé : une remarque.
        var v3 = v2
        v3.mesures = mesures(mediane: 70)
        let change = bilan(v1, v3)
        XCTAssertNil(change["meme_etat"])
        XCTAssertNotNil(change["ecarts"]?["exposition"])
        XCTAssertTrue(textes(change["remarques"]).contains { $0.hasPrefix("réglages globaux et étapes identiques mais l'image a changé") })

        // Historique plein : même nombre d'étapes, une autre dernière.
        var v4 = v2
        v4.derniereEtape = "Claude · passe 3 : ciel"
        let pleine = bilan(v1, v4)
        XCTAssertNil(pleine["meme_etat"])
        XCTAssertEqual(pleine["etapes_claude"], "nouvelles (dernière : « Claude · passe 3 : ciel »)")
    }

    func testFingerprintsOfFrameAndState() {
        let base = apercu()
        XCTAssertEqual(Bilan.cadre(base), Bilan.cadre(apercu()), "stable d'une lecture à l'autre")
        XCTAssertEqual(Bilan.etat(base), Bilan.etat(apercu()))
        // L'exposition change l'état, pas le cadre.
        XCTAssertEqual(Bilan.cadre(base), Bilan.cadre(apercu(exposition: 0.5)))
        XCTAssertNotEqual(Bilan.etat(base), Bilan.etat(apercu(exposition: 0.5)))
        // Ce qui déforme l'image change le cadre.
        for extra: [String: JSONValue] in [["PerspectiveVertical": 20], ["LensManualDistortionAmount": 10],
                                           ["LensProfileEnable": 1], ["LensProfileDistortionScale": 80]] {
            XCTAssertNotEqual(Bilan.cadre(base), Bilan.cadre(apercu(extra: extra)), "\(extra)")
        }
        XCTAssertNotEqual(Bilan.cadre(base), Bilan.cadre(apercu(angle: 1.2)))
        XCTAssertNotEqual(Bilan.cadre(base), Bilan.cadre(apercu(hauteur: 4000)))
        // Le vignetage d'objectif ne déforme pas.
        XCTAssertEqual(Bilan.cadre(base), Bilan.cadre(apercu(extra: ["LensProfileVignettingScale": 50])))
        // Le profil et son intensité sont dans l'état.
        guard case .object(var autre) = base else { return XCTFail() }
        autre["intensite_profil"] = 80
        XCTAssertNotEqual(Bilan.etat(base), Bilan.etat(.object(autre)))
    }

    func testViewReadsTheModuleAnswer() throws {
        var reponse = apercu(extra: ["GrainAmount": 25])
        guard case .object(var objet) = reponse else { return XCTFail() }
        objet["a_savoir"] = "Lightroom n'avait pas fini de calculer les réglages IA"
        objet["corrections_utilisateur"] = ["etape": "Claude · passe 1", "changements": []]
        reponse = .object(objet)
        let v = try XCTUnwrap(Bilan.Vue(apercu: reponse, quand: t0, taille: 1344, mesures: mesures(), detail: nil, neutres: nil))
        XCTAssertEqual(v.photo, 7)
        XCTAssertEqual(v.fichier, "DSCF2402.RAF")
        XCTAssertEqual(v.etapes, 1)
        XCTAssertEqual(v.derniereEtape, "Claude · passe 1")
        XCTAssertEqual(v.grain, 25)
        XCTAssertTrue(v.iaEnAttente)
        XCTAssertNotNil(v.corrections)
        let sansEtape = try XCTUnwrap(Bilan.Vue(apercu: apercu(etapes: ["nombre": 0, "derniere": .null]), quand: t0, taille: 1344,
                                               mesures: mesures(), detail: nil, neutres: nil))
        XCTAssertEqual(sansEtape.etapes, 0)
        XCTAssertNil(sansEtape.derniereEtape)
        XCTAssertFalse(sansEtape.iaEnAttente)
        XCTAssertNil(sansEtape.corrections)
        XCTAssertNil(Bilan.Vue(apercu: ["photo": ["fichier": "a.jpg"]], quand: t0, taille: 1344, mesures: mesures(), detail: nil, neutres: nil))
        XCTAssertTrue(Bilan.premiereVue.contains("point de départ"), "le texte du premier view_photo d'une photo")

        // Un module 1.1.1 ne donne pas les étapes : le bilan se fait sans elles.
        let ancien = try XCTUnwrap(Bilan.Vue(apercu: apercu(etapes: nil), quand: t0, taille: 1344, mesures: mesures(), detail: nil, neutres: nil))
        XCTAssertNil(ancien.etapes)
        var suivante = ancien
        suivante.quand = t0.addingTimeInterval(10)
        suivante.mesures = mesures(mediane: 60)
        let b = bilan(ancien, suivante)
        XCTAssertNil(b["etapes_claude"])
        XCTAssertNotNil(b["ecarts"]?["exposition"])
    }

    /// Le module redonne les corrections à la main à chaque aperçu, jusqu'à la commande suivante
    /// de Claude : seules des corrections nouvelles ou changées depuis la vue précédente se disent.
    func testHandCorrectionsAreToldOnlyWhenNew() throws {
        var avecCorrections = apercu()
        guard case .object(var objet) = avecCorrections else { return XCTFail() }
        objet["corrections_utilisateur"] = ["etape": "Claude · passe 1",
                                            "changements": [["cle": "Exposure2012", "claude": 0.3, "maintenant": 0.6]]]
        avecCorrections = .object(objet)
        func vueDe(_ reponse: JSONValue, apres secondes: Double) throws -> Bilan.Vue {
            try XCTUnwrap(Bilan.Vue(apercu: reponse, quand: t0.addingTimeInterval(secondes), taille: 1344, mesures: mesures(), detail: nil, neutres: nil))
        }
        let ligne: JSONValue = "l'utilisateur a aussi retouché à la main : un écart peut venir de lui"
        let sans = try vueDe(apercu(), apres: 0), avec = try vueDe(avecCorrections, apres: 30), encore = try vueDe(avecCorrections, apres: 60)
        XCTAssertEqual(bilan(sans, avec)["corrections_utilisateur"], ligne, "nouvelles depuis la vue précédente")
        XCTAssertNil(bilan(avec, encore)["corrections_utilisateur"], "les mêmes qu'à la vue précédente : rien de neuf")
        XCTAssertNotNil(bilan(avec, encore)["meme_etat"])
        // D'autres corrections à la main depuis : de nouveau dites.
        objet["corrections_utilisateur"] = ["etape": "Claude · passe 1",
                                            "changements": [["cle": "Exposure2012", "claude": 0.3, "maintenant": 0.9]]]
        let autres = try vueDe(.object(objet), apres: 90)
        XCTAssertEqual(bilan(encore, autres)["corrections_utilisateur"], ligne)
    }

    func testNeutralsAreTrackedInTheSession() {
        let masque = [Bool](repeating: true, count: 4)
        // Mesures non suivies presque égales (la sélection refaite perd les pixels colorés) ;
        // suivies, l'écart se voit.
        let v1 = vue(mesures(b: 3.0, part: 30), neutres: .init(a: 0, b: 3.0, part: 30, masque: masque))
        let v2 = vue(mesures(b: 3.1, part: 8), apres: 30, etapes: 2)
        let suivi = bilan(v1, v2, suivi: .init(a: 0, b: 7.5, part: 30, masque: masque))
        XCTAssertEqual(suivi["ecarts"]?["dominante_b"]?["suivie"], true, "\(suivi)")
        XCTAssertEqual(suivi["ecarts"]?["dominante_b"]?["ecart"]?.double ?? 0, 4.5, accuracy: 0.001)
        // Cadre changé : plus de suivi.
        var v3 = v2
        v3.cadre = "autre cadre"
        let nonSuivi = bilan(v1, v3, suivi: .init(a: 0, b: 7.5, part: 30, masque: masque))
        XCTAssertNil(nonSuivi["ecarts"]?["dominante_b"])
        XCTAssertTrue(textes(nonSuivi["sans_ecart_visible"]).contains("dominante_b"))
    }

    // MARK: Avant/après, zoom, mémoire

    func testBeforeAfterBilan() {
        let brulee = Bilan.avantApres(avant: mesures(hautes: 0.2), apres: mesures(hautes: 5, blanc: 5),
                                      detailAvant: detail(nettete: 50, bruit: 0.3), detailApres: detail(nettete: 50, bruit: 0.3),
                                      depuis: "l'état actuel : la proposition n'est pas appliquée",
                                      conseil: "Une « regression » se corrige dans la proposition avant de l'appliquer.")
        XCTAssertEqual(textes(brulee["regression"]), ["hautes lumières écrêtées : 0,2 → 5,0 % (+4,8 points)"])
        XCTAssertEqual(brulee["conseil"], "Une « regression » se corrige dans la proposition avant de l'appliquer.")
        XCTAssertEqual(brulee["depuis"], "l'état actuel : la proposition n'est pas appliquée")
        XCTAssertTrue(brulee["base"]?.string?.contains("non suivie") ?? false)
        XCTAssertNil(brulee["etapes_claude"])

        let sage = Bilan.avantApres(avant: mesures(b: 4, part: 20), apres: mesures(b: 1, part: 20), detailAvant: nil, detailApres: nil,
                                    depuis: "avant", conseil: "conseil")
        XCTAssertNil(sage["regression"])
        XCTAssertNil(sage["conseil"])
        XCTAssertEqual(sage["ecarts"]?["dominante_b"]?["suivie"], false)
        XCTAssertEqual(sage["ecarts"]?["dominante_b"]?["ecart"]?.double ?? 0, -3, accuracy: 0.001)
        XCTAssertTrue(Bilan.avantApres(avant: mesures(), apres: mesures(), detailAvant: detail(nettete: 50, bruit: 0.45),
                                       detailApres: detail(nettete: 50, bruit: 0.72), depuis: "avant", conseil: "c",
                                       grainAjoute: true)["a_verifier"] != nil)

        // Avant et après de cadres différents (redressement) : coins vides à vérifier, netteté et
        // bruit non comparés, et une remarque qui le dit.
        let redressee = Bilan.avantApres(avant: mesures(), apres: mesures(hautes: 6.2, blanc: 6),
                                         detailAvant: detail(nettete: 50, bruit: 0.3), detailApres: detail(nettete: 30, bruit: 0.3),
                                         depuis: "avant", conseil: "c", cadreChange: true)
        XCTAssertNil(redressee["regression"], "\(redressee)")
        XCTAssertNil(redressee["conseil"])
        XCTAssertTrue(textes(redressee["a_verifier"]).contains { $0.contains("coins vides possibles (Upright, perspective)") }, "\(redressee)")
        XCTAssertNil(redressee["ecarts"]?["nettete_max"])
        XCTAssertEqual(textes(redressee["remarques"]).first, "cadre différent entre l'avant et l'après (recadrage, Upright, rotation) : netteté et bruit non comparés")
        // Le même cadre : la même hausse est une régression, avec le conseil.
        let memeCadre = Bilan.avantApres(avant: mesures(), apres: mesures(hautes: 6.2, blanc: 6),
                                         detailAvant: detail(nettete: 50, bruit: 0.3), detailApres: detail(nettete: 30, bruit: 0.3),
                                         depuis: "avant", conseil: "c")
        XCTAssertEqual(textes(memeCadre["regression"]), ["hautes lumières écrêtées : 0,0 → 6,2 % (+6,2 points)",
                                                         "netteté passée de nette à douce : 50,0 → 30,0 (seuil 35)"])
        XCTAssertNil(memeCadre["remarques"])
    }

    func testZoomBilanGivesRawDeltasWithoutAlerts() {
        let zone = CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.2)
        let avant = Bilan.Zoom(zone: zone, cadre: "c", pixels: "1248 × 832", mesures: mesures(hautes: 0.2),
                               detail: detail(nettete: 20, bruit: 2.0, ombres: 2.4), quand: t0)
        var apres = avant
        apres.quand = t0.addingTimeInterval(45)
        apres.mesures = mesures(hautes: 3)
        apres.detail = detail(nettete: 12, bruit: 1.0, ombres: 1.2)
        let b = Bilan.zone(avant: avant, apres: apres, date: apres.quand)
        XCTAssertEqual(b["depuis"], "le zoom précédent sur la même zone, il y a 45 s")
        XCTAssertEqual(b["ecarts"]?["bruit_aplats"]?["ecart_pct"], -50)
        XCTAssertEqual(b["ecarts"]?["bruit_ombres"]?["ecart_pct"], -50)
        XCTAssertEqual(b["ecarts"]?["nettete_max"]?["ecart_pct"], -40)
        XCTAssertEqual(b["ecarts"]?["hautes_lumieres_pct"]?["apres"], 3)
        XCTAssertNotNil(b["ecarts"]?["mediane_L"])
        XCTAssertNil(b["regression"])
        XCTAssertNil(b["a_verifier"])
        XCTAssertTrue(b["base"]?.string?.contains("les seuils de lecture ne valent pas à cette échelle") ?? false)

        // Même zone à 0,002 près, même cadre et mêmes pixels.
        var voisine = avant
        voisine.zone = CGRect(x: 0.4015, y: 0.2985, width: 0.2, height: 0.201)
        XCTAssertTrue(avant.correspond(voisine))
        voisine.zone = CGRect(x: 0.405, y: 0.3, width: 0.2, height: 0.2)
        XCTAssertFalse(avant.correspond(voisine))
        var recadree = avant
        recadree.cadre = "autre"
        XCTAssertFalse(avant.correspond(recadree))
        var reduite = avant
        reduite.pixels = "624 × 416"
        XCTAssertFalse(avant.correspond(reduite))

        // Un zoom de la même zone remplace l'ancien ; six au plus.
        var liste = Bilan.ajouter(avant, a: [])
        liste = Bilan.ajouter(apres, a: liste)
        XCTAssertEqual(liste.count, 1)
        XCTAssertEqual(liste[0].quand, apres.quand)
        for i in 1...8 {
            var autre = avant
            autre.zone = CGRect(x: 0.05 * Double(i), y: 0.1, width: 0.1, height: 0.1)
            autre.quand = t0.addingTimeInterval(Double(100 + i))
            liste = Bilan.ajouter(autre, a: liste)
        }
        XCTAssertEqual(liste.count, Bilan.zoomsGardes)
        XCTAssertEqual(Double(liste.last?.zone.minX ?? 0), 0.4, accuracy: 0.0001)
        XCTAssertFalse(liste.contains { $0.correspond(apres) }, "le plus ancien est parti")
    }

    func testOldestPhotoIsDropped() {
        var suivis: [Int: Bilan.Suivi] = [:]
        for id in 1...31 {
            var v = vue(mesures(), apres: Double(id))
            v.photo = id
            suivis[id] = Bilan.Suivi(depart: v, precedente: v)
        }
        // La photo 1 vient d'être revue : c'est la 2 qui part.
        suivis[1]?.precedente.quand = t0.addingTimeInterval(100)
        Bilan.elaguer(&suivis)
        XCTAssertEqual(suivis.count, Bilan.photosGardees)
        XCTAssertNil(suivis[2])
        XCTAssertNotNil(suivis[1])
        XCTAssertNotNil(suivis[31])
    }

    /// Un bilan ordinaire reste court : moins de 1 500 caractères visés (taille réelle à relever sur
    /// de vraies passes). Ici, une deuxième passe qui éclaircit et brûle un peu, après une première.
    func testOrdinaryBilanStaysShort() {
        let depart = vue(mesures(mediane: 45, hautes: 0.2, chroma: 10, b: 4, part: 25), detail: detail(nettete: 48, bruit: 0.5))
        let precedente = vue(mesures(mediane: 52, hautes: 0.4, chroma: 12, b: 1, part: 25), detail: detail(nettete: 46, bruit: 0.55),
                             apres: 60, etapes: 2, derniere: "Claude · passe 1 : lumière")
        let maintenant = vue(mesures(mediane: 56, hautes: 2.4, blanc: 0.4, chroma: 13, b: 0.8, part: 25),
                             detail: detail(nettete: 47, bruit: 0.56), apres: 130, etapes: 3, derniere: "Claude · passe 2 : finitions")
        let b = Bilan.session(precedente: precedente, depart: depart, maintenant: maintenant, suiviPrecedente: nil, suiviDepart: nil,
                              date: maintenant.quand)
        XCTAssertEqual(textes(b["regression"]), ["hautes lumières écrêtées : 0,4 → 2,4 % (+2,0 points)"])
        XCTAssertNotNil(b["depuis_le_debut"])
        XCTAssertNotNil(b["conseil"])
        let taille = JSONCoding.line(b).count
        XCTAssertLessThan(taille, 1500, "\(taille) caractères : \(JSONCoding.pretty(b))")
    }
}
