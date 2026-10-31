# CLAUDE.md — module Lightroom (Lua)

Règles du module « Développeur » (`Developpeur.lrplugin`) et de la fenêtre Claude, sorties du
CLAUDE.md principal, qui garde les règles communes à tout le projet.

- Le module est du **Lua 5.1** (celui de Lightroom) : pas de `goto`, pas de `//`. Le JSON passe
  toujours par `Json.lua`, qui lit et écrit les nombres sans dépendre de la locale (en français,
  `string.format` écrirait « 0,35 »). Dans une tâche asynchrone, `LrTasks.pcall` et non `pcall`
  dès que le code peut attendre (rendu, accès au catalogue) ou rendre la main (`LrTasks.yield`, par
  `Photos.rendreLaMain`, la seule copie, que `Releve.rendreLaMain` et `Historique` reprennent :
  seulement si `LrTasks.canYield`, jamais dans un comparateur de `table.sort` ni un rappel de
  `gsub`, jamais en parcourant par `pairs` une table qu'une autre tâche agrandit : en prendre les
  clés d'abord ; correctif 1.3.8). Un grand JSON s'écrit morceau par morceau par `Json.ecrivain`
  (accolades, virgules et clés dans `Json.lua` : le relevé du Suivi, correctif 1.3.8). `os.time` et
  `os.date` passent par `Compat.lua` (remplacés par `LrDate` s'ils manquaient).
- Toute écriture dans le catalogue passe par `withWriteAccessDo` (`ecrire` dans `Ecriture.lua`) ;
  la simulation des tests le vérifie.
- La mémoire de Claude (champs de `Metadonnees.lua`) se lit par `lireChamp` ou `lireJson` et
  s'écrit par `garder` : Lightroom copie ces champs dans une copie virtuelle, et seuls ceux-là
  vérifient qu'elle appartient à la photo (`proprietaireMemoire`). Dans une écriture, Lightroom
  relit un champ du module avec sa valeur d'avant l'écriture (constaté par ses effets) : `garder`
  ne rattache donc une photo qu'une fois par écriture (`Photos.nouvelleEcriture`, appelé par
  `Ecriture` au début de chacune), et la simulation ne montre un champ écrit qu'après l'écriture.
  Voir `docs/SPEC.md`, Mémoire des retouches.
- **L'avant/après d'une étape se garde au rendu, jamais par une écriture** (1.3, `Etapes.lua` ;
  `docs/SPEC.md`, Pourquoi ?) : Lightroom ne rend que l'état actuel. Toute étape nouvelle passe par
  `Ecriture.nouvelleEtape` (`{ id, nom, avant, le }`, id par `Ecriture.idEtape`) ; `etape_id`
  (résultats, journal, `annuler`) n'est pas un réglage ; une étape d'avant la 1.3, sans id,
  s'annule par son rang. La capture se fait autour de la commande (`Liaison.recevoir` :
  `Etapes.avantCommande`, `apresCommande` une fois la réponse partie, `abandonner` ; ces crochets
  ne laissent passer aucune erreur) : case Avant/après et fenêtre ouverte ou son Claude au travail
  (`Etapes.actifPour`), ou `avant_apres` (la recette seulement, jamais un outil) ; une seule
  photo, la photo active ; jamais `sans_avant_apres` (`match_series` l'envoie), ni en pause, ni
  pour un refus prévisible ; jamais un rendu avec des calculs IA en attente. L'avant est la vue
  (`Rendu.apercu` ne la garde que pour l'image entière de l'état actuel, jamais un zoom, un
  `chemin_avant`, un `essayer` ni une image entière de la composition) reconnue par l'empreinte,
  sinon un rendu avant l'écriture ; l'après est rendu après la réponse. Une capture à la fois
  (`ATTENTE` 8 s pour les commandes hors `SANS_ATTENTE`, `PERIMEE` 120 s) ; `COTE` 1 024. Dans
  l'empreinte (`sansVolatils`), une table vide sous une clé texte vaut une clé absente (constaté le
  21 octobre 2026 : `MaskGroupBasedCorrections` absente ↔ `{}` après une comparaison, une
  annulation de masque, les rendus du recalage) ; Lightroom ne change seul aucune clé (constaté).
  Captures de 0,51 à 1,06 s, réponse +4 % avec une vue, +0,8 s sans ; ménage au chargement
  (`Etapes.menage`, 30 jours, 500 Mo).
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
  retirée au correctif 1.3.6 ; `Vignettes.decrireVignette`), sinon `prise_de_vue.iso` d'un module 1.3 ;
  `view_photo` retire `sensibilite` avant Claude. Pas le plafond de note (`Notation.plafond`), qui
  juge l'image, ni le tri, qui ne fait que dire la mesure. Les constats notés avant restent tels
  quels ; `constats_prise_de_vue`
  seulement si le module répond `note = true`, erreurs tues ; `noterAuCarnet` n'est vrai que dans
  `serve()` (ni `--call`, ni la recette, ni les tests), et seul lui fait demander les clés de la
  géométrie ; `view_photo`, `measure_angle` et `read_composition` restent `readOnlyHint`. Seuils
  `medianeSousExposee` 28, `p95SousExposee` 80 et `partBlancPurHaut` 3 % provisoires (aucun vrai
  cas). La case Carnet coupe les constats (elle devait couper aussi les leçons, décision de Dany du
  24 octobre 2026, devenue sans objet : la leçon est retirée au correctif 1.3.6). Depuis la fenêtre
  Claude, le carnet se voit dans la fenêtre Suivi, en graphiques depuis le correctif 1.3.7 (puce La
  fenêtre Suivi) : `--graphiques` lit `carnet.json` en lecture seule, et pour un original de même
  uuid, chaque code que le carnet a cherché (`vue.cherches`, le code de l'angle) l'emporte sur
  l'analyse d'office du Suivi ; une entrée du carnet absente du relevé ne compte pas, un carnet
  illisible fait une remarque.
- **Le Suivi : le relevé et l'analyse d'office** (correctif 1.3.7, décisions de Dany du 25 octobre
  2026 ; contrat figé dans `Tests/Contrats/suivi.json`, lu par `ContratSuiviTests`,
  `essais-releve.lua` et `essais-suivi.lua` : un changement voulu se fait des deux côtés).
  `suivi.json` (`Chemins.racine()`, format 1) n'est tenu que par `Releve.lua` (`Suivi.lua` est la
  fenêtre de la liaison, d'où ce nom), comme `carnet.json` par `Carnet.lua` : une table par
  catalogue (`cat:getPath()`), une entrée par original sous son id en texte (`original`, `uuid`,
  `fichier`, `ajout`, `ajout_le`, `vu`, `vues` : les photos vues de la famille, copies virtuelles
  comprises, `MAX_VUES` 20 ; `prise_de_vue` ; `note`, `drapeau`, `retouchee_par_claude` et
  `classement_le` de la famille ; `analyse`), `MAX_ORIGINAUX` 250 000 par catalogue depuis le
  correctif 1.3.8, 20 000 avant (les moins récemment vus sortent) ; tout lire puis tout écrire, par
  morceaux (relu par `Json.decode` avec un rythme ; écrit entrée par entrée par
  `Fichiers.ecrireParMorceaux`, un provisoire renommé d'un coup) ; illisible ou d'un
  autre format, mis de côté avant la première écriture (`suivi-illisible-<date>.json`, jamais
  écrasé) ; une copie neuve vers une vue ; rien n'est écrit au catalogue ; `uninstall.sh --tout` le
  retire. Qui entre : la sélection que voient `Fenetre.suivreSelection` et
  `FenetreRapide.suivreSelection` (`Releve.voirSelection` : une même clé ne compte qu'une fois,
  `Releve.revoir` à l'ouverture ou au rappel d'une fenêtre la fait compter même inchangée, une autre
  photo active dans le même groupe ne revoit qu'elle, comme une sélection de plus de `SEUIL_REVOIR`
  (2 000) photos revue moins de `REVOIR_APRES` (600 s) après sa vue entière ; `MAX_SELECTION` 250 000
  depuis le correctif 1.3.8, 1 000 avant, le reste dit au journal), par son original (`masterPhoto` d'une copie virtuelle, une seule fois), sauf les vidéos
  et les photos de « Développeur › Essais » (`Carnet.estPhotoDEssai` : elle ou son original ; pour une
  vue d'au moins `SEUIL_ESSAIS` (200) photos, lues d'un coup par `Carnet.photosDesEssais`, les
  collections Essais des ensembles Développeur, sinon photo par photo comme avant). La
  famille (l'original et ses copies hors Essais, `virtualCopies`, par lectures groupées, sinon une à
  une) donne la note la plus haute, le drapeau (« retenue » si l'une l'est, « rejetee » si toutes)
  et « retouchée par Claude » (`proprietaireMemoire`, comme `Photos.decrireTout`), relus à chaque
  vue et par `Releve.reclasser` à l'ouverture de la fenêtre Suivi (après son premier dessin, dans sa
  propre tâche, un seul à la fois). Pas de rattrapage : le Suivi part
  de zéro à l'installation. La file d'analyse, ce sont les entrées sans analyse, ou en erreur non
  abandonnée (elle reprend d'elle-même après une fermeture de Lightroom) ; une seule tâche
  (`Releve.vider`, que `Releve.relancer` lance depuis les boucles de la fenêtre Claude, de la Demande
  rapide et de la fenêtre Suivi) range d'abord les vues (des lectures du catalogue, même pendant que
  Claude travaille ; au-delà de `MAX_EN_ATTENTE` 20 vues en attente, elles se fondent en une, sans
  perdre de photo), puis analyse par lots de `LOT_ANALYSE` 10, la photo active nouvellement vue en
  tête : la vignette de l'original à `TAILLE_VIGNETTE` 1 024 (`Vignettes.demander`, dans
  `Temporaire/Suivi`, effacé après la réponse et au chargement : `Menage.TEMPORAIRES`), redressée
  (`Images.redresser`), puis `perl alarm 60` et `--analyser` (commande Analyse du Suivi), avec
  `retouchee` pour un original que Claude a retouché (seuls flou et yeux fermés s'y cherchent) et,
  depuis le correctif 1.3.8, l'objectif de la prise de vue (le genre macro).
  L'analyse attend pendant que Claude travaille (`Moteur.travaille`) ou que la liaison sert
  (`Lightroom.liaisonOccupee` : Claude Desktop, Claude Code en terminal, la recette ; une commande
  en cours ou finie depuis moins de 5 s : un trou plus long entre deux commandes de la recette
  laisserait partir un lot) ; un lot commencé juste avant est remis sans compter d'essai. Une
  analyse n'est jamais refaite après une édition (les défauts disent la prise de vue ; une retouche
  les cacherait), seulement pour des `regles` plus récentes ; le genre (correctif 1.3.8, demandé par
  Dany le 26 octobre 2026 : `analyse.genre`, un code de `Genre`, et `analyse.regles_genre`) a ses
  propres règles : une analyse sans genre, ou d'un genre de règles plus anciennes, se refait pour le
  genre seul, ses défauts, son `le` et son `regles` gardés ; sans genre, même avant toute réponse de
  la séance (les règles ne s'apprennent que d'une réponse, et toute la bibliothèque de Dany était déjà
  analysée), sauf si le connecteur répond sans `regles_genre` (`Releve.sansGenre`, pour la séance) ;
  un genre refait qui échoue garde l'analyse d'avant (`Releve.sansRefaire`) ; une erreur (une raison de
  `--analyser`, `pas_de_reponse`, `photo_introuvable`, `module`) compte un essai, réessayé
  `DELAI_REESSAI` (600 s) plus tard (devant la file gardée, `Releve.reessais`), l'entrée abandonnée
  au `ESSAIS_ANALYSE`-ième (3). Les écritures du fichier, vues et analyses comprises, sont espacées de
  `Releve.delaiEcriture` : au moins `DELAI_ECRITURE` (20 s : une écriture par photo parcourue aux
  flèches figeait Lightroom), `FACTEUR_ECRITURE` (10) fois la durée propre de la dernière (la somme
  de ses morceaux, sans le temps des autres tâches quand elle rend la main) et `SECONDES_PAR_MO` (1)
  par Mo du fichier (écrit ou relu ; chaque écriture l'écrit en entier : 85 000 originaux, 57 Mo,
  environ toutes les 57 s), au plus `DELAI_ECRITURE_MAX` (60 s : ce qui n'est pas écrit se perd si
  Lightroom quitte, `Arret.lua` ne s'exécutant pas ; les analyses se refont, une vue d'une photo
  nouvelle non), pendant une pause comme hors d'elle (plus d'écriture forcée au début de chaque
  pause depuis le correctif 1.3.8 : une liaison qui sert par moments réécrivait tout le relevé toutes
  les 7 s), sauf avant un dessin demandé de la fenêtre Suivi (`Releve.ecrire`, qui attend d'abord une
  écriture en cours) ; en fin de file, la tâche attend son tour en rangeant les vues qui arrivent. Toute la bibliothèque (correctif 1.3.8) : aucun morceau de calcul
  de plus de quelques centièmes de seconde sans rendre la main (`Releve.rendreLaMain` :
  `LrTasks.yield` seulement si `LrTasks.canYield`, sous `LrTasks.pcall`, qui ne laisse passer aucune
  erreur ; jamais sous un `pcall` simple, que Lua 5.1 refuse : la relecture et l'écriture passent par
  `LrTasks.pcall`, et `essais-releve.lua` compte les yields à travers un `pcall` simple), toutes les
  `PAS` (2 000) entrées des boucles, `PAS_UNE_A_UNE` (200) lectures une à une du catalogue,
  `LOT_LECTURE` (500) photos des lectures groupées, `PAS_ECRITURE` (500) entrées écrites et
  `PAS_JSON` (10 000) valeurs relues. Une seule relecture à la fois (les autres tâches l'attendent :
  deux registres, et ce qui change dans le premier se perdrait), une seule écriture à la fois (une
  autre l'attend, `Releve.ecrire` compris ; hors d'une tâche, laissée à la suivante), `aEcrire` remis
  à faux dès le début de l'écriture (ce qui se range pendant s'écrit à la suivante), abandonnée si le
  Suivi s'éteint (le fichier d'avant tel quel, aucun provisoire), l'enveloppe JSON par
  `Json.ecrivain` ; le texte JSON de chaque entrée est gardé (`jsonDe`, clés faibles) jusqu'à ce
  qu'elle change (`changee`, que doit appeler tout ce qui change une entrée : `rangerVue`,
  `poserClassement`, `manquee`, l'analyse réussie) : une écriture pendant l'analyse ne refait que les
  entrées changées. `poserClassement` ne change une entrée que si sa note, son drapeau ou
  « retouchée par Claude » changent (`classement_le` : l'heure de ce changement, ou de leur première
  lecture) : `Releve.reclasser` sans rien de changé n'écrit rien, et rend le nombre d'entrées
  changées ; une entrée qu'une vue range pendant qu'il tourne (`Releve.revues`) garde le classement
  de la vue. La file d'analyse se garde d'une vue à l'autre : les originaux d'une vue rangée, et un
  lot remis, passent devant (`mettreDevant`), une analyse manquée aussi, à son heure
  (`Releve.reessais`, `MAX_REESSAIS` 1 000 ; au-delà, elle attend que la file se refasse) ; elle ne se
  refait entière qu'épuisée, ou quand une réponse apporte des règles plus récentes (la première de la
  séance comprise : `Releve.file` remis à nil), par `construireFile` (`Releve.refaireFile` pour les
  essais), par paquets de même heure de vue triés en nombres (`trierParVu` : le rang dans la
  sélection puis l'identifiant, jamais un tri de textes, que Lua 5.1 compare par `strcoll`, ni un
  comparateur Lua sur toute la liste) ; `elaguer` ne trie qu'au-delà de la borne, d'après l'heure de
  vue de chaque entrée lue d'abord (une entrée revue pendant le tri reste). Une sélection que la
  fenêtre Suivi pose (`FenetreSuivi.montrerPhotos`, par `Releve.poserSelection`) ne se range pas :
  pendant la pose, aucune sélection vue ne compte, puis elle est notée vue (`cleVue`, `groupeVu`) ;
  ses photos sont déjà au relevé. Mémoire (correctif 1.3.8, mesurée sous `luajit -joff` par la revue,
  Lua 5.1 d'après un modèle) : le registre et `jsonDe` tiennent environ 0,2 Go à 85 000 originaux et
  0,6 Go à 250 000 dans Lightroom, pendant toute la séance, à peu près le double un moment à la
  relecture (le texte, l'arbre décodé et le registre ensemble) et à la première écriture. Le
  Suivi ne tourne que dans Lightroom : `Releve.allume` est faux par défaut, `Init.lua` l'allume
  (`Releve.allumer`), `Arret.lua` l'éteint (`Releve.eteindre` : `arrete`, plus aucune vue, aucune
  tâche, ni connecteur lancé ni écriture après l'attente en cours ; après un rechargement,
  l'ancienne instance ne réécrit jamais le relevé que tient la nouvelle, au prix des vues d'un
  `Releve.delaiEcriture` au plus, 60 s) ; les essais d'Init des deux suites l'éteignent ensuite (`tests.lua`,
  `essais-une-photo.lua`). Côté connecteur, `Suivi.codes` (les huit comptés, dans l'ordre de
  `PriseDeVue` : `codesAnalyse`, les six de `--analyser`, et `codesCarnet`, `horizon_penche` et
  `mise_au_point`, que seul Claude mesure) ; aucune liste de défauts dans le module ; l'analyse
  reprend les seuils du tri et du carnet sans en ajouter. `Genre.swift` (correctif 1.3.8) est la
  seule liste des genres et de leurs règles (onze codes, de `sport` à `autre` ; `Genre.classer`, pure :
  la première règle qui convient, sport, fêtes et événements, famille et groupes, portrait, macro,
  animaux, nourriture, véhicules, ville et architecture, paysage, autre ; les visages à l'envers
  écartés, `Genre.visages` par `Composition.visagePlausible` ; la fleur jugée sans « plant » ni
  « foliage », que Vision donne avec toute fleur, `Genre.sceneAutourDUneFleur` ; chaque étiquette
  connue de Vision, `GenreTests` ; seuils provisoires relevés le
  26 octobre 2026 sur les vignettes de 60 photos de Dany, 52 sur 53 rangées comme à l'œil ; ni
  nourriture, ni macro, ni fête, ni nuit dans ce relevé) ; aucune liste de genres dans le module. Rien du Suivi ne part chez Claude : aucun
  outil ne lit `suivi.json`. Reste à constater dans Lightroom : `batchGetRawMetadata` avec
  `masterPhoto` et `virtualCopies` (sinon une à une), `focalLength` en nombre (un texte « 23 mm » se
  lit aussi), une vignette de 1 024 rendue pour l'analyse.
- Un profil d'appareil se pose toujours par `libererProfil`, qui vide `MissingCameraProfile` :
  Lightroom y garde un nom introuvable, et tant qu'il y reste, tout profil suivant retombe à Adobe
  Standard. Il se relit après coup (`attendreProfils`) : Lightroom ne remplace un nom introuvable
  qu'une fraction de seconde après l'écriture. Les noms des simulations Fujifilm sont ceux que
  Lightroom range pour un X-H2S (casse indifférente, ponctuation exacte), dans le catalogue du
  serveur avec leurs `variants`. Voir `docs/SPEC.md`, Profil.
- Ce qui revient du JSON passe par `pourLightroom` avant `applyDevelopSettings` : une table qui
  porte une métatable (tableau relu par `Json.decode`) bloque Lightroom sans erreur, verrou
  d'écriture compris (voir `docs/SPEC.md`, Profil). La simulation de la liaison refuse les
  métatables.
- Ce que Lightroom ne calcule pas quand il est posé par `applyDevelopSettings` (tonalité et balance
  des blancs automatiques, masques IA, flou d'objectif, profils adaptatifs) passe par un paramètre
  prédéfini du module (`addDevelopPresetForPlugin` puis `applyDevelopPreset`). Un profil adaptatif
  n'y est marqué à calculer que si sa Look porte `isAdobeAdaptive` et le paramètre prédéfini
  `AILook = {Active = true}` (`poserAdaptatif`) ; les nombres des fichiers de profil restent des
  nombres (`ProfilsLook.convert`). Le calcul (masques IA, profil adaptatif, flou d'objectif, outil
  Supprimer) se fait par `photo:updateAISettings()`, **hors** de `withWriteAccessDo`, après
  l'écriture (`Ecriture.calculerIA`, deux passages au plus) et avant un rendu
  (`calculerAvantRendu`) ; un profil adaptatif se recalcule ainsi après une tache ou un flou, pas
  après une rotation, qui ne le change pas (constaté). Ce que Lightroom n'a pas pu calculer
  (modèles IA absents) ouvre au rendu la fenêtre « Mises à jour IA recommandées », qui attend
  l'utilisateur : rien n'y répond à sa place. Un tel paramètre prédéfini fait tomber une balance
  des blancs personnalisée aux butées : tout plan passe par `appliquerPlan`, qui la repose
  (`noterPresetDuModule` la mémorise). S'il porte `MaskGroupBasedCorrections`, il **remplace** les
  masques de la photo : il doit porter la liste entière, masques existants compris
  (`masquesParPreset`). Une liste de taches vide ne les retire pas : vider aussi `RetouchInfo`
  (`aRemettre`). Voir `docs/SPEC.md`. Le nom d'un paramètre prédéfini du module dont le contenu
  varie suit ce contenu (`presetContenu`) : Lightroom range un fichier par nom. Le module les
  efface à son chargement (`Menage.lua`, depuis `Init.lua` : à la fermeture de Lightroom,
  `Arret.lua` ne s'exécute pas, constaté) et à son arrêt ; `install.sh` aussi, Lightroom fermé
  seulement.
- La suppression des reflets (`Suppression.lua`, commande `supprimer`) suit le même chemin que le
  débruitage (photo affichée, hors de `withWriteAccessDo`, un seul traitement à la fois) ; l'état
  d'avant va dans la mémoire sous la clé `Suppression`, qui n'est jamais un réglage (la simulation
  le refuse) ; une autre intensité se pose en retirant puis reposant le filtre
  (`changeReflectionRemovalAmount` ne change rien au filtre rangé, constaté). `annuler` et
  `revenir` remettent les traitements calculés par `Annulation.remettreCalcules`.
- Débruitage, détails bruts et super résolution passent par `LrDevelopController`
  (`setEnhance`), sur la photo affichée dans le module Développement : le module l'y affiche,
  seule sélectionnée, laisse le temps de la charger, puis remet la vue. Un seul traitement à la
  fois (`avecVerrou`). Ces appels se font **hors** de `withWriteAccessDo` (la simulation le
  refuse) ; l'état d'avant va dans la mémoire, écrite avant le calcul, sous la clé `Amelioration`,
  qui n'est pas un réglage et ne doit jamais partir dans `applyDevelopSettings` (la simulation le
  refuse aussi).
- Le classement dans la Bibliothèque (note, drapeau, libellé, textes, texte alternatif, champs
  IPTC, position GPS, mots-clés, collections) se garde dans la mémoire sous la clé `Bibliotheque`,
  qui n'est pas un réglage : jamais dans `applyDevelopSettings` (la simulation le refuse) ;
  `annuler` et `revenir` la remettent par `Bibliotheque.remettre`. Titre, légende, droits d'auteur
  et libellé se lisent par `getFormattedMetadata` : `getRawMetadata` les refuse (la simulation
  aussi). Le libellé s'écrit comme un texte du jeu de libellés actif, vérifié par
  `colorNameForLabel` après l'écriture seulement ; un texte s'efface par un texte vide, jamais par
  nil (`ecrireChamp`). Une collection (et, supposé, un ensemble) ne se lit pas dans l'écriture qui
  l'a créée : la créer dans sa propre écriture, puis l'employer dans la suivante. Un mot-clé, lui,
  se crée et se pose dans l'écriture du classement (constaté), sans jamais y être lu (`getName` y
  échoue). Un paramètre prédéfini de métadonnées ne se voit qu'après l'écriture qui l'applique :
  relu ensuite (`relirePresetsMetadonnees`). Voir `docs/SPEC.md`, Bibliothèque.
- Le libellé se pose d'abord par le texte que donne `getLabelMapToColorName` (texte → couleur,
  constaté). Une position GPS s'efface par `setRawMetadata('gps', nil)` (constaté) ; l'état d'avant
  sans position est `{ aucune = true }`. Un champ IPTC donné un à un et un paramètre prédéfini de
  métadonnées ne vont pas dans le même appel. Le jour d'une prise de vue se lit à l'heure locale
  (`timeToUserFormat`) : `timeToW3CDate` donne l'UTC (constaté).
