# Développeur

Développeur relie Claude à Lightroom Classic sur Mac : vous écrivez à Claude dans une fenêtre de
Lightroom (ou dans Claude Desktop ou Claude Code), et il regarde vos photos, les mesure et les
retouche avec la méthode d'un retoucheur professionnel, en vous disant ce qu'il change et pourquoi.
Il note aussi vos photos selon un standard clair : il propose une note, que vous acceptez ou
changez dans Lightroom, ou il la pose lui-même si vous le lui demandez. Pour vous faire
progresser, il dit pourquoi il fait chaque étape, finit par la leçon de la photo, vous laisse
faire la retouche vous-même avant de comparer, lit la composition et tient un carnet de progrès de
vos prises de vue. Il est fait pour le
photographe amateur qui veut des photos d'allure professionnelle sans être un pro. Deux pièces : le
connecteur MCP-Développeur, un serveur MCP (*Model Context Protocol*) écrit en Swift, et le module
« Développeur » de Lightroom Classic, qui exécute ses demandes et porte la fenêtre Claude.

![La fenêtre Claude dans Lightroom Classic](docs/capture.png)

## Fonctions

### La fenêtre Claude dans Lightroom

- Une fenêtre flottante de 1 497 × 1 200 points, « Développeur » dans sa barre de titre : Fichier ›
  Module externe - Extras › Ouvrir la fenêtre Claude (même entrée dans le menu Bibliothèque, et
  raccourci ⌃⌥C une fois posé). Elle reste ouverte pendant que vous travaillez, dans tous les
  modules de Lightroom, et laisse environ 1 940 points à Lightroom sur un écran de 3 440 × 1 440.
  Son allure est celle de la maquette « B · Conversation claire », agrandie à votre demande.
- Le modèle, l'effort, l'apparence et quatre cases se règlent dans Fichier › Gestionnaire de
  modules externes › Développeur, section Fenêtre Claude, et non dans la fenêtre :
  - Modèle : Fable (le plus capable), Opus (retouche fine, par défaut), Sonnet (courant) ou Haiku
    (rapide).
  - Effort : maximal (par défaut), très élevé, élevé, moyen ou faible, le même pour les quatre
    modèles. Plus d'effort, c'est une réponse plus soignée, mais plus lente et qui compte davantage
    dans le forfait. Un autre modèle ou un autre effort vaut pour la demande suivante, dans la même
    conversation.
  - Apparence : claire (par défaut) ou sombre, à l'ouverture suivante de la fenêtre. Elle règle les
    fonds, les textes et les images de la fenêtre ; les boutons, les champs et les menus suivent
    l'apparence de macOS.
  - Autre photo, cochée par défaut : une nouvelle conversation quand vous choisissez une autre photo
    ou une autre sélection (voir plus bas).
  - À l'ouverture, cochée par défaut : Claude prépare une proposition de retouche de la photo
    active, sans rien appliquer (voir plus bas).
  - Avant/après, cochée par défaut : l'avant/après de chaque étape de Claude, pour « Pourquoi ? »
    (voir Apprendre avec Claude).
  - Leçon, cochée par défaut : Claude finit chaque retouche par la leçon de la photo.
- Trois colonnes :
  - à gauche, le volet des conversations : « ＋ Nouvelle conversation », Rechercher, la liste ; en
    bas, Renommer… et Supprimer…, Publication… et Consommation…, les versions et le voyant Écran ;
  - au centre, l'en-tête (le titre de la conversation, le Mode, les voyants Claude Code et
    Lightroom, la photo active et le nombre de photos sélectionnées), le fil, ▲ ▼ Fin, puis la
    saisie : les invites, le champ de demande, 📎, 📋, « Style » et son menu, le bandeau des
    messages et Envoyer ;
  - à droite, les onglets Aperçu, Proposition, Note (par défaut) et Leçon, l'aperçu commun aux
    quatre (◀ légende ▶ et ⤢ Agrandir dessous), puis la carte de l'onglet choisi.
- Claude y travaille par Claude Code et votre forfait claude.ai, avec les seuls outils du
  connecteur : ni fichiers, ni terminal, ni web.
- Les conversations : la liste les range par jour (Aujourd'hui, Hier, puis par mois), chacune avec
  son heure ou sa date et son nombre de photos, 22 par page (« Plus anciennes… » au bout) ; la
  recherche cherche dans leurs titres et leurs messages, sans tenir compte des accents. Chacune est
  une session Claude Code, reprise telle quelle à la réouverture. Renommer, supprimer (à la
  corbeille du Finder ; les retouches faites dans Lightroom restent). Le Carnet de progrès est en
  tête de la liste (voir Apprendre avec Claude).
- Une nouvelle conversation pour une autre photo : quand vous choisissez une autre photo active ou
  une autre sélection, et que la conversation montrée a déjà des messages sur d'autres photos, la
  fenêtre en commence une nouvelle ; l'ancienne reste dans la liste. Une photo choisie pendant que
  la fenêtre est fermée compte aussi. Ce que Claude change lui-même (une photo qu'il montre, un
  tri), pendant son travail et dans les 4 secondes qui suivent, reste dans la conversation, même
  fenêtre fermée : rouverte, elle retrouve la conversation où Claude travaillait. Pendant un
  exercice « Je le fais », vous pouvez regarder d'autres photos sans changer de conversation. La
  case Autre photo du Gestionnaire de modules externes coupe ce comportement.
- Un titre tiré de ce que Claude voit sur la première photo (« Flamant rose au bord de l'eau »).
- Le fil, sur 42 lignes : chaque tour marqué « Vous » ou « Claude », avec son heure ; vos
  demandes, les réponses de Claude (titres et listes mis en forme), chaque appel d'outil sur une
  ligne, son nom en Menlo (✓ fait, ● en cours, ✕ erreur), et les notes de Claude (« Notes
  proposées · passe 2 · 14 photos », puis une ligne par photo, « à vérifier » quand Claude doute) ;
  quand vous lui avez demandé de les poser : « Notes à poser » pendant l'appel, puis « Notes
  posées » (« posée » sur chaque ligne), ou « Notes non posées » si aucune ne l'a été (liaison en
  pause, accord attendu : la raison est sur chaque ligne). Une étape de Claude porte un bouton
  « Pourquoi ? » ; le tour de Claude qui a noté ou donné une leçon finit par « ☆ Voir la note » ou
  « Leçon de la photo ». Un clic sur un outil montre ce que Claude a demandé au connecteur et sa
  réponse, un clic sur une image la montre dans l'aperçu, sans changer d'onglet. ▲, ▼ et Fin pour
  s'y déplacer ; à droite, ce que fait Claude, sinon le dernier relevé du forfait (5 heures et
  semaine).
