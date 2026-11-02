import CoreGraphics
import Foundation

/// Les espèces (1.6.3, Especes.swift) : find_photos avec `species` (une espèce de la liste, par son
/// nom français ou scientifique, ou un groupe : « oiseau », « fleur »…) et view_photo avec `species`
/// (l'espèce la plus probable de la photo). Tout se calcule sur ce Mac.
///
/// Déroulé de find_photos avec `species` :
/// 1. la demande résolue dans la liste (une espèce d'abord, sinon un groupe ; inconnue : refus avec
///    des noms proches) ;
/// 2. les candidates : avec l'index de la recherche par le sens (MobileCLIP), les photos les plus
///    proches de la phrase du groupe (« a photo of a bird »), dates filtrées d'après l'index, passées
///    au module (`parmi`) avec les autres critères ; sans index, les photos des autres critères, qui
///    sont alors exigés ; au plus `Especes.candidatsMax` ;
/// 3. leurs vignettes (`vignettes`, `Especes.tailleVignette`), classées une à une par BioCLIP 2 ;
/// 4. gardées si la porte (MobileCLIP : animal ou plante ?) les laisse passer et si l'espèce cherchée passe `seuilRechercheProvisoire` (un groupe : la somme de ses
///    espèces passe `seuilGroupeProvisoire`), de la plus probable à la moins ; chaque photo reçoit
///    `espece` (la plus probable, avec sa confiance) et `score` ; la page se coupe ici.
/// Aucun mot-clé n'est posé : un mot-clé d'espèce passe par set_metadata, après l'accord de
/// l'utilisateur.
extension ToolHandler {
    /// Le moteur des espèces de ToolHandler : ce qui manque (get_status) et l'ouverture du classeur.
    public struct MoteurEspeces {
        public var manquants: () -> [String]
        public var ouvrir: () throws -> ClasseurEspeces
        public init(manquants: @escaping () -> [String] = { [] }, ouvrir: @escaping () throws -> ClasseurEspeces) {
            self.manquants = manquants
            self.ouvrir = ouvrir
        }
    }

    static let refusEspecesAbsentes = "La reconnaissance des espèces n'est pas installée sur ce Mac (modèle BioCLIP 2 absent : scripts/preparer-bioclip.sh) : chercher par les autres critères (query, keyword)."

    /// Le classeur, ouvert une fois par processus (vecteurs de la liste relus ou calculés).
    func ouvrirClasseurEspeces(_ moteur: MoteurEspeces) throws -> ClasseurEspeces {
        if let classeurEspeces { return classeurEspeces }
        let classeur = try moteur.ouvrir()
        classeurEspeces = classeur
        return classeur
    }

