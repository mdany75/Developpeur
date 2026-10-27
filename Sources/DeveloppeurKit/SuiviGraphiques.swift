import CoreGraphics
import Foundation

/// `mcp-developpeur --graphiques '<json>' <dossier>` (correctif 1.3.7) : les agrégats du relevé
/// `suivi.json` (et du carnet `carnet.json`, pour l'horizon et la mise au point vus par Claude) sur
/// une période (d'un jour de début, ou de la première photo, à un jour de fin, depuis le correctif
/// 1.3.8 : demandé par Dany le 26 octobre 2026 ; trois périodes fixes avant), les tuiles, et les neuf graphiques avec leurs barres et leurs créneaux, dans le repère
/// de l'image en points (origine en haut à gauche, y vers le bas). Les règles sont celles de
/// `regles.graphiques`, `regles.periodes`, `regles.tranches`, `regles.textes` et `regles.geometrie`
/// de Tests/Contrats/suivi.json ; chaque nombre de ses exemples en découle. Lecture seule des deux
/// fichiers : ni Lightroom, ni le catalogue, ni un original. Le dessin est dans SuiviDessin.swift.
extension Suivi {
    // MARK: Les graphiques

    enum Orientation: String {
        case verticale, horizontale
    }

    /// Ce qui ne dépend que du graphique : son orientation, son nombre fixe de créneaux (la fenêtre
    /// Suivi pose un calque sur chacun, une fois pour toutes), son unité, et s'il s'étale (une barre
    /// par colonne de la période, sur plusieurs créneaux).
    struct Definition {
        var orientation: Orientation
        var maxBarres: Int
        var unite: String
        var etale: Bool
    }

    /// Les neuf graphiques, dans l'ordre de la fenêtre (87 créneaux en tout ; les notes et les genres
    /// depuis le correctif 1.3.8, demandés par Dany le 26 octobre 2026).
    public static let graphiques = ["photos_par_mois", "focales", "iso", "heures", "objectifs", "notes", "genres", "defauts_frequents",
                                    "evolution_defaut"]
    static let definitions: [String: Definition] = [
        "photos_par_mois": Definition(orientation: .verticale, maxBarres: 13, unite: "photos", etale: true),
        "focales": Definition(orientation: .verticale, maxBarres: 8, unite: "photos", etale: false),
        "iso": Definition(orientation: .verticale, maxBarres: 8, unite: "photos", etale: false),
        "heures": Definition(orientation: .verticale, maxBarres: 12, unite: "photos", etale: false),
        "objectifs": Definition(orientation: .horizontale, maxBarres: 8, unite: "photos", etale: false),
        "notes": Definition(orientation: .verticale, maxBarres: 6, unite: "photos", etale: false),
        "genres": Definition(orientation: .horizontale, maxBarres: 11, unite: "photos", etale: false),
        "defauts_frequents": Definition(orientation: .horizontale, maxBarres: 8, unite: "%", etale: false),
        "evolution_defaut": Definition(orientation: .verticale, maxBarres: 13, unite: "%", etale: true),
    ]
    /// Les tailles permises d'un graphique, en points.
    static let largeurs = 120...1200, hauteurs = 80...600
    /// Les six couleurs que le module tire de Dispositions.PALETTES (seule table des couleurs).
    static let clesCouleurs = ["fond", "texte", "gris", "filet", "barre", "accent"]
    /// Les colonnes du temps au plus (le nombre de créneaux des graphiques étalés) : treize, pour qu'une
    /// année comptée d'un jour au même jour de l'année suivante (treize mois touchés) se montre mois par
    /// mois.
    static let colonnesMax = 13
    /// Un défaut cherché sur moins de photos ne peut être « le plus fréquent » que s'il n'y en a pas
    /// d'autre : le même seuil que Carnet.PHOTOS_SUFFISANTES du module.
    static let photosSuffisantes = 5

