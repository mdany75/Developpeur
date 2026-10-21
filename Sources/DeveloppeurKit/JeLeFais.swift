import Foundation

/// « Je le fais » (1.3), partie pure : l'utilisateur fait lui-même la retouche que Claude propose,
/// pour apprendre. preview_settings avec my_turn range la version de Claude en instantané
/// « Claude · ma version » sans rien appliquer ni rendre, et rend `a_faire` : les réglages dans
/// l'ordre des panneaux du module Développement (`aFaire`). Quand l'utilisateur a fini,
/// view_photo avec compare = claude_version montre la version de Claude (à gauche) à côté de la
/// sienne, avec les écarts réglage par réglage (`classer`) et l'écart principal (`principal`) :
/// l'écart mesuré le plus visible, ramené aux seuils de visibilité du bilan (Bilan.swift, sans seuil
/// nouveau), puis rattaché au réglage de sa famille qui l'explique le mieux. Sans SDK ni image : des
/// fonctions sur des données, testées telles quelles (JeLeFaisTests). Les outils sont dans
/// Tools+Retouche.swift (monTour) et Tools+Analyse.swift (viewPhoto).
///
/// L'ordre des panneaux n'existe qu'ici (`panneaux`). Provisoires jusqu'à la mesure 4 de la 1.3 :
/// les noms français des panneaux et de leurs sections, relevés dans Lightroom Classic 15.6, et les
/// tolérances de « comme Claude » (`tolerance`), à juger sur les trois premiers exercices de Dany.
enum JeLeFais {
    /// Nom de l'instantané de la version de Claude (« Claude · ma version » dans Lightroom).
    static let instantane = "ma version"
    /// Nom de l'étape de l'essai (« Claude · essai : ma version (je le fais) » dans l'Historique).
    static let etape = "ma version (je le fais)"

    // MARK: Panneaux

    /// Un panneau du module Développement et ses sections, dans l'ordre d'affichage.
    struct Panneau {
        var nom: String
        var sections: [String]
    }

    /// Les panneaux dans l'ordre d'affichage d'Adobe (aide-adobe § 1), précédés des paramètres
    /// prédéfinis (panneau de gauche : ils posent des réglages que la suite affine). Le Recadrage
    /// (outil R) vient après Transformation : choisir un mode Upright le remet à zéro. Noir et blanc
    /// remplace le Mélangeur de couleurs sur une photo en noir et blanc. Étalonnage des couleurs : le
    /// Color Grading ; Étalonnage : le calibrage de l'appareil, et la version de processus.
    static let panneaux: [Panneau] = [
        Panneau(nom: "Paramètres prédéfinis", sections: []),
        Panneau(nom: "Réglages de base", sections: ["Traitement", "Profil", "Balance des blancs", "Tonalité", "Présence", "HDR"]),
        Panneau(nom: "Courbe des tonalités", sections: []),
        Panneau(nom: "Mélangeur de couleurs", sections: ["TSL", "Couleur de point"]),
        Panneau(nom: "Noir et blanc", sections: []),
        Panneau(nom: "Étalonnage des couleurs", sections: []),
        Panneau(nom: "Détail", sections: []),
        Panneau(nom: "Flou de l'objectif", sections: []),
        Panneau(nom: "Corrections de l'objectif", sections: []),
        Panneau(nom: "Transformation", sections: []),
        Panneau(nom: "Recadrage", sections: []),
        Panneau(nom: "Effets", sections: []),
        Panneau(nom: "Étalonnage", sections: ["Processus"]),
    ]
    /// Une clé que rien ne range : en fin de liste.
    static let autres = "Autres"

    /// Le panneau et la section de chaque groupe du catalogue (DevelopCatalogue.groups).
    static let groupes: [String: (panneau: String, section: String?)] = [
        "Balance des blancs": ("Réglages de base", "Balance des blancs"),
        "Tonalité": ("Réglages de base", "Tonalité"),
        "HDR": ("Réglages de base", "HDR"),
        "Présence": ("Réglages de base", "Présence"),
        "Courbe des tonalités": ("Courbe des tonalités", nil),
        "TSL": ("Mélangeur de couleurs", "TSL"),
        "Noir et blanc": ("Noir et blanc", nil),
        "Étalonnage des couleurs": ("Étalonnage des couleurs", nil),
        "Détail": ("Détail", nil),
        "Effets": ("Effets", nil),
        "Optique": ("Corrections de l'objectif", nil),
        "Transformation": ("Transformation", nil),
        "Calibrage de l'appareil": ("Étalonnage", nil),
    ]

    /// Clés du recadrage, réunies en une seule ligne (angle en degrés, bords en part rognée).
    static let clesCadre = DevelopCatalogue.cropKeys

    /// Rang d'une clé du catalogue (son ordre dans DevelopCatalogue.all), pour trier dans un panneau.
    private static let rangsCatalogue: [String: Double] = {
        var rangs: [String: Double] = [:]
        for (i, reglage) in DevelopCatalogue.all.enumerated() where rangs[reglage.key] == nil { rangs[reglage.key] = Double(i) }
        return rangs
    }()

    private static func juste(avant cle: String) -> Double { (rangsCatalogue[cle] ?? 0) - 0.5 }
    private static func juste(apres cle: String, _ pas: Double = 0.1) -> Double { (rangsCatalogue[cle] ?? 0) + pas }

