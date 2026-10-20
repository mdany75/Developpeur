# CLAUDE.md — Développeur

Claude retouche les photos de Lightroom Classic. Deux pièces qui se parlent par TCP local
(127.0.0.1, ports 54770 et 54771) : le connecteur MCP-Développeur, un serveur MCP natif (Swift,
SwiftPM, sans Xcode ni Node, exécutable `mcp-developpeur`) que Claude Desktop et Claude Code
lancent sur stdio ; et le module Lightroom Classic « Développeur » en Lua
(`Lightroom/Developpeur.lrplugin`, Lightroom Classic 13.3 au moins), qui exécute ses commandes
dans le catalogue (la liaison) et porte la fenêtre Claude : une conversation avec Claude Code
(forfait claude.ai, jamais l'API) qui retouche et note par ce même connecteur, en trois
dispositions (Atelier, Conversation claire, Panneau), avec les fenêtres Publication,
Consommation et Séance de notation.

Trente-quatre outils : `get_status`, `list_selection`, `view_photo`, `measure_angle`,
`analyze_photos`, `get_settings`, `apply_settings`, `preview_settings`, `enhance_photo`,
`add_mask`, `edit_mask`, `retouch_spots`, `copy_settings`, `list_profiles`, `list_presets`,
`save_preset`, `undo_last`, `revert_to_original`, `export_journal`, `find_photos`,
`set_metadata`, `list_keywords`, `manage_collections`, `create_virtual_copy`, `show_photo`,
`cull_photos`, `contact_sheet`, `propose_ratings`, `remove_distractions`, `remember_style`,
`export_photos`, `compare_variants`, `choose_variant`, `match_series` ; neuf invites :
`retouche_pro`, `harmoniser_serie`, `tri_seance`, `noter`, `portrait`, `paysage`,
`noir_et_blanc`, `nuit_iso_eleve`, `partage` ; des ressources `developpeur://` (guide de style,
standard de notation `developpeur://notation`, aperçu et journal d'une photo). Le README décrit
les fonctions du point de vue de l'utilisateur ; le protocole entre le serveur et le module, et la
fenêtre Claude (section Fenêtre Claude), sont dans `docs/SPEC.md`.

Développeur 1.0 remplace MCP Lightroom 2.7 (et son surveillant de Camera Raw) et Claude pour
Lightroom 1.6.1, sans en reprendre de données. Leurs dépôts (`~/Developer/MCP-Lightroom`,
`~/Developer/Claude-pour-Lightroom`) se consultent en lecture seule : ne jamais y écrire.

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Commandes

| Action | Commande |
| --- | --- |
| Construire | `./build.sh` (tests, compilation release, signature Developer ID, `build/Developpeur.zip` notarisé) ; `SKIP_NOTARIZE=1` pour un essai, `--sans-tests` pour un essai rapide (jamais pour une version publiée) |
| Construire et installer | `./build.sh --install` (serveur dans `~/Library/Application Support/Developpeur/`, module dans `~/Library/Application Support/Adobe/Lightroom/Modules/`, inscription « MCP-Developpeur » dans Claude Desktop et Claude Code) |
| Tester le serveur | `swift test` |
| Tester le module | `scripts/tester-module.sh` (LuaJIT : `brew install luajit`) : forme du module, syntaxe, globales, liens entre les fichiers, puis les suites `Tests/Lua/Liaison` et `Tests/Lua/Fenetre`, et chaque `Tests/Lua/Fenetre/essais-*.lua` |
| Essayer à la main | `swift build && ./.build/debug/mcp-developpeur --status`, puis `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée) ; `--module diagnostic` liste les fonctions du SDK offertes, et avec `'{"valeurs": true}'` lit le jeu de libellés, le filtre de la Bibliothèque et l'original de la photo active ; `--version` |
| Recette dans Lightroom | `./.build/debug/mcp-developpeur --recette <id RAW> [--jpeg <id>] [--flash <id>] [--profondeur <id>] [--yeux-rouges <id>] [--x-t20 <id>] [--original] [--images <dossier>]` (copies virtuelles de la collection « Développeur › Essais » que Claude n'a pas encore retouchées ; `--flash` : une photo au flash, pour les expositions d'après la prise de vue ; `--profondeur` : la copie d'une photo Portrait d'iPhone ; `--yeux-rouges` : une vraie photo au flash ; `--x-t20` : un RAF de X-T20 ; `--original` accepte un original désigné par Dany ; `--images` : le dossier des zooms à regarder ; chacune est remise à l'origine ; l'étape « note proposée (propose_ratings), photo inchangée » vérifie le refus de 5 ★, range une proposition à vérifier par la vraie commande `notation`, qui reste dans `notation.json`, et lit la séance ouverte par `read_session`) |
| Réglages à plat | `./.build/debug/mcp-developpeur --dump [<id>]` (une clé par ligne, pour `diff` avant et après une opération faite à la main) |
| Recalage mesuré | `./.build/debug/mcp-developpeur --recalage <id>` (écarts du modèle de recalage sur la géométrie actuelle ; deux rendus « Claude · recalage » dans l'Historique) |
| Journal détaillé | `DEVELOPPEUR_VERBOSE=1` (durée des réponses et de chaque commande du module, sur stderr) ; `DEVELOPPEUR_LIMITE=<s>` pour essayer la réponse d'attente ; `DEVELOPPEUR_PORT=<port>` pour un autre port |
| Journaux du module | `~/Library/Logs/Developpeur/module.log` (liaison) et `conversation.log` (fenêtre Claude), gardés sous 1 Mo ; échanges avec Claude Code : `~/Library/Application Support/Developpeur/Sessions/` |
| Recharger le module dans Lightroom | Fermer les fenêtres du module (devant, elles réduisent le menu Fichier), Lightroom au premier plan, puis Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du module externe › Charger de nouveau le module ext. Un fichier `.lua` ajouté depuis le lancement ne se charge pas ainsi (« Could not load toolkit script »), ni donc un fichier qui le requiert (`Commandes.lua` requiert `Notation.lua`, nouveau en 1.1), ni un raccourci clavier changé : quitter et relancer Lightroom, après toute version qui ajoute un fichier `.lua` |
| Remesurer les polices | `swift scripts/metriques.swift > Lightroom/Developpeur.lrplugin/Metriques.lua` (si les polices du fil changent dans `Fenetre.lua`, ou pour un caractère nouveau du fil, comme ★ ☆ ⚑) ; images « aucun aperçu », une par cadre d'aperçu de `Dispositions.TAILLES` : `swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` |
| Désinstaller | `bash uninstall.sh [--tout]` (inscriptions, serveur, module, paramètres prédéfinis invisibles Lightroom fermé, fichiers de travail ; `--tout` : aussi guide de style, conversations, profils de publication, consommation, notes proposées et séances de notation (`notation.json`) et journaux ; jamais le catalogue ni les photos) |
| Publier une version | voir ci-dessous |

Les fichiers produits vont dans `build/`, ignoré par git. Rien de compilé n'est commité.

## Publier une version

Dans cet ordre :

1. Mettre le numéro à jour aux trois endroits : `CFBundleShortVersionString` dans
   `Resources/Info.plist`, `VERSION` dans `Lightroom/Developpeur.lrplugin/Info.lua` et
   `Liaison.VERSION` dans `Liaison.lua` ; ajouter la section `## X.Y — AAAA-MM-JJ` dans
   `CHANGELOG.md`, écrite pour l'utilisateur. `build.sh` refuse si les trois numéros diffèrent
   ou si cette section n'est pas la plus récente des sections numérotées (« ## Non publié » peut
   rester au-dessus).
2. `git add -A && git commit -m "Version X.Y" && git push origin main`
3. `./build.sh --install` (produit `build/Developpeur.zip`, signé Developer ID et notarisé :
   attend la réponse d'Apple, quelques minutes ; met l'installation à jour). Puis relancer
   Lightroom et Claude Desktop (s'il était ouvert pendant l'installation : le quitter, lancer
   `mcp-developpeur --install`, puis le rouvrir), ouvrir une nouvelle session Claude Code, et
   faire l'essai réel sur la collection « Développeur › Essais » : la recette (`--recette`), puis
   une demande dans la fenêtre Claude (⌃⌥C) sur l'une de ces photos, défaite ensuite. L'essai doit
   réussir avant le tag.
4. `git tag -a vX.Y -m "Version X.Y" && git push origin vX.Y`
5. `gh release create vX.Y "build/Developpeur.zip" --title "Développeur X.Y" --notes "$(~/.claude/skills/standard-projet/scripts/notes-version.sh X.Y)"`
6. Mettre à jour la feuille de route « Développeur — Feuille de route » (document claude.ai
   privé, https://claude.ai/code/artifact/9b2efe2d-d295-4655-9653-3a324d84472e, par le
   connecteur Claude Docs) : retirer ce que la version vient de livrer et corriger ce qui est
   devenu faux.

Une version par étape de la feuille de route (1.1 le nouvel écran et la notation, 1.2 rendu plus
juste, 1.3 apprendre en regardant Claude, 1.4 une sortie entière, 1.5 finitions et impression, 1.6
style appris), publiée après un essai réel ; entre deux, seulement des correctifs (`X.Y.Z`). Le
standard de notation (une étoile = un niveau de qualité fixe, 0 ★ = pas encore jugée, rejeter =
drapeau, Claude ne propose jamais 5 ★), venu de la section 1.1 de la feuille de route, est
maintenant le texte de `Notation.standard` (voir Règles).

Le README pointe vers `https://github.com/mdany75/Developpeur/releases/latest/download/Developpeur.zip`.

## Règles

- Répondre et écrire (commits, README, textes des outils, du module, des fenêtres et des erreurs)
  en français, dans un style simple et précis.
- **Pour un photographe amateur** : Dany retouche ses propres photos (souvenirs, écran, partage,
  impression), sans client, vente ni concours ; Développeur l'aide à leur donner une allure
  professionnelle sans être pro. Rien d'orienté client, mariage ou concours (galeries, collections
  publiées, profils Client ou Concours), et plus de Photoshop : ni agrandissement génératif, ni
  crédits Firefly, ni ouverture dans Photoshop. `MCPServerTests` et `Version25Tests` vérifient que
  les consignes, les outils et les invites n'en parlent pas ; `NotationTests`, le standard de
  notation.
