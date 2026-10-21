import Foundation

/// Harmonisation chiffrée d'une série (`match_series`) : l'exposition, la balance des blancs (par la
/// dominante des tons neutres, a* et b*) et le contraste de chaque photo, rapprochés de ceux d'une
/// photo de référence. Sans accord, le plan seulement ; avec confirm, des corrections relatives,
/// puis une nouvelle mesure et une seconde correction si l'écart reste. Le lien entre a*/b* et les
/// curseurs n'est pas linéaire (les kelvins encore moins) : la première passe part de pentes
/// moyennes, la seconde de celles que la photo a montrées. Chaque `appliquer` d'une série porte
/// `sans_avant_apres` (1.3) : le module ne garde pas l'avant/après de ces étapes (Etapes.lua), même
/// sur la photo active, pour ne pas ralentir la série ni faire attendre l'aperçu de mesure suivant.
extension ToolHandler {
    static let maxMatchedPhotos = 60
    static let matchDimensions = ["exposure", "white_balance", "contrast"]

    /// Effet des curseurs sur la dominante des tons neutres, relevé le 17 octobre 2026 dans Lightroom
    /// Classic 15.6 par des propositions mesurées (tons neutres suivis ; voir docs/SPEC.md,
    /// Harmonisation d'une série). La Teinte déplace aussi b* et la Température a* : les deux se
    /// résolvent ensemble. RAW (X-H2S, vers 5000 K), par unité : Teinte → a* +0,235, b* −0,215 ;
    /// mired → a* −0,082, b* −0,215. JPEG (balance relative) : Teinte → a* +0,18, b* −0,178 ;
    /// Température → a* +0,078, b* +0,605. Ci-dessous, les inverses : les curseurs pour un écart.
    struct PentesSerie: Equatable {
        /// RAW : Teinte = tintA·a + tintB·b ; mired = miredA·a + miredB·b.
        var tintA = 3.16, tintB = -1.20, miredA = -3.16, miredB = -3.45
        /// JPEG : Teinte = jpegTintA·a + jpegTintB·b ; Température = jpegTempA·a + jpegTempB·b.
        var jpegTintA = 4.93, jpegTintB = -0.64, jpegTempA = 1.45, jpegTempB = 1.47
        /// Contrast2012 par unité d'écart P95 − P5 de L* : +30 l'élargissent de 5,7.
        var contrasteParL = 5.3
        /// Exposure2012 par IL de luminance médiane : 1 au départ ; la balance et la courbe de
        /// tonalité en changent l'effet (constaté : −0,85 IL laissaient 0,2 IL d'écart).
        var expositionParIL = 1.0
    }

    /// Contraste corrigé au plus par passe : au-delà, l'écart vient de la scène plus que du réglage.
    static let maxContrastePasse = 30.0

    /// Seuils sous lesquels un écart ne se corrige pas (il ne se voit pas).
    static let seuilExposition = 0.1, seuilDominante = 1.5, seuilContraste = 4.0

    var seriesDefinitions: [JSONValue] {
        [
            tool("match_series",
                 "Harmonise une série sur une photo de référence, en chiffres : exposition (IL), balance des blancs (dominante des tons neutres, a* et b*, traduite en Temperature et Tint) et contraste (Contrast2012). Sans confirm : le plan, photo par photo (écarts mesurés et corrections proposées), sans rien changer : le montrer à l'utilisateur. Avec confirm = true : corrections relatives (une étape « Claude · <step_name> » par photo, que undo_last défait), nouvelle mesure, puis une seconde correction si un écart visible reste ; le résultat donne les écarts avant et après. Les photos sans assez de tons neutres gardent leur balance (dit). Pour les autres réglages (profil, couleurs, masques), copy_settings depuis la référence d'abord.",
                 properties: [
                    ("reference_id", prop("integer", "Photo de référence, déjà retouchée.")),
                    ("photo_ids", listProp("integer", "Photos à harmoniser (sans la référence).")),
                    ("selection", prop("boolean", "true = les photos sélectionnées dans Lightroom (la référence est écartée).")),
                    ("collection", prop("string", "Une collection : son nom, « Ensemble > Nom » ou son identifiant.")),
                    ("adjust", ["type": "array", "items": ["type": "string", "enum": .array(Self.matchDimensions.map(JSONValue.string))],
                                "description": "Ce qu'il faut rapprocher (défaut : les trois)."]),
                    ("by", enumProp(["measure", "exif"], "measure (défaut) : d'après les aperçus mesurés. exif : l'exposition seule, d'après l'ouverture, la vitesse et l'ISO de chaque photo, sans mesure (« Reproduire toutes les expositions » de Lightroom) : pour une série prise en manuel, ou un bracketing à ramener à la même luminosité.")),
                 ] + writeProperties,
                 required: ["reference_id"]),
        ]
    }

