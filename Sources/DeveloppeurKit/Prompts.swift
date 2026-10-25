import Foundation

/// Une invite proposée dans Claude (menu « + » de Claude Desktop, ou « / » dans Claude Code).
public struct PromptTemplate {
    public struct Argument {
        public var name: String
        public var description: String
    }

    public var name: String
    public var description: String
    public var arguments: [Argument]
    /// L'invite reçoit le guide de style de l'utilisateur à la fin (s'il existe).
    public var avecGuide: Bool = false
    public var render: ([String: String]) -> String

    public var definition: JSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "arguments": .array(arguments.map {
                ["name": .string($0.name), "description": .string($0.description), "required": false]
            }),
        ]
    }
}

public enum Prompts {
    /// L'invite telle que Claude la reçoit : son texte, puis le guide de style s'il y a lieu.
    public static func texte(_ prompt: PromptTemplate, _ arguments: [String: String], guide: String?) -> String {
        var texte = prompt.render(arguments)
        if prompt.avecGuide, let guide {
            texte += "\n\nGuide de style de l'utilisateur, à suivre sauf demande contraire (ses goûts ; remember_style y ajoute une préférence après son accord) :\n\n" + guide
        }
        return texte
    }

    public static let all: [PromptTemplate] = [retouchePro, aMaFacon, harmoniserSerie, triSeance, noter, portrait, paysage, noirEtBlanc, nuitIsoEleve, partage]

    private static let styleArgument = PromptTemplate.Argument(
        name: "style",
        description: "Rendu voulu, en quelques mots : naturel, chaud et doux, éditorial contrasté, noir et blanc, cinéma…")

    private static func styleSentence(_ arguments: [String: String]) -> String {
        guard let style = arguments["style"]?.trimmingCharacters(in: .whitespacesAndNewlines), !style.isEmpty else {
            return " Rendu voulu : naturel et fidèle à la scène."
        }
        return " Rendu voulu : \(style)."
    }