- Les onglets de droite : Aperçu (l'étape choisie par « Pourquoi ? »), Proposition (la retouche que
  Claude propose, ou la liste de « Je le fais »), Note (la carte Note, montrée à l'ouverture) et
  Leçon. La fenêtre passe d'elle-même à l'onglet Proposition quand Claude propose une retouche
  (sauf la proposition préparée à l'ouverture), à l'onglet Note quand il propose une note pour la
  photo active, et une fois à l'onglet Leçon quand une leçon arrive (pas quand une proposition
  attend ni pendant un exercice) ; jamais à l'onglet Aperçu.
- L'aperçu, de 405 × 270 : à l'ouverture de la fenêtre (et quand le menu ou ⌃⌥C la rappelle, ou
  que vous choisissez une autre photo), la photo active, avec sa légende (son nom, son appareil et
  sa date de prise de vue) ; puis les images que Claude regarde et les photos jointes. ◀ ▶ pour les
  parcourir (▶ depuis la dernière revient à la photo active), Agrandir pour les voir en grand.
- Le carré de la mise au point sur la photo active, pour une photo Fujifilm (RAF, ou JPEG de
  l'appareil) : vert, rouge si l'appareil a signalé la mise au point manquée. Le connecteur lit le
  point dans l'original, sur ce Mac et en temps limité, et le dessine sur l'aperçu ; Agrandir le
  montre aussi. Pour une autre marque, l'original n'est pas ouvert et l'aperçu reste sans carré ;
  de même sans point lisible.
- Une proposition préparée à l'ouverture : quand la fenêtre s'ouvre, ou que le menu ou ⌃⌥C la
  rappelle, sur une conversation vide, Claude prépare une proposition de retouche de la photo
  active, rendu naturel. Choisir une autre photo, fenêtre ouverte, ne la lance pas : elle vient au
  rappel suivant, si la conversation est vide. Claude note d'abord la photo si elle n'est pas
  encore évaluée, puis montre ce qu'il changerait, sans rien appliquer. La proposition attend dans
  l'onglet Proposition, sans que la fenêtre y passe : Accepter, Refuser ou Ajuster… quand vous le
  voulez. C'est une demande comme une autre, dans le fil et dans le forfait ; la case À
  l'ouverture du Gestionnaire de modules externes la coupe.
- Claude reçoit avec chaque demande la photo active et la sélection de Lightroom.
- Le Mode, en tête : Appliquer (Claude applique ses retouches), Proposer d'abord (il montre d'abord
  ce qu'il compte changer et attend votre accord) ou Je le fais (vous faites la retouche vous-même,
  voir Apprendre avec Claude). Les trois boutons sont grisés pendant que Claude travaille.
- Sept invites en raccourcis : Retouche pro, Portrait, Paysage, Noir et blanc, ISO élevé,
  Composition, Sports. Portrait, Paysage et Noir et blanc passent en fin de retouche par éclaircir
  et assombrir comme un tireur (voir Retouches locales), avec l'avant/après de cette étape ; en
  noir et blanc, le grain vient après. Composition lit la composition de la photo active et propose
  un cadre, sans l'appliquer.
- Une carte Note, dans l'onglet Note : la note posée de la photo active, vos étoiles et vos
  drapeaux, et celle que Claude propose, à accepter, laisser ou changer sans repasser par Claude.
  Dans la fenêtre, Claude note d'abord chaque photo qu'il traite : pas de bouton pour le lui
  demander (voir Noter vos photos).
- Un style joint à chaque demande, invites comprises, par le menu « Style » sous le champ de
  demande : Standard (rien d'ajouté), Ambre et éclat, Or et peau douce, Or rose et éclat, Éclatant
  et peau douce, Neutre, Rose froid et peau douce. « Peau douce » passe par un masque de la peau à
  la dose « Adoucir la peau (Lite) », la moitié pour un homme ou une personne âgée, rien pour un
  enfant, jamais par un réglage de toute la photo.
- Joindre une photo du disque (📎 : JPEG, PNG, HEIC, TIFF, WebP) ou coller l'image du
  presse-papiers (📋 : capture d'écran, image copiée, photo copiée dans le Finder), comme exemple
  ou comme référence de style. Les photos jointes s'affichent dans le bandeau ; un clic les retire.
- Retour dans le champ, ou Envoyer (le bouton bleu), envoie la demande ; Arrêter, à sa place
  pendant que Claude travaille, l'interrompt proprement en pleine retouche.
- Des voyants : Claude Code (connecté au forfait ou non) et la liaison avec Lightroom (arrêtée ou
  en erreur, un clic la démarre ou la relance) dans l'en-tête, l'écran principal du Mac en bas du
  volet. Le bandeau, sur deux lignes à gauche d'Envoyer, montre un message de la fenêtre (son
  infobulle le donne en entier), sinon l'aide en rouge d'un voyant quand quelque chose manque (un
  clic l'affiche en entier), sinon les photos jointes ; sans rien de tout cela, il reste vide.
- Le voyant Écran, lu par le connecteur à l'ouverture de la fenêtre : « Écran · étalonné » (vert)
  pour un profil de couleur mesuré par une sonde ; « Écran · non étalonné » (orange) pour le profil
  d'usine de l'écran, un profil standard du système ou un profil fait à l'œil avec l'assistant
  d'Apple ; « Écran · étalonné ? » (gris) pour un profil personnalisé sans trace d'une sonde, ou
  illisible ; « Écran », gris, s'il n'a pas pu être lu. Un clic le relit (un autre écran a pu être
  branché) et donne le détail : le profil de couleur, et comment juger les couleurs (couper Night
  Shift, et True Tone sur un écran Apple ; une sonde d'étalonnage crée un profil mesuré). Claude
  mesure la photo par ses chiffres, sans passer par l'écran ; vous la jugez sur le vôtre : s'il
  n'est pas étalonné, Claude vous le dit une fois par conversation, quand il vous demande votre
  avis sur la peau ou les couleurs.
- En bas du volet, les versions du module et du connecteur, en orange si elles ne vont plus
  ensemble.
- Fermer la fenêtre n'arrête pas Claude : le travail continue et se retrouve à la réouverture.
  Claude Code reste ouvert entre deux demandes (réponses plus rapides) et se ferme après 15 minutes
  sans demande (5 minutes ou 1 heure au choix) ou quand Lightroom quitte.

### Apprendre avec Claude

Ce que la 1.3 ajoute pour progresser en photo, en regardant Claude travailler, puis en faisant
vous-même.

**« Pourquoi ? » sur chaque étape**

- Chaque étape de Claude dans le fil a un bouton « Pourquoi ? ». Il ouvre l'onglet Aperçu sur
  cette étape : « Étape 2 sur 4 », son but, la photo et l'outil, la raison que Claude a donnée (le
  défaut vu, puis ce que l'étape y fait), et les réglages changés. Si l'étape a été annulée ensuite
  (`undo_last`) ou défaite (retour à « Avant Claude »), la carte le dit.
- L'aperçu montre l'après de l'étape ; Voir l'avant et Voir l'après passent de l'un à l'autre,
  Agrandir les montre côte à côte en grand, ◀ ▶ passent d'une étape à l'autre de la même photo, et
  Détail… montre l'appel de l'outil et sa réponse.
- Les images se gardent pendant que Claude travaille, sur la photo active, fenêtre ouverte : un
  rendu de plus par étape (environ une seconde, pendant que Claude écrit son appel suivant), rien
  d'écrit dans le catalogue. Pas d'avant/après pour une étape faite fenêtre fermée (Claude Desktop
  seul), sur plusieurs photos ou sur une autre photo que la photo active, ni pour un classement ;
  la carte le dit. La case Avant/après du Gestionnaire de modules externes coupe ces rendus.

**La leçon de la photo**

- À la fin d'une retouche, Claude donne la leçon de la photo en trois points, Lumière, Couleur et
  Composition : ce qui manquait, chiffres à l'appui, et ce qui l'aurait évité à la prise de vue
  (ou, quand rien ne manquait, ce qu'il faut refaire). Un réglage du boîtier n'y est cité que s'il
  a été lu dans le fichier.
- Elle se lit dans l'onglet Leçon (la fenêtre y passe une fois à son arrivée), ou par « Leçon de la
  photo » à la fin du tour de Claude ; Détail… montre les faits que le connecteur a donnés à
  Claude : la prise de vue, ce que Claude a corrigé, et des indices (une exposition remontée d'un
  demi-IL ou plus dit une photo sous-exposée, par exemple).
- Une leçon par photo et par conversation, rangée dans le carnet de progrès ; pas de leçon après
  une proposition seulement montrée, une notation, un classement ou une série. La case Leçon du
  Gestionnaire de modules externes la coupe.

**« Je le fais »**

- Pour apprendre en faisant : le bouton Je le fais de la carte Proposition (ou le Mode « Je le
  fais ») demande à Claude sa retouche de la photo active, ou celle de la proposition qui attend,
  sous forme de liste. Rien n'est appliqué : Claude range sa version dans l'instantané « Claude ·
  ma version ».
- La liste, dans l'onglet Proposition, suit l'ordre et les noms des panneaux du module
  Développement de Lightroom Classic en français : « Réglages de base › Tonalité › Exposition :
  0 → +0,35 », puis Courbe des tonalités, Mélangeur de couleurs (le noir et blanc y est), Color
  Grading, Détail, Corrections de l'objectif, Transformation, l'outil Recadrage, Flou de
  l'objectif, Effets, Etalonnage. Faites les réglages dans Lightroom : chaque ligne se coche toute
  seule (○ devient ✓), toutes les 2 secondes, et la carte dit « À vous · 3 réglages faits sur 7 ».
  Vous pouvez regarder d'autres photos pendant l'exercice.
- J'ai fini (le même bouton) : Claude compare votre version à la sienne, côte à côte dans l'aperçu
  (« Claude | vous » ; Agrandir en grand), d'abord ce qui est comme lui, puis l'écart qui se voit
  le plus et le réglage qui l'explique, puis les autres écarts. Votre version reste sur la photo ;
  la sienne ne s'y pose que si vous le lui demandez, et Annuler la dernière retouche vous rend la
  vôtre.

**La composition**

- L'invite Composition, ou une demande (« lis la composition », « propose un cadre ») : Claude lit
  la composition sur l'image entière, même recadrée (horizon, tiers, sujet, vers où regardent les
  visages, espace devant le sujet), propose un cadre (horizon droit et sur un tiers, sujet sur un
  tiers avec de l'espace devant lui) et dit la règle en une phrase.
- La proposition montre l'image entière, le cadre en pointillés, les tiers et le hors-cadre
  assombri ; la carte dit « Cadre : 3:2 (format d'origine), redressé de 1,4°, 82 % de la largeur
  gardée ». Rien ne change avant Accepter. Ajuster… offre Plus serré, Plus large, Horizon au tiers
  haut, Format 4:5 et Seulement redresser.
- Claude ne recadre que sur demande ou si la composition y gagne nettement, et le dit.

**Le carnet de progrès**

- Les défauts de vos prises de vue, notés tout seuls : quand Claude regarde une photo qu'il n'a pas
  encore retouchée (sous-exposition, ciel brûlé, flou, mise au point manquée, bruit fort), et quand
  il mesure une ligne penchée de 0,5° ou plus sur une photo dont la géométrie est intacte, ni
  recadrage tourné, ni Upright, ni perspective (horizon penché).
  Ils sont comptés par mois de prise de vue ; une photo sans date compte au mois où Claude l'a vue.
- En tête de la liste des conversations, le Carnet de progrès : un tableau des six derniers mois
  (« 2/9 » : le défaut sur 2 des 9 photos où il a été cherché ; « — » : pas cherché), puis ce qui
  progresse ou recule (les deux derniers mois contre les trois d'avant, dès 15 points d'écart, avec
  au moins 5 photos de chaque côté), et à travailler à la prochaine sortie (un défaut sur au moins
  20 % des photos récentes et au moins 2 photos, trois au plus), avec ce qui aide à la prise de vue.
- Un clic sur une ligne ouvre ses photos, leurs constats et leurs leçons ; « Retirer du carnet… »
  en retire une, après confirmation. « Demander à Claude ce qu'il en pense › » ouvre une
  conversation où Claude le lit et répond en trois puces, sans rien retoucher.
- Seules vos vraies prises de vue comptent : les photos de « Développeur › Essais » n'y entrent
  pas. La case Carnet du Gestionnaire de modules externes (section Liaison avec Claude) arrête les
  constats ; les leçons s'y rangent encore (c'est la case Leçon qui les coupe, dans la fenêtre).
  Les seuils de la sous-exposition (moitié des tons sous L* 28 et 95 % sous L* 80, sauf une photo
  voulue sombre) et du ciel brûlé (plus de 3 % du tiers haut en blanc pur) sont provisoires : aucun
  vrai cas parmi les photos d'essai.

### Ce que Claude sait faire par le connecteur

Les mêmes 36 outils servent dans la fenêtre Claude, dans Claude Desktop et dans Claude Code. Neuf
invites prêtes à l'emploi s'y ajoutent, dans le menu « + » de Claude Desktop et parmi les commandes
« / » de Claude Code : `retouche_pro` (une photo, en deux passes vérifiées, puis au plus deux passes
correctives si un défaut reste), `harmoniser_serie`, `tri_seance`, `noter` (une sortie, selon le
standard de notation, passe par passe), `portrait`, `paysage`, `noir_et_blanc`, `nuit_iso_eleve` et
`partage` (écran, web, Instagram, impression), chacune avec ses précisions au choix (style, photos,
garder, passe, destination) ; celles qui retouchent suivent votre guide de style. `portrait`,
`paysage` et `noir_et_blanc` passent en fin de retouche par éclaircir et assombrir comme un tireur
(avant le grain en noir et blanc), avec un avant/après de cette étape. Les invites qui retouchent
(`retouche_pro`, `portrait`, `paysage`, `noir_et_blanc`, `nuit_iso_eleve`) partent de ce que
l'appareil Fujifilm a noté de la prise de vue, lisent le bilan de chaque passe et finissent par un
résumé chiffré, puis par la leçon de la photo ; `retouche_pro`, `portrait` et `nuit_iso_eleve`
traitent aussi un éclairage mixte ; `retouche_pro`, `portrait` et `paysage` lisent la composition
avant de proposer un cadre.

**Regarder et mesurer**

- Voir une photo telle qu'elle est développée en ce moment (aperçu rendu par Lightroom), avec ses
  données de prise de vue et des mesures : luminosité (L*, centiles), écrêtage des hautes lumières
  (aussi canal par canal) et des ombres, contraste, saturation, dominante des tons neutres,
  netteté par zone et bruit.
- Un bilan chiffré d'une passe à l'autre : à chaque nouvel aperçu entier d'une photo, Claude voit
  ce qui a bougé depuis le précédent à la même taille (exposition en IL, contraste, écrêtage,
  dominante, saturation, netteté, bruit), avant → après, et depuis le premier de la session. Une
  « régression » signale un défaut que la passe a créé ou aggravé (hautes lumières écrêtées, ombres
  bouchées, couleurs très saturées, dominante accentuée, netteté ou bruit qui passent leur seuil) :
  Claude la corrige par une passe ciblée ou défait la dernière étape, et vous le dit. Un changement
  peut-être voulu (une annulation, un calcul IA en attente, une dominante corrigée au-delà du
  neutre, des coins vides après Upright) n'est qu'« à vérifier ». L'avant/après côte à côte et les
  propositions ont leur propre bilan, sans netteté ni bruit pour une proposition ; un zoom refait
  sur la même zone, le sien, sans alerte (utile après un débruitage). Dans la fenêtre Claude et
  avec les invites qui retouchent, Claude reprend ces chiffres dans son résumé (« hautes lumières
  écrêtées : 2,1 → 0,3 % »). Le bilan ne compare que des images rendues de même (deux aperçus de
  même taille, ou les deux côtés d'un avant/après ou d'une proposition), jamais une proposition à
  un aperçu d'avant, et sa mémoire dure tant que le connecteur tourne (une session de Claude
  Desktop ou de Claude Code ; dans la fenêtre Claude, tant que Claude Code reste ouvert). Les
  seuils de l'écrêtage, des ombres, des couleurs saturées et de la dominante ont été relevés dans
  Lightroom le 20 octobre 2026, en propositions sur les photos d'essai ; ceux de la netteté et du
  bruit, provisoires, restent à relever.
- L'éclairage de la photo : la couleur de la lumière, lue sur les tons presque neutres, par zone
  tonale (ombres, tons moyens, hautes lumières) et par région (une grille de 3 × 3), les visages à
  part (leur peau, et la lumière autour d'eux). Quand deux lumières de couleurs différentes se
  mêlent (une lampe et une fenêtre dans la même pièce), Claude dit « éclairage mixte », à confirmer
  à l'œil (un mur coloré n'est pas une lumière) : il règle la balance des blancs sur la lumière des
  visages ou du sujet (une balance proposée, température et teinte), puis traite l'autre zone par
  un masque, ou la garde chaude si c'est une lampe. Relevé les 20 et 21 octobre 2026 sur les huit
  photos d'essai : à leur balance, seul le portrait à deux lumières (fenêtres et éclairage chaud)
  se lit mixte, comme à l'œil ; sous une forte dominante ajoutée exprès, la mesure peut perdre une
  lumière ou en inventer une.
- Ce que voit Vision d'Apple, sur ce Mac et sans réseau : visages et pupilles, qualité de chaque
  visage, vers où il regarde (de face, vers la gauche ou la droite de l'image), note esthétique,
  zone qui attire l'œil.
- Le point de mise au point des photos Fujifilm (RAF, ou JPEG de l'appareil), lu dans l'original
  par le connecteur, sur ce Mac : sa place dans l'image, la netteté autour, et si l'appareil a
  signalé la mise au point manquée. Pour noter, ou pour vous montrer la mise au point, Claude le
  fait dessiner sur l'aperçu entier ou sur un zoom : un carré vert, rouge si la mise au point est
  signalée manquée. Sur un zoom, Claude sait aussi si le point tombe dans la zone, et la netteté
  autour ; le carré n'y est dessiné que s'il y tombe. Jamais sur un avant/après. Pour le voir sur
  chaque aperçu et chaque zoom : case Mise au point du Gestionnaire de modules externes (décochée
  par défaut). Les mesures sont prises avant le carré. Dans la fenêtre Claude, l'aperçu de la
  photo active le montre aussi (voir plus haut).
- L'intention de la prise de vue des photos Fujifilm, lue dans l'original par le connecteur, sur ce
  Mac et de la même ouverture que le point de mise au point : la simulation de film, la plage
  dynamique (DR100, DR200, DR400, auto ou réglée) et sa priorité, les tons clairs et foncés, la
  couleur, la compensation et le mode d'exposition, la balance Auto (priorité au blanc ou à
  l'ambiance) et une scène de nuit, choisis sur l'appareil. Claude s'en sert sans rien poser
  d'office : pour un RAW, il part en première passe du profil Lightroom de la simulation choisie, et
  le dit (sauf autre style demandé ou guide de style contraire) ; sur un JPEG de l'appareil, il ne
  refait pas ce que l'appareil y a déjà mis ; une photo voulue plus sombre (compensation de −2/3 IL
  ou davantage, scène de nuit) reste sombre ; un RAW en DR200 ou DR400 qui paraît sous-exposé,
  c'est la protection des hautes lumières à la prise de vue : il remonte l'exposition en les
  gardant ; en « priorité à l'ambiance », la chaleur des lampes reste. Donnée avec l'aperçu entier,
  pas avec un zoom ni un avant/après.
- L'écran principal du Mac (`get_status`) : son nom, son profil de couleur et s'il est mesuré par
  une sonde, lus sur ce Mac sans réseau ni permission. Les mesures n'en dépendent pas, votre œil
  si : quand votre avis compte (peau, couleurs), Claude vous dit une fois que l'écran n'est pas
  étalonné, ou vous demande s'il l'est quand le profil ne le dit pas.
- L'évaluation que Claude garde pour la photo, donnée avec l'aperçu entier et avec un zoom (pas
  avec un avant/après) : pas encore évaluée, note proposée à vérifier, acceptée ou changée par vous
  (voir Noter vos photos).
- Zoom à 100 % sur une zone (netteté, bruit, poussières) ; avant/après côte à côte (avant la
  première retouche de Claude, ou avant la dernière).
- Mesurer au dixième de degré l'angle d'une ligne qui devrait être droite (horizon, bâtiment,
  poteau), pour redresser sans tâtonner. Sur un contour irrégulier (des rides dans le sable),
  la mesure le dit et ne se prétend pas affinée.
- Lire la composition (`read_composition`), sur l'image entière même quand la photo est recadrée :
  l'horizon (son inclinaison et sa hauteur), le sujet (donné par Claude, sinon les visages, sinon
  la zone qui attire l'œil, si elle ne couvre pas plus de la moitié de l'image), vers où il regarde
  et l'espace devant lui, les tiers ; puis un cadre proposé, dans le format d'origine ou celui
  demandé : horizon droit et sur un tiers, sujet sur un tiers avec de l'espace devant lui, les
  règles tenues et celles lâchées dites. Rien n'est appliqué : `preview_settings` avec ce cadre le
  montre sur l'image entière, en pointillés, les tiers tracés et le hors-cadre assombri (voir
  Apprendre avec Claude). Sur une photo recadrée, la lecture laisse deux étapes « Claude ·
  composition » dans l'Historique (le cadre retiré le temps du rendu, puis remis tel quel), et la
  proposition une étape « Claude · essai : image entière ».
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
- « Je le fais » : `preview_settings` avec `my_turn` range la retouche de Claude dans l'instantané
  « Claude · ma version », sans rien appliquer ni rendre, et donne la liste des réglages à faire,
  dans l'ordre des panneaux du module Développement (voir Apprendre avec Claude) ; quand vous avez
  fini, `view_photo` avec `compare = claude_version` montre les deux versions côte à côte, avec
  les écarts réglage par réglage et l'écart principal, ramené aux seuils du bilan. Vos changements
  pendant l'exercice ne sont pas des préférences à retenir dans le guide de style. Claude ne pose
  sa version (`choose_variant` « ma version ») que si vous le demandez ; `undo_last` vous rend la
  vôtre, et l'instantané s'efface quand vous le voulez.
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
  à droite »), ou la seule personne d'un portrait, repérée par Vision : Lightroom calcule le même
  masque qu'à la main.
- Masques combinés (« le ciel sans le bâtiment », « le sujet limité aux hautes lumières »), objet
  désigné par un cadre ou un trait, pinceau le long de traits (éclaircir et assombrir à la main),
  dégradés linéaires et radiaux, plages de luminance, de couleurs (prélevées dans l'image) et de
  profondeur (photos Portrait d'iPhone).
- Éclaircir et assombrir comme un tireur en chambre noire, pour mener l'œil au sujet, en une seule
  étape « Claude · éclaircir et assombrir » : les grandes zones trop claires assombries par un
  dégradé linéaire (−0,3 à −0,7 IL), le sujet ou le visage éclairci par un dégradé radial (+0,2 à
  +0,4 IL), les bords assombris par un radial inversé (−0,3 IL, −0,5 au plus) à la place du
  vignetage après recadrage, jamais les deux. Ces doses sont des plafonds. Puis l'avant/après de
  cette seule étape : s'il montre un halo autour du sujet, une bande au bout d'un dégradé ou des
  coins en plaques, Claude défait l'étape et la reprend plus légère. Les invites `portrait`,
  `paysage` et `noir_et_blanc` (et leurs boutons dans la fenêtre Claude) y passent en fin de
  retouche (en noir et blanc, avant le grain) ; `retouche_pro` y passe si la photo le demande, et
  vous pouvez le demander sur toute photo.
- Réglages locaux, courbe du masque, couleur ponctuelle dans un seul masque, et les effets du
  panneau Masque (Blanchiment des dents, Renforcement de l'iris, Adoucir la peau (Lite), Adoucir la
  peau, et les vôtres), avec « Peau du visage lisse », que le connecteur ajoute d'après les
  paramètres prédéfinis Portrait adaptatifs d'Adobe ; posés sur la bonne partie et réglables en
  intensité.
- La peau dosée comme Adobe, d'après les fichiers de Lightroom Classic 15.6 : « Peau du visage
  lisse » par défaut (texture −20, clarté −10), « Adoucir la peau (Lite) » pour un gros plan aux
  pores marqués (texture −35, clarté −15), la moitié de la dose pour un homme ou une personne
  âgée, rien pour un enfant ; un masque par personne quand les doses diffèrent. Vision ne dit ni
  l'âge ni le genre d'un visage : Claude en juge à l'œil et, dans le doute, prend la dose la plus
  faible ; puis il vérifie par un zoom sur le visage (pores encore visibles, ni cire ni plaques).
  Plus lisse (« Adoucir la peau », ou au-delà de la dose Lite) seulement si vous le demandez, ou si
  votre guide de style le dit : sinon le connecteur refuse ce masque de la peau (visage ou corps)
  sans rien envoyer à Lightroom. La moitié de la dose est exacte : l'intensité d'un masque est
  linéaire (constaté dans Lightroom le 20 octobre 2026 sur un portrait d'essai : texture −20 et
  clarté −10, la dose « Peau du visage lisse », à l'intensité 50 rendent la même image, au pixel
  près, que texture −10 et clarté −5 à 100).
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
  (au point de mise au point lu dans les RAW et JPEG Fujifilm), yeux fermés ou plissés, photos
  presque noires ou brûlées, rafales et piles de Lightroom avec la meilleure de chacune, et un ordre
  de lecture (netteté et note esthétique ; la qualité des visages ne départage que les photos d'une
  même rafale ou pile).
- Le tri ne propose pas d'étoiles : il donne à chaque photo un plafond de note mesuré, le plancher
  technique du standard de notation (voir Noter vos photos). Floue, mise au point manquée ou yeux
  fermés : rejet proposé. La mise au point ne se juge que sur une zone qui a du détail : posée sur
  du sable lisse ou un ciel uni, elle est « non jugée » ; sur une texture faible (le bord d'un
  nuage), une mise au point manquée n'est qu'un doute, 2 ★ au plus, à vérifier par un zoom à
  100 %, sans rejet proposé. Douce, ou mise au point signalée manquée par l'appareil : 3 ★ au plus.
  Presque noire ou brûlée : 2 ★ au plus et « à vérifier », sans rejet proposé, car la retouche la
  rattrape souvent (surtout en RAW). Capture d'écran ou document : 1 ★. Pas la meilleure de sa
  rafale ou de sa pile : 3 ★. Bruit fort : à noter après le débruitage. Sans défaut mesuré : 4 ★
  au plus.
- Claude propose les rejets et des mots-clés (ceux de Vision, traduits en français), et ne les pose
  qu'après votre accord ; une photo que vous avez déjà notée ou marquée d'un drapeau n'est pas
  touchée.
- Planche contact : jusqu'à trente vignettes numérotées en une seule image, pour voir une série
  d'un coup d'œil ; d'une planche à l'autre, les numéros continuent.
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

**Noter**

- Noter des photos selon le standard de notation (`propose_ratings`) : de 0 à 4 ★, ou le rejet,
  avec la raison critère par critère (impact, qualités, plancher technique, finition) et une
  phrase. Sans autre demande, rien ne change sur les photos : chaque proposition arrive « à
  vérifier » dans la carte Note, où vous l'acceptez ou la changez. Une nouvelle proposition pour
  une photo remplace la précédente.
- Quand vous écrivez à Claude « note ces photos » ou « pose les notes », il pose aussi les notes
  dans Lightroom, « à vérifier » comprises : une étape « Claude · notation » par photo, qui
  s'annule comme un classement. Votre demande vaut accord, même en mode « Proposer d'abord » (avec
  « l'accord se donne ici », il attend encore le bouton Accepter de la fenêtre de suivi) ; la
  pause de la liaison l'arrête, et les photos protégées restent protégées.
- Jamais 5 ★ de lui-même : vous les posez, ou vous les lui demandez. Une note au-dessus du plafond
  mesuré au tri est refusée, sauf un défaut voulu et maîtrisé, que Claude nomme et vous laisse « à
  vérifier ».
- L'invite `noter` : une sortie notée passe par passe (le tri, des planches de 24 à 30 vignettes,
  les candidates à 4 ★ regardées à 100 %, puis les propositions). Sans précision, elle note la
  sélection.

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
  couleur »), précédée la première fois d'un instantané « Avant Claude ». Claude donne à chacune
  sa raison, en une phrase simple (le défaut vu, puis ce que l'étape y fait). Le journal des
  retouches, photo par photo, garde ces raisons et s'exporte en Markdown (`export_journal`,
  « Journal et carnet de progrès »).
- La leçon de la photo (`photo_lesson`), en fin de retouche : trois points (lumière, couleur,
  composition), chacun avec ce qui manquait et ce qui l'aurait évité à la prise de vue, et les
  défauts qu'il nomme. Le connecteur vérifie les trois points avant de rien ranger, et donne à
  Claude les faits mesurés : la prise de vue (compensation, flash, mode et mesure d'exposition),
  ses propres corrections, d'après son journal, et des indices (exposition corrigée d'un demi-IL
  ou plus, hautes lumières baissées sur une photo écrêtée, horizon redressé, cadre resserré…).
  Avec `read_facts`, les faits seuls, sans rien ranger. Les seuils de ces indices sont
  provisoires ; une photo remise à la main hors de Claude (Historique, ⌘Z) garde au journal des
  corrections qui n'y sont plus, et donc de faux indices.
- Le carnet de progrès (`export_journal` avec `notebook`) : le résumé du catalogue entier en
  Markdown, mois par mois, ce qui progresse et quoi travailler à la prochaine sortie (voir Apprendre
  avec Claude). Il se remplit tout seul quand Claude regarde une photo pas encore retouchée
  (`view_photo`) ou mesure une ligne penchée (`measure_angle`, `read_composition`), dans Claude
  Desktop, Claude Code et la fenêtre Claude ; les essais du connecteur en ligne de commande n'y
  notent rien.
- Annuler la dernière retouche de Claude, ou revenir à l'état d'avant Claude : seulement ce qu'il a
  changé, vos retouches faites à la main restent.
- Champ « Retouchée par Claude » dans les métadonnées, pour filtrer ces photos dans la Bibliothèque.

### Noter vos photos

Claude propose, vous décidez : chaque note proposée arrive « à vérifier » dans Lightroom, et
l'accepter ou la changer ne repasse pas par Claude, donc ne dépense rien de votre forfait. Si vous
lui demandez de noter (« note ces photos », « pose les notes »), il pose les notes lui-même, et
vous les reprenez au besoin dans la carte Note.

Dans la fenêtre Claude, il n'y a pas de bouton pour demander une note. Toute photo que Claude
traite, il la note d'abord, avant d'y toucher : il la trie seule (son plancher technique), la
regarde avec le carré de la mise au point (photos Fujifilm), puis propose sa note, sans la poser.
Une photo déjà évaluée ne se renote pas, sauf si vous le demandez. Claude lit son évaluation avec
l'aperçu (« pas encore évaluée », « 3 ★ proposée par Claude, à vérifier », « acceptée par
l'utilisateur : 3 ★ », « changée par l'utilisateur : … ») ; elle est gardée sur le Mac, dans
`~/Library/Application Support/Developpeur/notation.json`, propre au catalogue ouvert (les 2 000
propositions les plus récentes). Le catalogue n'en garde que les notes posées.

**Le standard de notation**

Une étoile dit un niveau de qualité, et rien d'autre, avec le même sens d'une sortie à l'autre.
Rejeter, c'est le drapeau Rejeter ; les doublons d'une rafale vont dans une pile sous la meilleure
vue ; la valeur affective, dans un mot-clé ou une collection. 0 ★ veut dire « pas encore jugée »,
jamais « mauvaise ».

- Rejet (drapeau) : un défaut majeur, involontaire, confirmé à l'œil. La seule photo de sa scène
  reçoit plutôt 1 ★, à vérifier.
- 1 ★ : gardée, mais pas au niveau du 2 ★.
- 2 ★ : correcte, sans défaut visible à la taille d'usage (écran, album) ; elle a besoin de l'album
  ou du récit pour exister.
- 3 ★ : elle tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu.
- 4 ★ : une 3 ★ qui a de l'impact : vue en premier sur une planche de 20 à 30 vignettes, nette à
  100 % sur le sujet, meilleure vue de son moment. Souvent 5 à 10 % d'une sortie, sans proportion
  imposée : une sortie faible peut n'en avoir aucune.
- 5 ★ : elle tient à côté de vos meilleures photos, toutes sorties confondues, développement fini.
  Vous seul en décidez : Claude ne propose jamais 5 ★, et ne les pose qu'à votre demande.

Les critères, du plus lourd au plus léger : l'impact (la photo arrête l'œil ; aucune mesure ne le
voit), les qualités de l'image (lumière, sujet clair, composition, moment, couleur), le plancher
technique (netteté, exposition, yeux, bruit, mesurés au tri : il plafonne la note sans la donner)
et, pour le 5 ★ seulement, la finition (halos aux bords des masques, peau plastique, saturation).
Un défaut visible à la taille d'usage plafonne la note à 2 ★, un défaut visible seulement à 100 %
à 3 ★ ; un défaut voulu et maîtrisé ne compte pas, ni l'effort de la prise de vue, ni la valeur
affective. Une sortie se note en quatre passes, une question chacune : rejeter ou non ; 3 ★ ou
non ; parmi les 3 ★, monter à 4 ; 5 ★, après le développement, vous seul.

Le standard entier (selon le genre, ce que valent les mesures, les photos étalons d'une collection
« Développeur › Étalons ») : la ressource `developpeur://notation` du connecteur, reprise aussi à la
fin de l'invite `noter`.

**La carte Note**

- Dans l'onglet Note de la fenêtre Claude, sous l'aperçu, pour la photo active :
  - Passes : les quatre passes du standard (Rejeter ?, 3 ★ ou non ?, Monter à 4 ?, 5 ★ ? (vous)),
    la passe de Claude en gras, celles d'avant cochées ;
  - Votre note : cinq étoiles cliquables, la note posée dans Lightroom et son sens (« Correcte »,
    « Tient seule »…) ; un clic pose la note, un clic sur la note posée la retire ;
  - Drapeau : « ⚑ Retenir » et « ⊗ Rejeter » posent le drapeau (un second clic le retire) ;
    « ? À vérifier » est posé, grisé, sans action ;
  - Claude propose : sa note en petites étoiles, « rejeter », ou « rien pour l'instant » ; puis
    ses critères en grille, du plus lourd au plus léger (Impact, Qualités, Plancher technique,
    Finition), l'état de sa proposition en couleur (rouge : à vérifier ; vert : acceptée ou
    changée ; gris : écartée), et sa raison ;
  - le plafond mesuré au tri (« Plafond 3 ★ : mesuré au tri, pas plus »), avec « Voir à 100 % »,
    qui montre dans l'aperçu le zoom que Claude a pris pour noter la photo (Agrandir : en grand) ;
    grisé quand il n'en a pas pris.
