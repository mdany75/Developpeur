import CoreGraphics
import Foundation

/// Recette de la 1.3 (« Apprendre en regardant Claude travailler ») : les cinq chantiers vérifiés
/// dans le vrai Lightroom, sur les copies d'essai de « Développeur › Essais », chaque étape défaite.
/// - « Pourquoi ? » : l'avant/après d'une étape gardé par le module (avant_apres, que seule la
///   recette envoie : il lève aussi la condition de la photo active, d'où ni show_photo ni fenêtre
///   ouverte), l'avant tiré de la vue sans second rendu, puis l'étape annulée ;
/// - la leçon de la photo : indices lus (read_facts), leçon d'une photo d'essai refusée par l'outil
///   (rangee = false : elle n'entre pas au carnet de Dany), puis rangée pour la recette par la
///   commande du module (essai_recette, sous l'entrée de la copie), relue, puis retirée ;
/// - le carnet de progrès : une photo d'essai refusée, puis notée pour la recette (essai_recette),
///   au mois de sa prise de vue, exportée (export_journal avec notebook), puis retirée, même si une
///   vérification échoue ;
/// - « Je le fais » : la version de Claude rangée sans rien appliquer, des réglages faits « à la
///   main », la comparaison côte à côte et ses écarts, puis la version effacée ;
/// - la composition lue (`--horizon`, une photo qui a un vrai horizon) : le cadre proposé
///   montré tel quel, le cadre actuel lu sur l'image entière, puis le cadre proposé appliqué et
///   l'horizon mesuré, droit et sur le tiers du bas.
/// Les quatre premiers vont dans la séquence du RAW (sequenceApprendre, après le bilan ;
/// sequenceJeLeFais, après les variantes), la composition dans sa propre séquence (lancer).
extension Recette {
    // MARK: - Réglages de la recette

    /// Nom de l'étape écrite pour l'avant/après (« Claude · recette : pourquoi » dans l'Historique).
    static let etapePourquoi = "recette : pourquoi"
    /// Attente de l'après d'une étape, rendu par le module une fois la réponse d'appliquer partie
    /// (capture d'environ une seconde, mesure 1 de la 1.3 : seuil visé 1,5 s), et le pas des lectures.
    static let attenteCapture: TimeInterval = 30
    static let pasCapture: TimeInterval = 0.25
    /// Le recadrage d'essai de la composition, le même que l'exemple « lire » du contrat
    /// (Tests/Contrats/composition.json) : 4:5, tourné de 2°, centré en x = 0,4, à 70 % du plus
    /// grand cadre.
    static let cadreEssai: JSONValue = ["aspect": "4:5", "angle": 2, "size": 0.7, "center_x": 0.4, "center_y": 0.5]
    /// Écarts permis entre deux cadres (centre, angle, largeur et ratio relatifs) : un cadre gardé
    /// par Lightroom, ou lu sur l'image entière, contre celui demandé.
    static let ecartCentre = 0.003, ecartAngle = 0.01, ecartTaille = 0.005
    /// L'horizon tombe sur le tiers du bas du cadre proposé, à 1 % de la hauteur près ; il y est
    /// droit à 0,2° près (measure_angle).
    static let ecartTiers = 0.01, ecartInclinaison = 0.2
    /// La taille la plus petite du cadre que read_composition propose ici (min_size) : un horizon
    /// près du milieu de l'image ne tient sur le tiers du bas qu'avec un cadre d'environ 75 % du plus
    /// grand (la valeur par défaut) ; plus haut, avec un plus petit. La recette vérifie la
    /// géométrie, pas le goût du cadre.
    static let tailleMinComposition = 0.5
    /// Un point de la leçon, par axe : de quoi la ranger (photo_lesson), pour une photo assombrie et
    /// réchauffée par la recette.
    static let pointsLecon: JSONValue = [
        ["axis": "light", "missing": "Recette : photo sous-exposée, remontée d'au moins 0,7 IL.",
         "at_capture": "Recette : exposer plus clair à la prise de vue.", "defects": ["underexposed"]],
        ["axis": "color", "missing": "Recette : dominante corrigée de 500 K.",
         "at_capture": "Recette : régler la balance des blancs selon la lumière.", "defects": ["color_cast"]],
        ["axis": "composition", "at_capture": "Recette : rien à reprendre au cadrage."],
    ]

    // MARK: - Séquence du RAW

    /// Après le bilan, sur la photo dans l'état `attendu` : l'avant/après d'une étape, la leçon de
    /// la photo, puis le carnet de progrès. Chacun revient à `attendu`.
    func sequenceApprendre(_ id: Int, _ photo: String, depart: Etat, attendu: Etat) throws {
        try etapePourquoi(id, photo, attendu: attendu)
        try etapeLecon(id, photo, depart: depart, attendu: attendu)
        try sequenceCarnet(id, photo)
    }

    // MARK: - « Pourquoi ? »