    public static let retouchePro = PromptTemplate(
        name: "retouche_pro",
        description: "Retoucher la photo active de Lightroom Classic comme un professionnel, en deux passes vérifiées, puis au plus deux passes correctives si un défaut reste.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche la photo active de Lightroom Classic comme le ferait un retoucheur professionnel.\(styleSentence(arguments))

            1. view_photo : regarde l'aperçu, les données de prise de vue, les mesures (luminosité, écrêtage, contraste, dominante, netteté, bruit) et ce que voit Vision (visages, zone d'intérêt).
            2. Pose un diagnostic en quelques lignes, chiffres à l'appui : exposition, balance des blancs, contraste, dominantes de couleur, mise au point, bruit, sujet, et ce que la photo cherche à montrer (intention_boitier, s'il est donné : ce que le photographe a choisi à la prise de vue). Un éclairage mixte (mesures › eclairage : mixte = true) se dit : balance des blancs sur la lumière des visages ou du sujet (balance_proposee), l'autre lumière par un masque à l'étape 7 (Temperature et Tint locaux), ou gardée chaude si c'est une lampe. Des reflets de vitre se retirent en premier, avant toute autre retouche (remove_distractions). Si elle demande un outil que tu n'as pas (passants, gros objet à effacer), dis-le dès maintenant.
            3. Si une ligne qui devrait être droite semble pencher (horizon, crête, bâtiment, poteau), mesure-la avec measure_angle plutôt qu'à l'œil.
            4. Première passe (apply_settings, step_name « passe 1 : lumière et couleur », avec reason) : profil adapté au rendu voulu (RAW Fujifilm : d'abord la simulation choisie au boîtier, intention_boitier.profil, sauf autre style demandé ; un profil adaptatif, Adaptive Color ou Adaptive B&W, se pose ici, sans auto_tone : Lightroom le calcule dès la retouche), corrections d'objectif, puis le redressement : soit crop.angle (de measure_angle, s'il penche de plus de 0,5°), soit Upright (verticales qui fuient), jamais les deux dans la même passe (Upright remet lui-même l'horizon ; après Upright, view_photo puis measure_angle de nouveau avant tout crop.angle) ; balance des blancs, puis exposition, hautes lumières, ombres, blancs, noirs et contraste. Ne recadre que si la composition y gagne nettement (read_composition donne le cadre : montre-le par preview_settings et attends l'accord), et dis-le ; avec Upright, le module coche « Contraindre le recadrage » et Lightroom resserre le cadre pour ne laisser aucun coin vide (lis « remarques ») : pour recadrer, fais-le dans un appel suivant, au centre que tu veux.
            5. view_photo de nouveau : juge le résultat d'un œil critique et sur les mesures (hautes lumières brûlées, aussi par canal, ombres bouchées, peau, couleurs, équilibre général). Lis le bilan (avant → après, chiffré) : une « regression » est un défaut que la passe a créé ou aggravé, à corriger avant la suite. Après Upright ou une perspective, regarde le cadre que Lightroom a gardé (« remarques ») et vérifie qu'aucun coin vide ne reste (view_photo le compterait comme blanc écrêté).
            6. Deuxième passe (step_name « passe 2 : finitions ») : présence, TSL (il touche toutes les couleurs semblables : pour un seul objet, plutôt un masque à l'étape 7), étalonnage (une dominante verte ou magenta restée dans les seules ombres : ShadowTint, pas Tint), courbe (relis d'abord ToneCurvePV2012 avec get_settings : des curseurs Parametric… à 0 ne prouvent pas une courbe droite), netteté (view_photo avec region pour juger à 100 %), vignetage (ou les bords par un radial inversé à l'étape 7, jamais les deux), avec retenue. Bruit fort (mesure au-dessus de 1,5) : le débruitage IA de Lightroom (enhance_photo) d'abord, avant la netteté, les masques et les taches de l'étape 7, et pas de LuminanceSmoothing par-dessus ; bruit léger : réduction manuelle modérée.
            7. Si la photo le demande, retouches locales avec add_mask (ciel, sujet, arrière-plan, visage, dégradés, combinés au besoin), légères ; pour un portrait, les effets de Lightroom (effect : blanchiment des dents sur person_part teeth, renforcement de l'iris sur iris_pupil, peau dosée comme le dit add_mask (« Peau du visage lisse » par défaut, rien pour un enfant)), souvent à intensité réduite (amount) ; yeux rouges avec retouch_spots, seulement si un zoom montre des pupilles rouges, au centre de la pupille vu dans ce zoom. Pour mener l'œil au sujet : éclaircir et assombrir comme un tireur (doses dans la description d'add_mask), en une étape, suivie de \(Tireur.avantApres).
            8. view_photo de nouveau. Si un défaut précis reste, mesuré ou visible (hautes lumières brûlées, ombres bouchées, dominante, peau, masque trop visible), ou une « regression » au bilan, fais une passe corrective ciblée sur ce seul défaut (step_name « passe 3 : … », avec une reason qui le nomme), puis vérifie de même. Deux passes correctives au plus : s'il reste un défaut, dis-le dans le résumé plutôt que d'empiler les réglages. Pas de passe corrective sans défaut constaté.
            9. view_photo avec compare = before_claude (son bilan chiffre ce qui a changé depuis l'état d'avant Claude), puis résume en quelques puces ce que tu as changé et pourquoi, chiffres du bilan à l'appui, et ce qui reste à faire à la main dans Lightroom s'il y a lieu.
            """
        })

    /// Ton style sur une photo neuve (1.3.5) : le guide de style appliqué d'abord, puis la méthode
    /// habituelle pour ce qui reste.
    public static let aMaFacon = PromptTemplate(
        name: "a_ma_facon",
        description: "Retoucher la photo active à la façon de l'utilisateur : son guide de style appliqué d'abord, puis la méthode habituelle seulement pour ce qu'il ne dit pas.",
        arguments: [],
        avecGuide: true,
        render: { _ in
            """
            Retouche la photo active de Lightroom Classic à ma façon : mon guide de style d'abord, puis ta méthode habituelle seulement pour ce qu'il ne dit pas.

            1. remember_style avec read (le guide est aussi plus bas) : relève chacune de mes préférences qui touche cette photo (profil, contraste, couleurs, peau, noir et blanc, grain, recadrage). Sans guide, dis-le, et retouche comme retouche_pro.
            2. view_photo : diagnostic bref, chiffres à l'appui, et ce que la photo cherche à montrer (intention_boitier, s'il est donné).
            3. Première passe (apply_settings, step_name « passe 1 : mon guide », avec reason) : mes préférences, telles que le guide les dit, sans les réinterpréter ; une préférence qui contredit la photo (un noir dense sur une scène de brume) se dit, et ne se pose pas.
            4. view_photo, puis la méthode de retouche_pro pour le reste seulement (balance, exposition, finitions, retouches locales légères), chaque étape avec sa reason ; ne défais pas une préférence du guide sans le dire.
            \(finRetouche) Dis enfin quelles préférences du guide ont servi.
            """
        })

    public static let harmoniserSerie = PromptTemplate(
        name: "harmoniser_serie",
        description: "Retoucher les photos sélectionnées dans Lightroom Classic pour qu'elles forment une série cohérente.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Harmonise les photos sélectionnées dans Lightroom Classic pour qu'elles forment une série cohérente.\(styleSentence(arguments))

            1. list_selection pour voir les photos, contact_sheet pour les voir d'un coup d'œil (\(ToolHandler.maxContactSheet) par planche), puis analyze_photos pour les mesurer toutes. Pour écarter les floues, les yeux fermés et les doublons d'une rafale ou d'une pile, cull_photos.
            2. view_photo sur un échantillon de 6 à 8 photos : repère les écarts de balance des blancs, d'exposition et de contraste.
            3. Choisis la photo de référence (dis laquelle et pourquoi) et retouche-la d'abord, en deux passes vérifiées, puis au plus deux passes correctives, seulement sur un défaut constaté.
            4. copy_settings depuis la référence vers les autres photos (profil et réglages communs). Upright : copy_settings copie le mode, que Lightroom recalcule pour chaque photo ; le module coche « Contraindre le recadrage », et Lightroom resserre le cadre de chacune pour ne laisser aucun coin vide. Poussière du capteur sur toute la série : propose la suppression de la poussière de Lightroom (Suppression des distractions › Poussière), à faire à la main sur une photo, puis Copier et Coller de Lightroom avec la case Poussière (Lightroom la refait pour chaque photo ; copy_settings ne le peut pas).
            5. match_series avec reference_id (sans confirm : le plan, écarts mesurés d'exposition, de balance et de contraste, photo par photo) ; montre-le, puis, avec l'accord, match_series avec confirm = true (deux passes mesurées par photo). Ce qui reste hors de sa portée se corrige par apply_settings, relative = true.
            6. Vérifie deux ou trois photos avec view_photo, puis résume ce qui a été fait.
            """
        })

    private static func argument(_ arguments: [String: String], _ nom: String) -> String? {
        guard let valeur = arguments[nom]?.trimmingCharacters(in: .whitespacesAndNewlines), !valeur.isEmpty else { return nil }
        return valeur
    }

    /// Vérification et résumé, communs aux invites de retouche.
    private static let finRetouche = """
        Puis view_photo de nouveau : si un défaut précis reste, mesuré, visible ou en « regression » au bilan, une passe corrective ciblée sur ce seul défaut (step_name « passe 3 : … », reason qui le nomme), deux au plus ; jamais de passe sans défaut constaté. Enfin view_photo avec compare = before_claude, et un résumé en quelques puces, chiffres du bilan à l'appui : ce qui a changé, pourquoi, et ce qui reste à faire à la main dans Lightroom.
        """

    public static let triSeance = PromptTemplate(
        name: "tri_seance",
        description: "Trier une séance : photos floues ou ratées, doublons de rafale, plafonds de note ; rejets et notes proposés selon le standard de notation, posés après accord.",
        arguments: [
            .init(name: "photos", description: "Où sont les photos : « la sélection », le nom d'une collection ou le chemin d'un dossier."),
            .init(name: "garder", description: "Combien en garder pour un album ou un partage, par exemple « 30 % » ou « les 20 meilleures » : une collection, pas une note."),
        ],
        render: { arguments in
            let ou = argument(arguments, "photos").map { "Photos : \($0)." } ?? "Photos : la sélection de Lightroom (sinon, demande où elles sont)."
            let garder = argument(arguments, "garder").map { " À garder : \($0) (dans une collection ; les notes suivent le standard, sans quota)." } ?? ""
            return """
            Trie une séance dans Lightroom Classic. \(ou)\(garder)

            1. cull_photos sur ces photos (selection, collection ou folder) : photos floues ou à la mise au point manquée, aux yeux fermés ou plissés, presque noires ou brûlées, rafales et piles de Lightroom (la meilleure de chacune), plafonds de note mesurés, rejets proposés, mots-clés fréquents. Une longue séance (des centaines de photos) : proposer d'abord une sauvegarde du catalogue (get_status, request_backup).
            2. contact_sheet par planches de 24 à 30 (offset) pour voir la séance d'un coup d'œil, puis chaque rafale ; view_photo (avec region sur le visage ou le sujet) pour une photo douteuse, et pour confirmer des yeux fermés (un sourire qui plisse les yeux peut être voulu). Une photo volontairement floue ou sombre n'est pas un défaut : juge l'intention.
            3. Les notes suivent le standard de notation (propose_ratings avec read_standard) : propose_ratings range des notes proposées de 0 à \(Notation.noteMaximale) étoiles, avec une raison par critère, sans dépasser les plafonds de cull_photos ; l'utilisateur accepte les notes dans Lightroom (carte Note), ou demande que tu les poses (apply = true). Ses coups de cœur sont un libellé de couleur qu'il pose lui-même : n'en propose ni n'en pose aucun sans sa demande. Pour noter toute la séance passe par passe : l'invite noter.
            4. Présente le tri à l'utilisateur, chiffres à l'appui : à rejeter (et pourquoi), la meilleure de chaque rafale, les notes proposées. Rien ne change sans son accord ; une photo déjà classée par lui garde son classement, sauf s'il le demande.
            5. Avec son accord : set_metadata (flag reject) pour les rejets, avec une reason ; au besoin une collection « Claude › Sélection » (manage_collections) pour les photos à garder, et des mots-clés proposés par cull_photos (seulement ceux qu'il approuve). Puis montrer le résultat dans Lightroom : show_photo avec folder ou collection et filter (rating_min, par exemple 3) ; restore_filter remet son filtre ensuite.
            6. Résume : combien de rejetées, de notes proposées ; comment les afficher dans Lightroom (filtre d'attributs de la Bibliothèque) ; undo_last défait un classement photo par photo.
            """
        })

    /// Une passe du standard de notation, telle que l'invite noter la donne.
    private static func passeNotation(_ arguments: [String: String]) -> String {
        guard let passe = argument(arguments, "passe") else { return " Toutes les passes du standard, une question à la fois (pass = 1, puis 2, puis 3 ; la 4, monter à 5 étoiles, après le développement)." }
        switch passe {
        case "1", "2", "3", "4": return " Passe \(passe) du standard (« Les passes ») : pass = \(passe) dans propose_ratings."
        default: return " Passe : \(passe)."
        }
    }

    public static let noter = PromptTemplate(
        name: "noter",
        description: "Noter des photos selon le standard de notation, passe par passe, avec une raison par critère : des notes proposées de 0 à 5 étoiles, que l'utilisateur accepte dans Lightroom (jamais de libellé de couleur).",
        arguments: [
            .init(name: "photos", description: "Où sont les photos : « la sélection », le nom d'une collection ou le chemin d'un dossier."),
            .init(name: "passe", description: "La passe : 1 (rejeter ou non), 2 (3 étoiles ou non), 3 (monter à 4 étoiles), 4 (monter à 5 étoiles, après le développement), ou une consigne (« revoir les 3 étoiles »)."),
        ],
        render: { arguments in
            let ou = argument(arguments, "photos").map { "Photos : \($0)." }
                ?? "Photos : la sélection de Lightroom (sinon, demande où elles sont)."
            return """
            Note des photos de Lightroom Classic selon le standard de notation, reproduit plus bas. \(ou)\(passeNotation(arguments))

            1. cull_photos sur ces photos : le plancher technique (défauts, plafonds de note), les rafales et les piles, les rejets proposés. Une photo de nuit ou au bruit fort se note après le débruitage.
            2. contact_sheet par planches de 24 à 30 (offset ; les numéros continuent d'une planche à l'autre) : l'Impact et les Qualités se jugent sur toute la sortie vue d'un coup.
            3. view_photo, avec region sur le sujet, pour les candidates à 4 et 5 étoiles (nette à 100 % sur le sujet, meilleure vue de son moment) et pour les cas douteux ; la Finition ne se juge que là (les vignettes peuvent dater d'avant la dernière retouche).
            4. propose_ratings, avec pass : une note de 0 à \(Notation.noteMaximale) ou flag reject, une raison par critère (impact, qualities, technical_floor ; finish pour une photo développée), une phrase (reason), to_check pour un cas douteux ; jamais au-dessus du plafond de cull_photos, sauf un défaut voulu et maîtrisé, dit dans technical_floor, avec to_check. 5 étoiles : rares, après le développement (passe 4). Jamais de libellé de couleur : ses coups de cœur, qu'il pose lui-même (set_metadata, seulement à sa demande). S'il demande que tu poses les notes, apply = true.
            5. Résume : combien par note, les cas douteux, et que l'utilisateur accepte ou change chaque note, arrivée à vérifier, dans Lightroom (carte Note). Jamais set_metadata pour une note sans sa demande ; une photo déjà notée par lui garde sa note, sauf s'il le demande.

            Standard de notation (aussi : ressource developpeur://notation, propose_ratings avec read_standard) :

            \(Notation.standard)
            """
        })

    public static let portrait = PromptTemplate(
        name: "portrait",
        description: "Retoucher un portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête, puis éclaircir et assombrir pour mener l'œil au visage.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche ce portrait dans Lightroom Classic (photo active), avec un rendu naturel : la personne doit se reconnaître.\(styleSentence(arguments))

            1. view_photo : visages et zone d'intérêt (Vision), mesures, données de prise de vue ; puis view_photo avec region sur les yeux : sont-ils nets ? La mise au point manquée ne se rattrape pas, dis-le. Regarde chaque visage : enfant, homme, femme ou personne âgée ; la dose de la peau en dépend (étape 4), et dans le doute, la plus faible.
            2. Première passe (apply_settings, « passe 1 : lumière et couleur ») : profil doux pour la peau (Adobe Portrait ; RAW Fujifilm : la simulation choisie au boîtier (intention_boitier.profil) si elle flatte la peau, sinon PRO Neg. Std, ASTIA ou Classic Chrome selon le style), corrections d'objectif, balance des blancs réglée sur la peau (ni orangée, ni grise, ni magenta) ; sous un éclairage mixte (view_photo › mesures › eclairage), balance sur la lumière du visage (balance_proposee), l'autre lumière par un masque à l'étape 4 (Temperature et Tint locaux) ou gardée chaude si c'est une lampe ; exposition juste sur le visage, hautes lumières de la peau tenues.
            3. view_photo : peau, yeux, arrière-plan. Deuxième passe (« passe 2 : finitions ») légère : Texture et Clarté globales modérées (une peau se lisse par masque, pas en global), Vibrance plutôt que Saturation, TSL des orangés avec retenue. Cadre : si le portrait y gagne nettement, read_composition, les yeux sur le tiers haut et de l'espace devant le regard ; son crop montré seul par preview_settings, sans compare, et l'accord attendu avant de l'appliquer.
            4. Retouches locales (add_mask). \(Peau.dosage) Puis, à intensité réduite (amount) : iris renforcé (iris_pupil), blanchiment des dents seulement si les dents se voient (teeth) ; arrière-plan (background) moins saturé s'il distrait (sa lumière se règle à l'étape 6). Petites imperfections passagères (boutons) : retouch_spots, jamais les grains de beauté ni les rides d'expression ; yeux rouges seulement si un zoom montre des pupilles rouges.
            5. Arrière-plan chargé et sujet bien détouré : lens_blur avec retenue (amount 20 à 40), puis view_photo avec region sur les contours (cheveux, épaules) : un halo ou un contour flou se retire.
            6. \(Tireur.methode(vers: "le visage", grandes: "Les grandes zones trop claires qui tirent l'œil hors du visage (fenêtre, mur clair, ciel)"))
            \(finRetouche)
            """
        })

    public static let paysage = PromptTemplate(
        name: "paysage",
        description: "Retoucher un paysage : horizon, ciel, profondeur, masques de paysage, puis éclaircir et assombrir pour mener l'œil au sujet.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche ce paysage dans Lightroom Classic (photo active).\(styleSentence(arguments))

            1. view_photo : mesures (hautes lumières du ciel, ombres), dominante, netteté. Mesure l'horizon avec measure_angle (sous 0,5°, il ne se voit pas) et les verticales d'un bâtiment s'il y en a.
            2. Première passe (apply_settings, « passe 1 : lumière et couleur ») : profil (Adobe Landscape ; RAW Fujifilm : la simulation choisie au boîtier (intention_boitier.profil), sinon Velvia pour des couleurs vives, PROVIA pour un rendu fidèle), corrections d'objectif, puis soit Upright si des verticales penchent, soit l'horizon redressé par crop.angle (pas les deux dans la même passe : après Upright, remesurer l'horizon), balance des blancs fidèle à la lumière (une lumière dorée reste dorée), hautes lumières baissées pour le ciel, ombres relevées sans aplatir, blancs et noirs posés.
            3. view_photo, puis deuxième passe (« passe 2 : finitions ») : Correction du voile modérée si la scène est voilée, Clarté et Texture avec retenue, Vibrance ; TSL des bleus et des verts pour des couleurs naturelles.
            4. Retouches locales (add_mask) : ciel (sky) un peu plus dense, sans halo au bord ; parties du paysage (landscape : montagnes, eau, végétation…) ; premier plan et lointain par un dégradé linéaire ou une plage de profondeur (depth, si la photo en porte une) ; une couleur précise par une plage de couleurs (color, samples prélevés dans l'image). Combine au besoin (combine : le ciel sans les montagnes). Contrôle chaque masque par view_photo avec region sur ses bords.
            5. Composition : read_composition, l'horizon désigné par deux points dans le dernier view_photo (le redressement de l'étape 2 a pu le déplacer) ; si le cadre y gagne nettement, preview_settings avec son crop seul, sans compare, la règle en une phrase (reason), et l'accord attendu avant apply_settings avec le même crop.
            6. \(Tireur.methode(vers: "le sujet", grandes: "Les grandes zones trop claires que l'étape 4 n'a pas déjà tenues (haut du ciel, eau ou sable qui brillent, premier plan clair)"))
            \(finRetouche)
            """
        })

    public static let noirEtBlanc = PromptTemplate(
        name: "noir_et_blanc",
        description: "Passer une photo en noir et blanc : profil, mélangeur, contraste local, éclaircir et assombrir, grain.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Passe la photo active de Lightroom Classic en noir et blanc.\(styleSentence(arguments))

            1. view_photo : la photo tient-elle en noir et blanc (lumière, formes, contraste des valeurs) ? Si ses couleurs font tout son sujet, dis-le avant de commencer.
            2. Profil (apply_settings, « passe 1 : noir et blanc ») : Adobe Monochrome, Adaptive B&W pour un RAW (en premier, sans auto_tone), ou pour un RAW Fujifilm ACROS (et ses filtres jaune, rouge, vert ; prise en noir et blanc au boîtier : intention_boitier.profil, avec son filtre) ; ou ConvertToGrayscale = 1 puis le mélangeur. Puis exposition, contraste, hautes lumières, ombres, blancs et noirs : de vrais noirs et de vrais blancs, sans boucher ni brûler.
            3. Mélangeur noir et blanc (GrayMixer…) : ciel plus dense (bleus vers le bas), peau plus claire (orangés vers le haut), feuillage selon l'effet voulu ; preview_settings avec compare si deux mélanges se discutent. Sous ACROS ou MONOCHROME (profils d'appareil), le mélangeur est sans effet : le filtre du profil fait ce travail (rouge : ciel sombre).
            4. Contraste local : courbe en S douce (tone_curve, après avoir relu ToneCurvePV2012), Clarté et Texture modérées.
            5. \(Tireur.methode(vers: "le sujet", grandes: "Les grandes zones trop claires (ciel, sol, mur) qui tirent l'œil hors du sujet"))
            6. Grain fin et discret (GrainAmount, GrainSize, GrainFrequency) si le style le demande, jugé à 100 % (view_photo avec region) ; un virage (Color Grading) seulement s'il est demandé.
            \(finRetouche)
            """
        })

    public static let nuitIsoEleve = PromptTemplate(
        name: "nuit_iso_eleve",
        description: "Retoucher une photo de nuit ou à ISO élevé : bruit, hautes lumières, couleurs des éclairages.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche cette photo de nuit ou à ISO élevé dans Lightroom Classic (photo active).\(styleSentence(arguments))

            1. view_photo : ISO, bruit mesuré (au-dessus de 1,5 il se voit), sources de lumière brûlées, dominantes des éclairages mêlés (sodium orangé, LED froides, néons verts ; mesures › eclairage) ; view_photo avec region dans les ombres ; intention_boitier (Fujifilm) : une compensation négative ou une scène de nuit dit une nuit voulue sombre.
            2. Débruitage d'abord (enhance_photo, denoise de 20 à 50 selon le bruit), avant les masques, les taches et la netteté, dont il change le résultat ; vérifie par un zoom à 100 % (ni plastique, ni détails inventés).
            3. Première passe (apply_settings, « passe 1 : lumière et couleur ») : balance des blancs sur la lumière principale, sans tout neutraliser (une rue au tungstène reste chaude) ; hautes lumières baissées pour retenir les lampes, ombres relevées avec retenue (elles montent le bruit), noirs posés pour garder une vraie nuit, sans remonter l'exposition d'ensemble au-delà de ce que dit intention_boitier.
            4. Deuxième passe (« passe 2 : finitions ») : TSL ou couleur ponctuelle pour calmer l'orangé du sodium ou le vert des néons ; netteté faible avec masquage (Sharpness, SharpenEdgeMasking), pas de réduction du bruit manuelle par-dessus le débruitage IA.
            5. Retouches locales légères (add_mask) : ciel plus sombre et plus propre, une source de lumière trop forte tenue par un masque radial.
            \(finRetouche)
            """
        })

    public static let partage = PromptTemplate(
        name: "partage",
        description: "Préparer des photos pour les montrer : écran, web, Instagram, impression ; dans un dossier choisi, sans rien écraser.",
        arguments: [
            .init(name: "destination", description: "Pour quoi : écran ou télé, web, Instagram, courriel, impression, archive…"),
            .init(name: "photos", description: "Quelles photos : « la sélection », une collection, les photos retenues…"),
        ],
        avecGuide: true,
        render: { arguments in
            let pour = argument(arguments, "destination").map { " Destination : \($0)." } ?? ""
            let quoi = argument(arguments, "photos").map { " Photos : \($0)." } ?? " Photos : la sélection de Lightroom (sinon, demande lesquelles)."
            return """
            Prépare des photos de Lightroom Classic pour les partager ou les imprimer.\(pour)\(quoi) Ce sont les photos personnelles de l'utilisateur, photographe amateur.

            1. export_photos avec list = true : livraisons types (les services Disque dur de l'utilisateur), modèles de noms de fichiers, filigranes, paramètres prédéfinis de métadonnées, dossiers récents.
            2. Vérifie les photos : celles qui sont prévues (find_photos : retenues, notées, d'une collection ; exported = false pour les retenues jamais exportées), retouchées ou non (export_journal), et dis-le si certaines ne le sont pas. Une photo dont l'original est introuvable (disque débranché) ne part que depuis son aperçu dynamique, 2560 px au plus : dis-le avec la raison.
            3. Propose des réglages adaptés et attends l'accord de l'utilisateur sur chaque point : dossier (avec lui, jamais deviné ; choose_folder = true lui ouvre une fenêtre dans Lightroom), format et taille (écran et web : la livraison type web, ou JPEG sRGB, long_edge 2048 ; Instagram : JPEG sRGB de 1080 px de large, long_edge 1080, ou 1350 pour une photo en hauteur au format 4:5, netteté écran ; courriel ou site qui limite le poids : max_size_kb ; écran ou télé HDR, pour une photo en mode HDR : hdr = true, en AVIF ou JPEG ; impression : JPEG qualité 100 pleine résolution (TIFF si le laboratoire le demande), netteté papier mat ou brillant, sRGB sauf demande du laboratoire, reimport = stack pour la garder empilée avec l'original ; archive : pleine qualité, ou original), filigrane seulement si l'utilisateur en veut un (watermark), modèle de noms (custom_text pour le nom de la sortie ou du voyage ; list = true avec filename_template et les photos montre les noms exacts), métadonnées, et lieu retiré ou non (retiré par défaut).
            4. Droits d'auteur : s'ils manquent (get_settings › classement) et que l'utilisateur veut les inscrire, set_metadata avec copyright ou metadata_preset, après accord ; le filigrane « copyright » les reprend. Pour le web, propose un texte alternatif par photo (alt_text, rédigé d'après view_photo), qui part avec le fichier.
            5. export_photos avec confirm = true. Un fichier déjà présent n'est jamais écrasé : le nouveau est renommé. Dis le résultat : dossier, nombre de fichiers, taille, échecs et leur raison, fichiers au-dessus du poids demandé, dimensions et HDR du premier fichier. En dernier recours, open_dialog ouvre la fenêtre d'exportation de Lightroom.
            """
        })
}

