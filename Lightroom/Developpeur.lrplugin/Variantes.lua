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
--
-- « Je le fais » (1.3) : Dany fait lui-même la retouche que Claude propose, pour apprendre. La
-- proposition est appliquée le temps d'être rangée en instantané « Claude · ma version »
-- (Rendu.essayer avec exercice et sans_rendu), puis la photo revient comme avant : rien n'est
-- appliqué. La mémoire de cette variante (variantesClaude, sans champ nouveau) garde exercice =
-- { depart, claude, le } : l'état de départ (departExercice) et la version de Claude (chaque
-- réglage de la proposition tel que Lightroom l'a gardé). Le journal reçoit une entrée de type
-- 'exercice' (etape « Claude · je le fais », changements de la proposition {cle, avant, apres}),
-- que la leçon et le carnet lisent comme jamais appliquée. La comparaison (Rendu.apercu, comparer
-- = 'versionClaude') pose la version de Claude le temps d'un rendu (valeursClaude) et dit les
-- écarts réglage par réglage (ecartsExercice). Choisir « ma version » (choose_variant) rend aussi à
-- undo_last les réglages que Dany avait changés hors de la proposition.

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
local COURBE_LINEAIRE, egal, lookVide = Reglages.COURBE_LINEAIRE, Reglages.egal, Reglages.lookVide
local ajouterJournal, creerInstantane, ecrire = Ecriture.ajouterJournal, Ecriture.creerInstantane, Ecriture.ecrire
local difference, ecrireMemoire, etatSimple = Ecriture.difference, Ecriture.ecrireMemoire, Ecriture.etatSimple
local EN_ATTENTE = Ecriture.EN_ATTENTE
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

-- « Je le fais » (1.3) ----------------------------------------------------------------------------

-- Le nom de la variante d'un exercice : l'instantané « Claude · ma version ».
Variantes.EXERCICE = 'ma version'
-- L'étape de l'entrée du journal d'un exercice (la forme que lit la leçon, Lecon.correctionsNettes).
Variantes.ETAPE_EXERCICE = 'Claude · je le fais'

-- Tables gardées entières dans l'état de départ, en plus des réglages simples (etatSimple) : le
-- profil à Look, les courbes et les couleurs ponctuelles, que la comparaison remet si Dany les a
-- changées.
local TABLES_EXERCICE = { 'Look', 'ToneCurvePV2012', 'ToneCurvePV2012Red', 'ToneCurvePV2012Green', 'ToneCurvePV2012Blue',
    'PointColors' }
-- Listes dont le départ ne garde que le nombre (etatSimple) : une liste vide les retire le temps
-- de la comparaison si le départ n'en avait aucune (comme undo_last) ; sinon, une liste que Dany a
-- changée reste dans les deux images (restent).
local LISTES_EXERCICE = { 'MaskGroupBasedCorrections', 'RetouchAreas', 'RedEyeInfo', 'DepthBasedCorrections' }
-- Les nombres que la comparaison rend (listes) : masques, taches, yeux rouges.
local LISTES_MONTREES = { { nom = 'masques', cle = 'MaskGroupBasedCorrections' }, { nom = 'taches', cle = 'RetouchAreas' },
    { nom = 'yeux_rouges', cle = 'RedEyeInfo' } }

local function dansListe(liste, cle)
    for _, element in ipairs(liste) do
        if element == cle then
            return true
        end
    end
    return false
end

local function nombre(etat, cle)
    return tonumber(etat['#' .. cle]) or 0
end

