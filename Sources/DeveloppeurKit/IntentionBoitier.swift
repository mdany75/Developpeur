import Foundation

/// L'intention de la prise de vue d'une photo Fujifilm : les réglages choisis sur l'appareil
/// (simulation de film, plage dynamique, tons clairs et foncés, compensation d'exposition, mode),
/// lus par LectureBoitier (Boitier.swift) dans la MakerNote et l'Exif, d'une seule ouverture avec
/// le point de mise au point. view_photo la donne sur l'aperçu entier (« intention_boitier »), avec
/// sa « lecture » : ce que Claude en tire pour la retouche. Rien n'est posé d'office : un RAW n'en
/// reçoit que la simulation, par le profil, en proposition de première passe.
///
/// Tags d'après ExifTool (Image/ExifTool/FujiFilm.pm, TagNames/FujiFilm) ; chaque valeur est
/// facultative, et une valeur hors de ce que l'appareil peut ranger est ignorée (type inattendu).
/// Recoupés le 20 octobre 2026 sur les vrais fichiers d'un X-H2S et d'un X-T20 (MakerNote lue à la
/// main, hors de ce code) : FilmMode, DynamicRangeSetting, DevelopmentDynamicRange,
/// AutoDynamicRange et Saturation en SHORT, ShadowTone et HighlightTone en SLONG (type 9). Restent à
/// relever : un X-T4, une simulation noir et blanc, la priorité à la plage dynamique.
public struct IntentionBoitier: Equatable {
    /// FilmMode (0x1401) : la simulation de film en couleur.
    public var simulation: Int?
    /// Saturation (0x1003) : le réglage Couleur d'une simulation en couleur, ou la simulation
    /// noir et blanc (ACROS, MONOCHROME, Sépia).
    public var saturation: Int?
    /// DynamicRangeSetting (0x1402) : 0 auto, 1 réglée ; 0x100, 0x200, 0x201 sur les anciens boîtiers.
    public var reglagePlage: Int?
    /// DevelopmentDynamicRange (0x1403) : la plage réglée (100, 200, 400).
    public var plageDeveloppement: Int?
    /// AutoDynamicRange (0x140b) : la plage choisie en auto.
    public var plageAuto: Int?
    /// DRangePriority (0x1443) : 0 auto, 1 fixe ; DRangePriorityAuto (0x1444) : 1 faible, 2 forte,
    /// 3 plus ; DRangePriorityFixed (0x1445) : 1 faible, 2 forte.
    public var priorite: Int?
    public var prioriteAuto: Int?
    public var prioriteFixe: Int?
    /// HighlightTone (0x1041) et ShadowTone (0x1040), en crans de l'appareil (cran = −valeur/16,
    /// de −2, plus doux, à +4, plus durs ; demi-crans possibles).
    public var tonsClairs: Double?
    public var tonsFonces: Double?
    /// WhiteBalance (0x1002).
    public var balance: Int?
    /// PictureMode (0x1031) et SceneRecognition (0x1425).
    public var modeImage: Int?
    public var scene: Int?
    /// ExposureCompensation (Exif 0x9204), en IL.
    public var compensation: Double?
    /// ExposureProgram (Exif 0x8822) : 1 manuel, 2 programme, 3 priorité à l'ouverture, 4 à la vitesse.
    public var programme: Int?

    public init(simulation: Int? = nil, saturation: Int? = nil, reglagePlage: Int? = nil, plageDeveloppement: Int? = nil,
                plageAuto: Int? = nil, priorite: Int? = nil, prioriteAuto: Int? = nil, prioriteFixe: Int? = nil,
                tonsClairs: Double? = nil, tonsFonces: Double? = nil, balance: Int? = nil, modeImage: Int? = nil,
                scene: Int? = nil, compensation: Double? = nil, programme: Int? = nil) {
        self.simulation = simulation
        self.saturation = saturation
        self.reglagePlage = reglagePlage
        self.plageDeveloppement = plageDeveloppement
        self.plageAuto = plageAuto
        self.priorite = priorite
        self.prioriteAuto = prioriteAuto
        self.prioriteFixe = prioriteFixe
        self.tonsClairs = tonsClairs
        self.tonsFonces = tonsFonces
        self.balance = balance
        self.modeImage = modeImage
        self.scene = scene
        self.compensation = compensation
        self.programme = programme
    }