- Le filtre de la Bibliothèque (`montrer`) se bâtit sur une copie du filtre actuel et se remet par
  ses valeurs exactes, jamais par un paramètre prédéfini : un filtre sans `columnBrowserDesc`, et
  « Filtres désactivés », remettent les colonnes du filtre Métadonnées par défaut (constaté). Un
  critère vide vaut « <nil> », le libellé « sans » est `noLabel`.
- Renommer, déplacer une collection ou changer ses critères, renommer un mot-clé ou ses synonymes
  touche la structure du catalogue : jamais de suppression, pas d'étape pour `undo_last` (la
  réponse donne l'état d'avant).
- Une commande qui calcule sur l'original (débruitage, détails bruts, super résolution, reflets)
  passe par `Photos.exigerOriginal` ; un rendu sans original ni aperçu dynamique est refusé
  (`rendre`) ; une livraison saute la photo. `checkPhotoAvailability` suit le disque à quelques
  secondes près (constaté).
- Un aperçu (`rendre`) fait passer `isExported` à vrai (constaté) : `apercuSeulement` le note, une
  livraison (`exporter`) ou une publication de la fenêtre Publication (`Publication.publier`)
  l'efface, en écriture privée ; « exportée » se lit par `Photos.exportee`, jamais par
  `isExported` seul.
