import ColorSync
import CoreGraphics
import Foundation

/// L'écran principal du Mac et son profil de couleur (« écran nommé », 1.2). Claude mesure la photo
/// par ses chiffres (view_photo), sans passer par l'écran ; l'utilisateur la juge sur le sien : le
/// connecteur dit quel est cet écran et si son profil vient d'une sonde d'étalonnage. Lu par
/// CoreGraphics et ColorSync, sans AppKit et sans aucune permission (environ 44 ms, relevé le
/// 20 octobre 2026). Le module ne le lit pas : macOS seul connaît l'écran, et la fenêtre Claude le
/// demande au connecteur (`mcp-developpeur --ecran`, une ligne JSON).
///
/// Constaté le 20 octobre 2026 (Odyssey G85SD en HDMI, seul écran) :
/// - ColorSyncProfileCopyHeader rend les signatures de l'en-tête à l'envers (« lppa » pour
///   « appl ») : l'en-tête se lit dans les octets du profil ICC, en gros-boutiste ;
/// - le profil d'usine d'un écran, tiré de son EDID, est rangé dans
///   /Library/ColorSync/Profiles/Displays/ (créateur « appl », sans balise vcgt) et refait par
///   macOS à chaque branchement : la date de son en-tête est celle du branchement, jamais dite ;
/// - FactoryProfiles (ColorSyncDeviceCopyDeviceInfo) : un dictionnaire de dictionnaires portant
///   chacun DeviceProfileURL, plus DeviceDefaultProfileID, un texte ; un mode peut pointer un profil
///   du système (« HDMI SD » : /System/Library/CoreServices/Resources/Profiles/SD 170M-A.icc) ;
/// - sRGB Profile.icc du système porte une balise meas : elle n'est pas l'indice d'une sonde.
///
/// Six classes (Etalonnage). `mesure` ne vaut vrai que pour une sonde, faux pour un profil d'usine,
/// standard ou fait à l'œil, et reste inconnu (nil) pour un profil personnalisé sans trace d'une
/// sonde : dans le doute, « étalonné ? » plutôt qu'« étalonné ». Aucun vrai profil de sonde n'a
/// encore été relevé (à constater) : l'indice est la balise vcgt avec un créateur autre qu'Apple,
/// ou le nom d'un logiciel de sonde dans le profil.
public enum Ecran {
    /// La classe du profil actif d'un écran.
    public enum Etalonnage: String, CaseIterable {
        case usine, standard, oeil, sonde, personnalise, inconnu

        /// Mesuré par une sonde : vrai, faux, ou inconnu (nil).
        public var mesure: Bool? {
            switch self {
            case .sonde: return true
            case .usine, .standard, .oeil: return false
            case .personnalise, .inconnu: return nil
            }
        }
    }

    /// D'où vient le profil actif, d'après ColorSync : un profil d'usine de l'écran, un profil
    /// choisi par l'utilisateur, ou on ne sait pas.
    public enum Origine: Equatable {
        case usine, personnalise, inconnue
    }

    /// Une date d'en-tête ICC (jour près).
    public struct Jour: Equatable {
        public var annee: Int
        public var mois: Int
        public var jour: Int

        public init(annee: Int, mois: Int, jour: Int) {
            self.annee = annee
            self.mois = mois
            self.jour = jour
        }
    }

    /// Le profil ICC actif : son nom (desc), son fichier, les signatures de l'en-tête (créateur,
    /// CMM), sa date, ses balises et le logiciel de sonde qu'il nomme.
    public struct Profil: Equatable {
        public var nom: String
        public var chemin: String?
        public var createur: String
        public var cmm: String
        public var date: Jour?
        public var tags: Set<String>
        public var logiciel: String?

        public init(nom: String, chemin: String? = nil, createur: String, cmm: String = "", date: Jour? = nil,
                    tags: Set<String> = [], logiciel: String? = nil) {
            self.nom = nom
            self.chemin = chemin
            self.createur = createur
            self.cmm = cmm
            self.date = date
            self.tags = tags
            self.logiciel = logiciel
        }
    }

    /// Un écran actif (les copies miroir sont écartées).
    public struct Affichage: Equatable {
        public var id: UInt32
        public var nom: String
        public var principal: Bool
        public var integre: Bool
        public var apple: Bool
        public var gamutLarge: Bool
        public var profil: Profil?
        public var etalonnage: Etalonnage

