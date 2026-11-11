import Foundation

/// Les paramètres prédéfinis « Claude / Poussière » et « Claude / Imperfections » que Dany a créés
/// dans Lightroom Classic 16 (10 novembre 2026), lus en lecture seule par le serveur avant que
/// remove_distractions les applique (`dust`, `imperfections`).
///
/// Un module ne peut pas lancer Supprimer › Poussière ni › Imperfections (docs/SPEC.md, « Pas
/// d'accès pour un module ») ; un paramètre prédéfini qui les porte, si. Constaté dans Lightroom
/// 16.0 (docs/SPEC.md, Suppression des passants, constats du 10 novembre) :
/// - les filtres de Supprimer se rangent dans `crs:FilterList` : `FilterID` 3 reflets, 4 passants,
///   6 poussière, 7 imperfections ; chaque filtre rangé a `crs:CompressedSettings="<digest>"` et sa
///   recette codée dans `crs:Table_<digest>` du même fichier ;
/// - créé d'une photo sans la suppression faite, le paramètre ne range qu'un signal d'effacement
///   (`crs:IsSignalForDelete="true"`) : appliqué, il RETIRE la suppression au lieu de la faire ;
/// - un paramètre peut porter des signaux d'effacement d'autres filtres : appliqué, il effacerait
///   reflets, passants, poussière ou imperfections déjà faits.
/// Le module ne voit que le digest (getDevelopSettings), jamais la table : d'où cette lecture du
/// fichier par le serveur. Tout ce qui n'est pas le seul filtre voulu (autres filtres, autres
/// réglages) fait refuser : jamais retoucher autre chose sans le dire.
public enum PresetSuppression {
    /// Le groupe des paramètres prédéfinis de Dany (« Claude / Poussière »).
    public static let groupe = "Claude"

    public enum Genre: String, CaseIterable, Sendable {
        case poussiere, imperfections

        /// `FilterID` du filtre de Supprimer dans `crs:FilterList`.
        public var filterID: Int { self == .poussiere ? 6 : 7 }
        /// Le nom du paramètre prédéfini, dans le groupe « Claude ».
        public var nom: String { self == .poussiere ? "Poussière" : "Imperfections" }
        /// Le nom de l'étape par défaut (« Claude · poussière »).
        public var etape: String { self == .poussiere ? "poussière" : "imperfections" }
        /// « Claude / Poussière ».
        public var nomComplet: String { "\(PresetSuppression.groupe) / \(nom)" }
    }

    /// Les filtres de Supprimer, par `FilterID` (constaté dans Lightroom 16.0).
    static let filtresSupprimer: [Int: String] = [3: "les reflets", 4: "les passants", 6: "la poussière", 7: "les imperfections"]

    /// Les attributs de `rdf:Description` qui décrivent le paramètre prédéfini sans rien régler
    /// (relevés dans les fichiers de Lightroom 16.0). `ProcessVersion` est rangé même quand la case
    /// n'est pas cochée (constaté : « Poussière » et « Imperfections » de Dany, Supprimer seul coché).
    static let attributsDuParametre: Set<String> = [
        "PresetType", "Cluster", "UUID", "SupportsAmount2", "SupportsAmount", "SupportsColor", "SupportsMonochrome",
        "SupportsHighDynamicRange", "SupportsNormalDynamicRange", "SupportsSceneReferred", "SupportsOutputReferred",
        "RequiresRGBTables", "ShowInPresets", "ShowInQuickActions", "CameraModelRestriction", "Copyright", "ContactInfo",
        "Version", "CompatibleVersion", "ProcessVersion", "AllowFilters", "HasSettings",
    ]
    /// Les éléments de `rdf:Description` qui ne règlent rien (hors `FilterList`).
    static let elementsDuParametre: Set<String> = ["Name", "ShortName", "SortName", "Group", "Description", "FilterList"]

