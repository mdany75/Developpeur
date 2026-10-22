# CLAUDE.md — Développeur

Claude retouche les photos de Lightroom Classic. Deux pièces qui se parlent par TCP local
(127.0.0.1, ports 54770 et 54771 ; depuis la 1.2, chaque commande porte le jeton privé de la
liaison) : le connecteur MCP-Développeur, un serveur MCP natif (Swift, SwiftPM, sans Xcode ni
Node, exécutable `mcp-developpeur`) que Claude Desktop et Claude Code lancent sur stdio ; et le
module Lightroom Classic « Développeur » en Lua (`Lightroom/Developpeur.lrplugin`, Lightroom
Classic 13.3 au moins), qui exécute ses commandes dans le catalogue (la liaison) et porte la
fenêtre Claude (« Développeur » dans sa barre de titre) : une conversation avec Claude Code
(forfait claude.ai, jamais l'API) qui retouche et note par ce même connecteur, en une seule
disposition (la Conversation claire, à l'allure de la fenêtre B depuis la 1.3), avec les fenêtres
Publication et Consommation.

Trente-six outils : `get_status`, `list_selection`, `view_photo`, `measure_angle`,
`read_composition`, `analyze_photos`, `get_settings`, `apply_settings`, `preview_settings`,
`enhance_photo`, `add_mask`, `edit_mask`, `retouch_spots`, `copy_settings`, `list_profiles`,
`list_presets`, `save_preset`, `undo_last`, `revert_to_original`, `export_journal`,
`find_photos`, `set_metadata`, `list_keywords`, `manage_collections`, `create_virtual_copy`,
`show_photo`, `cull_photos`, `contact_sheet`, `propose_ratings`, `remove_distractions`,
`remember_style`, `export_photos`, `compare_variants`, `choose_variant`, `match_series`,
`photo_lesson` ; neuf invites :
`retouche_pro`, `harmoniser_serie`, `tri_seance`, `noter`, `portrait`, `paysage`,
`noir_et_blanc`, `nuit_iso_eleve`, `partage` ; des ressources `developpeur://` (guide de style,
standard de notation `developpeur://notation`, aperçu et journal d'une photo). Depuis la 1.2 (le
rendu plus juste), `view_photo` mesure aussi l'éclairage (`mesures › eclairage`, éclairage mixte
nommé), donne l'intention lue au boîtier d'un fichier Fujifilm (`intention_boitier`) et le bilan
chiffré d'une passe à l'autre (`bilan`, alerte « regression ») ; `add_mask` dose la peau comme
Adobe (garde-fou `smoothing_requested`) et résume la méthode du tireur (éclaircir et assombrir) ;
`get_status` dit l'écran principal du Mac (`ecran`). La 1.3 (apprendre en regardant Claude,
publiée le 21 octobre 2026) ajoute l'avant/après et la raison de
chaque étape (« Pourquoi ? », `Etapes.lua`), la leçon de la photo (`photo_lesson`), « Je le
fais » (`preview_settings` avec `my_turn`, `view_photo` avec `compare = claude_version`), la
composition lue (`read_composition`) et le carnet de progrès (constats de `view_photo` et
`measure_angle`, `export_journal` avec `notebook`, `carnet.json`), et la fenêtre B, agrandie à
1 948 × 1 200. L'exécutable a aussi ses commandes de développement (`--status`, `--call`,
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
| Essayer à la main | `swift build && ./.build/debug/mcp-developpeur --status` (inscriptions, module, état du fichier du jeton de la liaison, jamais sa valeur, écran principal, même Lightroom fermé, puis la liaison), puis `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée ; lit l'écran comme le serveur, et chaque `--call` est un nouveau processus : le bilan de `view_photo` y repart de zéro) ; `--module diagnostic` liste les fonctions du SDK offertes, et avec `'{"valeurs": true}'` lit le jeu de libellés, le filtre de la Bibliothèque et l'original de la photo active ; `--version` |
| Recette dans Lightroom | `./.build/debug/mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id> [--hauteur-horizon <0 à 1>]] [--original] [--images <dossier>]` (copies virtuelles de la collection « Développeur › Essais » que Claude n'a pas encore retouchées ; avec le vrai pont seulement, d'abord deux étapes en lecture seule : « liaison fermée (jeton privé) » (commande sans jeton, puis avec un autre jeton, refusées ; ni le jeton ni son chemin dans `get_status`) et « écran nommé (get_status) » ; le RAW passe aussi par « intention lue au boîtier (view_photo, intention_boitier) », « bilan chiffré d'une passe à l'autre (view_photo), puis annulé », puis la 1.3 (`Recette+13.swift`) : « avant/après d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé », « leçon de la photo (photo_lesson) : ISO et indices lus, refusée pour une photo d'essai, rangée pour la recette (essai_recette), relue, retirée ; photo inchangée », « carnet de progrès : photo d'essai refusée, notée pour la recette (essai_recette), exportée, retirée », et après les variantes « « Je le fais » : ma version rangée sans rien appliquer, réglages changés, comparée côte à côte, puis effacée » ; l'étape du débruitage vérifie aussi que la photo active revient ; `--horizon` : une copie d'Essais qui a un vrai horizon net, à `--hauteur-horizon` (0,5 par défaut), pour les trois étapes de la composition (lue et montrée, cadre actuel lu sur l'image entière recadrée en 4:5 et tournée de 2°, cadre proposé appliqué et horizon remesuré), la dernière sautée avec sa raison sans horizon net ; sans `--horizon`, la recette dit que la composition n'est pas vérifiée ; et, dans le tri, « éclaircir et assombrir : radial inversé et dégradé linéaire (propositions) » puis « … : forme des bords (radial inversé, propositions) » ; `--flash` : une photo au flash, pour les expositions d'après la prise de vue ; `--profondeur` : la copie d'une photo Portrait d'iPhone ; `--yeux-rouges` : une vraie photo au flash ; `--x-t20` : un RAF de X-T20, avec l'étape « point de mise au point dessiné pour noter (view_photo, af_point) » (carré dessiné si le point est lu, évaluation dite, chemin de l'original jamais rendu à Claude) et l'intention lue au boîtier ; `--portrait` : un portrait, la peau dosée (visages vus par Vision ; trois doses en propositions, détail des joues mesuré ; `amount` 50 = la moitié de la dose, jugé à l'écart maximal, 2 niveaux au plus ; peau trop lissée refusée sans `smoothing_requested`, rien d'écrit ; dose par défaut posée à `amount` 50, relue, annulée) ; `--mixte` : une photo à deux lumières, en lecture seule (éclairage mixte nommé, cases lues sur 9, durée de la mesure), puis le RAW de `--recette` en témoin à une seule lumière s'il est une autre photo ; `--original` accepte un original désigné par Dany ; `--images` : le dossier des zooms à regarder (et des deux vues du bilan) ; chacune est remise à l'origine ; l'étape « note proposée (propose_ratings), photo inchangée ; puis posée sur demande et annulée » vérifie le refus de 5 ★, range une proposition à vérifier par la vraie commande `notation`, puis pose 2 ★ par `propose_ratings` avec `apply` et les annule par `undo_last` ; le registre `notation.json` est remis ensuite comme avant l'étape, même après un échec (`notation` `remettre`, `Recette.garderRegistreDesNotes`)) |
| Recette d'une version | toutes les options dont la collection d'essai a une photo (le 21 octobre 2026 : `--jpeg`, `--x-t20`, `--portrait`, `--mixte` ; ni flash, ni yeux rouges, ni Portrait d'iPhone, ni vrai horizon : `--horizon` demande d'ajouter aux Essais une copie qui a un horizon net, mer, lac ou plaine ; la dune 53709786 ne convient pas, ses rides de sable faussent la mesure), sur des copies remises à l'origine d'abord (`revert_to_original` : une copie que Claude a déjà retouchée est refusée) ; `--mixte` sur le portrait d'essai, la seule copie à deux lumières (relevé du 20 octobre 2026) ; l'étape du témoin à une seule lumière ne vient que si le RAW de `--recette` est une autre photo ; la sortie dans un fichier, en arrière-plan, jamais tronquée (`\| head` coupe la recette au milieu d'une étape) ; puis l'essai dans la fenêtre Claude (« Publier une version », étape 3) |
| Réglages à plat | `./.build/debug/mcp-developpeur --dump [<id>]` (une clé par ligne, pour `diff` avant et après une opération faite à la main) |
| Recalage mesuré | `./.build/debug/mcp-developpeur --recalage <id>` (écarts du modèle de recalage sur la géométrie actuelle ; deux rendus « Claude · recalage » dans l'Historique) |
| Carré de mise au point | `./.build/debug/mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (ce que la fenêtre Claude lance, avec le connecteur de `cheminConnecteur`, pour l'aperçu de la photo active : `PointAF.marquer` lit le point dans un original Fujifilm en temps borné (`LecteurBoitier`), le passe dans l'image affichée et le dessine sur la vignette, carré vert, rouge si l'appareil a signalé la mise au point manquée ; code 1 sans point) |
| Écran du Mac | `./.build/debug/mcp-developpeur --ecran` (l'écran principal et les autres, avec leur profil de couleur, une ligne JSON, chemin du profil et texte de la boîte compris ; `{"lu": false}` sans écran ; lu sans Lightroom ni permission : ce que la fenêtre Claude lance pour son voyant Écran) |
| Lecture du boîtier | `./.build/debug/mcp-developpeur --boitier <original>` (un fichier Fujifilm, RAF ou JPEG, lu sans Lightroom par `LecteurBoitier` : point de mise au point, `intention_boitier` comme `view_photo`, et `valeurs_lues` sous les noms d'exiftool, pour comparer avec lui ; une ligne JSON, code 1 si rien n'est lu) |
| Relevé du carnet | `./.build/debug/mcp-developpeur --constats <id>… [<fichier.jpg>…]` (pour fixer les seuils du carnet de progrès, en lecture seule : aperçu avec `point_af` à 1 344 px et les clés de la géométrie, jamais `carnet constater` ; par photo, L* médian et 95e centile, blanc pur du tiers haut, netteté et texture (au point de mise au point aussi), bruit, ISO et si le bruit y est cherché (1.3.1 ; l'Exif d'un fichier), boîtier, géométrie, étapes de Claude, défauts cherchés et retenus, puis un résumé ; un JPEG se mesure sans Lightroom, sans point ni intention ; lignes ✘ et code 1 en cas d'échec) |
| Relevé de l'éclairage | `./.build/debug/mcp-developpeur --eclairage <id>… [<fichier.jpg>…] [--essai '{…}']` (pour fixer les seuils de l'éclairage mixte : dominantes des tons neutres par case 3 × 3 et par zone tonale, visages, zone d'intérêt et scène de Vision, aux bornes 12, 15, 20, 25 et 30 de l'écart a*b* au centre des tons neutres, chaque ligne « borne N : … ; point neutre a* x b* y, centre a* x b* y », durée de la mesure, puis un résumé ; lecture seule par la commande `apercu`, sans point AF ni original ouvert ; un fichier JPEG se mesure sans Lightroom ; `--essai` passe par `preview_settings` (deux étapes « Claude · essai »), copies virtuelles seulement) |
| Journal détaillé | `DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ; `DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre port |
| Journaux du module | `~/Library/Logs/Developpeur/module.log` (liaison, avec les commandes refusées faute du bon jeton : une ligne par genre de refus toutes les 10 s au plus, jamais le jeton) et `conversation.log` (fenêtre Claude), gardés sous 1 Mo ; échanges avec Claude Code : `~/Library/Application Support/Developpeur/Sessions/` |
| Recharger le module dans Lightroom | Fermer les fenêtres du module (devant, elles réduisent le menu Fichier), Lightroom au premier plan, puis Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du module externe › Charger de nouveau le module ext. Un fichier `.lua` ajouté depuis le lancement ne se charge pas ainsi (« Could not load toolkit script »), ni donc un fichier qui le requiert (`Commandes.lua` requiert `Notation.lua`, nouveau en 1.1, et `Etapes.lua` et `Carnet.lua`, nouveaux en 1.3), ni un raccourci clavier changé : quitter et relancer Lightroom, après toute version qui ajoute un fichier `.lua` |
| Remesurer les polices | `swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua` (la police du système, `'<system>'` en 13, 12 et 11 et `'<system/bold>'` en 13, 12, 11 et 16, et Menlo 11 : clés `texte`, `texte12`, `petit`, `gras`, `gras12`, `gras11`, `titre`, `mono` ; si une police du fil ou des cartes change dans `Fenetre.lua`, ou pour un caractère nouveau, comme ★ ☆ ⚑ ＋ ⊗ ⤢) |
| Images de la fenêtre | `luajit scripts/gabarits.lua \| swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin` (les deux jeux, `images/` en claire et `images/sombre/`, d'après `Dispositions.IMAGES` et `Dispositions.PALETTES` ; refus avant d'écrire d'une couleur absente ou invalide, d'un dossier invalide ; signale les images orphelines) ; l'image « aucun aperçu », au cadre de l'aperçu (`images/vide-498x332.png` et `images/sombre/vide-498x332.png`) : `luajit scripts/gabarits.lua \| swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` ; après tout changement des tailles ou des palettes |
| Désinstaller | `bash uninstall.sh [--tout]` (inscriptions, serveur, module, paramètres prédéfinis invisibles Lightroom fermé, fichiers de travail, dont le jeton de la liaison `liaison.jeton` et `liaison.jeton.nouveau`, que la liaison d'un Lightroom ouvert réécrit dans les 5 s : relancer le script Lightroom fermé ; `--tout` : aussi guide de style, conversations, profils de publication, consommation, notes proposées (`notation.json`), carnet de progrès et leçons (`carnet.json`), avant/après des étapes (`Etapes/`) et journaux ; jamais le catalogue ni les photos) |
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
6. Mettre à jour la feuille de route « Développeur — Feuille de route » (document claude.ai
   privé, https://claude.ai/code/artifact/9b2efe2d-d295-4655-9653-3a324d84472e, par le
   connecteur Claude Docs) : retirer ce que la version vient de livrer et corriger ce qui est
   devenu faux.

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
dans Lightroom (1.3). Ce qui attend la 1.4 va sous « ## Non publié », au-dessus de « ## 1.3 ». Le
correctif 1.3.1, tiré de l'essai réel de la 1.3 (« ## Non publié », pas encore publié ni numéroté) :
`reason` accepté par `preview_settings`, `cull_photos` sur la photo active sans cible, bruit fort au
carnet et dans la leçon seulement à ISO élevé (`Carnet.isoEleve`), leçon d'une photo d'essai
jamais rangée au carnet.
Le standard de notation (une étoile = un niveau de qualité fixe, 0 ★ = pas encore jugée, rejeter =
drapeau, Claude ne propose jamais 5 ★), venu de la section 1.1 de la feuille de route, est
maintenant le texte de `Notation.standard` (voir Règles).

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
  (« Claude · liaison », « Claude · Publication », « Claude · Consommation »), les étapes
  « Claude · … », l'instantané « Avant Claude », l'ensemble de collections « Claude » et les
  copies virtuelles « Claude » gardent le nom Claude : c'est ce que Claude a fait. Seule la barre
  de titre de la fenêtre Claude dit « Développeur » (`Fenetre.afficher`, demandé par Dany le
  20 octobre 2026) ; son menu (« Ouvrir la fenêtre Claude », ⌃⌥C, que `Raccourcis.lua` vise) et la
  documentation l'appellent toujours « fenêtre Claude ».
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
- **`PriseDeVue.defauts` est la seule liste des défauts de la prise de vue** (16 codes, axe de la
  leçon, domaine du carnet, six mesurés) ; `PriseDeVue.vocabulaire` part avec chaque constat :
  aucune liste de défauts dans le module. `Prompts.Lecon.phrase` est la seule copie de la phrase de
  leçon des invites ; `ToolHandler.descriptionRaison` (la description de `reason`, répétée dans
  chaque outil qui écrit) fait 160 caractères au plus, comme `descriptionRaisonProposition`, celle
  de `preview_settings` depuis la 1.3.1 (Claude y joignait `reason` 3 fois sur 4 et l'appel était
  refusé ; elle ne promet pas le journal). Une proposition n'écrit rien : sa raison
  ne part jamais au module (ni étape ni journal), elle revient dans la réponse (`raison`), à
  redonner à `apply_settings` ; avec `my_turn`, elle est la raison de l'entrée `exercice` du
  journal (sinon `step_name`). `ToolHandler.raison` la nettoie et la borne (300 caractères).
- **Leçon de la photo** (`photo_lesson`, `Lecon.swift`, `Tools+Lecon.swift`) : dans
  `readOnlyTools` (ni photo ni catalogue changés ; la leçon va dans `carnet.json` par la commande
  `lecon`). Les trois points sont validés avant tout envoi, leurs clés vérifiées à la main
  (`ToolHandler.nommer`) ; un module sans la commande `lecon` donne `rangee = false` et une
  remarque, jamais une erreur d'outil ; `read_facts` n'envoie que `journal`. Les indices
  (`Lecon.Seuils`, provisoires) ne sont que des remarques ; les corrections nettes viennent du
  journal de Claude (une annulation par `etape_id`, sinon par le nom entre « », un retour vide
  tout), d'où de faux indices sur une copie remise hors de Claude (constaté le 21 octobre 2026) ;
  un exercice n'est jamais appliqué. L'indice du bruit (débruitage lancé, lissage remonté) suit la
  règle du carnet (1.3.1) : seulement à un ISO connu d'au moins `Carnet.isoEleve`, lu dans
  `sensibilite` de la description du journal détaillé (`Carnet.iso`), jamais dans son texte
  (« ISO 400 »). La leçon d'une photo de « Développeur › Essais » n'est pas rangée (`lecon garder`
  rend `rangee = false`, `motif` `essai` et sa remarque, jamais une erreur ; constaté le 21 octobre
  2026 : celle de la dune d'essai était rangée sous son original, une vraie photo), sauf avec
  `essai_recette` (la recette seulement, jamais un outil), sous l'entrée de la photo d'essai
  elle-même. `prise_de_vue_plus` (`exposureBias`, `flash`,
  `exposureProgram`, `meteringMode`) se lit clé par clé par `Photos.meta`, jamais dans
  `CLES_FORMATEES` ni `batchGetFormattedMetadata` ; Lightroom 15.6 n'en refuse aucune et rend des
  textes traduits (« 0 EV », « Non déclenché », « Priorité d'ouverture » : constaté le 21 octobre
  2026), que la simulation rend aussi.
- **« Je le fais » n'applique rien** (`JeLeFais.swift`, `Variantes.lua`) : `my_turn` envoie
  `essayer` avec `instantane` « ma version », `exercice` et `sans_rendu`, jamais `entier`, et
  `raison` (`reason`, sinon `step_name`) ; la
  réponse est sans image, donc ne consomme pas la remarque de l'écran ; un module sans `exercice`
  dans sa réponse est refusé. Sa mémoire est dans `variantesClaude` (`exercice = { depart, claude,
  le }`), jamais un champ nouveau ; l'entrée `exercice` du journal n'a pas d'`etape_id`. `view_photo`
  reste en lecture seule avec `claude_version` ; la version de Claude se rend par le chemin des
  comparaisons (`rendreAvant`, `valeursAComparer`) ; `essayer` n'est pas une étape (`Etapes` ne le
  capture pas) ; `Ecriture.difference` est la seule comparaison entre états simples. L'ordre et les
  noms des panneaux n'existent qu'à `JeLeFais.panneaux` (Lightroom 15.6 en français, constaté le
  21 octobre 2026 : Color Grading, Etalonnage sans accent, Flou de l'objectif après Transformation,
  le noir et blanc dans le Mélangeur de couleurs, « Outil Recadrage » après Transformation ; les
  sections de Réglages de base restent à relever). L'écart principal reprend les seuils de `Bilan`,
  sans en ajouter ; les tolérances sont provisoires. Le contrat est figé dans
  `Tests/Contrats/je-le-fais.json` : un changement voulu se fait des deux côtés.
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
  requis que dans `constater`). `lecon` et `carnet` n'écrivent rien dans le catalogue, ne
  s'arrêtent pas à la pause et ne se rejouent jamais (`LightroomBridge.lectures` : `etapes` oui,
  `lecon` et `carnet` non). Une photo de « Développeur › Essais » n'y entre pas, ni ses constats ni
  sa leçon (1.3.1), sauf `essai_recette` (la recette seulement), sous l'entrée de la photo d'essai,
  jamais celle de son original. Côté connecteur (`Carnet.swift`) : seuils et détection
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
  le même jour, la valeur brute elle-même vérifiée par l'étape de la leçon de la recette ;
  `Vignettes.decrireVignette` et le journal détaillé), sinon `prise_de_vue.iso` d'un module 1.3 ;
  `view_photo` retire `sensibilite` avant Claude. Pas le plafond de note (`Notation.plafond`), qui
  juge l'image, ni le tri, qui ne fait que dire la mesure. Les constats notés avant restent tels
  quels ; `constats_prise_de_vue`
  seulement si le module répond `note = true`, erreurs tues ; `noterAuCarnet` n'est vrai que dans
  `serve()` (ni `--call`, ni la recette, ni les tests), et seul lui fait demander les clés de la
  géométrie ; `view_photo`, `measure_angle` et `read_composition` restent `readOnlyHint`. Seuils
  `medianeSousExposee` 28, `p95SousExposee` 80 et `partBlancPurHaut` 3 % provisoires (aucun vrai
  cas). La case Carnet ne coupe que les constats : une leçon se range encore (question ouverte à
  Dany).
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
  fenêtre Claude, et `--boitier` à la main), d'une seule ouverture par photo (aucune pour un
  avant/après), en temps borné (`LecteurBoitier`, 2 s, qui remplace `LecteurPointsAF` depuis la
  1.2) : macOS peut faire attendre `open()` sans fin (autorisation d'accès au volume) ; un original
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
  `appareil` (« mise au point signalée manquée »), `carre` (s'il est dessiné : « vert » ou
  « rouge », puis « sur l'image » ou « sur le zoom ») }. Le carré (vert,
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
  de sonde n'est encore relevé. Seul `main.swift` pose `Ecran.lire` (les outils de `serve` et de
  `--call`, et la recette pour son étape « écran nommé ») ; `get_status` dit `ecran`, sans chemin
  de profil ; sinon une remarque part une fois par processus, au premier `view_photo`,
  `preview_settings` ou `compare_variants` réussi, dans un bloc de texte à part, si l'écran n'est
  pas mesuré ; `ServerInfo.instructions` n'en dit rien. Dans la fenêtre Claude, le voyant Écran
  passe par `mcp-developpeur --ecran` (`Lightroom.etatEcran`, `LrTasks.execute`, 5 s au plus), à
  l'ouverture (`Fenetre.verifier(true)`) et au clic, jamais toutes les 2 s ; un connecteur absent,
  plus ancien ou muet le laisse gris, sans erreur. À constater : `--ecran` lancé par Lightroom voit
  l'écran en moins de 5 s, sans demande d'autorisation de macOS.
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
  floue, une mise au point manquée ou des yeux fermés ; 3 pour une photo douce ou qui n'est pas la
  meilleure de sa rafale ; 2, à vérifier, pour une photo presque noire ou brûlée, ou une mise au
  point manquée sur une texture faible, 1.3 ; 1 pour une capture), que `dernierTri`
  (`ToolHandler`) garde pour le processus du serveur. Une scène sur fond noir voulu (L* médian 3,9)
  reste dite « presque noire » : à revoir, hors de la 1.3.
