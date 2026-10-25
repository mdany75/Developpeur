-- Etapes.lua : l'avant/après de chaque étape de Claude (1.3, « Pourquoi ? »), gardé sans aucune
-- écriture dans le catalogue, pour la fenêtre Claude.
--
-- Lightroom ne rend que l'état actuel d'une photo (LrExportSession prend les réglages du moment) :
-- ni un état de l'Historique ni un instantané ne se rendent sans être posés sur la photo. Les
-- images se gardent donc au moment de l'étape :
--   - l'avant : le dernier rendu connu de la photo dans le même état (la vue : l'image de
--     view_photo, gardée par Rendu.apercu, ou l'après de l'étape précédente), reconnu par une
--     empreinte des réglages et de l'orientation ; à défaut (une retouche à la main entre-temps),
--     un rendu juste avant l'écriture ;
--   - l'après : rendu juste après la réponse de la commande (Liaison.recevoir appelle
--     apresCommande une fois la réponse partie), pendant que Claude écrit son appel suivant.
-- Conditions : la case « Avant/après » cochée (préférence avantApresEtapes) et la fenêtre Claude
-- ouverte ou son Claude au travail (Etapes.actifPour, posé par la fenêtre), ou avant_apres = true
-- (la recette seulement, jamais un outil : elle lève aussi la condition de la photo active) ; une
-- commande qui écrit une étape sur une seule photo, la photo active ; jamais sans_avant_apres
-- (match_series), en pause, ni pour une commande que le mode « Proposer d'abord » ou une photo
-- protégée vont faire refuser.
-- Jamais un rendu quand Lightroom a encore des calculs IA à faire : un rendu que Claude n'a pas
-- demandé ne doit pas ouvrir la fenêtre « Mises à jour IA recommandées », qui attend l'utilisateur.
-- Une capture à la fois : toute autre commande (sauf SANS_ATTENTE) attend sa fin, ATTENTE secondes
-- au plus. Une photo changée pendant le rendu (empreintes E1 et E2 différentes) perd son après.
-- Une étape d'appliquer à recadrer (a_recadrer) attend recadrer pour son après ; si recadrer
-- n'écrit rien pour la photo ou échoue, l'après se rend tel quel.
--
-- Fichiers, dans Chemins.etapes()/<uuid de la photo>/ (une copie virtuelle a le sien) :
--   <id>-avant.jpg, <id>-apres.jpg   les images de l'étape (id : Ecriture.idEtape)
--   <id>.json                        { etat = 'pret' | 'manque' | 'en_cours', raison?, detail?,
--                                      duree?, photo, etape, le }
--   vue.jpg, prepare-<n>.jpg         la vue, et l'avant préparé d'une commande en cours (effacés
--                                      au chargement du module : ils ne servent qu'à une session)
-- Ménage au chargement du module (Init.lua) : fichiers de plus de JOURS jours, puis les plus
-- anciens au-delà de MAX_OCTETS. Ces images restent sur ce Mac : elles ne partent jamais vers
-- Claude ni vers le connecteur, sauf les chemins que donne la commande etapes (recette).
--
-- Sans LrView ni couleur : chargé par la liaison et par la fenêtre. Rendu et Ecriture sont requis
-- à l'appel (Rendu requiert Etapes ; Liaison et Commandes aussi).

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Preferences = require 'Preferences'

local Etapes = {
    -- Côté des images de l'après (pixels), comme les rendus d'analyse. Gardé après la mesure du
    -- 21 octobre 2026 (Lightroom Classic 15.6, deux copies d'Essais, 13 étapes) : une capture prend
    -- de 0,51 à 1,06 s (masques IA compris), sous la 1,5 s visée ; la réponse à Claude ne change pas
    -- quand une vue de l'état existe (+4 %), +0,8 s sans elle (l'avant rendu avant l'écriture) ;
    -- 0,6 à 0,9 Mo par étape.
    COTE = 1024,
    -- Attente d'une capture en cours par la commande suivante (secondes). Gardée après la même
    -- mesure : une commande suivante (view_photo) a attendu la fin de la capture environ 1,1 s, sans
    -- jamais toucher ce plafond.
    ATTENTE = 8,
    -- Une capture plus longue que cela est tenue pour interrompue (secondes).
    PERIMEE = 120,
    -- Ménage : âge maximal des fichiers (jours) et place maximale du dossier Etapes (octets).
    JOURS = 30,
    MAX_OCTETS = 500 * 1024 * 1024,
    VUE = 'vue.jpg',

    -- Compteur lu par la fenêtre : il change à chaque avant/après rangé (ou manqué).
    version = 0,
    -- Capture en cours (une à la fois) : depuis quand, et l'id de son étape.
    enCours = false,
    enCoursDepuis = 0,
    captureId = nil,
    -- Dernier rendu connu de chaque photo : vues[uuid] = { chemin, empreinte }.
    vues = {},
    -- Commandes préparées par avantCommande : prepares[cle] = { photo, photoId, uuid, dossier,
    -- avant?, raison?, detail? ; pour recadrer qui complète : derniere, enAttente?, nomEnAttente? }.
    prepares = {},
}

-- Vrai si la fenêtre Claude est ouverte ou si son Claude travaille : posé par la fenêtre
-- (Fenetre.afficher). Sans elle (Claude Desktop seul), aucune capture.
local function sansFenetre()
    return false
end
Etapes.actifPour = sansFenetre

-- Ce que chaque commande fait d'une étape : 'nouvelle' (une étape écrite, dont on garde l'avant et
-- l'après) ou 'completer' (recadrer complète l'étape précédente pour les photos de `completer` :
-- l'avant est déjà gardé ; pour une autre photo, c'est une étape nouvelle). Les classements
-- (metadonnees, collections, notation) n'en sont pas : rien ne change à l'image.
Etapes.COMMANDES = {
    appliquer = 'nouvelle', masquer = 'nouvelle', retoucher = 'nouvelle', copier = 'nouvelle',
    ameliorer = 'nouvelle', supprimer = 'nouvelle', recadrer = 'completer',
}

-- Commandes qui n'attendent pas la fin d'une capture : elles ne rendent ni n'écrivent rien que la
-- capture regarde (lectures, barre de progression, registres hors du catalogue).
Etapes.SANS_ATTENTE = {
    ping = true, etat = true, selection = true, progression = true, notation = true, etapes = true,
    carnet = true, journal = true, reglages = true, diagnostic = true,
}

-- Raisons d'un avant/après manquant, en mots (journal de la liaison ; la fenêtre les reprend).
Etapes.RAISONS = {
    calculs_ia = "Lightroom n'avait pas fini ses calculs IA (masques, profil adaptatif) : un rendu aurait ouvert la fenêtre « Mises à jour IA recommandées »",
    changee = "la photo a changé pendant le rendu",
    rendu = "Lightroom n'a pas pu rendre la photo",
    sans_avant = "aucune image de l'état d'avant",
    interrompue = "capture interrompue",
}

local function maintenant()
    return LrDate.currentTime()
end

local function genreDe(nom, params)
    if nom == 'masques' then
        return params.action ~= nil and tostring(params.action) ~= 'lister' and 'nouvelle' or nil
    elseif nom == 'variantes' then
        return params.action == 'choisir' and 'nouvelle' or nil
    end
    return Etapes.COMMANDES[nom]
end

-- Remise à zéro (essais) : plus de vue, de préparation ni de capture en cours, et plus de fenêtre.
function Etapes.oublier()
    Etapes.vues, Etapes.prepares = {}, {}
    Etapes.enCours, Etapes.enCoursDepuis, Etapes.captureId = false, 0, nil
    Etapes.version = 0
    Etapes.actifPour = sansFenetre
end

-- Activation -----------------------------------------------------------------------------------

-- Vrai si l'avant/après se garde pour cette commande : case cochée et fenêtre ouverte (ou son
-- Claude au travail), ou avant_apres (recette) ; jamais avec sans_avant_apres.
function Etapes.actif(params)
    params = params or {}
    if params.sans_avant_apres == true then
        return false
    end
    if params.avant_apres == true then
        return true
    end
    local coche = Preferences.lire().avantApresEtapes
    if coche == nil then
        coche = Chemins.defauts.avantApresEtapes
    end
    if coche ~= true then
        return false
    end
    local ok, oui = pcall(Etapes.actifPour)
    return ok and oui == true
