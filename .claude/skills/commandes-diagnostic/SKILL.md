---
name: commandes-diagnostic
description: Commandes détaillées de diagnostic et d'essai de Développeur (MCP-Développeur et module Lightroom). À charger pour faire la recette dans Lightroom ou la recette d'une version, essayer un outil à la main (--status, --call, --module diagnostic), lire les réglages à plat (--dump), mesurer le recalage, la mise au point, l'écran, le boîtier Fujifilm, fixer les seuils du carnet ou de l'éclairage mixte (--constats, --eclairage) ou les pentes de l'étalonnage d'après une référence (--etalonnage), essayer --analyser ou --graphiques du Suivi, lire les journaux, utiliser les variables DEVELOPPEUR_*, remesurer les polices, regénérer les images de la fenêtre, ou désinstaller en détail.
---

# Commandes de diagnostic et d'essai

Sorti de `CLAUDE.md` le 31 octobre 2026 (tableau Commandes) ; à lire quand on diagnostique, fait la
recette, mesure des seuils, ou regénère polices et images de la fenêtre. Les commandes de base
(construire, installer, tester, recharger le module) restent dans `CLAUDE.md`.

## Tester le serveur

`swift test` (jamais le vrai Lightroom, ni le vrai jeton, ni le vrai écran, ni le vrai mflux) ;
`DEVELOPPEUR_ECRAN_REEL=1 swift test --filter EcranTests` lit en plus le vrai écran du Mac
(`testLectureReelleSansPlantage`, sauté sans cette variable : lecture seule, aucune valeur attendue)

## Tester le module

`scripts/tester-module.sh` (LuaJIT : `brew install luajit`) : forme du module, syntaxe, globales,
liens entre les fichiers, puis les suites `Tests/Lua/Liaison` et `Tests/Lua/Fenetre`, et chaque
`essais-*.lua` des deux ; `DEVELOPPEUR_SUIVI_ORIGINAUX=250000 scripts/tester-module.sh` fait l'essai
« Taille réelle » d'`essais-releve.lua` à la borne de 250 000 originaux (85 000 par défaut ; plus
long)

## Essayer à la main

`swift build && ./.build/debug/mcp-developpeur --status` (inscriptions, module, état du fichier du
jeton de la liaison, jamais sa valeur, le nom de l'écran principal, même Lightroom fermé, puis la
liaison), puis `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée ;
lit l'écran comme le serveur, et chaque `--call` est un nouveau processus : le bilan de `view_photo`
y repart de zéro) ; `--module diagnostic` liste les fonctions du SDK offertes, et avec `'{"valeurs":
true}'` lit le jeu de libellés, le filtre de la Bibliothèque et l'original de la photo active ;
`--version`

## Recette dans Lightroom

