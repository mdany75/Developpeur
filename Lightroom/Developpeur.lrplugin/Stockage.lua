-- Stockage.lua : les conversations sur le disque, une par dossier
-- (Conversations/<id>/conversation.json et ses images), séances de notation comprises
-- (genre = 'notation').

local LrPathUtils = import 'LrPathUtils'

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'

local Stockage = {}

-- Format écrit dans chaque conversation.json.
Stockage.FORMAT = 'developpeur/1'

function Stockage.dossier(id)
    return LrPathUtils.child(Chemins.conversations(), id)
end

function Stockage.fichier(id)
    return LrPathUtils.child(Stockage.dossier(id), 'conversation.json')
end

-- Chemin absolu d'une image de la conversation (chemin relatif à son dossier).
function Stockage.image(id, chemin)
    return LrPathUtils.child(Stockage.dossier(id), chemin)
end

-- Une copie prête pour Json.encode : les listes restent des tableaux même vides.
local function pourJson(c)
    local copie = {}
    for cle, valeur in pairs(c) do
        copie[cle] = valeur
    end
    local elements = Json.tableau()
    for i, e in ipairs(c.elements or {}) do
        local x = {}
        for cle, valeur in pairs(e) do
            x[cle] = valeur
        end
        local images = Json.tableau()
        for j, chemin in ipairs(e.images or {}) do
            images[j] = chemin
        end
        x.images = images
        local changements = Json.tableau()
        for j, ch in ipairs(e.changements or {}) do
            changements[j] = ch
        end
        x.changements = changements
        -- Les notes proposées d'une notation : un tableau, même vide.
        if e.notes ~= nil or e.genre == 'notation' then
            local notes = Json.tableau()
            for j, note in ipairs(e.notes or {}) do
                notes[j] = note
            end
            x.notes = notes
        end
        elements[i] = x
    end
    copie.elements = elements
    copie.format = Stockage.FORMAT
    return copie
end

function Stockage.enregistrer(c)
    Fichiers.ecrire(Stockage.fichier(c.id), Json.encode(pourJson(c)))
end

-- Une conversation lue sur le disque, nil si le fichier est illisible.
function Stockage.lire(id)
    local texte = Fichiers.lire(Stockage.fichier(id))
    if not texte then
        return nil
    end
    local ok, c = pcall(Json.decode, texte)
    if not ok or type(c) ~= 'table' or type(c.elements) ~= 'table' then
        Journal.noter("Conversation illisible :", id, tostring(c))
        return nil
    end
    c.id = c.id or id
    -- Un texte en train d'arriver quand Lightroom s'est fermé : gardé tel quel.
    for _, e in ipairs(c.elements) do
        e.partiel = false
        e.images = e.images or {}
        e.changements = e.changements or {}
        if e.genre == 'notation' then
            e.notes = e.notes or {}
        end
        if (e.genre == 'outil' or e.genre == 'notation') and e.etat == 'enCours' then
            e.etat = 'erreur'
        end
    end
    return c
end

-- Toutes les conversations, la plus récente en premier.
function Stockage.charger()
    local liste = {}
    for _, nom in ipairs(Fichiers.entrees(Chemins.conversations())) do
        local c = Stockage.lire(nom)
        if c then
            liste[#liste + 1] = c
        end
    end
    table.sort(liste, function(a, b) return (a.modifiee or 0) > (b.modifiee or 0) end)
    return liste
end

-- À la corbeille du Finder, avec ses images.
function Stockage.supprimer(id)
    return Fichiers.corbeille(Stockage.dossier(id))
end

return Stockage