- Les listes de photos se décrivent par `Photos.decrireTout` (lectures groupées du catalogue) ;
  « retouchée par Claude » n'y compte que si `proprietaireMemoire` est l'uuid de la photo.
- Une personne précise (`add_mask`, `kind: "person"`) porte `InstanceIDs` **et** `InstanceBounds`,
  les cadres de toutes les personnes (le serveur les tire de Vision, `detecterPersonnes`) : sans
  eux, Lightroom ne la reconnaît pas (constaté). Sauf la personne seule d'une photo (Vision n'en
  trouve qu'une : `seule`) : faite à la main, elle n'a ni l'un ni l'autre, seulement le sous-type 0
  et sa catégorie, et le module l'envoie ainsi (`Locaux.personne`) ; numérotée, Lightroom la calcule
  de même puis retire le numéro (constaté le 20 octobre 2026, même `MaskDigest`).
  `Locaux.numeroPersonne` la compte comme la personne 1 (`Locaux.CATEGORIES_PERSONNE` : le
  sous-type 0 sert aussi à l'arrière-plan et au paysage). `sansCalculsIA` garde les cadres ;
  `Retouche.verifierPersonnes` retire un masque non reconnu après le calcul. Les masques vides se
  retirent par `deleteAllEmptyMasks`, hors de `withWriteAccessDo` (`Masques.retirerVides`).
- Un module ne peut pas : lancer ni faire refaire la poussière (le module ne fait que la retirer ;
  copiée, elle colle les taches de la source), convertir une version de processus 1 ou 2
  (`setProcessVersion` ne fait rien), mesurer la profondeur d'un cadre du flou d'objectif, calculer
  l'Upright avec repères (posés, la transformation attend le clic « Mettre à jour » de
  l'utilisateur). Constatés le 18 octobre 2026 : voir `docs/SPEC.md` ; ne pas les réessayer sans
  nouvelle piste.
- Le module n'agrandit plus, mais une photo déjà agrandie par l'ancien connecteur
  (`Reglages.estAgrandie` : cadre hors de [0, 1]) reste protégée : Claude ne la recadre pas
  (`preparerRecadrage` refuse), son recadrage ne se copie ni vers elle ni depuis elle, et
  « Contraindre le recadrage » n'y est pas coché.
- `LensProfileSetup = "LensDefaults"` ne tient que par un paramètre prédéfini du module avec
  `LensProfileEnable` (`presetObjectifParDefaut`), à l'application comme à l'annulation.
- Une rotation d'un quart de tour (`Conversions.lua`) se fait hors de `withWriteAccessDo` et se
  garde sous la clé `Rotation` de la mémoire, qui n'est pas un réglage.
- L'état laissé par Claude (`apresClaude`, pour relever les corrections faites à la main) s'écrit
  par `noterEtatFinal`, en écriture privée (`withPrivateWriteAccessDo`) : jamais une écriture
  ordinaire, qui ajouterait une opération à Édition › Annuler. Toute écriture de la mémoire seule
  (sans réglage ni instantané) passe de même par `Ecriture.ecrireMemoire` ; la mémoire d'une étape
  s'écrit avec ses réglages, dans la même écriture ordinaire.
- Une variante (`compare_variants`) se range en instantané par `createDevelopSnapshot` (dans une
  écriture, avec la mémoire `variantesClaude`) ; `applyDevelopSnapshot` et `deleteDevelopSnapshot`
  sont des commandes du module Développement : **hors** de `withWriteAccessDo` et photo affichée
  dans le module Développement (`Amelioration.afficherEnDeveloppement`, puis `remettreVue`),
  `snapshotID` pour poser, `id_global` pour effacer (constaté ; la simulation refuse le reste).
  La mémoire de l'étape s'écrit avant, et se retire si l'instantané n'a rien changé.
- Une livraison (`exporter`) passe par `LrExportSession` avec `LR_collisionHandling = 'rename'` :
  jamais `overwrite` hors du dossier temporaire d'un aperçu. Elle ne change pas les photos ; ses
  lots suivants (`suite`) ne redemandent pas l'accord. Les modèles de noms et les filigranes se
  lisent dans les `.lrtemplate` de l'utilisateur, côté serveur (`FilenameTemplates`,
  `FiligranesUtilisateur`) ; les noms exacts, par `getNameViaPreset` (commande `nomsFichiers`).
  Les livraisons types sont les réglages des services Disque dur, lus clé par clé
  (`Services.lua` ; côté serveur, `profilService`) : le module ne crée, ne change ni ne publie
  aucun service. Une sortie HDR n'est faite que pour une photo en mode HDR, dans les espaces et
  profondeurs que Lightroom offre (pas de HDR Rec. 2020 en JPEG ; JPEG 8 bits, AVIF 10, 32 bits
  seulement en HDR) : voir `docs/SPEC.md`, Formats, HDR, poids, filigrane. Une photo sans
  original ne part que depuis son aperçu dynamique, 2560 px au plus (`depuisApercu`) ; un aperçu
  dynamique ne se retire jamais d'une photo dont l'original manque.
