# Changements

## Non publié

### Ajouté
- Retouche générative par Fibo 2, sur votre demande seulement (outil `generative_edit`, le 36e) :
  ce que Lightroom ne sait pas faire, comme remplacer un pantalon par une jupe ou changer un objet,
  Claude le fait faire par Fibo 2 sur ce Mac (mflux, sans rien envoyer sur Internet). La photo
  développée part en TIFF 16 bits, Fibo 2 la modifie, seule la zone changée est reprise dans la
  photo en pleine résolution, et le résultat entre au catalogue en TIFF, empilé au-dessus de
  l'original, qui reste intact ; il devient la photo active, et Claude y fait les finitions.
  La zone changée peut rester un peu moins fine que le reste (Fibo 2 travaille à environ
  1 mégapixel). Il faut mflux
  (`uv tool install mflux`) et l'accès aux modèles Fibo 2 de Bria (licence CC BY-NC : usage
  personnel). `undo_last` ne retire pas la nouvelle photo : Photo › Retirer du catalogue, à la main.
  Les garde-fous des photos valent comme pour toute retouche (avec « Copies virtuelles seulement »,
  la nouvelle photo reçoit sa copie virtuelle, où se font les finitions) ; une photo d'essai va dans
  « Développeur › Essais », sans pile avec votre original ; le passage par un TIFF temporaire ne
  compte pas comme une exportation ; le TIFF garde toutes les métadonnées (libellé, mots-clés) en
  compression ZIP ; Fibo 2 s'arrête si Lightroom ou Claude se ferment pendant le calcul.
- Retouche générative, plus fine et plus complète :
  - Fibo 2 reçoit un recadrage autour de la zone à changer (avec une marge de contexte), plus
    seulement toute la photo réduite ; le reste de la photo garde ses pixels.
  - Jusqu'à 4 changements en un seul appel (« une jupe et un sac »), une zone chacun, recollés dans
    une seule nouvelle photo ; deux zones qui se chevauchent ou se touchent se font en deux fois.
  - SeedVR2 remet une zone rendue trop petite à sa taille, avec plus de détail (modèle de quelques
    Go téléchargé au premier usage), seulement pour une zone désignée et un agrandissement mesuré ;
    sans lui, mise à la taille ordinaire, et Claude le dit.
  - Décodage en pleine précision (hors qualité rapide) ; le mode rapide seulement sur demande.
  - Une seule barre de progression dans Lightroom, de 0 à 100 %, avec le changement en cours et le
    temps restant ; sa croix arrête tout sans rien importer, à tout moment.
  - La consigne part en anglais pour Fibo 2 ; Claude vous en montre la traduction française, gardée
    au journal de la photo.
  - Mémoire ménagée (après un premier essai qui a fait geler le Mac, Fibo 2 prenant 39 Go sur 48) :
    Fibo 2 et SeedVR2 tournent en mode économe (environ 21 Go pour Fibo 2, même image au pixel
    près). Claude ne refuse rien faute de mémoire libre : s'il en manque, le Mac se sert de son
    swap.
  - Le résultat ne se perd plus : si Lightroom ne peut pas l'importer, Claude réessaie une fois
    (seulement si Lightroom n'a pas reçu la demande, pour ne jamais l'importer deux fois), puis garde
    le TIFF dans « Fibo non importées » (dossier du Développeur) et vous dit où il est, à importer à
    la main ; si Lightroom a reçu la demande sans répondre, il vous dit de chercher d'abord la photo
    dans la pile de l'original. Si Lightroom ne répondait plus pendant le calcul, Claude le signale,
    même quand Fibo 2 échoue.
  - Un seul calcul de Fibo 2 à la fois sur le Mac : une autre session de Claude (Claude Desktop, la
    fenêtre Claude, le terminal) est refusée pendant ce temps, de même qu'un calcul en cours dans
    Fibo 2 Studio, deux calculs ensemble dépassant la mémoire.
  - Essai réel du 29 octobre 2026 (une tuque rouge à pompon sur un portrait de 26 mégapixels) :
    environ 8 minutes en qualité normale, SeedVR2 compris, raccord invisible à 100 %, sans que
    Lightroom cesse de répondre. Le mode qui montrait aussi la photo entière à Fibo 2 est retiré :
    à cet essai, Fibo 2 y a redessiné une seconde tête, plus petite, que la vérification
    d'alignement n'a pas vue ; le recadrage autour de la zone reste le seul chemin.

