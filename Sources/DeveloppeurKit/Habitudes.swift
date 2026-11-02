import Foundation

/// Les habitudes de l'utilisateur en chiffres (1.6, `remember_style` avec `habits`) : ce qu'il fait
/// seul sur ses photos notées (4 ★ et plus par défaut), sans ce que Claude y a fait. `learn` voit ce
/// qu'il corrige chez Claude ; `habits`, ce qu'il fait sans lui. Lecture seule : rien n'entre au guide
/// sans son accord (remember_style avec preference et confirm). Fonctions pures ; la lecture est
/// dans `Tools+Style` (commande `habitudes` du module).
///
/// Chaque valeur se mesure par son écart à la valeur neutre du réglage (`DevelopSetting.neutral`,
/// `DevelopCatalogue.rawDefaults` pour un RAW) : une valeur laissée par défaut n'est pas une
/// habitude. Groupes par appareil, puis, pour le détail, le bruit et le grain, par tranche d'ISO.
public enum Habitudes {
    // MARK: Seuils (provisoires : à fixer par le relevé, `--habitudes`, docs/SPEC.md « À constater »)

    /// Une phrase seulement pour un réglage lu sur au moins `minPhotos` photos, touché sur au moins
    /// `minJours` jours de prise de vue distincts (une rafale synchronisée n'est pas une habitude).
    static let minPhotos = 20, minJours = 5
    /// Touché (écart à la valeur neutre) sur au moins `toucheMin` des photos lues, dans le même sens
    /// pour au moins `sensMin` d'entre elles.
    static let toucheMin = 0.4, sensMin = 0.8
    /// Dispersion : l'écart entre les quartiles (P75 − P25) des écarts touchés au plus
    /// max(|médiane|, un pas), le pas valant (max − min) / `diviseurPas` de la plage du réglage.
    static let diviseurPas = 40.0

    // MARK: Limites

    /// Photos lues au plus par appel ; au-delà, les premières dans l'ordre de Lightroom.
    public static let maxPhotos = 5000
    /// Photos par commande `habitudes lire` (le module refuse au-delà de 250).
    static let lot = 250
    static let maxPhrases = 8
    /// Ce que la réponse montre (plafond de taille) : les appareils qui ont le plus de photos, et les
    /// réglages les plus touchés de chacun.
    static let maxGroupes = 4, maxReglages = 8, maxReglagesISO = 3

    // MARK: Clés lues

    /// Réglages numériques mesurés (jamais la température, qui dépend de la scène ; la teinte
    /// seulement hors RAW : voir `mesuree`).
    static let clesNumeriques = [
        "Exposure2012", "Contrast2012", "Highlights2012", "Shadows2012", "Whites2012", "Blacks2012",
        "Texture", "Clarity2012", "Dehaze", "Vibrance", "Saturation", "Tint",
        "Sharpness", "SharpenRadius", "SharpenDetail", "SharpenEdgeMasking", "LuminanceSmoothing", "ColorNoiseReduction",
        "GrainAmount", "GrainSize", "PostCropVignetteAmount",
    ]
    /// Les réglages qui se lisent aussi par tranche d'ISO (détail, bruit, grain).
    static let clesISO: Set<String> = ["Sharpness", "SharpenDetail", "LuminanceSmoothing", "ColorNoiseReduction", "GrainAmount"]
    /// Lus pour les parts (profil, balance, corrections d'objectif, recadrage, masques). Le recadrage
    /// se lit par ses cinq clés (`DevelopCatalogue.cropKeys`), celles que Claude garde dans
    /// `avantClaude` quand il recadre ou redresse, jamais par `HasCrop` (aucune écriture de Claude
    /// ne la range, et sa présence dans `getDevelopSettings` n'est pas constatée).
    static let clesParts = ["CameraProfile", "Look.Name", "WhiteBalance", "ProcessVersion", "LensProfileEnable",
                            "#MaskGroupBasedCorrections", "#RetouchAreas"] + DevelopCatalogue.cropKeys
    /// Toutes les clés envoyées au module (celles de son `etatSimple`).
    public static var cles: [String] { clesNumeriques + clesParts }

