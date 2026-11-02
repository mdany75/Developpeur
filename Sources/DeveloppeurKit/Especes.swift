import Accelerate
import CoreGraphics
import CryptoKit
import Foundation

/// Une entrée de la liste des espèces (Resources/especes/especes.tsv) : son groupe (« oiseau »,
/// « fleur »…), son nom français courant et son nom scientifique (genre espèce).
public struct Espece: Equatable {
    public var groupe: String
    public var nom: String
    public var latin: String

    public init(groupe: String, nom: String, latin: String) {
        self.groupe = groupe
        self.nom = nom
        self.latin = latin
    }
}

/// Les espèces (1.6.3) : BioCLIP 2 (imageomics, licence MIT), converti en CoreML par
/// scripts/preparer-bioclip.sh, reconnaît un oiseau, un animal, une fleur, un arbre ou un champignon
/// parmi la liste « Amérique du Nord et voyages » (Resources/especes/especes.tsv). Les vecteurs de
/// texte de toute la liste se calculent une fois et se gardent (`vecteursTexte`) ; une image se classe
/// par le produit avec eux, ramené en probabilités (softmax, `echelleLogits`). Tout reste sur ce Mac :
/// aucune image ne part. find_photos (`species`) et view_photo (`species`) s'en servent
/// (Tools+Especes.swift) ; sans le modèle, tout marche comme avant et get_status le dit.
public enum Especes {
    public static let nomModele = "BioCLIP-2"
    /// La phrase de chaque espèce pour l'encodeur de texte : le nom scientifique, comme la fiche de
    /// BioCLIP (classement zéro-coup par les noms d'espèces) et ses essais (« a photo of … »).
    public static func phrase(_ espece: Espece) -> String { "a photo of \(espece.latin)." }
    /// La porte « animal ou plante ? » : BioCLIP 2 ne sait pas dire qu'une image ne montre rien de
    /// vivant (constaté le 2 nov. 2026 : une capture d'écran a un cosinus de 0,66 avec « a photo of
    /// Coturnix coturnix. » et de 0,47 avec « a screenshot » ; les oiseaux, le quart de la liste,
    /// y prenaient plus de 0,5). MobileCLIP, un CLIP général, classe donc d'abord l'image entre ces
    /// phrases (softmax, échelle 100) ; la part des phrases de `porteNature` doit passer
    /// `seuilPorteProvisoire`. Sans MobileCLIP, pas de porte : find_photos et view_photo le disent
    /// (`porte` faux et une remarque, `ToolHandler.remarqueSansPorte`).
    public static let porteNature = [
        "a photo of a bird", "a photo of an animal", "a photo of an insect", "a photo of a butterfly", "a photo of a fish",
        "a photo of a reptile", "a photo of a frog", "a photo of a flower", "a photo of a plant", "a photo of a tree",
        "a photo of a mushroom",
    ]
    public static let porteAutre = [
        "a photo of a person", "a photo of people", "a photo of a building", "a photo of a city street", "a photo of a landscape",
        "a photo of the sky", "a photo of the sea", "a photo of a room", "a photo of food", "a photo of a car", "a screenshot",
        "a photo of a document", "a photo of an object",
    ]
    /// PROVISOIRE, comme les autres seuils (`--especes-essai`).
    public static let seuilPorteProvisoire = 0.5
    /// `logit_scale.exp()` de BioCLIP 2, relu par scripts/preparer-bioclip.sh (2 nov. 2026 : 100).
    public static let echelleLogits: Float = 100
    /// La confiance (probabilité parmi toute la liste) au-dessus de laquelle l'espèce d'une photo se
    /// dit. PROVISOIRE : à relever sur les photos de Dany (`--especes-essai`, docs/SPEC.md, À constater).
    public static let seuilConfianceProvisoire = 0.5
    /// La probabilité de l'espèce cherchée au-dessus de laquelle une photo sort de find_photos
    /// (`species`). PROVISOIRE, comme le seuil de confiance.
    public static let seuilRechercheProvisoire = 0.15
    /// La probabilité du groupe (somme de ses espèces) au-dessus de laquelle une photo sort d'une
    /// recherche par groupe (« oiseau »). PROVISOIRE.
    public static let seuilGroupeProvisoire = 0.5
    /// Les photos examinées au plus par une recherche (leurs vignettes, classées une à une).
    public static let candidatsMax = 200
    /// La taille des vignettes demandées au module (BioCLIP lit 224 × 224, découpe centrale).
    public static let tailleVignette = 512

