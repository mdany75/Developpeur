import CoreGraphics
import Foundation
import Vision

/// Une photo d'une séance à trier, mesurée sur sa vignette : netteté (sur toute l'image et au
/// point de mise au point de l'appareil), exposition, visages, note esthétique, empreinte (photos
/// semblables), mots-clés proposés.
public struct PhotoTriee {
    /// Un défaut mesuré, par genre : le plafond de note en dépend (`Notation.plafond`).
    public enum Defaut: Equatable {
        case floue, miseAuPointManquee, miseAuPointSignalee, yeuxFermes, presqueNoire, brulee
    }

    /// Au point de mise au point, vu dans la vignette.
    public struct MiseAuPoint {
        public var point: CGPoint
        public var nettete: Double?
        public var avertissement: Bool
        /// Texture autour du point (`Detail.autour`) ; nil si elle n'est pas mesurée.
        public var texture: Double? = nil

        /// La mise au point se juge-t-elle ici ? Pas sur une zone sans texture (ciel, nuage, sable
        /// lisse, mur : sous `DetailMeasurements.textureMin`), où la netteté au point n'en dit rien.
        /// Une texture non mesurée laisse juger, comme avant la 1.3.
        public var jugeable: Bool { texture.map { $0 >= DetailMeasurements.textureMin } ?? true }

        /// La mise au point se juge mais reste un doute : texture faible autour du point
        /// (`DetailMeasurements.textureDouteuse`), comme le bord d'un nuage ou un petit visage.
        public var douteuse: Bool { jugeable && (texture.map { $0 < DetailMeasurements.textureDouteuse } ?? false) }

        /// La netteté au point quand elle se juge ; nil sur une zone sans texture.
        public var netteteJugee: Double? { jugeable ? nettete : nil }

        /// Mesure le point dans l'image (netteté et texture, `Detail.autour`) ; `facteur` ramène la
        /// netteté d'une vignette du cache à celle d'un aperçu exporté (la texture, à une échelle plus
        /// grossière, n'en a pas besoin).
        public static func mesuree(_ image: CGImage, point: CGPoint, avertissement: Bool, facteur: Double = 1) -> MiseAuPoint {
            let mesure = Detail.autour(image, point: point)
            return MiseAuPoint(point: point, nettete: mesure.map { $0.nettete * facteur }, avertissement: avertissement,
                               texture: mesure?.texture)
        }
    }

    public var id: Int
    public var fichier: String
    /// Date de prise de vue (rafales : photos consécutives prises à quelques secondes d'intervalle).
    public var date: Date?
    /// Note et drapeau déjà posés dans Lightroom (pas de proposition par-dessus).
    public var note: Int?
    public var drapeau: String?
    /// Format du fichier (RAW, DNG, JPG…) : une exposition ratée se rattrape mieux sur un RAW.
    public var format: String?
    /// Pile de Lightroom (empilage à la main, ou automatique par heure de prise de vue) :
    /// l'identifiant de la photo du dessus. La meilleure de la pile est nommée ; les autres ne
    /// montent pas à 3 (`Notation.plafond` : 2 depuis l'échelle resserrée de la 1.4).
    public var pile: Int?
    /// Numéro de série du boîtier (1.3.5, `serie_boitier` de la description) : deux boîtiers sur la
    /// même scène ne forment pas une rafale.
    public var boitier: String?
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

    /// Netteté qui compte : au point de mise au point s'il est dans l'image et sur une zone qui a de
    /// la texture, sinon la zone la plus nette.
    var nettete: Double? { af?.netteteJugee ?? detail?.sharpest }

    static func r(_ value: Double) -> String { DevelopCatalogue.format((value * 10).rounded() / 10).replacingOccurrences(of: ".", with: ",") }
    static func r2(_ value: Double) -> String { DevelopCatalogue.format((value * 100).rounded() / 100).replacingOccurrences(of: ".", with: ",") }

    /// Part de l'image en blanc pur (`PhotoMeasurements.pureWhite`) au-delà de laquelle elle est
    /// brûlée (`defautsMesures`) ; le Suivi en tire sa surexposition (correctif 1.3.7).
    static let partBlancPurBrulee = 35.0

