import Foundation

/// Harmoniser par lumière (1.4, « Une sortie entière ») : une sortie (un voyage, une fête de
/// famille) se partage en groupes de photos prises sous la même lumière, que `match_series`
/// harmonise chacun sur sa propre référence. Le musée, la plage et le souper n'ont pas la même
/// lumière : une seule référence les rendrait tous faux.
///
/// Les photos se suivent dans l'ordre de prise de vue ; une nouvelle commence un groupe (`Coupure`)
/// quand le flash change (d'avec la dernière photo du groupe qui le dit), quand la lumière de la scène (`Prise.lumiere`, d'après l'ouverture, la
/// vitesse, l'ISO et la compensation) s'écarte de `ecartIL` ou plus de celle des dernières photos du
/// groupe, ou après une pause de plus de `pauseMax`, sauf si elle ressemble à l'une des dernières
/// (Vision, `distanceMemeLieu`) et que la pause reste sous `pauseMemeLieu` (le même lieu, après le
/// repas). Deux boîtiers sur la même scène restent dans le même groupe : la même lumière.
/// Fonctions pures ; seuils provisoires, choisis hors de Lightroom, à relever sur la sortie de
/// l'essai de la 1.4.
public enum GroupesLumiere {
    /// Ce que la prise de vue dit d'une photo.
    public struct Prise: Equatable {
        public var id: Int
        public var fichier: String
        public var date: Date?
        /// Nombre f.
        public var ouverture: Double?
        /// Secondes.
        public var vitesse: Double?
        public var iso: Double?
        /// Compensation d'exposition, en IL (nil : inconnue, comptée 0).
        public var compensation: Double?
        /// Le flash a-t-il éclairé ? Nil : inconnu.
        public var flash: Bool?

        public init(id: Int, fichier: String, date: Date? = nil, ouverture: Double? = nil, vitesse: Double? = nil,
                    iso: Double? = nil, compensation: Double? = nil, flash: Bool? = nil) {
            self.id = id
            self.fichier = fichier
            self.date = date
            self.ouverture = ouverture
            self.vitesse = vitesse
            self.iso = iso
            self.compensation = compensation
            self.flash = flash
        }

        /// Lumière de la scène, en IL à 100 ISO : log2(N² / t) − log2(ISO / 100), plus la
        /// compensation (une photo éclaircie d'une IL a reçu une IL de plus d'une scène qui n'a pas
        /// changé). Plein soleil vers 15, ombre ou ciel couvert 11 à 13, intérieur 5 à 8. Nil sans
        /// l'ouverture, la vitesse et l'ISO.
        public var lumiere: Double? {
            guard let ouverture, let vitesse, let iso, ouverture > 0, vitesse > 0, iso > 0,
                  ouverture.isFinite, vitesse.isFinite, iso.isFinite else { return nil }
            return log2(ouverture * ouverture / vitesse) - log2(iso / 100) + (compensation.flatMap { $0.isFinite ? $0 : nil } ?? 0)
        }
    }

    /// Une pause plus longue : une autre lumière, sauf le même lieu (provisoire).
    public static let pauseMax: TimeInterval = 10 * 60
    /// Une pause plus longue : une autre lumière, même au même lieu (provisoire).
    public static let pauseMemeLieu: TimeInterval = 60 * 60
    /// Distance des empreintes de Vision sous laquelle deux photos montrent le même lieu : entre la
    /// même scène d'une rafale (`VisionAnalysis.sameSceneDistance`, 0,5) et deux photos différentes
    /// (0,8 à 1). Provisoire.
    public static let distanceMemeLieu = 0.7
    /// Écart de la lumière de la scène, en IL, qui fait une autre lumière (le soleil et l'ombre
    /// d'un arbre en sont à 2 ou 3 ; une scène à contre-jour bien exposée à moins). Provisoire.
    public static let ecartIL = 2.5
    /// Photos du groupe dont la médiane de la lumière fait le repère (une lumière qui baisse peu à
    /// peu, un coucher de soleil, reste un groupe).
    public static let fenetreLumiere = 5
    /// Dernières photos du groupe auxquelles une photo d'après une pause peut ressembler.
    public static let fenetreLieu = 3

    /// Pourquoi un groupe commence.
    public enum Coupure: Equatable {
        /// La première photo de la série.
        case debut
        /// Le flash a changé : `allume` dit s'il éclaire la nouvelle photo.
        case flash(allume: Bool)
        /// La lumière de la scène a changé de tant d'IL (signée : plus claire si positive).
        case lumiere(ecart: Double)
        /// Une pause de tant de secondes.
        case pause(TimeInterval)
        /// La série passe aux photos sans date de prise de vue.
        case sansDate

        /// En mots, pour le plan.
        public var texte: String {
            switch self {
            case .debut: return "première photo de la série"
            case .flash(let allume): return allume ? "le flash éclaire à partir d'ici" : "plus de flash à partir d'ici"
            case .lumiere(let ecart):
                return "lumière de la scène \(ecart > 0 ? "plus forte" : "plus faible") de \(PhotoTriee.r(abs(ecart))) IL"
            case .pause(let secondes): return "pause de \(GroupesLumiere.duree(secondes))"
            case .sansDate: return "photos sans date de prise de vue"
            }
        }
    }

    /// Un groupe : les indices de ses photos dans la liste donnée, dans l'ordre de prise de vue.
    public struct Groupe: Equatable {
        public var membres: [Int]
        public var coupure: Coupure
    }

