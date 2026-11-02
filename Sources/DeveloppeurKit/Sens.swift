import CoreGraphics
import CoreML
import CryptoKit
import Foundation
import Vision

/// Un encodeur d'images et de textes dans le même espace (recherche par le sens, 1.6) : MobileCLIP S2
/// sur ce Mac (`EncodeurMobileCLIP`), ou un faux dans les essais. Les vecteurs rendus sont de norme 1.
public protocol EncodeurSens: AnyObject {
    /// Le nom du modèle, rangé dans l'index : un index d'un autre modèle ne se lit pas.
    var modele: String { get }
    var dimension: Int { get }
    func vecteur(image: CGImage) throws -> [Float]
    func vecteur(texte: String) throws -> [Float]
}

/// La recherche par le sens (1.6, chantier « sens ») : MobileCLIP S2 (CoreML, sur ce Mac, licence
/// apple-ascl, usage personnel accepté par Dany) calcule une empreinte de 512 nombres par vignette
/// pendant l'analyse du Suivi (`--analyser`, Suivi.swift), rangée dans un index par catalogue
/// (IndexSens.swift) ; find_photos (`query`, `similar_to`) y classe les photos. Aucune image ne part
/// chez Claude : il reçoit des identifiants et une pertinence. Ni espèces ni BioCLIP (1.6.1).
public enum Sens {
    /// La version des règles de l'empreinte : le module la range dans `analyse.regles_sens`, et une
    /// réponse de règles plus récentes fait refaire l'empreinte (une autre découpe, un autre modèle).
    public static let regles = 1
    public static let nomModele = "MobileCLIP-S2"
    /// Pertinence relative en dessous de laquelle une photo ne sort pas d'une recherche par le sens
    /// (0 : le score médian de l'index, 1 : le meilleur). PROVISOIRE : à relever par
    /// `--sens-essai` sur les photos de Dany (docs/SPEC.md, À constater).
    public static let seuilPertinenceProvisoire = 0.5
    /// Les photos les mieux classées qui passent au module pour les autres critères (MAX_TRI du module,
    /// au-delà duquel il refuse de filtrer après coup les dates, la focale ou les copies).
    public static let candidatsMax = 5000
    /// Les tranches de `candidatsMax` candidates qu'une recherche lit au plus (50 000 photos) pour
    /// remplir une page quand les autres critères (collection, mot-clé, note…) en écartent beaucoup.
    /// PROVISOIRE : le temps d'une tranche dans le module est à relever (docs/SPEC.md, À constater).
    public static let tranchesMax = 10

    // MARK: Fichiers

    /// Les fichiers du modèle : les deux encodeurs (.mlpackage à compiler, ou .mlmodelc déjà compilé)
    /// et le vocabulaire du tokeniseur.
    public struct Fichiers: Equatable {
        public var image: URL
        public var texte: URL
        public var vocabulaire: URL
        /// Où ranger les modèles compilés (Developpeur/Modeles).
        public var modeles: URL

        /// L'encodeur d'images est déjà compilé (.mlmodelc) : le Suivi peut l'ouvrir sous son délai.
        /// Un .mlpackage se compile d'abord par `--compiler-sens` (install.sh, ou le Suivi une fois par
        /// séance, sous sa propre alarme), jamais dans `--analyser`.
        public var imageCompilee: Bool { image.pathExtension != "mlpackage" }
    }

