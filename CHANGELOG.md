# Changements

## Non publié

La 1.3 : apprendre en regardant Claude. Claude dit pourquoi il fait chaque étape et en garde
l'avant/après, finit une retouche par la leçon de la photo (ce qui manquait, et ce qui l'aurait
évité à la prise de vue), vous laisse faire la retouche vous-même avec sa liste de réglages puis
compare vos deux versions, lit la composition et propose un cadre, et tient un carnet de progrès
de vos prises de vue, mois par mois. La fenêtre Claude prend l'allure de la maquette « B ·
Conversation claire », agrandie à votre demande à 1 948 × 1 200 points, en apparence claire ou
sombre. Après l'installation : quitter et relancer Lightroom (le module a deux fichiers nouveaux,
`Etapes.lua` et `Carnet.lua` : recharger le module ne suffit pas), rouvrir Claude Desktop (à
quitter pendant l'installation) et ouvrir une nouvelle session de Claude Code, pour avoir les 36
outils.
La fenêtre B n'a pas encore été vue dans Lightroom : ses tailles viennent de la maquette et de
constats faits le 21 octobre 2026 sur une fenêtre d'essai. La capture du README
(`docs/capture.png`) montre encore la fenêtre de la 1.2 ; elle sera refaite.

### Ajouté
- « Pourquoi ? » sur chaque étape : dans le fil de la fenêtre Claude, chaque étape de Claude a un
  bouton « Pourquoi ? ». Il ouvre l'onglet Aperçu sur cette étape : son avant/après dans l'aperçu
  (Voir l'avant, Voir l'après), la raison que Claude a donnée, les réglages changés, ◀ ▶ pour
  passer d'une étape à l'autre de la même photo, Détail… pour son appel au connecteur, et Agrandir
  pour l'avant et l'après côte à côte. Les images se gardent pendant le travail de Claude, sans
  rien écrire dans le catalogue (un rendu de plus par étape, environ une seconde, pendant que
  Claude écrit son appel suivant), dans `~/Library/Application Support/Developpeur/Etapes/` ; le
  module y fait le ménage à son chargement (30 jours, 500 Mo au plus). Pas d'avant/après pour une
  étape faite par Claude Desktop ou Claude Code pendant que la fenêtre est fermée, sur plusieurs
  photos ou sur une autre photo que la photo active, ni pour un classement. Case « Avant/après »
  du Gestionnaire de modules externes (section Fenêtre Claude), cochée par défaut. Chaque retouche
  demande à Claude une raison simple : le défaut vu, puis ce que l'étape y fait ; elle reste au
  journal (`export_journal`).
- La leçon de la photo : à la fin d'une retouche, Claude range la leçon de la photo
  (`photo_lesson`) en trois points, Lumière, Couleur et Composition : ce qui manquait, chiffres à
  l'appui, et ce qui l'aurait évité à la prise de vue (ou, si rien ne manquait, ce qu'il faut
  refaire). Elle se lit dans l'onglet Leçon de la fenêtre Claude (la fenêtre y passe une fois à son
  arrivée, pas quand une proposition attend ou qu'un exercice est en cours), ou par « Leçon de la
  photo » à la fin du tour de Claude dans le fil ; Détail… montre les faits mesurés. Le connecteur
  vérifie les trois points avant de les ranger, et donne à Claude les faits : la prise de vue
  (compensation, flash, mode et mesure d'exposition, lus en français dans Lightroom), ses propres
  corrections nettes (d'après son journal) et des indices à seuils provisoires. Une leçon par photo
  et par conversation ; pas de leçon après une proposition seulement montrée, une notation, un
  classement ou une série. Case « Leçon » du Gestionnaire de modules externes, cochée par défaut ;
  dans Claude Desktop, les invites qui retouchent finissent par la leçon.
- « Je le fais » : vous faites la retouche vous-même, pour apprendre. Le bouton Je le fais (carte
  Proposition, ou le Mode « Je le fais » en tête de la fenêtre) demande à Claude sa liste de
  réglages dans l'ordre des panneaux du module Développement, sous leurs noms de Lightroom Classic
  15.6 en français (« Réglages de base › Tonalité › Exposition : 0 → +0,35 », Color Grading,
  Etalonnage, Flou de l'objectif après Transformation, le noir et blanc dans le Mélangeur de
  couleurs, « Outil Recadrage »). Rien n'est appliqué : sa version est rangée dans l'instantané
  « Claude · ma version ». La liste se coche toute seule, toutes les 2 secondes, à mesure que vous
  réglez la photo (« À vous · 3 réglages faits sur 7 ») ; vous pouvez regarder d'autres photos
  pendant l'exercice. J'ai fini : Claude compare les deux versions côte à côte (« Claude | vous »
  dans l'aperçu ; Agrandir en grand), d'abord ce qui est comme lui, puis l'écart qui se voit le
  plus, ramené aux seuils du bilan, et le réglage qui l'explique. Sa version ne se pose sur la
  photo que si vous le demandez (`choose_variant`), et `undo_last` vous rend la vôtre. Dans Claude
  Desktop : `preview_settings` avec `my_turn`, puis `view_photo` avec `compare = claude_version`.
- La composition lue : Claude lit la composition sur l'image entière, même recadrée
  (`read_composition` : horizon, tiers, sujet, regard des visages, espace devant le sujet) et
  propose un cadre : horizon droit et sur un tiers, sujet sur un tiers avec de l'espace devant lui,
  la règle dite en une phrase. La proposition montre l'image entière, le cadre en pointillés, les
  tiers et le hors-cadre assombri ; rien ne change avant Accepter. Ajuster… offre alors Plus
  serré, Plus large, Horizon au tiers haut, Format 4:5 et Seulement redresser. Une invite
  « Composition » s'ajoute aux raccourcis de la fenêtre (avant Sports). Sur une photo recadrée, la
  lecture passe par deux étapes « Claude · composition » dans l'Historique (le cadre retiré le
  temps du rendu, puis remis tel quel), et la proposition par une étape « Claude · essai : image
  entière ». Un « visage » que Vision voit à l'envers (l'avant d'une voiture, sur une photo
  d'essai) et une zone d'intérêt qui couvre plus de la moitié de l'image ne sont pas pris pour le
  sujet. `view_photo` dit aussi vers où regarde chaque visage.
- Le carnet de progrès : les défauts de vos prises de vue (horizon penché, sous-exposition, ciel
  brûlé, flou, mise au point manquée, bruit fort), notés tout seuls quand Claude regarde une photo
  pas encore retouchée, ou mesure une ligne penchée, et comptés par mois de prise de vue. La
  fenêtre Claude le montre en tête de la liste des conversations : un tableau des six derniers mois
  (« 2/9 » : 2 photos sur les 9 où le défaut a été cherché), ce qui progresse ou recule (deux mois
  contre les trois d'avant, 15 points d'écart, assez de photos de chaque côté) et quoi travailler
  à la prochaine sortie, avec un conseil pour la prise de vue. Un clic sur une ligne ouvre ses
  photos, leurs constats et leurs leçons, avec « Retirer du carnet… » ; « Demander à Claude ce
  qu'il en pense › » ouvre une conversation où Claude le lit, sans rien retoucher. `export_journal`
  (« Journal et carnet de progrès ») le rend en Markdown avec `notebook`. Rangé dans
  `~/Library/Application Support/Developpeur/carnet.json`, à part du catalogue : une entrée par
  photo originale (ses copies virtuelles comprises), une table par catalogue. Les photos de
  « Développeur › Essais » n'y entrent pas. Case « Carnet » du Gestionnaire de modules externes
  (section Liaison avec Claude), cochée par défaut : décochée, plus aucun défaut n'est noté ; les
  leçons, elles, se rangent encore dans ce fichier (c'est la case Leçon qui les coupe, dans la
  fenêtre). Seuils de la sous-exposition et du ciel brûlé provisoires : aucun vrai cas parmi les
  photos d'essai.
- L'apparence claire ou sombre de la fenêtre Claude, au choix dans le Gestionnaire de modules
  externes (section Fenêtre Claude, menu Apparence), à son ouverture suivante. Elle règle les fonds,
  les textes et les images de la fenêtre ; les boutons, champs et menus suivent l'apparence de
  macOS.

### Changé
- La fenêtre Claude, à l'allure de la maquette « B · Conversation claire », agrandie à
  1 948 × 1 200 points (le volet des conversations, le centre, la colonne de droite et la hauteur
  plus grands que dans la maquette : environ 1 490 points laissés à Lightroom sur votre écran de
  3 440 × 1 440) :
  - à gauche, le volet : « ＋ Nouvelle conversation », Rechercher, la liste par jour (Aujourd'hui,
    Hier…) avec l'heure et le nombre de photos de chaque conversation, page par page (« Plus
    anciennes… » en bas, « Plus récentes… » en haut), le Carnet de progrès en tête ; en bas,
    Renommer… et Supprimer…, Publication… et Consommation…, les versions et le voyant Écran ;
  - au centre, l'en-tête : le titre, le Mode en trois boutons radio (Appliquer, Proposer d'abord,
    Je le fais ; grisés pendant que Claude travaille), les voyants Claude Code et Lightroom, et la
    photo active avec la sélection ; le fil de 42 lignes, chaque tour marqué « Vous » ou « Claude »
    avec son heure, les outils nommés en Menlo ; ▲ ▼ Fin, avec ce que fait Claude ou le relevé du
    forfait ; puis les invites, le champ de demande, 📎, 📋, « Style » et son menu, le bandeau des
    messages sur deux lignes, et Envoyer, un bouton bleu (Retour dans le champ envoie aussi) ;
  - à droite, les onglets Aperçu, Proposition, Note et Leçon, l'aperçu de 498 × 332 commun aux
    quatre, ◀ légende ▶ et ⤢ Agrandir, puis la carte de l'onglet, jusqu'en bas du panneau, avec
    ses boutons sous elle (▲ ▼ à gauche) dans chacun des quatre onglets. La légende de la
    photo active dit son nom, son appareil et sa date.
- La carte Note : les passes du standard, vos étoiles et vos drapeaux cliquables (posés dans
  Lightroom sans Claude ni forfait ; un clic sur la note posée la retire ; 5 ★ restent à vous),
  la note que Claude propose en petites étoiles, ses critères en grille, le plafond mesuré au tri
  et « Voir à 100 % », qui montre dans l'aperçu le zoom que Claude a pris pour noter (grisé sans
  zoom). En bas : Laisser à N ★ (la proposition écartée, rien n'est écrit dans Lightroom),
  Changer… et Accepter N ★, jamais Accepter 5 ★. « ? À vérifier » est posé, grisé.
- La carte Proposition et la carte de l'étape (onglet Aperçu) sur leurs fonds ; Accepter en bleu,
  Refuser, Ajuster… et Je le fais (J'ai fini pendant l'exercice) à côté. Les messages de la fenêtre
  sont plus courts, pour tenir sur les deux lignes du bandeau ; l'infobulle donne le texte entier.
- Le connecteur passe à 36 outils, avec `read_composition` (« Lire la composition ») et
  `photo_lesson` (« Leçon de la photo »), qui ne changent pas vos photos : la leçon va dans le
  carnet de progrès, à part du catalogue, et la lecture d'une photo recadrée ne laisse que ses deux
  étapes « Claude · composition » dans l'Historique. `export_journal` s'appelle « Journal et carnet
  de progrès ». Les invites `retouche_pro`, `portrait` et `paysage` lisent la composition avant de
  recadrer, et celles qui retouchent finissent par la leçon.
- `uninstall.sh` garde le carnet de progrès (`carnet.json`, leçons comprises) et l'avant/après des
  étapes (`Etapes/`) ; `uninstall.sh --tout` les retire avec le reste.

### Retiré
- Le voyant Mode : le mode se choisit par les boutons radio de l'en-tête. Les voyants Claude Code
  et Lightroom sont dans l'en-tête, Écran en bas du volet.
- Les onglets en boutons radio de la 1.2 (Note et Proposition) : quatre onglets en tête de la
  colonne de droite, Note par défaut.

### Corrigé
- La photo active revient après un passage par le module Développement (débruitage, suppression
  des reflets, variante choisie, et leur annulation) et après une copie virtuelle : le module
  remet la source et la sélection d'avant, le temps que Lightroom les affiche (constaté le
  21 octobre 2026 : une autre photo restait active).