    /// Tranches d'ISO, plus larges que celles du Suivi.
    static let tranchesISO = [
        Suivi.Tranche(jusqua: 800, libelle: "≤ 800", detail: "jusqu'à ISO 800"),
        Suivi.Tranche(jusqua: 1600, libelle: "≤ 1 600", detail: "de ISO 801 à 1 600"),
        Suivi.Tranche(jusqua: 3200, libelle: "≤ 3 200", detail: "de ISO 1 601 à 3 200"),
        Suivi.Tranche(jusqua: nil, libelle: "> 3 200", detail: "au-delà de ISO 3 200"),
    ]

    // MARK: Photos lues

    struct Photo: Equatable {
        var id: Int
        var appareil: String
        var iso: Double?
        var jour: String?
        var raw: Bool
        var valeurs: [String: JSONValue]
        var claude: Set<String>
        var reprises: Set<String>
        var copie: String?
        var virtuelle = false
        var essai = false
        var video = false
        var memoireAutre = false
        var illisible = false
    }

    /// Une photo de la réponse du module (`habitudes lire`).
    static func photo(_ v: JSONValue) -> Photo? {
        guard let id = v["id"]?.int else { return nil }
        let format = v["format"]?.string?.uppercased() ?? ""
        let appareil = v["appareil"]?.string?.trimmingCharacters(in: .whitespaces) ?? ""
        return Photo(id: id, appareil: appareil.isEmpty ? "appareil inconnu" : appareil, iso: v["iso"]?.double,
                     jour: v["jour"]?.string, raw: format == "RAW" || format == "DNG",
                     valeurs: v["valeurs"]?.object ?? [:],
                     claude: Set((v["claude"]?.array ?? []).compactMap(\.string)),
                     reprises: Set((v["reprises"]?.array ?? []).compactMap(\.string)),
                     copie: v["copie"]?.string, virtuelle: v["virtuelle"]?.bool == true, essai: v["essai"]?.bool == true,
                     video: v["video"]?.bool == true || format == "VIDEO", memoireAutre: v["memoire_autre"]?.bool == true,
                     illisible: v["erreur"]?.string != nil)
    }

    /// La valeur est-elle de l'utilisateur ? Pas si Claude l'a touchée (avantClaude), sauf s'il l'a
    /// reprise à la main depuis (corrections_utilisateur).
    static func deDany(_ p: Photo, _ cle: String) -> Bool {
        !p.claude.contains(cle) || p.reprises.contains(cle)
    }

    /// Un nombre d'une valeur du module (un booléen vaut 0 ou 1).
    static func nombre(_ v: JSONValue?) -> Double? {
        if let b = v?.bool { return b ? 1 : 0 }
        return v?.double
    }

    /// La valeur neutre d'un réglage pour ce format.
    static func neutre(_ cle: String, raw: Bool) -> Double {
        if raw, let d = DevelopCatalogue.rawDefaults[cle] { return d }
        return DevelopCatalogue.setting(cle)?.neutral ?? 0
    }

    /// Écart minimal compté comme « touché » (les arrondis de Lightroom).
    static let epsilon = 1e-6

    /// Ce réglage se mesure-t-il par son écart à la valeur neutre sur cette photo ? Pas la teinte d'un
    /// RAW : Lightroom la range en valeur absolue (en balance « Telle quelle », la teinte du boîtier,
    /// qui dépend de la scène, comme la température) ; hors RAW, elle est relative (0 = telle quelle).
    /// Ni la réduction du bruit de couleur d'une photo débruitée par Lightroom (`debruitee`).
    static func mesuree(_ cle: String, _ p: Photo) -> Bool {
        if cle == "Tint" { return !p.raw }
        if cle == "ColorNoiseReduction" { return !debruitee(p) }
        return true
    }

