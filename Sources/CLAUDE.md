# CLAUDE.md — serveur et mesures (Swift)

Règles du serveur MCP-Développeur et de ses mesures, sorties du CLAUDE.md principal, qui garde
les règles communes à tout le projet.

- **`PriseDeVue.defauts` est la seule liste des défauts de la prise de vue** (17 codes depuis le
  correctif 1.3.7, 16 avant ; domaine du carnet, six mesurés ; plus d'axe ni de clé anglaise depuis
  le correctif 1.3.6 ; `yeux_fermes`, nouveau au correctif 1.3.7, domaine netteté, après
  `mise_au_point`, `mesure` faux : le Suivi le compte d'après `--analyser`, le carnet de
  `view_photo` ne le cherche pas ; les dix autres non mesurés gardés pour les leçons d'avant
  rangées dans `carnet.json`) ; `PriseDeVue.vocabulaire` part avec
  chaque constat : aucune liste de défauts dans le module. `ToolHandler.descriptionRaison` (la description de `reason`, répétée dans
  chaque outil qui écrit) fait 160 caractères au plus, comme `descriptionRaisonProposition`, celle
  de `preview_settings` depuis la 1.3.1 (Claude y joignait `reason` 3 fois sur 4 et l'appel était
  refusé ; elle ne promet pas le journal). Une proposition n'écrit rien : sa raison
  ne part jamais au module (ni étape ni journal), elle revient dans la réponse (`raison`), à
  redonner à `apply_settings`. `ToolHandler.raison` la nettoie et la borne (300 caractères).
- **La composition se lit sur l'image entière** (`Composition.swift`, `Tools+Composition.swift`,
  `Rendu.lua`) : l'image entière se rend par l'écriture temporaire du cadre retiré
  (`sansRecadrage` : `Recadrage.AUCUN` et la case décochée), puis le retour, comme le recalage (deux
  étapes « Claude · composition ») ; une photo agrandie est refusée avant toute écriture ; un
  module qui ne rend pas `image_entiere` est refusé. Les positions de `view_photo` passent par
  `Composition.versImageEntiere` d'après `cadre_actuel` ; l'horizon se mesure sur l'image entière
  (angle absolu) ; le dessin suit le cadre que Lightroom a gardé, relu (`cadre_propose`), jamais la
  demande ; la marge de 0,998 sert aux arrondis du module (validée le 21 octobre 2026). Seuils
  relevés le 21 octobre 2026 : `roulisRenverse` 3π/4 (un visage à l'envers n'est ni le sujet ni le
  regard), `zoneInteretMax` 0,5 (au-delà, pas de sujet), `signeLacet` +1 confirmé, `seuilLacet`
  0,26 gardé, `LineAngle.ecartMax` 3 px (au-delà, la ligne n'est pas « affinée », l'angle vient des
  deux points), tiers à 0,35 % (`PreviewImages.traitTiersPart`), cadre à 0,4 %. Le contrat est figé
  dans `Tests/Contrats/composition.json`.
- **Mise au point jugée sur de la texture** (`Detail.autour`, relevé le 21 octobre 2026 sur les
  copies d'Essais) : sous `DetailMeasurements.textureMin` (18 : sable lisse, ciel uni), la mise au
  point est « non jugée » (pas de plafond, pas de constat au carnet sauf si l'appareil l'a
  signalée) ; jusqu'à `textureDouteuse` (30 : le bord d'un nuage), une mise au point manquée n'est
  qu'un doute : 1 (2 avant l'échelle resserrée de la 1.4), à vérifier, sans rejet proposé (`Notation.plafond`), et le carnet ne la compte
  pas. À relever sur un mur, de la neige et une vraie mise au point manquée avant de les changer.
- `match_series` compare la photo et la référence par la même mesure des tons neutres ; les tons
  suivis d'une passe à l'autre (`Measurements.neutres` avec masque) ne servent qu'aux pentes, et
  Teinte et Température se résolvent ensemble (`PentesSerie`, relevées dans Lightroom). Chaque
  photo repart des pentes relevées.
