# Changements

## 1.0 — 2026-10-20

Première version de Développeur. Elle réunit dans un seul projet, et une seule installation, le
connecteur MCP-Développeur (le serveur MCP que lancent Claude Desktop et Claude Code) et le module
« Développeur » de Lightroom Classic (la liaison avec le connecteur et la fenêtre Claude). Elle
remplace MCP Lightroom 2.7 et Claude pour Lightroom 1.6.1, pour un photographe amateur qui veut des
photos d'allure professionnelle.

### Ajouté
- La fenêtre Claude dans Lightroom (Fichier › Module externe - Extras › Ouvrir la fenêtre Claude,
  ou ⌃⌥C) : une conversation avec Claude Code et votre forfait claude.ai, jamais une clé d'API ;
  six invites en raccourcis, un style et un modèle au choix, des photos jointes, et les
  propositions à accepter, refuser ou ajuster.
- Le connecteur, inscrit sous le nom `MCP-Developpeur` dans Claude Desktop et Claude Code : 33
  outils pour regarder et mesurer, retoucher, faire des retouches locales, trier et harmoniser une
  série, classer dans la Bibliothèque, exporter, et garder votre style ; 8 invites, dont `partage`
  (écran, web, Instagram, impression), qui remplace `livraison`.
- Publication : cinq profils (JPEG 5 Mpx, JPEG pleine qualité, Web, Instagram, Impression) et les
  vôtres, sans Claude ni quota.
- Consommation : les jetons de la semaine, un budget (alerte à 80 %, arrêt à 100 %) et le dernier
  relevé du forfait.
- La fenêtre de suivi de la liaison, les garde-fous du Gestionnaire de modules externes et le mode
  « Proposer d'abord ».
- `install.sh` installe le tout (Claude Desktop fermé : il signale un Claude Desktop ouvert, qui
  réécrirait sa configuration sans le connecteur) et retire l'inscription de l'ancien connecteur
  `lightroom` ; `uninstall.sh` le retire, et `uninstall.sh --tout` retire aussi vos conversations,
  votre guide de style, vos profils de publication, le registre de consommation et les journaux.
  Les fichiers vont dans `~/Library/Application Support/Developpeur/`, les journaux dans
  `~/Library/Logs/Developpeur/`.

### Corrigé par rapport à MCP Lightroom
- La première retouche d'une copie virtuelle faite d'une photo que Claude avait déjà touchée se
  défait de nouveau (undo_last) et entre au journal : seul « Retouchée par Claude » en restait.

### Retiré par rapport à MCP Lightroom et Claude pour Lightroom
- Photoshop : plus d'ouverture d'une photo dans Photoshop, et plus de surveillant de Camera Raw
  (`MCP Lightroom Surveillant.app`, ni sa permission d'Accessibilité).
- L'agrandissement génératif (`expand_photo`) et ses crédits Firefly.
- Les galeries : Claude ne crée ni ne suit plus de collection publiée ; plus de profils de
  publication Client et Concours.
- La reprise de données : rien n'est repris des anciens projets (conversations, registre de
  consommation, guide de style, réglages) ; Développeur part de zéro.
