import Foundation

/// La recherche par le sens (1.6) : find_photos avec `query` (une phrase, en anglais) ou
/// `similar_to` (une photo), classés dans l'index du catalogue ouvert (IndexSens, rempli par
/// l'analyse du Suivi), puis les autres critères appliqués par le module parmi les mieux classées.
///
/// Déroulé :
/// 1. `etat` : le chemin du catalogue ouvert (jamais rendu à Claude), d'où le dossier de son index ;
///    relu à chaque appel (un autre catalogue ouvert entre deux appels a son propre index) ;
/// 2. le vecteur de la demande : le texte par l'encodeur (MobileCLIP, ouvert au premier usage), ou
///    celui rangé de la photo `similar_to` (une copie virtuelle ou une photo hors de l'index : son
///    original, demandé au module par `chercher` avec `parmi` et `originaux`) ;
/// 3. tout l'index classé (produit scalaire), les dates filtrées ici d'après le jour de prise de vue
///    rangé (date_from, date_to : le module refuserait un filtre de date seul, ou au-delà de 5 000
///    photos), la photo de `similar_to` écartée ; pertinence relative : 0 au score médian de
///    l'index, 1 au meilleur ; sous `Sens.seuilPertinenceProvisoire`, écartée ; au plus
///    `Sens.candidatsMax` ;
/// 4. `chercher` avec `parmi` (ces originaux, dans l'ordre de pertinence), les autres critères, le
///    tri (`aucun` : la pertinence), la page : le module garde l'ordre, décrit la page et compte
///    `total` parmi elles (une photo sortie du catalogue depuis son empreinte ne compte pas).
///
/// Une copie virtuelle compte pour son original (le Suivi n'indexe que les originaux) : ses critères
/// se lisent sur l'original.
extension ToolHandler {
    func findPhotosParLeSens(_ args: Arguments, _ criteres: [String: JSONValue]) throws -> JSONValue {
        let query = args.string("query")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let similaire = args.int("similar_to")
        if args.has("query"), query?.isEmpty != false { throw LightroomError.invalid("« query » : une phrase qui dit ce que montre la photo, en anglais.") }
        if args.has("similar_to"), similaire == nil { throw LightroomError.invalid("« similar_to » : l'id d'une photo.") }
        if query != nil, similaire != nil { throw LightroomError.invalid("query ou similar_to, pas les deux.") }
        guard let sens else {
            throw LightroomError.invalid("La recherche par le sens n'est pas installée sur ce Mac (modèle MobileCLIP absent) : chercher par les autres critères.")
        }
        let chemin = try lightroom.send("etat", [:], timeout: 10)["chemin_catalogue"]?.string
        guard let chemin, let index = IndexSens(lire: IndexSens.dossier(catalogue: chemin, racine: sens.racine)), index.nombre > 0 else {
            throw LightroomError.invalid("Aucune photo indexée pour ce catalogue : l'index se remplit pendant l'analyse du Suivi (fenêtre Claude ouverte, photos vues). Chercher par les autres critères ; get_status dit où il en est.")
        }

        // 2. Le vecteur de la demande.
        var vecteur: [Float]
        var exclus: Set<Int> = []
        if let query {
            let encodeur = try ouvrirEncodeurSens(sens)
            guard encodeur.modele == index.modele, encodeur.dimension == index.dimension else {
                throw LightroomError.invalid("L'index de ce catalogue vient d'un autre modèle (\(index.modele)) : il se refait pendant l'analyse du Suivi.")
            }
            vecteur = try encodeur.vecteur(texte: query)
        } else {
            let id = similaire!
            exclus.insert(id)
            if let rangé = index.vecteur(id: id) {
                vecteur = rangé
            } else {
                let original = try lightroom.send("chercher", ["parmi": [.number(Double(id))], "originaux": true, "tri": "aucun", "limite": 1],
                                                  timeout: Self.libraryTimeout)["photos"]?.array?.first?["id"]?.int
                guard let original, let rangé = index.vecteur(id: original) else {
                    throw LightroomError.invalid("La photo \(id) n'est pas encore dans l'index de la recherche par le sens (le Suivi ne l'a pas analysée).")
                }
                exclus.insert(original)
                vecteur = rangé
            }
        }

        // 3. Le classement, les dates, la pertinence.
        let classees = index.classer(vecteur)
        guard let meilleur = classees.first(where: { !exclus.contains($0.ligne.id) })?.score else {
            return Self.resultatSens([], index: index, candidats: 0)
        }
        let mediane = classees[classees.count / 2].score
        let debut = args.string("date_from").map { String($0.prefix(10)) }
        let fin = args.string("date_to").map { String($0.prefix(10)) }
        for (nom, jour) in [("date_from", debut), ("date_to", fin)] {
            if let jour, jour.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
                throw LightroomError.invalid("« \(nom) » invalide : une date AAAA-MM-JJ est attendue.")
            }
        }
        var candidats: [(id: Int, pertinence: Double)] = []
        for (ligne, score) in classees where !exclus.contains(ligne.id) {
            if debut != nil || fin != nil {
                guard let jour = ligne.jour else { continue }
                if let debut, jour < debut { continue }
                if let fin, jour > fin { continue }
            }
            let pertinence = meilleur > mediane ? Double((score - mediane) / (meilleur - mediane)) : 1
            if pertinence < Sens.seuilPertinenceProvisoire { break }
            candidats.append((ligne.id, min(1, pertinence)))
            if candidats.count >= Sens.candidatsMax { break }
        }
        guard !candidats.isEmpty else { return Self.resultatSens([], index: index, candidats: 0) }

