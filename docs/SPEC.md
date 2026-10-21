# Cahier des charges — Développeur

## But

Permettre à Claude (Claude Desktop, Claude Code, ou la fenêtre Claude dans Lightroom) de
développer les photos d'un catalogue Lightroom Classic comme un retoucheur professionnel :
regarder la photo, poser un diagnostic, régler, vérifier le rendu, affiner. L'utilisateur est un
photographe amateur, dont les photos sont à lui seul : il veut des photos d'allure
professionnelle sans être un pro. Il garde la main : chaque retouche est une étape de
l'Historique, annulable, et il peut exiger son accord avant toute modification.

Les numéros de version cités (de 1.3 à 2.6, dans les constats et les titres de sections) sont
ceux du connecteur dont Développeur 1.0 reprend le code ; leur date les situe.

## Architecture

Deux pièces :

- le connecteur MCP-Développeur : `mcp-developpeur`, serveur MCP natif en Swift
  (`serverInfo.name` MCP-Developpeur, `title` « MCP-Développeur », bundle
  `com.danymenard.mcp-developpeur`), installé dans `~/Library/Application Support/Developpeur/`
  et inscrit sous la clé `MCP-Developpeur` dans Claude Desktop et Claude Code ; 34 outils et
  9 invites ;
- le module Lightroom « Développeur » (`Lightroom/Developpeur.lrplugin`, identifiant
  `com.danymenard.developpeur`, Lightroom Classic 13.3 au moins), qui porte la liaison avec le
  serveur (`Liaison.lua`), la fenêtre Claude (voir Fenêtre Claude), les fenêtres Publication et
  Consommation, le registre des notes proposées (`Notation.lua`, voir Notation) et la fenêtre de
  suivi de la liaison. Journaux : `~/Library/Logs/Developpeur/`
  (`module.log` pour la liaison, `conversation.log` pour la fenêtre).

```
Claude Desktop / Claude Code
        │  stdio, JSON-RPC (MCP)
        ▼
mcp-developpeur (Swift)  ──── TCP 127.0.0.1:54770 (commandes) ───▶  Développeur
                       ◀─── TCP 127.0.0.1:54771 (réponses) ─────  (module Lua, LrSocket)
```

Le module ne peut pas parler MCP lui-même (pas de stdio dans Lightroom) ; les prises `LrSocket`
sont à sens unique, d'où deux ports. Le module écoute ; le serveur ouvre une connexion par
commande (prise des réponses d'abord), envoie `ping`, puis la commande, et referme. `LrSocket` ne
sert qu'un client à la fois, et Claude Desktop comme chaque session de Claude Code lancent leur
propre serveur : des connexions courtes les laissent se succéder.

La prise des réponses ne lit jamais : elle ne voit pas le client partir et resterait accrochée à
une connexion morte (constaté sur Lightroom Classic 15.6). Quand la prise des commandes se ferme,
le module ferme donc la prise des réponses et en ouvre une nouvelle ; `reconnect()` sur une prise
d'envoi fige Lightroom (constat du module MIDI2LR). Pendant cette réouverture, le serveur retente
un refus de connexion pendant 3 s et une poignée de main ratée une fois.

La fenêtre Claude lance Claude Code (`claude -p`), qui lance son propre `mcp-developpeur` :
celui-ci se connecte à la liaison du module comme celui de Claude Desktop (voir Fenêtre Claude).

Menus du module (Fichier et Bibliothèque › Module externe - Extras, `Info.lua`) : Ouvrir la
fenêtre Claude (⌃⌥C), Publication…, Consommation…, Afficher la fenêtre de suivi, Revenir à
« Avant Claude », Créer une copie virtuelle pour Claude, Démarrer la liaison avec Claude, Arrêter
la liaison avec Claude (la 1.1 avait aussi Séance de notation…, `MenuNotation.lua`, retirée en
1.1.1). Les titres des autres fenêtres (« Claude · liaison », « Claude · Publication »,
« Claude · Consommation »), les étapes de l'Historique (« Claude · … »), l'ensemble de collections
« Claude » et les copies virtuelles « Claude » portent le nom de Claude : c'est ce que Claude a
fait. Seule la barre de titre de la fenêtre Claude dit « Développeur », depuis la 1.1.1 (demandé
par Dany le 20 octobre 2026) ; ses menus et la documentation l'appellent toujours « fenêtre
Claude ».

## Messages entre le serveur et le module

Une ligne JSON par message, en UTF-8.

```
→ {"id": 7, "command": "appliquer", "params": {…}}
← {"id": 7, "result": {…}}
← {"id": 7, "error": "message en français, montré tel quel à Claude"}
← {"id": 8, "result": {…}, "evenements": {"photo_active": true}}
```

`evenements` accompagne une réponse quand la photo active a changé dans Lightroom depuis la
précédente (`LrApplication.addActivePhotoChangeObserver`, dans le contexte de la liaison, qui
retire l'observateur quand elle s'arrête ; une seule fois par changement), avec la nouvelle photo
(`id`, `fichier`). Le module ne le signale que si la photo active n'est plus celle de la dernière
fois (`derniereActive`) : un aperçu ou un débruitage qui affiche une autre photo puis remet la vue
n'est pas un changement. Le serveur le signale aux clients abonnés à
`developpeur://photo/active/apercu` (`notifications/resources/updated`) ; sans abonné, il le dit une
fois avec le résultat d'outil suivant (« À savoir : la photo active a changé… », pas après
`show_photo`, qui l'a changée lui-même). Constaté en 2.3 (journal MCP de Claude Desktop,
`mcp-server-<clé du connecteur>.log`) : en quinze connexions, Claude Desktop a demandé `resources/list` trois
fois, jamais `resources/subscribe` ni `resources/read`. Le protocole reste question-réponse,
l'événement attend donc la réponse suivante.

Une commande à la fois : le serveur fait passer les appels d'outils un à un (voir Délai des appels
d'outils), car le module traite chaque commande dans sa propre tâche. Une réponse dont l'`id` ne
correspond pas (arrivée après un délai dépassé) est ignorée.