    func findPhotosParEspece(_ args: Arguments, _ criteres: [String: JSONValue]) throws -> JSONValue {
        guard let demande = args.string("species")?.trimmingCharacters(in: .whitespacesAndNewlines), !demande.isEmpty else {
            throw LightroomError.invalid("« species » : un nom d'espèce (français ou latin) ou un groupe (oiseau, mammifère, papillon, fleur, arbre, champignon…).")
        }
        if args.has("query") || args.has("similar_to") { throw LightroomError.invalid("species ne va pas avec query ni similar_to.") }
        guard let especes else { throw LightroomError.invalid(Self.refusEspecesAbsentes) }
        let classeur = try ouvrirClasseurEspeces(especes)
        let liste = classeur.liste
        guard let cible = liste.resoudre(demande) else {
            let proches = liste.suggestions(demande)
            throw LightroomError.invalid("« \(demande) » n'est ni dans la liste des espèces (\(liste.especes.count) noms, français ou latins) ni un groupe (\(Especes.groupes.map(\.nom).joined(separator: ", ")))."
                + (proches.isEmpty ? " Chercher plutôt par le sens (query, en anglais)." : " Proches : \(proches.joined(separator: " ; "))."))
        }
        let groupe: Especes.Groupe
        let indicesCherches: [Int]
        let seuil: Double
        let cherche: JSONValue
        switch cible {
        case .espece(let i):
            let e = liste.especes[i]
            groupe = Especes.groupe(nom: e.groupe) ?? Especes.groupes[0]
            indicesCherches = [i]
            seuil = Especes.seuilRechercheProvisoire
            cherche = ["espece": .string(e.nom), "latin": .string(e.latin)]
        case .groupe(let g):
            groupe = g
            indicesCherches = liste.indices(g)
            seuil = Especes.seuilGroupeProvisoire
            cherche = ["groupe": .string(g.nom), "especes_de_la_liste": .number(Double(indicesCherches.count))]
        }

        // 2. Les candidates.
        var params = criteres
        let limite = params["limite"]?.int ?? Self.defaultSearchLimit
        let decalage = params["decalage"]?.int ?? 0
        params["limite"] = .number(Double(Especes.candidatsMax))
        params["decalage"] = 0
        var remarques: [JSONValue] = []
        var parIndex = false
        if let sens, let index = try indexSensOuvert(sens), let encodeur = try? ouvrirEncodeurSens(sens),
           encodeur.modele == index.modele, encodeur.dimension == index.dimension {
            let debut = args.string("date_from").map { String($0.prefix(10)) }
            let fin = args.string("date_to").map { String($0.prefix(10)) }
            var ids: [JSONValue] = []
            for (ligne, _) in index.classer(try encodeur.vecteur(texte: groupe.phrase)) {
                if debut != nil || fin != nil {
                    guard let jour = ligne.jour else { continue }
                    if let debut, jour < debut { continue }
                    if let fin, jour > fin { continue }
                }
                ids.append(.number(Double(ligne.id)))
                if ids.count >= Especes.candidatsSens { break }
            }
            params.removeValue(forKey: "date_debut")
            params.removeValue(forKey: "date_fin")
            params["parmi"] = .array(ids)
            if params["tri"] == nil { params["tri"] = "aucun" }
            parIndex = true
        } else {
            let autres = params.keys.filter { !["limite", "decalage", "tri", "mots_cles_details"].contains($0) }
            guard !autres.isEmpty else {
                throw LightroomError.invalid("Sans l'index de la recherche par le sens, « species » demande un autre critère (collection, dossier, dates, mot-clé…) : au plus \(Especes.candidatsMax) photos sont examinées.")
            }
            remarques.append("Sans l'index de la recherche par le sens : seules les photos des autres critères sont examinées.")
        }
        let reponse = try lightroom.send("chercher", params, timeout: Self.libraryTimeout).object ?? [:]
        if parIndex, reponse["parmi"]?.bool != true {
            throw LightroomError.invalid("Le module Lightroom installé ne connaît pas la recherche par le sens : installer la même version que le connecteur.")
        }
        let candidates = (reponse["photos"]?.array ?? []).filter { $0["video"]?.bool != true }
        let totalCandidates = reponse["total"]?.int ?? candidates.count
        if totalCandidates > candidates.count {
            remarques.append(.string(parIndex
                ? "Seules les \(candidates.count) photos les plus proches de « \(groupe.nom) » (recherche par le sens) ont été examinées : une date, un dossier ou une collection resserre la recherche."
                : "Seules les \(candidates.count) premières photos sur \(totalCandidates) ont été examinées : une date, un dossier ou une collection resserre la recherche."))
        }

        // 3. Les vignettes, classées une à une.
        var resultats: [Int: ClasseurEspeces.Resultat] = [:]
        var illisibles = 0
        let ids = candidates.compactMap { $0["id"]?.int }
        for debutLot in stride(from: 0, to: ids.count, by: 50) {
            let lot = Array(ids[debutLot..<min(debutLot + 50, ids.count)])
            let vignettes = try lightroom.send("vignettes", ["photos": .array(lot.map { .number(Double($0)) }), "taille": .number(Double(Especes.tailleVignette))],
                                               timeout: 120)
            for item in vignettes["photos"]?.array ?? [] {
                guard let id = item["id"]?.int else { continue }
                guard let data = try? Self.readPreview(item["vignette"]?.string), let image = PreviewImages.image(data),
                      let resultat = try? classeur.classer(image: image) else { illisibles += 1; continue }
                resultats[id] = resultat
            }
        }

        // 4. Les photos gardées, de la plus probable à la moins.
        var gardees: [(photo: JSONValue, score: Double)] = []
        for photo in candidates {
            // Ni animal ni plante d'après la porte (MobileCLIP) : écartée, quel que soit le score.
            guard let id = photo["id"]?.int, let resultat = resultats[id], resultat.vivant else { continue }
            let score = resultat.somme(indicesCherches)
            guard score >= seuil, var objet = photo.object else { continue }
            objet["espece"] = classeur.json(resultat)
            objet["score"] = .number((score * 100).rounded() / 100)
            gardees.append((.object(objet), score))
        }
        gardees.sort { $0.score > $1.score }
        let page = gardees.dropFirst(decalage).prefix(limite).map(\.photo)
        if illisibles > 0 { remarques.append(.string("\(illisibles) vignette(s) illisible(s), non examinée(s).")) }
        var resultat = reponse
        resultat.removeValue(forKey: "parmi")
        resultat["total"] = .number(Double(gardees.count))
        resultat["decalage"] = .number(Double(decalage))
        resultat["renvoyees"] = .number(Double(page.count))
        resultat["photos"] = .array(Array(page))
        resultat["remarques"] = .array((reponse["remarques"]?.array ?? []) + remarques)
        resultat["especes"] = [
            "modele": .string(Especes.nomModele), "cherche": cherche, "examinees": .number(Double(resultats.count)),
            "seuil_provisoire": .number(seuil),
            "remarque": "score : la probabilité de l'espèce (ou du groupe) d'après BioCLIP 2, sur ce Mac ; seuil provisoire, à vérifier à l'œil. Un mot-clé d'espèce ne s'écrit qu'avec l'accord de l'utilisateur (set_metadata).",
        ]
        return .object(resultat)
    }

