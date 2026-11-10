import Foundation

/// Les modèles de la retouche générative (`generative_edit`), demandé par Dany le 10 novembre 2026 :
/// « maintenant que tu as plusieurs autres modèles de retouche, regarde dans Fibo 2 Studio, emploie le
/// bon modèle, celui qui te donne le meilleur résultat ». D'après l'étude du même jour (mflux 0.24.0,
/// `--help` de chaque commande, Fibo 2 Studio 2.16) : Fibo 2 par défaut pour toute retouche dans une
/// zone ; Qwen-Image 2.1 Turbo, seul autre modèle de retouche par consigne de mflux à lire un masque
/// (`--mask-image`, blanc = repeindre, recollage exact hors du masque ; mflux-generate-fill, le
/// remplissage de FLUX.1 Fill par `--masked-image-path`, en lit un aussi, sans consigne de retouche ni
/// photo de référence, et n'est pas au catalogue), à départager par le banc d'essai que Dany juge
/// (`--generatif-banc`) ; Qwen-Image-Edit-2511 et FLUX 3 Klein (sans masque) pour plus tard ; Krea 2
/// Turbo écarté (création seulement, aucune retouche dans mflux) ; SeedVR2 reste l'agrandissement de la
/// zone (`Generatif.nomSeedVR`). Ici, les données pures : le catalogue, la table « genre de retouche →
/// modèle », la présence d'un modèle sur ce Mac (lue sans le charger) et le choix d'un appel.
public enum ModeleGeneratif: String, CaseIterable {
    case fibo2 = "fibo2"
    case qwenImage21 = "qwen_image_21"
    case qwenEdit2511 = "qwen_edit_2511"
    case flux3Klein = "flux3_klein"

    /// Où en est un modèle dans Développeur.
    public enum Statut: String {
        /// Le modèle par défaut de la table.
        case parDefaut = "par défaut"
        /// Branché dans generative_edit (model = son id), à départager par le banc d'essai avant
        /// d'entrer dans la table.
        case aDepartager = "à départager"
        /// Au catalogue seulement : pas encore branché (sans masque ; mémoire à mesurer).
        case plusTard = "plus tard"
    }

    /// La fiche d'un modèle : ce que le connecteur en sait, lu dans le `--help` et le code de mflux
    /// 0.24.0 installé (jamais en le lançant).
    public struct Fiche {
        public let modele: ModeleGeneratif
        /// Le nom dit à Dany.
        public let nom: String
        /// La commande de mflux (dans ~/.local/bin, à côté de celle de Fibo 2).
        public let executable: String
        /// Ce qui choisit le modèle dans la commande (`--model …`) ; vide : celui de la commande.
        public let optionModele: [String]
        /// Le dépôt Hugging Face des poids, et la révision que mflux 0.24 épingle
        /// (`ModelRevisions.PINNED`) : hors ligne, il ne lit que cet instantané du cache.
        public let depot: String
        public let revision: String
        /// Les dossiers que l'instantané doit avoir, chacun non vide, pour que le modèle soit complet.
        public let dossiers: [String]
        /// Le nombre d'étapes (nil : celui de la qualité de Fibo 2).
        public let etapes: Int?
        /// Les côtés de l'entrée : multiples de ce nombre (16 pour Fibo 2, 32 pour Qwen-Image 2.1).
        public let multiple: Int
        /// L'option du masque (blanc = refaire) ; nil : le modèle n'en lit aucun.
        public let optionMasque: String?
        /// Le nombre de photos de référence que la commande accepte (le connecteur en donne une au plus).
        public let referencesMax: Int
        /// La quantification passée à mflux (`--quantize`, bits) ; nil : les poids tels quels. Qwen-Image
        /// 2.1 en 8 bits : environ 33 Go en bf16, sur un Mac de 48 Go avec Lightroom ouvert (le Mac a
        /// gelé le 29 octobre 2026 avec deux calculs) ; `--quantize {3,4,5,6,8}` lu dans le `--help` de
        /// mflux-generate-qwen-2.1-edit installé, le 10 novembre 2026.
        public let quantification: Int?
        public let statut: Statut
        /// Vrai : generative_edit sait le lancer.
        public let branche: Bool
        /// Faux : un modèle absent du cache est refusé avant tout envoi (un téléchargement de plus de
        /// 30 Go ne se lance jamais au milieu d'un appel) ; vrai (Fibo 2) : il se télécharge au premier
        /// usage, comme avant.
        public let telechargeAuPremierUsage: Bool
        public let licence: String
        /// Ce qu'il fait le mieux, pour Dany (la planche du banc, la réponse).
        public let pourQuoi: String
    }