end

local function estActive(photo)
    local active = Photos.catalogue():getTargetPhoto()
    return active ~= nil and active.localIdentifier == photo.localIdentifier
end

-- La photo dont on garde l'avant/après : la seule que vise la commande, et la photo active (sauf
-- avant_apres). nil sinon : une série n'est jamais ralentie.
function Etapes.cible(params)
    local ok, photos = LrTasks.pcall(function()
        if params.photo ~= nil then
            return { Photos.photoVisee(params) }
        end
        return Photos.photosVisees(params)
    end)
    if not ok or type(photos) ~= 'table' or #photos ~= 1 then
        return nil
    end
    local photo = photos[1]
    if params.avant_apres == true or estActive(photo) then
        return photo
    end
    return nil
end

-- Vrai si la commande sera refusée sans rien écrire : mode « Proposer d'abord » sans accord (accord
-- dans Lightroom absent, refusé ou trop vieux, comme Ecriture.accordDansLightroom), ou photo
-- protégée (Ecriture.verifierProtection : copies virtuelles seulement, libellé, rejet). Pas de
-- rendu en vain.
local function seraRefusee(params, photo)
    local prefs = Preferences.lire()
    local Ecriture = require 'Ecriture'
    if not LrTasks.pcall(Ecriture.verifierProtection, { photo }, prefs, params, 'avant/après') then
        return true
    end
    if prefs.mode ~= 'proposer' then
        return false
    end
    if not params.confirme then
        return true
    end
    if prefs.accordDansLightroom then
        local accord = Liaison.accord
        return not (accord and accord.accepte and maintenant() - (tonumber(accord.le) or 0) < Ecriture.DUREE_ACCORD)
    end
    return false
