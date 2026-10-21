import Foundation

/// Standard de notation (sa seule copie : la ressource developpeur://notation, propose_ratings avec
/// read_standard, l'invite noter et la fenêtre Claude le reprennent d'ici), et plafonds de note que
/// cull_photos mesure sur une photo : le plancher technique du standard, qui borne la note sans la
/// donner.
public enum Notation {
    /// Le standard, en Markdown, tel que Claude et l'utilisateur le lisent.
    public static let standard = """
    # Standard de notation

    Une étoile dit un niveau de qualité, et rien d'autre. Ce niveau a le même sens d'une sortie à
    l'autre, pour que « 4 ★ et plus » garde son sens au fil des années. Les autres décisions ont
    chacune leur outil : rejeter, c'est le drapeau Rejeter ; les doublons d'une rafale, une pile sous
    la meilleure vue ; la valeur affective, un mot-clé ou une collection. 0 ★ veut dire « pas encore
    jugée », jamais « mauvaise ».

    ## Les notes

    - **Rejet (drapeau)** : défaut majeur, involontaire, confirmé à l'œil. Si c'est la seule photo de
      sa scène, proposer plutôt 1 ★, à vérifier.
    - **1 ★** : gardée, mais pas au niveau du 2 ★.
    - **2 ★** : correcte, aucun défaut visible à la taille d'usage (écran, album). Elle a besoin de
      l'album ou du récit pour exister.
    - **3 ★** : elle tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu : sujet clair,
      fond qui ne distrait pas, composition soignée, lumière qui sert le sujet, moment juste.
    - **4 ★** : une 3 ★ qui a de l'impact : vue en premier sur une planche de 20 à 30 vignettes,
      nette à 100 % sur le sujet, meilleure vue de son moment. Souvent 5 à 10 % d'une sortie, sans
      quota : une sortie faible peut n'en avoir aucune.
    - **5 ★** : elle tient à côté des meilleures photos de l'utilisateur, toutes sorties confondues ;
      développement fini, sans excès ; toujours forte quelques jours plus tard. Posée par
      l'utilisateur seul : Claude ne propose jamais 5 ★.

    Une photo qui ne remplit pas les conditions d'une note reçoit la note d'en dessous.

    ## Les critères, du plus lourd au plus léger

    1. **Impact** : la photo arrête l'œil, dit quelque chose, n'a pas l'air déjà vue. Aucune mesure ne
       le voit.
    2. **Qualités de l'image** : lumière, sujet clair, composition, moment ou expression, couleur.
    3. **Plancher technique**, mesuré par cull_photos : il plafonne la note, il ne la donne pas.
       Netteté (moins de 15 : floue ; 15 à 35 : douce ; plus de 35 : nette), exposition (presque noire,
       brûlée), yeux fermés, bruit (plus de 1,5 : fort ; une photo de nuit se note après le
       débruitage).
    4. **Finition**, pour le 5 ★ seulement : halos aux bords des masques, peau plastique, saturation.

    Plafonds : un défaut visible à la taille d'usage plafonne à 2 ★ ; un défaut visible seulement à
    100 % plafonne à 3 ★ ; un défaut voulu et maîtrisé ne compte pas. Ne comptent pas : l'effort de la
    prise de vue, la valeur affective.

    ## Selon le genre

    Famille : la relation, une douceur due au mouvement tolérée. Portrait : l'expression et les yeux.
    Paysage : la lumière, une netteté du premier plan jusqu'au fond. Nuit : notée après le
    débruitage. Sport : le sommet de l'action. Rue : le geste, plus de tolérance sur la netteté.

    ## Les passes, une question à la fois

    1. Rejeter ou non ? Les cas douteux (groupe, nuit, flou peut-être voulu) vont « à vérifier ».
    2. 3 ★ ou non ? Les autres photos gardées reçoivent 2 ★ (1 ★ au passage).
    3. Parmi les 3 ★, monter à 4 ★ ? Toute la sortie vue, les candidates regardées à 100 %.
    4. Après le développement, 5 ★ ? L'utilisateur seul.

    ## Ce que valent les mesures

    La note esthétique de Vision ne compare que des photos d'une même sortie et d'un même genre. La
    qualité de visage ne départage que les photos d'une rafale. Les mesures fixent le plancher et
    départagent une rafale ; elles ne justifient jamais seules un 4 ★.

    ## Photos étalons

    Si la collection « Développeur › Étalons » existe, la regarder avant de noter : une « tout juste
    3 » et une « presque 3 », de même entre 3 et 4, par genre.
    """

    /// Claude propose de 0 à 4 étoiles : 5 est posé par l'utilisateur seul.
    public static let noteMaximale = 4
    /// Les passes du standard ; la dernière (5 étoiles) est à l'utilisateur seul : Claude n'y
    /// propose rien.
    public static let passes = 4

