# Règles : mesures du serveur (défauts, composition, netteté, éclairage, bilan, écran)

Sorti de `Sources/CLAUDE.md` le 31 octobre 2026 ; à lire avant de toucher à `PriseDeVue`, à la
raison des outils, à `Composition.swift`, `Detail.swift`, `Eclairage.swift`, `Bilan.swift`,
`Ecran.swift`, ou à un seuil de mesure.

- **`PriseDeVue.defauts` est la seule liste des défauts de la prise de vue** (17 codes depuis le
  correctif 1.3.7, 16 avant ; domaine du carnet, six mesurés ; plus d'axe ni de clé anglaise depuis
  le correctif 1.3.6 ; `yeux_fermes`, nouveau au correctif 1.3.7, domaine netteté, après
  `mise_au_point`, `mesure` faux : le Suivi le compte d'après `--analyser`, le carnet de
  `view_photo` ne le cherche pas ; les dix autres non mesurés gardés pour les leçons d'avant rangées
  dans `carnet.json`) ; `PriseDeVue.vocabulaire` part avec chaque constat : aucune liste de défauts
  dans le module. `ToolHandler.descriptionRaison` (la description de `reason`, répétée dans chaque
  outil qui écrit) fait 160 caractères au plus, comme `descriptionRaisonProposition`, celle de
  `preview_settings` depuis la 1.3.1 (Claude y joignait `reason` 3 fois sur 4 et l'appel était
  refusé ; elle ne promet pas le journal). Une proposition n'écrit rien : sa raison ne part jamais
  au module (ni étape ni journal), elle revient dans la réponse (`raison`), à redonner à
  `apply_settings`. `ToolHandler.raison` la nettoie et la borne (300 caractères).
- **La composition se lit sur l'image entière** (`Composition.swift`, `Tools+Composition.swift`,
  `Rendu.lua`) : l'image entière se rend par l'écriture temporaire du cadre retiré (`sansRecadrage`
  : `Recadrage.AUCUN` et la case décochée), puis le retour, comme le recalage (deux étapes « Claude
  · composition ») ; une photo agrandie est refusée avant toute écriture ; un module qui ne rend pas
  `image_entiere` est refusé. Les positions de `view_photo` passent par
  `Composition.versImageEntiere` d'après `cadre_actuel` ; l'horizon se mesure sur l'image entière
  (angle absolu) ; le dessin suit le cadre que Lightroom a gardé, relu (`cadre_propose`), jamais la
  demande ; la marge de 0,998 sert aux arrondis du module (validée le 21 octobre 2026). Seuils
  relevés le 21 octobre 2026 : `roulisRenverse` 3π/4 (un visage à l'envers n'est ni le sujet ni le
  regard), `zoneInteretMax` 0,5 (au-delà, pas de sujet), `signeLacet` +1 confirmé, `seuilLacet` 0,26
  gardé, `LineAngle.ecartMax` 3 px (au-delà, la ligne n'est pas « affinée », l'angle vient des deux
  points), tiers à 0,35 % (`PreviewImages.traitTiersPart`), cadre à 0,4 %. Le contrat est figé dans
  `Tests/Contrats/composition.json`.