- En bas, ▲ ▼ font défiler, page par page, des critères plus longs que la carte ; puis Laisser à
  N ★ (garder la note du catalogue et écarter la proposition : rien n'est écrit dans Lightroom),
  Changer… (une autre note, de 0 à 5 ★, et au besoin un drapeau : sans drapeau, retenue, rejetée)
  et Accepter N ★, en bleu (la note proposée posée dans Lightroom ; le drapeau Rejeter pour un
  rejet, « Accepter le rejet » ; votre drapeau Retenue reste). Jamais « Accepter 5 ★ » : Claude
  ne les propose pas, vous les posez par les étoiles ou Changer….
- Les étoiles, les drapeaux, Laisser, Changer… et Accepter attendent que Claude ait fini de
  travailler, sans Claude ni forfait. Le clic vaut accord, même en mode « Proposer d'abord » ; les
  photos protégées du Gestionnaire de modules externes restent protégées. Une note posée s'annule
  comme un classement (Annuler la dernière retouche, ou ⌘Z) ; annulée, sa proposition redevient
  « à vérifier ». C'est votre note : revenir à « Avant Claude » la laisse en place.

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
  explicite (20 par défaut) ; le point de mise au point (Fujifilm) dessiné sur chaque aperçu et
  chaque zoom, et non seulement pour noter (décoché par défaut) ; le carnet de progrès (case
  Carnet, cochée par défaut) ; un diagnostic à coller dans la conversation (avec les cases de la
  1.3 et le nombre de photos du carnet) et le journal. Une retouche refusée dit pourquoi.
- La liaison fermée par un jeton privé (voir Vos photos) : une commande qui ne porte pas le jeton
  de la liaison est refusée sans rien faire. Le diagnostic du Gestionnaire de modules externes dit
  si le jeton est là et combien de commandes ont été refusées, jamais sa valeur.

![La fenêtre de suivi de la liaison](docs/suivi.png)

### « Proposer d'abord »

- Dans ce mode (Gestionnaire de modules externes, ou le Mode « Proposer d'abord » en tête de la
  fenêtre Claude), Claude montre le rendu de ce qu'il propose, côte à côte avec l'état actuel et
  avec le bilan chiffré de l'un à l'autre (une régression se corrige dans la proposition avant de
  vous la soumettre), ou décrit le changement, puis attend votre accord. Le module refuse toute
  écriture que Claude ne présente pas comme approuvée (retouche, masque, tache, classement,
  collection, exportation), et Claude ne le fait qu'après votre « oui ».
- Dans la fenêtre Claude, la proposition s'affiche (réglages avant → après) dans l'onglet
  Proposition, avec Accepter (en bleu), Refuser, Ajuster… et Je le fais : Ajuster…, c'est un texte
  libre, ou un ajustement d'un clic (Moins chaud, Peau plus naturelle, Garder le ciel, Plus de
  contraste ; pour un cadre : Plus serré, Plus large, Horizon au tiers haut, Format 4:5, Seulement
  redresser) ; Je le fais vous laisse faire vous-même ce que Claude propose (voir Apprendre avec
  Claude). ▲ ▼ font défiler une proposition plus longue que sa place.
