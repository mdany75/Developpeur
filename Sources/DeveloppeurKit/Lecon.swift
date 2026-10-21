import Foundation

/// La leçon de la photo (1.3), partie pure : trois points (lumière, couleur, composition) validés,
/// les corrections nettes de Claude tirées du journal, des indices de défauts mesurés à seuils
/// provisoires, les faits rendus à Claude, les remarques, le texte et la forme qu'attend le module
/// (commande lecon, action garder, Carnet.lua). Sans SDK ni Vision : des fonctions sur des données,
/// testées telles quelles (LeconTests). L'outil photo_lesson est dans Tools+Lecon.swift.
///
/// Aucune liste de défauts ici : leurs clés, codes, axes et libellés sont ceux de PriseDeVue, la
/// seule liste. Les indices nomment les défauts qu'une correction de Claude trahit (une exposition
/// remontée d'au moins 0,5 IL : la photo était sous-exposée) ; les autres (flou, éclairage mixte,
/// couleurs ternes, sujet centré, bords encombrés) restent au jugement de Claude, qui a la vue,
/// Vision et l'éclairage sous les yeux. Un indice que la leçon ne nomme pas donne une remarque,
/// jamais un refus : un choix de style ou une intention du boîtier suivie n'est pas un défaut.
enum Lecon {
    /// Chaque moitié d'un point (missing, at_capture) : une phrase simple. Le module accepte 600
    /// octets (Carnet.LONGUEUR_TEXTE) : 140 caractères y tiennent toujours.
    static let longueurPoint = 140
    /// Une preuve d'indice tient sur une ligne ; le module en accepte 400 octets.
    static let longueurPreuve = 160

    /// Clés d'un point. Une clé inconnue est refusée à la main : parametresInconnus ne voit que le
    /// premier niveau des arguments (comme pour propose_ratings).
    static let pointKeys = ["axis", "missing", "at_capture", "defects"]
    static let pointKeysProches = ["axe": "axis", "manque": "missing", "prise_de_vue": "at_capture", "defauts": "defects",
                                   "defaults": "defects", "capture": "at_capture", "lacking": "missing", "defect": "defects"]

    /// Un point validé : son axe, ce qui manquait (nil : rien ne manquait), ce qui l'aurait évité à
    /// la prise de vue (ou ce qui a marché, à refaire), les défauts nommés, tous de son axe.
    struct Point: Equatable {
        var axe: PriseDeVue.Axe
        var manque: String?
        var priseDeVue: String
        var defauts: [PriseDeVue.Defaut]
    }

    // MARK: Points

    /// Les trois points donnés à photo_lesson, vérifiés (exactement trois, chaque axe une fois,
    /// at_capture non vide, moitiés de `longueurPoint` caractères au plus, défauts connus et de
    /// l'axe du point), rendus dans l'ordre des axes. Un refus dit le point fautif et que rien n'a
    /// été rangé.
    static func points(_ items: [JSONValue]) throws -> [Point] {
        let axes = PriseDeVue.Axe.allCases.map(\.cle).joined(separator: ", ")
        guard items.count == PriseDeVue.Axe.allCases.count else {
            throw LightroomError.invalid("« points » : trois points, un par axe (\(axes)) ; \(items.count) donné(s). Rien n'a été rangé.")
        }
        var parAxe: [PriseDeVue.Axe: Point] = [:]
        for (index, item) in items.enumerated() {
            let p: Point
            do {
                p = try point(item)
            } catch let erreur as LightroomError {
                throw LightroomError.invalid("points[\(index)] : \(erreur.localizedDescription) Rien n'a été rangé.")
            }
            guard parAxe[p.axe] == nil else {
                throw LightroomError.invalid("points[\(index)] : l'axe « \(p.axe.cle) » est donné deux fois ; un point par axe (\(axes)). Rien n'a été rangé.")
            }
            parAxe[p.axe] = p
        }
        return PriseDeVue.Axe.allCases.compactMap { parAxe[$0] }
    }

