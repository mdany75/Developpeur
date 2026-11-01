# Module Lightroom : fenêtre Claude (structure, contrôles, apparence)

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Fenetre.lua`, à `Vues.lua`, à `Dispositions.lua`, aux images, aux polices, au champ de demande
ou aux raccourcis.

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
  (`Fenetre.preparerApparence`) ; deux jeux d'images, `images/` et `images/sombre/` (skill
  `commandes-diagnostic`, Images de la fenêtre) ; l'image « aucun aperçu » est `images/vide-498x332.png` et sa
  version sombre (`vide-320.png` est retirée) ; la palette sombre se lit au moins aussi bien que
  la claire (`essais-images.lua`) ; les contrôles natifs suivent l'apparence de macOS. Les polices
  sont celle du système et Menlo 11, mesurées par `scripts/metriques.swift` (D9 : l'encre fait 1 à
  2 points de moins que la chasse ; `Fenetre.largeurLibelle` ajoute 2 points à un libellé fixe).
- Un raccourci d'app vise le titre exact de l'entrée de menu, tel que Lightroom l'écrit : trois
  espaces devant chaque entrée de module (`Raccourcis.RETRAIT`, constaté par l'accessibilité) ;
  `Raccourcis.LISTE` : ⌃⌥C (Ouvrir la fenêtre Claude) et ⌘⌃⌥C (Demande rapide, correctif 1.3.3).
  Lightroom ne lit les raccourcis qu'à son lancement : un rechargement du module ne suffit pas.