- Pour que l'accord ne vienne que de vous : la case « l'accord se donne ici » du Gestionnaire de
  modules externes. Seul le bouton Accepter de la fenêtre de suivi compte alors, pour une seule
  écriture, dans les 10 minutes.

## Vos photos

Ce que Claude regarde part chez Anthropic, qui fait tourner Claude. Le reste ne quitte pas le Mac.

Ce qui part chez Anthropic quand Claude regarde ou classe :

- les aperçus JPEG que Lightroom rend pour lui (1344 px de grand côté par défaut, 2048 au plus), y
  compris les avant/après, les propositions, les variantes, l'image entière d'une photo recadrée
  (composition) et la comparaison de « Je le fais » ;
- les zooms à 100 % : un extrait de la photo en pleine résolution, 1600 px au plus ;
- les planches contact (jusqu'à trente vignettes) ;
- les photos que vous joignez ou collez dans la fenêtre Claude (réduites à 1568 px) ;
- la description des photos : nom du fichier, appareil, objectif, réglages de prise de vue, date,
  dimensions, note, drapeau, libellé, réglages de développement ;
- pour une photo Fujifilm, l'intention de la prise de vue que le connecteur lit dans l'original
  (simulation de film, plage dynamique, tons, compensation, mode, balance), sans l'original ;
- le nom de vos écrans et de leur profil de couleur, et comment ce profil a été fait (d'usine,
  standard, à l'œil, par une sonde, personnalisé ; le logiciel et la date du profil s'ils sont lus),
  dans `get_status` ou dans une remarque au premier aperçu d'une session du connecteur : jamais le
  chemin du profil ;
- les métadonnées que Claude lit ou pose : titre, légende, mots-clés, droits d'auteur, champs IPTC,
  position GPS, noms des collections, et le chemin d'un dossier quand il en a besoin (recherche,
  livraison, original introuvable) ;
