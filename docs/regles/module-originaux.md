# Module Lightroom : originaux et lecture du boîtier

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Photos.exigerOriginal`, à `--marquer-af`, à `--focus`, à `--boitier` ou à `LecteurBoitier`.

- Une commande qui calcule sur l'original (débruitage, détails bruts, super résolution, reflets,
  passants retirés ; pas les passants rendus) passe par `Photos.exigerOriginal` ; un rendu sans original ni aperçu dynamique est refusé
  (`rendre`) ; une livraison saute la photo. `checkPhotoAvailability` suit le disque à quelques
  secondes près (constaté).
- Le connecteur n'ouvre un original que
  pour la lecture du boîtier d'une photo Fujifilm, point de mise au point et intention de la prise
  de vue (`cull_photos`, `view_photo`, `--marquer-af` pour l'aperçu de la photo active de la
  fenêtre Claude, `--focus` pour son onglet Focus, et `--boitier` à la main), d'une seule
  ouverture par photo et par processus (aucune pour un avant/après ; `--marquer-af` et `--focus`
  sont deux processus, donc deux ouvertures pour la même photo active, la seconde seulement quand
  l'onglet Focus est montré), en temps borné (`LecteurBoitier`, 2 s, qui remplace
  `LecteurPointsAF` depuis la 1.2 ; et, pour `--marquer-af` et `--focus` lancés par la fenêtre,
  l'alarme de 5 s de `perl`, comme pour `--ecran` jusqu'au correctif 1.3.6) :
  macOS peut faire attendre `open()` sans fin (autorisation d'accès au volume) ; un original
  qui ne s'ouvre pas à temps est sauté, les suivants aussi tant que sa lecture n'a pas fini, puis la
  lecture reprend. Claude ne répond jamais à une demande d'autorisation de macOS. Le Suivi
  (correctif 1.3.7) n'ouvre jamais d'original : `--analyser` ne lit que les vignettes du cache de
  Lightroom que le module lui donne, `--graphiques` que `suivi.json` et `carnet.json`.
