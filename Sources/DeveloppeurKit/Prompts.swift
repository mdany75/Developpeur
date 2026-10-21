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

    public static let all: [PromptTemplate] = [retouchePro, harmoniserSerie, triSeance, noter, portrait, paysage, noirEtBlanc, nuitIsoEleve, partage]

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
            2. Pose un diagnostic en quelques lignes, chiffres à l'appui : exposition, balance des blancs, contraste, dominantes de couleur, mise au point, bruit, sujet, et ce que la photo cherche à montrer. Des reflets de vitre se retirent en premier, avant toute autre retouche (remove_distractions). Si elle demande un outil que tu n'as pas (passants, gros objet à effacer), dis-le dès maintenant.
            3. Si une ligne qui devrait être droite semble pencher (horizon, crête, bâtiment, poteau), mesure-la avec measure_angle plutôt qu'à l'œil.
            4. Première passe (apply_settings, step_name « passe 1 : lumière et couleur », avec reason) : profil adapté au rendu voulu (un profil adaptatif, Adaptive Color ou Adaptive B&W, se pose ici, sans auto_tone : Lightroom le calcule dès la retouche), corrections d'objectif, puis le redressement : soit crop.angle (de measure_angle, s'il penche de plus de 0,5°), soit Upright (verticales qui fuient), jamais les deux dans la même passe (Upright remet lui-même l'horizon ; après Upright, view_photo puis measure_angle de nouveau avant tout crop.angle) ; balance des blancs, puis exposition, hautes lumières, ombres, blancs, noirs et contraste. Ne recadre que si la composition y gagne nettement, et dis-le ; avec Upright, le module coche « Contraindre le recadrage » et Lightroom resserre le cadre pour ne laisser aucun coin vide (lis « remarques ») : pour recadrer, fais-le dans un appel suivant, au centre que tu veux.
            5. view_photo de nouveau : juge le résultat d'un œil critique et sur les mesures (hautes lumières brûlées, aussi par canal, ombres bouchées, peau, couleurs, équilibre général). Après Upright ou une perspective, regarde le cadre que Lightroom a gardé (« remarques ») et vérifie qu'aucun coin vide ne reste (view_photo le compterait comme blanc écrêté).
            6. Deuxième passe (step_name « passe 2 : finitions ») : présence, TSL (il touche toutes les couleurs semblables : pour un seul objet, plutôt un masque à l'étape 7), étalonnage (une dominante verte ou magenta restée dans les seules ombres : ShadowTint, pas Tint), courbe (relis d'abord ToneCurvePV2012 avec get_settings : des curseurs Parametric… à 0 ne prouvent pas une courbe droite), netteté (view_photo avec region pour juger à 100 %), vignetage, avec retenue. Bruit fort (mesure au-dessus de 1,5) : le débruitage IA de Lightroom (enhance_photo) d'abord, avant la netteté, les masques et les taches de l'étape 7, et pas de LuminanceSmoothing par-dessus ; bruit léger : réduction manuelle modérée.
            7. Si la photo le demande, retouches locales avec add_mask (ciel, sujet, arrière-plan, visage, dégradés, combinés au besoin), légères ; pour un portrait, les effets de Lightroom (effect : blanchiment des dents sur person_part teeth, renforcement de l'iris sur iris_pupil, peau adoucie), souvent à intensité réduite (amount) ; yeux rouges avec retouch_spots, seulement si un zoom montre des pupilles rouges, au centre de la pupille vu dans ce zoom.
            8. view_photo de nouveau. Si un défaut précis reste, mesuré ou visible (hautes lumières brûlées, ombres bouchées, dominante, peau, masque trop visible), fais une passe corrective ciblée sur ce seul défaut (step_name « passe 3 : … », avec une reason qui le nomme), puis vérifie de même. Deux passes correctives au plus : s'il reste un défaut, dis-le dans le résumé plutôt que d'empiler les réglages. Pas de passe corrective sans défaut constaté.
            9. view_photo avec compare = before_claude, puis résume en quelques puces ce que tu as changé et pourquoi, et ce qui reste à faire à la main dans Lightroom s'il y a lieu.
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
        Puis view_photo de nouveau : si un défaut précis reste, mesuré ou visible, une passe corrective ciblée sur ce seul défaut (step_name « passe 3 : … », reason qui le nomme), deux au plus ; jamais de passe sans défaut constaté. Enfin view_photo avec compare = before_claude, et un résumé en quelques puces : ce qui a changé, pourquoi, et ce qui reste à faire à la main dans Lightroom.
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
            3. Les notes suivent le standard de notation (propose_ratings avec read_standard) : propose_ratings range des notes proposées de 0 à \(Notation.noteMaximale) étoiles, avec une raison par critère, sans dépasser les plafonds de cull_photos ; 5 étoiles restent à l'utilisateur, qui accepte les notes dans Lightroom (carte Note), ou demande que tu les poses (apply = true). Pour noter toute la séance passe par passe : l'invite noter.
            4. Présente le tri à l'utilisateur, chiffres à l'appui : à rejeter (et pourquoi), la meilleure de chaque rafale, les notes proposées. Rien ne change sans son accord ; une photo déjà classée par lui garde son classement, sauf s'il le demande.
            5. Avec son accord : set_metadata (flag reject) pour les rejets, avec une reason ; au besoin une collection « Claude › Sélection » (manage_collections) pour les photos à garder, et des mots-clés proposés par cull_photos (seulement ceux qu'il approuve). Puis montrer le résultat dans Lightroom : show_photo avec folder ou collection et filter (rating_min, par exemple 3) ; restore_filter remet son filtre ensuite.
            6. Résume : combien de rejetées, de notes proposées ; comment les afficher dans Lightroom (filtre d'attributs de la Bibliothèque) ; undo_last défait un classement photo par photo.
            """
        })

    /// Une passe du standard de notation, telle que l'invite noter la donne.
    private static func passeNotation(_ arguments: [String: String]) -> String {
        guard let passe = argument(arguments, "passe") else { return " Toutes les passes du standard, une question à la fois (pass = 1, puis 2, puis 3)." }
        switch passe {
        case "1", "2", "3": return " Passe \(passe) du standard (« Les passes ») : pass = \(passe) dans propose_ratings."
        case "4": return " Passe 4 : 5 étoiles, l'utilisateur seul ; ne propose rien, montre-lui les candidates."
        default: return " Passe : \(passe)."
        }
    }

    public static let noter = PromptTemplate(
        name: "noter",
        description: "Noter des photos selon le standard de notation, passe par passe, avec une raison par critère : des notes proposées, que l'utilisateur accepte dans Lightroom (jamais 5 étoiles).",
        arguments: [
            .init(name: "photos", description: "Où sont les photos : « la sélection », le nom d'une collection ou le chemin d'un dossier."),
            .init(name: "passe", description: "La passe : 1 (rejeter ou non), 2 (3 étoiles ou non), 3 (monter à 4 étoiles), ou une consigne (« revoir les 3 étoiles »)."),
        ],
        render: { arguments in
            let ou = argument(arguments, "photos").map { "Photos : \($0)." }
                ?? "Photos : la sélection de Lightroom (sinon, demande où elles sont)."
            return """
            Note des photos de Lightroom Classic selon le standard de notation, reproduit plus bas. \(ou)\(passeNotation(arguments))

            1. cull_photos sur ces photos : le plancher technique (défauts, plafonds de note), les rafales et les piles, les rejets proposés. Une photo de nuit ou au bruit fort se note après le débruitage.
            2. contact_sheet par planches de 24 à 30 (offset ; les numéros continuent d'une planche à l'autre) : l'Impact et les Qualités se jugent sur toute la sortie vue d'un coup.
            3. view_photo, avec region sur le sujet, pour les candidates à 4 étoiles (nette à 100 % sur le sujet, meilleure vue de son moment) et pour les cas douteux ; la Finition ne se juge que là (les vignettes peuvent dater d'avant la dernière retouche).
            4. propose_ratings, avec pass : une note de 0 à \(Notation.noteMaximale) ou flag reject, une raison par critère (impact, qualities, technical_floor ; finish pour une photo développée), une phrase (reason), to_check pour un cas douteux ; jamais au-dessus du plafond de cull_photos, sauf un défaut voulu et maîtrisé, dit dans technical_floor, avec to_check. Jamais 5 étoiles de toi-même : l'utilisateur les pose, ou les demande (set_metadata). S'il demande que tu poses les notes, apply = true.
            5. Résume : combien par note, les cas douteux, et que l'utilisateur accepte ou change chaque note, arrivée à vérifier, dans Lightroom (carte Note). Jamais set_metadata pour une note sans sa demande ; une photo déjà notée par lui garde sa note, sauf s'il le demande.

            Standard de notation (aussi : ressource developpeur://notation, propose_ratings avec read_standard) :

            \(Notation.standard)
            """
        })

    public static let portrait = PromptTemplate(
        name: "portrait",
        description: "Retoucher un portrait : peau, yeux, dents, arrière-plan, flou d'objectif si la photo s'y prête.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche ce portrait dans Lightroom Classic (photo active), avec un rendu naturel : la personne doit se reconnaître.\(styleSentence(arguments))

            1. view_photo : visages et zone d'intérêt (Vision), mesures, données de prise de vue ; puis view_photo avec region sur les yeux : sont-ils nets ? La mise au point manquée ne se rattrape pas, dis-le.
            2. Première passe (apply_settings, « passe 1 : lumière et couleur ») : profil doux pour la peau (Adobe Portrait ; RAW Fujifilm : PRO Neg. Std, ASTIA ou Classic Chrome selon le style), corrections d'objectif, balance des blancs réglée sur la peau (ni orangée, ni grise, ni magenta), exposition juste sur le visage, hautes lumières de la peau tenues.
            3. view_photo : peau, yeux, arrière-plan. Deuxième passe (« passe 2 : finitions ») légère : Texture et Clarté globales modérées (une peau se lisse par masque, pas en global), Vibrance plutôt que Saturation, TSL des orangés avec retenue.
            4. Retouches locales (add_mask), à intensité réduite (amount) : peau adoucie (effect sur person_part face_skin, et body_skin si besoin), iris renforcé (iris_pupil), blanchiment des dents seulement si les dents se voient (teeth), un peu de lumière sur le visage ; arrière-plan (background) un peu plus sombre ou moins saturé s'il distrait. Petites imperfections passagères (boutons) : retouch_spots, jamais les grains de beauté ni les rides d'expression ; yeux rouges seulement si un zoom montre des pupilles rouges.
            5. Arrière-plan chargé et sujet bien détouré : lens_blur avec retenue (amount 20 à 40), puis view_photo avec region sur les contours (cheveux, épaules) : un halo ou un contour flou se retire.
            \(finRetouche)
            """
        })

    public static let paysage = PromptTemplate(
        name: "paysage",
        description: "Retoucher un paysage : horizon, ciel, profondeur, masques de paysage.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Retouche ce paysage dans Lightroom Classic (photo active).\(styleSentence(arguments))

            1. view_photo : mesures (hautes lumières du ciel, ombres), dominante, netteté. Mesure l'horizon avec measure_angle (sous 0,5°, il ne se voit pas) et les verticales d'un bâtiment s'il y en a.
            2. Première passe (apply_settings, « passe 1 : lumière et couleur ») : profil (Adobe Landscape ; RAW Fujifilm : Velvia pour des couleurs vives, PROVIA pour un rendu fidèle), corrections d'objectif, puis soit Upright si des verticales penchent, soit l'horizon redressé par crop.angle (pas les deux dans la même passe : après Upright, remesurer l'horizon), balance des blancs fidèle à la lumière (une lumière dorée reste dorée), hautes lumières baissées pour le ciel, ombres relevées sans aplatir, blancs et noirs posés.
            3. view_photo, puis deuxième passe (« passe 2 : finitions ») : Correction du voile modérée si la scène est voilée, Clarté et Texture avec retenue, Vibrance ; TSL des bleus et des verts pour des couleurs naturelles.
            4. Retouches locales (add_mask) : ciel (sky) un peu plus dense, sans halo au bord ; parties du paysage (landscape : montagnes, eau, végétation…) ; premier plan et lointain par un dégradé linéaire ou une plage de profondeur (depth, si la photo en porte une) ; une couleur précise par une plage de couleurs (color, samples prélevés dans l'image). Combine au besoin (combine : le ciel sans les montagnes). Contrôle chaque masque par view_photo avec region sur ses bords.
            5. Vignetage léger après le recadrage, seulement s'il sert la composition.
            \(finRetouche)
            """
        })

    public static let noirEtBlanc = PromptTemplate(
        name: "noir_et_blanc",
        description: "Passer une photo en noir et blanc : profil, mélangeur, contraste local, grain.",
        arguments: [styleArgument],
        avecGuide: true,
        render: { arguments in
            """
            Passe la photo active de Lightroom Classic en noir et blanc.\(styleSentence(arguments))

            1. view_photo : la photo tient-elle en noir et blanc (lumière, formes, contraste des valeurs) ? Si ses couleurs font tout son sujet, dis-le avant de commencer.
            2. Profil (apply_settings, « passe 1 : noir et blanc ») : Adobe Monochrome, Adaptive B&W pour un RAW (en premier, sans auto_tone), ou pour un RAW Fujifilm ACROS (et ses filtres jaune, rouge, vert) ; ou ConvertToGrayscale = 1 puis le mélangeur. Puis exposition, contraste, hautes lumières, ombres, blancs et noirs : de vrais noirs et de vrais blancs, sans boucher ni brûler.
            3. Mélangeur noir et blanc (GrayMixer…) : ciel plus dense (bleus vers le bas), peau plus claire (orangés vers le haut), feuillage selon l'effet voulu ; preview_settings avec compare si deux mélanges se discutent. Sous ACROS ou MONOCHROME (profils d'appareil), le mélangeur est sans effet : le filtre du profil fait ce travail (rouge : ciel sombre).
            4. Contraste local : courbe en S douce (tone_curve, après avoir relu ToneCurvePV2012), Clarté et Texture modérées, éclaircir et assombrir par masques (brush ou radial) pour guider l'œil.
            5. Grain fin et discret (GrainAmount, GrainSize, GrainFrequency) si le style le demande, jugé à 100 % (view_photo avec region) ; un virage (Color Grading) seulement s'il est demandé.
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

            1. view_photo : ISO, bruit mesuré (au-dessus de 1,5 il se voit), sources de lumière brûlées, dominantes des éclairages mêlés (sodium orangé, LED froides, néons verts) ; view_photo avec region dans les ombres.
            2. Débruitage d'abord (enhance_photo, denoise de 20 à 50 selon le bruit), avant les masques, les taches et la netteté, dont il change le résultat ; vérifie par un zoom à 100 % (ni plastique, ni détails inventés).
            3. Première passe (apply_settings, « passe 1 : lumière et couleur ») : balance des blancs sur la lumière principale, sans tout neutraliser (une rue au tungstène reste chaude) ; hautes lumières baissées pour retenir les lampes, ombres relevées avec retenue (elles montent le bruit), noirs posés pour garder une vraie nuit.
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
