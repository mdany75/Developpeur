import CoreGraphics
import Foundation

/// Bilan chiffré d'une passe à l'autre (view_photo, 1.2) : ce qui a bougé entre deux aperçus
/// d'une même photo (exposition en IL, contraste, écrêtage, dominante, saturation, netteté,
/// bruit), « avant → après », puis ce qui demande l'attention : une « regression » (un défaut
/// apparu ou aggravé depuis) ou un changement « a_verifier » (peut-être voulu : dominante
/// inversée, aller-retour d'une passe à l'autre, coins vides, annulation, calcul IA en attente).
/// Fonctions pures : les vues gardées pour la session sont à `ToolHandler`.
///
/// Seuils d'écart visible repris de match_series (`ToolHandler.seuilExposition`, `seuilContraste`,
/// `seuilDominante`), de `Measurements.seuilChroma` et de `Detail` (netteté 15 et 35, bruit 0,6
/// et 1,5). Seuils de régression de l'écrêtage, des ombres, des couleurs saturées et de la
/// dominante relevés le 20 octobre 2026 ; ceux de la netteté et du bruit, provisoires, à relever
/// (deux vues, avant et après une étape écrite puis défaite : étape « bilan chiffré » de la recette).
///
/// Ne se comparent que des mesures prises de même : deux vues de même taille (deux view_photo de
/// suite à la même taille donnent les mêmes 43 mesures ; d'une taille à l'autre, la netteté
/// varie jusqu'à 10 %), ou les deux images d'un même avant/après (view_photo avec compare, ou une
/// proposition et l'état actuel) ; jamais une proposition à une vue gardée. Netteté et bruit
/// seulement entre deux vues : une proposition n'en a pas.
enum Bilan {
    /// Ce qu'un view_photo sur l'aperçu entier laisse au bilan du suivant.
    struct Vue {
        var photo: Int
        var fichier: String
        var quand: Date
        /// Grand côté de l'aperçu demandé, en pixels : netteté et bruit ne se comparent qu'à taille égale.
        var taille: Int
        /// Empreintes du cadre (`Bilan.cadre`) et de l'état (`Bilan.etat`).
        var cadre: String
        var etat: String
        /// Étapes de Claude gardées pour la photo (`etapes_claude` du module) : nil avec un module
        /// d'avant la 1.2.
        var etapes: Int?
        var derniereEtape: String?
        var mesures: PhotoMeasurements
        var detail: DetailMeasurements?
        /// Tons neutres choisis sur cette vue (`Measurements.neutres`), suivis à la suivante.
        var neutres: Measurements.NeutresSuivis?
        /// Calculs IA en attente au rendu (« a_savoir ») : l'image peut changer sans réglage.
        var iaEnAttente: Bool
        /// Ce que l'utilisateur a retouché à la main depuis la dernière commande de Claude
        /// (`corrections_utilisateur` du module, en empreinte) ; nil sans retouche à la main. Le
        /// module le redonne à chaque aperçu jusqu'à la commande suivante de Claude : seul un
        /// changement d'une vue à l'autre peut expliquer un écart.
        var corrections: String?
        /// GrainAmount : un grain ajouté se mesure comme du bruit.
        var grain: Double
    }

    /// Le premier view_photo d'une photo dans la session (point de départ) et le dernier.
    struct Suivi {
        var depart: Vue
        var precedente: Vue
    }

    /// Un zoom à 100 % (view_photo avec region) : ses mesures, pour le zoom suivant sur la même zone.
    struct Zoom {
        var zone: CGRect
        var cadre: String
        /// « l × h » de `PreviewImages.crop`.
        var pixels: String
        var mesures: PhotoMeasurements
        var detail: DetailMeasurements?
        var quand: Date
    }

    /// Un défaut par genre : une régression déjà signalée ne se redit pas dans depuis_le_debut.
    enum Defaut: Hashable {
        case ecretage, canal, ombres, saturees, dominante, nettete, bruit
    }

    /// Les vues gardées d'une photo à une taille d'aperçu : le bilan ne compare que des aperçus de
    /// même taille.
    struct Cle: Hashable {
        var photo: Int
        var taille: Int
    }

    /// Vues gardées (photo et taille ; la plus ancienne part), et zooms gardés par photo.
    static let photosGardees = 30, zoomsGardes = 6
    /// Deux zooms visent la même zone quand chaque coordonnée tombe à cette distance près.
    static let toleranceZone = 0.002

    // MARK: Seuils

    /// Seuils de visibilité repris : sous eux, un écart ne se voit pas.
    static let seuilExposition = ToolHandler.seuilExposition, seuilContraste = ToolHandler.seuilContraste,
               seuilDominante = ToolHandler.seuilDominante, seuilChroma = Measurements.seuilChroma

    /// Seuils de visibilité neufs : écrêtage, en points de % ; part très saturée, en points ;
    /// netteté, en % de celle d'avant ; bruit, en niveaux sur 255. Au-dessus du plancher de deux
    /// vues de même taille, nul (relevé le 20 octobre 2026 sur les 8 copies « Essai ») ; leur
    /// valeur reste provisoire.
    static let ecartEcretage = 0.3, ecartSaturee = 1.0, ecartNettetePct = 10.0, ecartBruit = 0.1

