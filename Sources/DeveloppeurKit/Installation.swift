import CryptoKit
import Foundation

/// Mises à jour par le SSD (1.7, demande de Dany du 3 novembre 2026) : deux Mac, le SSD « Photos »
/// qui passe de l'un à l'autre, et l'autre Mac parfois connecté par cellulaire. Le dossier
/// `<dossier commun>/Installation/` garde la dernière version de tout ce qu'il faut pour Développeur
/// IA et Fibo 2 (module et connecteur, Fibo 2 Studio, uv, mflux et son Python, les modèles de Fibo,
/// SAM 2 de Fibo 2 Studio, Claude Code), avec `manifeste.json` (format 1). Un Mac y dépose ce qu'il a
/// de plus récent (`deposer`) et installe ce que le SSD a de plus récent (`installer`), **sans aucun
/// téléchargement** : seul le dépôt de mflux remplit son cache par uv (le Mac qui dépose a sa
/// connexion), l'installation de mflux se fait hors ligne (`--offline`, Python par un miroir
/// `file://`, mandataire mort qui coupe tout accès au réseau).
///
/// Règles : dossier commun non réglé ou absent : refus (texte du contrat) ; place libre vérifiée
/// avant ; toute copie passe par un nom `.partiel` renommé à la fin (jamais un élément à moitié copié
/// pris pour bon) ; une copie interrompue reprend (fichiers des arbres déjà complets gardés) ou
/// recommence ; mflux et les modèles refusés si un mflux tourne ; Fibo 2 Studio et SAM 2 refusés à
/// l'installation si l'application tourne ; un seul dépôt ou une seule installation à la fois sur ce
/// Mac (verrou). Jamais rien d'effacé chez Dany : une ancienne Fibo 2 Studio va à la Corbeille ; sur le
/// SSD, seul l'ancien exemplaire d'un élément remplacé est retiré.
///
/// Les tests passent un domicile, un dossier des applications, des exécutables (faux uv) et des
/// vérifications (mflux en cours, application ouverte, place libre) temporaires ou simulés.
public final class Installation {
    // MARK: Éléments

    /// Dans l'ordre de l'installation (uv avant mflux, Développeur en dernier).
    public enum Element: String, CaseIterable {
        case uv
        case mflux
        case modelesHF = "modeles_hf"
        case sam2
        case fibo2studio
        case claudeCode = "claude_code"
        case developpeur

        public var nom: String {
            switch self {
            case .uv: return "uv (Python de mflux)"
            case .mflux: return "mflux (moteur de Fibo 2)"
            case .modelesHF: return "Modèles de Fibo (Hugging Face)"
            case .sam2: return "SAM 2 de Fibo 2 Studio"
            case .fibo2studio: return "Fibo 2 Studio"
            case .claudeCode: return "Claude Code"
            case .developpeur: return "Développeur IA (module et connecteur)"
            }
        }
    }

    /// Les modèles de Hugging Face que Fibo demande, à Développeur (`Generatif.depotNormal`,
    /// `depotRapide`, `depotVLM`, SeedVR2 de `mflux-upscale-seedvr2`) comme à Fibo 2 Studio (Generator :
    /// les deux Fibo 2 et FIBO-vlm). Ni Whisper ni les autres modèles du cache. MobileCLIP et BioCLIP 2
    /// sont dans Modeles du dossier commun.
    public static let depotsHF = [Generatif.depotNormal, Generatif.depotRapide, Generatif.depotVLM, "numz/SeedVR2_comfyUI"]
    public static let nomApplicationFibo = "Fibo 2 Studio.app"
    public static let nomManifeste = "manifeste.json"
    public static let formatManifeste = 1
    public static let nomDossier = "Installation"
    /// Marge gardée en plus de la taille à copier.
    public static let marge: Int64 = 1_000_000_000

    // MARK: États

    public enum Etat: String {
        case aJour = "a_jour"
        case ssdPlusRecent = "ssd_plus_recent"
        case macPlusRecent = "mac_plus_recent"
        case absentDuSSD = "absent_du_ssd"
        case absentDuMac = "absent_du_mac"
        case absentPartout = "absent_partout"
        /// Deux ensembles dont chacun a ce que l'autre n'a pas (modèles, SAM 2) : le dépôt et
        /// l'installation ajoutent chacun ce qui manque, sans rien retirer.
        case differents = "differents"

        public var texte: String {
            switch self {
            case .aJour: return "à jour"
            case .ssdPlusRecent: return "SSD plus récent"
            case .macPlusRecent: return "Mac plus récent"
            case .absentDuSSD: return "absent du SSD"
            case .absentDuMac: return "absent du Mac"
            case .absentPartout: return "absent du Mac et du SSD"
            case .differents: return "différents (chacun a ce que l'autre n'a pas)"
            }
        }
        public var aDeposer: Bool { self == .macPlusRecent || self == .absentDuSSD || self == .differents }
        public var aInstaller: Bool { self == .ssdPlusRecent || self == .absentDuMac || self == .differents }
    }

    /// Un fichier suivi par son contenu et sa date (les `refs/*` des modèles, les fichiers de SAM 2) :
    /// à chemin égal, le contenu le plus récent l'emporte (`Installation.toleranceDate`).
    public struct Marque: Equatable {
        public var valeur: String
        /// Date de modification, en secondes depuis 1970 (gardée à la copie).
        public var date: Double
        public init(valeur: String, date: Double) {
            self.valeur = valeur
            self.date = date
        }
        var json: JSONValue { ["valeur": .string(valeur), "date": .number(date)] }
        init?(_ j: JSONValue?) {
            guard let v = j?["valeur"]?.string, let d = j?["date"]?.double else { return nil }
            self.init(valeur: v, date: d)
        }
    }

    /// Deux dates plus proches que ça sont égales (exFAT et FAT gardent la date à 2 s près).
    public static let toleranceDate: Double = 2

    /// Un côté (le Mac ou le SSD) d'un élément : sa version, l'ensemble qui le décrit quand il n'a pas
    /// de numéro (modèles : « dépôt@instantané » et « dépôt@instantané:fichier » de chaque fichier de
    /// l'instantané ; SAM 2 : ses fichiers), ses fichiers marqués (contenu et date : `refs/*` des
    /// modèles, fichiers de SAM 2), et le détail à dire.
    public struct Cote: Equatable {
        public var version: String
        public var ensemble: Set<String>?
        public var marques: [String: Marque]
        public var detail: [String: JSONValue]
        public init(version: String, ensemble: Set<String>? = nil, marques: [String: Marque] = [:], detail: [String: JSONValue] = [:]) {
            self.version = version
            self.ensemble = ensemble
            self.marques = marques
            self.detail = detail
        }
    }

    /// Chaque côté a-t-il un fichier marqué plus récent que l'autre (ou que l'autre n'a pas) ?
    static func marquesPlusRecentes(mac: [String: Marque], ssd: [String: Marque]) -> (mac: Bool, ssd: Bool) {
        var m = false, s = false
        for cle in Set(mac.keys).union(ssd.keys) {
            switch (mac[cle], ssd[cle]) {
            case (.some, nil): m = true
            case (nil, .some): s = true
            case (let a?, let b?) where a.valeur != b.valeur:
                if a.date > b.date + toleranceDate { m = true } else if b.date > a.date + toleranceDate { s = true }
            default: break
            }
        }
        return (m, s)
    }

    static func marquesJSON(_ marques: [String: Marque]) -> JSONValue { .object(marques.mapValues(\.json)) }
    static func marques(_ j: JSONValue?) -> [String: Marque] { (j?.object ?? [:]).compactMapValues { Marque($0) } }

    /// La comparaison : ensembles (inclusion) s'ils existent des deux côtés, sinon numéros (1.6.10 >
    /// 1.6.9, `MiseAJour.plusRecente`) ; deux textes que les numéros ne départagent pas : différents.
    public static func comparer(mac: Cote?, ssd: Cote?) -> Etat {
        guard let mac else { return ssd == nil ? .absentPartout : .absentDuMac }
        guard let ssd else { return .absentDuSSD }
        if let a = mac.ensemble, let b = ssd.ensemble {
            var etat: Etat = a == b ? .aJour : a.isSuperset(of: b) ? .macPlusRecent : b.isSuperset(of: a) ? .ssdPlusRecent : .differents
            // Les fichiers marqués : à chemin égal et contenu différent, le plus récent l'emporte.
            let (macPlus, ssdPlus) = marquesPlusRecentes(mac: mac.marques, ssd: ssd.marques)
            func joindre(_ e: Etat, _ x: Etat) -> Etat { e == .aJour ? x : (e == x ? e : .differents) }
            if macPlus { etat = joindre(etat, .macPlusRecent) }
            if ssdPlus { etat = joindre(etat, .ssdPlusRecent) }
            return etat
        }
        if mac.version == ssd.version { return .aJour }
        if MiseAJour.plusRecente(mac.version, que: ssd.version) { return .macPlusRecent }
        if MiseAJour.plusRecente(ssd.version, que: mac.version) { return .ssdPlusRecent }
        if MiseAJour.composantes(mac.version) != nil, MiseAJour.composantes(ssd.version) != nil { return .aJour }
        return .differents
    }

    // MARK: Environnement

    public struct Resultat {
        public var code: Int32
        public var sortie: String
    }

    /// Lance un exécutable (sans shell) : environnement donné (nil : celui du serveur), délai en
    /// secondes (nil : sans délai) ; sortie et erreurs mêlées.
    public typealias Lanceur = (_ executable: URL, _ arguments: [String], _ environnement: [String: String]?, _ delai: TimeInterval?) -> Resultat

    public struct Avance: Equatable {
        public var element: String
        public var fait: Int64
        public var total: Int64
        public var texte: String
    }