- **Ne jamais retoucher de vraies photos pendant les tests** : `swift test` passe par
  `FakeLightroom` et un faux module TCP ; `scripts/tester-module.sh` par les Lightroom simulés de
  `Tests/Lua/Liaison/Simulation.lua` et `Tests/Lua/Fenetre/Simulation.lua`, avec `faux-claude.sh`
  à la place de Claude Code (ni Claude, ni quota, dossier personnel temporaire). Un essai dans
  Lightroom, ou la recette, se fait sur les photos de la collection « Développeur › Essais » (des
  copies virtuelles que Claude choisit et y range), ou sur une photo que Dany désigne ; l'essai se
  défait ensuite (`undo_last`, `revert_to_original` ou ⌘Z).
- Ne jamais écrire dans les vrais fichiers de Claude ni dans les préférences de Lightroom depuis
  les tests : `ClaudeRegistration` reçoit des chemins temporaires, les raccourcis vont dans un
  fichier d'essai, le presse-papiers est un presse-papiers nommé.
- `stdout` est réservé au protocole JSON-RPC : les journaux vont sur `stderr`. Réponses et
  notifications de progression y passent sous le même verrou (`print(line:)` de `main.swift`).
- Claude Desktop (et l'onglet Code de l'application, qui lui passe ses appels) abandonne un outil
  au bout de 60 s, sans tenir compte de la progression, puis relance le serveur. Tout appel
  d'outil passe par `FileOutils` : un seul à la fois vers le module, réponse d'attente à 50 s sans
  `progressToken`, résultat gardé pour le même appel répété. Ne jamais appeler le module hors de
  cette file depuis le serveur (le module traite chaque commande dans sa propre tâche : deux
  commandes mêlées se gênent). Voir `docs/SPEC.md`, Délai des appels d'outils.