    /// Un seuil de régression : la part d'après monte d'au moins `hausseMin` points et atteint au
    /// moins `facteurMin` fois celle d'avant.
    struct Seuil {
        var hausseMin: Double
        var facteurMin = 1.0

        func franchi(_ avant: Double, _ apres: Double) -> Bool {
            // Une marge d'arrondi : en binaire, 2,4 − 0,4 vaut 1,999…
            apres - avant >= hausseMin - 1e-9 && apres >= facteurMin * avant - 1e-9
        }
    }

    /// Seuils de régression relevés le 20 octobre 2026, en propositions sur les copies « Essai »
    /// (Exposure +0,3 à +1,5, Whites +30 et +60, Blacks −30 et −60, Contrast +40, Vibrance +40,
    /// Saturation +30, Dehaze +30 ; écarts d'une proposition à une vue jusqu'à 0,9 point
    /// d'écrêtage, à dépasser). Écrêtage, canal et couleurs très saturées : 2 points de plus, et au
    /// moins 1,5 fois l'avant. Ombres bouchées : 2 points de plus ; une nuit n'alerte pas d'elle-même
    /// (le seuil porte sur l'écart, pas sur la valeur).
    static let regressionEcretage = Seuil(hausseMin: 2, facteurMin: 1.5)
    static let regressionCanal = Seuil(hausseMin: 2, facteurMin: 1.5)
    static let regressionOmbres = Seuil(hausseMin: 2)
    static let regressionSaturees = Seuil(hausseMin: 2, facteurMin: 1.5)
    /// Dominante des tons neutres qui s'éloigne du neutre (|a*| ou |b*|) d'au moins cette valeur.
    /// Relevé le 20 octobre 2026 : Tint ±15 donnait a* ±3, Temperature ±600 K jusqu'à 3,1 ;
    /// plancher de 0,2 d'une proposition à une vue.
    static let regressionDominante = 2.0
    /// Netteté passée sous un seuil de lecture : seulement avec une baisse d'au moins
    /// `baisseNetteteMin`. Bruit passé au-dessus : avec une hausse d'au moins `hausseBruitMin`.
    /// Provisoires, à relever.
    static let baisseNetteteMin = 3.0, hausseBruitMin = 0.1
    /// Baisse du bruit (en %) qui fait d'une baisse de netteté l'effet d'un débruitage : le grain
    /// retiré comptait comme détail.
    static let baisseBruitDebruitage = 30.0
    /// Part de la hausse de l'écrêtage (en %) que le blanc pur doit expliquer, cadre changé, pour
    /// y voir des coins vides (Upright, perspective) plutôt qu'une régression.
    static let partBlancPurCoins = 80.0

    // MARK: Mise en forme

    /// Un nombre à la française : « 2,6 », « +2,2 » avec `signe`, « −0,3 » (vrai signe moins).
    static func nombre(_ valeur: Double, signe: Bool = false, decimales: Int = 1) -> String {
        let facteur = pow(10.0, Double(decimales))
        let arrondi = (valeur * facteur).rounded() / facteur
        let texte = String(format: "%.\(decimales)f", abs(arrondi)).replacingOccurrences(of: ".", with: ",")
        if arrondi < 0 { return "−" + texte }
        return signe && arrondi > 0 ? "+" + texte : texte
    }

    /// Arrondi au `1 / parts` (10 : au dixième ; 20 : au pas de 0,05 ; 100 : au centième).
    static func arrondi(_ valeur: Double, parts: Double = 10) -> JSONValue {
        let r = (valeur * parts).rounded() / parts
        return .number(r == 0 ? 0 : r)
    }

    /// Un écart « avant, après, écart ».
    static func ecart(_ avant: Double, _ apres: Double, parts: Double = 10) -> [String: JSONValue] {
        ["avant": arrondi(avant, parts: parts), "apres": arrondi(apres, parts: parts), "ecart": arrondi(apres - avant, parts: parts)]
    }

    /// Lecture de la netteté (0 floue, 1 douce, 2 nette) et du bruit (0 faible, 1 visible, 2 fort),
    /// aux seuils de `DetailMeasurements`.
    static func lectureNettete(_ valeur: Double) -> (niveau: Int, nom: String) {
        valeur < DetailMeasurements.seuilFlou ? (0, "floue") : valeur < DetailMeasurements.seuilNet ? (1, "douce") : (2, "nette")
    }

    static func lectureBruit(_ valeur: Double) -> (niveau: Int, nom: String) {
        valeur < DetailMeasurements.bruitVisible ? (0, "faible") : valeur < DetailMeasurements.bruitFort ? (1, "visible") : (2, "fort")
    }

    /// Le bruit qui compte : le plus fort des aplats et des ombres, comme `noiseReading`.
    static func bruit(_ detail: DetailMeasurements) -> Double { max(detail.noise, detail.shadowNoise ?? 0) }

    // MARK: Empreintes

    /// Réglages d'objectif qui déforment l'image (avec ceux dont la clé commence par « Perspective »).
    static let clesGeometrie: Set<String> = ["LensProfileEnable", "LensProfileDistortionScale", "LensManualDistortionAmount"]