    /// L'avant/après d'une étape (Etapes.lua) : la vue de l'état actuel (commande apercu, comme
    /// view_photo) gardée par le module, une étape écrite par appliquer, puis l'après rendu une fois
    /// la réponse partie. La commande etapes liste aussi les étapes défaites d'avant (en_memoire =
    /// false, gardées jusqu'au ménage) : l'étape se trouve par l'identifiant que rend appliquer,
    /// jamais par sa place dans la liste. Un réglage seulement, sans cadre : avant_apres n'est pas
    /// transmis à recadrer par le serveur (pas de cadre avec Upright ici).
    func etapePourquoi(_ id: Int, _ photo: String, attendu: Etat) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "avant/après d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé") {
            let memoireAvant = try etapesGardees(id).filter { $0["en_memoire"]?.bool == true }.compactMap { $0["id"]?.string }
            // La vue : l'aperçu entier de l'état actuel, à la taille de view_photo, que le module
            // garde (avant_apres : la photo n'a pas à être la photo active).
            let vue = try tools.lightroom.send("apercu", ["photo": photoID, "taille": .number(Double(ToolHandler.defaultPreviewSize)),
                                                          "cles": [], "avant_apres": true], timeout: 120)
            let imageVue = try ToolHandler.readPreview(vue["chemin"]?.string)
            if let aSavoir = vue["a_savoir"]?.string {
                throw Echec(description: "calculs IA en attente au rendu de la vue, qui n'est donc pas gardée : \(aSavoir)")
            }
            guard let tailleVue = Self.dimensions(imageVue) else { throw Echec(description: "vue illisible") }
            // L'écriture, comme apply_settings (mêmes paramètres), avec avant_apres.
            let arguments = Arguments(raw: ["photo_ids": [photoID], "settings": ["Exposure2012": 0.5], "relative": true,
                                            "step_name": .string(Self.etapePourquoi), "confirm": true,
                                            "reason": "Recette automatisée du module : avant/après d'une étape."])
            var params = try tools.targets(arguments)
            params.merge(try tools.developParameters(arguments).params) { _, nouveau in nouveau }
            params.merge(tools.writeParameters(arguments, defaultStep: "retouche")) { _, nouveau in nouveau }
            params["avant_apres"] = true
            let debut = Date()
            let reponse = try tools.lightroom.send("appliquer", params, timeout: 180)
            guard let etapeId = reponse["resultats"]?.array?.first?["etape_id"]?.string, !etapeId.isEmpty else {
                throw Echec(description: "pas d'etape_id dans la réponse d'appliquer (module d'avant la 1.3 ?) : \(JSONCoding.line(reponse))")
            }
            // L'après se rend une fois la réponse partie : attendre qu'il soit prêt (ou manqué).
            let gardee = try attendreCapture(id, etapeId)
            let duree = Date().timeIntervalSince(debut)
            let memoireApres = try etapesGardees(id).filter { $0["en_memoire"]?.bool == true }.compactMap { $0["id"]?.string }
            let fichierAvant = gardee?["avant"]?.string, fichierApres = gardee?["apres"]?.string
            let avant = fichierAvant.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            let apres = fichierApres.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
            let dureeCapture = fichierAvant.flatMap { Self.dureeCapture(dossier: URL(fileURLWithPath: $0).deletingLastPathComponent(), etape: etapeId) }
            let (annulation, _) = try appel("undo_last", ["photo_ids": [photoID]])
            let defaite = try etapesGardees(id).first { $0["id"]?.string == etapeId }
            try verifierEgal(try etat(id), attendu)

            try verifier(gardee?["etat"]?.string == "pret",
                         "avant/après non gardé : \(gardee?["etat"]?.string ?? "étape absente de la liste")\(gardee?["raison"]?.string.map { " (\($0))" } ?? "")")
            // Une seule étape de plus, la nôtre (une mémoire pleine, Ecriture.MAX_ETAPES, perd la plus
            // ancienne) : ni comparaison ni autre étape gardée.
            try verifier(memoireApres == memoireAvant + [etapeId] || memoireApres == Array(memoireAvant.dropFirst()) + [etapeId],
                         "étapes de Claude en mémoire : \(memoireAvant.count) avant, \(memoireApres.count) après au lieu d'une de plus, la nôtre")
            try verifier(gardee?["nom"]?.string?.hasSuffix(Self.etapePourquoi) == true, "étape nommée « \(gardee?["nom"]?.string ?? "?") »")
            guard let avant, let apres, let tailleAvant = Self.dimensions(avant) else {
                throw Echec(description: "images de l'étape illisibles : \(fichierAvant ?? "pas d'avant") ; \(fichierApres ?? "pas d'après")")
            }
            // Une copie de la vue a ses dimensions ; un second rendu (Etapes.COTE) aurait les siennes.
            try verifier(tailleAvant == tailleVue, "l'avant (\(tailleAvant.0) × \(tailleAvant.1)) n'est pas la vue (\(tailleVue.0) × \(tailleVue.1)) : "
                         + "rendu de nouveau avant l'écriture")
            guard let lAvant = Self.luminanceMoyenne(avant), let lApres = Self.luminanceMoyenne(apres) else {
                throw Echec(description: "luminance des images de l'étape illisible")
            }
            try verifier(lApres > lAvant, "l'après (L* moyen \(Self.nombre(lApres))) n'est pas plus clair que l'avant (\(Self.nombre(lAvant))) pour +0,5 IL")
            let annulee = annulation["resultats"]?.array?.first
            try verifier(annulee?["annulee"]?.bool == true && annulee?["etape_id"]?.string == etapeId,
                         "annulation : \(annulee.map(JSONCoding.line) ?? "aucun résultat")")
            try verifier(defaite?["en_memoire"]?.bool == false, "l'étape défaite n'est pas dite hors de la mémoire : \(defaite.map(JSONCoding.line) ?? "absente")")
            return "« Claude · \(Self.etapePourquoi) » : avant = la vue (\(tailleVue.0) × \(tailleVue.1), sans second rendu), après plus clair "
                + "(L* moyen \(Self.nombre(lAvant)) → \(Self.nombre(lApres))) ; prêt en \(Self.nombre(duree)) s après la réponse"
                + (dureeCapture.map { " (capture : \(Self.nombre($0)) s)" } ?? "") + " ; annulée, gardée hors de la mémoire"
        }
    }

    /// Les étapes de Claude gardées pour la photo (commande etapes, lecture seule) : celles de la
    /// mémoire, puis les défaites.
    func etapesGardees(_ id: Int) throws -> [JSONValue] {
        try tools.lightroom.send("etapes", ["photo": .number(Double(id))], timeout: 30)["etapes"]?.array ?? []
    }

    /// Attend que l'étape `etapeId` soit prête ou manquée : une lecture tous les pasCapture, pendant
    /// attenteCapture au plus (un nombre de lectures borné, même sans attente réelle). Son entrée de
    /// la commande etapes à la dernière lecture, ou nil si elle n'est jamais listée.
    func attendreCapture(_ id: Int, _ etapeId: String) throws -> JSONValue? {
        var entree: JSONValue?
        for lecture in 0...Int(Self.attenteCapture / Self.pasCapture) {
            if lecture > 0 { attendre(Self.pasCapture) }
            entree = try etapesGardees(id).first { $0["id"]?.string == etapeId }
            if let etat = entree?["etat"]?.string, etat == "pret" || etat == "manque" { return entree }
        }
        return entree
    }

    /// La durée de la capture que le module a notée (`<id>.json` de l'étape, champ duree), en
    /// secondes ; nil sans fichier ni durée.
    static func dureeCapture(dossier: URL, etape: String) -> Double? {
        guard let texte = try? String(contentsOf: dossier.appendingPathComponent("\(etape).json"), encoding: .utf8),
              let json = try? JSONCoding.parse(texte) else { return nil }
        return json["duree"]?.double
    }

    /// Largeur et hauteur d'une image ; nil si elle est illisible.
    static func dimensions(_ data: Data) -> (Int, Int)? {
        PreviewImages.image(data).map { ($0.width, $0.height) }
    }

    /// L* moyen d'une image (Measurements) ; nil si elle est illisible.
    static func luminanceMoyenne(_ data: Data) -> Double? {
        Measurements.analyze(data)?.meanL
    }

    // MARK: - La leçon de la photo

    /// La leçon de la photo (photo_lesson) : la photo assombrie et réchauffée par la recette (une
    /// écriture, que Claude aurait corrigée : exposition remontée de 0,7 IL, température baissée de
    /// 500 K, nettes depuis le départ de la séquence), les faits (indices underexposed et color_cast),
    /// la leçon donnée à l'outil (trois points) et refusée par le module comme photo d'essai
    /// (rangee = false, motif essai : 1.3.1, une leçon d'essai n'entre pas au carnet de Dany), puis
    /// rangée par la commande du module avec essai_recette (jamais par un outil), sous l'entrée de la
    /// copie elle-même, relue (lecon lire), retirée (lecon retirer, même si une vérification échoue),
    /// et l'écriture annulée. Une leçon déjà rangée pour la copie (un essai d'avant la 1.3.1) n'est pas
    /// remplacée : l'étape s'arrête avant toute écriture.
    func etapeLecon(_ id: Int, _ photo: String, depart: Etat, attendu: Etat) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, Self.etapeLeconNom) {
            let deja = try tools.lightroom.send("lecon", ["action": "lire", "photos": [photoID]], timeout: 30)["lecons"]?.array ?? []
            guard deja.isEmpty else {
                throw Echec(description: "une leçon est déjà rangée pour cette copie (essai dans la fenêtre d'avant la 1.3.1 ?) : la recette la remplacerait ; "
                    + "la retirer d'abord (mcp-developpeur --module lecon '{\"action\": \"retirer\", \"photo\": \(id)}'), rien n'a été écrit")
            }
            guard let t0 = depart.temperature ?? attendu.temperature else { throw Echec(description: "pas de balance des blancs lisible") }
            // Nettes depuis le départ de la séquence, comme depuis l'état actuel : le journal compte
            // la première valeur d'avant de chaque réglage (Lecon.correctionsNettes).
            let exposition = min(max(Self.valeur(depart, "Exposure2012") ?? 0, Self.valeur(attendu, "Exposure2012") ?? 0) + 0.7, 5)
            let temperature = max(min(t0, attendu.temperature ?? t0) - 500, 2000)
            try ecrire("apply_settings", id, ["settings": ["Exposure2012": .number(exposition), "Temperature": .number(temperature)]])
            let ecrite = try etat(id)
            var aRetirer = false
            defer {
                if aRetirer { _ = try? tools.lightroom.send("lecon", ["action": "retirer", "photo": photoID], timeout: 30) }
            }
            let (faits, _) = try appel("photo_lesson", ["photo_id": photoID, "read_facts": true])
            let indices = (faits["faits"]?["indices"]?.array ?? []).compactMap { $0["defect"]?.string }
            let apresFaits = try etat(id)
            // Retirée même si une vérification échoue : celle que l'outil aurait rangée à tort, puis
            // celle de la recette.
            aRetirer = true
            let (reponse, _) = try appel("photo_lesson", ["photo_id": photoID, "points": Self.pointsLecon])
            let apresLecon = try etat(id)
            let parLOutil = try tools.lightroom.send("lecon", ["action": "lire", "photos": [photoID]], timeout: 30)["lecons"]?.array ?? []
            // Rangée pour la recette : la commande du module, avec essai_recette, que seule la recette
            // envoie (aucun outil ne le porte).
            let points = try Lecon.points(Self.pointsLecon.array ?? [])
            let rangement = try tools.lightroom.send("lecon", ["action": "garder", "photo": photoID, "essai_recette": true,
                                                               "lecon": Lecon.pourLeModule(points: points, indices: [])], timeout: 30)
            let lues = try tools.lightroom.send("lecon", ["action": "lire", "photos": [photoID]], timeout: 30)["lecons"]?.array ?? []
            let retrait = try tools.lightroom.send("lecon", ["action": "retirer", "photo": photoID], timeout: 30)
            aRetirer = false
            let restees = try tools.lightroom.send("lecon", ["action": "lire", "photos": [photoID]], timeout: 30)["lecons"]?.array ?? []
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), attendu)

            try verifier(indices.contains("underexposed") && indices.contains("color_cast"),
                         "indices lus : \(indices.isEmpty ? "aucun" : indices.joined(separator: ", ")) (attendus : underexposed et color_cast)")
            try verifierEgal(apresFaits, ecrite)
            try verifierEgal(apresLecon, ecrite)
            let lecon = reponse["lecon"]
            let remarques = (reponse["remarques"]?.array ?? []).compactMap(\.string)
            try verifier(lecon?["rangee"]?.bool == false && parLOutil.isEmpty,
                         "leçon d'une copie d'essai rangée par photo_lesson (elle irait au carnet de Dany) : \(lecon.map(JSONCoding.line) ?? "?")")
            try verifier(remarques.contains { $0.contains("Photo d'essai") }, "refus de la photo d'essai non dit : \(remarques.joined(separator: " ; "))")
            let fichier = faits["photo"]?["fichier"]?.string
            try verifier(rangement["rangee"]?.bool == true, "leçon non rangée avec essai_recette : \(JSONCoding.line(rangement))")
            try verifier(rangement["photo"]?.int == id && rangement["original"]?.int == id && rangement["fichier"]?.string == fichier,
                         "leçon de la recette rangée sous \(rangement["original"].map(JSONCoding.line) ?? "?") pour \(rangement["fichier"]?.string ?? "?") "
                            + "au lieu de l'entrée de la copie \(id), \(fichier ?? "?")")
            let mois = rangement["mois"]?.string
            try verifier(mois.map(Self.estUnMois) == true || rangement["sans_date"]?.bool == true,
                         "mois de la prise de vue : \(rangement["mois"].map(JSONCoding.line) ?? "absent")")
            let relue = lues.first { $0["photo"]?.int == id }
            try verifier(relue?["points"]?.array?.count == 3, "leçon relue : \(relue.map(JSONCoding.line) ?? "absente")")
            try verifier((retrait["retirees"]?.int ?? 0) >= 1 && !restees.contains { $0["photo"]?.int == id },
                         "leçon pas retirée : \(JSONCoding.line(retrait))")
            return "indices \(indices.joined(separator: ", ")) ; refusée par l'outil (photo d'essai) ; rangée pour la recette sous \(fichier ?? "?")"
                + (mois.map { " (prise de vue \($0))" } ?? " (sans date de prise de vue)") + ", relue, retirée ; écriture annulée"
        }
    }

    /// Le nom de l'étape de la leçon dans la recette.
    static let etapeLeconNom = "leçon de la photo (photo_lesson) : indices lus, refusée pour une photo d'essai, "
        + "rangée pour la recette (essai_recette), relue, retirée ; photo inchangée"

    /// Un mois de prise de vue tel que le module le range (« AAAA-MM »).
    static func estUnMois(_ texte: String) -> Bool {
        texte.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
    }

    /// La valeur numérique d'un réglage dans un état (réglages regroupés par get_settings), quel que
    /// soit son groupe ; nil s'il est absent ou pas encore calculé.
    static func valeur(_ etat: Etat, _ cle: String) -> Double? {
        (etat.reglages.object ?? [:]).values.lazy.compactMap { $0[cle]?.double }.first
    }

    // MARK: - Le carnet de progrès

    /// Le carnet de progrès (Carnet.lua), sur la copie d'essai, retouchée par Claude à ce moment-là :
    /// - d'abord une vue sans essai_recette : refusée comme photo d'essai (motif essai). Une copie
    ///   que le module ne verrait pas dans « Développeur › Essais » serait refusée quand même, pour
    ///   ses étapes de Claude (motif etapes) : rien n'est alors écrit, et rien d'autre n'est envoyé
    ///   (essai_recette n'y lèverait rien, et un angle irait à l'entrée de l'original, une vraie
    ///   photo de Dany) ;
    /// - puis l'angle de son horizon (measure_angle), avec essai_recette : la copie a son entrée à
    ///   elle (original = la copie), au mois de sa prise de vue, que find_photos retrouve au même jour ;
    /// - le carnet relu, puis exporté (export_journal avec notebook) ;
    /// - enfin carnet retirer {photos = [copie]}, même si une vérification échoue.
    /// Rien n'est écrit dans le catalogue. Une copie hors de la collection de recette est sautée.
    func sequenceCarnet(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        try etape(photo, "carnet de progrès : photo d'essai refusée, notée pour la recette (essai_recette), exportée, retirée") {
            guard try dansLaCollectionDeRecette(id) else {
                return "sautée : la copie n'est pas dans « \(Self.collectionDeRecette) » (le carnet noterait son original, une vraie photo)"
            }
            let depart = try etat(id)
            let vue = Carnet.Vue(cherches: ["sous_exposition"], defauts: [])
            let refus = try tools.lightroom.send("carnet", ["action": "constater", "photo": photoID, "vue": vue.json,
                                                            "vocabulaire": PriseDeVue.vocabulaire], timeout: Carnet.delaiConstat)
            guard refus["note"]?.bool == false else {
                throw Echec(description: "vue d'une copie d'essai notée au carnet, sans essai_recette : \(JSONCoding.line(refus)) ; "
                    + "rien d'autre n'est envoyé (entrée à vérifier à la main)")
            }
            guard refus["motif"]?.string == "essai" else {
                // La case Carnet décochée refuse tout avant de regarder la photo : rien n'en est vérifié.
                let cause = refus["motif"]?.string == "preference"
                    ? "cocher la case Carnet du Gestionnaire de modules externes le temps de la recette"
                    : "le module ne voit pas la copie dans « Développeur › Essais »"
                throw Echec(description: "refusée, mais pas comme photo d'essai (motif \(refus["motif"]?.string ?? "?") : \(refus["raison"]?.string ?? "")) : "
                    + cause + " ; rien d'autre n'est envoyé")
            }
            // L'horizon mesuré sur la géométrie de la copie (intacte jusqu'ici : ni recadrage tourné,
            // ni Upright), sans rien noter (le carnet ne note que pour le serveur de Claude).
            let (mesure, _) = try appel("measure_angle", ["photo_id": photoID, "x1": 0.1, "y1": 0.5, "x2": 0.9, "y2": 0.5])
            let inclinaison = mesure["inclinaison"]?.double ?? 0
            let angle = Carnet.angleJSON(Carnet.Constat(code: "horizon_penche", mesure: inclinaison, texte: ""), source: "recette")
            var aRetirer = true
            defer {
                if aRetirer { _ = try? tools.lightroom.send("carnet", ["action": "retirer", "photos": [photoID]], timeout: Carnet.delaiLecture) }
            }
            let note = try tools.lightroom.send("carnet", ["action": "constater", "photo": photoID, "angle": angle,
                                                           "vocabulaire": PriseDeVue.vocabulaire, "essai_recette": true],
                                                timeout: Carnet.delaiConstat)
            guard note["note"]?.bool == true else {
                let motif = note["motif"]?.string
                throw Echec(description: (motif == "geometrie" ? "géométrie de la copie déjà touchée au départ (recadrage tourné, Upright…) : choisir une copie à la géométrie intacte ; " : "")
                    + "angle refusé avec essai_recette : \(JSONCoding.line(note))")
            }
            let mois = note["mois"]?.string
            let priseLe = note["prise_le"]?.string
            let sansDate = note["sans_date"]?.bool == true
            // Le jour de la prise de vue, à l'heure locale, retrouvé par Lightroom (find_photos), et
            // pas la veille.
            var jourTrouve = true, veilleTrouvee = false
            if !sansDate, let jour = priseLe.map({ String($0.prefix(10)) }), let veille = Self.veille(jour) {
                jourTrouve = try photosDuJour(jour, jour).contains(id)
                veilleTrouvee = try photosDuJour(veille, veille).contains(id)
            }
            let lu = try tools.lightroom.send("carnet", ["action": "lire"], timeout: Carnet.delaiLecture)
            let entree = (lu["photos"]?.array ?? []).first { $0["photo"]?.int == id }
            let (journal, _) = try appel("export_journal", ["notebook": true])
            let markdown = journal["markdown"]?.string ?? ""
            let retrait = try tools.lightroom.send("carnet", ["action": "retirer", "photos": [photoID]], timeout: Carnet.delaiLecture)
            aRetirer = false
            let relu = try tools.lightroom.send("carnet", ["action": "lire"], timeout: Carnet.delaiLecture)
            try verifierEgal(try etat(id), depart)

            try verifier(note["original"]?.int == id && note["photo"]?.int == id,
                         "le constat d'essai n'a pas son entrée à elle : original \(note["original"].map(JSONCoding.line) ?? "?")")
            if sansDate {
                // Sans date de prise de vue, le module ne dit pas de mois (mois = la prise de vue de
                // l'entrée) : le résumé la compte au mois de son constat.
                try verifier(mois.map(Self.estUnMois) ?? true, "mois du constat (photo sans date) : \(mois ?? "absent")")
            } else {
                try verifier(mois.map(Self.estUnMois) == true && priseLe?.hasPrefix((mois ?? "?") + "-") == true,
                             "mois \(mois ?? "absent"), prise de vue \(priseLe ?? "absente")")
                try verifier(jourTrouve && !veilleTrouvee,
                             "le jour \(priseLe.map { String($0.prefix(10)) } ?? "?") ne retrouve pas la photo dans Lightroom (heure locale ?)"
                             + (veilleTrouvee ? " ; la veille la retrouve" : ""))
            }
            try verifier(entree?["prise"]?.string == mois && entree?["angle"] != nil && entree?["angle"]?.isNull == false,
                         "entrée relue : \(entree.map(JSONCoding.line) ?? "absente")")
            try verifier(markdown.hasPrefix("# Carnet de progrès"), "export_journal avec notebook : « \(markdown.prefix(60)) »")
            try verifier(retrait["retirees"]?.int == 1 && !(relu["photos"]?.array ?? []).contains { $0["photo"]?.int == id },
                         "entrée pas retirée : \(JSONCoding.line(retrait))")
            return "vue refusée (« \(refus["raison"]?.string ?? "photo d'essai") ») ; angle de \(Self.nombre(inclinaison))° noté pour la recette, "
                + (sansDate ? "sans date de prise de vue (comptée au mois du constat)" : "prise de vue \(priseLe ?? "?"), retrouvée au même jour")
                + " ; exporté, puis retiré ; catalogue inchangé"
        }
    }

    /// Les photos de « Développeur › Essais » prises de `debut` à `fin` (AAAA-MM-JJ, inclus).
    func photosDuJour(_ debut: String, _ fin: String) throws -> [Int] {
        let (reponse, _) = try appel("find_photos", ["collection": .string(Self.collectionDeRecette), "date_from": .string(debut),
                                                     "date_to": .string(fin), "limit": 500])
        return (reponse["photos"]?.array ?? []).compactMap { $0["id"]?.int }
    }

    /// La veille d'un jour (AAAA-MM-JJ) ; nil s'il ne se lit pas.
    static func veille(_ jour: String) -> String? {
        let format = DateFormatter()
        format.calendar = Calendar(identifier: .gregorian)
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        guard let date = format.date(from: jour) else { return nil }
        return format.string(from: date.addingTimeInterval(-86_400))
    }

    // MARK: - « Je le fais »

    /// « Je le fais » : la version de Claude rangée par preview_settings avec my_turn (rien
    /// d'appliqué ni de rendu, a_faire dans l'ordre des panneaux, entrée « exercice » au journal),
    /// puis des réglages faits « à la main » (apply_settings, en guise de Dany), la comparaison
    /// view_photo avec compare = claude_version (une image, les écarts classés), enfin ces réglages
    /// annulés et « ma version » effacée (même si une vérification échoue : ni undo_last ni
    /// revert_to_original ne l'effacent). Une « ma version » déjà rangée arrête l'étape avant toute
    /// écriture.
    func sequenceJeLeFais(_ id: Int, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let depart = try etat(id)
        let maVersion = "Claude · " + JeLeFais.instantane
        func variantes() throws -> [String] {
            (try appel("choose_variant", ["photo_id": photoID, "action": "list"]).0["variantes"]?.array ?? []).compactMap { $0["nom"]?.string }
        }
        try etape(photo, "« Je le fais » : ma version rangée sans rien appliquer, réglages changés, comparée côte à côte, puis effacée") {
            guard try !variantes().contains(maVersion) else {
                throw Echec(description: "« \(maVersion) » est déjà rangée (essai précédent ?) : l'effacer (choose_variant, action = delete, "
                    + "names = [\"\(JeLeFais.instantane)\"]) ; rien n'a été écrit")
            }
            var aEffacer = true
            defer {
                if aEffacer { _ = try? appel("choose_variant", ["photo_id": photoID, "action": "delete", "names": [.string(JeLeFais.instantane)]]) }
            }
            let (tour, imagesTour) = try appel("preview_settings", ["photo_id": photoID, "my_turn": true, "relative": true,
                                                                    "settings": ["Exposure2012": 0.3, "Vibrance": 10],
                                                                    "step_name": "recette : je le fais"])
            let apresTour = try etat(id)
            let rangees = try variantes()
            let entrees = try tools.lightroom.send("journal", ["photos": [photoID]], timeout: 60)["photos"]?.array?.first?["entrees"]?.array ?? []
            // Les réglages de Dany, comme s'il les avait faits à la main.
            try ecrire("apply_settings", id, ["settings": ["Exposure2012": 0.8, "Shadows2012": 20], "relative": true])
            let dany = try etat(id)
            let (comparaison, images) = try appel("view_photo", ["photo_id": photoID, "compare": "claude_version"])
            if let image = images.first { garder(image, "recette-je-le-fais.jpg") }
            let apresComparaison = try etat(id)
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            let annulee = try etat(id)
            let (effacement, _) = try appel("choose_variant", ["photo_id": photoID, "action": "delete", "names": [.string(JeLeFais.instantane)]])
            aEffacer = false
            let restees = try variantes()
            try verifierEgal(try etat(id), depart)

            try verifier(imagesTour.isEmpty, "my_turn a rendu \(imagesTour.count) image(s)")
            try verifierEgal(apresTour, depart)
            let faire = (tour["a_faire"]?.array ?? []).compactMap { $0["cle"]?.string }
            try verifier(faire == ["Exposure2012", "Vibrance"], "a_faire : \(faire.joined(separator: ", ")) (attendu : Exposure2012 puis Vibrance)")
            try verifier(rangees.contains(maVersion), "« \(maVersion) » pas rangée : \(rangees.joined(separator: ", "))")
            try verifier(entrees.last?["type"]?.string == "exercice", "dernière entrée du journal : \(entrees.last.map(JSONCoding.line) ?? "aucune")")
            try verifier(images.count == 1, "\(images.count) image(s) pour la comparaison")
            try verifierEgal(apresComparaison, dany)
            var sortes: [String: String] = [:]
            for ecart in comparaison["exercice"]?["ecarts"]?.array ?? [] {
                if let cle = ecart["cle"]?.string, let sorte = ecart["sorte"]?.string { sortes[cle] = sorte }
            }
            let attendues = ["Exposure2012": JeLeFais.Sorte.plusFort.rawValue, "Shadows2012": JeLeFais.Sorte.ajoute.rawValue,
                             "Vibrance": JeLeFais.Sorte.oublie.rawValue]
            try verifier(attendues.allSatisfy { sortes[$0.key] == $0.value },
                         "écarts : \(sortes.keys.sorted().map { "\($0) \(sortes[$0] ?? "?")" }.joined(separator: ", ")) "
                         + "(attendus : Exposure2012 plus_fort, Shadows2012 ajoute, Vibrance oublie)")
            try verifierEgal(annulee, depart)
            let effaces = (effacement["effaces"]?.array ?? []).compactMap(\.string)
            try verifier(effaces.contains(maVersion) && !restees.contains(maVersion), "« \(maVersion) » pas effacée : \(effaces.joined(separator: ", "))")
            return "a_faire : Exposition puis Vibrance, rien d'appliqué ni rendu ; écarts : Exposition plus fort, Ombres ajoutées, Vibrance oubliée"
                + (comparaison["exercice"]?["resume"]?.string.map { " (« \($0) »)" } ?? "") + " ; réglages annulés, « ma version » effacée"
        }
    }

    // MARK: - La composition lue (--horizon)

    /// L'horizon d'une photo lu par read_composition : sa droite dans l'image entière (un point
    /// `milieu` et son inclinaison, en degrés, positive quand elle monte vers la droite) et l'aspect
    /// de cette image (largeur sur hauteur).
    struct Horizon {
        var milieu: CGPoint
        var inclinaison: Double
        var aspect: Double

        /// Le point de la droite à `s` du milieu, en unités de la hauteur de l'image entière.
        func point(_ s: Double) -> CGPoint {
            let t = inclinaison * .pi / 180
            return CGPoint(x: (Double(milieu.x) * aspect + s * cos(t)) / aspect, y: Double(milieu.y) - s * sin(t))
        }

        /// Deux points de la droite dans l'image que montre view_photo, recadrée par `cadre` (nil :
        /// l'image entière), à `de` et `a` de sa largeur ; nil si l'un tombe hors du cadre. Avec
        /// leur milieu, sur la droite, dans l'image entière.
        func segment(dans cadre: Composition.Cadre?, de: Double = 0.15, a: Double = 0.85) -> (CGPoint, CGPoint, milieu: CGPoint)? {
            func vu(_ s: Double) -> CGPoint { Composition.depuisImageEntiere(point(s), cadre: cadre, aspect: aspect) }
            let u0 = Double(vu(0).x), pente = Double(vu(1).x) - u0
            guard abs(pente) > 1e-9 else { return nil }
            let s1 = (de - u0) / pente, s2 = (a - u0) / pente
            let p1 = vu(s1), p2 = vu(s2)
            guard [p1, p2].allSatisfy({ (0...1).contains(Double($0.x)) && (0...1).contains(Double($0.y)) }) else { return nil }
            return (p1, p2, point((s1 + s2) / 2))
        }
    }

    /// Le cadre d'un crop (celui de read_composition, de apply_settings ou de preview_settings :
    /// aspect, angle, size, center_x, center_y) dans l'image entière d'aspect `aspectImage`, comme le
    /// module le calcule quand il tient dans l'image (Recadrage.calculer) ; nil s'il ne se lit pas.
    static func cadre(crop: JSONValue?, aspectImage: Double) -> Composition.Cadre? {
        guard let crop, crop.object != nil, aspectImage > 0 else { return nil }
        var ratio = aspectImage
        if let texte = crop["aspect"]?.string {
            // « original » : le format de l'image (nil) ; un texte illisible : pas de cadre.
            do {
                ratio = try ToolHandler.aspectRatio(texte) ?? aspectImage
            } catch {
                return nil
            }
        }
        let angle = crop["angle"]?.double ?? 0, taille = crop["size"]?.double ?? 1
        let largeur = taille * Composition.plusGrandeLargeur(ratio: ratio, angle: angle, aspect: aspectImage)
        return Composition.Cadre(centreX: crop["center_x"]?.double ?? 0.5, centreY: crop["center_y"]?.double ?? 0.5,
                                 largeur: largeur, ratio: ratio, angle: angle)
    }

    /// Le cadre gardé par Lightroom que dit preview_settings (cadre_propose : ratio, angle, center_x,
    /// center_y, largeur en part de l'image entière) ; nil s'il manque.
    static func cadre(propose: JSONValue?) -> Composition.Cadre? {
        guard let propose, let ratio = propose["ratio"]?.double, let angle = propose["angle"]?.double,
              let x = propose["center_x"]?.double, let y = propose["center_y"]?.double, let largeur = propose["largeur"]?.double else { return nil }
        return Composition.Cadre(centreX: x, centreY: y, largeur: largeur, ratio: ratio, angle: angle)
    }

    /// Ce qui distingue deux cadres au-delà des écarts permis, en mots ; vide s'ils sont les mêmes.
    static func ecartsDeCadre(_ lu: Composition.Cadre, _ attendu: Composition.Cadre) -> [String] {
        var ecarts: [String] = []
        if abs(lu.centreX - attendu.centreX) > ecartCentre || abs(lu.centreY - attendu.centreY) > ecartCentre {
            ecarts.append("centre \(nombre(lu.centreX)) ; \(nombre(lu.centreY)) au lieu de \(nombre(attendu.centreX)) ; \(nombre(attendu.centreY))")
        }
        if abs(lu.angle - attendu.angle) > ecartAngle { ecarts.append("angle \(nombre(lu.angle))° au lieu de \(nombre(attendu.angle))°") }
        if abs(lu.largeur / attendu.largeur - 1) > ecartTaille {
            ecarts.append("largeur \(nombre(lu.largeur * 100)) % au lieu de \(nombre(attendu.largeur * 100)) %")
        }
        if abs(lu.ratio / attendu.ratio - 1) > ecartTaille { ecarts.append("ratio \(nombre(lu.ratio)) au lieu de \(nombre(attendu.ratio))") }
        return ecarts
    }

    /// L'horizon mesuré dans le cadre proposé, une fois appliqué (`vu`, measure_angle), contre ce que
    /// read_composition promet : droit à `ecartInclinaison` près quand il penche de
    /// Composition.seuilInclinaison ou plus dans l'image entière (`inclinaison`), sinon laissé tel
    /// quel (il ne se voit pas). Un angle proposé du mauvais signe tournerait l'horizon du double :
    /// la géométrie seule (inclinaison + angle du cadre) ne le verrait pas. Puis cette géométrie
    /// même, qui dit si Lightroom tourne le cadre comme le serveur le suppose. Les écarts en mots ;
    /// vide s'il n'y en a pas. Près du seuil (à 0,01° : l'inclinaison est arrondie au centième),
    /// redressé ou non, les deux se valent.
    static func ecartsHorizonApplique(vu: Double, inclinaison: Double, angleCadre: Double) -> [String] {
        var ecarts: [String] = []
        let seuil = Composition.seuilInclinaison
        let attendus = abs(abs(inclinaison) - seuil) <= 0.01 ? [0, inclinaison] : [abs(inclinaison) >= seuil ? 0 : inclinaison]
        if !attendus.contains(where: { abs(vu - $0) <= ecartInclinaison }) {
            ecarts.append(abs(inclinaison) >= seuil
                ? "horizon pas redressé : penché de \(nombre(vu))° dans le cadre (\(nombre(inclinaison))° dans l'image entière, cadre tourné de \(nombre(angleCadre))°)"
                : "horizon penché de \(nombre(vu))° dans le cadre au lieu de \(nombre(inclinaison))° (cadre tourné de \(nombre(angleCadre))°)")
        }
        // Dans un cadre tourné de a, une ligne penchée de t dans l'image entière penche de t + a.
        let geometrie = inclinaison + angleCadre
        if abs(vu - geometrie) > ecartInclinaison {
            ecarts.append("horizon penché de \(nombre(vu))° dans le cadre au lieu de \(nombre(geometrie))° (inclinaison + angle du cadre)")
        }
        return ecarts
    }

    /// Les réglages Crop* bruts de la photo (get_settings, all_keys : CropLeft… et
    /// CropConstrainToWarp), tels que Lightroom les range : read_composition retire le cadre le temps
    /// du rendu de l'image entière, puis le remet, et preview_settings remet la photo comme avant ; ils
    /// doivent revenir exactement (mesure 5 de la 1.3 : au millionième).
    func cadreBrut(_ id: Int) throws -> [String: JSONValue] {
        let tous = try appel("get_settings", ["photo_id": .number(Double(id)), "all_keys": true]).0["tous_les_reglages"]?.object ?? [:]
        return tous.filter { $0.key.hasPrefix("Crop") }
    }

    /// Écart permis entre deux valeurs Crop* relues (mesure 5 de la 1.3 : « identiques au millionième »).
    static let ecartBrut = 1e-6

    /// Les réglages Crop* qui ont changé (un nombre au-delà du millionième, toute autre valeur dès
    /// qu'elle diffère), en mots ; vide s'ils sont revenus.
    static func changementsBruts(_ avant: [String: JSONValue], _ apres: [String: JSONValue]) -> [String] {
        Set(avant.keys).union(apres.keys).sorted().compactMap { cle in
            if let a = avant[cle]?.double, let b = apres[cle]?.double, abs(a - b) <= ecartBrut { return nil }
            return avant[cle] == apres[cle] ? nil
                : "\(cle) \(avant[cle].map(JSONCoding.line) ?? "—") → \(apres[cle].map(JSONCoding.line) ?? "—")"
        }
    }

    /// L'aspect de l'image entière que dit read_composition (image_entiere : largeur, hauteur).
    static func aspectEntier(_ lecture: JSONValue) -> Double? {
        guard let largeur = lecture["image_entiere"]?["largeur"]?.double, let hauteur = lecture["image_entiere"]?["hauteur"]?.double,
              largeur > 0, hauteur > 0 else { return nil }
        return largeur / hauteur
    }

    /// La composition lue sur une photo qui a un horizon (`--horizon`, une copie de « Développeur ›
    /// Essais » ; à `hauteurHorizon` dans l'image que montre view_photo), en trois étapes :
    /// - read_composition, puis son crop montré tel quel par preview_settings (une image, le cadre
    ///   gardé par Lightroom égal au crop), la photo inchangée ;
    /// - le recadrage d'essai du contrat posé (4:5, 2°), puis read_composition : le cadre actuel lu
    ///   sur l'image entière égal à celui posé, l'horizon (donné dans l'image recadrée) retrouvé à sa
    ///   place dans l'image entière ;
    /// - le cadre proposé appliqué : l'horizon sur le tiers du bas (le cadre relu par
    ///   read_composition), droit à 0,2° près (measure_angle, sur une ligne affinée) ; les deux
    ///   recadrages annulés.
    /// Une copie qui porte Upright ou une perspective est refusée d'abord : Lightroom y resserre le
    /// cadre, qui ne serait plus celui proposé. Une photo sans horizon net à `hauteurHorizon` (la
    /// ligne lue n'est pas affinée : LineAngle.ecartMax) ne fait pas échouer la recette : les deux
    /// premières étapes, qui n'en dépendent pas, le disent, et la troisième est sautée avec sa raison
    /// (constaté le 21 octobre 2026 : la dune n'a pas d'horizon à mi-hauteur, et la mesure accrochée
    /// aux rides du sable faisait échouer l'étape sur du bruit ; il faut une copie d'Essais avec un
    /// vrai horizon pour --horizon).
    func sequenceHorizon(_ id: Int, _ depart: Etat, _ photo: String) throws {
        let photoID = JSONValue.number(Double(id))
        let y = hauteurHorizon
        var horizon = Horizon(milieu: .zero, inclinaison: 0, aspect: 1)
        // La ligne lue à hauteurHorizon est-elle un horizon (mesure affinée) ? Sinon, sa raison.
        var sansHorizon: String?
        try etape(photo, "composition lue, cadre proposé en pointillés, photo inchangée (read_composition, preview_settings)") {
            let geometrie = Carnet.clesGeometrie.filter { cle in
                Self.valeur(depart, cle).map { $0 != (cle == "PerspectiveScale" ? 100 : 0) } == true
            }
            try verifier(geometrie.isEmpty, "la copie porte \(geometrie.joined(separator: ", ")) : Lightroom y resserre le cadre ; "
                         + "choisir pour --horizon une copie sans Upright ni perspective")
            let brut = try cadreBrut(id)
            let (lecture, _) = try appel("read_composition", ["photo_id": photoID, "min_size": .number(Self.tailleMinComposition),
                                                              "horizon": ["x1": 0.1, "y1": .number(y), "x2": 0.9, "y2": .number(y)]])
            try verifierEgal(try etat(id), depart)
            let apresLecture = Self.changementsBruts(brut, try cadreBrut(id))
            try verifier(apresLecture.isEmpty, "recadrage changé par read_composition : " + apresLecture.joined(separator: " ; "))
            guard let aspect = Self.aspectEntier(lecture) else { throw Echec(description: "image entière non décrite : \(JSONCoding.line(lecture))") }
            guard let lu = lecture["horizon"], let inclinaison = lu["inclinaison"]?.double, let hauteur = lu["hauteur"]?.double else {
                throw Echec(description: "horizon non lu : \(JSONCoding.line(lecture))")
            }
            if lu["mesure"]?.string?.hasPrefix("affinée") != true {
                sansHorizon = "pas d'horizon net à \(Self.nombre(y)) de la hauteur (\(lu["mesure"]?.string ?? "mesure absente")) : "
                    + "choisir pour --horizon une copie d'Essais qui a un vrai horizon, et sa hauteur par --hauteur-horizon"
            }
            // Le cadre actuel de la copie (aucun, d'ordinaire) : l'horizon donné passe dans l'image entière.
            let cadreDepart = lecture["cadre_actuel"]?.object == nil ? nil : Self.cadre(crop: lecture["cadre_actuel"], aspectImage: aspect)
            let milieu = Composition.versImageEntiere(CGPoint(x: 0.5, y: y), cadre: cadreDepart, aspect: aspect)
            try verifier(abs(Double(milieu.y) - hauteur) <= 0.002,
                         "hauteur de l'horizon \(Self.nombre(hauteur)) au lieu de \(Self.nombre(Double(milieu.y))) (cadre actuel mal lu ?)")
            horizon = Horizon(milieu: milieu, inclinaison: inclinaison, aspect: aspect)
            guard let crop = lecture["crop"], let attendu = Self.cadre(crop: crop, aspectImage: aspect) else {
                throw Echec(description: "pas de cadre proposé : \(JSONCoding.line(lecture))")
            }
            let (proposition, images) = try appel("preview_settings", ["photo_id": photoID, "crop": crop, "step_name": "recette : composition"])
            try verifierEgal(try etat(id), depart)
            let apresProposition = Self.changementsBruts(brut, try cadreBrut(id))
            try verifier(apresProposition.isEmpty, "recadrage changé par preview_settings : " + apresProposition.joined(separator: " ; "))
            if let image = images.first { garder(image, "recette-composition.jpg") }
            try verifier(images.count == 1, "\(images.count) image(s) pour la proposition")
            try verifier(proposition["resume_cadre"]?.string != nil, "pas de résumé du cadre : \(proposition["remarque_cadre"]?.string ?? "")")
            guard let garde = Self.cadre(propose: proposition["cadre_propose"]) else {
                throw Echec(description: "cadre gardé par Lightroom non dit : \(proposition["remarque_cadre"]?.string ?? JSONCoding.line(proposition))")
            }
            let ecarts = Self.ecartsDeCadre(garde, attendu)
            try verifier(ecarts.isEmpty, "le cadre gardé par Lightroom n'est pas le crop proposé : " + ecarts.joined(separator: " ; "))
            return (sansHorizon == nil ? "horizon penché de \(Self.nombre(inclinaison))° à \(Self.nombre(hauteur)) de la hauteur ; "
                    : "\(sansHorizon ?? "") ; ")
                + "proposé : \(lecture["cadre_propose"]?["resume"]?.string ?? "?") ; montré tel quel (\(proposition["resume_cadre"]?.string ?? "?"))"
        }
        var cropPropose: JSONValue = .null
        var ligne = horizon.milieu
        var inclinaisonLue = horizon.inclinaison
        var lachees: [String] = []
        try etape(photo, "cadre actuel lu sur l'image entière (recadrée en 4:5, tournée de 2°)") {
            try ecrire("apply_settings", id, ["crop": Self.cadreEssai])
            let recadree = try etat(id)
            guard let pose = Self.cadre(crop: Self.cadreEssai, aspectImage: horizon.aspect),
                  let segment = horizon.segment(dans: pose) else {
                throw Echec(description: "l'horizon ne traverse pas le recadrage d'essai")
            }
            let brut = try cadreBrut(id)
            let (lecture, _) = try appel("read_composition", ["photo_id": photoID, "min_size": .number(Self.tailleMinComposition), "horizon": [
                "x1": .number(Double(segment.0.x)), "y1": .number(Double(segment.0.y)),
                "x2": .number(Double(segment.1.x)), "y2": .number(Double(segment.1.y))]])
            try verifierEgal(try etat(id), recadree)
            // Le cadre retiré le temps du rendu de l'image entière, puis remis tel quel.
            let remis = Self.changementsBruts(brut, try cadreBrut(id))
            try verifier(remis.isEmpty, "recadrage pas remis exactement après read_composition : " + remis.joined(separator: " ; "))
            let actuel = lecture["cadre_actuel"]
            try verifier(actuel?["aspect"]?.string == "4:5", "format du cadre actuel : \(actuel.map(JSONCoding.line) ?? "absent")")
            guard let lu = Self.cadre(crop: actuel, aspectImage: horizon.aspect) else {
                throw Echec(description: "cadre actuel non lu : \(actuel.map(JSONCoding.line) ?? "absent")")
            }
            let ecarts = Self.ecartsDeCadre(lu, pose)
            try verifier(ecarts.isEmpty, "cadre actuel lu sur l'image entière : " + ecarts.joined(separator: " ; "))
            // L'horizon donné dans l'image recadrée retombe à sa place dans l'image entière.
            let hauteur = lecture["horizon"]?["hauteur"]?.double
            try verifier(hauteur.map { abs($0 - Double(segment.milieu.y)) <= 0.005 } == true,
                         "horizon retrouvé à \(hauteur.map(Self.nombre) ?? "?") de la hauteur au lieu de \(Self.nombre(Double(segment.milieu.y)))")
            guard let crop = lecture["crop"], crop.object != nil else { throw Echec(description: "pas de cadre proposé : \(JSONCoding.line(lecture))") }
            cropPropose = crop
            ligne = segment.milieu
            inclinaisonLue = lecture["horizon"]?["inclinaison"]?.double ?? horizon.inclinaison
            lachees = (lecture["cadre_propose"]?["regles_lachees"]?.array ?? []).compactMap(\.string)
            return "\(actuel?["resume"]?.string ?? "4:5") ; horizon retrouvé à \(Self.nombre(hauteur ?? 0)) de la hauteur ; "
                + "nouveau cadre proposé : \(lecture["cadre_propose"]?["resume"]?.string ?? "?")"
        }
        try etape(photo, "cadre proposé appliqué : horizon droit, sur le tiers du bas (measure_angle), puis annulé") {
            // Sans horizon net, rien à redresser ni à placer : le recadrage d'essai est annulé, la
            // photo revient, et l'étape dit pourquoi elle est sautée.
            if let sansHorizon {
                _ = try appel("undo_last", ["photo_ids": [photoID]])
                try verifierEgal(try etat(id), depart)
                return "sautée : " + sansHorizon + " ; recadrage d'essai annulé"
            }
            try ecrire("apply_settings", id, ["crop": cropPropose])
            let (relecture, _) = try appel("read_composition", ["photo_id": photoID])
            let lu = Self.cadre(crop: relecture["cadre_actuel"], aspectImage: horizon.aspect)
            let surLeTiers = lu.map { Composition.depuisImageEntiere(ligne, cadre: $0, aspect: horizon.aspect) }
            let droite = Horizon(milieu: ligne, inclinaison: inclinaisonLue, aspect: horizon.aspect).segment(dans: lu)
            var mesure: JSONValue = .null
            if let segment = droite {
                mesure = try appel("measure_angle", ["photo_id": photoID, "x1": .number(Double(segment.0.x)), "y1": .number(Double(segment.0.y)),
                                                     "x2": .number(Double(segment.1.x)), "y2": .number(Double(segment.1.y))]).0
            }
            let (_, vue) = try appel("view_photo", ["photo_id": photoID, "size": 1024])
            if let image = vue.first { garder(image, "recette-composition-appliquee.jpg") }
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            _ = try appel("undo_last", ["photo_ids": [photoID]])
            try verifierEgal(try etat(id), depart)

            guard let lu, let surLeTiers else { throw Echec(description: "cadre appliqué non relu : \(JSONCoding.line(relecture["cadre_actuel"] ?? .null))") }
            try verifier(abs(Double(surLeTiers.y) - 2.0 / 3) <= Self.ecartTiers,
                         "horizon à \(Self.nombre(Double(surLeTiers.y))) de la hauteur du cadre au lieu des 2/3"
                         + (lachees.isEmpty ? "" : " (règles lâchées par read_composition : \(lachees.joined(separator: ", ")))"))
            guard droite != nil, let vu = mesure["inclinaison"]?.double else { throw Echec(description: "horizon hors du cadre appliqué") }
            try verifier(mesure["mesure"]?.string?.hasPrefix("affinée") == true,
                         "horizon non retrouvé dans le cadre appliqué : \(mesure["mesure"]?.string ?? "?")")
            let ecarts = Self.ecartsHorizonApplique(vu: vu, inclinaison: inclinaisonLue, angleCadre: lu.angle)
            try verifier(ecarts.isEmpty, ecarts.joined(separator: " ; "))
            return "horizon à \(Self.nombre(Double(surLeTiers.y))) de la hauteur, penché de \(Self.nombre(vu))° (\(mesure["mesure"]?.string ?? "")) ; "
                + "cadre \(Self.nombre(lu.angle))° ; deux recadrages annulés"
        }
    }
}
