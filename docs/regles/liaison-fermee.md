# Liaison fermée et ports

Sorti de `CLAUDE.md` le 31 octobre 2026 ; à lire quand on touche au jeton de la liaison
(`Liaison.preparerJeton`, `Liaison.garderFichierJeton`, `Liaison.recevoir`, `JetonLiaison`,
`LightroomBridge`) ou aux ports.
Les interdictions restent dans `CLAUDE.md`.

Texte d'origine des puces :

- Liaison fermée (1.2) : chaque ligne du serveur porte le `jeton` privé de la liaison, ping compris.
  Le module en tire un à chaque démarrage, avant d'ouvrir les prises (`Liaison.preparerJeton` : 32
  octets de `/dev/urandom`), le garde en mémoire et l'écrit d'un coup dans `liaison.jeton`
  (`~/Library/Application Support/Developpeur/`, droits 600 : fichier provisoire créé sous `umask
  077`, écrit par `io.open`, rangé par `mv`, relu), qu'il vérifie toutes les 5 s
  (`Liaison.garderFichierJeton`). Sans jeton, aucune prise ne s'ouvre : liaison en erreur, voyant
  rouge avec son aide. `Liaison.recevoir` vérifie le jeton avant `Commandes.executer`, donc avant la
  pause et « Proposer d'abord », sur toute sa longueur ; un refus répond `code: "jeton"` sans
  emporter l'événement de la photo active, et se note au journal une fois par 10 s et par genre.
  `depuisLightroom` est retiré des paramètres reçus du réseau : seuls les menus, la fenêtre de la
  liaison (« fenêtre de suivi » jusqu'au correctif 1.3.6) et la carte Note le posent, par appel
  direct (toute nouvelle voie interne reste un appel direct, jamais une ligne TCP). Le serveur relit
  le fichier à chaque connexion (`JetonLiaison.lire`), une fois de plus après un refus, ne le crée
  jamais et ne dit jamais sa valeur (`--status`, `get_status` et le diagnostic du Gestionnaire n'en
  disent que l'état) ; sans fichier, il n'envoie pas de jeton, et un module 1.1.1 accepte la ligne.
  La simulation de la liaison n'imite que les deux commandes du système du jeton (`LrTasks.execute`)
  et refuse toute autre. Constaté le 21 octobre 2026 par l'étape « liaison fermée (jeton privé) » de
  la recette : une commande sans jeton, ou avec un autre jeton, refusée ; restent à constater l'aléa
  lu et les droits 600 dans Lightroom, les refus par `nc` et `curl`, et un ancien serveur refusé
  (`docs/SPEC.md`, Liaison fermée).
- Ports fixes 54770 (commandes) et 54771 (réponses), sur 127.0.0.1 : `Liaison.lua` et
  `LightroomBridge` doivent rester d'accord (`DEVELOPPEUR_PORT` côté serveur pour essayer un autre
  port). Le serveur ouvre une connexion par commande : Claude Desktop, Claude Code et la fenêtre
  Claude se succèdent sur la même liaison, chacun avec le jeton du même fichier
  (`LightroomBridge.fromEnvironment`).