- Claude Desktop et chaque session de Claude Code gardent le serveur lancé à leur ouverture : après
  une installation, relancer Claude Desktop et ouvrir une nouvelle session Claude Code pour avoir les
  nouveaux outils. `/clear` vide la conversation mais ne relance pas le serveur. La fenêtre Claude
  lance le sien avec chaque processus Claude Code, fermé quand le module se recharge ou que
  Lightroom quitte.
- Claude Desktop ouvert garde `claude_desktop_config.json` en mémoire et le réécrit : une
  inscription faite pendant ce temps se perd (constaté le 20 octobre 2026 : `MCP-Developpeur`
  perdu, l'ancienne clé `lightroom` revenue). L'inscription se fait Claude Desktop fermé ;
  `install.sh` et `uninstall.sh` le signalent par `pgrep -xa Claude` (sans `-a`, pgrep ne voit pas
  Claude Desktop depuis une session de Claude Code qu'il a lancée). `--install` retire l'ancienne
  clé `lightroom` de MCP Lightroom (`ClaudeRegistration.ancienneCle`), `--status` la signale.
- Un seul connecteur : la clé `MCP-Developpeur` dans Claude Desktop et Claude Code
  (`ClaudeRegistration.serverKey`, égale à `ServerInfo.name` ; `title` « MCP-Développeur »), et
  le nom `developpeur` dans `connecteur.json` pour la fenêtre (`Session.SERVEUR`). Les fenêtres
  (« Claude », « Claude · liaison », « Claude · Publication », « Claude · Consommation »,
  « Claude · Séance de notation »), les étapes « Claude · … », l'instantané « Avant Claude »,
  l'ensemble de collections « Claude » et les copies virtuelles « Claude » gardent le nom Claude :
  c'est ce que Claude a fait.
- Le module est du **Lua 5.1** (celui de Lightroom) : pas de `goto`, pas de `//`. Le JSON passe
  toujours par `Json.lua`, qui lit et écrit les nombres sans dépendre de la locale (en français,
  `string.format` écrirait « 0,35 »). Dans une tâche asynchrone, `LrTasks.pcall` et non `pcall`
  dès que le code peut attendre (rendu, accès au catalogue). `os.time` et `os.date` passent par
  `Compat.lua` (remplacés par `LrDate` s'ils manquaient).
- Toute écriture dans le catalogue passe par `withWriteAccessDo` (`ecrire` dans `Ecriture.lua`) ;
  la simulation des tests le vérifie.
- La mémoire de Claude (champs de `Metadonnees.lua`) se lit par `lireChamp` ou `lireJson` et
  s'écrit par `garder` : Lightroom copie ces champs dans une copie virtuelle, et seuls ceux-là
  vérifient qu'elle appartient à la photo (`proprietaireMemoire`). Dans une écriture, Lightroom
  relit un champ du module avec sa valeur d'avant l'écriture (constaté par ses effets) : `garder`
  ne rattache donc une photo qu'une fois par écriture (`Photos.nouvelleEcriture`, appelé par
  `Ecriture` au début de chacune), et la simulation ne montre un champ écrit qu'après l'écriture.
  Voir `docs/SPEC.md`, Mémoire des retouches.
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
  eux, Lightroom ne la reconnaît pas (constaté). `sansCalculsIA` les garde ;
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
- `match_series` compare la photo et la référence par la même mesure des tons neutres ; les tons
  suivis d'une passe à l'autre (`Measurements.neutres` avec masque) ne servent qu'aux pentes, et
  Teinte et Température se résolvent ensemble (`PentesSerie`, relevées dans Lightroom). Chaque
  photo repart des pentes relevées.
- Le module signale la photo active changée avec sa réponse suivante (`evenements`, avec son `id`,
  seulement si elle n'est plus celle signalée la dernière fois) ; le serveur le transmet aux
  clients abonnés (`resources/subscribe`), sinon le dit une fois au résultat d'outil suivant
  (Claude Desktop ne s'abonne pas, constaté). Rien ne part sans une commande.
- Une photo hors du film fixe se sélectionne après l'affichage de son dossier, avec un délai
  (`selectionnerAvecSource`, constaté) : passer par lui. Le serveur n'ouvre un original que pour le
  point AF d'une photo Fujifilm, en temps borné (`LecteurPointsAF`) : macOS peut faire attendre
  `open()` sans fin (autorisation d'accès au volume) ; Claude ne répond jamais à une demande
  d'autorisation de macOS.
- Un masque combiné range chaque composant avec `MaskBlendMode` (0 ajouter, 1 soustraire) ; une
  intersection est une soustraction du composant inversé (`Locaux.combiner`).
- Formes constatées des masques récents (voir `docs/SPEC.md`, Retouches locales) : objet en
  rectangle = `Mask/Polygon` dont les `Points` sont des tables `{X, Y}` ; plage de couleurs =
  `PointModels` « c1 c2 c3 x y 0 », modèle Lab étalonné (`ModeleCouleur`) ; plage de profondeur =
  `Type = 3` et `DepthRange` de 0 à 1 (jamais `DepthMin`/`DepthMax`) ; couleurs ponctuelles d'un
  masque = `LocalPointColors`, des textes de 19 nombres. La simulation vérifie chacune.
- Le préfixe « Claude · » des noms de masques (serveur) et d'étapes (module) n'est jamais doublé :
  un nom donné qui le porte déjà le perd d'abord.
- Chaque constat fait dans Lightroom (« Constaté dans Lightroom Classic » de `docs/SPEC.md`,
  section Fenêtre Claude comprise) a sa règle dans la simulation de sa suite (`Tests/Lua/Liaison` ou
  `Tests/Lua/Fenetre`) et un test qui échoue sans la correction ; et une étape de la recette quand
  c'est possible.
- Un aperçu attend le calcul des masques IA (`attendreCalculsIA`) : sinon Lightroom ouvre la
  fenêtre « Mises à jour IA recommandées », qui bloque l'exportation jusqu'à la réponse de
  l'utilisateur. Toute exportation calcule d'abord les réglages IA : `calculerAvantRendu` pour la
  liaison, `photo:updateAISettings` dans `Publication.publier` pour la fenêtre Publication. Ni le
  serveur ni le module ne demandent la permission d'Accessibilité (elle irait à Claude Desktop, au
  terminal ou à Lightroom).
- Les seuils de netteté, de bruit, de ressemblance et d'ouverture des yeux (`Detail.swift`,
  `AnalyseVision.swift`) ont été relevés sur de vrais aperçus : les mesurer de nouveau avant de les
  changer ; les plafonds de note (`Notation.plafond`) les reprennent sans en ajouter. Au tri, une
  pile de Lightroom compte comme une rafale (seule sa meilleure vue échappe au plafond de 3 ★). Le
  tri (`cull_photos`) mesure les vignettes du cache de Lightroom (commande `vignettes`) et ramène
  leur netteté à celle d'un aperçu exporté (`thumbnailSharpnessFactor`, relevé). Vision ne
  s'appelle pas en grand parallèle (`concurrentPerform` l'a bloqué) : deux photos à la fois au
  plus.
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
  l'a par `read_standard` seulement (ses consignes l'y renvoient) ; l'invite `noter` sert à Claude
  Desktop et à Claude Code en terminal.
  `Notation.plafond` en tire les plafonds de `cull_photos` (0 et rejet proposé pour une photo
  floue, une mise au point manquée ou des yeux fermés ; 3 pour une photo douce ou qui n'est pas la
  meilleure de sa rafale ; 2, à vérifier, pour une photo presque noire ou brûlée ; 1 pour une
  capture), que `dernierTri` (`ToolHandler`) garde pour le processus du serveur.
- **Claude ne propose jamais 5 ★** : `propose_ratings` refuse une note de 5 ou plus avant tout
  envoi (`Notation.noteMaximale = 4`), et le module la refuse encore
  (`Notation.NOTE_MAX_PROPOSEE`) ; `set_metadata` garde 5 ★ pour l'utilisateur (à sa demande
  seulement), comme Changer… dans les fenêtres. Jamais `set_metadata` pour une note sans demande.
  `propose_ratings` est en lecture seule (`readOnlyTools` : rien dans le catalogue) ; il valide
  toutes les propositions avant d'envoyer quoi que ce soit (les clés de chaque élément à la main :
  `parametresInconnus` ne voit que le premier niveau), refuse une note au-dessus du plafond du
  dernier `cull_photos` sans `to_check`, refuse la passe 4 (5 ★, l'utilisateur seul ; le module
  aussi), et envoie une seule commande `notation` (`action = 'proposer'`), absente de
  `LightroomBridge.lectures` (rejouée, elle remettrait les propositions à « proposée »).
  `read_session` (seul) envoie `notation` avec `action = 'seance'` : la séance ouverte, ses photos
  et sa passe, pour l'invite `noter` hors de la fenêtre.
