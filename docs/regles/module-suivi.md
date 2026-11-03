# Module Lightroom : le Suivi (relevé et analyse d'office)

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
`Releve.lua`, à `suivi.json`, à `FenetreSuivi.lua`, à `Suivi.swift`, à `Genre.swift`, à `--analyser`
ou à `--graphiques`.

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
  retire. **Le journal** (demandé par Dany le 2 novembre 2026 : pendant une analyse, 65 Mo réécrits
  au plus toutes les 60 s, des Go par heure sur le SSD) : une écriture ordinaire n'ajoute que les
  entrées changées depuis la précédente (`changee` les note dans `sales`, `elaguer` les sorties dans
  `retirees`), une ligne JSON chacune, à la fin de `suivi.journal` (`Releve.fichierJournal`,
  `Fichiers.ajouterParMorceaux`) : `{catalogue, id, entree}` ou `{catalogue, id, retiree: true}`.
  Le format de `suivi.json` ne change pas. Relecture : `suivi.json`, puis le journal rejoué ligne
  par ligne (la dernière gagne ; une ligne illisible ou coupée ignorée, jamais tout le relevé ; un
  journal sans `suivi.json` se rejoue sur un relevé vide) ; `--graphiques` le rejoue de même
  (`SuiviGraphiques.lireReleve`, suivi.json lu d'abord). Compaction (`suivi.json` en entier, comme
  avant, le journal effacé juste avant que le nouveau remplace l'ancien : `avantDeRemplacer` de
  `Fichiers.ecrireParMorceaux`, un journal qui ne s'efface pas abandonne la compaction) seulement à
  la première écriture après une relecture qui a trouvé un journal (le chargement), au-delà de
  `SEUIL_JOURNAL` (5 Mo), à la fin de la file au-delà de `SEUIL_JOURNAL_FIN` (1 Mo), pour mettre de
  côté un relevé illisible, ou par `Releve.compacter`. Un ajout manqué (erreur) rend ses entrées à
  la suivante, qui commence par un saut de ligne (`journalCoupe`). `--mesures --echantillons` lit
  `suivi.json` seul : à lancer Lightroom relancé (le chargement compacte). Qui entre : la sélection que voient `Fenetre.suivreSelection` et
  `FenetreRapide.suivreSelection` (`Releve.voirSelection` : une même clé ne compte qu'une fois,
  `Releve.revoir` à l'ouverture ou au rappel d'une fenêtre la fait compter même inchangée, une autre
  photo active dans le même groupe ne revoit qu'elle, comme une sélection de plus de `SEUIL_REVOIR`
  (2 000) photos revue moins de `REVOIR_APRES` (600 s) après sa vue entière ; `MAX_SELECTION` 250 000
  depuis le correctif 1.3.8, 1 000 avant, le reste dit au journal), par son original (`masterPhoto`
  d'une copie virtuelle, une seule fois), sauf les vidéos
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
  un genre refait qui échoue garde l'analyse d'avant (`Releve.sansRefaire`) ; une erreur (une
  raison de
  `--analyser`, `pas_de_reponse`, `photo_introuvable`, `module`) compte un essai, réessayé
  `DELAI_REESSAI` (600 s) plus tard (devant la file gardée, `Releve.reessais`), l'entrée abandonnée
  au `ESSAIS_ANALYSE`-ième (3). Les écritures du fichier, vues et analyses comprises, sont espacées de
  `Releve.delaiEcriture` : au moins `DELAI_ECRITURE` (20 s : une écriture par photo parcourue aux
  flèches figeait Lightroom), `FACTEUR_ECRITURE` (10) fois la durée propre de la dernière (la somme
  de ses morceaux, sans le temps des autres tâches quand elle rend la main) et `SECONDES_PAR_MO` (1)
  par Mo écrit la dernière fois (le fichier entier relu ou compacté, ou les lignes ajoutées au
  journal depuis le 2 novembre 2026 ; avant, chaque écriture l'écrivait en entier : 85 000
  originaux, 57 Mo, environ toutes les 57 s), au plus `DELAI_ECRITURE_MAX` (60 s : ce qui n'est pas écrit se perd si
  Lightroom quitte, `Arret.lua` ne s'exécutant pas ; les analyses se refont, une vue d'une photo
  nouvelle non), pendant une pause comme hors d'elle (plus d'écriture forcée au début de chaque
  pause depuis le correctif 1.3.8 : une liaison qui sert par moments réécrivait tout le relevé toutes
  les 7 s), sauf avant un dessin demandé de la fenêtre Suivi (`Releve.ecrire`, qui attend d'abord une
  écriture en cours) ; en fin de file, la tâche attend son tour en rangeant les vues qui arrivent.
  Toute la bibliothèque (correctif 1.3.8) : aucun morceau de calcul
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
  `Releve.delaiEcriture` au plus, 60 s) ; les essais d'Init des deux suites l'éteignent ensuite
  (`tests.lua`,
  `essais-une-photo.lua`). Côté connecteur, `Suivi.codes` (les huit comptés, dans l'ordre de
  `PriseDeVue` : `codesAnalyse`, les six de `--analyser`, et `codesCarnet`, `horizon_penche` et
  `mise_au_point`, que seul Claude mesure) ; aucune liste de défauts dans le module ; l'analyse
  reprend les seuils du tri et du carnet sans en ajouter. `Genre.swift` (correctif 1.3.8) est la
  seule liste des genres et de leurs règles (onze codes, de `sport` à `autre` ; `Genre.classer`,
  pure :
  la première règle qui convient, sport, fêtes et événements, famille et groupes, portrait, macro,
  animaux, nourriture, véhicules, ville et architecture, paysage, autre ; les visages à l'envers
  écartés, `Genre.visages` par `Composition.visagePlausible` ; la fleur jugée sans « plant » ni
  « foliage », que Vision donne avec toute fleur, `Genre.sceneAutourDUneFleur` ; chaque étiquette
  connue de Vision, `GenreTests` ; seuils provisoires relevés le
  26 octobre 2026 sur les vignettes de 60 photos de Dany, 52 sur 53 rangées comme à l'œil ; ni
  nourriture, ni macro, ni fête, ni nuit dans ce relevé) ; aucune liste de genres dans le module.
  Rien du Suivi ne part chez Claude : aucun
  outil ne lit `suivi.json`. Reste à constater dans Lightroom : `batchGetRawMetadata` avec
  `masterPhoto` et `virtualCopies` (sinon une à une), `focalLength` en nombre (un texte « 23 mm » se
  lit aussi), une vignette de 1 024 rendue pour l'analyse.