    public enum Etat: Equatable, Sendable {
        /// Le seul filtre voulu, sans signal d'effacement, avec sa recette : à appliquer par son UUID.
        case valide(uuid: String, fichier: URL)
        /// Aucun paramètre « Claude / <nom> » dans le dossier.
        case absent
        /// Le filtre voulu n'y est qu'un signal d'effacement : l'appliquer retirerait la suppression.
        case effacementSeul(fichier: URL)
        /// Le filtre voulu manque, ou sa recette (`crs:Table_<digest>`), ou l'UUID du fichier.
        case incomplet(fichier: URL, raison: String)
        /// D'autres filtres ou d'autres réglages : l'appliquer retoucherait autre chose.
        case dangereux(fichier: URL, raisons: [String])
        /// Plusieurs fichiers portent ce nom dans le groupe « Claude ».
        case plusieurs([URL])
    }

    /// Ce qu'un fichier .xmp de paramètre prédéfini contient, lu sans rien interpréter.
    struct Lecture {
        var attributs: [String: String] = [:]
        var elements: [String] = []
        var nom: String?
        var groupe: String?
        var filtres: [[String: String]] = []
    }

    /// Cherche « Claude / <nom> » dans `dossier` (et ses sous-dossiers), puis le juge.
    public static func chercher(_ genre: Genre, dans dossier: URL) -> Etat {
        var trouves: [(URL, Lecture)] = []
        let fm = FileManager.default
        guard let parcours = fm.enumerator(at: dossier, includingPropertiesForKeys: [.isRegularFileKey],
                                           options: [.skipsHiddenFiles]) else { return .absent }
        for case let url as URL in parcours where url.pathExtension.lowercased() == "xmp" {
            guard let lecture = lire(url), let groupe = lecture.groupe, let nom = lecture.nom,
                  plier(groupe) == plier(Self.groupe), plier(nom) == plier(genre.nom) else { continue }
            trouves.append((url, lecture))
        }
        if trouves.count > 1 {
            return .plusieurs(trouves.map(\.0).sorted { $0.path < $1.path })
        }
        guard let (url, lecture) = trouves.first else { return .absent }
        return juger(lecture, genre: genre, fichier: url)
    }

    /// Juge un fichier lu : valide, effacement seul, incomplet ou dangereux.
    static func juger(_ lecture: Lecture, genre: Genre, fichier: URL) -> Etat {
        var raisons: [String] = []
        // D'autres réglages que Supprimer.
        let reglages = lecture.attributs.keys
            .filter { !attributsDuParametre.contains($0) && !$0.hasPrefix("Table_") }
            + lecture.elements.filter { !elementsDuParametre.contains($0) }
        if !reglages.isEmpty {
            raisons.append("il règle aussi " + reglages.sorted().joined(separator: ", "))
        }
        // D'autres filtres, faits ou effacés.
        let voulus = lecture.filtres.filter { Int($0["FilterID"] ?? "") == genre.filterID }
        for filtre in lecture.filtres where Int(filtre["FilterID"] ?? "") != genre.filterID {
            let id = filtre["FilterID"] ?? "?"
            let quoi = Int(id).flatMap { filtresSupprimer[$0] } ?? "le filtre \(id)"
            raisons.append(signal(filtre) ? "il effacerait \(quoi) déjà faits" : "il ferait aussi \(quoi)")
        }
        if !raisons.isEmpty {
            return .dangereux(fichier: fichier, raisons: raisons)
        }
        guard !voulus.isEmpty else {
            return .incomplet(fichier: fichier, raison: "il ne porte pas Supprimer › \(genre.nom)")
        }
        // Exactement une entrée du filtre voulu : une suppression faite et un signal d'effacement
        // ensemble, Lightroom ne dit pas lequel l'emporte (revue du 11 novembre 2026).
        guard voulus.count == 1, let filtre = voulus.first else {
            return .incomplet(fichier: fichier, raison: "il porte \(voulus.count) fois Supprimer › \(genre.nom) (une seule attendue)")
        }
        guard !signal(filtre) else { return .effacementSeul(fichier: fichier) }
        guard let digest = filtre["CompressedSettings"], !digest.isEmpty,
              let table = lecture.attributs["Table_" + digest], !table.isEmpty else {
            return .incomplet(fichier: fichier, raison: "la recette de Supprimer › \(genre.nom) manque")
        }
        guard let uuid = lecture.attributs["UUID"]?.trimmingCharacters(in: .whitespaces), !uuid.isEmpty else {
            return .incomplet(fichier: fichier, raison: "il n'a pas d'identifiant (UUID)")
        }
        return .valide(uuid: uuid, fichier: fichier)
    }