    /// Les sujets dont les yeux se lisent : les visages d'au moins la moitié de la largeur du plus
    /// grand, assez grands pour lire leurs yeux. Vide sans visage, ou sans yeux lisibles ; le Suivi
    /// (correctif 1.3.7) ne cherche les yeux fermés que s'il y en a.
    var sujetsAuxYeuxLus: [VisionReport.Face] {
        let visages = vision?.faces ?? []
        guard let grand = visages.map({ Double($0.box.width) }).max(), grand > 0 else { return [] }
        return visages.filter { Double($0.box.width) >= 0.5 * grand && $0.eyesClosed != nil }
    }

    /// Yeux fermés ou plissés sur un sujet : un visage d'au moins la moitié de la largeur du plus
    /// grand, assez grand pour lire ses yeux (`VisionAnalysis.closedEyesThreshold`). Nil sinon.
    var yeuxFermes: String? {
        let sujets = sujetsAuxYeuxLus
        let fermes = sujets.filter { $0.eyesClosed == true }
        guard !fermes.isEmpty else { return nil }
        if sujets.count == 1, let ouverture = fermes[0].eyeOpenness {
            return "yeux fermés ou plissés (ouverture \(Self.r2(ouverture)))"
        }
        return "yeux fermés ou plissés : \(fermes.count) visage\(fermes.count > 1 ? "s" : "") sur \(sujets.count)"
    }

    /// Yeux ouverts sur tous les sujets dont les yeux se lisent (les mêmes sujets que `yeuxFermes`) :
    /// la vue d'une rafale ou d'une pile qui fait proposer au rejet celles aux yeux fermés (1.3.4).
    var yeuxOuverts: Bool {
        let lus = sujetsAuxYeuxLus.compactMap(\.eyesClosed)
        return !lus.isEmpty && !lus.contains(true)
    }

    /// Les défauts de netteté mesurés : floue, mise au point manquée, ou signalée manquée par
    /// l'appareil (sans autre défaut de netteté, et pas nette au point). Seuils de `Detail`, relevés
    /// à 1024 px : moins de 15 floue, plus de 35 nette (`DetailMeasurements.seuilFlou` et
    /// `seuilNet`). La mise au point manquée ne se juge que sur une zone qui a de la texture
    /// (`MiseAuPoint.jugeable`, `DetailMeasurements.textureMin`) : sur du sable lisse ou un ciel uni,
    /// elle est « non jugée » et ne plafonne pas la note (faux constat du sable relevé le 21 octobre
    /// 2026 ; celui du nuage, qui a plus de texture, n'est plus qu'un doute : `textureDouteuse`,
    /// 1 à vérifier dans `Notation.plafond`, 2 avant l'échelle resserrée de la 1.4). Seule copie de ces
    /// règles : le tri (`defautsMesures`) et le carnet de progrès
    /// (`Carnet.constatsVue`) les reprennent.
    static func defautsNettete(detail: DetailMeasurements?, af: MiseAuPoint?) -> [(genre: Defaut, texte: String)] {
        var liste: [(genre: Defaut, texte: String)] = []
        if let detail, detail.sharpest < DetailMeasurements.seuilFlou {
            liste.append((.floue, "floue : aucune zone nette (netteté \(r(detail.sharpest)))"))
        } else if let af, let auPoint = af.netteteJugee, let detail, auPoint < DetailMeasurements.seuilFlou, detail.sharpest >= DetailMeasurements.seuilNet {
            liste.append((.miseAuPointManquee, "mise au point manquée : floue au point AF (\(r(auPoint))), nette ailleurs (\(r(detail.sharpest)))"))
        }
        // La netteté qui compte : au point de mise au point s'il est mesuré sur une zone qui a de la
        // texture, sinon la zone la plus nette (l'avertissement de l'appareil s'y confirme alors).
        if let af, af.avertissement, (af.netteteJugee ?? detail?.sharpest ?? 0) < DetailMeasurements.seuilNet, liste.isEmpty {
            liste.append((.miseAuPointSignalee, "mise au point signalée manquée par l'appareil"))
        }
        return liste
    }

