import Foundation

/// Harmoniser par lumière (1.4) : `match_series` avec `groups` partage une sortie entière en groupes
/// de photos prises sous la même lumière (`GroupesLumiere`), et propose une référence par groupe,
/// sans rien changer. Les photos se mesurent sur les vignettes du cache de Lightroom, comme le tri
/// (`cull_photos`), sans ouvrir aucun original : la description perd sa géométrie avant la mesure,
/// et le point de mise au point n'est pas lu. Chaque groupe s'harmonise ensuite sur sa référence,
/// une fois celle-ci retouchée : `match_series` avec `reference_id` et les `photo_ids` du groupe.
extension ToolHandler {
    func groupesDeLumiere(_ args: Arguments) throws -> JSONValue {
        let debut = Date()
        guard Self.serieDonnee(args) else {
            throw LightroomError.invalid("Photos de la sortie : photo_ids, selection = true, collection ou folder.")
        }
        guard !args.has("reference_id") else {
            throw LightroomError.invalid("« groups » forme les groupes de toute la sortie, sans reference_id ; chaque groupe s'harmonise ensuite par match_series avec reference_id et ses photo_ids.")
        }
        let serie = try seriesPhotosSansVideos(args, maximum: Self.maxPhotosSortie)
        var videos = serie.videos
        guard !serie.ids.isEmpty else {
            throw LightroomError.invalid(videos > 0 ? "Aucune photo : \(videos) vidéo(s), qui ne s'harmonisent pas." : "Aucune photo à grouper.")
        }
        var photos: [PhotoTriee] = []
        var prises: [GroupesLumiere.Prise] = []
        var retouchees: Set<Int> = []
        try thumbnails(serie.ids, taille: Self.cullThumbnailSize, minimum: Self.minimumCullSide, message: "groupes de lumière") { tout in
            let lot = tout.filter { !Self.estVideo($0.description) }
            videos += tout.count - lot.count
            // Comme le tri, deux photos à la fois au plus (Vision) ; sans géométrie, aucun original
            // ne s'ouvre pour le point de mise au point.
            var mesurees = [PhotoTriee?](repeating: nil, count: lot.count)
            let verrou = NSLock()
            let file = OperationQueue()
            file.maxConcurrentOperationCount = Self.parallelMeasures
            for i in lot.indices {
                var vignette = lot[i]
                if var description = vignette.description.object {
                    description.removeValue(forKey: "geometrie")
                    vignette.description = .object(description)
                }
                file.addOperation {
                    let photo = Self.mesurer(vignette, motsCles: false)
                    verrou.lock(); mesurees[i] = photo; verrou.unlock()
                }
            }
            file.waitUntilAllOperationsAreFinished()
            for (i, vignette) in lot.enumerated() {
                guard let photo = mesurees[i] else { continue }
                photos.append(photo)
                prises.append(Self.prise(vignette.description, photo: photo))
                if vignette.description["retouchee_par_claude"]?.bool == true { retouchees.insert(photo.id) }
            }
        }
        let groupes = GroupesLumiere.former(prises) { i, j in
            guard let a = photos[i].empreinte, let b = photos[j].empreinte else { return nil }
            return VisionAnalysis.distance(a, b)
        }
        var resultat = Self.planDesGroupes(groupes, prises: prises, photos: photos, retouchees: retouchees)
        if serie.total > serie.ids.count + serie.videos {
            resultat["photos_non_groupees"] = .string("\(serie.total - serie.ids.count - serie.videos) photo(s) de plus dans la série : au plus \(Self.maxPhotosSortie) par appel ; grouper la suite à part (photo_ids), puis rapprocher les groupes qui se touchent.")
        }
        if videos > 0 {
            resultat["videos_ecartees"] = .string("\(videos) vidéo(s) écartée(s) : seules les photos s'harmonisent.")
        }
        resultat["duree"] = .string(FileOutils.duree(Date().timeIntervalSince(debut)))
        return .object(resultat)
    }

    /// La prise de vue d'une photo, d'après la description des vignettes (`prise_de_vue` en nombres
    /// et `sensibilite`, 1.4) et la date déjà lue par le tri.
    static func prise(_ description: JSONValue, photo: PhotoTriee) -> GroupesLumiere.Prise {
        let prise = description["prise_de_vue"]
        return GroupesLumiere.Prise(id: photo.id, fichier: photo.fichier, date: photo.date,
                                    ouverture: prise?["ouverture"]?.double, vitesse: prise?["vitesse"]?.double,
                                    iso: description["sensibilite"]?.double, compensation: prise?["compensation"]?.double,
                                    flash: prise?["flash"]?.bool)
    }