    /// Un point, sans regarder les autres.
    static func point(_ item: JSONValue) throws -> Point {
        guard let objet = item.object else {
            throw LightroomError.invalid("un point est un objet {axis, missing, at_capture, defects}.")
        }
        let inconnues = objet.keys.filter { !pointKeys.contains($0) }.sorted()
        guard inconnues.isEmpty else {
            throw LightroomError.invalid("clé(s) inconnue(s) : \(ToolHandler.nommer(inconnues, pointKeysProches)). Clés acceptées : \(pointKeys.joined(separator: ", ")).")
        }
        let p = Arguments(raw: objet)
        guard let cleAxe = p.string("axis") else {
            throw LightroomError.invalid("« axis » manque : light, color ou composition.")
        }
        guard let axe = PriseDeVue.Axe(cle: cleAxe) else {
            let proche = PriseDeVue.Axe(rawValue: cleAxe).map { " (ici : « \($0.cle) »)" } ?? ""
            throw LightroomError.invalid("axe inconnu « \(cleAxe) »\(proche) : light, color ou composition.")
        }
        guard let priseDeVue = try moitie(p, "at_capture") else {
            throw LightroomError.invalid("« at_capture » manque (axe \(axe.cle)) : ce qui l'aurait évité à la prise de vue, ou, si rien ne manquait, ce qui a marché, à refaire.")
        }
        let manque = try moitie(p, "missing")
        var defauts: [PriseDeVue.Defaut] = []
        if p.has("defects") {
            guard let liste = p.array("defects") else {
                throw LightroomError.invalid("« defects » : une liste de défauts de l'axe \(axe.cle) (\(PriseDeVue.cles(axe: axe).joined(separator: ", "))).")
            }
            for valeur in liste {
                guard let cle = valeur.string, let defaut = PriseDeVue.defaut(cle: cle) else {
                    throw LightroomError.invalid("défaut inconnu \(JSONCoding.line(valeur)) ; ceux de l'axe \(axe.cle) : \(PriseDeVue.cles(axe: axe).joined(separator: ", ")).")
                }
                guard defaut.axe == axe else {
                    throw LightroomError.invalid("« \(cle) » est un défaut de l'axe \(defaut.axe.cle), pas de \(axe.cle) ; ceux de \(axe.cle) : \(PriseDeVue.cles(axe: axe).joined(separator: ", ")).")
                }
                if !defauts.contains(defaut) { defauts.append(defaut) }
            }
        }
        return Point(axe: axe, manque: manque, priseDeVue: priseDeVue, defauts: defauts)
    }

    /// Une moitié de point : nil si elle est absente ou vide après nettoyage ; refusée si ce n'est
    /// pas un texte ou si elle dépasse `longueurPoint` caractères.
    static func moitie(_ p: Arguments, _ cle: String) throws -> String? {
        guard let valeur = p.raw[cle], !valeur.isNull else { return nil }
        guard let brut = valeur.string else { throw LightroomError.invalid("« \(cle) » : un texte, une phrase simple.") }
        let texte = nettoyer(brut)
        guard !texte.isEmpty else { return nil }
        guard texte.count <= longueurPoint else {
            throw LightroomError.invalid("« \(cle) » trop long (\(texte.count) caractères, \(longueurPoint) au plus) : une phrase simple.")
        }
        return texte
    }