    /// D'après l'IFD de la MakerNote et l'IFD Exif ; nil si rien n'est lu.
    init?(note: [Int: LectureBoitier.Tiff.Entree], exif: [Int: LectureBoitier.Tiff.Entree]) {
        func entier(_ tag: Int) -> Int? { Self.entier(note[tag]) }
        self.init(simulation: entier(0x1401), saturation: entier(0x1003), reglagePlage: entier(0x1402),
                  plageDeveloppement: entier(0x1403), plageAuto: entier(0x140b), priorite: entier(0x1443),
                  prioriteAuto: entier(0x1444), prioriteFixe: entier(0x1445),
                  tonsClairs: Self.ton(note[0x1041]), tonsFonces: Self.ton(note[0x1040]),
                  balance: entier(0x1002), modeImage: entier(0x1031), scene: entier(0x1425),
                  compensation: Self.compensation(exif[0x9204]), programme: Self.entier(exif[0x8822]))
        if self == IntentionBoitier() { return nil }
    }

    /// Un réglage rangé en entier (SHORT ou LONG d'ordinaire) ; un texte ou des octets indéfinis
    /// (un type inattendu) ne se lisent pas : leur premier octet ne dirait rien de sûr.
    static func entier(_ entree: LectureBoitier.Tiff.Entree?) -> Int? {
        guard let entree, [1, 3, 4, 6, 8, 9].contains(entree.type) else { return nil }
        return entree.entier.map(Int.init)
    }

    // MARK: Seuils

    /// Compensation à partir de laquelle la photo est voulue plus sombre (ou plus claire) que la
    /// mesure de l'appareil : −2/3 IL et au-delà ; ±1/3 ne dit rien (cran souvent pris pour garder
    /// les hautes lumières). Provisoires, à relever sur les compensations des essais Fujifilm.
    static let seuilSombreVoulue = -0.6
    static let seuilClaireVoulue = 0.6
    /// Ce que l'appareil peut ranger : tons de −2 à +4 crans, par demi-cran ; compensation de ±5 IL
    /// (±10 accepté). Hors de là, la valeur vient d'un type inattendu et n'est pas gardée.
    static let tonsPossibles = -2.0...4.0
    static let compensationPossible = -10.0...10.0
    /// Plage dynamique en % : DR100 à DR800 (hors de là, une valeur qui ne dit rien).
    static let plagePossible = 100...800

    /// Le cran d'un ton (int32s, comme exiftool, quel que soit le type rangé).
    static func ton(_ entree: LectureBoitier.Tiff.Entree?) -> Double? {
        guard let valeur = entree?.signe32 else { return nil }
        let cran = Double(-valeur) / 16
        guard tonsPossibles.contains(cran), (cran * 2).rounded() == cran * 2 else { return nil }
        return cran
    }

    /// La compensation en IL (rationnel signé, comme exiftool, même rangé en RATIONAL).
    static func compensation(_ entree: LectureBoitier.Tiff.Entree?) -> Double? {
        guard let valeur = entree?.rationnel(signe: true), valeur.isFinite, compensationPossible.contains(valeur) else { return nil }
        return valeur
    }

    // MARK: Tables

    /// FilmMode : nom de la simulation et profil de Lightroom (nil : aucun). Profils DCP du
    /// catalogue (DevelopCatalogue.profiles) ; CLASSIC Neg., ETERNA Bleach Bypass et NOSTALGIC Neg.
    /// sont des profils à base de Look, rangés par appareil (relevés dans Lightroom Classic 15.6,
    /// Camera/Fujifilm/Fujifilm X-H2S). Les Studio Portrait des anciens compacts n'en ont pas.
    static let simulations: [Int: (nom: String, profil: String?)] = [
        0x000: ("PROVIA/Standard", "Camera PROVIA/Standard"),
        0x100: ("Studio Portrait", nil),
        0x110: ("Studio Portrait, saturation accrue", nil),
        0x120: ("ASTIA/Soft", "Camera ASTIA/Soft"),
        0x130: ("Studio Portrait, netteté accrue", nil),
        0x200: ("Velvia/Vivid", "Camera Velvia/Vivid"),
        0x300: ("Studio Portrait Ex", nil),
        0x400: ("Velvia/Vivid", "Camera Velvia/Vivid"),
        0x500: ("PRO Neg. Std", "Camera Pro Neg Std"),
        0x501: ("PRO Neg. Hi", "Camera Pro Neg Hi"),
        0x600: ("CLASSIC CHROME", "Camera CLASSIC CHROME"),
        0x700: ("ETERNA/Cinema", "Camera ETERNA/Cinema"),
        0x800: ("CLASSIC Neg.", "Camera CLASSIC Neg"),
        0x900: ("ETERNA Bleach Bypass", "Camera BLEACH BYPASS"),
        0xa00: ("NOSTALGIC Neg.", "Camera NOSTALGIC Neg"),
        0xb00: ("REALA ACE", "Camera REALA ACE"),
    ]

