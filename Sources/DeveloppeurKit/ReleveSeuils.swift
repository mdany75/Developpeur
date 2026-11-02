import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Le relevé des seuils provisoires (1.6, chantier « seuils », développement seulement :
/// `mcp-developpeur --mesures`). Rien n'y change une constante : il prépare les mesures dont un
/// compte rendu tirera les valeurs (liste des seuils, commandes et règles de décision :
/// `docs/SPEC.md`, Relevé des seuils provisoires). Quatre temps, chacun sa sous-commande :
///
/// 1. `--echantillons <suivi.json> <dossier>` : tire les lots de photos dans le relevé du Suivi,
///    lu seulement (originaux Fujifilm, sans les photos retouchées par Claude), au hasard mais de
///    façon reproductible (graine fixe). Ni Lightroom ni image.
/// 2. `--collecter <lot.json> <dossier>` : demande au module les vignettes du lot (commande
///    `vignettes`, par lots de 10 à 20, 1 024 px par défaut), les copie dans le dossier puis retire
///    les JPEG temporaires du module ; garde ce que le catalogue dit de chaque photo (heure exacte,
///    ISO, ouverture, vitesse, compensation, flash : la description de `vignettes`, pas
///    `suivi.json`, qui est à la minute et sans compensation ni flash) et si sa note vient de Claude
///    (commande `journal`). Deux lectures seulement : rien n'est écrit dans le catalogue ; Lightroom
///    peut rendre un aperçu qui manque.
/// 3. `--mesurer <dossier>` : mesure les vignettes copiées, sans Lightroom : les mesures du Suivi
///    (`Suivi.analyserPhoto`), l'écrêtage par la gamme rejoué à d'autres bornes, les points chauds
///    rejoués à d'autres seuils, la peau du plus grand visage (Teint), et, d'une photo à la suivante
///    d'un même groupe, la pause, l'écart de lumière, le flash, la distance des empreintes de Vision,
///    l'écart de la peau et les groupes de lumière de `match_series`. Sortie : `mesures.jsonl`,
///    `mesures.csv`, `paires.csv`, `resume.txt` et `resume.json`.
/// 4. `--fichiers <dossier> <fichier.jpg>…` : la même mesure sur des fichiers quelconques, sans
///    catalogue.
public enum ReleveSeuils {
    /// Les boîtiers relevés (ceux de Dany).
    public static let appareils = ["X-H2S", "X-T4", "X-T20"]
    /// Les tranches ISO du relevé du bruit (A1).
    public static let tranchesISO: [(nom: String, min: Double, max: Double)] = [
        ("moins de 800", 0, 800), ("800-1599", 800, 1600), ("1600-3199", 1600, 3200),
        ("3200-6399", 3200, 6400), ("6400 et plus", 6400, .infinity),
    ]
    /// Photos par commande `vignettes` (critique du plan : 50 dépassaient le délai du module quand
    /// des aperçus manquent).
    public static let parLotMin = 10, parLotMax = 20, parLotDefaut = 15
    public static let tailleDefaut = 1024, tailleMin = 128, tailleMax = 2048
    public static let graineDefaut: UInt64 = 20_261_101
    /// Délai d'une commande `vignettes` (le module attend 60 s au plus les rappels de Lightroom).
    static let delaiVignettes: TimeInterval = 120
    /// Lots qui échouent de suite avant d'abandonner la collecte (liaison arrêtée, Lightroom fermé).
    static let echecsDeSuiteMax = 3

    /// Bornes rejouées de l'écrêtage par la gamme (A4) : le canal le plus bas, puis C*.
    static let basesGamme: [UInt8] = [200, 210, 220, 230, 240]
    static let chromasGamme: [Double] = [20, 25, 30, 35, 40]
    /// Seuils rejoués des points chauds (A5).
    static let ecartsChauds: [Double] = [15, 20, 25]
    static let lMinsChauds: [Double] = [65, 70, 75]
    static let partsMinChaudes: [Double] = [0.2, 0.3, 0.5]
    static let partsMaxChaudes: [Double] = [15, 20, 30]

    /// Une sortie de la commande : ses lignes (pour la console) et son code (0 réussi, 1 échec,
    /// 2 arguments).
    public struct Sortie {
        public var lignes: [String]
        public var code: Int32
    }

    // MARK: Commande

    /// `--mesures <sous-commande> …` : les arguments après `--mesures`. `lightroom` n'est appelé que
    /// par `--collecter`.
    public static func commande(_ arguments: [String], lightroom: () -> LightroomServing,
                                ecrire: (String) -> Void = { _ in }) -> Sortie {
        var lignes: [String] = []
        func dire(_ ligne: String) { lignes.append(ligne); ecrire(ligne) }
        func refus(_ texte: String) -> Sortie { dire("✘ \(texte)"); dire(aide); return Sortie(lignes: lignes, code: 2) }
        var rest = arguments
        guard let mode = rest.first else { return refus("--mesures attend une sous-commande.") }
        rest.removeFirst()
        // Options communes : --graine, --taille, --par.
        var graine = graineDefaut, taille = tailleDefaut, parLot = parLotDefaut
        var positionnels: [String] = []
        while !rest.isEmpty {
            let item = rest.removeFirst()
            switch item {
            case "--graine", "--taille", "--par":
                guard let valeur = rest.first.flatMap({ Int($0) }) else { return refus("\(item) attend un nombre entier.") }
                rest.removeFirst()
                if item == "--graine" { graine = UInt64(max(0, valeur)) }
                if item == "--taille" { taille = valeur }
                if item == "--par" { parLot = valeur }
            default:
                positionnels.append(item)
            }
        }
        guard (tailleMin...tailleMax).contains(taille) else { return refus("--taille : de \(tailleMin) à \(tailleMax) px.") }
        guard (parLotMin...parLotMax).contains(parLot) else {
            return refus("--par : de \(parLotMin) à \(parLotMax) photos par commande vignettes.")
        }
        do {
            switch mode {
            case "--echantillons":
                guard positionnels.count == 2 else { return refus("--echantillons <suivi.json> <dossier>") }
                let donnees = try Data(contentsOf: URL(fileURLWithPath: positionnels[0]))
                let suivi = try JSONCoding.parse(donnees)
                let lots = echantillons(suivi, graine: graine)
                try ecrireLots(lots, graine: graine, dans: URL(fileURLWithPath: positionnels[1]), dire: dire)
            case "--collecter":
                guard positionnels.count == 2 else { return refus("--collecter <lot.json> <dossier>") }
                let lot = try JSONCoding.parse(Data(contentsOf: URL(fileURLWithPath: positionnels[0])))
                let bilan = try collecter(lot: lot, dans: URL(fileURLWithPath: positionnels[1]), lightroom: lightroom(),
                                          taille: taille, parLot: parLot, dire: dire)
                return Sortie(lignes: lignes, code: bilan.abandon ? 1 : 0)
            case "--mesurer":
                guard positionnels.count == 1 else { return refus("--mesurer <dossier>") }
                let dossier = URL(fileURLWithPath: positionnels[0])
                let entrees = try lireCatalogue(dossier)
                guard !entrees.isEmpty else { dire("✘ Aucune vignette dans \(dossier.path) (catalogue.jsonl vide ou absent)."); return Sortie(lignes: lignes, code: 1) }
                try mesurerEtEcrire(entrees, dans: dossier, dire: dire)
            case "--fichiers":
                guard positionnels.count >= 2 else { return refus("--fichiers <dossier> <fichier.jpg>…") }
                let dossier = URL(fileURLWithPath: positionnels[0])
                let entrees = positionnels.dropFirst().map { chemin in
                    Entree(fichier: URL(fileURLWithPath: chemin), meta: ["fichier": .string(URL(fileURLWithPath: chemin).lastPathComponent)])
                }
                try mesurerEtEcrire(Array(entrees), dans: dossier, dire: dire)
            default:
                return refus("Sous-commande inconnue : \(mode).")
            }
        } catch {
            dire("✘ \(error.localizedDescription)")
            return Sortie(lignes: lignes, code: 1)
        }
        return Sortie(lignes: lignes, code: 0)
    }

    public static let aide = """
    mcp-developpeur --mesures --echantillons <suivi.json> <dossier> [--graine <n>]
    mcp-developpeur --mesures --collecter <lot.json> <dossier> [--taille <px, 1024>] [--par <10 à 20, 15>]
    mcp-developpeur --mesures --mesurer <dossier>
    mcp-developpeur --mesures --fichiers <dossier> <fichier.jpg>…
    """

    // MARK: 1. Échantillons

    /// Une photo du relevé du Suivi, candidate à un lot.
    struct Candidate: Equatable {
        var id: Int
        var appareil: String
        var iso: Double?
        /// « 2015-07-25 18:08 » (à la minute) ; seulement pour tirer.
        var le: String?
        var note: Int?
        var genre: String?
        var cherches: Set<String>
        var defauts: Set<String>

        var jour: String? { le.map { String($0.prefix(10)) }.flatMap { $0.count == 10 ? $0 : nil } }
        var heure: Int? {
            guard let le, le.count >= 13 else { return nil }
            return Int(le.dropFirst(11).prefix(2))
        }
        /// Minutes depuis minuit.
        var minute: Int? {
            guard let le, le.count >= 16, let h = Int(le.dropFirst(11).prefix(2)), let m = Int(le.dropFirst(14).prefix(2)) else { return nil }
            return h * 60 + m
        }
    }

    /// Un lot tiré : son nom, ce qu'il sert à relever, et ses photos, chacune dans un groupe.
    struct Lot {
        var nom: String
        var but: String
        var photos: [(photo: Candidate, groupe: String)]
    }

    /// Le nom du boîtier relevé (« X-H2S »), ou nil pour un autre (« FUJIFILM X-H2S » compris).
    static func appareilReleve(_ texte: String?) -> String? {
        guard var nom = texte?.uppercased() else { return nil }
        nom = nom.replacingOccurrences(of: "FUJIFILM", with: "").trimmingCharacters(in: .whitespaces)
        return appareils.first { $0 == nom }
    }

    /// Les originaux Fujifilm du relevé du Suivi, triés par id, sans ceux que Claude a retouchés.
    static func candidates(_ suivi: JSONValue) -> [Candidate] {
        var liste: [Candidate] = []
        for (_, catalogue) in suivi["catalogues"]?.object ?? [:] {
            for (cle, entree) in catalogue["photos"]?.object ?? [:] {
                guard entree["retouchee_par_claude"]?.bool != true,
                      let id = entree["original"]?.int ?? Int(cle),
                      let appareil = appareilReleve(entree["prise_de_vue"]?["appareil"]?.string) else { continue }
                let analyse = entree["analyse"]
                liste.append(Candidate(id: id, appareil: appareil, iso: entree["prise_de_vue"]?["iso"]?.double,
                                       le: entree["prise_de_vue"]?["le"]?.string, note: entree["note"]?.int,
                                       genre: analyse?["genre"]?.string,
                                       cherches: Set((analyse?["cherches"]?.array ?? []).compactMap(\.string)),
                                       defauts: Set((analyse?["defauts"]?.array ?? []).compactMap(\.string))))
            }
        }
        return liste.sorted { $0.id < $1.id }
    }

    /// Un hasard reproductible (SplitMix64).
    struct Hasard {
        var etat: UInt64
        mutating func suivant() -> UInt64 {
            etat &+= 0x9E37_79B9_7F4A_7C15
            var z = etat
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func melanger<T>(_ liste: [T]) -> [T] {
            var copie = liste
            guard copie.count > 1 else { return copie }
            for i in stride(from: copie.count - 1, to: 0, by: -1) {
                let j = Int(suivant() % UInt64(i + 1))
                copie.swapAt(i, j)
            }
            return copie
        }
        mutating func tirer<T>(_ liste: [T], _ nombre: Int) -> [T] { Array(melanger(liste).prefix(max(0, nombre))) }
    }

    static func tranche(_ iso: Double?) -> String? {
        guard let iso else { return nil }
        return tranchesISO.first { iso >= $0.min && iso < $0.max }?.nom
    }

    /// Les lots du relevé (le plan, corrigé par sa critique) : A1 bruit par boîtier et tranche ISO
    /// (le X-T4 compris), A2 sous-exposition, A3 ciel brûlé, A4 couleurs hors gamme, A5 points chauds,
    /// A6 journées entières (groupes de lumière), A7 candidates de l'éclairage mixte (à trier à
    /// l'œil), A8 suites de portraits (teint). Une photo n'est qu'une fois dans un lot.
    static func echantillons(_ suivi: JSONValue, graine: UInt64) -> [Lot] {
        let tout = candidates(suivi)
        var lots: [Lot] = []
        func nouveau(_ nom: String, _ but: String, _ remplir: (inout Hasard, inout [(photo: Candidate, groupe: String)], (Candidate) -> Bool) -> Void) {
            var hasard = Hasard(etat: graine &+ UInt64(lots.count + 1) &* 0x2545_F491_4F6C_DD1D)
            var photos: [(photo: Candidate, groupe: String)] = []
            var pris = Set<Int>()
            remplir(&hasard, &photos) { photo in pris.insert(photo.id).inserted }
            // `prendre` dit si la photo n'était pas déjà du lot ; seules les nouvelles y entrent.
            lots.append(Lot(nom: nom, but: but, photos: photos))
        }
        func ajouter(_ choisies: [Candidate], _ groupe: String, _ photos: inout [(photo: Candidate, groupe: String)],
                     _ prendre: (Candidate) -> Bool) {
            for photo in choisies where prendre(photo) { photos.append((photo, groupe)) }
        }
        func libres(_ liste: [Candidate], _ photos: [(photo: Candidate, groupe: String)]) -> [Candidate] {
            let deja = Set(photos.map(\.photo.id))
            return liste.filter { !deja.contains($0.id) }
        }

        nouveau("A1", "Bruit selon l'ISO (Carnet.isoEleve) : bruit de --analyser par boîtier et tranche ISO.") { hasard, photos, prendre in
            for appareil in appareils {
                for t in tranchesISO {
                    let liste = tout.filter { $0.appareil == appareil && tranche($0.iso) == t.nom }
                    ajouter(hasard.tirer(liste, 120), "\(appareil) ISO \(t.nom)", &photos, prendre)
                }
            }
        }
        nouveau("A2", "Sous-exposition (Carnet.medianeSousExposee, p95SousExposee) : signalées, bien notées, et non signalées.") { hasard, photos, prendre in
            let base = tout.filter { $0.cherches.contains("sous_exposition") }
            let signalees = base.filter { $0.defauts.contains("sous_exposition") }
            ajouter(hasard.melanger(signalees.filter { ($0.note ?? 0) >= 3 }), "signalée, 3 étoiles ou plus", &photos, prendre)
            ajouter(hasard.tirer(libres(signalees.filter { $0.appareil == "X-H2S" && tranche($0.iso) == "3200-6399" }, photos), 100),
                    "signalée, X-H2S ISO 3200-6399", &photos, prendre)
            ajouter(hasard.tirer(libres(signalees, photos), 200), "signalée", &photos, prendre)
            ajouter(hasard.tirer(base.filter { !$0.defauts.contains("sous_exposition") }, 200), "non signalée", &photos, prendre)
        }
        nouveau("A3", "Ciel brûlé (Carnet.partBlancPurHaut) : signalées et paysages non signalés.") { hasard, photos, prendre in
            let base = tout.filter { $0.cherches.contains("ciel_brule") }
            ajouter(hasard.tirer(base.filter { $0.defauts.contains("ciel_brule") }, 600), "signalée", &photos, prendre)
            ajouter(hasard.tirer(base.filter { !$0.defauts.contains("ciel_brule") && $0.genre == "paysage" }, 200),
                    "paysage non signalé", &photos, prendre)
        }
        nouveau("A4", "Couleurs hors gamme (PhotoMeasurements.basGamme, chromaGamme, ecretageMin, natureNette).") { hasard, photos, prendre in
            ajouter(hasard.tirer(tout.filter { $0.genre == "macro" }, 190), "macro", &photos, prendre)
            ajouter(hasard.tirer(tout.filter { $0.genre == "paysage" && (17...20).contains($0.heure ?? -1) }, 150),
                    "paysage de 17 h à 21 h", &photos, prendre)
            ajouter(hasard.tirer(tout.filter { $0.genre == "sport" || $0.genre == "evenement" }, 150), "sport ou événement", &photos, prendre)
            ajouter(hasard.tirer(tout.filter { $0.genre == "portrait" }, 100), "portrait témoin", &photos, prendre)
        }
        nouveau("A5", "Points chauds (PointsChauds.ecartMediane, lMin, partMin, partMax) : à juger par Dany.") { hasard, photos, prendre in
            let gens = tout.filter { $0.genre == "famille" || $0.genre == "portrait" }
            let bienNotes = hasard.melanger(gens.filter { ($0.note ?? 0) >= 3 })
            ajouter(Array((bienNotes + hasard.melanger(gens.filter { ($0.note ?? 0) < 3 })).prefix(200)), "famille ou portrait", &photos, prendre)
            ajouter(hasard.tirer(tout.filter { $0.genre == "paysage" }, 50), "paysage", &photos, prendre)
        }
        nouveau("A6", "Groupes de lumière (GroupesLumiere.pauseMax, pauseMemeLieu, distanceMemeLieu, ecartIL) : journées entières du X-H2S.") { hasard, photos, prendre in
            var parJour: [String: [Candidate]] = [:]
            for photo in tout where photo.appareil == "X-H2S" && photo.jour != nil { parJour[photo.jour!, default: []].append(photo) }
            let jours = parJour.keys.filter { parJour[$0]!.count >= 40 }.sorted()
            for jour in hasard.tirer(jours, 10).sorted() {
                let suite = parJour[jour]!.sorted { ($0.le ?? "", $0.id) < ($1.le ?? "", $1.id) }
                ajouter(Array(suite.prefix(150)), "jour \(jour)", &photos, prendre)
            }
        }
        nouveau("A7", "Éclairage mixte (Eclairage.seuilTonal, partMinGroupe) : candidates à trier à l'œil sur des planches (lampe et fenêtre, soleil et ombre, une seule lumière).") { hasard, photos, prendre in
            let interieur = tout.filter { ["famille", "portrait", "evenement", "nourriture"].contains($0.genre ?? "") && (17...22).contains($0.heure ?? -1) }
            ajouter(hasard.tirer(interieur, 120), "soirée, gens ou repas (lampe probable)", &photos, prendre)
            let jour = tout.filter { ["famille", "portrait", "paysage"].contains($0.genre ?? "") && (10...14).contains($0.heure ?? -1) }
            ajouter(hasard.tirer(jour, 60), "de 10 h à 15 h (soleil probable)", &photos, prendre)
        }
        nouveau("A8", "Teint (Teint.ecartVisible, hausseAlerte) : suites de portraits, 3 photos ou plus à moins de 2 min l'une de l'autre.") { hasard, photos, prendre in
            var parJour: [String: [Candidate]] = [:]
            for photo in tout where (photo.genre == "portrait" || photo.genre == "famille") && photo.jour != nil && photo.minute != nil {
                parJour["\(photo.appareil) \(photo.jour!)", default: []].append(photo)
            }
            var suites: [[Candidate]] = []
            for cle in parJour.keys.sorted() {
                let liste = parJour[cle]!.sorted { ($0.minute!, $0.id) < ($1.minute!, $1.id) }
                var courante: [Candidate] = []
                for photo in liste {
                    if let derniere = courante.last, photo.minute! - derniere.minute! > 2 {
                        if courante.count >= 3 { suites.append(courante) }
                        courante = []
                    }
                    courante.append(photo)
                }
                if courante.count >= 3 { suites.append(courante) }
            }
            for (n, suite) in hasard.tirer(suites, 40).enumerated() {
                let premiere = suite[0]
                ajouter(Array(suite.prefix(6)), "suite \(n + 1) (\(premiere.appareil) \(premiere.le ?? ""))", &photos, prendre)
            }
        }
        return lots
    }

    static func json(_ lot: Lot, graine: UInt64) -> JSONValue {
        [
            "lot": .string(lot.nom), "but": .string(lot.but), "graine": .number(Double(graine)),
            "photos": .array(lot.photos.map { element in
                var objet: [String: JSONValue] = ["id": .number(Double(element.photo.id)), "groupe": .string(element.groupe),
                                                  "appareil": .string(element.photo.appareil)]
                if let iso = element.photo.iso { objet["iso"] = .number(iso) }
                if let le = element.photo.le { objet["le"] = .string(le) }
                if let note = element.photo.note { objet["note_suivi"] = .number(Double(note)) }
                if let genre = element.photo.genre { objet["genre"] = .string(genre) }
                objet["defauts_suivi"] = .array(element.photo.defauts.sorted().map(JSONValue.string))
                return .object(objet)
            }),
        ]
    }

    static func ecrireLots(_ lots: [Lot], graine: UInt64, dans dossier: URL, dire: (String) -> Void) throws {
        let dossierLots = dossier.appendingPathComponent("lots")
        try FileManager.default.createDirectory(at: dossierLots, withIntermediateDirectories: true)
        var texte: [String] = ["Échantillons du relevé des seuils (graine \(graine)), tirés de suivi.json, lu seulement :",
                               "originaux \(appareils.joined(separator: ", ")) sans les photos retouchées par Claude."]
        for lot in lots {
            let fichier = dossierLots.appendingPathComponent("\(lot.nom).json")
            try Data(JSONCoding.pretty(json(lot, graine: graine)).utf8).write(to: fichier)
            texte.append("")
            texte.append("\(lot.nom) : \(lot.photos.count) photos — \(lot.but)")
            var ordre: [String] = [], compte: [String: Int] = [:]
            for element in lot.photos {
                if compte[element.groupe] == nil { ordre.append(element.groupe) }
                compte[element.groupe, default: 0] += 1
            }
            for groupe in ordre {
                let n = compte[groupe]!
                texte.append("  \(groupe) : \(n)\(n < 30 ? " (moins de 30 : le seuil resterait provisoire)" : "")")
            }
        }
        try Data((texte.joined(separator: "\n") + "\n").utf8).write(to: dossier.appendingPathComponent("echantillons.txt"))
        texte.forEach(dire)
        dire("Lots écrits dans \(dossierLots.path)")
    }

    // MARK: 2. Collecte

    public struct BilanCollecte: Equatable {
        public var photos = 0
        public var copiees = 0
        public var dejaLa = 0
        public var erreurs = 0
        public var notesDeClaude = 0
        public var abandon = false
    }

    /// La note de la photo vient-elle de Claude ? Une entrée de son journal (`journal` du module :
    /// type `classement`) qui change la note (`propose_ratings`, `set_metadata`, la carte Note).
    /// Les notes que Dany pose lui-même dans Lightroom n'y sont jamais.
    static func noteParClaude(_ entrees: [JSONValue]) -> Bool {
        entrees.contains { entree in
            entree["type"]?.string == "classement"
                && (entree["changements"]?.array ?? []).contains { ["note", "rating"].contains($0["cle"]?.string ?? "") }
        }
    }

    static func nombre(_ valeur: Double?) -> JSONValue { valeur.map { $0.isFinite ? JSONValue.number($0) : .null } ?? .null }

    /// Le grand côté d'un JPEG, lu dans son en-tête.
    static func cote(_ donnees: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(donnees as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let l = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return max(l, h)
    }

    /// Ce que la collecte garde d'une photo : son lot et son groupe, la description du module
    /// (heure exacte, prise de vue en nombres), la note et qui l'a posée, la vignette copiée.
    static func ligneCatalogue(id: Int, lot: String, groupe: String?, description: JSONValue?, notePosee: Bool,
                               vignette: String?, cote: Int?, taille: Int, erreur: String?, duree: Double) -> JSONValue {
        var objet: [String: JSONValue] = ["id": .number(Double(id)), "lot": .string(lot), "taille": .number(Double(taille)),
                                          "duree_lot_s": .number((duree * 10).rounded() / 10)]
        if let groupe { objet["groupe"] = .string(groupe) }
        if let d = description {
            for cle in ["fichier", "appareil", "objectif", "date", "format"] { if let v = d[cle]?.string { objet[cle] = .string(v) } }
            let dateLue = Tri.date(d["date"]?.string)
            objet["date_secondes"] = .bool(dateLue != nil)
            if let s = d["sensibilite"]?.double { objet["iso"] = .number(s) }
            let prise = d["prise_de_vue"]
            objet["ouverture"] = nombre(prise?["ouverture"]?.double)
            objet["vitesse"] = nombre(prise?["vitesse"]?.double)
            objet["compensation"] = nombre(prise?["compensation"]?.double)
            if let flash = prise?["flash"]?.bool { objet["flash"] = .bool(flash) }
            var photo = PhotoTriee(id: id, fichier: d["fichier"]?.string ?? "")
            photo.date = dateLue
            objet["lumiere_il"] = nombre(ToolHandler.prise(d, photo: photo).lumiere.map { ($0 * 100).rounded() / 100 })
            if let note = d["note"]?.int { objet["note"] = .number(Double(note)) }
            objet["retouchee_par_claude"] = .bool(d["retouchee_par_claude"]?.bool == true)
        }
        objet["note_par_claude"] = .bool(notePosee)
        if let vignette { objet["vignette"] = .string(vignette) }
        if let cote { objet["cote"] = .number(Double(cote)) }
        if let erreur { objet["erreur"] = .string(erreur) }
        return .object(objet.filter { !$0.value.isNull })
    }

    /// `--collecter` : les vignettes du lot, par commandes de `parLot` photos, copiées dans
    /// `<dossier>/vignettes/<taille>/<id>.jpg`, le JPEG temporaire du module retiré aussitôt (et son
    /// dossier s'il est vide) ; une ligne par photo dans `<dossier>/catalogue.jsonl`. Une photo déjà
    /// copiée à cette taille (`catalogue.jsonl` et fichier présents) n'est pas redemandée : la
    /// collecte se reprend. Seules commandes : `vignettes` et `journal` (des lectures).
    static func collecter(lot: JSONValue, dans dossier: URL, lightroom: LightroomServing, taille: Int, parLot: Int,
                          dire: (String) -> Void) throws -> BilanCollecte {
        let nomLot = lot["lot"]?.string ?? "lot"
        var groupes: [Int: String] = [:], ids: [Int] = []
        for element in lot["photos"]?.array ?? [] {
            guard let id = element["id"]?.int ?? element.int, groupes[id] == nil, !ids.contains(id) else { continue }
            ids.append(id)
            if let groupe = element["groupe"]?.string { groupes[id] = groupe }
        }
        guard !ids.isEmpty else { throw LightroomError.invalid("Le lot n'a aucune photo (photos : [{id, groupe}, …]).") }
        let fm = FileManager.default
        let relatif = "vignettes/\(taille)"
        let dossierVignettes = dossier.appendingPathComponent(relatif)
        try fm.createDirectory(at: dossierVignettes, withIntermediateDirectories: true)
        let catalogue = dossier.appendingPathComponent("catalogue.jsonl")
        var deja = Set<Int>()
        for entree in (try? lireLignes(catalogue)) ?? [] where entree["taille"]?.int == taille && entree["vignette"] != nil {
            if let id = entree["id"]?.int, let chemin = entree["vignette"]?.string,
               fm.fileExists(atPath: dossier.appendingPathComponent(chemin).path) { deja.insert(id) }
        }
        if !fm.fileExists(atPath: catalogue.path) { fm.createFile(atPath: catalogue.path, contents: nil) }
        let sortie = try FileHandle(forWritingTo: catalogue)
        defer { try? sortie.close() }
        sortie.seekToEndOfFile()

        var bilan = BilanCollecte()
        bilan.dejaLa = ids.filter(deja.contains).count
        let aFaire = ids.filter { !deja.contains($0) }
        bilan.photos = aFaire.count
        let nombreLots = (aFaire.count + parLot - 1) / parLot
        dire("Collecte du lot \(nomLot) : \(aFaire.count) photo(s) à demander en \(nombreLots) commande(s) de \(parLot) au plus, à \(taille) px"
            + (bilan.dejaLa > 0 ? " (\(bilan.dejaLa) déjà copiée(s), reprises telles quelles)" : "") + ".")
        var echecsDeSuite = 0
        for (rang, debut) in stride(from: 0, to: aFaire.count, by: parLot).enumerated() {
            let lotIds = Array(aFaire[debut..<min(debut + parLot, aFaire.count)])
            let depart = Date()
            var lignes: [JSONValue] = []
            do {
                let reponse = try lightroom.send("vignettes", ["photos": .array(lotIds.map { .number(Double($0)) }), "taille": .number(Double(taille))],
                                                 timeout: delaiVignettes)
                var notes: [Int: Bool] = [:]
                if let journal = try? lightroom.send("journal", ["photos": .array(lotIds.map { .number(Double($0)) })], timeout: 60) {
                    for photo in journal["photos"]?.array ?? [] {
                        if let id = photo["photo"]?["id"]?.int { notes[id] = noteParClaude(photo["entrees"]?.array ?? []) }
                    }
                }
                let duree = Date().timeIntervalSince(depart)
                var vues = Set<Int>()
                for item in reponse["photos"]?.array ?? [] {
                    guard let id = item["id"]?.int else { continue }
                    vues.insert(id)
                    var erreur = item["erreur"]?.string, chemin: String?, cote: Int?
                    if let temporaire = item["vignette"]?.string {
                        do {
                            // readPreview lit puis retire le JPEG du module (et son dossier, vide).
                            let donnees = try ToolHandler.readPreview(temporaire)
                            let nom = "\(relatif)/\(id).jpg"
                            try donnees.write(to: dossier.appendingPathComponent(nom))
                            chemin = nom
                            cote = Self.cote(donnees)
                            bilan.copiees += 1
                        } catch {
                            erreur = error.localizedDescription
                        }
                    }
                    if chemin == nil { bilan.erreurs += 1; erreur = erreur ?? "pas de vignette" }
                    if notes[id] == true { bilan.notesDeClaude += 1 }
                    lignes.append(ligneCatalogue(id: id, lot: nomLot, groupe: groupes[id], description: item, notePosee: notes[id] == true,
                                                 vignette: chemin, cote: cote, taille: taille, erreur: erreur, duree: duree))
                }
                for id in lotIds where !vues.contains(id) {
                    bilan.erreurs += 1
                    lignes.append(ligneCatalogue(id: id, lot: nomLot, groupe: groupes[id], description: nil, notePosee: notes[id] == true,
                                                 vignette: nil, cote: nil, taille: taille, erreur: "absente de la réponse du module", duree: duree))
                }
                echecsDeSuite = 0
                dire(String(format: "lot %d/%d : %d photo(s), %d vignette(s) copiée(s) en %.1f s", rang + 1, nombreLots, lotIds.count,
                            lignes.filter { $0["vignette"] != nil }.count, duree).replacingOccurrences(of: ".", with: ","))
            } catch {
                echecsDeSuite += 1
                bilan.erreurs += lotIds.count
                lignes = lotIds.map { ligneCatalogue(id: $0, lot: nomLot, groupe: groupes[$0], description: nil, notePosee: false, vignette: nil,
                                                     cote: nil, taille: taille, erreur: error.localizedDescription,
                                                     duree: Date().timeIntervalSince(depart)) }
                dire("✘ lot \(rang + 1)/\(nombreLots) : \(error.localizedDescription)")
            }
            sortie.write(Data(lignes.map { JSONCoding.line($0) + "\n" }.joined().utf8))
            if echecsDeSuite >= echecsDeSuiteMax {
                bilan.abandon = true
                dire("✘ \(echecsDeSuiteMax) commandes de suite en échec : collecte arrêtée (liaison démarrée ? Lightroom ouvert ?). Relancer la même commande la reprend.")
                break
            }
        }
        dire("Collecte finie : \(bilan.copiees) vignette(s) copiée(s), \(bilan.erreurs) erreur(s), \(bilan.notesDeClaude) note(s) posée(s) par Claude (écartées du résumé). Ensuite : --mesures --mesurer \(dossier.path)")
        return bilan
    }

    static func lireLignes(_ fichier: URL) throws -> [JSONValue] {
        let texte = try String(contentsOf: fichier, encoding: .utf8)
        return texte.split(separator: "\n").compactMap { try? JSONCoding.parse(String($0)) }
    }

    // MARK: 3. Mesure

    /// Une vignette à mesurer, avec ce que la collecte en sait (`meta`).
    struct Entree {
        var fichier: URL
        var meta: [String: JSONValue]
    }

    /// Les vignettes de `catalogue.jsonl` (la dernière ligne de chaque photo l'emporte), dans l'ordre.
    static func lireCatalogue(_ dossier: URL) throws -> [Entree] {
        let lignes = try lireLignes(dossier.appendingPathComponent("catalogue.jsonl"))
        var ordre: [Int] = [], parId: [Int: JSONValue] = [:]
        for ligne in lignes {
            guard let id = ligne["id"]?.int else { continue }
            if parId[id] == nil { ordre.append(id) }
            if ligne["vignette"] != nil || parId[id]?["vignette"] == nil { parId[id] = ligne }
        }
        return ordre.compactMap { id in
            guard let ligne = parId[id], let chemin = ligne["vignette"]?.string else { return nil }
            return Entree(fichier: dossier.appendingPathComponent(chemin), meta: ligne.object ?? [:])
        }
    }

    /// Une photo mesurée : sa ligne, et ce que les paires en reprennent.
    struct Mesuree {
        var ligne: [String: JSONValue]
        var empreinte: VNFeaturePrintObservation?
        var peau: Teint.Mesure?
        var date: Date?
        var prise: GroupesLumiere.Prise?
    }

    static func r(_ valeur: Double, _ decimales: Double = 100) -> JSONValue { .number((valeur * decimales).rounded() / decimales) }

    /// L'écrêtage par la gamme rejoué : la part (%) des pixels qu'il compterait à chaque borne
    /// (canal le plus bas sous `bas`, C* d'au moins `chroma`, un canal à 254 ou plus).
    static func gammeRejouee(_ image: CGImage) -> [String: Double] {
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        guard let pixels = Measurements.rgba(reduite) else { return [:] }
        let total = reduite.width * reduite.height
        guard total > 0 else { return [:] }
        var comptes = [Int](repeating: 0, count: basesGamme.count * chromasGamme.count)
        for i in 0..<total {
            let rouge = pixels[i * 4], vert = pixels[i * 4 + 1], bleu = pixels[i * 4 + 2]
            guard max(rouge, vert, bleu) >= 254 else { continue }
            let bas = min(rouge, vert, bleu)
            let lab = Measurements.lab(rouge, vert, bleu)
            let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
            for (b, borne) in basesGamme.enumerated() where bas < borne {
                for (c, seuil) in chromasGamme.enumerated() where chroma >= seuil { comptes[b * chromasGamme.count + c] += 1 }
            }
        }
        var parts: [String: Double] = [:]
        for (b, borne) in basesGamme.enumerated() {
            for (c, seuil) in chromasGamme.enumerated() {
                parts["bas\(borne)_c\(Int(seuil))"] = Double(comptes[b * chromasGamme.count + c]) * 100 / Double(total)
            }
        }
        return parts
    }

    /// La nature de l'écrêtage en un mot, comme `PhotoMeasurements.natureEcretage`.
    static func nature(_ mesures: PhotoMeasurements) -> String {
        guard mesures.clippedHighlights >= PhotoMeasurements.ecretageMin else { return "aucune" }
        let gamme = mesures.clippedGamut, luminance = max(mesures.clippedHighlights - mesures.clippedGamut, 0)
        if gamme >= PhotoMeasurements.natureNette * luminance { return "gamme" }
        if luminance >= PhotoMeasurements.natureNette * gamme { return "luminance" }
        return "mixte"
    }

    /// Mesure une vignette (pure, sans Lightroom).
    static func mesurer(_ entree: Entree, index: Int) -> Mesuree {
        var ligne = entree.meta
        let id = entree.meta["id"]?.int ?? -(index + 1)
        ligne["fichier_mesure"] = .string(entree.fichier.lastPathComponent)
        guard let donnees = try? Data(contentsOf: entree.fichier), let image = PreviewImages.image(donnees) else {
            ligne["erreur"] = .string("vignette illisible : \(entree.fichier.path)")
            return Mesuree(ligne: ligne)
        }
        ligne["cote"] = .number(Double(max(image.width, image.height)))
        // Les mesures du Suivi, exactement (même vignette du cache, même facteur de netteté).
        let suivi = Suivi.analyserPhoto(Suivi.AAnalyser(id: id, vignette: entree.fichier.path, iso: entree.meta["iso"]?.double, cache: true,
                                                        retouchee: entree.meta["retouchee_par_claude"]?.bool == true,
                                                        objectif: entree.meta["objectif"]?.string))
        ligne["suivi"] = suivi
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        if let mesures = Measurements.analyze(reduite) {
            var ecretage: [String: JSONValue] = [
                "total_pct": r(mesures.clippedHighlights), "gamme_pct": r(mesures.clippedGamut),
                "luminance_pct": r(max(mesures.clippedHighlights - mesures.clippedGamut, 0)), "nature": .string(nature(mesures)),
            ]
            if let bande = mesures.gamutBand { ecretage["bande"] = .string(bande) }
            ecretage["gamme_rejouee_pct"] = .object(gammeRejouee(image).mapValues { r($0) })
            ligne["ecretage"] = .object(ecretage)
        }
        let grande = PreviewImages.scaled(image, maxSide: Detail.side)
        let vision = VisionAnalysis.analyze(grande)
        let sujet = (vision?.faces.map(\.box) ?? []) + [vision?.salientArea].compactMap { $0 }
        if let grille = PointsChauds.lireGrille(image) {
            let zones = PointsChauds.zones(grille, sujet: sujet)
            var chauds: [String: JSONValue] = [
                "zones": .number(Double(zones.count)), "part_pct": r(zones.map(\.part).reduce(0, +), 10),
                "detail": PointsChauds.json(zones)?["zones"] ?? .array([]),
                "grille": ["colonnes": .number(Double(grille.colonnes)), "lignes": .number(Double(grille.lignes)),
                           "mediane": r(grille.mediane, 10), "moyennes": .array(grille.moyennes.map { r($0, 10) })],
                "sujet": .array(sujet.map { ["x": r($0.minX, 1000), "y": r($0.minY, 1000), "largeur": r($0.width, 1000), "hauteur": r($0.height, 1000)] }),
            ]
            var rejoue: [String: JSONValue] = [:]
            for ecart in ecartsChauds {
                for lMin in lMinsChauds {
                    rejoue["ecart\(Int(ecart))_l\(Int(lMin))"] = .number(Double(PointsChauds.zones(grille, sujet: sujet, ecartMediane: ecart, lMin: lMin).count))
                }
            }
            for partMin in partsMinChaudes {
                rejoue["partmin\(partMin)"] = .number(Double(PointsChauds.zones(grille, sujet: sujet, partMin: partMin).count))
            }
            for partMax in partsMaxChaudes {
                rejoue["partmax\(Int(partMax))"] = .number(Double(PointsChauds.zones(grille, sujet: sujet, partMax: partMax).count))
            }
            chauds["rejoue"] = .object(rejoue)
            ligne["points_chauds"] = .object(chauds)
        }
        // La peau du plus grand visage (Teint), sur la vignette entière.
        let visages = (vision?.faces ?? []).filter(Composition.visagePlausible).map(\.box).sorted { $0.width > $1.width }
        let peau = Teint.mesurer(image, visages: visages)
        if let peau {
            ligne["peau"] = ["l": r(peau.l, 10), "a": r(peau.a, 10), "b": r(peau.b, 10), "pixels": .number(Double(peau.pixels)),
                             "teinte_deg": .number(peau.teinte.rounded())]
        }
        let date = Tri.date(entree.meta["date"]?.string)
        var prise: GroupesLumiere.Prise?
        if entree.meta["date"] != nil || entree.meta["iso"] != nil {
            prise = GroupesLumiere.Prise(id: id, fichier: entree.meta["fichier"]?.string ?? entree.fichier.lastPathComponent, date: date,
                                         ouverture: entree.meta["ouverture"]?.double, vitesse: entree.meta["vitesse"]?.double,
                                         iso: entree.meta["iso"]?.double, compensation: entree.meta["compensation"]?.double,
                                         flash: entree.meta["flash"]?.bool)
        }
        return Mesuree(ligne: ligne, empreinte: VisionAnalysis.featurePrint(grande), peau: peau, date: date, prise: prise)
    }

    /// Mesure les entrées, deux à la fois au plus (Vision).
    static func mesurerTout(_ entrees: [Entree], dire: (String) -> Void) -> [Mesuree] {
        var resultats = [Mesuree?](repeating: nil, count: entrees.count)
        let verrou = NSLock()
        let file = OperationQueue()
        file.maxConcurrentOperationCount = ToolHandler.parallelMeasures
        let depart = Date()
        for paquet in stride(from: 0, to: entrees.count, by: 50) {
            for i in paquet..<min(paquet + 50, entrees.count) {
                file.addOperation {
                    let mesuree = mesurer(entrees[i], index: i)
                    verrou.lock(); resultats[i] = mesuree; verrou.unlock()
                }
            }
            file.waitUntilAllOperationsAreFinished()
            dire(String(format: "%d/%d vignette(s) mesurée(s) (%.0f s)", min(paquet + 50, entrees.count), entrees.count, Date().timeIntervalSince(depart)))
        }
        return resultats.map { $0 ?? Mesuree(ligne: ["erreur": "non mesurée"]) }
    }

    /// Les paires d'une photo à la suivante dans chaque groupe (par l'heure exacte), et le groupe de
    /// lumière de chaque photo (`GroupesLumiere.former`, l'algorithme de `match_series`, sur les
    /// vraies prises de vue). Modifie `mesurees` (champ `groupe_lumiere`).
    static func paires(_ mesurees: inout [Mesuree]) -> [[String: JSONValue]] {
        var parGroupe: [String: [Int]] = [:], ordreGroupes: [String] = []
        for (i, m) in mesurees.enumerated() where m.prise != nil && m.ligne["erreur"] == nil {
            let groupe = m.ligne["groupe"]?.string ?? "tous"
            if parGroupe[groupe] == nil { ordreGroupes.append(groupe) }
            parGroupe[groupe, default: []].append(i)
        }
        var lignes: [[String: JSONValue]] = []
        for groupe in ordreGroupes {
            let indices = parGroupe[groupe]!.filter { mesurees[$0].date != nil }
                .sorted { (mesurees[$0].date!, $0) < (mesurees[$1].date!, $1) }
            for (a, b) in zip(indices, indices.dropFirst()) {
                let ma = mesurees[a], mb = mesurees[b]
                var ligne: [String: JSONValue] = ["groupe": .string(groupe), "id_a": ma.ligne["id"] ?? .null, "id_b": mb.ligne["id"] ?? .null,
                                                  "pause_s": r(mb.date!.timeIntervalSince(ma.date!), 10)]
                if let la = ma.prise?.lumiere, let lb = mb.prise?.lumiere { ligne["delta_il"] = r(lb - la) }
                if let fa = ma.prise?.flash { ligne["flash_a"] = .bool(fa) }
                if let fb = mb.prise?.flash { ligne["flash_b"] = .bool(fb) }
                if let ea = ma.empreinte, let eb = mb.empreinte, let d = VisionAnalysis.distance(ea, eb) { ligne["distance"] = r(d, 1000) }
                if let pa = ma.peau, let pb = mb.peau { ligne["ecart_peau"] = r(Teint.ecart(pb, pa), 10) }
                ligne["meme_appareil"] = .bool(ma.ligne["appareil"]?.string == mb.ligne["appareil"]?.string)
                lignes.append(ligne)
            }
            // Les groupes de lumière du groupe entier.
            let membres = parGroupe[groupe]!
            let prises = membres.map { mesurees[$0].prise! }
            let formes = GroupesLumiere.former(prises) { i, j in
                guard let a = mesurees[membres[i]].empreinte, let b = mesurees[membres[j]].empreinte else { return nil }
                return VisionAnalysis.distance(a, b)
            }
            for (n, forme) in formes.enumerated() {
                for (rang, membre) in forme.membres.enumerated() {
                    var info: [String: JSONValue] = ["numero": .number(Double(n + 1))]
                    if rang == 0 { info["coupure"] = .string(forme.coupure.texte) }
                    mesurees[membres[membre]].ligne["groupe_lumiere"] = .object(info)
                }
            }
        }
        return lignes
    }

    static func mesurerEtEcrire(_ entrees: [Entree], dans dossier: URL, dire: (String) -> Void) throws {
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        dire("Mesure de \(entrees.count) vignette(s), sans Lightroom.")
        var mesurees = mesurerTout(entrees, dire: dire)
        let lignesPaires = paires(&mesurees)
        let lignes = mesurees.map(\.ligne)
        try Data(lignes.map { JSONCoding.line(.object($0)) + "\n" }.joined().utf8).write(to: dossier.appendingPathComponent("mesures.jsonl"))
        try Data(csv(lignes).utf8).write(to: dossier.appendingPathComponent("mesures.csv"))
        try Data(csvPaires(lignesPaires).utf8).write(to: dossier.appendingPathComponent("paires.csv"))
        let resume = resumer(lignes, paires: lignesPaires)
        try Data((resume.texte.joined(separator: "\n") + "\n").utf8).write(to: dossier.appendingPathComponent("resume.txt"))
        try Data(JSONCoding.pretty(resume.json).utf8).write(to: dossier.appendingPathComponent("resume.json"))
        resume.texte.forEach(dire)
        dire("Écrits dans \(dossier.path) : mesures.jsonl, mesures.csv, paires.csv, resume.txt, resume.json")
    }

    // MARK: Fichiers CSV

    static func champ(_ valeur: JSONValue?) -> String {
        guard let valeur else { return "" }
        let texte: String
        switch valeur {
        case .null: texte = ""
        case .bool(let b): texte = b ? "1" : "0"
        case .number(let n): texte = n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .string(let s): texte = s
        case .array(let a): texte = a.map { champ($0) }.joined(separator: "|")
        case .object: texte = JSONCoding.line(valeur)
        }
        return texte.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + texte.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : texte
    }

    static let colonnes: [(nom: String, lire: ([String: JSONValue]) -> JSONValue?)] = [
        ("id", { $0["id"] }), ("lot", { $0["lot"] }), ("groupe", { $0["groupe"] }), ("fichier", { $0["fichier"] }),
        ("appareil", { $0["appareil"] }), ("iso", { $0["iso"] }), ("tranche_iso", { l in tranche(l["iso"]?.double).map(JSONValue.string) }),
        ("date", { $0["date"] }), ("date_secondes", { $0["date_secondes"] }), ("ouverture", { $0["ouverture"] }),
        ("vitesse", { $0["vitesse"] }), ("compensation", { $0["compensation"] }), ("flash", { $0["flash"] }),
        ("lumiere_il", { $0["lumiere_il"] }), ("note", { $0["note"] }), ("note_par_claude", { $0["note_par_claude"] }),
        ("retouchee_par_claude", { $0["retouchee_par_claude"] }), ("cote", { $0["cote"] }), ("duree_lot_s", { $0["duree_lot_s"] }),
        ("mediane_l", { $0["suivi"]?["mesures"]?["mediane_l"] }), ("p95_l", { $0["suivi"]?["mesures"]?["p95_l"] }),
        ("blanc_pur", { $0["suivi"]?["mesures"]?["blanc_pur"] }), ("blanc_pur_haut", { $0["suivi"]?["mesures"]?["blanc_pur_haut"] }),
        ("nettete", { $0["suivi"]?["mesures"]?["nettete"] }), ("bruit", { $0["suivi"]?["mesures"]?["bruit"] }),
        ("visages", { $0["suivi"]?["mesures"]?["visages"] }), ("genre", { $0["suivi"]?["genre"] }),
        ("cherches", { $0["suivi"]?["cherches"] }), ("defauts", { $0["suivi"]?["defauts"] }),
        ("ecretage_pct", { $0["ecretage"]?["total_pct"] }), ("gamme_pct", { $0["ecretage"]?["gamme_pct"] }),
        ("luminance_pct", { $0["ecretage"]?["luminance_pct"] }), ("nature_ecretage", { $0["ecretage"]?["nature"] }),
        ("bande", { $0["ecretage"]?["bande"] }), ("zones_chaudes", { $0["points_chauds"]?["zones"] }),
        ("part_chaude_pct", { $0["points_chauds"]?["part_pct"] }), ("peau_l", { $0["peau"]?["l"] }), ("peau_a", { $0["peau"]?["a"] }),
        ("peau_b", { $0["peau"]?["b"] }), ("peau_pixels", { $0["peau"]?["pixels"] }),
        ("groupe_lumiere", { $0["groupe_lumiere"]?["numero"] }), ("erreur", { $0["erreur"] ?? $0["suivi"]?["texte"] }),
    ]

    static func csv(_ lignes: [[String: JSONValue]]) -> String {
        ([colonnes.map(\.nom).joined(separator: ",")] + lignes.map { l in colonnes.map { champ($0.lire(l)) }.joined(separator: ",") })
            .joined(separator: "\n") + "\n"
    }

    static let colonnesPaires = ["groupe", "id_a", "id_b", "pause_s", "delta_il", "flash_a", "flash_b", "distance", "ecart_peau", "meme_appareil"]

    static func csvPaires(_ lignes: [[String: JSONValue]]) -> String {
        ([colonnesPaires.joined(separator: ",")] + lignes.map { l in colonnesPaires.map { champ(l[$0]) }.joined(separator: ",") })
            .joined(separator: "\n") + "\n"
    }

    // MARK: Résumé

    /// Le centile `p` (0 à 100, au rang le plus proche) d'une liste ; nil si elle est vide.
    static func centile(_ valeurs: [Double], _ p: Double) -> Double? {
        let triees = valeurs.filter(\.isFinite).sorted()
        guard !triees.isEmpty else { return nil }
        let rang = Int((p / 100 * Double(triees.count)).rounded(.up)) - 1
        return triees[min(max(rang, 0), triees.count - 1)]
    }

    static func f(_ x: Double?, _ decimales: Int = 2) -> String {
        guard let x else { return "—" }
        return String(format: "%.\(decimales)f", x).replacingOccurrences(of: ".", with: ",")
    }

    static func pct(_ n: Int, _ sur: Int) -> String { sur > 0 ? "\(n)/\(sur) (\(f(100 * Double(n) / Double(sur), 0)) %)" : "—" }

    /// Le résumé : par groupe et par boîtier et tranche ISO, les parts des défauts et les centiles
    /// des mesures ; les notes de Dany seulement (une note posée par Claude, `note_par_claude`, en
    /// est écartée) ; les photos retouchées par Claude et les erreurs sont écartées de tout.
    static func resumer(_ lignes: [[String: JSONValue]], paires: [[String: JSONValue]]) -> (texte: [String], json: JSONValue) {
        var texte: [String] = []
        var json: [String: JSONValue] = [:]
        let erreurs = lignes.filter { $0["erreur"] != nil || $0["suivi"]?["mesures"] == nil }
        let retouchees = lignes.filter { $0["retouchee_par_claude"]?.bool == true && $0["erreur"] == nil }
        let valides = lignes.filter { $0["erreur"] == nil && $0["suivi"]?["mesures"] != nil && $0["retouchee_par_claude"]?.bool != true }
        let notesClaude = valides.filter { $0["note_par_claude"]?.bool == true }.count
        let petites = valides.filter { ($0["cote"]?.int ?? 0) < ToolHandler.minimumCullSide }.count
        let avecDate = lignes.filter { $0["date"] != nil }
        let datesSecondes = avecDate.filter { Tri.date($0["date"]?.string) != nil }.count
        let durees = Dictionary(grouping: lignes.compactMap { l -> (String, Double)? in
            guard let d = l["duree_lot_s"]?.double else { return nil }
            return ("\(d)", d)
        }, by: \.0).values.compactMap { $0.first?.1 }
        texte.append("Résumé du relevé des seuils : \(lignes.count) photo(s), \(valides.count) mesurée(s).")
        texte.append("Écartées : \(erreurs.count) erreur(s) ou vignette(s) non mesurée(s), \(retouchees.count) retouchée(s) par Claude ; \(notesClaude) note(s) posée(s) par Claude (mesures gardées, note écartée).")
        texte.append("Vignettes sous \(ToolHandler.minimumCullSide) px : \(petites) (le Suivi ne les analyse pas).")
        if !avecDate.isEmpty { texte.append("Heure à la seconde lue par Tri.date : \(pct(datesSecondes, avecDate.count)).") }
        if !durees.isEmpty {
            texte.append("Durée d'une commande vignettes : médiane \(f(centile(durees, 50), 1)) s, 95e centile \(f(centile(durees, 95), 1)) s, maximum \(f(durees.max(), 1)) s.")
        }
        json["photos"] = .number(Double(lignes.count))
        json["mesurees"] = .number(Double(valides.count))
        json["erreurs"] = .number(Double(erreurs.count))
        json["retouchees_par_claude"] = .number(Double(retouchees.count))
        json["notes_par_claude"] = .number(Double(notesClaude))
        json["vignettes_petites"] = .number(Double(petites))
        json["dates_a_la_seconde"] = .number(Double(datesSecondes))

        func mesure(_ l: [String: JSONValue], _ cle: String) -> Double? { l["suivi"]?["mesures"]?[cle]?.double }
        func codes(_ l: [String: JSONValue], _ cle: String) -> Set<String> { Set((l["suivi"]?[cle]?.array ?? []).compactMap(\.string)) }
        func statistiques(_ liste: [[String: JSONValue]]) -> (lignes: [String], json: JSONValue) {
            let bruits = liste.compactMap { mesure($0, "bruit") }
            func defaut(_ code: String) -> (Int, Int) {
                let cherches = liste.filter { codes($0, "cherches").contains(code) }
                return (cherches.filter { codes($0, "defauts").contains(code) }.count, cherches.count)
            }
            let (sous, sousSur) = defaut("sous_exposition"), (ciel, cielSur) = defaut("ciel_brule"), (flou, flouSur) = defaut("flou")
            let forts = bruits.filter { $0 >= DetailMeasurements.bruitFort }.count
            let visibles = bruits.filter { $0 >= DetailMeasurements.bruitVisible }.count
            let medianes = liste.compactMap { mesure($0, "mediane_l") }, p95s = liste.compactMap { mesure($0, "p95_l") }
            let hauts = liste.compactMap { mesure($0, "blanc_pur_haut") }
            let gammes = liste.compactMap { $0["ecretage"]?["gamme_pct"]?.double }
            let natureGamme = liste.filter { $0["ecretage"]?["nature"]?.string == "gamme" }.count
            let zones = liste.compactMap { $0["points_chauds"]?["zones"]?.double }
            let peaux = liste.filter { $0["peau"] != nil }.count
            let lignesStat = [
                "    bruit : médiane \(f(centile(bruits, 50))), 90e centile \(f(centile(bruits, 90))) ; au moins \(f(DetailMeasurements.bruitFort, 1)) (fort) \(pct(forts, bruits.count)), au moins \(f(DetailMeasurements.bruitVisible, 1)) (visible) \(pct(visibles, bruits.count))",
                "    sous-exposition \(pct(sous, sousSur)), ciel brûlé \(pct(ciel, cielSur)), flou \(pct(flou, flouSur))",
                "    L* médian : 10e centile \(f(centile(medianes, 10), 1)), médiane \(f(centile(medianes, 50), 1)) ; L* 95e centile : médiane \(f(centile(p95s, 50), 1)) ; blanc pur du tiers haut : 95e centile \(f(centile(hauts, 95), 1)) %",
                "    gamme : 90e centile \(f(centile(gammes, 90))) %, nature « gamme » \(pct(natureGamme, gammes.count)) ; points chauds : \(f(zones.isEmpty ? nil : zones.reduce(0, +) / Double(zones.count))) zone(s) par photo ; peau lue \(pct(peaux, liste.count))",
            ]
            let objet: JSONValue = [
                "n": .number(Double(liste.count)), "bruit_p50": nombre(centile(bruits, 50)), "bruit_p90": nombre(centile(bruits, 90)),
                "bruit_fort": .number(Double(forts)), "bruit_mesure": .number(Double(bruits.count)),
                "sous_exposition": .number(Double(sous)), "sous_exposition_cherchee": .number(Double(sousSur)),
                "ciel_brule": .number(Double(ciel)), "ciel_brule_cherche": .number(Double(cielSur)),
                "flou": .number(Double(flou)), "flou_cherche": .number(Double(flouSur)),
                "mediane_l_p10": nombre(centile(medianes, 10)), "blanc_pur_haut_p95": nombre(centile(hauts, 95)),
                "gamme_p90": nombre(centile(gammes, 90)), "nature_gamme": .number(Double(natureGamme)), "peau_lue": .number(Double(peaux)),
            ]
            return (lignesStat, objet)
        }
        func parCle(_ titre: String, _ cle: ([String: JSONValue]) -> String?) -> JSONValue {
            var ordre: [String] = [], groupes: [String: [[String: JSONValue]]] = [:]
            for l in valides {
                guard let k = cle(l) else { continue }
                if groupes[k] == nil { ordre.append(k) }
                groupes[k, default: []].append(l)
            }
            guard !ordre.isEmpty else { return .object([:]) }
            texte.append("")
            texte.append(titre)
            var objet: [String: JSONValue] = [:]
            for k in ordre {
                let liste = groupes[k]!
                texte.append("  \(k) : \(liste.count) photo(s)\(liste.count < 30 ? " (moins de 30 : pas de décision)" : "")")
                let stat = statistiques(liste)
                texte += stat.lignes
                objet[k] = stat.json
            }
            return .object(objet)
        }
        json["par_groupe"] = parCle("Par groupe :") { $0["groupe"]?.string ?? $0["lot"]?.string }
        json["par_appareil_et_iso"] = parCle("Par boîtier et tranche ISO (ISO du catalogue) :") { l in
            guard let appareil = appareilReleve(l["appareil"]?.string) ?? l["appareil"]?.string, let t = tranche(l["iso"]?.double) else { return nil }
            return "\(appareil) ISO \(t)"
        }
        // Les notes de Dany seulement.
        let notees = valides.filter { $0["note_par_claude"]?.bool != true && ($0["note"]?.int ?? 0) >= 3 }
        if !notees.isEmpty {
            texte.append("")
            texte.append("Notées 3 étoiles ou plus par Dany (notes de Claude écartées) : \(notees.count) photo(s)")
            let stat = statistiques(notees)
            texte += stat.lignes
            json["notees_3_etoiles_par_dany"] = stat.json
        }
        // L'écrêtage par la gamme et les points chauds rejoués.
        let rejoueGamme = valides.compactMap { $0["ecretage"]?["gamme_rejouee_pct"]?.object }
        if !rejoueGamme.isEmpty {
            texte.append("")
            texte.append("Écrêtage par la gamme rejoué (part des photos à \(f(PhotoMeasurements.ecretageMin, 1)) % ou plus ; actuel : bas \(PhotoMeasurements.basGamme), C* \(Int(PhotoMeasurements.chromaGamme))) :")
            var objet: [String: JSONValue] = [:]
            for borne in basesGamme {
                var morceaux: [String] = []
                for seuil in chromasGamme {
                    let cle = "bas\(borne)_c\(Int(seuil))"
                    let n = rejoueGamme.filter { ($0[cle]?.double ?? 0) >= PhotoMeasurements.ecretageMin }.count
                    morceaux.append("C* \(Int(seuil)) \(pct(n, rejoueGamme.count))")
                    objet[cle] = .number(Double(n))
                }
                texte.append("  bas \(borne) : " + morceaux.joined(separator: " ; "))
            }
            json["gamme_rejouee"] = .object(objet)
        }
        let rejoueChauds = valides.compactMap { $0["points_chauds"]?["rejoue"]?.object }
        if !rejoueChauds.isEmpty {
            texte.append("")
            texte.append("Points chauds rejoués (zones par photo en moyenne ; actuel : écart \(Int(PointsChauds.ecartMediane)), L* \(Int(PointsChauds.lMin)), part \(PointsChauds.partMin) à \(Int(PointsChauds.partMax)) %) :")
            var objet: [String: JSONValue] = [:]
            let cles = rejoueChauds.first!.keys.sorted()
            for cle in cles {
                let moyenne = rejoueChauds.compactMap { $0[cle]?.double }.reduce(0, +) / Double(rejoueChauds.count)
                objet[cle] = nombre(moyenne)
            }
            texte.append("  " + cles.map { "\($0) \(f(objet[$0]?.double))" }.joined(separator: " ; "))
            json["points_chauds_rejoues"] = .object(objet)
        }
        // Les paires : pauses, lumière, Vision, peau.
        if !paires.isEmpty {
            func valeurs(_ liste: [[String: JSONValue]], _ cle: String) -> [Double] { liste.compactMap { $0[cle]?.double } }
            let memeFlash = paires.filter { $0["flash_a"] == $0["flash_b"] }
            let courtes = memeFlash.filter { ($0["pause_s"]?.double ?? .infinity) <= 60 }
            let deltas = valeurs(courtes, "delta_il").map(abs)
            texte.append("")
            texte.append("Paires (photo suivante du même groupe, par l'heure exacte) : \(paires.count)")
            texte.append("  |ΔIL| à moins de 60 s, même flash : \(deltas.count) paire(s), médiane \(f(centile(deltas, 50))), 90e centile \(f(centile(deltas, 90))), 95e centile \(f(centile(deltas, 95))) (ecartIL actuel \(f(GroupesLumiere.ecartIL, 1)))")
            let tranchesPause: [(String, Double, Double)] = [("moins de 1 min", 0, 60), ("1 à 5 min", 60, 300), ("5 à 10 min", 300, 600),
                                                              ("10 à 30 min", 600, 1800), ("30 à 60 min", 1800, 3600), ("plus de 1 h", 3600, .infinity)]
            var pauses: [String: JSONValue] = [:]
            for (nom, bas, haut) in tranchesPause {
                let liste = paires.filter { ($0["pause_s"]?.double).map { $0 >= bas && $0 < haut } ?? false }
                let distances = valeurs(liste, "distance"), dIL = valeurs(liste, "delta_il").map(abs)
                texte.append("  pause \(nom) : \(liste.count) ; distance Vision médiane \(f(centile(distances, 50), 3)), 90e centile \(f(centile(distances, 90), 3)) ; |ΔIL| médiane \(f(centile(dIL, 50)))")
                pauses[nom] = ["n": .number(Double(liste.count)), "distance_p50": nombre(centile(distances, 50)),
                               "distance_p90": nombre(centile(distances, 90)), "delta_il_p50": nombre(centile(dIL, 50))]
            }
            let peaux = valeurs(paires.filter { ($0["pause_s"]?.double ?? .infinity) <= 120 }, "ecart_peau")
            texte.append("  écart a*b* de la peau à moins de 2 min : \(peaux.count) paire(s), médiane \(f(centile(peaux, 50), 1)), 90e centile \(f(centile(peaux, 90), 1)) (ecartVisible actuel \(f(Teint.ecartVisible, 1)))")
            json["paires"] = [
                "n": .number(Double(paires.count)), "delta_il_60s_p50": nombre(centile(deltas, 50)), "delta_il_60s_p95": nombre(centile(deltas, 95)),
                "delta_il_60s_n": .number(Double(deltas.count)), "pauses": .object(pauses),
                "ecart_peau_2min_p50": nombre(centile(peaux, 50)), "ecart_peau_2min_p90": nombre(centile(peaux, 90)),
                "ecart_peau_2min_n": .number(Double(peaux.count)),
            ]
        }
        return (texte, .object(json))
    }
}
