# CLAUDE.md — Développeur

Claude retouche les photos de Lightroom Classic. Deux pièces qui se parlent par TCP local
(127.0.0.1, ports 54770 et 54771 ; depuis la 1.2, chaque commande porte le jeton privé de la
liaison) : le connecteur MCP-Développeur, un serveur MCP natif (Swift, SwiftPM, sans Xcode ni
Node, exécutable `mcp-developpeur`) que Claude Desktop et Claude Code lancent sur stdio ; et le
module Lightroom Classic « Développeur » en Lua (`Lightroom/Developpeur.lrplugin`, Lightroom
Classic 13.3 au moins), qui exécute ses commandes dans le catalogue (la liaison) et porte la
fenêtre Claude (« Développeur v » et la version du module dans sa barre de titre, « Développeur
v1.4 ») : une conversation avec Claude Code
(forfait claude.ai, jamais l'API) qui retouche et note par ce même connecteur, en une seule
disposition (la Conversation claire, à l'allure de la fenêtre B depuis la 1.3), une conversation
par photo depuis le correctif 1.3.6, avec les fenêtres Demande rapide, Suivi (les photos ouvertes et
le carnet de progrès en graphiques depuis le correctif 1.3.7), Publication et Consommation.

Trente-six outils : `get_status`, `list_selection`, `view_photo`, `measure_angle`,
`read_composition`, `analyze_photos`, `get_settings`, `apply_settings`, `preview_settings`,
`enhance_photo`, `add_mask`, `edit_mask`, `retouch_spots`, `copy_settings`, `list_profiles`,
`list_presets`, `save_preset`, `undo_last`, `revert_to_original`, `export_journal`,
`find_photos`, `set_metadata`, `list_keywords`, `manage_collections`, `create_virtual_copy`,
`show_photo`, `cull_photos`, `contact_sheet`, `propose_ratings`, `remove_distractions`,
`generative_edit` (29 octobre 2026), `remember_style`, `export_photos`, `compare_variants`, `choose_variant`, `match_series` ; dix
invites :
`retouche_pro`, `a_ma_facon` (1.3.5), `harmoniser_serie`, `tri_seance`, `noter`, `portrait`, `paysage`,
`noir_et_blanc`, `nuit_iso_eleve`, `partage` ; des ressources `developpeur://` (guide de style,
standard de notation `developpeur://notation`, aperçu et journal d'une photo). L'exécutable a aussi
ses commandes pour la fenêtre Claude (`--marquer-af`, `--focus`, `--analyser`, `--graphiques`) et
de développement (`--status`, `--call`,
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
| Tester le serveur | `swift test` (jamais le vrai Lightroom, ni le vrai jeton, ni le vrai écran, ni le vrai mflux) ; `DEVELOPPEUR_ECRAN_REEL=1 swift test --filter EcranTests` lit en plus le vrai écran du Mac (`testLectureReelleSansPlantage`, sauté sans cette variable : lecture seule, aucune valeur attendue) |
| Tester le module | `scripts/tester-module.sh` (LuaJIT : `brew install luajit`) : forme du module, syntaxe, globales, liens entre les fichiers, puis les suites `Tests/Lua/Liaison` et `Tests/Lua/Fenetre`, et chaque `essais-*.lua` des deux ; `DEVELOPPEUR_SUIVI_ORIGINAUX=250000 scripts/tester-module.sh` fait l'essai « Taille réelle » d'`essais-releve.lua` à la borne de 250 000 originaux (85 000 par défaut ; plus long) |
| Essayer à la main | `swift build && ./.build/debug/mcp-developpeur --status` (inscriptions, module, état du fichier du jeton de la liaison, jamais sa valeur, le nom de l'écran principal, même Lightroom fermé, puis la liaison), puis `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée ; lit l'écran comme le serveur, et chaque `--call` est un nouveau processus : le bilan de `view_photo` y repart de zéro) ; `--module diagnostic` liste les fonctions du SDK offertes, et avec `'{"valeurs": true}'` lit le jeu de libellés, le filtre de la Bibliothèque et l'original de la photo active ; `--version` |
| Recette dans Lightroom | `./.build/debug/mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id> [--hauteur-horizon <0 à 1>]] [--original] [--images <dossier>]` (copies virtuelles de la collection « Développeur › Essais » que Claude n'a pas encore retouchées ; avec le vrai pont seulement, d'abord deux étapes en lecture seule : « liaison fermée (jeton privé) » (commande sans jeton, puis avec un autre jeton, refusées ; ni le jeton ni son chemin dans `get_status`) et « écran nommé (get_status) » (un nom non vide, rien d'autre que `nom` et `autres` chez Claude, depuis le correctif 1.3.6) ; le RAW passe aussi par « intention lue au boîtier (view_photo, intention_boitier) », « bilan chiffré d'une passe à l'autre (view_photo), puis annulé », puis la 1.3 (`Recette+13.swift`) : « avant/après d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé » et « carnet de progrès : photo d'essai refusée, notée pour la recette (essai_recette), exportée, retirée » (les étapes de la leçon de la photo et de « Je le fais » sont retirées avec eux au correctif 1.3.6) ; l'étape du débruitage vérifie aussi que la photo active revient ; `--horizon` : une copie d'Essais qui a un vrai horizon net, à `--hauteur-horizon` (0,5 par défaut), pour les trois étapes de la composition (lue et montrée, cadre actuel lu sur l'image entière recadrée en 4:5 et tournée de 2°, cadre proposé appliqué et horizon remesuré), la dernière sautée avec sa raison sans horizon net ; sans `--horizon`, la recette dit que la composition n'est pas vérifiée ; et, dans le tri, « éclaircir et assombrir : radial inversé et dégradé linéaire (propositions) » puis « … : forme des bords (radial inversé, propositions) » ; `--flash` : une photo au flash, pour les expositions d'après la prise de vue ; `--profondeur` : la copie d'une photo Portrait d'iPhone ; `--yeux-rouges` : une vraie photo au flash ; `--x-t20` : un RAF de X-T20, avec l'étape « point de mise au point dessiné pour noter (view_photo, af_point) » (carré dessiné si le point est lu, évaluation dite, chemin de l'original jamais rendu à Claude) et l'intention lue au boîtier ; `--portrait` : un portrait, la carte du masque (1.3.4 : peau du visage et arrière-plan en proposition, `mask_map` ; la peau couvre le visage, l'arrière-plan n'y déborde pas, aucune alerte) et la peau dosée (visages vus par Vision ; trois doses en propositions, détail des joues mesuré ; `amount` 50 = la moitié de la dose, jugé à l'écart maximal, 2 niveaux au plus ; peau trop lissée refusée sans `smoothing_requested`, rien d'écrit ; dose par défaut posée à `amount` 50, relue, annulée) ; `--mixte` : une photo à deux lumières, en lecture seule (éclairage mixte nommé, cases lues sur 9, durée de la mesure), puis le RAW de `--recette` en témoin à une seule lumière s'il est une autre photo ; `--original` accepte un original désigné par Dany ; `--images` : le dossier des zooms à regarder (et des deux vues du bilan) ; chacune est remise à l'origine ; l'étape « note proposée (propose_ratings), photo inchangée ; puis posée sur demande et annulée » vérifie le refus de 6 ★ (5 ★ refusées jusqu'à la 1.3.1), range une proposition à vérifier par la vraie commande `notation`, puis pose 2 ★ par `propose_ratings` avec `apply` et les annule par `undo_last` ; le registre `notation.json` est remis ensuite comme avant l'étape, même après un échec (`notation` `remettre`, `Recette.garderRegistreDesNotes`) ; enfin la 1.4 (`Recette+14.swift`), sur toutes les photos données dès qu'il y en a deux : « groupes de lumière (match_series, groups), rien d'écrit » (chaque photo comptée une fois dans un groupe ou seule, aucun réglage changé, la prise de vue en nombres lue par la commande `vignettes` : ouverture, vitesse, flash)) |
| Recette d'une version | toutes les options dont la collection d'essai a une photo (le 21 octobre 2026 : `--jpeg`, `--x-t20`, `--portrait`, `--mixte` ; ni flash, ni yeux rouges, ni Portrait d'iPhone, ni vrai horizon : `--horizon` demande d'ajouter aux Essais une copie qui a un horizon net, mer, lac ou plaine ; la dune 53709786 ne convient pas, ses rides de sable faussent la mesure), sur des copies remises à l'origine d'abord (`revert_to_original` : une copie que Claude a déjà retouchée est refusée) ; `--mixte` sur le portrait d'essai, la seule copie à deux lumières (relevé du 20 octobre 2026) ; l'étape du témoin à une seule lumière ne vient que si le RAW de `--recette` est une autre photo ; la sortie dans un fichier, en arrière-plan, jamais tronquée (`\| head` coupe la recette au milieu d'une étape) ; puis l'essai dans la fenêtre Claude (« Publier une version », étape 3) |
| Réglages à plat | `./.build/debug/mcp-developpeur --dump [<id>]` (une clé par ligne, pour `diff` avant et après une opération faite à la main) |
| Recalage mesuré | `./.build/debug/mcp-developpeur --recalage <id>` (écarts du modèle de recalage sur la géométrie actuelle ; deux rendus « Claude · recalage » dans l'Historique) |
| Carré de mise au point | `./.build/debug/mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (ce que la fenêtre Claude lance, avec le connecteur de `cheminConnecteur`, pour l'aperçu de la photo active : `PointAF.marquer` lit le point dans un original Fujifilm en temps borné (`LecteurBoitier`), le passe dans l'image affichée et le dessine sur la vignette : le cadre AF rouge à la taille de Focus-Points avec un point au centre, comme l'onglet Focus (`PreviewImages.marquerFocus`, correctif 1.3.3), sinon le carré vert, rouge si l'appareil a signalé la mise au point manquée ; code 1 sans point) |
| Écran du Mac | `./.build/debug/mcp-developpeur --ecran` (pour le développement seulement depuis le correctif 1.3.6 : l'écran principal et les autres, avec leur profil de couleur classé, d'usine, standard, à l'œil, sonde, personnalisé ou inconnu, une ligne JSON, chemin du profil compris, sans la clé `detail` ni le texte de la boîte du voyant Écran, retirés avec lui ; `{"lu": false}` sans écran ; lu sans Lightroom ni permission ; ni la fenêtre Claude ni Claude ne le lisent plus) |
| Cadres de mise au point (onglet Focus) | `./.build/debug/mcp-developpeur --focus <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (ce que la fenêtre Claude lance pour l'onglet Focus, par `perl` et son alarme de 5 s : `Focus.marquer` lit la mise au point d'un original Fujifilm en temps borné (`LecteurBoitier`), dessine sur la vignette le cadre AF à sa taille en rouge et les visages et éléments du sujet en coins jaunes (`PreviewImages.marquerFocus`), puis écrit une ligne JSON : `lue`, les blocs `image`, `prise_de_vue` et `mise_au_point` en paires titre, valeur en français, `point_af`, `cadres`, `dessinee` ; rien de lu : `{"lue": false, "raison": …}` (`delai`, `introuvable`, `illisible` : `Focus.lire`) et code 1) |
| Lecture du boîtier | `./.build/debug/mcp-developpeur --boitier <original>` (un fichier Fujifilm, RAF ou JPEG, lu sans Lightroom par `LecteurBoitier` : point de mise au point, `intention_boitier` comme `view_photo`, `mise_au_point` comme l'onglet Focus, et `valeurs_lues` sous les noms d'exiftool, pour comparer avec lui (`exiftool -a -G1 -s`, celui de Focus-Points, en lecture seule) ; une ligne JSON, code 1 si rien n'est lu) |
| Analyse du Suivi | `./.build/debug/mcp-developpeur --analyser '<json>'` (ce que le relevé du Suivi lance, depuis `Releve.lua`, par `perl` et son alarme de 60 s, la réponse dans un fichier : 1 à 20 photos `{id, vignette, iso, cache, retouchee, objectif}` (`objectif` depuis le correctif 1.3.8, pour le genre macro), le module en envoie 10 ; chacune mesurée sur sa vignette du cache de Lightroom, déjà redressée, par les mesures et les règles du tri et du carnet (`Suivi.analyser` : netteté et bruit à 1 024 px, la netteté ramenée par `thumbnailSharpnessFactor` si `cache`, exposition et blanc pur du tiers haut à 512 px par `Carnet.constatsVue` sans point de mise au point ni intention, surexposition au-delà de `PhotoTriee.partBlancPurBrulee`, yeux fermés par `PhotoTriee.yeuxFermes` seulement s'il y a des `sujetsAuxYeuxLus`, bruit seulement à ISO `Carnet.isoEleve` ou plus, seuls flou et yeux avec `retouchee`), et depuis le correctif 1.3.8 le genre de la photo (`Genre.classer` : étiquettes de `VNClassifyImageRequest`, visages, personnes, chiens et chats, objectif macro), Vision deux à la fois, sans Lightroom ni original ; une ligne JSON `{ok, regles, regles_genre, photos: [{id, cherches, defauts, genre, mesures}]}` en codes de `PriseDeVue` et de `Genre`, ou par photo `{id, raison, texte}` (`vignette_absente`, `vignette_illisible`, `vignette_petite` sous 900 px, `delai` : 15 s par photo, 50 s pour l'appel, pour que la ligne parte avant l'alarme) ; refus de l'appel `{ok: false, raison, texte}` et code 1 (`arguments`, `trop_de_photos`) ; code 2 pour un nombre d'arguments faux, l'aide sur stderr et rien sur stdout ; forme figée dans `Tests/Contrats/suivi.json`) |
| Graphiques du Suivi | `./.build/debug/mcp-developpeur --graphiques '<json>' <dossier>` (ce que la fenêtre Suivi lance, par `perl` et son alarme de 60 s depuis le correctif 1.3.8, 20 s avant, la réponse dans un fichier : lit seulement `suivi.json` et `carnet.json` aux chemins donnés, aucun par défaut, et la table du catalogue donné ; d'après `debut` (facultatif : depuis la première photo) et `fin`, des jours « AAAA-MM-JJ » que donne le module (rien ne dépend de l'horloge du connecteur ; à la place d'`aujourd_hui` et de `periode`, `3_mois`, `12_mois` ou `tout`, depuis le correctif 1.3.8), `apparence` et ses six couleurs tirées de `Dispositions.PALETTES`, `defaut` (absent : le plus fréquent) et les tailles en points, dessine les neuf PNG en 2x dans le dossier (créé s'il manque ; `SuiviDessin.swift`) et écrit une ligne JSON : période (`debut`, `fin`, `libelle`, `par` : `mois`, `trimestre` ou `annee`, treize colonnes au plus, `depuis_le_debut`), photos, quatre tuiles, les huit défauts comptés, neuf graphiques (les notes de 0 à 5 ★ et les genres de photos depuis le correctif 1.3.8) avec leurs barres (rectangle dessiné, zone cliquable, `ids` croissants des originaux) et leurs créneaux ; refus `{ok: false, raison, texte}` et code 1 (`arguments`, `defaut_inconnu`, `suivi_illisible`, `dossier`, `dessin`), sans PNG laissé ; code 2 comme `--analyser` ; un relevé de 20 000 originaux en 0,3 s environ, une ligne de toute la bibliothèque de 0,7 Mo ; de 250 000 en 2,6 s, 0,7 Go de mémoire, une ligne de 10,6 Mo, que la fenêtre décode en rendant la main (mesuré le 26 octobre 2026 avec le graphique des notes, sur un relevé synthétique de photos de 2010 à 2026, « Du » vide ; le graphique des notes y ajoute une fois de plus les ids de toute la période, environ 15 %) ; forme figée dans `Tests/Contrats/suivi.json`) |
| Relevé du carnet | `./.build/debug/mcp-developpeur --constats <id>… [<fichier.jpg>…]` (pour fixer les seuils du carnet de progrès, en lecture seule : aperçu avec `point_af` à 1 344 px et les clés de la géométrie, jamais `carnet constater` ; par photo, L* médian et 95e centile, blanc pur du tiers haut, netteté et texture (au point de mise au point aussi), bruit, ISO et si le bruit y est cherché (1.3.1 ; l'Exif d'un fichier), boîtier, géométrie, étapes de Claude, défauts cherchés et retenus, puis un résumé ; un JPEG se mesure sans Lightroom, sans point ni intention ; lignes ✘ et code 1 en cas d'échec) |
| Relevé de l'éclairage | `./.build/debug/mcp-developpeur --eclairage <id>… [<fichier.jpg>…] [--essai '{…}']` (pour fixer les seuils de l'éclairage mixte : dominantes des tons neutres par case 3 × 3 et par zone tonale, visages, zone d'intérêt et scène de Vision, aux bornes 12, 15, 20, 25 et 30 de l'écart a*b* au centre des tons neutres, chaque ligne « borne N : … ; point neutre a* x b* y, centre a* x b* y », durée de la mesure, puis un résumé ; lecture seule par la commande `apercu`, sans point AF ni original ouvert ; un fichier JPEG se mesure sans Lightroom ; `--essai` passe par `preview_settings` (deux étapes « Claude · essai »), copies virtuelles seulement) |
| Journal détaillé | `DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ; `DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre port |
| Journaux du module | `~/Library/Logs/Developpeur/module.log` (liaison, avec les commandes refusées faute du bon jeton : une ligne par genre de refus toutes les 10 s au plus, jamais le jeton) et `conversation.log` (fenêtre Claude, Demande rapide, et depuis le correctif 1.3.7 le relevé et la fenêtre Suivi), gardés sous 1 Mo ; échanges avec Claude Code : `~/Library/Application Support/Developpeur/Sessions/` |
| Recharger le module dans Lightroom | Fermer les fenêtres du module (devant, elles réduisent le menu Fichier), Lightroom au premier plan, puis Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du module externe › Charger de nouveau le module ext. Un fichier `.lua` ajouté depuis le lancement ne se charge pas ainsi (« Could not load toolkit script »), ni donc un fichier qui le requiert (`Commandes.lua` requiert `Notation.lua`, nouveau en 1.1, et `Etapes.lua` et `Carnet.lua`, nouveaux en 1.3 ; `Moteur.lua` requiert `Historique.lua`, et `Fenetre.lua` `FenetreSuivi.lua`, nouveaux au correctif 1.3.6 ; `Fenetre.lua`, `FenetreRapide.lua` et `FenetreSuivi.lua` requièrent `Releve.lua`, nouveau au correctif 1.3.7 ; `FenetreSuivi.lua` requiert `Calendrier.lua`, nouveau au correctif 1.3.8), ni un raccourci clavier changé : quitter et relancer Lightroom, après toute version qui ajoute un fichier `.lua` |
| Remesurer les polices | `swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua` (la police du système, `'<system>'` en 13, 12 et 11 et `'<system/bold>'` en 13, 12, 11 et 16, et Menlo 11 : clés `texte`, `texte12`, `petit`, `gras`, `gras12`, `gras11`, `titre`, `mono` ; si une police du fil ou des cartes change dans `Fenetre.lua`, ou pour un caractère nouveau, comme ★ ☆ ⚑ ＋ ⊗ ⤢) |
| Images de la fenêtre | `luajit scripts/gabarits.lua \| swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin` (les deux jeux, `images/` en claire et `images/sombre/`, d'après `Dispositions.IMAGES`, `Dispositions.PALETTES` et l'ordre des segments (`segments` des gabarits, tiré de `Dispositions.ONGLETS`) ; refus avant d'écrire d'une couleur absente ou invalide, d'un dossier invalide, d'aucun segment ou d'un segment en double ; signale les images orphelines) ; l'image « aucun aperçu », au cadre de l'aperçu (`images/vide-498x332.png` et `images/sombre/vide-498x332.png`) : `luajit scripts/gabarits.lua \| swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` ; après tout changement des tailles ou des palettes |
| Désinstaller | `bash uninstall.sh [--tout]` (inscriptions, serveur, module, paramètres prédéfinis invisibles Lightroom fermé, fichiers de travail, dont le jeton de la liaison `liaison.jeton` et `liaison.jeton.nouveau`, que la liaison d'un Lightroom ouvert réécrit dans les 5 s : relancer le script Lightroom fermé ; `--tout` : aussi guide de style, conversations, mes demandes de la fenêtre Claude (`mes-demandes.json`), profils de publication, consommation, notes proposées (`notation.json`), carnet de progrès et leçons d'avant le correctif 1.3.6 (`carnet.json`), relevé du Suivi (`suivi.json`, et `suivi-illisible-*.json`, un relevé illisible mis de côté ; correctif 1.3.7), avant/après des étapes (`Etapes/`) et journaux ; sans `--tout`, ils restent ; jamais le catalogue ni les photos, ni « Fibo non importées » s'il n'est pas vide) |
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
6. Mettre à jour la page Analyse du Développeur, en artefact privé
   (https://claude.ai/artifact/9kQ7kKQk5VuXrrAWFrvVKS, source `docs/lavish/analyse-1-5.html`,
   analyse de la 1.4 du 27 octobre 2026) : la relire (Artifact, `read`), marquer faits les constats
   que la version livre et corriger ce qui est devenu faux, puis la republier à la même adresse.
   Feuille de route, Les 35 outils et Ordinogramme d'une retouche sont supprimées, avec leurs
   sources, à la demande de Dany le 27 octobre 2026, comme Guide des demandes et Apprendre avec
   Claude le même jour. Tout document nouveau pour Dany (guide, compte rendu, plan) se fait en
   page Lavish publiée en artefact (`npx -y lavish-axi <fichier>` pour sa relecture), sa source
   dans `docs/lavish/`, commitée et poussée, jamais un document Claude Docs.

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
  notation. La seule retouche générative permise est Fibo 2, en local, sur demande de Dany (puce
  Retouche générative par Fibo 2) ; les taches de Claude restent `patchmatch`.
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
  (« Développeur v1.4 » : `Fenetre.titreFenetre`, d'après `Composants.module()` ; « Développeur »
  seul si la version ne se lit pas) ; son menu (« Ouvrir la fenêtre Claude », ⌃⌥C, que
  `Raccourcis.lua` vise) et la documentation l'appellent toujours « fenêtre Claude ».
- Le module est du **Lua 5.1** (celui de Lightroom) : pas de `goto`, pas de `//`. Le JSON passe
  toujours par `Json.lua`, qui lit et écrit les nombres sans dépendre de la locale (en français,
  `string.format` écrirait « 0,35 »). Dans une tâche asynchrone, `LrTasks.pcall` et non `pcall`
  dès que le code peut attendre (rendu, accès au catalogue) ou rendre la main (`LrTasks.yield`, par
  `Photos.rendreLaMain`, la seule copie, que `Releve.rendreLaMain` et `Historique` reprennent :
  seulement si `LrTasks.canYield`, jamais dans un comparateur de `table.sort` ni un rappel de
  `gsub`, jamais en parcourant par `pairs` une table qu'une autre tâche agrandit : en prendre les
  clés d'abord ; correctif 1.3.8). Un grand JSON s'écrit morceau par morceau par `Json.ecrivain`
  (accolades, virgules et clés dans `Json.lua` : le relevé du Suivi, correctif 1.3.8). `os.time` et
  `os.date` passent par `Compat.lua` (remplacés par `LrDate` s'ils manquaient).
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
- **`PriseDeVue.defauts` est la seule liste des défauts de la prise de vue** (17 codes depuis le
  correctif 1.3.7, 16 avant ; domaine du carnet, six mesurés ; plus d'axe ni de clé anglaise depuis
  le correctif 1.3.6 ; `yeux_fermes`, nouveau au correctif 1.3.7, domaine netteté, après
  `mise_au_point`, `mesure` faux : le Suivi le compte d'après `--analyser`, le carnet de
  `view_photo` ne le cherche pas ; les dix autres non mesurés gardés pour les leçons d'avant
  rangées dans `carnet.json`) ; `PriseDeVue.vocabulaire` part avec
  chaque constat : aucune liste de défauts dans le module. `ToolHandler.descriptionRaison` (la description de `reason`, répétée dans
  chaque outil qui écrit) fait 160 caractères au plus, comme `descriptionRaisonProposition`, celle
  de `preview_settings` depuis la 1.3.1 (Claude y joignait `reason` 3 fois sur 4 et l'appel était
  refusé ; elle ne promet pas le journal). Une proposition n'écrit rien : sa raison
  ne part jamais au module (ni étape ni journal), elle revient dans la réponse (`raison`), à
  redonner à `apply_settings`. `ToolHandler.raison` la nettoie et la borne (300 caractères).
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
  Claude, le carnet se voit dans la fenêtre Suivi, en graphiques depuis le correctif 1.3.7 (puce La
  fenêtre Suivi) : `--graphiques` lit `carnet.json` en lecture seule, et pour un original de même
  uuid, chaque code que le carnet a cherché (`vue.cherches`, le code de l'angle) l'emporte sur
  l'analyse d'office du Suivi ; une entrée du carnet absente du relevé ne compte pas, un carnet
  illisible fait une remarque.
- **Le Suivi : le relevé et l'analyse d'office** (correctif 1.3.7, décisions de Dany du 25 octobre
  2026 ; contrat figé dans `Tests/Contrats/suivi.json`, lu par `ContratSuiviTests`,
  `essais-releve.lua` et `essais-suivi.lua` : un changement voulu se fait des deux côtés).
  `suivi.json` (`Chemins.racine()`, format 1) n'est tenu que par `Releve.lua` (`Suivi.lua` est la
  fenêtre de la liaison, d'où ce nom), comme `carnet.json` par `Carnet.lua` : une table par
  catalogue (`cat:getPath()`), une entrée par original sous son id en texte (`original`, `uuid`,
  `fichier`, `ajout`, `ajout_le`, `vu`, `vues` : les photos vues de la famille, copies virtuelles
  comprises, `MAX_VUES` 20 ; `prise_de_vue` ; `note`, `drapeau`, `retouchee_par_claude` et
  `classement_le` de la famille ; `analyse`), `MAX_ORIGINAUX` 250 000 par catalogue depuis le
  correctif 1.3.8, 20 000 avant (les moins récemment vus sortent) ; tout lire puis tout écrire, par
  morceaux (relu par `Json.decode` avec un rythme ; écrit entrée par entrée par
  `Fichiers.ecrireParMorceaux`, un provisoire renommé d'un coup) ; illisible ou d'un
  autre format, mis de côté avant la première écriture (`suivi-illisible-<date>.json`, jamais
  écrasé) ; une copie neuve vers une vue ; rien n'est écrit au catalogue ; `uninstall.sh --tout` le
  retire. Qui entre : la sélection que voient `Fenetre.suivreSelection` et
  `FenetreRapide.suivreSelection` (`Releve.voirSelection` : une même clé ne compte qu'une fois,
  `Releve.revoir` à l'ouverture ou au rappel d'une fenêtre la fait compter même inchangée, une autre
  photo active dans le même groupe ne revoit qu'elle, comme une sélection de plus de `SEUIL_REVOIR`
  (2 000) photos revue moins de `REVOIR_APRES` (600 s) après sa vue entière ; `MAX_SELECTION` 250 000
  depuis le correctif 1.3.8, 1 000 avant, le reste dit au journal), par son original (`masterPhoto` d'une copie virtuelle, une seule fois), sauf les vidéos
  et les photos de « Développeur › Essais » (`Carnet.estPhotoDEssai` : elle ou son original ; pour une
  vue d'au moins `SEUIL_ESSAIS` (200) photos, lues d'un coup par `Carnet.photosDesEssais`, les
  collections Essais des ensembles Développeur, sinon photo par photo comme avant). La
  famille (l'original et ses copies hors Essais, `virtualCopies`, par lectures groupées, sinon une à
  une) donne la note la plus haute, le drapeau (« retenue » si l'une l'est, « rejetee » si toutes)
  et « retouchée par Claude » (`proprietaireMemoire`, comme `Photos.decrireTout`), relus à chaque
  vue et par `Releve.reclasser` à l'ouverture de la fenêtre Suivi (après son premier dessin, dans sa
  propre tâche, un seul à la fois). Pas de rattrapage : le Suivi part
  de zéro à l'installation. La file d'analyse, ce sont les entrées sans analyse, ou en erreur non
  abandonnée (elle reprend d'elle-même après une fermeture de Lightroom) ; une seule tâche
  (`Releve.vider`, que `Releve.relancer` lance depuis les boucles de la fenêtre Claude, de la Demande
  rapide et de la fenêtre Suivi) range d'abord les vues (des lectures du catalogue, même pendant que
  Claude travaille ; au-delà de `MAX_EN_ATTENTE` 20 vues en attente, elles se fondent en une, sans
  perdre de photo), puis analyse par lots de `LOT_ANALYSE` 10, la photo active nouvellement vue en
  tête : la vignette de l'original à `TAILLE_VIGNETTE` 1 024 (`Vignettes.demander`, dans
  `Temporaire/Suivi`, effacé après la réponse et au chargement : `Menage.TEMPORAIRES`), redressée
  (`Images.redresser`), puis `perl alarm 60` et `--analyser` (commande Analyse du Suivi), avec
  `retouchee` pour un original que Claude a retouché (seuls flou et yeux fermés s'y cherchent) et,
  depuis le correctif 1.3.8, l'objectif de la prise de vue (le genre macro).
  L'analyse attend pendant que Claude travaille (`Moteur.travaille`) ou que la liaison sert
  (`Lightroom.liaisonOccupee` : Claude Desktop, Claude Code en terminal, la recette ; une commande
  en cours ou finie depuis moins de 5 s : un trou plus long entre deux commandes de la recette
  laisserait partir un lot) ; un lot commencé juste avant est remis sans compter d'essai. Une
  analyse n'est jamais refaite après une édition (les défauts disent la prise de vue ; une retouche
  les cacherait), seulement pour des `regles` plus récentes ; le genre (correctif 1.3.8, demandé par
  Dany le 26 octobre 2026 : `analyse.genre`, un code de `Genre`, et `analyse.regles_genre`) a ses
  propres règles : une analyse sans genre, ou d'un genre de règles plus anciennes, se refait pour le
  genre seul, ses défauts, son `le` et son `regles` gardés ; sans genre, même avant toute réponse de
  la séance (les règles ne s'apprennent que d'une réponse, et toute la bibliothèque de Dany était déjà
  analysée), sauf si le connecteur répond sans `regles_genre` (`Releve.sansGenre`, pour la séance) ;
  un genre refait qui échoue garde l'analyse d'avant (`Releve.sansRefaire`) ; une erreur (une raison de
  `--analyser`, `pas_de_reponse`, `photo_introuvable`, `module`) compte un essai, réessayé
  `DELAI_REESSAI` (600 s) plus tard (devant la file gardée, `Releve.reessais`), l'entrée abandonnée
  au `ESSAIS_ANALYSE`-ième (3). Les écritures du fichier, vues et analyses comprises, sont espacées de
  `Releve.delaiEcriture` : au moins `DELAI_ECRITURE` (20 s : une écriture par photo parcourue aux
  flèches figeait Lightroom), `FACTEUR_ECRITURE` (10) fois la durée propre de la dernière (la somme
  de ses morceaux, sans le temps des autres tâches quand elle rend la main) et `SECONDES_PAR_MO` (1)
  par Mo du fichier (écrit ou relu ; chaque écriture l'écrit en entier : 85 000 originaux, 57 Mo,
  environ toutes les 57 s), au plus `DELAI_ECRITURE_MAX` (60 s : ce qui n'est pas écrit se perd si
  Lightroom quitte, `Arret.lua` ne s'exécutant pas ; les analyses se refont, une vue d'une photo
  nouvelle non), pendant une pause comme hors d'elle (plus d'écriture forcée au début de chaque
  pause depuis le correctif 1.3.8 : une liaison qui sert par moments réécrivait tout le relevé toutes
  les 7 s), sauf avant un dessin demandé de la fenêtre Suivi (`Releve.ecrire`, qui attend d'abord une
  écriture en cours) ; en fin de file, la tâche attend son tour en rangeant les vues qui arrivent. Toute la bibliothèque (correctif 1.3.8) : aucun morceau de calcul
  de plus de quelques centièmes de seconde sans rendre la main (`Releve.rendreLaMain` :
  `LrTasks.yield` seulement si `LrTasks.canYield`, sous `LrTasks.pcall`, qui ne laisse passer aucune
  erreur ; jamais sous un `pcall` simple, que Lua 5.1 refuse : la relecture et l'écriture passent par
  `LrTasks.pcall`, et `essais-releve.lua` compte les yields à travers un `pcall` simple), toutes les
  `PAS` (2 000) entrées des boucles, `PAS_UNE_A_UNE` (200) lectures une à une du catalogue,
  `LOT_LECTURE` (500) photos des lectures groupées, `PAS_ECRITURE` (500) entrées écrites et
  `PAS_JSON` (10 000) valeurs relues. Une seule relecture à la fois (les autres tâches l'attendent :
  deux registres, et ce qui change dans le premier se perdrait), une seule écriture à la fois (une
  autre l'attend, `Releve.ecrire` compris ; hors d'une tâche, laissée à la suivante), `aEcrire` remis
  à faux dès le début de l'écriture (ce qui se range pendant s'écrit à la suivante), abandonnée si le
  Suivi s'éteint (le fichier d'avant tel quel, aucun provisoire), l'enveloppe JSON par
  `Json.ecrivain` ; le texte JSON de chaque entrée est gardé (`jsonDe`, clés faibles) jusqu'à ce
  qu'elle change (`changee`, que doit appeler tout ce qui change une entrée : `rangerVue`,
  `poserClassement`, `manquee`, l'analyse réussie) : une écriture pendant l'analyse ne refait que les
  entrées changées. `poserClassement` ne change une entrée que si sa note, son drapeau ou
  « retouchée par Claude » changent (`classement_le` : l'heure de ce changement, ou de leur première
  lecture) : `Releve.reclasser` sans rien de changé n'écrit rien, et rend le nombre d'entrées
  changées ; une entrée qu'une vue range pendant qu'il tourne (`Releve.revues`) garde le classement
  de la vue. La file d'analyse se garde d'une vue à l'autre : les originaux d'une vue rangée, et un
  lot remis, passent devant (`mettreDevant`), une analyse manquée aussi, à son heure
  (`Releve.reessais`, `MAX_REESSAIS` 1 000 ; au-delà, elle attend que la file se refasse) ; elle ne se
  refait entière qu'épuisée, ou quand une réponse apporte des règles plus récentes (la première de la
  séance comprise : `Releve.file` remis à nil), par `construireFile` (`Releve.refaireFile` pour les
  essais), par paquets de même heure de vue triés en nombres (`trierParVu` : le rang dans la
  sélection puis l'identifiant, jamais un tri de textes, que Lua 5.1 compare par `strcoll`, ni un
  comparateur Lua sur toute la liste) ; `elaguer` ne trie qu'au-delà de la borne, d'après l'heure de
  vue de chaque entrée lue d'abord (une entrée revue pendant le tri reste). Une sélection que la
  fenêtre Suivi pose (`FenetreSuivi.montrerPhotos`, par `Releve.poserSelection`) ne se range pas :
  pendant la pose, aucune sélection vue ne compte, puis elle est notée vue (`cleVue`, `groupeVu`) ;
  ses photos sont déjà au relevé. Mémoire (correctif 1.3.8, mesurée sous `luajit -joff` par la revue,
  Lua 5.1 d'après un modèle) : le registre et `jsonDe` tiennent environ 0,2 Go à 85 000 originaux et
  0,6 Go à 250 000 dans Lightroom, pendant toute la séance, à peu près le double un moment à la
  relecture (le texte, l'arbre décodé et le registre ensemble) et à la première écriture. Le
  Suivi ne tourne que dans Lightroom : `Releve.allume` est faux par défaut, `Init.lua` l'allume
  (`Releve.allumer`), `Arret.lua` l'éteint (`Releve.eteindre` : `arrete`, plus aucune vue, aucune
  tâche, ni connecteur lancé ni écriture après l'attente en cours ; après un rechargement,
  l'ancienne instance ne réécrit jamais le relevé que tient la nouvelle, au prix des vues d'un
  `Releve.delaiEcriture` au plus, 60 s) ; les essais d'Init des deux suites l'éteignent ensuite (`tests.lua`,
  `essais-une-photo.lua`). Côté connecteur, `Suivi.codes` (les huit comptés, dans l'ordre de
  `PriseDeVue` : `codesAnalyse`, les six de `--analyser`, et `codesCarnet`, `horizon_penche` et
  `mise_au_point`, que seul Claude mesure) ; aucune liste de défauts dans le module ; l'analyse
  reprend les seuils du tri et du carnet sans en ajouter. `Genre.swift` (correctif 1.3.8) est la
  seule liste des genres et de leurs règles (onze codes, de `sport` à `autre` ; `Genre.classer`, pure :
  la première règle qui convient, sport, fêtes et événements, famille et groupes, portrait, macro,
  animaux, nourriture, véhicules, ville et architecture, paysage, autre ; les visages à l'envers
  écartés, `Genre.visages` par `Composition.visagePlausible` ; la fleur jugée sans « plant » ni
  « foliage », que Vision donne avec toute fleur, `Genre.sceneAutourDUneFleur` ; chaque étiquette
  connue de Vision, `GenreTests` ; seuils provisoires relevés le
  26 octobre 2026 sur les vignettes de 60 photos de Dany, 52 sur 53 rangées comme à l'œil ; ni
  nourriture, ni macro, ni fête, ni nuit dans ce relevé) ; aucune liste de genres dans le module. Rien du Suivi ne part chez Claude : aucun
  outil ne lit `suivi.json`. Reste à constater dans Lightroom : `batchGetRawMetadata` avec
  `masterPhoto` et `virtualCopies` (sinon une à une), `focalLength` en nombre (un texte « 23 mm » se
  lit aussi), une vignette de 1 024 rendue pour l'analyse.
- **Mise au point jugée sur de la texture** (`Detail.autour`, relevé le 21 octobre 2026 sur les
  copies d'Essais) : sous `DetailMeasurements.textureMin` (18 : sable lisse, ciel uni), la mise au
  point est « non jugée » (pas de plafond, pas de constat au carnet sauf si l'appareil l'a
  signalée) ; jusqu'à `textureDouteuse` (30 : le bord d'un nuage), une mise au point manquée n'est
  qu'un doute : 1 (2 avant l'échelle resserrée de la 1.4), à vérifier, sans rejet proposé (`Notation.plafond`), et le carnet ne la compte
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
- **Retouche générative par Fibo 2** (`generative_edit`, le 36e outil, titre « Retouche générative
  (Fibo 2) », demandé par Dany le 29 octobre 2026 : « si tu ne peux pas le faire dans Lightroom
  (remplacer un pantalon par une jupe), exporte, fais faire par Fibo 2, importe et fais le reste par
  le MCP ») : le seul chemin génératif du projet, **seulement sur demande de Dany, jamais
  d'initiative** (description de l'outil, `ServerInfo.instructions` : « Changer un objet, un
  vêtement : generative_edit, sur sa demande. », et une puce des garde-fous de `Consignes.texte`).
  Fibo 2 tourne sur ce Mac par mflux (`~/.local/bin/mflux-generate-fibo2-edit`, mflux 0.24 ;
  modèles `briaai/Fibo-2.0-dev` et `briaai/Fibo-2.0-edit-turbo`, licence CC BY-NC) ; rien ne part
  sur Internet sauf le premier téléchargement du modèle. Déroulé (`Tools+Generatif.swift`) :
  exécutable vérifié d'abord (sinon refus, « uv tool install mflux », rien d'envoyé), commande `etat`
  (pause, « Proposer d'abord » sans `confirm` : refus avant tout calcul) ; la commande `exporter`
  existante (TIFF, `AdobeRGB`, 16 bits, `metadonnees = 'all'`, `sans_lieu = false`, taille réelle,
  sans filigrane ni réimportation, avec `etape` « Claude · Fibo 2 » et `raison`, la consigne) vers un
  dossier neuf `<racine>/Temporaire/Fibo/<uuid>/`, effacé à la fin (`defer`, et à l'arrêt du serveur
  par `ToolHandler.travailFibo`). Une exportation vers `Temporaire/Fibo` n'est pas une livraison
  (`Livraison.exporter`) : son accord se demande au nom de `generative_edit`, avec l'étape et la
  consigne (jamais `export_photos` : Claude aurait rappelé une vraie livraison) ; les garde-fous des
  photos (`verifierProtection` : copies virtuelles seulement, libellé protégé, rejetées) s'y
  appliquent avant tout calcul ; une photo jamais exportée y est notée `apercuSeulement`, comme après
  un aperçu (`Photos.exportee` reste faux), et le champ n'est jamais effacé ; un PNG sRGB 8 bits d'environ 1 Mpx (`Generatif.tailleCible` : même
  proportion, côtés multiples de 16) et, avec `region`, un masque PNG blanc sur noir élargi de
  `margeRegion` (3 % du petit côté) ; mflux par `Process`, sans shell, arguments en tableau, stdin
  vide, sortie dans un tuyau (stdout du serveur au protocole), progression tqdm (« 12/50 [ ») vers
  `avancer` (client et barre de Lightroom), annulation par `contexte.verifier()` et délai de
  `Generatif.delaiMax` (900 s) : SIGTERM puis SIGKILL après 3 s ; mflux en cours et dossier de l'appel
  tenus par `TravailFibo` (`ToolHandler.travailFibo`), que `serve()` arrête à la fin de l'entrée
  (Lightroom quitté, module rechargé, Claude Desktop fermé : mflux tient plusieurs Go) ; erreurs
  expliquées (`Generatif.expliquer` : accès refusé reconnu à « 401 Client Error », « 403 Client
  Error », « Unauthorized », « Forbidden », jamais à « 401 » seul, qu'écrit une barre de
  téléchargement ; modèle incomplet, réseau, sinon le code et les trois dernières lignes) ; qualité `normal` (`--steps 50`) ou `fast` (Turbo, 4 étapes, la copie locale
  du cache HF par `--model <instantané> --base-model fibo2-edit-turbo`) ; graine toujours passée (au
  hasard sans `seed`, rendue). Recomposition (`Generatif.swift`, pur, testé) : la zone changée est
  l'écart entrée-sortie à la petite taille, lissé en 3 × 3 (5 × 5 effaçait un trait d'un pixel), au-delà
  de `seuilEcart` (0,10, provisoire), points isolés retirés (majorité en 5 × 5), élargie
  (`elargissement` 2 %) et fondue, coupée par `region` ; sous `partMinimale` (0,05 %), refus, rien
  d'importé. La zone de mélange (`Generatif.zoneDeMelange`) : avec `region`, toute la zone donnée
  (élargie, fondue), Fibo n'ayant travaillé que là ; sans elle, la zone changée, ou toute la sortie
  au-delà de `partSortieEntiere` (60 % de l'image), ce que la réponse dit (`remarqueSortieEntiere`, en
  part de l'image) ; hors de la zone, les pixels du TIFF exporté restent identiques au bit près. TIFF
  final 16 bits Deflate (`compressionTIFF` 8, comme Lightroom ; le LZW grossissait de 30 %) avec le
  paquet XMP entier du TIFF exporté (`lireMetadonnees`, `CGImageDestinationAddImageAndMetadata` :
  libellé, texte alternatif, mots-clés hiérarchiques gardés ; la compression au premier niveau des
  options, constaté) et ses dictionnaires Exif, IPTC, GPS et TIFF, nommé `<base>-Fibo` (jamais
  doublé). Puis la commande `importerGeneree` du module
  (`Livraison.lua`), contrat identique des deux côtés : paramètres `{ photo, chemin, nom, consigne,
  confirme }` (la `reason` jointe à `consigne` après « — ») ; refus en pause, en « Proposer
  d'abord » sans `confirme`, et d'un chemin hors de `<racine>/Temporaire/Fibo` (`Livraison.dansFibo` :
  ni « . », ni « .. », ni segment vide), qui n'est pas un `.tif`/`.tiff` ou qui manque, et d'une photo
  protégée (`verifierProtection`, comme à l'exportation) ; destination le dossier de l'original
  (`masterPhoto` d'une copie virtuelle ; refus de l'original introuvable), `<nom>.tif` puis `-2`,
  `-3`… (jamais d'écrasement) ; `LrFileUtils.copy`, puis `catalog:addPhoto(chemin, original, 'above')`
  dans `Ecriture.ecrire` (« Claude · Fibo 2 ») ; une photo d'essai (elle ou son original dans
  « Développeur › Essais ») n'est pas empilée avec le vrai original (`addPhoto(chemin)`), elle va dans
  les mêmes collections Essais, dans une écriture suivante (le Suivi et le carnet la voient comme une
  photo d'essai) ; tout chemin importé se note pour `retirerReimportees` (la recette la retire) ; un
  refus de Lightroom met la copie à la Corbeille ; la photo ajoutée se cherche par `findPhotoByPath`
  si `addPhoto` ne la rend pas ; journal de Claude de la nouvelle photo (« Claude · Fibo 2 :
  <consigne> », `retoucheeParClaude`) par `Ecriture.ecrireMemoire`, sans étape : `undo_last` ne la
  retire pas (Photo › Retirer du catalogue, à la main) ; photo active par
  `Bibliotheque.selectionnerAvecSource` ; sous « Copies virtuelles seulement », une copie virtuelle
  « Claude » de la nouvelle photo, qui devient la photo active (les finitions se font sur elle) ;
  fichier temporaire effacé. Réponse `{ id, fichier, chemin, empilee, active }`, plus `essai` pour une
  photo d'essai (`empilee` faux) et, sous « Copies virtuelles seulement », `copie_virtuelle` (`id` est
  alors celui de la copie) et `photo_fibo` ; le connecteur les reprend dans `nouvelle_photo` et dit
  où se font les finitions (`ToolHandler.aSavoir`). Sans accord récent de l'exportation, l'accord
  d'`importerGeneree` se demande avec l'étape « Claude · Fibo 2 » et la consigne. L'accord dans Lightroom de l'exportation vers `Fibo` vaut une fois pour
  l'importation de la même photo dans les 3 h (`Livraison.exportsFibo`, `DUREE_GENEREE` : 4
  modifications, Fibo 2 puis SeedVR2, 15 min au plus chacun) : Dany n'est pas sollicité deux fois. `importerGeneree` n'est pas une lecture (absente de
  `LightroomBridge.lectures`) : rejouée une seule fois, et seulement si elle n'a pas été livrée
  (`.unreachable`, puce Mémoire ci-dessous). `Menage.TEMPORAIRES` comprend `Fibo`. L'exécutable,
  le cache HF, la racine et le délai sont injectables (`ToolHandler.fibo`, struct `Fibo`, **nil par
  défaut** comme `lireEcran` : generative_edit refuse alors sans rien lancer ; seul `outils()` de
  main.swift pose `Fibo()`, pour `serve()` et `--call`) : les tests passent un faux script shell qui
  écrit un PNG, jamais le vrai mflux (`GeneratifTests`,
  `essais-generatif.lua`, avec `catalog:addPhoto` dans la simulation de la liaison : refusé hors
  d'une écriture, fichier exigé, position `'above'` ou `'below'`, photo illisible dans l'écriture
  qui l'a créée, supposé). Reste à constater dans Lightroom : `addPhoto` empilé au-dessus de
  l'original et sa place dans la pile (repliée ou non), la photo ajoutée relue juste après
  l'écriture, un chemin déjà au catalogue refusé, `LrFileUtils.copy` sur `/Volumes/Photos`, la
  sélection de la nouvelle photo quand la source est une collection (Essais), `addPhoto` sans pile et
  la copie virtuelle de la photo importée ; côté mflux, le
  masque PNG en RVB lu par `--mask-path`, le seuil de la zone changée sur de vraies sorties, la
  durée réelle (normal et rapide) et la mémoire (environ 0,7 Go au connecteur pour 40 Mpx, estimé).
  Ajouts du même jour (demandés par Dany) : avec `region`, Fibo reçoit un **recadrage** autour de la
  zone (`Generatif.recadrage` : la zone agrandie de `margeContexte`, 50 % de sa taille de chaque côté,
  et d'au moins `contexteMin`, 35 % du petit côté, coupée aux bords sans être déplacée (garde plus
  souvent la taille native), jamais plus allongée que 8:1 (`rapportMax` : le petit côté grandit
  dans la photo, au lieu d'une entrée déformée) ; au-delà de 1 Mpx `tailleCible`, chaque côté borné
  au natif, sinon la taille native ramenée aux multiples de 16 par `ajuster16` (resserrée hors de
  la zone et de son fondu, sinon agrandie dans la photo, sinon gardée entière avec une entrée au
  multiple inférieur : jamais une bande de la zone coupée au bord), jamais plus grand), masque et zone de mélange
  dans son repère (`regionDansRecadrage`), recollé à sa place (`Generatif.recomposer` par `Piece`,
  l'une après l'autre ; sans zone, toute la photo, comme avant) ; **`edits`** (1 à 4 modifications
  `{label, instruction, instruction_fr, region}`, `Generatif.modifications` : jamais avec les
  arguments simples, une zone chacune dès deux, une `region` qui n'est pas un objet refusée, refus
  d'un chevauchement avant tout envoi, `chevauchement`, puis, après l'exportation, de deux zones
  dont les bords fondus se recouvriraient, `zonesTropProches` et `etendueMelange` : la seconde pièce
  effacerait le bord de la première), un
  passage de Fibo par modification depuis le même TIFF, une seule importation ; `instruction_fr`
  exigée, la consigne du module en français (`consigneJournal`) ; `context` = `full_and_crop`
  (`contexte.png` puis le recadrage dans `--image-paths`, consigne `consigneDeuxImages`, sans
  `--mask-path`, avec une zone seulement ; une sortie dont le pourtour de la zone a changé de plus de
  `partPourtourMax`, 30 %, ne s'aligne pas : rien n'en est repris, `partDuPourtourChangee`) ;
  **toujours `--low-ram`** (normal et rapide), `--vae-full-precision` en qualité normale, jamais
  `--quantize` (ni `-q`) ni `--step-cache-ratio` ; **SeedVR2** (`Fibo.seedVR`, par défaut à côté de mflux :
  `mflux-upscale-seedvr2 --model seedvr2-7b --resolution <côté court natif> --low-ram`, qui
  implique `--vae-tiling`) quand la
  sortie doit être agrandie de plus de `seuilSeedVR` (1,25) sur ses deux côtés et `upscale` vrai,
  avec une zone seulement, × `facteurMaxSeedVR` (4) et `pixelsMaxSeedVR` (16 Mpx) au plus
  (`Generatif.seedVR`, provisoires), sinon, absent ou en échec, mise à la taille ordinaire dite
  (`remarque_seedvr2`) ; une seule barre de 0 à 100 % (`Generatif.Avancement` : poids 3, 10, 70,
  15, 5 ; `tempsRestant` rien avant deux étapes, `texteProgression`, `BarreFibo`, qui ne recule
  jamais, renvoie la commande progression toutes les `relecture` (3) s même sans changement pour
  lire la croix, la relit avant `importerGeneree` et finit à 100 % ; les barres de chargement et de
  téléchargement ne comptent pas, `estUnChargement`), processus par `ToolHandler.executer`
  (`FinProcessus`, un seul lecteur de la sortie) ; un signal qui termine le serveur arrête mflux
  (`TravailFibo.arreterAuxSignaux`, posé par `serve()`).
  **Mémoire** (constaté le 29 octobre 2026, essai réel) : sans `--low-ram`, Fibo 2 a pris environ
  39 Go sur les 48 du Mac Studio ; Lightroom ouvert ne répondait plus (chaque commande progression
  refusée pendant 13 min, puis `importerGeneree` « Lightroom ne répond pas »), le TIFF final a été
  effacé avec le dossier temporaire, puis le Mac a gelé (une nuit plus tôt, deux mflux à 36 Go
  chacun : JetsamEvent). Mesures, Lightroom fermé (1 248 × 832, 6 étapes, `/usr/bin/time -l`,
  « peak memory footprint ») : défaut 39,0 Go (58 s) ; `--vae-full-precision` 39,2 Go ; `--low-ram`
  20,6 Go (54 s), image identique au pixel près ; `--low-ram --vae-full-precision` 20,6 Go,
  identique à `--vae-full-precision` seul ; `-q 8` 38,0 Go et moins fidèle (écart moyen 1,2, max
  146). **Un seul calcul à la fois** sur ce Mac, quel que soit le serveur (Claude Desktop, la
  fenêtre Claude, Claude Code en terminal : chacun sa `FileOutils`) : `flock` sur
  `<racine>/Temporaire/fibo-en-cours.verrou` (hors de `Temporaire/Fibo`, que le ménage efface ; le
  noyau le rend à la mort du processus), pris avant la garde et tenu tout l'appel
  (`Fibo.prendreVerrou`), sinon refus avant tout envoi (« Un autre calcul de Fibo 2 est en
  cours… ») : la garde seule ne voit pas un mflux qui charge encore son modèle ; puis un mflux lancé hors du serveur (Fibo 2 Studio, le Terminal), que le verrou ne voit pas : `Fibo.autreCalcul` (`pgrep -f "mflux-(generate|upscale)"`, injectable, jamais le vrai dans les tests), refus « Fibo 2 calcule déjà sur ce Mac… » avant la mémoire et tout envoi (constaté le 29 octobre 2026 : un calcul de Fibo 2 Studio en même temps que l'essai a fait geler le Mac). **Garde** avant
  chaque lancement : mémoire disponible (`Generatif.memoireDisponible`, `host_statistics64` :
  `free_count`, qui comprend déjà les spéculatives, plus `inactive_count`, fois la taille de page ;
  ni les spéculatives deux fois ni les purgeables, déjà dans les files active et inactive, relecture
  du 29 octobre 2026 ; calcul pur testé, port de `mach_host_self` rendu ; injectable,
  `Fibo.memoireLibre`, que les tests fabriquent) au moins `Generatif.memoireMinimale` (24 Go,
  provisoire) pour Fibo, sinon refus avant tout envoi au module (« Mémoire libre insuffisante pour
  Fibo 2 : X Go libres, 24 Go nécessaires… »), et plus tard dans l'appel la modification n'est pas
  lancée (`remarque_memoire`, refus si aucune n'est reprise) ; `memoireMinimaleSeedVR` (16 Go,
  provisoire) pour SeedVR2, sinon mise à la taille ordinaire dite ; une mesure illisible ne refuse
  rien, mais se dit (`remarque_garde_memoire`, `Generatif.memoireNonLue`, et une ligne sur stderr) ;
  `memoire_libre_go` et `memoire_minimale_go` dans la réponse. **Résultat gardé** :
  `importerGeneree` réessayé une fois après `Fibo.delaiReessaiImport` (5 s), seulement s'il n'a pas
  été livré (`nonLivree` : `.unreachable`, connexion refusée ou ping sans réponse) ; jamais sur
  `.timeout` ni `.interrupted` (la commande est partie : la rejouer importerait deux fois), ni sur
  un refus du module ; en échec (ou sans `id`), le TIFF final est déplacé vers `<racine>/Fibo non
  importées/<nom>.tif` (`-2`…, `garderNonImportee` par `renamex_np` et `RENAME_EXCL` : un nom pris
  entre-temps fait passer au rang suivant), hors de `Temporaire`, et l'erreur dit son chemin et
  « Fichier › Importer » à la main ; une commande partie sans réponse (`peutEtreExecutee`) ajoute
  que la photo est peut-être déjà dans la pile de l'original, à vérifier avant d'importer, et si le
  TIFF temporaire a disparu, qu'elle a sans doute été importée (jamais « rien n'a été importé ») ;
  un déplacement impossible laisse le TIFF seul dans le dossier de l'appel (le reste effacé), avec
  son chemin et l'avis que le prochain chargement du module le videra ; `uninstall.sh --tout` garde
  « Fibo non importées » s'il n'est pas vide. `BarreFibo` compte les
  progressions sans réponse de suite (`ToolHandler.avancer` rend vrai, faux ou nil) : dès
  `echecsSignales` (3), `remarque_lightroom` (« Lightroom ne répondait plus pendant le calcul :
  mémoire ? »), sans arrêt ; la même phrase suit toute erreur levée après le premier envoi de la
  barre (mflux en erreur, hors délai, sortie illisible, mémoire au lancement, importation), et
  un mflux arrêté par un signal (`FinProcessus.echec` avec `signal`) le dit (« le système l'a sans
  doute tué faute de mémoire »).
  Restent à constater : `--image-paths` à deux images dans mflux 0.24, la durée et la mémoire de
  SeedVR2 7B avec `--low-ram` (pour fixer son seuil), et ses bornes.
  Voir `docs/SPEC.md`, Retouche générative par Fibo 2.
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
- **Harmoniser par lumière** (1.4, `GroupesLumiere.swift`, `Tools+Lumiere.swift`) : `match_series`
  avec `groups` (sans `reference_id`, refusé avec lui) mesure les vignettes de toute la sortie comme
  `cull_photos` (`ToolHandler.mesurer`, `maxPhotosSortie` 2 000), sans ouvrir aucun original (la
  description perd `geometrie` avant la mesure : pas de point de mise au point), puis
  `GroupesLumiere.former`, pure : dans l'ordre de prise de vue (les photos sans date après, dans
  l'ordre donné, `sansDate`), une photo commence un groupe quand le flash change (deux connus), quand
  la lumière de la scène (`Prise.lumiere`, IL à 100 ISO : log2(N²/t) − log2(ISO/100) + compensation ;
  pas pour une photo au flash, ni contre une photo au flash) s'écarte de `ecartIL` (2,5) ou plus de la
  médiane des `fenetreLumiere` (5) dernières du groupe (un coucher de soleil qui baisse peu à peu
  reste un groupe), ou après une pause de plus de `pauseMax` (10 min), sauf même lieu (empreinte de
  Vision à moins de `distanceMemeLieu`, 0,7, de l'une des `fenetreLieu`, 3, dernières) dans
  `pauseMemeLieu` (1 h) ; deux boîtiers restent ensemble ; seuils provisoires, à relever sur la sortie
  de l'essai. La référence proposée (`GroupesLumiere.reference`) : sans défaut mesuré si possible,
  une photo déjà retouchée par Claude (`retouchee_par_claude` de la description), sinon la mieux
  classée au tri (`PhotoTriee.score`) parmi celles qui ont un visage plausible d'au moins
  `Teint.visageMin`, sinon parmi toutes ; un groupe de plus de `maxMatchedPhotos` (60) dit ses lots ;
  une photo seule sous sa lumière va dans `photos_seules`. Rien n'est écrit : le plan seulement
  (`planDesGroupes`). La prise de vue vient de la description des vignettes : `prise_de_vue` du
  module (1.4 : `aperture`, `shutterSpeed`, `exposureBias` et `flash` de `getRawMetadata`, un
  booléen ou rien), `sensibilite` et la date ; `view_photo` retire `prise_de_vue` avant Claude.
- **Le témoin du teint** (1.4, `Teint.swift`) : dans `match_series` avec `reference_id`, la peau du
  plus grand visage plausible (`VNDetectFaceRectanglesRequest`, `Composition.visagePlausible`, au
  moins `visageMin` de largeur) se lit au milieu du visage (`Teint.interieur`, comme l'éclairage)
  dans l'aperçu de mesure pris à pleine résolution (le zoom du visage, sans autre rendu), aux bornes
  de peau de l'éclairage (`Eclairage.peauLumineux`, `peauChroma`), `pixelsMin` (60) au moins ;
  seulement si la référence en a une (sinon aucune autre Vision). Un témoin, jamais la correction
  (deux personnes n'ont pas la même peau) : `teint` par photo (écart a*b* et teinte avant et après),
  et `a_verifier` quand l'harmonisation l'éloigne (`Teint.alerte` : après ≥ `ecartVisible`, 5, et
  hausse ≥ `hausseAlerte`, 2), à regarder par `view_photo` avec `region` sur le visage ; sans tons
  neutres (balance gardée), une remarque si la peau diffère de `ecartVisible`. Seuils provisoires ;
  Vision ne trouve aucun visage dans les images des tests : la lecture d'un vrai visage reste à
  constater.
- **Le tri d'une sortie entière** (1.4) : `cull_photos` prend `maxCulledPhotos` (1 000) photos par
  appel (`maxCulledDetails`, 500, avec `details` ; la réponse d'un tri de 2 000 photos toutes floues
  pèserait 0,9 Mo, texte et forme structurée), et, avec `offset` (sélection, collection, dossier), la tranche suivante ; une sélection plus
  longue n'est plus refusée (`parTranches` de `seriesPhotosSansVideos`), `photos_non_triees` dit
  l'`offset` suivant ; une rafale à cheval sur deux tranches s'y coupe. La commande `selection` du
  module prend `decalage` et le redit dans sa réponse (un module d'avant décrit le début : le
  connecteur la redemande une fois assez loin, `decalage` plus la tranche, et saute lui-même les
  premières) ; `chercher` décrit jusqu'à 2 000 photos (`MAX_RESULTATS` de `Bibliotheque.lua`, 500
  avant ; `find_photos` s'arrête toujours à `maxSearchLimit`, 500). Les groupes de lumière comparent le
  flash à la dernière photo du groupe qui le dit (deux boîtiers mêlés, l'un sans flash lu), et une
  photo seule dit ce qui la sépare avant et après elle (trouvailles de la relecture du 26 octobre
  2026 ; une vignette trop petite y est rendue comme un aperçu, comme au tri).
- **Noter une grande sélection** (1.4, constaté le soir du 26 octobre 2026 : « note la série » sur
  951 photos, par la Demande rapide, n'en notait que 24) : Claude Code range une réponse d'outil de
  plus de 25 000 jetons (son défaut) dans un fichier, et Claude ne peut rien lire dans la fenêtre
  (`--tools ""`) ; le tri de 951 photos faisait 147 000 caractères, dont 80 % de `plafonds`, une
  ligne par photo, et `list_selection` à 500, 168 000. `relais.sh` pose donc
  `MAX_MCP_OUTPUT_TOKENS=100000` (essai de bout en bout de `tests.lua`, par `faux-claude.sh`) ; au-delà
  de `Tri.plafondsParPhotoMax` (100) photos, le tri dit `plafonds_par_motif` à la place de `plafonds`
  (les photos de chaque plafond regroupées par `Notation.Plafond.motif`, la raison sans les mesures de
  chaque photo ; 43 000 caractères estimés pour ces 951 photos, 27 motifs), le plafond de chaque
  photo restant gardé pour `propose_ratings` (`dernierTri`) ; `contact_sheet` prend une sélection plus
  longue que sa planche dès l'offset 0 (`parTranches` ; refusée jusque-là, alors qu'un offset de 30
  passait), et sa suite compte les vidéos écartées (`decalage` + photos + vidéos : sans elles, des
  photos revenaient d'une planche à l'autre), une tranche faite de vidéos seulement donnant la suite au
  lieu d'une erreur ; sa réponse dit `planche` (`premiere`, `derniere` : positions dans la série,
  vidéos comprises ; `sur`), sauf pour `photo_ids` ; les consignes de la fenêtre (puce Notes, `Consignes.rapide`, `Consignes.noterRapide`)
  disent de noter plus de 30 photos planche par planche (`contact_sheet` avec `selection` et `offset`,
  puis `propose_ratings`), jusqu'à la dernière dans le même tour (la planche suffit pour confirmer les
  rejets du tri), sans `list_selection` pour les parcourir ; `Consignes.rapide` ne dit plus « sans
  suite » (Claude, Haiku à l'effort bas, renonçait alors à noter les 951 photos après le tri, reçu
  en entier : « je ne peux pas le faire fidèlement dans cette demande sans suite »), mais de faire la
  demande en entier dans le tour, même longue. Essais :
  `GroupesLumiereTests` (plafonds par motif, première planche d'une grande sélection, vidéos sautées).
  Trouvailles d'une relecture adverse du même soir (vidéos, planche de vidéos, ligne d'état), corrigées.
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
  lecture reprend. Claude ne répond jamais à une demande d'autorisation de macOS. Le Suivi
  (correctif 1.3.7) n'ouvre jamais d'original : `--analyser` ne lit que les vignettes du cache de
  Lightroom que le module lui donne, `--graphiques` que `suivi.json` et `carnet.json`.
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
  reprennent sans en ajouter, comme l'analyse d'office du Suivi (`Suivi.analyser`, correctif 1.3.7 :
  la photo « brûlée » du tri au-delà de `PhotoTriee.partBlancPurBrulee`, 35 %, y fait la
  surexposition, et les yeux fermés ne s'y cherchent que s'il y a des `sujetsAuxYeuxLus`, les
  sujets de `yeuxFermes` et de `yeuxOuverts`) ; `analyze_photos`, l'éclairage et le bilan les reprennent aussi, avec
  leurs propres seuils (puces suivantes). Au tri, une pile de Lightroom compte comme une rafale
  (seule sa meilleure vue échappe au plafond de 2 ★, 3 ★ avant l'échelle resserrée de la 1.4). Le tri (`cull_photos`) mesure les vignettes
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
  principal du Mac. » ; `--status` dit les noms seuls.
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
  correctif 1.3.4 : sinon 1, à vérifier, la seule vue de son moment ne se jetant pas pour un
  clignement, et le tri d'une seule photo, la note d'abord de la fenêtre, n'en rejette jamais ;
  2 pour une photo douce, à la mise au point signalée manquée, ou qui n'est pas la
  meilleure de sa rafale ; 1, à vérifier, pour une photo presque noire ou brûlée, ou une mise au
  point manquée sur une texture faible, 1.3 ; 1 pour une capture), que `dernierTri`
  (`ToolHandler`) garde pour le processus du serveur ; sans défaut, aucun plafond sous 5 (« aucun
  défaut mesuré : pas de plafond », correctif 1.3.2). **L'échelle resserrée d'une étoile** (1.4,
  26 octobre 2026, demandé par Dany : « je trouve que tu notes élevé », « tout baisser d'une
  étoile », « mais tu peux toujours donner un 5 étoiles ») : 1 ★ gardée, correcte (l'ancien 1 ★ et
  l'ancien 2 ★) ; 2 ★ tient seule (l'ancien 3 ★ ; un bon souvenir bien fait n'y suffit pas) ; 3 ★
  l'impact (l'ancien 4 ★) ; 4 ★ à côté des meilleures (l'ancien 5 ★) ; 5 ★ l'exceptionnel, très rare ;
  dans le doute, la plus basse ; les plafonds descendent d'une étoile (ceux d'avant : 3 et 2) ; les
  notes posées avant gardent l'ancienne échelle ; `Fenetre.SENS_NOTES` suit (« Gardée », « Tient
  seule », « A de l'impact », « Parmi vos meilleures », « Exceptionnelle »). Relevé du registre le
  même soir : sur 345 propositions, 16 % de rejets, 12 % à 1 ★, 55 % à 2 ★, 16 % à 3 ★, 1 % à 4 ★,
  dont deux 4 ★ données à des photos de famille notées seules, sans avoir vu la sortie. Une scène sur fond noir voulu (L* médian 3,9)
  reste dite « presque noire » : à revoir, hors de la 1.3.
- **Claude note de 0 à 5 ★, jamais un libellé de couleur sans demande** (correctif 1.3.2, demandé
  par Dany le 22 octobre 2026 : « si moi je veux une photo 5 étoiles, je placerai un code de
  couleur ») : `propose_ratings` refuse une note hors de 0 à 5 avant tout envoi
  (`Notation.noteMaximale = 5`, 4 jusqu'à la 1.3.1), et le module la refuse encore
  (`Notation.NOTE_MAX_PROPOSEE = 5`) ; la passe 4 (monter à 4, et à 5 pour l'exceptionnel, après
  le développement, depuis l'échelle resserrée de la 1.4) se propose comme les autres. Le standard (section « Les coups de cœur »), les descriptions de
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
  lire ni copier les jetons de connexion de Claude Code. Il pose `MAX_MCP_OUTPUT_TOKENS` (puce Noter
  une grande sélection).
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
  dire. »). Les consignes du connecteur font 3 784 caractères pour une limite de 3 796
  (`instructionsLimit` moins 300, `Version24Tests`) : raccourcir ailleurs avant d'y ajouter. La 1.2
  y a ajouté « vignetage ou radial inversé, jamais les deux », « « regression » au bilan » et
  « d'abord la simulation du boîtier, intention_boitier », et en a retiré la sauvegarde avant une
  longue série (elle reste dans la description de `get_status` et l'invite `tri_seance`) ; la 1.3,
  seulement « (read_composition) » dans « Recadrer … seulement sur demande » ; le correctif 1.3.2,
  « 0 à 5 ★, » et « libellé de couleur : sur sa demande » à la place de « 5 ★ : set_metadata, sur sa demande », payés par « rejets : set_metadata après accord »
  (au lieu de « rejets à poser par set_metadata après accord ») : toujours 3 787, sans changement
  au correctif 1.3.6 (elles ne nommaient pas `photo_lesson`) ; la retouche générative (29 octobre
  2026), « Changer un objet, un vêtement : generative_edit, sur sa demande. », sans « suppression
  générative » dans ce qui reste à la main, payée par « (sous 0,5°, invisible) », « mesure > 1,5 »,
  « Variantes : compare_variants », « dossier choisi avec lui » et « avec sa raison » : 3 784 ; le reste passe
  par les descriptions d'outils, les résultats et les invites. La
  longueur qu'une session de Claude Code garde d'une description d'outil n'est pas constatée :
  l'essentiel en tête, et un test de longueur pour les plus longues (`add_mask` 2 048 au plus,
  `view_photo` 1 850, `read_composition` 1 000, `preview_settings` 600, `analyze_photos` 520,
  `export_journal` avec sa propriété `notebook` 450, `reason` 160). Les consignes de la fenêtre
  (`Consignes.texte`, lues à chaque demande) font 6 835 caractères pour un plafond de 7 500
  (`essais-moteur.lua` ; 6 635 avec la première puce de la retouche générative, avant ses ajouts
  du même jour (consigne en anglais traduite, plusieurs changements en un appel, la couleur d'un
  objet par un masque) ; 6 359 avant la puce de la retouche générative par Fibo 2, le 29 octobre
  2026, mesurés ce jour-là, le 5 922 noté avant n'étant plus à jour ; 6 331 avant le deuxième retour de Dany du 25 octobre 2026, qui retire la
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
  disposition, après une retouche pro et une Demande rapide sur une copie d'essai du portrait
  DSCF2402, onglet Focus ; `suivi-graphiques.png` : la fenêtre Suivi ; `demande-rapide.png`,
  `publication.png`, `consommation.png`, `suivi.png` (fenêtre de la liaison) : les autres
  fenêtres ; toutes refaites le 28 octobre 2026 avec le module 1.4, par `screencapture -o -l <id>`
  de la fenêtre ; `carnet.png` est retirée le même jour (la page Carnet de progrès n'existe plus),
  `seance.png` avec la Séance en 1.1.1, `atelier.png` et `panneau.png` avec l'Atelier et le Panneau en 1.2), et une nouvelle version si ce
  qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/DeveloppeurKit/` : `JSONValue` (JSON générique), `MCPServer` (JSON-RPC, initialize, tools, prompts, ressources), `FileOutils` (appels d'outils un à un, réponse d'attente avant les 60 s de Claude Desktop), `Progression` (notifications de progression), `ContexteAppel` (progression et annulation d'un appel), `Tools` (socle des outils, 35 depuis le correctif 1.3.6, 36 avec `generative_edit` ; `fibo`, Fibo 2 injectable ; `lireEcran`, le nom de l'écran dans `get_status`, sans remarque au premier aperçu depuis le correctif 1.3.6 ; `vuesMesurees` et `zoomsMesures` du bilan ; `lecteurBoitier` ; `noterAuCarnet` ; `descriptionRaison`, la raison d'une étape) et ses extensions `Tools+Analyse` (aperçu, avec le point de mise au point, sur un zoom aussi, l'évaluation de la photo, l'éclairage, l'intention du boîtier et le bilan d'une passe à l'autre ; zoom et son `bilan_zone`, comparaison et son bilan, mesures de série, réglages ; `mesurerImage` ; `comparaisons` ; le rendu de fin de retouche au `before_claude`, `rendu_reproductible` ; la vue et la ligne au carnet : `noterLaVue`, `noterLAngle`, `constaterAuCarnet`), `Tools+Retouche` (`apply_settings`, `preview_settings`, avec le bilan d'une proposition et la surimpression du cadre proposé ; `enhance_photo`, `remove_distractions`), `Tools+Balance` (balance sur un point neutre ; `balanceProposee` d'un éclairage mixte), `Tools+Locales` (masques, taches, yeux rouges ; garde-fou de la peau, résumé du tireur dans la description d'`add_mask`), `Tools+Recalage` (grilles demandées, gardées en mémoire), `Tools+Gestion` (copie, profils, paramètres prédéfinis, journal ; `export_journal` avec `notebook`), `Tools+Bibliotheque` (recherche, classement, mots-clés, collections, copies virtuelles, photo montrée), `Tools+Tri` (tri d'une séance ou d'une sortie, 2 000 photos par appel et la suite par `offset` depuis la 1.4, planche contact jusqu'à 30 vignettes, vignettes par lots), `Tools+Notation` (`propose_ratings`, validé avant la commande `notation` ; notes posées avec `apply`), `Tools+Livraison` (`export_photos` : formats, HDR, poids, filigrane, réimportation, livraisons types lues dans les services Disque dur, noms exacts, dossier choisi, aperçus dynamiques, fenêtre d'exportation en dernier recours ; modèles de noms de fichiers et filigranes de l'utilisateur, relecture du fichier livré), `Tools+Variantes` (`compare_variants`, `choose_variant`), `Tools+Serie` (`match_series`, pentes de la balance, expositions d'après la prise de vue ; le témoin du teint depuis la 1.4), `Tools+Lumiere` (1.4 : `match_series` avec `groups`, les groupes de lumière d'une sortie et leur plan, `planDesGroupes`), `Tools+Style` (`remember_style`, ressources), `Tools+Composition` (`read_composition`, `apercu` avec `entier`), `Tools+Generatif` (`generative_edit` : struct `Fibo` injectable, mflux et SeedVR2 (`Fibo.seedVR`) ; un seul export en TIFF, un passage de Fibo par modification, chaque processus lancé et suivi par `ToolHandler.executer`, une seule barre (`BarreFibo`), recomposition de toutes les zones, une seule commande `importerGeneree`, réessayée une fois si elle n'est pas partie (`.unreachable`), le TIFF gardé dans « Fibo non importées » en échec ; un seul calcul à la fois sur le Mac (`Fibo.prendreVerrou`) ; garde de mémoire avant chaque lancement ; réponse `modifications`) ; `Tools+Lecon`, `Lecon` et `JeLeFais` sont retirés au correctif 1.3.6 ; `PriseDeVue` (vocabulaire des défauts de la prise de vue, seule liste : 17 codes depuis `yeux_fermes` au correctif 1.3.7, domaines du carnet, six mesurés ; `vocabulaire` envoyé au module), `Composition` (cadre dans l'image entière, passage de `view_photo` à l'image entière, plus grand cadre, cadre proposé et ordre de relâche, crop, résumé, lecture, regard, visages renversés et zone d'intérêt écartés ; pur), `Carnet` (seuils du carnet, dont `isoEleve`, `iso` et `bruitCherche`, `constatsVue`, `constatHorizon`, `geometrieIntacte`, Markdown d'`export_journal`, `sansLecons`, relevé `--constats`), `Tri` (défauts, rafales, ordre de lecture, plafonds de note, rejets proposés ; `PhotoTriee.defautsNettete`, seule copie des règles de netteté, partagée avec le carnet et le Suivi ; mise au point jugée sur la texture ; `partBlancPurBrulee` et `sujetsAuxYeuxLus`, repris par le Suivi depuis le correctif 1.3.7), `Notation` (standard de notation, seule copie ; plafonds de note), `GroupesLumiere` (1.4 : les groupes de lumière d'une sortie, pur : coupures, lumière de la scène, référence proposée ; seuils provisoires), `Teint` (1.4 : le témoin du teint, la peau du plus grand visage au milieu du visage, à pleine résolution de l'aperçu de mesure), `Boitier` (lecture de l'original Fujifilm d'une seule ouverture, Exif et MakerNote : point de mise au point, intention et mise au point en détail, `LectureBoitier` ; lecteur borné `LecteurBoitier`), `IntentionBoitier` (simulation, couleur, plage dynamique, tons, compensation, mode, balance, scène ; profil Lightroom de la simulation ; lecture pour Claude, `intention_boitier`), `PointAF` (point de mise au point des fichiers Fujifilm, passage dans l'image affichée ; `PointAF.marquer` pour `--marquer-af`), `Focus` (onglet Focus : `MiseAuPointBoitier`, la mise au point Fujifilm en détail et ses textes en français, `valeursLues` pour `--boitier` ; `Focus.cadres`, `Focus.tailleCadreAF`, `Focus.marquer` et `Focus.lire` (la raison d'une lecture vide, `Focus.nonLue`) pour `--focus` ; `PreviewImages.marquerFocus`), `Sauvegardes` (sauvegardes du catalogue et Time Machine, 1.3.5), `Apprentissage` (règles tirées des reprises à la main, 1.3.5), `Rendus` (rendu reproductible, `rendus.json`, 1.3.5 ; `ToolHandler.noterLeRendu`, au `view_photo` avec `compare = before_claude` depuis le correctif 1.3.6), `Suivi` (correctif 1.3.7, le Suivi côté connecteur : `--analyser` par `Suivi.analyser`, l'analyse d'office des vignettes d'un lot, avec le genre de chaque photo depuis le correctif 1.3.8, bornée par photo et pour l'appel, `mesurerBorne`, Vision deux à la fois ; `Suivi.codes`, `codesAnalyse`, `codesCarnet`, `codesSiRetouchee` ; textes, arrondis et refus du contrat, `Suivi.Refus` ; aucun chemin par défaut), `Genre` (correctif 1.3.8 : le genre d'une photo, seule liste des onze genres et de leurs règles ; `Genre.classer`, pure, sur les étiquettes de `VNClassifyImageRequest`, les visages, les personnes, les chiens et chats et l'objectif macro ; `Genre.lire`, Vision ; `Genre.regles`), `SuiviGraphiques` (`--graphiques` par `Suivi.graphiques` : lecture seule de `suivi.json` et de `carnet.json`, fusion avec le carnet, périodes (un jour de début, ou la première photo, à un jour de fin, depuis le correctif 1.3.8 ; colonnes par mois, trimestre ou année, treize au plus, `Suivi.colonnesMax`), tranches, tuiles, défaut le plus fréquent, les neuf graphiques (les notes et les genres depuis le correctif 1.3.8), leurs barres et leurs créneaux, `Suivi.placer`), `SuiviDessin` (les neuf PNG en 2x, CoreGraphics et CoreText : barres arrondies au bout, grille en pointillés, libellés de 10 à 7 points puis coupés « … » ; ni titre ni note, que la fenêtre écrit), `CarteMasque` (carte d'un masque, 1.3.4 : témoin, pixels du masque, lecture, alertes, image ; les rendus sont à `ToolHandler.cartesDesMasques`, dans `Tools+Locales`), `PointsChauds` (zones claires hors du sujet, 1.3.4), `Peau` (dosage de la peau d'après Adobe, seule copie ; effets intégrés « Peau du visage lisse » et « Adoucir la peau (Lite) » ; garde-fou d'`add_mask`), `Eclairage` (`MesureEclairage` : point neutre de l'image et centre des tons presque neutres, dominante par zone tonale et par case 3 × 3, visages à part, deux groupes de lumière et éclairage mixte, médianes par histogramme ; relevé `--eclairage`), `Bilan` (bilan chiffré d'une passe à l'autre, en fonctions pures : écarts visibles, régressions, à vérifier ; empreintes du cadre et de l'état ; les vues gardées sont à `ToolHandler`), `Ecran` (écran principal et profil ColorSync ; `nommer`, les noms seuls pour `get_status` ; six classes, textes et JSON pour `--ecran` seulement, le développement ; plus de remarque d'écran ni de `detail` depuis le correctif 1.3.6), `JetonLiaison` (fichier du jeton de la liaison : chemin, lecture, état pour `--status`), `MotsClesVision` (mots-clés de Vision traduits), `ModeleCouleur` (modèle d'une couleur prélevée), `ProfilsObjectif` (profils d'objectif `.lcp` installés), `GuideStyle` (guide de style de l'utilisateur, `~/Library/Application Support/Developpeur/guide-de-style.md`), `ReglagesAPlat` (`--dump`), `Catalogue` (les 124 réglages de développement, version minimale de Lightroom des plus récents, les profils d'appareil, les libellés), `Mesures` (mesures d'un aperçu, seuils nommés, tons neutres suivis d'une vue à l'autre), `Detail` (netteté et bruit, seuils nommés ; texture autour du point de mise au point, `Detail.autour`, `textureMin`, `textureDouteuse`), `AnalyseVision` (visages avec leur lacet et leur roulis, pupilles, note esthétique, saillance, photos semblables, cadres des personnes), `Lignes` (angle d'une ligne désignée ; « affinée » seulement sous `LineAngle.ecartMax`), `Recalage` (correspondance entre l'image corrigée et celle d'avant la correction d'objectif, Upright et la perspective), `Recette` (recette dans le vrai Lightroom ; aussi `lectureBoitier` pour `--boitier`, `Luminances`, `partAssombrie` et `formeDesBords` pour éclaircir et assombrir, `ecartMax` pour l'intensité de la peau, `dureeEclairage`, `resumeEcarts` ; photo active comparée, `ecartPhotoActive`, et registre des notes remis, `garderRegistreDesNotes`), `Recette+13` (recette de la 1.3 : Pourquoi ?, carnet, composition ; leçon et Je le fais retirés au correctif 1.3.6), `Recette+14` (recette de la 1.4 : les groupes de lumière sur toutes les photos données, en lecture seule, et la prise de vue en nombres que le module lit pour eux), `Images` (zoom, côte à côte, planche contact, carré du point de mise au point : `PreviewImages.marquerPoint` ; cadre proposé en pointillés : `PreviewImages.cadrePropose`), `ProfilsLook` (profils à base de Look installés), `EffetsLocaux` (effets locaux de Lightroom, `.lrtemplate`, puis les effets intégrés de `Peau` qui manquent), `PresetXMP` (paramètres prédéfinis XMP), `LightroomBridge` (client TCP du module, avec le jeton de la liaison dans chaque ligne), `Prompts` (invites ; `Prompts.Tireur` : doses et forme d'éclaircir et assombrir, seule copie), `ClaudeRegistration` (inscription dans les fichiers de configuration de Claude), `MiseAJour` (dernière version publiée, par `gh`, pour `--status`), `ServerInfo` (nom, titre, version, consignes données à Claude), `Generatif` (retouche générative par Fibo 2, pur : `edits` lus et refusés (zone exigée dès deux, chevauchement, zones trop proches), recadrage autour d'une zone et zone dans son repère, taille d'entrée, arguments de mflux (`--low-ram` toujours, `--vae-full-precision` en normal, deux images avec `full_and_crop`) et de SeedVR2 (`--low-ram`, seuil 1,25, bornes), mémoire disponible et ses seuils (`memoireDisponible`, `memoireMinimale`, `memoireMinimaleSeedVR`, `manqueDeMemoire`), consigne du journal en français, avancement en pourcentage et temps restant, erreurs expliquées, masque de la zone, zone changée, recomposition en pleine résolution par pièces, TIFF final avec ses métadonnées)
- `Sources/MCPDeveloppeur/main.swift` : options de ligne de commande (dont `--marquer-af`, pour l'aperçu de la photo active de la fenêtre Claude, `--focus`, pour son onglet Focus, `--analyser` et `--graphiques`, pour le Suivi (correctif 1.3.7 ; un mauvais nombre d'arguments donne le code 2, l'aide sur stderr et rien sur stdout : `usage(erreur:)`), et `--ecran`, pour le développement depuis le correctif 1.3.6 (plus de voyant Écran) ; `--boitier`, `--eclairage` et `--constats`, relevés à la main ; `--recette` avec `--horizon` et `--hauteur-horizon` ; `--status`, avec l'état du jeton et le nom de l'écran) et boucle stdio ; `outils()` pose `Ecran.lire` pour le serveur et `--call` (`get_status` seulement) ; `noterAuCarnet` vrai et `registreRendus` posé dans `serve()` seulement
- `Lightroom/Developpeur.lrplugin/`, le module :
  - déclaration et cycle de vie : `Info.lua` (« Développeur », `com.danymenard.developpeur`, menus, version), `Init.lua` / `Arret.lua` (depuis le correctif 1.3.7, le Suivi allumé au chargement et éteint à l'arrêt : `Releve.allumer`, `Releve.eteindre`), `Menage.lua` (paramètres prédéfinis invisibles effacés ; au chargement, depuis le correctif 1.3.6, les dossiers temporaires des groupes et des demandes rapides, et du Suivi depuis le correctif 1.3.7, et de Fibo 2 depuis la retouche générative : `Menage.temporaires`, `Menage.TEMPORAIRES`), `PluginInfoProvider.lua` (Gestionnaire de modules externes : section liaison, avec Mise au point et Carnet et, au diagnostic, l'état du jeton, les commandes refusées et les photos du carnet, et section fenêtre Claude, avec modèle, effort, apparence, Autre photo (reprendre sa conversation, sinon une nouvelle) et Avant/après ; les cases Leçon et « À l'ouverture » sont retirées au correctif 1.3.6), `Preferences.lua` (réglages de la liaison, dont `pointMiseAuPoint` et `carnet` ; ceux de la fenêtre dans `Chemins.defauts`, même table), `Metadonnees.lua` (champs privés), `Menu*.lua` (les neuf entrées de Module externe - Extras, dans Fichier et Bibliothèque)
  - la liaison : `Liaison.lua` (prises LrSocket, jeton privé et refus des lignes sans lui, `module.log`), `Commandes.lua` (répartition des commandes du serveur) et les modules qui les portent : `Lecture.lua` (état, avec `liaison_fermee`, sélection, réglages, paramètres prédéfinis, diagnostic, journal), `Rendu.lua` (aperçus, avec `point_af` : photo décrite par `Vignettes.decrireVignette`, évaluation, et `etapes_claude` pour le bilan ; image entière et cadre relu, `sansRecadrage` partagé avec le recalage ; la vue gardée pour `Etapes` ; propositions, `essayer` avec `entier`, rendus du recalage), `Etapes.lua` (avant/après des étapes : empreinte, vue, capture autour de chaque commande, commande `etapes`, `Etapes.images` pour la fenêtre, ménage), `Carnet.lua` (registre `carnet.json` : commande `carnet`, `constater`, `Carnet.resumer`, `vocabulaire`, `estPhotoDEssai` (`photosDuDefaut` retiré au correctif 1.3.8, avec « Photos d'un défaut… »), et `photosDesEssais` pour une grande vue du Suivi, correctif 1.3.8 ; les leçons d'avant le correctif 1.3.6 gardées telles quelles), `Retouche.lua` (appliquer, recadrer, masquer, retoucher, copier), `Amelioration.lua` (débruitage, détails bruts, super résolution), `Suppression.lua` (reflets, retrait de la poussière), `Masques.lua` (reprendre un masque : commande `masques` ; masques vides), `Conversions.lua` (rotation d'un quart de tour), `Progression.lua` (barre de progression de Lightroom pendant une série : commande `progression`), `Vignettes.lua` (vignettes du cache d'aperçus : commande `vignettes` ; `decrireVignette`, aussi pour l'aperçu de `view_photo`), `Notation.lua` (registre des notes proposées, `notation.json` : commande `notation`, avec `remettre` pour la recette, `Notation.poser`), `Livraison.lua` (exporter, fenêtre d'exportation, options de livraison, dossier choisi dans une fenêtre, noms exacts, aperçus dynamiques ; la photo de Fibo 2 importée et empilée : commande `importerGeneree`, `Livraison.dansFibo`, `Livraison.exportsFibo`), `Services.lua` (services de publication et réglages des services Disque dur, lus seulement), `Variantes.lua` (variantes en instantanés), `Annulation.lua` (annuler, revenir), `Bibliotheque.lua` (classement, paramètres prédéfinis de métadonnées, mots-clés, collections, recherche, copies virtuelles, photo montrée et filtre de la Bibliothèque : commandes `metadonnees`, `motsCles`, `collections`, `chercher`, `copieVirtuelle`, `montrer` ; notes acceptées ou posées sur demande : `Bibliotheque.noter` ; photo active et sélection remises : `Bibliotheque.remettreSelection`) ; leur socle : `Photos.lua` (photos visées, description, sensibilité ISO en nombre, mémoire de Claude ; `lireChamp` exporté pour le résumé du fil ; `Photos.rendreLaMain`, la seule copie de la main rendue à Lightroom, correctif 1.3.8), `Reglages.lua` (valeurs de développement), `Recalage.lua` (géométrie, grille du serveur), `Plans.lua` (ce qu'une retouche changera), `Ecriture.lua` (écriture dans le catalogue, étapes avec leur id, `Ecriture.nouvelleEtape`, journal, `Ecriture.difference`), `Profils.lua` (profil relu après l'écriture), `Recadrage.lua` (calcul du cadre), `Geometrie.lua` (positions de l'aperçu vers le fichier), `Locaux.lua` (tables des masques, taches et yeux rouges) — ces trois-là sans SDK —, `Json.lua` (depuis le correctif 1.3.8, `Json.decode(texte, rythme, pas)`, qui rend la main pendant une grande lecture, et `Json.ecrivain`, un objet écrit morceau par morceau), `Suivi.lua` (fenêtre de la liaison « Claude · liaison », menu « Afficher la fenêtre de la liaison », « fenêtre de suivi » jusqu'au correctif 1.3.6 ; `MenuSuivi.lua` garde son nom) ; `Liaison.lua` compte aussi les commandes en cours (`Liaison.enCours`, `Liaison.finCommande`, correctif 1.3.6), pour qu'Agrandir ne rende pas la photo pendant elles
  - la fenêtre Claude : `Fenetre.lua` (la fenêtre : état, actions, boucle, apparence, calques et boutons, bandeau, textes des cartes page par page, carte Note B, aperçu de la photo active et son carré de mise au point, « Obtenir » (la proposition demandée sous la carte Proposition, à la place de celle préparée à l'ouverture), une photo, une conversation (`suivreSelection`, `suivrePhotos`, conversation neuve ou de groupe, « Repartir à neuf »), voyants de l'en-tête (Claude Code et Lightroom ; versions et mode dans l'infobulle du voyant Lightroom ; le voyant Écran retiré) et boutons Suivi, Publication… et Consommation… (`ouvrirSuivi`, `ouvrirPublication`, `ouvrirConsommation` : correctif 1.3.7), la sélection vue passée au Suivi (`suivreSelection` par `Releve.voirSelection`, `Releve.revoir` à l'ouverture, `Releve.relancer` dans la boucle : correctif 1.3.7), titre « Développeur v… » (`titreFenetre`), aide d'une liaison sans jeton, menu Mes demandes et ses fenêtres Ajouter…, Renommer… et Supprimer… (« ＋ Garder la demande » retiré au correctif 1.3.6), le résumé en haut du fil (`resume`, `suivreResume`, `suivreNoteDuResume`, `ajouterResume`, `lignesAide`) ; onglets Focus, Note, Aperçu et Proposition : la mise au point de la photo active, la note, l'étape ou l'image du fil cliquée avec son pourquoi (`voirImageDuFil`, `etapeAvant`, `choisirEtapeDeLImage`), la proposition et la composition ; ouverture sur Focus et retour à Focus (`revenirAFocus`), bascules vers Aperçu, Proposition et Note ; Agrandir qui remplit 2 000 × 1 250 (`GRANDE`, `agrandirUne`, `agrandirDeux`, `cadreDeux` ; la photo active redemandée en grand : `agrandirActive`, `preparerGrande`, `rendreActive`, `TAILLE_GRANDE`) ; la vignette de secours de l'aperçu de la photo active (`DELAI_SECOURS_ACTIVE`, `decrireActive`) ; plus de volet, de liste, de Mode, de Leçon, de « Je le fais », d'onglet Suivi, de « Pourquoi ? » ni de Détail… dans l'onglet Aperçu depuis le correctif 1.3.6), `Vues.lua` (ses pièces : aplats, images, boutons bleus, éléments inactifs, ligne du fil, en-tête (titre, « Repartir à neuf », deux voyants, boutons Suivi, Publication… et Consommation… : `boutonSuivi`, `boutonPublication`, `boutonConsommation`), saisie, menu Mes demandes et bandeau, segments, aperçu, cartes Proposition, Aperçu (sans Détail… depuis le correctif 1.3.6), Focus et Note, et la fabrique masquable des onglets ; ni Noter ni Évaluer), `Dispositions.lua` (la fenêtre B, seule disposition : tailles, dimensions, onglets (`ONGLETS`, seule liste), images, apparences et palettes), `Fil.lua` (le fil en lignes : texte riche, appel, auteur et heure, actions (« ☆ Voir la note » ; « ＋ Garder la demande » retiré au correctif 1.3.6), éléments `historique`, mention « Demande rapide », le résumé de la fenêtre et sa place (`lignesResume`, `tete`, `avecResume`) ; `lignesCarte`, les textes des cartes coupés ; le texte de l'onglet Focus ; celui de la fenêtre Suivi, `texteSuivi`, est retiré au correctif 1.3.7), `Metriques.lua` (chasse des polices, produite par `scripts/metriques.swift`), `Moteur.lua` (conversations et processus de Claude Code, indépendants de la fenêtre ; la conversation de chaque photo : `conversationDe`, `preparerPhoto`, `completerDepuis`, `resumerGroupe`, `ecarter`, `noterVu` ; la Demande rapide : `envoyerRapide`, `conversationPour`, `reponseRapide` ; modèle et effort d'une demande), `Historique.lua` (correctif 1.3.6 : ce que la fenêtre dit d'une photo sans Claude ni jetons, « Historique de la photo », « Depuis la dernière fois » et le résumé d'un groupe, seule copie de leurs textes ; lectures du journal de Claude et des reprises à la main, `Historique.vu` ; les réglages hors des valeurs par défaut d'une photo sans étape de Claude, `Historique.ecarts` ; le résumé en haut du fil, section « Le résumé de la fenêtre » : `lireResumePhoto`, `lireResumeGroupe`, `resumePhoto`, `resumeGroupe`, `texteNote`), `FenetreSuivi.lua` (correctif 1.3.6, en graphiques depuis le correctif 1.3.7 : la fenêtre Suivi, sa période (deux dates gardées, « Du » et « au », depuis le correctif 1.3.8 : `lireDate`, `changerDate`, `periode` ; et leur calendrier, `ouvrirCalendrier`, `choisirDate`), ses tuiles, les neuf images de `--graphiques` (les genres sous « Ce que je photographie » depuis le correctif 1.3.8) et leurs 87 calques, les photos d'une barre dans la Bibliothèque ; « Photos d'un défaut… » et « Retirer du carnet… » retirés au correctif 1.3.8 ; depuis le correctif 1.3.8, `reclasserEnFond`, le reclassement dans sa propre tâche, `delaiRedessin`, la réponse décodée en rendant la main, et la sélection d'une barre posée par `Releve.poserSelection`), `Releve.lua` (correctif 1.3.7 : le relevé du Suivi, `suivi.json`, par original ; la file d'analyse d'office et sa tâche, par `--analyser` ; `Releve.reclasser`, `Releve.ecrire`, `Releve.uuidsDe` pour la fenêtre Suivi ; depuis le correctif 1.3.8, toute la bibliothèque : relu et écrit par morceaux, une relecture et une écriture à la fois, le JSON de chaque entrée gardé, la file gardée d'une vue à l'autre et ses réessais, `Releve.delaiEcriture`, `Releve.poserSelection`, `Releve.rendreLaMain` ; et le genre rangé avec l'analyse, refait seul : `Releve.reglesGenre`, `Releve.sansGenre`), `Calendrier.lua` (correctif 1.3.8 : le calendrier des champs « Du » et « au » de la fenêtre Suivi, une fenêtre modale de vues simples ; ses calculs purs : `joursDuMois`, la seule copie, `jourDeLaSemaine`, `grille`, `decaler`, `annees`, `cases`), `FenetreRapide.lua` et `MenuRapide.lua` (la Demande rapide ; sa sélection vue passée au Suivi depuis le correctif 1.3.7), `Session.lua` (un processus Claude Code par `relais.sh`), `relais.sh`, `Evenements.lua` (lignes stream-json de Claude Code), `Conversation.lua` (éléments d'une conversation : étapes, cadre demandé, dernier zoom, éléments `historique` ; champs `photo`, `vu`, `ecartee`, `groupe` (la retouche du tour et « Demande à garder » de Claude retirées au correctif 1.3.6) ; les éléments `lecon` et `exercice` d'avant le correctif 1.3.6 gardés sans ligne au fil), `Stockage.lua` (conversations sur le disque, jamais effacées depuis le correctif 1.3.6, et Mes demandes : `mes-demandes.json`), `Images.lua` (aperçus et photos jointes, base64 et `sips` ; carré de mise au point par le connecteur : `Images.marquerMiseAuPoint` ; onglet Focus : `Images.lireFocus` ; vignette remise à l'endroit : `Images.rotationManquante`, `Images.redresser` ; Agrandir : `Images.grande`, qui remplit la place), `presse-papiers.js` (lecture du presse-papiers par `osascript`), `Consignes.lua` (consignes ajoutées, dont les puces Peau (sans chiffres), Notes (la note d'abord de chaque photo traitée) et Mise au point montrée, et le résumé chiffré du bilan ; depuis la 1.3, les sections Composition et Raison de chaque étape, et la puce Carnet ; depuis le correctif 1.3.6, l'historique dans le Contexte et la fin d'une retouche par `view_photo` avec `compare = before_claude` (les sections Je le fais, Leçon de la photo, Écran et Demande à garder retirées) ; sept invites en raccourcis, dont Portrait, Paysage et Noir et blanc qui demandent la méthode du tireur sans chiffres, et Composition ; ajustements du cadre ; demande d'« Obtenir » (`Consignes.obtenir`, à la place de `proposerOuverture`), réponses aux propositions, règles de la Demande rapide (`rapide`, `rapidePhoto`), styles, modèles et efforts), `Lightroom.lua` (photo active, sa note et sa légende, sélection, sa clé et celle de son groupe, état et mode de la liaison, liaison occupée (`Lightroom.liaisonOccupee`, correctif 1.3.6), connexion de Claude Code, valeurs de l'onglet Focus : `Lightroom.infosFocus` ; l'écran principal n'y est plus lu depuis le correctif 1.3.6), `Composants.lua` (versions du module et du connecteur, dans l'infobulle du voyant Lightroom depuis le correctif 1.3.6 ; celle du module dans la barre de titre de la fenêtre Claude), `Raccourcis.lua` (⌃⌥C), `Chemins.lua` (dossiers et réglages de la fenêtre), `Fichiers.lua` (`Fichiers.ecrireParMorceaux` depuis le correctif 1.3.8 : un fichier écrit morceau par morceau, jamais à moitié), `Texte.lua` (UTF-8), `Journal.lua` (`conversation.log`), `Compat.lua` (`os.time`, `os.date`), `images/` et `images/sombre/` (les images de la fenêtre B en 2x, un jeu par apparence, dont `vide-498x332.png`, l'image « aucun aperçu ») ; `FenetrePublication.lua` et `Publication.lua` (profils et exportation de la fenêtre Publication), `FenetreConsommation.lua` et `Consommation.lua` (jetons comptés, budget de la semaine). La Séance de notation (`FenetreNotation.lua`, `MenuNotation.lua`) est retirée depuis la 1.1.1 (demandé par Dany le 20 octobre 2026)
- `scripts/` : `tester-module.sh` (vérification du module avec LuaJIT, essais à part des deux suites compris), `metriques.swift` (chasse des polices de la fenêtre), `gabarits.lua` (les tailles des images et les palettes de `Dispositions.lua`, en JSON), lu par `images-fenetre.swift` (les images de la fenêtre B, en deux jeux) et `images-vides.swift` (l'image « aucun aperçu » de chaque apparence, `vide-498x332.png`)
- `.github/workflows/tests.yml` : syntaxe des scripts et les deux suites à chaque envoi sur `main` (macOS)
- `build.sh` (tests, compilation, signature, archive notarisée), `install.sh`, `uninstall.sh`
- `Resources/Info.plist` : identifiant `com.danymenard.mcp-developpeur` et version (incrusté par `-sectcreate` dans `Package.swift`)
- `docs/SPEC.md` : cahier des charges, protocole entre le serveur et le module, les chantiers de la 1.3 et ce qui en reste à constater, et la fenêtre Claude (architecture, contraintes du SDK, fenêtre B et ses constats, fichiers) ; `docs/aide-adobe-developpement.md` : notes sur l'aide d'Adobe (outils de développement, ordre d'utilisation, écarts avec la méthode du connecteur, ce qui reste à faire à la main), à relire avant de changer les consignes (`ServerInfo`, `Consignes.lua`) ou les invites (`Prompts`) ; captures, refaites le 28 octobre 2026 : `capture.png` (la fenêtre Claude, capture principale du README), `suivi-graphiques.png` (la fenêtre Suivi), `demande-rapide.png`, `publication.png`, `consommation.png`, `suivi.png` (fenêtre de la liaison) ; `docs/lavish/` : les sources des pages Lavish publiées en artefacts (Analyse du Développeur, `analyse-1-5.html`), une par page, à garder identiques à leur artefact
