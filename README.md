# Développeur

Développeur relie Claude à Lightroom Classic sur Mac : vous écrivez à Claude dans une fenêtre de
Lightroom (ou dans Claude Desktop ou Claude Code), et il regarde vos photos, les mesure et les
retouche avec la méthode d'un retoucheur professionnel, en vous disant ce qu'il change et pourquoi.
Il est fait pour le photographe amateur qui veut des photos d'allure professionnelle sans être un
pro. Deux pièces : le connecteur MCP-Développeur, un serveur MCP (*Model Context Protocol*) écrit
en Swift, et le module « Développeur » de Lightroom Classic, qui exécute ses demandes et porte la
fenêtre Claude.

![La fenêtre Claude dans Lightroom Classic](docs/capture.png)

## Fonctions

### La fenêtre Claude dans Lightroom

- Une fenêtre flottante : Fichier › Module externe - Extras › Ouvrir la fenêtre Claude (même entrée
  dans le menu Bibliothèque, et raccourci ⌃⌥C une fois posé). Elle reste ouverte pendant que vous
  travaillez, dans tous les modules de Lightroom.
- Claude y travaille par Claude Code et votre forfait claude.ai, avec les seuls outils du
  connecteur : ni fichiers, ni terminal, ni web.
- Les conversations à gauche, rangées par période (aujourd'hui, cette semaine, plus ancien), avec
  une recherche dans leurs titres et leurs messages, sans tenir compte des accents. Chacune est une
  session Claude Code, reprise telle quelle à la réouverture. Renommer, supprimer (à la corbeille
  du Finder ; les retouches faites dans Lightroom restent).
- Un titre tiré de ce que Claude voit sur la première photo (« Flamant rose au bord de l'eau »).
- Le fil au centre : vos demandes, les réponses de Claude (titres et listes mis en forme), et
  chaque appel d'outil sur une ligne (✓ fait, ● en cours, ✕ erreur) ; un clic sur un outil montre
  ce que Claude a demandé au connecteur et sa réponse. ▲, ▼ et Fin pour s'y déplacer.
- « Ce que Claude voit », à droite : les aperçus qu'il regarde et les photos jointes, à parcourir
  avec ◀ ▶ et à agrandir.
- Claude reçoit avec chaque demande la photo active et la sélection de Lightroom.
- Six invites en raccourcis : Retouche pro, Portrait, Paysage, Noir et blanc, ISO élevé, Sports.
- Un style joint à chaque demande, invites comprises : Standard (rien d'ajouté), Ambre et éclat,
  Or et peau douce, Or rose et éclat, Éclatant et peau douce, Neutre, Rose froid et peau douce.
  « Peau douce » passe par un masque de la peau, jamais par un réglage de toute la photo.
- Le modèle, choisi par demande : Opus (retouche fine), Sonnet (courant), Haiku (rapide).
- Joindre une photo du disque (📎 : JPEG, PNG, HEIC, TIFF, WebP) ou coller l'image du
  presse-papiers (📋 : capture d'écran, image copiée, photo copiée dans le Finder), comme exemple
  ou comme référence de style.
- Retour envoie la demande ; Arrêter interrompt Claude proprement en pleine retouche.
- Des voyants : Claude Code (connecté au forfait ou non), liaison avec Lightroom (arrêtée, un clic
  la démarre), mode du connecteur (un clic bascule entre « Proposer d'abord » et « Appliquer
  directement »), et le dernier relevé du forfait (5 heures et semaine). Une aide en rouge dit quoi
  faire quand quelque chose manque.
- En bas à droite, les versions du module et du connecteur, en orange si elles ne vont plus
  ensemble.
- Fermer la fenêtre n'arrête pas Claude : le travail continue et se retrouve à la réouverture.
  Claude Code reste ouvert entre deux demandes (réponses plus rapides) et se ferme après 15 minutes
  sans demande (5 minutes ou 1 heure au choix) ou quand Lightroom quitte.

### Ce que Claude sait faire par le connecteur

Les mêmes 33 outils servent dans la fenêtre Claude, dans Claude Desktop et dans Claude Code. Huit
invites prêtes à l'emploi s'y ajoutent, dans le menu « + » de Claude Desktop et parmi les commandes
« / » de Claude Code : `retouche_pro` (une photo, en deux passes vérifiées, puis au plus deux passes
correctives si un défaut reste), `harmoniser_serie`, `tri_seance`, `portrait`, `paysage`,
`noir_et_blanc`, `nuit_iso_eleve` et `partage` (écran, web, Instagram, impression), chacune avec
ses précisions au choix (style, photos, destination) ; celles qui retouchent suivent votre guide de
style.

**Regarder et mesurer**

- Voir une photo telle qu'elle est développée en ce moment (aperçu rendu par Lightroom), avec ses
  données de prise de vue et des mesures : luminosité (L*, centiles), écrêtage des hautes lumières
  (aussi canal par canal) et des ombres, contraste, saturation, dominante des tons neutres,
  netteté par zone et bruit.
- Ce que voit Vision d'Apple, sur ce Mac et sans réseau : visages et pupilles, qualité de chaque
  visage, note esthétique, zone qui attire l'œil.
- Zoom à 100 % sur une zone (netteté, bruit, poussières) ; avant/après côte à côte (avant la
  première retouche de Claude, ou avant la dernière).
- Mesurer au dixième de degré l'angle d'une ligne qui devrait être droite (horizon, bâtiment,
  poteau), pour redresser sans tâtonner.
- Lire tous les réglages d'une photo, groupés comme dans le module Développement (profil,
  recadrage, courbes, masques, taches), avec son classement (note, drapeau, libellé, titre,
  mots-clés).

**Retoucher**

- Les réglages du module Développement : balance des blancs, tonalité, présence, courbes
  paramétrique et par points (RVB et par canal), TSL, noir et blanc et son mélangeur, étalonnage
  des couleurs, couleur ponctuelle, netteté et réduction du bruit, vignetage et grain, corrections
  d'objectif, transformation (Upright, perspective), calibrage, mode HDR (édition HDR, limite HDR,
  curseurs de l'aperçu SDR). En valeurs absolues ou en décalage, sur une photo, une liste de
  photos ou toute la sélection.
- Profils : Adobe Standard, les simulations de film Fujifilm des RAW (PROVIA, Velvia, ASTIA,
  CLASSIC CHROME, REALA ACE, PRO Neg., ETERNA, ACROS, MONOCHROME), et tous les profils à base de
  Look installés : Adobe Color, Paysage, Portrait, profils créatifs avec leur intensité de 0 à
  200 %, profils adaptatifs (RAW), et les vôtres. Le profil est relu après coup : si Lightroom ne
  le garde pas pour votre appareil, Claude le dit.
- Balance des blancs et tonalité automatiques de Lightroom, préréglages de balance (lumière du
  jour, nuageux, tungstène…), et balance sur un point neutre de l'image, comme la pipette : Claude
  mesure le point, le ramène au neutre et vérifie.
- Flou d'objectif : arrière-plan flou d'après la profondeur que Lightroom estime, intensité, forme
  du bokeh, et le pinceau d'affinage pour un contour mal détouré (des cheveux, par exemple).
- Débruitage IA, détails bruts et super résolution, que Lightroom calcule lui-même : la photo
  s'affiche le temps du calcul dans le module Développement, puis la vue revient comme avant.
  Suppression des reflets d'une vitre (Suppression des distractions › Reflets), de même.
- Redresser et recadrer : angle, ratio (« 4:5 », « 16:9 »…), taille et centre, sans bord vide.
  Après Upright ou une perspective, le module coche « Contraindre le recadrage » et Lightroom
  resserre le cadre pour ne laisser aucun coin vide.
- Variantes : deux à quatre interprétations d'une photo (naturelle, chaude, noir et blanc…),
  rangées en instantanés « Claude · … » et montrées sur une planche numérotée ; celle que vous
  choisissez se pose comme une retouche, les autres s'effacent.
- Copier une retouche vers d'autres photos, comme Synchroniser (sur demande avec le recadrage, les
  masques et les taches) ; appliquer un paramètre prédéfini, à l'intensité voulue, ou en créer un
  d'après une retouche réussie (groupe « Claude », visible au lancement suivant de Lightroom).
- Passer une photo d'une version de processus 3 à 5 à la version 6 (toujours montré d'abord),
  imposer un profil d'objectif installé (objectif manuel ou adapté), tourner d'un quart de tour,
  prendre un instantané avant une retouche importante.

**Retouches locales**

- Masques IA calculés par Lightroom : sujet, ciel, arrière-plan, parties d'une personne (peau du
  visage et du corps, iris, lèvres, dents, cheveux, sourcils, barbe, vêtements), éléments de
  paysage (eau, végétation, montagnes, architecture, sol, neige).