- Retouche générative d'après une autre photo (« mets le fond de cette photo-là ») : une photo de
  votre catalogue, ou une partie d'elle, sert de modèle de décor, de vêtement ou d'objet (argument
  `reference` de `generative_edit`). Il faut désigner la zone à changer (un rectangle ou un masque
  de Lightroom) : seule elle change, le reste garde ses pixels exacts. La photo de référence est
  seulement lue, jamais modifiée. Sans fiche de FIBO-vlm (il ne voit qu'une image). Un visage qui
  apparaît dans la zone, peut-être recopié de l'autre photo, est signalé à vérifier. À constater sur
  vos photos : Fibo 2 a déjà dessiné une seconde tête quand il recevait deux images.

- Retouche générative, cinq fonctions reprises de Fibo 2 Studio :
  - Par défaut (une trentaine de secondes et environ 16 Go en plus, dans un calcul à part fini avant Fibo 2), une fiche détaillée de chaque changement, rédigée sur le Mac par
    FIBO-vlm (le modèle de Bria qui décrit l'image, environ 8 Go) avant Fibo 2 : ce qui change, ce
    qui reste, la lumière, le décor ; Fibo 2 devrait mieux la suivre qu'une phrase (à constater).
    Elle est maintenant bien plus légère : environ 16 Go de mémoire et 35 à 60 s mesurés (une
    trentaine de secondes avec une zone, une minute sans), au lieu de 40 Go et 7 min (modèle en
    8 bits, mémoire de travail bornée, une seule rédaction, arrêtée dès que la fiche est complète
    avec une zone) ; active par défaut depuis son essai réel complet (fiche en 35 s, retouche en
    74 s en qualité rapide). Avec une zone,
    la fiche est celle de la zone grisée : FIBO-vlm n'y a plus buté lors des essais mesurés (deux
    graines) ; en cas d'échec, Fibo 2 reçoit la phrase seule, comme avant, et plus de fiche
    ordinaire de secours. Elle tourne seule avant Fibo 2 (jamais les deux en
    mémoire ensemble), s'arrête au bout de 3 min, et n'est jamais bloquante : sans le modèle, ou en
    cas d'échec, Fibo 2 reçoit la phrase seule et Claude le dit ; si mflux a changé de version
    depuis le réglage (0.24), Claude le signale. Claude vous en donne un court résumé.
  - Une liste de ce que Fibo 2 doit éviter (du texte ou un logo inventé, une personne ou une tête
    en double, des membres en trop, un corps déformé), à laquelle Claude peut ajouter ce que vous
    voulez éviter ; pas en qualité rapide (Turbo n'en tient pas compte). Elle remplace la
    description vide sur laquelle Fibo 2 a été entraîné pour se guider : elle en garde la forme, et
    son effet sur le rendu reste à mesurer.
  - Une qualité « équilibrée », la nouvelle qualité par défaut : environ le rendu de la qualité
    normale en deux fois moins de temps (30 étapes au lieu de 50) ; la normale et la rapide restent.
  - Un masque que vous peignez vous-même dans Lightroom (au pinceau ou avec tout autre outil du
    panneau Masquage) peut désigner la zone à changer : donnez-lui un nom (« Fibo ») et dites-le à
    Claude. Votre masque n'est ni changé ni retiré ; s'il manque, ou si deux masques portent ce
    nom, Claude vous le dit avec la liste des noms.
  - Le guidage (de 1 à 10, 5 par défaut) se règle sur demande : plus haut, Fibo 2 suit l'instruction
    de plus près.
  - Un calcul de Fibo 2 Studio lancé pendant le vôtre arrête le vôtre avant son étape suivante
    (fiche, Fibo 2 ou SeedVR2) : jamais deux calculs ensemble sur le Mac.
  - Provisoire : l'effet de la fiche, le rendu de la qualité
    équilibrée, l'effet de la liste à éviter et celui du guidage restent à constater sur vos photos.
    Un essai en qualité rapide ne vérifie que la fiche et le masque peint : la qualité équilibrée,
    la liste à éviter et le guidage demandent un essai en qualité équilibrée ou normale.

- Retouche générative : changer l'arrière-plan, le ciel ou une personne se fait avec un masque
  calculé par Lightroom (outil `generative_edit`, argument `mask`), plus avec un rectangle. Fibo 2
  reçoit le masque précis de ce qui doit changer (il gardait parfois des morceaux de l'ancien fond,
  un panneau ou une lettre, quand on ne lui donnait qu'un rectangle) ; seul le masque revient dans
  la photo, avec le bord doux du masque de Lightroom : les mèches fines des cheveux restent sur le
  nouveau fond, au lieu d'un contour découpé à l'allure de « photo collée » (un léger voile de
  l'ancien fond peut rester là où Lightroom lui-même hésite) ; le reste garde ses pixels exacts. Lightroom calcule le
  masque en pleine résolution sur deux rendus d'essai (un plus sombre, un plus clair : les noirs
  purs et les blancs brûlés du fond y sont aussi), après l'exportation de la photo (en « Proposer
  d'abord », l'accord se donne donc avant ces rendus) ; rien n'est gardé dans les réglages de la
  photo, mais quatre étapes « Claude · essai » restent dans son Historique. Un masque vide, qui
  couvre toute la photo, ou une personne que Lightroom n'a pas reconnue est refusé avant tout
  calcul de Fibo 2 ; les traits fins du masque (une mèche, le jour entre le bras et le corps) sont
  gardés. Les seuils (élargissement, bord doux, nettoyage, masque vide ou total) sont provisoires,
  à vérifier sur de vraies photos.
- La carte d'un masque (`add_mask` avec `mask_map`) ne demande plus d'accord dans Lightroom en
  « Proposer d'abord » : ce n'est qu'un rendu témoin, rien n'en est gardé (sa demande effaçait
  l'accord qu'attendait l'écriture des masques).

### Corrigé
- Fenêtre Suivi : un clic sur une barre montre de nouveau ses photos dans la Bibliothèque (il
  échouait, le Lua de Lightroom n'ayant pas une fonction que le module employait).
- Fenêtre Claude : une conversation ne prend plus pour titre un texte d'attente que Claude écrivait
  avant d'avoir vu la photo (« à définir après aperçu ») ; il donne son vrai titre à la vue suivante.

### Documentation
- Les captures du README sont refaites avec la 1.4 : la fenêtre Claude, la fenêtre Suivi en
  graphiques, la Demande rapide, Publication, Consommation et la fenêtre de la liaison.

## 1.4 — 2026-10-27

La 1.4, une sortie entière, du tri à l'harmonisation : un voyage ou une fête de famille, c'est des
centaines de photos, plusieurs lumières, parfois deux boîtiers. Claude les trie toutes d'un coup, puis
les harmonise groupe par groupe, chacun sur sa propre photo de référence : le musée, la plage et le
souper n'ont pas la même lumière, et une seule référence les rendait tous faux.

### Ajouté
- Harmoniser par lumière : demandez à Claude d'harmoniser une sortie (« harmonise ma sortie par
  lumière »). Il la partage d'abord en groupes de photos prises sous la même lumière : un groupe
  commence après une pause de plus de 10 minutes (sauf si la photo montre le même lieu, dans l'heure,
  comme après le repas), quand le flash s'allume ou s'éteint, ou quand la lumière de la scène change
  nettement (d'après l'ouverture, la vitesse, l'ISO et la compensation : le soleil et l'ombre d'un
  arbre, le dehors et le dedans). Deux boîtiers sur la même scène restent ensemble. Pour chaque
  groupe, il propose une photo de référence (une photo qu'il a déjà retouchée, sinon la mieux classée
  au tri, avec un visage s'il y en a), la retouche, puis harmonise les autres sur elle, une soixantaine
  à la fois. Rien ne change avant votre accord ; une photo seule sous sa lumière se retouche à part.
- Le témoin du teint : quand la photo de référence montre un visage, Claude compare la peau de chaque
  photo à la sienne, avant et après l'harmonisation, sur le visage pris à pleine taille dans l'aperçu
  qu'il mesure. Si la correction éloigne nettement la peau de celle de la référence, il vous le
  signale, à vérifier à l'œil : deux personnes n'ont pas la même peau, c'est un témoin, pas une règle.
  Sur une photo sans tons neutres (la balance y reste), il dit aussi quand la peau diffère.

### Changé
- Claude note plus sévèrement, à votre demande : toute l'échelle descend d'une étoile. Une photo
  gardée et correcte reçoit 1 ★ ; 2 ★ veut dire qu'elle tient seule devant quelqu'un qui ne connaît
  ni les gens ni le lieu (un bon souvenir bien fait n'y suffit plus) ; 3 ★, qu'elle a de l'impact ;
  4 ★, qu'elle tient à côté de vos meilleures photos. Le 5 ★ reste possible, pour l'exceptionnel :
  quelques photos par année au plus. Dans le doute entre deux notes, Claude prend la plus basse, et
  les plafonds du tri descendent aussi d'une étoile. Les notes déjà posées dans votre catalogue ne
  changent pas.
- Le tri d'une sortie entière : Claude trie jusqu'à 1 000 photos d'un coup (500 avant), et une sortie
  plus grande par tranches, sans que vous ayez à réduire la sélection ; les groupes de lumière
  prennent jusqu'à 2 000 photos d'un coup.
- Noter toute une sélection : « note la série » sur 951 photos ne notait que les 24 premières.
  Dans la fenêtre Claude et la Demande rapide, Claude reçoit maintenant le tri entier (il était
  trop long pour lui), puis note la sélection planche par planche, 30 photos à la fois, jusqu'à la
  dernière ; la planche contact prend une grande sélection dès la première planche. Au-delà de 100
  photos, le tri regroupe les plafonds de note par raison : sa réponse est trois fois plus courte
  (43 000 caractères au lieu de 147 000 pour ces 951 photos).
- Pendant que Claude travaille, la ligne d'état dit sur quelle photo de la sélection il en est
  (« Claude travaille · 3 outils faits · 11 s · photo 2 de 3 : XH2S8390.RAF »), ou quelles photos
  (« photos 31 à 60 de 951 »).
- Dans la fenêtre Suivi, la première tuile s'appelle « Photos analysées » (« Photos ouvertes »
  avant) : elle compte les photos déjà analysées de la période, et dit dessous combien il y en a en
  tout et ce qui reste (« sur 84 582 photos · 474 non analysées »). Le mot « ouvertes » quitte aussi
  les autres tuiles : « 25 % des photos ».

### À savoir
- Les seuils des groupes (10 minutes de pause, 2,5 IL de lumière, la ressemblance du même lieu) sont
  des premiers choix : l'essai de la 1.4, sur une vraie sortie d'au moins 500 photos, servira à les
  régler. Regardez les coupures que Claude propose, et dites-lui de rapprocher ou de séparer des
  groupes au besoin.
- Après l'installation : quitter puis relancer Lightroom (le module a un fichier nouveau), rouvrir
  Claude Desktop et ouvrir une nouvelle session de Claude Code.

Elle reprend aussi le correctif 1.3.8, construit le même jour et jamais publié seul : le Suivi qui
prend toute la bibliothèque sans figer Lightroom, les graphiques des notes et des genres de photos,
la période en deux dates gardées avec son calendrier, les boutons de l'en-tête sur la ligne du titre,
et l'historique d'une photo redit par le résumé.

### Changé
- Le Suivi peut prendre toute votre bibliothèque d'un coup : ouvrez Toutes les photographies,
  sélectionnez tout, puis ouvrez la fenêtre Claude ou la Demande rapide. Il accepte jusqu'à
  250 000 photos d'une même sélection (1 000 avant) et garde jusqu'à 250 000 originaux par catalogue
  (20 000 avant : au-delà, il oubliait les photos vues le moins récemment, analyses comprises). Vos
  88 071 photos y entrent, sauf les vidéos.
- Pour ne pas figer Lightroom pendant ce temps, le Suivi lit, range et écrit son relevé par petits
  morceaux et laisse Lightroom respirer entre deux, même avec toute la bibliothèque (mesuré hors de
  Lightroom sur des relevés de 85 000 et 250 000 photos ; à confirmer dans Lightroom avec la vôtre).
  Le relevé reste un seul fichier, `suivi.json`, écrit sans jamais être laissé à moitié ; plus il est
  grand, moins il s'écrit souvent, jusqu'à une minute entre deux écritures : si vous quittez
  Lightroom, la dernière minute de photos vues peut manquer au Suivi. La fenêtre Suivi s'ouvre tout de suite sur
  ce qu'elle sait, puis relit les notes et les drapeaux en arrière-plan et se redessine si l'un a
  changé. Un clic sur une barre de milliers de photos les montre aussi par morceaux, sans les
  ranger de nouveau au Suivi.
- Ce qui reste lent : l'analyse d'office. Elle se fait en arrière-plan, sur votre Mac, sans Claude ni
  forfait, à environ 3 photos par seconde : comptez à peu près 8 heures pour 85 000 photos. Elle
  s'arrête quand Claude travaille et reprend ensuite, et au lancement suivant de Lightroom si vous
  l'avez quitté. Une photo dont l'analyse a échoué (juste après une retouche, par exemple) se
  réessaie 10 minutes plus tard, sans attendre la fin de la file.
- La période de la fenêtre Suivi se choisit maintenant par deux dates, « Du » et « au », à la place
  du menu Période (3 derniers mois, 12 derniers mois, Tout), et se garde d'une ouverture à l'autre.
  Tapez une date comme vous l'écrivez : « 25 janvier 2025 », « 25/01/2025 », « 2025-01-25 », un
  mois ou une année seuls ; « au » accepte « aujourd'hui » (la fin avance alors chaque jour), et
  « Du » vide prend tout depuis la première photo. Sans période choisie : les douze derniers mois,
  jusqu'à aujourd'hui. Les graphiques du temps vont mois par mois jusqu'à treize mois (une année d'un
  25 janvier au suivant en touche treize), puis par trimestre, puis par année ; le premier mois et
  chaque janvier portent leur année, et l'infobulle d'un mois que la période ne couvre qu'en partie
  le dit (« janvier 2025, à partir du 25 »). Une date qui ne se lit pas, ou une période à l'envers,
  est refusée, et la ligne sous les champs dit lequel changer d'abord.
- Dans l'en-tête de la fenêtre Claude, Suivi, Publication… et Consommation… montent sur la ligne du
  titre, à droite de « Repartir à neuf », qui prend leur taille : quatre petits boutons côte à côte, en
  haut à droite. La photo active garde toute la ligne du dessous.
- « Historique de la photo » ne s'affiche plus en haut du fil : le résumé de la photo, juste dessous,
  dit déjà la même chose (de même pour le petit résumé d'une sélection de plusieurs photos). Claude le
  reçoit toujours avec votre première demande.

### Ajouté
- Un graphique des notes dans la fenêtre Suivi, à côté des objectifs : combien de photos à 0 ★ (pas
  encore notées) et de 1 à 5 ★ dans la période (la note la plus haute de la photo et de ses copies
  virtuelles). Un clic sur une barre montre ses photos dans la Bibliothèque ; une photo rejetée
  compte à sa note, et la note sous le graphique dit combien il y en a.
- Un graphique des genres de photos dans la fenêtre Suivi, sous « Ce que je photographie », en haut
  de la colonne de droite : portrait, famille et groupes, sport, paysage, macro et gros plans,
  animaux, ville et architecture, véhicules, nourriture, fêtes et événements, et autre. Le connecteur
  lit le genre de chaque photo sur sa vignette, avec Vision (Apple), pendant l'analyse d'office, sans
  Claude ni forfait. C'est une tendance, pas un classement sûr : Vision ne sait pas qui sont les
  personnes, « famille et groupes » veut dire deux personnes ou plus ; essayé sur 60 de vos photos,
  il en range 52 sur 53 comme à l'œil (la nourriture, le macro et les fêtes n'y étaient pas). Une
  photo faite à l'objectif macro (XF80 Macro), sans personne, compte en macro. Un clic sur une barre
  montre ses photos dans la Bibliothèque.
- Un calendrier pour choisir la période : un bouton à droite de « Du » et de « au » ouvre une petite
  fenêtre du mois, dans les couleurs du module ; ◀ ▶ ou les menus Mois et Année changent de mois, un
  clic sur un jour le choisit. « Première photo » (pour « Du ») et « Aujourd'hui » (pour « au », la
  fin qui avance) y sont aussi. Taper la date reste possible.

### À savoir
- Après l'installation : quitter puis relancer Lightroom (le module a un fichier nouveau).
- Les photos déjà analysées n'ont pas encore de genre : le Suivi les repasse toutes en arrière-plan,
  dès que la fenêtre Claude, la Demande rapide ou la fenêtre Suivi est ouverte, pour leur genre
  seulement (les défauts trouvés à leur première analyse restent). Comptez environ 10 heures pour
  85 000 photos ; le graphique des genres se remplit au fil de l'analyse, et sa note dit combien de
  photos ne sont pas encore classées.

## 1.3.7 — 2026-10-26

Le correctif 1.3.7, le Suivi en graphiques, décidé avec vous le 25 octobre 2026 : chaque photo que
vous ouvrez dans la fenêtre Claude ou la Demande rapide entre au Suivi et s'analyse d'office sur le
Mac, sans Claude ni forfait ; la fenêtre Suivi montre vos prises de vue et votre carnet de progrès
en graphiques ; Publication… et Consommation… reviennent dans l'en-tête de la fenêtre Claude, à
droite de Suivi.

Après l'installation : quitter puis relancer Lightroom (le module gagne trois fichiers depuis la
1.3.5 : un rechargement ne suffit pas), rouvrir Claude Desktop et ouvrir une nouvelle session de
Claude Code (le connecteur passe à 35 outils).

### Ajouté
- Le Suivi de vos photos : toute photo que vous ouvrez dans la fenêtre Claude ou la Demande rapide,
  seule ou dans une sélection (les 1 000 premières d'une sélection), y entre, à chaque ouverture de
  ces fenêtres et à chaque autre photo ou autre sélection. Une copie virtuelle compte pour son
  original, une seule fois (ni son ISO ni sa focale ne comptent deux fois) ; la note, le drapeau et
  « retouchée par Claude » sont ceux de l'original et de ses copies (la plus haute note, retenue si
  l'une l'est). Les vidéos et les photos de « Développeur › Essais » n'y entrent pas. Pas de
  rattrapage : le Suivi part de zéro à l'installation.
- L'analyse d'office de chaque photo ouverte, par le connecteur, sur la vignette de son original
  dans le cache de Lightroom, comme le tri d'une séance : sous-exposition, surexposition, ciel
  brûlé, flou, bruit (seulement à ISO 1 600 ou plus) et yeux fermés (seulement sur un visage dont
  les yeux se lisent). Elle se fait sur le Mac, sans Claude, sans forfait et sans réseau, en
  arrière-plan, par lots de 10 photos, la photo active d'abord ; elle attend pendant que Claude
  travaille (fenêtre Claude, Demande rapide, Claude Desktop) et reprend d'elle-même au lancement
  suivant de Lightroom. Une photo s'analyse une seule fois, telle qu'elle a été prise : une retouche
  ne la fait pas refaire (elle cacherait les défauts) ; sur une photo déjà retouchée par Claude,
  seuls le flou et les yeux fermés se cherchent. Une analyse manquée (une vignette illisible ou
  trop petite) se réessaie 10 minutes plus tard ; après trois essais, la photo reste sans analyse.
  Rien n'est écrit dans le catalogue, et rien de l'analyse ne part chez Anthropic. L'horizon penché et la mise au point manquée viennent toujours
  de ce que Claude mesure en regardant la photo (le carnet de progrès).
- Un clic sur une barre d'un graphique montre ses photos dans la Bibliothèque, en grille, sans rien
  changer (la source passe à Toutes les photographies quand la source affichée ne les a pas
  toutes) ; l'infobulle de la barre en dit le détail (« octobre 2026 · 42 photos »).
- Un nouveau défaut de la prise de vue, « Yeux fermés ou plissés » (17 au lieu de 16), que le Suivi
  compte d'après son analyse ; le carnet de `view_photo` ne le cherche pas.
- Publication… et Consommation… dans l'en-tête de la fenêtre Claude, à droite de Suivi : perdus
  avec le volet de gauche à l'essai de la 1.3.6, ils ouvrent leurs fenêtres comme avant, et restent
  aussi au menu Fichier › Module externe - Extras.
- Une photo, une conversation, dans la fenêtre Claude : choisir une seule photo dans Lightroom
  montre sa conversation, telle que vous l'avez laissée, et Claude reprend où il en était. Chaque
  copie virtuelle a la sienne. Une photo choisie fenêtre fermée compte aussi, à la réouverture.
- L'historique de la photo : une photo qui n'a pas encore de conversation en commence une, qui
  s'ouvre sur ses étapes de Claude (avec leur raison et leur date, qu'elles viennent de la fenêtre,
  de la Demande rapide ou de Claude Desktop) et sur ce que vous avez repris à la main depuis la
  dernière. Une photo sans étape de Claude y montre ses réglages qui s'écartent de leur valeur par
  défaut (par exemple « Profil Camera CLASSIC CHROME · Balance 5 600 K / +8 · Exposition +0,45 ·
  Ombres +30 · Recadrée · 2 masques », le profil sous le nom que Lightroom lui donne), que Claude
  reçoit aussi. Elle n'est gardée sur le disque qu'à
  votre première demande : parcourir des centaines de photos ne crée aucun fichier.
