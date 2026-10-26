import CoreGraphics
import Foundation

/// Le Suivi (correctif 1.3.7), côté connecteur : les deux commandes que le module lance par
/// `LrTasks.execute`, sous l'alarme de perl, hors de la liaison (comme `--focus`). Le contrat entre
/// les deux est figé dans Tests/Contrats/suivi.json (ContratSuiviTests ici, essais-suivi.lua côté
/// module) : un changement voulu se fait des deux côtés.
///
/// - `mcp-developpeur --analyser '<json>'` (`Suivi.analyser`) : les défauts de la prise de vue
///   mesurés sur les vignettes du cache de Lightroom que le module donne, par les mesures et les
///   règles du tri (`ToolHandler.mesurer`, sans point de mise au point) et du carnet
///   (`Carnet.constatsVue`, sans intention du boîtier), rendus en codes de `PriseDeVue`. Jamais
///   Lightroom, jamais l'original.
/// - `mcp-developpeur --graphiques '<json>' <dossier>` (`Suivi.graphiques`, SuiviGraphiques.swift) :
///   les tuiles et les huit graphiques d'une période, d'après le relevé `suivi.json` (tenu par
///   Releve.lua seul) et le carnet `carnet.json` (l'horizon et la mise au point vus par Claude),
///   lus seulement ; les PNG dessinés en 2x (SuiviDessin.swift) et les rectangles des barres.
///
/// Aucun chemin par défaut : le connecteur ne lit que les fichiers que la commande nomme (les
/// essais passent des fichiers temporaires, jamais le vrai relevé de l'utilisateur).
public enum Suivi {
    /// La réponse d'une commande du Suivi : la ligne JSON à écrire sur stdout, et le code de sortie
    /// (0 : `ok` vrai ; 1 : un refus de tout l'appel, `{ok: false, raison, texte}`).
    public struct Reponse: Equatable {
        public var ligne: JSONValue
        public var code: Int32
    }

    /// Un refus de tout l'appel (`regles.erreurs` du contrat) : sa raison et le texte qui se lit tel
    /// quel (fenêtre, journal).
    struct Refus: Error, Equatable {
        var raison: String
        var texte: String

        var reponse: Reponse {
            Reponse(ligne: ["ok": false, "raison": .string(raison), "texte": .string(texte)], code: 1)
        }
    }

    // MARK: Codes

    /// Les codes que le Suivi compte : six que `--analyser` cherche sur la vignette, et deux que seul
    /// Claude mesure (view_photo, measure_angle, read_composition), pris au carnet.
    public static let codesAnalyse = ["sous_exposition", "surexposition", "ciel_brule", "bruit", "flou", "yeux_fermes"]
    public static let codesCarnet = ["horizon_penche", "mise_au_point"]
    /// Les huit, dans l'ordre de `PriseDeVue.defauts`, seule liste des défauts.
    public static var codes: [String] {
        let comptes = Set(codesAnalyse + codesCarnet)
        return PriseDeVue.defauts.map(\.code).filter(comptes.contains)
    }
    /// Sur un original que Claude a déjà retouché, seuls le flou et les yeux fermés se cherchent : une
    /// retouche cacherait l'exposition, le ciel brûlé et le bruit (débruitage) de la prise de vue.
    static let codesSiRetouchee: Set<String> = ["flou", "yeux_fermes"]

    static func libelle(_ code: String) -> String { PriseDeVue.defaut(code: code)?.libelle ?? code }

    // MARK: Textes (regles.textes du contrat)

    /// Un entier, ses chiffres groupés par trois avec une espace (« 1 284 »).
    static func milliers(_ n: Int) -> String {
        let chiffres = Array(String(abs(n)))
        var groupes: [String] = []
        var fin = chiffres.count
        while fin > 0 {
            let debut = max(0, fin - 3)
            groupes.insert(String(chiffres[debut..<fin]), at: 0)
            fin = debut
        }
        return (n < 0 ? "-" : "") + groupes.joined(separator: " ")
    }

    /// « 0 photo », « 1 photo », « 2 photos », « 1 284 photos ».
    static func photos(_ n: Int) -> String { "\(milliers(n)) photo\(n > 1 ? "s" : "")" }

    /// L'arrondi au plus proche, demi vers le haut (comme le générateur du contrat : floor(x + 0,5)).
    /// Jamais de plantage : une valeur hors de la plage d'Int y est ramenée, une valeur qui n'est pas
    /// un nombre vaut 0 (un relevé abîmé ou édité à la main ne doit pas arrêter --graphiques).
    static func arrondi(_ x: Double) -> Int {
        let y = (x + 0.5).rounded(.down)
        if let entier = Int(exactly: y) { return entier }
        return y > 0 ? Int.max : y < 0 ? Int.min : 0
    }

