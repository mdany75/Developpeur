import CoreGraphics
import Foundation
import Vision

/// Voir et mesurer : `view_photo` (aperçu, zoom sur une zone, avant/après, mesures, netteté et
/// bruit, éclairage, Vision, bilan d'une passe à l'autre), `measure_angle` (angle d'une ligne,
/// pour redresser), `analyze_photos` (mesures d'une série, écarts avec une référence, photos
/// semblables) et `get_settings`. view_photo et measure_angle envoient aussi leurs constats de la
/// prise de vue au carnet de progrès (1.3, Carnet.swift), quand le serveur y note.
extension ToolHandler {
    /// Taille des aperçus d'analyse : celle où les seuils de netteté et de bruit ont été relevés.
    static let analysisSize = Detail.side
    static let maxAnalyzedPhotos = 30
    /// Les avant/après de view_photo (compare) et le mode de la commande apercu (comparer) :
    /// claude_version (« Je le fais », 1.3) rend la version de Claude rangée par my_turn.
    static let comparaisons: [(parametre: String, module: String)] = [
        ("before_claude", "avantClaude"), ("previous_step", "etapePrecedente"), ("claude_version", "versionClaude"),
    ]

    var analysisDefinitions: [JSONValue] {
        [
            tool("view_photo",
                 "Montre la photo telle qu'elle est développée en ce moment (aperçu JPEG rendu par Lightroom avec les réglages actuels), avec ses données de prise de vue, ses réglages non nuls et des mesures objectives : luminosité L*, centiles, écrêtage (aussi par canal), contraste, dominante des tons neutres (aussi par zone tonale et par région : « eclairage » nomme un éclairage mixte, lampe et fenêtre, et dit quoi en faire) et de toute l'image (dominante_globale), netteté par zone et bruit ; et ce que voit Vision (visages et pupilles, qualité des visages, note esthétique, zone d'intérêt). À appeler avant de retoucher, puis après chaque passe. « bilan » : écarts chiffrés avec le view_photo précédent de la même photo à la même taille (avant → après, et depuis_le_debut) ; « regression » : un défaut apparu ou aggravé depuis (écrêtage, ombres bouchées, couleurs saturées, dominante, netteté ou bruit passés leur seuil) : le corriger par une passe ciblée, ou undo_last s'il vient de la dernière étape, et le dire ; « a_verifier » : un changement peut-être voulu. Mesures sur un JPEG sRGB (une couleur hors du sRGB y paraît écrêtée) ; en HDR (HDREditMode), le rendu SDR : le HDR ne se voit pas. « a_savoir » (calculs IA en attente) : le dire. « evaluation » : la note de Claude gardée pour la photo (pas encore évaluée, à vérifier, acceptée…). « intention_boitier » (fichiers Fujifilm, lue dans l'original) : simulation de film, plage dynamique, tons clairs et foncés, compensation d'exposition et mode choisis à la prise de vue, avec sa « lecture » : la suivre sauf autre demande (une nuit voulue sombre reste sombre ; un RAW part de la simulation choisie). region = zoom à 100 % sur une zone (netteté et bruit en pleine résolution, taches ; refait sur la même zone : bilan_zone) ; compare = avant/après côte à côte, avec son bilan.",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("size", prop("integer", "Grand côté de l'aperçu en pixels (défaut \(Self.defaultPreviewSize), de \(Self.previewSizes.lowerBound) à \(Self.previewSizes.upperBound)).")),
                    ("region", objectProp("Zone à voir en pleine résolution (zoom 100 %, réduit si elle dépasse \(PreviewImages.maxSide) px), en fractions de l'image affichée.", [
                        "x": prop("number", "Bord gauche (0 à 1)."),
                        "y": prop("number", "Bord haut (0 à 1)."),
                        "width": prop("number", "Largeur (0 à 1)."),
                        "height": prop("number", "Hauteur (0 à 1)."),
                    ], required: ["x", "y", "width", "height"])),
                    ("compare", enumProp(Self.comparaisons.map(\.parametre), "Avant/après côte à côte : before_claude = l'état d'avant la première retouche de Claude ; previous_step = avant la dernière retouche ; claude_version = « Je le fais » : à gauche la version de Claude rangée par preview_settings avec my_turn, à droite l'état actuel (celle de l'utilisateur), avec exercice : écarts réglage par réglage et ecart_principal. L'Historique de Lightroom garde deux étapes « Claude · comparaison » (l'état d'avant, puis l'état actuel remis) : la photo revient telle qu'elle était.")),
                    ("af_point", prop("boolean", "true = le point de mise au point de l'appareil dessiné sur l'image ou le zoom (region) : cadre AF rouge, point au centre (manquée : point_af.appareil) ; fichiers Fujifilm seulement. Pour noter, ou montrer la mise au point. Sans lui, point_af le donne en chiffres (avec la netteté autour ; sur un zoom, dans_la_zone) ; l'utilisateur peut le vouloir dessiné en tout temps.")),
                 ],
                 required: []),
            tool("measure_angle",
                 "Mesure l'angle exact d'une ligne qui devrait être horizontale ou verticale (horizon, crête d'une chute, ligne de toit, arête d'un bâtiment, poteau), pour redresser au dixième de degré : donner deux points sur la ligne, dans l'image telle que la montre view_photo ; le serveur affine l'angle sur le contour le long du segment. Choisir une ligne vraiment droite dans la réalité, pas une ligne de perspective (rambarde, route qui fuit). Renvoie l'inclinaison et l'angle de recadrage qui la corrige (crop.angle d'apply_settings).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("x1", prop("number", "Premier point de la ligne, depuis la gauche (0 à 1).")),
                    ("y1", prop("number", "Premier point, depuis le haut (0 à 1).")),
                    ("x2", prop("number", "Second point, depuis la gauche (0 à 1).")),
                    ("y2", prop("number", "Second point, depuis le haut (0 à 1).")),
                 ],
                 required: ["x1", "y1", "x2", "y2"]),
            tool("analyze_photos",
                 "Mesures objectives de plusieurs photos sans les afficher (luminosité L*, contraste, écrêtage, dominante (et éclairage mixte), saturation, netteté, bruit, visages, note esthétique), pour juger, trier ou harmoniser une série. Repère les photos semblables (rafales, quasi-doublons) et la meilleure de chaque groupe. Avec reference_id : écarts de chaque photo avec la référence et indications pour s'en rapprocher (l'exposition en IL ; pour la couleur et le contraste, un sens à vérifier).",
                 properties: targetProperties + [
                    ("reference_id", prop("integer", "Photo de référence (correspondance de couleur et d'exposition).")),
                 ],
                 required: []),
            tool("get_settings",
                 "Donne tous les réglages de développement actuels d'une photo, groupés comme dans le module Développement, avec l'échelle de la température, le profil, le recadrage, les courbes par points, les masques, les couleurs ponctuelles, les retouches de taches, et son classement dans la Bibliothèque (note, drapeau, libellé, titre, mots-clés).",
                 properties: [
                    ("photo_id", photoIDProperty),
                    ("all_keys", prop("boolean", "true = ajoute « tous_les_reglages » : tout ce que Lightroom range pour la photo, même les réglages que ce serveur ne connaît pas encore (pour explorer un outil de Lightroom appliqué à la main).")),
                 ], required: []),
        ]
    }

    func viewPhoto(_ args: Arguments) throws -> ToolResult {
        let requested = args.int("size") ?? Self.defaultPreviewSize
        let size = min(max(requested, Self.previewSizes.lowerBound), Self.previewSizes.upperBound)
        var params: [String: JSONValue] = [
            "taille": .number(Double(size)),
            "cles": .array(DevelopCatalogue.keys.map(JSONValue.string)),
        ]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }

        var region: CGRect?
        if let object = args.object("region") {
            func part(_ key: String) throws -> Double {
                guard let value = object[key]?.double, (0...1).contains(value) else {
                    throw LightroomError.invalid("« region.\(key) » va de 0 à 1.")
                }
                return value
            }
            let rect = CGRect(x: try part("x"), y: try part("y"), width: try part("width"), height: try part("height"))
            guard rect.width > 0.005, rect.height > 0.005, rect.maxX <= 1.0001, rect.maxY <= 1.0001 else {
                throw LightroomError.invalid("« region » doit tenir dans l'image (x + width ≤ 1, y + height ≤ 1).")
            }
            region = rect
            params["taille"] = 0
        }
        let compare = args.string("compare")
        if let compare {
            guard let mode = Self.comparaisons.first(where: { $0.parametre == compare })?.module else {
                throw LightroomError.invalid("« compare » vaut before_claude, previous_step ou claude_version (« Je le fais » : la version de Claude rangée par preview_settings avec my_turn).")
            }
            guard region == nil else { throw LightroomError.invalid("« compare » et « region » ne vont pas ensemble.") }
            params["comparer"] = .string(mode)
        }
        let exercice = compare == "claude_version"
        // Le point de mise au point, sur l'aperçu entier ou un zoom (pas un avant/après).
        if compare == nil { params["point_af"] = true }

        let result = try lightroom.send("apercu", params, timeout: region == nil ? 120 : 240)
        var image = try Self.readPreview(result["chemin"]?.string)
        // Une seule ouverture de l'original (Fujifilm) pour le point de mise au point et
        // l'intention de la prise de vue ; aucune pour un avant/après.
        let boitier = compare == nil ? Self.lectureBoitier(result["photo"], lecteur: lecteurBoitier) : nil
        let raw = result["echelle_temperature"]?.string?.hasPrefix("kelvins") == true
        var info = result.object ?? [:]
        info.removeValue(forKey: "chemin")
        info.removeValue(forKey: "chemin_avant")
        // Les étapes de Claude servent au bilan (il les dit), pas telles quelles à Claude.
        info.removeValue(forKey: "etapes_claude")
        // Ce qui sert au point de mise au point, pas à Claude.
        let afToujours = info.removeValue(forKey: "point_af_toujours")?.bool == true
        if var photo = info["photo"]?.object {
            photo.removeValue(forKey: "chemin_original")
            photo.removeValue(forKey: "geometrie")
            photo.removeValue(forKey: "marque")
            // Le numéro de série du boîtier sert aux rafales du tri (1.3.5), pas à Claude.
            photo.removeValue(forKey: "serie_boitier")
            // La sensibilité en nombre sert au carnet (bruit fort à ISO élevé) ; Claude a son texte (iso).
            photo.removeValue(forKey: "sensibilite")
            info["photo"] = .object(photo)
        }
        if let settings = result["reglages"]?.object {
            info["reglages"] = Self.grouped(settings, onlyChanged: true, raw: raw)
        }
        Self.describeProcessVersion(&info)
        // Après « Je le fais » (my_turn), corrections_utilisateur est le travail de l'exercice.
        JeLeFais.annoterCorrections(&info)

        if let region {
            guard let piece = PreviewImages.crop(image, region: region) else {
                throw LightroomError.plugin("Zone trop petite ou aperçu illisible.")
            }
            image = piece.data
            info["zoom"] = [
                "pourcentage": .number(Double(piece.zoom)),
                "pixels": .string("\(piece.width) × \(piece.height)"),
                "zone": ["x": .number(region.minX), "y": .number(region.minY), "width": .number(region.width), "height": .number(region.height)],
            ]
            if let measures = Measurements.analyze(piece.data) {
                var detail = Detail.analyze(piece.data, maxSide: PreviewImages.maxSide)
                detail?.zoom = true
                info["mesures_zone"] = Self.merged(measures.json, detail?.json)
                // Un zoom refait sur la même zone (même cadre, mêmes pixels) : ses chiffres bruts
                // comparés au précédent, sans alerte. Les vues entières du bilan n'y touchent pas.
                if let id = result["photo"]?["id"]?.int {
                    let zoom = Bilan.Zoom(zone: region, cadre: Bilan.cadre(result), pixels: "\(piece.width) × \(piece.height)",
                                          mesures: measures, detail: detail, quand: Date())
                    if let precedent = zoomsMesures[id]?.last(where: { $0.correspond(zoom) }) {
                        info["bilan_zone"] = Bilan.zone(avant: precedent, apres: zoom, date: zoom.quand)
                    }
                    garderZoom(zoom, photo: id)
                }
            }
            // Sur un zoom aussi (demandé par Dany le 20 octobre 2026 : un zoom pour voir la mise au
            // point ne la montrait pas) : le point dans l'image entière, et dans la zone s'il y tombe.
            if let af = Self.pointAF(boitier, description: result["photo"]) {
                let local = CGPoint(x: (af.point.x - region.minX) / region.width, y: (af.point.y - region.minY) / region.height)
                let dedans = (0...1).contains(local.x) && (0...1).contains(local.y)
                var point = Self.pointAFJSON(af.point, avertissement: af.avertissement)
                point["dans_la_zone"] = .bool(dedans)
                if dedans, let decodee = PreviewImages.image(piece.data) {
                    if let nettete = Detail.nettete(decodee, autour: local) { point["nettete"] = .number((nettete * 10).rounded() / 10) }
                    // Le cadre AF de l'onglet Focus ramené dans le zoom ; sans cadre lu, le carré d'avant.
                    let cadres = Self.cadresAF(boitier, description: result["photo"]).map { cadre -> Focus.Cadre in
                        var c = cadre
                        c.coins = cadre.coins.map { CGPoint(x: ($0.x - region.minX) / region.width, y: ($0.y - region.minY) / region.height) }
                        return c
                    }
                    if args.bool("af_point") == true || afToujours,
                       let marquee = cadres.isEmpty ? PreviewImages.marquerPoint(decodee, local, manque: af.avertissement)
                                                    : PreviewImages.marquerFocus(decodee, cadres: cadres) {
                        image = marquee
                        point["carre"] = .string(cadres.isEmpty ? (af.avertissement ? "rouge, sur le zoom" : "vert, sur le zoom")
                                                                : "cadre AF rouge, point au centre, sur le zoom")
                    }
                }
                info["point_af"] = .object(point)
            }
        } else if let compare {
            let before = try Self.readPreview(result["chemin_avant"]?.string)
            // « Je le fais » : un module d'avant la 1.3 prendrait versionClaude pour l'étape
            // précédente, sans le dire ; sa comparaison n'est pas montrée (ses deux aperçus sont lus,
            // donc effacés).
            if exercice, result["exercice"]?.object == nil {
                let version = lightroom.moduleVersion.map { " (version \($0))" } ?? ""
                throw LightroomError.plugin("Le module de Lightroom\(version) ne connaît pas encore « Je le fais » : installer Développeur 1.3, puis quitter et relancer Lightroom, et refaire l'exercice (preview_settings avec my_turn).")
            }
            // Deux vues rendues par la même commande, mesurées comme l'aperçu entier, avec la forme
            // courte de l'éclairage ; leur bilan, sans toucher aux vues gardées.
            let avant = Self.mesurerImage(before, detail: true), apres = Self.mesurerImage(image, detail: true)
            if let avant { info["mesures_avant"] = avant.json }
            if let apres { info["mesures"] = apres.json }
            if let avant, let apres {
                info["bilan"] = Bilan.avantApres(
                    avant: avant.mesures, apres: apres.mesures, detailAvant: avant.detail, detailApres: apres.detail,
                    depuis: exercice ? "ma version (Claude, à gauche)"
                        : compare == "before_claude" ? "l'état d'avant la première retouche de Claude (à gauche)"
                        : "l'état d'avant la dernière retouche (à gauche)",
                    conseil: exercice ? "Une « regression » est un défaut de la version de l'utilisateur que celle de Claude n'a pas : le lui dire simplement, sans toucher à la photo."
                        : "Une « regression » restée se dit dans le résumé.",
                    // Des images de dimensions différentes : recadrage, Upright ou rotation entre les deux.
                    cadreChange: avant.largeur != apres.largeur || avant.hauteur != apres.hauteur)
            }
            image = PreviewImages.sideBySide(before, image) ?? image
            info["image"] = exercice ? "À gauche ma version (Claude), à droite la vôtre." : "À gauche avant, à droite maintenant."
            // Les écarts de l'exercice, réglage par réglage (classés), et l'écart principal mesuré sur
            // les deux images : d'abord ce qui est réussi, puis l'écart qui compte.
            if exercice, let module = result["exercice"] {
                info["exercice"] = JeLeFais.enrichir(module, raw: raw, claude: avant?.mesures, vous: apres?.mesures)
            }
        } else if let decodee = PreviewImages.image(image) {
            // Un seul décodage du JPEG ; une seule réduction à 512 px pour les mesures, les tons
            // neutres suivis du bilan et l'éclairage ; le détail à 1024 px ; Vision une fois.
            let reduite = PreviewImages.scaled(decodee, maxSide: Measurements.maxSide)
            var measures = Measurements.analyze(reduite)
            let detail = Detail.analyze(PreviewImages.scaled(decodee, maxSide: Detail.side))
            let vision = VisionAnalysis.analyze(decodee)
            // L'éclairage, visages à part (ceux de Vision) ; son point neutre va aux mesures (la
            // dominante de toute l'image, gardée avec la vue pour le bilan).
            let eclairage = measures == nil ? nil
                : Eclairage.mesurer(reduite, visages: vision?.faces.map(\.box) ?? [], sujet: vision?.salientArea)
            measures?.pointNeutre = eclairage?.neutre
            if let measures {
                var mesures = Self.merged(measures.json, detail?.json)
                // Les balances proposées partent de la balance de la réponse brute (Temperature en
                // kelvins pour un RAW, pas regroupée).
                if let eclairage {
                    mesures = Self.merged(mesures, ["eclairage": eclairage.json(balance: Self.balanceProposee(eclairage, reponse: result))])
                }
                mesures = Self.conseilDominanteGlobale(mesures, balance: Self.balanceGlobale(measures, reponse: result))
                // Les points chauds (1.3.4) : sur l'aperçu entier seulement, hors des visages et de la
                // zone d'intérêt ; dits, jamais corrigés d'office.
                let sujet = (vision?.faces.map(\.box) ?? []) + [vision?.salientArea].compactMap { $0 }
                if let points = PointsChauds.json(PointsChauds.trouver(reduite, sujet: sujet)) {
                    mesures = Self.merged(mesures, ["points_chauds": points])
                }
                info["mesures"] = mesures
            }
            if let vision { info["vision"] = vision.json }
            info["taille_apercu"] = .number(Double(size))
            // Le bilan d'une passe à l'autre, sur la réponse brute (géométrie de la photo, réglages
            // à plat, étapes de Claude) et avant le carré du point de mise au point.
            if let measures, let bilan = bilanDeLaVue(apercu: result, taille: size, mesures: measures, detail: detail, reduite: reduite) {
                info["bilan"] = bilan
            }
            let af = Self.pointAF(boitier, description: result["photo"])
            // Netteté et texture autour du point, mesurées avant le carré : sur une zone sans texture
            // (ciel, sable lisse), la mise au point ne se juge pas (DetailMeasurements.textureMin).
            let miseAuPoint = af.map { PhotoTriee.MiseAuPoint.mesuree(decodee, point: $0.point, avertissement: $0.avertissement) }
            let netteteAF = miseAuPoint?.nettete
            // Le carnet de progrès (1.3) : sur une photo que Claude n'a pas encore retouchée, les
            // défauts de la prise de vue, mesurés avant le carré du point de mise au point ; dits à
            // Claude seulement si le module les a notés.
            if let constats = noterLaVue(apercu: result, mesures: measures, detail: detail, reduite: reduite,
                                         af: miseAuPoint,
                                         intention: boitier?.intention), !constats.isEmpty {
                info["constats_prise_de_vue"] = .array(constats.map(JSONValue.string))
            }
            // Le point de mise au point de l'appareil (Fujifilm) : toujours en chiffres, en carré
            // sur l'image avec af_point (pour noter) ou si l'utilisateur le veut en tout temps
            // (préférence du module). Les mesures sont prises avant le carré.
            if let af {
                var point = Self.pointAFJSON(af.point, avertissement: af.avertissement)
                if let nettete = netteteAF { point["nettete"] = .number((nettete * 10).rounded() / 10) }
                if miseAuPoint?.jugeable == false {
                    point["mise_au_point"] = "non jugée : zone sans texture autour du point (ciel, sable, mur) ; regarder la netteté du sujet"
                }
                // Le cadre AF comme l'onglet Focus (rouge, à sa taille, point au centre) ; sans cadre
                // lu, le carré d'avant (vert, rouge si manquée).
                let cadres = Self.cadresAF(boitier, description: result["photo"])
                if args.bool("af_point") == true || afToujours,
                   let marquee = cadres.isEmpty ? PreviewImages.marquerPoint(decodee, af.point, manque: af.avertissement)
                                                : PreviewImages.marquerFocus(decodee, cadres: cadres) {
                    image = marquee
                    point["carre"] = .string(cadres.isEmpty ? (af.avertissement ? "rouge, sur l'image" : "vert, sur l'image")
                                                            : "cadre AF rouge, point au centre, sur l'image")
                }
                info["point_af"] = .object(point)
            }
            // L'intention de la prise de vue (Fujifilm), sur l'aperçu entier seulement.
            if let intention = boitier?.intention {
                info["intention_boitier"] = intention.json(raw: raw, profil: raw ? profilDuBoitier(intention, appareil: result["appareil"]) : nil,
                                                           profilActuel: result["profil"]?.string)
            }
        }
        return ToolResult(content: [Self.imageContent(image), .text(JSONCoding.pretty(.object(info)))])
    }

    /// Le bilan d'un view_photo sur l'aperçu entier (Bilan.swift) : la vue de cette réponse,
    /// comparée à la précédente de la même photo à la même taille d'aperçu (et à la première), puis
    /// gardée à sa place. `apercu` : la réponse brute du module (géométrie de la photo, réglages à
    /// plat, étapes de Claude), lue avant les retraits ; `reduite` : l'aperçu réduit à 512 px des
    /// mesures. Nil sans identifiant de photo.
    func bilanDeLaVue(apercu: JSONValue, taille: Int, mesures: PhotoMeasurements, detail: DetailMeasurements?,
                      reduite: CGImage, quand: Date = Date()) -> JSONValue? {
        guard let vue = Bilan.Vue(apercu: apercu, quand: quand, taille: taille, mesures: mesures, detail: detail,
                                  neutres: Measurements.neutres(reduite)) else { return nil }
        let cle = Bilan.Cle(photo: vue.photo, taille: taille)
        // Un autre fichier sous le même identifiant (un autre catalogue) : un nouveau départ.
        guard let suivi = vuesMesurees[cle], suivi.precedente.fichier == vue.fichier else {
            for (autre, ancien) in vuesMesurees where autre.photo == vue.photo && ancien.precedente.fichier != vue.fichier {
                vuesMesurees.removeValue(forKey: autre)
            }
            let autresTailles = vuesMesurees.keys.filter { $0.photo == vue.photo && $0.taille != taille }.map(\.taille)
            vuesMesurees[cle] = Bilan.Suivi(depart: vue, precedente: vue)
            Bilan.elaguer(&vuesMesurees)
            return .string(Bilan.premiereVue(taille: taille, autresTailles: autresTailles))
        }
        // Les tons neutres de cette vue sur les pixels choisis aux vues d'avant, à cadre égal
        // seulement (un autre cadre déplace les pixels).
        func suivis(_ autre: Bilan.Vue) -> Measurements.NeutresSuivis? {
            guard autre.cadre == vue.cadre, let masque = autre.neutres?.masque else { return nil }
            return Measurements.neutres(reduite, masque: masque)
        }
        let json = Bilan.session(precedente: suivi.precedente, depart: suivi.depart, maintenant: vue,
                                 suiviPrecedente: suivis(suivi.precedente), suiviDepart: suivis(suivi.depart), date: quand)
        vuesMesurees[cle] = Bilan.Suivi(depart: suivi.depart, precedente: vue)
        Bilan.elaguer(&vuesMesurees)
        return json
    }

    // MARK: Carnet de progrès

    /// Envoie un constat au carnet du module (commande carnet constater, avec le vocabulaire de
    /// PriseDeVue) : `constat` est { vue: … } ou { angle: … }. Vrai si le module l'a noté. Un refus
    /// (note = false : case Carnet décochée, photo d'essai, déjà retouchée, géométrie touchée) est
    /// normal, et toute erreur est tue (un module 1.2 répond « Commande inconnue ») : l'outil
    /// réussit quand même. Rien n'est écrit dans le catalogue, seulement carnet.json.
    func constaterAuCarnet(photo: Int, _ constat: [String: JSONValue]) -> Bool {
        var params: [String: JSONValue] = ["action": "constater", "photo": .number(Double(photo)), "vocabulaire": PriseDeVue.vocabulaire]
        params.merge(constat) { _, nouveau in nouveau }
        do {
            return try lightroom.send("carnet", params, timeout: Carnet.delaiConstat)["note"]?.bool == true
        } catch {
            Carnet.journaliser("carnet de progrès : constat de la photo \(photo) non noté (\(error.localizedDescription))")
            return false
        }
    }

    /// La vue entière de view_photo au carnet : seulement quand le serveur note au carnet
    /// (`noterAuCarnet`), pour une photo identifiée sans étape de Claude (etapes_claude.nombre == 0,
    /// que le module donne avec point_af), et que l'utilisateur n'a pas changée à la main depuis le
    /// dernier état laissé par Claude (corrections_utilisateur : après « Je le fais », ou des étapes
    /// défaites puis des réglages faits à la main, elle n'est plus telle que prise, et sa vue
    /// remplacerait celle d'avant). Ni sur une image rendue avant la fin des calculs IA (a_savoir) :
    /// elle ne montre pas l'état de la photo (le module ne la garde pas non plus pour l'avant/après,
    /// ni le bilan pour une « regression »). L'horizon n'y est cherché que sur une géométrie intacte
    /// (réglages et angle de recadrage de la réponse), le bruit qu'à un ISO connu et élevé
    /// (`Carnet.iso`, `Carnet.bruitCherche`). Rend les textes des défauts trouvés si le module a noté
    /// la vue, nil sinon.
    func noterLaVue(apercu: JSONValue, mesures: PhotoMeasurements?, detail: DetailMeasurements?, reduite: CGImage,
                    af: PhotoTriee.MiseAuPoint?, intention: IntentionBoitier?) -> [String]? {
        guard noterAuCarnet, let id = apercu["photo"]?["id"]?.int, apercu["etapes_claude"]?["nombre"]?.int == 0,
              apercu["corrections_utilisateur"]?.object == nil, apercu["a_savoir"]?.isNull ?? true else { return nil }
        let intacte = Carnet.geometrieIntacte(reglages: apercu["reglages"], angleRecadrage: apercu["recadrage"]?["angle"]?.double ?? 0)
        let vue = Carnet.constatsVue(mesures: mesures, detail: detail, reduite: reduite, af: af, intention: intention,
                                     iso: Carnet.iso(photo: apercu["photo"], priseDeVue: apercu["prise_de_vue"]), geometrieIntacte: intacte)
        guard !vue.cherches.isEmpty, constaterAuCarnet(photo: id, ["vue": vue.json]) else { return nil }
        return vue.textes
    }

    /// Une ligne mesurée (measure_angle, read_composition) au carnet, si elle compte
    /// (`Carnet.constatHorizon` : horizontale penchée de 0,5° ou plus, géométrie intacte). Rend le
    /// texte du constat si le module l'a noté, nil sinon.
    func noterLAngle(apercu: JSONValue, tilt: Double, vertical: Bool, angleActuel: Double, source: String) -> String? {
        guard noterAuCarnet, let id = apercu["photo"]?["id"]?.int,
              let constat = Carnet.constatHorizon(tilt: tilt, vertical: vertical, angleActuel: angleActuel, reglages: apercu["reglages"]),
              constaterAuCarnet(photo: id, ["angle": Carnet.angleJSON(constat, source: source)]) else { return nil }
        return constat.texte
    }

    /// Les clés de la commande apercu d'une ligne mesurée : celles de la géométrie quand le constat
    /// peut partir au carnet (pour juger qu'elle est intacte), aucune sinon.
    var clesDeLaLigne: JSONValue {
        noterAuCarnet ? .array(Carnet.clesGeometrie.map(JSONValue.string)) : []
    }

    /// Garde un zoom pour le suivant sur la même zone : `Bilan.zoomsGardes` par photo, et
    /// `Bilan.photosGardees` photos au plus (part celle dont le dernier zoom est le plus ancien).
    func garderZoom(_ zoom: Bilan.Zoom, photo: Int) {
        zoomsMesures[photo] = Bilan.ajouter(zoom, a: zoomsMesures[photo] ?? [])
        guard zoomsMesures.count > Bilan.photosGardees,
              let ancienne = zoomsMesures.min(by: { ($0.value.last?.quand ?? .distantPast) < ($1.value.last?.quand ?? .distantPast) })?.key
        else { return }
        zoomsMesures.removeValue(forKey: ancienne)
    }

    /// Une image (aperçu d'avant/après, proposition) mesurée comme l'aperçu entier de view_photo :
    /// un décodage, la réduction à 512 px, et la forme courte de l'éclairage ; le détail (netteté
    /// et bruit) pour une vue seulement, au bilan.
    struct ImageMesuree {
        var largeur: Int
        var hauteur: Int
        var mesures: PhotoMeasurements
        var detail: DetailMeasurements?
        var eclairage: MesureEclairage?

        /// Les mesures et l'éclairage, sans le détail (qui ne sert qu'au bilan).
        var json: JSONValue {
            ToolHandler.merged(mesures.json, eclairage.map { ["eclairage": $0.json(balance: nil, court: true)] })
        }
    }

    static func mesurerImage(_ data: Data, detail: Bool) -> ImageMesuree? {
        guard let image = PreviewImages.image(data) else { return nil }
        let reduite = PreviewImages.scaled(image, maxSide: Measurements.maxSide)
        guard var mesures = Measurements.analyze(reduite) else { return nil }
        let eclairage = Eclairage.mesurer(reduite)
        mesures.pointNeutre = eclairage?.neutre
        return ImageMesuree(largeur: image.width, hauteur: image.height, mesures: mesures,
                            detail: detail ? Detail.analyze(PreviewImages.scaled(image, maxSide: Detail.side)) : nil,
                            eclairage: eclairage)
    }

    /// Ce que l'aperçu entier de view_photo ajoute à couleur › dominante_globale : la balance qui la
    /// ramène au gris et quoi en faire. Rien sans dominante globale.
    static func conseilDominanteGlobale(_ mesures: JSONValue, balance: (temperature: Double, tint: Double)?) -> JSONValue {
        guard var objet = mesures.object, var couleur = objet["couleur"]?.object,
              var globale = couleur["dominante_globale"]?.object else { return mesures }
        if let balance {
            globale["balance_proposee"] = [
                "Temperature": .number(balance.temperature),
                "Tint": .number(balance.tint),
                "remarque": "un seul calcul, d'après les pentes de match_series : pour un grand écart, il dépasse souvent la cible ; white_balance_point avec scene la remesure",
            ]
        }
        globale["conseil"] = .string(conseilDominante)
        couleur["dominante_globale"] = .object(globale)
        objet["couleur"] = .object(couleur)
        return .object(objet)
    }

    static let conseilDominante = "À confirmer à l'œil : une lumière voulue (coucher de soleil, lampe) ou une scène aux couleurs franches "
        + "(sable, bois) décale aussi le point neutre. Si un blanc ou un gris de la scène la montre (vêtement blanc, chemin, mur, "
        + "nuages) : la corriger en première passe, avant le reste, par apply_settings avec white_balance_point (deux passes "
        + "mesurées) : {scene: true} pour toute l'image, ou {x, y} sur un gris terne (un blanc vif peut dépasser la chroma "
        + "admise) ; un écart de 1 000 K ou plus est normal (ombre, ciel couvert, lampe). Puis view_photo : dominante_globale "
        + "disparaît, la peau est naturelle."

    /// Le profil de Lightroom de la simulation choisie au boîtier, pour l'appareil de la photo
    /// (`appareil` de l'aperçu : marque, modèle) : profil DCP du catalogue ou Look installé ; nil
    /// sinon (la lecture le dit).
    func profilDuBoitier(_ intention: IntentionBoitier, appareil: JSONValue?) -> String? {
        intention.profilLightroom(marque: appareil?["marque"]?.string, modele: appareil?["modele"]?.string, looks: lookProfiles)
    }

    /// Le point de mise au point dans l'image affichée entière (de 0 à 1), et l'avertissement de
    /// l'appareil.
    static func pointAFJSON(_ point: CGPoint, avertissement: Bool) -> [String: JSONValue] {
        var json: [String: JSONValue] = ["x": .number((Double(point.x) * 1000).rounded() / 1000),
                                         "y": .number((Double(point.y) * 1000).rounded() / 1000)]
        if avertissement { json["appareil"] = "mise au point signalée manquée" }
        return json
    }

    /// Les clés de `extra` ajoutées à l'objet `base`.
    static func merged(_ base: JSONValue, _ extra: JSONValue?) -> JSONValue {
        guard var object = base.object else { return base }
        for (key, value) in extra?.object ?? [:] { object[key] = value }
        return .object(object)
    }

    func measureAngle(_ args: Arguments) throws -> JSONValue {
        func coordinate(_ key: String) throws -> Double {
            guard let value = args.double(key), (0...1).contains(value) else {
                throw LightroomError.invalid("« \(key) » va de 0 à 1 (fraction de l'image affichée).")
            }
            return value
        }
        let from = CGPoint(x: try coordinate("x1"), y: try coordinate("y1"))
        let to = CGPoint(x: try coordinate("x2"), y: try coordinate("y2"))
        var params: [String: JSONValue] = ["taille": .number(Double(Self.defaultPreviewSize)), "cles": clesDeLaLigne]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        let result = try lightroom.send("apercu", params, timeout: 120)
        let data = try Self.readPreview(result["chemin"]?.string)
        guard let line = LineAngle.measure(data, from: from, to: to) else {
            throw LightroomError.invalid("Segment trop court : choisir deux points éloignés sur la ligne (au moins un cinquième de l'image).")
        }
        func r(_ value: Double, _ step: Double = 0.05) -> JSONValue { .number((value / step).rounded() * step) }
        let current = result["recadrage"]?["angle"]?.double ?? 0
        let proposed = current + line.correction
        var output: [String: JSONValue] = [
            "photo": result["photo"] ?? .null,
            "ligne": .string(line.vertical ? "verticale" : "horizontale"),
            "angle_d_apres_les_points": r(line.pointsAngle),
            "inclinaison": r(line.tilt),
            "angle_de_recadrage_actuel": r(current),
            "crop_angle": r(proposed),
            "base": .string("Degrés. Inclinaison positive : la ligne tourne dans le sens antihoraire (une horizontale monte vers la droite). crop_angle = l'angle de recadrage qui la met d'aplomb : apply_settings avec crop {\"angle\": crop_angle}, en redonnant aspect, size, center_x et center_y si la photo est recadrée. Sous 0,5°, l'inclinaison ne se voit pas."),
        ]
        if let refined = line.refinedAngle {
            output["angle_mesure"] = r(refined)
            output["mesure"] = .string("affinée sur \(line.edgePoints) points du contour (écart moyen \(DevelopCatalogue.format(((line.residual ?? 0) * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")) px)")
        } else if line.contourIrregulier {
            output["mesure"] = .string("d'après les deux points seulement : le contour le long du segment est trop irrégulier pour être une ligne (écart moyen \(DevelopCatalogue.format(((line.residual ?? 0) * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",")) px, au-delà de \(DevelopCatalogue.format(LineAngle.ecartMax).replacingOccurrences(of: ".", with: ",")) px), vérifier par un zoom")
        } else {
            output["mesure"] = .string("d'après les deux points seulement : aucun contour net le long du segment, vérifier par un zoom")
        }
        // Le carnet de progrès (1.3) : une horizontale penchée sur une géométrie intacte.
        if let constat = noterLAngle(apercu: result, tilt: line.tilt, vertical: line.vertical, angleActuel: current, source: "measure_angle") {
            output["constats_prise_de_vue"] = [.string(constat)]
        }
        return .object(output)
    }

    func analyzePhotos(_ args: Arguments) throws -> JSONValue {
        var ids = try args.intList("photo_ids") ?? []
        var nonMesurees = 0
        if ids.isEmpty {
            let limit = Self.maxAnalyzedPhotos
            let selection = try lightroom.send(args.bool("selection") == true ? "selection" : "etat",
                                               args.bool("selection") == true ? ["limite": .number(Double(limit))] : [:], timeout: 30)
            if let photos = selection["photos"]?.array {
                ids = photos.compactMap { $0["id"]?.int }
                // Une sélection plus longue que la limite : les photos laissées de côté sont dites.
                nonMesurees = max(0, (selection["total"]?.int ?? ids.count) - ids.count)
            } else if let active = selection["photo_active"]?["id"]?.int {
                ids = [active]
            }
        }
        guard !ids.isEmpty else { throw LightroomError.invalid("Aucune photo à mesurer : donner photo_ids ou selection = true.") }
        guard ids.count <= Self.maxAnalyzedPhotos else {
            throw LightroomError.invalid("Au plus \(Self.maxAnalyzedPhotos) photos par appel.")
        }

        // Un seul décodage du JPEG par photo, pour les mesures, le détail, Vision et l'empreinte.
        func measure(_ id: Int) throws -> (description: JSONValue, measures: PhotoMeasurements, image: CGImage) {
            let result = try lightroom.send("apercu", ["photo": .number(Double(id)), "taille": .number(Double(Self.analysisSize)), "cles": []], timeout: 120)
            let data = try Self.readPreview(result["chemin"]?.string)
            guard let image = PreviewImages.image(data), let measures = Measurements.analyzeScaled(image) else {
                throw LightroomError.plugin("Aperçu illisible pour la photo \(id).")
            }
            return (result["photo"] ?? .object(["id": .number(Double(id))]), measures, image)
        }

        var reference: (description: JSONValue, measures: PhotoMeasurements, image: CGImage)?
        if let referenceID = args.int("reference_id") { reference = try measure(referenceID) }
        var photos: [JSONValue] = []
        var candidates: [SeriesCandidate] = []
        for id in ids {
            let (description, measures, image) = try measure(id)
            var item: [String: JSONValue] = [
                "id": .number(Double(id)),
                "fichier": description["fichier"] ?? .null,
                "mesures": measures.json,
            ]
            let detail = Detail.analyze(PreviewImages.scaled(image, maxSide: Detail.side))
            if let detail {
                item["nettete"] = ["max": .number((detail.sharpest * 10).rounded() / 10), "lecture": .string(detail.sharpnessReading)]
                item["bruit"] = ["aplats": .number((detail.noise * 100).rounded() / 100), "lecture": .string(detail.noiseReading)]
            }
            let vision = VisionAnalysis.analyze(image)
            // L'éclairage, en trois mots : mixte ou non, l'écart entre zones et sa lecture.
            if let eclairage = Eclairage.mesurer(image, visages: vision?.faces.map(\.box) ?? [], sujet: vision?.salientArea) {
                var resume: [String: JSONValue] = ["mixte": .bool(eclairage.mixte), "lecture": .string(eclairage.lecture)]
                if let ecart = eclairage.ecartRegions { resume["ecart_regions"] = .number((ecart * 10).rounded() / 10) }
                item["eclairage"] = .object(resume)
            }
            if let vision {
                var summary: [String: JSONValue] = ["visages": .number(Double(vision.faces.count))]
                if let best = vision.faces.compactMap(\.quality).max() { summary["qualite_visage_max"] = .number((best * 100).rounded() / 100) }
                if let aesthetics = vision.aesthetics { summary["esthetique"] = .number((aesthetics * 100).rounded() / 100) }
                item["vision"] = .object(summary)
            }
            candidates.append(SeriesCandidate(id: id, detail: detail, vision: vision, featurePrint: VisionAnalysis.featurePrint(image)))
            if let reference, id != args.int("reference_id") {
                item["ecart_avec_reference"] = Measurements.compare(measures, toReference: reference.measures)
            }
            photos.append(.object(item))
        }
        var result: [String: JSONValue] = ["photos": .array(photos)]
        if nonMesurees > 0 {
            result["photos_non_mesurees"] = .number(Double(nonMesurees))
            result["remarque"] = .string("\(nonMesurees) photo(s) de la sélection non mesurée(s) : au plus \(Self.maxAnalyzedPhotos) par appel ; les mesurer par photo_ids, par lots.")
        }
        if let reference {
            result["reference"] = ["fichier": reference.description["fichier"] ?? .null, "mesures": reference.measures.json]
        }
        if candidates.count > 1 {
            let groups = VisionAnalysis.groups(candidates.map(\.featurePrint))
            result["photos_semblables"] = .array(groups.map { members in
                let best = members.max { candidates[$0].score < candidates[$1].score } ?? members[0]
                return [
                    "photos": .array(members.map { .number(Double(candidates[$0].id)) }),
                    "meilleure": .number(Double(candidates[best].id)),
                    "pourquoi": .string(candidates[best].reason),
                ]
            })
            result["base_semblables"] = .string("Photos semblables : même scène d'après Vision (rafale, quasi-doublon, même photo recadrée). « meilleure » : la plus nette, au meilleur visage et à la meilleure note esthétique ; à confirmer à l'œil avant de trier.")
        }
        return .object(result)
    }

    /// Une photo d'une série, pour choisir la meilleure d'un groupe de photos semblables.
    struct SeriesCandidate {
        var id: Int
        var detail: DetailMeasurements?
        var vision: VisionReport?
        var featurePrint: VNFeaturePrintObservation?

        /// Une photo floue passe derrière ; puis la note esthétique (à demi-poids, comme l'ordre de
        /// lecture du tri) et la qualité du meilleur visage, qui départage des photos semblables
        /// (même sujet) : comme `PhotoTriee.scoreDansGroupe`.
        var score: Double {
            let sharp = min((detail?.sharpest ?? 0) / 60, 1)
            let face = vision?.faces.compactMap(\.quality).max() ?? 0
            return sharp + Tri.poidsEsthetique * (vision?.aesthetics ?? 0) + 0.5 * face
        }

        var reason: String {
            var parts: [String] = []
            if let detail { parts.append("netteté \(DevelopCatalogue.format((detail.sharpest).rounded()))") }
            if let face = vision?.faces.compactMap(\.quality).max() { parts.append("visage \(DevelopCatalogue.format((face * 100).rounded() / 100))") }
            if let aesthetics = vision?.aesthetics { parts.append("note esthétique \(DevelopCatalogue.format((aesthetics * 100).rounded() / 100))") }
            return parts.isEmpty ? "aucune mesure" : parts.joined(separator: ", ")
        }
    }

    func getSettings(_ args: Arguments) throws -> JSONValue {
        var params: [String: JSONValue] = ["cles": .array(DevelopCatalogue.keys.map(JSONValue.string)), "details": true]
        if let id = args.int("photo_id") { params["photo"] = .number(Double(id)) }
        if args.bool("all_keys") == true { params["toutes"] = true }
        var result = try lightroom.send("reglages", params, timeout: 30).object ?? [:]
        if let settings = result["reglages"]?.object {
            result["reglages"] = Self.grouped(settings, onlyChanged: false)
        }
        if let all = result.removeValue(forKey: "tous") {
            result["tous_les_reglages"] = all
        }
        Self.describeProcessVersion(&result)
        JeLeFais.annoterCorrections(&result)
        return .object(result)
    }

    /// « 11.0 » → « version 5 (11.0) », et ce qu'il faut savoir d'une version ancienne.
    static func describeProcessVersion(_ info: inout [String: JSONValue]) {
        guard let value = info["version_processus"]?.string, let version = DevelopCatalogue.processVersion(value) else { return }
        info["version_processus"] = .string("version \(version) (\(value))")
        let current = DevelopCatalogue.currentProcessVersion.version
        guard version < current else { return }
        info["version_processus_ancienne"] = .string(version < 3
            ? "Version \(version) (2003 ou 2010) : les réglages *2012 et les outils récents ne s'y appliquent pas ; la mettre à jour à la main dans Lightroom (Paramètres › Mettre à jour vers la version de processus actuelle), en comparant : un module ne peut pas convertir ses curseurs."
            : "Version \(version) : process_version = \(current) la met à jour (rendu qui peut changer nettement : preview_settings d'abord, puis l'accord de l'utilisateur).")
    }
}
