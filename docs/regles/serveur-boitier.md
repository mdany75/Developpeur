# Règles : intention et point de mise au point du boîtier

Sorti de `Sources/CLAUDE.md` le 31 octobre 2026 ; à lire avant de toucher à `IntentionBoitier`,
`LectureBoitier`, `Boitier.swift`, `PointAF.swift` ou à `point_af` de `view_photo`.

- L'intention de la prise de vue (`IntentionBoitier`, lue par `LectureBoitier` dans la MakerNote et
  l'Exif : simulation de film, couleur, plage dynamique et sa priorité, tons clairs et foncés,
  compensation, mode, balance, scène) se lit seulement : `view_photo` la donne sur l'aperçu entier
  (`intention_boitier`, avec sa `lecture`), jamais sur un zoom ni un avant/après, et rien n'est posé
  d'office. Un RAW n'en reçoit que la simulation, par son profil Lightroom (`profilLightroom` : DCP
  du catalogue ou Look installé), en première passe, sauf autre style demandé ou guide de style
  contraire ; un JPEG de l'appareil porte déjà simulation, plage dynamique et tons (ne pas les
  refaire) ; une compensation de −0,6 IL ou moins dit une photo voulue sombre, à ne pas remonter
  (seuils de ±0,6 IL provisoires). Recoupé le 20 octobre 2026 sur de vrais RAF (X-H2S, X-T4, X-T20),
  MakerNote lue à la main ; un HEIF de l'appareil n'est pas lu.
- Le point de mise au point dans `view_photo` (Fujifilm, lu par le serveur dans l'original,
  `Boitier.swift`, et placé dans l'image affichée, `PointAF.swift`) : un aperçu entier ou un zoom
  (`region`), jamais un avant/après (`compare`), envoie `point_af = true` à la commande `apercu` ;
  le module décrit alors la photo comme pour les vignettes (`Vignettes.decrireVignette` :
  `chemin_original`, `marque`, `geometrie`) et ajoute `point_af_toujours` (préférence
  `pointMiseAuPoint`), `evaluation` (`Notation.resume`) et, pour le bilan, `etapes_claude`
  (`nombre`, `derniere`) ; le serveur retire `chemin_original`, `geometrie`, `marque`,
  `point_af_toujours` et `etapes_claude` avant de répondre à Claude. Réponse : `point_af` { `x`, `y`
  (dans l'image affichée entière, de 0 à 1, sur un zoom aussi), `dans_la_zone` (zoom seulement),
  `nettete` (autour du point ; sur un zoom, dans le zoom, si le point y tombe), `appareil` (« mise
  au point signalée manquée »), `carre` (s'il est dessiné : « cadre AF rouge, point au centre »
  depuis le correctif 1.3.3, `ToolHandler.cadresAF` et `PreviewImages.marquerFocus`, sinon « vert »
  ou « rouge », puis « sur l'image » ou « sur le zoom ») }. Le carré (vert, rouge si l'appareil a
  signalé la mise au point manquée ; côté 6 % du petit côté, liseré sombre ;
  `PreviewImages.marquerPoint`) se dessine avec `af_point = true` (pour noter, ou montrer la mise au
  point) ou si la case « Mise au point » de la section de la liaison du Gestionnaire est cochée
  (`pointMiseAuPoint` de `Preferences.lua`, décochée par défaut) ; sur un zoom (demandé par Dany le
  20 octobre 2026), seulement si le point tombe dans la zone. Mesures et Vision sont prises avant le
  carré. Un seul lecteur pour `view_photo` (`ToolHandler.lecteurBoitier`), qui lit le point et
  l'intention d'une seule ouverture : une lecture bloquée n'en lance pas d'autres. Les consignes de
  la fenêtre (`Consignes.texte`) ont leur puce : « Mise au point montrée ou jugée : view_photo avec
  af_point = true, sur l'aperçu entier comme sur un zoom (region)… ».