- La mise au point ne se juge plus sur une zone sans détail : posée sur du sable lisse ou un ciel
  uni, elle est « non jugée » ; sur une texture faible (le bord d'un nuage), une mise au point
  manquée n'est plus qu'un doute : 2 ★ au plus, à vérifier par un zoom à 100 %, sans rejet
  proposé, et le carnet ne la compte pas. Constaté le 21 octobre 2026 sur deux photos d'essai
  nettes, que le tri proposait à tort de rejeter. Revers connu : un petit visage vraiment flou
  passe lui aussi pour un doute.
- Une ligne mesurée sur un contour irrégulier (les rides du sable) ne se dit plus « affinée » :
  `measure_angle` et `read_composition` le disent, et l'angle vient des deux points donnés.
- `export_journal` montre maintenant les réglages d'une variante choisie (`choose_variant`) : son
  entrée de journal s'écrivait avant la pose, sans ses changements.

## 1.2 — 2026-10-21

Un rendu plus juste sur chaque photo. Claude lit ce que vous avez choisi au boîtier (fichiers
Fujifilm), nomme un éclairage mixte, chiffre d'une passe à l'autre ce que sa retouche a changé et
signale ce qu'elle a abîmé, dose la peau comme Adobe, éclaircit et assombrit comme un tireur pour
mener l'œil au sujet, et sait sur quel écran vous jugez la photo. La liaison entre le connecteur et
Lightroom est fermée par un jeton privé. La fenêtre Claude n'a plus qu'une disposition, la
Conversation claire ; l'aperçu de la photo active y montre son point de mise au point (Fujifilm),
et Claude y prépare une proposition de retouche dès l'ouverture. Après l'installation, relancer
Lightroom et Claude Desktop, et ouvrir une nouvelle session de Claude Code : un connecteur d'avant
la 1.2 resté ouvert est refusé par la liaison, avec un message qui le dit.

### Ajouté
- L'intention de la prise de vue, pour les fichiers Fujifilm (RAF ou JPEG de l'appareil, pas un
  HEIF) : `view_photo` lit dans l'original, d'une seule ouverture avec le point de mise au point et
  en temps limité, les réglages choisis sur l'appareil (`intention_boitier`) : simulation de film
  (ACROS, MONOCHROME et Sépia compris), réglage Couleur, plage dynamique (DR100, DR200, DR400…,
  auto ou réglée) et sa priorité, tons clairs et foncés, compensation et mode d'exposition, balance
  automatique et scène de nuit ; pour un RAW, aussi le profil de Lightroom qui rend cette
  simulation sur cet appareil. Sa « lecture » guide Claude, sans rien poser d'office : un RAW part
  de la simulation choisie (proposée en première passe, et dite, sauf autre style demandé), un JPEG
  de l'appareil ne se voit pas refaire ce qu'il porte déjà, une photo prise avec une compensation
  de −2/3 IL ou moins (seuil provisoire), ou en scène de nuit, reste sombre, et des hautes lumières
  protégées au boîtier (DR200, DR400) le restent quand l'exposition remonte. Sur l'aperçu entier
  seulement, ni sur un zoom ni sur un avant/après. Lu le 20 octobre 2026 sur de vrais RAF (X-H2S,
  X-T4, X-T20) et recoupé avec la MakerNote lue à la main : tout concorde.