    /// Débruitée par Lightroom (Améliorer › Débruiter) ? Constaté dans Lightroom 15.6 (2 novembre
    /// 2026) : le débruitage, sur le RAW (filtre Denoise de FilterList) comme dans un DNG « -Bruit »
    /// d'avant, met `ColorNoiseReduction` à 0 ; sur 523 X-H2S notées, les 313 RAW ou DNG à 0 étaient
    /// tous débruités. La baisser à 0 à la main est rare : elle se confond avec le débruitage.
    static func debruitee(_ p: Photo) -> Bool {
        p.raw && nombre(p.valeurs["ColorNoiseReduction"]).map { abs($0) <= epsilon } == true
    }

    /// Le cadre neutre : aucun recadrage, aucun redressement.
    static let cadreNeutre: [String: Double] = ["CropAngle": 0, "CropLeft": 0, "CropTop": 0, "CropRight": 1, "CropBottom": 1]
    /// Écart au cadre neutre compté comme un recadrage (bords de 0 à 1, angle en degrés).
    static let epsilonCadre = 1e-3

    /// La photo est-elle recadrée ou redressée par l'utilisateur ? nil si aucune clé du cadre n'est
    /// lue. Un cadre dont Claude a touché une clé (avantClaude) est à Claude, sauf si l'utilisateur a
    /// repris une de ces clés à la main depuis : un redressement change aussi les bords.
    static func recadree(_ p: Photo) -> Bool? {
        let lues = DevelopCatalogue.cropKeys.compactMap { cle in nombre(p.valeurs[cle]).map { (cle, $0) } }
        guard !lues.isEmpty else { return nil }
        let cles = Set(DevelopCatalogue.cropKeys)
        if !p.claude.isDisjoint(with: cles), p.reprises.isDisjoint(with: cles) { return false }
        return lues.contains { cle, v in abs(v - (cadreNeutre[cle] ?? 0)) > epsilonCadre }
    }

    /// Les raisons d'écarter une photo avant tout calcul, ou nil.
    static func ecartee(_ p: Photo) -> String? {
        if p.video { return "videos" }
        if p.essai { return "essais" }
        if p.virtuelle, let copie = p.copie, copie.lowercased().hasPrefix("claude") { return "copies_claude" }
        if p.illisible { return "illisibles" }
        if let pv = p.valeurs["ProcessVersion"]?.string, let version = DevelopCatalogue.processVersion(pv), version < 3 {
            return "ancien_processus"
        }
        if !retouchee(p) { return "sans_retouche" }
        return nil
    }

    /// Une valeur de l'utilisateur hors de sa valeur neutre, un masque, une retouche ou un recadrage ?
    /// Les corrections d'objectif et la balance (teinte comprise) ne comptent pas (un réglage
    /// d'importation ou le boîtier les pose).
    static func retouchee(_ p: Photo) -> Bool {
        for cle in clesNumeriques where cle != "Tint" && mesuree(cle, p) && deDany(p, cle) {
            if let v = nombre(p.valeurs[cle]), abs(v - neutre(cle, raw: p.raw)) > epsilon { return true }
        }
        for cle in ["#MaskGroupBasedCorrections", "#RetouchAreas"] where deDany(p, cle) {
            if let v = nombre(p.valeurs[cle]), v > 0 { return true }
        }
        return recadree(p) == true
    }

    // MARK: Statistiques

    /// Quantile par interpolation linéaire d'une liste triée (q de 0 à 1).
    static func quantile(_ triees: [Double], _ q: Double) -> Double {
        guard !triees.isEmpty else { return 0 }
        let position = q * Double(triees.count - 1)
        let bas = Int(position.rounded(.down)), haut = Int(position.rounded(.up))
        return triees[bas] + (triees[haut] - triees[bas]) * (position - Double(bas))
    }

