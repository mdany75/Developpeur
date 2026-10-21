import CoreGraphics
import Foundation
import XCTest
@testable import DeveloppeurKit

/// « Je le fais » (1.3), côté connecteur : la liste à faire dans l'ordre des panneaux du module
/// Développement, le classement des écarts réglage par réglage, l'écart principal mesuré aux seuils
/// du bilan (JeLeFais, fonctions pures), preview_settings avec my_turn et view_photo avec
/// compare = claude_version, par FakeLightroom. Le module (essayer avec exercice et sans_rendu,
/// apercu avec comparer = versionClaude) a ses propres essais dans la suite de la liaison ; ce qui
/// passe entre les deux est figé dans Tests/Contrats/je-le-fais.json (ContratJeLeFaisTests) : les
/// fausses réponses d'ici en suivent la forme.
final class JeLeFaisTests: XCTestCase {
    // MARK: Aides

    let fine = JeLeFais.espaceMilliers, insecable = JeLeFais.espaceUnite

    func changement(_ cle: String, _ avant: JSONValue, _ apres: JSONValue) -> JSONValue {
        ["cle": .string(cle), "avant": avant, "apres": apres]
    }

    func ecart(_ cle: String, _ depart: JSONValue, _ claude: JSONValue, _ vous: JSONValue) -> JSONValue {
        ["cle": .string(cle), "depart": depart, "claude": claude, "vous": vous]
    }

    /// Mesures construites à la main, comme celles des essais du bilan.
    func mesures(mediane: Double = 50, p5: Double = 10, p95: Double = 90, hautes: Double = 0, ombres: Double = 0,
                 chroma: Double = 12, a: Double = 0, b: Double = 0, part: Double = 30) -> PhotoMeasurements {
        PhotoMeasurements(meanL: mediane, percentilesL: [1: p5, 5: p5, 25: mediane, 50: mediane, 75: mediane, 95: p95, 99: p95],
                          histogramL: [Double](repeating: 10, count: 10), clippedHighlights: hautes, pureWhite: 0,
                          crushedShadows: ombres, clippedChannels: [0, 0, 0], meanChroma: chroma, saturatedShare: 0,
                          neutralA: a, neutralB: b, neutralShare: part, pixelCount: 512 * 341)
    }

    /// L* qui donne `il` IL de plus que `l`.
    func clarte(_ l: Double, plus il: Double) -> Double { 116 * cbrt(Measurements.luminance(l) * pow(2, il)) - 16 }

    func lignes(_ valeur: JSONValue) -> [JSONValue] { valeur.array ?? [] }

    func ligne(_ liste: [JSONValue], _ cle: String) throws -> JSONValue {
        try XCTUnwrap(liste.first { $0["cle"]?.string == cle }, "pas de ligne \(cle)")
    }

    // MARK: Liste à faire

    /// Un plan mêlé sort dans l'ordre des panneaux : paramètres prédéfinis, profil, balance,
    /// tonalité, présence, courbe, détail, corrections de l'objectif, transformation, recadrage,
    /// effets, étalonnage ; une clé inconnue en dernier.
    func testLaListeSuitLOrdreDesPanneaux() throws {
        let changements: [JSONValue] = [
            changement("RedHue", 0, 5),
            changement("Vibrance", 0, 10),
            changement("CropLeft", 0, 0.02),
            changement("CleInconnue", 0, 1),
            changement("Exposure2012", 0, 0.35),
            changement("PostCropVignetteAmount", 0, -15),
            changement("CropAngle", 0, -1.2),
            changement("Sharpness", 40, 60),
            changement("CameraProfile", "Adobe Standard", "Adobe Color"),
            changement("PerspectiveUpright", 0, 2),
            changement("Temperature", 5200, 5600),
            changement("CropTop", 0, 0.03),
            changement("ToneCurvePV2012", "2 points", "4 points"),
            changement("LensProfileEnable", 0, 1),
            changement("Preset", "—", "Adobe / Vif"),
            changement("CropRight", 1, 0.98),
            changement("CropBottom", 1, 0.97),
        ]
        let liste = lignes(JeLeFais.aFaire(changements, raw: true))
        XCTAssertEqual(liste.compactMap { $0["cle"]?.string }, [
            "Preset", "CameraProfile", "Temperature", "Exposure2012", "Vibrance", "ToneCurvePV2012", "Sharpness",
            "LensProfileEnable", "PerspectiveUpright", "Crop", "PostCropVignetteAmount", "RedHue", "CleInconnue",
        ])
        XCTAssertEqual(liste.compactMap { $0["panneau"]?.string }, [
            "Paramètres prédéfinis", "Réglages de base", "Réglages de base", "Réglages de base", "Réglages de base",
            "Courbe des tonalités", "Détail", "Corrections de l'objectif", "Transformation", "Recadrage", "Effets", "Étalonnage",
            JeLeFais.autres,
        ])
        XCTAssertEqual(liste.prefix(5).map { $0["section"]?.string }, [nil, "Profil", "Balance des blancs", "Tonalité", "Présence"])
        XCTAssertEqual(liste.compactMap { $0["n"]?.int }, Array(1...13), "numérotées dans l'ordre")

        // Les textes : virgule décimale, signe des curseurs bipolaires, kelvins d'un RAW, degrés.
        XCTAssertEqual(try ligne(liste, "Exposure2012")["texte"], "Réglages de base › Tonalité › Exposition : 0 → +0,35")
        XCTAssertEqual(try ligne(liste, "Temperature")["a"]?.string, "5\(fine)600\(insecable)K")
        XCTAssertEqual(try ligne(liste, "Temperature")["de"]?.string, "5\(fine)200\(insecable)K")
        XCTAssertEqual(try ligne(liste, "Vibrance")["a"], "+10")
        XCTAssertEqual(try ligne(liste, "PostCropVignetteAmount")["a"], "−15")
        XCTAssertEqual(try ligne(liste, "Sharpness")["texte"], "Détail › Netteté › Gain : 40 → 60", "sans la parenthèse du catalogue")
        XCTAssertEqual(try ligne(liste, "Sharpness")["reglage"], "Netteté : gain")
        XCTAssertEqual(try ligne(liste, "RedHue")["reglage"], "Rouge primaire, teinte", "sans le préfixe qui redit le panneau")
        XCTAssertEqual(try ligne(liste, "RedHue")["texte"], "Étalonnage › Rouge primaire, teinte : 0 → +5")
        XCTAssertEqual(try ligne(liste, "PostCropVignetteAmount")["texte"], "Effets › Vignetage › Gain : 0 → −15")
        XCTAssertEqual(try ligne(liste, "PerspectiveUpright")["a"], "complet")
        XCTAssertEqual(try ligne(liste, "LensProfileEnable")["a"], "activé")
        XCTAssertEqual(try ligne(liste, "CameraProfile")["texte"], "Réglages de base › Profil › Profil : Adobe Standard → Adobe Color")
        XCTAssertEqual(try ligne(liste, "Preset")["texte"], "Paramètres prédéfinis › Paramètre prédéfini : — → Adobe / Vif")
        XCTAssertEqual(try ligne(liste, "Exposure2012")["apres"]?.double, 0.35, "la valeur brute, pour cocher ce qui a bougé")

        // Les cinq clés du cadre en une ligne : angle en degrés, bords en part rognée.
        let cadre = try ligne(liste, "Crop")
        XCTAssertEqual(cadre["reglage"], "Cadre")
        XCTAssertEqual(cadre["cles"]?.array?.count, 5)
        XCTAssertEqual(cadre["a"]?.string, "angle −1,2°, rogné à gauche 2\(insecable)%, en haut 3\(insecable)%, à droite 2\(insecable)%, en bas 3\(insecable)%")
        XCTAssertEqual(cadre["de"]?.string, "angle 0°, sans rognage")
        XCTAssertEqual(cadre["apres"]?["CropAngle"]?.double, -1.2)
        XCTAssertEqual(liste.filter { $0["panneau"] == "Recadrage" }.count, 1, "une seule ligne de recadrage")

        // Une clé inconnue va sous « Autres », avec son nom.
        XCTAssertEqual(try ligne(liste, "CleInconnue")["reglage"], "CleInconnue")
    }