    /// Les clés que le catalogue ne range pas, ou qu'il range ailleurs que leur panneau : à la main.
    private static let speciales: [String: (panneau: String, section: String?, ordre: Double)] = {
        var table: [String: (panneau: String, section: String?, ordre: Double)] = [
            "Preset": ("Paramètres prédéfinis", nil, 0),
            "ConvertToGrayscale": ("Réglages de base", "Traitement", 0),
            "CameraProfile": ("Réglages de base", "Profil", 0),
            "Look": ("Réglages de base", "Profil", 1),
            "WhiteBalance": ("Réglages de base", "Balance des blancs", juste(avant: DevelopCatalogue.temperatureKey)),
            "AutoTone": ("Réglages de base", "Tonalité", juste(avant: "Exposure2012")),
            "PointColors": ("Mélangeur de couleurs", "Couleur de point", 0),
            "AutoGrayscaleMix": ("Noir et blanc", nil, juste(avant: "GrayMixerRed")),
            "LensBlur": ("Flou de l'objectif", nil, 0),
            "DepthBasedCorrections": ("Flou de l'objectif", nil, 1),
            "LensProfileName": ("Corrections de l'objectif", nil, juste(apres: "LensProfileEnable")),
            "UprightFourSegments": ("Transformation", nil, juste(apres: "PerspectiveUpright", 0.1)),
            "UprightTransform": ("Transformation", nil, juste(apres: "PerspectiveUpright", 0.2)),
            "CropConstrainToWarp": ("Transformation", nil, juste(apres: "PerspectiveUpright", 0.3)),
            "ProcessVersion": ("Étalonnage", "Processus", 0),
        ]
        for (i, courbe) in DevelopCatalogue.curveKeys.enumerated() {
            table[courbe.key] = ("Courbe des tonalités", nil, juste(apres: "CurveRefineSaturation", 0.1 * Double(i + 1)))
        }
        for (i, cle) in clesCadre.enumerated() { table[cle] = ("Recadrage", nil, Double(i)) }
        return table
    }()

    /// La place d'un réglage : son panneau, sa section, et son rang pour le tri (panneau, section,
    /// ordre dans le panneau). Une clé inconnue va en fin, sous « Autres ».
    struct Place: Equatable {
        var panneau: String
        var section: String?
        var rangPanneau: Int
        var rangSection: Int
        var ordre: Double

        func avant(_ autre: Place) -> Bool {
            (rangPanneau, rangSection, ordre) < (autre.rangPanneau, autre.rangSection, autre.ordre)
        }
    }

    static func place(cle: String) -> Place {
        var panneau = autres, section: String?, ordre = Double.greatestFiniteMagnitude
        if let speciale = speciales[cle] {
            (panneau, section, ordre) = speciale
        } else if cle.hasPrefix("Upright") {
            (panneau, ordre) = ("Transformation", juste(apres: "PerspectiveUpright", 0.25))
        } else if let reglage = DevelopCatalogue.setting(cle), let groupe = groupes[reglage.group] {
            (panneau, section, ordre) = (groupe.panneau, groupe.section, rangsCatalogue[cle] ?? 0)
        }
        let rangPanneau = panneaux.firstIndex { $0.nom == panneau } ?? panneaux.count
        let sections = rangPanneau < panneaux.count ? panneaux[rangPanneau].sections : []
        // Une clé sans section vient après les sections nommées (Étalonnage : Processus, puis les curseurs).
        let rangSection = section.flatMap { sections.firstIndex(of: $0) } ?? sections.count
        return Place(panneau: panneau, section: section, rangPanneau: rangPanneau, rangSection: rangSection, ordre: ordre)
    }

    // MARK: Noms

    /// Préfixe du libellé du catalogue qui redit le panneau (« TSL : teinte rouge » dans le Mélangeur
    /// de couleurs) : retiré.
    private static let prefixesRedondants: [String: String] = [
        "Courbe des tonalités": "Courbe", "Mélangeur de couleurs": "TSL", "Noir et blanc": "Mélangeur noir et blanc",
        "Étalonnage des couleurs": "Étalonnage", "Étalonnage": "Calibrage", "Transformation": "Transformation",
    ]
    /// Noms des clés hors du catalogue, tels que les montre le panneau.
    private static let nomsSpeciaux: [String: String] = [
        "Preset": "Paramètre prédéfini", "ConvertToGrayscale": "Couleur ou noir et blanc", "CameraProfile": "Profil",
        "Look": "Profil (Look)", "WhiteBalance": "Préréglage", "AutoTone": "Auto", "AutoGrayscaleMix": "Auto",
        "PointColors": "Couleur ponctuelle", "LensBlur": "Flou d'objectif", "DepthBasedCorrections": "Pinceau d'affinage",
        "LensProfileName": "Profil d'objectif", "UprightFourSegments": "Upright guidé : repères",
        "UprightTransform": "Upright : corrections", "CropConstrainToWarp": "Contraindre le recadrage",
        "ProcessVersion": "Version de processus",
    ]
    /// La ligne du recadrage.
    static let nomCadre = "Cadre"

    /// Le nom court d'un réglage : le libellé du catalogue sans sa parenthèse (plages, défauts) ni le
    /// préfixe qui redit le panneau.
    static func reglage(cle: String) -> String {
        if let nom = nomsSpeciaux[cle] { return nom }
        guard var texte = DevelopCatalogue.label(for: cle) else { return cle }
        if let parenthese = texte.range(of: " (") { texte = String(texte[..<parenthese.lowerBound]) }
        if let prefixe = prefixesRedondants[place(cle: cle).panneau], texte.hasPrefix(prefixe + " : ") {
            let reste = texte.dropFirst(prefixe.count + 3)
            texte = reste.prefix(1).uppercased() + reste.dropFirst()
        }
        return texte
    }