- **Claude ne propose jamais 5 ★** : `propose_ratings` refuse une note de 5 ou plus avant tout
  envoi (`Notation.noteMaximale = 4`), et le module la refuse encore
  (`Notation.NOTE_MAX_PROPOSEE`) ; `set_metadata` garde 5 ★ pour l'utilisateur (à sa demande
  seulement : 5 ★ que Dany demande à Claude passent par lui), comme Changer… et les étoiles de la
  carte Note ; la carte n'offre jamais « Accepter 5 ★ » (`Fenetre.noteDeCinq`, `Fenetre.PAS_CINQ`).
  Jamais `set_metadata` pour une note sans demande. `propose_ratings` (titre « Noter des photos »)
  n'est plus en lecture seule depuis la 1.1.1 (hors de `readOnlyTools` : avec `apply`, il écrit
  dans le catalogue) ; il valide toutes les propositions avant d'envoyer quoi que ce soit (les clés
  de chaque élément à la main : `parametresInconnus` ne voit que le premier niveau), refuse une
  note au-dessus du plafond du dernier `cull_photos` sans `to_check`, refuse la passe 4 (5 ★,
  l'utilisateur seul ; le module aussi), et envoie une seule commande `notation`
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
  `depuisLightroom` est retiré des paramètres reçus du réseau : seuls les menus, la fenêtre de suivi
  et la carte Note le posent, par appel direct (toute nouvelle voie interne reste un appel direct,
  jamais une ligne TCP). Le serveur relit le fichier à chaque connexion (`JetonLiaison.lire`), une
  fois de plus après un refus, ne le crée jamais et ne dit jamais sa valeur (`--status`, `get_status`
  et le diagnostic du Gestionnaire n'en disent que l'état) ; sans fichier, il n'envoie pas de jeton,
  et un module 1.1.1 accepte la ligne. La simulation de la liaison n'imite que les deux commandes du
  système du jeton (`LrTasks.execute`) et refuse toute autre. Constaté le 21 octobre 2026 par
  l'étape « liaison fermée (jeton privé) » de la recette : une commande sans jeton, ou avec un autre
  jeton, refusée ; restent à constater l'aléa lu et les droits 600 dans Lightroom, les refus par
  `nc` et `curl`, et un ancien serveur refusé (`docs/SPEC.md`, Liaison fermée).
- `apply_settings` respecte le mode « Proposer d'abord » du module (refus sans `confirm = true`) ;
  ne pas contourner. La fenêtre Claude le montre et le bascule par les radios du Mode (clé `mode`
  des préférences du module).
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
  seulement « (read_composition) » dans « Recadrer … seulement sur demande » (un repli « …puis
  photo_lesson » n'est à faire que si Claude Desktop ne l'appelle pas, en raccourcissant d'abord une
  autre phrase) ; le reste passe par les descriptions d'outils, les résultats et les invites. La
  longueur qu'une session de Claude Code garde d'une description d'outil n'est pas constatée :
  l'essentiel en tête, et un test de longueur pour les plus longues (`add_mask` 2 048 au plus,
  `view_photo` 1 850, `photo_lesson` 1 200, `read_composition` 1 000, `preview_settings` 600,
  `analyze_photos` 520, `export_journal` avec sa propriété `notebook` 450, `reason` 160). Les
  consignes de la fenêtre (`Consignes.texte`, lues à chaque demande) font 7 466 caractères pour
  un plafond de 7 500 (`essais-moteur.lua`) : la 1.3 y a mis ses sections Composition, Je le fais,
  Raison de chaque étape et Leçon de la photo, et la puce Carnet ; ce qui dépasse va aux
  descriptions d'outils.
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
  `DeveloppeurClaude-conversation-grande-<FORME>`, `Fenetre.FORME` 4 depuis l'élargissement à
  1 948 × 1 200, 3 pour 1 497 × 1 200, 2 pour la fenêtre B de 1 280 × 800, 1 avant) : quand le
  contenu change de taille, augmenter `Fenetre.FORME`.