    /// Une photo mesurée : ses mesures et ce qu'il faut pour la corriger.
    struct PhotoSerie {
        var id: Int
        var fichier: JSONValue
        var raw: Bool
        var temperature: Double?
        var mesures: PhotoMeasurements
        /// Tons neutres suivis (mêmes pixels d'une passe à l'autre).
        var neutres: Measurements.NeutresSuivis?
    }

    func matchSeries(_ args: Arguments) throws -> JSONValue {
        guard let reference = args.int("reference_id") else { throw LightroomError.invalid("« reference_id » : la photo de référence.") }
        let dimensions = Set((args.array("adjust") ?? Self.matchDimensions.map(JSONValue.string)).compactMap(\.string))
        guard !dimensions.isEmpty, dimensions.isSubset(of: Self.matchDimensions) else {
            throw LightroomError.invalid("« adjust » : \(Self.matchDimensions.joined(separator: ", ")).")
        }
        let serie = try seriesPhotos(args, maximum: Self.maxMatchedPhotos + 1)
        var ids = serie.ids.filter { $0 != reference }
        // Une collection ou une sélection plus longue que la limite : les photos laissées de côté sont dites.
        let nonHarmonisees = max(0, serie.total - serie.ids.count) + max(0, ids.count - Self.maxMatchedPhotos)
        ids = Array(ids.prefix(Self.maxMatchedPhotos))
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à harmoniser (la référence est écartée).") }
        if let by = args.string("by"), by != "measure" {
            guard by == "exif" else { throw LightroomError.invalid("« by » : measure ou exif.") }
            return try matchSeriesExif(args, reference: reference, ids: ids)
        }
        let confirme = args.bool("confirm") == true
        let total = ids.count * (confirme ? 3 : 1) + 1
        var fait = 0
        avancer(0, sur: total, "Mesure de la référence", titre: "harmonisation de la série")
        let ref = try mesurerSerie(reference)
        fait += 1
        var lignes: [JSONValue] = []
        for id in ids {
            try contexte.verifier()
            // Chaque photo part des pentes relevées : celles d'une autre photo ne lui valent rien.
            var pentes = PentesSerie()
            let photo = try mesurerSerie(id)
            fait += 1
            avancer(fait, sur: total, "Mesure de \(photo.fichier.string ?? "la photo \(id)")", titre: "harmonisation de la série")
            let ecart = Self.ecartSerie(photo, ref)
            var correction = Self.correction(ecart, photo: photo, dimensions: dimensions, pentes: pentes)
            var ligne: [String: JSONValue] = ["id": .number(Double(id)), "fichier": photo.fichier, "ecart_avant": Self.ecartJSON(ecart)]
            if correction.reglages.isEmpty {
                ligne["correction"] = "aucune : déjà proche de la référence"
                if !correction.remarques.isEmpty { ligne["remarques"] = .array(correction.remarques.map(JSONValue.string)) }
                lignes.append(.object(ligne))
                continue
            }
            ligne["correction_proposee"] = .object(correction.reglages.mapValues { .number(($0 * 100).rounded() / 100) })
            if !correction.remarques.isEmpty { ligne["remarques"] = .array(correction.remarques.map(JSONValue.string)) }
            guard confirme else {
                lignes.append(.object(ligne))
                continue
            }
            // Passe 1, mesure, puis passe 2 sur l'écart restant, avec les pentes que la photo a montrées.
            var etapes: [JSONValue] = []
            var mesuree = photo
            for passe in 1...2 {
                try contexte.verifier()
                let nom = "\(args.string("step_name") ?? "harmonisation") : passe \(passe)"
                var (params, _) = try developParameters(Arguments(raw: ["settings": .object(correction.reglages.mapValues { .number($0) }),
                                                                        "relative": true]))
                params["photos"] = [.number(Double(id))]
                var ecriture = writeParameters(Arguments(raw: ["step_name": .string(nom), "reason": args.raw["reason"] ?? .null, "confirm": true]),
                                               defaultStep: nom)
                ecriture["raison"] = ecriture["raison"] ?? .string("Harmonisation sur la référence.")
                params.merge(ecriture) { _, new in new }
                params["sans_avant_apres"] = true
                _ = try lightroom.send("appliquer", params, timeout: 180)
                etapes.append(.string("Claude · " + nom))
                let avant = mesuree
                mesuree = try mesurerSerie(id, masque: photo.neutres?.masque)
                fait += 1
                avancer(min(fait, total), sur: total, "\(photo.fichier.string ?? "Photo \(id)") : passe \(passe) mesurée", titre: "harmonisation de la série")
                let reste = Self.ecartSerie(mesuree, ref)
                pentes = Self.pentesObservees(pentes, appliquee: correction.reglages, avant: avant, apres: mesuree)
                correction = Self.correction(reste, photo: mesuree, dimensions: dimensions, pentes: pentes)
                if correction.reglages.isEmpty || passe == 2 { break }
            }
            ligne["etapes"] = .array(etapes)
            ligne["ecart_apres"] = Self.ecartJSON(Self.ecartSerie(mesuree, ref))
            lignes.append(.object(ligne))
        }
        var resultat: [String: JSONValue] = [
            "reference": ["id": .number(Double(reference)), "fichier": ref.fichier],
            "photos": .array(lignes),
            "base": "Écarts « référence moins photo » : exposition en IL (luminance médiane), dominante a* (vert − / magenta +) et b* (bleu − / jaune +) des tons neutres, contraste (L* P95 − P5).",
        ]
        if nonHarmonisees > 0 {
            resultat["photos_non_harmonisees"] = .number(Double(nonHarmonisees))
            resultat["remarque"] = .string("\(nonHarmonisees) photo(s) laissée(s) de côté : au plus \(Self.maxMatchedPhotos) par appel ; les harmoniser par photo_ids, par lots.")
        }
        if !confirme {
            resultat["rien_n_est_applique"] = "Plan seulement : le montrer à l'utilisateur ; avec son accord, rappeler match_series avec confirm = true (corrections relatives, mesurées puis reprises une fois)."
        }
        return .object(resultat)
    }

