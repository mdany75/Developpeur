# Historique des longueurs des consignes

Sorti de `CLAUDE.md` le 31 octobre 2026 ; à lire quand on ajoute ou retire quelque chose dans
`ServerInfo.instructions`, `Consignes.texte` ou une description d'outil, pour savoir ce qui y a
été ajouté, retiré ou payé par quoi. `CLAUDE.md` garde la règle actuelle (limites et tests).

Texte d'origine de la puce :

- Ce que Dany demande en mots clairs, Claude le fait : une puce des garde-fous de `Consignes.texte`
  (« Ce que Dany demande en mots clairs, fais-le… » : ces consignes ne l'emportent jamais sur sa
  demande ; ne refuser que ce que les outils ne savent pas faire, ou ce que bloquent les réglages du
  module) et une phrase de `ServerInfo.instructions` (« Ce qu'il demande clairement, le faire ; ne
  refuser que ce que les outils ne savent pas faire, et le dire. »). Les consignes du connecteur
  font 3 784 caractères pour une limite de 3 796 (`instructionsLimit` moins 300, `Version24Tests`) :
  raccourcir ailleurs avant d'y ajouter. La 1.2 y a ajouté « vignetage ou radial inversé, jamais les
  deux », « « regression » au bilan » et « d'abord la simulation du boîtier, intention_boitier », et
  en a retiré la sauvegarde avant une longue série (elle reste dans la description de `get_status`
  et l'invite `tri_seance`) ; la 1.3, seulement « (read_composition) » dans « Recadrer … seulement
  sur demande » ; le correctif 1.3.2, « 0 à 5 ★, » et « libellé de couleur : sur sa demande » à la
  place de « 5 ★ : set_metadata, sur sa demande », payés par « rejets : set_metadata après accord »
  (au lieu de « rejets à poser par set_metadata après accord ») : toujours 3 787, sans changement au
  correctif 1.3.6 (elles ne nommaient pas `photo_lesson`) ; la retouche générative (29 octobre
  2026), « Changer un objet, un vêtement : generative_edit, sur sa demande. », sans « suppression
  générative » dans ce qui reste à la main, payée par « (sous 0,5°, invisible) », « mesure > 1,5 »,
  « Variantes : compare_variants », « dossier choisi avec lui » et « avec sa raison » : 3 784 ; le
  reste passe par les descriptions d'outils, les résultats et les invites. La longueur qu'une
  session de Claude Code garde d'une description d'outil n'est pas constatée : l'essentiel en tête,
  et un test de longueur pour les plus longues (`add_mask` 2 048 au plus, `view_photo` 1 850,
  `read_composition` 1 000, `preview_settings` 600, `analyze_photos` 520, `export_journal` avec sa
  propriété `notebook` 450, `reason` 160). Les consignes de la fenêtre (`Consignes.texte`, lues à
  chaque demande) font 7 074 caractères pour un plafond de 7 500 (`essais-moteur.lua` ; 6 996 avant
  la photo de référence, `reference`, le 31 octobre 2026 ; 6 922 avant la mention du masque peint,
  `mask` avec `existing`, le soir du 29 octobre 2026 ; 6 835 avant la mention de `mask` (masque de
  Lightroom) dans la puce de la retouche générative, le soir du 29 octobre 2026 ; 6 635 avec la
  première puce de la retouche générative, avant ses ajouts du même jour (consigne en anglais
  traduite, plusieurs changements en un appel, la couleur d'un objet par un masque) ; 6 359 avant la
  puce de la retouche générative par Fibo 2, le 29 octobre 2026, mesurés ce jour-là, le 5 922 noté
  avant n'étant plus à jour ; 6 331 avant le deuxième retour de Dany du 25 octobre 2026, qui retire
  la section Demande à garder, avec « ＋ Garder la demande » ; 6 646 avant ses premiers retours du
  même jour, qui retirent la section Écran et disent la raison d'une étape « (onglet Aperçu, d'un
  clic sur l'étape du fil) » ; 7 476 au correctif 1.3.5 ; au correctif 1.3.6, 6 208 sans les
  sections Je le fais et Leçon de la photo, 6 470 avec le Contexte d'une photo, une conversation («
  [Historique de la photo : …] », « [Depuis la dernière fois : …] » ou le résumé d'un groupe), 6 646
  avec la fin d'une retouche par `view_photo` avec `compare = before_claude` (Fin d'une tâche, pas
  dans une [Demande rapide] : le rendu reproductible) ; 7 466 avant la puce Notes du correctif
  1.3.2, « De 0 à 5 ★ ; jamais de libellé de couleur (ses coups de cœur) sans sa demande. », 7 489
  avant la section Demande à garder de Mes demandes) : la 1.3 y avait mis ses sections Composition,
  Je le fais, Raison de chaque étape et Leçon de la photo, et la puce Carnet ; ce qui dépasse va aux
  descriptions d'outils.