- **La fenêtre B** (1.3, maquette « B · Conversation claire » ; `docs/SPEC.md`, Fenêtre B),
  agrandie à la demande de Dany le 21 octobre 2026 : fenêtre de 1 948 × 1 200 (1 497 × 1 200,
  constaté à l'écran, puis élargie de 20 % à gauche, 40 % au centre et 20 % à droite), contenu de
  1 946 × 1 166 (D7 : barre de titre de 33, marge de 1 sauf en haut, constaté) ; volet 324, centre
  1 064, droite 556, filets de 1 ; aperçu 498 × 332 (vignette en 2x de 996 × 664) ; des lignes de
  fil d'environ 150 caractères (choix de Dany). `Dispositions.TAILLES` est la seule table des
  tailles, et `Dispositions.dimensions()` en tire le reste : `D.lignes` (42 lignes de 21) et
  `D.cases` (22 cases de 40) se calculent de la hauteur, comme les cartes (`D.placeCartes` 720 ;
  carte Note de 559, les autres de 679 ; `criteres` 30, `propLignes` 40, `etapeLignes` 40,
  `leconLignes` 42 : le plus de lignes qui laisse 12 points sous le contenu, ce que vérifie
  `essais-fenetre-b.lua`). Les cartes Proposition, Aperçu (étape) et Leçon descendent comme la
  carte Note jusqu'à leur rangée de boutons, posée sous elles au bas du panneau : ▲ ▼ à gauche,
  les boutons à droite, en carrés de bezel 26 et titres en 13 (`carteEtRangee` de `Vues.lua` ;
  demandé par Dany le 21 octobre 2026). Elle
  a été vue dans Lightroom le 21 octobre 2026, à 1 497 × 1 200 puis à 1 948 × 1 200 (capture
  `docs/capture.png`, essai réel de la 1.3). `Fenetre.lua`
  garde l'état, les rafraîchissements, les actions et la boucle ; les pièces sont dans `Vues.lua` ;
  l'assemblage, les dimensions, les images (`Dispositions.IMAGES`) et les apparences dans
  `Dispositions.lua` : ni `require 'Fenetre'` ni couleur créée à leur chargement (`liens.lua` les
  charge sans `LrColor`), couleurs, polices et actions arrivent par `F`. Une seule disposition, sans
  réouverture ni menu des conversations ; chaque ouverture a sa génération (`Fenetre.generation`) ;
  les conversations des anciennes séances de notation restent sur le disque, absentes de la liste,
  et `Moteur.ouvrir` les refuse.
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
- Mise en page de la fenêtre B (le détail pièce par pièce : `docs/SPEC.md`, Fenêtre B) : la
  liste des conversations en cases fixes (`Fenetre.casesListe`, pure : le Carnet de progrès en
  première case de la première page, « Plus récentes… » en tête d'une page qui en suit une autre,
  « Plus anciennes… » toujours en dernière case ; page gardée par `Fenetre.pageListe`) ; sept
  invites en carrés. L'étiquette « Style » est devant son menu, sous le champ, comme dans la
  maquette (décision de Dany après le lot B3, qui remplace le « sans étiquette » du 20 octobre
  2026) ; pas de menu Modèle (Modèle et Effort sont au Gestionnaire de modules externes). Trois
  voyants en pastilles PNG : Claude Code et Lightroom dans l'en-tête, Écran en bas du volet ; plus
  de voyant Mode. Le Mode : trois `radio_button` liés à
  `mode` (Appliquer, Proposer d'abord, Je le fais) par `Fenetre.lierRadio` (un clic, même sur le
  radio déjà coché, annule l'envoi automatique), grisés pendant que Claude travaille (décision de
  Dany), la valeur tirée de l'état (`Fenetre.modeMontre`, garde `Fenetre.modeAuto`) et reposée au
  2e tour de la boucle (`Fenetre.reposerMode`, constaté D12) ; `Fenetre.changerMode` ne suit qu'un
  vrai clic, et J'ai fini ne part jamais d'un radio. Le bandeau : deux lignes de petit texte
  (`Fenetre.LIGNES_BANDEAU`, `Fenetre.texteBandeau`, « … » au bout de la seconde), l'infobulle
  donne le texte entier ; tout message nouveau de la fenêtre passe par une constante, tient en deux
  lignes et entre dans l'essai « Bandeau » d'`essais-fenetre-b.lua`.
- Le fil B est une grille de `D.lignes` lignes de 21 (`Vues.ligneFil`, `Fil.lua`) : la colonne
  auteur de 60 (« Vous », « Claude », l'heure, posés par `Fil.lignes` sur des copies, jamais dans
  le cache), un écart de 12, le texte de 648 (`D.texteFil`, `Fenetre.largeurTexte`), coupé d'après
  la chasse mesurée (`Metriques.lua`) ; ne pas y insérer de vues de hauteur variable. Les genres à
  icône sont en retrait de 20 (`Fil.RETRAITS`) ; la ligne d'un appel (genre `appel`) est un texte
  riche, le nom en Menlo 11 (`Fil.uneLigneOutil`), et les autres variantes lisent le texte sans
  balise (`transform`) ; « Pourquoi ? » (`q..i`, carré small de 80 dans une `f:row` à
  `margin_left`, D6) est au bout d'une ligne d'étape ; le tour de Claude finit par sa ligne
  d'actions (`x..i` : « ☆ Voir la note », « Leçon de la photo »). Un clic sur une ligne se répartit
  dans l'ordre image, ligne du carnet, leçon, étape, sinon détail de l'outil
  (`Fenetre.sorteDeClic`, `Fenetre.clics`).
- Les cartes (Note, Proposition, Aperçu, Leçon) sont des colonnes superposées sur leurs images
  (carte-note, carte-proposition, carte-etape, carte-lecon), le texte à 379 en 12 points (`CARTES` :
  police `texte12`, emphase `gras12` pour la note et la leçon ; une carte sans emphase perd ses
  balises), coupé par `Fenetre.lignesCarte` et montré page par page (`Fenetre.montrerPage` ; ▲ ▼ de
  `Vues.fleches`, propriétés `<cle>Monte` et `<cle>Descend` pour `note`, `proposition`, `etape` et
  `lecon`) ; un nouveau texte revient à sa première page. Les onglets sont quatre segments en
  images sous calques (`Vues.segments`, `Fenetre.choisirSegment`), clé `onglet` : `apercu` (l'étape
  de « Pourquoi ? »), `proposition`, `notation` (par défaut) et `lecon`. Une seule bascule d'elle-même
  par arrivée : une proposition, une liste ou une comparaison « Je le fais » vers Proposition (sauf
  la proposition préparée à l'ouverture), une note pour la photo active vers Note, une leçon vers
  Leçon (`Fenetre.leconVue`, jamais quand une proposition attend ou qu'un exercice est en cours) ;
  jamais vers Aperçu. `Fenetre.surOnglet` ne suit qu'un vrai clic ; ses crochets et ceux de
  `Fenetre.apercuOnglet` sont appelés sous `pcall` hors d'une tâche, sous `LrTasks.pcall` dans une
  tâche (`LrTasks.canYield`). L'aperçu,
  commun aux quatre onglets, appartient à l'onglet (`Fenetre.apercuOnglet`, demandé d'abord par
  `rafraichirApercu` ; nil : l'aperçu commun) ; un clic sur une ligne d'image reste prioritaire
  jusqu'à un autre onglet, une image nouvelle, une autre conversation ou un clic sur une étape.
  Claude qui travaille ramène au fil (`Fenetre.revenirAuFil`).
- La carte Note B (`Vues.notation`) : les passes (`Vues.passes`, la passe 4 à Dany), les étoiles
  cliquables (`Fenetre.poserEtoile`), les drapeaux (`Fenetre.poserDrapeau`), « ? À vérifier »
  grisé, « Claude propose » en petites étoiles, la grille des critères (`Fenetre.lignesCriteres`,
  clés `ng..k`, `ne..k`, `nt..k`), le plafond et « Voir à 100 % » (décision de Dany du 21 octobre
  2026 : `Conversation.dernierZoom`, le dernier zoom de `view_photo` avec `region` sur la photo dans
  la conversation, montré dans l'aperçu par `Fenetre.voirZoom`, sans Claude ni Lightroom ; grisé
  sans zoom), puis « Laisser à N ★ », Changer… et « Accepter N ★ » en bleu (`peutAccepterNote`).
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
- Pourquoi ? dans la fenêtre : une ligne d'étape (`Conversation.estEtape`,
  `Conversation.OUTILS_ETAPES`) porte « Pourquoi ? » ; `Fenetre.pourquoi` puis `Fenetre.montrerEtape`
  ouvrent l'onglet Aperçu, jamais par une bascule ; `Fenetre.etape` désigne l'élément par son id,
  remis à nil quand la conversation change ; l'aperçu passe par `Fenetre.apercuOnglet.apercu` (◀ ▶
  coupés) ; les images se lisent par `Etapes.images` dans une tâche, réduites par
  `Images.vignette`, gardées par étape (`Fenetre.imagesEtapes`) et relues quand `Etapes.version`
  change ; Agrandir passe par `Fenetre.agrandirDeux` ; `Etapes.actifPour = Fenetre.etapesActives`,
  posé par `Fenetre.afficher` ; une conversation de la 1.2 se relit dans `detail`
  (`Conversation.infoEtape`) ; `Stockage` écrit `etapes`, `annule` et `revenu` en tableaux.
- La leçon dans la fenêtre : l'élément `lecon` (`Conversation.leconDemandee`, `leconLue`,
  `completerLecon`, `outilDeLAppel`) se fait de l'entrée de `photo_lesson`, jamais pour
  `read_facts` ; plus de carte Leçon dans le fil : l'onglet Leçon (`Vues.lecon`, `Fil.texteLecon`,
  `Fenetre.leconChoisie`, `Fenetre.AUCUNE_LECON`) ; Détail… ouvre l'appel ; `Stockage` écrit points
  et défauts en tableaux et relit une leçon en cours en erreur ; « [Sans leçon] »
  (`Consignes.sansLecon`) est joint par `Moteur.envoyer` quand `leconFinRetouche` est faux, après la
  ligne de style, sans relancer Claude Code.