- **Harmoniser par lumière** (1.4, `GroupesLumiere.swift`, `Tools+Lumiere.swift`) : `match_series`
  avec `groups` (sans `reference_id`, refusé avec lui) mesure les vignettes de toute la sortie comme
  `cull_photos` (`ToolHandler.mesurer`, `maxPhotosSortie` 2 000), sans ouvrir aucun original (la
  description perd `geometrie` avant la mesure : pas de point de mise au point), puis
  `GroupesLumiere.former`, pure : dans l'ordre de prise de vue (les photos sans date après, dans
  l'ordre donné, `sansDate`), une photo commence un groupe quand le flash change (deux connus), quand
  la lumière de la scène (`Prise.lumiere`, IL à 100 ISO : log2(N²/t) − log2(ISO/100) + compensation ;
  pas pour une photo au flash, ni contre une photo au flash) s'écarte de `ecartIL` (2,5) ou plus de la
  médiane des `fenetreLumiere` (5) dernières du groupe (un coucher de soleil qui baisse peu à peu
  reste un groupe), ou après une pause de plus de `pauseMax` (10 min), sauf même lieu (empreinte de
  Vision à moins de `distanceMemeLieu`, 0,7, de l'une des `fenetreLieu`, 3, dernières) dans
  `pauseMemeLieu` (1 h) ; deux boîtiers restent ensemble ; seuils provisoires, à relever sur la sortie
  de l'essai. La référence proposée (`GroupesLumiere.reference`) : sans défaut mesuré si possible,
  une photo déjà retouchée par Claude (`retouchee_par_claude` de la description), sinon la mieux
  classée au tri (`PhotoTriee.score`) parmi celles qui ont un visage plausible d'au moins
  `Teint.visageMin`, sinon parmi toutes ; un groupe de plus de `maxMatchedPhotos` (60) dit ses lots ;
  une photo seule sous sa lumière va dans `photos_seules`. Rien n'est écrit : le plan seulement
  (`planDesGroupes`). La prise de vue vient de la description des vignettes : `prise_de_vue` du
  module (1.4 : `aperture`, `shutterSpeed`, `exposureBias` et `flash` de `getRawMetadata`, un
  booléen ou rien), `sensibilite` et la date ; `view_photo` retire `prise_de_vue` avant Claude.
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
  pèserait 0,9 Mo, texte et forme structurée), et, avec `offset` (sélection, collection, dossier), la tranche suivante ; une sélection plus
  longue n'est plus refusée (`parTranches` de `seriesPhotosSansVideos`), `photos_non_triees` dit
  l'`offset` suivant ; une rafale à cheval sur deux tranches s'y coupe. La commande `selection` du
  module prend `decalage` et le redit dans sa réponse (un module d'avant décrit le début : le
  connecteur la redemande une fois assez loin, `decalage` plus la tranche, et saute lui-même les
  premières) ; `chercher` décrit jusqu'à 2 000 photos (`MAX_RESULTATS` de `Bibliotheque.lua`, 500
  avant ; `find_photos` s'arrête toujours à `maxSearchLimit`, 500). Les groupes de lumière comparent le
  flash à la dernière photo du groupe qui le dit (deux boîtiers mêlés, l'un sans flash lu), et une
  photo seule dit ce qui la sépare avant et après elle (trouvailles de la relecture du 26 octobre
  2026 ; une vignette trop petite y est rendue comme un aperçu, comme au tri).
- **Noter une grande sélection** (1.4, constaté le soir du 26 octobre 2026 : « note la série » sur
  951 photos, par la Demande rapide, n'en notait que 24) : Claude Code range une réponse d'outil de
  plus de 25 000 jetons (son défaut) dans un fichier, et Claude ne peut rien lire dans la fenêtre
  (`--tools ""`) ; le tri de 951 photos faisait 147 000 caractères, dont 80 % de `plafonds`, une
  ligne par photo, et `list_selection` à 500, 168 000. `relais.sh` pose donc
  `MAX_MCP_OUTPUT_TOKENS=100000` (essai de bout en bout de `tests.lua`, par `faux-claude.sh`) ; au-delà
  de `Tri.plafondsParPhotoMax` (100) photos, le tri dit `plafonds_par_motif` à la place de `plafonds`
  (les photos de chaque plafond regroupées par `Notation.Plafond.motif`, la raison sans les mesures de
  chaque photo ; 43 000 caractères estimés pour ces 951 photos, 27 motifs), le plafond de chaque
  photo restant gardé pour `propose_ratings` (`dernierTri`) ; `contact_sheet` prend une sélection plus
  longue que sa planche dès l'offset 0 (`parTranches` ; refusée jusque-là, alors qu'un offset de 30
  passait), et sa suite compte les vidéos écartées (`decalage` + photos + vidéos : sans elles, des
  photos revenaient d'une planche à l'autre), une tranche faite de vidéos seulement donnant la suite au
  lieu d'une erreur ; sa réponse dit `planche` (`premiere`, `derniere` : positions dans la série,
  vidéos comprises ; `sur`), sauf pour `photo_ids` ; les consignes de la fenêtre (puce Notes, `Consignes.rapide`, `Consignes.noterRapide`)
  disent de noter plus de 30 photos planche par planche (`contact_sheet` avec `selection` et `offset`,
  puis `propose_ratings`), jusqu'à la dernière dans le même tour (la planche suffit pour confirmer les
  rejets du tri), sans `list_selection` pour les parcourir ; `Consignes.rapide` ne dit plus « sans
  suite » (Claude, Haiku à l'effort bas, renonçait alors à noter les 951 photos après le tri, reçu
  en entier : « je ne peux pas le faire fidèlement dans cette demande sans suite »), mais de faire la
  demande en entier dans le tour, même longue. Essais :
  `GroupesLumiereTests` (plafonds par motif, première planche d'une grande sélection, vidéos sautées).
  Trouvailles d'une relecture adverse du même soir (vidéos, planche de vidéos, ligne d'état), corrigées.