    /// Un JPEG : la température est relative ; une température en kelvins reste en kelvins même sans
    /// raw (elle sort de la plage relative).
    func testTemperatureRelativeOuEnKelvins() {
        let jpeg = lignes(JeLeFais.aFaire([changement("Temperature", 0, 12)], raw: false))
        XCTAssertEqual(jpeg.first?["texte"], "Réglages de base › Balance des blancs › Température : 0 → +12")
        XCTAssertEqual(JeLeFais.texte(cle: "Temperature", 4850, raw: false), "4\(fine)850\(insecable)K")
        XCTAssertEqual(JeLeFais.texte(cle: "Temperature", 12000, raw: true), "12\(fine)000\(insecable)K")
        XCTAssertEqual(JeLeFais.texte(cle: "WhiteBalance", "As Shot", raw: true), "Telle quelle")
        XCTAssertEqual(JeLeFais.texte(cle: "ConvertToGrayscale", true, raw: true), "noir et blanc")
        XCTAssertEqual(JeLeFais.texte(cle: "ColorGradeMidtoneHue", 45, raw: true), "45°")
        XCTAssertEqual(JeLeFais.texte(cle: "Contrast2012", .number(ToolHandler.pendingAutoValue), raw: true), "auto")
        // La version de processus : rangée par Lightroom dans les écarts du module (« 15.4 »), nommée
        // dans la liste à faire (« version 6 », le nom que le serveur envoie) ; dite pareil.
        XCTAssertEqual(JeLeFais.texte(cle: "ProcessVersion", "15.4", raw: true), "version 6")
        XCTAssertEqual(JeLeFais.texte(cle: "ProcessVersion", "11.0", raw: true), "version 5")
        XCTAssertEqual(JeLeFais.texte(cle: "ProcessVersion", "version 6", raw: true), "version 6")
    }

    /// Les quatre courbes par points gardent leur canal (le libellé du catalogue le met entre
    /// parenthèses) ; les listes et les clés hors catalogue ont un nom français.
    func testLesCourbesGardentLeurCanal() {
        let liste = lignes(JeLeFais.aFaire([
            changement("ToneCurvePV2012Red", "linéaire", "3 points"), changement("ToneCurvePV2012", "linéaire", "4 points"),
            changement("MaskGroupBasedCorrections", "0 masque", "2 masques"),
        ], raw: true))
        XCTAssertEqual(liste.compactMap { $0["reglage"]?.string }, ["Courbe par points : RVB", "Courbe par points : rouge", "Masques"])
        XCTAssertEqual(liste.first?["texte"], "Courbe des tonalités › Courbe par points › RVB : linéaire → 4 points")
        XCTAssertEqual(liste.dropFirst().first?["texte"], "Courbe des tonalités › Courbe par points › Rouge : linéaire → 3 points")
        for courbe in DevelopCatalogue.curveKeys {
            XCTAssertFalse(JeLeFais.reglage(cle: courbe.key).contains("("), courbe.key)
        }
    }