- Le registre des notes proposées et des séances (`Notation.lua`) sert la liaison (commande
  `notation` : `proposer`, `lire`, `seance`, rien dans le catalogue) et les fenêtres (carte Note,
  Séance de notation). Il se charge dans les deux simulations : `Bibliotheque` n'est requise qu'au
  moment d'écrire, et rien de l'interface (un test le vérifie). Il est rangé dans `notation.json`
  (`Chemins.racine()`), propre au catalogue ouvert (chemin gardé ; un autre catalogue trouve un
  registre vide), les photos en clés texte (`Json.decode` rend des clés texte), chacune avec son
  uuid (une photo d'un autre uuid perd sa proposition) ; tout ce qui en sort vers une vue est une
  table neuve. Une proposition `to_check` commence « à vérifier » (`a_verifier`) : Tout accepter
  ne la prend pas. Les fenêtres s'abonnent (`Notation.abonner`, noms `'fenetre'` et `'seance'`) et
  comparent `Notation.version`. Le registre ne voit pas une annulation (undo_last, ⌘Z : constaté
  le 20 octobre 2026, la planche montrait encore « acceptée ») : quand une fenêtre relit la note et
  le drapeau d'une photo (carte Note : `Fenetre.majPhoto` ; Séance : la planche, ses 12 photos et
  celle de la fiche), elle appelle `Notation.recaler(releves, version)`, en un seul appel par
  lecture (une écriture de `notation.json` au plus pour une page) et avec `Notation.version` lue
  avant les photos (un relevé plus vieux qu'une note posée entre-temps, ou fait pendant une
  écriture de `Notation.poser`, ne défait rien) : une proposition acceptée ou changée dont la note
  n'y est plus redevient `proposee`.
