-- Variantes.lua : interprétations d'une photo rangées en instantanés de Lightroom (panneau
-- Instantanés), sans copie virtuelle.
--
-- Une variante se prépare comme une proposition (Rendu.essayer avec `instantane`) : appliquée,
-- rangée en instantané « Claude · <nom> », rendue, puis la photo revient comme avant. La mémoire de
-- la photo (champ variantesClaude) garde, pour chaque variante, les réglages qu'elle touche.
-- Choisir une variante (commande variantes, action choisir) pose son instantané par
-- applyDevelopSnapshot, comme une étape que undo_last défait : la valeur d'avant de chacun de ces
-- réglages va dans la mémoire, écrite avant. L'instantané remet aussi ce que la photo avait au
-- moment de la variante : un réglage changé depuis, hors de ceux de la variante, ne se défait pas.
--
-- Relevé dans le code de Lightroom Classic 15.6 (LrPhoto, DevelopTemplateBrowser,
-- DevelopSnapshotDataModel) : applyDevelopSnapshot et deleteDevelopSnapshot passent par des
-- commandes du module Développement (ag.develop.applySnapshotSettings, ag.develop.removeSnapshot),
-- les mêmes que le panneau Instantanés. Constaté le 17 octobre 2026 : dans une écriture,
-- applyDevelopSnapshot ne change rien ; hors écriture non plus, tant que la photo n'est pas affichée
-- dans le module Développement ; affichée (Amelioration.afficherEnDeveloppement), elle prend
-- l'instantané par son snapshotID (un uuid). L'effacement se fait de même, photo affichée, par son
-- id_global.
-- createDevelopSnapshot, lui, s'appelle dans une écriture (référence du SDK), sans affichage.

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Amelioration = require 'Amelioration'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local decrire, garder, lireJson, photoVisee = Photos.decrire, Photos.garder, Photos.lireJson, Photos.photoVisee
local DEFAUTS, pourLightroom, resume = Reglages.DEFAUTS, Reglages.pourLightroom, Reglages.resume
local ajouterJournal, creerInstantane, ecrire = Ecriture.ajouterJournal, Ecriture.creerInstantane, Ecriture.ecrire
local ecrireMemoire = Ecriture.ecrireMemoire
local modeTexte, nomEtape, nouvelleEtape = Ecriture.modeTexte, Ecriture.nomEtape, Ecriture.nouvelleEtape
local sansRetouche, verifierAccord = Ecriture.sansRetouche, Ecriture.verifierAccord
local verifierPause, verifierProtection = Ecriture.verifierPause, Ecriture.verifierProtection

local Variantes = {}

local function echouer(message)
    error(message, 0)
end

-- « chaude », « Claude · chaude » → « Claude · chaude » : le nom de l'instantané.
function Variantes.nomInstantane(nom)
    return nomEtape({ etape = nom }, "variante")
end

