import Foundation

/// Un réglage de développement de Lightroom Classic que Claude peut lire et modifier.
/// `key` est le nom employé par le SDK de Lightroom (le même que dans les fichiers XMP, sans « crs: »).
public struct DevelopSetting: Equatable {
    public var key: String
    public var label: String
    public var group: String
    public var min: Double
    public var max: Double
    /// Réglage à valeurs entières seulement (un mode, un interrupteur).
    public var isWhole: Bool
    /// Interrupteur que Lightroom range en vrai ou faux (et non 0 ou 1).
    public var isBoolean: Bool
    /// Valeur par défaut de Lightroom, sans effet propre, que view_photo ne montre pas (0 pour la
    /// plupart ; relevées dans Lightroom Classic 15.6 sur une copie RAW et un JPEG jamais retouchés :
    /// rayon de netteté 1, détail 25, détail du bruit 50, milieu et contour du vignetage 50, taille du
    /// grain 25, teintes des franges 30/70 et 40/60, échelles du profil d'objectif 100, fusion de
    /// l'étalonnage 50). Voir `rawDefaults` pour ce qui dépend du format.
    public var neutral: Double
    /// Version de Lightroom Classic qui a introduit ce réglage (nil : plus ancien que la 8) : sur
    /// une version plus ancienne, le serveur refuse plutôt que d'écrire une clé ignorée.
    public var since: String?

    public init(_ key: String, _ label: String, group: String, min: Double, max: Double, whole: Bool = false, boolean: Bool = false,
                neutral: Double = 0, since: String? = nil) {
        self.key = key
        self.label = label
        self.group = group
        self.min = min
        self.max = max
        self.isWhole = whole || boolean || (min == 0 && max == 1)
        self.isBoolean = boolean
        self.neutral = neutral
        self.since = since
    }

    /// Réglage à deux états (0 = désactivé, 1 = activé).
    public var isSwitch: Bool { min == 0 && max == 1 }

    public var range: JSONValue { [.number(min), .number(max)] }
}

/// Un profil d'appareil que Claude peut choisir. `name` est la valeur de `CameraProfile` dans
/// les réglages de Lightroom ; `make`, la marque d'appareil à laquelle le profil est réservé ;
/// `variants`, les autres orthographes du nom selon l'appareil, que le module essaie quand
/// Lightroom ne garde pas `name` (voir docs/SPEC.md, Profil) ; `missingOn`, les modèles pour
/// lesquels Lightroom range le nom mais rend Adobe Standard (constaté au rendu) : le module refuse.
public struct CameraProfile: Equatable {
    public var name: String
    public var description: String
    public var make: String?
    public var variants: [String]
    public var missingOn: [String]

    public init(_ name: String, _ description: String, make: String? = nil, variants: [String] = [], missingOn: [String] = []) {
        self.name = name
        self.description = description
        self.make = make
        self.variants = variants
        self.missingOn = missingOn
    }

    /// Vrai pour son nom ou l'une de ses variantes, sans tenir compte de la casse.
    public func matches(_ name: String) -> Bool {
        let wanted = name.lowercased()
        return ([self.name] + variants).contains { $0.lowercased() == wanted }
    }
}

/// Les réglages globaux pris en charge : balance des blancs, tonalité, présence, courbe
/// paramétrique, TSL, noir et blanc, étalonnage des couleurs, détail, effets, optique,
/// transformation et calibrage de l'appareil. Le profil, le recadrage, la courbe par points et
/// la couleur ponctuelle passent par leurs propres paramètres ; les masques et les retouches de
/// taches, par leurs propres outils.
public enum DevelopCatalogue {
    /// La température est en kelvins pour un RAW ou un DNG (2000 à 50000) et relative pour un
    /// JPEG, un TIFF ou un HEIC (−100 à +100) ; la teinte va de −150 à +150 (RAW) ou de −100 à +100.
    /// Le module Lightroom applique la bonne plage selon la photo.
    public static let temperatureKey = "Temperature"
    public static let tintKey = "Tint"