- Seule une note acceptée ou changée s'écrit, par `Notation.poser`, dans une tâche, jamais pendant
  que Claude travaille (`Moteur.travaille` : la carte Note et la Séance le refusent dans la vue et
  dans l'action), puis `Bibliotheque.noter` : une écriture (`ecrire`) par lot de 500 photos, une
  étape « Claude · notation » par photo que `undo_last` défait, mémoire `Bibliotheque` gardée ;
  garde-fous des photos (`verifierProtection` : copies virtuelles seulement, libellé protégé,
  photos rejetées) maintenus ; `depuisLightroom` et `confirme` lèvent la pause, « Proposer
  d'abord » et le plafond de photos par écriture (le clic, ou la confirmation de Tout accepter,
  vaut accord explicite). Une note posée ainsi par l'utilisateur n'entre pas dans l'état d'avant
  Claude (`memoriser` sans `fusionnerOriginal`) : « Revenir à « Avant Claude » » et
  `revert_to_original` la laissent en place ; `undo_last` la défait toujours, étape par étape.
  Accepter pose la proposition telle quelle : un rejet pose le drapeau sans toucher les étoiles,
  une note ne retire qu'un rejet déjà posé (un drapeau Retenue reste). La passe 4 (5 ★) ne se lance
  pas dans la Séance (`Consignes.passes[4]` n'a pas de message, seulement `seul`).
- Ports fixes 54770 (commandes) et 54771 (réponses), sur 127.0.0.1 : `Liaison.lua` et
  `LightroomBridge` doivent rester d'accord (`DEVELOPPEUR_PORT` côté serveur pour essayer un autre
  port). Le serveur ouvre une connexion par commande : Claude Desktop, Claude Code et la fenêtre
  Claude se succèdent sur la même liaison.
- `apply_settings` respecte le mode « Proposer d'abord » du module (refus sans `confirm = true`) ;
  ne pas contourner. La fenêtre Claude le montre et le bascule (clé `mode` des préférences du
  module).
- **Jamais l'API** : la fenêtre Claude passe par Claude Code et la connexion claude.ai.
  `relais.sh` retire de l'environnement les clés d'API et les autres fournisseurs
  (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, Bedrock, Vertex) ; ne jamais
  lire ni copier les jetons de connexion de Claude Code.
- Lightroom ne sait pas tenir un processus par ses tuyaux : `relais.sh`, lancé par
  `LrTasks.execute`, garde Claude Code ouvert pour une conversation (`entree.jsonl` passé par
  `tail -f`, `sortie.jsonl` relu par le moteur) et le ferme quand Lightroom n'est plus là. Claude
  Code ne reçoit que le connecteur (`connecteur.json`, `--strict-mcp-config`, outils
  `mcp__developpeur__*`, `Conversation.PREFIXE_OUTILS`), aucun outil intégré (`--tools ""`), rien
  qui demande une permission, ni compétences ni réglages de l'utilisateur, dans le dossier de
  travail vide `Atelier/`. Voir `docs/SPEC.md`, Fenêtre Claude › Claude Code.
- Le presse-papiers ne se lit que sur un clic de l'utilisateur (bouton 📋, `presse-papiers.js`) ;
  les essais passent par un presse-papiers nommé, jamais le vrai.
- Toute table donnée à Lightroom par la fenêtre (éléments d'une liste, d'un menu, réglages
  d'exportation, valeur d'une propriété) est neuve : jamais une table relue par `Json.decode`
  (métatable, Lightroom bloque ; la simulation de la fenêtre la refuse).
- La fenêtre ne peut pas changer de structure une fois ouverte, et une vue masquée garde sa place :
  tout ce qui varie passe par des propriétés liées (`bind`) et des variantes superposées de même
  taille (`place = 'overlapping'`). `visible` lié ne masque qu'une vue simple (texte, bouton,
  image, menu, champ, case, liste, séparateur) : sur un conteneur (`row`, `column`, `view`,
  `group_box`, `tab_view`, `scrolled_view`), Lightroom l'ignore (constaté le 20 octobre 2026 : les
  trois onglets de la Conversation claire s'affichaient superposés), et la simulation de la fenêtre
  le refuse. Une condition de visibilité des pièces passe toujours par `F.egal`, `F.non`, `F.si` ou
  `F.condition`, que `F.et` sait combiner en une liaison à plusieurs clés (`keys`, `operation`). Le
  contenu d'un onglet se crée par une fabrique masquable (`Vues.masquable(f, F, condition)`) : elle
  pose la condition sur chaque vue simple, combinée avec son propre `visible`, et s'emboîte
  (Retoucher, puis `aProposition`) ; pas de `group_box` dans un onglet (elle en fait une colonne à
  titre gras), et jamais `visible` sur la colonne d'une variante. Le fil est une grille de lignes
  (`Fil.lua`), coupées d'après la chasse mesurée des polices (`Metriques.lua`) ; ne pas y insérer
  de vues de hauteur variable. Une propriété liée doit avoir une valeur avant l'ouverture (les
  tests le vérifient, pour chaque clé d'une liaison à plusieurs clés). `save_frame`
  garde la taille d'une ouverture à l'autre, un cadre par disposition et par taille
  (`Fenetre.cadre` : `DeveloppeurClaude-<disposition>-<taille>-<FORME>`) : quand le contenu de la
  fenêtre Claude rapetisse, augmenter `Fenetre.FORME`.