    /// Developpeur/Modeles : les modèles compilés et le vocabulaire.
    public static var dossierModeles: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Developpeur/Modeles", isDirectory: true)
    }

    /// Le cache de Hugging Face où `hf download apple/coreml-mobileclip` range les modèles.
    public static var cacheHuggingFace: URL {
        let env = ProcessInfo.processInfo.environment
        if let hub = env["HF_HUB_CACHE"], !hub.isEmpty { return URL(fileURLWithPath: hub, isDirectory: true) }
        if let home = env["HF_HOME"], !home.isEmpty { return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("hub") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    /// Les fichiers trouvés : dans `modeles` (compilés, `mobileclip_s2_image.mlmodelc`), sinon les
    /// .mlpackage du cache de Hugging Face (le dernier instantané) ; nil si un manque, avec la liste
    /// de ce qui manque.
    public static func trouver(modeles: URL = dossierModeles, cache: URL = cacheHuggingFace) -> (fichiers: Fichiers?, manquants: [String]) {
        let fm = FileManager.default
        func existe(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
        let instantanes = cache.appendingPathComponent("models--apple--coreml-mobileclip/snapshots", isDirectory: true)
        let dossiers = ((try? fm.contentsOfDirectory(at: instantanes, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
        func encodeur(_ nom: String) -> URL? {
            let compile = modeles.appendingPathComponent("\(nom).mlmodelc", isDirectory: true)
            if existe(compile) { return compile }
            for dossier in dossiers {
                let paquet = dossier.appendingPathComponent("\(nom).mlpackage", isDirectory: true)
                if existe(paquet) { return paquet }
            }
            return nil
        }
        var manquants: [String] = []
        let image = encodeur("mobileclip_s2_image")
        let texte = encodeur("mobileclip_s2_text")
        let vocabulaire = modeles.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz")
        if image == nil { manquants.append("mobileclip_s2_image.mlpackage (hf download apple/coreml-mobileclip)") }
        if texte == nil { manquants.append("mobileclip_s2_text.mlpackage (hf download apple/coreml-mobileclip)") }
        if !existe(vocabulaire) { manquants.append("\(vocabulaire.path) (vocabulaire de CLIP, copié par l'installation)") }
        guard let image, let texte, manquants.isEmpty else { return (nil, manquants) }
        return (Fichiers(image: image, texte: texte, vocabulaire: vocabulaire, modeles: modeles), [])
    }

    // MARK: Calcul

    /// Le vecteur ramené à la norme 1 (vide ou nul : tel quel).
    public static func normaliser(_ v: [Float]) -> [Float] {
        let norme = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norme > 0, norme.isFinite else { return v }
        return v.map { $0 / norme }
    }

    /// L'empreinte du chemin d'un catalogue (le dossier de son index).
    public static func empreinte(catalogue: String) -> String {
        SHA256.hash(data: Data(catalogue.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24).description
    }

    /// Developpeur/Index : un dossier par catalogue, sous l'empreinte de son chemin.
    public static var racineIndex: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Developpeur/Index", isDirectory: true)
    }
}

/// MobileCLIP S2 en CoreML : l'encodeur d'images (entrée `image`, 256 × 256, découpe centrale par
/// CoreML d'après sa contrainte) et l'encodeur de texte (entrée `text`, 77 jetons du tokeniseur de
/// CLIP) ; sortie `final_emb_1` (512 nombres), ramenée à la norme 1. Les noms et tailles se lisent
/// dans la description du modèle : aucun n'est écrit en dur, sauf en repli. Un .mlpackage se compile
/// au premier usage (`MLModel.compileModel`), la copie compilée rangée dans Developpeur/Modeles (à
/// constater sous le runtime durci : `--preparer-sens`). Jamais dans `swift test`.
public final class EncodeurMobileCLIP: EncodeurSens {
    public let modele = Sens.nomModele
    public private(set) var dimension: Int
    let encodeurImage: MLModel
    /// Le temps des compilations faites (0 : déjà compilés), pour `--preparer-sens`.
    public private(set) var secondesDeCompilation: Double = 0
    private let verrou = NSLock()

    public enum Erreur: Error, LocalizedError {
        case modele(String)
        public var errorDescription: String? {
            switch self { case .modele(let detail): return "MobileCLIP : \(detail)" }
        }
    }

    /// L'encodeur d'images s'ouvre tout de suite ; celui de texte et le tokeniseur au premier texte
    /// (`--analyser`, lancé à chaque lot du Suivi, n'en a pas besoin).
    public init(fichiers: Sens.Fichiers) throws {
        self.fichiers = fichiers
        let debut = Date()
        let image = try Self.compile(fichiers.image, dans: fichiers.modeles)
        encodeurImage = try MLModel(contentsOf: image, configuration: Self.configuration)
        dimension = encodeurImage.modelDescription.outputDescriptionsByName.values.first?.multiArrayConstraint?.shape.last?.intValue ?? 512
        if fichiers.image.pathExtension == "mlpackage" { secondesDeCompilation = Date().timeIntervalSince(debut) }
    }

    let fichiers: Sens.Fichiers
    private var texteOuvert: (modele: MLModel, tokeniseur: TokeniseurCLIP)?

    static var configuration: MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }

    /// L'encodeur de texte et le tokeniseur, ouverts une fois (sous le verrou).
    private func texte() throws -> (modele: MLModel, tokeniseur: TokeniseurCLIP) {
        if let texteOuvert { return texteOuvert }
        let debut = Date()
        let url = try Self.compile(fichiers.texte, dans: fichiers.modeles)
        let ouvert = (try MLModel(contentsOf: url, configuration: Self.configuration), try TokeniseurCLIP(vocabulaire: fichiers.vocabulaire))
        if fichiers.texte.pathExtension == "mlpackage" { secondesDeCompilation += Date().timeIntervalSince(debut) }
        texteOuvert = ouvert
        return ouvert
    }

    /// Le modèle compilé : un .mlmodelc tel quel ; un .mlpackage compilé, puis rangé d'un coup sous
    /// son nom dans `dossier` (un processus arrêté pendant la compilation ne laisse rien à moitié).
    static func compile(_ url: URL, dans dossier: URL) throws -> URL {
        guard url.pathExtension == "mlpackage" else { return url }
        let fm = FileManager.default
        let cible = dossier.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".mlmodelc", isDirectory: true)
        if fm.fileExists(atPath: cible.path) { return cible }
        let copie = try sansLiens(url)
        defer { try? fm.removeItem(at: copie.deletingLastPathComponent()) }
        let compile = try MLModel.compileModel(at: copie)
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        let provisoire = dossier.appendingPathComponent(".\(cible.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: provisoire)
        try fm.moveItem(at: compile, to: provisoire)
        if fm.fileExists(atPath: cible.path) {
            try? fm.removeItem(at: provisoire)
        } else {
            try fm.moveItem(at: provisoire, to: cible)
        }
        return cible
    }

    /// Une copie du paquet, liens symboliques résolus, dans un dossier temporaire à effacer. Le cache
    /// de Hugging Face range weight.bin en lien vers ses blobs : `compileModel` le refuse alors
    /// (« weight.bin doesn't exist », constaté le 2 nov. 2026 sous le runtime durci).
    static func sansLiens(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let copie = fm.temporaryDirectory
            .appendingPathComponent("developpeur-sens-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(url.lastPathComponent, isDirectory: true)
        try fm.createDirectory(at: copie, withIntermediateDirectories: true)
        for relatif in fm.subpaths(atPath: url.path) ?? [] {
            let source = url.appendingPathComponent(relatif)
            let cible = copie.appendingPathComponent(relatif)
            var dossier: ObjCBool = false
            guard fm.fileExists(atPath: source.path, isDirectory: &dossier) else { continue }
            if dossier.boolValue {
                try fm.createDirectory(at: cible, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: cible.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: source.resolvingSymlinksInPath(), to: cible)
            }
        }
        return copie
    }

    /// Compile les deux encodeurs dans Developpeur/Modeles (rien si c'est déjà fait) ; le temps pris.
    /// `--compiler-sens` seulement (install.sh, le Suivi sous sa propre alarme), jamais `swift test`.
    public static func compiler(_ fichiers: Sens.Fichiers) throws -> Double {
        let debut = Date()
        _ = try compile(fichiers.image, dans: fichiers.modeles)
        _ = try compile(fichiers.texte, dans: fichiers.modeles)
        return Date().timeIntervalSince(debut)
    }

    /// Ce que disent les deux modèles (noms, types, formes), pour `--preparer-sens`.
    public var description: JSONValue {
        func decrire(_ m: MLModel) -> JSONValue {
            func f(_ d: MLFeatureDescription) -> JSONValue {
                var o: [String: JSONValue] = ["nom": .string(d.name), "type": .number(Double(d.type.rawValue))]
                if let c = d.imageConstraint { o["image"] = ["largeur": .number(Double(c.pixelsWide)), "hauteur": .number(Double(c.pixelsHigh))] }
                if let c = d.multiArrayConstraint {
                    o["forme"] = .array(c.shape.map { .number($0.doubleValue) })
                    o["donnees"] = .number(Double(c.dataType.rawValue))
                }
                return .object(o)
            }
            return ["entrees": .array(m.modelDescription.inputDescriptionsByName.values.map(f)),
                    "sorties": .array(m.modelDescription.outputDescriptionsByName.values.map(f))]
        }
        verrou.lock(); defer { verrou.unlock() }
        let texte: JSONValue = (try? self.texte()).map { decrire($0.modele) } ?? "illisible"
        return ["image": decrire(encodeurImage), "texte": texte, "dimension": .number(Double(dimension))]
    }

    public func vecteur(image: CGImage) throws -> [Float] {
        verrou.lock(); defer { verrou.unlock() }
        guard let entree = encodeurImage.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
              let contrainte = entree.imageConstraint else {
            throw Erreur.modele("l'encodeur d'images n'a pas d'entrée image.")
        }
        let valeur = try MLFeatureValue(cgImage: image, constraint: contrainte,
                                        options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue])
        let sortie = try encodeurImage.prediction(from: MLDictionaryFeatureProvider(dictionary: [entree.name: valeur]))
        return try Self.lire(sortie, encodeurImage)
    }

    public func vecteur(texte: String) throws -> [Float] {
        verrou.lock(); defer { verrou.unlock() }
        let (encodeurTexte, tokeniseur) = try self.texte()
        guard let entree = encodeurTexte.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .multiArray }),
              let contrainte = entree.multiArrayConstraint else {
            throw Erreur.modele("l'encodeur de texte n'a pas d'entrée de jetons.")
        }
        let jetons = tokeniseur.jetons(texte)
        let forme = contrainte.shape.isEmpty ? [1, NSNumber(value: TokeniseurCLIP.longueur)] : contrainte.shape
        let tableau = try MLMultiArray(shape: forme, dataType: contrainte.dataType == .int32 ? .int32 : contrainte.dataType)
        for i in 0..<min(tableau.count, jetons.count) { tableau[i] = NSNumber(value: jetons[i]) }
        let sortie = try encodeurTexte.prediction(from: MLDictionaryFeatureProvider(dictionary: [entree.name: MLFeatureValue(multiArray: tableau)]))
        return try Self.lire(sortie, encodeurTexte)
    }

    /// La première sortie en tableau de nombres, ramenée à la norme 1.
    static func lire(_ sortie: MLFeatureProvider, _ modele: MLModel) throws -> [Float] {
        let nom = modele.modelDescription.outputDescriptionsByName.keys.sorted().first ?? "final_emb_1"
        guard let tableau = sortie.featureValue(for: nom)?.multiArrayValue else { throw Erreur.modele("pas de sortie « \(nom) ».") }
        var v = [Float](repeating: 0, count: tableau.count)
        for i in 0..<tableau.count { v[i] = tableau[i].floatValue }
        return Sens.normaliser(v)
    }
}
