import CoreGraphics
import Foundation
import Vision

/// Le genre d'une photo (correctif 1.3.8, demandé par Dany le 26 octobre 2026 : « un graphique par
/// style de photo, par catégorie : sport, paysage, portrait, famille, macro… ») : lu par
/// `--analyser` sur la vignette, en même temps que les défauts de la prise de vue, et compté par
/// `--graphiques` (le graphique « Genres de photos » de la fenêtre Suivi). Seule liste des genres et
/// de leurs règles ; le module ne connaît aucun genre (il range le code que rend le connecteur).
///
/// Ce que Vision dit d'une image : ses étiquettes (VNClassifyImageRequest, 1 303 étiquettes en
/// anglais, hiérarchiques : « sport » accompagne « soccer »), les visages (VisionReport, déjà mesurés
/// pour les yeux), les personnes (VNDetectHumanRectanglesRequest) et les chiens et chats
/// (VNRecognizeAnimalsRequest). Vision ne sait ni qui sont les personnes ni si c'est la famille :
/// « Famille et groupes », ce sont deux personnes ou plus de taille comparable. Le genre est une
/// tendance, pas un classement sûr : les seuils (provisoires) sont relevés le 26 octobre 2026 sur les
/// vignettes de 60 photos de Dany (portraits, groupes, sport, paysages, ville, avions, un chien, une
/// tortue), en lecture seule : des 53 assez grandes pour --analyser (900 px au moins), 52 sont
/// rangées comme à l'œil (le château Frontenac la nuit reste un paysage : « castle » à 0,25) ; la
/// nourriture, le macro, les fêtes et la nuit n'y étaient pas, leurs seuils sont à éprouver.
public enum Genre {
    /// La version de ces règles : le module la range dans `analyse.regles_genre`, et une réponse de
    /// règles plus récentes fait refaire le genre seul (les défauts gardés : ils disent la prise de
    /// vue, qu'une retouche faite depuis cacherait).
    public static let regles = 1

    /// Les genres, dans l'ordre de leurs règles (le premier qui convient l'emporte) puis du graphique
    /// à égalité : code et libellé. « Autre » en dernier.
    public static let liste: [(code: String, libelle: String)] = [
        ("sport", "Sport"),
        ("evenement", "Fêtes et événements"),
        ("famille", "Famille et groupes"),
        ("portrait", "Portrait"),
        ("macro", "Macro et gros plans"),
        ("animaux", "Animaux"),
        ("nourriture", "Nourriture"),
        ("vehicules", "Véhicules"),
        ("ville", "Ville et architecture"),
        ("paysage", "Paysage"),
        ("autre", "Autre"),
    ]
    public static var codes: [String] { liste.map(\.code) }
    public static func libelle(_ code: String) -> String { liste.first { $0.code == code }?.libelle ?? code }

    // MARK: Les étiquettes de Vision qui comptent pour chaque genre

    static let sport: Set<String> = ["sport", "ballgames", "athletics", "winter_sport", "watersport", "motorsport", "martial_arts",
                                     "skydiving", "parachute", "equestrian", "cycling", "gymnastics", "racquet"]
    static let evenement: Set<String> = ["celebration", "wedding", "wedding_dress", "wedding_cake", "bride", "groom", "bridesmaid",
                                         "birthday_cake", "graduation", "ceremony", "christmas_tree", "christmas_decoration", "fireworks",
                                         "parade", "concert", "carnival", "balloon", "santa_claus", "easter_egg", "jack_o_lantern",
                                         "dragon_parade", "circus"]
    static let animaux: Set<String> = ["animal", "mammal", "bird", "canine", "feline", "dog", "cat", "horse", "reptile", "fish",
                                       "ungulates", "rodent", "marsupial", "cetacean", "raptor", "poultry"]
    static let insectes: Set<String> = ["insect", "arthropods", "butterfly", "bee", "ladybug", "spider", "dragonfly", "moth", "ant",
                                        "caterpillar", "snail", "gastropod", "arachnid", "centipede", "millipede", "scarab", "worm"]
    static let nourriture: Set<String> = ["food", "dessert", "baked_goods", "fruit", "vegetable", "meat", "seafood", "salad",
                                          "sandwich", "pizza", "pasta", "soup", "cake", "drink", "cocktail"]
    static let fleurs: Set<String> = ["flower", "blossom", "flower_arrangement", "bouquet", "rose", "tulip", "orchid", "daisy",
                                      "sunflower", "lily", "dahlia", "petunia", "begonia", "carnation", "chrysanthemum", "daffodil",
                                      "marigold", "poinsettia", "snapdragon", "dandelion", "cornflower", "mushroom"]
    static let vehicules: Set<String> = ["vehicle", "aircraft", "airplane", "helicopter", "automobile", "car", "motorcycle", "train",
                                         "train_real", "boat", "watercraft", "atv", "truck", "bus", "sailboat", "speedboat", "yacht"]
    static let ville: Set<String> = ["building", "cityscape", "skyscraper", "castle", "tower", "bridge", "monument", "street", "alley",
                                     "arch", "dome", "belltower", "clock_tower", "lighthouse", "ruins", "house_single", "apartment",
                                     "storefront", "statue", "pyramid", "obelisk", "fountain", "windmill"]
    static let nature: Set<String> = ["sky", "blue_sky", "cloudy", "mountain", "hill", "beach", "shore", "ocean", "lake", "river",
                                      "water_body", "waterfall", "forest", "tree", "foliage", "desert", "sand", "sand_dune", "canyon",
                                      "cliff", "rocks", "snow", "glacier", "sunset_sunrise", "night_sky", "aurora", "island", "wetland",
                                      "land", "grass", "plant", "creek", "volcano", "iceberg"]
    /// La scène autour d'une fleur : la nature sans la hiérarchie des plantes (Vision donne toujours
    /// « plant », et souvent « foliage », à la confiance de la fleur : relevé de la relecture du
    /// 26 octobre 2026 sur les fleurs de /Library/User Pictures, rose et tournesol à 0,94 et 0,95).
    static let sceneAutourDUneFleur = nature.subtracting(["plant", "foliage"])

