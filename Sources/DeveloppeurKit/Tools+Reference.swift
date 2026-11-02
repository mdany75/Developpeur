import CoreGraphics
import Foundation

/// Étalonnage d'après une photo de référence du catalogue (`match_look`, 1.6) : donner à une photo
/// (ou à une petite série) le rendu d'une autre, déjà retouchée. Ce n'est pas `match_series`, qui
/// neutralise les écarts d'une même sortie : ici on copie un style (des ombres froides et des hautes
/// lumières chaudes), en réglages ordinaires que Lightroom garde modifiables.
///
/// Mesures et traduction : `Reference` (pur). Ici : lire les photos, rendre le plan, puis, avec
/// confirm, au plus deux passes mesurées, chacune une écriture ABSOLUE en une seule étape « Claude ·
/// <step_name> : passe N » (le drapeau relatif vaut pour tout un `appliquer` : les valeurs finales se
/// calculent d'après les réglages relus par l'aperçu). `sans_avant_apres` comme match_series : la
/// fenêtre Claude lit les étapes dans `photos[].etapes` (Conversation.lua, SERIES). Les plafonds de
/// dose partent avec chaque écriture (le module juge la Vibrance finale) ; la saturation de
/// l'étalonnage a sa borne propre (`Reference.saturationMax`). La peau : les visages de Vision ne
/// guident pas la mesure, et si la passe 1 déplace la peau d'un écart qui se voit, la passe 2 rend la
/// moitié du changement des tons moyens, puis `a_verifier`.
extension ToolHandler {
    static let maxLookPhotos = 20
    static let lookDimensions = ["tone", "color_grading", "saturation", "white_balance"]
    static let lookDimensionsDefaut = ["tone", "color_grading", "saturation"]

    var referenceDefinitions: [JSONValue] {
        [
            tool("match_look",
                 "Donne à une photo le rendu d'une photo de référence du catalogue (reference_id), déjà retouchée : tons (Exposition, Contraste), couleur des ombres, des tons moyens et des hautes lumières (Étalonnage des couleurs), saturation (Vibrance seulement), balance sur demande. La couleur de chaque zone se mesure sur ses pixels peu saturés, sans les visages ; seul le partage entre zones se copie (la part commune, c'est la balance : adjust white_balance). Sans confirm : le plan, sans rien changer, à montrer. Avec confirm = true : valeurs finales en une étape « Claude · <step_name> : passe N » par passe, nouvelle mesure, une seconde passe si l'écart reste (deux au plus) ; le résultat donne les écarts par zone avant et après (rapproche_pct). Saturation de l'étalonnage \(Int(Reference.saturationMax)) au plus par zone, Vibrance sous son plafond de dose ; si la peau bouge nettement, la passe 2 rend la moitié du changement des tons moyens (a_verifier). Pour neutraliser une série prise ensemble : match_series.",
                 properties: [
                    ("reference_id", prop("integer", "Photo du catalogue dont on veut le rendu (son aperçu développé).")),
                    ("photo_id", photoIDProperty),
                    ("photo_ids", listProp("integer", "Photos à traiter, au plus \(Self.maxLookPhotos) (la référence est écartée).")),
                    ("selection", prop("boolean", "true = les photos sélectionnées dans Lightroom (la référence est écartée).")),
                    ("collection", prop("string", "Une collection : son nom, « Ensemble > Nom » ou son identifiant.")),
                    ("adjust", ["type": "array", "items": ["type": "string", "enum": .array(Self.lookDimensions.map(JSONValue.string))],
                                "description": "Ce qu'il faut copier (défaut : tone, color_grading, saturation). white_balance seulement sur demande : la couleur du sujet reste honnête."]),
                    ("strength", prop("number", "Part de l'écart à combler, de 0,25 à 1 (défaut 0,6 : rapproche sans copier ; 1 vise la référence).")),
                    ("protect_skin", prop("boolean", "Défaut true : les visages ne guident pas la mesure, et le changement des tons moyens est réduit si la peau bouge.")),
                    ("strong_dose_requested", prop("boolean", "true seulement sur demande claire de l'utilisateur : saturation de l'étalonnage jusqu'à \(Int(Reference.saturationMaxForte)), Vibrance au-delà de son plafond.")),
                 ] + writeProperties,
                 required: ["reference_id"]),
        ]
    }

    /// Une photo lue pour match_look : son aperçu, sa signature, ses réglages et sa peau.
    struct PhotoRendu {
        var id: Int
        var fichier: JSONValue
        var image: CGImage
        var signature: Reference.Signature
        var etat: Reference.Etat
        var visages: [CGRect]
        var peau: Teint.Mesure?
    }

