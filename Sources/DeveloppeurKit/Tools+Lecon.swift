import Foundation

/// La leçon de la photo (1.3) : en fin de retouche d'une photo, trois points, lumière, couleur et
/// composition, chacun « ce qui manquait » et « à la prise de vue ». Les défauts nommés viennent de
/// PriseDeVue, seule liste ; la leçon est rangée par le module à part du catalogue (carnet.json),
/// d'où sa place dans readOnlyTools : ni la photo ni le catalogue ne changent.
///
/// L'outil valide les trois points (Lecon.points) avant toute commande ; puis il lit le journal
/// détaillé de la photo (commande journal avec detaille : description, prise de vue, entrées), en
/// tire les corrections nettes de Claude et les indices de défauts, avec la première vue mesurée
/// de la session (vuesMesurees) ; enfin il range la leçon (commande lecon, action garder). Un
/// module qui ne connaît pas encore la commande (module 1.2 resté chargé) laisse la leçon non
/// rangée, avec une remarque : jamais une erreur d'outil. read_facts = true : les faits seuls,
/// seule la commande journal part.
extension ToolHandler {
    /// Chaque moitié d'un point (missing, at_capture) : une phrase simple.
    static let longueurPointLecon = Lecon.longueurPoint
    /// Le journal détaillé d'une photo (comme export_journal), puis le rangement de la leçon.
    static let journalLeconTimeout: TimeInterval = 60
    static let leconTimeout: TimeInterval = 30

