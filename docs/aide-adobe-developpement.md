# Aide Adobe : développement et outils de Lightroom Classic

Notes prises le 16 octobre 2026 sur l'aide officielle d'Adobe en français
(https://helpx.adobe.com/fr/lightroom-classic/desktop.html), pour Lightroom Classic 15.6 : les
20 pages « Traitement et développement des photos », plus Développement rapide, Gestion des
couleurs, Tri assisté, Nouveautés et trois pages de dépannage. Les pages sont résumées dans nos
mots, pas recopiées. Pour chaque réglage, la clé du connecteur vient de
`Sources/DeveloppeurKit/Catalogue.swift`, et le paramètre, de la description des outils ;
« hors connecteur » veut dire que le connecteur ne sait pas le faire (revu pour Développeur 1.0,
le 20 octobre 2026). Adobe refuse les lectures automatiques (`curl`, WebFetch : 403) : les pages se
relisent dans un navigateur.

## 1. Ordre d'utilisation

Adobe ne donne pas de marche à suivre complète. L'ordre des panneaux du module Développement
(Réglages de base, Courbe, Mélangeur de couleurs, Color Grading, Détail, Flou de l'objectif,
Correction de l'objectif, Transformation, Effets, Étalonnage) est un ordre d'affichage, que
l'utilisateur peut changer, et non un ordre de travail. L'ordre ci-dessous réunit ce que les pages
disent explicitement (marqué **Adobe**) et ce qu'on en déduit (le reste).

1. **Trier** : `cull_photos` (yeux fermés, rafales, piles), ou le tri assisté de Lightroom. Rien n'est
   supprimé sans l'utilisateur.
2. **Préparer les fichiers** : correction de champ plat (crée des DNG), puis fusion HDR ou
   panorama. **Adobe** : on développe l'image fusionnée, pas les sources. Des sources penchées
   reçoivent toutes la même transformation Upright exacte.
3. **Version de processus et point de retour.** **Adobe** : mettre à jour la version une photo à
   la fois, en comparant ; faire un instantané avant un gros changement.
4. **Reflets de vitre** (`remove_distractions`). **Adobe** : avant toute autre retouche.
5. **Améliorer : débruitage IA** (`enhance_photo`). **Adobe** : avant les masques IA et les
   suppressions, dont il change le résultat. Super résolution seulement pour agrandir.
6. **Profil** (`profile`, `profile_amount`). **Adobe** : changer de profil ne touche pas aux
   curseurs, on peut donc en changer plus tard ; un profil adaptatif se pose avant toute autre
   retouche, jamais avec la tonalité automatique.
7. **Géométrie.** **Adobe** : corrections de profil d'objectif (`LensProfileEnable`) avant
   Upright ; essayer les modes Upright ; affiner par les curseurs ; « Contraindre le recadrage ».
   Choisir un mode Upright remet à zéro le recadrage et les transformations : recadrer et
   redresser après. Changer le profil d'objectif oblige à refaire Upright.
8. **Balance des blancs** : préréglage (RAW, DNG) ou point neutre, puis Température, puis
   Teinte. **Adobe** : une dominante verte ou magenta restée dans les ombres se corrige par
   `ShadowTint` (Étalonnage).
9. **Tonalité** : tonalité automatique comme point de départ, puis Exposition (par 1/3 IL),
   Contraste, Hautes lumières, Ombres, Blancs, Noirs, en surveillant l'écrêtage par canal.
10. **Présence** : Texture, Clarté, Correction du voile, Vibrance, Saturation. **Adobe** : la
    Clarté se juge à 100 % (pousser jusqu'aux halos, puis reculer) ; la Correction du voile une
    fois la base faite.
11. **Courbe des tonalités**, pour affiner ce que Réglages de base a fait (**Adobe**).
12. **Couleurs ciblées** : Mélangeur (TSL) ou Couleur de point ; Étalonnage (teinte d'une
    primaire, puis sa saturation : **Adobe**) ; noir et blanc (conversion, tonalité, puis mélange
    des gris : **Adobe**) ; Color Grading.
13. **Détail** : netteté et réduction du bruit manuelles, jugées à 100 % ou plus (**Adobe**).
14. **Corrections d'objectif fines** : aberrations, franges. **Adobe** : franges locales après
    toutes les transformations de l'objectif.
15. **Retouches locales** : le masque le plus automatique qui convient, affiné par combinaison,
    puis les curseurs, puis contrôle (masques IA calculés).
16. **Flou d'objectif**, après les masques ; vérifier les contours.
17. **Suppressions** : taches (`retouch_spots`) ; poussière, intrus, suppression générative à la
    main.
18. **Effets** : vignetage après recadrage, grain, vérifiés à plusieurs zooms.
19. **Vérifier** en Avant/Après, masques IA à jour.
20. **Série** (**Adobe**) : finir une photo de référence, puis copier ou synchroniser ; sur
    plusieurs photos, réglages relatifs.
21. **Sortie** : espace couleur selon la destination (sRVB pour le web, profil d'imprimante),
    sortie HDR au besoin.

## 2. Écarts avec la méthode du connecteur

La méthode est celle des consignes de `ServerInfo.swift` et des invites `retouche_pro` et
`harmoniser_serie` (`Prompts.swift`). Elles reprennent ces points ; la colonne de droite dit
comment.

| Point | Ce que dit Adobe | Le connecteur |
| --- | --- | --- |
| Débruitage IA | Avant les masques IA et les suppressions | Consignes et `retouche_pro` : avant la netteté, les masques IA et `retouch_spots` |
| Profil adaptatif | En premier, sans tonalité automatique ; à rafraîchir après une tache, une rotation ou un flou d'objectif | Posé en premier, sans tonalité automatique, par un paramètre prédéfini du module (voir `docs/SPEC.md`, Profils adaptatifs) ; après une tache ou un flou d'objectif, le module le fait recalculer par `photo:updateAISettings()` ; une rotation ne le change pas (constaté : voir `docs/SPEC.md`, Aperçus et masques IA, Calcul par le SDK) |
| Upright et recadrage | Upright efface le recadrage : recadrer après | `applyDevelopSettings` garde le recadrage (constaté, voir `docs/SPEC.md`, Recadrage), mais Upright laisse des coins vides : le module coche « Contraindre le recadrage », et un cadre demandé se calcule sur la grille de recalage |
| Dominante dans les ombres | `ShadowTint` | Consignes et `retouche_pro` : `ShadowTint`, pas `Tint` |
| Mélangeur de couleurs | Touche toutes les couleurs semblables | Consignes et `retouche_pro` : un masque pour un seul objet |
| Courbe | Courbe à points et curseurs de région sont indépendants | Consignes et `retouche_pro` : `Parametric…` à 0 ne prouve pas une courbe droite, relire `ToneCurvePV2012` |
| Reflets | Suppression des distractions › Reflets, avant le reste | `remove_distractions`, avant toute autre retouche (consignes) |
| Poussière, intrus, suppression générative | Outils IA dédiés | Hors connecteur : consignes et invites les font proposer à la main (§ 4) |
| Bracketing et Upright | Copier la transformation exacte | `copy_settings` copie le mode, que Lightroom recalcule par photo ; « Contraindre le recadrage » resserre le cadre de chacune |
| Mesures | Développement affiche en ProPhoto RVB | `view_photo` mesure un JPEG sRGB : une couleur hors gamme sRGB y paraît écrêtée ; une photo en mode HDR est mesurée dans son rendu SDR (consignes) |

## 3. Notes par thème

### 3.1 Module Développement, options, Développement rapide, paramètres prédéfinis

- **Module Développement** : à gauche Navigateur, Paramètres prédéfinis, Instantanés,
  Historique ; à droite les panneaux (liste au § 1) ; barre d'outils locaux : Recadrage,
  Supprimer, Yeux rouges, Masquage. Un point rouge sous un outil signale un élément à mettre à
  jour (masque IA à recalculer) : c'est le cas que `view_photo` signale par `a_savoir`.
  Dans la vue de référence, le recadrage n'est pas disponible.
- **Annuler** : « Réinitialiser » revient aux réglages par défaut ; « Général : remise à zéro »
  retire tout ; l'Historique et les Instantanés gardent les états. Le mode Avant montre la photo
  telle qu'importée, paramètres prédéfinis d'importation compris : revenir à l'état d'avant
  Claude n'est pas remettre à zéro.
- **Versions de processus** : PV2012 (Lightroom 4 et suivants) apporte Exposition, Contraste,
  Tons clairs, Tons foncés, Blancs, Noirs ; PV5 améliore la correction du voile négative et les
  ISO élevés ; PV6 réduit les cassures du Mélangeur et du mélange N&B. Les clés `…2012` du
  connecteur supposent PV2012 ou plus récent. Mise à jour d'une version 3 à 5 vers la 6 :
  `process_version` (montrée d'abord, instantané pris avant) ; les versions 1 et 2 (2003, 2010)
  se mettent à jour à la main. Une mise à jour de version peut changer nettement le rendu.
- **Appliquer à d'autres photos** : Copier/Coller, Précédent, Synchroniser, Synchronisation auto
  (`copy_settings`). « Reproduire toutes les expositions » ajuste l'exposition d'après l'ouverture,
  la vitesse et l'ISO : `match_series` avec `by: "exif"`.
- **Développement rapide** (Bibliothèque) : sur plusieurs photos, les réglages sont relatifs
  (comme `relative: true`). Exposition par 1/3 IL ou 1 IL. Tonalité automatique : `auto_tone`.
  Vibrance plutôt que Saturation pour des couleurs ternes.
- **Paramètres prédéfinis** : appliqués avant les autres réglages, qu'on corrige ensuite
  (`preset` d'`apply_settings`). Curseur « Quantité prédéfinie » : `preset_amount`. Un nom peut
  exister deux fois dans un groupe (Dupliquer) ; Remplacer écrase. Un paramètre réservé aux RAW
  ou portant un profil d'appareil ne s'applique pas à un JPEG. Paramètre adaptatif ISO : valeurs
  interpolées selon l'ISO. Nouveautés 15.3 : douze paramètres « Style : Inspiré d'un film ».

### 3.2 Ton et couleur

**Profils**
- Adobe Color par défaut (Adobe Monochrome pour une photo N&B).
- Groupes réservés au RAW : Adobe Raw, Camera Matching (rendu de l'appareil, simulations
  Fujifilm), Adaptatif.
- Profils créatifs (Artistique, N&B, Moderne, Vintage) : pour tout fichier, avec un curseur
  Degré (`profile_amount`, 0 à 200).
- Profils adaptatifs : intensité 0 à 200, meilleurs sur un RAW en HDR ; à mettre à jour après une
  retouche de taches, une rotation ou un flou d'objectif (le module le fait après une tache ou un
  flou ; une rotation ne les change pas, constaté).

**Balance des blancs**
- Préréglages (Tel quel, Auto, Lumière du jour…) seulement pour RAW et DNG : `white_balance` ;
  pour un JPEG, `as_shot` ou `auto`.
- Sélecteur : cliquer un gris neutre éclairé, jamais un reflet ni un blanc pur
  (`white_balance_point`, mesuré sur l'aperçu puis vérifié).
- `Temperature` en kelvins pour un RAW (2000 à 50000 ; tungstène vers 3200 K), relative (−100 à
  +100) pour un JPEG, un TIFF, un PSD. `Tint` : négatif vers le vert, positif vers le magenta.

**Tonalité** (Réglages de base, PV2012)

| Réglage | Clé | Note |
| --- | --- | --- |
| Exposition | `Exposure2012` | +1 ≈ un diaphragme |
| Contraste | `Contrast2012` | surtout les tons moyens |
| Tons clairs | `Highlights2012` | vers la gauche, récupère la surexposition |
| Tons foncés | `Shadows2012` | vers la droite, débouche |
| Blancs | `Whites2012` | règle l'écrêtage des blancs |
| Noirs | `Blacks2012` | règle l'écrêtage des noirs |
| Automatique | `auto_tone` | point de départ, limite l'écrêtage aux deux bouts |

**Histogramme et écrêtage** : un indicateur blanc signale les trois canaux écrêtés, un indicateur
coloré un ou deux ; une valeur à 0 % ou 100 % sur un canal laisse souvent du détail récupérable
dans les autres. `view_photo` mesure l'écrêtage par canal.

**Présence**

| Réglage | Clé | Note |
| --- | --- | --- |
| Texture | `Texture` | absente de la page ; ne touche ni la couleur ni la tonalité (page Masquage) |
| Clarté | `Clarity2012` | contraste local ; juger à 100 %, reculer avant les halos |
| Correction du voile | `Dehaze` | négatif ajoute du voile ; aussi en local |
| Vibrance | `Vibrance` | ménage les couleurs vives et la peau |
| Saturation | `Saturation` | égale sur toutes les couleurs, −100 = monochrome |

**Courbe des tonalités**
- Paramétrique : `ParametricHighlights`, `ParametricLights`, `ParametricDarks`,
  `ParametricShadows` ; les séparateurs de régions : `ParametricShadowSplit`,
  `ParametricMidtoneSplit`, `ParametricHighlightSplit`.
- Par points : `tone_curve` (`ToneCurvePV2012` et ses canaux `Red`, `Green`, `Blue`, points de 0 à
  255, 16 au plus). Le menu Linéaire / Contraste moyen / Contraste fort ne bouge pas les curseurs
  de région. Une photo jamais retouchée peut déjà porter une courbe.
- « Affiner la saturation » de la courbe : `CurveRefineSaturation`.

**Mélangeur de couleurs**
- TSL : `HueAdjustment…`, `SaturationAdjustment…`, `LuminanceAdjustment…` pour Red, Orange,
  Yellow, Green, Aqua, Blue, Purple, Magenta (−100 à +100). Agit sur toutes les couleurs
  semblables de l'image.
- Couleur de point : `point_colors` (`PointColors`) ; une couleur prélevée, décalages de teinte,
  saturation, luminance, `range` et `variance`. La liste envoyée remplace les couleurs
  existantes ; dans un seul masque, `point_colors` d'`add_mask`.

**Étalonnage** : `ShadowTint` (dominante des ombres), puis pour chaque primaire la teinte avant la
saturation (`RedHue`, `RedSaturation`, `GreenHue`, `GreenSaturation`, `BlueHue`,
`BlueSaturation`).

**Noir et blanc** : `ConvertToGrayscale` = 1, puis la tonalité, puis `GrayMixerRed` à
`GrayMixerMagenta`. Le bouton Auto du mélange N&B : `auto_gray_mix`. Préférer ce mélange à une
Saturation à −100.

**Color Grading** : teinte et saturation des ombres (`SplitToningShadowHue`,
`SplitToningShadowSaturation`), des tons moyens (`ColorGradeMidtoneHue`, `ColorGradeMidtoneSat`)
et des hautes lumières (`SplitToningHighlightHue`, `SplitToningHighlightSaturation`), puis Fusion
(`ColorGradeBlending`), puis Balance (`SplitToningBalance`). Les noirs et blancs extrêmes ne se
colorent pas. Sert aussi au virage d'une photo N&B.

**Gestion des couleurs** : Développement affiche en ProPhoto RVB, les autres modules en Adobe
RVB. À l'export : sRVB pour le web, profil d'imprimante sinon. Une saturation qui tient en
ProPhoto peut déborder en sRVB.

### 3.3 Détail, corrections de l'objectif, effets

(La page « Retouche de photos » traite de ces réglages, pas des taches.)

| Réglage | Clé | Note |
| --- | --- | --- |
| Netteté : Gain | `Sharpness` (0 à 150) | valeur plutôt faible |
| Rayon | `SharpenRadius` (0,5 à 3) | petit pour les détails fins |
| Détail | `SharpenDetail` | haut : textures |
| Masquage | `SharpenEdgeMasking` | 100 : seulement les contours ; épargne ciel et peau |
| Bruit : Luminance | `LuminanceSmoothing` | |
| Détail, Contraste | `LuminanceNoiseReductionDetail`, `LuminanceNoiseReductionContrast` | |
| Couleur | `ColorNoiseReduction`, `ColorNoiseReductionDetail` | |
| Profil d'objectif | `LensProfileEnable`, `LensProfileDistortionScale`, `LensProfileVignettingScale` | choix d'un profil installé : `lens_profile` (`list_profiles` avec `lens`) |
| Aberration chromatique | `AutoLateralCA` | |
| Franges | `DefringePurpleAmount`, `DefringeGreenAmount` (0 à 20), plages `…HueLo/Hi` | attention aux objets réellement violets ou verts ; les protéger par un masque `Defringe` négatif |
| Distorsion manuelle | `LensManualDistortionAmount` | |
| Vignetage de l'objectif | `VignetteAmount`, `VignetteMidpoint` | |
| Vignetage après recadrage | `PostCropVignetteStyle` (1 priorité des tons clairs, 2 couleur, 3 peinture), `…Amount`, `…Midpoint`, `…Roundness`, `…Feather`, `…HighlightContrast` | effet créatif |
| Grain | `GrainAmount`, `GrainSize`, `GrainFrequency` | à partir d'une taille de 25, Lightroom adoucit |

La netteté réglée ici vaut aussi pour l'export et l'impression. Les profils d'objectif offerts
diffèrent entre RAW et non-RAW.

### 3.4 Géométrie

**Upright** (panneau Transformation, `PerspectiveUpright`)
- Modes : 0 désactivé, 1 auto (équilibre, garde le plus d'image), 2 complet (niveau, vertical et
  auto réunis), 3 niveau, 4 vertical. Le mode « Avec repères » (5) : Claude pose les repères
  (`upright_guides`), Lightroom ne calcule la correction qu'au clic sur « Mettre à jour ». Pas de
  meilleur mode universel : les essayer (`preview_settings`).
- Curseurs : `PerspectiveVertical`, `PerspectiveHorizontal`, `PerspectiveRotate` (−10 à 10),
  `PerspectiveAspect`, `PerspectiveScale` (50 à 150), `PerspectiveX`, `PerspectiveY`.
  « Contraindre le recadrage » (`CropConstrainToWarp`) : le module la coche avec Upright, la
  perspective ou la distorsion manuelle ; posée par le SDK, Lightroom resserre le cadre (constaté).
- Copie : « Mode Upright » (recalculé par photo, scènes différentes), « Transformations Upright »
  (identique, pour un bracketing), « Réglages Upright » (les curseurs).

**Champ plat** (Bibliothèque) : retire un vignetage asymétrique ou teinté à partir d'une image
d'étalonnage prise avec la même optique ; produit des DNG ; une option supprime les originaux
(jamais sans l'accord de l'utilisateur). Hors connecteur : le vignetage de l'objectif ne corrige
ni l'asymétrie ni la dominante.

### 3.5 Masquage, corrections locales, filtre radial, flou d'objectif

**Types de masques** (`add_mask`)

| Interface | Connecteur |
| --- | --- |
| Sujet, Ciel, Arrière-plan | `kind: subject`, `sky`, `background` |
| Paysage (Ciel, Neige, Architecture, Végétation, Eau, Sol naturel, Sol artificiel, Montagnes) | `kind: landscape` et `part` |
| Personnes et leurs parties (peau du visage et du corps, cheveux, lèvres, barbe, sclère, iris et pupille, sourcils, vêtements, dents) | `kind: person_part` et `part` (toutes les personnes) ; une personne précise : `kind: person`, `person` (son numéro) ou `person_at` (un point sur elle), et `part` au besoin |
| Dégradé linéaire | `kind: linear` (`from` = effet entier, `to` = effet nul) |
| Dégradé radial | `kind: radial` (`center_x/y`, `radius_x/y`, `angle`, `feather`, `invert`) |
| Gamme de luminance | `kind: luminance` (`min`, `max`, `feather`) |
| Objets | `kind: object` (`box` ou `strokes`) |
| Pinceau | `kind: brush` (`strokes`, `auto_mask`) |
| Plage de couleurs | `kind: color` (`samples`, `color_range`) |
| Plage de profondeur | `kind: depth` (`min`, `max` ; photo Portrait d'iPhone) |

**Combinaisons** : Ajouter, Soustraire, Intersection, Inverser → `combine` (`add`, `subtract`,
`intersect`), `invert`. Lightroom range une intersection comme une soustraction du composant
inversé. Dupliquer, masquer, afficher, supprimer, recalculer un masque, ou affiner son contour :
`edit_mask` (`duplicate`, `hide`, `show`, `remove`, `recompute`, `refine`, `remove_empty`) ;
`undo_last` retire aussi les masques d'une étape.

**Curseurs locaux** : `Temperature`, `Tint`, `Exposure`, `Contrast`, `Highlights`, `Shadows`,
`Whites`, `Blacks`, `Texture`, `Clarity`, `Dehaze`, `Saturation`, `Sharpness` (négatif adoucit),
`Noise`, `Moire`, `Defringe`, couleur (`ToningHue`, `ToningSaturation`), décalage de teinte
(`Hue`), grain (`Grain`), intensité `amount` ; courbe locale (`tone_curve` du masque) et couleur
ponctuelle locale (`point_colors`) ; Contour progressif et « Edge » d'un masque IA (15.5) :
`refine` (`feather`, `edge`).

**Masques IA**
- À mettre à jour si l'image a changé, a été déplacée ou pivotée.
- Copiés ou synchronisés, ils sont recalculés pour chaque photo (`copy_settings` avec
  `include_masks`). Si l'un est mal posé : « Tout mettre à jour ».
- Un masque non calculé n'a aucun effet visible : relire `a_savoir`.

**Principe d'Adobe** : une sélection grossière, affinée par une gamme. Dans le connecteur, c'est
un masque IA ou un dégradé, intersecté avec une gamme de luminance.

**Filtre radial** : vignette décentrée sur le sujet. Pour assombrir autour du sujet, l'ellipse est
inversée, avec un contour progressif généreux. Plusieurs filtres peuvent se cumuler.

**Anciens outils** : Pinceau réglage et Filtre gradué ne s'appliquent plus depuis Lightroom
Classic 11.0, remplacés par Masquage. Les effets du menu Effet (« Blanchiment des dents »,
« Amélioration de l'iris », « Adoucir la peau » et ceux de l'utilisateur) : `effect` d'`add_mask`,
lus dans leurs `.lrtemplate` (`EffetsLocaux.swift`), sur la bonne partie (`person_part` `teeth`,
`iris_pupil`, `face_skin`).

**Flou d'objectif** (`lens_blur`)
- Carte de profondeur estimée par l'IA ; mise au point sur le sujet détecté par défaut, ou plage
  `near`/`far`. Intensité `amount` : 20 à 40 conseillé.
- Forme du bokeh (cercle, bulle, 5 lames, anneau, anamorphique) : `bokeh` ; œil de chat :
  `cat_eye` ; pinceau d'affinage (Net, Flou) : `refine` ; « Amplifier » (éclat des points
  lumineux, `HighlightsBoost`) : `highlights`. Hors connecteur : la mise au point par un cadre
  tracé sur l'image (le connecteur : sujet, ou `near`/`far`).
- Un mauvais détourage (cheveux, bords) se corrige au pinceau d'affinage, vérifié par un zoom ;
  sinon, réduire ou retirer le flou.
- En série, cocher « Mise au point sur le sujet » pour une détection par photo.

### 3.6 Améliorer et suppressions (IA)

**Améliorer** (panneau Détail ; `enhance_photo`)
- Réduire le bruit (`denoise`, 1 à 100).
- Détails bruts (`raw_details`) : RAW Bayer et X-Trans seulement.
- Super résolution (`super_resolution`) : 2× en largeur et en hauteur ; mêmes formats que les
  détails bruts, plus JPEG et TIFF ; au plus 128 Mpx et 32 500 px de côté. Une image déjà
  améliorée ne l'est pas une deuxième fois.
- Calcul par le processeur graphique (le Neural Engine d'Apple ne sert pas au débruitage).
  Depuis la 15.3, les traitements IA lancés par lots tournent en arrière-plan.

**Suppressions** (outil Supprimer)
- Corriger et Dupliquer : `retouch_spots` (`heal`, `clone`).
- Supprimer sans IA générative (remplissage d'après ce qui entoure) : `retouch_spots`, mode
  `remove`. Suppression générative (Firefly, sur les serveurs d'Adobe, sans crédits génératifs) :
  hors connecteur.
- Suppression des distractions : Personnes, Reflets, Poussière. Reflets : `remove_distractions` ;
  Personnes et Poussière restent hors connecteur (la poussière se retire seulement).
  - Personnes : pas sur WinARM.
  - Reflets : Quantité de −100 à 100, qualité Prévisualisation, Standard ou Optimale ; améliorée
    en 15.6.
  - Poussière : redétectée sur chaque photo quand on copie le traitement par Copier et Coller de
    Lightroom (constaté le 18 octobre 2026 : un module ne peut ni la lancer ni la faire refaire ;
    `remove_distractions` sait la retirer).

### 3.7 Fusions et HDR

- **Fusion HDR** (Ctrl+H) : Alignement automatique, Tonalité automatique, Correction des
  décalages (commencer par Faible). Le résultat est un DNG.
- **Panorama** : projections Sphérique, Perspective (garde les droites, pour l'architecture),
  Cylindrique ; Déformation du contour, Remplir les bords, Recadrage automatique. Un panorama HDR
  demande des séries régulières.
- **Mode HDR** : bouton HDR dans Réglages de base, Limite HDR, rendu SDR. Il faut un écran HDR et
  un processeur graphique compatible. La courbe va de 0 à 500. Export en AVIF, JPEG XL, TIFF, PSD
  ou PNG. Le connecteur : `HDREditMode`, `HDRMaxValue` et les curseurs `SDR*` de l'aperçu SDR
  (`apply_settings`), puis `export_photos` avec `hdr` (aussi en JPEG, avec carte de gain) ;
  `view_photo` mesure le rendu SDR.

Les fusions HDR et panorama sont hors connecteur ; on développe le DNG obtenu comme une photo.

### 3.8 Tri assisté

Il retient les photos d'après la netteté du sujet, la netteté des yeux et les yeux ouverts, et
rejette les problèmes d'exposition, les photos ratées, les documents et les reçus. Il empile
automatiquement et applique des actions par lots (marqueur, note, libellé, suppression). Il est en
accès anticipé ; le panneau Visages est arrivé en 15.4. `cull_photos` mesure la netteté (au point
AF des Fujifilm), les visages, les yeux fermés ou plissés, une note esthétique, et
regroupe les rafales et les piles de Lightroom (une seule photo proposée par pile) ; le tri assisté
reste utile pour juger la netteté des yeux et pour ses actions par lots.

### 3.9 Dépannage

- **Débruitage en erreur** sous Lightroom Classic 15.3 ou plus ancien avec Camera Raw 18.4 : passer
  à 15.4 ou plus, ou revenir à Camera Raw 18.3.
- **Stockage des modifications par IA** : dans le dossier `.lrcat-data`, à côté du catalogue.
  - Ne jamais le lire ni l'écrire directement.
  - Le sauvegarder avec le catalogue.
  - Ne pas le synchroniser par un nuage pendant que le catalogue est ouvert.
  - En cas d'erreur, vérifier les droits, une seule instance de Lightroom et la place libre sur le
    disque.
- **Module Développement désactivé ou boîte barrée**
  - Causes à vérifier : abonnement, connexion, mise à jour, processeur graphique.
  - Débruitage, détails bruts et super résolution échouent alors : le dire à l'utilisateur.

### 3.10 Nouveautés (développement)

- **15.6** (septembre 2026) : suppression des reflets améliorée.
- **15.5** (août 2026) :
  - opacité de la zone rognée réglable ;
  - curseurs Contour progressif et Edge pour les masques ;
  - Convertir au format DNG.
- **15.4** (juin 2026) :
  - doublons ;
  - panneau Visages du tri assisté ;
  - détection du sujet plus précise.
- **15.3** (avril 2026) :
  - paramètres prédéfinis d'inspiration cinéma ;
  - réglages IA par lots en arrière-plan.
- **15.2** (février 2026) : Modifier dans Firefly, format WebP.
- **Avant la 15.2** :
  - tri assisté et empilage automatique ;
  - suppression de la poussière, des personnes et des reflets ;
  - Sélectionner un paysage ;
  - profils adaptatifs ;
  - Variance de la couleur de point.

## 4. Hors de portée du connecteur : à proposer à la main

| Besoin | Outil de Lightroom |
| --- | --- |
| Passants à l'arrière-plan | Suppression des distractions > Personnes |
| Poussière sur une série | Suppression des distractions > Poussière, puis Copier et Coller de Lightroom (case Poussière) |
| Mise au point du flou d'objectif sur un cadre | Flou de l'objectif > outil de zone (le connecteur : sujet, ou plage de profondeur) |
| Version de processus 2003 ou 2010 | Paramètres > Mettre à jour vers la version de processus actuelle |
| Upright avec repères | Repères tracés par Claude ; clic sur « Mettre à jour » (section Upright) |
| Gros objet sur un fond complexe | Supprimer avec l'IA générative |
| Vignetage asymétrique ou teinté | Correction de champ plat (image d'étalonnage) |
| Bracketing, panorama | Fusion HDR, Panorama, puis développer le DNG |

## Sources

Toutes sous https://helpx.adobe.com/fr/lightroom-classic/desktop/ :

- process-and-develop-photos/ : develop-module-tools, develop-module-options, apply-presets,
  image-tone-color, color-mixer, masking, apply-local-adjustments, lightroom-radial-filter,
  lens-blur, retouch-photos, remove-tool, distraction-removal-people,
  distraction-removal-reflections, distraction-removal-dust, enhance-details,
  guided-upright-perspective-correction, flat-field-correction, panorama, hdr-photo-merge,
  hdr-output (`.html`)
- organize-photos-in-lightroom-classic/ : using-quick-develop-panel, assisted-culling
- workspace/color-management ; introduction-to-lightroom-classic/whats-new
- technical-support/ : workflow-issues/denoise-issues/troubleshoot-denoise-issues,
  workflow-issues/catalog-issues/ai-edits-storage-error,
  technical-issues/rendering-issues/develop-module-disabled

Non lus : les images, les vidéos et une section vide de la page Fusion HDR (nombre de photos à
fusionner).