    struct Statistique: Equatable {
        var cle: String
        /// Photos où la valeur est de l'utilisateur.
        var photos: Int
        var touchees: Int
        /// Jours de prise de vue distincts des photos touchées.
        var jours: Int
        var mediane: Double
        var p25: Double
        var p75: Double
        /// Part des photos touchées dans le sens majoritaire, et ce sens (+1 ou −1).
        var memeSens: Double
        var sens: Double
        var touche: Double { photos > 0 ? Double(touchees) / Double(photos) : 0 }

        /// Les seuils qui ne tiennent pas (vide : une phrase).
        var manque: [String] {
            var raisons: [String] = []
            if photos < Habitudes.minPhotos { raisons.append("photos") }
            if jours < Habitudes.minJours { raisons.append("jours") }
            if touche < Habitudes.toucheMin { raisons.append("touche") }
            if memeSens < Habitudes.sensMin { raisons.append("sens") }
            if p75 - p25 > Swift.max(abs(mediane), Habitudes.pas(cle)) { raisons.append("dispersion") }
            return raisons
        }
    }

    /// Le pas d'un réglage : sa plage divisée par `diviseurPas`.
    static func pas(_ cle: String) -> Double {
        guard let s = DevelopCatalogue.setting(cle) else { return 1 }
        return (s.max - s.min) / diviseurPas
    }

    /// La statistique d'un réglage sur ces photos (écarts à la valeur neutre), ou nil s'il n'est lu
    /// sur aucune photo comme valeur de l'utilisateur.
    static func statistique(_ cle: String, _ photos: [Photo]) -> Statistique? {
        var lues = 0
        var ecarts: [Double] = []
        var jours = Set<String>()
        for p in photos where deDany(p, cle) && mesuree(cle, p) {
            guard let v = nombre(p.valeurs[cle]) else { continue }
            lues += 1
            let ecart = v - neutre(cle, raw: p.raw)
            guard abs(ecart) > epsilon else { continue }
            ecarts.append(ecart)
            if let jour = p.jour { jours.insert(jour) }
        }
        guard lues > 0 else { return nil }
        let triees = ecarts.sorted()
        let hausses = ecarts.filter { $0 > 0 }.count, baisses = ecarts.count - hausses
        return Statistique(cle: cle, photos: lues, touchees: ecarts.count, jours: jours.count,
                           mediane: quantile(triees, 0.5), p25: quantile(triees, 0.25), p75: quantile(triees, 0.75),
                           memeSens: ecarts.isEmpty ? 0 : Double(max(hausses, baisses)) / Double(ecarts.count),
                           sens: hausses >= baisses ? 1 : -1)
    }

    /// Valeurs de Claude écartées (photo et réglage lus, mais de Claude).
    static func valeursDeClaude(_ photos: [Photo]) -> Int {
        photos.reduce(0) { total, p in total + cles.filter { p.valeurs[$0] != nil && !deDany(p, $0) }.count }
    }

    struct Groupe {
        var appareil: String
        var photos: [Photo]
        var jours: Int { Set(photos.compactMap(\.jour)).count }
        var reglages: [Statistique]
        var parISO: [(tranche: Suivi.Tranche, photos: Int, reglages: [Statistique])]
    }

    static func groupe(_ appareil: String, _ photos: [Photo]) -> Groupe {
        var parISO: [(tranche: Suivi.Tranche, photos: Int, reglages: [Statistique])] = []
        for (index, tranche) in tranchesISO.enumerated() {
            let dans = photos.filter { $0.iso.map { Suivi.tranche($0, tranchesISO) == index } ?? false }
            guard !dans.isEmpty else { continue }
            parISO.append((tranche, dans.count, clesNumeriques.filter(clesISO.contains).compactMap { statistique($0, dans) }))
        }
        return Groupe(appareil: appareil, photos: photos, reglages: clesNumeriques.compactMap { statistique($0, photos) }, parISO: parISO)
    }