    public var fiche: Fiche {
        switch self {
        case .fibo2:
            return Fiche(modele: self, nom: "Fibo 2", executable: Generatif.nomExecutable, optionModele: [],
                         depot: Generatif.depotNormal, revision: "fb2b781f9e9e5572a6c348a5af7a4d155a2b1ed0",
                         dossiers: ["transformer", "text_encoder", "vae"], etapes: nil, multiple: 16,
                         optionMasque: "--mask-path", referencesMax: 5, quantification: nil, statut: .parDefaut, branche: true,
                         telechargeAuPremierUsage: true, licence: "CC BY-NC 4.0",
                         pourQuoi: "retouche dans une zone (masque natif), fiche de FIBO-vlm ; le seul essayé sur les photos de Dany")
        case .qwenImage21:
            return Fiche(modele: self, nom: "Qwen-Image 2.1 Turbo", executable: "mflux-generate-qwen-2.1-edit",
                         optionModele: ["--model", "qwen-image-2.1-turbo"],
                         depot: "Qwen/Qwen-Image-2.1-Turbo", revision: "fc13ba1986fcb905854dc8de2f52eee395f49b5b",
                         dossiers: ["transformer", "text_encoder", "vae", "processor"], etapes: 8, multiple: 32,
                         optionMasque: "--mask-image", referencesMax: 10, quantification: 8, statut: .aDepartager, branche: true,
                         telechargeAuPremierUsage: false, licence: "recherche, usage non commercial",
                         pourQuoi: "retouche dans une zone, rapide (8 étapes, sans guidage) ; recolle exactement la photo hors du masque")
        case .qwenEdit2511:
            return Fiche(modele: self, nom: "Qwen-Image-Edit-2511", executable: "mflux-generate-qwen-edit",
                         optionModele: ["--model", "qwen-image-edit-2511"],
                         depot: "Qwen/Qwen-Image-Edit-2511", revision: "6f3ccc0b56e431dc6a0c2b2039706d7d26f22cb9",
                         dossiers: ["transformer", "text_encoder", "vae"], etapes: 20, multiple: 16,
                         optionMasque: nil, referencesMax: 3 /* 1 à 3 images (fiche de Qwen-Image-Edit-2509) */, quantification: nil, statut: .plusTard, branche: false,
                         telechargeAuPremierUsage: false, licence: "Apache 2.0",
                         pourQuoi: "consigne simple sans masque ; environ 39 Go annoncés, à mesurer avec Lightroom ouvert")
        case .flux3Klein:
            return Fiche(modele: self, nom: "FLUX 3 Klein", executable: "mflux-generate-flux3-edit",
                         optionModele: [],
                         depot: "black-forest-labs/flux-3-image-klein", revision: "8454017f9ebaada30c998fccd9f67a80c7580f68",
                         dossiers: ["transformer", "text_encoder", "vae"], etapes: 16, multiple: 16,
                         optionMasque: nil, referencesMax: 10, quantification: nil, statut: .plusTard, branche: false,
                         telechargeAuPremierUsage: false, licence: "FLUX Kommunity (non relue)",
                         pourQuoi: "plusieurs photos de référence, sans masque ni négatif")
        }
    }

    /// L'étape « Claude · <modèle> » de l'exportation, de l'importation et du journal de la nouvelle
    /// photo : le modèle réellement employé (revue du 10 novembre 2026 ; « Claude · Fibo 2 » pour Fibo 2,
    /// comme avant).
    public var etape: String { "Claude · " + fiche.nom }

    /// Le suffixe du nom de la nouvelle photo (`<photo>-Fibo.tif`, `<photo>-Qwen.tif`).
    public var suffixe: String {
        switch self {
        case .fibo2: return "Fibo"
        case .qwenImage21: return "Qwen"
        case .qwenEdit2511: return "QwenEdit"
        case .flux3Klein: return "Flux3"
        }
    }

    /// Les ids que generative_edit accepte (model), « auto » compris.
    public static var idsBranches: [String] { ["auto"] + allCases.filter { $0.fiche.branche }.map(\.rawValue) }

    // MARK: Présence sur ce Mac

    /// Le dossier de l'instantané épinglé du modèle dans le cache Hugging Face.
    func instantane(cache: URL) -> URL {
        cache.appendingPathComponent("models--" + fiche.depot.replacingOccurrences(of: "/", with: "--"))
            .appendingPathComponent("snapshots/" + fiche.revision)
    }