extension Prompts {
    /// Éclaircir et assombrir comme un tireur en chambre noire (1.2). Les doses n'existent qu'ici :
    /// les invites portrait, paysage et noir_et_blanc les reprennent par `methode`, la description
    /// d'add_mask par `resume` (la fenêtre Claude ne lit pas les invites ; ses boutons Portrait,
    /// Paysage et Noir et blanc, dans Consignes.lua, demandent la méthode sans chiffres).
    ///
    /// Les doses (zones, sujet, bords) viennent de la feuille de route, pas d'une mesure : ce sont
    /// des plafonds. Constaté le 20 octobre 2026 (Lightroom Classic 15.6, propositions sur des copies
    /// « Essai ») : un radial inversé (Locaux.radial : Flipped avec MaskInverted) n'assombrit que
    /// hors de l'ellipse, le centre reste intact.
    ///
    /// La forme des bords (`bordsRayon`, `bordsFondu`) est relevée le même jour sur une seule photo,
    /// un paysage (propositions de 1 344 px, radial inversé centré, radius_x = radius_y, Exposure
    /// −0,5 IL) : le centre n'est jamais touché et toutes les formes descendent sans marche. Au rayon
    /// 0,7, fondu 80 : milieu des bords −16 niveaux, coins −21 à −27, baisse commencée vers 15 % de la
    /// diagonale (le tiers central intact) ; fondu 100 assombrit presque tout le cadre, fondu 50 fait
    /// une vignette marquée aux seuls coins. Vérifiée le 21 octobre 2026 par la recette sur un
    /// portrait pris à l'intérieur, décentrée sur sa zone d'intérêt : à −0,3 IL, centre −0,5 %,
    /// milieu des bords −9,1 %, coins −8,5 % de luminance, plus forte marche 1,6 %. Le
    /// fondu du radial du sujet (`sujetFondu`) n'est pas relevé : à vérifier de même (ni halo, ni
    /// peau écrêtée).
    public enum Tireur {
        /// Le nom de l'étape (step_name), seul : « Claude · éclaircir et assombrir » dans l'Historique.
        public static let nomEtape = "éclaircir et assombrir"
        public static let etape = "« \(nomEtape) »"
        /// Grandes zones trop claires, par un dégradé linéaire.
        public static let zones = "Exposure de −0,3 à −0,7 IL"
        /// Le sujet (ou le visage), éclairci par un dégradé radial.
        public static let sujet = "+0,2 à +0,4 IL"
        /// Les bords, assombris par un radial inversé à la place du vignetage après recadrage.
        public static let bords = "−0,3 IL, −0,5 au plus"
        /// Forme du radial inversé des bords : une ellipse aux proportions de l'image (radius_x en part
        /// de la largeur, radius_y de la hauteur), assez grande pour laisser le sujet intact, au fondu
        /// large. Relevée centrée sur un paysage : à vérifier par la recette (voir plus haut).
        static let bordsRayon = "0,7"
        static let bordsFondu = "80"
        /// Fondu du radial du sujet. Pas relevé : à vérifier par la recette (ni halo, ni peau écrêtée).
        static let sujetFondu = "80 à 100"
        /// Vision rend la zone_d_interet par son coin haut gauche et sa taille : le centre se dit
        /// « au milieu », comme pour le radial du sujet.
        public static let forme = "invert = true, centré au milieu de la zone_d_interet de Vision (à défaut, du sujet), radius_x et radius_y \(bordsRayon), feather \(bordsFondu)"
        /// L'avant/après de cette seule étape, obligatoire.
        public static let avantApres = "view_photo avec compare = previous_step"