- Une personne précise d'une photo de groupe (« la personne de gauche », « les cheveux de l'enfant
  à droite »), repérée par Vision : Lightroom calcule le même masque qu'à la main.
- Masques combinés (« le ciel sans le bâtiment », « le sujet limité aux hautes lumières »), objet
  désigné par un cadre ou un trait, pinceau le long de traits (éclaircir et assombrir à la main),
  dégradés linéaires et radiaux, plages de luminance, de couleurs (prélevées dans l'image) et de
  profondeur (photos Portrait d'iPhone).
- Réglages locaux, courbe du masque, couleur ponctuelle dans un seul masque, et les effets du
  panneau Masque (Blanchiment des dents, Renforcement de l'iris, Adoucir la peau, et les vôtres),
  posés sur la bonne partie et réglables en intensité.
- Reprendre un masque après coup : masquer, afficher, dupliquer (inversé au besoin), retirer,
  recalculer, adoucir ou resserrer son contour (Lightroom 15.5). Les masques que Lightroom trouve
  vides sont retirés, et Claude le dit. Chaque masque porte un nom « Claude · … » dans le panneau
  Masquage.
- Effacer des taches (poussières du capteur, petits défauts) en correction, en duplication ou avec
  l'outil Supprimer sans IA générative ; corriger des yeux rouges.
- Des positions justes malgré la correction d'objectif, Upright ou la perspective : le connecteur
  mesure le déplacement sur deux rendus de la photo et recale chaque position.

**Séries et tri**

- Trier une séance, jusqu'à 500 photos (sélection, collection ou dossier), sur les vignettes que
  Lightroom garde déjà en cache, sans exporter chaque photo : photos floues, mise au point manquée
  (au point de mise au point lu dans les RAW et
  JPEG Fujifilm), yeux fermés ou plissés, photos presque noires ou brûlées, rafales et piles de
  Lightroom avec la meilleure de chacune, classement par netteté, note esthétique et qualité des
  visages.
- Claude propose drapeaux, notes et mots-clés (ceux de Vision, traduits en français), et ne les
  pose qu'après votre accord ; une photo que vous avez déjà classée n'est pas touchée.
- Planche contact : douze vignettes numérotées en une seule image, pour voir une série d'un coup
  d'œil.
- Mesurer une série et la comparer à une photo de référence ; repérer les photos semblables
  (rafales, quasi-doublons) et la meilleure de chaque groupe.
- Harmoniser une série sur une photo de référence, en chiffres : exposition, balance des blancs et
  contraste. Claude montre d'abord le plan photo par photo ; avec votre accord, il corrige en deux
  passes mesurées. Ou l'exposition seule, d'après l'ouverture, la vitesse et l'ISO (une série prise
  en manuel, un bracketing).
- Une longue série montre sa progression photo par photo, dans Claude Code et dans la barre de
  progression de Lightroom, et s'arrête proprement si vous l'interrompez (Échap dans Claude Code,
  croix de la barre dans Lightroom). Avant des centaines de photos, Claude propose une sauvegarde du
  catalogue, que Lightroom fait à sa prochaine fermeture.

**Bibliothèque**

- Chercher dans tout le catalogue : texte, mot-clé, note, drapeau, libellé de couleur, appareil,
  objectif, ISO, format, dates, dossier, collection, photos retouchées ou non par Claude, retenues
  jamais exportées.
- Classer : note, drapeau, libellé de couleur, titre, légende, droits d'auteur, texte alternatif et
  description longue rédigés d'après la photo, champs IPTC (lieu, événement, personnes), mots-clés
  rangés dans votre hiérarchie (« Lieux > Canada > Montréal »), paramètre prédéfini de métadonnées.
- Position GPS donnée, ou reprise des photos de votre téléphone prises au plus près dans le temps
  (horloge de l'appareil décalée comprise).
- Collections (dans un ensemble « Claude »), collections dynamiques d'après une recherche ;
  renommer ou déplacer une collection, renommer un mot-clé. Rien n'est jamais supprimé.
- Copies virtuelles nommées, pour essayer une interprétation sans toucher à l'original.
- Montrer dans Lightroom la photo dont parle Claude (loupe, grille, comparaison, ensemble, module
  Développement, avant/après), ou le résultat d'un tri par un filtre de la Bibliothèque ; votre
  filtre d'avant revient ensuite.
- Un classement s'annule comme une retouche.

**Export et partage**

- Exporter des photos développées comme dans Lightroom, dans le dossier que vous choisissez (par
  son chemin, ou dans une fenêtre que Claude ouvre dans Lightroom) : JPEG, JPEG XL, AVIF, TIFF,
  PNG, PSD, DNG ou original ; qualité, espace colorimétrique, taille, netteté de sortie,
  métadonnées, lieu retiré par défaut. Un fichier qui existe déjà n'est jamais écrasé : le nouveau
  reçoit « -2 ».
- Sortie HDR pour une photo réglée en mode HDR (Claude relit le fichier livré et dit s'il est bien
  HDR) ; poids maximal d'un JPEG ; filigrane (le vôtre, ou vos droits d'auteur) ; vos modèles de
  noms de fichiers, et les noms exacts que Lightroom donnera.
- Les réglages de vos services de publication « Disque dur » comme livraisons types, et vos
  dossiers d'exportation récents ; remettre un fichier livré dans le catalogue, par exemple un
  TIFF d'impression empilé avec l'original.
- Disque des originaux débranché : une photo part depuis son aperçu dynamique, jusqu'à 2560 px.
  Claude crée ces aperçus avant que vous partiez avec le portable, et les retire au retour.
- En dernier recours, la fenêtre d'exportation de Lightroom s'ouvre pour ces photos, et vous
  terminez.

**Mémoire et style**

- Un guide de style personnel, en Markdown, que vous pouvez modifier :
  `~/Library/Application Support/Developpeur/guide-de-style.md` (profils, contraste, couleurs,
  peaux, noir et blanc, grain, recadrage, livraison). Claude le lit avant de retoucher, et n'y
  ajoute une préférence (« jamais de vignetage ») qu'après votre accord sur la phrase exacte.
- Claude voit ce que vous avez corrigé à la main depuis sa dernière retouche (« Vibrance remise à
  0, Ombres +54 »), en tient compte, et vous propose de le retenir dans le guide.
- Chaque retouche est une étape nommée du panneau Historique (« Claude · passe 1 : lumière et
  couleur »), précédée la première fois d'un instantané « Avant Claude ». Le journal des
  retouches, photo par photo, garde la raison de chacune et s'exporte en Markdown.
- Annuler la dernière retouche de Claude, ou revenir à l'état d'avant Claude : seulement ce qu'il a
  changé, vos retouches faites à la main restent.
- Champ « Retouchée par Claude » dans les métadonnées, pour filtrer ces photos dans la Bibliothèque.

### Publication

Une fenêtre à part (Publication…, dans le menu du module ou par le bouton de la fenêtre Claude),
pour publier des photos en fichiers sans Claude, donc sans quota.

- Cinq profils : JPEG 5 Mpx, JPEG pleine qualité, Web (2048 px), Instagram (1080 px de petit côté,
  à recadrer en 4:5 avant) et Impression (TIFF 16 bits, Adobe RVB) ; et les vôtres (Nouveau profil… :
  format JPEG, TIFF ou PNG, qualité, espace colorimétrique, taille, profondeur, poids maximal,
  filigrane).
- Un profil, ou plusieurs formats à la fois (un sous-dossier chacun) ; la photo active, la
  sélection ou une collection ; le dossier de publication.
- Un de vos modèles de noms de Lightroom, avec son texte personnalisé, et les noms qu'il donnera ;
  droits d'auteur seulement dans les métadonnées, lieu (GPS) retiré, filigrane des droits d'auteur ;
  poids estimé.
- Lightroom exporte lui-même, sans jamais écraser un fichier (« -2 ») et sans changer les photos du
  catalogue.

![La fenêtre Publication](docs/publication.png)

### Consommation

Une fenêtre à part (Consommation…) pour suivre ce que la fenêtre Claude consomme de votre forfait.

- Les économies actives : seulement le connecteur, aucun outil intégré ni compétence de Claude
  Code, un dossier de travail à part, la publication sans Claude, Claude Code gardé ouvert entre
  deux demandes.
- Les jetons comptés cette semaine et un budget de la semaine, de 500 000 à 20 millions de jetons
  (ou sans budget) : alerte à 80 %, arrêt des demandes à 100 %.
- Le dernier relevé du forfait que Claude Code transmet (5 heures et semaine, tous modèles
  confondus) ; le menu Usage de Claude reste la référence.
- Les jetons par jour sur une semaine et les dernières demandes. Seules les demandes faites dans la
  fenêtre Claude sont comptées.

![La fenêtre Consommation](docs/consommation.png)

### Fenêtre de suivi et garde-fous

- La fenêtre de suivi (Afficher la fenêtre de suivi) : état de la liaison, version, mode,
  proposition en attente, derniers réglages appliqués, journal où un clic sélectionne la photo,
  Annuler la dernière retouche, et Mettre en pause (Claude peut alors regarder, pas retoucher).
- Un message bref au centre de l'écran à chaque retouche de Claude (désactivable).
- Dans le menu du module : Revenir à « Avant Claude » (photos sélectionnées ; ⌘Z annule),
  Créer une copie virtuelle pour Claude, Démarrer et Arrêter la liaison avec Claude.
- Dans Fichier › Gestionnaire de modules externes › Développeur : démarrer la liaison au lancement,
  le mode, l'instantané « Avant Claude », la variation maximale de l'exposition par retouche (2 IL
  par défaut) et la saturation maximale (30) ; photos protégées (copies virtuelles seulement,
  photos d'un libellé de couleur, photos rejetées) ; un plafond de photos par retouche sans accord
  explicite (20 par défaut) ; un diagnostic à coller dans la conversation et le journal. Une
  retouche refusée dit pourquoi.

![La fenêtre de suivi de la liaison](docs/suivi.png)

### « Proposer d'abord »

- Dans ce mode (Gestionnaire de modules externes, ou un clic sur le voyant de la fenêtre Claude),
  Claude montre le rendu de ce qu'il propose, côte à côte avec l'état actuel, ou décrit le
  changement, puis attend votre accord. Le module refuse toute écriture que Claude ne présente pas
  comme approuvée (retouche, masque, tache, classement, collection, exportation), et Claude ne le
  fait qu'après votre « oui ».
- Dans la fenêtre Claude, la proposition s'affiche à droite (réglages avant → après) avec
  Accepter, Refuser et Ajuster… : un texte libre, ou un ajustement d'un clic (Moins chaud, Peau
  plus naturelle, Garder le ciel, Plus de contraste).
- Pour que l'accord ne vienne que de vous : la case « l'accord se donne ici » du Gestionnaire de
  modules externes. Seul le bouton Accepter de la fenêtre de suivi compte alors, pour une seule
  écriture, dans les 10 minutes.

## Vos photos

Ce que Claude regarde part chez Anthropic, qui fait tourner Claude. Le reste ne quitte pas le Mac.

Ce qui part chez Anthropic quand Claude regarde ou classe :

- les aperçus JPEG que Lightroom rend pour lui (1344 px de grand côté par défaut, 2048 au plus), y
  compris les avant/après, les propositions et les variantes ;
- les zooms à 100 % : un extrait de la photo en pleine résolution, 1600 px au plus ;
- les planches contact (douze vignettes) ;
- les photos que vous joignez ou collez dans la fenêtre Claude (réduites à 1568 px) ;
- la description des photos : nom du fichier, appareil, objectif, réglages de prise de vue, date,
  dimensions, note, drapeau, libellé, réglages de développement ;
- les métadonnées que Claude lit ou pose : titre, légende, mots-clés, droits d'auteur, champs IPTC,
  position GPS, noms des collections, et le chemin d'un dossier quand il en a besoin (recherche,
  livraison, original introuvable) ;
- les chiffres des mesures et de Vision (luminosité, netteté, visages, mots-clés), et bien sûr vos
  messages.

Ce qui reste sur le Mac :

- le catalogue et les originaux : Claude ne reçoit jamais un fichier original ;
- le calcul des mesures et l'analyse de Vision, faits sur le Mac, sans réseau ; le tri lit les
  vignettes du cache de Lightroom sur le Mac et n'en envoie que les résultats ;
- les fichiers exportés, et toute la fenêtre Publication, qui ne parle jamais à Claude ;
- les conversations de la fenêtre Claude (avec les images que Claude a regardées), le guide de
  style, les profils de publication et le registre de consommation, dans
  `~/Library/Application Support/Developpeur/` ; les journaux dans `~/Library/Logs/Developpeur/`.
  Claude Code garde aussi ses propres sessions dans `~/.claude`.

Le module et le connecteur se parlent par deux ports de cet ordinateur seulement (54770 et 54771,
adresse 127.0.0.1). Le connecteur n'appelle jamais Anthropic lui-même ; la seule question qu'il
pose au réseau est celle de `--status` à GitHub, par `gh`, sur la dernière version publiée.

Claude passe par votre forfait claude.ai, jamais par une clé d'API : Claude Desktop et Claude Code
sont connectés à votre compte, et la fenêtre Claude lance le `claude` officiel en retirant de son
environnement toute clé d'API (`ANTHROPIC_API_KEY`…) ; elle ne lit jamais vos jetons de connexion.
Ce qui part chez Anthropic suit les conditions et les réglages de confidentialité de votre compte
claude.ai.

## Ce qui reste à faire à la main dans Lightroom

Le SDK de Lightroom ne donne pas tout aux modules. Claude vous propose de faire ceci à la main :

- **Poussière du capteur** : Suppression des distractions › Poussière sur une photo ; pour une
  série, Copier puis Coller de Lightroom avec la case Poussière (Lightroom la refait pour chaque
  photo). Un module ne peut ni la lancer ni la faire refaire ; Claude peut seulement la retirer.
- **Passants** : Suppression des distractions › Personnes, qui passe par le remplissage génératif
  d'Adobe.
- **Suppression générative** : l'outil Supprimer avec l'IA générative ; les taches de Claude
  emploient l'outil Supprimer sans elle.
- **Upright avec repères** : Claude pose les repères, mais Lightroom ne calcule la correction qu'au
  clic sur « Mettre à jour » (panneau Transformation), que Claude vous demande.
- **Anciennes versions de processus** : une photo en version 1 ou 2 (2003, 2010) se met à jour à
  la main ; seul Lightroom sait convertir ses curseurs.
- **Fusion HDR et panorama** (Photo › Fusion de photos), et la correction de champ plat.
- **Mise au point du flou d'objectif par un cadre tracé sur l'image** : Claude la règle sur le
  sujet ou sur une plage de profondeur.

Le débruitage, les détails bruts, la super résolution et la suppression des reflets demandent
Lightroom Classic 15.3 ou plus récent ; le contour d'un masque IA, 15.5. La plage de couleurs suit
un modèle de couleur approché : Claude en vérifie la sélection sur l'aperçu.

## Installer

Téléchargez [Developpeur.zip](https://github.com/mdany75/Developpeur/releases/latest/download/Developpeur.zip)
(toujours la dernière version) et décompressez-le. Quittez Claude Desktop (⌘Q) : ouvert, il garde
sa configuration en mémoire et la réécrit, sans le connecteur. Puis dans le Terminal :

```bash
bash ~/Downloads/Developpeur/install.sh
```

Le script, sans droits d'administrateur :

1. copie le connecteur `mcp-developpeur` dans `~/Library/Application Support/Developpeur/` ;
2. copie le module `Developpeur.lrplugin` dans `~/Library/Application Support/Adobe/Lightroom/Modules/`,
   d'où Lightroom Classic le charge à son lancement (une version précédente est remplacée en
   entier) ;
3. inscrit le connecteur sous le nom `MCP-Developpeur` dans Claude Desktop
   (`claude_desktop_config.json`) et dans Claude Code (`~/.claude.json`), en gardant une copie
   `.avant-mcp-developpeur` de chaque fichier, et retire l'ancien connecteur `lightroom` (MCP
   Lightroom, que Développeur remplace) ; si Claude Desktop est ouvert, il le dit : le quitter,
   lancer `"$HOME/Library/Application Support/Developpeur/mcp-developpeur" --install`, puis le
   rouvrir ;
4. Lightroom fermé seulement, efface les paramètres prédéfinis invisibles que le module crée pour
   les masques IA et le flou d'objectif (il recrée ceux dont il a besoin) ;
5. dit si Claude Code manque pour la fenêtre Claude.

Ce qui est déjà là reste : guide de style, conversations, profils de publication, registre de
consommation, journaux. Le catalogue et les photos ne sont jamais touchés.

Ensuite :

- quitter et relancer Lightroom Classic : le module se charge et démarre la liaison ;
- ouvrir Claude Desktop : le connecteur `MCP-Developpeur` apparaît dans ses outils ;
- dans Claude Code, ouvrir une nouvelle session (`/clear` ne relance pas le connecteur) ;
- pour le raccourci ⌃⌥C : Fichier › Gestionnaire de modules externes › Développeur › Poser le
  raccourci, puis relancer Lightroom. Un module ne peut pas déclarer de raccourci : c'est un
  raccourci d'app de macOS, qui sert quand la fenêtre principale de Lightroom est devant. Pour le
  poser à la main (Réglages Système › Clavier › Raccourcis clavier › Raccourcis des apps), taper
  trois espaces puis « Ouvrir la fenêtre Claude » : Lightroom met ces espaces devant chaque entrée
  de module.

Configuration requise :

- macOS 14 ou plus récent ;
- Lightroom Classic 13.3 ou plus récent (le module ne se charge pas dans une version plus
  ancienne) ;
- Claude Desktop ou Claude Code, connecté à votre compte claude.ai ;
- pour la fenêtre Claude : [Claude Code](https://claude.com/claude-code) installé et connecté
  (`claude`, puis `/login`), à `~/.local/bin/claude` par défaut (aussi cherché dans
  `/opt/homebrew/bin` et `/usr/local/bin`, et réglable dans le Gestionnaire de modules externes) ;
- facultatif : [`gh`](https://cli.github.com) connecté à GitHub, pour que `--status` signale une
  version plus récente.

Le connecteur ne demande pas l'Accessibilité ni aucune autre permission particulière ; seul macOS
peut demander une fois l'accès au disque de vos photos (voir En cas de problème). Pour vérifier
l'installation, Lightroom ouvert :

```bash
"$HOME/Library/Application Support/Developpeur/mcp-developpeur" --status
```

Pour désinstaller : `bash uninstall.sh` (dans le dossier décompressé, ou depuis le dépôt),
Claude Desktop fermé comme pour l'installation (sinon, le script dit quoi vérifier). Il
retire l'inscription dans Claude, le connecteur, le module, ses paramètres prédéfinis invisibles
(Lightroom fermé) et ses fichiers de travail, et garde votre guide de style, vos conversations,
vos profils de publication, le registre de consommation et les journaux ; `bash uninstall.sh
--tout` les retire aussi. Les retouches déjà faites restent dans le catalogue (elles s'annulent
dans le panneau Historique).

### Premiers pas

Lightroom ouvert, une photo sélectionnée, demandez à Claude par exemple : « Retouche la photo
active, rendu naturel et un peu chaud », « Passe-la en CLASSIC CHROME et redresse l'horizon »,
« Assombris le ciel sans toucher au bâtiment », « Efface les poussières du capteur », « Débruite
cette photo de nuit », « Montre-moi d'abord ce que tu proposes », « Montre-moi trois
interprétations : naturelle, chaude et noir et blanc », « Harmonise cette série sur la troisième
photo », « Trie la séance et propose-moi les meilleures » ou « Prépare la sélection pour
Instagram ».

Claude regarde la photo, pose un diagnostic chiffré, applique une première passe (profil, balance
des blancs, tonalité), vérifie le rendu, puis fait les finitions, dans l'ordre que recommande
l'aide d'Adobe (corrections d'objectif avant Upright, débruitage avant les masques et les taches).
Si la vérification montre encore un défaut précis (hautes lumières brûlées, dominante, masque trop
visible), il fait une passe corrective ciblée, deux au plus, et dit ce qui reste. Pour comparer :
l'instantané « Avant Claude », ou un avant/après demandé à Claude (la touche `\` du module
Développement montre l'état à l'importation, pas celui d'avant Claude).

Claude Desktop abandonne un outil au bout de 60 secondes. Quand Lightroom travaille plus longtemps
(plusieurs masques IA, débruitage), le connecteur répond avant : Claude dit que Lightroom finit
encore et rappelle l'outil, qui donne alors le résultat sans rien refaire. Claude Code et la
fenêtre Claude attendent la fin.

### En cas de problème

- **Liaison coupée après une installation** : relancer Lightroom (le module se recharge à son
  lancement), puis vérifier avec `--status`. « Charger de nouveau le module ext. » (Gestionnaire de
  modules externes) relance aussi la liaison, mais ne voit pas un fichier ajouté au module depuis
  le lancement de Lightroom.
- **Voyant Claude Code en rouge dans la fenêtre** : ouvrir le Terminal, lancer `claude`, puis
  `/login` avec votre compte claude.ai ; ou régler le chemin de Claude Code dans le Gestionnaire de
  modules externes.
- **Demandes arrêtées dans la fenêtre** : le budget de la semaine est atteint ; l'augmenter dans
  la fenêtre Consommation.
- **Outils absents ou anciens dans Claude** : relancer Claude Desktop, ou ouvrir une nouvelle
  session Claude Code. Un connecteur et un module de versions différentes sont signalés (en orange
  dans la fenêtre Claude, et par Claude).
- **Connecteur absent de Claude Desktop après l'installation** (ou ancien connecteur `lightroom`
  revenu, que `--status` signale) : Claude Desktop était ouvert et a réécrit sa configuration. Le
  quitter (⌘Q), lancer `"$HOME/Library/Application Support/Developpeur/mcp-developpeur" --install`,
  puis le rouvrir.
- **Fenêtre « … souhaite accéder aux fichiers d'un volume »** : macOS demande l'autorisation de
  lire le disque de vos photos pour le connecteur lancé par Claude ; c'est à vous d'y répondre.
  Sans elle, le tri continue sans lire le point de mise au point des RAW Fujifilm.
- **Fenêtre « Mises à jour IA recommandées »** : Lightroom n'a pas pu calculer un masque IA (ses
  modèles IA ne sont pas encore téléchargés) ; répondre « Exporter », case « Mettre à jour les
  photos concernées » cochée.
- **« Synch. auto » de Lightroom** : dans les essais, les retouches de Claude ne se sont pas
  propagées aux autres photos sélectionnées ; la couper quand même pendant que Claude travaille, par
  précaution.
- **Une retouche refusée** : le message dit pourquoi (mode « Proposer d'abord », photo protégée,
  plafond de photos, liaison en pause). Le diagnostic du Gestionnaire de modules externes et les
  journaux `~/Library/Logs/Developpeur/module.log` (liaison) et `conversation.log` (fenêtre Claude)
  aident à comprendre un échec.

## Reconstruire

Il faut Xcode (ou ses outils en ligne de commande) avec Swift 5.9 ou plus récent, et LuaJIT pour
les tests du module (`brew install luajit`). Pour une archive signée et notarisée : le certificat
« Developer ID Application » dans le trousseau et un profil `notarisation` de `xcrun notarytool` ;
sans certificat, la signature est ad hoc et l'archive n'est pas notarisée.

```bash
./build.sh
```

Le script vérifie que le numéro de version est le même dans `Resources/Info.plist`, `Info.lua` et
`Liaison.lua`, et que `CHANGELOG.md` a sa section ; lance les deux suites de tests ; compile le
connecteur ; le signe ; puis produit `build/Developpeur.zip` (connecteur, module, `install.sh`,
`uninstall.sh`, README, CHANGELOG, licence), notarisé chez Apple.

- `./build.sh --install` installe ensuite sur ce Mac ce qui vient d'être produit.
- `./build.sh --sans-tests` saute les tests (essai rapide, jamais pour une version publiée).
- `SKIP_NOTARIZE=1 ./build.sh` signe sans notariser ; `SIGN_IDENTITY="-"` impose la signature ad
  hoc.

## Tests

```bash
swift test
```

Le connecteur : protocole MCP, outils, catalogue des réglages, inscription dans Claude (sur des
fichiers temporaires) et liaison TCP avec un faux module Lightroom.

```bash
scripts/tester-module.sh
```

Le module, avec LuaJIT : forme du module, syntaxe et globales de chaque fichier, syntaxe de
`relais.sh`, liens entre les fichiers, puis deux suites, chacune sur son Lightroom simulé :
`Tests/Lua/Liaison` (les commandes du connecteur) et `Tests/Lua/Fenetre` (la fenêtre Claude avec un
faux Claude Code, Publication et Consommation).

Aucun test ne touche Lightroom, Claude, vos photos ni les fichiers de Claude, et aucun ne consomme
de quota. Les deux suites tournent aussi à chaque envoi sur `main` (GitHub Actions).

Pour la mise au point, Lightroom ouvert et liaison démarrée, l'exécutable installé
(`~/Library/Application Support/Developpeur/mcp-developpeur`) offre aussi :

- `--call <outil> '{…}'` : appelle un outil comme le ferait Claude ;
- `--module diagnostic` : les fonctions du SDK que Lightroom offre au module
  (`'{"valeurs": true}'` lit aussi le jeu de libellés, le filtre de la Bibliothèque et l'original
  de la photo active) ;
- `--dump [<id>]` : tous les réglages bruts d'une photo, une clé par ligne, à comparer avec `diff`
  avant et après une opération faite à la main ;
- `--recalage <id>` : les écarts du recalage des positions sur la géométrie actuelle de la photo ;
- `--recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>]` :
  rejoue une séquence complète dans le vrai Lightroom, sur des copies virtuelles de la collection
  « Développeur › Essais » (des originaux seulement avec `--original`), vérifie chaque étape sur
  les réglages relus, puis remet chaque photo dans son état de départ, même après un échec ;
- `--version`.

## Organisation

- `Sources/DeveloppeurKit/` : le connecteur (protocole MCP, outils, invites, catalogue des
  réglages, mesures et Vision, liaison TCP avec le module)
- `Sources/MCPDeveloppeur/main.swift` : l'exécutable `mcp-developpeur` (options de ligne de
  commande, boucle stdio)
- `Lightroom/Developpeur.lrplugin/` : le module Lightroom Classic, en Lua 5.1 (liaison avec le
  connecteur, fenêtre Claude et `relais.sh` qui lance Claude Code, Publication, Consommation,
  fenêtre de suivi)
- `Tests/DeveloppeurKitTests/` : tests du connecteur, avec un faux Lightroom et un faux module TCP
- `Tests/Lua/Liaison/`, `Tests/Lua/Fenetre/` : tests du module, chacun sur son Lightroom simulé
- `scripts/` : `tester-module.sh` ; `metriques.swift` et `images-vides.swift`, qui produisent des
  fichiers de la fenêtre Claude (chasse des polices, images « aucun aperçu »)
- `Resources/Info.plist` : identifiant et numéro de version du connecteur
- `docs/` : captures, `SPEC.md` (cahier des charges, protocole entre le connecteur et le module,
  et la fenêtre Claude), `aide-adobe-developpement.md` (notes sur l'aide d'Adobe)
- `build.sh`, `install.sh`, `uninstall.sh` : construire, installer, désinstaller

## Licence

Sous licence MIT ([LICENSE](LICENSE)) : chacun peut utiliser, modifier et redistribuer le code, en
gardant l'avis de droit d'auteur.
