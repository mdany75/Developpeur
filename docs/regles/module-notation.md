# Module Lightroom : notation (registre, notes posées, carte Note)

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Notation.lua`, à `notation.json`, à la carte Note de la fenêtre ou à `propose_ratings`.

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
  active, le refus « Photos à traiter » ; `contact_sheet`, lui, demande toujours une série),
  `view_photo` avec `af_point = true`, puis `propose_ratings` sans `apply` ;
  sa note arrive « à vérifier » dans la carte Note, où Dany l'accepte, la laisse ou la change
  (Accepter, Laisser, Changer…, les étoiles). Une photo déjà évaluée (`view_photo` : `evaluation`)
  ne se renote pas, sauf s'il le demande. Ni Noter ni Évaluer : ni dans les invites, ni dans la
  carte Note (`Fenetre.noter`, `Consignes.noterPhoto` et `Consignes.noterSelection` retirés) ;
  « ? À vérifier » est posé grisé, sans action (`Vues.inactif`, décision de Dany du 21 octobre
  2026 ; `Fenetre.verifierNote` reste nil ; le remettre comme « remettre à vérifier » par
  `Notation.decider` est une question ouverte), et les essais le vérifient ; l'aide de la carte
  Note (`Fenetre.AIDE_NOTATION`) le dit. Les consignes du connecteur (`ServerInfo`, Claude Desktop) ne
  demandent pas cette note d'abord.