- « Depuis la dernière fois » : quand vous revenez à une photo qui a changé depuis que sa
  conversation l'a vue (une étape de Claude faite ailleurs, une reprise à la main), une ligne du fil
  dit ce qui a changé ; rien de changé, rien d'ajouté. L'historique et ce complément sont faits par
  la fenêtre, sans Claude ni forfait, et partent une seule fois avec votre demande suivante : Claude
  sait d'où il repart. (Lightroom ne laisse pas lire son panneau Historique : l'historique, c'est le
  journal de Claude et vos reprises à la main.)
- Plusieurs photos sélectionnées : une conversation de groupe, le temps du travail, jamais gardée,
  qui commence par un résumé court (« 3 de ces 12 photos ont déjà des étapes de Claude : … »).
  Changer de photo active dans la même sélection ne change pas de conversation ; ce que Claude y
  fait arrive dans le journal de chaque photo, que sa conversation lira ensuite.
- « Repartir à neuf », à droite du titre de la conversation : une conversation neuve pour la photo,
  avec son historique. L'ancienne reste sur le disque, mise de côté, jamais effacée. Grisé pendant
  que Claude travaille, sans photo seule, ou quand la conversation montrée n'est pas celle de la
  photo active.
- Le bouton Suivi, en haut à droite de l'en-tête de la fenêtre Claude : la fenêtre Suivi, à part,
  comme Publication et Consommation (à l'essai de la 1.3.6, le carnet de progrès en texte, page par
  page ; en graphiques depuis le correctif 1.3.7, plus haut).