end

-- Empreinte de l'état ---------------------------------------------------------------------------

-- Clés que Lightroom calcule ou résout lui-même, sans effet visible à elles seules : retirées de
-- l'empreinte, à toute profondeur. Les matrices UprightTransform_* (et UprightTransformCount),
-- Lightroom les calcule au rendu d'après les autres réglages (constaté ; comme pour
-- Recalage.empreinteGeometrie) : comptées, elles changeraient l'empreinte pendant le rendu de
-- l'après de toute étape qui pose Upright. Liste gardée après le relevé du 21 octobre 2026
-- (--dump avant et après, Lightroom Classic 15.6, deux copies d'Essais) : à 0, 1 et 5 s, après un
-- aperçu, une proposition ou un débruitage relu, Lightroom n'a changé seul aucune clé, pas même
-- une de celles-ci ; seules les écritures du module en ont changé (GlobalInputDigest du débruitage).
local VOLATILES = { LensProfileName = true, LensProfileFilename = true, LensProfileIsEmbedded = true }

local function volatile(cle)
    return type(cle) == 'string' and (VOLATILES[cle] or cle:match('Digest$') ~= nil or cle:match('DigestVersion$') ~= nil
        or cle:match('^UprightTransform') ~= nil)
end

-- Une table vide vaut une clé absente. Constaté le 21 octobre 2026 (même relevé) : sur une photo
-- sans masque, MaskGroupBasedCorrections passait d'absente à {} (retour de view_photo compare =
-- before_claude, annulation de l'étape qui posait des masques) puis de {} à absente (rendus du
-- recalage), sans rien changer à l'image ; comptée, la vue gardée ne valait plus et l'étape suivante
-- rendait de nouveau son avant. RetouchInfo (taches vidées, aRemettre), RetouchAreas, RedEyeInfo et
-- DepthBasedCorrections sont des listes de la même sorte. Seulement sous une clé texte : un élément
-- vide d'une liste garde sa place.
local function vide(valeur)
    return type(valeur) == 'table' and valeur ~= Json.null and next(valeur) == nil
end

local function sansVolatils(valeur)
    if type(valeur) ~= 'table' or valeur == Json.null then
        return valeur
    end
    local copie = {}
    for cle, element in pairs(valeur) do
        if not volatile(cle) and not (type(cle) == 'string' and vide(element)) then
            copie[cle] = sansVolatils(element)
        end
    end
    return copie
end

Etapes.sansVolatils = sansVolatils

-- Empreinte de l'état d'une photo : ses réglages (sans les clés volatiles ; Json.encode trie les
-- clés) et son orientation, qu'une rotation d'un quart de tour change sans toucher aux réglages.
function Etapes.empreinte(photo)
    return Locaux.empreinte(Json.encode(sansVolatils(photo:getDevelopSettings()))) .. '|' .. tostring(Photos.brut(photo, 'orientation'))