    /// Chaque groupe du catalogue a son panneau, et chaque panneau nommé existe : aucune clé connue ne
    /// tombe sous « Autres ».
    func testChaqueReglageDuCatalogueASonPanneau() {
        for groupe in DevelopCatalogue.groups {
            XCTAssertNotNil(JeLeFais.groupes[groupe], "groupe sans panneau : \(groupe)")
        }
        let noms = Set(JeLeFais.panneaux.map(\.nom))
        let cles = DevelopCatalogue.keys + DevelopCatalogue.cropKeys + DevelopCatalogue.curveKeys.map(\.key)
            + ["Preset", "CameraProfile", "Look", "WhiteBalance", "AutoTone", "PointColors", "AutoGrayscaleMix", "LensBlur",
               "DepthBasedCorrections", "LensProfileName", "UprightFourSegments", "CropConstrainToWarp", "ProcessVersion"]
        for cle in cles {
            let place = JeLeFais.place(cle: cle)
            XCTAssertTrue(noms.contains(place.panneau), "\(cle) : panneau inconnu \(place.panneau)")
            if let section = place.section {
                XCTAssertTrue(JeLeFais.panneaux.first { $0.nom == place.panneau }?.sections.contains(section) == true, "\(cle) : section \(section)")
            }
        }
        XCTAssertEqual(JeLeFais.place(cle: "ConvertToGrayscale").section, "Traitement", "le traitement est dans Réglages de base")
        XCTAssertEqual(JeLeFais.place(cle: "GrayMixerRed").panneau, "Noir et blanc")
        XCTAssertEqual(JeLeFais.place(cle: "HueAdjustmentRed").section, "TSL")
        XCTAssertEqual(JeLeFais.place(cle: "PointColors").section, "Couleur de point")
        // Recadrage après Transformation (Upright le remet à zéro), Étalonnage en dernier.
        let rang = { (cle: String) in JeLeFais.place(cle: cle).rangPanneau }
        XCTAssertLessThan(rang("PerspectiveVertical"), rang("CropAngle"))
        XCTAssertLessThan(rang("CropAngle"), rang("PostCropVignetteAmount"))
        XCTAssertLessThan(rang("PostCropVignetteAmount"), rang("RedHue"))
        XCTAssertEqual(rang("CleInconnue"), JeLeFais.panneaux.count)
        // Dans Réglages de base : Présence avant HDR, même si le catalogue range HDR avant.
        XCTAssertTrue(JeLeFais.place(cle: "Vibrance").avant(JeLeFais.place(cle: "HDREditMode")))
        // La préréglage de balance avant la température, l'Auto avant l'exposition.
        XCTAssertTrue(JeLeFais.place(cle: "WhiteBalance").avant(JeLeFais.place(cle: "Temperature")))
        XCTAssertTrue(JeLeFais.place(cle: "AutoTone").avant(JeLeFais.place(cle: "Exposure2012")))
    }

    // MARK: Classement

    func testClasserLesEcarts() {
        func sorte(_ cle: String, _ d: JSONValue?, _ c: JSONValue?, _ v: JSONValue?, raw: Bool = true) -> String {
            JeLeFais.classer(depart: d, claude: c, vous: v, cle: cle, raw: raw).rawValue
        }
        // Exposition : tolérance de 0,1 IL.
        XCTAssertEqual(sorte("Exposure2012", 0, 0.35, 0.4), "comme_claude")
        XCTAssertEqual(sorte("Exposure2012", 0, 0.35, 0.8), "plus_fort")
        XCTAssertEqual(sorte("Exposure2012", 0, 0.35, 0.2), "moins_fort")
        XCTAssertEqual(sorte("Exposure2012", 0, 0.35, -0.3), "a_l_inverse")
        XCTAssertEqual(sorte("Exposure2012", 0, 0.35, 0.05), "oublie")
        // Un réglage que Claude ne touchait pas.
        XCTAssertEqual(sorte("Clarity2012", 0, 0, 20), "ajoute")
        XCTAssertEqual(sorte("Clarity2012", 0, 0, 4), "comme_claude", "sous la tolérance de 5 points")
        // Un départ absent vaut la valeur par défaut du catalogue.
        XCTAssertEqual(sorte("SharpenDetail", nil, 40, 25), "oublie")
        // Profil : un autre choix.
        XCTAssertEqual(sorte("CameraProfile", "Adobe Standard", "Adobe Color", "Camera CLASSIC CHROME"), "autre_choix")
        XCTAssertEqual(sorte("CameraProfile", "Adobe Standard", "Adobe Color", "Adobe Color"), "comme_claude")
        XCTAssertEqual(sorte("CameraProfile", "Adobe Standard", "Adobe Color", "Adobe Standard"), "oublie")
        // Température en kelvins pour un RAW (150 K), en relatif pour un JPEG (3).
        XCTAssertEqual(sorte("Temperature", 5000, 5600, 5700, raw: true), "comme_claude")
        XCTAssertEqual(sorte("Temperature", 5000, 5600, 5700, raw: false), "comme_claude", "des kelvins se reconnaissent à leur valeur")
        XCTAssertEqual(sorte("Temperature", 5000, 5600, 5900, raw: true), "plus_fort")
        XCTAssertEqual(sorte("Temperature", 0, 10, 15, raw: false), "plus_fort")
        XCTAssertEqual(sorte("Temperature", 0, 10, 12, raw: false), "comme_claude")
        // Un mode : ni plus ni moins fort.
        XCTAssertEqual(sorte("PerspectiveUpright", 0, 2, 1), "autre_choix")
        XCTAssertEqual(sorte("LensProfileEnable", false, true, true), "comme_claude")
        XCTAssertEqual(sorte("ColorGradeMidtoneHue", 0, 40, 200), "autre_choix", "une teinte est circulaire")
        // Les tables (courbes, couleurs ponctuelles) : « changée » ou « inchangée » depuis le départ ;
        // côté utilisateur, « changée » comme Claude, ou « changée autrement » (Variantes.ecartsExercice).
        XCTAssertEqual(sorte("ToneCurvePV2012", "inchangée", "changée", "inchangée"), "oublie")
        XCTAssertEqual(sorte("ToneCurvePV2012", "inchangée", "inchangée", "changée"), "ajoute")
        XCTAssertEqual(sorte("ToneCurvePV2012", "inchangée", "changée", "changée"), "comme_claude", "la même courbe que Claude")
        XCTAssertEqual(sorte("ToneCurvePV2012", "inchangée", "changée", "changée autrement"), "autre_choix")
        XCTAssertEqual(sorte("ToneCurvePV2012", "inchangée", "inchangée", "inchangée"), "comme_claude")
        XCTAssertEqual(sorte("ToneCurvePV2012", nil, "changée", "inchangée"), "oublie", "sans départ dit")
        // La Look, par son nom.
        XCTAssertEqual(sorte("Look", "aucune", "Adobe Vif", "Adobe Vif"), "comme_claude")
        XCTAssertEqual(sorte("Look", "aucune", "Adobe Vif", "aucune"), "oublie")
        // Un réglage automatique pas encore calculé ne se classe pas.
        XCTAssertEqual(sorte("Contrast2012", 0, .number(ToolHandler.pendingAutoValue), 10), "autre_choix")
        XCTAssertEqual(Set(JeLeFais.Sorte.allCases.map(\.rawValue)),
                       ["comme_claude", "plus_fort", "moins_fort", "a_l_inverse", "oublie", "ajoute", "autre_choix"])
    }