- Trois boutons dans la Demande rapide, à gauche de la demande, chacun une demande toute faite pour toutes
  les photos sélectionnées : noter (Claude pose ses notes, de 0 à 5 ★ ou un rejet), Retouche pro
  et Portrait, comme les invites de la fenêtre Claude.
- Un résumé en haut du fil, fait par la fenêtre sans Claude ni forfait, à l'ouverture de la fenêtre
  et chaque fois qu'une autre photo ou une autre sélection change la conversation montrée : sous
  l'historique de la photo (ou le résumé court du groupe), au-dessus de votre première demande, en
  tête du fil sans historique ; « Depuis la dernière fois » reste à sa place, plus bas. Pour une
  photo : sa prise de vue (appareil, objectif, focale, ouverture, vitesse, ISO, date), sa note et
  son drapeau, et son état (ses étapes de Claude, vos reprises à la main, ses réglages hors de leur
  valeur par défaut). Pour plusieurs photos : leur nombre, leurs dates (du … au …), leurs appareils,
  et combien sont retouchées par Claude, notées, rejetées. Il reste à cette place (d'abord en bas du
  fil, déplacé à votre demande du même jour), se refait à la fin de chaque tour de Claude et suit la
  note posée ; le fil s'ouvre toujours sur son bas, la dernière réponse. Il n'est ni gardé dans la
  conversation, ni envoyé à Claude.