- Une livraison réimportée et empilée va dans le dossier de l'original (`sourceFolder` : Lightroom
  n'empile que là) ; `undo_last` ne la retire pas. Seule la recette retire une photo réimportée
  (`retirerReimportees` : chemin exact réimporté par le module dans la même session, puis le
  fichier à la Corbeille) ; jamais vers un dossier neuf en essai, qui resterait au catalogue.
- La fenêtre de choix du dossier (`choisirDossier`, `runOpenPanel`) s'ouvre dans sa propre tâche :
  la commande répond sans attendre l'utilisateur (40 s au plus, puis `en_attente`).
- Le module signale la photo active changée avec sa réponse suivante (`evenements`, avec son `id`,
  seulement si elle n'est plus celle signalée la dernière fois) ; le serveur le transmet aux
  clients abonnés (`resources/subscribe`), sinon le dit une fois au résultat d'outil suivant
  (Claude Desktop ne s'abonne pas, constaté). Rien ne part sans une commande.
- Une photo hors du film fixe se sélectionne après l'affichage de son dossier, avec un délai
  (`selectionnerAvecSource`, constaté) : passer par lui. De même pour la remettre : après un
  passage au module Développement (débruitage, son annulation, variante), une copie virtuelle ou un
  TIFF réimporté retiré, la source, la photo active et la sélection d'avant reviennent par
  `Bibliotheque.remettreSelection` (sélection refaite pendant `DELAI_SOURCE`, photo active relue,
  « Photo active d'avant non remise » au journal ; constaté le 21 octobre 2026 : sans attendre,
  une autre photo restait active), et la simulation de la liaison l'impose (`S.visiblesSous`). Le
  connecteur n'ouvre un original que
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
- Un aperçu attend le calcul des masques IA (`attendreCalculsIA`) : sinon Lightroom ouvre la
  fenêtre « Mises à jour IA recommandées », qui bloque l'exportation jusqu'à la réponse de
  l'utilisateur. Toute exportation calcule d'abord les réglages IA : `calculerAvantRendu` pour la
  liaison, `photo:updateAISettings` dans `Publication.publier` pour la fenêtre Publication. Ni le
  serveur ni le module ne demandent la permission d'Accessibilité (elle irait à Claude Desktop, au
  terminal ou à Lightroom).
- Le registre des notes proposées (`Notation.lua`) sert la liaison (commande `notation` :
  `proposer`, `lire`, et depuis la 1.3 `remettre`, la recette seulement, jamais un outil, qui remet
  une proposition telle que lue avant une étape, ou la retire ; rien dans le catalogue, sauf
  `proposer` avec `poser`) et la carte Note de la fenêtre Claude. Il se charge dans les deux
  simulations : `Bibliotheque` n'est requise qu'au moment d'écrire, et rien de l'interface (un test
  le vérifie). Il est rangé dans `notation.json`
  (`Chemins.racine()`, format 2 : les propositions seulement ; un registre plus ancien perd ses
  séances à la relecture), propre au catalogue ouvert (chemin gardé ; un autre catalogue trouve un
  registre vide), les photos en clés texte (`Json.decode` rend des clés texte), chacune avec son
  uuid (une photo d'un autre uuid perd sa proposition) ; tout ce qui en sort vers une vue est une
  table neuve. Toute nouvelle proposition commence « à vérifier » (état `a_verifier`, depuis la
  1.1.1) : Dany l'accepte ou la change ; `to_check` (champ `a_verifier`) dit en plus que Claude
  doute ; l'état `proposee` ne reste que pour les propositions d'avant la 1.1.1.
  `Notation.resume` en tire l'évaluation que `view_photo` donne (« pas encore évaluée », « 3 ★
  proposée par Claude, à vérifier », « acceptée par l'utilisateur : 3 ★ », « changée par
  l'utilisateur : … »). La fenêtre s'abonne (`Notation.abonner('fenetre', …)`) et compare
  `Notation.version`. Le registre ne voit pas une annulation (undo_last, ⌘Z : constaté le
  20 octobre 2026) : quand la fenêtre relit la note et le drapeau de la photo active
  (`Fenetre.majPhoto`), elle appelle `Notation.recaler(releves, version)`, avec `Notation.version`
  lue avant la photo (un relevé plus vieux qu'une note posée entre-temps, ou fait pendant une
  écriture de `Notation.poser`, ne défait rien) : une proposition acceptée ou changée dont la note
  n'y est plus redevient `a_verifier`, à accepter ou changer de nouveau ; mais une note posée puis
  annulée sur une photo qui avait déjà cette note reste « acceptee » (constaté le 21 octobre 2026
  par la recette : `recaler` n'y voit rien), d'où `remettre` dans la recette. L'élément `notation`
  du fil (appel de `propose_ratings`) ne sert qu'à l'affichage : le registre reste la source.
- Une proposition ne devient une note posée que par `Notation.poser`, puis `Bibliotheque.noter` :
  une écriture (`ecrire`) par lot de 500 photos, une étape « Claude · notation » par photo que
  `undo_last` défait, mémoire `Bibliotheque` gardée ; garde-fous des photos (`verifierProtection` :
  copies virtuelles seulement, libellé protégé, photos rejetées) maintenus. Deux chemins :
  Accepter, Changer…, les étoiles et les drapeaux de la carte Note (`Fenetre.poserEtoile`,
  `Fenetre.poserDrapeau` ; Retenir ou retirer un drapeau ne décide pas la proposition, Rejeter si),
  dans une tâche, jamais pendant que Claude travaille ni pendant une note en cours (refus dits au
  bandeau), où
  `depuisLightroom` et `confirme` lèvent la pause, « Proposer d'abord » et le plafond de photos
  par écriture (le clic vaut accord explicite) ; ou Dany demande à Claude « note ces photos » ou
  « pose les notes » (`propose_ratings` avec `apply = true` : `Notation.proposer` avec `poser`,
  puis `Notation.poser` avec `depuisLightroom = false` et `confirme = true`, « à vérifier »
  comprises), où la pause de la liaison l'arrête, mais ni « Proposer d'abord » ni le plafond (la
  demande explicite vaut accord ; l'accord dans Lightroom, `accordDansLightroom`, se demande
  encore : son refus dit de rappeler `propose_ratings` avec `apply = true`, car `Notation.poser`
  passe `outil` à `Bibliotheque.noter` ; `rappel` dans `Ecriture.lua`). Réponse : `posees` (et
  `erreur_pose`) ; le titre de l'élément du fil dit « Notes à poser » pendant l'appel, puis
  « Notes posées » si au moins une l'est, sinon « Notes non posées » (pause, accord attendu), et
  chaque photo « posée » ou « non posée : <raison> ». Une note posée ainsi n'entre pas dans l'état
  d'avant Claude (`memoriser` sans `fusionnerOriginal`) : « Revenir à « Avant Claude » » et
  `revert_to_original` la laissent en place ; `undo_last` la défait toujours, étape par étape.
  Accepter pose la proposition telle quelle : un rejet pose le drapeau sans toucher les étoiles,
  une note ne retire qu'un rejet déjà posé (un drapeau Retenue reste). Laisser (« Laisser à N ★ »)
  écarte la proposition par `Notation.decider` `ecartee`, sans rien écrire au catalogue.
- Dans la fenêtre Claude, toute photo que Claude traite, il la note d'abord, avant d'y toucher
  (puce Notes de `Consignes.texte`, demandé par Dany le 20 octobre 2026) : `cull_photos` sur elle
  (plancher technique ; sans `photo_ids`, `selection`, `collection` ni `folder`, il prend la photo
  active par la commande `etat` depuis la 1.3.1, car Claude l'oubliait 2 fois sur 4 ; sans photo
  active, le refus « Photos à traiter » ; `contact_sheet`, lui, demande toujours une série), `view_photo` avec `af_point = true`, puis `propose_ratings` sans `apply` ;
  sa note arrive « à vérifier » dans la carte Note, où Dany l'accepte, la laisse ou la change
  (Accepter, Laisser, Changer…, les étoiles). Une photo déjà évaluée (`view_photo` : `evaluation`)
  ne se renote pas, sauf s'il le demande. Ni Noter ni Évaluer : ni dans les invites, ni dans la
  carte Note (`Fenetre.noter`, `Consignes.noterPhoto` et `Consignes.noterSelection` retirés) ;
  « ? À vérifier » est posé grisé, sans action (`Vues.inactif`, décision de Dany du 21 octobre
  2026 ; `Fenetre.verifierNote` reste nil ; le remettre comme « remettre à vérifier » par
  `Notation.decider` est une question ouverte), et les essais le vérifient ; l'aide de la carte
  Note (`Fenetre.AIDE_NOTATION`) le dit. Les consignes du connecteur (`ServerInfo`, Claude Desktop) ne
  demandent pas cette note d'abord.
- Lightroom ne sait pas tenir un processus par ses tuyaux : `relais.sh`, lancé par
  `LrTasks.execute`, garde Claude Code ouvert pour une conversation (`entree.jsonl` passé par
  `tail -f`, `sortie.jsonl` relu par le moteur) et le ferme quand Lightroom n'est plus là. Claude
  Code ne reçoit que le connecteur (`connecteur.json`, `--strict-mcp-config`, outils
  `mcp__developpeur__*`, `Conversation.PREFIXE_OUTILS`), aucun outil intégré (`--tools ""`), rien
  qui demande une permission, ni compétences ni réglages de l'utilisateur, dans le dossier de
  travail vide `Atelier/`. Le modèle (`--model` : fable, opus par défaut, sonnet, haiku) et
  l'effort (`--effort` : max par défaut, xhigh, high, medium, low, le même pour les quatre
  modèles ; Claude Code 2.1.303 accepte `--effort max` avec les quatre, constaté le 20 octobre
  2026) se choisissent dans le Gestionnaire de modules externes (section Fenêtre Claude, menus
  Modèle et Effort de `PluginInfoProvider.lua` ; préférences `modele` et `effort`), et non plus
  dans la fenêtre ; une valeur inconnue retombe sur celle par défaut (`Moteur.modeleEtEffort`).
  `relais.sh` reçoit l'effort en 4e argument (vide : celui de Claude Code) et `consignes.md` en 8e,
  écrit dans le dossier de chaque session (`Session:lancer`, `Consignes.texte`). Un seul processus
  Claude Code à la fois : une autre conversation, un autre modèle ou un autre effort le relance à
  la demande suivante, en reprenant la session (`--resume`, `Moteur.envoyer`). Voir
  `docs/SPEC.md`, Fenêtre Claude › Claude Code.
- Le presse-papiers ne se lit que sur un clic de l'utilisateur (bouton 📋, `presse-papiers.js`) ;
  les essais passent par un presse-papiers nommé, jamais le vrai.
- Toute table donnée à Lightroom par la fenêtre (éléments d'une liste, d'un menu, réglages
  d'exportation, valeur d'une propriété) est neuve : jamais une table relue par `Json.decode`
  (métatable, Lightroom bloque ; la simulation de la fenêtre la refuse).
- La fenêtre ne peut pas changer de structure une fois ouverte, et une vue masquée garde sa place :
  tout ce qui varie passe par des propriétés liées (`bind`) et des variantes superposées de même
  taille (`place = 'overlapping'`). `visible` lié ne masque qu'une vue simple (texte, bouton,
  image, menu, champ, case, liste, séparateur) et un `f:view` (constaté le 21 octobre 2026, D10) :
  sur `row`, `column`, `group_box`, `tab_view` et `scrolled_view`, Lightroom l'ignore (constaté le
  20 octobre 2026 : les trois onglets de la 1.1 s'affichaient superposés), et la simulation de la
  fenêtre refuse ces cinq-là. Une condition de visibilité passe toujours par `F.egal`, `F.non`,
  `F.si` ou `F.condition`, que `F.et` combine en une liaison à plusieurs clés (`keys`,
  `operation`). Le contenu d'un onglet se crée par une fabrique masquable (`Vues.masquable(f, F,
  condition)`, depuis `variante` de `Dispositions.lua`) : la condition sur chaque vue simple,
  combinée avec son propre `visible` ; seule la variante montrée répond (constaté, D11) ; pas de
  `group_box` dans un onglet, jamais `visible` sur la colonne d'une variante. Une propriété liée a
  une valeur avant l'ouverture (les tests le vérifient, pour chaque clé d'une liaison à plusieurs
  clés). `save_frame` garde la taille d'une ouverture à l'autre (`Fenetre.cadre()` :
  `DeveloppeurClaude-conversation-grande-<FORME>`, `Fenetre.FORME` 5 depuis le correctif 1.3.6
  (1 623 × 1 200, sans le volet), 4 pour 1 948 × 1 200, 3 pour 1 497 × 1 200, 2 pour la fenêtre B
  de 1 280 × 800, 1 avant) : quand le contenu change de taille, augmenter `Fenetre.FORME`.
- Contrôles de la fenêtre B, d'après les constats du 21 octobre 2026 (blocs A à D d'un module
  d'essai, dans `docs/SPEC.md` ; chacun a sa règle dans `Tests/Lua/Fenetre/Simulation.lua` et son
  essai) : fonds et filets en aplats (`Vues.aplat`, un `f:picture` sans image à
  `background_color`, A4 ; `background_color` est sans effet sur `row`, `column`, `view`,
  `group_box` et la fenêtre, A1 et A5 ; `primary_line_color` aussi, A6) ; images de
  `Dispositions.IMAGES`, un PNG 2x chacune, toujours avec `width` et `height`, chemin par
  `Fenetre.image` (jamais `images/<nom>.png` en dur) ; tout clic sur une image passe par un calque
  (`Fenetre.calque`, registre `Fenetre.parCalque` : un `mouse_down` sur un `f:picture` ne reçoit
  rien, C1 ; un calque n'a pas d'`enabled`, son gestionnaire vérifie l'état) ; tout bouton passe par
  `Fenetre.bouton` (`push_button`, ou `square_button` avec `carre` ; `icone` par `image_name`, sans
  titre, B3 ; `bezel` : cadre = bezel + 2, D5) ; les boutons bleus sont des images
  (`Vues.boutonBleu` : Envoyer, Accepter, Accepter N ★ ; image enfoncée 0,15 s) ; un élément de la
  maquette sans fonction est posé grisé, sans action (`Vues.inactif`, « À venir ») ; texte riche
  `<EM>` toujours avec `emphasis_font`, l'emphase de la même taille que le texte, `text_color` et
  `emphasis_color` ensemble, ni entité ni balise seule (B1, D4) ; `Fil.largeur` ignore les
  balises, `Fil.couper` les ferme et les rouvre ligne par ligne, les textes venus de Claude les
  perdent.
- Le champ de demande est `immediate = false` (Retour le valide). Aucun bouton par défaut dans la
  fenêtre (constaté D1 : Retour dans « Rechercher », `immediate = true`, déclencherait aussi le
  bouton par défaut) : Retour passe par l'observateur du champ et l'envoi automatique (0,3 s) ;
  Envoyer est un bouton bleu en image sous calque, Arrêter un carré superposé, montré pendant le
  travail. Tout bouton (`Fenetre.bouton`, `F.bouton` dans les pièces, `square_button` compris :
  `S.BOUTONS` des essais) et tout calque annulent l'envoi automatique (un clic valide d'abord le
  champ, constaté D3), et les essais le vérifient pour chacun : un `f:push_button` créé à part
  enverrait la demande tapée.
- L'apparence claire ou sombre (préférence `apparence` de `Chemins.defauts`, `claire` ; menu
  Apparence du Gestionnaire de modules externes, dite par le diagnostic ; une valeur inconnue
  retombe sur `claire` à l'emploi, `Dispositions.apparence`) : `Dispositions.PALETTES` est la seule
  table des couleurs (images et `Fenetre.COULEURS`), reprise à chaque ouverture
  (`Fenetre.preparerApparence`) ; deux jeux d'images, `images/` et `images/sombre/` (tableau
  Commandes, Images de la fenêtre) ; l'image « aucun aperçu » est `images/vide-498x332.png` et sa
  version sombre (`vide-320.png` est retirée) ; la palette sombre se lit au moins aussi bien que
  la claire (`essais-images.lua`) ; les contrôles natifs suivent l'apparence de macOS. Les polices
  sont celle du système et Menlo 11, mesurées par `scripts/metriques.swift` (D9 : l'encre fait 1 à
  2 points de moins que la chasse ; `Fenetre.largeurLibelle` ajoute 2 points à un libellé fixe).
- Ne jamais nommer un fichier du module `Versions.lua` : Lightroom refuse de le charger (constaté ;
  d'où `Composants.lua`). Un seul `Info.lua`, `Init.lua`, `Arret.lua` et `PluginInfoProvider.lua`
  pour la liaison et la fenêtre, sans fichier de fusion (`InfoFenetre.lua`…) :
  `scripts/tester-module.sh` refuse l'un et l'autre.
- Un raccourci d'app vise le titre exact de l'entrée de menu, tel que Lightroom l'écrit : trois
  espaces devant chaque entrée de module (`Raccourcis.RETRAIT`, constaté par l'accessibilité) ;
  `Raccourcis.LISTE` : ⌃⌥C (Ouvrir la fenêtre Claude) et ⌘⌃⌥C (Demande rapide, correctif 1.3.3).
  Lightroom ne lit les raccourcis qu'à son lancement : un rechargement du module ne suffit pas.
- Pas de calcul long en Lua sur la tâche de l'interface : base64, réductions d'images (`sips`) et
  commandes du système passent par `LrTasks.execute` (qui ne bloque que la tâche).