- L'éclairage mixte nommé : `view_photo` mesure la dominante des tons presque neutres par zone
  tonale (ombres, tons moyens, hautes lumières) et par région (grille de 3 × 3), les visages à part
  (leur peau, et la lumière autour d'eux) : `mesures › eclairage`. Quand deux lumières de couleurs
  différentes se mêlent (une lampe et une fenêtre dans la même pièce), la mesure nomme les deux
  lumières et leurs zones (« plus chaude tiers gauche… »), donne leur écart, une balance des blancs
  proposée pour la lumière des visages (ou du sujet) et le conseil : la balance sur les visages,
  l'autre zone par un masque (Température et Teinte locales), ou gardée chaude si c'est une lampe.
  Claude vous le dit, à confirmer à l'œil (un mur coloré n'est pas une lumière). Une forme courte
  (lecture, écart, zones tonales) va dans l'avant/après et les propositions ; `analyze_photos` en
  donne la lecture et l'écart. Seuil relevé le 20 octobre 2026 sur les huit photos d'essai, à la
  balance de chacune : seul le portrait éclairé par des fenêtres et une lumière chaude ressort
  mixte (écart 9,7 pour un seuil de 8), les sept autres restent entre 2,1 et 7,1. Sous une forte
  dominante ajoutée exprès (balance à 3 200 K sur ce portrait, Température +30 sur un intérieur à
  la lampe), la mesure peut perdre une lumière ou en inventer une.
