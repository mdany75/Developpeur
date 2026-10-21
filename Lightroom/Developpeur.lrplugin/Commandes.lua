-- Commandes.lua : ce que le serveur MCP peut demander à Lightroom.
--
--   ping        → {pong = true, version}
--   etat        {sauvegarde?}          → versions, mode, pause, limites, photo active ; sauvegarde :
--                                          sauvegarde du catalogue à la prochaine fermeture
--   selection   {limite}                → photos sélectionnées et leurs données de prise de vue
--   reglages    {photo?, cles, details?, toutes?} → valeurs actuelles, profil, recadrage, appareil (et, avec
--                                          details, courbes, masques, couleurs ponctuelles, taches,
--                                          classement dans la Bibliothèque)
--   apercu      {photo?, taille, cles, comparer?, point_af?} → JPEG rendu avec les réglages actuels
--                                          (chemin d'un fichier temporaire, que le serveur lit puis
--                                          efface) ; taille 0 = pleine résolution ; comparer =
--                                          'avantClaude' ou 'etapePrecedente' rend aussi l'état d'avant
--                                          (chemin_avant) ; point_af : la photo décrite comme pour les
--                                          vignettes (point de mise au point) et point_af_toujours
--   appliquer   {photos?|selection?, reglages, booleens?, profil?, profil_marque?, profil_variantes?, profil_absent_sur?, profil_look?,
--                recadrage?, recalages?, courbes?, couleurs_ponctuelles?, balance?, auto_ton?, flou_objectif?,
--                preset?, quantite_preset?, melange_nb_auto?, profil_objectif?, reperes?, rotation?,
--                instantane_avant?, version_processus?, plages, libelles, relatif, etape, raison?, confirme} ; a_recadrer dans un résultat :
--                cadre demandé à placer sur la nouvelle géométrie (commande recadrer)
--   masquer     {photos?|selection?, masques, etape, raison?, confirme} → ajoute des masques
--                                          (un masque peut porter des composants combinés)
--   retoucher   {photo?, taches, yeux, etape, raison?, confirme}       → taches et yeux rouges
--   ameliorer   {photo?, ameliorations, etape, raison?, confirme} → débruitage, détails bruts,
--                                          super résolution, calculés par Lightroom
--   copier      {source, photos?|selection?, cles, inclure, etape, raison?, confirme}
--   geometrie   {photo?|photos?|selection?, rendre?, taille?} → correction géométrique active,
--                                          transformation (Upright, perspective), empreinte ; avec
--                                          rendre, les deux rendus du recalage
--   recadrer    {photos, recadrage, recalages, completer?, etape, raison?, confirme} → cadre demandé,
--                                          sans les coins vides d'Upright et de la perspective
--   essayer     {action, photo?, taille, comparer?, …} → applique, rend, puis remet comme avant
--   presets     {filtre?, limite}       → paramètres prédéfinis de développement
--   creerPreset {nom, photo?, cles, inclure} → réglages d'une photo, pour un paramètre prédéfini
--   diagnostic  {modules?}              → fonctions du SDK offertes par cette version de Lightroom
--   journal     {photos?|selection?}    → journal des retouches de Claude
--   annuler     {photos?|selection?}    → défait la dernière retouche de Claude
--   revenir     {photos?|selection?}    → remet l'état d'avant la première retouche de Claude
--   metadonnees {photos?|selection?, note?, drapeau?, libelle?, titre?, legende?, droits?, iptc?, gps?,
--                gps_depuis?, ajouter?, synonymes?, retirer?, preset_metadonnees?, etape, raison?, confirme}
--                                       → note, drapeau, libellé, textes, texte alternatif, champs
--                                          IPTC, position GPS, mots-clés
--   motsCles    {filtre?, limite}       → mots-clés du catalogue, par chemin
--   collections {action, nom?, nouveau_nom?, ensemble?, collection?, recherche?, mot_cle?, synonymes?,
--                photos?|selection?, etape, raison?, confirme}
--                                         → lister, créer (dans « Claude »), ajouter, retirer des photos ;
--                                          renommer, deplacer, criteres d'une collection ; mot_cle
--   chercher    {critères…, exportee?, tri?, limite, decalage?} → photos du catalogue qui y répondent
--   copieVirtuelle {photos?|selection?, nom?, afficher?, confirme} → copies virtuelles nommées
--   montrer     {photos?|selection?, module?, vue?, source_dossier?, source_collection?, filtre?,
--                filtre_preset?, remettre_filtre?} → photos sélectionnées et affichées dans Lightroom ;
--                                          source et filtre de la Bibliothèque
--   vignettes   {photos, taille}        → vignettes du cache d'aperçus (chemins de JPEG temporaires),
--                                          description, chemin du fichier et géométrie de chaque photo
--   supprimer   {photo?, reflets|poussiere, etape, raison?, confirme} → suppression des reflets,
--                                          calculée par Lightroom (filtre dereflect) ; poussière :
--                                          seulement la retirer
--   exporter    {photos, dossier, sous_dossier?, reglages, jetons?, texte_perso?, sequence?, suite?,
--                confirme} → fichiers livrés (jamais d'écrasement : renommés)
--   fenetreExport {photos?|selection?}  → fenêtre d'exportation de Lightroom, photos sélectionnées
--   livraison   {}                      → modèles de noms, paramètres prédéfinis de métadonnées,
--                                          services de publication et réglages des services
--                                          Disque dur (livraisons types)
--   choisirDossier {titre?, depart?, attente?} → dossier choisi par l'utilisateur dans une fenêtre
--                                          (en_attente tant qu'il n'a pas choisi, annule)
--   nomsFichiers {photos?|selection?, modele, texte_perso?, sequence?} → noms que Lightroom
--                                          calculera avec ce modèle
--   apercusDynamiques {photos?|selection?, retirer?} → aperçus dynamiques créés (crees,
--                                          existants, echecs) ou retirés
--   retirerReimportees {chemins}        → recette : retire du catalogue les fichiers que le module
--                                          vient d'y réimporter (même session, 30 min)
--   variantes   {photo?, action, nom?, noms?, effacer_autres?, etape, raison?, confirme} → variantes
--                                          rangées en instantanés : lister, choisir, effacer
--                                          (essayer avec `instantane` les prépare)
--   masques     {photo?, action, masque?, inverser?, nom?, contour?, decalage?, etape, raison?, confirme}
--                                       → lister, masquer, afficher, retirer, dupliquer, recalculer,
--                                          affiner un masque ; retirer les masques vides
--   progression {id, titre?, fait?, total?, message?, fin?} → barre de progression de Lightroom
--                                          pendant une série ; annulee si l'utilisateur l'a arrêtée
--   notation    {action, passe?, propositions?, poser?, photos?} → notes proposées par Claude,
--                                          rangées pour la carte Note : proposer (jamais 5
--                                          étoiles ; posées aussi avec poser, à la demande de
--                                          Dany), lire
--   lecon       {action, photo?, photos?, lecon?} → leçons des photos (1.3), rangées dans
--                                          carnet.json : garder (lecon = {points, indices?} :
--                                          trois points, un par axe, lumiere, couleur,
--                                          composition ; la nouvelle remplace l'ancienne), lire,
--                                          retirer
--   carnet      {action, photos?}       → carnet de progrès (1.3), carnet.json : lire (les
--                                          originaux du catalogue ouvert, leçons comprises),
--                                          retirer
--   etapes      {photo?}                → étapes de Claude gardées pour la photo et leurs images
--                                          avant/après (1.3, Etapes.lua) : { photo, etapes = [{ id,
--                                          nom, en_memoire, avant, apres, etat, raison }] ; lecture
--                                          seule
--
-- Étapes (1.3) : chaque résultat d'une commande qui écrit une étape de Claude (appliquer,
-- recadrer, masquer, retoucher, copier, ameliorer, supprimer, variantes choisir, masques,
-- metadonnees, collections) porte etape_id, l'identifiant de cette étape (null sans étape) ; annuler
-- rend celui de l'étape défaite. L'avant/après d'une étape se garde autour de la commande
-- (Liaison.recevoir, Etapes.lua) ; avant_apres = true (la recette seulement) le force, même hors de
-- la photo active, et sans_avant_apres = true (match_series) l'empêche.
--
-- lecon et carnet n'écrivent rien dans le catalogue et ne s'arrêtent pas à la pause ; ils écrivent
-- carnet.json, à part : le serveur ne les rejoue jamais (LightroomBridge.lectures).
-- Sans « photo » ni « photos » ni « selection », la commande vise la photo active.
-- Les erreurs sont levées avec error(message, 0) : le message part tel quel vers Claude.
-- Toute commande, ping compris, n'arrive ici qu'avec le jeton de la liaison (Liaison.recevoir) ;
-- depuisLightroom n'y vient jamais du réseau.
--
-- Chaque commande est dans le module de son domaine :
--   Lecture.lua      etat, selection, reglages, presets, creerPreset, diagnostic, journal
--   Rendu.lua        apercu, essayer, geometrie
--   Retouche.lua     appliquer, recadrer, masquer, retoucher, copier
--   Amelioration.lua ameliorer
--   Annulation.lua   annuler, revenir
--   Bibliotheque.lua metadonnees, motsCles, collections, chercher, copieVirtuelle, montrer
--   Vignettes.lua    vignettes
--   Suppression.lua  supprimer
--   Livraison.lua    exporter, fenetreExport, livraison, choisirDossier, nomsFichiers,
--                    apercusDynamiques, retirerReimportees (réglages des services : Services.lua)
--   Variantes.lua    variantes
--   Masques.lua      masques
--   Progression.lua  progression
--   Notation.lua     notation
--   Carnet.lua       lecon, carnet
--   Etapes.lua       etapes
-- Elles s'appuient sur Photos.lua (photos visées, mémoire de Claude), Reglages.lua (valeurs de
-- développement), Recalage.lua (géométrie et grille du serveur), Plans.lua (ce qu'une retouche
-- changera), Ecriture.lua (écriture dans le catalogue, étapes, journal) et Profils.lua (profil
-- relu après l'écriture).

local Amelioration = require 'Amelioration'
local Annulation = require 'Annulation'
local Bibliotheque = require 'Bibliotheque'
local Carnet = require 'Carnet'
local Etapes = require 'Etapes'
local Lecture = require 'Lecture'
local Livraison = require 'Livraison'
local Masques = require 'Masques'
local Notation = require 'Notation'
local Progression = require 'Progression'
local Rendu = require 'Rendu'
local Retouche = require 'Retouche'
local Suppression = require 'Suppression'
local Variantes = require 'Variantes'
local Vignettes = require 'Vignettes'

local Commandes = {}

local table_commandes = {
    -- La version du module : le serveur la compare à la sienne à chaque connexion.
    ping = function() return { pong = true, version = require('Liaison').VERSION } end,
    etat = Lecture.etat,
    selection = Lecture.selection,
    reglages = Lecture.reglages,
    apercu = Rendu.apercu,
    geometrie = Rendu.geometrie,
    appliquer = Retouche.appliquer,
    recadrer = Retouche.recadrer,
    masquer = Retouche.masquer,
    retoucher = Retouche.retoucher,
    ameliorer = Amelioration.ameliorer,
    copier = Retouche.copier,
    essayer = Rendu.essayer,
    presets = Lecture.presets,
    creerPreset = Lecture.creerPreset,
    diagnostic = Lecture.diagnostic,
    journal = Lecture.journal,
    annuler = Annulation.annuler,
    revenir = Annulation.revenir,
    metadonnees = Bibliotheque.metadonnees,
    motsCles = Bibliotheque.motsCles,
    collections = Bibliotheque.collections,
    chercher = Bibliotheque.chercher,
    copieVirtuelle = Bibliotheque.copieVirtuelle,
    montrer = Bibliotheque.montrer,
    vignettes = Vignettes.vignettes,
    supprimer = Suppression.supprimer,
    exporter = Livraison.exporter,
    fenetreExport = Livraison.fenetreExport,
    livraison = Livraison.options,
    choisirDossier = Livraison.choisirDossier,
    nomsFichiers = Livraison.nomsFichiers,
    apercusDynamiques = Livraison.apercusDynamiques,
    retirerReimportees = Livraison.retirerReimportees,
    variantes = Variantes.variantes,
    masques = Masques.masques,
    progression = Progression.progression,
    notation = Notation.commande,
    lecon = Carnet.commandeLecon,
    carnet = Carnet.commande,
    etapes = Etapes.commande,
}

function Commandes.executer(nom, params)
    local commande = table_commandes[nom]
    if not commande then
        error("Commande inconnue : " .. tostring(nom), 0)
    end
    if nom ~= 'progression' then
        Progression.verifierPerimee()
    end
    return commande(params or {})
end

return Commandes
