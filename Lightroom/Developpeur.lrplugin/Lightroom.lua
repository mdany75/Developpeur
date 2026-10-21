-- Lightroom.lua : ce que la fenêtre lit de Lightroom et de son entourage : photo active (avec sa
-- note posée) et sélection, état de la liaison et mode « Proposer d'abord » (lus directement : la
-- liaison est dans ce même module), connexion de Claude Code. À appeler depuis une tâche.

local LrApplication = import 'LrApplication'
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

-- Photo active ({ id, nom, note, drapeau }) et nombre de photos sélectionnées. La note (0 à 5) et
-- le drapeau ('retenue', 'aucun', 'rejetee') posés, pour la carte Note de la fenêtre ; nil si la
-- photo ne les donne pas.
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

-- Mode de la liaison : 'proposer' (Proposer d'abord) ou 'appliquer'.
function Lightroom.mode()
    local ok, prefs = pcall(Preferences.lire)
    if ok and prefs and prefs.mode == 'proposer' then
        return 'proposer'
    end
    return 'appliquer'
end

function Lightroom.basculerMode()
    Preferences.lire().mode = Lightroom.mode() == 'proposer' and 'appliquer' or 'proposer'
    return Lightroom.mode()
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
