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
    l'autre (depuis l'échelle resserrée du 26 octobre 2026, plus bas), pour que « 3 ★ et plus »
    garde son sens au fil des années. Les autres décisions ont chacune leur outil : rejeter, c'est
    le drapeau Rejeter ; les doublons d'une rafale, une pile sous la meilleure vue ; la valeur
    affective, un mot-clé ou une collection ; les coups de cœur de l'utilisateur, un libellé de
    couleur qu'il pose lui-même. 0 ★ veut dire « pas encore jugée », jamais « mauvaise ».

    ## Les notes

    L'échelle de Claude va de 0 à 5 ★, plus le rejet.

    - **Rejet (drapeau)** : défaut majeur, involontaire, confirmé à l'œil. Si c'est la seule photo de
      sa scène, proposer plutôt 1 ★, à vérifier.
    - **1 ★** : gardée : correcte à la taille d'usage (écran, album), ou un peu en dessous. Elle a
      besoin de l'album ou du récit pour exister. La plupart des photos gardées d'une sortie.
    - **2 ★** : elle tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu : sujet clair,
      fond qui ne distrait pas, composition soignée, lumière qui sert le sujet, moment juste. Un bon
      souvenir bien fait (un sourire, une belle lumière) n'y suffit pas.
    - **3 ★** : une 2 ★ qui a de l'impact : vue en premier sur une planche de 20 à 30 vignettes,
      nette à 100 % sur le sujet, meilleure vue de son moment. Souvent 5 à 10 % d'une sortie, sans
      quota : une sortie faible peut n'en avoir aucune.
    - **4 ★** : une 3 ★ qui tient à côté des meilleures photos de l'utilisateur, toutes sorties
      confondues ; développement fini, sans excès, la Finition vue à 100 % ; toujours forte quelques
      jours plus tard. Rare : bien moins que les 3 ★, souvent aucune dans une sortie ; jamais avant le
      développement, ni sans avoir vu toute la sortie.
    - **5 ★** : une 4 ★ exceptionnelle, parmi les toutes meilleures de l'utilisateur, de celles qu'on
      imprime en grand. Très rare : quelques-unes par année au plus ; jamais avant le développement,
      ni sans avoir vu toute la sortie.

    Une photo qui ne remplit pas les conditions d'une note reçoit la note d'en dessous : dans le
    doute entre deux notes, la plus basse. Échelle resserrée d'une étoile le 26 octobre 2026, à la
    demande de l'utilisateur (Claude notait trop haut) : le 2 ★ d'aujourd'hui est le 3 ★ d'avant ; les
    notes posées avant gardent l'ancienne échelle.

    ## Les coups de cœur

    Les coups de cœur de l'utilisateur ne sont pas des étoiles : c'est un libellé de couleur qu'il
    pose lui-même. Claude ne propose, ne pose ni ne change jamais un libellé de couleur de lui-même :
    seulement à la demande explicite de l'utilisateur (set_metadata).

    ## Les critères, du plus lourd au plus léger

    1. **Impact** : la photo arrête l'œil, dit quelque chose, n'a pas l'air déjà vue. Aucune mesure ne
       le voit.
    2. **Qualités de l'image** : lumière, sujet clair, composition, moment ou expression, couleur.
    3. **Plancher technique**, mesuré par cull_photos : il plafonne la note, il ne la donne pas.
       Netteté (moins de 15 : floue ; 15 à 35 : douce ; plus de 35 : nette), exposition (presque noire,
       brûlée), yeux fermés (rejet seulement si une autre vue de la rafale les a ouverts : la seule
       vue de son moment ne se jette pas pour un clignement), bruit (plus de 1,5 : fort ; une photo de
       nuit se note après le débruitage).
    4. **Finition**, pour le 4 ★ et le 5 ★ seulement : halos aux bords des masques, peau plastique,
       saturation.

    Plafonds : un défaut visible à la taille d'usage plafonne à 1 ★ ; un défaut visible seulement à
    100 % plafonne à 2 ★ ; un défaut voulu et maîtrisé ne compte pas. Ne comptent pas : l'effort de la
    prise de vue, la valeur affective.

    ## Selon le genre

    Famille : la relation, une douceur due au mouvement tolérée. Portrait : l'expression et les yeux.
    Paysage : la lumière, une netteté du premier plan jusqu'au fond. Nuit : notée après le
    débruitage. Sport : le sommet de l'action. Rue : le geste, plus de tolérance sur la netteté.

    ## Les passes, une question à la fois

    1. Rejeter ou non ? Les cas douteux (groupe, nuit, flou peut-être voulu) vont « à vérifier ».
    2. 2 ★ ou non ? Les autres photos gardées reçoivent 1 ★.
    3. Parmi les 2 ★, monter à 3 ★ ? Toute la sortie vue, les candidates regardées à 100 %.
    4. Après le développement, parmi les 3 ★, monter à 4 ★, et, pour l'exceptionnel, à 5 ★ ? Les
       candidates regardées à 100 %, Finition comprise ; aucune si aucune ne tient à côté des
       meilleures de l'utilisateur.

    ## Ce que valent les mesures

    La note esthétique de Vision ne compare que des photos d'une même sortie et d'un même genre. La
    qualité de visage ne départage que les photos d'une rafale. Les mesures fixent le plancher et
    départagent une rafale ; elles ne justifient jamais seules un 3 ★ ni plus.

    ## Photos étalons

    Si la collection « Développeur › Étalons » existe, la regarder avant de noter : une « tout juste
    2 » et une « presque 2 », de même entre 2 et 3, entre 3 et 4 et entre 4 et 5, par genre.
    """

    /// Claude propose de 0 à 5 étoiles (demandé par Dany le 22 octobre 2026 : ses coups de cœur
    /// sont un libellé de couleur qu'il pose lui-même, jamais Claude).
    public static let noteMaximale = 5
    /// Les passes du standard ; la dernière (monter à 4 étoiles, et à 5 pour l'exceptionnel) se fait
    /// après le développement.
    public static let passes = 4

    /// Les critères d'une proposition, du plus lourd au plus léger : nom dans propose_ratings, nom
    /// pour le module (commande notation), obligatoire ou non (la Finition ne compte que pour un 4 ou un 5).
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
        /// Défaut majeur (floue, mise au point manquée, yeux fermés quand une autre vue de la rafale
        /// les a ouverts) : rejet proposé, à confirmer à l'œil.
        public var rejet: Bool
        /// Rattrapable par la retouche ou douteux : à vérifier par l'utilisateur.
        public var aVerifier: Bool
    }

    /// Le plafond d'une photo triée, d'après le standard et les seuils déjà relevés (netteté 15 et
    /// 35, bruit 1,5 : `DetailMeasurements.seuilFlou`, `seuilNet` et `bruitFort`), pour les seuls
    /// défauts (sans défaut, aucun plafond sous `noteMaximale`, 5 depuis le 22 octobre 2026) : un défaut
    /// majeur, 0 et rejet proposé ; un défaut visible seulement à 100 % (douce, mise au point
    /// signalée manquée par l'appareil), 2 ; presque noire ou brûlée, 1, à
    /// vérifier (souvent rattrapable, surtout en RAW) ; une capture ou un document selon Vision, 1 ;
    /// une photo qui n'est pas la meilleure de sa rafale ou de sa pile (`doublon`), 2 (un 3 est la
    /// meilleure vue de son moment). Des yeux fermés ne sont un défaut majeur que si une autre vue de
    /// la rafale ou de la pile les a ouverts (`autreVueYeuxOuverts`, la règle de la rafale, 1.3.4) ;
    /// sinon, 1, à vérifier. Une étoile plus bas qu'avant le 26 octobre 2026 (l'échelle resserrée à
    /// la demande de Dany : Claude notait trop haut), comme les niveaux du standard. Un bruit fort ne plafonne pas : la photo se note après le débruitage, à
    /// vérifier. Nil si rien n'a pu être mesuré (vignette illisible).
    public static func plafond(_ photo: PhotoTriee, doublon: Bool, autreVueYeuxOuverts: Bool = false) -> Plafond? {
        guard photo.erreur == nil else { return nil }
        var limites: [(note: Int, raison: String)] = []
        var rejet = false, aVerifier = false
        let raw = ["RAW", "DNG"].contains(photo.format?.uppercased() ?? "")
        for (genre, texte) in photo.defautsMesures {
            switch genre {
            case .miseAuPointManquee where photo.af?.douteuse == true:
                // Texture faible autour du point (DetailMeasurements.textureDouteuse) : un doute, pas
                // un rejet (le bord d'un nuage, relevé le 21 octobre 2026).
                limites.append((1, texte + " ; texture faible autour du point : à vérifier par un zoom à 100 %"))
                aVerifier = true
            case .floue, .miseAuPointManquee:
                limites.append((0, texte))
                rejet = true
            case .yeuxFermes where autreVueYeuxOuverts:
                limites.append((0, texte + " ; une autre vue de sa rafale les a ouverts"))
                rejet = true
            case .yeuxFermes:
                // La règle de la rafale (1.3.4) : la seule vue de son moment (la seule photo d'un
                // groupe) ne se jette pas pour un clignement.
                limites.append((1, texte + " ; aucune autre vue de sa rafale ne les a ouverts : la seule de son moment ne se jette pas pour un clignement, à vérifier"))
                aVerifier = true
            case .miseAuPointSignalee:
                limites.append((2, texte))
            case .presqueNoire, .brulee:
                limites.append((1, texte + (raw ? " : rattrapable par la retouche (RAW), à vérifier" : " : à vérifier après la retouche")))
                aVerifier = true
            }
        }
        let signalee = photo.defautsMesures.contains { $0.genre == .miseAuPointSignalee }
        if !rejet, !signalee, let nettete = photo.nettete, nettete < DetailMeasurements.seuilNet {
            limites.append((2, "douce (netteté \(PhotoTriee.r(nettete))\(photo.af?.netteteJugee != nil ? " au point AF" : "") ; nette à partir de \(PhotoTriee.r(DetailMeasurements.seuilNet)))"))
        }
        if photo.vision?.utility == true {
            limites.append((1, "capture ou document selon Vision"))
        }
        if doublon {
            limites.append((2, "pas la meilleure de sa rafale ou de sa pile (un 3 est la meilleure vue de son moment)"))
        }
        if let detail = photo.detail, max(detail.noise, detail.shadowNoise ?? 0) >= DetailMeasurements.bruitFort {
            limites.append((noteMaximale, "bruit fort (\(PhotoTriee.r2(max(detail.noise, detail.shadowNoise ?? 0)))) : à noter après le débruitage (enhance_photo)"))
            aVerifier = true
        }
        let note = limites.map(\.note).min() ?? noteMaximale
        let raison = limites.isEmpty
            ? "aucun défaut mesuré : pas de plafond"
            : limites.sorted { $0.note < $1.note }.map(\.raison).joined(separator: " ; ")
        return Plafond(note: min(note, noteMaximale), raison: raison, rejet: rejet, aVerifier: aVerifier)
    }
}
