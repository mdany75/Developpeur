# CLAUDE.md — serveur et mesures (Swift)

Règles du serveur MCP-Développeur et de ses mesures, sorties du CLAUDE.md principal, qui garde
les règles communes à tout le projet. Le détail (seuils relevés, dates, historique des correctifs,
contrats de réponse) est dans `docs/regles/serveur-*.md` ; lire le fichier du thème avant d'y
toucher :

- défauts, raison des outils, composition, netteté, éclairage, bilan, écran :
  `docs/regles/serveur-mesures.md` ;
- `match_series`, groupes de lumière, teint, tri d'une sortie, grande sélection, longue série :
  `docs/regles/serveur-serie-et-tri.md` ;
- intention du boîtier et point de mise au point (`view_photo`) : `docs/regles/serveur-boitier.md` ;
- masques, peau, tireur, taches, positions, contrainte du recadrage :
  `docs/regles/serveur-retouches-locales.md` ;
- standard de notation, plafonds, échelle, libellés de couleur : `docs/regles/serveur-notation.md`.

## Mesures

- **`PriseDeVue.defauts` est la seule liste des défauts** ; `PriseDeVue.vocabulaire` part avec
  chaque constat : aucune liste de défauts dans le module. `yeux_fermes` a `mesure` faux : le
  Suivi le compte, le carnet de `view_photo` ne le cherche pas.
- **Raison** : `ToolHandler.descriptionRaison` et `descriptionRaisonProposition` font 160 caractères
  au plus (plus longue, Claude joignait `reason` à preview_settings et l'appel était refusé) ; la seconde ne
  promet pas le journal. Une proposition n'écrit rien : sa raison ne part jamais au module (ni étape
  ni journal), elle revient dans `raison`, à redonner à `apply_settings`. `ToolHandler.raison` la
  borne (300).
- **La composition se lit sur l'image entière** (`sansRecadrage`, deux étapes « Claude ·
  composition ») ; une photo agrandie est refusée avant toute écriture, un module sans
  `image_entiere` aussi. Positions par `Composition.versImageEntiere` ; le dessin suit le cadre
  relu (`cadre_propose`), jamais la demande. Contrat figé : `Tests/Contrats/composition.json`.
- **Mise au point jugée sur de la texture** (`Detail.autour`) : sous `textureMin`, « non jugée » ;
  ni plafond ni constat au carnet, sauf si l'appareil l'a signalée ; jusqu'à `textureDouteuse`, un
  doute à vérifier, sans rejet proposé, que le carnet ne compte pas.
- **Ne changer aucun seuil relevé sans le remesurer** (netteté, bruit, texture, yeux, éclairage,
  bilan, `thumbnailSharpnessFactor`) ; les seuils dits provisoires restent à relever. Le tri, les
  plafonds (`Notation.plafond`) et `Suivi.analyser` reprennent les seuils sans en ajouter.
- **Vision ne s'appelle pas en grand parallèle** (`concurrentPerform` l'a bloqué) : deux photos
  à la fois au plus. Ne lit ni le genre ni l'âge d'un visage.
- **Éclairage** (`Eclairage.swift`) : tons presque neutres lus autour du point neutre de l'image
  ramené vers le gris (`Eclairage.centrer`, `toleranceNeutre`), car une borne absolue ne lisait
  plus rien sous une autre balance ; sous une dominante extrême, son conseil dit « à confirmer à
  l'œil ».
- **Bilan de `view_photo`** (`Bilan.swift`, `vuesMesurees`, `Bilan.Cle` photo et taille) : une
  autre taille d'aperçu repart de zéro. Jamais une proposition contre une vue gardée : une
  proposition avec `compare` et `view_photo` avec `compare` ont leur propre bilan, sur deux images de la même commande ; netteté et
  bruit seulement entre deux vues. Toute image se mesure par `ToolHandler.mesurerImage` (512 px).
  Tons neutres suivis à cadre égal seulement (`Bilan.cadre`). Une annulation ou un calcul IA en
  attente ne donne pas de « regression » : `a_verifier`.
- **Écran** (`Ecran.swift`, sans AppKit ni permission) : **plus rien sur l'étalonnage** (Dany
  n'achètera jamais de sonde) : ni Dany ni Claude n'en entendent parler. Le classement ne sert qu'à
  `--ecran`. Seul `main.swift` pose `Ecran.lire` ; seul `get_status` le lit, et ne dit que les noms
  (`Ecran.nommer`). `EcranTests` vérifient qu'aucune description ni `ServerInfo.instructions` ne
  parlent de sonde, et qu'aucun aperçu ne lit l'écran. Piège : `ColorSyncProfileCopyHeader` rend les
  signatures à l'envers ; l'en-tête ICC se lit dans les octets.