    public struct Environnement {
        public var donnees: DossierDonnees
        /// Le dossier personnel (~) où vont uv, mflux, le cache de Hugging Face, SAM 2, Claude Code.
        public var domicile: URL
        /// /Applications.
        public var applications: URL
        /// Où chercher uv sur ce Mac, le premier qui répond l'emporte à version égale.
        public var uvCandidats: [URL]
        public var cacheHF: URL
        public var connecteur: URL
        public var module: URL
        /// L'archive de Développeur gardée sur ce Mac par install.sh (le dépôt sans --archive).
        public var archiveLocale: URL
        /// Temporaire/Mises a jour, local.
        public var temporaire: URL
        public var nomOrdinateur: () -> String
        public var mfluxEnCours: () -> Bool
        public var fiboStudioOuvert: () -> Bool
        /// Octets libres du volume qui porte ce chemin (nil : inconnu, rien n'est refusé).
        public var placeLibre: (URL) -> Int64?
        public var lancer: Lanceur
        /// Met à la Corbeille (une ancienne Fibo 2 Studio) ; les tests la déplacent ailleurs.
        public var corbeille: (URL) throws -> Void
        public var avancement: (Avance) -> Void
        public var maintenant: () -> Date

        public init(donnees: DossierDonnees = DossierDonnees(),
                    domicile: URL = FileManager.default.homeDirectoryForCurrentUser,
                    applications: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
                    uvCandidats: [URL]? = nil, cacheHF: URL? = nil, connecteur: URL? = nil, module: URL? = nil,
                    nomOrdinateur: @escaping () -> String = Installation.nomDeCetOrdinateur,
                    mfluxEnCours: @escaping () -> Bool = Fibo.mfluxEnCours,
                    fiboStudioOuvert: @escaping () -> Bool = Installation.fiboStudioEnCours,
                    placeLibre: @escaping (URL) -> Int64? = Installation.placeLibreReelle,
                    lancer: @escaping Lanceur = Installation.lancerProcessus,
                    corbeille: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
                    avancement: @escaping (Avance) -> Void = { _ in },
                    maintenant: @escaping () -> Date = Date.init) {
            self.donnees = donnees
            self.domicile = domicile
            self.applications = applications
            self.uvCandidats = uvCandidats ?? Installation.uvCandidats(domicile: domicile, essai: false)
            self.cacheHF = cacheHF ?? domicile.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
            self.connecteur = connecteur ?? donnees.racineLocale.appendingPathComponent("mcp-developpeur")
            self.module = module ?? domicile.appendingPathComponent("Library/Application Support/Adobe/Lightroom/Modules/Developpeur.lrplugin", isDirectory: true)
            self.archiveLocale = donnees.racineLocale.appendingPathComponent("Archive/Developpeur.zip")
            self.temporaire = donnees.racineLocale.appendingPathComponent("Temporaire/Mises a jour", isDirectory: true)
            self.nomOrdinateur = nomOrdinateur
            self.mfluxEnCours = mfluxEnCours
            self.fiboStudioOuvert = fiboStudioOuvert
            self.placeLibre = placeLibre
            self.lancer = lancer
            self.corbeille = corbeille
            self.avancement = avancement
            self.maintenant = maintenant
        }

        // Chemins de ce Mac
        var outilsUV: URL { domicile.appendingPathComponent(".local/share/uv/tools", isDirectory: true) }
        var binLocal: URL { domicile.appendingPathComponent(".local/bin", isDirectory: true) }
        var pythonUV: URL { domicile.appendingPathComponent(".local/share/uv/python", isDirectory: true) }
        var sam2: URL { domicile.appendingPathComponent("Library/Application Support/Fibo 2 Studio/SAM2", isDirectory: true) }
        var versionsClaude: URL { domicile.appendingPathComponent(".local/share/claude/versions", isDirectory: true) }
        var lienClaude: URL { binLocal.appendingPathComponent("claude") }
        var applicationFibo: URL { applications.appendingPathComponent(Installation.nomApplicationFibo, isDirectory: true) }
    }

    /// Où chercher uv : ~/.local/bin, puis Homebrew. Pour un essai à la main sur un domicile donné
    /// (`DEVELOPPEUR_DOMICILE`), ce domicile seul : l'uv du vrai Mac ne doit pas répondre à sa place.
    public static func uvCandidats(domicile: URL, essai: Bool) -> [URL] {
        let local = domicile.appendingPathComponent(".local/bin/uv")
        return essai ? [local] : [local, URL(fileURLWithPath: "/opt/homebrew/bin/uv"), URL(fileURLWithPath: "/usr/local/bin/uv")]
    }

    public let env: Environnement
    public init(_ env: Environnement = Environnement()) { self.env = env }

    // MARK: Refus

    public struct Refus: Error, LocalizedError {
        public let texte: String
        public init(_ texte: String) { self.texte = texte }
        public var errorDescription: String? { texte }
    }

    public static let texteNonRegle = "Aucun dossier commun n'est réglé : les mises à jour par le SSD passent par lui. Le régler dans "
        + "Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom › Dossier commun."
    public static let texteMfluxEnCours = "Un calcul de mflux tourne sur ce Mac (Fibo 2 Studio, Développeur ou le Terminal) : "
        + "mflux et les modèles se mettent à jour une fois qu'il est fini."
    public static let texteFiboOuvert = "Fibo 2 Studio est ouvert : le quitter (⌘Q) quand il ne sert plus, puis relancer la mise à jour. "
        + "Développeur ne le quitte jamais à votre place."
    public static let texteVerrou = "Une autre mise à jour par le SSD est déjà en cours sur ce Mac : attendre qu'elle finisse."

    /// Le dossier Installation du dossier commun ; refus s'il n'est pas réglé ou s'il est introuvable.
    public func dossierInstallation() throws -> URL {
        switch env.donnees.etat() {
        case .local: throw Refus(Self.texteNonRegle)
        case .communAbsent(let url): throw Refus(DossierDonnees.texteIntrouvable(url.path))
        case .commun(let url): return url.appendingPathComponent(Self.nomDossier, isDirectory: true)
        }
    }

    // MARK: Manifeste

    func lireManifeste(_ installation: URL) -> [String: [String: JSONValue]] {
        let url = installation.appendingPathComponent(Self.nomManifeste)
        guard let data = try? Data(contentsOf: url), let objet = (try? JSONCoding.parse(data))?.object,
              objet["format"]?.int == Self.formatManifeste, let elements = objet["elements"]?.object else { return [:] }
        return elements.compactMapValues(\.object)
    }