`./.build/debug/mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>]
[--yeux-rouges <id>] [--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id>
[--hauteur-horizon <0 à 1>]] [--original] [--images <dossier>]` (copies virtuelles de la collection
« Développeur › Essais » que Claude n'a pas encore retouchées ; avec le vrai pont seulement, d'abord
deux étapes en lecture seule : « liaison fermée (jeton privé) » (commande sans jeton, puis avec un
autre jeton, refusées ; ni le jeton ni son chemin dans `get_status`) et « écran nommé (get_status) »
(un nom non vide, rien d'autre que `nom` et `autres` chez Claude, depuis le correctif 1.3.6) ; le
RAW passe aussi par « intention lue au boîtier (view_photo, intention_boitier) », « bilan chiffré
d'une passe à l'autre (view_photo), puis annulé », puis la 1.3 (`Recette+13.swift`) : « avant/après
d'une étape gardé sans autre rendu (Pourquoi ?), puis annulé » et « carnet de progrès : photo
d'essai refusée, notée pour la recette (essai_recette), exportée, retirée » (les étapes de la leçon
de la photo et de « Je le fais » sont retirées avec eux au correctif 1.3.6) ; l'étape du débruitage
vérifie aussi que la photo active revient ; `--horizon` : une copie d'Essais qui a un vrai horizon
net, à `--hauteur-horizon` (0,5 par défaut), pour les trois étapes de la composition (lue et
montrée, cadre actuel lu sur l'image entière recadrée en 4:5 et tournée de 2°, cadre proposé
appliqué et horizon remesuré), la dernière sautée avec sa raison sans horizon net ; sans
`--horizon`, la recette dit que la composition n'est pas vérifiée ; et, dans le tri, « éclaircir et
assombrir : radial inversé et dégradé linéaire (propositions) » puis « … : forme des bords (radial
inversé, propositions) » ; `--flash` : une photo au flash, pour les expositions d'après la prise de
vue ; `--profondeur` : la copie d'une photo Portrait d'iPhone ; `--yeux-rouges` : une vraie photo au
flash ; `--x-t20` : un RAF de X-T20, avec l'étape « point de mise au point dessiné pour noter
(view_photo, af_point) » (carré dessiné si le point est lu, évaluation dite, chemin de l'original
jamais rendu à Claude) et l'intention lue au boîtier ; `--portrait` : un portrait, la carte du
masque (1.3.4 : peau du visage et arrière-plan en proposition, `mask_map` ; la peau couvre le
visage, l'arrière-plan n'y déborde pas, aucune alerte) et la peau dosée (visages vus par Vision ;
trois doses en propositions, détail des joues mesuré ; `amount` 50 = la moitié de la dose, jugé à
l'écart maximal, 2 niveaux au plus ; peau trop lissée refusée sans `smoothing_requested`, rien
d'écrit ; dose par défaut posée à `amount` 50, relue, annulée) ; `--mixte` : une photo à deux
lumières, en lecture seule (éclairage mixte nommé, cases lues sur 9, durée de la mesure), puis le
RAW de `--recette` en témoin à une seule lumière s'il est une autre photo ; `--original` accepte un
original désigné par Dany ; `--images` : le dossier des zooms à regarder (et des deux vues du bilan)
; chacune est remise à l'origine ; l'étape « note proposée (propose_ratings), photo inchangée ; puis
posée sur demande et annulée » vérifie le refus de 6 ★ (5 ★ refusées jusqu'à la 1.3.1), range une
proposition à vérifier par la vraie commande `notation`, puis pose 2 ★ par `propose_ratings` avec
`apply` et les annule par `undo_last` ; le registre `notation.json` est remis ensuite comme avant
l'étape, même après un échec (`notation` `remettre`, `Recette.garderRegistreDesNotes`) ; enfin la
1.4 (`Recette+14.swift`), sur toutes les photos données dès qu'il y en a deux : « groupes de lumière
(match_series, groups), rien d'écrit » (chaque photo comptée une fois dans un groupe ou seule, aucun
réglage changé, la prise de vue en nombres lue par la commande `vignettes` : ouverture, vitesse,
flash))

## Recette d'une version

toutes les options dont la collection d'essai a une photo (le 21 octobre 2026 : `--jpeg`, `--x-t20`,
`--portrait`, `--mixte` ; ni flash, ni yeux rouges, ni Portrait d'iPhone, ni vrai horizon :
`--horizon` demande d'ajouter aux Essais une copie qui a un horizon net, mer, lac ou plaine ; la
dune 53709786 ne convient pas, ses rides de sable faussent la mesure), sur des copies remises à
l'origine d'abord (`revert_to_original` : une copie que Claude a déjà retouchée est refusée) ;
`--mixte` sur le portrait d'essai, la seule copie à deux lumières (relevé du 20 octobre 2026) ;
l'étape du témoin à une seule lumière ne vient que si le RAW de `--recette` est une autre photo ; la
sortie dans un fichier, en arrière-plan, jamais tronquée (`| head` coupe la recette au milieu d'une
étape) ; puis l'essai dans la fenêtre Claude (skill `publier-version`, étape 3)

