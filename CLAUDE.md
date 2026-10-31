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

Les outils, les invites et les ressources `developpeur://` se lisent dans
`Sources/DeveloppeurKit/` (fichiers `Tools+*.swift`) ; les options de l'exécutable, dans le tableau
Commandes. Le README décrit les fonctions du point de vue de l'utilisateur ; le protocole entre le
serveur et le module, les chantiers de la 1.3 et la fenêtre Claude (section Fenêtre Claude, dont
Fenêtre B) sont dans `docs/SPEC.md`.

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
| Journal détaillé | `DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ; `DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre port ; `DEVELOPPEUR_FIBO_GARDER=<dossier>` (développement seulement : chaque appel de `generative_edit` y copie, dans un sous-dossier à son nom, les rendus du masque, le TIFF exporté avec ses métadonnées, GPS compris, l'entrée, le masque et la sortie de Fibo ; rien n'y est jamais effacé : ne pas la laisser posée) |
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
   (https://claude.ai/artifact/9kQ7kKQk5VuXrrAWFrvVKS, source `docs/artefacts/analyse-1-5.html`,
   analyse de la 1.4 du 27 octobre 2026) : la relire (Artifact, `read`), marquer faits les constats
   que la version livre et corriger ce qui est devenu faux, puis la republier à la même adresse.
   Feuille de route, Les 35 outils et Ordinogramme d'une retouche sont supprimées, avec leurs
   sources, à la demande de Dany le 27 octobre 2026, comme Guide des demandes et Apprendre avec
   Claude le même jour. Tout document nouveau pour Dany (guide, compte rendu, plan) se fait en
   page HTML publiée en artefact privé (outil Artifact ; Dany le relit et l'annote par les
   commentaires de l'artefact), sa source dans `docs/artefacts/`, commitée et poussée, jamais un
   document Claude Docs. Lavish n'est plus utilisé depuis le 31 octobre 2026.

Le README pointe vers `https://github.com/mdany75/Developpeur/releases/latest/download/Developpeur.zip`.

## Règles

Les règles propres à une partie du projet sont dans des fichiers à part, chargés quand on y
travaille. Les lire avant d'y toucher :

- `Lightroom/CLAUDE.md` : le module Lua (catalogue, Bibliothèque, livraisons, Suivi, carnet,
  notation côté module, fenêtre Claude et fenêtre B, relais) ;
- `Sources/CLAUDE.md` : les mesures et les outils en Swift (composition, détail, éclairage, écran,
  bilan, peau, doses, lumière, teint, tri, notation, masques, mise au point) ;
- `docs/regles/retouche-generative.md` : la retouche générative par Fibo 2 (`generative_edit`).

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
  défait ensuite (`undo_last`, `revert_to_original` ou ⌘Z). Ranger une copie dans Essais **après**
  l'avoir remise à l'origine : `revert_to_original` défait aussi ce rangement (classement gardé dans
  la mémoire `Bibliotheque`) ; constaté le 29 octobre 2026, la copie n'était plus dans Essais et le
  TIFF de Fibo 2 a été empilé avec le vrai original.
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
- Le préfixe « Claude · » des noms de masques (serveur) et d'étapes (module) n'est jamais doublé :
  un nom donné qui le porte déjà le perd d'abord.
- Chaque constat fait dans Lightroom (« Constaté dans Lightroom Classic » de `docs/SPEC.md`,
  section Fenêtre Claude comprise) a sa règle dans la simulation de sa suite (`Tests/Lua/Liaison` ou
  `Tests/Lua/Fenetre`) et un test qui échoue sans la correction, même quand il confirme le code (le
  radial inversé) ; et une étape de la recette quand c'est possible. Un constat de rendu (une
  image), que la simulation ne peut pas imiter (la linéarité de `CorrectionAmount`), le dit dans
  `docs/SPEC.md` et a son étape de recette.
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
  (`Consignes.texte`, lues à chaque demande) font 7 074 caractères pour un plafond de 7 500
  (`essais-moteur.lua` ; 6 996 avant la photo de référence, `reference`, le 31 octobre 2026 ; 6 922 avant la mention du masque peint, `mask` avec `existing`, le soir du
  29 octobre 2026 ; 6 835 avant la mention de `mask` (masque de Lightroom) dans la puce de la
  retouche générative, le soir du 29 octobre 2026 ; 6 635 avec la première puce de la retouche générative, avant ses ajouts
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

- `Sources/DeveloppeurKit/` : le serveur MCP et ses outils ; `Sources/MCPDeveloppeur/main.swift` :
  les options de ligne de commande ; `Tests/` : les essais (`swift test`).
- `Lightroom/Developpeur.lrplugin/` : le module Lua et la fenêtre Claude.
- `scripts/` : essais du module, polices et images de la fenêtre ; `build.sh`, `install.sh`,
  `uninstall.sh` ; `Resources/Info.plist` : identifiant et version.
- `docs/SPEC.md` : cahier des charges et protocole ; `docs/regles/` : règles chargées au besoin ;
  `docs/artefacts/` : sources des pages publiées en artefacts.
- Règles par partie : `Lightroom/CLAUDE.md`, `Sources/CLAUDE.md`.
