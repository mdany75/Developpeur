import CoreGraphics
import ImageIO
import Foundation

/// Recette dans le vrai Lightroom (`mcp-developpeur --recette`) : rejoue sur des photos d'essai ce
/// que Claude fait d'habitude, par les mêmes outils, vérifie chaque étape sur les réglages relus,
/// puis remet chaque photo dans son état d'avant Claude, même après un échec. Des copies
/// virtuelles seulement, sauf avec `originaux` (`--original`) : un original revient aux mêmes
/// réglages, mais son historique garde les étapes de la recette.
/// Les défauts que la simulation ne connaît pas encore s'y voient (balance des blancs tombée aux
/// butées, masques remplacés, aperçu bloqué).
public final class Recette {
    public struct Etape: Equatable {
        public var photo: String
        public var nom: String
        public var reussie: Bool
        public var detail: String
        public var duree: TimeInterval
    }

    struct Echec: Error, CustomStringConvertible {
        var description: String
    }

    /// Ce que la recette compare d'une étape à l'autre.
    struct Etat: Equatable {
        var reglages: JSONValue
        var masques: JSONValue
        var profil: JSONValue
        var recadrage: JSONValue
        var balance: String?
        var copieVirtuelle: Bool?
        /// Note, drapeau, libellé, titre et mots-clés (get_settings).
        var classement: JSONValue = .null

        var nombreMasques: Int { masques.array?.count ?? 0 }
        var temperature: Double? { reglages["Balance des blancs"]?["Temperature"]?.double }
        var teinte: Double? { reglages["Balance des blancs"]?["Tint"]?.double }
        var comparable: [JSONValue] { [reglages, masques, profil, recadrage, classement] }
    }