    private static let colors: [(String, String)] = [
        ("Red", "rouge"), ("Orange", "orange"), ("Yellow", "jaune"), ("Green", "vert"),
        ("Aqua", "bleu-vert"), ("Blue", "bleu"), ("Purple", "pourpre"), ("Magenta", "magenta"),
    ]

    public static let all: [DevelopSetting] = {
        var list: [DevelopSetting] = [
            DevelopSetting(temperatureKey, "Température", group: "Balance des blancs", min: -100, max: 50000),
            DevelopSetting(tintKey, "Teinte", group: "Balance des blancs", min: -150, max: 150),

            DevelopSetting("Exposure2012", "Exposition", group: "Tonalité", min: -5, max: 5),
            DevelopSetting("Contrast2012", "Contraste", group: "Tonalité", min: -100, max: 100),
            DevelopSetting("Highlights2012", "Hautes lumières", group: "Tonalité", min: -100, max: 100),
            DevelopSetting("Shadows2012", "Ombres", group: "Tonalité", min: -100, max: 100),
            DevelopSetting("Whites2012", "Blancs", group: "Tonalité", min: -100, max: 100),
            DevelopSetting("Blacks2012", "Noirs", group: "Tonalité", min: -100, max: 100),

            // Édition HDR (Lightroom Classic 13.0). Plages relevées dans le code de Lightroom Classic
            // 15.6 (AgDevelopParams, AgCameraRawUtils) : curseurs de l'aperçu SDR de −100 à +100 ;
            // limite HDR en crans, au dixième (le menu de Lightroom propose 1, 2, 3, 4 et 8, « Maxi ») ;
            // constaté le 17 octobre 2026 : 2,3 sur une photo jamais passée en HDR.
            DevelopSetting("HDREditMode", "Mode d'édition HDR", group: "HDR", min: 0, max: 1, since: "13.0"),
            DevelopSetting("HDRMaxValue", "Limite HDR, en crans (Lightroom propose 1, 2, 3, 4 ou 8 = maxi)", group: "HDR", min: 0, max: 8, since: "13.0"),
            DevelopSetting("SDRBrightness", "Aperçu SDR : luminosité", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRContrast", "Aperçu SDR : contraste", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRClarity", "Aperçu SDR : clarté", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRHighlights", "Aperçu SDR : hautes lumières", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRShadows", "Aperçu SDR : ombres", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRWhites", "Aperçu SDR : blancs", group: "HDR", min: -100, max: 100, since: "13.0"),
            DevelopSetting("SDRBlend", "Aperçu SDR : saturation des hautes lumières", group: "HDR", min: -100, max: 100, since: "13.0"),

            DevelopSetting("Texture", "Texture", group: "Présence", min: -100, max: 100, since: "8.3"),
            DevelopSetting("Clarity2012", "Clarté", group: "Présence", min: -100, max: 100),
            DevelopSetting("Dehaze", "Correction du voile", group: "Présence", min: -100, max: 100),
            DevelopSetting("Vibrance", "Vibrance", group: "Présence", min: -100, max: 100),
            DevelopSetting("Saturation", "Saturation", group: "Présence", min: -100, max: 100),

            DevelopSetting("ParametricHighlights", "Courbe : hautes lumières", group: "Courbe des tonalités", min: -100, max: 100),
            DevelopSetting("ParametricLights", "Courbe : tons clairs", group: "Courbe des tonalités", min: -100, max: 100),
            DevelopSetting("ParametricDarks", "Courbe : tons foncés", group: "Courbe des tonalités", min: -100, max: 100),
            DevelopSetting("ParametricShadows", "Courbe : ombres", group: "Courbe des tonalités", min: -100, max: 100),
            // Plages et défauts relevés dans Camera Raw (Lightroom Classic 15.6, getCRParamsInfo).
            DevelopSetting("ParametricShadowSplit", "Courbe : limite ombres / tons foncés (défaut 25)", group: "Courbe des tonalités", min: 10, max: 70, neutral: 25),
            DevelopSetting("ParametricMidtoneSplit", "Courbe : limite tons foncés / tons clairs (défaut 50)", group: "Courbe des tonalités", min: 20, max: 80, neutral: 50),
            DevelopSetting("ParametricHighlightSplit", "Courbe : limite tons clairs / hautes lumières (défaut 75)", group: "Courbe des tonalités", min: 30, max: 90, neutral: 75),
            DevelopSetting("CurveRefineSaturation", "Courbe : affiner la saturation (100 par défaut ; plus bas retire la saturation qu'ajoute une courbe contrastée)", group: "Courbe des tonalités", min: 0, max: 100, neutral: 100),
        ]
        for (prefix, word) in [("HueAdjustment", "Teinte"), ("SaturationAdjustment", "Saturation"), ("LuminanceAdjustment", "Luminance")] {
            for (color, name) in colors {
                list.append(DevelopSetting(prefix + color, "TSL : \(word.lowercased()) \(name)", group: "TSL", min: -100, max: 100))
            }
        }
        list.append(DevelopSetting("ConvertToGrayscale", "Traitement noir et blanc (0 couleur, 1 noir et blanc)", group: "Noir et blanc", min: 0, max: 1, boolean: true))
        for (color, name) in colors {
            list.append(DevelopSetting("GrayMixer" + color, "Mélangeur noir et blanc : \(name)", group: "Noir et blanc", min: -100, max: 100))
        }
        list += [
            DevelopSetting("SplitToningShadowHue", "Étalonnage : teinte des ombres", group: "Étalonnage des couleurs", min: 0, max: 359),
            DevelopSetting("SplitToningShadowSaturation", "Étalonnage : saturation des ombres", group: "Étalonnage des couleurs", min: 0, max: 100),
            DevelopSetting("ColorGradeShadowLum", "Étalonnage : luminance des ombres", group: "Étalonnage des couleurs", min: -100, max: 100),
            DevelopSetting("ColorGradeMidtoneHue", "Étalonnage : teinte des tons moyens", group: "Étalonnage des couleurs", min: 0, max: 359),
            DevelopSetting("ColorGradeMidtoneSat", "Étalonnage : saturation des tons moyens", group: "Étalonnage des couleurs", min: 0, max: 100),
            DevelopSetting("ColorGradeMidtoneLum", "Étalonnage : luminance des tons moyens", group: "Étalonnage des couleurs", min: -100, max: 100),
            DevelopSetting("SplitToningHighlightHue", "Étalonnage : teinte des hautes lumières", group: "Étalonnage des couleurs", min: 0, max: 359),
            DevelopSetting("SplitToningHighlightSaturation", "Étalonnage : saturation des hautes lumières", group: "Étalonnage des couleurs", min: 0, max: 100),
            DevelopSetting("ColorGradeHighlightLum", "Étalonnage : luminance des hautes lumières", group: "Étalonnage des couleurs", min: -100, max: 100),
            DevelopSetting("ColorGradeGlobalHue", "Étalonnage : teinte globale", group: "Étalonnage des couleurs", min: 0, max: 359),
            DevelopSetting("ColorGradeGlobalSat", "Étalonnage : saturation globale", group: "Étalonnage des couleurs", min: 0, max: 100),
            DevelopSetting("ColorGradeGlobalLum", "Étalonnage : luminance globale", group: "Étalonnage des couleurs", min: -100, max: 100),
            DevelopSetting("ColorGradeBlending", "Étalonnage : fusion (défaut 50)", group: "Étalonnage des couleurs", min: 0, max: 100, neutral: 50),
            DevelopSetting("SplitToningBalance", "Étalonnage : équilibre", group: "Étalonnage des couleurs", min: -100, max: 100),

            DevelopSetting("Sharpness", "Netteté : gain (défaut 40 pour un RAW, 0 sinon)", group: "Détail", min: 0, max: 150),
            DevelopSetting("SharpenRadius", "Netteté : rayon (défaut 1)", group: "Détail", min: 0.5, max: 3, neutral: 1),
            DevelopSetting("SharpenDetail", "Netteté : détail (défaut 25)", group: "Détail", min: 0, max: 100, neutral: 25),
            DevelopSetting("SharpenEdgeMasking", "Netteté : masquage", group: "Détail", min: 0, max: 100),
            DevelopSetting("LuminanceSmoothing", "Réduction du bruit : luminance", group: "Détail", min: 0, max: 100),
            DevelopSetting("LuminanceNoiseReductionDetail", "Réduction du bruit : détail de la luminance (défaut 50)", group: "Détail", min: 0, max: 100, neutral: 50),
            DevelopSetting("LuminanceNoiseReductionContrast", "Réduction du bruit : contraste de la luminance", group: "Détail", min: 0, max: 100),
            DevelopSetting("ColorNoiseReduction", "Réduction du bruit : couleur (défaut 25 pour un RAW, 0 sinon)", group: "Détail", min: 0, max: 100),
            DevelopSetting("ColorNoiseReductionDetail", "Réduction du bruit : détail de la couleur (défaut 50)", group: "Détail", min: 0, max: 100, neutral: 50),
            DevelopSetting("ColorNoiseReductionSmoothness", "Réduction du bruit : lissage de la couleur (défaut 50)", group: "Détail", min: 0, max: 100, neutral: 50),

            DevelopSetting("PostCropVignetteAmount", "Vignetage : gain", group: "Effets", min: -100, max: 100),
            DevelopSetting("PostCropVignetteMidpoint", "Vignetage : milieu (défaut 50)", group: "Effets", min: 0, max: 100, neutral: 50),
            DevelopSetting("PostCropVignetteFeather", "Vignetage : contour progressif (défaut 50)", group: "Effets", min: 0, max: 100, neutral: 50),
            DevelopSetting("PostCropVignetteRoundness", "Vignetage : arrondi", group: "Effets", min: -100, max: 100),
            DevelopSetting("PostCropVignetteStyle", "Vignetage : style (1 priorité aux hautes lumières, 2 priorité couleur, 3 peinture)", group: "Effets", min: 1, max: 3, whole: true, neutral: 1),
            DevelopSetting("PostCropVignetteHighlightContrast", "Vignetage : hautes lumières", group: "Effets", min: 0, max: 100),
            DevelopSetting("GrainAmount", "Grain : gain", group: "Effets", min: 0, max: 100),
            DevelopSetting("GrainSize", "Grain : taille (défaut 25)", group: "Effets", min: 0, max: 100, neutral: 25),
            DevelopSetting("GrainFrequency", "Grain : cassure (défaut 50)", group: "Effets", min: 0, max: 100, neutral: 50),

            DevelopSetting("LensProfileEnable", "Corrections de profil d'objectif (0 ou 1)", group: "Optique", min: 0, max: 1),
            DevelopSetting("AutoLateralCA", "Suppression de l'aberration chromatique (0 ou 1)", group: "Optique", min: 0, max: 1),
            DevelopSetting("LensProfileDistortionScale", "Profil d'objectif : correction de la distorsion (%, défaut 100)", group: "Optique", min: 0, max: 200, neutral: 100),
            DevelopSetting("LensProfileVignettingScale", "Profil d'objectif : correction du vignetage (%, défaut 100)", group: "Optique", min: 0, max: 200, neutral: 100),
            DevelopSetting("LensManualDistortionAmount", "Distorsion manuelle", group: "Optique", min: -100, max: 100),
            DevelopSetting("VignetteAmount", "Vignetage de l'objectif : gain", group: "Optique", min: -100, max: 100),
            DevelopSetting("VignetteMidpoint", "Vignetage de l'objectif : milieu (défaut 50)", group: "Optique", min: 0, max: 100, neutral: 50),
            DevelopSetting("DefringePurpleAmount", "Franges pourpres : gain", group: "Optique", min: 0, max: 20),
            DevelopSetting("DefringePurpleHueLo", "Franges pourpres : teinte basse (défaut 30)", group: "Optique", min: 0, max: 100, neutral: 30),
            DevelopSetting("DefringePurpleHueHi", "Franges pourpres : teinte haute (défaut 70)", group: "Optique", min: 0, max: 100, neutral: 70),
            DevelopSetting("DefringeGreenAmount", "Franges vertes : gain", group: "Optique", min: 0, max: 20),
            DevelopSetting("DefringeGreenHueLo", "Franges vertes : teinte basse (défaut 40)", group: "Optique", min: 0, max: 100, neutral: 40),
            DevelopSetting("DefringeGreenHueHi", "Franges vertes : teinte haute (défaut 60)", group: "Optique", min: 0, max: 100, neutral: 60),

            DevelopSetting("PerspectiveUpright", "Upright (0 désactivé, 1 auto, 2 complet, 3 niveau, 4 vertical)", group: "Transformation", min: 0, max: 4, whole: true),
            DevelopSetting("PerspectiveVertical", "Transformation : verticale", group: "Transformation", min: -100, max: 100),
            DevelopSetting("PerspectiveHorizontal", "Transformation : horizontale", group: "Transformation", min: -100, max: 100),
            DevelopSetting("PerspectiveRotate", "Transformation : rotation", group: "Transformation", min: -10, max: 10),
            DevelopSetting("PerspectiveAspect", "Transformation : aspect", group: "Transformation", min: -100, max: 100),
            DevelopSetting("PerspectiveScale", "Transformation : échelle", group: "Transformation", min: 50, max: 150, neutral: 100),
            DevelopSetting("PerspectiveX", "Transformation : décalage horizontal", group: "Transformation", min: -100, max: 100),
            DevelopSetting("PerspectiveY", "Transformation : décalage vertical", group: "Transformation", min: -100, max: 100),

            DevelopSetting("ShadowTint", "Calibrage : teinte des ombres", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("RedHue", "Calibrage : rouge primaire, teinte", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("RedSaturation", "Calibrage : rouge primaire, saturation", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("GreenHue", "Calibrage : vert primaire, teinte", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("GreenSaturation", "Calibrage : vert primaire, saturation", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("BlueHue", "Calibrage : bleu primaire, teinte", group: "Calibrage de l'appareil", min: -100, max: 100),
            DevelopSetting("BlueSaturation", "Calibrage : bleu primaire, saturation", group: "Calibrage de l'appareil", min: -100, max: 100),
        ]
        return list
    }()

    /// Réglages que Lightroom range en vrai ou faux : le module les convertit.
    public static var booleanKeys: [String] { all.filter(\.isBoolean).map(\.key) }

    /// Valeurs par défaut propres aux RAW (relevées dans Lightroom Classic 15.6 : un JPEG part de 0) :
    /// la netteté et la réduction du bruit de couleur que Lightroom applique à tout RAW. view_photo ne
    /// les montre pas sur un RAW, comme les autres valeurs par défaut.
    public static let rawDefaults: [String: Double] = ["Sharpness": 40, "ColorNoiseReduction": 25]

    // MARK: Profils

    /// Clé du profil dans les réglages de Lightroom.
    public static let profileKey = "CameraProfile"

    /// Profils qu'il suffit de nommer : Adobe Standard et les simulations de film Fujifilm
    /// rangées en profils DCP. Les profils à base de « Look » (Adobe Color, CLASSIC Neg.,
    /// NOSTALGIC Neg.…) demandent davantage et ne sont pas dans cette liste (la lecture du boîtier,
    /// IntentionBoitier, les cherche parmi les profils installés). Les noms sont ceux que
    /// Lightroom Classic 15.6 range pour un X-H2S (relevés le 16 octobre 2026) : il les cherche sans
    /// tenir compte de la casse, mais la ponctuation compte (« Camera PRO Neg. Hi » n'y est pas) ;
    /// `variants` garde l'orthographe des appareils plus anciens.
    public static let profiles: [CameraProfile] = [
        CameraProfile("Adobe Standard", "neutre, le profil de base d'Adobe"),
        CameraProfile("Camera PROVIA/Standard", "PROVIA : rendu standard et polyvalent", make: "FUJIFILM"),
        CameraProfile("Camera Velvia/Vivid", "Velvia : couleurs saturées et contraste fort, pour le paysage", make: "FUJIFILM"),
        CameraProfile("Camera ASTIA/Soft", "ASTIA : doux, peau flatteuse, ciels encore colorés", make: "FUJIFILM"),
        CameraProfile("Camera CLASSIC CHROME", "CLASSIC CHROME : couleurs sourdes, ombres marquées, style reportage", make: "FUJIFILM"),
        // Constaté en 2.4 sur un RAF de X-T20 : ETERNA et REALA ACE gardent leur nom, mais le rendu
        // est celui d'Adobe Standard (mêmes chroma, contraste et tons neutres, au centième près).
        CameraProfile("Camera REALA ACE", "REALA ACE : couleurs fidèles, contraste net, polyvalent (appareils récents)", make: "FUJIFILM",
                      missingOn: ["X-T20"]),
        CameraProfile("Camera Pro Neg Hi", "PRO Neg. Hi : portrait, un peu plus de contraste", make: "FUJIFILM", variants: ["Camera PRO Neg. Hi"]),
        CameraProfile("Camera Pro Neg Std", "PRO Neg. Std : portrait, très doux et neutre", make: "FUJIFILM", variants: ["Camera PRO Neg. Std"]),
        CameraProfile("Camera ETERNA/Cinema", "ETERNA : cinéma, couleurs et contraste retenus", make: "FUJIFILM", missingOn: ["X-T20"]),
        CameraProfile("Camera ACROS", "ACROS : noir et blanc fin et riche", make: "FUJIFILM"),
        CameraProfile("Camera ACROS+Ye Filter", "ACROS, filtre jaune : ciels un peu plus sombres", make: "FUJIFILM"),
        CameraProfile("Camera ACROS+R Filter", "ACROS, filtre rouge : ciels sombres, contraste fort", make: "FUJIFILM"),
        CameraProfile("Camera ACROS+G Filter", "ACROS, filtre vert : peau plus douce", make: "FUJIFILM"),
        CameraProfile("Camera Monochrome", "MONOCHROME : noir et blanc standard", make: "FUJIFILM"),
        CameraProfile("Camera Monochrome+Ye Filter", "MONOCHROME, filtre jaune", make: "FUJIFILM"),
        CameraProfile("Camera Monochrome+R Filter", "MONOCHROME, filtre rouge", make: "FUJIFILM"),
        CameraProfile("Camera Monochrome+G Filter", "MONOCHROME, filtre vert", make: "FUJIFILM"),
    ]

    /// Le profil d'appareil de ce nom ou de l'une de ses variantes, sans tenir compte de la casse.
    public static func profile(_ name: String) -> CameraProfile? {
        profiles.first { $0.matches(name) }
    }

    // MARK: Version de processus

    /// Valeur de `ProcessVersion` rangée par Lightroom pour chaque version de processus (relevé dans
    /// Lightroom Classic 15.6, `kProcessVersionHistoryNames`) ; la 6 est l'actuelle.
    public static let processVersions: [(value: String, version: Int)] = [
        ("5.0", 1), ("5.7", 2), ("6.6", 3), ("6.7", 3), ("10.0", 4), ("11.0", 5), ("15.4", 6),
    ]
    public static let currentProcessVersion = (value: "15.4", version: 6)

    /// Le numéro de la version de processus rangée (« 11.0 » → 5), ou nil si elle est inconnue.
    public static func processVersion(_ value: String) -> Int? {
        processVersions.first { $0.value == value }?.version
    }

    // MARK: Flou d'objectif

    /// Une forme du bokeh du flou d'objectif : `parameter` est son nom dans lens_blur, `fields` les
    /// champs de la table `LensBlur` qu'elle pose. Relevé dans Lightroom Classic 15.6
    /// (`kLensBlurBokehPresetNames`, et la table de `cr_lens_blur_params::ApplyBokehPreset` dans
    /// Camera Raw), recoupé avec les paramètres prédéfinis d'Adobe « Adaptive - Blur Background »
    /// (Circle, Bubble, Geometric, Ring, Oval) ; CatEyeAmount n'est pas touché.
    public struct BokehShape: Equatable {
        public var parameter: String
        public var label: String
        public var fields: [String: Double]
    }

    public static let bokehShapes: [BokehShape] = {
        let neutral: [String: Double] = ["BokehShape": 0, "BokehShapeDetail": 0, "BokehAspect": 0, "BokehRotation": 0,
                                         "SphericalAberration": 0, "CatEyeScale": 100]
        func shape(_ parameter: String, _ label: String, _ changes: [String: Double]) -> BokehShape {
            BokehShape(parameter: parameter, label: label, fields: neutral.merging(changes) { _, new in new })
        }
        return [
            shape("circle", "cercle", [:]),
            shape("soap_bubble", "bulle de savon", ["SphericalAberration": 80]),
            shape("blade", "diaphragme à 5 lames", ["BokehShapeDetail": 1, "BokehRotation": 50]),
            shape("ring", "anneau (objectif catadioptrique)", ["BokehShape": 1, "BokehShapeDetail": 3, "SphericalAberration": 25]),
            shape("anamorphic", "anamorphique (ovale)", ["BokehAspect": -100]),
        ]
    }()

    // MARK: Amélioration

    /// Un traitement que Lightroom calcule lui-même (panneau Amélioration) et qu'aucun réglage ne
    /// pose : `parameter` est son nom dans enhance_photo, `lightroom` celui de
    /// `LrDevelopController.setEnhance`.
    public struct Enhancement: Equatable {
        public var parameter: String
        public var lightroom: String
        public var label: String

        /// Clé des changements que renvoie le module (« Amelioration.denoise »…).
        public var changeKey: String { "Amelioration." + lightroom }
    }

    public static let enhancements: [Enhancement] = [
        Enhancement(parameter: "denoise", lightroom: "denoise", label: "Débruitage IA"),
        Enhancement(parameter: "raw_details", lightroom: "rawDetails", label: "Détails bruts"),
        Enhancement(parameter: "super_resolution", lightroom: "superRes", label: "Super résolution"),
    ]

    /// Intensité du débruitage dans Lightroom (`setEnhance`, `changeDenoiseAmount`), et celle
    /// qu'il propose.
    public static let denoiseAmountRange = 1.0...100.0
    public static let defaultDenoiseAmount = 50.0

    // MARK: Recadrage

    /// Clés du recadrage dans les réglages de Lightroom : calculées par le module à partir du
    /// paramètre `crop`, jamais demandées directement.
    public static let cropKeys = ["CropAngle", "CropLeft", "CropTop", "CropRight", "CropBottom"]
    /// « Contraindre le recadrage » : le module la coche avec Upright, la perspective ou la
    /// distorsion manuelle, et Lightroom resserre le cadre (voir docs/SPEC.md, Recadrage).
    public static let constrainCropKey = "CropConstrainToWarp"

    /// Clés des courbes par points, par canal (RVB, rouge, vert, bleu).
    public static let curveKeys: [(channel: String, key: String, label: String)] = [
        ("rgb", "ToneCurvePV2012", "Courbe par points (RVB)"),
        ("red", "ToneCurvePV2012Red", "Courbe par points (rouge)"),
        ("green", "ToneCurvePV2012Green", "Courbe par points (vert)"),
        ("blue", "ToneCurvePV2012Blue", "Courbe par points (bleu)"),
    ]

    /// Libellés des clés qui ne sont pas des réglages du catalogue : profil, recadrage, courbes,
    /// couleur ponctuelle, masques, retouches de taches, modes automatiques, amélioration et
    /// classement dans la Bibliothèque.
    private static let extraLabels: [String: String] = {
        var labels: [String: String] = [
            profileKey: "Profil",
            "Look": "Profil (Look)",
            "CropAngle": "Recadrage : angle",
            "CropLeft": "Recadrage : bord gauche",
            "CropTop": "Recadrage : bord haut",
            "CropRight": "Recadrage : bord droit",
            "CropBottom": "Recadrage : bord bas",
            "CropConstrainToWarp": "Recadrage : contraindre à l'image (sans coins vides)",
            "PointColors": "Couleur ponctuelle",
            "MaskGroupBasedCorrections": "Masques",
            "RetouchAreas": "Retouches de taches",
            "RedEyeInfo": "Yeux rouges",
            "WhiteBalance": "Balance des blancs (mode)",
            "AutoTone": "Tonalité automatique",
            "Preset": "Paramètre prédéfini",
            "LensBlur": "Flou d'objectif",
            "ProcessVersion": "Version de processus",
            "Amelioration": "Amélioration (débruitage, détails bruts, super résolution)",
            "Suppression": "Suppression des distractions (reflets)",
            "Suppression.reflets": "Reflets supprimés (intensité)",
            "Suppression.poussiere": "Poussière du capteur supprimée",
            "FilterList": "Traitements calculés (débruitage, reflets, poussière…)",
            "AutoGrayscaleMix": "Mélange noir et blanc automatique",
            "LensProfileName": "Profil d'objectif",
            "UprightFourSegments": "Upright : repères",
            "UprightTransform": "Upright : corrections (matrices)",
            "Rotation": "Rotation (orientation)",
            "DepthBasedCorrections": "Flou d'objectif : pinceau d'affinage",
            // Classement dans la Bibliothèque (set_metadata, manage_collections).
            "Bibliotheque": "Bibliothèque (note, drapeau, libellé, textes, mots-clés, collections)",
            "note": "Note",
            "drapeau": "Drapeau",
            "libelle": "Libellé de couleur",
            "titre": "Titre",
            "legende": "Légende",
            "droits": "Droits d'auteur",
            "mots_cles": "Mots-clés",
            "collection": "Collection",
        ]
        for curve in curveKeys { labels[curve.key] = curve.label }
        for enhancement in enhancements { labels[enhancement.changeKey] = enhancement.label }
        return labels
    }()

    /// Libellé français d'une clé renvoyée par le module : réglage du catalogue, profil ou recadrage.
    public static func label(for key: String) -> String? {
        setting(key)?.label ?? extraLabels[key]
    }

    public static var keys: [String] { all.map(\.key) }

    public static func setting(_ key: String) -> DevelopSetting? {
        index[key]
    }

    private static let index: [String: DevelopSetting] =
        Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    /// Groupes dans l'ordre du panneau Développement.
    public static var groups: [String] {
        var seen: [String] = []
        for setting in all where !seen.contains(setting.group) { seen.append(setting.group) }
        return seen
    }

    /// Plages envoyées au module Lightroom pour les clés demandées.
    public static func ranges(for keys: [String]) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for key in keys {
            if let setting = setting(key) { object[key] = setting.range }
        }
        return .object(object)
    }

    /// Libellés français envoyés au module Lightroom, pour sa fenêtre de la liaison.
    public static func labels(for keys: [String]) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for key in keys {
            if let label = label(for: key) { object[key] = .string(label) }
        }
        return .object(object)
    }

    /// Nombre sans décimale inutile : 2 → « 2 », 0.35 → « 0.35 ».
    public static func format(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