    /// Exposition d'une photo à la prise de vue (module : `prise_de_vue`), et son Exposure2012.
    struct ExpositionPriseDeVue {
        var id: Int
        var fichier: JSONValue
        var ouverture: Double
        var vitesse: Double
        var iso: Double
        var exposition: Double
        /// Lumière reçue, en IL (plus grand = plus de lumière) : log2(t · S / N²).
        var lumiere: Double { log2(vitesse * iso / max(ouverture * ouverture, 0.01)) }
    }

    func expositionPriseDeVue(_ id: Int) throws -> ExpositionPriseDeVue {
        let reponse = try lightroom.send("reglages", ["photo": .number(Double(id)), "cles": ["Exposure2012"]], timeout: 30)
        guard let exif = reponse["prise_de_vue"], let ouverture = exif["ouverture"]?.double, let vitesse = exif["vitesse"]?.double,
              let iso = exif["iso"]?.double, ouverture > 0, vitesse > 0, iso > 0 else {
            throw LightroomError.invalid("La photo \(id) n'a pas d'ouverture, de vitesse ou d'ISO lisibles : by = measure, d'après l'aperçu.")
        }
        return ExpositionPriseDeVue(id: id, fichier: reponse["photo"]?["fichier"] ?? .null, ouverture: ouverture, vitesse: vitesse, iso: iso,
                                    exposition: reponse["reglages"]?["Exposure2012"]?.double ?? 0)
    }

