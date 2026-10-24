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

La 1.2 de Développeur (un rendu plus juste sur chaque photo) a sept chantiers, chacun dans sa
section : Liaison fermée, Peau, Éclaircir et assombrir, Éclairage mixte, Bilan d'une passe à
l'autre, Écran, Lecture du boîtier ; ce qui en reste à voir dans Lightroom est dans À constater
dans Lightroom (1.2). Elle porte aussi ce qui a suivi la 1.1.1 : la Conversation claire seule,
l'aperçu de la photo active avec son point de mise au point et la proposition préparée à
l'ouverture (voir Fenêtre Claude), le point de mise au point sur un zoom de `view_photo` (voir Tri
d'une séance) et le masque d'une personne seule gardé (voir Masques : pistes de la 2.1).

La 1.3 (apprendre en regardant Claude), publiée le 21 octobre 2026 (`CHANGELOG.md`, « 1.3 »), a
cinq chantiers, chacun dans sa section : Pourquoi ? :
l'avant/après des étapes, Leçon de la photo, Je le fais, Composition lue, Carnet de progrès ; ce
qui en reste à voir dans Lightroom est dans À constater dans Lightroom (1.3). Elle porte aussi la
fenêtre B, l'allure de la maquette « B · Conversation claire », agrandie à la demande de Dany
(voir Fenêtre Claude › Fenêtre B), et les corrections tirées des mesures du 21 octobre 2026 dans
Lightroom (photo active remise, texture au point de mise au point, faux visages, ligne affinée,
empreinte des étapes, registre des notes remis par la recette).

## Architecture

Deux pièces :

- le connecteur MCP-Développeur : `mcp-developpeur`, serveur MCP natif en Swift
  (`serverInfo.name` MCP-Developpeur, `title` « MCP-Développeur », bundle
  `com.danymenard.mcp-developpeur`), installé dans `~/Library/Application Support/Developpeur/`
  et inscrit sous la clé `MCP-Developpeur` dans Claude Desktop et Claude Code ; 36 outils (34
  jusqu'à la 1.2 ; la 1.3 ajoute `read_composition` après `measure_angle` et `photo_lesson` à la
  fin, tous deux en lecture seule) et 10 invites (a_ma_facon depuis la 1.3.5) ;