    // MARK: Groupes

    /// Un groupe de la liste, ses autres noms (français et anglais, pluriels) et la phrase anglaise
    /// qui le cherche dans l'index du sens (MobileCLIP), avec d'autres au besoin : un groupe disparate
    /// (« invertébré » : crabes, escargots, vers, insectes) se cherche par la meilleure de ses phrases.
    public struct Groupe: Equatable {
        public var nom: String
        public var alias: [String]
        public var phrase: String
        /// Les groupes de la liste qu'il réunit (« plante » : fleur, arbre, arbuste, plante).
        public var membres: [String]
        public var autresPhrases: [String] = []
        /// Les phrases qui le cherchent dans l'index du sens : une photo y vaut son meilleur score.
        public var phrases: [String] { [phrase] + autresPhrases }
    }

    /// Les groupes de base, ceux qu'une ligne de la liste peut porter.
    public static let groupesDeBase = ["oiseau", "mammifère", "reptile", "amphibien", "poisson", "papillon", "insecte", "araignée",
                                       "invertébré", "fleur", "arbre", "arbuste", "champignon", "plante"]

    public static let groupes: [Groupe] = [
        Groupe(nom: "oiseau", alias: ["oiseaux", "bird", "birds"], phrase: "a photo of a bird", membres: ["oiseau"]),
        Groupe(nom: "mammifère", alias: ["mammifères", "mammal", "mammals"], phrase: "a photo of a mammal", membres: ["mammifère"]),
        Groupe(nom: "reptile", alias: ["reptiles"], phrase: "a photo of a reptile", membres: ["reptile"]),
        Groupe(nom: "amphibien", alias: ["amphibiens", "amphibian", "amphibians", "grenouille", "frog"], phrase: "a photo of a frog", membres: ["amphibien"]),
        Groupe(nom: "poisson", alias: ["poissons", "fish"], phrase: "a photo of a fish", membres: ["poisson"]),
        Groupe(nom: "papillon", alias: ["papillons", "butterfly", "butterflies", "moth"], phrase: "a photo of a butterfly", membres: ["papillon"]),
        Groupe(nom: "insecte", alias: ["insectes", "insect", "insects"], phrase: "a photo of an insect", membres: ["insecte", "papillon"]),
        Groupe(nom: "araignée", alias: ["araignées", "spider", "spiders"], phrase: "a photo of a spider", membres: ["araignée"]),
        // Invertébré de base : la mer (crabes, coquillages, méduses), mais aussi escargots, limaces,
        // vers, mille-pattes, scorpions, tiques ; le groupe réunit en plus insectes et araignées.
        Groupe(nom: "invertébré", alias: ["invertébrés", "invertebrate", "invertebrates"], phrase: "a photo of a sea creature",
               membres: ["invertébré", "insecte", "papillon", "araignée"],
               autresPhrases: ["a photo of a snail", "a photo of a slug", "a photo of a worm", "a photo of a centipede",
                               "a photo of a scorpion", "a photo of an insect", "a photo of a spider"]),
        Groupe(nom: "fleur", alias: ["fleurs", "flower", "flowers"], phrase: "a photo of a flower", membres: ["fleur"]),
        Groupe(nom: "arbre", alias: ["arbres", "tree", "trees"], phrase: "a photo of a tree", membres: ["arbre"]),
        Groupe(nom: "arbuste", alias: ["arbustes", "shrub", "shrubs", "bush"], phrase: "a photo of a shrub", membres: ["arbuste"]),
        Groupe(nom: "champignon", alias: ["champignons", "mushroom", "mushrooms", "fungus"], phrase: "a photo of a mushroom", membres: ["champignon"]),
        Groupe(nom: "plante", alias: ["plantes", "plant", "plants", "végétal"], phrase: "a photo of a plant",
               membres: ["plante", "fleur", "arbre", "arbuste"], autresPhrases: ["a photo of a flower", "a photo of a tree"]),
        Groupe(nom: "animal", alias: ["animaux", "animals", "faune", "wildlife"], phrase: "a photo of an animal",
               membres: ["oiseau", "mammifère", "reptile", "amphibien", "poisson", "papillon", "insecte", "araignée", "invertébré"],
               autresPhrases: ["a photo of a bird", "a photo of a fish", "a photo of an insect", "a photo of a sea creature"]),
    ]

