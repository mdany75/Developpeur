import Foundation

/// Recalage des positions sur la géométrie de la photo (voir Recalage.swift) : avant une commande
/// qui place des taches, des yeux rouges ou des dégradés, le module dit quelles photos ont une
/// correction géométrique active (profil d'objectif, Upright, perspective) et son empreinte ; les
/// grilles qui manquent se calculent sur deux rendus non recadrés (commande « geometrie » avec
/// `rendre`), puis restent en mémoire tant que la géométrie ne change pas. La même grille dit où
/// Upright et la perspective laissent des coins vides : le module y ajuste le recadrage.
extension ToolHandler {
    /// Photos recalées par commande au plus : deux rendus chacune.
    static let maxRecalages = 8
    /// Grand côté des rendus du recalage : 1 pixel pour 3 d'un fichier de 6240 px.
    static let tailleRecalage = 2048

    /// Le paramètre `recalages` du module (par identifiant de photo : grille et empreinte), ou nil,
    /// et les remarques pour Claude. Ne lève pas d'erreur : sans recalage, le module avertit.
    /// `transformees` : seulement les photos où Upright, la perspective ou la distorsion manuelle
    /// sont actifs (le recadrage : le profil d'objectif seul ne laisse pas de coin vide).
    func recalages(_ cible: [String: JSONValue], transformees: Bool = false) -> (JSONValue?, [JSONValue]) {
        guard let reponse = try? lightroom.send("geometrie", cible, timeout: 30),
              let photos = reponse["photos"]?.array else { return (nil, []) }
        var grilles: [String: JSONValue] = [:]
        var notes: [JSONValue] = []
        var manquantes: [(id: Int, empreinte: String)] = []
        for info in photos {
            guard info["active"]?.bool == true, !transformees || info["transformation"]?.bool == true,
                  let id = info["photo"]?.int, let empreinte = info["empreinte"]?.string else { continue }
            if let connue = recalagesConnus["\(id)|\(empreinte)"] {
                if let grille = connue { grilles[String(id)] = Self.recalageJSON(grille, empreinte) }
            } else {
                manquantes.append((id, empreinte))
            }
        }
        if manquantes.count > Self.maxRecalages {
            notes.append(.string("Positions recalées sur les \(Self.maxRecalages) premières photos seulement : les \(manquantes.count - Self.maxRecalages) autres ont une correction géométrique et peuvent être décalées."))
            manquantes = Array(manquantes.prefix(Self.maxRecalages))
        }
        guard !manquantes.isEmpty else { return (grilles.isEmpty ? nil : .object(grilles), notes) }

        let demande: [String: JSONValue] = ["photos": .array(manquantes.map { .number(Double($0.id)) }), "rendre": true,
                                            "taille": .number(Double(Self.tailleRecalage))]
        let rendus: JSONValue
        do {
            rendus = try lightroom.send("geometrie", demande, timeout: 60 + 40 * Double(manquantes.count))
        } catch {
            notes.append(.string("Recalage de la géométrie impossible (\(error.localizedDescription)) : les positions peuvent être décalées."))
            return (grilles.isEmpty ? nil : .object(grilles), notes)
        }
        for info in rendus["photos"]?.array ?? [] {
            guard let id = info["photo"]?.int, let empreinte = info["empreinte"]?.string else { continue }
            let corrigee = (try? Self.readPreview(info["chemin_corrige"]?.string)).flatMap(PreviewImages.image)
            let origine = (try? Self.readPreview(info["chemin_origine"]?.string)).flatMap(PreviewImages.image)
            guard let corrigee, let origine else {
                notes.append(.string("Recalage de la photo \(id) impossible : rendus illisibles."))
                continue
            }
            let resultat = Recalage.calculer(corrigee: corrigee, origine: origine)
            recalagesConnus["\(id)|\(empreinte)"] = .some(resultat?.grille)
            if let resultat {
                grilles[String(id)] = Self.recalageJSON(resultat.grille, empreinte)
            } else {
                notes.append(.string("Recalage de la photo \(id) impossible : image trop uniforme pour mesurer la correction géométrique ; les positions peuvent être décalées près des bords."))
            }
        }
        return (grilles.isEmpty ? nil : .object(grilles), notes)
    }

