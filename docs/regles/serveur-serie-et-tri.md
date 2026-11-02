# Règles : série, lumière, teint et tri

Sorti de `Sources/CLAUDE.md` le 31 octobre 2026 ; à lire avant de toucher à `match_series`,
`GroupesLumiere.swift`, `Teint.swift`, `cull_photos`, `contact_sheet`, au découpage en tranches ou
au suivi d'une longue série (`ContexteAppel`).

- `match_series` compare la photo et la référence par la même mesure des tons neutres ; les tons
  suivis d'une passe à l'autre (`Measurements.neutres` avec masque) ne servent qu'aux pentes, et
  Teinte et Température se résolvent ensemble (`PentesSerie`, relevées dans Lightroom). Chaque photo
  repart des pentes relevées.
- **Harmoniser par lumière** (1.4, `GroupesLumiere.swift`, `Tools+Lumiere.swift`) : `match_series`
  avec `groups` (sans `reference_id`, refusé avec lui) mesure les vignettes de toute la sortie comme
  `cull_photos` (`ToolHandler.mesurer`, `maxPhotosSortie` 2 000), sans ouvrir aucun original (la
  description perd `geometrie` avant la mesure : pas de point de mise au point), puis
  `GroupesLumiere.former`, pure : dans l'ordre de prise de vue (les photos sans date après, dans
  l'ordre donné, `sansDate`), une photo commence un groupe quand le flash change (deux connus),
  quand la lumière de la scène (`Prise.lumiere`, IL à 100 ISO : log2(N²/t) − log2(ISO/100) +
  compensation ; pas pour une photo au flash, ni contre une photo au flash) s'écarte de `ecartIL`
  (2,5) ou plus de la médiane des `fenetreLumiere` (5) dernières du groupe (un coucher de soleil qui
  baisse peu à peu reste un groupe), ou après une pause de plus de `pauseMax` (10 min), sauf même
  lieu (empreinte de Vision à moins de `distanceMemeLieu`, 0,7, de l'une des `fenetreLieu`, 3,
  dernières) dans `pauseMemeLieu` (1 h) ; deux boîtiers restent ensemble ; seuils provisoires, à
  relever sur la sortie de l'essai. La référence proposée (`GroupesLumiere.reference`) : sans défaut
  mesuré si possible, une photo déjà retouchée par Claude (`retouchee_par_claude` de la
  description), sinon la mieux classée au tri (`PhotoTriee.score`) parmi celles qui ont un visage
  plausible d'au moins `Teint.visageMin`, sinon parmi toutes ; un groupe de plus de
  `maxMatchedPhotos` (60) dit ses lots ; une photo seule sous sa lumière va dans `photos_seules`.
  Rien n'est écrit : le plan seulement (`planDesGroupes`). La prise de vue vient de la description
  des vignettes : `prise_de_vue` du module (1.4 : `aperture`, `shutterSpeed`, `exposureBias` et
  `flash` de `getRawMetadata`, un booléen ou rien), `sensibilite` et la date ; `view_photo` retire
  `prise_de_vue` avant Claude.
