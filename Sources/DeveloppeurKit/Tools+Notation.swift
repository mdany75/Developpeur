import Foundation

/// Noter selon le standard de notation (`Notation.standard`) : `propose_ratings` range des notes
/// proposées dans le registre du module (commande notation), hors du catalogue, pour la carte Note
/// de la fenêtre Claude, où elles arrivent « à vérifier » : l'utilisateur les accepte ou les change
/// (la Séance de notation est retirée depuis la 1.1.1). Avec apply (l'utilisateur a demandé que
/// Claude note), le module les pose aussi dans le catalogue, comme Accepter (demandé par Dany le
/// 20 octobre 2026). Claude ne propose jamais 5 étoiles : l'utilisateur les pose, ou les demande
/// (set_metadata).
extension ToolHandler {
    /// Propositions d'un appel au plus : une séance triée d'un coup (cull_photos).
    static let maxRatings = maxCulledPhotos
    /// Clés d'une proposition. Une clé inconnue est refusée à la main : parametresInconnus ne voit
    /// que le premier niveau des arguments (le piège photo_id et photo_ids s'y rejouerait).
    static let ratingKeys = ["photo_id", "rating", "flag", "criteria", "reason", "to_check"]
    static let ratingKeysProches = ["photo": "photo_id", "photo_ids": "photo_id", "id": "photo_id", "note": "rating", "stars": "rating",
                                    "drapeau": "flag", "criteres": "criteria", "raison": "reason", "a_verifier": "to_check"]
    static let criteriaProches = ["qualites": "qualities", "quality": "qualities", "plancher": "technical_floor",
                                  "technical": "technical_floor", "finition": "finish"]
    /// Une seule commande, courte : le module décrit les photos et range les propositions.
    static let notationTimeout: TimeInterval = 60

    var notationDefinitions: [JSONValue] {
        let criteres: [String: JSONValue] = [
            "impact": prop("string", "Impact : la photo arrête l'œil, dit quelque chose, n'a pas l'air déjà vue (le plus lourd ; aucune mesure ne le voit)."),
            "qualities": prop("string", "Qualités de l'image : lumière, sujet clair, composition, moment ou expression, couleur."),
            "technical_floor": prop("string", "Plancher technique : netteté, exposition, yeux, bruit (cull_photos), et le plafond qu'il donne."),
            "finish": prop("string", "Finition, pour une photo développée : halos aux bords des masques, peau, saturation (facultatif)."),
        ]
        let proposition = objectProp("Une proposition, pour une photo.", [
            "photo_id": prop("integer", "Identifiant de la photo (champ « id » de cull_photos, contact_sheet ou list_selection)."),
            "rating": prop("integer", "Note proposée, de 0 à \(Notation.noteMaximale) (5 : l'utilisateur seul)."),
            "flag": enumProp(["reject"], "reject = rejet (défaut majeur, involontaire, confirmé à l'œil), à la place de rating."),
            "criteria": objectProp("La raison critère par critère, \(Notation.longueurCritere) caractères au plus chacun.", criteres,
                                   required: Notation.criteres.filter(\.obligatoire).map(\.nom)),
            "reason": prop("string", "La raison en une phrase (\(Notation.longueurRaison) caractères au plus), montrée à l'utilisateur."),
            "to_check": prop("boolean", "true = cas douteux (groupe, nuit, flou peut-être voulu ; défaut voulu au-dessus du plafond). Toute proposition arrive de toute façon « à vérifier » dans la carte Note."),
        ], required: ["photo_id", "criteria", "reason"])
        return [
            tool("propose_ratings",
                 "Note des photos selon le standard de notation (read_standard = true le donne ; le lire avant de noter), pour la carte Note de la fenêtre Claude dans Lightroom : de 0 à \(Notation.noteMaximale) étoiles, ou flag reject, avec une raison par critère (impact, qualities, technical_floor ; finish pour une photo développée) et une phrase (reason). Sans apply, les notes sont rangées comme propositions « à vérifier », sans rien changer dans le catalogue : l'utilisateur les accepte ou les change dans Lightroom. apply = true quand l'utilisateur demande que tu notes ou que tu poses les notes (« note ces photos », « pose les notes ») : chaque note est aussi posée dans Lightroom, « à vérifier » comprises (une étape « Claude · notation » par photo, que undo_last défait). Jamais 5 étoiles ici : si l'utilisateur en demande, set_metadata. Regarder les photos d'abord (contact_sheet ; view_photo à 100 % pour un 4). Une note au-dessus du plafond mesuré par le dernier cull_photos est refusée, sauf un défaut voulu et maîtrisé, dit dans technical_floor, avec to_check = true. Une proposition pour une photo remplace la précédente.",
                 properties: [
                    ("ratings", ["type": "array", "items": proposition,
                                 "description": .string("Les propositions, une par photo (\(Self.maxRatings) au plus par appel).")]),
                    ("pass", prop("integer", "Passe du standard : 1 rejeter ou non, 2 trois étoiles ou non, 3 monter à quatre parmi les trois (la passe 4, cinq étoiles, est à l'utilisateur seul : rien à proposer).")),
                    ("read_standard", prop("boolean", "true = renvoyer le standard de notation (seul : rien n'est rangé ; avec ratings, en plus des propositions).")),
                    ("apply", prop("boolean", "true = l'utilisateur a demandé que tu notes ou que tu poses les notes : elles sont aussi posées dans le catalogue (réponse : posees). false ou absent : rangées comme propositions seulement.")),
                 ],
                 required: []),
        ]
    }

