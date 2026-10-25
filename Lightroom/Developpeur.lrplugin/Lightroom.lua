-- Lightroom.lua : ce que la fenêtre lit de Lightroom et de son entourage : photo active (avec sa
-- note posée, et sa légende quand elle change) et sélection, état de la liaison et mode « Proposer
-- d'abord » (lus directement : la liaison est dans ce même module), connexion de Claude Code, ce
-- que l'onglet Focus montre de Lightroom (Lightroom.infosFocus). À appeler depuis une tâche. (L'écran
-- principal du Mac, que lisait `mcp-developpeur --ecran` pour le voyant Écran, n'est plus lu depuis
-- le correctif 1.3.6 : le voyant est retiré.)

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Preferences = require 'Preferences'
local Texte = require 'Texte'

local Lightroom = {}

-- Drapeau (pickStatus : 1, 0 ou −1), en mots.
local DRAPEAUX = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetee' }

-- Photos d'une sélection comptées dans la clé de son groupe (au-delà, les premières seulement).
Lightroom.MAX_GROUPE = 2000

-- Photo active ({ id, nom, note, drapeau }) et nombre de photos sélectionnées. La note (0 à 5) et
-- le drapeau ('retenue', 'aucun', 'rejetee') posés, pour la carte Note de la fenêtre ; nil si la
-- photo ne les donne pas. `cle` : la photo active et la sélection en un texte ; `groupe` (plusieurs
-- photos sélectionnées) : la clé de la conversation de ce groupe (correctif 1.3.6), l'ensemble de
-- ses photos sans l'ordre ni la photo active (« nombre:ids rangés »).
function Lightroom.photos()
    local info = { selection = 0 }
    local ok = LrTasks.pcall(function()
        local catalogue = LrApplication.activeCatalog()
        local active = catalogue:getTargetPhoto()
        if active then
            info.active = { id = active.localIdentifier, nom = active:getFormattedMetadata('fileName') or '' }
            local photos = catalogue:getTargetPhotos()
            info.selection = #photos
            -- La photo active et la sélection en un texte (Fenetre.suivreSelection) : la photo
            -- active, puis les 500 premières photos de la sélection et leur nombre.
            local ids = { tostring(active.localIdentifier), tostring(#photos) }
            for i = 1, math.min(#photos, 500) do
                ids[#ids + 1] = tostring(photos[i].localIdentifier)
            end
            info.cle = table.concat(ids, ':')
            if #photos > 1 then
                local groupe = {}
                for i = 1, math.min(#photos, Lightroom.MAX_GROUPE) do
                    groupe[i] = tonumber(photos[i].localIdentifier) or 0
                end
                table.sort(groupe)
                for i, id in ipairs(groupe) do
                    groupe[i] = string.format('%d', id)
                end
                info.groupe = tostring(#photos) .. ':' .. table.concat(groupe, ':')
            end
            local okNote, note, drapeau = LrTasks.pcall(function()
                return active:getRawMetadata('rating'), active:getRawMetadata('pickStatus')
            end)
            if okNote then
                info.active.note = math.floor(tonumber(note) or 0)
                info.active.drapeau = DRAPEAUX[tonumber(drapeau) or 0] or 'aucun'
            end
        end
    end)
    if not ok then
        info.active = nil
    end
    return info
end

-- (Lightroom.photo, la photo d'une ancienne conversation choisie dans la liste du volet, est retirée
-- au correctif 1.3.6 : la fenêtre montre toujours la conversation de la photo choisie dans
-- Lightroom.)

-- La légende d'une photo, pour l'aperçu de la photo active et l'en-tête de la fenêtre (fenêtre B,
-- 1.3) : { nom (son nom de fichier), copie (le nom de sa copie virtuelle), appareil (le modèle du
-- boîtier), date (de prise de vue : « 10 juil. 2020 ») }, une table neuve de textes, chacun absent
-- s'il ne se lit pas. La date se lit à l'heure locale (timeToUserFormat : timeToW3CDate donne
-- l'UTC, constaté), les mois par Carnet.MOIS_COURTS, leur seule copie. Lue seulement quand la photo
-- active change (Fenetre.majPhoto) : Lightroom.photos, toutes les 2 s, n'en lit rien. À appeler
-- depuis une tâche.
function Lightroom.legende(id)
    local l = {}
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if not photo then
            return
        end
        local function texte(cle)
            local ok, v = LrTasks.pcall(function() return photo:getFormattedMetadata(cle) end)
            v = ok and type(v) == 'string' and Texte.nettoyer(v) or ''
            return v ~= '' and v or nil
        end
        l.nom, l.copie, l.appareil = texte('fileName'), texte('copyName'), texte('cameraModel')
        local ok, prise = LrTasks.pcall(function() return photo:getRawMetadata('dateTimeOriginal') end)
        if ok and type(prise) == 'number' then
            local jour = tonumber(LrDate.timeToUserFormat(prise, '%d'))
            local mois = require('Carnet').MOIS_COURTS[tonumber(LrDate.timeToUserFormat(prise, '%m')) or 0]
            local annee = LrDate.timeToUserFormat(prise, '%Y')
            if jour and mois and annee then
                l.date = string.format('%d %s %s', jour, mois, annee)
            end
        end
    end)
    return l
end

-- Ce que l'onglet Focus montre de Lightroom (demandé par Dany le 22 octobre 2026 : les sections
-- Image Information et Shooting Information de Focus-Points), en textes déjà traduits par
-- Lightroom (getFormattedMetadata, clé par clé sous LrTasks.pcall comme Photos.meta : une clé
-- refusée ne gêne pas les autres ; jamais une lecture groupée), sous les clés de
-- Lightroom.CLES_FOCUS, plus `date` (date et heure de la prise de vue, à l'heure locale :
-- « 13 janv. 2026 à 09:13:04 »). Une table neuve de textes, chacun absent s'il ne se lit pas. Une
-- copie virtuelle donne le nom de son original. Le boîtier (stabilisation, mode d'entraînement,
-- mise au point) vient du connecteur (Images.lireFocus). À appeler depuis une tâche.
Lightroom.CLES_FOCUS = {
    nom = 'fileName', copie = 'copyName', origine = 'dimensions', actuelle = 'croppedDimensions',
    marque = 'cameraMake', modele = 'cameraModel', objectif = 'lens', focale = 'focalLength', vitesse = 'shutterSpeed',
    ouverture = 'aperture', iso = 'isoSpeedRating', correction = 'exposureBias', programme = 'exposureProgram',
    mesure = 'meteringMode',
}

function Lightroom.infosFocus(id)
    local l = {}
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if not photo then
            return
        end
        for cle, nom in pairs(Lightroom.CLES_FOCUS) do
            local ok, v = LrTasks.pcall(function() return photo:getFormattedMetadata(nom) end)
            v = ok and (type(v) == 'string' or type(v) == 'number') and Texte.nettoyer(tostring(v)) or ''
            l[cle] = v ~= '' and v or nil
        end
        local ok, prise = LrTasks.pcall(function() return photo:getRawMetadata('dateTimeOriginal') end)
        if ok and type(prise) == 'number' then
            local jour = tonumber(LrDate.timeToUserFormat(prise, '%d'))
            local mois = require('Carnet').MOIS_COURTS[tonumber(LrDate.timeToUserFormat(prise, '%m')) or 0]
            if jour and mois then
                l.date = string.format('%d %s %s à %s', jour, mois, LrDate.timeToUserFormat(prise, '%Y'),
                    LrDate.timeToUserFormat(prise, '%H:%M:%S'))
            end
        end
    end)
    return l
end

-- « DSCF4961 » pour DSCF4961.RAF.
function Lightroom.nomCourt(nom)
    return (tostring(nom or ''):gsub('%.[^.]*$', ''))
end

-- « ★★★☆☆ » pour 3 (de 0 à 5 étoiles).
function Lightroom.etoiles(note)
    local n = math.max(0, math.min(5, math.floor(tonumber(note) or 0)))
    return string.rep('★', n) .. string.rep('☆', 5 - n)
end

-- La ligne de contexte jointe à chaque demande.
function Lightroom.contexte(info)
    if not info.active then
        return "[Lightroom : aucune photo active ni sélectionnée]"
    end
    local selection = info.selection == 1 and "1 photo" or (tostring(info.selection) .. " photos")
    return string.format("[Lightroom : photo active %s (%s) ; sélection : %s]", tostring(info.active.id), info.active.nom, selection)
end

-- État de la liaison avec le serveur : 'active', 'erreur' (ports tenus par un autre Lightroom,
-- par exemple) ou 'arretee', et l'erreur s'il y en a une.
function Lightroom.liaison()
    if not Liaison.actif then
        return 'arretee'
    elseif Liaison.erreur then
        return 'erreur', Liaison.erreur
    end
    return 'active'
end

-- Démarre la liaison si elle est arrêtée, ou la relance après une erreur (clic sur le voyant de
-- la fenêtre).
function Lightroom.demarrerLiaison()
    if Liaison.actif and Liaison.erreur then
        Liaison.arreter()
    end
    if not Liaison.actif then
        Liaison.demarrer()
    end
end

-- Mode de la liaison : 'proposer' (Proposer d'abord) ou 'appliquer', celui de la préférence `mode`
-- que le Gestionnaire de modules externes règle (la fenêtre n'a plus de radios pour le changer,
-- correctif 1.3.6).
function Lightroom.mode()
    local ok, prefs = pcall(Preferences.lire)
    if ok and prefs and prefs.mode == 'proposer' then
        return 'proposer'
    end
    return 'appliquer'
end

-- Connexion de Claude Code (`claude auth status`) : { installe, connecte, forfait, texte }.
function Lightroom.etatClaude(claude)
    if not Fichiers.existe(claude) then
        return { installe = false, connecte = false, texte = "Claude Code introuvable" }
    end
    Fichiers.creerDossier(Chemins.temporaire())
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'auth-' .. Conversation.identifiant() .. '.json')
    LrTasks.execute('/usr/bin/env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL ' .. Texte.shell(claude)
        .. ' auth status > ' .. Texte.shell(sortie) .. ' 2>/dev/null')
    local texte = Fichiers.lire(sortie) or ''
    Fichiers.supprimer(sortie)
    local ok, json = pcall(Json.decode, texte)
    if not ok or type(json) ~= 'table' then
        return { installe = true, connecte = nil, texte = "Claude Code" }
    end
    if json.loggedIn ~= true then
        return { installe = true, connecte = false, texte = "Claude Code · non connecté" }
    end
    local forfait = json.authMethod == 'claude.ai'
    return { installe = true, connecte = true, forfait = forfait, texte = forfait and "Claude Code · forfait" or "Claude Code · " .. tostring(json.authMethod) }
end

-- Sélectionne une photo du catalogue par son identifiant (numéros cités par Claude).
function Lightroom.selectionner(id)
    LrTasks.pcall(function()
        local catalogue = LrApplication.activeCatalog()
        local photo = catalogue:getPhotoByLocalId(tonumber(id))
        if photo then
            catalogue:setSelectedPhotos(photo, {})
        end
    end)
end

return Lightroom