    /// Empreinte du cadre d'une réponse « apercu » (avec point_af) : la géométrie de la photo
    /// (dimensions affichées, orientation, cadre), l'angle de recadrage et les réglages qui la
    /// déforment. Un cadre changé rend les pixels incomparables un à un (tons neutres suivis,
    /// netteté, bruit). Clés triées : l'empreinte est stable.
    static func cadre(_ apercu: JSONValue) -> String {
        var reglages: [String: JSONValue] = [:]
        for (cle, valeur) in apercu["reglages"]?.object ?? [:] where cle.hasPrefix("Perspective") || clesGeometrie.contains(cle) {
            reglages[cle] = valeur
        }
        return JSONCoding.line([
            "geometrie": apercu["photo"]?["geometrie"] ?? .null,
            "angle": apercu["recadrage"]?["angle"] ?? .null,
            "reglages": .object(reglages),
        ])
    }

    /// Empreinte de l'état global : réglages, profil et son intensité (ni masques ni taches, que
    /// les étapes de Claude disent).
    static func etat(_ apercu: JSONValue) -> String {
        JSONCoding.line([
            "reglages": apercu["reglages"] ?? .null,
            "profil": apercu["profil"] ?? .null,
            "intensite_profil": apercu["intensite_profil"] ?? .null,
        ])
    }

    // MARK: Comparaison de deux mesures

    struct Comparaison {
        var ecarts: [String: JSONValue] = [:]
        /// Ce qui a été comparé sans écart visible.
        var sansEcart: [String] = []
        var regressions: [(defaut: Defaut, texte: String)] = []
        var aVerifier: [String] = []
        var remarques: [String] = []
    }