    func callNotation(_ name: String, _ args: Arguments) throws -> ToolResult? {
        switch name {
        case "propose_ratings": return json(try proposeRatings(args))
        default: return nil
        }
    }

    /// Valide toutes les propositions avant d'envoyer quoi que ce soit (un refus ne range rien),
    /// puis une seule commande notation au module ; sa réponse est rendue telle quelle.
    func proposeRatings(_ args: Arguments) throws -> JSONValue {
        let lireStandard = args.bool("read_standard") == true
        var liste: [JSONValue] = []
        if args.has("ratings") {
            guard let items = args.array("ratings") else {
                throw LightroomError.invalid("« ratings » doit être une liste de propositions : {photo_id, rating ou flag, criteria, reason, to_check}.")
            }
            liste = items
        }
        guard !liste.isEmpty else {
            guard lireStandard else {
                throw LightroomError.invalid("« ratings » : une proposition par photo (photo_id, rating de 0 à \(Notation.noteMaximale) ou flag reject, criteria, reason) ; read_standard = true donne le standard de notation.")
            }
            return ["standard": .string(Notation.standard)]
        }
        guard liste.count <= Self.maxRatings else {
            throw LightroomError.invalid("Au plus \(Self.maxRatings) propositions par appel (\(liste.count) données). Rien n'a été rangé.")
        }
        var params: [String: JSONValue] = ["action": "proposer"]
        if args.has("apply") {
            guard let poser = args.bool("apply") else { throw LightroomError.invalid("« apply » : true ou false. Rien n'a été rangé.") }
            if poser { params["poser"] = true }
        }
        if args.has("pass") {
            guard let passe = args.int("pass"), (1...Notation.passes).contains(passe) else {
                throw LightroomError.invalid("« pass » : la passe du standard, de 1 à \(Notation.passes - 1) (la passe \(Notation.passes), 5 étoiles, est à l'utilisateur seul). Rien n'a été rangé.")
            }
            guard passe < Notation.passes else {
                throw LightroomError.invalid("Passe \(Notation.passes) : 5 étoiles, l'utilisateur seul ; rien à proposer. Rien n'a été rangé.")
            }
            params["passe"] = .number(Double(passe))
        }
        var propositions: [JSONValue] = [], erreurs: [String] = [], vues: Set<Int> = []
        for (index, item) in liste.enumerated() {
            do {
                let (photo, proposition) = try Self.proposition(item, plafonds: dernierTri)
                guard vues.insert(photo).inserted else { throw LightroomError.invalid("photo \(photo) proposée deux fois.") }
                propositions.append(proposition)
            } catch let erreur as LightroomError {
                erreurs.append("ratings[\(index)] : \(erreur.localizedDescription)")
            }
        }
        guard erreurs.isEmpty else {
            let reste = erreurs.count > 10 ? "\n… et \(erreurs.count - 10) autre(s)." : ""
            throw LightroomError.invalid("Rien n'a été rangé :\n" + erreurs.prefix(10).joined(separator: "\n") + reste)
        }
        params["propositions"] = .array(propositions)
        var reponse = try lightroom.send("notation", params, timeout: Self.notationTimeout).object ?? [:]
        if lireStandard { reponse["standard"] = .string(Notation.standard) }
        return .object(reponse)
    }

