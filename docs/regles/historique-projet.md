# Historique du projet (présentation et constats datés)

Sorti de `CLAUDE.md` le 31 octobre 2026 ; à lire quand on cherche d'où vient une règle de
`CLAUDE.md` (dates des constats, versions où une fenêtre ou un nom a changé).
`CLAUDE.md` garde la règle actuelle.

## Présentation d'origine

Claude retouche les photos de Lightroom Classic. Deux pièces qui se parlent par TCP local
(127.0.0.1, ports 54770 et 54771 ; depuis la 1.2, chaque commande porte le jeton privé de la
liaison) : le connecteur MCP-Développeur, un serveur MCP natif (Swift, SwiftPM, sans Xcode ni
Node, exécutable `mcp-developpeur`) que Claude Desktop et Claude Code lancent sur stdio ; et le
module Lightroom Classic « Développeur » en Lua (`Lightroom/Developpeur.lrplugin`, Lightroom
Classic 13.3 au moins), qui exécute ses commandes dans le catalogue (la liaison) et porte la
fenêtre Claude (« Développeur v » et la version du module dans sa barre de titre, « Développeur
v1.4 ») : une conversation avec Claude Code
(forfait claude.ai, jamais l'API) qui retouche et note par ce même connecteur, en une seule
disposition (la Conversation claire, à l'allure de la fenêtre B depuis la 1.3), une conversation
par photo depuis le correctif 1.3.6, avec les fenêtres Demande rapide, Suivi (les photos ouvertes et
le carnet de progrès en graphiques depuis le correctif 1.3.7), Publication et Consommation.

Les outils, les invites et les ressources `developpeur://` se lisent dans
`Sources/DeveloppeurKit/` (fichiers `Tools+*.swift`) ; les options de l'exécutable, dans
`Sources/MCPDeveloppeur/main.swift`. Le README décrit les fonctions du point de vue de l'utilisateur ; le protocole entre le
serveur et le module, les chantiers de la 1.3 et la fenêtre Claude (section Fenêtre Claude, dont
Fenêtre B) sont dans `docs/SPEC.md`.

Développeur 1.0 remplace MCP Lightroom 2.7 (et son surveillant de Camera Raw) et Claude pour
Lightroom 1.6.1, sans en reprendre de données. Leurs dépôts (`~/Developer/MCP-Lightroom`,
`~/Developer/Claude-pour-Lightroom`) se consultent en lecture seule : ne jamais y écrire.

Ce projet suit le standard commun des projets de Dany (`/standard-projet` le vérifie).

## Puces d'origine, avec leurs dates

- **Ne jamais retoucher de vraies photos pendant les tests** : `swift test` passe par
  `FakeLightroom` et un faux module TCP ; `scripts/tester-module.sh` par les Lightroom simulés de
  `Tests/Lua/Liaison/Simulation.lua` et `Tests/Lua/Fenetre/Simulation.lua`, avec `faux-claude.sh` à
  la place de Claude Code (ni Claude, ni quota, dossier personnel temporaire). Un essai dans
  Lightroom, ou la recette, se fait sur les photos de la collection « Développeur › Essais » (des
  copies virtuelles que Claude choisit et y range), ou sur une photo que Dany désigne ; l'essai se
  défait ensuite (`undo_last`, `revert_to_original` ou ⌘Z). Ranger une copie dans Essais **après**
  l'avoir remise à l'origine : `revert_to_original` défait aussi ce rangement (classement gardé dans
  la mémoire `Bibliotheque`) ; constaté le 29 octobre 2026, la copie n'était plus dans Essais et le
  TIFF de Fibo 2 a été empilé avec le vrai original.
- Ne jamais écrire dans les vrais fichiers de Claude ni dans les préférences de Lightroom depuis les
  tests : `ClaudeRegistration` reçoit des chemins temporaires, les raccourcis vont dans un fichier
  d'essai, le presse-papiers est un presse-papiers nommé. Ni lire le vrai jeton de la liaison ni le
  vrai écran : `LightroomBridge.fichierJeton` vaut nil par défaut, et `ToolHandler.lireEcran` (comme
  `Recette.lireEcran`) ne lit aucun écran par défaut ; les tests passent un fichier temporaire ou un
  écran fabriqué, et aucun n'envoie par `LightroomBridge.fromEnvironment()` ; seul
  `DEVELOPPEUR_ECRAN_REEL=1` fait lire l'écran du Mac à `swift test`.
- Claude Desktop ouvert garde `claude_desktop_config.json` en mémoire et le réécrit : une
  inscription faite pendant ce temps se perd (constaté le 20 octobre 2026 : `MCP-Developpeur` perdu,
  l'ancienne clé `lightroom` revenue). L'inscription se fait Claude Desktop fermé ; `install.sh` et
  `uninstall.sh` le signalent par `pgrep -xa Claude` (sans `-a`, pgrep ne voit pas Claude Desktop
  depuis une session de Claude Code qu'il a lancée). `--install` retire l'ancienne clé `lightroom`
  de MCP Lightroom (`ClaudeRegistration.ancienneCle`), `--status` la signale.
- Un seul connecteur : la clé `MCP-Developpeur` dans Claude Desktop et Claude Code
  (`ClaudeRegistration.serverKey`, égale à `ServerInfo.name` ; `title` « MCP-Développeur »), et le
  nom `developpeur` dans `connecteur.json` pour la fenêtre (`Session.SERVEUR`). Les fenêtres («
  Claude · liaison », « Claude · Publication », « Claude · Consommation », « Claude · Suivi », «
  Claude · Demande rapide »), les étapes « Claude · … », l'instantané « Avant Claude », l'ensemble
  de collections « Claude » et les copies virtuelles « Claude » gardent le nom Claude : c'est ce que
  Claude a fait. Seule la barre de titre de la fenêtre Claude dit « Développeur »
  (`Fenetre.afficher`, demandé par Dany le 20 octobre 2026), suivi de la version du module depuis
  ses retours du 25 octobre 2026 (« Développeur v1.4 » : `Fenetre.titreFenetre`, d'après
  `Composants.module()` ; « Développeur » seul si la version ne se lit pas) ; son menu (« Ouvrir la
  fenêtre Claude », ⌃⌥C, que `Raccourcis.lua` vise) et la documentation l'appellent toujours «
  fenêtre Claude ».
- `apply_settings` respecte le mode « Proposer d'abord » du module (refus sans `confirm = true`) ;
  ne pas contourner. La fenêtre Claude suit la clé `mode` des préférences du module, que seul le
  Gestionnaire de modules externes règle (les radios du Mode sont retirées au correctif 1.3.6), et
  la dit dans l'infobulle du voyant Lightroom.
- **Pour un photographe amateur** : Dany retouche ses propres photos (souvenirs, écran, partage,
  impression), sans client, vente ni concours ; Développeur l'aide à leur donner une allure
  professionnelle sans être pro. Rien d'orienté client, mariage ou concours (galeries, collections
  publiées, profils Client ou Concours), et plus de Photoshop : ni agrandissement génératif, ni
  crédits Firefly, ni ouverture dans Photoshop. `MCPServerTests` et `Version25Tests` vérifient que
  les consignes, les outils et les invites n'en parlent pas ; `NotationTests`, le standard de
  notation. La seule retouche générative permise est Fibo 2, en local, sur demande de Dany (`docs/regles/retouche-generative.md`) ; les taches de Claude restent `patchmatch`.
- Claude Desktop et chaque session de Claude Code gardent le serveur lancé à leur ouverture : après
  une installation, relancer Claude Desktop et ouvrir une nouvelle session Claude Code pour avoir
  les nouveaux outils ; un connecteur d'avant la 1.2 resté ouvert est refusé par le module 1.2
  (« Liaison fermée : cette commande ne porte pas le jeton… », qui dit de relancer). `/clear` vide
  la conversation mais ne relance pas le serveur. La fenêtre Claude lance le sien avec chaque
  processus Claude Code, fermé quand le module se recharge ou que Lightroom quitte.
- Chaque constat fait dans Lightroom (« Constaté dans Lightroom Classic » de `docs/SPEC.md`, section
  Fenêtre Claude comprise) a sa règle dans la simulation de sa suite (`Tests/Lua/Liaison` ou
  `Tests/Lua/Fenetre`) et un test qui échoue sans la correction, même quand il confirme le code (le
  radial inversé) ; et une étape de la recette quand c'est possible. Un constat de rendu (une
  image), que la simulation ne peut pas imiter (la linéarité de `CorrectionAmount`), le dit dans
  `docs/SPEC.md` et a son étape de recette.
- **Jamais l'API** : la fenêtre Claude passe par Claude Code et la connexion claude.ai. `relais.sh`
  retire de l'environnement les clés d'API et les autres fournisseurs (`ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, Bedrock, Vertex) ; ne jamais lire ni copier les
  jetons de connexion de Claude Code. Il pose `MAX_MCP_OUTPUT_TOKENS` (puce Noter une grande
  sélection).
