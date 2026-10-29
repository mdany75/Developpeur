import CoreGraphics
import Foundation

/// Fibo 2 sur ce Mac : l'exécutable de mflux, celui de SeedVR2 (la zone remise à sa taille), le
/// cache de Hugging Face (le modèle Turbo local) et la racine des fichiers de travail du Développeur,
/// où vont les dossiers temporaires (`<racine>/Temporaire/Fibo/<uuid>/`, que le module vide aussi à
/// son chargement). Les tests passent de faux exécutables (des scripts) et des dossiers temporaires ;
/// SeedVR2 est cherché par défaut à côté de mflux (le faux dossier des tests, jamais le vrai).
public struct Fibo {
    public var executable: URL
    public var seedVR: URL
    public var cacheHF: URL
    public var racine: URL
    /// Délai maximal de chaque passage de Fibo, et de chaque passage de SeedVR2.
    public var delaiMax: TimeInterval

    public init(executable: URL? = nil, seedVR: URL? = nil, cacheHF: URL? = nil, racine: URL? = nil, delaiMax: TimeInterval = Generatif.delaiMax) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let executable = executable ?? home.appendingPathComponent(".local/bin/" + Generatif.nomExecutable)
        self.executable = executable
        self.seedVR = seedVR ?? executable.deletingLastPathComponent().appendingPathComponent(Generatif.nomSeedVR)
        self.cacheHF = cacheHF ?? home.appendingPathComponent(".cache/huggingface/hub")
        self.racine = racine ?? home.appendingPathComponent("Library/Application Support/Developpeur")
        self.delaiMax = delaiMax
    }

    /// Le dossier des fichiers temporaires de Fibo (le module y refuse tout autre chemin).
    var dossierTemporaire: URL { racine.appendingPathComponent("Temporaire/Fibo") }
}

/// Le calcul de Fibo 2 en cours (un à la fois : FileOutils passe les appels un à un) : mflux (ou
/// SeedVR2) et le dossier temporaire de l'appel, pour que l'arrêt du serveur (fin de l'entrée :
/// Lightroom quitté, module rechargé, Claude Desktop fermé) arrête mflux, qui tient plusieurs Go de mémoire, et
/// efface le dossier, que le `defer` de l'appel n'efface plus si le processus se termine.
public final class TravailFibo {
    private let verrou = NSLock()
    private var processus: Process?
    private var dossier: URL?

    public init() {}

    func commencer(dossier: URL) {
        verrou.lock(); defer { verrou.unlock() }
        self.dossier = dossier
    }

    func lancer(_ processus: Process) {
        verrou.lock(); defer { verrou.unlock() }
        self.processus = processus
    }

    func finir() {
        verrou.lock(); defer { verrou.unlock() }
        processus = nil
        dossier = nil
    }

    /// mflux en cours (pour les essais).
    var enCours: Process? {
        verrou.lock(); defer { verrou.unlock() }
        return processus
    }

    /// Arrête mflux s'il tourne (SIGTERM, puis SIGKILL après 3 s) et efface le dossier de l'appel.
    public func arreter() {
        verrou.lock()
        let processus = self.processus, dossier = self.dossier
        self.processus = nil
        self.dossier = nil
        verrou.unlock()
        if let processus, processus.isRunning {
            processus.terminate()
            let fin = Date().addingTimeInterval(3)
            while processus.isRunning, Date() < fin { usleep(50_000) }
            if processus.isRunning { kill(processus.processIdentifier, SIGKILL) }
        }
        if let dossier { try? FileManager.default.removeItem(at: dossier) }
    }

    /// Le serveur terminé par un signal (SIGTERM, SIGINT, SIGHUP) plutôt que par la fin de son
    /// entrée : mflux (ou SeedVR2) arrêté et le dossier de l'appel effacé, puis `sortir` (par défaut,
    /// la fin du processus avec le code du signal). Les sources rendues sont à garder pour la vie du
    /// serveur (serve, dans main.swift).
    public func arreterAuxSignaux(_ signaux: [Int32] = [SIGTERM, SIGINT, SIGHUP],
                                  sortir: @escaping (Int32) -> Void = { exit(128 + $0) }) -> [DispatchSourceSignal] {
        signaux.map { numero in
            signal(numero, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: numero, queue: .global())
            source.setEventHandler { [weak self] in
                self?.arreter()
                sortir(numero)
            }
            source.resume()
            return source
        }
    }
}


/// Ce qu'un processus (mflux ou SeedVR2) a dit de son avancée, partagé entre la lecture de sa
/// sortie et la boucle qui l'attend.
final class SuiviProcessus {
    private let verrou = NSLock()
    let debut = Date()
    private var etapeLue: Int?
    private var premiereLue: (etape: Int, date: Date)?
    private var fractionLue: Double = 0
    private var totalLu: Int?

    /// Une étape plus petite que la dernière lue : une autre barre commence (la vraie, après une
    /// barre de chargement qui aurait le même nombre d'étapes) ; le rythme repart d'elle.
    func noterEtape(_ etape: Int) {
        verrou.lock(); defer { verrou.unlock() }
        if premiereLue == nil || etape < (etapeLue ?? 0) { premiereLue = (etape, Date()) }
        etapeLue = etape
    }

    /// L'avancée d'une barre (SeedVR2) : une barre d'un autre total en remplace la fraction.
    func noterFraction(fait: Int, total: Int) {
        verrou.lock(); defer { verrou.unlock() }
        let fraction = min(1, Double(fait) / Double(max(1, total)))
        fractionLue = totalLu == total ? max(fractionLue, fraction) : fraction
        totalLu = total
    }