    func ecrireManifeste(_ installation: URL, _ elements: [String: [String: JSONValue]]) throws {
        let url = installation.appendingPathComponent(Self.nomManifeste)
        let partiel = installation.appendingPathComponent(Self.nomManifeste + ".partiel")
        let objet: JSONValue = ["format": .number(Double(Self.formatManifeste)),
                                "elements": .object(elements.mapValues(JSONValue.object))]
        try Data((JSONCoding.pretty(objet) + "\n").utf8).write(to: partiel)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: partiel)
    }

    /// Une entrée du manifeste pour un élément déposé.
    func entree(version: String, fichiers: [(chemin: String, taille: Int64, sha256: String?)], en plus: [String: JSONValue] = [:]) -> [String: JSONValue] {
        var e = plus
        e["version"] = .string(version)
        e["fichiers"] = .array(fichiers.map { f in
            var o: [String: JSONValue] = ["chemin": .string(f.chemin), "taille": .number(Double(f.taille))]
            if let s = f.sha256 { o["sha256"] = .string(s) }
            return .object(o)
        })
        e["taille"] = .number(Double(fichiers.reduce(0) { $0 + $1.taille }))
        e["depose_le"] = .string(Self.dateISO(env.maintenant()))
        e["depuis"] = .string(env.nomOrdinateur())
        return e
    }

    static func dateISO(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Le côté SSD d'un élément, d'après le manifeste, seulement si ses fichiers sont là (et à leur
    /// taille, pour un fichier) : un élément annoncé mais incomplet est absent.
    func coteSSD(_ element: Element, installation: URL, manifeste: [String: [String: JSONValue]]) -> Cote? {
        guard let e = manifeste[element.rawValue], let version = e["version"]?.string else { return nil }
        let fm = FileManager.default
        for f in e["fichiers"]?.array ?? [] {
            guard let chemin = f["chemin"]?.string else { return nil }
            let url = installation.appendingPathComponent(chemin)
            var dossier: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &dossier) else { return nil }
            if !dossier.boolValue, let taille = f["taille"]?.double, Int64(taille) != Self.taille(url) { return nil }
        }
        let ensemble = e["ensemble"]?.array.map { Set($0.compactMap(\.string)) }
        var detail: [String: JSONValue] = [:]
        for cle in ["depose_le", "depuis", "taille", "python", "uv", "modeles", "connecteur", "module"] { detail[cle] = e[cle] }
        return Cote(version: version, ensemble: ensemble, marques: Self.marques(e["marques"]), detail: detail)
    }

    // MARK: Côté Mac

    public func coteMac(_ element: Element) -> Cote? {
        switch element {
        case .uv: return uvDuMac().map { Cote(version: $0.version, detail: ["chemin": .string($0.url.path)]) }
        case .mflux: return mfluxDuMac().map { Cote(version: $0.version, detail: ["python": .string($0.python)]) }
        case .modelesHF:
            let inv = Self.inventaireHF(hub: env.cacheHF, depots: Self.depotsHF)
            guard !inv.ensemble.isEmpty else { return nil }
            return Cote(version: Self.texteModeles(inv.ensemble), ensemble: inv.ensemble, marques: inv.marques,
                        detail: ["taille": .number(Double(inv.taille)), "modeles": inv.modelesJSON])
        case .sam2:
            let inv = Self.inventaireDossier(env.sam2, empreintes: true)
            guard !inv.ensemble.isEmpty else { return nil }
            return Cote(version: "\(inv.ensemble.count) fichiers de modèles", ensemble: inv.ensemble, marques: inv.marques,
                        detail: ["taille": .number(Double(inv.taille))])
        case .fibo2studio:
            guard let v = Self.versionApplication(env.applicationFibo) else { return nil }
            return Cote(version: v)
        case .claudeCode: return claudeDuMac().map { Cote(version: $0.version, detail: ["chemin": .string($0.url.path)]) }
        case .developpeur:
            let connecteur = versionConnecteur()
            let module = Self.versionModule(env.module.appendingPathComponent("Info.lua"))
            var detail: [String: JSONValue] = [:]
            detail["connecteur"] = connecteur.map(JSONValue.string)
            detail["module"] = module.map(JSONValue.string)
            // La plus ancienne des deux : c'est elle qu'une installation remplace.
            let versions = [connecteur, module].compactMap { $0 }
            guard let premiere = versions.first else { return nil }
            let v = versions.reduce(premiere) { MiseAJour.plusRecente($0, que: $1) ? $1 : $0 }
            return Cote(version: v, detail: detail)
        }
    }

    func uvDuMac() -> (version: String, url: URL)? {
        var meilleur: (version: String, url: URL)?
        for url in env.uvCandidats where FileManager.default.isExecutableFile(atPath: url.path) {
            guard let v = versionUV(url) else { continue }
            if meilleur == nil || MiseAJour.plusRecente(v, que: meilleur!.version) { meilleur = (v, url) }
        }
        return meilleur
    }

    func versionUV(_ url: URL) -> String? {
        let r = env.lancer(url, ["--version"], nil, 10)
        guard r.code == 0 else { return nil }
        let mots = r.sortie.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard mots.count >= 2, mots[0] == "uv", MiseAJour.composantes(String(mots[1])) != nil else { return nil }
        return String(mots[1])
    }

    /// mflux installé par uv : sa version (dist-info) et celle de son Python (pyvenv.cfg).
    func mfluxDuMac() -> (version: String, python: String)? {
        Self.mfluxDans(env.outilsUV.appendingPathComponent("mflux", isDirectory: true))
    }

    static func mfluxDans(_ dossier: URL) -> (version: String, python: String)? {
        let fm = FileManager.default
        guard let cfg = try? String(contentsOf: dossier.appendingPathComponent("pyvenv.cfg"), encoding: .utf8),
              let python = cfg.split(separator: "\n").first(where: { $0.hasPrefix("version_info") })?
                .split(separator: "=").last?.trimmingCharacters(in: .whitespaces) else { return nil }
        let lib = dossier.appendingPathComponent("lib", isDirectory: true)
        for py in (try? fm.contentsOfDirectory(atPath: lib.path)) ?? [] where py.hasPrefix("python") {
            let site = lib.appendingPathComponent(py).appendingPathComponent("site-packages")
            for nom in (try? fm.contentsOfDirectory(atPath: site.path)) ?? [] where nom.hasPrefix("mflux-") && nom.hasSuffix(".dist-info") {
                let v = String(nom.dropFirst("mflux-".count).dropLast(".dist-info".count))
                if MiseAJour.composantes(v) != nil { return (v, python) }
            }
        }
        return nil
    }

    /// Claude Code : ~/.local/bin/claude, lien vers ~/.local/share/claude/versions/<version>.
    func claudeDuMac() -> (version: String, url: URL)? {
        let fm = FileManager.default
        if let cible = try? fm.destinationOfSymbolicLink(atPath: env.lienClaude.path) {
            let url = URL(fileURLWithPath: cible, relativeTo: env.binLocal).standardizedFileURL
            let v = url.lastPathComponent
            if MiseAJour.composantes(v) != nil, fm.isExecutableFile(atPath: url.path) { return (v, url) }
        }
        guard fm.isExecutableFile(atPath: env.lienClaude.path) else { return nil }
        let r = env.lancer(env.lienClaude, ["--version"], nil, 10)
        guard r.code == 0, let v = r.sortie.split(separator: " ").first.map(String.init), MiseAJour.composantes(v) != nil else { return nil }
        return (v, env.lienClaude.resolvingSymlinksInPath())
    }

    func versionConnecteur() -> String? {
        guard FileManager.default.isExecutableFile(atPath: env.connecteur.path) else { return nil }
        let r = env.lancer(env.connecteur, ["--version"], nil, 10)
        let v = r.sortie.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && MiseAJour.composantes(v) != nil ? v : nil
    }

    /// La version d'un Info.lua de module (`VERSION = { major = 1, minor = 6, revision = 7 … }`).
    public static func versionModule(texte: String) -> String? {
        guard let debut = texte.range(of: #"VERSION\s*=\s*\{"#, options: .regularExpression), let fin = texte[debut.upperBound...].firstIndex(of: "}") else { return nil }
        let bloc = String(texte[debut.upperBound..<fin])
        func champ(_ nom: String) -> Int? {
            guard let r = bloc.range(of: #"\b"# + nom + #"\s*=\s*(\d+)"#, options: .regularExpression) else { return nil }
            return Int(bloc[r].split(separator: "=").last!.trimmingCharacters(in: .whitespaces))
        }
        guard let major = champ("major"), let minor = champ("minor") else { return nil }
        let revision = champ("revision") ?? 0
        return revision > 0 ? "\(major).\(minor).\(revision)" : "\(major).\(minor)"
    }

    static func versionModule(_ infoLua: URL) -> String? {
        (try? String(contentsOf: infoLua, encoding: .utf8)).flatMap { versionModule(texte: $0) }
    }

    static func versionApplication(_ app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let objet = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let v = objet["CFBundleShortVersionString"] as? String, !v.isEmpty else { return nil }
        return v
    }

    /// La version de Développeur dans une archive (Developpeur/Developpeur.lrplugin/Info.lua), lue par unzip.
    func versionArchive(_ zip: URL) -> String? {
        let r = env.lancer(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", zip.path, "Developpeur/Developpeur.lrplugin/Info.lua"], nil, 30)
        return r.code == 0 ? Self.versionModule(texte: r.sortie) : nil
    }

    /// Le témoin qu'une archive est d'essai (build.sh sans notarisation ou avec --sans-tests) : elle ne
    /// va jamais sur le SSD, l'autre Mac la proposerait.
    public static let temoinEssai = "Developpeur/ESSAI"
    public static let texteArchiveEssai = "archive d'essai (non notarisée, ou construite avec --sans-tests) : jamais déposée sur le SSD."

    func archiveDEssai(_ zip: URL) -> Bool {
        env.lancer(URL(fileURLWithPath: "/usr/bin/unzip"), ["-l", zip.path, Self.temoinEssai], nil, 30).code == 0
    }

    // MARK: Comparaison

    public struct Ligne {
        public var element: Element
        public var mac: Cote?
        public var ssd: Cote?
        public var etat: Etat
    }

    public func comparer() throws -> [Ligne] {
        let installation = try dossierInstallation()
        let manifeste = lireManifeste(installation)
        return Element.allCases.map { element in
            let mac = coteMac(element)
            let ssd = coteSSD(element, installation: installation, manifeste: manifeste)
            return Ligne(element: element, mac: mac, ssd: ssd, etat: Self.comparer(mac: mac, ssd: ssd))
        }
    }

    public static func json(_ ligne: Ligne) -> JSONValue {
        func cote(_ c: Cote?) -> JSONValue {
            guard let c else { return .null }
            var o = c.detail
            o["version"] = .string(c.version)
            return .object(o)
        }
        return ["element": .string(ligne.element.rawValue), "nom": .string(ligne.element.nom), "etat": .string(ligne.etat.rawValue),
                "etat_texte": .string(ligne.etat.texte), "mac": cote(ligne.mac), "ssd": cote(ligne.ssd),
                "a_deposer": .bool(ligne.etat.aDeposer), "a_installer": .bool(ligne.etat.aInstaller)]
    }

    public static func texte(_ ligne: Ligne) -> String {
        let mac = ligne.mac.map { "Mac \($0.version)" } ?? "absent du Mac"
        let ssd = ligne.ssd.map { "SSD \($0.version)" + ($0.detail["depuis"]?.string.map { ", déposé depuis « \($0) »" } ?? "") } ?? "absent du SSD"
        return "\(ligne.element.nom) : \(ligne.etat.texte) (\(mac) ; \(ssd))"
    }

    static func texteModeles(_ ensemble: Set<String>) -> String {
        let instantanes = ensemble.filter { !$0.contains(":") }
        let depots = Set(instantanes.compactMap { $0.split(separator: "@").first.map(String.init) })
        return "\(depots.count) modèle\(depots.count > 1 ? "s" : ""), \(instantanes.count) instantané\(instantanes.count > 1 ? "s" : "")"
    }

    // MARK: Action

    public struct Fait {
        public var element: Element
        /// « depose », « installe », « rien », « refuse », « echec ».
        public var action: String
        /// Une phrase, sans retour à la ligne.
        public var texte: String
        /// Ce qui l'accompagne (les notes d'install.sh), une phrase chacune.
        public var notes: [String] = []
        public init(element: Element, action: String, texte: String, notes: [String] = []) {
            self.element = element
            self.action = action
            self.texte = texte
            self.notes = notes
        }
        public var json: JSONValue {
            ["element": .string(element.rawValue), "action": .string(action), "texte": .string(texte),
             "notes": .array(notes.map(JSONValue.string))]
        }
    }

    /// Ce qu'il faut relancer après des installations (texte pour Dany).
    public static func aRelancer(_ faits: [Fait]) -> [String] {
        let installes = Set(faits.filter { $0.action == "installe" }.map(\.element))
        var r: [String] = []
        if installes.contains(.developpeur) {
            r.append("Lightroom Classic : le quitter et le relancer pour charger le nouveau module.")
            r.append("Claude Desktop : le quitter (⌘Q) et le rouvrir, puis ouvrir une nouvelle session de Claude Code, pour le nouveau connecteur.")
        }
        if installes.contains(.claudeCode) { r.append("Claude Code : ouvrir une nouvelle session (la fenêtre Claude relance le sien d'elle-même).") }
        if installes.contains(.fibo2studio) || installes.contains(.sam2) { r.append("Fibo 2 Studio : le rouvrir.") }
        return r
    }

    /// Dépose (vers le SSD) ou installe (sur ce Mac) les éléments donnés, ou, sans liste, tous ceux
    /// que la comparaison désigne. Un élément à jour ne bouge pas ; un refus n'arrête pas les autres.
    public func executer(deposer depot: Bool, elements demandes: [Element]?, archive: URL? = nil) throws -> (lignes: [Ligne], faits: [Fait]) {
        let installation = try dossierInstallation()
        let verrou = try prendreVerrou()
        defer { close(verrou) }
        try FileManager.default.createDirectory(at: installation, withIntermediateDirectories: true)
        var lignes = try comparer()
        var faits: [Fait] = []
        for element in Element.allCases {
            guard let i = lignes.firstIndex(where: { $0.element == element }) else { continue }
            let ligne = lignes[i]
            // Une archive donnée (build.sh, install.sh) se dépose même si ce Mac n'a pas encore Développeur.
            let voulu = demandes?.contains(element) ?? (depot ? ligne.etat.aDeposer || (element == .developpeur && archive != nil) : ligne.etat.aInstaller)
            guard voulu else { continue }
            // Développeur se dépose depuis une archive : sans elle (ni --archive ni celle d'install.sh), rien.
            if depot, element == .developpeur, demandes == nil, archive == nil,
               !FileManager.default.fileExists(atPath: env.archiveLocale.path) { continue }
            // Développeur au dépôt : l'archive se compare elle-même à celle du SSD.
            guard depot ? ligne.etat.aDeposer || element == .developpeur : ligne.etat.aInstaller else {
                let pourquoi: String
                switch ligne.etat {
                case .aJour: pourquoi = "déjà à jour"
                case .absentPartout: pourquoi = "absent du Mac et du SSD"
                case .absentDuMac, .ssdPlusRecent: pourquoi = "le SSD est plus récent : rien à déposer (--installer)"
                default: pourquoi = "ce Mac est plus récent : rien à installer (--deposer)"
                }
                faits.append(Fait(element: element, action: "rien", texte: "\(element.nom) : \(pourquoi)."))
                continue
            }
            do {
                let rendu = depot ? try self.deposer(element, ligne: ligne, installation: installation, archive: archive)
                    : try installer(element, ligne: ligne, installation: installation)
                // Première ligne : le fait ; les suivantes : ses notes.
                var lignesRendu = rendu.components(separatedBy: "\n")
                let texte = lignesRendu.removeFirst()
                faits.append(Fait(element: element, action: texte.hasPrefix("=") ? "rien" : (depot ? "depose" : "installe"),
                                  texte: texte.hasPrefix("=") ? String(texte.dropFirst()) : texte, notes: lignesRendu.filter { !$0.isEmpty }))
            } catch let refus as Refus {
                faits.append(Fait(element: element, action: "refuse", texte: "\(element.nom) : \(refus.texte)"))
            } catch {
                faits.append(Fait(element: element, action: "echec", texte: "\(element.nom) : échec (\(error.localizedDescription))."))
            }
            if let f = faits.last { journaliser(([(depot ? "dépôt" : "installation") + ", " + f.action + " : " + f.texte] + f.notes.map { "  - " + $0 }).joined(separator: "\n")) }
            // L'état d'après, relu.
            let manifeste = lireManifeste(installation)
            let mac = coteMac(element)
            let ssd = coteSSD(element, installation: installation, manifeste: manifeste)
            lignes[i] = Ligne(element: element, mac: mac, ssd: ssd, etat: Self.comparer(mac: mac, ssd: ssd))
        }
        return (lignes, faits)
    }

    /// Un seul dépôt ou une seule installation à la fois sur ce Mac (`flock`, rendu par le noyau à la
    /// fin du processus).
    func prendreVerrou() throws -> Int32 {
        let fichier = env.temporaire.deletingLastPathComponent().appendingPathComponent("mises-a-jour.verrou")
        try FileManager.default.createDirectory(at: fichier.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(fichier.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Refus("verrou illisible : \(fichier.path)") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw Refus(Self.texteVerrou)
        }
        return fd
    }

    func verifierPlace(_ octets: Int64, sur cible: URL) throws {
        var dossier = cible
        while !FileManager.default.fileExists(atPath: dossier.path), dossier.path != "/" { dossier.deleteLastPathComponent() }
        guard let libre = env.placeLibre(dossier) else { return }
        if octets + Self.marge > libre {
            throw Refus("place insuffisante sur le disque de \(dossier.path) : il faut \(Self.go(octets + Self.marge)), il reste \(Self.go(libre)).")
        }
    }

    static func go(_ octets: Int64) -> String {
        String(format: "%.1f Go", Double(octets) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }

    func avancer(_ element: Element, _ fait: Int64, _ total: Int64, _ texte: String) {
        env.avancement(Avance(element: element.rawValue, fait: fait, total: total, texte: texte))
    }

    // MARK: Dépôt

    func deposer(_ element: Element, ligne: Ligne, installation: URL, archive: URL?) throws -> String {
        let fm = FileManager.default
        var manifeste = lireManifeste(installation)
        switch element {
        case .uv:
            guard let uv = uvDuMac() else { throw Refus("uv est absent de ce Mac.") }
            let source = uv.url.resolvingSymlinksInPath()
            try verifierPlace(Self.taille(source), sur: installation)
            let partiel = try dossierPartiel(installation, element)
            let cible = partiel.appendingPathComponent("uv")
            try copierFichier(source, vers: cible, element: element)
            chmod(cible.path, 0o755)
            let sha = try Self.sha256(cible)
            try remplacer(partiel, par: installation.appendingPathComponent(element.rawValue))
            manifeste[element.rawValue] = entree(version: uv.version, fichiers: [("uv/uv", Self.taille(source), sha)])
            try ecrireManifeste(installation, manifeste)
            return "uv \(uv.version) déposé sur le SSD."

        case .developpeur:
            guard let zip = archive ?? (fm.fileExists(atPath: env.archiveLocale.path) ? env.archiveLocale : nil) else {
                throw Refus("il faut l'archive Developpeur.zip (./build.sh --install ou install.sh la déposent ; sinon --archive <Developpeur.zip>).")
            }
            guard let v = versionArchive(zip) else { throw Refus("\(zip.path) n'est pas une archive de Développeur lisible.") }
            if archiveDEssai(zip) { throw Refus(Self.texteArchiveEssai) }
            if let ssd = ligne.ssd?.version {
                if ssd == v { return "=Développeur IA \(v) est déjà sur le SSD." }
                if MiseAJour.plusRecente(ssd, que: v) { throw Refus("le SSD a déjà la \(ssd), plus récente que cette archive (\(v)).") }
            }
            try verifierPlace(Self.taille(zip), sur: installation)
            let partiel = try dossierPartiel(installation, element)
            let cible = partiel.appendingPathComponent("Developpeur.zip")
            try copierFichier(zip, vers: cible, element: element)
            let sha = try Self.sha256(cible), taille = Self.taille(cible)
            try remplacer(partiel, par: installation.appendingPathComponent(element.rawValue))
            manifeste[element.rawValue] = entree(version: v, fichiers: [("developpeur/Developpeur.zip", taille, sha)])
            try ecrireManifeste(installation, manifeste)
            return "Développeur IA \(v) déposé sur le SSD."

        case .fibo2studio:
            guard let v = ligne.mac?.version else { throw Refus("Fibo 2 Studio est absent de ce Mac.") }
            try verifierPlace(Self.tailleArbre(env.applicationFibo), sur: installation)
            let partiel = try dossierPartiel(installation, element)
            let cible = partiel.appendingPathComponent("Fibo 2 Studio.zip")
            try? fm.removeItem(at: cible)
            avancer(element, 0, 1, "Fibo 2 Studio \(v) : archive (ditto)")
            let r = env.lancer(URL(fileURLWithPath: "/usr/bin/ditto"), ["-c", "-k", "--keepParent", env.applicationFibo.path, cible.path], nil, 600)
            guard r.code == 0 else { throw Refus("ditto a échoué : \(r.sortie.prefix(300))") }
            let sha = try Self.sha256(cible)
            try remplacer(partiel, par: installation.appendingPathComponent(element.rawValue))
            manifeste[element.rawValue] = entree(version: v, fichiers: [("fibo2studio/Fibo 2 Studio.zip", Self.taille(installation.appendingPathComponent("fibo2studio/Fibo 2 Studio.zip")), sha)])
            try ecrireManifeste(installation, manifeste)
            avancer(element, 1, 1, "Fibo 2 Studio \(v) déposé")
            return "Fibo 2 Studio \(v) déposé sur le SSD."

        case .claudeCode:
            guard let claude = claudeDuMac() else { throw Refus("Claude Code est absent de ce Mac (~/.local/bin/claude).") }
            try verifierPlace(Self.taille(claude.url), sur: installation)
            let partiel = try dossierPartiel(installation, element)
            let nom = "claude-\(claude.version)"
            let cible = partiel.appendingPathComponent(nom)
            try copierFichier(claude.url, vers: cible, element: element)
            chmod(cible.path, 0o755)
            let sha = try Self.sha256(cible), taille = Self.taille(cible)
            try remplacer(partiel, par: installation.appendingPathComponent(element.rawValue))
            manifeste[element.rawValue] = entree(version: claude.version, fichiers: [("claude_code/" + nom, taille, sha)])
            try ecrireManifeste(installation, manifeste)
            return "Claude Code \(claude.version) déposé sur le SSD."

        case .mflux:
            if env.mfluxEnCours() { throw Refus(Self.texteMfluxEnCours) }
            return try deposerMflux(installation: installation, manifeste: &manifeste)

        case .modelesHF:
            if env.mfluxEnCours() { throw Refus(Self.texteMfluxEnCours) }
            let hub = installation.appendingPathComponent("modeles_hf/hub", isDirectory: true)
            let inv = Self.inventaireHF(hub: env.cacheHF, depots: Self.depotsHF)
            guard !inv.entrees.isEmpty else { throw Refus("aucun des modèles de Fibo n'est dans le cache de Hugging Face de ce Mac.") }
            try copierArbre(inv.entrees, de: env.cacheHF, vers: hub, element: element, marques: Set(inv.marques.keys))
            // L'inventaire du SSD est relu après la pose des liens : seul ce qui est vraiment là est déclaré.
            let surSSD = Self.inventaireHF(hub: hub, depots: Self.depotsHF)
            manifeste[element.rawValue] = entree(version: Self.texteModeles(surSSD.ensemble), fichiers: [("modeles_hf/hub", surSSD.taille, nil)],
                                                 en: ["ensemble": .array(surSSD.ensemble.sorted().map(JSONValue.string)), "modeles": surSSD.modelesJSON,
                                                      "marques": Self.marquesJSON(surSSD.marques)])
            try ecrireManifeste(installation, manifeste)
            return "Modèles de Fibo déposés sur le SSD (\(Self.texteModeles(surSSD.ensemble)), \(Self.go(surSSD.taille)))."

        case .sam2:
            let cible = installation.appendingPathComponent("sam2/SAM2", isDirectory: true)
            let inv = Self.inventaireDossier(env.sam2, empreintes: true)
            guard !inv.entrees.isEmpty else { throw Refus("SAM 2 de Fibo 2 Studio est absent de ce Mac.") }
            try copierArbre(inv.entrees, de: env.sam2, vers: cible, element: element, marques: Set(inv.marques.keys))
            let surSSD = Self.inventaireDossier(cible, empreintes: true)
            manifeste[element.rawValue] = entree(version: "\(surSSD.ensemble.count) fichiers de modèles", fichiers: [("sam2/SAM2", surSSD.taille, nil)],
                                                 en: ["ensemble": .array(surSSD.ensemble.sorted().map(JSONValue.string)),
                                                      "marques": Self.marquesJSON(surSSD.marques)])
            try ecrireManifeste(installation, manifeste)
            return "SAM 2 de Fibo 2 Studio déposé sur le SSD (\(Self.go(surSSD.taille)))."
        }
    }

    /// mflux : son cache uv et l'archive de son Python rangés sur le SSD, pour une installation hors
    /// ligne. uv remplit un cache neuf (`<Installation>/mflux.partiel/cache`) en installant la même
    /// version de mflux, avec le même Python, dans des dossiers d'outils temporaires (jamais ceux de ce
    /// Mac) ; l'archive de Python, gardée par uv (UV_PYTHON_CACHE_DIR), est rangée comme le miroir de
    /// python-build-standalone l'attend (`python/<date>/cpython-<v>+<date>-….tar.gz`). Le seul moment
    /// où le réseau sert (PyPI et l'archive de Python) : sur le Mac qui dépose.
    func deposerMflux(installation: URL, manifeste: inout [String: [String: JSONValue]]) throws -> String {
        let fm = FileManager.default
        guard let mflux = mfluxDuMac() else { throw Refus("mflux est absent de ce Mac (uv tool install mflux).") }
        guard let uv = uvDuMac() else { throw Refus("uv est absent de ce Mac.") }
        let estime = Self.tailleArbre(env.outilsUV.appendingPathComponent("mflux")) + 200_000_000
        try verifierPlace(estime, sur: installation)
        // Un dossier partiel d'un dépôt interrompu sert de nouveau : uv reprend son cache.
        let partiel = installation.appendingPathComponent("mflux.partiel", isDirectory: true)
        let cache = partiel.appendingPathComponent("cache", isDirectory: true)
        let archives = partiel.appendingPathComponent("python-archives", isDirectory: true)
        let travail = env.temporaire.appendingPathComponent("mflux-depot", isDirectory: true)
        try? fm.removeItem(at: travail)
        for d in [cache, archives, travail] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: travail) }
        avancer(.mflux, 0, 3, "mflux \(mflux.version) : uv remplit le cache du SSD (PyPI)")
        var e = environnementUV(cache: cache)
        e["UV_PYTHON_CACHE_DIR"] = archives.path
        e["UV_TOOL_DIR"] = travail.appendingPathComponent("tools").path
        e["UV_TOOL_BIN_DIR"] = travail.appendingPathComponent("bin").path
        e["UV_PYTHON_INSTALL_DIR"] = travail.appendingPathComponent("python").path
        e["UV_PYTHON_BIN_DIR"] = travail.appendingPathComponent("pybin").path
        let r = env.lancer(uv.url, ["tool", "install", "mflux==\(mflux.version)", "--python", mflux.python, "--managed-python"], e, 3600)
        guard r.code == 0 else { throw Refus("uv n'a pas pu remplir le cache : \(Self.fin(r.sortie))") }
        guard Self.mfluxDans(travail.appendingPathComponent("tools/mflux")) != nil else { throw Refus("uv n'a pas installé mflux dans le dossier d'essai.") }
        avancer(.mflux, 1, 3, "mflux \(mflux.version) : archive de Python \(mflux.python)")
        // L'archive de Python, au chemin du miroir.
        let motif = #"cpython-(\d+\.\d+\.\d+)-(\d{8})-(.+\.tar\.(gz|zst))$"#
        let python = partiel.appendingPathComponent("python", isDirectory: true)
        var archivePython: String?
        for nom in (try? fm.contentsOfDirectory(atPath: archives.path)) ?? [] {
            guard let r = nom.range(of: motif, options: .regularExpression) else { continue }
            let morceau = String(nom[r])
            let parties = morceau.split(separator: "-", maxSplits: 3).map(String.init)
            guard parties.count == 4, parties[1] == mflux.python else { continue }
            let date = parties[2], reste = parties[3]
            let chemin = "\(date)/cpython-\(parties[1])+\(date)-\(reste)"
            let cible = python.appendingPathComponent(chemin)
            try fm.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: cible)
            try fm.moveItem(at: archives.appendingPathComponent(nom), to: cible)
            archivePython = chemin
        }
        if archivePython == nil {
            // Dépôt repris : l'archive est déjà rangée.
            let deja = (fm.enumerator(atPath: python.path)?.allObjects as? [String] ?? []).first { $0.contains("cpython-\(mflux.python)+") }
            archivePython = deja
        }
        guard let archivePython else { throw Refus("uv n'a pas gardé l'archive de Python \(mflux.python) (UV_PYTHON_CACHE_DIR).") }
        try? fm.removeItem(at: archives)
        avancer(.mflux, 2, 3, "mflux \(mflux.version) : rangement sur le SSD")
        // L'uv qui a rempli ce cache part avec lui : un autre uv peut ranger son cache autrement, ou
        // chercher une autre construction de Python dans le miroir. L'installation se sert de celui-ci.
        try copierFichier(uv.url.resolvingSymlinksInPath(), vers: partiel.appendingPathComponent("uv"), element: .mflux, mode: 0o755)
        try remplacer(partiel, par: installation.appendingPathComponent("mflux"))
        let final = installation.appendingPathComponent("mflux")
        let cheminArchive = final.appendingPathComponent("python").appendingPathComponent(archivePython)
        let uvGarde = final.appendingPathComponent("uv")
        manifeste[Element.mflux.rawValue] = entree(version: mflux.version, fichiers: [
            ("mflux/cache", Self.tailleArbre(final.appendingPathComponent("cache")), nil),
            ("mflux/python/" + archivePython, Self.taille(cheminArchive), try Self.sha256(cheminArchive)),
            ("mflux/uv", Self.taille(uvGarde), try Self.sha256(uvGarde)),
        ], en: ["python": .string(mflux.python), "uv": .string(uv.version)])
        try ecrireManifeste(installation, manifeste)
        avancer(.mflux, 3, 3, "mflux \(mflux.version) déposé")
        return "mflux \(mflux.version) (Python \(mflux.python)) déposé sur le SSD (\(Self.go(Self.tailleArbre(final))))."
    }

    /// L'environnement de uv : propre (ni configuration de l'utilisateur ni réseau d'un mandataire du
    /// serveur), dossier personnel donné.
    func environnementUV(cache: URL) -> [String: String] {
        ["HOME": env.domicile.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "UV_CACHE_DIR": cache.path,
         "UV_NO_MODIFY_PATH": "1", "UV_NO_CONFIG": "1", "UV_PYTHON_DOWNLOADS": "automatic", "LANG": "fr_CA.UTF-8"]
    }

    /// Ce qui coupe tout accès au réseau d'un processus : un mandataire mort (port 9, rien n'écoute).
    static let reseauCoupe = ["HTTP_PROXY": "http://127.0.0.1:9", "HTTPS_PROXY": "http://127.0.0.1:9", "ALL_PROXY": "http://127.0.0.1:9",
                              "http_proxy": "http://127.0.0.1:9", "https_proxy": "http://127.0.0.1:9", "all_proxy": "http://127.0.0.1:9",
                              "NO_PROXY": "", "no_proxy": "", "HF_HUB_OFFLINE": "1", "UV_OFFLINE": "1"]

    // MARK: Installation

    func installer(_ element: Element, ligne: Ligne, installation: URL) throws -> String {
        let fm = FileManager.default
        guard let ssd = ligne.ssd else { throw Refus("absent du SSD.") }
        switch element {
        case .uv:
            let source = installation.appendingPathComponent("uv/uv")
            try verifierPlace(Self.taille(source), sur: env.binLocal)
            try verifierEmpreinte("uv/uv", installation: installation, element: element)
            try fm.createDirectory(at: env.binLocal, withIntermediateDirectories: true)
            let cible = env.binLocal.appendingPathComponent("uv")
            try copierFichier(source, vers: cible, element: element, mode: 0o755)
            return "uv \(ssd.version) installé dans \(cible.path)."

        case .mflux:
            if env.mfluxEnCours() { throw Refus(Self.texteMfluxEnCours) }
            return try installerMflux(installation: installation, ssd: ssd)

        case .modelesHF:
            if env.mfluxEnCours() { throw Refus(Self.texteMfluxEnCours) }
            let hub = installation.appendingPathComponent("modeles_hf/hub", isDirectory: true)
            let inv = Self.inventaireHF(hub: hub, depots: Self.depotsHF)
            try copierArbre(inv.entrees, de: hub, vers: env.cacheHF, element: element, marques: Set(inv.marques.keys))
            // Chaque fichier de chaque instantané du SSD doit maintenant être là, lien compris.
            let surMac = Self.inventaireHF(hub: env.cacheHF, depots: Self.depotsHF)
            let manque = inv.ensemble.subtracting(surMac.ensemble)
            guard manque.isEmpty else {
                throw Refus("copie incomplète : \(manque.count) fichier\(manque.count > 1 ? "s" : "") des modèles manque\(manque.count > 1 ? "nt" : "") "
                    + "dans \(env.cacheHF.path) (\(manque.sorted().prefix(3).joined(separator: ", "))) : relancer l'installation.")
            }
            return "Modèles de Fibo installés dans \(env.cacheHF.path) (\(Self.texteModeles(inv.ensemble)))."

        case .sam2:
            if env.fiboStudioOuvert() { throw Refus(Self.texteFiboOuvert) }
            let source = installation.appendingPathComponent("sam2/SAM2", isDirectory: true)
            let inv = Self.inventaireDossier(source, empreintes: true)
            try copierArbre(inv.entrees, de: source, vers: env.sam2, element: element, marques: Set(inv.marques.keys))
            return "SAM 2 de Fibo 2 Studio installé dans \(env.sam2.path)."

        case .fibo2studio:
            if env.fiboStudioOuvert() { throw Refus(Self.texteFiboOuvert) }
            let zip = installation.appendingPathComponent("fibo2studio/Fibo 2 Studio.zip")
            try verifierPlace(Self.taille(zip) * 3, sur: env.applications)
            try verifierEmpreinte("fibo2studio/Fibo 2 Studio.zip", installation: installation, element: element)
            let partiel = env.applications.appendingPathComponent(".Fibo 2 Studio.partiel", isDirectory: true)
            try? fm.removeItem(at: partiel)
            try fm.createDirectory(at: partiel, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: partiel) }
            avancer(element, 0, 1, "Fibo 2 Studio \(ssd.version) : décompression (ditto)")
            let r = env.lancer(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, partiel.path], nil, 600)
            let nouvelle = partiel.appendingPathComponent(Self.nomApplicationFibo, isDirectory: true)
            guard r.code == 0, Self.versionApplication(nouvelle) != nil else { throw Refus("ditto n'a pas pu décompresser l'application : \(Self.fin(r.sortie))") }
            if fm.fileExists(atPath: env.applicationFibo.path) { try env.corbeille(env.applicationFibo) }
            try fm.moveItem(at: nouvelle, to: env.applicationFibo)
            avancer(element, 1, 1, "Fibo 2 Studio \(ssd.version) installé")
            return "Fibo 2 Studio \(ssd.version) installé dans \(env.applications.path) (l'ancienne version est dans la Corbeille)."

        case .claudeCode:
            guard let fichier = ssd.version.isEmpty ? nil : installation.appendingPathComponent("claude_code/claude-\(ssd.version)"),
                  fm.fileExists(atPath: fichier.path) else { throw Refus("le fichier de Claude Code manque sur le SSD.") }
            try verifierPlace(Self.taille(fichier), sur: env.versionsClaude)
            try verifierEmpreinte("claude_code/claude-\(ssd.version)", installation: installation, element: element)
            try fm.createDirectory(at: env.versionsClaude, withIntermediateDirectories: true)
            let cible = env.versionsClaude.appendingPathComponent(ssd.version)
            try copierFichier(fichier, vers: cible, element: element, mode: 0o755)
            // Le lien, posé à côté puis renommé par-dessus l'ancien.
            try fm.createDirectory(at: env.binLocal, withIntermediateDirectories: true)
            let lien = env.binLocal.appendingPathComponent("claude.partiel")
            try? fm.removeItem(at: lien)
            try fm.createSymbolicLink(atPath: lien.path, withDestinationPath: cible.path)
            guard rename(lien.path, env.lienClaude.path) == 0 else { throw Refus("lien de Claude Code impossible à poser (\(env.lienClaude.path)).") }
            return "Claude Code \(ssd.version) installé (\(env.lienClaude.path))."

        case .developpeur:
            let zip = installation.appendingPathComponent("developpeur/Developpeur.zip")
            try verifierPlace(Self.taille(zip) * 4, sur: env.temporaire)
            try verifierEmpreinte("developpeur/Developpeur.zip", installation: installation, element: element)
            let dossier = env.temporaire.appendingPathComponent("developpeur-\(ssd.version)", isDirectory: true)
            try? fm.removeItem(at: dossier)
            try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dossier) }
            avancer(element, 0, 2, "Développeur IA \(ssd.version) : décompression")
            let r = env.lancer(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", zip.path, dossier.path], nil, 300)
            let script = dossier.appendingPathComponent("Developpeur/install.sh")
            guard r.code == 0, fm.fileExists(atPath: script.path) else { throw Refus("archive illisible : \(Self.fin(r.sortie))") }
            avancer(element, 1, 2, "Développeur IA \(ssd.version) : install.sh")
            var e = ProcessInfo.processInfo.environment
            e["HOME"] = env.domicile.path
            // install.sh ne redépose pas l'archive qu'on vient de prendre sur le SSD.
            e["DEVELOPPEUR_DEPUIS_SSD"] = "1"
            let s = env.lancer(URL(fileURLWithPath: "/bin/bash"), [script.path], e, 900)
            guard s.code == 0 else { throw Refus("install.sh a échoué : \(Self.fin(s.sortie))") }
            avancer(element, 2, 2, "Développeur IA \(ssd.version) installé")
            journaliser("install.sh de Développeur IA \(ssd.version) :\n" + s.sortie.trimmingCharacters(in: .whitespacesAndNewlines))
            // Le fait, puis ses notes (une par ligne : Prochaines étapes et avertissements d'install.sh).
            return (["Développeur IA \(ssd.version) installé."] + Self.notesInstallSh(s.sortie)).joined(separator: "\n")
        }
    }

    /// L'uv de l'installation de mflux : exactement celui qui a rempli le cache (numéro du manifeste) ;
    /// d'abord sa copie gardée avec mflux (`mflux/uv`), sinon celui du SSD (`uv/uv`) ou de ce Mac s'ils
    /// portent ce numéro. Les fichiers du SSD sont vérifiés par leur empreinte avant d'être lancés.
    func uvPourMflux(installation: URL, ssd: Cote) throws -> URL {
        let fm = FileManager.default
        guard let voulu = ssd.detail["uv"]?.string else { throw Refus("le manifeste ne dit pas quel uv a rempli le cache de mflux : redéposer mflux.") }
        let garde = installation.appendingPathComponent("mflux/uv")
        if fm.isExecutableFile(atPath: garde.path) {
            try verifierEmpreinte("mflux/uv", installation: installation, element: .mflux)
            if versionUV(garde) == voulu { return garde }
        }
        let uvSSD = installation.appendingPathComponent("uv/uv")
        if fm.isExecutableFile(atPath: uvSSD.path), versionUV(uvSSD) == voulu {
            try verifierEmpreinte("uv/uv", installation: installation, element: .uv)
            return uvSSD
        }
        for url in env.uvCandidats where fm.isExecutableFile(atPath: url.path) && versionUV(url) == voulu { return url }
        throw Refus("il faut uv \(voulu), celui qui a rempli le cache de mflux, et il n'est ni sur le SSD ni sur ce Mac : redéposer mflux depuis l'autre Mac.")
    }

    /// mflux hors ligne : Python depuis le miroir `file://` du SSD, puis mflux depuis le cache du SSD
    /// (`--offline`), réseau coupé ; avec l'uv qui a rempli le cache (`uvPourMflux`).
    func installerMflux(installation: URL, ssd: Cote) throws -> String {
        let dossier = installation.appendingPathComponent("mflux", isDirectory: true)
        guard let python = ssd.detail["python"]?.string else { throw Refus("le manifeste ne dit pas le Python de mflux.") }
        let uv = try uvPourMflux(installation: installation, ssd: ssd)
        // L'archive de Python, vérifiée avant que uv ne la décompresse.
        for f in lireManifeste(installation)[Element.mflux.rawValue]?["fichiers"]?.array ?? [] {
            if let chemin = f["chemin"]?.string, chemin.hasPrefix("mflux/python/") {
                try verifierEmpreinte(chemin, installation: installation, element: .mflux)
            }
        }
        try verifierPlace(Self.tailleArbre(dossier), sur: env.outilsUV)
        var e = environnementUV(cache: dossier.appendingPathComponent("cache"))
        e.merge(Self.reseauCoupe) { _, b in b }
        e["UV_PYTHON_INSTALL_MIRROR"] = dossier.appendingPathComponent("python", isDirectory: true).absoluteString.trimmingSuffix("/")
        e["UV_PYTHON_INSTALL_DIR"] = env.pythonUV.path
        e["UV_TOOL_DIR"] = env.outilsUV.path
        e["UV_TOOL_BIN_DIR"] = env.binLocal.path
        avancer(.mflux, 0, 2, "Python \(python) depuis le SSD")
        let p = env.lancer(uv, ["python", "install", python, "--no-bin"], e, 600)
        guard p.code == 0 else { throw Refus("uv n'a pas pu installer Python \(python) depuis le SSD : \(Self.fin(p.sortie))") }
        avancer(.mflux, 1, 2, "mflux \(ssd.version) depuis le SSD (hors ligne)")
        let r = env.lancer(uv, ["tool", "install", "mflux==\(ssd.version)", "--python", python, "--managed-python", "--offline", "--force"], e, 1800)
        guard r.code == 0 else { throw Refus("uv n'a pas pu installer mflux hors ligne : \(Self.fin(r.sortie))") }
        guard let installe = mfluxDuMac(), installe.version == ssd.version else { throw Refus("mflux \(ssd.version) introuvable après l'installation.") }
        avancer(.mflux, 2, 2, "mflux \(ssd.version) installé")
        return "mflux \(ssd.version) (Python \(python)) installé hors ligne dans \(env.outilsUV.path)."
    }

    /// Le fichier `chemin` (relatif à Installation) a-t-il l'empreinte que le manifeste lui donne ?
    /// L'entrée se cherche par son chemin ; un fichier sans empreinte au manifeste passe.
    func verifierEmpreinte(_ chemin: String, installation: URL, element: Element) throws {
        let manifeste = lireManifeste(installation)
        let fichiers = manifeste[element.rawValue]?["fichiers"]?.array ?? []
        guard let attendu = fichiers.first(where: { $0["chemin"]?.string == chemin })?["sha256"]?.string else { return }
        guard try Self.sha256(installation.appendingPathComponent(chemin)) == attendu else {
            throw Refus("le fichier \(chemin) du SSD est abîmé (empreinte SHA-256 différente) : le redéposer depuis l'autre Mac.")
        }
    }

    /// Les notes d'install.sh pour Dany : chaque point « - … » qui suit « Prochaines étapes : », ses
    /// lignes de suite jointes en une seule.
    public static func notesInstallSh(_ sortie: String) -> [String] {
        let lignes = sortie.components(separatedBy: "\n")
        guard let debut = lignes.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("Prochaines étapes") }) else { return [] }
        var notes: [String] = []
        for ligne in lignes[(debut + 1)...] {
            let t = ligne.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            if t.hasPrefix("- ") {
                notes.append(String(t.dropFirst(2)))
            } else if ligne.hasPrefix(" "), !notes.isEmpty {
                notes[notes.count - 1] += " " + t
            }
        }
        return notes
    }

    /// Le journal durable des mises à jour (racine locale, `mises-a-jour.journal`) : chaque fait, et la
    /// sortie complète d'install.sh. Gardé sous 1 Mo (la moitié la plus récente).
    func journaliser(_ texte: String) {
        let url = env.donnees.racineLocale.appendingPathComponent(Self.nomJournal)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var tout = (try? Data(contentsOf: url)) ?? Data()
        tout.append(Data("[\(Self.dateISO(env.maintenant()))] \(texte)\n".utf8))
        if tout.count > 1_000_000 { tout = tout.suffix(500_000) }
        try? tout.write(to: url, options: .atomic)
    }

    public static let nomJournal = "mises-a-jour.journal"

    static func fin(_ texte: String) -> String {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 400 ? "…" + String(t.suffix(400)) : (t.isEmpty ? "sans message" : t)
    }

    // MARK: Copies

    /// Un dossier `<élément>.partiel` dans Installation, vidé.
    func dossierPartiel(_ installation: URL, _ element: Element) throws -> URL {
        let partiel = installation.appendingPathComponent(element.rawValue + ".partiel", isDirectory: true)
        try? FileManager.default.removeItem(at: partiel)
        try FileManager.default.createDirectory(at: partiel, withIntermediateDirectories: true)
        return partiel
    }

    /// Le dossier partiel prend la place de l'ancien (mis à `.ancien`, retiré une fois le nouveau en place).
    func remplacer(_ partiel: URL, par final: URL) throws {
        let fm = FileManager.default
        let ancien = final.deletingLastPathComponent().appendingPathComponent(final.lastPathComponent + ".ancien")
        try? fm.removeItem(at: ancien)
        if fm.fileExists(atPath: final.path) { try fm.moveItem(at: final, to: ancien) }
        try fm.moveItem(at: partiel, to: final)
        try? fm.removeItem(at: ancien)
    }

    static let morceau = 16 * 1024 * 1024

    /// Copie un fichier dans `<cible>.partiel` par morceaux (avancement), puis le renomme par-dessus
    /// la cible. Une copie interrompue recommence.
    func copierFichier(_ source: URL, vers cible: URL, element: Element, mode: mode_t? = nil,
                       dejaFait: Int64 = 0, total: Int64? = nil) throws {
        let fm = FileManager.default
        let partiel = cible.deletingLastPathComponent().appendingPathComponent(cible.lastPathComponent + ".partiel")
        try fm.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: partiel)
        guard fm.createFile(atPath: partiel.path, contents: nil) else { throw Refus("écriture impossible : \(partiel.path)") }
        let lecture = try FileHandle(forReadingFrom: source)
        defer { try? lecture.close() }
        let ecriture = try FileHandle(forWritingTo: partiel)
        let taille = Self.taille(source)
        let tout = total ?? taille
        var copie: Int64 = 0
        var dernier = Date.distantPast
        do {
            while let donnees = try lecture.read(upToCount: Self.morceau), !donnees.isEmpty {
                try ecriture.write(contentsOf: donnees)
                copie += Int64(donnees.count)
                if Date().timeIntervalSince(dernier) > 1 {
                    dernier = Date()
                    avancer(element, dejaFait + copie, tout, "\(element.nom) : \(Self.go(dejaFait + copie)) sur \(Self.go(tout))")
                }
            }
            try ecriture.close()
        } catch {
            try? ecriture.close()
            try? fm.removeItem(at: partiel)
            throw error
        }
        guard copie == taille else {
            try? fm.removeItem(at: partiel)
            throw Refus("copie incomplète de \(source.lastPathComponent).")
        }
        if let mode { chmod(partiel.path, mode) } else if let p = try? fm.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber {
            chmod(partiel.path, mode_t(p.uint16Value))
        }
        guard rename(partiel.path, cible.path) == 0 else { throw Refus("renommage impossible : \(cible.path)") }
    }

    /// Une entrée d'un arbre à copier, relative à sa racine.
    public struct Entree: Equatable {
        public enum Genre: Equatable { case dossier, fichier(Int64), lien(String) }
        public var chemin: String
        public var genre: Genre
    }

    /// Copie un arbre : dossiers, puis fichiers, puis liens (posés seulement là où rien n'existe). Un
    /// fichier ordinaire déjà là à la même taille est gardé (une copie interrompue reprend : les blobs
    /// sont nommés par leur empreinte). Un fichier marqué (`marques` : `refs/*` des modèles, fichiers de
    /// SAM 2, dont le nom ne dit pas le contenu) est gardé s'il a le même contenu, remplacé si la source
    /// est plus récente, gardé sinon ; sa date suit la source. Rien n'est retiré de la cible, sauf les
    /// « .partiel » laissés par une copie interrompue (les nôtres) dans les dossiers de l'arbre. Place
    /// vérifiée avant.
    func copierArbre(_ entrees: [Entree], de source: URL, vers cible: URL, element: Element, marques: Set<String> = []) throws {
        let fm = FileManager.default
        func existeA(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
        // Les « .partiel » d'une copie interrompue, dans les dossiers de cet arbre seulement.
        var dossiersArbre: Set<String> = [""]
        for e in entrees {
            if e.genre == .dossier { dossiersArbre.insert(e.chemin) }
            dossiersArbre.insert((e.chemin as NSString).deletingLastPathComponent)
        }
        for d in dossiersArbre {
            let url = d.isEmpty ? cible : cible.appendingPathComponent(d, isDirectory: true)
            for nom in (try? fm.contentsOfDirectory(atPath: url.path)) ?? [] where nom.hasSuffix(".partiel") {
                let f = url.appendingPathComponent(nom)
                if (try? fm.attributesOfItem(atPath: f.path))?[.type] as? FileAttributeType == .typeRegular { try? fm.removeItem(at: f) }
            }
        }
        var aCopier: [(String, Int64)] = []
        for e in entrees {
            if case .fichier(let t) = e.genre {
                let c = cible.appendingPathComponent(e.chemin)
                guard fm.fileExists(atPath: c.path) else { aCopier.append((e.chemin, t)); continue }
                if marques.contains(e.chemin) {
                    let s = source.appendingPathComponent(e.chemin)
                    if Self.taille(c) == t, (try? Self.sha256(c)) == (try? Self.sha256(s)) { continue }
                    if Self.dateModification(s) > Self.dateModification(c) + Self.toleranceDate { aCopier.append((e.chemin, t)) }
                } else if Self.taille(c) != t {
                    aCopier.append((e.chemin, t))
                }
            }
        }
        let total = aCopier.reduce(0) { $0 + $1.1 }
        try verifierPlace(total, sur: cible)
        try fm.createDirectory(at: cible, withIntermediateDirectories: true)
        for e in entrees where e.genre == .dossier {
            try fm.createDirectory(at: cible.appendingPathComponent(e.chemin, isDirectory: true), withIntermediateDirectories: true)
        }
        var fait: Int64 = 0
        avancer(element, 0, total, "\(element.nom) : \(Self.go(total)) à copier")
        for (chemin, t) in aCopier {
            let s = source.appendingPathComponent(chemin), c = cible.appendingPathComponent(chemin)
            try copierFichier(s, vers: c, element: element, dejaFait: fait, total: total)
            if marques.contains(chemin) {
                try? fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: Self.dateModification(s))], ofItemAtPath: c.path)
            }
            fait += t
            avancer(element, fait, total, "\(element.nom) : \(Self.go(fait)) sur \(Self.go(total))")
        }
        for e in entrees {
            guard case .lien(let destination) = e.genre else { continue }
            let c = cible.appendingPathComponent(e.chemin)
            guard !existeA(c) else { continue }
            try fm.createDirectory(at: c.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: c.path, withDestinationPath: destination)
        }
    }

    // MARK: Inventaires

    public struct InventaireHF {
        public var entrees: [Entree] = []
        /// « dépôt@instantané » de chaque instantané complet, et « dépôt@instantané:fichier » de chacun
        /// de ses fichiers : un instantané à moitié là n'est pas égal à un instantané entier.
        public var ensemble: Set<String> = []
        /// Les `models--…/refs/<nom>` (la révision suivie) : valeur et date.
        public var marques: [String: Marque] = [:]
        public var taille: Int64 = 0
        public var modeles: [String: (refs: [String: String], instantanes: [String])] = [:]
        public var modelesJSON: JSONValue {
            .object(modeles.mapValues { m in
                ["refs": .object(m.refs.mapValues(JSONValue.string)), "instantanes": .array(m.instantanes.sorted().map(JSONValue.string))]
            })
        }
    }

    static func ignoree(_ nom: String) -> Bool {
        nom.hasSuffix(".lock") || nom.hasSuffix(".incomplete") || nom == ".locks" || nom.hasSuffix(".partiel") || nom == ".DS_Store"
    }

    /// Les entrées d'un cache de Hugging Face pour ces dépôts : le dossier de chaque modèle (refs,
    /// instantanés, blobs, trees) et, en suivant ses liens, les fichiers qu'ils visent hors de lui (les
    /// blobs partagés `hub/blobs/<xx>/<sha256>` et leur `.refs`), à leur place relative : la structure
    /// reste valide sur l'autre Mac. Rien d'autre du cache (Whisper…). Lecture seule.
    public static func inventaireHF(hub: URL, depots: [String]) -> InventaireHF {
        let fm = FileManager.default
        // La racine elle-même peut être un lien (suivi) ; les liens du cache se lisent ensuite
        // lexicalement (« .. » retiré sans résoudre d'autre lien : la structure du cache seule compte).
        let racine = hub.resolvingSymlinksInPath()
        var inv = InventaireHF()
        var vus = Set<String>()
        var dossiers = Set<String>()
        var tailles: [String: Int64] = [:]
        func ajouterDossier(_ chemin: String) {
            if dossiers.insert(chemin).inserted { inv.entrees.append(Entree(chemin: chemin, genre: .dossier)) }
        }

        /// Le chemin relatif à la racine d'une destination de lien, ou nil s'il sort du cache.
        func relatif(depuis chemin: String, _ destination: String) -> String? {
            guard !destination.hasPrefix("/") else {
                let r = racine.path
                return destination.hasPrefix(r + "/") ? String(destination.dropFirst(r.count + 1)) : nil
            }
            var parties = Array(chemin.split(separator: "/").map(String.init).dropLast())
            for morceau in destination.split(separator: "/").map(String.init) {
                switch morceau {
                case ".", "": continue
                case "..":
                    guard !parties.isEmpty else { return nil }
                    parties.removeLast()
                default: parties.append(morceau)
                }
            }
            return parties.isEmpty ? nil : parties.joined(separator: "/")
        }
        func parcourir(_ chemin: String) {
            guard !vus.contains(chemin) else { return }
            vus.insert(chemin)
            let url = racine.appendingPathComponent(chemin)
            guard let attributs = try? fm.attributesOfItem(atPath: url.path), let type = attributs[.type] as? FileAttributeType else { return }
            switch type {
            case .typeDirectory:
                ajouterDossier(chemin)
                for nom in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where !ignoree(nom) {
                    parcourir(chemin + "/" + nom)
                }
            case .typeSymbolicLink:
                guard let destination = try? fm.destinationOfSymbolicLink(atPath: url.path) else { return }
                inv.entrees.append(Entree(chemin: chemin, genre: .lien(destination)))
                if let r = relatif(depuis: chemin, destination) {
                    // Les dossiers qui mènent à la cible (blobs/xx), puis elle et son .refs.
                    var parents: [String] = []
                    var p = (r as NSString).deletingLastPathComponent
                    while !p.isEmpty, !dossiers.contains(p) {
                        parents.insert(p, at: 0)
                        p = (p as NSString).deletingLastPathComponent
                    }
                    parents.forEach(ajouterDossier)
                    parcourir(r)
                    if r.hasPrefix("blobs/") { parcourir(r + ".refs") }
                }
            case .typeRegular:
                let t = (attributs[.size] as? NSNumber)?.int64Value ?? 0
                inv.entrees.append(Entree(chemin: chemin, genre: .fichier(t)))
                tailles[chemin] = t
            default: return
            }
        }
        for depot in depots {
            let modele = "models--" + depot.replacingOccurrences(of: "/", with: "--")
            guard fm.fileExists(atPath: racine.appendingPathComponent(modele).path) else { continue }
            parcourir(modele)
            var refs: [String: String] = [:]
            for nom in (try? fm.contentsOfDirectory(atPath: racine.appendingPathComponent(modele + "/refs").path)) ?? [] where !ignoree(nom) {
                let url = racine.appendingPathComponent(modele + "/refs/" + nom)
                guard let valeur = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                refs[nom] = valeur
                inv.marques[modele + "/refs/" + nom] = Marque(valeur: valeur, date: dateModification(url))
            }
            var instantanes: [String] = []
            let dossierInstantanes = racine.appendingPathComponent(modele + "/snapshots")
            for rev in (try? fm.contentsOfDirectory(atPath: dossierInstantanes.path)) ?? [] where !ignoree(rev) {
                if let fichiers = fichiersInstantane(dossierInstantanes.appendingPathComponent(rev)) {
                    instantanes.append(rev)
                    inv.ensemble.insert(depot + "@" + rev)
                    for f in fichiers { inv.ensemble.insert(depot + "@" + rev + ":" + f) }
                }
            }
            inv.modeles[depot] = (refs, instantanes)
        }
        // Le témoin des blobs partagés et celui du cache, s'il y a des blobs partagés.
        if inv.entrees.contains(where: { $0.chemin.hasPrefix("blobs/") }) {
            parcourir("blobs/.huggingface-shared-blobs")
        }
        parcourir("CACHEDIR.TAG")
        inv.taille = tailles.values.reduce(0, +)
        return inv
    }

    /// Un instantané complet : chaque lien qu'il porte mène à un fichier (aucun lien cassé), et il a au
    /// moins un fichier.
    static func instantaneComplet(_ dossier: URL) -> Bool { fichiersInstantane(dossier) != nil }

    /// Les fichiers d'un instantané (chemins relatifs), ou nil s'il a un lien cassé ou aucun fichier.
    /// Les fichiers qui manquent tout à fait (lien jamais posé) ne se voient pas ici : la comparaison
    /// les voit, car l'ensemble porte chaque fichier.
    static func fichiersInstantane(_ dossier: URL) -> [String]? {
        let fm = FileManager.default
        let base = dossier.standardizedFileURL.path
        guard let enumerateur = fm.enumerator(at: dossier, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { return nil }
        var fichiers: [String] = []
        for case let url as URL in enumerateur {
            guard !ignoree(url.lastPathComponent) else { continue }
            let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            let chemin = url.standardizedFileURL.path
            let relatif = chemin.hasPrefix(base + "/") ? String(chemin.dropFirst(base.count + 1)) : url.lastPathComponent
            if v?.isSymbolicLink == true {
                var estDossier: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &estDossier) else { return nil }
                if !estDossier.boolValue { fichiers.append(relatif) }
            } else if v?.isRegularFile == true {
                fichiers.append(relatif)
            }
        }
        return fichiers.isEmpty ? nil : fichiers.sorted()
    }

    /// Un dossier ordinaire (SAM 2) : ses entrées, l'ensemble des chemins des fichiers de ses
    /// .mlpackage (les .mlmodelc, compilés sur chaque Mac, se copient sans compter) et, avec
    /// `empreintes`, leurs marques (SHA-256 et date) : un nouvel export aux mêmes tailles se voit.
    public static func inventaireDossier(_ donne: URL, empreintes: Bool = false)
        -> (entrees: [Entree], ensemble: Set<String>, taille: Int64, marques: [String: Marque]) {
        let fm = FileManager.default
        // Le dossier lui-même peut être un lien (suivi) ; ce qu'il contient, non.
        let dossier = donne.resolvingSymlinksInPath()
        var entrees: [Entree] = [], ensemble = Set<String>(), taille: Int64 = 0, marques: [String: Marque] = [:]
        func parcourir(_ chemin: String) {
            let url = chemin.isEmpty ? dossier : dossier.appendingPathComponent(chemin)
            guard let a = try? fm.attributesOfItem(atPath: url.path), let type = a[.type] as? FileAttributeType else { return }
            switch type {
            case .typeDirectory:
                if !chemin.isEmpty { entrees.append(Entree(chemin: chemin, genre: .dossier)) }
                for nom in ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() where !ignoree(nom) {
                    parcourir(chemin.isEmpty ? nom : chemin + "/" + nom)
                }
            case .typeSymbolicLink:
                if let d = try? fm.destinationOfSymbolicLink(atPath: url.path) { entrees.append(Entree(chemin: chemin, genre: .lien(d))) }
            case .typeRegular:
                let t = (a[.size] as? NSNumber)?.int64Value ?? 0
                entrees.append(Entree(chemin: chemin, genre: .fichier(t)))
                taille += t
                if chemin.contains(".mlpackage/") {
                    ensemble.insert(chemin)
                    if empreintes, let sha = try? sha256(url) { marques[chemin] = Marque(valeur: sha, date: dateModification(url)) }
                }
            default: return
            }
        }
        parcourir("")
        return (entrees, ensemble, taille, marques)
    }

    // MARK: Outils

    /// Date de modification en secondes depuis 1970 (0 : illisible).
    public static func dateModification(_ url: URL) -> Double {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    public static func taille(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// La taille d'un dossier (fichiers ordinaires, sans suivre les liens).
    public static func tailleArbre(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    public static func sha256(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hash = SHA256()
        while let d = try h.read(upToCount: morceau), !d.isEmpty { hash.update(data: d) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func nomDeCetOrdinateur() -> String {
        let r = lancerProcessus(URL(fileURLWithPath: "/usr/sbin/scutil"), ["--get", "ComputerName"], nil, 5)
        let nom = r.sortie.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.code == 0 && !nom.isEmpty ? nom : (Host.current().localizedName ?? "Mac")
    }

    /// Fibo 2 Studio tourne-t-il ? (`pgrep -f` sur l'exécutable de l'application).
    public static func fiboStudioEnCours() -> Bool {
        lancerProcessus(URL(fileURLWithPath: "/usr/bin/pgrep"), ["-f", "Fibo 2 Studio.app/Contents/MacOS/"], nil, 5).code == 0
    }

    public static func placeLibreReelle(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    /// Le lanceur réel : sortie et erreurs mêlées, lues au fil de l'eau ; arrêt au délai.
    public static func lancerProcessus(_ executable: URL, _ arguments: [String], _ environnement: [String: String]?, _ delai: TimeInterval?) -> Resultat {
        let p = Process()
        p.executableURL = executable
        p.arguments = arguments
        if let environnement { p.environment = environnement }
        p.standardInput = FileHandle.nullDevice
        let tuyau = Pipe()
        p.standardOutput = tuyau
        p.standardError = tuyau
        let verrou = NSLock()
        var donnees = Data()
        tuyau.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            verrou.lock(); donnees.append(d)
            if donnees.count > 200_000 { donnees = donnees.suffix(100_000) }
            verrou.unlock()
        }
        do { try p.run() } catch {
            tuyau.fileHandleForReading.readabilityHandler = nil
            return Resultat(code: 127, sortie: error.localizedDescription)
        }
        if let delai {
            let fin = Date().addingTimeInterval(delai)
            while p.isRunning, Date() < fin { usleep(50_000) }
            if p.isRunning { p.terminate() }
        }
        p.waitUntilExit()
        tuyau.fileHandleForReading.readabilityHandler = nil
        let reste = (try? tuyau.fileHandleForReading.readToEnd()) ?? Data()
        verrou.lock(); donnees.append(reste); verrou.unlock()
        return Resultat(code: p.terminationStatus, sortie: String(decoding: donnees, as: UTF8.self))
    }
}

extension String {
    func trimmingSuffix(_ s: String) -> String { hasSuffix(s) ? String(dropLast(s.count)) : self }
}