    /// Pourquoi le modèle ne peut pas tourner sur ce Mac (nil : il le peut), lu sans le charger : la
    /// commande de mflux (à côté de celle de Fibo 2, `dossierBin`), puis, sauf pour un modèle qui se
    /// télécharge au premier usage, l'instantané épinglé complet dans le cache (chaque dossier de
    /// `dossiers` présent et non vide, aucun fichier « .incomplete » d'un téléchargement interrompu).
    public func raisonAbsent(dossierBin: URL, cache: URL) -> String? {
        let f = fiche
        guard f.branche else { return "\(f.nom) n'est pas encore branché dans Développeur (\(f.statut.rawValue))" }
        let commande = dossierBin.appendingPathComponent(f.executable)
        guard FileManager.default.isExecutableFile(atPath: commande.path) else {
            return "la commande \(f.executable) est introuvable sur ce Mac (\(commande.path)) ; l'installer dans le Terminal : uv tool install mflux"
        }
        if f.telechargeAuPremierUsage { return nil }
        if let manque = Self.manqueDansLeCache(instantane(cache: cache), dossiers: f.dossiers, blobs: cache
            .appendingPathComponent("models--" + f.depot.replacingOccurrences(of: "/", with: "--")).appendingPathComponent("blobs")) {
            return "\(f.nom) n'est pas complet sur ce Mac (\(manque)) ; le télécharger une fois dans le Terminal : hf download \(f.depot) --revision \(f.revision)"
        }
        return nil
    }

    /// Ce qui manque à un instantané (nil : rien).
    static func manqueDansLeCache(_ instantane: URL, dossiers: [String], blobs: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: instantane.path) else { return "révision \(instantane.lastPathComponent.prefix(8)) absente du cache" }
        for dossier in dossiers {
            let contenu = (try? fm.contentsOfDirectory(atPath: instantane.appendingPathComponent(dossier).path)) ?? []
            if contenu.filter({ !$0.hasPrefix(".") }).isEmpty { return "dossier \(dossier) absent ou vide" }
        }
        if ((try? fm.contentsOfDirectory(atPath: blobs.path)) ?? []).contains(where: { $0.hasSuffix(".incomplete") }) {
            return "téléchargement interrompu"
        }
        return nil
    }
}

extension Generatif {
    // MARK: Genre de retouche et choix du modèle

    /// Le genre d'une retouche, lu dans l'appel lui-même (jamais demandé) : sa forme (zone, photo de
    /// référence), puis, dans une zone, l'instruction (retirer ou changer).
    public enum Genre: String, CaseIterable {
        /// Retirer un objet, une personne, un fil, dans une zone.
        case retirer
        /// Changer ou ajouter un objet, un vêtement, dans une zone.
        case changer
        /// Remplir une zone d'après une photo de référence (fond, décor, vêtement d'une autre photo).
        case remplirAvecReference = "remplir_avec_reference"
        /// Toute la photo, sans zone (ambiance, saison).
        case photoEntiere = "photo_entiere"

        var texte: String {
            switch self {
            case .retirer: return "retirer dans une zone"
            case .changer: return "changer ou ajouter dans une zone"
            case .remplirAvecReference: return "remplir une zone d'après une photo de référence"
            case .photoEntiere: return "toute la photo, sans zone"
            }
        }
    }

    /// Une instruction qui retire (« remove the wire », « erase the person », « get rid of »).
    static func retire(_ instruction: String) -> Bool {
        instruction.range(of: #"(?i)\b(remove|removes|removing|erase|erasing|delete|deleting|get rid of|take out|take away|clean up|without the)\b"#,
                          options: .regularExpression) != nil
    }

    /// Le genre d'un appel : sans zone, toute la photo ; avec une référence, remplir ; sinon retirer ou
    /// changer d'après la première instruction.
    static func genre(instruction: String, avecZone: Bool, avecReference: Bool) -> Genre {
        if !avecZone { return .photoEntiere }
        if avecReference { return .remplirAvecReference }
        return retire(instruction) ? .retirer : .changer
    }

    /// La table « genre de retouche → modèle » : le modèle employé par model = auto, et ceux à
    /// départager pour ce genre par le banc d'essai (`--generatif-banc`). Fibo 2 partout tant que Dany
    /// n'a pas jugé le banc ; Qwen-Image 2.1 Turbo à départager partout où il y a une zone (il ne
    /// comprend un masque que sur la première image, la photo à changer). Toute la photo : Fibo 2 seul
    /// (à environ 1 Mpx, toute retouche générative de la photo entière perd sa définition ; l'ambiance
    /// et les couleurs se font dans Lightroom).
    public static let tableDesModeles: [Genre: (modele: ModeleGeneratif, aDepartager: [ModeleGeneratif])] = [
        .retirer: (.fibo2, [.qwenImage21]),
        .changer: (.fibo2, [.qwenImage21]),
        .remplirAvecReference: (.fibo2, [.qwenImage21]),
        .photoEntiere: (.fibo2, []),
    ]