### Changé
- Le carnet de progrès se voit en graphiques dans la fenêtre Suivi (les défauts les plus fréquents,
  l'évolution d'un défaut), et non plus en texte, mois par mois : ce qui progresse et ce qu'il faut
  travailler à la prochaine sortie, demandez-le à Claude (« Comment progressent mes prises de
  vue ? »), qui lit toujours le carnet. Ses constats, sa case du Gestionnaire de modules externes
  et « Photos d'un défaut… » ne changent pas.
- La fenêtre Claude passe à 1 623 × 1 200 points (1 948 de large avant), sans le volet de gauche ;
  le fil garde sa largeur. Les deux voyants (Claude Code, Lightroom) sont dans l'en-tête. Sa barre
  de titre dit la version du module : « Développeur v1.3.7 » (la Demande rapide garde son titre).
  Les versions du module et du connecteur, et le mode de la liaison, sont dans l'infobulle du
  voyant Lightroom, qui passe à l'orange quand l'une des deux versions est à mettre à jour ou que
  le connecteur est introuvable. Publication… et Consommation…, qui étaient dans le volet, sont en
  haut à droite de l'en-tête, à côté de Suivi.
- Les onglets de droite sont, dans l'ordre, Focus, Note, Aperçu et Proposition. La fenêtre s'ouvre
  sur Focus et y revient chaque fois que vous choisissez une autre photo ; une proposition qui
  attend déjà garde son onglet sans reprendre la main.