    var lessonDefinitions: [JSONValue] {
        let parAxe = PriseDeVue.Axe.allCases.map { axe in
            "\(axe.cle) : \(PriseDeVue.cles(axe: axe).joined(separator: ", "))"
        }.joined(separator: " ; ")
        let point = objectProp("Un point de la leçon, pour un axe.", [
            "axis": enumProp(PriseDeVue.Axe.allCases.map(\.cle),
                             "L'axe : light (lumière, netteté comprise), color (couleur) ou composition ; chacun une fois."),
            "missing": prop("string", "Ce qui manquait, chiffres à l'appui (bilan de view_photo, réglages du journal), \(Self.longueurPointLecon) caractères au plus. Absent ou vide : rien ne manquait."),
            "at_capture": prop("string", "Ce qui l'aurait évité à la prise de vue ; si rien ne manquait, ce qui a marché, à refaire. \(Self.longueurPointLecon) caractères au plus."),
            "defects": ["type": "array", "items": ["type": "string", "enum": .array(PriseDeVue.defauts.map { .string($0.cle) })],
                        "description": .string("Les défauts nommés, ceux de l'axe du point, pour le carnet de progrès (\(parAxe)). Vide : aucun.")],
        ], required: ["axis", "at_capture"])
        return [
            tool("photo_lesson",
                 "Leçon de la photo, en dernier, après le résumé de sa retouche et la proposition de cadre éventuelle : trois points, lumière, couleur et composition (axis light, color, composition), une fois chacun. Pour chacun, ce qui manquait (missing), chiffres à l'appui (bilan de view_photo, journal ; composition : read_composition s'il a servi), et ce qui l'aurait évité à la prise de vue (at_capture) : exposition, heure, place, réglage du boîtier (intention_boitier s'il est donné). Un axe sans défaut : missing absent, at_capture dit ce qui a marché. Une phrase simple chacun, \(Self.longueurPointLecon) caractères au plus ; defects : les défauts nommés, pour le carnet de progrès. Une intention du boîtier suivie (nuit voulue sombre) n'est pas un défaut. Une par photo (la nouvelle remplace l'ancienne) ; pas après une proposition seule (rien d'appliqué), une notation, un classement ou une série. Photo et catalogue inchangés : la leçon est rangée à part (carnet.json). Réponse : faits (corrections nettes de Claude, première vue mesurée, prise de vue) et remarques (défaut mesuré non nommé). read_facts = true : les faits seuls, rien n'est rangé. Hors de la fenêtre Claude : la redire en trois puces.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("points", ["type": "array", "items": point, "minItems": 3, "maxItems": 3,
                                "description": "Les trois points, un par axe (light, color, composition), dans n'importe quel ordre."]),
                    ("read_facts", prop("boolean", "true = les faits seuls (corrections nettes de Claude, mesures de départ, prise de vue), sans points : rien n'est rangé.")),
                 ],
                 required: []),
        ]
    }

    func callLesson(_ name: String, _ args: Arguments) throws -> ToolResult? {
        switch name {
        case "photo_lesson": return json(try photoLesson(args))
        default: return nil
        }
    }

    /// La leçon de la photo : points validés avant tout envoi ; journal détaillé ; faits (corrections
    /// nettes, première vue mesurée, prise de vue, indices) ; leçon rangée par le module (avec
    /// points) ; remarques.
    func photoLesson(_ args: Arguments) throws -> JSONValue {
        if args.has("read_facts"), args.bool("read_facts") == nil {
            throw LightroomError.invalid("« read_facts » : true ou false. Rien n'a été rangé.")
        }
        let lireFaits = args.bool("read_facts") == true
        guard args.has("points") || lireFaits else {
            throw LightroomError.invalid("photo_lesson : donner les trois points de la leçon (points), un par axe, light, color et composition : at_capture (ce qui l'aurait évité à la prise de vue, ou ce qui a marché), missing s'il manquait quelque chose, defects (les défauts nommés) ; ou read_facts = true pour les faits seuls. Rien n'a été rangé.")
        }
        guard !(args.has("points") && lireFaits) else {
            throw LightroomError.invalid("read_facts = true donne les faits seuls, sans points ; pour ranger la leçon, points sans read_facts. Rien n'a été rangé.")
        }
        var photoDemandee: Int?
        if args.has("photo_id") {
            guard let id = args.int("photo_id") else {
                throw LightroomError.invalid("« photo_id » : l'identifiant de la photo, un entier. Rien n'a été rangé.")
            }
            photoDemandee = id
        }
        // Les points d'abord : un refus n'envoie rien.
        var points: [Lecon.Point]?
        if !lireFaits {
            guard let items = args.array("points") else {
                throw LightroomError.invalid("« points » : une liste de trois points {axis, missing, at_capture, defects}. Rien n'a été rangé.")
            }
            points = try Lecon.points(items)
        }

        // Le journal détaillé de la photo : sa description (prise de vue comprise) et ses entrées.
        var params: [String: JSONValue] = ["detaille": true]
        if let photoDemandee { params["photos"] = [.number(Double(photoDemandee))] }
        let journal = try lightroom.send("journal", params, timeout: Self.journalLeconTimeout)
        guard let premiere = journal["photos"]?.array?.first, let description = premiere["photo"],
              let id = description["id"]?.int else {
            throw LightroomError.plugin("Le module n'a pas décrit la photo (journal) : rien n'a été rangé.")
        }
        let fichier = description["fichier"]?.string ?? "photo \(id)"
        let corrections = Lecon.correctionsNettes(premiere["entrees"]?.array ?? [])
        let depart = departDeLaSession(photo: id, fichier: fichier)
        let indices = Lecon.indices(corrections: corrections, depart: depart, iso: Carnet.iso(photo: description))
        let faits = Lecon.faits(photo: description, corrections: corrections, depart: depart, indices: indices)
        let photo: JSONValue = ["id": .number(Double(id)), "fichier": .string(fichier)]
        guard let points else {
            return ["photo": photo, "faits": faits, "rangee": false]
        }

        // La leçon rangée par le module ; une erreur de ce seul envoi laisse la leçon non rangée.
        var remarques = Lecon.remarques(points: points, indices: indices)
        var lecon: [String: JSONValue] = ["photo": .number(Double(id)), "fichier": .string(fichier), "rangee": false, "remplacee": false]
        do {
            let rangement = try lightroom.send("lecon", ["action": "garder", "photo": .number(Double(id)),
                                                         "lecon": Lecon.pourLeModule(points: points, indices: indices)],
                                               timeout: Self.leconTimeout)
            lecon["rangee"] = .bool(rangement["rangee"]?.bool ?? false)
            lecon["remplacee"] = .bool(rangement["remplacee"]?.bool ?? false)
            for cle in ["mois", "prise_le", "sans_date"] {
                if let valeur = rangement[cle], !valeur.isNull { lecon[cle] = valeur }
            }
            if let remarque = rangement["remarque"]?.string, !remarque.isEmpty { remarques.append(remarque) }
        } catch {
            remarques.append(Self.remarqueLeconNonRangee(error))
        }
        var resultat: [String: JSONValue] = [
            "lecon": .object(lecon),
            "texte": .string(Lecon.texte(points: points, fichier: fichier)),
            "faits": faits,
            "remarques": .array(remarques.map(JSONValue.string)),
        ]
        // Rendu reproductible (1.3.5) : les réglages de fin de retouche gardés, comparés à ceux de la
        // retouche précédente de la même photo si celle-ci est repartie de l'origine depuis.
        if let registre = registreRendus {
            let retours = (premiere["entrees"]?.array ?? []).filter { $0["type"]?.string == "retour" }.count
            if let comparaison = try? noterLeRendu(id: id, retours: retours, registre: registre) {
                resultat["rendu_reproductible"] = comparaison
            }
        }
        return .object(resultat)
    }

    /// Le rendu de fin de retouche d'une photo (ses réglages principaux et son profil), gardé ; la
    /// comparaison avec la retouche précédente, s'il y a lieu.
    func noterLeRendu(id: Int, retours: Int, registre: RegistreRendus) throws -> JSONValue? {
        let reponse = try lightroom.send("reglages", ["photo": .number(Double(id)), "cles": .array(RegistreRendus.cles.map(JSONValue.string))],
                                         timeout: 30)
        var reglages: [String: Double] = [:]
        for cle in RegistreRendus.cles { if let valeur = reponse["reglages"]?[cle]?.double { reglages[cle] = valeur } }
        return try registre.noter(RegistreRendus.Rendu(photo: id, le: Date(), reglages: reglages, profil: reponse["profil"]?.string, retours: retours))
    }

    /// Le départ de la leçon : la plus ancienne vue mesurée de la session pour cette photo, toutes
    /// tailles d'aperçu confondues, du même fichier (un autre fichier sous le même identifiant est
    /// une autre photo, d'un autre catalogue). Nil sans view_photo de cette photo dans ce processus.
    func departDeLaSession(photo: Int, fichier: String) -> Bilan.Vue? {
        vuesMesurees.filter { $0.key.photo == photo && $0.value.depart.fichier == fichier }
            .map(\.value.depart)
            .min { $0.quand < $1.quand }
    }

    /// La leçon n'a pas été rangée (la réponse et ses faits restent) : un module d'avant la 1.3,
    /// sans la commande, demande de relancer Lightroom ; sinon, la raison.
    static func remarqueLeconNonRangee(_ erreur: Error) -> String {
        let message = erreur.localizedDescription
        if message.contains("Commande inconnue") {
            return "Leçon non rangée : le module de Lightroom chargé ne connaît pas encore la commande lecon (module d'avant la 1.3). Quitter puis relancer Lightroom après l'installation ; la leçon de cette réponse reste valable."
        }
        return "Leçon non rangée dans le carnet (carnet.json) : \(message)"
    }
}