    /// Les groupes de lumière de `prises`. `distance(i, j)` : la distance des empreintes de Vision de
    /// deux photos (indices), nil si l'une manque. Les photos sans date viennent après, dans
    /// l'ordre donné, sans critère de temps.
    public static func former(_ prises: [Prise], distance: (Int, Int) -> Double?) -> [Groupe] {
        let datees = prises.indices.filter { prises[$0].date != nil }
            .sorted { prises[$0].date! != prises[$1].date! ? prises[$0].date! < prises[$1].date! : $0 < $1 }
        let ordre = datees + prises.indices.filter { prises[$0].date == nil }
        var groupes: [Groupe] = []
        for i in ordre {
            guard let courant = groupes.last else {
                groupes.append(Groupe(membres: [i], coupure: .debut))
                continue
            }
            if let coupure = coupure(prises, groupe: courant.membres, photo: i, distance: distance) {
                groupes.append(Groupe(membres: [i], coupure: coupure))
            } else {
                groupes[groupes.count - 1].membres.append(i)
            }
        }
        return groupes
    }

    /// Ce qui sépare la photo `photo` du groupe en cours (nil : elle en fait partie). Dans l'ordre :
    /// le flash, la lumière de la scène, le temps.
    static func coupure(_ prises: [Prise], groupe: [Int], photo i: Int, distance: (Int, Int) -> Double?) -> Coupure? {
        guard let precedente = groupe.last else { return .debut }
        let a = prises[precedente], b = prises[i]
        // Le flash de la dernière photo du groupe qui le dit (un boîtier qui ne le dit pas, mêlé à
        // un autre, ne cache pas le changement).
        if let fb = b.flash, let fa = groupe.reversed().lazy.compactMap({ prises[$0].flash }).first, fa != fb {
            return .flash(allume: fb)
        }
        // Au flash, l'éclair fait la lumière : la scène ne se compare pas.
        if b.flash != true, let lumiere = b.lumiere {
            let recentes = groupe.suffix(fenetreLumiere).compactMap { prises[$0].flash == true ? nil : prises[$0].lumiere }
            if !recentes.isEmpty {
                let ecart = lumiere - Eclairage.mediane(recentes)
                if abs(ecart) >= ecartIL { return .lumiere(ecart: ecart) }
            }
        }
        switch (a.date, b.date) {
        case let (da?, db?):
            let pause = db.timeIntervalSince(da)
            guard pause > pauseMax else { return nil }
            let memeLieu = pause <= pauseMemeLieu
                && groupe.suffix(fenetreLieu).contains { j in distance(j, i).map { $0 < distanceMemeLieu } ?? false }
            return memeLieu ? nil : .pause(pause)
        case (nil, nil):
            return nil
        default:
            return .sansDate
        }
    }

    /// Une durée en minutes ou en heures, à la française.
    static func duree(_ secondes: TimeInterval) -> String {
        let minutes = Int((secondes / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let heures = minutes / 60, reste = minutes % 60
        return reste == 0 ? "\(heures) h" : "\(heures) h \(String(format: "%02d", reste))"
    }

    /// La lumière de la scène en mots, d'après sa médiane en IL à 100 ISO (repères de la règle du
    /// soleil ; une indication, pas une mesure).
    public static func nomLumiere(_ il: Double) -> String {
        switch il {
        case 14...: return "plein jour"
        case 11..<14: return "ombre ou ciel couvert"
        case 8..<11: return "intérieur clair, ou fin du jour"
        case 5..<8: return "intérieur"
        default: return "intérieur sombre, ou nuit"
        }
    }

    /// La référence proposée d'un groupe (un indice de `photos`) et pourquoi : une photo déjà
    /// retouchée par Claude d'abord (elle donne déjà le rendu voulu), sinon, quand le groupe a des
    /// visages, une photo avec un visage assez grand pour le témoin du teint ; parmi elles, la
    /// première au classement du tri (`PhotoTriee.score`), sans défaut mesuré si possible.
    static func reference(_ membres: [Int], photos: [PhotoTriee], retouchees: Set<Int>) -> (index: Int, pourquoi: String)? {
        guard !membres.isEmpty else { return nil }
        let sansDefaut = membres.filter { photos[$0].defauts.isEmpty }
        let pool = sansDefaut.isEmpty ? membres : sansDefaut
        func meilleure(_ liste: [Int]) -> Int? { liste.max { photos[$0].score < photos[$1].score } }
        let defaut = sansDefaut.isEmpty ? " (toutes ont un défaut mesuré : à confirmer à l'œil)" : ""
        if let deja = meilleure(pool.filter { retouchees.contains(photos[$0].id) }) {
            return (deja, "déjà retouchée par Claude : elle donne le rendu du groupe" + defaut)
        }
        let avecVisage = pool.filter { (photos[$0].vision?.faces ?? []).contains { Double($0.box.width) >= Teint.visageMin && Composition.visagePlausible($0) } }
        if let visage = meilleure(avecVisage) {
            return (visage, "la mieux classée au tri parmi celles qui ont un visage (témoin du teint), à retoucher d'abord" + defaut)
        }
        guard let choisie = meilleure(pool) else { return nil }
        return (choisie, "la mieux classée au tri (netteté, note esthétique de Vision), à retoucher d'abord" + defaut)
    }
}
