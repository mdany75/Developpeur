import CoreGraphics
import Foundation
import Vision

/// Une photo d'une séance à trier, mesurée sur sa vignette : netteté (sur toute l'image et au
/// point de mise au point de l'appareil), exposition, visages, note esthétique, empreinte (photos
/// semblables), mots-clés proposés.
public struct PhotoTriee {
    /// Au point de mise au point, vu dans la vignette.
    public struct MiseAuPoint {
        public var point: CGPoint
        public var nettete: Double?
        public var avertissement: Bool
    }

    public var id: Int
    public var fichier: String
    /// Date de prise de vue (rafales : photos consécutives prises à quelques secondes d'intervalle).
    public var date: Date?
    /// Note et drapeau déjà posés dans Lightroom (pas de proposition par-dessus).
    public var note: Int?
    public var drapeau: String?
    /// Pile de Lightroom (empilage à la main, ou automatique par heure de prise de vue) :
    /// l'identifiant de la photo du dessus. Une seule photo proposée par pile.
    public var pile: Int?
    public var detail: DetailMeasurements?
    public var mesures: PhotoMeasurements?
    public var vision: VisionReport?
    public var empreinte: VNFeaturePrintObservation?
    public var af: MiseAuPoint?
    public var motsCles: [MotsClesVision.Proposition] = []
    /// La vignette n'a pas pu être lue : rien n'est mesuré.
    public var erreur: String?

    public init(id: Int, fichier: String) {
        self.id = id
        self.fichier = fichier
    }

    /// Netteté qui compte : au point de mise au point s'il est dans l'image, sinon la zone la plus nette.
    var nettete: Double? { af?.nettete ?? detail?.sharpest }