    /// Part des photos (valeur de l'utilisateur seulement) pour lesquelles `garde` est vrai, ou nil.
    static func part(_ photos: [Photo], _ cle: String, _ garde: (JSONValue) -> Bool) -> Double? {
        let lues = photos.filter { deDany($0, cle) }.compactMap { $0.valeurs[cle] }
        guard !lues.isEmpty else { return nil }
        return Double(lues.filter(garde).count) / Double(lues.count)
    }

    // MARK: Phrases

    struct Phrase {
        var rubrique: String
        var constat: String
        var phrase: String
        var force: Double
    }

    /// Libellé court d'un réglage (sans la parenthèse des défauts).
    static func libelle(_ cle: String) -> String {
        let texte = DevelopCatalogue.label(for: cle) ?? cle
        return texte.components(separatedBy: " (").first ?? texte
    }

    static func signe(_ v: Double) -> String {
        let absolu = abs(v)
        guard absolu >= 0.005 else { return "0" }
        let texte = Bilan.nombre(absolu, decimales: absolu < 1 ? 2 : (absolu < 10 ? 1 : 0))
        return (v < 0 ? "−" : "+") + texte
    }

    static func pourcent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    /// La phrase d'une statistique qui passe tous les seuils, ou nil.
    static func phrase(_ s: Statistique, appareil: String, note: Int, tranche: Suivi.Tranche? = nil) -> Phrase? {
        guard s.manque.isEmpty else { return nil }
        let nom = libelle(s.cle)
        let verbe = s.sens > 0 ? "montes" : "baisses"
        let parDefaut = DevelopCatalogue.rawDefaults[s.cle] != nil || (DevelopCatalogue.setting(s.cle)?.neutral ?? 0) != 0
        let rapport = parDefaut ? " par rapport à sa valeur par défaut" : ""
        let ou = tranche.map { ", \($0.detail)" } ?? ""
        let constat = "Sur tes \(appareil) notées \(note) ★ et plus\(ou) (\(s.photos) photos, \(s.jours) jours de prise de vue), tu \(verbe) \(nom) sur \(pourcent(s.touche)) d'entre elles, de \(signe(s.mediane)) en médiane\(rapport) (de \(signe(s.p25)) à \(signe(s.p75)) pour la moitié), dans le même sens \(pourcent(s.memeSens)) du temps."
        let valeur = parDefaut ? "environ \(signe(s.mediane)) par rapport à sa valeur par défaut" : "autour de \(signe(s.mediane))"
        let texte = "\(appareil)\(tranche.map { " (\($0.detail))" } ?? "") : \(nom) plus \(s.sens > 0 ? "haut" : "bas"), \(valeur)."
        let rubrique = s.cle.hasPrefix("Grain") ? "grain" : Apprentissage.rubrique(s.cle)
        return Phrase(rubrique: rubrique, constat: constat, phrase: texte, force: s.touche * s.memeSens)
    }

    /// Les phrases de tous les groupes, les plus fortes d'abord, `maxPhrases` au plus. Une phrase par
    /// tranche d'ISO seulement si le même réglage n'en a pas déjà une pour tout l'appareil.
    static func phrases(_ groupes: [Groupe], note: Int) -> [Phrase] {
        var liste: [Phrase] = []
        for g in groupes {
            let generales = g.reglages.compactMap { s in phrase(s, appareil: g.appareil, note: note).map { (s.cle, $0) } }
            liste += generales.map(\.1)
            let dejaDites = Set(generales.map(\.0))
            for t in g.parISO {
                liste += t.reglages.filter { !dejaDites.contains($0.cle) }.compactMap { phrase($0, appareil: g.appareil, note: note, tranche: t.tranche) }
            }
        }
        return Array(liste.sorted { $0.force != $1.force ? $0.force > $1.force : $0.phrase < $1.phrase }.prefix(maxPhrases))
    }

    // MARK: Analyse

    struct Analyse {
        var trouvees: Int
        var lues: Int
        var ecartees: [String: Int]
        var valeursDeClaude: Int
        var memoireAutre: Int
        var groupes: [Groupe]
        var phrases: [Phrase]
    }