    // MARK: Écart principal

    func testEcartPrincipalMesureAuxSeuilsDuBilan() throws {
        let ecarts: [JSONValue] = [
            ecart("Exposure2012", 0, 0.35, 0.8),
            ecart("Shadows2012", 0, 0, 20),
            ecart("Vibrance", 0, 10, 10),
            ecart("Temperature", 5200, 5200, 5700),
        ]
        let exercice: JSONValue = ["instantane": "Claude · ma version", "ecarts": .array(ecarts)]
        // Seule l'exposition dépasse son seuil (+0,6 IL) : la famille exposition, et dans elle
        // Exposure2012 (0,45 IL, 4,5 fois sa tolérance) plutôt que Shadows2012 (20 points, 4 fois),
        // même si Shadows2012 est le plus grand rapporté à l'étendue du catalogue (10 % contre 4,5 %).
        let claire = JeLeFais.enrichir(exercice, raw: true, claude: mesures(), vous: mesures(mediane: clarte(50, plus: 0.6)))
        let principal = try XCTUnwrap(claire["ecart_principal"]?.object)
        XCTAssertEqual(principal["visible"], true)
        XCTAssertEqual(principal["mesure"], "exposition")
        XCTAssertEqual(principal["ecart"]?.double ?? 0, 0.6, accuracy: 0.05)
        XCTAssertEqual(principal["seuil"]?.double, Bilan.seuilExposition)
        XCTAssertEqual(principal["reglage"]?["cle"], "Exposure2012")
        XCTAssertEqual(principal["reglage"]?["sorte"], "plus_fort")
        let texte = try XCTUnwrap(principal["texte"]?.string)
        XCTAssertTrue(texte.hasPrefix("Votre version est plus claire de 0,6 IL (visible dès 0,1 IL)."), texte)
        XCTAssertTrue(texte.contains("Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude"), texte)

        // Une dominante b* de 3 (seuil 1,5) : la famille dominante_b, Temperature.
        let chaude = JeLeFais.enrichir(exercice, raw: true, claude: mesures(), vous: mesures(b: 3))
        XCTAssertEqual(chaude["ecart_principal"]?["mesure"], "dominante_b")
        XCTAssertEqual(chaude["ecart_principal"]?["reglage"]?["cle"], "Temperature")
        XCTAssertTrue(chaude["ecart_principal"]?["texte"]?.string?.contains("plus chaude (jaune)") == true)
        // Trop peu de tons neutres : la dominante ne se juge pas (comme au bilan).
        let peuNeutre = JeLeFais.enrichir(exercice, raw: true, claude: mesures(part: 2), vous: mesures(b: 3, part: 2))
        XCTAssertEqual(peuNeutre["ecart_principal"]?["visible"], false)

        // Tout sous les seuils : rien de visible.
        XCTAssertNil(JeLeFais.principal(claude: mesures(), vous: mesures(mediane: clarte(50, plus: 0.05), chroma: 13, b: 1),
                                        ecarts: [], raw: true))
        let pareilles = JeLeFais.enrichir(exercice, raw: true, claude: mesures(), vous: mesures(b: 1))
        XCTAssertEqual(pareilles["ecart_principal"]?["visible"], false)
        XCTAssertTrue(pareilles["ecart_principal"]?["texte"]?.string?.hasPrefix("Aucun écart mesuré") == true)

        // Un écart visible qu'aucun réglage global de sa famille n'explique.
        let sansReglage = JeLeFais.enrichir(["ecarts": [ecart("Vibrance", 0, 10, 10)]], raw: true,
                                            claude: mesures(), vous: mesures(mediane: clarte(50, plus: -0.5)))
        XCTAssertEqual(sansReglage["ecart_principal"]?["mesure"], "exposition")
        XCTAssertNil(sansReglage["ecart_principal"]?["reglage"])
        XCTAssertTrue(sansReglage["ecart_principal"]?["texte"]?.string?.contains("plus sombre") == true)
        XCTAssertTrue(sansReglage["ecart_principal"]?["texte"]?.string?.contains("Aucun réglage global") == true)
    }