- « Je le fais » dans la fenêtre : `preview_settings` avec `my_turn` fait un exercice, jamais une
  proposition à accepter ; le bouton (`titreJeLeFais`, « J'ai fini » pendant un exercice) est actif
  quand Claude est libre et qu'il y a un exercice, une proposition en attente ou une photo active ;
  le suivi (`Fenetre.suivreExercice`, toutes les 2 s) lit `getDevelopSettings` sans rien écrire
  (`Lightroom.valeurs`) et coche d'après `avant` et la signature des tables (`Lightroom.NON_SUIVIS`
  jamais coché) ; une bascule par liste et par comparaison ; pas de nouvelle conversation par photo
  pendant un exercice.
- La composition dans la fenêtre : `preview_settings` avec un `crop` (sauf `reset`) est une
  proposition de recadrage (`Conversation.cadreDemande`, `Conversation.cadreLu`, seule copie du
  libellé : `Conversation.LIBELLE_RECADRAGE`) ; la carte dit « Cadre : <résumé> » ; un vrai clic sur
  l'onglet Proposition remontre son image (`Fenetre.montrerImageProposition`) ; Ajuster… offre
  `Consignes.ajustementsCadre`.
- La page Carnet de progrès (`Fenetre.vue` `'carnet'`, `Fenetre.CARNET` `'¶carnet'`) n'a pas de genre
  de ligne à elle (des barres ▁…█ demanderaient de remesurer les polices : `Fil.lignesCarnet`,
  `Fil.tableauCarnet`) ; ses lignes n'agissent que sur la page ; Renommer… et Supprimer… y sont
  gardés ; un retrait passe par un appel direct à `Carnet.commande`, jamais une ligne TCP ; la
  lecture du résumé se fait dans une tâche, et la boucle suit `Carnet.version`.