    // MARK: Les seuils (provisoires : relevé du 26 octobre 2026)

    /// Une étiquette de sport, de fête, d'animal ou de véhicule l'emporte à cette confiance (le sport
    /// plus bas : un terrain de soccer le soir, joueurs au loin, ne donnait que 0,4 à 0,52 ; aucune
    /// autre des 60 vignettes n'avait d'étiquette de sport au-dessus de 0,2).
    static let seuilSport = 0.4, seuilEvenement = 0.5, seuilAnimal = 0.5, seuilVehicule = 0.6
    /// Un véhicule l'emporte seulement s'il n'est pas loin derrière la scène (un voilier sur un lac,
    /// un pont : un paysage ou la ville).
    static let margeVehicule = 0.15
    /// Un insecte (presque toujours de près) à cette confiance : macro.
    static let seuilInsecte = 0.4
    /// La nourriture (seulement si elle dépasse la fleur : le pissenlit, « dandelion », donne aussi
    /// « food » à la même confiance), une fleur de près (sans grande scène autour).
    static let seuilNourriture = 0.6, seuilFleur = 0.6, natureFleurMax = 0.5
    /// La ville : une étiquette de bâtiment forte, ou faible mais pas moins que la nature.
    static let seuilVille = 0.5, villeFaible = 0.3
    /// Le paysage : une étiquette de nature à cette confiance.
    static let seuilPaysage = 0.4
    /// Un visage compte à partir de cette hauteur (part de la hauteur de l'image), une personne à
    /// partir de cette surface (part de l'image).
    static let visageMin = 0.05, corpsMin = 0.04
    /// Deux personnes « comparables » (Famille et groupes) : le second visage d'au moins la moitié du
    /// premier, ou le second corps d'au moins 40 % du premier.
    static let secondVisage = 0.5, secondCorps = 0.4
    /// Un portrait : un visage d'au moins 8 % de la hauteur, ou une personne d'au moins 10 % de
    /// l'image (en pied).
    static let visagePortrait = 0.08, corpsPortrait = 0.10
    /// Un chien ou un chat vu par VNRecognizeAnimalsRequest compte à cette confiance et cette surface.
    static let animalVuConfiance = 0.5, animalVuSurface = 0.02

    /// Ce que Vision a dit d'une image, et l'objectif : ce que `classer` lit.
    public struct Indices: Equatable {
        /// Les étiquettes de VNClassifyImageRequest et leur confiance (0 à 1).
        public var etiquettes: [String: Double] = [:]
        /// La hauteur de chaque visage, en part de la hauteur de l'image, de la plus grande à la plus
        /// petite.
        public var visages: [Double] = []
        /// La surface de chaque personne, en part de l'image, de la plus grande à la plus petite.
        public var corps: [Double] = []
        /// Chaque chien ou chat vu : sa confiance et sa surface (part de l'image).
        public var animauxVus: [Animal] = []
        /// L'objectif de la prise de vue est un macro (son nom le dit : « XF80mmF2.8 R LM OIS WR Macro »).
        public var objectifMacro = false

        public struct Animal: Equatable {
            public var confiance: Double
            public var surface: Double
            public init(confiance: Double, surface: Double) { self.confiance = confiance; self.surface = surface }
        }

        public init(etiquettes: [String: Double] = [:], visages: [Double] = [], corps: [Double] = [], animauxVus: [Animal] = [],
                    objectifMacro: Bool = false) {
            self.etiquettes = etiquettes
            self.visages = visages.sorted(by: >)
            self.corps = corps.sorted(by: >)
            self.animauxVus = animauxVus
            self.objectifMacro = objectifMacro
        }