- Un bilan chiffré d'une passe à l'autre : à chaque nouveau `view_photo` d'une photo (aperçu
  entier, à la même taille), Claude voit ce qui a bougé depuis le précédent, avant → après
  (exposition en IL, contraste, écrêtage, ombres bouchées, dominante sur les mêmes tons neutres,
  couleurs très saturées, netteté, bruit), et depuis le premier de la session. Une « regression »
  signale un défaut que la passe a créé ou aggravé : hautes lumières ou un canal écrêtés, ou
  couleurs très saturées (2 points de plus, et au moins 1,5 fois l'avant), ombres bouchées
  (2 points de plus), dominante des tons neutres qui s'éloigne du neutre d'au moins 2 en a* ou b*,
  netteté ou bruit passés leur seuil ; Claude la corrige par une passe ciblée ou la défait
  (`undo_last`), et vous le dit. Ce qui peut être voulu n'est qu'« à vérifier » (dominante passée
  de l'autre côté, coins vides après un Upright, netteté en baisse après un débruitage, calculs IA
  en attente), et une annulation n'est jamais une régression. L'avant/après de `view_photo`
  (`compare`) a son propre bilan, et une proposition montrée à côté de l'état actuel
  (`preview_settings`, ou `add_mask` avec `preview`, et `compare`) le sien, sans netteté ni bruit ;
  un zoom refait sur la même zone, le sien (`bilan_zone`, sans alerte). Le résumé de fin de
  retouche reprend ces chiffres (« hautes lumières écrêtées : 2,1 → 0,3 % »). La mémoire dure le
  temps de la session du connecteur. Seuils de régression de l'écrêtage, des ombres, des couleurs
  saturées et de la dominante relevés le 20 octobre 2026 en propositions sur les photos d'essai, où
  deux vues de suite à la même taille donnent les mêmes chiffres ; ceux de la netteté et du bruit
  restent provisoires.
- L'effet « Peau du visage lisse » (texture −20, clarté −10 : les valeurs d'un paramètre prédéfini
  adaptatif du groupe Portrait de Lightroom) parmi les effets d'`add_mask`, et « Adoucir la peau
  (Lite) » (texture −35, clarté −15) même si son fichier manque. Avec un garde-fou : `add_mask`
  refuse, sans rien envoyer à Lightroom (proposition comprise), un masque de la peau (`face_skin`,
  `body_skin`) qui lisse plus qu'« Adoucir la peau (Lite) », intensité comprise, ou qui baisse la
  netteté, sauf si vous avez demandé une peau plus lisse ou que votre guide de style le dit
  (`smoothing_requested`) : Claude ne lisse plus davantage de lui-même. Ses remarques disent la
  dose posée sous 100 % d'intensité.
- Éclaircir et assombrir comme un tireur en chambre noire, pour mener l'œil au sujet : les invites
  `portrait` et `paysage` finissent par cette étape, `noir_et_blanc` la fait avant le grain, et les
  boutons Portrait, Paysage et Noir et blanc de la fenêtre Claude la demandent. Un seul `add_mask`
  (« Claude · éclaircir et assombrir » dans l'Historique, que `undo_last` défait) : grandes zones
  trop claires assombries par un dégradé linéaire (−0,3 à −0,7 IL), sujet ou visage éclairci par
  un dégradé radial (+0,2 à +0,4 IL), bords assombris par un radial inversé (−0,3 IL, −0,5 au
  plus ; rayon 0,7 et fondu 80, au milieu de la zone d'intérêt de Vision) à la place du vignetage
  après recadrage, jamais les deux. Ces doses sont des plafonds. Suit un avant/après de cette seule
  étape (`view_photo` avec `compare = previous_step`) : s'il y voit un halo, une bande ou une
  plaque sombre aux coins, Claude défait l'étape et la refait plus légère. En mode « Proposer
  d'abord », il la montre d'abord en proposition. La méthode est aussi dans la description
  d'`add_mask`, que Claude lit partout. Constaté le 20 octobre 2026 : le radial inversé
  n'assombrit que hors de son ellipse (à −2 IL sur un portrait d'essai, coins −31 à −69 niveaux
  sur 255, centre −0,3). La forme des bords, relevée le même jour sur un paysage, radial centré
  (tiers central intact, baisse sans marche jusqu'aux coins), est constatée le 21 octobre 2026 sur
  un portrait d'essai pris à l'intérieur, centrée sur sa zone d'intérêt : à −0,3 IL, la luminance
  baisse de 0,5 % au centre, 9,1 % au milieu des bords et 8,5 % aux coins, sans marche de plus de
  1,6 %. Le fondu du radial du sujet reste à vérifier.
- L'écran nommé : un quatrième voyant dans la fenêtre Claude, lu à l'ouverture,
  « Écran · étalonné » (vert), « Écran · non étalonné » (orange) ou « Écran · étalonné ? » (gris,
  dans le doute), et « Écran » en gris s'il n'a pas pu être lu. Un clic le relit et donne le
  détail : l'écran principal du Mac, son profil de couleur (d'usine, standard du système, fait à
  l'œil avec l'assistant d'Apple, mesuré par une sonde, ou personnalisé) et, sauf pour un profil de
  sonde, comment juger les couleurs (couper Night Shift, et True Tone sur un écran Apple ; où
  choisir le profil dans les Réglages système). « Étalonné » veut dire mesuré par une sonde ; la
  reconnaissance d'un vrai profil de sonde reste à constater (seul un profil d'usine a été lu
  jusqu'ici). `get_status` et `mcp-developpeur --status` disent aussi l'écran. Claude mesure la
  photo par ses chiffres, sans passer par l'écran ; s'il n'est pas étalonné, il vous le dit une
  fois, quand votre avis compte (peau, couleurs). L'écran se lit sur le Mac (ColorSync), sans
  réseau ni permission ; Claude en reçoit le nom et celui du profil, jamais le chemin du fichier
  du profil.
- Le carré de mise au point sur l'aperçu de la photo active (« Photo active · … »), pour un
  fichier Fujifilm : à l'ouverture de la fenêtre Claude (menu Ouvrir la fenêtre Claude ou ⌃⌥C,
  même déjà ouverte) et quand vous choisissez une autre photo, le connecteur lit le point dans
  l'original, en temps limité, et le dessine sur la vignette : un carré vert, rouge si l'appareil
  a signalé la mise au point manquée. Agrandir montre la vignette avec son carré. L'original d'une
  autre marque n'est pas ouvert ; sans point lu à temps, ou hors du cadre, l'aperçu reste sans
  carré.
- Une proposition de retouche prête à l'ouverture : sur une conversation vide (une autre photo en
  commence une), quand la fenêtre Claude s'ouvre ou que le menu ou ⌃⌥C la rappelle, Claude note
  d'abord la photo active si elle n'est pas encore évaluée, puis montre ce qu'il changerait, au
  rendu naturel (`preview_settings`), sans rien appliquer. La proposition attend dans l'onglet
  Proposition, sans que la fenêtre y bascule : vous l'acceptez, la refusez ou l'ajustez quand vous
  voulez. Case « À l'ouverture » du Gestionnaire de modules externes (section Fenêtre Claude,
  « Claude prépare une proposition de retouche (rien n'est appliqué) »), cochée par défaut.
- Le point de mise au point sur un zoom de `view_photo` (`region`), pour les fichiers Fujifilm : sa
  place dans l'image entière et s'il tombe dans la zone (`dans_la_zone`) ; s'il y tombe, la
  netteté autour du point dans le zoom et, avec `af_point` (ou la case « Mise au point » du
  Gestionnaire de modules externes), le carré dessiné sur le zoom. Toujours pas sur un avant/après
  (`compare`). Dans la fenêtre Claude, Claude fait dessiner le carré quand il montre ou juge la
  mise au point, sur l'aperçu entier comme sur un zoom.
- La liaison locale fermée par un jeton privé : à chaque démarrage de la liaison, le module tire un
  jeton au hasard et le range dans `~/Library/Application Support/Developpeur/liaison.jeton`,
  lisible par vous seul ; le connecteur le joint à chaque commande, pour Claude Desktop, Claude
  Code et la fenêtre Claude. Une commande sans ce jeton, ou avec un autre, venue d'un autre
  programme du Mac ou d'une page web, est refusée avant tout (« Liaison fermée : … », constaté le
  21 octobre 2026 dans Lightroom) et notée au journal du module, sans l'inonder : elle ne peut ni
  regarder, ni retoucher, ni passer outre la pause ou « Proposer d'abord ». Le jeton protège de ce
  qui ne peut pas lire vos fichiers ; un programme qui tourne sous votre compte le pourrait. Le
  diagnostic du Gestionnaire de modules externes dit si le jeton est là et combien de commandes ont
  été refusées, `--status` dit l'état de son fichier (jamais sa valeur), et la fenêtre Claude a sa
  propre aide si la liaison n'a pas pu le préparer. `uninstall.sh` retire le fichier, Lightroom
  fermé (ouvert, il le réécrit).

