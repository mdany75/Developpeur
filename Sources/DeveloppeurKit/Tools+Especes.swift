import CoreGraphics
import Foundation

/// Les espèces (1.6.3, Especes.swift) : find_photos avec `species` (une espèce de la liste, par son
/// nom français ou scientifique, ou un groupe : « oiseau », « fleur »…) et view_photo avec `species`
/// (l'espèce la plus probable de la photo). Tout se calcule sur ce Mac.
///
/// Déroulé de find_photos avec `species` :
/// 1. la demande résolue dans la liste (une espèce d'abord, sinon un groupe ; inconnue : refus avec
///    des noms proches) ;
/// 2. les candidates, au plus `Especes.candidatsMax` : les photos des autres critères s'ils en
///    gardent assez peu (toutes examinées, analysées par le Suivi ou non) ; sinon, avec l'index de la
///    recherche par le sens (MobileCLIP), les photos indexées classées par les phrases du groupe
///    (« a photo of a bird »), dates filtrées d'après l'index, passées au module (`parmi`) par
///    tranches avec les autres critères, et la réponse dit que les photos pas encore analysées ne
///    sont pas examinées ; sans index, les autres critères sont exigés ;
/// 3. leurs vignettes (`vignettes`, `Especes.tailleVignette`), classées une à une par BioCLIP 2 ;
/// 4. gardées si la porte (MobileCLIP : animal ou plante ? ; absente, la réponse le dit) les laisse passer et si l'espèce cherchée passe `seuilRechercheProvisoire` (un groupe : la somme de ses
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

    /// Sans MobileCLIP, pas de porte « animal ou plante ? » (Especes.porteNature) : la réponse le dit.
    static let remarqueSansPorte = "Sans le modèle de la recherche par le sens (MobileCLIP), rien ne vérifie d'abord que l'image montre un animal ou une plante : une capture d'écran ou un bâtiment peut ressortir. Vérifier à l'œil."

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
        var remarquesModule: [JSONValue] = []
        func garderRemarques(_ r: [String: JSONValue]) {
            for remarque in r["remarques"]?.array ?? [] where !remarquesModule.contains(remarque) { remarquesModule.append(remarque) }
        }
        let autres = params.keys.filter { !["limite", "decalage", "tri", "mots_cles_details"].contains($0) }
        var reponse: [String: JSONValue] = [:]
        var candidates: [JSONValue] = []
        // a. Les autres critères d'abord : s'ils gardent au plus `candidatsMax` photos, toutes sont
        //    examinées, que le Suivi les ait analysées ou non (l'index n'y sert pas).
        var totalCriteres: Int?
        if !autres.isEmpty {
            reponse = try lightroom.send("chercher", params, timeout: Self.libraryTimeout).object ?? [:]
            candidates = (reponse["photos"]?.array ?? []).filter { $0["video"]?.bool != true }
            totalCriteres = reponse["total"]?.int ?? candidates.count
        }
        // b. Plus de photos (ou aucun autre critère) : l'index du sens les classe par la meilleure des
        //    phrases du groupe, sur tout l'index, puis le module applique les autres critères parmi
        //    elles, par tranches de `trancheSens` dans cet ordre, jusqu'à `candidatsMax` (comme
        //    findPhotosParLeSens) : une collection classée loin ne rend pas une liste vide.
        var parIndex = false
        if totalCriteres.map({ $0 > Especes.candidatsMax }) ?? true, let sens, let index = try indexSensOuvert(sens),
           let encodeur = try? ouvrirEncodeurSens(sens), encodeur.modele == index.modele, encodeur.dimension == index.dimension {
            let debut = args.string("date_from").map { String($0.prefix(10)) }
            let fin = args.string("date_to").map { String($0.prefix(10)) }
            var meilleurs: [Int: Float] = [:]
            for phrase in groupe.phrases {
                for (ligne, score) in index.classer(Sens.normaliser(try encodeur.vecteur(texte: phrase))) {
                    if debut != nil || fin != nil {
                        guard let jour = ligne.jour else { continue }
                        if let debut, jour < debut { continue }
                        if let fin, jour > fin { continue }
                    }
                    if score > meilleurs[ligne.id] ?? -.infinity { meilleurs[ligne.id] = score }
                }
            }
            let classees = meilleurs.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
            var tranches = params
            tranches.removeValue(forKey: "date_debut")
            tranches.removeValue(forKey: "date_fin")
            if tranches["tri"] == nil { tranches["tri"] = "aucun" }
            let tranche = max(1, trancheSens)
            var parIndexCandidates: [JSONValue] = []
            var premiere: [String: JSONValue] = [:]
            var lues = 0, tranchesLues = 0
            while lues < classees.count, tranchesLues < Sens.tranchesMax, parIndexCandidates.count < Especes.candidatsMax {
                let ids = classees[lues..<min(classees.count, lues + tranche)].map { JSONValue.number(Double($0)) }
                tranches["parmi"] = .array(ids)
                tranches["limite"] = .number(Double(Especes.candidatsMax - parIndexCandidates.count))
                let morceau = try lightroom.send("chercher", tranches, timeout: Self.libraryTimeout).object ?? [:]
                guard morceau["parmi"]?.bool == true else {
                    throw LightroomError.invalid("Le module Lightroom installé ne connaît pas la recherche par le sens : installer la même version que le connecteur.")
                }
                if premiere.isEmpty { premiere = morceau }
                garderRemarques(morceau)
                parIndexCandidates += (morceau["photos"]?.array ?? []).filter { $0["video"]?.bool != true }
                    .prefix(Especes.candidatsMax - parIndexCandidates.count)
                lues += ids.count
                tranchesLues += 1
            }
            if !premiere.isEmpty {
                parIndex = true
                reponse = premiere
                candidates = parIndexCandidates
                let parmiCriteres = totalCriteres.map { " parmi les \($0) photos des autres critères" } ?? ""
                remarques.append(.string("Recherche par l'index du sens\(parmiCriteres) : seules les photos déjà analysées par le Suivi (\(index.nombre) dans l'index) sont examinées ; celles qu'il n'a pas encore vues ne le sont pas."))
                if candidates.count >= Especes.candidatsMax {
                    remarques.append(.string("Seules les \(candidates.count) photos les plus proches de « \(groupe.nom) » (recherche par le sens) ont été examinées : une date, un dossier ou une collection resserre la recherche."))
                } else if lues < classees.count {
                    remarques.append(.string("Liste coupée : seules les \(lues) photos de l'index les plus proches de « \(groupe.nom) » ont été lues ; une date, un dossier ou une collection resserre la recherche."))
                }
            }
        }
        if !parIndex {
            guard let totalCriteres else {
                throw LightroomError.invalid("Sans l'index de la recherche par le sens, « species » demande un autre critère (collection, dossier, dates, mot-clé…) : au plus \(Especes.candidatsMax) photos sont examinées.")
            }
            garderRemarques(reponse)
            if totalCriteres > candidates.count {
                remarques.append(.string("Seules les \(candidates.count) premières photos sur \(totalCriteres) ont été examinées (sans l'index de la recherche par le sens) : une date, un dossier ou une collection resserre la recherche."))
            }
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
        if !classeur.aUnePorte { remarques.append(.string(Self.remarqueSansPorte)) }
        resultat["remarques"] = .array(remarquesModule + remarques)
        resultat["especes"] = [
            "modele": .string(Especes.nomModele), "cherche": cherche, "examinees": .number(Double(resultats.count)),
            "seuil_provisoire": .number(seuil), "porte": .bool(classeur.aUnePorte),
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
            bloc["porte"] = .bool(classeur.aUnePorte)
            if bloc["trouvee"]?.bool == true {
                bloc["remarque"] = .string("Seuil provisoire \(Bilan.nombre(Especes.seuilConfianceProvisoire, decimales: 2)), à vérifier à l'œil ; le nom en mot-clé seulement après l'accord de l'utilisateur."
                    + (classeur.aUnePorte ? "" : " " + Self.remarqueSansPorte))
            }
            // Les encodeurs lisent le carré central (VNImageCropAndScaleOption.centerCrop) : sur une
            // image allongée, un sujet près d'un bord n'est pas vu.
            let cote = Double(min(image.width, image.height)), long = Double(max(image.width, image.height))
            if cote > 0, long / cote > 1.05 {
                bloc["lu_sur"] = "carré central"
                let carre = "Lu sur le carré central de l'image : un sujet près d'un bord demande un zoom sur lui (region)."
                bloc["remarque"] = .string([bloc["remarque"]?.string, carre].compactMap { $0 }.joined(separator: " "))
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
        if let classeurEspeces {
            bloc["especes_de_la_liste"] = .number(Double(classeurEspeces.liste.especes.count))
            bloc["porte"] = .bool(classeurEspeces.aUnePorte)
        }
        return .object(bloc)
    }
}