    /// Les défauts mesurés, par genre : ceux de la netteté (`defautsNettete`), yeux fermés, presque
    /// noire, brûlée.
    public var defautsMesures: [(genre: Defaut, texte: String)] {
        var liste = Self.defautsNettete(detail: detail, af: af)
        if let yeux = yeuxFermes { liste.append((.yeuxFermes, yeux)) }
        if let mesures {
            if mesures.medianL < 6 { liste.append((.presqueNoire, "presque noire (L* médian \(Self.r(mesures.medianL)))")) }
            if mesures.pureWhite > Self.partBlancPurBrulee { liste.append((.brulee, "brûlée (\(Self.r(mesures.pureWhite)) % de blanc pur)")) }
        }
        return liste
    }

    /// Ce qui la fait écarter, en clair (vignette illisible comprise).
    public var defauts: [String] {
        if let erreur { return ["vignette illisible : \(erreur)"] }
        return defautsMesures.map(\.texte)
    }

    /// Ordre de lecture d'une séance (classement, photos seules), pas une note : une photo floue ou
    /// ratée passe derrière, puis la netteté et la note esthétique de Vision (à demi-poids : elle
    /// va de −1 à 1, et ne compare que des photos d'une même sortie). La qualité des visages n'y
    /// entre pas : elle ne compare que des prises d'un même visage (`scoreDansGroupe`).
    public var score: Double {
        let net = min((nettete ?? 0) / 60, 1)
        return net + Tri.poidsEsthetique * (vision?.aesthetics ?? 0) - Double(defauts.count)
    }

    /// Départage les photos d'une même rafale ou pile (même sujet) : seulement là, la qualité du
    /// meilleur visage compte.
    var scoreDansGroupe: Double { score + 0.5 * (vision?.faces.compactMap(\.quality).max() ?? 0) }

    public var pourquoi: String {
        var parties: [String] = []
        if let auPoint = af?.netteteJugee { parties.append("netteté au point AF \(Self.r(auPoint))") }
        else if let detail {
            let sansTexture = af?.nettete != nil && af?.jugeable == false
            parties.append("netteté \(Self.r(detail.sharpest))" + (sansTexture ? " (point AF sur une zone sans texture : mise au point non jugée)" : ""))
        }
        if let visage = vision?.faces.compactMap(\.quality).max() { parties.append("visage \(DevelopCatalogue.format((visage * 100).rounded() / 100))") }
        if let note = vision?.aesthetics { parties.append("note esthétique \(DevelopCatalogue.format((note * 100).rounded() / 100))") }
        if vision?.utility == true { parties.append("utilitaire selon Vision (capture, document)") }
        return parties.isEmpty ? "aucune mesure" : parties.joined(separator: ", ")
    }

    /// Une ligne par photo, pour `details`.
    var json: JSONValue {
        var item: [String: JSONValue] = ["id": .number(Double(id)), "fichier": .string(fichier),
                                         "ordre": .number((score * 100).rounded() / 100), "mesures": .string(pourquoi)]
        if let detail { item["nettete_max"] = .number((detail.sharpest * 10).rounded() / 10) }
        if let bruit = detail?.noise { item["bruit"] = .number((bruit * 100).rounded() / 100) }
        let liste = defauts
        if !liste.isEmpty { item["defauts"] = .array(liste.map(JSONValue.string)) }
        if let pile { item["pile"] = .number(Double(pile)) }
        if let af {
            var point: [String: JSONValue] = ["x": .number((Double(af.point.x) * 1000).rounded() / 1000),
                                              "y": .number((Double(af.point.y) * 1000).rounded() / 1000)]
            if !af.jugeable {
                point["mise_au_point"] = "non jugée : zone sans texture autour du point"
            } else if af.douteuse {
                point["mise_au_point"] = "à vérifier : texture faible autour du point"
            }
            item["point_af"] = .object(point)
        }
        if !motsCles.isEmpty { item["mots_cles"] = .array(motsCles.map { .string($0.mot) }) }
        let yeux = (vision?.faces ?? []).compactMap { face in face.eyeOpenness.map { (face.box.width, $0) } }
        if !yeux.isEmpty {
            item["yeux"] = .array(yeux.map { ["visage": .number((Double($0.0) * 1000).rounded() / 1000), "ouverture": .number(($0.1 * 1000).rounded() / 1000)] })
        }
        return .object(item)
    }
}