-- État de départ d'un exercice (fonction pure, à lire avant toute écriture) : les réglages simples
-- (etatSimple : nombres, booléens, textes suivis, nom de la Look, nombre d'éléments des listes),
-- les tables de TABLES_EXERCICE en copies neuves (pourLightroom), et le nombre de taches de l'outil
-- Supprimer (#RemoveAreas : Lightroom en dérive RetouchAreas).
function Variantes.departExercice(reglages)
    local etat = etatSimple(reglages)
    for _, cle in ipairs(TABLES_EXERCICE) do
        if type(reglages[cle]) == 'table' then
            etat[cle] = pourLightroom(reglages[cle])
        end
    end
    etat['#RemoveAreas'] = type(reglages.RemoveAreas) == 'table' and #reglages.RemoveAreas or 0
    return etat
end

-- La version de Claude : chaque réglage de la proposition (cles) tel que Lightroom l'a gardé, la
-- proposition appliquée (paramètres prédéfinis du module, tonalité automatique, profil relu
-- compris), sinon la valeur de la proposition, sinon celle par défaut ; jamais une valeur
-- automatique pas encore calculée. Des tables neuves.
local function versionDuPlan(cles, apres, nouveaux)
    local claude = {}
    for cle in pairs(cles) do
        local valeur = apres[cle]
        if valeur == nil then
            valeur = nouveaux[cle]
        end
        if valeur == nil then
            valeur = DEFAUTS[cle]
        end
        if valeur ~= nil and valeur ~= EN_ATTENTE and valeur ~= Json.null then
            claude[cle] = pourLightroom(valeur)
        end
    end
    return claude
end

-- Range l'état actuel de la photo (une proposition appliquée) en instantané, avec les réglages que
-- la variante touche (dans sa propre écriture). Avec exercice ({ depart, avant, nouveaux, raison,
-- changements } : « Je le fais »), la mémoire de la variante garde aussi exercice = { depart,
-- claude, le } (la valeur de départ d'une table de Claude que le départ ne garde pas vient de la
-- proposition : avant), et le journal reçoit l'entrée de l'exercice, dans la même écriture que
-- l'instantané.
function Variantes.ranger(photo, nom, cles, exercice)
    local complet = Variantes.nomInstantane(nom)
    local memoire = lireJson(photo, 'variantesClaude', {})
    local liste = Json.tableau()
    for cle in pairs(cles) do
        liste[#liste + 1] = cle
    end
    table.sort(liste)
    local ok, date = pcall(LrDate.timeToUserFormat, LrDate.currentTime(), '%Y-%m-%d %H:%M')
    memoire[complet] = { cles = liste, le = ok and date or '' }
    local journal
    if exercice then
        local depart = exercice.depart or {}
        local claude = versionDuPlan(cles, photo:getDevelopSettings(), exercice.nouveaux or {})
        local avant = exercice.avant or {}
        for cle, valeur in pairs(claude) do
            if type(valeur) == 'table' and depart[cle] == nil and type(avant[cle]) == 'table'
                and not dansListe(TABLES_EXERCICE, cle) then
                depart[cle] = pourLightroom(avant[cle])
            end
        end
        memoire[complet].exercice = { depart = depart, claude = claude, le = memoire[complet].le }
        journal = lireJson(photo, 'journalClaude', {})
        -- La note le dit dans export_journal, qui liste les changements comme ceux d'une retouche.
        ajouterJournal(journal, { etape = Variantes.ETAPE_EXERCICE, type = 'exercice', raison = exercice.raison,
            changements = exercice.changements or Json.tableau(),
            note = "Version de Claude rangée en instantané « " .. complet
                .. " », non appliquée : l'utilisateur fait la retouche lui-même." })
    end
    ecrire(complet, function()
        photo:createDevelopSnapshot(complet, true)
        garder(photo, 'variantesClaude', Json.encode(memoire))
        if journal then
            garder(photo, 'journalClaude', Json.encode(Json.tableau(journal)))
        end
    end)
    return complet
end

-- L'exercice « Je le fais » rangé pour la photo ({ instantane, depart, claude, le }, des tables
-- neuves, sans métatable), ou nil : aucun, ou sa variante effacée. nom : celui de la variante
-- (Variantes.EXERCICE par défaut).
function Variantes.exercice(photo, nom)
    nom = Variantes.nomInstantane(nom or Variantes.EXERCICE)
    local info = lireJson(photo, 'variantesClaude', {})[nom]
    if type(info) ~= 'table' or type(info.exercice) ~= 'table' then
        return nil
    end
    local ex = pourLightroom(info.exercice)
    if type(ex.depart) ~= 'table' or type(ex.claude) ~= 'table' then
        return nil
    end
    ex.instantane = nom
    return ex
end

-- Ce que Dany a changé depuis le départ de l'exercice (fonction pure) : les réglages simples (cle →
-- valeur de départ), les tables de TABLES_EXERCICE, les listes dont le nombre a changé, et l'état
-- actuel au format du départ.
local function changementsDeDany(ex, actuels)
    local depart = ex.depart or {}
    local maintenant = Variantes.departExercice(actuels)
    local simples, tables, listes = {}, {}, {}
    for _, c in ipairs(difference(depart, maintenant)) do
        local cle = c.cle
        if type(cle) == 'string' and type(c.avant) ~= 'table' and not cle:match('^#') and cle ~= 'Look.Name' then
            simples[cle] = c.avant
        end
    end
    for _, cle in ipairs(TABLES_EXERCICE) do
        if not egal(depart[cle], maintenant[cle]) then
            tables[cle] = true
        end
    end
    for _, cle in ipairs(LISTES_EXERCICE) do
        if nombre(depart, cle) ~= nombre(maintenant, cle) then
            listes[cle] = true
        end
    end
    if nombre(depart, 'RemoveAreas') ~= nombre(maintenant, 'RemoveAreas') then
        listes.RetouchAreas = true
    end
    return simples, tables, listes, maintenant
end

-- La valeur de départ d'une table de TABLES_EXERCICE, à remettre : sans valeur au départ, une
-- courbe linéaire, une Look vide (profil sans Look) ou aucune couleur ponctuelle.
local function tableDeDepart(depart, cle)
    if depart[cle] ~= nil then
        return pourLightroom(depart[cle])
    end
    if cle:match('^ToneCurvePV2012') then
        return pourLightroom(COURBE_LINEAIRE)
    end
    return {}
end

-- Les valeurs à poser le temps du rendu de la version de Claude (fonction pure, des tables neuves) :
-- sa version, plus, sur chaque réglage que Dany a changé et que Claude ne touche pas, la valeur de
-- départ (profil et Look, courbes, couleurs ponctuelles compris), et une liste vide pour les
-- masques, taches, yeux rouges et traits d'affinage que Dany a ajoutés à une photo qui n'en avait
-- pas. Second résultat, restent (Json.tableau) : les listes changées par Dany qui restent dans les
-- deux images (le départ en avait déjà, ou des taches de l'outil Supprimer, dont Lightroom dérive
-- RetouchAreas).
function Variantes.valeursClaude(ex, actuels)
    local valeurs = pourLightroom(ex.claude or {})
    local depart = ex.depart or {}
    local simples, tables, listes, maintenant = changementsDeDany(ex, actuels)
    for cle, valeur in pairs(simples) do
        if valeurs[cle] == nil then
            valeurs[cle] = valeur
        end
    end
    for cle in pairs(tables) do
        if valeurs[cle] == nil then
            valeurs[cle] = tableDeDepart(depart, cle)
        end
    end
    local restent = Json.tableau()
    for _, cle in ipairs(LISTES_EXERCICE) do
        if listes[cle] and valeurs[cle] == nil then
            local supprimer = cle == 'RetouchAreas'
                and (nombre(depart, 'RemoveAreas') > 0 or nombre(maintenant, 'RemoveAreas') > 0)
            if nombre(depart, cle) == 0 and not supprimer then
                valeurs[cle] = {}
            else
                restent[#restent + 1] = cle
            end
        end
    end
    return valeurs, restent
end

local function nomLook(look)
    return lookVide(look) and "aucune" or tostring(look.Name)
end

local function nul(valeur)
    if valeur == nil then
        return Json.null
    end
    return valeur
end

-- Les écarts de l'exercice (fonction pure) : Json.tableau de {cle, depart, claude, vous}, par clé,
-- sur les réglages que Claude ou Dany ont changés depuis le départ. Look : le nom de la Look. Une
-- autre table (courbe, couleurs ponctuelles, flou d'objectif…) : « inchangée » ou « changée »
-- (vous : « changée » comme Claude, « changée autrement » sinon). Les listes vont à part (listes :
-- masques, taches, yeux_rouges = { depart, vous }, leurs nombres). Troisième résultat : vrai si
-- Dany n'a rien changé.
function Variantes.ecartsExercice(ex, actuels)
    local depart, claude = ex.depart or {}, ex.claude or {}
    local simples, tables, listesChangees, maintenant = changementsDeDany(ex, actuels)
    local cles, vues = {}, {}
    local function ajouter(cle)
        if not vues[cle] and not dansListe(LISTES_EXERCICE, cle) and cle ~= 'RemoveAreas' and cle ~= 'RetouchInfo' then
            vues[cle] = true
            cles[#cles + 1] = cle
        end
    end
    -- Les réglages simples de Claude que l'état de départ suit (etatSimple) : un nom que Lightroom
    -- résout lui-même (profil d'objectif), une empreinte, n'en sont pas.
    for cle, valeur in pairs(claude) do
        if type(valeur) == 'table' or etatSimple({ [cle] = valeur })[cle] ~= nil then
            ajouter(cle)
        end
    end
    for cle in pairs(simples) do ajouter(cle) end
    for cle in pairs(tables) do ajouter(cle) end
    table.sort(cles)
    local ecarts = Json.tableau()
    local rienChange = true
    for _, cle in ipairs(cles) do
        local d, c, v
        if cle == 'Look' then
            d = nomLook(depart.Look)
            c = claude.Look ~= nil and nomLook(claude.Look) or d
            v = nomLook(maintenant.Look)
        elseif type(depart[cle]) == 'table' or type(claude[cle]) == 'table' or dansListe(TABLES_EXERCICE, cle) then
            local dt, ct, vt = depart[cle], claude[cle], actuels[cle]
            if ct == nil then
                ct = dt
            end
            d = "inchangée"
            c = egal(ct, dt) and "inchangée" or "changée"
            if egal(vt, dt) then
                v = "inchangée"
            elseif egal(vt, ct) or c == "inchangée" then
                v = "changée"
            else
                v = "changée autrement"
            end
        else
            d, v = depart[cle], maintenant[cle]
            c = claude[cle]
            if c == nil then
                c = d
            end
        end
        if not egal(v, d) then
            rienChange = false
        end
        if not egal(c, d) or not egal(v, d) then
            ecarts[#ecarts + 1] = { cle = cle, depart = nul(d), claude = nul(c), vous = nul(v) }
        end
    end
    local listes = {}
    for _, l in ipairs(LISTES_MONTREES) do
        listes[l.nom] = { depart = nombre(depart, l.cle), vous = nombre(maintenant, l.cle) }
    end
    if next(listesChangees) then
        rienChange = false
    end
    return ecarts, listes, rienChange
end

-- Les réglages que Dany a changés depuis le départ de l'exercice, en clés de Lightroom (ensemble) :
-- poser « ma version » (son instantané : le départ et la version de Claude) les remet au départ ;
-- undo_last doit les lui rendre.
local function clesDeDany(ex, actuels)
    local simples, tables, listes = changementsDeDany(ex, actuels)
    local cles = {}
    for cle in pairs(simples) do cles[cle] = true end
    for cle in pairs(tables) do cles[cle] = true end
    for cle in pairs(listes) do cles[cle] = true end
    if cles.RetouchAreas and type(actuels.RemoveAreas) == 'table' then
        cles.RemoveAreas = true
    end
    return cles
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
-- la variante ; pour « ma version » d'un exercice, aussi ceux que Dany a changés depuis le départ
-- (l'instantané les remet au départ : undo_last les lui rend). L'entrée du journal, écrite avec la
-- mémoire avant la pose, est réécrite après avec ses changements (export_journal, la leçon).
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
    local cles, vues = {}, {}
    for _, cle in ipairs(info.cles or {}) do
        cles[#cles + 1] = cle
        vues[cle] = true
    end
    local exercice = type(info.exercice) == 'table' and Variantes.exercice(photo, nom) or nil
    if exercice then
        local deDany = {}
        for cle in pairs(clesDeDany(exercice, actuels)) do
            if not vues[cle] then
                deDany[#deDany + 1] = cle
            end
        end
        table.sort(deDany)
        for _, cle in ipairs(deDany) do
            cles[#cles + 1] = cle
        end
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
    -- réécrite avec eux, sinon ni export_journal ni la leçon ne voient les réglages de la variante.
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
