# Règle : retouche générative par Fibo 2

Sortie du CLAUDE.md principal (qui y renvoie). À lire avant de toucher à `generative_edit`,
`Generatif.swift` ou au module de la retouche générative.

- **Retouche générative par Fibo 2** (`generative_edit`, le 36e outil, titre « Retouche générative
  (Fibo 2) », demandé par Dany le 29 octobre 2026 : « si tu ne peux pas le faire dans Lightroom
  (remplacer un pantalon par une jupe), exporte, fais faire par Fibo 2, importe et fais le reste par
  le MCP ») : le seul chemin génératif du projet, **seulement sur demande de Dany, jamais
  d'initiative** (description de l'outil, `ServerInfo.instructions` : « Changer un objet, un
  vêtement : generative_edit, sur sa demande. », et une puce des garde-fous de `Consignes.texte`).
  Fibo 2 tourne sur ce Mac par mflux (`~/.local/bin/mflux-generate-fibo2-edit`, mflux 0.24 ;
  modèles `briaai/Fibo-2.0-dev` et `briaai/Fibo-2.0-edit-turbo`, licence CC BY-NC) ; rien ne part
  sur Internet sauf le premier téléchargement du modèle. Déroulé (`Tools+Generatif.swift`) :
  exécutable vérifié d'abord (sinon refus, « uv tool install mflux », rien d'envoyé), commande `etat`
  (pause, « Proposer d'abord » sans `confirm` : refus avant tout calcul) ; la commande `exporter`
  existante (TIFF, `AdobeRGB`, 16 bits, `metadonnees = 'all'`, `sans_lieu = false`, taille réelle,
  sans filigrane ni réimportation, avec `etape` « Claude · Fibo 2 » et `raison`, la consigne) vers un
  dossier neuf `<racine>/Temporaire/Fibo/<uuid>/`, effacé à la fin (`defer`, et à l'arrêt du serveur
  par `ToolHandler.travailFibo`). Une exportation vers `Temporaire/Fibo` n'est pas une livraison
  (`Livraison.exporter`) : son accord se demande au nom de `generative_edit`, avec l'étape et la
  consigne (jamais `export_photos` : Claude aurait rappelé une vraie livraison) ; les garde-fous des
  photos (`verifierProtection` : copies virtuelles seulement, libellé protégé, rejetées) s'y
  appliquent avant tout calcul ; une photo jamais exportée y est notée `apercuSeulement`, comme après
  un aperçu (`Photos.exportee` reste faux), et le champ n'est jamais effacé ; un PNG sRGB 8 bits d'environ 1 Mpx (`Generatif.tailleCible` : même
  proportion, côtés multiples de 16) et, avec `region`, un masque PNG blanc sur noir élargi de
  `margeRegion` (3 % du petit côté) ; mflux par `Process`, sans shell, arguments en tableau, stdin
  vide, sortie dans un tuyau (stdout du serveur au protocole), progression tqdm (« 12/50 [ ») vers
  `avancer` (client et barre de Lightroom), annulation par `contexte.verifier()` et délai de
  `Generatif.delaiMax` (900 s) : SIGTERM puis SIGKILL après 3 s ; mflux en cours et dossier de l'appel
  tenus par `TravailFibo` (`ToolHandler.travailFibo`), que `serve()` arrête à la fin de l'entrée
  (Lightroom quitté, module rechargé, Claude Desktop fermé : mflux tient plusieurs Go) ; erreurs
  expliquées (`Generatif.expliquer` : accès refusé reconnu à « 401 Client Error », « 403 Client
  Error », « Unauthorized », « Forbidden », jamais à « 401 » seul, qu'écrit une barre de
  téléchargement ; modèle incomplet, réseau, sinon le code et les trois dernières lignes) ; qualité `balanced` (par défaut depuis le soir du 29 octobre 2026 : `--steps 30 --cfg-end 0.6`), `normal` (`--steps 50`) ou `fast` (Turbo, 4 étapes, la copie locale
  du cache HF par `--model <instantané> --base-model fibo2-edit-turbo`) ; graine toujours passée (au
  hasard sans `seed`, rendue). Recomposition (`Generatif.swift`, pur, testé) : la zone changée est
  l'écart entrée-sortie à la petite taille, lissé en 3 × 3 (5 × 5 effaçait un trait d'un pixel), au-delà
  de `seuilEcart` (0,10, provisoire), points isolés retirés (majorité en 5 × 5), élargie
  (`elargissement` 2 %) et fondue, coupée par `region` ; sous `partMinimale` (0,05 %), refus, rien
  d'importé. La zone de mélange (`Generatif.zoneDeMelange`) : avec `region`, toute la zone donnée
  (élargie, fondue), Fibo n'ayant travaillé que là ; sans elle, la zone changée, ou toute la sortie
  au-delà de `partSortieEntiere` (60 % de l'image), ce que la réponse dit (`remarqueSortieEntiere`, en
  part de l'image) ; hors de la zone, les pixels du TIFF exporté restent identiques au bit près. TIFF
  final 16 bits Deflate (`compressionTIFF` 8, comme Lightroom ; le LZW grossissait de 30 %) avec le
  paquet XMP entier du TIFF exporté (`lireMetadonnees`, `CGImageDestinationAddImageAndMetadata` :
  libellé, texte alternatif, mots-clés hiérarchiques gardés ; la compression au premier niveau des
  options, constaté) et ses dictionnaires Exif, IPTC, GPS et TIFF, nommé `<base>-Fibo` (jamais
  doublé). Puis la commande `importerGeneree` du module
  (`Livraison.lua`), contrat identique des deux côtés : paramètres `{ photo, chemin, nom, consigne,
  confirme }` (la `reason` jointe à `consigne` après « — ») ; refus en pause, en « Proposer
  d'abord » sans `confirme`, et d'un chemin hors de `<racine>/Temporaire/Fibo` (`Livraison.dansFibo` :
  ni « . », ni « .. », ni segment vide), qui n'est pas un `.tif`/`.tiff` ou qui manque, et d'une photo
  protégée (`verifierProtection`, comme à l'exportation) ; destination le dossier de l'original
  (`masterPhoto` d'une copie virtuelle ; refus de l'original introuvable), `<nom>.tif` puis `-2`,
  `-3`… (jamais d'écrasement) ; `LrFileUtils.copy`, puis `catalog:addPhoto(chemin, original, 'above')`
  dans `Ecriture.ecrire` (« Claude · Fibo 2 ») ; une photo d'essai (elle ou son original dans
  « Développeur › Essais ») n'est pas empilée avec le vrai original (`addPhoto(chemin)`), elle va dans
  les mêmes collections Essais, dans une écriture suivante (le Suivi et le carnet la voient comme une
  photo d'essai) ; tout chemin importé se note pour `retirerReimportees` (la recette la retire) ; un
  refus de Lightroom met la copie à la Corbeille ; la photo ajoutée se cherche par `findPhotoByPath`
  si `addPhoto` ne la rend pas ; journal de Claude de la nouvelle photo (« Claude · Fibo 2 :
  <consigne> », `retoucheeParClaude`) par `Ecriture.ecrireMemoire`, sans étape : `undo_last` ne la
  retire pas (Photo › Retirer du catalogue, à la main) ; photo active par
  `Bibliotheque.selectionnerAvecSource` ; sous « Copies virtuelles seulement », une copie virtuelle
  « Claude » de la nouvelle photo, qui devient la photo active (les finitions se font sur elle) ;
  fichier temporaire effacé. Réponse `{ id, fichier, chemin, empilee, active }`, plus `essai` pour une
  photo d'essai (`empilee` faux) et, sous « Copies virtuelles seulement », `copie_virtuelle` (`id` est
  alors celui de la copie) et `photo_fibo` ; le connecteur les reprend dans `nouvelle_photo` et dit
  où se font les finitions (`ToolHandler.aSavoir`). Sans accord récent de l'exportation, l'accord
  d'`importerGeneree` se demande avec l'étape « Claude · Fibo 2 » et la consigne. L'accord dans Lightroom de l'exportation vers `Fibo` vaut une fois pour
  l'importation de la même photo dans les 3 h (`Livraison.exportsFibo`, `DUREE_GENEREE` : 4
  modifications, Fibo 2 puis SeedVR2, 15 min au plus chacun) : Dany n'est pas sollicité deux fois. `importerGeneree` n'est pas une lecture (absente de
  `LightroomBridge.lectures`) : rejouée une seule fois, et seulement si elle n'a pas été livrée
  (`.unreachable`, puce Mémoire ci-dessous). `Menage.TEMPORAIRES` comprend `Fibo`. L'exécutable,
  le cache HF, la racine et le délai sont injectables (`ToolHandler.fibo`, struct `Fibo`, **nil par
  défaut** comme `lireEcran` : generative_edit refuse alors sans rien lancer ; seul `outils()` de
  main.swift pose `Fibo()`, pour `serve()` et `--call`) : les tests passent un faux script shell qui
  écrit un PNG, jamais le vrai mflux (`GeneratifTests`,
  `essais-generatif.lua`, avec `catalog:addPhoto` dans la simulation de la liaison : refusé hors
  d'une écriture, fichier exigé, position `'above'` ou `'below'`, photo illisible dans l'écriture
  qui l'a créée, supposé). **Constaté le 29 octobre 2026** (essai réel, après les corrections de
  mémoire : copie d'essai de DSCF2402.RAF, 26 Mpx, Lightroom ouvert, « tuque rouge à pompon »,
  `region` {0,27, 0,09, 0,18, 0,17}, graine 42, qualité normale) : réussi ; recadrage 2 247 ×
  1 456 px, sortie de Fibo 1 280 × 832, SeedVR2 7B (× 1,8), 2,7 % de la photo changés, tuque nette,
  raccord invisible à 100 % ; 471 s en tout, dont 417 s Fibo 2 et SeedVR2 ; 32,4 Go libres au départ,
  jamais sous 72 % libre ; chaque commande progression a répondu (0,00 s) ; `importerGeneree`
  11,96 s (copie par `LrFileUtils.copy` dans le dossier de l'original), `addPhoto` empilé au-dessus de
  l'original, photo devenue active ;
  masque PNG RVB accepté par `--mask-path` ; `--low-ram` et `--vae-full-precision` acceptés par
  mflux 0.24 ; SeedVR2 7B téléchargé et lancé avec `--low-ram`. Reste à constater dans Lightroom :
  la place dans la pile (repliée ou non), la photo ajoutée relue juste après l'écriture, un chemin
  déjà au catalogue refusé, la sélection de la nouvelle photo quand la source est une collection
  (Essais), `addPhoto` sans pile et la copie virtuelle de la photo importée ; côté mflux, le seuil
  de la zone changée sur d'autres sorties, la durée en qualité rapide et la mémoire du connecteur
  (environ 0,7 Go pour 40 Mpx, estimé).
  Ajouts du même jour (demandés par Dany) : avec `region`, Fibo reçoit un **recadrage** autour de la
  zone (`Generatif.recadrage` : la zone agrandie de `margeContexte`, 50 % de sa taille de chaque côté,
  et d'au moins `contexteMin`, 35 % du petit côté, coupée aux bords sans être déplacée (garde plus
  souvent la taille native), jamais plus allongée que 8:1 (`rapportMax` : le petit côté grandit
  dans la photo, au lieu d'une entrée déformée) ; au-delà de 1 Mpx `tailleCible`, chaque côté borné
  au natif, sinon la taille native ramenée aux multiples de 16 par `ajuster16` (resserrée hors de
  la zone et de son fondu, sinon agrandie dans la photo, sinon gardée entière avec une entrée au
  multiple inférieur : jamais une bande de la zone coupée au bord), jamais plus grand), masque et zone de mélange
  dans son repère (`regionDansRecadrage`), recollé à sa place (`Generatif.recomposer` par `Piece`,
  l'une après l'autre ; sans zone, toute la photo, comme avant) ; **`edits`** (1 à 4 modifications
  `{label, instruction, instruction_fr, region}`, `Generatif.modifications` : jamais avec les
  arguments simples, une zone chacune dès deux, une `region` qui n'est pas un objet refusée, refus
  d'un chevauchement avant tout envoi, `chevauchement`, puis, après l'exportation, de deux zones
  dont les bords fondus se recouvriraient, `zonesTropProches` et `etendueMelange` : la seconde pièce
  effacerait le bord de la première), un
  passage de Fibo par modification depuis le même TIFF, une seule importation ; `instruction_fr`
  exigée, la consigne du module en français (`consigneJournal`) ; le recadrage seul (avec son
  masque) est le seul chemin avec une zone : le mode à deux images (`context` = `full_and_crop`,
  photo entière et recadrage, sans masque) est retiré le 29 octobre 2026, après l'essai réel (771 s,
  une seconde tête de la personne redessinée dans le recadrage, que la garde d'alignement du
  pourtour n'a pas vue : 2 % changés, pièce reprise) ; un `context` reçu est refusé comme tout
  paramètre inconnu ;
  **toujours `--low-ram`** (normal et rapide), `--vae-full-precision` en qualité normale, jamais
  `--quantize` (ni `-q`) ni `--step-cache-ratio` ; **SeedVR2** (`Fibo.seedVR`, par défaut à côté de mflux :
  `mflux-upscale-seedvr2 --model seedvr2-7b --resolution <côté court natif> --low-ram`, qui
  implique `--vae-tiling`) quand la
  sortie doit être agrandie de plus de `seuilSeedVR` (1,25) sur ses deux côtés et `upscale` vrai,
  avec une zone seulement, × `facteurMaxSeedVR` (4) et `pixelsMaxSeedVR` (16 Mpx) au plus
  (`Generatif.seedVR`, provisoires), sinon, absent ou en échec, mise à la taille ordinaire dite
  (`remarque_seedvr2`) ; une seule barre de 0 à 100 % (`Generatif.Avancement` : poids 3, 10, 70,
  15, 5 ; `tempsRestant` rien avant deux étapes, `texteProgression`, `BarreFibo`, qui ne recule
  jamais, renvoie la commande progression toutes les `relecture` (3) s même sans changement pour
  lire la croix, la relit avant `importerGeneree` et finit à 100 % ; les barres de chargement et de
  téléchargement ne comptent pas, `estUnChargement`), processus par `ToolHandler.executer`
  (`FinProcessus`, un seul lecteur de la sortie) ; un signal qui termine le serveur arrête mflux
  (`TravailFibo.arreterAuxSignaux`, posé par `serve()`).
  **Mémoire** (constaté le 29 octobre 2026, essai réel) : sans `--low-ram`, Fibo 2 a pris environ
  39 Go sur les 48 du Mac Studio ; Lightroom ouvert ne répondait plus (chaque commande progression
  refusée pendant 13 min, puis `importerGeneree` « Lightroom ne répond pas »), le TIFF final a été
  effacé avec le dossier temporaire, puis le Mac a gelé (une nuit plus tôt, deux mflux à 36 Go
  chacun : JetsamEvent). Mesures, Lightroom fermé (1 248 × 832, 6 étapes, `/usr/bin/time -l`,
  « peak memory footprint ») : défaut 39,0 Go (58 s) ; `--vae-full-precision` 39,2 Go ; `--low-ram`
  20,6 Go (54 s), image identique au pixel près ; `--low-ram --vae-full-precision` 20,6 Go,
  identique à `--vae-full-precision` seul ; `-q 8` 38,0 Go et moins fidèle (écart moyen 1,2, max
  146). **Un seul calcul à la fois** sur ce Mac, quel que soit le serveur (Claude Desktop, la
  fenêtre Claude, Claude Code en terminal : chacun sa `FileOutils`) : `flock` sur
  `<racine>/Temporaire/fibo-en-cours.verrou` (hors de `Temporaire/Fibo`, que le ménage efface ; le
  noyau le rend à la mort du processus), pris d'abord et tenu tout l'appel
  (`Fibo.prendreVerrou`), sinon refus avant tout envoi (« Un autre calcul de Fibo 2 est en
  cours… ») ; puis un mflux lancé hors du serveur (Fibo 2 Studio, le Terminal), que le verrou ne voit pas : `Fibo.autreCalcul` (`pgrep -f "mflux-(generate|upscale)"`, injectable, jamais le vrai dans les tests), refus « Fibo 2 calcule déjà sur ce Mac… » avant tout envoi (constaté le 29 octobre 2026 : un calcul de Fibo 2 Studio en même temps que l'essai a fait geler le Mac). **Plus de garde de
  mémoire** (retirée le 29 octobre 2026 au soir, à la demande de Dany : « le Mac créera du swap au
  besoin ») : ni refus ni saut faute de mémoire libre, ni au départ, ni avant une modification, ni
  pour SeedVR2 (lancé dès que ses autres conditions sont remplies), et la mémoire du Mac n'est plus
  lue (`memoireDisponible`, `memoireMinimale` 24 Go, `memoireMinimaleSeedVR` 16 Go,
  `Fibo.memoireLibre`, `memoire_libre_go`, `remarque_memoire` retirés) ; `--low-ram` et un seul
  calcul à la fois suffisent. **Résultat gardé** :
  `importerGeneree` réessayé une fois après `Fibo.delaiReessaiImport` (5 s), seulement s'il n'a pas
  été livré (`nonLivree` : `.unreachable`, connexion refusée ou ping sans réponse) ; jamais sur
  `.timeout` ni `.interrupted` (la commande est partie : la rejouer importerait deux fois), ni sur
  un refus du module ; en échec (ou sans `id`), le TIFF final est déplacé vers `<racine>/Fibo non
  importées/<nom>.tif` (`-2`…, `garderNonImportee` par `renamex_np` et `RENAME_EXCL` : un nom pris
  entre-temps fait passer au rang suivant), hors de `Temporaire`, et l'erreur dit son chemin et
  « Fichier › Importer » à la main ; une commande partie sans réponse (`peutEtreExecutee`) ajoute
  que la photo est peut-être déjà dans la pile de l'original, à vérifier avant d'importer, et si le
  TIFF temporaire a disparu, qu'elle a sans doute été importée (jamais « rien n'a été importé ») ;
  un déplacement impossible laisse le TIFF seul dans le dossier de l'appel (le reste effacé), avec
  son chemin et l'avis que le prochain chargement du module le videra ; `uninstall.sh --tout` garde
  « Fibo non importées » s'il n'est pas vide. `BarreFibo` compte les
  progressions sans réponse de suite (`ToolHandler.avancer` rend vrai, faux ou nil) : dès
  `echecsSignales` (3), `remarque_lightroom` (« Lightroom ne répondait plus pendant le calcul :
  mémoire ? »), sans arrêt ; la même phrase suit toute erreur levée après le premier envoi de la
  barre (mflux en erreur, hors délai, sortie illisible, importation), et
  un mflux arrêté par un signal (`FinProcessus.echec` avec `signal`) le dit (« le système l'a sans
  doute tué faute de mémoire »).
  Restent à constater : la mémoire en pointe de SeedVR2 7B avec `--low-ram`, et ses bornes (× 4,
  16 Mpx).
  **Masque de Lightroom** (`mask`, demandé par Dany le soir du 29 octobre 2026 : avec un rectangle
  pour un arrière-plan, Fibo avait gardé un panneau et un « R » de l'ancien fond) : une seule
  modification, refusé avec `region` (l'un ou l'autre), avec `edits` et dans `edits` ; la zone comme
  un masque d'add_mask (kind, part, person, invert, combine…), sans effet ni réglage
  (`ToolHandler.zoneParameter`, `areaParameter` et `composantsParameter` communs avec `maskParameter`,
  `proprietesZone` et `proprieteComposant` pour les deux schémas ; `prelever(_:photo:)` et `recalages`
  comme add_mask, et `verifierVersion` de `refine`, 15.5, avant tout envoi). Lu **après**
  l'exportation (en « Proposer d'abord » avec l'accord dans Lightroom, l'accord se demande à
  l'exportation, avant ces rendus : rendus avant, ils se perdaient et se refaisaient au rappel ; un
  refus du masque vient donc après une exportation, effacée avec le dossier de l'appel) : deux
  commandes `essayer` (action `masquer`, « Claude · masque pour Fibo 2 », `taille` 0, pleine
  résolution ; `temoin`, qui fait sauter `Liaison.demanderAccord` dans `Rendu.essayer`, comme pour
  les cartes de `mask_map`, et lui fait dire `personnes_non_reconnues`, `Plans.lirePersonnes`, la
  lecture que `Retouche.verifierPersonnes` reprend) : le témoin sombre puis le clair
  (`Generatif.temoinsMasque` : `temoinSombre`, −2 IL et plus froid, qui change les blancs brûlés ;
  `temoinClair`, +1,5 IL, noirs +30 et plus froid, qui change le noir pur ; jamais deux réglages de
  sens contraire dans un témoin : −2 IL et noirs +30 s'annulaient dans une plage de tons sombres,
  trouvaille de la relecture), l'état actuel avec le premier (`comparer`) ; rien n'est gardé dans
  les réglages, quatre étapes « Claude · essai » restent dans l'Historique. Une personne non
  reconnue est refusée dès le premier rendu ; les remarques du module vont dans `masque.remarques`.
  Masque binaire : l'union des écarts des deux témoins au seuil de 6 (`seuilMasque`,
  `ajouterAuMasque`), nettoyé (`nettoyer` : îlots retirés et trous bouchés de moins de
  `aireNettoyage` pixels, un carré du grand côté sur 512 (`grilleNettoyage`), 169 px à 6 240 px, en
  8-connexité, suivi borné ; un trait fin mais long, une mèche, une sangle, le jour entre le bras et
  le corps, garde ses pixels : l'ancien nettoyage par blocs les effaçait, trouvaille de la
  relecture), refusé si moins de 0,01 % de la photo est dans le masque ou hors de lui
  (`partMasqueMin`, `refusMasque` : un petit sujet, un oiseau de 0,4 %, passe), remis à la taille du
  TIFF au plus proche voisin s'il le faut (son opacité en bilinéaire, `redimensionnerOpacite`, puis 0
  hors du binaire remis à la taille et élargi) ; son cadre englobant tient lieu de `region` (recadrage,
  SeedVR2, dont la remarque d'un masque trop étendu ne conseille jamais region : `avecMasque`) ; Fibo
  reçoit la part couverte de chaque pixel d'entrée, élargie de `margeMasque` (1 %) ; mflux grise
  lui-même la zone (jamais remplie par le connecteur) ; zone de mélange en pleine résolution : **le
  bord doux de Lightroom** (`Generatif.OpaciteDuMasque`, demandé par Dany le 29 octobre 2026 au
  soir : « adoucis-le »), l'opacité du masque IA lue dans les mêmes rendus, avant qu'ils ne soient
  libérés (`masqueDesRendus` rend `opacite`, un octet par pixel ; le dernier témoin resservi, le
  premier redécodé) : par témoin et par canal, l'écart en log2 de la lumière linéaire
  (`opaciteEpsilon` 0,002) ; l'effet plein, médiane des écarts dans l'intérieur sûr (à plus de
  `opaciteErosion`, 0,3 % du petit côté, 12 px, du dehors), par valeur de l'état actuel (table de
  256, cases centrées sur 0, lissée) ; α par moindres carrés sur 2 témoins × 3 canaux avec le
  binaire en a priori (`opaciteAPriori`, λ 0,3) ; rampe renforcée en smoothstep (`opaciteBas` 0,03,
  `opaciteHaut` 0,35 : de 0,12 à 0,85, un voile gris de l'ancien fond restait) ; lissage d'un pixel
  (`lisserOpacite`, deux passages, en entiers) ; calculé sur tout le binaire élargi de
  `opaciteMarge`, 2 px (`classe`, distances par `distanceEchiquier`), jamais forcé plein à une
  profondeur fixe (relecture du même soir : un radial, un dégradé ou un bord affiné restent partiels
  sur des centaines de pixels, et la profondeur pleine de 50 px, `opaciteProfondeur`, retirée, y
  faisait une marche ; pleine seulement là où α atteint `opaciteHaut`) ; là où les témoins ne disent
  presque rien (Σ f² sous `opaciteAppui`, 1), repli vers l'ancien bord, le binaire fondu
  (`fonduBinaire`, `fonduMasque` 0,15 %), sur toute sa largeur (`margeOpacite` : 2 px, ou
  `etendueFondu` s'il est plus large, 6 px à 4 160 px ; la part de repli étendue en carré,
  `maximumCarre`) ; exactement 0 au-delà (la photo y garde ses pixels au bit près ; `zoneDuMasque`
  lit l'opacité). Sur une longue rampe, l'effet plein relevé dans un intérieur sûr qui a des pixels
  partiels est sous-estimé : la zone y monte plus tôt que Lightroom, sans marche ; et le binaire n'y
  commence que vers 10 % d'opacité (le seuil), d'où un départ en saut au bord, comme avant. Masque de Fibo inchangé (le binaire élargi de 1 %). Relevé
  sur les vraies images de l'essai (labo du 29 octobre 2026, quatre bords comparés par deux juges :
  fondu large asymétrique, filtre guidé, opacité décontaminée, celui-ci) : le bord binaire tombait
  à 0 à 20 % d'opacité de Lightroom, mèches fines mangées ; le masque IA est une rampe d'environ
  20 px, des partiels jusqu'à 48 px dans le binaire ; avec le bord doux, mèches gardées sur le
  nouveau fond, poncho net, aucun pixel du sujet touché à plus de 2 px du masque (5,36 millions) ;
  reste un léger voile de l'ancien fond là où Lightroom met une opacité moyenne. Masque binaire et
  opacité en 0,53 à 0,59 s sur 26 Mpx (décodages compris, `-O`), 1,04 Go en pointe pour tout le chemin
  avec deux recompositions ; calculée sur tout le masque (relecture du même soir), 0,7 à 0,9 s et
  1,2 Go, la même opacité sur ce portrait à 326 pixels près (au fond, à plus de 50 px du bord, 25
  niveaux au plus). Seuils provisoires : un seul portrait ; à éprouver sur un sujet clair
  devant un fond sombre et sur un ciel. Réponse `masque` (kind, inverse, part, cadre,
  `calcule_par`, lecture, remarques). Durée relevée sur 26 Mpx, compilé pour le débogage : masque
  binaire 3,4 s, nettoyage 5,3 s, masque de Fibo 2,0 s, opacité et zone de mélange de l'ordre de
  22 s (le test ne borne strictement qu'en publication). **Constaté le 29 octobre 2026 au soir**
  (essai réel, Lightroom ouvert, nouvelle copie
  d'essai de DSCF2402.RAF, 26 Mpx, `mask` `background`, Times Square, graine 42, qualité rapide,
  demandée par Dany : « fais les tests en turbo mode ») : réussi en 41 s, dont 22 s de Fibo 2 ;
  masque de 79,2 % de la photo, cadre de toute la photo, aligné au TIFF exporté (aucun décalage
  visible au bord) ; tout l'ancien fond remplacé (ni panneau ni « R »), la personne intacte ;
  80,8 % changés ; SeedVR2 non lancé (× 5,0), mise à la taille ordinaire ; le bord des cheveux était
  net mais découpé (pas de mèches fines sur le nouveau fond) : repris par le bord doux ci-dessus,
  vérifié sur ces images (recomposition refaite par le code du connecteur), puis par un second essai
  réel le même soir (nouvelle copie d'essai, Turbo, 40 s) : mèches fines gardées sur le nouveau fond,
  plus d'effet découpé ; essai défait (photo retirée, TIFF à la Corbeille). Seuils provisoires ; restent à constater dans Lightroom les deux témoins sur un
  noir pur, un fond très sombre et un blanc brûlé, et une personne non reconnue.
  Voir `docs/SPEC.md`, Retouche générative par Fibo 2 (Masque de Lightroom).
  **Cinq fonctions de Fibo 2 Studio** (demandées par Dany le soir du 29 octobre 2026 ;
  `~/Developer/Fibo2Studio` se lit seulement, jamais d'écriture) : (1) **fiche de FIBO-vlm**
  (`structured_prompt`, vrai par défaut : faux quelques heures le 29 octobre 2026 au soir, après 39,7 Go et 402 s en swap et un mode masqué en échec, puis remis vrai avec le réglage léger ci-dessous, après son essai réel de bout en bout du 29 octobre 2026 au soir (nouvelle copie d'essai de DSCF2402.RAF, arrière-plan Times Square, Turbo, graine 42) : fiche en 35 s, appel en 74 s, environ 10 Go résidents pendant la fiche ; fiche fidèle (femme, lunettes, cape noire, Times Square) et rendu plus vivant (passants à l'échelle, taxis)) : avant chaque passage de Fibo, `briaai/FIBO-vlm` (environ
  8 Go) rédige une fiche VGL (légende du résultat et `edit_instruction`), passée à mflux par
  `--prompt-file` ; le Python de mflux (`Fibo.python`, par défaut à côté du vrai exécutable, lien
  suivi : celui des essais n'en a pas) en `-I`, sur `Generatif.scriptFiche` écrit dans le dossier de
  l'appel (`fiche-fibo-vlm.py`, tâche edit), sans shell, par `ToolHandler.executer` (annulation,
  `TravailFibo`), `Fibo.delaiFiche` (180 s ; 300 avant le réglage léger), hors ligne (`HF_HUB_OFFLINE`,
  `HF_HUB_CACHE`) ; l'image d'entrée de Fibo grisée dans la zone comme mflux (`Generatif.griser`,
  binaire à 128, gris 128) avec `--use-mask`. **Réglage léger** (mesuré le 29 octobre 2026 au soir,
  Mac de 48 Go, Lightroom ouvert, un calcul à la fois, `/usr/bin/time -l` : 33 à 45 s et 15,6 à
  16,0 Go de pointe en mode masqué, deux graines, et 58 s et 16,7 Go sans zone, au lieu de 402 s et
  39,7 Go) : `mx.set_cache_limit`
  à 4 Go avant le chargement (la pointe venait du cache de tampons de MLX, non borné : 32,7 Go ;
  `lm_head` recopié en float32 à chaque jeton) ; `FiboVLM(quantize=8)` (5,5 Go actifs au lieu de
  8,9, fiche aussi fidèle ; 4 et 6 bouclent) ; `max_tokens` 1 536 (fiches de 568 à 1 012 jetons ; une
  boucle coupée vers 115 s) ; **une seule génération** (`_generate_internal`, jamais `FiboVLM.edit`
  ni ses replis) : en mode masqué, FIBO-vlm n'écrit jamais `edit_instruction` et boucle après
  `text_render` ou ferme l'objet au hasard (la cause de « Masked edit prompt generation failed ») ;
  le script s'arrête dès que `"text_render":[…]` est fermé (texte relu tous les 4 jetons, par
  `Qwen3VLUtil.sample_top_p` remplacé, puis le texte final : une génération finie juste après le
  `]` ; la fin cherchée hors des chaînes JSON, `fin_text_render`, jamais par un motif : un crochet
  dans un texte à rendre, « OPEN [24h] », faisait boucler jusqu'à la borne ou couper dans la
  chaîne), ferme l'objet et pose `edit_instruction` (« Fill the masked area: » et l'instruction, par
  `_normalize_edit_output` avec `fallback_edit_instruction`) ; sans zone, la fiche se rédige sans
  masque, jusqu'à sa fin ; une accolade fermée trop tôt se répare (`reparer`, dans les deux modes :
  seulement si la suite reprend par une clé, `}` puis `,"`, blancs permis, et gardée seulement si le
  texte se lit alors en entier ; sinon le texte d'origine, dont `_extract_single_json_object` de
  mflux garde le meilleur objet : une fiche complète suivie d'un second objet commencé restait
  illisible après une réparation aveugle) ; une `ValueError` levée avant la normalisation (MLX)
  est dite telle quelle (« erreur FIBO-vlm : … », plus « aucune réponse ») ; `sample_top_p` et
  `_normalize_edit_output` remis après la génération (`finally`) ; plus de repli sans masque ni de
  `--image-originale` (`marqueRepliFiche` retirée).
  Le script se sert de détails internes de mflux 0.24 (`Generatif.versionMfluxFiche`) : il lit la
  version installée (`importlib.metadata`) et, si elle diffère, l'écrit sur sa sortie
  (`marqueVersionFiche`, « version de mflux : … »), dont le connecteur ne garde que la version
  (`Generatif.versionDite`) dans `remarque_fiche` (« mflux installé : 0.25.0 ; le script de la fiche
  est réglé sur 0.24.0 : à revérifier. », `remarqueVersion`) ; toute exception : code 1, la phrase seule. Essai : `testScriptDeFicheReglageLeger`
  fait tourner le vrai script sous un Python de Homebrew sur de faux paquets mlx et mflux (la
  normalisation calquée sur celle de mflux 0.24 ; boucle après `text_render`, crochets dans un texte,
  fin entre deux relectures, accolade fermée trop tôt avec et sans zone, deux objets à la suite,
  erreur avant la normalisation, attributs remis) ; **la fiche passe à mflux telle
  que le VLM l'a écrite** (l'ordre VGL de ses clés : jamais réécrite par `JSONCoding`, qui trie ;
  l'instruction jointe à la fin s'il en manque, `ficheAvecInstruction`) ; fini avant le lancement de
  mflux ; jamais bloquant (Python ou modèle absents, `Generatif.vlmLocal`, qui juge l'instantané de
  la révision que mflux épingle, `revisionVLM` bd13da5e…, jamais `refs/main`, à relire à chaque mise
  à jour de mflux ; échec, délai, fiche illisible : la phrase seule, `remarque_fiche` ; fiche refusée
  par mflux, `ficheRefusee` : seulement ses messages de refus, `refusDeFiche`, jamais un mot qu'une
  trace montre : mflux relancé une fois avec la phrase) ; phase « fiche
  (FIBO-vlm) » de la barre (`poidsFiche`) ; réponse : un court résumé par modification
  (`Generatif.resumeFiche`) ; `Fibo.motifAutreCalcul` voit aussi `fibo_vlm_tool.py` et
  `fiche-fibo-vlm.py`, et `Fibo.autreCalcul` se relit avant chaque lancement (FIBO-vlm, mflux,
  SeedVR2 : `seulSurLeMac`), un calcul lancé ailleurs pendant l'appel l'arrête, rien d'importé.
  (2) **Phrase d'exclusion** (`Generatif.termesExclusion`, `--negative-prompt` : texte, logos,
  filigrane, personne, tête ou membres en double, déformé ; la partie texte laissée de côté quand
  l'instruction parle de texte, `parleDeTexte`, et « duplicate person » quand elle ajoute une
  personne, `ajouteUnePersonne`) plus `avoid` ; elle **remplace** la légende nulle que mflux passe
  d'ordinaire à une retouche (`NULL_CAPTION`) : elle part au format de cette légende
  (`legendeExclusion` : ses clés vides, dans son ordre, les termes sous `aesthetics.artifacts`),
  jamais en mots libres ; hors Turbo seulement (dit dans `remarque_guidage`). (3) **Qualité équilibrée** (`balanced`, par défaut,
  `Generatif.qualiteParDefaut`). (4) **Masque peint** (`mask: {existing: "<nom>"}`, seul dans
  `mask`) : cherché avant l'exportation par la commande `masques` (lister,
  `ToolHandler.masqueExistant`, casse indifférente ; absent ou en double, refusé avec les noms) ;
  dans `essayer` avec `temoin`, la zone `{type = 'existant', masque}` fait copier ses
  `CorrectionMasks` (`Plans.preparerMasques`, `composantsExistants`, `pourLightroom`, nouveaux
  identifiants par `Locaux.nouveauxIdentifiants`) dans un masque témoin nouveau ; rien de Dany n'est
  changé ni retiré ; la simulation refuse un `CorrectionID` ou un `MaskID` en double sur la photo ;
  un masque peint vidé (`composants` vides) est refusé par le connecteur avant l'exportation et
  l'accord, et un masque peint presque vide ou total a son propre refus (`refusMasque` avec
  `peint`), jamais celui d'un masque calculé.
  **Constaté le 29 octobre 2026 au soir** (essais réels en Turbo, Lightroom ouvert, Fibo 2 Studio
  ouvert sans calcul, nouvelles copies d'essai de DSCF2402.RAF, graine 42) : (A) arrière-plan avec la
  fiche demandée : FIBO-vlm n'a pas fini en 300 s, repli sur la phrase seule, l'appel a réussi
  (342 s) ; mesuré seul ensuite (`/usr/bin/time -l`) : 402 s et 39,7 Go de pointe, en swap, et son
  mode masqué a levé « Masked edit prompt generation failed » (repli sans masque) : d'où
  `structured_prompt` faux par défaut, puis le réglage léger (environ 16 Go, 33 à 45 s avec une zone, 58 s sans zone, mesuré hors du connecteur) ; (B) masque existant « Claude · Fibo » (vêtements, posé par
  add_mask) : poncho noir changé en rouge en 36 s, dont 22 s de Fibo 2, 15,6 % de la photo, 10,2 Go
  de pointe ; plis, maille, manchettes et mains gardés ; un peu de noir reste sur les épaules sous
  les mèches, hors du masque de Lightroom. Un pgrep dont la ligne de commande contient le motif
  (une boucle de suivi) fait refuser l'appel (« Fibo 2 calcule déjà… ») : suivre la mémoire par un
  script dont la ligne ne le contient pas.
  (6) **Guidage** (`guidance`, de 1 à 10, absent : 5, celui de mflux) hors Turbo ; à 1, ni exclusion
  ni `--cfg-end`. Arguments de mflux dans `Generatif.arguments` (pur, testé). Provisoires et restent
  à constater : la mémoire en pointe de la fiche dans le connecteur (mesurée hors de lui ; son essai
  réel de bout en bout a réussi, 35 s), effet de la fiche et de l'exclusion (avec et sans,
  même graine), rendu de la qualité équilibrée, effet du guidage,
  masque peint au pinceau dans un vrai Lightroom ; un essai en Turbo ne vérifie que la fiche et le
  masque peint (Turbo ne lit ni l'exclusion, ni le guidage, ni `--cfg-end`). Voir `docs/SPEC.md`,
  Retouche générative par Fibo 2 (Fiche de FIBO-vlm, exclusion, qualité équilibrée, guidage, masque
  peint).
  **Photo de référence** (`reference` : `{ photo_id, region }`, demandée par Dany : « mets le fond de
  cette photo-là ») : `Generatif.reference`, avant tout envoi : une seule modification (jamais avec
  `edits`), une zone exigée (`region` ou `mask` : sans zone, Fibo redessinerait toute la photo d'après
  l'autre). mflux 0.24 refuse `--mask-path` avec plusieurs images, et son masque n'est qu'un grisage
  (`grey_out`) : l'entrée est grisée dans la zone par le connecteur (`Generatif.griser`), les deux images
  passées sans masque (`--image-paths entree reference`, `Generatif.arguments` avec `reference`) ; avec
  plusieurs images, mflux recadre chacune à sa taille d'entraînement (`trained_size`), la première
  comprise : l'entrée y est mise exactement (`Generatif.tailleEntrainee`, port vérifié contre le vrai
  code le 31 octobre 2026 ; `tailleAvecReference`), `--width` et `--height` la même. La référence se
  rend par la commande `apercu` (lecture seule, `coteReference` 1 536 px ; `imageReference` coupe
  `region` et borne le grand côté), en PNG dans le dossier de l'appel, après l'exportation et le
  masque ; l'instruction la nomme `<image_2>` (sinon « Use <image_2> as the reference for this
  change. » ajouté, `instructionAvecReference`) ; jamais de fiche de FIBO-vlm (il ne voit qu'une
  image) ; un visage nouveau dans la zone (`Generatif.visagesNouveaux`, `Teint.visages`) fait un
  `a_verifier`, jamais un refus ; réponse `reference`. **Constaté le 31 octobre 2026** (essai réel en
  Turbo, nouvelle copie d'essai 53796103 de DSCF2402.RAF, `mask` `background`, référence la dune
  53709786, graine 42) : réussi en 55 s, dont 36 s de Fibo 2 ; entrée 1 248 × 832 (taille
  d'entraînement), sortie alignée sur l'entrée, la femme intacte, le décor de la dune repris (ciel,
  arbres, sable, voiture téléguidée et le petit personnage au loin), aucune seconde tête, bord des
  cheveux doux ; 73,7 % changés ; essai défait (photo retirée, TIFF à la Corbeille). Reste à
  constater : hors Turbo, un vêtement, une personne recopiée assez grande pour `a_verifier`.