## Série et tri

- `match_series` compare photo et référence par la même mesure des tons neutres ; les tons suivis
  ne servent qu'aux pentes ; Teinte et Température se résolvent ensemble (`PentesSerie`).
- **`match_look`** (1.6, `Reference.swift`) : couleur des zones sur leurs pixels peu saturés, jamais
  par la mesure d'`Eclairage` ; la part commune aux zones est la balance (seulement avec
  `white_balance`) ; une écriture absolue par passe, deux au plus ; pentes provisoires
  (`--etalonnage`). Exposition (0,5 IL, `expositionMax`) et contraste (30) bornés en tout par
  appel, depuis la valeur de départ (`traduire(…, depart:)` à la passe 2) : l'écart de clarté vient
  aussi de la scène (constaté le 2 novembre 2026).
- **Harmoniser par lumière** (`GroupesLumiere.former`, pure) : `groups` est refusé avec
  `reference_id` ; aucun original ouvert ; rien n'est écrit, le plan seulement (`planDesGroupes`).
  `view_photo` retire `prise_de_vue` avant Claude.
- **Le témoin du teint** (`Teint.swift`) : seulement si la référence a un visage (sinon aucune autre
  Vision) ; un témoin, jamais la correction (deux personnes n'ont pas la même peau) : `a_verifier`
  quand l'harmonisation l'éloigne.
- **Tri d'une sortie entière** : `cull_photos` par tranches (`maxCulledPhotos`, `offset`,
  `parTranches`) ; `find_photos` s'arrête toujours à `maxSearchLimit`.
- **Noter une grande sélection** : Claude Code range une réponse d'outil de plus de 25 000 jetons
  dans un fichier que la fenêtre ne lit pas : `relais.sh` pose `MAX_MCP_OUTPUT_TOKENS=100000`, le
  tri dit `plafonds_par_motif` au-delà de `Tri.plafondsParPhotoMax`, et les consignes disent de
  noter planche par planche (`contact_sheet` puis `propose_ratings`), jusqu'à la dernière dans le
  tour, sans `list_selection`. `Consignes.rapide` ne doit pas dire « sans suite » (Haiku renonçait).