- Le champ de demande est `immediate = false` (Retour le valide) ; tout bouton de la fenêtre Claude
  passe par `Fenetre.bouton` (`F.bouton` dans les pièces), celui de la Séance par son `bouton`
  local : ils annulent l'envoi automatique (un clic valide aussi le champ), et les essais le
  vérifient pour chaque bouton. Un nouveau bouton créé par `f:push_button` enverrait la demande
  tapée.
- La fenêtre Claude a trois dispositions : préférence `disposition` de `Chemins.defauts`
  (`'atelier'`, `'conversation'` par défaut, `'panneau'`), menu du Gestionnaire de modules externes
  et menu Disposition de la fenêtre. `Fenetre.lua` garde l'état, les rafraîchissements, les
  actions et la boucle ; les pièces (carte Note comprise) sont dans `Vues.lua`, les assemblages et
  leurs dimensions par taille (`Dispositions.TAILLES`) dans `Dispositions.lua` : ni
  `require 'Fenetre'` ni couleur créée à leur chargement (`liens.lua` les charge sans `LrColor`),
  couleurs, polices et actions arrivent par `F`. Une autre disposition rouvre la fenêtre
  (`Fenetre.rouvrir`, appelé aussi par `Fenetre.afficher` quand les préférences ont changé) : la
  demande validée revient dans le champ sans partir (`Fenetre.brouillon`, posé sous
  `Fenetre.ignorerSaisie`), et chaque ouverture a sa génération (`Fenetre.generation`) : une seule
  boucle tourne. Les séances (`genre == 'notation'`) ne se montrent pas parmi les conversations.
- Les onglets (Aperçu, Proposition, Note ; Retoucher, Noter) sont une rangée de `radio_button`
  (clé `onglet` ; la simulation exige `checked_value`) au-dessus de variantes superposées de même
  largeur, pas un `tab_view` (non constaté dans Lightroom) ; une seule bascule automatique par
  proposition ou note arrivée (vers Proposition, Retoucher ou Note).
- La Séance de notation (`FenetreNotation.lua`, `save_frame = 'DeveloppeurNotation'`) est
  autonome : elle ne dépend pas des pièces de la fenêtre Claude (ses propres aides) et s'appuie sur
  `Notation`, `Moteur`, `Consignes.passes`, `Fil`, `Publication` et `Vignettes.demander`. Sa
  conversation est de genre `'notation'`, dans le même moteur (`Moteur.nouvelleSeance`, jamais
  `Moteur.courante`) ; `Moteur.envoyer` reçoit `conversation` et `contexte`, `Moteur.enCours` dit
  laquelle travaille. Une seule session Claude Code : passer de l'une à l'autre la relance par
  `--resume`. `consignes.md` s'écrit dans le dossier de chaque session (`Session:lancer`),
  `Consignes.texteNotation` en plus pour une séance (`Consignes.pour`). L'élément `notation` du
  fil (appel de `propose_ratings`) ne sert qu'à l'affichage : le registre reste la source.