    /// La version de processus que porte le fichier (`crs:ProcessVersion`, « 15.4 »), rangée même
    /// quand la case n'est pas cochée : appliquée, elle pourrait changer celle de la photo, donc son
    /// rendu (pas encore constaté) ; remove_distractions la compare d'abord à celle de la photo.
    public static func versionProcessus(_ fichier: URL) -> String? {
        guard let valeur = lire(fichier)?.attributs["ProcessVersion"]?.trimmingCharacters(in: .whitespaces),
              !valeur.isEmpty else { return nil }
        return valeur
    }

    static func signal(_ filtre: [String: String]) -> Bool {
        filtre["IsSignalForDelete"]?.lowercased() == "true"
    }

    /// Nom comparé sans casse, sans accents, sans espaces autour (« Poussiere » = « Poussière »).
    static func plier(_ texte: String) -> String {
        texte.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Lit un fichier .xmp (nil s'il est illisible ou trop gros pour un paramètre prédéfini).
    static func lire(_ url: URL) -> Lecture? {
        guard let taille = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, taille < 20_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        return lire(data)
    }

    static func lire(_ data: Data) -> Lecture? {
        let lecteur = Lecteur()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = lecteur
        guard parser.parse(), lecteur.vu else { return nil }
        return lecteur.lecture
    }

    /// Lecteur XML : le premier `rdf:Description`, ses attributs `crs:`, ses éléments, le texte de
    /// `crs:Name` et `crs:Group`, et les filtres de `crs:FilterList`.
    final class Lecteur: NSObject, XMLParserDelegate {
        var lecture = Lecture()
        var vu = false
        var pile: [String] = []
        var profondeurDescription: Int?
        var texte = ""

        static func local(_ nom: String) -> String {
            nom.split(separator: ":").last.map(String.init) ?? nom
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            pile.append(elementName)
            texte = ""
            if profondeurDescription == nil, elementName == "rdf:Description", !vu {
                vu = true
                profondeurDescription = pile.count
                for (cle, valeur) in attributes where cle.hasPrefix("crs:") {
                    lecture.attributs[Self.local(cle)] = valeur
                }
                return
            }
            guard let base = profondeurDescription else { return }
            if pile.count == base + 1 {
                lecture.elements.append(Self.local(elementName))
            }
            // Un filtre : rdf:li de crs:FilterList › crs:Filters › rdf:Seq.
            if elementName == "rdf:li", pile.count == base + 4,
               pile[base] == "crs:FilterList", pile[base + 1] == "crs:Filters" {
                var filtre: [String: String] = [:]
                for (cle, valeur) in attributes where cle.hasPrefix("crs:") {
                    filtre[Self.local(cle)] = valeur
                }
                lecture.filtres.append(filtre)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            texte += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if let base = profondeurDescription, elementName == "rdf:li", pile.count == base + 3 {
                switch pile[base] {
                case "crs:Name" where lecture.nom == nil: lecture.nom = texte
                case "crs:Group" where lecture.groupe == nil: lecture.groupe = texte
                default: break
                }
            }
            if let base = profondeurDescription, pile.count == base {
                profondeurDescription = nil
            }
            pile.removeLast()
            texte = ""
        }
    }
}
