import CoreGraphics
import Foundation
import XCTest
@testable import DeveloppeurKit

/// Un module simulé pour la recette de la 1.3 (Recette+13.swift) : l'état d'une copie d'essai
/// (réglages, recadrage, étapes de Claude et leurs avant/après, journal, exercice « Je le fais »,
/// registres des leçons et du carnet) et des rendus de synthèse (un gris, ou un horizon penché vu à
/// travers le recadrage), assez pour que chaque étape voie ce que Lightroom ferait. Des écarts
/// réglables (un avant rendu de nouveau, un cadre resserré, un angle mal lu…) vérifient que chaque
/// étape les signale. Le recadrage suit Recadrage.calculer et Recadrage.lire du module, tels que le
/// contrat de la composition (Tests/Contrats/composition.json) les fige.
final class ModuleRecette13: LightroomServing {
    /// L'image affichée entière, en pixels (le RAF de X-H2S du contrat).
    static let largeur = 6240.0, hauteur = 4160.0
    let id: Int
    let fichier = "DSCF1595.RAF (Essai)"
    let racine = TestSupport.temporaryDirectory()
    var reglages: [String: Double]
    var recadrage: [String: Double]?
    /// L'état où revert_to_original remet la photo (garderCommeDepart le change).
    private var depart: ([String: Double], [String: Double]?)

    struct Etape { var id: String; var nom: String; var reglages: [String: Double]; var recadrage: [String: Double]? }
    struct Capture { var avant: URL?; var apres: URL?; var etat: String; var raison: String?; var lecturesEnCours: Int }
    var memoire: [Etape] = []
    var defaites: [(id: String, nom: String)] = []
    var journal: [JSONValue] = []
    var captures: [String: Capture] = [:]
    private var compteur = 0
    private var vue: (empreinte: String, chemin: URL)?
    var exercice: (depart: [String: Double], claude: [String: Double])?
    var instantanes: [String] = []
    var lecons: [Int: JSONValue] = [:]
    var carnet: [Int: JSONValue] = [:]
    var commandes: [(nom: String, params: [String: JSONValue])] = []

    /// Dans « Développeur › Essais » pour find_photos, et pour le module (Carnet.estPhotoDEssai).
    var dansLaCollection = true, dansLesEssais = true
    /// La case Carnet du Gestionnaire décochée : tout constat est refusé (motif preference).
    var carnetDecoche = false
    /// Écarts d'un module fautif pour la leçon (1.3.1) : la leçon d'une photo d'essai rangée par
    /// l'outil (module 1.3), ou celle de la recette rangée sous l'original malgré essai_recette.
    var leconsDEssaiRangees = false, originalPourLaRecette = false
    var priseLe: String? = "2025-07-14 18:32"
    /// Le jour où find_photos retrouve la photo (par défaut celui de priseLe).
    var jourTrouve: String?
    /// La scène : un horizon penché (degrés) à `hauteurHorizon`, ou un gris uni.
    var horizon: Double?
    var hauteurHorizon = 0.55
    // Écarts réglables.
    var avantRenduDeNouveau = false
    var lecturesEnCours = 2
    var captureManquee: String?
    var cadreResserre = 1.0
    var angleLuIgnore = false
    var vueSansAngle = false
    var ecartsOublies: Set<String> = []
    /// L'écart des Crop* remis par l'image entière (apercu avec entier) : 0, ils reviennent exactement.
    var ecartRestauration = 0.0
    private var decalageBrut = 0.0
    /// Une erreur à lever pour une commande (selon ses paramètres et l'état).
    var erreur: ((String, [String: JSONValue]) -> Error?)?

    init(id: Int = 7, reglages: [String: Double] = ["Exposure2012": 0, "Temperature": 5000, "Tint": 10, "Vibrance": 0, "Shadows2012": 0]) {
        self.id = id
        self.reglages = reglages
        depart = (reglages, nil)
    }

    /// Les réglages posés avant la recette (une copie passée par Upright…) : l'état d'origine.
    func garderCommeDepart() { depart = (reglages, recadrage) }

    var aspect: Double { Self.largeur / Self.hauteur }
    var photoJSON: JSONValue { ["id": .number(Double(id)), "fichier": .string(fichier), "retouchee_par_claude": .bool(!memoire.isEmpty)] }
    /// Le mois de la prise de vue ; aucun sans date (le module rend alors mois = nil, sans_date).
    var mois: String? { priseLe.map { String($0.prefix(7)) } }
    var moisJSON: JSONValue { mois.map(JSONValue.string) ?? .null }
    func noms(_ commande: String) -> [String] { commandes.filter { $0.nom == commande }.compactMap { $0.params["action"]?.string } }
    func params(_ commande: String) -> [[String: JSONValue]] { commandes.filter { $0.nom == commande }.map(\.params) }

    // MARK: Rendus

    func luminance(_ x: Double, _ y: Double, _ r: [String: Double]) -> Double {
        var base = 110.0
        if let horizon {
            let ligne = hauteurHorizon - tan(horizon * .pi / 180) * (x - 0.5) * aspect
            base = y < ligne ? 200 : 70
        }
        return min(255, base * pow(2, (r["Exposure2012"] ?? 0) * 0.5))
    }

    /// Le cadre posé, comme Recadrage.calculer puis Recadrage.lire : {ratio, angle, centre, largeur en pixels}.
    func cadreModule(_ d: [String: Double], resserre: Double = 1) -> [String: JSONValue] {
        let ratio = d["ratio"] ?? aspect, angle = d["angle"] ?? 0, taille = d["taille"] ?? 1
        let cx = d["centre_x"] ?? 0.5, cy = d["centre_y"] ?? 0.5
        let t = abs(angle) * .pi / 180
        let bx = cos(t) + sin(t) / ratio, by = sin(t) + cos(t) / ratio
        let maximum = min(Self.largeur / bx, Self.hauteur / by)
        let w = min(taille * maximum, 2 * min(cx, 1 - cx) * Self.largeur / bx, 2 * min(cy, 1 - cy) * Self.hauteur / by) * resserre
        return ["ratio": .number(ratio), "angle": .number(angle), "centre_x": .number(cx), "centre_y": .number(cy), "largeur": .number(w)]
    }

    var dimensions: JSONValue { ["largeur": .number(Self.largeur), "hauteur": .number(Self.hauteur)] }

    func cadre(_ d: [String: Double]?) -> Composition.Cadre? {
        d.flatMap { Composition.Cadre(module: .object(cadreModule($0)), dimensions: dimensions) }
    }

    func image(_ r: [String: Double], cadre: Composition.Cadre?, cote: Int = 480) -> Data {
        let ratio = cadre?.ratio ?? aspect
        let w = ratio >= 1 ? cote : max(1, Int((Double(cote) * ratio).rounded()))
        let h = max(1, Int((Double(w) / ratio).rounded()))
        var vu = cadre
        if vueSansAngle { vu?.angle = 0 }
        return TestSupport.jpegPixels(width: w, height: h) { px, py in
            let p = Composition.versImageEntiere(CGPoint(x: (Double(px) + 0.5) / Double(w), y: (Double(py) + 0.5) / Double(h)),
                                                 cadre: vu, aspect: self.aspect)
            let v = UInt8(max(0, min(255, self.luminance(Double(p.x), Double(p.y), r).rounded())))
            return (v, v, v)
        }
    }

    func rendre(_ r: [String: Double], cadre: Composition.Cadre?) -> String { TestSupport.previewFile(image(r, cadre: cadre)) }

    func empreinte(_ r: [String: Double], _ c: [String: Double]?) -> String {
        r.keys.sorted().map { "\($0)=\(r[$0]!)" }.joined(separator: ",") + "|" + (c ?? [:]).keys.sorted().map { "\($0)=\(c![$0]!)" }.joined(separator: ",")
    }

    // MARK: Étapes

    /// Une étape « recette : pourquoi » d'un essai d'avant, défaite, dont les images restent.
    func ajouterEtapeDefaite() {
        let dossier = racine.appendingPathComponent("Etapes")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let avant = dossier.appendingPathComponent("e0-avant.jpg"), apres = dossier.appendingPathComponent("e0-apres.jpg")
        try? TestSupport.jpeg(red: 90, green: 90, blue: 90).write(to: avant)
        try? TestSupport.jpeg(red: 30, green: 30, blue: 30).write(to: apres)
        defaites.append(("e0", "Claude · recette : pourquoi"))
        captures["e0"] = Capture(avant: avant, apres: apres, etat: "pret", raison: nil, lecturesEnCours: 0)
    }

