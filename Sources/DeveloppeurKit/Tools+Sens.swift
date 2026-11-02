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
///    `Sens.candidatsMax` ; une phrase dont la meilleure photo (dans les dates) a un score brut sous
///    `Sens.plancherScoreBrutProvisoire` ne rend rien (« Rien ne ressemble vraiment… ») ;
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
            return Self.resultatSens([], index: index, candidats: 0, query: query)
        }
        let mediane = classees[classees.count / 2].score
        let debut = args.string("date_from").map { String($0.prefix(10)) }
        let fin = args.string("date_to").map { String($0.prefix(10)) }
        for (nom, jour) in [("date_from", debut), ("date_to", fin)] {
            if let jour, jour.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
                throw LightroomError.invalid("« \(nom) » invalide : une date AAAA-MM-JJ est attendue.")
            }
        }
        var candidats: [(id: Int, pertinence: Double, score: Float)] = []
        var meilleurScoreBrut: Float?
        for (ligne, score) in classees where !exclus.contains(ligne.id) {
            if debut != nil || fin != nil {
                guard let jour = ligne.jour else { continue }
                if let debut, jour < debut { continue }
                if let fin, jour > fin { continue }
            }
            // Le plancher : une phrase dont la meilleure photo (dans les dates) ressemble trop peu ne
            // rend rien, même si la pertinence relative la ferait passer.
            if meilleurScoreBrut == nil {
                meilleurScoreBrut = score
                if query != nil, score < Sens.plancherScoreBrutProvisoire { break }
            }
            let pertinence = meilleur > mediane ? Double((score - mediane) / (meilleur - mediane)) : 1
            if pertinence < Sens.seuilPertinenceProvisoire { break }
            candidats.append((ligne.id, min(1, pertinence), score))
        }
        guard !candidats.isEmpty else {
            return Self.resultatSens([], index: index, candidats: 0, query: query, meilleurScoreBrut: meilleurScoreBrut)
        }

        // 4. Les autres critères, par le module, parmi les candidates, par tranches de
        //    `trancheSens` (5 000, MAX_TRI du module) dans l'ordre de pertinence, jusqu'à remplir la
        //    page : une collection, un mot-clé ou une note qui ne gardent que des photos classées loin
        //    ne rendent pas une liste vide. Au plus `Sens.tranchesMax` tranches ; au-delà, la liste
        //    est dite coupée.
        var params = criteres
        params.removeValue(forKey: "date_debut")
        params.removeValue(forKey: "date_fin")
        if params["tri"] == nil { params["tri"] = "aucun" }
        let limite = params["limite"]?.int ?? Self.defaultSearchLimit
        let decalage = params["decalage"]?.int ?? 0
        let tranche = max(1, trancheSens)
        var page: [JSONValue] = []
        var trouvees = 0, lues = 0, tranchesLues = 0
        var reponse: [String: JSONValue] = [:]
        var remarques: [JSONValue] = []
        while lues < candidats.count, tranchesLues < Sens.tranchesMax, trouvees < decalage + limite {
            let ids = candidats[lues..<min(candidats.count, lues + tranche)].map { JSONValue.number(Double($0.id)) }
            params["parmi"] = .array(ids)
            params["decalage"] = .number(Double(max(0, decalage - trouvees)))
            params["limite"] = .number(Double(max(1, limite - page.count)))
            let morceau = try lightroom.send("chercher", params, timeout: Self.libraryTimeout).object ?? [:]
            guard morceau["parmi"]?.bool == true else {
                throw LightroomError.invalid("Le module Lightroom installé ne connaît pas la recherche par le sens : installer la même version que le connecteur.")
            }
            if reponse.isEmpty { reponse = morceau }
            for remarque in morceau["remarques"]?.array ?? [] where !remarques.contains(remarque) { remarques.append(remarque) }
            page += (morceau["photos"]?.array ?? []).prefix(limite - page.count)
            trouvees += morceau["total"]?.int ?? 0
            lues += ids.count
            tranchesLues += 1
        }
        reponse.removeValue(forKey: "parmi")
        reponse["total"] = .number(Double(trouvees))
        reponse["decalage"] = .number(Double(decalage))
        reponse["renvoyees"] = .number(Double(page.count))
        reponse["photos"] = .array(page)
        if lues < candidats.count {
            if trouvees >= decalage + limite {
                remarques.append(.string("Total d'au moins \(trouvees) : les candidates suivantes (\(candidats.count - lues), moins pertinentes) ne sont pas encore lues ; la page suivante (offset) les lit."))
            } else {
                remarques.append(.string("Liste coupée : seules les \(lues) candidates les plus pertinentes sur \(candidats.count) ont passé les autres critères ; une phrase plus précise, ou une date, resserre la recherche."))
            }
        }
        if tranchesLues > 1, params["tri"]?.string != "aucun" {
            remarques.append(.string("Tri appliqué par tranches de \(tranche) candidates, de la plus pertinente à la moins pertinente."))
        }
        reponse["remarques"] = .array(remarques)
        let photos = page
        let pertinences = Dictionary(candidats.map { ($0.id, ($0.pertinence, $0.score)) }, uniquingKeysWith: { a, _ in a })
        let marquees = photos.map { photo -> JSONValue in
            guard var objet = photo.object, let id = objet["id"]?.int, let (p, score) = pertinences[id] else { return photo }
            objet["pertinence"] = .number((p * 100).rounded() / 100)
            // Le score brut (cosinus), pour le prochain relevé du plancher et du seuil.
            objet["score_brut"] = .number((Double(score) * 1000).rounded() / 1000)
            return .object(objet)
        }
        reponse["photos"] = .array(marquees)
        let bloc = Self.resultatSens(marquees, index: index, candidats: candidats.count, meilleurScoreBrut: meilleurScoreBrut)
        reponse["recherche_par_le_sens"] = bloc["recherche_par_le_sens"]
        return .object(reponse)
    }

    /// Le bloc `recherche_par_le_sens` (et, sans candidate, toute la réponse : avec une phrase dont la
    /// meilleure photo reste sous le plancher, « Rien ne ressemble vraiment… » dans `remarques`).
    static func resultatSens(_ photos: [JSONValue], index: IndexSens, candidats: Int, query: String? = nil, meilleurScoreBrut: Float? = nil) -> JSONValue {
        var bloc: [String: JSONValue] = [
            "modele": .string(index.modele), "photos_indexees": .number(Double(index.nombre)), "candidates": .number(Double(candidats)),
            "remarque": .string("Seules les photos déjà analysées par le Suivi sont dans l'index ; pertinence relative (1 = la meilleure), seuil provisoire \(Bilan.nombre(Sens.seuilPertinenceProvisoire, decimales: 1)) ; score_brut : le cosinus, plancher provisoire \(Bilan.nombre(Double(Sens.plancherScoreBrutProvisoire), decimales: 2)). À vérifier à l'œil."),
        ]
        var remarques: [JSONValue] = []
        if let meilleurScoreBrut {
            bloc["meilleur_score_brut"] = .number((Double(meilleurScoreBrut) * 1000).rounded() / 1000)
            if let query, photos.isEmpty, meilleurScoreBrut < Sens.plancherScoreBrutProvisoire {
                remarques.append(.string("Rien ne ressemble vraiment à « \(query) » parmi les \(index.nombre) photos indexées (meilleur score brut \(Bilan.nombre(Double(meilleurScoreBrut), decimales: 2)), sous le plancher provisoire \(Bilan.nombre(Double(Sens.plancherScoreBrutProvisoire), decimales: 2))) : aucune photo rendue. Le dire tel quel ; une autre phrase, ou les autres critères, peuvent chercher autrement."))
            }
        }
        var reponse: [String: JSONValue] = ["total": .number(Double(photos.count)), "decalage": 0, "renvoyees": .number(Double(photos.count)), "photos": .array(photos),
                                            "recherche_par_le_sens": .object(bloc)]
        if !remarques.isEmpty { reponse["remarques"] = .array(remarques) }
        return .object(reponse)
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
