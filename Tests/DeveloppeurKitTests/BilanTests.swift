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

        let ombres = comparer(mesures(ombres: 0.2), mesures(ombres: 2.4))
        XCTAssertEqual(ombres.regressions.map(\.texte), ["ombres bouchées : 0,2 → 2,4 %"])
        XCTAssertTrue(comparer(mesures(ombres: 0.2), mesures(ombres: 1.8)).regressions.isEmpty, "moins de 2 points")
        XCTAssertTrue(comparer(mesures(ombres: 12.5), mesures(ombres: 14)).regressions.isEmpty, "une nuit n'alerte pas d'elle-même")

        let canal = comparer(mesures(hautes: 3, canaux: [0.8, 0.5, 0]), mesures(hautes: 3.2, canaux: [4.1, 0.6, 0]))
        XCTAssertEqual(canal.regressions.map(\.texte), ["canal rouge écrêté : 0,8 → 4,1 % (couleur poussée hors du sRGB ou brûlée)"])
        XCTAssertEqual(canal.ecarts["canal_ecrete"]?["canal"], "rouge")
        let lesDeux = comparer(mesures(hautes: 0.4, canaux: [0.4, 0, 0]), mesures(hautes: 4.5, canaux: [4.5, 0, 0]))
        XCTAssertEqual(lesDeux.regressions.map(\.defaut), [.ecretage], "le canal ne se redit pas sous l'écrêtage")

        let saturees = comparer(mesures(saturee: 3.1), mesures(saturee: 7.4))
        XCTAssertEqual(saturees.regressions.map(\.texte), ["couleurs très saturées (C* > 60) : 3,1 → 7,4 % des pixels"])
        XCTAssertTrue(comparer(mesures(saturee: 3.1), mesures(saturee: 4.5)).regressions.isEmpty)
        XCTAssertTrue(comparer(mesures(saturee: 6), mesures(saturee: 8.5)).regressions.isEmpty, "2 points de plus, mais pas 1,5 fois l'avant")

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
        XCTAssertEqual(b2["depuis"], "le view_photo précédent de cette photo à 1344 px, il y a 1 min 00 s")

        let b3 = Bilan.session(precedente: deuxieme, depart: premiere, maintenant: troisieme, suiviPrecedente: nil, suiviDepart: nil, date: troisieme.quand)
        XCTAssertTrue(textes(b3["a_verifier"]).contains("aller-retour de l'exposition : +0,50 IL à la passe précédente, −0,30 IL depuis : des réglages empilés font dériver la photo"),
                      "\(b3)")
        let debut = try XCTUnwrap(b3["depuis_le_debut"])
        XCTAssertEqual(debut["depuis"], "le premier view_photo à 1344 px de la session, il y a 3 min 05 s")
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
        let precedente = vue(mesures(hautes: 1.6), apres: 60, etapes: 2)
        let maintenant = vue(mesures(hautes: 2.8), apres: 120, etapes: 3)
        let b = Bilan.session(precedente: precedente, depart: depart, maintenant: maintenant, suiviPrecedente: nil, suiviDepart: nil, date: maintenant.quand)
        XCTAssertNil(b["regression"])
        XCTAssertEqual(textes(b["depuis_le_debut"]?["regression"]), ["hautes lumières écrêtées : 0,4 → 2,8 % (+2,4 points)"])
        XCTAssertNotNil(b["conseil"])
        // Déjà signalée à la vue précédente : pas redite.
        let forte = vue(mesures(hautes: 4), apres: 120, etapes: 3)
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
        XCTAssertTrue(Bilan.premiereVue(taille: 1344).contains("point de départ"), "le texte du premier view_photo d'une photo")

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
        XCTAssertEqual(textes(suivi["regression"]), ["dominante accentuée sur les mêmes tons neutres : b* +3,0 → +7,5 (plus chaude)"])
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

    // MARK: Seuils relevés le 20 octobre 2026 (mesures, section 4)

    func testRegressionThresholdsFromTheMeasurements() {
        XCTAssertEqual(Bilan.regressionEcretage.hausseMin, 2)
        XCTAssertEqual(Bilan.regressionEcretage.facteurMin, 1.5)
        XCTAssertEqual(Bilan.regressionCanal.hausseMin, 2)
        XCTAssertEqual(Bilan.regressionCanal.facteurMin, 1.5)
        XCTAssertEqual(Bilan.regressionOmbres.hausseMin, 2)
        XCTAssertEqual(Bilan.regressionOmbres.facteurMin, 1)
        XCTAssertEqual(Bilan.regressionSaturees.hausseMin, 2)
        XCTAssertEqual(Bilan.regressionSaturees.facteurMin, 1.5)
        XCTAssertEqual(Bilan.regressionDominante, 2)
        // Le plancher d'une proposition à une vue (scène : hautes lumières 1,8 → 2,7) n'alerte pas.
        XCTAssertTrue(comparer(mesures(hautes: 1.8), mesures(hautes: 2.7)).regressions.isEmpty)
        // Exposure +0,3 sur la scène (1,8 → 4,3) alerte ; Whites +30 sur la dune (0 → 0,6), non.
        XCTAssertEqual(comparer(mesures(hautes: 1.8), mesures(hautes: 4.3)).regressions.map(\.defaut), [.ecretage])
        XCTAssertTrue(comparer(mesures(hautes: 0), mesures(hautes: 0.6)).regressions.isEmpty)
        // Juste au seuil : 2 points de plus comptent (2,4 − 0,4 vaut 1,999… en binaire).
        XCTAssertEqual(comparer(mesures(hautes: 0.4), mesures(hautes: 2.4)).regressions.count, 1)
        // 2 points de plus, mais moins de 1,5 fois l'avant : non.
        XCTAssertTrue(comparer(mesures(hautes: 5), mesures(hautes: 7.4)).regressions.isEmpty)
        // Contraste +40 sur la nuit (ombres 0,7 → 3,9) alerte : le seuil porte sur l'écart.
        XCTAssertEqual(comparer(mesures(ombres: 0.7), mesures(ombres: 3.9)).regressions.map(\.defaut), [.ombres])
        // Saturation +30 (3 → 5,9) alerte ; Vibrance +40 (3 → 4,2), non.
        XCTAssertEqual(comparer(mesures(saturee: 3), mesures(saturee: 5.9)).regressions.map(\.defaut), [.saturees])
        XCTAssertTrue(comparer(mesures(saturee: 3), mesures(saturee: 4.2)).regressions.isEmpty)
    }

    /// Une dominante des tons neutres qui s'éloigne du neutre de 2 ou plus (relevé : Tint ±15 donnait
    /// a* ±3 sur le portrait) : une régression ; celle qui s'en rapproche, non.
    func testDominanceMovingAwayFromNeutralIsARegression() {
        let teinte = comparer(mesures(a: 0.1, part: 20), mesures(a: 3.2, part: 20))
        XCTAssertEqual(teinte.regressions.map(\.texte), ["dominante accentuée sur les tons neutres : a* +0,1 → +3,2 (plus magenta)"])
        XCTAssertEqual(teinte.regressions.first?.defaut, .dominante)
        XCTAssertTrue(comparer(mesures(b: 8.3, part: 20), mesures(b: 5.2, part: 20)).regressions.isEmpty, "plus près du neutre")
        XCTAssertTrue(comparer(mesures(b: 0.4, part: 20), mesures(b: 2.2, part: 20)).regressions.isEmpty, "moins de 2")
        // À travers le neutre, vers le froid : une régression, pas une « correction dépassée ».
        let froide = comparer(mesures(b: 0.5, part: 20), mesures(b: -3.1, part: 20))
        XCTAssertEqual(froide.regressions.map(\.texte), ["dominante accentuée sur les tons neutres : b* +0,5 → −3,1 (plus froide)"])
        XCTAssertTrue(froide.aVerifier.isEmpty)
        let depassee = comparer(mesures(b: 2.5, part: 20), mesures(b: -4.6, part: 20))
        XCTAssertEqual(depassee.regressions.map(\.defaut), [.dominante], "accentuée de 2,1")
        XCTAssertTrue(depassee.aVerifier.isEmpty, "pas redite en « correction dépassée »")
        XCTAssertTrue(comparer(mesures(a: 0.1, part: 2), mesures(a: 3.2, part: 20)).regressions.isEmpty, "trop peu de tons neutres")
        // Une régression de dominante se dédoublonne comme les autres dans depuis_le_debut.
        let depart = vue(mesures(a: 0, part: 20)), precedente = vue(mesures(a: 2.5, part: 20), apres: 30, etapes: 2)
        let maintenant = vue(mesures(a: 5, part: 20), apres: 60, etapes: 3)
        let b = Bilan.session(precedente: precedente, depart: depart, maintenant: maintenant, suiviPrecedente: nil, suiviDepart: nil, date: maintenant.quand)
        XCTAssertEqual(textes(b["regression"]).count, 1)
        XCTAssertNil(b["depuis_le_debut"]?["regression"])
    }

    // MARK: Branché dans view_photo et les propositions

    /// Le faux module : chaque « apercu » et « essayer » rend l'état présent dans un nouveau
    /// fichier (le serveur l'efface après lecture), avec les étapes de Claude seulement pour
    /// point_af, comme Rendu.apercu.
    final class Module {
        var image: Data
        var avant: Data?
        var proposee: Data?
        var id = 7
        var fichier = "DSCF2402.RAF"
        var etapes = 0
        var derniere: String?
        var hauteur = 4160
        var reglages: [String: JSONValue] = ["Exposure2012": 0, "Temperature": 5200, "Tint": 10]
        /// Un aperçu lent : la commande « apercu » de view_photo attend `porte`.
        var porte: DispatchSemaphore?
        let fake = FakeLightroom()

        init(_ image: Data) {
            self.image = image
            fake.onSend = { [unowned self] command, params in
                switch command {
                case "apercu":
                    if params["point_af"]?.bool == true, let porte = self.porte { _ = porte.wait(timeout: .now() + 5) }
                    self.fake.replies["apercu"] = self.apercu(params)
                case "essayer":
                    self.fake.replies["essayer"] = self.essai(params)
                default:
                    break
                }
            }
        }

        func apercu(_ params: [String: JSONValue]) -> JSONValue {
            var objet: [String: JSONValue] = [
                "chemin": .string(TestSupport.previewFile(image)),
                "photo": ["id": .number(Double(id)), "fichier": .string(fichier),
                          "geometrie": ["largeur": 6240, "hauteur": .number(Double(hauteur)), "orientation": "AB"]],
                "recadrage": ["recadree": false, "angle": 0],
                "reglages": .object(reglages),
                "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
            ]
            if params["point_af"]?.bool == true {
                objet["etapes_claude"] = ["nombre": .number(Double(etapes)), "derniere": derniere.map(JSONValue.string) ?? .null]
            }
            if params["comparer"] != nil, let avant { objet["chemin_avant"] = .string(TestSupport.previewFile(avant)) }
            return .object(objet)
        }

        func essai(_ params: [String: JSONValue]) -> JSONValue {
            var objet: [String: JSONValue] = ["chemin": .string(TestSupport.previewFile(proposee ?? image)),
                                              "photo": ["id": .number(Double(id)), "fichier": .string(fichier)]]
            if params["comparer"]?.bool == true { objet["chemin_actuel"] = .string(TestSupport.previewFile(image)) }
            return .object(objet)
        }
    }

    func gris(_ v: UInt8) -> Data { TestSupport.jpeg(red: v, green: v, blue: v, width: 600, height: 400) }

    func vue(_ tools: ToolHandler, _ arguments: [String: JSONValue] = [:]) throws -> JSONValue {
        let result = tools.call(name: "view_photo", arguments: arguments)
        XCTAssertFalse(result.isError, result.text)
        return try JSONCoding.parse(result.text)
    }

    func testFirstViewIsTheStartingPointThenNumericDeltas() throws {
        let module = Module(gris(115))
        let tools = ToolHandler(lightroom: module.fake)
        let premiere = try vue(tools)
        XCTAssertTrue(premiere["bilan"]?.string?.contains("point de départ") == true, "\(premiere["bilan"] ?? .null)")
        XCTAssertNil(premiere["etapes_claude"], "les étapes vont au bilan, pas telles quelles à Claude")

        module.image = gris(140)
        module.etapes = 1
        module.derniere = "Claude · passe 1 : lumière"
        module.reglages["Exposure2012"] = 0.5
        let bilan = try XCTUnwrap(try vue(tools)["bilan"])
        let exposition = try XCTUnwrap(bilan["ecarts"]?["exposition"], "\(bilan)")
        XCTAssertGreaterThan(exposition["IL"]?.double ?? 0, 0)
        XCTAssertLessThan(exposition["avant"]?.double ?? 0, exposition["apres"]?.double ?? 0)
        XCTAssertEqual(bilan["etapes_claude"], "1 de plus (dernière : « Claude · passe 1 : lumière »)")
        XCTAssertEqual(bilan["depuis"]?.string?.hasPrefix("le view_photo précédent de cette photo à 1344 px"), true, "\(bilan)")

        // Rien de changé : le même état, en quelques mots.
        let meme = try XCTUnwrap(try vue(tools)["bilan"])
        XCTAssertNotNil(meme["meme_etat"], "\(meme)")
        XCTAssertEqual(meme["etapes_claude"], "aucune nouvelle")
    }

    /// Le bilan ne compare que des aperçus de même taille (relevé du 20 octobre 2026 : d'une taille à
    /// l'autre, la netteté varie jusqu'à 10 %) : une autre taille est un nouveau départ, et la vue
    /// suivante à 1344 px se compare à la précédente à 1344 px.
    func testOnlyViewsOfTheSameSizeAreCompared() throws {
        let module = Module(gris(115))
        let tools = ToolHandler(lightroom: module.fake)
        _ = try vue(tools)
        let grande = try XCTUnwrap(try vue(tools, ["size": 2048])["bilan"]?.string)
        XCTAssertTrue(grande.contains("à 2048 px") && grande.contains("déjà vue à 1344 px"), grande)
        module.image = gris(140)
        module.etapes = 1
        let retour = try XCTUnwrap(try vue(tools)["bilan"])
        XCTAssertEqual(retour["depuis"]?.string?.hasPrefix("le view_photo précédent de cette photo à 1344 px"), true, "\(retour)")
        XCTAssertNotNil(retour["ecarts"]?["exposition"])
        XCTAssertFalse(textes(retour["remarques"]).contains { $0.contains("taille d'aperçu différente") }, "\(retour)")
        XCTAssertEqual(Set(tools.vuesMesurees.keys.map(\.taille)), [1344, 2048])
    }

    func testNeutralsAreTrackedBetweenViews() throws {
        // La moitié gauche grise, la droite d'un rouge franc ; puis la moitié grise réchauffée.
        func image(gauche: (UInt8, UInt8, UInt8)) -> Data {
            TestSupport.jpegPixels(width: 600, height: 400) { x, _ in x < 300 ? gauche : (200, 30, 30) }
        }
        let module = Module(image(gauche: (128, 128, 128)))
        let tools = ToolHandler(lightroom: module.fake)
        _ = try vue(tools)
        module.image = image(gauche: (150, 128, 95))
        module.etapes = 1
        let info = try vue(tools)
        let bilan = try XCTUnwrap(info["bilan"])
        let dominante = try XCTUnwrap(bilan["ecarts"]?["dominante_b"], "\(bilan)")
        XCTAssertEqual(dominante["suivie"], true)
        XCTAssertGreaterThan(dominante["ecart"]?.double ?? 0, 15, "les mêmes pixels, devenus jaunes")
        XCTAssertTrue(textes(bilan["regression"]).contains { $0.hasPrefix("dominante accentuée sur les mêmes tons neutres : b*") }, "\(bilan)")
        // Choisis à nouveau, les tons neutres de cette vue seraient presque tous sortis de la sélection.
        XCTAssertLessThan(info["mesures"]?["couleur"]?["tons_neutres"]?["part_pct"]?.double ?? 100, PhotoMeasurements.partNeutreMin)

        // Un autre cadre (Upright) : plus de suivi, et une remarque.
        module.hauteur = 3900
        module.etapes = 2
        module.image = image(gauche: (128, 128, 128))
        let recadree = try XCTUnwrap(try vue(tools)["bilan"])
        XCTAssertNotEqual(recadree["ecarts"]?["dominante_b"]?["suivie"], true)
        XCTAssertTrue(textes(recadree["remarques"]).contains { $0.hasPrefix("cadre changé") }, "\(recadree)")
    }

    func testSeveralPhotosAndFilesAreKeptApart() throws {
        let module = Module(gris(100))
        let tools = ToolHandler(lightroom: module.fake)
        module.id = 1
        _ = try vue(tools)
        module.id = 2
        module.image = gris(200)
        XCTAssertTrue(try vue(tools)["bilan"]?.string?.contains("point de départ") == true)
        module.id = 1
        module.image = gris(100)
        XCTAssertNotNil(try vue(tools)["bilan"]?["meme_etat"], "la photo 1 se compare à sa propre vue")
        // Le même identifiant, un autre fichier (un autre catalogue) : un nouveau départ.
        module.fichier = "AUTRE.JPG"
        XCTAssertTrue(try vue(tools)["bilan"]?.string?.contains("point de départ") == true)
        XCTAssertEqual(tools.vuesMesurees.keys.filter { $0.photo == 1 }.count, 1)
    }

    func testZoomGetsItsOwnBilanAndLeavesTheMainOne() throws {
        let module = Module(AnalyseTests.noisyGray(amount: 12))
        let tools = ToolHandler(lightroom: module.fake)
        _ = try vue(tools)
        let zone: JSONValue = ["x": 0.4, "y": 0.3, "width": 0.2, "height": 0.2]
        XCTAssertNil(try vue(tools, ["region": zone])["bilan_zone"], "premier zoom de cette zone")
        module.image = AnalyseTests.noisyGray(amount: 4)
        let second = try vue(tools, ["region": zone])
        let bruit = try XCTUnwrap(second["bilan_zone"]?["ecarts"]?["bruit_aplats"], "\(second)")
        XCTAssertLessThan(bruit["ecart_pct"]?.double ?? 0, 0, "moins de bruit, comme après un débruitage")
        XCTAssertNil(second["bilan"], "un zoom n'a pas le bilan de l'aperçu entier")
        XCTAssertNil(try vue(tools, ["region": ["x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2]])["bilan_zone"], "une autre zone")
        XCTAssertEqual(tools.zoomsMesures[7]?.count, 2)
        // La vue entière suivante se compare à la vue entière précédente, pas au zoom.
        let entiere = try XCTUnwrap(try vue(tools)["bilan"])
        XCTAssertEqual(entiere["depuis"]?.string?.hasPrefix("le view_photo précédent de cette photo à 1344 px"), true, "\(entiere)")
        XCTAssertNotNil(entiere["ecarts"]?["bruit"], "\(entiere)")
    }

    func testZoomsAreKeptForThirtyPhotosAtMost() {
        let tools = ToolHandler(lightroom: FakeLightroom())
        for id in 1...31 {
            tools.garderZoom(Bilan.Zoom(zone: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), cadre: "c", pixels: "100 × 100",
                                        mesures: mesures(), detail: nil, quand: t0.addingTimeInterval(Double(id))), photo: id)
        }
        XCTAssertEqual(tools.zoomsMesures.count, Bilan.photosGardees)
        XCTAssertNil(tools.zoomsMesures[1], "part la photo dont le dernier zoom est le plus ancien")
        XCTAssertNotNil(tools.zoomsMesures[31])
    }

    func testCompareGivesABilanWithoutTouchingTheMemory() throws {
        let module = Module(gris(120))
        let tools = ToolHandler(lightroom: module.fake)
        _ = try vue(tools)
        module.avant = gris(90)
        let comparaison = try vue(tools, ["compare": "before_claude"])
        let bilan = try XCTUnwrap(comparaison["bilan"])
        XCTAssertEqual(bilan["depuis"], "l'état d'avant la première retouche de Claude (à gauche)")
        XCTAssertGreaterThan(bilan["ecarts"]?["exposition"]?["IL"]?.double ?? 0, 0)
        XCTAssertNotNil(comparaison["mesures_avant"]?["eclairage"]?["lecture"], "la forme courte de l'éclairage, avant et après")
        XCTAssertNotNil(comparaison["mesures"]?["eclairage"]?["zones_tonales"])
        XCTAssertNil(comparaison["mesures"]?["eclairage"]?["visages"], "forme courte : sans visages ni conseil")
        XCTAssertEqual(try vue(tools, ["compare": "previous_step"])["bilan"]?["depuis"], "l'état d'avant la dernière retouche (à gauche)")
        // Les vues gardées n'ont pas bougé : la vue suivante se compare à la première.
        XCTAssertNotNil(try vue(tools)["bilan"]?["meme_etat"])
        // Avant et après de dimensions différentes (un recadrage entre les deux) : netteté et bruit non comparés.
        module.avant = TestSupport.jpeg(red: 90, green: 90, blue: 90, width: 600, height: 300)
        let recadree = try XCTUnwrap(try vue(tools, ["compare": "before_claude"])["bilan"])
        XCTAssertTrue(textes(recadree["remarques"]).contains { $0.hasPrefix("cadre différent entre l'avant et l'après") }, "\(recadree)")
    }

    func testPreviewCompareWarnsBeforeApplying() throws {
        let module = Module(gris(120))
        // La proposition brûle 5 % de l'image (une bande blanche en haut).
        module.proposee = TestSupport.jpegPixels(width: 600, height: 400) { _, y in y < 20 ? (255, 255, 255) : (120, 120, 120) }
        let tools = ToolHandler(lightroom: module.fake)
        let result = tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 1], "compare": true])
        XCTAssertFalse(result.isError, result.text)
        let info = try JSONCoding.parse(result.text)
        let bilan = try XCTUnwrap(info["bilan"], result.text)
        XCTAssertTrue(textes(bilan["regression"]).contains { $0.hasPrefix("hautes lumières écrêtées : 0,0 →") }, "\(bilan)")
        XCTAssertEqual(bilan["conseil"], "Une « regression » se corrige dans la proposition avant de l'appliquer.")
        XCTAssertEqual(bilan["depuis"], "l'état actuel : la proposition n'est pas appliquée")
        XCTAssertNil(bilan["ecarts"]?["nettete_max"], "ni netteté ni bruit pour une proposition")
        XCTAssertFalse(textes(bilan["sans_ecart_visible"]).contains("bruit"))
        XCTAssertNotNil(info["mesures_proposition"]?["eclairage"]?["mixte"])
        XCTAssertNotNil(info["mesures_actuelles"]?["eclairage"]?["mixte"])
        XCTAssertTrue(tools.vuesMesurees.isEmpty, "une proposition ne se garde pas comme une vue")

        let sansComparaison = try JSONCoding.parse(tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 1]]).text)
        XCTAssertNil(sansComparaison["bilan"])
        XCTAssertNotNil(sansComparaison["mesures_proposition"]?["eclairage"])
        // Un grain proposé : un bruit en hausse serait voulu.
        XCTAssertTrue(ToolHandler.grainAjoute(.array([["cle": "GrainAmount", "avant": 0, "apres": 25]])))
        XCTAssertFalse(ToolHandler.grainAjoute(.array([["cle": "GrainAmount", "avant": 25, "apres": 0]])))
        XCTAssertFalse(ToolHandler.grainAjoute(nil))
    }

    /// Le résultat gardé par FileOutils (réponse d'attente, puis le même appel) : la vue n'est
    /// mesurée et gardée qu'une fois.
    func testRepeatedCallAfterTheLimitKeepsOneBilan() throws {
        let module = Module(gris(115))
        let server = TestSupport.makeServer(module.fake)
        func appel(_ id: Int) throws -> (texte: String, image: Bool) {
            let ligne = #"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"view_photo","arguments":{}}}"#
            let reponse = try JSONCoding.parse(XCTUnwrap(server.handle(line: ligne)))
            let contenu = reponse["result"]?["content"]?.array ?? []
            return (contenu.compactMap { $0["text"]?.string }.joined(separator: "\n"), contenu.contains { $0["type"]?.string == "image" })
        }
        XCTAssertTrue(try appel(1).texte.contains("point de départ"))

        module.image = gris(140)
        module.etapes = 1
        module.derniere = "Claude · passe 1"
        let porte = DispatchSemaphore(value: 0)
        module.porte = porte
        server.toolBudget = 0.3
        let attente = try appel(2)
        XCTAssertFalse(attente.image)
        XCTAssertTrue(attente.texte.contains("n'est pas fini"), attente.texte)
        // Les mesures (Vision, détail, éclairage) prennent plus que 0,3 s : le même appel attend la fin.
        porte.signal()
        server.toolBudget = 5
        let repris = try appel(3)
        XCTAssertTrue(repris.image)
        XCTAssertTrue(repris.texte.contains("Résultat de l'appel précédent de view_photo"), repris.texte)
        XCTAssertTrue(repris.texte.contains("1 de plus (dernière : « Claude · passe 1 »)"), repris.texte)
        XCTAssertEqual(module.fake.commands.filter { $0 == "apercu" }.count, 2, "l'aperçu lent n'est demandé qu'une fois")

        // La vue gardée est celle de l'appel lent : la suivante n'y voit rien de neuf.
        module.porte = nil
        server.toolBudget = 5
        let suivante = try appel(4)
        XCTAssertTrue(suivante.texte.contains("aucune nouvelle") && suivante.texte.contains("meme_etat"), suivante.texte)
    }

    func testDescriptionsSayTheBilanAndStayShort() throws {
        let definitions = ToolHandler(lightroom: FakeLightroom()).definitions
        func description(_ nom: String) throws -> String {
            try XCTUnwrap(definitions.first { $0["name"]?.string == nom }?["description"]?.string)
        }
        let vue = try description("view_photo")
        XCTAssertLessThanOrEqual(vue.count, 1850, "view_photo : \(vue.count) caractères")
        XCTAssertTrue(vue.hasPrefix("Montre la photo telle qu'elle est développée en ce moment"))
        // L'essentiel en tête : ce qu'il montre et quand l'appeler, avant les clés de la réponse.
        let quand = try XCTUnwrap(vue.range(of: "À appeler avant de retoucher, puis après chaque passe."))
        XCTAssertLessThan(vue.distance(from: vue.startIndex, to: quand.lowerBound), 700)
        for attendu in ["« eclairage » nomme un éclairage mixte", "« bilan » : écarts chiffrés avec le view_photo précédent de la même photo à la même taille",
                        "« regression »", "undo_last s'il vient de la dernière étape", "« a_verifier »", "bilan_zone", "avec son bilan"] {
            XCTAssertTrue(vue.contains(attendu), "view_photo sans « \(attendu) »")
        }
        let proposition = try description("preview_settings")
        XCTAssertLessThanOrEqual(proposition.count, 600, "preview_settings : \(proposition.count) caractères")
        XCTAssertTrue(proposition.hasPrefix("Proposition visuelle : montre le rendu d'une retouche"))
        XCTAssertTrue(proposition.contains("Avec compare : « bilan » de l'état actuel à la proposition"))
        let serie = try description("analyze_photos")
        XCTAssertLessThanOrEqual(serie.count, 520, "analyze_photos : \(serie.count) caractères")
        XCTAssertTrue(serie.hasPrefix("Mesures objectives de plusieurs photos sans les afficher"))
        XCTAssertTrue(serie.contains("dominante (et éclairage mixte)"))
    }
}