    /// Saturation d'une photo en noir et blanc : la simulation et son profil (Sépia : un Look).
    static let monochromes: [Int: (nom: String, profil: String)] = [
        0x300: ("MONOCHROME", "Camera Monochrome"),
        0x301: ("MONOCHROME, filtre rouge", "Camera Monochrome+R Filter"),
        0x302: ("MONOCHROME, filtre jaune", "Camera Monochrome+Ye Filter"),
        0x303: ("MONOCHROME, filtre vert", "Camera Monochrome+G Filter"),
        0x310: ("Sépia", "Camera Sepia"),
        0x500: ("ACROS", "Camera ACROS"),
        0x501: ("ACROS, filtre rouge", "Camera ACROS+R Filter"),
        0x502: ("ACROS, filtre jaune", "Camera ACROS+Ye Filter"),
        0x503: ("ACROS, filtre vert", "Camera ACROS+G Filter"),
    ]

    /// Saturation d'une simulation en couleur : le réglage Couleur de l'appareil (0x8000 : celui
    /// de la simulation, rien à dire).
    static let couleurs: [Int: Int] = [0x0: 0, 0x80: 1, 0x100: 2, 0xc0: 3, 0xe0: 4, 0x180: -1, 0x400: -2, 0x4c0: -3, 0x4e0: -4]

    static let modes: [Int: String] = [1: "manuel", 2: "programme", 3: "priorité à l'ouverture", 4: "priorité à la vitesse"]
    static let balances: [Int: String] = [0x1: "Auto, priorité au blanc", 0x2: "Auto, priorité à l'ambiance"]
    static let niveauxPrioriteAuto: [Int: String] = [1: "faible", 2: "forte", 3: "plus"]
    static let niveauxPrioriteFixe: [Int: String] = [1: "faible", 2: "forte"]

    // MARK: Valeurs lues

    /// Une simulation noir et blanc se lit dans la saturation, qui n'en range qu'en noir et blanc :
    /// elle l'emporte sur FilmMode (absent en noir et blanc, d'après ExifTool ; à relever).
    var monochrome: (nom: String, profil: String)? { saturation.flatMap { Self.monochromes[$0] } }

    public var noirEtBlanc: Bool { monochrome != nil }

    public var nomSimulation: String? { monochrome?.nom ?? simulation.flatMap { Self.simulations[$0]?.nom } }

    /// Le profil de Lightroom de la simulation, tel que le nomme le catalogue ou le Look.
    public var profilSimulation: String? {
        if let monochrome { return monochrome.profil }
        return simulation.flatMap { Self.simulations[$0]?.profil }
    }

    /// Le réglage Couleur, en couleur seulement.
    public var couleur: Int? { noirEtBlanc ? nil : saturation.flatMap { Self.couleurs[$0] } }

    /// La plage dynamique en %, et si l'appareil l'a choisie (auto).
    public var plageDynamique: (pourcent: Int, auto: Bool)? {
        let lue: (pourcent: Int, auto: Bool)?
        switch reglagePlage {
        case 0: lue = plageAuto.map { ($0, true) }
        case 1: lue = plageDeveloppement.map { ($0, false) }
        case 0x100: lue = (100, false)
        case 0x200: lue = (230, false)
        case 0x201: lue = (400, false)
        default: lue = nil
        }
        guard let lue, Self.plagePossible.contains(lue.pourcent) else { return nil }
        return lue
    }

    /// La priorité à la plage dynamique, retenue seulement si son niveau est lu (désactivée : à
    /// relever).
    public var prioritePlage: (niveau: String, auto: Bool)? {
        if priorite != 0, let niveau = prioriteFixe.flatMap({ Self.niveauxPrioriteFixe[$0] }) { return (niveau, false) }
        if priorite != 1, let niveau = prioriteAuto.flatMap({ Self.niveauxPrioriteAuto[$0] }) { return (niveau, true) }
        return nil
    }

    public var mode: String? { programme.flatMap { Self.modes[$0] } }