    /// « Reproduire toutes les expositions » : chaque photo reçoit l'Exposure2012 de la référence,
    /// corrigé de l'écart de lumière à la prise de vue (ouverture, vitesse, ISO), sans mesure. Une
    /// photo qui a reçu une IL de moins qu'elle prend +1.
    func matchSeriesExif(_ args: Arguments, reference: Int, ids: [Int]) throws -> JSONValue {
        let ref = try expositionPriseDeVue(reference)
        let confirme = args.bool("confirm") == true
        var lignes: [JSONValue] = []
        for (index, id) in ids.enumerated() {
            try contexte.verifier()
            avancer(index, sur: ids.count, "Exposition de la photo \(id)", titre: "harmonisation de la série")
            let photo = try expositionPriseDeVue(id)
            let ecart = ref.lumiere - photo.lumiere
            let cible = (min(max(ref.exposition + ecart, -5), 5) * 100).rounded() / 100
            var ligne: [String: JSONValue] = [
                "id": .number(Double(id)), "fichier": photo.fichier,
                "prise_de_vue": .string("f/\(DevelopCatalogue.format((photo.ouverture * 10).rounded() / 10)), \(Self.vitesseTexte(photo.vitesse)), ISO \(DevelopCatalogue.format(photo.iso))"),
                "ecart_IL": .number((ecart * 100).rounded() / 100),
                "Exposure2012": ["avant": .number(photo.exposition), "propose": .number(cible)],
            ]
            if abs(ref.exposition + ecart) > 5 {
                ligne["limite"] = "L'écart dépasse la plage d'Exposure2012 (−5 à +5 IL) : l'exposition proposée s'y arrête."
            }
            if abs(cible - photo.exposition) < 0.01 {
                ligne["correction"] = "aucune : même exposition que la référence"
            } else if confirme {
                let nom = args.string("step_name") ?? "expositions reproduites"
                var (params, _) = try developParameters(Arguments(raw: ["settings": ["Exposure2012": .number(cible)]]))
                params["photos"] = [.number(Double(id))]
                var ecriture = writeParameters(Arguments(raw: ["step_name": .string(nom), "reason": args.raw["reason"] ?? .null, "confirm": true]),
                                               defaultStep: nom)
                ecriture["raison"] = ecriture["raison"] ?? .string("Exposition reproduite d'après la prise de vue de la référence.")
                params.merge(ecriture) { _, new in new }
                params["sans_avant_apres"] = true
                let reponse = try lightroom.send("appliquer", params, timeout: 120)
                ligne["etape"] = .string("Claude · " + nom)
                if let remarques = reponse["resultats"]?.array?.first?["remarques"], !(remarques.array ?? []).isEmpty {
                    ligne["remarques"] = remarques
                }
            }
            lignes.append(.object(ligne))
        }
        var resultat: [String: JSONValue] = [
            "reference": ["id": .number(Double(reference)), "fichier": ref.fichier, "Exposure2012": .number(ref.exposition),
                          "prise_de_vue": .string("f/\(DevelopCatalogue.format((ref.ouverture * 10).rounded() / 10)), \(Self.vitesseTexte(ref.vitesse)), ISO \(DevelopCatalogue.format(ref.iso))")],
            "photos": .array(lignes),
            "base": "Exposition reproduite d'après la prise de vue (ouverture, vitesse, ISO), sans mesure : Exposure2012 de la référence plus l'écart de lumière reçue, en IL. Le flash et une lumière qui change entre les prises ne comptent pas. La balance et le contraste ne changent pas.",
        ]
        if !confirme {
            resultat["rien_n_est_applique"] = "Plan seulement : le montrer à l'utilisateur ; avec son accord, rappeler match_series avec by = exif et confirm = true."
        }
        return .object(resultat)
    }

    static func vitesseTexte(_ secondes: Double) -> String {
        secondes >= 0.5 ? "\(DevelopCatalogue.format((secondes * 10).rounded() / 10)) s" : "1/\(Int((1 / secondes).rounded())) s"
    }