    static func r(_ value: Double) -> String { DevelopCatalogue.format((value * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",") }
    static func r2(_ value: Double) -> String { DevelopCatalogue.format((value * 100).rounded() / 100).replacingOccurrences(of: ".", with: ",") }

    /// Yeux fermés ou plissés sur un sujet : un visage d'au moins la moitié de la largeur du plus
    /// grand, assez grand pour lire ses yeux (`VisionAnalysis.closedEyesThreshold`). Nil sinon.
    var yeuxFermes: String? {
        let visages = vision?.faces ?? []
        guard let grand = visages.map({ Double($0.box.width) }).max(), grand > 0 else { return nil }
        let sujets = visages.filter { Double($0.box.width) >= 0.5 * grand && $0.eyesClosed != nil }
        let fermes = sujets.filter { $0.eyesClosed == true }
        guard !fermes.isEmpty else { return nil }
        if sujets.count == 1, let ouverture = fermes[0].eyeOpenness {
            return "yeux fermés ou plissés (ouverture \(Self.r2(ouverture)))"
        }
        return "yeux fermés ou plissés : \(fermes.count) visage\(fermes.count > 1 ? "s" : "") sur \(sujets.count)"
    }

    /// Ce qui la fait écarter : floue, mise au point manquée, yeux fermés, presque noire, brûlée.
    /// Seuils de netteté de `Detail` (relevés à 1024 px : moins de 15 floue, plus de 35 nette).
    public var defauts: [String] {
        if let erreur { return ["vignette illisible : \(erreur)"] }
        var liste: [String] = []
        if let detail, detail.sharpest < 15 {
            liste.append("floue : aucune zone nette (netteté \(Self.r(detail.sharpest)))")
        } else if let af, let auPoint = af.nettete, let detail, auPoint < 15, detail.sharpest >= 35 {
            liste.append("mise au point manquée : floue au point AF (\(Self.r(auPoint))), nette ailleurs (\(Self.r(detail.sharpest)))")
        }
        if let af, af.avertissement, (nettete ?? 0) < 35, !liste.contains(where: { $0.hasPrefix("floue") || $0.hasPrefix("mise au point") }) {
            liste.append("mise au point signalée manquée par l'appareil")
        }
        if let yeux = yeuxFermes { liste.append(yeux) }
        if let mesures {
            if mesures.medianL < 6 { liste.append("presque noire (L* médian \(Self.r(mesures.medianL)))") }
            if mesures.pureWhite > 35 { liste.append("brûlée (\(Self.r(mesures.pureWhite)) % de blanc pur)") }
        }
        return liste
    }

    /// Une photo floue ou ratée passe derrière ; puis la note esthétique et la qualité du meilleur visage.
    public var score: Double {
        let net = min((nettete ?? 0) / 60, 1)
        let visage = vision?.faces.compactMap(\.quality).max() ?? 0
        return net + (vision?.aesthetics ?? 0) + 0.5 * visage - Double(defauts.count)
    }

    public var pourquoi: String {
        var parties: [String] = []
        if let auPoint = af?.nettete { parties.append("netteté au point AF \(Self.r(auPoint))") }
        else if let detail { parties.append("netteté \(Self.r(detail.sharpest))") }
        if let visage = vision?.faces.compactMap(\.quality).max() { parties.append("visage \(DevelopCatalogue.format((visage * 100).rounded() / 100))") }
        if let note = vision?.aesthetics { parties.append("note esthétique \(DevelopCatalogue.format((note * 100).rounded() / 100))") }
        if vision?.utility == true { parties.append("utilitaire selon Vision (capture, document)") }
        return parties.isEmpty ? "aucune mesure" : parties.joined(separator: ", ")
    }

    /// Une ligne par photo, pour `details`.
    var json: JSONValue {
        var item: [String: JSONValue] = ["id": .number(Double(id)), "fichier": .string(fichier),
                                         "score": .number((score * 100).rounded() / 100), "mesures": .string(pourquoi)]
        if let detail { item["nettete_max"] = .number((detail.sharpest * 10).rounded() / 10) }
        if let bruit = detail?.noise { item["bruit"] = .number((bruit * 100).rounded() / 100) }
        let liste = defauts
        if !liste.isEmpty { item["defauts"] = .array(liste.map(JSONValue.string)) }
        if let pile { item["pile"] = .number(Double(pile)) }
        if let af {
            item["point_af"] = ["x": .number((af.point.x * 1000).rounded() / 1000), "y": .number((af.point.y * 1000).rounded() / 1000)]
        }
        if !motsCles.isEmpty { item["mots_cles"] = .array(motsCles.map { .string($0.mot) }) }
        let yeux = (vision?.faces ?? []).compactMap { face in face.eyeOpenness.map { (face.box.width, $0) } }
        if !yeux.isEmpty {
            item["yeux"] = .array(yeux.map { ["visage": .number((Double($0.0) * 1000).rounded() / 1000), "ouverture": .number(($0.1 * 1000).rounded() / 1000)] })
        }
        return .object(item)
    }
}

/// Bilan d'une séance : photos floues ou ratées, rafales avec la meilleure de chacune,
/// classement, et propositions de drapeaux et de notes que Claude présente avant de les poser
/// (set_metadata).
public enum Tri {
    /// Part des photos sans défaut proposées retenues (les meilleures de chaque groupe d'abord).
    static let partRetenue = 0.4
    /// Part des photos sans défaut proposées à 4 étoiles (au moins une).
    static let partQuatreEtoiles = 0.1
    static let tailleClassement = 15
    /// Deux photos consécutives sont de la même rafale si Vision y voit la même scène et si elles
    /// sont prises à moins de `ecartRafale` secondes l'une de l'autre. Relevé le 17 octobre 2026
    /// sur une vraie séance de 329 photos : sans l'écart de temps, les photos semblables de
    /// proche en proche formaient un groupe de 193 photos (même salle, même éclairage).
    static let ecartRafale: TimeInterval = 4
    /// Sans date, une ressemblance plus stricte (même photo, ou presque).
    static let distanceSansDate = 0.35

    /// Groupes dont une seule photo est proposée : les rafales, et les piles de Lightroom (une pile
    /// et une rafale qui se touchent n'en font qu'un). `pile` : la photo du dessus, si le groupe
    /// porte une pile.
    static func groupes(_ photos: [PhotoTriee]) -> [(membres: [Int], pile: Int?)] {
        var parent = Array(photos.indices)
        func racine(_ i: Int) -> Int { var i = i; while parent[i] != i { i = parent[i] }; return i }
        func unir(_ a: Int, _ b: Int) { let ra = racine(a), rb = racine(b); if ra != rb { parent[rb] = ra } }
        for groupe in rafales(photos) { for i in groupe.dropFirst() { unir(groupe[0], i) } }
        var parPile: [Int: Int] = [:]
        for i in photos.indices {
            guard let pile = photos[i].pile else { continue }
            if let premier = parPile[pile] { unir(premier, i) } else { parPile[pile] = i }
        }
        var membres: [Int: [Int]] = [:]
        for i in photos.indices { membres[racine(i), default: []].append(i) }
        let ordre = rangDate(photos)
        return membres.values.filter { $0.count > 1 }
            .map { groupe in
                let tries = groupe.sorted { ordre[$0]! < ordre[$1]! }
                return (tries, tries.compactMap { photos[$0].pile }.first)
            }
            .sorted { ordre[$0.membres[0]]! < ordre[$1.membres[0]]! }
    }