- le module Lightroom « Développeur » (`Lightroom/Developpeur.lrplugin`, identifiant
  `com.danymenard.developpeur`, Lightroom Classic 13.3 au moins), qui porte la liaison avec le
  serveur (`Liaison.lua`), la fenêtre Claude (voir Fenêtre Claude), les fenêtres Publication et
  Consommation, le registre des notes proposées (`Notation.lua`, voir Notation), depuis la 1.3
  l'avant/après des étapes (`Etapes.lua`) et le carnet de progrès avec les leçons des photos
  (`Carnet.lua`, `carnet.json`), et la fenêtre de suivi de la liaison. Journaux :
  `~/Library/Logs/Developpeur/`
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
propre serveur : des connexions courtes les laissent se succéder. Depuis la 1.2, chaque ligne,
`ping` compris, porte le jeton privé de la liaison, sans lequel le module la refuse (voir Liaison
fermée).

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
→ {"id": 7, "jeton": "<64 chiffres hexadécimaux>", "command": "appliquer", "params": {…}}
← {"id": 7, "result": {…}}
← {"id": 7, "error": "message en français, montré tel quel à Claude"}
← {"id": 7, "error": "Liaison fermée : …", "code": "jeton"}
← {"id": 8, "result": {…}, "evenements": {"photo_active": true}}
```

`jeton` (1.2) : le jeton privé que le module tire à chaque démarrage de la liaison et range dans
`liaison.jeton` ; le serveur le relit à chaque connexion. Une ligne sans lui, ou avec un autre,
reçoit une erreur `code = "jeton"` et n'atteint pas la commande ; un serveur qui ne trouve pas le
fichier n'envoie pas la clé (un module d'avant la 1.2 accepte alors la ligne comme avant). Voir
Liaison fermée.

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
| `ping` | — | `{pong: true, version}` ; depuis la 1.2, refusé lui aussi sans le bon `jeton` |
| `etat` | `sauvegarde?` | versions, catalogue, mode, pause, limites, photo active, `liaison_fermee` (1.2 : vrai) ; avec `sauvegarde`, la sauvegarde du catalogue demandée pour la fermeture suivante |
| `selection` | `limite` | `total`, `renvoyees`, `photos` (id, fichier, données de prise de vue, note, drapeau, libellé, pile, `active`) |
| `reglages` | `photo?`, `cles`, `details?`, `toutes?` | `reglages` (valeurs des clés demandées), `photo` (id, fichier, `copie_virtuelle`), `echelle_temperature`, `version_processus`, `profil`, `intensite_profil`, `appareil`, `recadrage` (angle, dimensions, orientation) ; avec `details` : `courbes_par_points`, `masques` (composants avec leur mode), `couleurs_ponctuelles`, `taches`, `yeux_rouges`, `filtres_calcules`, `amelioration` (photo affichée dans le module Développement seulement), `classement` (note, drapeau, libellé, titre, mots-clés) ; avec `toutes` : `tous`, tout ce que Lightroom range |
| `apercu` | `photo?`, `taille` (0 = pleine résolution), `cles`, `comparer?`, `point_af?`, `entier?` | `chemin` d'un JPEG sRGB rendu par Lightroom, plus ce que donne `reglages` ; avec `comparer` (`avantClaude` ou `etapePrecedente`), `chemin_avant` ; `a_savoir` si des masques IA n'étaient pas encore calculés (voir Aperçus et masques IA) ; avec `point_af` (1.1.1, `view_photo` sur l'aperçu entier ; après la 1.1.1, sur un zoom `region` aussi, jamais sur un avant/après), la photo décrite comme pour `vignettes` (`chemin_original`, `marque`, `geometrie`, et depuis la 1.3.1 `sensibilite`, l'ISO en nombre, pour le carnet de progrès), `point_af_toujours` (préférence `pointMiseAuPoint`) et `evaluation` (`Notation.resume`) : voir Tri d'une séance › Point de mise au point ; avec `point_af` aussi (1.2), `etapes_claude` (`nombre`, `derniere` : les étapes de Claude gardées pour la photo, `etapesClaude`, lues seulement), pour le bilan de `view_photo` (voir Bilan d'une passe à l'autre) ; avec `comparer = versionClaude` (1.3), `chemin_avant` est la version de Claude de l'exercice, et `exercice` = `{instantane, le, ecarts [{cle, depart, claude, vous}], listes {masques, taches, yeux_rouges = {depart, vous}}, restent, rien_change}` (voir Je le fais) ; avec `entier` (1.3, `read_composition`), l'image entière sans son cadre, `image_entiere` = vrai, `dimensions` {`largeur`, `hauteur`}, `cadre_actuel` (absent sans recadrage), refusé avec `comparer` ou `point_af` (voir Composition lue) |
| `appliquer` | `photos?` ou `selection?`, `reglages`, `booleens?`, `looks_traitement?`, `profil?`, `profil_marque?`, `profil_variantes?`, `profil_look?`, `recadrage?`, `recalages?`, `courbes?`, `couleurs_ponctuelles?`, `balance?`, `auto_ton?`, `preset?`, `plages`, `libelles`, `relatif`, `etape`, `raison?`, `confirme` | par photo : `changements` (`cle`, `avant`, `apres`) et `remarques` ; `a_recadrer` et `etape_ecrite` quand un cadre demandé reste à placer (voir Recadrage) |
| `recadrer` | `photos`, `recadrage`, `recalages`, `completer?`, `etape`, `raison?`, `confirme` | comme `appliquer` (changements du cadre seulement) |
| `masquer` | `photos?` ou `selection?`, `masques` (chacun avec ses `composants?` combinés et ses `couleurs_ponctuelles?` ; types `ia`, `lineaire`, `radial`, `luminance`, `couleur` avec ses `prelevements` et son `etendue`, `profondeur`, `pinceau`, `objet` avec ses `traits` ou son `rectangle`), `recalages?`, `etape`, `raison?`, `confirme` | comme `appliquer` |
| `ameliorer` | `photo?`, `ameliorations` (`nom` : `denoise`, `rawDetails` ou `superRes`, `actif`, `intensite?`), `libelles`, `etape`, `raison?`, `confirme` | comme `appliquer`, plus `amelioration` (état après le calcul) |
| `retoucher` | `photo?`, `taches`, `yeux`, `recalages?`, `etape`, `raison?`, `confirme` | comme `appliquer` |
| `geometrie` | `photo?`, `photos?` ou `selection?`, `rendre?`, `taille?` | `photos` : par photo, `active` (correction géométrique), `transformation` (Upright, perspective ou distorsion manuelle), `empreinte` ; avec `rendre`, `chemin_corrige` et `chemin_origine` (voir Recalage de la géométrie) |
| `copier` | `source`, `photos?` ou `selection?`, `cles`, `inclure`, `etape`, `raison?`, `confirme` | comme `appliquer`, sans la photo source |
| `essayer` | `action` (`appliquer`, `masquer`, `retoucher`), `photo?`, `taille`, `comparer?`, `instantane?`, `exercice?`, `sans_rendu?`, `entier?`, et les paramètres de l'action | `chemin` (et `chemin_actuel`), `changements`, `remarques` ; avec `instantane`, l'état proposé est rangé en instantané « Claude · <nom> » avant le rendu (`instantane` dans la réponse) ; la photo est remise comme avant. 1.3 : `exercice` (exige `instantane`) range aussi le départ et la version de Claude dans la mémoire de la variante, l'entrée `exercice` au journal, et rend `exercice = {instantane}` et `raw` ; une proposition qui ne change rien est refusée ; `sans_rendu` : aucun rendu, ni `chemin` (voir Je le fais). `entier`, avec un recadrage proposé (action `appliquer`, ni `sans_rendu` ni `exercice`) : `cadre_propose` (le cadre que Lightroom a gardé, relu), `dimensions` et `chemin_entier` (troisième étape « Claude · essai : image entière ») ; sans image entière, la remarque « Image entière non rendue : … » (voir Composition lue) |
| `presets` | `filtre?`, `limite` | `total`, `presets` (dossier, nom, UUID) |
| `creerPreset` | `nom`, `photo?`, `cles`, `inclure` | `reglages` de la photo, dont le serveur fait un fichier XMP |
| `journal` | `photos?` ou `selection?`, `detaille?` | par photo : `entrees` (date, étape, raison, changements ou note ; `etape_id` depuis la 1.3) ; avec `detaille` (1.3, `photo_lesson`), la photo décrite en entier et `prise_de_vue_plus` `{compensation, flash, programme, mesure}`, chacune omise si Lightroom la refuse ou la rend vide (voir Leçon de la photo) |
| `diagnostic` | `modules?`, `methodes?`, `cles?`, `valeurs?` | fonctions offertes par le SDK de cette version de Lightroom : celles des modules, des méthodes cherchées par leur nom sur le catalogue, la photo active, le premier mot-clé, la première collection et le premier ensemble (sans les appeler), et le type des métadonnées brutes de la photo active ; avec `valeurs`, des valeurs lues sans rien écrire : jeu de libellés, filtre de la Bibliothèque et ses paramètres prédéfinis, original et aperçu dynamique de la photo active |
| `annuler` | `photos?` ou `selection?` | par photo : étape annulée et réglages remis ; depuis la 1.3, `etape_id` de l'étape défaite (null pour une étape d'avant la 1.3) |
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
| `notation` | `action` (`proposer`, `lire`, `remettre`) ; `proposer` : `propositions` (`photo`, `note` de 0 à 5 (0 à 4 jusqu'à la 1.3.1), `drapeau` `aucun` ou `rejetee`, `criteres` `{impact, qualites, plancher, finition?}`, `plafond?`, `raison`, `a_verifier`), `passe?`, `poser?` ; `lire` : `photos?` | `proposer` : `propositions` (`photo`, `fichier`, `note_avant`, `drapeau_avant`, `etat`, toujours `a_verifier` depuis la 1.1.1), `refusees` (`photo`, `raison`) ; avec `poser`, `posees` (`photo`, `etat`, `note`, `drapeau`, `erreur`, `remarques`) et `erreur_pose?` ; `lire` : `propositions`, `perdues?`. Sans `poser`, rien n'est écrit dans le catalogue (voir Notation). 1.3 : `remettre` (`photo`, `proposition` ou null ; la recette seulement, jamais un outil) remet la proposition lue avant une étape de la recette, ou la retire, sans rien écrire au catalogue |
| `lecon` (1.3) | `action` (`garder`, `lire`, `retirer`) ; `garder` : `photo?`, `lecon` = `{points, indices?}` (trois points, un par axe : `lumiere`, `couleur`, `composition`), `essai_recette?` (1.3.1, la recette seulement) ; `lire` : `photos?` ; `retirer` : `photo` ou `photos` | `garder` : `{photo, original, fichier, rangee, remplacee, mois, prise_le, sans_date, remarque?}`, ou pour une photo de « Développeur › Essais » sans `essai_recette` (1.3.1) `{photo, fichier, rangee = false, remplacee = false, motif = essai, remarque}`, jamais une erreur ; avec `essai_recette`, sous l'entrée de la photo d'essai (`original` = elle) ; `lire` : `{lecons, perdues?}` (une photo disparue ou d'un autre uuid perd sa leçon) ; `retirer` : `{retirees}`. Rien dans le catalogue, pas d'arrêt par la pause, jamais rejouée (voir Leçon de la photo) |
| `carnet` (1.3) | `action` (`constater`, `lire`, `retirer`) ; `constater` : `photo`, `vue` = `{cherches, defauts [{code, mesure?, texte?}]}` ou `angle` = `{inclinaison, code, source?}`, `vocabulaire`, `essai_recette?` ; `lire` : `resume?` ; `retirer` : `photos` | `constater` : `{note = true, constat, photo, original, fichier, mois, prise_le, sans_date, remplacee, remarque?}` ou `{note = false, motif (preference, essai, etapes, geometrie), raison, photo}` ; `lire` : `{catalogue, nombre, photos, resume?}` (leçons comprises) ; `retirer` : `{retirees, absentes?}` (un original ou une copie). Rien dans le catalogue, pas d'arrêt par la pause, jamais rejouée (voir Carnet de progrès) |
| `etapes` (1.3) | `photo?` | `{photo, etapes [{id, nom, en_memoire, avant, apres, etat, raison}]}` : les étapes de la mémoire, puis celles qui ne restent que sur le disque ; lecture seule, rejouée (voir Pourquoi ? : l'avant/après des étapes) |

Étapes (1.3) : chaque résultat d'une commande qui écrit une étape de Claude (`appliquer`,
`recadrer` — le même id que l'étape qu'il complète —, `masquer`, `retoucher`, `copier`,
`masques`, `ameliorer`, `supprimer`, `metadonnees`, `collections`) porte `etape_id`, null sans
étape ; `variantes` `choisir` le rend à plat. Deux paramètres de plus pour toute commande qui écrit
une étape : `avant_apres` (la recette seulement, jamais un outil : force l'avant/après, même hors
de la photo active) et `sans_avant_apres` (`match_series` : jamais d'avant/après). Les lectures
que le serveur rejoue une fois après une coupure (`LightroomBridge.lectures`) gagnent `etapes` ;
`lecon` et `carnet` n'y sont pas : ils écrivent `carnet.json`.

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

## Liaison fermée (1.2)

Jusqu'à la 1.1.1, tout programme du Mac, ou une page web (un POST vers 127.0.0.1:54770), pouvait
envoyer une commande au module, qui la traitait comme celle du connecteur ; une ligne qui portait
`depuisLightroom` sautait même la pause et l'accord dans Lightroom (lu dans `Ecriture.lua`). Depuis
la 1.2, chaque ligne porte un jeton privé, que seul le compte de l'utilisateur peut lire.

**Le jeton naît dans le module**, le côté qui écoute. À chaque démarrage de la liaison, avant
d'ouvrir les prises (`Liaison.demarrer`, `Liaison.preparerJeton`), le module lit 32 octets de
`/dev/urandom` (`Liaison.tirerJeton`) et en fait 64 chiffres hexadécimaux en minuscules. Il les
garde en mémoire (`Liaison.jeton`) et les écrit d'un coup (`Liaison.ecrireJeton`) : un fichier
provisoire `liaison.jeton.nouveau` créé vide sous `umask 077` (`LrTasks.execute` de
`umask 077 && /bin/rm -f … && /usr/bin/touch …`), le jeton écrit dedans par `io.open` (jamais sur
une ligne de commande), puis rangé par `/bin/mv -f` à sa place,
`~/Library/Application Support/Developpeur/liaison.jeton`, et relu. Le jeton n'est jamais
journalisé, ni dans une réponse, ni dans l'état ; le diagnostic du Gestionnaire de modules externes
dit seulement « Jeton : présent (chemin) ; commandes refusées : N », et `etat` dit
`liaison_fermee = true`. Si le jeton ne peut pas être écrit (aléa illisible ou trop court, fichier
impossible à créer ou à ranger, jeton relu différent), aucune prise ne s'ouvre : la liaison reste
active mais en erreur (`Liaison.erreur` commence par « jeton de la liaison : »), le voyant Lightroom
de la fenêtre Claude passe au rouge avec sa propre aide (voir Fenêtre Claude › Voyants et liaison),
et un clic sur ce voyant la relance (le menu Démarrer seul n'y fait rien : Arrêter, puis Démarrer).
Pendant que la liaison tourne, le fichier est vérifié tous les 10 tours de sa boucle (0,5 s
chacun : 5 s, `Liaison.VERIFIER_JETON_TOUTES`) : effacé, ou remplacé par un démarrage plus ancien,
il est réécrit (« Fichier du jeton réécrit » au journal ; un échec n'est noté qu'au premier tour qui
échoue). Le jeton change à chaque démarrage et s'oublie à l'arrêt (par sa génération) ;
`uninstall.sh` retire `liaison.jeton` et `liaison.jeton.nouveau` avec les fichiers de travail, et
dit de le relancer une fois Lightroom quitté, puisque la liaison réécrit le fichier dans les 5 s.

**Vérification** (`Liaison.recevoir`) : juste après la lecture du JSON, avant `dernierEchange` et
`Commandes.executer`, donc avant la pause, « Proposer d'abord » et l'accord dans Lightroom, `ping`
compris. La comparaison (`Liaison.memeJeton`) parcourt toute la longueur. Une ligne refusée reçoit
`{"id", "error", "code": "jeton"}` avec l'un des textes de `Liaison.REFUS_JETON` : `sans` (« cette
commande ne porte pas le jeton de la liaison » : un connecteur d'avant la 1.2 ; quitter puis
rouvrir Claude Desktop, ou ouvrir une nouvelle session de Claude Code), `faux` (« le jeton de cette
commande n'est pas celui de la liaison » : réessayer, sinon relancer la liaison) ou `aucun` (le
module n'a pas de jeton). Elle n'emporte pas l'événement de la photo active, destiné au vrai serveur
(`Liaison.repondre(objet, true)`). Les refus sont comptés (`Liaison.refus`, lignes illisibles
comprises) et notés au journal au plus une fois par 10 s et par genre (`DELAI_REFUS` : « Commande
refusée sans jeton (connecteur d'avant la 1.2, ou autre programme) », « Commande refusée : mauvais
jeton », « Message illisible ignoré ») : une inondation de lignes ne remplit pas `module.log`.
`depuisLightroom` est retiré des paramètres reçus du réseau : seuls les menus, la fenêtre de suivi
et la carte Note le posent, par appel direct.

**Le serveur** (`JetonLiaison.swift`, `LightroomBridge`) ne crée jamais ce fichier et n'en dit
jamais la valeur. `JetonLiaison.lire` n'accepte qu'un fichier ordinaire (ni lien, ni dossier, ni
tube nommé : genre et taille vérifiés avant la lecture) de 1 Ko au plus, qui contient exactement
64 chiffres hexadécimaux en minuscules. `LightroomBridge` relit le fichier à chaque connexion et met
`jeton` dans chaque ligne ; sans fichier lisible, aucune clé. Le `ping` refusé fait relire le
fichier une seule fois (la liaison a pu redémarrer entre la lecture et le ping, « jeton de la
liaison renouvelé : relu » au journal détaillé) ; un fichier absent ou mal formé donne
`LightroomBridge.jetonIntrouvableMessage` (relancer la liaison : Arrêter, puis Démarrer) ; une
commande refusée après un ping accepté n'est pas reprise (rien n'a été fait). Le serveur de Claude
Desktop, celui de Claude Code (fenêtre Claude comprise : Claude Code lance son propre
`mcp-developpeur` par `connecteur.json`), `--call`, `--module`, `--dump`, `--recalage`,
`--eclairage`, `--recette` et `--status` passent tous par `LightroomBridge.fromEnvironment`, qui
pointe le vrai fichier : ils ont le même jeton, sans rien changer à `connecteur.json`, à
`relais.sh` ni aux inscriptions. `mcp-developpeur --status` dit l'état du fichier
(`JetonLiaison.etat` : absent, illisible ou mal formé, « présent, lisible par vous seul », ou lisible
par d'autres comptes avec ses droits), jamais la valeur.

| Serveur | Module | Ce qui se passe |
| --- | --- | --- |
| 1.2 | 1.1.1 ou plus ancien | pas de fichier `liaison.jeton` : aucune clé `jeton`, la ligne passe comme avant |
| 1.1.1 ou plus ancien | 1.2 | ligne sans jeton : refusée (`sans`), avec le message qui dit de relancer Claude Desktop ou d'ouvrir une nouvelle session de Claude Code |
| 1.2 | 1.2 | jeton relu à chaque connexion ; après un redémarrage de la liaison, relu une fois de plus |

**Tests.** `LightroomBridge.fichierJeton` vaut nil par défaut : seul `fromEnvironment` pointe le vrai
fichier, et aucun test n'envoie par lui ; les tests passent un fichier temporaire (`FakePlugin` a
son jeton attendu). La simulation de la liaison (`Tests/Lua/Liaison/Simulation.lua`) imite
`/dev/urandom` (illisible ou trop court avec `S.aleaIllisible`) et seulement les deux commandes du
système du jeton (`LrTasks.execute`, sur `S.fichiers` et `S.droits`, droits 600 posés par la
création ; toute autre commande lève une erreur ; `S.codeCommandes` les fait échouer) : changer la
forme de ces commandes oblige à changer la simulation. Les essais sont dans la section « Liaison
fermée (1.2) » de `Tests/Lua/Liaison/tests.lua`.

**Limites.** Un programme lancé par l'utilisateur lui-même peut lire le fichier, donc le jeton : la
liaison fermée arrête une page web et les autres comptes du Mac, pas ce que l'utilisateur lance. Le
port des réponses (54771) ne lit rien et n'est pas contrôlé. Les démarrages successifs se servent du
même fichier provisoire : arrêter puis redémarrer la liaison pendant les quelques millisecondes où
l'ancien démarrage prépare encore son jeton peut faire échouer le `mv` du second (« fichier du jeton
impossible à ranger », voyant rouge, un clic relance), ou laisser l'ancien jeton dans le fichier
jusqu'à la vérification suivante (5 s ; le serveur relit le fichier une fois).

**Constaté dans Lightroom Classic 15.6, le 20 octobre 2026** (module de la 1.2 chargé dans
Lightroom) : au démarrage, `module.log` dit « Liaison démarrée (ports 54770 et 54771, jeton privé) »
(donc `/dev/urandom` lu, les deux commandes du système passées et le jeton relu) ;
`stat -f '%Lp %z'` du fichier donne « 600 65 » (droits 600, 64 chiffres et un saut de ligne) ; une
ligne sans jeton est refusée, avec une seule ligne au journal (« Commande refusée sans jeton
(connecteur d'avant la 1.2, ou autre programme) ») ; le fichier effacé est revenu à la
vérification suivante, dans les 5 s (« Fichier du jeton réécrit » ; le journal ne date pas
l'effacement). Le 21 octobre 2026, l'étape « liaison fermée (jeton privé) » de la
recette : une commande `etat` sans jeton, puis une avec un autre jeton, refusées, une ligne au
journal chacune (« Commande refusée : mauvais jeton » pour la seconde) ; le jeton de la liaison
passe. Ce qui reste à voir est dans À constater dans Lightroom (1.2).

## Consignes et invites

`ServerInfo.instructions` donne à Claude la méthode de travail ; les dix invites de
`Prompts.swift` (`retouche_pro`, `a_ma_facon`, `harmoniser_serie`, `tri_seance`, `noter`, `portrait`,
`paysage`, `noir_et_blanc`, `nuit_iso_eleve`, `partage`) l'appliquent à un cas, `retouche_pro` et
`harmoniser_serie` pas à pas, `noter` passe par passe selon le standard de notation (voir
Notation). Depuis le correctif 1.3.2, les consignes disent « noter : propose_ratings (0 à 5 ★,
standard developpeur://notation ; apply = true s'il demande de noter ; libellé de couleur : sur sa
demande) », et « trier : cull_photos (rejets : set_metadata après accord ; … » (raccourci pour
garder la longueur, 3 787 caractères) ; de la 1.1.1 à la 1.3.1 : « …, 5 ★ : set_metadata, sur sa
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
tenir, elles faisaient 3 793 caractères ; en 1.2, 3 768 (ci-dessous). Le détail propre à un outil
va dans sa description, qui n'est pas coupée (pour une description longue, pas constaté : voir À
constater dans Lightroom (1.2)).

**1.2.** Les consignes du connecteur perdent « Avant des centaines de photos : proposer une
sauvegarde du catalogue (get_status, request_backup) », que la description de `get_status` porte
déjà (`testInstructionsFollowAdobeHelp` lit les consignes et les définitions ensemble), et
« appuyer le diagnostic sur ces chiffres autant que sur l'œil » devient « diagnostic sur ces
chiffres autant qu'à l'œil ». Elles gagnent : « vignetage ou radial inversé, jamais les deux »
(deuxième passe), « « regression » au bilan » parmi les défauts qui justifient une passe
corrective, et « RAW Fujifilm : d'abord la simulation du boîtier, intention_boitier » (profil). Elles
font 3 768 caractères (UTF-16), et toutes les phrases déjà testées y restent. Le reste des sept
chantiers de la 1.2 passe ailleurs :

- les descriptions d'outils, que Claude Desktop et la fenêtre Claude lisent : celle d'`add_mask`
  finit par `Prompts.Tireur.resume` (méthode du tireur, 1 559 caractères au total, garde de 2 048
  dans les tests), sa propriété `effect` par `Peau.dosage`, et chaque masque a
  `smoothing_requested` ; celle de `view_photo` dit l'éclairage, le bilan et `intention_boitier`
  (1 783 caractères, garde de 1 850) ; celle de `preview_settings` le bilan d'une proposition (538,
  garde de 600) ; celle d'`analyze_photos` « dominante (et éclairage mixte) » (garde de 520) ;
  celle de `get_status` l'écran ; la propriété `compare` d'`add_mask`, « avec leur bilan chiffré » ;
- le texte que le serveur rend seulement quand il sert : la `lecture` d'`intention_boitier`, le
  `conseil` d'un éclairage mixte, le `bilan` et sa `regression`, la remarque de l'écran (une fois
  par processus, voir Écran), le refus d'une peau trop lissée et ses remarques ;
- les invites (`Prompts.swift`) : `retouche_pro` (étape 2 : `intention_boitier`, puis l'éclairage
  mixte, balance sur la lumière des visages ou du sujet, `balance_proposee`, l'autre lumière par
  un masque à l'étape 7 ou gardée chaude si c'est une lampe ; 4 : RAW Fujifilm, d'abord la
  simulation choisie au boîtier, `intention_boitier.profil` ; 5 : lire le bilan, une
  « regression » se corrige avant la suite ; 6 : vignetage, ou les bords par un radial inversé à
  l'étape 7, jamais les deux ; 7 : peau dosée comme le dit `add_mask`, puis éclaircir et assombrir
  comme un tireur, suivi de `view_photo` avec `compare = previous_step` ; 8 : une « regression »
  au bilan justifie une passe corrective ; 9 : `compare = before_claude` et le résumé, chiffres du
  bilan à l'appui), `portrait` (1 : regarder chaque visage, enfant, homme, femme ou personne âgée,
  la dose de la peau en dépend, dans le doute la plus faible ; 2 : la simulation du boîtier si elle
  flatte la peau, et sous un éclairage mixte la balance sur la lumière du visage ; 4 : « Retouches
  locales (add_mask). » puis `Peau.dosage` ; 6 : `Tireur.methode`), `paysage` (2 : la simulation du
  boîtier ; 5 : `Tireur.methode`, à la place du vignetage léger d'avant), `noir_et_blanc` (2 : ACROS
  et son filtre pris au boîtier ; 5 : `Tireur.methode` ; 6 : le grain), `nuit_iso_eleve` (1 :
  `mesures › eclairage`, et `intention_boitier` : une compensation négative ou une scène de nuit
  dit une nuit voulue sombre ; 3 : ne pas remonter l'exposition au-delà de ce que dit
  `intention_boitier`), et `finRetouche` (« regression » au bilan, résumé chiffré) ;
- `Consignes.lua`, pour la fenêtre (voir Fenêtre Claude › Claude Code).

La méthode du tireur n'existe qu'à un endroit, `Prompts.Tireur` (voir Éclaircir et assombrir) ; le
dosage de la peau, qu'à `Peau.dosage` (voir Peau) : les invites et les descriptions les reprennent,
jamais une copie des chiffres.

**1.3.** Les consignes du connecteur ne gagnent que « Recadrer (read_composition) seulement sur
demande ou si la composition y gagne nettement, et le dire. » (« (read_composition) » ajouté) :
3 787 caractères (UTF-16) pour 3 796. Une réserve de 19 caractères était gardée pour un repli de la
leçon (« …et pourquoi, puis photo_lesson. ») si Claude Desktop n'appelait pas `photo_lesson` : non
fait, faute de mesure qui le demande ; une ligne « journal et carnet » a été refusée (le titre
d'`export_journal` et sa propriété `notebook` suffisent). Le reste de la 1.3 passe par :

- les descriptions d'outils : `photo_lesson` (1 200 caractères au plus, garde de
  `PriseDeVueTests` et `LeconTests`), `read_composition` (1 000 au plus), `export_journal` avec sa
  propriété `notebook` (450 au plus, `CarnetTests`), `preview_settings` (« (trois avec crop) »,
  sous sa garde de 600 ; propriétés `my_turn` et `overlay` hors garde), la propriété `compare` de
  `view_photo` (`claude_version`, hors garde de 1 850), et `reason`, répétée dans chaque outil qui
  écrit : `ToolHandler.descriptionRaison`, 160 caractères au plus (« Pourquoi, en une phrase
  simple : le défaut vu, puis ce que l'étape y fait. Gardé au journal (export_journal) ; la
  fenêtre Claude le montre avec l'étape cliquée. ») ;
- les invites : `Prompts.Lecon.phrase` (« Enfin photo_lesson : … »), seule copie, finit l'étape 9
  de `retouche_pro` et `finRetouche` (`portrait`, `paysage`, `noir_et_blanc`, `nuit_iso_eleve`) ;
  `read_composition` entre à l'étape 4 de `retouche_pro` (le cadre montré par `preview_settings`,
  l'accord attendu), à la fin de l'étape 3 de `portrait` (les yeux sur le tiers haut, de l'espace
  devant le regard) et dans une étape 5 « Composition » de `paysage` (le tireur passe à
  l'étape 6). Rien dans `harmoniser_serie`, `tri_seance`, `noter` ni `partage` ;
- le vocabulaire des défauts de la prise de vue, `PriseDeVue.defauts`, seule liste (voir Leçon de
  la photo), et le texte que le serveur rend quand il sert (faits de la leçon, `a_faire` et écarts
  de « Je le fais », lecture de la composition, `constats_prise_de_vue`) ;
- `Consignes.lua`, pour la fenêtre (voir Fenêtre Claude › Claude Code).

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
retouche sur une conversation vide (voir Disposition et Proposition préparée à l'ouverture). Ces
changements font partie de la 1.2, qui ajoute à la fenêtre un quatrième voyant, Écran, l'aide
d'une liaison qui n'a pas pu préparer son jeton privé, et des consignes pour la peau, l'écran, le
bilan et la méthode du tireur (voir Voyants et liaison, et Claude Code). Captures :
`docs/capture.png` (la fenêtre Claude, en Conversation claire), `docs/publication.png`,
`docs/consommation.png` et `docs/suivi.png` (la fenêtre de suivi de la liaison) ;
`docs/atelier.png` et `docs/panneau.png`, les deux autres dispositions, sont retirées avec elles.

En 1.3, la Conversation claire prend l'allure de la maquette « B · Conversation claire » (la
fenêtre B, lots B0 à B5), agrandie à 1 948 × 1 200 à la demande de Dany (voir Fenêtre B) : volet
des conversations à gauche (le Carnet de progrès en tête de sa liste), au centre l'en-tête avec le
Mode en boutons radio, le fil B, sa barre et la saisie, à droite quatre onglets (Aperçu,
Proposition, Note, Leçon ; cinq depuis l'onglet Focus du 22 octobre 2026, entre Aperçu et
Proposition : voir Onglet Focus), l'aperçu commun et la carte de l'onglet ; apparence claire ou
sombre.
Les sections Disposition, Voyants et liaison, Carte Note et Bas de la fenêtre décrivent la 1.2 :
ce qui y a changé est dit en tête de chacune. Les cinq chantiers de la 1.3 ont chacun leur partie
« dans la fenêtre » dans leur section (Pourquoi ?, Leçon de la photo, Je le fais, Composition lue,
Carnet de progrès). `docs/capture.png` montre la fenêtre B de la 1.3 (une retouche, ses étapes
avec « Pourquoi ? » et la leçon de la photo), et `docs/carnet.png` la page Carnet de progrès.

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
depuis le correctif 1.3.2 (demandé par Dany le 22 octobre 2026), « De 0 à 5 ★ ; jamais de libellé
de couleur (ses coups de cœur) sans sa demande. » (de la 1.1.1 à la 1.3.1 : jamais 5 ★ de
lui-même, `set_metadata` si Dany en demande ; en 1.1 : jamais `set_metadata` pour une note sans
demande, jamais 5 ★). Les consignes font 7 489 caractères (plafond 7 500). Après la 1.1.1, une puce de plus, sous Notes : « Mise au
point montrée ou jugée : view_photo avec af_point = true, sur l'aperçu entier comme sur un zoom
(region) : le carré y est dessiné, s'il tombe dans la zone (point_af : dans_la_zone) » (voir Tri
d'une séance › Point de mise au point). Les consignes du connecteur (`ServerInfo`, pour Claude
Desktop) ne demandent pas de noter d'abord.

En 1.2, `Consignes.texte` gagne une section « ## Écran », après « ## Contexte » : Claude mesure la
photo par ses chiffres (`view_photo`), Dany la juge sur son écran ; si le connecteur dit cet écran
non étalonné (remarque d'un aperçu, ou `get_status` : `ecran`), le dire en une phrase, une fois par
conversation, quand Claude demande son avis sur la peau ou les couleurs. Les garde-fous gagnent la
puce « Peau » : dosée comme le dit `add_mask` (effect « Peau du visage lisse » par défaut), plus
lisse seulement si Dany le demande en mots ou si son guide de style le dit, alors
`smoothing_requested = true`, et dire la dose posée. La phrase « Peau adoucie » du Style est refaite
sans chiffres : la dose « Adoucir la peau (Lite) » d'`add_mask`, sur la peau seulement, jamais sur
toute la photo ; la moitié de la dose pour un homme ou une personne âgée, rien pour un enfant (les
chiffres restent dans `Peau.swift` ; un essai vérifie qu'il n'y a ni −35, ni −15, ni « amount 50 »
dans le Style). « ## Fin d'une tâche » demande le résumé « chiffres du bilan de view_photo à
l'appui », et qu'une « regression » restée au bilan se dise. Les boutons Portrait, Paysage et Noir
et blanc (`Consignes.invites`) demandent d'éclaircir et assombrir comme un tireur (« doses
d'add_mask ») et l'avant/après de cette étape, sans chiffres : les doses arrivent à Claude Code par
la description d'`add_mask` (`Prompts.Tireur.resume`), car la fenêtre ne lit pas les invites
(`--disable-slash-commands`). La méthode elle-même n'entre pas dans `Consignes.texte`, dont
l'en-tête laisse la méthode de retouche au connecteur ; l'intention du boîtier et l'éclairage mixte
non plus : la fenêtre reçoit les mêmes descriptions et les mêmes résultats d'outils que Claude
Desktop.

En 1.3, `Consignes.texte` gagne quatre sections et une puce : « ## Composition » (398 caractères
pour une part de 400, entre Garde-fous et Je le fais : la règle dans `reason`, la façon de la tenir
à la prise de vue dans la réponse), « ## Je le fais » (594 pour 600 : il s'appuie sur
`corrections_utilisateur.exercice` du serveur sans la redire), « ## Raison de chaque étape » (395
pour 400, entre Style et Fin d'une tâche), « ## Leçon de la photo » (597 pour 600, après Fin
d'une tâche : résumé court, proposition de cadre s'il y en a une, puis `photo_lesson` en dernier ;
un réglage du boîtier cité seulement s'il est lu ; une leçon par photo et par conversation, même
après « J'ai fini » ; pas de leçon après une proposition seulement montrée, une notation, un
classement ou une série, ni avec la ligne « [Sans leçon] » ; la fenêtre la montre dans l'onglet
Leçon), et la puce Carnet des garde-fous (250 au plus : les défauts se notent seuls ; si Dany
demande ses progrès, `export_journal` avec `notebook = true`, puis trois puces). « ## Fin d'une
tâche » dit « fais un résumé » et finit par « Puis la leçon (voir Leçon de la photo). » ; la puce
Proposer d'abord dit « Accepter, Refuser, Ajuster et Je le fais ». `Consignes.texte` fait
7 466 caractères pour un plafond de 7 500, vérifié par un essai d'`essais-moteur.lua` (5 064 en
1.2) : ce qui dépasse va aux descriptions d'outils. Hors du plafond, les messages des boutons
(400 au plus chacun) : `Consignes.jeLeFais(avecProposition)`, `Consignes.jaiFini(photo)`,
`Consignes.carnet` (la ligne d'action du carnet, « Ne retouche rien. »),
`Consignes.ajustementsCadre` (Plus serré, Plus large, Horizon au tiers haut, Format 4:5,
Seulement redresser) et `Consignes.sansLecon` (« [Sans leçon] », joint par `Moteur.envoyer`
quand la case Leçon est décochée, après la ligne de style, sans relancer Claude Code). Les
invites passent de 6 à 7, Composition avant Sports, sans chiffre.

Depuis la 1.1, `consignes.md` est écrit dans le dossier de chaque session (`Session:lancer` ;
huitième argument de `relais.sh` depuis la 1.1.1, septième en 1.1), plus à la racine : Claude
Code le lit un peu après son lancement en
arrière-plan, et un fichier commun pourrait être réécrit entre-temps. Son texte est
`Consignes.texte` (en 1.1, `Consignes.pour(c)` y ajoutait `Consignes.texteNotation` pour une
conversation de séance ; retirés en 1.1.1). Les boutons d'invites de la fenêtre
(`Consignes.invites` : Retouche pro, Portrait, Paysage, Noir et blanc, ISO élevé, Composition
depuis la 1.3, Sports)
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
dessus sa méthode (« peau adoucie » : depuis la 1.2, la dose « Adoucir la peau (Lite) » d'`add_mask`
sur la peau seulement, jamais toute la photo ; avant, « un masque de la peau »). Le nom du style
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
  séparateur) et, depuis le constat du 21 octobre 2026 (D10, voir Constaté dans Lightroom Classic
  15.6 (21 octobre 2026, fenêtre B)), un `f:view` : posé sur un autre conteneur (`row`, `column`,
  `group_box`, `tab_view`, `scrolled_view`), il reste sans effet et tout le contenu reste montré
  (constaté le 20 octobre 2026, voir plus bas). La simulation de la fenêtre refuse ces cinq-là
  (« visible sur un conteneur : sans effet dans Lightroom (constaté) »). Toute condition de
  visibilité des pièces passe par `Fenetre.condition`, `egal`, `non` ou `si`, qui gardent leurs conditions (clé et test) pour que
  `Fenetre.et` les combine en une liaison à plusieurs clés (`LrView.bind{keys, operation}`,
  `LrBinding.kUnsupportedDirection` pour le sens de la vue vers la table).
- Pas de défilement par programme d'un `scrolled_view` ou d'une `simple_list`.

D'où le fil en grille de lignes fixes (`Fil.lua`) : chaque ligne superpose une variante par genre
(police, couleur) et une icône par état ; seul le texte et le genre changent. Les lignes sont
coupées à la largeur de la colonne d'après la chasse des caractères mesurée par AppKit dans les
polices données à Lightroom (jusqu'à la 1.2, Helvetica Neue 13, Helvetica Neue Bold 13, Menlo 11 ;
depuis la fenêtre B, la police du système, voir Fenêtre B : `scripts/metriques.swift` →
`Metriques.lua`), moins une marge de 10 points, avec troncature en fin de ligne au cas où.
Depuis la 1.1.1, une ponctuation haute (; : ! ? ») reste avec le mot d'avant, et « avec celui
d'après : `Fil.couper` les lie par une espace insécable, comptée comme une espace
et rendue ordinaire dans la ligne (une ligne de la carte Note commençait par « ; mais », vu sur la
capture). La grille montre la fin du fil ; ▲ ▼ Fin déplacent la fenêtre de lecture, qui
reste en place quand des lignes arrivent pendant qu'on lit plus haut. Les images ne peuvent pas
s'insérer dans la grille : elles s'affichent dans le cadre de l'aperçu (`f:picture`, réduction
sur fond 2B2B2B faite par `sips`, carrée, le cadre de la vue ne changeant pas de taille ;
`Images.vignette(dossier, nom, cote, hauteur)`, où `hauteur` servait au cadre 3:2 de l'Atelier,
retiré après la 1.1.1).

De même, depuis la 1.1.1, le texte de la carte Note (`notationTexte` jusqu'à la 1.2 ; en 1.3, la
grille des critères, voir Carte Note B) et celui de la Proposition
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

Les onglets de la 1.2, Note (par défaut) et Proposition (`D.onglets`), sont une rangée de
`radio_button` (clé `onglet`, chacun avec son `checked_value`) au-dessus de variantes superposées
de même largeur (`place = 'overlapping'`), et non un `tab_view` (rendu correct, constaté le
21 octobre 2026, C3, mais non retenu). En 1.3, la rangée devient quatre segments en images sous
calques (Aperçu, Proposition, Note, Leçon : voir Fenêtre B ; cinq avec Focus, 22 octobre 2026) ; les variantes superposées et
`Vues.masquable` restent (constaté le 21 octobre 2026, D11 : seule la variante montrée répond).
Le Panneau avait les siens, Retoucher et Noter : retirés avec lui après la 1.1.1. Les colonnes des
variantes ne portent pas `visible` : leur contenu se crée par une fabrique masquable
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
  ainsi le focus et se vide). Constaté le 21 octobre 2026 (D1 à D3) : Retour dans le champ (sans
  bouton par défaut) donne l'observateur, puis l'envoi automatique 0,3 s après ; un clic (calque,
  radio, segment, bouton) valide d'abord le champ, puis agit, et annule l'envoi ; avec un bouton
  par défaut, Retour dans un champ `immediate = true` (« Rechercher ») déclencherait aussi son
  action. D'où, en 1.3, aucun bouton par défaut dans la fenêtre : Envoyer est un bouton bleu en
  image sous calque (voir Fenêtre B), et Retour passe toujours par l'observateur.
- Toute table passée à Lightroom est neuve (une table relue par `Json.decode` porte une métatable,
  sur laquelle Lightroom bloque : constaté par la liaison, voir Profil).
- `LrTasks.execute` ne bloque que la tâche : base64, sips, `osascript`, `mcp-developpeur --version`
  et `claude auth status` passent par là, et après la 1.1.1 `mcp-developpeur --marquer-af` (voir
  Disposition), en 1.2 `mcp-developpeur --ecran` (sous `perl alarm 5`, dans un `LrTasks.pcall`,
  voir Voyants et liaison), jamais par un calcul en Lua sur la tâche de l'interface.

### Voyants et liaison

En 1.3 (fenêtre B), trois voyants en pastilles PNG (`Vues.voyant`, `F.PASTILLES`) : Claude Code
et Lightroom dans l'en-tête, sous le titre (`Vues.voyantClaude`, `Vues.voyantLightroom`), Écran
en bas du volet (`Vues.voyantEcran`) ; le voyant Mode est retiré (`texteMode`, `etatMode`) : le
mode se choisit par les trois boutons radio de l'en-tête (voir Fenêtre B). Leur lecture est celle
de la 1.2, décrite ici.

Sous le titre de la conversation, quatre voyants en 1.2 (trois avant), en rangée
(`Vues.voyants(f, F, largeur)`, `D.voyant` = 150 points chacun). Claude Code : `claude auth
status`, lu à l'ouverture de la fenêtre (forfait, autre connexion, non connecté, introuvable).
Lightroom : la liaison, qui est dans ce même module ; la fenêtre la lit directement
(`Lightroom.liaison` : `Liaison.actif`, `Liaison.erreur`), toutes les 2 s, sans commande du système
ni connexion. Arrêtée ou en erreur (ports tenus par un autre Lightroom ouvert, par exemple), le
voyant passe au rouge et l'aide du bandeau dit quoi faire ; un clic sur le voyant la démarre, ou la
relance après une erreur (`Lightroom.demarrerLiaison`). Depuis la 1.2, une erreur qui contient
« jeton » (le jeton privé n'a pas pu être préparé, voir Liaison fermée) a sa propre aide, avant
celle des ports : « La liaison avec Claude n'a pas pu préparer son jeton privé (<erreur>) : cliquez
le voyant Lightroom pour la relancer ; le détail est dans ~/Library/Logs/Developpeur/module.log. »
Le mode : un clic bascule « Proposer d'abord » et « Appliquer directement »
(`Lightroom.basculerMode`, clé `mode` des préférences, celle que lit la liaison).

Écran (1.2) : l'écran principal du Mac et son profil de couleur (voir Écran). Le module ne le lit
pas lui-même : `Lightroom.etatEcran(connecteur)` lance, par `LrTasks.execute` dans un
`LrTasks.pcall`, `/usr/bin/perl -e 'alarm 5; exec @ARGV' <connecteur> --ecran`, sortie dans
`Chemins.temporaire()/ecran-<id>.json`, lue puis effacée ; `Lightroom.decrireEcran(json)`, pure,
en tire une table neuve de textes : `mesure` vrai, « Écran · étalonné », vert (`ok`) ; faux,
« Écran · non étalonné », orange (`attention`) ; absente, « Écran · étalonné ? », gris (`neutre`).
Sans réponse lisible, « Écran », gris, et le détail dit pourquoi : `Lightroom.ECRAN_INTROUVABLE`
(connecteur absent ou sans chemin : réinstaller, ou régler son chemin dans le Gestionnaire),
`ECRAN_ILLISIBLE` (pas de réponse dans les 5 s, ou un connecteur d'avant la 1.2, qui répond à
`--ecran` par son aide), `ECRAN_AUCUN` (`{"lu": false}` : aucun écran lu). L'écran se lit à
l'ouverture, dans la tâche de `Fenetre.verifier(true)` (`Fenetre.poserEcran`), et au clic sur son
voyant (`Fenetre.montrerEcran`, dans une tâche : il relit l'écran, puis montre la boîte « Claude ·
écran » avec le détail du connecteur), jamais toutes les 2 s par `Fenetre.periodique`. Avant
l'ouverture, `texteEcran` vaut « Écran » et `etatEcran` `neutre`. Une panne de la commande laisse
le voyant gris, et la suite de `Fenetre.verifier` passe. Le clic, comme tout bouton, annule l'envoi
automatique de la demande tapée.

### Disposition (1.1 ; une seule après la 1.1.1 ; fenêtre B en 1.3)

Cette section décrit la Conversation claire jusqu'à la 1.2 ; en 1.3, sa mise en page, ses
dimensions, ses pièces et son image « aucun aperçu » sont celles de la fenêtre B (voir Fenêtre B).
Restent valables : une seule disposition (`Dispositions.NOM`, `conversation`), l'aperçu de la
photo active et son carré de mise au point, et la génération de chaque ouverture.

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
(`LecteurBoitier`, 2 s), le passe dans l'image affichée et recadrée
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
`D.envoiACote`). L'image « aucun aperçu » du cadre (`Dispositions.imageVide`) était en 1.2
`vide-320.png`, seule dans le module, dessinée par `scripts/images-vides.swift` (retirée en 1.3 :
`images/vide-498x332.png` et `images/sombre/vide-498x332.png`, voir Fenêtre B) ;
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
`DeveloppeurClaude-conversation-grande-<Fenetre.FORME>`, `FORME` à 1 jusqu'à la 1.2, 2 pour la
fenêtre B de 1 280 × 800, 3 pour la fenêtre agrandie de la 1.3 (1 497 × 1 200), 4 pour la fenêtre
élargie (1 948 × 1 200)) porte le nom qu'avait celui
de la Conversation claire en 1.1.1 : le cadre déjà enregistré sert encore (en 1.1.1,
`Fenetre.cadre(disposition)` : `DeveloppeurClaude-<disposition>-grande-<FORME>` ; en 1.1,
`DeveloppeurClaude-<disposition>-<taille>-<FORME>`).

### Fenêtre B (1.3)

La Conversation claire de la 1.3 suit la maquette « B · Conversation claire » (1 280 × 800 ;
`Dispositions.lua`, `Vues.lua`, lots B0 à B5), agrandie à la demande de Dany le 21 octobre 2026 :
son écran fait 3 440 × 1 440, et il a voulu « la partie de gauche peut-être doublée, celle du
milieu 33 % plus large, celle de droite parfaite, la hauteur 33 % plus haute ». Un premier
agrandissement à 1 671 × 1 064 a été arrêté ; retenu, sur la suggestion de Claude choisie par
Dany : 1 497 × 1 200 (environ 1 940 points laissés à Lightroom, des lignes de fil d'environ 103
caractères), constatée à l'écran le 21 octobre 2026. Le même jour, Dany l'a élargie de 20 % à
gauche, 40 % au centre et 20 % à droite : 1 948 × 1 200 (environ 1 490 points laissés à
Lightroom, des lignes de fil d'environ 150 caractères), et a voulu les cartes Proposition, Aperçu
et Leçon comme la carte Note : jusqu'en bas du panneau, leurs boutons sous elles. Écart voulu avec
la maquette, qui reste la référence de l'allure.

**Dimensions** (`Dispositions.TAILLES`, puis `Dispositions.dimensions()`, qui en tire le reste) :

- la fenêtre de 1 948 × 1 200 et son cadre constaté (D7 : barre de titre de 33, 32 blancs et un
  filet ; marge de 1 à gauche, à droite et en bas, aucune en haut) : contenu de 1 946 × 1 166
  (constaté à 1 280 × 800 et à 1 497 × 1 200) ;
- trois colonnes et deux filets de 1 : volet 324 (marges de 10 : 304 utiles), centre 1 064 (marges
  de 20 : 1 024 utiles), droite 556 (le panneau de 528, à 14 du bord) ;
- au centre : en-tête de 68 et son filet, fil (le reste : 920), barre de 30, saisie de 147. Le fil :
  des lignes de 21 sous une marge de 20 et au-dessus d'au moins 16 ; leur nombre se calcule
  (`D.lignes`, 42 ; la grille fait 882). Chaque ligne : la colonne auteur de 60, un écart de 12,
  le texte de 952 (`D.texteFil`, `Fenetre.largeurTexte()`) ;
- la liste des conversations : des cases de 40, autant que sa place en tient (`D.cases`, 22 dans
  915) ;
- à droite : le panneau en image (528 × 1 146), son intérieur de 498, l'aperçu commun en 3:2 de
  498 × 332 (sa vignette en 2x, 996 × 664, `Images.vignette`), la rangée ◀ légende ▶ · ⤢ Agrandir,
  puis la place des cartes (`D.placeCartes`, 720) : carte Note de 583 (559 jusqu'à la 1.3.1, avec
  la rangée des passes et la ligne du plafond ; l'onglet Note la remplit),
  cartes Proposition, Aperçu (étape) et Leçon de 679, chacune suivie, comme la carte Note, de 12
  et de sa rangée de boutons au bas du panneau (▲ ▼ à gauche, les boutons à droite, bezel 26,
  titres en 13 : `carteEtRangee` de `Vues.lua`) ; leur intérieur de 472 (`D.carte`, textes en 12).
  Les lignes des cartes : `criteres` 33 (une grille de 34 lignes de 16 ; 30 jusqu'à la 1.3.1), `propLignes` 40,
  `etapeLignes` 40, `leconLignes` 42 : le plus grand nombre qui laisse au moins 12 points sous le
  contenu estimé (`essais-fenetre-b.lua` le vérifie, et échoue en disant quoi changer si la
  hauteur change) ;
- `Fenetre.FORME` 4 : le cadre enregistré `DeveloppeurClaude-conversation-grande-4` (3 pour
  1 497 × 1 200).

La fenêtre construite (simulation) compte 2 317 vues, dont 1 490 simples (1 368 et 857 à
1 280 × 800) ; Mes demandes (22 octobre 2026) en ajoute 86 : le menu et son espace, et par ligne du
fil une rangée et « ＋ Garder la demande » (2 289 vues, dont 1 473 simples, avant lui ; 2 375, dont
1 516, après, au compte de toutes les vues de l'arbre) : son temps d'ouverture est à mesurer. Elle ne tient pas sur un écran de portable
(1 440 × 900) : son contenu est de taille fixe, sans défilement.

**Volet** (`Vues.volet`) : « ＋ Nouvelle conversation » (bezel 26), la loupe devant
« Rechercher » (champ `immediate = true`), la liste en cases, puis Renommer… et Supprimer…, un
filet, Publication… et Consommation… (venus de la colonne droite), les deux lignes des versions
(`Vues.versions`) et le voyant Écran. La liste (`Vues.caseListe`, `Fenetre.casesListe`, pure) :
une case par conversation (titre en gras si elle est choisie, sous-titre « 19 h 46 · 1 photo » ou
« 12 oct. · 48 photos », `Fenetre.sousTitreListe`), des en-têtes de jour (Aujourd'hui, Hier,
« Plus tôt en <mois> », « <Mois> <année> », `Fenetre.periodeListe`, mois de `Carnet.MOIS`),
jamais en bout de page, « Plus récentes… » dans la première case d'une page qui en suit une
autre et « Plus anciennes… » toujours dans la dernière case ; la page se garde
(`Fenetre.pageListe`), remise à 1 par la recherche et par Nouvelle. La case du Carnet de progrès
vient en tête (`Fenetre.CARNET`, voir Carnet de progrès). Chaque case porte
un calque (`Fenetre.cliquerListe`, refusé pendant que Claude travaille : le bandeau le dit) et une
infobulle liée qui donne le titre entier. La `simple_list` de la 1.2 est retirée, avec
`selectionListe`, `listeConversations` et leur observateur.

**En-tête** (`Vues.entete`) : le titre de la conversation (gras 16, `D.titre` = 720 − 320 laissés
au Mode ; plus de ✎ : Renommer… suffit), puis le Mode (`Vues.mode`) : trois `radio_button` liés à
la clé `mode` par `Fenetre.lierRadio` (un clic, même sur le radio déjà coché, annule l'envoi
automatique de la demande que ce clic a validée) : Appliquer et Proposer d'abord (le mode de la
liaison), Je le fais (l'exercice, voir Je le fais). Grisés pendant que Claude travaille
(`enabled = libre`, décision de Dany : le voyant Mode de la 1.2 basculait à tout moment) ; Je le
fais suit `peutJeLeFais`. La valeur montrée est tirée de l'état (`Fenetre.modeMontre`) et posée sous
la garde `Fenetre.modeAuto` ; `Fenetre.changerMode` ne suit qu'un vrai clic (pendant un exercice,
Appliquer ou Proposer d'abord change le mode et le bandeau dit « L'exercice continue ; liaison :
… »). Constaté D12 : un radio inactif coché par sa valeur se dessine sans point à la première
ouverture ; `Fenetre.reposerMode` repose donc la valeur (par `aucun`) au 2e tour de la boucle
(`Fenetre.TOUR_REPOSER_MODE`). Dessous : les voyants Claude Code et Lightroom, et la photo active
(`infoPhoto`, texte riche : « Active : <EM>nom (copie)</EM> · Sélection : <EM>N</EM> »).

**Fil B** (`Vues.ligneFil`, `Fil.lua`) : chaque ligne est une `f:row` de 21 points ; la colonne
auteur en variantes selon `a..i` (« Vous » en gras 12 bleu, « Claude » en gras 12, l'heure `h..i`
en petit gris, posées par `Fil.lignes` sur des copies, jamais dans le cache ; « 19 h 42 » sur la
ligne qui suit l'auteur) ; puis le texte, ses variantes par genre (`Fenetre.STYLES`), les genres à
icône (`appel`, `apercu`, `proposition`, `note`) en retrait de 20 (`Fil.RETRAITS`). La ligne d'un
appel d'outil (genre `appel`, nouveau) est un texte riche : « <EM>apply_settings</EM>  description »
en 12 gris, le nom en Menlo 11 (`Fil.uneLigneOutil`) ; pour une étape, « étape « Claude · <but> » ·
N réglages » ; les autres variantes lisent le texte sans balise (`transform`, `Fenetre.sansBalises` :
une variante cachée ne voit jamais une balise qu'elle ne sait pas montrer). « Pourquoi ? » (carré
small de 80, bezel de 15 dans la case de 21, constaté D6) se montre par `q..i` au bout d'une ligne
d'étape (`Fil.PLACE_POURQUOI` laissé libre ; `Fil.SUFFIXE_ETAPE` de la 1.3 avant B4 est retiré),
dans une `f:row` poussée par `margin_left` : constaté D6, la rangée ne prend pas les clics du texte.
Le tour de Claude qui a noté ou donné une leçon finit par une ligne `actions` (`x..i`) : « ☆ Voir
la note » (`Fenetre.voirNote` → `montrerNote` : l'onglet Note, comme un vrai clic ;
`Fenetre.NOTE_AUTRE_PHOTO` au bandeau si la photo active n'est pas celle notée), « Leçon de la
photo » (`Fenetre.voirLecon` → `montrerLecon`), ou les deux ; celui qui a retouché et donné sa
« Demande à garder » y gagne « ＋ Garder la demande », au bout de la ligne, à droite (voir Mes
demandes). La barre (`Vues.defilement`) : ▲ ▼ en
icônes, Fin, la position dans le fil, et à droite l'activité de Claude (orange) ou le relevé du
forfait. Un clic sur une ligne se répartit par `Fenetre.sorteDeClic` (`Fenetre.clics`) : image,
ligne du carnet, leçon, étape, sinon détail de l'outil.

**Saisie** (`Vues.saisie`) : les sept invites en carrés (bezel 24, `Vues.invites` ; ni « ★ Noter »
ni séparateur), le champ de demande sur deux lignes (`immediate = false`), puis 📎 et 📋 (carrés à
icône seule, `image_name`), l'étiquette « Style » et son menu (décision de Dany après le lot B3 :
comme la maquette, à la place du « sans étiquette » du 20 octobre 2026), le menu Mes demandes (280,
`D.mesDemandes` ; voir Mes demandes), le bandeau, et Envoyer.
Pas de menu Modèle (décision de Dany : Modèle et Effort sont dans le Gestionnaire de modules
externes). Envoyer (`Vues.envoi`) est un bouton bleu en image (`Vues.boutonBleu`), Arrêter un carré
superposé, montré pendant le travail ; aucun bouton par défaut (repli décidé après D1). Le bandeau
(`Vues.bandeau`, à la place du menu Modèle de la maquette, `D.bandeau` 324 depuis Mes demandes, 612
avant) : deux lignes de petit
texte (`Fenetre.LIGNES_BANDEAU`), coupées d'après la chasse mesurée (`Fenetre.texteBandeau`, « … »
au bout de la seconde) ; l'infobulle donne le message entier, un clic l'aide entière. Les messages
de la fenêtre sont des constantes raccourcies pour y tenir (`CHOISIR_CONVERSATION`,
`EXERCICE_CONTINUE`, `PAS_D_IMAGE`, `NOTE_AUTRE_PHOTO`, `NOTE_EN_COURS`, `AUCUNE_PHOTO`, et trois
refus de `Moteur.lua` ; `PAS_CINQ` est retiré au correctif 1.3.2) ; l'essai « Bandeau »
d'`essais-fenetre-b.lua` les mesure.

**Colonne droite** (`droite` de `Dispositions.lua`) : le panneau en image, les segments Aperçu |
Focus | Proposition | Note | Leçon centrés à cheval sur son bord (Focus depuis le 22 octobre 2026 :
voir Onglet Focus ; 72 + 62 + 98 + 57 + 65 = 354 dans le panneau de 528) (`Vues.segments` : chacun son image et sa
variante bleue `-actif`, sous un calque, `Fenetre.choisirSegment`, un vrai clic ; ni survol ni
focus), l'aperçu (`Vues.apercu`, sur un aplat du fond des vignettes, 2B2B2B dans les deux
apparences), la rangée ◀ légende ▶ · ⤢ Agrandir commune aux onglets
(`Vues.navigationApercu` ; la légende de la photo active est un texte riche, « <EM>nom
(copie)</EM> · appareil · date », lue par `Lightroom.legende` seulement quand la photo active
change, à l'heure locale), puis les variantes superposées, chacune sur sa carte en image :
l'étape dans Aperçu (`Vues.etape`, carte-etape), la proposition (`Vues.proposition`,
carte-proposition), la carte Note (`Vues.notation`, sa grille au-dessus de carte-note) et la leçon
(`Vues.lecon`, carte-lecon), et, depuis le 22 octobre 2026, la carte Focus (`Vues.focus`,
carte-focus, deuxième variante). Clés d'onglet : `apercu`, `focus`, `proposition`, `notation` (par
défaut, montré à l'ouverture) et `lecon` ; `Fenetre.apercuOnglet` et `Fenetre.surOnglet` passent sous la
clé `apercu` (l'ancien `etape`). Bascules d'elle-même, une par arrivée : vers Proposition quand une
proposition (ou une liste « Je le fais », ou une comparaison) arrive, sauf celle préparée à
l'ouverture ; vers Note quand une note arrive pour la photo active ; vers Leçon une fois par leçon
arrivée (`Fenetre.leconVue`), jamais quand une proposition attend ou qu'un exercice est en cours ;
jamais vers Aperçu ni vers Focus. L'aperçu appartient à l'onglet (`Fenetre.apercuOnglet`, demandé d'abord par
`rafraichirApercu` ; nil : l'aperçu commun) ; un clic sur une ligne d'image reste prioritaire
jusqu'à un autre onglet, une image nouvelle, une autre conversation ou un clic sur une étape.

**Contrôles** (constats du 21 octobre 2026, voir plus bas) :

- fonds et filets : des aplats (`Vues.aplat`, un `f:picture` sans image à `background_color`) ;
  `background_color` est sans effet sur `row`, `column`, `view`, `group_box` et sur la fenêtre
  (A1, A5), et `primary_line_color` d'un séparateur aussi (A6) ;
- images : `Dispositions.IMAGES`, seule source de leurs tailles en points, un seul PNG en 2x
  (144 ppp) chacune, toujours avec `width` et `height` ; chemin par `Fenetre.image` (jamais
  `images/<nom>.png` écrit en dur), dans le jeu de l'apparence ;
- tout clic sur une image passe par un calque (`Fenetre.calque` : un texte vide de taille fixe
  posé dessus, registre `Fenetre.parCalque`) : `mouse_down` sur un `f:picture` ne reçoit rien
  (C1). Un calque n'a pas d'`enabled` : son gestionnaire vérifie l'état lui-même ;
- tout bouton passe par `Fenetre.bouton` (`push_button`, ou `square_button` avec `carre` : le
  rectangle blanc à bord fin de la maquette, B3) : `icone` pose une image par `image_name`, sans
  titre (une icône chevauche le titre, B3) ; `bezel` donne la hauteur visible, le cadre en a 2 de
  plus (D5, `Dispositions.cadreBouton`). Les boutons à icône et titre de la maquette portent donc
  un glyphe dans leur titre (＋ ☆ ⚑ ⊗ ? ⤢) ;
- les boutons bleus (`Vues.boutonBleu` : Envoyer, Accepter, Accepter N ★) : trois images (normal,
  enfoncé 0,15 s par `Fenetre.enfoncer`, inactif), le titre blanc par-dessus (éteint quand il est
  inactif : `titreInactif` de la palette), un calque qui ne fait rien quand sa clé d'état est
  fausse ; ni survol, ni focus clavier ;
- un élément de la maquette sans fonction est posé grisé, sans action, infobulle « À venir »
  (`Vues.inactif`, `Fenetre.A_VENIR`) : « ? À vérifier » de la carte Note ;
- texte riche : `<EM>` exige `emphasis_font` (sans lui, ni gras ni couleur, D4) ; une emphase plus
  grande que la police du texte coupe la dernière ligne de `height_in_lines` (D4) : emphase de même
  taille partout ; `text_color` et `emphasis_color` vont ensemble ; ni `&lt;` ni `&amp;` (affichés
  tels quels) ; une balise seule disparaît. `Fil.largeur` ignore les balises et mesure la partie
  balisée dans sa police d'emphase ; `Fil.couper` ne coupe jamais une balise : il ferme le passage
  en fin de ligne et le rouvre à la suivante. Les textes venus de Claude perdent leurs balises ;
- polices : celle du système (`'<system>'` en 13, 12 et 11, `'<system/bold>'` en 13, 12, 11 et
  16) et Menlo 11, mesurées par `scripts/metriques.swift` (clés `texte`, `texte12`, `petit`,
  `gras`, `gras12`, `gras11`, `titre`, `mono` ; ＋ ⊗ ⤢ ajoutés aux caractères mesurés) : l'encre
  de Lightroom fait 1 à 2 points de moins que la chasse NSFont (D9) ; `Fenetre.largeurLibelle`
  ajoute 2 points à un libellé fixe ;
- `visible` lié sur un `f:view` le cache et le montre (D10) ; les variantes superposées par
  `Vues.masquable` ne laissent répondre que la variante montrée (D11).

**Apparence** : préférence `apparence` (`Chemins.defauts`, `claire`) et menu Apparence de la
section Fenêtre Claude du Gestionnaire de modules externes (« de la fenêtre Claude, à sa prochaine
ouverture ; boutons et champs suivent macOS »), que le diagnostic dit. `Dispositions.APPARENCES`
(`claire` → `images`, `sombre` → `images/sombre`), `Dispositions.PALETTES` (la seule table des
couleurs : 37 clés par palette, textes, aplats, filets, aperçu, images ; la claire est la
maquette, avec l'orange, le rouge et Menlo de la 1.2), `Dispositions.apparence` (une valeur inconnue
retombe sur `claire`, à l'emploi, comme `Moteur.modeleEtEffort`), `Dispositions.image(nom,
apparence)`, `Dispositions.couleurs(apparence)` (triplets neufs, sans `LrColor`). La fenêtre les
reprend à chaque ouverture (`Fenetre.preparerApparence`, `Fenetre.COULEURS`). La palette sombre :
fonds #1E1E1E, #2A2A2A et #323232 (comme macOS en sombre), textes #E8E8E8, bleu des textes
#5AA2F6, bleu des boutons #1F6FDB (titre blanc à 4,8:1), titre d'un bouton bleu inactif #7F8EA3 sur
#2B3F5C (3,2:1 : il paraît éteint) ; chacun de ses textes se lit au moins aussi bien que dans la
claire sur les mêmes fonds (`essais-images.lua`). Les contrôles natifs suivent l'apparence de
macOS, quelle que soit celle choisie ici. Les images : `luajit scripts/gabarits.lua | swift
scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin` (les deux jeux, d'après
`Dispositions.IMAGES` et `Dispositions.PALETTES` ; refus, avant d'écrire, d'une couleur absente ou
invalide, d'un dossier invalide), et l'image « aucun aperçu » par `luajit scripts/gabarits.lua |
swift scripts/images-vides.swift Lightroom/Developpeur.lrplugin` : `images/vide-498x332.png` et
`images/sombre/vide-498x332.png` (`Dispositions.nomImageVide`, `Dispositions.imageVide(apparence)`),
du fond et du texte de chaque palette. `vide-320.png` (1.2) et `vide-330x220.png` (fenêtre B de
1 280 × 800) sont retirées.

**Écarts voulus ou inévitables avec la maquette** : barre de titre native « Développeur », blanche,
de 33 ; fond de la fenêtre #EFEFEF, non réglable, visible seulement dans la marge de 1 ; filets
sans relief ; boutons blancs à coins carrés ; un glyphe à la place des icônes au trait des boutons
à titre ; pas d'état enfoncé natif ni de focus pour les boutons et segments en images ; pas de
défilement natif de la liste ni du fil (cases et lignes fixes, ▲ ▼) ; une seule emphase par texte
riche ; « Passe 2 · à vérifier. » à la place d'un oui ou non par passe ; éléments ajoutés pour ne
rien perdre de la 1.2 et de la 1.3 (voyant Écran, bandeau, position dans le fil, ▲ ▼ des cartes,
◀ ▶ des images, invite Composition, contenu des onglets que la maquette ne dessine pas) ; non
posés, par décision de Dany : « ★ Noter » et le menu Modèle (et le ✎ du titre) ; les étoiles de
« Votre note » sans état grisé pendant le travail (le clic est refusé et le bandeau le dit).

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

### Proposition dépassée par une étape de Claude (correctif 1.3.2)

Constaté le 22 octobre 2026 sur une copie d'essai : la proposition préparée à l'ouverture attendait
dans l'onglet Proposition ; Dany a écrit « Applique ta proposition, puis termine par la leçon de la
photo. » ; Claude a posé les mêmes réglages par `apply_settings` (étape « Claude · passe 1 :
lumière et couleur »), puis `photo_lesson`. La carte offrait encore Accepter (bleu), Refuser,
Ajuster… et Je le fais : Accepter aurait fait poser la proposition une seconde fois ; et la fenêtre
ne passait pas à l'onglet Leçon, qui ne s'ouvre pas tant qu'une proposition attend.

Règle (`Conversation.clorePropositions`, appelée à la réponse de chaque outil d'étape, avec ses
textes) : dès qu'un outil d'étape qui change l'image (`Conversation.OUTILS_ETAPES`, sauf les
classements `set_metadata` et `manage_collections`, qui ne la changent pas ; jamais en `preview`,
jamais en erreur) écrit une étape (un `etape_id` dans sa réponse) sur la photo d'une proposition
encore en attente arrivée avant lui, cette proposition n'attend plus. `match_series` ne donne pas
d'`etape_id` (une série ne garde pas d'avant/après) : ses photos écrites se lisent dans `photos`
de sa réponse, celles qui portent `etapes` (par la mesure) ou `etape` (`by = exif`)
(`Conversation.photosHarmonisees`) ; un plan sans `confirm`, une photo déjà proche de la
référence et la référence elle-même, que `match_series` ne touche pas, n'en ont pas : leurs
propositions attendent. Sa photo : le `photo_id` de l'entrée de `preview_settings`, sinon celle de
sa réponse (`Conversation.photoLue`) ; inconnue (une proposition enregistrée avant le correctif,
sans champ `photo`, ou une réponse qui ne l'a pas dite), la proposition attend, comme avant le
correctif : une étape sur une autre photo la clorait à tort (relu le 22 octobre 2026 : « Remplacée »
sur la photo A après un `apply_settings` sur B, A inchangée). Elle devient `appliquee`
(« Appliquée par Claude ») si la première étape de sa photo pose chacun des réglages lus de la
proposition (clé et valeur d'après, en texte, telles que les deux réponses du connecteur les
disent ; il en faut au moins un de lu), sinon `remplacee` (« Remplacée par une retouche de
Claude ») : une partie des réglages, d'autres valeurs, un autre outil, `match_series` (ses
réglages relatifs ne se comparent pas), ou une proposition dont la réponse n'a pas dit ses
réglages. Le nom de l'étape est gardé (`etapeClaude` ; pour `match_series`, sa première étape sur
la photo, « harmonisation : passe 1 »).
`Conversation.propositionEnAttente` ne la rend plus : Accepter, Refuser et Ajuster… sont grisés
(`enAttente` faux), `Moteur.repondre` et `Moteur.ajuster` ne font rien, et la leçon qui suit
s'ouvre (`Fenetre.rafraichirLecon`). La carte montre la dernière proposition du fil si elle est
close ainsi (`Conversation.propositionClose`), sa phrase en tête (`Fenetre.phraseClose` :
« Appliquée par Claude (étape « passe 1 : lumière et couleur ») : elle n'attend plus votre
accord. »), puis sa raison et ses réglages, sans la phrase de l'aperçu d'un recadrage (« Rien ne
change avant Accepter. »). Le fil dit « Proposition appliquée par Claude » ou « Proposition
remplacée par une retouche de Claude ». Une proposition acceptée, refusée, ajustée ou faite par
Dany (Je le fais) garde son chemin ; une conversation enregistrée avant le correctif garde ses
propositions en attente (la règle ne joue qu'à l'arrivée d'une réponse, et leur photo n'est pas
connue). Essais : `Tests/Lua/Fenetre/essais-lecon.lua` (« Proposition dépassée… », dont une
proposition sans photo connue et `match_series`).

### Carte Note (1.1, revue en 1.1.1)

Jusqu'à la 1.2 ; en 1.3, son allure et ses boutons sont ceux de la carte Note B (section
suivante).

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
  vous l'acceptez ou la changez ; 5 ★ reste à vous seul (depuis le correctif 1.3.2 : de 0 à 5 ★ ;
  vos coups de cœur, un libellé de couleur que vous posez vous-même).

Boutons (Accepter et Changer… passent par `F.enTache` : ils lisent le registre et le catalogue,
ou ouvrent une fenêtre modale) :

- **Accepter** (`Fenetre.accepterNote`) : la proposition telle quelle
  (`Notation.poser{ {photo = id} }` par `Fenetre.poserNote`) ; actif pour une proposition « à
  vérifier » (ou « proposée », d'avant la 1.1.1) ;
- **Changer…** (`Fenetre.changerNote`) : fenêtre modale « Changer la note », de 0 à 5 ★ et le
  drapeau (inchangé, sans drapeau, Retenue, Rejetée) ; actif dès qu'une photo est active.

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

### Mes demandes (demandé par Dany le 22 octobre 2026)

Ses mots : « un menu déroulant à droite de Style. Ce menu aurait une liste de mes prompts
personnels, donc j'ai pas à recréer à chaque fois », avec ajouter, supprimer et renommer, et,
« suite à une correction d'une photo », la demande de Claude à ajouter. Ses choix : choisir une
demande remplit le champ (sans l'envoyer : Retour l'envoie) ; après une retouche, un bouton
« Garder la demande » sur la ligne d'actions du tour de Claude ; la gestion au bas du menu.

**Le menu** (`Vues.mesDemandes`) : un `popup_menu` de 280 (`Dispositions.TAILLES.mesDemandes`),
à droite du menu Style, 8 points après lui, dans la rangée sous le champ ; le bandeau prend ce
qu'il laisse (`D.bandeau` 324). Ses éléments (`Fenetre.elementsMesDemandes`, tables neuves, liés
par `mesDemandesItems`) : son titre « Mes demandes » (valeur `Fenetre.MENU_TITRE`, la valeur
montrée quand rien n'est choisi), un séparateur, chaque demande « Nom — description » (valeur :
son indice), coupée par « … » à la largeur du menu moins ses flèches (`Fenetre.titreDemande`,
`Fenetre.FLECHES_MENU` 32, mesurée dans la police du menu, `texte` de `Metriques`), un séparateur,
puis Ajouter…, Renommer… et Supprimer… ; sans demande, « Aucune demande gardée » grisé et Ajouter…
seul. Relevé dans `AgViewUtils.getPopupMenu` de Lightroom 15.6 (code compilé, lecture seule, sans
l'avoir vu) : un élément `{ separator = true }` est un séparateur, `enabled = false` grise un
élément (`updateStatus`), un élément-table sans `title` montrerait `tostring` de la table ;
`value_equal` et « < no_match_found > » (une valeur sans élément) existent : d'où le titre en
élément, toujours choisi. La simulation de la fenêtre en tient : `S.refusElements` (à la création
et à chaque nouvelle valeur liée), `S.choisir` (ni séparateur, ni élément grisé, ni valeur
absente ; le champ tapé validé d'abord, comme par un clic). Grisé pendant que Claude travaille
(`enabled = libre`), comme le Mode.

**Choisir une demande** (`Fenetre.choisirMesDemandes`, l'observateur de `mesDemandes`) : sa valeur
passe par `Fenetre.lierRadio`, comme le Mode : un choix, même du titre rechoisi, annule l'envoi
automatique de la demande que ce clic aurait validée (supposé pour un menu ; constaté D3 pour un
calque, un radio, un segment et un bouton). Le menu revient aussitôt à son titre (pour rechoisir
la même demande). La demande va dans le champ, à la place du texte tapé (`Fenetre.mettreDemande` :
la clé `saisie` posée sous `Fenetre.ignorerSaisie`, `Fenetre.demandeMise` gardée,
`Fenetre.DEMANDE_DANS_LE_CHAMP` au bandeau) : ni envoi automatique, ni bouton, ni bascule
d'onglet. Retour l'envoie : validé sans y rien changer, le champ ne change pas la clé, et la table
ne prévient pas son observateur (supposé, comme la simulation) ; la valeur liée du champ passe donc
par `Fenetre.lierSaisie`, dont le `transform` (de la vue vers la table) lance l'envoi automatique
quand la valeur poussée est la demande mise. Changée dans le champ, la demande part par
l'observateur, comme une demande tapée ; Envoyer l'envoie aussi.

**Ajouter…, Renommer…, Supprimer…** (dans une tâche, `Fenetre.enTache`) : de petites fenêtres
modales. Ajouter… (`Fenetre.ajouterDemande`) : Nom, Description (courte, montrée dans le menu
après le nom) et Texte (six lignes), pré-remplis du texte du champ (depuis le menu) ou de la
demande de Claude (depuis « ＋ Garder la demande ») ; un nom proposé déjà pris en reçoit un libre
(« … 2 », `Stockage.nomLibre`). Renommer… (`Fenetre.renommerDemande`) : un menu « Demande : »
(les noms), puis les mêmes champs, remplis de la demande choisie. Supprimer…
(`Fenetre.supprimerDemande`) : le même menu, le texte de la demande, puis `LrDialogs.confirm`. Le
refus (`Stockage.refusDemande` : `NOM_VIDE`, `NOM_PRIS` — majuscules et accents ne comptent pas
—, `TEXTE_VIDE`) se dit en direct sous les champs, et le bouton d'action est grisé tant qu'il reste
(`actionBinding = { enabled = { bind_to_object = q, key = 'valide' } }` de
`LrDialogs.presentModalDialog`, relevé dans `LrDialogs.lua`) ; un refus après le clic (le bouton
resté actif, le fichier changé entre-temps, une écriture impossible) rouvre la fenêtre, champs
gardés et raison dite. Le bandeau dit `DEMANDE_GARDEE`, `DEMANDE_CHANGEE`, `DEMANDE_RETIREE`.

**Rangement** (`Stockage.lua`, section « Mes demandes ») : `mes-demandes.json` dans
`Chemins.racine()`, `{ format = 1, demandes = [ { nom, description, texte } ] }`, trié par nom
(`Texte.plier`), écrit d'un coup (`Fichiers.ecrire` : provisoire, puis renommé), relu à chaque
ouverture de la fenêtre et avant chaque changement (`Stockage.garderDemande`,
`Stockage.changerDemande`, `Stockage.retirerDemande`). Une entrée sans nom ou sans texte, ou d'un
nom déjà lu, ne se lit pas. Un fichier illisible (ou d'un autre format) n'est jamais perdu en
silence : dit au journal et au bandeau (`Fenetre.DEMANDES_ILLISIBLES`), il est mis de côté
(`mes-demandes-illisible-<date>.json`) avant la première écriture, comme `carnet.json` ; s'il ne
peut pas l'être, rien n'est écrit. Tout ce qui en sort est fait de tables neuves. `uninstall.sh
--tout` le retire (tout le dossier) ; sans `--tout`, il reste, dit avec le reste.

**La demande de Claude** : la section « Demande à garder » des consignes de la fenêtre
(`Consignes.texte`) : après une retouche (une étape écrite ; pas une proposition, une notation, un
classement ou une leçon seuls), Claude finit sa réponse par une ligne seule « Demande à garder :
« … » », une ou deux phrases qui referaient son travail sur une photo semblable, sans identifiant
ni nom de fichier ; la section Leçon dit « rien après (sauf Demande à garder) ». Le texte des
consignes y a fait de la place (7 489 → 7 476 caractères pour un plafond de 7 500) en raccourcissant
l'introduction, Pour qui, Mise en forme, Contexte, la puce Proposer d'abord, la puce Notes, Titre,
Style et Leçon, sans en changer le sens. La fenêtre reconnaît la ligne
(`Conversation.demandeAGarder` : gras ou puce Markdown, guillemets « », “ ” ou " ", point final
après eux, espaces insécables ; la dernière du texte ; le gabarit « <ta demande> » refusé). La
ligne d'actions du tour (`Fil.lignes`) gagne « ＋ Garder la demande » quand ce tour a retouché
(`Conversation.estRetouche` : un outil de `OUTILS_ETAPES` hors des classements, abouti, avec une
étape écrite ; `match_series` abouti) et que le texte de Claude, arrivé en entier, porte la ligne :
`actions` prend le suffixe `+demande` (`Fil.valeurActions`, `Fil.lireActions`), `demande`
l'indice du texte. Le bouton (`Vues.ligneFil` : carré small de 136, en petit) se pose au bout de
la ligne, à droite, dans une rangée poussée par `margin_left` (D6), comme « Pourquoi ? » : une vue
masquée garde sa place, et le poser après les deux autres boutons demanderait une variante par
place (quatre boutons par ligne au lieu d'un). Son clic (`Fenetre.garderDemande`) ouvre Ajouter…
pré-rempli : le nom proposé est ce qui précède « : » (40 caractères au plus), sinon les quatre
premiers mots, sans la ponctuation de sa fin (« … » retiré en entier, jamais dans une classe de
Lua 5.1, qui en prendrait chaque octet à part : « Retouche ÉTÉ À » perdait l'octet 0x80 de « À »,
relu le 22 octobre 2026) ; la description, la suite, coupée aux mots (60 caractères au plus,
`Conversation.preparerDemande`) ; le texte entier. La ligne reste dans le fil : Dany la lit.

Essais : `Tests/Lua/Fenetre/essais-mes-demandes.lua`.

### Carte Note B (1.3)

En 1.3, la carte Note suit la maquette (`Vues.notation`, lot B5) ; la section précédente reste
vraie pour ce qu'elle fait au registre (`Notation.poser`, `Notation.recaler`, abonnement). Une
grille d'étiquettes grises de 12 alignées à droite sur 70 points (`D.etiquetteNote` ; « Votre
note : » mesure 66,6).

Correctif 1.3.2 (demandé par Dany le 22 octobre 2026 : « tu vas pouvoir enlever dans l'interface
Passes … et Plafond 4 : mesuré au tri, pas plus ») : plus de rangée « Passes : » (`Vues.passes`,
`Fenetre.PASSES`, `Fenetre.PASSE_MAX_CLAUDE`, `Fenetre.etatPasse`, la clé `notePasse`,
`D.lignePasses`, les images coche-10 et chevron-passe) ni de ligne du plafond sous son filet
(`Vues.lignePlafond`, `Fenetre.textePlafond`, les clés `aPlafond` et `plafondTexte`, l'image
avertissement, la couleur `filetPlafond`, `D.plafond`, `D.avertissement`). La passe de Claude reste
dans l'en-tête de la grille (« <EM>Passe 2 · à vérifier.</EM> … ») ; le plafond mesuré au tri reste
dans le registre (`plafond` de la proposition) et dans le critère Plancher technique que Claude
écrit. La place libérée va à la grille des critères : `TAILLES.autourNote` 137 (161 avant), carte
Note de 583 (559), `criteres` 33 (30), soit 34 lignes de 16, le plus qui laisse 12 points sous le
contenu (`essais-fenetre-b.lua`) ; carte-note régénérée dans les deux jeux. « Voir à 100 % » passe
dans la rangée du bas (`Vues.voirZoom`, carré de bezel 26, titre en 13, `D.zoom` 92 : son titre
mesure 76,3), toujours montré, grisé sans zoom (il ne suivait plus rien une fois la ligne du
plafond retirée). La carte, de haut en bas :

- « Votre note : » : cinq étoiles de 24 sous des calques de 30 (`Vues.etoilesNote`, constaté C4 :
  le clic sur la 3e pose 3 ★) qui appellent `Fenetre.poserEtoile(k)` ; un clic sur la note posée
  la retire (0 ★) ; 5 ★ se pose. À droite, `notePoseeTitre` (le sens du standard,
  `Fenetre.SENS_NOTES` : « Pas encore jugée », « Correcte », « Tient seule »…) et `notePoseeSous`
  (« 2 ★ · drapeau Retenue ») ;
- « Drapeau : » : « ⚑ Retenir » et « ⊗ Rejeter » (carrés de bezel 24, `Fenetre.poserDrapeau` : le
  drapeau, ou aucun si la photo l'a déjà ; les étoiles restent. Retenir, ou retirer un drapeau, ne
  décide rien de la proposition de Claude ; Rejeter la décide : changée, ou acceptée si Claude
  proposait le rejet), et « ? À vérifier » posé grisé (`Vues.inactif`). Question encore ouverte
  à Dany : le remettre comme « remettre à vérifier » par `Notation.decider`, qui existe ;
- « Claude propose » (gras 12) : cinq petites étoiles (etoile12) d'après `noteClaude` (0 à 5),
  « rejeter » en rouge, ou « rien pour l'instant » ; à droite, « critères du plus lourd au plus
  léger » ;
- la carte des critères (`Vues.carteCriteres`, sur carte-note) : une grille de `D.criteres` + 1
  lignes de 16 (`Vues.ligneCritere`, variantes selon `ng..k` : `plein`, `etat` — la première ligne,
  « <EM>Passe 2 · à vérifier.</EM> raison », l'emphase de la couleur de `notationCouleur`, une
  variante par teinte de `Fenetre.TEINTES_NOTE` —, `critere` — l'étiquette en gras 12 sur 120
  points, `ne..k`, puis le texte sur 251, `nt..k`, son verdict en `<EM>` : `Fenetre.verdict`, deux
  mots au plus jusqu'au premier point —), lue page par page (`Fenetre.lignesCriteres(prop,
  largeurs)` à la place de `Fenetre.texteNote`, `CARTES.note` en grille, `montrerPage` avec ses
  lignes déjà faites) ;
- en bas : ▲ ▼ (`Vues.fleches 'note'`), « Voir à 100 % » (`Vues.voirZoom`), puis, à droite,
  « Laisser à N ★ » ou « Laisser rejetée » (`titreLaisser` : `Fenetre.laisserNote`,
  `Notation.decider` `ecartee`, rien dans le catalogue ; la proposition passe en gris et Accepter
  se grise), « Changer… », et « Accepter N ★ » ou « Accepter le rejet », un bouton bleu
  (`Vues.boutonBleu`, clé `peutAccepterNote`), jusqu'à « Accepter 5 ★ » depuis le correctif 1.3.2
  (`Fenetre.noteDeCinq` et `Fenetre.PAS_CINQ` sont retirés).

« Voir à 100 % » (décision de Dany du 21 octobre 2026) : le zoom que Claude a pris pour noter la
photo, c'est-à-dire la plus récente image d'un appel réussi de `view_photo` avec `region` sur cette
photo dans la conversation (`Conversation.dernierZoom`, pur ; la photo vient de `photo_id`, sinon
de la réponse), gardé par `Fenetre.zoomDeLaNote` ; `Fenetre.voirZoom` le montre dans l'aperçu comme
un clic sur sa ligne d'image (Agrandir : en grand), sans Claude ni Lightroom. Sans zoom, le même
bouton grisé, infobulle `Fenetre.SANS_ZOOM` (deux carrés superposés : une infobulle liée n'est
pas constatée). Jusqu'à la 1.3.1, toute la ligne du plafond, ce bouton compris, suivait
`aPlafond` ; depuis le correctif 1.3.2, il est dans la rangée du bas et toujours montré.

Étoiles, drapeaux, Laisser, Changer… et Accepter passent par une tâche et sont refusés pendant que
Claude travaille (`Fenetre.CLAUDE_TRAVAILLE`), pendant une note en cours
(`Fenetre.NOTE_EN_COURS`) ou sans photo active (`Fenetre.AUCUNE_PHOTO`), et le bandeau le dit ; ils
écrivent par `Notation.poser` (le clic vaut accord) ou `Bibliotheque.noter`, une étape
« Claude · notation » que `undo_last` défait. `Fenetre.rafraichirNotation` pose `noteCatalogue`,
`notePoseeTitre`, `notePoseeSous`, `noteClaude`, `notationCouleur`, la grille, `peutVoirZoom`,
`titreAccepterNote`, `titreLaisser`, `peutAccepterNote` et `peutChangerNote`. Toujours ni Noter ni
Évaluer (`Fenetre.verifierNote` reste nil).

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
nouvelle conversation (`Fenetre.suivreSelection`, demandé par Dany le 20 octobre 2026), sauf
pendant un exercice « Je le fais » (1.3 : Dany peut regarder d'autres photos sans le perdre). Elle est
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
                                            dont ecran-<id>.json en 1.2, PhotoActive/ : vignette
                                            de la photo active, et après la 1.1.1 sa copie marquée
                                            <nom>-af.jpg ; en 1.1, Notation/<séance>/ : vignettes
                                            de la séance)
    liaison.jeton                           jeton privé de la liaison (1.2), écrit par le module à
                                            chaque démarrage, droits 600 ; liaison.jeton.nouveau,
                                            son fichier provisoire (voir Liaison fermée)
    connecteur.json                         écrit à chaque lancement de Claude Code
    consommation.json, publication.json     jetons comptés, profils de publication de l'utilisateur
    notation.json                           notes proposées par Claude (registre, format 2, propre
                                            au catalogue ouvert ; voir Notation)
    carnet.json                             carnet de progrès et leçons des photos (1.3, format 1 :
                                            vocabulaire en tête, une table par catalogue, une entrée
                                            par original ; voir Carnet de progrès) ;
                                            carnet-illisible-<date>.json : un fichier illisible
                                            mis de côté, jamais écrasé
    Etapes/<uuid>/                          avant/après des étapes de Claude (1.3) : <id>-avant.jpg,
                                            <id>-apres.jpg, <id>.json ; vue.jpg et prepare-<n>.jpg,
                                            d'une session (voir Pourquoi ? : l'avant/après des
                                            étapes)
    guide-de-style.md                       guide de style (remember_style)
~/Library/Logs/Developpeur/module.log         journal de la liaison
~/Library/Logs/Developpeur/conversation.log   journal de la fenêtre
```