    /// « Réglages de base › Tonalité › Exposition » ; un réglage « Netteté : gain » devient
    /// « Détail › Netteté › Gain » (le texte ne redit pas « : » avant la valeur).
    static func chemin(_ place: Place, reglage: String) -> String {
        let morceaux = reglage.components(separatedBy: " : ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ([place.panneau] + (place.section.map { [$0] } ?? []) + morceaux).joined(separator: " › ")
    }

    // MARK: Valeurs

    /// Espace fine insécable des milliers (« 5 600 ») et espace insécable devant l'unité (« 600 K »,
    /// « 3 % ») : toutes deux mesurées dans Metriques.lua (la fenêtre les coupe juste).
    static let espaceMilliers = "\u{202F}", espaceUnite = "\u{00A0}"

    /// « 0,35 », « +0,35 » (avec `signe`), « −1,2 » : au plus `decimales` décimales, virgule, vrai
    /// signe moins ; 0 sans signe.
    static func nombre(_ valeur: Double, signe: Bool, decimales: Int = 2) -> String {
        let facteur = pow(10.0, Double(decimales))
        let arrondi = (valeur * facteur).rounded() / facteur
        guard arrondi != 0 else { return "0" }
        let texte = DevelopCatalogue.format(abs(arrondi)).replacingOccurrences(of: ".", with: ",")
        return arrondi < 0 ? "−" + texte : (signe ? "+" + texte : texte)
    }

    /// « 5 600 K » : une température en kelvins, au kelvin près, milliers séparés.
    static func kelvins(_ valeur: Double) -> String {
        var chiffres = String(Int(valeur.rounded()))
        var groupes: [String] = []
        while chiffres.count > 3 {
            groupes.insert(String(chiffres.suffix(3)), at: 0)
            chiffres.removeLast(3)
        }
        groupes.insert(chiffres, at: 0)
        return groupes.joined(separator: espaceMilliers) + espaceUnite + "K"
    }

    /// La température est en kelvins pour un RAW ; une valeur hors de la plage relative (−100 à
    /// +100) en est forcément aussi.
    static func enKelvins(_ valeur: Double, raw: Bool) -> Bool { raw || abs(valeur) > 100 }

    private static let nomsUpright: [Int: String] = [0: "désactivé", 1: "auto", 2: "complet", 3: "niveau", 4: "vertical", 5: "guidé"]
    private static let nomsStyleVignetage: [Int: String] = [1: "priorité aux hautes lumières", 2: "priorité couleur", 3: "peinture"]
    /// Préréglages de balance des blancs, tels que Lightroom les range et tels qu'il les nomme en
    /// français (provisoire, mesure 4).
    private static let nomsBalance: [String: String] = [
        "As Shot": "Telle quelle", "Auto": "Auto", "Daylight": "Lumière du jour", "Cloudy": "Nuageux", "Shade": "Ombre",
        "Tungsten": "Tungstène", "Fluorescent": "Fluorescent", "Flash": "Flash", "Custom": "Personnalisée",
    ]

    /// Une teinte en degrés (Étalonnage des couleurs : de 0 à 359).
    static func estUneTeinte(_ cle: String) -> Bool {
        guard let reglage = DevelopCatalogue.setting(cle) else { return false }
        return reglage.min == 0 && reglage.max == 359
    }

    /// Un nombre d'une valeur du module : un nombre, ou un booléen (interrupteurs que Lightroom range
    /// en vrai ou faux).
    static func nombre(_ valeur: JSONValue?) -> Double? {
        if let nombre = valeur?.double { return nombre }
        if let booleen = valeur?.bool { return booleen ? 1 : 0 }
        return nil
    }

    /// La valeur d'un réglage telle que la montre le panneau : « +0,35 », « 5 600 K », « −1,2° »,
    /// « activé », « complet », « 45° », ou le texte du module (profil, préréglage…).
    static func texte(cle: String, _ valeur: JSONValue?, raw: Bool) -> String {
        guard let valeur, !valeur.isNull else { return "—" }
        if let texte = valeur.string { return cle == "WhiteBalance" ? (nomsBalance[texte] ?? texte) : texte }
        guard let v = nombre(valeur) else { return JSONCoding.line(valeur) }
        if v == ToolHandler.pendingAutoValue { return "auto" }
        let reglage = DevelopCatalogue.setting(cle)
        switch cle {
        case DevelopCatalogue.temperatureKey where enKelvins(v, raw: raw): return kelvins(v)
        case "ConvertToGrayscale": return v >= 0.5 ? "noir et blanc" : "couleur"
        case "PerspectiveUpright": return nomsUpright[Int(v.rounded())] ?? nombre(v, signe: false)
        case "PostCropVignetteStyle": return nomsStyleVignetage[Int(v.rounded())] ?? nombre(v, signe: false)
        case "CropAngle", "PerspectiveRotate": return nombre(v, signe: true, decimales: 1) + "°"
        default: break
        }
        if valeur.bool != nil || reglage?.isSwitch == true { return v >= 0.5 ? "activé" : "désactivé" }
        if estUneTeinte(cle) { return nombre(v, signe: false, decimales: 0) + "°" }
        let bipolaire = (reglage?.min ?? 0) < 0 && (reglage?.max ?? 0) > 0
        return nombre(v, signe: bipolaire)
    }

    /// Le recadrage en une ligne : « angle −1,2°, rogné à gauche 2 %, en haut 3 % », ou « angle 0°,
    /// sans rognage ». Seuls les bords connus (changés) sont dits.
    static func texteCadre(_ valeurs: [String: Double]) -> String {
        var parties: [String] = []
        if let angle = valeurs["CropAngle"] { parties.append("angle " + nombre(angle, signe: true, decimales: 1) + "°") }
        let bords: [(cle: String, nom: String, depuisLaFin: Bool)] = [
            ("CropLeft", "à gauche", false), ("CropTop", "en haut", false), ("CropRight", "à droite", true), ("CropBottom", "en bas", true),
        ]
        var connus = 0
        var rognes: [String] = []
        for bord in bords {
            guard let v = valeurs[bord.cle] else { continue }
            connus += 1
            let part = (bord.depuisLaFin ? 1 - v : v) * 100
            if part >= 0.05 { rognes.append("\(bord.nom) \(nombre(part, signe: false, decimales: 1))\(espaceUnite)%") }
        }
        if connus > 0 { parties.append(rognes.isEmpty ? "sans rognage" : "rogné " + rognes.joined(separator: ", ")) }
        return parties.isEmpty ? "—" : parties.joined(separator: ", ")
    }

    /// Les valeurs du cadre d'un côté (avant, après ; départ, Claude, vous), par clé.
    private static func valeursCadre(_ entrees: [[String: JSONValue]], _ champ: String) -> [String: Double] {
        var valeurs: [String: Double] = [:]
        for entree in entrees {
            if let cle = entree["cle"]?.string, let v = nombre(entree[champ]) { valeurs[cle] = v }
        }
        return valeurs
    }

    // MARK: Liste à faire

    /// La liste « à faire » d'un exercice : les changements de la proposition (`changements` de la
    /// commande essayer : {cle, avant, apres}) triés dans l'ordre des panneaux, puis dans celui du
    /// catalogue (tri stable). Les cinq clés du cadre font une seule ligne. Chaque élément :
    /// {n, panneau, section, reglage, cle, de, a, texte, avant, apres} ; `avant` et `apres` sont les
    /// valeurs brutes (par clé pour le cadre, avec `cles`), pour que la fenêtre coche ce qui a bougé.
    static func aFaire(_ changements: [JSONValue], raw: Bool) -> JSONValue {
        var lignes: [(place: Place, rang: Int, json: [String: JSONValue])] = []
        var cadre: [[String: JSONValue]] = []
        for (i, changement) in changements.enumerated() {
            guard let entree = changement.object, let cle = entree["cle"]?.string else { continue }
            if clesCadre.contains(cle) {
                cadre.append(entree)
                continue
            }
            let place = place(cle: cle)
            let nom = reglage(cle: cle)
            let de = texte(cle: cle, entree["avant"], raw: raw), a = texte(cle: cle, entree["apres"], raw: raw)
            lignes.append((place, i, [
                "panneau": .string(place.panneau), "section": place.section.map(JSONValue.string) ?? .null,
                "reglage": .string(nom), "cle": .string(cle), "de": .string(de), "a": .string(a),
                "texte": .string("\(chemin(place, reglage: nom)) : \(de) → \(a)"),
                "avant": entree["avant"] ?? .null, "apres": entree["apres"] ?? .null,
            ]))
        }
        if !cadre.isEmpty {
            let place = place(cle: clesCadre[0])
            let de = texteCadre(valeursCadre(cadre, "avant")), a = texteCadre(valeursCadre(cadre, "apres"))
            var avant: [String: JSONValue] = [:], apres: [String: JSONValue] = [:]
            for entree in cadre {
                guard let cle = entree["cle"]?.string else { continue }
                avant[cle] = entree["avant"] ?? .null
                apres[cle] = entree["apres"] ?? .null
            }
            let presentes = clesCadre.filter { avant[$0] != nil }
            lignes.append((place, changements.count, [
                "panneau": .string(place.panneau), "section": .null, "reglage": .string(nomCadre), "cle": "Crop",
                "cles": .array(presentes.map(JSONValue.string)), "de": .string(de), "a": .string(a),
                "texte": .string("\(chemin(place, reglage: nomCadre)) : \(de) → \(a)"),
                "avant": .object(avant), "apres": .object(apres),
            ]))
        }
        lignes.sort { $0.place.avant($1.place) || (!$1.place.avant($0.place) && $0.rang < $1.rang) }
        return .array(lignes.enumerated().map { n, ligne in
            var json = ligne.json
            json["n"] = .number(Double(n + 1))
            return .object(json)
        })
    }

    // MARK: Écarts

    /// Tolérance de « comme Claude » (provisoire, mesure 4) : sous elle, deux valeurs d'un réglage
    /// ne se distinguent pas. Exposition 0,1 IL ; température 150 K pour un RAW, 3 sinon ; teinte 3 ;
    /// curseurs de −100 à +100 : 5 points, de 0 à 100 : 3 ; teintes : 5° ; angles : 0,3° ; bords du
    /// cadre : 1 % de l'image ; un interrupteur ou un mode : toute différence ; autres plages : 3 %.
    static func tolerance(cle: String, raw: Bool) -> Double {
        switch cle {
        case "Exposure2012": return 0.1
        case DevelopCatalogue.temperatureKey: return raw ? 150 : 3
        case DevelopCatalogue.tintKey: return 3
        case "CropAngle", "PerspectiveRotate": return 0.3
        case "CropLeft", "CropTop", "CropRight", "CropBottom": return 0.01
        default: break
        }
        guard let reglage = DevelopCatalogue.setting(cle) else { return 0.5 }
        if estUneTeinte(cle) { return 5 }
        if reglage.isWhole { return 0.5 }
        if reglage.min == -100, reglage.max == 100 { return 5 }
        if reglage.min == 0, reglage.max == 100 { return 3 }
        return (reglage.max - reglage.min) * 0.03
    }

    /// Comment la version de l'utilisateur se place, réglage par réglage, par rapport à celle de
    /// Claude (depuis l'état de départ commun).
    enum Sorte: String, CaseIterable {
        case commeClaude = "comme_claude", plusFort = "plus_fort", moinsFort = "moins_fort", aLInverse = "a_l_inverse",
             oublie, ajoute, autreChoix = "autre_choix"

        var texte: String {
            switch self {
            case .commeClaude: return "comme Claude"
            case .plusFort: return "plus fort que Claude"
            case .moinsFort: return "moins fort que Claude"
            case .aLInverse: return "à l'inverse de Claude"
            case .oublie: return "pas fait (Claude l'avait changé)"
            case .ajoute: return "ajouté par vous (Claude n'y touchait pas)"
            case .autreChoix: return "un autre choix que Claude"
            }
        }
    }

    /// Valeur par défaut d'une clé absente de l'état de départ : celle du catalogue (0 le plus
    /// souvent), un cadre entier pour les bords droit et bas.
    static func defaut(cle: String) -> Double {
        if cle == "CropRight" || cle == "CropBottom" { return 1 }
        return DevelopCatalogue.setting(cle)?.neutral ?? 0
    }

    /// Les tables (courbes, Look, couleurs ponctuelles) arrivent du module en « changée » ou
    /// « inchangée » depuis le départ.
    static let tableChangee = "changée", tableInchangee = "inchangée"

    /// Classe un réglage : comme Claude (à la tolérance près), plus fort, moins fort, à l'inverse,
    /// oublié (Claude l'avait changé, l'utilisateur non), ajouté (l'inverse), ou un autre choix
    /// (profil, préréglage, mode, teinte, ou deux tables changées toutes deux).
    static func classer(depart: JSONValue?, claude: JSONValue?, vous: JSONValue?, cle: String, raw: Bool) -> Sorte {
        if let c = nombre(claude), let v = nombre(vous) {
            let d = nombre(depart) ?? defaut(cle: cle)
            guard ![d, c, v].contains(ToolHandler.pendingAutoValue) else { return .autreChoix }
            let enK = cle == DevelopCatalogue.temperatureKey && [d, c, v].contains { enKelvins($0, raw: raw) }
            let tol = tolerance(cle: cle, raw: enK)
            if abs(v - c) <= tol + 1e-9 { return .commeClaude }
            let claudeBouge = abs(c - d) > tol + 1e-9, vousBouge = abs(v - d) > tol + 1e-9
            if !claudeBouge && vousBouge { return .ajoute }
            if claudeBouge && !vousBouge { return .oublie }
            // Un interrupteur, un mode ou une teinte (circulaire) : ni plus ni moins fort.
            if DevelopCatalogue.setting(cle)?.isWhole == true || estUneTeinte(cle) { return .autreChoix }
            if (c - d) * (v - d) < 0 { return .aLInverse }
            return abs(v - d) > abs(c - d) ? .plusFort : .moinsFort
        }
        let tc = claude?.string, tv = vous?.string
        let tables: Set<String> = [tableChangee, tableInchangee]
        if let tc, let tv, tables.contains(tc), tables.contains(tv) {
            switch (tc == tableChangee, tv == tableChangee) {
            case (false, false): return .commeClaude
            case (true, false): return .oublie
            case (false, true): return .ajoute
            case (true, true): return .autreChoix
            }
        }
        let td = depart.map { $0.isNull ? "" : ($0.string ?? JSONCoding.line($0)) } ?? ""
        let c = claude.map { $0.isNull ? "" : ($0.string ?? JSONCoding.line($0)) } ?? ""
        let v = vous.map { $0.isNull ? "" : ($0.string ?? JSONCoding.line($0)) } ?? ""
        if v == c { return .commeClaude }
        if v == td { return .oublie }
        if c == td { return .ajoute }
        return .autreChoix
    }

    /// Les écarts d'un exercice (`exercice` de la commande apercu avec comparer = versionClaude) :
    /// chaque écart {cle, depart, claude, vous} reçoit son panneau, sa section, son réglage, sa sorte
    /// et une ligne de texte, dans l'ordre des panneaux ; les cinq clés du cadre font une ligne. S'y
    /// ajoutent `comme_claude` (les réglages faits comme Claude), `resume` et `ecart_principal`
    /// (mesuré sur les deux images, Claude à gauche, l'utilisateur à droite). Le reste de la réponse
    /// du module (instantané, date, listes, ce qui reste dans les deux images) passe tel quel.
    static func enrichir(_ exercice: JSONValue, raw: Bool, claude: PhotoMeasurements?, vous: PhotoMeasurements?) -> JSONValue {
        var sortie = exercice.object ?? [:]
        var lignes: [(place: Place, rang: Int, sorte: Sorte, json: [String: JSONValue])] = []
        var cadre: [[String: JSONValue]] = []
        for (i, ecart) in (exercice["ecarts"]?.array ?? []).enumerated() {
            guard var entree = ecart.object, let cle = entree["cle"]?.string else { continue }
            if clesCadre.contains(cle) {
                cadre.append(entree)
                continue
            }
            let place = place(cle: cle)
            let nom = reglage(cle: cle)
            let sorte = classer(depart: entree["depart"], claude: entree["claude"], vous: entree["vous"], cle: cle, raw: raw)
            entree["panneau"] = .string(place.panneau)
            entree["section"] = place.section.map(JSONValue.string) ?? .null
            entree["reglage"] = .string(nom)
            entree["sorte"] = .string(sorte.rawValue)
            entree["texte"] = .string("\(chemin(place, reglage: nom)) : départ \(texte(cle: cle, entree["depart"], raw: raw)), "
                + "Claude \(texte(cle: cle, entree["claude"], raw: raw)), vous \(texte(cle: cle, entree["vous"], raw: raw)) — \(sorte.texte)")
            lignes.append((place, i, sorte, entree))
        }
        if !cadre.isEmpty {
            let place = place(cle: clesCadre[0])
            let sortes = cadre.compactMap { entree in
                entree["cle"]?.string.map { classer(depart: entree["depart"], claude: entree["claude"], vous: entree["vous"], cle: $0, raw: raw) }
            }
            // Le cadre en entier : comme Claude si chaque clé l'est ; oublié ou ajouté si toutes
            // le sont ; sinon un autre cadre.
            let sorte: Sorte = sortes.allSatisfy { $0 == .commeClaude } ? .commeClaude
                : sortes.allSatisfy { $0 == .oublie || $0 == .commeClaude } ? .oublie
                : sortes.allSatisfy { $0 == .ajoute || $0 == .commeClaude } ? .ajoute : .autreChoix
            var json: [String: JSONValue] = [
                "cle": "Crop", "cles": .array(cadre.compactMap { $0["cle"] }),
                "panneau": .string(place.panneau), "section": .null, "reglage": .string(nomCadre), "sorte": .string(sorte.rawValue),
            ]
            for champ in ["depart", "claude", "vous"] {
                var valeurs: [String: JSONValue] = [:]
                for entree in cadre { if let cle = entree["cle"]?.string { valeurs[cle] = entree[champ] ?? .null } }
                json[champ] = .object(valeurs)
            }
            json["texte"] = .string("\(chemin(place, reglage: nomCadre)) : départ \(texteCadre(valeursCadre(cadre, "depart"))) ; "
                + "Claude \(texteCadre(valeursCadre(cadre, "claude"))) ; vous \(texteCadre(valeursCadre(cadre, "vous"))) — \(sorte.texte)")
            lignes.append((place, Int.max, sorte, json))
        }
        lignes.sort { $0.place.avant($1.place) || (!$1.place.avant($0.place) && $0.rang < $1.rang) }
        sortie["ecarts"] = .array(lignes.map { .object($0.json) })
        sortie["comme_claude"] = .array(lignes.filter { $0.sorte == .commeClaude }.compactMap { $0.json["reglage"] })
        sortie["resume"] = .string(resume(lignes.map(\.sorte)))
        if let restent = exercice["restent"]?.array?.compactMap(\.string), !restent.isEmpty {
            sortie["a_savoir_exercice"] = .string("Ajoutés à la main sur une photo qui en avait déjà, \(restent.joined(separator: ", ")) restent dans les deux images : la version de Claude ne peut pas les retirer le temps du rendu.")
        }
        let ecarts = lignes.map { (cle: $0.json["cle"]?.string ?? "", sorte: $0.sorte, json: $0.json) }
        if let claude, let vous, let ecart = principal(claude: claude, vous: vous, ecarts: ecarts, raw: raw) {
            sortie["ecart_principal"] = ecart.json
        } else {
            sortie["ecart_principal"] = ["visible": false, "texte": .string(claude == nil || vous == nil
                ? "Écart principal non mesuré : une des deux images est illisible."
                : "Aucun écart mesuré ne dépasse les seuils de visibilité du bilan : les deux versions se ressemblent à l'image.")]
        }
        return .object(sortie)
    }

    /// « 7 réglages comparés : 4 comme Claude, 1 plus fort, 1 oublié, 1 ajouté. »
    static func resume(_ sortes: [Sorte]) -> String {
        guard !sortes.isEmpty else { return "Aucun réglage à comparer." }
        let mots: [Sorte: (String, String)] = [
            .commeClaude: ("comme Claude", "comme Claude"), .plusFort: ("plus fort", "plus forts"), .moinsFort: ("moins fort", "moins forts"),
            .aLInverse: ("à l'inverse", "à l'inverse"), .oublie: ("oublié", "oubliés"), .ajoute: ("ajouté", "ajoutés"),
            .autreChoix: ("autre choix", "autres choix"),
        ]
        let parties = Sorte.allCases.compactMap { sorte -> String? in
            let n = sortes.filter { $0 == sorte }.count
            guard n > 0, let mot = mots[sorte] else { return nil }
            return "\(n) \(n > 1 ? mot.1 : mot.0)"
        }
        return "\(sortes.count) réglage\(sortes.count > 1 ? "s" : "") comparé\(sortes.count > 1 ? "s" : "") : \(parties.joined(separator: ", "))."
    }

    // MARK: Écart principal

    /// Les réglages qui expliquent chaque mesure du bilan : clés exactes, ou préfixes terminés par
    /// « * » (« Parametric* » : toute la courbe paramétrique).
    static let familles: [String: [String]] = {
        let courbes = DevelopCatalogue.curveKeys.map(\.key)
        let ecretage = ["Highlights2012", "Whites2012", "Exposure2012"]
        let saturation = ["Vibrance", "Saturation", "SaturationAdjustment*"]
        return [
            "exposition": ["Exposure2012", "Shadows2012", "Highlights2012", "Whites2012", "Blacks2012"] + courbes,
            "contraste": ["Contrast2012", "Whites2012", "Blacks2012", "Clarity2012", "Dehaze", "Parametric*"] + courbes,
            "hautes_lumieres_pct": ecretage, "blanc_pur_pct": ecretage, "canal_ecrete": ecretage,
            "ombres_bouchees_pct": ["Shadows2012", "Blacks2012"],
            "dominante_b": [DevelopCatalogue.temperatureKey, "ColorGrade*", "SplitToning*"],
            "dominante_a": [DevelopCatalogue.tintKey, "ShadowTint", "RedHue", "RedSaturation", "GreenHue", "GreenSaturation", "BlueHue", "BlueSaturation"],
            "chroma_moyenne": saturation, "tres_saturee_pct": saturation,
        ]
    }()

    /// Une clé appartient à la famille d'une mesure.
    static func dansLaFamille(_ cle: String, _ mesure: String) -> Bool {
        (familles[mesure] ?? []).contains { $0.hasSuffix("*") ? cle.hasPrefix(String($0.dropLast())) : cle == $0 }
    }

    /// L'écart principal entre la version de Claude et celle de l'utilisateur.
    struct Principal {
        /// La mesure du bilan (exposition, contraste, hautes_lumieres_pct…).
        var mesure: String
        /// Après moins avant : l'utilisateur moins Claude, dans l'unité de la mesure (IL pour
        /// l'exposition, L* pour le contraste, points de % pour l'écrêtage…).
        var ecart: Double
        var claude: Double
        var vous: Double
        /// Le seuil de visibilité du bilan, et combien de fois l'écart le dépasse.
        var seuil: Double
        var fois: Double
        /// Le canal pour canal_ecrete.
        var canal: String?
        /// Le réglage de la famille qui l'explique le mieux (nil : aucun réglage global).
        var reglage: [String: JSONValue]?

        var json: JSONValue {
            var json: [String: JSONValue] = [
                "visible": true, "mesure": .string(mesure),
                "claude": Bilan.arrondi(claude), "vous": Bilan.arrondi(vous),
                "ecart": Bilan.arrondi(ecart, parts: mesure == "exposition" ? 20 : 10),
                "seuil": .number(seuil), "fois_le_seuil": Bilan.arrondi(fois),
                "texte": .string(texte),
            ]
            if let canal { json["canal"] = .string(canal) }
            if let reglage {
                json["reglage"] = .object(reglage.filter { ["cle", "cles", "reglage", "panneau", "section", "depart", "claude", "vous", "sorte", "texte"].contains($0.key) })
            }
            return .object(json)
        }

        /// « Votre version est plus claire de 0,6 IL (visible dès 0,1 IL). Le réglage qui l'explique
        /// le mieux : … »
        var texte: String {
            let n = { (x: Double, d: Int) in JeLeFais.nombre(abs(x), signe: false, decimales: d) }
            let s = { (x: Double) in JeLeFais.nombre(x, signe: true, decimales: 1) }
            let pct = JeLeFais.espaceUnite + "%"
            let plus = ecart > 0
            let constat: String
            switch mesure {
            case "exposition": constat = "plus \(plus ? "claire" : "sombre") de \(n(ecart, 2)) IL (visible dès \(n(seuil, 1)) IL)"
            case "contraste": constat = "\(plus ? "plus" : "moins") contrastée : \(n(claude, 1)) → \(n(vous, 1)) en L*, p95 moins p5 (visible dès \(n(seuil, 0)))"
            case "hautes_lumieres_pct": constat = "avec \(plus ? "plus" : "moins") de hautes lumières écrêtées : \(n(claude, 1)) → \(n(vous, 1))\(pct) (visible dès \(n(seuil, 1)) point)"
            case "blanc_pur_pct": constat = "avec \(plus ? "plus" : "moins") de blanc pur : \(n(claude, 1)) → \(n(vous, 1))\(pct) (visible dès \(n(seuil, 1)) point)"
            case "ombres_bouchees_pct": constat = "avec \(plus ? "plus" : "moins") d'ombres bouchées : \(n(claude, 1)) → \(n(vous, 1))\(pct) (visible dès \(n(seuil, 1)) point)"
            case "canal_ecrete": constat = "avec le canal \(canal ?? "") \(plus ? "plus" : "moins") écrêté : \(n(claude, 1)) → \(n(vous, 1))\(pct) (visible dès \(n(seuil, 1)) point)"
            case "dominante_b": constat = "plus \(plus ? "chaude (jaune)" : "froide (bleue)") : b* des tons neutres \(s(claude)) → \(s(vous)) (visible dès \(n(seuil, 1)))"
            case "dominante_a": constat = "plus \(plus ? "magenta" : "verte") : a* des tons neutres \(s(claude)) → \(s(vous)) (visible dès \(n(seuil, 1)))"
            case "chroma_moyenne": constat = "\(plus ? "plus" : "moins") saturée : chroma moyenne \(n(claude, 1)) → \(n(vous, 1)) (visible dès \(n(seuil, 0)))"
            default: constat = "avec \(plus ? "plus" : "moins") de couleurs très saturées : \(n(claude, 1)) → \(n(vous, 1))\(pct) (visible dès \(n(seuil, 0)) point)"
            }
            var texte = "Votre version est \(constat)."
            if let reglage, let ligne = reglage["texte"]?.string {
                texte += " Le réglage qui l'explique le mieux : \(ligne)."
            } else {
                texte += " Aucun réglage global de sa famille ne l'explique : un masque, une tache ou une courbe ?"
            }
            return texte
        }
    }

    /// L'écart principal : l'écart mesuré le plus grand une fois ramené à son seuil de visibilité du
    /// bilan (exposition 0,1 IL, contraste 4, écrêtage 0,3 point, dominante 1,5, chroma 3, très
    /// saturée 1 point : ceux de Bilan, rien de nouveau), de Claude (`claude`, à gauche) à
    /// l'utilisateur (`vous`). Dans sa famille, le réglage retenu est celui dont l'écart entre les deux
    /// versions dépasse le plus sa tolérance (une courbe changée vient en dernier). Nil si rien ne
    /// passe son seuil.
    static func principal(claude: PhotoMeasurements, vous: PhotoMeasurements,
                          ecarts: [(cle: String, sorte: Sorte, json: [String: JSONValue])], raw: Bool) -> Principal? {
        var candidats: [(mesure: String, ecart: Double, claude: Double, vous: Double, seuil: Double, canal: String?)] = [
            ("exposition", Measurements.ecartIL(claude, vous), claude.medianL, vous.medianL, Bilan.seuilExposition, nil),
            ("contraste", vous.contrast - claude.contrast, claude.contrast, vous.contrast, Bilan.seuilContraste, nil),
            ("hautes_lumieres_pct", vous.clippedHighlights - claude.clippedHighlights, claude.clippedHighlights, vous.clippedHighlights, Bilan.ecartEcretage, nil),
            ("blanc_pur_pct", vous.pureWhite - claude.pureWhite, claude.pureWhite, vous.pureWhite, Bilan.ecartEcretage, nil),
            ("ombres_bouchees_pct", vous.crushedShadows - claude.crushedShadows, claude.crushedShadows, vous.crushedShadows, Bilan.ecartEcretage, nil),
            ("chroma_moyenne", vous.meanChroma - claude.meanChroma, claude.meanChroma, vous.meanChroma, Bilan.seuilChroma, nil),
            ("tres_saturee_pct", vous.saturatedShare - claude.saturatedShare, claude.saturatedShare, vous.saturatedShare, Bilan.ecartSaturee, nil),
        ]
        if claude.clippedChannels.count == 3, vous.clippedChannels.count == 3 {
            let noms = ["rouge", "vert", "bleu"]
            let i = (0..<3).max { abs(vous.clippedChannels[$0] - claude.clippedChannels[$0]) < abs(vous.clippedChannels[$1] - claude.clippedChannels[$1]) } ?? 0
            candidats.append(("canal_ecrete", vous.clippedChannels[i] - claude.clippedChannels[i], claude.clippedChannels[i], vous.clippedChannels[i],
                              Bilan.ecartEcretage, noms[i]))
        }
        // La dominante ne se juge qu'avec assez de tons neutres des deux côtés (comme le bilan).
        if claude.neutralShare >= PhotoMeasurements.partNeutreMin, vous.neutralShare >= PhotoMeasurements.partNeutreMin {
            candidats.append(("dominante_b", vous.neutralB - claude.neutralB, claude.neutralB, vous.neutralB, Bilan.seuilDominante, nil))
            candidats.append(("dominante_a", vous.neutralA - claude.neutralA, claude.neutralA, vous.neutralA, Bilan.seuilDominante, nil))
        }
        // Le plus visible ; à égalité, l'ordre ci-dessus (l'exposition d'abord).
        var meilleur: (index: Int, fois: Double)?
        for (i, c) in candidats.enumerated() {
            let fois = abs(c.ecart) / c.seuil
            guard fois >= 1 - 1e-9 else { continue }
            if meilleur == nil || fois > meilleur!.fois + 1e-9 { meilleur = (i, fois) }
        }
        guard let meilleur else { return nil }
        let c = candidats[meilleur.index]
        return Principal(mesure: c.mesure, ecart: c.ecart, claude: c.claude, vous: c.vous, seuil: c.seuil, fois: meilleur.fois,
                         canal: c.canal, reglage: reglageEnCause(c.mesure, ecarts: ecarts, raw: raw))
    }

    /// Le réglage de la famille d'une mesure dont l'écart entre les deux versions dépasse le plus sa
    /// tolérance ; une table changée (courbe) seulement si aucun nombre ne diffère.
    static func reglageEnCause(_ mesure: String, ecarts: [(cle: String, sorte: Sorte, json: [String: JSONValue])], raw: Bool) -> [String: JSONValue]? {
        var meilleur: (score: Double, json: [String: JSONValue])?
        var table: [String: JSONValue]?
        for ecart in ecarts where ecart.sorte != .commeClaude && dansLaFamille(ecart.cle, mesure) {
            guard let c = nombre(ecart.json["claude"]), let v = nombre(ecart.json["vous"]) else {
                if table == nil { table = ecart.json }
                continue
            }
            let enK = ecart.cle == DevelopCatalogue.temperatureKey && (enKelvins(c, raw: raw) || enKelvins(v, raw: raw))
            let score = abs(v - c) / tolerance(cle: ecart.cle, raw: enK)
            if meilleur == nil || score > meilleur!.score { meilleur = (score, ecart.json) }
        }
        return meilleur?.json ?? table
    }
}