    /// Les critères d'une proposition, du plus lourd au plus léger : nom dans propose_ratings, nom
    /// pour le module (commande notation), obligatoire ou non (la Finition ne compte que pour un 5).
    static let criteres: [(nom: String, module: String, obligatoire: Bool)] = [
        ("impact", "impact", true), ("qualities", "qualites", true), ("technical_floor", "plancher", true), ("finish", "finition", false),
    ]
    /// Longueur d'un critère et de la raison d'une proposition, en caractères : celle demandée à
    /// Claude (la carte de note la montre entière), et celle refusée au-delà (Claude dépasse de peu
    /// en comptant mal : constaté, 209 pour 200 ; la carte coupe le surplus, le fil le garde).
    static let longueurCritere = 200
    static let longueurRaison = 300
    static let toleranceCritere = 300
    static let toleranceRaison = 400

    /// Ce que le plancher technique mesuré permet au plus.
    public struct Plafond: Equatable {
        /// Note la plus haute que la photo peut recevoir (0 à `noteMaximale`).
        public var note: Int
        /// Pourquoi, mesures à l'appui.
        public var raison: String
        /// Défaut majeur (floue, mise au point manquée, yeux fermés) : rejet proposé, à confirmer à l'œil.
        public var rejet: Bool
        /// Rattrapable par la retouche ou douteux : à vérifier par l'utilisateur.
        public var aVerifier: Bool
    }

    /// Le plafond d'une photo triée, d'après le standard et les seuils déjà relevés (netteté 15 et
    /// 35, bruit 1,5 : `DetailMeasurements.seuilFlou`, `seuilNet` et `bruitFort`) : un défaut
    /// majeur, 0 et rejet proposé ; un défaut visible seulement à 100 % (douce, mise au point
    /// signalée manquée par l'appareil), 3 ; presque noire ou brûlée, 2, à
    /// vérifier (souvent rattrapable, surtout en RAW) ; une capture ou un document selon Vision, 1 ;
    /// une photo qui n'est pas la meilleure de sa rafale ou de sa pile (`doublon`), 3 (un 4 est la
    /// meilleure vue de son moment). Un bruit fort ne plafonne pas : la photo se note après le
    /// débruitage, à vérifier. Nil si rien n'a pu être mesuré (vignette illisible).
    public static func plafond(_ photo: PhotoTriee, doublon: Bool) -> Plafond? {
        guard photo.erreur == nil else { return nil }
        var limites: [(note: Int, raison: String)] = []
        var rejet = false, aVerifier = false
        let raw = ["RAW", "DNG"].contains(photo.format?.uppercased() ?? "")
        for (genre, texte) in photo.defautsMesures {
            switch genre {
            case .floue, .miseAuPointManquee, .yeuxFermes:
                limites.append((0, texte))
                rejet = true
            case .miseAuPointSignalee:
                limites.append((3, texte))
            case .presqueNoire, .brulee:
                limites.append((2, texte + (raw ? " : rattrapable par la retouche (RAW), à vérifier" : " : à vérifier après la retouche")))
                aVerifier = true
            }
        }
        let signalee = photo.defautsMesures.contains { $0.genre == .miseAuPointSignalee }
        if !rejet, !signalee, let nettete = photo.nettete, nettete < DetailMeasurements.seuilNet {
            limites.append((3, "douce (netteté \(PhotoTriee.r(nettete))\(photo.af?.nettete != nil ? " au point AF" : "") ; nette à partir de \(PhotoTriee.r(DetailMeasurements.seuilNet)))"))
        }
        if photo.vision?.utility == true {
            limites.append((1, "capture ou document selon Vision"))
        }
        if doublon {
            limites.append((3, "pas la meilleure de sa rafale ou de sa pile (un 4 est la meilleure vue de son moment)"))
        }
        if let detail = photo.detail, max(detail.noise, detail.shadowNoise ?? 0) >= DetailMeasurements.bruitFort {
            limites.append((noteMaximale, "bruit fort (\(PhotoTriee.r2(max(detail.noise, detail.shadowNoise ?? 0)))) : à noter après le débruitage (enhance_photo)"))
            aVerifier = true
        }
        let note = limites.map(\.note).min() ?? noteMaximale
        let raison = limites.isEmpty
            ? "aucun défaut mesuré : \(noteMaximale) au plus (5 : l'utilisateur seul)"
            : limites.sorted { $0.note < $1.note }.map(\.raison).joined(separator: " ; ")
        return Plafond(note: min(note, noteMaximale), raison: raison, rejet: rejet, aVerifier: aVerifier)
    }
}