    /// Le réglage qui explique l'écart principal pousse la mesure dans le sens de l'écart : une
    /// version plus claire ne s'explique pas par des Ombres plus basses, même de beaucoup ; une
    /// version plus contrastée s'explique par des Noirs plus bas (le sens est inverse).
    func testLeReglageEnCauseVaDansLeSensDeLEcart() throws {
        let claire = mesures(mediane: clarte(50, plus: 0.6))
        // Ombres : Claude +40, vous 0 (8 fois la tolérance), donc plus sombre ; Exposition : +0,8 au
        // lieu de +0,35 (4,5 fois), donc plus clair : c'est elle qui explique.
        let deux = JeLeFais.enrichir(["ecarts": [ecart("Shadows2012", 0, 40, 0), ecart("Exposure2012", 0, 0.35, 0.8)]],
                                     raw: true, claude: mesures(), vous: claire)
        XCTAssertEqual(deux["ecart_principal"]?["mesure"], "exposition")
        XCTAssertEqual(deux["ecart_principal"]?["reglage"]?["cle"], "Exposure2012")
        // Seules les Ombres, plus basses : rien de global n'explique une version plus claire.
        let inverse = JeLeFais.enrichir(["ecarts": [ecart("Shadows2012", 0, 40, 0)]], raw: true, claude: mesures(), vous: claire)
        XCTAssertNil(inverse["ecart_principal"]?["reglage"])
        XCTAssertTrue(inverse["ecart_principal"]?["texte"]?.string?.contains("Aucun réglage global") == true)
        // Plus contrastée : Noirs −30 (vous) au lieu de 0 l'explique ; Contraste −20 (vous) non.
        let contrastee = JeLeFais.enrichir(["ecarts": [ecart("Contrast2012", 0, 0, -20), ecart("Blacks2012", 0, 0, -30)]],
                                           raw: true, claude: mesures(p5: 20, p95: 80), vous: mesures(p5: 10, p95: 90))
        XCTAssertEqual(contrastee["ecart_principal"]?["mesure"], "contraste")
        XCTAssertEqual(contrastee["ecart_principal"]?["reglage"]?["cle"], "Blacks2012")
        // Plus chaude : la Température plus haute l'explique.
        let chaude = JeLeFais.enrichir(["ecarts": [ecart("Temperature", 5200, 5800, 5200), ecart("Tint", 0, 0, 10)]],
                                       raw: true, claude: mesures(b: 3), vous: mesures(b: 0))
        XCTAssertEqual(chaude["ecart_principal"]?["mesure"], "dominante_b")
        XCTAssertTrue(chaude["ecart_principal"]?["texte"]?.string?.contains("plus froide") == true)
        XCTAssertEqual(chaude["ecart_principal"]?["reglage"]?["cle"], "Temperature", "vous plus froid, Température plus basse")
        XCTAssertEqual(JeLeFais.sens("Blacks2012", "ombres_bouchees_pct"), -1)
        XCTAssertEqual(JeLeFais.sens("SaturationAdjustmentRed", "chroma_moyenne"), 1)
        XCTAssertNil(JeLeFais.sens("ColorGradeMidtoneHue", "dominante_b"), "une teinte n'a pas de sens simple")
    }

    /// Les écarts reçoivent panneau, réglage, sorte et texte, dans l'ordre des panneaux ; le cadre en
    /// une ligne ; ce qui est fait comme Claude, et un résumé.
    func testEnrichirLesEcarts() throws {
        let exercice: JSONValue = [
            "instantane": "Claude · ma version", "le": "2026-10-21 10:00",
            "ecarts": [
                ecart("Clarity2012", 0, 0, 20), ecart("Exposure2012", 0, 0.35, 0.8), ecart("Vibrance", 0, 10, 0),
                ecart("Contrast2012", 0, 10, 12),
                ecart("CropAngle", 0, -1.2, -1.2), ecart("CropLeft", 0, 0.02, 0.02),
                ecart("ToneCurvePV2012", "inchangée", "inchangée", "changée"),
                // Ce qui suit d'autres réglages (recadrage actif, nom de la courbe) : ni compté ni nommé.
                ecart("HasCrop", false, true, true), ecart("ToneCurveName2012", "Linear", "Linear", "Custom"),
            ],
            "listes": ["masques": ["depart": 0, "vous": 1], "taches": ["depart": 0, "vous": 0], "yeux_rouges": ["depart": 0, "vous": 0]],
            "restent": ["MaskGroupBasedCorrections", "RetouchAreas"],
            "rien_change": false,
        ]
        let enrichi = JeLeFais.enrichir(exercice, raw: true, claude: mesures(), vous: mesures())
        let liste = lignes(enrichi["ecarts"] ?? [])
        XCTAssertEqual(liste.compactMap { $0["cle"]?.string }, ["Exposure2012", "Contrast2012", "Clarity2012", "Vibrance", "ToneCurvePV2012", "Crop"])
        XCTAssertEqual(try ligne(liste, "Exposure2012")["sorte"], "plus_fort")
        XCTAssertEqual(try ligne(liste, "Exposure2012")["panneau"], "Réglages de base")
        XCTAssertEqual(try ligne(liste, "Exposure2012")["texte"],
                       "Réglages de base › Tonalité › Exposition : départ 0, Claude +0,35, vous +0,8 — plus fort que Claude")
        XCTAssertEqual(try ligne(liste, "Clarity2012")["sorte"], "ajoute")
        XCTAssertEqual(try ligne(liste, "Vibrance")["sorte"], "oublie")
        XCTAssertEqual(try ligne(liste, "ToneCurvePV2012")["sorte"], "ajoute")
        XCTAssertEqual(try ligne(liste, "ToneCurvePV2012")["texte"],
                       "Courbe des tonalités › Courbe par points › RVB : Claude inchangée, vous changée — ajouté par vous (Claude n'y touchait pas)",
                       "une table : changée ou non, sans « départ »")
        let cadre = try ligne(liste, "Crop")
        XCTAssertEqual(cadre["sorte"], "comme_claude")
        XCTAssertEqual(cadre["claude"]?["CropAngle"]?.double, -1.2)
        XCTAssertEqual(enrichi["comme_claude"], ["Contraste", "Cadre"])
        XCTAssertEqual(enrichi["resume"], "6 réglages comparés : 2 comme Claude, 1 plus fort, 1 oublié, 2 ajoutés.")
        // Le reste de la réponse du module passe tel quel ; ce qui reste dans les deux images est dit.
        XCTAssertEqual(enrichi["instantane"], "Claude · ma version")
        XCTAssertEqual(enrichi["listes"]?["masques"]?["vous"], 1)
        let aSavoir = try XCTUnwrap(enrichi["a_savoir_exercice"]?.string)
        XCTAssertTrue(aSavoir.contains("(masques, taches)") && aSavoir.contains("se voit dans les deux images"), aSavoir)
        XCTAssertFalse(aSavoir.contains("MaskGroupBasedCorrections"), "les listes en français")
        XCTAssertEqual(enrichi["ecart_principal"]?["visible"], false, "deux images mesurées pareilles")
        // Sans mesures (image illisible) : pas d'écart principal, dit.
        XCTAssertTrue(JeLeFais.enrichir(exercice, raw: true, claude: nil, vous: mesures())["ecart_principal"]?["texte"]?.string?
            .contains("non mesuré") == true)
    }