    private func capturer(_ etapeId: String, _ avantR: [String: Double], _ avantC: [String: Double]?) {
        let dossier = racine.appendingPathComponent("Etapes")
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        let avant = dossier.appendingPathComponent("\(etapeId)-avant.jpg"), apres = dossier.appendingPathComponent("\(etapeId)-apres.jpg")
        if let vue, vue.empreinte == empreinte(avantR, avantC), !avantRenduDeNouveau {
            try? FileManager.default.copyItem(at: vue.chemin, to: avant)
        } else {
            try? image(avantR, cadre: cadre(avantC), cote: 320).write(to: avant)
        }
        if captureManquee == nil { try? image(reglages, cadre: cadre(recadrage), cote: 320).write(to: apres) }
        try? JSONCoding.line(["etat": .string(captureManquee == nil ? "pret" : "manque"), "duree": 0.8, "photo": .number(Double(id))])
            .write(to: dossier.appendingPathComponent("\(etapeId).json"), atomically: true, encoding: .utf8)
        captures[etapeId] = Capture(avant: avant, apres: captureManquee == nil ? apres : nil, etat: captureManquee == nil ? "pret" : "manque",
                                    raison: captureManquee, lecturesEnCours: lecturesEnCours)
    }

    private func entree(_ etapeId: String, _ nom: String, _ enMemoire: Bool) -> JSONValue {
        guard var c = captures[etapeId] else {
            return ["id": .string(etapeId), "nom": .string(nom), "en_memoire": .bool(enMemoire), "avant": .null, "apres": .null, "etat": "inconnu", "raison": .null]
        }
        if c.lecturesEnCours > 0 {
            c.lecturesEnCours -= 1
            captures[etapeId] = c
            return ["id": .string(etapeId), "nom": .string(nom), "en_memoire": .bool(enMemoire), "avant": .null, "apres": .null, "etat": "en_cours", "raison": .null]
        }
        return ["id": .string(etapeId), "nom": .string(nom), "en_memoire": .bool(enMemoire),
                "avant": c.avant.map { .string($0.path) } ?? .null, "apres": c.apres.map { .string($0.path) } ?? .null,
                "etat": .string(c.etat), "raison": c.raison.map(JSONValue.string) ?? .null]
    }

    private func appliquer(_ demande: [String: JSONValue]?, relatif: Bool, a r: inout [String: Double]) -> [JSONValue] {
        var changements: [JSONValue] = []
        for (cle, valeur) in demande ?? [:] {
            guard let x = valeur.double else { continue }
            let ancien = r[cle] ?? 0, nouveau = relatif ? ancien + x : x
            r[cle] = nouveau
            changements.append(["cle": .string(cle), "avant": .number(ancien), "apres": .number(nouveau)])
        }
        return changements
    }

    // MARK: Commandes