    /// Le groupe d'une ligne de la liste.
    public static func groupe(nom: String) -> Groupe? { groupes.first { $0.nom == nom } }

    /// Un nom ramené à sa forme de comparaison : minuscules, sans accents, apostrophes et espaces
    /// uniformes (« Mésange à tête noire » = « mesange a tete noire »).
    public static func cle(_ texte: String) -> String {
        let plie = texte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_CA"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
        return plie.split(whereSeparator: { $0.isWhitespace || $0 == "-" }).joined(separator: " ")
    }

    // MARK: Liste

    /// La liste lue (TSV : groupe, nom français, nom scientifique ; « # » commente) et son empreinte.
    public struct Liste {
        public let especes: [Espece]
        public let empreinte: String
        private let parCle: [String: Int]

        public enum Erreur: Error, LocalizedError {
            case ligne(Int, String)
            public var errorDescription: String? {
                switch self { case .ligne(let n, let detail): return "Liste des espèces, ligne \(n) : \(detail)" }
            }
        }

        public init(contenu: String) throws {
            var especes: [Espece] = []
            for (i, brute) in contenu.components(separatedBy: "\n").enumerated() {
                let ligne = brute.trimmingCharacters(in: .whitespacesAndNewlines)
                if ligne.isEmpty || ligne.hasPrefix("#") { continue }
                let champs = ligne.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
                guard champs.count == 3, champs.allSatisfy({ !$0.isEmpty }) else {
                    throw Erreur.ligne(i + 1, "trois champs attendus (groupe, nom français, nom scientifique).")
                }
                guard Especes.groupesDeBase.contains(champs[0]) else { throw Erreur.ligne(i + 1, "groupe inconnu « \(champs[0]) ».") }
                especes.append(Espece(groupe: champs[0], nom: champs[1], latin: champs[2]))
            }
            self.especes = especes
            empreinte = SHA256.hash(data: Data(contenu.utf8)).map { String(format: "%02x", $0) }.joined()
            var parCle: [String: Int] = [:]
            for (i, e) in especes.enumerated() {
                for nom in [e.latin, e.nom] where parCle[Especes.cle(nom)] == nil { parCle[Especes.cle(nom)] = i }
            }
            self.parCle = parCle
        }

        public init(fichier: URL) throws {
            try self.init(contenu: String(contentsOf: fichier, encoding: .utf8))
        }

        /// Ce que demande « species » : une espèce (son nom français ou scientifique) d'abord, sinon
        /// un groupe (son nom ou un de ses autres noms) ; nil si rien ne correspond.
        public func resoudre(_ demande: String) -> Cible? {
            let c = Especes.cle(demande)
            if let i = parCle[c] { return .espece(i) }
            if let g = Especes.groupes.first(where: { Especes.cle($0.nom) == c || $0.alias.contains { Especes.cle($0) == c } }) {
                return .groupe(g)
            }
            return nil
        }

        /// Des noms proches d'une demande inconnue (qui la contiennent), pour le refus.
        public func suggestions(_ demande: String, nombre: Int = 5) -> [String] {
            let c = Especes.cle(demande)
            guard c.count >= 3 else { return [] }
            return especes.filter { Especes.cle($0.nom).contains(c) || Especes.cle($0.latin).contains(c) }
                .prefix(nombre).map { "\($0.nom) (\($0.latin))" }
        }

        /// Les indices des espèces d'un groupe.
        public func indices(_ groupe: Groupe) -> [Int] {
            especes.indices.filter { groupe.membres.contains(especes[$0].groupe) }
        }
    }

    public enum Cible: Equatable {
        case espece(Int)
        case groupe(Groupe)
    }

    // MARK: Fichiers