    // MARK: preview_settings avec my_turn

    /// Réponse d'essayer d'un module 1.3 avec exercice et sans_rendu : aucun chemin.
    func reponseMonTour() -> JSONValue {
        [
            "mode": "proposer d'abord", "photo": ["id": 7, "fichier": "DSCF1595.RAF", "copie_virtuelle": false], "etape": "Claude · essai : ma version (je le fais)",
            "instantane": "Claude · ma version", "exercice": ["instantane": "Claude · ma version"], "raw": true,
            "changements": [changement("Vibrance", 0, 10), changement("Temperature", 5200, 5600), changement("Exposure2012", 0, 0.35)],
            "remarques": [],
        ]
    }

    func testMyTurnRangeSansRienRendre() throws {
        let fake = FakeLightroom()
        fake.replies["essayer"] = reponseMonTour()
        let tools = ToolHandler(lightroom: fake)
        let result = tools.call(name: "preview_settings", arguments: [
            "settings": ["Exposure2012": 0.35, "Vibrance": 10, "Temperature": 5600], "my_turn": true, "photo_id": 7,
            "step_name": "lumière",
        ])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.commands, ["essayer"], "une seule commande, aucun aperçu")
        let params = fake.lastParams
        XCTAssertEqual(params["instantane"], "ma version")
        XCTAssertEqual(params["exercice"], true)
        XCTAssertEqual(params["sans_rendu"], true)
        XCTAssertEqual(params["action"], "appliquer")
        XCTAssertEqual(params["etape"], "ma version (je le fais)")
        XCTAssertEqual(params["raison"], "lumière", "le nom de la proposition : la raison de l'entrée « Claude · je le fais » du journal")
        XCTAssertEqual(params["photo"]?.int, 7)
        XCTAssertNil(params["entier"])
        XCTAssertNil(params["comparer"])
        XCTAssertNil(params["taille"])
        XCTAssertFalse(result.porteUneImage, "pas d'image")
        let info = try JSONCoding.parse(result.text)
        let faire = lignes(info["a_faire"] ?? [])
        XCTAssertEqual(faire.compactMap { $0["cle"]?.string }, ["Temperature", "Exposure2012", "Vibrance"])
        XCTAssertEqual(faire.first?["a"]?.string, "5\(fine)600\(insecable)K", "le côté RAW se lit dans raw de la réponse")
        XCTAssertEqual(info["ensuite"], "Quand l'utilisateur a fini : view_photo avec compare = claude_version.")
        XCTAssertEqual(info["instantane"], "Claude · ma version")
        XCTAssertEqual(info["photo"]?["id"], 7)
        XCTAssertTrue(info["rien_n_est_applique"]?.string?.contains("choose_variant « ma version »") == true)
        XCTAssertNil(info["remarques_serveur"])