    /// Une proposition validée, telle que le module l'attend : photo, note (0 pour un rejet),
    /// drapeau (« aucun » ou « rejetee »), critères, plafond connu, raison, à vérifier.
    static func proposition(_ item: JSONValue, plafonds: [Int: Notation.Plafond]) throws -> (Int, JSONValue) {
        guard let objet = item.object else {
            throw LightroomError.invalid("une proposition est un objet {photo_id, rating ou flag, criteria, reason, to_check}.")
        }
        let inconnues = objet.keys.filter { !ratingKeys.contains($0) }.sorted()
        guard inconnues.isEmpty else {
            throw LightroomError.invalid("clé(s) inconnue(s) : \(nommer(inconnues, ratingKeysProches)). Clés acceptées : \(ratingKeys.joined(separator: ", ")).")
        }
        let p = Arguments(raw: objet)
        guard let photo = p.int("photo_id") else { throw LightroomError.invalid("« photo_id » : l'identifiant de la photo, un entier.") }

        var note: Int?
        if p.has("rating") {
            guard let valeur = p.int("rating") else { throw LightroomError.invalid("« rating » doit être un nombre entier, de 0 à \(Notation.noteMaximale).") }
            guard valeur <= Notation.noteMaximale else { throw LightroomError.invalid("Claude ne propose jamais 5 étoiles : c'est à l'utilisateur.") }
            guard valeur >= 0 else { throw LightroomError.invalid("« rating » va de 0 à \(Notation.noteMaximale).") }
            note = valeur
        }
        var rejet = false
        if p.has("flag") {
            guard p.string("flag") == "reject" else { throw LightroomError.invalid("« flag » : seulement reject (le rejet) ; une note se donne par rating.") }
            rejet = true
        }
        if note != nil, rejet { throw LightroomError.invalid("rating ou flag reject, pas les deux.") }
        if note == nil, !rejet { throw LightroomError.invalid("rating (de 0 à \(Notation.noteMaximale)) ou flag reject.") }

        guard let criteres = p.object("criteria") else {
            throw LightroomError.invalid("« criteria » : {impact, qualities, technical_floor, finish}, une raison par critère.")
        }
        let inconnus = criteres.keys.filter { cle in !Notation.criteres.contains { $0.nom == cle } }.sorted()
        guard inconnus.isEmpty else {
            throw LightroomError.invalid("criteria : clé(s) inconnue(s) : \(nommer(inconnus, criteriaProches)). Clés acceptées : \(Notation.criteres.map(\.nom).joined(separator: ", ")).")
        }
        var versModule: [String: JSONValue] = [:]
        for critere in Notation.criteres {
            let valeur = criteres[critere.nom] ?? .null
            guard valeur.isNull || valeur.string != nil else { throw LightroomError.invalid("« criteria.\(critere.nom) » doit être un texte.") }
            let texte = valeur.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if texte.isEmpty {
                guard !critere.obligatoire else {
                    throw LightroomError.invalid("« criteria.\(critere.nom) » vide : une raison pour chacun de \(Notation.criteres.filter(\.obligatoire).map(\.nom).joined(separator: ", ")).")
                }
                continue
            }
            guard texte.count <= Notation.toleranceCritere else {
                throw LightroomError.invalid("« criteria.\(critere.nom) » trop long (\(texte.count) caractères, \(Notation.longueurCritere) demandés).")
            }
            versModule[critere.module] = .string(texte)
        }

        let raison = p.string("reason")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raison.isEmpty else { throw LightroomError.invalid("« reason » : la raison en une phrase.") }
        guard raison.count <= Notation.toleranceRaison else {
            throw LightroomError.invalid("« reason » trop longue (\(raison.count) caractères, \(Notation.longueurRaison) demandés).")
        }
        var aVerifier = false
        if p.has("to_check") {
            guard let valeur = p.bool("to_check") else { throw LightroomError.invalid("« to_check » : true ou false.") }
            aVerifier = valeur
        }

        // Le plafond mesuré borne la note ; un refus plutôt qu'un plafonnement sans le dire. Un
        // défaut voulu et maîtrisé ne compte pas (standard) : la note passe, à vérifier.
        let plafond = plafonds[photo]
        if let note, let plafond, note > plafond.note, !aVerifier {
            throw LightroomError.invalid("photo \(photo) : \(note) étoile(s), au-dessus du plafond mesuré par cull_photos (\(plafond.note) : \(plafond.raison)). Proposer au plus \(plafond.note) ; un défaut voulu et maîtrisé se dit dans technical_floor, avec to_check = true ; une photo retouchée depuis le tri : relancer cull_photos.")
        }
        var proposition: [String: JSONValue] = [
            "photo": .number(Double(photo)), "note": .number(Double(note ?? 0)), "drapeau": .string(rejet ? "rejetee" : "aucun"),
            "criteres": .object(versModule), "raison": .string(raison), "a_verifier": .bool(aVerifier),
        ]
        if let plafond { proposition["plafond"] = .number(Double(plafond.note)) }
        return (photo, .object(proposition))
    }

    /// Les clés inconnues, chacune avec la bonne quand elle s'en rapproche.
    static func nommer(_ cles: [String], _ proches: [String: String]) -> String {
        cles.map { cle in proches[cle].map { "\(cle) (ici : « \($0) »)" } ?? cle }.joined(separator: ", ")
    }
}