    /// Les fichiers des espèces : les deux encodeurs compilés par scripts/preparer-bioclip.sh, le
    /// vocabulaire de CLIP (le même tokeniseur que MobileCLIP) et la liste, copiée par l'installation.
    public struct Fichiers: Equatable {
        public var image: URL
        public var texte: URL
        public var vocabulaire: URL
        public var liste: URL
        public var modeles: URL
        /// Le fichier des vecteurs de texte de la liste, gardés.
        public var cache: URL { modeles.appendingPathComponent("bioclip2_especes.cache") }
        /// Pour l'encodeur commun (EncodeurMobileCLIP).
        public var sens: Sens.Fichiers { Sens.Fichiers(image: image, texte: texte, vocabulaire: vocabulaire, modeles: modeles) }
    }

    /// Les fichiers trouvés dans Developpeur/Modeles ; nil si un manque, avec la liste de ce qui manque.
    public static func trouver(modeles: URL = Sens.dossierModeles) -> (fichiers: Fichiers?, manquants: [String]) {
        let fm = FileManager.default
        let image = modeles.appendingPathComponent("bioclip2_image.mlmodelc", isDirectory: true)
        let texte = modeles.appendingPathComponent("bioclip2_text.mlmodelc", isDirectory: true)
        let vocabulaire = modeles.appendingPathComponent("bpe_simple_vocab_16e6.txt.gz")
        let liste = modeles.appendingPathComponent("especes.tsv")
        var manquants: [String] = []
        if !fm.fileExists(atPath: image.path) { manquants.append("bioclip2_image.mlmodelc (scripts/preparer-bioclip.sh)") }
        if !fm.fileExists(atPath: texte.path) { manquants.append("bioclip2_text.mlmodelc (scripts/preparer-bioclip.sh)") }
        if !fm.fileExists(atPath: vocabulaire.path) { manquants.append("bpe_simple_vocab_16e6.txt.gz (vocabulaire de CLIP, copié par l'installation)") }
        if !fm.fileExists(atPath: liste.path) { manquants.append("especes.tsv (liste des espèces, copiée par l'installation)") }
        guard manquants.isEmpty else { return (nil, manquants) }
        return (Fichiers(image: image, texte: texte, vocabulaire: vocabulaire, liste: liste, modeles: modeles), [])
    }