    static func analyser(_ photos: [Photo], trouvees: Int, note: Int) -> Analyse {
        var ecartees: [String: Int] = [:]
        var gardees: [Photo] = []
        for p in photos {
            if let raison = ecartee(p) { ecartees[raison, default: 0] += 1 } else { gardees.append(p) }
        }
        let parAppareil = Dictionary(grouping: gardees, by: \.appareil)
        let groupes = parAppareil.map { groupe($0.key, $0.value) }
            .sorted { $0.photos.count != $1.photos.count ? $0.photos.count > $1.photos.count : $0.appareil < $1.appareil }
        return Analyse(trouvees: trouvees, lues: photos.count, ecartees: ecartees, valeursDeClaude: valeursDeClaude(gardees),
                       memoireAutre: gardees.filter(\.memoireAutre).count, groupes: groupes, phrases: phrases(groupes, note: note))
    }

    // MARK: Réponses

    static func arrondi(_ v: Double, _ cle: String) -> JSONValue {
        Bilan.arrondi(v, parts: cle == "Exposure2012" || cle == "SharpenRadius" ? 100 : 10)
    }

    static func json(_ s: Statistique, detaille: Bool) -> JSONValue {
        var o: [String: JSONValue] = [
            "reglage": .string(s.cle), "libelle": .string(libelle(s.cle)),
            "photos": .number(Double(s.photos)), "touche": Bilan.arrondi(s.touche, parts: 100),
            "mediane": arrondi(s.mediane, s.cle), "p25": arrondi(s.p25, s.cle), "p75": arrondi(s.p75, s.cle),
            "meme_sens": Bilan.arrondi(s.memeSens, parts: 100), "jours": .number(Double(s.jours)),
        ]
        if detaille {
            o["touchees"] = .number(Double(s.touchees))
            o["neutre_ecart"] = "écarts à la valeur neutre"
            o["seuils_manques"] = .array(s.manque.map(JSONValue.string))
            o["pas"] = Bilan.arrondi(pas(s.cle), parts: 100)
        }
        return .object(o)
    }

    static func groupeJSON(_ g: Groupe, detaille: Bool) -> JSONValue {
        let photos = g.photos
        var o: [String: JSONValue] = ["appareil": .string(g.appareil), "photos": .number(Double(photos.count)), "jours": .number(Double(g.jours))]
        var profils: [String: Int] = [:]
        for p in photos where deDany(p, "CameraProfile") {
            if let nom = p.valeurs["CameraProfile"]?.string {
                let look = deDany(p, "Look.Name") ? p.valeurs["Look.Name"]?.string : nil
                profils[look.map { "\(nom) + \($0)" } ?? nom, default: 0] += 1
            }
        }
        let totalProfils = max(1, profils.values.reduce(0, +))
        o["profils"] = .array(profils.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(detaille ? 20 : 3).map {
            ["profil": .string($0.key), "part": Bilan.arrondi(Double($0.value) / Double(totalProfils), parts: 100)]
        })
        if let v = part(photos, "WhiteBalance", { $0.string == "As Shot" }) { o["balance_telle_quelle"] = Bilan.arrondi(v, parts: 100) }
        if let v = part(photos, "LensProfileEnable", { (nombre($0) ?? 0) > 0 }) { o["corrections_objectif"] = Bilan.arrondi(v, parts: 100) }
        let cadres = photos.compactMap(recadree)
        if !cadres.isEmpty { o["recadrees"] = Bilan.arrondi(Double(cadres.filter { $0 }.count) / Double(cadres.count), parts: 100) }
        if let v = part(photos, "#MaskGroupBasedCorrections", { (nombre($0) ?? 0) > 0 }) { o["avec_masques"] = Bilan.arrondi(v, parts: 100) }
        let reglages = g.reglages.sorted { $0.touche != $1.touche ? $0.touche > $1.touche : $0.cle < $1.cle }
        o["reglages"] = .array((detaille ? reglages : Array(reglages.filter { $0.touchees > 0 }.prefix(maxReglages))).map { json($0, detaille: detaille) })
        o["par_iso"] = .array(g.parISO.map { t in
            let r = t.reglages.sorted { $0.touche != $1.touche ? $0.touche > $1.touche : $0.cle < $1.cle }
            return ["tranche": .string(t.tranche.libelle), "photos": .number(Double(t.photos)),
                    "reglages": .array((detaille ? r : Array(r.filter { $0.touchees > 0 }.prefix(maxReglagesISO))).map { json($0, detaille: detaille) })]
        })
        return .object(o)
    }