    /// Aperçu d'analyse, mesures, et balance actuelle (kelvins pour un RAW).
    func mesurerSerie(_ id: Int, masque: [Bool]? = nil) throws -> PhotoSerie {
        let reponse = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(Self.analysisSize)),
                                                    "cles": ["Temperature", "Tint"]], timeout: 120)
        let data = try Self.readPreview(reponse["chemin"]?.string)
        guard let mesures = Measurements.analyze(data) else { throw LightroomError.plugin("Aperçu illisible pour la photo \(id).") }
        let raw = reponse["echelle_temperature"]?.string?.contains("kelvins") == true
        var neutres = Measurements.neutres(data, masque: masque)
        if neutres == nil, masque != nil { neutres = Measurements.neutres(data) }
        return PhotoSerie(id: id, fichier: reponse["photo"]?["fichier"] ?? .null, raw: raw,
                          temperature: reponse["reglages"]?["Temperature"]?.double, mesures: mesures, neutres: neutres)
    }

    struct EcartSerie: Equatable {
        var exposition: Double
        var a: Double?
        var b: Double?
        var contraste: Double
    }

    /// Écart avec la référence. La dominante se compare par la même mesure des deux côtés (tons
    /// neutres choisis à nouveau sur chaque image) ; les tons neutres suivis servent seulement à la
    /// pente (constaté le 17 octobre 2026 : comparés à la référence, ils laissaient 4,2 de b* d'écart
    /// sur une photo que la mesure commune disait juste).
    static func ecartSerie(_ photo: PhotoSerie, _ reference: PhotoSerie) -> EcartSerie {
        let p = photo.mesures, r = reference.mesures
        let photoY = max(Measurements.luminance(p.medianL), 0.0005), referenceY = max(Measurements.luminance(r.medianL), 0.0005)
        let neutres = p.neutralShare >= PhotoMeasurements.partNeutreMin && r.neutralShare >= PhotoMeasurements.partNeutreMin
        return EcartSerie(exposition: min(max(log2(referenceY / photoY), -3), 3),
                          a: neutres ? r.neutralA - p.neutralA : nil,
                          b: neutres ? r.neutralB - p.neutralB : nil,
                          contraste: r.contrast - p.contrast)
    }

    static func ecartJSON(_ ecart: EcartSerie) -> JSONValue {
        func r(_ value: Double, _ step: Double = 0.1) -> JSONValue { .number((value / step).rounded() / (1 / step).rounded()) }
        var objet: [String: JSONValue] = ["exposition_IL": r(ecart.exposition, 0.05), "contraste": r(ecart.contraste)]
        objet["dominante_a"] = ecart.a.map { r($0) } ?? "pas assez de tons neutres"
        objet["dominante_b"] = ecart.b.map { r($0) } ?? "pas assez de tons neutres"
        return .object(objet)
    }

    /// Corrections relatives pour un écart, d'après les pentes.
    static func correction(_ ecart: EcartSerie, photo: PhotoSerie, dimensions: Set<String>, pentes: PentesSerie)
        -> (reglages: [String: Double], remarques: [String]) {
        var reglages: [String: Double] = [:], remarques: [String] = []
        if dimensions.contains("exposure"), abs(ecart.exposition) >= seuilExposition {
            reglages["Exposure2012"] = (min(max(ecart.exposition * pentes.expositionParIL, -2), 2) * 20).rounded() / 20
        }
        if dimensions.contains("white_balance") {
            if let b = ecart.b, let a = ecart.a {
                if abs(a) >= seuilDominante || abs(b) >= seuilDominante {
                    if photo.raw, let kelvins = photo.temperature, kelvins > 0 {
                        let mired = 1_000_000 / kelvins + pentes.miredA * a + pentes.miredB * b
                        let cible = 1_000_000 / max(mired, 20)
                        reglages["Temperature"] = (min(max(cible, 2000), 50000) - kelvins).rounded()
                        reglages["Tint"] = min(max(pentes.tintA * a + pentes.tintB * b, -40), 40).rounded()
                    } else if !photo.raw {
                        reglages["Temperature"] = min(max(pentes.jpegTempA * a + pentes.jpegTempB * b, -40), 40).rounded()
                        reglages["Tint"] = min(max(pentes.jpegTintA * a + pentes.jpegTintB * b, -40), 40).rounded()
                    } else {
                        remarques.append("Balance des blancs gardée : la température de ce RAW n'a pas pu être lue.")
                    }
                }
            } else {
                remarques.append("Balance des blancs gardée : pas assez de tons neutres pour la mesurer (sur cette photo ou la référence).")
            }
        }
        if dimensions.contains("contrast"), abs(ecart.contraste) >= seuilContraste {
            let voulu = pentes.contrasteParL * ecart.contraste
            reglages["Contrast2012"] = min(max(voulu, -maxContrastePasse), maxContrastePasse).rounded()
            if abs(voulu) > maxContrastePasse {
                remarques.append("Écart de contraste trop grand pour le seul curseur Contraste (\(Int(voulu.rounded())) demandé, \(Int(maxContrastePasse)) au plus par passe) : la scène diffère, ou il faut la courbe, les Blancs et les Noirs.")
            }
        }
        return (reglages.filter { $0.value != 0 }, remarques)
    }

    /// Pentes du contraste et de l'exposition corrigées d'après ce qu'une passe a fait : une variation
    /// mesurée dans le bon sens et assez grande donne la pente de cette photo, bornée. La balance garde
    /// ses pentes : une passe la rapproche, la suivante finit.
    static func pentesObservees(_ pentes: PentesSerie, appliquee: [String: Double], avant: PhotoSerie, apres: PhotoSerie) -> PentesSerie {
        var nouvelles = pentes
        let depart = PentesSerie().contrasteParL
        let mesure = apres.mesures.contrast - avant.mesures.contrast
        if let curseur = appliquee["Contrast2012"], abs(mesure) >= 0.5, curseur / mesure > 0 {
            nouvelles.contrasteParL = min(max(curseur / mesure, depart / 4), depart * 4)
        }
        let yAvant = max(Measurements.luminance(avant.mesures.medianL), 0.0005), yApres = max(Measurements.luminance(apres.mesures.medianL), 0.0005)
        let ilMesures = log2(yApres / yAvant)
        if let curseur = appliquee["Exposure2012"], abs(ilMesures) >= 0.05, curseur / ilMesures > 0 {
            nouvelles.expositionParIL = min(max(curseur / ilMesures, 0.5), 2.5)
        }
        return nouvelles
    }
}