- les chiffres des mesures et de Vision (luminosité, netteté, éclairage, bilan d'une passe à
  l'autre, visages, mots-clés), la place du point de mise au point, l'évaluation que Claude garde
  pour la photo, les faits de la leçon de la photo, le résumé du carnet de progrès quand Claude le
  lit (`export_journal` avec `notebook` : jamais ses lignes photo par photo), et bien sûr vos
  messages.

Ce qui reste sur le Mac :

- le catalogue et les originaux : Claude ne reçoit jamais un fichier original ;
- le calcul des mesures et l'analyse de Vision, faits sur le Mac, sans réseau ; la lecture de
  l'original pour le point de mise au point et l'intention de la prise de vue (seul ce qui en est
  lu part, jamais l'original) ; la lecture de l'écran, sans réseau ni permission ; le tri lit les
  vignettes du cache de Lightroom sur le Mac et n'en envoie que les résultats ;
- le jeton privé de la liaison (`liaison.jeton`), qui ne part jamais chez Claude ni dans un
  journal ;
- les fichiers exportés, et toute la fenêtre Publication, qui ne parle jamais à Claude ;
- les conversations de la fenêtre Claude (avec les images que Claude a regardées), le guide de
  style, les profils de publication, le registre de consommation, les notes proposées avec
  l'évaluation de chaque photo (`notation.json`), le carnet de progrès et les leçons des photos
  (`carnet.json` : une table par catalogue, une entrée par photo originale, 3 000 au plus par
  catalogue, les plus anciennes sortent au-delà), et l'avant/après des étapes de Claude
  (`Etapes/`, une image avant et une après par étape, de 0,6 à 0,9 Mo ; ménage au chargement du
  module : 30 jours, 500 Mo au plus), dans `~/Library/Application Support/Developpeur/` ; les
  journaux dans `~/Library/Logs/Developpeur/`. Les images de `Etapes/` ne partent jamais chez
  Claude. Claude Code garde aussi ses propres sessions dans `~/.claude`.

Le module et le connecteur se parlent par deux ports de cet ordinateur seulement (54770 et 54771,
adresse 127.0.0.1). Le connecteur n'appelle jamais Anthropic lui-même ; la seule question qu'il
pose au réseau est celle de `--status` à GitHub, par `gh`, sur la dernière version publiée.

Depuis la 1.2, cette liaison est fermée par un jeton privé. À chaque démarrage de la liaison, le
module en tire un au hasard et le range dans
`~/Library/Application Support/Developpeur/liaison.jeton`, lisible par vous seul ; le connecteur le
relit à chaque connexion et le joint à chaque commande. Une commande sans ce jeton, ou avec un
autre, venue d'un autre programme du Mac ou d'une page web, est refusée sans rien faire et notée au
journal : elle ne peut ni regarder, ni retoucher, ni passer outre la pause ou « Proposer
d'abord ». Le jeton protège de ce qui ne peut pas lire vos fichiers ; un programme qui tourne sous
votre compte, lui, le pourrait. Un connecteur d'avant la 1.2 resté ouvert est refusé de même (voir
En cas de problème).

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
consommation, notes proposées, carnet de progrès, avant/après des étapes, journaux. Le catalogue
et les photos ne sont jamais touchés.

Ensuite :

- quitter et relancer Lightroom Classic : le module se charge et démarre la liaison (recharger le
  module ne suffit pas quand une version lui ajoute des fichiers, comme la 1.3) ;
- ouvrir Claude Desktop : le connecteur `MCP-Developpeur` apparaît dans ses outils ;
- dans Claude Code, ouvrir une nouvelle session (`/clear` ne relance pas le connecteur) ; depuis la
  1.2, la liaison refuse un connecteur plus ancien resté ouvert (voir En cas de problème) ;
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

Le connecteur ne demande pas l'Accessibilité ni aucune autre permission particulière (l'écran se
lit sans permission) ; seul macOS peut demander une fois l'accès au disque de vos photos (voir En
cas de problème). Pour vérifier l'installation, Lightroom ouvert :