### Changé
- La peau dosée comme Adobe : par défaut « Peau du visage lisse » ; « Adoucir la peau (Lite) » pour
  un gros plan aux pores marqués ; la moitié de la dose (`amount` 50) pour un homme ou une personne
  âgée ; rien pour un enfant ; un masque par personne quand les doses diffèrent, puis un zoom sur
  le visage (pores encore visibles, ni cire ni plaques). Vision ne dit ni l'âge ni le genre d'un
  visage : Claude juge à l'œil et, dans le doute, prend la dose la plus faible. Constaté le
  20 octobre 2026 : l'intensité d'un masque est linéaire (à 50, la même image, au pixel près, que
  les curseurs à moitié). Dans la fenêtre Claude, la peau adoucie des styles « … et peau douce »
  (Or, Éclatant, Rose froid) est la dose « Adoucir la peau (Lite) », sur la peau seulement, la
  moitié pour un homme ou une personne âgée, rien pour un enfant.
- `paysage` n'a plus de « vignetage léger » : le radial inversé des bords le remplace, jamais les
  deux, et `retouche_pro` comme les consignes du connecteur le disent. Dans `noir_et_blanc`,
  éclaircir et assombrir devient une étape à part, et le grain vient après.
- Les invites suivent ce qui est nouveau : `retouche_pro`, `portrait`, `paysage`, `noir_et_blanc`
  et `nuit_iso_eleve` partent de l'intention du boîtier (Fujifilm), comme les consignes du
  connecteur (RAW Fujifilm : d'abord la simulation du boîtier) ; `retouche_pro`, `portrait` et
  `nuit_iso_eleve` traitent l'éclairage mixte ; une « regression » au bilan appelle une passe
  corrective, et le résumé de fin donne les chiffres du bilan, dans les invites comme dans la
  fenêtre Claude.
- L'avant/après de `view_photo` et les propositions (`preview_settings`, `add_mask` avec `preview`)
  sont mesurés comme l'aperçu entier (même réduction de l'image), avec la forme courte de
  l'éclairage.
- La fenêtre Claude n'a plus qu'une disposition, la Conversation claire : à gauche les
  conversations, au centre le fil, à droite les onglets Note et Proposition, l'aperçu, puis la
  carte Note ou la Proposition. Si vous aviez choisi l'Atelier ou le Panneau, elle s'ouvre
  maintenant en Conversation claire ; la taille déjà enregistrée en Conversation claire sert
  encore.

### Retiré
- L'Atelier et le Panneau, avec ce qui ne servait qu'à eux : le menu des conversations (la liste
  de la Conversation claire reste) et les onglets Retoucher et Noter du Panneau.
