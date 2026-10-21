import Foundation

/// Les défauts de la prise de vue (1.3) : la seule liste, que reprennent la leçon de la photo
/// (photo_lesson : ses trois axes et l'enum de ses `defects`) et le carnet de progrès (ses domaines,
/// et les six défauts qu'il compte d'après une mesure). Sans Vision ni SDK : des données, testées
/// telles quelles (PriseDeVueTests). Le module reçoit `vocabulaire` (codes français, libellés,
/// conseils) avec ses commandes : aucune liste n'est écrite dans son code (il peut ranger la copie
/// reçue dans carnet.json, pour la page du carnet).
///
/// Les libellés et les conseils s'adressent à un photographe amateur : une phrase simple, ce qu'il
/// aurait pu faire au moment de déclencher. Un réglage propre à une marque n'y est cité qu'en
/// exemple (« sur un Fujifilm ») : la leçon ne cite un réglage du boîtier que s'il est lu.
public enum PriseDeVue {
    /// Axe d'un point de la leçon de la photo : chacun une fois, dans cet ordre.
    public enum Axe: String, CaseIterable {
        case lumiere, couleur, composition

        /// Code français (module, carnet).
        public var code: String { rawValue }
        /// Clé anglaise (`axis` de photo_lesson).
        public var cle: String {
            switch self {
            case .lumiere: return "light"
            case .couleur: return "color"
            case .composition: return "composition"
            }
        }
        public var nom: String {
            switch self {
            case .lumiere: return "Lumière"
            case .couleur: return "Couleur"
            case .composition: return "Composition"
            }
        }

        public init?(cle: String) {
            guard let axe = Self.allCases.first(where: { $0.cle == cle }) else { return nil }
            self = axe
        }
    }

    /// Domaine du carnet de progrès : la netteté y a le sien (flou, mise au point, bruit), rangée
    /// sous Lumière dans la leçon, qui n'a que trois axes.
    public enum Domaine: String, CaseIterable {
        case lumiere, nettete, couleur, composition

        public var code: String { rawValue }
        public var nom: String {
            switch self {
            case .lumiere: return "Lumière"
            case .nettete: return "Netteté"
            case .couleur: return "Couleur"
            case .composition: return "Composition"
            }
        }
    }

    public struct Defaut: Equatable {
        /// Code français : celui du module et du carnet (`^[a-z_]+$`).
        public let code: String
        /// Clé anglaise : une valeur de l'enum `defects` de photo_lesson.
        public let cle: String
        /// Axe de la leçon.
        public let axe: Axe
        /// Domaine du carnet.
        public let domaine: Domaine
        /// Ce que l'utilisateur lit (carnet, carte de la leçon).
        public let libelle: String
        /// Ce qui l'aurait évité à la prise de vue.
        public let conseil: String
        /// Compté par le carnet d'après une mesure : view_photo sur une photo que Claude n'a pas
        /// encore retouchée ; pour l'horizon, une ligne mesurée (measure_angle ou read_composition)
        /// sur une géométrie intacte (ni CropAngle, ni Upright, ni perspective), même après une
        /// passe de tonalité. Les autres ne viennent que des leçons.
        public let mesure: Bool
    }

    /// Bornes des textes : un libellé tient sur une ligne du carnet, un conseil dans une moitié de
    /// point de la leçon.
    public static let longueurLibelle = 40
    public static let longueurConseil = 140