- Un clic sur une étape de Claude dans le fil ouvre l'onglet Aperçu : son avant/après au-dessus, sa
  raison dans la carte (ce que faisait « Pourquoi ? »). Un clic sur une image du fil l'y montre
  aussi, avec le pourquoi de l'étape qui la précède ; l'image de la proposition qui attend votre
  accord s'ouvre dans l'onglet Proposition, et une photo jointe n'a pas de pourquoi.
- Les onglets suivent Claude d'eux-mêmes : chaque nouvelle image de Claude (un aperçu, une
  comparaison) ouvre l'onglet Aperçu, une proposition l'onglet Proposition, une note l'onglet Note.
- Agrandir montre l'image en 2 000 × 1 250 points (1 100 × 740 avant), l'avant et l'après côte à
  côte ensemble dans ce cadre ; une image plus petite est agrandie pour remplir la place (un peu
  plus douce, jamais minuscule). La photo active (onglet Focus, aperçu de la photo active) se
  redemande en grand à Lightroom au moment du clic ; juste après une retouche, quand Lightroom la
  refuse, un rendu de la photo la remplace (pendant que Claude travaille, dans la fenêtre ou par
  Claude Desktop : l'image du panneau, agrandie).
- Le mode (Appliquer directement, ou Proposer d'abord) se règle seulement dans le Gestionnaire de
  modules externes (section Liaison avec Claude, « Avant d'appliquer ») ; la fenêtre suit ce
  réglage.
- Le titre d'une conversation : le nom de la photo (ou « 12 photos » pour un groupe) jusqu'à celui
  que Claude donne ; il ne se renomme plus. Une conversation commencée par la Demande rapide reçoit
  son titre à la première demande faite dans la fenêtre Claude.
- La case Autre photo du Gestionnaire de modules externes devient « Reprendre sa conversation,
  sinon une nouvelle », et vaut aussi pour la Demande rapide. Décochée : la conversation montrée
  reste, quelle que soit la sélection, et chaque demande rapide part dans une conversation jamais
  gardée.
- Plus de proposition préparée à l'ouverture de la fenêtre Claude (votre décision du 25 octobre
  2026) : pour en avoir une, cliquez Obtenir, sous la carte de l'onglet Proposition. Claude propose
  alors une retouche de la photo active, dans sa conversation, sans rien appliquer (il la note
  d'abord si elle n'est pas encore évaluée), et la fenêtre passe à l'onglet Proposition, où vous
  l'acceptez, la refusez ou l'ajustez. Obtenir est grisé pendant que Claude travaille (fenêtre
  Claude ou Demande rapide), quand plusieurs photos ou aucune sont sélectionnées, et quand une
  proposition attend déjà. Sous la carte : Obtenir, Refuser, Ajuster… et Accepter.
- La Demande rapide sur une seule photo écrit dans la conversation de cette photo, la même que la
  fenêtre Claude, gardée sur le disque, et Claude y reprend sa session ; la fenêtre Claude y montre
  « Demande rapide » sous la demande. Sur plusieurs photos, elle part comme avant dans une
  conversation jamais gardée, avec le résumé court du groupe.
- Une demande tapée dans la Demande rapide vise toutes les photos sélectionnées, et non plus la
  seule photo active (sauf si elle en nomme une).
- Dans la Demande rapide, une autre photo ou une autre sélection efface la réponse, qui parlait
  d'autres photos ; ce que vous avez tapé reste. La conversation d'une photo, elle, reste gardée.
- À la fin d'une retouche dans la fenêtre Claude, Claude montre l'avant/après depuis l'état d'avant
  lui (`view_photo` avec `compare = before_claude`), puis fait son résumé chiffré, comme les invites
  de Claude Desktop ; pas dans une demande rapide.
- Le rendu reproductible se garde à cet avant/après de fin de retouche, au lieu de la leçon. Chaque
  photo garde la fin de chacune de ses retouches ; une retouche repartie de l'origine s'y compare à
  chaque avant/après de ce genre, même avant d'être finie, et un écart trop grand vous est dit à la
  fin de la retouche.
- Le menu « Afficher la fenêtre de suivi » devient « Afficher la fenêtre de la liaison » (le bouton
  du Gestionnaire de modules externes aussi) : le mot « Suivi » est maintenant celui de la fenêtre
  Suivi, vos prises de vue et votre carnet de progrès.
- Le carnet de progrès (`export_journal` avec `notebook`, fenêtre Suivi) ne montre plus que les
  constats ; les leçons déjà rangées restent dans `carnet.json`, telles quelles, sans être montrées.

### Corrigé
- La balance des blancs d'une photo à forte dominante (signalé le 24 octobre 2026 : un portrait à
  l'ombre des feuillus restait bleu après Retouche pro, réchauffé de 600 K seulement). `view_photo`
  dit maintenant la dominante de toute l'image (`dominante_globale`) et quoi en faire ; les tons
  presque neutres, qui ne gardent que les pixels déjà gris, la sous-estimaient. `white_balance_point`
  accepte `{scene: true}` : toute l'image, en deux passes mesurées, puis l'Auto de Lightroom, rendu
  et mesuré de même, gardé s'il laisse l'image plus neutre (sur ce portrait : 7 054 K et +31,
  gravier neutre, au lieu de 5 750 K et +16). Claude ne pose plus lui-même de chiffres pour une
  telle dominante (6 400 K et +14 laissaient encore le gravier bleu, quand l'Auto le rendait
  neutre). Le bilan ne prend plus cette correction pour une dominante accentuée : c'est un point
  « à vérifier ».

## 1.3.5 — 2026-10-23

Le correctif 1.3.5, fait à votre demande le 23 octobre 2026 au soir : huit chantiers tirés de la
feuille de route (trois de la 1.4, un de la 1.5 et les quatre de la 1.6, le style). Après
l'installation : quitter puis relancer Lightroom (le module change), rouvrir Claude Desktop et
ouvrir une nouvelle session de Claude Code.

### Ajouté
- La sauvegarde dite avant une série : `get_status` dit la dernière sauvegarde du catalogue (le
  dossier Backups de Lightroom, à côté du catalogue) et Time Machine (sa dernière sauvegarde, et si
  le volume du catalogue y est). Lues seulement : Claude ne règle rien.
- Préparer un tirage : `export_photos` avec `print` (format en centimètres, « 20x30 », « 30x45 »,
  résolution, papier mat ou brillant) donne le grand côté à la bonne résolution et la netteté de
  sortie du papier. Claude dit qu'un tirage sort plus sombre et plus doux que l'écran (les ombres
  un peu remontées sur une copie « tirage », si la photo le demande) et où choisir le profil du
  laboratoire.
- Ton style sur une photo neuve : le style « À ma façon » dans le menu Style de la fenêtre Claude,
  et l'invite `a_ma_facon` de Claude Desktop : ton guide de style appliqué d'abord, puis la méthode
  habituelle seulement pour ce qu'il ne dit pas.
- Rendu reproductible : à la fin d'une retouche, ses réglages principaux sont gardés ; la même
  photo retouchée de nouveau depuis l'origine s'y compare, et un écart trop grand se signale.
- Apprendre de tes corrections : `remember_style` avec `learn` lit tes reprises à la main sur une
  série (depuis la dernière retouche de Claude) ; une règle n'est proposée que si elle revient
  souvent et dans le même sens (« tu baisses la Correction du voile après Claude, sur 7 photos sur
  9 »), et elle n'entre au guide qu'avec ton accord.

### Changé
- Les styles de la fenêtre (Ambre et éclat, Or et peau douce, Or rose et éclat, Éclatant et peau
  douce, Neutre, Rose froid et peau douce) deviennent des recettes chiffrées, les mêmes à chaque
  photo, au lieu de mots réinterprétés à chaque demande. Ce sont des recettes de départ, à ajuster
  à votre goût.
- Les rafales par boîtier : le numéro de série du boîtier entre dans la description ; deux boîtiers
  sur la même scène (X-H2S et X-T4) ne forment plus une rafale.
- Les vidéos écartées : marquées dans la description, le tri, l'harmonisation d'une série et la
  livraison les sautent et disent combien.
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