        // 4. Les autres critères, par le module, parmi les candidates.
        var params = criteres
        params.removeValue(forKey: "date_debut")
        params.removeValue(forKey: "date_fin")
        params["parmi"] = .array(candidats.map { .number(Double($0.id)) })
        if params["tri"] == nil { params["tri"] = "aucun" }
        var reponse = try lightroom.send("chercher", params, timeout: Self.libraryTimeout).object ?? [:]
        guard reponse["parmi"]?.bool == true else {
            throw LightroomError.invalid("Le module Lightroom installé ne connaît pas la recherche par le sens : installer la même version que le connecteur.")
        }
        reponse.removeValue(forKey: "parmi")
        let pertinences = Dictionary(candidats.map { ($0.id, $0.pertinence) }, uniquingKeysWith: { a, _ in a })
        let photos = (reponse["photos"]?.array ?? []).map { photo -> JSONValue in
            guard var objet = photo.object, let id = objet["id"]?.int, let p = pertinences[id] else { return photo }
            objet["pertinence"] = .number((p * 100).rounded() / 100)
            return .object(objet)
        }
        reponse["photos"] = .array(photos)
        let bloc = Self.resultatSens(photos, index: index, candidats: candidats.count)
        reponse["recherche_par_le_sens"] = bloc["recherche_par_le_sens"]
        return .object(reponse)
    }

    /// Le bloc `recherche_par_le_sens` (et, sans candidate, toute la réponse).
    static func resultatSens(_ photos: [JSONValue], index: IndexSens, candidats: Int) -> JSONValue {
        let bloc: JSONValue = [
            "modele": .string(index.modele), "photos_indexees": .number(Double(index.nombre)), "candidates": .number(Double(candidats)),
            "remarque": .string("Seules les photos déjà analysées par le Suivi sont dans l'index ; pertinence relative (1 = la meilleure), seuil provisoire \(Bilan.nombre(Sens.seuilPertinenceProvisoire, decimales: 1)). À vérifier à l'œil."),
        ]
        return ["total": .number(Double(photos.count)), "decalage": 0, "renvoyees": .number(Double(photos.count)), "photos": .array(photos),
                "recherche_par_le_sens": bloc]
    }

    /// L'encodeur, ouvert une fois par processus.
    func ouvrirEncodeurSens(_ sens: Suivi.IndexeurSens) throws -> EncodeurSens {
        if let encodeurSens { return encodeurSens }
        let encodeur = try sens.ouvrir()
        encodeurSens = encodeur
        return encodeur
    }

    /// Le bloc de get_status : où en est l'index du catalogue ouvert (nil sans recherche par le sens).
    func etatIndexSens(catalogue: String?) -> JSONValue? {
        guard let sens else { return nil }
        let manquants = sens.manquants()
        var bloc: [String: JSONValue] = ["modele": .string(Sens.nomModele), "installee": .bool(manquants.isEmpty)]
        if !manquants.isEmpty { bloc["manquants"] = .array(manquants.map(JSONValue.string)) }
        let index = catalogue.flatMap { IndexSens(lire: IndexSens.dossier(catalogue: $0, racine: sens.racine)) }
        bloc["photos_indexees"] = .number(Double(index?.nombre ?? 0))
        if let derniere = index?.derniere {
            let format = DateFormatter()
            format.locale = Locale(identifier: "fr_CA")
            format.dateFormat = "yyyy-MM-dd HH:mm"
            bloc["derniere_empreinte"] = .string(format.string(from: derniere))
        }
        bloc["remplie_par"] = "l'analyse du Suivi, en arrière-plan, quand Claude ne travaille pas (photos vues dans la fenêtre Claude)"
        return .object(bloc)
    }
}