```bash
"$HOME/Library/Application Support/Developpeur/mcp-developpeur" --status
```

Il dit la version (et s'il en existe une plus récente), les inscriptions, le module, l'état du
jeton de la liaison (présent et lisible par vous seul, absent ou illisible ; jamais sa valeur),
l'écran principal et son profil (même Lightroom fermé), puis la liaison.

Pour désinstaller : `bash uninstall.sh` (dans le dossier décompressé, ou depuis le dépôt),
Claude Desktop fermé comme pour l'installation (sinon, le script dit quoi vérifier). Il
retire l'inscription dans Claude, le connecteur, le module, ses paramètres prédéfinis invisibles
(Lightroom fermé) et ses fichiers de travail, dont le jeton de la liaison (un Lightroom ouvert le
réécrit : relancer le script après l'avoir quitté), et garde votre guide de style, vos
conversations, vos profils de publication, le registre de consommation, les notes proposées, le
carnet de progrès et ses leçons (`carnet.json`), l'avant/après des étapes (`Etapes/`) et les
journaux ; `bash uninstall.sh --tout` les retire aussi. Les retouches déjà faites restent dans le
catalogue (elles s'annulent dans le panneau Historique).

### Premiers pas

Lightroom ouvert, une photo sélectionnée, demandez à Claude par exemple : « Retouche la photo
active, rendu naturel et un peu chaud », « Passe-la en CLASSIC CHROME et redresse l'horizon »,
« Assombris le ciel sans toucher au bâtiment », « Éclaircis et assombris pour mener l'œil au
visage », « Efface les poussières du capteur », « Débruite cette photo de nuit », « Montre-moi
d'abord ce que tu proposes », « Montre-moi trois interprétations : naturelle, chaude et noir et
blanc », « Harmonise cette série sur la troisième photo », « Trie la séance et propose-moi les
meilleures », « Note ces photos » (Claude pose les notes), « Lis la composition et propose un
cadre », « Comment progressent mes prises de vue ? » (le carnet de progrès) ou « Prépare la
sélection pour Instagram ». Dans la fenêtre Claude, une photo que Claude traite est d'abord
notée : sa note attend « à vérifier » dans la carte Note. À l'ouverture de la fenêtre, sur une
conversation vide, Claude prépare déjà une proposition de retouche de la photo active : elle
attend dans l'onglet Proposition, où Je le fais vous laisse la faire vous-même. Après une
retouche, « Pourquoi ? » sur une étape du fil en montre l'avant/après, et l'onglet Leçon la leçon
de la photo.

Claude regarde la photo, pose un diagnostic chiffré (avec ce que l'appareil Fujifilm a noté de la
prise de vue, et un éclairage mixte s'il y en a un), applique une première passe (profil, balance
des blancs, tonalité), vérifie le rendu, puis fait les finitions, dans l'ordre que recommande
l'aide d'Adobe (corrections d'objectif avant Upright, débruitage avant les masques et les taches).
Si la vérification montre encore un défaut précis (hautes lumières brûlées, dominante, masque trop
visible, ou une régression que chiffre le bilan), il fait une passe corrective ciblée, deux au
plus, et dit ce qui reste. Dans la fenêtre Claude et avec les invites qui retouchent, son résumé
de fin donne les chiffres du bilan. Pour comparer :
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
- **« Liaison fermée : cette commande ne porte pas le jeton de la liaison… »** : un connecteur
  d'avant la 1.2 tourne encore (Claude Desktop, ou une session de Claude Code, ouverts pendant
  l'installation). Quitter puis rouvrir Claude Desktop, ou ouvrir une nouvelle session de Claude
  Code. Si le message revient, le connecteur installé est plus ancien que le module : réinstaller
  Développeur.
- **« Liaison fermée : le module n'a pas de jeton »**, jeton absent ou illisible selon `--status`,
  ou dans la fenêtre Claude l'aide « n'a pas pu préparer son jeton privé » : relancer la liaison
  (Fichier › Module externe - Extras › Arrêter, puis Démarrer la liaison avec Claude, ou un clic
  sur le voyant Lightroom de la fenêtre Claude), qui réécrit le fichier ; le détail est dans
  `~/Library/Logs/Developpeur/module.log`. « Le jeton de cette commande n'est pas celui de la
  liaison » : la liaison vient de redémarrer, réessayer ; si le refus se répète, la relancer.
- **Voyant Écran gris (« Écran »)** : le connecteur n'a pas répondu dans les 5 secondes, est
  introuvable ou plus ancien que la 1.2 (un clic sur le voyant en dit la raison) : réinstaller
  Développeur, ou régler le chemin du connecteur dans le Gestionnaire de modules externes.
- **Connecteur absent de Claude Desktop après l'installation** (ou ancien connecteur `lightroom`
  revenu, que `--status` signale) : Claude Desktop était ouvert et a réécrit sa configuration. Le
  quitter (⌘Q), lancer `"$HOME/Library/Application Support/Developpeur/mcp-developpeur" --install`,
  puis le rouvrir.
- **Fenêtre « … souhaite accéder aux fichiers d'un volume »** : macOS demande l'autorisation de
  lire le disque de vos photos pour le connecteur lancé par Claude ; c'est à vous d'y répondre.
  Sans elle, le tri et l'aperçu continuent sans le point de mise au point ni l'intention de la
  prise de vue des photos Fujifilm ; leur lecture reprend une fois votre réponse donnée.
- **Fenêtre « Mises à jour IA recommandées »** : Lightroom n'a pas pu calculer un masque IA (ses
  modèles IA ne sont pas encore téléchargés) ; répondre « Exporter », case « Mettre à jour les
  photos concernées » cochée.
- **« Synch. auto » de Lightroom** : dans les essais, les retouches de Claude ne se sont pas
  propagées aux autres photos sélectionnées ; la couper quand même pendant que Claude travaille, par
  précaution.
- **« Le module de Lightroom ne connaît pas encore le carnet de progrès » (ou « Je le fais », ou
  « Leçon non rangée : … module d'avant la 1.3 »)** : le module chargé dans Lightroom est plus
  ancien que le connecteur ; quitter puis relancer Lightroom (la 1.3 ajoute des fichiers au module,
  qu'un rechargement ne voit pas), et réinstaller Développeur si le message revient.
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
fichiers temporaires), liaison TCP avec un faux module Lightroom (jeton compris, dans un fichier
temporaire), ce que la 1.2 ajoute (bilan, éclairage, lecture des fichiers Fujifilm, écran,
dosage de la peau) et la 1.3 (leçon de la photo, composition lue, « Je le fais », carnet de
progrès, recette de la 1.3 sur un module simulé), sur des images, des fichiers et des profils de
couleur fabriqués. Les contrats de la composition et de « Je le fais » entre le connecteur et le
module (`Tests/Contrats/`) sont lus par les deux suites.

```bash
scripts/tester-module.sh
```

Le module, avec LuaJIT : forme du module, syntaxe et globales de chaque fichier, syntaxe de
`relais.sh`, liens entre les fichiers, puis deux suites, chacune sur son Lightroom simulé :
`Tests/Lua/Liaison` (les commandes du connecteur, notes proposées, avant/après des étapes, carnet
et leçons comprises) et `Tests/Lua/Fenetre` (la fenêtre Claude avec un faux Claude Code, ses
images et ses apparences, Publication et Consommation) ; dans chacune, les essais `essais-*.lua`
tournent après `tests.lua`. La simulation de la fenêtre imite ce qui a été constaté dans
Lightroom (Retour, clics, vues masquées, texte riche…) et refuse ce qui n'y marche pas.

Aucun test ne touche Lightroom, Claude, vos photos ni les fichiers de Claude, et aucun ne consomme
de quota. Un test relit seulement, s'il les trouve, les doses de la peau rangées dans l'application
Lightroom Classic ; aucun ne lit votre écran, sauf sur demande :
`DEVELOPPEUR_ECRAN_REEL=1 swift test`. Les deux suites tournent aussi à chaque envoi sur `main`
(GitHub Actions).

Pour la mise au point, Lightroom ouvert et liaison démarrée, l'exécutable installé
(`~/Library/Application Support/Developpeur/mcp-developpeur`) offre aussi ce qui suit ; ce qui
parle au module y passe avec le jeton de la liaison, comme le connecteur :

- `--call <outil> '{…}'` : appelle un outil comme le ferait Claude ;
- `--module diagnostic` : les fonctions du SDK que Lightroom offre au module
  (`'{"valeurs": true}'` lit aussi le jeu de libellés, le filtre de la Bibliothèque et l'original
  de la photo active) ;
- `--dump [<id>]` : tous les réglages bruts d'une photo, une clé par ligne, à comparer avec `diff`
  avant et après une opération faite à la main ;
- `--recalage <id>` : les écarts du recalage des positions sur la géométrie actuelle de la photo ;
- `--marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>` : le carré de mise au
  point d'un fichier Fujifilm dessiné sur une vignette, comme dans l'aperçu de la photo active de
  la fenêtre Claude (code 1 sans point), sans Lightroom ni liaison ;
- `--boitier <original>` : ce que l'appareil a rangé dans un fichier Fujifilm (RAF ou JPEG) : point
  de mise au point, intention de la prise de vue comme dans `view_photo`, et valeurs lues sous les
  noms d'exiftool, une ligne JSON (code 1 si rien n'est lu), sans Lightroom ni liaison ;
- `--ecran` : l'écran principal et son profil de couleur, une ligne JSON (ce que lit le voyant Écran
  de la fenêtre Claude ; `{"lu": false}` sans écran), sans Lightroom ni liaison ;
- `--eclairage <id>… [<fichier.jpg>…] [--essai '{…}']` : le relevé de l'éclairage mixte (couleur des
  tons neutres par case et par zone tonale, visages, à plusieurs bornes), en lecture seule ; un
  fichier JPEG se mesure sans Lightroom ; `--essai` mesure sous une autre balance par
  `preview_settings` (deux étapes « Claude · essai » dans l'Historique), sur une copie virtuelle
  seulement ;
- `--constats <id>… [<fichier.jpg>…]` : le relevé des seuils du carnet de progrès (luminosité,
  blanc pur du tiers haut, netteté et texture au point de mise au point, bruit, boîtier,
  géométrie, puis les défauts que `view_photo` noterait), en lecture seule : rien n'est noté au
  carnet ; un fichier JPEG se mesure sans Lightroom ;
- `--recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>]`
  `[--x-t20 <id>] [--portrait <id>] [--mixte <id>] [--horizon <id> [--hauteur-horizon <0 à 1>]]` :
  rejoue une séquence complète dans le vrai
  Lightroom, sur des copies virtuelles de la collection « Développeur › Essais » (des originaux
  seulement avec `--original`), vérifie chaque étape sur les réglages relus, puis remet chaque
  photo dans son état de départ, même après un échec. Elle commence par la liaison fermée (une
  commande sans jeton, ou avec un autre, refusée) et l'écran nommé, en lecture seule ; le RAW
  passe aussi par l'intention lue au boîtier, le bilan chiffré d'une passe à l'autre (une étape
  écrite puis annulée) et éclaircir et assombrir (en propositions), le X-T20 par l'intention ;
  `--portrait` y ajoute la peau dosée sur un portrait (trois doses en propositions, l'intensité 50
  qui vaut la moitié, le refus d'une peau trop lissée, la dose par défaut posée puis annulée),
  `--mixte` une photo à deux lumières lue mixte, puis le RAW lu à une seule lumière, en lecture
  seule. Le RAW passe aussi par la 1.3 : l'avant/après d'une étape, la leçon (rangée, relue,
  retirée), le carnet (la copie d'essai notée pour la recette, puis retirée) et « Je le fais » (sa
  version rangée, comparée, puis effacée) ; `--horizon` vérifie la composition lue sur une copie
  d'essai qui a un vrai horizon (sans horizon net à `--hauteur-horizon`, 0,5 par défaut, la
  dernière étape, le cadre appliqué, est sautée avec sa raison). La recette remet aussi le registre
  des notes comme elle l'a trouvé ;