- Le menu Disposition du Gestionnaire de modules externes, et la réouverture de la fenêtre quand
  la disposition y changeait.

### Corrigé
- Le masque d'une personne précise (`add_mask`, `kind: "person"`) sur une photo où elle est seule,
  un portrait par exemple : Lightroom le calculait bien, mais le module le retirait aussitôt comme
  « personne non reconnue ». Il est maintenant fait comme à la main dans Lightroom, et gardé ; la
  peau, les yeux ou les cheveux de cette personne aussi.
- Une commande reçue par la liaison ne peut plus se dire venue de Lightroom même
  (`depuisLightroom`) pour lever la pause ou l'accord demandé dans Lightroom : ce drapeau ne vient
  plus du réseau.

## 1.1.1 — 2026-10-20

Une fenêtre Claude plus légère : le modèle, l'effort et la disposition se choisissent dans le
Gestionnaire de modules externes, une autre photo commence une nouvelle conversation, Claude note
d'abord chaque photo qu'il traite (sa note arrive « à vérifier », vous l'acceptez ou la changez),
et la Séance de notation est retirée.

### Ajouté
- Fable, le modèle le plus capable, avec Opus (par défaut), Sonnet et Haiku.
- L'effort de Claude : maximal (par défaut), très élevé, élevé, moyen ou faible, le même pour les
  quatre modèles. Modèle et effort se choisissent dans Fichier › Gestionnaire de modules externes ›
  Développeur, section Fenêtre Claude ; un autre choix vaut pour la demande suivante, et la
  conversation continue.
- Une nouvelle conversation quand vous choisissez une autre photo active ou une autre sélection,
  si la conversation montrée a déjà des messages et parlait d'autres photos. Une sélection qui
  change pendant que Claude travaille, ou jusqu'à quatre secondes après (photo montrée par Claude,
  tri), devient celle de la conversation, et une fenêtre fermée pendant qu'il travaillait retrouve
  sa conversation à la réouverture ; une conversation vide reste ; une photo choisie fenêtre
  fermée compte aussi, à la réouverture. Case « Autre photo » du Gestionnaire de modules externes,
  cochée par défaut.