    func send(_ command: String, _ params: [String: JSONValue], timeout: TimeInterval) throws -> JSONValue {
        commandes.append((command, params))
        if let erreur = erreur?(command, params) { throw erreur }
        let action = params["action"]?.string
        switch command {
        case "reglages":
            var r: [String: JSONValue] = ["photo": ["id": .number(Double(id)), "fichier": .string(fichier), "copie_virtuelle": true],
                                          "reglages": .object(reglages.mapValues { .number($0) }), "masques": [], "profil": "Adobe Color",
                                          "recadrage": recadrage.map { .object($0.mapValues { .number($0) }) } ?? ["angle": 0],
                                          "balance_des_blancs": "As Shot", "classement": ["note": 0]]
            if params["toutes"]?.bool == true {
                // Des Crop* bruts tirés du cadre posé (leur calcul exact ne sert pas ici : seulement
                // qu'ils reviennent tels quels).
                var tous = reglages.mapValues { JSONValue.number($0) }
                let c = recadrage ?? [:]
                tous["CropAngle"] = .number(c["angle"] ?? 0)
                tous["CropLeft"] = .number(c.isEmpty ? 0 : (c["centre_x"] ?? 0.5) - 0.3 * (c["taille"] ?? 1) + decalageBrut)
                tous["CropRight"] = .number(c.isEmpty ? 1 : (c["centre_x"] ?? 0.5) + 0.3 * (c["taille"] ?? 1))
                tous["CropTop"] = .number(c.isEmpty ? 0 : (c["centre_y"] ?? 0.5) - 0.3 * (c["taille"] ?? 1))
                tous["CropBottom"] = .number(c.isEmpty ? 1 : (c["centre_y"] ?? 0.5) + 0.3 * (c["taille"] ?? 1))
                tous["CropConstrainToWarp"] = 0
                r["tous"] = .object(tous)
            }
            return .object(r)
        case "apercu":
            var r: [String: JSONValue] = ["photo": photoJSON, "reglages": .object(reglages.mapValues { .number($0) }),
                                          "recadrage": ["angle": .number(recadrage?["angle"] ?? 0)],
                                          "echelle_temperature": "kelvins (RAW : 2000 à 50000)",
                                          "etapes_claude": ["nombre": .number(Double(memoire.count))]]
            if params["comparer"]?.string == "versionClaude", let ex = exercice {
                r["chemin_avant"] = .string(rendre(ex.claude, cadre: cadre(recadrage)))
                r["chemin"] = .string(rendre(reglages, cadre: cadre(recadrage)))
                let cles = Set(ex.depart.keys).union(ex.claude.keys).union(reglages.keys).subtracting(ecartsOublies).sorted()
                let ecarts: [JSONValue] = cles.compactMap { cle in
                    let d = ex.depart[cle] ?? 0, c = ex.claude[cle] ?? d, v = reglages[cle] ?? d
                    guard d != c || d != v else { return nil }
                    return ["cle": .string(cle), "depart": .number(d), "claude": .number(c), "vous": .number(v)]
                }
                r["exercice"] = ["instantane": "Claude · ma version", "le": "aujourd'hui", "ecarts": .array(ecarts), "listes": [:],
                                 "restent": [], "rien_change": false]
                return .object(r)
            }
            let entier = params["entier"]?.bool == true
            let chemin = rendre(reglages, cadre: entier ? nil : cadre(recadrage))
            r["chemin"] = .string(chemin)
            if params["avant_apres"]?.bool == true {
                let copie = racine.appendingPathComponent("vue-\(UUID().uuidString).jpg")
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: chemin), to: copie)
                vue = (empreinte(reglages, recadrage), copie)
            }
            if entier {
                r["image_entiere"] = true
                r["dimensions"] = dimensions
                if recadrage != nil { decalageBrut += ecartRestauration }
                if let recadrage {
                    var lu = cadreModule(recadrage)
                    if angleLuIgnore { lu["angle"] = 0 }
                    r["cadre_actuel"] = .object(lu)
                }
            }
            return .object(r)
        case "geometrie":
            return ["photos": [["photo": .number(Double(id)), "active": false]]]
        case "appliquer":
            let avantR = reglages, avantC = recadrage
            var changements = appliquer(params["reglages"]?.object, relatif: params["relatif"]?.bool == true, a: &reglages)
            if let demande = params["recadrage"]?.object {
                recadrage = demande.compactMapValues(\.double)
                changements.append(["cle": "CropAngle", "avant": .number(avantC?["angle"] ?? 0), "apres": .number(recadrage?["angle"] ?? 0)])
            }
            compteur += 1
            let etapeId = "e\(compteur)", nom = "Claude · " + (params["etape"]?.string ?? "retouche")
            memoire.append(Etape(id: etapeId, nom: nom, reglages: avantR, recadrage: avantC))
            journal.append(["type": "retouche", "etape": .string(nom), "etape_id": .string(etapeId), "changements": .array(changements)])
            if params["avant_apres"]?.bool == true { capturer(etapeId, avantR, avantC) }
            return ["resultats": [["photo": photoJSON, "etape": .string(nom), "etape_id": .string(etapeId), "changements": .array(changements),
                                   "remarques": []]]]
        case "annuler":
            guard let derniere = memoire.popLast() else { return ["resultats": [["photo": photoJSON, "annulee": false, "sans_retouche": true]]] }
            reglages = derniere.reglages
            recadrage = derniere.recadrage
            defaites.append((derniere.id, derniere.nom))
            journal.append(["type": "annulation", "etape": .string("Annulation de « \(derniere.nom) »"), "etape_id": .string(derniere.id)])
            return ["resultats": [["photo": photoJSON, "annulee": true, "etape": .string(derniere.nom), "etape_id": .string(derniere.id),
                                   "changements": []]]]
        case "revenir":
            (reglages, recadrage) = depart
            for etape in memoire.reversed() { defaites.append((etape.id, etape.nom)) }
            memoire = []
            journal.append(["type": "retour"])
            return ["resultats": [["photo": photoJSON, "changements": []]]]
        case "etapes":
            let liste = memoire.map { entree($0.id, $0.nom, true) } + defaites.map { entree($0.id, $0.nom, false) }
            return ["photo": photoJSON, "etapes": .array(liste)]
        case "journal":
            return ["photos": [["photo": ["id": .number(Double(id)), "fichier": .string(fichier), "appareil": "X-H2S", "format": "RAW"],
                                "entrees": .array(journal)]]]
        case "essayer":
            if params["exercice"]?.bool == true {
                var claude = reglages
                let changements = appliquer(params["reglages"]?.object, relatif: params["relatif"]?.bool == true, a: &claude)
                exercice = (reglages, claude)
                if !instantanes.contains("Claude · ma version") { instantanes.append("Claude · ma version") }
                journal.append(["type": "exercice", "etape": "Claude · je le fais", "changements": .array(changements)])
                return ["exercice": ["instantane": "Claude · ma version"], "changements": .array(changements), "raw": true, "photo": photoJSON,
                        "etape": "Claude · essai : ma version (je le fais)", "mode": "appliquer directement"]
            }
            var proposition = reglages
            let changements = appliquer(params["reglages"]?.object, relatif: params["relatif"]?.bool == true, a: &proposition)
            let demande = params["recadrage"]?.object?.compactMapValues(\.double)
            var r: [String: JSONValue] = ["chemin": .string(rendre(proposition, cadre: cadre(demande ?? recadrage))), "photo": photoJSON,
                                          "changements": .array(changements), "etape": "Claude · essai", "mode": "appliquer directement"]
            if params["entier"]?.bool == true, let demande {
                r["cadre_propose"] = .object(cadreModule(demande, resserre: cadreResserre))
                r["chemin_entier"] = .string(rendre(proposition, cadre: nil))
                r["dimensions"] = dimensions
            }
            return .object(r)
        case "variantes":
            if action == "effacer" {
                let voulus = (params["noms"]?.array ?? []).compactMap(\.string).map { $0.hasPrefix("Claude · ") ? $0 : "Claude · " + $0 }
                let effaces = instantanes.filter { voulus.isEmpty || voulus.contains($0) }
                instantanes.removeAll { effaces.contains($0) }
                if effaces.contains("Claude · ma version") { exercice = nil }
                return ["photo": photoJSON, "effaces": .array(effaces.map(JSONValue.string))]
            }
            return ["photo": photoJSON, "variantes": .array(instantanes.map { ["nom": .string($0), "reglages": []] })]
        case "chercher":
            guard dansLaCollection else { return ["photos": [], "total": 0] }
            if let debut = params["date_debut"]?.string, let fin = params["date_fin"]?.string {
                guard let jour = jourTrouve ?? priseLe.map({ String($0.prefix(10)) }), debut <= jour, jour <= fin else { return ["photos": [], "total": 0] }
            }
            return ["photos": [["id": .number(Double(id)), "fichier": .string(fichier)]], "total": 1]
        case "lecon":
            let voulues = (params["photos"]?.array ?? []).compactMap(\.int) + [params["photo"]?.int].compactMap { $0 }
            switch action {
            case "garder":
                // Comme Carnet.lua (1.3.1) : la leçon d'une photo d'essai n'est pas rangée, sauf avec
                // essai_recette, sous l'entrée de la photo d'essai ; une autre, sous son original (9001).
                if dansLesEssais, params["essai_recette"]?.bool != true, !leconsDEssaiRangees {
                    return ["photo": .number(Double(id)), "fichier": .string(fichier), "rangee": false, "remplacee": false, "motif": "essai",
                            "remarque": "Photo d'essai (Développeur › Essais) : sa leçon n'entre pas au carnet de progrès, qui ne compte que les vraies prises de vue. La leçon de cette réponse reste valable."]
                }
                let original = dansLesEssais && !originalPourLaRecette ? id : 9001
                let remplacee = lecons[id] != nil
                lecons[id] = ["photo": .number(Double(id)), "fichier": .string(fichier), "points": params["lecon"]?["points"] ?? [],
                              "original": .number(Double(original)), "mois": moisJSON]
                return ["photo": .number(Double(id)), "original": .number(Double(original)), "fichier": .string(fichier), "rangee": true,
                        "remplacee": .bool(remplacee), "mois": moisJSON, "prise_le": priseLe.map(JSONValue.string) ?? .null,
                        "sans_date": .bool(priseLe == nil)]
            case "lire":
                return ["lecons": .array(lecons.filter { voulues.isEmpty || voulues.contains($0.key) }.map(\.value))]
            default:
                let retirees = voulues.filter { lecons.removeValue(forKey: $0) != nil }.count
                return ["retirees": .number(Double(retirees))]
            }
        case "carnet":
            switch action {
            case "constater":
                let refus: (String, String) -> JSONValue = { motif, raison in
                    ["note": false, "motif": .string(motif), "raison": .string(raison), "photo": .number(Double(self.id))]
                }
                if carnetDecoche {
                    return refus("preference", "Carnet de progrès décoché dans le Gestionnaire de modules externes : rien n'est noté.")
                }
                if params["essai_recette"]?.bool != true, dansLesEssais {
                    return refus("essai", "Photo d'essai (Développeur › Essais) : le carnet ne compte que les vraies prises de vue.")
                }
                if params["vue"] != nil, !memoire.isEmpty {
                    return refus("etapes", "Photo déjà retouchée par Claude : sa prise de vue ne se mesure qu'avant la première retouche.")
                }
                // Une photo d'essai a son entrée à elle ; une autre, celle de son original (9001).
                let cle = dansLesEssais ? id : 9001
                let remplacee = carnet[cle] != nil
                carnet[cle] = ["photo": .number(Double(cle)), "prise": moisJSON, "prise_le": priseLe.map(JSONValue.string) ?? .null,
                               "sans_date": priseLe == nil ? true : .null, "angle": params["angle"] ?? .null, "vue": params["vue"] ?? .null, "lecons": []]
                return ["note": true, "constat": params["angle"] != nil ? "angle" : "vue", "photo": .number(Double(id)), "original": .number(Double(cle)),
                        "fichier": .string(fichier), "mois": moisJSON, "prise_le": priseLe.map(JSONValue.string) ?? .null,
                        "sans_date": .bool(priseLe == nil), "remplacee": .bool(remplacee)]
            case "lire":
                var r: [String: JSONValue] = ["catalogue": "Essais.lrcat", "nombre": .number(Double(carnet.count)),
                                              "photos": .array(carnet.keys.sorted().compactMap { carnet[$0] })]
                if params["resume"]?.bool == true {
                    r["resume"] = ["titres": ["carnet": "Carnet de progrès"], "vide": .bool(carnet.isEmpty), "photos": .number(Double(carnet.count)), "mois": []]
                }
                return .object(r)
            default:
                let ids = (params["photos"]?.array ?? []).compactMap(\.int)
                let retirees = ids.filter { carnet.removeValue(forKey: $0) != nil }.count
                return ["retirees": .number(Double(retirees))]
            }
        default:
            return [:]
        }
    }
}

/// La recette de la 1.3 face au module simulé : chaque étape réussit sur un module juste, et dit
/// l'écart d'un module fautif ; ce qu'elle pose se défait (réglages, leçon, carnet, « ma version »),
/// même après un échec.
final class Recette13Tests: XCTestCase {
    func recette(_ module: ModuleRecette13) -> Recette {
        let recette = Recette(lightroom: module)
        recette.attendre = { _ in }
        return recette
    }

    func details(_ recette: Recette) -> String { recette.etapes.map { "\($0.nom) : \($0.detail)" }.joined(separator: " | ") }

    // MARK: Pourquoi ?