    /// 100 × n / sur, exact (0 quand sur = 0) : les rangs se comparent sur lui, avant l'arrondi.
    static func part(_ n: Int, sur: Int) -> Double { sur > 0 ? 100.0 * Double(n) / Double(sur) : 0 }

    /// La valeur d'un pourcentage : au dixième, demi vers le haut ; 0 quand sur = 0.
    static func valeurPourcentage(_ n: Int, sur: Int) -> Double {
        sur > 0 ? ((part(n, sur: sur) * 10 + 0.5).rounded(.down)) / 10 : 0
    }

    /// Le texte d'un pourcentage : « — » quand sur = 0, « 0 % » quand n = 0, « < 1 % » sous 1, sinon
    /// l'entier le plus proche.
    static func textePourcentage(_ n: Int, sur: Int) -> String {
        guard sur > 0 else { return "—" }
        let p = part(n, sur: sur)
        if p == 0 { return "0 %" }
        if p < 1 { return "< 1 %" }
        return "\(arrondi(p)) %"
    }

    static func dixieme(_ x: Double) -> JSONValue { .number((x * 10).rounded() / 10) }
    static func centieme(_ x: Double) -> JSONValue { .number((x * 100).rounded() / 100) }

    // MARK: --analyser

    /// La version des règles de l'analyse : le module la range dans `analyse.regles`, et une réponse
    /// de règles plus récentes que celles d'une entrée la fait refaire.
    public static let reglesAnalyse = 1
    /// Photos par appel (le module en envoie 10).
    public static let maxPhotosAnalyse = 20
    /// Le temps d'une photo, puis de tout l'appel : sous l'alarme de 60 s de perl (côté module), pour
    /// que la ligne parte toujours ; une photo qui n'a pas fini à temps a la raison `delai` (le
    /// module lui compte un essai, comme pour les autres raisons). Provisoires : une mesure prend
    /// d'ordinaire moins d'une seconde (Vision compris), deux à la fois.
    public static let delaiParPhoto: TimeInterval = 15
    public static let delaiAnalyse: TimeInterval = 50

    /// Une photo à analyser, telle que le module la donne.
    public struct AAnalyser: Equatable {
        public var id: Int
        public var vignette: String
        public var iso: Double?
        public var cache: Bool
        public var retouchee: Bool
    }

    /// `--analyser '<json>'` : une ligne `{ok, regles, photos}` (une photo par photo reçue, dans le
    /// même ordre), ou un refus de tout l'appel. `mesurer` et les délais se remplacent pour les essais.
    public static func analyser(_ texte: String, delaiParPhoto: TimeInterval = delaiParPhoto, delaiTotal: TimeInterval = delaiAnalyse,
                                mesurer: @escaping (AAnalyser) -> JSONValue = analyserPhoto) -> Reponse {
        let photos: [AAnalyser]
        do {
            photos = try lireAAnalyser(texte)
        } catch let refus as Refus {
            return refus.reponse
        } catch {
            return Refus(raison: "arguments", texte: "Arguments de --analyser : \(error.localizedDescription)").reponse
        }
        let mesurees = mesurerBorne(photos, mesurer: mesurer, parPhoto: delaiParPhoto, total: delaiTotal)
        return Reponse(ligne: ["ok": true, "regles": .number(Double(reglesAnalyse)), "photos": .array(mesurees)], code: 0)
    }

