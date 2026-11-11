# CLAUDE.md — module Lightroom (Lua)

Règles du module « Développeur » (`Developpeur.lrplugin`) et de la fenêtre Claude, sorties du
CLAUDE.md principal, qui garde les règles communes à tout le projet. Le détail par thème est dans
`docs/regles/module-*.md` ; chaque puce ci-dessous dit quand le lire.

## Lua 5.1 et tâches

- Le module est du **Lua 5.1** (celui de Lightroom) : pas de `goto`, pas de `//`. Le JSON passe
  toujours par `Json.lua`, qui lit et écrit les nombres sans dépendre de la locale (en français,
  `string.format` écrirait « 0,35 »). Dans une tâche asynchrone, `LrTasks.pcall` et non `pcall`
  dès que le code peut attendre (rendu, accès au catalogue) ou rendre la main (`LrTasks.yield`, par
  `Photos.rendreLaMain`, la seule copie, que `Releve.rendreLaMain` et `Historique` reprennent :
  seulement si `LrTasks.canYield`, jamais dans un comparateur de `table.sort` ni un rappel de
  `gsub`, jamais en parcourant par `pairs` une table qu'une autre tâche agrandit : en prendre les
  clés d'abord ; jamais sous un `pcall` simple, que Lua 5.1 refuse). Un grand JSON s'écrit morceau
  par morceau par `Json.ecrivain` (accolades, virgules et clés restent dans `Json.lua` ; ainsi
  s'écrit le relevé du Suivi). `os.time` et `os.date` passent par `Compat.lua` (remplacés par
  `LrDate` s'ils manquaient).
- Barre d'une commande longue (`Progression.lua`) : un point sûr (`Progression.pointSur(suivi)`,
  le suivi de `Progression.suiviDe(params)`, nil hors d'une commande : la fenêtre n'est jamais
  arrêtée) jamais dans une écriture au catalogue ni entre une proposition et sa remise ; la croix
  ne marque que la commande de sa barre, une fois ; jamais deux barres (rien pendant celle d'une
  série, rien pour `SANS_BARRE`) ; la simulation tourne la surveillance à chaque `LrTasks.sleep` et
  pendant un rendu (`S.dureeRendu`). `docs/SPEC.md`, Barre et arrêt d'une commande longue.
- Pas de calcul long en Lua sur la tâche de l'interface : base64, réductions d'images (`sips`) et
  commandes du système passent par `LrTasks.execute` (qui ne bloque que la tâche).
- Ne jamais nommer un fichier du module `Versions.lua` : Lightroom refuse de le charger (constaté ;
  d'où `Composants.lua`). Un seul `Info.lua`, `Init.lua`, `Arret.lua` et `PluginInfoProvider.lua`
  pour la liaison et la fenêtre, sans fichier de fusion (`InfoFenetre.lua`…) :
  `scripts/tester-module.sh` refuse l'un et l'autre. À la fermeture de Lightroom, `Arret.lua` ne
  s'exécute pas (constaté) : le ménage se fait au chargement (`Menage.lua`, depuis `Init.lua`).

## Dossier commun (deux Mac, un SSD)

- Deux racines (`Chemins.lua`) : locale (`Chemins.locale`, `Chemins.racine` : connecteur, jeton,
  `Sessions/`, `Atelier/`, `Temporaire/`, `connecteur.json`, le pointeur `dossier-commun.json`,
  tout ce qui touche Fibo) et celle des données (`Chemins.donnees` : les noms de
  `Chemins.NOMS_DONNEES`, copies illisibles comprises). Tout fichier de données passe par
  `Chemins.donnees`, `Chemins.donnee`, `Chemins.conversations`, `Chemins.etapes` ou
  `Chemins.claudeCode`, jamais par `Chemins.racine`. Le pointeur se relit à chaque accès ; seul
  `DossierCommun.lua` l'écrit (Gestionnaire de modules externes).
- Réglé mais introuvable (SSD débranché) : refus (`Chemins.messageAbsent`), **jamais de repli sur
  la racine locale** ; les fenêtres le disent à l'ouverture (`Chemins.verifierDonnees`), le Suivi se
  met en pause (`Releve.relancer`). Un registre en mémoire se relit quand son fichier change de
  racine (jamais écrit dans l'autre). Un chemin absolu relu d'un fichier de données passe par
  `Chemins.rebaser`, la seule fonction de rebasage.
- Le dossier commun s'appelle « Développeur IA » (`DossierCommun.NOM`) : la racine d'un volume
  choisie donne son dossier « Développeur IA », le choix s'ouvre sur `/Volumes/Photos`
  (`DossierCommun.VOLUMES`, `VOLUME_PHOTOS` : injectés dans les essais, jamais le vrai SSD).
- Le réglage (un seul à la fois : `DossierCommun.enCours`) ferme la liaison (`Chemins.changement` :
  toute commande sauf ping refusée), attend le Suivi et la commande en cours ; refuse un dossier
  vide quand l'ancien dossier commun est introuvable ; copie (copie récursive,
  `DossierCommun.copierArbre`, qui rend la main à Lightroom ; venant de ce Mac, aussi les
  `<sessionID>.jsonl` des conversations, par `relais.sh --projet`), recopie un fichier changé
  pendant la copie, range sous la marque `.rangement-en-cours.json` (un rangement interrompu se
  termine au choix suivant), écrit le pointeur, **puis** met de côté les données de ce Mac
  (« Avant le dossier commun <date> ») ; n'efface jamais rien. « Revenir au dossier de ce Mac » ne
  retire que le pointeur. `DossierCommun.lua` se prend par `pcall(require, …)` dans
  `PluginInfoProvider.lua` (fichier nouveau : rechargement sans relance). La progression passe par
  `LrDialogs.showModalProgressDialog` (au premier plan du Gestionnaire), sinon `LrProgressScope`.
- `relais.sh` copie `Claude Code/<id>.jsonl` du dossier commun avant `--resume` seulement si
  l'échange local manque ou en est le début, et vers lui après la fin (normale, en erreur, ou par
  `trap` sur TERM, HUP, INT ; un échange du SSD qui n'est pas le début du local est gardé à côté,
  `.avant-<date>`) (`DEVELOPPEUR_DONNEES`), jamais rien d'autre de `~/.claude` ; une copie
  manquée va dans `dossier-commun.erreur`, que `Session.lire` porte au Journal et à la conversation.
  `uninstall.sh` ne touche jamais le dossier commun. Essais : `essais-dossier-commun.lua` des deux
  suites (jamais le vrai `~/.claude` : `CLAUDE_CONFIG_DIR` simulé).
- Mises à jour par le SSD (1.7, `MisesAJour.lua`) : le module ne copie ni n'installe rien
  lui-même, il lance `--mises-a-jour` (comparaison sous l'alarme de perl ; dépôt et installation à
  part, `&`, la croix de la barre fait `kill`). Au lancement : en dernier dans la tâche d'`Init.lua`,
  rien sans dossier commun réglé et présent ; l'installation seulement après « Mettre à jour » ;
  jamais Fibo 2 Studio quitté à la place de Dany. Essais : `essais-mises-a-jour.lua` (faux
  connecteur). `docs/SPEC.md`, Mises à jour par le SSD (1.7).

## Écritures et mémoire

- Toute écriture dans le catalogue passe par `withWriteAccessDo` (`ecrire` dans `Ecriture.lua`) ;
  la simulation des tests le vérifie. Mais `updateAISettings`, `setEnhance`, la suppression des
  reflets et des passants, `deleteAllEmptyMasks`, la rotation d'un quart de tour et les instantanés
  (`applyDevelopSnapshot`, `deleteDevelopSnapshot`) se font **hors** de `withWriteAccessDo`.
- La mémoire de Claude (champs de `Metadonnees.lua`) se lit par `lireChamp` ou `lireJson` et
  s'écrit par `garder` : Lightroom copie ces champs dans une copie virtuelle, et seuls ceux-là
  vérifient qu'elle appartient à la photo (`proprietaireMemoire`). Dans une écriture, Lightroom
  relit un champ du module avec sa valeur d'avant l'écriture (constaté par ses effets) : `garder`
  ne rattache donc une photo qu'une fois par écriture (`Photos.nouvelleEcriture`, appelé par
  `Ecriture` au début de chacune), et la simulation ne montre un champ écrit qu'après l'écriture.
  Voir `docs/SPEC.md`, Mémoire des retouches. Les listes de photos se décrivent par
  `Photos.decrireTout` (lectures groupées) ; « retouchée par Claude » n'y compte que si
  `proprietaireMemoire` est l'uuid de la photo.