    /// Compare deux mesures (après moins avant). Un écart n'est listé que s'il passe son seuil de
    /// visibilité (sinon son nom va dans `sansEcart`). Avec `suivis`, la dominante se lit sur les
    /// mêmes pixels neutres (`neutresApres` mesurés avec le masque de `neutresAvant`) ; sinon sur
    /// les tons neutres de chaque image. Netteté et bruit seulement si les deux mesures existent, à
    /// la même taille, et que le cadre n'a pas changé.
    static func comparer(avant: PhotoMeasurements, apres: PhotoMeasurements,
                         detailAvant: DetailMeasurements?, detailApres: DetailMeasurements?,
                         neutresAvant: Measurements.NeutresSuivis?, neutresApres: Measurements.NeutresSuivis?,
                         suivis: Bool, cadreChange: Bool, grainAjoute: Bool) -> Comparaison {
        var c = Comparaison()
        func noter(_ nom: String, _ visible: Bool, _ valeur: [String: JSONValue]) {
            if visible { c.ecarts[nom] = .object(valeur) } else { c.sansEcart.append(nom) }
        }
        func pourcent(_ x: Double) -> String { "\(nombre(x)) %" }
        // « +0,8 point », « +2,2 points » : le pluriel à partir de 2.
        func points(_ x: Double) -> String { "\(nombre(x, signe: true)) point\(abs((x * 10).rounded()) >= 20 ? "s" : "")" }

        // Exposition, contraste.
        let il = Measurements.ecartIL(avant, apres)
        var exposition = ecart(avant.medianL, apres.medianL)
        exposition["IL"] = arrondi(il, parts: 20)
        noter("exposition", abs(il) >= seuilExposition, exposition)
        var contraste = ecart(avant.contrast, apres.contrast)
        contraste["p5"] = .string("\(nombre(avant.percentilesL[5] ?? 0)) → \(nombre(apres.percentilesL[5] ?? 0))")
        contraste["p95"] = .string("\(nombre(avant.percentilesL[95] ?? 0)) → \(nombre(apres.percentilesL[95] ?? 0))")
        noter("contraste", abs(apres.contrast - avant.contrast) >= seuilContraste, contraste)

        // Écrêtage.
        noter("hautes_lumieres_pct", abs(apres.clippedHighlights - avant.clippedHighlights) >= ecartEcretage,
              ecart(avant.clippedHighlights, apres.clippedHighlights))
        noter("blanc_pur_pct", abs(apres.pureWhite - avant.pureWhite) >= ecartEcretage, ecart(avant.pureWhite, apres.pureWhite))
        noter("ombres_bouchees_pct", abs(apres.crushedShadows - avant.crushedShadows) >= ecartEcretage,
              ecart(avant.crushedShadows, apres.crushedShadows))
        let canaux = ["rouge", "vert", "bleu"]
        let canauxComparables = avant.clippedChannels.count == 3 && apres.clippedChannels.count == 3
        if canauxComparables {
            let i = (0..<3).max { abs(apres.clippedChannels[$0] - avant.clippedChannels[$0]) < abs(apres.clippedChannels[$1] - avant.clippedChannels[$1]) } ?? 0
            var canal = ecart(avant.clippedChannels[i], apres.clippedChannels[i])
            canal["canal"] = .string(canaux[i])
            noter("canal_ecrete", abs(apres.clippedChannels[i] - avant.clippedChannels[i]) >= ecartEcretage, canal)
        }

        // Dominante des tons neutres.
        var a0 = avant.neutralA, b0 = avant.neutralB, a1 = apres.neutralA, b1 = apres.neutralB
        var part0 = avant.neutralShare, part1 = apres.neutralShare
        let suivie = suivis && neutresAvant != nil && neutresApres != nil
        if suivie, let n0 = neutresAvant, let n1 = neutresApres {
            (a0, b0, a1, b1, part0, part1) = (n0.a, n0.b, n1.a, n1.b, n0.part, n1.part)
        }
        var dominantes: [String] = []
        if part0 >= PhotoMeasurements.partNeutreMin, part1 >= PhotoMeasurements.partNeutreMin {
            for (nom, x0, x1) in [("dominante_a", a0, a1), ("dominante_b", b0, b1)] {
                var valeur = ecart(x0, x1)
                valeur["suivie"] = .bool(suivie)
                noter(nom, abs(x1 - x0) >= seuilDominante, valeur)
            }
            let tons = suivie ? "les mêmes tons neutres" : "les tons neutres"
            let legere = PhotoMeasurements.dominanteLegere
            for (axe, x0, x1, plus, moins) in [("b*", b0, b1, "chaude", "froide"), ("a*", a0, a1, "magenta", "verte")] {
                if abs(x1) - abs(x0) >= regressionDominante - 1e-9 {
                    // Une dominante qui s'éloigne du neutre : un défaut apparu ou aggravé.
                    dominantes.append("dominante accentuée sur \(tons) : \(axe) \(nombre(x0, signe: true)) → \(nombre(x1, signe: true)) (plus \(x1 > 0 ? plus : moins))")
                } else if x0 * x1 < 0, abs(x0) >= legere, abs(x1) >= legere {
                    // Une dominante qui change de sens, nette des deux côtés : correction dépassée ?
                    c.aVerifier.append("dominante passée de \(x0 > 0 ? plus : moins) (\(axe) \(nombre(x0, signe: true))) à \(x1 > 0 ? plus : moins) (\(axe) \(nombre(x1, signe: true))) sur \(tons) : correction dépassée ?")
                }
            }
        } else {
            c.remarques.append("dominante non comparée : moins de \(nombre(PhotoMeasurements.partNeutreMin, decimales: 0)) % de tons neutres")
        }
        // La dominante de toute l'image (point neutre). Quand elle se rapproche nettement du gris, la
        // balance a été corrigée : les tons suivis, gris sous l'ancienne dominante, reprennent la
        // couleur de leur objet. Ce n'est pas une dominante accentuée, mais un point à vérifier à
        // l'œil (24 octobre 2026 : sans cela, la vraie correction d'une forte dominante passait pour
        // une « regression »).
        if let g0 = avant.pointNeutre, let g1 = apres.pointNeutre {
            let d0 = hypot(g0.a, g0.b), d1 = hypot(g1.a, g1.b)
            func point(_ g: MesureEclairage.Neutre) -> JSONValue { ["a": arrondi(g.a), "b": arrondi(g.b)] }
            noter("dominante_globale", abs(d1 - d0) >= seuilDominante,
                  ["avant": point(g0), "apres": point(g1), "ecart_au_gris": .string("\(nombre(d0)) → \(nombre(d1))")])
            if d0 - d1 >= regressionDominante, !dominantes.isEmpty {
                c.aVerifier += dominantes.map {
                    "\($0), mais toute l'image se rapproche du neutre (point neutre à \(nombre(d0)) → \(nombre(d1)) du gris) : "
                        + "ces tons paraissaient gris sous l'ancienne dominante ; juger un blanc ou la peau à l'œil"
                }
                dominantes = []
            }
        }

        // Saturation.
        noter("chroma_moyenne", abs(apres.meanChroma - avant.meanChroma) >= seuilChroma, ecart(avant.meanChroma, apres.meanChroma))
        noter("tres_saturee_pct", abs(apres.saturatedShare - avant.saturatedShare) >= ecartSaturee,
              ecart(avant.saturatedShare, apres.saturatedShare))

        // Régressions d'écrêtage : le blanc pur d'un cadre changé, ce sont plutôt des coins vides.
        let h0 = avant.clippedHighlights, h1 = apres.clippedHighlights
        var ecretage = false
        if regressionEcretage.franchi(h0, h1) {
            ecretage = true
            if cadreChange, apres.pureWhite - avant.pureWhite >= partBlancPurCoins / 100 * (h1 - h0) {
                c.aVerifier.append("cadre changé et blanc pur en hausse (\(nombre(avant.pureWhite)) → \(pourcent(apres.pureWhite))) : coins vides possibles (Upright, perspective)")
            } else {
                c.regressions.append((.ecretage, "hautes lumières écrêtées : \(nombre(h0)) → \(pourcent(h1)) (\(points(h1 - h0)))"))
            }
        }
        if !ecretage, canauxComparables {
            let franchis = (0..<3).filter { regressionCanal.franchi(avant.clippedChannels[$0], apres.clippedChannels[$0]) }
            if let i = franchis.max(by: { apres.clippedChannels[$0] - avant.clippedChannels[$0] < apres.clippedChannels[$1] - avant.clippedChannels[$1] }) {
                c.regressions.append((.canal, "canal \(canaux[i]) écrêté : \(nombre(avant.clippedChannels[i])) → \(pourcent(apres.clippedChannels[i])) (couleur poussée hors du sRGB ou brûlée)"))
            }
        }
        if regressionOmbres.franchi(avant.crushedShadows, apres.crushedShadows) {
            c.regressions.append((.ombres, "ombres bouchées : \(nombre(avant.crushedShadows)) → \(pourcent(apres.crushedShadows))"))
        }
        if regressionSaturees.franchi(avant.saturatedShare, apres.saturatedShare) {
            c.regressions.append((.saturees, "couleurs très saturées (C* > \(nombre(PhotoMeasurements.chromaTresSaturee, decimales: 0))) : \(nombre(avant.saturatedShare)) → \(pourcent(apres.saturatedShare)) des pixels"))
        }
        c.regressions += dominantes.map { (.dominante, $0) }

        // Netteté et bruit : à taille et cadre égaux.
        if let d0 = detailAvant, let d1 = detailApres, d0.side == d1.side, !cadreChange {
            let n0 = d0.sharpest, n1 = d1.sharpest
            let l0 = lectureNettete(n0), l1 = lectureNettete(n1)
            var nettete = ecart(n0, n1)
            nettete["lecture"] = .string("\(l0.nom) → \(l1.nom)")
            noter("nettete_max", abs(n1 - n0) >= ecartNettetePct / 100 * n0 && arrondi(n1 - n0) != 0, nettete)
            let r0 = bruit(d0), r1 = bruit(d1)
            let lb0 = lectureBruit(r0), lb1 = lectureBruit(r1)
            var bruitJSON = ecart(r0, r1, parts: 100)
            bruitJSON["lecture"] = .string("\(lb0.nom) → \(lb1.nom)")
            noter("bruit", abs(r1 - r0) >= ecartBruit, bruitJSON)

            if l1.niveau < l0.niveau, n0 - n1 >= baisseNetteteMin {
                let seuil = l1.niveau == 0 ? DetailMeasurements.seuilFlou : DetailMeasurements.seuilNet
                if r0 > 0, (r0 - r1) / r0 * 100 >= baisseBruitDebruitage {
                    c.aVerifier.append("netteté en baisse avec le bruit (\(nombre(n0)) → \(nombre(n1)), bruit \(nombre(r0, decimales: 2)) → \(nombre(r1, decimales: 2))) : le débruitage retire aussi du grain que la mesure comptait comme détail ; juger par un zoom")
                } else {
                    c.regressions.append((.nettete, "netteté passée de \(l0.nom) à \(l1.nom) : \(nombre(n0)) → \(nombre(n1)) (seuil \(nombre(seuil, decimales: 0)))"))
                }
            }
            if lb1.niveau > lb0.niveau, r1 - r0 >= hausseBruitMin {
                let seuil = lb1.niveau == 2 ? DetailMeasurements.bruitFort : DetailMeasurements.bruitVisible
                if grainAjoute {
                    c.aVerifier.append("bruit en hausse avec le grain ajouté (\(nombre(r0, decimales: 2)) → \(nombre(r1, decimales: 2))) : voulu ?")
                } else {
                    c.regressions.append((.bruit, "bruit passé de \(lb0.nom) à \(lb1.nom) : \(nombre(r0, decimales: 2)) → \(nombre(r1, decimales: 2)) (seuil \(nombre(seuil)))"))
                }
            }
        }
        return c
    }