    var etat: (etape: Int?, premiere: (etape: Int, date: Date)?, fraction: Double) {
        verrou.lock(); defer { verrou.unlock() }
        return (etapeLue, premiereLue, fractionLue)
    }
}

/// La fin d'un processus lancé par `executer` (l'annulation, elle, est levée).
enum FinProcessus {
    case reussi
    case echec(code: Int32, journal: String)
    case delai
    case lancement(String)
}

/// generative_edit (Retouche générative, Fibo 2) : la photo développée part en TIFF 16 bits
/// (commande exporter du module, comme export_photos) ; pour chaque modification (1 à 4), Fibo 2
/// reçoit un recadrage autour de sa zone (ou la photo entière, sans zone), à environ 1 Mpx, depuis
/// le même TIFF ; une sortie agrandie de plus de 1,25 fois pour revenir à sa taille passe d'abord
/// par SeedVR2 ; chaque zone est reprise dans la photo en pleine résolution (Generatif.swift), puis
/// le TIFF final entre au catalogue, empilé au-dessus de l'original (commande importerGeneree, une
/// seule fois). Seulement sur demande de l'utilisateur ; jamais d'initiative.
extension ToolHandler {
    /// Délai de la commande importerGeneree (copie du fichier, ajout au catalogue).
    static let importTimeout: TimeInterval = 120