end

-- Fichiers --------------------------------------------------------------------------------------

local function dossierUuid(uuid)
    return LrPathUtils.child(Chemins.etapes(), uuid)
end

-- Dossier des images d'une photo, par son uuid (un autre catalogue, une copie virtuelle : le sien).
function Etapes.dossier(photo)
    local uuid = Photos.brut(photo, 'uuid')
    if type(uuid) ~= 'string' or uuid == '' then
        return nil
    end
    return dossierUuid(uuid)
end

local function chemin(dossier, nom)
    return LrPathUtils.child(dossier, nom)
end

local function effacer(fichier)
    if fichier and LrFileUtils.exists(fichier) then
        LrFileUtils.delete(fichier)
    end
end

-- Range un fichier à sa place (en remplaçant celui qui y était), puis efface le dossier temporaire
-- du rendu, propre à lui (Rendu.rendre). Vrai si le fichier est là.
local function ranger(source, destination, dossierRendu)
    Fichiers.creerDossier(LrPathUtils.parent(destination))
    effacer(destination)
    LrFileUtils.move(source, destination)
    if dossierRendu then
        effacer(dossierRendu)
    end
    return Fichiers.existe(destination)
end

-- Copie un fichier (en remplaçant celui qui y était). Vrai si la copie est là.
local function copier(source, destination)
    if not Fichiers.existe(source) then
        return false
    end
    Fichiers.creerDossier(LrPathUtils.parent(destination))
    effacer(destination)
    LrFileUtils.copy(source, destination)
    return Fichiers.existe(destination)
end

local function ecrireEtat(dossier, id, etat)
    etat.le = maintenant()
    Fichiers.ecrire(chemin(dossier, id .. '.json'), Json.encode(etat))
end

local function lireEtat(dossier, id)
    local texte = Fichiers.lire(chemin(dossier, id .. '.json'))
    if not texte then
        return nil
    end
    local ok, etat = pcall(Json.decode, texte)
    return ok and type(etat) == 'table' and etat or nil
end

-- Rendu -----------------------------------------------------------------------------------------

-- Vrai si Lightroom a encore des calculs IA à faire pour cette photo.
local function encoreACalculer(photo)
    if Locaux.calculsEnAttente(photo:getDevelopSettings()) then
        return true
    end
    local ok, besoin = pcall(function() return photo.needsUpdateAISettings end)
    if ok and type(besoin) == 'function' then
        local lu, oui = LrTasks.pcall(besoin, photo)
        return lu and oui == true
    end
    return false
end

-- Rend l'état actuel de la photo (Etapes.COTE) et le range en `destination`. Rend le chemin et
-- l'empreinte de l'état rendu, ou nil, la raison ('calculs_ia', 'changee', 'rendu') et le détail.
-- Les calculs IA d'abord (calculerAvantRendu) ; s'il en reste, rien n'est rendu.
function Etapes.rendreEtat(photo, destination)
    require('Ecriture').calculerAvantRendu(photo)
    if encoreACalculer(photo) then
        return nil, 'calculs_ia'
    end
    local e1 = Etapes.empreinte(photo)
    local ok, rendu = LrTasks.pcall(require('Rendu').rendre, photo, Etapes.COTE)
    if not ok then
        return nil, 'rendu', Liaison.messageErreur(rendu)
    end
    local dossierRendu = LrPathUtils.parent(rendu)
    local e2 = Etapes.empreinte(photo)
    if e1 ~= e2 then
        -- Claude ou l'utilisateur a écrit pendant le rendu : l'image ne dit plus l'état.
        effacer(rendu)
        effacer(dossierRendu)
        return nil, 'changee'
    end
    if not ranger(rendu, destination, dossierRendu) then
        return nil, 'rendu', "image introuvable après le rendu"
    end
    return destination, e2
end

-- La vue (Rendu.apercu) -------------------------------------------------------------------------