    /// L'empreinte d'un modèle compilé : la taille et la date de chacun de ses fichiers (un modèle
    /// refait par scripts/preparer-bioclip.sh en change).
    public static func empreinteModele(_ dossier: URL) -> String {
        let fm = FileManager.default
        var parties: [String] = []
        for relatif in (fm.subpaths(atPath: dossier.path) ?? []).sorted() {
            guard let a = try? fm.attributesOfItem(atPath: dossier.appendingPathComponent(relatif).path),
                  a[.type] as? FileAttributeType == .typeRegular else { continue }
            let taille = (a[.size] as? NSNumber)?.int64Value ?? 0
            let date = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parties.append("\(relatif):\(taille):\(Int(date))")
        }
        return SHA256.hash(data: Data(parties.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Vecteurs de texte gardés

    /// Les vecteurs de texte de toute la liste (`n × dimension`, chacun de norme 1) : relus dans
    /// `cache` si sa clé est la même (liste, phrase, modèle), sinon calculés puis gardés (écrits d'un
    /// coup : un processus arrêté ne laisse rien à moitié). Une ligne JSON d'en-tête, puis les nombres
    /// en 16 bits.
    public static func vecteursTexte(liste: Liste, encodeur: EncodeurSens, cache: URL, empreinteModele: String,
                                     avancement: ((Int, Int) -> Void)? = nil) throws -> (matrice: [Float], depuisLeCache: Bool) {
        let phrases = liste.especes.map(phrase)
        let cle = SHA256.hash(data: Data("\(liste.empreinte)|\(phrase(Espece(groupe: "", nom: "", latin: "X")))|\(encodeur.modele)|\(empreinteModele)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let d = encodeur.dimension, n = phrases.count
        if let lue = lireCache(cache, cle: cle, nombre: n, dimension: d) { return (lue, true) }
        var matrice = [Float]()
        matrice.reserveCapacity(n * d)
        for (i, texte) in phrases.enumerated() {
            let v = Sens.normaliser(try encodeur.vecteur(texte: texte))
            guard v.count == d else { throw EncodeurMobileCLIP.Erreur.modele("vecteur de texte de \(v.count) nombres, \(d) attendus.") }
            matrice += v
            if i % 250 == 249 { avancement?(i + 1, n) }
        }
        try? ecrireCache(cache, cle: cle, nombre: n, dimension: d, matrice: matrice)
        return (matrice, false)
    }

    static func lireCache(_ url: URL, cle: String, nombre: Int, dimension: Int) -> [Float]? {
        guard let data = try? Data(contentsOf: url), let fin = data.firstIndex(of: 0x0A),
              let entete = try? JSONCoding.parse(String(decoding: data[data.startIndex..<fin], as: UTF8.self)),
              entete["cle"]?.string == cle, entete["nombre"]?.int == nombre, entete["dimension"]?.int == dimension else { return nil }
        let corps = data[(fin + 1)...]
        guard corps.count == nombre * dimension * 2 else { return nil }
        var demi = [UInt16](repeating: 0, count: nombre * dimension)
        _ = demi.withUnsafeMutableBytes { corps.copyBytes(to: $0) }
        return demi.map { Float(Float16(bitPattern: UInt16(littleEndian: $0))) }
    }

    static func ecrireCache(_ url: URL, cle: String, nombre: Int, dimension: Int, matrice: [Float]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(JSONCoding.line(["cle": .string(cle), "nombre": .number(Double(nombre)), "dimension": .number(Double(dimension)),
                                         "modele": .string(nomModele)]).utf8)
        data.append(0x0A)
        let demi = matrice.map { Float16($0).bitPattern.littleEndian }
        demi.withUnsafeBytes { data.append(contentsOf: $0) }
        let provisoire = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: provisoire)
        _ = try? fm.removeItem(at: url)
        try fm.moveItem(at: provisoire, to: url)
    }
}

/// Le classement d'une image parmi la liste : l'encodeur (BioCLIP 2, ou un faux dans les essais) et
/// les vecteurs de texte de la liste.
public final class ClasseurEspeces {
    public let liste: Especes.Liste
    let encodeur: EncodeurSens
    /// La porte « animal ou plante ? » (MobileCLIP) ; nil : pas de porte.
    let porte: EncodeurSens?
    private var vecteursPorte: [[Float]]?
    let matrice: [Float]
    public let dimension: Int
    public var aUnePorte: Bool { porte != nil }
    /// Les vecteurs de texte venaient du fichier gardé (faux : calculés à l'ouverture).
    public let depuisLeCache: Bool

    public init(liste: Especes.Liste, encodeur: EncodeurSens, matrice: [Float], depuisLeCache: Bool = false, porte: EncodeurSens? = nil) {
        self.liste = liste
        self.encodeur = encodeur
        self.porte = porte
        self.matrice = matrice
        dimension = encodeur.dimension
        self.depuisLeCache = depuisLeCache
    }

    /// Ouvre le classeur : la liste lue, les vecteurs de texte relus ou calculés (`Especes.vecteursTexte`).
    public static func ouvrir(liste: Especes.Liste, encodeur: EncodeurSens, cache: URL, empreinteModele: String, porte: EncodeurSens? = nil,
                              avancement: ((Int, Int) -> Void)? = nil) throws -> ClasseurEspeces {
        let (matrice, lue) = try Especes.vecteursTexte(liste: liste, encodeur: encodeur, cache: cache, empreinteModele: empreinteModele,
                                                       avancement: avancement)
        return ClasseurEspeces(liste: liste, encodeur: encodeur, matrice: matrice, depuisLeCache: lue, porte: porte)
    }

    /// Les probabilités de chaque espèce de la liste (même ordre), qui font 1 ensemble, et la part
    /// « animal ou plante » de la porte (nil sans porte).
    public struct Resultat {
        public let probabilites: [Double]
        public var nature: Double?

        /// Les `k` espèces les plus probables (indice, probabilité), de la plus probable à la moins.
        public func meilleures(_ k: Int) -> [(indice: Int, probabilite: Double)] {
            probabilites.enumerated().sorted { $0.element > $1.element }.prefix(k).map { ($0.offset, $0.element) }
        }

        /// Faux si la porte a jugé que l'image ne montre ni animal ni plante.
        public var vivant: Bool { (nature ?? 1) >= Especes.seuilPorteProvisoire }

        /// La probabilité de plusieurs espèces ensemble (un groupe).
        public func somme(_ indices: [Int]) -> Double { indices.reduce(0) { $0 + probabilites[$1] } }
    }

    /// Le classement d'un vecteur d'image (de norme 1) : softmax de `echelleLogits` × cosinus.
    public func classer(vecteur: [Float]) -> Resultat {
        let n = liste.especes.count
        guard n > 0, vecteur.count == dimension, matrice.count == n * dimension else { return Resultat(probabilites: []) }
        var scores = [Float](repeating: 0, count: n)
        matrice.withUnsafeBufferPointer { m in
            vecteur.withUnsafeBufferPointer { v in
                scores.withUnsafeMutableBufferPointer { s in
                    vDSP_mmul(m.baseAddress!, 1, v.baseAddress!, 1, s.baseAddress!, 1, vDSP_Length(n), 1, vDSP_Length(dimension))
                }
            }
        }
        let logits = scores.map { Double($0 * Especes.echelleLogits) }
        let maximum = logits.max() ?? 0
        let exps = logits.map { exp($0 - maximum) }
        let total = exps.reduce(0, +)
        return Resultat(probabilites: exps.map { $0 / total })
    }

    /// L'image classée : la porte (MobileCLIP, si elle est là), puis BioCLIP 2.
    public func classer(image: CGImage) throws -> Resultat {
        var resultat = classer(vecteur: Sens.normaliser(try encodeur.vecteur(image: image)))
        resultat.nature = try nature(image)
        return resultat
    }

    /// La part « animal ou plante » de l'image d'après la porte ; nil sans porte.
    public func nature(_ image: CGImage) throws -> Double? {
        guard let porte else { return nil }
        if vecteursPorte == nil {
            vecteursPorte = try (Especes.porteNature + Especes.porteAutre).map { Sens.normaliser(try porte.vecteur(texte: $0)) }
        }
        guard let textes = vecteursPorte else { return nil }
        let v = Sens.normaliser(try porte.vecteur(image: image))
        let logits = textes.map { t in Double(zip(t, v).reduce(Float(0)) { $0 + $1.0 * $1.1 } * 100) }
        let maximum = logits.max() ?? 0
        let exps = logits.map { exp($0 - maximum) }
        return exps.prefix(Especes.porteNature.count).reduce(0, +) / exps.reduce(0, +)
    }

    /// L'espèce d'une photo, pour view_photo et find_photos : la plus probable si elle passe
    /// `seuil`, sinon `trouvee` faux et les plus proches, dites incertaines.
    public func json(_ resultat: Resultat, seuil: Double = Especes.seuilConfianceProvisoire) -> JSONValue {
        let meilleures = resultat.meilleures(3)
        func decrire(_ m: (indice: Int, probabilite: Double)) -> JSONValue {
            let e = liste.especes[m.indice]
            return ["nom": .string(e.nom), "latin": .string(e.latin), "groupe": .string(e.groupe),
                    "confiance": .number((m.probabilite * 100).rounded() / 100)]
        }
        guard let premiere = meilleures.first else { return ["trouvee": false] }
        guard resultat.vivant else {
            return ["trouvee": false, "nature": .number(((resultat.nature ?? 0) * 100).rounded() / 100),
                    "remarque": "Ni animal ni plante reconnus au premier plan (MobileCLIP) : pas d'espèce à proposer."]
        }
        if premiere.probabilite >= seuil {
            var bloc = decrire(premiere).object ?? [:]
            bloc["trouvee"] = true
            let autres = meilleures.dropFirst().filter { $0.probabilite >= 0.05 }
            if !autres.isEmpty { bloc["autres"] = .array(autres.map(decrire)) }
            return .object(bloc)
        }
        return ["trouvee": false, "plus_proches": .array(meilleures.filter { $0.probabilite >= 0.02 }.map(decrire)),
                "remarque": .string("Aucune espèce de la liste au-dessus du seuil provisoire \(Bilan.nombre(seuil, decimales: 2)) : à ne pas proposer comme mot-clé.")]
    }
}