Dans le module (1.3) : `images/` et `images/sombre/`, les images de la fenêtre B, un jeu par
apparence (voir Fenêtre B). `uninstall.sh` garde `carnet.json` et `Etapes/` ; `--tout` retire
tout le dossier, eux compris.

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

1.3 : `Preferences.defauts` gagne `carnet` (vrai par défaut : case « Carnet » de la section
Liaison, après Mise au point, « Carnet de progrès : noter les défauts vus à la prise de vue, avant
la première retouche de Claude » ; décochée, `carnet constater` refuse avec le motif `preference`,
voir Carnet de progrès) ; `Chemins.defauts` gagne `avantApresEtapes` (vrai : case « Avant/après »,
« Garder l'avant/après de chaque étape de Claude (un rendu de plus par étape, photo active
seulement) »), `leconFinRetouche` (vrai : case « Leçon », « Claude finit chaque retouche par la
leçon de la photo » ; décochée, `Moteur.envoyer` joint « [Sans leçon] ») et `apparence`
(`claire` : menu « Apparence », après Effort, voir Fenêtre B). Les deux cases suivent « À
l'ouverture ». Le diagnostic les dit au bout de leur ligne, sans en changer le début, que lisent
les essais : « ; carnet de progrès : true (N photos) » sur la ligne Mode (`Carnet.nombre`, « ? »
s'il ne se lit pas), et « ; avant/après des étapes : … ; leçon en fin de retouche : … ;
apparence : claire » sur la ligne Fenêtre Claude (une apparence inconnue est dite à côté de celle
sur laquelle elle retombe). La case Carnet ne vise que les constats : `lecon garder` ne la lit
pas, et une leçon se range encore dans `carnet.json` quand elle est décochée (décidé par Dany le
24 octobre 2026 : elle coupera aussi les leçons, montrées encore dans la fenêtre ; au prochain
correctif).

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

En 1.3, en bas du volet, au-dessus du voyant Écran, en gris des en-têtes (`Vues.versions`). Jusqu'à
la 1.2, en bas de la colonne de droite (en 1.1 et 1.1.1, aussi de la colonne Note de l'Atelier et de la
fenêtre du Panneau, retirés), deux lignes (`Composants.lua`, `Vues.versions`), lues à
l'ouverture de la fenêtre : « Développeur », ce module (`VERSION` de son `Info.lua`), et
« MCP-Développeur », le connecteur (`mcp-developpeur --version`, cinq secondes au plus). Les deux
viennent de la même installation, au même numéro : si elles diffèrent, la plus ancienne passe en
orange « à mettre à jour » (réinstaller Développeur) ; un connecteur absent devient
« MCP-Développeur · introuvable ».

### Bas de la fenêtre

Jusqu'à la 1.2. En 1.3, chaque colonne a sa hauteur fixe dans le contenu de 1 166 (voir Fenêtre
B) : plus d'espace élastique ni de `D.hauteurListe` tiré des lignes du fil ; le bandeau tient sur
deux lignes dans la rangée du bas de la saisie, à gauche d'Envoyer.

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

### Constaté dans Lightroom Classic 15.6 (21 octobre 2026, fenêtre B)

Dans un module d'essai hors du dépôt (« Essai de la fenêtre B », blocs A à C le matin, D l'après-midi
avec « … cadre D7 »), ouvert par la recherche du menu Aide, clics et frappes dans ces fenêtres
seulement, aucune photo touchée ; le module d'essai est ensuite allé à la Corbeille. Mesures sur
captures (écran principal de Dany à 1x : un pixel de capture vaut un point). Chaque constat a sa
règle dans `Tests/Lua/Fenetre/Simulation.lua` et son essai dans `Tests/Lua/Fenetre` (lot B2).
« Relevé » veut dire lu dans le code de Lightroom (AgUI, AgPictureView), pas vu.

- A1 · `background_color` de `presentFloatingDialog` : sans effet ; fond mesuré #EFEFEF (gris par
  défaut). La simulation le refuse.
- A2 · `scrolled_view` : `background_color` appliqué, bord « bezel » ; les liaisons vivent dedans.
- A3 · Une image sous un contenu (`place = 'overlapping'`, l'image d'abord) : la carte arrondie
  bordée en PNG reste dessous, le bouton posé dessus reçoit le clic.
- A4 · `f:picture` : `background_color` sans `value` fait un aplat ; `scaling = 'stretch'` étire
  une tuile ; `frame_width` et `frame_color` font un rectangle bordé. La simulation exige `width`
  et `height` (relevé dans AgPictureView : sans eux, la taille en pixels) et refuse un `f:picture`
  sans image ni fond.
- A5 · `background_color` sur `row` ou `view` : sans effet (refusé aussi sur `column` et
  `group_box`).
- A6 · `primary_line_color` d'un séparateur : sans effet (la ligne reste #DBDBDB) ; refusé.
- B1 · Texte riche `<EM>` dans un `static_text` : passage en gras et en couleur avec
  `emphasis_font` ; une balise `<EM>` seule (non fermée) disparaît : aucune étiquette n'en contient.
  Polices `'<system>'`, `'<system/bold>'`, `{ name = '<system/bold>', size = 16 }`, Helvetica Neue
  Medium 12, Menlo 11 : toutes rendues.
- B2 · Boutons natifs : tailles, gras et glyphes rendus.
- B3 · Bouton par défaut (`default = true`) : le bleu de macOS ; `text_color` sur un
  `push_button` : appliqué ; `image_name` d'un bouton : l'icône se pose mais chevauche le titre
  (refusé avec un titre) ; `square_button` : un rectangle blanc à bord fin, coins carrés.
- B4 · Bouton bleu en image, texte blanc, sous un calque : clic reçu.
- B5 · Champ de deux lignes avec texte indicatif, menu Style, trois `radio_button` du Mode : rendus.
- B6 · Pastilles et icônes PNG en 2x : nettes.
- C1 · `mouse_down` posé sur un `f:picture` : aucun effet ; un calque (`static_text` vide de taille
  fixe posé sur l'image) reçoit le clic. La simulation refuse `mouse_down` sur un `f:picture`.
- C2 · Onglets segmentés en images sur un panneau en image : un clic choisit l'onglet (en bleu).
- C3 · `tab_view` natif : rendu macOS correct, valeur liée lue (non retenu : D11 répond).
- C4 · Étoiles en images sous calques : un clic sur la 3e donne « Votre note : 3 ★ ».
- C5 · Liste groupée par jour sur deux lignes : fond de sélection en image, titre en gras, un clic
  sur une ligne la choisit.
- Barre de titre : 32 points blancs, un filet, puis le fond.
- D1 · Retour dans un champ `immediate = false` avec Envoyer `default = true` : l'observateur du
  champ, puis l'action d'Envoyer 1 ms après, qui lit la valeur validée ; un seul envoi. Retour dans
  « Rechercher » (`immediate = true`) déclenche aussi l'action du bouton par défaut. Sans bouton
  par défaut : Retour donne l'observateur, puis l'envoi automatique 0,308 s après ; Retour dans
  « Rechercher » ne déclenche rien. D'où le repli : aucun bouton par défaut dans la fenêtre. La
  simulation imite la frappe et Retour (`S.taper`, `S.retour`) et refuse plus d'un `default`.
- D2 · Envoyer inactif ou masqué : Retour ne le déclenche plus (ni Arrêter, montré à sa place) ;
  l'observateur, puis l'envoi automatique (0,306 s).
- D3 · Texte tapé sans Retour, puis un clic sur un calque, un radio, un segment ou un bouton :
  l'observateur du champ d'abord (le clic valide le champ), puis le clic, 1 à 3 ms après ; le texte
  reste ; aucun envoi automatique (chaque clic l'annule). `S.cliquer` l'imite.
- D4 · `<EM>` en gras 12 sur `<system>` 12 : même interligne (15 points) que le texte sans balise ;
  une balise sur deux lignes les met toutes deux en gras. Police 11 et emphase gras 12 : la dernière
  ligne de `height_in_lines` est coupée. « < » et « & » bruts s'affichent tels quels, « &lt; » et
  « &amp; » ne sont pas décodés. `emphasis_color` seule, sans `emphasis_font` : aucun effet.
  `text_color` gris avec `emphasis_font` gras et `emphasis_color` ambre : l'emphase reste ambre et
  grasse, le reste gris (le relevé dans AgUI disait le contraire : démenti). Un titre lié balisé
  garde son balisage à chaque nouvelle valeur. La simulation refuse une balise non fermée ou
  imbriquée, une entité, `emphasis_color` sans `emphasis_font`, et une emphase plus grande que le
  texte quand `height_in_lines` est juste.
- D5 · `square_button` : sans hauteur, bezel visible de 17 (regular), 15 (small), 11 (mini) ;
  `height` imposée : 2 de moins (22 donne 20) ; glyphes ☆ ⚑ ⊗ ? ⤢ + rendus (⚑ et ⤢ plus petits) ;
  icônes PNG 2x de 12, 14 et 16 nettes, grisées quand le bouton est inactif ; « ? À vérifier »
  inactif : titre et bord grisés.
- D6 · Trois cases de 21 : 63 points exactement ; « Pourquoi ? » small : bezel de 15, 3 points
  au-dessus et au-dessous ; posé dans une `f:row` à `margin_left` ou seul à `place_horizontal = 1`,
  il répond ; la rangée posée sur le texte ne lui prend pas ses clics ; bouton masqué : le clic va
  au texte.
- D7 · Fenêtre de 1 280 × 799 pour un contenu demandé de 1 278 × 765 : barre de titre de 33 (32
  blancs et un filet #E0E0E0), contenu juste dessous, marge de 1 à gauche, à droite et en bas,
  aucune en haut ; volet 183, centre 630, droite 463 : largeurs exactes ; filets de 1 aux places
  prévues. Couleurs lues à travers le profil de l'écran (#D2D2D2 → #DADADA, #ECECEC → #EFEFEF…).
  Coins du bas arrondis par la fenêtre. Ouverture : construite en 0 ms, montrée en 13 ms. D'où, pour
  1 280 × 800, un contenu de 1 278 × 766 (`S.contenuPourFenetre`).
- D8 · Apparence claire : champ, bouton, carré, menu, case et radio natifs lisibles sur blanc et
  sur #F2F2F2. Sombre : non fait (l'apparence du système n'a pas été basculée).
- D9 · Tailles de police appliquées ; l'encre de Lightroom fait 1 à 2 points de moins que la chasse
  NSFont (`'<system>'` 236 contre 237,8 ; `{ '<system/bold>', 12 }` 235 contre 237,0…) : les
  chasses de `Metriques.lua` restent justes.
- D10 · `visible` lié sur un `f:view` : il se cache et se montre (caché à la création, il ne se voit
  pas ; la place reste) ; un `f:view` posé sur une autre vue, caché, laisse passer le clic dessous.
  La simulation l'accepte ; `row`, `column`, `group_box`, `tab_view` et `scrolled_view` restent
  refusés (constat du 20 octobre 2026).
- D11 · Quatre variantes superposées par `Vues.masquable` : sous Aperçu (la variante du dessous),
  Note et Leçon (celle du dessus), le bouton, le carré, le calque bleu et le texte de la carte
  montrée répondent, aucun d'une carte cachée ; une pastille liée à deux clés se cache et se montre.
  Les onglets restent donc des variantes superposées. La simulation refuse un geste sur une vue
  masquée ou inactive.
- D12 · `radio_button` inactif coché par sa valeur : à la première ouverture, un disque gris sans
  point ; après la valeur reposée, et dès la création à la seconde ouverture, grisé et coché. D'où
  `Fenetre.reposerMode` (`S.RADIO_INACTIF_A_REPOSER` dans la simulation).

Relevés dans le code de Lightroom, non vus : au plus un bouton par défaut par fenêtre
(`setDefaultButtonCell`) ; `f:picture` sans `width` ni `height` prend la taille en pixels de son
image. Non constatés : un clic sur une vue inactive (la simulation le refuse) ; la police par
défaut d'un `static_text` (13 points, supposée) ; un `default` lié qui change fenêtre ouverte (sans
objet : aucun bouton par défaut).

Décisions de Dany le même jour : la fenêtre B d'après la maquette, puis agrandie (voir Fenêtre B) ;
l'étiquette « Style » devant son menu ; Appliquer et Proposer d'abord grisés pendant que Claude
travaille ; ni Noter ni Évaluer, ni menu Modèle ; « ? À vérifier » posé grisé ; « Voir à 100 % »
montre dans l'aperçu le zoom que Claude a pris pour noter ; l'apparence claire ou sombre choisie au
Gestionnaire de modules externes.

### À constater dans Lightroom (1.1, 1.1.1 et après)

En 1.3, la fenêtre B change plusieurs points ci-dessous : les onglets en boutons radio (3), les
hauteurs de la Conversation claire (6) et la rangée de quatre voyants (15) sont sans objet ; ce
qui reste à voir de la fenêtre B et des chantiers de la 1.3 est dans À constater dans Lightroom
(1.3).

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
`essais-integration` 7, `essais-moteur` 13) ; rien n'en a encore été vu dans Lightroom. La 1.2
entière (ces trois changements et les sept chantiers, lots 1 à 9 et 12) passe les deux suites :
`swift test` 367 tests, dont 1 sauté sans `DEVELOPPEUR_ECRAN_REEL=1` (la lecture du vrai écran,
`EcranTests.testLectureReelleSansPlantage`) ; `scripts/tester-module.sh` : liaison 235, fenêtre
47, `essais-dispositions` 18, `essais-integration` 7, `essais-moteur` 16. Ce qui en a été vu dans
Lightroom est dans la section de chaque chantier ; ce qui reste à voir, dans À constater dans
Lightroom (1.2), sauf ce qui tient à la fenêtre (points 15 et 16 ci-dessous).
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
15. Voyant Écran (1.2) : `mcp-developpeur --ecran`, lancé par Lightroom (`LrTasks.execute`,
    connecteur signé au runtime durci), voit-il l'écran de la session, en moins de 5 s, sans demande
    d'autorisation de macOS (ne jamais y répondre à la place de Dany) ? La langue que lit ce
    processus (`Locale.preferredLanguages`) doit être fr-CA, pour que la boîte « Claude · écran »
    dise « Réglages système › Écrans › Profil de couleur ». Capture de la rangée de quatre voyants
    (150 points chacun, environ 690 sur les 900 du centre) : « Écran · non étalonné » non coupé ;
    `docs/capture.png` à refaire. Un voyant orange en permanence (« non étalonné », le cas de la
    plupart des écrans d'amateur) gêne-t-il Dany ? Le repli serait le gris (`neutre`), le texte
    gardé (`Lightroom.decrireEcran`). L'aide « jeton privé » du voyant Lightroom quand le jeton n'a
    pas pu être écrit.
16. Consignes de la 1.2 avec le vrai Claude : les boutons Portrait, Paysage et Noir et blanc mènent
    à un seul `add_mask` « éclaircir et assombrir » suivi de `view_photo` avec
    `compare = previous_step` ; Claude dit une seule fois, quand il demande l'avis de Dany sur la
    peau ou les couleurs, que l'écran n'est pas étalonné ; le résumé de fin donne les chiffres du
    bilan ; Claude ne pose pas `smoothing_requested` de lui-même.

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
  `Top`, `Right`, `Bottom`, `Angle`, `Feather`, et `Flipped = true` toujours : l'inversion passe par
  `MaskInverted` seul, constaté le 20 octobre 2026, voir Éclaircir et assombrir), `Mask/RangeMask`
  de luminance (`LumRange` : quatre valeurs, écrites avec un point quelle que soit la locale),
  `Mask/Image` pour les masques IA (`MaskSubType` 1 sujet, 2 ciel, 0 avec `MaskSubCategoryID` 22
  arrière-plan ou 5000x paysage, 3 avec une catégorie pour les parties d'une personne) ;
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
n'y voit que des réglages locaux. Depuis la 1.2, deux effets intégrés pour la peau s'ajoutent après
ceux des fichiers, un garde-fou refuse une peau trop lissée, et la remarque d'un effet dit sa dose
sous 100 % (voir Peau).

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

## Peau (1.2)

Le lissage de la peau suit les doses qu'Adobe range dans ses fichiers (pas dans son aide), relevées
le 20 octobre 2026 dans Lightroom Classic 15.6, en lecture seule :

- « Peau du visage lisse » (Smooth Facial Skin) : `Settings/Premium/Adaptive - Portrait/Smooth
  Face.xmp`, une `Correction` sur `MaskSubType` 3, `MaskSubCategoryID` 2 (la peau du visage de
  toutes les personnes : `person_part` `face_skin`), `LocalTexture` −0,2 et `LocalClarity2012`
  −0,1 ; Enhance Portrait a les mêmes valeurs, Polished Portrait et Glamour −0,25 et −0,1. C'est un
  paramètre prédéfini adaptatif, pas un effet local : le serveur le fournit en effet intégré ;
- « Adoucir la peau (Lite) » (Soften Skin (Lite)) : `SoftenSkin(Lite).lrtemplate` de
  `localized_presets`, texture −0,35 et clarté −0,15 ;
- « Adoucir la peau » (Soften Skin) : `SoftenSkin.lrtemplate`, clarté −1 et netteté +0,25 ; jamais
  intégré.

`Peau.swift` (`enum Peau`) est la seule copie de ces chiffres, sur l'échelle des curseurs
(`Peau.Dose` : texture, clarté, netteté) : `parDefaut` (texture −20, clarté −10), `lite` (−35,
−15), `forte` (clarté −100, netteté +25, pour les textes seulement). `Peau.effetsIntegres`
(« Peau du visage lisse » et « Adoucir la peau (Lite) », valeurs tirées de ces doses ÷ 100)
s'ajoutent à `LocalEffectLibrary` après les effets des fichiers, qui l'emportent : un effet du même
nom, français ou anglais, n'est pas répété (sur le Mac de Dany, « Adoucir la peau (Lite) » vient de
son `.lrtemplate`, et seule « Peau du visage lisse » s'ajoute). `Peau.dosage`, le texte que Claude
lit, finit la description d'`effect` d'`add_mask` et fait l'étape 4 de l'invite `portrait` : par
défaut « Peau du visage lisse » ; « Soften Skin (Lite) » pour un gros plan dont un zoom montre des
pores marqués ; `amount` 50 pour un homme ou une personne âgée (la moitié de la dose, exactement) ;
rien pour un enfant ; un masque par personne quand les doses diffèrent sur une même photo (`kind`
`person`, `person_at` sur son visage, `part` `face_skin`) ; « Soften Skin » seulement si
l'utilisateur demande une peau plus lisse ; puis `view_photo` avec `region` sur le visage (pores
encore visibles, ni cire ni plaques). La fenêtre Claude (`Consignes.lua`) y renvoie sans chiffres.

**Garde-fou** (`Peau.verifier`, à la fin de `maskParameter`, que seul `add_mask` appelle, après la
lecture de `combine`, avant le prélèvement et tout envoi : un refus n'envoie aucune commande,
`preview` compris). Un masque de peau qui dépasse la dose Lite, intensité comprise (réglage ×
`amount`) : texture sous −35, clarté sous −15, ou netteté négative (Adobe ne la baisse dans aucune
de ses doses), est refusé, sauf avec `smoothing_requested = true`, propriété d'un masque (pas d'un
composant), à poser seulement sur demande de l'utilisateur ou de son guide de style (sa description,
`Peau.demandeDescription`, dit « Jamais de toi-même »). La dose compte l'effet et ses `adjustments`
ensemble. Est de la peau (`Peau.surLaPeau`) : un premier composant `person_part` ou `person` de
`part` `face_skin` ou `body_skin`, non inversé ; ou un composant combiné qui la garde, ajouté ou
intersecté non inversé, ou soustrait inversé (A − non B = A ∩ B, comme Lightroom range une
intersection : `Locaux.combiner`) ; la peau soustraite, ou inversée puis ajoutée ou intersectée, la
retire. Le refus nomme le masque, l'excès, la dose par défaut, et finit par « Rien n'a été fait. ».
`copy_settings`, `edit_mask` (dupliquer) et `match_series` ne passent pas par lui.