-- Avant le rendu de view_photo : l'empreinte de l'état si sa vue est à garder (avant/après actif,
-- photo active ou avant_apres), sinon nil. Rendu.apercu ne l'appelle que pour l'image entière de
-- l'état actuel (ni zoom, ni image d'avant d'une comparaison, ni image entière sans cadre). Les
-- calculs IA se font d'abord (rendre les ferait de toute façon) : l'empreinte est celle de l'état
-- que le rendu montre, et ne change pas pendant le rendu à cause d'eux.
function Etapes.avantVue(photo, params)
    params = params or {}
    if not Etapes.actif(params) then
        return nil
    end
    if params.avant_apres ~= true and not estActive(photo) then
        return nil
    end
    require('Ecriture').calculerAvantRendu(photo)
    return Etapes.empreinte(photo)
end

-- Garde une copie de l'image de view_photo (le serveur efface la sienne après l'avoir lue) comme
-- vue de la photo, si l'état n'a pas changé pendant le rendu.
function Etapes.garderVue(photo, rendu, empreinte)
    if not rendu or not empreinte or Etapes.empreinte(photo) ~= empreinte then
        return false
    end
    local dossier = Etapes.dossier(photo)
    if not dossier then
        return false
    end
    local vue = chemin(dossier, Etapes.VUE)
    if not copier(rendu, vue) then
        return false
    end
    Etapes.vues[Photos.brut(photo, 'uuid')] = { chemin = vue, empreinte = empreinte }
    return true
end

-- Avant et après une commande (Liaison.recevoir) -----------------------------------------------

-- Attend la fin d'une capture en cours, ATTENTE secondes au plus. Faux si elle dure encore.
local function attendreCapture()
    if Etapes.enCours and maintenant() - Etapes.enCoursDepuis > Etapes.PERIMEE then
        Etapes.enCours, Etapes.captureId = false, nil
    end
    if not Etapes.enCours then
        return true
    end
    local debut = maintenant()
    while Etapes.enCours and maintenant() - debut < Etapes.ATTENTE do
        LrTasks.sleep(0.1)
    end
    if Etapes.enCours then
        Liaison.noter(string.format("Avant/après : capture encore en cours après %d s, la commande suivante part quand même", Etapes.ATTENTE))
        return false
    end
    return true
end

Etapes.attendreCapture = attendreCapture

-- Id de la dernière étape de Claude dans la mémoire de la photo (nil sans étape ou sans id).
local function derniereEtape(photo)
    local etapes = Photos.lireJson(photo, 'etapesClaude', {})
    local derniere = type(etapes) == 'table' and etapes[#etapes]
    local id = type(derniere) == 'table' and derniere.id
    return type(id) == 'string' and id ~= '' and id or nil
end

local compteurPrepares = 0

-- Avant une commande : attend une capture en cours (sauf SANS_ATTENTE), puis, pour une commande
-- qui écrira une étape sur la photo cible, prépare son avant : une copie de la vue si elle montre
-- l'état actuel, sinon (une nouvelle étape seulement) un rendu de cet état, gardé comme vue. Rend
-- la clé de la préparation (à passer à apresCommande ou abandonner), ou nil.
function Etapes.avantCommande(nom, params)
    params = params or {}
    if not Etapes.SANS_ATTENTE[nom] then
        attendreCapture()
    end
    local genre = genreDe(nom, params)
    if not genre or not Etapes.actif(params) or Liaison.pause then
        return nil
    end
    local photo = Etapes.cible(params)
    local dossier = photo and Etapes.dossier(photo)
    if not dossier or seraRefusee(params, photo) then
        return nil
    end
    if genre == 'completer' then
        local complete = false
        for _, id in ipairs(type(params.completer) == 'table' and params.completer or {}) do
            complete = complete or tonumber(id) == photo.localIdentifier
        end
        genre = complete and 'completer' or 'nouvelle'
    end
    compteurPrepares = compteurPrepares + 1
    local cle = compteurPrepares
    local uuid = Photos.brut(photo, 'uuid')
    local prepare = { photo = photo, photoId = photo.localIdentifier, uuid = uuid, dossier = dossier }
    if genre == 'completer' then
        -- L'étape que recadrer complète : la dernière de la mémoire. Son avant est celui d'avant
        -- appliquer, jamais une vue d'entre les deux (capturer). Laissée « en cours » par appliquer
        -- (a_recadrer), son après se rend même si recadrer n'écrit rien pour la photo (cadre déjà
        -- juste, pas de recalage) ou échoue (apresCommande, abandonner).
        prepare.derniere = derniereEtape(photo)
        local lu = prepare.derniere and lireEtat(dossier, prepare.derniere)
        if lu and lu.etat == 'en_cours' then
            prepare.enAttente, prepare.nomEnAttente = prepare.derniere, lu.etape
        end
    end
    local preparee = chemin(dossier, 'prepare-' .. cle .. '.jpg')
    local empreinte = Etapes.empreinte(photo)
    local vue = Etapes.vues[uuid]
    if vue and vue.empreinte == empreinte and copier(vue.chemin, preparee) then
        prepare.avant = preparee
    elseif genre == 'nouvelle' then
        -- Aucune vue de cet état (retouche à la main depuis view_photo, ou pas de view_photo) : un
        -- rendu maintenant, avant l'écriture.
        Etapes.enCours, Etapes.enCoursDepuis = true, maintenant()
        -- rendreEtat rend (chemin, empreinte) ou (nil, raison, détail).
        local ok, rendu, second, detail = LrTasks.pcall(Etapes.rendreEtat, photo, chemin(dossier, Etapes.VUE))
        Etapes.enCours = false
        if ok and rendu then
            Etapes.vues[uuid] = { chemin = rendu, empreinte = second }
            if copier(rendu, preparee) then
                prepare.avant = preparee
            end
            Liaison.noter("Avant/après : état d'avant rendu avant l'écriture (pas de vue de cet état)", photo.localIdentifier)
        else
            prepare.raison = ok and second or 'rendu'
            prepare.detail = ok and detail or Liaison.messageErreur(rendu)
        end
    end
    Etapes.prepares[cle] = prepare
    return cle