    /// Rang de chaque photo dans l'ordre de prise de vue (l'ordre donné sans date).
    static func rangDate(_ photos: [PhotoTriee]) -> [Int: Int] {
        let ordre = photos.indices.sorted { a, b in
            switch (photos[a].date, photos[b].date) {
            case let (da?, db?): return da != db ? da < db : a < b
            default: return a < b
            }
        }
        var rang: [Int: Int] = [:]
        for (r, i) in ordre.enumerated() { rang[i] = r }
        return rang
    }

    /// Rafales : suites de photos consécutives (dans l'ordre de prise de vue) semblables et prises
    /// coup sur coup. Les photos seules ne forment pas de groupe.
    static func rafales(_ photos: [PhotoTriee]) -> [[Int]] {
        let ordre = photos.indices.sorted { a, b in
            switch (photos[a].date, photos[b].date) {
            case let (da?, db?): return da < db
            default: return a < b
            }
        }
        var groupes: [[Int]] = []
        var courant: [Int] = []
        for i in ordre {
            if let precedent = courant.last, memeRafale(photos[precedent], photos[i]) {
                courant.append(i)
            } else {
                if courant.count > 1 { groupes.append(courant) }
                courant = [i]
            }
        }
        if courant.count > 1 { groupes.append(courant) }
        return groupes
    }

    static func memeRafale(_ a: PhotoTriee, _ b: PhotoTriee) -> Bool {
        guard let ea = a.empreinte, let eb = b.empreinte, let distance = VisionAnalysis.distance(ea, eb) else { return false }
        if let da = a.date, let db = b.date {
            return abs(db.timeIntervalSince(da)) <= ecartRafale && distance < VisionAnalysis.sameSceneDistance
        }
        return distance < distanceSansDate
    }

    /// Date de prise de vue telle que le module la donne (« 2025-06-14 15:02:11.287 »).
    static func date(_ texte: String?) -> Date? {
        guard let texte else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            let lecteur = DateFormatter()
            lecteur.locale = Locale(identifier: "en_US_POSIX")
            lecteur.dateFormat = format
            if let date = lecteur.date(from: texte) { return date }
        }
        return nil
    }