- L'intention de la prise de vue (`IntentionBoitier`, lue par `LectureBoitier` dans la MakerNote et
  l'Exif : simulation de film, couleur, plage dynamique et sa priorité, tons clairs et foncés,
  compensation, mode, balance, scène) se lit seulement : `view_photo` la donne sur l'aperçu entier
  (`intention_boitier`, avec sa `lecture`), jamais sur un zoom ni un avant/après, et rien n'est
  posé d'office. Un RAW n'en reçoit que la simulation, par son profil Lightroom (`profilLightroom` :
  DCP du catalogue ou Look installé), en première passe, sauf autre style demandé ou guide de style
  contraire ; un JPEG de l'appareil porte déjà simulation, plage dynamique et tons (ne pas les
  refaire) ; une compensation de −0,6 IL ou moins dit une photo voulue sombre, à ne pas remonter
  (seuils de ±0,6 IL provisoires). Recoupé le 20 octobre 2026 sur de vrais RAF (X-H2S, X-T4,
  X-T20), MakerNote lue à la main ; un HEIF de l'appareil n'est pas lu.
- Le point de mise au point dans `view_photo` (Fujifilm, lu par le serveur dans l'original,
  `Boitier.swift`, et placé dans l'image affichée, `PointAF.swift`) : un aperçu entier ou un zoom
  (`region`), jamais un avant/après (`compare`), envoie `point_af = true` à la commande `apercu` ;
  le module décrit alors la photo comme pour les vignettes (`Vignettes.decrireVignette` :
  `chemin_original`, `marque`, `geometrie`) et ajoute `point_af_toujours` (préférence
  `pointMiseAuPoint`), `evaluation` (`Notation.resume`) et, pour le bilan, `etapes_claude`
  (`nombre`, `derniere`) ; le serveur retire `chemin_original`, `geometrie`, `marque`,
  `point_af_toujours` et `etapes_claude` avant de répondre à Claude. Réponse : `point_af` { `x`,
  `y` (dans l'image affichée entière, de 0 à 1, sur un zoom aussi), `dans_la_zone` (zoom
  seulement), `nettete` (autour du point ; sur un zoom, dans le zoom, si le point y tombe),
  `appareil` (« mise au point signalée manquée »), `carre` (s'il est dessiné : « cadre AF rouge,
  point au centre » depuis le correctif 1.3.3, `ToolHandler.cadresAF` et
  `PreviewImages.marquerFocus`, sinon « vert » ou « rouge », puis « sur l'image » ou « sur le
  zoom ») }. Le carré (vert,
  rouge si l'appareil a signalé la mise au point manquée ; côté 6 % du petit côté, liseré sombre ;
  `PreviewImages.marquerPoint`) se dessine avec `af_point = true` (pour noter, ou montrer la mise
  au point) ou si la case « Mise au point » de la section de la liaison du Gestionnaire est cochée
  (`pointMiseAuPoint` de `Preferences.lua`, décochée par défaut) ; sur un zoom (demandé par Dany
  le 20 octobre 2026), seulement si le point tombe dans la zone. Mesures et Vision sont prises
  avant le carré. Un seul lecteur pour `view_photo` (`ToolHandler.lecteurBoitier`), qui lit le
  point et l'intention d'une seule ouverture : une lecture bloquée n'en lance pas d'autres. Les
  consignes de la fenêtre (`Consignes.texte`) ont leur puce :
  « Mise au point montrée ou jugée : view_photo avec af_point = true, sur l'aperçu entier comme sur
  un zoom (region)… ».
- Un masque combiné range chaque composant avec `MaskBlendMode` (0 ajouter, 1 soustraire) ; une
  intersection est une soustraction du composant inversé (`Locaux.combiner`).
- Formes constatées des masques récents (voir `docs/SPEC.md`, Retouches locales) : objet en
  rectangle = `Mask/Polygon` dont les `Points` sont des tables `{X, Y}` ; plage de couleurs =
  `PointModels` « c1 c2 c3 x y 0 », modèle Lab étalonné (`ModeleCouleur`) ; plage de profondeur =
  `Type = 3` et `DepthRange` de 0 à 1 (jamais `DepthMin`/`DepthMax`) ; couleurs ponctuelles d'un
  masque = `LocalPointColors`, des textes de 19 nombres ; dégradé radial = `Mask/CircularGradient`
  avec `Flipped = true` toujours, inversé par `MaskInverted` seul (`Locaux.radial` ; inversé, il
  n'agit que hors de l'ellipse : coins −31 à −69, centre −0,3 sur 255, à −2 IL sans fondu ; non
  inversé, centre −45 ; constaté le 20 octobre 2026), y compris en composant combiné, en copie
  inversée d'`edit_mask` et copié vers une autre photo. La simulation vérifie chacune (pour le
  radial : `Flipped == true` et un `MaskInverted` booléen). La forme d'un radial fait à la main
  n'est pas relevée, ni l'effet d'un radial sans `Flipped`.