    // MARK: Bilan d'un view_photo

    static let conseilSession = "Une « regression » se corrige par une passe ciblée sur ce seul défaut, ou se défait par undo_last si la dernière étape en est la cause ; la dire à l'utilisateur si elle reste."
    static let baseSession = "Après moins avant. Exposition en IL (luminance médiane) ; dominante sur les mêmes pixels neutres (suivie) si le cadre n'a pas changé ; netteté et bruit à taille d'aperçu et cadre égaux."
    /// Le texte du premier view_photo d'une photo à une taille d'aperçu ; `autresTailles` : celles
    /// où la photo a déjà été vue dans la session (le bilan ne compare que des aperçus de même taille).
    static func premiereVue(taille: Int, autresTailles: [Int] = []) -> String {
        guard !autresTailles.isEmpty else {
            return "Premier view_photo de cette photo dans cette session : point de départ du bilan des suivants."
        }
        let deja = autresTailles.sorted().map { "\($0) px" }.joined(separator: ", ")
        return "Premier view_photo de cette photo à \(taille) px dans cette session : point de départ du bilan des suivants à cette taille "
            + "(déjà vue à \(deja) : le bilan ne compare que des aperçus de même taille)."
    }

    /// Le bilan d'un view_photo sur l'aperçu entier : écarts avec le précédent de la même photo
    /// (`precedente`), et depuis le premier de la session (`depart`) s'il est plus ancien, tous
    /// deux à la même taille d'aperçu.
    /// `suiviPrecedente` et `suiviDepart` : les tons neutres de `maintenant` mesurés avec le
    /// masque de `precedente` et de `depart` (nil si le cadre a changé). Une régression qui suit
    /// une annulation, ou un rendu aux calculs IA en attente, passe dans « a_verifier ».
    static func session(precedente: Vue, depart: Vue, maintenant: Vue,
                        suiviPrecedente: Measurements.NeutresSuivis?, suiviDepart: Measurements.NeutresSuivis?,
                        date: Date) -> JSONValue {
        func ilYA(_ quand: Date) -> String { "il y a \(FileOutils.duree(max(0, date.timeIntervalSince(quand))))" }
        var json: [String: JSONValue] = ["depuis": .string("le view_photo précédent de cette photo à \(precedente.taille) px, \(ilYA(precedente.quand))")]

        // Étapes de Claude depuis le view_photo précédent.
        var annulation = false, etapesIdentiques = precedente.etapes == maintenant.etapes
        if let avant = precedente.etapes, let apres = maintenant.etapes {
            let derniere = maintenant.derniereEtape.map { " (dernière : « \($0) »)" } ?? ""
            if apres > avant {
                json["etapes_claude"] = .string("\(apres - avant) de plus\(derniere)")
            } else if apres < avant {
                annulation = true
                json["etapes_claude"] = .string("\(avant - apres) de moins : retouche défaite (undo_last ou revert_to_original)")
            } else if maintenant.derniereEtape != precedente.derniereEtape {
                // Historique plein (20 étapes) : le nombre ne bouge plus, le nom de la dernière si.
                etapesIdentiques = false
                json["etapes_claude"] = .string("nouvelles\(derniere)")
            } else {
                json["etapes_claude"] = "aucune nouvelle"
            }
        }
        if maintenant.corrections != nil, maintenant.corrections != precedente.corrections {
            json["corrections_utilisateur"] = "l'utilisateur a aussi retouché à la main : un écart peut venir de lui"
        }

        let cadreChange = precedente.cadre != maintenant.cadre
        let memeTaille = precedente.taille == maintenant.taille
        let suivis = !cadreChange && precedente.neutres != nil && suiviPrecedente != nil
        var c = comparer(avant: precedente.mesures, apres: maintenant.mesures,
                         detailAvant: memeTaille ? precedente.detail : nil, detailApres: maintenant.detail,
                         neutresAvant: precedente.neutres, neutresApres: suivis ? suiviPrecedente : nil,
                         suivis: suivis, cadreChange: cadreChange, grainAjoute: maintenant.grain > precedente.grain)

        let memeEtat = precedente.etat == maintenant.etat && !cadreChange && etapesIdentiques
        if memeEtat, c.ecarts.isEmpty, c.regressions.isEmpty, c.aVerifier.isEmpty {
            json["meme_etat"] = "Rien n'a changé depuis le view_photo précédent (réglages, profil, cadre et étapes de Claude identiques)."
            return .object(json)
        }

        var remarques: [String] = []
        if !memeTaille { remarques.append("taille d'aperçu différente (\(precedente.taille) → \(maintenant.taille)) : netteté et bruit non comparés") }
        if cadreChange { remarques.append("cadre changé (recadrage, Upright, rotation) : tons neutres non suivis, netteté et bruit non comparés") }
        if memeEtat { remarques.append("réglages globaux et étapes identiques mais l'image a changé : masque, tache ou retouche à la main, ou calcul IA fini depuis") }
        remarques += c.remarques

        // Une régression après une annulation, ou sur un rendu incomplet, est à vérifier.
        let prefixe: String? = annulation ? "revenu après l'annulation : "
            : (precedente.iaEnAttente || maintenant.iaEnAttente) ? "calcul IA en attente sur l'un des rendus : " : nil
        let signalees = Set(c.regressions.map(\.defaut))
        var regressions = c.regressions.map(\.texte)
        if let prefixe {
            c.aVerifier += regressions.map { prefixe + $0 }
            regressions = []
        }

        var regressionDepuisDebut = false
        if depart.quand != precedente.quand {
            // Pas d'aller-retour après une annulation : défaire la passe précédente la ramène en
            // arrière, c'est le but, et non des réglages empilés.
            if !annulation {
                c.aVerifier += allersRetours(depart: depart, precedente: precedente, maintenant: maintenant,
                                             suiviPrecedente: suiviPrecedente, suiviDepart: suiviDepart)
            }
            // Depuis le premier view_photo : une dérive lente, faite de petites passes.
            let cadreDepuis = depart.cadre != maintenant.cadre
            let suivisDepuis = !cadreDepuis && depart.neutres != nil && suiviDepart != nil
            let d = comparer(avant: depart.mesures, apres: maintenant.mesures,
                             detailAvant: depart.taille == maintenant.taille ? depart.detail : nil, detailApres: maintenant.detail,
                             neutresAvant: depart.neutres, neutresApres: suivisDepuis ? suiviDepart : nil,
                             suivis: suivisDepuis, cadreChange: cadreDepuis, grainAjoute: maintenant.grain > depart.grain)
            var debut: [String: JSONValue] = [
                "depuis": .string("le premier view_photo à \(depart.taille) px de la session, \(ilYA(depart.quand))"),
                "ecarts": d.ecarts.isEmpty ? "aucun écart visible" : .object(d.ecarts),
            ]
            let nouvelles = d.regressions.filter { !signalees.contains($0.defaut) }.map(\.texte)
            if !nouvelles.isEmpty {
                if let prefixe {
                    debut["a_verifier"] = .array(nouvelles.map { .string(prefixe + $0) })
                } else {
                    debut["regression"] = .array(nouvelles.map(JSONValue.string))
                    regressionDepuisDebut = true
                }
            }
            if cadreDepuis || depart.taille != maintenant.taille {
                debut["remarque"] = cadreDepuis ? "cadre changé depuis : tons neutres non suivis, netteté et bruit non comparés"
                    : "taille d'aperçu différente : netteté et bruit non comparés"
            }
            json["depuis_le_debut"] = .object(debut)
        }

        if !c.ecarts.isEmpty { json["ecarts"] = .object(c.ecarts) }
        if !c.sansEcart.isEmpty { json["sans_ecart_visible"] = .array(c.sansEcart.map(JSONValue.string)) }
        if !regressions.isEmpty { json["regression"] = .array(regressions.map(JSONValue.string)) }
        if !c.aVerifier.isEmpty { json["a_verifier"] = .array(c.aVerifier.map(JSONValue.string)) }
        if !remarques.isEmpty { json["remarques"] = .array(remarques.map(JSONValue.string)) }
        if !regressions.isEmpty || regressionDepuisDebut { json["conseil"] = .string(conseilSession) }
        json["base"] = .string(baseSession)
        return .object(json)
    }