end

-- Une commande en erreur (appelé une fois sa réponse partie) : sa préparation est effacée ; une
-- étape laissée en cours par appliquer (a_recadrer) que ce recadrer devait compléter reste telle
-- quelle, et son après se rend maintenant.
function Etapes.abandonner(cle)
    local prepare = cle and Etapes.prepares[cle]
    if prepare and prepare.enAttente then
        return Etapes.apresCommande(nil, nil, nil, cle)
    end
    Etapes.prepares[cle or 0] = nil
    if prepare then
        effacer(prepare.avant)
    end
end

-- L'étape écrite pour la photo préparée, d'après la réponse : son id, a_recadrer, son nom.
local function etapeDe(resultat, photoId)
    if type(resultat) ~= 'table' then
        return nil
    end
    local liste = type(resultat.resultats) == 'table' and resultat.resultats or { resultat }
    for _, r in ipairs(liste) do
        if type(r) == 'table' and type(r.etape_id) == 'string' and type(r.photo) == 'table' and tonumber(r.photo.id) == photoId then
            return r.etape_id, r.a_recadrer == true, r.etape
        end
    end
    return nil
end

local function capturer(prepare, id, aRecadrer, nomEtape)
    local dossier = prepare.dossier
    local avant = chemin(dossier, id .. '-avant.jpg')
    -- Une étape complétée (recadrer : son id existait avant la commande) garde l'avant de l'étape
    -- qu'elle complète, ou reste sans avant : jamais l'avant préparé, qui montre l'état d'entre
    -- appliquer et recadrer. Il ne sert qu'à une étape nouvelle.
    local completee = prepare.derniere ~= nil and id == prepare.derniere
    if prepare.avant and not completee and not Fichiers.existe(avant) then
        ranger(prepare.avant, avant)
    else
        effacer(prepare.avant)
    end
    local base = { photo = prepare.photoId, etape = nomEtape }
    if aRecadrer then
        -- La commande recadrer suit et complète la même étape : l'après viendra avec elle.
        base.etat = 'en_cours'
        ecrireEtat(dossier, id, base)
        Etapes.version = Etapes.version + 1
        return
    end
    local debut = maintenant()
    -- rendreEtat rend (chemin, empreinte) ou (nil, raison, détail).
    local rendu, second, detail = Etapes.rendreEtat(prepare.photo, chemin(dossier, id .. '-apres.jpg'))
    local raison
    if rendu then
        -- L'après devient la vue : l'avant de l'étape suivante, sans autre rendu.
        Etapes.vues[prepare.uuid] = { chemin = rendu, empreinte = second }
    else
        raison = second
    end
    local aAvant = Fichiers.existe(avant)
    if rendu and not aAvant then
        raison, detail = prepare.raison or 'sans_avant', prepare.detail
    end
    base.etat = (rendu and aAvant) and 'pret' or 'manque'
    base.raison, base.detail = raison, detail
    base.duree = maintenant() - debut
    ecrireEtat(dossier, id, base)
    Etapes.version = Etapes.version + 1
    if base.etat == 'pret' then
        Liaison.noter(string.format("Avant/après de « %s » gardé en %.1f s", tostring(nomEtape or id), base.duree), prepare.photoId)
    else
        Liaison.noter(string.format("Avant/après de « %s » non gardé : %s", tostring(nomEtape or id),
            Etapes.RAISONS[raison] or tostring(raison)), prepare.photoId)
    end