    public var nomBalance: String? { balance.flatMap { Self.balances[$0] } }

    /// Scène de nuit : mode choisi (scène de nuit, nuit sur trépied, basse lumière) ou reconnu par
    /// l'appareil (scène de nuit, portrait de nuit).
    public var nuit: Bool {
        (modeImage.map { [0x5, 0x17, 0x18].contains($0) } ?? false) || (scene.map { [0x300, 0x103].contains($0) } ?? false)
    }

    // MARK: Profil de Lightroom

    /// Le profil de Lightroom qui rend la simulation pour cet appareil : le profil DCP du catalogue
    /// (sauf sur un modèle où Lightroom le rend comme Adobe Standard, `missingOn`), ou le Look
    /// installé pour cet appareil ; nil sinon.
    public func profilLightroom(marque: String?, modele: String?, looks: LookProfileLibrary) -> String? {
        guard let nom = profilSimulation else { return nil }
        if let profil = DevelopCatalogue.profile(nom) {
            let appareil = (modele ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            if !appareil.isEmpty, profil.missingOn.contains(where: { $0.uppercased() == appareil }) { return nil }
            return profil.name
        }
        return looks.candidates(named: nom).first { $0.matches(make: marque, model: modele) }?.name
    }

    /// Le profil actuel de la photo est-il ce profil ? Sans tenir compte de la casse (Lightroom
    /// range sa propre orthographe), ni des autres orthographes du catalogue.
    static func memeProfil(_ profil: String, _ actuel: String?) -> Bool {
        guard let actuel else { return false }
        return profil.lowercased() == actuel.lowercased() || DevelopCatalogue.profile(profil)?.matches(actuel) == true
    }

    // MARK: Pour Claude

    /// Ce que view_photo donne : les réglages lus, puis la lecture. `raw` : Lightroom développe un
    /// RAW (sinon un JPEG de l'appareil, déjà rendu) ; `profil` : profilLightroom, pour un RAW ;
    /// `profilActuel` : le profil de la photo.
    public func json(raw: Bool, profil: String?, profilActuel: String?) -> JSONValue {
        var json: [String: JSONValue] = [:]
        if let nom = nomSimulation { json["simulation"] = .string(nom) }
        if raw, let profil { json["profil"] = .string(profil) }
        if let couleur, couleur != 0 { json["couleur"] = .number(Double(couleur)) }
        if let plage = plageDynamique { json["plage_dynamique"] = .string("DR\(plage.pourcent) (\(plage.auto ? "auto" : "réglée"))") }
        if let priorite = prioritePlage { json["priorite_plage_dynamique"] = .string(priorite.auto ? "\(priorite.niveau) (auto)" : priorite.niveau) }
        if let tons = tonsClairs, tons != 0 { json["tons_clairs"] = .number(tons) }
        if let tons = tonsFonces, tons != 0 { json["tons_fonces"] = .number(tons) }
        if let compensation, (compensation * 100).rounded() != 0 { json["compensation"] = .number((compensation * 100).rounded() / 100) }
        if let mode { json["mode"] = .string(mode) }
        if let nomBalance { json["balance"] = .string(nomBalance) }
        if nuit { json["scene"] = "nuit" }
        let lignes = lecture(raw: raw, profil: profil, profilActuel: profilActuel)
        if !lignes.isEmpty { json["lecture"] = .array(lignes.map(JSONValue.string)) }
        return .object(json)
    }

    /// Les consignes tirées de ce que l'appareil dit, seulement celles qui s'appliquent.
    public func lecture(raw: Bool, profil: String?, profilActuel: String?) -> [String] {
        var lignes: [String] = []
        if let compensation, compensation <= Self.seuilSombreVoulue {
            lignes.append("Compensation \(Self.texteIL(compensation)) IL à la prise de vue : photo voulue plus sombre que la mesure de l'appareil (nuit, ambiance, lumières à tenir). Garder sa luminosité d'ensemble : ne pas remonter Exposure2012 vers une moyenne ; éclaircir le sujet ou les ombres par un masque s'il le faut, et le dire.")
        } else if let compensation, compensation >= Self.seuilClaireVoulue {
            lignes.append("Compensation \(Self.texteIL(compensation)) IL à la prise de vue : photo voulue plus claire que la mesure (contre-jour, neige, rendu lumineux) ; ne pas la ramener vers une moyenne.")
        } else if programme == 1, (compensation ?? 0) == 0 {
            lignes.append("Exposition réglée à la main (mode manuel) : sa luminosité est un choix ; avant de la changer, juger l'intention d'après la scène (nuit, contre-jour).")
        }
        if nuit {
            lignes.append("Scène de nuit (mode choisi ou reconnu par l'appareil) : une vraie nuit reste sombre (noirs posés, lumières tenues).")
        }
        if raw {
            if let nom = nomSimulation {
                if let profil {
                    lignes.append(Self.memeProfil(profil, profilActuel)
                        ? "Le profil actuel est la simulation choisie au boîtier (\(nom)) : le garder, sauf autre style demandé."
                        : "Simulation choisie au boîtier : \(nom). En première passe, partir du profil « \(profil) » (apply_settings, profile), sauf autre style demandé ou guide de style contraire ; le dire.")
                } else {
                    lignes.append("Simulation choisie au boîtier : \(nom), sans profil Lightroom pour cet appareil ; s'en approcher par les réglages seulement si l'utilisateur le demande.")
                }
            }
            if let plage = plageDynamique, plage.pourcent >= 200 {
                let ecart = Self.texteIL(log2(Double(plage.pourcent) / 100), signe: false)
                var ligne = "Plage dynamique DR\(plage.pourcent) : hautes lumières protégées à la prise de vue (RAW exposé \(ecart) IL plus bas). Les tenir ; si la photo paraît sous-exposée d'environ \(ecart) IL, c'est cette protection : remonter l'exposition en gardant les hautes lumières (Highlights2012 négatif) ; les ombres relevées seront plus bruitées."
                // Avec une photo voulue sombre, les deux lectures se complètent : rattraper la
                // protection, pas la compensation.
                if let compensation, compensation <= Self.seuilSombreVoulue {
                    ligne += " La compensation de \(Self.texteIL(compensation)) IL, elle, reste voulue : ne rattraper que cette protection."
                }
                lignes.append(ligne)
            }
            let tons = [tonsClairs.flatMap { $0 != 0 ? "tons clairs \(Self.cran($0))" : nil },
                        tonsFonces.flatMap { $0 != 0 ? "tons foncés \(Self.cran($0))" : nil }].compactMap { $0 }
            if !tons.isEmpty {
                lignes.append("Tons choisis au boîtier : \(tons.joined(separator: ", ")) (de −2, plus doux, à +4, plus durs). Lightroom ne les applique pas à un RAW : s'en inspirer pour Highlights2012, Shadows2012 ou la courbe, sans les imposer.")
            }
        } else if nomSimulation != nil || plageDynamique != nil || tonsClairs != nil || tonsFonces != nil {
            let simulation = nomSimulation.map { "la simulation « \($0) »" } ?? "la simulation de film"
            lignes.append("JPEG de l'appareil : \(simulation), la plage dynamique et les tons y sont déjà appliqués ; ne pas les refaire.")
        }
        switch balance {
        case 0x2: lignes.append("Balance du boîtier « Auto, priorité à l'ambiance » : la chaleur des lampes était voulue ; ne pas la neutraliser entièrement.")
        case 0x1: lignes.append("Balance du boîtier « Auto, priorité au blanc » : un blanc neutre était voulu.")
        default: break
        }
        if let priorite = prioritePlage {
            lignes.append("Priorité à la plage dynamique (\(priorite.niveau)) : contraste réduit au boîtier pour garder ombres et lumières ; ne pas le rendre d'office.")
        }
        return lignes
    }

    /// Une valeur en IL arrondie au tiers : « −1 », « −2/3 », « +1 1/3 » (sans signe : « 1 1/3 »).
    public static func texteIL(_ valeur: Double, signe: Bool = true) -> String {
        let tiers = Int((valeur * 3).rounded())
        guard tiers != 0 else { return "0" }
        let entier = abs(tiers) / 3, reste = abs(tiers) % 3
        let corps = entier == 0 ? "\(reste)/3" : (reste == 0 ? "\(entier)" : "\(entier) \(reste)/3")
        return signe ? (tiers < 0 ? "−" : "+") + corps : corps
    }

    /// Un cran de l'appareil, au demi-cran : « +1 », « −0,5 ».
    public static func cran(_ valeur: Double) -> String {
        let demis = Int((valeur * 2).rounded())
        guard demis != 0 else { return "0" }
        let corps = demis % 2 == 0 ? "\(abs(demis) / 2)" : "\(abs(demis) / 2),5"
        return (demis < 0 ? "−" : "+") + corps
    }
}
