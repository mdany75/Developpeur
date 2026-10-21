-- Stockage.lua : les conversations sur le disque, une par dossier
-- (Conversations/<id>/conversation.json et ses images), celles des anciennes séances de notation
-- comprises (genre = 'notation'). Les listes d'un élément (images, changements, notes, et en 1.3
-- etapes, annule, revenu, les points d'une leçon et leurs défauts) s'écrivent toujours en tableaux
-- JSON.

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
        -- Les étapes écrites par un outil (1.3), chacune avec ses changements, les étapes défaites
        -- (undo_last) et les photos remises (revert_to_original) : des tableaux, même vides (une
        -- conversation de la 1.2 n'en a pas : ils se relisent dans le détail de l'appel).
        if e.etapes ~= nil then
            local etapes = Json.tableau()
            for j, etape in ipairs(e.etapes) do
                local y = {}
                for cle, valeur in pairs(etape) do
                    y[cle] = valeur
                end
                local siens = Json.tableau()
                for k, ch in ipairs(etape.changements or {}) do
                    siens[k] = ch
                end
                y.changements = siens
                etapes[j] = y
            end
            x.etapes = etapes
        end
        for _, cle in ipairs({ 'annule', 'revenu' }) do
            if e[cle] ~= nil then
                local liste = Json.tableau()
                for j, valeur in ipairs(e[cle]) do
                    liste[j] = valeur
                end
                x[cle] = liste
            end
        end
        -- Les points d'une leçon (1.3), et les défauts de chaque point : des tableaux, même vides.
        if e.genre == 'lecon' then
            local points = Json.tableau()
            for j, point in ipairs(e.points or {}) do
                local y = {}
                for cle, valeur in pairs(point) do
                    y[cle] = valeur
                end
                local defauts = Json.tableau()
                for k, d in ipairs(point.defauts or {}) do
                    defauts[k] = d
                end
                y.defauts = defauts
                points[j] = y
            end
            x.points = points
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
        if e.genre == 'lecon' then
            e.points = e.points or {}
        end
        -- Un appel resté en cours (Lightroom fermé pendant l'appel) n'a pas abouti.
        if (e.genre == 'outil' or e.genre == 'notation' or e.genre == 'lecon') and e.etat == 'enCours' then
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