    static var regleDeLecture: String {
        "Écarts à la valeur neutre de chaque réglage (médiane, quartiles P25 et P75 des photos touchées). Une phrase seulement pour un réglage lu sur au moins \(minPhotos) photos, touché sur au moins \(minJours) jours de prise de vue et \(Int(toucheMin * 100)) % des photos, dans le même sens au moins \(Int(sensMin * 100)) % du temps, sans grande dispersion (seuils provisoires). Rien n'est ajouté : proposer chaque phrase à l'utilisateur, puis remember_style avec preference, category (rubrique) et confirm = true seulement après son accord."
    }

    static let aSavoir = "Ce que Claude a touché est écarté, sauf ce que l'utilisateur a repris à la main depuis sa dernière retouche (une reprise suivie d'une autre retouche de Claude ne se voit plus : sous-compté plutôt que mal attribué). Les retouches des anciens outils (MCP Lightroom, Claude pour Lightroom) et un paramètre d'importation ne se distinguent pas des siennes. Une copie virtuelle garde les clés de Claude de son original. Réduction du bruit de couleur à 0 sur un RAW ou un DNG : le débruitage de Lightroom, pas compté. Écartées : vidéos, photos de Développeur › Essais, copies virtuelles « Claude », ancien processus, photos sans retouche."

    /// Ce que remember_style rend (plafonné : appareils, réglages et phrases les plus parlants).
    static func json(_ a: Analyse, note: Int, detaille: Bool = false) -> JSONValue {
        var o: [String: JSONValue] = [
            "note_min": .number(Double(note)),
            "photos_trouvees": .number(Double(a.trouvees)), "photos_lues": .number(Double(a.lues)),
            "ecartees": .object(a.ecartees.mapValues { .number(Double($0)) }),
            "valeurs_de_claude_ecartees": .number(Double(a.valeursDeClaude)),
            "groupes": .array((detaille ? a.groupes : Array(a.groupes.prefix(maxGroupes))).map { groupeJSON($0, detaille: detaille) }),
            "phrases": .array(a.phrases.map { p in
                ["rubrique": .string(p.rubrique), "constat": .string(p.constat), "phrase_proposee": .string(p.phrase),
                 "force": Bilan.arrondi(p.force, parts: 100)]
            }),
            "regle_de_lecture": .string(regleDeLecture),
            "a_savoir": .string(aSavoir),
        ]
        if a.trouvees > a.lues {
            o["echantillon"] = .string("\(a.trouvees) photos trouvées : les \(a.lues) premières seulement, dans l'ordre de Lightroom. Préciser par une collection, un dossier ou un appareil.")
        }
        if a.memoireAutre > 0 {
            o["copies_avec_memoire_de_l_original"] = .number(Double(a.memoireAutre))
        }
        if a.groupes.count > maxGroupes, !detaille {
            o["autres_appareils"] = .array(a.groupes.dropFirst(maxGroupes).map { .string("\($0.appareil) (\($0.photos.count))") })
        }
        if a.phrases.isEmpty {
            o["remarque"] = a.groupes.isEmpty
                ? "Aucune photo retouchée par l'utilisateur à lire ici : rien à en tirer."
                : "Des réglages lus, mais aucun n'est assez fréquent, constant et resserré pour faire une phrase."
        }
        return .object(o)
    }
}