        // compare, size et overlay sont sans effet : une remarque, toujours rien de rendu.
        let avecCompare = tools.call(name: "preview_settings", arguments: [
            "settings": ["Exposure2012": 0.35], "my_turn": true, "compare": true, "size": 2048,
        ])
        XCTAssertFalse(avecCompare.isError, avecCompare.text)
        XCTAssertEqual(fake.commands, ["essayer", "essayer"])
        XCTAssertNil(fake.lastParams["comparer"])
        XCTAssertNil(fake.lastParams["taille"])
        XCTAssertFalse(avecCompare.porteUneImage)
        let remarques = try JSONCoding.parse(avecCompare.text)["remarques_serveur"]?.array?.compactMap(\.string) ?? []
        XCTAssertTrue(remarques.contains { $0.hasPrefix("compare, size sans effet avec my_turn") }, "\(remarques)")
        // compare = false ne demandait rien : pas de remarque.
        let sansCompare = tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.35], "my_turn": true, "compare": false])
        XCTAssertFalse(sansCompare.isError, sansCompare.text)
        XCTAssertNil(try JSONCoding.parse(sansCompare.text)["remarques_serveur"])
    }

    /// Relecture du lot 5 : un recadrage avec my_turn n'envoie jamais entier (rien n'est rendu), et
    /// la ligne du cadre est dans la liste.
    func testMyTurnAvecCropNEnvoiePasEntier() throws {
        let fake = FakeLightroom()
        var reponse = reponseMonTour().object ?? [:]
        reponse["changements"] = [changement("CropAngle", 0, -1.2), changement("CropLeft", 0, 0.02)]
        fake.replies["essayer"] = .object(reponse)
        let tools = ToolHandler(lightroom: fake)
        let result = tools.call(name: "preview_settings", arguments: ["crop": ["angle": -1.2, "aspect": "4:5"], "my_turn": true])
        XCTAssertFalse(result.isError, result.text)
        // La géométrie est lue (recalage du recadrage, comme aujourd'hui), puis un seul essai.
        XCTAssertEqual(fake.commands, ["geometrie", "essayer"])
        XCTAssertNil(fake.lastParams["entier"], "my_turn : pas d'image entière")
        XCTAssertNotNil(fake.lastParams["recadrage"])
        XCTAssertFalse(result.porteUneImage)
        let faire = lignes(try JSONCoding.parse(result.text)["a_faire"] ?? [])
        XCTAssertEqual(faire.first?["panneau"], "Recadrage")
        // Sans my_turn, le même recadrage part avec entier (lot 5).
        _ = tools.call(name: "preview_settings", arguments: ["crop": ["angle": -1.2, "aspect": "4:5"]])
        XCTAssertEqual(fake.calls.last?.params["entier"], true)
    }

    /// Un module d'avant la 1.3 ignore exercice et sans_rendu : il rend quand même. Ses aperçus sont
    /// effacés, et l'outil dit de mettre le module à jour.
    func testMyTurnAvecUnModuleAncien() throws {
        let fake = FakeLightroom()
        fake.moduleVersion = "1.2"
        let chemin = TestSupport.previewFile(TestSupport.jpeg(red: 120, green: 120, blue: 120))
        fake.replies["essayer"] = ["chemin": .string(chemin), "instantane": "Claude · ma version",
                                   "changements": [changement("Exposure2012", 0, 0.35)]]
        let result = ToolHandler(lightroom: fake).call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.35], "my_turn": true])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("ne connaît pas encore « Je le fais »"), result.text)
        XCTAssertTrue(result.text.contains("(version 1.2)"), result.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chemin), "l'aperçu rendu est effacé")
    }

    /// Relecture du lot 1 : preview_settings avec my_turn ne porte pas d'image, donc ne consomme pas
    /// la remarque de l'écran ; le view_photo suivant la porte.
    func testMyTurnNeConsommePasLaRemarqueDeLEcran() throws {
        let fake = FakeLightroom()
        fake.replies["essayer"] = reponseMonTour()
        let image = TestSupport.jpeg(red: 120, green: 120, blue: 120)
        fake.onSend = { [unowned fake] command, _ in
            if command == "apercu" { fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(image)), "photo": ["id": 7]] }
        }
        let tools = ToolHandler(lightroom: fake)
        var lectures = 0
        tools.lireEcran = { lectures += 1; return Ecran.Etat(principal: EcranTests.odyssey) }
        let tour = tools.call(name: "preview_settings", arguments: ["settings": ["Exposure2012": 0.35], "my_turn": true])
        XCTAssertFalse(tour.isError, tour.text)
        XCTAssertEqual(EcranTests.textes(tour).count, 1, "pas de remarque sans image")
        XCTAssertNotNil(try JSONCoding.parse(tour.text)["a_faire"], "le texte reste du JSON lisible")
        XCTAssertEqual(lectures, 0, "l'écran n'est pas encore lu")
        let vue = tools.call(name: "view_photo", arguments: [:])
        XCTAssertFalse(vue.isError, vue.text)
        XCTAssertEqual(EcranTests.textes(vue).last, Ecran.remarque(EcranTests.odyssey))
        XCTAssertEqual(lectures, 1)
    }

    // MARK: view_photo avec compare = claude_version

    /// Faux module : la version de Claude (à gauche, chemin_avant) et celle de l'utilisateur
    /// (chemin), avec l'exercice que rend apercu avec comparer = versionClaude.
    func moduleComparaison(claude: UInt8 = 100, vous: UInt8 = 140, exercice: JSONValue? = nil) -> FakeLightroom {
        let fake = FakeLightroom()
        let exercice = exercice ?? [
            "instantane": "Claude · ma version", "le": "2026-10-21 10:00",
            "ecarts": [ecart("Exposure2012", 0, 0.35, 0.8), ecart("Clarity2012", 0, 0, 20), ecart("Vibrance", 0, 10, 0),
                       ecart("Temperature", 5200, 5600, 5650)],
            "listes": ["masques": ["depart": 0, "vous": 1], "taches": ["depart": 0, "vous": 0], "yeux_rouges": ["depart": 0, "vous": 0]], "restent": [], "rien_change": false,
        ]
        fake.onSend = { [unowned fake] command, params in
            guard command == "apercu" else { return }
            var reponse: [String: JSONValue] = [
                "chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: vous, green: vous, blue: vous, width: 600, height: 400))),
                "photo": ["id": 7, "fichier": "DSCF1595.RAF"], "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                "reglages": ["Exposure2012": 0.8, "Clarity2012": 20, "Temperature": 5650],
            ]
            if params["comparer"] != nil {
                reponse["chemin_avant"] = .string(TestSupport.previewFile(TestSupport.jpeg(red: claude, green: claude, blue: claude, width: 600, height: 400)))
                if params["comparer"] == "versionClaude" { reponse["exercice"] = exercice }
            }
            fake.replies["apercu"] = .object(reponse)
        }
        return fake
    }

    func testViewPhotoMontreLesDeuxVersionsEtLesEcarts() throws {
        let fake = moduleComparaison()
        let tools = ToolHandler(lightroom: fake)
        let result = tools.call(name: "view_photo", arguments: ["compare": "claude_version"])
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(fake.lastParams["comparer"], "versionClaude")
        XCTAssertNil(fake.lastParams["point_af"], "pas de point de mise au point sur un avant/après")
        XCTAssertTrue(result.porteUneImage)
        // L'image : les deux versions côte à côte.
        guard case .image(let base64, _)? = result.content.first, let data = Data(base64Encoded: base64),
              let image = PreviewImages.image(data) else { return XCTFail("pas d'image") }
        XCTAssertGreaterThan(image.width, 1200, "deux images de 600 côte à côte")
        let info = try JSONCoding.parse(result.text)
        XCTAssertEqual(info["image"], "À gauche ma version (Claude), à droite la vôtre.")
        XCTAssertTrue(info["bilan"]?["depuis"]?.string?.hasPrefix("ma version") == true, "\(info["bilan"] ?? .null)")
        XCTAssertNotNil(info["bilan"]?["ecarts"]?["exposition"], "la version de l'utilisateur est plus claire")
        let exercice = try XCTUnwrap(info["exercice"])
        let ecarts = lignes(exercice["ecarts"] ?? [])
        XCTAssertEqual(try ligne(ecarts, "Exposure2012")["sorte"], "plus_fort")
        XCTAssertEqual(try ligne(ecarts, "Exposure2012")["panneau"], "Réglages de base")
        XCTAssertTrue(try ligne(ecarts, "Exposure2012")["texte"]?.string?.hasSuffix("plus fort que Claude") == true)
        XCTAssertEqual(try ligne(ecarts, "Clarity2012")["sorte"], "ajoute")
        XCTAssertEqual(try ligne(ecarts, "Vibrance")["sorte"], "oublie")
        XCTAssertEqual(try ligne(ecarts, "Temperature")["sorte"], "comme_claude", "50 K : sous la tolérance d'un RAW (raw d'après l'échelle)")
        XCTAssertEqual(exercice["comme_claude"], ["Température"])
        XCTAssertEqual(exercice["ecart_principal"]?["visible"], true)
        XCTAssertEqual(exercice["ecart_principal"]?["mesure"], "exposition")
        XCTAssertEqual(exercice["ecart_principal"]?["reglage"]?["cle"], "Exposure2012")
        XCTAssertEqual(exercice["listes"]?["masques"]?["vous"], 1)
        XCTAssertNil(info["chemin_avant"])
        XCTAssertNil(info["photo"]?["chemin_original"])
        // view_photo reste en lecture seule.
        let definition = try XCTUnwrap(tools.definitions.first { $0["name"] == "view_photo" })
        XCTAssertEqual(definition["annotations"]?["readOnlyHint"], true)
    }

    func testViewPhotoRefuseUneComparaisonInconnue() {
        let fake = moduleComparaison()
        let result = ToolHandler(lightroom: fake).call(name: "view_photo", arguments: ["compare": "ma_version"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("claude_version"), result.text)
        XCTAssertEqual(fake.commands, [], "rien n'est envoyé")
    }

    /// Un module d'avant la 1.3 prendrait versionClaude pour l'étape précédente : refusé, ses deux
    /// aperçus effacés.
    func testViewPhotoClaudeVersionAvecUnModuleAncien() throws {
        let fake = FakeLightroom()
        let apres = TestSupport.previewFile(TestSupport.jpeg(red: 140, green: 140, blue: 140))
        let avant = TestSupport.previewFile(TestSupport.jpeg(red: 100, green: 100, blue: 100))
        fake.replies["apercu"] = ["chemin": .string(apres), "chemin_avant": .string(avant), "photo": ["id": 7]]
        let result = ToolHandler(lightroom: fake).call(name: "view_photo", arguments: ["compare": "claude_version"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("ne connaît pas encore « Je le fais »"), result.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: apres))
        XCTAssertFalse(FileManager.default.fileExists(atPath: avant))
        // Les autres comparaisons ne demandent pas d'exercice.
        fake.replies["apercu"] = ["chemin": .string(TestSupport.previewFile(TestSupport.jpeg(red: 140, green: 140, blue: 140))),
                                  "chemin_avant": .string(TestSupport.previewFile(TestSupport.jpeg(red: 100, green: 100, blue: 100)))]
        XCTAssertFalse(ToolHandler(lightroom: fake).call(name: "view_photo", arguments: ["compare": "before_claude"]).isError)
    }

    // MARK: Descriptions

    /// Seules deux propriétés changent : my_turn (nouvelle) et compare (claude_version). Les
    /// descriptions des deux outils restent sous leurs gardes (BilanTests).
    func testLesProprietesDisentJeLeFais() throws {
        let definitions = ToolHandler(lightroom: FakeLightroom()).definitions
        let proposition = try XCTUnwrap(definitions.first { $0["name"] == "preview_settings" })
        let tour = try XCTUnwrap(proposition["inputSchema"]?["properties"]?["my_turn"])
        XCTAssertEqual(tour["type"], "boolean")
        let texte = try XCTUnwrap(tour["description"]?.string)
        for attendu in ["« Je le fais »", "« Claude · ma version »", "a_faire", "ordre du panneau Développement", "compare = claude_version"] {
            XCTAssertTrue(texte.contains(attendu), "my_turn sans « \(attendu) »")
        }
        XCTAssertFalse(proposition["description"]?.string?.contains("my_turn") == true, "la description de l'outil ne change pas")
        let vue = try XCTUnwrap(definitions.first { $0["name"] == "view_photo" })
        let compare = try XCTUnwrap(vue["inputSchema"]?["properties"]?["compare"])
        XCTAssertEqual(compare["enum"], ["before_claude", "previous_step", "claude_version"])
        XCTAssertTrue(compare["description"]?.string?.contains("claude_version = « Je le fais »") == true)
        XCTAssertTrue(compare["description"]?.string?.contains("ecart_principal") == true)
        XCTAssertLessThanOrEqual(try XCTUnwrap(vue["description"]?.string).count, 1850)
        XCTAssertLessThanOrEqual(try XCTUnwrap(proposition["description"]?.string).count, 600)
    }
}