    /// Le modèle d'un appel et pourquoi.
    struct ChoixModele {
        var modele: ModeleGeneratif
        var genre: Genre
        /// Vrai : model = auto (la table) ; faux : l'id donné.
        var auto: Bool
        var pourquoi: String
    }

    /// Le modèle d'un appel : `demande` (model : nil ou « auto » = la table, sinon un id branché), le
    /// genre de l'appel, et ce qui manque à chaque modèle sur ce Mac (`absent`, nil : présent). Un id
    /// inconnu ou pas encore branché est refusé ; un modèle demandé absent, refusé avec sa raison ; avec
    /// auto, un modèle de la table absent (sauf Fibo 2, qui se télécharge au premier usage) laisse la
    /// place à Fibo 2, et la raison le dit.
    static func choisirModele(_ demande: String?, genre: Genre, table: [Genre: (modele: ModeleGeneratif, aDepartager: [ModeleGeneratif])] = tableDesModeles,
                              absent: (ModeleGeneratif) -> String?) throws -> ChoixModele {
        let texte = demande?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "auto"
        if texte.isEmpty || texte == "auto" {
            let ligne = table[genre] ?? (.fibo2, [])
            var pourquoi = "auto : \(ligne.modele.fiche.nom), le modèle de la table pour « \(genre.texte) »"
            if !ligne.aDepartager.isEmpty {
                pourquoi += " (\(ligne.aDepartager.map(\.fiche.nom).joined(separator: ", ")) à départager par le banc d'essai)"
            }
            if ligne.modele != .fibo2, let raison = absent(ligne.modele) {
                return ChoixModele(modele: .fibo2, genre: genre, auto: true,
                                   pourquoi: "auto : Fibo 2, car \(ligne.modele.fiche.nom), le modèle de la table pour « \(genre.texte) », manque ici (\(raison))")
            }
            return ChoixModele(modele: ligne.modele, genre: genre, auto: true, pourquoi: pourquoi)
        }
        guard let modele = ModeleGeneratif(rawValue: texte) else {
            throw LightroomError.invalid("« model » : \(ModeleGeneratif.idsBranches.joined(separator: ", ")) (pas « \(demande ?? "") »). Rien n'a été fait.")
        }
        guard modele.fiche.branche else {
            throw LightroomError.invalid("« model » : \(modele.fiche.nom) n'est pas encore branché dans Développeur (\(modele.fiche.statut.rawValue) : \(modele.fiche.pourQuoi)) ; employer \(ModeleGeneratif.idsBranches.joined(separator: ", ")). Rien n'a été fait.")
        }
        if let raison = absent(modele) {
            throw LightroomError.invalid("« model » : \(modele.fiche.nom) ne peut pas tourner sur ce Mac : \(raison). Rien n'a été fait.")
        }
        return ChoixModele(modele: modele, genre: genre, auto: false, pourquoi: "demandé (model = \(modele.rawValue)) pour « \(genre.texte) »")
    }

    /// Le catalogue en JSON, avec la présence de chaque modèle sur ce Mac (le banc d'essai, la recette).
    static func catalogueJSON(dossierBin: URL, cache: URL) -> JSONValue {
        .array(ModeleGeneratif.allCases.map { m in
            let f = m.fiche
            var objet: [String: JSONValue] = [
                "id": .string(m.rawValue), "nom": .string(f.nom), "commande": .string(f.executable),
                "options_modele": .array(f.optionModele.map(JSONValue.string)), "depot": .string(f.depot), "revision": .string(f.revision),
                "masque": f.optionMasque.map(JSONValue.string) ?? .null, "references_max": .number(Double(f.referencesMax)),
                "multiple": .number(Double(f.multiple)), "statut": .string(f.statut.rawValue), "branche": .bool(f.branche),
                "quantification": f.quantification.map { .number(Double($0)) } ?? .null,
                "licence": .string(f.licence), "pour_quoi": .string(f.pourQuoi),
                // Le vrai dossier (~/.cache/huggingface/hub est un lien vers le SSD sur ce Mac).
                "chemin_cache": .string(m.instantane(cache: cache.resolvingSymlinksInPath()).path),
            ]
            let depotCache = cache.appendingPathComponent("models--" + f.depot.replacingOccurrences(of: "/", with: "--"))
            objet["dans_le_cache"] = .bool(ModeleGeneratif.manqueDansLeCache(m.instantane(cache: cache), dossiers: f.dossiers,
                                                                               blobs: depotCache.appendingPathComponent("blobs")) == nil)
            if let etapes = f.etapes { objet["etapes"] = .number(Double(etapes)) }
            let raison = m.raisonAbsent(dossierBin: dossierBin, cache: cache)
            objet["present"] = .bool(raison == nil)
            if let raison { objet["raison_absent"] = .string(raison) }
            return .object(objet)
        })
    }