**Remarques** (`remarques_serveur` d'`add_mask`) : la remarque d'un effet dit sa dose sous 100 %
(« ; à 70 % : … », `describe(_:facteur:)`, qui ne change pas la teinte d'un virage) ; « Peau
(masque N) : … » signale une dose au-dessus de « Peau du visage lisse » (pour un gros plan aux
pores marqués), ou une dose au-delà de la dose Lite posée à la demande (`smoothing_requested`),
avec de quoi la vérifier (`view_photo` avec `region` sur le visage).

**Constaté le 20 octobre 2026** (Lightroom Classic 15.6, propositions `add_mask` de 1 344 px sur le
portrait d'essai 53709912, `person_part` `face_skin`) : l'intensité d'un masque
(`CorrectionAmount`) est linéaire. Texture −20 et clarté −10 à `amount` 50 rendent la même image, au
pixel près (écart maximal 0), que texture −10 et clarté −5 à 100 ; « Adoucir la peau (Lite) » à
50, la même que texture −17,5 et clarté −7,5 à 100. La dose entière et la moitié ne diffèrent que de
7 niveaux au plus (0,01 en moyenne), aucun pixel au-delà de 12 : à 1 344 px, un lissage fin change
peu la luminance. D'où « la moitié de la dose, exactement » (`Peau.intensiteReduite` = 50). C'est
un constat de rendu : la simulation de la liaison ne peut pas en avoir de règle. La recette
(`--portrait`) le vérifie au pixel près, pas par la part des pixels changés, qui ne verrait pas
7 niveaux : le 21 octobre 2026, 0 niveau d'écart avec la moitié des curseurs, pour les deux doses ;
le détail des joues gardé à 89 % avec les doses par défaut et Lite, 76 % avec « Adoucir la peau » ;
le refus sans `smoothing_requested` ; la dose par défaut posée et relue (voir Recette dans
Lightroom).

**Vision ne dit ni le genre ni l'âge d'un visage** : `VNClassifyImageRequest` (1 303 étiquettes)
nomme l'image entière, dont adult, baby, child et teen, et rien ne sépare un homme, une femme ou
une personne âgée. Claude juge à l'œil (étape 1 de `portrait`), et dans le doute prend la dose la
plus faible. Un indice « enfant probable » par visage (`VNClassifyImageRequest` limitée au cadre du
visage, `regionOfInterest`, dans la branche de l'aperçu entier de `view_photo`) était prévu en
phase 2 (lot 11) ; il n'est pas fait : il fallait d'abord un relevé sur des visages d'âge connu,
désignés par Dany, et ne le garder qu'avec au moins 90 % de précision. Ce relevé n'a pas eu lieu ;
sans lui, l'indice ne se fait pas.

**Limites.** Le garde-fou juge chaque masque seul : deux masques de peau sur la même zone, dans un
même appel ou d'un appel à l'autre (une passe corrective qui en rajoute un), s'additionnent sans
refus (une somme refuserait à tort « un masque par personne », et le serveur ne lit pas les masques
déjà posés). Un masque Sujet ou Personne entière (`person` sans `part`) lissé fort n'est pas
couvert, ni le bruit local (`LocalLuminanceNoise`).

## Éclaircir et assombrir (1.2)

La méthode du tireur en chambre noire, pour mener l'œil au sujet : un seul `add_mask` après le
recadrage (`step_name` « éclaircir et assombrir », `Prompts.Tireur.nomEtape` ; « Claude ·
éclaircir et assombrir » dans l'Historique, une étape que `undo_last` défait), une `reason` qui dit
où va l'œil, un masque doux par geste :

- les grandes zones trop claires, assombries par un dégradé linéaire (`kind` `linear` ; `from_x`,
  `from_y` du côté le plus clair, où l'effet est entier ; `to_x`, `to_y` où il s'éteint), Exposure
  de −0,3 à −0,7 IL selon l'écart (`Tireur.zones`) ; si le sujet traverse le dégradé, `combine`
  `[{"mode": "subtract", "kind": "subject"}]` ;
- le sujet (ou le visage), éclairci de +0,2 à +0,4 IL (`Tireur.sujet`) par un dégradé radial au
  milieu du cadre du visage ou de la `zone_d_interet` de Vision (à défaut, du sujet vu au
  diagnostic), `radius_x` d'une à deux fois sa largeur, `feather` 80 à 100 (`Tireur.sujetFondu`) ;
- les bords, −0,3 IL, −0,5 au plus (`Tireur.bords`), par un dégradé radial inversé
  (`Tireur.forme` : `invert = true`, centré au milieu de la `zone_d_interet` de Vision, à défaut du
  sujet, `radius_x` et `radius_y` 0,7, `feather` 80), à la place du vignetage après recadrage,
  jamais les deux : pas de radial inversé si la photo porte déjà un `PostCropVignetteAmount`, ou si
  le guide de style écarte le vignetage ;
- une zone de forme irrégulière : le pinceau (`kind` `brush`, `strokes`).

Ces doses sont des plafonds, venues de la feuille de route, pas d'une mesure : rester en dessous si
le geste se remarque. En mode « Proposer d'abord », l'étape se montre d'abord par `add_mask` avec
`preview` et `compare`. Puis l'avant/après, obligatoire : `view_photo` avec
`compare = previous_step` (l'état d'avant cette seule étape, à gauche) ; le sujet doit ressortir
sans que le geste se voie : ni halo, ni bande à la limite d'un dégradé, ni anneau ou plaque sombre
dans les coins, pas plus d'ombres bouchées qu'avant (`ecretage_pct` de `mesures` et de
`mesures_avant`), aucune « regression » au bilan. Un défaut vu : `undo_last`, puis le même
`add_mask` à doses réduites (`amount`), et l'avant/après de nouveau.

`Prompts.Tireur` (`Prompts.swift`) est la seule copie des doses et de la forme (`zones`, `sujet`,
`bords`, `bordsRayon`, `bordsFondu`, `sujetFondu`, `forme`, `avantApres`). `Tireur.methode` (vers
où l'œil doit aller, et les grandes zones claires de ce genre de photo) fait l'étape des invites
`portrait` (6, vers le visage), `paysage` (5) et `noir_et_blanc` (5, le grain passant en 6) ;
`retouche_pro` y renvoie (étapes 6 et 7) ;
`Tireur.resume` finit la description d'`add_mask`, car la fenêtre Claude ne lit pas les invites ;
ses boutons Portrait, Paysage et Noir et blanc demandent la méthode sans chiffres (voir Fenêtre
Claude › Claude Code). Les consignes du connecteur n'en disent que « vignetage ou radial inversé,
jamais les deux ».

**Constaté le 20 octobre 2026** (Lightroom Classic 15.6, propositions de 1 344 px sur le portrait
d'essai 53709912 : `add_mask` radial centré en (0,5 ; 0,5), rayon 0,35, `feather` 0, Exposure
−2 IL, comparé au même radial à +0,01 IL ; luminance moyenne par zone 3 × 3, écart en niveaux) :
la forme de `Locaux.radial` (`Mask/CircularGradient` avec `Flipped = true`) agit dans l'ellipse ;
avec `MaskInverted = true` en plus, hors de l'ellipse seulement :

- inversé : coins −69, −68, −31, −58 ; bords haut −2, bas −1, gauche −20, droite −13 ; centre −0,3 ;
- non inversé : centre −45, haut −72, bas −41 ; coins −20, −19, −12, −18 ;
- linéaire de (0,5 ; 0) à (0,5 ; 0,4) : tiers du haut −48 à −57, le reste moins de 1 : le côté de
  `from` seul.

`Locaux.radial` n'a donc pas été changé : il pose toujours `Flipped = true`, inversé ou non, et
l'inversion passe par `MaskInverted` seul ; `Locaux.combiner` et l'action `dupliquer` de
`Masques.lua` ne changent que `MaskInverted` et `MaskBlendMode`. Règle de la simulation de la
liaison (`verifierMasques`, pour `applyDevelopSettings` comme pour un paramètre prédéfini, chaque
composant d'un masque combiné compris) : un `Mask/CircularGradient` porte `Flipped == true` et un
`MaskInverted` booléen. Les essais de la suite de la liaison figent la forme de `Locaux.radial` clé
par clé (18 clés, inversé ou non), vérifient le refus d'une autre forme, et suivent un radial
inversé de bout en bout (`masquer` avec et sans masque IA ; composant intersecté, copie inversée
par `edit_mask`, copie vers une autre photo). Un radial sans `Flipped` n'a pas été essayé dans
Lightroom (il agirait peut-être à l'envers) : la simulation le refuse, sans que ce soit un constat.
La règle porte sur l'état fusionné de la photo : un radial fait à la main sans `Flipped`, s'il en
existe, serait refusé par la simulation ; la forme d'un radial fait à la main n'a pas été relevée.

**Forme des bords, relevée le 20 octobre 2026** sur une seule photo, le paysage 53709786
(propositions de 1 344 px, radial inversé centré, `radius_x` = `radius_y`, donc une ellipse aux
proportions du cadre, Exposure −0,5 IL ; baisse de luminance en niveaux sur 255 au centre, au
milieu des bords et aux coins, et profil de la diagonale du centre au coin en 20 segments) :

| rayon | fondu | centre | milieu des bords | coins | la baisse commence (diagonale) |
| --- | --- | --- | --- | --- | --- |
| 0,6 | 50 | 0 | −16 | −24 à −29 | vers 35 % |
| 0,6 | 80 | 0 | −20 | −24 à −30 | vers 10 % |
| 0,6 | 100 | 0 | −23 | −24 à −30 | dès le centre |
| 0,7 | 50 | 0 | −11 | −20 à −25 | vers 45 % |
| 0,7 | 80 | 0 | −16 | −21 à −27 | vers 15 % |
| 0,7 | 100 | 0 | −20 | −22 à −28 | dès le centre |
| 0,75 | 50 | 0 | −8 | −18 à −22 | vers 50 % |
| 0,75 | 80 | 0 | −14 | −20 à −25 | vers 15 % |
| 0,75 | 100 | 0 | −19 | −21 à −26 | dès le centre |

Toutes les formes descendent sans marche, aucune vignette en plaques (le petit creux vers le
15e segment vient de la scène : à −0,5 IL, une zone claire perd plus de niveaux qu'une sombre), et
le centre n'est jamais touché. Retenu (`bordsRayon`, `bordsFondu`) : rayon 0,7, fondu 80, le tiers
central intact. Le fondu 100 assombrit presque tout le cadre ; le fondu 50 fait une vignette
marquée aux seuls coins. Le 21 octobre 2026, la recette a revu l'inversion sur le portrait
53709912 (coins assombris à 100 %, milieu 0 %), et cette forme sur ce portrait, décentrée sur la
zone d'intérêt (0,38 ; 0,29) : centre 0,48 % de luminance en moins à −0,3 IL, 0,59 % à −0,5 IL ;
coin le plus loin 11,93 % et 19,38 % ; ni plaque ni anneau (voir Recette dans Lightroom). Restent
à voir (À constater dans Lightroom (1.2)) : cette forme sur un intérieur ; le fondu du radial du
sujet ; les doses, que Dany juge sur l'avant/après.

## Proposition, comparaison et paramètres prédéfinis

`essayer` applique un plan (retouche, masques ou taches), rend l'aperçu, puis réapplique les
valeurs d'avant ; rien n'est mémorisé ni journalisé, mais l'Historique garde les deux étapes.
`preview_settings` accepte `reason` (1.3.1 : Claude l'y joignait 3 fois sur 4, comme à
`apply_settings`, et l'appel était refusé ; sa description, `ToolHandler.descriptionRaisonProposition`,
ne promet pas le journal) :
une proposition n'est pas une étape, la raison ne part pas au module ; elle revient dans la réponse
(`raison`, avec `raison_lecture` : la redonner à `apply_settings`). Avec `my_turn`, elle est la
`raison` de l'entrée `exercice` du journal (sinon `step_name`, comme avant).
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

Depuis la 1.2, ces seuils sont nommés, sans changer de valeur, et repris par le tri, les plafonds de
note, `analyze_photos` et le bilan : `DetailMeasurements.seuilFlou` (15), `seuilNet` (35),
`bruitVisible` (0,6), `bruitFort` (1,5) ; `PhotoMeasurements.partNeutreMin` (3 % de tons neutres
pour juger une dominante), `dominanteLegere` (2), `dominanteNette` (6), `chromaTresSaturee` (60) ;
`Measurements.seuilChroma` (3, écart de chroma moyenne visible). Le 35 de la photo brûlée du tri
(`pureWhite > 35`, en % de blanc pur) n'est pas un seuil de netteté : il reste un nombre. Depuis la
1.2 aussi, l'aperçu entier de `view_photo`, les deux images d'un avant/après et une proposition se
mesurent de même (`ToolHandler.mesurerImage`) : un seul décodage, puis la réduction à 512 px par
CGContext (`PreviewImages.scaled`, comme `analyzeScaled`), jamais la vignette d'ImageIO. Avant,
`view_photo` mesurait la réduction CGContext et les propositions la vignette d'ImageIO : sur un même
aperçu de 1 344 px, L* médiane 42,5 contre 42,3, p95 79,9 contre 79,6 (relevé hors de Lightroom
pendant la 1.2), l'ordre de l'écart proposition contre vue relevé dans Lightroom (voir Bilan). Le
zoom (`region`) garde sa mesure de toujours. `view_photo` mesure aussi l'éclairage (voir Éclairage
mixte) et donne son bilan (voir Bilan d'une passe à l'autre).

`AnalyseVision.swift` passe l'aperçu à Vision (macOS) : visages et repères (pupilles, largeur
des yeux), qualité de capture de chaque visage, note esthétique (macOS 15 et plus), saillance par
attention. Les positions sont ramenées au repère de `view_photo` (Vision compte depuis le bas).
Le rayon d'une correction d'yeux rouges vaut 15 % de la largeur de l'œil, une estimation. Les
empreintes (`VNGenerateImageFeaturePrintRequest`) donnent la ressemblance : relevé 0,10 pour la
même photo développée autrement, 0,44 pour la même photo recadrée, de 0,8 à 1 entre photos
différentes ; sous 0,5, même scène (groupes de proche en proche). La meilleure d'un groupe : la
plus nette, puis la note esthétique et le meilleur visage. Vision ne dit ni le genre ni l'âge d'un
visage ; l'indice « enfant probable » prévu pour la peau n'est pas fait (voir Peau).

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

## Éclairage mixte (1.2)

`Eclairage.swift` lit l'éclairage d'un aperçu sur ses tons presque neutres (des gris dans la
réalité, qui prennent la couleur de la lumière) : leur dominante (médianes de a* et b*) par zone
tonale et par case d'une grille 3 × 3, les visages à part. Deux groupes de cases de couleurs
différentes disent un éclairage mixte (une lampe et une fenêtre dans la même pièce). Serveur
seulement : le module ne change pas.

**Mesure** (`Eclairage.mesurer`, sur l'aperçu réduit à 512 px des mesures de `view_photo`, la même
réduction, faite une fois) :

- un ton presque neutre : ni écrêté ni bouché (aucune composante à 250 ou plus, ni à 5 ou moins),
  L* de 15 à 95, hors des visages, à moins de `Eclairage.chromaMax` (12) en a*b* d'un centre
  (`Eclairage.centrer`) : le gris, tant que le point neutre de l'image en reste à
  `toleranceNeutre` (10) près ; au-delà (une dominante globale), le point neutre ramené de 10 vers
  le gris. Le point neutre (`Eclairage.pointNeutre`) : les médianes de a* et b* des tons peu
  saturés (C* < 40, `borneNeutreGlobal`), puis de ceux à moins de deux fois la borne de ce premier
  point ;
- les zones tonales : ombres (L* < 40), tons moyens (40 à 70), hautes lumières (au-delà), lues à
  partir de 2 % de l'image ; `ecart_tonal` entre ombres et hautes lumières, dit à partir de
  `seuilTonal` (8 : `lecture_tonale`, lumière d'appoint d'une autre couleur, ou dominante des
  ombres, ShadowTint ou Color Grading des ombres) ;
- la grille 3 × 3 (bornes comme `Detail`) : une case se lit à partir de 3 % de tons neutres
  (`PhotoMeasurements.partNeutreMin`, comme la dominante de `view_photo`) et 200 pixels ; trois
  cases lues au moins ;
- deux groupes : de toutes les partitions des cases lues en deux (255 au plus pour 9 cases), celle
  qui maximise la variance entre groupes (wG · wD · |μG − μD|²), chaque groupe portant au moins
  `partMinGroupe` (20 %) des tons neutres lus ; `ecart_regions`, la distance a*b* entre les deux ;
  mixte à partir de `seuilMixte` (8). Le plus chaud (ou le plus magenta, si l'écart tient surtout
  à a*) d'abord ; chaque groupe nommé par ses cases (« tiers gauche », « bande du milieu », sinon
  les noms de `DetailMeasurements.zoneNames`) ;
- les visages (cadres de Vision, du plus large au plus petit ; 4 au plus, larges d'au moins 4 % de
  l'image ; un cadre non fini est écarté) : agrandis de 10 % de chaque côté et retirés des cases et
  des zones tonales ; la peau au milieu du visage (L* 25 à 92, C* 6 à 50, non écrêtée, 20 pixels
  au moins, `pixelsMinPeau`) ; la lumière dans un anneau de 2,5 × 2,75 cadres autour, sans les
  pixels à moins de 10 en a*b* de la peau (cou, mains), lue à partir de 100 pixels et 3 % de tons
  neutres, sinon la case du visage ;
- la lumière du sujet : celle des visages (moyenne pondérée par leur largeur), sinon celle de la
  zone d'intérêt de Vision (100 pixels neutres au moins).

Les médianes des cases et des zones se prennent par histogramme, au pas de 0,05
(`Eclairage.Histogramme`) : trier chaque case coûtait 27 ms sur 31 par aperçu (mesuré le
20 octobre 2026 en version optimisée, sur une image de synthèse), l'histogramme ramène la mesure
à 6 ms ; la peau, petite, garde le tri.

**Dans `view_photo`** (`mesures › eclairage`, aperçu entier) : `lecture` (« une seule lumière (écart
entre zones 7,6, sous 8) », « éclairage mixte : plus chaude … (a* …, b* …), plus froide … ; écart
9,7 ; visages dans … », ou pourquoi l'éclairage ne se lit pas), `mixte`, `ecart_regions`,
`zones_tonales` (`a`, `b`, `part_pct`), `lecture_tonale` s'il y a lieu, et `visages`
(`index_vision`, le rang dans `vision.visages` depuis 0, la liste de la mesure pouvant en sauter ;
`peau` L, a, b, `teinte_deg` ; `lumiere` ; `lumiere_mesuree` ; `dans_la_lumiere` si mixte).
Seulement si l'éclairage est mixte, pour rester court (une photo à une seule lumière en reçoit
environ 240 caractères sans visage) : `regions_3x3`, `groupes` (`lumiere`, `zones`, `a`, `b`,
`part_pct`), `balance_proposee`, `conseil` et `base` (la règle de mesure, datée). La forme courte
(`lecture`, `mixte`, `ecart_regions`, `zones_tonales`, `lecture_tonale`) va dans `mesures` et
`mesures_avant` d'un avant/après, et dans `mesures_actuelles` et `mesures_proposition` d'une
proposition ; `analyze_photos` donne `eclairage` (`mixte`, `ecart_regions`, `lecture`) par photo.

`balance_proposee` (`ToolHandler.balanceProposee`, `Tools+Balance.swift`) : la Temperature et la
Tint qui neutralisent la lumière des visages (ou du sujet), par les pentes de `match_series`
(`balancePourPoint`), depuis la balance de la réponse brute du module (Temperature en kelvins pour
un RAW, avant le regroupement des réglages) ; « ordre de grandeur, d'après les pentes de
match_series ; à vérifier par view_photo ». Rien sans Temperature lue, sans lumière du sujet, ou si
l'éclairage n'est pas mixte. `conseil` : à confirmer à l'œil (un mur coloré n'est pas une lumière)
et à dire à l'utilisateur ; balance des blancs sur la lumière des visages (`balance_proposee`, ou
`white_balance_point` sur un gris près d'eux) ou du sujet ; puis l'autre zone par un masque
(dégradé linéaire ou radial, ou objet, sur les cases nommées ; Temperature et Tint locaux contre
son écart), ou gardée chaude si c'est une lampe ; vérifier par `view_photo` que `ecart_regions`
baisse. Les invites `retouche_pro`, `portrait` et `nuit_iso_eleve` le reprennent (voir Consignes
et invites).

**Relevé** : `mcp-developpeur --eclairage <id>… [<fichier.jpg>…] [--essai '{…}']`
(`Eclairage.releve`). Chaque photo, par la commande `apercu` à la taille de `view_photo` mais sans
`point_af` (ni carré, ni ouverture de l'original, et la Temperature brute gardée), ou un fichier
JPEG lu sans Lightroom, est mesurée à chaque borne de `bornesReleve` (12, 15, 20, 25, 30), avec
Vision (visages, zone d'intérêt, scène : interior_room, outdoor, sky), le point neutre et le centre,
la balance qui neutralise la lumière du sujet, et la durée de la mesure ; un tableau résumé finit
la sortie. Lecture seule ; `--essai` passe par `preview_settings` (une autre balance : la
proposition mesurée telle que Lightroom l'a rendue ; copies virtuelles seulement, refusé sur un
original ; deux étapes « Claude · essai » dans l'Historique ; balance inconnue avec un paramètre
prédéfini ou une balance automatique). Une ligne « ✘ » dit une photo non mesurée (code 1).

**Relevé du 20 octobre 2026** (Lightroom Classic 15.6, `--eclairage` sur les 8 copies « Essai », à
leur propre balance ; la borne était alors absolue, C* < N autour du gris ; seuil mixte 8).
Vérité à l'œil : 53709912 (portrait dans une salle d'exposition : jour des fenêtres et éclairage
chaud) mixte ; 53709628 (intérieur, lampe), 53709579 (statue en plein jour), 53709786 (dune) et
53709534 (ciel) à une seule lumière ; 53709833 (groupe, intérieur, mur jaune) à une seule lumière
probable ; 53709724 (fête foraine de nuit) et 53709677 (scène) cas limites (lumières colorées).
Écart entre régions, « mixte » à 8 et plus :

| copie | C* < 12 | 15 | 20 | 25 | 30 |
| --- | --- | --- | --- | --- | --- |
| 53709912 | 9,8 mixte | 11,6 mixte | 9,3 mixte | 9,4 mixte | 9,4 mixte |
| 53709833 | 5,7 | 6,7 | 10,2 mixte | 11,0 mixte | 11,1 mixte |
| 53709786 | 2,2 | 2,9 | 3,4 | 3,4 | 3,4 |
| 53709724 | 5,7 | 8,0 mixte | 10,7 mixte | 11,5 mixte | 12,0 mixte |
| 53709628 | 7,1 | 12,6 mixte | 13,5 mixte | 13,8 mixte | 13,7 mixte |
| 53709534 | 5,5 | 5,7 | 6,5 | 9,0 mixte | 9,0 mixte |
| 53709579 | 4,8 | 12,5 mixte | 14,5 mixte | 14,1 mixte | 12,6 mixte |
| 53709677 | 5,5 (4 cases sur 9) | 4,9 | 9,5 mixte | 14,6 mixte | 17,7 mixte |

C* < 12 est la seule borne qui suit l'œil : seul le portrait ressort ; à 15 et au-delà, des objets
colorés pris pour des gris (ciel bleu, bouteille orange, plante, mur jaune) font de faux mixtes.
`chromaMax` (12) et `seuilMixte` (8) sont relevés là ; la mesure prenait 85 à 107 ms (version de
débogage). Sous une autre balance, la borne absolue ne tenait pas : à 3 200 K, le portrait n'avait
plus aucune case lue (0 sur 9), la dune 2 et la statue 0 ; à +30 en relatif, l'intérieur HEIC 0 ;
à 6 500 K, proche de la balance du portrait, le résultat tenait (9,7 contre 9,8). Une dominante
globale poussait tous les gris hors de la borne : d'où le centre au point neutre de l'image.

**Le centre et sa tolérance** (`toleranceNeutre`, provisoire), mesurés le 21 octobre 2026 hors de
Lightroom, sur cinq aperçus du relevé lus comme fichiers (53709912, 53709628, 53709724, 53709833,
53709579) : à la balance de la photo, le point neutre est à 3 à 11,2 du gris ; centré sur lui sans
tolérance, le portrait perdait son éclairage mixte (9,9 → 4,8) et l'intérieur à la lampe en gagnait
un (7,3 → 9,4) ; avec 10, les écarts du relevé restent à 0,1 près, et sous sept dominantes simulées
(gains en lumière linéaire), 38 lectures sur 40 gardent au moins 7 cases sur 9 (30 sur 40 autour du
gris seul). Aucun autre centre essayé (gris seul, point neutre sans tolérance, milieu des quartiles
ou des déciles, avec ou sans tolérance) ne tient mieux à la fois la balance de la photo et les
dominantes. Le critère d'un écart qui varie de moins de 25 % sous une autre balance n'est pas
atteint, quel que soit le centre : l'écart a*b* lui-même varie sous un gain en lumière linéaire,
même sur les mêmes pixels (portrait : 9,9 → 13,5 ou 3,2).

**Relevé du 21 octobre 2026** dans Lightroom Classic 15.6 (`--eclairage`, et `--essai` à 3 200 et
6 500 K pour les RAW, ±30 en relatif pour le JPEG et le HEIC ; borne 12 autour du centre, tolérance
10, seuil mixte 8) :

- à la balance de la photo : seul 53709912 est mixte (9,7 ; écart tonal 10,0), les 7 autres sous 8
  (2,1 à 7,1) ; 9 cases lues sur 9 partout, sauf la scène 53709677 (6 sur 9) : la vérité à l'œil
  est tenue ;
- à 6 500 K : 53709912 reste mixte (10,1), les autres RAW à une seule lumière ; 53709677 n'a plus
  qu'une case lue (forte dominante chaude sur une scène aux lumières colorées) ;
- à 3 200 K : 6 à 9 cases lues sur 9 (0 à 4 avant le centre au point neutre), mais 53709912 n'est
  plus mixte (4,6) ;
- ±30 en relatif : 53709534 (JPEG) reste à une seule lumière ; 53709628 (HEIC, intérieur à la
  lampe) aussi à −30, mais se lit mixte à +30 (11,4), sous la forte dominante chaude ajoutée.

La mesure prend 85 à 110 ms par photo (version de débogage). Elle suit donc l'œil à la balance de
la photo et sous une balance raisonnable ; sous une dominante forcée extrême, elle peut perdre une
lumière (le portrait à 3 200 K) ou en inventer une (l'intérieur à +30). La recette du même jour
(`--mixte 53709912`, par `view_photo`) le redit : éclairage mixte, écart 9,7, 9 cases lues sur 9,
visages dans les deux lumières, balance proposée Temperature 5558, Tint 15, mesure en 155 ms.
Limite connue (commentaire de `toleranceNeutre`) : une dominante qui rapproche du gris la lumière
majoritaire laisse le point neutre près du gris, et l'autre lumière sort de la borne. Le conseil le
dit déjà : « à confirmer à l'œil ». Seul le portrait est mixte parmi les copies d'essai : le seuil
repose sur lui. `toleranceNeutre`, `seuilTonal`, `partMinGroupe` et `pixelsMinPeau` restent
provisoires.

## Bilan d'une passe à l'autre (1.2)

`Bilan.swift` (fonctions pures) chiffre ce qui a bougé entre deux aperçus d'une même photo
(exposition en IL, contraste, écrêtage, dominante, saturation, netteté, bruit), « avant → après »,
puis ce qui demande l'attention : une `regression` (un défaut apparu ou aggravé depuis) ou un
changement `a_verifier` (peut-être voulu). Il fait la clé `bilan` de `view_photo` (aperçu entier, et
avant/après avec `compare`), `bilan_zone` d'un zoom refait sur la même zone, et le `bilan` d'une
proposition avec `compare`.

**Ce qui est gardé** (`ToolHandler`, pour la vie du processus du serveur, comme `dernierTri` ; les
appels passent un à un par `FileOutils`, sans verrou) : `vuesMesurees`, rangé par `Bilan.Cle`
(photo et taille d'aperçu demandée), le premier `view_photo` de la session sur l'aperçu entier
(`depart`) et le dernier (`precedente`) : mesures, détail, tons neutres choisis
(`Measurements.neutres`, avec leur masque), empreintes du cadre et de l'état, étapes de Claude,
calcul IA en attente (`a_savoir`), empreinte de `corrections_utilisateur`, `GrainAmount` ; 30 au
plus (`Bilan.photosGardees`, la plus ancienne part). `zoomsMesures` : 6 zooms par photo
(`zoomsGardes`), 30 photos au plus. Un autre fichier sous le même identifiant (un autre catalogue)
repart de zéro. La vue se construit sur la réponse brute du module (`Bilan.Vue(apercu:…)`), avant le
retrait de la géométrie et le regroupement des réglages, et avant le carré du point de mise au
point. La mémoire est celle du processus : chaque `--call` est un nouveau processus, et son
`view_photo` est toujours le premier (« Premier view_photo de cette photo dans cette session »).

**Empreintes.** `Bilan.cadre` : la géométrie de la photo (dimensions affichées, orientation, cadre),
l'angle de recadrage, et les réglages qui déforment (`Perspective*`, `LensProfileEnable`,
`LensProfileDistortionScale`, `LensManualDistortionAmount`). `Bilan.etat` : les réglages, le profil
et son intensité (ni masques ni taches, que les étapes disent). Les étapes viennent du module
(`etapes_claude` de `apercu` avec `point_af` : `nombre` et `derniere`, lus dans `etapesClaude`) :
nil avec un module d'avant la 1.2. Le serveur les retire de la réponse à Claude : le bilan les dit.

**Ne se comparent que des mesures prises de même** : deux vues de même taille d'aperçu (une autre
taille repart de zéro et le dit : « Premier view_photo de cette photo à N px… le bilan ne compare
que des aperçus de même taille ») ; les tons neutres suivis (la dominante sur les mêmes pixels : le
masque de la vue d'avant appliqué à la nouvelle, comme pour `match_series`) qu'à cadre égal ;
netteté et bruit qu'à taille et cadre égaux. Les deux images d'un avant/après (`view_photo` avec
`compare`) se comparent entre elles, sans toucher aux vues gardées ; une proposition
(`preview_settings`, ou `add_mask` et `retouch_spots` avec `preview`, et `compare`) à l'état actuel
rendu par la même commande, jamais à une vue gardée, et sans netteté ni bruit (une proposition n'en
a pas) ; une proposition sans `compare` n'a pas de bilan. Un zoom ne touche pas aux vues entières.

**Écarts** (`ecarts`, chacun `avant`, `apres`, `ecart`), listés au-dessus de leur seuil de
visibilité, sinon nommés dans `sans_ecart_visible` :

- `exposition` (L* médiane, et `IL` d'après le rapport des luminances médianes,
  `Measurements.ecartIL`) : 0,1 IL (`ToolHandler.seuilExposition`, repris de `match_series`) ;
- `contraste` (p95 − p5, avec `p5` et `p95`) : 4 (`seuilContraste`) ;
- `hautes_lumieres_pct`, `blanc_pur_pct`, `ombres_bouchees_pct`, `canal_ecrete` (le canal qui bouge
  le plus) : 0,3 point (`Bilan.ecartEcretage`) ;
- `dominante_a`, `dominante_b` (avec `suivie`) : 1,5 (`seuilDominante`) ; pas comparées sous 3 % de
  tons neutres (une remarque le dit) ;
- `chroma_moyenne` : 3 (`Measurements.seuilChroma`) ; `tres_saturee_pct` : 1 point
  (`ecartSaturee`) ;
- `nettete_max` (avec sa lecture : floue, douce, nette) : 10 % de l'avant (`ecartNettetePct`) ;
  `bruit` (le plus fort des aplats et des ombres, avec sa lecture : faible, visible, fort) : 0,1
  (`ecartBruit`).

**Régressions** (`regression`, un texte par défaut, rangés par genre, `Bilan.Defaut`) :

- hautes lumières écrêtées, canal écrêté (« couleur poussée hors du sRGB ou brûlée »), couleurs
  très saturées (C* > 60) : au moins 2 points de plus et au moins 1,5 fois l'avant
  (`regressionEcretage`, `regressionCanal`, `regressionSaturees`) ; le canal n'est pas redit sous
  une régression de l'écrêtage ;
- ombres bouchées : au moins 2 points de plus (`regressionOmbres`) ; une nuit n'alerte pas d'elle-
  même, le seuil porte sur l'écart ;
- « dominante accentuée sur (les mêmes) tons neutres » : |a*| ou |b*| qui s'éloigne de 0 d'au
  moins 2 (`regressionDominante`) ; elle n'est pas redite en « correction dépassée » ;
- netteté passée de nette à douce, ou de douce à floue (seuils 35 et 15), avec une baisse d'au
  moins 3 (`baisseNetteteMin`) ; bruit passé de faible à visible, ou de visible à fort (0,6 et 1,5),
  avec une hausse d'au moins 0,1 (`hausseBruitMin`).

Une marge d'arrondi (1e-9) évite qu'un écart pile au seuil le rate (en binaire, 2,4 − 0,4 vaut
1,999…).

**À vérifier** (`a_verifier`), plutôt qu'une régression :

- une dominante qui change de sens, nette des deux côtés (2 au moins, `dominanteLegere`) :
  « correction dépassée ? » ;
- cadre changé, et un blanc pur qui explique au moins 80 % de la hausse de l'écrêtage
  (`partBlancPurCoins`) : « coins vides possibles (Upright, perspective) » ;
- netteté en baisse avec un bruit en baisse d'au moins 30 % (`baisseBruitDebruitage`) : le
  débruitage retire aussi du grain que la mesure comptait comme détail ; juger par un zoom ;
- bruit en hausse avec un grain ajouté (`GrainAmount` en hausse) : voulu ?
- toute régression qui suit une annulation (`etapes_claude` en baisse : « revenu après
  l'annulation : … ») ou un rendu aux calculs IA en attente (« calcul IA en attente sur l'un des
  rendus : … ») ;
- un aller-retour d'une passe à l'autre (exposition, contraste, dominante b*, deux écarts visibles
  de signes opposés : « des réglages empilés font dériver la photo »), sauf après une annulation,
  qui défait la passe d'avant à dessein. La dominante b* se lit sur les tons suivis quand le cadre
  n'a pas changé depuis le départ : l'écart de la passe précédente est alors l'écart depuis le
  départ moins celui depuis la précédente.

**Le reste du bilan d'une vue** : `depuis` (« le view_photo précédent de cette photo à N px, il y a
… ») ; `etapes_claude` (« 1 de plus (dernière : « … ») », « 1 de moins : retouche défaite (undo_last
ou revert_to_original) », « nouvelles » quand l'historique de 20 étapes est plein, « aucune
nouvelle ») ; `corrections_utilisateur` (« l'utilisateur a aussi retouché à la main : un écart peut
venir de lui »), seulement si ces corrections sont nouvelles ou ont changé depuis la vue précédente
(le module les redonne à chaque aperçu jusqu'à la commande suivante de Claude) ; `meme_etat`, seul
avec `depuis`, les étapes et les corrections, quand l'état, le cadre et les étapes sont identiques
et que rien n'est listé ; `depuis_le_debut` (les écarts depuis le premier `view_photo` de la session
à cette taille, et ses régressions qui ne sont pas déjà dites, par genre : une dérive lente, faite
de petites passes) ; `remarques` (taille différente, cadre changé, image changée sans réglage :
masque, tache, retouche à la main ou calcul IA fini) ; `conseil`, seulement avec une régression
(« se corrige par une passe ciblée sur ce seul défaut, ou se défait par undo_last si la dernière
étape en est la cause ; la dire à l'utilisateur si elle reste ») ; `base`. Le premier `view_photo`
d'une photo ne donne que « point de départ du bilan des suivants ».

**Avant/après et propositions** (`Bilan.avantApres`) : la même forme, sans étapes ni aller-retour ;
tons neutres non suivis (l'image d'avant peut avoir un autre cadre) ; `cadreChange` quand les deux
images n'ont pas les mêmes dimensions (recadrage, Upright, rotation) : ni netteté ni bruit, une
remarque le dit, et un blanc pur en hausse est à vérifier. `conseil` d'un avant/après : « Une
« regression » restée se dit dans le résumé. » ; d'une proposition : « Une « regression » se corrige
dans la proposition avant de l'appliquer. »

**Zoom refait sur la même zone** (`bilan_zone`) : la même zone à 0,002 près (`toleranceZone`), du
même cadre, aux mêmes pixels, comparée au dernier zoom de cette zone : les chiffres bruts
(luminosité, écrêtage, netteté et bruit avec leur écart en %, utile après un débruitage), sans
alerte : les seuils de lecture ne valent pas à 100 %.

**Résultat gardé par `FileOutils`** : une vue répondue après la limite de 50 s, puis redemandée aux
mêmes arguments, n'est mesurée et gardée qu'une fois.

**Constaté le 20 octobre 2026** (Lightroom Classic 15.6, les 8 copies « Essai », propositions et
lectures seulement) :

- plancher : deux `view_photo` de suite à 1 344 px donnent les mêmes 43 mesures (écart 0) : toute
  différence entre deux vues de même taille est réelle. Le même état à 1 024, 1 344 et 2 048 px
  (53709786) : L* jusqu'à 0,4 ; tons neutres, b* 0,2 et part 2,1 points ; bruit des ombres 0,27 ;
  netteté jusqu'à 10 % (50,1, 44,9 et 45,6) : d'où la mémoire par taille d'aperçu ;
- proposition contre vue : `preview_settings` sans changement (relatif, Exposure2012 + 0) contre
  `view_photo`, même taille : L* médiane +0,2, p95 +0,3, hautes lumières +0,2 à +0,9 point
  (53709677 : 1,8 → 2,7), ombres bouchées +0,3, a* +0,2, b* −0,2 : d'où « jamais une proposition à
  une vue gardée ». Une part de cet écart venait du serveur (deux chemins de mesure, unifiés depuis :
  voir Mesures) ; le reste est à remesurer ;
- seuils de régression, en propositions, par rapport à une vue (le plancher ci-dessus à retrancher) :
  hautes lumières, Exposure +0,3 : +0,3, +0,3 et +2,5 points ; +0,7 : +0,5 et +10 ; +1,5 : +1, +3,6
  et +19,4 ; Whites +30 : +0,6 et +3,5 ; Whites +60 : +46,9, +7,5 et +11,5 ; le canal le plus écrêté
  suit les hautes lumières. Ombres bouchées : Blacks −30 sur la nuit 53709724, 0,7 → 12,5 ; −60,
  24,1 ; Contrast +40, 0,7 → 3,9 ; Blacks −60 sur 53709628, 0 → 1,6. Très saturées : Saturation +30,
  3 → 5,9 et 1,2 → 2,4 ; Vibrance +40, 3 → 4,2 et 1,2 → 1,7. Dominante : Tint ±15 sur le portrait,
  a* +3,1 et −2,9 ; Temperature ±600 K, a* +1 et −1,6, b* −0,4 et −3,1 (sur le HEIC 53709628, la
  Temperature est relative : lignes écartées). Médiane L* : Exposure +0,3 donne +6 à +7, un
  changement voulu, chiffré sans alerte. D'où 2 points et 1,5 fois l'avant (écrêtage, canal,
  saturées), 2 points (ombres), 2 (dominante) : relevés en propositions, provisoires comme le dit
  le relevé, à revoir d'une vue à l'autre.

Le 21 octobre 2026, l'étape « bilan chiffré » de la recette (53709912, deux vues de 1 024 px) :
deux vues de suite en `meme_etat`, sans `corrections_utilisateur` ; la vue qui suit une proposition
sans `compare` ne la compare pas ; après Exposure +2 IL et Whites +50 écrits, +2,45 IL, les
régressions « hautes lumières écrêtées : 0,0 → 6,5 % (+6,4 points) » et « bruit passé de visible à
fort : 0,70 → 1,65 (seuil 1,5) », « 1 de plus » ; après `undo_last`, « 1 de moins », sans
`regression` (voir Recette dans Lightroom). Les étapes de Claude lues par le module, et
l'empreinte des retouches à la main, tiennent donc dans Lightroom.

Netteté et bruit ne se mesurent pas en proposition : leurs seuils (`baisseNetteteMin`,
`hausseBruitMin`, `baisseBruitDebruitage`, `ecartNettetePct`, `ecartBruit`), `partBlancPurCoins`
et `toleranceZone` restent provisoires, à relever par deux vues (avant et après une étape écrite
puis défaite : l'étape « bilan chiffré » de la recette, dont une seule passe forte, +2 IL, ne fixe
pas encore ces seuils). `ecartEcretage` (0,3 point) et `ecartSaturee` (1 point) sont au-dessus du
plancher nul de deux vues de même taille, mais leur valeur reste provisoire elle aussi.

## Écran (1.2)

Claude mesure la photo par ses chiffres, sans passer par l'écran ; l'utilisateur la juge sur le
sien. `Ecran.swift` dit quel est cet écran et si son profil de couleur vient d'une sonde
d'étalonnage. Serveur seulement : macOS seul connaît l'écran, et la fenêtre Claude le demande au
connecteur (voir Fenêtre Claude › Voyants et liaison).

**Lecture** (`Ecran.lire`), par CoreGraphics et ColorSync, sans AppKit et sans aucune permission
(environ 44 ms, relevé le 20 octobre 2026) : `CGGetActiveDisplayList` (copies miroir écartées),
`CGMainDisplayID` (l'écran de la barre des menus d'abord, `principal`, puis les `autres`), le nom
que ColorSync donne à l'écran (`ColorSyncDeviceCopyDeviceInfo`), le profil actif
(`ColorSyncProfileCreateWithDisplayID`, son fichier par `ColorSyncProfileGetURL`), les profils
d'usine et personnalisés de l'écran (`FactoryProfiles`, `CustomProfiles`). L'en-tête ICC se lit
dans les octets du profil, en gros-boutiste (CMM aux octets 4 à 7, date de 24 à 29, « acsp » de 36
à 39, créateur de 80 à 83 ; un profil de moins de 132 octets ou sans « acsp » n'est pas lu), jamais
par `ColorSyncProfileCopyHeader`. Origine (`Ecran.origine`) : usine si le profil est l'un des
profils d'usine de l'écran, ou rangé sous `/Library/ColorSync/Profiles/Displays/` ; personnalisé
s'il est l'un de ses `CustomProfiles` ; inconnue sinon.

**Classes** (`Ecran.Etalonnage`, `Ecran.classer`, dans cet ordre) : `usine` (origine usine : jamais
mesuré) ; `standard` (un profil du système, sous `/System/`) ; `sonde` (un logiciel de sonde nommé
dans le profil, `Ecran.logicielsDeSonde` : DisplayCAL, ArgyllCMS, i1Profiler, Calibrite, X-Rite,
ColorMunki, Datacolor Spyder, basICColor, ColorNavigator, Palette Master, Calibration Studio,
Calman) ; pour un créateur Apple, `oeil` avec la balise `vcgt` (l'assistant d'étalonnage d'Apple),
`standard` sans elle ; `sonde` encore pour `vcgt` d'un autre créateur ; `personnalise` pour le
reste ; `inconnu` sans profil lisible. `mesure` vaut vrai pour `sonde` seulement, faux pour
`usine`, `standard` et `oeil`, null pour `personnalise` et `inconnu` : dans le doute, « étalonné ? »
plutôt qu'« étalonné ». La balise `meas` n'est pas un indice.

**JSON** (`Ecran.json`) : `principal` et `autres`, chacun `nom`, `integre`, `gamut_large`, `profil`
(son nom, ou null), `etalonnage`, `mesure` (vrai, faux ou null), `date_profil` (AAAA-MM-JJ, jamais
pour un profil d'usine), `logiciel`, `texte` (« Odyssey G85SD · profil d'usine, non mesuré sur ce
Mac ») ; avec `detail` (fenêtre Claude et `--ecran` seulement), le chemin de chaque profil et le
texte de la boîte « Claude · écran » (`Ecran.detail` : l'écran, son profil, et pour juger les
couleurs, une sonde et « coupez Night Shift (et True Tone sur un écran Apple) » ; les Réglages
nommés comme le Mac les nomme, `Ecran.reglageProfil` : « Réglages système › Écrans › Profil de
couleur » en fr-CA, « Réglages Système › Moniteurs › Profil de couleur » sinon). Le chemin d'un
profil ne va jamais à Claude (il peut nommer le dossier personnel).

**Au connecteur** : `get_status` ajoute `ecran` (sans chemin ni détail), et sa description dit
quoi en faire. `ToolHandler.lireEcran` ne lit aucun écran par défaut (les tests) ; `main.swift` pose
`Ecran.lire` pour le serveur et `--call`. La remarque de l'écran (`Ecran.remarque`, nil pour un écran
mesuré par une sonde : « Écran principal de l'utilisateur : …, … Les mesures de view_photo n'en
dépendent pas, son œil si : quand son avis compte (peau, couleurs), lui dire en une phrase que son
écran n'est pas étalonné », ou « lui demander si son écran est étalonné » pour `mesure` inconnue)
part une fois par processus du serveur, au premier `view_photo`, `preview_settings` ou
`compare_variants` réussi, dans un bloc de texte à part (le JSON du résultat reste lisible tel
quel) ; rien si `get_status` a déjà dit l'écran. C'est elle qui porte la consigne : les consignes
du connecteur n'ont plus de place. `mcp-developpeur --ecran` écrit une ligne JSON
(`Ecran.json(…, detail: true)`), ou `{"lu": false}` sans écran, avec le code 0 : la fenêtre ne lit
que cela. `mcp-developpeur --status` dit l'écran principal et les autres (ou « aucun écran lu »)
avant la liaison.

**Constaté le 20 octobre 2026** (Mac de Dany, macOS 27, un seul écran, Odyssey G85SD en HDMI) :
`ColorSyncProfileCopyHeader` rend les signatures de l'en-tête à l'envers (« lppa » pour
« appl ») ; le profil d'usine de l'écran, tiré de son EDID, est rangé dans
`/Library/ColorSync/Profiles/Displays/` (créateur « appl », sans balise `vcgt`) et refait par macOS
à chaque branchement (la date de son en-tête est celle du branchement : elle n'est jamais dite) ;
`FactoryProfiles` est un dictionnaire de dictionnaires portant chacun `DeviceProfileURL` (des NSURL),
plus `DeviceDefaultProfileID`, un texte ; un mode peut viser un profil du système (« HDMI SD » :
`/System/Library/CoreServices/Resources/Profiles/SD 170M-A.icc`) et rester usine ;
`sRGB Profile.icc` du système porte une balise `meas`. L'écran se lit « Odyssey G85SD · profil
d'usine, non mesuré sur ce Mac », classe `usine`. Les libellés des Réglages sont relevés dans
`DisplaysExt.appex` et Réglages Système (le Mac de Dany est en fr-CA). Aucun vrai profil de sonde
n'a été relevé : l'indice reste la balise `vcgt` d'un autre créateur qu'Apple, ou le nom d'un
logiciel. Le 21 octobre 2026, l'étape « écran nommé (get_status) » de la recette (dans le processus
de la recette, pas lancé par Lightroom) dit la même chose, sans chemin de profil ; `--ecran` lancé
par Lightroom pour le voyant reste à voir.

**Tests.** `EcranTests` fabrique ses profils (en-tête lu dans les octets, `meas`, `vcgt` avec un
autre créateur, texte de DisplayCAL, `vcgt` d'Apple, textes UTF-16) et vérifie `get_status` et la
remarque une fois ; `swift test` ne lit jamais le vrai écran : `testLectureReelleSansPlantage` est
sauté sauf avec `DEVELOPPEUR_ECRAN_REEL=1`. Les essais de la fenêtre passent par un faux connecteur
(`S.home/connecteur-ecran`) et un faux connecteur d'avant la 1.2.

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
sur un RAF de X-H2S) : le serveur la lit lui-même, en lecture seule, comme le module Focus Points
la lit par exiftool (`PointAF.swift` jusqu'à la 1.1.1 ; depuis la 1.2, `LectureBoitier` de
`Boitier.swift`, qui lit aussi l'intention de la prise de vue d'une même ouverture : voir Lecture
du boîtier). RAF : « FUJIFILMCCD-RAW », position du JPEG incorporé à
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
vignette, ou `.RAF`), et la lecture est bornée à 2 s (`LecteurBoitier`) : un original qui ne s'ouvre
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
(`Vignettes.decrireVignette` : `chemin_original`, `marque`, `geometrie`, `sensibilite` depuis la
1.3.1), et ajoute `point_af_toujours` (préférence `pointMiseAuPoint`) et `evaluation` (`Notation.resume`, lue dans
`notation.json` : « pas encore évaluée », « 3 ★ proposée par Claude, à vérifier »,
« acceptée par l'utilisateur : 3 ★ », « changée par l'utilisateur : 4 ★ (proposée : 3 ★) »,
« proposition écartée par l'utilisateur (3 ★) » ; « rejet » à la place des étoiles pour un
rejet). Le serveur retire `chemin_original`, `geometrie`, `marque` et `sensibilite` de la description, et
`point_af_toujours`, avant de répondre à Claude. Un point dans l'image affichée donne `point_af` :
`x` et `y` (de 0 à 1 depuis le coin haut gauche, au millième), `nettete` (autour du point, dans
le carré de 12 % de `Detail.nettete`, sans le facteur des vignettes), `appareil` (« mise au point
signalée manquée » si l'appareil l'a signalé) et `carre` s'il est dessiné. Le carré
(`PreviewImages.marquerPoint`) : vert, rouge pour une mise au point signalée manquée, côté de 6 %
du petit côté (16 px au moins), un liseré sombre autour pour rester visible sur un fond clair ; il
est dessiné avec le paramètre `af_point = true` (pour noter : consignes de la fenêtre) ou quand
la case « Mise au point » du Gestionnaire est cochée (`pointMiseAuPoint`, décochée par défaut).
Mesures et Vision sont prises avant le carré. `view_photo` a un seul lecteur
(`ToolHandler.lecteurBoitier`) : une lecture bloquée n'en lance pas d'autres. Un point hors du
cadre (recadrage) n'est pas donné. Depuis la 1.2, une seule ouverture de l'original sert au point
et à l'intention (`intention_boitier`, aperçu entier seulement), aucune pour un avant/après ;
`view_photo` ouvre l'original d'un fichier Fujifilm même sans géométrie, puisque l'intention n'en a
pas besoin (le module envoie toujours la géométrie avec `point_af = true`), alors que le tri, sans
géométrie, ne l'ouvre pas.

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
orientation, cadre) ; le connecteur lit le point en temps borné (`LecteurBoitier`, 2 s), le passe
dans l'image affichée et recadrée (`GeometriePhoto.versApercu`), dessine le carré sur la vignette
(`PreviewImages.marquerPoint`, vert ou rouge) et l'écrit dans `<sortie.jpg>`, puis écrit sur sa
sortie une ligne JSON (`x`, `y`, `avertissement`). Code 1 sans point (pas un fichier Fujifilm,
point illisible ou hors du cadre, original qui ne s'ouvre pas à temps), 2 pour des arguments
illisibles. Il ne passe pas par la liaison : c'est un processus à part, lancé par Lightroom.

**Tri** (`cull_photos`, `Tri.swift`). Photos visées : `photo_ids`, la sélection, une collection ou un
dossier (par `chercher`, triées par date), 500 au plus, par lots de 25 vignettes (une commande à la
fois vers le module) ; progression et annulation entre deux lots (voir Délai des appels d'outils).
Sans aucun des quatre, la photo active (commande `etat`, 1.3.1 : dans la fenêtre Claude, la note
d'abord de la photo active l'oubliait 2 fois sur 4) ; sans photo active, le refus « Photos à
traiter ». `contact_sheet` garde ce refus : une planche d'une seule photo ne montre pas de série.
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

**Texture au point de mise au point (1.3).** Constaté le 21 octobre 2026 (mesures de la 1.3, vues
de 1 344 px des huit copies d'Essais) : deux fausses « mise au point manquée », au tri comme au
carnet, le point posé sur du sable lisse (netteté 12,6, la voiture et la dune nettes) et sur un
nuage (6,6, toute la scène nette) : une zone sans texture paraît floue. `Detail.autour` mesure
dans le carré de la netteté une texture (75e centile de l'écart entre blocs voisins de 8 × 8 px,
à 1 024 px). Sous `DetailMeasurements.textureMin` (18 : le sable à 11,2 et 11,6, mesuré le carré
vert du point AF effacé), la mise au point est « non jugée » (`PhotoTriee.MiseAuPoint.jugeable`) :
pas de « manquée », pas de plafond, et le carnet ne la cherche pas, sauf si l'appareil l'a
signalée (la zone la plus nette la confirme alors). De 18 à `textureDouteuse` (30 : le bord du
nuage à 23,6 et 24,1, autant qu'un petit visage flou, 21,3 à 27,2), une mise au point manquée n'est
qu'un doute (`douteuse`) : `Notation.plafond` donne 2, à vérifier par un zoom à 100 %, sans rejet
proposé, et le carnet ne la compte pas. Les sujets nets relevés vont de 28,4 à 64,6 (un petit
visage net de 25,8 à 28,4). `view_photo` (`point_af.mise_au_point`) et `cull_photos` (`point_af`,
`pourquoi`) disent « non jugée : zone sans texture autour du point » ou « à vérifier : texture
faible autour du point » ; `--constats` a sa colonne texture. Seuils choisis sur ces seuls
relevés : à relever sur un ciel uni, un mur, de la neige et une vraie mise au point manquée.

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
  sinon pas de plafond, 5 (depuis le correctif 1.3.2 ; jusqu'à la 1.3.1, 4, 5 étant à l'utilisateur
  seul). Le plus bas l'emporte, raisons jointes ; une vignette
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

## Lecture du boîtier (1.2)

Ce que l'appareil a rangé dans un fichier Fujifilm (RAF, ou JPEG de l'appareil) se lit d'une seule
ouverture de l'original (`Boitier.swift`) : le point de mise au point (`PointAF`, voir Tri d'une
séance) et l'intention de la prise de vue (`IntentionBoitier.swift`), les réglages choisis sur
l'appareil. Rien n'est posé d'office : `view_photo` les donne à Claude, avec ce qu'il en tire.

**Lecture** (`LectureBoitier.lire`, en lecture seule) : un RAF (en-tête « FUJIFILMCCD-RAW », position
du JPEG incorporé à l'octet 84, grand-boutiste) ou un JPEG (FF D8), dont 128 Ko sont lus
(`tailleLue`) ; le segment APP1 « Exif », IFD0, l'IFD Exif (0x8769), la MakerNote (0x927C) qui
commence par « FUJIFILM », puis l'IFD de Fujifilm (petit-boutiste, positions depuis le début de la
MakerNote). Le point et l'intention se lisent l'un sans l'autre : un point (0, 0) n'empêche plus de
lire l'intention, et une MakerNote coupée rend encore ce que l'Exif donne (compensation, mode). Un
HEIF de l'appareil (ni RAF ni FF D8) n'est pas lu. La lecture TIFF (`LectureBoitier.Tiff`) connaît
la taille des douze types ; `entiers` lit sans signe (le motif des bits), `signes` relit en signé
selon la largeur, `signe32` lit 4 octets en int32s comme exiftool, quel que soit le type rangé
(sans lui, ShadowTone −16 rangé en LONG se lirait 4294967280) ; `rationnel` lit un RATIONAL ou un
SRATIONAL, signé à la demande (comme exiftool pour la compensation). Un réglage d'un type inattendu
(texte, octets indéfinis : `IntentionBoitier.entier` ne lit que les types 1, 3, 4, 6, 8 et 9) ou
hors de ce que l'appareil peut ranger est ignoré, sans planter.

**Lecteur borné** (`LecteurBoitier`, qui remplace `LecteurPointsAF` depuis la 1.2, même délai de
2 s) :
un original qui ne s'ouvre pas à temps est sauté, et les suivants aussi tant que sa lecture n'a pas
fini (une demande d'autorisation de macOS pour le volume, constaté en 2.3 : voir Tri d'une séance) ;
quand elle finit, la lecture reprend. Fujifilm seulement (`marque`, ou un `.RAF`) : l'original
d'une autre marque n'est pas ouvert. `view_photo` a son lecteur (`ToolHandler.lecteurBoitier`),
`cull_photos` le sien par série, `--marquer-af` et `--boitier` le leur.

**Tags lus** (noms et valeurs d'ExifTool, `Image/ExifTool/FujiFilm.pm`) :

| Tag | Nom | Lu comme |
| --- | --- | --- |
| 0x1401 | FilmMode | la simulation en couleur : 0x000 PROVIA/Standard, 0x120 ASTIA/Soft, 0x200 et 0x400 Velvia/Vivid, 0x500 PRO Neg. Std, 0x501 PRO Neg. Hi, 0x600 CLASSIC CHROME, 0x700 ETERNA/Cinema, 0x800 CLASSIC Neg., 0x900 ETERNA Bleach Bypass, 0xa00 NOSTALGIC Neg., 0xb00 REALA ACE ; Studio Portrait des anciens compacts (0x100, 0x110, 0x130, 0x300), sans profil |
| 0x1003 | Saturation | le réglage Couleur d'une simulation en couleur (−4 à +4 ; 0x8000 : celui de la simulation), ou la simulation noir et blanc : MONOCHROME (0x300, filtres rouge, jaune, vert 0x301 à 0x303), Sépia (0x310), ACROS (0x500, filtres 0x501 à 0x503), qui l'emporte sur FilmMode |
| 0x1402 | DynamicRangeSetting | 0 auto (plage dans 0x140b), 1 réglée (dans 0x1403) ; 0x100, 0x200, 0x201 : DR100, 230 et 400 des anciens boîtiers ; hors de DR100 à DR800, ignorée |
| 0x1403 | DevelopmentDynamicRange | la plage réglée (100, 200, 400) |
| 0x140b | AutoDynamicRange | la plage choisie en auto |
| 0x1443 à 0x1445 | DRangePriority, DRangePriorityAuto, DRangePriorityFixed | priorité à la plage dynamique : 0 auto, 1 fixe ; en auto, 1 faible, 2 forte, 3 plus ; fixe, 1 faible, 2 forte ; retenue seulement si son niveau est lu |
| 0x1041, 0x1040 | HighlightTone, ShadowTone | tons clairs et foncés, en int32s : cran = −valeur/16, de −2 (plus doux) à +4 (plus durs), par demi-cran |
| 0x1002 | WhiteBalance | 0x1 Auto, priorité au blanc ; 0x2 Auto, priorité à l'ambiance |
| 0x1031 | PictureMode | 0x5, 0x17, 0x18 : modes de nuit choisis (scène de nuit, nuit sur trépied, basse lumière) |
| 0x1425 | SceneRecognition | 0x300, 0x103 : scène de nuit, portrait de nuit, reconnus par l'appareil |
| Exif 0x9204 | ExposureCompensation | la compensation en IL, rationnel signé même rangé en RATIONAL, ±10 IL au plus |
| Exif 0x8822 | ExposureProgram | 1 manuel, 2 programme, 3 priorité à l'ouverture, 4 priorité à la vitesse |

**Profil de Lightroom** (pour un RAW, `IntentionBoitier.profilLightroom`, appelée par
`ToolHandler.profilDuBoitier` avec la marque et le modèle de l'aperçu) : le profil DCP du catalogue
(`DevelopCatalogue.profiles`), sauf sur un modèle où Lightroom le rend comme Adobe Standard
(`missingOn`, modèle comparé sans la casse) ; sinon le profil à base de Look installé pour cet
appareil (`Camera CLASSIC Neg`, `Camera BLEACH BYPASS`, `Camera NOSTALGIC Neg`, `Camera Sepia`,
relevés en lecture seule dans le dossier des profils de Lightroom Classic 15.6, Camera/Fujifilm/
Fujifilm X-H2S ; le X-T4 n'y a pas NOSTALGIC Neg., le X-T20 aucun Look) ; sinon aucun.

**Dans `view_photo`** (`intention_boitier`, sur l'aperçu entier seulement : ni zoom ni avant/après) :
`simulation`, `profil` (RAW, s'il est trouvé), `couleur` (non nulle), `plage_dynamique`
(« DR200 (auto) », « DR100 (réglée) »), `priorite_plage_dynamique` (« forte (auto) », « faible »),
`tons_clairs` et `tons_fonces` (crans non nuls), `compensation` (IL au centième, non nulle), `mode`,
`balance`, `scene` (« nuit »), et `lecture`, les phrases qui s'appliquent
(`IntentionBoitier.lecture`) :

- compensation de −2/3 IL et au-delà (`seuilSombreVoulue`, −0,6) : photo voulue plus sombre que
  la mesure de l'appareil, garder sa luminosité d'ensemble, ne pas remonter Exposure2012 vers une
  moyenne ; +2/3 et au-delà (`seuilClaireVoulue`, +0,6) : voulue plus claire ; ±1/3 ne dit rien ;
  en mode manuel sans compensation : sa luminosité est un choix, juger l'intention d'après la
  scène ;
- scène de nuit (mode choisi ou reconnu par l'appareil) : une vraie nuit reste sombre ;
- pour un RAW : le profil actuel est déjà la simulation (le garder, sauf autre style demandé), ou
  partir du profil de la simulation en première passe, sauf autre style demandé ou guide de style
  contraire, et le dire ; sans profil pour cet appareil, s'en approcher par les réglages seulement
  sur demande ; à DR200 et plus, hautes lumières protégées à la prise de vue (RAW exposé de
  log2(DR/100) IL plus bas) : les tenir, remonter l'exposition en gardant les hautes lumières, les
  ombres relevées seront plus bruitées ; avec une compensation sombre en plus, « ne rattraper que
  cette protection » ; tons choisis au boîtier : Lightroom ne les applique pas à un RAW, s'en
  inspirer sans les imposer ;
- pour un JPEG de l'appareil : la simulation, la plage dynamique et les tons y sont déjà
  appliqués, ne pas les refaire ;
- balance « priorité à l'ambiance » : la chaleur des lampes était voulue ; « priorité au blanc » :
  un blanc neutre était voulu ;
- priorité à la plage dynamique : contraste réduit au boîtier, ne pas le rendre d'office.

Le module ne change pas : il donne déjà `chemin_original`, `marque` et `geometrie` avec `point_af`.
La description de `view_photo`, la première consigne de profil du connecteur et les invites le
reprennent (voir Consignes et invites) ; un RAW n'en reçoit que la simulation, par le profil, en
proposition de première passe.

**`mcp-developpeur --boitier <original>`** (`Recette.lectureBoitier`) : la même lecture, sans
Lightroom (le point dans le fichier entier, `intention_boitier` comme `view_photo` la donne, RAW
d'après l'extension `.raf`, le modèle non lu : un Look réservé à un modèle n'est pas trouvé), et
`valeurs_lues` sous les noms et numéros d'exiftool (« FilmMode (0x1401) »…), une ligne JSON ; code 1
si rien n'est lu. Pour comparer à exiftool, dans le Terminal de Dany (l'accès au volume lui est
déjà donné).

**Constaté le 20 octobre 2026** (Lightroom Classic 15.6, `view_photo` sur de vrais RAF des copies
d'essai) : 53709912 (X-H2S, DSCF2402) manuel, PROVIA/Standard, DR100 réglée ; 53709724 (X-H2S)
priorité à la vitesse, PROVIA, DR100 ; 53709579 (X-T20) programme, PROVIA, DR200 auto, couleur +2,
tons clairs et foncés +1 ; 53709677 (X-T4) manuel, PROVIA, DR100. Recoupé hors du code du serveur
(MakerNote lue à la main, Exif par ImageIO) : FilmMode 0 (PROVIA), DynamicRangeSetting 1 et
DevelopmentDynamicRange 100 (DSCF2402) ; DynamicRangeSetting 0 et AutoDynamicRange 200, Saturation
0x100 (+2), ShadowTone et HighlightTone −16 rangés en SLONG (type 9) (X-T20) ; ExposureProgram 1 et
2. Tout concorde ; la MakerNote des trois boîtiers tient dans les 128 Ko lus. Le 21 octobre 2026,
l'étape « intention lue au boîtier » de la recette, photo inchangée et chemin de l'original absent
de la réponse : 53709912, PROVIA/Standard, profil Camera PROVIA/Standard, DR100 (réglée), manuel,
2 phrases de lecture ; 53709579 (X-T20), le même profil, DR200 (auto), couleur +2, tons clairs et
foncés +1, programme, 3 phrases. Ce qui reste à relever (noir et blanc, priorité à la plage
dynamique, forme de la compensation, ce que Lightroom fait d'un RAF à DR200 et plus, les seuils de
±0,6 IL) est dans À constater dans Lightroom (1.2).

## Onglet Focus (demandé par Dany le 22 octobre 2026)

Dany emploie le module Focus-Points (v4 PRE 4, installé ; Apache 2.0) pour voir où l'appareil a
fait la mise au point. L'onglet Focus de la fenêtre Claude, entre Aperçu et Proposition (clé
`focus`, `D.ongletFocus`), montre la photo active de même, avec les sections Image Information,
Shooting Information et Focus Information de Focus-Points, en français.

**Lecture du boîtier** (`Focus.swift`, `MiseAuPointBoitier`, lue par `LectureBoitier` de la même
ouverture que le point et l'intention ; `LectureBoitier.miseAuPoint`). Les étiquettes sont celles
qu'ExifTool nomme (`Image/ExifTool/FujiFilm.pm`, livré avec Focus-Points) et que
`FujifilmDelegates.lua` de Focus-Points lit par exiftool ; Développeur les lit lui-même, sans
exiftool :

| Tag | Nom | Lu comme |
| --- | --- | --- |
| 0x1021 | FocusMode | 0 auto, 1 manuel, 65535 vidéo (sans FocusSettings) |
| 0x1022 | AFMode | 0 aucun, 1 point unique, 256 zone, 512 large / suivi (sans FocusSettings) |
| 0x1023 | FocusPixel | x y dans le repère du JPEG incorporé (ExifImageWidth × ExifImageHeight) |
| 0x102b | PrioritySettings | un int16u : AF-SPriority (masque 0x000f), AF-CPriority (0x00f0) : 1 déclenchement, 2 mise au point |
| 0x102d | FocusSettings | un int32u : FocusMode2 (0x0f : 0 AF-M, 1 AF-S, 2 AF-C), PreAF (0xf0), AFAreaMode (0x0f00 : 0 point unique, 1 zone, 2 large / suivi), AFAreaPointSize (0xf000, 0 sans objet), AFAreaZoneSize (0xff0000 : largeur dans les 4 bits bas, hauteur au-delà du 5e) |
| 0x104d | CropMode | 1 format 35 mm sur GFX, 2 viseur sport, 4 recadrage 1,25× (obturateur électronique), 8 téléconvertisseur numérique |
| 0x1101 | SequenceNumber | rang dans la rafale |
| 0x1103 | DriveSettings | un int32u : DriveMode (0xff : 0 vue par vue, 1 rafale lente, 2 rafale rapide), DriveSpeed (0xff000000, images par seconde) |
| 0x1301 | FocusWarning | 0 bonne, 1 floue |
| 0x1422 | ImageStabilization | type (0 aucune, 1 optique, 2 capteur, 3 objectif, 258 capteur et objectif plus numérique, 512 numérique), mode (0 désactivée, 1 en continu, 2 à la prise de vue seulement), puis un nombre non nommé |
| 0x4100 | FacesDetected | nombre de visages |
| 0x4103 | FacePositions | gauche, haut, droite, bas de chaque visage |
| 0x4201 | FaceElementTypes | 1 visage, 2 œil gauche, 3 œil droit, 7 corps, 8 tête, 9 les deux yeux, 11 deux-roues, 12 à 29 voitures, animaux, oiseaux, avions, trains |
| 0x4203 | FaceElementPositions | gauche, haut, droite, bas de chaque élément |

Les masques d'ExifTool se décalent de leurs bits à zéro (`(mot & masque) >> décalage`). Un réglage
groupé se lit quel que soit le type rangé (`LectureBoitier.Tiff.Entree.mot` : les premiers octets
de la valeur, comme ExifTool les lit en données binaires) ; une liste de positions, en SHORT,
LONG, BYTE ou octets indéfinis, 64 nombres au plus. Comme dans Focus-Points (`getAfPoints`), les
positions des visages et des éléments sont dans le même repère que FocusPixel (ExifTool dit « in
full-sized image », mais Focus-Points les met à l'échelle comme le point, et DSCF2402 le
confirme : la tête de 1283 à 1999 sur 4 416). Les textes en français (`lignesImage`,
`lignesPriseDeVue`, `lignesMiseAuPoint`) : « AF-S (ponctuel) », « Déclenchement »,
« Point unique », « Bonne », « Capteur, active (mode 1, en continu) », « Vue par vue »,
« tête, visage, œil gauche, œil droit ». La priorité suit le mode (AF-S ou AF-C) ; mode AF et
taille ne se disent pas en mise au point manuelle ; « Visages détectés : aucun » pour 0 ; un type
d'élément inconnu se nomme par son code. `--boitier` les donne aussi (`mise_au_point`, et
`valeurs_lues` sous les noms d'exiftool : « AFAreaPointSize (0x102d) », « FacePositions
(0x4103) »…).

**Relevé du 22 octobre 2026** (hors de Lightroom, en lecture seule) : DSCF2402.RAF (X-H2S,
l'original de la copie d'essai 53709912), lu par `--boitier` et par l'exiftool de Focus-Points
(`-a -G1 -s`, puis `-v3` pour les types) : tout concorde. FocusPixel 1665 845 (4 416 × 2 944),
PrioritySettings 0x0011 (SHORT), FocusSettings 0x00006001 (LONG : AF-S, point unique de taille
6), DriveSettings 0 (LONG), CropMode 0, FocusWarning 0, ImageStabilization 2 1 0, FacesDetected
1, FacePositions 1283 476 1999 1124, FaceElementTypes 8 1 2 3 (rangés en SHORT : int8u chez
ExifTool), FaceElementPositions (tête, visage, œil gauche 1435 787 1516 868, œil droit 1635 767
1716 848) : le point tombe dans l'œil droit, comme Focus-Points le montre. Ces valeurs (pas la
photo) sont dans `BoitierTests.dscf2402`. `--focus` sur une vignette tirée de l'original par
`sips` : 0,02 s, un cadre AF et quatre sujets.

**Cadres** (`Focus.cadres`, dans l'image affichée : chaque coin passe par
`GeometriePhoto.versApercu`, comme le point de `--marquer-af`, orientation et cadre de Lightroom
compris ; un cadre entièrement hors du cadre n'est pas dessiné, et la carte dit « lus, hors du
cadre actuel » si le point y est). Le cadre AF, centré sur FocusPixel (`Focus.tailleCadreAF`) :
un point unique, un mode large / suivi ou un point sans taille lue, le carré de 4 % du petit côté
de Focus-Points (sa taille « Medium » par défaut : FocusPointPrefs.focusBoxSize,
DefaultPointRenderer.createFocusFrame), la taille lue du point restant dite dans la carte ;
constaté le 22 octobre 2026 sur DSCF2402 : le premier modèle (un point de taille n couvrait n/6
d'une case de la grille, la taille 6 une case entière) dessinait un cadre trois fois plus grand que
Focus-Points, presque celui du visage. Une zone de l × h : l × h cases d'une grille dont la case
fait 1/13 du grand côté (la grille de 117 points, 13 × 9, du X-H2S : 340 × 327 pixels dans le
repère de 4 416 × 2 944), provisoire : pas relevée à l'écran, ni la grille des boîtiers plus
anciens (91 points en 13 × 7 sur un X-T20). Les visages et
les éléments, à leurs positions ; un visage dont le cadre est déjà celui d'un élément (la tête, sur
le X-H2S) n'est pas repris. CropMode est lu et dit (bloc Image, « Recadrage du boîtier ») ; les
positions restent celles du repère d'ExifImageWidth et ExifImageHeight, comme dans Focus-Points :
qu'un recadrage du boîtier (1,25×, viseur sport) les décale par rapport à l'image que Lightroom
montre reste à constater ; la zone du téléconvertisseur numérique (CropTopLeft, CropSize), que
Focus-Points dessine, ne l'est pas ici.

**Dessin** (`PreviewImages.marquerFocus`) : le cadre AF en rouge, entier, avec un point au
centre ; les visages et les éléments en coins jaunes (un quart de chaque côté), comme
Focus-Points ; un liseré sombre sous chaque trait ; épaisseur de 0,3 % du grand côté (2 pixels au
moins) ; un cadre de moins de 12 pixels grandit autour de son centre. À juger à l'écran.

**`mcp-developpeur --focus <original> '<géométrie JSON>' <vignette.jpg> <sortie.jpg>`**
(`Focus.marquer`, sur le modèle de `--marquer-af`) : lecture bornée (`LecteurBoitier`, 2 s), la
vignette marquée écrite dans `sortie`, et une ligne JSON : `lue`, `image`, `prise_de_vue` et
`mise_au_point` (paires titre, valeur, en français), `point_af` (x, y dans l'image affichée,
`dans_le_cadre`), `cadres` (`point_af`, `sujets` : ceux dessinés) et `dessinee`. Une géométrie ou
une vignette illisible donne les valeurs sans dessin. Rien de lu (`Focus.lire`, `Focus.nonLue`) :
la ligne `{"lue": false, "raison": …}` et le code 1, avec la raison `delai` (l'original ne s'est
pas ouvert dans les 2 s : `LecteurBoitier.bloque`), `introuvable` (pas de fichier à ce chemin) ou
`illisible` (ouvert à temps, sans rien que `LectureBoitier` sache lire : un HEIF de l'appareil, un
fichier sans la MakerNote de Fujifilm, une autre marque).

**Dans la fenêtre** (`Fenetre.lua`, section Focus ; `Vues.focus`, `Fil.texteFocus`,
`Lightroom.infosFocus`, `Images.lireFocus`) :

- le segment « Focus » (62 points, images `seg-focus` et `seg-focus-actif` des deux apparences) et
  sa variante, la carte Focus sur `carte-focus` (comme celle de la leçon : titre `focusTitre` en
  gras 12, « Focus · DSCF2402.RAF (Essai) » ; texte `focusTexte` en 12, `D.focusLignes` lignes,
  page par page par `Fenetre.montrerPage('focus', …)` et ▲ ▼, les titres des blocs en `<EM>`, gras
  12) ;
- jamais de bascule d'elle-même : `Fenetre.choisirOnglet` n'est jamais appelé pour Focus ; seul un
  vrai clic sur le segment l'ouvre (`Fenetre.surOnglet.focus`) ;
- l'aperçu de l'onglet (`Fenetre.apercuOnglet.focus`) : la vignette de la photo active avec ses
  cadres (sans, pour une autre marque), sa légende, l'image vide pendant la lecture, ◀ ▶ coupés ;
  Agrandir montre la vignette marquée en grand. Après un clic sur une ligne d'image du fil,
  l'aperçu montre cette image (`Fenetre.imageCliquee`), et Agrandir aussi, comme dans les onglets
  Aperçu et Proposition, jusqu'à un autre onglet. L'aperçu de la photo active des autres onglets,
  et son carré de `--marquer-af`, ne changent pas ;
- la lecture (`Fenetre.lireFocus`, `Fenetre.preparerFocus`), dans une tâche, une à la fois :
  `Vignettes.decrireVignette` (l'original, la marque, la géométrie ; une copie virtuelle donne
  l'original de la copie), `Lightroom.infosFocus` (fileName, copyName, dimensions,
  croppedDimensions, cameraMake, cameraModel, lens, focalLength, shutterSpeed, aperture,
  isoSpeedRating, exposureBias, exposureProgram, meteringMode par getFormattedMetadata, clé par
  clé ; la date et l'heure de dateTimeOriginal à l'heure locale), la vignette du cache de Lightroom
  (`Vignettes.demander`, 1 024, dans `PhotoActive/Focus-…`), puis, pour un fichier Fujifilm
  (`Fenetre.estFujifilm`, la même règle que le carré), `Images.lireFocus` :
  `/usr/bin/perl -e 'alarm 5; exec @ARGV' <connecteur> --focus …`, cinq secondes au plus ; rien
  n'est calculé en Lua ;
- un onglet caché ne lit rien ; l'onglet suit la photo active (`Fenetre.majPhoto` appelle
  `Fenetre.rafraichirFocus`) ; le résultat est gardé pour la photo (`Fenetre.focus`, refait à
  chaque ouverture de la fenêtre), et un vrai clic ne le relit que si la géométrie de la photo
  (cadre, orientation) ou son édition (`editCount`, `lastEditTime` : une retouche) a changé ; à la
  fin d'un tour de Claude (`Moteur.finTravail` change), l'onglet montré se relit par la même règle
  (`Fenetre.suivreFocus`, depuis la boucle ; constaté le 22 octobre 2026 : après « Retouche pro »,
  l'onglet montrait encore la photo d'avant, et Dany a demandé à Claude « reload l'image ») ; après
  une retouche faite photo affichée dans le module Développement, tant que Lightroom n'a pas refait
  son aperçu, `requestJpegThumbnail` répond « error loading thumb » à 512 px et plus, mais rend la
  vignette de 256 (constaté le même jour par la commande `vignettes`, plus d'une minute après la
  retouche : l'onglet relu restait sans image) : la vignette se redemande une fois par seconde,
  `Fenetre.ESSAIS_VIGNETTE_FOCUS` (3) fois, puis à `Fenetre.TAILLE_SECOURS_FOCUS` (256, moins nette
  mais à jour), sans signature, donc le clic suivant ou la fin d'un tour de Claude relit la grande.
  L'aperçu commun des autres onglets rencontre le même refus (il réessaie à chaque rafraîchissement,
  « error loading thumb » au journal) : à constater s'il reste longtemps sans image ;
- une lecture qui finit quand sa photo n'est plus la photo active (Dany est passé à une autre
  pendant ce temps) ne sert plus : son dossier s'efface, et le résultat de la photo active, lu
  entre-temps, reste montré (sans cela, il était effacé, puis relu) ;
- une lecture en erreur (`Fenetre.preparerFocus` qui lève une erreur, notée au journal) garde un
  résultat d'échec pour la photo, sans signature : la carte dit « non lue », et les
  rafraîchissements de l'aperçu ne relancent pas la lecture ; un vrai clic sur le segment la
  relance ;
- autre marque : Image et Prise de vue, et « Mise au point : non lue (seulement les fichiers
  Fujifilm pour l'instant) » (`Fil.FOCUS_AUTRE_MARQUE`) ; rien de lu, la raison dite par le
  connecteur (`Images.lireFocus` la rend en troisième, l'une d'`Images.RAISONS_FOCUS`) :
  « non lue (original introuvable) » (`Fil.FOCUS_INTROUVABLE`), « non lue (original trop long à
  ouvrir) » (`Fil.FOCUS_DELAI`), « non lue (format pas encore lu, comme le HEIF, ou fichier sans
  les données de l'appareil) » (`Fil.FOCUS_ILLISIBLE`) ; sans raison dite (connecteur muet,
  alarme de 5 s, erreur de la lecture) : « non lue (original illisible, introuvable ou trop long à
  ouvrir) » (`Fil.FOCUS_NON_LUE`) ; connecteur absent : « non lue (connecteur introuvable :
  réinstaller Développeur) » ; sans photo active, l'aide.

Essais : `BoitierTests` (`testMiseAuPointDeDSCF2402`, `testReglagesGroupesEnOctetsIndefinis`),
`FocusTests` (cadres, tailles, dessin, `Focus.marquer`, la raison de `Focus.lire`, `--boitier`),
`Tests/Lua/Fenetre/essais-focus.lua` (un faux connecteur qui répond la ligne de DSCF2402, comme
celui de `--marquer-af` d'`essais-integration.lua`), et les essais des segments, des cartes et des
images (`essais-dispositions`, `essais-fenetre-b`, `essais-images`, `tests.lua`).

## Notation (`propose_ratings`, `notation`)

Depuis la 1.1. Claude propose des notes selon un standard, critère par critère ; depuis la 1.1.1,
toute proposition arrive « à vérifier », et l'utilisateur l'accepte ou la change dans Lightroom
(carte Note de la fenêtre Claude ; la Séance de notation de la 1.1 et les boutons Noter et
À vérifier sont retirés), sans repasser par Claude ni dépenser de quota. Dans la fenêtre Claude, Claude note
d'abord toute photo qu'il traite, avant d'y toucher, sans rien poser (consignes de la fenêtre,
voir Carte Note) ; une photo déjà évaluée ne se renote pas, sauf demande (`view_photo` :
`evaluation`). Sans demande, Claude ne pose rien lui-même. Depuis la 1.1.1 (demandé par Dany le
20 octobre 2026), quand l'utilisateur lui demande de noter (« note ces photos », « pose les
notes »), `propose_ratings` avec `apply` pose aussi les notes (voir plus bas). Depuis le
correctif 1.3.2 (demandé par Dany le 22 octobre 2026 : « je veux que tu notes les photos de 0 à
5 étoiles ; si moi je veux une photo 5 étoiles, je placerai un code de couleur »), Claude note de 0
à 5 ★ ; les coups de cœur de l'utilisateur sont un libellé de couleur qu'il pose lui-même : Claude
n'en propose, n'en pose ni n'en change jamais sans sa demande explicite (`set_metadata`). De la 1.1
à la 1.3.1, Claude ne proposait jamais 5 ★ (l'utilisateur les posait, ou les demandait par
`set_metadata`). Ce qui reste à voir dans Lightroom : Fenêtre Claude › À constater dans Lightroom
(1.1, 1.1.1 et après), et À constater dans Lightroom (1.3), point 21.

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
  la valeur affective, un mot-clé ou une collection ; les coups de cœur de l'utilisateur, un
  libellé de couleur qu'il pose lui-même (section « Les coups de cœur », 1.3.2). 0 ★ veut dire
  « pas encore jugée ». L'échelle de Claude va de 0 à 5 ★, plus le rejet.
- Rejet : défaut majeur, involontaire, confirmé à l'œil (la seule photo de sa scène : plutôt 1 ★,
  à vérifier). 1 ★ : gardée, sous le niveau 2. 2 ★ : correcte, aucun défaut visible à la taille
  d'usage. 3 ★ : tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu. 4 ★ : une
  3 ★ qui a de l'impact (vue en premier sur une planche de 20 à 30 vignettes, nette à 100 % sur
  le sujet, meilleure vue de son moment ; souvent 5 à 10 % d'une sortie, sans quota). 5 ★ : une
  4 ★ qui tient à côté des meilleures photos de l'utilisateur, toutes sorties confondues ;
  développement fini, sans excès, la Finition vue à 100 % ; toujours forte quelques jours plus
  tard ; rare (bien moins que les 4 ★, souvent aucune dans une sortie), jamais avant le
  développement ni sans avoir vu toute la sortie (jusqu'à la 1.3.1 : posée par l'utilisateur
  seul). Une photo qui ne remplit pas les conditions d'une note reçoit celle d'en dessous.
- Critères, du plus lourd au plus léger : Impact (aucune mesure ne le voit), Qualités de l'image,
  Plancher technique (mesuré par `cull_photos` : il plafonne la note, il ne la donne pas),
  Finition (pour le 5 ★). Un défaut visible à la taille d'usage plafonne à 2 ★, visible seulement
  à 100 % à 3 ★ ; un défaut voulu et maîtrisé ne compte pas.
- Selon le genre (famille, portrait, paysage, nuit notée après le débruitage, sport, rue), puis
  quatre passes, une question chacune : 1 rejeter ou non ; 2 3 ★ ou non (sinon 2 ★, 1 ★ au
  passage) ; 3 parmi les 3 ★, monter à 4 ; 4 après le développement, parmi les 4 ★, monter à 5
  (les candidates vues à 100 %, Finition comprise ; aucune si aucune ne tient à côté des
  meilleures de l'utilisateur).
- Les mesures fixent le plancher et départagent une rafale ; elles ne justifient jamais seules un
  4 ★ ni un 5 ★. Photos étalons : la collection « Développeur › Étalons », si elle existe (entre 3
  et 4, et entre 4 et 5).

`Notation.noteMaximale` = 5 depuis le correctif 1.3.2 (4 avant) : Claude propose de 0 à 5
étoiles. `set_metadata` pose toujours une note de 0 à 5 quand l'utilisateur le demande ; son
`color_label` dit qu'un libellé de couleur ne se pose qu'à la demande explicite de l'utilisateur,
qui marque ainsi ses coups de cœur. Les plafonds de `Notation.plafond` ne valent que pour les
défauts : sans défaut mesuré, le plafond est `noteMaximale` (5), « aucun défaut mesuré : pas de
plafond », et `cull_photos` ne le liste pas.

### `cull_photos` et `contact_sheet`

`cull_photos` mesure le plancher technique : plafonds par photo (`plafonds`, `Notation.plafond`),
rejets proposés seulement pour un défaut majeur, ordre de lecture (`ordre`) au lieu d'un score, plus
de proposition de retenue ni d'étoile ; ses plafonds vont dans `dernierTri`. Sans cible, la photo
active (1.3.1). `contact_sheet` montre
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
  `{photo_id, rating (0 à 5) ou flag: "reject", criteria: {impact, qualities, technical_floor,
  finish}, reason, to_check}`. `rating` ou `flag`, pas les deux (`flag` seul : le rejet) ;
  `impact`, `qualities` et `technical_floor` obligatoires et non vides, `finish` facultatif (une
  photo développée) ; 200 caractères demandés par critère (`longueurCritere`), 300 pour `reason`
  (`longueurRaison`), refusés seulement au-delà de 300 et 400 (`toleranceCritere`,
  `toleranceRaison` : Claude dépasse de peu en comptant mal, constaté ; la carte coupe le
  surplus) ; `to_check` : un cas douteux (groupe, nuit, flou peut-être voulu ; défaut voulu
  au-dessus du plafond) ; depuis la 1.1.1, sa description ajoute que toute proposition arrive de
  toute façon « à vérifier » dans la carte Note (le registre garde `to_check` dans le champ
  `a_verifier` de la proposition).
- `pass` : la passe du standard, de 1 à 4 (depuis le correctif 1.3.2 ; jusqu'à la 1.3.1, la
  passe 4 était refusée, « Passe 4 : 5 étoiles, l'utilisateur seul ; rien à proposer. », par le
  serveur et par le module).
- `read_standard` : seul, rend `{standard}` sans rien envoyer au module ; avec `ratings`, les
  propositions sont rangées et le standard s'ajoute à la réponse.
- `apply` (1.1.1) : `true` quand l'utilisateur demande que Claude note ou pose les notes (« note
  ces photos », « pose les notes ») : la commande reçoit `poser = true`, et les notes sont aussi
  posées dans le catalogue, « à vérifier » comprises (réponse : `posees`). `false` ou absent :
  propositions seulement. La description de l'outil le dit, et ajoute (1.3.2) : jamais de libellé
  de couleur, les coups de cœur de l'utilisateur, qu'il pose lui-même (`set_metadata`, seulement à
  sa demande) ; un 5 se regarde à 100 % (jusqu'à la 1.3.1 : jamais 5 étoiles ici).

En 1.1, `session` (l'identifiant d'une séance) et `read_session` (la séance ouverte dans
Lightroom, par l'action `seance`) servaient à la Séance de notation : retirés en 1.1.1.

Tout est validé avant d'envoyer quoi que ce soit : un refus ne range rien. Les erreurs viennent
ensemble, une ligne `ratings[i] : …` chacune (dix au plus), après « Rien n'a été rangé : ».
Refusés : une note hors de 0 à 5 (« « rating » va de 0 à 5. » ; jusqu'à la 1.3.1, 5 ou plus :
« Claude ne propose jamais 5 étoiles : c'est à l'utilisateur. ») ou non entière ; `rating` avec `flag`, ou ni l'un ni l'autre ; un
`flag` autre que `reject` ; une clé inconnue dans une proposition ou dans `criteria`, avec la
bonne clé quand elle s'en rapproche (« note (ici : « rating ») ») — validée à la main
(`ratingKeys`), car `parametresInconnus` ne voit que le premier niveau des arguments ; un
critère obligatoire vide, un critère ou une raison trop longs, une raison vide, un `to_check` qui
n'est pas un booléen ; une photo proposée deux fois ; `apply` qui n'est pas un booléen, `pass`
hors de 1 à 4, plus de 500 propositions, `ratings` absent ou vide sans `read_standard`. Enfin une
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
          propositions: [{photo, note: 0…5 (0 pour un rejet), drapeau: "aucun" | "rejetee",
                          criteres: {impact, qualites, plancher, finition?},
                          plafond?: entier (celui de dernierTri), raison, a_verifier: booléen}]}
```

La réponse du module est rendue telle quelle (aussi en `structuredContent`), avec `standard` si
demandé. `notation` n'est pas une lecture que `LightroomBridge` rejoue après une coupure
(`LightroomBridge.lectures`) : rejouée, elle remettrait les propositions acceptées ou changées à
« à vérifier », et avec `poser`, elle écrirait de nouveau.

L'invite `noter` (arguments `photos` et `passe` : 1, 2, 3, 4 ou une consigne ; sans le guide de
style) : `cull_photos`, `contact_sheet` par planches de 24 à 30, `view_photo` sur le sujet pour les
candidates à 4 et 5 ★ et les cas douteux, `propose_ratings` avec `pass`, puis un résumé ; jamais
`set_metadata` pour une note sans demande ; 5 ★ rares, après le développement (passe 4) ; jamais
de libellé de couleur (ses coups de cœur, qu'il pose lui-même : `set_metadata`, seulement à sa
demande) ; `apply = true` si l'utilisateur demande que Claude pose les notes ; la passe 4 se
propose comme les autres depuis le correctif 1.3.2 (jusqu'à la 1.3.1 : jamais 5 ★ de lui-même, et
rien de proposé à la passe 4). Sans `photos`, la sélection de Lightroom (sinon, demander où elles
sont ; en 1.1, d'abord la séance ouverte, par `read_session`). Le standard entier la termine.
`tri_seance` ne propose plus de drapeau Retenue : les notes passent par `propose_ratings` (de 0 à
5 ★ depuis le correctif 1.3.2 ; acceptées dans la carte Note, ou posées avec `apply` à sa
demande ; ou l'invite `noter` ; ses coups de cœur, un libellé de couleur qu'il pose lui-même), et
`garder` désigne une collection, pas une note.

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

Une proposition : `{photo, uuid, fichier, note (0 à 5, nil pour un rejet), drapeau ('aucun' ou
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

- `proposer` : refuse tout pour une note qui n'est pas un entier de 0 à 5
  (`Notation.NOTE_MAX_PROPOSEE`, 5 depuis le correctif 1.3.2 ; second garde-fou, après le
  serveur), un drapeau autre que `aucun` ou `rejetee`, une proposition sans note ni rejet, une
  proposition sans photo, ou une passe hors de 1 à 4 (la passe 4 est permise depuis le correctif
  1.3.2 ; jusqu'à la 1.3.1, 5 ★ et la passe 4 étaient refusés) ; une photo introuvable va
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

- `remettre` (1.3 ; la recette seulement, jamais un outil) : `{photo, proposition}` remet la
  proposition d'une photo telle que `lire` l'a rendue avant une étape de la recette (ses champs
  gardés, l'uuid de la photo repris), ou la retire (`proposition` absente ou null) ; refuse plus
  de 5 étoiles (4 jusqu'à la 1.3.1), un état inconnu ou une autre photo, sans rien changer ; rien n'est écrit dans le
  catalogue. Réponse : `{photo, proposition}`. Constaté le 21 octobre 2026 : la recette posait
  avec `apply` puis défaisait par `undo_last` une note de 2 ★ sur une copie qui avait déjà 2 ★ ;
  le registre ne voit pas l'annulation et `Notation.recaler` n'y trouvait rien à reprendre (la note
  était là) : la proposition restait « acceptee », comme si Dany l'avait acceptée, et `view_photo`
  le disait. La recette lit donc le registre avant l'étape « note proposée… » et le remet après,
  même après un échec (`Recette.garderRegistreDesNotes`).

`propose_ratings` envoie `proposer` ; aucun outil n'envoie `lire` ni `remettre` (les essais de la
liaison et la recette les emploient, et `--module`).

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
inchangée ; puis posée sur demande et annulée » (son nom depuis la 1.1.1) : 6 étoiles refusées
(« « rating » va de 0 à 5 » ; jusqu'à la 1.3.1, 5 étoiles refusées, « jamais 5 étoiles »), puis 2 étoiles avec `to_check` rangées par la vraie commande `notation`
(état « a_verifier », celui de toute proposition depuis la 1.1.1), la photo inchangée ; depuis la
1.1.1, la même proposition avec `apply` : 2 ★ posées (`posees`, état « acceptee », note relue dans
le classement), puis `undo_last`, après quoi la photo est de nouveau comme au départ (en 1.1,
l'étape lisait la séance ouverte par `read_session`, retiré). Jusqu'à la 1.2, elle laissait une
proposition pour la photo d'essai dans `notation.json`, « acceptee » (constaté le 21 octobre
2026 : `Notation.recaler` n'y voit rien quand la photo avait déjà cette note) ; depuis la 1.3, la
recette lit le registre avant l'étape et le remet après, même après un échec (commande `notation`,
action `remettre`, `Recette.garderRegistreDesNotes` ; voir Le registre).
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

Depuis la 1.2 (`Recette.lancer(…, portrait:, mixte:)`) :

- avec le vrai pont seulement (`tools.lightroom as? LightroomBridge` : les tests passent par un faux
  module, attendent la liste exacte des étapes et ne lisent jamais le vrai écran), d'abord deux
  étapes en lecture seule. « liaison fermée (jeton privé) » (`sequenceLiaison`) : `get_status` dit
  `liaison_fermee` (sinon, un module d'avant la 1.2 : rien d'autre essayé) et ne donne ni le jeton
  ni le chemin de son fichier ; une commande `etat` sans jeton, puis avec un autre jeton bien formé
  (64 zéros, dans un fichier temporaire effacé ensuite), sont refusées (« Liaison fermée ») ; le
  jeton de la liaison passe. « écran nommé (get_status) » (`sequenceEcran`) : `ecran.principal` a un
  nom et une classe connue, sans chemin de profil ; la lecture de l'écran (`Recette.lireEcran`, que
  `main.swift` pose à `Ecran.lire`) n'est posée dans les outils que le temps de l'étape, pour
  qu'aucune remarque d'écran ne s'ajoute aux `view_photo` de la recette ;
- copie d'un RAW : « intention lue au boîtier (view_photo, intention_boitier) » après le profil
  d'appareil (simulation et lecture exigées pour un fichier Fujifilm, photo inchangée, chemin de
  l'original absent ; sautée pour une autre marque ; « rien de lu » sans original ou sans
  ouverture dans les 2 s) ; « bilan chiffré d'une passe à l'autre (view_photo), puis annulé » après
  l'aperçu et l'analyse (`etapeBilan` : deux vues de 1 024 px en `meme_etat`, une de plus si la
  première signale un calcul IA en attente ; `corrections_utilisateur` absent entre deux vues
  identiques ; une proposition sans `compare` n'a pas de bilan, et la vue suivante ne la compare
  pas ; Exposure +2 IL et Whites +50 écrits en relatif : exposition d'au moins +0,5 IL et « 1 de
  plus » ; puis `undo_last` : « 1 de moins », sans `regression`, et l'état revenu ; images
  `recette-bilan-avant.jpg` et `recette-bilan-apres.jpg`) ;
- à la fin du tri (`sequenceTireur`), deux étapes d'éclaircir et assombrir, en propositions de
  512 px seulement : l'inversion (un radial inversé, un radial et un linéaire, à −2 IL et fondu 0,
  comparés à une proposition presque neutre, le même radial à +0,01 IL ; part des pixels assombris,
  sous 0,8 fois leur luminance d'avant : radial inversé, plus de la moitié dans chaque coin et
  moins de 5 % au milieu ; sans inversion, l'inverse ; linéaire, le haut seul), puis la forme des
  bords de `Prompts.Tireur` (rayon 0,7, fondu 80, au milieu de la zone d'intérêt de Vision, à −0,3
  et −0,5 IL ; baisse lue en part de luminance perdue, et non en niveaux, pour qu'un coin sombre ne
  passe pas pour un anneau : centre de moins de 2 %, coin le plus loin de 5 % au moins, ni plaque,
  une seule marche qui fait plus de la moitié de la baisse au coin, `FormeBords.marcheMax`, ni
  anneau, une fin de profil sous 60 % de son pic, `finMin`) ; les pixels d'avant à 12 niveaux ou
  moins ne comptent pas ;
- copie d'un X-T20 (`--x-t20`) : l'intention lue au boîtier, après le point de mise au point ;
- `--portrait <id>` (`sequencePortrait`, puis `sequencePeau`, sur le visage le plus grand que voit
  Vision) : « visages vus par Vision (view_photo) » ; « peau : trois doses en propositions, détail
  des joues mesuré » (Peau du visage lisse, Adoucir la peau (Lite), et Adoucir la peau avec
  `smoothing_requested` s'il est installé ; la dose la plus forte doit lisser, sinon Lightroom ne
  reconnaît pas la peau) ; « intensité d'un masque : amount 50 = la moitié de la dose
  (propositions) », jugée au pixel près (`Recette.ecartMax`, 2 niveaux au plus,
  `Recette.ecartIdentique`), avec en témoin la dose entière, qui doit s'en distinguer (plus de
  3 niveaux), sinon il n'y a rien à juger ; « peau trop lissée refusée sans smoothing_requested,
  rien d'écrit » ; « dose par défaut posée à amount 50, relue, annulée » (`CorrectionAmount` 0,5,
  `LocalTexture` −0,2, `LocalClarity2012` −0,1, `MaskSubType` 3, `MaskSubCategoryID` 2, calcul de
  la peau du visage) ;
- `--mixte <id>` (`sequenceEclairage`, lecture seule, copies d'essai) : « éclairage mixte nommé
  (view_photo) » (lu mixte, grille et conseil, cases lues, durée de la mesure refaite sur l'aperçu
  rendu, balance proposée), puis « une seule lumière, en témoin (view_photo) » sur le RAW de la
  recette, sautée quand `--recette` et `--mixte` désignent la même photo (53709912, le portrait,
  est la seule copie mixte ; la dune 53709786 convient en témoin).

Les seuils de la recette 1.2 sont à elle et provisoires : `FormeBords` (`centreMax` 2 %, `coinMin`
5 %, `marcheMax` 0,5, `finMin` 0,6), `Recette.ecartIdentique` (2 niveaux) et le témoin (plus de
3 niveaux), ceux de l'inversion (plus de la moitié, moins de 5 %).

**Recette de la 1.2, le 21 octobre 2026** (Lightroom Classic 15.6, code de la 1.2 ; RAW 53709912,
JPEG 53709534, `--x-t20 53709579`, `--portrait 53709912`, `--mixte 53709912`) : réussie, 82 étapes,
code 0, de 02:19 à 02:25. Pour la 1.2 :

- liaison fermée : sans jeton et avec un autre jeton, refusées, une ligne au journal chacune
  (« Commande refusée sans jeton (connecteur d'avant la 1.2, ou autre programme) », « Commande
  refusée : mauvais jeton ») ; le jeton de la liaison passe ;
- écran nommé (`get_status`, dans le processus de la recette) : « Odyssey G85SD · profil d'usine, non
  mesuré sur ce Mac » ;
- intention lue au boîtier : 53709912, PROVIA/Standard, profil Camera PROVIA/Standard, DR100
  (réglée), manuel, 2 phrases de lecture ; 53709579 (X-T20), PROVIA/Standard, Camera
  PROVIA/Standard, DR200 (auto), couleur +2, tons clairs et foncés +1, programme, 3 phrases ;
- bilan chiffré : deux vues de 1 024 px identiques (`meme_etat`), la proposition ignorée ; après
  Exposure +2 IL et Whites +50, exposition 40,9 → 84,2 (+2,45 IL), contraste 67,6 → 75, hautes
  lumières 0 → 6,5 %, blanc pur 0 → 1 %, canal rouge écrêté 0 → 6,4 %, netteté 53,4 → 86,6 (nette
  → nette), bruit 0,70 → 1,65 (visible → fort) ; `regression` : « hautes lumières écrêtées : 0,0 →
  6,5 % (+6,4 points) » et « bruit passé de visible à fort : 0,70 → 1,65 (seuil 1,5) » ; puis
  `undo_last` : « 1 de moins », sans `regression`. `etapes_claude` (`Rendu.lua`) marche donc dans
  Lightroom ;
- éclaircir et assombrir, sur le portrait : radial inversé, coins assombris à 100 % (les quatre),
  milieu 0 % ; sans inversion, milieu 99,85 % ; linéaire, haut 100 %, bas 0 %. Forme des bords
  (rayon 0,7, fondu 80, centrée sur la zone d'intérêt en (0,38 ; 0,29)) : à −0,3 IL, centre 0,48 %,
  milieu des bords 9,1 %, coins 8,45 % (le plus loin 11,93 %) de luminance en moins, plus forte
  marche 1,61 % ; à −0,5 IL, centre 0,59 %, bords 14,39 %, coins 13,85 % (le plus loin 19,38 %),
  plus forte marche 2,41 % ; ni plaque ni anneau, à l'une comme à l'autre dose ;
- peau, sur le portrait (2 visages, le plus grand à 9,2 % de la largeur) : détail des joues gardé,
  89,27 % avec « Peau du visage lisse », 89,11 % avec « Adoucir la peau (Lite) », 75,98 % avec
  « Adoucir la peau » demandé (0,47 % des pixels changés de plus de 12 niveaux, 0 % pour les deux
  autres) ; `amount` 50 contre la moitié des curseurs : 0 niveau d'écart, pour 7,21 et 8 niveaux
  avec la dose entière ; « Adoucir la peau » refusé sans `smoothing_requested` ; la dose par défaut
  posée, `CorrectionAmount` 0,5, texture et clarté relues, peau du visage calculée dès la retouche,
  puis annulée ;
- éclairage mixte nommé (53709912) : écart 9,7, 9 cases lues sur 9, visages dans les deux lumières,
  balance proposée Temperature 5558, Tint 15, mesure en 155 ms (version de débogage) ; le témoin à
  une seule lumière n'a pas tourné (même photo que le RAW de la recette).

Depuis la 1.3 (`Recette+13.swift`, appelée par `sequenceRAW` et `lancer` ; essais
`Recette13Tests.swift` sur un module simulé à état) :

- copie d'un RAW, après le bilan : « avant/après d'une étape gardé sans autre rendu (Pourquoi ?),
  puis annulé » (`etapePourquoi` : la vue gardée par `apercu` avec `avant_apres`, l'étape écrite par
  `appliquer` avec `avant_apres`, Exposure2012 +0,5 ; l'étape retrouvée par l'`etape_id` de la
  réponse, jamais par sa place dans la liste, qui garde aussi les étapes défaites ; l'après attendu
  par la commande `etapes`, en lectures bornées, 30 s au plus ; état « pret », une étape de plus en
  mémoire, l'avant aux dimensions de la vue, donc sans second rendu, l'après plus clair ; la durée
  lue dans `<id>.json` ; puis `undo_last`, l'étape dite hors de la mémoire) ; « leçon de la photo
  (photo_lesson) : ISO et indices lus, refusée pour une photo d'essai, rangée pour la recette
  (essai_recette), relue, retirée ; photo inchangée » (`etapeLecon`, sautée hors de « Développeur ›
  Essais », où la leçon irait au carnet de l'original : Exposure2012 = max(départ,
  actuel) + 0,7 et Temperature = min(départ, actuel) − 500 K, calculés depuis le départ de la
  séquence ; le journal détaillé doit porter `sensibilite` en nombre (1.3.1) ; `read_facts` doit
  donner `underexposed` et `color_cast` ; puis les trois points par
  `photo_lesson`, qui doit rendre `rangee = false` avec la remarque de la photo d'essai, et rien de
  rangé pour la copie (1.3.1) ; puis `lecon garder` avec `essai_recette` par la commande du module,
  jamais par un outil, sous l'entrée de la copie (`original` = la copie), `lecon lire`, `lecon
  retirer` et `undo_last` ; une leçon déjà rangée pour la copie, d'un essai d'avant la 1.3.1, arrête
  l'étape avant toute écriture) ; « carnet de progrès : photo d'essai refusée, notée
  pour la recette (essai_recette), exportée, retirée » (`sequenceCarnet`, sautée hors de
  « Développeur › Essais » : une vue sans `essai_recette` doit être refusée de motif `essai`, tout
  autre motif arrête l'étape sans rien envoyer d'autre ; puis l'angle de `measure_angle` avec
  `essai_recette`, sous l'entrée de la copie ; le mois, et `find_photos` qui retrouve la photo au
  jour de sa prise de vue et pas la veille ; `carnet lire`, `export_journal` avec `notebook`
  (« # Carnet de progrès »), et `carnet retirer {photos = [copie]}`, même après un échec) ;
- après les variantes : « « Je le fais » : ma version rangée sans rien appliquer, réglages changés,
  comparée côte à côte, puis effacée » (`sequenceJeLeFais` : `my_turn` Exposure2012 +0,3 et
  Vibrance +10 en relatif ; rien d'appliqué ni de rendu, `a_faire` Exposition puis Vibrance,
  « Claude · ma version » rangée, l'entrée `exercice` au journal ; `apply_settings` à la place de
  Dany, +0,8 et Shadows2012 +20 ; `view_photo` avec `claude_version` : une image, Exposure2012
  `plus_fort`, Shadows2012 `ajoute`, Vibrance `oublie` ; `undo_last`, puis « ma version » effacée,
  même après un échec ; une « ma version » déjà rangée arrête l'étape) ;
- l'étape du débruitage vérifie aussi la photo active, lue par `get_status` avant et après
  (`Recette.ecartPhotoActive`, voir Bibliothèque) ;
- `--horizon <id>` (`sequenceHorizon`, `--hauteur-horizon` de 0,05 à 0,95, 0,5 par défaut ; une
  copie avec Upright ou une perspective est refusée d'emblée) : « composition lue, cadre proposé en
  pointillés, photo inchangée » (le cadre gardé égal au crop : centre à 0,003, largeur et ratio à
  0,5 %, angle à 0,01° ; les `Crop*` inchangés au millionième) ; « cadre actuel lu sur l'image
  entière (recadrée en 4:5, tournée de 2°) » (le recadrage d'essai du contrat de la composition :
  le cadre actuel égal à celui posé, les `Crop*` remis exactement, l'horizon retombé à sa place) ;
  « cadre proposé appliqué : horizon droit, sur le tiers du bas (measure_angle) », puis deux
  `undo_last`. Sans horizon net à cette hauteur (une mesure qui n'est pas « affinée »), les deux
  premières réussissent et le disent, la troisième est sautée avec sa raison (« choisir pour
  --horizon une copie d'Essais qui a un vrai horizon »), le recadrage d'essai annulé ; sans
  `--horizon`, la recette dit que la composition n'est pas vérifiée.

La recette retire toujours ce qu'elle range hors du catalogue (la leçon, l'entrée du carnet de la
copie, l'instantané « Claude · ma version », la proposition de notes remise), même après un échec ;
elle ne remplace jamais une leçon déjà rangée ni une « ma version » d'avant (l'étape s'arrête
avant toute écriture) ; elle n'envoie `essai_recette`, ni `carnet retirer`, qu'après un refus de
motif `essai` (un angle irait sinon à l'entrée de l'original, et retirer l'effacerait).

**Recette de la 1.3, le 21 octobre 2026** (Lightroom Classic 15.6, code d'essai de la 1.3 avant
les corrections du lot 18 ; `--recette 53709912 --jpeg 53709534 --x-t20 53709579 --portrait
53709912 --mixte 53709912 --horizon 53709786`, 380 s) : 91 étapes, 90 réussies. Pourquoi ? :
l'avant est la vue de 1 344 × 896, sans second rendu, l'après plus clair (L* 36,8 → 45,3), prêt
1,54 s après la réponse, capture en 1,02 s. Leçon : `underexposed` et `color_cast`, rangée (prise de
vue 2026-01), relue, retirée. Carnet : la vue refusée « Photo d'essai (Développeur › Essais) : le
carnet ne compte que les vraies prises de vue. » (`estPhotoDEssai` constaté sur une vraie copie),
l'angle noté avec `essai_recette` au jour de sa prise de vue, exporté, retiré, catalogue inchangé.
Je le fais : `a_faire` Exposition puis Vibrance, écarts `plus_fort`, `ajoute`, `oublie`, « ma
version » effacée. Composition : les deux premières étapes réussies ; la troisième en échec,
l'horizon penché de 0,55° au lieu de 0,33° : la dune n'a pas d'horizon à mi-hauteur, et la mesure
« affinée » s'accrochait aux rides du sable (d'où `LineAngle.ecartMax` et l'étape sautée). Toutes
les étapes de la 1.2 passent. La proposition de notes de la recette restait « acceptee » (d'où
`remettre`), et la photo active d'avant n'était pas remise après les passages au module
Développement (d'où `Bibliotheque.remettreSelection`). Il manque à « Développeur › Essais » une
copie qui a un vrai horizon pour `--horizon`.

`get_settings` avec `all_keys` ajoute tout ce que Lightroom range (`toutes` côté module) : pour
explorer un outil appliqué à la main (flou d'objectif, réduction du bruit…).

## À constater dans Lightroom (1.2)

La 1.2 passe les deux suites (`swift test` : 367 tests, dont 1 sauté sans
`DEVELOPPEUR_ECRAN_REEL=1` ; `scripts/tester-module.sh` : liaison 235, fenêtre 47,
`essais-dispositions` 18, `essais-integration` 7, `essais-moteur` 16). Ce qui a été vu dans
Lightroom les 20 et 21 octobre 2026 (les relevés de chaque chantier, puis la recette de la 1.2,
réussie) est daté dans la section de chaque chantier et dans Recette dans Lightroom. Reste à voir,
sur les copies d'essai ou une photo que Dany désigne, chaque essai défait ensuite ; ce qui sera
constaté passera dans sa section, avec sa règle dans la simulation de sa suite quand c'en est une
(un constat de rendu n'en a pas). Ce qui tient à la fenêtre Claude est aux points 15 et 16 de sa
liste (Fenêtre Claude › À constater dans Lightroom).

1. Liaison fermée : le jeton change entre Arrêter et Démarrer la liaison. Un POST `curl` vers
   127.0.0.1:54770 : ses en-têtes comptés comme lignes illisibles (une note par 10 s), son corps
   refusé faute de jeton, rien dans l'Historique ; le diagnostic du Gestionnaire de modules externes
   dit « Jeton : présent (…) ; commandes refusées : N ». La durée de la commande `etat` ne change pas
   (`DEVELOPPEUR_VERBOSE=1`). Un Claude Desktop resté ouvert sur un connecteur d'avant la 1.2 reçoit
   « Liaison fermée : cette commande ne porte pas le jeton… », puis marche une fois relancé ; la
   fenêtre Claude marche sans réglage ; `--status` dit l'état du jeton.
2. Peau : « un masque par personne » dans un groupe (sur 53709833, Vision ne voit que 2 personnes
   sur 4 : lesquelles Lightroom reconnaît-il pour `kind` `person` et `part` `face_skin` ?) ; sur
   53709677, le masque de la personne a été retiré à la recette du 20 octobre 2026, peut-être par
   le défaut de la personne seule corrigé depuis (voir Masques : pistes de la 2.1) : à réessayer ;
   si Lightroom ne la reconnaît toujours pas, l'étape des doses de la recette y échoue (« rien de
   lissé ») ; la largeur des visages qui fait un « gros plan » ; les doses par masque ne doivent
   pas faire passer la netteté maximale sous 35 (une régression « nette à douce » à tort). Le panneau
   Masque montre-t-il les curseurs d'un effet intégré, sans nom d'effet (« Peau du visage lisse »
   n'est pas dans le menu Effet de Lightroom) ?
3. Éclaircir et assombrir : la forme des bords sur un intérieur (53709628), décentrée sur la zone
   d'intérêt ; le radial du sujet (fondu 80 à 100), écrit sur 53709912 puis défait : ni halo, ni
   peau écrêtée ; les doses (−0,3 à −0,7, +0,2 à +0,4, −0,3 à −0,5 IL, venues de la feuille de
   route), jugées par Dany sur l'avant/après d'un portrait, d'un paysage et d'un intérieur ; la
   forme d'un radial fait à la main (`get_settings` avec `all_keys`) : `Flipped` toujours vrai ?
   Sinon, assouplir la règle de la simulation. Les seuils de la recette (`FormeBords`,
   `Recette.ecartIdentique`, l'inversion) restent provisoires.
4. Lecture du boîtier : `--boitier` sur les originaux des essais (X-H2S : DSCF2402, DSCF4245,
   DSCF1595, DSCF8755 ; X-T4 : DSCF8880 ; X-T20 : 20200718_161742.raf et 20200710_193347.jpg),
   comparé à exiftool, dans le Terminal de Dany (jamais répondre à une demande d'autorisation de
   macOS à sa place). En noir et blanc, FilmMode (0x1401) est-il absent et la simulation dans
   Saturation (0x1003) ? 0x1443 à 0x1445 quand la priorité à la plage dynamique est désactivée (si
   0x1444 vaut 1 même désactivée, la phrase de priorité sortirait à chaque photo). La forme de
   0x9204 (−2/3 ou −67/100, SRATIONAL ou RATIONAL) et les compensations habituelles de Dany, pour
   les seuils de ±0,6 IL (±1/3 ne doit rien déclencher). Lightroom compense-t-il la plage
   dynamique d'un RAF à DR200 ou DR400 ? Comparer la L* médiane de `view_photo` (Exposure2012 = 0,
   profil de la simulation) à celle du JPEG incorporé : la phrase de la plage dynamique se règle
   là-dessus. La nuit 53709724 (ISO 12 800) : compensation, mode et scène lus ; L* médiane avant et
   après l'essai réel : Claude ne remonte pas une nuit voulue sombre. Après un profil de simulation
   posé à la main, `profil` de la réponse `apercu` le nomme-t-il, pour que « le profil actuel est
   la simulation » sorte ? La durée de `view_photo` avec la lecture (moins d'une seconde visée).
5. Éclairage mixte : `toleranceNeutre` (10), `seuilTonal` (8), `partMinGroupe` (20 %) et
   `pixelsMinPeau` (20) sont provisoires, et seul le portrait est mixte parmi les copies d'essai :
   un intérieur vraiment éclairé par une lampe et une fenêtre est à ajouter avec Dany (une copie
   virtuelle rangée dans « Développeur › Essais »). La balance proposée (Temperature 5558, Tint 15
   sur 53709912) ramène-t-elle la lumière des visages à |a*| et |b*| de 2 au plus
   (`--eclairage 53709912 --essai` avec elle) ? Sinon les pentes de `match_series`, relevées vers
   5 000 K, ne valent pas si loin. L'anneau autour d'un visage lit-il la lumière qui l'éclaire ?
   `--essai` en mode « Proposer d'abord » avec l'accord dans Lightroom coché demande un accord par
   essai. La durée de la mesure en version optimisée (moins de 50 ms visés).
6. Bilan : les seuils de netteté et de bruit (`baisseNetteteMin` 3, `hausseBruitMin` 0,1,
   `baisseBruitDebruitage` 30 %, `ecartNettetePct` 10 %, `ecartBruit` 0,1), par deux vues avant et
   après une étape écrite puis défaite : débruitage 30 et 50 sur 53709724 (pas 53709833, qui porte
   déjà la réduction du bruit de son original), Shadows +60, Exposure +1, Sharpness +60, Grain 25.
   Les coins vides : Upright 2 et PerspectiveVertical 40, avec et sans « Contraindre le
   recadrage » (`Bilan.cadre` change-t-il, et `partBlancPurCoins`, 80 %, envoie-t-il l'alerte dans
   « coins vides possibles » ?). Le plancher proposition contre vue, à remesurer depuis que les
   propositions se mesurent comme les vues (presque nul attendu ; sinon, le reste vient du rendu de
   Lightroom). La « dominante accentuée » sur une correction voulue (balance sur la lumière des
   visages d'un éclairage mixte, style chaud demandé) : si Claude la défait à tort, la passer dans
   `a_verifier`. La taille de ce que lit Claude dans `view_photo` (6,9 Ko de JSON pour le portrait
   mixte, le 21 octobre 2026 ; la lecture du boîtier, 300 à 1 300 caractères, se répète à chaque
   vue) et sa durée en version optimisée (environ 0,9 s en débogage, sur un aperçu de 1 344 px
   d'un portrait à quatre visages, avec Vision, le détail, l'éclairage et le bilan).
7. Écran : des profils standard (sRGB IEC61966-2.1, puis Display P3, choisis par Dany dans les
   Réglages système, puis le sien remis : classe `standard`) ; un profil fait à l'œil (assistant
   d'Apple : emplacement, créateur, `vcgt`, classe `oeil`) ; un vrai profil de sonde (DisplayCAL,
   Calibrite, i1Profiler, Spyder : créateur, `vcgt`, textes desc, cprt et meta), et un profil de
   fabricant qui cite X-Rite dans son cprt (classé sonde à tort ?) ; où les logiciels de sonde
   rangent leurs profils (sous `/Library/ColorSync/Profiles/Displays/`, un profil de sonde serait
   classé usine). Un écran Apple (préréglages XDR, Studio Display) : ses préréglages restent
   « usine ». `testEnteteLuDansLesOctets` sur le runner macos-15 de GitHub (« lppa »). La remarque
   d'écran arrive à Claude au premier aperçu, une fois, dans Claude Desktop et dans la fenêtre ;
   `--status` dit l'écran.
8. Consignes et descriptions : une session de Claude Code voit les consignes du connecteur entières
   (3 768 caractères) et les descriptions d'outils longues (`add_mask` 1 559, `view_photo` 1 783)
   sans les couper : pour une description d'outil, jamais constaté.

## Pourquoi ? : l'avant/après des étapes (1.3)

Dans la fenêtre Claude, chaque étape de Claude montre pourquoi elle a été faite (sa raison) et son
avant/après. Lightroom ne rend que l'état actuel d'une photo (`LrExportSession` prend les réglages
du moment) : ni un état de l'Historique ni un instantané ne se rendent sans être posés sur la
photo. L'avant/après se garde donc au moment de l'étape, au rendu, jamais par une écriture dans
le catalogue.

**Identité des étapes** (`Ecriture.lua`). `Ecriture.idEtape()` fabrique un identifiant
`%X-%04X-%d` (l'heure, un tirage, un compteur), qui sert aussi de nom de fichier ;
`Ecriture.nouvelleEtape(etapes, nom, avant)` ajoute `{ id, nom, avant, le }` à la mémoire
(`etapesClaude`, 20 au plus) et rend l'id : toute étape nouvelle passe par lui (`ecrirePlans` —
appliquer, masquer, retoucher, copier, masques, la poussière —, `Amelioration`, `Suppression`,
`Variantes.choisir`, `Bibliotheque.memoriser`). `etape_id` va dans l'entrée du journal et dans
chaque résultat (voir Messages entre le serveur et le module) ; quand Lightroom n'a rien lancé
(débruitage, reflets), la mémoire est remise et la réponse n'a pas d'`etape_id`. `recadrer` garde
l'id de l'étape qu'il complète. `annuler` rend l'`etape_id` de l'étape défaite (null pour une
étape d'avant la 1.3, qui s'annule par son rang).

**Capture** (`Etapes.lua`, sans `LrView` ni couleur ; chargé par la liaison et la fenêtre).
`Liaison.recevoir`, après le jeton, appelle `Etapes.avantCommande(nom, params)`, puis, une fois la
réponse partie, `Etapes.apresCommande`, ou `Etapes.abandonner` sur une erreur ; ces crochets ne
laissent passer aucune erreur. Conditions : la case Avant/après cochée (`avantApresEtapes`, défaut
de `Chemins.defauts`) et la fenêtre Claude ouverte ou son Claude au travail (`Etapes.actifPour`,
posé par `Fenetre.afficher` : `Fenetre.etapesActives` ; sans fenêtre, Claude Desktop seul, aucune
capture), ou `avant_apres = true` (la recette seulement, jamais un outil, qui lève aussi la
condition suivante) ; une commande qui écrit une étape sur une seule photo, la photo active ; ni
`sans_avant_apres` (`match_series`), ni pause, ni refus prévisible (« Proposer d'abord » sans
accord, photo protégée : `Ecriture.verifierProtection`). Commandes : `appliquer`, `masquer`,
`retoucher`, `copier`, `ameliorer`, `supprimer`, `masques` (hors `lister`) et `variantes`
`choisir` font une étape nouvelle ; `recadrer` complète l'étape précédente pour les photos de
`completer`. Les classements (`metadonnees`, `collections`, `notation`) n'ont pas d'avant/après.

- L'avant : la vue, c'est-à-dire le dernier rendu connu de la photo dans le même état (l'image
  entière de l'état actuel que `Rendu.apercu` garde, `Etapes.garderVue`, jamais un zoom, un
  `chemin_avant`, un `essayer` ni une image entière de `read_composition` ; ou l'après de l'étape
  précédente), reconnue par une empreinte ; à défaut (une retouche à la main entre-temps), un rendu
  juste avant l'écriture, gardé comme vue.
- L'après : rendu une fois la réponse partie, pendant que Claude écrit son appel suivant, puis il
  devient la vue. Avec `a_recadrer`, l'avant est rangé tout de suite et `<id>.json` dit `en_cours` :
  `recadrer` complète l'après.
- L'empreinte : `Locaux.empreinte(Json.encode(sansVolatils(réglages)))`, puis `|` et
  l'orientation. `sansVolatils` retire, à toute profondeur, les clés en `…Digest` et
  `…DigestVersion`, `UprightTransform*`, `LensProfileName`, `LensProfileFilename` et
  `LensProfileIsEmbedded`, et tient une table vide sous une clé texte pour une clé absente (un
  élément vide d'une liste garde sa place). Si l'empreinte change pendant le rendu (E1 et E2
  différentes), l'après est jeté (raison `changee`).
- Jamais un rendu quand Lightroom a encore des calculs IA à faire (après `calculerAvantRendu`, ou
  `needsUpdateAISettings`) : un rendu que Claude n'a pas demandé ne doit pas ouvrir la fenêtre
  « Mises à jour IA recommandées » (raison `calculs_ia`).
- Une capture à la fois : toute commande hors `Etapes.SANS_ATTENTE` (`ping`, `etat`, `selection`,
  `progression`, `notation`, `etapes`, `lecon`, `carnet`, `journal`, `reglages`, `diagnostic`)
  attend sa fin, `ATTENTE` (8 s) au plus ; une capture de plus de `PERIMEE` (120 s) est tenue pour
  interrompue.
- Fichiers, dans `Chemins.etapes()/<uuid>/` (une copie virtuelle a le sien) : `<id>-avant.jpg`,
  `<id>-apres.jpg` (côté `COTE`, 1 024 px ; l'avant est la vue de 1 344 quand elle a servi),
  `<id>.json` (`{ etat = pret | manque | en_cours, raison?, detail?, duree?, photo, etape, le }`),
  `vue.jpg` et `prepare-<n>.jpg`. Raisons en mots : `Etapes.RAISONS` (`calculs_ia`, `changee`,
  `rendu`, `sans_avant`, `interrompue`). Ménage au chargement du module (`Etapes.menage`, dans son
  propre `LrTasks.pcall` d'`Init.lua`) : la vue et les préparations d'une session passée, puis les
  fichiers de plus de 30 jours (`JOURS`), puis les plus anciens au-delà de 500 Mo (`MAX_OCTETS`),
  et les dossiers vidés. Ces images ne partent jamais vers Claude ni vers le connecteur, sauf les
  chemins de la commande `etapes` (la recette).
- `etapes {photo?}` : les étapes de la mémoire, puis celles qui ne restent que sur le disque
  (`en_memoire = false`), avec leurs images et leur état ; lecture seule, rejouée.
  `Etapes.images(photoId, etapeId)` rend une table neuve à la fenêtre ; `Etapes.version` change à
  chaque avant/après rangé ou manqué.

Un plan B (une capture à 1 568 px reprise par `view_photo`) était prévu si les captures
ralentissaient trop Claude : non nécessaire (mesures ci-dessous).

**Dans la fenêtre.** Une étape (`Conversation.OUTILS_ETAPES` : `apply_settings`, `add_mask`,
`edit_mask`, `retouch_spots`, `copy_settings`, `enhance_photo`, `remove_distractions`,
`choose_variant`, `match_series`, `set_metadata`, `manage_collections`) appelée sans `preview`
garde `raison` (`reason`) et `etape` (`step_name`) ; à la réponse, `e.etapes`
(`Conversation.etapesLues` : `{ photo, id, nom, fichier, changements }` pour chaque résultat qui
porte un `etape_id`), `e.annule` pour `undo_last`, `e.revenu` pour `revert_to_original` ; `Stockage`
les écrit en tableaux, même vides. `Conversation.estEtape(e)`, `Conversation.etapes(c, photo)` (une
étape est « annulée » par un `undo_last` suivant, par son id, sinon par son nom ; « défaite » par un
`revert_to_original` suivant) ; une conversation de la 1.2 se relit dans `detail`
(`Conversation.infoEtape`, sans id). Sa ligne du fil porte le bouton « Pourquoi ? » (voir Fenêtre
B) : `Fenetre.pourquoi(i)` relit la ligne, puis `Fenetre.montrerEtape` ouvre l'onglet Aperçu, jamais
par une bascule automatique. `Fenetre.etape` = `{ conversation, photo, id, element, vue, suivre }`
(l'id de l'élément, pas son indice), remis à nil quand la conversation change. La carte
(`Vues.etape`) : « Étape n sur N · but » (sans étape : « Pourquoi ? », `Fenetre.TITRE_ETAPE`, et
l'aide `Fenetre.AIDE_ETAPE`), le sous-titre (fichier · outil · « annulée ensuite (undo_last) »,
« défaite ensuite (revert_to_original) » ou « en cours »), la raison, ce qui a changé, et « Pas
d'avant/après : … » ou « Avant/après incomplet : … » (`Fenetre.SANS_IMAGES`, `Etapes.RAISONS`),
page par page (`etapeTexte`, `D.etapeLignes`). L'aperçu montre l'après (« Étape n sur N · après »,
ou avant, « avant/après en préparation… », « pas d'avant/après ») ; ses ◀ ▶ sont coupés ; ◀ ▶ de la
carte passent d'une étape à l'autre de la même photo (la dernière reprend le mode suivre, qui suit
la dernière étape à mesure que Claude travaille) ; Voir l'avant / Voir l'après (`titreBascule`) ;
Détail… (l'appel et sa réponse) ; Agrandir montre l'avant et l'après côte à côte
(`Fenetre.agrandirDeux`, chaque image dans 540 × 700, `Fenetre.GRANDE_DEUX`, titre « Claude ·
<titre> »), ou la seule image qui existe. Les images se lisent par `Etapes.images` dans une tâche,
réduites par `Images.vignette`, gardées par étape (`Fenetre.imagesEtapes`) et relues quand
`Etapes.version` change. Un vrai clic sur le segment Aperçu sans étape choisie montre la dernière
étape de la photo active, sinon de la conversation.

**Consignes.** La raison de chaque retouche : `ToolHandler.descriptionRaison` (160 caractères au
plus), répétée dans chaque outil qui écrit ; dans la fenêtre, la section « ## Raison de chaque
étape » (voir Fenêtre Claude › Claude Code).

**Constaté le 21 octobre 2026** (Lightroom Classic 15.6, deux copies d'Essais, 13 étapes
capturées par la commande brute du module avec `avant_apres`, puis défaites) : une capture prend
0,51 à 1,06 s (masques IA compris), sous la 1,5 s visée ; la réponse à Claude ne change pas quand
une vue de l'état existe (0,24 contre 0,25 s : +4 %), et prend +0,8 s sans elle (l'avant rendu
avant l'écriture) ; 0,6 à 0,9 Mo par étape (500 Mo : 600 à 800 étapes) ; un `view_photo` qui suit
une capture l'attend (environ 1,1 s), sans erreur. `COTE` 1 024 et `ATTENTE` 8 sont gardés. Un
masque IA posé par `add_mask` est calculé avant la capture : pas de raison `calculs_ia`, pas de
fenêtre IA. Lightroom ne change seul aucune clé (à 0, 1 et 5 s, après un aperçu, une proposition,
un débruitage relu) ; seules les écritures du module en changent (`GlobalInputDigest` du
débruitage). Mais `MaskGroupBasedCorrections` passait d'absente à `{}` (retour de `view_photo`
`compare = before_claude`, annulation de l'étape qui posait des masques) puis de `{}` à absente
(rendus du recalage), sans effet sur l'image : d'où la table vide tenue pour absente dans
`sansVolatils`. La simulation de la liaison fait tomber un `MaskGroupBasedCorrections` vide à une
écriture de `LensProfileEnable` ou de `PerspectiveUpright` (les rendus du recalage) : le
déclencheur exact est supposé, et dit comme tel.

## Leçon de la photo (1.3)

À la fin d'une retouche, la leçon de la photo : trois points, Lumière, Couleur et Composition,
chacun avec ce qui manquait et ce qui l'aurait évité à la prise de vue, rangés dans
`carnet.json` ; Claude les écrit, le connecteur les vérifie et lui donne les faits.

**Le vocabulaire des défauts** (`PriseDeVue.swift`, sans Vision) : `PriseDeVue.defauts` est la
seule liste des défauts de la prise de vue (la leçon, le carnet, les indices). Seize codes, chacun
avec sa clé anglaise (l'énumération de `photo_lesson`), son axe de leçon (`lumiere`, `couleur`,
`composition`), son domaine de carnet (`lumiere`, `nettete`, `couleur`, `composition`), son
libellé (40 caractères au plus), son conseil à la prise de vue (140 au plus) et s'il est mesuré :
`horizon_penche`, `verticales_fuyantes`, `cadrage_large`, `sujet_centre`, `bords_encombres`
(composition) ; `sous_exposition`, `surexposition`, `ciel_brule`, `ombres_bouchees`,
`contraste_plat`, `bruit`, `flou`, `mise_au_point` (lumière, les trois derniers au domaine
netteté) ; `dominante`, `eclairage_mixte`, `couleurs_ternes` (couleur). Six sont mesurés
(`horizon_penche`, `sous_exposition`, `ciel_brule`, `bruit`, `flou`, `mise_au_point`) : le
carnet les compte. `PriseDeVue.vocabulaire`, un tableau JSON dans l'ordre de la liste, part avec
chaque constat du carnet : le module n'écrit aucune liste de défauts.

**L'outil** (`photo_lesson`, `Tools+Lecon.swift` ; partie pure dans `Lecon.swift`), en lecture
seule (`readOnlyTools`) : ni la photo ni le catalogue ne changent ; la leçon va dans `carnet.json`
par la commande `lecon`. Sans points ni `read_facts`, un refus qui explique les trois points ; les
deux à la fois, refusé aussi. Les points sont validés avant tout envoi (`Lecon.points`) : trois,
chaque axe (`light`, `color`, `composition`) une fois, rendus dans l'ordre des axes ;
`at_capture` obligatoire, `missing` facultatif (absent : rien ne manquait) ; chaque moitié 140
caractères au plus (`Lecon.longueurPoint`) et 600 octets (`Carnet.LONGUEUR_TEXTE`) ; chaque défaut
connu et de l'axe de son point. Une clé inconnue est refusée à la main par `ToolHandler.nommer`,
avec son nom proche ; un refus nomme le point fautif et dit « Rien n'a été rangé ». Puis `journal
{photos, detaille: true}` (60 s), le départ (`departDeLaSession` : la plus ancienne vue de
`vuesMesurees` pour cette photo, toutes tailles), et `lecon {action garder, photo, lecon}` (30 s).
Toute erreur de ce seul envoi donne `rangee = false` et une remarque (un module d'avant la 1.3 :
« Leçon non rangée : le module de Lightroom chargé ne connaît pas encore la commande lecon… »),
jamais une erreur d'outil. Réponse : `lecon {photo, fichier, rangee, remplacee, mois, prise_le,
sans_date}`, `texte` (« Leçon de la photo · <fichier> », une ligne par axe), `faits`,
`remarques` (« Mesuré : … ; la leçon ne nomme pas « … » : à revoir »). Avec `read_facts`,
`{photo, faits, rangee: false}`, et seule la commande `journal` part.

**Les faits** : `prise_de_vue` (la description de la photo, et `prise_de_vue_plus`
`{compensation, flash, programme, mesure}`, lus un à un par `Photos.meta` sous `LrTasks.pcall`,
jamais dans `CLES_FORMATEES` ni une lecture groupée : `Lecture.journal` avec `detaille`) ;
`corrections` (`Lecon.correctionsNettes` : retouches, classements et exercices s'empilent ; une
annulation retire l'entrée de même `etape_id`, sinon la dernière dont l'étape est le nom entre
« », sinon la dernière ; un retour vide la pile ; par clé, la première valeur d'avant et la
dernière d'après, les écarts nuls retirés ; un exercice marque `exercice = true`, que rien ne
défait) ; `depart` (la vue : L* médian, hautes lumières écrêtées, ombres bouchées, tons neutres,
dominante, `etapes_claude` à ce moment, ou un texte sans vue) ; `indices` (`Lecon.indices`, des
remarques, jamais des refus, chacun avec sa preuve chiffrée en français : « Exposition +1,10 IL
(0,00 → 1,10) ») et `seuils`. Seuils provisoires (`Lecon.Seuils`) : exposition ±0,5 IL ; hautes
lumières −40 ou blancs −30 si le départ est écrêté à 0,5 % ou plus ; ombres +40 ou noirs +25 si le
départ est bouché à 2 % ou plus ; correction du voile +10 ; débruitage lancé, ou réduction du bruit
de luminance +20, seulement à un ISO connu d'au moins `Carnet.isoEleve` (1.3.1, la règle du carnet :
la sensibilité en nombre, `sensibilite` de la description du journal détaillé, `Carnet.iso` ; à ISO
bas, un débruitage soigne des ombres relevées ou une texture, pas un ISO trop haut ; la preuve dit
« à ISO 3200 ») ; température 400 K (10 en relatif, JPEG), teinte 10, ou une dominante nette au
départ (seulement sans retouche de Claude) ; `CropAngle` 0,5° ; Upright posé ou perspective
verticale de 10 ; surface du cadre sous 0,85 et resserrée par Claude, seulement sans rotation ni
Upright. Limite connue : les corrections viennent du journal de Claude, pas de l'état actuel ; une
copie remise hors de Claude (Historique, ⌘Z) garde au journal des corrections qui n'y sont plus, d'où
de faux indices (constaté le 21 octobre 2026 : 15 corrections lues sur une copie revenue à sa
référence, indices `underexposed` et `color_cast` faux). À recouper un jour avec les réglages
actuels.

**Le module** (`Carnet.lua`, commande `lecon`) : `garder` vérifie tout avant de toucher au registre
(trois points, un par axe ; `prise_de_vue` obligatoire ; codes `^[a-z_]+$`, 12 au plus par point ;
20 indices au plus ; textes bornés en octets), puis range la leçon sous l'original de la photo
(voir Carnet de progrès : une leçon par photo, la nouvelle remplace l'ancienne). Une photo de
« Développeur › Essais » (`Carnet.estPhotoDEssai`) n'est pas rangée (1.3.1 : constaté le 21 octobre
2026, la leçon de l'essai réel sur la dune d'essai 53709786 était rangée sous son original
43178545, une vraie photo de Dany) : `{photo, fichier, rangee = false, remplacee = false, motif =
essai, remarque}`, jamais une erreur, et `photo_lesson` le dit dans ses remarques ; sauf avec
`essai_recette`, que seule la recette envoie, sous l'entrée de la photo d'essai elle-même, comme
pour `constater` ; `lire` vérifie
l'uuid des photos demandées ; `retirer` retire aussi l'entrée qui n'a plus rien. Ni le catalogue
ni la pause, jamais rejouée.

**Invites** : `Prompts.Lecon.phrase` (seule copie) finit l'étape 9 de `retouche_pro` et
`finRetouche` (voir Consignes et invites).

**Dans la fenêtre.** L'élément `lecon` se fait de l'entrée de `photo_lesson`, jamais pour
`read_facts` (`Conversation.AXES_LECON`, `leconDemandee` : tables neuves dans l'ordre des axes, un
axe inconnu écarté, textes sur une ligne sans `**` ni accents graves) ; `leconLue` lit la réponse
(seulement la remarque de rangement, jamais « Mesuré : … », qui est pour Claude) ;
`completerLecon` (états en cours, fait, erreur) ; `outilDeLAppel` (l'élément outil du même
appel). `Stockage` écrit points et défauts en tableaux, et relit une leçon restée en cours en
erreur. Plus de carte Leçon dans le fil depuis le lot B4 : l'onglet Leçon (`Vues.lecon` sur
carte-lecon, `Fil.texteLecon` et `Fil.titreLecon`, `CARTES.lecon` en 12 et gras 12, axes en
`<EM>`, `D.leconLignes`) montre la leçon choisie (`Fenetre.leconChoisie`, remise à nil par une
autre conversation), sinon la dernière de la photo active, sinon l'aide (`Fenetre.AUCUNE_LECON`) ;
Détail… ouvre l'appel et sa réponse (`Fenetre.detailLecon`). Une seule bascule par leçon arrivée
(`Fenetre.leconVue`), jamais quand une proposition attend ou qu'un exercice est en cours ; à
l'ouverture, ou sur une autre conversation, les leçons déjà là sont marquées vues. Le tour de
Claude finit par « Leçon de la photo » (voir Fenêtre B). La case Leçon décochée : « [Sans leçon] »
(`Consignes.sansLecon`) joint par `Moteur.envoyer`. Une leçon refusée ou interrompue dit « Leçon
non rangée : … ». La recherche des conversations cherche aussi dans les leçons (axe, manque, prise
de vue).

**Constaté le 21 octobre 2026** : `getFormattedMetadata` rend les quatre clés de
`CLES_PRISE_DE_VUE_PLUS` sur les copies lues (X-H2S, X-T20 en RAF et en JPEG, iPhone 13 Pro),
aucune refusée, en textes traduits dans la langue de Lightroom (« 0 EV », « Non déclenché »,
« Priorité d'ouverture », « Priorité d'obturation », « Normal », « Moyenne pondérée », « Motif ») ;
la simulation rend ces textes. Le format d'une compensation non nulle n'est pas relevé (aucune
copie n'en a) ; rien ne l'analyse, le texte passe tel quel à Claude. `mois` et `prise_le` sont à
l'heure locale (`timeToUserFormat`), y compris pour deux photos dont l'UTC tombe le lendemain.
Commande `journal` avec `detaille` : 0,01 à 0,22 s ; `lecon garder` et `retirer` : 0,22 s (le pas
de la boucle de réception de la liaison).

## Je le fais (1.3)

Dany fait lui-même la retouche que Claude propose, pour apprendre : Claude range sa version sans
rien appliquer et donne la liste des réglages ; quand Dany a fini, il compare les deux versions.

**Le connecteur.** `preview_settings` avec `my_turn = true` (`monTour`, `Tools+Retouche.swift`,
après `developParameters`, la balance sur un point et les recalages) envoie une seule commande
`essayer` : action `appliquer`, étape « ma version (je le fais) », `instantane` « ma version »,
`exercice` et `sans_rendu`, jamais `entier`, `taille` ni `comparer` (`compare`, `size` et
`overlay` sont sans effet, `remarques_serveur` le dit). Réponse en texte seul, sans image (elle ne
consomme donc pas la remarque de l'écran) : `a_faire`, `instantane`, `photo`, `mode`, `etape`,
`remarques`, `rien_n_est_applique`, `base` et `ensuite` (« Quand l'utilisateur a fini : view_photo
avec compare = claude_version. »). Un module sans `exercice` dans sa réponse est refusé, ses
aperçus effacés. `view_photo` avec `compare = claude_version` (`ToolHandler.comparaisons` :
`before_claude` → `avantClaude`, `previous_step` → `etapePrecedente`, `claude_version` →
`versionClaude`) : les deux versions côte à côte (« À gauche ma version (Claude), à droite la
vôtre. »), `bilan.depuis` « ma version (Claude, à gauche) » avec un conseil propre à l'exercice,
et `exercice` enrichi par `JeLeFais.enrichir` sur les mesures des deux images ; toujours en
lecture seule, sans `point_af` ; un module qui ne rend pas `exercice` est refusé.
`corrections_utilisateur`, tant que l'exercice est la dernière commande de Claude sur la photo,
est annoté `exercice` (« ce n'est pas une préférence à retenir »).

**`JeLeFais.swift`** (pur) :

- `panneaux`, seule table de l'ordre et des noms des panneaux, ceux de Lightroom Classic 15.6 en
  français (constaté le 21 octobre 2026, voir `docs/aide-adobe-developpement.md` § 1) : Paramètres
  prédéfinis ; Réglages de base (Traitement, Profil, Balance des blancs, Tonalité, Présence, HDR) ;
  Courbe des tonalités ; Mélangeur de couleurs (TSL, Noir et blanc, Couleur de point) ; Color
  Grading ; Détail ; Corrections de l'objectif ; Transformation ; Outil Recadrage (un outil de la
  bande, après Transformation : choisir un mode Upright remet le recadrage à zéro) ; Flou de
  l'objectif ; Effets ; Etalonnage (Processus, puis les curseurs) ; Autres en dernier. Les sections
  de Réglages de base restent à relever (panneau replié). `groupes` range chaque groupe du
  catalogue ; les clés hors catalogue sont rangées à la main ;
- `aFaire` : `{n, panneau, section, reglage, cle, de, a, texte, avant, apres}` ; les cinq clés du
  cadre font une ligne (`Crop`, avec `cles`) ; textes à la virgule décimale, au vrai signe moins
  (« Réglages de base › Tonalité › Exposition : 0 → +0,35 », « 5 600 K », « −1,2° ») ;
- `tolerance` (provisoires, à juger sur les trois premiers exercices de Dany) : exposition
  0,1 IL ; température 150 K pour un RAW, 3 sinon ; teinte 3 ; plages −100 à +100 : 5 ; 0 à 100 :
  3 ; teintes 5° ; angles 0,3° ; bords du cadre 1 % ; modes : toute différence ; autres : 3 % de la
  plage ;
- `classer` : sept sortes (`comme_claude`, `plus_fort`, `moins_fort`, `a_l_inverse`, `oublie`,
  `ajoute`, `autre_choix`) ; un mode, une teinte ou un profil donne « autre choix » ; une table
  arrive « changée » ou « inchangée » ;
- `principal` : l'écart mesuré le plus grand une fois ramené à son seuil du bilan (aucun seuil
  nouveau ; la dominante seulement avec assez de tons neutres), puis le réglage de sa famille dont
  l'écart dépasse le plus sa tolérance, une courbe en dernier ; toujours un objet :
  `{visible: true, mesure, claude, vous, ecart, seuil, fois_le_seuil, reglage, texte}` ou
  `{visible: false, texte}`.

**Le module** (`Variantes.lua`, `Rendu.lua`). `essayer` avec `exercice` : le départ lu avant toute
écriture (`departExercice` : `etatSimple`, plus des copies de Look, des quatre courbes, de
`PointColors` et `#RemoveAreas`, et le départ des tables de Claude d'après `plan.avant`) ; une
proposition qui ne change rien refusée (« Rien à faire : la proposition est l'état actuel. Rien
n'a été écrit. ») ; l'instantané « Claude · ma version » (`createDevelopSnapshot` sur un nom
existant le met à jour, constaté), sa mémoire `exercice = { depart, claude (relue après
l'application), le }` et l'entrée du journal (`etape` « Claude · je le fais », type `exercice`,
raison, changements, note « non appliquée ») dans la même écriture ; « Claude · fin de l'essai »,
puis `noterEtatFinal` : `apresClaude` devient le départ. `essayer` n'est pas une étape (`Etapes`
ne le capture pas). `apercu` avec `comparer = versionClaude` rend la version de Claude par le chemin
des comparaisons (`rendreAvant`, `valeursAComparer`) : `valeursClaude` (la version de Claude, plus
le départ des réglages que Dany a changés hors d'elle : simples, profil et Look, courbes, couleurs
ponctuelles ; une liste vide pour les masques, yeux rouges, traits d'affinage et taches qu'il a
ajoutés à un départ qui n'en avait pas, sauf les taches de l'outil Supprimer, et `restent` : les
listes qu'on ne peut défaire) et `ecartsExercice` (`{cle, depart, claude, vous}` pour les réglages
changés ; Look par son nom ; une autre table « inchangée », « changée » ou « changée autrement » ;
les réglages que Lightroom résout lui-même exclus). Sans exercice : « Aucune version de Claude
rangée pour « Je le fais » sur cette photo : preview_settings avec my_turn = true la prépare. »
`choose_variant` « ma version » ajoute à l'étape les réglages que Dany a changés (simples, tables,
listes, `RemoveAreas` avec `RetouchAreas`), et `undo_last` les lui rend ; l'exercice survit à
`revert_to_original` et s'efface par `choose_variant` avec `delete`. `Ecriture.difference` est la
seule comparaison entre états simples. Limite : une table que Dany change à la main hors de Look,
des courbes et de `PointColors` (un flou d'objectif fait à la main) n'est pas vue, et reste dans les
deux images. Le contrat entre le serveur et le module est figé dans `Tests/Contrats/je-le-fais.json`,
lu par `ContratJeLeFaisTests.swift` et `essais-jelefais.lua` : un changement voulu se fait des deux
côtés.

**Dans la fenêtre.** `preview_settings` avec `my_turn` fait un élément `exercice`, jamais une
proposition à accepter : `enCours`, puis `aFaire` à la réponse (sa liste en tables neuves, avec
`instantane`, `photo`, `fichier`), `comparee` après `view_photo` avec `claude_version` (`ecarts`,
`commeClaude`, `resume`, `principal`, `aSavoir`), ou `erreur` ; une proposition en attente devant
une liste qui arrive passe à `faite` (« à faire vous-même »). `Stockage` écrit les listes en
tableaux, et relit un exercice resté en cours en erreur. La carte Proposition le montre
(`Fenetre.texteExercice` : la liste groupée par panneau, ✓ ou ○ devant chaque réglage ; comparé :
le résumé, l'écart principal, les écarts, ce qui reste dans les deux images, l'instantané), sauf si
une proposition est arrivée après lui ; `exerciceEtat` (« À vous · 1 réglage fait sur 5 »). Le
suivi (`Fenetre.suivreExercice`, toutes les 2 s par `Fenetre.periodique`) lit `getDevelopSettings`
sans rien écrire (`Lightroom.valeurs`, `Lightroom.lireValeurs` : comme le module décrit les
réglages ; `Lightroom.NON_SUIVIS` n'est jamais coché) ; la page ne revient pas en tête quand un
réglage se coche. Le bouton (`titreJeLeFais` : « Je le fais », ou « J'ai fini » pendant un
exercice ; `peutJeLeFais` : Claude libre et un exercice, une proposition en attente ou une photo
active) et le Mode « Je le fais » mènent à `Fenetre.jeLeFais` : `Moteur.jaiFini` pendant un
exercice, sinon `Moteur.jeLeFais` (la proposition en attente passe à `faite`, puis
`Consignes.jeLeFais(avecProposition)` ; refusé sans photo active ni proposition). Une bascule vers
l'onglet Proposition par liste et par comparaison (`Fenetre.cleExerciceVu`) ; l'aperçu de l'onglet
montre la comparaison, légendée « Claude | vous · fichier », sans ◀ ▶ (`Fenetre.apercuExercice`),
et Agrandir la montre en grand. Pas de nouvelle conversation par photo pendant un exercice.

**Constaté le 21 octobre 2026** (mesure 4, sur une copie d'Essais) : `my_turn` en 0,28 s, sans
image, `a_faire` dans l'ordre des panneaux, « Claude · ma version » apparu, réglages inchangés
(`--dump` identique) ; `claude_version` en 4,01 s, une image côte à côte, retour exact ;
`choose_variant` « ma version » puis `undo_last` : retour exact à l'état « de Dany ». Le changement
« à la main » a été fait par `apply_settings` : `corrections_utilisateur`, les noms à l'écran, le
survol de l'instantané et un vrai exercice restent à voir. Un petit désaccord d'arrondi entre
l'écart (0,55 IL) et son texte (« 0,54 IL ») n'est pas traité.

## Composition lue (1.3)

Claude lit la composition sur l'image entière, même recadrée, et propose un cadre, montré avant
d'être appliqué.

**`read_composition`** (`Tools+Composition.swift`, en lecture seule ; partie pure dans
`Composition.swift`, sans Vision ni SDK). Tout est vérifié avant l'envoi (clés de `horizon` et de
`subject` à la main par `nommer`, énumérations, `size`, `min_size`, `aspect`). La commande `apercu`
part avec `{taille 1344, cles, entier: true, photo?}` (120 s) ; une réponse sans `image_entiere`
(module d'avant la 1.3) est refusée, son fichier effacé. Les points donnés dans l'image de
`view_photo` passent dans l'image entière (`Composition.versImageEntiere`, d'après `cadre_actuel`,
repère d'aspect A, axes e1 = (cos θ, sin θ) et e2 = (−sin θ, cos θ), la formule de
`cadreDansZone`). L'horizon se mesure par `LineAngle` sur l'image entière, décodée une fois : un
angle absolu. Le sujet : celui donné, sinon les visages (au moins 25 % de l'aire du plus grand ; un
visage renversé, roulis au-delà de `roulisRenverse` 3π/4, est écarté avant), sinon la zone
d'intérêt de Vision si elle ne couvre pas plus de `zoneInteretMax` (0,5) de l'image, sinon aucun
(`sujet {source: « aucun », raison}`). Le regard : `facing` donné, sinon le lacet du visage
principal (`seuilLacet` 0,26 rad, `signeLacet` +1 : un lacet positif regarde vers la droite de
l'image). Le cadre proposé (`Composition.proposer`) : le centre affine en w ; la boîte englobante
dans l'image, les coins du sujet à 3 % des bords du cadre (`margeSujet`) ; la plus grande largeur
(au moins `min_size`), ou la taille imposée, × 0,998 (`margeArrondis`, pour les arrondis du module) ;
sans solution, lâcher dans l'ordre : sujet sur le tiers, sujet centré, horizon sur le tiers, puis
le plus grand cadre centré ; l'angle : −inclinaison, ou l'angle actuel s'il garde l'horizon droit,
sinon 0. Réponse sans image : `image_entiere`, `cadre_actuel` (crop équivalent et résumé, ou
« aucun »), `horizon` (inclinaison, angles de recadrage, hauteurs, mesure), `sujet` (source,
cadre, centre, regard), `lecture` (phrases simples, seuil 0,06), `crop` (prêt pour
`preview_settings` et `apply_settings`), `cadre_propose` (résumé « 3:2 (format d'origine), redressé
de 1,4°, 82 % de la largeur gardée », règles tenues et lâchées, conseil si presque identique),
`rien_n_est_applique`. `view_photo` donne aussi le `regard` de chaque visage.

**`preview_settings` avec `crop`** : `entier` part quand il y a un recadrage (sauf retrait, `overlay
= false` ou `my_turn`). `surimpressionDuCadre` lit `chemin_entier` en premier (le fichier est
effacé même si la suite échoue) et dessine `PreviewImages.cadrePropose` : le hors-cadre assombri
(noir à 0,5), les tiers tournés avec le cadre (blanc à 0,7 sur un trait sombre, 0,35 % du grand
côté, `traitTiersPart`), le cadre en pointillés blancs sur un trait sombre (0,4 %,
`traitCadrePart` ; tiret d'environ un quarantième du côté). L'image montrée devient l'image entière
dessinée (avec `compare` : l'état actuel à gauche) ; la réponse gagne `resume_cadre` et
`cadre_propose` en chiffres, sans `chemin_entier` ni `dimensions` ; sans cadre gardé, ou illisible,
`remarque_cadre` le dit et l'image recadrée reste. Les mesures et le bilan restent ceux de l'image
recadrée.

**Le module** (`Rendu.lua`). `apercu` avec `entier` : refusé avec `comparer` ou `point_af`, sur une
photo agrandie (`Reglages.estAgrandie`), sur une photo recadrée aux dimensions inconnues, et sur un
original absent sans aperçu dynamique, sans rien écrire ; une photo ni recadrée ni contrainte se
rend telle quelle, sans écriture ; sinon l'écriture temporaire du cadre retiré (`sansRecadrage` :
`Recadrage.AUCUN` et `CropConstrainToWarp` à 0, partagé avec le recalage), deux étapes « Claude ·
composition (image entière) » et « Claude · composition (retour) » (le retour même si le rendu
échoue), comme le recalage ; la pause n'est vérifiée que s'il faut écrire. `cadre_actuel` vient des
`Crop*` lus avant l'écriture ; `Etapes` n'est jamais appelé. `essayer` avec `entier` : le cadre
que Lightroom a gardé est relu après le rendu de la proposition (`cadre_propose`, dimensions),
puis la troisième étape « Claude · essai : image entière » ; le dessin suit ce cadre relu, jamais la
demande ; à la remise, les clés posées et absentes de `plan.avant` reprennent leur valeur d'avant,
`CropConstrainToWarp` compris. Le contrat est figé dans `Tests/Contrats/composition.json` (lire,
proposer, proposer sans image entière, refus d'une photo agrandie), lu par
`ContratCompositionTests.swift` et `essais-composition.lua`.

**Dans la fenêtre.** L'invite Composition (avant Sports, sans chiffre). `preview_settings` avec un
`crop` (sauf `reset`) fait une proposition de recadrage : la ligne « Recadrage » demandée
(`Conversation.cadreDemande`, `Conversation.LIBELLE_RECADRAGE`), remplacée à la réponse par ce que
Lightroom a gardé (`Conversation.cadreLu` : `resume_cadre`, image entière dessinée ou non). La carte
Proposition dit la raison, « Cadre : <résumé> » et ce que montre l'aperçu (`Fenetre.CADRE_DESSINE`,
ou « Rien ne change avant Accepter. » seul), puis les autres réglages. Un vrai clic sur l'onglet
Proposition remontre l'image de la proposition en attente (`Fenetre.montrerImageProposition`),
gardée jusqu'à ◀ ▶, une image nouvelle, une autre conversation ou la proposition décidée ; une
bascule ne la demande pas. Ajuster… offre `Consignes.ajustementsCadre`. Section des consignes
« ## Composition ».

**Constaté le 21 octobre 2026** (mesure 5, copies d'Essais, défait ensuite) : `read_composition`
en 0,66 à 2,22 s (1,19 s avec un recadrage à retirer) ; sur la dune recadrée en 4:5 et tournée de
2°, puis sur une copie verticale, `cadre_actuel` exact et les `Crop*` identiques au millionième
après la lecture ; la proposition acceptée pose les `Crop*` montrés, sans « Cadre réduit »
(`margeArrondis` validée) ; le lacet de Vision (révision 3, par pas de π/4) : `signeLacet` +1
confirmé à l'œil, `seuilLacet` gardé ; la calandre d'une voiture prise pour un visage (roulis −π)
faisait un cadre à 100 % : `roulisRenverse`. Un filtre de qualité sous 0,3 n'est pas fait : il
écarterait de vrais visages (0,12 à 0,28 la nuit). Une zone d'intérêt de 67 % sur une photo sans
sujet : `zoneInteretMax`. Les tiers à 0,25 % pâlissaient sur un fond clair réduit à 320 px :
0,35 %. Sur les rides du sable, une mesure « affinée » s'accrochait au bruit (écart moyen 10 à
13 px) : `LineAngle.ecartMax` 3 px (au-delà, `contourIrregulier` : l'angle vient des deux points,
et `measure_angle` comme `read_composition` le disent). Aucune copie d'Essais n'a de vrai horizon :
la dernière étape de `--recette --horizon` (le cadre appliqué) se saute avec sa raison.

## Carnet de progrès (1.3)

Les défauts de la prise de vue, comptés par mois de prise de vue : ce qui progresse, ce qui recule,
quoi travailler à la prochaine sortie. Rien n'est écrit dans le catalogue.

**Le connecteur** (`Carnet.swift`, pur). Seuils : `horizonMin` 0,5° ; `angleNul` 0,005° (le même
que `Carnet.ANGLE_NUL` du module) ; provisoires : `medianeSousExposee` 28 et `p95SousExposee` 80
(sous-exposition si les deux, sauf compensation de −0,6 IL ou moins, scène ou mode de nuit),
`partBlancPurHaut` 3 % (ciel brûlé : le tiers haut de la réduction à 512 px en blanc pur, trois
canaux à 254 ou plus) ; flou, mise au point et bruit fort par les seuils relevés de `Detail` (15,
35, 1,5), seulement à 1 024 px au moins, et par la seule copie de ces règles,
`PhotoTriee.defautsNettete` (la mise au point demande un point lu, sur une zone qui a de la
texture : voir Tri d'une séance). Le bruit fort, un défaut de la prise de vue (« garder l'ISO plus
bas »), ne se cherche et ne se compte qu'à un ISO connu d'au moins `isoEleve` (1 600, provisoire ;
`bruitCherche`, 1.3.1) ; son texte dit l'ISO (« bruit fort : 1,93 (seuil 1,5) à ISO 4000 »).
L'ISO vient de la réponse du module (`Carnet.iso`) : `sensibilite`, la sensibilité en nombre que
`Vignettes.decrireVignette` ajoute à la description (`Photos.sensibilite`, isoSpeedRating brut),
sinon `prise_de_vue.iso` de `lireReglages` (un module 1.3, seulement avec l'ouverture et la
vitesse) ; jamais le texte formaté « ISO 160 ». `view_photo` retire `sensibilite` avant Claude, qui
a ce texte. Ni le plafond de note (`Notation.plafond`, qui juge l'image : à noter après le
débruitage) ni le tri (qui dit la mesure, sans défaut de bruit) ne changent. `constatsVue` rend `{cherches, defauts [{code, mesure, texte}]}`
dans l'ordre de `PriseDeVue` (`horizon_penche` n'est cherché que sur une géométrie intacte) ;
`constatHorizon` ne rend rien pour une verticale, sous 0,5°, ou sur une géométrie touchée
(`geometrieIntacte` : recadrage tourné de moins de 0,005°, ni Upright, ni perspective, ni
distorsion manuelle, les 9 clés de `Recalage.transformationActive`). Le carnet ne se remplit que
par le serveur que lance Claude (`noterAuCarnet`, vrai seulement dans `serve()` : ni `--call`, ni
la recette, ni les tests) :

- `view_photo`, aperçu entier d'une photo sans étape de Claude (`etapes_claude.nombre` 0) : la vue
  est jugée avant le carré du point de mise au point, puis `carnet constater {photo, vue,
  vocabulaire}` (10 s) ; `constats_prise_de_vue` (textes) seulement si le module répond `note =
  true` avec des défauts ; toute erreur est tue (un module 1.2 : `view_photo` réussit) ;
- `measure_angle` et `read_composition` : `{photo, angle {inclinaison au centième, code
  horizon_penche, source}, vocabulaire}` ; l'aperçu d'une ligne ne demande les 9 clés de la
  géométrie que quand `noterAuCarnet` est vrai. Ces trois outils restent en lecture seule : ils
  n'écrivent que `carnet.json` ;
- `export_journal` avec `notebook` : `carnet lire {resume: true}` (30 s), puis `{markdown, carnet,
  catalogue?, remarque?}` ; le Markdown (`Carnet.markdown`) reprend tels quels les titres et les
  phrases du module (tableau « Défaut | mois… » en n/sur, « — » sans recherche, l'année dans
  l'en-tête quand elle change ; Ce qui progresse, Ce qui recule, À travailler) ; les entrées et
  leurs leçons ne vont jamais à Claude ; un module d'avant la 1.3 : « Le module de Lightroom ne
  connaît pas encore le carnet de progrès : installer Développeur 1.3, puis quitter et relancer
  Lightroom. »

**Le module** (`Carnet.lua`, registre `carnet.json`, format 1). Un fichier pour tous les
catalogues, chacun sa table sous son chemin ; une entrée par original (`masterPhoto`) : `{photo,
uuid, fichier, prise 'AAAA-MM', prise_le 'AAAA-MM-JJ HH:MM' (heure locale), sans_date, le, vue?,
angle?, lecons}` ; 3 000 originaux au plus par catalogue (`MAX_PHOTOS`, les plus anciens sortent) ;
un fichier illisible est mis de côté avant la première écriture ; tout ce qui sort vers une vue est
une copie neuve, vers le serveur des tableaux JSON même vides ; `Carnet.version` et
`Carnet.abonner` pour la fenêtre. `constater` : contrôles avant toute lecture (vue ou angle, pas
les deux ; vocabulaire obligatoire, 40 défauts au plus ; codes connus, 12 au plus ; au moins un
défaut cherché ; mesures finies ; textes de 200 octets au plus) ; puis les refus, dans cet ordre :
`preference` (la case Carnet décochée, avant toute lecture du catalogue ; `Preferences` et
`Recalage` ne sont requis qu'ici), `essai` (la photo ou son original dans « Développeur ›
Essais », `Carnet.estPhotoDEssai`, sauf `essai_recette`, que seule la recette envoie : la copie a
alors son entrée à elle), `etapes` (une vue sur une photo qui a des étapes de Claude), `geometrie`
(un angle sur une géométrie touchée ; accepté après une passe de tonalité). Comme `garder` : tout
lire, puis changer le registre d'un coup. Une nouvelle vue remplace l'ancienne, un nouvel angle
aussi ; les leçons restent. Le vocabulaire reçu est rangé en tête du fichier : aucune liste de
défauts n'est écrite dans le module. `Carnet.resumer(maintenant)` : les six derniers mois de prise
de vue qui ont des photos (une photo sans date compte au mois de son constat ; une photo datée après
aujourd'hui n'est pas comptée, une remarque le dit) ; par défaut cherché, `par_mois {n, sur}` (une
base propre à chaque défaut) ; la tendance compare les 2 derniers mois aux 3 d'avant, « progresse »
ou « recule » dès 15 points d'écart avec au moins 5 photos de chaque côté ; `a_travailler` : 20 %
des photos récentes et au moins 2, trois au plus, avec le conseil et « À la prise de vue : … » ;
une remarque sous 5 photos. Les phrases du résumé n'existent que dans `Carnet.lua` (`Carnet.TITRES`,
`Carnet.MOIS`, `Carnet.MOIS_COURTS`). `Carnet.photosDuDefaut(code, maintenant)` et
`Carnet.vocabulaire()` servent la fenêtre.

La case Carnet (préférence `carnet`) ne coupe encore que les constats : `lecon garder` ne la lit
pas (Dany a décidé le 24 octobre 2026 qu'elle coupera aussi les leçons, au prochain correctif). `lecon garder` refuse en revanche une photo d'essai, comme `constater`
(1.3.1, voir Leçon de la photo) : rien de « Développeur › Essais » n'entre au carnet de Dany, sauf
`essai_recette`. Rejouée, une commande `lecon` ou `carnet` réécrirait `carnet.json` :
aucune n'est dans `LightroomBridge.lectures`.

**Dans la fenêtre.** L'entrée « Carnet de progrès » est la première case de la liste
(`Fenetre.CARNET` = `'¶carnet'`, distinct de la marque « § » des en-têtes, comparée sur tous ses
octets ; la recherche la trouve par « carnet » ou « progres »). La choisir passe `Fenetre.vue` à
`'carnet'` (`Fenetre.ouvrirCarnet`) et lit le résumé dans une tâche (`Fenetre.lireCarnet`) ; la
page (`Fil.lignesCarnet`, avec les seuls genres de lignes qui existent : titre, note, outil,
claude, apercu, vide ; pas de barres ▁…█, qui demanderaient de remesurer les polices) : le titre,
la note et la remarque, le tableau en Menlo resserré à la largeur (`Fil.tableauCarnet` : colonne
Défaut de 14 caractères au moins), Ce qui progresse, Ce qui recule, À travailler, puis la ligne
bleue « Demander à Claude ce qu'il en pense › ». Elle se lit depuis son haut (`Fenetre.hautCarnet`),
▲ ▼ la font défiler. Un clic sur une rangée (`defaut`) ouvre, dans une tâche, la fenêtre des photos
du défaut (`Fenetre.montrerDefaut` : mois, fichier, constat, leçon ; le conseil ; la leçon de la
photo choisie ; « Retirer du carnet… » en `otherVerb`, puis une confirmation, puis un appel direct
à `Carnet.commande {action retirer, photos = {id de l'original}}`, jamais une ligne TCP). La ligne
d'action (`action = 'demander'`) ouvre une nouvelle conversation titrée « Avis de Claude sur le
carnet de progrès » (`Fenetre.TITRE_DEMANDE_CARNET`) et lui envoie `Consignes.carnet`. Sur la
page : Renommer… et Supprimer… ne font rien (le bandeau dit de choisir une conversation) ; une
conversation choisie, Nouvelle conversation, Envoyer, une invite ou Claude qui travaille (Accepter,
Je le fais) ramènent au fil (`Fenetre.quitterCarnet`, `Fenetre.revenirAuFil`) ; une autre photo
choisie prépare la nouvelle conversation sans quitter la page (`Fenetre.nouvelle(garderPage)`) ;
la boucle relit la page quand `Carnet.version` change.

**Constaté le 21 octobre 2026** (lecture seule par `--constats` sur les huit copies d'Essais, 14 s,
rien noté) : aucun faux constat de sous-exposition (deux photos très sombres écartées par le 95e
centile : une scène sur fond noir, une nuit éclairée), aucun vrai cas non plus ; aucun ciel brûlé
(1,3 % au plus) : les seuils restent provisoires. Deux fausses « mise au point manquée » (le point
sur du sable lisse, sur un nuage), communes au tri : d'où la texture au point de mise au point
(voir Tri d'une séance). Le tri donne une netteté 11 à 23 % au-dessus de l'aperçu, mais classe
pareil. La recette a constaté `estPhotoDEssai` sur une vraie copie (refus de motif `essai`), un
angle noté avec `essai_recette` au jour de la prise de vue, exporté puis retiré. Une scène sur fond
noir (L* médian 3,9) reste dite « presque noire » au tri : à revoir dans `Notation.plafond`, hors de
la 1.3.

**Constaté le 21 octobre 2026, après l'essai réel de la 1.3** (correctif 1.3.1 ; lecture seule par la
commande `reglages`, `--module`, pour l'ISO, et `--constats` pour le bruit, sur les quatre photos de
Dany notées « bruit » au carnet et sept copies d'Essais ; bruit : le plus fort des aplats et des
ombres, à 1 344 px réduits à 1 024) :

| Photo | ISO | Bruit | Avant 1.3.1 | Depuis |
| --- | --- | --- | --- | --- |
| 53448416 XH2S9386.RAF (reflets d'eau) | 160 | 8,99 | bruit | non cherché |
| 53448617 XH2S8387.RAF | 160 | 3,27 au carnet (0,44 après 5 étapes de Claude) | bruit | non cherché |
| 53670499 XH2S0406.RAF (Copie 1), sous-bois | 320 | 4,71 | bruit | non cherché |
| 53709534 JPEG de X-T20 (Essai) | 400 | 1,62 | bruit | non cherché |
| 53709579 RAF de X-T20 (Essai) | 400 | 1,39 | — | non cherché |
| 53709912 portrait (Essai) | 160 | 0,56 | — | non cherché |
| 53709786 dune (Essai) | 160 | 1,02 | — | non cherché |
| 53709833 groupe (Essai, 7 étapes de Claude) | 1 600 | 0,34 | — | cherché, pas trouvé |
| 53709677 scène (Essai) | 3 200 | 0,67 | — | cherché, pas trouvé |
| 53282184 XH2S7665.RAF | 4 000 | 1,93 (1,66 au carnet) | bruit | bruit |
| 53709724 fête foraine (Essai) | 12 800 | 2,09 | bruit | bruit |

La texture prise pour du bruit est toute à ISO 400 ou moins ; le vrai bruit à ISO 4 000 et plus. Le
relevé ne tranche pas entre les deux : `isoEleve` = 1 600, provisoire, à éprouver sur de vraies
photos à ISO 800, 1 600 et 3 200. L'ISO brut est un nombre (160 à 12 800 : `prise_de_vue.iso` de la
commande `reglages`) ; la simulation de la liaison le rend ainsi, jamais le texte formaté. Les
entrées déjà notées ne changent pas d'elles-mêmes : celles de 53448416, 53448617 et 53589118
(l'original de 53670499) gardent un « bruit » faux, à nettoyer avec Dany (une nouvelle vue de
53448416 ou de la copie 53670499, pas encore retouchées, remplacerait la vue ; 53448617 a des
étapes de Claude, et `carnet retirer` emporterait aussi la leçon de sa copie 53726503) ; celle de
53282184 (ISO 4 000) reste juste. La leçon de la dune d'essai 53709786, rangée sous son original
43178545 avant ce correctif, se retire par `lecon retirer {photo = 53709786}`.

## À constater dans Lightroom (1.3)

Les cinq chantiers et la fenêtre B passent les deux suites (`swift test` : 525 tests, dont 1 sauté
sans `DEVELOPPEUR_ECRAN_REEL=1` ; `scripts/tester-module.sh` : liaison 240, `essais-carnet` 20,
`essais-composition` 19, `essais-etapes` 28, `essais-jelefais` 20, `essais-lecon` 6,
`essais-registre` 19 ; fenêtre 64, `essais-carnet` 13, `essais-composition` 11,
`essais-dispositions` 26, `essais-fenetre-b` 43, `essais-gestionnaire` 5, `essais-images` 15,
`essais-integration` 9, `essais-jelefais` 18, `essais-lecon` 18, `essais-moteur` 18,
`essais-pourquoi` 15). Les mesures du 21 octobre 2026 (ligne de commande, copies d'Essais, défaites
ensuite) et la recette (91 étapes, une en échec : l'horizon de la dune, d'où `LineAngle.ecartMax` et
l'étape sautée) sont dans la section de chaque chantier. Restent à voir (et, pour l'onglet Focus
du 22 octobre 2026, la liste à la fin) :

1. La fenêtre B entière : la taille réelle (1 948 × 1 200, contenu 1 946 × 1 166, cadre
   `…-grande-4` ; D7 mesuré à 1 280 × 800 et à 1 497 × 1 200), sa place sur l'écran de
   3 440 × 1 440 (sous la barre des menus, hors du Dock), le temps d'ouverture avec 2 317 vues ;
   comparée côte à côte avec la maquette : fonds, filets, panneau, cartes, segments, polices,
   couleurs, alignements. Puis caler sur la capture `barreTitre`, `margeDialogue`, `hauteurLigne`,
   les marges, `criteres`, `propLignes`, `etapeLignes`, `leconLignes` et les hauteurs des images
   (`Dispositions.IMAGES`, images régénérées), et `Fenetre.FORME` si le contenu rapetisse.
2. Les hauteurs données à des `f:row` et `f:column` (en-tête, fil, barre, grille, liste) et au champ
   Rechercher : respectées, marges comprises ? `place_vertical = 0.5` (titre blanc du bouton bleu,
   pastilles, Mode, Style, bandeau) ; les rangées sans `fill_horizontal`.
3. Les 42 lignes de 21 du fil et la marge du bas ; la colonne auteur, l'heure une ligne plus bas ; le
   texte riche d'une ligne d'appel (Menlo 11 dans du 12, largeur réelle contre `Metriques`) ;
   « Pourquoi ? » en police 11 explicite dans la case de 21 ; les boutons d'actions et le clic du
   texte quand ils sont cachés ; aucun clignotement d'un genre à l'autre (`transform`).
4. Lisibilité des lignes de 648 points (environ 103 caractères ; une réponse ordinaire de Claude
   va à 108) : un centre de 680 à 720 garderait moins de 100 caractères (une seule valeur,
   `TAILLES.centre`).
5. Les cartes de 40 et 41 lignes en 12 (interligne de 15 constaté sur 12 lignes) et la grille de 35
   lignes de 16 de la carte Note ; leurs boutons au-dessus du bas ; textes 12 et emphases
   colorées ; les largeurs des carrés (« Laisser rejetée », « J'ai fini »).
6. Le Mode : la valeur reposée au 2e tour de la boucle (D12) dessine-t-elle « Je le fais » inactif
   et coché à la première ouverture ? Le `transform` de `Fenetre.lierRadio` sur un radio déjà coché.
   Le menu Style choisi après une demande tapée sans Retour (la simulation sait choisir dans un
   `popup_menu` depuis Mes demandes, `S.choisir`, mais le menu Style n'annule l'envoi qu'à un
   changement de valeur : son observateur, sans `Fenetre.lierRadio`).
7. Les infobulles liées (cases de la liste, bandeau) ; le bandeau de deux lignes dans une rangée de
   boutons de 26 ; les messages raccourcis entiers à l'écran.
8. Les clics sur les calques (cases, segments, étoiles, Envoyer, Accepter) ; Arrêter ou Envoyer
   quand l'autre est masqué ; les deux « Voir à 100 % » superposés.
9. La vignette JPEG de 996 × 664 dans un `f:picture` de 498 × 332 (réduite et nette) ; l'aperçu
   bord à bord dans le panneau ; les grandes images en 2x (panneau de 1 056 × 2 292 px, cartes de
   996 × 1 358 et 996 × 1 118).
10. La légende de la photo active (`Lightroom.legende` : copie, appareil, date à l'heure locale) et
    `infoPhoto`, en texte riche, `truncation = 'middle'` sur un nom long.
11. L'apparence sombre, seulement si Dany bascule lui-même son Mac : panneau, cartes, sélection,
    image « aucun aperçu », titre éteint #7F8EA3 sur #2B3F5C, emphase ambre, teintes de l'état de
    la note ; et la fenêtre quand son apparence diffère de celle de macOS (icônes `image_name` sur
    un bouton natif, titres des radios sur les aplats) ; `Chemins.ressource('images/sombre/…')`
    passé à `LrPathUtils.child`. Le menu Apparence avec une préférence inconnue : vide ou le premier
    élément ?
12. Carte Note : les étoiles posent la note (une étape « Claude · notation » que `undo_last` défait),
    un clic sur la note posée la retire, 5 ★ se posent ; Retenir et Rejeter ; Laisser n'écrit rien
    et grise Accepter ; « Accepter N ★ » change son titre blanc ; « Voir à 100 % » après une vraie
    notation avec un zoom. Sur une copie d'Essais, défait ensuite.
13. Pourquoi ? : une capture avec la fenêtre ouverte et la photo active ; `match_series` sans capture
    (`sans_avant_apres`) ; Claude Desktop seul, fenêtre fermée : aucune capture ; une capture pendant
    un `preview_settings` d'un autre client ; le ménage du dossier `Etapes` au chargement suivant ;
    la capture sautée pour calculs IA (sans modèles IA, non provocable) ; le déclencheur exact de
    `MaskGroupBasedCorrections` vide ; les images de l'étape dans l'aperçu, Voir l'avant, Agrandir.
14. Leçon : avec le vrai Claude, la leçon en fin de retouche, une seule, rien après une proposition
    seule ; la bascule vers l'onglet Leçon pendant un vrai travail, et son absence quand une
    proposition attend ; « [Sans leçon] » respecté ; dans Claude Desktop, `photo_lesson` appelé par
    les invites (sinon, le repli des consignes du connecteur) ; le format d'une compensation non
    nulle ; les seuils des indices jugés contre une vraie retouche.
15. Je le fais : les noms des sections de Réglages de base ; un vrai exercice, avec des changements
    faits à la main (Exposition, Ombres, masque IA Ciel, courbe), la liste cochée sans saccade
    toutes les 2 s, la reprise après 15 minutes, `corrections_utilisateur`, la comparaison et un
    `MaskGroupBasedCorrections` vide sans fenêtre IA ; le survol de « Claude · ma version » dans le
    Navigateur ; les tolérances sur les trois premiers exercices de Dany.
16. Composition : `--horizon` avec une copie d'Essais qui a un vrai horizon net (mer, lac, plaine ;
    à ajouter à la collection) ; les étapes « Claude · composition » à l'Historique ; le dessin du
    cadre (tiers à 0,35 %) dans l'aperçu de 405 et dans Agrandir, sur fond clair et sombre ; le
    roulis de Vision sur d'autres faux visages ; la zone d'intérêt sur des paysages sans sujet.
17. Carnet : la page dans la grille du fil (tableau Menlo aligné, « — », mois accentués) ; la
    fenêtre des photos d'un défaut (`otherVerb` de `presentModalDialog`, jamais employé ailleurs,
    puis `LrDialogs.confirm` dans la même tâche) ; « Retirer du carnet… » sur une vraie photo
    désignée par Dany ; « Demander à Claude ce qu'il en pense » ; la durée de `Carnet.resumer` et
    la taille de `carnet.json` avec quelques centaines de photos ; les cas manquants (une vraie
    sous-exposition, de la neige ou un haut blanc, une photo voulue sombre à −2/3 IL, du DR400, un
    horizon penché) ; le plancher de texture sur un ciel uni, un mur, de la neige, et une vraie mise
    au point manquée sur un sujet.
18. La photo active et la sélection revenues après un débruitage, son annulation, une variante, une
    copie virtuelle et le TIFF réimporté retiré par la recette (l'étape « débruitage » de la recette
    le vérifie ; pas encore les autres) ; `DELAI_SOURCE` (3 s) suffisant pour une collection ;
    aucune ligne « Photo active d'avant non remise » au journal. La recette ne remet pas à la fin la
    photo active d'avant elle (`show_photo` la change) : à décider.
19. Le registre des notes après la recette : la proposition de la copie RAW remise telle qu'avant
    l'étape (`notation remettre`) ; celle laissée « acceptee » le 21 octobre 2026, avant la
    correction, à remettre « à vérifier » une fois.
20. Correctif 1.3.1. Constaté le 22 octobre 2026 (recette de la 1.3.1, 86 étapes, et essai dans la
    fenêtre Claude sur le portrait d'essai, défait ensuite) : `sensibilite` en nombre dans le
    journal détaillé d'un RAF de X-H2S (ISO 160) ; la leçon de la copie d'essai refusée par
    l'outil puis rangée pour la recette ; `cull_photos` sans cible sur la photo active et
    `preview_settings` avec `reason`, sans refus, dans la proposition préparée à l'ouverture ; dans
    l'onglet Leçon, « Leçon non rangée : photo d'essai… » sous la leçon. Restent : `sensibilite`
    dans l'aperçu avec `point_af` et pour un JPEG ; `isoEleve` (1 600) à éprouver sur de vraies
    photos à ISO 800, 1 600 et 3 200 ; la carte Proposition qui offre encore Accepter quand Claude
    a appliqué la proposition à la demande écrite de Dany (vu le même jour) ; le JPEG d'essai
    53709534 rendu sans `Brightness`, `Contrast` et `Exposure` (réglages du processus 2010, sans
    effet en 15.4) et avec `MaskGroupBasedCorrections = {}` après la recette, ce que sa
    référence n'avait pas.
21. Correctif 1.3.2 (non publié ; essais dans les simulations seulement). La proposition dépassée
    (voir Proposition dépassée par une étape de Claude) : refaire l'essai du 22 octobre 2026 sur une
    copie d'essai (proposition préparée à l'ouverture, « Applique ta proposition, puis termine par
    la leçon de la photo. ») : la carte dit « Appliquée par Claude (étape « … ») », Accepter (bleu
    inactif), Refuser et Ajuster… grisés, Je le fais encore actif, l'onglet Leçon ouvert à
    l'arrivée de la leçon ; et une retouche qui change la proposition (« Remplacée par une retouche
    de Claude ») ; une proposition sur une photo de série, puis « Harmonise la série » (`match_series`
    avec `confirm`) : « Remplacée », la proposition de la référence en attente. La carte Note sans
    Passes ni Plafond (voir Carte Note B) : la grille des
    critères de 34 lignes sur la carte de 583, « Voir à 100 % » dans la rangée du bas avec Laisser,
    Changer… et Accepter (les cinq boutons et ▲ ▼ tiennent-ils dans les 498 points ?), « Accepter
    5 ★ » quand Claude propose 5 ★ ; Claude qui propose 5 ★ à une photo qui le mérite, sans jamais
    poser ni changer un libellé de couleur.
22. L'onglet Focus (non publié ; essais dans les simulations, et `--boitier` et `--focus` sur
    DSCF2402.RAF hors de Lightroom ; voir Onglet Focus). Après un nouveau démarrage de Lightroom
    (images nouvelles, aucun fichier `.lua` nouveau : un rechargement du module suffit) : le
    segment « Focus » entre Aperçu et Proposition (largeur, libellé, les cinq segments centrés), en
    claire et en sombre ; la carte Focus (trois blocs, titres en gras, une seule page pour une
    photo Fujifilm) ; aucune bascule vers Focus (proposition, note, leçon qui arrivent) ; sur la
    copie d'essai 53709912 (DSCF2402), le cadre rouge sur l'œil droit, la tête, le visage et les
    deux yeux en coins jaunes, comme Focus-Points les montre, à comparer à sa capture ; la taille
    du cadre AF d'un point unique calée le 22 octobre 2026 sur celle de Focus-Points (4 % du petit
    côté) ; celle d'une zone de 5 × 5 et d'un suivi à comparer à l'écran du X-H2S ; les textes de Lightroom tels qu'il les rend en français (dimensions,
    focale, vitesse, ouverture, ISO, compensation, programme, mesure : leur forme exacte n'est pas
    relevée ; « Exposition : <vitesse> à <ouverture> ») ; une photo d'une autre marque (iPhone) :
    sans cadre, Image et Prise de vue, « Mise au point : non lue (seulement les fichiers Fujifilm
    pour l'instant) » ; une copie virtuelle recadrée ou tournée (les cadres suivent le cadre de
    Lightroom ; un vrai clic relit après un recadrage) ; la durée (la carte « lecture… », puis la
    photo et ses cadres en moins d'une seconde attendue) et aucune demande d'autorisation de macOS
    pour l'original ; Agrandir, et Agrandir après un clic sur une ligne d'image du fil (l'image
    cliquée) ; un HEIF de l'appareil et un original déplacé (« non lue (format pas encore lu…) »,
    « non lue (original introuvable) ») ; une photo prise en recadrage 1,25× ou au viseur sport
    (les positions décalées ou non par rapport à l'image de Lightroom).
23. Mes demandes (non publié ; essais dans les simulations seulement ; voir Mes demandes). Après un
    rechargement du module (aucun fichier `.lua` nouveau) : le menu à droite de Style, à 280, sa
    flèche et son titre « Mes demandes » ; ses séparateurs et « Aucune demande gardée » grisé
    (relevés dans `AgViewUtils`, jamais vus) ; « Nom — description » coupé à la largeur du menu, la
    liste ouverte aussi large ; un choix qui met la demande dans le champ et remet le menu sur son
    titre (la valeur reposée dans l'observateur même de la clé) ; un texte tapé sans Retour, puis
    un choix : rien ne part (le champ validé par le clic sur le menu, supposé) ; le menu ouvert
    puis fermé sans choix (Échap, clic à côté) après une frappe : la demande tapée part-elle
    0,3 s plus tard, comme peut-être avec le menu Style ? ; Retour dans le champ rempli, sans y
    rien changer : la demande part-elle (`Fenetre.lierSaisie`, le transform appelé sans
    changement de valeur, supposé) ? sinon, Envoyer ; les fenêtres Ajouter…, Renommer… et
    Supprimer… (bouton grisé par `actionBinding` tant qu'un refus reste, refus dit en direct, Retour
    dans le champ Texte de six lignes) ; avec le vrai Claude, une retouche finie par « Demande à
    garder : « … » » (une ou deux phrases, sans identifiant), après la leçon, et rien de tel après
    une proposition, une notation ou une leçon seule ; « ＋ Garder la demande » au bout de la ligne
    d'actions, à droite, et sa fenêtre pré-remplie ; le bandeau de 324 (deux lignes) ; le temps
    d'ouverture de la fenêtre avec 86 vues de plus.

## Correctif 1.3.5 : huit chantiers de la feuille de route

Demandé par Dany le 23 octobre 2026 au soir, juste après la 1.3.4, au-delà de la limite d'usage à
sa demande : trois chantiers de la 1.4 (« Sauvegarde dite avant une série », « Rafales par
boîtier », « Vidéos écartées »), un de la 1.5 (« Préparer un tirage ») et les quatre de la 1.6
(« Ton style sur une photo neuve », « Rendu reproductible », « Styles en recettes fixes »,
« Apprendre de tes corrections »). Les règles et les seuils sont dans CLAUDE.md (puce « Correctif
1.3.5 »). Constaté à l'essai dans la fenêtre Claude, le 23 octobre 2026 : le connecteur lancé depuis
Lightroom ne lit pas `/Library/Preferences/com.apple.TimeMachine.plist` (il faut l'accès complet au
disque, que ni Lightroom ni Claude ne demandent) ; d'où le repli par `tmutil destinationinfo` et
`tmutil isexcluded`. La sauvegarde du catalogue, elle, s'y est lue (6 sauvegardes, la dernière le
19 octobre). Ce qui reste à constater dans Lightroom : `cameraSerialNumber` lu par
`getFormattedMetadata` (supposé ; refusé, la clé manque et les rafales restent celles d'avant) ;
le nom des dossiers de sauvegarde « AAAA-MM-JJ HHMM » dans Backups (celui de Lightroom Classic,
supposé) ; `tmutil isexcluded` sur un volume externe, sans demande d'autorisation de macOS ;
`LR_size_resolution` dans le fichier livré (300 ppp) ; une vidéo dans une collection, sautée par le
tri et la livraison. Les recettes des styles sont des recettes de départ, choisies par Claude
hors de Lightroom : à juger à l'œil sur de vraies photos et à ajuster avec Dany.

## Correctif 1.3.4 : quatre chantiers de la feuille de route

Demandé par Dany le 23 octobre 2026 : quatre chantiers tirés de la feuille de route (« Yeux : la
règle de la rafale » de la 1.4 ; « Écrêtage : luminance ou gamme », « Carte du masque » et
« Points chauds » de la 1.5), tous du côté du connecteur. « Harmoniser par lumière » (effort gros)
reste dans la 1.4. De la ligne Yeux, la partie « « À vérifier » devient un libellé de couleur,
filtrable » est écartée : Dany a choisi « rien de filtrable » (elle allait contre la règle du
correctif 1.3.2, les libellés de couleur sont ses coups de cœur).

**Yeux : la règle de la rafale** (`Notation.plafond`, `autreVueYeuxOuverts` ;
`PhotoTriee.yeuxOuverts` ; `Tri.analyser`). Des yeux fermés ne font proposer le rejet (plafond 0)
que si une autre vue du même groupe (rafale ou pile, `Tri.groupes`) a les yeux ouverts sur tous
ses sujets lus (les mêmes sujets que `yeuxFermes` : un visage d'au moins la moitié de la largeur du
plus grand, aux yeux lisibles). Sinon : 2, à vérifier, sans rejet. Le tri d'une seule photo (la
note d'abord de la fenêtre) n'a pas de groupe : il ne rejette jamais pour des yeux fermés. Le
standard de notation le dit (plancher technique).

**Écrêtage : luminance ou gamme** (`PhotoMeasurements.natureEcretage`, `clippedGamut`,
`gamutBand`, clé `ecretage_nature` des mesures). Mesuré sur l'aperçu sRGB réduit à 512 px, dès
0,1 % d'écrêtage : un pixel à un canal saturé (254 ou plus) l'est par la gamme si son canal le
plus bas est sous 220 et son C* d'au moins 30, sinon par la luminance. La lecture dit la
correction qui va : Hautes lumières ou Blancs pour la luminance ; TSL de la bande la plus touchée
(teinte TSV la plus proche des huit bandes de Lightroom) ou profil pour la gamme, en disant que
baisser les Hautes lumières éteindrait la photo. Seuils provisoires, choisis hors de Lightroom.

**Carte du masque** (`CarteMasque.swift`, `ToolHandler.cartesDesMasques`, `add_mask` avec
`mask_map`). Lightroom ne dit pas où porte un masque : le serveur fait rendre la photo avec chaque
masque seul (commande `essayer`, action `masquer`, 512 px), sa zone gardée et son effet remplacé
par un témoin fort (+1,5 IL, température −40, à pleine intensité), et compare au rendu de l'état
actuel donné par le premier appel (`comparer`). Hors du masque, les deux rendus sont les mêmes
pixels (même commande, même rendu) : un écart de 6 sur 255 dans un canal marque le masque, les
blocs JPEG du bord ne bougeant que de 1 à 3 (supposé, à constater). Puis Vision sur l'état actuel
(les visages), la lecture (part, zone, centre, part de chaque visage couverte) et les alertes
(seuils de CLAUDE.md, provisoires). Les cartes passent avant l'écriture ; elles ne la bloquent pas.
Chaque rendu témoin laisse ses deux étapes « Claude · essai » dans l'Historique, comme toute
proposition. À constater dans Lightroom : l'écart hors du masque (zéro attendu), un masque IA
calculé pour le témoin comme pour la vraie écriture, la durée par masque ; l'étape « carte du
masque » de `--portrait` en est le premier relevé.

**Points chauds** (`PointsChauds.swift`, clé `points_chauds` des mesures de `view_photo`, aperçu
entier seulement). Grille de 24 cases sur le grand côté ; une case chaude dépasse la médiane de L*
de 20 et atteint 70 ; les cases voisines forment une zone, gardée entre 0,3 % et 20 % de l'image,
écartée si 30 % de son cadre tombe dans un visage ou la zone d'intérêt de Vision (une zone
d'intérêt de plus de la moitié de l'image ne compte pas). Cinq zones au plus, de la plus forte.
Rien n'est corrigé d'office : la lecture le dit. Seuils provisoires : à relever sur une fenêtre
dans un intérieur, une nappe, un ciel blanc derrière un portrait.

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
simulation ne rend une photo sélectionnable qu'un moment après l'affichage de son dossier. Il en va
de même de la source remise (constaté le 21 octobre 2026, mesures de la 1.3 : après un débruitage,
son annulation ou une variante choisie sur une copie d'Essais, la photo active d'avant, hors du
dossier de la copie, ne revenait pas : trois fois une autre photo est restée active). D'où
`Bibliotheque.remettreSelection` (la source remise si elle a changé, puis la photo active et la
sélection refaites pendant `DELAI_SOURCE`, la photo active relue, et « Photo active d'avant non
remise » au journal si elle ne revient pas), seul chemin de `Amelioration.remettreVue` (débruitage,
détails bruts, super résolution, variantes), de `copieVirtuelle` et de `retirerReimportees` (qui
remet aussi la vue après un échec). Règle de la simulation de la liaison (`setActiveSources`) : un
dossier affiché à la place d'une source connue fait sortir du film fixe les photos hors de lui ;
la source revenue, ses photos ne se sélectionnent qu'après `S.delaiSource` (`S.visiblesSous`).
L'étape « débruitage » de la recette compare la photo active avant et après. Essayé dans
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
- `etapesClaude` : les 20 dernières retouches, avec les valeurs qu'elles ont remplacées ; depuis
  la 1.3, chacune est `{ id, nom, avant, le }` (`Ecriture.nouvelleEtape`, seul chemin d'une étape
  nouvelle ; `id` : `Ecriture.idEtape`, voir Pourquoi ? : l'avant/après des étapes) ; une étape
  écrite avant la 1.3, sans `id`, s'annule toujours par son rang, et reçoit un `id` si `recadrer`
  la complète ;
- `journalClaude` : les 200 dernières entrées du journal (date, étape, raison, changements),
  annulations et retours compris ; il reste après un retour à l'état d'avant Claude. Depuis la
  1.3, chaque entrée d'une étape porte son `etape_id` ; l'annulation, l'`etape_id` de l'étape
  défaite ; le retour, `etape_ids`. « Je le fais » y ajoute une entrée `exercice` (« Claude · je le
  fais », sans `etape_id` : rien n'est appliqué, aucune annulation ne la défait) ;
- `retoucheeParClaude` : « oui », visible et filtrable dans la Bibliothèque ;
- `proprietaireMemoire` : uuid de la photo à qui appartiennent ces champs (schéma 3) ;
- `variantesClaude` : pour chaque instantané de variante « Claude · <nom> », les réglages qu'il
  touche et sa date (schéma 4, version 2.0 ; voir Variantes) ; depuis la 1.3, celle de
  « Claude · ma version » porte aussi `exercice = { depart, claude, le }` (voir Je le fais) : un
  exercice n'ajoute aucun champ de mémoire ;
- `apresClaude` : l'état où la dernière commande de Claude a laissé la photo (étape, `editCount`,
  `lastEditTime`, réglages simples), écrit par `withPrivateWriteAccessDo`, pour relever les
  corrections faites ensuite à la main (schéma 5, version 2.1 ; voir Retouche globale : pistes de
  la 2.1). Après `preview_settings` avec `my_turn` (1.3), c'est le départ de l'exercice :
  `corrections_utilisateur` rapporte alors le travail de l'utilisateur dans « Je le fais », annoté
  comme tel (`JeLeFais.annoterCorrections`), et non une préférence à retenir.

L'avant/après des étapes (1.3) n'est pas dans la mémoire : il se garde au rendu, dans
`~/Library/Application Support/Developpeur/Etapes/`, jamais par une écriture (voir Pourquoi ? :
l'avant/après des étapes). `etape_id` n'est pas un réglage.

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
  n'écrivent rien dans le catalogue (ni pause, ni accord, ni garde-fous) ; Claude propose de 0 à
  5 ★ (au-delà, refus du serveur, puis du module ; jusqu'à la 1.3.1, jamais 5 ★), et ne touche à
  aucun libellé de couleur sans la demande de l'utilisateur. Les notes que l'utilisateur pose depuis la
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
- Liaison fermée (1.2) : une ligne sans le jeton privé de la liaison, ou avec un autre, est refusée
  avant toute commande, `ping` compris, donc avant la pause et « Proposer d'abord » ;
  `depuisLightroom` n'est jamais reçu du réseau (voir Liaison fermée).
- Peau (1.2) : `add_mask` refuse, avant tout envoi, un masque de peau lissé au-delà de la dose
  « Adoucir la peau (Lite) », intensité comprise, ou à netteté négative, sans
  `smoothing_requested` (voir Peau).

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

1.3 : l'entrée du journal de `choisir` s'écrivait avant la pose, donc sans ses changements
(`export_journal` ne les montrait pas) ; elle est réécrite après la pose avec ses changements, par
une écriture privée, et retirée avec l'étape si la pose ne prend pas. La comparaison
(`rendreAvant`) remet aussi `RetouchInfo` au retour. L'exercice « Je le fais » est une variante,
« Claude · ma version », avec sa mémoire `exercice` ; `choisir` « ma version » touche aussi les
réglages que Dany a changés depuis (voir Je le fais). La photo active d'avant revient par
`Bibliotheque.remettreSelection` (voir Bibliothèque).

## Harmonisation d'une série (`match_series`)

Le serveur mesure la référence et chaque photo sur un aperçu d'analyse (`apercu`, avec
`Temperature` et `Tint`), calcule les écarts (exposition par la luminance médiane, dominante a* et
b* des tons neutres, contraste P95 − P5), puis propose des corrections relatives (`appliquer`,
`relatif`). Avec `confirm`, deux passes : après la première, une nouvelle mesure, puis une
correction de l'écart restant. Depuis la 1.3, ses `appliquer` portent `sans_avant_apres` : une
série n'est jamais ralentie par l'avant/après des étapes (voir Pourquoi ?).

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