- Ne jamais nommer un fichier du module `Versions.lua` : Lightroom refuse de le charger (constaté ;
  d'où `Composants.lua`). Un seul `Info.lua`, `Init.lua`, `Arret.lua` et `PluginInfoProvider.lua`
  pour la liaison et la fenêtre, sans fichier de fusion (`InfoFenetre.lua`…) :
  `scripts/tester-module.sh` refuse l'un et l'autre.
- Un raccourci d'app vise le titre exact de l'entrée de menu, tel que Lightroom l'écrit : trois
  espaces devant chaque entrée de module (`Raccourcis.RETRAIT`, constaté par l'accessibilité).
  Lightroom ne lit les raccourcis qu'à son lancement : un rechargement du module ne suffit pas.
- Pas de calcul long en Lua sur la tâche de l'interface : base64, réductions d'images (`sips`) et
  commandes du système passent par `LrTasks.execute` (qui ne bloque que la tâche).
- Un essai de publication dans Lightroom (fenêtre Publication) se fait sur une photo d'essai, et
  le fichier publié va ensuite à la Corbeille (jamais effacé).
- `build.sh` signe avec le certificat « Developer ID Application » de Dany et le runtime durci,
  puis notarise l'archive (profil `notarisation` de `notarytool`). `SKIP_NOTARIZE=1` pour un essai
  rapide ; ne jamais publier une archive non notarisée, ni construite avec `--sans-tests`.
- Avant de pousser une fonctionnalité : README et `CHANGELOG.md` à jour, capture d'écran refaite
  dans Lightroom si l'interface a changé (`docs/capture.png` : la fenêtre Claude ;
  `publication.png`, `consommation.png`, `suivi.png` : les autres fenêtres), et une nouvelle
  version si ce qu'on installe a changé.
- Pousser sur `main` directement.

## Organisation

- `Sources/DeveloppeurKit/` : `JSONValue` (JSON générique), `MCPServer` (JSON-RPC, initialize, tools, prompts, ressources), `FileOutils` (appels d'outils un à un, réponse d'attente avant les 60 s de Claude Desktop), `Progression` (notifications de progression), `ContexteAppel` (progression et annulation d'un appel), `Tools` (socle des outils) et ses extensions `Tools+Analyse` (aperçu, zoom, comparaison, mesures de série, réglages), `Tools+Retouche` (`apply_settings`, `preview_settings`, `enhance_photo`, `remove_distractions`), `Tools+Balance` (balance sur un point neutre), `Tools+Locales` (masques, taches, yeux rouges), `Tools+Recalage` (grilles demandées, gardées en mémoire), `Tools+Gestion` (copie, profils, paramètres prédéfinis, journal), `Tools+Bibliotheque` (recherche, classement, mots-clés, collections, copies virtuelles, photo montrée), `Tools+Tri` (tri d'une séance, planche contact jusqu'à 30 vignettes, vignettes par lots), `Tools+Notation` (`propose_ratings`, validé avant la commande `notation`), `Tools+Livraison` (`export_photos` : formats, HDR, poids, filigrane, réimportation, livraisons types lues dans les services Disque dur, noms exacts, dossier choisi, aperçus dynamiques, fenêtre d'exportation en dernier recours ; modèles de noms de fichiers et filigranes de l'utilisateur, relecture du fichier livré), `Tools+Variantes` (`compare_variants`, `choose_variant`), `Tools+Serie` (`match_series`, pentes de la balance, expositions d'après la prise de vue), `Tools+Style` (`remember_style`, ressources) ; `Tri` (défauts, rafales, ordre de lecture, plafonds de note, rejets proposés), `Notation` (standard de notation, seule copie ; plafonds de note), `PointAF` (point de mise au point des fichiers Fujifilm, passage dans l'image affichée), `MotsClesVision` (mots-clés de Vision traduits), `ModeleCouleur` (modèle d'une couleur prélevée), `ProfilsObjectif` (profils d'objectif `.lcp` installés), `GuideStyle` (guide de style de l'utilisateur, `~/Library/Application Support/Developpeur/guide-de-style.md`), `ReglagesAPlat` (`--dump`), `Catalogue` (les 124 réglages de développement, version minimale de Lightroom des plus récents, les profils d'appareil, les libellés), `Mesures` (mesures d'un aperçu), `Detail` (netteté et bruit), `AnalyseVision` (visages, pupilles, note esthétique, saillance, photos semblables, cadres des personnes), `Lignes` (angle d'une ligne désignée), `Recalage` (correspondance entre l'image corrigée et celle d'avant la correction d'objectif, Upright et la perspective), `Recette` (recette dans le vrai Lightroom), `Images` (zoom, côte à côte, planche contact), `ProfilsLook` (profils à base de Look installés), `EffetsLocaux` (effets locaux de Lightroom, `.lrtemplate`), `PresetXMP` (paramètres prédéfinis XMP), `LightroomBridge` (client TCP du module), `Prompts` (invites), `ClaudeRegistration` (inscription dans les fichiers de configuration de Claude), `MiseAJour` (dernière version publiée, par `gh`, pour `--status`), `ServerInfo` (nom, titre, version, consignes données à Claude)
- `Sources/MCPDeveloppeur/main.swift` : options de ligne de commande et boucle stdio
- `Lightroom/Developpeur.lrplugin/`, le module :
  - déclaration et cycle de vie : `Info.lua` (« Développeur », `com.danymenard.developpeur`, menus, version), `Init.lua` / `Arret.lua`, `Menage.lua` (paramètres prédéfinis invisibles effacés), `PluginInfoProvider.lua` (Gestionnaire de modules externes : sections liaison et fenêtre Claude, disposition comprise), `Preferences.lua` (réglages de la liaison ; ceux de la fenêtre dans `Chemins.defauts`, même table), `Metadonnees.lua` (champs privés), `Menu*.lua` (les neuf entrées de Module externe - Extras, dans Fichier et Bibliothèque ; `MenuNotation.lua` : Séance de notation…)
  - la liaison : `Liaison.lua` (prises LrSocket, `module.log`), `Commandes.lua` (répartition des commandes du serveur) et les modules qui les portent : `Lecture.lua` (état, sélection, réglages, paramètres prédéfinis, diagnostic, journal), `Rendu.lua` (aperçus, propositions, rendus du recalage), `Retouche.lua` (appliquer, recadrer, masquer, retoucher, copier), `Amelioration.lua` (débruitage, détails bruts, super résolution), `Suppression.lua` (reflets, retrait de la poussière), `Masques.lua` (reprendre un masque : commande `masques` ; masques vides), `Conversions.lua` (rotation d'un quart de tour), `Progression.lua` (barre de progression de Lightroom pendant une série : commande `progression`), `Vignettes.lua` (vignettes du cache d'aperçus ; `Vignettes.demander`, aussi pour la Séance), `Notation.lua` (registre des notes proposées et des séances, `notation.json` : commande `notation`, `Notation.poser`), `Livraison.lua` (exporter, fenêtre d'exportation, options de livraison, dossier choisi dans une fenêtre, noms exacts, aperçus dynamiques), `Services.lua` (services de publication et réglages des services Disque dur, lus seulement), `Variantes.lua` (variantes en instantanés), `Annulation.lua` (annuler, revenir), `Bibliotheque.lua` (classement, paramètres prédéfinis de métadonnées, mots-clés, collections, recherche, copies virtuelles, photo montrée et filtre de la Bibliothèque : commandes `metadonnees`, `motsCles`, `collections`, `chercher`, `copieVirtuelle`, `montrer` ; notes acceptées : `Bibliotheque.noter`) ; leur socle : `Photos.lua` (photos visées, description, mémoire de Claude), `Reglages.lua` (valeurs de développement), `Recalage.lua` (géométrie, grille du serveur), `Plans.lua` (ce qu'une retouche changera), `Ecriture.lua` (écriture dans le catalogue, étapes, journal), `Profils.lua` (profil relu après l'écriture), `Recadrage.lua` (calcul du cadre), `Geometrie.lua` (positions de l'aperçu vers le fichier), `Locaux.lua` (tables des masques, taches et yeux rouges) — ces trois-là sans SDK —, `Json.lua`, `Suivi.lua` (fenêtre de suivi « Claude · liaison »)
  - la fenêtre Claude : `Fenetre.lua` (la fenêtre : état, actions, boucle, réouverture), `Vues.lua` (ses pièces, carte Note comprise, et la fabrique masquable des onglets), `Dispositions.lua` (Atelier, Conversation claire, Panneau, et leurs dimensions), `Fil.lua` (le fil en lignes), `Metriques.lua` (chasse des polices, produite par `scripts/metriques.swift`), `Moteur.lua` (conversations et processus de Claude Code, indépendants de la fenêtre), `Session.lua` (un processus Claude Code par `relais.sh`), `relais.sh`, `Evenements.lua` (lignes stream-json de Claude Code), `Conversation.lua` (éléments d'une conversation), `Stockage.lua` (conversations sur le disque), `Images.lua` (aperçus et photos jointes, base64 et `sips`), `presse-papiers.js` (lecture du presse-papiers par `osascript`), `Consignes.lua` (consignes ajoutées, invites en raccourcis, styles), `Lightroom.lua` (photo active et sa note, sélection, état de la liaison, connexion de Claude Code), `Composants.lua` (versions du module et du connecteur en bas de la fenêtre), `Raccourcis.lua` (⌃⌥C), `Chemins.lua` (dossiers et réglages de la fenêtre), `Fichiers.lua`, `Texte.lua` (UTF-8), `Journal.lua` (`conversation.log`), `Compat.lua` (`os.time`, `os.date`), `vide-*.png` (images « aucun aperçu », une par cadre d'aperçu : `vide-120.png` à `vide-320.png` carrées, `vide-450x300.png` à `vide-720x480.png` pour l'Atelier ; `vide-120.png` aussi pour les cases de la Séance, `vide-300.png` pour sa fiche) ; `FenetrePublication.lua` et `Publication.lua` (profils et exportation de la fenêtre Publication), `FenetreConsommation.lua` et `Consommation.lua` (jetons comptés, budget de la semaine), `FenetreNotation.lua` (Séance de notation : passes, planche, fiche, Tout accepter)
- `Tests/DeveloppeurKitTests/` : tests XCTest avec `FakeLightroom` et `FakePlugin` (TCP)
- `Tests/Lua/Liaison/` : `Simulation.lua` (SDK de Lightroom simulé pour les commandes du serveur), `tests.lua`, et `liens.lua` (chaque champ lu d'un module requis existe, dans tous les fichiers du module)
- `Tests/Lua/Fenetre/` : `Simulation.lua` (SDK simulé pour la fenêtre, dossier personnel temporaire, liaison jamais démarrée ; refuse `visible` sur un conteneur, évalue les liaisons à plusieurs clés), `faux-claude.sh` (imite Claude Code en stream-json), `tests.lua`, et les essais à part `essais-*.lua` (chacun charge la simulation, la complète localement sans toucher `Simulation.lua`, a ses propres aides et sort en échec si un essai échoue ; tous lancés par `tester-module.sh`) : `essais-dispositions.lua`, `essais-moteur.lua`, `essais-seance.lua`, `essais-integration.lua` (de bout en bout avec les vrais modules, `sips` compris)
- `scripts/` : `tester-module.sh` (vérification du module avec LuaJIT), `metriques.swift` (chasse des polices du fil), `images-vides.swift` (images « aucun aperçu », une par cadre de `Dispositions.TAILLES`)
- `.github/workflows/tests.yml` : syntaxe des scripts et les deux suites à chaque envoi sur `main` (macOS)
- `build.sh` (tests, compilation, signature, archive notarisée), `install.sh`, `uninstall.sh`
- `Resources/Info.plist` : identifiant `com.danymenard.mcp-developpeur` et version (incrusté par `-sectcreate` dans `Package.swift`)
- `docs/SPEC.md` : cahier des charges, protocole entre le serveur et le module, et la fenêtre Claude (architecture, contraintes du SDK, fichiers) ; `docs/aide-adobe-developpement.md` : notes sur l'aide d'Adobe (outils de développement, ordre d'utilisation, écarts avec la méthode du connecteur, ce qui reste à faire à la main), à relire avant de changer les consignes (`ServerInfo`, `Consignes.lua`) ou les invites (`Prompts`) ; captures : `capture.png` (la fenêtre Claude, capture principale du README), `publication.png`, `consommation.png`, `suivi.png` (fenêtre de suivi de la liaison)