| Commande | Paramètres | Résultat |
| --- | --- | --- |
| `ping` | — | `{pong: true, version}` |
| `etat` | `sauvegarde?` | versions, catalogue, mode, pause, limites, photo active ; avec `sauvegarde`, la sauvegarde du catalogue demandée pour la fermeture suivante |
| `selection` | `limite` | `total`, `renvoyees`, `photos` (id, fichier, données de prise de vue, note, drapeau, libellé, pile, `active`) |
| `reglages` | `photo?`, `cles`, `details?`, `toutes?` | `reglages` (valeurs des clés demandées), `photo` (id, fichier, `copie_virtuelle`), `echelle_temperature`, `version_processus`, `profil`, `intensite_profil`, `appareil`, `recadrage` (angle, dimensions, orientation) ; avec `details` : `courbes_par_points`, `masques` (composants avec leur mode), `couleurs_ponctuelles`, `taches`, `yeux_rouges`, `filtres_calcules`, `amelioration` (photo affichée dans le module Développement seulement), `classement` (note, drapeau, libellé, titre, mots-clés) ; avec `toutes` : `tous`, tout ce que Lightroom range |
| `apercu` | `photo?`, `taille` (0 = pleine résolution), `cles`, `comparer?`, `point_af?` | `chemin` d'un JPEG sRGB rendu par Lightroom, plus ce que donne `reglages` ; avec `comparer` (`avantClaude` ou `etapePrecedente`), `chemin_avant` ; `a_savoir` si des masques IA n'étaient pas encore calculés (voir Aperçus et masques IA) ; avec `point_af` (1.1.1, `view_photo` sur l'aperçu entier ; après la 1.1.1, sur un zoom `region` aussi, jamais sur un avant/après), la photo décrite comme pour `vignettes` (`chemin_original`, `marque`, `geometrie`), `point_af_toujours` (préférence `pointMiseAuPoint`) et `evaluation` (`Notation.resume`) : voir Tri d'une séance › Point de mise au point |
| `appliquer` | `photos?` ou `selection?`, `reglages`, `booleens?`, `looks_traitement?`, `profil?`, `profil_marque?`, `profil_variantes?`, `profil_look?`, `recadrage?`, `recalages?`, `courbes?`, `couleurs_ponctuelles?`, `balance?`, `auto_ton?`, `preset?`, `plages`, `libelles`, `relatif`, `etape`, `raison?`, `confirme` | par photo : `changements` (`cle`, `avant`, `apres`) et `remarques` ; `a_recadrer` et `etape_ecrite` quand un cadre demandé reste à placer (voir Recadrage) |
| `recadrer` | `photos`, `recadrage`, `recalages`, `completer?`, `etape`, `raison?`, `confirme` | comme `appliquer` (changements du cadre seulement) |
| `masquer` | `photos?` ou `selection?`, `masques` (chacun avec ses `composants?` combinés et ses `couleurs_ponctuelles?` ; types `ia`, `lineaire`, `radial`, `luminance`, `couleur` avec ses `prelevements` et son `etendue`, `profondeur`, `pinceau`, `objet` avec ses `traits` ou son `rectangle`), `recalages?`, `etape`, `raison?`, `confirme` | comme `appliquer` |
| `ameliorer` | `photo?`, `ameliorations` (`nom` : `denoise`, `rawDetails` ou `superRes`, `actif`, `intensite?`), `libelles`, `etape`, `raison?`, `confirme` | comme `appliquer`, plus `amelioration` (état après le calcul) |
| `retoucher` | `photo?`, `taches`, `yeux`, `recalages?`, `etape`, `raison?`, `confirme` | comme `appliquer` |
| `geometrie` | `photo?`, `photos?` ou `selection?`, `rendre?`, `taille?` | `photos` : par photo, `active` (correction géométrique), `transformation` (Upright, perspective ou distorsion manuelle), `empreinte` ; avec `rendre`, `chemin_corrige` et `chemin_origine` (voir Recalage de la géométrie) |
| `copier` | `source`, `photos?` ou `selection?`, `cles`, `inclure`, `etape`, `raison?`, `confirme` | comme `appliquer`, sans la photo source |
| `essayer` | `action` (`appliquer`, `masquer`, `retoucher`), `photo?`, `taille`, `comparer?`, `instantane?`, et les paramètres de l'action | `chemin` (et `chemin_actuel`), `changements`, `remarques` ; avec `instantane`, l'état proposé est rangé en instantané « Claude · <nom> » avant le rendu (`instantane` dans la réponse) ; la photo est remise comme avant |
| `presets` | `filtre?`, `limite` | `total`, `presets` (dossier, nom, UUID) |
| `creerPreset` | `nom`, `photo?`, `cles`, `inclure` | `reglages` de la photo, dont le serveur fait un fichier XMP |
| `journal` | `photos?` ou `selection?` | par photo : `entrees` (date, étape, raison, changements ou note) |
| `diagnostic` | `modules?`, `methodes?`, `cles?`, `valeurs?` | fonctions offertes par le SDK de cette version de Lightroom : celles des modules, des méthodes cherchées par leur nom sur le catalogue, la photo active, le premier mot-clé, la première collection et le premier ensemble (sans les appeler), et le type des métadonnées brutes de la photo active ; avec `valeurs`, des valeurs lues sans rien écrire : jeu de libellés, filtre de la Bibliothèque et ses paramètres prédéfinis, original et aperçu dynamique de la photo active |
| `annuler` | `photos?` ou `selection?` | par photo : étape annulée et réglages remis |
| `revenir` | `photos?` ou `selection?` | par photo : réglages remis à l'état d'avant Claude |
| `metadonnees` | `photos?` ou `selection?`, `note?`, `drapeau?` (`retenue`, `rejetee`, `aucun`), `libelle?` (`rouge`… `violet`, `aucun`), `titre?`, `legende?`, `droits?`, `ajouter?`, `retirer?` (mots-clés, par nom ou chemin « A > B »), `preset_metadonnees?` (nom ou identifiant), `etape`, `raison?`, `confirme` | comme `appliquer` ; `mots_cles_crees` (chemins) quand il en a créé (voir Bibliothèque) |
| `motsCles` | `filtre?`, `limite` | `total`, `mots_cles` (chemin, nombre de photos) |
| `collections` | `action` (`lister`, `creer`, `ajouter`, `retirer`), `nom?`, `ensemble?`, `collection?` (id, nom ou « Ensemble > Nom »), `recherche?` (critères de `chercher`), `photos?` ou `selection?`, `etape`, `raison?`, `confirme` | `lister` : `collections` (id, nom, ensemble, dynamique, photos), `ensembles` ; sinon `collection`, et pour les photos ajoutées ou retirées, `resultats` comme `appliquer` |
| `chercher` | `texte?`, `mots_cles?`, `sans_mots_cles?`, `note_min?`, `note_max?`, `drapeau?`, `libelle?`, `appareil?`, `objectif?`, `iso_min?`, `iso_max?`, `format?`, `depuis_jours?`, `date_debut?`, `date_fin?`, `dossier?`, `sous_dossiers?`, `collection?`, `retouchee_par_claude?`, `copies_virtuelles?`, `tri?`, `mots_cles_details?`, `limite`, `decalage?` | `total`, `photos` (description détaillée), `remarques` |
| `copieVirtuelle` | `photos?` ou `selection?`, `nom?`, `afficher?`, `confirme` | `copies` (id, fichier, `original`), `a_savoir` |
| `montrer` | `photos?` ou `selection?`, `module?` (`bibliotheque`, `developpement`), `vue?` (`loupe`, `grille`, `comparer`, `ensemble`, `avant_apres`), `filtre?`, `filtre_preset?`, `remettre_filtre?`, `source_dossier?` ou `source_collection?` (sans photo : la source et le filtre seuls) | `photos`, `module`, `source_changee`, `vue`, `filtre`, `source`, `a_savoir` (voir Bibliothèque, et Ajouts de la 2.4 › Filtre de la Bibliothèque) |
| `vignettes` | `photos` (50 au plus), `taille` (minimum demandé, de 128 à 2048) | `taille`, `dossier`, `photos` : par photo, sa description détaillée, `vignette` (chemin d'un JPEG temporaire) ou `erreur`, `chemin_original`, `geometrie` (`largeur`, `hauteur`, `orientation`, `cadre` s'il est recadré) ; voir Tri d'une séance |
| `supprimer` | `photo?`, `reflets` (`actif`, `intensite?` de 1 à 100, `qualite?` : `preview`, `standard`, `best`) ou `poussiere` (`actif` = false : la retirer), `etape`, `raison?`, `confirme` | comme `appliquer`, plus `reflets` (état après le calcul : `reflets`, `intensite`) ; voir Suppression des reflets et Poussière du capteur |
| `exporter` | `photos`, `dossier` (sauf `reimporter = pile`), `sous_dossier?`, `reglages` (`format`, `qualite`, `espace`, `profondeur`, `hdr`, `compatibilite`, `sans_perte`, `poids_max_ko`, `filigrane`, `reimporter` (`catalogue`, `pile`), `position_pile`, `taille` `{type, valeur}`, `nettete` `{support, niveau}`, `metadonnees`, `sans_lieu`, `resolution`), `jetons?`, `texte_perso?`, `sequence?`, `suite?`, `confirme` | `dossier`, `format`, `fichiers` : par photo, `chemin`, `octets`, `depuis_apercu_dynamique`, `reimportee` (id), ou `erreur` ; voir Livraison |
| `fenetreExport` | `photos?` ou `selection?` | `ouverte`, `photos` : la fenêtre d'exportation de Lightroom, photos sélectionnées |
| `livraison` | — | `modeles_noms`, `presets_metadonnees` (nom, id), `services_publication` (id, nom, module ; `reglages` d'un service Disque dur, clés `LR_…`) |
| `choisirDossier` | `titre?`, `depart?`, `attente?` | `dossier`, ou `annule`, ou `en_attente` (la fenêtre attend l'utilisateur ; la commande suivante relit son choix) |
| `nomsFichiers` | `photos?` ou `selection?`, `modele` (nom), `texte_perso?`, `sequence?` | `modele`, `noms` (20 au plus : photo, `nom` sans l'extension, ou `erreur`) |
| `apercusDynamiques` | `photos?` ou `selection?`, `retirer?` | `crees`, `existants`, `echecs`, `sans_original`, `retires`, `absents`, `taille_mo` |
| `retirerReimportees` | `chemins` | `retires` : recette seulement ; fichiers que le module vient de réimporter (même session, 30 min) |
| `masques` | `photo?`, `action` (`lister`, `masquer`, `afficher`, `retirer`, `dupliquer`, `recalculer`, `affiner`, `retirer_vides`), `masque?`, `inverser?`, `nom?`, `contour?`, `decalage?`, `etape`, `raison?`, `confirme` | `lister` : `photo`, `masques` ; sinon `resultats` comme `appliquer`, et `masques` (la liste après l'écriture) ; voir Masques : pistes de la 2.1 |
| `progression` | `id`, `titre?`, `fait?`, `total?`, `message?`, `fin?` | `annulee` (croix de la barre de Lightroom), `fermee` à la fin |
| `variantes` | `photo?`, `action` (`lister`, `choisir`, `effacer`), `nom?`, `noms?`, `effacer_autres?`, `etape`, `raison?`, `confirme` | `lister` : `variantes` (nom, réglages touchés, date) ; `choisir` : `etape`, `instantane`, `changements`, `effaces` ; `effacer` : `effaces` ; voir Variantes |
| `notation` | `action` (`proposer`, `lire`) ; `proposer` : `propositions` (`photo`, `note` de 0 à 4, `drapeau` `aucun` ou `rejetee`, `criteres` `{impact, qualites, plancher, finition?}`, `plafond?`, `raison`, `a_verifier`), `passe?`, `poser?` ; `lire` : `photos?` | `proposer` : `propositions` (`photo`, `fichier`, `note_avant`, `drapeau_avant`, `etat`, toujours `a_verifier` depuis la 1.1.1), `refusees` (`photo`, `raison`) ; avec `poser`, `posees` (`photo`, `etat`, `note`, `drapeau`, `erreur`, `remarques`) et `erreur_pose?` ; `lire` : `propositions`, `perdues?`. Sans `poser`, rien n'est écrit dans le catalogue (voir Notation) |

Sans `photo`, `photos` ni `selection`, la commande vise la photo active. L'aperçu est rendu dans
un dossier temporaire propre à chaque demande ; le serveur lit le fichier, l'envoie à Claude en
base64 et efface le fichier et son dossier. L'aperçu fait 1344 px de grand côté par défaut (Claude
réduit toute image au-delà d'environ 1,15 mégapixel) ; au-delà de 600 Ko, le serveur le
recompresse, car Claude Desktop refuse les réponses d'outil d'environ 1 Mo et plus.

## Délai des appels d'outils

Constaté le 16 octobre 2026 (Claude Desktop, onglet Code avec Claude Code 2.1.299 ; Lightroom
Classic 15.6) : un `add_mask` avec `preview`, `compare`, `size` 1600 et quatre masques (IA ciel,
IA végétation, IA eau, un dégradé linéaire), sur un RAF de X-H2S avec Upright, la photo affichée
dans le module Développement, a échoué avec « Error: Request timed out » à 60,5 s. Ce matin-là,
deux `view_photo` (fenêtre « Mises à jour IA recommandées ») avaient échoué de même, à 60,5 et
62,4 s. Le module, lui, a fini : la photo était remise comme avant.

- L'onglet Code de l'application reçoit le connecteur de l'hôte Claude Desktop
  (`LocalMcpServerManager`, `claude_desktop_config.json`), comme le chat : le processus qui a
  servi les appels suivants est celui que Claude.app a lancé, pas celui de Claude Code. L'hôte
  appelle les outils sans options : délai par défaut du SDK MCP, 60 s, sans `onprogress` (pas de
  `progressToken` dans la requête) ni relance sur progression (relevé dans le code de Claude.app ;
  seul un réglage de déploiement géré, `mcp.toolTimeoutSec`, le change). Sur l'erreur, il marque
  la connexion comme perdue : à l'appel suivant, il ferme le serveur et en lance un autre (journal
  de Claude.app, 15:33:01), qui a perdu ses grilles de recalage.
- Claude Code en terminal (2.1.295) passe `onprogress`, donc un `progressToken`, avec un délai
  d'outil de 1e8 ms et une garde d'inactivité de 30 min (stdio) que chaque notification relance.

Mesuré sur la copie d'essai RAW (même aperçu, Upright actif, photo **non** affichée), avec
`DEVELOPPEUR_VERBOSE=1` : 8,9 à 11,6 s en tout dans la version optimisée (`geometrie` 0,2 s ;
les deux rendus du recalage à 2048 px, 2,3 s ; calcul de la grille, 0,3 s ; `essayer`, deux rendus
à 1600 px et le calcul de trois masques IA par l'exportation, 6,3 à 9,1 s), 21,8 s dans la version
de débogage (grille : 6 s). Sur la photo affichée, l'`attendreCalculsIA` du `view_photo` qui a
suivi l'application des mêmes masques a attendu ses 10 s en vain (`a_savoir`) : Lightroom n'avait
pas calculé les trois masques IA en 10 s. La part de chaque étape sur la photo affichée n'a pas
été mesurée (il faut y afficher une photo d'essai).

Constaté en 2.3 (18 octobre 2026, Claude Desktop 2.42304, onglet Code) : un `cull_photos` long par
le connecteur de Claude Desktop a reçu la réponse d'attente à 50 s, son rappel aux mêmes
arguments la progression (« 1 min 50 s ») ; Claude Desktop n'a ni coupé l'appel ni relancé le
serveur (même processus avant et après). Le code de Claude.app range un réglage `mcpToolTimeoutSec`
(60 à 3600 s), réservé aux déploiements gérés ; sans lui, le délai reste celui du SDK MCP. Mesurer
au-delà de 60 s demanderait de relancer Claude Desktop avec une autre limite
(`DEVELOPPEUR_LIMITE`) : la réponse d'attente reste à 50 s.

Le serveur fait donc passer les appels d'outils par une file (`FileOutils.swift`) : un seul à la
fois vers le module, dans l'ordre d'arrivée, sur un fil à part (le serveur continue de lire stdin :
`ping` répond pendant un rendu). Sans `progressToken` (Claude Desktop), un appel a 50 s
(`DEVELOPPEUR_LIMITE`) à partir de son arrivée :

- fini à temps, il répond normalement ;
- commencé mais pas fini, il répond d'attendre (« n'est pas fini après 50 s… rappeler avec
  exactement les mêmes arguments ») ; la commande continue, et son résultat est gardé 5 minutes
  pour le même appel répété (même outil, mêmes arguments), qui le reçoit dès qu'il est prêt, avec
  une ligne qui le dit, sans rien refaire ; une autre commande qui commence entre-temps l'efface ;
- pas encore commencé (il attendait la fin d'un autre), il n'est pas lancé du tout, et la réponse
  le dit : sinon la fin d'une proposition, qui remet la photo comme avant, pourrait effacer une
  retouche appliquée entre-temps.

Avec un `progressToken` (Claude Code), le serveur envoie `notifications/progress` toutes les 5 s
tant que l'appel attend, s'arrête avant la réponse, et attend la fin sans limite (les délais de
`LightroomBridge` restent).

Une longue série (`cull_photos`, `contact_sheet`) donne sa vraie progression (`ContexteAppel`) :
`progress` = photos faites, `total` = photos de la série, et un message (« tri des photos (25 sur
329) »), à chaque lot ; entre deux lots, le battement avance d'un centième au plus, sans atteindre
la photo suivante (la valeur doit croître à chaque notification). Sans jeton, la réponse d'attente
dit où en est la série (« où il en est : 125 sur 329 : tri des photos »). `notifications/cancelled`
(Échap dans Claude Code) arrête l'appel nommé par `requestId` entre deux lots : ce qui est commencé
dans Lightroom va jusqu'au bout, la suite ne part pas, et aucune réponse n'est envoyée (spécification
MCP) ; un appel pas encore commencé n'est pas lancé. Une annulation d'un appel déjà répondu est
ignorée.

## Consignes et invites

`ServerInfo.instructions` donne à Claude la méthode de travail ; les neuf invites de
`Prompts.swift` (`retouche_pro`, `harmoniser_serie`, `tri_seance`, `noter`, `portrait`,
`paysage`, `noir_et_blanc`, `nuit_iso_eleve`, `partage`) l'appliquent à un cas, `retouche_pro` et
`harmoniser_serie` pas à pas, `noter` passe par passe selon le standard de notation (voir
Notation). Depuis la 1.1.1, les consignes disent « noter : propose_ratings (standard
developpeur://notation ; apply = true s'il demande de noter ; 5 ★ : set_metadata, sur sa
demande) » (en 1.1 : « …, jamais 5 ★) »), et, au début, « Ce qu'il demande clairement, le faire ;
ne refuser que ce que les outils ne savent pas faire, et le dire. » (demandé par Dany le
20 octobre 2026). L'ordre suit l'aide d'Adobe
(`docs/aide-adobe-developpement.md`, § 1 et 2), corrigé par ce que le connecteur constate (profil
adaptatif, Upright et recadrage, ci-dessous) ; ce qu'il ne sait pas faire (§ 4) est proposé à
l'utilisateur, à faire à la main.

Claude Code ne garde que les 4096 premiers caractères des consignes d'un serveur (constaté le
16 octobre 2026 : celles de la 1.6.1, 5365 caractères, s'arrêtaient au milieu d'un mot, suivies de
« [truncated] »). Un test les garde sous cette limite (`ServerInfo.instructionsLimit`, 4096), un
autre 300 caractères en dessous (3 796), pour la consigne suivante : en 1.1.1, raccourcies pour y
tenir, elles font 3 793 caractères. Le détail propre à un outil va dans sa description, qui n'est
pas coupée.

## Fenêtre Claude

La fenêtre Claude du module (Fichier › Module externe - Extras › Ouvrir la fenêtre Claude,
⌃⌥C) : une conversation avec Claude, qui retouche les photos du catalogue par le connecteur
MCP-Développeur, sans quitter Lightroom. Sa barre de titre dit « Développeur » depuis la 1.1.1
(`Fenetre.afficher`, demandé par Dany le 20 octobre 2026 ; « Claude » avant) ; les autres fenêtres
du module gardent « Claude · … », et les menus comme la documentation l'appellent toujours
« fenêtre Claude ». Claude passe par Claude Code et le forfait claude.ai de l'utilisateur, jamais
par l'API. La fenêtre a une carte « Note » pour la photo active depuis la 1.1. La 1.1 et la 1.1.1
avaient trois dispositions au choix (Atelier, Conversation claire, Panneau) ; après la 1.1.1, il
n'en reste qu'une, la Conversation claire (demandé par Dany le 20 octobre 2026, voir
Disposition). La 1.1 avait aussi une fenêtre à part pour noter une sortie entière, la Séance de
notation : elle est retirée depuis la 1.1.1 (demandé par Dany le 20 octobre 2026), comme les
boutons Noter et À vérifier. Depuis, Claude note d'abord toute photo qu'il traite dans la fenêtre,
et sa note arrive « à vérifier » ; une demande à Claude (« note ces photos ») note une sélection
(voir Carte Note et Notation). Après la 1.1.1, l'aperçu de la photo active montre aussi le point
de mise au point d'un fichier Fujifilm, et, à l'ouverture, Claude prépare une proposition de
retouche sur une conversation vide (voir Disposition et Proposition préparée à l'ouverture). Ce
qui suit la 1.1.1 ira dans la 1.2 (en préparation). Captures : `docs/capture.png` (la fenêtre
Claude, en Conversation claire), `docs/publication.png`, `docs/consommation.png` et
`docs/suivi.png` (la fenêtre de suivi de la liaison) ; `docs/atelier.png` et `docs/panneau.png`,
les deux autres dispositions, sont retirées avec elles.

### Relais vers Claude Code

```
Lightroom Classic, module Développeur
 ├─ fenêtre Claude (Fenetre.lua, Moteur.lua, Session.lua)
 │     │ LrTasks.execute (/bin/sh relais.sh … &)
 │     ▼
 │   relais.sh ── tail -f entree.jsonl ──▶ claude -p (stream-json) ──▶ sortie.jsonl
 │                                            │ stdio (MCP)
 │                                            ▼
 │                                       mcp-developpeur (Swift)
 │                                            │ TCP 127.0.0.1:54770 / 54771
 └─ liaison (Liaison.lua) ◀───────────────────┘
```

Lightroom ne sait ni lancer un processus avec ses tuyaux, ni lui écrire, ni lire sa sortie au fil
de l'eau : `LrTasks.execute` lance une commande du shell et rend son code de sortie. D'où
`relais.sh`, lancé en arrière-plan, qui garde Claude Code ouvert pour une conversation :

- la fenêtre ajoute une ligne JSON par message à `entree.jsonl` (`io.open` en ajout) ;
  `tail -n +1 -f` la passe à Claude Code par un tuyau nommé ;
- Claude Code écrit ses événements dans `sortie.jsonl`, que le moteur relit toutes les 0,25 s
  pendant une demande (position gardée, lignes incomplètes mises de côté) ;
- `arreter` (fichier créé par la fenêtre) ferme Claude Code : fin de son entrée, puis arrêt s'il
  traîne 3 s ; `fin.code` donne son code de sortie, `erreurs.log` la fin de son journal ;
- relais.sh ferme aussi Claude Code quand Lightroom n'est plus là (pid du parent du shell lancé par
  `LrTasks.execute`, sinon `pgrep`).

Un dossier par lancement (`Sessions/<id>-<date>-<n>/`, date en secondes Unix) : un processus
remplacé (autre modèle, autre effort, autre conversation) n'écrit jamais dans les fichiers du
suivant. Au chargement du module (`Init.lua`), les dossiers d'un chargement précédent du module
sont fermés (`arreter`) ou effacés (`Session.menage`).

### Claude Code

```
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
       --mcp-config connecteur.json --strict-mcp-config --tools "" --allowedTools "mcp__developpeur__*"
       --permission-prompts none --disable-slash-commands --setting-sources local
       --model <fable|opus|sonnet|haiku> --append-system-prompt-file Sessions/<dossier>/consignes.md
       [--effort <low|medium|high|xhigh|max>] [--resume <session>]
```

Options vérifiées avec Claude Code 2.1.303 : seulement le connecteur, nommé `developpeur` dans
`connecteur.json` (`Session.SERVEUR` : ses outils sont `mcp__developpeur__*`,
`Conversation.PREFIXE_OUTILS`), par le chemin absolu de `mcp-developpeur` ; aucun outil intégré,
rien qui demande une permission, ni compétences ni réglages de l'utilisateur. relais.sh retire
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL` et les fournisseurs Bedrock et
Vertex de l'environnement : le forfait est toujours employé (constaté le 19 octobre 2026 :
`apiKeySource: none`, connecteur `connected`, 33 outils ; le 20 octobre, 34 avec la 1.1).
`--effort` (1.1.1) : Claude Code 2.1.303 l'annonce avec cinq niveaux (`low`, `medium`, `high`,
`xhigh`, `max`), et les accepte avec chacun des quatre modèles (constaté le 20 octobre 2026, note
de `Consignes.efforts`).

Modèle et effort (1.1.1) : Fable (« Fable · le plus capable »), Opus (par défaut, « Opus ·
retouche fine »), Sonnet, Haiku (`Consignes.modeles`) ; effort maximal (`max`, par défaut), très
élevé (`xhigh`), élevé (`high`), moyen (`medium`), faible (`low`), le même pour les quatre modèles
(`Consignes.efforts`). Ils se choisissent dans le Gestionnaire de modules externes (préférences
`modele` et `effort`, voir Préférences), et non plus dans la fenêtre (la 1.1 y avait le menu
Modèle, et pas d'effort). `Moteur.modeleEtEffort(options)` donne ceux d'une demande : ceux des
options, sinon ceux des préférences ; une valeur inconnue (préférences d'une autre version, faute
de frappe) retombe sur celle par défaut (`Chemins.defauts`). `Session:lancer` passe l'effort à
`relais.sh` en quatrième argument (après le dossier, le chemin de Claude Code et le modèle ; vide :
celui de Claude Code, sans `--effort`). `Moteur.changerModele` n'existe plus : rien ne relance
Claude Code au moment du choix.

`consignes.md` (`Consignes.texte`) ne dit que ce qui tient à la fenêtre (pour qui, mise en forme
en texte simple, ligne de contexte, style, titre, garde-fous) : la méthode de retouche reste celle
des consignes du connecteur. Depuis la 1.1.1, ses garde-fous commencent par « Ce que Dany demande
en mots clairs, fais-le » (ses demandes l'emportent sur ces consignes ; ne refuser que ce que les
outils ne savent pas faire, ou ce que bloquent les réglages du module, et le dire), et la puce
« Notes » dit : par `propose_ratings`, selon le standard que `read_standard` donne, avec la raison
critère par critère ; toute photo que Claude traite, il la note d'abord, avant d'y toucher
(`cull_photos` sur elle pour le plancher technique, `view_photo` avec `af_point = true` pour le
carré de la mise au point, puis `propose_ratings` sans `apply`), et sa note arrive « à vérifier »
dans la carte Note, que Dany accepte ou change (demandé par Dany le 20 octobre 2026) ; une photo
déjà évaluée (`view_photo` : `evaluation`) ne se renote pas, sauf s'il le demande ;
`apply = true` quand Dany demande que Claude note (« note ces photos », « pose les notes ») ;
jamais 5 ★ de lui-même, `set_metadata` si Dany en demande (en 1.1 : jamais `set_metadata` pour
une note sans demande, jamais 5 ★). Après la 1.1.1, une puce de plus, sous Notes : « Mise au
point montrée ou jugée : view_photo avec af_point = true, sur l'aperçu entier comme sur un zoom
(region) : le carré y est dessiné, s'il tombe dans la zone (point_af : dans_la_zone) » (voir Tri
d'une séance › Point de mise au point). Les consignes du connecteur (`ServerInfo`, pour Claude
Desktop) ne demandent pas de noter d'abord. Depuis la 1.1, `consignes.md` est écrit dans le
dossier de chaque session (`Session:lancer` ; huitième argument de `relais.sh` depuis la 1.1.1,
septième en 1.1), plus à la racine : Claude Code le lit un peu après son lancement en
arrière-plan, et un fichier commun pourrait être réécrit entre-temps. Son texte est
`Consignes.texte` (en 1.1, `Consignes.pour(c)` y ajoutait `Consignes.texteNotation` pour une
conversation de séance ; retirés en 1.1.1). Les boutons d'invites de la fenêtre
(`Consignes.invites` : Retouche pro, Portrait, Paysage, Noir et blanc, ISO élevé, Sports)
envoient une demande toute faite, d'après les invites du connecteur ; après la 1.1.1,
`Consignes.proposerOuverture` est celle que la fenêtre envoie d'elle-même à l'ouverture (voir
Proposition préparée à l'ouverture). Le bouton Noter de la 1.1
(`Consignes.noterPhoto`, et `Consignes.noterSelection` dans un premier état de la 1.1.1) est
retiré en 1.1.1 : la note se fait d'abord, d'elle-même (voir Carte Note).

Une conversation = une session Claude Code (`session_id` du message `init` et du `result`),
reprise par `--resume` au lancement suivant (inactivité, autre modèle, autre effort, autre
conversation, redémarrage de Lightroom). Le dossier de travail est `Atelier/` (vide, sans
CLAUDE.md). Si la session reprise n'existe plus (« No conversation found »), la conversation
repart d'une nouvelle session, et une note le dit.

Un seul processus Claude Code et une seule demande à la fois. `Moteur.envoyer(texte, options)`
(options : `modele`, `effort`, `jointes`, `style`) écrit dans la conversation ouverte : si le
processus ouvert est celui d'une autre conversation, d'un autre modèle ou d'un autre effort, il
est fermé, et la demande relance Claude Code en reprenant la session de la conversation. Un autre
modèle ou un autre effort choisi dans le Gestionnaire vaut donc pour la demande suivante.
`Moteur.courante` est la conversation ouverte dans la fenêtre Claude ; `Moteur.enCours`, celle de
la demande en cours. Pendant une demande, un refus dit « Claude travaille encore : attendez la
fin, ou cliquez Arrêter. » ; `Moteur.texteTravail` ajoute « dans une autre conversation » quand la
demande en cours n'est pas celle montrée. En 1.1, `options.conversation` et `options.contexte`
servaient à la Séance de notation : retirés en 1.1.1.

Messages écrits : `{"type":"user","message":{"role":"user","content":[images…, texte]}}` ; une
interruption : `{"type":"control_request","request_id":"interruption-N","request":{"subtype":"interrupt"}}`
(réponse `control_response`, puis un `result` « error_during_execution ») ; sans réponse après
10 s, le processus est fermé.

Le style du menu Style (`Consignes.styles`), sauf Standard (le choix par défaut, réglage
`styleChoisi`), ajoute après la ligne de contexte
« [Style demandé : <nom> — <définition>] » ; la consigne « Style » dit à Claude de l'appliquer par-
dessus sa méthode (« peau adoucie » : un masque de la peau, jamais toute la photo). Le nom du style
est gardé dans l'élément de la demande (`style`) et rappelé dans le fil.

Chaque demande commence par une ligne de contexte (`Lightroom.contexte` : `[Lightroom : photo
active <id> (<fichier>) ; sélection : n photos]`) ; tant que la conversation n'a pas de titre,
elle finit par le rappel du marqueur de titre (`[titre : …]`), que la fenêtre retire de
l'affichage. En 1.1, une séance de notation avait sa propre ligne (`[Lightroom : séance de
notation « <titre> », N photos ; passe n]`) : retirée avec elle.

L'appel de `propose_ratings` fait un élément `notation` du fil (`Conversation.notesDemandees`,
d'après l'entrée de l'outil, quand elle porte des `ratings` ; `pose` quand elle porte
`apply = true`), complété par la réponse du connecteur (`Conversation.notesLues`,
`Conversation.completerNotation` : `proposee`, `posee` quand `posees` donne la photo `acceptee` ou
`changee`, ou `refusee`, par photo ; une pose en échec garde « non posée : <raison> » ; une note
lue au-dessus de 4 est ramenée à 4). Ce n'est que pour le fil : le registre du module
(`Notation.lua`) reste la source de la carte Note. `Fil.lua` le montre en lignes de genres
existants (un genre de plus ajouterait une vue à chaque ligne) : un titre « Notes proposées ·
passe n · N photos » (« Notes non rangées » sur un refus du connecteur ; depuis la 1.1.1, avec
`apply`, « Notes à poser » pendant l'appel, puis « Notes posées » si au moins une photo l'est,
sinon « Notes non posées » : pause de la liaison, accord attendu, la raison sur chaque ligne
« non posée : … »), puis une ligne par photo (« ★★★☆☆ fichier · à vérifier · raison », « à
vérifier » quand Claude a passé `to_check`, « ★★☆☆☆ fichier · posée · raison », « ⚑ Rejeter… »),
`Fil.NOTES_MONTREES` (12) au plus, puis « … et N autres ».
`Stockage` écrit `notes` toujours en tableau, et relit un élément resté « enCours » comme
« erreur ». ★ ☆ ⚑ ont leur chasse dans `Metriques.lua`.

### Événements lus

`system/init` (session, serveurs MCP : une note si `developpeur` n'est pas `connected`),
`system/status`, `stream_event` (texte partiel), `assistant` (textes, appels d'outils), `user`
(résultats d'outils et leurs images base64), `result` (fin, interruption, erreur),
`rate_limit_event` (`unifiedWindows.five_hour` et `seven_day`), `control_response`. Les autres
sont ignorés (`Evenements.lua`).

### Contraintes du SDK de Lightroom pour la fenêtre

- `LrDialogs.presentFloatingDialog` : fenêtre non bloquante (SDK 5), `onShow` donne `toFront` et
  `close`, `selectionChangeObserver` signale les changements de sélection. Le contenu se construit
  une fois : on ne peut pas ajouter de vues à une fenêtre ouverte.
- Une vue masquée (`visible = false`) garde sa place dans la mise en page (doc du SDK) : seules
  des variantes superposées (`place = 'overlapping'`) de même taille peuvent alterner.
- `visible` lié ne masque qu'une vue simple (texte, bouton, image, menu, champ, case, liste,
  séparateur) : posé sur un conteneur (`row`, `column`, `view`, `group_box`, `tab_view`,
  `scrolled_view`), il reste sans effet et tout le contenu reste montré (constaté le 20 octobre
  2026, voir plus bas). La simulation de la fenêtre le refuse (« visible sur un conteneur : sans
  effet dans Lightroom (constaté) »). Toute condition de visibilité des pièces passe par
  `Fenetre.condition`, `egal`, `non` ou `si`, qui gardent leurs conditions (clé et test) pour que
  `Fenetre.et` les combine en une liaison à plusieurs clés (`LrView.bind{keys, operation}`,
  `LrBinding.kUnsupportedDirection` pour le sens de la vue vers la table).
- Pas de défilement par programme d'un `scrolled_view` ou d'une `simple_list`.

D'où le fil en grille de lignes fixes (`Fil.lua`) : chaque ligne superpose une variante par genre
(police, couleur) et une icône par état ; seul le texte et le genre changent. Les lignes sont
coupées à la largeur de la colonne d'après la chasse des caractères mesurée par AppKit dans les
polices données à Lightroom (Helvetica Neue 13, Helvetica Neue Bold 13, Menlo 11 :
`scripts/metriques.swift` → `Metriques.lua`), moins une marge de 10 points, avec troncature en fin
de ligne au cas où. Depuis la 1.1.1, une ponctuation haute (; : ! ? ») reste avec le mot d'avant,
et « avec celui d'après : `Fil.couper` les lie par une espace insécable, comptée comme une espace
et rendue ordinaire dans la ligne (une ligne de la carte Note commençait par « ; mais », vu sur la
capture). La grille montre la fin du fil ; ▲ ▼ Fin déplacent la fenêtre de lecture, qui
reste en place quand des lignes arrivent pendant qu'on lit plus haut. Les images ne peuvent pas
s'insérer dans la grille : elles s'affichent dans le cadre de l'aperçu (`f:picture`, réduction
sur fond 2B2B2B faite par `sips`, carrée, le cadre de la vue ne changeant pas de taille ;
`Images.vignette(dossier, nom, cote, hauteur)`, où `hauteur` servait au cadre 3:2 de l'Atelier,
retiré après la 1.1.1).

De même, depuis la 1.1.1, le texte de la carte Note (`notationTexte`) et celui de la Proposition
(`propositionTexte`) sont des `static_text` de hauteur fixe, montrés page par page : coupés en
lignes comme le fil (`Fenetre.lignesCarte` : `Fil.couper` dans la police `P.texte`, largeurs
`D.largeurNote` et `D.largeurProposition`, moins la marge du fil ; paragraphes et lignes vides
gardés), une page de `D.criteres + 3` lignes pour la carte Note et de `D.propLignes` lignes pour
la Proposition (`Fenetre.montrerPage(cle, texte)`, clés `note` et `proposition`). Deux petites
flèches ▲ ▼ (`Vues.fleches`, boutons `size = 'mini'`) à droite des boutons de la carte, poussées
au bord par un espace élastique (rangée à `fill_horizontal = 1`), font défiler d'une page moins
une ligne, la dernière ligne vue gardée (`Fenetre.defilerTexte(cle, sens)` ; propriétés
`noteMonte`, `noteDescend`, `propositionMonte`, `propositionDescend`) ; la dernière page est
pleine. Un nouveau texte revient à la première page.

Les onglets, Note (par défaut) et Proposition (`D.onglets`), sont une rangée de `radio_button`
(clé `onglet`, chacun avec son `checked_value`) au-dessus de variantes superposées de même
largeur (`place = 'overlapping'`), et non un `tab_view`, dont le comportement n'a pas été
constaté. Le Panneau avait les siens, Retoucher et Noter : retirés avec lui après la 1.1.1. Les
colonnes des variantes ne portent pas `visible` : leur contenu se crée par une fabrique masquable
(`Vues.masquable(f, F, condition)`, appelée par `variante` de `Dispositions.lua`), qui pose la
condition de l'onglet (`onglet` égal à sa valeur) sur chaque vue simple que les pièces créent, et
la combine avec un `visible` déjà posé (couleurs de la carte Note ; en 1.1.1, dans Retoucher du
Panneau, aussi pastilles des voyants, lignes du fil, états du bandeau) ; une boîte de groupe y
devient une colonne à titre gras (son cadre et son titre resteraient montrés). Une fabrique
masquable peut s'envelopper dans une autre, les conditions se combinent (en 1.1.1, dans
Retoucher du Panneau, les invites, le Style et leur bandeau portaient aussi `aProposition` faux,
la proposition et le sien `aProposition` vrai).
Conteneurs, espaces et écarts passent tels quels. Les colonnes des variantes restent donc là,
vides, l'une sur l'autre : la dernière (Proposition depuis la 1.1.1) couvre celle d'avant (Note),
et laisse passer les clics vers ses boutons (constaté en 1.1 pour Agrandir, alors dans l'onglet
Aperçu sous la colonne Note ; le reste à l'usage, point 3 plus bas). La fenêtre ne change
d'onglet d'elle-même qu'au passage de faux à vrai, une fois par arrivée
(`Fenetre.choisirOnglet`, `Fenetre.ongletAuto`) : vers Proposition quand une proposition arrive
(sauf celle préparée à l'ouverture, après la 1.1.1 : voir Proposition préparée à l'ouverture),
vers Note quand une note arrive pour la photo montrée (« à vérifier », comme toute proposition
depuis la 1.1.1, ou « proposée », d'avant ; pas quand une autre photo est choisie). Un clic sur
une ligne d'image la montre dans l'aperçu, sans changer d'onglet : l'aperçu est hors des onglets
depuis la 1.1.1 (en 1.1, ce clic la ramenait à l'onglet Aperçu).

- Champ de demande (`immediate = false`) : constaté dans Lightroom 15.6, Retour ne fait pas de saut
  de ligne ; il valide le champ (le texte passe à la table de propriétés, puis est tout sélectionné).
  Avec `immediate = true`, la frappe passe caractère par caractère mais Retour ne se voit pas du
  tout (ni `validate` ni observateur). Le clic d'un bouton valide aussi le champ, juste avant
  l'action du bouton. Un texte validé part donc après 0,3 s, sauf si un clic de bouton (tous passent
  par `Fenetre.bouton`, appelé par les pièces de `Vues.lua`), un choix dans la liste, le menu
  Style, un onglet ou la fermeture de la fenêtre l'annule ; Envoyer l'envoie lui-même, une seule
  fois. Depuis la 1.1.1, la fenêtre n'a plus de menu Modèle ni Disposition, et pas de menu Effort
  (le modèle et l'effort sont dans le Gestionnaire de modules externes) ; après la 1.1.1, ni menu
  des conversations (Atelier, Panneau), ni réouverture quand la disposition changeait. Une
  fenêtre fermée entre-temps ne l'envoie pas : l'envoi automatique compare la génération de la
  fenêtre (`Fenetre.generation`). Le champ est désactivé pendant que Claude travaille (il perd
  ainsi le focus et se vide).
- Toute table passée à Lightroom est neuve (une table relue par `Json.decode` porte une métatable,
  sur laquelle Lightroom bloque : constaté par la liaison, voir Profil).
- `LrTasks.execute` ne bloque que la tâche : base64, sips, `osascript`, `mcp-developpeur --version`
  et `claude auth status` passent par là, et après la 1.1.1 `mcp-developpeur --marquer-af` (voir
  Disposition), jamais par un calcul en Lua sur la tâche de l'interface.

### Voyants et liaison

Sous le titre de la conversation, trois voyants. Claude Code : `claude auth status`, lu à
l'ouverture de la fenêtre (forfait, autre connexion, non connecté, introuvable). Lightroom : la
liaison, qui est dans ce même module ; la fenêtre la lit directement (`Lightroom.liaison` :
`Liaison.actif`, `Liaison.erreur`), toutes les 2 s, sans commande du système ni connexion. Arrêtée
ou en erreur (ports tenus par un autre Lightroom ouvert, par exemple), le voyant passe au rouge et
l'aide du bandeau dit quoi faire ; un clic sur le voyant la démarre, ou la relance après une erreur
(`Lightroom.demarrerLiaison`). Le mode : un clic bascule « Proposer d'abord » et « Appliquer
directement » (`Lightroom.basculerMode`, clé `mode` des préférences, celle que lit la liaison).

### Disposition (1.1 ; une seule après la 1.1.1)

Après la 1.1.1, une seule disposition : la Conversation claire (`Dispositions.NOM`,
`conversation`), toujours en grande taille (demandé par Dany le 20 octobre 2026). La 1.1 et la
1.1.1 en avaient trois au choix (préférence `disposition`, `conversation` par défaut), retirées
avec ce choix : la préférence, le menu Disposition du Gestionnaire de modules externes (voir
Préférences), l'Atelier et le Panneau (décrits plus bas, comme historique). La 1.1 avait aussi
trois tailles (petite, moyenne par défaut et grande, préférence `taille`), retirées en 1.1.1 au
profit de la grande.

La Conversation claire, la mise en page de la 1.0 :

- à gauche, la colonne des conversations (`Vues.listeConversations`) : Nouvelle conversation, le
  champ Rechercher, la liste, puis Renommer… et Supprimer… ;
- au centre : le titre de la conversation et ✎ (la photo active à droite), les voyants en rangée,
  un séparateur, le fil, ▲ ▼ Fin (la position dans le fil, l'activité à droite), un espace
  élastique, un séparateur, les invites sur une seule rangée avec le menu Style au bout, le
  bandeau, puis 📎, 📋, le champ de demande (trois lignes) et Envoyer à sa droite ;
- à droite, depuis la 1.1.1 (demandé par Dany le 20 octobre 2026 : l'aperçu et la note
  ensemble), de haut en bas : les boutons radio Note (par défaut) et Proposition, à la place du
  titre « Ce que Claude voit » (retiré) ; l'aperçu ; ◀ légende ▶ ; Agrandir ; une ligne vide
  (`f:spacer` de 8 points) ; la carte Note ou le panneau Proposition (variantes superposées) ; un
  espace élastique ; Publication… et Consommation… ; un séparateur ; les versions. En 1.1, elle
  avait trois onglets (Aperçu, Proposition et Note), suivis de Publication, Consommation et du menu
  Disposition.

Les deux dispositions retirées après la 1.1.1, telles qu'elles étaient en 1.1.1 :

- **Atelier** (`atelier`) : la photo d'abord. Colonne de la photo : une barre (menu des
  conversations, Nouvelle, Supprimer…), l'aperçu dans un cadre 3:2 de 720 × 480, ◀ légende ▶
  Agrandir, puis la proposition ; colonne Note : la photo active, la carte Note, un espace
  élastique, Publication et Consommation, un séparateur et les versions en bas ; colonne de la
  conversation, étroite : titre, voyants en colonne, fil, ▲ ▼ Fin avec l'activité dessous,
  invites trois par rangée (le menu Style au bout de la dernière), bandeau, demande, puis Envoyer
  seul à droite (`Vues.envoi`).
- **Panneau** (`panneau`) : une fenêtre étroite et haute, à côté de Lightroom. En-tête : l'aperçu
  carré de 200, et à côté le menu des conversations, Nouvelle, ✎, Supprimer…, la photo active, sa
  note posée, la légende, ◀ ▶ Agrandir ; deux onglets, Retoucher (voyants en rangée, fil, ▲ ▼ Fin,
  invites trois par rangée avec le Style au bout, bandeau, demande, puis Envoyer seul à droite ;
  une proposition en attente prenait la place des invites, du Style et de leur bandeau, en
  variante superposée avec son propre bandeau, clé `aProposition`) et Noter (la carte Note
  entière) ; en bas un séparateur, Publication et Consommation, et les versions.

Depuis la 1.1.1, ni menu Modèle (la 1.1 l'avait à côté d'Envoyer), ni menu Effort, ni menu
Disposition dans la fenêtre (demandé par Dany le 20 octobre 2026 : un écran plus léger) : le
modèle et l'effort sont dans le Gestionnaire de modules externes (voir Préférences). Plus de bouton
Noter non plus (en 1.1, dans la barre de l'Atelier, en tête des invites de la Conversation claire
et dans la carte Note), ni de bouton Séance… : Claude note de lui-même (voir Carte Note). Le menu
Style (`Vues.style`) n'a plus d'étiquette « Style » : `Vues.invites` le met au bout de la rangée
d'invites (en 1.1, « Style » et son menu sur leur propre ligne, le bandeau à droite ; en 1.1.1,
au bout de la dernière des rangées de trois de l'Atelier et du Panneau). Le bandeau
(`Vues.bandeau`) a sa propre ligne, sous les invites (voir Bas de la fenêtre).

**Aperçu de la photo active.** L'aperçu montre la photo active à l'ouverture de la fenêtre, et
quand Dany choisit une autre photo (demandé le 20 octobre 2026) : `Fenetre.afficher` remet
`Fenetre.idActif` à nil et `Fenetre.voirActive` à vrai, puis `Fenetre.majPhoto` voit la photo
active (aussi quand la fenêtre, déjà ouverte, est rappelée par le menu ou ⌃⌥C, qui la remet
devant). La légende dit « Photo active · DSCF1595 ». Sa vignette se fait dans une tâche :
`Vignettes.demander` (le cache d'aperçus de Lightroom, `requestJpegThumbnail`, 1 024 points,
`Fenetre.TAILLE_PHOTO_ACTIVE`) l'écrit dans un dossier à elle sous
`Chemins.temporaire()/PhotoActive` (`Images.vignette` garde ses réductions par nom de fichier : un
dossier neuf évite une vignette d'avant une retouche), puis `Images.vignette` la réduit au cadre
de l'aperçu ; le dossier de la vignette d'avant s'efface ; Agrandir la montre en grand
(`Images.grande`). Une image nouvelle de la conversation montrée (Claude regarde, une photo
jointe : `Fenetre.nbImages` grandit) prend sa place ; ◀ depuis la photo active montre la dernière
image de la conversation, ▶ depuis la dernière revient à la photo active ; un clic sur une ligne
d'image du fil relit d'abord les images de la conversation, pour ne pas rebasculer.

Après la 1.1.1 (demandé par Dany le 20 octobre 2026), la vignette d'un fichier Fujifilm porte le
carré de mise au point, avant sa réduction : `Fenetre.marquerMiseAuPoint(id, source)` décrit la
photo (`Vignettes.decrireVignette` : `chemin_original`, `marque`, `geometrie`, dans une tâche) ;
pour la marque « FUJIFILM » ou un original `.RAF`, `Images.marquerMiseAuPoint(connecteur,
original, geometrie, source)` lance le connecteur en ligne de commande par `LrTasks.execute`
(chemin `cheminConnecteur` des préférences, sorties jetées) :

```
mcp-developpeur --marquer-af <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>
```

Le connecteur (`PointAF.marquer`) lit le point dans l'original, en temps borné
(`LecteurPointsAF`, 2 s), le passe dans l'image affichée et recadrée
(`GeometriePhoto.versApercu`), dessine le carré (`PreviewImages.marquerPoint` : vert, rouge si
l'appareil a signalé la mise au point manquée) et écrit la vignette marquée dans `<sortie.jpg>`
(la fenêtre la nomme `<nom>-af.jpg`, à côté de la vignette) ; il écrit alors sur sa sortie une
ligne JSON (`x`, `y`, `avertissement`) et finit avec le code 0. Sans point (pas un fichier
Fujifilm, point illisible ou hors du cadre, original qui ne s'ouvre pas à temps), il finit avec
le code 1 sans rien écrire ; avec de mauvais arguments, le code 2. La fenêtre garde alors la
vignette sans carré, sans le journaliser ; un connecteur absent n'est pas lancé. Pour une autre
marque, pas d'appel : l'original n'est pas ouvert (voir Tri d'une séance › Point de mise au
point). Agrandir montre la vignette marquée. Le carré se dessine en tout temps sur cet aperçu,
sans tenir compte de la case « Mise au point » (`pointMiseAuPoint`), qui ne vaut que pour
`view_photo`.

Dimensions (`Dispositions.TAILLES`, une seule table depuis le retrait des autres dispositions,
complétée par `Dispositions.dimensions()`, sans argument, qui rend une table neuve avec `nom`) :
liste 250, fil 900, droite 340, aperçu 320 (points) ; fil de 42 lignes (`lignes`), proposition 21
(`propLignes`), critères 12 (`criteres`). En 1.1.1, une table par disposition, complétée par
`Dispositions.dimensions(nom)`, qui retombait sur la Conversation claire pour une valeur
inconnue : Atelier, photo 740, aperçu 720 × 480, Note 300, conversation (`fil`) 440, menu 240,
fil de 38 lignes, proposition 9, critères 15 ; Panneau, contenu 460, aperçu 200, fil de 20
lignes, proposition 6, critères 20.

Proposition = lignes du panneau Proposition (`propLignes`) ; critères = `criteres`, d'où les
`D.criteres + 3` lignes du texte de la carte Note. Largeurs de ces textes : `D.largeurNote` et
`D.largeurProposition` (la colonne de droite moins 24). Ce sont les valeurs de la grande taille de
la 1.1, sauf le fil (40 lignes en 1.1), la proposition (22) et les critères (14). Le champ de
demande a `D.fil - 170` de large, Envoyer 110 ; le nombre de lignes du fil donne au centre la
hauteur de la colonne de droite (l'aperçu, puis la carte Note) ; pas encore mesuré dans
Lightroom.

Largeur de fenêtre calculée (pas encore mesurée dans Lightroom) : 1564 points (en 1.1.1, Atelier
environ 1554, Panneau 484). Hauteur estimée (17 points par ligne de fil) : environ 900 en 1.1,
avec 40 lignes, pas encore réestimée avec 42 (en 1.1.1, Atelier environ 1 030 points de contenu,
Panneau environ 1 020 avec 20 lignes, environ 1 050 avec la barre de titre, pour tenir sur un
écran de 1080 points ; avec 30 lignes, environ 1 190, qui ne tenait ni sur un portable ni sur un
écran de 1080).

Le code : `Fenetre.lua` garde l'état, ce qui remplit les propriétés liées (`rafraichir…`), les
actions, la boucle et l'ouverture ; `Vues.lua` les pièces (`Vues.grille`, `defilement`,
`voyants`, `bandeau`, `versions`, `titre`, `listeConversations`, `invites`, `style`, `fleches`,
`boutonEnvoyer`, `saisie`, `apercu`, `navigationApercu`, `agrandir`, `proposition`, `notation`,
`autresFenetres`, `onglets`, et la fabrique `masquable` des onglets), chacune liée aux propriétés
de la fenêtre, sans `require 'Fenetre'` ni couleur créée au chargement (couleurs, polices, `bind`,
`egal`, `bouton` et les actions arrivent par `F`) ; `Vues.boutonNoter`, `Vues.boutonSeance`,
`Vues.menuModele` et `Vues.disposition` sont retirés en 1.1.1, comme `D.invitesPetites` (invites
en petit de la petite taille). Après la 1.1.1, `Dispositions.lua` n'a plus que `NOM`, `TAILLES`,
`dimensions()`, `imageVide` et `construire` (l'assemblage de la Conversation claire) : `LISTE`,
`items`, `valider`, `DEFAUT`, `atelier` et `panneau` sont retirés. Dans `Vues.lua`, partent ce qui
ne servait qu'aux deux autres : `menuConversations`, `boutonsConversation`, `envoi`, les voyants
en colonne, les invites par rangées de trois (`D.invitesParRangee`), l'activité sous ▲ ▼
(`D.activiteDessous`), le cadre non carré de l'aperçu (`D.apercuHauteur`) et les boutons en petit
d'Agrandir et des autres fenêtres ; Envoyer est toujours à côté du champ (plus de
`D.envoiACote`). L'image « aucun aperçu » du cadre (`Dispositions.imageVide`) est `vide-320.png`,
seule dans le module, dessinée par `scripts/images-vides.swift`, qui n'en dessine plus qu'une ;
`vide-200.png` (Panneau) et `vide-720x480.png` (Atelier) sont retirées après la 1.1.1, comme en
1.1.1 celles des petite et moyenne tailles et `vide-300`, faite pour la fiche de la Séance de
notation. La liste ne montre pas les conversations des anciennes séances de notation
(`genre == 'notation'`), restées sur le disque, et `Moteur.ouvrir` les refuse (« elle ne s'ouvre
plus »). Le menu des conversations de l'Atelier et du Panneau (les 40 plus récentes,
`Fenetre.MAX_MENU`, sans en-têtes, la conversation montrée toujours dedans ; `Fenetre.elementsMenu`,
propriétés `menuConversations` et `conversationChoisie`) est retiré après la 1.1.1, avec eux.

**Réouverture, retirée après la 1.1.1.** Une fenêtre ouverte ne change pas de structure : en 1.1
et 1.1.1, une autre disposition la fermait et la rouvrait (en 1.1, par le menu Disposition de la
fenêtre, `Fenetre.changerDisposition` ; en 1.1.1, par le Gestionnaire de modules externes : toutes
les 2 s, la boucle, `Fenetre.periodique`, comparait la disposition des préférences à celle de la
fenêtre ouverte, `Fenetre.dispositionChangee`, puis lançait `Fenetre.rouvrir` une seule fois,
`Fenetre.aRouvrir` ; le texte du champ, gardé dans `Fenetre.brouillon`, revenait sans partir). Avec
une seule disposition, `Fenetre.rouvrir`, `dispositionChangee`, `aRouvrir`, `brouillon` et
`Fenetre.disposition` sont retirés ; `Fenetre.periodique` ne relit plus que les voyants et la photo
active. Chaque ouverture garde sa génération (`Fenetre.generation`) : `Fenetre.boucle(generation)`
s'arrête dès qu'une autre fenêtre est ouverte, il n'en tourne jamais deux, et l'envoi automatique
d'une fenêtre fermée ne part pas. « Ouvrir la fenêtre Claude » (ou ⌃⌥C) sur une fenêtre ouverte la
met devant, remontre la photo active et, sur une conversation vide, fait préparer une proposition
(voir Proposition préparée à l'ouverture). Le cadre enregistré (`Fenetre.cadre()`, sans argument :
`DeveloppeurClaude-conversation-grande-<Fenetre.FORME>`, `FORME` à 1) porte le nom qu'avait celui
de la Conversation claire en 1.1.1 : le cadre déjà enregistré sert encore (en 1.1.1,
`Fenetre.cadre(disposition)` : `DeveloppeurClaude-<disposition>-grande-<FORME>` ; en 1.1,
`DeveloppeurClaude-<disposition>-<taille>-<FORME>`).

### Proposition préparée à l'ouverture (après la 1.1.1)

À l'ouverture de la fenêtre, et quand le menu Ouvrir la fenêtre Claude ou ⌃⌥C la rappelle, Claude
prépare une proposition de retouche de la photo active (demandé par Dany le 20 octobre 2026) :
`Fenetre.proposerAOuverture`, appelée après `Fenetre.majPhoto` (à l'ouverture, juste avant que
la fenêtre s'affiche ; dans une tâche quand elle est rappelée), envoie
`Consignes.proposerOuverture` (« Prépare une proposition de retouche de la photo active, rendu
naturel : note-la d'abord si elle n'est pas encore évaluée, puis montre ce que tu changerais avec
preview_settings, sans rien appliquer. J'accepterai, refuserai ou ajusterai dans l'onglet
Proposition. ») par `Fenetre.envoyer`, comme une demande de Dany (style et photos jointes,
modèle et effort des préférences). Elle ne le fait que si la fenêtre a une photo active, que
Claude ne travaille pas, que la préférence `propositionAOuverture` est cochée (voir Préférences),
et que la conversation montrée est vide (ou qu'il n'y en a pas) : une conversation qui a déjà des
éléments ne reçoit rien. Une autre photo choisie fenêtre fermée
commence une nouvelle conversation à la réouverture (`Fenetre.majPhoto`, voir Nouvelle
conversation par photo), qui reçoit donc la demande ; une autre photo choisie fenêtre ouverte,
quand elle commence une conversation, la laisse vide jusqu'au rappel suivant de la fenêtre.

La proposition qui arrive attend dans l'onglet Proposition, sans y basculer : tant que
`Fenetre.propositionAuto` est vrai (posé après l'envoi), `Fenetre.rafraichirProposition` ne change
pas d'onglet, et la carte Note reste devant. La demande suivante de Dany (`Fenetre.envoyer`)
l'efface : les propositions suivantes se montrent de nouveau d'elles-mêmes. La note que Claude
propose d'abord (voir Carte Note) fait encore passer à l'onglet Note, comme toute note arrivée
pour la photo montrée (`Fenetre.rafraichirNotation`).

### Carte Note (1.1, revue en 1.1.1)

`Vues.notation` : un `group_box` « Note » pour la photo active, dans l'onglet Note, sous l'aperçu
(dans un onglet, une colonne à titre gras, par `Vues.masquable`) ; en 1.1 et 1.1.1, aussi dans la
colonne Note de l'Atelier et l'onglet Noter du Panneau, retirés après la 1.1.1. Il montre :

- le nom de la photo (`notationNom`) et sa note posée (`notationPosee`,
  `Fenetre.texteNotePosee` : « Note posée : ★★☆☆☆ · rejetée », « aucune, pas encore jugée »),
  lue par `Lightroom.photos()` (`rating` et `pickStatus` de la photo active) ;
- la note que Claude propose (`Notation.proposition(id)`, dans une tâche) : « Claude propose :
  ★★★☆☆ » ou « rejeter », en couleur selon l'état (rouge à vérifier, vert acceptée ou changée, gris
  écartée, orange « proposée », d'avant la 1.1.1 : quatre variantes superposées) ; l'état et la
  passe (« à vérifier · passe 2 », « changée : ★★★★★ ») ;
- depuis la 1.1.1, un seul texte (`notationTexte`, `Fenetre.texteNote`, à la place de
  `notationCriteres` et `notationRaison`) : les critères du plus lourd au plus léger (Impact,
  Qualités, Plancher technique, Finition), « Plafond mesuré : n ★ », une ligne vide, puis la
  raison ; montré page par page, ▲ ▼ à droite des boutons (voir Contraintes du SDK). Sans
  proposition : « Aucune note proposée » et l'aide (`Fenetre.AIDE_NOTATION`) : Claude note d'abord
  chaque photo qu'il traite, selon le standard, critère par critère ; sa note arrive à vérifier,
  vous l'acceptez ou la changez ; 5 ★ reste à vous seul.

Boutons (Accepter et Changer… passent par `F.enTache` : ils lisent le registre et le catalogue,
ou ouvrent une fenêtre modale) :

- **Accepter** (`Fenetre.accepterNote`) : la proposition telle quelle
  (`Notation.poser{ {photo = id} }` par `Fenetre.poserNote`) ; actif pour une proposition « à
  vérifier » (ou « proposée », d'avant la 1.1.1) ;
- **Changer…** (`Fenetre.changerNote`) : fenêtre modale « Changer la note », de 0 à 5 ★
  (l'utilisateur peut poser 5 ★, Claude jamais) et le drapeau (inchangé, sans drapeau, Retenue,
  Rejetée) ; actif dès qu'une photo est active.

Depuis la 1.1.1 (demandé par Dany le 20 octobre 2026 : ne garder qu'Accepter et Changer…), plus
de bouton Noter, ou Évaluer (`Fenetre.noter`, `Consignes.noterPhoto`, et
`Consignes.noterSelection` d'un premier état de la 1.1.1), ni À vérifier (`Fenetre.verifierNote`,
qui passait la proposition à vérifier par `Notation.decider`), ni Séance… (`Fenetre.seance`,
1.1). À la place, toute photo que Claude traite dans la fenêtre, il la note d'abord, avant d'y
toucher (consignes de la fenêtre, puce Notes : `cull_photos` sur elle, `view_photo` avec
`af_point = true`, puis `propose_ratings` sans `apply`) ; toute proposition arrive « à vérifier »
(voir Le registre), et Dany l'accepte ou la change. Une photo déjà évaluée ne se renote pas, sauf
si Dany le demande : `view_photo` donne son évaluation (`evaluation`, gardée dans `notation.json` ;
voir Tri d'une séance › Point de mise au point). Quand Dany écrit à Claude « note ces photos » ou
« pose les notes », Claude appelle `propose_ratings` avec `apply = true` (consignes de la fenêtre
et du connecteur) : les notes sont aussi posées dans le catalogue (voir Notation), et la carte
montre la proposition acceptée. En 1.1.1, l'onglet « Noter » du Panneau était la carte Note ;
il est retiré avec le Panneau.

Accepter et Changer… sont désactivés pendant que Claude travaille (`Moteur.travaille`) ou qu'une
écriture de la fenêtre est en cours (`Fenetre.noteEnCours`), et `Fenetre.poserNote` le revérifie :
ces écritures ne passent pas par la file du connecteur, et une commande de Claude peut écrire au
même moment. La fenêtre s'abonne au registre (`Notation.abonner('fenetre', …)`, retiré par
`Fenetre.desabonner`) et compare aussi `Notation.version` à chaque tour de sa boucle. Quand elle
relit la photo active (`Fenetre.majPhoto`, toutes les 2 s et après une écriture), elle recale le
registre sur sa note et son drapeau (`Notation.recaler`, avec la version lue avant) : une note
acceptée ou changée puis annulée (undo_last, ⌘Z) rend la proposition de nouveau « à vérifier ».

### Séance de notation (1.1, retirée en 1.1.1)

La 1.1 avait une fenêtre à part pour noter une sortie entière, passe par passe (« Claude · Séance
de notation », `FenetreNotation.lua`, cadre `DeveloppeurNotation`, ouverte par le menu Séance de
notation…, par Séance… ou par Noter avec plusieurs photos) : une planche de 12 vignettes, une
fiche, Tout accepter, sa propre conversation de genre `notation`, ses consignes
(`Consignes.texteNotation`) et ses passes (`Consignes.passes`). Elle est retirée en 1.1.1 (demandé
par Dany le 20 octobre 2026), avec `MenuNotation.lua`, les boutons Séance…, `Consignes.pour`,
`Moteur.nouvelleSeance`, `Conversation.nouvelleSeance`, les séances du registre, l'action
`seance` de la commande `notation`, les paramètres `session` et `read_session` de
`propose_ratings`, `essais-seance.lua` et `docs/seance.png` (`Vignettes.demander`, qui lui
donnait ses vignettes, reste : il sert à l'aperçu de la photo active). Les conversations des
anciennes séances (genre `notation`) restent sur le disque, absentes de la liste (et du menu des
conversations, retiré après la 1.1.1), et ne s'ouvrent plus (`Moteur.ouvrir` les refuse). Ce qui
a été constaté sur elle reste plus bas, comme historique.

### Nouvelle conversation par photo (1.1.1)

Quand l'utilisateur choisit une autre photo active ou une autre sélection, la fenêtre commence une
nouvelle conversation (`Fenetre.suivreSelection`, demandé par Dany le 20 octobre 2026). Elle est
appelée par `Fenetre.majPhoto`, toutes les 2 s (`Fenetre.periodique`) et à chaque changement de
sélection que signale `selectionChangeObserver`. La clé de la sélection (`info.cle`, faite par
`Lightroom.photos()`) réunit l'identifiant de la photo active, le nombre de photos sélectionnées et
les identifiants des 500 premières. Chaque demande envoyée pose la clé lue juste avant l'envoi
sur la conversation (`c.cle`, par `Fenetre.envoyer`), et la note comme vue. La fenêtre garde la
dernière clé vue et l'heure où elle l'a vue (`Fenetre.voirSelection` : `Fenetre.cleVue`,
`Fenetre.cleVueLe`). Une clé différente de la précédente commence une nouvelle conversation
(`Fenetre.nouvelle`, « Autre photo choisie : nouvelle conversation » au journal) quand :

- Claude n'a pas travaillé depuis que la clé précédente a été vue : il ne travaille pas
  (`Moteur.travaille`), et la fin de son dernier travail (`Moteur.finTravail`, datée par le moteur,
  fenêtre ouverte ou fermée, à la fin d'une demande ou du processus) précède d'au moins 4 s
  l'heure où la clé précédente a été vue (`Fenetre.DELAI_APRES_TRAVAIL`). Sinon, la nouvelle clé
  devient celle de la conversation (`c.cle`), sans en commencer une autre : une sélection changée
  pendant le travail de Claude, ou jusqu'à 4 s après, peut être la sienne (`show_photo`, un tri) ;
- la préférence `nouvelleParPhoto` est cochée (case « Autre photo » du Gestionnaire de modules
  externes, cochée par défaut) ;
- la conversation montrée a déjà des éléments (une conversation vide n'est pas remplacée) et
  parlait d'autres photos (sa clé n'est pas la nouvelle).

`Fenetre.cleVue` et `Fenetre.cleVueLe` restent d'une ouverture de la fenêtre à l'autre (pas d'un
chargement du module à l'autre) : une photo choisie fenêtre fermée compte aussi, à la réouverture
(après la 1.1.1, la nouvelle conversation, vide, reçoit alors la proposition préparée à
l'ouverture), et une fenêtre fermée pendant que Claude travaillait retrouve sa conversation à la
réouverture (la clé qu'elle avait vue date d'avant la fin de son travail). Un premier état de la
1.1.1 notait la fin du travail dans la boucle de la fenêtre (`Fenetre.finTravail`,
`Fenetre.travaillait`), donc fenêtre ouverte seulement : retirés. Revenir aux photos d'une
ancienne conversation ne la rouvre pas.

### Fichiers

```
~/Library/Application Support/Developpeur/
    mcp-developpeur                         le connecteur (installé par install.sh)
    Conversations/<id>/conversation.json    le fil (format « developpeur/1 », dates Unix), celles
                                            des anciennes séances de notation comprises (genre
                                            « notation », qui ne s'ouvrent plus)
    Conversations/<id>/image-*              aperçus de Claude ; jointe-*.jpg : photos jointes
    Conversations/<id>/.vignettes/          réductions pour la fenêtre
    Sessions/<id>-<date>-<n>/               échanges avec un processus Claude Code, et ses
                                            consignes (consignes.md, écrit à son lancement)
    Atelier/                                dossier de travail de Claude Code (vide)
    Temporaire/                             fichiers de passage (Collees/, sorties de commandes,
                                            PhotoActive/ : vignette de la photo active, et après
                                            la 1.1.1 sa copie marquée <nom>-af.jpg ; en 1.1,
                                            Notation/<séance>/ : vignettes de la séance)
    connecteur.json                         écrit à chaque lancement de Claude Code
    consommation.json, publication.json     jetons comptés, profils de publication de l'utilisateur
    notation.json                           notes proposées par Claude (registre, format 2, propre
                                            au catalogue ouvert ; voir Notation)
    guide-de-style.md                       guide de style (remember_style)
~/Library/Logs/Developpeur/module.log         journal de la liaison
~/Library/Logs/Developpeur/conversation.log   journal de la fenêtre
```

### Préférences

Une seule table, les préférences du module (`LrPrefs`, lues par `Preferences.lire`) : la liaison
y a ses réglages (`Preferences.defauts` : `demarrerAuLancement`, `mode`, `instantane`, limites,
garde-fous, `accordDansLightroom`, `retourVisuel`, et depuis la 1.1.1 `pointMiseAuPoint`, faux
par défaut : le point de mise au point dessiné sur chaque aperçu de `view_photo`, pas seulement
pour noter, voir Tri d'une séance › Point de mise au point), et `Chemins.prefs` y ajoute ceux de
la fenêtre (`Chemins.defauts` : `modele` — `fable`, `opus` par défaut, `sonnet`, `haiku` —,
`effort` — `max` par défaut, `xhigh`, `high`, `medium`, `low`, le même pour les quatre modèles,
depuis la 1.1.1 —, `nouvelleParPhoto` — vrai par défaut, depuis la 1.1.1, voir Nouvelle
conversation par photo —, `propositionAOuverture` — vrai par défaut, après la 1.1.1, voir
Proposition préparée à l'ouverture —, `styleChoisi`, `inactivite` en minutes), puis
`cheminClaude` et `cheminConnecteur` (par défaut, le premier Claude Code trouvé et
`~/Library/Application Support/Developpeur/mcp-developpeur`) ; la fenêtre Publication y garde
`dossierPublication` et `profilPublication`. Aucune clé ne sert aux deux. La clé `taille`
(petite, moyenne par défaut, grande) est retirée en 1.1.1 : une seule taille ; la clé
`disposition` (`atelier`, `conversation` par défaut, `panneau`, depuis la 1.1) l'est après la
1.1.1 : une seule disposition (voir Disposition). Le mode « Proposer d'abord » est la clé `mode`
de la liaison, que la fenêtre montre et bascule. Tout se règle dans Fichier › Gestionnaire de
modules externes › Développeur (sections Liaison avec Claude et Fenêtre Claude,
`PluginInfoProvider.lua`). Depuis la 1.1.1, la section Liaison a la case « Mise au point »
(« Montrer le carré de mise au point (Fujifilm) sur chaque aperçu »), et la section Fenêtre Claude
les menus Modèle (« pour la demande suivante ») et Effort (« le même pour les quatre modèles »)
et la case « Autre photo » (« Nouvelle conversation pour une autre photo ou sélection ») ; le
menu Taille de la fenêtre est retiré. Après la 1.1.1, le menu Disposition (« la fenêtre ouverte
se rouvre »), qui suivait le menu Effort, est retiré, et la case « À l'ouverture » (« Claude
prépare une proposition de retouche (rien n'est appliqué) ») suit « Autre photo ». Le modèle et
l'effort ne se choisissent plus que là (en 1.1, le modèle ne se choisissait que dans la fenêtre,
et la disposition aussi par son menu). Un autre modèle ou un autre effort vaut pour la demande
suivante (voir Claude Code). Le diagnostic du Gestionnaire donne `pointMiseAuPoint` (« point de
mise au point en tout temps ») avec les réglages de la liaison, et le modèle, l'effort,
`nouvelleParPhoto` et, après la 1.1.1, `propositionAOuverture` (« proposition à l'ouverture »)
avec ceux de la fenêtre (la disposition, qu'il donnait en 1.1.1, n'y est plus).

### Coller une image

Le SDK ne lit pas le presse-papiers, et ⌘V dans un champ n'y colle que du texte. Le bouton 📋
lance `presse-papiers.js` (JavaScript pour Automation, `osascript -l JavaScript`) : les fichiers
d'image copiés dans le Finder (leurs chemins), sinon une image (PNG, TIFF, JPEG, HEIC) écrite dans
`Temporaire/Collees/`. L'image est ensuite jointe comme une photo du disque (réduite à 1568 px,
JPEG). Le script lit seulement ; les essais passent par un presse-papiers nommé, jamais le vrai.

### Publication

Fenêtre à part (`FenetrePublication.lua`, « Claude · Publication »), sans Claude ni quota :
`LrExportSession` (`Publication.lua`) avec les identifiants de réglages de la livraison
(`Livraison.lua`, voir Livraison) : `LR_collisionHandling = 'rename'`, jamais d'écrasement ; taille
en mégapixels, grand ou petit côté ; `LR_jpeg_limitSize` pour un poids maximal ; filigrane
`<simpleCopyrightWatermark>` ; `LR_embeddedMetadataOption` ; `LR_removeLocationMetadata`. Profils :
JPEG 5 Mpx, JPEG pleine qualité, Web, Instagram, Impression (`Publication.STANDARDS`), et ceux de
l'utilisateur dans `publication.json` ; la liste se construit à l'ouverture (la fenêtre se rouvre
après un ajout). Photos : la photo active, la sélection ou une collection. Plusieurs profils : une
exportation par profil, chacune dans un sous-dossier à son nom. Les réglages IA sont calculés avant
le rendu (`photo:updateAISettings`). Une photo publiée perd le champ `apercuSeulement` (voir Ajouts
de la 2.4, Photos exportées), en une écriture privée, hors de Édition › Annuler. Le modèle de
noms est lu dans son fichier `.lrtemplate` (dossier Filename Templates de Lightroom) et rendu en
jetons (`LR_tokens`) ; les noms se prévoient par `photo:getNameViaPreset`. Poids estimé
(`Publication.poidsEstime`) : JPEG environ 0,25 octet par pixel à 80, 0,55 à 100, d'après les
dimensions recadrées des photos (la moyenne des 200 premières au-delà).

### Consommation

`consommation.json` : une entrée par demande terminée (date, modèle, `usage` du `result`, début de
la demande), trois mois gardés ; jetons comptés = entrée + sortie + écriture du cache + lecture du
cache / 10. Semaine du forfait : sept jours avant la reprise donnée par Claude Code, sinon lundi.
Budget (2 M par défaut) : alerte à 80 %, refus des demandes à 100 %. Les barres sont des caractères
(Menlo : fond « ░ », part pleine « █ » superposée). Fenêtre « Claude · Consommation »
(`FenetreConsommation.lua`).

### Versions

En bas de la colonne de droite (en 1.1 et 1.1.1, aussi de la colonne Note de l'Atelier et de la
fenêtre du Panneau, retirés), deux lignes (`Composants.lua`, `Vues.versions`), lues à
l'ouverture de la fenêtre : « Développeur », ce module (`VERSION` de son `Info.lua`), et
« MCP-Développeur », le connecteur (`mcp-developpeur --version`, cinq secondes au plus). Les deux
viennent de la même installation, au même numéro : si elles diffèrent, la plus ancienne passe en
orange « à mettre à jour » (réinstaller Développeur) ; un connecteur absent devient
« MCP-Développeur · introuvable ».

### Bas de la fenêtre

Dans la Conversation claire (la disposition de la 1.0, seule après la 1.1.1), les trois
colonnes finissent sur la même ligne : Renommer et Supprimer à gauche, le champ de demande et
Envoyer au centre, la ligne de MCP-Développeur à droite. Les colonnes ont `fill_vertical = 1` ; à
droite, une `f:spacer` élastique, sous la carte Note ou la proposition, pousse en bas Publication
et Consommation, le séparateur et les versions ; au centre, une autre (après ▲ ▼ Fin) ne grandit
que si une autre colonne est plus haute. La liste des conversations a une hauteur fixe
(`D.hauteurListe` = lignes du fil × 17 + 85 depuis la 1.1.1, + 93 en 1.1 : la grille, plus ce
qui la suit au centre, ▲ ▼, séparateur, invites et Style, bandeau, demande) : `fill_vertical` sur
`simple_list` reste sans effet (constaté). Dans l'Atelier (retiré après la 1.1.1), un espace
élastique poussait de même Publication, Consommation et les versions en bas de la colonne Note,
et les invites en bas de la colonne de la conversation. Sous le champ de demande, plus de ligne de
message (dans l'Atelier et le Panneau de la 1.1.1, seulement Envoyer, à droite) : ce qui s'y
affichait passe dans le bandeau (`Vues.bandeau`), une ligne en petit sur sa propre ligne, sous
les invites et le menu Style, au-dessus de la demande, depuis la 1.1.1 (en 1.1, à droite du menu
Style, sauf dans le Panneau). Il montre un message (orange), sinon l'aide d'un voyant rouge (un
clic l'affiche en entier), sinon les photos jointes (un clic les retire), sinon rien
(`Fenetre.etatBandeau` : `message`, `aide`, `jointes` ou `vide`). Le rappel « ajouté à chaque
demande, invites comprises » de la 1.1 (état `rappel`) est retiré en 1.1.1 (demandé par Dany le
20 octobre 2026) ; l'infobulle du menu Style le dit encore. La propriété `bandeau` suit
`message`, `aide` et `jointes` par des observateurs.

### Raccourcis clavier

Le SDK ne déclare pas de raccourci pour un module. `Raccourcis.lua` ajoute aux raccourcis d'app de
macOS pour Lightroom (`defaults write com.adobe.LightroomClassicCC7 NSUserKeyEquivalents
-dict-add`, sans toucher aux autres) : « Ouvrir la fenêtre Claude » ⌃⌥C, par le titre exact de
l'entrée de menu (seulement la fenêtre de conversation ; Publication et Consommation s'ouvrent
par ses boutons). Le bouton « Poser le raccourci » du Gestionnaire de modules externes (section
Fenêtre Claude) l'écrit ; Lightroom les lit à son lancement. Ils ne servent que si le menu Fichier
est complet, c'est-à-dire la fenêtre principale de Lightroom devant (voir les constats
ci-dessous). Les essais écrivent dans un domaine à part. Lightroom met trois espaces devant chaque
entrée d'un module dans Module externe - Extras (titres lus par l'accessibilité : « Développeur »,
puis «    Ouvrir la fenêtre Claude »), et macOS cherche le titre exact : le raccourci est donc
écrit avec ces trois espaces (`Raccourcis.RETRAIT`). Sans eux, il restait sans effet (constaté).
Constaté le 19 octobre 2026 (Lightroom Classic 15.6) : écrit avec les espaces puis Lightroom
relancé, le menu affiche ⌃⌥C et la touche ouvre la fenêtre ; un simple rechargement du module ne
suffit pas.

### Constaté dans Lightroom Classic 15.6 (19 octobre 2026)

- La fenêtre flottante s'ouvre par Fichier › Module externe - Extras › Ouvrir la fenêtre Claude ;
  les variantes superposées de la grille alternent bien selon le genre de chaque ligne, les
  polices nommées (Helvetica Neue, Menlo) sont respectées et la coupe des lignes tient dans la
  colonne.
- `f:picture` suit sa propriété liée (chemin d'un fichier JPEG) : l'aperçu change sans rouvrir la
  fenêtre. `mouse_down` d'un `static_text` répond au clic.
- `simple_list` liée (éléments et sélection) se met à jour ; une conversation nouvelle y prend son
  titre dès que Claude l'a donné.
- Un saut de ligne ajouté au champ de demande (par l'accessibilité) envoie la demande ; une vraie
  frappe de Retour au clavier reste à observer (le bouton Envoyer suffit dans tous les cas).
- Un module nommé `Versions.lua` ne se charge pas (« Could not load toolkit script: Versions »,
  `require` depuis la fenêtre) : nommé `Composants.lua`. Éviter ce nom.
- `save_frame` garde la taille de la fenêtre d'une ouverture à l'autre : elle ne rétrécit pas si
  le contenu devient plus étroit ou moins haut (bande vide en bas). Le cadre de la fenêtre Claude
  porte donc la taille choisie et un numéro de forme (`Fenetre.cadre` :
  `DeveloppeurClaude-<taille>-1` en 1.0, `DeveloppeurClaude-<disposition>-<taille>-1` en 1.1,
  `DeveloppeurClaude-<disposition>-grande-1` en 1.1.1, une seule taille,
  `DeveloppeurClaude-conversation-grande-1` après la 1.1.1, une seule disposition, le même nom
  que le cadre de la Conversation claire en 1.1.1, où 1 est `Fenetre.FORME`, à augmenter quand le
  contenu rapetisse) ; la fenêtre rouvre alors une fois à la position par défaut. Les autres
  fenêtres ont leur cadre : `DeveloppeurPublication`, `DeveloppeurConsommation`,
  `DeveloppeurSuivi`, et en 1.1 `DeveloppeurNotation` (Séance de notation, retirée en 1.1.1).
- Quand une fenêtre du module est devant (ou que Lightroom n'est pas l'application active), le
  menu Fichier de Lightroom est réduit (Nouveau catalogue, Ouvrir le catalogue, Mise en page,
  Imprimante) : les entrées du module et le Gestionnaire de modules n'y sont pas. D'où les boutons
  Publication et Consommation dans la fenêtre Claude (et, en 1.1, Séance… et le menu Disposition,
  retirés en 1.1.1 : le modèle et l'effort se choisissent dans le Gestionnaire, la fenêtre
  principale de Lightroom devant, comme la disposition en 1.1.1, retirée depuis).
- Publication : JPEG 5 Mpx d'un RAF de X-H2S, 2738 × 1825, sRGB, sans position GPS ; dossier créé,
  bilan et « Afficher dans le Finder ».
- 20 octobre 2026 (1.1, premier essai réel) : `visible` lié posé sur un conteneur est sans effet.
  Dans la Conversation claire, les trois onglets (Aperçu, Proposition, Note : colonnes à
  `visible = F.egal('onglet', …)`) s'affichaient tous ensemble, superposés ; même chose pour les
  colonnes `aProposition` du Panneau, et une boîte de groupe dans un onglet ne se masque pas non
  plus. Sur une vue simple, il marche : la Séance de notation (retirée en 1.1.1) masquait bien
  ses cases vides (`static_text` et `f:picture`), comme les variantes de la 1.0 (bandeau, voyants,
  lignes du fil). D'où `Vues.masquable` (voir Contraintes du SDK) ; la simulation de la fenêtre
  refuse `visible` sur un conteneur.
- 20 octobre 2026 (1.1) : après Accepter dans la Séance de notation puis `undo_last`, la note
  quitte bien le catalogue, mais la planche et la fiche montraient encore « acceptée » ★★★ : le
  registre ne voit pas l'annulation. D'où `Notation.recaler`, appelé alors par la planche et la
  fiche de la Séance, et par la carte Note, seule à le faire depuis la 1.1.1 (voir Le registre).
- 20 octobre 2026 (1.1), vus fonctionner : la Séance de notation (planche, fiche, Accepter,
  `undo_last` qui retire la note, réouverture par ↻ ; fenêtre retirée en 1.1.1), le Gestionnaire
  de modules externes avec le menu Disposition, et une passe 1 avec le vrai Claude.
- 20 octobre 2026 (1.1, essai réel avant la publication), vus fonctionner : les trois
  dispositions en taille Grande (l'Atelier et le Panneau retirés après la 1.1.1), ouvertes l'une
  après l'autre par le menu Disposition de la fenêtre (elle se ferme et se rouvre, la
  conversation gardée ; menu retiré en 1.1.1, réouverture retirée après la 1.1.1) ; les
  onglets par vues simples (chaque onglet ne montre que ses vues ; Agrandir de l'onglet Aperçu,
  retiré en 1.1.1, répond sous la colonne Note, superposée) ; les glyphes ★ ☆ ◀ ▶ ; Noter (bouton
  retiré en 1.1.1) avec le vrai Claude (cull_photos, view_photo, propose_ratings ; la carte Note
  montre « Claude propose : ★★★☆☆ », « à vérifier · passe 1 », les critères et le plafond
  mesuré ; « Notes proposées · 1 photo » dans le fil) ; la recette, étape « note proposée
  (propose_ratings), photo inchangée » comprise.
- 20 octobre 2026 (1.1) : Claude propose le plus souvent « à vérifier » (deux fois sur deux), et
  la fenêtre ne passait d'elle-même à l'onglet Note que pour une note « proposée » : elle y passe
  aussi pour « à vérifier » (`Fenetre.rafraichirNotation`). Depuis la 1.1.1, toute proposition
  arrive « à vérifier ».
- 20 octobre 2026 (1.1) : Claude a écrit un critère de 209 caractères pour 200 demandés, et
  `propose_ratings` a tout refusé (il a recommencé, plus court) : la longueur demandée reste 200,
  le refus ne vient qu'au-delà de 300 (`Notation.toleranceCritere`).
- 20 octobre 2026 (1.1) : dans le Panneau, le rappel « ajouté à chaque demande » restait sous la
  place laissée à la proposition, plus haute, loin du Style : chaque variante (invites et Style,
  proposition) porte son bandeau (le rappel est retiré en 1.1.1, le Panneau après la 1.1.1).
- 20 octobre 2026 (1.1.1), vus sur les captures refaites (`docs/capture.png`, `atelier.png`,
  `panneau.png` ; ces deux-là retirées après la 1.1.1, avec leurs dispositions) : la barre de
  titre « Développeur » et les versions 1.1.1 ; dans la Conversation claire, les boutons radio
  Note et Proposition en tête de la colonne de droite, puis l'aperçu, ◀ légende ▶, Agrandir, la
  carte Note (« Claude propose : ★★☆☆☆ » en rouge, « à vérifier ·
  passe 1 », critères, plafond mesuré et raison, coupés en page, ▼ actif ; boutons Accepter et
  Changer… seulement), Publication… et Consommation… au-dessus des versions ; dans les trois
  dispositions, le menu Style au bout de la dernière rangée d'invites, sans étiquette, et il y
  tient ; ni Noter, ni À vérifier, ni menu Modèle ou Disposition ; Envoyer seul sous la demande
  dans l'Atelier et le Panneau ; l'aperçu de l'Atelier, `f:picture` de 720 × 480, avec une
  vignette 3:2. Deux défauts vus, corrigés depuis, à revoir sur une prochaine capture : une ligne
  de la carte Note commençait par « ; mais » (`Fil.couper`, voir Contraintes du SDK), et dans
  l'Atelier les ▲ ▼ de la Proposition (740 points) n'allaient pas jusqu'au bord droit de leur
  rangée (les rangées des boutons des deux cartes portent depuis `fill_horizontal = 1` ; sans
  objet pour l'Atelier, retiré après la 1.1.1).

### À constater dans Lightroom (1.1, 1.1.1 et après)

La 1.1 a été construite et vérifiée le 20 octobre 2026 par les deux suites (`swift test`,
`scripts/tester-module.sh`, essais `essais-*.lua` compris), puis essayée dans Lightroom le même
jour, avant sa publication : ce qui y a été vu est dans la section précédente, et ses défauts
sont corrigés. La 1.1.1 (même jour : titre « Développeur », modèle et effort dans le
Gestionnaire, une seule taille, Conversation claire revue, nouvelle conversation par photo,
`apply`, Séance retirée, plus de Noter ni d'À vérifier : Claude note d'abord, « à vérifier »,
point de mise au point dans `view_photo`) est vérifiée par les deux suites (`swift test` :
237 tests ; `scripts/tester-module.sh` : liaison 212, fenêtre 43, `essais-dispositions` 17,
`essais-integration` 6, `essais-moteur` 13) ; dans Lightroom, seules les captures ont été
refaites (section précédente ; `docs/seance.png` est retirée). Après la 1.1.1 (pour la 1.2 : point
de mise au point sur l'aperçu de la photo active et sur un zoom, proposition préparée à
l'ouverture, Conversation claire seule), les deux suites passent (`swift test` : 238 tests ;
`scripts/tester-module.sh` : liaison 212, fenêtre 43, `essais-dispositions` 17,
`essais-integration` 7, `essais-moteur` 13) ; rien n'en a encore été vu dans Lightroom.
Restent à voir, à l'usage ; ce qui sera constaté passera dans sa section, avec sa règle dans la
simulation de sa suite.

1. Claude Desktop accepte l'`outputSchema` de `propose_ratings` (`propositions`, `refusees`,
   `posees`, `erreur_pose` de type texte ou null, `standard` ; plus de `seance` depuis la 1.1.1)
   et lit `structuredContent` ; Claude Code 2.1.303 rend le `tool_result` de `propose_ratings` en
   texte JSON `{propositions, refusees, posees?}`, comme l'attend `Conversation.notesLues`.
2. Planche de 30 vignettes (`contact_sheet`) : poids réel, et lisibilité de l'Impact à environ
   208 × 139 px par photo. Plafonds de `cull_photos` sur une vraie séance (rejets proposés, photos
   presque noires « à vérifier », doublons de rafale plafonnés à 3). Durée de la commande
   `notation` pour 500 propositions, et pour 500 notes posées avec `apply` (dans les 60 s de
   `notationTimeout`).
3. Rendu de ⚑ dans les lignes du fil (Menlo 11). Les largeurs de `Metriques.lua` viennent de
   NSString : vérifier qu'aucune ligne n'est coupée autrement, ni dans les textes de la carte Note
   et de la Proposition, coupés de même (1.1.1). Onglets par vues simples : les boutons d'un
   onglet couvert (Accepter, Changer… et ▲ ▼ de la carte Note sous la colonne Proposition ;
   Agrandir répondait en 1.1 sous la colonne Note, constaté ; en 1.1.1, aussi tout Retoucher
   sous la colonne Noter du Panneau, retiré après la 1.1.1). S'ils ne répondaient pas : passer à
   un `tab_view` du SDK (`tab_view_item` par onglet, `value` liée à `onglet`). Les boutons ▲ ▼
   en `size = 'mini'` (rendus, vu sur les captures) : leur clic, une page à la fois, et leur place
   au bord droit de la rangée (`fill_horizontal`) ; la ponctuation haute gardée avec son mot. Un
   clic sur un bouton radio ou un choix dans un `popup_menu` valide-t-il le champ de demande, et
   avant ou après l'observateur qui annule l'envoi ?
4. Réouverture : sans objet après la 1.1.1 (une seule disposition, plus de réouverture : voir
   Disposition). Constatée en 1.1 par le menu Disposition ; celle de la 1.1.1, par la boucle
   (`Fenetre.periodique`) après un changement dans le Gestionnaire, n'a pas été vue.
5. Menu des conversations (`popup_menu` de l'Atelier et du Panneau) : sans objet après la 1.1.1,
   retiré avec eux.
6. Hauteurs et largeurs réelles de la Conversation claire, seule disposition, dans sa seule
   taille : 42 lignes de fil (le centre à la hauteur de la colonne de droite : boutons radio,
   aperçu, carte Note ; la liste des conversations, `D.hauteurListe`, au niveau du champ de
   demande), et les rangées de boutons, dont les invites et le Style sur une seule rangée. Le
   cadre enregistré (`DeveloppeurClaude-conversation-grande-1`) repris de la 1.1.1, lui-même
   repris de la grande taille de la 1.1 (`-grande-`).
7. Carte Note de bout en bout : Accepter (dans une tâche) et Changer… (fenêtre modale, 0 à 5 ★)
   écrivent par `Bibliotheque.noter` depuis une tâche de la fenêtre (`setRawMetadata` de
   `rating` et `pickStatus`). La note posée se relit dans la carte. Lecture de
   `catalog:getPath()` depuis les tâches de la fenêtre. Le message « Lightroom est occupé »
   s'affiche si Claude Desktop écrit au même moment.
8. `propose_ratings` avec `apply` (« note ces photos ») : notes posées, une opération ⌘Z
   « Claude · notation » par écriture, une étape par photo que `undo_last` défait une à une ; la
   pause de la liaison l'arrête ; en « Proposer d'abord » avec « Confirmer dans Lightroom »
   (`accordDansLightroom`), l'accord de la fenêtre de suivi (`depuisLightroom` faux), et le refus
   qui dit de rappeler `propose_ratings` avec `apply = true` ; le fil dit « Notes à poser »
   pendant l'appel, puis « Notes posées » et « posée » (ou « Notes non posées » et la raison), la
   carte Note « acceptée ». Une note posée reste après « Revenir à « Avant Claude » » sur une
   photo que Claude a aussi retouchée.
9. Nouvelle conversation par photo : une autre photo choisie à la main commence une conversation ;
   `show_photo` ou un tri du vrai Claude n'en commence pas, et les 4 s après la fin du travail
   (`Moteur.finTravail`) suffisent ; une photo choisie fenêtre fermée compte à la réouverture, et
   une fenêtre fermée pendant que Claude travaillait retrouve sa conversation.
10. Avec le vrai Claude : `consignes.md` de la session bien lu ; `--model fable` et `--effort`
    acceptés dans la fenêtre ; un autre modèle ou un autre effort relance Claude Code à la demande
    suivante par `--resume` (temps de démarrage, bonne session, coût du cache, grilles de recalage
    perdues) ; Claude note d'abord chaque photo qu'il traite (`cull_photos`, `view_photo` avec
    `af_point`, `propose_ratings` sans `apply`), ne renote pas une photo déjà évaluée
    (`evaluation`), passe `apply = true` quand Dany écrit « note ces photos », et n'écrit pas de
    note par `set_metadata` sans demande ; les lignes « Notes proposées » et « Notes posées »
    s'affichent dans le fil. Dans Claude Desktop, l'invite `noter` sans précision note la
    sélection.
11. Gestionnaire de modules externes (le menu Disposition s'y affichait en 1.1, constaté) : les
    menus Modèle et Effort, les cases « Autre photo » et, après la 1.1.1, « À l'ouverture » de la
    section Fenêtre Claude, et la case « Mise au point » de la section Liaison s'affichent et
    s'écrivent ; plus de menu Taille, ni, après la 1.1.1, de menu Disposition. Coût de la
    réécriture de `notation.json` à chaque décision avec quelques centaines de propositions.
12. Point de mise au point dans `view_photo` (1.1.1) : sur un RAF de Fujifilm (X-T20 de la recette,
    X-H2S), le carré à la place du collimateur, photo tournée ou recadrée comprise ; rouge pour
    une mise au point signalée manquée ; dessiné sans `af_point` quand la case « Mise au point »
    est cochée ; une lecture bloquée par une demande d'autorisation de macOS saute le point, puis
    reprend quand l'utilisateur a répondu. Après la 1.1.1, sur un zoom (`region`) : le carré dans
    la zone quand le point y tombe (`dans_la_zone`), à sa place sur le zoom ; `dans_la_zone` faux
    et pas de carré quand il tombe ailleurs.
13. Aperçu de la photo active marqué (après la 1.1.1) : sur un RAF de Fujifilm (X-T20, X-H2S),
    `mcp-developpeur --marquer-af` lancé par Lightroom (`LrTasks.execute`) dessine le carré à sa
    place sur la vignette, photo tournée ou recadrée comprise, rouge pour une mise au point
    signalée manquée ; Agrandir le montre ; le temps ajouté à l'ouverture (lecture bornée à 2 s).
    Une demande d'autorisation de macOS pour le connecteur lancé par Lightroom : la vignette
    reste-t-elle sans carré, sans bloquer la fenêtre ? Une autre marque : rien n'est lancé.
14. Proposition préparée à l'ouverture (après la 1.1.1), avec le vrai Claude : la demande part à
    l'ouverture et au rappel par le menu ou ⌃⌥C, sur une conversation vide seulement ; Claude
    note d'abord la photo, puis appelle `preview_settings` sans rien appliquer ; la proposition
    attend dans l'onglet Proposition, la carte Note devant ; rien ne part quand la case « À
    l'ouverture » est décochée ou que la conversation a déjà des messages. Coût en jetons d'une
    demande à chaque photo nouvelle (fenêtre Consommation).

## Réglages

Les 124 réglages globaux de `Catalogue.swift`, par leur nom dans le SDK de Lightroom (le même que
dans les XMP) : balance des blancs, tonalité (`*2012`), HDR (`HDREditMode`, `HDRMaxValue`, curseurs
`SDR*` de l'aperçu SDR), présence, courbe paramétrique (ses trois limites de zones et « Affiner la
saturation » compris), TSL, noir et
blanc (`ConvertToGrayscale`, rangé en booléen, et `GrayMixer*`), étalonnage des couleurs, détail
(dont les réglages fins du bruit), effets (dont le style du vignetage), optique (dont la distorsion
et le vignetage manuels, les franges), transformation (`Perspective*`), calibrage de l'appareil. Le serveur refuse un nom inconnu et ramène une
valeur absolue dans sa plage ; le module borne de nouveau (valeurs relatives comprises), règle la
plage de la température et de la teinte selon la photo (RAW : 2000 à 50000 K et ±150 ; autres :
±100, rangées par Lightroom dans `IncrementalTemperature` et `IncrementalTint`), arrondit (exposition au centième, rayon de netteté au dixième, le reste à l'unité), puis
applique les limites de l'utilisateur. Une température ou une teinte imposée fait passer la
balance des blancs en « Personnalisée ».

Les réglages de transformation absents des réglages d'une photo valent leur valeur neutre
(`PerspectiveScale` 100, les autres 0), mémorisée comme valeur d'avant. Upright (`PerspectiveUpright`,
0 à 4) déclenche bien l'analyse de Lightroom : les matrices `UprightTransform_*` sont calculées.

Courbe paramétrique : plages et défauts relevés dans Camera Raw (Lightroom Classic 15.6,
`getCRParamsInfo`) : `ParametricShadowSplit` 10 à 70 (25), `ParametricMidtoneSplit` 20 à 80 (50),
`ParametricHighlightSplit` 30 à 90 (75), `CurveRefineSaturation` 0 à 100 (100). Lightroom les rend
toujours (`getDevelopSettings`) : `view_photo` ne montre pas un réglage à sa valeur neutre
(`DevelopSetting.neutral`), et le module tient ces défauts pour la valeur d'avant d'un réglage absent.

Version de processus : relevé dans Lightroom Classic 15.6 (`kProcessVersionHistoryNames`) :
`ProcessVersion` vaut « 5.0 » (version 1, 2003), « 5.7 » (2, 2010), « 6.6 » ou « 6.7 » (3, 2012),
« 10.0 » (4), « 11.0 » (5) et « 15.4 » (6, l'actuelle). `get_settings` et `view_photo` la donnent
(« version 5 (11.0) ») et signalent une version ancienne (`version_processus_ancienne`).
`process_version: 6` la met à jour (`ProcessVersion = "15.4"` par `applyDevelopSettings`, qui
l'écrit tel quel, relevé), en tout mode seulement avec `confirm` : le rendu peut changer nettement,
Adobe conseille de comparer, et `preview_settings` le montre. Les versions 3 à 6 ont les mêmes clés
(`*2012`) ; les versions 1 et 2 ont les leurs (`Exposure`, `FillLight`…), que seul le menu de
Lightroom convertit (Paramètres › Mettre à jour vers la version de processus actuelle : Luminosité
+15 de 2010 y devient Exposition 2012 +0,3, Noirs 1 deviennent −2, et grain et réduction du bruit
changent ; constaté le 18 octobre 2026). Un module ne le peut pas : `ProcessVersion` posé par
`applyDevelopSettings` ou par un paramètre prédéfini du module change la version sans convertir
(Exposition 2012 reste à 0), et `LrDevelopController.setProcessVersion("Version 6")` ne fait rien
(relevé : il compare le nom demandé aux noms de `kProcessVersionHistoryNames`, des textes à
traduire, ZSTR, qui ne lui sont jamais égaux ; constaté, photo affichée dans le module
Développement). Le module laisse donc ces photos, et la remarque dit de le faire à la main. Un
instantané « Claude · avant version de processus » est pris avant toute mise à jour.

Courbe par points : `courbes` porte les listes à plat (x1, y1, x2, y2…) de `ToneCurvePV2012` et de
ses variantes par canal ; le module met `ToneCurveName2012` à « Custom ». Couleur ponctuelle :
`couleurs_ponctuelles` porte les tables `PointColors` que le serveur construit (saturation et
luminosité source de 0 à 1, décalages de −1 à +1, plages relevées dans le catalogue). La teinte
source, `SrcHue`, va de 0 à 6, en sixièmes de tour (doc du SDK, `addPointColorSwatch` : « Values
from 0 to 6 » ; relevé 4,65753 sur une robe lavande, 279°) : le serveur divise les degrés par 60
(avant la 2.1, par 360 : la teinte visée était fausse). La variance (curseur de −100 à +100, onglet
Variance) va dans `PointColors[i].Variance`, le curseur divisé par 100 (40 → 0,4, constaté le
17 octobre 2026).

Constaté dans Lightroom Classic 15.6 :

- le traitement noir et blanc (`ConvertToGrayscale = true`) est rangé mais pas rendu sous une Look
  couleur comme Adobe Color ; dans le catalogue, un RAW en noir et blanc porte Adobe Monochrome.
  Le serveur envoie donc `looks_traitement` (Adobe Monochrome et Adobe Color) et le module change
  de Look comme l'interface de Lightroom ;
- `AutoTone = true` et `WhiteBalance = "Auto"` posés par `applyDevelopSettings` sont rangés mais
  rien n'est calculé. Passés par un paramètre prédéfini du module (`addDevelopPresetForPlugin`,
  puis `applyDevelopPreset`), le chemin des paramètres prédéfinis d'Adobe, ils sont calculés ;
- un paramètre prédéfini du module sans balance des blancs (tonalité automatique, masques IA) fait
  tomber une balance personnalisée (`WhiteBalance = "Custom"`) aux butées, 2000 K et −150 : seules
  `Temperature` et `Tint` changent. Ceux d'Adobe la gardent, et une balance « Telle quelle » n'est
  pas touchée. Le module mémorise donc la balance dans l'étape (`noterPresetDuModule`) et la
  repose après ses paramètres prédéfinis (`appliquerPlan`), avec les valeurs que la commande lui
  donne. Pour un JPEG (`IncrementalTemperature`, `IncrementalTint`), la recette le vérifie depuis
  le 16 octobre 2026 (copie verticale d'un JPEG sans données d'appareil) : une balance relative (+10) reste après
  la tonalité automatique et un masque IA. La chute aux butées d'une balance de JPEG sans cette
  remise n'a pas été observée directement.

Exclus : suppression générative, fusions HDR et panorama, retouche au pixel, que le SDK n'expose
pas. Le débruitage, les détails bruts et la super résolution passent par `ameliorer` (voir
Débruitage, détails bruts, super résolution).

## Profil

`apply_settings` accepte `profile` : Adobe Standard ou une simulation de film Fujifilm rangée en
profil DCP, que Lightroom applique par son seul nom (`CameraProfile = "Camera CLASSIC CHROME"`), ou
un profil à base de Look. Le
serveur envoie `profil` et, pour un profil réservé à une marque, `profil_marque` ; le module refuse
(remarque, sans erreur) un fichier qui n'est pas un RAW ou dont la marque ne correspond pas.

Les simulations Fujifilm ne sont pas des fichiers DCP sur le disque : Camera Raw les embarque, et
leur nom varie d'un appareil à l'autre. Le catalogue du serveur (`DevelopCatalogue.profiles`) donne
le nom que Lightroom range pour un X-H2S et, sous `variants`, les autres orthographes connues ; le
serveur reconnaît l'une ou l'autre, sans la casse, envoie le nom du catalogue et, s'il y en a,
`profil_variantes`.

Constaté dans Lightroom Classic 15.6 (16 octobre 2026, copies virtuelles de RAW de X-H2S) :

- Lightroom cherche le nom sans tenir compte de la casse et range sa propre orthographe
  (« Camera MONOCHROME » devient « Camera Monochrome », « Camera ACROS+Ye FILTER » devient
  « Camera ACROS+Ye Filter ») ; la ponctuation compte : « Camera PRO Neg. Hi » et « Camera PRO Neg.
  Std » n'existent pas pour cet appareil, « Camera Pro Neg Hi » et « Camera Pro Neg Std » oui.
  REALA ACE existe aussi (« Camera REALA ACE »).
- Autres appareils, constaté en 2.3 (18 octobre 2026, copies d'un RAF de X-T4 et d'un RAF de
  X-T20) : le X-T4 garde les seize noms du X-H2S tels quels (REALA ACE compris) ; CLASSIC Neg y est
  une Look sur « Camera PROVIA/Standard » (`Look.Name = Camera CLASSIC Neg`), NOSTALGIC Neg
  n'existe pas. Le X-T20 range d'autres orthographes : « Camera PROVIA/STANDARD », « Camera
  Velvia/VIVID », « Camera ASTIA/SOFT », « Camera Pro Neg. Hi », « Camera Pro Neg. Std », « Camera
  ACROS+Ye FILTER » (et +R, +G), « Camera MONOCHROME » (et ses filtres en FILTER) : toutes
  retrouvées (casse, `variants`) ; REALA ACE et ETERNA/Cinema n'y existent pas (relus « Adobe
  Standard » : refusés, profil d'avant remis), CLASSIC Neg et NOSTALGIC Neg non plus (Look absente).
  Corrigé en 2.4 (recette du 18 octobre 2026) : Lightroom garde maintenant les noms « Camera
  ETERNA/Cinema » et « Camera REALA ACE » sur ce RAF de X-T20, sans `MissingCameraProfile`, même
  après un rendu, mais l'aperçu est celui d'Adobe Standard au centième près (chroma 9, contraste
  86,9, tons neutres −3,6 et −2,5 ; Classic Chrome : 8,3, 92,4, −4,6 et −2,1). Aucun réglage ne
  distingue ce repli : le catalogue du serveur nomme ces modèles (`missingOn`, envoyé en
  `profil_absent_sur`) et le module refuse le profil, avec une remarque.
  `list_profiles` le dit. `LrApplication.dumpCameraProfileInfo` (non documentée) ne rend rien :
  sans argument comme avec l'identifiant d'une photo, Lightroom ouvre la fenêtre « Une erreur
  interne s'est produite. AgStoreProviderSession:getEntityByID: id must be a number or string »,
  que `pcall` n'attrape pas ; écartée.
- Mélangeur noir et blanc sous un profil d'appareil monochrome, constaté en 2.3 (copie d'un RAF de
  X-H2S au ciel bleu, luminance L* du ciel sur l'aperçu) : Adobe Color 78,1 ; Camera ACROS 79,0 ;
  plus `GrayMixerBlue` −80 : 79,0, aucun effet (la valeur est rangée, `EnableGrayscaleMix` vrai) ;
  témoin Adobe Monochrome avec le même mélange : 30,1. Le profil rend déjà du gris : le plan le
  dit en remarque (`noterMelangeSansEffet`) pour ACROS et MONOCHROME, et l'invite noir et blanc
  envoie vers le filtre du profil.
- Un nom introuvable est accepté sans erreur : juste après l'écriture, `getDevelopSettings` relit
  le nom posé ; moins d'une demi-seconde plus tard, Adobe Standard. Le catalogue range alors le nom
  introuvable sous `MissingCameraProfile` (et son empreinte sous `MissingCameraProfileDigest`).
  Tant qu'il y reste, tout profil d'appareil posé ensuite par le SDK retombe à Adobe Standard, même
  un nom valide (« Camera ASTIA/Soft », le profil de base « Camera PROVIA/Standard » d'une Look
  CLASSIC Neg), et même après une relance de Lightroom. `MissingCameraProfile = ""` le libère.
- `getDevelopSettings` ne rend ni `CameraProfileDigest` (l'empreinte du profil, que le catalogue
  range, recalculée au rendu suivant) ni `MissingCameraProfile`, ni `MissingCameraProfileDigest`.
- `LrApplication.dumpCameraProfileInfo(chemin, id)`, non documentée, liste les fichiers DCP du
  disque (tous les appareils, plusieurs secondes) : sans les simulations Fujifilm embarquées, elle
  n'aide pas à trouver leur nom.

Le module pose donc tout profil d'appareil avec `MissingCameraProfile = ""` et
`MissingCameraProfileDigest = ""` (`libererProfil` : retouche, annulation, retour, proposition,
comparaison). Après l'écriture, il relit le profil de chaque photo pendant 1,5 s, une seule
attente pour toutes (`attendreProfils`) ; un nom qui ne diffère que par la casse tient, et la
réponse donne celui que Lightroom a rangé. Un profil qui ne tient pas est essayé sous chaque
variante (une étape de plus dans l'Historique) ; si aucune ne tient, le profil d'avant est remis
(Look comprise, comme Adobe Color), le changement sort de la réponse et du journal, et une remarque
dit pourquoi (`note` de l'entrée du journal). `essayer` le dit de même ; `annuler` et `revenir`
ajoutent `remarque` quand un profil remis ne tient pas.

Adobe Color, CLASSIC Neg., NOSTALGIC Neg. et les autres profils récents sont une « Look » posée sur
un profil de base (`CameraProfile = "Adobe Standard"`, `Look = {Name = "Adobe Color", …}`). Pour
passer à un profil DCP, le module envoie `Look = {}` ; la Look d'avant est mémorisée telle quelle,
et l'annulation la remet. Ce qui revient du JSON passe par `pourLightroom` (copie profonde sans
métatables ni `null`) : une Look relue telle quelle, avec la métatable que `Json.decode` pose sur
les tableaux, a bloqué `applyDevelopSettings` sans erreur, verrou d'écriture compris, jusqu'au
redémarrage de Lightroom. La simulation des tests refuse toute métatable.

Profils à base de Look (`ProfilsLook.swift`) : le serveur lit les fichiers XMP de type « Look »
livrés avec Lightroom (`Resources/Settings/Adobe/Profiles`), ceux de Camera Raw et ceux de
l'utilisateur, et construit la table `Look` comme le catalogue la range : `Name`, `UUID`, `Amount`,
`Copyright`, `Group`, `Supports*`, et `Parameters` (profil de base, empreinte de la table de
couleur, courbes, version). Les nombres restent des nombres (`RGBTableAmount`, `RGBTables`,
`ProfileGainTableMap`) ; seuls les noms, versions et empreintes (`CameraProfile`, `LookTable`,
`RGBTable`, `Version`) sont du texte. Constaté dans Lightroom Classic 15.6 : un nombre envoyé en
texte est écarté de la Look sans erreur ; Artistic 01 (`RGBTableAmount = 0.5`) sortait alors à
pleine force (chroma moyenne 27,4 au lieu de 18,3). Les données des tables (`crs:Table_…`) restent dans le fichier :
Lightroom les retrouve par leur empreinte (constaté avec CLASSIC Neg.). Un nom peut avoir un
fichier par appareil (simulations Fujifilm) : le serveur envoie tous les `candidats` avec leur
`restriction`, et le module prend celui de l'appareil de la photo. `intensite` règle `Amount`
(0 à 2) pour les profils qui le permettent.

### Profils adaptatifs

Adaptive Color et Adaptive B&W (dossier Adaptive, RAW seulement) sont des Looks que Lightroom
calcule pour chaque photo par IA. Relevé le 16 octobre 2026 (Lightroom Classic 15.6, copie d'essai
RAW de X-H2S sous CLASSIC CHROME) :

- Choisi à la main, Adaptive Color pose `CameraProfile = "Adobe Standard"`, une `Look` portant
  `isAdobeAdaptive = true`, `Cluster = "Adobe"`, `Group = Adaptive` et, dans `Parameters`,
  `RGBTables = 100` et `ProfileGainTableMap = 100` (des nombres), et un réglage `AILook` (hors de
  la Look) : `Active = true`, `AILookData` (empreinte du calcul), `InputDigest`,
  `InputDigestVersion = 5`, `ModelVersion`, `Version`. Le journal de Camera Raw montre le calcul
  (`ai_look::DoInference`, détection du sujet et du ciel).
- Posé par `applyDevelopSettings` (jusqu'à la 1.6.1, sans `isAdobeAdaptive` ni `AILook`), il est
  rangé (Lightroom ajoute `isAdobeAdaptive`) mais jamais calculé : `AILook` reste vide, même après
  un rendu, et le profil de base reste celui d'avant.
- Par un paramètre prédéfini du module (`addDevelopPresetForPlugin`, puis `applyDevelopPreset`,
  qui passe dans Lightroom par `applyDevelopPresetToPhotoIds`), il n'est marqué « à mettre à jour »
  que si la Look porte déjà `isAdobeAdaptive` **et** si le paramètre prédéfini porte
  `AILook = {Active = true}` : sans l'un ou l'autre, `AILook` reste sans `AILookData` et aucune
  fenêtre ne s'ouvre, même 60 s plus tard. Lightroom complète `AILook` (`ModelVersion`,
  `Version`).
- Marqué, il n'est pas calculé de lui-même dans la minute (rien en 75 s, photo affichée dans
  Développement ; une fois, environ deux minutes après la pose, pendant que l'utilisateur
  regardait le panneau Réglages de base, sans cliquer). Le panneau Réglages de base montre un
  bouton « Mettre à jour ». L'exportation qui suit ouvre la fenêtre « Mises à jour IA
  recommandées », pour la photo affichée comme pour une autre ; Exporter, case « Mettre à jour »
  cochée, et Lightroom calcule avant de rendre : même
  `AILookData` et même `InputDigest` qu'à la main, et l'aperçu change (L* médiane 60,4 → 60, contraste 43,5 → 47,6,
  chroma 11,7 → 16,1 ; sans le calcul, Adobe Standard et la table fixe seuls : 57,9, 40,2, 13,1).
- Après une rotation (`crop.angle`), Lightroom ne le marque pas à recalculer : `AILook` garde ses
  empreintes et l'exportation n'ouvre pas de fenêtre. L'aide d'Adobe demande de le mettre à jour
  après des taches, une rotation ou un flou d'objectif : depuis la 1.8, le module le demande à
  Lightroom par `updateAISettings`, qui le recalcule après une tache ou un flou ; une rotation ne
  le change pas (voir Aperçus et masques IA, Calcul par le SDK).
- Un paramètre prédéfini créé dans Lightroom avec la case Profil cochée, sur une photo sous
  Adaptive Color, est vide (`HasSettings = False`) : Lightroom n'y range pas un profil adaptatif.

Le module pose donc un profil adaptatif par un paramètre prédéfini du module (`poserAdaptatif`) :
la Look telle que le serveur la lit (`isAdobeAdaptive` et `Cluster` ajoutés pour le dossier
Adaptive), et ce que le serveur met dans `par_preset` (`LookProfile.adaptivePreset` :
`CameraProfile = "Adobe Standard"`, `AILook = {Active = true}`) ; `AILook` est mémorisé pour
l'annulation. Après l'écriture (`verifierCalculAdaptatif`), un `AILook` inactif défait le profil
(jamais un faux succès) ; actif sans `AILookData`, une remarque dit qu'il sera calculé au rendu
suivant. `Locaux.lookACalculer` le compte parmi les calculs en attente : `rendre` ne l'attend pas
(Lightroom ne le fait pas de lui-même, contrairement aux masques IA de la photo affichée,
`Locaux.calculsSpontanes`) ; s'il reste à calculer après l'exportation, `a_savoir` le dit. `copier` traite de même un profil adaptatif de la source, sans
son `AILook` (ses empreintes ne valent que pour elle). La simulation range ces règles
(`rangerLookAdaptatif`, `mettreAJourLook`) ; la recette pose Adaptive Color, demande un aperçu,
vérifie `AILookData`, puis annule.

## Recadrage

`apply_settings` accepte `crop` : `aspect` (« 4:5 », « original »…), `angle` (−45 à +45), `size`
(0,2 à 1), `center_x`, `center_y` (0 à 1, dans l'image affichée), ou `reset`. Le serveur vérifie et
envoie `recadrage = {ratio?, angle, taille, centre_x?, centre_y?}` (un centre seulement s'il est
donné) ou `{retirer = true}` ; le module (`Recadrage.lua`) calcule les cinq réglages `Crop*`. Constaté dans Lightroom Classic 15.6 :

- les coordonnées (0 à 1) sont dans le repère du fichier, avant l'orientation ;
- le cadre est tourné de `CropAngle`, et (`CropLeft`, `CropTop`), (`CropRight`, `CropBottom`) sont
  ses coins haut gauche et bas droit : Lightroom en déduit largeur = dx·cos θ + dy·sin θ et
  hauteur = −dx·sin θ + dy·cos θ (dx, dy : écarts entre les coins, en pixels) ;
- un angle positif fait tourner l'image affichée dans le sens antihoraire (son côté droit monte) ;
- `getRawMetadata('orientation')` donne l'orientation ; pour « DA » (appareil tenu poignée en
  haut), le bord droit du fichier s'affiche en haut ; « BC » est le quart de tour inverse.

Le module prend le plus grand cadre au ratio demandé dont la boîte englobante tient dans l'image,
le réduit autour d'un centre décalé, puis relit `croppedDimensions` et signale un ratio obtenu
différent de plus de 2 %.

Une photo déjà agrandie hors de Lightroom par l'agrandissement génératif de Camera Raw (cadre
hors de [0, 1], ou filtre `FilterID` 9 de `FilterList` : `Reglages.estAgrandie`) perdrait son
agrandissement à tout recadrage calculé dans [0, 1] (constaté : un `crop.angle` de 1° ramenait
`CropLeft` de −0,1997 à 0,018), d'où le refus de la recadrer (`preparerRecadrage`), la copie du
recadrage vers ou depuis elle sautée, et « Contraindre le recadrage » laissé tel quel sur elle.

Constaté dans Lightroom Classic 15.6 (16 octobre 2026, copie d'essai RAW de X-H2S, XF16-55) :
`PerspectiveUpright` posé par `applyDevelopSettings` ne touche pas au recadrage, qu'il soit posé
avant ou dans le même appel (`Crop*` relus identiques après le calcul des matrices
`UprightTransform_*`), alors que l'interface remet le recadrage à zéro quand on choisit un mode
Upright. Le cadre se pose sur l'image transformée : sans recadrage, Upright complet (2) laisse des
coins vides, blancs dans l'aperçu, que les mesures de `view_photo` comptent comme écrêtage (7,4 à
7,8 % de blanc pur) ; un cadre au ratio d'origine réduit à 85 % en laissait encore un (0,4 %).
`CropConstrainToWarp` (« Contraindre le recadrage ») reste à 0.

### Contraindre le recadrage

Constaté le même jour, sur la même copie, Upright complet posé :

- `CropConstrainToWarp = 1` posé par `applyDevelopSettings`, seul ou avec `PerspectiveUpright`
  dans le même appel : Lightroom resserre aussitôt le cadre (relu à la commande suivante), au même
  ratio et au même angle, et l'aperçu n'a plus de blanc pur. Cadre entier : 85 % de la largeur,
  centré en (0,43 ; 0,50) ; 3:2 tourné de 3° : centré en (0,44 ; 0,47) ;
- tant que la case reste cochée, chaque écriture du cadre ou du mode Upright est resserrée de même.
  Un cadre qui ne montre que la photo reste tel quel, même plus petit que le plus grand possible
  (4:5 centré à 47 % de la largeur, 4:5 à 60 %) ; un cadre qui déborde un peu se réduit autour de
  son centre (4:5 centré à 90 % : 47 %, centre gardé) ; un cadre qui touche deux bords (l'image
  entière, un 4:5 pleine hauteur) devient le plus grand cadre possible, quitte à se déplacer (le
  4:5 passe du centre 0,50 à 0,25). Upright 4 garde un cadre qui tient ; Upright remis à 0, la case
  cochée, le cadre bouge d'un millième ;
- ce cadre resserré n'est pas dans ce que le module a écrit : un retour à l'origine qui ne
  connaissait pas le cadre d'avant a gardé le cadre resserré (photo d'essai remise à la main).

Le module coche donc la case (`preparerContrainte`) dès qu'une retouche, une copie ou une
proposition touche la géométrie (`Perspective*`, `Lens*`, un paramètre prédéfini) ou le cadre d'une
photo dont Upright, la perspective ou la distorsion manuelle seront actifs, et mémorise alors les
cinq réglages `Crop*`, que Lightroom peut changer : l'annulation et le retour à l'origine les
remettent, case comprise. Après l'écriture, il relit le cadre (`relireCadres`, une fois tout de
suite, une fois 0,3 s plus tard s'il n'a pas bougé) : la réponse et le journal donnent celui que
Lightroom a gardé, avec la remarque « Cadre resserré par Lightroom… » (largeur, centre). Le profil
d'objectif seul ne compte pas : il agrandit l'image pour ne pas laisser de coin vide.

Les rendus du recalage (`geometrie` avec `rendre`) décochent la case le temps des rendus : sinon
Lightroom resserrerait l'image « entière » sur l'image transformée, et la grille ne porterait plus
sur l'image entière. Un utilisateur qui coche lui-même la case avait déjà ce défaut.

### Cadre demandé sans coins vides

Pour un cadre demandé, Lightroom choisirait le centre lui-même dès que le cadre touche deux bords.
La grille du recalage (voir Recalage de la géométrie) dit où sont les coins vides : un point de
l'image affichée entière montre la photo si la grille le ramène dans l'image d'avant les
corrections, à 0,2 % près (`Geometrie.zone` ; la marge couvre l'interpolation de la grille et le
bord adouci du rendu). Seuls Upright, la perspective et la distorsion manuelle comptent
(`transformation` de la commande `geometrie`), ce qui évite les deux rendus pour le seul profil
d'objectif.

Avec une zone, `Recadrage.calculer` vérifie 8 points par côté du cadre (coins compris : la
distorsion courbe un peu les bords) et cherche, par dichotomie, la plus grande largeur qui tient
autour d'un centre ; la zone étant presque convexe, un cadre qui tient tient encore réduit autour
du même centre. La référence de `taille` est le plus grand cadre sans coin vide, centre libre
(recherche par motifs, du dixième au demi-millième de l'image, diagonales comprises). Un centre
non donné reste au milieu de l'image si le cadre voulu y tient, sinon il glisse vers le centre du
plus grand cadre, juste assez ; un axe donné ne bouge pas. Sans zone, le calcul est celui d'avant.
La remarque « Cadre resserré sur l'image redressée… » donne la largeur obtenue et, s'il a bougé,
le centre.

Vérifié sur la même copie : sur deux rendus à 2048 px, la zone que la grille dit remplie ne
compte aucun pixel blanc (639 410 pixels), celle qu'elle dit vide en compte 95 % (la marge, au
bord). Les cadres calculés tombent à 0,3 % près sur ceux de Lightroom : cadre entier 84,7 % de la
largeur, centré en (0,426 ; 0,500) ; 4:5 libre centré en (0,249 ; 0,500) ; 3:2 tourné de 3°
centré en (0,437 ; 0,469). Posés, eux et un 4:5 gardé au centre (47 %) donnent 0 % de blanc pur,
et Lightroom les garde tels quels, case cochée.

Déroulement, côté serveur :

- `apply_settings` et `preview_settings` avec un recadrage (sans `reset`) et sans réglage
  `Perspective*` ou `Lens*` ni paramètre prédéfini : le serveur demande d'abord les grilles des
  photos transformées (`recalages`, comme pour les masques), et le module calcule le cadre du
  premier coup ;
- un recadrage demandé dans la même retouche qu'Upright, la perspective ou la distorsion manuelle
  n'a pas de grille pour la géométrie obtenue : Lightroom le resserre (case cochée), et le module
  signale `a_recadrer` (et `etape_ecrite`). Le serveur calcule alors la grille de la nouvelle
  géométrie et envoie `recadrer` avec le même recadrage : le cadre se place au centre et à la
  taille demandés. Ses changements et ses remarques remplacent ceux de la réponse. Pour les photos
  de `completer`, `recadrer` complète la dernière étape de Claude, du même nom : valeurs d'avant
  des réglages qu'elle ne touchait pas (et `avantClaude`), entrée du journal dont les changements
  du cadre partent de la valeur d'avant l'étape ; `undo_last` défait le tout, et l'Historique de
  Lightroom montre deux étapes du même nom, plus celles du recalage. Sans grille (image trop
  uniforme), le cadre de Lightroom reste, et la remarque le dit ;
- un recadrage retiré (`reset`) reste retiré ; la case cochée, Lightroom le resserre.

L'empreinte de la géométrie laisse de côté les matrices `UprightTransform_*` (et
`UprightTransformCount`), que Lightroom calcule après coup, et les réglages à leur valeur neutre,
que les rendus du recalage posent en remettant la photo : sinon la grille calculée ne valait déjà
plus pour `recadrer`. Elle est relue après les rendus.

La simulation (`Tests/Lua/Liaison/Simulation.lua`) déforme l'image quand Upright, la perspective ou la
distorsion manuelle sont actifs (un trapèze : les coins du bas vides, 7,7 % du cadre entier), et
chaque rendu compte la part de son cadre hors de l'image (`coinsVides`) ; la case cochée, elle
réduit le cadre autour de son centre jusqu'à n'en montrer aucun (elle ne le déplace jamais), et
elle pose les matrices `UprightTransform_*` au rendu suivant (le moment est supposé). La recette
passe Upright complet et une perspective verticale forte (40) sur la photo RAW, puis un 3:2 au
centre, vérifie que le blanc pur de l'aperçu n'augmente pas et que le cadre se calcule sur la
grille, puis annule. Upright seul ne suffit pas à l'éprouver : il dépend de l'image. Constaté le
16 octobre 2026 sur la même copie, repassée en Adobe Color : Upright complet l'agrandissait
d'environ 5 % (`UprightTransform_2`) sans laisser de coin vide, et un 4:5 au centre n'avait rien à
éviter.

## Retouches locales

`add_mask` et `retouch_spots` reçoivent des positions dans l'image telle que la montre
`view_photo` (recadrée, tournée, orientée) ; `Geometrie.lua` les ramène dans le repère du fichier
entier, non recadré, avant l'orientation, en suivant le modèle du cadre ci-dessus. Les tables
(`Locaux.lua`) suivent celles du catalogue et des paramètres prédéfinis adaptatifs d'Adobe :

- `MaskGroupBasedCorrections` : une `Correction` par masque, avec ses réglages `Local*` de −1 à +1
  (exposition : ±1 = ±4 IL ; virage : teinte en degrés, saturation de 0 à 1 ; relevés dans
  `DevelopLocalizedCommon` de Lightroom Classic 15.6 : `LocalHue` ±1 = ±180°, `LocalGrain` ±1 =
  ±100, `LocalCurveRefineSaturation` de 0 à 100) ; sa courbe, `MainCurve`, `RedCurve`,
  `GreenCurve`, `BlueCurve`, un tableau de textes « x,y » (linéaire : « 0,0 », « 255,255 » ;
  comme dans le paramètre prédéfini d'Adobe « Adaptive - Sky/Blue Pop ») ; et ses
  `CorrectionMasks` : `Mask/Gradient` (`ZeroX/Y`, `FullX/Y`), `Mask/CircularGradient` (`Left`,
  `Top`, `Right`, `Bottom`, `Angle`, `Feather`), `Mask/RangeMask` de luminance (`LumRange` : quatre
  valeurs, écrites avec un point quelle que soit la locale), `Mask/Image` pour les masques IA
  (`MaskSubType` 1 sujet, 2 ciel, 0 avec `MaskSubCategoryID` 22 arrière-plan ou 5000x paysage,
  3 avec une catégorie pour les parties d'une personne) ;
- `RetouchAreas` : une entrée par tache, cercle `Mask/Ellipse` dont le rayon se rapporte au grand
  côté du fichier (constaté : un disque cloné reste un cercle) ;
- `RedEyeInfo` : une entrée par œil (pupille, taille, assombrissement ; les valeurs de détection
  de Lightroom sont remplacées par des moyennes relevées dans le catalogue).

Constaté dans Lightroom Classic 15.6 : les dégradés, la plage de luminance et les taches posés par
`applyDevelopSettings` sont rendus ; un masque IA posé ainsi ne l'est pas. Le module pose donc les
masques IA par un paramètre prédéfini du module (`presetsApres`), comme un paramètre prédéfini
adaptatif : Lightroom calcule pour la photo les masques IA qui n'ont pas d'empreinte. Ce
paramètre prédéfini **remplace** les masques de la photo au lieu de s'y ajouter (constaté en
version 1.3 : cinq masques IA, puis un sixième par un second `add_mask`, n'en laissaient qu'un ;
les six en un seul `add_mask` en donnaient six). Il porte donc la liste entière
(`masquesParPreset`) : les masques de la photo, puis ceux de la commande dans l'ordre demandé,
dégradés compris. Les masques de la photo y passent tels que Lightroom les a rangés : leurs
empreintes (`MaskDigest`, `InputDigest`…) sont celles de cette photo, et les retirer ferait
recalculer tous ses masques IA à chaque ajout. Sans masque IA dans la commande, la liste passe par
`applyDevelopSettings`, comme avant.

Copiés d'une photo à l'autre (`copier`), les masques perdent leurs empreintes (`sansCalculsIA`)
pour être recalculés ; s'il y a un masque IA, ils passent aussi par un paramètre prédéfini du
module, un seul pour toutes les photos de la copie, qui remplace leurs masques comme le veut la
copie. `essayer` passe par le même plan que `masquer`, et remet ensuite les masques d'avant par
`applyDevelopSettings`, empreintes comprises, comme l'annulation.

`RetouchAreas = {}` ne retire pas les taches : le module vide aussi l'ancienne forme `RetouchInfo`
(`aRemettre`), ce qui les retire.

Masques relevés le 17 octobre 2026 dans Lightroom Classic 15.6, faits à la main sur la copie
d'essai RAW et relus par `get_settings` avec `all_keys` :

- **Pinceau** : un composant `Mask/Aggregate` (nommé, « Pinceau 1 ») qui porte un `Mask/Paint` par
  trait, sans nom : `Radius`, `Flow`, `CenterWeight` et `Dabs`, une liste de textes : « r <rayon> »,
  « f <flux> », « h <dureté> » (comme `CenterWeight` ; absents à leur défaut), puis une touche par
  point, « d x y », ou « M x y » avec le masquage automatique (`DevelopLocalizedCommon` le confirme).
  Les positions sont des parts de l'image (repère du fichier) ; deux traits de rayons très
  différents (0,0136 et 0,0019) ont leurs touches espacées de 0,2 rayon. Le rayon se rapporte au
  grand côté du fichier, comme celui des taches : constaté par la recette du 17 octobre 2026, un
  trait dur d'exposition −2 IL, de rayon 0,02, posé par le module, a laissé une bande de 40 px de
  haut sur un aperçu de 1024 px (40,96 attendus ; 27 si le rayon se rapportait à la hauteur),
  centrée à 0,5 comme demandé. `add_mask` avec
  `kind: "brush"` reçoit des `strokes` (points dans l'aperçu, `size` en part de sa largeur,
  `feather` → `CenterWeight` = 1 − `feather`/100, `flow`), ramenés au fichier par `Geometrie.lua`
  et recalés comme les dégradés (`Locaux.touches`, `Locaux.pinceau`) ;
- **Objet** (Objets, au pinceau) : un `Mask/Image` de sous-type 0 sans catégorie (`kMLMaskSubType` :
  Object 0), avec `Gesture` = un `Mask/Paint` de rayon 0 et ses touches (« r », puis « d x y »),
  `ReferencePoint`, et ce que Lightroom calcule (`MaskDigest`, `InputDigest`, `Origin`,
  `FullMaskSize`, `WholeImageArea`, `ModelVersion`). `kind: "object"` reçoit un `box` (un trait le
  traverse dans sa longueur, de 15 à 85 %, d'un rayon du quart de sa petite dimension) ou des
  `strokes` ; le masque passe par un paramètre prédéfini du module comme les autres masques IA.
  Constaté le 17 octobre 2026 sur la copie d'essai : Lightroom calcule l'objet d'après un geste écrit
  par le module (`MaskDigest`, `Origin`…) quand le trait est fin et posé sur l'objet (rayon 0,007 le
  long d'une coque de bateau ; un cadre serré autour de lui, ou la zone d'intérêt de Vision, avec un
  trait de rayon 0,01) ; un trait de rayon 0,05 au milieu d'un cadre qui prenait surtout le fond n'a
  rien donné : `ErrorReason = 1`, sans `MaskDigest`. Un tel masque n'attend plus de calcul
  (`Locaux.masquesIAACalculer`), et `add_mask` le dit (`Locaux.masquesIAEnEchec`). Le mode
  rectangle range un `Mask/Polygon` dans `Gesture` ; constaté le 17 octobre 2026 : ses `Points`
  sont des tables `{X, Y}` (repère du fichier) ; ainsi, `kind: "object"` avec `box` pose les
  quatre coins du cadre (`Locaux.objetRectangle`) et Lightroom calcule l'objet entier (un érable
  désigné par son cadre, sélectionné seul, ciel et voisins intacts) ; des points en textes « x y »,
  en paires `{x, y}`, en « d x y » ou en un seul texte font rejeter le geste (`ErrorReason` 1, geste
  retiré : la simulation le refuse de même). Avec des `strokes` en plus, le cadre devient un trait
  fin, comme avant ;
- **Plage de couleurs** : `Mask/RangeMask` avec `CorrectionRangeMask = {Type = 1, Version = 3,
  ColorAmount, Invert, SampleType = 0, PointModels = {"c1 c2 c3 x y 0"}}`, et `CorrectionReferenceX`
  et `CorrectionReferenceY` au premier prélèvement. `cr_range_mask` de Camera Raw calcule ses limites
  en Lab (`ComputeLabLimits`, `LabMin`, `LabMax`). Étalonné le 17 octobre 2026 sur la copie d'essai
  XH2S0396 (ciel bleu, érable rouge, feuillage, herbe, chemin), en assombrissant la plage de 4 IL et en
  mesurant chaque zone : en faisant varier une valeur à la fois, la première suit la clarté, la
  deuxième l'axe vert-rouge, la troisième l'axe bleu-jaune (neutres vers 0,5). Le modèle retenu
  (`ModeleCouleur`) : L*/100, 0,5 + a*/100, 0,5 + b*/100, d'un Lab D50 de la couleur moyenne (7 × 7 px)
  de l'aperçu à 1024 px. Le ciel prélevé assombrit le ciel (luminance × 0,47) sans le reste (chemin
  × 0,81) ; l'érable prélevé, l'érable seul (× 0,54). Une échelle de 60 à 80 serre davantage les
  couleurs peu saturées (ciel × 0,42, chemin × 0,92 à 0,99), 128 à 200 prend mieux les couleurs
  saturées (érable × 0,44) mais déborde ailleurs : 100 est un compromis, et le modèle reste approché
  (mesuré sur le rendu sRGB, pas sur les données de Camera Raw). Le masque fait à la main relevé
  avant (« 0.018204 0.820061 0.667465 », un gris bleuté) ne cadre pas avec ce modèle : le pixel relevé
  était peut-être très sombre. `kind: "color"` reçoit `samples` (1 à 5 points) et `color_range`
  (`ColorAmount`, défaut 0,5) ; le serveur prélève sur l'aperçu de la seule photo visée ;
- **Plage de profondeur** : `Type = 3` et `DepthRange`, quatre valeurs de 0 à 1 comme `LumRange`
  (`Locaux.profondeur`). Constaté le 17 octobre 2026 sur une copie d'une photo Portrait d'iPhone 13
  Pro (HEIC à carte de disparité) : 0 à 0,35 n'assombrit que le bras tendu au premier plan, 0,6 à 1
  tout le reste ; 0 est le plus proche. `DepthMin`, `DepthMax` et `DepthFeather` (forme « M2 ») à la
  place de `DepthRange`, ou des valeurs de 0 à 100, font prendre l'image entière (la simulation les
  refuse) ; `Type = -1` revient au même que 3. Au premier aperçu après l'ajout de la photo, rien n'a
  changé : Lightroom n'avait sans doute pas encore chargé la carte (`negative:hasDepthMap()`). Le
  pinceau Affiner du flou d'objectif range ses traits dans `DepthBasedCorrections` (des
  `Mask/Aggregate` de `Mask/Paint`, `LocalCorrectedDepth` = −1 ou 1) ;
- **Couleur ponctuelle dans un masque** : `LocalPointColors`, un texte de 19 nombres « %f, %f, … »
  par couleur, dans l'ordre `SrcHue`, `SrcSat`, `SrcLum`, `HueShift`, `SatScale`, `LumScale`,
  `RangeAmount`, puis `HueRange`, `SatRange` et `LumRange` (`LowerNone`, `LowerFull`, `UpperFull`,
  `UpperNone`) : relevé dans `DevelopPointColorUtils.serializePointColors` et `DevelopLocalizedCommon`
  (`correctionKey = 'LocalPointColors'`) ; la variance va dans `LocalColorVariance`, un tableau de
  textes « %f », un par couleur, que le module pose avec elles. Constaté le 17 octobre 2026 : posé par le module sur un dégradé radial couvrant la photo,
  Lightroom le rend (teintes décalées, saturation retirée sur la plage de couleurs voisine).
  `add_mask` reçoit `point_colors` par masque, comme `apply_settings` ;
- une plage de luminance faite à la main porte `LuminanceDepthSampleInfo = "0 x y"` (le point
  cliqué) à côté de `LumRange` ; le module ne le pose pas.

Effets locaux (`add_mask` avec `effect`) : les paramètres prédéfinis de réglage local de
Lightroom, menu Effet du panneau Masque. Lightroom les range en fichiers `.lrtemplate` (une table
Lua, `type = "LocalizedAdjustmentPreset"`, `internalName`, `title`, `value`) : les six d'Adobe
dans l'application (`Develop.lrmodule/…/localized_presets`, `TeethWhitening.lrtemplate`…), copiés
sous leur nom français dans `~/Library/Application Support/Adobe/Lightroom/Local Adjustment
Presets/` avec ceux de l'utilisateur. `value` porte les réglages à l'échelle d'une correction (−1
à +1 ; `exposure2012 = 0.1` est le +0,40 IL du Blanchiment des dents) ; les anciennes clés
(`exposure`, `contrast`, `clarity`, `brightness`, versions de processus 2003 et 2010) sont
écartées, et une teinte sans saturation (`toningHue = 240`, `toningSaturation = 0`) aussi. Le
serveur (`EffetsLocaux.swift`) lit ces fichiers, met les réglages de l'effet dans `locaux` (ceux
d'`adjustments` les remplacent, réglage par réglage), nomme le masque d'après l'effet, et dit ce
qu'il pose (`remarques_serveur`) ; `amount` en règle l'intensité (`CorrectionAmount`). Le module
n'y voit que des réglages locaux.

Masques combinés (`add_mask` avec `combine`) : un masque porte plusieurs composants dans ses
`CorrectionMasks`, chacun avec son `MaskBlendMode`. Relevé dans le code de Lightroom Classic 15.6
(`DevelopLocalizedConstants` : `kMaskBlendModeEnum = {add = 0, subtract = 1}` ;
`DevelopModuleCommands` : une intersection devient une soustraction dont le composant est
inversé) : ajouter = `MaskBlendMode` 0, soustraire = 1, intersecter = 1 avec `MaskInverted`
basculé (A ∩ B = A − non B). Le premier composant est toujours ajouté. Le serveur envoie
`composants` (`mode` : `ajouter`, `soustraire` ou `intersecter`, la zone comme un masque,
`inverser`) ; le module (`Locaux.combiner`) range chaque composant ainsi, et le masque passe par
un paramètre prédéfini du module dès qu'un composant est un masque IA. `reglages` nomme chaque
composant avec son mode (« Architecture (soustrait) », « Haut (intersection) »). Constaté dans
Lightroom Classic 15.6 : un ciel moins le sujet, posé ainsi, garde `MaskBlendMode = 1` et chaque
composant IA reçoit son `MaskDigest` ; un ciel intersecté avec un dégradé radial n'éclaircit que le
ciel à l'intérieur du cercle, net sur la cuve et la ligne d'arbres.

### Recalage de la géométrie

Constaté dans Lightroom Classic 15.6, sur une copie virtuelle d'un RAW de X-H2S (XF16-55 à 20 mm,
profil d'objectif « Camera Settings » embarqué dans le RAF, 6240 × 4160) : Lightroom range les
positions des taches (`RetouchAreas`), des yeux rouges (`RedEyeInfo`) et des dégradés
(`MaskGroupBasedCorrections`) dans l'image d'**avant** la correction de profil d'objectif. Mesure :
corrections posées sur un mur et un plancher uniformes, centre de la zone changée dans un zoom à
100 % ; profil actif, écart de 5 px au plus en haut près du centre, de −19 à −26 px au bord gauche,
de +24 à +25 px au bord droit (vers l'extérieur) ; profil coupé (`LensProfileEnable = 0`), 0 px
partout (2 au plus). Même écart pour les trois sortes de positions. Upright et la perspective sont
supposés suivre la même règle (le module avertissait déjà d'un décalage possible).

Le module ne peut pas calculer cette déformation (profil embarqué, propre à l'appareil). Le
serveur la mesure : la commande `geometrie` dit pour chaque photo si une correction géométrique
est active (profil d'objectif avec une distorsion non nulle, distorsion manuelle, Upright,
perspective) et son empreinte (dimensions, orientation et tous les réglages `LensProfile*`,
`LensManual*`, `Perspective*`, `Upright*`, hachés). Avec `rendre`, elle rend la photo deux fois
sans recadrage, à 2048 px : telle quelle, puis sans ces corrections (`LensProfileEnable = 0`,
Upright et perspective à zéro), et la remet comme avant ; comme une comparaison, l'Historique
garde les étapes « Claude · recalage ». `Recalage.swift` compare les deux rendus par corrélation
normalisée de petites zones, du grossier (256 px, recherche à ±15 % pour Upright) au fin (2048 px,
au dixième de pixel), écarte les zones trop uniformes et les motifs répétés, puis ajuste un
modèle physique sur les zones fiables (homographie, puis distorsion radiale autour du centre,
k1 et k2 ; Levenberg-Marquardt, sans les zones aberrantes). Le modèle, évalué sur une grille de
17 × 12 nœuds posée sur l'image corrigée, part dans `recalages` (par photo : `colonnes`, `lignes`,
`x`, `y`, `empreinte`) avec `masquer`, `retoucher` et `essayer`. `Geometrie.point` passe le cadre
et l'orientation, puis interpole la grille sur l'image affichée entière. Le module refuse une
grille dont l'empreinte n'est plus celle de la photo, et le dit (« sans recalage ») ; recalée, une
position donne la remarque « Positions recalées … (déplacement jusqu'à N px) ».

Mesuré le 17 octobre 2026 (`mcp-developpeur --recalage <id>` : zones fiables, écart du modèle aux
zones mesurées, moyen, maximal et à moins de 12 % d'un bord, en pixels du fichier), sur une copie
d'un RAW de X-H2S (XF16-55, 6240 px) : profil d'objectif seul, 143 zones sur 204, écart moyen
0,5 px et maximal 2,7 px ; Upright automatique, 148 zones, 0,7 et 2,9 px ; Upright complet, 136
zones, 0,6 et 2,8 px ; perspective verticale forte (40), 87 zones seulement (la perspective vide
une partie de l'image), 2,3 px en moyenne, 6,1 px au plus, 5,6 px près des bords. Le modèle
(homographie et distorsion radiale) suffit pour Upright ; l'écart d'une perspective forte, un
dixième de pour cent de la largeur, reste sous le rayon d'une tache : pas de modèle plus souple
pour l'instant.

Le serveur garde les grilles en mémoire par photo et empreinte (un échec aussi : image trop
uniforme), en recalcule huit au plus par commande, et ne demande rien pour des masques sans
position (IA, plage de luminance). Les positions relues (`reglages`) restent dans le repère de
Lightroom.

Noms : le serveur nomme chaque masque « Claude · » suivi du nom donné (ou du type), et le module
nomme chaque étape « Claude · » suivi de `etape`. Un nom qui commence déjà par « Claude · » (en
majuscules ou non, même répété) perd ce préfixe avant : il n'est jamais doublé.

## Proposition, comparaison et paramètres prédéfinis

`essayer` applique un plan (retouche, masques ou taches), rend l'aperçu, puis réapplique les
valeurs d'avant ; rien n'est mémorisé ni journalisé, mais l'Historique garde les deux étapes.
`apercu` avec `comparer` applique de même l'état d'avant le temps d'un rendu. Les paramètres
prédéfinis de l'utilisateur s'appliquent par `applyDevelopPreset`, avant les réglages de la même
commande. `save_preset` écrit un fichier XMP de paramètre prédéfini (`PresetXMP.swift`) dans
`~/Library/Application Support/Adobe/CameraRaw/Settings/Claude` : ceux que crée
`addDevelopPresetForPlugin` restent invisibles dans le panneau. Masques, taches et couleurs
ponctuelles n'y vont pas.

## Mesures

`Mesures.swift` mesure l'aperçu JPEG réduit à 512 px : L* (moyenne, centiles, histogramme par
tranches de 10), écrêtage (une composante ≥ 254, blanc pur, trois composantes ≤ 2), contraste
(p95 − p5), chroma moyenne, part très saturée (C* > 60), dominante a*/b* des tons presque neutres
(C* < 15). La comparaison avec une référence chiffre l'exposition par le rapport des luminances
médianes (en IL) et donne seulement un sens pour la couleur, le contraste et la saturation.
L'écrêtage se donne aussi canal par canal (≥ 254).

`Detail.swift` mesure la luminance à 1024 px de grand côté (en pleine résolution pour un zoom) :
netteté de 9 zones (95e centile de la valeur absolue du laplacien) et bruit (écart type du résidu
pixel − moyenne 3 × 3 dans les 10 % de blocs 16 × 16 les plus calmes, hors aplats saturés ; aussi
dans les aplats sombres). Seuils relevés sur des aperçus réels de 1024 px : une photo nette donne
de 45 à 150 selon son contenu, un flou gaussien de rayon 1,5 px de 12 à 26, un flou marqué moins
de 6 (lecture : moins de 15 floue probable, plus de 35 nette) ; une image propre donne un bruit de
0,2 à 0,5, des ombres relevées vers 1, un bruit ajouté de ±6 niveaux de 1 à 2 (lecture : moins de
0,6 faible, plus de 1,5 fort). `analyze_photos` rend donc ses aperçus à 1024 px.

`AnalyseVision.swift` passe l'aperçu à Vision (macOS) : visages et repères (pupilles, largeur
des yeux), qualité de capture de chaque visage, note esthétique (macOS 15 et plus), saillance par
attention. Les positions sont ramenées au repère de `view_photo` (Vision compte depuis le bas).
Le rayon d'une correction d'yeux rouges vaut 15 % de la largeur de l'œil, une estimation. Les
empreintes (`VNGenerateImageFeaturePrintRequest`) donnent la ressemblance : relevé 0,10 pour la
même photo développée autrement, 0,44 pour la même photo recadrée, de 0,8 à 1 entre photos
différentes ; sous 0,5, même scène (groupes de proche en proche). La meilleure d'un groupe : la
plus nette, puis la note esthétique et le meilleur visage.

Horizon : `VNDetectHorizonRequest` ne voyait pas l'horizon pourtant net d'une photo de bord de
mer, et donnait −1,9° sur une photo mesurée à 0,4° ; un histogramme des orientations de contours
se laisse prendre par les lignes de perspective (+3,5° au lieu de 0,4°). D'où `measure_angle`
(`Lignes.swift`) : Claude désigne une ligne vraiment droite, le serveur cherche le contour le plus
marqué de colonne en colonne (ou de rangée en rangée pour une verticale) dans une bande autour du
segment, au sous-pixel, et ajuste une droite en écartant les points aberrants. Sur des aperçus
tournés de +2° et −3°, l'écart mesuré est juste à 0,02° (crête d'une chute) et 0,2° (berge).
`crop_angle` = l'angle de recadrage actuel moins l'inclinaison (positif : sens antihoraire).

L'aperçu est un JPEG sRGB : une couleur que Lightroom garde dans son espace de travail (ProPhoto
RVB dans Développement) mais qui sort du sRGB y paraît écrêtée sur un canal. Une photo en mode HDR
(`HDREditMode`) y est mesurée dans son rendu SDR. Les coins vides laissés par Upright ou la
perspective comptent comme blanc pur (voir Recadrage).

## Flou d'objectif et traitements calculés : relevé du catalogue

Relevé dans le catalogue (Lightroom fermé, lecture seule) le 16 octobre 2026 :

- le flou d'objectif est une table `LensBlur` : `Active`, `BlurAmount` (0 à 100), `BokehAspect`,
  `BokehRotation`, `BokehShape`, `BokehShapeDetail`, `CatEyeAmount`, `CatEyeScale`, `FocalRange`
  (« début du fondu, début de la zone nette, fin de la zone nette, fin du fondu », profondeur de 0
  à 100, fondus de 80 : « −80 0 55 135 »), `FocalRangeSource` (1 : sujet), `HighlightsBoost`,
  `HighlightsThreshold`, `ImageOrientation`, `SampledArea`, `SampledRange`, `SphericalAberration`,
  `SubjectRange`, `Version` = 1 ; Lightroom y ajoute la carte de profondeur calculée
  (`DepthMapInfo`, empreintes). Le module pose la table par un paramètre prédéfini du module
  (`Locaux.flouObjectif`), comme les masques IA, et l'aperçu attend `DepthMapInfo`. Sur un flou
  actif, ce que la demande ne donne pas reste (`lens_blur` avec `bokeh` seul ne change que la
  forme). Zone nette manuelle (`near`, `far`) : le module écrit `FocalRangeSource = 0` avec
  `FocalRange` et `SubjectRange` ; constaté le 17 octobre 2026 sur une copie d'un RAW de X-H2S
  (un flamant au premier plan) : Lightroom garde la zone et range `FocalRangeSource = 3` après le
  calcul ; zone proche (0 à 30), le flamant reste net, zone lointaine (70 à 100), il se brouille et
  le fond se raffermit ;
- formes du bokeh, relevées le 17 octobre 2026 dans Lightroom Classic 15.6 (`kLensBlurBokehPresetNames`
  d'`AgDevelopParams` : Circle 0, SoapBubble 1, Blade 2, Ring 3, Anamorphic 4 ; la table de
  `cr_lens_blur_params::ApplyBokehPreset` dans Camera Raw, où `setLensBlurBokeh` aboutit) et
  recoupées avec les paramètres prédéfinis d'Adobe « Adaptive - Blur Background » (Circle, Bubble,
  Geometric, Ring, Oval) : chacune pose `BokehShape`, `BokehShapeDetail`, `BokehAspect`,
  `BokehRotation`, `SphericalAberration` et `CatEyeScale = 100`, sans toucher à `CatEyeAmount`
  (l'effet « œil de chat », 80 dans les variantes « Swirl » d'Adobe). Cercle : tout à 0 ; bulle de
  savon : `SphericalAberration` 80 ; 5 lames : `BokehShapeDetail` 1, `BokehRotation` 50 ; anneau :
  `BokehShape` 1, `BokehShapeDetail` 3, `SphericalAberration` 25 ; anamorphique : `BokehAspect`
  −100. Le serveur tire ces champs de son catalogue (`DevelopCatalogue.bokehShapes`) ; le module
  les écrit dans la table, par le même paramètre prédéfini (posés ainsi plutôt que par
  `setLensBlurBokeh`, qui exige le module Développement). Constaté équivalent en 2.3 (18 octobre
  2026, copie d'un RAF de X-H2S, flou actif) : `setLensBlurBokeh('SoapBubble' | 'Blade' | 'Ring' |
  'Anamorphic' | 'Circle')` range exactement les champs du catalogue du serveur, et dans l'autre
  sens `getSelectedLensBlurBokeh` reconnaît (« Ring », « Anamorphic ») une forme posée par le
  module ;
- la réduction du bruit et la super résolution sont des filtres « Enhance » de `FilterList`,
  avec les données d'image calculées (`ImageGroup`, empreintes, `Table_…`) et de gros fichiers
  dans `Lightroom Catalog.lrcat-data` : le résultat d'un calcul, qu'un module ne peut pas
  fabriquer. Les « détails bruts » n'apparaissent dans aucune photo du catalogue.

## Débruitage, détails bruts, super résolution (`ameliorer`)

Le module les lance par `LrDevelopController`, comme un clic dans le panneau Amélioration.
Relevé dans le code de Lightroom Classic 15.6 (`LrDevelopController.lua` et `DevelopEnhance.lua`,
livrés compilés dans l'application et lus en lecture seule) :

- `setEnhance(nom, actif, intensite)` : `nom` = `denoise`, `rawDetails` ou `superRes` ; intensité du
  débruitage de 1 à 100, vérifiée seulement si elle est donnée. Hors du module Développement, refus
  (« this operation can be executed only when the Develop module is opened. ») ; si
  `<nom>Enabled` est faux, refus avec la raison de Lightroom (`<nom>InfoText`). Sinon le calcul se
  fait en arrière-plan (`runEnhanceInBackground`), et son résultat n'arrive dans `FilterList` qu'à
  la fin (étape d'historique de Lightroom) ;
- `getEnhancePanelState()` : `denoiseState`, `rawDetailsState`, `superResState`, `denoiseAmount`,
  `<nom>Enabled`, `<nom>InfoText`, `enhanceNeedsUpdate` ; nil hors du module Développement ;
- `changeDenoiseAmount(intensite)` : de 1 à 100, seulement si le débruitage est actif ;
- `toggleEnhance(nom, intensite, rappel, argument)` bascule l'état ; le module ne s'en sert pas.

Ces fonctions agissent sur la photo affichée dans le module Développement : le module la
sélectionne seule (`catalog:setSelectedPhotos` ; avec plusieurs photos sélectionnées et la
synchronisation automatique, Lightroom pourrait traiter toutes les photos — supposé, d'après les
curseurs que MIDI2LR règle, à vérifier), passe au module Développement
(`LrApplicationView.switchToModule`), laisse 1,5 s au module Développement pour charger la photo
(avant, `getEnhancePanelState` donnerait l'état de la précédente), attend que Lightroom
l'affiche (10 s au plus ; une photo hors du film fixe fait d'abord afficher son dossier, comme
`montrer`, et la source d'avant revient après ; introuvable, elle est refusée avec un message), lance
chaque traitement l'un après l'autre et attend qu'il soit rangé : l'état voulu dans le panneau et
`FilterList` changé, deux lectures de suite (3 minutes au plus par traitement, mesurées à
l'horloge ; passé ce délai, une remarque). Il remet ensuite le module et la sélection d'avant.
Les appels se font hors de `withWriteAccessDo` (Lightroom écrit lui-même son étape
d'historique ; la simulation le refuse) ; seules les écritures du module (instantané, mémoire,
journal) passent par `ecrire`. Un seul traitement calculé à la fois : une deuxième commande
(Claude qui réessaie après un délai dépassé, le menu Revenir) est refusée tant que le premier
tourne.

L'état d'avant des seuls traitements que Claude change (`denoise`, `rawDetails`, `superRes`,
`denoiseAmount`) va dans la mémoire sous la clé `Amelioration`, qui n'est pas un réglage. Elle est
écrite **avant** le calcul (sinon une écriture finale qui échoue, ou un calcul fini après le délai,
laisserait la photo traitée sans étape à annuler), et remise telle qu'elle était si Lightroom n'a
lancé aucun traitement ; le journal suit le calcul. `annuler` et `revenir` la remettent par les
mêmes fonctions, d'abord ce qui doit être retiré, puis ce qui doit être remis, avant d'écrire. Si
Lightroom ne suit pas, la photo reste telle quelle, avec la raison (le menu Revenir l'affiche),
et sa mémoire est gardée. `undo_last` et `revert_to_original` attendent donc jusqu'à 11 minutes.
Une comparaison (`apercu` avec `comparer`) ne défait pas un traitement calculé : elle le dit, et
refuse si la retouche à comparer n'est que cela. `reglages` donne l'état d'amélioration de la
photo seulement si elle est affichée dans le module Développement (seul cas où Lightroom le dit).
Il faut Lightroom Classic 15.3 ou plus récent (le module le vérifie). Pas de proposition
visuelle : le calcul est trop long pour être fait puis défait.

Constaté dans Lightroom Classic 15.6, sur une copie virtuelle d'un RAW de X-H2S (6240 × 4160) :

- débruitage à 40 en 7,9 s, son annulation en 2,8 s ; dans la recette, débruitage puis
  annulation en 10,9 s ;
- le débruitage coche aussi les détails bruts, et les retire avec lui : la mémoire garde ce que
  Lightroom change de lui-même avec les traitements demandés, pour le remettre avec eux ;
- détails bruts seuls : 4,4 s en tout (chargement de la photo compris), annulation en 2,7 s ;
  filtre intitulé « Raw Details » ;
- super résolution seule : 7,7 s en tout ; elle coche aussi les détails bruts ; filtre intitulé
  « Super Resolution » ; `reglages` donne alors des dimensions doublées (12480 × 8320), et un zoom à
  100 % (`apercu` avec une zone) se rend normalement, en 3 s. Les titres complets (avant le « = »)
  n'ont pas été relus ;
- tant que le débruitage ou la super résolution est actif, Lightroom refuse de toucher aux détails
  bruts (`rawDetailsEnabled` faux, `rawDetailsInfoText` : « Appliqué automatiquement lors de
  l'utilisation de la super-résolution ou de la réduction de bruit. ») : l'annulation de la 1.5,
  qui les retirait en premier, échouait après une super résolution. Le module lance donc les
  traitements dans l'ordre débruitage, super résolution, détails bruts, ne relance pas ce que
  Lightroom a déjà fait de lui-même, et laisse les détails bruts qu'un traitement resté actif
  impose (remarque à Claude s'il demandait de les retirer) ;
- `<nom>Enabled` vaut `negative:isFinalQuality() and …` (relevé dans `DevelopEnhance`) : tant que
  la photo n'est pas chargée en pleine qualité, les trois sont faux et `<nom>InfoText` n'est que la
  description du traitement (« Double la résolution de l'image… »). Constaté au premier passage au
  module Développement après la relance de Lightroom, sur une photo en super résolution :
  l'annulation était refusée après les 1,5 s de chargement, et passait au deuxième essai, en 2,8 s.
  Le module attend donc qu'un traitement au moins soit possible (20 s au plus) avant de juger ce
  que Lightroom permet ; passé ce délai, il le dit (original hors ligne, supposé) ;
- le résultat est un seul filtre de `FilterList.Filters` : `Name = "Enhance"`, `FilterID = 1`,
  `Title = "$$$/CRaw/Filter/Title/Denoise=Denoise"`, `CompressedSettings` et sa table `Table_…`,
  `Images` (empreintes, données d'image), bornes source et destination. `reglages` en tire
  `filtres_calcules` (« Denoise ») pour toute photo ; l'état détaillé (intensité) n'est donné que
  pour la photo affichée ;
- une photo absente du film fixe (autre dossier ou collection) n'est pas sélectionnée par
  `setSelectedPhotos` : Lightroom ne l'affiche pas, et le module répond au bout de 10 s qu'il faut
  l'afficher dans le film fixe, vue remise.

## Suppression des distractions : relevé du SDK

Relevé le 17 octobre 2026 dans le code de Lightroom Classic 15.6 (`LrDevelopController.lua`,
`DevelopDustManualRemove.lua`, `DevelopDustDistractionRemoval.lua`, `DevelopDustOverlay.lua`,
`DevelopDustPanel.lua`, `AgCameraRawController.lua`, compilés et lus en lecture seule, et
`strings` du binaire de Camera Raw). Ces fonctions manquent à la référence du SDK (à jour jusqu'à
la 14.1). Ce qui est marqué « supposé » reste à vérifier dans Lightroom ; rien n'en est écrit dans
le module, sauf le mode « Supprimer » de `retouch_spots` et `RemoveAreas` (ci-dessous).

Les fonctions refusent par `assert` (une erreur Lua, à prendre par `LrTasks.pcall`) avec l'un de
trois messages : « this operation can be executed only when Develop module is active. »,
« this operation can be executed only when Remove-tool is opened in Develop module » (l'outil
Supprimer ouvert, `goToRemove`), « this operation can be executed only when the Develop module is
opened. ».

**Taches de l'outil Supprimer.** Relevé sur deux taches génératives faites à la main (outil Supprimer,
détection d'objet, au pinceau) : rangées dans `RemoveAreas`, `SpotType = 'heal_patchmatch'`,
`fill_method = 'firefly'`, `Method = 'poisson'`, `SourceState = 'sourceAutoComputed'`, `Masks` = un
`Mask/Image` (calculé, `MaskDigest`) dont le `Gesture` est le trait de pinceau, et le résultat du
calcul : `IngestInfo`, `pm_version`, `pm_patch`, `pm_patch_mask`, `pm_patch_variations`,
`pm_clio_model_version` (« clio-erase-2.0… »), `pm_search_*`, `pm_target_*`, `pm_remap_info_*`… Une
tache sans IA générative n'a pas pu être relevée (Lightroom ne l'a pas rangée pendant l'essai).
`retouch_spots` offre `mode: "remove"` : une tache ronde `heal_patchmatch`, `fill_method =
'patchmatch'`, `Method = 'poisson'`, sans résultat. Constaté par la recette du 17 octobre 2026 :
Lightroom en calcule le remplissage par `updateAISettings` (`pm_patch`, `pm_version`, `pm_search_*`,
`pm_target_*`, `pm_remap_info_*`, sans `pm_clio_model_version` : pas d'IA générative), et retire
alors `fill_method` (patchmatch par défaut) ; `sourceX` et `sourceY` passent à 0.
`Locaux.calculsEnAttente` compte une telle tache sans `pm_patch`. Code :
elles se rangent avec `SpotType = 'heal_patchmatch'` (relevé :
« invalid spot type. Allowed values: 'heal_patchmatch', 'heal', 'clone'. ») ; ce qui les dit
génératives est `fill_method` (en minuscules) : `'patchmatch'` sans IA générative, `'firefly'` pour
la suppression générative, qui passe par les serveurs d'Adobe. `Method` ne connaît que `poisson` et
`gaussian` (binaire). Une tache `heal_patchmatch` porte aussi ses paramètres de remplissage
(`pm_version`, `pm_method`, `pm_patch…`, supposé d'après le binaire) et des tables d'images :
écrite sans eux, Lightroom doit la recalculer (« Missing image tables for spot. »,
`isUpdateNeededForCASpots` ; le moment est à vérifier). Une tache à détection d'objet a
`What = 'Mask/Image'` dans `Masks`. Nouvelle clé : **`RemoveAreas`**. Quand elle existe, Lightroom
la lit avant `RetouchAreas` (`getRetouchKey`) et en dérive `RetouchAreas` (sans les taches
`Mask/Image`) et `RetouchInfo` (les cercles) ; une liste vide efface les trois. Le module ajoute
donc ses taches à `RemoveAreas` aussi quand la photo en porte une, et la remet à l'annulation.
Constaté en 2.3 (18 octobre 2026) sur une copie d'un RAF de X-H2S : une tache Supprimer faite à la
main (objet détecté, IA générative décochée) n'est que dans `RemoveAreas` (`Mask/Image` avec son
geste `Mask/Paint`, `heal_patchmatch`, `poisson`, `pm_…`), sans `RetouchAreas` ; une tache Supprimer
de Claude y ajoute la sienne et crée `RetouchAreas` (la sienne seule) ; `undo_last` rend
exactement l'état fait à la main (`--dump` identique), la tache de l'utilisateur gardée. Préférences de l'outil (`getRemovePanelPreferences`,
`setRemovePanelPreferences`, sans condition) : `newSpotType`, `brushSize` (1 à 100),
`brushFeather` (0 à 100), `useGenerativeAI`, `detectObjects`, `toolOverlay`, `visualizeSpots`,
`visualizationThreshold`. `getAllSpots(mode)` (module Développement) rend une copie des taches
(`RemoveAreas`, sinon `RetouchAreas`) ; `getSelectedSpotParams` et `setSelectedSpotParams` (outil
Supprimer ouvert) lisent et remplacent la tache sélectionnée entière.

**Passants.** `detectDistractingPeople()` (outil Supprimer ouvert) ne fait qu'ouvrir la section
Personnes ; la détection suit en arrière-plan (modèle local `background_people_v1`), sans rappel
de fin (supposé : `countAllSpots('distractingPeopleRemoval')` pour l'attendre).
`applyRemovalOnDetectedDistractingPeople(rappel, argument)` refuse « Detected distracting people
are already removed. » ou « No distracting people spots are present for removal. », sinon lance la
suppression en arrière-plan (fenêtre de progression annulable) et appelle `rappel(argument)` à la
fin. Le résultat est un filtre `remove_people` de `FilterList` (et `EnableDistractionRemoval`), pas
une tache. Le remplissage passe par le service génératif d'Adobe (« clio », supposé d'après le
binaire et les journaux d'erreurs) : il demande le réseau et un compte qui y a droit.

**Reflets.** `toggleReflectionRemoval(intensite, qualite, rappel, argument)` (module Développement)
pose ou retire le filtre `dereflect` de `FilterList` : intensité de −100 à 100 (défaut 100),
qualité `'preview'`, `'standard'` ou `'best'`. Il ne fait rien, sans erreur, si la photo n'est pas
chargée en pleine qualité ou si Lightroom ne le permet pas pour elle (`supportsDereflectFilter`).
Le calcul se fait en arrière-plan, sur ce Mac (modèle `dereflect`), et appelle `rappel(argument)`
à la fin. `changeReflectionRemovalAmount(n)` et `changeReflectionRemovalQuality(q, …)` le règlent ;
`getReflectionRemovalPanelState()` (outil Supprimer ouvert) rend `checkboxState`, `amount`,
`quality`, `enabled` (pleine qualité) et `isSupported`. La fenêtre « Mises à jour IA
recommandées » prévoit « Update Removal: Reflections » et « Update Removal: People ».

### Suppression des reflets (`supprimer`, `remove_distractions`)

Le module lance la suppression des reflets comme le débruitage (`Suppression.lua`) : la photo
affichée, seule sélectionnée, dans le module Développement (`afficherEnDeveloppement`), le panneau
Reflets lu le temps de savoir si Lightroom la prend en charge (`goToRemove`,
`getReflectionRemovalPanelState` : `isSupported`, `enabled`, puis l'outil d'avant remis par
`selectTool`), `toggleReflectionRemoval(intensite, qualite, rappel)` hors d'une écriture, puis
l'attente de l'état voulu (`hasFilterWithName('dereflect')`) et de `FilterList` changé, deux
lectures de suite, trois minutes au plus ; la vue d'avant est remise. Un seul traitement calculé à
la fois, débruitage compris (`avecVerrou`). L'état d'avant va dans la mémoire sous la clé
`Suppression` (`reflets`, `intensite`), qui n'est pas un réglage (la simulation la refuse dans
`applyDevelopSettings`), écrite avant le calcul et remise telle qu'elle était si rien n'a changé ;
`annuler` et `revenir` la remettent par les mêmes appels (`Annulation.remettreCalcules`, avec la clé
`Amelioration`). Une comparaison (`apercu` avec `comparer`) ne la défait pas, et le dit. Les passants
restent à faire à la main (remplissage génératif d'Adobe).

Constaté le 17 octobre 2026 dans Lightroom Classic 15.6, sur une copie d'essai RAW de X-H2S :

- le filtre rangé : `Name = 'Reflections'`, `FilterID = 3`, `Title =
  '$$$/CRaw/Filter/ReflectionRemoval/FilterPanelTitle=Reflection Removal'`, `CompressedSettings`, sa
  table et ses `Images` (empreinte `GlobalInputDigest`, `BlendParams`, `Opacity`) ;
  `EnableDistractionRemoval` vaut `true` sur toutes les photos, avec ou sans filtre. `reglages` en
  tire `filtres_calcules` (« Reflection Removal ») ;
- l'intensité est rangée dans le premier `BlendParams`, une fraction « n/d » :
  « 858993459/1073741824 » = 0,8 pour 80 (`Suppression.intensite`) ;
- pose à 80 en 15 s au premier appel (photo à charger), à 50 en 5 s ; annulation en 2,9 s ;
- `changeReflectionRemovalAmount(50)` sur un filtre posé ne change rien au filtre rangé (rien après
  3 minutes) : pour une autre intensité, le module retire le filtre (`resetFilterWithName`), puis le
  repose (50 → 80 en 6 s, l'annulation revient à 50) ;
- une photo absente du film fixe est refusée, comme pour le débruitage (après une relance de
  Lightroom, la source affichée peut avoir changé : `show_photo` l'y remet).

## Aperçus et masques IA

Les masques IA posés par un paramètre prédéfini du module n'ont pas encore leur calcul
(`MaskDigest`) : Lightroom le fait peu après, sur la photo affichée. Un aperçu exporté avant ouvre
la fenêtre « Mises à jour IA recommandées », qui attend un clic et bloque la réponse : constaté
dans Lightroom Classic 15.6, deux `view_photo` ont dépassé le délai de Claude ainsi (les 60 s de
Claude Desktop, voir Délai des appels d'outils). Sur une
photo qui n'est pas affichée, Lightroom ne calcule rien de lui-même (aucune empreinte après 20 s)
et c'est l'exportation qui calcule, sans fenêtre (un masque ciel : 10 s). Avant d'exporter un
aperçu de la photo active, `rendre` attend donc que tous les masques IA aient leur `MaskDigest`
(et un flou d'objectif actif sa carte de profondeur), une dizaine de secondes au plus ; passé ce
délai, il exporte quand même, et la fenêtre attend la réponse de l'utilisateur. Si les masques
ont leur empreinte après l'exportation (« Exporter » cliqué, case « Mettre à jour » cochée), la
réponse n'a pas d'`a_savoir` ; sinon elle en porte un. Pour une autre photo, il n'attend pas. Un
profil adaptatif marqué « à mettre à jour » n'est pas attendu non plus (Lightroom ne le calcule
pas de lui-même) : l'exportation ouvre la fenêtre, pour la photo affichée comme pour une autre
(voir Profil, Profils adaptatifs). Depuis la 1.8, `updateAISettings` calcule tout cela dès la
retouche et avant chaque rendu (ci-dessous) : relevé le 19 octobre 2026, 682 calculs notés dans le
journal du module, aucun en échec, aucune mise à jour faite pendant une exportation, et les
recettes de la 1.8 à la 2.5 ont vérifié chaque aperçu sans clic. La fenêtre ne s'ouvre plus que si
Lightroom n'a pas pu calculer : des modèles IA pas téléchargés (`updateAISettings` ne fait rien,
sans erreur). Elle attend alors l'utilisateur, car le module ne peut pas répondre à une fenêtre de
Lightroom (le SDK n'y a pas accès) ; la remarque de la retouche et la réponse d'attente du serveur
(`FileOutils`, à 50 s) disent quoi y répondre.

### Calcul par le SDK (`updateAISettings`)

Relevé le 17 octobre 2026 dans le code de Lightroom Classic 15.6 (`LrPhoto`, `LrCatalog`,
`SdkApplyDevelopPreset`, `AgCameraRawBatchPixelMaskUpdate`, `DevelopBackgroundOperations`,
`AgExportSession`, compilés, lus en lecture seule) :

- `photo:updateAISettings()` (SDK 13.3) appelle `updatePixelsMasksInBackground`, le même calcul
  que la case « Mettre à jour les photos concernées » de la fenêtre « Mises à jour IA
  recommandées » à l'exportation : masques IA, profil adaptatif (`aiLook`), flou d'objectif, outil
  Supprimer, suppression des distractions, débruitage, détails bruts, super résolution. Elle ne
  vérifie ni l'écriture ni la photo affichée, ne lève aucune erreur et ne rend rien ; ses fenêtres
  de confirmation sont sautées (pas de photo principale). Elle attend son tour dans la file des
  opérations IA, puis la fin du calcul (synchrone), et écrit par une commande de Lightroom (étape
  « Mettre à jour les paramètres IA », annulable) : à appeler hors de `withWriteAccessDo`. Sans
  rien à mettre à jour, elle ne fait rien ; si les modèles IA ne sont pas téléchargés, Lightroom
  propose le téléchargement et ne fait rien d'autre, sans erreur. Certaines mises à jour demandent
  Internet (suppression générative).
- `photo:needsUpdateAISettings()` rend vrai s'il reste à calculer (`aiUpdateRequiredStatus`, sinon
  les boutons « Mettre à jour » du négatif) ; `catalog:updateAISettings(photos)` fait la même
  chose pour plusieurs photos.
- Le 4ᵉ argument d'`applyDevelopPreset` (`updateAISettings`) ne vaut que pour les paramètres
  prédéfinis de style d'Adobe ; pour un paramètre prédéfini créé par `addDevelopPresetForPlugin`,
  il est ignoré (`applyPresetSettings`, puis `kAIUpdateCalculate`).

Constaté par la recette du 17 octobre 2026 (Lightroom Classic 15.6, copie d'essai RAW) : Adaptive
Color posé par un paramètre prédéfini du module, puis `updateAISettings`, est calculé aussitôt
(`AILookData`), sans fenêtre ; un masque IA ciel, un objet et la carte de profondeur d'un flou
d'objectif de même. Sous Adaptive Color : après une tache, puis un flou d'objectif,
`updateAISettings` recalcule le profil (`InputDigest` et `AILookData` changés à chaque fois) ;
après une rotation (`crop.angle` 2°), il ne fait rien, et le profil reposé de force par un
paramètre prédéfini du module (sa Look, `AILook = {Active = true}`, comme « Mettre à jour »), puis
calculé, redonne la même `InputDigest` et la même `AILookData` : Lightroom calcule le profil sur la
photo entière, avant le recadrage, qu'une rotation ne change pas (d'où, le 16 octobre, pas de
fenêtre à l'exportation après une rotation). Après le flou, un premier passage de
`updateAISettings` laissait un calcul en attente : le module en fait un second.

Le module appelle donc `updateAISettings` après l'écriture (`Ecriture.calculerIA`), pour chaque
photo dont la retouche touche un calcul (paramètre prédéfini, masques, profil, flou, taches, cadre,
géométrie) et qui en a un en attente (`Locaux.calculsEnAttente` ou `needsUpdateAISettings`), ou
qui porte un profil adaptatif quand la retouche touche ses taches, sa rotation ou son flou (l'aide
d'Adobe demande alors de le mettre à jour) : la remarque dit s'il a été recalculé (`InputDigest`
changé), inchangé par une rotation, ou laissé par Lightroom (« Mettre à jour » à la main). Une commande y passe 90 s au plus ; les photos suivantes attendent le
rendu, et la remarque le dit. Un calcul qui ne se fait pas (modèles absents) laisse la remarque, et
la suite d'avant prend le relais : `rendre` appelle d'abord `updateAISettings` pour ce qui reste
(`calculerAvantRendu`), puis attend ; si la fenêtre s'ouvre encore, elle attend la réponse de
l'utilisateur, que la remarque et la réponse d'attente du serveur lui indiquent (« Exporter », case
« Mettre à jour » cochée). `appliquer`, `masquer`,
`retoucher`, `copier`, `recadrer` et `essayer` passent par là ; `masquer` ne dit plus `a_savoir`
quand ses masques IA sont calculés. Depuis la 2.6, le module demande Lightroom Classic 13.3
(`LrSdkVersion` et `LrSdkMinimumVersion` de `Info.lua`) : Lightroom ne le charge pas avant ; le
chemin sans `updateAISettings` reste dans le code et la simulation (`S.miseAJourIA = false`).
La simulation (`Simulation.lua`) offre les deux fonctions (`S.miseAJourIA`), les refuse dans une
écriture (supposé), et recalcule un profil adaptatif devenu périmé par une tache ou un flou
(constaté ; `S.lookFige` pour un Lightroom qui ne le ferait pas), pas par une rotation. La recette
vérifie le critère de la 1.8 : un masque ciel et un profil adaptatif posés, puis un aperçu, sans
fenêtre (ouverte, elle retiendrait l'aperçu au-delà du délai de la liaison) ; et le profil
adaptatif recalculé après une tache et un flou,
inchangé par une rotation.

Constaté le 16 octobre 2026 (Lightroom Classic 15.6, RAW X-H2S), sur un `add_mask` en
proposition (`preview`, `compare`) d'un ciel et d'un dégradé, photo active mais pas affichée dans
Développement :

- la fenêtre s'est ouverte au rendu de la proposition et la requête de Claude a dépassé son délai
  (« Request timed out » de Claude Code, pas le délai de `LightroomBridge`) ; les masques de
  l'essai sont restés sur la photo jusqu'à ce que la fenêtre soit fermée à la main, puisque
  « Claude · fin de l'essai » ne vient qu'après le rendu ;
- après cette fenêtre fermée, un vrai `add_mask` du même ciel n'a jamais reçu de `MaskDigest`,
  même la photo affichée dans Développement (rien après 30 s, ni après `undo_last` puis un nouvel
  `add_mask`) : seul « Mettre à jour » dans le panneau Masquage l'a fait calculer. « Lightroom le
  fait peu après » n'est donc pas sûr : sans `updateAISettings`, la fenêtre pouvait s'ouvrir à
  chaque aperçu.

Juste après la tonalité automatique, Lightroom range −999999 dans les réglages qu'il doit encore
calculer (Saturation, Vibrance, Contraste, Hautes lumières, Ombres, Noirs…). Constaté en 2.5 :
ils ne prennent leur valeur que quand Lightroom affiche la photo dans le module Développement
(16 valeurs en attente, toujours là 12 s après un aperçu exporté et 10 s après l'affichage dans la
Bibliothèque ; aucune 2 s après l'affichage dans le Développement). La recette de la 2.4 passait
parce que Lightroom était resté dans le Développement. Le serveur les montre comme « auto
(calculé quand Lightroom affiche la photo dans le module Développement) ».

`createDevelopSnapshot` attend Lightroom : appelé sous `pcall`, il échouait sans bruit (« Yielding
is not allowed within a C or metamethod call » dans le journal de Lightroom) et l'instantané
« Avant Claude » n'était jamais créé ; il passe par `LrTasks.pcall`. La commande `diagnostic`
protège de même `getmetatable`, que Lightroom refuse sur ses objets. Les paramètres d'exportation de Lightroom n'ont aucune clé pour cette mise à jour.

Les paramètres prédéfinis du module sont des fichiers de `~/Library/Application Support/Adobe/
Lightroom/Plugin Develop Presets/com.danymenard.developpeur/`, un par nom (`<nom>.lrtemplate` ;
30 le 16 octobre 2026, dont 26 de masques IA) : un même nom reprend le même fichier. Depuis la
1.5, le nom d'un paramètre prédéfini dont le contenu varie (masques, flou d'objectif) porte
l'empreinte de son contenu (`presetContenu`, `Locaux.empreinte`) : le même contenu ne crée plus de
fichier, et le module garde ceux de la session. Lightroom les charge à son lancement : `install.sh`
les efface seulement Lightroom fermé (il recrée ceux qu'il utilise), `uninstall.sh` retire le
dossier, Lightroom fermé aussi. Constaté le 16 octobre 2026 : après l'effacement des 29 fichiers,
Lightroom Classic 15.6 se lance normalement, et un essai complet (recette comprise) en recrée 7,
dont 6 de masques IA, que chaque `add_mask` avec un masque IA continue d'ajouter.

## Tri d'une séance (`vignettes`, `cull_photos`, `contact_sheet`)

**Vignettes.** `photo:requestJpegThumbnail(largeur, hauteur, rappel)` (SDK 5.0, dans une tâche)
rend un aperçu que Lightroom a déjà, ou qu'il rend s'il manque à cette taille ; la taille demandée
est un minimum ; le rappel reçoit le JPEG (un texte) ou nil et la raison ; la requête doit rester
référencée jusqu'au rappel. La commande `vignettes` (`Vignettes.lua`) les demande toutes à la fois
(50 au plus), attend les rappels (60 s au plus), écrit chaque JPEG dans un dossier temporaire propre
à la commande, et joint la description de chaque photo, le chemin de son fichier et sa géométrie.
Le serveur lit puis efface, comme un aperçu. Constaté le 17 octobre 2026 (Lightroom Classic 15.6) :
six vignettes en 0,75 s ; des aperçus standard de 1720 px de grand côté pour les RAW (1113 px pour
un JPEG d'iPhone), pour 1024 demandés. Mesurées à 1024 px, leur netteté vaut de 0,84 à 0,93 fois
celle des aperçus exportés (moyenne 0,88, sur les six photos d'essai), leur bruit de 0,83 à 1,15
fois, la note esthétique et la qualité des visages de Vision quasiment la même : le serveur multiplie
la netteté d'une vignette par 1,13 (`thumbnailSharpnessFactor`) pour garder les seuils de `Detail`.
Une vignette illisible ou de moins de 900 px est remplacée par un aperçu exporté (`apercu`, 1024 px).
Une vignette peut dater d'avant la dernière retouche (le cache de Lightroom) : le tri le dit.

**Point de mise au point.** ImageIO ne donne pas la MakerNote de Fujifilm (constaté sous macOS 26
sur un RAF de X-H2S) : le serveur la lit lui-même (`PointAF.swift`), en lecture seule, comme le
module Focus Points la lit par exiftool. RAF : « FUJIFILMCCD-RAW », position du JPEG incorporé à
l'octet 84 (grand-boutiste) ; son Exif porte les dimensions de ce JPEG (`ExifImageWidth`,
`ExifImageHeight`) et la MakerNote (0x927C) : « FUJIFILM », position de l'IFD, entrées
petit-boutistes repérées depuis le début de la MakerNote ; `FocusPixel` (0x1023, x y dans le repère
du JPEG incorporé), `FocusWarning` (0x1301, 1 = mise au point manquée), `FacesDetected` (0x4100).
Vérifié sur deux RAF contre exiftool 13.55 : « 2488 1052 » sur 4416 × 2944, « 2206 1471 ». Ce repère
est celui du fichier avant l'orientation ; `GeometriePhoto.versApercu`, l'inverse exact de
`Geometrie.point` du module sans la grille de recalage, le ramène dans la vignette (orientation,
cadre tourné). La netteté s'y mesure dans un carré de 12 % du petit côté (`Detail.nettete`).

Constaté en 2.3 (18 octobre 2026) : un `cull_photos` de 130 JPEG d'un Kodak DX4900 par Claude
Desktop est resté à « 0 sur 130 » ; échantillonné, le serveur attendait dans `open()` de
`PointAF.lire`, sur un original du volume externe « Photos » que le terminal ouvrait en 0,02 s :
macOS demandait à l'utilisateur d'autoriser l'accès au volume pour le processus lancé par Claude
Desktop (fenêtre UserNotificationCenter), et `open()` attendait la réponse, avec toute la file des
outils derrière lui. Depuis, l'original n'est ouvert que pour un fichier Fujifilm (`marque` de la
vignette, ou `.RAF`), et la lecture est bornée à 2 s (`LecteurPointsAF`) : un original qui ne s'ouvre
pas est sauté, et les suivants aussi tant que sa lecture n'a pas fini (un seul fil bloqué à la
fois), et le bilan le dit (`points_af`). Depuis la 1.1.1, quand la lecture bloquée finit
(l'utilisateur a répondu), elle débloque le lecteur et les lectures reprennent (avant, il restait
bloqué jusqu'à la fin de la série). Claude ne répond pas à une demande d'autorisation de macOS :
c'est à l'utilisateur.

**Point de mise au point dans `view_photo`** (1.1.1). Le même point, lu de même dans l'original
(Fujifilm seulement, `ToolHandler.pointAF`, commun avec `cull_photos`), sert à noter une photo
regardée : `view_photo` envoie `point_af = true` à la commande `apercu`, pour l'aperçu entier,
et après la 1.1.1 pour un zoom (`region`) aussi, jamais pour un avant/après (`compare` ; en
1.1.1, l'aperçu entier seulement). Le module décrit alors la photo comme pour une vignette
(`Vignettes.decrireVignette` : `chemin_original`, `marque`, `geometrie`), et ajoute
`point_af_toujours` (préférence `pointMiseAuPoint`) et `evaluation` (`Notation.resume`, lue dans
`notation.json` : « pas encore évaluée », « 3 ★ proposée par Claude, à vérifier »,
« acceptée par l'utilisateur : 3 ★ », « changée par l'utilisateur : 4 ★ (proposée : 3 ★) »,
« proposition écartée par l'utilisateur (3 ★) » ; « rejet » à la place des étoiles pour un
rejet). Le serveur retire `chemin_original`, `geometrie` et `marque` de la description, et
`point_af_toujours`, avant de répondre à Claude. Un point dans l'image affichée donne `point_af` :
`x` et `y` (de 0 à 1 depuis le coin haut gauche, au millième), `nettete` (autour du point, dans
le carré de 12 % de `Detail.nettete`, sans le facteur des vignettes), `appareil` (« mise au point
signalée manquée » si l'appareil l'a signalé) et `carre` s'il est dessiné. Le carré
(`PreviewImages.marquerPoint`) : vert, rouge pour une mise au point signalée manquée, côté de 6 %
du petit côté (16 px au moins), un liseré sombre autour pour rester visible sur un fond clair ; il
est dessiné avec le paramètre `af_point = true` (pour noter : consignes de la fenêtre) ou quand
la case « Mise au point » du Gestionnaire est cochée (`pointMiseAuPoint`, décochée par défaut).
Mesures et Vision sont prises avant le carré. `view_photo` a un seul lecteur
(`ToolHandler.lecteurAF`) : une lecture bloquée n'en lance pas d'autres. Un point hors du cadre
(recadrage) n'est pas donné.

**Sur un zoom** (après la 1.1.1, demandé par Dany le 20 octobre 2026 : un zoom pour voir la mise
au point ne la montrait pas). Le même point, lu de même, est ramené dans la zone demandée
(`region`, de 0 à 1 dans l'image entière). `point_af` donne `x` et `y` dans l'image entière (au
millième, comme sur l'aperçu entier, `ToolHandler.pointAFJSON`), `appareil` s'il y a lieu, et
`dans_la_zone` : vrai si le point tombe dans la zone. Alors seulement, `nettete` est mesurée
autour du point dans le zoom (le carré de 12 % de `Detail.nettete`, du petit côté du zoom), et le
carré est dessiné sur le zoom, à sa place dans la zone, avec `af_point = true` ou la case « Mise
au point » (`carre` : « vert, sur le zoom », ou « rouge, sur le zoom ») ; les mesures de la zone
(`mesures_zone`) sont prises avant. Un point hors de la zone donne `dans_la_zone` faux, sans
netteté ni carré. Les consignes de la fenêtre le disent (puce « Mise au point montrée ou jugée »,
voir Claude Code), et la description de `af_point` aussi (« sur l'image ou le zoom (region) »).

**Sur l'aperçu de la photo active de la fenêtre Claude** (après la 1.1.1, demandé par Dany le
20 octobre 2026). Le même point, lu dans l'original par `mcp-developpeur --marquer-af <original>
'<géométrie JSON>' <vignette.jpg> <sortie.jpg>` (`PointAF.marquer`, `main.swift`), lancé par la
fenêtre (`Images.marquerMiseAuPoint`, voir Fenêtre Claude › Disposition) pour un fichier Fujifilm
seulement : `geometrie` est celle de `Vignettes.decrireVignette` (dimensions affichées,
orientation, cadre) ; le connecteur lit le point en temps borné (`LecteurPointsAF`, 2 s), le passe
dans l'image affichée et recadrée (`GeometriePhoto.versApercu`), dessine le carré sur la vignette
(`PreviewImages.marquerPoint`, vert ou rouge) et l'écrit dans `<sortie.jpg>`, puis écrit sur sa
sortie une ligne JSON (`x`, `y`, `avertissement`). Code 1 sans point (pas un fichier Fujifilm,
point illisible ou hors du cadre, original qui ne s'ouvre pas à temps), 2 pour des arguments
illisibles. Il ne passe pas par la liaison : c'est un processus à part, lancé par Lightroom.

**Tri** (`cull_photos`, `Tri.swift`). Photos visées : `photo_ids`, la sélection, une collection ou un
dossier (par `chercher`, triées par date), 500 au plus, par lots de 25 vignettes (une commande à la
fois vers le module) ; progression et annulation entre deux lots (voir Délai des appels d'outils).
Chaque vignette, réduite à 1024 px : `Detail`, `Measurements`, Vision (visages, qualité, note
esthétique), empreinte, point AF, et les mots-clés de Vision si demandés. Deux photos mesurées à la
fois au plus : constaté le 17 octobre 2026, 25 analyses Vision lancées ensemble par
`DispatchQueue.concurrentPerform` ont bloqué le serveur (tous les fils attendaient la file de
capacité de Vision, `VNControlledCapacityTasksQueue`) ; une `OperationQueue` à deux opérations ne
bloque pas. Défauts : floue (zone la plus nette sous 15), mise au point manquée (sous 15 au point
AF, plus de 35 ailleurs), mise au point signalée manquée par l'appareil (si la netteté au point AF
reste sous 35), yeux fermés ou plissés d'un sujet (voir Ajouts de la 2.4), presque noire (L* médian
sous 6), brûlée (plus de 35 % de blanc pur). Ordre de lecture (`ordre`, qui remplace `score` dans
`classement` et `details` depuis la 1.1) : la netteté (au point AF s'il est dans l'image, divisée
par 60, au plus 1), plus la note esthétique de Vision à demi-poids (`Tri.poidsEsthetique`), moins
un par défaut ; ce n'est pas une note. La moitié de la qualité du meilleur visage ne compte que
pour départager les photos d'une rafale ou d'une pile (`scoreDansGroupe`) : elle ne compare que
des prises d'un même visage. Rafales : suites de photos consécutives (par date de prise de vue) où
Vision voit la même scène (distance sous 0,5) et prises à 4 s au plus l'une de l'autre (sans date,
distance sous 0,35). Constaté sur une séance de 329 photos en intérieur : sans l'écart de temps, les
photos semblables de proche en proche formaient un groupe de 193 photos (même salle, même éclairage) ;
avec lui, 61 rafales, dont une de 59 photos prises en continu.

Depuis la 1.1, le bilan suit le standard de notation (voir Notation) :

- `plafonds` (`{"<id>": {note_max, pourquoi, a_verifier?}}`, seulement pour une photo plafonnée
  sous 4 ou à vérifier ; chaque ligne de `details` porte aussi `plafond`). Le plancher technique
  du standard, par `Notation.plafond(_:doublon:)`, avec les seuils déjà relevés (aucun nouveau) :
  floue, mise au point manquée ou yeux fermés, 0 et rejet proposé ; douce (netteté sous 35) ou
  mise au point signalée manquée par l'appareil, 3 ; presque noire ou brûlée, 2 et à vérifier
  (souvent rattrapable par la retouche, surtout en RAW ou DNG : le format de la photo est lu) ;
  capture ou document selon Vision (`utility`), 1 ; pas la meilleure de sa rafale ou de sa pile,
  3 (un 4 est la meilleure vue de son moment) ; bruit fort (1,5 et plus,
  `DetailMeasurements.bruitFort`), pas de plafond mais à vérifier (à noter après le débruitage) ;
  sinon 4 (5 : l'utilisateur seul). Le plus bas l'emporte, raisons jointes ; une vignette
  illisible n'a pas de plafond. Un plafond borne la note, il ne la donne pas.
- `propositions` : seulement `{flag: "reject", photo_ids, pourquoi}`, pour les photos au plafond 0
  (défaut majeur, à confirmer à l'œil) encore libres (ni note ni drapeau, un seul test pour toute
  proposition) ; pour la seule photo de sa scène, `pourquoi` conseille plutôt 1 ★ à vérifier
  (`propose_ratings` avec `to_check`). Plus de `pick` ni d'étoile.
- `rafales[].meilleure` et `piles[].meilleure` nomment la meilleure de chaque groupe ;
  `rafales_moins_bonnes`, les autres photos sans défaut des groupes (plafonnées à 3) ; `classement`
  (les 15 premières photos sans défaut, dans l'ordre de lecture) ; `deja_classees`, combien de
  photos portent déjà un drapeau ou une note.
- Les plafonds de ce tri remplacent ceux d'un tri précédent des mêmes photos dans `dernierTri`
  (`ToolHandler`), que `propose_ratings` fait respecter.

Claude présente les rejets, puis les pose après accord par `set_metadata` (`flag: reject`, une étape
par photo, que `undo_last` défait) ; les étoiles se proposent par `propose_ratings`, après avoir
regardé les photos. Jusqu'à la 1.0, le tri proposait aussi de retenir la meilleure de chaque rafale
et les meilleures photos seules (jusqu'à 40 % des photos sans défaut), et 4 étoiles pour les 10 %
meilleures, une photo au moins : retiré, le standard n'a qu'un drapeau, Rejeter, n'a pas de quota,
et une étoile ne se tire pas d'une mesure. Critère de la 1.9 vérifié le
17 octobre 2026 : les 329 photos du dossier de cette séance, triées en 22 à 26 s (version
optimisée), toutes depuis le cache, sans blocage : 13 photos à défaut (5 mises au point manquées, 7
presque noires, 1 signalée par l'appareil).

**Mots-clés proposés** (`MotsClesVision.swift`). `VNClassifyImageRequest` nomme en anglais, parmi 1303
étiquettes (relevées sous macOS 26 par `supportedIdentifiers`, du plus large au plus précis) ; une
table les traduit toutes en français (vocabulaire du Québec quand il diffère : tuque, bleuet,
motoneige, chandail à capuchon…), un test vérifie qu'aucune ne manque. Seules les étiquettes sûres
sont gardées (`hasMinimumRecall(0.01, forPrecision: 0.9)`, confiance d'au moins 0,1), sans les plus
générales (animal, plante, structure, extérieur, matériel optique…) ni les doublons de traduction ;
six par photo au plus. Le tri en donne la liste par photo et les plus fréquents de la séance ; Claude
les pose par `set_metadata` après accord.

**Planche contact** (`contact_sheet`). Trente vignettes au plus depuis la 1.1 (douze avant ;
`maxContactSheet`) : le standard de notation juge l'Impact sur une planche de 20 à 30 vignettes.
512 px demandés, sur fond gris foncé, chacune dans une case 3:2, numérotée dans une pastille
(élargie pour trois chiffres) et légendée de son nom de fichier (coupé au milieu s'il est trop
long, CoreText) ; 2 colonnes jusqu'à 4 photos, 3 jusqu'à 9, 4 jusqu'à 16, 5 jusqu'à 25, puis 6
(`PreviewImages.colonnesPlanche` ; `columns` de 1 à 6) ; 1600 px de large, réduite si elle est
trop haute. L'image passe par `imageContent`, recompressée au besoin (Claude Desktop refuse une
réponse d'environ 1 Mo). Au-delà de 20 vignettes, les noms se lisent mal sur l'image : la légende
JSON fait foi (numéro, id, fichier, note, drapeau, libellé, date). `offset` donne la planche
suivante d'une sélection, d'une collection ou d'un dossier, et les numéros continuent d'une planche
à l'autre (`offset` + 1 ; depuis 1 avec `photo_ids`) ; `suite` dit combien il en reste. Constaté
(1.9, douze au plus) : les sept photos de la collection de recette en 1,2 s.

## Notation (`propose_ratings`, `notation`)

Depuis la 1.1. Claude propose des notes selon un standard, critère par critère ; depuis la 1.1.1,
toute proposition arrive « à vérifier », et l'utilisateur l'accepte ou la change dans Lightroom
(carte Note de la fenêtre Claude ; la Séance de notation de la 1.1 et les boutons Noter et
À vérifier sont retirés), sans repasser par Claude ni dépenser de quota. Dans la fenêtre Claude, Claude note
d'abord toute photo qu'il traite, avant d'y toucher, sans rien poser (consignes de la fenêtre,
voir Carte Note) ; une photo déjà évaluée ne se renote pas, sauf demande (`view_photo` :
`evaluation`). Sans demande, Claude ne pose rien lui-même. Depuis la 1.1.1 (demandé par Dany le
20 octobre 2026), quand l'utilisateur lui demande de noter (« note ces photos », « pose les
notes »), `propose_ratings` avec `apply` pose aussi les notes (voir plus bas). Claude ne propose
jamais 5 ★ de lui-même ; 5 ★ que l'utilisateur demande passent par `set_metadata`. Ce qui reste à
voir dans Lightroom : Fenêtre Claude › À constater dans Lightroom (1.1 et 1.1.1).

### Le standard

Une seule copie du texte : `Notation.standard` (`Sources/DeveloppeurKit/Notation.swift`, Markdown).
La ressource `developpeur://notation` (`standard-de-notation`, `Tools+Style.swift`),
`propose_ratings` avec `read_standard` et la fin de l'invite `noter` le reprennent de là ;
`NotationTests` en vérifie le début, la fin, les titres et quelques phrases, et l'absence des mots
interdits (ceux que `MCPServerTests` cherche). Le module ne le recopie pas : ses consignes y
renvoient (par `propose_ratings` avec `read_standard` : Claude Code n'a dans la fenêtre ni
ressources ni invites, `--tools ""` et `--disable-slash-commands`) ; en 1.1, les passes et le
rappel de la Séance de notation, retirés en 1.1.1, y renvoyaient aussi. En résumé :

- Une étoile dit un niveau de qualité, et rien d'autre, avec le même sens d'une sortie à l'autre.
  Rejeter, c'est le drapeau Rejeter ; les doublons d'une rafale, une pile sous la meilleure vue ;
  la valeur affective, un mot-clé ou une collection. 0 ★ veut dire « pas encore jugée ».
- Rejet : défaut majeur, involontaire, confirmé à l'œil (la seule photo de sa scène : plutôt 1 ★,
  à vérifier). 1 ★ : gardée, sous le niveau 2. 2 ★ : correcte, aucun défaut visible à la taille
  d'usage. 3 ★ : tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu. 4 ★ : une
  3 ★ qui a de l'impact (vue en premier sur une planche de 20 à 30 vignettes, nette à 100 % sur
  le sujet, meilleure vue de son moment ; souvent 5 à 10 % d'une sortie, sans quota). 5 ★ : parmi
  les meilleures de l'utilisateur, posée par lui seul. Une photo qui ne remplit pas les conditions
  d'une note reçoit celle d'en dessous.
- Critères, du plus lourd au plus léger : Impact (aucune mesure ne le voit), Qualités de l'image,
  Plancher technique (mesuré par `cull_photos` : il plafonne la note, il ne la donne pas),
  Finition (pour le 5 ★). Un défaut visible à la taille d'usage plafonne à 2 ★, visible seulement
  à 100 % à 3 ★ ; un défaut voulu et maîtrisé ne compte pas.
- Selon le genre (famille, portrait, paysage, nuit notée après le débruitage, sport, rue), puis
  quatre passes, une question chacune : 1 rejeter ou non ; 2 3 ★ ou non (sinon 2 ★, 1 ★ au
  passage) ; 3 parmi les 3 ★, monter à 4 ; 4 5 ★, l'utilisateur seul, après le développement.
- Les mesures fixent le plancher et départagent une rafale ; elles ne justifient jamais seules un
  4 ★. Photos étalons : la collection « Développeur › Étalons », si elle existe.

`Notation.noteMaximale` = 4 : Claude propose de 0 à 4 étoiles. `set_metadata` pose toujours 5 ★
quand l'utilisateur le demande.

### `cull_photos` et `contact_sheet`

`cull_photos` mesure le plancher technique : plafonds par photo (`plafonds`, `Notation.plafond`),
rejets proposés seulement pour un défaut majeur, ordre de lecture (`ordre`) au lieu d'un score, plus
de proposition de retenue ni d'étoile ; ses plafonds vont dans `dernierTri`. `contact_sheet` montre
jusqu'à 30 vignettes, pour juger l'Impact sur toute une sortie. Détails : Tri d'une séance.

### L'outil `propose_ratings`

Définition dans `Tools+Notation.swift` ; titre « Noter des photos » depuis la 1.1.1
(`ToolHandler.titles`, `Tools.swift` ; « Proposer des notes » en 1.1). Il n'est plus en lecture
seule depuis la 1.1.1 (`readOnlyHint` faux : absent de `ToolHandler.readOnlyTools`) : avec
`apply`, les notes sont posées dans le catalogue ; sans lui, rien ne change sur les photos ni dans
le catalogue, les propositions vont au registre du module. Sa description le dit depuis la
1.1.1 : sans `apply`, les notes sont rangées comme propositions « à vérifier », que l'utilisateur
accepte ou change dans Lightroom. `outputSchema` (`ToolHandler.outputSchemas`, « Propositions
rangées pour la carte Note, et posées avec apply ; ou le standard de notation. ») :
`{propositions, refusees, posees, erreur_pose (texte ou null), standard}`, propriétés en plus
permises ; plus de `seance` ni de Séance de notation depuis la 1.1.1.

Arguments :

- `ratings` : les propositions, une par photo, 500 au plus par appel (`maxRatings`, comme
  `cull_photos`) ; obligatoire sauf avec `read_standard`. Chacune :
  `{photo_id, rating (0 à 4) ou flag: "reject", criteria: {impact, qualities, technical_floor,
  finish}, reason, to_check}`. `rating` ou `flag`, pas les deux (`flag` seul : le rejet) ;
  `impact`, `qualities` et `technical_floor` obligatoires et non vides, `finish` facultatif (une
  photo développée) ; 200 caractères demandés par critère (`longueurCritere`), 300 pour `reason`
  (`longueurRaison`), refusés seulement au-delà de 300 et 400 (`toleranceCritere`,
  `toleranceRaison` : Claude dépasse de peu en comptant mal, constaté ; la carte coupe le
  surplus) ; `to_check` : un cas douteux (groupe, nuit, flou peut-être voulu ; défaut voulu
  au-dessus du plafond) ; depuis la 1.1.1, sa description ajoute que toute proposition arrive de
  toute façon « à vérifier » dans la carte Note (le registre garde `to_check` dans le champ
  `a_verifier` de la proposition).
- `pass` : la passe du standard, de 1 à 3 ; 4 (5 ★, l'utilisateur seul) est refusée avec des
  `ratings` (« Passe 4 : 5 étoiles, l'utilisateur seul ; rien à proposer. »), et le module la
  refuse encore.
- `read_standard` : seul, rend `{standard}` sans rien envoyer au module ; avec `ratings`, les
  propositions sont rangées et le standard s'ajoute à la réponse.
- `apply` (1.1.1) : `true` quand l'utilisateur demande que Claude note ou pose les notes (« note
  ces photos », « pose les notes ») : la commande reçoit `poser = true`, et les notes sont aussi
  posées dans le catalogue, « à vérifier » comprises (réponse : `posees`). `false` ou absent :
  propositions seulement. La description de l'outil le dit, et ajoute : jamais 5 étoiles ici ; si
  l'utilisateur en demande, `set_metadata`.

En 1.1, `session` (l'identifiant d'une séance) et `read_session` (la séance ouverte dans
Lightroom, par l'action `seance`) servaient à la Séance de notation : retirés en 1.1.1.

Tout est validé avant d'envoyer quoi que ce soit : un refus ne range rien. Les erreurs viennent
ensemble, une ligne `ratings[i] : …` chacune (dix au plus), après « Rien n'a été rangé : ».
Refusés : une note de 5 ou plus (« Claude ne propose jamais 5 étoiles : c'est à
l'utilisateur. »), négative ou non entière ; `rating` avec `flag`, ou ni l'un ni l'autre ; un
`flag` autre que `reject` ; une clé inconnue dans une proposition ou dans `criteria`, avec la
bonne clé quand elle s'en rapproche (« note (ici : « rating ») ») — validée à la main
(`ratingKeys`), car `parametresInconnus` ne voit que le premier niveau des arguments ; un
critère obligatoire vide, un critère ou une raison trop longs, une raison vide, un `to_check` qui
n'est pas un booléen ; une photo proposée deux fois ; `apply` qui n'est pas un booléen, `pass`
hors de 1 à 3, plus de 500 propositions, `ratings` absent ou vide sans `read_standard`. Enfin une
note au-dessus du plafond mesuré par le dernier `cull_photos` de la photo (`dernierTri`), sauf avec
`to_check = true` : un défaut voulu et maîtrisé ne compte pas (standard), Claude le dit dans
`technical_floor` ; le message invite aussi à relancer `cull_photos` pour une photo retouchée
depuis le tri. Ces refus valent aussi avec `apply` : rien n'est posé.

`dernierTri` (`ToolHandler`) vit dans le processus du serveur : il se perd quand le serveur est
relancé, et chaque client a le sien (Claude Desktop, chaque session de Claude Code, chaque
processus Claude Code de la fenêtre) ; un tri fait dans Claude Desktop ne plafonne pas les notes
proposées dans la fenêtre.

Puis une seule commande, par `FileOutils`, en 60 s au plus (`notationTimeout`, pose comprise avec
`apply`) :

```
notation {action: "proposer", passe?: entier, poser?: true,
          propositions: [{photo, note: 0…4 (0 pour un rejet), drapeau: "aucun" | "rejetee",
                          criteres: {impact, qualites, plancher, finition?},
                          plafond?: entier (celui de dernierTri), raison, a_verifier: booléen}]}
```

La réponse du module est rendue telle quelle (aussi en `structuredContent`), avec `standard` si
demandé. `notation` n'est pas une lecture que `LightroomBridge` rejoue après une coupure
(`LightroomBridge.lectures`) : rejouée, elle remettrait les propositions acceptées ou changées à
« à vérifier », et avec `poser`, elle écrirait de nouveau.

L'invite `noter` (arguments `photos` et `passe` : 1, 2, 3, 4 ou une consigne ; sans le guide de
style) : `cull_photos`, `contact_sheet` par planches de 24 à 30, `view_photo` sur le sujet pour les
candidates à 4 ★ et les cas douteux, `propose_ratings` avec `pass`, puis un résumé ; jamais
`set_metadata` pour une note sans demande ; jamais 5 ★ de lui-même (l'utilisateur les pose, ou les
demande : `set_metadata`) ; `apply = true` si l'utilisateur demande que Claude pose les notes ; à
la passe 4, rien de proposé. Sans `photos`, la sélection de Lightroom (sinon, demander où elles
sont ; en 1.1, d'abord la séance ouverte, par `read_session`). Le standard entier la termine.
`tri_seance` ne propose plus de 4 ou 5 ★ ni de drapeau Retenue : les notes passent par
`propose_ratings` (de 0 à 4 ★, 5 ★ à l'utilisateur seul ; acceptées dans la carte Note, ou posées
avec `apply` à sa demande ; ou l'invite `noter`), et `garder` désigne une collection, pas une
note.

### Le registre (`Notation.lua`, `notation.json`)

Le module range les propositions en mémoire et dans
`~/Library/Application Support/Developpeur/notation.json` (`Fichiers.ecrire`, réécrit à chaque
changement), propre au catalogue ouvert : le chemin du catalogue y est gardé
(`catalog:getPath()`), et un autre catalogue trouve un registre vide (le fichier ne change qu'à sa
première proposition). Format 2 depuis la 1.1.1 : `{format = 2, catalogue, propositions}`. Un
registre plus ancien (format 1, avec `seances`, `seanceActive` et `prochain`) perd ses séances à la
relecture : `normaliser` ne garde que les propositions, sans leur `seance`. Les clés des photos
sont des textes (`Json.decode` rend des clés texte) ; chaque proposition garde l'uuid de sa photo :
un identifiant qui désigne maintenant une autre photo perd sa proposition (`lire`, `poser`). Au
plus 2000 propositions (`Notation.MAX_PROPOSITIONS`) : les plus anciennes sortent (en 1.1, aussi
50 séances au plus). Le fichier se charge dans les deux simulations et sans l'interface :
`Bibliotheque` n'est requis qu'au moment d'écrire. Tout ce qui sort vers une vue est une table
neuve, sans métatable. `Notation.version` augmente à chaque changement ; `Notation.abonner(nom,
fn)`, `Notation.desabonner(nom)` et `Notation.signaler(quoi)` (`propositions`, `decision`, `pose`,
`recalage`) préviennent les fenêtres abonnées (`fenetre`, la seule depuis la 1.1.1).

Une proposition : `{photo, uuid, fichier, note (0 à 4, nil pour un rejet), drapeau ('aucun' ou
'rejetee'), criteres = {impact, qualites, plancher, finition}, plafond, raison, a_verifier, passe,
note_avant, drapeau_avant, etat, note_choisie, drapeau_choisi, le, decide_le, commentaire}`.
`etat` : `a_verifier` (depuis la 1.1.1, toute proposition commence ainsi, demandé par Dany le
20 octobre 2026 : l'utilisateur l'accepte ou la change ; le champ `a_verifier`, lui, dit en plus
que Claude doute), `acceptee` (posée telle quelle), `changee` (posée autrement : `note_choisie`,
`drapeau_choisi`), `ecartee` (qu'aucun bouton ne pose plus depuis la 1.1.1 : Écarter était dans
la Séance) ; `proposee` ne reste que pour les propositions d'avant la 1.1.1 (en 1.1, l'état d'une
proposition sans doute). Une nouvelle proposition pour la même photo remplace l'ancienne.

API : `Notation.proposition(idPhoto)`, `Notation.resume(idPhoto)` (1.1.1 : l'évaluation en une
phrase, pour `view_photo`, voir Tri d'une séance › Point de mise au point),
`Notation.decider(idPhoto, etat, details)` (`a_verifier`, `ecartee`, ou `proposee` pour revenir
sur la décision ; le mot de l'utilisateur gardé dans `commentaire` ; rien dans le catalogue ; rend
vrai, ou nil et la raison ; aucun bouton ne l'appelle depuis que À vérifier est retiré, en 1.1.1),
`Notation.poser(liste, options)` et `Notation.recaler(releves, version)` (voir plus bas). Les
séances de la 1.1 (`Notation.ouvrirSeance`, `seanceActive`, `seance`, `choisirPasse`,
`propositions`, `compter`) sont retirées en 1.1.1.

**Commande `notation`** (`Commandes.lua` → `Notation.commande`), actions `proposer` et `lire` (en
1.1, aussi `seance`, retirée en 1.1.1). Sans `poser`, rien n'est écrit dans le catalogue : ni la
pause, ni l'accord, ni les garde-fous ne s'y appliquent, comme pour `vignettes`.

- `proposer` : refuse tout pour une note de 5 ou plus (second garde-fou, après le serveur), un
  drapeau autre que `aucun` ou `rejetee`, une note qui n'est pas un entier de 0 à 4, une
  proposition sans note ni rejet, une proposition sans photo, une passe hors de 1 à 4, ou la
  passe 4 (5 ★, l'utilisateur seul : rien à proposer, second garde-fou) ; une photo introuvable va
  dans `refusees` sans bloquer les autres. Un rejet est un drapeau sans note (le serveur envoie
  0) : l'accepter laisse les étoiles de la photo. La passe d'une proposition est celle donnée. Note
  et drapeau d'avant (`note_avant`, `drapeau_avant`) sont lus par `Photos.decrireTout`. État :
  toujours `a_verifier` depuis la 1.1.1 (en 1.1, `a_verifier` seulement si Claude doutait, sinon
  `proposee`) ; `a_verifier = true` garde le doute de Claude. Réponse : `{propositions: [{photo,
  fichier, note_avant, drapeau_avant, etat}], refusees: [{photo, raison}]}` ; le journal de la
  liaison note « Notation : n propositions ». Avec `poser = true` (`propose_ratings` avec
  `apply`, 1.1.1), les propositions rangées sont aussi posées, comme Accepter, « à vérifier »
  comprises : `Notation.poser(liste, {depuisLightroom = false, confirme = true})` (voir plus bas).
  La réponse ajoute `posees` (`photo`, `etat` — `acceptee` ou `changee` —, `note`, `drapeau`,
  `erreur`, `remarques`), et `erreur_pose` quand une écriture a échoué (pause de la liaison,
  accord en attente, garde-fou) : les propositions restent alors rangées, « à vérifier ».
- `lire` (`photos?`) : `{propositions (sans l'uuid), perdues?}` ; les propositions dont la photo
  a disparu ou changé sont retirées et comptées dans `perdues`.

`propose_ratings` envoie `proposer` ; aucun outil n'envoie `lire` (les essais de la liaison
l'emploient, et `--module`).

### Poser une note (`Notation.poser`, `Bibliotheque.noter`) et l'annuler

Une note proposée ne s'écrit qu'à la demande de l'utilisateur : Accepter et Changer… de la carte
Note (et, en 1.1, Tout accepter de la Séance), et depuis la 1.1.1 sa demande à Claude
(`propose_ratings` avec `apply`, commande `notation` avec `poser`). Toujours par
`Notation.poser(liste, options)`, dans une tâche : `liste = {{photo, note (0 à 5) ou nil, drapeau
('aucun', 'rejetee', 'retenue') ou nil, raison}}` ; `options` : `depuisLightroom` et `confirme`,
vrais par défaut (un clic dans la fenêtre), `depuisLightroom` faux pour une pose demandée à Claude.

- Sans note ni drapeau (Accepter, `apply`) : la proposition telle quelle, sa note, et le drapeau
  Rejeter pour un rejet (les étoiles restent) ; une note proposée sans rejet retire seulement un
  rejet déjà posé (« aucun » d'une proposition veut dire « pas rejetée » : un drapeau Retenue de
  l'utilisateur reste).
- Avec des valeurs (Changer…) : celles-là, 5 ★ compris ; nil laisse le champ tel quel.
- Une photo dont l'uuid n'est plus celui de la proposition est refusée, sa proposition retirée.
- Une écriture par lot de 500 photos (`Notation.LOT`) : `Bibliotheque.noter{notes, etape =
  'notation', depuisLightroom, confirme, outil}` (`outil` = `propose_ratings` quand
  `depuisLightroom` est faux) ; une erreur arrête ce lot et les suivants. Puis la
  proposition passe à `acceptee` (la photo porte ce que Claude proposait) ou `changee`
  (`note_choisie`, `drapeau_choisi`), sauf si elle a été remplacée pendant l'écriture. Rend
  `{ok, erreur, resultats = {{photo, etat, note, drapeau, changements, remarques, erreur}}}`.

`Bibliotheque.noter(params)` (`params.notes`, comme ci-dessus, plus `etape`, `depuisLightroom`,
`confirme`, et depuis la 1.1.1 `outil`, l'outil de Claude à rappeler après un accord,
`set_metadata` sans lui) : une seule écriture (`Ecriture.ecrire`) pour toutes ses photos, 500 au
plus ; une étape par photo (« Claude · notation », clé `Bibliotheque` de la mémoire), sa raison au
journal (type `classement`) ; identifiants dédoublonnés : une photo donnée deux fois ne compte
qu'une fois, avec sa dernière valeur, et sa remarque le dit (dans une écriture, Lightroom relit un
champ du module avec sa valeur d'avant : la seconde étape effacerait la première). `depuisLightroom`
lève la pause et l'accord dans Lightroom ; `confirme` passe « Proposer d'abord » et le plafond de
photos par écriture (c'est l'utilisateur qui pose : le clic, ou sa demande explicite à Claude,
vaut accord) ; les autres garde-fous des photos (`verifierProtection` : copies virtuelles
seulement, libellé protégé, photos rejetées) restent. Avec `apply`, `depuisLightroom` est faux :
la pause de la liaison arrête la pose, et en mode « Proposer d'abord » avec « Confirmer dans
Lightroom » (`accordDansLightroom`), l'accord de la fenêtre de suivi est demandé
(`Ecriture.accordDansLightroom`) ; l'échec revient dans `erreur_pose`. Ce refus dit à Claude de
rappeler `propose_ratings` avec `apply = true` une fois l'accord donné (`rappel` dans
`Ecriture.lua` : `propose_ratings` n'a pas de `confirm`, `apply` y vaut accord ; pour les autres
outils, « <outil> avec confirm = true ») ; dans un premier état de la 1.1.1, il disait
`set_metadata`. `verifierProtection` reçoit le même outil.

Annulation : comme un classement. ⌘Z défait l'écriture entière, une opération « Claude ·
notation » comme toute écriture groupée (à constater pour une pose de plusieurs photos avec
`apply`) ; `undo_last` défait la dernière étape de chaque photo, une à une. La note posée est
celle de l'utilisateur : elle n'entre pas dans `avantClaude` (`memoriser` sans
`fusionnerOriginal`), et `revert_to_original` comme « Revenir à « Avant Claude » » la laissent en
place (une photo qui ne porte que des notes posées ainsi n'a pas de retouche de Claude à défaire).
Une note que Claude aurait posée par `set_metadata` avant, sur la même photo, reste dans
`avantClaude` : le retour à l'origine remet la note d'avant celle-là.

Le registre ne voit pas l'annulation : la note quitte le catalogue, la proposition restait
`acceptee` (constaté le 20 octobre 2026, planche et fiche de la Séance de la 1.1). La fenêtre le
recale donc sur ce qu'elle relit : `Notation.recaler(releves, version)`, `releves = {{photo, note
(0 à 5), drapeau ('retenue', 'aucun', 'rejetee', ou pickStatus 1, 0, −1)}}`, appelé par la carte
Note (`Fenetre.majPhoto`, la photo active ; en 1.1, aussi par la planche de la Séance, en un seul
appel pour ses 12 photos et celle de la fiche). Une proposition `acceptee` dont la photo ne porte
plus ce qu'elle proposait (sa note sans rejet ; pour un rejet, le drapeau Rejeter seul : les
étoiles ne comptent pas, et un drapeau Retenue de l'utilisateur sur une note acceptée non plus), ou
`changee` dont la note ou le drapeau choisis ne sont plus là (une autre note posée à la main
compte aussi), repasse à `a_verifier` depuis la 1.1.1 (à `proposee` en 1.1) : `note_choisie`,
`drapeau_choisi` et `decide_le` effacés ; la carte Note la montre de nouveau « à vérifier », à
accepter ou à changer. Une note illisible, un drapeau inconnu, une photo sans proposition ou une
proposition à décider ne changent rien. `version` est `Notation.version` lue avant les relevés :
si le registre a changé depuis (une note posée entre-temps par une autre tâche, relevé périmé),
rien n'est recalé, et la lecture suivante le fera ; de même pendant une écriture de
`Notation.poser` (elle rend la main pendant l'écriture et la relecture des photos : une fenêtre a
pu relever une photo avant que sa note y soit posée), dont la version ne change qu'à la fin. Ces
deux conditions se vérifient après le chargement du registre, qui peut lui aussi rendre la main ;
le reste du recalage ne la rend pas. Une seule écriture de `notation.json` pour tous les relevés
(`changer('recalage')`, une ligne au journal de la liaison) ; aucune sans changement. Rend le
nombre de propositions recalées. Seule la fenêtre recale : sans fenêtre Claude ouverte, ou pour
une photo qu'elle ne montre pas (une note posée avec `apply` puis défaite par `undo_last`, par
exemple), la commande `notation` (`lire`) et l'évaluation de `view_photo` rendent encore l'état
gardé, jusqu'à ce que la carte Note relise cette photo.

## Recette dans Lightroom

`mcp-developpeur --recette` (`Recette.swift`) passe par les outils, comme Claude, sur des photos
d'essai que Claude n'a pas encore retouchées (le retour à l'origine de la fin effacerait aussi ces
retouches) : des copies virtuelles (`copie_virtuelle`, champ de la description d'une photo),
rangées dans la collection « Développeur › Essais » (`Recette.collectionDeRecette`), et des
originaux avec `--original`. Un essai fait à la main sur ces photos se défait ensuite (`undo_last`,
`revert_to_original` ou ⌘Z). Un original revient aux mêmes réglages, mais son historique garde
les étapes de la recette, son journal (`journalClaude`) aussi, et l'instantané « Avant Claude »
reste si l'option est cochée : l'étape « photo d'essai » le dit. Copie d'un RAW : balance personnalisée (+300 K, +4), profil
d'appareil « Camera PRO Neg. Hi » (Fujifilm : relu sous le nom de l'appareil, puis annulé ; sautée pour une
autre marque), profil adaptatif Adaptive Color (calculé au rendu qui suit : `AILookData` relu,
puis annulé), masque IA de l'arrière-plan, second
masque IA sujet (les deux restent), masque combiné (arrière-plan sans le sujet : deux composants,
le second soustrait ; l'arrière-plan plutôt que le ciel depuis la 2.1, qui retire un masque vide :
une photo de groupe n'avait aucun ciel pour Lightroom), tonalité automatique (la balance reste), propositions de réglages et de masque
(rien n'est gardé), aperçu avec netteté et Vision, mesure d'angle, tache près du bord (position
recalée sur la correction d'objectif, puis annulée), débruitage puis son annulation, super
résolution puis son annulation (réglages identiques à ceux d'avant), annulation, puis la
Bibliothèque : collection « Claude › Recette MCP-Développeur » avec la photo, classement (note,
drapeau, libellé, titre, mot-clé « MCP-Développeur (recette) › Essai », relus), recherche critère
par critère avec sa contre-épreuve, annulation du classement, retrait de la collection et son
annulation ; puis la 1.9 : tri sur la vignette du cache (mesures, mots-clés, rien de changé),
planche contact, suppression des reflets à 60 puis 90 (intensités relues, deux annulations, filtre
retiré), objet désigné par un rectangle (geste `Mask/Polygon` relu, puis annulé), plage de couleurs
et couleur ponctuelle d'un masque en propositions (une part des pixels change, rien n'est gardé) ;
puis la 2.0 (livraison, variantes, mode HDR) et la 2.1 : profil d'objectif choisi puis profil par
défaut remis à l'annulation, rotation d'un quart de tour, mélange noir et blanc automatique (curseurs
calculés relus), personne 1 reconnue par Lightroom puis recalculée, masque vide retiré, pinceau
d'affinage du flou, chacun annulé ; enfin le retour à l'origine (réglages, masques, profil, recadrage et classement identiques au
départ). La collection et le mot-clé restent dans le catalogue, vides, et resservent à la recette
suivante. Avec `--profondeur <id>` (une copie d'une photo Portrait d'iPhone) : une plage de
profondeur en proposition, qui ne doit assombrir qu'une part de l'image.
Depuis la 2.4, `--yeux-rouges <id>` (une vraie photo au flash) mesure la part de pixels rouges dans
chaque pupille avant et après la correction, et `--x-t20 <id>` relit les profils d'un X-T20 (Pro
Neg Hi sous son orthographe, ETERNA refusé) ; la Bibliothèque ajoute texte alternatif, champs IPTC
et position GPS relus puis défaits, photos jamais exportées, filtre posé puis remis. Constaté en
2.4 : une photo d'essai rangée dans la collection des photos d'essai par Claude garde cet ajout
dans sa mémoire, et le retour à l'origine de la fin l'en retirait ; elle y est maintenant remise
(`remettreDansLaCollection`).
Depuis la 1.1, après la planche contact, l'étape « note proposée (propose_ratings), photo
inchangée ; puis posée sur demande et annulée » (son nom depuis la 1.1.1) : 5 étoiles refusées
(« jamais 5 étoiles »), puis 2 étoiles avec `to_check` rangées par la vraie commande `notation`
(état « a_verifier », celui de toute proposition depuis la 1.1.1), la photo inchangée ; depuis la
1.1.1, la même proposition avec `apply` : 2 ★ posées (`posees`, état « acceptee », note relue dans
le classement), puis `undo_last`, après quoi la photo est de nouveau comme au départ (en 1.1,
l'étape lisait la séance ouverte par `read_session`, retiré). Elle laisse une proposition pour la
photo d'essai dans `notation.json` (aucune commande ne retire une proposition), « acceptee »
jusqu'à ce que la carte Note relise cette photo, puis de nouveau « a_verifier »
(`Notation.recaler`).
Depuis la 1.1.1, avec `--x-t20`, l'étape « point de mise au point dessiné pour noter (view_photo,
af_point) » : `view_photo` avec `af_point = true` à 1024 px ; une image, l'évaluation dite
(`evaluation`), le chemin de l'original absent de la réponse ; un point lu (`point_af`) doit porter
son carré (`carre`). Sans point lu (original absent, ou sans point AF), l'étape le dit sans
échouer.
Copie d'un JPEG : balance relative, tonalité automatique, masque IA. Copie au flash : pupilles
par Vision, zooms avant et après la correction des yeux rouges, enregistrés pour l'œil. Avec un
RAW et un JPEG : harmonisation en plan ; avec un RAW et la photo au flash : expositions d'après la
prise de vue, en plan. Chaque
séquence se termine par le retour à l'origine, même après un échec.

`get_settings` avec `all_keys` ajoute tout ce que Lightroom range (`toutes` côté module) : pour
explorer un outil appliqué à la main (flou d'objectif, réduction du bruit…).

## Bibliothèque

`Bibliotheque.lua` ; outils `find_photos`, `set_metadata`, `list_keywords`, `manage_collections`,
`create_virtual_copy` et `show_photo` (`Tools+Bibliotheque.swift`). Depuis la 1.1,
`Bibliotheque.noter` pose aussi les notes que l'utilisateur accepte ou change dans la fenêtre
Claude, sans commande du serveur, et depuis la 1.1.1 celles qu'il demande à Claude de poser
(`propose_ratings` avec `apply`, par la commande `notation`) ; voir Notation.

Relevé dans Lightroom Classic 15.6 (commande `diagnostic`, 16 octobre 2026) : le catalogue offre
`createVirtualCopies`, `createKeyword`, `getKeywords`, `createCollection`, `createCollectionSet`,
`createSmartCollection`, `getChildCollections`, `getChildCollectionSets`,
`getCollectionByLocalIdentifier`, `findPhotos`, `batchGetRawMetadata`, `getFolderByPath`,
`getActiveSources` et `setActiveSources` (pas `getCollectionSetByLocalIdentifier`) ; la photo,
`setRawMetadata`, `addKeyword`, `removeKeyword` et `getContainedCollections` ; un mot-clé, `getName`,
`getParent`, `getChildren`, `getPhotos` (pas d'identifiant) ; une collection, `addPhotos`,
`removePhotos`, `getPhotos`, `isSmartCollection` et `localIdentifier`. `getRawMetadata` donne la
note (`rating`, nil sans note), le drapeau (`pickStatus` : 1, 0 ou −1), `colorNameForLabel` et les
mots-clés (`keywords`), mais refuse `title`, `caption`, `copyright`, `label`, `creator`, `copyName`,
`folder` et `keywordTags` : ceux-là se lisent par `getFormattedMetadata` (la simulation refuse de
même). `LrSelection` (drapeaux, notes, libellés de la sélection) existe aussi ; le module ne s'en
sert pas.

**Écriture.** Une commande, une écriture (`withWriteAccessDo`) pour toutes ses photos ; chacune
garde une étape `{ nom, avant = { Bibliotheque = … } }` et son entrée au journal (type
`classement`). La clé `Bibliotheque` porte ce que l'étape a remplacé : `note`, `drapeau`,
`libelle` (le texte d'avant), `titre`, `legende`, `droits`, et pour les mots-clés et les
collections ce qu'elle a ajouté (`ajoutes`, à retirer) et retiré (`retires`, à remettre), par
chemin de mot-clé ou identifiant de collection. Dans `avantClaude`, la première valeur de chaque
champ, et le cumul des ajouts et retraits (un ajout puis un retrait s'annulent ; une étape annulée
en sort, `Bibliotheque.annulerCumul` : sinon un retrait annulé laisserait au retour à l'origine la
photo dans la collection où Claude l'avait mise). Comme
`Amelioration`, ce n'est pas un réglage : `annuler` et `revenir` l'écartent de
`applyDevelopSettings` (la simulation le refuse) et la remettent par `Bibliotheque.remettre`, dans
la même écriture ; une comparaison (`comparer`) n'a rien à rendre pour un classement. Un classement
ne fait pas « Retouchée par Claude », et l'instantané « Avant Claude » vient à la première
retouche du développement même après un classement (`Ecriture.sansRetouche`). « Proposer d'abord »
et la pause s'y appliquent. Une copie virtuelle ou une collection créée reste : le SDK ne
supprime pas de photo, et le module ne supprime rien.

**Créer, puis employer.** Constaté dans Lightroom Classic 15.6 (recette du 16 octobre 2026) : une
collection créée dans une écriture ne se lit pas dans la même (« Can't get collection information
after creating collection inside the same withWriteAccessDo function », à la lecture de son
`localIdentifier`). L'ensemble « Claude », la collection et ses photos s'écrivent donc chacun dans
sa propre écriture (supposé pareil pour un ensemble). La simulation refuse de lire ou d'employer
une collection ou un ensemble dans l'écriture qui l'a créé. L'écriture interrompue par cette erreur
a été défaite entièrement : l'ensemble « Claude », créé juste avant dans la même écriture, n'est pas
resté.

Un mot-clé, lui, s'emploie dans l'écriture qui l'a créé : constaté en 2.3 (18 octobre 2026), sous
un mot-clé existant lu hors de l'écriture, `createKeyword` puis `photo:addKeyword` dans la même
écriture pose le mot-clé, et deux niveaux neufs aussi (le second créé sous le premier, puis posé) ;
seule sa lecture échoue (`getName` : « attempt to index a nil value », l'écriture entière défaite).
Les mots-clés qui manquent se créent donc dans l'écriture du classement, les parents avant leurs
enfants, chacun une fois, sans rien lire d'eux (leurs chemins sont connus d'avance) : un classement
est une seule opération pour ⌘Z. Le paramètre prédéfini de métadonnées passe avant les mots-clés
(il relit ceux de la photo). La simulation refuse la lecture d'un mot-clé créé dans l'écriture,
pas son emploi.

**Mots-clés.** Un nom ou un chemin (« Lieux > Canada > Montréal », aussi avec › ou |) désigne
d'abord un chemin complet, sinon la fin d'un chemin, s'il n'y en a qu'un (sinon le module demande
le chemin). Ce qui manque est créé à sa place par `createKeyword(nom, {}, true, parent, true)`
(qui rend celui qui existe au même endroit), avant l'écriture du classement.

**Libellé.** Lightroom range un texte, celui du jeu de libellés actif (« Rouge », « Vert »… dans
le catalogue de Dany, en français) ; `colorNameForLabel` en donne la couleur. Pour poser une
couleur, le module écrit d'abord le texte d'une photo qui a déjà cette couleur (`findPhotos` sur
`labelColor`), sinon « Rouge », puis relit la couleur après l'écriture et essaie au besoin le texte
suivant (« Red »…), chacun dans sa propre écriture ; si aucun ne convient, le libellé d'avant
revient, et la réponse et le journal le disent. Constaté dans Lightroom Classic 15.6 (recette du
16 octobre 2026) : relu dans la même écriture, « Rouge » n'était pas encore rouge (la simulation
garde la couleur d'avant jusqu'à la fin de l'écriture) ; et un libellé ne s'efface pas par nil
(« entity:__newindex(): Field "colorLabels" cannot be set to nil. ») : un texte vide l'efface
(supposé pareil pour le titre, la légende et les droits d'auteur). Une note s'efface par nil si
Lightroom l'accepte, par 0 sinon.

**Recherche.** `findPhotos { searchDesc }`, avec la forme des collections dynamiques. Relevé dans
les modèles qu'installe Lightroom Classic 15.6 (`smart_collections/*.lrtemplate`) : `rating >=`,
`labelColor ==` (rouge = 1), `captureTime inLast` avec `value_units = 'days'`, `touchTime`,
`fileFormat == 'VIDEO'`, `keywords empty`, et `combine = 'intersect'` ; dans son code : les
opérations sur un texte (`any`, `all`, `words`, `noneOf`, `beginsWith`, `endsWith`, `empty`,
`notEmpty`), les critères `pick`, `camera`, `lens`, `isoSpeedRating`, `all` (tous les champs) et le
préfixe `sdktext:` des champs d'un module (« Retouchée par Claude » est déclaré `searchable`).
Vérifié par la recette dans Lightroom Classic 15.6 (16 octobre 2026), critère par critère, avec
une contre-épreuve qui ne doit pas trouver la photo : `rating >=` et `<=`, `pick ==`, `labelColor ==`,
`keywords words`, `all` + `all`, `fileFormat ==`, `sdktext:<id>.retoucheeParClaude notEmpty` et
`empty`, `captureTime inLast`, `camera ==` le modèle. La note, le drapeau (`pickStatus`), le
libellé (texte « Rouge »), le titre et un mot-clé créé s'écrivent et se relisent ; l'annulation et
le retour à l'origine les remettent.
Les dates exactes (`LrDate.timeToW3CDate`), le dossier (`getFolderByPath` puis `getPhotos`), la
collection et les copies virtuelles se filtrent après coup, 5000 photos au plus ; le tri aussi.

**Copie virtuelle.** `createVirtualCopies(nom)` agit sur les photos sélectionnées : le module les
sélectionne (en affichant au besoin le dossier de la première), crée les copies, puis remet la
sélection et la source (ou montre les copies, avec `afficher`). Il les essaie dans une écriture,
puis hors d'une écriture si Lightroom refuse ; la fenêtre de suivi dit lequel a servi. Essayé dans
Lightroom Classic 15.6 (16 octobre 2026, copie d'une copie virtuelle) : la copie est créée, sous le
nom demandé, avec les réglages de sa source ; elle ne voit rien de la mémoire de Claude que
Lightroom lui a copiée (journal vide) ; la sélection d'avant revient. La recette n'en crée pas :
aucun outil ne supprime une photo. Les nouvelles
copies se trouvent par la différence des `virtualCopies` de l'original, avant et après.

**Montrer.** `setSelectedPhotos`, puis `LrApplicationView.switchToModule` et `showView` ; une photo
hors du film fixe fait afficher son dossier (`setActiveSources`). Rien n'est écrit. Constaté en 2.3
(18 octobre 2026) : aussitôt après `setActiveSources`, `setSelectedPhotos` ne sélectionne pas
encore la photo du dossier affiché (`create_virtual_copy` et `enhance_photo` échouaient sur une
photo hors du film fixe, puis réussissaient au second essai, le dossier étant affiché) ; la
sélection se refait donc pendant 3 s au plus (`selectionnerAvecSource`, `DELAI_SOURCE`), et la
simulation ne rend une photo sélectionnable qu'un moment après l'affichage de son dossier. Essayé dans
Lightroom Classic 15.6 (16 octobre 2026) : module Développement, puis Bibliothèque en loupe, sans
erreur. Vues relevées dans `LrApplicationView.lua` de Lightroom Classic 15.6 : `loupe`, `grid`,
`compare`, `survey`, `people`, `develop_loupe`, `develop_before_after_horiz`,
`develop_before_after_vert`, `develop_before`, `develop_reference_horiz`, `develop_reference_vert`.
`show_photo` offre loupe, grille, comparaison, ensemble (`survey`) et l'avant/après côte à côte
(`develop_before_after_horiz`, module Développement). L'« Avant » de Lightroom est l'état de la
photo à l'importation, ou celui qu'on y a copié (un instantané › Copier les paramètres de
l'instantané dans Avant) : pas l'état d'avant Claude, et la réponse le dit (`a_savoir`).

Menu Fichier (ou Bibliothèque) › Module externe - Extras › « Créer une copie virtuelle pour
Claude » : une copie « Claude » de chaque photo sélectionnée, sélectionnée ensuite (ni la pause ni
le mode « Proposer d'abord » ne s'y appliquent : c'est l'utilisateur qui la demande).

**Paramètre prédéfini de métadonnées** (`metadonnees`, `preset_metadonnees`) :
`photo:applyMetadataPreset(id)` dans l'écriture du classement ; les 29 champs IPTC qu'il peut
remplir (lus par `getFormattedMetadata`) et les mots-clés sont lus avant et après : la mémoire
garde les valeurs d'avant, et l'annulation remet celles qui ont changé (`setRawMetadata`).
Constaté en 2.3 (18 octobre 2026), avec un paramètre prédéfini d'essai « Claude essai droits »
(copyright et gros titre, créé dans Métadonnées › Modifier les paramètres prédéfinis ; gardé dans
`Metadata Presets` pour les essais) : le fichier range `["com.adobe.copyright"]`,
`["com.adobe.headline"]` et un `uuid` (l'identifiant que donne `metadataPresets()`) ; appliqué, il
pose bien les champs, mais **pas visibles dans l'écriture qui l'applique** (contrairement à
`setRawMetadata`) : la réponse disait « aucun champ n'a changé ». Ce qu'il a changé se relit donc
après l'écriture (`relirePresetsMetadonnees`) et va au journal par une écriture privée ; les
mots-clés qu'il ajoute vont dans l'étape. `undo_last` vide les champs posés (copyright, gros titre
relus vides) ; le résumé de l'annulation nomme « champs IPTC ». La simulation n'applique un
paramètre prédéfini de métadonnées qu'à la fin de l'écriture.

## Mémoire des retouches

Champs privés du module, dans le catalogue, pour chaque photo :

- `avantClaude` : valeur d'origine de chaque réglage que Claude a touché (premier changement), et
  sous la clé `Amelioration` l'état d'origine du débruitage, des détails bruts et de la super
  résolution, sous la clé `Suppression` celui des reflets, sous la clé `Bibliotheque` celui du
  classement (voir Bibliothèque ; sans les notes que l'utilisateur pose depuis la fenêtre, qui
  restent au retour à l'origine, voir Notation), sous
  la clé `Rotation` les quarts de tour à refaire pour revenir
  (version 2.1) ;
- `etapesClaude` : les 20 dernières retouches, avec les valeurs qu'elles ont remplacées ;
- `journalClaude` : les 200 dernières entrées du journal (date, étape, raison, changements),
  annulations et retours compris ; il reste après un retour à l'état d'avant Claude ;
- `retoucheeParClaude` : « oui », visible et filtrable dans la Bibliothèque ;
- `proprietaireMemoire` : uuid de la photo à qui appartiennent ces champs (schéma 3) ;
- `variantesClaude` : pour chaque instantané de variante « Claude · <nom> », les réglages qu'il
  touche et sa date (schéma 4, version 2.0 ; voir Variantes) ;
- `apresClaude` : l'état où la dernière commande de Claude a laissé la photo (étape, `editCount`,
  `lastEditTime`, réglages simples), écrit par `withPrivateWriteAccessDo`, pour relever les
  corrections faites ensuite à la main (schéma 5, version 2.1 ; voir Retouche globale : pistes de
  la 2.1).

Sous la clé `Bibliotheque`, le classement garde aussi `iptc` (champs IPTC d'avant un paramètre
prédéfini de métadonnées, remis tels quels).

Constaté dans Lightroom Classic 15.6 (16 octobre 2026) : une copie virtuelle reçoit les champs du
module de son original. Claude avait retouché un original RAW ; l'utilisateur en a créé une copie
virtuelle et l'a réinitialisée (Adobe Color, réglages par défaut). Avant toute retouche, la copie
était « Retouchée par Claude » ; après les retouches de Claude sur la copie, la comparaison
`before_claude` montrait l'état d'avant Claude de l'original (CLASSIC CHROME, exposition +0,3,
vibrance 15), pas celui de la copie. `revert_to_original` y aurait remis les valeurs de
l'original, `undo_last` défait ses étapes, et `export_journal` mêlé les deux journaux.

Depuis, chaque écriture de la mémoire passe par `garder`, qui la rattache à sa photo
(`proprietaireMemoire`) ; une mémoire qui nomme une autre photo se lit comme une mémoire vide, et
la première écriture sur la copie l'efface entièrement avant d'écrire (même ce qu'elle ne touche
pas, comme le journal pendant un débruitage). Constaté par ses effets dans Lightroom Classic 15.6
(20 octobre 2026) : dans une écriture, un champ du module se relit avec sa valeur d'avant
l'écriture. Sur une copie qui avait reçu la mémoire de son original, chaque champ gardé relisait
donc l'ancien propriétaire et effaçait ceux déjà écrits : après la première retouche, seul le
dernier champ restait (« Retouchée par Claude »), et undo_last ne trouvait rien. `garder` ne
rattache maintenant une photo qu'une fois par écriture (`Photos.nouvelleEcriture`, au début de
chaque écriture d'`Ecriture`) ; la simulation applique les champs du module à la fin de
l'écriture. Une mémoire sans propriétaire (écrite avant le
schéma 3) reste lue comme avant et se rattache à la photo à sa prochaine écriture : sur un
original, c'est la sienne. Sur une copie virtuelle, elle est tenue pour reçue de l'original si son
journal commence par la même entrée que celui de l'original (un journal ne fait que s'allonger,
jusqu'à 200 entrées) ; il faudrait, pour s'y tromper, que Claude ait retouché la copie et
l'original dans la même minute, avec les mêmes valeurs et la même raison. Limites : le champ
« Retouchée par Claude » qu'affiche la Bibliothèque reste celui de l'original sur la copie tant que
Claude n'y a rien écrit (le module ne l'écrit pas pendant une lecture) ; une copie créée avant
cette correction, et retouchée ensuite par Claude, garde une mémoire mêlée, que le module tient
pour reçue puisque son journal commence comme celui de l'original (Claude n'y remet ni n'y défait
rien ; ⌘Z et l'historique de Lightroom restent). Lightroom copie aussi `proprietaireMemoire` :
constaté en 2.3 (18 octobre 2026), une copie virtuelle d'une copie retouchée par Claude
(`create_virtual_copy`) porte tous les champs de sa source, `proprietaireMemoire` égal à l'uuid de
la source et non au sien ; son journal (`export_journal`) est vide, et les instantanés (« Avant
Claude ») sont copiés aussi.

`undo_last` réapplique les valeurs remplacées par la dernière étape ; `revert_to_original`
réapplique `avantClaude` et efface les champs de mémoire (pas le journal). Les réglages que l'utilisateur a changés à la
main sans que Claude y touche restent. À la première retouche, un instantané « Avant Claude » est
créé (si la version de Lightroom le permet et que l'option est cochée).

## Garde-fous

- Mode « Proposer d'abord » : le module refuse `appliquer`, `recadrer`, `masquer`, `retoucher`,
  `ameliorer`, `supprimer`, `copier`, `masques` (sauf `lister`), `metadonnees`, `collections`
  (sauf `lister`), `copieVirtuelle`, `exporter` et `variantes` (`choisir`) sans `confirme`, et le
  message demande à Claude de montrer la proposition (`essayer`) ou les changements, et d'attendre
  l'accord.
- Pause (fenêtre de suivi) : Claude peut regarder, pas retoucher ; l'utilisateur peut toujours
  annuler depuis Lightroom.
- Limites réglables : variation de l'exposition par retouche (2 IL par défaut), saturation
  absolue (±30 par défaut).
- Écritures groupées : une commande sur plusieurs photos est une seule opération (⌘Z).
- « Confirmer dans Lightroom » (`accordDansLightroom`) : en mode « Proposer d'abord », `confirme`
  ne suffit pas ; la proposition attend dans la fenêtre de suivi (Accepter, Refuser), et un accord
  vaut pour une écriture, dans les 10 minutes. Une livraison en plusieurs lots ne le demande
  qu'au premier (`suite`).
- Photos protégées (`verifierProtection`) : copies virtuelles seulement, libellé de couleur
  protégé, photos rejetées ; plafond de photos par écriture (20 par défaut) sans `confirme`. Toutes
  les écritures sur des photos y passent, propositions comprises ; `annuler` et `revenir` non.
  Une livraison ne change pas les photos : elle n'y passe pas.
- Notes (1.1, voir Notation) : sans `apply`, `propose_ratings` et la commande `notation`
  n'écrivent rien dans le catalogue (ni pause, ni accord, ni garde-fous) ; Claude ne propose
  jamais 5 ★ (refus du serveur, puis du module). Les notes que l'utilisateur pose depuis la
  fenêtre (`Bibliotheque.noter`, avec `depuisLightroom` et `confirme`) passent par les garde-fous
  des photos (copies virtuelles seulement, libellé protégé, photos rejetées), sans la pause, ni
  « Proposer d'abord », ni l'accord dans Lightroom, ni le plafond de photos par écriture (le clic
  vaut accord explicite), et jamais pendant que Claude travaille dans la fenêtre. Celles que
  l'utilisateur demande à Claude de poser (1.1.1, `apply` : `confirme` sans `depuisLightroom`)
  passent par les mêmes garde-fous des photos et s'arrêtent à la pause ; ni « Proposer d'abord »
  ni le plafond de photos par écriture ne les retiennent (la demande explicite vaut accord), mais
  en mode « Proposer d'abord », l'accord dans Lightroom, s'il est coché, est demandé ; le refus
  dit alors de rappeler `propose_ratings` avec `apply = true`.
- Version minimale de Lightroom (`DevelopSetting.since`) : le serveur lit la version une fois
  (`etat`) et refuse un réglage plus récent qu'elle (Texture 8.3 ; HDR, couleur ponctuelle, flou
  d'objectif 13.0), plutôt que d'écrire une clé que Lightroom ignorerait.

## Livraison (`exporter`, `export_photos`)

`exporter` passe par la même `LrExportSession` que les aperçus, vers le dossier choisi
(`LR_export_destinationType = 'specificFolder'`), avec `LR_collisionHandling = 'rename'` : un
fichier qui existe déjà n'est jamais écrasé. Constaté le 17 octobre 2026 : la seconde livraison
d'une photo donne « DSCF4306-2.jpg », et le premier fichier garde son contenu (même empreinte).
Identifiants relevés dans le code de Lightroom Classic 15.6 (`AgExportSettings`,
`ExportMetadataSection`, `ExportSessionQueries`) : formats `JPEG`, `TIFF`, `PNG`, `DNG`,
`ORIGINAL` ; espaces `sRGB`, `AdobeRGB`, `DisplayP3`, `ProPhotoRGB` ; métadonnées `all`,
`copyrightOnly`, `copyrightAndContactOnly`, `allExceptCameraRawInfo`, `allExceptCameraInfo` ;
tailles `longEdge`, `shortEdge`, `megapixels` (`LR_size_megapixels` ; pour un côté, la valeur va
dans `LR_size_maxWidth` et `LR_size_maxHeight`) ; netteté `screen`, `matte`, `glossy`, niveaux 1 à
3. Constaté : 5 mégapixels donnent 2738 × 1825 px pour un RAW 3:2 ; une photo plus petite n'est
pas agrandie (`LR_size_doNotEnlarge`) ; « droits d'auteur seulement » retire la marque de
l'appareil ; le lieu est retiré par défaut.

Avant le rendu, chaque photo passe par `calculerAvantRendu` (masques IA, profil adaptatif) : la
fenêtre « Mises à jour IA recommandées » ne s'ouvre pas.

Modèles de noms : le serveur lit les fichiers `.lrtemplate` de
`~/Library/Application Support/Adobe/Lightroom/Filename Templates` (le nom du fichier est celui
qu'affiche Lightroom) : la suite `deflated` de jetons (`{ value = "date_YYYYMMDD" }`) et de textes
(`"-"`, ou `ZSTR "$$$/…= of "` dont il garde la valeur après le signe égal) devient
`LR_tokens = "{{date_YYYYMMDD}}-{{image_name}}"`, avec `LR_renamingTokensOn`,
`LR_tokenCustomString` (`custom_token`) et `LR_initialSequenceNumber`, que le serveur fait suivre
d'un lot à l'autre. Les modèles du nom de la prise de vue (`shoot_custom_token`, capture en mode
connecté) ne sont pas offerts ; un modèle qui numérote « x sur y » (`naming_sequenceTotal`) part
en une seule session. Constaté : « Nom personnalisé - Séquence », texte « Essai », départ 7 :
`Essai-7.jpg`, `Essai-8.jpg`, `Essai-9.jpg`.

Profils de livraison (serveur) : `web_5mp` et `pleine_qualite`, tirés des dossiers d'exportation
de l'utilisateur (« Lightroom Export 5 Megapixels », « Lightroom Export Full Quality », lus dans
les dossiers récents des préférences de Lightroom, `AgMRUPopupList_AgExport_destinationFolderPathPrefix`).
Ce sont aussi deux services de publication « Disque dur » de l'utilisateur, dont les réglages se
lisent (`publishService:getPublishSettings()`, clé par clé : `pairs` ne rend rien, table
observable), relevés le 18 octobre 2026 (2.3) : JPEG `LR_jpeg_quality = 1` (100), sRGB 8 bits,
`LR_outputSharpeningOn = false`, toutes les métadonnées, lieu et personnes retirés, mots-clés à
plat ; 5 mégapixels pour l'un, pleine résolution pour l'autre. Le profil `web_5mp` disait qualité 80
et netteté pour écran : il suit maintenant ces réglages (qualité 100, sans netteté de sortie). Le
serveur découpe la série en lots de 10 (progression, annulation entre deux lots).

`fenetreExport` sélectionne les photos (en affichant leur dossier au besoin) et ouvre la fenêtre
d'exportation de Lightroom (`photo:openExportDialog`, SDK 7.4) dans sa propre tâche, pour que la
réponse parte. Constaté en 2.3 (18 octobre 2026) : la réponse revient en 0,02 s
(`{ouverte: true, photos: 1}`), la fenêtre « Exporter un fichier » s'ouvre sur la photo, et Annuler
la ferme sans rien exporter.

`livraison` : `LrApplication.filenamePresets()` et `metadataPresets()` (nom → identifiant), et
`catalog:getPublishServices()` (`Services.decrire` : identifiant, nom, module de chaque service,
et les réglages des services Disque dur ; voir Livraisons types). Le module ne fait que les
lire : rien n'y est créé, changé ni publié.

### Formats, HDR, poids, filigrane (2.5)

Relevé dans le code de Lightroom Classic 15.6 (`AgExportSettings`, `ExportFileSettingsSection`) :
formats `JXL` (JPEG XL ; `LR_jxl_quality`, `LR_jxl_losslessQuality`), `AVIF` (`LR_avif_quality`,
0,7 par défaut), `PSD` (et `PSB`, pas offert) ; la qualité va de 0 à 1 comme `LR_jpeg_quality`.
Sortie HDR : `LR_enableHDRDisplay` et un espace HDR, `sRGB_hdr` (HDR Rec. 709), `p3_hdr` (HDR P3) ou
`Rec2020_hdr` (HDR Rec. 2020, pas en JPEG : `chooseAcceptableColorSpaces`) ; `Rec2020` existe aussi
en SDR. `LR_maximumCompatibility` (image SDR et carte de gain) : toujours vrai en JPEG HDR, faux en
PNG et PSD, au choix en AVIF, JPEG XL et TIFF (vrai par défaut). Profondeur (`main.40` du
désassemblage) : JPEG 8 bits, AVIF 10, PNG et JPEG XL 16 en HDR, TIFF et PSD 16 ou 32 en HDR ;
32 bits seulement en HDR. Le module refuse une sortie HDR pour une photo hors du mode HDR
(`HDREditMode`) : elle n'y ajouterait rien. Poids maximal : `LR_jpeg_useLimitSize` et
`LR_jpeg_limitSize` (en Ko), JPEG seulement. Filigrane : `LR_useWatermark` et
`LR_watermarking_id`, `<simpleCopyrightWatermark>` (les droits d'auteur de la photo) ou
l'identifiant d'un filigrane de l'utilisateur ; ni l'original ni le DNG n'en portent. Les
filigranes sont des modèles de Lightroom dans `Watermarks/*.lrtemplate` (type
« WatermarkingPreset », `id`, `title`, `value.items` : textes et images ; `AgWatermarkingData`) :
le serveur les lit comme les modèles de noms.

Constaté le 18 octobre 2026 (copie d'essai RAW passée en mode HDR, puis remise) :

- AVIF HDR avec carte de gain : 10 bits, Display P3, carte de gain ISO 21496-1 lue par ImageIO ;
  sans (`maximize_compatibility = false`) : « Display P3 ; SMPTE ST 2084 PQ ». JPEG HDR : 8 bits,
  carte de gain ISO 21496-1. PNG HDR : 16 bits, PQ. JPEG XL HDR Rec. 2020 : 16 bits, profil
  « nclc (9,1,2) », et une boîte `jhgm` (sa carte de gain), qu'ImageIO ne lit pas : le serveur la
  cherche dans le fichier. TIFF HDR 32 bits : P3 linéaire, en virgule flottante.
- Une photo hors du mode HDR est refusée avec sa raison ; JPEG XL qualité 80, AVIF (10 bits) et
  PSD 16 bits se livrent.
- Poids maximal : 200 Ko donnent 159 Ko, 100 Ko donnent 90 Ko, 60 Ko à 800 px donnent 57 Ko ; à
  1600 px, 60 Ko sont hors d'atteinte et Lightroom livre le plus petit fichier possible (74 Ko) :
  le serveur le dit (`au_dessus_du_poids`).
- Filigrane : le filigrane d'essai « Claude essai filigrane » (un texte, fichier écrit pour les
  essais et gardé) apparaît en bas à droite ; celui des droits d'auteur ne dessine rien sur une
  photo sans droits d'auteur (même image qu'une livraison sans filigrane).

### Livraisons types, noms exacts, dossier choisi (2.5)

Les livraisons types sont les services Disque dur (`com.adobe.ag.export.file`) : `livraison` lit
leurs réglages clé par clé (`getPublishSettings`, liste `CLES_SERVICE` de `Services.lua`) et le
serveur les traduit (`profilService`) : qualité de 0 à 1 en centièmes, taille `megapixels`,
`longEdge`, `shortEdge` (une autre, « wh », devient un grand côté, et le profil le dit), netteté,
métadonnées, lieu, poids, filigrane, HDR, dossier (`LR_export_destinationPathPrefix`, le dossier
habituel). Sans service Disque dur, les deux profils d'avant (`web_5mp`, `pleine_qualite`).
Constaté : les deux services de l'utilisateur donnent « Lightroom Export 5 Megapixels » (JPEG
qualité 100, sRGB, 5 mégapixels) et « Lightroom Export Full Quality » (pleine résolution).

Noms exacts : `photo:getNameViaPreset(id, texte, numero)` (identifiant de `filenamePresets`, le
chemin du fichier du modèle), sans l'extension, que le serveur ajoute d'après le format ; un nom
déjà pris dans le dossier est signalé (Lightroom y ajoutera « -2 »). Constaté : « Nom personnalisé
- Séquence », avec un texte et le départ 7 : `<texte>-7`, `<texte>-8`… ; « Date - Nom du fichier »
donne `27092023-IMG_2580`, comme l'exportation avec les jetons lus par le serveur : en français,
le jeton `date_YYYYMMDD` rend JJMMAAAA (le nom du jeton ne dit pas l'ordre).

Dossier choisi : `LrDialogs.runOpenPanel` (dossiers seulement, bouton « Nouveau dossier »), dans sa
propre tâche ; la commande attend le choix 40 s au plus, puis répond `en_attente`, et la suivante
relit le choix (une seule fenêtre ouverte). Constaté : la fenêtre « Dossier de livraison
(Claude) » s'ouvre dans Lightroom sur le dossier de départ, en colonnes ; « Choisir » sans
sélection rend le dossier affiché.

### Réimportation, aperçus dynamiques (2.5)

Réimportation : `LR_reimportExportedPhoto`, `LR_reimport_stackWithOriginal` et
`LR_reimport_stackWithOriginal_position` (`below` par défaut). Lightroom n'offre l'empilement
qu'avec « Même dossier que la photo originale » (`ExportLocationSection` : `canStackWithOriginal`
quand `export_destinationType = 'sourceFolder'`) : empilée, la livraison va dans le dossier de
l'original. Lightroom ajoute le fichier au catalogue après le rendu (`AgExportRendition` : `post`) ;
le module le retrouve par `findPhotoByPath` (10 s au plus). Constaté : un TIFF de la copie d'essai
RAW est ajouté (photo 53664756) et empilé sous l'original (pile de 3 : original, copie, TIFF) ;
réimporté dans un dossier neuf, le fichier ajoute aussi ce dossier au catalogue (panneau
Dossiers), qu'aucune fonction du SDK ne retire : la recette passe donc par l'empilement.
`undo_last` ne retire pas une photo réimportée ; la recette seule le fait (`retirerReimportees` :
chemin exact, réimporté par le module dans la même session, 30 min au plus), par
`LrSelection.removeFromCatalog` (SDK 14.3), la photo seule sélectionnée : constaté, retirée sans
fenêtre en 0,5 s ; le fichier va ensuite à la Corbeille.

Aperçus dynamiques : `catalog:buildSmartPreviews(photos)` rend `created`, `existed`, `failed`
(Lightroom montre sa barre de progression) ; `photo:deleteSmartPreview()` rend `deleted`. Le
module ne retire jamais l'aperçu d'une photo dont l'original manque. Constaté (original de la
copie d'essai JPEG renommé une minute) : la livraison à 1200 px part de l'aperçu dynamique
(802 × 1200 px), la pleine résolution est refusée avec sa raison ; `checkPhotoAvailability` a vu
l'absence plus de 12 s après le renommage (une livraison faite avant passe quand même par
l'aperçu, sans le dire). Un aperçu fait 0,3 Mo pour ce JPEG de 1489 × 2227 px.

## Variantes (`essayer` avec `instantane`, `variantes`)

`compare_variants` (serveur) fait une proposition par variante (`essayer`, `instantane = nom`) :
la variante est appliquée, rangée en instantané « Claude · <nom> »
(`createDevelopSnapshot(nom, true)`, dans une écriture, avec la mémoire `variantesClaude` : les
réglages que la proposition touche), rendue, puis la photo revient comme avant. Le serveur
compose la planche (état actuel, puis les variantes). L'Historique garde les étapes « Claude ·
essai : variante … ».

Relevé dans le code de Lightroom Classic 15.6 (`LrPhoto`, `DevelopTemplateBrowser`,
`DevelopSnapshotDataModel`) : `applyDevelopSnapshot(id)` lance la commande
`ag.develop.applySnapshotSettings` (`imageID`, `settingsID` = le `snapshotID` de
`getDevelopSnapshots`, un uuid), `deleteDevelopSnapshot(uuid)` la commande
`ag.develop.removeSnapshot` (l'image courante du module Développement), les mêmes que le panneau
Instantanés. Constaté le 17 octobre 2026 : dans une écriture, `applyDevelopSnapshot` ne change
rien, sans erreur ; hors écriture non plus, la photo n'étant pas affichée dans le module
Développement ; affichée (`Amelioration.afficherEnDeveloppement`, puis la vue d'avant remise),
elle prend l'instantané par son `snapshotID` ; l'effacement se fait de même, par l'`id_global`.

`variantes` (`choisir`) écrit d'abord la mémoire (étape avec la valeur d'avant de chaque réglage
de la variante, état d'avant Claude, journal, instantané « Avant Claude » la première fois), puis
pose l'instantané, photo affichée, et relit les réglages (3 s au plus) : si rien n'a changé,
l'étape est retirée et la commande échoue. `undo_last` défait la variante comme une retouche.
Limite : l'instantané remet ce que la photo avait quand la variante a été préparée ; un réglage
changé depuis, hors de ceux de la variante, ne se défait pas. `effacer` (ou `effacer_autres`)
efface les instantanés de variantes de Claude ; un nom donné avec le préfixe « Claude · »
s'efface même sans mémoire.

## Harmonisation d'une série (`match_series`)

Le serveur mesure la référence et chaque photo sur un aperçu d'analyse (`apercu`, avec
`Temperature` et `Tint`), calcule les écarts (exposition par la luminance médiane, dominante a* et
b* des tons neutres, contraste P95 − P5), puis propose des corrections relatives (`appliquer`,
`relatif`). Avec `confirm`, deux passes : après la première, une nouvelle mesure, puis une
correction de l'écart restant.

Relevé le 17 octobre 2026 dans Lightroom Classic 15.6, par des propositions mesurées sur un RAW de
X-H2S (5050 K, Teinte 14) et un JPEG d'essai : RAW, +600 K (−21 mired) montent b* de 4,5 et a*
de 2,0 ; −500 K baissent b* de 4,7 ; Teinte +10 : a* +2,4, b* −2,0. JPEG (balance relative),
Température +20 : b* +11,6, a* +2,1 ; Teinte +20 : a* +3,6, b* −3,6. Contraste +30 : P95 − P5
élargi de 5,7. Le serveur résout Teinte et Température ensemble (inverse de ces effets, par
unité) ; l'exposition suit la pente que la photo a montrée à la première passe (constaté : −0,85 IL
laissaient 0,2 IL d'écart) ; le contraste se borne à 30 par passe.

Constaté : refaite à chaque mesure, la sélection des tons neutres (chroma sous 15) perd les pixels
qui se colorent : à +600 K, b* restait à 12,2 → 12,3 et la part neutre tombait de 40 % à 8 %. Les
mêmes pixels, suivis d'une mesure à l'autre (`Measurements.neutres`, masque de la première),
donnent 12,2 → 16,7. Mais comparés à la référence (mesurée par sa propre sélection), ils
laissaient 4,2 de b* d'écart sur une photo que la mesure commune disait juste : les écarts se
mesurent donc par la même sélection des deux côtés, et les tons suivis ne servent qu'aux pentes.
Essai réel (deux photos d'essai de scènes différentes) : a* de −7,1 à −1,0 et de −5,4 à −0,2, b*
de −13,2 à −1,2, exposition à 0,05 IL près.

## Mode HDR

Réglages `HDREditMode` (0 ou 1), `HDRMaxValue` (limite HDR, en crans au dixième ; le menu de
Lightroom propose 1, 2, 3, 4 et 8, « Maxi ») et l'aperçu SDR : `SDRBrightness`, `SDRContrast`,
`SDRClarity`, `SDRHighlights`, `SDRShadows`, `SDRWhites`, `SDRBlend` (saturation des hautes
lumières), de −100 à +100 (relevé dans `AgDevelopParams` et `AgCameraRawUtils` de Lightroom
Classic 15.6). Constaté le 17 octobre 2026 : `applyDevelopSettings` les pose (`HDREditMode` relu
comme le nombre 1), `undo_last` les remet ; une photo jamais passée en HDR porte `HDRMaxValue =
2,3`. L'aperçu de Claude, un JPEG SDR, suit les curseurs SDR : luminosité SDR de +20 à −60, la
médiane L passe de 43 à 33. Claude ne voit pas le rendu HDR ; depuis la 2.5, `export_photos` livre
en HDR (`hdr`, voir Livraison).

## Ressources et guide de style

Ressources MCP : `developpeur://guide-de-style` (Markdown), `developpeur://notation` (depuis la
1.1 : le standard de notation, `Notation.standard`, en Markdown, sans commande au module ; voir
Notation), `developpeur://photo/active/apercu` et les
modèles `developpeur://photo/{id}/apercu` (JPEG, comme `view_photo`) et
`developpeur://photo/{id}/journal` (Markdown, comme `export_journal`). Leur lecture passe par la
file des outils (`resources/read`), une à la fois avec les appels d'outils ; une ressource
inconnue répond l'erreur −32002. Abonnement (`resources/subscribe`) à la photo active : voir
Messages entre le serveur et le module.

Le guide de style est un fichier Markdown de l'utilisateur
(`~/Library/Application Support/Developpeur/guide-de-style.md`), rangé par rubriques
(profils, lumière et contraste, couleurs, peaux, noir et blanc, grain, recadrage, livraison,
autres). `remember_style` le lit, ou y ajoute une préférence datée sous sa rubrique, seulement
avec `confirm` (la phrase approuvée par l'utilisateur). Les invites de retouche l'incluent
(coupé à 6000 caractères, le reste par la ressource).

## Retouche globale : pistes de la 2.1

Constaté dans Lightroom Classic 15.6, les 17 et 18 octobre 2026, sur les photos d'essai :

- **Balance sur un point neutre** (`white_balance_point`, `Tools+Balance.swift`) : le serveur
  mesure le point (disque de 0,8 % du grand côté, L*a*b* D65, pixels écrêtés exclus) sur l'aperçu,
  refuse un point brûlé, trop sombre (L* < 8) ou trop coloré (chroma > 25), et calcule la balance
  comme `match_series` (RAW : mireds et teinte, d'après les pentes relevées ; JPEG : relatif), puis
  mesure de nouveau et fait une seconde passe si l'écart dépasse 1. Fond gris d'un studio : a* 3,3,
  b* −15 → −1,1, −1,2 → 0, 0 en deux passes (5150 K, +19 → 6869 K, −7) ; annulées exactement.
- **Quantité d'un paramètre prédéfini** (`preset_amount`) : `applyDevelopPreset(preset, module,
  quantité)` (relevé dans `SdkApplyDevelopPreset` : arrondie, divisée par 100, ignorée hors de 0 à
  2). Vignettage « Élevé » : −30 à 100 %, −15 à 50 %.
- **Mélange noir et blanc automatique** (`auto_gray_mix`) : `AutoGrayscaleMix = true` par un
  paramètre prédéfini du module, après `ConvertToGrayscale` ; Lightroom calcule les `GrayMixer*`
  (−10, −19, −23, −27, −18, +10, +16, +4 sur un RAW), que l'étape mémorise ; annulation exacte. Le
  bouton Automatique de l'interface n'a pas répondu à un clic par l'Accessibilité.
- **Profil d'objectif choisi** (`lens_profile`, `ProfilsObjectif.swift`) : fait à la main,
  `LensProfileSetup = "Custom"`, `LensProfileName` (le `ProfileName` du `.lcp`),
  `LensProfileFilename` (le fichier), `LensProfileIsEmbedded = false` ; Lightroom calcule
  `LensProfileDigest`. Le module pose les trois premiers, et choisit le fichier des RAW ou celui
  des autres formats (deux fichiers du même nom) ; Lightroom calcule l'empreinte comme à la main.
  Les profils se lisent dans les dossiers `LensProfiles/1.0` (application, `/Library`, utilisateur :
  3633 fichiers ici). Retour au profil par défaut : `LensProfileSetup = "LensDefaults"` posé par
  `applyDevelopSettings` ne remplace pas « Custom » (constaté, pour `lens_profile: "auto"` comme pour
  l'annulation) ; par un paramètre prédéfini du module avec `LensProfileEnable`, comme ceux d'Adobe
  (« Adobe Vivid + Lens »), oui, et Lightroom reprend le profil par défaut (« Camera Settings »,
  embarqué). Sans `LensProfileEnable`, ce paramètre prédéfini le met à 0. L'annulation et le retour
  à l'origine l'appliquent quand l'état d'avant est « LensDefaults », puis reposent une balance
  personnalisée.
- **Upright avec repères** (`upright_guides`) : fait à la main, `PerspectiveUpright = 5`,
  `UprightFourSegmentsCount`, `UprightFourSegments_i = "x1,y1,x2,y2"` (%0.9f) dans le repère du
  fichier avant l'orientation ; Lightroom calcule `UprightTransform_5`. Posés par
  `applyDevelopSettings` ou par un paramètre prédéfini du module (même avec `UprightVersion = 0`),
  les repères sont rangés et affichés dans l'outil, mais Lightroom ne calcule pas la transformation,
  ni au rendu ni à l'ouverture de l'outil : seul le bouton « Mettre à jour » de la section Upright
  la calcule d'après eux (commande `ag.develop.reanalyzeUprightImageSettings`, qui vide les clés de
  `getUprightTransformKeys` ; hors de portée d'un module). Le module pose les repères et la remarque
  demande ce clic à l'utilisateur.
- **Transformations Upright exactes** (`copy_settings` avec `include_upright_exact`) : toutes les
  clés `Upright*` de la source et `PerspectiveUpright`, sans `UprightDependentDigest` ni
  `UprightGuidedDependentDigest` (le Copier de Lightroom les retire aussi, relevé dans
  `AgCameraRawNamedSettingsCopyPaste`). Constaté : les matrices sont gardées sur la photo visée,
  après un rendu aussi ; annulation exacte.
- **Expositions d'après la prise de vue** (`match_series` avec `by: "exif"`) : lumière reçue
  log2(t·S/N²) d'après l'ouverture, la vitesse et l'ISO (`reglages` rend `prise_de_vue`) ;
  `Exposure2012` de la référence plus l'écart, borné à ±5 (dit). Le flash ne compte pas. Plan
  d'abord, `confirm` pour appliquer ; la limite d'exposition des préférences du module s'applique.
- **Instantané à la demande** (`snapshot`) : « Claude · <nom> », pris dans l'écriture de l'étape,
  avant les réglages (`creerInstantane`) ; un aussi, de lui-même, avant `process_version`.
- **Rotation d'un quart de tour** (`rotate`) : `photo:rotateLeft()` et `rotateRight()` (SDK 7.4 ;
  relevé : la commande `ag.library.rotate`), hors d'une écriture, attendue sur
  `getRawMetadata("orientation")` ; constaté AB → BC, dimensions échangées. La mémoire garde
  `Rotation` (quarts à refaire pour revenir), qui n'est pas un réglage ; `undo_last` et
  `revert_to_original` la remettent (`Conversions.lua`). Une proposition ne la montre pas.
- **Corrections de l'utilisateur** : à la fin de chaque commande qui écrit, le champ `apresClaude`
  garde l'étape, `editCount` et `lastEditTime` (métadonnées brutes, des nombres) et les réglages
  simples, par `catalog:withPrivateWriteAccessDo` (constaté : pas d'opération de plus dans Édition
  › Annuler). `get_settings` et `view_photo` rendent `corrections_utilisateur` quand
  `editCount` ou `lastEditTime` ont changé depuis (constaté : Vibrance remise à 0 et Ombres +54 à la
  main sont relevées). Ce que Lightroom résout lui-même peu après l'écriture (nom et origine du
  profil d'objectif par défaut, réglages absents qu'il ajoute) n'en est pas. `undo_last` dit ce
  qu'il remet de ces corrections et ce qui reste. Les consignes disent de proposer
  `remember_style`, avec l'accord de l'utilisateur.

## Masques : pistes de la 2.1

- **Personne précise** (`add_mask`, `kind: "person"`, `person` ou `person_at`, `part`) : fait à la
  main, un `Mask/Image` de sous-type 0, catégorie 20036 pour la personne entière (ou celle d'une
  partie : 5 les cheveux), `InstanceIDs = {{InstanceID = n − 1}}`, et `InstanceBounds`, les cadres
  de toutes les personnes (Left, Top, Right, Bottom de 0 à 1, de gauche à droite). Constaté le
  18 octobre 2026 : sans `InstanceBounds`, ou avec un seul cadre, ou deux cadres de l'image entière,
  Lightroom retire `InstanceIDs` et calcule autre chose (sous-type 3, catégorie 13) ; avec les six
  cadres d'une photo de groupe, même décalés de 0,02, il calcule exactement le masque fait à la
  main (même `MaskDigest`) et range `ReferencePoint` sur la personne. Le serveur tire les cadres de
  Vision (`VNDetectHumanRectanglesRequest`, à moins de 0,02 de ceux de Lightroom ici) sur l'aperçu,
  choisit la personne dont le cadre contient `person_at`, et refuse un numéro au-delà de ce que
  Vision trouve ; le module ramène les cadres dans le fichier et, après le calcul
  (`Retouche.verifierPersonnes`), retire un masque que Lightroom n'a pas reconnu, et le dit.
  `sansCalculsIA` garde `InstanceBounds` (un recalcul sans eux perdait la personne, constaté).
  Copié sur une autre photo, un tel masque n'est reconnu que si les personnes y sont aux mêmes
  places : la copie le dit (`Locaux.personnesPerdues`).
  **Personne seule** (constaté le 20 octobre 2026 sur le portrait d'essai 53709912, une seule
  personne pour Lightroom et pour Vision) : fait à la main (Masquage › Personnes › Personne 1,
  Toute la personne), le masque n'a ni `InstanceIDs` ni `InstanceBounds` : sous-type 0, catégorie
  20036, `ReferencePoint` sur la personne. Envoyé ainsi par le module, il donne le même masque
  (même `MaskDigest`, même `ReferencePoint`) ; la peau du visage de même (sous-type 0, catégorie 2).
  Envoyé numéroté avec un seul cadre, Lightroom le calcule aussi à l'identique, puis retire
  `InstanceIDs` et `InstanceBounds` : le module le prenait pour une personne non reconnue et le
  retirait (« sur 1 trouvées par Vision »), d'où l'échec de la recette sur un portrait. Depuis, le
  serveur marque `seule` quand Vision ne trouve qu'une personne ; le module envoie alors le masque
  sans numéro ni cadres, et `Locaux.numeroPersonne` compte comme la personne 1 un masque de
  sous-type 0 sans `InstanceIDs` dont la catégorie est celle d'une personne
  (`Locaux.CATEGORIES_PERSONNE` : 20036 et les parties ; le sous-type 0 sert aussi à l'arrière-plan,
  22, et au paysage, 5000x). `Locaux.personnesPerdues` signale un tel masque qui n'est plus de
  sous-type 0 après un recalcul. La simulation de la liaison suit ce constat (une seule personne
  trouvée : masque de personne calculé sur elle, numéro et cadres retirés).
- **Affinage d'un masque IA** (Lightroom 15.5, `refine` : contour progressif et contour) : rangé
  dans le `Mask/Image` même : `Feather` (curseur 25 → 0,354, 50 → 1,92, 100 → 10 ; le serveur suit
  10 × (s/100)^2,381) et `EdgeShift` (le curseur divisé par 10). Constaté : posés par le module,
  ils restent avec l'empreinte du masque, sans nouveau calcul.
- **Reprendre un masque** (`edit_mask`, commande `masques`, `Masques.lua`) : lister, masquer et
  afficher (`CorrectionActive`), retirer, dupliquer (nouveaux identifiants, inversé au besoin),
  affiner, recalculer (empreintes retirées, toute la liste par un paramètre prédéfini du module),
  retirer les masques vides. Constaté : chacun garde les empreintes des autres masques, et
  `undo_last` le défait ; la liste rend le contour en valeurs de curseurs.
- **Masques vides** : `catalog:deleteAllEmptyMasks(photos)` (SDK 14.0 ; relevé : la commande
  `ag.develop.deleteEmptyMasks`), hors d'une écriture, après le calcul d'un `add_mask` qui porte des
  masques IA : constaté, « Visages » sur un paysage est retiré et dit, le ciel reste ; l'étape garde
  la liste d'avant (annulation exacte).
- **Pinceau d'affinage du flou d'objectif** (`lens_blur.refine`) : une `Correction` par groupe de
  traits dans `DepthBasedCorrections` (`Mask/Aggregate` de `Mask/Paint`, touches dans le repère du
  fichier, `LocalCorrectedDepth` −1 Net, +1 Flou, `CorrectionReferenceX/Y` sur le trait), comme à
  la main. Constaté : posé par le module, Lightroom recalcule la carte de profondeur et le rendu
  floute le visage tracé en mode Flou ; `get_settings` compte les traits
  (`flou_objectif_affinage`).
- **Mise au point sur un cadre** : faite à la main, `SampledArea` (« haut gauche bas droite »),
  `FocalRangeSource = 2`, et Lightroom mesure `SampledRange` et `FocalRange` dans la carte de
  profondeur. Posés par un module, cette mesure ne se fait pas (`SampledRange` reste « 0 0 ») et la
  zone passe en manuelle (`FocalRangeSource = 3`) : pas de `focus_box` ; `near` et `far`, ou à la
  main.

## Poussière du capteur

Relevé dans Lightroom Classic 15.6 (`DevelopDustDistractionRemoval`, `LrDevelopController`) : la
recherche se lance par `AgDevelopSupport.handleDistractionRemovalSensorDust`, depuis l'interface ;
aucune fonction du SDK ne la lance. Elle est locale et rapide ; le filtre « Dust Removal »
(`FilterID = 6`) porte ses cadres (`SrcBounds…`, `DstBounds…`, `…DefaultCropArea…` : l'image entière
du fichier), `CompressedSettings` et sa table (`Table_<empreinte>`, les taches trouvées), et une
image par tache (`Images`). Sans poussière trouvée, rien n'est gardé. Constaté le 18 octobre 2026 :

- un filtre posé par le module sans résultat est refusé sans ses cadres (« Invalid parameters for
  constructing an AgRect »), puis vidé par Lightroom avec eux, même sur une photo qui a de la
  poussière ;
- copié d'une autre photo, il est gardé tel quel sur une photo aux mêmes réglages et y colle les
  taches de la source (seule zone qui diffère du rendu sans lui : celle d'une tache de la source),
  même ses empreintes d'entrée retirées (Lightroom les remet) ; sur une photo tournée, il est vidé.
  Le Coller de Lightroom, lui, invalide la référence (`invalidateReference`) et refait la recherche
  sur chaque photo.

`remove_distractions` ne fait donc que retirer une suppression de la poussière (`dust: {"remove":
false}`) ; la poussière d'une série reste à faire à la main : Supprimer › Poussière sur une photo,
puis Copier et Coller de Lightroom avec la case Poussière.

## Synchronisation automatique

Constaté dans Lightroom Classic 15.6 : avec « Synch. auto » activée et plusieurs photos
sélectionnées, les écritures du SDK (`applyDevelopSettings`, paramètres prédéfinis du module) sur
la photo active ne se sont pas propagées aux autres photos sélectionnées. Les traitements de
`LrDevelopController` (débruitage, reflets) et la pose d'un instantané se font la photo seule
sélectionnée, par précaution. Le README conseille de couper « Synch. auto » pendant que Claude
travaille.

## Paramètres prédéfinis invisibles du module

Les masques IA, le flou d'objectif et les modes automatiques passent par des paramètres
prédéfinis du module (`addDevelopPresetForPlugin`) : un fichier `.lrtemplate` par nom dans
`~/Library/Application Support/Adobe/Lightroom/Plugin Develop Presets/<id du module>`, que
Lightroom charge à chaque lancement. Le module les efface à son chargement et à son arrêt
(`Menage.lua`), `install.sh` aussi, Lightroom fermé. Constaté le 17 octobre 2026 : à la fermeture
de Lightroom, `LrShutdownPlugin` (`Arret.lua`) ne s'exécute pas (un fichier créé pendant la
session restait après la fermeture) ; au lancement suivant, `Init.lua` l'a effacé (« 1 paramètre
prédéfini invisible de la session précédente effacé »). Le SDK offre `LrShutdownApp` pour la
fermeture de l'application (`LrShutdownFunction(fini, progression)`, relevé dans
`AgSdkPluginLoader`), mais Lightroom montre alors une fenêtre « tâches de fermeture » du module à
chaque fermeture : le ménage au chargement l'évite.


## Vérifications de la 2.3

Faites le 18 octobre 2026 dans Lightroom Classic 15.6, sur des copies virtuelles d'essai, chacune
remise ensuite. Les constats qui
ont changé le code sont aussi dans leur section (Bibliothèque, Livraison, Profil, Montrer, Tri,
Mémoire des retouches, Suppression des distractions, Messages, Délai des appels d'outils).

- **Recharger le module** (Gestionnaire de modules externes › Outils de l'auteur du module externe
  › Charger de nouveau le module ext.) : la nouvelle instance démarre la liaison, l'ancienne note
  « Liaison arrêtée » quelques secondes après ; les deux prises écoutent et le serveur obtient une
  réponse en moins de 6 s, sans relancer Lightroom. Mais un fichier `.lua` ajouté au module depuis
  le lancement de Lightroom ne se charge pas : « Une erreur interne s'est produite. Could not load
  toolkit script: <nom> », une fenêtre par commande, qui bloque la liaison. Une installation qui
  ajoute un fichier demande donc de relancer Lightroom (`install.sh` le dit quand Lightroom est
  ouvert).
- **Balance sur un point d'un JPEG** (`white_balance_point`, cadre blanc d'une porte) : sur la
  photo telle quelle, a* −0,2 et b* 1,3, une passe (Température −2, Teinte +2 en relatif,
  `IncrementalTemperature`, `IncrementalTint`), a* 0,3 et b* −0,5. Avec une dominante posée
  (Température +25, Teinte −15 : b* 17,8), la première passe revient à 0 et 0 (b* 1,3), la seconde
  à −2 et +2. L'échelle relative d'un JPEG suit donc la même pente que celle des RAW.
- **Yeux rouges**, sur une vraie photo au flash (Kodak DX4900, 2002 ; copie « Claude essai yeux
  rouges », rangée dans la collection) : les pupilles et le `rayon_yeux_rouges` (0,003) de Vision,
  tels quels dans `retouch_spots`, donnent `RedEyeInfo` (ellipse 0,003 × 0,0045 sur une photo 3:2,
  `pupilDarkenAmount` 0,5) ; au zoom, plus de rouge : la part de pixels rouges dans les pupilles
  passe de 0,36 et 0,25 à 0,01 et 0. `undo_last` : réglages identiques.
- **Personne précise copiée sur une rafale** (DSCF4306 et DSCF4307, prises à 2 s d'intervalle) :
  le masque « personne 3 » (`InstanceIDs` 2, six `InstanceBounds`) copié par `copy_settings` avec
  `include_masks` garde les cadres de la source, et Lightroom le recalcule (autre `MaskDigest`) ; la
  zone éclaircie sur la seconde photo est entre 0,45 et 0,60 de la largeur, pour un cadre source de
  0,450 à 0,554 : la même personne. Aucune remarque. L'annulation laisse `AILook = {}`, la version
  18.7 de la Look et `MaskGroupBasedCorrections = {}`, sans effet visible.
- **Taches sur une photo en super résolution** (RAF vertical, 4160 × 6240 devenu 8320 × 12480) : une
  tache près du bord droit (x 0,951) tombe au bon endroit (centre relu à 0,948 pour l'objet à 0,950,
  recalage jusqu'à 40 px) et retire proprement l'objet avec un rayon assez grand.
- **Upright avec repères, de bout en bout** : deux repères calés sur `measure_angle` ; posés, la
  transformation n'est pas calculée (`UprightTransform_5` identité) ; au clic « Mettre à jour » (fait
  par Claude à la place de l'utilisateur, panneau Transformation), Lightroom calcule
  `UprightTransform_5`, retire les analyses 0 à 4, remet le centre à 0,5 et la focale à 35, et
  resserre un peu le cadre (contrainte) : `view_photo` le voit comme une correction de
  l'utilisateur, et `undo_last` remet Upright, les repères, le cadre et la contrainte (sa remarque le
  dit) ; seules les analyses Upright en cache restent autres, sans effet Upright désactivé.
- **Fenêtre de suivi** : une proposition qui attend l'accord dans Lightroom affiche maintenant la
  raison donnée par Claude, et le journal ne la note plus « Refusé » (le refus fait à Claude porte
  `Liaison.EN_ATTENTE`). Capture de la fenêtre de suivi : `docs/suivi.png`.

## Ajouts de la 2.4

Faits le 18 octobre 2026 dans Lightroom Classic 15.6, sur des copies virtuelles d'essai et, en
lecture seule, sur la séance de 329 photos du tri (voir Tri d'une séance). La
commande `diagnostic` avec `valeurs` lit sans rien écrire le jeu de libellés actif, le filtre de
la Bibliothèque et ses paramètres prédéfinis, l'original et l'aperçu dynamique de la photo active.

- **Yeux fermés** (`VisionAnalysis.openness`, `PhotoTriee.yeuxFermes`). Vision ne dit pas si un
  œil est ouvert ; l'ouverture se mesure sur le contour de l'œil (`leftEye`, `rightEye`) : l'étendue
  perpendiculaire à l'axe des deux points les plus éloignés (les coins), sur la longueur de cet axe,
  insensible à l'inclinaison du visage ; le plus ouvert des deux yeux (un clin d'œil ne compte
  pas) ; pas de lecture sous 12 px de largeur d'œil. Relevé sur 59 visages de cette séance
  (aperçus de 1344 px, regardés un à un) : fermés ou plissés de 0,05 à 0,11, ouverts à partir de
  0,14 (de 0,14 à 0,16, un sourire qui plisse, les yeux visibles) ; seuil 0,12. Au tri, un défaut
  si un sujet (visage d'au moins la moitié de la largeur du plus grand) a les yeux fermés : 41
  photos sur les 249 aux yeux lisibles (330 photos triées en 26 s, comme en 1.9).
- **Piles** : `isInStackInFolder`, `topOfStackInFolderContainingPhoto` (une photo, aussi par
  `batchGetRawMetadata`), `stackPositionInFolder`, `countStackInFolderMembers` se lisent. Une copie
  virtuelle est empilée avec son original (constaté : les copies d'essai de DSCF4306 et DSCF4307,
  dans le dossier de cette séance). Au tri, une pile et une rafale qui se touchent font un seul groupe,
  dont une seule photo est proposée ; la description d'une photo donne sa pile.
- **Jeu de libellés** : `getLabelMapToColorName` (dans une tâche) rend texte → couleur
  (`Rouge = red`, `Jaune = yellow`… dans le catalogue de Dany). Le module le lit d'abord ; les
  essais d'avant (texte d'une photo de cette couleur, puis textes par défaut) restent pour un
  Lightroom qui ne le donnerait pas.
- **Filtre de la Bibliothèque** (`montrer` avec `filtre`, `filtre_preset`, `remettre_filtre`).
  `getCurrentViewFilter` rend une table plus riche que la référence du SDK : `noLabel` (la
  référence écrit `nolabel`), `labelOp`, `export`, `stack`, `gpsLocation`, `comments`, `likes`,
  et le texte « <nil> » pour un critère vide, comme les paramètres prédéfinis de filtre de
  Lightroom (`Filter Presets/*.lrtemplate`) ; le second résultat est le nom du paramètre
  prédéfini actif (« Filtres désactivés »). Constaté : un filtre posé sans `columnBrowserDesc`, et
  le paramètre prédéfini « Filtres désactivés », remettent les colonnes du filtre Métadonnées par
  défaut (date, appareil, objectif, libellé) ; le module bâtit donc le filtre sur une copie du
  filtre actuel et remet l'état d'avant par ses valeurs exactes, colonnes comprises (les colonnes
  d'exposition de Dany, perdues au premier essai, ont été remises : « Informations
  d'exposition », puis les filtres coupés sur ses colonnes). `setViewFilter` pose drapeau (`pick` :
  `flagged`, `rejected`, `unflagged`), note (`minRating`, `ratingOp`), relus. Une photo cachée par
  le filtre ne se sélectionne plus : la réponse le dit (`restore_filter`).
- **Original absent** : `checkPhotoAvailability` rend faux dès que le fichier est renommé
  (essai : l'original de la copie d'essai JPEG, `IMG_2580.JPEG`, renommé une minute puis remis),
  et vrai moins de 10 s après sa remise ; `smartPreviewInfo` est une table vide sans aperçu
  dynamique. Refus constatés, avec le chemin et la marche à suivre : débruitage (`enhance_photo`),
  aperçu sans aperçu dynamique (`view_photo`), livraison (`export_photos`) ; la suppression des
  reflets suit le même chemin (simulation).
- **Position GPS** : `gps` se pose (`{ latitude, longitude }`) et s'efface par nil (constaté,
  relu `nil` après `undo_last`) ; `gpsAltitude` se pose ; la direction n'est pas copiée d'une
  photo de téléphone (c'est celle du téléphone). `dateTimeOriginal` (brute) est un instant
  absolu : entre un X-H2S (heure sans fuseau) et un iPhone (avec fuseau), l'écart relu est exact
  (6 h 03 min 31 s entre DSCF4307 et IMG_7928, 21 811 s). La séance au boîtier et les photos du
  téléphone de Dany ne se recouvrent pas dans le temps : l'essai s'est fait avec un écart
  maximal élargi, puis défait.
- **Jour d'une prise de vue** : `LrDate.timeToW3CDate` donne l'UTC ; les photos du téléphone
  prises le 28 juin 2025 à 20 h 13 (heure de l'Est) répondaient à `date_from = 2025-06-29`. Le
  jour se lit maintenant par `timeToUserFormat(t, '%Y-%m-%d')`, à l'heure locale (la simulation
  décale son heure locale de `S.fuseau`).
- **Collections et mots-clés** : `setName`, `setParent` (nil : à la racine) et
  `setSearchDescription` d'une collection, `setAttributes { keywordName, synonyms }` d'un mot-clé,
  chacun dans une écriture, constatés et relus (une collection dynamique d'essai, restée ;
  synonymes du mot-clé de la recette posés puis vidés ; un mot-clé d'essai renommé puis remis).
  `createKeyword` reçoit les synonymes d'un mot
  de Vision (son nom anglais) à la création. undo_last ne défait pas la structure du catalogue :
  la réponse donne l'état d'avant.
- **Barre de progression** : `LrProgressScope { title }`, `setCancelable`, `setPortionComplete`,
  `setCaption`, `isCanceled` et `done` répondent sans erreur dans une commande du module, la barre
  passant d'une commande à l'autre (commande `progression`, identifiant de l'appel). L'affichage
  et la croix n'ont pas été vus à l'écran (accès refusé) : `isCanceled` est relu à chaque avancée,
  et une barre sans nouvelle depuis 5 min se ferme à la commande suivante.
- **Sauvegarde** : `LrApplication.backupAtNextShutdown(_PLUGIN.id)` (`get_status`,
  `request_backup`) ; la sauvegarde se fait à la fermeture suivante, par la fenêtre de Lightroom.
- **Photos exportées** : constaté en recette, un aperçu de Claude (`view_photo`, rendu par
  `LrExportSession` dans un dossier temporaire) fait passer `isExported` à vrai : la copie d'essai
  du X-T20, jamais exportée, l'était après la première étape. Le module note donc
  `apercuSeulement = 'oui'` (champ privé, écriture privée, schéma 6) quand un aperçu fait passer une
  photo à « exportée », et une livraison de Claude ou une publication de la fenêtre Publication
  l'efface (écriture privée) ; « exportée » = `isExported` sans ce champ (`Photos.exportee`). Les
  photos rendues par Claude avant la 2.4 restent comptées exportées ; une photo que Claude a rendue
  puis que l'utilisateur exporte lui-même par Fichier › Exporter compte encore comme jamais
  exportée (Lightroom ne dit pas qui a exporté).
- **Lectures groupées** : `batchGetFormattedMetadata`, `batchGetRawMetadata` et
  `batchGetPropertyForPlugin` décrivent les listes (`selection`, `chercher`, `vignettes`) ;
  « retouchée par Claude » n'y compte que si `proprietaireMemoire` est l'uuid de la photo.
- **Texte alternatif** : `altTextAccessibility` et `extDescrAccessibility` se lisent par
  `getRawMetadata` et s'écrivent par `setRawMetadata` ; `event` et `personShown` par
  `getFormattedMetadata` et `setRawMetadata` (recette : relus, puis défaits).
- **view_photo et `compare`** : l'outil reste annoncé en lecture seule ; les deux étapes « Claude ·
  comparaison » de l'Historique remettent la photo telle qu'elle était, et sa description le dit.

## Ajouts de la 2.5

Faits le 18 octobre 2026 dans Lightroom Classic 15.6, sur des copies virtuelles d'essai, chacune
remise ensuite. Les détails sont dans Livraison (Formats, HDR, poids, filigrane ; Livraisons
types, noms exacts, dossier choisi ; Réimportation, aperçus dynamiques). Le code de
Lightroom s'est lu en lecture seule par un désassembleur de bytecode Lua 5.1 (en-tête standard ;
les numéros de ligne de Lightroom ne se lisent pas), dans `Export.lrmodule` et `Resources`.

- **Diagnostic** : `methodes` sonde aussi `service_publication` (le premier service de
  publication). Constaté : `getPublishSettings`, `getNameViaPreset`, `buildSmartPreview`,
  `buildSmartPreviews`, `findPhotoByPath`, `LrDialogs.runOpenPanel` et
  `LrSelection.removeFromCatalog` existent.
- **Reste dans le catalogue de l'essai** : le dossier vide « reimport » (sous le dossier
  temporaire de la session de Claude), ajouté par la réimportation d'essai dans un dossier neuf ;
  le SDK ne retire pas un dossier (clic droit › Supprimer, à la main). Le fichier de filigrane
  « Claude essai filigrane » est gardé pour les essais et la recette.