- **La recherche par le sens** (1.6, `docs/SPEC.md`, 1.6 : recherche par le sens) : le Suivi remplit
  l'index du sens sans seconde passe. `Releve.sondeSens` : `--sens-etat` une fois par séance (alarme
  `ALARME_SENS`, 20 s) ; sans `regles_sens` (connecteur d'avant la 1.6, modèle absent), rien du sens
  ne part à `--analyser` (son entrée reste celle du contrat). Avec `Releve.reglesSens` : `catalogue`
  dans l'entrée, `uuid`, `date` et `sens_seul` (`seulementSens`) par photo ; une analyse sans
  `regles_sens` à jour entre dans la file (`quand`) et se refait pour l'empreinte seule, ses défauts,
  son genre et son heure gardés (`analyseAvec`) ; une réponse sans `regles_sens` alors qu'il l'avait
  dite (modèle disparu, ou qui ne s'ouvre pas : `sens_erreur`) : plus demandée de la séance.
  `a_compiler` de `--sens-etat` : `--compiler-sens` une fois (`ALARME_COMPILATION`), puis la question
  reposée. L'empreinte va dans `Developpeur/Index` (le connecteur), jamais dans `suivi.json` ; seuls
  `analyse.regles_sens` et `analyse.index_sens` (la génération de l'index) y sont rangés : une
  analyse d'une autre génération que `Releve.indexSens` (index effacé ou refait), ou sans génération,
  refait son empreinte seule (`sensAFaire`).