    /// L'aperçu de mesure d'une photo (sans `id` : la photo active), sa signature et ses réglages.
    /// `visages` : ceux d'une lecture précédente de la même photo (même cadre), pour suivre la peau.
    func lireRendu(_ id: Int?, visages connus: [CGRect]? = nil, peau: Bool) throws -> PhotoRendu {
        var params: [String: JSONValue] = ["taille": .number(Double(Self.analysisSize)), "cles": .array(Reference.clesLues.map(JSONValue.string))]
        if let id { params["photo"] = .number(Double(id)) }
        let reponse = try lightroom.send("apercu", params, timeout: 120)
        let data = try Self.readPreview(reponse["chemin"]?.string)
        guard let image = PreviewImages.image(data) else { throw LightroomError.plugin("Aperçu illisible pour la photo \(id.map(String.init) ?? "active").") }
        guard let lu = id ?? reponse["photo"]?["id"]?.int else { throw LightroomError.plugin("Le module n'a pas dit quelle photo est active : donner photo_id.") }
        let visages = peau ? (connus ?? detecterVisages(image)) : []
        guard let signature = Reference.lire(image, visages: visages) else { throw LightroomError.plugin("Aperçu illisible pour la photo \(lu).") }
        var reglages: [String: Double] = [:]
        for (cle, valeur) in reponse["reglages"]?.object ?? [:] {
            if let nombre = valeur.double, nombre != Self.pendingAutoValue { reglages[cle] = nombre }
        }
        let raw = reponse["echelle_temperature"]?.string?.contains("kelvins") == true
        return PhotoRendu(id: lu, fichier: reponse["photo"]?["fichier"] ?? .null, image: image, signature: signature,
                          etat: Reference.Etat(reglages: reglages, raw: raw), visages: visages,
                          peau: peau ? Teint.mesurer(image, visages: visages) : nil)
    }

