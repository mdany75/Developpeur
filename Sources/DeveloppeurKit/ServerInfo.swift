import Foundation

public enum ServerInfo {
    /// Identifiant du serveur (`serverInfo.name`), celui de la clé d'inscription dans Claude.
    public static let name = "MCP-Developpeur"
    /// Nom affiché (`serverInfo.title`).
    public static let title = "MCP-Développeur"

    /// Numéro écrit dans Resources/Info.plist, incrusté dans l'exécutable.
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Claude Code ne garde que les 4096 premiers caractères des consignes d'un serveur (constaté
    /// le 16 octobre 2026) : ce qui dépasse est perdu. Le détail propre à un outil va dans sa
    /// description.
    public static let instructionsLimit = 4096

    public static let instructions = """
    Retouche photo dans Lightroom Classic, par le module « Développeur ». \
    L'utilisateur est photographe amateur, ses photos sont à lui : \
    viser le rendu d'un retoucheur professionnel, naturel, et lui dire simplement ce qui change et pourquoi. \
    Ce qu'il demande clairement, le faire ; ne refuser que ce que les outils ne savent pas faire, et le dire. \
    Méthode : view_photo (photo développée, mesures, Vision) : \
    diagnostic sur ces chiffres autant qu'à l'œil ; un diagnostic bref (exposition, balance des blancs, contraste, couleurs, sujet, intention) ; \
    une première passe avec apply_settings (profil, corrections d'objectif puis Upright, balance des blancs, puis tonalité) ; view_photo pour vérifier ; \
    une deuxième passe de finitions (présence, TSL, étalonnage, courbe, détail, vignetage ou radial inversé, jamais les deux) ; au besoin des retouches locales avec add_mask, \
    combinées au besoin (combine : le ciel sans le bâtiment) ; puis view_photo : si un défaut précis reste, mesuré ou visible \
    (hautes lumières brûlées, ombres bouchées, dominante, peau, masque trop visible, « regression » au bilan), une passe corrective ciblée sur ce seul défaut \
    (step_name « passe 3 : … », reason qui le nomme), vérifiée de même ; deux au plus, puis dire ce qui reste ; \
    jamais de passe sans défaut constaté (des réglages empilés font dériver la photo) ; \
    enfin un résumé de ce qui a changé et pourquoi. Donner « reason » à chaque retouche (journal : export_journal). \
    Profil : la base des couleurs et du contraste, à choisir avant le reste (list_profiles ; RAW Fujifilm : d'abord la simulation du boîtier, intention_boitier). \
    Couleur : une dominante verte ou magenta restée dans les seules ombres se corrige par ShadowTint, pas par Tint ; \
    le mélangeur TSL touche toutes les couleurs semblables : pour un seul objet, un masque ; dents, iris, peau : add_mask avec effect. \
    Géométrie : mesurer une inclinaison avec measure_angle (sous 0,5°, elle ne se voit pas) ; redresser par crop.angle, ou par Upright après les corrections d'objectif. \
    Recadrer (read_composition) seulement sur demande ou si la composition y gagne nettement, et le dire. \
    Bruit fort (mesure au-dessus de 1,5, ISO élevé, ombres relevées) : enhance_photo (denoise de 20 à 50), avant netteté, \
    masques IA et retouch_spots ; super résolution seulement pour un grand tirage ou un fort recadrage. \
    Série : copy_settings depuis une référence, puis match_series ; trier : \
    cull_photos (rejets : set_metadata après accord ; show_photo avec filter pour le montrer), contact_sheet ; noter : propose_ratings (0 à 5 ★, standard developpeur://notation ; apply = true s'il demande de noter ; libellé de couleur : sur sa demande) ; \
    classer : find_photos, set_metadata, \
    manage_collections ; undo_last défait aussi un classement. \
    Interprétations : compare_variants, puis choose_variant. \
    Partager ou imprimer : export_photos (list = true d'abord ; dossier choisi avec l'utilisateur, choose_folder). Goûts : remember_style (le lire ; n'y ajouter qu'après accord) ; corrections_utilisateur (ses reprises à la main) : en tenir compte, proposer de les retenir. \
    Un outil « pas fini » après 50 s se rappelle avec les mêmes arguments. \
    Rester naturel sauf style demandé ; Vibrance plutôt que Saturation ; modéré sur Clarity2012, Dehaze, Texture et les réglages locaux. \
    Mode « Proposer d'abord » : montrer le rendu (preview_settings, preview = true) ou les changements, attendre l'accord, puis confirm = true. \
    Reflets d'une vitre : remove_distractions, avant toute autre retouche. Original introuvable : le dire, avec la raison donnée. \
    À proposer de faire à la main dans Lightroom : passants (Suppression des distractions › Personnes), poussière (› Poussière ; série : Copier puis Coller de Lightroom), suppression générative, correction de champ plat, \
    fusions HDR et panorama.
    """
}