    /// Les blancs et les retours à la ligne ramenés à une espace.
    static func nettoyer(_ texte: String) -> String {
        texte.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: Corrections nettes

    /// Ce que Claude a changé, en net : sa première valeur d'avant et sa dernière d'après.
    struct Correction: Equatable {
        var cle: String
        var avant: JSONValue
        var apres: JSONValue
        /// La dernière valeur vient d'un exercice « Je le fais » (entrée 'exercice' du journal) : la
        /// version de Claude, jamais appliquée à la photo.
        var exercice = false
        /// Avec exercice : la dernière valeur que Claude avait appliquée avant, s'il y en a une.
        var appliquee: JSONValue?
    }

    /// Les corrections nettes de Claude d'après le journal de la photo (champ journalClaude, dans
    /// l'ordre), dans l'ordre où chaque clé est touchée la première fois. Une pile des entrées
    /// actives :
    /// - 'retouche' et 'classement' s'y empilent (un classement peut être défait, mais ses
    ///   changements, une note ou un mot-clé, ne sont pas des corrections de l'image) ;
    /// - 'exercice' (« Je le fais ») aussi, mais ses valeurs sont la version de Claude, jamais
    ///   appliquée (`exercice`) ; aucune annulation ne la défait, faute d'avoir été appliquée ;
    /// - 'annulation' retire l'entrée de même etape_id, sinon la dernière dont l'étape est le nom
    ///   entre « » (une mémoire sans identifiant, d'avant la 1.3), sinon la dernière ;
    /// - 'retour' (revert_to_original) vide la pile.
    /// Les clés revenues à leur valeur d'avant sont retirées.
    static func correctionsNettes(_ entrees: [JSONValue]) -> [Correction] {
        struct Active {
            var type: String
            var etape: String?
            var id: String?
            var changements: [JSONValue]
            var annulable: Bool { type != "exercice" }
        }
        var pile: [Active] = []
        for entree in entrees {
            guard let objet = entree.object, let type = objet["type"]?.string else { continue }
            switch type {
            case "retouche", "classement", "exercice":
                pile.append(Active(type: type, etape: objet["etape"]?.string, id: identifiant(objet["etape_id"]),
                                   changements: objet["changements"]?.array ?? []))
            case "annulation":
                if let id = identifiant(objet["etape_id"]), let i = pile.lastIndex(where: { $0.id == id }) {
                    pile.remove(at: i)
                } else if let nom = etapeAnnulee(objet["etape"]?.string),
                          let i = pile.lastIndex(where: { $0.annulable && $0.etape == nom }) {
                    pile.remove(at: i)
                } else if let i = pile.lastIndex(where: \.annulable) {
                    pile.remove(at: i)
                }
            case "retour":
                pile.removeAll()
            default:
                continue
            }
        }
        var ordre: [String] = [], nettes: [String: Correction] = [:]
        for active in pile where active.type == "retouche" || active.type == "exercice" {
            let exercice = active.type == "exercice"
            for changement in active.changements {
                guard let c = changement.object, let cle = c["cle"]?.string, !cle.isEmpty else { continue }
                let avant = c["avant"] ?? .null, apres = c["apres"] ?? .null
                guard var nette = nettes[cle] else {
                    nettes[cle] = Correction(cle: cle, avant: avant, apres: apres, exercice: exercice)
                    ordre.append(cle)
                    continue
                }
                if exercice {
                    if !nette.exercice { nette.appliquee = nette.apres }
                    nette.exercice = true
                } else {
                    nette.exercice = false
                    nette.appliquee = nil
                }
                nette.apres = apres
                nettes[cle] = nette
            }
        }
        return ordre.compactMap { nettes[$0] }.filter { !memeValeur($0.avant, $0.apres) }
    }

    /// L'identifiant d'une étape (etape_id, 1.3), en texte ; nil s'il manque.
    static func identifiant(_ valeur: JSONValue?) -> String? {
        guard let valeur, !valeur.isNull else { return nil }
        if let texte = valeur.string { return texte.isEmpty ? nil : texte }
        if let entier = valeur.int { return String(entier) }
        if let nombre = valeur.double { return String(nombre) }
        return nil
    }

    /// Le nom de l'étape défaite, entre « » : « Annulation de « Claude · passe 2 » » → « Claude · passe 2 ».
    static func etapeAnnulee(_ texte: String?) -> String? {
        guard let texte, let debut = texte.range(of: "« "), let fin = texte.range(of: " »", options: .backwards),
              debut.upperBound <= fin.lowerBound else { return nil }
        let nom = String(texte[debut.upperBound..<fin.lowerBound])
        return nom.isEmpty ? nil : nom
    }

    static func memeValeur(_ a: JSONValue, _ b: JSONValue) -> Bool {
        if let x = a.double, let y = b.double { return abs(x - y) < 1e-6 }
        return a == b
    }

    /// Un nombre d'une valeur du journal (nombre, ou texte d'un nombre).
    static func nombre(_ valeur: JSONValue?) -> Double? {
        guard let valeur else { return nil }
        if let x = valeur.double { return x }
        if let texte = valeur.string { return Double(texte.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        return nil
    }

    // MARK: Indices

    /// Un défaut que trahit une correction de Claude (ou la vue de départ), et sa preuve chiffrée.
    struct Indice: Equatable {
        var defaut: PriseDeVue.Defaut
        var preuve: String
    }

    /// Seuils des indices, provisoires : déduits des corrections de Claude, ils peuvent compter un
    /// choix de style comme un défaut (d'où des remarques, jamais des refus). À relever sur les
    /// huit copies « Essai » (mesure 3), puis à noter dans SPEC.
    enum Seuils {
        /// Exposure2012 remontée (sous-exposée) ou baissée (surexposée), en IL.
        static let exposition = 0.5
        /// Highlights2012 ou Whites2012 baissés, et une vue de départ écrêtée d'au moins tant de %.
        static let hautesLumieres = -40.0, blancs = -30.0, ecretageDepart = 0.5
        /// Shadows2012 ou Blacks2012 remontés, et une vue de départ bouchée d'au moins tant de %.
        static let ombres = 40.0, noirs = 25.0, ombresDepart = 2.0
        /// Dehaze remonté : une lumière plate ou voilée.
        static let voile = 10.0
        /// LuminanceSmoothing remonté (sans le débruitage de Lightroom).
        static let lissage = 20.0
        /// Température : écart en kelvins quand les valeurs dépassent `kelvins` (RAW), sinon sur
        /// l'échelle relative d'un JPEG ; teinte ; dominante de la vue de départ (tons neutres).
        static let temperatureKelvins = 400.0, temperatureRelative = 10.0, kelvins = 1000.0, teinte = 10.0
        static let dominanteDepart = PhotoMeasurements.dominanteNette
        /// CropAngle : même seuil que les consignes (« sous 0,5°, elle ne se voit pas »).
        static let angle = 0.5
        /// PerspectiveVertical : des verticales redressées à la main.
        static let perspective = 10.0
        /// Surface du cadre recadré par Claude (fraction de l'image), sans rotation ni Upright.
        static let surfaceCadre = 0.85
    }

    /// Les indices tirés des corrections nettes de Claude (un exercice compte : c'est son jugement)
    /// et de la première vue mesurée de la session (nil : pas de view_photo de cette photo dans ce
    /// processus du serveur), dans l'ordre de PriseDeVue.
    static func indices(corrections: [Correction], depart: Bilan.Vue?) -> [Indice] {
        var parCle: [String: Correction] = [:]
        for c in corrections where parCle[c.cle] == nil { parCle[c.cle] = c }
        func ecart(_ cle: String) -> (avant: Double, apres: Double, ecart: Double)? {
            guard let c = parCle[cle], let apres = nombre(c.apres) else { return nil }
            let avant = nombre(c.avant) ?? 0
            return (avant, apres, apres - avant)
        }
        func libelle(_ cle: String) -> String { DevelopCatalogue.label(for: cle) ?? cle }
        func change(_ cle: String, _ e: (avant: Double, apres: Double, ecart: Double), decimales: Int = 0, unite: String = "") -> String {
            "\(libelle(cle)) \(Bilan.nombre(e.ecart, signe: true, decimales: decimales))\(unite) (\(Bilan.nombre(e.avant, decimales: decimales)) → \(Bilan.nombre(e.apres, decimales: decimales)))"
        }
        var trouves: [String: String] = [:]
        func noter(_ cle: String, _ preuves: [String]) {
            guard !preuves.isEmpty, PriseDeVue.defaut(cle: cle) != nil else { return }
            trouves[cle] = preuves.joined(separator: " ; ")
        }

        // Exposition.
        if let e = ecart("Exposure2012") {
            if e.ecart >= Seuils.exposition { noter("underexposed", [change("Exposure2012", e, decimales: 2, unite: " IL")]) }
            if e.ecart <= -Seuils.exposition { noter("overexposed", [change("Exposure2012", e, decimales: 2, unite: " IL")]) }
        }
        // Hautes lumières, si la vue de départ était écrêtée (ou inconnue).
        var hautes: [String] = []
        if let e = ecart("Highlights2012"), e.ecart <= Seuils.hautesLumieres { hautes.append(change("Highlights2012", e)) }
        if let e = ecart("Whites2012"), e.ecart <= Seuils.blancs { hautes.append(change("Whites2012", e)) }
        if !hautes.isEmpty {
            if let depart {
                if depart.mesures.clippedHighlights >= Seuils.ecretageDepart {
                    noter("blown_highlights", hautes + ["au départ, \(Bilan.nombre(depart.mesures.clippedHighlights)) % de hautes lumières écrêtées"])
                }
            } else {
                noter("blown_highlights", hautes + ["sans vue de départ mesurée"])
            }
        }
        // Ombres, si la vue de départ était bouchée (ou inconnue).
        var ombres: [String] = []
        if let e = ecart("Shadows2012"), e.ecart >= Seuils.ombres { ombres.append(change("Shadows2012", e)) }
        if let e = ecart("Blacks2012"), e.ecart >= Seuils.noirs { ombres.append(change("Blacks2012", e)) }
        if !ombres.isEmpty {
            if let depart {
                if depart.mesures.crushedShadows >= Seuils.ombresDepart {
                    noter("crushed_shadows", ombres + ["au départ, \(Bilan.nombre(depart.mesures.crushedShadows)) % d'ombres bouchées"])
                }
            } else {
                noter("crushed_shadows", ombres + ["sans vue de départ mesurée"])
            }
        }
        // Voile.
        if let e = ecart("Dehaze"), e.ecart >= Seuils.voile { noter("flat_light", [change("Dehaze", e)]) }
        // Bruit : le débruitage de Lightroom lancé, ou la réduction du bruit de luminance remontée.
        var bruit: [String] = []
        if let c = parCle["Amelioration.denoise"], !actif(c.avant), actif(c.apres) {
            bruit.append("\(libelle("Amelioration.denoise")) lancé (\(JSONCoding.line(c.avant)) → \(JSONCoding.line(c.apres)))")
        }
        if let e = ecart("LuminanceSmoothing"), e.ecart >= Seuils.lissage { bruit.append(change("LuminanceSmoothing", e)) }
        noter("noise", bruit)
        // Dominante : balance des blancs corrigée, ou vue de départ nettement colorée.
        var dominante: [String] = []
        if let e = ecart("Temperature") {
            let enKelvins = max(abs(e.avant), abs(e.apres)) > Seuils.kelvins
            if abs(e.ecart) >= (enKelvins ? Seuils.temperatureKelvins : Seuils.temperatureRelative) {
                dominante.append(change("Temperature", e, unite: enKelvins ? " K" : ""))
            }
        }
        if let e = ecart("Tint"), abs(e.ecart) >= Seuils.teinte { dominante.append(change("Tint", e)) }
        // La vue de départ ne dit la dominante de la prise de vue que si Claude n'y avait encore
        // rien changé.
        if let depart, (depart.etapes ?? 0) == 0, depart.mesures.neutralShare >= PhotoMeasurements.partNeutreMin,
           max(abs(depart.mesures.neutralA), abs(depart.mesures.neutralB)) >= Seuils.dominanteDepart {
            dominante.append("au départ, tons neutres à a* \(Bilan.nombre(depart.mesures.neutralA)), b* \(Bilan.nombre(depart.mesures.neutralB)) (\(depart.mesures.castReading))")
        }
        noter("color_cast", dominante)
        // Horizon.
        let angle = ecart("CropAngle")
        let penche = angle.map { abs($0.ecart) >= Seuils.angle } ?? false
        if let angle, penche { noter("tilted_horizon", [change("CropAngle", angle, decimales: 1, unite: "°")]) }
        // Verticales : Upright posé, ou la perspective verticale corrigée à la main.
        var verticales: [String] = []
        var upright = false
        if let c = parCle["PerspectiveUpright"], (nombre(c.avant) ?? 0) == 0, let apres = nombre(c.apres), apres != 0 {
            upright = true
            verticales.append("\(libelle("PerspectiveUpright").components(separatedBy: " (").first ?? "Upright") posé (0 → \(Bilan.nombre(apres, decimales: 0)))")
        }
        if let e = ecart("PerspectiveVertical"), abs(e.ecart) >= Seuils.perspective { verticales.append(change("PerspectiveVertical", e)) }
        noter("converging_verticals", verticales)
        // Cadrage : le cadre resserré par Claude, sans rotation ni Upright (qui resserrent d'eux-mêmes).
        let bords = ["CropLeft", "CropTop", "CropRight", "CropBottom"]
        if !penche, !upright, bords.contains(where: { parCle[$0] != nil }) {
            func bord(_ cle: String, apres: Bool) -> Double {
                let defaut = cle == "CropLeft" || cle == "CropTop" ? 0.0 : 1.0
                guard let c = parCle[cle] else { return defaut }
                return nombre(apres ? c.apres : c.avant) ?? defaut
            }
            func surface(apres: Bool) -> Double {
                max(0, bord("CropRight", apres: apres) - bord("CropLeft", apres: apres))
                    * max(0, bord("CropBottom", apres: apres) - bord("CropTop", apres: apres))
            }
            let avant = surface(apres: false), apres = surface(apres: true)
            if apres < Seuils.surfaceCadre, apres < avant - 1e-6 {
                noter("loose_framing", ["cadre resserré par Claude à \(Bilan.nombre(apres * 100, decimales: 0)) % de l'image (avant : \(Bilan.nombre(avant * 100, decimales: 0)) %)"])
            }
        }

        return PriseDeVue.defauts.compactMap { defaut in
            trouves[defaut.cle].map { Indice(defaut: defaut, preuve: String($0.prefix(longueurPreuve))) }
        }
    }

    /// Un traitement actif dans le journal (débruitage : 0, « non » ou rien quand il ne l'est pas).
    static func actif(_ valeur: JSONValue) -> Bool {
        if valeur.isNull { return false }
        if let x = valeur.double { return x != 0 }
        if let b = valeur.bool { return b }
        if let texte = valeur.string { return !["", "0", "non", "aucun"].contains(texte.lowercased()) }
        return true
    }

    // MARK: Faits, remarques, texte

    /// Une valeur simple (nombre, texte, booléen, rien) : les tables (courbes, masques) restent au
    /// journal.
    static func simple(_ valeur: JSONValue) -> Bool {
        valeur.array == nil && valeur.object == nil
    }

    /// Les faits rendus à Claude : la prise de vue (description détaillée du journal, avec
    /// prise_de_vue_plus s'il a été lu), les corrections nettes de Claude (valeurs simples), la
    /// première vue mesurée de la session, et les indices.
    static func faits(photo: JSONValue, corrections: [Correction], depart: Bilan.Vue?, indices: [Indice],
                      maintenant: Date = Date()) -> JSONValue {
        var prise: [String: JSONValue] = [:]
        for cle in ["appareil", "objectif", "iso", "vitesse", "ouverture", "focale", "date", "format"] {
            if let valeur = photo[cle], !valeur.isNull { prise[cle] = valeur }
        }
        if let plus = photo["prise_de_vue_plus"]?.object, !plus.isEmpty { prise["prise_de_vue_plus"] = .object(plus) }

        var liste: [JSONValue] = []
        var exercice = false
        for c in corrections where simple(c.avant) && simple(c.apres) {
            var objet: [String: JSONValue] = ["cle": .string(c.cle), "libelle": .string(DevelopCatalogue.label(for: c.cle) ?? c.cle),
                                              "avant": c.avant, "apres": c.apres]
            if c.exercice {
                exercice = true
                objet["exercice"] = true
                if let appliquee = c.appliquee, simple(appliquee) { objet["appliquee"] = appliquee }
            }
            liste.append(.object(objet))
        }
        var faits: [String: JSONValue] = [
            "prise_de_vue": .object(prise),
            "corrections": .array(liste),
            "corrections_lecture": .string(liste.isEmpty
                ? "aucune correction de Claude au journal de cette photo (ou toutes défaites)"
                : "corrections nettes de Claude d'après le journal : première valeur d'avant, dernière d'après ; étapes annulées ou défaites par un retour exclues"
                    + (exercice ? " ; exercice = version de Claude dans « Je le fais », jamais appliquée (appliquee : sa dernière valeur appliquée)" : "")),
            "indices": .array(indices.map { indice in
                ["defect": .string(indice.defaut.cle), "code": .string(indice.defaut.code), "axe": .string(indice.defaut.axe.cle),
                 "libelle": .string(indice.defaut.libelle), "preuve": .string(indice.preuve)]
            }),
            "seuils": "provisoires : un indice est une piste, à confirmer à l'œil (un choix de style ou une intention du boîtier suivie n'est pas un défaut)",
        ]
        if let depart {
            let m = depart.mesures
            var vue: [String: JSONValue] = [
                "vue": .string("premier view_photo de la session, à \(depart.taille) px, il y a \(FileOutils.duree(max(0, maintenant.timeIntervalSince(depart.quand))))"),
                "mediane_L": Bilan.arrondi(m.medianL),
                "hautes_lumieres_ecretees_pct": Bilan.arrondi(m.clippedHighlights),
                "ombres_bouchees_pct": Bilan.arrondi(m.crushedShadows),
                "tons_neutres": ["a": Bilan.arrondi(m.neutralA), "b": Bilan.arrondi(m.neutralB), "part_pct": Bilan.arrondi(m.neutralShare)],
                "dominante": .string(m.castReading),
            ]
            if let etapes = depart.etapes {
                vue["etapes_claude"] = .string(etapes == 0
                    ? "aucune : la photo telle qu'elle était avant Claude"
                    : "\(etapes) déjà\(depart.derniereEtape.map { " (dernière : « \($0) »)" } ?? "") : la vue n'est pas l'état d'origine")
            } else {
                vue["etapes_claude"] = "inconnues (module d'avant la 1.2)"
            }
            faits["depart"] = .object(vue)
        } else {
            faits["depart"] = "aucune vue mesurée : pas de view_photo de cette photo dans cette session du connecteur (autre conversation, autre modèle) ; le journal reste la source"
        }
        return .object(faits)
    }

    /// Un indice dont le défaut n'est nommé par aucun point : une remarque, à revoir.
    static func remarques(points: [Point], indices: [Indice]) -> [String] {
        let nommes = Set(points.flatMap { $0.defauts.map(\.cle) })
        return indices.filter { !nommes.contains($0.defaut.cle) }.map { indice in
            "Mesuré : \(indice.preuve) ; la leçon ne nomme pas « \(indice.defaut.libelle) » (\(indice.defaut.cle)) : à revoir si c'en était un (une intention du boîtier suivie n'en est pas un)."
        }
    }

    /// La leçon en texte (Claude Desktop, détail de l'appel) : un titre, puis un point par axe.
    static func texte(points: [Point], fichier: String) -> String {
        var lignes = ["Leçon de la photo · \(fichier)"]
        for p in points {
            let manque = p.manque.map { "Ce qui manquait : \($0) " } ?? "Rien ne manquait. "
            let prise = p.manque == nil ? "À refaire : \(p.priseDeVue)" : "À la prise de vue : \(p.priseDeVue)"
            lignes.append("- \(p.axe.nom) — \(manque)\(prise)")
        }
        return lignes.joined(separator: "\n")
    }

    /// La leçon telle que l'attend le module (lecon, action garder ; Carnet.lua) : codes français,
    /// points dans l'ordre des axes { axe, manque?, prise_de_vue, defauts = [{code, libelle}] },
    /// indices [{code, axe, libelle, preuve}].
    static func pourLeModule(points: [Point], indices: [Indice]) -> JSONValue {
        [
            "points": .array(points.map { p in
                var point: [String: JSONValue] = [
                    "axe": .string(p.axe.code), "prise_de_vue": .string(p.priseDeVue),
                    "defauts": .array(p.defauts.map { ["code": .string($0.code), "libelle": .string($0.libelle)] }),
                ]
                if let manque = p.manque { point["manque"] = .string(manque) }
                return .object(point)
            }),
            "indices": .array(indices.map { indice in
                ["code": .string(indice.defaut.code), "axe": .string(indice.defaut.axe.code),
                 "libelle": .string(indice.defaut.libelle), "preuve": .string(indice.preuve)]
            }),
        ]
    }
}