-- Les instantanés de la photo : { id, nom } (getDevelopSnapshots : snapshotID, name, id_global).
local function instantanes(photo)
    local liste = {}
    local ok, entrees = LrTasks.pcall(photo.getDevelopSnapshots, photo)
    for _, e in ipairs(ok and type(entrees) == 'table' and entrees or {}) do
        liste[#liste + 1] = { id = e.snapshotID, uuid = e.id_global, nom = tostring(e.name or '') }
    end
    return liste
end

local function trouver(photo, nom)
    for _, instantane in ipairs(instantanes(photo)) do
        if instantane.nom == nom then
            return instantane
        end
    end
    return nil
end

-- Range l'état actuel de la photo (une proposition appliquée) en instantané, avec les réglages que
-- la variante touche (dans sa propre écriture).
function Variantes.ranger(photo, nom, cles)
    local complet = Variantes.nomInstantane(nom)
    local memoire = lireJson(photo, 'variantesClaude', {})
    local liste = Json.tableau()
    for cle in pairs(cles) do
        liste[#liste + 1] = cle
    end
    table.sort(liste)
    local ok, date = pcall(LrDate.timeToUserFormat, LrDate.currentTime(), '%Y-%m-%d %H:%M')
    memoire[complet] = { cles = liste, le = ok and date or '' }
    ecrire(complet, function()
        photo:createDevelopSnapshot(complet, true)
        garder(photo, 'variantesClaude', Json.encode(memoire))
    end)
    return complet
end

local function lister(photo)
    local memoire = lireJson(photo, 'variantesClaude', {})
    local liste = Json.tableau()
    for _, instantane in ipairs(instantanes(photo)) do
        local info = memoire[instantane.nom]
        if info then
            liste[#liste + 1] = { nom = instantane.nom, reglages = Json.tableau(info.cles or {}), le = info.le }
        end
    end
    return liste
end

-- Pose l'instantané d'une variante comme une étape de Claude. Les réglages de l'étape sont ceux de
-- la variante (« ma version » d'un ancien exercice « Je le fais », retiré au correctif 1.3.6, comme
-- les autres). L'entrée du journal, écrite avec la mémoire avant la pose, est réécrite après avec
-- ses changements (export_journal).
local function choisir(photo, params, prefs)
    local nom = Variantes.nomInstantane(params.nom)
    local instantane = trouver(photo, nom)
    if not instantane and trouver(photo, tostring(params.nom)) then
        echouer("L'instantané « " .. tostring(params.nom) .. " » n'est pas une variante préparée par Claude : l'utilisateur peut le poser lui-même dans le panneau Instantanés.")
    end
    local memoire = lireJson(photo, 'variantesClaude', {})
    local info = memoire[nom]
    if not instantane then
        echouer("Aucun instantané « " .. nom .. " » sur cette photo (compare_variants le prépare ; variantes offertes : choose_variant avec action « list »).")
    end
    if not info then
        echouer("L'instantané « " .. nom .. " » n'est pas une variante préparée par Claude : l'utilisateur peut le poser lui-même dans le panneau Instantanés.")
    end
    local etape = nomEtape(params, "variante " .. nom:gsub('^Claude · ', ''))
    local actuels = photo:getDevelopSettings()
    local cles = {}
    for _, cle in ipairs(info.cles or {}) do
        cles[#cles + 1] = cle
    end
    local avant = {}
    for _, cle in ipairs(cles) do
        if actuels[cle] ~= nil then
            avant[cle] = pourLightroom(actuels[cle])
        elseif DEFAUTS[cle] ~= nil then
            avant[cle] = DEFAUTS[cle]
        end
    end
    local original = lireJson(photo, 'avantClaude', {})
    local etapes = lireJson(photo, 'etapesClaude', {})
    local journal = lireJson(photo, 'journalClaude', {})
    local entree = { etape = etape, type = 'retouche', raison = params.raison, changements = Json.tableau() }
    -- La mémoire d'abord (écriture privée, hors de Édition › Annuler : Lightroom écrit lui-même
    -- l'étape de l'instantané posé), puis l'instantané (hors écriture).
    if sansRetouche(original) and prefs.instantane then
        ecrire(etape, function() creerInstantane(photo) end)
    end
    -- L'étape et son id (1.3), dans la mémoire, le journal (etape_id) et la réponse.
    local etapeId = nouvelleEtape(etapes, etape, avant)
    entree.etape_id = etapeId
    ecrireMemoire(etape, function()
        for cle, valeur in pairs(avant) do
            if original[cle] == nil then
                original[cle] = valeur
            end
        end
        ajouterJournal(journal, entree)
        garder(photo, 'avantClaude', Json.encode(original))
        garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
        garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
        garder(photo, 'retoucheeParClaude', 'oui')
    end)
    -- Lightroom pose l'instantané par une commande : relu jusqu'à ce qu'il ait changé.
    local function change(apres)
        for _, cle in ipairs(cles) do
            if not Reglages.egal(actuels[cle], apres[cle]) then
                return true
            end
        end
        return #cles == 0
    end
    local function attendre(secondes)
        local apres = photo:getDevelopSettings()
        for _ = 1, secondes * 10 do
            if change(apres) then
                return apres, true
            end
            LrTasks.sleep(0.1)
            apres = photo:getDevelopSettings()
        end
        return apres, change(apres)
    end
    local pose, erreur, apres, fait
    Amelioration.avecVerrou(function()
        local vue = Amelioration.afficherEnDeveloppement(photo, import 'LrDevelopController')
        pose, erreur = LrTasks.pcall(photo.applyDevelopSnapshot, photo, instantane.id)
        apres, fait = attendre(3)
        Amelioration.remettreVue(vue)
    end)
    -- Ce qui a changé, pour la réponse et le journal.
    for _, cle in ipairs(cles) do
        if not Reglages.egal(actuels[cle], apres[cle]) then
            entree.changements[#entree.changements + 1] = { cle = cle, avant = resume(cle, actuels[cle]) or Json.null,
                apres = resume(cle, apres[cle]) or Json.null }
        end
    end
    if #entree.changements == 0 and #cles > 0 then
        -- Rien n'a changé : l'étape notée ne doit pas rester dans la mémoire, ni son entrée au journal.
        table.remove(etapes)
        for i = #journal, 1, -1 do
            if journal[i] == entree then
                table.remove(journal, i)
                break
            end
        end
        ecrireMemoire(etape .. " (retirée)", function()
            garder(photo, 'etapesClaude', Json.encode(Json.tableau(etapes)))
            garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
        end)
        echouer("Lightroom n'a pas posé l'instantané « " .. nom .. " »" .. (pose and "" or (" : " .. Liaison.messageErreur(erreur)))
            .. ". Rien n'a changé : l'utilisateur peut le poser lui-même dans le panneau Instantanés.")
    end
    -- L'entrée du journal a été écrite avant la pose, sans ses changements (inconnus alors) :
    -- réécrite avec eux, sinon export_journal ne voit pas les réglages de la variante.
    if #entree.changements > 0 then
        ecrireMemoire(etape .. " (journal)", function()
            garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
        end)
    end
    Liaison.noter("Variante « " .. nom .. " » posée", photo.localIdentifier)
    return { photo = decrire(photo, false), etape = etape, etape_id = etapeId, instantane = nom, changements = entree.changements }
end

-- Efface des instantanés de variantes de Claude (tous, ou ceux nommés), et leur mémoire. Un nom
-- donné qui porte le préfixe « Claude · » s'efface même sans mémoire (variante d'un essai
-- interrompu). Hors écriture (commande de Lightroom), puis la mémoire dans une écriture.
local function effacer(photo, params, garde)
    local memoire = lireJson(photo, 'variantesClaude', {})
    local voulus
    if type(params.noms) == 'table' and #params.noms > 0 then
        voulus = {}
        for _, nom in ipairs(params.noms) do
            voulus[Variantes.nomInstantane(nom)] = true
        end
    end
    local effaces = Json.tableau()
    local cibles = {}
    for _, instantane in ipairs(instantanes(photo)) do
        local deClaude = memoire[instantane.nom] or (voulus and voulus[instantane.nom])
        if deClaude and instantane.nom ~= garde and (not voulus or voulus[instantane.nom]) then
            cibles[#cibles + 1] = instantane
        end
    end
    if #cibles == 0 then
        return effaces
    end
    -- Photo affichée dans le module Développement ; la commande attend l'id_global (constaté).
    Amelioration.avecVerrou(function()
        local vue = Amelioration.afficherEnDeveloppement(photo, import 'LrDevelopController')
        for _, instantane in ipairs(cibles) do
            LrTasks.pcall(photo.deleteDevelopSnapshot, photo, instantane.uuid)
            for _ = 1, 10 do
                if not trouver(photo, instantane.nom) then
                    break
                end
                LrTasks.sleep(0.1)
            end
            if not trouver(photo, instantane.nom) then
                effaces[#effaces + 1] = instantane.nom
                memoire[instantane.nom] = nil
            end
        end
        Amelioration.remettreVue(vue)
    end)
    if #effaces > 0 then
        ecrireMemoire("Claude · instantanés de variantes effacés", function()
            garder(photo, 'variantesClaude', Json.encode(memoire))
        end)
    end
    return effaces
end

-- Commande « variantes » : lister, choisir (et effacer les autres si demandé), effacer.
function Variantes.variantes(params)
    local photo = photoVisee(params)
    local action = tostring(params.action or 'lister')
    if action == 'lister' then
        return { photo = decrire(photo, false), variantes = lister(photo) }
    end
    if action ~= 'choisir' and action ~= 'effacer' then
        echouer("Action inconnue : « " .. action .. " » (lister, choisir ou effacer).")
    end
    verifierPause(params)
    local prefs = Preferences.lire()
    if action == 'effacer' then
        return { photo = decrire(photo, false), effaces = effacer(photo, params) }
    end
    verifierAccord(prefs, params, 'choose_variant')
    verifierProtection({ photo }, prefs, params, 'choose_variant')
    local resultat = choisir(photo, params, prefs)
    Ecriture.noterEtatFinal({ photo }, resultat.etape)
    resultat.mode = modeTexte(prefs)
    if params.effacer_autres then
        resultat.effaces = effacer(photo, {}, resultat.instantane)
    end
    return resultat
end

return Variantes