    let tools: ToolHandler
    let images: URL?
    let originaux: Bool
    let rapport: (Etape) -> Void
    public private(set) var etapes: [Etape] = []
    /// L'écran du Mac, posé dans les outils le temps de l'étape « écran nommé ». Aucun par défaut,
    /// comme ToolHandler.lireEcran : main.swift pose `Ecran.lire` pour `--recette`, les tests un
    /// écran fabriqué (swift test ne lit jamais le vrai écran, même avec un vrai pont).
    public var lireEcran: () -> Ecran.Etat? = { nil }
    /// Hauteur de l'horizon de la photo de `--horizon`, de 0 à 1 dans l'image que montre view_photo
    /// (`--hauteur-horizon` ; le milieu par défaut).
    public var hauteurHorizon = 0.5
    /// Attente entre deux lectures d'une capture (1.3, avant/après d'une étape) : les tests ne
    /// dorment pas.
    var attendre: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }

    public init(lightroom: LightroomServing, images: URL? = nil, originaux: Bool = false,
                rapport: @escaping (Etape) -> Void = { _ in }) {
        tools = ToolHandler(lightroom: lightroom)
        self.images = images
        self.originaux = originaux
        self.rapport = rapport
    }

    public var reussie: Bool { !etapes.isEmpty && etapes.allSatisfy(\.reussie) }

    /// Lance les séquences demandées : un RAW (obligatoire en pratique), un JPEG, une photo au flash
    /// avec des yeux rouges, un portrait (la peau dosée), une photo qui a un horizon (la composition
    /// lue, 1.3) et une photo à deux lumières (l'éclairage mixte nommé). Avec le vrai pont seulement
    /// (pas le faux module des tests, qui attendent la liste exacte des étapes, et qui ne doivent
    /// jamais lire le vrai écran), d'abord la liaison fermée et l'écran nommé.
    public func lancer(raw: Int?, jpeg: Int?, flash: Int?, profondeur: Int? = nil, yeuxRouges: Int? = nil, xt20: Int? = nil,
                       portrait: Int? = nil, mixte: Int? = nil, horizon: Int? = nil) {
        if let pont = tools.lightroom as? LightroomBridge {
            sequenceLiaison(pont)
            sequenceEcran()
        }
        if let raw { sequence("RAW \(raw)", id: raw, corps: sequenceRAW) }
        if let jpeg { sequence("JPEG \(jpeg)", id: jpeg, corps: sequenceJPEG) }
        if let flash { sequence("flash \(flash)", id: flash, corps: sequenceFlash) }
        if let profondeur { try? sequenceProfondeur(profondeur, "profondeur \(profondeur)") }
        if let yeuxRouges { sequence("yeux rouges \(yeuxRouges)", id: yeuxRouges, corps: sequenceYeuxRouges) }
        if let xt20 { sequence("X-T20 \(xt20)", id: xt20, corps: sequenceXT20) }
        if let portrait { sequence("portrait \(portrait)", id: portrait, corps: sequencePortrait) }
        // 1.3, la composition lue (Recette+13.swift) : sans --horizon, rien n'en est vérifié.
        if let horizon { sequence("horizon \(horizon)", id: horizon, corps: sequenceHorizon) }
        if let mixte { sequenceEclairage(mixte, unique: raw == mixte ? nil : raw) }
        if let raw, let jpeg { try? sequenceSerie(reference: raw, autre: jpeg) }
        if let raw, let flash { try? sequenceExpositions(reference: raw, autre: flash) }
    }

    // MARK: - Liaison et écran (vrai pont seulement)

    /// Liaison fermée (1.2) : le module refuse une commande sans le jeton privé de la liaison, ou
    /// avec un autre jeton, et laisse passer celui qu'il a écrit dans liaison.jeton (le pont de la
    /// recette le relit). Lecture seule : la commande etat, jamais une écriture. Un module d'avant
    /// la 1.2 ne dit pas liaison_fermee : rien d'autre n'est essayé.
    func sequenceLiaison(_ pont: LightroomBridge) {
        try? etape("liaison", "liaison fermée (jeton privé)") {
            let (statut, _) = try appel("get_status", [:])
            guard statut["liaison_fermee"]?.bool == true else {
                throw Echec(description: "module d'avant la 1.2 (get_status ne dit pas liaison_fermee) : rien d'autre essayé")
            }
            // Ni le jeton ni son chemin ne partent chez Claude.
            let texte = JSONCoding.line(statut)
            try verifier(!texte.contains(JetonLiaison.nomFichier), "le chemin du jeton est dans get_status")
            if let jeton = pont.fichierJeton.flatMap(JetonLiaison.lire) {
                try verifier(!texte.contains(jeton), "le jeton est dans get_status")
            }
            // Le refus d'un pont vers le même module, sans jeton ou avec un autre ; nil s'il passe.
            func refus(_ fichierJeton: URL?) -> String? {
                let autre = LightroomBridge(host: pont.host, requestPort: pont.requestPort, replyPort: pont.replyPort, fichierJeton: fichierJeton)
                defer { autre.disconnect() }
                do {
                    _ = try autre.send("etat", [:], timeout: 10)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            let sans = refus(nil)
            try verifier(sans?.contains("Liaison fermée") == true, "commande sans jeton : \(sans ?? "acceptée")")
            // Un autre jeton bien formé (64 zéros), dans un fichier temporaire effacé ensuite.
            let faux = FileManager.default.temporaryDirectory.appendingPathComponent("recette-jeton-\(UUID().uuidString)")
            try Data((String(repeating: "0", count: 64) + "\n").utf8).write(to: faux)
            defer { try? FileManager.default.removeItem(at: faux) }
            let autre = refus(faux)
            try verifier(autre?.contains("Liaison fermée") == true, "commande avec un autre jeton : \(autre ?? "acceptée")")
            _ = try appel("get_status", [:])
            return "sans jeton et avec un autre jeton : refusées ; le jeton de la liaison passe"
        }
    }

    /// Écran nommé (1.2) : get_status dit l'écran principal du Mac, sans le chemin de son profil.
    /// La lecture de l'écran n'est posée dans les outils que le temps de l'étape : la remarque d'un
    /// aperçu ne doit jamais s'ajouter aux view_photo de la recette (appel recolle les blocs de texte
    /// avant de lire le JSON), et get_status la tient pour dite.
    func sequenceEcran() {
        try? etape("Mac", "écran nommé (get_status)") {
            tools.lireEcran = lireEcran
            defer { tools.lireEcran = { nil } }
            let (statut, _) = try appel("get_status", [:])
            guard let ecran = statut["ecran"], let principal = ecran["principal"] else {
                throw Echec(description: "aucun écran lu (session sans écran ?)")
            }
            let classes = Ecran.Etalonnage.allCases.map(\.rawValue)
            try verifier(principal["nom"]?.string?.isEmpty == false, "écran sans nom : \(JSONCoding.line(principal))")
            try verifier(classes.contains(principal["etalonnage"]?.string ?? ""), "classe inconnue : \(JSONCoding.line(principal))")
            try verifier(!JSONCoding.line(ecran).contains("\"chemin\""), "le chemin du profil est allé à Claude")
            let autres = ecran["autres"]?.array?.count ?? 0
            return (principal["texte"]?.string ?? "?") + (autres > 0 ? " ; \(autres) autre(s) écran(s)" : "")
        }
    }

    // MARK: - Séquences

    func sequenceRAW(_ id: Int, _ depart: Etat, _ photo: String) throws {
        guard let t0 = depart.temperature, let tint0 = depart.teinte else { throw Echec(description: "pas de balance des blancs lisible") }
        let m0 = depart.nombreMasques
        var balance = depart
        try etape(photo, "balance personnalisée") {
            try ecrire("apply_settings", id, ["settings": ["Temperature": 300, "Tint": 4], "relative": true])
            balance = try etat(id)
            try verifier(balance.balance == "Custom", "balance « \(balance.balance ?? "?") » au lieu de Custom")
            try verifierProche(balance.temperature, t0 + 300, "température")
            try verifierProche(balance.teinte, tint0 + 4, "teinte")
            return "\(Self.nombre(t0)) → \(Self.nombre(t0 + 300)) K"
        }
        // Constaté dans Lightroom Classic 15.6 : « Camera PRO Neg. Hi » n'existe pas pour un X-H2S
        // (« Camera Pro Neg Hi » oui) ; Lightroom posait Adobe Standard après coup, et bloquait les
        // profils suivants. Le serveur envoie le nom de l'appareil, le module relit le profil.
        try etape(photo, "profil d'appareil (PRO Neg. Hi)") {
            let (reponse, _) = try appel("apply_settings", ["photo_ids": [.number(Double(id))], "profile": "Camera PRO Neg. Hi",
                                                            "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let resultat = reponse["resultats"]?.array?.first
            let remarques = (resultat?["remarques"]?.array ?? []).compactMap(\.string)
            if remarques.contains(where: { $0.contains("réservé aux appareils") }) {
                return "sauté : \(remarques.joined(separator: " ; "))"
            }
            let apres = try etat(id)
            try verifier(remarques.isEmpty && apres.profil.string?.lowercased().contains("pro neg") == true,
                         "profil relu \(JSONCoding.line(apres.profil))\(remarques.isEmpty ? "" : " : " + remarques.joined(separator: " ; "))")
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), balance)
            return "\(apres.profil.string ?? "?") posé et relu, puis annulé"
        }
        try etapeIntention(id, photo)
        // Constaté en 2.3 : sous Camera ACROS, le mélangeur noir et blanc ne change rien (le profil
        // rend déjà du gris) ; le plan le dit en remarque.
        try etape(photo, "mélangeur sous ACROS") {
            let (profil, _) = try appel("apply_settings", ["photo_ids": [.number(Double(id))], "profile": "Camera ACROS",
                                                           "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            if (profil["resultats"]?.array?.first?["remarques"]?.array ?? []).contains(where: { $0.string?.contains("réservé aux appareils") == true }) {
                return "sauté : pas un RAW Fujifilm"
            }
            let (melange, _) = try appel("apply_settings", ["photo_ids": [.number(Double(id))], "settings": ["GrayMixerBlue": -80],
                                                            "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let remarques = (melange["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), balance)
            try verifier(remarques.contains { $0.contains("sans effet sous le profil") }, "remarques : \(remarques.joined(separator: " ; "))")
            return "remarque « sans effet » sous ACROS, puis annulé"
        }
        // Constaté dans Lightroom Classic 15.6 : posé par applyDevelopSettings, un profil adaptatif
        // restait rangé sans calcul ; par un paramètre prédéfini du module, Lightroom le calculait au
        // rendu suivant, par la fenêtre « Mises à jour IA recommandées » (jusqu'à la 2.5, le veilleur y
        // répondait). Depuis la 1.8, photo:updateAISettings() le calcule dès la retouche : ouverte,
        // la fenêtre attendrait un clic, et l'aperçu ne viendrait pas (délai de la liaison dépassé).
        let photoID = JSONValue.number(Double(id))
        func calculAdaptatif() throws -> JSONValue? {
            try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["AILook"]
        }
        try etape(photo, "profil adaptatif (Adaptive Color), calculé sans fenêtre") {
            let (reponse, _) = try appel("apply_settings", ["photo_ids": [photoID], "profile": "Adaptive Color",
                                                            "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let remarques = (reponse["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
            let profil = try etat(id).profil
            try verifier(profil.string == "Adaptive Color",
                         "profil relu \(JSONCoding.line(profil))\(remarques.isEmpty ? "" : " : " + remarques.joined(separator: " ; "))")
            let desLaRetouche = try calculAdaptatif()?["AILookData"]?.string != nil
            let (vue, _) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            let calcul = try calculAdaptatif()
            try verifier(calcul?["AILookData"]?.string != nil, "pas calculé au rendu : AILook \(calcul.map(JSONCoding.line) ?? "absent")")
            try verifier(vue["a_savoir"] == nil, vue["a_savoir"]?.string ?? "")
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), balance)
            return "\(desLaRetouche ? "calculé dès la retouche" : "calculé avant le rendu"), sans fenêtre, puis annulé"
        }
        // L'arrière-plan plutôt que le ciel : depuis la 2.1, un masque que Lightroom trouve vide est
        // retiré, et une photo d'essai peut n'avoir aucun ciel (constaté sur une photo de groupe).
        try etape(photo, "masque IA (arrière-plan), avec courbe et grain locaux, calculé sans fenêtre") {
            try ecrire("add_mask", id, ["masks": [["kind": "background", "name": "Recette arrière-plan", "adjustments": ["Exposure": -0.1, "Grain": 10],
                                                   "tone_curve": ["rgb": [[0, 8], [255, 250]]]]]])
            let apres = try etat(id)
            try verifier(apres.nombreMasques == m0 + 1, "\(apres.nombreMasques) masques au lieu de \(m0 + 1)")
            try verifierBalance(apres, balance)
            let locaux = apres.masques.array?.last?["reglages_locaux"]
            try verifier(locaux?["LocalGrain"]?.double.map { abs($0 - 0.1) < 0.001 } == true && locaux?["MainCurve"] != nil,
                         "courbe et grain locaux relus : \(locaux.map(JSONCoding.line) ?? "aucun")")
            let corrections = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["MaskGroupBasedCorrections"]?.array
            let calcule = corrections?.last?["CorrectionMasks"]?.array?.first?["MaskDigest"]?.string != nil
            let (vue, _) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            try verifier(vue["a_savoir"] == nil, vue["a_savoir"]?.string ?? "")
            return "\(apres.nombreMasques) masque(s), \(calcule ? "calculé dès la retouche" : "calculé avant le rendu"), sans fenêtre ; courbe et grain relus ; balance gardée"
        }
        var deuxMasques = balance
        // Un effet local de Lightroom (menu Effet du panneau Masque), par son nom d'Adobe : Densité −
        // (Éclaircir) pose +0,25 IL (exposure2012 = 0,0625 dans son fichier).
        try etape(photo, "second masque IA (sujet), avec un effet local") {
            try ecrire("add_mask", id, ["masks": [["kind": "subject", "name": "Recette sujet", "effect": "Dodge (Lighten)"]]])
            deuxMasques = try etat(id)
            try verifier(deuxMasques.nombreMasques == m0 + 2, "\(deuxMasques.nombreMasques) masques au lieu de \(m0 + 2) : le premier a été remplacé")
            try verifierBalance(deuxMasques, balance)
            let exposition = deuxMasques.masques.array?.last?["reglages_locaux"]?["LocalExposure2012"]?.double
            try verifier(exposition.map { abs($0 - 0.0625) < 0.001 } == true,
                         "effet Densité − : LocalExposure2012 \(exposition.map(Self.nombre) ?? "absent") au lieu de 0,0625")
            return "\(deuxMasques.nombreMasques) masques, effet Densité − posé, balance gardée"
        }
        try etape(photo, "masque combiné (arrière-plan sans le sujet)") {
            try ecrire("add_mask", id, ["masks": [["kind": "background", "name": "Recette arrière-plan sans sujet", "adjustments": ["Exposure": -0.05],
                                                   "combine": [["mode": "subtract", "kind": "subject"]]]]])
            let apres = try etat(id)
            try verifier(apres.nombreMasques == m0 + 3, "\(apres.nombreMasques) masques au lieu de \(m0 + 3)")
            let composants = apres.masques.array?.last?["composants"]?.array ?? []
            try verifier(composants.count == 2, "\(composants.count) composant(s) au lieu de 2")
            try verifier(composants.last?.string?.hasSuffix("(soustrait)") == true, "second composant non soustrait : \(composants.last.map(JSONCoding.line) ?? "—")")
            try verifierBalance(apres, balance)
            deuxMasques = apres
            return "\(apres.nombreMasques) masques, dont un combiné ; balance gardée"
        }
        // Pinceau : touches relevées sur un masque fait à la main ; le rayon rapporté au grand côté du
        // fichier est supposé. Un trait dur, horizontal, d'exposition −2 IL laisse une bande sombre :
        // sa hauteur dit l'unité du rayon (41 px sur 1024 si le grand côté, 27 si la hauteur d'un 3:2).
        try etape(photo, "pinceau : trait dur, rayon et position vérifiés sur le rendu") {
            let (_, imagesAvant) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            try ecrire("add_mask", id, ["masks": [["kind": "brush", "name": "Recette pinceau", "adjustments": ["Exposure": -2],
                                                   "strokes": [["points": [[0.3, 0.5], [0.7, 0.5]], "size": 0.02, "feather": 0]]]]])
            let apres = try etat(id)
            let (vue, imagesApres) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let first = imagesApres.first { garder(first, "recette-pinceau.jpg") }
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), deuxMasques)
            try verifier(apres.nombreMasques == deuxMasques.nombreMasques + 1, "\(apres.nombreMasques) masques au lieu de \(deuxMasques.nombreMasques + 1)")
            guard let a = imagesAvant.first, let b = imagesApres.first, let bande = Self.bandeAssombrie(avant: a, apres: b) else {
                throw Echec(description: "aucune bande assombrie trouvée sur le rendu\(vue["a_savoir"]?.string.map { " : " + $0 } ?? "")")
            }
            let attendue = 2 * 0.02 * bande.largeur
            try verifier(abs(bande.hauteur / attendue - 1) < 0.25,
                         "bande de \(Self.nombre(bande.hauteur)) px au lieu de \(Self.nombre(attendue)) (rayon rapporté au grand côté)")
            try verifier(abs(bande.centre - 0.5) < 0.02, "bande centrée à \(Self.nombre(bande.centre)) de la hauteur au lieu de 0,5")
            return "bande de \(Self.nombre(bande.hauteur)) px (attendue \(Self.nombre(attendue))), centrée à \(Self.nombre(bande.centre)) ; annulé"
        }
        // Objet : un masque IA de sous-type 0 et un geste au pinceau (relevé sur un masque Objets
        // fait à la main). Constaté le 17 octobre 2026 : Lightroom le calcule d'après un trait fin écrit
        // par le module, posé sur l'objet ; le cadre est la zone d'intérêt que voit Vision.
        try etape(photo, "objet désigné par un cadre, calculé sans fenêtre") {
            let zone = try appel("view_photo", ["photo_id": photoID, "size": 1024]).0["vision"]?["zone_d_interet"]
            guard let x = zone?["x"]?.double, let y = zone?["y"]?.double, let w = zone?["width"]?.double, let h = zone?["height"]?.double else {
                return "sauté : Vision ne voit pas de zone d'intérêt sur cette photo"
            }
            try ecrire("add_mask", id, ["masks": [["kind": "object", "name": "Recette objet", "adjustments": ["Exposure": 0.05],
                                                   "box": ["x": .number(x), "y": .number(y), "width": .number(w), "height": .number(h)]]]])
            let corrections = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["MaskGroupBasedCorrections"]?.array
            let objet = corrections?.last?["CorrectionMasks"]?.array?.first
            let (vue, images) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let first = images.first { garder(first, "recette-objet.jpg") }
            let relu = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["MaskGroupBasedCorrections"]?.array?
                .last?["CorrectionMasks"]?.array?.first
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), deuxMasques)
            try verifier(relu?["MaskDigest"]?.string != nil, "objet pas calculé par Lightroom : \(relu.map(JSONCoding.line) ?? "absent")")
            try verifier(vue["a_savoir"] == nil, "calculs IA en attente au rendu : \(vue["a_savoir"]?.string ?? "")")
            return "objet \(objet?["MaskDigest"]?.string != nil ? "calculé dès la retouche" : "calculé avant le rendu") ; annulé"
        }
        var auto = deuxMasques
        try etape(photo, "tonalité automatique") {
            try ecrire("apply_settings", id, ["auto_tone": true])
            auto = try etat(id)
            try verifierBalance(auto, balance)
            // Lightroom ne calcule les valeurs automatiques qu'au rendu suivant (−999999 d'ici là) :
            // un aperçu les fixe, avant de comparer les étapes suivantes.
            let enAttente = Self.valeursEnAttente(auto)
            guard enAttente > 0 else { return "balance gardée" }
            _ = try appel("view_photo", ["photo_id": .number(Double(id)), "size": 512])
            auto = try etat(id)
            // Constaté en 2.5 : Lightroom ne les calcule qu'en affichant la photo dans le module
            // Développement (un aperçu exporté ne suffit pas) ; la recette l'y montre au besoin.
            for _ in 0..<5 where Self.valeursEnAttente(auto) > 0 {
                Thread.sleep(forTimeInterval: 1)
                auto = try etat(id)
            }
            var montree = false
            if Self.valeursEnAttente(auto) > 0 {
                _ = try appel("show_photo", ["photo_ids": [.number(Double(id))], "module": "develop"])
                montree = true
                for _ in 0..<15 where Self.valeursEnAttente(auto) > 0 {
                    Thread.sleep(forTimeInterval: 1)
                    auto = try etat(id)
                }
            }
            try verifier(Self.valeursEnAttente(auto) == 0, "valeurs automatiques toujours pas calculées, photo affichée dans le module Développement")
            return "balance gardée ; \(enAttente) valeur(s) automatique(s) calculée(s)" + (montree ? " à l'affichage dans le module Développement" : " au rendu")
        }
        try etape(photo, "proposition visuelle (réglages)") {
            _ = try appel("preview_settings", ["photo_id": .number(Double(id)), "step_name": "recette : essai", "settings": ["Exposure2012": 1]])
            try verifierEgal(try etat(id), auto)
            return "rien n'est gardé"
        }
        try etape(photo, "proposition visuelle (masque)") {
            _ = try appel("add_mask", ["photo_ids": [.number(Double(id))], "step_name": "recette : essai", "preview": true,
                                       "masks": [["kind": "background", "adjustments": ["Exposure": -0.2]]]])
            try verifierEgal(try etat(id), auto)
            return "rien n'est gardé, \(auto.nombreMasques) masques"
        }
        try etape(photo, "aperçu et analyse") {
            let (info, images) = try appel("view_photo", ["photo_id": .number(Double(id))])
            try verifier(!images.isEmpty, "aucune image")
            try verifier(info["mesures"]?["nettete"] != nil, "pas de mesure de netteté")
            try verifier(info["vision"] != nil, "pas d'analyse Vision")
            if let first = images.first { garder(first, "recette-raw.jpg") }
            var detail = "netteté \(info["mesures"]?["nettete"]?["lecture"]?.string ?? "?"), \(info["vision"]?["visages"]?.array?.count ?? 0) visage(s)"
            if info["a_savoir"] != nil { detail += " ; masques IA pas encore calculés au moment du rendu" }
            return detail
        }
        try etapeBilan(id, photo, attendu: auto)
        // 1.3 (Recette+13.swift) : l'avant/après d'une étape, le carnet de progrès ; chacun revient à
        // l'état de la tonalité automatique.
        try sequenceApprendre(id, photo, attendu: auto)
        try etape(photo, "mesure d'angle") {
            let (info, _) = try appel("measure_angle", ["photo_id": .number(Double(id)), "x1": 0.1, "y1": 0.5, "x2": 0.9, "y2": 0.5])
            try verifier(info["crop_angle"]?.double != nil, "pas d'angle proposé")
            return "\(info["mesure"]?.string ?? "")"
        }
        // Constaté dans Lightroom Classic 15.6 : taches, yeux rouges et masques sont rangés avant la
        // correction d'objectif ; le serveur recale les positions (deux rendus la première fois).
        try etape(photo, "tache près du bord, position recalée") {
            let (info, _) = try appel("retouch_spots", ["photo_id": .number(Double(id)), "spots": [["x": 0.04, "y": 0.5, "radius": 0.01]],
                                                         "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let resultat = info["resultats"]?.array?.first
            let remarques = ((resultat?["remarques"]?.array ?? []) + (info["remarques_serveur"]?.array ?? [])).compactMap(\.string)
            try verifier(!(resultat?["changements"]?.array ?? []).isEmpty, "aucune tache posée")
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), auto)
            if let probleme = remarques.first(where: { $0.contains("sans recalage") || $0.hasPrefix("Recalage") }) {
                throw Echec(description: probleme)
            }
            return remarques.first { $0.hasPrefix("Positions recalées") } ?? "pas de correction géométrique sur cette copie"
        }
        // Constaté dans Lightroom Classic 15.6 : le cadre se pose sur l'image transformée, et Upright
        // complet laissait des coins vides, blancs dans l'aperçu (7,8 % de blanc pur sans recadrage).
        // Le module coche « Contraindre le recadrage » : Lightroom resserre le cadre, dans la même
        // étape, et l'annulation remet le cadre d'avant. Upright seul dépend de l'image : le 16 octobre
        // au soir, sur la même copie repassée en Adobe Color, il étirait l'image sans laisser de
        // coin vide. La perspective verticale forte en laisse toujours.
        try etape(photo, "Upright complet et perspective, cadre sans coins vides") {
            let (avant, _) = try appel("view_photo", ["photo_id": .number(Double(id)), "size": 1024])
            let blancAvant = avant["mesures"]?["ecretage_pct"]?["blanc_pur"]?.double ?? 0
            let (reponse, _) = try appel("apply_settings", ["photo_ids": [.number(Double(id))],
                                                            "settings": ["PerspectiveUpright": 2, "PerspectiveVertical": 40],
                                                            "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let resultat = reponse["resultats"]?.array?.first
            let remarques = ((resultat?["remarques"]?.array ?? []) + (reponse["remarques_serveur"]?.array ?? [])).compactMap(\.string)
            let cles = Set((resultat?["changements"]?.array ?? []).compactMap { $0["cle"]?.string })
            let (apres, images) = try appel("view_photo", ["photo_id": .number(Double(id)), "size": 1024])
            if let first = images.first { garder(first, "recette-upright.jpg") }
            let blanc = apres["mesures"]?["ecretage_pct"]?["blanc_pur"]?.double ?? 0
            // Un cadre demandé ensuite se calcule sur la grille de recalage, au centre demandé : en 3:2,
            // il demande toute la largeur, que les coins vides de la perspective entament.
            let (cadre, _) = try appel("apply_settings", ["photo_ids": [.number(Double(id))], "crop": ["aspect": "3:2", "center_x": 0.5],
                                                          "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let remarquesCadre = ((cadre["resultats"]?.array?.first?["remarques"]?.array ?? []) + (cadre["remarques_serveur"]?.array ?? []))
                .compactMap(\.string)
            let (recadree, imagesCadre) = try appel("view_photo", ["photo_id": .number(Double(id)), "size": 1024])
            if let first = imagesCadre.first { garder(first, "recette-upright-3-2.jpg") }
            let blancCadre = recadree["mesures"]?["ecretage_pct"]?["blanc_pur"]?.double ?? 0
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), auto)
            try verifier(cles.contains("PerspectiveUpright"), "Upright non posé")
            try verifier(cles.contains(DevelopCatalogue.constrainCropKey), "« Contraindre le recadrage » non cochée")
            try verifier(blanc <= blancAvant + 0.1,
                         "blanc pur \(Self.nombre(blancAvant)) % avant, \(Self.nombre(blanc)) % après Upright : coins vides\(cles.contains("CropLeft") ? "" : " (cadre non resserré)")")
            if let probleme = remarquesCadre.first(where: { $0.contains("sans recalage") || $0.hasPrefix("Recalage") }) {
                throw Echec(description: "cadre 3:2 : \(probleme)")
            }
            try verifier(remarquesCadre.contains { $0.hasPrefix("Cadre resserré sur l'image redressée") },
                         "cadre 3:2 calculé sans la grille : \(remarquesCadre.joined(separator: " ; "))")
            try verifier(blancCadre <= blancAvant + 0.1, "blanc pur \(Self.nombre(blancCadre)) % avec le cadre 3:2 : coins vides")
            let resserre = remarques.first { $0.hasPrefix("Cadre resserré par Lightroom") }
            return "blanc pur \(Self.nombre(blancAvant)) → \(Self.nombre(blanc)) % ; \(resserre ?? "cadre inchangé, sans coin vide") ; "
                + "3:2 au centre sans coin vide (\(Self.nombre(blancCadre)) %) ; annulés"
        }
        // Relevé dans Lightroom Classic 15.6 : les limites des zones de la courbe et « Affiner la
        // saturation » sont des réglages ordinaires ; reste à voir qu'applyDevelopSettings les prend.
        try etape(photo, "courbe : limites des zones et saturation") {
            try ecrire("apply_settings", id, ["settings": ["ParametricShadowSplit": 30, "ParametricHighlightSplit": 70, "CurveRefineSaturation": 70]])
            let courbe = try etat(id).reglages["Courbe des tonalités"]
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), auto)
            try verifier(courbe?["ParametricShadowSplit"]?.double == 30 && courbe?["ParametricHighlightSplit"]?.double == 70
                         && courbe?["CurveRefineSaturation"]?.double == 70, "relus : \(courbe.map(JSONCoding.line) ?? "rien")")
            return "30, 70 et 70 relus, puis annulés"
        }
        // Forme du bokeh : champs de LensBlur relevés dans Camera Raw (Lightroom Classic 15.6) et dans
        // les paramètres prédéfinis d'Adobe ; la carte de profondeur, calculée sans fenêtre.
        try etape(photo, "flou d'objectif, bokeh en anneau") {
            try ecrire("apply_settings", id, ["lens_blur": ["amount": 30, "bokeh": "ring"]])
            let tous = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]
            let flou = tous?["LensBlur"]
            let (vue, images) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let first = images.first { garder(first, "recette-bokeh-anneau.jpg") }
            let profondeur = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["DepthMapInfo"]
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), auto)
            try verifier(flou?["BokehShape"]?.double == 1 && flou?["BokehShapeDetail"]?.double == 3 && flou?["SphericalAberration"]?.double == 25,
                         "LensBlur relu : \(flou.map(JSONCoding.line) ?? "absent")")
            try verifier(profondeur != nil && vue["a_savoir"] == nil, "carte de profondeur pas calculée : \(vue["a_savoir"]?.string ?? "")")
            return "anneau posé, profondeur \(tous?["DepthMapInfo"] != nil ? "calculée dès la retouche" : "calculée avant le rendu"), sans fenêtre ; annulé"
        }
        // Constaté le 21 octobre 2026 : après un débruitage et son annulation (deux passages au module
        // Développement), la photo active d'avant ne revenait pas (Amelioration.remettreVue) ; elle
        // doit être la même avant et après.
        try etape(photo, "débruitage, puis son annulation") {
            let activeAvant = try photoActive()
            let (info, _) = try appel("enhance_photo", ["photo_id": .number(Double(id)), "denoise": 30, "step_name": "recette",
                                                         "confirm": true, "reason": "Recette automatisée du module."])
            let resultat = info["resultats"]?.array?.first
            let remarques = (resultat?["remarques"]?.array ?? []).compactMap(\.string).joined(separator: " ; ")
            try verifier(resultat?["amelioration"]?["denoise"]?.bool == true, "débruitage absent après le calcul\(remarques.isEmpty ? "" : " : " + remarques)")
            // Sans étape écrite (photo déjà débruitée), undo_last défairait la tonalité automatique.
            try verifier(!(resultat?["changements"]?.array ?? []).isEmpty, "aucune étape de débruitage à annuler\(remarques.isEmpty ? "" : " : " + remarques)")
            let (annulation, _) = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            let annulee = annulation["resultats"]?.array?.first
            try verifier(annulee?["annulee"]?.bool == true, "débruitage non annulé : \(annulee?["raison"]?.string ?? "?")")
            try verifierEgal(try etat(id), auto)
            let ecart = Self.ecartPhotoActive(avant: activeAvant, apres: try photoActive())
            try verifier(ecart == nil, ecart ?? "")
            let active = activeAvant == nil ? "" : " ; photo active d'avant revenue"
            return (remarques.isEmpty ? "calculé, puis retiré" : "calculé, puis retiré (\(remarques))") + active
        }
        // Constaté dans Lightroom Classic 15.6 : la super résolution coche aussi les détails bruts,
        // et Lightroom refuse d'y toucher tant qu'elle est active (l'annulation de la 1.5 échouait).
        try etape(photo, "super résolution, puis son annulation") {
            let (info, _) = try appel("enhance_photo", ["photo_id": .number(Double(id)), "super_resolution": true, "step_name": "recette",
                                                         "confirm": true, "reason": "Recette automatisée du module."])
            let resultat = info["resultats"]?.array?.first
            let remarques = (resultat?["remarques"]?.array ?? []).compactMap(\.string).joined(separator: " ; ")
            // Une copie qui porte déjà la Réduction du bruit de son original : Lightroom n'offre
            // pas la super résolution avec elle (constaté), et rien n'est posé.
            if resultat?["amelioration"]?["superRes"]?.bool != true, remarques.contains("Réduction du bruit") {
                try verifierEgal(try etat(id), auto)
                return "sautée : la photo porte déjà la Réduction du bruit (\(remarques))"
            }
            try verifier(resultat?["amelioration"]?["superRes"]?.bool == true, "super résolution absente après le calcul\(remarques.isEmpty ? "" : " : " + remarques)")
            try verifier(!(resultat?["changements"]?.array ?? []).isEmpty, "aucune étape de super résolution à annuler\(remarques.isEmpty ? "" : " : " + remarques)")
            let (annulation, _) = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            let annulee = annulation["resultats"]?.array?.first
            try verifier(annulee?["annulee"]?.bool == true, "super résolution non annulée : \(annulee?["raison"]?.string ?? "?")")
            try verifierEgal(try etat(id), auto)
            let details = resultat?["amelioration"]?["rawDetails"]?.bool == true ? ", avec ses détails bruts" : ""
            return "calculée\(details), puis retirée\(remarques.isEmpty ? "" : " (\(remarques))")"
        }
        // Outil Supprimer sans IA générative : rangé comme Lightroom le range (relevé), le remplissage
        // reste à calculer par Lightroom (« Update Remove », supposé par updateAISettings).
        try etape(photo, "tache Supprimer sans IA générative, calculée par Lightroom") {
            let (info, _) = try appel("retouch_spots", ["photo_id": photoID, "spots": [["x": 0.45, "y": 0.45, "radius": 0.01, "mode": "remove"]],
                                                         "step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."])
            let remarques = (info["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
            let tous = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]
            let tache = (tous?["RemoveAreas"]?.array ?? tous?["RetouchAreas"]?.array)?.last
            let (vue, _) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            let relue = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]
            let calculee = (relue?["RemoveAreas"]?.array ?? relue?["RetouchAreas"]?.array)?.last
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), auto)
            // Constaté le 17 octobre 2026 : une fois calculée, la tache perd fill_method (patchmatch par
            // défaut) ; une tache générative garde son mode de remplissage et le modèle d'Adobe
            // (pm_clio_model_version).
            try verifier(calculee?["SpotType"]?.string == "heal_patchmatch" && (calculee?["fill_method"]?.string ?? "patchmatch") == "patchmatch"
                         && calculee?["pm_clio_model_version"] == nil, "tache relue : \(calculee.map(JSONCoding.line) ?? "absente")")
            try verifier(calculee?["pm_patch"] != nil, "remplissage pas calculé par Lightroom\(remarques.isEmpty ? "" : " : " + remarques.joined(separator: " ; "))")
            try verifier(vue["a_savoir"] == nil, "calculs en attente au rendu : \(vue["a_savoir"]?.string ?? "")")
            return "remplissage \(tache?["pm_patch"] != nil ? "calculé dès la retouche" : "calculé avant le rendu"), sans IA générative ; annulée"
        }
        try etape(photo, "annulation") {
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), deuxMasques)
            return "retour à l'état d'avant la tonalité automatique"
        }
        try sequenceBibliotheque(id, photo)
        // L'aide d'Adobe demande de mettre à jour un profil adaptatif après des taches, une rotation ou
        // un flou d'objectif. Constaté le 17 octobre 2026 (Lightroom Classic 15.6) : updateAISettings le
        // recalcule après une tache et un flou (InputDigest changé) ; une rotation ne le change pas (il
        // est calculé sur la photo entière, avant le recadrage), même reposé de force.
        try etape(photo, "profil adaptatif après une tache, un flou et une rotation") {
            let depart = try etat(id)
            func remarques(_ reponse: JSONValue) -> [String] {
                (reponse["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
            }
            func retouche(_ outil: String, _ arguments: [String: JSONValue]) throws -> [String] {
                var tous = arguments
                tous["step_name"] = "recette"; tous["confirm"] = true; tous["reason"] = "Recette automatisée du module."
                return remarques(try appel(outil, tous).0)
            }
            _ = try retouche("apply_settings", ["photo_ids": [photoID], "profile": "Adaptive Color"])
            let e0 = try calculAdaptatif()?["InputDigest"]
            let rTache = try retouche("retouch_spots", ["photo_id": photoID, "spots": [["x": 0.3, "y": 0.7, "radius": 0.02]]])
            let e1 = try calculAdaptatif()?["InputDigest"]
            let rFlou = try retouche("apply_settings", ["photo_ids": [photoID], "lens_blur": ["amount": 30]])
            let e2 = try calculAdaptatif()?["InputDigest"]
            let rRotation = try retouche("apply_settings", ["photo_ids": [photoID], "crop": ["angle": 2]])
            let e3 = try calculAdaptatif()?["InputDigest"]
            let (vue, _) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            for _ in 0..<4 { _ = try appel("undo_last", ["photo_ids": [photoID]]) }
            try verifierEgal(try etat(id), depart)
            try verifier(e0 != nil && e1 != e0, "pas recalculé après la tache : \(rTache.joined(separator: " ; "))")
            try verifier(e2 != e1, "pas recalculé après le flou : \(rFlou.joined(separator: " ; "))")
            try verifier(e3 == e2 && rRotation.contains { $0.hasPrefix("Profil adaptatif inchangé") },
                         "rotation : \(e3 == e2 ? "même empreinte" : "empreinte changée") ; \(rRotation.joined(separator: " ; "))")
            try verifier(vue["a_savoir"] == nil, "calculs en attente au rendu : \(vue["a_savoir"]?.string ?? "")")
            return "recalculé après la tache et le flou, inchangé par la rotation, sans fenêtre ; annulés"
        }
        try sequenceTri(id, photo)
        try sequenceLivraison(id, photo)
        try sequenceVariantes(id, photo)
        try sequenceHDR(id, photo)
        try sequenceLivraison25(id, photo)
        try sequenceRetoucheMasques(id, photo)
    }

    /// Version 2.1 (pistes 2.3 et 2.4) : profil d'objectif choisi puis remis par défaut à
    /// l'annulation, rotation d'un quart de tour, mélange noir et blanc automatique, masque d'une
    /// personne précise reconnu par Lightroom (cadres de Vision) et recalculé, masque vide retiré,
    /// pinceau d'affinage du flou d'objectif ; chacun annulé.
    func sequenceRetoucheMasques(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        func remarques(_ reponse: JSONValue) -> [String] {
            (reponse["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
        }
        func retouche(_ outil: String, _ arguments: [String: JSONValue]) throws -> JSONValue {
            var tous = arguments
            // edit_mask, retouch_spots et enhance_photo visent une photo (photo_id) ; les autres une liste.
            if ["edit_mask", "retouch_spots", "enhance_photo", "remove_distractions"].contains(outil) { tous["photo_id"] = photoID } else { tous["photo_ids"] = [photoID] }
            tous["step_name"] = "recette"; tous["confirm"] = true; tous["reason"] = "Recette automatisée du module."
            return try appel(outil, tous).0
        }
        func annuler(_ fois: Int = 1) throws {
            for _ in 0..<fois { _ = try appel("undo_last", ["photo_ids": [photoID]]) }
        }
        // Constaté le 18 octobre 2026 : applyDevelopSettings laissait LensProfileSetup à « Custom » à
        // l'annulation ; un paramètre prédéfini du module remet le profil par défaut.
        try etape(photo, "profil d'objectif choisi, puis profil par défaut remis à l'annulation") {
            let depart = try etat(id)
            let (liste, _) = try appel("list_profiles", ["photo_id": photoID, "lens": "Fujifilm XF"])
            guard let nom = liste["profils_objectif"]?.array?.first(where: { $0["pour"]?.string == "RAW" })?["nom"]?.string else {
                return "sauté : aucun profil d'objectif Fujifilm XF installé"
            }
            let reponse = try retouche("apply_settings", ["lens_profile": .string(nom)])
            let notes = remarques(reponse)
            try annuler()
            try verifierEgal(try etat(id), depart)
            try verifier(!notes.contains { $0.contains("Profil d'objectif") && $0.contains("pas gardé") }, notes.joined(separator: " ; "))
            return "« \(nom) » posé, relu ; annulé, profil par défaut revenu"
        }
        try etape(photo, "rotation d'un quart de tour, annulée") {
            let depart = try etat(id)
            let reponse = try retouche("apply_settings", ["rotate": "right"])
            let changement = reponse["resultats"]?.array?.first?["changements"]?.array?.first { $0["cle"]?.string == "Rotation" }
            try annuler()
            try verifierEgal(try etat(id), depart)
            try verifier(changement != nil, "rotation absente : \(JSONCoding.line(reponse))")
            return "orientation \(changement?["avant"]?.string ?? "?") → \(changement?["apres"]?.string ?? "?"), puis remise"
        }
        try etape(photo, "mélange noir et blanc automatique, annulé") {
            let depart = try etat(id)
            _ = try retouche("apply_settings", ["settings": ["ConvertToGrayscale": 1], "auto_gray_mix": true])
            func melange() throws -> [Double] {
                let tous = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"] ?? .null
                return ["Red", "Orange", "Yellow", "Green", "Aqua", "Blue", "Purple", "Magenta"].compactMap { tous["GrayMixer" + $0]?.double }
            }
            // Comme la tonalité automatique : −999999 jusqu'à ce que Lightroom le calcule, peu après un
            // rendu (constaté le 18 octobre 2026 : tantôt dès le rendu, tantôt plus tard), ou à
            // l'affichage de la photo dans le module Développement.
            func attendre() throws -> [Double] {
                var lus = try melange()
                for _ in 0..<10 where lus.contains(-999999) {
                    Thread.sleep(forTimeInterval: 1)
                    lus = try melange()
                }
                return lus
            }
            var curseurs = try melange()
            var calcul = "dès la retouche"
            if curseurs.contains(-999999) {
                _ = try appel("view_photo", ["photo_id": photoID, "size": 512])
                curseurs = try attendre()
                calcul = "après un rendu"
            }
            if curseurs.contains(-999999) {
                _ = try appel("show_photo", ["photo_ids": [photoID], "module": "develop"])
                curseurs = try attendre()
                calcul = "à l'affichage en Développement"
            }
            try annuler()
            try verifierEgal(try etat(id), depart)
            try verifier(curseurs.count == 8 && !curseurs.contains(-999999) && curseurs.contains { $0 != 0 }, "curseurs du mélange relus : \(curseurs)")
            return "curseurs calculés par Lightroom \(calcul) (\(curseurs.map(Self.nombre).joined(separator: ", "))) ; annulé"
        }
        // Constaté le 18 octobre 2026 : Lightroom ne reconnaît une personne que si le masque porte les
        // cadres de toutes les personnes (InstanceBounds) ; ceux de Vision suffisent.
        try etape(photo, "masque d'une personne précise, reconnu puis recalculé") {
            let depart = try etat(id)
            let ajout = try retouche("add_mask", ["masks": [["kind": "person", "person": 1, "adjustments": ["Exposure": 0.2], "name": "Personne recette"]]])
            let notesAjout = remarques(ajout)
            // Photo de groupe : Lightroom exige les cadres de toutes les personnes, et Vision en
            // manque parfois (constaté : 2 sur 4) ; le masque est alors retiré et l'utilisateur
            // prévenu. Un portrait seul reste vérifié.
            if let note = notesAjout.first(where: { $0.contains("n'a pas reconnu la personne") }),
               let n = note.range(of: #"sur (\d+) trouvées"#, options: .regularExpression).flatMap({ Int(note[$0].filter(\.isNumber)) }), n >= 2 {
                try annuler()
                try verifierEgal(try etat(id), depart)
                return "sautée, photo de groupe : \(note) ; annulé"
            }
            let liste = try appel("edit_mask", ["photo_id": photoID, "action": "list"]).0
            let composant = liste["masques"]?.array?.last?["composants"]?.array?.first
            let recalcul = try retouche("edit_mask", ["action": "recompute", "mask": "Personne recette"])
            let notesRecalcul = remarques(recalcul)
            let relu = try appel("edit_mask", ["photo_id": photoID, "action": "list"]).0["masques"]?.array?.last?["composants"]?.array?.first
            try annuler(2)
            try verifierEgal(try etat(id), depart)
            try verifier(!notesAjout.contains { $0.contains("retiré") }, notesAjout.joined(separator: " ; "))
            try verifier(composant?["personne"]?.int == 1 && composant?["calcule"]?.bool == true, "masque relu : \(composant.map(JSONCoding.line) ?? "absent")")
            try verifier(relu?["personne"]?.int == 1 && !notesRecalcul.contains { $0.contains("plus reconnu") },
                         "après le recalcul : \(relu.map(JSONCoding.line) ?? "absent") \(notesRecalcul.joined(separator: " ; "))")
            return "personne 1 reconnue, calculée, toujours elle après le recalcul ; annulé"
        }
        try etape(photo, "masque vide retiré après le calcul") {
            let depart = try etat(id)
            let reponse = try retouche("add_mask", ["masks": [["kind": "landscape", "part": "mountains", "adjustments": ["Exposure": -0.2]],
                                                            ["kind": "subject", "adjustments": ["Exposure": 0.1]]]])
            let notes = remarques(reponse)
            try annuler()
            try verifierEgal(try etat(id), depart)
            guard let note = notes.first(where: { $0.contains("masques vides") }) else {
                return "sauté : Lightroom a trouvé des montagnes ici (\(notes.joined(separator: " ; ")))"
            }
            return note
        }
        try etape(photo, "pinceau d'affinage du flou d'objectif, annulé") {
            let depart = try etat(id)
            _ = try retouche("apply_settings", ["lens_blur": ["amount": 40, "refine": [["mode": "blur", "strokes": [["points": [[0.45, 0.4], [0.55, 0.42]], "size": 0.03]]]]]])
            let (lu, _) = try appel("get_settings", ["photo_id": photoID])
            let traits = lu["flou_objectif_affinage"]?.int
            try annuler()
            try verifierEgal(try etat(id), depart)
            try verifier((traits ?? 0) >= 1, "trait d'affinage relu : \(traits.map(String.init) ?? "absent")")
            return "1 trait rangé (DepthBasedCorrections) ; annulé"
        }
    }

    /// Version 2.0 (critère) : une séance livrée en deux formats, nommée selon un modèle de
    /// l'utilisateur, sans écraser de fichier. Dans un dossier temporaire, effacé ensuite.
    func sequenceLivraison(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("recette-livraison-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dossier) }
        try etape(photo, "livraison en deux formats, modèle de noms, sans écrasement") {
            let modele = tools.filenameTemplates.all().first { $0.name == "Nom personnalisé - Séquence" }
            // Livraisons types : les services Disque dur de l'utilisateur (2.5), sinon les profils par défaut.
            let profils = try appel("export_photos", ["list": true]).0["profils"]?.array ?? []
            let profilWeb = profils.first { $0["reglages"]?.string?.contains("mégapixels") == true }?["nom"]?.string ?? "web_5mp"
            let profilPlein = profils.first { $0["reglages"]?.string?.contains("pleine résolution") == true }?["nom"]?.string ?? "pleine_qualite"
            var web: [String: JSONValue] = ["photo_ids": [photoID], "folder": .string(dossier.path), "subfolder": "web", "profile": .string(profilWeb), "confirm": true]
            if let modele { web["filename_template"] = .string(modele.name); web["custom_text"] = "Recette" }
            let (premiere, _) = try appel("export_photos", web)
            guard let fichier = premiere["fichiers"]?.array?.first?["fichier"]?.string else { throw Echec(description: "aucun fichier : \(JSONCoding.line(premiere))") }
            let avant = try Data(contentsOf: URL(fileURLWithPath: fichier))
            let (seconde, _) = try appel("export_photos", web)
            let autre = seconde["fichiers"]?.array?.first?["fichier"]?.string ?? ""
            let (pleine, _) = try appel("export_photos", ["photo_ids": [photoID], "folder": .string(dossier.path), "subfolder": "pleine",
                                                          "profile": .string(profilPlein), "confirm": true])
            let grand = pleine["fichiers"]?.array?.first?["fichier"]?.string ?? ""
            // Une livraison est une vraie exportation : une photo jamais exportée le devient
            // (Photos.exportee), le reste ne change pas.
            var livree = depart
            if var classement = depart.classement.object {
                classement["exportee"] = true
                livree.classement = .object(classement)
            }
            try verifierEgal(try etat(id), livree)
            try verifier(autre != fichier && FileManager.default.fileExists(atPath: autre), "seconde livraison : \(autre)")
            try verifier((try? Data(contentsOf: URL(fileURLWithPath: fichier))) == avant, "le premier fichier a changé")
            let (l1, h1) = ToolHandler.dimensions(fichier) ?? (0, 0), (l2, h2) = ToolHandler.dimensions(grand) ?? (0, 0)
            try verifier(abs(Double(l1 * h1) / 1_000_000 - 5) < 0.3 || l1 * h1 < 5_000_000, "web : \(l1) × \(h1)")
            try verifier(l2 * h2 > l1 * h1, "pleine qualité pas plus grande : \(l2) × \(h2)")
            return "\((fichier as NSString).lastPathComponent) (\(l1) × \(h1)), puis \((autre as NSString).lastPathComponent) sans écraser ; pleine qualité \(l2) × \(h2)\(modele == nil ? " ; modèle de noms absent de ce Mac" : "")"
        }
    }

    /// Version 2.0 (critère) : trois variantes d'une photo comparées puis l'une retenue, sans copie
    /// virtuelle ; annulée, puis les instantanés effacés.
    func sequenceVariantes(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        try etape(photo, "trois variantes en instantanés, l'une retenue, annulée") {
            guard let t0 = depart.temperature else { throw Echec(description: "pas de balance des blancs lisible") }
            let (_, planche) = try appel("compare_variants", ["photo_id": photoID, "variants": [
                ["name": "recette naturelle", "settings": ["Exposure2012": 0.1]],
                ["name": "recette chaude", "settings": ["Temperature": .number(t0 + 800), "Vibrance": 10]],
                ["name": "recette noir et blanc", "settings": ["ConvertToGrayscale": 1]],
            ]])
            try verifierEgal(try etat(id), depart)
            let liste = try appel("choose_variant", ["photo_id": photoID, "action": "list"]).0["variantes"]?.array ?? []
            let (choix, _) = try appel("choose_variant", ["photo_id": photoID, "name": "recette chaude", "delete_others": true,
                                                          "step_name": "recette", "reason": "Recette automatisée du module.", "confirm": true])
            let posee = try etat(id)
            let reste = try appel("choose_variant", ["photo_id": photoID, "action": "list"]).0["variantes"]?.array ?? []
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            let effaces = try appel("choose_variant", ["photo_id": photoID, "action": "delete"]).0["effaces"]?.array ?? []
            try verifierEgal(try etat(id), depart)
            try verifier(planche.count == 1, "pas de planche")
            try verifier(liste.count >= 3, "\(liste.count) variantes rangées")
            try verifierProche(posee.temperature, t0 + 800, "température de la variante posée")
            try verifier(reste.count == 1, "autres variantes pas effacées : \(reste.count)")
            try verifier(effaces.count == 1, "variante retenue pas effacée à la fin")
            return "\(liste.count) instantanés, « chaude » posée (\(Self.nombre(t0)) → \(Self.nombre(posee.temperature ?? 0)) K, \((choix["changements"]?.array?.count ?? 0)) réglages), les autres effacés ; annulée"
        }
    }

    /// Version 2.0 (piste 2.1) : mode HDR posé et annulé ; l'aperçu (JPEG, SDR) suit les curseurs de l'aperçu SDR.
    func sequenceHDR(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        try etape(photo, "mode HDR, aperçu SDR réglé, annulé") {
            try ecrire("apply_settings", id, ["settings": ["HDREditMode": 1, "SDRBrightness": 30]])
            let (hdr, _) = try appel("get_settings", ["photo_id": photoID])
            let (comparaison, _) = try appel("preview_settings", ["photo_id": photoID, "settings": ["SDRBrightness": -50], "compare": true, "size": 512])
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            try verifier(hdr["reglages"]?["HDR"]?["HDREditMode"]?.int == 1, "mode HDR relu : \(hdr["reglages"]?["HDR"].map(JSONCoding.line) ?? "absent")")
            let m1 = comparaison["mesures_actuelles"]?["luminosite_L"]?["mediane"]?.double ?? 0
            let m2 = comparaison["mesures_proposition"]?["luminosite_L"]?["mediane"]?.double ?? 0
            try verifier(m1 - m2 > 3, "l'aperçu ne suit pas la luminosité SDR : médiane \(Self.nombre(m1)) → \(Self.nombre(m2))")
            return "HDREditMode relu ; médiane L de l'aperçu \(Self.nombre(m1)) → \(Self.nombre(m2)) avec la luminosité SDR ; annulé"
        }
    }

    /// Livraison d'essai en AVIF HDR et en JPEG filigrané, relues dans le dossier temporaire ; poids
    /// maximal, noms exacts, aperçu dynamique, réimportation empilée. Chacune défaite.
    func sequenceLivraison25(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent("recette-livraison25-\(UUID().uuidString)")
        // Le module ne crée que le dernier niveau du dossier de livraison (son parent doit exister).
        try FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dossier) }
        var derniere: JSONValue = .null
        func livrer(_ sous: String, _ arguments: [String: JSONValue]) throws -> (String, [String: JSONValue]) {
            var tous = arguments
            tous["photo_ids"] = [photoID]
            tous["folder"] = .string(dossier.appendingPathComponent(sous).path)
            tous["confirm"] = true
            let (reponse, _) = try appel("export_photos", tous)
            derniere = reponse
            guard let fichier = reponse["fichiers"]?.array?.first?["fichier"]?.string else { throw Echec(description: "aucun fichier : \(JSONCoding.line(reponse))") }
            return (fichier, ToolHandler.lectureFichier(fichier) ?? [:])
        }
        try etape(photo, "AVIF et JPEG HDR relus (carte de gain), photo en mode HDR ; annulé") {
            try ecrire("apply_settings", id, ["settings": ["HDREditMode": 1]])
            let (avif, lu) = try livrer("hdr", ["format": "avif", "hdr": true, "long_edge": 1200])
            let (avifSeul, luSeul) = try livrer("hdr-seul", ["format": "avif", "hdr": true, "maximize_compatibility": false, "long_edge": 1200])
            let (_, luJpeg) = try livrer("hdr-jpeg", ["hdr": true, "long_edge": 1200])
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            try verifier(lu["profondeur"]?.int == 10 && lu["hdr"]?.string?.contains("carte de gain") == true, "AVIF HDR relu : \(JSONCoding.line(.object(lu)))")
            try verifier(luSeul["hdr"]?.string?.contains("PQ") == true, "AVIF HDR seul relu : \(JSONCoding.line(.object(luSeul)))")
            try verifier(luJpeg["hdr"]?.string?.contains("carte de gain") == true, "JPEG HDR relu : \(JSONCoding.line(.object(luJpeg)))")
            return "\((avif as NSString).lastPathComponent) : \(lu["dimensions"]?.string ?? "?"), 10 bits, \(lu["hdr"]?.string ?? "?") ; "
                + "\((avifSeul as NSString).lastPathComponent) sans carte : \(luSeul["hdr"]?.string ?? "?") ; JPEG : \(luJpeg["hdr"]?.string ?? "?") ; annulé"
        }
        try etape(photo, "JPEG filigrané relu, poids maximal tenu") {
            // Le filigrane d'essai « Claude essai filigrane » s'il est installé ; sinon celui des
            // droits d'auteur, posés le temps de l'essai (sans droits, il ne dessine rien : constaté).
            let essai = tools.filigranes.all().first { $0.nom == "Claude essai filigrane" }
            if essai == nil { try ecrire("set_metadata", id, ["copyright": "© Recette MCP-Développeur"]) }
            let (sans, _) = try livrer("sans", ["long_edge": 800])
            let (avec, _) = try livrer("filigrane", ["long_edge": 800, "watermark": .string(essai?.nom ?? "copyright")])
            // Limite : 60 % du poids sans limite. Constaté : une limite hors d'atteinte à cette taille
            // donne le plus petit fichier possible, que le serveur signale (au_dessus_du_poids).
            let poidsSans = (try? FileManager.default.attributesOfItem(atPath: sans))?[.size] as? Int ?? 0
            let limite = max(Int(Double(poidsSans) * 0.6 / 1024), 10)
            let (leger, luLeger) = try livrer("poids", ["long_edge": 800, "max_size_kb": .number(Double(limite))])
            let signale = derniere["au_dessus_du_poids"]?.string
            if essai == nil { _ = try appel("undo_last", ["photo_ids": [photoID]]) }
            let part = Self.partChangee(try Data(contentsOf: URL(fileURLWithPath: sans)), try Data(contentsOf: URL(fileURLWithPath: avec)))
            let octets = (try? FileManager.default.attributesOfItem(atPath: leger))?[.size] as? Int ?? 0
            try verifierEgal(try etat(id), depart)
            // Seuil bas : sur un fond clair, le filigrane des droits change peu de pixels (constaté :
            // 0,21 % à 800 px, bien visible) ; sans filigrane, deux livraisons sont identiques.
            try verifier(part > 0.001, "filigrane invisible : \(Self.nombre(part * 100)) % des pixels changés")
            try verifier(octets > 0 && octets < poidsSans && (octets <= limite * 1024 || signale != nil),
                         "poids : \(octets) octets pour \(limite) Ko (sans limite : \(poidsSans)), rien de signalé")
            return "filigrane « \(essai?.nom ?? "copyright") » : \(Self.nombre(part * 100)) % des pixels changés ; \(limite) Ko demandés : "
                + "\(luLeger["poids_ko"]?.int ?? 0) Ko (sans limite : \(poidsSans / 1024) Ko)" + (signale.map { " ; signalé : \($0)" } ?? "")
        }
        try etape(photo, "noms exacts calculés par Lightroom, puis livrés sous ce nom") {
            guard tools.filenameTemplates.all().contains(where: { $0.name == "Nom personnalisé - Séquence" }) else { return "modèle « Nom personnalisé - Séquence » absent de ce Mac" }
            let (noms, _) = try appel("export_photos", ["list": true, "photo_ids": [photoID], "filename_template": "Nom personnalisé - Séquence",
                                                        "custom_text": "Recette", "start_number": 7])
            let prevu = noms["noms"]?.array?.first?["nom"]?.string ?? "?"
            let (fichier, _) = try livrer("noms", ["long_edge": 400, "filename_template": "Nom personnalisé - Séquence", "custom_text": "Recette", "start_number": 7])
            try verifier((fichier as NSString).lastPathComponent == prevu, "prévu \(prevu), livré \((fichier as NSString).lastPathComponent)")
            return "\(prevu), comme prévu"
        }
        try etape(photo, "aperçu dynamique créé puis retiré") {
            let (cree, _) = try appel("export_photos", ["photo_ids": [photoID], "smart_previews": "build"])
            guard cree["existants"] == nil else { return "aperçu dynamique déjà là au départ : gardé tel quel" }
            let (retire, _) = try appel("export_photos", ["photo_ids": [photoID], "smart_previews": "delete"])
            try verifier(cree["crees"]?.array?.count == 1, "pas créé : \(JSONCoding.line(cree))")
            try verifier(retire["retires"]?.array?.count == 1, "pas retiré : \(JSONCoding.line(retire))")
            return "créé (\(Self.nombre(cree["taille_mo"]?.double ?? 0)) Mo), puis retiré"
        }
        try etape(photo, "TIFF réimporté, empilé avec l'original, puis retiré du catalogue et mis à la Corbeille") {
            let (reponse, _) = try appel("export_photos", ["photo_ids": [photoID], "format": "tiff", "long_edge": 600, "reimport": "stack", "confirm": true])
            guard let fichier = reponse["fichiers"]?.array?.first?["fichier"]?.string, let nouvelle = reponse["reimportees"]?.array?.first?["id"]?.int else {
                throw Echec(description: "rien de réimporté : \(JSONCoding.line(reponse))")
            }
            let dossierOriginal = (fichier as NSString).deletingLastPathComponent
            let (pile, _) = try appel("find_photos", ["folder": .string(dossierOriginal), "text": .string(((fichier as NSString).lastPathComponent as NSString).deletingPathExtension), "limit": 20])
            let empilee = (pile["photos"]?.array ?? []).first { $0["id"]?.int == nouvelle }?["pile"]
            _ = try tools.lightroom.send("retirerReimportees", ["chemins": [.string(fichier)]], timeout: 60)
            try FileManager.default.trashItem(at: URL(fileURLWithPath: fichier), resultingItemURL: nil)
            try verifierEgal(try etat(id), depart)
            try verifier(empilee != nil && empilee != .null, "pas empilée avec l'original")
            return "\((fichier as NSString).lastPathComponent) empilé (\(empilee?["photos"]?.int ?? 0) photos dans la pile), puis retiré et mis à la Corbeille"
        }
    }

    /// Version 2.0 : harmonisation chiffrée, en plan (rien n'est écrit), du JPEG sur le RAW.
    func sequenceSerie(reference: Int, autre: Int) throws {
        try etape("série \(reference) → \(autre)", "harmonisation chiffrée (plan)") {
            let avant = try etat(autre)
            let (plan, _) = try appel("match_series", ["reference_id": .number(Double(reference)), "photo_ids": [.number(Double(autre))]])
            try verifierEgal(try etat(autre), avant)
            let ligne = plan["photos"]?.array?.first
            try verifier(ligne?["ecart_avant"]?["exposition_IL"]?.double != nil, "écarts absents : \(JSONCoding.line(plan))")
            let correction = ligne?["correction_proposee"].map(JSONCoding.line) ?? "aucune"
            return "écart d'exposition \(Self.nombre(ligne?["ecart_avant"]?["exposition_IL"]?.double ?? 0)) IL ; correction proposée : \(correction) ; rien d'écrit"
        }
    }

    /// Version 2.1 (piste 2.3) : expositions reproduites d'après la prise de vue, en plan.
    func sequenceExpositions(reference: Int, autre: Int) throws {
        try etape("série \(reference) → \(autre)", "expositions d'après la prise de vue (plan)") {
            let avant = try etat(autre)
            let (plan, _) = try appel("match_series", ["reference_id": .number(Double(reference)), "photo_ids": [.number(Double(autre))], "by": "exif"])
            try verifierEgal(try etat(autre), avant)
            let ligne = plan["photos"]?.array?.first
            try verifier(ligne?["ecart_IL"]?.double != nil, "écart absent : \(JSONCoding.line(plan))")
            return "\(ligne?["prise_de_vue"]?.string ?? "?") : écart \(Self.nombre(ligne?["ecart_IL"]?.double ?? 0)) IL ; rien d'écrit"
        }
    }

    /// Version 1.9 : tri d'une séance sur les vignettes du cache, planche contact, suppression des
    /// reflets, objet désigné par un rectangle, plage de couleurs, couleur ponctuelle d'un masque ;
    /// 1.1 : la note proposée ; 1.2 : éclaircir et assombrir (sequenceTireur).
    func sequenceTri(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        let recette: [String: JSONValue] = ["step_name": "recette", "confirm": true, "reason": "Recette automatisée du module."]
        func avec(_ arguments: [String: JSONValue]) -> [String: JSONValue] { arguments.merging(recette) { $1 } }
        func remarques(_ reponse: JSONValue) -> [String] {
            (reponse["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
        }
        // Critère de la 1.9 : une séance triée sans blocage, sur les vignettes du cache de Lightroom.
        try etape(photo, "tri d'une séance sur les vignettes du cache") {
            let (bilan, _) = try appel("cull_photos", ["photo_ids": [photoID], "details": true, "keywords": true])
            let vignettes = bilan["vignettes"]
            try verifier(bilan["photos_analysees"]?.int == 1, "photos analysées : \(bilan["photos_analysees"].map(JSONCoding.line) ?? "?")")
            try verifier(vignettes?["cache_de_lightroom"]?.int == 1, "vignette pas tirée du cache : \(vignettes.map(JSONCoding.line) ?? "?")")
            let ligne = bilan["photos"]?.array?.first
            try verifier(ligne?["nettete_max"]?.double != nil, "pas de netteté mesurée")
            try verifierEgal(try etat(id), depart)
            let mots = (ligne?["mots_cles"]?.array ?? []).compactMap(\.string).prefix(3).joined(separator: ", ")
            return "\(ligne?["mesures"]?.string ?? "?")\(mots.isEmpty ? "" : " ; mots-clés : " + mots) ; en \(vignettes?["duree"]?.string ?? "?")"
        }
        try etape(photo, "planche contact") {
            let (legende, images) = try appel("contact_sheet", ["photo_ids": [photoID]])
            try verifier(images.count == 1 && PreviewImages.image(images[0]) != nil, "pas d'image")
            try verifier(legende["photos"]?.array?.first?["vignette"] == nil, "vignette absente")
            return "une image, \(legende["photos"]?.array?.count ?? 0) vignette numérotée"
        }
        // 1.1 : une note proposée se range dans le registre du module, hors du catalogue ; une note
        // hors de l'échelle (6 étoiles ; Claude propose de 0 à 5 depuis le correctif 1.3.2) est
        // refusée avant d'atteindre Lightroom. À vérifier (to_check) : le plafond du tri ne gêne
        // pas, et le module la range dans l'état « a_verifier ». 1.1.1 : avec apply (« note ces
        // photos »), la note est posée, une étape que undo_last défait.
        // Le registre des notes (notation.json) est remis comme la recette l'a trouvé : il ne voit
        // pas undo_last, et la note posée puis défaite y restait « acceptee » (constaté le 21 octobre
        // 2026), comme si Dany l'avait acceptée.
        try etape(photo, "note proposée (propose_ratings), photo inchangée ; puis posée sur demande et annulée") {
            let detail = try garderRegistreDesNotes(id) { () throws -> String in
                let criteres: JSONValue = ["impact": "Recette.", "qualities": "Recette.", "technical_floor": "Recette."]
                let six = tools.call(name: "propose_ratings", arguments: ["ratings": [["photo_id": photoID, "rating": 6, "criteria": criteres,
                                                                                       "reason": "Recette automatisée du module."]]])
                try verifier(six.isError && six.text.contains("« rating » va de 0 à 5"), "6 étoiles acceptées : \(six.text)")
                let (reponse, _) = try appel("propose_ratings", ["ratings": [["photo_id": photoID, "rating": 2, "to_check": true, "criteria": criteres,
                                                                               "reason": "Recette automatisée du module."]]])
                let proposee = reponse["propositions"]?.array?.first
                try verifier(proposee?["photo"]?.int == id && proposee?["etat"]?.string == "a_verifier", "proposition non rangée : \(JSONCoding.line(reponse))")
                try verifierEgal(try etat(id), depart)
                let (pose, _) = try appel("propose_ratings", ["apply": true, "ratings": [["photo_id": photoID, "rating": 2, "to_check": true, "criteria": criteres,
                                                                                        "reason": "Recette automatisée du module."]]])
                let posee = pose["posees"]?.array?.first
                let note = try etat(id).classement["note"]?.int
                _ = try appel("undo_last", ["photo_ids": [photoID]])
                try verifierEgal(try etat(id), depart)
                try verifier(posee?["etat"]?.string == "acceptee" && note == 2, "note pas posée : \(JSONCoding.line(pose))")
                return "rangée pour \(proposee?["fichier"]?.string ?? "?"), à vérifier, rien de changé ; avec apply, 2 ★ posées, puis annulées"
            }
            return detail + " ; registre des notes remis comme la recette l'a trouvé"
        }
        // Constaté le 17 octobre 2026 : filtre « Reflections » (FilterID 3), intensité dans BlendParams ;
        // changeReflectionRemovalAmount ne change pas le filtre rangé.
        try etape(photo, "suppression des reflets, intensité changée, annulée") {
            let (pose, _) = try appel("remove_distractions", avec(["photo_id": photoID, "reflections": ["amount": 60]]))
            let premier = pose["resultats"]?.array?.first?["reflets"]
            let (change, _) = try appel("remove_distractions", avec(["photo_id": photoID, "reflections": ["amount": 90]]))
            let second = change["resultats"]?.array?.first?["reflets"]
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            let reste = try appel("get_settings", ["photo_id": photoID]).0["filtres_calcules"]?.array ?? []
            try verifier(premier?["intensite"]?.int == 60, "intensité relue : \(premier.map(JSONCoding.line) ?? "?") ; \(remarques(pose).joined(separator: " ; "))")
            try verifier(second?["intensite"]?.int == 90, "intensité changée : \(second.map(JSONCoding.line) ?? "?") ; \(remarques(change).joined(separator: " ; "))")
            try verifier(!reste.contains { $0.string?.contains("Reflection") == true }, "filtre resté après l'annulation")
            return "60 puis 90, relues ; les deux étapes annulées"
        }
        // Constaté le 17 octobre 2026 : le rectangle (Mask/Polygon, points {X, Y}) est calculé par Lightroom.
        try etape(photo, "objet désigné par un rectangle") {
            let (reponse, _) = try appel("add_mask", avec(["photo_ids": [photoID], "masks": [[
                "kind": "object", "box": ["x": 0.3, "y": 0.3, "width": 0.4, "height": 0.4], "adjustments": ["Exposure": -0.5]]]]))
            let tous = try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]
            let objet = tous?["MaskGroupBasedCorrections"]?.array?.last?["CorrectionMasks"]?.array?.first
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            try verifier(objet?["Gesture"]?.array?.first?["What"]?.string == "Mask/Polygon", "geste relu : \(objet?["Gesture"].map(JSONCoding.line) ?? "absent")")
            if objet?["MaskDigest"] == nil {
                return "geste rangé ; Lightroom n'y a pas trouvé d'objet (\(remarques(reponse).joined(separator: " ; "))) ; annulé"
            }
            return "objet calculé par Lightroom ; annulé"
        }
        try etape(photo, "plage de couleurs et couleur ponctuelle d'un masque (propositions)") {
            let (actuel, avant) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            _ = actuel
            let (_, couleur) = try appel("add_mask", ["photo_ids": [photoID], "preview": true, "size": 512, "step_name": "recette",
                                                      "masks": [["kind": "color", "samples": [[0.5, 0.5]], "color_range": 60, "adjustments": ["Exposure": -3]]]])
            let (_, ponctuelle) = try appel("add_mask", ["photo_ids": [photoID], "preview": true, "size": 512, "step_name": "recette",
                                                         "masks": [["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 2, "feather": 0,
                                                                    "point_colors": [["hue": 30, "saturation": 30, "luminance": 50, "saturation_shift": -100, "luminance_shift": -60, "range": 100]]]]])
            try verifierEgal(try etat(id), depart)
            guard let image0 = avant.first, let image1 = couleur.first, let image2 = ponctuelle.first else { throw Echec(description: "aperçus manquants") }
            let partCouleur = Self.partChangee(image0, image1), partPonctuelle = Self.partChangee(image0, image2)
            try verifier(partCouleur > 0.005, "la plage de couleurs n'a rien sélectionné")
            // La mesure compte les pixels dont la luminosité change : l'orange visé (30°, en sixièmes de
            // tour depuis la 2.1) est aussi assombri, pas seulement désaturé.
            try verifier(partPonctuelle > 0.005, "la couleur ponctuelle n'a rien changé")
            return "plage de couleurs : \(Self.nombre(partCouleur * 100)) % des pixels assombris ; couleur ponctuelle : \(Self.nombre(partPonctuelle * 100)) % changés"
        }
        try sequenceTireur(id, depart, photo)
    }

    /// 1.2, éclaircir et assombrir (méthode du tireur, Prompts.Tireur) : l'inversion du radial, puis
    /// la forme des bords que Claude pose. Des propositions à 512 px, comparées à une proposition
    /// presque neutre (même chemin de rendu : une vue se rend un peu autrement, et peut porter le
    /// carré du point de mise au point). Rien n'est gardé.
    func sequenceTireur(_ id: Int, _ depart: Etat, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        func proposition(_ masque: [String: JSONValue]) throws -> Data {
            let (_, images) = try appel("add_mask", ["photo_ids": [photoID], "preview": true, "size": 512, "step_name": "recette",
                                                     "masks": [.object(masque)]])
            guard let image = images.first else { throw Echec(description: "aperçu de la proposition manquant") }
            return image
        }
        let neutre: [String: JSONValue] = ["kind": "radial", "center_x": 0.5, "center_y": 0.5, "radius_x": 0.35, "radius_y": 0.35,
                                           "feather": 0, "adjustments": ["Exposure": 0.01]]
        // Constaté le 20 octobre 2026 (propositions à −2 IL, fondu 0, sur un portrait d'essai) : le
        // radial inversé (Flipped avec MaskInverted) assombrit l'extérieur de l'ellipse et laisse le
        // centre ; sans invert, l'inverse ; le linéaire, le côté de from seulement. Le fondu nul isole
        // l'inversion du contour.
        try etape(photo, "éclaircir et assombrir : radial inversé et dégradé linéaire (propositions)") {
            let base = try proposition(neutre)
            var radial = neutre
            radial["adjustments"] = ["Exposure": -2]
            var inverse = radial
            inverse["invert"] = true
            let a = try proposition(inverse), b = try proposition(radial)
            let c = try proposition(["kind": "linear", "from_x": 0.5, "from_y": 0, "to_x": 0.5, "to_y": 0.5, "adjustments": ["Exposure": -2]])
            try verifierEgal(try etat(id), depart)
            let coins = [CGRect(x: 0, y: 0, width: 0.1, height: 0.1), CGRect(x: 0.9, y: 0, width: 0.1, height: 0.1),
                         CGRect(x: 0, y: 0.9, width: 0.1, height: 0.1), CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)]
            let milieu = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
            let haut = CGRect(x: 0.3, y: 0, width: 0.4, height: 0.1), bas = CGRect(x: 0.3, y: 0.9, width: 0.4, height: 0.1)
            guard let la = Luminances(avant: base, apres: a), let lb = Luminances(avant: base, apres: b),
                  let lc = Luminances(avant: base, apres: c) else { throw Echec(description: "aperçus illisibles ou de tailles différentes") }
            func pct(_ part: Double?) -> String { part.map { "\(Self.nombre($0 * 100)) %" } ?? "—" }
            // Un coin trop sombre (12 niveaux au plus) ne se mesure pas : les autres suffisent.
            let coinsA = coins.compactMap(la.part), coinsB = coins.compactMap(lb.part)
            try verifier(coinsA.count >= 2 && coinsB.count >= 2, "coins trop sombres pour mesurer")
            let milieuA = la.part(milieu) ?? 0, milieuB = lb.part(milieu) ?? 0
            let hautC = lc.part(haut) ?? 0, basC = lc.part(bas) ?? 0
            try verifier(coinsA.allSatisfy { $0 > 0.5 } && milieuA < 0.05,
                         "radial inversé : coins \(coinsA.map(pct).joined(separator: ", ")), milieu \(pct(milieuA)) (attendu : coins assombris, milieu intact)")
            try verifier(coinsB.allSatisfy { $0 < 0.05 } && milieuB > 0.5,
                         "radial : coins \(coinsB.map(pct).joined(separator: ", ")), milieu \(pct(milieuB)) (attendu : milieu assombri, coins intacts)")
            try verifier(hautC > 0.5 && basC < 0.05, "linéaire : haut \(pct(hautC)), bas \(pct(basC)) (attendu : le haut seul)")
            return "radial inversé : coins \(coinsA.map(pct).joined(separator: ", ")), milieu \(pct(milieuA)) ; sans invert : milieu \(pct(milieuB)) ; "
                + "linéaire : haut \(pct(hautC)), bas \(pct(basC))"
        }
        // La forme des bords que les invites et add_mask donnent (Prompts.Tireur.forme), relevée le
        // 20 octobre 2026 sur un paysage, radial centré : le centre jamais touché, une baisse qui monte
        // sans marche vers les coins. Vérifiée ici telle que Claude la pose : au milieu de la zone
        // d'intérêt de Vision, aux deux bornes de Prompts.Tireur.bords (−0,3 et −0,5 IL).
        try etape(photo, "éclaircir et assombrir : forme des bords (radial inversé, propositions)") {
            let (vue, _) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            let zone = Self.rectangle(vue["vision"]?["zone_d_interet"])
            let centre = zone.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0.5, y: 0.5)
            let rayon = Double(Prompts.Tireur.bordsRayon.replacingOccurrences(of: ",", with: ".")) ?? 0.7
            let fondu = Double(Prompts.Tireur.bordsFondu) ?? 80
            let base = try proposition(neutre)
            var formes: [(Double, FormeBords)] = []
            for dose in [-0.3, -0.5] {
                let bords = try proposition(["kind": "radial", "center_x": .number(Double(centre.x)), "center_y": .number(Double(centre.y)),
                                             "radius_x": .number(rayon), "radius_y": .number(rayon), "feather": .number(fondu), "invert": true,
                                             "adjustments": ["Exposure": .number(dose)]])
                guard let forme = Self.formeDesBords(avant: base, apres: bords, centre: centre) else {
                    throw Echec(description: "aperçus illisibles ou de tailles différentes")
                }
                formes.append((dose, forme))
            }
            try verifierEgal(try etat(id), depart)
            // En pour cent de luminance perdue (FormeBords).
            let n = { (valeur: Double) in Self.nombre(valeur * 100) }
            var mesures: [String] = []
            for (dose, forme) in formes {
                let mesure = "à \(Self.nombre(dose)) IL : centre \(n(forme.centre)) %, milieu des bords \(n(forme.bords)) %, coins \(n(forme.coins)) % "
                    + "(le plus loin \(n(forme.coinLoin)) %) de luminance en moins ; plus forte marche \(n(forme.marche)) % ; "
                    + "profil vers le coin le plus loin : \(forme.profil.map { n($0) }.joined(separator: " "))"
                try verifier(forme.centre < FormeBords.centreMax, "centre touché : \(mesure)")
                try verifier(forme.coinLoin >= FormeBords.coinMin, "bords à peine assombris : \(mesure)")
                try verifier(!forme.enPlaque, "vignette en plaque (une marche fait l'essentiel de la baisse) : \(mesure)")
                try verifier(!forme.enAnneau, "anneau (la baisse retombe avant le coin) : \(mesure)")
                mesures.append(mesure)
            }
            return "rayon \(Prompts.Tireur.bordsRayon), fondu \(Prompts.Tireur.bordsFondu), centré sur \(zone == nil ? "le milieu (pas de zone d'intérêt)" : "la zone d'intérêt") "
                + "(\(Self.nombre(Double(centre.x))) ; \(Self.nombre(Double(centre.y)))) ; " + mesures.joined(separator: " ; ")
        }
    }

    /// Plage de profondeur, sur une copie virtuelle qui porte une carte de profondeur (photo
    /// Portrait d'un iPhone) : le plus proche assombri, et seulement lui. Des propositions
    /// seulement : rien n'est gardé, la photo n'a pas à revenir à l'origine (elle peut porter le
    /// classement de Claude qui l'a rangée dans la collection de recette).
    func sequenceProfondeur(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        try etape(photo, "plage de profondeur (proposition)") {
            try verifier(depart.copieVirtuelle == true || originaux, "c'est un original : la recette n'y touche qu'avec l'option --original")
            let (_, avant) = try appel("view_photo", ["photo_id": photoID, "size": 512])
            let (_, proche) = try appel("add_mask", ["photo_ids": [photoID], "preview": true, "size": 512, "step_name": "recette",
                                                     "masks": [["kind": "depth", "min": 0, "max": 35, "adjustments": ["Exposure": -3]]]])
            try verifierEgal(try etat(id), depart)
            guard let image0 = avant.first, let image1 = proche.first else { throw Echec(description: "aperçus manquants") }
            let part = Self.partChangee(image0, image1)
            try verifier(part > 0.005 && part < 0.9, "part assombrie : \(Self.nombre(part * 100)) % (rien, ou l'image entière : pas de carte de profondeur ?)")
            return "\(Self.nombre(part * 100)) % des pixels assombris (le plus proche)"
        }
    }

    /// Le plus grand écart de luminance (niveaux sur 255) entre deux rendus de même taille ; nil
    /// s'ils ne se comparent pas. Deux rendus des mêmes réglages sont identiques au pixel près
    /// (relevé le 20 octobre 2026), d'où `ecartIdentique` : 2 niveaux, pour l'arrondi du JPEG.
    static func ecartMax(_ a: Data, _ b: Data) -> Double? {
        guard let l = Luminances(avant: a, apres: b) else { return nil }
        return Double(zip(l.avant, l.apres).map { abs($0 - $1) }.max() ?? 0)
    }

    static let ecartIdentique = 2.0

    /// Part des pixels dont la luminance change de plus de 12 niveaux entre deux aperçus de même taille.
    static func partChangee(_ a: Data, _ b: Data) -> Double {
        guard let ia = PreviewImages.image(a), let ib = PreviewImages.image(b), ia.width == ib.width, ia.height == ib.height,
              let (w, h, la) = Detail.luminance(ia), let (_, _, lb) = Detail.luminance(ib) else { return 0 }
        var changes = 0
        for i in 0..<(w * h) where abs(la[i] - lb[i]) > 12 { changes += 1 }
        return Double(changes) / Double(w * h)
    }

    /// Les luminances (0 à 255) de deux rendus de même taille, pour lire zone par zone ce qu'un
    /// masque a assombri. Une zone se donne en fractions de l'image, depuis le haut gauche.
    struct Luminances {
        let largeur: Int, hauteur: Int
        let avant: [Float], apres: [Float]

        /// nil : un rendu illisible, ou deux tailles différentes.
        init?(avant: Data, apres: Data) {
            guard let ia = PreviewImages.image(avant), let ib = PreviewImages.image(apres), ia.width == ib.width, ia.height == ib.height,
                  let (w, h, la) = Detail.luminance(ia), let (_, _, lb) = Detail.luminance(ib) else { return nil }
            largeur = w
            hauteur = h
            self.avant = la
            self.apres = lb
        }

        /// Chaque pixel de la zone, bornée à l'image : sa luminance avant, puis après.
        func parcourir(_ zone: CGRect, _ corps: (Float, Float) -> Void) {
            let x0 = max(0, min(largeur, Int((Double(zone.minX) * Double(largeur)).rounded(.down))))
            let x1 = max(0, min(largeur, Int((Double(zone.maxX) * Double(largeur)).rounded(.up))))
            let y0 = max(0, min(hauteur, Int((Double(zone.minY) * Double(hauteur)).rounded(.down))))
            let y1 = max(0, min(hauteur, Int((Double(zone.maxY) * Double(hauteur)).rounded(.up))))
            guard x1 > x0, y1 > y0 else { return }
            for y in y0..<y1 {
                for x in x0..<x1 { corps(avant[y * largeur + x], apres[y * largeur + x]) }
            }
        }

        /// Part des pixels assombris (après sous 0,8 fois avant, comme `bandeAssombrie`), sans ceux
        /// d'avant à 12 niveaux ou moins ; nil s'il n'en reste aucun.
        func part(_ zone: CGRect) -> Double? {
            var comptes = 0, assombris = 0
            parcourir(zone) { a, b in
                guard a > 12 else { return }
                comptes += 1
                if b < a * 0.8 { assombris += 1 }
            }
            return comptes == 0 ? nil : Double(assombris) / Double(comptes)
        }

        /// Baisse relative moyenne de luminance : la part perdue (1 − après / avant ; 0,15 = 15 % de
        /// moins), sans les pixels d'avant à 12 niveaux ou moins ; nil s'il n'en reste aucun. En part
        /// et non en niveaux : à exposition égale, une zone sombre perd moins de niveaux qu'une claire
        /// (relevé du 20 octobre 2026 : le creux du profil venait de la scène), et un coin sombre
        /// passerait pour un anneau ou des bords à peine assombris.
        func baisse(_ zone: CGRect) -> Double? {
            var total = 0.0, comptes = 0
            parcourir(zone) { a, b in
                guard a > 12 else { return }
                total += Double((a - b) / a)
                comptes += 1
            }
            return comptes == 0 ? nil : total / Double(comptes)
        }
    }

    /// Part des pixels d'une zone qu'un masque a assombris entre deux rendus de même taille (après
    /// sous 0,8 fois avant ; les pixels d'avant à 12 niveaux ou moins ne comptent pas) ; 0 pour deux
    /// tailles différentes, un rendu illisible ou une zone trop sombre.
    static func partAssombrie(avant: Data, apres: Data, zone: CGRect) -> Double {
        Luminances(avant: avant, apres: apres)?.part(zone) ?? 0
    }

    /// Ce qu'un radial inversé des bords fait à l'image, en baisse relative de luminance
    /// (`Luminances.baisse`, de 0 à 1) : au centre du radial, au milieu des quatre bords, aux quatre
    /// coins et au coin le plus loin du centre ; et le profil de la baisse du centre à ce coin.
    /// Relevé le 20 octobre 2026 en niveaux (rayon 0,7, fondu 80, −0,5 IL, sur un paysage) : centre
    /// 0, milieu des bords −16, coins −21 à −27, une baisse qui monte sans marche. Les seuils sont
    /// provisoires ; passés le 21 octobre 2026 sur un portrait pris à l'intérieur (centre 0,5 %,
    /// plus forte marche 1,6 % à −0,3 IL), loin des bornes.
    struct FormeBords {
        var centre: Double
        var bords: Double
        var coins: Double
        var coinLoin: Double
        /// Les segments mesurables seulement (un segment tout noir n'a pas de baisse lisible).
        var profil: [Double]

        /// La plus forte hausse de la baisse d'un pas du profil au suivant.
        var marche: Double { zip(profil, profil.dropFirst()).map { $1 - $0 }.max() ?? 0 }
        /// Une plaque sombre : une seule marche fait l'essentiel de la baisse au coin.
        var enPlaque: Bool { coinLoin > 0 && marche > Self.marcheMax * coinLoin }
        /// Un anneau : la baisse retombe avant le coin (une scène peut creuser le profil un peu).
        var enAnneau: Bool {
            guard let pic = profil.max(), pic > 0, let fin = profil.last else { return false }
            return fin < Self.finMin * pic
        }
        static let marcheMax = 0.5, finMin = 0.6
        /// Le centre reste intact (moins de 2 % de luminance perdue) ; le coin le plus loin en perd
        /// au moins 5 % (−0,3 IL entier en ôte environ 9 % dans un JPEG sRGB).
        static let centreMax = 0.02, coinMin = 0.05
    }

    /// La forme des bords entre deux rendus de même taille (`centre` : celui du radial, en fractions
    /// de l'image) ; nil s'ils ne se comparent pas. Le profil : `segments` carrés de 4 % du cadre,
    /// du centre au coin le plus loin.
    static func formeDesBords(avant: Data, apres: Data, centre: CGPoint, segments: Int = 20) -> FormeBords? {
        guard let l = Luminances(avant: avant, apres: apres) else { return nil }
        let cote = 0.1
        func carre(_ x: Double, _ y: Double, _ c: Double = cote) -> CGRect {
            CGRect(x: min(max(x - c / 2, 0), 1 - c), y: min(max(y - c / 2, 0), 1 - c), width: c, height: c)
        }
        func moyenne(_ zones: [CGRect]) -> Double {
            let baisses = zones.compactMap(l.baisse)
            return baisses.isEmpty ? 0 : baisses.reduce(0, +) / Double(baisses.count)
        }
        let cx = Double(centre.x), cy = Double(centre.y)
        let coins = [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]
        let loin = coins.max { hypot($0.0 - cx, $0.1 - cy) < hypot($1.0 - cx, $1.1 - cy) } ?? (1, 1)
        let profil = (0..<max(segments, 2)).compactMap { k -> Double? in
            let t = (Double(k) + 0.5) / Double(max(segments, 2))
            return l.baisse(carre(cx + (loin.0 - cx) * t, cy + (loin.1 - cy) * t, 0.04))
        }
        return FormeBords(centre: l.baisse(carre(cx, cy)) ?? 0,
                          bords: moyenne([carre(0.5, 0), carre(0.5, 1), carre(0, 0.5), carre(1, 0.5)]),
                          coins: moyenne(coins.map { carre($0.0, $0.1) }),
                          coinLoin: l.baisse(carre(loin.0, loin.1)) ?? 0,
                          profil: profil)
    }

    /// Un cadre de Vision en JSON ({x, y, width, height}, fractions depuis le haut gauche).
    static func rectangle(_ json: JSONValue?) -> CGRect? {
        guard let x = json?["x"]?.double, let y = json?["y"]?.double, let w = json?["width"]?.double, let h = json?["height"]?.double,
              w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Les écarts d'un bilan de view_photo en une ligne : « exposition 47,8 → 71,2 (+1,95 IL) ; … ».
    static func resumeEcarts(_ ecarts: JSONValue?) -> String {
        if let texte = ecarts?.string { return texte }
        guard let objet = ecarts?.object, !objet.isEmpty else { return "aucun écart visible" }
        return objet.keys.sorted().map { cle in
            let ecart = objet[cle] ?? .null
            var texte = "\(cle) \(ecart["avant"]?.double.map(nombre) ?? "?") → \(ecart["apres"]?.double.map(nombre) ?? "?")"
            if let il = ecart["IL"]?.double { texte += " (\(il > 0 ? "+" : "")\(nombre(il)) IL)" }
            for precision in ["canal", "lecture"] {
                if let valeur = ecart[precision]?.string { texte += " (\(valeur))" }
            }
            return texte
        }.joined(separator: " ; ")
    }

    /// La durée (en millisecondes) de la mesure de l'éclairage sur un aperçu, avec les visages et la
    /// zone d'intérêt que donne Vision (`vision` de view_photo) ; nil sur un aperçu illisible.
    static func dureeEclairage(_ data: Data, vision: JSONValue?) -> Double? {
        guard let image = PreviewImages.image(data) else { return nil }
        let visages = (vision?["visages"]?.array ?? []).compactMap { rectangle($0["cadre"]) }
        let debut = Date()
        guard Eclairage.mesurer(image, visages: visages, sujet: rectangle(vision?["zone_d_interet"])) != nil else { return nil }
        return Date().timeIntervalSince(debut) * 1000
    }

    // MARK: - Vérifications sans Lightroom

    /// La lecture du boîtier d'un fichier Fujifilm (RAF, ou JPEG de l'appareil), sans Lightroom
    /// (`mcp-developpeur --boitier`), pour la comparer à exiftool : le point de mise au point (dans
    /// le fichier entier, avant l'orientation), l'intention comme view_photo la donne (RAW d'après
    /// l'extension .raf ; profil de Lightroom du catalogue, ou d'un Look installé sans restriction
    /// d'appareil : le modèle n'est pas lu ici), la mise au point en détail comme l'onglet Focus de
    /// la fenêtre Claude la montre (`mise_au_point`), et les valeurs lues, sous les noms d'exiftool. Une
    /// seule ouverture, bornée (LecteurBoitier : 2 s). nil si rien n'est lu (autre marque, fichier
    /// illisible, original qui ne s'ouvre pas à temps).
    public static func lectureBoitier(_ fichier: URL, lecteur: LecteurBoitier = LecteurBoitier(),
                                      looks: LookProfileLibrary = LookProfileLibrary()) -> JSONValue? {
        guard let lecture = lecteur.lire(fichier), lecture.point != nil || lecture.intention != nil || lecture.miseAuPoint != nil else { return nil }
        var json: [String: JSONValue] = ["fichier": .string(fichier.lastPathComponent)]
        var valeurs: [String: JSONValue] = [:]
        if let point = lecture.point {
            var af: [String: JSONValue] = ["x": .number((point.x * 1000).rounded() / 1000), "y": .number((point.y * 1000).rounded() / 1000),
                                           "avertissement": .bool(point.avertissement)]
            if let visages = point.visages { af["visages"] = .number(Double(visages)) }
            json["point_af"] = .object(af)
        }
        if let intention = lecture.intention {
            let raw = fichier.pathExtension.lowercased() == "raf"
            let profil = raw ? intention.profilLightroom(marque: "FUJIFILM", modele: nil, looks: looks) : nil
            json["intention_boitier"] = intention.json(raw: raw, profil: profil, profilActuel: nil)
            valeurs.merge(valeursLues(intention).object ?? [:]) { a, _ in a }
        }
        // La mise au point en détail, comme l'onglet Focus la montre (sans la géométrie de
        // Lightroom : le point n'est pas situé dans le cadre).
        if let m = lecture.miseAuPoint {
            func lignes(_ liste: [MiseAuPointBoitier.Ligne]) -> JSONValue { .array(liste.map { .string("\($0.titre) : \($0.valeur)") }) }
            json["mise_au_point"] = ["image": lignes(m.lignesImage), "prise_de_vue": lignes(m.lignesPriseDeVue),
                                     "mise_au_point": lignes(m.lignesMiseAuPoint())]
            valeurs.merge(m.valeursLues) { a, _ in a }
        }
        if !valeurs.isEmpty { json["valeurs_lues"] = .object(valeurs) }
        return .object(json)
    }

    /// Les valeurs lues dans la MakerNote et l'Exif, sous les noms et numéros d'exiftool (tons en
    /// crans de l'appareil, compensation en IL).
    static func valeursLues(_ i: IntentionBoitier) -> JSONValue {
        var valeurs: [String: JSONValue] = [:]
        let entiers: [(String, Int?)] = [
            ("FilmMode (0x1401)", i.simulation), ("Saturation (0x1003)", i.saturation),
            ("DynamicRangeSetting (0x1402)", i.reglagePlage), ("DevelopmentDynamicRange (0x1403)", i.plageDeveloppement),
            ("AutoDynamicRange (0x140b)", i.plageAuto), ("DRangePriority (0x1443)", i.priorite),
            ("DRangePriorityAuto (0x1444)", i.prioriteAuto), ("DRangePriorityFixed (0x1445)", i.prioriteFixe),
            ("WhiteBalance (0x1002)", i.balance), ("PictureMode (0x1031)", i.modeImage), ("SceneRecognition (0x1425)", i.scene),
            ("ExposureProgram (0x8822)", i.programme),
        ]
        for (nom, valeur) in entiers {
            if let valeur { valeurs[nom] = .number(Double(valeur)) }
        }
        let reels: [(String, Double?)] = [("HighlightTone (0x1041, crans)", i.tonsClairs), ("ShadowTone (0x1040, crans)", i.tonsFonces),
                                          ("ExposureCompensation (0x9204, IL)", i.compensation)]
        for (nom, valeur) in reels {
            if let valeur { valeurs[nom] = .number((valeur * 1000).rounded() / 1000) }
        }
        return .object(valeurs)
    }

    /// Bibliothèque : collection de recette, classement, recherche critère par critère, annulations.
    /// Le mot-clé « MCP-Développeur (recette) › Essai » et la collection « Claude › Recette
    /// MCP-Développeur » restent dans le catalogue, vides, et resservent à la recette suivante.
    func sequenceBibliotheque(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let avant = try etat(id)
        let raison: JSONValue = "Recette automatisée du module."
        var collection: JSONValue = .null
        func ids(_ criteres: [String: JSONValue]) throws -> [Int] {
            var arguments = criteres
            arguments["collection"] = collection
            let (reponse, _) = try appel("find_photos", arguments)
            return (reponse["photos"]?.array ?? []).compactMap { $0["id"]?.int }
        }
        try etape(photo, "collection de recette") {
            let (reponse, _) = try appel("manage_collections", ["action": "create", "name": "Recette MCP-Développeur", "photo_ids": [photoID],
                                                                "step_name": "recette", "confirm": true, "reason": raison])
            collection = reponse["collection"]?["id"] ?? .null
            try verifier(collection.int != nil, "pas d'identifiant de collection : \(JSONCoding.line(reponse))")
            try verifier(try ids([:]).contains(id), "la photo n'est pas dans la collection")
            return "collection \(collection.int ?? 0) dans l'ensemble « Claude »"
        }
        let note = avant.classement["note"]?.int == 4 ? 3 : 4
        let drapeau = avant.classement["drapeau"]?.string == "retenue" ? ("reject", "rejetée") : ("pick", "retenue")
        let libelle = avant.classement["libelle"]?.string == "rouge" ? ("green", "vert") : ("red", "rouge")
        let motCle = "MCP-Développeur (recette) > Essai"
        try etape(photo, "classement (note, drapeau, libellé, titre, mot-clé)") {
            try ecrire("set_metadata", id, ["rating": .number(Double(note)), "flag": .string(drapeau.0), "color_label": .string(libelle.0),
                                            "title": "Recette MCP-Développeur", "add_keywords": [.string(motCle)]])
            let c = try etat(id).classement
            try verifier(c["note"]?.int == note, "note \(JSONCoding.line(c["note"] ?? .null)) au lieu de \(note)")
            try verifier(c["drapeau"]?.string == drapeau.1, "drapeau « \(c["drapeau"]?.string ?? "?") » au lieu de « \(drapeau.1) »")
            try verifier(c["libelle"]?.string == libelle.1, "libellé « \(c["libelle"]?.string ?? "?") » au lieu de « \(libelle.1) »")
            try verifier(c["titre"]?.string == "Recette MCP-Développeur", "titre « \(c["titre"]?.string ?? "?") »")
            try verifier(c["mots_cles"]?.array?.contains(.string(motCle)) == true, "mots-clés \(JSONCoding.line(c["mots_cles"] ?? .null))")
            return "note \(note), \(drapeau.1), \(libelle.1), titre et mot-clé relus"
        }
        // Chaque critère trouve la photo, et sa contre-épreuve ne la trouve pas : un critère que
        // Lightroom ignorerait sans erreur rendrait toutes les photos de la collection.
        try etape(photo, "recherche, critère par critère") {
            let (info, _) = try appel("get_settings", ["photo_id": photoID])
            var epreuves: [(String, [String: JSONValue], [String: JSONValue])] = [
                ("note", ["rating_min": .number(Double(note)), "rating_max": .number(Double(note))], ["rating_min": .number(Double(note + 1))]),
                ("drapeau", ["flag": .string(drapeau.0)], ["flag": drapeau.0 == "pick" ? "reject" : "pick"]),
                ("libellé", ["color_label": .string(libelle.0)], ["color_label": "blue"]),
                ("mot-clé", ["keyword": "Essai"], ["keyword": "Introuvable MCP"]),
                ("texte", ["text": "Recette MCP"], ["text": "Introuvable MCP"]),
                ("format", ["file_format": "RAW"], ["file_format": "JPG"]),
                ("retouchée par Claude", ["edited_by_claude": true], ["edited_by_claude": false]),
                ("depuis N jours", ["last_days": 36500], ["last_days": 1]),
            ]
            if let modele = info["appareil"]?["modele"]?.string {
                epreuves.append(("appareil", ["camera": .string(modele)], ["camera": "Appareil inexistant MCP"]))
            }
            var echecs: [String] = []
            for (nom, oui, non) in epreuves {
                do {
                    if try !ids(oui).contains(id) { echecs.append("\(nom) : photo pas trouvée") }
                    if try ids(non).contains(id) { echecs.append("\(nom) : la contre-épreuve la trouve aussi") }
                } catch {
                    echecs.append("\(nom) : \(error)")
                }
            }
            try verifier(echecs.isEmpty, echecs.joined(separator: " ; "))
            return "\(epreuves.count) critères, chacun avec sa contre-épreuve"
        }
        try etape(photo, "annulation du classement") {
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            try verifier(try !ids(["keyword": "Essai"]).contains(id), "le mot-clé est resté")
            return "note, drapeau, libellé, titre et mot-clé d'avant"
        }
        // Constaté en 2.3 : un paramètre prédéfini de métadonnées ne se voit qu'après l'écriture qui
        // l'applique ; le module relit ses champs ensuite. Sauté sans paramètre prédéfini.
        try etape(photo, "paramètre prédéfini de métadonnées") {
            let (liste, _) = try appel("export_photos", ["list": true])
            guard let preset = liste["presets_metadonnees"]?.array?.first?["nom"]?.string else {
                return "sauté : aucun paramètre prédéfini de métadonnées dans ce catalogue"
            }
            let (reponse, _) = try appel("set_metadata", ["photo_ids": [photoID], "metadata_preset": .string(preset), "confirm": true,
                                                          "reason": "Recette automatisée du module."])
            let changements = reponse["resultats"]?.array?.first?["changements"]?.array ?? []
            let (annule, _) = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            try verifier(!changements.isEmpty, "aucun champ relu : \(JSONCoding.line(reponse))")
            let remis = annule["resultats"]?.array?.first?["reglages_remis"]?["Bibliotheque"]?.string ?? ""
            try verifier(remis.contains("champs IPTC"), "annulation : « \(remis) »")
            return "« \(preset) » : \(changements.count) champ(s) relus après l'écriture, puis défaits"
        }
        // 2.4 : texte alternatif, champs IPTC et position GPS écrits, relus, puis défaits.
        try etape(photo, "texte alternatif, champs IPTC et position GPS") {
            try ecrire("set_metadata", id, ["alt_text": "Recette MCP-Développeur : texte alternatif.",
                                            "iptc": ["city": "Recetteville", "event": "Recette MCP-Développeur"],
                                            "gps": ["latitude": 46.8139, "longitude": -71.2080, "altitude": 98]])
            let c = try etat(id).classement
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), avant)
            try verifier(c["texte_alternatif"]?.string == "Recette MCP-Développeur : texte alternatif.", "texte alternatif « \(c["texte_alternatif"]?.string ?? "?") »")
            try verifier(c["iptc"]?["city"]?.string == "Recetteville" && c["iptc"]?["event"]?.string == "Recette MCP-Développeur",
                         "IPTC \(JSONCoding.line(c["iptc"] ?? .null))")
            let lat = c["gps"]?["latitude"]?.double ?? 0, alt = c["gps"]?["altitude"]?.double ?? 0
            try verifier(abs(lat - 46.8139) < 1e-4 && abs(alt - 98) < 0.5, "GPS \(JSONCoding.line(c["gps"] ?? .null))")
            return "relus, puis défaits (réglages et classement d'avant)"
        }
        try etape(photo, "photos jamais exportées") {
            let exportee = avant.classement["exportee"]?.bool == true
            try verifier(try ids(["exported": .bool(exportee)]).contains(id), "pas trouvée avec exported = \(exportee)")
            try verifier(try !ids(["exported": .bool(!exportee)]).contains(id), "trouvée aussi avec exported = \(!exportee)")
            return exportee ? "déjà exportée" : "jamais exportée"
        }
        try etape(photo, "filtre de la Bibliothèque, puis le filtre d'avant") {
            let (pose, _) = try appel("show_photo", ["collection": collection, "filter": ["rating_min": 5]])
            let (remis, _) = try appel("show_photo", ["restore_filter": true])
            try verifier(pose["filtre"]?.string?.hasPrefix("Filtre posé") == true, "filtre : \(JSONCoding.line(pose))")
            try verifier(remis["filtre"]?.string?.hasPrefix("Filtre d'avant Claude remis") == true, "remise : \(JSONCoding.line(remis))")
            return "posé sur la collection, puis remis"
        }
        // L'avant/après est une vue du module Développement ; la Bibliothèque revient ensuite.
        try etape(photo, "avant/après dans Lightroom") {
            let (reponse, _) = try appel("show_photo", ["photo_ids": [photoID], "view": "before_after"])
            try verifier(reponse["module"]?.string == "Développement", "module « \(reponse["module"]?.string ?? "?") »")
            try verifier(reponse["a_savoir"]?.string?.contains("pas l'état d'avant Claude") == true, "la limite de l'Avant n'est pas dite")
            _ = try appel("show_photo", ["photo_ids": [photoID], "view": "loupe"])
            return "montrée en avant/après, puis en loupe dans la Bibliothèque"
        }
        try etape(photo, "retrait de la collection, puis son annulation") {
            try ecrire("manage_collections", id, ["action": "remove", "collection": collection])
            try verifier(try !ids([:]).contains(id), "la photo est restée dans la collection")
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifier(try ids([:]).contains(id), "l'annulation ne l'a pas remise dans la collection")
            return "retirée, puis remise"
        }
    }

    func sequenceJPEG(_ id: Int, _ depart: Etat, _ photo: String) throws {
        guard let t0 = depart.temperature else { throw Echec(description: "pas de balance des blancs lisible") }
        var balance = depart
        try etape(photo, "balance personnalisée") {
            try ecrire("apply_settings", id, ["settings": ["Temperature": 10], "relative": true])
            balance = try etat(id)
            try verifierProche(balance.temperature, t0 + 10, "température")
            return "\(Self.nombre(t0)) → \(Self.nombre(t0 + 10))"
        }
        try etape(photo, "tonalité automatique") {
            try ecrire("apply_settings", id, ["auto_tone": true])
            try verifierBalance(try etat(id), balance)
            return "balance gardée"
        }
        try etape(photo, "masque IA (sujet)") {
            try ecrire("add_mask", id, ["masks": [["kind": "subject", "name": "Recette sujet", "adjustments": ["Exposure": 0.05]]]])
            let apres = try etat(id)
            try verifier(apres.nombreMasques == depart.nombreMasques + 1, "\(apres.nombreMasques) masques au lieu de \(depart.nombreMasques + 1)")
            try verifierBalance(apres, balance)
            return "balance gardée"
        }
    }

    func sequenceFlash(_ id: Int, _ depart: Etat, _ photo: String) throws {
        var yeux: [(x: Double, y: Double, rayon: Double)] = []
        var zone = CGRect.zero
        try etape(photo, "pupilles par Vision") {
            let (info, images) = try appel("view_photo", ["photo_id": .number(Double(id))])
            for visage in info["vision"]?["visages"]?.array ?? [] {
                let rayon = visage["rayon_yeux_rouges"]?.double ?? 0.004
                for pupille in visage["pupilles"]?.array ?? [] {
                    if let x = pupille["x"]?.double, let y = pupille["y"]?.double { yeux.append((x, y, rayon)) }
                }
            }
            try verifier(!yeux.isEmpty, "Vision ne voit aucune pupille")
            // Zone carrée autour du premier œil, en fractions de l'image.
            let image = images.first.flatMap(PreviewImages.image)
            let aspect = image.map { Double($0.width) / Double($0.height) } ?? 1.5
            let largeur = 0.08, hauteur = min(1, 0.08 * aspect)
            zone = CGRect(x: min(max(yeux[0].x - largeur / 2, 0), 1 - largeur), y: min(max(yeux[0].y - hauteur / 2, 0), 1 - hauteur),
                          width: largeur, height: hauteur)
            return "\(yeux.count) pupille(s)"
        }
        func regarder(_ nom: String) throws -> String {
            let (_, images) = try appel("view_photo", ["photo_id": .number(Double(id)), "region": [
                "x": .number(zone.minX), "y": .number(zone.minY), "width": .number(zone.width), "height": .number(zone.height)]])
            guard let first = images.first else { throw Echec(description: "aucune image") }
            return garder(first, nom) ?? "(image non enregistrée)"
        }
        var avant = ""
        try etape(photo, "zoom sur un œil, avant") { avant = try regarder("yeux-rouges-avant.jpg"); return avant }
        try etape(photo, "correction des yeux rouges") {
            try ecrire("retouch_spots", id, ["red_eyes": .array(yeux.map { ["x": .number($0.x), "y": .number($0.y), "radius": .number($0.rayon)] })],
                       cible: "photo_id")
            let (info, _) = try appel("get_settings", ["photo_id": .number(Double(id))])
            let nombre = info["yeux_rouges"]?.int ?? 0
            try verifier(nombre == yeux.count, "\(nombre) correction(s) au lieu de \(yeux.count)")
            return "\(nombre) correction(s)"
        }
        try etape(photo, "zoom sur un œil, après") { "à comparer à l'œil : \(avant) et \(try regarder("yeux-rouges-apres.jpg"))" }
    }

    /// Constaté en 2.3 sur une vraie photo au flash (Kodak DX4900) : la part de pixels rouges dans
    /// les pupilles passait de 0,36 et 0,25 à 0,01 et 0 après la correction. Rejoué ici : zoom sur
    /// chaque pupille avant et après, la part de pixels rouges au centre doit tomber.
    func sequenceYeuxRouges(_ id: Int, _ depart: Etat, _ photo: String) throws {
        var yeux: [(x: Double, y: Double, rayon: Double)] = []
        var aspect = 1.5
        try etape(photo, "pupilles par Vision") {
            let (info, images) = try appel("view_photo", ["photo_id": .number(Double(id))])
            for visage in info["vision"]?["visages"]?.array ?? [] {
                let rayon = visage["rayon_yeux_rouges"]?.double ?? 0.004
                for pupille in visage["pupilles"]?.array ?? [] {
                    if let x = pupille["x"]?.double, let y = pupille["y"]?.double { yeux.append((x, y, rayon)) }
                }
            }
            try verifier(!yeux.isEmpty, "Vision ne voit aucune pupille")
            if let image = images.first.flatMap(PreviewImages.image) { aspect = Double(image.width) / Double(image.height) }
            return "\(yeux.count) pupille(s)"
        }
        // Part de pixels rouges dans un carré centré sur chaque pupille, de la taille de la pupille.
        func rouges() throws -> [Double] {
            try yeux.map { oeil in
                let largeur = max(oeil.rayon * 8, 0.02), hauteur = min(1, largeur * aspect)
                let zone = CGRect(x: min(max(oeil.x - largeur / 2, 0), 1 - largeur), y: min(max(oeil.y - hauteur / 2, 0), 1 - hauteur),
                                  width: largeur, height: hauteur)
                let (_, images) = try appel("view_photo", ["photo_id": .number(Double(id)), "region": [
                    "x": .number(zone.minX), "y": .number(zone.minY), "width": .number(zone.width), "height": .number(zone.height)]])
                guard let data = images.first else { throw Echec(description: "aucune image") }
                return Self.partRouge(data, centre: CGPoint(x: (oeil.x - zone.minX) / zone.width, y: (oeil.y - zone.minY) / zone.height),
                                      rayon: oeil.rayon / zone.width)
            }
        }
        var avant: [Double] = []
        try etape(photo, "pixels rouges dans les pupilles, avant") {
            avant = try rouges()
            try verifier(avant.contains { $0 > 0.1 }, "pas de pupille rouge : \(avant.map(Self.nombre).joined(separator: ", "))")
            return avant.map(Self.nombre).joined(separator: ", ")
        }
        try etape(photo, "correction des yeux rouges, mesurée") {
            try ecrire("retouch_spots", id, ["red_eyes": .array(yeux.map { ["x": .number($0.x), "y": .number($0.y), "radius": .number($0.rayon)] })],
                       cible: "photo_id")
            let apres = try rouges()
            for (a, b) in zip(avant, apres) where a > 0.1 {
                try verifier(b < a / 3, "part de rouge \(Self.nombre(a)) → \(Self.nombre(b)) : pas assez retirée")
            }
            _ = try appel("undo_last", ["photo_ids": [.number(Double(id))]])
            try verifierEgal(try etat(id), depart)
            return "\(avant.map(Self.nombre).joined(separator: ", ")) → \(apres.map(Self.nombre).joined(separator: ", ")), puis annulé"
        }
    }

    /// Part des pixels rouges (rouge franc, nettement au-dessus du vert et du bleu) dans un disque
    /// de l'image (centre et rayon en fractions de la largeur).
    static func partRouge(_ data: Data, centre: CGPoint, rayon: Double) -> Double {
        guard let image = PreviewImages.image(data), let pixels = Measurements.rgba(image) else { return 0 }
        let w = image.width, h = image.height
        let cx = Double(centre.x) * Double(w), cy = Double(centre.y) * Double(h), r = max(2, rayon * Double(w))
        var total = 0, rouges = 0
        for y in max(0, Int(cy - r))..<min(h, Int(cy + r) + 1) {
            for x in max(0, Int(cx - r))..<min(w, Int(cx + r) + 1) where hypot(Double(x) - cx, Double(y) - cy) <= r {
                let i = (y * w + x) * 4
                let (rr, g, b) = (Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
                total += 1
                if rr > 90, rr > 1.6 * g, rr > 1.6 * b { rouges += 1 }
            }
        }
        return total == 0 ? 0 : Double(rouges) / Double(total)
    }

    /// Constaté en 2.3 sur un RAF de X-T20 : Lightroom range ses simulations sous d'autres
    /// orthographes (« Camera Pro Neg. Hi »), et n'a ni ETERNA ni REALA ACE pour lui. Rejoué ici.
    func sequenceXT20(_ id: Int, _ depart: Etat, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "profils d'un X-T20") {
            let (liste, _) = try appel("list_profiles", ["photo_id": photoID])
            try verifier(liste["appareil"]?.string?.contains("X-T20") == true, "appareil « \(liste["appareil"]?.string ?? "?") »")
            try verifier(liste["utilisation"]?.string?.contains("X-T20") == true, "la limite des boîtiers anciens n'est pas dite")
            return liste["appareil"]?.string ?? "?"
        }
        try etape(photo, "Pro Neg Hi relu sous le nom du X-T20") {
            try ecrire("apply_settings", id, ["profile": "Camera Pro Neg Hi"])
            let profil = try etat(id).profil
            let nom = profil.string ?? profil["nom"]?.string ?? JSONCoding.line(profil)
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            try verifier(nom.lowercased().hasPrefix("camera pro neg") && nom.contains("Hi"), "profil relu « \(nom) »")
            return "« \(nom) », puis annulé"
        }
        // 1.1.1 : le point de mise au point lu dans le RAF, dessiné sur l'aperçu pour noter, et
        // l'évaluation gardée dite par view_photo.
        try etape(photo, "point de mise au point dessiné pour noter (view_photo, af_point)") {
            let (info, images) = try appel("view_photo", ["photo_id": photoID, "af_point": true, "size": 1024])
            try verifier(!images.isEmpty, "pas d'image")
            try verifier(info["evaluation"]?.string?.isEmpty == false, "évaluation non dite")
            try verifier(info["photo"]?["chemin_original"] == nil, "le chemin de l'original est allé à Claude")
            guard let point = info["point_af"], let x = point["x"]?.double, let y = point["y"]?.double else {
                return "aucun point lu (original absent ou sans point AF) ; évaluation : \(info["evaluation"]?.string ?? "?")"
            }
            try verifier(point["carre"]?.string != nil, "carré non dessiné : \(JSONCoding.line(point))")
            return String(format: "point %.2f × %.2f, carré %@ ; évaluation : %@", x, y, point["carre"]?.string ?? "?",
                          info["evaluation"]?.string ?? "?")
        }
        try etapeIntention(id, photo)
        try etape(photo, "ETERNA refusé, profil d'avant remis") {
            let (reponse, _) = try appel("apply_settings", ["photo_ids": [photoID], "profile": "Camera ETERNA/Cinema", "step_name": "recette",
                                                            "confirm": true, "reason": "Recette automatisée du module."])
            let remarques = (reponse["resultats"]?.array?.first?["remarques"]?.array ?? []).compactMap(\.string)
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            try verifier(remarques.contains { $0.contains("non disponible pour cet appareil") }, "remarques : \(remarques.joined(separator: " ; "))")
            return "refusé (Lightroom le rendrait comme Adobe Standard), dit en remarque"
        }
    }

    /// 1.2 : le bilan de view_photo d'une passe à l'autre, sur une photo dans l'état `attendu`.
    /// Relevé le 20 octobre 2026 sur les 8 copies « Essai » : deux vues de suite à la même taille
    /// donnent les mêmes mesures (plancher nul) ; une proposition se rend un peu autrement qu'une vue
    /// (jusqu'à 0,9 point d'écrêtage) : le bilan ne compare jamais l'une à l'autre. Une étape écrite
    /// fait apparaître son écart, l'annulation le défait. Netteté et bruit, dits ici, relèvent leurs
    /// seuils (encore provisoires) sur un vrai RAW ; les deux vues sont gardées (--images).
    func etapeBilan(_ id: Int, _ photo: String, attendu: Etat) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "bilan chiffré d'une passe à l'autre (view_photo), puis annulé") {
            func bilan() throws -> JSONValue { try appel("view_photo", ["photo_id": photoID, "size": 1024]).0["bilan"] ?? .null }
            let (premiere, avant) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let image = avant.first { garder(image, "recette-bilan-avant.jpg") }
            var seconde = try bilan()
            // La photo porte des masques IA (étapes précédentes) : un calcul fini entre les deux rendus
            // change l'image (a_savoir à la première vue). Une vue de plus, alors seulement.
            if seconde["meme_etat"] == nil, premiere["a_savoir"] != nil { seconde = try bilan() }
            try verifier(seconde["meme_etat"] != nil, "deux vues de suite à 1024 px diffèrent : \(JSONCoding.line(seconde))")
            // L'empreinte des retouches à la main suppose que le module relit les mêmes valeurs dans
            // le même ordre : sans retouche, elle ne bouge pas d'une vue à l'autre.
            try verifier(seconde["corrections_utilisateur"] == nil, "retouche à la main vue entre deux vues identiques : \(JSONCoding.line(seconde))")
            let (proposition, _) = try appel("preview_settings", ["photo_id": photoID, "step_name": "recette : essai",
                                                                   "settings": ["Exposure2012": 1], "relative": true])
            try verifier(proposition["bilan"] == nil, "bilan d'une proposition sans compare : \(JSONCoding.line(proposition["bilan"] ?? .null))")
            let apresProposition = try bilan()
            try verifier(apresProposition["meme_etat"] != nil && apresProposition["corrections_utilisateur"] == nil,
                         "la vue qui suit une proposition l'a comparée : \(JSONCoding.line(apresProposition))")
            try ecrire("apply_settings", id, ["settings": ["Exposure2012": 2, "Whites2012": 50], "relative": true])
            let (vue, images) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let image = images.first { garder(image, "recette-bilan-apres.jpg") }
            let ecrite = vue["bilan"] ?? .null
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            let defaite = try bilan()
            try verifierEgal(try etat(id), attendu)
            let il = ecrite["ecarts"]?["exposition"]?["IL"]?.double
            try verifier((il ?? 0) >= 0.5, "exposition \(il.map(Self.nombre) ?? "absente") IL au lieu de +0,5 au moins : \(JSONCoding.line(ecrite))")
            try verifier(ecrite["etapes_claude"]?.string?.hasPrefix("1 de plus") == true,
                         "étapes de Claude après l'écriture : \(ecrite["etapes_claude"].map(JSONCoding.line) ?? "absentes")")
            try verifier(defaite["etapes_claude"]?.string?.hasPrefix("1 de moins") == true,
                         "étapes de Claude après l'annulation : \(defaite["etapes_claude"].map(JSONCoding.line) ?? "absentes")")
            try verifier(defaite["regression"] == nil, "« regression » après l'annulation : \(JSONCoding.line(defaite["regression"] ?? .null))")
            // Une régression de l'écrêtage dépend de la photo : dite, pas exigée.
            let regressions = (ecrite["regression"]?.array ?? []).compactMap(\.string)
            return "deux vues identiques (meme_etat), la proposition ignorée ; +2 IL et Whites +50 : \(Self.resumeEcarts(ecrite["ecarts"]))"
                + (regressions.isEmpty ? " ; aucune regression" : " ; regression : " + regressions.joined(separator: " ; "))
                + " ; annulé : 1 de moins, sans regression"
        }
    }

    /// 1.2 : l'intention de la prise de vue, lue dans l'original Fujifilm (view_photo, aperçu
    /// entier : intention_boitier). Recoupé le 20 octobre 2026 sur de vrais RAF (X-H2S, X-T4,
    /// X-T20), MakerNote lue à la main : simulation, plage dynamique, tons, mode. view_photo ne fait
    /// qu'un rendu : la photo ne change pas, et le chemin de l'original ne va pas à Claude.
    func etapeIntention(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "intention lue au boîtier (view_photo, intention_boitier)") {
            let avant = try etat(id)
            let (info, _) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            try verifierEgal(try etat(id), avant)
            try verifier(info["photo"]?["chemin_original"] == nil, "le chemin de l'original est allé à Claude")
            let marque = info["appareil"]?["marque"]?.string
            guard marque?.uppercased().contains("FUJIFILM") == true else {
                return "sautée : pas un fichier Fujifilm (\(marque ?? "marque inconnue"))"
            }
            guard let intention = info["intention_boitier"] else {
                return "rien de lu : original absent, ou pas ouvert dans les 2 s (autorisation de macOS ?)"
            }
            let simulation = intention["simulation"]?.string ?? ""
            let lecture = (intention["lecture"]?.array ?? []).compactMap(\.string)
            try verifier(!simulation.isEmpty, "simulation non lue : \(JSONCoding.line(intention))")
            try verifier(!lecture.isEmpty, "aucune lecture : \(JSONCoding.line(intention))")
            let lus = ["profil", "plage_dynamique", "priorite_plage_dynamique", "couleur", "tons_clairs", "tons_fonces", "compensation",
                       "mode", "balance", "scene"].compactMap { cle in intention[cle].map { "\(cle) \($0.string ?? JSONCoding.line($0))" } }
            return "simulation \(simulation)" + (lus.isEmpty ? "" : ", " + lus.joined(separator: ", "))
                + " ; \(lecture.count) phrase(s) de lecture"
        }
    }

    /// 1.2 : la peau dosée comme Adobe (Peau.swift), sur un portrait d'essai : trois doses en
    /// propositions, avec le détail gardé au milieu des joues ; l'intensité d'un masque, linéaire
    /// (constaté le 20 octobre 2026 au pixel près : amount 50 rend comme la moitié des curseurs) ;
    /// une dose trop forte refusée sans smoothing_requested ; enfin la dose par défaut posée, relue,
    /// puis annulée.
    func sequencePortrait(_ id: Int, _ depart: Etat, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        var visage = CGRect.zero
        try etape(photo, "visages vus par Vision (view_photo)") {
            let (info, _) = try appel("view_photo", ["photo_id": photoID, "size": 1344])
            let cadres = (info["vision"]?["visages"]?.array ?? []).compactMap { Self.rectangle($0["cadre"]) }
            guard let plusGrand = cadres.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
                throw Echec(description: "Vision ne voit aucun visage : choisir un portrait (--portrait)")
            }
            visage = plusGrand
            return "\(cadres.count) visage(s) ; le plus grand fait \(Self.nombre(Double(plusGrand.width) * 100)) % de la largeur"
        }
        try etapeCarteDuMasque(id, depart, photo)
        try sequencePeau(id, depart, photo, visage: visage)
    }

    /// 1.3.4 : la carte du masque (CarteMasque.swift), en proposition : la peau du visage et
    /// l'arrière-plan, un rendu témoin chacun. La peau doit couvrir le plus grand visage, l'arrière-plan
    /// ne pas déborder sur lui ; rien n'est gardé.
    func etapeCarteDuMasque(_ id: Int, _ depart: Etat, _ photo: String) throws {
        try etape(photo, "carte du masque : un rendu témoin par masque, visages et alertes (add_mask, mask_map, en proposition)") {
            let (info, images) = try appel("add_mask", ["photo_ids": [.number(Double(id))], "preview": true, "size": 1024, "step_name": "recette",
                                                        "mask_map": true,
                                                        "masks": [["kind": "person_part", "part": "face_skin", "adjustments": ["Exposure": 0.1]],
                                                                  ["kind": "background", "adjustments": ["Exposure": -0.1]]]])
            try verifierEgal(try etat(id), depart)
            let carte = info["carte_des_masques"] ?? .null
            let cartes = carte["masques"]?.array ?? []
            try verifier(cartes.count == 2, "deux cartes attendues : \(JSONCoding.line(carte))")
            try verifier(images.count >= 2, "l'image de la carte et celle de la proposition attendues")
            let peau = cartes[0], fond = cartes[1]
            let partPeau = peau["part_de_l_image_pct"]?.double ?? 0, partFond = fond["part_de_l_image_pct"]?.double ?? 0
            let visagePeau = peau["visages_couverts_pct"]?.array?.first?.double ?? 0
            let visageFond = fond["visages_couverts_pct"]?.array?.first?.double ?? 100
            let alertes = (fond["alertes"]?.array ?? []).compactMap(\.string)
            try verifier(visagePeau >= 30, "la peau couvre \(Self.nombre(visagePeau)) % du visage : \(JSONCoding.line(peau))")
            try verifier(visageFond < CarteMasque.debordVisage * 100 && alertes.isEmpty,
                         "l'arrière-plan couvre \(Self.nombre(visageFond)) % du visage : \(alertes.joined(separator: " ; "))")
            return "peau : \(Self.nombre(partPeau)) % de l'image, \(Self.nombre(visagePeau)) % du visage ; arrière-plan : \(Self.nombre(partFond)) % de l'image, \(Self.nombre(visageFond)) % du visage ; aucune alerte"
        }
    }

    /// La peau dosée sur le visage que Vision a vu (`visage`, en fractions de l'image) : les doses
    /// en propositions, l'intensité, le refus, puis la dose par défaut posée et annulée.
    func sequencePeau(_ id: Int, _ depart: Etat, _ photo: String, visage: CGRect) throws {
        let photoID = JSONValue.number(Double(id))
        let peau: [String: JSONValue] = ["kind": "person_part", "part": "face_skin"]
        func masque(_ reste: [String: JSONValue]) -> JSONValue { .object(peau.merging(reste) { $1 }) }
        func proposition(_ reste: [String: JSONValue]) throws -> Data {
            let (_, images) = try appel("add_mask", ["photo_ids": [photoID], "preview": true, "size": 1344, "step_name": "recette",
                                                     "masks": [masque(reste)]])
            guard let image = images.first else { throw Echec(description: "aperçu de la proposition manquant") }
            return image
        }
        let forteInstallee = tools.localEffects.effect(named: "Soften Skin") != nil
        // Le milieu des joues : le centre du visage, descendu de 15 % de sa hauteur ; une zone de la
        // moitié de sa largeur.
        func detailDesJoues(_ data: Data) -> Double? {
            guard let image = PreviewImages.image(data) else { return nil }
            let point = CGPoint(x: visage.midX, y: min(visage.midY + 0.15 * visage.height, 1))
            let cote = Double(visage.width) * Double(image.width) * 0.5 / Double(min(image.width, image.height))
            return Detail.nettete(image, autour: point, cote: cote)
        }
        // Les rendus de chaque effet à pleine dose : le témoin de l'intensité.
        var pleines: [String: Data] = [:]
        try etape(photo, "peau : trois doses en propositions, détail des joues mesuré") {
            // Le point de comparaison : une proposition presque neutre sur la même peau.
            let base = try proposition(["adjustments": ["Exposure": 0.01]])
            var doses: [(String, [String: JSONValue])] = [("Peau du visage lisse", ["effect": "Peau du visage lisse"]),
                                                          ("Adoucir la peau (Lite)", ["effect": "Soften Skin (Lite)"])]
            if forteInstallee { doses.append(("Adoucir la peau, demandé", ["effect": "Soften Skin", "smoothing_requested": true])) }
            guard let detailBase = detailDesJoues(base), detailBase > 0 else { throw Echec(description: "détail des joues illisible sur l'aperçu") }
            var gardes: [(String, Double, Double)] = []
            for (nom, reste) in doses {
                let image = try proposition(reste)
                if let effet = reste["effect"]?.string { pleines[effet] = image }
                guard let detail = detailDesJoues(image) else { throw Echec(description: "\(nom) : détail des joues illisible") }
                gardes.append((nom, detail / detailBase, Self.partChangee(base, image)))
            }
            try verifierEgal(try etat(id), depart)
            let textes = gardes.map { "\($0.0) : \(Self.nombre($0.1 * 100)) % du détail gardé, \(Self.nombre($0.2 * 100)) % des pixels changés" }
            // La dose la plus forte doit toucher la peau : sinon Lightroom ne l'a pas reconnue.
            try verifier((gardes.last?.1 ?? 1) < 1, "rien de lissé (Lightroom ne reconnaît pas la peau ?) : \(textes.joined(separator: " ; "))")
            return textes.joined(separator: " ; ") + (forteInstallee ? "" : " ; « Adoucir la peau » absent de ce Mac")
        }
        try etape(photo, "intensité d'un masque : amount \(Peau.nombre(Peau.intensiteReduite)) = la moitié de la dose (propositions)") {
            // Au pixel près, et non par partChangee : un lissage fin change peu de pixels de plus de
            // 12 niveaux (relevé le 20 octobre 2026 : dose entière contre moitié, 7 niveaux au plus),
            // et l'étape passerait même si Lightroom ignorait l'intensité. La dose entière sert de
            // témoin : elle doit se distinguer de la moitié, sinon il n'y a rien à juger.
            let part = Peau.intensiteReduite / 100
            var ecarts: [String] = []
            for (effet, dose) in [("Peau du visage lisse", Peau.parDefaut), ("Soften Skin (Lite)", Peau.lite)] {
                let reduit = try proposition(["effect": .string(effet), "amount": .number(Peau.intensiteReduite)])
                let curseurs = try proposition(["adjustments": ["Texture": .number(dose.texture * part), "Clarity": .number(dose.clarte * part)]])
                guard let plein = pleines[effet], let ecart = Self.ecartMax(reduit, curseurs), let temoin = Self.ecartMax(reduit, plein) else {
                    throw Echec(description: "« \(effet) » : aperçus illisibles ou de tailles différentes")
                }
                try verifier(ecart <= Self.ecartIdentique, "« \(effet) » à amount \(Peau.nombre(Peau.intensiteReduite)) contre la moitié de ses curseurs : "
                             + "jusqu'à \(Self.nombre(ecart)) niveaux d'écart (\(Self.nombre(Self.ecartIdentique)) au plus)")
                try verifier(temoin > Self.ecartIdentique + 1, "« \(effet) » : la dose entière et la moitié ne se distinguent pas sur cette photo "
                             + "(\(Self.nombre(temoin)) niveaux d'écart au plus) : rien à juger")
                ecarts.append("« \(effet) » : \(Self.nombre(ecart)) niveau(x) d'écart au plus avec la moitié des curseurs, \(Self.nombre(temoin)) avec la dose entière")
            }
            try verifierEgal(try etat(id), depart)
            return ecarts.joined(separator: " ; ")
        }
        try etape(photo, "peau trop lissée refusée sans smoothing_requested, rien d'écrit") {
            // « Adoucir la peau » (clarté −100), ou des curseurs au-delà de la dose Lite.
            let forte: [String: JSONValue] = forteInstallee ? ["effect": "Soften Skin"] : ["adjustments": ["Texture": -50, "Clarity": -30]]
            let refus = tools.call(name: "add_mask", arguments: ["photo_ids": [photoID], "masks": [masque(forte)], "step_name": "recette",
                                                                 "confirm": true, "reason": "Recette automatisée du module."])
            try verifier(refus.isError && refus.text.contains("smoothing_requested"), "pas refusée : \(refus.text)")
            try verifierEgal(try etat(id), depart)
            return forteInstallee ? "« Adoucir la peau » refusé" : "texture −50, clarté −30 refusées"
        }
        try etape(photo, "dose par défaut posée à amount \(Peau.nombre(Peau.intensiteReduite)), relue, annulée") {
            try ecrire("add_mask", id, ["masks": [masque(["effect": "Peau du visage lisse", "amount": .number(Peau.intensiteReduite)])]])
            func derniere() throws -> JSONValue? {
                try appel("get_settings", ["photo_id": photoID, "all_keys": true]).0["tous_les_reglages"]?["MaskGroupBasedCorrections"]?.array?.last
            }
            var correction = try derniere()
            var calcul = "calculée dès la retouche"
            if correction?["CorrectionMasks"]?.array?.first?["MaskDigest"]?.string == nil {
                _ = try appel("view_photo", ["photo_id": photoID, "size": 512])
                correction = try derniere()
                calcul = "calculée avant le rendu"
            }
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)
            let zone = correction?["CorrectionMasks"]?.array?.first
            func proche(_ cle: String, _ attendu: Double) -> Bool { correction?[cle]?.double.map { abs($0 - attendu) < 0.001 } == true }
            try verifier(correction?["CorrectionName"]?.string?.contains("Peau du visage lisse") == true, "nom relu : \(correction?["CorrectionName"].map(JSONCoding.line) ?? "absent")")
            try verifier(proche("CorrectionAmount", Peau.intensiteReduite / 100) && proche("LocalTexture", Peau.parDefaut.texture / 100)
                         && proche("LocalClarity2012", Peau.parDefaut.clarte / 100),
                         "intensité et curseurs relus : \(correction.map(JSONCoding.line) ?? "absents")")
            try verifier(zone?["MaskSubType"]?.double == 3 && zone?["MaskSubCategoryID"]?.double == 2,
                         "pas la peau du visage : \(zone.map(JSONCoding.line) ?? "aucun masque")")
            try verifier(zone?["MaskDigest"]?.string != nil, "peau pas calculée par Lightroom : \(zone.map(JSONCoding.line) ?? "aucun masque")")
            return "CorrectionAmount \(Peau.nombre(Peau.intensiteReduite / 100)), texture et clarté relues, peau du visage \(calcul) ; annulée"
        }
    }

    /// 1.2 : l'éclairage mixte nommé par view_photo (mesures › eclairage), sur une photo que Dany
    /// désigne comme éclairée par deux lumières (--mixte : lampe et fenêtre) ; puis, en témoin, le
    /// RAW de la recette (`unique`, une autre photo) lu à une seule lumière. Lecture seule.
    /// Relevé le 20 octobre 2026 sur les 8 copies « Essai » : à la balance de la photo, seul le
    /// portrait (fenêtres et éclairage chaud) se lit mixte, ses 9 cases lues ; mesure en 85 à 200 ms.
    func sequenceEclairage(_ id: Int, unique: Int? = nil) {
        /// L'éclairage d'une copie d'essai par view_photo, la photo inchangée ; avec la durée de la
        /// mesure, refaite sur l'aperçu rendu (visages et zone d'intérêt de Vision, comme view_photo).
        /// Dans l'étape : une photo introuvable est un échec noté, pas une séquence muette.
        func lire(_ id: Int) throws -> (eclairage: JSONValue, duree: Double?) {
            let depart = try etat(id)
            try verifier(depart.copieVirtuelle == true || originaux, "c'est un original : la recette n'y touche qu'avec l'option --original")
            let (info, images) = try appel("view_photo", ["photo_id": .number(Double(id))])
            try verifierEgal(try etat(id), depart)
            guard let eclairage = info["mesures"]?["eclairage"] else { throw Echec(description: "pas de mesure de l'éclairage") }
            return (eclairage, images.first.flatMap { Self.dureeEclairage($0, vision: info["vision"]) })
        }
        func ms(_ duree: Double?) -> String { duree.map { "\(Int($0.rounded())) ms" } ?? "?" }
        try? etape("éclairage \(id)", "éclairage mixte nommé (view_photo)") {
            let (eclairage, duree) = try lire(id)
            let lecture = eclairage["lecture"]?.string ?? "?"
            try verifier(eclairage["mixte"]?.bool == true && lecture.hasPrefix("éclairage mixte"), "pas lu comme un éclairage mixte : \(lecture)")
            let grille = (eclairage["regions_3x3"]?.array ?? []).flatMap { $0.array ?? [] }
            try verifier(grille.count == 9 && eclairage["conseil"]?.string != nil, "grille ou conseil absents : \(JSONCoding.line(eclairage))")
            let lues = grille.filter { !$0.isNull }.count
            let balance = eclairage["balance_proposee"].map { " ; balance proposée : Temperature \($0["Temperature"].map(JSONCoding.line) ?? "?"), Tint \($0["Tint"].map(JSONCoding.line) ?? "?")" } ?? ""
            return "\(lecture) ; \(lues)/9 cases lues ; mesure en \(ms(duree))\(balance)"
        }
        guard let unique else { return }
        try? etape("éclairage \(unique)", "une seule lumière, en témoin (view_photo)") {
            let (eclairage, duree) = try lire(unique)
            let lecture = eclairage["lecture"]?.string ?? "?"
            try verifier(eclairage["mixte"]?.bool == false && !lecture.hasPrefix("éclairage mixte"),
                         "lu comme un éclairage mixte (une seule lumière attendue sur le RAW de la recette) : \(lecture)")
            let ecart = eclairage["ecart_regions"]?.double.map { " ; écart entre régions \(Self.nombre($0))" } ?? ""
            return "\(lecture)\(ecart) ; mesure en \(ms(duree))"
        }
    }

    // MARK: - Déroulement

    /// Vérifie que la photo est une copie virtuelle (ou un original, avec `originaux`) que Claude
    /// n'a pas encore retouchée, déroule la séquence, puis la remet à l'origine et vérifie qu'elle
    /// est revenue à son état de départ.
    func sequence(_ photo: String, id: Int, corps: (Int, Etat, String) throws -> Void) {
        var depart: Etat?
        do {
            try etape(photo, "photo d'essai") {
                let initial = try etat(id)
                guard let virtuelle = initial.copieVirtuelle else {
                    throw Echec(description: "le module Lightroom ne dit pas si c'est une copie virtuelle : installer la même version que ce serveur")
                }
                try verifier(virtuelle || originaux, "c'est un original : la recette n'y touche qu'avec l'option --original")
                let (info, _) = try appel("view_photo", ["photo_id": .number(Double(id)), "size": 512])
                // Le retour à l'origine de la fin effacerait aussi les retouches de Claude d'avant la recette.
                try verifier(info["photo"]?["retouchee_par_claude"]?.bool != true,
                             "Claude a déjà retouché cette photo : le retour à l'origine de la fin effacerait aussi ces retouches ; en prendre une autre")
                depart = initial
                var detail = "\(info["photo"]?["fichier"]?.string ?? "?"), \(initial.nombreMasques) masque(s), balance \(initial.balance ?? "?")"
                if !virtuelle {
                    let (statut, _) = try appel("get_status", [:])
                    let instantane = statut["instantane_avant_claude"]?.bool == true ? ", et l'instantané « Avant Claude »" : ""
                    detail += " ; original : son historique gardera les étapes de la recette\(instantane)"
                }
                return detail
            }
        } catch {
            return
        }
        guard let depart else { return }
        // Constaté en 2.4 : une photo d'essai rangée dans la collection de recette par Claude garde
        // cet ajout dans sa mémoire, et le retour à l'origine de la fin l'en retirait. Elle y est
        // remise (une étape de classement, qui ne fait pas « retouchée par Claude »).
        let dansCollection = (try? dansLaCollectionDeRecette(id)) ?? false
        var remise = false
        do {
            try corps(id, depart, photo)
            try etape(photo, "retour à l'origine") {
                remise = true
                _ = try appel("revert_to_original", ["photo_ids": [.number(Double(id))]])
                try verifierEgal(try etat(id), depart)
                return "réglages identiques à ceux du départ" + (try remettreDansLaCollection(id, dansCollection))
            }
        } catch {
            if !remise {
                try? etape(photo, "remise à l'origine après l'échec") {
                    _ = try appel("revert_to_original", ["photo_ids": [.number(Double(id))]])
                    // Une livraison faite avant l'échec reste une exportation : revenir ne l'efface pas.
                    let apres = try etat(id)
                    var attendu = depart
                    if var classement = depart.classement.object, let exportee = apres.classement["exportee"] {
                        classement["exportee"] = exportee
                        attendu.classement = .object(classement)
                    }
                    try verifierEgal(apres, attendu)
                    return "réglages identiques à ceux du départ" + (try remettreDansLaCollection(id, dansCollection))
                }
            }
        }
    }

    /// Collection des photos d'essai (ensemble « Développeur », collection « Essais ») : les copies
    /// virtuelles que Claude a choisies et rangées, que la recette peut retoucher.
    static let collectionDeRecette = "Développeur > Essais"

    func dansLaCollectionDeRecette(_ id: Int) throws -> Bool {
        let (reponse, _) = try appel("find_photos", ["collection": .string(Self.collectionDeRecette), "limit": 500])
        return (reponse["photos"]?.array ?? []).contains { $0["id"]?.int == id }
    }

    /// Remet la photo dans la collection de recette si elle y était au départ ; le texte à ajouter
    /// au détail de l'étape.
    func remettreDansLaCollection(_ id: Int, _ dansCollection: Bool) throws -> String {
        guard dansCollection, try !dansLaCollectionDeRecette(id) else { return "" }
        try ecrire("manage_collections", id, ["action": "add", "collection": .string(Self.collectionDeRecette)])
        try verifier(try dansLaCollectionDeRecette(id), "pas remise dans « \(Self.collectionDeRecette) »")
        return " ; remise dans la collection de recette"
    }

    func etape(_ photo: String, _ nom: String, _ corps: () throws -> String) throws {
        let debut = Date()
        do {
            let detail = try corps()
            noter(Etape(photo: photo, nom: nom, reussie: true, detail: detail, duree: Date().timeIntervalSince(debut)))
        } catch {
            noter(Etape(photo: photo, nom: nom, reussie: false, detail: "\(error)", duree: Date().timeIntervalSince(debut)))
            throw error
        }
    }

    func noter(_ etape: Etape) {
        etapes.append(etape)
        rapport(etape)
    }

    // MARK: - Outils

    /// Appelle un outil comme Claude ; renvoie son JSON et ses images. Une erreur de l'outil
    /// devient un échec de l'étape.
    func appel(_ outil: String, _ arguments: [String: JSONValue]) throws -> (JSONValue, [Data]) {
        let resultat = tools.call(name: outil, arguments: arguments)
        var texte = "", images: [Data] = []
        for bloc in resultat.content {
            switch bloc {
            case .text(let t): texte += t
            case .image(let base64, _): if let data = Data(base64Encoded: base64) { images.append(data) }
            }
        }
        if resultat.isError { throw Echec(description: texte) }
        return ((try? JSONCoding.parse(texte)) ?? .string(texte), images)
    }

    /// La photo active de Lightroom (son identifiant), lue par get_status ; nil sans photo active.
    func photoActive() throws -> Int? {
        try appel("get_status", [:]).0["photo_active"]?["id"]?.int
    }

    /// L'écart de la photo active après un passage au module Développement : nil si celle d'avant
    /// est revenue (ou s'il n'y en avait pas). Constaté le 21 octobre 2026 : sans la remise de la
    /// sélection après celle de la source (Bibliotheque.remettreSelection), une autre photo restait
    /// active.
    static func ecartPhotoActive(avant: Int?, apres: Int?) -> String? {
        guard let avant, apres != avant else { return nil }
        return "photo active \(apres.map(String.init) ?? "aucune") au lieu de \(avant) après le passage au module Développement "
            + "(la vue d'avant n'est pas remise)"
    }

    /// La proposition de note d'une photo dans le registre du module (notation.json), telle que la
    /// commande notation lire la rend ; nil sans proposition. Lecture seule.
    func propositionDuRegistre(_ id: Int) throws -> JSONValue? {
        let reponse = try tools.lightroom.send("notation", ["action": "lire", "photos": [.number(Double(id))]], timeout: 30)
        return reponse["propositions"]?.array?.first { $0["photo"]?.int == id }
    }

    /// Remet la proposition d'une photo telle qu'elle a été lue (nil : aucune, retirée), par la
    /// commande notation remettre ; rien n'est écrit dans le catalogue.
    func remettreProposition(_ id: Int, _ proposition: JSONValue?) throws {
        _ = try tools.lightroom.send("notation", ["action": "remettre", "photo": .number(Double(id)), "proposition": proposition ?? .null],
                                     timeout: 30)
    }

    /// Fait `corps` (une étape qui propose et pose des notes), puis remet le registre des notes de la
    /// photo comme il était avant, même après un échec, et vérifie qu'il l'est. Le registre ne voit
    /// pas undo_last : la note posée puis défaite par la recette y restait « acceptee » (constaté le
    /// 21 octobre 2026, 53709912), comme si Dany l'avait acceptée.
    func garderRegistreDesNotes<T>(_ id: Int, _ corps: () throws -> T) throws -> T {
        let avant = try propositionDuRegistre(id)
        let resultat: T
        do {
            resultat = try corps()
        } catch {
            try? remettreProposition(id, avant)
            throw error
        }
        try remettreProposition(id, avant)
        let apres = try propositionDuRegistre(id)
        try verifier(apres == avant, "registre des notes pas remis : \(apres.map(JSONCoding.line) ?? "aucune proposition") "
                     + "au lieu de \(avant.map(JSONCoding.line) ?? "aucune proposition")")
        return resultat
    }

    /// Retouche réelle : nom d'étape « recette », accord donné (la recette est lancée à la main).
    func ecrire(_ outil: String, _ id: Int, _ arguments: [String: JSONValue], cible: String = "photo_ids") throws {
        var tous = arguments
        tous[cible] = cible == "photo_ids" ? [.number(Double(id))] : .number(Double(id))
        tous["step_name"] = "recette"
        tous["confirm"] = true
        tous["reason"] = "Recette automatisée du module."
        _ = try appel(outil, tous)
    }

    func etat(_ id: Int) throws -> Etat {
        let (info, _) = try appel("get_settings", ["photo_id": .number(Double(id))])
        return Etat(reglages: info["reglages"] ?? .null, masques: info["masques"] ?? .array([]), profil: info["profil"] ?? .null,
                    recadrage: info["recadrage"] ?? .null, balance: info["balance_des_blancs"]?.string,
                    copieVirtuelle: info["photo"]?["copie_virtuelle"]?.bool, classement: info["classement"] ?? .null)
    }

    func verifier(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition { throw Echec(description: message()) }
    }

    func verifierProche(_ valeur: Double?, _ attendu: Double, _ nom: String) throws {
        guard let valeur, abs(valeur - attendu) < 0.6 else {
            throw Echec(description: "\(nom) \(valeur.map(Self.nombre) ?? "absente") au lieu de \(Self.nombre(attendu))")
        }
    }

    func verifierBalance(_ etat: Etat, _ attendu: Etat) throws {
        try verifier(etat.balance == attendu.balance, "balance « \(etat.balance ?? "?") » au lieu de « \(attendu.balance ?? "?") »")
        try verifierProche(etat.temperature, attendu.temperature ?? 0, "température")
        try verifierProche(etat.teinte, attendu.teinte ?? 0, "teinte")
    }

    func verifierEgal(_ etat: Etat, _ attendu: Etat) throws {
        guard etat.comparable != attendu.comparable else { return }
        throw Echec(description: "différences : " + Self.differences(etat, attendu).prefix(6).joined(separator: " ; "))
    }

    static func differences(_ etat: Etat, _ attendu: Etat) -> [String] {
        var lignes: [String] = []
        let groupes = Set((etat.reglages.object ?? [:]).keys).union((attendu.reglages.object ?? [:]).keys).sorted()
        for groupe in groupes {
            let a = etat.reglages[groupe]?.object ?? [:], b = attendu.reglages[groupe]?.object ?? [:]
            for cle in Set(a.keys).union(b.keys).sorted() where a[cle] != b[cle] {
                lignes.append("\(cle) \(b[cle].map(JSONCoding.line) ?? "—") → \(a[cle].map(JSONCoding.line) ?? "—")")
            }
        }
        if etat.nombreMasques != attendu.nombreMasques { lignes.append("masques \(attendu.nombreMasques) → \(etat.nombreMasques)") }
        else if etat.masques != attendu.masques { lignes.append("masques modifiés") }
        if etat.profil != attendu.profil { lignes.append("profil \(JSONCoding.line(attendu.profil)) → \(JSONCoding.line(etat.profil))") }
        if etat.recadrage != attendu.recadrage { lignes.append("recadrage modifié") }
        if etat.classement != attendu.classement {
            lignes.append("classement \(JSONCoding.line(attendu.classement)) → \(JSONCoding.line(etat.classement))")
        }
        return lignes
    }

    /// La bande horizontale qu'un trait de pinceau a assombrie entre deux rendus de même taille,
    /// mesurée au milieu de l'image (de 45 % à 55 % de la largeur) : sa hauteur en pixels (là où
    /// l'écart de luminance dépasse la moitié de son maximum), son centre en part de la hauteur, et
    /// la largeur du rendu.
    static func bandeAssombrie(avant: Data, apres: Data) -> (hauteur: Double, centre: Double, largeur: Double)? {
        func pixels(_ data: Data) -> (w: Int, h: Int, v: [UInt8])? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let w = image.width, h = image.height
            var v = [UInt8](repeating: 0, count: w * h)
            guard let ctx = CGContext(data: &v, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return (w, h, v)
        }
        guard let a = pixels(avant), let b = pixels(apres), a.w == b.w, a.h == b.h, a.h > 10 else { return nil }
        // Par rangée, la part des pixels assombris d'au moins 20 % le long du trait (de 32 à 68 % de
        // la largeur). Constaté le 17 octobre 2026 : un écart moyen en niveaux, à mi-hauteur, donnait
        // 26 px au lieu de 41 sur une famille en vêtements sombres (−2 IL y assombrit peu en valeur
        // absolue), alors que la bande se voyait entière.
        let x0 = Int(Double(a.w) * 0.32), x1 = Int(Double(a.w) * 0.68)
        var parts = [Double](repeating: 0, count: a.h)
        for y in 0..<a.h {
            var assombris = 0, comptes = 0
            for x in x0..<x1 {
                let avant = Double(a.v[y * a.w + x]), apres = Double(b.v[y * a.w + x])
                guard avant > 12 else { continue }
                comptes += 1
                if apres < avant * 0.8 { assombris += 1 }
            }
            parts[y] = comptes > 0 ? Double(assombris) / Double(comptes) : 0
        }
        guard let maximum = parts.max(), maximum > 0.5, let pic = parts.firstIndex(of: maximum) else { return nil }
        var haut = pic, bas = pic
        while haut > 0, parts[haut - 1] > 0.5 { haut -= 1 }
        while bas < a.h - 1, parts[bas + 1] > 0.5 { bas += 1 }
        return (Double(bas - haut + 1), (Double(haut + bas) / 2 + 0.5) / Double(a.h), Double(a.w))
    }

    /// Réglages qui attendent encore leur calcul automatique par Lightroom.
    static func valeursEnAttente(_ etat: Etat) -> Int {
        (etat.reglages.object ?? [:]).values.reduce(0) { total, groupe in
            total + (groupe.object ?? [:]).values.filter { $0.string == ToolHandler.pendingAutoText }.count
        }
    }

    @discardableResult
    func garder(_ image: Data, _ nom: String) -> String? {
        guard let images else { return nil }
        try? FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let fichier = images.appendingPathComponent(nom)
        return (try? image.write(to: fichier)) != nil ? fichier.path : nil
    }

    static func nombre(_ valeur: Double) -> String { DevelopCatalogue.format((valeur * 100).rounded() / 100) }
}