- **Mise au point jugée sur de la texture** (`Detail.autour`, relevé le 21 octobre 2026 sur les
  copies d'Essais) : sous `DetailMeasurements.textureMin` (18 : sable lisse, ciel uni), la mise au
  point est « non jugée » (pas de plafond, pas de constat au carnet sauf si l'appareil l'a signalée)
  ; jusqu'à `textureDouteuse` (30 : le bord d'un nuage), une mise au point manquée n'est qu'un doute
  : 1 (2 avant l'échelle resserrée de la 1.4), à vérifier, sans rejet proposé (`Notation.plafond`),
  et le carnet ne la compte pas. À relever sur un mur, de la neige et une vraie mise au point
  manquée avant de les changer.
- Les seuils de netteté et de bruit (`DetailMeasurements.seuilFlou` 15, `seuilNet` 35,
  `bruitVisible` 0,6, `bruitFort` 1,5, et depuis la 1.3 `textureMin` 18 et `textureDouteuse` 30 :
  `Detail.swift` ; la marge des ombres de la 1.6.6, `marge_ombres_il` = 2,2 × log2(`bruitVisible` ÷ bruit
  des ombres) en niveaux sRGB, bornée de −2 à 4 IL, muette sous 0,05 (ombres lissées par le JPEG), s'en dérive sans seuil nouveau de lecture, supposant un bruit qui monte
  comme le signal : provisoire, à relever), de ressemblance et d'ouverture des yeux (`AnalyseVision.swift`) et de l'éclairage
  mixte (`Eclairage.chromaMax` 12, `seuilMixte` 8) ont été relevés sur de vrais aperçus : les
  mesurer de nouveau avant de les changer. Ceux de la dominante et de la saturation sont nommés
  aussi, sans relevé noté dans le code (`PhotoMeasurements.partNeutreMin` 3, `dominanteLegere` 2,
  `dominanteNette` 6, `chromaTresSaturee` 60 ; `Measurements.seuilChroma` 3). Le tri et les plafonds
  de note (`Notation.plafond`) les reprennent sans en ajouter, comme l'analyse d'office du Suivi
  (`Suivi.analyser`, correctif 1.3.7 : la photo « brûlée » du tri au-delà de
  `PhotoTriee.partBlancPurBrulee`, 35 %, y fait la surexposition, et les yeux fermés ne s'y
  cherchent que s'il y a des `sujetsAuxYeuxLus`, les sujets de `yeuxFermes` et de `yeuxOuverts`) ;
  `analyze_photos`, l'éclairage et le bilan les reprennent aussi, avec leurs propres seuils (puces
  suivantes). Au tri, une pile de Lightroom compte comme une rafale (seule sa meilleure vue échappe
  au plafond de 2 ★, 3 ★ avant l'échelle resserrée de la 1.4). Le tri (`cull_photos`) mesure les
  vignettes du cache de Lightroom (commande `vignettes`) et ramène leur netteté à celle d'un aperçu
  exporté (`thumbnailSharpnessFactor`, relevé ; le 21 octobre 2026, le tri donnait encore 11 à 23 %
  de plus que l'aperçu, en classant pareil : gardé). Vision ne s'appelle pas en grand parallèle
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
  depuis la réponse brute d'`apercu`). `chromaMax` 12 et `seuilMixte` 8 relevés le 20 octobre 2026
  sur les 8 copies d'essai (`--eclairage`) : seul le portrait à deux lumières ressort (9,8), les
  autres de 2,2 à 7,1 ; à 15 et au-delà, des objets colorés pris pour des gris font de faux mixtes.
  Avec la tolérance, relevé le 21 octobre 2026 (`--eclairage`, à la balance de la photo et avec
  `--essai`) : l'œil tenu à la balance de la photo (portrait 9,7, les autres de 2,1 à 7,1) et à 6
  500 K ; sous une dominante forcée extrême, la mesure peut perdre une lumière (portrait à 3 200 K :
  4,6) ou en inventer une (intérieur à la lampe à +30 : 11,4) : son conseil dit « à confirmer à
  l'œil ». `toleranceNeutre` (10), choisie hors de Lightroom sur cinq aperçus, est la seule valeur
  essayée à ce relevé (son commentaire la dit encore à relever) ; `seuilTonal`, `partMinGroupe` et
  `pixelsMinPeau` restent provisoires. Mesure en 123 à 199 ms par photo à ce relevé.
- Le bilan de `view_photo` (`Bilan.swift`) compare l'aperçu entier au précédent de la même photo à
  la même taille d'aperçu, et au premier de la session (`depuis_le_debut`) : `vuesMesurees` de
  `ToolHandler`, rangé par `Bilan.Cle` (photo et taille), gardé pour le processus du serveur comme
  `dernierTri` (30 au plus, `Bilan.photosGardees`) ; une autre taille repart de zéro et le dit (même
  état à 1 024, 1 344 et 2 048 px : netteté jusqu'à 10 % d'écart ; deux vues de suite à la même
  taille : les mêmes 43 mesures ; constaté le 20 octobre 2026). Jamais une proposition contre une
  vue gardée (le même jour, une proposition sans changement s'écartait d'une vue jusqu'à 0,9 point
  d'écrêtage ; mesurées depuis par le même chemin, l'écart qui reste est à relever) : une
  proposition avec `compare` (`preview_settings`, `add_mask` avec `preview`) et `view_photo` avec
  `compare` ont leur propre bilan, sur deux images rendues par la même commande ; netteté et bruit
  seulement entre deux vues. Toute image se mesure par un décodage et la réduction à 512 px
  (`ToolHandler.mesurerImage`, comme `analyzeScaled`). Les tons neutres ne se suivent qu'à cadre
  égal (`Bilan.cadre`). Une annulation (`etapes_claude` en baisse, que `Rendu.apercu` donne en
  lecture seule) ou un calcul IA en attente ne donne pas de « regression » : elle passe dans
  `a_verifier`. Un zoom refait sur la même zone a son `bilan_zone`, sans alerte (`zoomsMesures`, 6
  par photo, 30 photos). Seuils de visibilité repris de `match_series`, de
  `Measurements.seuilChroma` et de `Detail` ; seuils de régression relevés le 20 octobre 2026 en
  propositions (écrêtage, un canal, couleurs très saturées : 2 points de plus et 1,5 fois l'avant ;
  ombres bouchées : 2 points de plus, une nuit n'alerte pas d'elle-même ; dominante des tons neutres
  : |a*| ou |b*| qui s'éloigne de 0 de 2) ; ceux de la netteté et du bruit (`baisseNetteteMin`,
  `hausseBruitMin`, `ecartNettetePct`, `ecartBruit`…) restent à relever (étape « bilan chiffré » de
  la recette).
- L'écran principal du Mac (`Ecran.swift`) se lit par CoreGraphics et ColorSync, sans AppKit ni
  permission (environ 44 ms) ; l'en-tête ICC se lit dans les octets du profil
  (`ColorSyncProfileCopyHeader` rend ses signatures à l'envers, « lppa » pour « appl », constaté le
  20 octobre 2026). Six classes (`Ecran.Etalonnage`) : un profil d'usine (`FactoryProfiles`, tiré de
  l'EDID, rangé dans `/Library/ColorSync/Profiles/Displays` et refait à chaque branchement), un
  profil standard du système et un profil fait à l'œil ne sont jamais « mesurés », et la balise
  `meas` n'est pas un indice (`sRGB Profile.icc` du système la porte) ; `mesure` ne vaut vrai que
  pour un profil qui nomme un logiciel de sonde, ou dont la balise `vcgt` vient d'un créateur autre
  qu'Apple, et reste inconnu (« étalonné ? ») pour un autre profil personnalisé. Aucun vrai profil
  de sonde n'est encore relevé. **Plus rien sur l'étalonnage** depuis le correctif 1.3.6 (décision
  de Dany du 25 octobre 2026 : il n'achètera jamais de sonde) : ni Dany ni Claude n'en entendent
  parler. Le classement (`Ecran.Etalonnage`, `mesure`, `Ecran.texte`) ne sert plus qu'à
  `mcp-developpeur --ecran`, pour le développement (`Ecran.json`, sans la clé `detail` :
  `Ecran.detail` et `Ecran.reglageProfil`, le seul conseil d'une sonde, sont retirés avec le
  voyant). Seul `main.swift` pose `Ecran.lire` (les outils de `serve` et de `--call`, et la recette
  pour son étape « écran nommé ») ; seul `get_status` le lit, et ne dit que les noms (`Ecran.nommer`
  : `ecran: { nom, autres }`, `autres` seulement s'il y en a ; ni profil, ni chemin, ni
  `etalonnage`, `mesure`, `texte`, date ou logiciel), sa description seulement « ecran : le nom de
  l'écran principal du Mac. » ; `--status` dit les noms seuls. `ServerInfo.instructions` n'en a
  jamais parlé. `EcranTests` vérifient qu'aucune description d'outil ni `ServerInfo.instructions` ne
  parlent de sonde ou d'écran non étalonné, et qu'aucun aperçu ne lit l'écran
  (`testAucuneRemarqueDEcranAuxApercus`).