    /// Les seize défauts, dans l'ordre où le carnet les montre.
    public static let defauts: [Defaut] = [
        Defaut(code: "horizon_penche", cle: "tilted_horizon", axe: .composition, domaine: .composition,
               libelle: "Horizon ou ligne penchée",
               conseil: "Afficher le niveau électronique ou la grille du viseur, et caler l'horizon dessus avant de déclencher.",
               mesure: true),
        Defaut(code: "verticales_fuyantes", cle: "converging_verticals", axe: .composition, domaine: .composition,
               libelle: "Verticales qui fuient",
               conseil: "Reculer et garder l'appareil droit, sans le lever vers le bâtiment ; une focale plus courte aide.",
               mesure: false),
        Defaut(code: "cadrage_large", cle: "loose_framing", axe: .composition, domaine: .composition,
               libelle: "Cadrage trop large",
               conseil: "Avancer d'un pas ou zoomer : le sujet remplit le cadre, et ce qui ne le sert pas reste dehors.",
               mesure: false),
        Defaut(code: "sujet_centre", cle: "centered_subject", axe: .composition, domaine: .composition,
               libelle: "Sujet au centre sans raison",
               conseil: "Poser le sujet sur une ligne des tiers de la grille, avec de l'espace du côté où il regarde ou avance.",
               mesure: false),
        Defaut(code: "bords_encombres", cle: "cluttered_edges", axe: .composition, domaine: .composition,
               libelle: "Bords encombrés",
               conseil: "Faire le tour des bords du viseur avant de déclencher ; un pas de côté retire ce qui dépasse.",
               mesure: false),
        Defaut(code: "sous_exposition", cle: "underexposed", axe: .lumiere, domaine: .lumiere,
               libelle: "Photo sous-exposée",
               conseil: "Monter la compensation d'exposition (+1/3 à +1 IL) en suivant l'histogramme, sans brûler les hautes lumières.",
               mesure: true),
        Defaut(code: "surexposition", cle: "overexposed", axe: .lumiere, domaine: .lumiere,
               libelle: "Photo surexposée",
               conseil: "Baisser la compensation d'exposition (−1/3 à −1 IL) : rien ne doit coller au bord droit de l'histogramme.",
               mesure: false),
        Defaut(code: "ciel_brule", cle: "blown_highlights", axe: .lumiere, domaine: .lumiere,
               libelle: "Ciel ou haut de l'image brûlé",
               conseil: "Exposer pour le ciel (compensation négative, alerte de surexposition du viseur) ; sur un Fujifilm, DR200 ou DR400 aide.",
               mesure: true),
        Defaut(code: "ombres_bouchees", cle: "crushed_shadows", axe: .lumiere, domaine: .lumiere,
               libelle: "Ombres bouchées",
               conseil: "Chercher une lumière moins dure (ombre douce, ciel voilé, autre heure), ou déboucher le sujet par un réflecteur.",
               mesure: false),
        Defaut(code: "contraste_plat", cle: "flat_light", axe: .lumiere, domaine: .lumiere,
               libelle: "Lumière plate ou voilée",
               conseil: "Chercher une lumière qui modèle : tôt le matin ou en fin de journée, de côté plutôt que de face ; un pare-soleil.",
               mesure: false),
        Defaut(code: "bruit", cle: "noise", axe: .lumiere, domaine: .nettete,
               libelle: "Bruit fort (ISO élevé)",
               conseil: "Garder l'ISO plus bas : un appui ou la stabilisation pour une vitesse plus lente, une ouverture plus grande.",
               mesure: true),
        Defaut(code: "flou", cle: "blur", axe: .lumiere, domaine: .nettete,
               libelle: "Photo floue ou bougée",
               conseil: "Une vitesse d'au moins 1/(2 × focale), la stabilisation et l'appareil tenu ferme ; plus vite pour un sujet qui bouge.",
               mesure: true),
        Defaut(code: "mise_au_point", cle: "missed_focus", axe: .lumiere, domaine: .nettete,
               libelle: "Mise au point à côté",
               conseil: "Un seul collimateur, posé sur le sujet (les yeux d'un portrait), et l'AF continu (AF-C) s'il bouge.",
               mesure: true),
        Defaut(code: "dominante", cle: "color_cast", axe: .couleur, domaine: .couleur,
               libelle: "Dominante de couleur",
               conseil: "Régler la balance des blancs selon la lumière, ou la mesurer sur un gris ; en RAW, elle se rattrape sans perte.",
               mesure: false),
        Defaut(code: "eclairage_mixte", cle: "mixed_light", axe: .couleur, domaine: .couleur,
               libelle: "Éclairage mixte",
               conseil: "Éviter de mêler lumières chaudes et froides sur le sujet : éteindre une lampe, ou le placer face à une seule source.",
               mesure: false),
        Defaut(code: "couleurs_ternes", cle: "dull_colors", axe: .couleur, domaine: .couleur,
               libelle: "Couleurs ternes",
               conseil: "Chercher la lumière qui fait vivre les couleurs (soleil de côté, après la pluie), et un rendu plus vif au boîtier.",
               mesure: false),
    ]

    /// Le défaut d'un code français, ou nil.
    public static func defaut(code: String) -> Defaut? { defauts.first { $0.code == code } }

    /// Le défaut d'une clé anglaise (photo_lesson), ou nil.
    public static func defaut(cle: String) -> Defaut? { defauts.first { $0.cle == cle } }

    /// Les clés anglaises d'un axe, dans l'ordre de la liste.
    public static func cles(axe: Axe) -> [String] { defauts.filter { $0.axe == axe }.map(\.cle) }

    /// Les défauts que le carnet compte d'après une mesure.
    public static var mesures: [Defaut] { defauts.filter(\.mesure) }

    /// Le vocabulaire envoyé au module (commandes du carnet et de la leçon) : un tableau, dans
    /// l'ordre de la liste, de { code, cle, axe, domaine, libelle, conseil, mesure }, codes français.
    public static var vocabulaire: JSONValue {
        .array(defauts.map { defaut in
            [
                "code": .string(defaut.code),
                "cle": .string(defaut.cle),
                "axe": .string(defaut.axe.code),
                "domaine": .string(defaut.domaine.code),
                "libelle": .string(defaut.libelle),
                "conseil": .string(defaut.conseil),
                "mesure": .bool(defaut.mesure),
            ]
        })
    }
}
