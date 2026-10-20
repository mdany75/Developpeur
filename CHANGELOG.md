# Changements

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