    /// Les noms des mois, comme Carnet.MOIS et Carnet.MOIS_COURTS du module.
    static let moisLongs = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre",
                            "novembre", "décembre"]
    static let moisCourts = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

    /// Une tranche fixe : la borne qu'elle ne dépasse pas (nil pour la dernière), son libellé court et
    /// son détail.
    struct Tranche {
        var jusqua: Double?
        var libelle: String
        var detail: String
    }

    /// Faites pour les focales des objectifs Fujifilm (16-80, 23, 56, 70-300) ; un iPhone (6,8 mm)
    /// tombe dans « ≤ 15 ». La focale se range arrondie au mm (demi vers le haut).
    static let tranchesFocales = [
        Tranche(jusqua: 15, libelle: "≤ 15", detail: "15 mm ou moins"),
        Tranche(jusqua: 23, libelle: "≤ 23", detail: "16 à 23 mm"),
        Tranche(jusqua: 35, libelle: "≤ 35", detail: "24 à 35 mm"),
        Tranche(jusqua: 55, libelle: "≤ 55", detail: "36 à 55 mm"),
        Tranche(jusqua: 90, libelle: "≤ 90", detail: "56 à 90 mm"),
        Tranche(jusqua: 150, libelle: "≤ 150", detail: "91 à 150 mm"),
        Tranche(jusqua: 300, libelle: "≤ 300", detail: "151 à 300 mm"),
        Tranche(jusqua: nil, libelle: "> 300", detail: "plus de 300 mm"),
    ]
    /// `Carnet.isoEleve` (1 600) est la borne de « ≤ 1 600 » : le bruit fort se cherche au-dessus.
    static let tranchesISO = [
        Tranche(jusqua: 200, libelle: "≤ 200", detail: "ISO 200 ou moins"),
        Tranche(jusqua: 400, libelle: "≤ 400", detail: "ISO 201 à 400"),
        Tranche(jusqua: 800, libelle: "≤ 800", detail: "ISO 401 à 800"),
        Tranche(jusqua: 1600, libelle: "≤ 1 600", detail: "ISO 801 à 1 600"),
        Tranche(jusqua: 3200, libelle: "≤ 3 200", detail: "ISO 1 601 à 3 200"),
        Tranche(jusqua: 6400, libelle: "≤ 6 400", detail: "ISO 3 201 à 6 400"),
        Tranche(jusqua: 12800, libelle: "≤ 12 800", detail: "ISO 6 401 à 12 800"),
        Tranche(jusqua: nil, libelle: "> 12 800", detail: "plus de ISO 12 800"),
    ]

    static func tranche(_ valeur: Double, _ tranches: [Tranche]) -> Int {
        tranches.firstIndex { $0.jusqua.map { valeur <= $0 } ?? true } ?? tranches.count - 1
    }

    static let noteDefauts = "En % des photos où il est cherché : bruit à ISO 1 600 et plus, yeux sur un visage, horizon et mise au point quand Claude regarde la photo."
    static let carnetIllisible = "carnet.json illisible : l'horizon et la mise au point vus par Claude ne comptent pas."

    // MARK: L'entrée

    /// Une date à l'heure locale, « AAAA-MM-JJ HH:MM » (l'heure peut manquer).
    struct DateLocale: Equatable {
        var annee: Int
        var mois: Int
        var jour: Int
        var heure: Int?

        /// Le rang du mois (année × 12 + mois − 1), pour comparer et compter les mois.
        var rangMois: Int { annee * 12 + mois - 1 }

        init(annee: Int, mois: Int, jour: Int, heure: Int? = nil) {
            (self.annee, self.mois, self.jour, self.heure) = (annee, mois, jour, heure)
        }

        /// Le jour, pour comparer (année × 10 000 + mois × 100 + jour).
        var cle: Int { annee * 10000 + mois * 100 + jour }
        /// Le trimestre (année × 4 + trimestre − 1).
        var rangTrimestre: Int { annee * 4 + (mois - 1) / 3 }
        /// Le même jour, sans l'heure.
        var jourSeul: DateLocale { DateLocale(annee: annee, mois: mois, jour: jour) }
        /// « AAAA-MM-JJ ».
        var iso: String { String(format: "%04d-%02d-%02d", annee, mois, jour) }
        /// « 20 novembre 2026 », « 1er mars 2026 ».
        var texte: String { "\(jour == 1 ? "1er" : String(jour)) \(Suivi.moisLongs[mois - 1]) \(annee)" }

        /// Le nombre de jours du mois.
        static func jours(annee: Int, mois: Int) -> Int {
            switch mois {
            case 2: return annee % 4 == 0 && (annee % 100 != 0 || annee % 400 == 0) ? 29 : 28
            case 4, 6, 9, 11: return 30
            default: return 31
            }
        }

        /// Un jour « AAAA-MM-JJ » qui existe (le 31 avril, non), de 1900 à 9999 ; nil sinon.
        static func jourExact(_ texte: String?) -> DateLocale? {
            guard let texte, texte.utf8.count == 10, let d = DateLocale(texte), d.annee >= 1900,
                  d.jour <= jours(annee: d.annee, mois: d.mois) else { return nil }
            return d
        }

        init?(_ texte: String?) {
            guard let texte else { return nil }
            let c = Array(texte.utf8)
            func nombre(_ debut: Int, _ longueur: Int) -> Int? {
                guard debut + longueur <= c.count else { return nil }
                var valeur = 0
                for octet in c[debut..<(debut + longueur)] {
                    guard octet >= 48, octet <= 57 else { return nil }
                    valeur = valeur * 10 + Int(octet - 48)
                }
                return valeur
            }
            guard c.count >= 10, c[4] == 45, c[7] == 45, let annee = nombre(0, 4), let mois = nombre(5, 2), let jour = nombre(8, 2),
                  (1...12).contains(mois), (1...31).contains(jour) else { return nil }
            self.init(annee: annee, mois: mois, jour: jour)
            if c.count >= 13, c[10] == 32 || c[10] == 84, let heure = nombre(11, 2), (0...23).contains(heure) { self.heure = heure }
        }
    }

    /// L'entrée de `--graphiques`, vérifiée (`graphiques.entree` du contrat).
    struct EntreeGraphiques {
        var suivi: String
        var carnet: String?
        var catalogue: String
        /// Le premier jour de la période ; nil : depuis la première photo.
        var debut: DateLocale?
        /// Le dernier jour de la période (compris).
        var fin: DateLocale
        var apparence: String
        var couleurs: [String: String]
        var defaut: String?
        var tailles: [String: (largeur: Int, hauteur: Int)]
    }

    static func lireEntree(_ texte: String) throws -> EntreeGraphiques {
        let prefixe = "Arguments de --graphiques : "
        func refus(_ detail: String) -> Refus { Refus(raison: "arguments", texte: prefixe + detail) }
        guard let objet = (try? JSONCoding.parse(texte))?.object else {
            throw refus("le JSON ne se lit pas (un objet attendu, comme graphiques.entree du contrat).")
        }
        guard let suivi = objet["suivi"]?.string, !suivi.isEmpty else { throw refus("suivi est le chemin de suivi.json.") }
        var carnet: String?
        if let valeur = objet["carnet"] {
            guard let chemin = valeur.string else { throw refus("carnet, facultatif, est le chemin de carnet.json.") }
            carnet = chemin.isEmpty ? nil : chemin
        }
        guard let catalogue = objet["catalogue"]?.string, !catalogue.isEmpty else {
            throw refus("catalogue est le chemin du catalogue ouvert.")
        }
        guard let fin = DateLocale.jourExact(objet["fin"]?.string) else {
            throw refus("fin est le dernier jour de la période, AAAA-MM-JJ, à l'heure locale.")
        }
        var debut: DateLocale?
        if let valeur = objet["debut"] {
            guard let jour = DateLocale.jourExact(valeur.string) else {
                throw refus("debut, facultatif, est le premier jour de la période, AAAA-MM-JJ, à l'heure locale.")
            }
            guard jour.cle <= fin.cle else { throw refus("debut ne vient pas après fin.") }
            debut = jour
        }
        guard let apparence = objet["apparence"]?.string, ["claire", "sombre"].contains(apparence) else {
            throw refus("apparence vaut claire ou sombre.")
        }
        guard let couleursDonnees = objet["couleurs"]?.object else {
            throw refus("couleurs donne fond, texte, gris, filet, barre et accent, en six chiffres hexadécimaux.")
        }
        var couleurs: [String: String] = [:]
        for cle in clesCouleurs {
            guard let hex = couleursDonnees[cle]?.string, couleurHex(hex) != nil else {
                throw refus("couleurs.\(cle) est une couleur en six chiffres hexadécimaux (0A64D8).")
            }
            couleurs[cle] = hex
        }
        var defaut: String?
        if let valeur = objet["defaut"] {
            guard let code = valeur.string else { throw refus("defaut, facultatif, est l'un des huit codes comptés.") }
            guard codes.contains(code) else {
                throw Refus(raison: "defaut_inconnu",
                            texte: "« \(code) » n'est pas un défaut que le Suivi compte (\(codes.joined(separator: ", "))).")
            }
            defaut = code
        }
        guard let taillesDonnees = objet["tailles"]?.object else {
            throw refus("tailles donne les neuf graphiques (\(graphiques.joined(separator: ", "))), chacun { largeur, hauteur }.")
        }
        var tailles: [String: (largeur: Int, hauteur: Int)] = [:]
        for cle in graphiques {
            guard let largeur = taillesDonnees[cle]?["largeur"]?.int, let hauteur = taillesDonnees[cle]?["hauteur"]?.int,
                  largeurs.contains(largeur), hauteurs.contains(hauteur) else {
                throw refus("tailles.\(cle) va de \(largeurs.lowerBound) × \(hauteurs.lowerBound) à \(milliers(largeurs.upperBound)) × \(hauteurs.upperBound) points.")
            }
            tailles[cle] = (largeur, hauteur)
        }
        return EntreeGraphiques(suivi: suivi, carnet: carnet, catalogue: catalogue, debut: debut, fin: fin, apparence: apparence,
                                couleurs: couleurs, defaut: defaut, tailles: tailles)
    }

    /// Une couleur en six chiffres hexadécimaux (« 0A64D8 »), en sRVB ; nil sinon.
    static func couleurHex(_ texte: String) -> CGColor? {
        let octets = Array(texte.utf8)
        guard octets.count == 6, octets.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let valeur = UInt32(texte, radix: 16) else { return nil }
        return CGColor(srgbRed: Double((valeur >> 16) & 0xFF) / 255, green: Double((valeur >> 8) & 0xFF) / 255,
                       blue: Double(valeur & 0xFF) / 255, alpha: 1)
    }

    // MARK: Le relevé et le carnet

    /// Un original du relevé, réduit à ce que les graphiques comptent.
    struct PhotoSuivie {
        enum Etat { case analysee, enAttente, enEchec }

        var cle: String
        var id: Int
        var uuid: String?
        var prise: DateLocale?
        var ajout: DateLocale?
        var objectif: String?
        var focale: Double?
        var iso: Double?
        var note: Int
        /// Le drapeau de la famille vaut « rejetee » (toutes ses photos rejetées).
        var rejetee: Bool
        var retouchee: Bool
        var etat: Etat
        /// Pour chaque code cherché : trouvé ou non (l'analyse, puis le carnet par-dessus).
        var resultats: [String: Bool]
        /// Le genre lu par --analyser (un code de `Genre`, correctif 1.3.8) ; nil : pas encore classée.
        var genre: String? = nil

        /// La date qui la place dans une période : la prise de vue, sinon l'ajout au Suivi.
        var date: DateLocale? { prise ?? ajout }
    }

    // Lectures d'un objet de JSONSerialization (bien plus rapide que JSONValue pour des dizaines de
    // milliers d'entrées : 250 000 originaux, la borne du relevé depuis le correctif 1.3.8, en 2,9 s).
    static func nombre(_ valeur: Any?) -> Double? {
        guard let n = valeur as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let double = n.doubleValue
        return double.isFinite ? double : nil
    }

    static func booleen(_ valeur: Any?) -> Bool? {
        guard let n = valeur as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    static func textes(_ valeur: Any?) -> [String] { (valeur as? [Any])?.compactMap { $0 as? String } ?? [] }

    // Les nombres du relevé, gardés seulement s'ils sont plausibles : un relevé lisible mais abîmé ou
    // édité à la main (une focale à 1e20, une note à 1e20, un original à 1e30) ne doit jamais arrêter
    // --graphiques (« Double value cannot be converted to Int » : ni ligne, ni code 1). Le module
    // n'écrit que des valeurs venues de Lightroom.

    /// Au-delà, une focale ou un ISO n'est pas une valeur lue : comptés « sans focale lue », « sans ISO
    /// lu ».
    static let valeurPlausibleMax = 1e6

    /// Une focale ou un ISO plausible (fini, positif, sous `valeurPlausibleMax`) ; nil sinon : absent.
    static func plausible(_ valeur: Double?) -> Double? {
        guard let valeur, valeur > 0, valeur < valeurPlausibleMax else { return nil }
        return valeur
    }

    /// La note de la famille, de 0 à 5, comme Releve.lua la relit (partie entière, bornée) ; 0 sans
    /// note lue.
    static func noteBornee(_ valeur: Double?) -> Int {
        guard let valeur else { return 0 }
        return Int(min(5, max(0, valeur.rounded(.down))))
    }

    /// L'identifiant d'un original lu dans `original` : un entier qu'un Double représente exactement
    /// (2^53 au plus) ; nil sinon (l'entrée est ignorée).
    static func identifiant(_ valeur: Double?) -> Int? {
        guard let valeur, abs(valeur) <= 9_007_199_254_740_992 else { return nil }
        return Int(exactly: valeur)
    }

    /// La table d'un catalogue dans un fichier de format 1 (`catalogues › <chemin> › photos`) ; nil si
    /// le fichier n'est pas un objet JSON de format 1. Un fichier sans ce catalogue : une table vide.
    static func photosDuCatalogue(_ chemin: String, catalogue: String) -> [String: Any]? {
        guard let donnees = FileManager.default.contents(atPath: chemin),
              let racine = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any],
              nombre(racine["format"]) == 1 else { return nil }
        guard let catalogues = racine["catalogues"] else { return [:] }
        guard let tables = catalogues as? [String: Any] else { return nil }
        return (tables[catalogue] as? [String: Any])?["photos"] as? [String: Any] ?? [:]
    }

    /// Les originaux du relevé pour le catalogue : vide sans fichier (rien n'est refusé), refus
    /// `suivi_illisible` pour un fichier qui ne se lit pas ou d'un autre format.
    static func lireReleve(_ chemin: String, catalogue: String) throws -> [PhotoSuivie] {
        guard FileManager.default.fileExists(atPath: chemin) else { return [] }
        guard let table = photosDuCatalogue(chemin, catalogue: catalogue) else {
            throw Refus(raison: "suivi_illisible", texte: "suivi.json illisible (JSON invalide, ou format autre que 1) : rien n'est dessiné.")
        }
        let comptes = Set(codes)
        let genres = Set(Genre.codes)
        return table.compactMap { cle, valeur -> PhotoSuivie? in
            guard let entree = valeur as? [String: Any], let id = Int(cle) ?? identifiant(nombre(entree["original"])) else { return nil }
            let prise = entree["prise_de_vue"] as? [String: Any] ?? [:]
            let objectif = (prise["objectif"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            var etat = PhotoSuivie.Etat.enAttente
            var resultats: [String: Bool] = [:]
            var genre: String?
            if let analyse = entree["analyse"] as? [String: Any] {
                if let code = analyse["genre"] as? String, genres.contains(code) { genre = code }
                if analyse["cherches"] is [Any] {
                    etat = .analysee
                    let trouves = Set(textes(analyse["defauts"]))
                    for code in textes(analyse["cherches"]) where comptes.contains(code) { resultats[code] = trouves.contains(code) }
                } else if booleen(analyse["abandonnee"]) == true {
                    etat = .enEchec
                }
            }
            return PhotoSuivie(cle: cle, id: id, uuid: entree["uuid"] as? String, prise: DateLocale(prise["le"] as? String),
                               ajout: DateLocale(entree["ajout_le"] as? String), objectif: objectif,
                               focale: plausible(nombre(prise["focale"])), iso: plausible(nombre(prise["iso"])),
                               note: noteBornee(nombre(entree["note"])), rejetee: entree["drapeau"] as? String == "rejetee",
                               retouchee: booleen(entree["retouchee_par_claude"]) ?? false,
                               etat: etat, resultats: resultats, genre: genre)
        }
    }

    /// Le carnet par-dessus l'analyse (`codes.fusion_avec_le_carnet` du contrat) : pour une entrée
    /// du carnet sous la même clé, du même uuid, chaque code compté qu'il a cherché (vue.cherches, et
    /// le code de l'angle) prend son résultat (trouvé : dans vue.defauts, ou le code de l'angle), car
    /// il est mesuré sur l'aperçu de view_photo, au point de mise au point. Une entrée du carnet
    /// absente du relevé ne compte jamais. Rend vrai si le carnet existe mais ne se lit pas.
    static func fusionnerCarnet(_ chemin: String?, catalogue: String, dans photos: inout [PhotoSuivie]) -> Bool {
        guard let chemin, FileManager.default.fileExists(atPath: chemin) else { return false }
        guard let table = photosDuCatalogue(chemin, catalogue: catalogue) else { return true }
        let comptes = Set(codes)
        for index in photos.indices {
            guard let entree = table[photos[index].cle] as? [String: Any], let uuid = photos[index].uuid,
                  entree["uuid"] as? String == uuid else { continue }
            var cherches: Set<String> = [], trouves: Set<String> = []
            if let vue = entree["vue"] as? [String: Any] {
                cherches.formUnion(textes(vue["cherches"]))
                for defaut in vue["defauts"] as? [Any] ?? [] {
                    if let code = defaut as? String { trouves.insert(code) }
                    if let code = (defaut as? [String: Any])?["code"] as? String { trouves.insert(code) }
                }
            }
            if let code = (entree["angle"] as? [String: Any])?["code"] as? String {
                cherches.insert(code)
                trouves.insert(code)
            }
            for code in cherches where comptes.contains(code) { photos[index].resultats[code] = trouves.contains(code) }
        }
        return false
    }

    // MARK: La géométrie

    /// Un rectangle en points entiers, dans le repère de l'image (origine en haut à gauche).
    struct Rect: Equatable {
        var x: Int, y: Int, largeur: Int, hauteur: Int

        var json: JSONValue {
            ["x": .number(Double(x)), "y": .number(Double(y)), "largeur": .number(Double(largeur)), "hauteur": .number(Double(hauteur))]
        }
    }

    struct Barre {
        var libelle: String
        var detail: String
        var valeur: Double
        var texte: String
        var n: Int
        var sur: Int?
        var ids: [Int]
        var couleur: String
        var rect = Rect(x: 0, y: 0, largeur: 0, hauteur: 0)
        var zone = Rect(x: 0, y: 0, largeur: 0, hauteur: 0)

        var json: JSONValue {
            var objet: [String: JSONValue] = [
                "libelle": .string(libelle), "detail": .string(detail), "valeur": .number(valeur), "texte": .string(texte),
                "n": .number(Double(n)), "ids": .array(ids.map { .number(Double($0)) }), "couleur": .string(couleur),
                "x": .number(Double(rect.x)), "y": .number(Double(rect.y)), "largeur": .number(Double(rect.largeur)),
                "hauteur": .number(Double(rect.hauteur)), "zone": zone.json,
            ]
            if let sur { objet["sur"] = .number(Double(sur)) }
            return .object(objet)
        }
    }

    struct Graphique {
        var cle: String
        var titre: String
        var fichier: String
        var largeur: Int
        var hauteur: Int
        var definition: Definition
        var echelle: Double = 0
        var sansValeur: Int = 0
        var note: String?
        var vide: Bool = true
        /// Ce que dit un graphique vide, au milieu.
        var texteVide = "Aucune photo"
        var barres: [Barre] = []
        var creneaux: [(rect: Rect, barre: Int)] = []

        var json: JSONValue {
            var objet: [String: JSONValue] = [
                "titre": .string(titre), "fichier": .string(fichier), "largeur": .number(Double(largeur)),
                "hauteur": .number(Double(hauteur)), "orientation": .string(definition.orientation.rawValue),
                "max_barres": .number(Double(definition.maxBarres)), "unite": .string(definition.unite), "echelle": .number(echelle),
                "sans_valeur": .number(Double(sansValeur)), "vide": .bool(vide), "barres": .array(barres.map(\.json)),
                "creneaux": .array(creneaux.map { creneau in
                    guard case .object(var objet) = creneau.rect.json else { return creneau.rect.json }
                    objet["barre"] = .number(Double(creneau.barre))
                    return .object(objet)
                }),
            ]
            if let note { objet["note"] = .string(note) }
            return .object(objet)
        }
    }

    /// La hauteur du tracé d'un graphique vertical : 16 points au-dessus pour les valeurs, 20 au-dessous
    /// pour les libellés.
    static func traceVertical(_ hauteur: Int) -> Int { hauteur - 36 }
    /// Libellés d'un graphique horizontal sur les `floor(0,4 × L)` premiers points, valeurs sur les 48
    /// derniers.
    static func colonneLibelles(_ largeur: Int) -> Int { Int((Double(largeur) * 0.4).rounded(.down)) }

    /// Place les barres et les créneaux (`regles.geometrie` du contrat) : les créneaux ne dépendent
    /// que de la taille ; une barre étalée en occupe plusieurs.
    static func placer(_ g: inout Graphique) {
        let n = g.definition.maxBarres, L = g.largeur, H = g.hauteur
        let k = g.barres.count
        g.echelle = g.barres.map(\.valeur).max() ?? 0
        var occupe = [Int](repeating: 0, count: n)
        func longueur(_ valeur: Double, _ trace: Int) -> Int {
            valeur > 0 && g.echelle > 0 ? max(1, arrondi(valeur / g.echelle * Double(trace))) : 0
        }
        switch g.definition.orientation {
        case .verticale:
            let xs = (0..<n).map { 8 + $0 * (L - 16) / n } + [L - 8]
            g.creneaux = (0..<n).map { (Rect(x: xs[$0], y: 0, largeur: xs[$0 + 1] - xs[$0], hauteur: H), 0) }
            let T = traceVertical(H)
            let (s, d) = g.definition.etale && k > 0 && k <= n ? (n / k, (n - (n / k) * k) / 2) : (1, 0)
            for j in g.barres.indices where d + j * s + s <= n {
                let premier = d + j * s, dernier = premier + s - 1
                for c in premier...dernier { occupe[c] = j + 1 }
                let zone = Rect(x: xs[premier], y: 0, largeur: xs[dernier + 1] - xs[premier], hauteur: H)
                let largeur = max(1, Int((Double(zone.largeur) * 0.6).rounded(.down)))
                let hauteur = longueur(g.barres[j].valeur, T)
                g.barres[j].zone = zone
                g.barres[j].rect = Rect(x: zone.x + (zone.largeur - largeur) / 2, y: 16 + T - hauteur, largeur: largeur, hauteur: hauteur)
            }
        case .horizontale:
            let ys = (0..<n).map { 4 + $0 * (H - 8) / n } + [H - 4]
            g.creneaux = (0..<n).map { (Rect(x: 0, y: ys[$0], largeur: L, hauteur: ys[$0 + 1] - ys[$0]), 0) }
            let x0 = colonneLibelles(L) + 4
            let B = L - 52 - x0
            for j in g.barres.indices where j < n {
                occupe[j] = j + 1
                let zone = Rect(x: 0, y: ys[j], largeur: L, hauteur: ys[j + 1] - ys[j])
                let hauteur = max(1, Int((Double(zone.hauteur) * 0.6).rounded(.down)))
                g.barres[j].zone = zone
                g.barres[j].rect = Rect(x: x0, y: zone.y + (zone.hauteur - hauteur) / 2, largeur: longueur(g.barres[j].valeur, B), hauteur: hauteur)
            }
        }
        for c in g.creneaux.indices { g.creneaux[c].barre = occupe[c] }
    }

    // MARK: Les agrégats

    /// Une colonne du temps : un mois (son rang), un trimestre (son rang), une année, ou les années
    /// d'avant une année.
    enum Colonne {
        case mois(Int), trimestre(Int), annee(Int), avant(Int)

        func contient(_ date: DateLocale) -> Bool {
            switch self {
            case .mois(let rang): return date.rangMois == rang
            case .trimestre(let rang): return date.rangTrimestre == rang
            case .annee(let annee): return date.annee == annee
            case .avant(let annee): return date.annee < annee
            }
        }

        /// Le libellé court (dessiné) et le début du détail (l'infobulle).
        var noms: (libelle: String, detail: String) {
            switch self {
            case .mois(let rang):
                let mois = (rang % 12 + 12) % 12
                return (Suivi.moisCourts[mois], "\(Suivi.moisLongs[mois]) \((rang - mois) / 12)")
            case .trimestre(let rang):
                let t = (rang % 4 + 4) % 4, annee = (rang - t) / 4
                return ("T\(t + 1) \(annee)", "\(Suivi.moisLongs[3 * t]) à \(Suivi.moisLongs[3 * t + 2]) \(annee)")
            case .annee(let annee): return ("\(annee)", "\(annee)")
            case .avant(let annee): return ("< \(annee)", "avant \(annee)")
            }
        }

        /// Le premier et le dernier jour de la colonne ; nil pour les années d'avant une année.
        var bornes: (premier: DateLocale, dernier: DateLocale)? {
            func jours(_ annee: Int, de premierMois: Int, a dernierMois: Int) -> (premier: DateLocale, dernier: DateLocale) {
                (DateLocale(annee: annee, mois: premierMois, jour: 1),
                 DateLocale(annee: annee, mois: dernierMois, jour: DateLocale.jours(annee: annee, mois: dernierMois)))
            }
            switch self {
            case .mois(let rang):
                let mois = (rang % 12 + 12) % 12
                return jours((rang - mois) / 12, de: mois + 1, a: mois + 1)
            case .trimestre(let rang):
                let t = (rang % 4 + 4) % 4
                return jours((rang - t) / 4, de: 3 * t + 1, a: 3 * t + 3)
            case .annee(let annee): return jours(annee, de: 1, a: 12)
            case .avant: return nil
            }
        }
    }

    /// Les libellés et les détails des colonnes du temps (correctif 1.3.8) : l'année au premier mois et
    /// à chaque janvier (« déc. 2025 », « janv. 2026 » : sur treize mois, le même mois revient) ; une
    /// colonne que la période ne couvre qu'en partie le dit dans son détail (« novembre 2025, à partir
    /// du 20 », « novembre 2026, jusqu'au 20 », « juillet à septembre 2025, à partir du 25 août »). Sans
    /// `debut` (depuis la première photo), la première colonne n'est jamais dite en partie : aucune
    /// photo n'est avant elle.
    static func nomsDesColonnes(_ colonnes: [Colonne], debut: DateLocale?, fin: DateLocale) -> [(libelle: String, detail: String)] {
        func jour(_ d: DateLocale, avecMois: Bool) -> String {
            "\(d.jour == 1 ? "1er" : String(d.jour))" + (avecMois ? " \(moisLongs[d.mois - 1])" : "")
        }
        return colonnes.enumerated().map { index, colonne in
            var (libelle, detail) = colonne.noms
            if case .mois(let rang) = colonne {
                let mois = (rang % 12 + 12) % 12
                if index == 0 || mois == 0 { libelle += " \((rang - mois) / 12)" }
            }
            guard let bornes = colonne.bornes else { return (libelle, detail) }
            var avecMois = true
            if case .mois = colonne { avecMois = false }
            // Ce que la période couvre de la colonne : de `premier` (le début, s'il tombe après son
            // premier jour) à `dernier` (la fin, si elle tombe avant son dernier jour) ; un seul jour,
            // même au bord de la colonne (le 1er, le 30), se dit « le … ».
            let apres = debut.flatMap { $0.cle > bornes.premier.cle ? $0 : nil }
            let avant = fin.cle < bornes.dernier.cle ? fin : nil
            let premier = apres ?? bornes.premier, dernier = avant ?? bornes.dernier
            if apres == nil && avant == nil { return (libelle, detail) }
            if premier.cle == dernier.cle {
                detail += ", le \(jour(premier, avecMois: avecMois))"
            } else if let a = apres, let b = avant {
                detail += ", du \(jour(a, avecMois: avecMois)) au \(jour(b, avecMois: avecMois))"
            } else if let a = apres {
                detail += ", à partir du \(jour(a, avecMois: avecMois))"
            } else if let b = avant {
                detail += ", jusqu'au \(jour(b, avecMois: avecMois))"
            }
            return (libelle, detail)
        }
    }

    /// Un défaut sur un ensemble de photos : n = celles où il est trouvé, sur = celles où il est
    /// cherché, et les ids des premières, croissants.
    static let aucun: (n: Int, sur: Int, ids: [Int]) = (0, 0, [])

    static func compte(_ code: String, _ photos: [PhotoSuivie]) -> (n: Int, sur: Int, ids: [Int]) {
        var sur = 0, ids: [Int] = []
        for photo in photos {
            guard let trouve = photo.resultats[code] else { continue }
            sur += 1
            if trouve { ids.append(photo.id) }
        }
        return (ids.count, sur, ids.sorted())
    }

    /// Le défaut le plus fréquent (`defaut_le_plus_frequent` du contrat) : parmi les codes cherchés
    /// sur au moins `photosSuffisantes` photos et trouvés une fois, sinon parmi tous ceux trouvés une
    /// fois, le plus haut pourcentage exact, puis le plus grand n, puis l'ordre des codes.
    static func plusFrequent(_ stats: [String: (n: Int, sur: Int, ids: [Int])]) -> String? {
        let ordre = codes
        let trouves = ordre.filter { (stats[$0]?.n ?? 0) >= 1 }
        let assez = trouves.filter { (stats[$0]?.sur ?? 0) >= photosSuffisantes }
        let candidats = assez.isEmpty ? trouves : assez
        var meilleur: String?
        for code in candidats {
            guard let actuel = meilleur else { meilleur = code; continue }
            let a = stats[actuel] ?? aucun, c = stats[code] ?? aucun
            let pa = part(a.n, sur: a.sur), pc = part(c.n, sur: c.sur)
            // À égalité exacte, le premier dans l'ordre des codes reste.
            if pc > pa || (pc == pa && c.n > a.n) { meilleur = code }
        }
        return meilleur
    }

    /// « N photo(s) <ce qui manque> n'y est (sont) pas. »
    static func noteSans(_ n: Int, _ quoi: String) -> String {
        "\(photos(n)) \(quoi) n'y \(n > 1 ? "sont" : "est") pas."
    }

    /// Une barre qui compte des photos (graphiques en photos).
    static func barreCompte(_ libelle: String, _ detail: String, _ ids: [Int]) -> Barre {
        Barre(libelle: libelle, detail: "\(detail) · \(photos(ids.count))", valeur: Double(ids.count), texte: milliers(ids.count),
              n: ids.count, sur: nil, ids: ids.sorted(), couleur: "barre")
    }

    /// Ce que `--graphiques` calcule, sans rien écrire : la sortie et les graphiques à dessiner.
    static func calculer(_ entree: EntreeGraphiques, photos tous: [PhotoSuivie], remarques: [String],
                         dossier: String) -> (sortie: JSONValue, graphiques: [Graphique]) {
        // La période : du jour de début (ou de la première photo) au jour de fin, compris ; une photo
        // datée après la fin (horloge de l'appareil fausse, ou une fin choisie) n'y est pas.
        let fin = entree.fin
        let periode = tous.filter { photo in
            guard let cle = photo.date?.cle else { return false }
            return cle <= fin.cle && entree.debut.map { cle >= $0.cle } ?? true
        }.sorted { $0.id < $1.id }
        let debut = entree.debut ?? periode.compactMap(\.date).min { $0.cle < $1.cle }?.jourSeul ?? fin
        let datees = periode.filter { $0.prise != nil }
        let analysees = periode.filter { $0.etat == .analysee }.count
        let enEchec = periode.filter { $0.etat == .enEchec }.count
        let enAttente = periode.count - analysees - enEchec

        var stats: [String: (n: Int, sur: Int, ids: [Int])] = [:]
        for code in codes { stats[code] = compte(code, periode) }
        let frequent = plusFrequent(stats)
        let suivi = entree.defaut ?? frequent

        // Les colonnes du temps (colonnesMax au plus) : les mois de la période, sinon ses trimestres,
        // sinon ses années, la première réunissant au besoin les années d'avant les douze dernières.
        let colonnes: [Colonne], par: String
        if fin.rangMois - debut.rangMois < colonnesMax {
            (colonnes, par) = ((debut.rangMois...fin.rangMois).map { .mois($0) }, "mois")
        } else if fin.rangTrimestre - debut.rangTrimestre < colonnesMax {
            (colonnes, par) = ((debut.rangTrimestre...fin.rangTrimestre).map { .trimestre($0) }, "trimestre")
        } else if fin.annee - debut.annee < colonnesMax {
            (colonnes, par) = ((debut.annee...fin.annee).map { .annee($0) }, "annee")
        } else {
            let premiere = fin.annee - (colonnesMax - 2)
            (colonnes, par) = ([.avant(premiere)] + (premiere...fin.annee).map { .annee($0) }, "annee")
        }
        let libellePeriode: String
        if entree.debut == nil {
            libellePeriode = periode.isEmpty ? "jusqu'au \(fin.texte)" : "depuis la première photo, le \(debut.texte), jusqu'au \(fin.texte)"
        } else {
            libellePeriode = debut.cle == fin.cle ? "le \(fin.texte)" : "du \(debut.texte) au \(fin.texte)"
        }
        let periodeJSON: JSONValue = ["debut": .string(debut.iso), "fin": .string(fin.iso), "libelle": .string(libellePeriode),
                                      "par": .string(par), "depuis_le_debut": .bool(entree.debut == nil)]

        // Les tuiles.
        let total = periode.count
        var etatAnalyse: [String] = []
        if enAttente > 0 { etatAnalyse.append("\(milliers(enAttente)) en cours d'analyse") }
        if enEchec > 0 { etatAnalyse.append("\(milliers(enEchec)) non analysée\(enEchec > 1 ? "s" : "")") }
        // « Photos analysées » (1.4, demandé par Dany le 26 octobre 2026, « Photos ouvertes » avant) :
        // les photos de la période déjà analysées ; le détail dit combien il y en a en tout et le
        // reste. Le mot « ouvertes » est retiré des tuiles à sa demande du même soir.
        let detailAnalysees = total == 0 ? "aucune photo dans la période"
            : etatAnalyse.isEmpty ? "toutes les photos" : (["sur \(photos(total))"] + etatAnalyse).joined(separator: " · ")
        func partDesPhotos(_ k: Int) -> String { total == 0 ? "—" : "\(textePourcentage(k, sur: total)) des photos" }
        func tuile(_ cle: String, _ titre: String, _ valeur: Int, _ detail: String) -> JSONValue {
            ["cle": .string(cle), "titre": .string(titre), "valeur": .number(Double(valeur)), "texte": .string(milliers(valeur)),
             "detail": .string(detail)]
        }
        let retouchees = periode.filter(\.retouchee).count
        let notees = periode.filter { $0.note >= 4 }.count
        var tuiles: [JSONValue] = [
            tuile("photos_analysees", "Photos analysées", analysees, detailAnalysees),
            tuile("retouchees_par_claude", "Retouchées par Claude", retouchees, partDesPhotos(retouchees)),
            tuile("notees_4_plus", "Notées 4 ★ ou plus", notees, partDesPhotos(notees)),
        ]
        if let frequent, let s = stats[frequent] {
            tuiles.append(["cle": "defaut_frequent", "titre": "Défaut le plus fréquent", "valeur": .number(valeurPourcentage(s.n, sur: s.sur)),
                           "texte": .string(textePourcentage(s.n, sur: s.sur)),
                           "detail": .string("\(libelle(frequent)) · \(photos(s.n)) sur \(milliers(s.sur))"), "code": .string(frequent)])
        } else if analysees > 0 {
            let surQuoi = analysees == 1 ? "la photo analysée" : "les \(milliers(analysees)) photos analysées"
            tuiles.append(["cle": "defaut_frequent", "titre": "Défaut le plus fréquent", "valeur": 0, "texte": "Aucun",
                           "detail": .string("aucun défaut trouvé sur \(surQuoi)")])
        } else {
            tuiles.append(["cle": "defaut_frequent", "titre": "Défaut le plus fréquent", "valeur": 0, "texte": "—", "detail": "aucune photo analysée"])
        }

        let defautsJSON: [JSONValue] = codes.map { code in
            let s = stats[code] ?? aucun
            return ["code": .string(code), "libelle": .string(libelle(code)), "n": .number(Double(s.n)), "sur": .number(Double(s.sur)),
                    "valeur": .number(valeurPourcentage(s.n, sur: s.sur)), "texte": .string(textePourcentage(s.n, sur: s.sur))]
        }

        func base(_ cle: String, _ titre: String) -> Graphique {
            let taille = entree.tailles[cle] ?? (largeurs.lowerBound, hauteurs.lowerBound)
            var chemin = dossier
            while chemin.count > 1, chemin.hasSuffix("/") { chemin.removeLast() }
            return Graphique(cle: cle, titre: titre, fichier: "\(chemin)/\(cle).png", largeur: taille.largeur, hauteur: taille.hauteur,
                             definition: definitions[cle] ?? Definition(orientation: .verticale, maxBarres: 12, unite: "photos", etale: false))
        }
        var resultat: [Graphique] = []
        func finir(_ g: inout Graphique) {
            placer(&g)
            resultat.append(g)
        }

        // Photos par mois (par trimestre, par année pour une longue période) : les photos datées
        // seulement.
        let unite = ["mois": "mois", "trimestre": "trimestre", "annee": "année"][par] ?? par
        let noms = nomsDesColonnes(colonnes, debut: entree.debut, fin: fin)
        var g = base("photos_par_mois", "Photos par \(unite)")
        g.barres = colonnes.indices.map { i in
            barreCompte(noms[i].libelle, noms[i].detail, datees.filter { colonnes[i].contient($0.prise!) }.map { $0.id })
        }
        g.sansValeur = periode.count - datees.count
        if g.sansValeur > 0 { g.note = noteSans(g.sansValeur, "sans date de prise de vue") }
        g.vide = !g.barres.contains { $0.n > 0 }
        finir(&g)

        // Focales (arrondies au mm) et ISO, en tranches fixes.
        func parTranches(_ cle: String, _ titre: String, _ tranches: [Tranche], _ valeur: (PhotoSuivie) -> Double?, sans: String) {
            var g = base(cle, titre)
            let avec = periode.compactMap { photo in valeur(photo).map { (photo.id, $0) } }
            g.barres = tranches.indices.map { i in
                barreCompte(tranches[i].libelle, tranches[i].detail, avec.filter { tranche($0.1, tranches) == i }.map { $0.0 })
            }
            g.sansValeur = periode.count - avec.count
            if g.sansValeur > 0 { g.note = noteSans(g.sansValeur, sans) }
            g.vide = !g.barres.contains { $0.n > 0 }
            finir(&g)
        }
        parTranches("focales", "Focales (mm)", tranchesFocales, { $0.focale.map { Double(arrondi($0)) } }, sans: "sans focale lue")
        parTranches("iso", "Sensibilité (ISO)", tranchesISO, { $0.iso }, sans: "sans ISO lu")

        // Heures de la prise de vue, par deux heures.
        g = base("heures", "Heure de la prise de vue")
        let avecHeure = datees.compactMap { photo in photo.prise?.heure.map { (photo.id, $0) } }
        g.barres = (0..<12).map { k in
            barreCompte("\(2 * k) h", "de \(2 * k) h à \(2 * k + 2) h", avecHeure.filter { $0.1 / 2 == k }.map { $0.0 })
        }
        g.sansValeur = periode.count - avecHeure.count
        if g.sansValeur > 0 { g.note = noteSans(g.sansValeur, "sans date de prise de vue") }
        g.vide = !g.barres.contains { $0.n > 0 }
        finir(&g)

        // Objectifs : par nombre de photos décroissant, puis par nom (en minuscules, octet par octet),
        // « Inconnu » après les objectifs nommés à égalité ; plus de huit : les sept premiers et « Autres ».
        g = base("objectifs", "Objectifs")
        var groupes: [String: [Int]] = [:]
        for photo in periode { groupes[photo.objectif ?? "", default: []].append(photo.id) }
        let ordre = groupes.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            if a.key.isEmpty != b.key.isEmpty { return !a.key.isEmpty }
            let la = Array(a.key.lowercased().utf8), lb = Array(b.key.lowercased().utf8)
            if la != lb { return la.lexicographicallyPrecedes(lb) }
            return Array(a.key.utf8).lexicographicallyPrecedes(Array(b.key.utf8))
        }
        let gardes = ordre.count > 8 ? Array(ordre.prefix(7)) : ordre
        g.barres = gardes.map { groupe in
            groupe.key.isEmpty ? barreCompte("Inconnu", "Objectif inconnu", groupe.value) : barreCompte(groupe.key, groupe.key, groupe.value)
        }
        if ordre.count > 8 {
            let autres = ordre.dropFirst(7)
            let m = autres.count
            g.barres.append(barreCompte("Autres", m == 1 ? "1 autre objectif" : "\(milliers(m)) autres objectifs", autres.flatMap { $0.value }))
        }
        g.vide = g.barres.isEmpty
        finir(&g)

        // Notes : celle de la famille (la plus haute de l'original et de ses copies virtuelles), de
        // 0 ★ (pas encore notée : le standard de notation) à 5 ★. Une photo rejetée (le drapeau) compte
        // à sa note, et la note du graphique le dit.
        g = base("notes", "Notes")
        g.barres = (0...5).map { note in
            barreCompte("\(note) ★", note == 0 ? "0 ★, pas encore notée" : "\(note) ★", periode.filter { $0.note == note }.map { $0.id })
        }
        let rejetees = periode.filter(\.rejetee).count
        if rejetees > 0 {
            g.note = rejetees == 1 ? "Dont 1 rejetée (drapeau), comptée à sa note."
                : "Dont \(milliers(rejetees)) rejetées (drapeau), comptées à leur note."
        }
        g.vide = !g.barres.contains { $0.n > 0 }
        finir(&g)

        // Genres (correctif 1.3.8, demandé par Dany le 26 octobre 2026) : le genre de chaque photo, lu par
        // --analyser sur sa vignette (Genre) ; par nombre de photos décroissant, puis l'ordre des genres,
        // « Autre » toujours en dernier ; seuls les genres qui ont des photos, en % des photos classées.
        g = base("genres", "Genres de photos")
        var parGenre: [String: [Int]] = [:]
        for photo in periode {
            if let genre = photo.genre { parGenre[genre, default: []].append(photo.id) }
        }
        let rangsGenres = Dictionary(uniqueKeysWithValues: Genre.codes.enumerated().map { ($1, $0) })
        let presents = Genre.codes.filter { !(parGenre[$0] ?? []).isEmpty }.sorted { a, b in
            if (a == "autre") != (b == "autre") { return b == "autre" }
            let na = parGenre[a]!.count, nb = parGenre[b]!.count
            if na != nb { return na > nb }
            return rangsGenres[a]! < rangsGenres[b]!
        }
        let classees = periode.filter { $0.genre != nil }.count
        g.barres = presents.map { code in
            let ids = parGenre[code]!
            return Barre(libelle: Genre.libelle(code), detail: "\(Genre.libelle(code)) · \(photos(ids.count)) (\(textePourcentage(ids.count, sur: classees)))",
                         valeur: Double(ids.count), texte: milliers(ids.count), n: ids.count, sur: nil, ids: ids.sorted(), couleur: "barre")
        }
        // Sans genre : les photos à classer (en file, ou analysées avant le genre : l'analyse d'office y
        // passe) et celles qui ne le seront jamais (analyse abandonnée), dites à part, comme la tuile.
        g.sansValeur = periode.count - classees
        let nonAnalysees = periode.filter { $0.genre == nil && $0.etat == .enEchec }.count
        let aClasser = g.sansValeur - nonAnalysees
        var manque: [String] = []
        if aClasser > 0 { manque.append("\(photos(aClasser)) pas encore classée\(aClasser > 1 ? "s" : "")") }
        if nonAnalysees > 0 { manque.append("\(milliers(nonAnalysees)) non analysée\(nonAnalysees > 1 ? "s" : "")") }
        g.note = manque.isEmpty
            ? "Lu sur la vignette par Vision (Apple) : une tendance, pas un classement sûr."
            : "Lu sur la vignette par Vision (Apple) : une tendance. \(manque.joined(separator: " · "))."
        g.texteVide = periode.isEmpty ? "Aucune photo" : "Pas encore classées"
        g.vide = g.barres.isEmpty
        finir(&g)

        // Défauts les plus fréquents : les codes cherchés dans la période, par pourcentage exact
        // décroissant, puis n décroissant, puis l'ordre des codes ; le défaut suivi en accent.
        g = base("defauts_frequents", "Défauts les plus fréquents")
        let rangs = Dictionary(uniqueKeysWithValues: codes.enumerated().map { ($1, $0) })
        let cherches = codes.filter { (stats[$0]?.sur ?? 0) > 0 }.sorted { a, b in
            let sa = stats[a]!, sb = stats[b]!
            let pa = part(sa.n, sur: sa.sur), pb = part(sb.n, sur: sb.sur)
            if pa != pb { return pa > pb }
            if sa.n != sb.n { return sa.n > sb.n }
            return rangs[a]! < rangs[b]!
        }
        g.barres = cherches.map { code in
            let s = stats[code]!
            return Barre(libelle: libelle(code),
                         detail: "\(libelle(code)) · \(photos(s.n)) sur \(milliers(s.sur)) (\(textePourcentage(s.n, sur: s.sur)))",
                         valeur: valeurPourcentage(s.n, sur: s.sur), texte: textePourcentage(s.n, sur: s.sur), n: s.n, sur: s.sur,
                         ids: s.ids, couleur: code == suivi ? "accent" : "barre")
        }
        g.note = noteDefauts
        g.vide = g.barres.isEmpty
        finir(&g)

        // L'évolution du défaut suivi, colonne par colonne, parmi les photos datées.
        let rythme = "\(unite) par \(unite)"
        g = base("evolution_defaut", suivi.map { "\(libelle($0)), \(rythme)" } ?? "Évolution d'un défaut")
        g.barres = colonnes.indices.map { i in
            let (libelleColonne, detailColonne) = noms[i]
            let s = suivi.map { code in compte(code, datees.filter { colonnes[i].contient($0.prise!) }) } ?? aucun
            let detail = s.sur > 0 ? "\(detailColonne) · \(photos(s.n)) sur \(milliers(s.sur)) (\(textePourcentage(s.n, sur: s.sur)))"
                : "\(detailColonne) · défaut cherché sur aucune photo"
            return Barre(libelle: libelleColonne, detail: detail, valeur: valeurPourcentage(s.n, sur: s.sur),
                         texte: textePourcentage(s.n, sur: s.sur), n: s.n, sur: s.sur, ids: s.ids, couleur: "accent")
        }
        if let suivi {
            g.sansValeur = periode.filter { $0.prise == nil && $0.resultats[suivi] != nil }.count
            if g.sansValeur > 0 { g.note = noteSans(g.sansValeur, "sans date de prise de vue") }
        } else {
            g.note = "Aucun défaut trouvé dans la période."
            g.texteVide = "Aucun défaut"
        }
        g.vide = !g.barres.contains { ($0.sur ?? 0) > 0 }
        finir(&g)

        var sortie: [String: JSONValue] = [
            "ok": true, "catalogue": .string(entree.catalogue), "periode": periodeJSON,
            "photos": .number(Double(total)), "sans_date": .number(Double(periode.count - datees.count)),
            "analyse": ["analysees": .number(Double(analysees)), "en_attente": .number(Double(enAttente)), "en_echec": .number(Double(enEchec))],
            "tuiles": .array(tuiles), "defauts": .array(defautsJSON),
            "graphiques": .object(Dictionary(uniqueKeysWithValues: resultat.map { ($0.cle, $0.json) })),
            "remarques": .array(remarques.map(JSONValue.string)),
        ]
        if let suivi {
            sortie["defaut_suivi"] = ["code": .string(suivi), "libelle": .string(libelle(suivi)), "choisi": .bool(entree.defaut != nil)]
        }
        return (.object(sortie), resultat)
    }

    // MARK: La commande

    /// `--graphiques '<json>' <dossier>` : lit l'entrée, le relevé et le carnet, calcule, crée le
    /// dossier et y dessine les neuf PNG ; une ligne JSON, ou un refus de tout l'appel (aucun PNG
    /// laissé).
    public static func graphiques(_ texte: String, dossier: String) -> Reponse {
        do {
            let entree = try lireEntree(texte)
            var photos = try lireReleve(entree.suivi, catalogue: entree.catalogue)
            let illisible = fusionnerCarnet(entree.carnet, catalogue: entree.catalogue, dans: &photos)
            let (sortie, aDessiner) = calculer(entree, photos: photos, remarques: illisible ? [carnetIllisible] : [], dossier: dossier)
            let url = URL(fileURLWithPath: dossier, isDirectory: true)
            var estDossier: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier) {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &estDossier), estDossier.boolValue,
                  FileManager.default.isWritableFile(atPath: url.path) else {
                throw Refus(raison: "dossier", texte: "Le dossier \(dossier) ne se crée pas ou ne s'écrit pas : rien n'est dessiné.")
            }
            var ecrits: [URL] = []
            for g in aDessiner {
                let fichier = URL(fileURLWithPath: g.fichier)
                guard dessiner(g, couleurs: entree.couleurs, vers: fichier) else {
                    for ecrit in ecrits { try? FileManager.default.removeItem(at: ecrit) }
                    throw Refus(raison: "dessin", texte: "Le graphique « \(g.titre) » ne se dessine pas : rien n'est dessiné.")
                }
                ecrits.append(fichier)
            }
            return Reponse(ligne: sortie, code: 0)
        } catch let refus as Refus {
            return refus.reponse
        } catch {
            return Refus(raison: "arguments", texte: "Arguments de --graphiques : \(error.localizedDescription)").reponse
        }
    }
}
