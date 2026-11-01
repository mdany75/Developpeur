# Module Lightroom : carnet de progrès

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Carnet.lua`, à `carnet.json`, à `Carnet.swift` ou aux constats de la prise de vue.

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
  retirée au correctif 1.3.6 ; `Vignettes.decrireVignette`), sinon `prise_de_vue.iso` d'un module
  1.3 ;
  `view_photo` retire `sensibilite` avant Claude. Pas le plafond de note (`Notation.plafond`), qui
  juge l'image, ni le tri, qui ne fait que dire la mesure. Les constats notés avant restent tels
  quels ; `constats_prise_de_vue`
  seulement si le module répond `note = true`, erreurs tues ; `noterAuCarnet` n'est vrai que dans
  `serve()` (ni `--call`, ni la recette, ni les tests), et seul lui fait demander les clés de la
  géométrie ; `view_photo`, `measure_angle` et `read_composition` restent `readOnlyHint`. Seuils
  `medianeSousExposee` 28, `p95SousExposee` 80 et `partBlancPurHaut` 3 % provisoires (aucun vrai
  cas). La case Carnet coupe les constats (elle devait couper aussi les leçons, décision de Dany du
  24 octobre 2026, devenue sans objet : la leçon est retirée au correctif 1.3.6). Depuis la fenêtre
  Claude, le carnet se voit dans la fenêtre Suivi, en graphiques depuis le correctif 1.3.7 (`docs/SPEC.md`,
  Correctif 1.3.7 : le Suivi en graphiques) : `--graphiques` lit `carnet.json` en lecture seule, et pour un original de même
  uuid, chaque code que le carnet a cherché (`vue.cherches`, le code de l'angle) l'emporte sur
  l'analyse d'office du Suivi ; une entrée du carnet absente du relevé ne compte pas, un carnet
  illisible fait une remarque.