        public init(id: UInt32, nom: String, principal: Bool, integre: Bool = false, apple: Bool = false,
                    gamutLarge: Bool = false, profil: Profil?, etalonnage: Etalonnage) {
            self.id = id
            self.nom = nom
            self.principal = principal
            self.integre = integre
            self.apple = apple
            self.gamutLarge = gamutLarge
            self.profil = profil
            self.etalonnage = etalonnage
        }
    }

    /// L'écran principal (celui de la barre des menus) et les autres.
    public struct Etat: Equatable {
        public var principal: Affichage
        public var autres: [Affichage]

        public init(principal: Affichage, autres: [Affichage] = []) {
            self.principal = principal
            self.autres = autres
        }
    }

    // MARK: - Lecture

    /// Clés du dictionnaire d'un appareil (ColorSyncDeviceCopyDeviceInfo).
    static let cleDescription = texte(kColorSyncDeviceDescription, repli: "DeviceDescription")
    static let cleUsine = texte(kColorSyncFactoryProfiles, repli: "FactoryProfiles")
    static let clePersonnalises = texte(kColorSyncCustomProfiles, repli: "CustomProfiles")
    static let cleURL = texte(kColorSyncDeviceProfileURL, repli: "DeviceProfileURL")

    /// Les profils d'usine que ColorSync tire de l'EDID et refait au branchement (constaté).
    static let dossierUsine = "/Library/ColorSync/Profiles/Displays/"

    /// Le fabricant Apple, dans CGDisplayVendorNumber.
    static let fabricantApple: UInt32 = 0x610

    private static func texte(_ cle: Unmanaged<CFString>?, repli: String) -> String {
        guard let cle else { return repli }
        return cle.takeUnretainedValue() as String
    }