/// Bilan d'une séance : photos floues ou ratées, rafales avec la meilleure de chacune, ordre de
/// lecture, plafonds de note mesurés (le plancher technique du standard de notation) et
/// proposition de rejet, que Claude présente avant de la poser (set_metadata). Aucune étoile : elles
/// se proposent par propose_ratings, après avoir regardé les photos.
public enum Tri {
    /// Poids de la note esthétique de Vision dans l'ordre de lecture (elle va de −1 à 1, la netteté
    /// de 0 à 1) : un indice d'Impact, pas un critère du standard.
    static let poidsEsthetique = 0.5
    static let tailleClassement = 15
    /// Au-delà, les plafonds se disent par motif (`plafonds_par_motif`), pas photo par photo.
    static let plafondsParPhotoMax = 100
    /// Deux photos consécutives sont de la même rafale si Vision y voit la même scène et si elles
    /// sont prises à moins de `ecartRafale` secondes l'une de l'autre. Relevé le 17 octobre 2026
    /// sur une vraie séance de 329 photos : sans l'écart de temps, les photos semblables de
    /// proche en proche formaient un groupe de 193 photos (même salle, même éclairage).
    static let ecartRafale: TimeInterval = 4
    /// Sans date, une ressemblance plus stricte (même photo, ou presque).
    static let distanceSansDate = 0.35

    /// Groupes dont seule la meilleure vue échappe au plafond de 2 ★ (3 ★ avant le 26 octobre 2026) : les rafales, et les piles de
    /// Lightroom (une pile et une rafale qui se touchent n'en font qu'un). `pile` : la photo du
    /// dessus, si le groupe porte une pile.
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
        // Deux boîtiers différents (X-H2S et X-T4 sur la même scène) : jamais la même rafale (1.3.5).
        if let sa = a.boitier, let sb = b.boitier, !sa.isEmpty, !sb.isEmpty, sa != sb { return false }
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

    /// Groupes (rafales et piles), la meilleure de chacun, et le plafond de chaque photo (par indice).
    struct Analyse {
        var groupes: [(membres: [Int], pile: Int?)]
        var meilleures: [Int: Int]   // groupe → indice
        var plafonds: [Int: Notation.Plafond]
    }

    static func analyser(_ photos: [PhotoTriee]) -> Analyse {
        let groupes = Self.groupes(photos)
        // La meilleure de chaque rafale : sans défaut si possible, au meilleur score dans le groupe
        // (la qualité des visages y départage des prises du même sujet).
        var meilleures: [Int: Int] = [:]
        var autres: Set<Int> = []
        for (g, groupe) in groupes.enumerated() {
            let candidates = groupe.membres.filter { photos[$0].defauts.isEmpty }
            let pool = candidates.isEmpty ? groupe.membres : candidates
            let meilleure = pool.max { photos[$0].scoreDansGroupe < photos[$1].scoreDansGroupe }
            meilleures[g] = meilleure
            autres.formUnion(groupe.membres.filter { $0 != meilleure })
        }
        // La règle de la rafale (1.3.4) : des yeux fermés ne font proposer le rejet que si une autre
        // vue du même groupe les a ouverts.
        var avecAutreVue: Set<Int> = []
        for groupe in groupes {
            for i in groupe.membres where groupe.membres.contains(where: { $0 != i && photos[$0].yeuxOuverts }) {
                avecAutreVue.insert(i)
            }
        }
        var plafonds: [Int: Notation.Plafond] = [:]
        for i in photos.indices {
            plafonds[i] = Notation.plafond(photos[i], doublon: autres.contains(i), autreVueYeuxOuverts: avecAutreVue.contains(i))
        }
        return Analyse(groupes: groupes, meilleures: meilleures, plafonds: plafonds)
    }

    /// Le plafond de chaque photo mesurée, par identifiant (sans les vignettes illisibles).
    public static func plafonds(_ photos: [PhotoTriee]) -> [Int: Notation.Plafond] {
        var parPhoto: [Int: Notation.Plafond] = [:]
        for (i, plafond) in analyser(photos).plafonds { parPhoto[photos[i].id] = plafond }
        return parPhoto
    }