- L'aperçu montre la photo active (légende en texte riche : le nom et sa copie, l'appareil, la date
  de prise de vue, lus par `Lightroom.legende` seulement quand la photo active change, à l'heure
  locale) à l'ouverture de la fenêtre (même déjà ouverte : menu Ouvrir la fenêtre Claude ou ⌃⌥C) et
  quand une autre photo devient active (`Fenetre.majPhoto`, `Fenetre.idActif`, `Fenetre.voirActive` ;
  demandé par Dany le 20 octobre 2026) : sa vignette vient du cache d'aperçus de Lightroom
  (`Vignettes.demander`,
  `requestJpegThumbnail`, dans une tâche), dans un dossier à elle sous
  `Chemins.temporaire()/PhotoActive` (l'ancien s'efface), réduite au cadre par `Images.vignette`,
  refaite à chaque ouverture. Une image nouvelle de la conversation montrée (`Fenetre.nbImages`)
  la remplace ; ◀ revient aux images de la conversation, ▶ depuis la dernière y retourne ; un clic
  sur une ligne d'image relit les images d'abord (pas de bascule).
- Sur la vignette de la photo active d'un fichier Fujifilm (marque, ou original `.RAF`), le carré
  de mise au point est dessiné avant la réduction (`Fenetre.marquerMiseAuPoint`, demandé par Dany
  le 20 octobre 2026) : `Images.marquerMiseAuPoint` lance par `LrTasks.execute` le connecteur de
  `cheminConnecteur` (s'il existe), `mcp-developpeur --marquer-af <original> '<géométrie JSON>'
  <vignette.jpg> <sortie.jpg>` (géométrie de `Vignettes.decrireVignette`) ; `PointAF.marquer` lit
  le point dans l'original en temps borné, le passe dans l'image affichée et écrit `<nom>-af.jpg`
  à côté de la vignette, carré vert, rouge si l'appareil a signalé la mise au point manquée ;
  code 1 sans point (l'aperçu reste sans carré, sans rien au journal). Autre marque : pas d'appel,
  l'original n'est pas ouvert. Agrandir montre la vignette marquée.
- À l'ouverture de la fenêtre Claude, et quand le menu ou ⌃⌥C la rappelle, Claude prépare une
  proposition de retouche de la photo active (`Fenetre.proposerAOuverture`, après
  `Fenetre.majPhoto` ; demandé par Dany le 20 octobre 2026) : seulement si la préférence
  `propositionAOuverture` est vraie (`Chemins.defauts`, vraie par défaut ; case « À l'ouverture :
  Claude prépare une proposition de retouche (rien n'est appliqué) » de la section Fenêtre Claude
  du Gestionnaire de modules externes, que le diagnostic dit), qu'une photo est active, que Claude
  est libre et que la conversation montrée est vide (une autre photo en commence une). La demande
  est `Consignes.proposerOuverture` (la noter d'abord si elle n'est pas encore évaluée, puis
  `preview_settings`, sans rien appliquer) ; la proposition attend dans l'onglet Proposition sans
  y basculer (`Fenetre.propositionAuto`, effacé par la demande suivante de Dany,
  `Fenetre.envoyer`).
- Une autre photo active ou une autre sélection, choisie par Dany, commence une nouvelle
  conversation (`Fenetre.suivreSelection`, depuis `Fenetre.majPhoto` ; préférence
  `nouvelleParPhoto`, case « Autre photo » du Gestionnaire, cochée par défaut ; demandé par Dany le
  20 octobre 2026) : quand la clé de `Lightroom.photos` (`info.cle` : la photo active, le nombre de
  photos sélectionnées et les 500 premières) change, et que la conversation montrée a déjà des
  messages et parlait d'autres photos (`c.cle`, posée à chaque demande par `Fenetre.envoyer`). Si
  Claude a travaillé depuis que la sélection d'avant a été vue (`Moteur.travaille`, ou
  `Moteur.finTravail` plus `Fenetre.DELAI_APRES_TRAVAIL`, 4 s, au-delà de l'heure où elle a été
  vue), la sélection changée peut être la sienne (`show_photo`, tri) : elle devient celle de la
  conversation. La fin du travail est datée par le moteur (`Moteur.finTravail`, fenêtre ouverte ou
  fermée) ; la fenêtre garde la sélection vue et son heure (`Fenetre.voirSelection` :
  `Fenetre.cleVue`, `Fenetre.cleVueLe`) d'une ouverture à l'autre : une photo choisie fenêtre
  fermée compte aussi, et une fenêtre fermée pendant que Claude travaillait retrouve sa
  conversation à la réouverture. Une conversation vide n'est pas remplacée, ni une conversation
  pendant un exercice « Je le fais » ; sur la page Carnet, la nouvelle conversation se prépare sans
  quitter la page (`Fenetre.nouvelle(garderPage)`).
- Ne jamais nommer un fichier du module `Versions.lua` : Lightroom refuse de le charger (constaté ;
  d'où `Composants.lua`). Un seul `Info.lua`, `Init.lua`, `Arret.lua` et `PluginInfoProvider.lua`
  pour la liaison et la fenêtre, sans fichier de fusion (`InfoFenetre.lua`…) :
  `scripts/tester-module.sh` refuse l'un et l'autre.
- Un raccourci d'app vise le titre exact de l'entrée de menu, tel que Lightroom l'écrit : trois
  espaces devant chaque entrée de module (`Raccourcis.RETRAIT`, constaté par l'accessibilité).
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
  disposition, la fenêtre B de la 1.3 avec ses étapes, « Pourquoi ? » et la leçon de la photo ;
  `docs/carnet.png`, la page Carnet de progrès ; `publication.png`, `consommation.png`,
  `suivi.png` : les autres fenêtres ; `seance.png` est retirée avec la Séance en 1.1.1,
  `atelier.png` et `panneau.png` avec l'Atelier et le Panneau en 1.2), et une nouvelle version si ce
  qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/DeveloppeurKit/` : `JSONValue` (JSON générique), `MCPServer` (JSON-RPC, initialize, tools, prompts, ressources), `FileOutils` (appels d'outils un à un, réponse d'attente avant les 60 s de Claude Desktop), `Progression` (notifications de progression), `ContexteAppel` (progression et annulation d'un appel), `Tools` (socle des outils, 36 ; `lireEcran`, l'écran dans `get_status` ou dit une fois au premier aperçu ; `vuesMesurees` et `zoomsMesures` du bilan ; `lecteurBoitier` ; `noterAuCarnet` ; `descriptionRaison`, la raison d'une étape) et ses extensions `Tools+Analyse` (aperçu, avec le point de mise au point, sur un zoom aussi, l'évaluation de la photo, l'éclairage, l'intention du boîtier et le bilan d'une passe à l'autre ; zoom et son `bilan_zone`, comparaison et son bilan, mesures de série, réglages ; `mesurerImage` ; `compare = claude_version` de « Je le fais », `comparaisons` ; la vue et la ligne au carnet : `noterLaVue`, `noterLAngle`, `constaterAuCarnet`), `Tools+Retouche` (`apply_settings`, `preview_settings`, avec le bilan d'une proposition, la surimpression du cadre proposé et `my_turn` : `monTour` ; `enhance_photo`, `remove_distractions`), `Tools+Balance` (balance sur un point neutre ; `balanceProposee` d'un éclairage mixte), `Tools+Locales` (masques, taches, yeux rouges ; garde-fou de la peau, résumé du tireur dans la description d'`add_mask`), `Tools+Recalage` (grilles demandées, gardées en mémoire), `Tools+Gestion` (copie, profils, paramètres prédéfinis, journal ; `export_journal` avec `notebook`), `Tools+Bibliotheque` (recherche, classement, mots-clés, collections, copies virtuelles, photo montrée), `Tools+Tri` (tri d'une séance, planche contact jusqu'à 30 vignettes, vignettes par lots), `Tools+Notation` (`propose_ratings`, validé avant la commande `notation` ; notes posées avec `apply`), `Tools+Livraison` (`export_photos` : formats, HDR, poids, filigrane, réimportation, livraisons types lues dans les services Disque dur, noms exacts, dossier choisi, aperçus dynamiques, fenêtre d'exportation en dernier recours ; modèles de noms de fichiers et filigranes de l'utilisateur, relecture du fichier livré), `Tools+Variantes` (`compare_variants`, `choose_variant`), `Tools+Serie` (`match_series`, pentes de la balance, expositions d'après la prise de vue), `Tools+Style` (`remember_style`, ressources), `Tools+Lecon` (`photo_lesson` : journal détaillé, départ de `vuesMesurees`, `lecon garder`), `Tools+Composition` (`read_composition`, `apercu` avec `entier`) ; `PriseDeVue` (vocabulaire des défauts de la prise de vue, seule liste : 16 codes, axes de la leçon, domaines du carnet, six mesurés ; `vocabulaire` envoyé au module), `Lecon` (partie pure de la leçon : points validés, corrections nettes du journal, indices à seuils provisoires `Lecon.Seuils`, faits, remarques, texte, forme pour le module), `JeLeFais` (ordre et noms des panneaux, seule copie ; place et nom court d'un réglage, liste à faire, tolérances, classement, écart principal ramené aux seuils du bilan ; pur), `Composition` (cadre dans l'image entière, passage de `view_photo` à l'image entière, plus grand cadre, cadre proposé et ordre de relâche, crop, résumé, lecture, regard, visages renversés et zone d'intérêt écartés ; pur), `Carnet` (seuils du carnet, dont `isoEleve`, `iso` et `bruitCherche`, `constatsVue`, `constatHorizon`, `geometrieIntacte`, Markdown d'`export_journal`, relevé `--constats`), `Tri` (défauts, rafales, ordre de lecture, plafonds de note, rejets proposés ; `PhotoTriee.defautsNettete`, seule copie des règles de netteté, partagée avec le carnet ; mise au point jugée sur la texture), `Notation` (standard de notation, seule copie ; plafonds de note), `Boitier` (lecture de l'original Fujifilm d'une seule ouverture, Exif et MakerNote : point de mise au point et intention, `LectureBoitier` ; lecteur borné `LecteurBoitier`), `IntentionBoitier` (simulation, couleur, plage dynamique, tons, compensation, mode, balance, scène ; profil Lightroom de la simulation ; lecture pour Claude, `intention_boitier`), `PointAF` (point de mise au point des fichiers Fujifilm, passage dans l'image affichée ; `PointAF.marquer` pour `--marquer-af`), `Peau` (dosage de la peau d'après Adobe, seule copie ; effets intégrés « Peau du visage lisse » et « Adoucir la peau (Lite) » ; garde-fou d'`add_mask`), `Eclairage` (`MesureEclairage` : point neutre de l'image et centre des tons presque neutres, dominante par zone tonale et par case 3 × 3, visages à part, deux groupes de lumière et éclairage mixte, médianes par histogramme ; relevé `--eclairage`), `Bilan` (bilan chiffré d'une passe à l'autre, en fonctions pures : écarts visibles, régressions, à vérifier ; empreintes du cadre et de l'état ; les vues gardées sont à `ToolHandler`), `Ecran` (écran principal et profil ColorSync, six classes, textes, JSON ; remarque d'écran ; `--ecran`), `JetonLiaison` (fichier du jeton de la liaison : chemin, lecture, état pour `--status`), `MotsClesVision` (mots-clés de Vision traduits), `ModeleCouleur` (modèle d'une couleur prélevée), `ProfilsObjectif` (profils d'objectif `.lcp` installés), `GuideStyle` (guide de style de l'utilisateur, `~/Library/Application Support/Developpeur/guide-de-style.md`), `ReglagesAPlat` (`--dump`), `Catalogue` (les 124 réglages de développement, version minimale de Lightroom des plus récents, les profils d'appareil, les libellés), `Mesures` (mesures d'un aperçu, seuils nommés, tons neutres suivis d'une vue à l'autre), `Detail` (netteté et bruit, seuils nommés ; texture autour du point de mise au point, `Detail.autour`, `textureMin`, `textureDouteuse`), `AnalyseVision` (visages avec leur lacet et leur roulis, pupilles, note esthétique, saillance, photos semblables, cadres des personnes), `Lignes` (angle d'une ligne désignée ; « affinée » seulement sous `LineAngle.ecartMax`), `Recalage` (correspondance entre l'image corrigée et celle d'avant la correction d'objectif, Upright et la perspective), `Recette` (recette dans le vrai Lightroom ; aussi `lectureBoitier` pour `--boitier`, `Luminances`, `partAssombrie` et `formeDesBords` pour éclaircir et assombrir, `ecartMax` pour l'intensité de la peau, `dureeEclairage`, `resumeEcarts` ; photo active comparée, `ecartPhotoActive`, et registre des notes remis, `garderRegistreDesNotes`), `Recette+13` (recette de la 1.3 : Pourquoi ?, leçon, carnet, Je le fais, composition), `Images` (zoom, côte à côte, planche contact, carré du point de mise au point : `PreviewImages.marquerPoint` ; cadre proposé en pointillés : `PreviewImages.cadrePropose`), `ProfilsLook` (profils à base de Look installés), `EffetsLocaux` (effets locaux de Lightroom, `.lrtemplate`, puis les effets intégrés de `Peau` qui manquent), `PresetXMP` (paramètres prédéfinis XMP), `LightroomBridge` (client TCP du module, avec le jeton de la liaison dans chaque ligne), `Prompts` (invites ; `Prompts.Tireur` : doses et forme d'éclaircir et assombrir, seule copie), `ClaudeRegistration` (inscription dans les fichiers de configuration de Claude), `MiseAJour` (dernière version publiée, par `gh`, pour `--status`), `ServerInfo` (nom, titre, version, consignes données à Claude)
- `Sources/MCPDeveloppeur/main.swift` : options de ligne de commande (dont `--marquer-af`, pour l'aperçu de la photo active de la fenêtre Claude, et `--ecran`, pour son voyant Écran ; `--boitier`, `--eclairage` et `--constats`, relevés à la main ; `--recette` avec `--horizon` et `--hauteur-horizon` ; `--status`, avec l'état du jeton et l'écran) et boucle stdio ; `outils()` pose `Ecran.lire` pour le serveur et `--call` ; `noterAuCarnet` vrai dans `serve()` seulement
- `Lightroom/Developpeur.lrplugin/`, le module :
  - déclaration et cycle de vie : `Info.lua` (« Développeur », `com.danymenard.developpeur`, menus, version), `Init.lua` / `Arret.lua`, `Menage.lua` (paramètres prédéfinis invisibles effacés), `PluginInfoProvider.lua` (Gestionnaire de modules externes : section liaison, avec Mise au point et Carnet et, au diagnostic, l'état du jeton, les commandes refusées et les photos du carnet, et section fenêtre Claude, avec modèle, effort, apparence, Autre photo, À l'ouverture, Avant/après et Leçon), `Preferences.lua` (réglages de la liaison, dont `pointMiseAuPoint` et `carnet` ; ceux de la fenêtre dans `Chemins.defauts`, même table), `Metadonnees.lua` (champs privés), `Menu*.lua` (les huit entrées de Module externe - Extras, dans Fichier et Bibliothèque)
  - la liaison : `Liaison.lua` (prises LrSocket, jeton privé et refus des lignes sans lui, `module.log`), `Commandes.lua` (répartition des commandes du serveur) et les modules qui les portent : `Lecture.lua` (état, avec `liaison_fermee`, sélection, réglages, paramètres prédéfinis, diagnostic, journal, détaillé pour la leçon), `Rendu.lua` (aperçus, avec `point_af` : photo décrite par `Vignettes.decrireVignette`, évaluation, et `etapes_claude` pour le bilan ; image entière et cadre relu, `sansRecadrage` partagé avec le recalage ; version de Claude d'un exercice ; la vue gardée pour `Etapes` ; propositions, `essayer` avec `exercice`, `sans_rendu` et `entier`, rendus du recalage), `Etapes.lua` (avant/après des étapes : empreinte, vue, capture autour de chaque commande, commande `etapes`, `Etapes.images` pour la fenêtre, ménage), `Carnet.lua` (registre `carnet.json` : commandes `lecon` et `carnet`, `constater`, `Carnet.resumer`, `photosDuDefaut`, `vocabulaire`, `estPhotoDEssai`), `Retouche.lua` (appliquer, recadrer, masquer, retoucher, copier), `Amelioration.lua` (débruitage, détails bruts, super résolution), `Suppression.lua` (reflets, retrait de la poussière), `Masques.lua` (reprendre un masque : commande `masques` ; masques vides), `Conversions.lua` (rotation d'un quart de tour), `Progression.lua` (barre de progression de Lightroom pendant une série : commande `progression`), `Vignettes.lua` (vignettes du cache d'aperçus : commande `vignettes` ; `decrireVignette`, aussi pour l'aperçu de `view_photo`), `Notation.lua` (registre des notes proposées, `notation.json` : commande `notation`, avec `remettre` pour la recette, `Notation.poser`), `Livraison.lua` (exporter, fenêtre d'exportation, options de livraison, dossier choisi dans une fenêtre, noms exacts, aperçus dynamiques), `Services.lua` (services de publication et réglages des services Disque dur, lus seulement), `Variantes.lua` (variantes en instantanés ; l'exercice « Je le fais » : `departExercice`, `valeursClaude`, `ecartsExercice`), `Annulation.lua` (annuler, revenir), `Bibliotheque.lua` (classement, paramètres prédéfinis de métadonnées, mots-clés, collections, recherche, copies virtuelles, photo montrée et filtre de la Bibliothèque : commandes `metadonnees`, `motsCles`, `collections`, `chercher`, `copieVirtuelle`, `montrer` ; notes acceptées ou posées sur demande : `Bibliotheque.noter` ; photo active et sélection remises : `Bibliotheque.remettreSelection`) ; leur socle : `Photos.lua` (photos visées, description, sensibilité ISO en nombre, mémoire de Claude), `Reglages.lua` (valeurs de développement), `Recalage.lua` (géométrie, grille du serveur), `Plans.lua` (ce qu'une retouche changera), `Ecriture.lua` (écriture dans le catalogue, étapes avec leur id, `Ecriture.nouvelleEtape`, journal, `Ecriture.difference`), `Profils.lua` (profil relu après l'écriture), `Recadrage.lua` (calcul du cadre), `Geometrie.lua` (positions de l'aperçu vers le fichier), `Locaux.lua` (tables des masques, taches et yeux rouges) — ces trois-là sans SDK —, `Json.lua`, `Suivi.lua` (fenêtre de suivi « Claude · liaison »)
  - la fenêtre Claude : `Fenetre.lua` (la fenêtre : état, actions, boucle, apparence, calques et boutons, liste en cases, Mode, bandeau, textes des cartes page par page, carte Note B, aperçu de la photo active et son carré de mise au point, proposition préparée à l'ouverture, nouvelle conversation par photo, voyant Écran lu à l'ouverture et au clic, aide d'une liaison sans jeton ; onglets Aperçu, Proposition, Note et Leçon : l'étape de « Pourquoi ? », l'exercice « Je le fais » et son suivi, la composition, la leçon ; page Carnet de progrès), `Vues.lua` (ses pièces : aplats, images, boutons bleus, éléments inactifs, ligne du fil, volet et liste, en-tête et Mode, voyants, saisie et bandeau, segments, aperçu, cartes Proposition, Aperçu, Leçon et Note, et la fabrique masquable des onglets ; ni Noter ni Évaluer), `Dispositions.lua` (la fenêtre B, seule disposition : tailles, dimensions, images, apparences et palettes), `Fil.lua` (le fil en lignes : texte riche, appel, auteur et heure, actions ; la leçon, la page du carnet), `Metriques.lua` (chasse des polices, produite par `scripts/metriques.swift`), `Moteur.lua` (conversations et processus de Claude Code, indépendants de la fenêtre ; modèle et effort d'une demande), `Session.lua` (un processus Claude Code par `relais.sh`), `relais.sh`, `Evenements.lua` (lignes stream-json de Claude Code), `Conversation.lua` (éléments d'une conversation : étapes, leçon, exercice, cadre demandé, dernier zoom), `Stockage.lua` (conversations sur le disque), `Images.lua` (aperçus et photos jointes, base64 et `sips` ; carré de mise au point par le connecteur : `Images.marquerMiseAuPoint`), `presse-papiers.js` (lecture du presse-papiers par `osascript`), `Consignes.lua` (consignes ajoutées, dont la section Écran, les puces Peau (sans chiffres), Notes (la note d'abord de chaque photo traitée) et Mise au point montrée, et le résumé chiffré du bilan ; depuis la 1.3, les sections Composition, Je le fais, Raison de chaque étape et Leçon de la photo, et la puce Carnet ; sept invites en raccourcis, dont Portrait, Paysage et Noir et blanc qui demandent la méthode du tireur sans chiffres, et Composition ; messages de Je le fais, J'ai fini et du carnet, « [Sans leçon] », ajustements du cadre ; demande de la proposition à l'ouverture, réponses aux propositions, styles, modèles et efforts), `Lightroom.lua` (photo active, sa note et sa légende, sélection et sa clé, réglages suivis d'un exercice, état de la liaison, connexion de Claude Code, écran principal par `mcp-developpeur --ecran`), `Composants.lua` (versions du module et du connecteur en bas du volet), `Raccourcis.lua` (⌃⌥C), `Chemins.lua` (dossiers et réglages de la fenêtre), `Fichiers.lua`, `Texte.lua` (UTF-8), `Journal.lua` (`conversation.log`), `Compat.lua` (`os.time`, `os.date`), `images/` et `images/sombre/` (les images de la fenêtre B en 2x, un jeu par apparence, dont `vide-498x332.png`, l'image « aucun aperçu ») ; `FenetrePublication.lua` et `Publication.lua` (profils et exportation de la fenêtre Publication), `FenetreConsommation.lua` et `Consommation.lua` (jetons comptés, budget de la semaine). La Séance de notation (`FenetreNotation.lua`, `MenuNotation.lua`) est retirée depuis la 1.1.1 (demandé par Dany le 20 octobre 2026)
- `Tests/DeveloppeurKitTests/` : tests XCTest avec `FakeLightroom` et `FakePlugin` (TCP, dans `LightroomBridgeTests` ; `jetonAttendu` : le jeton qu'il exige, nil pour un module d'avant la 1.2) ; pour la 1.2 : `PeauTests`, `BoitierTests` (fichiers Fujifilm fabriqués, tons en SLONG et en LONG), `EclairageTests`, `BilanTests` (longueur des descriptions de `view_photo`, `preview_settings` et `analyze_photos` comprise), `EcranTests` (tests purs, `get_status`, la remarque une fois ; la lecture du vrai écran avec `DEVELOPPEUR_ECRAN_REEL=1` seulement), `JetonLiaisonTests` ; pour la 1.3 : `PriseDeVueTests`, `PourquoiTests`, `LeconTests`, `JeLeFaisTests` et `ContratJeLeFaisTests`, `CompositionTests` et `ContratCompositionTests`, `CarnetTests`, `Recette13Tests` (un module simulé à état). `FakeLightroom` note `progression`, `lecon` et `carnet` à part (`progressions`, `lecons`, `carnets`)
- `Tests/Contrats/` : `je-le-fais.json` et `composition.json`, les échanges figés entre le serveur et le module, lus par les essais Swift et Lua (un changement voulu se fait des deux côtés)
- `Tests/Lua/Liaison/` : `Simulation.lua` (SDK de Lightroom simulé pour les commandes du serveur ; `LrTasks.execute` n'y imite que les deux commandes du fichier du jeton et refuse toute autre ; un `Mask/CircularGradient` sans `Flipped = true` ou sans `MaskInverted` booléen y est refusé ; `isoSpeedRating` brut y est un nombre, jamais le texte formaté ; le film fixe suit la source affichée, `S.visiblesSous` ; un `MaskGroupBasedCorrections` vide tombe aux rendus du recalage), `Aides.lua` (aides communes et remise à zéro par module, `A.remiseAZero`), `tests.lua`, les essais à part `essais-carnet.lua`, `essais-composition.lua`, `essais-etapes.lua`, `essais-jelefais.lua`, `essais-lecon.lua`, `essais-registre.lua`, et `liens.lua` (chaque champ lu d'un module requis existe, dans tous les fichiers du module)
- `Tests/Lua/Fenetre/` : `Simulation.lua` (SDK simulé pour la fenêtre, dossier personnel temporaire, liaison jamais démarrée ; refuse `visible` sur `row`, `column`, `group_box`, `tab_view` et `scrolled_view`, évalue les liaisons à plusieurs clés ; d'après les constats du 21 octobre 2026, refuse aussi `background_color` sur `row`, `column`, `view`, `group_box` et la fenêtre, `primary_line_color`, `mouse_down` sur un `f:picture`, un `f:picture` sans taille ou sans image ni fond, `image_name` avec un titre, plus d'un `default = true`, un `<EM>` mal formé ou sans `emphasis_font`, `presse-papiers.js` sans nom ; imite la frappe, Retour et les clics, `S.taper`, `S.retour`, `S.cliquer`, et refuse un geste sur une vue masquée ou inactive ; donne `copyName`, `cameraModel` et `dateTimeOriginal`), `faux-claude.sh` (imite Claude Code en stream-json), `tests.lua`, et les essais à part `essais-*.lua` (chacun charge la simulation, la complète localement sans toucher `Simulation.lua`, a ses propres aides et sort en échec si un essai échoue ; tous lancés par `tester-module.sh`) : `essais-dispositions.lua`, `essais-moteur.lua`, `essais-integration.lua` (de bout en bout avec les vrais modules, `sips` compris), `essais-gestionnaire.lua`, `essais-images.lua` (palettes et images des deux apparences), `essais-fenetre-b.lua` (cadre, tailles, contrôles, carte Note B, bandeau), `essais-pourquoi.lua`, `essais-lecon.lua`, `essais-jelefais.lua`, `essais-composition.lua`, `essais-carnet.lua` ; `faux-claude.sh` a les cas LECON, « Je le fais » et « J'ai fini »
- `scripts/` : `tester-module.sh` (vérification du module avec LuaJIT, essais à part des deux suites compris), `metriques.swift` (chasse des polices de la fenêtre), `gabarits.lua` (les tailles des images et les palettes de `Dispositions.lua`, en JSON), lu par `images-fenetre.swift` (les images de la fenêtre B, en deux jeux) et `images-vides.swift` (l'image « aucun aperçu » de chaque apparence, `vide-498x332.png`)
- `.github/workflows/tests.yml` : syntaxe des scripts et les deux suites à chaque envoi sur `main` (macOS)
- `build.sh` (tests, compilation, signature, archive notarisée), `install.sh`, `uninstall.sh`
- `Resources/Info.plist` : identifiant `com.danymenard.mcp-developpeur` et version (incrusté par `-sectcreate` dans `Package.swift`)
- `docs/SPEC.md` : cahier des charges, protocole entre le serveur et le module, les chantiers de la 1.3 et ce qui en reste à constater, et la fenêtre Claude (architecture, contraintes du SDK, fenêtre B et ses constats, fichiers) ; `docs/aide-adobe-developpement.md` : notes sur l'aide d'Adobe (outils de développement, ordre d'utilisation, écarts avec la méthode du connecteur, ce qui reste à faire à la main), à relire avant de changer les consignes (`ServerInfo`, `Consignes.lua`) ou les invites (`Prompts`) ; captures : `capture.png` (la fenêtre Claude, fenêtre B de la 1.3, capture principale du README), `carnet.png` (la page Carnet de progrès), `publication.png`, `consommation.png`, `suivi.png` (fenêtre de suivi de la liaison)