    /// Les écrans actifs, l'écran principal d'abord ; nil s'il n'y en a aucun (session sans écran).
    public static func lire() -> Etat? {
        var nombre: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &nombre) == .success, nombre > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(nombre))
        guard CGGetActiveDisplayList(nombre, &ids, &nombre) == .success else { return nil }
        let actifs = ids.prefix(Int(nombre)).filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
        let principalID = CGMainDisplayID()
        guard let principal = actifs.first(where: { $0 == principalID }) ?? actifs.first else { return nil }
        return Etat(principal: affichage(principal, principal: true),
                    autres: actifs.filter { $0 != principal }.map { affichage($0, principal: false) })
    }

    /// Un écran : son nom (celui que ColorSync lui donne), son profil actif et sa classe.
    static func affichage(_ id: CGDirectDisplayID, principal: Bool) -> Affichage {
        var appareil: [String: Any]?
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let classe = kColorSyncDisplayDeviceClass?.takeUnretainedValue() {
            appareil = ColorSyncDeviceCopyDeviceInfo(classe, uuid)?.takeRetainedValue() as? [String: Any]
        }
        let integre = CGDisplayIsBuiltin(id) != 0
        let espace = CGDisplayCopyColorSpace(id)
        var url: URL?
        var icc: Data?
        if let actif = ColorSyncProfileCreateWithDisplayID(id)?.takeRetainedValue() {
            url = ColorSyncProfileGetURL(actif, nil)?.takeUnretainedValue() as URL?
            icc = ColorSyncProfileCopyData(actif, nil)?.takeRetainedValue() as Data?
        }
        if icc == nil {
            icc = espace.copyICCData() as Data?
        }
        let lu = icc.flatMap { profil(icc: $0, url: url) }
        var nom = (appareil?[cleDescription] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if nom.isEmpty {
            nom = integre ? "Écran intégré" : "Écran"
        }
        return Affichage(id: id, nom: nom, principal: principal, integre: integre,
                         apple: CGDisplayVendorNumber(id) == fabricantApple, gamutLarge: espace.isWideGamutRGB,
                         profil: lu, etalonnage: classer(lu, origine: origine(url: url, appareil: appareil)))
    }

    /// Le profil d'un écran, lu dans ses octets ICC ; nil s'il n'est pas un profil ICC lisible.
    /// L'en-tête se lit dans les octets, en gros-boutiste, jamais par ColorSyncProfileCopyHeader,
    /// qui rend les signatures à l'envers (constaté : « lppa » pour « appl ») : CMM aux octets 4 à
    /// 7, date aux octets 24 à 29 (année, mois, jour), « acsp » aux octets 36 à 39, créateur aux
    /// octets 80 à 83.
    public static func profil(icc: Data, url: URL?) -> Profil? {
        let octets = [UInt8](icc)
        guard octets.count >= 132, signature(octets, 36) == "acsp",
              let lu = ColorSyncProfileCreate(icc as CFData, nil)?.takeRetainedValue() else { return nil }
        let tags = (ColorSyncProfileCopyTagSignatures(lu)?.takeRetainedValue() as? [String]) ?? []
        var nom = (ColorSyncProfileCopyDescriptionString(lu)?.takeRetainedValue() as String?) ?? ""
        if nom.isEmpty {
            nom = url?.deletingPathExtension().lastPathComponent ?? "sans nom"
        }
        return Profil(nom: nom, chemin: url.map { $0.standardizedFileURL.path }, createur: signature(octets, 80),
                      cmm: signature(octets, 4), date: jour(octets), tags: Set(tags), logiciel: logicielDeSonde(icc))
    }

    /// Une signature de quatre lettres de l'en-tête, sans ses espaces ni ses octets nuls.
    static func signature(_ octets: [UInt8], _ debut: Int) -> String {
        guard octets.count >= debut + 4 else { return "" }
        let lettres = octets[debut..<debut + 4].filter { $0 != 0 }
        return (String(bytes: lettres, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// La date de l'en-tête (octets 24, 26 et 28, gros-boutiste), si elle est plausible.
    static func jour(_ octets: [UInt8]) -> Jour? {
        guard octets.count >= 30 else { return nil }
        func mot(_ i: Int) -> Int { Int(octets[i]) << 8 | Int(octets[i + 1]) }
        let date = Jour(annee: mot(24), mois: mot(26), jour: mot(28))
        guard date.annee >= 1900, (1...12).contains(date.mois), (1...31).contains(date.jour) else { return nil }
        return date
    }

    /// Les logiciels de sonde, par le texte qu'ils laissent dans un profil (desc, cprt, meta…), dans
    /// l'ordre où les chercher : « Created with DisplayCAL … and ArgyllCMS » est de DisplayCAL.
    static let logicielsDeSonde: [(cle: String, nom: String)] = [
        ("displaycal", "DisplayCAL"),
        ("argyll", "ArgyllCMS"),
        ("i1profiler", "i1Profiler"),
        ("i1 profiler", "i1Profiler"),
        ("calibrite", "Calibrite"),
        ("x-rite", "X-Rite"),
        ("xrite", "X-Rite"),
        ("colormunki", "ColorMunki"),
        ("datacolor", "Datacolor Spyder"),
        ("spyder", "Datacolor Spyder"),
        ("basiccolor", "basICColor"),
        ("colornavigator", "ColorNavigator"),
        ("palette master", "Palette Master"),
        ("calibration studio", "Calibration Studio"),
        ("calman", "Calman"),
    ]

    /// Le logiciel de sonde que nomme un profil. Les octets nuls retirés ramènent à l'ASCII les
    /// textes UTF-16 gros-boutistes des balises mluc et dict ; la balise meas n'est pas un indice
    /// (sRGB Profile.icc du système la porte, constaté).
    static func logicielDeSonde(_ icc: Data) -> String? {
        let octets = icc.filter { $0 != 0 }
        guard let texte = String(bytes: octets, encoding: .isoLatin1)?.lowercased() else { return nil }
        return logicielsDeSonde.first { texte.contains($0.cle) }?.nom
    }

    /// D'où vient le profil actif : `.usine` s'il est l'un des profils d'usine de l'écran
    /// (FactoryProfiles), ou rangé avec les profils que ColorSync tire de l'EDID ; `.personnalise`
    /// s'il est l'un des profils choisis pour l'écran (CustomProfiles : des URL, ou NSNull) ;
    /// `.inconnue` sinon.
    public static func origine(url: URL?, appareil: [String: Any]?) -> Origine {
        guard let url, url.isFileURL else { return .inconnue }
        let chemin = url.standardizedFileURL.path
        if chemins(appareil?[cleUsine]).contains(chemin) || chemin.hasPrefix(dossierUsine) {
            return .usine
        }
        if chemins(appareil?[clePersonnalises]).contains(chemin) {
            return .personnalise
        }
        return .inconnue
    }

    /// Les chemins des profils d'un dictionnaire de ColorSync : chaque valeur est une URL, ou un
    /// dictionnaire portant DeviceProfileURL ; les textes (DeviceDefaultProfileID) et NSNull sont
    /// sautés.
    static func chemins(_ valeur: Any?) -> Set<String> {
        guard let dictionnaire = valeur as? [String: Any] else { return [] }
        var chemins = Set<String>()
        for (_, element) in dictionnaire {
            let url = (element as? URL) ?? ((element as? [String: Any])?[cleURL] as? URL)
            if let url, url.isFileURL {
                chemins.insert(url.standardizedFileURL.path)
            }
        }
        return chemins
    }

    /// La classe d'un profil, dans cet ordre : un profil d'usine n'est jamais « mesuré » ; un profil
    /// du système est standard ; un logiciel de sonde nommé, ou la balise vcgt (courbes de la carte
    /// graphique) d'un créateur autre qu'Apple, fait une sonde ; un profil d'Apple avec vcgt est
    /// celui de l'assistant d'étalonnage (fait à l'œil) ; le reste est personnalisé.
    public static func classer(_ profil: Profil?, origine: Origine) -> Etalonnage {
        if origine == .usine { return .usine }
        guard let profil else { return .inconnu }
        if let chemin = profil.chemin, chemin.hasPrefix("/System/") { return .standard }
        if profil.logiciel != nil { return .sonde }
        if profil.createur == "appl" { return profil.tags.contains("vcgt") ? .oeil : .standard }
        if profil.tags.contains("vcgt") { return .sonde }
        return .personnalise
    }

    // MARK: - Textes

    static let mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre",
                       "octobre", "novembre", "décembre"]

    /// « 3 mars 2026 », « 1er janvier 2022 » (sans locale).
    public static func dateEnMots(_ date: Jour) -> String {
        let jour = date.jour == 1 ? "1er" : String(date.jour)
        return "\(jour) \(mois[max(0, min(11, date.mois - 1))]) \(date.annee)"
    }

    /// « 2026-03-03 ».
    static func dateISO(_ date: Jour) -> String {
        String(format: "%04d-%02d-%02d", date.annee, date.mois, date.jour)
    }

    /// Le nom du profil, ou celui de l'écran.
    static func nomProfil(_ a: Affichage) -> String {
        a.profil?.nom ?? a.nom
    }

    /// Le profil en mots, sans le nom de l'écran.
    static func profilEnMots(_ a: Affichage) -> String {
        switch a.etalonnage {
        case .usine:
            return "profil d'usine, non mesuré sur ce Mac"
        case .standard:
            return "profil standard du système « \(nomProfil(a)) », non mesuré"
        case .oeil:
            return "profil fait à l'œil (assistant d'Apple), non mesuré"
        case .sonde:
            var texte = "profil mesuré par une sonde"
            if let logiciel = a.profil?.logiciel { texte += " (\(logiciel))" }
            if let date = a.profil?.date { texte += ", du \(dateEnMots(date))" }
            return texte
        case .personnalise:
            return "profil personnalisé « \(nomProfil(a)) », sans trace d'une sonde"
        case .inconnu:
            return "profil illisible"
        }
    }

    /// Une ligne : « Odyssey G85SD · profil d'usine, non mesuré sur ce Mac ».
    public static func texte(_ a: Affichage) -> String {
        "\(a.nom) · \(profilEnMots(a))"
    }

    /// La remarque dite une fois à Claude, au premier aperçu, si l'écran n'est pas mesuré ; nil s'il
    /// l'est. Elle porte la consigne : les consignes du connecteur n'ont plus de place.
    public static func remarque(_ a: Affichage) -> String? {
        let debut = "Écran principal de l'utilisateur : \(a.nom), \(profilEnMots(a)). Les mesures de view_photo "
            + "n'en dépendent pas, son œil si : quand son avis compte (peau, couleurs), "
        switch a.etalonnage.mesure {
        case .some(true): return nil
        case .some(false): return debut + "lui dire en une phrase que son écran n'est pas étalonné."
        case .none: return debut + "lui demander si son écran est étalonné."
        }
    }

    /// Le texte de la boîte « Claude · écran » de la fenêtre Claude (un clic sur le voyant Écran).
    public static func detail(_ e: Etat) -> String {
        let a = e.principal
        var qualites: [String] = []
        if a.integre { qualites.append("intégré") }
        if a.gamutLarge { qualites.append("gamut large") }
        var lignes = ["Écran principal : \(a.nom)\(qualites.isEmpty ? "" : " (\(qualites.joined(separator: ", ")))")."]
        let nom = "« \(nomProfil(a)) »"
        switch a.etalonnage {
        case .usine:
            lignes.append("Profil de couleur : \(nom), le profil d'usine de l'écran, non mesuré sur ce Mac.")
        case .standard:
            lignes.append("Profil de couleur : \(nom), un profil standard du système, non mesuré sur cet écran.")
        case .oeil:
            lignes.append("Profil de couleur : \(nom), fait à l'œil avec l'assistant d'étalonnage d'Apple, non mesuré.")
        case .sonde:
            var texte = "Profil de couleur : \(nom), mesuré par une sonde"
            if let logiciel = a.profil?.logiciel { texte += " (\(logiciel))" }
            if let date = a.profil?.date { texte += ", profil du \(dateEnMots(date))" }
            lignes.append(texte + ".")
        case .personnalise:
            lignes.append("Profil de couleur : \(nom), un profil personnalisé, sans trace d'une sonde (ni logiciel "
                + "d'étalonnage nommé, ni courbes de la carte graphique).")
        case .inconnu:
            lignes.append("Profil de couleur : illisible.")
        }
        for autre in e.autres {
            lignes.append("Autre écran : \(texte(autre)).")
        }
        lignes.append("")
        let conseil = "Pour juger les couleurs, coupez Night Shift (et True Tone sur un écran Apple)."
        let reglage = "(Réglages Système › Moniteurs › Profil de couleur)"
        switch a.etalonnage.mesure {
        case .some(true):
            lignes.append("Claude mesure la photo par ses chiffres ; vous la jugez sur un écran étalonné.")
        case .some(false):
            lignes.append("Claude mesure la photo par ses chiffres, sans passer par l'écran ; vous la jugez sur le vôtre. "
                + "Sans étalonnage, la peau et les couleurs peuvent y paraître autrement qu'en tirage ou sur un autre "
                + "écran : une sonde d'étalonnage crée un profil mesuré \(reglage). \(conseil)")
        case .none:
            lignes.append("Claude mesure la photo par ses chiffres, sans passer par l'écran ; vous la jugez sur le vôtre. "
                + "Si ce profil ne vient pas d'une sonde d'étalonnage, la peau et les couleurs peuvent y paraître "
                + "autrement qu'en tirage ou sur un autre écran : une sonde crée un profil mesuré \(reglage). \(conseil)")
        }
        return lignes.joined(separator: "\n")
    }

    /// Un écran en JSON : nom, integre, gamut_large, profil (son nom), etalonnage, mesure (vrai, faux
    /// ou null), date_profil (AAAA-MM-JJ, jamais pour un profil d'usine), logiciel, texte ; avec
    /// `detail`, aussi le chemin du profil, qui ne part jamais chez Claude (get_status) : il peut
    /// nommer le dossier personnel et ne lui sert à rien.
    static func json(_ a: Affichage, detail: Bool) -> JSONValue {
        var objet: [String: JSONValue] = [
            "nom": .string(a.nom),
            "integre": .bool(a.integre),
            "gamut_large": .bool(a.gamutLarge),
            "profil": .null,
            "etalonnage": .string(a.etalonnage.rawValue),
            "mesure": .null,
            "texte": .string(texte(a)),
        ]
        if let profil = a.profil {
            objet["profil"] = .string(profil.nom)
        }
        if let mesure = a.etalonnage.mesure {
            objet["mesure"] = .bool(mesure)
        }
        if a.etalonnage != .usine, let date = a.profil?.date {
            objet["date_profil"] = .string(dateISO(date))
        }
        if let logiciel = a.profil?.logiciel {
            objet["logiciel"] = .string(logiciel)
        }
        if detail, let chemin = a.profil?.chemin {
            objet["chemin"] = .string(chemin)
        }
        return .object(objet)
    }

    /// L'état en JSON : `principal` et `autres` ; avec `detail` (fenêtre Claude, --ecran), les
    /// chemins des profils et le texte de la boîte (`detail`).
    public static func json(_ e: Etat, detail: Bool = false) -> JSONValue {
        var objet: [String: JSONValue] = [
            "principal": json(e.principal, detail: detail),
            "autres": .array(e.autres.map { json($0, detail: detail) }),
        ]
        if detail {
            objet["detail"] = .string(Ecran.detail(e))
        }
        return .object(objet)
    }
}