    public static func bilan(_ photos: [PhotoTriee], details: Bool = false) -> JSONValue {
        let analyse = analyser(photos)
        let tous = analyse.groupes
        let groupes = tous.map(\.membres)
        let meilleures = analyse.meilleures
        let sansDefaut = photos.indices.filter { photos[$0].defauts.isEmpty }

        func ids(_ indices: [Int]) -> JSONValue { .array(indices.sorted().map { .number(Double(photos[$0].id)) }) }
        // Une seule règle pour toute proposition : la photo ne porte ni note ni drapeau (le drapeau
        // revient du module en « rejetée », avec l'accent : « aucun » est le seul repère sûr).
        func libre(_ i: Int) -> Bool { (photos[i].note ?? 0) == 0 && (photos[i].drapeau ?? "aucun") == "aucun" }

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
                 "ordre": .number((photos[i].score * 100).rounded() / 100), "pourquoi": .string(photos[i].pourquoi)]
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

        // Plafonds : seulement ceux qui bornent la note, ou qui demandent une vérification. Une
        // grande série les regroupe par motif (sans les mesures de chaque photo) : une ligne par
        // photo faisait 80 % de la réponse du tri de 951 photos (147 000 caractères, 26 octobre 2026).
        let bornes = analyse.plafonds.filter { $0.value.note < Notation.noteMaximale || $0.value.aVerifier }
        if !bornes.isEmpty, photos.count <= plafondsParPhotoMax {
            var plafonds: [String: JSONValue] = [:]
            for (i, plafond) in bornes {
                var item: [String: JSONValue] = ["note_max": .number(Double(plafond.note)), "pourquoi": .string(plafond.raison)]
                if plafond.aVerifier { item["a_verifier"] = true }
                plafonds[String(photos[i].id)] = .object(item)
            }
            resultat["plafonds"] = .object(plafonds)
        } else if !bornes.isEmpty {
            var parMotif: [String: (plafond: Notation.Plafond, photos: [Int])] = [:]
            for (i, plafond) in bornes {
                let cle = "\(plafond.note)|\(plafond.aVerifier)|\(plafond.motif)"
                parMotif[cle, default: (plafond, [])].photos.append(i)
            }
            resultat["plafonds_par_motif"] = .array(parMotif.values
                .sorted { ($0.plafond.note, -$0.photos.count, $0.plafond.motif) < ($1.plafond.note, -$1.photos.count, $1.plafond.motif) }
                .map { groupe in
                    var item: [String: JSONValue] = ["note_max": .number(Double(groupe.plafond.note)), "pourquoi": .string(groupe.plafond.motif),
                                                     "nombre": .number(Double(groupe.photos.count)), "photos": ids(groupe.photos)]
                    if groupe.plafond.aVerifier { item["a_verifier"] = true }
                    return .object(item)
                })
        }

        // Le standard n'a qu'un drapeau, Rejeter : pour un défaut majeur seulement, à confirmer à l'œil.
        var propositions: [JSONValue] = []
        let aRejeter = photos.indices.filter { analyse.plafonds[$0]?.rejet == true && libre($0) }
        if !aRejeter.isEmpty {
            propositions.append(["flag": "reject", "photo_ids": ids(aRejeter),
                                 "pourquoi": "défaut majeur (floue, mise au point manquée, ou yeux fermés quand une autre vue de sa rafale les a ouverts : floues_ou_ratees), à confirmer à l'œil ; la seule photo de sa scène : plutôt 1 étoile à vérifier (propose_ratings, to_check)"])
        }
        let doublons = groupes.enumerated().flatMap { g, membres in
            membres.filter { $0 != meilleures[g] && photos[$0].defauts.isEmpty }
        }
        if !doublons.isEmpty {
            resultat["rafales_moins_bonnes"] = ids(doublons)
        }
        resultat["propositions"] = .array(propositions)
        let dejaClassees = photos.indices.filter { !libre($0) }.count
        if dejaClassees > 0 {
            resultat["deja_classees"] = .string("\(dejaClassees) photo(s) portent déjà un drapeau ou une note : aucune proposition ne les touche.")
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
        if details {
            resultat["photos"] = .array(photos.indices.map { i in
                guard var ligne = photos[i].json.object else { return photos[i].json }
                if let plafond = analyse.plafonds[i] { ligne["plafond"] = .number(Double(plafond.note)) }
                return .object(ligne)
            })
        }
        return .object(resultat)
    }
}
