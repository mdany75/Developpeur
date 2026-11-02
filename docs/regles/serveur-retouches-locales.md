# Règles : masques, peau, tireur, taches et géométrie

Sorti de `Sources/CLAUDE.md` le 31 octobre 2026 ; à lire avant de toucher à `add_mask`, `edit_mask`,
`Locaux`, `Peau.swift`, `Prompts.Tireur`, aux taches (`preparerTaches`), aux positions
(`Geometrie.lua`, `Recalage.swift`) ou à « Contraindre le recadrage ».

- Un masque combiné range chaque composant avec `MaskBlendMode` (0 ajouter, 1 soustraire) ; une
  intersection est une soustraction du composant inversé (`Locaux.combiner`).
- Formes constatées des masques récents (voir `docs/SPEC.md`, Retouches locales) : objet en
  rectangle = `Mask/Polygon` dont les `Points` sont des tables `{X, Y}` ; plage de couleurs =
  `PointModels` « c1 c2 c3 x y 0 », modèle Lab étalonné (`ModeleCouleur`), **un seul** par plage
  (deux font planter Lightroom 15.6, constaté le 1er novembre 2026 ; une autre couleur : un
  composant combiné) ; plage de profondeur =
  `Type = 3` et `DepthRange` de 0 à 1 (jamais `DepthMin`/`DepthMax`) ; couleurs ponctuelles d'un
  masque = `LocalPointColors`, des textes de 19 nombres ; dégradé radial = `Mask/CircularGradient`
  avec `Flipped = true` toujours, inversé par `MaskInverted` seul (`Locaux.radial` ; inversé, il
  n'agit que hors de l'ellipse : coins −31 à −69, centre −0,3 sur 255, à −2 IL sans fondu ; non
  inversé, centre −45 ; constaté le 20 octobre 2026), y compris en composant combiné, en copie
  inversée d'`edit_mask` et copié vers une autre photo. Au calcul du masque, Lightroom range
  `Flipped` faux sur un radial inversé (constaté le 2 novembre 2026) : la copie inversée
  d'`edit_mask` repose `Flipped = true`. La simulation vérifie chacune (pour le radial :
  `Flipped == true`, ou faux avec `MaskInverted` vrai, et un `MaskInverted` booléen). L'effet d'un
  radial sans `Flipped`, ou `Flipped` faux sans inversion, n'est pas relevé.
- Le dosage de la peau n'existe qu'à un endroit : `Peau` (`Peau.swift` : `parDefaut`, « Peau du
  visage lisse », texture −20 et clarté −10 ; `lite`, « Adoucir la peau (Lite) », −35 et −15 ;
  `intensiteReduite`, `amount` 50 pour un homme ou une personne âgée ; rien pour un enfant ;
  `dosage`, `effetsIntegres`), d'après les fichiers d'Adobe et non son aide (relevés le 20 octobre
  2026, Lightroom Classic 15.6). La description d'`effect` d'`add_mask` et l'invite `portrait`
  reprennent `Peau.dosage` ; `Consignes.lua` y renvoie sans chiffres. Les deux effets intégrés
  viennent après ceux des fichiers (`LocalEffectLibrary`), qui l'emportent. `add_mask` refuse, avant
  tout envoi (proposition comprise : un refus n'envoie aucune commande), un masque de peau
  (`face_skin`, `body_skin` ; en premier composant non inversé, ou en composant qui la garde :
  `Peau.surLaPeau`) au-delà de la dose Lite, intensité comprise, ou à netteté négative, sans
  `smoothing_requested`, qui ne se pose que sur demande de Dany ou de son guide de style
  (`Peau.verifier`, dans `maskParameter`, qu'`add_mask` seul appelle : ni `copy_settings`, ni
  `edit_mask`, ni `match_series`). L'intensité d'un masque (`CorrectionAmount`) est linéaire
  (constaté le 20 octobre 2026, en propositions sur la peau d'un portrait : texture −20 et clarté
  −10 à `amount` 50 rendent la même image, au pixel près, que −10 et −5 à 100 ; de même pour «
  Adoucir la peau (Lite) ») : un constat de rendu, sans règle possible dans la simulation, que
  vérifie l'étape « intensité d'un masque » de `--portrait`. Vision ne dit ni le genre ni l'âge d'un
  visage : Claude juge à l'œil, et dans le doute prend la dose la plus faible.
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
  route, sans mesure : ce sont des plafonds. La forme des bords a été relevée le 20 octobre 2026 sur
  un seul paysage, radial centré, en propositions à −0,5 IL (rayons 0,6 à 0,75, fondus 50, 80 et 100
  : centre jamais touché, baisse sans marche ; rayon 0,7 et fondu 80 : tiers central intact, milieu
  des bords −16 sur 255, coins −21 à −27 ; fondu 100 : presque tout le cadre ; fondu 50 : les seuls
  coins). L'étape « forme des bords » de la recette la mesure telle que Claude la pose (au milieu de
  la zone d'intérêt, à −0,3 et −0,5 IL : centre intact, ni plaque ni anneau). Restent à juger à
  l'œil cette forme sur un portrait et un intérieur, et le fondu du radial du sujet (80 à 100 : ni
  halo, ni peau écrêtée).
- Une photo qui porte `RemoveAreas` (outil Supprimer à détection d'objet) est lue par là, et
  `RetouchAreas` en est dérivé : les taches de Claude vont dans les deux (`preparerTaches`). Une
  tache Supprimer de Claude est toujours `fill_method = 'patchmatch'`, jamais générative.
- Les positions des masques et des taches se donnent dans l'image que montre `view_photo` ;
  `Geometrie.lua` les ramène dans le repère du fichier. Toute nouvelle position passe par lui. Ce
  repère est celui d'avant la correction d'objectif, Upright et la perspective : le serveur calcule
  une grille de recalage sur deux rendus (`Recalage.swift`, commande `geometrie`), que
  `Geometrie.lua` interpole ; toute commande qui place des positions la demande (`Tools+Recalage`).
- Upright, la perspective et la distorsion manuelle laissent des coins vides dans le cadre : toute
  écriture qui touche la géométrie ou le cadre d'une photo redressée coche « Contraindre le
  recadrage » (`preparerContrainte`), qui fait resserrer le cadre par Lightroom ; le cadre est
  mémorisé avant (Lightroom le change sans qu'on l'écrive) et relu après (`relireCadres`). Un cadre
  demandé se calcule dans la zone que la grille de recalage dit remplie (`Geometrie.zone`) ; demandé
  avec Upright, il se place ensuite (`a_recadrer`, commande `recadrer`, qui complète la même étape).
  Les rendus du recalage décochent la case. Voir `docs/SPEC.md`, Contraindre le recadrage.