    /// Aller-retour : un écart de la passe précédente défait par la suivante (de signes opposés,
    /// tous deux visibles), pour l'exposition, le contraste et la dominante b*. Celle-ci sur les
    /// tons neutres suivis quand le cadre n'a pas changé depuis le départ : l'écart de la passe
    /// précédente est alors l'écart depuis le départ moins celui depuis la précédente.
    static func allersRetours(depart: Vue, precedente: Vue, maintenant: Vue,
                              suiviPrecedente: Measurements.NeutresSuivis?, suiviDepart: Measurements.NeutresSuivis?) -> [String] {
        var textes: [String] = []
        func verifier(_ quoi: String, _ avant: Double, _ depuis: Double, seuil: Double, decimales: Int, unite: String) {
            guard abs(avant) >= seuil, abs(depuis) >= seuil, avant * depuis < 0 else { return }
            textes.append("aller-retour \(quoi) : \(nombre(avant, signe: true, decimales: decimales))\(unite) à la passe précédente, \(nombre(depuis, signe: true, decimales: decimales))\(unite) depuis : des réglages empilés font dériver la photo")
        }
        verifier("de l'exposition", Measurements.ecartIL(depart.mesures, precedente.mesures),
                 Measurements.ecartIL(precedente.mesures, maintenant.mesures), seuil: seuilExposition, decimales: 2, unite: " IL")
        verifier("du contraste", precedente.mesures.contrast - depart.mesures.contrast,
                 maintenant.mesures.contrast - precedente.mesures.contrast, seuil: seuilContraste, decimales: 1, unite: "")
        let memeCadre = depart.cadre == precedente.cadre && precedente.cadre == maintenant.cadre
        if memeCadre, let n0 = depart.neutres, let n1 = precedente.neutres, let s1 = suiviPrecedente, let s0 = suiviDepart {
            let depuis = s1.b - n1.b
            verifier("de la dominante (b*)", (s0.b - n0.b) - depuis, depuis, seuil: seuilDominante, decimales: 1, unite: "")
        } else if [depart, precedente, maintenant].allSatisfy({ $0.mesures.neutralShare >= PhotoMeasurements.partNeutreMin }) {
            verifier("de la dominante (b*)", precedente.mesures.neutralB - depart.mesures.neutralB,
                     maintenant.mesures.neutralB - precedente.mesures.neutralB, seuil: seuilDominante, decimales: 1, unite: "")
        }
        return textes
    }