- Une longue série passe par le `ContexteAppel` : `avancer` après chaque lot, `verifier` avant.
- **Habitudes** (`Habitudes.swift`, `remember_style` avec `habits`, 1.6) : lecture seule, rien au
  guide sans accord ; attribution par les clés de Claude rendues dans l'espace de `etatSimple`
  (`Lecture.habitudes`, plus celles de l'original pour une copie virtuelle) ; recadrage par les
  clés `Crop*`, jamais `HasCrop` ; ni température ni teinte d'un RAW, ni bruit de couleur à 0
  d'un RAW ou d'un DNG (le débruitage de Lightroom, `Habitudes.debruitee`) ; écarts à la valeur neutre
  (`rawDefaults` pour un RAW) ; seuils
  provisoires, à fixer par `--habitudes` (`docs/SPEC.md`, 1.6 : tes habitudes en chiffres).

## Boîtier

- **L'intention du boîtier** (`IntentionBoitier`) se lit seulement : sur l'aperçu entier, jamais sur
  un zoom ni un avant/après, rien posé d'office. Un RAW n'en reçoit que la simulation
  (`profilLightroom`), sauf autre style demandé ou guide de style contraire ; ne pas refaire ce que
  porte un JPEG de l'appareil ; une compensation de −0,6 IL ou moins dit une photo voulue sombre, à
  ne pas remonter.
- **Le point de mise au point** (`Boitier.swift`, `PointAF.swift`) : aperçu entier ou zoom, jamais
  un avant/après ; le serveur retire `chemin_original`, `geometrie`, `marque`, `point_af_toujours`
  et `etapes_claude` avant Claude. Sur un zoom, le carré seulement si le point tombe dans la zone.
  Mesures et Vision avant le carré. Un seul lecteur (`ToolHandler.lecteurBoitier`) : une lecture
  bloquée n'en lance pas d'autres.

## Retouches locales et géométrie

- Masque combiné : `MaskBlendMode` (0 ajouter, 1 soustraire) ; une intersection = soustraction du
  composant inversé (`Locaux.combiner`).
- **Formes des masques** : plage de profondeur par `DepthRange`, jamais `DepthMin`/`DepthMax` ;
  dégradé radial avec `Flipped = true` toujours, inversé par `MaskInverted` seul (`Locaux.radial`),
  partout (combiné, `edit_mask`, copie). La simulation vérifie chaque forme.
- **Le dosage de la peau n'existe qu'à un endroit** : `Peau` (d'après les fichiers d'Adobe, non
  son aide) ; `Consignes.lua` y renvoie sans chiffres. `add_mask` seul refuse, avant tout envoi,
  une peau au-delà de la dose Lite ou à netteté négative sans `smoothing_requested`, posé
  seulement sur demande de Dany ou de son guide (`Peau.verifier`). Piège : `CorrectionAmount` est
  linéaire (étape de `--portrait`). Dans le doute sur un visage, la dose la plus faible.
- **Les doses du tireur n'existent qu'à un endroit** : `Prompts.Tireur` (plafonds, sans mesure),
  repris dans la description d'`add_mask` car la fenêtre ne lit pas les invites ; `Consignes.texte`
  n'en dit rien, et les boutons de la fenêtre demandent la méthode sans chiffres. Radial inversé ou
  vignetage, jamais les deux (rien si la photo porte déjà `PostCropVignetteAmount` ou si le guide
  écarte le vignetage).
- Une tache Supprimer de Claude est toujours `patchmatch`, jamais générative ; `RetouchAreas` se
  dérive de `RemoveAreas` (`preparerTaches`).
- Positions données dans l'image de `view_photo` : toute nouvelle position passe par
  `Geometrie.lua` (recalage `Recalage.swift`, `Tools+Recalage`).
- Une écriture qui touche la géométrie d'une photo redressée coche « Contraindre le recadrage »
  (`preparerContrainte`) ; le cadre est mémorisé avant et relu après (`relireCadres`), car
  Lightroom le change sans qu'on l'écrive.

## Recherche par le sens (1.6)

- MobileCLIP S2 en CoreML (`Sens.swift`), tokeniseur de CLIP en Swift (`TokeniseurCLIP`, vérifié
  par `Tests/Contrats/jetons-clip.json`), index par catalogue hors du catalogue (`IndexSens.swift` :
  vecteurs fp16 contigus et SQLite), rempli par `--analyser` pendant le Suivi ; `find_photos` avec
  `query` ou `similar_to` (`Tools+Sens.swift`, `docs/SPEC.md`). `ToolHandler.sens` et le `sens` de
  `Suivi.analyser` sont nil par défaut : seul main.swift pose le vrai modèle, jamais `swift test`.
- Les dates d'une recherche par le sens se filtrent d'après l'index (le module refuse un filtre de
  date seul) ; le module reçoit `parmi` et répond `parmi = true`. Le chemin du catalogue ne part
  jamais chez Claude. Le seuil de pertinence est provisoire (`--sens-essai`).
- **Jamais de compilation ni d'ouverture du modèle dans le délai d'une photo** : `--compiler-sens`
  compile (install.sh, le Suivi sous sa propre alarme) ; `--analyser` ouvre l'encodeur et l'index une
  fois avant les mesures (`Suivi.delaiOuvertureSens`), et sans eux ne rend pas `regles_sens` ;
  l'empreinte se calcule après les défauts, qui restent si elle est en retard. `--sens-etat`
  n'annonce qu'un modèle compilé qui s'ouvre. L'index porte une `generation` (refait : une autre).
- `find_photos` par le sens passe les candidates au module par tranches de `Sens.candidatsMax`
  jusqu'à remplir la page (`Sens.tranchesMax`), et dit un total minimum ou une liste coupée.

## Espèces (BioCLIP 2, 1.6.3)

- BioCLIP 2 en CoreML (`Especes.swift`, `Tools+Especes.swift`), converti par
  `scripts/preparer-bioclip.sh` (cosinus avec PyTorch d'au moins 0,99, sinon rien d'installé), lu par
  `EncodeurMobileCLIP` (même tokeniseur, `Tests/Contrats/jetons-bioclip.json`). La liste
  (`Resources/especes/especes.tsv`) n'existe qu'à un endroit : un nom douteux se retire, jamais ne se
  devine ; ni doublon ni cultivar (`EspecesTests`). Ses vecteurs se gardent
  (`Modeles/bioclip2_especes.cache`), refaits quand la liste ou le modèle changent.
- `ToolHandler.especes` est nil par défaut : seul main.swift pose le vrai modèle, jamais `swift test`.
  Sans lui, `species` refuse sans rien envoyer au module.
