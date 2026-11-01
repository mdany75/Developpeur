# Module Lightroom : réglages, profils, calculs IA et traitements

Sorti de `Lightroom/CLAUDE.md` le 31 octobre 2026 (qui y renvoie) ; à lire avant de toucher à
l'écriture des réglages (`applyDevelopSettings`, paramètres prédéfinis du module), aux profils,
aux masques, au débruitage, aux reflets, aux rotations, aux variantes ou aux instantanés.

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
- Une personne précise (`add_mask`, `kind: "person"`) porte `InstanceIDs` **et** `InstanceBounds`,
  les cadres de toutes les personnes (le serveur les tire de Vision, `detecterPersonnes`) : sans
  eux, Lightroom ne la reconnaît pas (constaté). Sauf la personne seule d'une photo (Vision n'en
  trouve qu'une : `seule`) : faite à la main, elle n'a ni l'un ni l'autre, seulement le sous-type 0
  et sa catégorie, et le module l'envoie ainsi (`Locaux.personne`) ; numérotée, Lightroom la calcule
  de même puis retire le numéro (constaté le 20 octobre 2026, même `MaskDigest`).
  `Locaux.numeroPersonne` la compte comme la personne 1 (`Locaux.CATEGORIES_PERSONNE` : le
  sous-type 0 sert aussi à l'arrière-plan et au paysage). `sansCalculsIA` garde les cadres ;
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