end

-- Après une commande, une fois sa réponse partie : range l'avant préparé sous l'id de l'étape
-- écrite, puis rend l'après (sauf a_recadrer : recadrer complète la même étape). Une capture à la
-- fois ; la commande suivante l'attend (avantCommande).
function Etapes.apresCommande(nom, params, resultat, cle)
    local prepare = cle and Etapes.prepares[cle]
    if not prepare then
        return
    end
    Etapes.prepares[cle] = nil
    local id, aRecadrer, nomEtape = etapeDe(resultat, prepare.photoId)
    if not id and prepare.enAttente then
        -- recadrer n'a rien écrit pour la photo, ou a échoué (abandonner) : l'étape laissée en
        -- cours par appliquer est finie telle quelle ; son après se rend maintenant.
        id, aRecadrer, nomEtape = prepare.enAttente, false, prepare.nomEnAttente
    end
    if not id then
        -- Rien d'écrit pour cette photo : pas d'étape, pas d'avant/après.
        effacer(prepare.avant)
        return
    end
    Etapes.enCours, Etapes.enCoursDepuis, Etapes.captureId = true, maintenant(), id
    local ok, erreur = LrTasks.pcall(capturer, prepare, id, aRecadrer, nomEtape)
    Etapes.enCours, Etapes.captureId = false, nil
    if not ok then
        Liaison.noter("Avant/après non gardé : " .. Liaison.messageErreur(erreur), prepare.photoId)
    end
end

-- Lecture ---------------------------------------------------------------------------------------

-- État d'une étape d'après ses fichiers : { avant = nom | nil, apres = nom | nil, etat, raison }.
-- etat : 'pret' (les deux images), 'en_cours' (capture en cours ou recadrage attendu), 'manque'
-- (raison), 'inconnu' (rien de gardé : fenêtre fermée, autre photo, étape d'avant la 1.3…).
local function etatEtape(dossier, id)
    local nomAvant, nomApres = id .. '-avant.jpg', id .. '-apres.jpg'
    local a = dossier and Fichiers.existe(chemin(dossier, nomAvant))
    local p = dossier and Fichiers.existe(chemin(dossier, nomApres))
    local lu = dossier and lireEtat(dossier, id)
    local info = { avant = a and nomAvant or nil, apres = p and nomApres or nil }
    if a and p then
        info.etat = 'pret'
    elseif Etapes.captureId == id then
        info.etat = 'en_cours'
    elseif lu and lu.etat == 'en_cours' then
        if maintenant() - (tonumber(lu.le) or 0) > Etapes.PERIMEE then
            info.etat, info.raison = 'manque', 'interrompue'
        else
            info.etat = 'en_cours'
        end
    elseif lu then
        info.etat = 'manque'
        info.raison = type(lu.raison) == 'string' and lu.raison or nil
    else
        info.etat = 'inconnu'
    end
    return info, lu
end

-- Les images d'une étape, pour la fenêtre (dans une tâche) : une table neuve { dossier, avant =
-- nom | nil, apres = nom | nil, etat, raison }.
function Etapes.images(photoId, etapeId)
    local ok, photo = LrTasks.pcall(Photos.photoParId, photoId)
    local dossier = ok and photo and Etapes.dossier(photo) or nil
    if not dossier or type(etapeId) ~= 'string' or etapeId == '' then
        return { etat = 'inconnu' }
    end
    local info = etatEtape(dossier, etapeId)
    return { dossier = dossier, avant = info.avant, apres = info.apres, etat = info.etat, raison = info.raison }
end

