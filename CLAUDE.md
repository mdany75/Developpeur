# CLAUDE.md — Développeur

Claude retouche les photos de Lightroom Classic. Deux pièces liées par TCP local (127.0.0.1, ports
fixes 54770 commandes et 54771 réponses, jeton privé depuis la 1.2) : le connecteur
MCP-Développeur, serveur MCP natif (Swift, SwiftPM, sans Xcode ni Node, exécutable
`mcp-developpeur`) que Claude Desktop et Claude Code lancent sur stdio ; et le module Lightroom
Classic « Développeur » en Lua (`Lightroom/Developpeur.lrplugin`, Lightroom Classic 13.3 au moins),
qui exécute les commandes dans le catalogue (la liaison) et porte la fenêtre Claude : une
conversation par photo avec Claude Code (forfait claude.ai, jamais l'API), qui retouche et note par
ce même connecteur, avec les fenêtres Demande rapide, Suivi, Publication et Consommation.

Outils, invites et ressources `developpeur://` : `Sources/DeveloppeurKit/Tools+*.swift`. Le README
parle pour l'utilisateur ; `docs/SPEC.md` porte le protocole, les chantiers de la 1.3 et la
fenêtre Claude (dont Fenêtre B) ; `docs/artefacts/`, les sources des pages publiées en artefacts ; `docs/regles/`, les règles
chargées au besoin. Options de l'exécutable : `Sources/MCPDeveloppeur/main.swift` ; essais :
`Tests/` (`swift test`) et `scripts/` (module, polices et images de la fenêtre) ; identifiant et
version : `Resources/Info.plist`.
D'où vient une règle (dates, présentation d'origine) : `docs/regles/historique-projet.md`.

Développeur 1.0 remplace MCP Lightroom 2.7 et Claude pour Lightroom 1.6.1, sans en reprendre de
données. Leurs dépôts (`~/Developer/MCP-Lightroom`, `~/Developer/Claude-pour-Lightroom`) se
consultent en lecture seule : ne jamais y écrire.

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Commandes

- `./build.sh` : tests, compilation release, signature Developer ID (runtime durci),
  `build/Developpeur.zip` notarisé (profil `notarisation` de `notarytool`). `SKIP_NOTARIZE=1` ou
  `--sans-tests` pour un essai seulement : ne jamais publier une archive non notarisée, ni
  construite avec `--sans-tests`.
- `./build.sh --install` : serveur dans `~/Library/Application Support/Developpeur/`, module dans
  `~/Library/Application Support/Adobe/Lightroom/Modules/`, inscription « MCP-Developpeur » dans
  Claude Desktop et Claude Code.
- `swift test` : jamais le vrai Lightroom, ni le vrai jeton, ni le vrai écran, ni le vrai mflux.
- `scripts/tester-module.sh` (LuaJIT : `brew install luajit`) : forme, syntaxe, globales, liens
  entre les fichiers, suites `Tests/Lua/Liaison` et `Tests/Lua/Fenetre` avec leurs `essais-*.lua`.
- À la main : `swift build && ./.build/debug/mcp-developpeur --status`, puis
  `--call <outil> '{…}' [--image <fichier.jpg>]` (Lightroom ouvert, liaison démarrée ; chaque
  `--call` est un nouveau processus : le bilan de `view_photo` y repart de zéro).
- Recharger le module : fermer ses fenêtres (devant, elles réduisent le menu Fichier), Lightroom au
  premier plan, Fichier › Gestionnaire de modules externes › Développeur › Outils de l'auteur du
  module externe › Charger de nouveau le module ext. Piège : un `.lua` ajouté depuis le lancement
  ne se charge pas ainsi (« Could not load toolkit script »), ni un fichier qui le requiert, ni un
  raccourci clavier changé : quitter et relancer Lightroom après toute version qui ajoute un `.lua`.
- `bash uninstall.sh [--tout]` : jamais le catalogue ni les photos, ni « Fibo non importées » s'il
  n'est pas vide ; la liaison d'un Lightroom ouvert réécrit le jeton dans les 5 s : relancer le
  script Lightroom fermé.