        func score(_ ensemble: Set<String>) -> Double { ensemble.compactMap { etiquettes[$0] }.max() ?? 0 }
    }

    /// Un objectif macro, d'après son nom (sans tenir compte de la casse).
    public static func estMacro(_ objectif: String?) -> Bool {
        objectif?.range(of: "macro", options: .caseInsensitive) != nil
    }

    /// Le genre d'une image (pur) : la première règle qui convient, dans l'ordre de `liste`.
    /// 1. sport, 2. fêtes et événements : leurs étiquettes ;
    /// 3. famille et groupes : deux personnes comparables ou plus (visages ou corps) ;
    /// 4. portrait : un grand visage ou une personne en pied ;
    /// 5. macro : un insecte, ou un objectif macro sans personne ;
    /// 6. animaux : leurs étiquettes, ou un chien ou un chat vu ;
    /// 7. nourriture (plus sûre que la fleur) ; puis macro encore pour une fleur de près (la scène
    ///    autour sans « plant » ni « foliage », que Vision donne avec toute fleur) ;
    /// 8. véhicules : leur étiquette, pas loin derrière la scène ;
    /// 9. ville et architecture ; 10. paysage ; sinon autre.
    public static func classer(_ i: Indices) -> String {
        if i.score(sport) >= seuilSport { return "sport" }
        if i.score(evenement) >= seuilEvenement { return "evenement" }
        let visages = i.visages.filter { $0 >= visageMin }
        let corps = i.corps.filter { $0 >= corpsMin }
        let deux = (visages.count >= 2 && visages[1] >= secondVisage * visages[0]) || (corps.count >= 2 && corps[1] >= secondCorps * corps[0])
        if deux { return "famille" }
        if (i.visages.first ?? 0) >= visagePortrait || (i.corps.first ?? 0) >= corpsPortrait { return "portrait" }
        if i.score(insectes) >= seuilInsecte { return "macro" }
        let sansPersonne = visages.isEmpty && corps.isEmpty
        if i.objectifMacro && sansPersonne { return "macro" }
        if i.score(animaux) >= seuilAnimal || i.animauxVus.contains(where: { $0.confiance >= animalVuConfiance && $0.surface >= animalVuSurface }) {
            return "animaux"
        }
        let scoreFleurs = i.score(fleurs)
        if i.score(nourriture) >= seuilNourriture && i.score(nourriture) > scoreFleurs { return "nourriture" }
        let scoreNature = i.score(nature), scoreVille = i.score(ville)
        if scoreFleurs >= seuilFleur && i.score(sceneAutourDUneFleur) < natureFleurMax { return "macro" }
        let scoreVehicule = i.score(vehicules)
        if scoreVehicule >= seuilVehicule && scoreVehicule >= max(scoreNature, scoreVille) - margeVehicule { return "vehicules" }
        if scoreVille >= seuilVille || (scoreVille >= villeFaible && scoreVille >= scoreNature) { return "ville" }
        if scoreNature >= seuilPaysage { return "paysage" }
        return "autre"
    }

    /// Les étiquettes les plus sûres (pour les mesures de --analyser : le journal et les relevés).
    static func principales(_ etiquettes: [String: Double], nombre: Int = 3) -> [String] {
        etiquettes.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(nombre).map(\.key)
    }

    /// Les visages qui comptent pour le genre : ceux que Composition juge plausibles (un visage à
    /// l'envers, comme le devant d'une voiture de 53709912 au roulis −π, n'est pas une personne).
    public static func visages(_ rapport: VisionReport?) -> [CGRect] {
        (rapport?.faces ?? []).filter(Composition.visagePlausible).map(\.box)
    }

    /// Ce que Vision dit de `image` (la vignette à `Detail.side`), avec les visages déjà mesurés
    /// (`Genre.visages`, repère en haut à gauche) et l'objectif.
    public static func lire(_ image: CGImage, visages: [CGRect], objectif: String?) -> Indices {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let classe = VNClassifyImageRequest()
        let humains = VNDetectHumanRectanglesRequest()
        humains.upperBodyOnly = false
        let betes = VNRecognizeAnimalsRequest()
        try? handler.perform([classe, humains, betes])
        var etiquettes: [String: Double] = [:]
        for observation in classe.results ?? [] where observation.confidence >= 0.05 {
            etiquettes[observation.identifier] = Double(observation.confidence)
        }
        let corps = (humains.results ?? []).map { Double($0.boundingBox.width * $0.boundingBox.height) }
        let vus = (betes.results ?? []).map { o in
            Indices.Animal(confiance: Double(o.labels.first?.confidence ?? 0), surface: Double(o.boundingBox.width * o.boundingBox.height))
        }
        return Indices(etiquettes: etiquettes, visages: visages.map { Double($0.height) }, corps: corps, animauxVus: vus,
                       objectifMacro: estMacro(objectif))
    }
}