    /// L'avant/après d'une étape : la vue gardée (avant_apres), l'étape écrite, l'après attendu le
    /// temps de sa capture, retrouvé par son identifiant même quand une étape défaite d'avant suit
    /// dans la liste, puis l'étape annulée et dite hors de la mémoire.
    func testPourquoiGardeLAvantApresPuisAnnule() throws {
        let module = ModuleRecette13()
        module.ajouterEtapeDefaite()
        let recette = recette(module)
        let depart = try recette.etat(7)
        try recette.etapePourquoi(7, "RAW 7", attendu: depart)
        XCTAssertTrue(recette.reussie, details(recette))
        let detail = try XCTUnwrap(recette.etapes.first?.detail)
        XCTAssertTrue(detail.contains("avant = la vue (480 × 320, sans second rendu)"), detail)
        XCTAssertTrue(detail.contains("(capture : 0.8 s)"), detail)
        // La vue, puis l'écriture, toutes deux avec avant_apres ; un seul réglage, pas de cadre.
        let apercu = try XCTUnwrap(module.params("apercu").first)
        XCTAssertEqual(apercu["avant_apres"]?.bool, true)
        let ecriture = try XCTUnwrap(module.params("appliquer").first)
        XCTAssertEqual(ecriture["avant_apres"]?.bool, true)
        XCTAssertEqual(ecriture["reglages"]?["Exposure2012"]?.double, 0.5)
        XCTAssertEqual(ecriture["relatif"]?.bool, true)
        XCTAssertEqual(ecriture["etape"]?.string, "recette : pourquoi")
        XCTAssertEqual(ecriture["confirme"]?.bool, true)
        XCTAssertNil(ecriture["recadrage"])
        // L'après se fait attendre deux lectures, puis l'étape est défaite.
        XCTAssertGreaterThanOrEqual(module.commandes.filter { $0.nom == "etapes" }.count, 4)
        XCTAssertEqual(module.commandes.map(\.nom).filter { ["appliquer", "annuler"].contains($0) }, ["appliquer", "annuler"])
        XCTAssertEqual(module.reglages, ["Exposure2012": 0, "Temperature": 5000, "Tint": 10, "Vibrance": 0, "Shadows2012": 0])
        XCTAssertTrue(module.memoire.isEmpty)
    }

    /// Un avant rendu de nouveau (la vue pas gardée, ou pas reconnue) et un après manqué se disent ;
    /// l'étape est défaite quand même.
    func testPourquoiDitUnAvantRenduDeNouveauOuManque() throws {
        let rendu = ModuleRecette13()
        rendu.avantRenduDeNouveau = true
        let premiere = recette(rendu)
        XCTAssertThrowsError(try premiere.etapePourquoi(7, "RAW 7", attendu: try premiere.etat(7)))
        XCTAssertTrue(premiere.etapes.first?.detail.contains("rendu de nouveau avant l'écriture") == true, details(premiere))
        XCTAssertTrue(rendu.memoire.isEmpty, "étape défaite malgré l'échec")

        let manque = ModuleRecette13()
        manque.captureManquee = "calculs_ia"
        let seconde = recette(manque)
        XCTAssertThrowsError(try seconde.etapePourquoi(7, "RAW 7", attendu: try seconde.etat(7)))
        XCTAssertTrue(seconde.etapes.first?.detail.contains("avant/après non gardé : manque (calculs_ia)") == true, details(seconde))
        XCTAssertTrue(manque.memoire.isEmpty)
    }

    /// Une capture qui ne finit pas : l'attente est bornée, et l'étape échoue en le disant.
    func testPourquoiNAttendPasSansFin() throws {
        let module = ModuleRecette13()
        module.lecturesEnCours = 10_000
        let recette = recette(module)
        XCTAssertThrowsError(try recette.etapePourquoi(7, "RAW 7", attendu: try recette.etat(7)))
        XCTAssertTrue(recette.etapes.first?.detail.contains("avant/après non gardé : en_cours") == true, details(recette))
        let lectures = module.commandes.filter { $0.nom == "etapes" }.count
        XCTAssertLessThanOrEqual(lectures, Int(Recette.attenteCapture / Recette.pasCapture) + 4)
    }

    // MARK: La leçon

    /// La photo telle que la séquence du RAW la laisse : une balance réchauffée de 300 K, puis une
    /// exposition remontée (la tonalité automatique) ; l'état de départ et celui-ci.
    func preparerLecon(_ recette: Recette, _ module: ModuleRecette13) throws -> (Recette.Etat, Recette.Etat) {
        let depart = try recette.etat(7)
        try recette.ecrire("apply_settings", 7, ["settings": ["Temperature": 300], "relative": true])
        try recette.ecrire("apply_settings", 7, ["settings": ["Exposure2012": 0.4]])
        return (depart, try recette.etat(7))
    }

    /// Les indices sous-exposée et dominante, d'après les corrections nettes depuis le départ (la
    /// balance de +300 K déjà au journal : −500 K depuis l'état actuel ne suffirait pas) ; la leçon de
    /// la copie d'essai refusée par l'outil (1.3.1 : elle n'entre pas au carnet de Dany), puis rangée
    /// pour la recette par la commande du module (essai_recette, jamais par un outil) sous l'entrée
    /// de la copie, relue, retirée ; l'écriture annulée.
    func testLeconRangeeRelueRetireePuisAnnulee() throws {
        let module = ModuleRecette13()
        let recette = recette(module)
        let (depart, attendu) = try preparerLecon(recette, module)
        try recette.etapeLecon(7, "RAW 7", depart: depart, attendu: attendu)
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertTrue(recette.etapes[0].detail.hasPrefix("indices underexposed, color_cast ; refusée par l'outil (photo d'essai) ; rangée pour la recette"),
                      details(recette))
        XCTAssertTrue(recette.etapes[0].detail.contains("(prise de vue 2025-07)"), details(recette))
        let ecriture = try XCTUnwrap(module.params("appliquer").last)
        XCTAssertEqual(try XCTUnwrap(ecriture["reglages"]?["Exposure2012"]?.double), 1.1, accuracy: 1e-9)
        XCTAssertEqual(ecriture["reglages"]?["Temperature"]?.double, 4500)
        XCTAssertEqual(module.noms("lecon"), ["lire", "garder", "lire", "garder", "lire", "retirer", "lire"])
        let garder = module.params("lecon").filter { $0["action"]?.string == "garder" }
        XCTAssertNil(garder[0]["essai_recette"], "photo_lesson ne porte jamais essai_recette")
        XCTAssertEqual(garder[1]["essai_recette"]?.bool, true)
        XCTAssertEqual(garder[1]["lecon"]?["points"]?.array?.count, 3)
        XCTAssertTrue(module.lecons.isEmpty)
        XCTAssertEqual(module.reglages["Exposure2012"], 0.4, "écriture annulée")
        XCTAssertEqual(module.reglages["Temperature"], 5300)
    }

    /// Un module qui range la leçon d'une copie d'essai par l'outil (module 1.3), ou celle de la
    /// recette sous l'original (une vraie photo de Dany) : l'étape le dit, et la leçon est retirée.
    func testLeconDEssaiRangeeAuMauvaisEndroitSeDit() throws {
        let module = ModuleRecette13()
        module.leconsDEssaiRangees = true
        let recette = recette(module)
        let (depart, attendu) = try preparerLecon(recette, module)
        XCTAssertThrowsError(try recette.etapeLecon(7, "RAW 7", depart: depart, attendu: attendu))
        XCTAssertTrue(recette.etapes[0].detail.contains("leçon d'une copie d'essai rangée par photo_lesson"), details(recette))
        XCTAssertTrue(module.lecons.isEmpty, "retirée malgré l'échec")
        XCTAssertEqual(module.reglages["Exposure2012"], 0.4, "écriture annulée")

        let original = ModuleRecette13()
        original.originalPourLaRecette = true
        let seconde = self.recette(original)
        let (depart2, attendu2) = try preparerLecon(seconde, original)
        XCTAssertThrowsError(try seconde.etapeLecon(7, "RAW 7", depart: depart2, attendu: attendu2))
        XCTAssertTrue(seconde.etapes[0].detail.contains("leçon de la recette rangée sous 9001"), details(seconde))
        XCTAssertTrue(original.lecons.isEmpty)
    }