    // MARK: Qwen-Image 2.1

    /// Environ un mégapixel, mêmes proportions, côtés multiples de `multiple` (32 pour Qwen-Image 2.1,
    /// qui refuse un autre côté). Qwen-Image 2.1 Turbo travaille toujours à cette taille, même pour un
    /// petit recadrage (sous 1 024 px, le README de mflux dit que Turbo change le détail fin en grille
    /// de pixels) : la recomposition remet la zone à la taille du recadrage.
    static func tailleCible(largeur: Int, hauteur: Int, multiple: Int) -> (largeur: Int, hauteur: Int) {
        guard multiple != 16 else { return tailleCible(largeur: largeur, hauteur: hauteur) }
        let rapport = max(0.125, min(8, Double(largeur) / Double(max(hauteur, 1))))
        let l = (1024.0 * 1024.0 * rapport).squareRoot(), h = l / rapport
        func arrondi(_ v: Double) -> Int { max(256, Int((v / Double(multiple)).rounded()) * multiple) }
        return (arrondi(l), arrondi(h))
    }

    /// L'instruction donnée à Qwen-Image 2.1 : les marques de Fibo 2 (`<image_1>`, `<image_2>`) en mots
    /// (« image 1 », « image 2 », que le README de mflux emploie), et la zone grisée de Fibo dite
    /// masquée (Qwen ne grise rien : il repeint la zone blanche du masque).
    static func instructionPourQwen(_ instruction: String) -> String {
        instruction.replacingOccurrences(of: "<image_1>", with: "image 1")
            .replacingOccurrences(of: "<image_2>", with: "image 2")
            // Casse indifférente : « Grey area », « GRAY AREA », une majuscule en tête de phrase.
            .replacingOccurrences(of: #"\b(grey|gray) area"#, with: "masked area", options: [.regularExpression, .caseInsensitive])
    }

    /// Les arguments de Qwen-Image 2.1 Turbo (`mflux-generate-qwen-2.1-edit --model qwen-image-2.1-turbo`),
    /// en tableau : la phrase seule (jamais de fiche de FIBO-vlm, propre à Fibo 2), l'entrée (non grisée)
    /// puis la photo de référence, le masque par `--mask-image` (blanc = repeindre, sur la première image,
    /// avec ou sans référence : mflux recolle exactement les pixels hors du masque), 8 étapes, sans
    /// --guidance (Turbo refuse tout autre que 1) ni --negative-prompt (sans effet à guidage 1), ni
    /// --cfg-end ni --vae-full-precision (propres à Fibo 2) ; --quantize 8 (sa fiche : environ 33 Go en
    /// bf16, trop avec Lightroom ouvert), --low-ram, la taille (côtés multiples de 32), la graine et la
    /// sortie, un PNG (`.png`, d'après --output). Pas de --verify.
    static func argumentsQwen(entree: URL, masque: URL?, instruction: String, taille: (largeur: Int, hauteur: Int),
                              graine: Int, sortie: URL, reference: URL? = nil) -> [String] {
        let f = ModeleGeneratif.qwenImage21.fiche
        var args = f.optionModele + ["--prompt", instructionPourQwen(instruction)]
        args += ["--image-paths", entree.path] + (reference.map { [$0.path] } ?? [])
        if let masque, let option = f.optionMasque { args += [option, masque.path] }
        args += ["--steps", String(f.etapes ?? 8)]
        if let bits = f.quantification { args += ["--quantize", String(bits)] }
        args += ["--low-ram", "--width", String(taille.largeur), "--height", String(taille.hauteur), "--seed", String(graine), "--output", sortie.path]
        return args
    }
}

extension Generatif {
    /// Le catalogue des modèles et leur présence sur ce Mac, d'après la configuration de Fibo
    /// (`--generatif-banc --catalogue`).
    public static func catalogue(fibo: Fibo) -> JSONValue {
        catalogueJSON(dossierBin: fibo.executable.deletingLastPathComponent(), cache: fibo.cacheHF)
    }
}