    /// Bilan d'un avant/après (view_photo avec compare, ou une proposition avec compare) : même
    /// format que `session`, sans étapes ni aller-retour ; les tons neutres ne sont pas suivis
    /// (l'image d'avant peut avoir un autre cadre). `conseil` n'est donné qu'avec une régression.
    /// `cadreChange` (par exemple deux images de proportions différentes : recadrage, Upright,
    /// rotation) : netteté et bruit ne se comparent pas, et un blanc pur en hausse est « à
    /// vérifier » (coins vides possibles), comme d'une vue à l'autre.
    static func avantApres(avant: PhotoMeasurements, apres: PhotoMeasurements,
                           detailAvant: DetailMeasurements?, detailApres: DetailMeasurements?,
                           depuis: String, conseil: String, grainAjoute: Bool = false, cadreChange: Bool = false) -> JSONValue {
        var c = comparer(avant: avant, apres: apres, detailAvant: detailAvant, detailApres: detailApres,
                         neutresAvant: nil, neutresApres: nil, suivis: false, cadreChange: cadreChange, grainAjoute: grainAjoute)
        if cadreChange {
            c.remarques.insert("cadre différent entre l'avant et l'après (recadrage, Upright, rotation) : netteté et bruit non comparés", at: 0)
        }
        var json: [String: JSONValue] = ["depuis": .string(depuis)]
        if !c.ecarts.isEmpty { json["ecarts"] = .object(c.ecarts) }
        if !c.sansEcart.isEmpty { json["sans_ecart_visible"] = .array(c.sansEcart.map(JSONValue.string)) }
        if !c.regressions.isEmpty {
            json["regression"] = .array(c.regressions.map { .string($0.texte) })
            json["conseil"] = .string(conseil)
        }
        if !c.aVerifier.isEmpty { json["a_verifier"] = .array(c.aVerifier.map(JSONValue.string)) }
        if !c.remarques.isEmpty { json["remarques"] = .array(c.remarques.map(JSONValue.string)) }
        json["base"] = "Après moins avant, sur deux images rendues et mesurées de même. Exposition en IL d'après la luminance médiane ; dominante sur les tons neutres de chaque image (non suivie : l'image d'avant peut avoir un autre cadre) ; netteté et bruit entre deux vues seulement (pas pour une proposition)."
        return .object(json)
    }