    var generativeDefinitions: [JSONValue] {
        let region = objectProp("La zone à changer, de 0 à 1 dans l'image que montre view_photo, la plus juste possible : Fibo 2 travaille sur un recadrage autour d'elle, et seule elle revient dans la photo, en pleine résolution.",
                                ["x": prop("number", "Bord gauche, de 0 à 1."), "y": prop("number", "Bord haut, de 0 à 1."),
                                 "width": prop("number", "Largeur, de 0 à 1."), "height": prop("number", "Hauteur, de 0 à 1.")],
                                required: ["x", "y", "width", "height"])
        let instruction = prop("string", "En anglais, précise : ce qui change et ce qui doit rester (pose, lumière, reste du corps) ; « replace the trousers with a knee-length navy skirt, keep the pose, the light and everything else unchanged ».")
        let francais = prop("string", "Exigée : la traduction française de instruction, montrée à l'utilisateur et gardée au journal.")
        let label = prop("string", "Nom court en français de la modification (« jupe »), pour la barre de progression et la réponse.")
        return [
            tool("generative_edit",
                 "Retouche générative par Fibo 2, sur ce Mac : seulement sur demande explicite de l'utilisateur, jamais d'initiative, pour ce que Lightroom ne sait pas faire (changer un vêtement, ajouter, retirer ou changer un objet ; la seule couleur d'un objet : add_mask). Ordre : d'abord les corrections de base sur la photo d'origine (profil, balance, exposition), puis generative_edit, puis les finitions (apply_settings, add_mask…) sur la nouvelle photo, par son id. instruction : en anglais, précise (ce qui change et ce qui reste : pose, lumière, reste du corps) ; instruction_fr : sa traduction, pour l'utilisateur ; region : la zone, la plus juste possible (Fibo 2 travaille sur un recadrage autour d'elle ; le reste garde ses pixels). Plusieurs changements : edits (4 au plus, une region chacune, sans chevauchement), un seul appel, une seule nouvelle photo. Le résultat entre au catalogue en TIFF, empilé au-dessus de l'original (intact), et devient la photo active ; undo_last ne le retire pas. Quelques minutes par modification (« pas fini » : rappeler avec les mêmes arguments). Vérifier ensuite avec view_photo. Mode « Proposer d'abord » : décrire, attendre l'accord, puis confirm = true.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("instruction", instruction),
                    ("instruction_fr", francais),
                    ("region", region),
                    ("label", label),
                    ("edits", ["type": "array", "minItems": 1, "maxItems": .number(Double(Generatif.maxModifications)),
                               "description": "Plusieurs modifications en un appel (à la place de instruction, instruction_fr, region) : chacune avec sa region, sans chevauchement ; deux zones qui se touchent ou presque : deux appels, le second sur la nouvelle photo.",
                               "items": objectProp("Une modification.", ["label": label, "instruction": instruction, "instruction_fr": francais, "region": region],
                                                   required: ["instruction", "instruction_fr", "region"])]),
                    ("context", enumProp(["crop", "full_and_crop"], "crop (défaut) : Fibo 2 reçoit le recadrage autour de la zone ; full_and_crop : aussi la photo entière, pour la lumière et le style (sans masque ; avec region seulement).")),
                    ("upscale", prop("boolean", "Vrai par défaut : une zone que Fibo 2 rend plus petite que sa taille dans la photo passe par SeedVR2 (plus de détail) ; faux : mise à la taille ordinaire.")),
                    ("quality", enumProp(["normal", "fast"], "normal (défaut) : \(Generatif.etapesNormal) étapes, pleine précision, quelques minutes ; fast : Turbo, \(Generatif.etapesRapide) étapes, plus rapide et moins fidèle.")),
                    ("seed", prop("integer", "Graine (facultative) : la même graine et la même instruction redonnent la même image ; sans elle, une graine au hasard, rendue dans la réponse.")),
                    ("confirm", prop("boolean", "true = l'utilisateur a approuvé cette retouche (exigé en mode « Proposer d'abord »).")),
                    ("reason", prop("string", Self.descriptionRaison)),
                 ],
                 required: []),
        ]
    }

    func generativeEdit(_ args: Arguments) throws -> JSONValue {
        do {
            return try retoucheGenerative(args)
        } catch is ArretDansLightroom {
            throw LightroomError.plugin("Arrêté dans Lightroom (croix de la barre de progression) : Fibo 2 est arrêté, rien n'a été importé.")
        }
    }

    /// Ce que l'appel prépare pour une modification, puis ce que Fibo 2 en a fait.
    private struct Passage {
        var modif: Generatif.Modification
        /// Le recadrage dans la photo (toute la photo sans zone).
        var cadre: Generatif.Pixels
        /// La zone dans le repère du recadrage.
        var regionCadre: CGRect?
        var taille: (largeur: Int, hauteur: Int)
        var seedVRPrevu: Bool
        var piece: Generatif.Piece?
        var partChangee = 0.0
        var sortieEntiere = false
        var seedVRFait = false
        var remarqueSeedVR: String?
        /// Une sortie qui ne s'aligne pas sur le recadrage (full_and_crop) : rien n'en est repris.
        var nonAlignee: String?
    }

    private func retoucheGenerative(_ args: Arguments) throws -> JSONValue {
        let debut = Date()
        // Seuls serve() et --call (main.swift) le posent : un ToolHandler neuf (les essais) ne lance
        // jamais le vrai mflux.
        guard let fibo else {
            throw LightroomError.invalid("Fibo 2 n'est pas configuré dans ce serveur : rien n'a été fait.")
        }
        let modifications = try Generatif.modifications(args.raw)
        let qualiteTexte = args.string("quality") ?? "normal"
        guard let qualite = Generatif.Qualite(rawValue: qualiteTexte) else { throw LightroomError.invalid("« quality » : normal ou fast.") }
        let modeTexte = args.string("context") ?? "crop"
        guard let mode = Generatif.ModeContexte(rawValue: modeTexte) else { throw LightroomError.invalid("« context » : crop ou full_and_crop.") }
        if mode == .fullAndCrop, modifications.contains(where: { $0.region == nil }) {
            throw LightroomError.invalid("« context » = full_and_crop : seulement avec une region (la zone à modifier). Rien n'a été fait.")
        }
        let agrandir = args.bool("upscale") ?? true
        let graine: Int
        if args.has("seed") {
            guard let donnee = args.int("seed"), (0...Int(Int32.max)).contains(donnee) else {
                throw LightroomError.invalid("« seed » : un entier de 0 à \(Int32.max).")
            }
            graine = donnee
        } else {
            graine = Int.random(in: 0...999_999_999)
        }
        guard FileManager.default.isExecutableFile(atPath: fibo.executable.path) else {
            throw LightroomError.invalid("Fibo 2 (mflux) est introuvable sur ce Mac (\(fibo.executable.path)). L'installer dans le Terminal : uv tool install mflux ; le modèle se télécharge au premier usage. Rien n'a été fait.")
        }
        let confirme = args.bool("confirm") ?? false
        let etat = try lightroom.send("etat", [:], timeout: 10)
        if etat["pause"]?.bool == true {
            throw LightroomError.invalid("Liaison en pause dans Lightroom : rien n'a été fait. La reprendre (fenêtre de la liaison), puis rappeler generative_edit.")
        }
        if etat["mode"]?.string == "proposer d'abord", !confirme {
            throw LightroomError.invalid("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été fait. Dire à l'utilisateur ce que Fibo 2 changera (instruction_fr, zone, qualité, quelques minutes), attendre son accord, puis rappeler generative_edit avec confirm = true.")
        }
        guard let photo = args.int("photo_id") ?? etat["photo_active"]?["id"]?.int else {
            throw LightroomError.invalid("Aucune photo active : donner photo_id.")
        }

        let dossier = fibo.dossierTemporaire.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        travailFibo.commencer(dossier: dossier)
        defer {
            travailFibo.finir()
            try? FileManager.default.removeItem(at: dossier)
        }
        // L'étape et la raison que la fenêtre de la liaison montre avec une demande d'accord, et que
        // le journal de la nouvelle photo garde : le texte français (et la raison donnée).
        let consigne = Generatif.consigneJournal(modifications, raison: Self.raison(args))
        var barre = BarreFibo(handler: self, avancement: Generatif.Avancement(seedVR: modifications.map { _ in false }), nombre: modifications.count)

        // 1. La photo développée en TIFF 16 bits Adobe RGB, taille réelle, métadonnées gardées.
        barre.montrer(.export, "exportation de la photo en TIFF", rang: nil, detail: nil)
        let reponse = try lightroom.send("exporter", [
            "photos": [.number(Double(photo))],
            "dossier": .string(dossier.path),
            "reglages": ["format": "TIFF", "espace": "AdobeRGB", "profondeur": 16, "metadonnees": "all", "sans_lieu": false],
            "etape": .string(Self.etapeFibo),
            "raison": .string(consigne),
            "confirme": .bool(confirme),
        ], timeout: Self.exportTimeout)
        let fichier = reponse["fichiers"]?.array?.first
        guard let cheminTIFF = fichier?["chemin"]?.string else {
            throw LightroomError.plugin("La photo n'a pas pu partir en TIFF : \(fichier?["erreur"]?.string ?? "raison inconnue"). Rien n'a été fait.")
        }
        let tiff = URL(fileURLWithPath: cheminTIFF)
        guard tiff.standardizedFileURL.path.hasPrefix(dossier.standardizedFileURL.path + "/"),
              let (origine, proprietes) = Generatif.lireImage(tiff) else {
            throw LightroomError.plugin("Le TIFF exporté est introuvable ou illisible (\(cheminTIFF)). Rien n'a été fait.")
        }
        try contexte.verifier()
        // Deux zones dont les bords fondus se recouvriraient (qui se touchent ou presque) : la seconde
        // effacerait le bord de la première. Vu ici, d'après la taille de la photo exportée.
        if modifications.count > 1,
           let (a, b) = Generatif.zonesTropProches(modifications.compactMap(\.region), largeur: origine.width, hauteur: origine.height) {
            throw LightroomError.invalid("Les zones de « \(modifications[a].label) » et de « \(modifications[b].label) » se touchent ou sont trop proches : leurs bords fondus se recouvriraient, et la seconde effacerait le bord de la première. Les faire en deux appels successifs (le second sur la nouvelle photo, par son id). Rien n'a été importé.")
        }

        // 2. Le recadrage et la taille de l'entrée de chaque modification ; SeedVR2 prévu ou non.
        let seedVRPresent = FileManager.default.isExecutableFile(atPath: fibo.seedVR.path)
        var passages: [Passage] = modifications.map { modif in
            let cadre: Generatif.Pixels, taille: (largeur: Int, hauteur: Int), regionCadre: CGRect?
            if let region = modif.region {
                (cadre, taille) = Generatif.recadrage(region, largeur: origine.width, hauteur: origine.height)
                regionCadre = Generatif.regionDansRecadrage(region, cadre: cadre, largeur: origine.width, hauteur: origine.height)
            } else {
                cadre = Generatif.Pixels(x: 0, y: 0, largeur: origine.width, hauteur: origine.height)
                taille = Generatif.tailleCible(largeur: origine.width, hauteur: origine.height)
                regionCadre = nil
            }
            let prevu = seedVRPresent && Generatif.seedVR(cadre: cadre, taille: taille, avecRegion: modif.region != nil, demande: agrandir).lancer
            return Passage(modif: modif, cadre: cadre, regionCadre: regionCadre, taille: taille, seedVRPrevu: prevu)
        }
        barre.avancement = Generatif.Avancement(seedVR: passages.map(\.seedVRPrevu))
        // La photo entière à ~1 Mpx, pour le contexte (full_and_crop), écrite une fois.
        var cheminContexte: URL?
        if mode == .fullAndCrop {
            let taille = Generatif.tailleCible(largeur: origine.width, hauteur: origine.height)
            guard let pixels = Generatif.entree(origine, cadre: nil, taille: taille),
                  let image = Generatif.image8(pixels, largeur: taille.largeur, hauteur: taille.hauteur) else {
                throw LightroomError.plugin("Entrée de Fibo 2 impossible à préparer. Rien n'a été fait.")
            }
            cheminContexte = dossier.appendingPathComponent("contexte.png")
            try Generatif.ecrirePNG(image, vers: cheminContexte!)
        }

        // 3. Fibo 2, une fois par modification, chacune depuis le TIFF exporté.
        let modeleRapide = qualite == .fast ? Generatif.modeleLocal(depot: Generatif.depotRapide, cache: fibo.cacheHF) : nil
        var dureeFibo: TimeInterval = 0
        var chargementVu: TimeInterval?
        for rang in passages.indices {
            var passage = passages[rang]
            let n = rang + 1, taille = passage.taille
            guard let entree = Generatif.entree(origine, cadre: passage.modif.region == nil ? nil : passage.cadre, taille: taille),
                  let imageEntree = Generatif.image8(entree, largeur: taille.largeur, hauteur: taille.hauteur) else {
                throw LightroomError.plugin("Entrée de Fibo 2 impossible à préparer. Rien n'a été fait.")
            }
            let cheminEntree = dossier.appendingPathComponent("entree-\(n).png")
            try Generatif.ecrirePNG(imageEntree, vers: cheminEntree)
            var cheminMasque: URL?
            if let regionCadre = passage.regionCadre, mode == .crop {
                let masque = Generatif.masqueRegion(regionCadre, largeur: taille.largeur, hauteur: taille.hauteur)
                guard let image = Generatif.imageMasque(masque, largeur: taille.largeur, hauteur: taille.hauteur) else {
                    throw LightroomError.plugin("Masque de Fibo 2 impossible à préparer. Rien n'a été fait.")
                }
                cheminMasque = dossier.appendingPathComponent("masque-\(n).png")
                try Generatif.ecrirePNG(image, vers: cheminMasque!)
            }
            let cheminSortie = dossier.appendingPathComponent("sortie-\(n).png")
            let arguments = Generatif.arguments(entree: cheminEntree, masque: cheminMasque, instruction: passage.modif.instruction, taille: taille,
                                                qualite: qualite, graine: graine, sortie: cheminSortie, modeleRapide: modeleRapide,
                                                contexte: cheminContexte)
            let avant = Set((try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? [])
            barre.montrer(.chargement(rang), passage.modif.label, rang: n, detail: "chargement du modèle")
            let debutFibo = Date()
            let suivi = SuiviProcessus()
            let fin = try executer(fibo.executable, arguments, dossier: dossier, delai: fibo.delaiMax, suivi: suivi,
                                   lire: { ligne in
                                       guard let e = Generatif.progression(ligne, etapes: qualite.etapes) else { return false }
                                       suivi.noterEtape(e); return true
                                   },
                                   tic: {
                                       let lu = suivi.etat
                                       guard let etape = lu.etape, let premiere = lu.premiere else {
                                           barre.montrer(.chargement(rang), passage.modif.label, rang: n, detail: "chargement du modèle")
                                           return
                                       }
                                       let chargement = premiere.date.timeIntervalSince(suivi.debut)
                                       let reste = Generatif.tempsRestant(etape: etape, sur: qualite.etapes, premiere: premiere.etape,
                                                                         secondesDepuisPremiere: Date().timeIntervalSince(premiere.date),
                                                                         chargement: chargementVu ?? chargement, suivantes: passages.count - n)
                                       barre.montrer(.etapes(rang, fait: etape, sur: qualite.etapes), passage.modif.label, rang: n,
                                                     detail: reste.map(Generatif.texteTempsRestant))
                                   })
            switch fin {
            case .reussi: break
            case .echec(let code, let journal):
                throw LightroomError.plugin(Generatif.expliquer(journal: journal, code: code, rapide: qualite == .fast) + " Rien n'a été importé.")
            case .delai:
                throw LightroomError.plugin("Fibo 2 n'a pas fini en \(Int(fibo.delaiMax / 60)) min : arrêté, rien n'a été importé. Réessayer avec quality = fast, ou plus tard.")
            case .lancement(let raison):
                throw LightroomError.plugin("Fibo 2 (mflux) ne se lance pas : \(raison). Rien n'a été fait.")
            }
            if chargementVu == nil, let premiere = suivi.etat.premiere { chargementVu = premiere.date.timeIntervalSince(suivi.debut) }
            dureeFibo += Date().timeIntervalSince(debutFibo)
            guard let generee = Generatif.lireImage(sortieDeFibo(cheminSortie, dossier: dossier, avant: avant))?.image,
                  let sortie = Generatif.pixelsRGBA8(generee, largeur: taille.largeur, hauteur: taille.hauteur) else {
                throw LightroomError.plugin("Fibo 2 a fini sans image lisible. Rien n'a été importé.")
            }
            try contexte.verifier()

            // Sans masque (full_and_crop), une sortie qui ne s'aligne pas sur le recadrage (reprise de
            // la photo entière, sujet cadré autrement) : le pourtour de la zone a changé ; rien n'en
            // est repris.
            if mode == .fullAndCrop, let regionCadre = passage.regionCadre,
               let pourtour = Generatif.partDuPourtourChangee(entree: entree, sortie: sortie, largeur: taille.largeur, hauteur: taille.hauteur, region: regionCadre),
               pourtour > Generatif.partPourtourMax {
                passage.nonAlignee = "La sortie de Fibo 2 ne s'aligne pas sur le recadrage (\(Int((pourtour * 100).rounded())) % du pourtour de la zone changé) : rien n'en est repris. Réessayer avec context = crop, ou une autre seed."
                passages[rang] = passage
                continue
            }

            // La zone changée (dans le repère du recadrage), et la zone de mélange.
            let changee = Generatif.zoneChangee(entree: entree, sortie: sortie, largeur: taille.largeur, hauteur: taille.hauteur, region: passage.regionCadre)
            let partCadre = Generatif.part(changee)
            passage.partChangee = partCadre * Double(passage.cadre.largeur * passage.cadre.hauteur) / Double(origine.width * origine.height)
            if partCadre >= Generatif.partMinimale {
                let (zone, entiere) = Generatif.zoneDeMelange(changee: changee, region: passage.regionCadre, largeur: taille.largeur, hauteur: taille.hauteur)
                passage.sortieEntiere = entiere
                var image = generee
                // SeedVR2 : la sortie remise à la taille native de son recadrage (côté court), sinon
                // mise à la taille ordinaire, dite dans la réponse.
                let decision = Generatif.seedVR(cadre: passage.cadre, taille: taille, avecRegion: passage.modif.region != nil, demande: agrandir)
                if !decision.lancer {
                    passage.remarqueSeedVR = decision.raison
                } else {
                    if !seedVRPresent {
                        passage.remarqueSeedVR = "SeedVR2 est absent de ce Mac (\(fibo.seedVR.path)) : mise à la taille ordinaire, moins de détail. L'installer avec mflux (uv tool install mflux)."
                    } else {
                        let (agrandie, remarque) = try passerSeedVR(cheminSortie: sortieDeFibo(cheminSortie, dossier: dossier, avant: avant), rang: rang, passage: passage,
                                                                    graine: graine, dossier: dossier, fibo: fibo, barre: &barre)
                        if let agrandie { image = agrandie; passage.seedVRFait = true }
                        passage.remarqueSeedVR = remarque
                    }
                }
                passage.piece = Generatif.Piece(generee: image, zone: zone, largeurZone: taille.largeur, hauteurZone: taille.hauteur, cadre: passage.cadre)
            }
            passages[rang] = passage
        }

        // 4. La recomposition en pleine résolution, toutes les zones dans le même TIFF.
        let pieces = passages.compactMap(\.piece)
        guard !pieces.isEmpty else {
            let nonAlignees = passages.compactMap(\.nonAlignee)
            if !nonAlignees.isEmpty, nonAlignees.count == passages.count {
                throw LightroomError.plugin(nonAlignees[0].replacingOccurrences(of: "rien n'en est repris", with: "rien n'a été importé"))
            }
            let dans = modifications.count > 1 ? " dans aucune des zones" : (modifications[0].region == nil ? "" : " dans la zone")
            throw LightroomError.plugin("Fibo 2 n'a rien changé de visible\(dans) : rien n'a été importé. Reformuler l'instruction (plus précise, en anglais), ou changer seed.")
        }
        barre.montrer(.fin, "recomposition et importation", rang: nil, detail: nil)
        guard let finale = Generatif.recomposer(origine: origine, pieces: pieces) else {
            throw LightroomError.plugin("Recomposition impossible. Rien n'a été importé.")
        }
        let nom = Self.nomGenere(tiff)
        let cheminFinal = dossier.appendingPathComponent(nom + ".tif")
        try Generatif.ecrireTIFF(finale, proprietes: proprietes, metadonnees: Generatif.lireMetadonnees(tiff), vers: cheminFinal)
        // La croix a pu être cliquée pendant la recomposition et l'écriture (plusieurs secondes) :
        // relue juste avant l'importation.
        barre.relire()
        try contexte.verifier()

        // 5. La nouvelle photo au catalogue, empilée au-dessus de l'original (une seule importation).
        let importee = try lightroom.send("importerGeneree", [
            "photo": .number(Double(photo)),
            "chemin": .string(cheminFinal.path),
            "nom": .string(nom),
            "consigne": .string(consigne),
            "confirme": .bool(confirme),
        ], timeout: Self.importTimeout)
        guard let nouvelle = importee["id"]?.int else {
            throw LightroomError.plugin("Lightroom n'a pas rendu l'identifiant de la nouvelle photo.")
        }
        barre.terminer()

        // 6. La réponse.
        var nouvellePhoto: [String: JSONValue] = [
            "id": .number(Double(nouvelle)),
            "fichier": importee["fichier"] ?? .string(nom + ".tif"),
            "chemin": importee["chemin"] ?? .null,
            "empilee": importee["empilee"] ?? true,
            "active": importee["active"] ?? false,
        ]
        for cle in ["essai", "copie_virtuelle", "photo_fibo"] where importee[cle] != nil {
            nouvellePhoto[cle] = importee[cle]
        }
        var resultat: [String: JSONValue] = [
            "photo_origine": .number(Double(photo)),
            "nouvelle_photo": .object(nouvellePhoto),
            "modifications": .array(passages.map { Self.decrire($0) }),
            "qualite": .string(qualite.texte),
            "graine": .number(Double(graine)),
            "duree_s": .number(Date().timeIntervalSince(debut).rounded()),
            "duree_fibo_s": .number(dureeFibo.rounded()),
            "a_savoir": .string(Self.aSavoir(importee, id: nouvelle)),
        ]
        if mode == .fullAndCrop { resultat["contexte"] = .string(mode.rawValue) }
        let sansChangement = passages.filter { $0.piece == nil && $0.nonAlignee == nil }.map(\.modif.label)
        if !sansChangement.isEmpty {
            resultat["remarque_zones"] = .string("Fibo 2 n'a rien changé de visible pour « \(sansChangement.joined(separator: " », « ")) » : rien n'en est repris ; le redemander (instruction plus précise, ou autre seed) sur la nouvelle photo.")
        }
        let nonAlignees = passages.filter { $0.nonAlignee != nil }.map(\.modif.label)
        if !nonAlignees.isEmpty {
            resultat["remarque_alignement"] = .string("La sortie de Fibo 2 ne s'aligne pas sur le recadrage pour « \(nonAlignees.joined(separator: " », « ")) » : rien n'en est repris ; le redemander avec context = crop, ou une autre seed, sur la nouvelle photo.")
        }
        if let passage = passages.first, passages.count == 1,
           let remarque = Generatif.remarqueSortieEntiere(partChangee: passage.partChangee, sortieEntiere: passage.sortieEntiere) {
            resultat["sortie_entiere"] = true
            resultat["remarque"] = .string(remarque)
        }
        return .object(resultat)
    }

    /// Une modification dans la réponse : son nom, l'instruction anglaise, sa traduction, la part
    /// changée (de la photo), sa zone et son recadrage, la résolution de la zone et SeedVR2.
    private static func decrire(_ passage: Passage) -> JSONValue {
        let c = passage.cadre, t = passage.taille
        var objet: [String: JSONValue] = [
            "label": .string(passage.modif.label),
            "instruction": .string(passage.modif.instruction),
            "instruction_fr": .string(passage.modif.instructionFr),
            "reprise": .bool(passage.piece != nil),
            "part_changee_pct": .number((passage.partChangee * 1000).rounded() / 10),
            "seedvr2": .bool(passage.seedVRFait),
        ]
        if let region = passage.modif.region {
            objet["region"] = ["x": .number(region.minX), "y": .number(region.minY), "width": .number(region.width), "height": .number(region.height)]
            objet["recadrage_px"] = ["x": .number(Double(c.x)), "y": .number(Double(c.y)), "width": .number(Double(c.largeur)), "height": .number(Double(c.hauteur))]
        }
        let facteur = Generatif.facteur(cadre: c, taille: t)
        let quoi = passage.modif.region == nil ? "La zone changée vient de la sortie de Fibo 2, \(t.largeur) × \(t.hauteur) px, pour toute la photo, \(c.largeur) × \(c.hauteur) px"
            : "La zone vient de la sortie de Fibo 2, \(t.largeur) × \(t.hauteur) px, pour un recadrage de \(c.largeur) × \(c.hauteur) px de la photo"
        let comment: String
        if facteur <= 1.0001 {
            comment = " : à sa taille native, sans perte de détail."
        } else if passage.seedVRFait {
            comment = " (× \(nombre(facteur))) : remise à la taille par SeedVR2."
        } else {
            comment = " (× \(nombre(facteur))) : mise à la taille ordinaire, moins fine que le reste" + (passage.sortieEntiere ? "." : ", qui garde sa pleine résolution.")
        }
        objet["resolution_zone"] = .string(quoi + comment)
        if let remarque = passage.remarqueSeedVR { objet["remarque_seedvr2"] = .string(remarque) }
        if passage.piece == nil { objet["remarque"] = .string(passage.nonAlignee ?? "Fibo 2 n'a rien changé de visible ici : rien n'en est repris.") }
        return .object(objet)
    }

    /// SeedVR2 sur la sortie de Fibo : l'image remise à la taille native du recadrage, ou nil et la
    /// raison (absent, erreur, délai) ; l'annulation, elle, est levée.
    private func passerSeedVR(cheminSortie: URL, rang: Int, passage: Passage, graine: Int, dossier: URL, fibo: Fibo,
                              barre: inout BarreFibo) throws -> (CGImage?, String?) {
        let n = rang + 1
        let cible = dossier.appendingPathComponent("seedvr-\(n).png")
        let resolution = min(passage.cadre.largeur, passage.cadre.hauteur)
        let arguments = Generatif.argumentsSeedVR(entree: cheminSortie, resolution: resolution, graine: graine, sortie: cible)
        barre.montrer(.seedVR(rang, fraction: 0), passage.modif.label, rang: n, detail: "agrandissement (SeedVR2)")
        let suivi = SuiviProcessus()
        let copie = barre
        let fin = try executer(fibo.seedVR, arguments, dossier: dossier, delai: fibo.delaiMax, suivi: suivi,
                               lire: { ligne in
                                   guard let p = Generatif.progressionLibre(ligne) else { return false }
                                   suivi.noterFraction(fait: p.fait, total: p.total); return true
                               },
                               tic: { copie.montrer(.seedVR(rang, fraction: suivi.etat.fraction), passage.modif.label, rang: n, detail: "agrandissement (SeedVR2)") })
        let repli = " : mise à la taille ordinaire, moins de détail."
        switch fin {
        case .reussi:
            guard let image = Generatif.lireImage(cible)?.image else { return (nil, "SeedVR2 a fini sans image lisible" + repli) }
            return (image, nil)
        case .echec(let code, let journal):
            let fin = journal.split(separator: "\n").suffix(2).joined(separator: " ")
            return (nil, "SeedVR2 s'est arrêté avec une erreur (code \(code)\(fin.isEmpty ? "" : " : " + fin))" + repli)
        case .delai:
            return (nil, "SeedVR2 n'a pas fini en \(Int(fibo.delaiMax / 60)) min, arrêté" + repli)
        case .lancement(let raison):
            return (nil, "SeedVR2 ne se lance pas (\(raison))" + repli)
        }
    }

    /// L'étape que la fenêtre de la liaison montre pour une demande d'accord de la retouche générative.
    static let etapeFibo = "Claude · Fibo 2"

    /// Ce qu'il faut savoir de la nouvelle photo, d'après la réponse d'importerGeneree : empilée avec
    /// l'original, ou photo d'essai rangée dans « Développeur › Essais » sans pile ; sous « Copies
    /// virtuelles seulement », sa copie virtuelle, où se font les finitions.
    static func aSavoir(_ importee: JSONValue, id: Int) -> String {
        let rangement = importee["empilee"]?.bool == false
            ? "la nouvelle photo (une photo d'essai) est rangée dans « Développeur › Essais », sans pile avec l'original,"
            : "la nouvelle photo est empilée au-dessus de lui"
        let copie = importee["copie_virtuelle"]?.bool == true
            ? " ; « Copies virtuelles seulement » : sa copie virtuelle devient la photo active, et les finitions (apply_settings, add_mask…) se font sur la copie, par son id \(id)"
            : " et devient la photo active : les finitions (apply_settings, add_mask…) se font sur elle, par son id \(id)"
        return "L'original est intact ; " + rangement + copie + ". undo_last ne la retire pas (Photo › Retirer du catalogue, à la main). La vérifier avec view_photo."
    }

    /// Le nom de la nouvelle photo, sans extension : celui du TIFF exporté suivi de « -Fibo » (sans
    /// le doubler pour une photo déjà faite par Fibo 2).
    static func nomGenere(_ tiff: URL) -> String {
        var base = tiff.deletingPathExtension().lastPathComponent
        if let plage = base.range(of: #"-Fibo(-\d+)?$"#, options: .regularExpression) { base.removeSubrange(plage) }
        return (base.isEmpty ? "Photo" : base) + "-Fibo"
    }

    static func nombre(_ valeur: Double) -> String {
        String(format: "%.1f", valeur).replacingOccurrences(of: ".", with: ",")
    }

    /// L'image écrite par mflux : à `--output`, sinon un PNG apparu dans son dossier pendant son calcul.
    func sortieDeFibo(_ attendue: URL, dossier: URL, avant: Set<String>) -> URL {
        if FileManager.default.fileExists(atPath: attendue.path) { return attendue }
        let autres = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
        let png = autres.filter { $0.lowercased().hasSuffix(".png") && !avant.contains($0) }.sorted()
        return png.first.map { dossier.appendingPathComponent($0) } ?? attendue
    }

    /// Lance un processus (mflux ou SeedVR2) avec l'environnement de Fibo (télémétrie de Hugging
    /// Face coupée, sortie Python sans tampon, PATH de ce Mac), lit sa sortie ligne à ligne (`lire`
    /// rend vrai pour une ligne d'avancée, qui ne va pas au journal), appelle `tic` toutes les 0,25 s
    /// (la barre), l'arrête si l'appel est annulé (client, croix de la barre : levé) ou s'il dépasse
    /// le délai (`.delai`).
    func executer(_ executable: URL, _ arguments: [String], dossier: URL, delai: TimeInterval, suivi: SuiviProcessus,
                  lire: @escaping (String) -> Bool, tic: () -> Void) throws -> FinProcessus {
        let processus = Process()
        processus.executableURL = executable
        processus.arguments = arguments
        var environnement = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environnement["PATH"] = [executable.deletingLastPathComponent().path, home + "/.local/bin", "/opt/homebrew/bin",
                                 "/usr/bin", "/bin", "/usr/sbin", "/sbin"].joined(separator: ":")
        environnement["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environnement["PYTHONUNBUFFERED"] = "1"
        // En ligne : un modèle manquant se télécharge au premier usage.
        environnement.removeValue(forKey: "HF_HUB_OFFLINE")
        processus.environment = environnement
        processus.currentDirectoryURL = dossier
        // stdin et stdout du serveur sont au protocole : le processus n'en voit rien.
        processus.standardInput = FileHandle.nullDevice
        let tuyau = Pipe()
        processus.standardOutput = tuyau
        processus.standardError = tuyau

        let verrou = NSLock()
        var lignes = Generatif.Lignes()
        var journal = ""
        func lireTexte(_ texte: String, fin: Bool = false) {
            verrou.lock(); defer { verrou.unlock() }
            for ligne in lignes.ajouter(texte) + (fin ? lignes.finir() : []) {
                if !lire(ligne), !ligne.contains("Redirects are currently not supported") {
                    journal += ligne + "\n"
                    if journal.count > 20_000 { journal = String(journal.suffix(15_000)) }
                }
            }
        }
        // Un seul lecteur : le gestionnaire lit jusqu'à la fin du tuyau, puis le signale (jamais un
        // readDataToEndOfFile en même temps, qui mêlerait l'ordre des morceaux du journal).
        let finLecture = DispatchSemaphore(value: 0)
        tuyau.fileHandleForReading.readabilityHandler = { poignee in
            let donnees = poignee.availableData
            guard !donnees.isEmpty else {
                poignee.readabilityHandler = nil
                finLecture.signal()
                return
            }
            lireTexte(String(decoding: donnees, as: UTF8.self))
        }
        let fini = DispatchSemaphore(value: 0)
        processus.terminationHandler = { _ in fini.signal() }
        do {
            try processus.run()
            travailFibo.lancer(processus)
        } catch {
            tuyau.fileHandleForReading.readabilityHandler = nil
            return .lancement(error.localizedDescription)
        }
        func arreter() {
            processus.terminate()
            if fini.wait(timeout: .now() + 3) == .timedOut {
                kill(processus.processIdentifier, SIGKILL)
                _ = fini.wait(timeout: .now() + 3)
            }
            tuyau.fileHandleForReading.readabilityHandler = nil
        }
        while fini.wait(timeout: .now() + 0.25) == .timedOut {
            tic()
            do {
                try contexte.verifier()
            } catch {
                arreter()
                throw error
            }
            if Date().timeIntervalSince(suivi.debut) > delai {
                arreter()
                return .delai
            }
        }
        // La fin du tuyau (un petit-enfant qui le garderait ouvert : 2 s au plus), puis le reste de
        // la dernière ligne.
        if finLecture.wait(timeout: .now() + 2) == .timedOut { tuyau.fileHandleForReading.readabilityHandler = nil }
        lireTexte("", fin: true)
        guard processus.terminationReason == .exit, processus.terminationStatus == 0 else {
            verrou.lock(); let texte = journal; verrou.unlock()
            return .echec(code: processus.terminationStatus, journal: texte)
        }
        return .reussi
    }
}

/// La barre de progression de tout l'appel (client et Lightroom, par `avancer`) : un pourcentage de
/// 0 à 100, qui ne redescend jamais, et son texte, envoyés quand l'un ou l'autre change, et au
/// moins toutes les `relecture` secondes même sans changement : la croix de Lightroom ne se lit que
/// dans la réponse de la commande progression (un chargement du modèle, un premier téléchargement
/// ou SeedVR2 restent longtemps sur le même texte).
struct BarreFibo {
    unowned let handler: ToolHandler
    var avancement: Generatif.Avancement
    let nombre: Int
    private let dernier = Dernier()
    static let relecture: TimeInterval = 3
    static let titre = "Fibo 2"

    init(handler: ToolHandler, avancement: Generatif.Avancement, nombre: Int) {
        self.handler = handler
        self.avancement = avancement
        self.nombre = nombre
    }

    private final class Dernier {
        var texte = ""
        var pourcentage = 0
        var envoi = Date.distantPast
    }

    func montrer(_ phase: Generatif.Avancement.Phase, _ quoi: String, rang: Int?, detail: String?) {
        let pourcentage = max(dernier.pourcentage, avancement.pourcentage(phase))
        let texte = Generatif.texteProgression(quoi, rang: rang, sur: nombre, pourcentage: pourcentage, detail: detail)
        guard texte != dernier.texte || Date().timeIntervalSince(dernier.envoi) >= Self.relecture else { return }
        envoyer(pourcentage, texte)
    }

    /// Relit la croix de Lightroom : la dernière progression renvoyée telle quelle.
    func relire() {
        guard !dernier.texte.isEmpty else { return }
        envoyer(dernier.pourcentage, dernier.texte)
    }

    /// La fin : 100 %, une fois la nouvelle photo au catalogue.
    func terminer() {
        envoyer(100, "Fibo 2 : terminé, 100 %")
    }

    private func envoyer(_ pourcentage: Int, _ texte: String) {
        dernier.texte = texte
        dernier.pourcentage = pourcentage
        dernier.envoi = Date()
        handler.avancer(pourcentage, sur: 100, texte, titre: Self.titre)
    }
}