- Les clés `Suppression`, `Amelioration`, `Bibliotheque` et `Rotation` de la mémoire ne sont pas
  des réglages : jamais dans `applyDevelopSettings` (la simulation le refuse) ; `etape_id` non
  plus.
- L'état laissé par Claude (`apresClaude`) s'écrit par `noterEtatFinal`, et toute écriture de la
  mémoire seule par `Ecriture.ecrireMemoire`, en écriture privée (`withPrivateWriteAccessDo`) :
  jamais une écriture ordinaire, qui ajouterait une opération à Édition › Annuler.
- **L'avant/après d'une étape se garde au rendu, jamais par une écriture** (Lightroom ne rend que
  l'état actuel) : toute étape nouvelle passe par `Ecriture.nouvelleEtape` ; `avant_apres` est
  pour la recette seulement, jamais un outil ; une seule photo, la photo active ; jamais avec
  `sans_avant_apres`, ni en pause, ni pour un refus prévisible, ni un rendu avec des calculs IA en
  attente ; les crochets d'`Etapes` ne laissent passer aucune erreur. `Rendu.apercu` ne garde la
  vue (l'avant) que pour l'image entière de l'état actuel : jamais un zoom, un `chemin_avant`, un
  `essayer` ni une image entière de la composition. Avant de toucher à `Etapes.lua` ou à la
  capture : lire `docs/regles/module-avant-apres.md`.

## Réglages, profils et calculs IA

Avant de toucher à l'écriture des réglages, aux profils, aux masques, au débruitage, aux reflets,
aux passants, aux variantes ou aux instantanés : lire `docs/regles/module-reglages-et-traitements.md`.
Les pièges :

- Ce qui revient du JSON passe par `pourLightroom` avant `applyDevelopSettings` : une table qui
  porte une métatable (tableau relu par `Json.decode`) bloque Lightroom sans erreur, verrou
  d'écriture compris. De même, toute table donnée à Lightroom par la fenêtre est neuve, jamais
  relue par `Json.decode`. Les deux simulations refusent les métatables.
- Un profil se pose toujours par `libererProfil` (vide `MissingCameraProfile`, sinon tout profil
  suivant retombe à Adobe Standard) et se relit après coup (`attendreProfils`).
- Ce que `applyDevelopSettings` ne calcule pas (auto, masques IA, flou d'objectif, profils
  adaptatifs, `LensProfileSetup = "LensDefaults"`, qui ne tient qu'avec `LensProfileEnable`, à
  l'application comme à l'annulation) passe par un paramètre prédéfini du module ; `install.sh`
  n'en fait le ménage que Lightroom fermé. Un tel paramètre fait tomber une balance des blancs
  personnalisée (tout plan passe par `appliquerPlan`), **remplace** tous les masques s'il porte
  `MaskGroupBasedCorrections` (il doit porter la liste entière : `masquesParPreset`), et son nom
  suit son contenu (`presetContenu`). Une liste de taches vide ne les retire pas : vider aussi
  `RetouchInfo`.
- Le calcul IA (`photo:updateAISettings()`, `Ecriture.calculerIA`) se fait après l'écriture et
  avant tout rendu ou exportation (`calculerAvantRendu`, `attendreCalculsIA`) : sinon la fenêtre
  « Mises à jour IA recommandées » bloque l'exportation ; rien n'y répond à la place de
  l'utilisateur.
- Débruitage, détails bruts, super résolution, instantanés : photo affichée dans le module
  Développement, un seul traitement à la fois (`avecVerrou`). `changeReflectionRemovalAmount` ne
  change rien au filtre rangé : retirer puis reposer le filtre.
- Une personne précise porte `InstanceIDs` **et** `InstanceBounds` (sauf la personne seule :
  `Locaux.personne`), sinon Lightroom ne la reconnaît pas.
- Un module ne peut pas : lancer ni refaire la poussière (il ne fait que la retirer ; le serveur
  applique pour cela le paramètre prédéfini « Claude / Poussière », `Sources/CLAUDE.md`), convertir une
  version de processus 1 ou 2, mesurer la profondeur d'un cadre du flou d'objectif, calculer
  l'Upright avec repères : ne pas les réessayer sans nouvelle piste.
- Une photo déjà agrandie par l'ancien connecteur (`Reglages.estAgrandie`) reste protégée : Claude
  ne la recadre pas, son recadrage ne se copie ni vers elle ni depuis elle, « Contraindre le
  recadrage » n'y est pas coché.

## Bibliothèque, livraisons, originaux

- Bibliothèque (avant d'y toucher : `docs/regles/module-bibliotheque.md`) : titre, légende, droits
  et libellé se lisent par `getFormattedMetadata` (`getRawMetadata` les refuse) ; le libellé se
  vérifie par `colorNameForLabel` après l'écriture seulement ; un texte
  s'efface par un texte vide, jamais par nil ; une collection ne se lit pas dans l'écriture qui
  l'a créée ; un mot-clé n'y est jamais lu (`getName` échoue) ; un paramètre prédéfini de
  métadonnées ne se voit qu'après l'écriture qui l'applique, et ne va pas dans le même appel que
  des champs IPTC donnés un à un ; le filtre (`montrer`) se remet par
  ses valeurs exactes, jamais par un paramètre prédéfini ; renommer ou déplacer touche la
  structure : jamais de suppression, pas d'étape pour `undo_last`. Une position GPS s'efface par
  `setRawMetadata('gps', nil)` ; le jour d'une prise de vue se lit par `timeToUserFormat`
  (`timeToW3CDate` donne l'UTC). Une photo hors du film fixe se sélectionne par
  `selectionnerAvecSource`, la sélection d'avant revient par `Bibliotheque.remettreSelection`.
- Livraisons (avant d'y toucher : `docs/regles/module-livraisons.md`) : `LrExportSession` avec
  `LR_collisionHandling = 'rename'`, jamais `overwrite` hors du dossier temporaire d'un aperçu ; le
  module ne crée, ne change ni ne publie aucun service ; une livraison ne change pas les photos,
  ses lots suivants (`suite`) ne redemandent pas l'accord ; sortie HDR seulement pour une photo en
  mode HDR (32 bits seulement en HDR) ; une photo sans original ne part que depuis son aperçu
  dynamique (2560 px au plus), qui ne se retire jamais d'une photo dont l'original manque. Une
  livraison réimportée et empilée va dans le dossier de l'original (Lightroom n'empile que là) ;
  `undo_last` ne la retire pas ; seule la recette retire une photo réimportée, jamais vers un
  dossier neuf en essai. Un aperçu fait passer `isExported` à vrai : « exportée » se lit par
  `Photos.exportee`, jamais par `isExported` seul. `choisirDossier` s'ouvre dans sa propre tâche.
  Ni le serveur ni le module ne demandent la permission d'Accessibilité.
- Originaux (avant de toucher à `Photos.exigerOriginal`, `--marquer-af`, `--focus` ou
  `LecteurBoitier` : `docs/regles/module-originaux.md`) : un rendu sans original ni aperçu dynamique
  est refusé (`rendre`). Le connecteur n'ouvre un original que pour la lecture du boîtier d'une
  photo Fujifilm (point de mise au point, intention), une ouverture par photo et par processus
  (aucune pour un avant/après), en temps borné (macOS peut faire attendre `open()` sans fin) ;
  Claude ne répond jamais à une demande d'autorisation de macOS ; le Suivi n'ouvre jamais
  d'original.
- Le module signale la photo active changée avec sa réponse suivante (`evenements`, avec son `id`,
  seulement si elle n'est plus celle signalée la dernière fois) ; le serveur le transmet aux
  clients abonnés (`resources/subscribe`), sinon le dit une fois au résultat d'outil suivant
  (Claude Desktop ne s'abonne pas, constaté). Rien ne part sans une commande.

## Notation, carnet, Suivi

- Notation (avant de toucher à `Notation.lua`, `notation.json`, la carte Note ou `propose_ratings` :
  `docs/regles/module-notation.md`) : toute proposition commence « à vérifier » ; une note ne se
  pose que par `Notation.poser` puis `Bibliotheque.noter` ; `remettre` est pour la recette
  seulement, jamais un outil ; la carte Note n'écrit jamais pendant que Claude travaille ni pendant
  une note en cours ; tout ce qui sort du registre vers une vue est une table neuve ; le registre ne
  touche au catalogue que par `proposer` avec `poser`, et l'élément `notation` du fil ne sert qu'à
  l'affichage. Une note posée n'entre pas dans l'état d'avant Claude (`revert_to_original` la laisse
  ; `undo_last` la défait). Le registre ne voit pas une annulation (`undo_last`, ⌘Z) :
  `Notation.recaler`, à la relecture de la photo active ; mais une note posée puis annulée sur une
  photo qui avait déjà cette note reste « acceptee ». Dans la fenêtre Claude, toute photo que Claude
  traite, il la note d'abord (puce Notes de `Consignes.texte`) ; ni Noter ni Évaluer dans les
  invites ni la carte Note ; les consignes du connecteur (`ServerInfo`) ne demandent pas cette note
  d'abord.
- Carnet de progrès (avant de toucher à `Carnet.lua`, `carnet.json` ou `Carnet.swift` :
  `docs/regles/module-carnet.md`) : `carnet.json` n'est tenu que par `Carnet.lua`, les phrases
  du résumé n'existent que dans `Carnet.resumer` ; `carnet` n'écrit rien dans le catalogue, ne
  s'arrête pas à la pause et ne se rejoue jamais ; une photo de « Développeur › Essais »
  n'y entre pas, sauf `essai_recette`, jamais sous l'entrée de son original ; les leçons d'avant
  le correctif 1.3.6 ne sont jamais montrées, envoyées ni perdues ; seuils et détection seulement
  dans `Carnet.swift`, règles de netteté seulement dans `PhotoTriee.defautsNettete` ;
  `noterAuCarnet` n'est vrai que dans `serve()`, et seul lui fait demander les clés de la
  géométrie ; `constats_prise_de_vue` seulement si le module répond `note = true` ; l'ISO ne sert
  ni au plafond de note ni au tri ; `--graphiques` lit `carnet.json` en lecture seule.
- Le Suivi (avant de toucher à `Releve.lua`, `suivi.json`, `FenetreSuivi.lua`, `Suivi.swift`,
  `Genre.swift`, `--analyser` ou `--graphiques` : `docs/regles/module-suivi.md`) : contrat figé dans
  `Tests/Contrats/suivi.json` (un changement voulu se fait des deux côtés). `suivi.json` n'est tenu
  que par `Releve.lua` (`Suivi.lua` est la fenêtre de la liaison), avec son journal
  `suivi.journal` (entrées changées, rejouées par `Releve.lua` et `--graphiques` ; suivi.json
  réécrit en entier seulement à la compaction) ; rien n'est écrit au catalogue ;
  ni vidéos ni photos d'Essais ; pas de rattrapage à l'installation ; un relevé illisible est mis de
  côté, jamais écrasé ; une analyse n'est jamais refaite après une édition, seulement pour des
  `regles` plus récentes ; aucun calcul de plus de quelques centièmes de seconde sans rendre la main
  ; une seule relecture et une seule écriture à la fois ; jamais un tri de textes (`strcoll`) ni un
  comparateur Lua sur toute la liste (`trierParVu`) ; `poserClassement` ne change une entrée que si
  note, drapeau ou « retouchée par Claude » changent ; une sélection posée par la fenêtre Suivi ne
  se range pas ; le Suivi ne tourne que dans Lightroom (`Releve.allumer`) et une ancienne instance
  ne réécrit jamais le relevé ; tout ce qui change une entrée appelle `changee` ; aucune liste de
  défauts ni de genres dans le module (`Genre.swift` est la seule) ; rien du Suivi ne part chez
  Claude.

## Fenêtre Claude et relais

- Claude Code (avant de toucher à `relais.sh`, `Moteur.lua`, `Session.lua`, au modèle ou à
  l'effort : `docs/regles/module-relais-claude-code.md`) : Lightroom ne sait pas tenir un
  processus par ses tuyaux, d'où `relais.sh`. Claude Code ne reçoit que le connecteur
  (`--strict-mcp-config`), aucun outil intégré (`--tools ""`), rien qui demande une permission,
  ni compétences ni réglages de l'utilisateur, dans le dossier vide `Atelier/`. Un seul processus
  Claude Code à la fois. Modèle et effort se choisissent dans le Gestionnaire de modules externes,
  plus dans la fenêtre.
- Invites réglables (après la 1.8 ; `docs/SPEC.md`, Invites réglables) : ce qui part d'un bouton
  se fait au clic par `Consignes.message`, `classerRapideMessage`, `demandeObtenir` ou
  `proposerAppliquerRapide`, qui relisent `invites.json` ; jamais `invite.message` ni les
  constantes (`noterRapide`, `classerRapide`, `PROPOSITION_COMPLETE`…), qui sont le message tout à
  Oui. Une étape à Non est toujours dite à Claude (`Consignes.NE_PAS_FAIRE`), jamais seulement
  omise ; tout à Oui, le message reste mot pour mot celui d'avant (`essais-invites.lua`). Un
  `invites.json` illisible ou d'un autre format est mis de côté (`invites-illisible-<date>.json`)
  avant toute écriture, jamais écrasé.
- Le presse-papiers ne se lit que sur un clic de l'utilisateur (bouton 📋, `presse-papiers.js`) ;
  les essais passent par un presse-papiers nommé, jamais le vrai.
- Fenêtre (avant de toucher à `Fenetre.lua`, `Vues.lua`, `Dispositions.lua`, aux images, aux
  polices, au champ de demande ou aux raccourcis : `docs/regles/module-fenetre-claude.md`) :
  - elle ne change pas de structure une fois ouverte et une vue masquée garde sa place : tout ce
    qui varie passe par `bind` et des variantes superposées (`place = 'overlapping'`) ; `visible`
    lié est ignoré sur `row`, `column`, `group_box`, `tab_view` et `scrolled_view` (la simulation
    les refuse) ; une condition passe par `F.egal`, `F.non`, `F.si`, `F.condition` ou `F.et` ;
    un onglet par `Vues.masquable` ; pas de `group_box` dans un onglet, jamais `visible` sur la
    colonne d'une variante ; seule la variante montrée répond ; une propriété liée a une valeur
    avant l'ouverture ;
  - quand le contenu change de taille, augmenter `Fenetre.FORME` (`save_frame`) ;
  - `background_color` est sans effet sur `row`, `column`, `view`, `group_box` et la fenêtre :
    aplats par `Vues.aplat` ; un `mouse_down` sur un `f:picture` ne reçoit rien : clic par
    `Fenetre.calque` (un calque n'a pas d'`enabled`) ; image par `Fenetre.image`, jamais
    `images/<nom>.png` en dur, toujours avec `width` et `height` ; tout bouton par `Fenetre.bouton`
    ; `<EM>` toujours avec `emphasis_font`, `text_color` et `emphasis_color` ensemble, ni entité ni
    balise seule ;
  - aucun bouton par défaut (Retour le déclencherait) : le champ de demande est
    `immediate = false`, Retour passe par l'observateur et l'envoi automatique, que tout bouton et
    tout calque annulent (un `f:push_button` créé à part enverrait la demande tapée) ;
  - `Dispositions.PALETTES` est la seule table des couleurs (apparence claire ou sombre) ;
  - un raccourci d'app vise le titre exact de l'entrée de menu (trois espaces devant,
    `Raccourcis.RETRAIT`) ; Lightroom ne lit les raccourcis qu'à son lancement.
