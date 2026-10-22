-- Stockage.lua : les conversations sur le disque, une par dossier
-- (Conversations/<id>/conversation.json et ses images), celles des anciennes séances de notation
-- comprises (genre = 'notation'). Les listes d'un élément (images, changements, notes, et en 1.3
-- etapes, annule, revenu, les points d'une leçon et leurs défauts, la liste à faire d'un exercice
-- « Je le fais », ses écarts et les réglages faits comme Claude) s'écrivent toujours en tableaux
-- JSON.
-- Aussi les demandes personnelles de Dany, le menu Mes demandes de la fenêtre (mes-demandes.json,
-- section « Mes demandes » en bas de ce fichier).

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Texte = require 'Texte'

local Stockage = {}

-- Format écrit dans chaque conversation.json.
Stockage.FORMAT = 'developpeur/1'

-- Les textes d'un réglage à faire ou d'un écart d'un exercice « Je le fais » (1.3) : relus
-- seulement s'ils sont des textes (la carte et le fil les mettent bout à bout).
local CHAMPS_TEXTE_EXERCICE = { 'panneau', 'section', 'reglage', 'cle', 'texte', 'sorte', 'de', 'a' }

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
        -- Un exercice « Je le fais » (1.3) : sa liste (avec les clés du cadre), ses écarts et les
        -- réglages faits comme Claude, des tableaux même vides.
        if e.genre == 'exercice' then
            local aFaire = Json.tableau()
            for j, item in ipairs(e.aFaire or {}) do
                local y = {}
                for cle, valeur in pairs(item) do
                    y[cle] = valeur
                end
                if type(item.cles) == 'table' then
                    local cles = Json.tableau()
                    for k, nom in ipairs(item.cles) do
                        cles[k] = nom
                    end
                    y.cles = cles
                end
                aFaire[j] = y
            end
            x.aFaire = aFaire
            for _, cle in ipairs({ 'ecarts', 'commeClaude' }) do
                local liste = Json.tableau()
                for j, valeur in ipairs(e[cle] or {}) do
                    liste[j] = valeur
                end
                x[cle] = liste
            end
            x.comparaisonEnCours = nil
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
            -- Seulement des points en table, chacun avec sa liste de défauts : le fil et
            -- l'enregistrement les parcourent (un fichier abîmé ne doit pas bloquer la fenêtre).
            local points = {}
            for _, p in ipairs(type(e.points) == 'table' and e.points or {}) do
                if type(p) == 'table' then
                    if type(p.defauts) ~= 'table' then
                        p.defauts = {}
                    end
                    points[#points + 1] = p
                end
            end
            e.points = points
        end
        -- Un appel resté en cours (Lightroom fermé pendant l'appel) n'a pas abouti.
        if (e.genre == 'outil' or e.genre == 'notation' or e.genre == 'lecon' or e.genre == 'exercice') and e.etat == 'enCours' then
            e.etat = 'erreur'
        end
        if e.genre == 'exercice' then
            -- Seulement des réglages et des écarts en table, et des textes en texte (un fichier
            -- abîmé ne doit pas bloquer le fil ni la carte) ; une comparaison restée en cours
            -- n'aboutira plus.
            for _, cle in ipairs({ 'aFaire', 'ecarts' }) do
                local gardes = {}
                for _, x in ipairs(type(e[cle]) == 'table' and e[cle] or {}) do
                    if type(x) == 'table' then
                        for _, champ in ipairs(CHAMPS_TEXTE_EXERCICE) do
                            if type(x[champ]) ~= 'string' then
                                x[champ] = nil
                            end
                        end
                        gardes[#gardes + 1] = x
                    end
                end
                e[cle] = gardes
            end
            if type(e.commeClaude) ~= 'table' then
                e.commeClaude = {}
            end
            if type(e.principal) ~= 'table' then
                e.principal = nil
            elseif type(e.principal.texte) ~= 'string' then
                e.principal.texte = nil
            end
            for _, champ in ipairs({ 'texte', 'resume', 'aSavoir', 'fichier', 'instantane', 'comparaisonRefusee' }) do
                if type(e[champ]) ~= 'string' then
                    e[champ] = nil
                end
            end
            e.comparaisonEnCours = nil
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

-- Mes demandes -----------------------------------------------------------------------------------
-- Les demandes personnelles de Dany (demandé par Dany le 22 octobre 2026) : le menu Mes demandes de
-- la fenêtre Claude, à droite du menu Style, les met dans le champ de demande. Rangées dans
-- mes-demandes.json (Chemins.racine()) : { format = 1, demandes = [ { nom, description, texte } ] },
-- par nom (sans tenir compte des majuscules ni des accents), écrit d'un coup (Fichiers.ecrire :
-- provisoire, puis renommé), relu à chaque ouverture de la fenêtre et avant chaque changement. Un
-- fichier illisible (ou d'un autre format) n'est jamais écrasé ni perdu en silence : le journal le
-- dit à la lecture, et il est mis de côté (mes-demandes-illisible-<date>.json) avant la première
-- écriture, comme carnet.json (Carnet.lua). Tout ce qui sort d'ici est fait de tables neuves (jamais
-- une table relue par Json.decode : Lightroom bloque sur sa métatable). uninstall.sh --tout le
-- retire ; sans --tout, il reste.

Stockage.FORMAT_DEMANDES = 1

-- Les refus d'une demande, dits dans sa fenêtre (Ajouter…, Renommer…).
Stockage.NOM_VIDE = "Donnez un nom à la demande."
Stockage.NOM_PRIS = "Une autre demande porte déjà ce nom : choisissez-en un autre."
Stockage.TEXTE_VIDE = "Écrivez le texte de la demande."
Stockage.DEMANDE_INTROUVABLE = "Cette demande n'est plus dans Mes demandes."

function Stockage.fichierDemandes()
    return LrPathUtils.child(Chemins.racine(), 'mes-demandes.json')
end

-- Un texte d'une seule ligne (le nom, la description) : espaces et sauts de ligne ramenés à une
-- espace.
local function uneLigne(valeur)
    return Texte.nettoyer((tostring(valeur or ''):gsub('%s+', ' ')))
end

-- Une demande propre et neuve, nil si elle n'a ni nom ni texte : nom et description sur une ligne,
-- texte tel quel, sans les blancs du début et de la fin.
local function demandePropre(d)
    if type(d) ~= 'table' or type(d.nom) ~= 'string' or type(d.texte) ~= 'string' then
        return nil
    end
    local propre = { nom = uneLigne(d.nom), description = type(d.description) == 'string' and uneLigne(d.description) or '',
        texte = Texte.nettoyer(d.texte) }
    if propre.nom == '' or propre.texte == '' then
        return nil
    end
    return propre
end

local function cleNom(nom)
    return Texte.plier(uneLigne(nom))
end

local function trier(liste)
    table.sort(liste, function(a, b)
        local ka, kb = cleNom(a.nom), cleNom(b.nom)
        if ka ~= kb then
            return ka < kb
        end
        return a.nom < b.nom
    end)
    return liste
end

-- Les demandes rangées, triées par nom, en tables neuves ; puis vrai si le fichier est là mais
-- illisible (rien n'en est lu, il sera mis de côté avant la première écriture).
function Stockage.lireDemandes()
    local contenu = Fichiers.lire(Stockage.fichierDemandes())
    if contenu == nil or Texte.nettoyer(contenu) == '' then
        return {}, false
    end
    local ok, r = pcall(Json.decode, contenu)
    if not ok or type(r) ~= 'table' or tonumber(r.format) ~= Stockage.FORMAT_DEMANDES or type(r.demandes) ~= 'table' then
        Journal.noter("Mes demandes : mes-demandes.json illisible, gardé tel quel :", tostring(ok and 'format inconnu' or r))
        return {}, true
    end
    local liste, vus = {}, {}
    for _, d in ipairs(r.demandes) do
        local propre = demandePropre(d)
        if propre and not vus[cleNom(propre.nom)] then
            vus[cleNom(propre.nom)] = true
            liste[#liste + 1] = propre
        end
    end
    return trier(liste), false
end

-- Écrit la liste entière (un fichier illisible mis de côté d'abord). Rend vrai, ou faux et la
-- raison.
function Stockage.ecrireDemandes(liste, illisible)
    local fichier = Stockage.fichierDemandes()
    if illisible and Fichiers.existe(fichier) then
        local aCote = LrPathUtils.child(Chemins.racine(), 'mes-demandes-illisible-' .. tostring(os.time()) .. '.json')
        pcall(LrFileUtils.move, fichier, aCote)
        if Fichiers.existe(fichier) or not Fichiers.existe(aCote) then
            Journal.noter("Mes demandes : mes-demandes.json illisible non mis de côté, rien n'est écrit")
            return false, "mes-demandes.json est illisible et n'a pas pu être mis de côté : rien n'est écrit."
        end
        Journal.noter("Mes demandes : mes-demandes.json illisible mis de côté :", aCote)
    end
    local demandes = Json.tableau()
    for k, d in ipairs(trier(liste)) do
        demandes[k] = { nom = d.nom, description = d.description or '', texte = d.texte }
    end
    local ok, erreur = pcall(Fichiers.ecrire, fichier, Json.encode({ format = Stockage.FORMAT_DEMANDES, demandes = demandes }))
    if not ok then
        Journal.noter("Mes demandes non enregistrées :", tostring(erreur))
        return false, "Mes demandes non enregistrées : " .. tostring(erreur)
    end
    return true
end

-- L'indice de la demande de ce nom (sans tenir compte des majuscules ni des accents), nil sans
-- elle.
function Stockage.indiceDemande(liste, nom)
    local cle = cleNom(nom)
    for k, d in ipairs(liste) do
        if cleNom(d.nom) == cle then
            return k
        end
    end
    return nil
end

-- Le refus d'une demande `d` ({ nom, description, texte }) dans `liste`, la demande `ancien` (son
-- nom, quand elle en remplace une) mise à part : une phrase pour Dany, nil si elle se garde.
function Stockage.refusDemande(liste, d, ancien)
    if uneLigne(d and d.nom) == '' then
        return Stockage.NOM_VIDE
    end
    local k = Stockage.indiceDemande(liste, d.nom)
    if k and not (ancien and cleNom(liste[k].nom) == cleNom(ancien)) then
        return Stockage.NOM_PRIS
    end
    if Texte.nettoyer(d.texte) == '' then
        return Stockage.TEXTE_VIDE
    end
    return nil
end

-- Un nom libre tiré de `nom` : lui-même, sinon « nom 2 », « nom 3 »…
function Stockage.nomLibre(liste, nom)
    nom = uneLigne(nom)
    if nom == '' or not Stockage.indiceDemande(liste, nom) then
        return nom
    end
    local n = 2
    while Stockage.indiceDemande(liste, nom .. ' ' .. n) do
        n = n + 1
    end
    return nom .. ' ' .. n
end

-- Relit le fichier, applique `changer(liste)` (qui rend nil, ou la raison d'un refus), puis écrit.
-- Rend vrai et la liste écrite, ou faux et la raison.
local function changerDemandes(changer)
    local liste, illisible = Stockage.lireDemandes()
    local refus = changer(liste)
    if refus then
        return false, refus
    end
    local ok, raison = Stockage.ecrireDemandes(liste, illisible)
    if not ok then
        return false, raison
    end
    return true, trier(liste)
end

-- Garde une nouvelle demande. Rend vrai et la liste, ou faux et le refus.
function Stockage.garderDemande(d)
    return changerDemandes(function(liste)
        local refus = Stockage.refusDemande(liste, d)
        if refus then
            return refus
        end
        liste[#liste + 1] = demandePropre(d)
        return nil
    end)
end

-- Remplace la demande nommée `ancien` par `d` (autre nom, autre description, autre texte).
function Stockage.changerDemande(ancien, d)
    return changerDemandes(function(liste)
        local k = Stockage.indiceDemande(liste, ancien)
        if not k then
            return Stockage.DEMANDE_INTROUVABLE
        end
        local refus = Stockage.refusDemande(liste, d, ancien)
        if refus then
            return refus
        end
        liste[k] = demandePropre(d)
        return nil
    end)
end

-- Retire la demande nommée `nom`.
function Stockage.retirerDemande(nom)
    return changerDemandes(function(liste)
        local k = Stockage.indiceDemande(liste, nom)
        if not k then
            return Stockage.DEMANDE_INTROUVABLE
        end
        table.remove(liste, k)
        return nil
    end)
end

return Stockage