        /// La méthode, étape d'une invite : `vers`, où l'œil doit aller (« le visage », « le sujet ») ;
        /// `grandes`, les grandes zones trop claires de ce genre de photo, en début de phrase.
        static func methode(vers: String, grandes: String) -> String {
            "Éclaircir et assombrir, comme un tireur en chambre noire, pour mener l'œil vers \(vers) : un seul add_mask après le recadrage (step_name \(etape), une reason qui dit où va l'œil), un masque doux par geste. \(grandes) : assombries par un dégradé linéaire (kind linear ; from_x, from_y du côté le plus clair, où l'effet est entier ; to_x, to_y où il s'éteint), \(zones) selon l'écart ; si le sujet traverse le dégradé, combine [{\"mode\": \"subtract\", \"kind\": \"subject\"}]. Puis \(vers) : éclairci de \(sujet) par un dégradé radial (kind radial ; center_x, center_y au milieu du cadre du visage ou de la zone_d_interet que donne Vision (à défaut, du sujet vu au diagnostic) ; radius_x d'une à deux fois sa largeur ; feather \(sujetFondu)). Puis les bords : \(bords), par un dégradé radial inversé (kind radial, \(forme)), à la place du vignetage après recadrage, jamais les deux : si la photo en porte déjà un (PostCropVignetteAmount), ou si le guide de style écarte le vignetage, pas de radial inversé. Une zone de forme irrégulière : le pinceau (kind brush, strokes). Ces doses sont des plafonds : rester en dessous si le geste se remarque. En mode « Proposer d'abord », montre d'abord cette étape par add_mask avec preview = true et compare = true. Puis l'avant/après, obligatoire : \(avantApres) (l'état d'avant cette seule étape, à gauche). Le sujet doit ressortir sans que le geste se voie : ni halo autour du sujet, ni bande à la limite d'un dégradé, ni anneau ou plaque sombre dans les coins, et pas plus d'ombres bouchées qu'avant (ecretage_pct de mesures et de mesures_avant ; aucune « regression » au bilan). Un défaut vu : undo_last, puis le même add_mask à doses réduites (amount), et l'avant/après de nouveau."
        }

        /// La méthode en bref, à la fin de la description d'add_mask.
        public static let resume = "Éclaircir et assombrir pour mener l'œil au sujet (méthode du tireur des invites portrait, paysage et noir_et_blanc) : un seul add_mask après le recadrage, step_name \(etape) ; grandes zones trop claires par un dégradé linéaire, \(zones) ; sujet éclairci par un dégradé radial sur lui, \(sujet) ; bords par un dégradé radial inversé (\(forme)), \(bords), à la place du vignetage après recadrage, jamais les deux ; puis \(avantApres) : ni halo, ni bande, ni plaque sombre aux coins, sinon undo_last et doses réduites (amount)."
    }
}