    /// Les photos de l'entrée, vérifiées avant toute mesure (`analyser.entree` du contrat) ; le premier
    /// écart fait refuser tout l'appel.
    static func lireAAnalyser(_ texte: String) throws -> [AAnalyser] {
        let prefixe = "Arguments de --analyser : "
        func refus(_ detail: String) -> Refus { Refus(raison: "arguments", texte: prefixe + detail) }
        guard let objet = (try? JSONCoding.parse(texte))?.object else {
            throw refus("le JSON ne se lit pas (un objet { photos: [ … ] } attendu).")
        }
        guard let liste = objet["photos"]?.array, !liste.isEmpty else {
            throw refus("photos est un tableau de 1 à \(maxPhotosAnalyse) photos.")
        }
        guard liste.count <= maxPhotosAnalyse else {
            throw Refus(raison: "trop_de_photos", texte: "Au plus \(maxPhotosAnalyse) photos par appel de --analyser (\(liste.count) reçues).")
        }
        return try liste.enumerated().map { index, element in
            let rang = "photos[\(index + 1)]"
            guard let photo = element.object else { throw refus("\(rang) est un objet { id, vignette, iso, cache, retouchee }.") }
            guard let id = photo["id"]?.int else { throw refus("\(rang).id est un nombre (l'id de l'original).") }
            guard let vignette = photo["vignette"]?.string, !vignette.isEmpty else {
                throw refus("\(rang).vignette est le chemin d'un JPEG (la vignette, déjà redressée).")
            }
            var iso: Double?
            if let valeur = photo["iso"] {
                guard let nombre = valeur.double, nombre.isFinite, nombre > 0 else { throw refus("\(rang).iso est un nombre (absent : inconnu).") }
                iso = nombre
            }
            func booleen(_ cle: String) throws -> Bool {
                guard let valeur = photo[cle] else { return false }
                guard let oui = valeur.bool else { throw refus("\(rang).\(cle) est un booléen.") }
                return oui
            }
            return AAnalyser(id: id, vignette: vignette, iso: iso, cache: try booleen("cache"), retouchee: try booleen("retouchee"))
        }
    }

    /// Une photo qui ne s'analyse pas : `{ id, raison, texte }`.
    static func sansAnalyse(_ id: Int, _ raison: String, _ texte: String) -> JSONValue {
        ["id": .number(Double(id)), "raison": .string(raison), "texte": .string(texte)]
    }

    /// Les mesures d'une vignette, comme au tri (`ToolHandler.mesurer`) : ramenée à `Detail.side`
    /// px pour la netteté, le bruit et Vision ; à `Measurements.maxSide` pour l'exposition et le blanc
    /// pur du tiers haut, comme au carnet (`ToolHandler.mesurerImage`). La netteté d'une vignette du
    /// cache se ramène par `ToolHandler.thumbnailSharpnessFactor`. Sous `ToolHandler.minimumCullSide`,
    /// la vignette ne s'analyse pas.
    public static func analyserPhoto(_ photo: AAnalyser) -> JSONValue {
        let chemin = photo.vignette
        guard FileManager.default.fileExists(atPath: chemin) else {
            return sansAnalyse(photo.id, "vignette_absente", "Vignette introuvable : \(chemin).")
        }
        guard let donnees = try? Data(contentsOf: URL(fileURLWithPath: chemin)), let image = PreviewImages.image(donnees) else {
            return sansAnalyse(photo.id, "vignette_illisible", "Vignette illisible : \(chemin) n'est pas une image.")
        }
        let cote = max(image.width, image.height)
        guard cote >= ToolHandler.minimumCullSide else {
            return sansAnalyse(photo.id, "vignette_petite",
                               "Vignette de \(cote) px de grand côté : il en faut \(ToolHandler.minimumCullSide) au moins.")
        }
        let grande = PreviewImages.scaled(image, maxSide: Detail.side)
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        let mesures = Measurements.analyze(reduite)
        let facteur = photo.cache ? ToolHandler.thumbnailSharpnessFactor : 1
        let detail = Detail.analyze(grande).map { mesure -> DetailMeasurements in
            var ramenee = mesure
            ramenee.zones = mesure.zones.map { $0 * facteur }
            return ramenee
        }
        let vision = VisionAnalysis.analyze(grande)
        let trouves = codesTrouves(mesures: mesures, detail: detail, reduite: reduite, vision: vision, iso: photo.iso,
                                   retouchee: photo.retouchee)

        var lues: [String: JSONValue] = ["cote": .number(Double(cote))]
        if let mesures {
            lues["mediane_l"] = dixieme(mesures.medianL)
            lues["p95_l"] = dixieme(mesures.percentilesL[95] ?? mesures.medianL)
            lues["blanc_pur"] = dixieme(mesures.pureWhite)
        }
        if let haut = Carnet.blancPurHaut(reduite) { lues["blanc_pur_haut"] = dixieme(haut) }
        if let detail {
            lues["nettete"] = dixieme(detail.sharpest)
            lues["bruit"] = centieme(max(detail.noise, detail.shadowNoise ?? 0))
        }
        if let vision {
            lues["visages"] = .number(Double(vision.faces.count))
            var triee = PhotoTriee(id: photo.id, fichier: "")
            triee.vision = vision
            if let ouverture = triee.sujetsAuxYeuxLus.compactMap(\.eyeOpenness).min() { lues["ouverture_yeux"] = centieme(ouverture) }
        }
        return ["id": .number(Double(photo.id)), "cherches": .array(trouves.cherches.map(JSONValue.string)),
                "defauts": .array(trouves.defauts.map(JSONValue.string)), "mesures": .object(lues)]
    }