    /// L'index du sens du catalogue ouvert, s'il a des photos (nil sinon).
    func indexSensOuvert(_ sens: Suivi.IndexeurSens) throws -> IndexSens? {
        guard let chemin = try lightroom.send("etat", [:], timeout: 10)["chemin_catalogue"]?.string,
              let index = IndexSens(lire: IndexSens.dossier(catalogue: chemin, racine: sens.racine)), index.nombre > 0 else { return nil }
        return index
    }

    /// L'espèce d'une image de view_photo (`species`) : le bloc `espece`, ou pourquoi il manque.
    func especeDeLImage(_ image: CGImage?) -> JSONValue {
        guard let especes else { return ["trouvee": false, "remarque": .string(Self.refusEspecesAbsentes)] }
        guard let image else { return ["trouvee": false, "remarque": "aperçu illisible"] }
        do {
            let classeur = try ouvrirClasseurEspeces(especes)
            var bloc = classeur.json(try classeur.classer(image: image)).object ?? [:]
            bloc["modele"] = .string(Especes.nomModele)
            if bloc["trouvee"]?.bool == true {
                bloc["remarque"] = .string("Seuil provisoire \(Bilan.nombre(Especes.seuilConfianceProvisoire, decimales: 2)), à vérifier à l'œil ; le nom en mot-clé seulement après l'accord de l'utilisateur.")
            }
            return .object(bloc)
        } catch {
            return ["trouvee": false, "remarque": .string("Espèce non lue : \(error.localizedDescription)")]
        }
    }

    /// Le bloc de get_status : les espèces installées ou ce qui manque (nil sans moteur).
    func etatEspeces() -> JSONValue? {
        guard let especes else { return nil }
        let manquants = especes.manquants()
        var bloc: [String: JSONValue] = ["modele": .string(Especes.nomModele), "installee": .bool(manquants.isEmpty)]
        if !manquants.isEmpty { bloc["manquants"] = .array(manquants.map(JSONValue.string)) }
        if let classeurEspeces { bloc["especes_de_la_liste"] = .number(Double(classeurEspeces.liste.especes.count)) }
        return .object(bloc)
    }
}