- Dans la fenêtre Claude, Claude note d'abord toute photo qu'il traite, avant d'y toucher : son
  plancher technique (`cull_photos`), la photo avec son point de mise au point (`view_photo`), puis
  sa note selon le standard (`propose_ratings`). Sa note arrive « à vérifier » dans la carte Note :
  vous l'acceptez ou la changez. Une photo déjà évaluée ne se renote pas, sauf si vous le
  demandez : `view_photo` dit où en est son évaluation (« pas encore évaluée », « 3 ★ proposée par
  Claude, à vérifier », « acceptée par l'utilisateur : 3 ★ »…).
- Le point de mise au point dans `view_photo`, pour les fichiers Fujifilm (lu dans l'original,
  comme au tri), sur l'aperçu entier (pas un zoom ni un avant/après) : sa place dans l'image, la
  netteté autour, et si l'appareil a signalé la mise au point manquée. Pour noter, Claude le fait
  dessiner sur l'image : un carré vert, rouge si l'appareil a signalé la mise au point manquée ;
  les mesures sont prises avant le carré. Case « Mise au point » du Gestionnaire de modules
  externes (section Liaison avec Claude, décochée par défaut, « Montrer le carré de mise au point
  (Fujifilm) sur chaque aperçu ») : le carré sur chaque aperçu.
- À l'ouverture de la fenêtre Claude (menu Ouvrir la fenêtre Claude ou ⌃⌥C, même déjà ouverte),
  l'aperçu montre la photo sélectionnée dans Lightroom (« Photo active · … »), sa vignette tirée
  du cache d'aperçus de Lightroom ; de même quand vous choisissez une autre photo. Une image que
  Claude regarde ensuite prend sa place ; ◀ revient aux images de la conversation, ▶ depuis la
  dernière revient à la photo active, et Agrandir la montre en grand.
- ▲ ▼ à droite des boutons de la carte Note (Accepter, Changer…) et de la Proposition (Accepter,
  Refuser, Ajuster…) : un texte plus long que la carte défile page par page ; un nouveau texte
  revient à la première page.
- Claude pose les notes quand vous le lui demandez (« note ces photos », « pose les notes ») :
  `propose_ratings` avec `apply` les range et les pose comme Accepter, une étape « Claude ·
  notation » par photo, que `undo_last` défait. La pause de la liaison l'arrête ; les garde-fous
  des photos (copies virtuelles seulement, libellé protégé, photos rejetées) restent ; en mode
  « Proposer d'abord » avec l'accord donné dans Lightroom (case Accord), la pose attend votre
  Accepter dans la fenêtre de suivi, puis Claude la refait. Le fil dit « Notes à poser » pendant
  l'appel, puis « Notes posées » et « posée » pour chaque photo, ou « Notes non posées » avec la
  raison sur chaque ligne.

### Changé
- La barre de titre de la fenêtre Claude dit « Développeur ». Les autres fenêtres gardent
  « Claude · … », et le menu reste Ouvrir la fenêtre Claude (⌃⌥C).
- Le modèle ne se choisit plus dans la fenêtre, mais dans le Gestionnaire de modules externes,
  avec l'effort.
- La disposition de la fenêtre : dans le Gestionnaire de modules externes seulement. Une fenêtre
  ouverte se rouvre d'elle-même dans les deux secondes quand elle change, la demande tapée gardée
  (changée dans le Gestionnaire, elle attendait jusqu'ici la prochaine ouverture).
- Conversation claire : à droite, de haut en bas, les boutons Note (par défaut) et Proposition,
  l'aperçu, toujours montré, avec ◀ ▶ et Agrandir dessous, puis la carte Note ou la
  Proposition ; en bas, Publication… et Consommation…, au-dessus des versions. Une proposition qui
  arrive montre la Proposition, une note proposée pour la photo active la carte Note ; un clic sur
  une image du fil la montre dans l'aperçu, sans changer d'onglet. Le fil a 42 lignes (au lieu de
  30 dans la taille moyenne de la 1.1, celle par défaut, ou 40 dans la grande), et Envoyer est
  seul à droite du champ de demande.
- Atelier : Publication… et Consommation… en bas de la colonne Note, au-dessus des versions ;
  Envoyer seul sous le champ, à droite.
- Panneau : Envoyer seul sous le champ, à droite ; en bas, Publication… et Consommation…, puis les
  versions.
- Le menu Style, sans étiquette, est au bout de la dernière rangée d'invites, dans les trois
  dispositions. Dessous, sur sa propre ligne dans chacune, le bandeau montre un message, l'aide
  d'un voyant rouge ou les photos jointes, sinon rien.
- Toute note que Claude propose arrive « à vérifier » (en rouge dans la carte Note), plus
  seulement les cas douteux. La carte Note n'a plus que Accepter et Changer…, et montre un seul
  texte : les critères, le plafond mesuré, puis la raison. Après une annulation (`undo_last`, ⌘Z),
  une note acceptée ou changée qui n'est plus posée redevient « à vérifier » (elle redevenait à
  décider).
- 5 ★ : Claude ne les propose jamais de lui-même ; si vous lui en demandez, il les pose
  (`set_metadata`).
- Claude fait ce que vous lui demandez clairement : il ne refuse que ce que ses outils ne savent
  pas faire, ou ce que bloquent les réglages du module (« Proposer d'abord », garde-fous), et il le
  dit.
- `propose_ratings` s'appelle « Noter des photos » et n'est plus en lecture seule (avec `apply`, il
  écrit dans le catalogue) ; ses propositions arrivent « à vérifier ». Sans précision, l'invite
  `noter` vise la sélection.

### Retiré
- La Séance de notation : sa fenêtre, l'entrée Séance de notation… des menus Fichier et
  Bibliothèque (Module externe - Extras), et les boutons Séance… de la carte Note et de l'Atelier.
  Les séances rangées dans `notation.json` disparaissent à la première lecture du fichier, les
  notes proposées restent ; les conversations des anciennes séances restent sur le disque, mais
  ne se montrent ni ne s'ouvrent plus.
- Les boutons Noter (invites de la Conversation claire, carte Note, barre de l'Atelier) et
  À vérifier (carte Note) : Claude note de lui-même chaque photo qu'il traite, et chaque note
  arrive déjà « à vérifier ». L'onglet Noter du Panneau reste : c'est la carte Note.
- Le choix de la taille de la fenêtre (Petite, Moyenne, Grande) dans le Gestionnaire de modules
  externes : la fenêtre a toujours la grande taille, et un cadre déjà enregistré en grande sert
  encore.
- Le menu Disposition de la fenêtre Claude.
- L'onglet Aperçu de la Conversation claire et son titre « Ce que Claude voit » : l'aperçu est
  toujours montré.
- L'étiquette « Style » du menu Style, et le rappel « ajouté à chaque demande, invites
  comprises » du bandeau (l'infobulle du menu le dit).
- Les paramètres `session` et `read_session` de `propose_ratings`, et le champ `seance` de sa
  réponse (`pass` reste : la passe du standard).

### Corrigé
- Le texte de la carte Note et du fil ne coupe plus une ligne avant une ponctuation haute : une
  ligne ne commence plus par « ; », « : », « ! », « ? » ou « », et « « » reste avec le mot qui le
  suit.
- Au tri (`cull_photos`), quand l'ouverture d'un original attend (demande d'autorisation de macOS
  pour le volume), les points de mise au point des photos suivantes ne sont plus sautés jusqu'à
  la fin du tri : la lecture reprend dès que cette ouverture aboutit.

## 1.1 — 2026-10-20

Le nouvel écran et la notation : la fenêtre Claude en trois dispositions, et des notes que Claude
propose selon un standard clair, que vous acceptez ou changez dans Lightroom.

### Ajouté
- Trois dispositions de la fenêtre Claude : Conversation claire (par défaut, la plus proche de la
  1.0, avec à droite les onglets Aperçu, Proposition et Note), Atelier (la photo en grand, la carte
  Note à côté, la conversation dans une colonne étroite) et Panneau (une fenêtre étroite et haute,
  onglets Retoucher et Noter). Au choix dans Fichier › Gestionnaire de modules externes ›
  Développeur, ou par le menu Disposition de la fenêtre, qui la rouvre aussitôt, la demande tapée
  gardée.
- La carte Note, dans chaque disposition : la note posée de la photo active, la note que Claude
  propose avec sa raison critère par critère (Impact, Qualités, Plancher technique, Finition) et le
  plafond mesuré au tri ; Noter, Accepter, Changer… (de 0 à 5 ★, et le drapeau), À vérifier et
  Séance….
- La Séance de notation, une fenêtre à part (Séance de notation… dans le menu du module, Séance…
  dans la carte Note, ou Noter avec plusieurs photos sélectionnées) : la sélection ou une
  collection, les quatre passes du standard (rejets, trois étoiles, quatre étoiles, cinq étoiles ;
  la quatrième est à vous seul et ne se lance pas), une planche de douze vignettes par page, la
  fiche de la photo choisie, Tout accepter, un filtre et un échange avec Claude dans une
  conversation propre à la séance.
- Le standard de notation : ce que veut dire chaque note, du rejet à 5 ★, les critères du plus
  lourd au plus léger, les plafonds et une question par passe. Le texte entier est la ressource
  `developpeur://notation` du connecteur.
- L'outil `propose_ratings` (34 outils) : Claude propose des notes de 0 à 4 ★, ou le rejet, avec
  une raison par critère, sans rien changer sur les photos. Jamais 5 ★ : vous seul les posez. Une
  note au-dessus du plafond mesuré au tri est refusée, sauf un défaut voulu et maîtrisé, laissé « à
  vérifier ». Il lit aussi la Séance de notation ouverte dans Lightroom (ses photos, sa passe).
- L'invite `noter` (9 invites) : noter une sortie selon le standard, passe par passe ; sans
  précision, la Séance de notation ouverte, sinon la sélection.
- Les notes proposées dans le fil de la fenêtre Claude (« Notes proposées · passe 2 · 14
  photos »).
- Une note acceptée ou changée s'écrit dans Lightroom sans repasser par Claude, donc sans rien
  dépenser de votre forfait, et jamais pendant que Claude travaille ; elle s'annule comme un
  classement, et sa proposition redevient alors à décider. C'est votre note : revenir à « Avant
  Claude » la laisse en place.
- Les notes proposées et les séances restent sur le Mac (`notation.json`) : `uninstall.sh` les
  garde, `uninstall.sh --tout` les retire.

### Changé
- `cull_photos` suit le standard : plus d'étoiles ni de drapeau Retenue proposés. Chaque photo
  reçoit un plafond de note mesuré : floue, mise au point manquée ou yeux fermés, rejet proposé ;
  douce, 3 ★ au plus ; presque noire ou brûlée, 2 ★ au plus et « à vérifier », sans rejet proposé
  (la retouche la rattrape souvent, surtout en RAW) ; capture d'écran ou document, 1 ★ ; pas la
  meilleure de sa rafale ou de sa pile, 3 ★ ; bruit fort, à noter après le débruitage.
- Le classement du tri devient un ordre de lecture (`ordre` au lieu de `score`) : la note
  esthétique de Vision y compte à moitié.
- `contact_sheet` : jusqu'à 30 vignettes par planche (au lieu de 12), et les numéros continuent
  d'une planche à l'autre.
- L'invite `tri_seance` ne propose plus de 4 ou 5 ★ ni de drapeau Retenue : les notes passent par
  `propose_ratings` (de 0 à 4 ★, 5 ★ à vous seul), et ce qu'il faut garder va dans une collection,
  pas dans une note.
- `set_metadata` pose toujours 5 ★, mais seulement à votre demande.

### Corrigé
- Le tri ne propose plus de rejeter une photo que vous aviez notée sans lui poser de drapeau : une
  photo déjà notée ou marquée d'un drapeau n'est jamais proposée.
- Le classement du tri ne met plus un paysage derrière un portrait : la qualité des visages ne
  départage que les photos d'une même rafale ou pile.

## 1.0 — 2026-10-20

Première version de Développeur. Elle réunit dans un seul projet, et une seule installation, le
connecteur MCP-Développeur (le serveur MCP que lancent Claude Desktop et Claude Code) et le module
« Développeur » de Lightroom Classic (la liaison avec le connecteur et la fenêtre Claude). Elle
remplace MCP Lightroom 2.7 et Claude pour Lightroom 1.6.1, pour un photographe amateur qui veut des
photos d'allure professionnelle.

### Ajouté
- La fenêtre Claude dans Lightroom (Fichier › Module externe - Extras › Ouvrir la fenêtre Claude,
  ou ⌃⌥C) : une conversation avec Claude Code et votre forfait claude.ai, jamais une clé d'API ;
  six invites en raccourcis, un style et un modèle au choix, des photos jointes, et les
  propositions à accepter, refuser ou ajuster.
- Le connecteur, inscrit sous le nom `MCP-Developpeur` dans Claude Desktop et Claude Code : 33
  outils pour regarder et mesurer, retoucher, faire des retouches locales, trier et harmoniser une
  série, classer dans la Bibliothèque, exporter, et garder votre style ; 8 invites, dont `partage`
  (écran, web, Instagram, impression), qui remplace `livraison`.
- Publication : cinq profils (JPEG 5 Mpx, JPEG pleine qualité, Web, Instagram, Impression) et les
  vôtres, sans Claude ni quota.
- Consommation : les jetons de la semaine, un budget (alerte à 80 %, arrêt à 100 %) et le dernier
  relevé du forfait.
- La fenêtre de suivi de la liaison, les garde-fous du Gestionnaire de modules externes et le mode
  « Proposer d'abord ».
- `install.sh` installe le tout (Claude Desktop fermé : il signale un Claude Desktop ouvert, qui
  réécrirait sa configuration sans le connecteur) et retire l'inscription de l'ancien connecteur
  `lightroom` ; `uninstall.sh` le retire, et `uninstall.sh --tout` retire aussi vos conversations,
  votre guide de style, vos profils de publication, le registre de consommation et les journaux.
  Les fichiers vont dans `~/Library/Application Support/Developpeur/`, les journaux dans
  `~/Library/Logs/Developpeur/`.

### Corrigé par rapport à MCP Lightroom
- La première retouche d'une copie virtuelle faite d'une photo que Claude avait déjà touchée se
  défait de nouveau (undo_last) et entre au journal : seul « Retouchée par Claude » en restait.

### Retiré par rapport à MCP Lightroom et Claude pour Lightroom
- Photoshop : plus d'ouverture d'une photo dans Photoshop, et plus de surveillant de Camera Raw
  (`MCP Lightroom Surveillant.app`, ni sa permission d'Accessibilité).
- L'agrandissement génératif (`expand_photo`) et ses crédits Firefly.
- Les galeries : Claude ne crée ni ne suit plus de collection publiée ; plus de profils de
  publication Client et Concours.
- La reprise de données : rien n'est repris des anciens projets (conversations, registre de
  consommation, guide de style, réglages) ; Développeur part de zéro.