    /// Bilan d'un zoom refait sur la même zone : les chiffres bruts, sans alerte (les seuils de
    /// lecture ne valent pas à 100 %). Netteté et bruit avec leur écart en % (après un débruitage).
    static func zone(avant: Zoom, apres: Zoom, date: Date) -> JSONValue {
        func avecPourcent(_ x0: Double, _ x1: Double, parts: Double) -> JSONValue {
            var valeur = ecart(x0, x1, parts: parts)
            if x0 > 0 { valeur["ecart_pct"] = arrondi((x1 - x0) / x0 * 100, parts: 1) }
            return .object(valeur)
        }
        var ecarts: [String: JSONValue] = [
            "mediane_L": .object(ecart(avant.mesures.medianL, apres.mesures.medianL)),
            "hautes_lumieres_pct": .object(ecart(avant.mesures.clippedHighlights, apres.mesures.clippedHighlights)),
            "ombres_bouchees_pct": .object(ecart(avant.mesures.crushedShadows, apres.mesures.crushedShadows)),
        ]
        if let d0 = avant.detail, let d1 = apres.detail {
            ecarts["nettete_max"] = avecPourcent(d0.sharpest, d1.sharpest, parts: 10)
            ecarts["nettete_mediane"] = avecPourcent(d0.medianSharpness, d1.medianSharpness, parts: 10)
            ecarts["bruit_aplats"] = avecPourcent(d0.noise, d1.noise, parts: 100)
            if let s0 = d0.shadowNoise, let s1 = d1.shadowNoise { ecarts["bruit_ombres"] = avecPourcent(s0, s1, parts: 100) }
        }
        return [
            "depuis": .string("le zoom précédent sur la même zone, il y a \(FileOutils.duree(max(0, date.timeIntervalSince(avant.quand))))"),
            "ecarts": .object(ecarts),
            "base": "Zoom à 100 % : chiffres bruts comparés à ceux du zoom précédent sur la même zone ; les seuils de lecture ne valent pas à cette échelle.",
        ]
    }

    // MARK: Mémoire des vues

    /// Retire les vues les plus anciennes (d'après la dernière) au-delà de `garder`.
    static func elaguer<Cle: Hashable>(_ suivis: inout [Cle: Suivi], garder: Int = photosGardees) {
        guard suivis.count > garder else { return }
        let anciennes = suivis.sorted { $0.value.precedente.quand < $1.value.precedente.quand }.prefix(suivis.count - garder)
        for (id, _) in anciennes { suivis.removeValue(forKey: id) }
    }

    /// La liste des zooms d'une photo avec `zoom` : il remplace celui de la même zone, et seuls les
    /// `garder` plus récents restent.
    static func ajouter(_ zoom: Zoom, a zooms: [Zoom], garder: Int = zoomsGardes) -> [Zoom] {
        Array((zooms.filter { !$0.correspond(zoom) } + [zoom]).suffix(garder))
    }
}

extension Bilan.Zoom {
    /// La même zone (chaque coordonnée à `Bilan.toleranceZone` près), du même cadre, aux mêmes pixels.
    func correspond(_ autre: Bilan.Zoom) -> Bool {
        let t = Bilan.toleranceZone
        return cadre == autre.cadre && pixels == autre.pixels
            && abs(Double(zone.minX - autre.zone.minX)) <= t && abs(Double(zone.minY - autre.zone.minY)) <= t
            && abs(Double(zone.width - autre.zone.width)) <= t && abs(Double(zone.height - autre.zone.height)) <= t
    }
}

extension Bilan.Vue {
    /// La vue d'une réponse « apercu » du module (view_photo sur l'aperçu entier, avec point_af),
    /// lue avant que le serveur n'en retire la géométrie. Nil sans identifiant de photo.
    init?(apercu: JSONValue, quand: Date, taille: Int, mesures: PhotoMeasurements,
          detail: DetailMeasurements?, neutres: Measurements.NeutresSuivis?) {
        guard let photo = apercu["photo"]?["id"]?.int else { return nil }
        func present(_ cle: String) -> JSONValue? { apercu[cle].flatMap { $0.isNull ? nil : $0 } }
        self.init(photo: photo, fichier: apercu["photo"]?["fichier"]?.string ?? "", quand: quand, taille: taille,
                  cadre: Bilan.cadre(apercu), etat: Bilan.etat(apercu),
                  etapes: apercu["etapes_claude"]?["nombre"]?.int, derniereEtape: apercu["etapes_claude"]?["derniere"]?.string,
                  mesures: mesures, detail: detail, neutres: neutres,
                  iaEnAttente: present("a_savoir") != nil, corrections: present("corrections_utilisateur").map(JSONCoding.line),
                  grain: apercu["reglages"]?["GrainAmount"]?.double ?? 0)
    }
}