- BioCLIP 2 ne sait pas dire qu'une image ne montre rien de vivant : la porte MobileCLIP
  (`Especes.porteNature`) passe d'abord ; sans elle, la réponse le dit (`remarqueSansPorte`). Tous
  les seuils sont provisoires (`--especes-essai`).
- `find_photos` avec `species` : les autres critères seuls d'abord, s'ils gardent au plus
  `candidatsMax` photos (toutes examinées, indexées ou non) ; sinon l'index du sens, par tranches,
  et la réponse dit que les photos pas encore analysées ne sont pas examinées. `view_photo` lit le
  carré central (`lu_sur`).
- Un mot-clé d'espèce ne s'écrit jamais sans l'accord de Dany ; `view_photo` ne dit l'espèce que sur
  demande (`species`), jamais sur un avant/après.

## Catalogue et notation

- Le catalogue des réglages (noms, plages, libellés) n'existe qu'à un endroit :
  `Sources/DeveloppeurKit/Catalogue.swift`. Le serveur envoie au module les plages et les
  libellés de chaque commande ; le module ne connaît que les plages de la température et de la
  teinte, qui dépendent de la photo (kelvins pour un RAW, relatives pour un JPEG).
- **Les plafonds de dose n'existent qu'à un endroit** : `DevelopCatalogue.plafondsDose` (Clarté,
  Voile, Texture, Vibrance ; la Saturation suit `saturationMax` du Gestionnaire), envoyés en
  `plafonds` ; le module les juge sur la valeur finale, en valeur absolue (`Plans.verifierDoses`),
  et refuse avant toute écriture sans `strong_dose_requested` (`dose_forte`), posé seulement sur
  demande de Dany, de son guide ou de la recette d'un style qu'il a choisi.
- **Le standard de notation n'existe qu'à un endroit** : `Notation.standard`. La fenêtre ne lit ni
  ressources ni invites : elle l'a par `read_standard` seulement. Des yeux fermés ne font rejeter
  que si une autre vue de la rafale ou de la pile les a ouverts ; le tri d'une seule photo n'en
  rejette jamais ; sans défaut, aucun plafond sous 5. Échelle resserrée d'une étoile (1.4) : dans le
  doute, la plus basse ; les notes posées avant gardent l'ancienne échelle.
- **Claude note de 0 à 5 ★, jamais un libellé de couleur sans demande** : les coups de cœur de Dany
  sont un libellé de couleur qu'il pose lui-même ; Claude n'en propose, n'en pose ni n'en change
  jamais sans sa demande explicite. Jamais `set_metadata` pour une note sans demande.
  `propose_ratings` écrit avec `apply` (hors de `readOnlyTools`), valide tout avant d'envoyer (clés
  de chaque élément à la main), refuse une note au-dessus du plafond du dernier tri sans `to_check`,
  et sa commande `notation` reste hors de `LightroomBridge.lectures` (rejouée, elle remettrait les
  propositions « à vérifier »).

## Mises à jour par le SSD (1.7)

- `Installation.swift` (`--mises-a-jour`) est le seul à écrire dans `<dossier commun>/Installation`
  et son `manifeste.json` ; le module et les scripts passent par lui. **Jamais de téléchargement à
  l'installation** : mflux par `--offline`, Python par le miroir `file://` du SSD, mandataire mort ;
  seul le dépôt de mflux remplit son cache en ligne, dans des dossiers d'outils temporaires.
- Toute copie par « .partiel » renommé ; un arbre (modèles, SAM 2) ne retire rien (sauf nos
  « .partiel » orphelins) et garde un fichier déjà complet, sauf un fichier marqué (`refs/*`, SAM 2 :
  contenu et date, le plus récent l'emporte) ; un instantané se compare fichier par fichier ; mflux
  s'installe avec l'uv qui a rempli son cache (`mflux/uv`) ; place, mflux en cours, Fibo 2 Studio ouvert et verrou vérifiés avant. Les modèles
  copiés sont ceux de `Installation.depotsHF` seulement, en suivant leurs liens (blobs partagés).
- Les tests passent un domicile, des applications, un faux uv et des vérifications simulées
  (`InstallationTests`) ; jamais le vrai `~`, ni `/Applications`, ni le vrai cache. Un essai à la
  main : `DEVELOPPEUR_DOMICILE` et `DEVELOPPEUR_APPLICATIONS` vers des dossiers temporaires, jamais
  `--installer developpeur` (son install.sh inscrit le connecteur dans le vrai Claude Desktop).