- Le dosage de la peau n'existe qu'à un endroit : `Peau` (`Peau.swift` : `parDefaut`, « Peau du
  visage lisse », texture −20 et clarté −10 ; `lite`, « Adoucir la peau (Lite) », −35 et −15 ;
  `intensiteReduite`, `amount` 50 pour un homme ou une personne âgée ; rien pour un enfant ;
  `dosage`, `effetsIntegres`), d'après les fichiers d'Adobe et non son aide (relevés le 20 octobre
  2026, Lightroom Classic 15.6). La description d'`effect` d'`add_mask` et l'invite `portrait`
  reprennent `Peau.dosage` ; `Consignes.lua` y renvoie sans chiffres. Les deux effets intégrés
  viennent après ceux des fichiers (`LocalEffectLibrary`), qui l'emportent. `add_mask` refuse,
  avant tout envoi (proposition comprise : un refus n'envoie aucune commande), un masque de peau
  (`face_skin`, `body_skin` ; en premier composant non inversé, ou en composant qui la garde :
  `Peau.surLaPeau`) au-delà de la dose Lite, intensité comprise, ou à netteté négative, sans
  `smoothing_requested`, qui ne se pose que sur demande de Dany ou de son guide de style
  (`Peau.verifier`, dans `maskParameter`, qu'`add_mask` seul appelle : ni `copy_settings`, ni
  `edit_mask`, ni `match_series`). L'intensité d'un masque (`CorrectionAmount`) est linéaire
  (constaté le 20 octobre 2026, en propositions sur la peau d'un portrait : texture −20 et clarté
  −10 à `amount` 50 rendent la même image, au pixel près, que −10 et −5 à 100 ; de même pour
  « Adoucir la peau (Lite) ») : un constat de rendu, sans règle possible dans la simulation, que
  vérifie l'étape « intensité d'un masque » de `--portrait`. Vision ne dit ni le genre ni l'âge
  d'un visage : Claude juge à l'œil, et dans le doute prend la dose la plus faible.
- Les doses et la forme d'éclaircir et assombrir (méthode du tireur) n'existent qu'à un endroit :
  `Prompts.Tireur` (grandes zones trop claires par un dégradé linéaire, −0,3 à −0,7 IL ; sujet
  éclairci par un radial, +0,2 à +0,4 IL ; bords par un radial inversé, −0,3 IL, −0,5 au plus, en
  ellipse du cadre de rayon 0,7 et de fondu 80, au milieu de la `zone_d_interet` de Vision ; un seul
  `add_mask`, étape « Claude · éclaircir et assombrir »). Les invites `portrait`, `paysage` et
  `noir_et_blanc` les reprennent (`Tireur.methode`), `retouche_pro` y renvoie, et la description
  d'`add_mask` aussi (`Tireur.resume`), car la fenêtre Claude ne lit pas les invites : ses boutons
  Portrait, Paysage et Noir et blanc demandent la méthode sans chiffres, et `Consignes.texte` n'en
  dit rien. Le radial inversé remplace le vignetage après recadrage, jamais les deux (rien si la
  photo porte déjà `PostCropVignetteAmount` ou si le guide de style écarte le vignetage) ; l'étape
  se vérifie par `view_photo` avec `compare = previous_step`. Les doses viennent de la feuille de
  route, sans mesure : ce sont des plafonds. La forme des bords a été relevée le 20 octobre 2026
  sur un seul paysage, radial centré, en propositions à −0,5 IL (rayons 0,6 à 0,75, fondus 50, 80
  et 100 : centre jamais touché, baisse sans marche ; rayon 0,7 et fondu 80 : tiers central
  intact, milieu des bords −16 sur 255, coins −21 à −27 ; fondu 100 : presque tout le cadre ;
  fondu 50 : les seuls coins). L'étape « forme des bords » de la recette la mesure telle que Claude
  la pose (au milieu de la zone d'intérêt, à −0,3 et −0,5 IL : centre intact, ni plaque ni anneau).
  Restent à juger à l'œil cette forme sur un portrait et un intérieur, et le fondu du radial du
  sujet (80 à 100 : ni halo, ni peau écrêtée).
- Les seuils de netteté et de bruit (`DetailMeasurements.seuilFlou` 15, `seuilNet` 35,
  `bruitVisible` 0,6, `bruitFort` 1,5, et depuis la 1.3 `textureMin` 18 et `textureDouteuse` 30 :
  `Detail.swift`), de ressemblance et d'ouverture des yeux
  (`AnalyseVision.swift`) et de l'éclairage mixte (`Eclairage.chromaMax` 12, `seuilMixte` 8) ont été
  relevés sur de vrais aperçus : les mesurer de nouveau avant de les changer. Ceux de la dominante
  et de la saturation sont nommés aussi, sans relevé noté dans le code
  (`PhotoMeasurements.partNeutreMin` 3, `dominanteLegere` 2, `dominanteNette` 6, `chromaTresSaturee`
  60 ; `Measurements.seuilChroma` 3). Le tri et les plafonds de note (`Notation.plafond`) les
  reprennent sans en ajouter, comme l'analyse d'office du Suivi (`Suivi.analyser`, correctif 1.3.7 :
  la photo « brûlée » du tri au-delà de `PhotoTriee.partBlancPurBrulee`, 35 %, y fait la
  surexposition, et les yeux fermés ne s'y cherchent que s'il y a des `sujetsAuxYeuxLus`, les
  sujets de `yeuxFermes` et de `yeuxOuverts`) ; `analyze_photos`, l'éclairage et le bilan les reprennent aussi, avec
  leurs propres seuils (puces suivantes). Au tri, une pile de Lightroom compte comme une rafale
  (seule sa meilleure vue échappe au plafond de 2 ★, 3 ★ avant l'échelle resserrée de la 1.4). Le tri (`cull_photos`) mesure les vignettes
  du cache de Lightroom (commande `vignettes`) et ramène leur netteté à celle d'un aperçu exporté
  (`thumbnailSharpnessFactor`, relevé ; le 21 octobre 2026, le tri donnait encore 11 à 23 % de plus
  que l'aperçu, en classant pareil : gardé). Vision ne s'appelle pas en grand parallèle
  (`concurrentPerform` l'a bloqué) : deux photos à la fois au plus.
- L'éclairage (`Eclairage.swift` : `mesures › eclairage` de `view_photo` ; forme courte dans
  l'avant/après, les propositions et `analyze_photos`) se lit sur les tons presque neutres pris
  autour du gris ; quand une dominante globale en écarte le point neutre de l'image (médiane a*, b*
  de ses tons peu saturés) de plus de `toleranceNeutre` (10), autour de ce point ramené de 10 vers
  le gris (`Eclairage.centrer`) : une borne absolue (C* < 12) ne lisait plus aucune case sous une
  autre balance (0 sur 9 pour le portrait à 3 200 K, constaté le 20 octobre 2026). Par zone tonale
  et par case 3 × 3, visages à part (leur peau, et la lumière autour) ; deux groupes de cases
  écartés de `seuilMixte` (8) ou plus font un éclairage mixte, avec `balance_proposee` sur la
  lumière des visages ou du sujet, par les pentes de `match_series` (`ToolHandler.balanceProposee`,
  depuis la réponse brute d'`apercu`). `chromaMax` 12 et
  `seuilMixte` 8 relevés le 20 octobre 2026 sur les 8 copies d'essai (`--eclairage`) : seul le
  portrait à deux lumières ressort (9,8), les autres de 2,2 à 7,1 ; à 15 et au-delà, des objets
  colorés pris pour des gris font de faux mixtes. Avec la tolérance, relevé le 21 octobre 2026
  (`--eclairage`, à la balance de la photo et avec `--essai`) : l'œil tenu à la balance de la photo
  (portrait 9,7, les autres de 2,1 à 7,1) et à 6 500 K ; sous une dominante forcée extrême, la
  mesure peut perdre une lumière (portrait à 3 200 K : 4,6) ou en inventer une (intérieur à la
  lampe à +30 : 11,4) : son conseil dit « à confirmer à l'œil ». `toleranceNeutre` (10), choisie
  hors de Lightroom sur cinq aperçus, est la seule valeur essayée à ce relevé (son commentaire la
  dit encore à relever) ; `seuilTonal`, `partMinGroupe` et `pixelsMinPeau` restent provisoires.
  Mesure en 123 à 199 ms par photo à ce relevé.
- Le bilan de `view_photo` (`Bilan.swift`) compare l'aperçu entier au précédent de la même photo à
  la même taille d'aperçu, et au premier de la session (`depuis_le_debut`) : `vuesMesurees` de
  `ToolHandler`, rangé par `Bilan.Cle` (photo et taille), gardé pour le processus du serveur comme
  `dernierTri` (30 au plus, `Bilan.photosGardees`) ; une autre taille repart de zéro et le dit
  (même état à 1 024, 1 344 et 2 048 px : netteté jusqu'à 10 % d'écart ; deux vues de suite à la
  même taille : les mêmes 43 mesures ; constaté le 20 octobre 2026). Jamais une proposition contre
  une vue gardée (le même jour, une proposition sans changement s'écartait d'une vue jusqu'à
  0,9 point d'écrêtage ; mesurées depuis par le même chemin, l'écart qui reste est à relever) :
  une proposition avec `compare` (`preview_settings`, `add_mask` avec `preview`) et `view_photo`
  avec `compare` ont leur propre bilan, sur deux images rendues par la même commande ; netteté et
  bruit seulement entre deux vues. Toute image se mesure par un décodage et la réduction à 512 px
  (`ToolHandler.mesurerImage`, comme `analyzeScaled`). Les tons neutres ne se suivent qu'à cadre
  égal (`Bilan.cadre`). Une annulation (`etapes_claude` en baisse, que `Rendu.apercu` donne en
  lecture seule) ou un calcul IA en attente ne donne pas de « regression » : elle passe dans
  `a_verifier`. Un zoom refait sur la même zone a son `bilan_zone`, sans alerte (`zoomsMesures`,
  6 par photo, 30 photos). Seuils de visibilité repris de `match_series`, de
  `Measurements.seuilChroma` et de `Detail` ; seuils de régression relevés le 20 octobre 2026 en
  propositions (écrêtage, un canal, couleurs très saturées : 2 points de plus et 1,5 fois l'avant ;
  ombres bouchées : 2 points de plus, une nuit n'alerte pas d'elle-même ; dominante des tons
  neutres : |a*| ou |b*| qui s'éloigne de 0 de 2) ; ceux de la netteté et du bruit
  (`baisseNetteteMin`, `hausseBruitMin`, `ecartNettetePct`, `ecartBruit`…) restent à relever (étape
  « bilan chiffré » de la recette).
- L'écran principal du Mac (`Ecran.swift`) se lit par CoreGraphics et ColorSync, sans AppKit ni
  permission (environ 44 ms) ; l'en-tête ICC se lit dans les octets du profil
  (`ColorSyncProfileCopyHeader` rend ses signatures à l'envers, « lppa » pour « appl », constaté le
  20 octobre 2026). Six classes (`Ecran.Etalonnage`) : un profil d'usine (`FactoryProfiles`, tiré
  de l'EDID, rangé dans `/Library/ColorSync/Profiles/Displays` et refait à chaque branchement), un
  profil standard du système et un profil fait à l'œil ne sont jamais « mesurés », et la balise
  `meas` n'est pas un indice (`sRGB Profile.icc` du système la porte) ; `mesure` ne vaut vrai que
  pour un profil qui nomme un logiciel de sonde, ou dont la balise `vcgt` vient d'un créateur autre
  qu'Apple, et reste inconnu (« étalonné ? ») pour un autre profil personnalisé. Aucun vrai profil
  de sonde n'est encore relevé. **Plus rien sur l'étalonnage** depuis le correctif 1.3.6 (décision
  de Dany du 25 octobre 2026 : il n'achètera jamais de sonde) : ni Dany ni Claude n'en entendent
  parler. Le classement (`Ecran.Etalonnage`, `mesure`, `Ecran.texte`) ne sert plus qu'à
  `mcp-developpeur --ecran`, pour le développement (`Ecran.json`, sans la clé `detail` :
  `Ecran.detail` et `Ecran.reglageProfil`, le seul conseil d'une sonde, sont retirés avec le
  voyant). Seul
  `main.swift` pose `Ecran.lire` (les outils de `serve` et de `--call`, et la recette pour son étape
  « écran nommé ») ; seul `get_status` le lit, et ne dit que les noms (`Ecran.nommer` :
  `ecran: { nom, autres }`, `autres` seulement s'il y en a ; ni profil, ni chemin, ni `etalonnage`,
  `mesure`, `texte`, date ou logiciel), sa description seulement « ecran : le nom de l'écran
  principal du Mac. » ; `--status` dit les noms seuls.
  `ServerInfo.instructions` n'en a jamais parlé. `EcranTests` vérifient qu'aucune description
  d'outil ni `ServerInfo.instructions` ne parlent de sonde ou d'écran non étalonné, et qu'aucun
  aperçu ne lit l'écran (`testAucuneRemarqueDEcranAuxApercus`).
- Une longue série passe par le `ContexteAppel` de l'outil : `avancer` (de `ToolHandler`) après
  chaque lot (progression envoyée au client, reprise dans la réponse d'attente, et barre de
  progression de Lightroom par la commande `progression`, fermée à la fin de l'appel par
  `fermerBarre`), `verifier` avant chaque lot (annulation par `notifications/cancelled`, sans
  réponse ; croix de la barre de Lightroom, `ArretDansLightroom`, avec une réponse).
- Une photo qui porte `RemoveAreas` (outil Supprimer à détection d'objet) est lue par là, et
  `RetouchAreas` en est dérivé : les taches de Claude vont dans les deux (`preparerTaches`). Une
  tache Supprimer de Claude est toujours `fill_method = 'patchmatch'`, jamais générative.
- Les positions des masques et des taches se donnent dans l'image que montre `view_photo` ;
  `Geometrie.lua` les ramène dans le repère du fichier. Toute nouvelle position passe par lui.
  Ce repère est celui d'avant la correction d'objectif, Upright et la perspective : le serveur
  calcule une grille de recalage sur deux rendus (`Recalage.swift`, commande `geometrie`), que
  `Geometrie.lua` interpole ; toute commande qui place des positions la demande
  (`Tools+Recalage`).
- Upright, la perspective et la distorsion manuelle laissent des coins vides dans le cadre : toute
  écriture qui touche la géométrie ou le cadre d'une photo redressée coche « Contraindre le
  recadrage » (`preparerContrainte`), qui fait resserrer le cadre par Lightroom ; le cadre est
  mémorisé avant (Lightroom le change sans qu'on l'écrive) et relu après (`relireCadres`). Un
  cadre demandé se calcule dans la zone que la grille de recalage dit remplie (`Geometrie.zone`) ;
  demandé avec Upright, il se place ensuite (`a_recadrer`, commande `recadrer`, qui complète la même
  étape). Les rendus du recalage décochent la case. Voir `docs/SPEC.md`, Contraindre le
  recadrage.
- Le catalogue des réglages (noms, plages, libellés) n'existe qu'à un endroit :
  `Sources/DeveloppeurKit/Catalogue.swift`. Le serveur envoie au module les plages et les
  libellés de chaque commande ; le module ne connaît que les plages de la température et de la
  teinte, qui dépendent de la photo (kelvins pour un RAW, relatives pour un JPEG).
- Le standard de notation n'existe qu'à un endroit : `Notation.standard`
  (`Sources/DeveloppeurKit/Notation.swift`). La ressource `developpeur://notation`,
  `propose_ratings` avec `read_standard` et l'invite `noter` le reprennent ; Claude Code dans la
  fenêtre ne lit ni les ressources ni les invites (`--tools ""`, `--disable-slash-commands`) : il
  l'a par `read_standard` seulement (ses consignes l'y renvoient) ; l'invite `noter` (la sélection
  par défaut) sert à Claude Desktop et à Claude Code en terminal.
  `Notation.plafond` en tire les plafonds de `cull_photos` (0 et rejet proposé pour une photo
  floue, une mise au point manquée, ou des yeux fermés quand une autre vue de sa rafale ou de sa
  pile les a ouverts, `PhotoTriee.yeuxOuverts`, `autreVueYeuxOuverts` ; la règle de la rafale,
  correctif 1.3.4 : sinon 1, à vérifier, la seule vue de son moment ne se jetant pas pour un
  clignement, et le tri d'une seule photo, la note d'abord de la fenêtre, n'en rejette jamais ;
  2 pour une photo douce, à la mise au point signalée manquée, ou qui n'est pas la
  meilleure de sa rafale ; 1, à vérifier, pour une photo presque noire ou brûlée, ou une mise au
  point manquée sur une texture faible, 1.3 ; 1 pour une capture), que `dernierTri`
  (`ToolHandler`) garde pour le processus du serveur ; sans défaut, aucun plafond sous 5 (« aucun
  défaut mesuré : pas de plafond », correctif 1.3.2). **L'échelle resserrée d'une étoile** (1.4,
  26 octobre 2026, demandé par Dany : « je trouve que tu notes élevé », « tout baisser d'une
  étoile », « mais tu peux toujours donner un 5 étoiles ») : 1 ★ gardée, correcte (l'ancien 1 ★ et
  l'ancien 2 ★) ; 2 ★ tient seule (l'ancien 3 ★ ; un bon souvenir bien fait n'y suffit pas) ; 3 ★
  l'impact (l'ancien 4 ★) ; 4 ★ à côté des meilleures (l'ancien 5 ★) ; 5 ★ l'exceptionnel, très rare ;
  dans le doute, la plus basse ; les plafonds descendent d'une étoile (ceux d'avant : 3 et 2) ; les
  notes posées avant gardent l'ancienne échelle ; `Fenetre.SENS_NOTES` suit (« Gardée », « Tient
  seule », « A de l'impact », « Parmi vos meilleures », « Exceptionnelle »). Relevé du registre le
  même soir : sur 345 propositions, 16 % de rejets, 12 % à 1 ★, 55 % à 2 ★, 16 % à 3 ★, 1 % à 4 ★,
  dont deux 4 ★ données à des photos de famille notées seules, sans avoir vu la sortie. Une scène sur fond noir voulu (L* médian 3,9)
  reste dite « presque noire » : à revoir, hors de la 1.3.
- **Claude note de 0 à 5 ★, jamais un libellé de couleur sans demande** (correctif 1.3.2, demandé
  par Dany le 22 octobre 2026 : « si moi je veux une photo 5 étoiles, je placerai un code de
  couleur ») : `propose_ratings` refuse une note hors de 0 à 5 avant tout envoi
  (`Notation.noteMaximale = 5`, 4 jusqu'à la 1.3.1), et le module la refuse encore
  (`Notation.NOTE_MAX_PROPOSEE = 5`) ; la passe 4 (monter à 4, et à 5 pour l'exceptionnel, après
  le développement, depuis l'échelle resserrée de la 1.4) se propose comme les autres. Le standard (section « Les coups de cœur »), les descriptions de
  `propose_ratings` et de `color_label` (`set_metadata`), les invites `noter` et `tri_seance`,
  `ServerInfo.instructions` (« libellé de couleur : sur sa demande ») et `Consignes.texte` (« De 0 à
  5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa demande. ») disent que les coups de
  cœur de Dany sont un libellé de couleur qu'il pose lui-même : Claude n'en propose, n'en pose ni
  n'en change jamais sans sa demande explicite. La carte offre « Accepter 5 ★ » (`Fenetre.noteDeCinq`
  et `Fenetre.PAS_CINQ` retirés). `set_metadata` pose toujours une note de 0 à 5 à la demande de
  Dany, comme Changer… et les étoiles de la carte Note. Jamais `set_metadata` pour une note sans
  demande. `propose_ratings` (titre « Noter des photos »)
  n'est plus en lecture seule depuis la 1.1.1 (hors de `readOnlyTools` : avec `apply`, il écrit
  dans le catalogue) ; il valide toutes les propositions avant d'envoyer quoi que ce soit (les clés
  de chaque élément à la main : `parametresInconnus` ne voit que le premier niveau), refuse une
  note au-dessus du plafond du dernier `cull_photos` sans `to_check`, et envoie une seule commande `notation`
  (`action = 'proposer'`, plus `poser` avec `apply = true`), absente de `LightroomBridge.lectures`
  (rejouée, elle remettrait les propositions « à vérifier »). Plus de `session` ni de
  `read_session` (Séance de notation retirée) ; `pass` est la passe du standard.