    func matchLook(_ args: Arguments) throws -> JSONValue {
        guard let reference = args.int("reference_id") else {
            throw LightroomError.invalid("« reference_id » : la photo du catalogue dont on veut le rendu. Un fichier hors du catalogue n'est pas encore pris (1.6) : l'importer d'abord.")
        }
        let demandees = (args.array("adjust") ?? Self.lookDimensionsDefaut.map(JSONValue.string)).compactMap(\.string)
        guard !demandees.isEmpty, Set(demandees).isSubset(of: Self.lookDimensions) else {
            throw LightroomError.invalid("« adjust » : \(Self.lookDimensions.joined(separator: ", ")).")
        }
        var options = Reference.Options()
        options.tons = demandees.contains("tone")
        options.etalonnage = demandees.contains("color_grading")
        options.saturation = demandees.contains("saturation")
        options.balance = demandees.contains("white_balance")
        options.doseForte = args.bool("strong_dose_requested") == true
        if args.has("strength") {
            guard let force = args.double("strength"), Reference.forces.contains(force) else {
                throw LightroomError.invalid("« strength » : de 0,25 à 1.")
            }
            options.force = force
        }
        let peau = args.bool("protect_skin") ?? true

        // Les photos : photo_ids, selection, collection ; sinon photo_id, ou la photo active.
        var ids: [Int?]
        var videos = 0, laissees = 0
        if args.has("photo_ids") || args.bool("selection") == true || args.has("collection") {
            let serie = try seriesPhotosSansVideos(args, maximum: Self.maxLookPhotos + 1)
            let sans = serie.ids.filter { $0 != reference }
            laissees = max(0, serie.total - serie.ids.count - serie.videos) + max(0, sans.count - Self.maxLookPhotos)
            ids = Array(sans.prefix(Self.maxLookPhotos)).map { $0 }
            videos = serie.videos
        } else {
            ids = [args.int("photo_id")]
        }
        if ids.count == 1, ids[0] == reference { throw LightroomError.invalid("La photo à traiter est la référence elle-même.") }
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à traiter (la référence est écartée).") }

        let confirme = args.bool("confirm") == true
        let titre = "rendu de la référence"
        let total = ids.count * (confirme ? 3 : 1) + 1
        var fait = 0
        avancer(0, sur: total, "Mesure de la référence", titre: titre)
        let ref = try lireRendu(reference, peau: peau)
        fait += 1
        var lignes: [JSONValue] = []
        var aVerifier: [JSONValue] = []
        for cible in ids {
            try contexte.verifier()
            var pentes = Reference.Pentes()
            let photo = try lireRendu(cible, peau: peau)
            if photo.id == reference { throw LightroomError.invalid("La photo active est la référence elle-même : donner photo_id.") }
            fait += 1
            avancer(fait, sur: total, "Mesure de \(photo.fichier.string ?? "la photo \(photo.id)")", titre: titre)
            let ecartAvant = Reference.ecart(photo: photo.signature, reference: ref.signature)
            var (reglages, limites) = Reference.traduire(ecartAvant, etat: photo.etat, options: options, pentes: pentes)
            var ligne: [String: JSONValue] = ["id": .number(Double(photo.id)), "fichier": photo.fichier,
                                              "ecart_avant": Reference.ecartJSON(ecartAvant, balance: options.balance)]
            if photo.signature.remarques.contains(where: { $0.hasPrefix("bandes") }) {
                limites.append("Bandes noires écartées de la mesure de la photo.")
            }
            if reglages.isEmpty {
                ligne["reglages"] = "aucun : déjà proche de la référence (ou rien de comparable)"
                if !limites.isEmpty { ligne["limites"] = .array(limites.map(JSONValue.string)) }
                lignes.append(.object(ligne))
                continue
            }
            ligne["reglages_proposes"] = .object(reglages.mapValues { .number(($0 * 100).rounded() / 100) })
            guard confirme else {
                if !limites.isEmpty { ligne["limites"] = .array(limites.map(JSONValue.string)) }
                lignes.append(.object(ligne))
                continue
            }
            var etapes: [JSONValue] = []
            var mesuree = photo
            var moyensReduits = false
            for passe in 1...2 {
                try contexte.verifier()
                let nom = "\(args.string("step_name").map(Self.withoutClaudePrefix).flatMap { $0.isEmpty ? nil : $0 } ?? "rendu de référence") : passe \(passe)"
                var reglagesArgs: [String: JSONValue] = ["settings": .object(reglages.mapValues { .number($0) })]
                if options.doseForte { reglagesArgs["strong_dose_requested"] = true }
                var (params, _) = try developParameters(Arguments(raw: reglagesArgs))
                params["photos"] = [.number(Double(photo.id))]
                var ecriture = writeParameters(Arguments(raw: ["step_name": .string(nom), "reason": args.raw["reason"] ?? .null, "confirm": true]),
                                               defaultStep: nom)
                ecriture["raison"] = ecriture["raison"] ?? .string("Rendu de la photo de référence.")
                params.merge(ecriture) { _, new in new }
                params["sans_avant_apres"] = true
                let reponse = try lightroom.send("appliquer", params, timeout: 180)
                if let remarques = reponse["resultats"]?.array?.first?["remarques"]?.array, !remarques.isEmpty {
                    limites += remarques.compactMap(\.string)
                }
                etapes.append(.string("Claude · " + nom))
                let avant = mesuree
                mesuree = try lireRendu(photo.id, visages: photo.visages, peau: peau)
                fait += 1
                avancer(min(fait, total), sur: total, "\(photo.fichier.string ?? "Photo \(photo.id)") : passe \(passe) mesurée", titre: titre)
                guard passe == 1 else { break }
                pentes = Reference.pentesObservees(pentes, avant: avant.etat, apres: reglages, mesureAvant: avant.signature, mesureApres: mesuree.signature)
                pentes.serie = Self.pentesObservees(pentes.serie, appliquee: Self.delta(reglages, avant.etat, ["Exposure2012", "Contrast2012"]),
                                                    avant: Self.commeSerie(avant), apres: Self.commeSerie(mesuree))
                // La passe 2 vise ce qui manque pour combler la part demandée (strength) de l'écart du
                // départ, pas une part de ce qui reste.
                let reste = Reference.ecart(photo: mesuree.signature, reference: ref.signature)
                var entiere = options
                entiere.force = 1
                var suite = Reference.traduire(Reference.ecartVise(reste: reste, avant: ecartAvant, force: options.force),
                                               etat: mesuree.etat, options: entiere, pentes: pentes)
                // La peau a bougé d'un écart qui se voit : la passe 2 rend la moitié du changement des tons moyens.
                if let p0 = photo.peau, let p1 = mesuree.peau, Teint.ecart(p1, p0) >= Teint.ecartVisible {
                    let cles = Reference.clesZones[1]
                    let gain = pentes.gain[1]
                    let v0 = Reference.vecteur(teinte: photo.etat.valeur(cles.teinte), saturation: photo.etat.valeur(cles.saturation), gain: gain)
                    let v1 = Reference.vecteur(teinte: mesuree.etat.valeur(cles.teinte), saturation: mesuree.etat.valeur(cles.saturation), gain: gain)
                    let moitie = v0 + 0.5 * (v1 - v0)
                    if (v1 - v0).norme > 0 {
                        suite.reglages[cles.teinte] = moitie.norme > 0 ? Reference.teinteLightroom(angle: atan2(moitie.b, moitie.a) * 180 / .pi).rounded().truncatingRemainder(dividingBy: 360) : mesuree.etat.valeur(cles.teinte)
                        suite.reglages[cles.saturation] = (moitie.norme / gain).rounded()
                        moyensReduits = true
                    }
                }
                suite.reglages = suite.reglages.filter { $0.value != mesuree.etat.valeur($0.key) }
                guard !suite.reglages.isEmpty else { break }
                reglages = suite.reglages
                limites += suite.limites.filter { !limites.contains($0) }
            }
            let ecartApres = Reference.ecart(photo: mesuree.signature, reference: ref.signature)
            ligne["etapes"] = .array(etapes)
            ligne["ecart_apres"] = Reference.ecartJSON(ecartApres, balance: options.balance)
            if let d0 = Reference.distance(ecartAvant, balance: options.balance), d0 > 0, let d1 = Reference.distance(ecartApres, balance: options.balance) {
                ligne["rapproche_pct"] = .number(((1 - d1 / d0) * 100).rounded())
            }
            if !limites.isEmpty { ligne["limites"] = .array(limites.map(JSONValue.string)) }
            if let p0 = photo.peau {
                var teint: [String: JSONValue] = ["avant": Teint.jsonReference(p0)]
                if let p1 = mesuree.peau {
                    let ecart = Teint.ecart(p1, p0)
                    teint["apres"] = Teint.jsonReference(p1)
                    teint["deplacement_ab"] = .number((ecart * 10).rounded() / 10)
                    if moyensReduits || ecart >= Teint.ecartVisible {
                        let texte = "La peau a bougé (écart a*b* \(PhotoTriee.r(ecart)))\(moyensReduits ? " : la passe 2 a rendu la moitié du changement des tons moyens" : "") ; vérifier à l'œil, view_photo avec region sur le visage."
                        teint["a_verifier"] = .string(texte)
                        aVerifier.append(["id": .number(Double(photo.id)), "fichier": photo.fichier, "pourquoi": .string(texte)])
                    }
                }
                ligne["teint"] = .object(teint)
            }
            lignes.append(.object(ligne))
        }
        var referenceJSON: [String: JSONValue] = ["id": .number(Double(reference)), "fichier": ref.fichier,
                                                  "signature": Reference.signatureJSON(ref.signature)]
        if peau { referenceJSON["teint"] = Teint.jsonReference(ref.peau) }
        var resultat: [String: JSONValue] = [
            "reference": .object(referenceJSON),
            "photos": .array(lignes),
            "base": .string("Écarts « référence moins photo » : exposition en IL (L* médiane), contraste (L* P95 − P5), chroma médiane, et pour chaque zone (ombres L* < \(Int(Reference.limites[0])), tons moyens, hautes lumières > \(Int(Reference.limites[1]))) la médiane a* (vert − / magenta +) et b* (bleu − / jaune +) de ses pixels peu saturés (C* < \(Int(Reference.chromaZone))), visages écartés, sans la part commune aux zones sauf avec white_balance ; distance = moyenne a*b* des zones. Pentes provisoires : la passe 2 corrige d'après la mesure."),
        ]
        if !aVerifier.isEmpty { resultat["a_verifier"] = .array(aVerifier) }
        if laissees > 0 {
            resultat["photos_non_traitees"] = .string("\(laissees) photo(s) laissée(s) de côté : au plus \(Self.maxLookPhotos) par appel ; la suite par photo_ids, ou copy_settings depuis une photo traitée puis match_series.")
        }
        if !confirme {
            resultat["rien_n_est_applique"] = "Plan seulement : le montrer à l'utilisateur ; avec son accord, rappeler match_look avec confirm = true (valeurs finales, mesurées puis reprises une fois)."
        }
        return Self.avecVideos(.object(resultat), videos)
    }

    /// Le changement relatif de quelques clés entre l'état et les valeurs finales (pour les pentes de
    /// match_series).
    static func delta(_ finales: [String: Double], _ etat: Reference.Etat, _ cles: [String]) -> [String: Double] {
        var d: [String: Double] = [:]
        for cle in cles { if let v = finales[cle] { d[cle] = v - etat.valeur(cle) } }
        return d
    }

    /// Une photo lue comme celles de match_series, pour reprendre ses pentes d'exposition et de contraste.
    static func commeSerie(_ photo: PhotoRendu) -> PhotoSerie {
        var mesures = Measurements.analyzeScaled(photo.image) ?? Measurements.analyze(rgba: [128, 128, 128, 255], count: 1)!
        // La médiane et le contraste de la signature (cadre utile, comme l'écart).
        for (p, v) in photo.signature.centiles { mesures.percentilesL[p] = v }
        return PhotoSerie(id: photo.id, fichier: photo.fichier, raw: photo.etat.raw, temperature: photo.etat.reglages["Temperature"],
                          mesures: mesures, neutres: nil)
    }
}
