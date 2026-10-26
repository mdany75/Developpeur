# CLAUDE.md — Développeur

Claude retouche les photos de Lightroom Classic. Deux pièces qui se parlent par TCP local
(127.0.0.1, ports 54770 et 54771 ; depuis la 1.2, chaque commande porte le jeton privé de la
liaison) : le connecteur MCP-Développeur, un serveur MCP natif (Swift, SwiftPM, sans Xcode ni
Node, exécutable `mcp-developpeur`) que Claude Desktop et Claude Code lancent sur stdio ; et le
module Lightroom Classic « Développeur » en Lua (`Lightroom/Developpeur.lrplugin`, Lightroom
Classic 13.3 au moins), qui exécute ses commandes dans le catalogue (la liaison) et porte la
fenêtre Claude (« Développeur v » et la version du module dans sa barre de titre, « Développeur
v1.3.6 ») : une conversation avec Claude Code
(forfait claude.ai, jamais l'API) qui retouche et note par ce même connecteur, en une seule
disposition (la Conversation claire, à l'allure de la fenêtre B depuis la 1.3), une conversation
par photo depuis le correctif 1.3.6, avec les fenêtres Demande rapide, Suivi (le carnet de progrès),
Publication et Consommation.

Trente-cinq outils : `get_status`, `list_selection`, `view_photo`, `measure_angle`,
`read_composition`, `analyze_photos`, `get_settings`, `apply_settings`, `preview_settings`,
`enhance_photo`, `add_mask`, `edit_mask`, `retouch_spots`, `copy_settings`, `list_profiles`,
`list_presets`, `save_preset`, `undo_last`, `revert_to_original`, `export_journal`,
`find_photos`, `set_metadata`, `list_keywords`, `manage_collections`, `create_virtual_copy`,
`show_photo`, `cull_photos`, `contact_sheet`, `propose_ratings`, `remove_distractions`,
`remember_style`, `export_photos`, `compare_variants`, `choose_variant`, `match_series` ; dix
invites :
`retouche_pro`, `a_ma_facon` (1.3.5), `harmoniser_serie`, `tri_seance`, `noter`, `portrait`, `paysage`,
`noir_et_blanc`, `nuit_iso_eleve`, `partage` ; des ressources `developpeur://` (guide de style,
standard de notation `developpeur://notation`, aperçu et journal d'une photo). Depuis la 1.2 (le
rendu plus juste), `view_photo` mesure aussi l'éclairage (`mesures › eclairage`, éclairage mixte
nommé), donne l'intention lue au boîtier d'un fichier Fujifilm (`intention_boitier`) et le bilan
chiffré d'une passe à l'autre (`bilan`, alerte « regression ») ; `add_mask` dose la peau comme
Adobe (garde-fou `smoothing_requested`) et résume la méthode du tireur (éclaircir et assombrir) ;
`get_status` dit l'écran principal du Mac (`ecran`, son nom seul depuis le correctif 1.3.6). La 1.3
(apprendre en regardant Claude,
publiée le 21 octobre 2026) ajoute l'avant/après et la raison de
chaque étape (« Pourquoi ? », `Etapes.lua`), la leçon de la photo (`photo_lesson`), « Je le
fais » (`preview_settings` avec `my_turn`, `view_photo` avec `compare = claude_version`), la
composition lue (`read_composition`) et le carnet de progrès (constats de `view_photo` et
`measure_angle`, `export_journal` avec `notebook`, `carnet.json`), et la fenêtre B, agrandie à
1 948 × 1 200. Le correctif 1.3.6 retire la leçon de la photo (`photo_lesson` : 35 outils) et
« Je le fais », le volet de gauche et la rangée Mode de la fenêtre Claude (1 623 × 1 200 ; après
l'essai de Dany, les onglets Focus, Note, Aperçu et Proposition, un clic sur une étape à la place de
« Pourquoi ? », le carnet de progrès dans la fenêtre Suivi, plus rien sur l'étalonnage de l'écran ;
après son deuxième retour, le résumé en bas du fil, Agrandir qui remplit la place, une vignette de la
photo active toujours à l'endroit, ni Détail… dans l'onglet Aperçu ni « ＋ Garder la demande »),
et donne à chaque photo sa conversation (`Historique.lua`) ; le
rendu reproductible se garde au `view_photo` avec `compare = before_claude`. L'exécutable a aussi
ses commandes de développement (`--status`, `--call`,
`--recette`, `--eclairage`, `--boitier`, `--ecran`, `--constats`… : tableau Commandes). Le README
décrit les fonctions du point de vue de l'utilisateur ; le protocole entre le serveur et le
module, les chantiers de la 1.3 et la fenêtre Claude (section Fenêtre Claude, dont Fenêtre B)
sont dans `docs/SPEC.md`.

Développeur 1.0 remplace MCP Lightroom 2.7 (et son surveillant de Camera Raw) et Claude pour
Lightroom 1.6.1, sans en reprendre de données. Leurs dépôts (`~/Developer/MCP-Lightroom`,
`~/Developer/Claude-pour-Lightroom`) se consultent en lecture seule : ne jamais y écrire.

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Commandes

| Action | Commande |
| --- | --- |
| Construire | `./build.sh` (tests, compilation release, signature Developer ID, `build/Developpeur.zip` notarisé) ; `SKIP_NOTARIZE=1` pour un essai, `--sans-tests` pour un essai rapide (jamais pour une version publiée) |
| Construire et installer | `./build.sh --install` (serveur dans `~/Library/Application Support/Developpeur/`, module dans `~/Library/Application Support/Adobe/Lightroom/Modules/`, inscription « MCP-Developpeur » dans Claude Desktop et Claude Code) |
| Tester le serveur | `swift test` (jamais le vrai Lightroom, ni le vrai jeton, ni le vrai écran) ; `DEVELOPPEUR_ECRAN_REEL=1 swift test --filter EcranTests` lit en plus le vrai écran du Mac (`testLectureReelleSansPlantage`, sauté sans cette variable : lecture seule, aucune valeur attendue) |
| Tester le module | `scripts/tester-module.sh` (LuaJIT : `brew install luajit`) : forme du module, syntaxe, globales, liens entre les fichiers, puis les suites `Tests/Lua/Liaison` et `Tests/Lua/Fenetre`, et chaque `essais-*.lua` des deux |
| Essayer à la main | `swift build && ./.build/debug/mcp-developpeur --status` (inscriptions, module, état du fichier du jeton de la liaison, jamais sa valeur, le nom de l'écran principal, même Lightroom fermé, puis la liaison), puis `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée ; lit l'écran comme le serveur, et chaque `--call` est un nouveau processus : le bilan de `view_photo` y repart de zéro) ; `--module diagnostic` liste les fonctions du SDK offertes, et avec `'{"valeurs": true}'` lit le jeu de libellés, le filtre de la Bibliothèque et l'original de la photo active ; `--version` |
| Recette dans Lightroom | `./.build/debug/mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id> [--hauteur-horizon <0 à 1>]] [--original] [--images <dossier>]` (copies virtuelles de la collection « Développeur › Essais » que Claude n'a pas encore retouchées ; avec le vrai pont seulement, d'abord deux étapes en lecture seule : « liaison fermée (jeton privé) » (commande sans jeton, puis avec un autre jeton, refusées ; ni le jeton ni son chemin dans `get_status`) et « écran nommé (get_status) » (un nom non vide, rien d'autre que `nom` et `autres` chez Claude, depuis le correctif 1.3.6) ; le RAW passe aussi par « intention lue au boîtier (view_photo, intention_boitier) », « bilan chiffré d'une passe à l'autre (view_photo), puis annulé », puis la 1.3 (`Recette+13.swift`) : « avant/après d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé » et « carnet de progrès : photo d'essai refusée, notée pour la recette (essai_recette), exportée, retirée » (les étapes de la leçon de la photo et de « Je le fais » sont retirées avec eux au correctif 1.3.6) ; l'étape du débruitage vérifie aussi que la photo active revient ; `--horizon` : une copie d'Essais qui a un vrai horizon net, à `--hauteur-horizon` (0,5 par défaut), pour les trois étapes de la composition (lue et montrée, cadre actuel lu sur l'image entière recadrée en 4:5 et tournée de 2°, cadre proposé appliqué et horizon remesuré), la dernière sautée avec sa raison sans horizon net ; sans `--horizon`, la recette dit que la composition n'est pas vérifiée ; et, dans le tri, « éclaircir et assombrir : radial inversé et dégradé linéaire (propositions) » puis « … : forme des bords (radial inversé, propositions) » ; `--flash` : une photo au flash, pour les expositions d'après la prise de vue ; `--profondeur` : la copie d'une photo Portrait d'iPhone ; `--yeux-rouges` : une vraie photo au flash ; `--x-t20` : un RAF de X-T20, avec l'étape « point de mise au point dessiné pour noter (view_photo, af_point) » (carré dessiné si le point est lu, évaluation dite, chemin de l'original jamais rendu à Claude) et l'intention lue au boîtier ; `--portrait` : un portrait, la carte du masque (1.3.4 : peau du visage et arrière-plan en proposition, `mask_map` ; la peau couvre le visage, l'arrière-plan n'y déborde pas, aucune alerte) et la peau dosée (visages vus par Vision ; trois doses en propositions, détail des joues mesuré ; `amount` 50 = la moitié de la dose, jugé à l'écart maximal, 2 niveaux au plus ; peau trop lissée refusée sans `smoothing_requested`, rien d'écrit ; dose par défaut posée à `amount` 50, relue, annulée) ; `--mixte` : une photo à deux lumières, en lecture seule (éclairage mixte nommé, cases lues sur 9, durée de la mesure), puis le RAW de `--recette` en témoin à une seule lumière s'il est une autre photo ; `--original` accepte un original désigné par Dany ; `--images` : le dossier des zooms à regarder (et des deux vues du bilan) ; chacune est remise à l'origine ; l'étape « note proposée (propose_ratings), photo inchangée ; puis posée sur demande et annulée » vérifie le refus de 6 ★ (5 ★ refusées jusqu'à la 1.3.1), range une proposition à vérifier par la vraie commande `notation`, puis pose 2 ★ par `propose_ratings` avec `apply` et les annule par `undo_last` ; le registre `notation.json` est remis ensuite comme avant l'étape, même après un échec (`notation` `remettre`, `Recette.garderRegistreDesNotes`)) |
| Recette d'une version | toutes les options dont la collection d'essai a une photo (le 21 octobre 2026 : `--jpeg`, `--x-t20`, `--portrait`, `--mixte` ; ni flash, ni yeux rouges, ni Portrait d'iPhone, ni vrai horizon : `--horizon` demande d'ajouter aux Essais une copie qui a un horizon net, mer, lac ou plaine ; la dune 53709786 ne convient pas, ses rides de sable faussent la mesure), sur des copies remises à l'origine d'abord (`revert_to_original` : une copie que Claude a déjà retouchée est refusée) ; `--mixte` sur le portrait d'essai, la seule copie à deux lumières (relevé du 20 octobre 2026) ; l'étape du témoin à une seule lumière ne vient que si le RAW de `--recette` est une autre photo ; la sortie dans un fichier, en arrière-plan, jamais tronquée (`\| head` coupe la recette au milieu d'une étape) ; puis l'essai dans la fenêtre Claude (« Publier une version », étape 3) |
| Réglages à plat | `./.build/debug/mcp-developpeur --dump [<id>]` (une clé par ligne, pour `diff` avant et après une opération faite à la main) |
| Recalage mesuré | `./.build/debug/mcp-developpeur --recalage <id>` (écarts du modèle de recalage sur la géométrie actuelle ; deux rendus « Claude · recalage » dans l'Historique) |
| Carré de mise au point | `./.build/debug/mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (ce que la fenêtre Claude lance, avec le connecteur de `cheminConnecteur`, pour l'aperçu de la photo active : `PointAF.marquer` lit le point dans un original Fujifilm en temps borné (`LecteurBoitier`), le passe dans l'image affichée et le dessine sur la vignette : le cadre AF rouge à la taille de Focus-Points avec un point au centre, comme l'onglet Focus (`PreviewImages.marquerFocus`, correctif 1.3.3), sinon le carré vert, rouge si l'appareil a signalé la mise au point manquée ; code 1 sans point) |
| Écran du Mac | `./.build/debug/mcp-developpeur --ecran` (pour le développement seulement depuis le correctif 1.3.6 : l'écran principal et les autres, avec leur profil de couleur classé, d'usine, standard, à l'œil, sonde, personnalisé ou inconnu, une ligne JSON, chemin du profil compris, sans la clé `detail` ni le texte de la boîte du voyant Écran, retirés avec lui ; `{"lu": false}` sans écran ; lu sans Lightroom ni permission ; ni la fenêtre Claude ni Claude ne le lisent plus) |
| Cadres de mise au point (onglet Focus) | `./.build/debug/mcp-developpeur --focus <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (ce que la fenêtre Claude lance pour l'onglet Focus, par `perl` et son alarme de 5 s : `Focus.marquer` lit la mise au point d'un original Fujifilm en temps borné (`LecteurBoitier`), dessine sur la vignette le cadre AF à sa taille en rouge et les visages et éléments du sujet en coins jaunes (`PreviewImages.marquerFocus`), puis écrit une ligne JSON : `lue`, les blocs `image`, `prise_de_vue` et `mise_au_point` en paires titre, valeur en français, `point_af`, `cadres`, `dessinee` ; rien de lu : `{"lue": false, "raison": …}` (`delai`, `introuvable`, `illisible` : `Focus.lire`) et code 1) |
| Lecture du boîtier | `./.build/debug/mcp-developpeur --boitier <original>` (un fichier Fujifilm, RAF ou JPEG, lu sans Lightroom par `LecteurBoitier` : point de mise au point, `intention_boitier` comme `view_photo`, `mise_au_point` comme l'onglet Focus, et `valeurs_lues` sous les noms d'exiftool, pour comparer avec lui (`exiftool -a -G1 -s`, celui de Focus-Points, en lecture seule) ; une ligne JSON, code 1 si rien n'est lu) |
| Relevé du carnet | `./.build/debug/mcp-developpeur --constats <id>… [<fichier.jpg>…]` (pour fixer les seuils du carnet de progrès, en lecture seule : aperçu avec `point_af` à 1 344 px et les clés de la géométrie, jamais `carnet constater` ; par photo, L* médian et 95e centile, blanc pur du tiers haut, netteté et texture (au point de mise au point aussi), bruit, ISO et si le bruit y est cherché (1.3.1 ; l'Exif d'un fichier), boîtier, géométrie, étapes de Claude, défauts cherchés et retenus, puis un résumé ; un JPEG se mesure sans Lightroom, sans point ni intention ; lignes ✘ et code 1 en cas d'échec) |
| Relevé de l'éclairage | `./.build/debug/mcp-developpeur --eclairage <id>… [<fichier.jpg>…] [--essai '{…}']` (pour fixer les seuils de l'éclairage mixte : dominantes des tons neutres par case 3 × 3 et par zone tonale, visages, zone d'intérêt et scène de Vision, aux bornes 12, 15, 20, 25 et 30 de l'écart a*b* au centre des tons neutres, chaque ligne « borne N : … ; point neutre a* x b* y, centre a* x b* y », durée de la mesure, puis un résumé ; lecture seule par la commande `apercu`, sans point AF ni original ouvert ; un fichier JPEG se mesure sans Lightroom ; `--essai` passe par `preview_settings` (deux étapes « Claude · essai »), copies virtuelles seulement) |
| Journal détaillé | `DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ; `DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre port |
| Journaux du module | `~/Library/Logs/Developpeur/module.log` (liaison, avec les commandes refusées faute du bon jeton : une ligne par genre de refus toutes les 10 s au plus, jamais le jeton) et `conversation.log` (fenêtre Claude), gardés sous 1 Mo ; échanges avec Claude Code : `~/Library/Application Support/Developpeur/Sessions/` |
| Recharger le module dans Lightroom | Fermer les fenêtres du module (devant, elles réduisent le menu Fichier), Lightroom au premier plan, puis Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du module externe › Charger de nouveau le module ext. Un fichier `.lua` ajouté depuis le lancement ne se charge pas ainsi (« Could not load toolkit script »), ni donc un fichier qui le requiert (`Commandes.lua` requiert `Notation.lua`, nouveau en 1.1, et `Etapes.lua` et `Carnet.lua`, nouveaux en 1.3 ; `Moteur.lua` requiert `Historique.lua`, et `Fenetre.lua` `FenetreSuivi.lua`, nouveaux au correctif 1.3.6), ni un raccourci clavier changé : quitter et relancer Lightroom, après toute version qui ajoute un fichier `.lua` |
| Remesurer les polices | `swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua` (la police du système, `'<system>'` en 13, 12 et 11 et `'<system/bold>'` en 13, 12, 11 et 16, et Menlo 11 : clés `texte`, `texte12`, `petit`, `gras`, `gras12`, `gras11`, `titre`, `mono` ; si une police du fil ou des cartes change dans `Fenetre.lua`, ou pour un caractère nouveau, comme ★ ☆ ⚑ ＋ ⊗ ⤢) |
| Images de la fenêtre | `luajit scripts/gabarits.lua \| swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin` (les deux jeux, `images/` en claire et `images/sombre/`, d'après `Dispositions.IMAGES`, `Dispositions.PALETTES` et l'ordre des segments (`segments` des gabarits, tiré de `Dispositions.ONGLETS`) ; refus avant d'écrire d'une couleur absente ou invalide, d'un dossier invalide, d'aucun segment ou d'un segment en double ; signale les images orphelines) ; l'image « aucun aperçu », au cadre de l'aperçu (`images/vide-498x332.png` et `images/sombre/vide-498x332.png`) : `luajit scripts/gabarits.lua \| swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` ; après tout changement des tailles ou des palettes |
| Désinstaller | `bash uninstall.sh [--tout]` (inscriptions, serveur, module, paramètres prédéfinis invisibles Lightroom fermé, fichiers de travail, dont le jeton de la liaison `liaison.jeton` et `liaison.jeton.nouveau`, que la liaison d'un Lightroom ouvert réécrit dans les 5 s : relancer le script Lightroom fermé ; `--tout` : aussi guide de style, conversations, mes demandes de la fenêtre Claude (`mes-demandes.json`), profils de publication, consommation, notes proposées (`notation.json`), carnet de progrès et leçons d'avant le correctif 1.3.6 (`carnet.json`), avant/après des étapes (`Etapes/`) et journaux ; sans `--tout`, ils restent ; jamais le catalogue ni les photos) |
| Publier une version | voir ci-dessous |

Les fichiers produits vont dans `build/`, ignoré par git. Rien de compilé n'est commité.

## Publier une version

Dans cet ordre :

1. Mettre le numéro à jour aux trois endroits : `CFBundleShortVersionString` dans
   `Resources/Info.plist`, `VERSION` dans `Lightroom/Developpeur.lrplugin/Info.lua` et
   `Liaison.VERSION` dans `Liaison.lua` ; ajouter la section `## X.Y — AAAA-MM-JJ` dans
   `CHANGELOG.md`, écrite pour l'utilisateur. `build.sh` refuse si les trois numéros diffèrent
   ou si cette section n'est pas la plus récente des sections numérotées (« ## Non publié » peut
   rester au-dessus).
2. `git add -A && git commit -m "Version X.Y" && git push origin main`
3. `./build.sh --install` (produit `build/Developpeur.zip`, signé Developer ID et notarisé :
   attend la réponse d'Apple, quelques minutes ; met l'installation à jour). Puis relancer
   Lightroom et Claude Desktop (s'il était ouvert pendant l'installation : le quitter, lancer
   `mcp-developpeur --install`, puis le rouvrir), ouvrir une nouvelle session Claude Code, et
   faire l'essai réel sur la collection « Développeur › Essais » : la recette (`--recette`, ligne
   « Recette d'une version » des Commandes), puis une demande dans la fenêtre Claude (⌃⌥C) sur
   l'une de ces photos, défaite ensuite. L'essai doit réussir avant le tag.
4. `git tag -a vX.Y -m "Version X.Y" && git push origin vX.Y`
5. `gh release create vX.Y "build/Developpeur.zip" --title "Développeur X.Y" --notes "$(~/.claude/skills/standard-projet/scripts/notes-version.sh X.Y)"`
6. Mettre à jour la feuille de route, dans sa page Lavish seulement (artefact privé
   https://claude.ai/artifact/1nTRUJhgpvrkYybt7pNVns ; demandé par Dany le 24 octobre 2026, qui a
   fait supprimer l'ancien document Claude Docs le même jour) : la relire (Artifact, `read`), retirer
   ce que la version vient de livrer et corriger ce qui est devenu faux (frise des versions,
   bilan et décisions compris), l'ouvrir dans Lavish (`npx -y lavish-axi <fichier>`, source dans
   `docs/lavish/`, commitée et poussée depuis le 24 octobre 2026 : le dépôt est public) pour la
   relecture de Dany, puis la republier à la même adresse. De même pour
   les pages que la version rend fausses : Les 35 outils
   (https://claude.ai/artifact/KniGdYp5yt4DPsLcbsLoCL, source `les-36-outils.html`, nom gardé),
   Guide des demandes
   (https://claude.ai/artifact/F7uUKLaAnzo3BX6kWxBGPP), Apprendre avec Claude
   (https://claude.ai/artifact/CZR9wrRWk73gGGBb46HxXU), Ordinogramme d'une retouche
   (https://claude.ai/artifact/RzGhic1X61H3crEBFYjTLd). Tout document nouveau pour Dany (guide,
   compte rendu, plan) se fait de même : une page Lavish publiée en artefact, sa source dans
   `docs/lavish/`, jamais un document Claude Docs.

Une version par étape de la feuille de route (1.1 le nouvel écran et la notation, 1.2 rendu plus
juste, 1.3 apprendre en regardant Claude, 1.4 une sortie entière, 1.5 finitions et impression, 1.6
style appris), publiée après un essai réel ; entre deux, seulement des correctifs (`X.Y.Z`), et
ce que Dany demande lui-même entre deux étapes (1.1.1 : modèle et effort dans le Gestionnaire de
modules externes, une seule taille de fenêtre, nouvelle conversation par photo, chaque photo
traitée notée d'abord « à vérifier » sans bouton Évaluer, notes posées sur demande, Séance de
notation retirée). La 1.2 (« ## 1.2 — 2026-10-21 » de `CHANGELOG.md`, publiée après son essai réel)
est le rendu plus juste : peau dosée comme Adobe, éclaircir et assombrir comme un tireur, intention
lue au boîtier, éclairage mixte nommé, bilan chiffré d'une passe à l'autre, écran nommé, liaison
locale fermée par un jeton privé ; avec ce que Dany avait demandé depuis la 1.1.1 (une seule
disposition, aperçu de la photo active avec son point de mise au point, proposition préparée à
l'ouverture, point de mise au point sur un zoom, masque d'une personne seule gardé). La 1.3
(« ## 1.3 — 2026-10-21 » de `CHANGELOG.md`, publiée après son essai réel) apprend en regardant
Claude : Pourquoi ?, leçon de la photo, Je le fais, composition lue, carnet de progrès, avec la
fenêtre B demandée par Dany (1 948 × 1 200), faite sur la branche d'intégration `version-1.3`
(lots 1 à 19, fenêtre B, son agrandissement et son élargissement). En restent : une copie
d'Essais qui a un vrai horizon pour `--horizon`, et ce que `docs/SPEC.md` garde dans À constater
dans Lightroom (1.3). Le correctif 1.3.1 (« ## 1.3.1 — 2026-10-22 », publié après sa recette, 86
étapes, et un essai dans la fenêtre Claude) : `reason` dans `preview_settings`, `cull_photos` sur la
photo active, bruit du carnet à ISO élevé (`Carnet.isoEleve`), leçon d'une photo d'essai hors du
carnet. Ce qui attend la 1.4 va sous « ## Non publié », au-dessus de la dernière section
numérotée.
Le standard de notation (une étoile = un niveau de qualité fixe, 0 ★ = pas encore jugée, rejeter =
drapeau, Claude note de 0 à 5 ★ depuis le correctif 1.3.2, les coups de cœur de Dany sont un
libellé de couleur qu'il pose lui-même), venu de la section 1.1 de la feuille de route, est
maintenant le texte de `Notation.standard` (voir Règles). Le correctif 1.3.2 (« ## 1.3.2 — 2026-10-22 ») :
une proposition qu'une étape de Claude dépasse n'attend plus, Claude note de 0 à 5 ★, la carte
Note perd la rangée des passes et la ligne du plafond, l'onglet Focus (la mise au point Fujifilm
comme Focus-Points, `--focus`) et Mes demandes (menu à droite de Style, « ＋ Garder la demande »,
retiré au correctif 1.3.6) ;
demandés par Dany le 22 octobre 2026. Le correctif 1.3.4 (« ## 1.3.4 — 2026-10-23 », demandé par
Dany le 23 octobre 2026, quatre chantiers tirés de la 1.4 et de la 1.5 de la feuille de route, tous
côté connecteur) : la règle de la rafale pour les yeux fermés, la nature de l'écrêtage (luminance ou
gamme), la carte du masque (`mask_map`) et les points chauds ; « Harmoniser par lumière » reste dans
la 1.4, et la partie « « À vérifier » devient un libellé de couleur, filtrable » de la ligne Yeux est
écartée (décision de Dany du 23 octobre 2026 : rien de filtrable). Le correctif 1.3.5 (« ## 1.3.5 —
2026-10-23 », demandé par Dany le même soir, au-delà de la limite d'usage à sa demande) : huit
chantiers de la feuille de route, trois de la 1.4 (sauvegarde dite, rafales par boîtier, vidéos
écartées), un de la 1.5 (préparer un tirage) et les quatre de la 1.6 (ton style sur une photo neuve,
rendu reproductible, styles en recettes fixes, apprendre de tes corrections) ; il change le module
(relancer Lightroom). Publié le 23 octobre 2026 (tag v1.3.5 sur fedabf3) après les deux suites, sa recette (87
étapes) et un essai dans la fenêtre Claude (sauvegardes dites, +0,2 IL sur le portrait d'essai,
défait). Publié le 23 octobre 2026 sur la demande de Dany (« publie »), après les deux suites et sa recette (87 étapes), sans l'essai dans la fenêtre Claude : le contrôle en arrière-plan refuse « Ouvrir la fenêtre Claude » et ⌃⌥C (pris pour une commande du presse-papiers) et l'accord plein écran n'est pas venu ; l'essai reste à faire.

Le 24 octobre 2026, Dany a retiré l'épreuvage (ni sonde pour l'écran, ni profil ICC du labo) :
la 1.5 est livrée par les correctifs 1.3.4 et 1.3.5, comme la 1.6 par le 1.3.5 ; reste la 1.4,
dont l'essai sur une sortie de 500 photos servira aussi à éprouver la notation (notée, puis
renotée en partie quelques jours plus tard ; pas de photos étalons).

Le correctif 1.3.6 (« ## 1.3.6 — 2026-10-25 », numéroté, construit et installé le 25 octobre 2026
pour les essais de Dany ; recette, essai réel, tag et Release seulement sur son ordre ; décidé avec
Dany le même jour) : une photo, une conversation (la photo seule choisie reprend la sienne, sinon une
neuve qui commence par son historique ; plusieurs photos, une conversation de groupe jamais gardée ;
« Repartir à neuf » ; la Demande rapide sur une photo seule écrit dans la conversation de la
photo), la fenêtre Claude allégée (volet de gauche et rangée Mode retirés, 1 623 × 1 200, menu
« Afficher la fenêtre de la liaison »), la leçon de la photo (`photo_lesson` : 35 outils) et « Je le
fais » retirés, plus de proposition préparée à l'ouverture (« Obtenir » sous la carte de l'onglet
Proposition, décision de Dany du 25 octobre 2026), le rendu reproductible gardé au `view_photo`
avec `compare = before_claude` ; avec ce qui attendait sous
« ## Non publié » (la balance des blancs de toute l'image, la Demande rapide sans ♻). Puis, le même
jour, les retours de Dany après son essai de la 1.3.6 installée (tous acceptés, numéro gardé) : un
clic sur une étape ou une image du fil à la place du bouton « Pourquoi ? » ; les onglets Focus,
Note, Aperçu et Proposition, la fenêtre ouverte sur Focus et ramenée à Focus à chaque autre photo ;
une image de Claude qui arrive ouvre Aperçu, une proposition Proposition, une note Note ; Agrandir
jusqu'à 2 000 × 1 250 (qu'il remplit depuis le deuxième retour, plus bas) ; le carnet de progrès dans la fenêtre Suivi (bouton Suivi de l'en-tête, à la
place de l'onglet Suivi qui avait remplacé Leçon ; les graphiques et l'ajout de chaque photo au
carnet attendent le correctif 1.3.7) ; plus rien sur l'étalonnage de l'écran (ni voyant Écran, ni
section Écran des consignes, ni remarque au premier aperçu, `get_status` ne dit que le nom) ; les
réglages hors des valeurs par défaut dans l'historique d'une photo sans étape de Claude ; la barre
de titre « Développeur v1.3.6 ». Il ajoute deux fichiers au module (`Historique.lua`,
`FenetreSuivi.lua`) : quitter et relancer Lightroom. Puis, le même jour, le deuxième retour de Dany
(accepté tel quel, numéro gardé) : une vignette de la photo active toujours à l'endroit (juste après
une retouche, la vignette de secours d'une photo verticale arrivait couchée dans Focus et Agrandir) ;
Agrandir qui remplit toujours 2 000 × 1 250, en agrandissant une image plus petite, et redemande la
photo active en grand au clic (sinon un rendu) ; le bouton Détail… de l'onglet Aperçu retiré ; un
résumé en bas du fil, fait par la fenêtre, jamais gardé ni envoyé à Claude ; « ＋ Garder la
demande » retiré avec la ligne « Demande à garder » de Claude et sa section des consignes (le menu
Mes demandes reste). Aucun fichier nouveau au module (`essais-resume.lua` aux essais), connecteur
inchangé.

Le README pointe vers `https://github.com/mdany75/Developpeur/releases/latest/download/Developpeur.zip`.

## Règles

- Répondre et écrire (commits, README, textes des outils, du module, des fenêtres et des erreurs)
  en français, dans un style simple et précis.
- **Pour un photographe amateur** : Dany retouche ses propres photos (souvenirs, écran, partage,
  impression), sans client, vente ni concours ; Développeur l'aide à leur donner une allure
  professionnelle sans être pro. Rien d'orienté client, mariage ou concours (galeries, collections
  publiées, profils Client ou Concours), et plus de Photoshop : ni agrandissement génératif, ni
  crédits Firefly, ni ouverture dans Photoshop. `MCPServerTests` et `Version25Tests` vérifient que
  les consignes, les outils et les invites n'en parlent pas ; `NotationTests`, le standard de
  notation.
- **Ne jamais retoucher de vraies photos pendant les tests** : `swift test` passe par
  `FakeLightroom` et un faux module TCP ; `scripts/tester-module.sh` par les Lightroom simulés de
  `Tests/Lua/Liaison/Simulation.lua` et `Tests/Lua/Fenetre/Simulation.lua`, avec `faux-claude.sh`
  à la place de Claude Code (ni Claude, ni quota, dossier personnel temporaire). Un essai dans
  Lightroom, ou la recette, se fait sur les photos de la collection « Développeur › Essais » (des
  copies virtuelles que Claude choisit et y range), ou sur une photo que Dany désigne ; l'essai se
  défait ensuite (`undo_last`, `revert_to_original` ou ⌘Z).
- Ne jamais écrire dans les vrais fichiers de Claude ni dans les préférences de Lightroom depuis
  les tests : `ClaudeRegistration` reçoit des chemins temporaires, les raccourcis vont dans un
  fichier d'essai, le presse-papiers est un presse-papiers nommé. Ni lire le vrai jeton de la
  liaison ni le vrai écran : `LightroomBridge.fichierJeton` vaut nil par défaut, et
  `ToolHandler.lireEcran` (comme `Recette.lireEcran`) ne lit aucun écran par défaut ; les tests
  passent un fichier temporaire ou un écran fabriqué, et aucun n'envoie par
  `LightroomBridge.fromEnvironment()` ; seul `DEVELOPPEUR_ECRAN_REEL=1` fait lire l'écran du Mac à
  `swift test`.
- `stdout` est réservé au protocole JSON-RPC : les journaux vont sur `stderr`. Réponses et
  notifications de progression y passent sous le même verrou (`print(line:)` de `main.swift`).
- Claude Desktop (et l'onglet Code de l'application, qui lui passe ses appels) abandonne un outil
  au bout de 60 s, sans tenir compte de la progression, puis relance le serveur. Tout appel
  d'outil passe par `FileOutils` : un seul à la fois vers le module, réponse d'attente à 50 s sans
  `progressToken`, résultat gardé pour le même appel répété. Ne jamais appeler le module hors de
  cette file depuis le serveur (le module traite chaque commande dans sa propre tâche : deux
  commandes mêlées se gênent). Voir `docs/SPEC.md`, Délai des appels d'outils.
- Claude Desktop et chaque session de Claude Code gardent le serveur lancé à leur ouverture : après
  une installation, relancer Claude Desktop et ouvrir une nouvelle session Claude Code pour avoir les
  nouveaux outils ; un connecteur d'avant la 1.2 resté ouvert est refusé par le module 1.2
  (« Liaison fermée : cette commande ne porte pas le jeton… », qui dit de relancer). `/clear` vide
  la conversation mais ne relance pas le serveur. La fenêtre Claude lance le sien avec chaque
  processus Claude Code, fermé quand le module se recharge ou que Lightroom quitte.
- Claude Desktop ouvert garde `claude_desktop_config.json` en mémoire et le réécrit : une
  inscription faite pendant ce temps se perd (constaté le 20 octobre 2026 : `MCP-Developpeur`
  perdu, l'ancienne clé `lightroom` revenue). L'inscription se fait Claude Desktop fermé ;
  `install.sh` et `uninstall.sh` le signalent par `pgrep -xa Claude` (sans `-a`, pgrep ne voit pas
  Claude Desktop depuis une session de Claude Code qu'il a lancée). `--install` retire l'ancienne
  clé `lightroom` de MCP Lightroom (`ClaudeRegistration.ancienneCle`), `--status` la signale.
- Un seul connecteur : la clé `MCP-Developpeur` dans Claude Desktop et Claude Code
  (`ClaudeRegistration.serverKey`, égale à `ServerInfo.name` ; `title` « MCP-Développeur »), et
  le nom `developpeur` dans `connecteur.json` pour la fenêtre (`Session.SERVEUR`). Les fenêtres
  (« Claude · liaison », « Claude · Publication », « Claude · Consommation », « Claude · Suivi »,
  « Claude · Demande rapide »), les étapes
  « Claude · … », l'instantané « Avant Claude », l'ensemble de collections « Claude » et les
  copies virtuelles « Claude » gardent le nom Claude : c'est ce que Claude a fait. Seule la barre
  de titre de la fenêtre Claude dit « Développeur » (`Fenetre.afficher`, demandé par Dany le
  20 octobre 2026), suivi de la version du module depuis ses retours du 25 octobre 2026
  (« Développeur v1.3.6 » : `Fenetre.titreFenetre`, d'après `Composants.module()` ; « Développeur »
  seul si la version ne se lit pas) ; son menu (« Ouvrir la fenêtre Claude », ⌃⌥C, que
  `Raccourcis.lua` vise) et la documentation l'appellent toujours « fenêtre Claude ».
- Le module est du **Lua 5.1** (celui de Lightroom) : pas de `goto`, pas de `//`. Le JSON passe
  toujours par `Json.lua`, qui lit et écrit les nombres sans dépendre de la locale (en français,
  `string.format` écrirait « 0,35 »). Dans une tâche asynchrone, `LrTasks.pcall` et non `pcall`
  dès que le code peut attendre (rendu, accès au catalogue). `os.time` et `os.date` passent par
  `Compat.lua` (remplacés par `LrDate` s'ils manquaient).
- Toute écriture dans le catalogue passe par `withWriteAccessDo` (`ecrire` dans `Ecriture.lua`) ;
  la simulation des tests le vérifie.
- La mémoire de Claude (champs de `Metadonnees.lua`) se lit par `lireChamp` ou `lireJson` et
  s'écrit par `garder` : Lightroom copie ces champs dans une copie virtuelle, et seuls ceux-là
  vérifient qu'elle appartient à la photo (`proprietaireMemoire`). Dans une écriture, Lightroom
  relit un champ du module avec sa valeur d'avant l'écriture (constaté par ses effets) : `garder`
  ne rattache donc une photo qu'une fois par écriture (`Photos.nouvelleEcriture`, appelé par
  `Ecriture` au début de chacune), et la simulation ne montre un champ écrit qu'après l'écriture.
  Voir `docs/SPEC.md`, Mémoire des retouches.
- **L'avant/après d'une étape se garde au rendu, jamais par une écriture** (1.3, `Etapes.lua` ;
  `docs/SPEC.md`, Pourquoi ?) : Lightroom ne rend que l'état actuel. Toute étape nouvelle passe par
  `Ecriture.nouvelleEtape` (`{ id, nom, avant, le }`, id par `Ecriture.idEtape`) ; `etape_id`
  (résultats, journal, `annuler`) n'est pas un réglage ; une étape d'avant la 1.3, sans id,
  s'annule par son rang. La capture se fait autour de la commande (`Liaison.recevoir` :
  `Etapes.avantCommande`, `apresCommande` une fois la réponse partie, `abandonner` ; ces crochets
  ne laissent passer aucune erreur) : case Avant/après et fenêtre ouverte ou son Claude au travail
  (`Etapes.actifPour`), ou `avant_apres` (la recette seulement, jamais un outil) ; une seule
  photo, la photo active ; jamais `sans_avant_apres` (`match_series` l'envoie), ni en pause, ni
  pour un refus prévisible ; jamais un rendu avec des calculs IA en attente. L'avant est la vue
  (`Rendu.apercu` ne la garde que pour l'image entière de l'état actuel, jamais un zoom, un
  `chemin_avant`, un `essayer` ni une image entière de la composition) reconnue par l'empreinte,
  sinon un rendu avant l'écriture ; l'après est rendu après la réponse. Une capture à la fois
  (`ATTENTE` 8 s pour les commandes hors `SANS_ATTENTE`, `PERIMEE` 120 s) ; `COTE` 1 024. Dans
  l'empreinte (`sansVolatils`), une table vide sous une clé texte vaut une clé absente (constaté le
  21 octobre 2026 : `MaskGroupBasedCorrections` absente ↔ `{}` après une comparaison, une
  annulation de masque, les rendus du recalage) ; Lightroom ne change seul aucune clé (constaté).
  Captures de 0,51 à 1,06 s, réponse +4 % avec une vue, +0,8 s sans ; ménage au chargement
  (`Etapes.menage`, 30 jours, 500 Mo).
- **`PriseDeVue.defauts` est la seule liste des défauts de la prise de vue** (16 codes, domaine du
  carnet, six mesurés ; plus d'axe ni de clé anglaise depuis le correctif 1.3.6, les dix autres
  gardés pour les leçons d'avant rangées dans `carnet.json`) ; `PriseDeVue.vocabulaire` part avec
  chaque constat : aucune liste de défauts dans le module. `ToolHandler.descriptionRaison` (la description de `reason`, répétée dans
  chaque outil qui écrit) fait 160 caractères au plus, comme `descriptionRaisonProposition`, celle
  de `preview_settings` depuis la 1.3.1 (Claude y joignait `reason` 3 fois sur 4 et l'appel était
  refusé ; elle ne promet pas le journal). Une proposition n'écrit rien : sa raison
  ne part jamais au module (ni étape ni journal), elle revient dans la réponse (`raison`), à
  redonner à `apply_settings`. `ToolHandler.raison` la nettoie et la borne (300 caractères).
- **La leçon de la photo et « Je le fais » sont retirés au correctif 1.3.6** (décision de Dany du
  25 octobre 2026) : `photo_lesson`, `Lecon.swift`, `Tools+Lecon.swift`, `Prompts.Lecon.phrase`, la
  commande `lecon`, le journal détaillé (`detaille`, `prise_de_vue_plus`), `JeLeFais.swift`,
  `my_turn`, `compare = claude_version`, l'exercice de `Variantes.lua` et de `Rendu.lua`
  (`exercice`, `sans_rendu`, `versionClaude`) et `Tests/Contrats/je-le-fais.json`. Les leçons déjà
  rangées restent dans `carnet.json` (puce Carnet de progrès), et les éléments `lecon` et
  `exercice` d'une conversation d'avant se relisent et se réécrivent tels quels, sans ligne au fil
  (`essais-proposition.lua`). `essayer` n'est pas une étape (`Etapes` ne le capture pas) ;
  `Ecriture.difference` est la seule comparaison entre états simples (`Historique.lua` la reprend
  par `Ecriture.correctionsUtilisateur`).
- **La composition se lit sur l'image entière** (`Composition.swift`, `Tools+Composition.swift`,
  `Rendu.lua`) : l'image entière se rend par l'écriture temporaire du cadre retiré
  (`sansRecadrage` : `Recadrage.AUCUN` et la case décochée), puis le retour, comme le recalage (deux
  étapes « Claude · composition ») ; une photo agrandie est refusée avant toute écriture ; un
  module qui ne rend pas `image_entiere` est refusé. Les positions de `view_photo` passent par
  `Composition.versImageEntiere` d'après `cadre_actuel` ; l'horizon se mesure sur l'image entière
  (angle absolu) ; le dessin suit le cadre que Lightroom a gardé, relu (`cadre_propose`), jamais la
  demande ; la marge de 0,998 sert aux arrondis du module (validée le 21 octobre 2026). Seuils
  relevés le 21 octobre 2026 : `roulisRenverse` 3π/4 (un visage à l'envers n'est ni le sujet ni le
  regard), `zoneInteretMax` 0,5 (au-delà, pas de sujet), `signeLacet` +1 confirmé, `seuilLacet`
  0,26 gardé, `LineAngle.ecartMax` 3 px (au-delà, la ligne n'est pas « affinée », l'angle vient des
  deux points), tiers à 0,35 % (`PreviewImages.traitTiersPart`), cadre à 0,4 %. Le contrat est figé
  dans `Tests/Contrats/composition.json`.
- **Carnet de progrès** : `carnet.json` n'est tenu que par `Carnet.lua` (une table par catalogue,
  une entrée par original, 3 000 au plus ; tout lire, puis changer le registre d'un coup ; une copie
  neuve vers une vue, des tableaux JSON vers le serveur ; un fichier illisible mis de côté ; les
  phrases du résumé n'existent que dans `Carnet.resumer` ; `Preferences` et `Recalage` ne sont
  requis que dans `constater`). `carnet` n'écrit rien dans le catalogue, ne s'arrête pas à la
  pause et ne se rejoue jamais (`LightroomBridge.lectures` : `etapes` oui, `carnet` non). Une photo
  de « Développeur › Essais » n'y entre pas, sauf `essai_recette` (la recette seulement), sous
  l'entrée de la photo d'essai, jamais celle de son original. Les leçons d'avant le correctif 1.3.6
  restent dans les entrées qui en ont, telles que `Json.decode` les a rendues (tableaux marqués),
  réécrites à l'identique à chaque écriture, jamais montrées ni envoyées au serveur, jamais
  perdues par `retirer` ni par l'élagage (une entrée qui n'a plus qu'elles ne compte plus au carnet) ;
  côté connecteur, `Carnet.sansLecons` retire encore une clé `lecons` d'un résumé avant Claude et le
  Markdown. Côté connecteur (`Carnet.swift`) : seuils et détection
  seulement là, codes de `PriseDeVue`, règles de netteté seulement dans
  `PhotoTriee.defautsNettete` ; la vue part au premier `view_photo` entier d'une photo sans étape de
  Claude, avant le carré du point de mise au point ; l'horizon n'est trouvé que par une ligne mesurée
  (`measure_angle`, `read_composition`) de 0,5° ou plus sur une géométrie intacte
  (`Carnet.geometrieIntacte`) ; netteté et bruit à 1 024 px au moins ; le bruit fort (« garder
  l'ISO plus bas ») ne se cherche, et ne se compte, qu'à un ISO connu d'au moins `Carnet.isoEleve`
  (1 600, provisoire, `Carnet.bruitCherche` ; 1.3.1). Relevé du 21 octobre 2026 (`--constats` et la
  commande `reglages`, quatre photos de Dany et sept copies d'Essais) : à ISO 160 à 400, la texture
  (reflets d'eau, sous-bois) mesurait de 1,62 à 8,99, de faux constats ; à ISO 4 000 et 12 800, un
  vrai bruit (1,93 et 2,09) ; à 1 600 et 3 200, rien au-dessus de `bruitFort` : le seuil reste à
  éprouver entre 400 et 4 000. L'ISO vient de la réponse du module (`Carnet.iso`) : `sensibilite`
  de la description (`Photos.sensibilite`, isoSpeedRating brut lu par `tonumber` : de 160 à 12 800
  le même jour ; un nombre, constaté le 22 octobre 2026 par l'étape de la leçon de la recette,
  retirée au correctif 1.3.6 ; `Vignettes.decrireVignette`), sinon `prise_de_vue.iso` d'un module 1.3 ;
  `view_photo` retire `sensibilite` avant Claude. Pas le plafond de note (`Notation.plafond`), qui
  juge l'image, ni le tri, qui ne fait que dire la mesure. Les constats notés avant restent tels
  quels ; `constats_prise_de_vue`
  seulement si le module répond `note = true`, erreurs tues ; `noterAuCarnet` n'est vrai que dans
  `serve()` (ni `--call`, ni la recette, ni les tests), et seul lui fait demander les clés de la
  géométrie ; `view_photo`, `measure_angle` et `read_composition` restent `readOnlyHint`. Seuils
  `medianeSousExposee` 28, `p95SousExposee` 80 et `partBlancPurHaut` 3 % provisoires (aucun vrai
  cas). La case Carnet coupe les constats (elle devait couper aussi les leçons, décision de Dany du
  24 octobre 2026, devenue sans objet : la leçon est retirée au correctif 1.3.6). Depuis la fenêtre
  Claude, le carnet se lit dans la fenêtre Suivi (puce La fenêtre Suivi).
- **Mise au point jugée sur de la texture** (`Detail.autour`, relevé le 21 octobre 2026 sur les
  copies d'Essais) : sous `DetailMeasurements.textureMin` (18 : sable lisse, ciel uni), la mise au
  point est « non jugée » (pas de plafond, pas de constat au carnet sauf si l'appareil l'a
  signalée) ; jusqu'à `textureDouteuse` (30 : le bord d'un nuage), une mise au point manquée n'est
  qu'un doute : 2, à vérifier, sans rejet proposé (`Notation.plafond`), et le carnet ne la compte
  pas. À relever sur un mur, de la neige et une vraie mise au point manquée avant de les changer.
- Un profil d'appareil se pose toujours par `libererProfil`, qui vide `MissingCameraProfile` :
  Lightroom y garde un nom introuvable, et tant qu'il y reste, tout profil suivant retombe à Adobe
  Standard. Il se relit après coup (`attendreProfils`) : Lightroom ne remplace un nom introuvable
  qu'une fraction de seconde après l'écriture. Les noms des simulations Fujifilm sont ceux que
  Lightroom range pour un X-H2S (casse indifférente, ponctuation exacte), dans le catalogue du
  serveur avec leurs `variants`. Voir `docs/SPEC.md`, Profil.
- Ce qui revient du JSON passe par `pourLightroom` avant `applyDevelopSettings` : une table qui
  porte une métatable (tableau relu par `Json.decode`) bloque Lightroom sans erreur, verrou
  d'écriture compris (voir `docs/SPEC.md`, Profil). La simulation de la liaison refuse les
  métatables.
- Ce que Lightroom ne calcule pas quand il est posé par `applyDevelopSettings` (tonalité et balance
  des blancs automatiques, masques IA, flou d'objectif, profils adaptatifs) passe par un paramètre
  prédéfini du module (`addDevelopPresetForPlugin` puis `applyDevelopPreset`). Un profil adaptatif
  n'y est marqué à calculer que si sa Look porte `isAdobeAdaptive` et le paramètre prédéfini
  `AILook = {Active = true}` (`poserAdaptatif`) ; les nombres des fichiers de profil restent des
  nombres (`ProfilsLook.convert`). Le calcul (masques IA, profil adaptatif, flou d'objectif, outil
  Supprimer) se fait par `photo:updateAISettings()`, **hors** de `withWriteAccessDo`, après
  l'écriture (`Ecriture.calculerIA`, deux passages au plus) et avant un rendu
  (`calculerAvantRendu`) ; un profil adaptatif se recalcule ainsi après une tache ou un flou, pas
  après une rotation, qui ne le change pas (constaté). Ce que Lightroom n'a pas pu calculer
  (modèles IA absents) ouvre au rendu la fenêtre « Mises à jour IA recommandées », qui attend
  l'utilisateur : rien n'y répond à sa place. Un tel paramètre prédéfini fait tomber une balance
  des blancs personnalisée aux butées : tout plan passe par `appliquerPlan`, qui la repose
  (`noterPresetDuModule` la mémorise). S'il porte `MaskGroupBasedCorrections`, il **remplace** les
  masques de la photo : il doit porter la liste entière, masques existants compris
  (`masquesParPreset`). Une liste de taches vide ne les retire pas : vider aussi `RetouchInfo`
  (`aRemettre`). Voir `docs/SPEC.md`. Le nom d'un paramètre prédéfini du module dont le contenu
  varie suit ce contenu (`presetContenu`) : Lightroom range un fichier par nom. Le module les
  efface à son chargement (`Menage.lua`, depuis `Init.lua` : à la fermeture de Lightroom,
  `Arret.lua` ne s'exécute pas, constaté) et à son arrêt ; `install.sh` aussi, Lightroom fermé
  seulement.
- La suppression des reflets (`Suppression.lua`, commande `supprimer`) suit le même chemin que le
  débruitage (photo affichée, hors de `withWriteAccessDo`, un seul traitement à la fois) ; l'état
  d'avant va dans la mémoire sous la clé `Suppression`, qui n'est jamais un réglage (la simulation
  le refuse) ; une autre intensité se pose en retirant puis reposant le filtre
  (`changeReflectionRemovalAmount` ne change rien au filtre rangé, constaté). `annuler` et
  `revenir` remettent les traitements calculés par `Annulation.remettreCalcules`.
- Débruitage, détails bruts et super résolution passent par `LrDevelopController`
  (`setEnhance`), sur la photo affichée dans le module Développement : le module l'y affiche,
  seule sélectionnée, laisse le temps de la charger, puis remet la vue. Un seul traitement à la
  fois (`avecVerrou`). Ces appels se font **hors** de `withWriteAccessDo` (la simulation le
  refuse) ; l'état d'avant va dans la mémoire, écrite avant le calcul, sous la clé `Amelioration`,
  qui n'est pas un réglage et ne doit jamais partir dans `applyDevelopSettings` (la simulation le
  refuse aussi).
- Le classement dans la Bibliothèque (note, drapeau, libellé, textes, texte alternatif, champs
  IPTC, position GPS, mots-clés, collections) se garde dans la mémoire sous la clé `Bibliotheque`,
  qui n'est pas un réglage : jamais dans `applyDevelopSettings` (la simulation le refuse) ;
  `annuler` et `revenir` la remettent par `Bibliotheque.remettre`. Titre, légende, droits d'auteur
  et libellé se lisent par `getFormattedMetadata` : `getRawMetadata` les refuse (la simulation
  aussi). Le libellé s'écrit comme un texte du jeu de libellés actif, vérifié par
  `colorNameForLabel` après l'écriture seulement ; un texte s'efface par un texte vide, jamais par
  nil (`ecrireChamp`). Une collection (et, supposé, un ensemble) ne se lit pas dans l'écriture qui
  l'a créée : la créer dans sa propre écriture, puis l'employer dans la suivante. Un mot-clé, lui,
  se crée et se pose dans l'écriture du classement (constaté), sans jamais y être lu (`getName` y
  échoue). Un paramètre prédéfini de métadonnées ne se voit qu'après l'écriture qui l'applique :
  relu ensuite (`relirePresetsMetadonnees`). Voir `docs/SPEC.md`, Bibliothèque.
- Le libellé se pose d'abord par le texte que donne `getLabelMapToColorName` (texte → couleur,
  constaté). Une position GPS s'efface par `setRawMetadata('gps', nil)` (constaté) ; l'état d'avant
  sans position est `{ aucune = true }`. Un champ IPTC donné un à un et un paramètre prédéfini de
  métadonnées ne vont pas dans le même appel. Le jour d'une prise de vue se lit à l'heure locale
  (`timeToUserFormat`) : `timeToW3CDate` donne l'UTC (constaté).
- Le filtre de la Bibliothèque (`montrer`) se bâtit sur une copie du filtre actuel et se remet par
  ses valeurs exactes, jamais par un paramètre prédéfini : un filtre sans `columnBrowserDesc`, et
  « Filtres désactivés », remettent les colonnes du filtre Métadonnées par défaut (constaté). Un
  critère vide vaut « <nil> », le libellé « sans » est `noLabel`.
- Renommer, déplacer une collection ou changer ses critères, renommer un mot-clé ou ses synonymes
  touche la structure du catalogue : jamais de suppression, pas d'étape pour `undo_last` (la
  réponse donne l'état d'avant).
- Une commande qui calcule sur l'original (débruitage, détails bruts, super résolution, reflets)
  passe par `Photos.exigerOriginal` ; un rendu sans original ni aperçu dynamique est refusé
  (`rendre`) ; une livraison saute la photo. `checkPhotoAvailability` suit le disque à quelques
  secondes près (constaté).
- Un aperçu (`rendre`) fait passer `isExported` à vrai (constaté) : `apercuSeulement` le note, une
  livraison (`exporter`) ou une publication de la fenêtre Publication (`Publication.publier`)
  l'efface, en écriture privée ; « exportée » se lit par `Photos.exportee`, jamais par
  `isExported` seul.
- Les listes de photos se décrivent par `Photos.decrireTout` (lectures groupées du catalogue) ;
  « retouchée par Claude » n'y compte que si `proprietaireMemoire` est l'uuid de la photo.
- Une personne précise (`add_mask`, `kind: "person"`) porte `InstanceIDs` **et** `InstanceBounds`,
  les cadres de toutes les personnes (le serveur les tire de Vision, `detecterPersonnes`) : sans
  eux, Lightroom ne la reconnaît pas (constaté). Sauf la personne seule d'une photo (Vision n'en
  trouve qu'une : `seule`) : faite à la main, elle n'a ni l'un ni l'autre, seulement le sous-type 0
  et sa catégorie, et le module l'envoie ainsi (`Locaux.personne`) ; numérotée, Lightroom la calcule
  de même puis retire le numéro (constaté le 20 octobre 2026, même `MaskDigest`).
  `Locaux.numeroPersonne` la compte comme la personne 1 (`Locaux.CATEGORIES_PERSONNE` : le
  sous-type 0 sert aussi à l'arrière-plan et au paysage). `sansCalculsIA` garde les cadres ;
  `Retouche.verifierPersonnes` retire un masque non reconnu après le calcul. Les masques vides se
  retirent par `deleteAllEmptyMasks`, hors de `withWriteAccessDo` (`Masques.retirerVides`).
- Un module ne peut pas : lancer ni faire refaire la poussière (le module ne fait que la retirer ;
  copiée, elle colle les taches de la source), convertir une version de processus 1 ou 2
  (`setProcessVersion` ne fait rien), mesurer la profondeur d'un cadre du flou d'objectif, calculer
  l'Upright avec repères (posés, la transformation attend le clic « Mettre à jour » de
  l'utilisateur). Constatés le 18 octobre 2026 : voir `docs/SPEC.md` ; ne pas les réessayer sans
  nouvelle piste.
- Le module n'agrandit plus, mais une photo déjà agrandie par l'ancien connecteur
  (`Reglages.estAgrandie` : cadre hors de [0, 1]) reste protégée : Claude ne la recadre pas
  (`preparerRecadrage` refuse), son recadrage ne se copie ni vers elle ni depuis elle, et
  « Contraindre le recadrage » n'y est pas coché.
- `LensProfileSetup = "LensDefaults"` ne tient que par un paramètre prédéfini du module avec
  `LensProfileEnable` (`presetObjectifParDefaut`), à l'application comme à l'annulation.
- Une rotation d'un quart de tour (`Conversions.lua`) se fait hors de `withWriteAccessDo` et se
  garde sous la clé `Rotation` de la mémoire, qui n'est pas un réglage.
- L'état laissé par Claude (`apresClaude`, pour relever les corrections faites à la main) s'écrit
  par `noterEtatFinal`, en écriture privée (`withPrivateWriteAccessDo`) : jamais une écriture
  ordinaire, qui ajouterait une opération à Édition › Annuler. Toute écriture de la mémoire seule
  (sans réglage ni instantané) passe de même par `Ecriture.ecrireMemoire` ; la mémoire d'une étape
  s'écrit avec ses réglages, dans la même écriture ordinaire.
- Une variante (`compare_variants`) se range en instantané par `createDevelopSnapshot` (dans une
  écriture, avec la mémoire `variantesClaude`) ; `applyDevelopSnapshot` et `deleteDevelopSnapshot`
  sont des commandes du module Développement : **hors** de `withWriteAccessDo` et photo affichée
  dans le module Développement (`Amelioration.afficherEnDeveloppement`, puis `remettreVue`),
  `snapshotID` pour poser, `id_global` pour effacer (constaté ; la simulation refuse le reste).
  La mémoire de l'étape s'écrit avant, et se retire si l'instantané n'a rien changé.
- Une livraison (`exporter`) passe par `LrExportSession` avec `LR_collisionHandling = 'rename'` :
  jamais `overwrite` hors du dossier temporaire d'un aperçu. Elle ne change pas les photos ; ses
  lots suivants (`suite`) ne redemandent pas l'accord. Les modèles de noms et les filigranes se
  lisent dans les `.lrtemplate` de l'utilisateur, côté serveur (`FilenameTemplates`,
  `FiligranesUtilisateur`) ; les noms exacts, par `getNameViaPreset` (commande `nomsFichiers`).
  Les livraisons types sont les réglages des services Disque dur, lus clé par clé
  (`Services.lua` ; côté serveur, `profilService`) : le module ne crée, ne change ni ne publie
  aucun service. Une sortie HDR n'est faite que pour une photo en mode HDR, dans les espaces et
  profondeurs que Lightroom offre (pas de HDR Rec. 2020 en JPEG ; JPEG 8 bits, AVIF 10, 32 bits
  seulement en HDR) : voir `docs/SPEC.md`, Formats, HDR, poids, filigrane. Une photo sans
  original ne part que depuis son aperçu dynamique, 2560 px au plus (`depuisApercu`) ; un aperçu
  dynamique ne se retire jamais d'une photo dont l'original manque.
- Une livraison réimportée et empilée va dans le dossier de l'original (`sourceFolder` : Lightroom
  n'empile que là) ; `undo_last` ne la retire pas. Seule la recette retire une photo réimportée
  (`retirerReimportees` : chemin exact réimporté par le module dans la même session, puis le
  fichier à la Corbeille) ; jamais vers un dossier neuf en essai, qui resterait au catalogue.
- La fenêtre de choix du dossier (`choisirDossier`, `runOpenPanel`) s'ouvre dans sa propre tâche :
  la commande répond sans attendre l'utilisateur (40 s au plus, puis `en_attente`).
- `match_series` compare la photo et la référence par la même mesure des tons neutres ; les tons
  suivis d'une passe à l'autre (`Measurements.neutres` avec masque) ne servent qu'aux pentes, et
  Teinte et Température se résolvent ensemble (`PentesSerie`, relevées dans Lightroom). Chaque
  photo repart des pentes relevées.
- Le module signale la photo active changée avec sa réponse suivante (`evenements`, avec son `id`,
  seulement si elle n'est plus celle signalée la dernière fois) ; le serveur le transmet aux
  clients abonnés (`resources/subscribe`), sinon le dit une fois au résultat d'outil suivant
  (Claude Desktop ne s'abonne pas, constaté). Rien ne part sans une commande.
- Une photo hors du film fixe se sélectionne après l'affichage de son dossier, avec un délai
  (`selectionnerAvecSource`, constaté) : passer par lui. De même pour la remettre : après un
  passage au module Développement (débruitage, son annulation, variante), une copie virtuelle ou un
  TIFF réimporté retiré, la source, la photo active et la sélection d'avant reviennent par
  `Bibliotheque.remettreSelection` (sélection refaite pendant `DELAI_SOURCE`, photo active relue,
  « Photo active d'avant non remise » au journal ; constaté le 21 octobre 2026 : sans attendre,
  une autre photo restait active), et la simulation de la liaison l'impose (`S.visiblesSous`). Le
  connecteur n'ouvre un original que
  pour la lecture du boîtier d'une photo Fujifilm, point de mise au point et intention de la prise
  de vue (`cull_photos`, `view_photo`, `--marquer-af` pour l'aperçu de la photo active de la
  fenêtre Claude, `--focus` pour son onglet Focus, et `--boitier` à la main), d'une seule
  ouverture par photo et par processus (aucune pour un avant/après ; `--marquer-af` et `--focus`
  sont deux processus, donc deux ouvertures pour la même photo active, la seconde seulement quand
  l'onglet Focus est montré), en temps borné (`LecteurBoitier`, 2 s, qui remplace
  `LecteurPointsAF` depuis la 1.2 ; et, pour `--marquer-af` et `--focus` lancés par la fenêtre,
  l'alarme de 5 s de `perl`, comme pour `--ecran` jusqu'au correctif 1.3.6) :
  macOS peut faire attendre `open()` sans fin (autorisation d'accès au volume) ; un original
  qui ne s'ouvre pas à temps est sauté, les suivants aussi tant que sa lecture n'a pas fini, puis la
  lecture reprend. Claude ne répond jamais à une demande d'autorisation de macOS.
- L'intention de la prise de vue (`IntentionBoitier`, lue par `LectureBoitier` dans la MakerNote et
  l'Exif : simulation de film, couleur, plage dynamique et sa priorité, tons clairs et foncés,
  compensation, mode, balance, scène) se lit seulement : `view_photo` la donne sur l'aperçu entier
  (`intention_boitier`, avec sa `lecture`), jamais sur un zoom ni un avant/après, et rien n'est
  posé d'office. Un RAW n'en reçoit que la simulation, par son profil Lightroom (`profilLightroom` :
  DCP du catalogue ou Look installé), en première passe, sauf autre style demandé ou guide de style
  contraire ; un JPEG de l'appareil porte déjà simulation, plage dynamique et tons (ne pas les
  refaire) ; une compensation de −0,6 IL ou moins dit une photo voulue sombre, à ne pas remonter
  (seuils de ±0,6 IL provisoires). Recoupé le 20 octobre 2026 sur de vrais RAF (X-H2S, X-T4,
  X-T20), MakerNote lue à la main ; un HEIF de l'appareil n'est pas lu.
- Le point de mise au point dans `view_photo` (Fujifilm, lu par le serveur dans l'original,
  `Boitier.swift`, et placé dans l'image affichée, `PointAF.swift`) : un aperçu entier ou un zoom
  (`region`), jamais un avant/après (`compare`), envoie `point_af = true` à la commande `apercu` ;
  le module décrit alors la photo comme pour les vignettes (`Vignettes.decrireVignette` :
  `chemin_original`, `marque`, `geometrie`) et ajoute `point_af_toujours` (préférence
  `pointMiseAuPoint`), `evaluation` (`Notation.resume`) et, pour le bilan, `etapes_claude`
  (`nombre`, `derniere`) ; le serveur retire `chemin_original`, `geometrie`, `marque`,
  `point_af_toujours` et `etapes_claude` avant de répondre à Claude. Réponse : `point_af` { `x`,
  `y` (dans l'image affichée entière, de 0 à 1, sur un zoom aussi), `dans_la_zone` (zoom
  seulement), `nettete` (autour du point ; sur un zoom, dans le zoom, si le point y tombe),
  `appareil` (« mise au point signalée manquée »), `carre` (s'il est dessiné : « cadre AF rouge,
  point au centre » depuis le correctif 1.3.3, `ToolHandler.cadresAF` et
  `PreviewImages.marquerFocus`, sinon « vert » ou « rouge », puis « sur l'image » ou « sur le
  zoom ») }. Le carré (vert,
  rouge si l'appareil a signalé la mise au point manquée ; côté 6 % du petit côté, liseré sombre ;
  `PreviewImages.marquerPoint`) se dessine avec `af_point = true` (pour noter, ou montrer la mise
  au point) ou si la case « Mise au point » de la section de la liaison du Gestionnaire est cochée
  (`pointMiseAuPoint` de `Preferences.lua`, décochée par défaut) ; sur un zoom (demandé par Dany
  le 20 octobre 2026), seulement si le point tombe dans la zone. Mesures et Vision sont prises
  avant le carré. Un seul lecteur pour `view_photo` (`ToolHandler.lecteurBoitier`), qui lit le
  point et l'intention d'une seule ouverture : une lecture bloquée n'en lance pas d'autres. Les
  consignes de la fenêtre (`Consignes.texte`) ont leur puce :
  « Mise au point montrée ou jugée : view_photo avec af_point = true, sur l'aperçu entier comme sur
  un zoom (region)… ».
- Un masque combiné range chaque composant avec `MaskBlendMode` (0 ajouter, 1 soustraire) ; une
  intersection est une soustraction du composant inversé (`Locaux.combiner`).
- Formes constatées des masques récents (voir `docs/SPEC.md`, Retouches locales) : objet en
  rectangle = `Mask/Polygon` dont les `Points` sont des tables `{X, Y}` ; plage de couleurs =
  `PointModels` « c1 c2 c3 x y 0 », modèle Lab étalonné (`ModeleCouleur`) ; plage de profondeur =
  `Type = 3` et `DepthRange` de 0 à 1 (jamais `DepthMin`/`DepthMax`) ; couleurs ponctuelles d'un
  masque = `LocalPointColors`, des textes de 19 nombres ; dégradé radial = `Mask/CircularGradient`
  avec `Flipped = true` toujours, inversé par `MaskInverted` seul (`Locaux.radial` ; inversé, il
  n'agit que hors de l'ellipse : coins −31 à −69, centre −0,3 sur 255, à −2 IL sans fondu ; non
  inversé, centre −45 ; constaté le 20 octobre 2026), y compris en composant combiné, en copie
  inversée d'`edit_mask` et copié vers une autre photo. La simulation vérifie chacune (pour le
  radial : `Flipped == true` et un `MaskInverted` booléen). La forme d'un radial fait à la main
  n'est pas relevée, ni l'effet d'un radial sans `Flipped`.
- Le dosage de la peau n'existe qu'à un endroit : `Peau` (`Peau.swift` : `parDefaut`, « Peau du
  visage lisse », texture −20 et clarté −10 ; `lite`, « Adoucir la peau (Lite) », −35 et −15 ;
  `intensiteReduite`, `amount` 50 pour un homme ou une personne âgée ; rien pour un enfant ;
  `dosage`, `effetsIntegres`), d'après les fichiers d'Adobe et non son aide (relevés le 20 octobre
  2026, Lightroom Classic 15.6). La description d'`effect` d'`add_mask` et l'invite `portrait`
  reprennent `Peau.dosage` ; `Consignes.lua` y renvoie sans chiffres. Les deux effets intégrés
  viennent après ceux des fichiers (`LocalEffectLibrary`), qui l'emportent. `add_mask` refuse,
  avant tout envoi (proposition comprise : un refus n'envoie aucune commande), un masque de peau
  (`face_skin`, `body_skin` ; en premier composant non inversé, ou en composant qui la garde :
  `Peau.surLaPeau`) au-delà de la dose Lite, intensité comprise, ou à netteté négative, sans
  `smoothing_requested`, qui ne se pose que sur demande de Dany ou de son guide de style
  (`Peau.verifier`, dans `maskParameter`, qu'`add_mask` seul appelle : ni `copy_settings`, ni
  `edit_mask`, ni `match_series`). L'intensité d'un masque (`CorrectionAmount`) est linéaire
  (constaté le 20 octobre 2026, en propositions sur la peau d'un portrait : texture −20 et clarté
  −10 à `amount` 50 rendent la même image, au pixel près, que −10 et −5 à 100 ; de même pour
  « Adoucir la peau (Lite) ») : un constat de rendu, sans règle possible dans la simulation, que
  vérifie l'étape « intensité d'un masque » de `--portrait`. Vision ne dit ni le genre ni l'âge
  d'un visage : Claude juge à l'œil, et dans le doute prend la dose la plus faible.
- Les doses et la forme d'éclaircir et assombrir (méthode du tireur) n'existent qu'à un endroit :
  `Prompts.Tireur` (grandes zones trop claires par un dégradé linéaire, −0,3 à −0,7 IL ; sujet
  éclairci par un radial, +0,2 à +0,4 IL ; bords par un radial inversé, −0,3 IL, −0,5 au plus, en
  ellipse du cadre de rayon 0,7 et de fondu 80, au milieu de la `zone_d_interet` de Vision ; un seul
  `add_mask`, étape « Claude · éclaircir et assombrir »). Les invites `portrait`, `paysage` et
  `noir_et_blanc` les reprennent (`Tireur.methode`), `retouche_pro` y renvoie, et la description
  d'`add_mask` aussi (`Tireur.resume`), car la fenêtre Claude ne lit pas les invites : ses boutons
  Portrait, Paysage et Noir et blanc demandent la méthode sans chiffres, et `Consignes.texte` n'en
  dit rien. Le radial inversé remplace le vignetage après recadrage, jamais les deux (rien si la
  photo porte déjà `PostCropVignetteAmount` ou si le guide de style écarte le vignetage) ; l'étape
  se vérifie par `view_photo` avec `compare = previous_step`. Les doses viennent de la feuille de
  route, sans mesure : ce sont des plafonds. La forme des bords a été relevée le 20 octobre 2026
  sur un seul paysage, radial centré, en propositions à −0,5 IL (rayons 0,6 à 0,75, fondus 50, 80
  et 100 : centre jamais touché, baisse sans marche ; rayon 0,7 et fondu 80 : tiers central
  intact, milieu des bords −16 sur 255, coins −21 à −27 ; fondu 100 : presque tout le cadre ;
  fondu 50 : les seuls coins). L'étape « forme des bords » de la recette la mesure telle que Claude
  la pose (au milieu de la zone d'intérêt, à −0,3 et −0,5 IL : centre intact, ni plaque ni anneau).
  Restent à juger à l'œil cette forme sur un portrait et un intérieur, et le fondu du radial du
  sujet (80 à 100 : ni halo, ni peau écrêtée).
- Le préfixe « Claude · » des noms de masques (serveur) et d'étapes (module) n'est jamais doublé :
  un nom donné qui le porte déjà le perd d'abord.
- Chaque constat fait dans Lightroom (« Constaté dans Lightroom Classic » de `docs/SPEC.md`,
  section Fenêtre Claude comprise) a sa règle dans la simulation de sa suite (`Tests/Lua/Liaison` ou
  `Tests/Lua/Fenetre`) et un test qui échoue sans la correction, même quand il confirme le code (le
  radial inversé) ; et une étape de la recette quand c'est possible. Un constat de rendu (une
  image), que la simulation ne peut pas imiter (la linéarité de `CorrectionAmount`), le dit dans
  `docs/SPEC.md` et a son étape de recette.
- Un aperçu attend le calcul des masques IA (`attendreCalculsIA`) : sinon Lightroom ouvre la
  fenêtre « Mises à jour IA recommandées », qui bloque l'exportation jusqu'à la réponse de
  l'utilisateur. Toute exportation calcule d'abord les réglages IA : `calculerAvantRendu` pour la
  liaison, `photo:updateAISettings` dans `Publication.publier` pour la fenêtre Publication. Ni le
  serveur ni le module ne demandent la permission d'Accessibilité (elle irait à Claude Desktop, au
  terminal ou à Lightroom).
- Les seuils de netteté et de bruit (`DetailMeasurements.seuilFlou` 15, `seuilNet` 35,
  `bruitVisible` 0,6, `bruitFort` 1,5, et depuis la 1.3 `textureMin` 18 et `textureDouteuse` 30 :
  `Detail.swift`), de ressemblance et d'ouverture des yeux
  (`AnalyseVision.swift`) et de l'éclairage mixte (`Eclairage.chromaMax` 12, `seuilMixte` 8) ont été
  relevés sur de vrais aperçus : les mesurer de nouveau avant de les changer. Ceux de la dominante
  et de la saturation sont nommés aussi, sans relevé noté dans le code
  (`PhotoMeasurements.partNeutreMin` 3, `dominanteLegere` 2, `dominanteNette` 6, `chromaTresSaturee`
  60 ; `Measurements.seuilChroma` 3). Le tri et les plafonds de note (`Notation.plafond`) les
  reprennent sans en ajouter ; `analyze_photos`, l'éclairage et le bilan les reprennent aussi, avec
  leurs propres seuils (puces suivantes). Au tri, une pile de Lightroom compte comme une rafale
  (seule sa meilleure vue échappe au plafond de 3 ★). Le tri (`cull_photos`) mesure les vignettes
  du cache de Lightroom (commande `vignettes`) et ramène leur netteté à celle d'un aperçu exporté
  (`thumbnailSharpnessFactor`, relevé ; le 21 octobre 2026, le tri donnait encore 11 à 23 % de plus
  que l'aperçu, en classant pareil : gardé). Vision ne s'appelle pas en grand parallèle
  (`concurrentPerform` l'a bloqué) : deux photos à la fois au plus.
- L'éclairage (`Eclairage.swift` : `mesures › eclairage` de `view_photo` ; forme courte dans
  l'avant/après, les propositions et `analyze_photos`) se lit sur les tons presque neutres pris
  autour du gris ; quand une dominante globale en écarte le point neutre de l'image (médiane a*, b*
  de ses tons peu saturés) de plus de `toleranceNeutre` (10), autour de ce point ramené de 10 vers
  le gris (`Eclairage.centrer`) : une borne absolue (C* < 12) ne lisait plus aucune case sous une
  autre balance (0 sur 9 pour le portrait à 3 200 K, constaté le 20 octobre 2026). Par zone tonale
  et par case 3 × 3, visages à part (leur peau, et la lumière autour) ; deux groupes de cases
  écartés de `seuilMixte` (8) ou plus font un éclairage mixte, avec `balance_proposee` sur la
  lumière des visages ou du sujet, par les pentes de `match_series` (`ToolHandler.balanceProposee`,
  depuis la réponse brute d'`apercu`). `chromaMax` 12 et
  `seuilMixte` 8 relevés le 20 octobre 2026 sur les 8 copies d'essai (`--eclairage`) : seul le
  portrait à deux lumières ressort (9,8), les autres de 2,2 à 7,1 ; à 15 et au-delà, des objets
  colorés pris pour des gris font de faux mixtes. Avec la tolérance, relevé le 21 octobre 2026
  (`--eclairage`, à la balance de la photo et avec `--essai`) : l'œil tenu à la balance de la photo
  (portrait 9,7, les autres de 2,1 à 7,1) et à 6 500 K ; sous une dominante forcée extrême, la
  mesure peut perdre une lumière (portrait à 3 200 K : 4,6) ou en inventer une (intérieur à la
  lampe à +30 : 11,4) : son conseil dit « à confirmer à l'œil ». `toleranceNeutre` (10), choisie
  hors de Lightroom sur cinq aperçus, est la seule valeur essayée à ce relevé (son commentaire la
  dit encore à relever) ; `seuilTonal`, `partMinGroupe` et `pixelsMinPeau` restent provisoires.
  Mesure en 123 à 199 ms par photo à ce relevé.
- **La dominante de toute l'image** (24 octobre 2026, signalée par Dany : XH2S0312.RAF, un portrait à
  l'ombre des feuillus, balance auto du boîtier 5 150 K et +29, que Retouche pro n'avait réchauffé
  que jusqu'à 5 750 K et +16) : les tons presque neutres (`Measurements`, C* < 15) n'en gardent que
  les pixels déjà gris (b* −3, « légèrement froide », quand le chandail blanc était à −30 et le
  gravier à −23). `PhotoMeasurements.pointNeutre` reçoit le point neutre de l'éclairage
  (`MesureEclairage.neutre`, posé par `view_photo` et `mesurerImage`, gardé avec la vue) ; au-delà
  de `Eclairage.toleranceNeutre` du gris, `couleur › dominante_globale` le dit (`dominanteGlobale`,
  `lectureDominanteGlobale`) et la lecture des tons neutres y renvoie ; l'aperçu entier y ajoute
  `conseilDominante` (la balance proposée d'un seul coup est retirée le 25 octobre 2026 : Claude en
  tirait des chiffres timides, 6 400 K et +14, qui laissaient le gravier bleu). Pour un grand
  écart, les pentes de `PentesSerie` dépassent la cible (ce portrait : 6 968 K et +2 viraient au
  vert, la pipette sur le gravier à 7 881 K et −2 au jaune-vert ; 7 000 K et +28 le laissaient
  neutre) : `white_balance_point` avec `{scene: true}` (`mesurerScene`) prend le point neutre de
  toute l'image, sans les refus du point (chroma, brûlé, noir), et apply_settings le remesure en
  seconde passe (essai sur « XH2S0312 (Essai ombre) » des Essais : 6 890 K et +1, puis 7 054 K et
  +31, gravier a* 3,7, b* −1,2, défait ensuite) ; puis `validerParLAuto` (« deux passes et l'Auto »,
  choix de Dany du 25 octobre 2026) rend l'Auto de Lightroom en proposition (`essayer`, à
  `analysisSize`), mesure son point neutre de même et le pose (« … : balance, Auto de Lightroom »)
  s'il est plus près du gris d'au moins `margeAuto` (`balance_point › gardee`). Les deux se trompent
  tour à tour : l'Auto rendait neutre le gravier de XH2S0312 (Copie 3) que 6 400 K et +14 laissaient
  bleu, mais virait au magenta sur XH2S0310 (cheveux gris a* 8,7, b* −7,5 contre 2,7 et −3,3 pour
  Claude) ; sur l'Essai ombre, la balance mesurée (à 4,8 du gris) l'emportait sur l'Auto (6,7). Les
  valeurs de l'Auto ne se relisent qu'une fois la photo affichée dans le module Développement
  (sinon « auto (calculé quand… ) ») : le rendu mesuré seul compte. Les écarts de tonalité avec
  l'Auto (XH2S0310 : exposition +0,10 contre +0,45, ombres +53 contre +25, noirs −19 contre −5) sont
  un rendu plus plat, pas une erreur. Le bilan compare aussi `dominante_globale` ; quand
  elle se rapproche du gris d'au moins `regressionDominante`, une dominante accentuée sur les tons
  suivis passe dans `a_verifier` (ils reprennent la couleur de leur objet). Seuil et conseil
  provisoires, à éprouver sur d'autres scènes (sable, intérieur à la lampe, coucher de soleil).
- Le bilan de `view_photo` (`Bilan.swift`) compare l'aperçu entier au précédent de la même photo à
  la même taille d'aperçu, et au premier de la session (`depuis_le_debut`) : `vuesMesurees` de
  `ToolHandler`, rangé par `Bilan.Cle` (photo et taille), gardé pour le processus du serveur comme
  `dernierTri` (30 au plus, `Bilan.photosGardees`) ; une autre taille repart de zéro et le dit
  (même état à 1 024, 1 344 et 2 048 px : netteté jusqu'à 10 % d'écart ; deux vues de suite à la
  même taille : les mêmes 43 mesures ; constaté le 20 octobre 2026). Jamais une proposition contre
  une vue gardée (le même jour, une proposition sans changement s'écartait d'une vue jusqu'à
  0,9 point d'écrêtage ; mesurées depuis par le même chemin, l'écart qui reste est à relever) :
  une proposition avec `compare` (`preview_settings`, `add_mask` avec `preview`) et `view_photo`
  avec `compare` ont leur propre bilan, sur deux images rendues par la même commande ; netteté et
  bruit seulement entre deux vues. Toute image se mesure par un décodage et la réduction à 512 px
  (`ToolHandler.mesurerImage`, comme `analyzeScaled`). Les tons neutres ne se suivent qu'à cadre
  égal (`Bilan.cadre`). Une annulation (`etapes_claude` en baisse, que `Rendu.apercu` donne en
  lecture seule) ou un calcul IA en attente ne donne pas de « regression » : elle passe dans
  `a_verifier`. Un zoom refait sur la même zone a son `bilan_zone`, sans alerte (`zoomsMesures`,
  6 par photo, 30 photos). Seuils de visibilité repris de `match_series`, de
  `Measurements.seuilChroma` et de `Detail` ; seuils de régression relevés le 20 octobre 2026 en
  propositions (écrêtage, un canal, couleurs très saturées : 2 points de plus et 1,5 fois l'avant ;
  ombres bouchées : 2 points de plus, une nuit n'alerte pas d'elle-même ; dominante des tons
  neutres : |a*| ou |b*| qui s'éloigne de 0 de 2) ; ceux de la netteté et du bruit
  (`baisseNetteteMin`, `hausseBruitMin`, `ecartNettetePct`, `ecartBruit`…) restent à relever (étape
  « bilan chiffré » de la recette).
- L'écran principal du Mac (`Ecran.swift`) se lit par CoreGraphics et ColorSync, sans AppKit ni
  permission (environ 44 ms) ; l'en-tête ICC se lit dans les octets du profil
  (`ColorSyncProfileCopyHeader` rend ses signatures à l'envers, « lppa » pour « appl », constaté le
  20 octobre 2026). Six classes (`Ecran.Etalonnage`) : un profil d'usine (`FactoryProfiles`, tiré
  de l'EDID, rangé dans `/Library/ColorSync/Profiles/Displays` et refait à chaque branchement), un
  profil standard du système et un profil fait à l'œil ne sont jamais « mesurés », et la balise
  `meas` n'est pas un indice (`sRGB Profile.icc` du système la porte) ; `mesure` ne vaut vrai que
  pour un profil qui nomme un logiciel de sonde, ou dont la balise `vcgt` vient d'un créateur autre
  qu'Apple, et reste inconnu (« étalonné ? ») pour un autre profil personnalisé. Aucun vrai profil
  de sonde n'est encore relevé. **Plus rien sur l'étalonnage** depuis le correctif 1.3.6 (décision
  de Dany du 25 octobre 2026 : il n'achètera jamais de sonde) : ni Dany ni Claude n'en entendent
  parler. Le classement (`Ecran.Etalonnage`, `mesure`, `Ecran.texte`) ne sert plus qu'à
  `mcp-developpeur --ecran`, pour le développement (`Ecran.json`, sans la clé `detail` :
  `Ecran.detail` et `Ecran.reglageProfil`, le seul conseil d'une sonde, sont retirés avec le
  voyant). Seul
  `main.swift` pose `Ecran.lire` (les outils de `serve` et de `--call`, et la recette pour son étape
  « écran nommé ») ; seul `get_status` le lit, et ne dit que les noms (`Ecran.nommer` :
  `ecran: { nom, autres }`, `autres` seulement s'il y en a ; ni profil, ni chemin, ni `etalonnage`,
  `mesure`, `texte`, date ou logiciel), sa description seulement « ecran : le nom de l'écran
  principal du Mac. » ; `--status` dit les noms seuls. Retirés : la remarque « écran non mesuré » du
  premier aperçu d'un processus (`Ecran.remarque`, `ToolHandler.ecranSignale`, `outilsAvecApercu`,
  `ajouterRemarqueEcran`, `remarqueEcran` : les aperçus ne lisent plus l'écran), et dans la fenêtre
  Claude le voyant Écran (`Vues.voyantEcran`, `TAILLES.voyantEcran`, `Fenetre.poserEcran`,
  `montrerEcran`, `texteEcran`, `etatEcran`, `Lightroom.etatEcran`, `decrireEcran`, `ECRAN_*` : la
  fenêtre ne lance plus `--ecran`) et la section « ## Écran » de `Consignes.texte`.
  `ServerInfo.instructions` n'en a jamais parlé. `EcranTests` vérifient qu'aucune description
  d'outil ni `ServerInfo.instructions` ne parlent de sonde ou d'écran non étalonné, et qu'aucun
  aperçu ne lit l'écran (`testAucuneRemarqueDEcranAuxApercus`).
- Une longue série passe par le `ContexteAppel` de l'outil : `avancer` (de `ToolHandler`) après
  chaque lot (progression envoyée au client, reprise dans la réponse d'attente, et barre de
  progression de Lightroom par la commande `progression`, fermée à la fin de l'appel par
  `fermerBarre`), `verifier` avant chaque lot (annulation par `notifications/cancelled`, sans
  réponse ; croix de la barre de Lightroom, `ArretDansLightroom`, avec une réponse).
- Une photo qui porte `RemoveAreas` (outil Supprimer à détection d'objet) est lue par là, et
  `RetouchAreas` en est dérivé : les taches de Claude vont dans les deux (`preparerTaches`). Une
  tache Supprimer de Claude est toujours `fill_method = 'patchmatch'`, jamais générative.
- Les positions des masques et des taches se donnent dans l'image que montre `view_photo` ;
  `Geometrie.lua` les ramène dans le repère du fichier. Toute nouvelle position passe par lui.
  Ce repère est celui d'avant la correction d'objectif, Upright et la perspective : le serveur
  calcule une grille de recalage sur deux rendus (`Recalage.swift`, commande `geometrie`), que
  `Geometrie.lua` interpole ; toute commande qui place des positions la demande
  (`Tools+Recalage`).
- Upright, la perspective et la distorsion manuelle laissent des coins vides dans le cadre : toute
  écriture qui touche la géométrie ou le cadre d'une photo redressée coche « Contraindre le
  recadrage » (`preparerContrainte`), qui fait resserrer le cadre par Lightroom ; le cadre est
  mémorisé avant (Lightroom le change sans qu'on l'écrive) et relu après (`relireCadres`). Un
  cadre demandé se calcule dans la zone que la grille de recalage dit remplie (`Geometrie.zone`) ;
  demandé avec Upright, il se place ensuite (`a_recadrer`, commande `recadrer`, qui complète la même
  étape). Les rendus du recalage décochent la case. Voir `docs/SPEC.md`, Contraindre le
  recadrage.
- Le catalogue des réglages (noms, plages, libellés) n'existe qu'à un endroit :
  `Sources/DeveloppeurKit/Catalogue.swift`. Le serveur envoie au module les plages et les
  libellés de chaque commande ; le module ne connaît que les plages de la température et de la
  teinte, qui dépendent de la photo (kelvins pour un RAW, relatives pour un JPEG).
- Le standard de notation n'existe qu'à un endroit : `Notation.standard`
  (`Sources/DeveloppeurKit/Notation.swift`). La ressource `developpeur://notation`,
  `propose_ratings` avec `read_standard` et l'invite `noter` le reprennent ; Claude Code dans la
  fenêtre ne lit ni les ressources ni les invites (`--tools ""`, `--disable-slash-commands`) : il
  l'a par `read_standard` seulement (ses consignes l'y renvoient) ; l'invite `noter` (la sélection
  par défaut) sert à Claude Desktop et à Claude Code en terminal.
  `Notation.plafond` en tire les plafonds de `cull_photos` (0 et rejet proposé pour une photo
  floue, une mise au point manquée, ou des yeux fermés quand une autre vue de sa rafale ou de sa
  pile les a ouverts, `PhotoTriee.yeuxOuverts`, `autreVueYeuxOuverts` ; la règle de la rafale,
  correctif 1.3.4 : sinon 2, à vérifier, la seule vue de son moment ne se jetant pas pour un
  clignement, et le tri d'une seule photo, la note d'abord de la fenêtre, n'en rejette jamais ;
  3 pour une photo douce ou qui n'est pas la
  meilleure de sa rafale ; 2, à vérifier, pour une photo presque noire ou brûlée, ou une mise au
  point manquée sur une texture faible, 1.3 ; 1 pour une capture), que `dernierTri`
  (`ToolHandler`) garde pour le processus du serveur ; sans défaut, aucun plafond sous 5 (« aucun
  défaut mesuré : pas de plafond », correctif 1.3.2). Une scène sur fond noir voulu (L* médian 3,9)
  reste dite « presque noire » : à revoir, hors de la 1.3.
- **Claude note de 0 à 5 ★, jamais un libellé de couleur sans demande** (correctif 1.3.2, demandé
  par Dany le 22 octobre 2026 : « si moi je veux une photo 5 étoiles, je placerai un code de
  couleur ») : `propose_ratings` refuse une note hors de 0 à 5 avant tout envoi
  (`Notation.noteMaximale = 5`, 4 jusqu'à la 1.3.1), et le module la refuse encore
  (`Notation.NOTE_MAX_PROPOSEE = 5`) ; la passe 4 (monter à 5, après le développement) se propose
  comme les autres. Le standard (section « Les coups de cœur »), les descriptions de
  `propose_ratings` et de `color_label` (`set_metadata`), les invites `noter` et `tri_seance`,
  `ServerInfo.instructions` (« libellé de couleur : sur sa demande ») et `Consignes.texte` (« De 0 à
  5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa demande. ») disent que les coups de
  cœur de Dany sont un libellé de couleur qu'il pose lui-même : Claude n'en propose, n'en pose ni
  n'en change jamais sans sa demande explicite. La carte offre « Accepter 5 ★ » (`Fenetre.noteDeCinq`
  et `Fenetre.PAS_CINQ` retirés). `set_metadata` pose toujours une note de 0 à 5 à la demande de
  Dany, comme Changer… et les étoiles de la carte Note. Jamais `set_metadata` pour une note sans
  demande. `propose_ratings` (titre « Noter des photos »)
  n'est plus en lecture seule depuis la 1.1.1 (hors de `readOnlyTools` : avec `apply`, il écrit
  dans le catalogue) ; il valide toutes les propositions avant d'envoyer quoi que ce soit (les clés
  de chaque élément à la main : `parametresInconnus` ne voit que le premier niveau), refuse une
  note au-dessus du plafond du dernier `cull_photos` sans `to_check`, et envoie une seule commande `notation`
  (`action = 'proposer'`, plus `poser` avec `apply = true`), absente de `LightroomBridge.lectures`
  (rejouée, elle remettrait les propositions « à vérifier »). Plus de `session` ni de
  `read_session` (Séance de notation retirée) ; `pass` est la passe du standard.
- Le registre des notes proposées (`Notation.lua`) sert la liaison (commande `notation` :
  `proposer`, `lire`, et depuis la 1.3 `remettre`, la recette seulement, jamais un outil, qui remet
  une proposition telle que lue avant une étape, ou la retire ; rien dans le catalogue, sauf
  `proposer` avec `poser`) et la carte Note de la fenêtre Claude. Il se charge dans les deux
  simulations : `Bibliotheque` n'est requise qu'au moment d'écrire, et rien de l'interface (un test
  le vérifie). Il est rangé dans `notation.json`
  (`Chemins.racine()`, format 2 : les propositions seulement ; un registre plus ancien perd ses
  séances à la relecture), propre au catalogue ouvert (chemin gardé ; un autre catalogue trouve un
  registre vide), les photos en clés texte (`Json.decode` rend des clés texte), chacune avec son
  uuid (une photo d'un autre uuid perd sa proposition) ; tout ce qui en sort vers une vue est une
  table neuve. Toute nouvelle proposition commence « à vérifier » (état `a_verifier`, depuis la
  1.1.1) : Dany l'accepte ou la change ; `to_check` (champ `a_verifier`) dit en plus que Claude
  doute ; l'état `proposee` ne reste que pour les propositions d'avant la 1.1.1.
  `Notation.resume` en tire l'évaluation que `view_photo` donne (« pas encore évaluée », « 3 ★
  proposée par Claude, à vérifier », « acceptée par l'utilisateur : 3 ★ », « changée par
  l'utilisateur : … »). La fenêtre s'abonne (`Notation.abonner('fenetre', …)`) et compare
  `Notation.version`. Le registre ne voit pas une annulation (undo_last, ⌘Z : constaté le
  20 octobre 2026) : quand la fenêtre relit la note et le drapeau de la photo active
  (`Fenetre.majPhoto`), elle appelle `Notation.recaler(releves, version)`, avec `Notation.version`
  lue avant la photo (un relevé plus vieux qu'une note posée entre-temps, ou fait pendant une
  écriture de `Notation.poser`, ne défait rien) : une proposition acceptée ou changée dont la note
  n'y est plus redevient `a_verifier`, à accepter ou changer de nouveau ; mais une note posée puis
  annulée sur une photo qui avait déjà cette note reste « acceptee » (constaté le 21 octobre 2026
  par la recette : `recaler` n'y voit rien), d'où `remettre` dans la recette. L'élément `notation`
  du fil (appel de `propose_ratings`) ne sert qu'à l'affichage : le registre reste la source.
- Une proposition ne devient une note posée que par `Notation.poser`, puis `Bibliotheque.noter` :
  une écriture (`ecrire`) par lot de 500 photos, une étape « Claude · notation » par photo que
  `undo_last` défait, mémoire `Bibliotheque` gardée ; garde-fous des photos (`verifierProtection` :
  copies virtuelles seulement, libellé protégé, photos rejetées) maintenus. Deux chemins :
  Accepter, Changer…, les étoiles et les drapeaux de la carte Note (`Fenetre.poserEtoile`,
  `Fenetre.poserDrapeau` ; Retenir ou retirer un drapeau ne décide pas la proposition, Rejeter si),
  dans une tâche, jamais pendant que Claude travaille ni pendant une note en cours (refus dits au
  bandeau), où
  `depuisLightroom` et `confirme` lèvent la pause, « Proposer d'abord » et le plafond de photos
  par écriture (le clic vaut accord explicite) ; ou Dany demande à Claude « note ces photos » ou
  « pose les notes » (`propose_ratings` avec `apply = true` : `Notation.proposer` avec `poser`,
  puis `Notation.poser` avec `depuisLightroom = false` et `confirme = true`, « à vérifier »
  comprises), où la pause de la liaison l'arrête, mais ni « Proposer d'abord » ni le plafond (la
  demande explicite vaut accord ; l'accord dans Lightroom, `accordDansLightroom`, se demande
  encore : son refus dit de rappeler `propose_ratings` avec `apply = true`, car `Notation.poser`
  passe `outil` à `Bibliotheque.noter` ; `rappel` dans `Ecriture.lua`). Réponse : `posees` (et
  `erreur_pose`) ; le titre de l'élément du fil dit « Notes à poser » pendant l'appel, puis
  « Notes posées » si au moins une l'est, sinon « Notes non posées » (pause, accord attendu), et
  chaque photo « posée » ou « non posée : <raison> ». Une note posée ainsi n'entre pas dans l'état
  d'avant Claude (`memoriser` sans `fusionnerOriginal`) : « Revenir à « Avant Claude » » et
  `revert_to_original` la laissent en place ; `undo_last` la défait toujours, étape par étape.
  Accepter pose la proposition telle quelle : un rejet pose le drapeau sans toucher les étoiles,
  une note ne retire qu'un rejet déjà posé (un drapeau Retenue reste). Laisser (« Laisser à N ★ »)
  écarte la proposition par `Notation.decider` `ecartee`, sans rien écrire au catalogue.
- Dans la fenêtre Claude, toute photo que Claude traite, il la note d'abord, avant d'y toucher
  (puce Notes de `Consignes.texte`, demandé par Dany le 20 octobre 2026) : `cull_photos` sur elle
  (plancher technique ; sans `photo_ids`, `selection`, `collection` ni `folder`, il prend la photo
  active par la commande `etat` depuis la 1.3.1, car Claude l'oubliait 2 fois sur 4 ; sans photo
  active, le refus « Photos à traiter » ; `contact_sheet`, lui, demande toujours une série), `view_photo` avec `af_point = true`, puis `propose_ratings` sans `apply` ;
  sa note arrive « à vérifier » dans la carte Note, où Dany l'accepte, la laisse ou la change
  (Accepter, Laisser, Changer…, les étoiles). Une photo déjà évaluée (`view_photo` : `evaluation`)
  ne se renote pas, sauf s'il le demande. Ni Noter ni Évaluer : ni dans les invites, ni dans la
  carte Note (`Fenetre.noter`, `Consignes.noterPhoto` et `Consignes.noterSelection` retirés) ;
  « ? À vérifier » est posé grisé, sans action (`Vues.inactif`, décision de Dany du 21 octobre
  2026 ; `Fenetre.verifierNote` reste nil ; le remettre comme « remettre à vérifier » par
  `Notation.decider` est une question ouverte), et les essais le vérifient ; l'aide de la carte
  Note (`Fenetre.AIDE_NOTATION`) le dit. Les consignes du connecteur (`ServerInfo`, Claude Desktop) ne
  demandent pas cette note d'abord.
- Ports fixes 54770 (commandes) et 54771 (réponses), sur 127.0.0.1 : `Liaison.lua` et
  `LightroomBridge` doivent rester d'accord (`DEVELOPPEUR_PORT` côté serveur pour essayer un autre
  port). Le serveur ouvre une connexion par commande : Claude Desktop, Claude Code et la fenêtre
  Claude se succèdent sur la même liaison, chacun avec le jeton du même fichier
  (`LightroomBridge.fromEnvironment`).
- Liaison fermée (1.2) : chaque ligne du serveur porte le `jeton` privé de la liaison, ping compris.
  Le module en tire un à chaque démarrage, avant d'ouvrir les prises (`Liaison.preparerJeton` :
  32 octets de `/dev/urandom`), le garde en mémoire et l'écrit d'un coup dans `liaison.jeton`
  (`~/Library/Application Support/Developpeur/`, droits 600 : fichier provisoire créé sous
  `umask 077`, écrit par `io.open`, rangé par `mv`, relu), qu'il vérifie toutes les 5 s
  (`Liaison.garderFichierJeton`). Sans jeton, aucune prise ne s'ouvre : liaison en erreur, voyant
  rouge avec son aide. `Liaison.recevoir` vérifie le jeton avant `Commandes.executer`, donc avant
  la pause et « Proposer d'abord », sur toute sa longueur ; un refus répond `code: "jeton"` sans
  emporter l'événement de la photo active, et se note au journal une fois par 10 s et par genre.
  `depuisLightroom` est retiré des paramètres reçus du réseau : seuls les menus, la fenêtre de la
  liaison (« fenêtre de suivi » jusqu'au correctif 1.3.6) et la carte Note le posent, par appel direct (toute nouvelle voie interne reste un appel direct,
  jamais une ligne TCP). Le serveur relit le fichier à chaque connexion (`JetonLiaison.lire`), une
  fois de plus après un refus, ne le crée jamais et ne dit jamais sa valeur (`--status`, `get_status`
  et le diagnostic du Gestionnaire n'en disent que l'état) ; sans fichier, il n'envoie pas de jeton,
  et un module 1.1.1 accepte la ligne. La simulation de la liaison n'imite que les deux commandes du
  système du jeton (`LrTasks.execute`) et refuse toute autre. Constaté le 21 octobre 2026 par
  l'étape « liaison fermée (jeton privé) » de la recette : une commande sans jeton, ou avec un autre
  jeton, refusée ; restent à constater l'aléa lu et les droits 600 dans Lightroom, les refus par
  `nc` et `curl`, et un ancien serveur refusé (`docs/SPEC.md`, Liaison fermée).
- `apply_settings` respecte le mode « Proposer d'abord » du module (refus sans `confirm = true`) ;
  ne pas contourner. La fenêtre Claude suit la clé `mode` des préférences du module, que seul le
  Gestionnaire de modules externes règle (les radios du Mode sont retirées au correctif 1.3.6), et
  la dit dans l'infobulle du voyant Lightroom.
- **Jamais l'API** : la fenêtre Claude passe par Claude Code et la connexion claude.ai.
  `relais.sh` retire de l'environnement les clés d'API et les autres fournisseurs
  (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, Bedrock, Vertex) ; ne jamais
  lire ni copier les jetons de connexion de Claude Code.
- Lightroom ne sait pas tenir un processus par ses tuyaux : `relais.sh`, lancé par
  `LrTasks.execute`, garde Claude Code ouvert pour une conversation (`entree.jsonl` passé par
  `tail -f`, `sortie.jsonl` relu par le moteur) et le ferme quand Lightroom n'est plus là. Claude
  Code ne reçoit que le connecteur (`connecteur.json`, `--strict-mcp-config`, outils
  `mcp__developpeur__*`, `Conversation.PREFIXE_OUTILS`), aucun outil intégré (`--tools ""`), rien
  qui demande une permission, ni compétences ni réglages de l'utilisateur, dans le dossier de
  travail vide `Atelier/`. Le modèle (`--model` : fable, opus par défaut, sonnet, haiku) et
  l'effort (`--effort` : max par défaut, xhigh, high, medium, low, le même pour les quatre
  modèles ; Claude Code 2.1.303 accepte `--effort max` avec les quatre, constaté le 20 octobre
  2026) se choisissent dans le Gestionnaire de modules externes (section Fenêtre Claude, menus
  Modèle et Effort de `PluginInfoProvider.lua` ; préférences `modele` et `effort`), et non plus
  dans la fenêtre ; une valeur inconnue retombe sur celle par défaut (`Moteur.modeleEtEffort`).
  `relais.sh` reçoit l'effort en 4e argument (vide : celui de Claude Code) et `consignes.md` en 8e,
  écrit dans le dossier de chaque session (`Session:lancer`, `Consignes.texte`). Un seul processus
  Claude Code à la fois : une autre conversation, un autre modèle ou un autre effort le relance à
  la demande suivante, en reprenant la session (`--resume`, `Moteur.envoyer`). Voir
  `docs/SPEC.md`, Fenêtre Claude › Claude Code.
- Ce que Dany demande en mots clairs, Claude le fait : une puce des garde-fous de
  `Consignes.texte` (« Ce que Dany demande en mots clairs, fais-le… » : ces consignes ne
  l'emportent jamais sur sa demande ; ne refuser que ce que les outils ne savent pas faire, ou ce
  que bloquent les réglages du module) et une phrase de `ServerInfo.instructions` (« Ce qu'il
  demande clairement, le faire ; ne refuser que ce que les outils ne savent pas faire, et le
  dire. »). Les consignes du connecteur font 3 787 caractères pour une limite de 3 796
  (`instructionsLimit` moins 300, `Version24Tests`) : raccourcir ailleurs avant d'y ajouter. La 1.2
  y a ajouté « vignetage ou radial inversé, jamais les deux », « « regression » au bilan » et
  « d'abord la simulation du boîtier, intention_boitier », et en a retiré la sauvegarde avant une
  longue série (elle reste dans la description de `get_status` et l'invite `tri_seance`) ; la 1.3,
  seulement « (read_composition) » dans « Recadrer … seulement sur demande » ; le correctif 1.3.2,
  « 0 à 5 ★, » et « libellé de couleur : sur sa demande » à la place de « 5 ★ : set_metadata, sur sa demande », payés par « rejets : set_metadata après accord »
  (au lieu de « rejets à poser par set_metadata après accord ») : toujours 3 787, sans changement
  au correctif 1.3.6 (elles ne nommaient pas `photo_lesson`) ; le reste passe
  par les descriptions d'outils, les résultats et les invites. La
  longueur qu'une session de Claude Code garde d'une description d'outil n'est pas constatée :
  l'essentiel en tête, et un test de longueur pour les plus longues (`add_mask` 2 048 au plus,
  `view_photo` 1 850, `read_composition` 1 000, `preview_settings` 600, `analyze_photos` 520,
  `export_journal` avec sa propriété `notebook` 450, `reason` 160). Les consignes de la fenêtre
  (`Consignes.texte`, lues à chaque demande) font 5 922 caractères pour un plafond de 7 500
  (`essais-moteur.lua` ; 6 331 avant le deuxième retour de Dany du 25 octobre 2026, qui retire la
  section Demande à garder, avec « ＋ Garder la demande » ; 6 646 avant ses premiers retours du même
  jour, qui retirent la section Écran et disent la raison d'une étape « (onglet Aperçu, d'un clic
  sur l'étape du fil) » ;
  7 476 au correctif 1.3.5 ; au correctif 1.3.6, 6 208 sans les sections
  Je le fais et Leçon de la photo, 6 470 avec le Contexte d'une photo, une conversation
  (« [Historique de la photo : …] », « [Depuis la dernière fois : …] » ou le résumé d'un groupe),
  6 646 avec la fin d'une retouche par `view_photo` avec `compare = before_claude` (Fin d'une
  tâche, pas dans une [Demande rapide] : le rendu reproductible) ; 7 466 avant la puce Notes du
  correctif 1.3.2, « De 0 à 5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa
  demande. », 7 489 avant la section Demande à garder de Mes demandes) : la 1.3 y avait mis ses
  sections Composition, Je le fais, Raison de chaque étape et Leçon de la photo, et la puce
  Carnet ; ce qui dépasse va aux descriptions d'outils.
- Le presse-papiers ne se lit que sur un clic de l'utilisateur (bouton 📋, `presse-papiers.js`) ;
  les essais passent par un presse-papiers nommé, jamais le vrai.
- Toute table donnée à Lightroom par la fenêtre (éléments d'une liste, d'un menu, réglages
  d'exportation, valeur d'une propriété) est neuve : jamais une table relue par `Json.decode`
  (métatable, Lightroom bloque ; la simulation de la fenêtre la refuse).
- La fenêtre ne peut pas changer de structure une fois ouverte, et une vue masquée garde sa place :
  tout ce qui varie passe par des propriétés liées (`bind`) et des variantes superposées de même
  taille (`place = 'overlapping'`). `visible` lié ne masque qu'une vue simple (texte, bouton,
  image, menu, champ, case, liste, séparateur) et un `f:view` (constaté le 21 octobre 2026, D10) :
  sur `row`, `column`, `group_box`, `tab_view` et `scrolled_view`, Lightroom l'ignore (constaté le
  20 octobre 2026 : les trois onglets de la 1.1 s'affichaient superposés), et la simulation de la
  fenêtre refuse ces cinq-là. Une condition de visibilité passe toujours par `F.egal`, `F.non`,
  `F.si` ou `F.condition`, que `F.et` combine en une liaison à plusieurs clés (`keys`,
  `operation`). Le contenu d'un onglet se crée par une fabrique masquable (`Vues.masquable(f, F,
  condition)`, depuis `variante` de `Dispositions.lua`) : la condition sur chaque vue simple,
  combinée avec son propre `visible` ; seule la variante montrée répond (constaté, D11) ; pas de
  `group_box` dans un onglet, jamais `visible` sur la colonne d'une variante. Une propriété liée a
  une valeur avant l'ouverture (les tests le vérifient, pour chaque clé d'une liaison à plusieurs
  clés). `save_frame` garde la taille d'une ouverture à l'autre (`Fenetre.cadre()` :
  `DeveloppeurClaude-conversation-grande-<FORME>`, `Fenetre.FORME` 5 depuis le correctif 1.3.6
  (1 623 × 1 200, sans le volet), 4 pour 1 948 × 1 200, 3 pour 1 497 × 1 200, 2 pour la fenêtre B
  de 1 280 × 800, 1 avant) : quand le contenu change de taille, augmenter `Fenetre.FORME`.
- **La fenêtre B** (1.3, maquette « B · Conversation claire » ; `docs/SPEC.md`, Fenêtre B),
  agrandie à la demande de Dany le 21 octobre 2026 (1 497 × 1 200, constaté à l'écran, puis
  1 948 × 1 200, élargie de 20 % à gauche, 40 % au centre et 20 % à droite), puis sans son volet de
  gauche ni son filet au correctif 1.3.6 (décision de Dany du 25 octobre 2026) : fenêtre de
  1 623 × 1 200, contenu de 1 621 × 1 166 (D7 : barre de titre de 33, marge de 1 sauf en haut,
  constaté) ; centre 1 064, droite 556, filet de 1 ; aperçu 498 × 332 (vignette en 2x de
  996 × 664) ; des lignes de fil d'environ 150 caractères (choix de Dany, gardé).
  `Dispositions.TAILLES` est la seule table des tailles, et `Dispositions.dimensions()` en tire le
  reste : `D.lignes` (42 lignes de 21) se calcule de la hauteur, comme les cartes
  (`D.placeCartes` 720 ; carte Note de 583, les autres de 679 ; `criteres` 33, `propLignes` 42 (40
  avant le correctif 1.3.6, avec la ligne d'état d'un exercice), `etapeLignes` 40, `focusLignes`
  42 (`suiviLignes` est parti avec l'onglet Suivi) : le plus de lignes qui laisse 12 points sous le
  contenu, ce que vérifie `essais-fenetre-b.lua`). Les cartes Proposition, Aperçu (étape) et Focus
  (▲ ▼ seulement) descendent comme la
  carte Note jusqu'à leur rangée de boutons, posée sous elles au bas du panneau : ▲ ▼ à gauche,
  les boutons à droite, en carrés de bezel 26 et titres en 13 (`carteEtRangee` de `Vues.lua` ;
  demandé par Dany le 21 octobre 2026). Elle
  a été vue dans Lightroom le 21 octobre 2026, à 1 497 × 1 200 puis à 1 948 × 1 200 (capture
  `docs/capture.png`, essai réel de la 1.3), et par Dany le 25 octobre 2026 à 1 623 × 1 200 (son
  essai de la 1.3.6, d'où ses retours ; pas encore après eux). `Fenetre.lua`
  garde l'état, les rafraîchissements, les actions et la boucle ; les pièces sont dans `Vues.lua` ;
  l'assemblage, les dimensions, les images (`Dispositions.IMAGES`) et les apparences dans
  `Dispositions.lua` : ni `require 'Fenetre'` ni couleur créée à leur chargement (`liens.lua` les
  charge sans `LrColor`), couleurs, polices et actions arrivent par `F`. Une seule disposition, sans
  réouverture ni menu des conversations ; chaque ouverture a sa génération (`Fenetre.generation`) ;
  les conversations des anciennes séances de notation restent sur le disque, jamais montrées, et
  `Moteur.montrer` et `Moteur.ouvrir` les refusent.
- Contrôles de la fenêtre B, d'après les constats du 21 octobre 2026 (blocs A à D d'un module
  d'essai, dans `docs/SPEC.md` ; chacun a sa règle dans `Tests/Lua/Fenetre/Simulation.lua` et son
  essai) : fonds et filets en aplats (`Vues.aplat`, un `f:picture` sans image à
  `background_color`, A4 ; `background_color` est sans effet sur `row`, `column`, `view`,
  `group_box` et la fenêtre, A1 et A5 ; `primary_line_color` aussi, A6) ; images de
  `Dispositions.IMAGES`, un PNG 2x chacune, toujours avec `width` et `height`, chemin par
  `Fenetre.image` (jamais `images/<nom>.png` en dur) ; tout clic sur une image passe par un calque
  (`Fenetre.calque`, registre `Fenetre.parCalque` : un `mouse_down` sur un `f:picture` ne reçoit
  rien, C1 ; un calque n'a pas d'`enabled`, son gestionnaire vérifie l'état) ; tout bouton passe par
  `Fenetre.bouton` (`push_button`, ou `square_button` avec `carre` ; `icone` par `image_name`, sans
  titre, B3 ; `bezel` : cadre = bezel + 2, D5) ; les boutons bleus sont des images
  (`Vues.boutonBleu` : Envoyer, Accepter, Accepter N ★ ; image enfoncée 0,15 s) ; un élément de la
  maquette sans fonction est posé grisé, sans action (`Vues.inactif`, « À venir ») ; texte riche
  `<EM>` toujours avec `emphasis_font`, l'emphase de la même taille que le texte, `text_color` et
  `emphasis_color` ensemble, ni entité ni balise seule (B1, D4) ; `Fil.largeur` ignore les
  balises, `Fil.couper` les ferme et les rouvre ligne par ligne, les textes venus de Claude les
  perdent.
- Le champ de demande est `immediate = false` (Retour le valide). Aucun bouton par défaut dans la
  fenêtre (constaté D1 : Retour dans « Rechercher », `immediate = true`, déclencherait aussi le
  bouton par défaut) : Retour passe par l'observateur du champ et l'envoi automatique (0,3 s) ;
  Envoyer est un bouton bleu en image sous calque, Arrêter un carré superposé, montré pendant le
  travail. Tout bouton (`Fenetre.bouton`, `F.bouton` dans les pièces, `square_button` compris :
  `S.BOUTONS` des essais) et tout calque annulent l'envoi automatique (un clic valide d'abord le
  champ, constaté D3), et les essais le vérifient pour chacun : un `f:push_button` créé à part
  enverrait la demande tapée.
- Mise en page de la fenêtre B (le détail pièce par pièce : `docs/SPEC.md`, Fenêtre B) : deux
  colonnes, le centre et la colonne droite ; le volet de gauche est retiré au correctif 1.3.6
  (« ＋ Nouvelle conversation », Rechercher, la liste des conversations en cases,
  `Fenetre.casesListe` et `Fenetre.pageListe`, Renommer…, Supprimer…, Publication… et Consommation…, qui restent au
  menu Module externe - Extras, les versions et le voyant Écran ; images `loupe` et `selection`
  retirées) ; sept invites en carrés. L'étiquette « Style » est devant son menu, sous le champ,
  comme dans la maquette (décision de Dany après le lot B3, qui remplace le « sans étiquette » du 20 octobre
  2026), puis le menu Mes demandes (280 ; voir la puce Mes demandes) ; pas de menu Modèle (Modèle
  et Effort sont au Gestionnaire de modules externes). Deux voyants en pastilles PNG dans
  l'en-tête : Claude Code et Lightroom (`voyantClaude` 125, `voyantLightroom` 150, `ecartVoyants`
  14 ; plus de voyant Mode, et le voyant Écran, passé d'abord du volet à l'en-tête, est retiré avec
  l'étalonnage : puce de l'écran), puis la photo active (`D.info`, le reste de la rangée) et, au
  bout de la rangée, en haut à droite sous « Repartir à neuf », le bouton Suivi (`Vues.boutonSuivi`,
  carré small, titre « Suivi » en petit, `TAILLES.boutonSuivi` 56 ; `Fenetre.ouvrirSuivi` : puce
  La fenêtre Suivi). L'infobulle du voyant Lightroom
  (`Fenetre.infobulleLightroom`, une seule ligne) dit la liaison, les versions du module et du
  connecteur (`Composants.lignes`) et le mode de la liaison ; il passe à l'orange quand l'une des
  versions est à mettre à jour ou le connecteur introuvable (`Fenetre.alerteVersions`). Plus de
  rangée Mode (correctif 1.3.6 : les radios, `Fenetre.modeMontre`, `modeAuto`, `reposerMode` et
  `changerMode` sont retirés) : la fenêtre suit la préférence `mode` du Gestionnaire, relue à
  chaque tour ; à sa place, à droite du titre, « Repartir à neuf » (carré de bezel 22,
  `D.repartir` 120 dans `D.placeRepartir` 320 ; puce Une photo, une conversation). Le titre, en
  gras 16, est celui que Claude donne, sans Renommer. Le bandeau : deux lignes de petit texte
  (`Fenetre.LIGNES_BANDEAU`, `Fenetre.texteBandeau`, « … » au bout de la seconde), l'infobulle
  donne le texte entier ; tout message nouveau de la fenêtre passe par une constante, tient en deux
  lignes et entre dans l'essai « Bandeau » d'`essais-fenetre-b.lua`.
- Le fil B est une grille de `D.lignes` lignes de 21 (`Vues.ligneFil`, `Fil.lua`) : la colonne
  auteur de 60 (« Vous », « Claude », l'heure, posés par `Fil.lignes` sur des copies, jamais dans
  le cache), un écart de 12, le texte de 952 (`D.texteFil`, `Fenetre.largeurTexte`), coupé d'après
  la chasse mesurée (`Metriques.lua`) ; ne pas y insérer de vues de hauteur variable. Les genres à
  icône sont en retrait de 20 (`Fil.RETRAITS`) ; la ligne d'un appel (genre `appel`) est un texte
  riche, le nom en Menlo 11 (`Fil.uneLigneOutil`), et les autres variantes lisent le texte sans
  balise (`transform`) ; une ligne d'étape prend toute la largeur du texte (« Pourquoi ? », un carré
  small de 80 à son bout, `q..i`, `Fenetre.pourquoi`, `D.pourquoi` et `Fil.PLACE_POURQUOI`, est
  retiré par les retours de Dany du 25 octobre 2026 : un clic sur la ligne en tient lieu) ; le tour
  de Claude qui a noté finit par sa ligne d'actions (`x..i` : `note`, « ☆ Voir la note », seul ;
  « Leçon de la photo » est retirée au correctif 1.3.6, et « ＋ Garder la demande », au bout de la
  ligne après une retouche, avec le suffixe `+demande` de `x..i`, `Fil.valeurActions`,
  `Fil.lireActions` et `Fenetre.lireActions`, au deuxième retour de Dany du même jour). Une
  conversation vide montre son titre et l'aide (`Fenetre.lignesAide`, des lignes d'aucun élément),
  et le résumé de la fenêtre vient toujours en dernier, sous la conversation (puce Le résumé en bas
  du fil). Un élément `historique` (correctif 1.3.6)
  reprend le genre `note` (ⓘ sur sa première ligne, ses puces « •  » en retrait), sans auteur ni
  heure, et clôt le tour de Claude d'avant ; une demande faite par la Demande rapide porte sous son
  texte la ligne « Demande rapide » (`Fil.MENTION_RAPIDE`). Le fil ne montre que la conversation
  (plus de page Carnet de progrès, `Fenetre.vue`). Un clic sur une ligne se répartit dans l'ordre
  image, étape, sinon détail de l'outil (`Fenetre.sorteDeClic`, `Fenetre.clics` ; puce du clic sur
  une étape ou une image). Les lignes d'image disent ce que fait le clic : « Aperçu de Claude ·
  cliquer pour le voir, avec son pourquoi », « Avant / après · cliquer pour le voir », « Photo
  jointe 1 · cliquer pour la voir » (`Fil.lignes`).
- **Mes demandes** (demandé par Dany le 22 octobre 2026 ; `docs/SPEC.md`, Mes demandes) : un
  `popup_menu` à droite du menu Style (`Vues.mesDemandes`, `TAILLES.mesDemandes` 280 ; le bandeau
  garde 324), ses éléments refaits en tables neuves (`Fenetre.elementsMesDemandes` : titre « Mes
  demandes », valeur `Fenetre.MENU_TITRE` ; chaque demande « Nom — description » coupée à la
  largeur du menu, `Fenetre.titreDemande` ; Ajouter…, Renommer…, Supprimer… ; sans demande,
  « Aucune demande gardée » grisé ; `{ separator = true }` et `enabled = false` relevés dans
  `AgViewUtils.getPopupMenu`, la simulation les vérifie, `S.refusElements`, `S.choisir`). Sa
  valeur passe par `Fenetre.lierRadio` (un choix, même du titre, annule l'envoi automatique) et
  revient à son titre ; une demande choisie va dans le champ, jamais envoyée
  (`Fenetre.mettreDemande` : `saisie` posée sous `Fenetre.ignorerSaisie`), grisé pendant que Claude
  travaille. Retour l'envoie : le champ passe par `Fenetre.lierSaisie`, dont le `transform` lance
  l'envoi d'une demande mise et non changée (`Fenetre.demandeMise` ; supposé : Lightroom pousse la
  valeur du champ à Retour sans changement). Ajouter…, Renommer… et Supprimer… : petites fenêtres
  modales dans une tâche, refus en direct (`Stockage.refusDemande` : nom vide, nom pris sans tenir
  compte des majuscules ni des accents, texte vide) et bouton d'action grisé par `actionBinding`,
  rouvertes sur un refus après le clic. Rangées par `Stockage.lua` seul (section Mes demandes) dans
  `mes-demandes.json` de `Chemins.racine()` : écrit d'un coup, relu à chaque ouverture et avant
  chaque changement, illisible mis de côté avant la première écriture (jamais écrasé), trié par
  nom ; `uninstall.sh --tout` le retire. Ajouter… est pré-rempli du texte du champ, sans nom
  proposé. « ＋ Garder la demande » est retiré au correctif 1.3.6 (deuxième retour de Dany du
  25 octobre 2026, accepté tel quel) : la ligne « Demande à garder : « … » » que Claude écrivait à
  la fin d'une retouche, la section « ## Demande à garder » des consignes, `Fenetre.garderDemande`,
  `Conversation.demandeAGarder`, `Conversation.estRetouche` (qui ne servait qu'à elle),
  `Conversation.preparerDemande`, `Conversation.LIGNE_DEMANDE`, `Stockage.nomLibre`,
  `D.garderDemande` et `D.ecartActions` ; une ligne « Demande à garder » d'une conversation d'avant
  reste un texte de Claude comme un autre. Essais : `essais-mes-demandes.lua` (qui vérifie aussi
  que ces noms ont disparu).
- Les cartes (Note, Proposition, Aperçu, Focus) sont des colonnes superposées sur leurs
  images (carte-note, carte-proposition, carte-etape, carte-focus ; carte-lecon et carte-suivi
  retirées au correctif 1.3.6), le texte à 472 en
  12 points (`CARTES` : police `texte12`, emphase `gras12` pour la note et Focus ; une
  carte sans emphase perd ses balises), coupé par `Fil.lignesCarte` (`Fenetre.lignesCarte` en est
  l'alias ; la fenêtre Suivi et les légendes en grand s'en servent aussi) et montré page par page
  (`Fenetre.montrerPage` ; ▲ ▼ de `Vues.fleches`, propriétés `<cle>Monte` et `<cle>Descend` pour
  `note`, `proposition`, `etape` et `focus`) ; un nouveau texte revient à sa première page.
- **Les onglets** (retours de Dany du 25 octobre 2026) : quatre segments en images sous calques
  (`Vues.segments`, `Fenetre.choisirSegment`), dans l'ordre de `Dispositions.ONGLETS`, seule liste
  (valeur, titre, image ; `Dispositions.gabarits` la donne en `segments` à
  `scripts/images-fenetre.swift`, qui en tire l'ordre et les bouts arrondis et refuse « aucun
  segment » et un segment en double) : `focus` (62), `notation` (Note, 57), `apercu` (72, l'étape et
  les images du fil, l'ancien Pourquoi ?) et `proposition` (98), clé `onglet` ; plus de Suivi
  (devenu une fenêtre) ni de Leçon. La fenêtre s'ouvre sur Focus (`D.ongletParDefaut` `'focus'`,
  même avec une proposition en attente ; les images comptées sont remises à zéro à l'ouverture : une
  image arrivée fenêtre fermée n'est pas une arrivée) et y revient chaque fois que la conversation
  montrée change pour une autre photo choisie, ou un groupe (`Fenetre.revenirAFocus`, depuis
  `Fenetre.suivreSelection` ; ni pour Obtenir, ni pour « Repartir à neuf », ni case Autre photo
  décochée) : une bascule de la fenêtre, qui lit la photo active (`Fenetre.apercuOnglet.focus`) ; une
  proposition qui y attend déjà ne reprend pas la main (`Fenetre.propositionVue`). Bascules
  d'elle-même, une par arrivée (`Fenetre.choisirOnglet`, sans le crochet d'un vrai clic) : une image
  de Claude (`view_photo`, une comparaison : `Fenetre.imageDeClaude`) vers Aperçu
  (`Fenetre.rafraichirApercu`, puis `Fenetre.voirImageDuFil(chemin, true)` : l'aperçu montre l'image
  et suit les suivantes, la carte le pourquoi de l'étape qui la précède) ; une proposition vers
  Proposition (celle d'« Obtenir » comprise ; son image aussi, jamais Aperçu) ; une note pour la
  photo active vers Note ; une photo jointe par Dany ne change pas d'onglet. Les règles « jamais vers
  Aperçu » et « jamais vers Focus » sont tombées avec ces retours. `Fenetre.surOnglet` ne suit qu'un
  vrai clic ; ses crochets et ceux de
  `Fenetre.apercuOnglet` sont appelés sous `pcall` hors d'une tâche, sous `LrTasks.pcall` dans une
  tâche (`LrTasks.canYield`). L'aperçu,
  commun aux quatre onglets, appartient à l'onglet (`Fenetre.apercuOnglet`, demandé d'abord par
  `rafraichirApercu` ; nil : l'aperçu commun) ; une image du fil montrée (`Fenetre.imageCliquee`)
  reste prioritaire jusqu'à un autre onglet, une image nouvelle, une autre conversation ou un clic
  sur une étape. Le changement d'onglet d'un clic sur une ligne d'image, puis l'image posée,
  supposent des observateurs de propriétés synchrones (comme `Fenetre.choisirOnglet`) : pas encore
  constaté dans Lightroom.
- La carte Note B (`Vues.notation`) : les étoiles cliquables (`Fenetre.poserEtoile`), les drapeaux
  (`Fenetre.poserDrapeau`), « ? À vérifier » grisé, « Claude propose » en petites étoiles (0 à 5),
  la grille des critères (`Fenetre.lignesCriteres`, clés `ng..k`, `ne..k`, `nt..k` ; la passe de
  Claude dans son en-tête), puis la rangée du bas : ▲ ▼, « Voir à 100 % » (`Vues.voirZoom` ;
  décision de Dany du 21 octobre 2026 : `Conversation.dernierZoom`, le dernier zoom de
  `view_photo` avec `region` sur la photo dans la conversation, montré dans l'aperçu par
  `Fenetre.voirZoom`, sans Claude ni Lightroom ; grisé sans zoom), « Laisser à N ★ », Changer… et
  « Accepter N ★ » en bleu (`peutAccepterNote`), jusqu'à « Accepter 5 ★ ». Plus de rangée
  « Passes : » ni de ligne du plafond sous son filet (correctif 1.3.2, demandé par Dany le
  22 octobre 2026 : `Vues.passes`, `Fenetre.PASSES`, `Fenetre.etatPasse`, `notePasse`,
  `Vues.lignePlafond`, `Fenetre.textePlafond`, `aPlafond`, `plafondTexte`, `filetPlafond` et les
  images coche-10, chevron-passe et avertissement retirés) : la grille des critères a leur place
  (`TAILLES.autourNote` 137, carte Note de 583, `criteres` 33), le plafond reste au registre et
  dans le critère Plancher technique.
- L'apparence claire ou sombre (préférence `apparence` de `Chemins.defauts`, `claire` ; menu
  Apparence du Gestionnaire de modules externes, dite par le diagnostic ; une valeur inconnue
  retombe sur `claire` à l'emploi, `Dispositions.apparence`) : `Dispositions.PALETTES` est la seule
  table des couleurs (images et `Fenetre.COULEURS`), reprise à chaque ouverture
  (`Fenetre.preparerApparence`) ; deux jeux d'images, `images/` et `images/sombre/` (tableau
  Commandes, Images de la fenêtre) ; l'image « aucun aperçu » est `images/vide-498x332.png` et sa
  version sombre (`vide-320.png` est retirée) ; la palette sombre se lit au moins aussi bien que
  la claire (`essais-images.lua`) ; les contrôles natifs suivent l'apparence de macOS. Les polices
  sont celle du système et Menlo 11, mesurées par `scripts/metriques.swift` (D9 : l'encre fait 1 à
  2 points de moins que la chasse ; `Fenetre.largeurLibelle` ajoute 2 points à un libellé fixe).
- **Un clic sur une étape ou une image du fil** (l'ancien Pourquoi ? ; retours de Dany du
  25 octobre 2026, `essais-pourquoi.lua`) : un clic sur une ligne d'étape (`Conversation.estEtape`,
  `Conversation.OUTILS_ETAPES`) ouvre l'onglet Aperçu, son avant/après dans l'aperçu et sa raison
  dans la carte (`Fenetre.clics.etape`, `Fenetre.montrerEtape`) ; un clic sur une ligne d'image
  aussi (`Fenetre.voirImageDuFil` : l'onglet change d'abord, puis l'aperçu montre l'image et la
  carte le pourquoi de l'étape qui la précède dans le fil, `Fenetre.etapeAvant` et
  `Fenetre.choisirEtapeDeLImage`, sans la suivre ; un classement, `set_metadata` ou
  `manage_collections`, est sauté : le pourquoi est celui de la retouche qui a fait l'image ; sans
  étape avant elle, `Fenetre.SANS_ETAPE_IMAGE`). L'image d'une proposition et une photo jointe par
  Dany ne sont faites par aucune étape (`Fenetre.imageDeClaude` faux) : la carte dit ce qu'elles
  sont (`Fenetre.texteSansEtape` : `SANS_ETAPE_PROPOSITION`, `SANS_ETAPE_JOINTE`), au clic comme par
  ◀ ▶, jamais le pourquoi du tour d'avant ; l'image de la proposition qui attend ouvre l'onglet
  Proposition, où sont sa raison et Accepter (`Fenetre.voirPropositionDuFil`), décidée ou close
  elle s'ouvre dans Aperçu. Devant une image du fil, ◀ ▶ vont d'une image à l'autre et la carte
  suit (`carteSuitImage`) ; Voir l'avant, ou ◀ ▶ de la carte, repassent à l'avant/après de l'étape.
  « Voir à 100 % » de la carte Note garde l'onglet Note (`Fenetre.montrerImageDuFil`).
  `Fenetre.etape` désigne l'élément par son id,
  remis à nil quand la conversation change ; l'aperçu passe par `Fenetre.apercuOnglet.apercu` (◀ ▶
  coupés devant une étape) ; les images se lisent par `Etapes.images` dans une tâche, réduites par
  `Images.vignette`, gardées par étape (`Fenetre.imagesEtapes`) et relues quand `Etapes.version`
  change ; Agrandir passe par `Fenetre.agrandirDeux` ; `Etapes.actifPour = Fenetre.etapesActives`,
  posé par `Fenetre.afficher` ; une conversation de la 1.2 se relit dans `detail`
  (`Conversation.infoEtape`) ; `Stockage` écrit `etapes`, `annule` et `revenu` en tableaux. La carte
  sans étape garde son titre « Pourquoi ? » (`Fenetre.TITRE_ETAPE`) et son aide dit de cliquer une
  étape (`Fenetre.AIDE_ETAPE`) ; la consigne de la raison dit « (onglet Aperçu, d'un clic sur
  l'étape du fil) ». Sous la carte (`Vues.etape`) : ▲ ▼, ◀ ▶ et Voir l'avant / Voir l'après
  (`titreBascule`) ; Détail… (l'appel de l'outil et sa réponse : `D.detail`, `Fenetre.detailEtape`,
  la clé `etapeADetail`) est retiré au deuxième retour de Dany du 25 octobre 2026.
- **Agrandir** (retours de Dany du 25 octobre 2026 ; 1 100 × 740 jusque-là) : l'image en grand
  remplit `Fenetre.GRANDE` (2 000 × 1 250, qui laisse la barre de titre et Fermer de la fenêtre
  modale sur l'écran de 3 440 × 1 440 de Dany : environ 1 330 de haut en tout), sous chacune de ses
  formes, la photo active, la vignette Focus, une image du fil ou de la proposition, une image
  d'étape seule (`Fenetre.agrandirUne`, une seule fonction pour les quatre), et l'avant et l'après
  côte à côte, les deux ensemble avec leurs titres et la légende (`Fenetre.agrandirDeux`, place par
  `Fenetre.cadreDeux`, pure, sans plafond à 1 : 994 de large au plus par image, `ECART_DEUX` 12,
  `ECART_TITRE` 4, `ECART_LEGENDE` 8, une ligne de 16 d'après `Metriques`, une image illisible sur
  `LARGEUR_ILLISIBLE` 200 ; une légende longue réduit la hauteur des images). `Images.grande`
  remplit toujours la place à ses proportions (deuxième retour de Dany du même jour, qui voyait la
  vignette de secours de Focus, 320 × 213, à sa vraie taille : minuscule) : une image plus grande
  est réduite, une plus petite agrandie par `sips` (un peu plus douce ; 300 × 200 donne
  1 875 × 1 250), rangée dans `.vignettes` à côté ; une image qui a déjà la taille garde son propre
  fichier ; illisible, « Aperçu illisible ». La photo active (Focus, l'aperçu de la photo active) se
  redemande en grand au clic (`Fenetre.agrandirActive`, dans une tâche ; `Fenetre.preparerGrande`) :
  une vignette de `Fenetre.TAILLE_GRANDE` (2 048, le plafond de `Vignettes`) ; refusée (juste après
  une retouche), un rendu par `Rendu.rendre`, le chemin des aperçus de `view_photo`
  (`Fenetre.rendreActive`, copié dans `PhotoActive/Grande-…`), sauf pendant que Claude travaille
  (`Moteur.travaille`) ou qu'une commande de la liaison est en cours ou a fini depuis moins de
  `Lightroom.DELAI_LIAISON_LIBRE` (5 s) (`Lightroom.liaisonOccupee`, d'après `Liaison.enCours`,
  compté par `Liaison.recevoir` de la vérification du jeton à `apresCommande` ou `abandonner`, même
  en erreur, une ligne refusée non comptée, et `Liaison.finCommande` : Claude Desktop ou Claude Code
  en terminal, que `Moteur.travaille` ne voit pas ; le rendu se mêlerait à leurs commandes) ; sinon
  l'image du panneau, agrandie. Comme un aperçu de `view_photo`, ce rendu calcule d'abord les
  réglages IA (`calculerAvantRendu`), fait passer `isExported` à vrai et note la photo
  `apercuSeulement` (écriture privée, rien dans Édition › Annuler). La grande image se redresse
  (puce suivante), puis se marque comme celle du panneau : les cadres de Focus (`Images.lireFocus` :
  un `--focus` de plus, donc une ouverture de plus de l'original au clic), le carré des autres
  onglets (`Fenetre.marquerMiseAuPoint`) ; son dossier s'efface à la fermeture. La vignette du
  panneau reste à `TAILLE_PHOTO_ACTIVE` 1 024 (le cache rend plus grand, 1 720 pixels pour un RAW,
  constaté le 17 octobre 2026) ; les images d'étape font 1 024 (`Etapes.COTE`) et remplissent leur
  moitié. Pas encore vu dans Lightroom (ni le rendu lancé depuis la fenêtre, ni la netteté d'une
  image agrandie) ; essais avec le vrai `sips` dans `essais-integration.lua`, purs dans
  `essais-dispositions.lua`, la photo active et Focus dans `essais-focus.lua` (`Rendu` y est
  remplacé : `Rendu.lua` ne se charge pas dans la simulation de la fenêtre, sans `LrApplicationView`).
- **Une vignette de la photo active toujours à l'endroit** (`Images.rotationManquante`, pure, et
  `Images.redresser` ; deuxième retour de Dany du 25 octobre 2026) : sur XH2S0407.RAF (Copie 1),
  4160 × 6240, juste après une retouche, la vignette de secours de Focus
  (`Fenetre.TAILLE_SECOURS_FOCUS`, 256) était couchée (320 × 213 : le fichier avant le quart de tour
  de Lightroom), et l'image de Focus et d'Agrandir aussi ; aucune vignette de Lightroom ne porte de
  balise d'orientation, et les autres sont tournées (1 146 × 1 720, 573 × 860, 520 × 780 : relevé le
  même jour dans `Temporaire/PhotoActive`). Une vignette se compare à la photo telle que Lightroom
  l'affiche (dimensions, orientation et cadre de `Vignettes.decrireVignette`, par
  `Geometrie.contexte` et `Geometrie.apercu`, à `Images.ECART_PROPORTIONS` près, 0,08 en
  logarithme) : debout au cadre actuel, elle reste ; couchée au cadre, elle se tourne du quart de
  tour de son orientation (BC : `sips -r 90`, DA : `sips -r 270`) ; sinon elle se compare à la photo
  entière, sans le cadre (la vignette de secours peut dater d'avant la retouche qui vient de
  recadrer la photo, en 4:5 par exemple) : couchée et plus près que debout, elle se tourne, debout
  elle reste. Un demi-tour (CD) ne se voit pas aux proportions et reste. Elle se redresse avant
  d'être montrée ou marquée, partout où la fenêtre prend une vignette de la photo active : l'aperçu
  commun (avant `--marquer-af`), Focus (la vignette de secours comprise, avant `--focus`) et
  Agrandir. Le connecteur ne tourne rien : il dessine dans l'image affichée sur les pixels reçus.
  Reste à constater dans Lightroom : `sips -r` sur une vraie vignette couchée, et que la vignette de
  secours date bien d'avant la retouche. Essais : `essais-focus.lua` (une photo verticale simulée,
  sa vignette de 256 couchée).
- La leçon et « Je le fais » dans la fenêtre sont retirés au correctif 1.3.6 : l'onglet Leçon,
  l'action « Leçon de la photo » du fil, la case Leçon du Gestionnaire (`leconFinRetouche`),
  « [Sans leçon] » (`Consignes.sansLecon`), les sections Leçon de la photo et Je le fais des
  consignes, le bouton « Je le fais » / « J'ai fini » de la carte Proposition, le suivi de
  l'exercice (`Fenetre.suivreExercice`, `Lightroom.valeurs`) et `Consignes.jeLeFais` et
  `Consignes.jaiFini`.
- La composition dans la fenêtre : `preview_settings` avec un `crop` (sauf `reset`) est une
  proposition de recadrage (`Conversation.cadreDemande`, `Conversation.cadreLu`, seule copie du
  libellé : `Conversation.LIBELLE_RECADRAGE`) ; la carte dit « Cadre : <résumé> » ; un vrai clic sur
  l'onglet Proposition remontre son image (`Fenetre.montrerImageProposition`) ; Ajuster… offre
  `Consignes.ajustementsCadre`.
- **La fenêtre Suivi** (`FenetreSuivi.lua`, retours de Dany du 25 octobre 2026 ; d'abord l'onglet
  Suivi, à la place de Leçon, au correctif 1.3.6) : le carnet de progrès, que montrait la page
  Carnet de progrès du fil (`Fenetre.vue` `'carnet'`, `Fil.lignesCarnet`, `Fil.tableauCarnet`,
  retirés avec le volet), dans une fenêtre à part, « Claude · Suivi » (`FenetreSuivi.TITRE`, cadre
  `DeveloppeurCarnet`), comme Publication et Consommation : ses contrôles sont ceux du système (ni
  aplat ni image, l'apparence de macOS), toute table donnée à Lightroom est neuve. Seul le bouton
  Suivi de l'en-tête l'ouvre (`Fenetre.ouvrirSuivi`, `FenetreSuivi.afficher` ; ouverte, elle passe
  devant ; pas d'entrée au menu Module externe - Extras). Elle montre le résumé du carnet du
  catalogue ouvert, ses constats seulement, page par page avec ▲ ▼ (`FenetreSuivi.LARGEUR` 600,
  `LIGNES` 36, en 12 et ses passages balisés en gras 12, `Fil.lignesCarte`) : `Fil.texteSuivi`
  d'après `Carnet.resumer`, seule source des phrases (la note, les défauts mois par mois sur leur
  ligne, libellé en `<EM>`, puis Ce qui progresse et À travailler) ; un résumé illisible fait un
  texte qui le dit. Le résumé se lit dans une tâche (`FenetreSuivi.lire`, `LrTasks.pcall`) à
  l'ouverture, puis chaque fois que le registre change (`Carnet.version`, abonnement `suivi`, relu
  par sa boucle, `FenetreSuivi.suivre` ; désabonnée à sa fermeture). « Photos d'un défaut… » (actif
  s'il y a des défauts) choisit un défaut (`FenetreSuivi.choisirDefaut`) puis ouvre la fenêtre de
  ses photos (`FenetreSuivi.montrerDefaut` : tables neuves, leurs constats seulement) et « Retirer
  du carnet… » (`FenetreSuivi.retirerDuCarnet`, appel direct à `Carnet.commande`, jamais une ligne
  TCP ; son message en bas de la fenêtre). La fenêtre Claude n'a plus ni l'onglet ni sa carte
  (`Vues.suivi`, `CARTES.suivi`, segment `seg-suivi`, `carte-suivi`, `D.ongletSuivi`,
  `D.suiviLignes`, `D.photosDefaut`, son abonnement `fenetre` au carnet et sa lecture dans la
  boucle). « Demander à Claude ce qu'il en pense › » (`Consignes.carnet`) est retiré : une
  conversation sans photo. Seul l'onglet est devenu une fenêtre : la case Carnet du Gestionnaire,
  `carnet.json`, `Carnet.lua` et le carnet d'`export_journal` gardent leur nom ; « fenêtre de la
  liaison » (`Suivi.lua`) reste distincte. Les graphiques du carnet et l'ajout de chaque photo au
  carnet viendront au correctif 1.3.7. Essais : `essais-carnet.lua`.
- L'aperçu montre la photo active (légende en texte riche : le nom et sa copie, l'appareil, la date
  de prise de vue, lus par `Lightroom.legende` seulement quand la photo active change, à l'heure
  locale) à l'ouverture de la fenêtre (même déjà ouverte : menu Ouvrir la fenêtre Claude ou ⌃⌥C) et
  quand une autre photo devient active (`Fenetre.majPhoto`, `Fenetre.idActif`, `Fenetre.voirActive` ;
  demandé par Dany le 20 octobre 2026) : sa vignette vient du cache d'aperçus de Lightroom
  (`Vignettes.demander`,
  `requestJpegThumbnail`, dans une tâche), dans un dossier à elle sous
  `Chemins.temporaire()/PhotoActive` (l'ancien s'efface), réduite au cadre par `Images.vignette`,
  refaite à chaque ouverture. Juste après une retouche, Lightroom refuse la vignette de 1 024 (« error
  loading thumb ») : comme Focus, elle se redemande une fois par seconde, `ESSAIS_VIGNETTE_FOCUS`
  fois, puis à `TAILLE_SECOURS_FOCUS`, redressée et marquée, notée de secours
  (`Fenetre.apercuActif.secours`, deuxième retour de Dany du 25 octobre 2026 : l'aperçu restait vide,
  Agrandir grisé) ; la grande se redemande à un rafraîchissement suivant,
  `Fenetre.DELAI_SECOURS_ACTIVE` (10 s) au moins après la dernière demande (la fin de chaque demande
  rafraîchit l'aperçu : sans ce délai, elle en relancerait une autre sans fin), et un échec relance
  le délai. Une image nouvelle de la conversation montrée (`Fenetre.nbImages`)
  la remplace (une image de Claude ouvre en plus l'onglet Aperçu : puce Les onglets) ; ◀ revient
  aux images de la conversation, ▶ depuis la dernière y retourne ; un clic sur une ligne d'image
  relit les images d'abord, puis ouvre l'onglet Aperçu sur la sienne. Les onglets montrent toujours
  la photo active de Lightroom : la photo d'une ancienne conversation choisie dans la liste
  (`Fenetre.photoDeLaConversation`, `Lightroom.photo`, correctif 1.3.3) est retirée avec la liste
  au correctif 1.3.6.
- Sur la vignette de la photo active d'un fichier Fujifilm (marque, ou original `.RAF`), le carré
  de mise au point est dessiné avant la réduction (`Fenetre.marquerMiseAuPoint`, demandé par Dany
  le 20 octobre 2026) : `Images.marquerMiseAuPoint` lance par `LrTasks.execute` le connecteur de
  `cheminConnecteur` (s'il existe), `mcp-developpeur --marquer-af <original> '<géométrie JSON>'
  <vignette.jpg> <sortie.jpg>` (géométrie de `Vignettes.decrireVignette`) ; `PointAF.marquer` lit
  le point dans l'original en temps borné, le passe dans l'image affichée et écrit `<nom>-af.jpg`
  à côté de la vignette, carré vert, rouge si l'appareil a signalé la mise au point manquée ;
  code 1 sans point (l'aperçu reste sans carré, sans rien au journal). Autre marque : pas d'appel,
  l'original n'est pas ouvert. La vignette est redressée avant (`Images.redresser`) ; la
  description de la photo se lit une fois pour les deux (`Fenetre.decrireActive`). Agrandir
  redemande la photo en grand, puis la marque de même (puce Agrandir).
- **L'onglet Focus** (demandé par Dany le 22 octobre 2026 ; `docs/SPEC.md`, Onglet Focus), le
  premier des onglets depuis les retours de Dany du 25 octobre 2026 (entre Aperçu et Proposition
  avant ; clé `focus`, `D.ongletFocus`, segment de 62) : la photo active comme le
  module Focus-Points la montre (v4, Apache 2.0, installé, lu seulement : jamais y écrire ; ses
  étiquettes et la mise à l'échelle des visages viennent de `FujifilmDelegates.lua`, citées dans
  SPEC). Côté connecteur, `MiseAuPointBoitier` (`Focus.swift`) lit, de la même ouverture que le
  point et l'intention, FocusMode, AFMode, PrioritySettings, FocusSettings, CropMode, DriveSettings,
  SequenceNumber, FocusWarning, ImageStabilization, visages et éléments du sujet (positions dans
  le repère de FocusPixel) ; les réglages groupés par `Tiff.Entree.mot`, quel que soit le type
  rangé ; ses textes en français n'existent que là (`lignesImage`, `lignesPriseDeVue`,
  `lignesMiseAuPoint`). La taille du cadre AF (`Focus.tailleCadreAF`) : le carré de 4 % du petit
  côté de Focus-Points pour un point unique, un suivi ou un point sans taille lue (constaté le
  22 octobre 2026 : le modèle d'une case de 1/13 du grand côté pour la taille 6 était trois fois
  trop grand) ; l × h cases de 1/13 du grand côté pour une zone, provisoire. Côté module (`Fenetre.lua`, section Focus) : la fenêtre s'ouvre sur
  Focus et y revient quand une autre photo choisie montre sa conversation (`Fenetre.revenirAFocus`,
  une bascule par `Fenetre.choisirOnglet`, qui lit la photo active par
  `Fenetre.apercuOnglet.focus` ; jusqu'à ces retours, seulement un vrai clic) ; un onglet caché ne
  lit rien ; la lecture dans une tâche (`Fenetre.lireFocus`), une à la fois : `Lightroom.infosFocus`
  (getFormattedMetadata clé par clé, jamais groupé), `Vignettes.demander`, puis pour un fichier
  Fujifilm (`Fenetre.estFujifilm`, la règle du carré) `Images.lireFocus` (`perl` et son alarme de
  5 s, comme `--marquer-af`) ; la réponse décodée ne sert qu'à faire du texte (`Fil.texteFocus`), jamais
  donnée à Lightroom ; le résultat gardé pour la photo (`Fenetre.focus`, refait à chaque ouverture,
  son dossier effacé), relu par un vrai clic seulement si la géométrie ou l'édition (editCount,
  lastEditTime : une retouche) a changé, et à la fin d'un tour de Claude si l'onglet est montré
  (`Fenetre.suivreFocus`, depuis la boucle ; constaté le 22 octobre 2026 : après « Retouche pro »,
  l'onglet montrait la photo d'avant) ; après une retouche, tant que Lightroom n'a pas refait
  l'aperçu, il répond « error loading thumb » à une vignette de 512 px ou plus mais rend celle de 256
  (constaté le même jour, plus d'une minute après) : la vignette se redemande une fois par seconde,
  `Fenetre.ESSAIS_VIGNETTE_FOCUS` (3) fois, puis à `Fenetre.TAILLE_SECOURS_FOCUS` (256), sans
  signature (la grande se relit au clic suivant ou à la fin d'un tour de Claude), redressée avant
  `--focus` (`Images.redresser` : celle d'une photo verticale arrive couchée, constaté le 25 octobre
  2026 sur XH2S0407.RAF (Copie 1) ; puce de la vignette à l'endroit). Agrandir y redemande la photo
  en grand et relance `--focus` sur elle (`Fenetre.agrandirActive`, puce Agrandir). Une lecture finie
  quand sa photo n'est plus la photo active ne touche pas `Fenetre.focus` (son dossier s'efface) ;
  une lecture en erreur garde un résultat d'échec sans signature (« non lue », pas de relecture à
  chaque rafraîchissement ; un vrai clic relit). Rien de lu : la raison du connecteur
  (`Images.RAISONS_FOCUS` : `delai`, `introuvable`, `illisible`, d'où `Fil.FOCUS_DELAI`,
  `FOCUS_INTROUVABLE`, `FOCUS_ILLISIBLE`), sinon `Fil.FOCUS_NON_LUE`, qui couvre les trois. Après
  un clic sur une ligne d'image du fil, l'aperçu et Agrandir montrent cette image
  (`Fenetre.imageCliquee`, comme `Fenetre.modeEtape` et `Fenetre.comparaisonMontree`). L'aperçu des
  autres onglets et le carré de `--marquer-af` ne changent pas.
- **« Obtenir »** (correctif 1.3.6, décision de Dany du 25 octobre 2026, à la place de la
  proposition que la fenêtre préparait d'elle-même à son ouverture depuis le 20 octobre 2026 :
  `Fenetre.proposerAOuverture`, `Fenetre.propositionAuto`, la préférence `propositionAOuverture`,
  la case « À l'ouverture » du Gestionnaire et sa ligne du diagnostic sont retirés ; une valeur
  restée dans les préférences de Lightroom n'est plus lue) : sous la carte de l'onglet
  Proposition, la rangée est ▲ ▼, Obtenir, Refuser, Ajuster… et Accepter en bleu
  (`Vues.proposition` ; Obtenir en carré de bezel 26, titre en 13, `TAILLES.obtenir` 80 ; la
  rangée tient en 452 points pour 498, `essais-fenetre-b.lua`). Obtenir (`Fenetre.obtenir`, dans
  une tâche) demande une proposition de retouche de la photo seule active dans sa conversation
  (`Fenetre.suivrePhotos` : la montrée si c'est la sienne, sinon la gardée, sinon une neuve avec
  son historique, gardée dès cette demande ; case Autre photo décochée comprise), sans rien
  appliquer : `Consignes.obtenir` (l'ancienne `Consignes.proposerOuverture`) a `demande` (la noter
  d'abord si elle n'est pas encore évaluée, puis `preview_settings`), qui part à Claude, et `fil`
  (« Propose-moi une retouche de cette photo, sans rien appliquer. »), seul gardé dans le fil et
  sur le disque (option `affiche` de `Fenetre.envoyer` et de `Moteur.envoyer`) ; le style et les
  photos jointes partent avec, comme pour une invite. La proposition qui arrive se montre dans
  l'onglet Proposition, comme les autres. Grisé (`peutObtenir`, faux avant l'ouverture et dès le
  clic, `Fenetre.peutObtenir`, posé par `Fenetre.poserObtenir` depuis `rafraichirProposition` et
  `majPhoto`) pendant que Claude travaille (fenêtre ou Demande rapide : `Moteur.travaille`), sans
  photo seule (plusieurs photos sélectionnées, ou aucune) et quand une proposition attend déjà,
  dans la conversation montrée ou dans celle de la photo (`Moteur.conversationDe`) ; une
  proposition close par une étape de Claude n'attend plus. Un clic refusé le dit au bandeau
  (`Fenetre.CLAUDE_TRAVAILLE`, `OBTENIR_SANS_PHOTO`, `OBTENIR_EN_ATTENTE`) ; la carte vide
  (`Fenetre.AUCUNE_PROPOSITION`) dit de cliquer Obtenir. Essais : `essais-une-photo.lua`.
- Une proposition en attente qu'une étape de Claude dépasse n'attend plus (correctif 1.3.2,
  constaté le 22 octobre 2026 : « Applique ta proposition » laissait Accepter actif et bloquait la
  bascule vers la leçon) : `Conversation.clorePropositions`, à la réponse d'un outil de
  `Conversation.OUTILS_ETAPES` qui change l'image (pas `Conversation.CLASSEMENTS`, ni `preview`, ni
  une erreur) et écrit une étape sur sa photo (`photo` : `photo_id` de l'entrée, sinon
  `Conversation.photoLue` ; inconnue, dont une proposition d'avant le correctif, elle attend :
  jamais close par l'étape d'une autre photo) ; `match_series`, sans `etape_id`, par les photos de
  sa réponse qui portent `etapes` ou `etape` (`Conversation.photosHarmonisees` : jamais la
  référence ni un plan) ; `appliquee` si la première étape
  pose chacun de ses réglages lus à la même valeur d'après, sinon `remplacee`
  (`Conversation.ETATS_CLAUDE`, `etapeClaude`). La carte montre `Conversation.propositionClose`,
  sa phrase en tête (`Fenetre.phraseClose`), Accepter, Refuser et Ajuster… grisés ; une
  proposition décidée par Dany garde son chemin (`docs/SPEC.md`, Proposition dépassée). Essais :
  `essais-proposition.lua` (venus d'`essais-lecon.lua` au correctif 1.3.6).
- **Une photo, une conversation** (correctif 1.3.6, décidé avec Dany le 25 octobre 2026 ; à la
  place de la nouvelle conversation à chaque photo du 20 octobre 2026) : une autre photo active ou une autre sélection, choisie par Dany, montre sa conversation
  (`Fenetre.suivreSelection`, depuis `Fenetre.majPhoto`, puis `Fenetre.suivrePhotos` ; préférence
  `nouvelleParPhoto`, même clé, case « Autre photo : reprendre sa conversation, sinon une
  nouvelle » du Gestionnaire, cochée par défaut, qui commande aussi la Demande rapide ; décochée, la
  conversation montrée reste, quelle que soit la sélection). Photo seule : la plus récente qui se
  montre pour son `localIdentifier` (`Moteur.conversationDe`, `Moteur.montrable` ; une copie
  virtuelle a la sienne), que Claude reprend par sa session (`--resume`), complétée de l'élément
  « Depuis la dernière fois » si la photo a changé depuis qu'elle l'a vue (`Moteur.completerDepuis` :
  les étapes du journal de Claude plus récentes que `vu`, faites ailleurs, et les reprises à la main
  si editCount ou lastEditTime ont changé ; rien de changé, rien d'ajouté ; aussi à l'ouverture de
  la fenêtre, `Fenetre.revoirPhoto`) ; sans elle, une neuve (`Fenetre.conversationNeuve`,
  `Moteur.preparerPhoto` : titre provisoire, le nom de la photo, jusqu'à celui que Claude donne)
  qui commence par l'élément « Historique de la photo » (ses étapes de Claude avec raison et date,
  les 8 dernières, et ses reprises à la main depuis la dernière ; « retouchée à la main » sans
  étape si editCount le dit ; rien sinon ; sans étape de Claude, la puce « Réglages hors des valeurs
  par défaut : … », puce suivante, avec « sans étape de Claude » même à editCount 0, un paramètre
  prédéfini posé à l'importation), gardée sur le disque seulement à la première demande
  (`Moteur.envoyer` ; parcourir 300 photos ne crée aucun fichier). Plusieurs photos : une
  conversation de groupe (`Fenetre.conversationDeGroupe`, titre « N photos »), jamais gardée,
  images dans `Temporaire/Groupes/<id>` (effacé quand elle est quittée, `Moteur.montrer`, et au
  chargement du module, `Menage.temporaires`), qui commence par un résumé court
  (`Historique.groupe` : « N de ces M photos ont déjà des étapes de Claude : … », 5 noms au plus ;
  toute la sélection par les lectures groupées du catalogue, journal, propriétaire et uuid ; si
  elles échouent, les 500 premières une à une, `Historique.MAX_GROUPE`, et le texte le dit) ; sa
  clé (`groupe`, `info.groupe` de `Lightroom.photos`) est l'ensemble des photos rangées, sans
  l'ordre ni la photo active (2 000 au plus, `Lightroom.MAX_GROUPE`) : changer de photo active dans
  la même sélection ne change rien. Ces trois éléments (`historique`, `sorte` `historique`,
  `depuis` ou `groupe`) sont faits par la fenêtre sans Claude ni jetons (`Historique.lua`, seule
  copie de leurs textes, dans une tâche : le journal de Claude, `journalClaude` par
  `Photos.lireJson`, et les reprises à la main par `Ecriture.correctionsUtilisateur` ; Lightroom ne
  laisse pas lire son panneau Historique) ; ils ne commencent pas la conversation
  (`Conversation.commencee`) et partent une seule fois avec la demande suivante (`pourClaude`, une
  ligne entre crochets, `Conversation.historiquesAEnvoyer`), marqués `envoye` seulement après un
  `session:envoyer` réussi ; ils redeviennent à envoyer si la reprise échoue (« No conversation
  found ») ou si Claude Code s'arrête avant tout événement de Claude (`Moteur.historiquesEnCours`,
  `reponduEnCours`, `GENRES_CLAUDE`) ; une session perdue (`sessionPerdue`) fait joindre
  l'historique actuel de la photo à la demande renvoyée (`rejoindreHistorique`). À la fin de
  chaque tour, `Moteur.noterVu` relit ce que la conversation a vu (`vu`, `Historique.vu` : nombre
  d'entrées du journal, la dernière, editCount, lastEditTime) : ses propres étapes ne refont pas de
  complément. Champs gardés avec la conversation (`Stockage.lua`) : `photo`, `vu`, `ecartee` et
  `ecarteeLe`, `sessionPerdue`, et `rapide` sur les éléments de la Demande rapide ; une
  conversation de groupe (`groupe`) ou une demande rapide jetable (`c.rapide`) ne va jamais sur le
  disque. Une conversation d'avant le correctif dont la dernière demande portait sur une photo seule (`c.cle`
  « id:1:id », `Conversation.photoDeLaCle`) devient au chargement celle de cette photo, seulement
  si aucune plus récente ne l'a déjà, écartée comprise (`Moteur.charger`) ; les autres (groupes)
  restent sur le disque, plus montrées ; les anciennes séances de notation restent refusées. Plus
  de liste, de Rechercher, de Renommer… ni de Supprimer… (`Moteur.renommer`, `Moteur.supprimer`,
  `Stockage.supprimer` et `Conversation.correspond` retirés) : une conversation n'est jamais
  effacée, son titre est celui que Claude donne (une conversation créée par la Demande rapide en
  reçoit un à la première demande faite dans la fenêtre). « Repartir à neuf » (`Fenetre.repartir`)
  commence pour la photo une conversation neuve avec son historique et met de côté toutes ses
  autres conversations commencées qui se montrent (`Moteur.ecarter` : jamais reprises ni montrées,
  jamais effacées) ; grisé (`peutRepartir`) pendant que Claude travaille, sans photo seule, et tant
  que la conversation montrée n'est pas celle de la photo seule active (`Fenetre.peutRepartir`,
  refus `Fenetre.REPARTIR_AUTRE` ou `REPARTIR_SANS_PHOTO`). Rien ne change pendant que Claude
  travaille, ni juste après s'il a changé la sélection lui-même (`Moteur.travaille`, ou
  `Moteur.finTravail` plus `Fenetre.DELAI_APRES_TRAVAIL`, 4 s, au-delà de l'heure où elle a été
  vue : elle devient la clé `c.cle` de la conversation montrée). La fin du travail est datée par le
  moteur, fenêtre ouverte ou fermée ; la fenêtre garde la sélection vue et son heure
  (`Fenetre.voirSelection` : `Fenetre.cleVue`, `Fenetre.cleVueLe`) d'une ouverture à l'autre : une
  photo choisie fenêtre fermée compte aussi. Une demande rapide faite hors de la conversation
  montrée (`Moteur.selectionRapide`) ne compte pas comme un travail dans celle-ci ; une sélection
  que `Moteur.montrer` refuse (une demande rapide a réservé Claude Code) remet `cleVue` et
  `cleVueLe`, pour être suivie après le travail. Une conversation neuve sans photo (case décochée)
  devient celle de la photo seule de sa première demande (`Fenetre.envoyer`). Essais :
  `essais-une-photo.lua`.
- **Le résumé des réglages** (`Historique.ecarts`, pure ; demandé par Dany le 25 octobre 2026) : pour
  une photo sans étape de Claude (`Historique.etat` lit `getDevelopSettings` seulement quand son
  journal est vide, sous `LrTasks.pcall`), l'élément « Historique de la photo » porte la puce
  « Réglages hors des valeurs par défaut : Profil Camera CLASSIC CHROME · Balance 5 600 K / +8 ·
  Exposition +0,45 · Ombres +30 · Recadrée · 2 masques » (`Historique.REGLAGES`,
  `Historique.texteReglages`), dans le fil et pour Claude, joint une seule fois à la demande
  suivante comme le reste de l'historique, en mots français (pas les clés de Lightroom). Dans l'ordre
  des panneaux : le profil (Adobe Color pour un RAW, Embedded, supposé, pour un autre fichier, à
  l'intensité 100 : `Historique.PROFILS_PAR_DEFAUT` ; le nom tel que Lightroom le range), la balance
  (Telle quelle par défaut ; kelvins et teinte pour un RAW, relatifs pour un JPEG, noms en français,
  `Historique.BALANCES`), le noir et blanc, la tonalité et la présence avec leur signe
  (`Historique.TONALITE`, libellés de `Conversation.libelles`), la courbe, la TSL (pas en noir et
  blanc), l'étalonnage, la netteté (40 pour un RAW, 0 sinon), la réduction du bruit, le bruit de
  couleur (25 pour un RAW, 0 sinon), les corrections d'objectif, la transformation, le vignetage, le
  grain, le calibrage, « Recadrée » et « Redressée de N° », puis les masques, les taches et les yeux
  rouges comptés et le flou de l'objectif. Seulement des valeurs par défaut sûres, celles d'Adobe
  (`Catalogue.swift`), arrondies comme Lightroom les montre (`Reglages.arrondir`) ; un réglage que
  Lightroom ne rend pas, ou illisible, se tait plutôt que d'inventer, comme un quart de tour (que
  l'appareil pose aussi), le débruitage et les détails bruts, la teinte d'étalonnage sans
  saturation, le fondu et l'équilibre ; un profil ou des corrections d'objectif posés par les
  réglages par défaut de Dany se disent comme les autres. Nombres à la française (virgule, « − »
  U+2212, espace fine insécable U+202F des milliers et devant « K », tous mesurés dans
  `Metriques.lua`). Rien pour une photo qui a des étapes de Claude. Essais :
  `essais-une-photo.lua` (l'exemple de Dany, chaque panneau, les défauts d'un RAW et d'un JPEG).
- **Le résumé en bas du fil** (deuxième retour de Dany du 25 octobre 2026, accepté tel quel ;
  `docs/SPEC.md`, Une photo, une conversation › Le résumé en bas du fil) : à l'ouverture de la
  fenêtre (et quand le menu ou ⌃⌥C la rappelle), et chaque fois qu'une autre photo ou un autre groupe
  change la conversation montrée, la fenêtre fait un résumé sans Claude ni jetons, toujours en bas
  du fil, sous la conversation (ou sous l'aide d'une conversation vide), après une ligne vide
  (`Fenetre.ajouterResume`, depuis `Fenetre.rafraichirFil`) : ses lignes par `Fil.lignesResume`,
  comme un élément `historique` (genre `note`, ⓘ sur l'en-tête, puces en retrait), mais d'aucun
  élément ni tour (un clic n'y fait rien). Ses lectures et ses textes ne sont qu'à `Historique.lua`
  (section « Le résumé de la fenêtre ») : une photo (`Historique.lireResumePhoto`,
  `Historique.resumePhoto`, « Résumé de la photo : <nom> ») : « Prise de vue : » l'appareil,
  l'objectif, la focale, l'ouverture, la vitesse et l'ISO tels que Lightroom les écrit
  (`Historique.CLES_PRISE`, métadonnées formatées), puis la date de prise de vue à l'heure locale
  (`timeToUserFormat`) ; « Note et drapeau : 3 ★ · retenue » (`Historique.texteNote`) ; « État : »
  ses étapes de Claude (combien, la dernière, sa date et son nom), sinon « retouchée à la main, sans
  étape de Claude » (editCount) ou « sans étape de Claude ni retouche » ; puis les reprises à la main
  et les réglages hors des valeurs par défaut (`Historique.etat`, `Historique.texteReprises`,
  `Historique.texteReglages`, ici même après des étapes de Claude) ; plusieurs photos
  (`Historique.lireResumeGroupe`, `Historique.resumeGroupe`, « Résumé de la sélection : N photos »)
  : « Prises du … au … » (ou « le … », « (N sans date) », « Dates de prise de vue inconnues »), les
  appareils les plus fréquents (`Historique.APPAREILS_MONTRES` 4, puis « … » ; « inconnu (N) »), et
  « Retouchées par Claude : … · notées : … · rejetées : … » (retouchée : `retoucheeParClaude`
  seulement si `proprietaireMemoire` est l'uuid de la photo, comme `Photos.decrireTout` ; notée : au
  moins 1 ★). Lectures par les trois lectures groupées du catalogue (`batchGetFormattedMetadata`,
  `batchGetRawMetadata`, `batchGetPropertyForPlugin`), par appel direct, dans une tâche ; si l'une
  échoue, une à une (`Photos.meta`, `Photos.brut`, `Photos.lireChamp`, exporté pour lui), les
  `Historique.MAX_GROUPE` premières d'un groupe seulement, et l'en-tête le dit ; une photo absente
  de la lecture groupée des champs du module n'en a aucun (supposé, comme `Historique.lireGroupe`).
  Jamais gardé dans la conversation, ni sur le disque, ni envoyé à Claude : `Fenetre.resume`
  { conversation, photo ou groupe, donnees, texte, fin, versionNotation, perime }, en mémoire
  seulement, remis à nil à chaque ouverture. Il est celui de la conversation montrée : de sa photo
  (`c.photo`), ou de la sélection quand elle est son groupe (`c.groupe` égal à celui de
  `Lightroom.photos`) ; rien pour une conversation sans photo ni groupe (case Autre photo décochée).
  `Fenetre.suivreResume` (`Fenetre.refaireResume`) : depuis la boucle, avant le rafraîchissement,
  aussitôt quand `Fenetre.suivreSelection` change la conversation montrée, après « Repartir à neuf »
  et à l'ouverture ; il le refait pour une autre conversation montrée, même pendant que Claude
  travaille, et, Claude libre, quand un tour a fini (`Moteur.finTravail`), que le registre des notes
  a changé (`Notation.version`) ou qu'il est périmé (`perime`, la fenêtre rappelée : gardé et montré
  jusque-là) ; jamais pendant le travail de Claude pour la même conversation, ni pour la photo active
  changée dans le même groupe. La note et le drapeau d'une photo suivent ceux de la photo active que
  `Fenetre.majPhoto` lit toutes les 2 s (`Fenetre.suivreNoteDuResume`), sans relire le catalogue.
  Aucun caractère nouveau (un essai vérifie que tout ce qu'il écrit est mesuré dans `Metriques`) ; un
  caractère d'un texte de Lightroom non mesuré compte comme « M » (une coupe prudente). Reste à
  constater dans Lightroom : les textes formatés réels, la date, sa durée sur 500 photos et plus, et
  la note suivie après Accepter (`docs/SPEC.md`, Correctif 1.3.6, point 15). Essais :
  `essais-resume.lua`.
- **La Demande rapide** (correctif 1.3.3, demandée par Dany le 22 octobre 2026 ; `FenetreRapide.lua`,
  `MenuRapide.lua`) : une fenêtre flottante à part, d'environ 1 000 × 250 (`save_frame`
  `DeveloppeurRapide-<N>`, à augmenter quand la taille change). Depuis le correctif 1.3.6
  (`Moteur.envoyerRapide`) : une photo seule (case Autre photo cochée), la demande part dans la
  conversation de la photo, la même que la fenêtre Claude (`Moteur.conversationPour` : la montrée
  si elle est à cette photo, sinon la plus récente gardée, sinon une neuve avec son historique),
  sans la montrer, gardée sur le disque dès cette demande, avec « Depuis la dernière fois » s'il y
  a lieu ; Claude reprend la session de la photo (les deux fenêtres donnent les mêmes consignes :
  une demande rapide puis une demande de la fenêtre Claude sur la même photo ne relancent rien) ;
  `Consignes.rapidePhoto` ; la demande et ce qui y répond portent `rapide` (le fil de la fenêtre
  Claude le dit : `Fil.MENTION_RAPIDE`), le titre reste le provisoire, et si la fenêtre Claude
  montre cette conversation, son fil se met à jour (`Moteur.signaler`). Plusieurs photos, ou la
  case décochée : une conversation neuve (`c.rapide`, jamais gardée, `enregistrer` sauté, images
  dans `Temporaire/Rapide/<id>`, effacé à la suivante et au chargement du module,
  `Menage.temporaires` ; session neuve), avec le résumé court du groupe ; `Consignes.rapide`
  (toute la sélection, sans noter d'abord, « Pas de titre. » ; `Consignes.rapide` et
  `Consignes.rapidePhoto` disaient « Ni titre, ni « Demande à garder ». » jusqu'au deuxième retour
  de Dany du 25 octobre 2026). La fenêtre ne montre
  que la réponse à sa demande (`Moteur.reponseRapide`). Un seul Claude Code à la fois : il est
  réservé avant les lectures du catalogue (`Moteur.travaille`, `Moteur.tourRapide =
  Moteur.RESERVE_RAPIDE`, rendu par `libererRapide` si une lecture échoue), et
  `Moteur.processusFini` ne finit le travail que pour `Moteur.enCours`.
  Disposition en pièces superposées (`place = 'overlapping'`) placées par `margin_top` et
  `margin_left` : le résultat page par page (`FenetreRapide.montrer`, `Fil.couper`, 9 lignes de
  13 points ; ▲ ▼ en push_button « mini » comme `Vues.fleches`, une page moins une ligne par clic),
  la demande de 3 lignes (`immediate = false`) et ▲ ▼ puis Envoyer à sa droite, de la hauteur de
  sa boîte (55). À sa gauche, trois carrés à icône de 55 (`FenetreRapide.CARRE`)
  (`FenetreRapide.ACTIONS`, demandés par Dany le 24 octobre 2026 ; images `rapide-noter`,
  `rapide-retouche`, `rapide-portrait` de `Dispositions.IMAGES`, jeu de l'apparence choisie) :
  chacun envoie sa demande toute faite par `FenetreRapide.demander`, le champ laissé tel quel ;
  noter (`Consignes.noterRapide` : `propose_ratings` avec `apply`, le clic vaut la demande), puis
  Retouche pro et Portrait (messages des invites, `Consignes.invite`, pour chaque photo par
  `Consignes.surLaSelection`). Pas encore vus dans Lightroom. Toute demande rapide, tapée ou par
  un bouton, vise toutes les photos sélectionnées, pas seulement la photo active
  (`Consignes.rapide` ; demandé par Dany le 24 octobre 2026). Une autre photo active ou une autre
  sélection efface la réponse (`FenetreRapide.suivreSelection`, `Lightroom.photos` toutes les 2 s
  depuis la boucle, `Moteur.oublierRapide` : la conversation d'une photo reste gardée), le champ
  gardé ; une sélection changée pendant le
  travail de Claude ou moins de `DELAI_APRES_TRAVAIL` (4 s) après, comme `Fenetre.suivreSelection`,
  la garde ; la sélection vue (`cleVue`, `cleVueLe`) reste d'une ouverture à l'autre. Le bouton ♻
  est retiré (demandé par Dany le 24 octobre 2026 : chaque demande partait alors dans une
  conversation neuve). Essais : `essais-rapide.lua`. Constaté le 22 octobre 2026 : dans ce
  `f:view`, la boîte du champ et une f:column commencent à leur `margin_top` ; un petit bouton
  seul dans sa f:row est décalé de 9 ; un clic sur un bouton valide le champ (l'envoi par Retour
  attend 0,3 s et ▲ ▼ l'annulent) ; Échap n'arrive pas à une fenêtre flottante.
- **La carte du masque** (correctif 1.3.4, `CarteMasque.swift`, `ToolHandler.cartesDesMasques`) :
  `add_mask` avec `mask_map`, une seule photo, fait rendre chaque masque (`CarteMasque.maxMasques`,
  4) seul, par la commande `essayer` (rien n'est gardé ; deux étapes « Claude · essai » chacun dans
  l'Historique), sa zone gardée mais son effet remplacé par le témoin (`CarteMasque.temoin` :
  +1,5 IL et `LocalTemperature` −0,4, `quantite` 1, sans couleurs ponctuelles), en 512 px ; l'état
  actuel vient du premier rendu (`comparer`), une seule fois. Les pixels du masque sont ceux qui
  s'écartent de `seuilEcart` (6) : hors du masque, les deux rendus sont les mêmes pixels. Les
  cartes passent avant l'écriture et ne la bloquent pas (une carte qui échoue le dit dans
  `remarques`) ; la réponse porte `carte_des_masques` et l'image en tête. Alertes : presque vide
  (`partVide` 0,5 %), presque total (`partTotale` 95 %), déborde sur un visage (`debordVisage`
  25 %, visages de Vision sur l'état actuel ; sauf une personne, une partie de personne, un sujet et
  un radial non inversé, `viseUnePersonne`), semble inversé (un ciel au centre plus bas que
  `cielBas` 0,6 ; un sujet ou une personne qui couvre plus de `sujetLarge` 40 % de l'image et
  moins de `sujetVisages` 20 % des visages). Tous ces seuils sont provisoires, choisis hors de
  Lightroom ; l'étape « carte du masque » de `--portrait` les éprouve sur la peau et l'arrière-plan
  d'un portrait d'essai.
- **La nature de l'écrêtage** (correctif 1.3.4, `PhotoMeasurements.natureEcretage`, clé
  `ecretage_nature` des mesures, dès `ecretageMin` 0,1 % d'écrêtage) : un pixel écrêté (un canal
  à 254 ou plus) l'est par la gamme si son canal le plus bas est sous `basGamme` (220) et son C*
  d'au moins `chromaGamme` (30), sinon par la luminance ; une nature l'emporte au-delà de
  `natureNette` (2 fois l'autre), sinon « mixte » ; la bande de la TSL la plus touchée
  (`PhotoMeasurements.bandes`, teinte TSV, la plus proche) dit quelle couleur corriger. Mesurée
  dans l'aperçu sRGB : la lecture dit qu'en Adobe RVB ou P3 une partie rentre dans la gamme. Seuils
  provisoires, à relever sur des fleurs, un coucher de soleil, un vêtement vif.
- **Les points chauds** (correctif 1.3.4, `PointsChauds.swift`, clé `points_chauds` des mesures de
  `view_photo`, aperçu entier seulement, ni zoom ni avant/après) : une grille de `grille` (24) cases
  sur le grand côté de l'aperçu réduit ; une case est chaude au-dessus de la médiane de
  `ecartMediane` (20 L*) et d'au moins `lMin` (70) ; les cases voisines font une zone, gardée entre
  `partMin` (0,3 %) et `partMax` (20 %) de l'image, et écartée si plus de `recouvrementSujet` (30 %)
  de son cadre tombe dans un visage ou la zone d'intérêt (sauf une zone d'intérêt de plus de la
  moitié de l'image) ; `maxZones` (5) au plus, de la plus forte (écart fois surface). Dits, jamais
  corrigés d'office (la lecture le dit). Seuils provisoires.
- **Correctif 1.3.5, huit chantiers** (`docs/SPEC.md`, Correctif 1.3.5) :
  - **Sauvegarde dite** (`Sauvegardes.swift`) : `etat` donne `chemin_catalogue` (`cat:getPath()`),
    que `status` retire avant Claude ; `ToolHandler.lireSauvegardes` (rien par défaut ; `main.swift`
    pose `Sauvegardes.lire`, comme `lireEcran`) lit les dossiers datés « AAAA-MM-JJ HHMM » de
    `Backups` à côté du catalogue et `/Library/Preferences/com.apple.TimeMachine.plist`
    (`Destinations`, `SnapshotDates`, `AutoBackup`), puis `tmutil isexcluded` sur le volume du
    catalogue ; toute lecture du volume des photos ou d'un outil est bornée (`Sauvegardes.borne`,
    3 s) : macOS peut y faire attendre, Claude ne répond jamais à sa place. Rien n'est réglé. Lancé
    depuis Lightroom (la fenêtre Claude), le connecteur ne lit pas ces préférences (accès complet
    au disque ; constaté le 23 octobre 2026 à l'essai de la 1.3.5 : « préférences non lisibles ») :
    repli par `tmutil destinationinfo` (la destination) et `tmutil isexcluded` (le volume), sans la
    date de la dernière sauvegarde (`preferences_lues` faux, `a_savoir`).
  - **Rafales par boîtier** : `Vignettes.decrireVignette` lit `serie_boitier`
    (`cameraSerialNumber`, par `Photos.meta`, une à la fois : une clé refusée ne casse aucun lot) ;
    `PhotoTriee.boitier`, et `Tri.memeRafale` refuse deux boîtiers différents ; `view_photo` retire
    `serie_boitier` avant Claude.
  - **Vidéos écartées** : `Photos.decrire` pose `video = true` (fileFormat VIDEO) ;
    `seriesPhotosSansVideos` les retire d'une collection, d'un dossier ou de la sélection et les
    compte (`seriesPhotos` les retire aussi) ; le tri les écarte encore à la lecture des vignettes
    (photo_ids), `match_series` et `cull_photos` disent `videos_ecartees`, et `Livraison.exporter`
    les saute et les compte (`videos_ecartees`).
  - **Préparer un tirage** : `export_photos` avec `print` (`ToolHandler.tirage` : `size` en cm,
    `ppi` 300 par défaut de 240 à 600, `paper` matte ou glossy) donne `taille` (grand côté),
    `resolution` (que `Livraison.lua` lisait déjà, `LR_size_resolution`) et `nettete` du papier,
    niveau standard ; `long_edge` et `sharpening` donnés à part l'emportent. Le profil ICC du labo
    ne passe pas par le module (espaces de `colorSpaces` seulement) : la fenêtre d'exportation.
  - **Ton style sur une photo neuve** : le style `ma_facon` (« À ma façon ») de `Consignes.styles`,
    sans recette, et l'invite `a_ma_facon` (`Prompts.aMaFacon`, avec le guide, finit par
    `finRetouche`).
  - **Styles en recettes fixes** : chaque style de `Consignes.styles` (sauf Standard et À ma façon)
    a sa `recette` (`valeurs` posées telles quelles, l'étalonnage ; `relatif`, décalages avec
    relative = true ; `peau` ; `note`), mise en texte par `Consignes.texteRecette` et jointe à la
    ligne de style (`Consignes.ligneStyle`) : rien dans `Consignes.texte` (7 476 caractères alors).
    Recettes de départ choisies par Claude, à ajuster au goût de Dany.
  - **Apprendre de tes corrections** (`Apprentissage.swift`) : `remember_style` avec `learn` et une
    série (`Apprentissage.maxPhotos`, 200) lit `corrections_utilisateur` par la commande
    `reglages`, photo par photo ; une règle seulement pour un réglage repris sur au moins
    `minPhotos` (3) photos et `frequenceMin` (60 %) des photos reprises, dans le même sens pour
    `sensMin` (80 %) d'entre elles (provisoires) ; rien n'est écrit, la phrase proposée n'entre au
    guide que par `preference` et `confirm`.
  - **Rendu reproductible** (`Rendus.swift`, `RegistreRendus`) : à la fin d'une retouche, au
    `view_photo` avec `compare = before_claude` depuis le correctif 1.3.6 (d'abord à la fin de
    `photo_lesson`, retiré ; les invites et `Consignes.texte`, section Fin d'une tâche, le demandent
    en dernier, pas dans une [Demande rapide]), `ToolHandler.noterLeRendu` lit les réglages de
    `RegistreRendus.seuils` et le profil dans la réponse de la commande `apercu`, compte les
    entrées « retour » du journal (commande `journal`) et les garde dans `rendus.json` (3 par photo,
    2 000 photos) : un rendu par série (une retouche, d'un retour à l'origine au suivant), le
    dernier de chacune ; plus de retours que le dernier gardé, une nouvelle série commence ;
    autant ou moins (le journal garde ses 200 dernières entrées), la même série continue et le
    nouveau rendu remplace son dernier ; dans les deux cas, il se compare au dernier de la série
    d'avant (`rendu_reproductible`, rien pour la première série ; un écart trop grand se rejuge à
    la fin d'une retouche pas finie). Un `rendus.json` d'avant se relit tel quel. Seuils provisoires
    (0,3 IL, 15 à 20 points, 400 K pour un RAW, un autre profil) ; `registreRendus` n'est posé que
    par `serve()`, comme `noterAuCarnet` (ni `--call`, ni la recette, ni les tests).
- Ne jamais nommer un fichier du module `Versions.lua` : Lightroom refuse de le charger (constaté ;
  d'où `Composants.lua`). Un seul `Info.lua`, `Init.lua`, `Arret.lua` et `PluginInfoProvider.lua`
  pour la liaison et la fenêtre, sans fichier de fusion (`InfoFenetre.lua`…) :
  `scripts/tester-module.sh` refuse l'un et l'autre.
- Un raccourci d'app vise le titre exact de l'entrée de menu, tel que Lightroom l'écrit : trois
  espaces devant chaque entrée de module (`Raccourcis.RETRAIT`, constaté par l'accessibilité) ;
  `Raccourcis.LISTE` : ⌃⌥C (Ouvrir la fenêtre Claude) et ⌘⌃⌥C (Demande rapide, correctif 1.3.3).
  Lightroom ne lit les raccourcis qu'à son lancement : un rechargement du module ne suffit pas.
- Pas de calcul long en Lua sur la tâche de l'interface : base64, réductions d'images (`sips`) et
  commandes du système passent par `LrTasks.execute` (qui ne bloque que la tâche).
- Un essai de publication dans Lightroom (fenêtre Publication) se fait sur une photo d'essai, et
  le fichier publié va ensuite à la Corbeille (jamais effacé).
- `build.sh` signe avec le certificat « Developer ID Application » de Dany et le runtime durci,
  puis notarise l'archive (profil `notarisation` de `notarytool`). `SKIP_NOTARIZE=1` pour un essai
  rapide ; ne jamais publier une archive non notarisée, ni construite avec `--sans-tests`.
- Avant de pousser une fonctionnalité : README et `CHANGELOG.md` à jour, capture d'écran refaite
  dans Lightroom si l'interface a changé (`docs/capture.png` : la fenêtre Claude, sa seule
  disposition, la fenêtre B de la 1.3.2 après une retouche pro : ses étapes, « Pourquoi ? »,
  « ＋ Garder la demande », le menu Mes demandes et l'onglet Focus, refaite le 22 octobre 2026 ;
  à refaire au correctif 1.3.6 : elle montrera la fenêtre de 1 623 × 1 200, sans volet ni Mode,
  ses onglets Focus, Note, Aperçu et Proposition, le bouton Suivi et le résumé en bas du fil, sans
  « Pourquoi ? » ni « ＋ Garder la demande » ;
  `docs/carnet.png`, la page Carnet de progrès, à refaire au correctif 1.3.6 : elle montrera
  la fenêtre Suivi ; `publication.png`, `consommation.png`,
  `suivi.png` : les autres fenêtres ; `seance.png` est retirée avec la Séance en 1.1.1,
  `atelier.png` et `panneau.png` avec l'Atelier et le Panneau en 1.2), et une nouvelle version si ce
  qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/DeveloppeurKit/` : `JSONValue` (JSON générique), `MCPServer` (JSON-RPC, initialize, tools, prompts, ressources), `FileOutils` (appels d'outils un à un, réponse d'attente avant les 60 s de Claude Desktop), `Progression` (notifications de progression), `ContexteAppel` (progression et annulation d'un appel), `Tools` (socle des outils, 35 depuis le correctif 1.3.6 ; `lireEcran`, le nom de l'écran dans `get_status`, sans remarque au premier aperçu depuis le correctif 1.3.6 ; `vuesMesurees` et `zoomsMesures` du bilan ; `lecteurBoitier` ; `noterAuCarnet` ; `descriptionRaison`, la raison d'une étape) et ses extensions `Tools+Analyse` (aperçu, avec le point de mise au point, sur un zoom aussi, l'évaluation de la photo, l'éclairage, l'intention du boîtier et le bilan d'une passe à l'autre ; zoom et son `bilan_zone`, comparaison et son bilan, mesures de série, réglages ; `mesurerImage` ; `comparaisons` ; le rendu de fin de retouche au `before_claude`, `rendu_reproductible` ; la vue et la ligne au carnet : `noterLaVue`, `noterLAngle`, `constaterAuCarnet`), `Tools+Retouche` (`apply_settings`, `preview_settings`, avec le bilan d'une proposition et la surimpression du cadre proposé ; `enhance_photo`, `remove_distractions`), `Tools+Balance` (balance sur un point neutre ; `balanceProposee` d'un éclairage mixte), `Tools+Locales` (masques, taches, yeux rouges ; garde-fou de la peau, résumé du tireur dans la description d'`add_mask`), `Tools+Recalage` (grilles demandées, gardées en mémoire), `Tools+Gestion` (copie, profils, paramètres prédéfinis, journal ; `export_journal` avec `notebook`), `Tools+Bibliotheque` (recherche, classement, mots-clés, collections, copies virtuelles, photo montrée), `Tools+Tri` (tri d'une séance, planche contact jusqu'à 30 vignettes, vignettes par lots), `Tools+Notation` (`propose_ratings`, validé avant la commande `notation` ; notes posées avec `apply`), `Tools+Livraison` (`export_photos` : formats, HDR, poids, filigrane, réimportation, livraisons types lues dans les services Disque dur, noms exacts, dossier choisi, aperçus dynamiques, fenêtre d'exportation en dernier recours ; modèles de noms de fichiers et filigranes de l'utilisateur, relecture du fichier livré), `Tools+Variantes` (`compare_variants`, `choose_variant`), `Tools+Serie` (`match_series`, pentes de la balance, expositions d'après la prise de vue), `Tools+Style` (`remember_style`, ressources), `Tools+Composition` (`read_composition`, `apercu` avec `entier`) ; `Tools+Lecon`, `Lecon` et `JeLeFais` sont retirés au correctif 1.3.6 ; `PriseDeVue` (vocabulaire des défauts de la prise de vue, seule liste : 16 codes, domaines du carnet, six mesurés ; `vocabulaire` envoyé au module), `Composition` (cadre dans l'image entière, passage de `view_photo` à l'image entière, plus grand cadre, cadre proposé et ordre de relâche, crop, résumé, lecture, regard, visages renversés et zone d'intérêt écartés ; pur), `Carnet` (seuils du carnet, dont `isoEleve`, `iso` et `bruitCherche`, `constatsVue`, `constatHorizon`, `geometrieIntacte`, Markdown d'`export_journal`, `sansLecons`, relevé `--constats`), `Tri` (défauts, rafales, ordre de lecture, plafonds de note, rejets proposés ; `PhotoTriee.defautsNettete`, seule copie des règles de netteté, partagée avec le carnet ; mise au point jugée sur la texture), `Notation` (standard de notation, seule copie ; plafonds de note), `Boitier` (lecture de l'original Fujifilm d'une seule ouverture, Exif et MakerNote : point de mise au point, intention et mise au point en détail, `LectureBoitier` ; lecteur borné `LecteurBoitier`), `IntentionBoitier` (simulation, couleur, plage dynamique, tons, compensation, mode, balance, scène ; profil Lightroom de la simulation ; lecture pour Claude, `intention_boitier`), `PointAF` (point de mise au point des fichiers Fujifilm, passage dans l'image affichée ; `PointAF.marquer` pour `--marquer-af`), `Focus` (onglet Focus : `MiseAuPointBoitier`, la mise au point Fujifilm en détail et ses textes en français, `valeursLues` pour `--boitier` ; `Focus.cadres`, `Focus.tailleCadreAF`, `Focus.marquer` et `Focus.lire` (la raison d'une lecture vide, `Focus.nonLue`) pour `--focus` ; `PreviewImages.marquerFocus`), `Sauvegardes` (sauvegardes du catalogue et Time Machine, 1.3.5), `Apprentissage` (règles tirées des reprises à la main, 1.3.5), `Rendus` (rendu reproductible, `rendus.json`, 1.3.5 ; `ToolHandler.noterLeRendu`, au `view_photo` avec `compare = before_claude` depuis le correctif 1.3.6), `CarteMasque` (carte d'un masque, 1.3.4 : témoin, pixels du masque, lecture, alertes, image ; les rendus sont à `ToolHandler.cartesDesMasques`, dans `Tools+Locales`), `PointsChauds` (zones claires hors du sujet, 1.3.4), `Peau` (dosage de la peau d'après Adobe, seule copie ; effets intégrés « Peau du visage lisse » et « Adoucir la peau (Lite) » ; garde-fou d'`add_mask`), `Eclairage` (`MesureEclairage` : point neutre de l'image et centre des tons presque neutres, dominante par zone tonale et par case 3 × 3, visages à part, deux groupes de lumière et éclairage mixte, médianes par histogramme ; relevé `--eclairage`), `Bilan` (bilan chiffré d'une passe à l'autre, en fonctions pures : écarts visibles, régressions, à vérifier ; empreintes du cadre et de l'état ; les vues gardées sont à `ToolHandler`), `Ecran` (écran principal et profil ColorSync ; `nommer`, les noms seuls pour `get_status` ; six classes, textes et JSON pour `--ecran` seulement, le développement ; plus de remarque d'écran ni de `detail` depuis le correctif 1.3.6), `JetonLiaison` (fichier du jeton de la liaison : chemin, lecture, état pour `--status`), `MotsClesVision` (mots-clés de Vision traduits), `ModeleCouleur` (modèle d'une couleur prélevée), `ProfilsObjectif` (profils d'objectif `.lcp` installés), `GuideStyle` (guide de style de l'utilisateur, `~/Library/Application Support/Developpeur/guide-de-style.md`), `ReglagesAPlat` (`--dump`), `Catalogue` (les 124 réglages de développement, version minimale de Lightroom des plus récents, les profils d'appareil, les libellés), `Mesures` (mesures d'un aperçu, seuils nommés, tons neutres suivis d'une vue à l'autre), `Detail` (netteté et bruit, seuils nommés ; texture autour du point de mise au point, `Detail.autour`, `textureMin`, `textureDouteuse`), `AnalyseVision` (visages avec leur lacet et leur roulis, pupilles, note esthétique, saillance, photos semblables, cadres des personnes), `Lignes` (angle d'une ligne désignée ; « affinée » seulement sous `LineAngle.ecartMax`), `Recalage` (correspondance entre l'image corrigée et celle d'avant la correction d'objectif, Upright et la perspective), `Recette` (recette dans le vrai Lightroom ; aussi `lectureBoitier` pour `--boitier`, `Luminances`, `partAssombrie` et `formeDesBords` pour éclaircir et assombrir, `ecartMax` pour l'intensité de la peau, `dureeEclairage`, `resumeEcarts` ; photo active comparée, `ecartPhotoActive`, et registre des notes remis, `garderRegistreDesNotes`), `Recette+13` (recette de la 1.3 : Pourquoi ?, carnet, composition ; leçon et Je le fais retirés au correctif 1.3.6), `Images` (zoom, côte à côte, planche contact, carré du point de mise au point : `PreviewImages.marquerPoint` ; cadre proposé en pointillés : `PreviewImages.cadrePropose`), `ProfilsLook` (profils à base de Look installés), `EffetsLocaux` (effets locaux de Lightroom, `.lrtemplate`, puis les effets intégrés de `Peau` qui manquent), `PresetXMP` (paramètres prédéfinis XMP), `LightroomBridge` (client TCP du module, avec le jeton de la liaison dans chaque ligne), `Prompts` (invites ; `Prompts.Tireur` : doses et forme d'éclaircir et assombrir, seule copie), `ClaudeRegistration` (inscription dans les fichiers de configuration de Claude), `MiseAJour` (dernière version publiée, par `gh`, pour `--status`), `ServerInfo` (nom, titre, version, consignes données à Claude)
- `Sources/MCPDeveloppeur/main.swift` : options de ligne de commande (dont `--marquer-af`, pour l'aperçu de la photo active de la fenêtre Claude, `--focus`, pour son onglet Focus, et `--ecran`, pour le développement depuis le correctif 1.3.6 (plus de voyant Écran) ; `--boitier`, `--eclairage` et `--constats`, relevés à la main ; `--recette` avec `--horizon` et `--hauteur-horizon` ; `--status`, avec l'état du jeton et le nom de l'écran) et boucle stdio ; `outils()` pose `Ecran.lire` pour le serveur et `--call` (`get_status` seulement) ; `noterAuCarnet` vrai et `registreRendus` posé dans `serve()` seulement
- `Lightroom/Developpeur.lrplugin/`, le module :
  - déclaration et cycle de vie : `Info.lua` (« Développeur », `com.danymenard.developpeur`, menus, version), `Init.lua` / `Arret.lua`, `Menage.lua` (paramètres prédéfinis invisibles effacés ; au chargement, depuis le correctif 1.3.6, les dossiers temporaires des groupes et des demandes rapides : `Menage.temporaires`), `PluginInfoProvider.lua` (Gestionnaire de modules externes : section liaison, avec Mise au point et Carnet et, au diagnostic, l'état du jeton, les commandes refusées et les photos du carnet, et section fenêtre Claude, avec modèle, effort, apparence, Autre photo (reprendre sa conversation, sinon une nouvelle) et Avant/après ; les cases Leçon et « À l'ouverture » sont retirées au correctif 1.3.6), `Preferences.lua` (réglages de la liaison, dont `pointMiseAuPoint` et `carnet` ; ceux de la fenêtre dans `Chemins.defauts`, même table), `Metadonnees.lua` (champs privés), `Menu*.lua` (les neuf entrées de Module externe - Extras, dans Fichier et Bibliothèque)
  - la liaison : `Liaison.lua` (prises LrSocket, jeton privé et refus des lignes sans lui, `module.log`), `Commandes.lua` (répartition des commandes du serveur) et les modules qui les portent : `Lecture.lua` (état, avec `liaison_fermee`, sélection, réglages, paramètres prédéfinis, diagnostic, journal), `Rendu.lua` (aperçus, avec `point_af` : photo décrite par `Vignettes.decrireVignette`, évaluation, et `etapes_claude` pour le bilan ; image entière et cadre relu, `sansRecadrage` partagé avec le recalage ; la vue gardée pour `Etapes` ; propositions, `essayer` avec `entier`, rendus du recalage), `Etapes.lua` (avant/après des étapes : empreinte, vue, capture autour de chaque commande, commande `etapes`, `Etapes.images` pour la fenêtre, ménage), `Carnet.lua` (registre `carnet.json` : commande `carnet`, `constater`, `Carnet.resumer`, `photosDuDefaut`, `vocabulaire`, `estPhotoDEssai` ; les leçons d'avant le correctif 1.3.6 gardées telles quelles), `Retouche.lua` (appliquer, recadrer, masquer, retoucher, copier), `Amelioration.lua` (débruitage, détails bruts, super résolution), `Suppression.lua` (reflets, retrait de la poussière), `Masques.lua` (reprendre un masque : commande `masques` ; masques vides), `Conversions.lua` (rotation d'un quart de tour), `Progression.lua` (barre de progression de Lightroom pendant une série : commande `progression`), `Vignettes.lua` (vignettes du cache d'aperçus : commande `vignettes` ; `decrireVignette`, aussi pour l'aperçu de `view_photo`), `Notation.lua` (registre des notes proposées, `notation.json` : commande `notation`, avec `remettre` pour la recette, `Notation.poser`), `Livraison.lua` (exporter, fenêtre d'exportation, options de livraison, dossier choisi dans une fenêtre, noms exacts, aperçus dynamiques), `Services.lua` (services de publication et réglages des services Disque dur, lus seulement), `Variantes.lua` (variantes en instantanés), `Annulation.lua` (annuler, revenir), `Bibliotheque.lua` (classement, paramètres prédéfinis de métadonnées, mots-clés, collections, recherche, copies virtuelles, photo montrée et filtre de la Bibliothèque : commandes `metadonnees`, `motsCles`, `collections`, `chercher`, `copieVirtuelle`, `montrer` ; notes acceptées ou posées sur demande : `Bibliotheque.noter` ; photo active et sélection remises : `Bibliotheque.remettreSelection`) ; leur socle : `Photos.lua` (photos visées, description, sensibilité ISO en nombre, mémoire de Claude ; `lireChamp` exporté pour le résumé du fil), `Reglages.lua` (valeurs de développement), `Recalage.lua` (géométrie, grille du serveur), `Plans.lua` (ce qu'une retouche changera), `Ecriture.lua` (écriture dans le catalogue, étapes avec leur id, `Ecriture.nouvelleEtape`, journal, `Ecriture.difference`), `Profils.lua` (profil relu après l'écriture), `Recadrage.lua` (calcul du cadre), `Geometrie.lua` (positions de l'aperçu vers le fichier), `Locaux.lua` (tables des masques, taches et yeux rouges) — ces trois-là sans SDK —, `Json.lua`, `Suivi.lua` (fenêtre de la liaison « Claude · liaison », menu « Afficher la fenêtre de la liaison », « fenêtre de suivi » jusqu'au correctif 1.3.6 ; `MenuSuivi.lua` garde son nom) ; `Liaison.lua` compte aussi les commandes en cours (`Liaison.enCours`, `Liaison.finCommande`, correctif 1.3.6), pour qu'Agrandir ne rende pas la photo pendant elles
  - la fenêtre Claude : `Fenetre.lua` (la fenêtre : état, actions, boucle, apparence, calques et boutons, bandeau, textes des cartes page par page, carte Note B, aperçu de la photo active et son carré de mise au point, « Obtenir » (la proposition demandée sous la carte Proposition, à la place de celle préparée à l'ouverture), une photo, une conversation (`suivreSelection`, `suivrePhotos`, conversation neuve ou de groupe, « Repartir à neuf »), voyants de l'en-tête (Claude Code et Lightroom ; versions et mode dans l'infobulle du voyant Lightroom ; le voyant Écran retiré) et bouton Suivi (`ouvrirSuivi`), titre « Développeur v… » (`titreFenetre`), aide d'une liaison sans jeton, menu Mes demandes et ses fenêtres Ajouter…, Renommer… et Supprimer… (« ＋ Garder la demande » retiré au correctif 1.3.6), le résumé en bas du fil (`resume`, `suivreResume`, `suivreNoteDuResume`, `ajouterResume`, `lignesAide`) ; onglets Focus, Note, Aperçu et Proposition : la mise au point de la photo active, la note, l'étape ou l'image du fil cliquée avec son pourquoi (`voirImageDuFil`, `etapeAvant`, `choisirEtapeDeLImage`), la proposition et la composition ; ouverture sur Focus et retour à Focus (`revenirAFocus`), bascules vers Aperçu, Proposition et Note ; Agrandir qui remplit 2 000 × 1 250 (`GRANDE`, `agrandirUne`, `agrandirDeux`, `cadreDeux` ; la photo active redemandée en grand : `agrandirActive`, `preparerGrande`, `rendreActive`, `TAILLE_GRANDE`) ; la vignette de secours de l'aperçu de la photo active (`DELAI_SECOURS_ACTIVE`, `decrireActive`) ; plus de volet, de liste, de Mode, de Leçon, de « Je le fais », d'onglet Suivi, de « Pourquoi ? » ni de Détail… dans l'onglet Aperçu depuis le correctif 1.3.6), `Vues.lua` (ses pièces : aplats, images, boutons bleus, éléments inactifs, ligne du fil, en-tête (titre, « Repartir à neuf », deux voyants, bouton Suivi), saisie, menu Mes demandes et bandeau, segments, aperçu, cartes Proposition, Aperçu (sans Détail… depuis le correctif 1.3.6), Focus et Note, et la fabrique masquable des onglets ; ni Noter ni Évaluer), `Dispositions.lua` (la fenêtre B, seule disposition : tailles, dimensions, onglets (`ONGLETS`, seule liste), images, apparences et palettes), `Fil.lua` (le fil en lignes : texte riche, appel, auteur et heure, actions (« ☆ Voir la note » ; « ＋ Garder la demande » retiré au correctif 1.3.6), éléments `historique`, mention « Demande rapide », le résumé de la fenêtre (`lignesResume`) ; `lignesCarte`, les textes des cartes coupés ; le texte de l'onglet Focus et de la fenêtre Suivi), `Metriques.lua` (chasse des polices, produite par `scripts/metriques.swift`), `Moteur.lua` (conversations et processus de Claude Code, indépendants de la fenêtre ; la conversation de chaque photo : `conversationDe`, `preparerPhoto`, `completerDepuis`, `resumerGroupe`, `ecarter`, `noterVu` ; la Demande rapide : `envoyerRapide`, `conversationPour`, `reponseRapide` ; modèle et effort d'une demande), `Historique.lua` (correctif 1.3.6 : ce que la fenêtre dit d'une photo sans Claude ni jetons, « Historique de la photo », « Depuis la dernière fois » et le résumé d'un groupe, seule copie de leurs textes ; lectures du journal de Claude et des reprises à la main, `Historique.vu` ; les réglages hors des valeurs par défaut d'une photo sans étape de Claude, `Historique.ecarts` ; le résumé en bas du fil, section « Le résumé de la fenêtre » : `lireResumePhoto`, `lireResumeGroupe`, `resumePhoto`, `resumeGroupe`, `texteNote`), `FenetreSuivi.lua` (correctif 1.3.6 : la fenêtre Suivi, le carnet de progrès, ses photos d'un défaut et « Retirer du carnet… »), `FenetreRapide.lua` et `MenuRapide.lua` (la Demande rapide), `Session.lua` (un processus Claude Code par `relais.sh`), `relais.sh`, `Evenements.lua` (lignes stream-json de Claude Code), `Conversation.lua` (éléments d'une conversation : étapes, cadre demandé, dernier zoom, éléments `historique` ; champs `photo`, `vu`, `ecartee`, `groupe` (la retouche du tour et « Demande à garder » de Claude retirées au correctif 1.3.6) ; les éléments `lecon` et `exercice` d'avant le correctif 1.3.6 gardés sans ligne au fil), `Stockage.lua` (conversations sur le disque, jamais effacées depuis le correctif 1.3.6, et Mes demandes : `mes-demandes.json`), `Images.lua` (aperçus et photos jointes, base64 et `sips` ; carré de mise au point par le connecteur : `Images.marquerMiseAuPoint` ; onglet Focus : `Images.lireFocus` ; vignette remise à l'endroit : `Images.rotationManquante`, `Images.redresser` ; Agrandir : `Images.grande`, qui remplit la place), `presse-papiers.js` (lecture du presse-papiers par `osascript`), `Consignes.lua` (consignes ajoutées, dont les puces Peau (sans chiffres), Notes (la note d'abord de chaque photo traitée) et Mise au point montrée, et le résumé chiffré du bilan ; depuis la 1.3, les sections Composition et Raison de chaque étape, et la puce Carnet ; depuis le correctif 1.3.6, l'historique dans le Contexte et la fin d'une retouche par `view_photo` avec `compare = before_claude` (les sections Je le fais, Leçon de la photo, Écran et Demande à garder retirées) ; sept invites en raccourcis, dont Portrait, Paysage et Noir et blanc qui demandent la méthode du tireur sans chiffres, et Composition ; ajustements du cadre ; demande d'« Obtenir » (`Consignes.obtenir`, à la place de `proposerOuverture`), réponses aux propositions, règles de la Demande rapide (`rapide`, `rapidePhoto`), styles, modèles et efforts), `Lightroom.lua` (photo active, sa note et sa légende, sélection, sa clé et celle de son groupe, état et mode de la liaison, liaison occupée (`Lightroom.liaisonOccupee`, correctif 1.3.6), connexion de Claude Code, valeurs de l'onglet Focus : `Lightroom.infosFocus` ; l'écran principal n'y est plus lu depuis le correctif 1.3.6), `Composants.lua` (versions du module et du connecteur, dans l'infobulle du voyant Lightroom depuis le correctif 1.3.6 ; celle du module dans la barre de titre de la fenêtre Claude), `Raccourcis.lua` (⌃⌥C), `Chemins.lua` (dossiers et réglages de la fenêtre), `Fichiers.lua`, `Texte.lua` (UTF-8), `Journal.lua` (`conversation.log`), `Compat.lua` (`os.time`, `os.date`), `images/` et `images/sombre/` (les images de la fenêtre B en 2x, un jeu par apparence, dont `vide-498x332.png`, l'image « aucun aperçu ») ; `FenetrePublication.lua` et `Publication.lua` (profils et exportation de la fenêtre Publication), `FenetreConsommation.lua` et `Consommation.lua` (jetons comptés, budget de la semaine). La Séance de notation (`FenetreNotation.lua`, `MenuNotation.lua`) est retirée depuis la 1.1.1 (demandé par Dany le 20 octobre 2026)
- `Tests/DeveloppeurKitTests/` : tests XCTest avec `FakeLightroom` et `FakePlugin` (TCP, dans `LightroomBridgeTests` ; `jetonAttendu` : le jeton qu'il exige, nil pour un module d'avant la 1.2) ; pour la 1.2 : `PeauTests`, `BoitierTests` (fichiers Fujifilm fabriqués, tons en SLONG et en LONG), `EclairageTests`, `BilanTests` (longueur des descriptions de `view_photo`, `preview_settings` et `analyze_photos` comprise), `EcranTests` (tests purs, `nommer`, `get_status` qui ne dit que le nom, aucune remarque aux aperçus depuis le correctif 1.3.6 ; la lecture du vrai écran avec `DEVELOPPEUR_ECRAN_REEL=1` seulement), `JetonLiaisonTests` ; pour la 1.3 : `PriseDeVueTests`, `PourquoiTests`, `CompositionTests` et `ContratCompositionTests`, `CarnetTests`, `Recette13Tests` (un module simulé à état ; `LeconTests`, `JeLeFaisTests` et `ContratJeLeFaisTests` sont retirés au correctif 1.3.6) ; pour la 1.3.5 : `Version135Tests` (le rendu reproductible au `before_claude` et ses séries compris) ; pour la 1.3.4 : `CarteMasqueTests` (carte du masque, lecture, alertes, `add_mask` avec `mask_map` face au faux module) et `EcretageEtPointsChaudsTests` ; la règle de la rafale dans `NotationTests` et `TriTests` ; pour l'onglet Focus : `FocusTests` et, dans `BoitierTests`, les valeurs de DSCF2402 (`BoitierTests.dscf2402`, jamais la photo). `FakeLightroom` note `progression` et `carnet` à part (`progressions`, `carnets`)
- `Tests/Contrats/` : `composition.json`, l'échange figé entre le serveur et le module, lu par les essais Swift et Lua (un changement voulu se fait des deux côtés ; `je-le-fais.json` est retiré au correctif 1.3.6)
- `Tests/Lua/Liaison/` : `Simulation.lua` (SDK de Lightroom simulé pour les commandes du serveur ; `LrTasks.execute` n'y imite que les deux commandes du fichier du jeton et refuse toute autre ; un `Mask/CircularGradient` sans `Flipped = true` ou sans `MaskInverted` booléen y est refusé ; `isoSpeedRating` brut y est un nombre, jamais le texte formaté ; le film fixe suit la source affichée, `S.visiblesSous` ; un `MaskGroupBasedCorrections` vide tombe aux rendus du recalage), `Aides.lua` (aides communes et remise à zéro par module, `A.remiseAZero`), `tests.lua` (dont `Liaison.enCours`), les essais à part `essais-carnet.lua`, `essais-composition.lua`, `essais-etapes.lua`, `essais-registre.lua` (les leçons d'avant le correctif 1.3.6 gardées dans `carnet.json`), et `liens.lua` (chaque champ lu d'un module requis existe, dans tous les fichiers du module)
- `Tests/Lua/Fenetre/` : `Simulation.lua` (SDK simulé pour la fenêtre, dossier personnel temporaire, liaison jamais démarrée ; refuse `visible` sur `row`, `column`, `group_box`, `tab_view` et `scrolled_view`, évalue les liaisons à plusieurs clés ; d'après les constats du 21 octobre 2026, refuse aussi `background_color` sur `row`, `column`, `view`, `group_box` et la fenêtre, `primary_line_color`, `mouse_down` sur un `f:picture`, un `f:picture` sans taille ou sans image ni fond, `image_name` avec un titre, plus d'un `default = true`, un `<EM>` mal formé ou sans `emphasis_font`, `presse-papiers.js` sans nom ; imite la frappe, Retour et les clics, `S.taper`, `S.retour`, `S.cliquer`, et le choix dans un menu, `S.choisir` (ni séparateur ni élément grisé : `S.refusElements`, relevé dans `AgViewUtils.getPopupMenu`), et refuse un geste sur une vue masquée ou inactive ; donne `copyName`, `cameraModel` et `dateTimeOriginal`), `faux-claude.sh` (imite Claude Code en stream-json), `tests.lua`, et les essais à part `essais-*.lua` (chacun charge la simulation, la complète localement sans toucher `Simulation.lua`, a ses propres aides et sort en échec si un essai échoue ; tous lancés par `tester-module.sh`) : `essais-dispositions.lua`, `essais-moteur.lua`, `essais-integration.lua` (de bout en bout avec les vrais modules, `sips` compris, Agrandir dans 2 000 × 1 250 aussi), `essais-gestionnaire.lua`, `essais-images.lua` (palettes et images des deux apparences), `essais-fenetre-b.lua` (cadre, tailles, contrôles, carte Note B, bandeau), `essais-pourquoi.lua` (un clic sur une étape ou une image du fil, le pourquoi de l'étape qui précède, l'image d'une proposition et une photo jointe, les bascules vers Aperçu), `essais-composition.lua`, `essais-carnet.lua` (le bouton Suivi et la fenêtre Suivi, « Photos d'un défaut… »), `essais-une-photo.lua` (une photo, une conversation : historique et son résumé des réglages, « Depuis la dernière fois », groupe, retour à Focus, « Repartir à neuf », conversations d'avant le correctif 1.3.6, plus de proposition à l'ouverture, « Obtenir », ménage des dossiers temporaires), `essais-resume.lua` (le résumé en bas du fil : ses textes et leurs caractères, les lectures groupées et une à une, l'ouverture, une autre photo, un groupe, la fin d'un tour, la note suivie, le rappel par le menu, jamais gardé ni envoyé), `essais-proposition.lua` (la proposition dépassée, venue d'`essais-lecon.lua`, et une conversation d'avant le correctif 1.3.6 qui porte des éléments `lecon` et `exercice`), `essais-focus.lua` (l'onglet Focus, avec un faux `mcp-developpeur --focus` comme celui de `--marquer-af` d'`essais-integration.lua` ; une photo verticale simulée, XH2S0407.RAF (Copie 1), et sa vignette de secours couchée, `rotationManquante`, Agrandir sur Focus et sur la photo active : grande vignette, rendu, liaison occupée, vignette de secours de l'aperçu), `essais-mes-demandes.lua` (le menu Mes demandes, ses fenêtres, `mes-demandes.json`, et l'absence de « ＋ Garder la demande », retiré au correctif 1.3.6), `essais-rapide.lua` (la Demande rapide : boutons à icône sans ♻, réponse effacée par une autre sélection, la conversation de la photo seule, la demande jetable de plusieurs photos, Claude Code réservé avant les lectures) ; `essais-lecon.lua` et `essais-jelefais.lua` sont retirés au correctif 1.3.6, comme les cas LECON, « Je le fais » et « J'ai fini » de `faux-claude.sh`
- `scripts/` : `tester-module.sh` (vérification du module avec LuaJIT, essais à part des deux suites compris), `metriques.swift` (chasse des polices de la fenêtre), `gabarits.lua` (les tailles des images et les palettes de `Dispositions.lua`, en JSON), lu par `images-fenetre.swift` (les images de la fenêtre B, en deux jeux) et `images-vides.swift` (l'image « aucun aperçu » de chaque apparence, `vide-498x332.png`)
- `.github/workflows/tests.yml` : syntaxe des scripts et les deux suites à chaque envoi sur `main` (macOS)
- `build.sh` (tests, compilation, signature, archive notarisée), `install.sh`, `uninstall.sh`
- `Resources/Info.plist` : identifiant `com.danymenard.mcp-developpeur` et version (incrusté par `-sectcreate` dans `Package.swift`)
- `docs/SPEC.md` : cahier des charges, protocole entre le serveur et le module, les chantiers de la 1.3 et ce qui en reste à constater, et la fenêtre Claude (architecture, contraintes du SDK, fenêtre B et ses constats, fichiers) ; `docs/aide-adobe-developpement.md` : notes sur l'aide d'Adobe (outils de développement, ordre d'utilisation, écarts avec la méthode du connecteur, ce qui reste à faire à la main), à relire avant de changer les consignes (`ServerInfo`, `Consignes.lua`) ou les invites (`Prompts`) ; captures : `capture.png` (la fenêtre Claude, fenêtre B de la 1.3.2 avec l'onglet Focus, capture principale du README ; à refaire au correctif 1.3.6 : la fenêtre de 1 623 × 1 200), `carnet.png` (la page Carnet de progrès ; à refaire au correctif 1.3.6 : la fenêtre Suivi), `publication.png`, `consommation.png`, `suivi.png` (fenêtre de la liaison) ; `docs/lavish/` : les sources des pages Lavish publiées en artefacts (feuille de route, Les 35 outils (`les-36-outils.html`, nom gardé), Guide des demandes, Apprendre avec Claude, Ordinogramme d'une retouche), une par page, à garder identiques à leur artefact