Ce qui reste à voir dans Lightroom, hors des étapes de la recette : `docs/SPEC.md`, À vérifier à la
prochaine recette (les seuls points encore ouverts des sections « À constater », un par ligne, avec
leur lien et la façon de les voir : dans la recette, à la main dans Lightroom, ou avec Dany). Un
point constaté passe dans sa section et sort de cette liste.

## Réglages à plat

`./.build/debug/mcp-developpeur --dump [<id>]` (une clé par ligne, pour `diff` avant et après une
opération faite à la main)

## Recalage mesuré

`./.build/debug/mcp-developpeur --recalage <id>` (écarts du modèle de recalage sur la géométrie
actuelle ; deux rendus « Claude · recalage » dans l'Historique)

## Carré de mise au point

`./.build/debug/mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg>
<sortie.jpg>` (ce que la fenêtre Claude lance, avec le connecteur de `cheminConnecteur`, pour
l'aperçu de la photo active : `PointAF.marquer` lit le point dans un original Fujifilm en temps
borné (`LecteurBoitier`), le passe dans l'image affichée et le dessine sur la vignette : le cadre AF
rouge à la taille de Focus-Points avec un point au centre, comme l'onglet Focus
(`PreviewImages.marquerFocus`, correctif 1.3.3), sinon le carré vert, rouge si l'appareil a signalé
la mise au point manquée ; code 1 sans point)

## Écran du Mac

`./.build/debug/mcp-developpeur --ecran` (pour le développement seulement depuis le correctif 1.3.6
: l'écran principal et les autres, avec leur profil de couleur classé, d'usine, standard, à l'œil,
sonde, personnalisé ou inconnu, une ligne JSON, chemin du profil compris, sans la clé `detail` ni le
texte de la boîte du voyant Écran, retirés avec lui ; `{"lu": false}` sans écran ; lu sans Lightroom
ni permission ; ni la fenêtre Claude ni Claude ne le lisent plus)

## Cadres de mise au point (onglet Focus)

`./.build/debug/mcp-developpeur --focus <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>`
(ce que la fenêtre Claude lance pour l'onglet Focus, par `perl` et son alarme de 5 s :
`Focus.marquer` lit la mise au point d'un original Fujifilm en temps borné (`LecteurBoitier`),
dessine sur la vignette le cadre AF à sa taille en rouge et les visages et éléments du sujet en
coins jaunes (`PreviewImages.marquerFocus`), puis écrit une ligne JSON : `lue`, les blocs `image`,
`prise_de_vue` et `mise_au_point` en paires titre, valeur en français, `point_af`, `cadres`,
`dessinee` ; rien de lu : `{"lue": false, "raison": …}` (`delai`, `introuvable`, `illisible` :
`Focus.lire`) et code 1)

## Lecture du boîtier

`./.build/debug/mcp-developpeur --boitier <original>` (un fichier Fujifilm, RAF ou JPEG, lu sans
Lightroom par `LecteurBoitier` : point de mise au point, `intention_boitier` comme `view_photo`,
`mise_au_point` comme l'onglet Focus, et `valeurs_lues` sous les noms d'exiftool, pour comparer avec
lui (`exiftool -a -G1 -s`, celui de Focus-Points, en lecture seule) ; une ligne JSON, code 1 si rien
n'est lu)

## Analyse du Suivi

`./.build/debug/mcp-developpeur --analyser '<json>'` (ce que le relevé du Suivi lance, depuis
`Releve.lua`, par `perl` et son alarme de 60 s, la réponse dans un fichier : 1 à 20 photos `{id,
vignette, iso, cache, retouchee, objectif}` (`objectif` depuis le correctif 1.3.8, pour le genre
macro), le module en envoie 10 ; chacune mesurée sur sa vignette du cache de Lightroom, déjà
redressée, par les mesures et les règles du tri et du carnet (`Suivi.analyser` : netteté et bruit à
1 024 px, la netteté ramenée par `thumbnailSharpnessFactor` si `cache`, exposition et blanc pur du
tiers haut à 512 px par `Carnet.constatsVue` sans point de mise au point ni intention, surexposition
au-delà de `PhotoTriee.partBlancPurBrulee`, yeux fermés par `PhotoTriee.yeuxFermes` seulement s'il y
a des `sujetsAuxYeuxLus`, bruit seulement à ISO `Carnet.isoEleve` ou plus, seuls flou et yeux avec
`retouchee`), et depuis le correctif 1.3.8 le genre de la photo (`Genre.classer` : étiquettes de
`VNClassifyImageRequest`, visages, personnes, chiens et chats, objectif macro), Vision deux à la
fois, sans Lightroom ni original ; une ligne JSON `{ok, regles, regles_genre, photos: [{id,
cherches, defauts, genre, mesures}]}` en codes de `PriseDeVue` et de `Genre`, ou par photo `{id,
raison, texte}` (`vignette_absente`, `vignette_illisible`, `vignette_petite` sous 900 px, `delai` :
15 s par photo, 50 s pour l'appel, pour que la ligne parte avant l'alarme) ; refus de l'appel `{ok:
false, raison, texte}` et code 1 (`arguments`, `trop_de_photos`) ; code 2 pour un nombre d'arguments
faux, l'aide sur stderr et rien sur stdout ; forme figée dans `Tests/Contrats/suivi.json`)

## Graphiques du Suivi

`./.build/debug/mcp-developpeur --graphiques '<json>' <dossier>` (ce que la fenêtre Suivi lance, par
`perl` et son alarme de 60 s depuis le correctif 1.3.8, 20 s avant, la réponse dans un fichier : lit
seulement `suivi.json` et `carnet.json` aux chemins donnés, aucun par défaut, et la table du
catalogue donné ; d'après `debut` (facultatif : depuis la première photo) et `fin`, des jours «
AAAA-MM-JJ » que donne le module (rien ne dépend de l'horloge du connecteur ; à la place
d'`aujourd_hui` et de `periode`, `3_mois`, `12_mois` ou `tout`, depuis le correctif 1.3.8),
`apparence` et ses six couleurs tirées de `Dispositions.PALETTES`, `defaut` (absent : le plus
fréquent) et les tailles en points, dessine les neuf PNG en 2x dans le dossier (créé s'il manque ;
`SuiviDessin.swift`) et écrit une ligne JSON : période (`debut`, `fin`, `libelle`, `par` : `mois`,
`trimestre` ou `annee`, treize colonnes au plus, `depuis_le_debut`), photos, quatre tuiles, les huit
défauts comptés, neuf graphiques (les notes de 0 à 5 ★ et les genres de photos depuis le correctif
1.3.8) avec leurs barres (rectangle dessiné, zone cliquable, `ids` croissants des originaux) et
leurs créneaux ; refus `{ok: false, raison, texte}` et code 1 (`arguments`, `defaut_inconnu`,
`suivi_illisible`, `dossier`, `dessin`), sans PNG laissé ; code 2 comme `--analyser` ; un relevé de
20 000 originaux en 0,3 s environ, une ligne de toute la bibliothèque de 0,7 Mo ; de 250 000 en 2,6
s, 0,7 Go de mémoire, une ligne de 10,6 Mo, que la fenêtre décode en rendant la main (mesuré le 26
octobre 2026 avec le graphique des notes, sur un relevé synthétique de photos de 2010 à 2026, « Du »
vide ; le graphique des notes y ajoute une fois de plus les ids de toute la période, environ 15 %) ;
forme figée dans `Tests/Contrats/suivi.json`)

## Relevé des seuils provisoires (1.6)

`./.build/debug/mcp-developpeur --mesures --echantillons <suivi.json> <dossier>` (lots A1 à A8 tirés
de `suivi.json`, lu seulement, graine fixe), puis `--mesures --collecter <dossier>/lots/A1.json
<dossier>/A1 [--taille 1024] [--par 15]` (vignettes par 10 à 20, copiées puis retirées du dossier
temporaire du module, heure exacte, compensation et flash du catalogue, note de Claude repérée au
journal ; reprise si relancée ; Lightroom peut rendre des aperçus manquants), puis `--mesures
--mesurer <dossier>/A1` (sans Lightroom : `mesures.jsonl`, `mesures.csv`, `paires.csv`,
`resume.txt`, `resume.json`) ; `--mesures --fichiers <dossier> <fichier.jpg>…` pour des fichiers.
Seuils, commandes exactes et règles de décision : `docs/SPEC.md`, Relevé des seuils provisoires
(1.6). En arrière-plan, sortie dans un fichier.

## Relevé du carnet

`./.build/debug/mcp-developpeur --constats <id>… [<fichier.jpg>…]` (pour fixer les seuils du carnet
de progrès, en lecture seule : aperçu avec `point_af` à 1 344 px et les clés de la géométrie, jamais
`carnet constater` ; par photo, L* médian et 95e centile, blanc pur du tiers haut, netteté et
texture (au point de mise au point aussi), bruit, ISO et si le bruit y est cherché (1.3.1 ; l'Exif
d'un fichier), boîtier, géométrie, étapes de Claude, défauts cherchés et retenus, puis un résumé ;
un JPEG se mesure sans Lightroom, sans point ni intention ; lignes ✘ et code 1 en cas d'échec)

## Relevé de l'éclairage

`./.build/debug/mcp-developpeur --eclairage <id>… [<fichier.jpg>…] [--essai '{…}']` (pour fixer les
seuils de l'éclairage mixte : dominantes des tons neutres par case 3 × 3 et par zone tonale,
visages, zone d'intérêt et scène de Vision, aux bornes 12, 15, 20, 25 et 30 de l'écart a*b* au
centre des tons neutres, chaque ligne « borne N : … ; point neutre a* x b* y, centre a* x b* y »,
durée de la mesure, puis un résumé ; lecture seule par la commande `apercu`, sans point AF ni
original ouvert ; un fichier JPEG se mesure sans Lightroom ; `--essai` passe par `preview_settings`
(deux étapes « Claude · essai »), copies virtuelles seulement)

## Relevé de l'étalonnage (match_look, 1.6)

`./.build/debug/mcp-developpeur --etalonnage <id>… [<fichier.jpg>…] [--balayage]` (pour fixer les
constantes provisoires de `Reference.swift` : docs/SPEC.md, Étalonnage d'après une référence, À
constater). Sans `--balayage`, lecture seule (commande `apercu`, ou un fichier JPEG sans
Lightroom) : par image, une ligne « C* < N : » à chaque borne 12, 20, 30 et 45, avec la couleur
a*b* et la part de chaque zone tonale, la chroma médiane et P90, les centiles de L*, les bandes de
la TSL et les remarques (bandes noires, visages). Avec `--balayage` (identifiants de NOUVELLES
copies virtuelles d'Essais remises à l'origine seulement ; un original est refusé) : 29 rendus par
`preview_settings` (deux étapes « Claude · essai » chacun, 58 en tout, à défaire ensuite par
`revert_to_original`), teintes 0 à 300 par zone à saturation 25, saturations 12, 25 et 50 à la
teinte 30, Vibrance ±30 ; chaque ligne donne le décalage a*b* de chaque zone, puis un résumé
(angle et gain dans sa zone, `vibranceParChroma`). Sortie dans un fichier, en arrière-plan, jamais
tronquée ; lignes ✘ et code 1 en cas d'échec.

## Journal détaillé

`DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ;
`DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre
port ; `DEVELOPPEUR_FIBO_GARDER=<dossier>` (développement seulement : chaque appel de
`generative_edit` y copie, dans un sous-dossier à son nom, les rendus du masque, le TIFF exporté
avec ses métadonnées, GPS compris, l'entrée, le masque et la sortie de Fibo ; rien n'y est jamais
effacé : ne pas la laisser posée)

## Journaux du module

`~/Library/Logs/Developpeur/module.log` (liaison, avec les commandes refusées faute du bon jeton :
une ligne par genre de refus toutes les 10 s au plus, jamais le jeton) et `conversation.log`
(fenêtre Claude, Demande rapide, et depuis le correctif 1.3.7 le relevé et la fenêtre Suivi), gardés
sous 1 Mo ; échanges avec Claude Code : `~/Library/Application Support/Developpeur/Sessions/`

## Recharger le module dans Lightroom

Fermer les fenêtres du module (devant, elles réduisent le menu Fichier), Lightroom au premier plan,
puis Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du module externe
› Charger de nouveau le module ext. Un fichier `.lua` ajouté depuis le lancement ne se charge pas
ainsi (« Could not load toolkit script »), ni donc un fichier qui le requiert (`Commandes.lua`
requiert `Notation.lua`, nouveau en 1.1, et `Etapes.lua` et `Carnet.lua`, nouveaux en 1.3 ;
`Moteur.lua` requiert `Historique.lua`, et `Fenetre.lua` `FenetreSuivi.lua`, nouveaux au correctif
1.3.6 ; `Fenetre.lua`, `FenetreRapide.lua` et `FenetreSuivi.lua` requièrent `Releve.lua`, nouveau au
correctif 1.3.7 ; `FenetreSuivi.lua` requiert `Calendrier.lua`, nouveau au correctif 1.3.8), ni un
raccourci clavier changé : quitter et relancer Lightroom, après toute version qui ajoute un fichier
`.lua`

## Remesurer les polices

`swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua` (la police du
système, `'<system>'` en 13, 12 et 11 et `'<system/bold>'` en 13, 12, 11 et 16, et Menlo 11 : clés
`texte`, `texte12`, `petit`, `gras`, `gras12`, `gras11`, `titre`, `mono` ; si une police du fil ou
des cartes change dans `Fenetre.lua`, ou pour un caractère nouveau, comme ★ ☆ ⚑ ＋ ⊗ ⤢)

## Images de la fenêtre

`luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin`
(les deux jeux, `images/` en claire et `images/sombre/`, d'après `Dispositions.IMAGES`,
`Dispositions.PALETTES` et l'ordre des segments (`segments` des gabarits, tiré de
`Dispositions.ONGLETS`) ; refus avant d'écrire d'une couleur absente ou invalide, d'un dossier
invalide, d'aucun segment ou d'un segment en double ; signale les images orphelines) ; l'image «
aucun aperçu », au cadre de l'aperçu (`images/vide-498x332.png` et `images/sombre/vide-498x332.png`)
: `luajit scripts/gabarits.lua | swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` ;
après tout changement des tailles ou des palettes

## Désinstaller

`bash uninstall.sh [--tout]` (inscriptions, serveur, module, paramètres prédéfinis invisibles
Lightroom fermé, fichiers de travail, dont le jeton de la liaison `liaison.jeton` et
`liaison.jeton.nouveau`, que la liaison d'un Lightroom ouvert réécrit dans les 5 s : relancer le
script Lightroom fermé ; `--tout` : aussi guide de style, conversations, mes demandes de la fenêtre
Claude (`mes-demandes.json`), profils de publication, consommation, notes proposées
(`notation.json`), carnet de progrès et leçons d'avant le correctif 1.3.6 (`carnet.json`), relevé du
Suivi (`suivi.json`, et `suivi-illisible-*.json`, un relevé illisible mis de côté ; correctif
1.3.7), avant/après des étapes (`Etapes/`) et journaux ; sans `--tout`, ils restent ; jamais le
catalogue ni les photos, ni « Fibo non importées » s'il n'est pas vide)