    /// Une leçon déjà rangée pour la copie n'est pas remplacée : rien n'est écrit.
    func testLeconDejaRangeeArreteAvantToutEcriture() throws {
        let module = ModuleRecette13()
        module.lecons[7] = ["photo": 7, "points": []]
        let recette = recette(module)
        XCTAssertThrowsError(try recette.etapeLecon(7, "RAW 7", depart: try recette.etat(7), attendu: try recette.etat(7)))
        XCTAssertTrue(recette.etapes[0].detail.contains("une leçon est déjà rangée"), details(recette))
        XCTAssertEqual(module.noms("lecon"), ["lire"])
        XCTAssertTrue(module.params("appliquer").isEmpty)
        XCTAssertNotNil(module.lecons[7], "la leçon d'avant reste")
    }

    /// Une erreur après le rangement : la leçon est retirée quand même.
    func testLeconRetireeMemeApresUneErreur() throws {
        let module = ModuleRecette13()
        module.erreur = { [unowned module] commande, params in
            commande == "lecon" && params["action"]?.string == "lire" && module.lecons[7] != nil ? LightroomError.plugin("lecture impossible") : nil
        }
        let recette = recette(module)
        let (depart, attendu) = try preparerLecon(recette, module)
        XCTAssertThrowsError(try recette.etapeLecon(7, "RAW 7", depart: depart, attendu: attendu))
        XCTAssertEqual(module.noms("lecon"), ["lire", "garder", "lire", "garder", "lire", "retirer"])
        XCTAssertTrue(module.lecons.isEmpty)
    }

    // MARK: Le carnet

    /// Le carnet : la vue refusée comme photo d'essai, l'angle noté avec essai_recette à l'entrée de
    /// la copie, au mois de sa prise de vue (le même jour retrouvé par find_photos, pas la veille),
    /// relu, exporté, puis retiré ; rien n'est écrit dans le catalogue.
    func testCarnetRefuseNoteExporteRetire() throws {
        let module = ModuleRecette13()
        _ = try module.send("appliquer", ["reglages": ["Exposure2012": 0.2], "etape": "recette"], timeout: 1)
        let recette = recette(module)
        try recette.sequenceCarnet(7, "RAW 7")
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertTrue(recette.etapes[0].detail.contains("prise de vue 2025-07-14 18:32, retrouvée au même jour"), details(recette))
        XCTAssertEqual(module.noms("carnet"), ["constater", "constater", "lire", "lire", "retirer", "lire"])
        let constats = module.params("carnet").filter { $0["action"]?.string == "constater" }
        XCTAssertNotNil(constats[0]["vue"])
        XCTAssertNil(constats[0]["essai_recette"], "le refus d'abord, sans essai_recette")
        XCTAssertEqual(constats[1]["essai_recette"]?.bool, true)
        XCTAssertEqual(constats[1]["angle"]?["code"]?.string, "horizon_penche")
        XCTAssertNotNil(constats[1]["vocabulaire"]?.array)
        let jours = module.params("chercher").compactMap { $0["date_debut"]?.string }
        XCTAssertEqual(jours, ["2025-07-14", "2025-07-13"])
        XCTAssertTrue(module.carnet.isEmpty)
        XCTAssertFalse(module.commandes.contains { $0.nom == "appliquer" && $0.params["etape"]?.string != "recette" })
    }

    /// Une copie que le module ne voit pas dans les essais (refus pour ses étapes) : rien d'autre
    /// n'est envoyé, ni essai_recette (l'angle irait à l'original), ni retirer (l'entrée de
    /// l'original partirait).
    func testCarnetNeVaJamaisALOriginal() throws {
        let module = ModuleRecette13()
        module.dansLesEssais = false
        _ = try module.send("appliquer", ["reglages": ["Exposure2012": 0.2], "etape": "recette"], timeout: 1)
        let recette = recette(module)
        XCTAssertThrowsError(try recette.sequenceCarnet(7, "RAW 7"))
        XCTAssertTrue(recette.etapes[0].detail.contains("pas comme photo d'essai (motif etapes"), details(recette))
        XCTAssertEqual(module.noms("carnet"), ["constater"])
        XCTAssertTrue(module.carnet.isEmpty)

        // Hors de la collection de recette : sautée, aucune commande du carnet.
        let dehors = ModuleRecette13()
        dehors.dansLaCollection = false
        let autre = self.recette(dehors)
        try autre.sequenceCarnet(7, "RAW 7")
        XCTAssertTrue(autre.etapes[0].detail.hasPrefix("sautée"), details(autre))
        XCTAssertTrue(dehors.noms("carnet").isEmpty)
    }

    /// Le jour de la prise de vue mal lu (la veille retrouvée) se dit ; une erreur avant le retrait
    /// (l'export) laisse retirer l'entrée quand même.
    func testCarnetRetireMemeApresUnEchec() throws {
        let module = ModuleRecette13()
        module.jourTrouve = "2025-07-13"
        let recette = recette(module)
        XCTAssertThrowsError(try recette.sequenceCarnet(7, "RAW 7"))
        XCTAssertTrue(recette.etapes[0].detail.contains("la veille la retrouve"), details(recette))
        XCTAssertTrue(module.carnet.isEmpty)

        let export = ModuleRecette13()
        export.erreur = { commande, params in
            commande == "carnet" && params["resume"]?.bool == true ? LightroomError.plugin("résumé impossible") : nil
        }
        let seconde = self.recette(export)
        XCTAssertThrowsError(try seconde.sequenceCarnet(7, "RAW 7"))
        XCTAssertEqual(export.noms("carnet").last, "retirer")
        XCTAssertTrue(export.carnet.isEmpty)
    }

    /// Une copie sans date de prise de vue : le module ne dit pas de mois (sans_date), et la recette
    /// ne cherche pas de jour à retrouver ; l'entrée est retirée.
    func testCarnetSansDateDePriseDeVue() throws {
        let module = ModuleRecette13()
        module.priseLe = nil
        let recette = recette(module)
        try recette.sequenceCarnet(7, "RAW 7")
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertTrue(recette.etapes[0].detail.contains("sans date de prise de vue (comptée au mois du constat)"), details(recette))
        XCTAssertTrue(module.params("chercher").allSatisfy { $0["date_debut"] == nil }, "aucun jour cherché sans date")
        XCTAssertEqual(module.noms("carnet").last, "lire")
        XCTAssertTrue(module.carnet.isEmpty)
    }

    /// La case Carnet décochée refuse tout : l'étape le dit (la cocher), sans rien envoyer d'autre.
    func testCarnetCaseDecocheeSeDit() throws {
        let module = ModuleRecette13()
        module.carnetDecoche = true
        let recette = recette(module)
        XCTAssertThrowsError(try recette.sequenceCarnet(7, "RAW 7"))
        XCTAssertTrue(recette.etapes[0].detail.contains("motif preference"), details(recette))
        XCTAssertTrue(recette.etapes[0].detail.contains("cocher la case Carnet"), details(recette))
        XCTAssertFalse(recette.etapes[0].detail.contains("ne voit pas la copie"), details(recette))
        XCTAssertEqual(module.noms("carnet"), ["constater"])
    }

    // MARK: Les trois étapes après le bilan

    /// Après le bilan : l'avant/après d'une étape, la leçon, puis le carnet, dans cet ordre, chacun
    /// revenu à l'état d'avant (réglages, leçons, carnet).
    func testApprendreEnchaineLesTroisEtapes() throws {
        let module = ModuleRecette13()
        let recette = recette(module)
        let (depart, attendu) = try preparerLecon(recette, module)
        try recette.sequenceApprendre(7, "RAW 7", depart: depart, attendu: attendu)
        XCTAssertTrue(recette.reussie, details(recette))
        XCTAssertEqual(recette.etapes.map(\.nom), [
            "avant/après d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé",
            "leçon de la photo (photo_lesson) : indices lus, refusée pour une photo d'essai, rangée pour la recette (essai_recette), relue, retirée ; photo inchangée",
            "carnet de progrès : photo d'essai refusée, notée pour la recette (essai_recette), exportée, retirée",
        ])
        XCTAssertEqual(module.reglages, ["Exposure2012": 0.4, "Temperature": 5300, "Tint": 10, "Vibrance": 0, "Shadows2012": 0])
        XCTAssertEqual(module.memoire.count, 2, "les deux écritures de la préparation, rien de plus")
        XCTAssertTrue(module.lecons.isEmpty)
        XCTAssertTrue(module.carnet.isEmpty)
    }