- Recette (dans Lightroom ou d'une version), `--module diagnostic`, `--dump`, `--recalage`,
  `--marquer-af`, `--ecran`, `--focus`, `--boitier`, `--analyser`, `--graphiques`, `--constats`,
  `--eclairage`, `--etalonnage`, variables `DEVELOPPEUR_*`, journaux, polices, images de la fenêtre, détail de la
  désinstallation : skill `commandes-diagnostic`. Recette d'une version sur des copies remises à
  l'origine d'abord, sortie dans un fichier, en arrière-plan, jamais tronquée (`| head` la coupe au
  milieu d'une étape). `--eclairage --essai` et `--etalonnage --balayage` : copies virtuelles seulement. `--constats` en lecture
  seule (jamais `carnet constater`). Le chemin de l'original n'est jamais rendu à Claude
  (`af_point`). `--ecran` : pour le développement seulement (ni la fenêtre Claude ni Claude ne
  lisent plus l'écran). `DEVELOPPEUR_FIBO_GARDER` : développement seulement,
  rien n'y est jamais effacé (TIFF avec GPS) : ne pas la laisser posée.
- Publier une version : skill `publier-version` (numéro aux trois endroits, `Resources/Info.plist`,
  `Info.lua` et `Liaison.VERSION`, que `build.sh` compare au `CHANGELOG.md`).

Les fichiers produits vont dans `build/`, ignoré par git. Rien de compilé n'est commité.

## Règles

Avant de toucher à une partie, lire ses règles : `Lightroom/CLAUDE.md` (module Lua : catalogue,
Bibliothèque, livraisons, Suivi, carnet, notation côté module, fenêtre Claude et fenêtre B,
relais) ; `Sources/CLAUDE.md` (mesures et outils en Swift : composition, détail, éclairage, écran,
bilan, peau, doses, lumière, teint, tri, notation, masques, mise au point) ;
`docs/regles/retouche-generative.md` (Fibo 2, `generative_edit`) ; `docs/regles/liaison-fermee.md`
(jeton de la liaison, ports).

- Répondre et écrire (commits, README, textes des outils, du module, des fenêtres et des erreurs)
  en français, dans un style simple et précis.
- **Pour un photographe amateur** : Dany retouche ses propres photos (souvenirs, écran, partage,
  impression), sans client, vente ni concours ; Développeur l'aide à leur donner une allure
  professionnelle. Rien d'orienté client, mariage ou concours (galeries, collections publiées,
  profils Client ou Concours), et plus de Photoshop (ni agrandissement génératif, ni crédits
  Firefly, ni ouverture dans Photoshop) : `MCPServerTests` et `Version25Tests` le vérifient ;
  `NotationTests`, le standard de notation. Seule retouche générative permise : Fibo 2, en local,
  sur demande de Dany ; les taches de Claude restent `patchmatch`.
- **Ne jamais retoucher de vraies photos pendant les tests** : `swift test` passe par
  `FakeLightroom` et un faux module TCP ; `scripts/tester-module.sh` par les `Simulation.lua` des
  deux suites, avec `faux-claude.sh` à la place de Claude Code (ni Claude, ni quota, dossier personnel temporaire). Un essai dans
  Lightroom, ou la recette, se fait sur la collection « Développeur › Essais » (copies virtuelles
  que Claude choisit et y range) ou sur une photo que Dany désigne, et se défait ensuite
  (`undo_last`, `revert_to_original` ou ⌘Z). Ranger une copie dans Essais **après** l'avoir remise
  à l'origine : `revert_to_original` défait aussi ce rangement (mémoire `Bibliotheque`).
- Depuis les tests, ne jamais écrire dans les vrais fichiers de Claude ni dans les préférences de
  Lightroom (`ClaudeRegistration` reçoit des chemins temporaires, raccourcis dans un fichier
  d'essai, presse-papiers nommé), ni lire le vrai jeton ni le vrai écran
  (`LightroomBridge.fichierJeton` nil, `ToolHandler.lireEcran` et `Recette.lireEcran` sans écran
  par défaut ; aucun test n'envoie par `LightroomBridge.fromEnvironment()`). Seul
  `DEVELOPPEUR_ECRAN_REEL=1` fait lire l'écran du Mac à `swift test`.
- `stdout` est réservé au JSON-RPC : les journaux vont sur `stderr`. Réponses et notifications de
  progression sous le même verrou (`print(line:)` de `main.swift`).
- Claude Desktop (et l'onglet Code de l'application) abandonne un outil au bout de 60 s, malgré la
  progression, puis relance le serveur. Tout appel d'outil passe par `FileOutils` (un seul à la
  fois, réponse d'attente à 50 s sans `progressToken`, résultat gardé pour l'appel répété) : ne
  jamais appeler le module hors de cette file depuis le serveur (le module traite chaque commande
  dans sa propre tâche : deux commandes mêlées se gênent). `docs/SPEC.md`,
  Délai des appels d'outils.
- Claude Desktop et chaque session de Claude Code gardent le serveur lancé à leur ouverture : après
  une installation, relancer Claude Desktop et ouvrir une nouvelle session (`/clear` ne relance pas
  le serveur). Un connecteur d'avant la 1.2 resté ouvert est refusé par le module (« Liaison
  fermée… »). La fenêtre Claude lance le sien avec chaque processus Claude Code, fermé quand le
  module se recharge ou que Lightroom quitte.
- Claude Desktop ouvert garde `claude_desktop_config.json` en mémoire et le réécrit : une
  inscription faite pendant ce temps se perd. S'inscrire Claude Desktop fermé ; `install.sh` et
  `uninstall.sh` le signalent par `pgrep -xa Claude` (sans `-a`, pgrep ne voit pas Claude Desktop
  depuis une session de Claude Code qu'il a lancée). `--install` retire l'ancienne clé
  `lightroom` (`ClaudeRegistration.ancienneCle`), `--status` la signale.
- Un seul connecteur : clé `MCP-Developpeur` (`ClaudeRegistration.serverKey` = `ServerInfo.name`,
  `title` « MCP-Développeur »), nom `developpeur` dans `connecteur.json` (`Session.SERVEUR`). Les
  fenêtres « Claude · … », les étapes « Claude · … », l'instantané « Avant Claude », l'ensemble de
  collections et les copies virtuelles « Claude » gardent le nom Claude : c'est ce que Claude a
  fait. Le nom affiché du module est « Développeur IA pour Lightroom » (`LrPluginName`, Gestionnaire
  de modules externes), sans changer d'identifiant (`LrToolkitIdentifier`, dossiers, clé, collection
  « Développeur › Essais ») ; la barre de titre de la fenêtre Claude dit « Développeur IA » suivi du
  numéro installé (« Développeur IA v1.5 » : `Fenetre.titreFenetre`, d'après `Composants.module()` ;
  « Développeur IA » seul si la version ne se lit pas) ; son menu (« Ouvrir la fenêtre Claude »,
  ⌃⌥C, visé par `Raccourcis.lua`) et la documentation disent toujours « fenêtre Claude ».
- Le préfixe « Claude · » des noms de masques (serveur) et d'étapes (module) n'est jamais doublé :
  un nom donné qui le porte déjà le perd d'abord.
- Chaque constat fait dans Lightroom (« Constaté dans Lightroom Classic » de `docs/SPEC.md`, section
  Fenêtre Claude comprise) a sa
  règle dans la simulation de sa suite et un test qui échoue sans la correction, même quand il
  confirme le code ; et une étape de la recette quand c'est possible. Un constat de rendu que la
  simulation ne peut pas imiter (la linéarité de `CorrectionAmount`) le dit dans `docs/SPEC.md` et
  a son étape de recette.
- Ports : `Liaison.lua` et `LightroomBridge` doivent rester d'accord. Une connexion par commande ;
  Claude Desktop, Claude Code et la fenêtre Claude se succèdent sur la liaison, avec le jeton du
  même fichier.
- Liaison fermée : chaque ligne du serveur porte le `jeton`, ping compris ; `Liaison.recevoir` le
  vérifie avant `Commandes.executer`. `depuisLightroom` est retiré des paramètres reçus du réseau ;
  seuls les menus, la fenêtre de la liaison et la carte Note le posent, par appel direct : toute
  nouvelle voie interne reste un appel direct, jamais une ligne TCP. Le serveur ne crée jamais le
  fichier du jeton et ne dit jamais sa valeur (`--status`, `get_status`, diagnostic : son état
  seulement) ; le journal non plus. La simulation de la liaison n'imite que les deux commandes
  système du jeton et refuse toute autre.
- `apply_settings` respecte le mode « Proposer d'abord » (refus sans `confirm = true`) : ne pas
  contourner. Seul le Gestionnaire de modules externes règle la clé `mode` ; la fenêtre Claude la
  suit et la dit dans l'infobulle du voyant Lightroom.
- **Jamais l'API** : la fenêtre Claude passe par Claude Code et la connexion claude.ai.
  `relais.sh` retire de l'environnement les clés d'API et les autres fournisseurs
  (`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, Bedrock, Vertex) et pose
  `MAX_MCP_OUTPUT_TOKENS` ; ne jamais lire ni copier les jetons de connexion de Claude Code.
- Ce que Dany demande en mots clairs, Claude le fait (puce des garde-fous de `Consignes.texte`,
  phrase de `ServerInfo.instructions`) : ces consignes ne l'emportent jamais sur sa demande ; ne
  refuser que ce que les outils ne savent pas faire, ou ce que bloquent les réglages du module.
- Longueurs : consignes du connecteur sous `instructionsLimit` moins 300 (`Version24Tests`) ;
  consignes de la fenêtre (`Consignes.texte`, lues à chaque demande) sous 7 500
  (`essais-moteur.lua`). Les deux sont presque pleines : raccourcir ailleurs avant d'y ajouter ; ce
  qui dépasse va aux descriptions d'outils, aux résultats et aux invites. La longueur qu'une
  session garde d'une description d'outil n'est pas constatée : l'essentiel en tête, et un test de
  longueur pour les plus longues. Chiffres et historique : `docs/regles/historique-consignes.md`.
- Un essai de publication (fenêtre Publication) se fait sur une photo d'essai ; le fichier publié
  va ensuite à la Corbeille, jamais effacé.
- Version publiée : l'essai réel (recette, puis une demande dans la fenêtre Claude sur Essais,
  défaite) doit réussir avant le tag. Tout document nouveau pour Dany (guide, compte rendu, plan) :
  page HTML en artefact privé (outil Artifact, annotée par ses commentaires), source dans
  `docs/artefacts/`, commitée et poussée, jamais un document Claude Docs ; plus de Lavish.
- Avant de pousser une fonctionnalité : README et `CHANGELOG.md` à jour, captures refaites dans
  Lightroom si l'interface a changé (lesquelles et comment : `docs/regles/captures.md`), et une
  nouvelle version si ce qu'on installe a changé.
- Pousser sur `main` directement.
