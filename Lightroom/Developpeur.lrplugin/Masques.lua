-- Masques.lua : reprendre un masque de la photo sans défaire toute l'étape qui l'a posé (commande
-- « masques ») : le lister, le masquer ou l'afficher, le retirer, le dupliquer (inversé au besoin),
-- le faire recalculer par Lightroom, affiner son contour ; et retirer les masques vides.
--
-- Les masques d'une photo sont la liste MaskGroupBasedCorrections, une « Correction » par masque
-- (Locaux.lua). Masquer = CorrectionActive faux (l'œil du panneau Masques) ; retirer = la liste sans
-- lui ; dupliquer = une copie, avec d'autres identifiants. Ces changements gardent les empreintes
-- des masques IA (MaskDigest…) : ils passent par applyDevelopSettings, comme l'annulation, sans
-- nouveau calcul. Recalculer un masque IA (« Tout mettre à jour » d'Adobe) : ses empreintes retirées
-- (Locaux.sansCalculsIA), il passe par un paramètre prédéfini du module avec toute la liste
-- (Plans.masquesParPreset), puis updateAISettings le calcule.
--
-- Masques vides : relevé dans le code de Lightroom Classic 15.6 (LrCatalog) :
-- catalog:deleteAllEmptyMasks(photos) (SDK 14.0) lance la commande ag.develop.deleteEmptyMasks pour
-- ces photos (sans elles : la sélection). Un masque IA qui n'a rien trouvé (« Personnes » sur un
-- paysage) est vide. Le module relit la liste ensuite : l'étape garde la liste d'avant.

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local catalogue, decrire, photoVisee = Photos.catalogue, Photos.decrire, Photos.photoVisee
local minuscules, pluriel, pourLightroom = Reglages.minuscules, Reglages.pluriel, Reglages.pourLightroom
local resume = Reglages.resume
local noter, nouveauPlan = Plans.noter, Plans.nouveauPlan
local calculerIA, ecrirePlans, modeTexte = Ecriture.calculerIA, Ecriture.ecrirePlans, Ecriture.modeTexte
local nomEtape, noterEtatFinal, resultatsPlans = Ecriture.nomEtape, Ecriture.noterEtatFinal, Ecriture.resultatsPlans
local verifierAccord, verifierPause = Ecriture.verifierAccord, Ecriture.verifierPause
local verifierProtection = Ecriture.verifierProtection

local Masques = {}

local function echouer(message)
    error(message, 0)
end

local function sansPrefixe(texte)
    local reste = tostring(texte or '')
    while true do
        local suite = reste:match('^%s*[Cc][Ll][Aa][Uu][Dd][Ee]%s*·%s*(.*)$')
        if not suite then
            return reste
        end
        reste = suite
    end
end

-- Description d'un composant pour Claude : ce qu'il est, son mode, s'il est calculé.
local SOUS_TYPES = { [1] = "sujet", [2] = "ciel", [3] = "partie d'une personne" }

local function decrireComposant(m)
    local d = { nom = m.MaskName or Json.null, type = tostring(m.What or '?'):gsub('^Mask/', '') }
    if m.What == 'Mask/Image' then
        d.ia = SOUS_TYPES[tonumber(m.MaskSubType)] or (Locaux.numeroPersonne(m) and "personne") or "IA"
        d.calcule = m.MaskDigest ~= nil
        if (tonumber(m.ErrorReason) or 0) ~= 0 and m.MaskDigest == nil then
            d.echec = true
        end
        d.personne = Locaux.numeroPersonne(m)
        d.contour_progressif = tonumber(m.Feather)
        d.contour = tonumber(m.EdgeShift)
    end
    if tonumber(m.MaskBlendMode) == 1 then
        d.mode = m.MaskInverted == true and "intersection" or "soustrait"
    elseif m.MaskInverted == true then
        d.mode = "inversé"
    end
    return d
end

local function lister(liste)
    local masques = Json.tableau()
    for i, correction in ipairs(liste) do
        local composants = Json.tableau()
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            composants[#composants + 1] = decrireComposant(m)
        end
        masques[#masques + 1] = {
            numero = i,
            nom = correction.CorrectionName or Json.null,
            actif = correction.CorrectionActive ~= false,
            intensite = tonumber(correction.CorrectionAmount) or 1,
            composants = composants,
        }
    end
    return masques
end

-- Le masque désigné par son numéro (à partir de 1) ou son nom, préfixe « Claude · » ou non.
local function trouver(liste, designation)
    local numero = tonumber(designation)
    if numero then
        if not liste[numero] then
            echouer(string.format("Pas de masque n° %d : la photo en a %d.", numero, #liste))
        end
        return numero
    end
    local voulu = minuscules(sansPrefixe(designation))
    local trouves = {}
    for i, correction in ipairs(liste) do
        if minuscules(sansPrefixe(correction.CorrectionName)) == voulu then
            trouves[#trouves + 1] = i
        end
    end
    if #trouves == 0 then
        local noms = {}
        for i, correction in ipairs(liste) do
            noms[#noms + 1] = string.format("%d « %s »", i, tostring(correction.CorrectionName or "sans nom"))
        end
        echouer("Aucun masque « " .. tostring(designation) .. " » sur cette photo"
            .. (#noms > 0 and (" (masques : " .. table.concat(noms, ", ") .. ")") or " (elle n'a pas de masque)") .. ".")
    end
    if #trouves > 1 then
        echouer("Plusieurs masques s'appellent « " .. tostring(designation) .. " » : le désigner par son numéro (masques n° "
            .. table.concat(trouves, ", ") .. ").")
    end
    return trouves[1]
end

-- Nouveaux identifiants pour une copie (Lightroom les veut uniques sur la photo).
local function renouveler(correction)
    correction.CorrectionID = Locaux.uuid()
    correction.CorrectionSyncID = Locaux.syncId()
    local function masques(liste)
        for _, m in ipairs(liste or {}) do
            if type(m) == 'table' then
                m.MaskID = Locaux.uuid()
                m.MaskSyncID = Locaux.syncId()
                masques(m.Masks)
            end
        end
    end
    masques(correction.CorrectionMasks)
end

-- Retire les masques vides de la photo d'un plan (catalog:deleteAllEmptyMasks), et note ceux que
-- Lightroom a retirés. Renvoie la liste d'avant si des masques sont partis, sinon nil. Hors d'une
-- écriture : c'est une commande de Lightroom (supposé, comme updateAISettings).
local DUREE_MASQUES_VIDES = 3

function Masques.retirerVides(plan)
    local cat = catalogue()
    local ok, fonction = pcall(function() return cat.deleteAllEmptyMasks end)
    if not ok or type(fonction) ~= 'function' then
        return nil
    end
    local avant = plan.photo:getDevelopSettings().MaskGroupBasedCorrections
    avant = type(avant) == 'table' and avant or {}
    if #avant == 0 then
        return nil
    end
    local fait, erreur = LrTasks.pcall(fonction, cat, { plan.photo })
    if not fait then
        Liaison.noter("Masques vides non retirés : " .. tostring(erreur))
        return nil
    end
    local apres
    local debut = LrDate.currentTime()
    repeat
        apres = plan.photo:getDevelopSettings().MaskGroupBasedCorrections
        apres = type(apres) == 'table' and apres or {}
        if #apres ~= #avant then
            break
        end
        LrTasks.sleep(0.25)
    until LrDate.currentTime() - debut > DUREE_MASQUES_VIDES
    if #apres >= #avant then
        return nil
    end
    local restants = {}
    for _, correction in ipairs(apres) do
        restants[tostring(correction.CorrectionID)] = true
    end
    local partis = {}
    for _, correction in ipairs(avant) do
        if not restants[tostring(correction.CorrectionID)] then
            partis[#partis + 1] = "« " .. tostring(correction.CorrectionName or "sans nom") .. " »"
        end
    end
    noter(plan, string.format("Lightroom n'a rien trouvé pour %s : %s, retiré%s (masques vides).", pluriel(#partis, "masque", "masques"),
        table.concat(partis, ", "), #partis > 1 and "s" or ""))
    return pourLightroom(avant)
end

local ACTIONS = { masquer = true, afficher = true, retirer = true, dupliquer = true, recalculer = true, affiner = true, retirer_vides = true }

function Masques.masques(params)
    local photo = photoVisee(params)
    local actuels = photo:getDevelopSettings()
    local existants = type(actuels.MaskGroupBasedCorrections) == 'table' and actuels.MaskGroupBasedCorrections or {}
    local action = tostring(params.action or 'lister')
    if action == 'lister' then
        return { photo = decrire(photo, false), masques = lister(existants) }
    end
    if not ACTIONS[action] then
        echouer("Action inconnue : " .. action .. " (lister, masquer, afficher, retirer, dupliquer, recalculer, affiner, retirer_vides).")
    end
    verifierPause(params)
    local prefs = Preferences.lire()
    verifierAccord(prefs, params, 'edit_mask')
    verifierProtection({ photo }, prefs, params, 'edit_mask')
    local etape = nomEtape(params, "masques")
    local plan = nouveauPlan(photo)

    if action == 'retirer_vides' then
        local avant = Masques.retirerVides(plan)
        if avant then
            plan.avant.MaskGroupBasedCorrections = avant
            plan.horsEcriture = true
            plan.changements[#plan.changements + 1] = { cle = 'MaskGroupBasedCorrections', avant = resume('MaskGroupBasedCorrections', avant),
                apres = resume('MaskGroupBasedCorrections', photo:getDevelopSettings().MaskGroupBasedCorrections) }
            ecrirePlans({ plan }, etape, prefs, params)
            noterEtatFinal({ photo }, etape)
        else
            noter(plan, "Aucun masque vide sur cette photo.")
        end
        return { mode = modeTexte(prefs), resultats = resultatsPlans({ plan }, etape, params) }
    end

    local liste = pourLightroom(existants)
    local i = trouver(liste, params.masque)
    local nom = tostring(liste[i].CorrectionName or ("masque " .. i))
    local apres
    if action == 'masquer' or action == 'afficher' then
        local actif = action == 'afficher'
        if (liste[i].CorrectionActive ~= false) == actif then
            noter(plan, string.format("Le masque « %s » est déjà %s.", nom, actif and "affiché" or "masqué"))
        else
            liste[i].CorrectionActive = actif
        end
        apres = string.format("« %s » %s", nom, actif and "affiché" or "masqué")
    elseif action == 'retirer' then
        table.remove(liste, i)
        apres = string.format("%s (« %s » retiré)", pluriel(#liste, "masque", "masques"), nom)
    elseif action == 'dupliquer' then
        local copie = pourLightroom(liste[i])
        renouveler(copie)
        local nouveau = sansPrefixe(params.nom)
        copie.CorrectionName = "Claude · " .. (nouveau ~= '' and nouveau or (sansPrefixe(nom) .. " (copie)"))
        if params.inverser and type(copie.CorrectionMasks) == 'table' and copie.CorrectionMasks[1] then
            copie.CorrectionMasks[1].MaskInverted = copie.CorrectionMasks[1].MaskInverted ~= true
        end
        table.insert(liste, i + 1, copie)
        apres = string.format("%s (+ « %s »%s)", pluriel(#liste, "masque", "masques"), copie.CorrectionName, params.inverser and ", inversé" or "")
    elseif action == 'affiner' then
        local touches = 0
        for _, m in ipairs(liste[i].CorrectionMasks or {}) do
            if Locaux.affiner(m, params.contour, params.decalage) then
                touches = touches + 1
            end
        end
        if touches == 0 then
            echouer("Le masque « " .. nom .. " » n'a pas de composant IA : seuls les masques IA (sujet, ciel, personnes, objets…) ont un contour à affiner.")
        end
        apres = string.format("« %s » : contour affiné", nom)
    elseif action == 'recalculer' then
        if not Locaux.aDesMasquesIA({ liste[i] }) then
            echouer("Le masque « " .. nom .. " » n'a pas de composant IA : rien à recalculer.")
        end
        Locaux.sansCalculsIA({ liste[i] })
        apres = string.format("« %s » recalculé par Lightroom", nom)
    end

    if not Reglages.egal(liste, pourLightroom(existants)) or action == 'recalculer' then
        plan.avant.MaskGroupBasedCorrections = pourLightroom(existants)
        if action == 'recalculer' then
            Plans.masquesParPreset(plan, Plans.presetMasques("Claude · masques recalculés", liste))
        else
            plan.nouveaux.MaskGroupBasedCorrections = liste
        end
        plan.changements[#plan.changements + 1] = { cle = 'MaskGroupBasedCorrections', avant = resume('MaskGroupBasedCorrections', existants), apres = apres }
        ecrirePlans({ plan }, etape, prefs, params)
        calculerIA({ plan })
        if action == 'recalculer' then
            local relus = plan.photo:getDevelopSettings().MaskGroupBasedCorrections
            for _, echec in ipairs(Locaux.masquesIAEnEchec(relus)) do
                noter(plan, string.format("Lightroom n'a pas su calculer le masque « %s ».", echec))
            end
            for _, perdu in ipairs(Locaux.personnesPerdues(existants, relus)) do
                noter(plan, string.format("Masque « %s » : Lightroom n'a plus reconnu la personne ; undo_last le remet comme avant.", perdu))
            end
        end
        noterEtatFinal({ photo }, etape)
    end
    local reponse = { mode = modeTexte(prefs), resultats = resultatsPlans({ plan }, etape, params) }
    reponse.masques = lister(type(photo:getDevelopSettings().MaskGroupBasedCorrections) == 'table' and photo:getDevelopSettings().MaskGroupBasedCorrections or {})
    return reponse
end

return Masques