- **Le témoin du teint** (1.4, `Teint.swift`) : dans `match_series` avec `reference_id`, la peau du
  plus grand visage plausible (`VNDetectFaceRectanglesRequest`, `Composition.visagePlausible`, au
  moins `visageMin` de largeur) se lit au milieu du visage (`Teint.interieur`, comme l'éclairage)
  dans l'aperçu de mesure pris à pleine résolution (le zoom du visage, sans autre rendu), aux bornes
  de peau de l'éclairage (`Eclairage.peauLumineux`, `peauChroma`), `pixelsMin` (60) au moins ;
  seulement si la référence en a une (sinon aucune autre Vision). Un témoin, jamais la correction
  (deux personnes n'ont pas la même peau) : `teint` par photo (écart a*b* et teinte avant et après),
  et `a_verifier` quand l'harmonisation l'éloigne (`Teint.alerte` : après ≥ `ecartVisible`, 5, et
  hausse ≥ `hausseAlerte`, 2), à regarder par `view_photo` avec `region` sur le visage ; sans tons
  neutres (balance gardée), une remarque si la peau diffère de `ecartVisible`. Seuils provisoires ;
  Vision ne trouve aucun visage dans les images des tests : la lecture d'un vrai visage reste à
  constater.
- **Le tri d'une sortie entière** (1.4) : `cull_photos` prend `maxCulledPhotos` (1 000) photos par
  appel (`maxCulledDetails`, 500, avec `details` ; la réponse d'un tri de 2 000 photos toutes floues
  pèserait 0,9 Mo, texte et forme structurée), et, avec `offset` (sélection, collection, dossier),
  la tranche suivante ; une sélection plus longue n'est plus refusée (`parTranches` de
  `seriesPhotosSansVideos`), `photos_non_triees` dit l'`offset` suivant ; une rafale à cheval sur
  deux tranches s'y coupe. La commande `selection` du module prend `decalage` et le redit dans sa
  réponse (un module d'avant décrit le début : le connecteur la redemande une fois assez loin,
  `decalage` plus la tranche, et saute lui-même les premières) ; `chercher` décrit jusqu'à 2 000
  photos (`MAX_RESULTATS` de `Bibliotheque.lua`, 500 avant ; `find_photos` s'arrête toujours à
  `maxSearchLimit`, 500). Les groupes de lumière comparent le flash à la dernière photo du groupe
  qui le dit (deux boîtiers mêlés, l'un sans flash lu), et une photo seule dit ce qui la sépare
  avant et après elle (trouvailles de la relecture du 26 octobre 2026 ; une vignette trop petite y
  est rendue comme un aperçu, comme au tri).
- **Noter une grande sélection** (1.4, constaté le soir du 26 octobre 2026 : « note la série » sur
  951 photos, par la Demande rapide, n'en notait que 24) : Claude Code range une réponse d'outil de
  plus de 25 000 jetons (son défaut) dans un fichier, et Claude ne peut rien lire dans la fenêtre
  (`--tools ""`) ; le tri de 951 photos faisait 147 000 caractères, dont 80 % de `plafonds`, une
  ligne par photo, et `list_selection` à 500, 168 000. `relais.sh` pose donc
  `MAX_MCP_OUTPUT_TOKENS=100000` (essai de bout en bout de `tests.lua`, par `faux-claude.sh`) ;
  au-delà de `Tri.plafondsParPhotoMax` (100) photos, le tri dit `plafonds_par_motif` à la place de
  `plafonds` (les photos de chaque plafond regroupées par `Notation.Plafond.motif`, la raison sans
  les mesures de chaque photo ; 43 000 caractères estimés pour ces 951 photos, 27 motifs), le
  plafond de chaque photo restant gardé pour `propose_ratings` (`dernierTri`) ; `contact_sheet`
  prend une sélection plus longue que sa planche dès l'offset 0 (`parTranches` ; refusée jusque-là,
  alors qu'un offset de 30 passait), et sa suite compte les vidéos écartées (`decalage` + photos +
  vidéos : sans elles, des photos revenaient d'une planche à l'autre), une tranche faite de vidéos
  seulement donnant la suite au lieu d'une erreur ; sa réponse dit `planche` (`premiere`, `derniere`
  : positions dans la série, vidéos comprises ; `sur`), sauf pour `photo_ids` ; les consignes de la
  fenêtre (puce Notes, `Consignes.rapide`, `Consignes.noterRapide`) disent de noter plus de 30
  photos planche par planche (`contact_sheet` avec `selection` et `offset`, puis `propose_ratings`),
  jusqu'à la dernière dans le même tour (la planche suffit pour confirmer les rejets du tri), sans
  `list_selection` pour les parcourir ; `Consignes.rapide` ne dit plus « sans suite » (Claude, Haiku
  à l'effort bas, renonçait alors à noter les 951 photos après le tri, reçu en entier : « je ne peux
  pas le faire fidèlement dans cette demande sans suite »), mais de faire la demande en entier dans
  le tour, même longue. Essais : `GroupesLumiereTests` (plafonds par motif, première planche d'une
  grande sélection, vidéos sautées). Trouvailles d'une relecture adverse du même soir (vidéos,
  planche de vidéos, ligne d'état), corrigées.
- Une longue série passe par le `ContexteAppel` de l'outil : `avancer` (de `ToolHandler`) après
  chaque lot (progression envoyée au client, reprise dans la réponse d'attente, et barre de
  progression de Lightroom par la commande `progression`, fermée à la fin de l'appel par
  `fermerBarre`), `verifier` avant chaque lot (annulation par `notifications/cancelled`, sans
  réponse ; croix de la barre de Lightroom, `ArretDansLightroom`, avec une réponse).
- **Étalonnage d'après une référence** (1.6, `match_look`, `Reference.swift` pure,
  `Tools+Reference.swift`) : `reference_id` seulement (pas de fichier externe dans la 1.6). La
  couleur d'une zone se lit sur ses pixels peu saturés (C* < `chromaZone`), jamais par la mesure
  des tons presque neutres d'`Eclairage` (C* < 12 : elle écarte le rendu à copier) ; visages
  écartés ; un pixel n'est écarté au noir que si ses trois composantes y sont (une ombre teintée
  profonde compte). Seul le partage entre zones se copie : la part commune est la balance, copiée
  seulement avec `white_balance` ; jamais la moyenne des zones (une seule zone teintée donnerait
  la couleur complémentaire aux autres) : médiane des trois, ou les tons moyens. Clés : `SplitToning*` (ombres, hautes lumières), `ColorGradeMidtone*` ;
  jamais `ColorGradeShadowHue` (refusée par Lightroom). Tons par Exposition et Contraste seulement.
  Vibrance seule, sous `plafondsDose`, d'après la chroma des seuls pixels colorés (C* ≥
  `chromaZone` : l'étalonnage teinte les gris, la Vibrance ne doit pas le recompter) ; saturation
  de l'étalonnage sous max(`Reference.saturationMax`, valeur actuelle). Une photo en erreur ne
  fait pas échouer la série (ligne `erreur` avec ses `etapes`) ; vidéos de `photo_ids` écartées.
  Au plus deux passes, chacune UNE écriture absolue (valeurs finales d'après les réglages relus),
  `sans_avant_apres` ; la passe 2 vise `strength` de l'écart du départ. Peau qui bouge de
  `Teint.ecartVisible` : moitié du changement des tons moyens, `a_verifier`. La fenêtre le traite
  comme `match_series` (`Conversation.SERIES`). Pentes, `chromaZone` et `seuilScenes` relevés par `--etalonnage` le 2 novembre 2026 (SPEC) ; `Teint.ecartVisible` reste provisoire.
