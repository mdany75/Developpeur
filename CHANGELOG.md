# Changements

## Non publié

Pour la prochaine version, la 1.2 (un rendu plus juste sur chaque photo, en préparation) : à
l'ouverture de la fenêtre Claude, l'aperçu de la photo active montre son point de mise au point
(fichiers Fujifilm), et Claude prépare une proposition de retouche sans rien appliquer ; un zoom
montre aussi le point de mise au point ; la fenêtre n'a plus qu'une disposition, la Conversation
claire.

### Ajouté
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

### Changé
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