    /// La séquence du RAW appelle la 1.3 à sa place (le faux module de ces essais ne la mène pas
    /// jusque-là : elle s'arrête à la balance) : après le bilan, l'avant/après, la leçon et le carnet,
    /// avant la mesure d'angle, qui laisse la géométrie intacte jusque-là ; « Je le fais » juste après
    /// les variantes, qui effacent toutes celles de Claude.
    func testLaSequenceDuRAWAppelleLaRecette13() throws {
        let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: racine.appendingPathComponent("Sources/DeveloppeurKit/Recette.swift"), encoding: .utf8)
        let debut = try XCTUnwrap(source.range(of: "func sequenceRAW("))
        let fin = try XCTUnwrap(source.range(of: "\n    }\n", range: debut.upperBound..<source.endIndex))
        let corps = String(source[debut.upperBound..<fin.lowerBound])
        func position(_ texte: String) throws -> String.Index { try XCTUnwrap(corps.range(of: texte), texte).lowerBound }
        let bilan = try position("try etapeBilan(id, photo, attendu: auto)")
        let apprendre = try position("try sequenceApprendre(id, photo, depart: depart, attendu: auto)")
        let angle = try position("\"mesure d'angle\"")
        XCTAssertTrue(bilan < apprendre && apprendre < angle)
        XCTAssertTrue(corps.contains("try sequenceVariantes(id, photo)\n"))
        let variantes = try position("try sequenceVariantes(id, photo)\n")
        let jeLeFais = try position("try sequenceJeLeFais(id, photo)")
        let entre = corps[corps.index(variantes, offsetBy: "try sequenceVariantes(id, photo)\n".count)..<jeLeFais]
        XCTAssertTrue(entre.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.allSatisfy { $0.isEmpty || $0.hasPrefix("//") },
                      "rien entre les variantes et « Je le fais » : \(entre)")
    }

    // MARK: Je le fais

    /// « Je le fais » : rien d'appliqué ni de rendu, a_faire dans l'ordre des panneaux, l'exercice au
    /// journal ; les réglages « de Dany » comparés (plus fort, ajouté, oublié) ; annulés, puis « ma
    /// version » effacée.
    func testJeLeFaisRangeCompareEfface() throws {
        let module = ModuleRecette13()
        let recette = recette(module)
        try recette.sequenceJeLeFais(7, "RAW 7")
        XCTAssertTrue(recette.reussie, details(recette))
        let essai = try XCTUnwrap(module.params("essayer").first)
        XCTAssertEqual(essai["exercice"]?.bool, true)
        XCTAssertEqual(essai["sans_rendu"]?.bool, true)
        XCTAssertEqual(essai["instantane"]?.string, "ma version")
        let dany = try XCTUnwrap(module.params("appliquer").first)
        XCTAssertEqual(dany["reglages"]?["Shadows2012"]?.double, 20)
        XCTAssertEqual(module.params("apercu").last?["comparer"]?.string, "versionClaude")
        XCTAssertEqual(module.noms("variantes"), ["lister", "lister", "effacer", "lister"])
        XCTAssertTrue(module.instantanes.isEmpty)
        XCTAssertNil(module.exercice)
        XCTAssertTrue(module.memoire.isEmpty, "réglages de Dany annulés")
    }

    /// Un écart oublié par le module se dit, et « ma version » est effacée quand même ; une « ma
    /// version » d'avant arrête l'étape avant toute écriture ; une erreur de comparaison laisse effacer.
    func testJeLeFaisDitLesEcartsEtEffaceToujours() throws {
        let oubli = ModuleRecette13()
        oubli.ecartsOublies = ["Vibrance"]
        let premiere = recette(oubli)
        XCTAssertThrowsError(try premiere.sequenceJeLeFais(7, "RAW 7"))
        XCTAssertTrue(premiere.etapes[0].detail.contains("écarts : Exposure2012 plus_fort, Shadows2012 ajoute"), details(premiere))
        XCTAssertTrue(oubli.instantanes.isEmpty)

        let reste = ModuleRecette13()
        reste.instantanes = ["Claude · ma version"]
        let seconde = recette(reste)
        XCTAssertThrowsError(try seconde.sequenceJeLeFais(7, "RAW 7"))
        XCTAssertTrue(seconde.etapes[0].detail.contains("est déjà rangée"), details(seconde))
        XCTAssertTrue(reste.params("essayer").isEmpty)
        XCTAssertEqual(reste.instantanes, ["Claude · ma version"], "rien n'est effacé de ce qu'elle n'a pas rangé")

        let comparaison = ModuleRecette13()
        comparaison.erreur = { commande, params in
            commande == "apercu" && params["comparer"] != nil ? LightroomError.plugin("rendu impossible") : nil
        }
        let troisieme = recette(comparaison)
        XCTAssertThrowsError(try troisieme.sequenceJeLeFais(7, "RAW 7"))
        XCTAssertEqual(comparaison.noms("variantes").last, "effacer")
        XCTAssertTrue(comparaison.instantanes.isEmpty)
    }

    // MARK: La composition (--horizon)

    func moduleHorizon() -> ModuleRecette13 {
        let module = ModuleRecette13()
        module.horizon = 1.2
        return module
    }

    func lancerHorizon(_ module: ModuleRecette13) -> (Recette, [String]) {
        var lignes: [String] = []
        let recette = Recette(lightroom: module) { lignes.append("\($0.reussie ? "✔" : "✘") \($0.nom)") }
        recette.attendre = { _ in }
        recette.hauteurHorizon = module.hauteurHorizon
        recette.lancer(raw: nil, jpeg: nil, flash: nil, horizon: 7)
        return (recette, lignes)
    }

    /// --horizon : la composition lue, le cadre proposé montré tel quel, le cadre actuel lu sur
    /// l'image entière (le recadrage d'essai du contrat), puis le cadre proposé appliqué : horizon sur
    /// le tiers du bas, droit ; les recadrages annulés, la photo remise à l'origine.
    func testHorizonLuProposeAppliqueDroitSurLeTiers() throws {
        let module = moduleHorizon()
        let (recette, lignes) = lancerHorizon(module)
        XCTAssertEqual(lignes, ["✔ photo d'essai",
                                "✔ composition lue, cadre proposé en pointillés, photo inchangée (read_composition, preview_settings)",
                                "✔ cadre actuel lu sur l'image entière (recadrée en 4:5, tournée de 2°)",
                                "✔ cadre proposé appliqué : horizon droit, sur le tiers du bas (measure_angle), puis annulé",
                                "✔ retour à l'origine"], details(recette))
        XCTAssertTrue(recette.etapes[1].detail.hasPrefix("horizon penché de 1."), details(recette))
        // Le recadrage d'essai : celui du contrat (4:5, 2°, centre 0,4 ; 0,5, 70 %).
        let essai = try XCTUnwrap(module.params("appliquer").first?["recadrage"])
        XCTAssertEqual(essai["ratio"]?.double, 0.8)
        XCTAssertEqual(essai["angle"]?.double, 2)
        XCTAssertEqual(essai["taille"]?.double, 0.7)
        XCTAssertEqual(essai["centre_x"]?.double, 0.4)
        // Deux recadrages, deux annulations, puis le retour à l'origine.
        XCTAssertEqual(module.commandes.map(\.nom).filter { ["appliquer", "annuler", "revenir"].contains($0) },
                       ["appliquer", "appliquer", "annuler", "annuler", "revenir"])
        XCTAssertNil(module.recadrage)
        // Le cadre proposé appliqué redresse l'horizon (angle −1,2 environ).
        let propose = try XCTUnwrap(module.params("appliquer").last?["recadrage"]?["angle"]?.double)
        XCTAssertEqual(propose, -1.2, accuracy: 0.15)
        XCTAssertTrue(module.params("apercu").contains { $0["entier"]?.bool == true }, "image entière lue")
        XCTAssertTrue(module.params("essayer").contains { $0["entier"]?.bool == true }, "proposition sur l'image entière")
    }

    /// Un cadre resserré par Lightroom, un cadre actuel mal lu, un horizon vu penché dans le cadre
    /// appliqué, une photo sans horizon net, une copie passée par Upright : chacun se dit, et la
    /// photo est remise à l'origine.
    func testHorizonDitChaqueEcart() throws {
        func echec(_ preparer: (ModuleRecette13) -> Void, _ etape: Int, _ texte: String, file: StaticString = #filePath, line: UInt = #line) {
            let module = moduleHorizon()
            preparer(module)
            let (recette, lignes) = lancerHorizon(module)
            XCTAssertEqual(lignes.last, "✔ remise à l'origine après l'échec", details(recette), file: file, line: line)
            XCTAssertEqual(lignes.firstIndex { $0.hasPrefix("✘") }, etape, lignes.joined(separator: " | "), file: file, line: line)
            XCTAssertTrue(recette.etapes[etape].detail.contains(texte), recette.etapes[etape].detail, file: file, line: line)
            XCTAssertNil(module.recadrage, file: file, line: line)
        }
        echec({ $0.cadreResserre = 0.97 }, 1, "le cadre gardé par Lightroom n'est pas le crop proposé : largeur")
        echec({ $0.ecartRestauration = 1e-5 }, 2, "recadrage pas remis exactement après read_composition : CropLeft")
        echec({ $0.angleLuIgnore = true }, 2, "cadre actuel lu sur l'image entière : angle 0° au lieu de 2°")
        echec({ $0.vueSansAngle = true }, 3, "dans le cadre au lieu de")
        echec({ $0.reglages["PerspectiveUpright"] = 2; $0.garderCommeDepart() }, 1, "la copie porte PerspectiveUpright")
    }

    /// Constaté le 21 octobre 2026 : la dune d'essai n'a pas d'horizon à mi-hauteur, et la mesure
    /// accrochée aux rides du sable faisait échouer l'étape « horizon » sur du bruit. Sans horizon net
    /// (la ligne lue n'est pas affinée), la recette ne la fait pas échouer : les deux premières étapes,
    /// qui n'en dépendent pas, le disent ; la troisième est sautée avec sa raison, le recadrage d'essai
    /// annulé, la photo remise à l'origine.
    func testHorizonSansContourNetSauteLEtapeAvecSaRaison() throws {
        let module = moduleHorizon()
        module.horizon = nil
        let (recette, lignes) = lancerHorizon(module)
        XCTAssertEqual(lignes, ["✔ photo d'essai",
                                "✔ composition lue, cadre proposé en pointillés, photo inchangée (read_composition, preview_settings)",
                                "✔ cadre actuel lu sur l'image entière (recadrée en 4:5, tournée de 2°)",
                                "✔ cadre proposé appliqué : horizon droit, sur le tiers du bas (measure_angle), puis annulé",
                                "✔ retour à l'origine"], details(recette))
        XCTAssertTrue(recette.etapes[1].detail.hasPrefix("pas d'horizon net à 0.55 de la hauteur"), details(recette))
        let saut = recette.etapes[3].detail
        XCTAssertTrue(saut.hasPrefix("sautée : pas d'horizon net"), saut)
        XCTAssertTrue(saut.contains("une copie d'Essais qui a un vrai horizon"), saut)
        XCTAssertTrue(saut.hasSuffix("recadrage d'essai annulé"), saut)
        // Un recadrage (celui d'essai), une annulation, puis le retour à l'origine : le cadre proposé
        // n'est jamais appliqué.
        XCTAssertEqual(module.commandes.map(\.nom).filter { ["appliquer", "annuler", "revenir"].contains($0) },
                       ["appliquer", "annuler", "revenir"])
        XCTAssertNil(module.recadrage)
    }

    /// Les Crop* remis au millionième près (mesure 5) suffisent ; au-delà, l'écart se dit.
    func testHorizonCadreRemisAuMillionieme() {
        let module = moduleHorizon()
        module.ecartRestauration = 5e-7
        let (recette, lignes) = lancerHorizon(module)
        XCTAssertFalse(lignes.contains { $0.hasPrefix("✘") }, details(recette))
        XCTAssertNil(module.recadrage)
    }

    /// Sans --horizon, aucune lecture de la composition.
    func testSansHorizonRienDeLaComposition() {
        let module = moduleHorizon()
        let recette = recette(module)
        recette.lancer(raw: nil, jpeg: nil, flash: nil)
        XCTAssertTrue(recette.etapes.isEmpty)
        XCTAssertTrue(module.commandes.isEmpty)
    }

    // MARK: Fonctions pures

    /// Les cadres de la recette, lus comme le contrat de la composition les fige : le crop proposé
    /// (exemple « proposer ») donne le cadre que Lightroom garde ; le recadrage d'essai (exemple
    /// « lire »), le cadre actuel lu sur l'image entière.
    func testCadresDuContrat() throws {
        let contrat = try JSONCoding.parse(String(contentsOf: ContratCompositionTests.fichier, encoding: .utf8))
        let lire = try XCTUnwrap(contrat["exemples"]?["lire"]?["apercu"]?["reponse"])
        let dimensions = lire["dimensions"]
        let aspect = try XCTUnwrap(dimensions?["largeur"]?.double) / XCTUnwrap(dimensions?["hauteur"]?.double)
        let actuel = try XCTUnwrap(Composition.Cadre(module: lire["cadre_actuel"], dimensions: dimensions))
        let essai = try XCTUnwrap(Recette.cadre(crop: Recette.cadreEssai, aspectImage: aspect))
        XCTAssertEqual(Recette.ecartsDeCadre(actuel, essai), [])
        let proposer = try XCTUnwrap(contrat["exemples"]?["proposer"])
        let garde = try XCTUnwrap(Composition.Cadre(module: proposer["essayer"]?["reponse"]?["cadre_propose"],
                                                    dimensions: proposer["essayer"]?["reponse"]?["dimensions"]))
        let crop = try XCTUnwrap(Recette.cadre(crop: proposer["preview_settings"]?["crop"], aspectImage: aspect))
        XCTAssertEqual(Recette.ecartsDeCadre(garde, crop), [])
        // Le faux module de ces essais lit et calcule comme le contrat.
        let module = ModuleRecette13()
        let simule = try XCTUnwrap(module.cadre(["ratio": 0.8, "angle": 2, "taille": 0.7, "centre_x": 0.4, "centre_y": 0.5]))
        XCTAssertEqual(Recette.ecartsDeCadre(simule, actuel), [])
        // « original » : le format de l'image ; un format illisible : pas de cadre ; un écart se dit.
        XCTAssertEqual(try XCTUnwrap(Recette.cadre(crop: ["aspect": "original", "size": 1], aspectImage: 1.5)).ratio, 1.5)
        XCTAssertNil(Recette.cadre(crop: ["aspect": "n'importe"], aspectImage: 1.5))
        XCTAssertNil(Recette.cadre(crop: "aucun", aspectImage: 1.5))
        var decale = essai
        decale.centreX += 0.01
        XCTAssertEqual(Recette.ecartsDeCadre(decale, essai).count, 1)
        XCTAssertNil(Recette.cadre(propose: ["ratio": 1.5]))
    }

    /// Deux points de l'horizon dans une image recadrée et tournée : sur la droite, aux abscisses
    /// voulues, et leur milieu sur la droite de l'image entière.
    func testSegmentDeLHorizonDansUnCadre() throws {
        let horizon = Recette.Horizon(milieu: CGPoint(x: 0.5, y: 0.55), inclinaison: 1.2, aspect: 1.5)
        let cadre = try XCTUnwrap(Recette.cadre(crop: Recette.cadreEssai, aspectImage: 1.5))
        let segment = try XCTUnwrap(horizon.segment(dans: cadre))
        XCTAssertEqual(Double(segment.0.x), 0.15, accuracy: 1e-9)
        XCTAssertEqual(Double(segment.1.x), 0.85, accuracy: 1e-9)
        for point in [segment.0, segment.1] {
            let entier = Composition.versImageEntiere(point, cadre: cadre, aspect: 1.5)
            let attendu = 0.55 - tan(1.2 * .pi / 180) * (Double(entier.x) - 0.5) * 1.5
            XCTAssertEqual(Double(entier.y), attendu, accuracy: 1e-9)
        }
        let attenduMilieu = 0.55 - tan(1.2 * .pi / 180) * (Double(segment.milieu.x) - 0.5) * 1.5
        XCTAssertEqual(Double(segment.milieu.y), attenduMilieu, accuracy: 1e-9)
        // Sans cadre : l'image entière ; une droite qui sort du cadre : rien.
        XCTAssertNotNil(horizon.segment(dans: nil))
        XCTAssertNil(Recette.Horizon(milieu: CGPoint(x: 0.5, y: 0.02), inclinaison: 30, aspect: 1.5).segment(dans: nil))
    }

    /// L'horizon mesuré dans le cadre appliqué : droit quand le cadre redresse, tel quel sous le
    /// seuil ; un angle proposé du mauvais signe (l'horizon tourné du double, que la géométrie seule
    /// accepterait) et un cadre que Lightroom tournerait à l'envers se disent.
    func testHorizonAppliqueDroitEtGeometrie() {
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 0.05, inclinaison: 1.2, angleCadre: -1.2), [])
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 0.3, inclinaison: 0.3, angleCadre: 0), [])
        // Près du seuil (inclinaison arrondie), redressé ou non.
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 0.5, inclinaison: 0.5, angleCadre: 0), [])
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 0, inclinaison: 0.5, angleCadre: -0.5), [])
        // L'angle proposé du mauvais signe : t + a = 2,4, mais l'horizon n'est pas redressé.
        let signe = Recette.ecartsHorizonApplique(vu: 2.4, inclinaison: 1.2, angleCadre: 1.2)
        XCTAssertEqual(signe.count, 1, signe.joined(separator: " | "))
        XCTAssertTrue(signe.first?.hasPrefix("horizon pas redressé") == true, signe.joined(separator: " | "))
        // Lightroom qui tournerait le cadre à l'envers : les deux écarts.
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 2.4, inclinaison: 1.2, angleCadre: -1.2).count, 2)
        // Sous le seuil, un cadre qui le penche davantage.
        XCTAssertEqual(Recette.ecartsHorizonApplique(vu: 2.3, inclinaison: 0.3, angleCadre: 2).count, 1)
    }

    /// Les Crop* relus : un nombre au millionième près, toute autre valeur exactement.
    func testChangementsBrutsAuMillionieme() {
        XCTAssertEqual(Recette.changementsBruts(["CropLeft": 0.1, "CropAngle": 2], ["CropLeft": 0.1000005, "CropAngle": 2]), [])
        XCTAssertEqual(Recette.changementsBruts(["CropLeft": 0.1], ["CropLeft": 0.10001]).count, 1)
        XCTAssertEqual(Recette.changementsBruts(["CropConstrainToWarp": 0], ["CropConstrainToWarp": 1]), ["CropConstrainToWarp 0 → 1"])
        XCTAssertEqual(Recette.changementsBruts(["CropConstrainToWarp": 0], [:]), ["CropConstrainToWarp 0 → —"])
        XCTAssertEqual(Recette.changementsBruts(["CropUnit": "pixels"], ["CropUnit": "pouces"]).count, 1)
    }

    func testMoisVeilleEtDureeDeCapture() throws {
        XCTAssertTrue(Recette.estUnMois("2025-07"))
        XCTAssertFalse(Recette.estUnMois("2025-13"))
        XCTAssertFalse(Recette.estUnMois("2025-07-14"))
        XCTAssertEqual(Recette.veille("2025-03-01"), "2025-02-28")
        XCTAssertEqual(Recette.veille("2024-03-01"), "2024-02-29")
        XCTAssertEqual(Recette.veille("2026-01-01"), "2025-12-31")
        XCTAssertNil(Recette.veille("hier"))
        let dossier = TestSupport.temporaryDirectory()
        try #"{"duree":1.25,"etat":"pret"}"#.write(to: dossier.appendingPathComponent("e3.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Recette.dureeCapture(dossier: dossier, etape: "e3"), 1.25)
        XCTAssertNil(Recette.dureeCapture(dossier: dossier, etape: "e4"))
        let sombre = TestSupport.jpeg(red: 60, green: 60, blue: 60), clair = TestSupport.jpeg(red: 160, green: 160, blue: 160)
        XCTAssertGreaterThan(try XCTUnwrap(Recette.luminanceMoyenne(clair)), try XCTUnwrap(Recette.luminanceMoyenne(sombre)))
        XCTAssertTrue(Recette.dimensions(sombre)! == (300, 200))
        XCTAssertNil(Recette.dimensions(Data("rien".utf8)))
    }

    // MARK: Constats du 21 octobre 2026 (lot 18)

    /// La photo active d'avant un passage au module Développement (débruitage, son annulation) doit
    /// revenir : constaté trois fois qu'une autre photo restait active. L'étape le vérifie par
    /// get_status.
    func testLaPhotoActiveDAvantDoitRevenir() throws {
        XCTAssertNil(Recette.ecartPhotoActive(avant: 53448416, apres: 53448416))
        XCTAssertNil(Recette.ecartPhotoActive(avant: nil, apres: 53448372), "pas de photo active au départ : rien à remettre")
        let ecart = try XCTUnwrap(Recette.ecartPhotoActive(avant: 53448416, apres: 53448372))
        XCTAssertTrue(ecart.hasPrefix("photo active 53448372 au lieu de 53448416"), ecart)
        XCTAssertTrue(try XCTUnwrap(Recette.ecartPhotoActive(avant: 53448416, apres: nil)).hasPrefix("photo active aucune"))
        let fake = FakeLightroom()
        fake.replies["etat"] = ["photo_active": ["id": 53448416, "fichier": "XH2S9386.RAF"]]
        let recette = Recette(lightroom: fake)
        XCTAssertEqual(try recette.photoActive(), 53448416)
        XCTAssertEqual(fake.commands, ["etat"], "lue par get_status, sans rien écrire")
        fake.replies["etat"] = ["photo_active": .null]
        XCTAssertNil(try recette.photoActive())
    }

    /// Le registre des notes (notation.json) ne voit pas undo_last : après l'étape de notation de la
    /// recette, la proposition de 53709912 restait « acceptee ». La recette le remet comme elle l'a
    /// trouvé (commande notation remettre), même après un échec, et vérifie qu'il l'est.
    func testLeRegistreDesNotesEstRemisCommeAvant() throws {
        let fake = FakeLightroom()
        let avant: JSONValue = ["photo": 12, "fichier": "DSCF2402.RAF (Essai)", "note": 2, "etat": "a_verifier", "le": 1792000000]
        var registre: JSONValue? = avant
        var remises: [JSONValue] = []
        fake.onSend = { [unowned fake] commande, params in
            guard commande == "notation" else { return }
            switch params["action"]?.string {
            case "remettre":
                remises.append(params["proposition"] ?? .null)
                if let proposition = params["proposition"], !proposition.isNull { registre = proposition } else { registre = nil }
                fake.replies["notation"] = ["photo": 12, "proposition": registre ?? .null]
            default:
                fake.replies["notation"] = ["propositions": .array(registre.map { [$0] } ?? [])]
            }
        }
        let recette = Recette(lightroom: fake)
        // L'étape pose la note : le registre la dit acceptée.
        let detail = try recette.garderRegistreDesNotes(12) { () -> String in
            registre = ["photo": 12, "fichier": "DSCF2402.RAF (Essai)", "note": 2, "etat": "acceptee", "le": 1792000100, "decide_le": 1792000100]
            return "posée, puis annulée"
        }
        XCTAssertEqual(detail, "posée, puis annulée")
        XCTAssertEqual(registre, avant, "la proposition d'avant, telle quelle")
        XCTAssertEqual(remises, [avant])
        XCTAssertEqual(fake.calls.compactMap { $0.params["action"]?.string }, ["lire", "remettre", "lire"])
        XCTAssertFalse(fake.commands.contains { $0 != "notation" }, "rien d'autre, rien dans le catalogue")

        // Aucune proposition au départ : celle de la recette est retirée, même après un échec.
        registre = nil
        remises = []
        struct Panne: Error {}
        XCTAssertThrowsError(try recette.garderRegistreDesNotes(12) { () -> String in
            registre = ["photo": 12, "note": 2, "etat": "acceptee"]
            throw Panne()
        })
        XCTAssertNil(registre)
        XCTAssertEqual(remises, [.null])

        // Un module qui ne remet rien : l'écart se dit.
        var lectures = 0
        fake.onSend = { [unowned fake] commande, params in
            guard commande == "notation", params["action"]?.string == "lire" else { return }
            lectures += 1
            fake.replies["notation"] = ["propositions": [["photo": 12, "etat": .string(lectures == 1 ? "a_verifier" : "acceptee")]]]
        }
        XCTAssertThrowsError(try recette.garderRegistreDesNotes(12) { "rien" }) { erreur in
            XCTAssertTrue("\(erreur)".contains("registre des notes pas remis"), "\(erreur)")
        }
    }
}