- `--version`.

## Organisation

- `Sources/DeveloppeurKit/` : le connecteur (protocole MCP, outils, invites, catalogue des
  réglages, standard de notation, dosage de la peau, mesures et Vision, éclairage, bilan d'une
  passe à l'autre, lecture des fichiers Fujifilm, écran, défauts de la prise de vue, leçon de la
  photo, composition lue, « Je le fais », carnet de progrès, liaison TCP avec le module et son
  jeton)
- `Sources/MCPDeveloppeur/main.swift` : l'exécutable `mcp-developpeur` (options de ligne de
  commande, boucle stdio)
- `Lightroom/Developpeur.lrplugin/` : le module Lightroom Classic, en Lua 5.1 (liaison avec le
  connecteur, registre des notes proposées, avant/après des étapes, carnet de progrès et leçons,
  fenêtre Claude et `relais.sh` qui lance Claude Code, Publication, Consommation, fenêtre de
  suivi) ; ses images, en deux jeux, dans `images/` (apparence claire) et `images/sombre/`
- `Tests/DeveloppeurKitTests/` : tests du connecteur, avec un faux Lightroom et un faux module TCP
- `Tests/Lua/Liaison/`, `Tests/Lua/Fenetre/` : tests du module, chacun sur son Lightroom simulé
- `Tests/Contrats/` : les échanges de la composition et de « Je le fais » entre le connecteur et
  le module, lus par les deux suites
- `scripts/` : `tester-module.sh` ; `metriques.swift` (chasse des polices de la fenêtre Claude),
  `gabarits.lua` (tailles et couleurs des images de la fenêtre), lu par `images-fenetre.swift` et
  `images-vides.swift`, qui les dessinent (images de la fenêtre, image « aucun aperçu »)
- `Resources/Info.plist` : identifiant et numéro de version du connecteur
- `docs/` : captures, `SPEC.md` (cahier des charges, protocole entre le connecteur et le module,
  et la fenêtre Claude), `aide-adobe-developpement.md` (notes sur l'aide d'Adobe)
- `build.sh`, `install.sh`, `uninstall.sh` : construire, installer, désinstaller

## Licence

Sous licence MIT ([LICENSE](LICENSE)) : chacun peut utiliser, modifier et redistribuer le code, en
gardant l'avis de droit d'auteur.