    public static func bilan(_ photos: [PhotoTriee], details: Bool = false) -> JSONValue {
        let tous = Self.groupes(photos)
        let groupes = tous.map(\.membres)
        var dansUnGroupe: [Int: Int] = [:]   // indice → groupe
        for (g, membres) in groupes.enumerated() { for i in membres { dansUnGroupe[i] = g } }
        let sansDefaut = photos.indices.filter { photos[$0].defauts.isEmpty }

        // La meilleure de chaque rafale : sans défaut si possible, au meilleur score.
        var meilleures: [Int: Int] = [:]   // groupe → indice
        for (g, membres) in groupes.enumerated() {
            let candidates = membres.filter { photos[$0].defauts.isEmpty }
            let pool = candidates.isEmpty ? membres : candidates
            meilleures[g] = pool.max { photos[$0].score < photos[$1].score }
        }

        // Retenues : les meilleures des groupes (sans défaut), puis les photos seules, par score,
        // jusqu'à la part voulue des photos sans défaut.
        let objectif = max(1, Int((Double(sansDefaut.count) * partRetenue).rounded()))
        var retenues = Set(meilleures.values.filter { photos[$0].defauts.isEmpty })
        let seules = sansDefaut.filter { dansUnGroupe[$0] == nil }.sorted { photos[$0].score > photos[$1].score }
        for i in seules where retenues.count < objectif { retenues.insert(i) }
        let quatre = Set(sansDefaut.sorted { photos[$0].score > photos[$1].score }
            .prefix(max(1, Int((Double(sansDefaut.count) * partQuatreEtoiles).rounded()))))
            .intersection(retenues)

        func ids(_ indices: [Int]) -> JSONValue { .array(indices.sorted().map { .number(Double(photos[$0].id)) }) }
        func libres(_ indices: [Int], drapeau: Bool) -> [Int] {
            indices.filter { i in drapeau ? (photos[i].drapeau ?? "aucun") == "aucun" : (photos[i].note ?? 0) == 0 }
        }

        let ratees = photos.indices.filter { !photos[$0].defauts.isEmpty }
        var resultat: [String: JSONValue] = [
            "photos_analysees": .number(Double(photos.count)),
            "floues_ou_ratees": .array(ratees.map { i in
                ["id": .number(Double(photos[i].id)), "fichier": .string(photos[i].fichier),
                 "pourquoi": .string(photos[i].defauts.joined(separator: " ; "))]
            }),
            "rafales": .array(groupes.enumerated().filter { tous[$0.offset].pile == nil }.map { g, membres in
                let best = meilleures[g] ?? membres[0]
                return ["photos": ids(membres), "meilleure": .number(Double(photos[best].id)),
                        "pourquoi": .string(photos[best].pourquoi)]
            }),
            "classement": .array(sansDefaut.sorted { photos[$0].score > photos[$1].score }.prefix(tailleClassement).map { i in
                ["id": .number(Double(photos[i].id)), "fichier": .string(photos[i].fichier),
                 "score": .number((photos[i].score * 100).rounded() / 100), "pourquoi": .string(photos[i].pourquoi)]
            }),
        ]

        let piles = groupes.enumerated().filter { tous[$0.offset].pile != nil }
        if !piles.isEmpty {
            resultat["piles"] = .array(piles.map { g, membres in
                let best = meilleures[g] ?? membres[0]
                return ["photos": ids(membres), "dessus": .number(Double(tous[g].pile ?? photos[membres[0]].id)),
                        "meilleure": .number(Double(photos[best].id)), "pourquoi": .string(photos[best].pourquoi)]
            })
        }
        let yeux = photos.indices.filter { photos[$0].yeuxFermes != nil }
        if !yeux.isEmpty { resultat["yeux_fermes"] = ids(yeux) }

        var propositions: [JSONValue] = []
        let aRejeter = libres(ratees, drapeau: true)
        if !aRejeter.isEmpty {
            propositions.append(["flag": "reject", "photo_ids": ids(aRejeter), "pourquoi": "floues, ratées ou aux yeux fermés (floues_ou_ratees)"])
        }
        let aRetenir = libres(Array(retenues), drapeau: true)
        if !aRetenir.isEmpty {
            propositions.append(["flag": "pick", "photo_ids": ids(aRetenir),
                                 "pourquoi": "la meilleure de chaque rafale ou pile, puis les meilleures photos seules"])
        }
        let aNoter = libres(Array(quatre), drapeau: false)
        if !aNoter.isEmpty {
            propositions.append(["rating": 4, "photo_ids": ids(aNoter), "pourquoi": "les meilleures de la séance (classement)"])
        }
        let doublons = groupes.enumerated().flatMap { g, membres in
            membres.filter { $0 != meilleures[g] && photos[$0].defauts.isEmpty && !retenues.contains($0) }
        }
        if !doublons.isEmpty {
            resultat["rafales_moins_bonnes"] = ids(doublons)
        }
        resultat["propositions"] = .array(propositions)
        let dejaClassees = photos.filter { ($0.drapeau ?? "aucun") != "aucun" || ($0.note ?? 0) > 0 }.count
        if dejaClassees > 0 {
            resultat["deja_classees"] = .string("\(dejaClassees) photo(s) portent déjà un drapeau ou une note : les propositions ne les touchent pas.")
        }

        let motsCles = photos.flatMap { $0.motsCles.map(\.mot) }
        if !motsCles.isEmpty {
            var compte: [String: Int] = [:]
            for mot in motsCles { compte[mot, default: 0] += 1 }
            resultat["mots_cles_frequents"] = .array(compte.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(15).map { ["mot": .string($0.key), "photos": .number(Double($0.value))] })
            if !details {
                var parPhoto: [String: JSONValue] = [:]
                for photo in photos where !photo.motsCles.isEmpty {
                    parPhoto[String(photo.id)] = .array(photo.motsCles.map { .string($0.mot) })
                }
                resultat["mots_cles_par_photo"] = .object(parPhoto)
            }
        }
        if details { resultat["photos"] = .array(photos.map(\.json)) }
        return .object(resultat)
    }
}