    /// Le plan des groupes, pour Claude : chaque groupe d'au moins deux photos avec sa lumière, sa
    /// référence proposée et le chemin pour l'harmoniser ; les photos seules à part.
    static func planDesGroupes(_ groupes: [GroupesLumiere.Groupe], prises: [GroupesLumiere.Prise], photos: [PhotoTriee],
                               retouchees: Set<Int>) -> [String: JSONValue] {
        let jour = DateFormatter()
        jour.locale = Locale(identifier: "fr_CA")
        jour.dateFormat = "yyyy-MM-dd HH:mm"
        var liste: [JSONValue] = [], seules: [JSONValue] = []
        for (rang, groupe) in groupes.enumerated() {
            let membres = groupe.membres
            guard membres.count > 1 else {
                // Ce qui la sépare de la photo d'avant, et de celle d'après.
                let i = membres[0]
                let apres = rang + 1 < groupes.count ? "après elle : \(groupes[rang + 1].coupure.texte)" : "dernière photo de la série"
                seules.append(["id": .number(Double(prises[i].id)), "fichier": .string(prises[i].fichier),
                               "pourquoi": .string("seule sous sa lumière (\(groupe.coupure.texte) ; \(apres)) : à retoucher seule, rien à harmoniser")])
                continue
            }
            var item: [String: JSONValue] = [
                "numero": .number(Double(liste.count + 1)),
                "photos": .array(membres.map { .number(Double(prises[$0].id)) }),
                "nombre": .number(Double(membres.count)),
                "commence": .string(groupe.coupure.texte),
            ]
            let dates = membres.compactMap { prises[$0].date }
            if let premiere = dates.min(), let derniere = dates.max() {
                item["prises"] = .string(premiere == derniere ? jour.string(from: premiere)
                                         : "\(jour.string(from: premiere)) à \(jour.string(from: derniere))")
            }
            let auFlash = membres.filter { prises[$0].flash == true }.count
            let lumieres = membres.compactMap { prises[$0].flash == true ? nil : prises[$0].lumiere }
            if auFlash * 2 > membres.count {
                item["lumiere"] = "au flash"
            } else if !lumieres.isEmpty {
                let mediane = Eclairage.mediane(lumieres)
                item["lumiere"] = .string("\(GroupesLumiere.nomLumiere(mediane)) (IL \(PhotoTriee.r(mediane)) à 100 ISO)")
            } else {
                item["lumiere"] = "inconnue (ni ouverture, ni vitesse, ni ISO lisibles)"
            }
            let isos = membres.compactMap { prises[$0].iso }
            if let bas = isos.min(), let haut = isos.max() {
                item["iso"] = .string(bas == haut ? "ISO \(DevelopCatalogue.format(bas))"
                                      : "ISO \(DevelopCatalogue.format(bas)) à \(DevelopCatalogue.format(haut))")
            }
            let boitiers = Set(membres.compactMap { photos[$0].boitier }.filter { !$0.isEmpty })
            if boitiers.count > 1 { item["boitiers"] = .number(Double(boitiers.count)) }
            let avecVisage = membres.filter { (photos[$0].vision?.faces ?? []).contains { Double($0.box.width) >= Teint.visageMin && Composition.visagePlausible($0) } }
            if !avecVisage.isEmpty { item["photos_avec_visage"] = .number(Double(avecVisage.count)) }
            if let reference = GroupesLumiere.reference(membres, photos: photos, retouchees: retouchees) {
                let photo = photos[reference.index]
                item["reference_proposee"] = ["id": .number(Double(photo.id)), "fichier": .string(photo.fichier),
                                              "pourquoi": .string(reference.pourquoi)]
                let autres = membres.count - 1
                if autres > maxMatchedPhotos {
                    let lots = (autres + maxMatchedPhotos - 1) / maxMatchedPhotos
                    item["lots"] = .string("\(autres) photos à harmoniser : \(lots) appels de match_series, \(maxMatchedPhotos) photo_ids au plus chacun, avec la même référence.")
                }
            }
            liste.append(.object(item))
        }
        var resultat: [String: JSONValue] = [
            "photos_analysees": .number(Double(prises.count)),
            "groupes": .array(liste),
            "base": .string("Groupes de lumière, dans l'ordre de prise de vue : un groupe commence quand le flash change, quand la lumière de la scène (IL à 100 ISO, d'après l'ouverture, la vitesse, l'ISO et la compensation) s'écarte de \(PhotoTriee.r(GroupesLumiere.ecartIL)) IL ou plus de la médiane des \(GroupesLumiere.fenetreLumiere) dernières photos du groupe, ou après une pause de plus de \(GroupesLumiere.duree(GroupesLumiere.pauseMax)), sauf si Vision voit le même lieu (empreinte à moins de \(DevelopCatalogue.format(GroupesLumiere.distanceMemeLieu)) de l'une des \(GroupesLumiere.fenetreLieu) dernières) dans l'heure. Deux boîtiers sur la même scène restent ensemble. Seuils provisoires : regarder les coupures (contact_sheet), et rapprocher ou séparer des groupes au besoin. Référence proposée : une photo déjà retouchée par Claude, sinon la mieux classée au tri, avec un visage si le groupe en a (témoin du teint de match_series). Mesures sur les vignettes du cache de Lightroom, sans ouvrir aucun original ; une photo sans vignette assez grande est rendue comme un aperçu (comme au tri)."),
            "suite": .string("Montrer les groupes à l'utilisateur. Puis, groupe par groupe : retoucher la référence (deux passes vérifiées), copy_settings depuis elle vers les autres photos du groupe (profil et réglages communs), puis match_series avec reference_id et les photo_ids du groupe (sans confirm : le plan ; avec l'accord, confirm = true), \(maxMatchedPhotos) photos au plus par appel. Une photo seule se retouche à part."),
            "rien_n_est_applique": "Plan seulement : aucune photo n'est changée.",
        ]
        if !seules.isEmpty { resultat["photos_seules"] = .array(seules) }
        return resultat
    }
}