    /// Après une retouche écrite (« appliquer ») : un recadrage demandé qui n'a pas eu de grille pour
    /// la géométrie obtenue (`a_recadrer` : la même retouche pose ou change Upright, la perspective
    /// ou la distorsion manuelle) a été resserré par Lightroom, « Contraindre le recadrage » cochée,
    /// quitte à se déplacer ; il se place maintenant au centre et à la taille demandés, sur la grille
    /// de la nouvelle géométrie (commande « recadrer »). Ses changements de cadre et ses remarques
    /// remplacent ceux de la réponse ; l'étape de la retouche est complétée, pour que undo_last
    /// défasse le tout.
    func recadrerApres(_ reponse: JSONValue, _ params: [String: JSONValue], notes: inout [JSONValue]) -> JSONValue {
        guard var objet = reponse.object, var resultats = objet["resultats"]?.array else { return reponse }
        var ids: [Int] = [], completer: [Int] = []
        for (index, resultat) in resultats.enumerated() {
            guard var r = resultat.object else { continue }
            let signale = r.removeValue(forKey: "a_recadrer")?.bool == true
            let ecrite = r.removeValue(forKey: "etape_ecrite")?.bool == true
            resultats[index] = .object(r)
            guard signale, let id = r["photo"]?["id"]?.int else { continue }
            ids.append(id)
            if ecrite { completer.append(id) }
        }
        objet["resultats"] = .array(resultats)
        guard !ids.isEmpty else { return .object(objet) }

        let photos = JSONValue.array(ids.map { .number(Double($0)) })
        let (grilles, remarques) = recalages(["photos": photos], transformees: true)
        notes += remarques
        var demande: [String: JSONValue] = ["photos": photos, "completer": .array(completer.map { .number(Double($0)) })]
        for cle in ["etape", "raison", "confirme"] { demande[cle] = params[cle] }
        if let etape = resultats.first?["etape"] { demande["etape"] = etape }
        demande["recadrage"] = params["recadrage"]
        demande["recalages"] = grilles
        let recadre: JSONValue
        do {
            recadre = try lightroom.send("recadrer", demande, timeout: 60)
        } catch {
            notes.append(.string("Recadrage demandé non placé (\(error.localizedDescription)) : Lightroom a resserré le cadre lui-même, au centre qu'il a choisi ; le vérifier avec view_photo."))
            return .object(objet)
        }
        let cadre = Set(DevelopCatalogue.cropKeys)
        for nouveau in recadre["resultats"]?.array ?? [] {
            guard let id = nouveau["photo"]?["id"]?.int,
                  let index = resultats.firstIndex(where: { $0["photo"]?["id"]?.int == id }),
                  var r = resultats[index].object else { continue }
            let changements = nouveau["changements"]?.array ?? []
            if !changements.isEmpty {
                let gardes = (r["changements"]?.array ?? []).filter { !cadre.contains($0["cle"]?.string ?? "") }
                r["changements"] = .array(gardes + changements)
            }
            r["remarques"] = .array((r["remarques"]?.array ?? []) + (nouveau["remarques"]?.array ?? []))
            resultats[index] = .object(r)
        }
        objet["resultats"] = .array(resultats)
        return .object(objet)
    }

    /// Le recadrage d'une retouche peut-il tenir compte de la géométrie actuelle ? Non si la même
    /// retouche change la géométrie (le module le signale alors après l'écriture).
    static func changeGeometrie(_ params: [String: JSONValue]) -> Bool {
        if params["preset"] != nil { return true }
        return (params["reglages"]?.object ?? [:]).keys.contains { $0.hasPrefix("Perspective") || $0.hasPrefix("Lens") }
    }

    /// Grilles pour un recadrage demandé (`recadrage` sans `retirer`) sur une géométrie qui ne
    /// change pas : le module calcule alors le cadre sans coins vides du premier coup.
    func recalagesDuRecadrage(_ params: inout [String: JSONValue], cible: [String: JSONValue]) -> [JSONValue] {
        guard let cadre = params["recadrage"], cadre["retirer"] == nil, !Self.changeGeometrie(params) else { return [] }
        let (grilles, remarques) = recalages(cible, transformees: true)
        params["recalages"] = grilles
        return remarques
    }

    static func recalageJSON(_ grille: Recalage.Grille, _ empreinte: String) -> JSONValue {
        var objet = grille.json.object ?? [:]
        objet["empreinte"] = .string(empreinte)
        return .object(objet)
    }
}