    /// Les défauts cherchés et trouvés sur une vignette mesurée (`analyser.regles_des_codes` du
    /// contrat), dans l'ordre des codes : ceux du carnet (`Carnet.constatsVue`, sans point de mise
    /// au point ni intention ni horizon : sous-exposition, ciel brûlé, flou à `Detail.side` px, bruit
    /// à ISO élevé), la surexposition de la photo « brûlée » du tri
    /// (`PhotoTriee.partBlancPurBrulee`) et les yeux fermés du tri (`PhotoTriee.yeuxFermes`),
    /// cherchés seulement si les yeux d'un sujet se lisent. Un original retouché par Claude
    /// (`retouchee`) n'est cherché que pour le flou et les yeux.
    public static func codesTrouves(mesures: PhotoMeasurements?, detail: DetailMeasurements?, reduite: CGImage?,
                                    vision: VisionReport?, iso: Double?, retouchee: Bool) -> (cherches: [String], defauts: [String]) {
        let vue = Carnet.constatsVue(mesures: mesures, detail: detail, reduite: reduite, af: nil, intention: nil, iso: iso,
                                     geometrieIntacte: false)
        var cherches = Set(vue.cherches), trouves = Set(vue.defauts.map(\.code))
        if let mesures {
            cherches.insert("surexposition")
            if mesures.pureWhite > PhotoTriee.partBlancPurBrulee { trouves.insert("surexposition") }
        }
        var triee = PhotoTriee(id: 0, fichier: "")
        triee.vision = vision
        if !triee.sujetsAuxYeuxLus.isEmpty {
            cherches.insert("yeux_fermes")
            if triee.yeuxFermes != nil { trouves.insert("yeux_fermes") }
        }
        cherches.formIntersection(retouchee ? codesSiRetouchee : Set(codesAnalyse))
        trouves.formIntersection(cherches)
        let ordre = codes
        return (ordre.filter(cherches.contains), ordre.filter(trouves.contains))
    }

    /// Les résultats d'une mesure, écrits par les fils de mesure et lus à la fin, sous un verrou : une
    /// mesure qui finit après son délai écrit encore ici, sans effet sur la réponse déjà partie.
    private final class Resultats: @unchecked Sendable {
        private let verrou = NSLock()
        private var valeurs: [JSONValue?]

        init(_ nombre: Int) { valeurs = Array(repeating: nil, count: nombre) }

        func ranger(_ valeur: JSONValue, a index: Int) {
            verrou.lock(); defer { verrou.unlock() }
            if valeurs[index] == nil { valeurs[index] = valeur }
        }

        func lire() -> [JSONValue?] {
            verrou.lock(); defer { verrou.unlock() }
            return valeurs
        }
    }

    /// Mesure les photos, deux à la fois au plus (Vision, `ToolHandler.parallelMeasures` : 25
    /// analyses lancées ensemble l'ont bloqué), chacune en `parPhoto` secondes au plus et toutes en
    /// `total` : une photo qui n'a pas fini, ou pas commencé, à temps a la raison `delai` ; sa mesure
    /// ne s'arrête pas (Vision ne s'interrompt pas), mais la ligne part sans elle, et le processus
    /// s'arrête avec elle.
    static func mesurerBorne(_ photos: [AAnalyser], mesurer: @escaping (AAnalyser) -> JSONValue,
                             parPhoto: TimeInterval, total: TimeInterval) -> [JSONValue] {
        let resultats = Resultats(photos.count)
        let places = DispatchSemaphore(value: ToolHandler.parallelMeasures)
        let groupe = DispatchGroup()
        let limite = DispatchTime.now() + total
        for (index, photo) in photos.enumerated() {
            guard places.wait(timeout: limite) == .success else { break }
            let finie = DispatchSemaphore(value: 0)
            groupe.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                resultats.ranger(mesurer(photo), a: index)
                finie.signal()
            }
            DispatchQueue.global(qos: .userInitiated).async {
                _ = finie.wait(timeout: min(DispatchTime.now() + parPhoto, limite))
                places.signal()
                groupe.leave()
            }
        }
        groupe.wait()
        let delai = Bilan.nombre(parPhoto, decimales: 0)
        return zip(photos, resultats.lire()).map { photo, valeur in
            valeur ?? sansAnalyse(photo.id, "delai", "Mesure trop longue (plus de \(delai) s, ou l'appel entier) : la photo n'est pas analysée.")
        }
    }
}