-- Commande « etapes » {photo?}, en lecture seule : les étapes de Claude gardées pour la photo (sa
-- mémoire, puis celles du disque défaites depuis) et leurs images. { photo, etapes = [{ id, nom,
-- en_memoire, avant = chemin | null, apres = chemin | null, etat, raison }] }.
function Etapes.commande(params)
    local photo = Photos.photoVisee(params or {})
    local dossier = Etapes.dossier(photo)
    local liste, vus = Json.tableau(), {}
    local function ajouter(id, nom, enMemoire)
        local info = { etat = 'inconnu' }
        if type(id) == 'string' and id ~= '' then
            vus[id] = true
            info = etatEtape(dossier, id)
        end
        liste[#liste + 1] = {
            id = type(id) == 'string' and id or Json.null,
            nom = nom ~= nil and tostring(nom) or Json.null,
            en_memoire = enMemoire,
            avant = info.avant and chemin(dossier, info.avant) or Json.null,
            apres = info.apres and chemin(dossier, info.apres) or Json.null,
            etat = info.etat,
            raison = info.raison or Json.null,
        }
    end
    for _, etape in ipairs(Photos.lireJson(photo, 'etapesClaude', {})) do
        if type(etape) == 'table' then
            ajouter(etape.id, etape.nom, true)
        end
    end
    -- Les étapes défaites (undo_last, revert_to_original) ou sorties des MAX_ETAPES dernières de la
    -- mémoire gardent leurs images jusqu'au ménage.
    local defaites = {}
    for _, nom in ipairs(dossier and Fichiers.entrees(dossier) or {}) do
        local id = nom:match('^(.+)%.json$')
        if id and not vus[id] then
            local lu = lireEtat(dossier, id)
            defaites[#defaites + 1] = { id = id, nom = lu and lu.etape, le = lu and tonumber(lu.le) or 0 }
        end
    end
    table.sort(defaites, function(a, b)
        if a.le ~= b.le then
            return a.le < b.le
        end
        return a.id < b.id
    end)
    for _, etape in ipairs(defaites) do
        ajouter(etape.id, etape.nom, false)
    end
    return { photo = Photos.decrire(photo, false), etapes = liste }
end

-- Ménage ----------------------------------------------------------------------------------------

-- Au chargement du module : la vue et les préparations d'une session passée, les fichiers de plus
-- de JOURS jours, puis les plus anciens tant que le dossier dépasse MAX_OCTETS ; les dossiers
-- vidés. Rend le nombre de fichiers effacés.
function Etapes.menage(heure)
    heure = heure or maintenant()
    local racine = Chemins.etapes()
    if not Fichiers.existe(racine) then
        return 0
    end
    local fichiers, dossiers = {}, {}
    for _, nomDossier in ipairs(Fichiers.entrees(racine)) do
        local dossier = chemin(racine, nomDossier)
        if LrFileUtils.exists(dossier) == 'directory' then
            dossiers[#dossiers + 1] = dossier
            for _, nom in ipairs(Fichiers.entrees(dossier)) do
                local fichier = chemin(dossier, nom)
                local attributs = LrFileUtils.exists(fichier) == 'file' and LrFileUtils.fileAttributes(fichier)
                if attributs then
                    fichiers[#fichiers + 1] = { chemin = fichier, nom = nom, date = tonumber(attributs.fileModificationDate) or heure,
                        taille = tonumber(attributs.fileSize) or 0 }
                end
            end
        end
    end
    local effaces, gardes, total = 0, {}, 0
    for _, f in ipairs(fichiers) do
        if f.nom == Etapes.VUE or f.nom:match('^prepare%-') or heure - f.date > Etapes.JOURS * 86400 then
            effacer(f.chemin)
            effaces = effaces + 1
        else
            gardes[#gardes + 1] = f
            total = total + f.taille
        end
    end
    table.sort(gardes, function(a, b)
        if a.date ~= b.date then
            return a.date < b.date
        end
        return a.chemin < b.chemin
    end)
    local i = 1
    while total > Etapes.MAX_OCTETS and i <= #gardes do
        effacer(gardes[i].chemin)
        total = total - gardes[i].taille
        effaces = effaces + 1
        i = i + 1
    end
    for _, dossier in ipairs(dossiers) do
        if #Fichiers.entrees(dossier) == 0 then
            effacer(dossier)
        end
    end
    if effaces > 0 then
        Liaison.noter(string.format("Avant/après des étapes : %d fichier(s) ancien(s) effacé(s)", effaces))
    end
    return effaces
end

return Etapes
