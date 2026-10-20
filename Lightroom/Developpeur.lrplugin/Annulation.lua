-- Annulation.lua : défaire la dernière retouche de Claude (annuler) ou toutes (revenir),
-- d'après la mémoire de la photo : réglages, traitements calculés (clés Amelioration et
-- Suppression) et classement dans la Bibliothèque (clé Bibliotheque), chacun par son chemin.

local LrTasks = import 'LrTasks'

local Amelioration = require 'Amelioration'
local Bibliotheque = require 'Bibliotheque'
local Conversions = require 'Conversions'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Profils = require 'Profils'
local Reglages = require 'Reglages'
local Suppression = require 'Suppression'

local decrire, garder, lireJson = Photos.decrire, Photos.garder, Photos.lireJson
local photosVisees = Photos.photosVisees
local aRemettre, libererProfil = Reglages.aRemettre, Reglages.libererProfil
local cumulerRotation, pourLightroom, resumer = Reglages.cumulerRotation, Reglages.pourLightroom, Reglages.resumer
local ajouterJournal, ecrire = Ecriture.ajouterJournal, Ecriture.ecrire
local correctionsUtilisateur, noterEtatFinal = Ecriture.correctionsUtilisateur, Ecriture.noterEtatFinal
local verifierPause = Ecriture.verifierPause
local verifierProfilsRemis = Profils.verifierProfilsRemis

local Annulation = {}

-- Traitements calculés par Lightroom, gardés dans la mémoire sous leur clé (pas des réglages) : ils
-- se remettent par LrDevelopController, photo affichée dans le module Développement ; la rotation,
-- par la commande de rotation de Lightroom (Conversions.lua).
local CALCULES = {
    { cle = 'Amelioration', remettre = Amelioration.remettre },
    { cle = 'Suppression', remettre = Suppression.remettre },
    { cle = 'Rotation', remettre = Conversions.remettreRotation },
}

-- Ce que l'utilisateur a changé à la main depuis la dernière commande de Claude, que l'annulation
-- d'une étape va remettre (les réglages de l'étape) ou laisser (les autres). nil : rien changé.
local function avertirCorrections(photo, reglages)
    local corrections = correctionsUtilisateur(photo)
    if not corrections then
        return nil
    end
    local remises, gardees = {}, {}
    for _, changement in ipairs(corrections.changements) do
        if reglages[changement.cle] ~= nil then
            remises[#remises + 1] = changement.cle
        else
            gardees[#gardees + 1] = changement.cle
        end
    end
    local parties = {}
    if #remises > 0 then
        parties[#parties + 1] = "l'annulation remet aussi " .. table.concat(remises, ", ") .. ", que l'utilisateur avait "
            .. (#remises > 1 and "changés" or "changé") .. " à la main depuis"
    end
    if #gardees > 0 then
        parties[#parties + 1] = (#remises > 0 and "ses autres corrections à la main restent (" or "ses corrections à la main restent (")
            .. table.concat(gardees, ", ") .. ")"
    end
    return "Depuis cette étape, " .. table.concat(parties, " ; ") .. "."
end

-- Remet d'abord, photo par photo, ce qui passe par LrDevelopController (traitements calculés),
-- puis laisse les réglages à applyDevelopSettings. Une photo dont Lightroom ne remet pas un
-- traitement reste telle quelle, avec la raison : sa mémoire est gardée, pour réessayer.
local function remettreCalcules(plans, resultats, cleResultat)
    local suite = {}
    for _, plan in ipairs(plans) do
        plan.remis = plan.reglages
        local reglages, aRemettreCalcules = {}, {}
        for cle, valeur in pairs(plan.reglages) do
            local calcule
            for _, c in ipairs(CALCULES) do
                if c.cle == cle then
                    calcule = c
                end
            end
            if calcule then
                aRemettreCalcules[#aRemettreCalcules + 1] = { remettre = calcule.remettre, voulue = valeur }
            else
                reglages[cle] = valeur
            end
        end
        plan.reglages = reglages
        local ok, erreur = true, nil
        for _, calcule in ipairs(aRemettreCalcules) do
            if ok then
                ok, erreur = LrTasks.pcall(calcule.remettre, plan.photo, calcule.voulue)
            end
        end
        if ok then
            suite[#suite + 1] = plan
        else
            resultats[#resultats + 1] = { photo = decrire(plan.photo, false), [cleResultat] = false, raison = Liaison.messageErreur(erreur) }
        end
    end
    return suite
end

local function nomsDesCles(reglages)
    local liste = {}
    for cle in pairs(reglages) do
        liste[#liste + 1] = cle
    end
    table.sort(liste)
    return table.concat(liste, ", ")
end

-- Le classement dans la Bibliothèque se remet à part (Bibliotheque.remettre) : jamais par
-- applyDevelopSettings. plan.remis garde tout, pour la réponse.
local function separerBibliotheque(plans)
    for _, plan in ipairs(plans) do
        plan.bibliotheque = plan.reglages.Bibliotheque
        plan.notes = {}
        if plan.bibliotheque ~= nil then
            local reglages = {}
            for cle, valeur in pairs(plan.reglages) do
                if cle ~= 'Bibliotheque' then
                    reglages[cle] = valeur
                end
            end
            plan.reglages = reglages
        end
    end
    return plans
end

-- Profil d'objectif par défaut à remettre : applyDevelopSettings laisse LensProfileSetup à 'Custom'
-- (constaté) ; le paramètre prédéfini du module le pose, puis la balance personnalisée qu'il fait
-- tomber revient (comme Ecriture.appliquerPlan). À préparer hors de l'écriture.
local CLES_BALANCE = { 'WhiteBalance', 'Temperature', 'Tint', 'IncrementalTemperature', 'IncrementalTint' }

local function preparerObjectif(plans)
    for _, plan in ipairs(plans) do
        if plan.reglages.LensProfileSetup == 'LensDefaults' then
            local actuels = plan.photo:getDevelopSettings()
            local enable = plan.reglages.LensProfileEnable
            if enable == nil then
                enable = actuels.LensProfileEnable
            end
            plan.objectifParDefaut = Plans.presetObjectifParDefaut(tonumber(enable) ~= 0)
            local balance = {}
            for _, cle in ipairs(CLES_BALANCE) do
                local valeur = plan.reglages[cle]
                if valeur == nil then
                    valeur = actuels[cle]
                end
                balance[cle] = valeur
            end
            plan.balanceObjectif = balance.WhiteBalance == 'Custom' and balance or nil
        end
    end
    return plans
end

local function remettreObjectif(plan, etape)
    if plan.objectifParDefaut then
        plan.photo:applyDevelopPreset(plan.objectifParDefaut, _PLUGIN)
        if plan.balanceObjectif then
            plan.photo:applyDevelopSettings(plan.balanceObjectif, etape)
        end
    end
end

-- Remarque d'une photo : profil non remis, collection introuvable…
local function remarque(plan, remarques)
    local parties = { remarques[plan.photo.localIdentifier] }
    for _, note in ipairs(plan.notes) do
        parties[#parties + 1] = note
    end
    return #parties > 0 and table.concat(parties, " ") or nil
end

function Annulation.annuler(params)
    verifierPause(params)
    local resultats = Json.tableau()
    local plans = {}
    for _, photo in ipairs(photosVisees(params)) do
        local etapes = lireJson(photo, 'etapesClaude', {})
        local derniere = table.remove(etapes)
        if derniere then
            local reglages = aRemettre(pourLightroom(derniere.avant or {}))
            plans[#plans + 1] = { photo = photo, etapes = etapes, nom = tostring(derniere.nom or "retouche"),
                reglages = reglages, journal = lireJson(photo, 'journalClaude', {}),
                original = lireJson(photo, 'avantClaude', {}), corrections = avertirCorrections(photo, reglages) }
        else
            resultats[#resultats + 1] = { photo = decrire(photo, false), annulee = false, sans_retouche = true,
                raison = "Aucune retouche de Claude à annuler sur cette photo." }
        end
    end

    plans = preparerObjectif(separerBibliotheque(remettreCalcules(plans, resultats, 'annulee')))
    if #plans > 0 then
        ecrire("Claude · annulation", function()
            for _, plan in ipairs(plans) do
                if next(plan.reglages) then
                    plan.photo:applyDevelopSettings(libererProfil(plan.reglages), "Claude · annulation de « " .. plan.nom .. " »")
                end
                remettreObjectif(plan, "Claude · annulation de « " .. plan.nom .. " »")
                Bibliotheque.remettre(plan.photo, plan.bibliotheque, plan.notes)
                local cumulChange = Bibliotheque.annulerCumul(plan.original, plan.bibliotheque)
                -- Une rotation annulée sort du cumul des rotations de l'état d'avant Claude.
                if type(plan.remis.Rotation) == 'table' then
                    plan.original.Rotation = cumulerRotation(plan.original.Rotation, plan.remis.Rotation.quarts, true)
                    cumulChange = true
                end
                if cumulChange then
                    garder(plan.photo, 'avantClaude', Json.encode(plan.original))
                end
                ajouterJournal(plan.journal, { etape = "Annulation de « " .. plan.nom .. " »", type = 'annulation',
                    changements = Json.tableau(), note = "Réglages remis : " .. nomsDesCles(plan.remis) })
                garder(plan.photo, 'etapesClaude', Json.encode(Json.tableau(plan.etapes)))
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
            end
        end)
        local remarques = verifierProfilsRemis(plans)
        local photos = {}
        for _, plan in ipairs(plans) do
            local description = decrire(plan.photo, false)
            if plan.corrections then
                plan.notes[#plan.notes + 1] = plan.corrections
            end
            resultats[#resultats + 1] = { photo = description, annulee = true, etape = plan.nom,
                reglages_remis = resumer(plan.remis), remarque = remarque(plan, remarques) }
            Liaison.noter("Annulé : " .. plan.nom .. " sur " .. description.fichier)
            photos[#photos + 1] = plan.photo
        end
        noterEtatFinal(photos, "annulation")
    end
    return { resultats = resultats }
end

function Annulation.revenir(params)
    verifierPause(params)
    local resultats = Json.tableau()
    local plans = {}
    for _, photo in ipairs(photosVisees(params)) do
        local original = aRemettre(pourLightroom(lireJson(photo, 'avantClaude', {})))
        if next(original) then
            plans[#plans + 1] = { photo = photo, reglages = original, journal = lireJson(photo, 'journalClaude', {}) }
        else
            resultats[#resultats + 1] = { photo = decrire(photo, false), remise = false, sans_retouche = true,
                raison = "Aucune retouche de Claude sur cette photo." }
        end
    end

    plans = preparerObjectif(separerBibliotheque(remettreCalcules(plans, resultats, 'remise')))
    if #plans > 0 then
        ecrire("Claude · retour à l'état d'avant Claude", function()
            for _, plan in ipairs(plans) do
                if next(plan.reglages) then
                    plan.photo:applyDevelopSettings(libererProfil(plan.reglages), "Claude · retour à l'état d'avant Claude")
                end
                remettreObjectif(plan, "Claude · retour à l'état d'avant Claude")
                Bibliotheque.remettre(plan.photo, plan.bibliotheque, plan.notes)
                ajouterJournal(plan.journal, { etape = "Retour à l'état d'avant Claude", type = 'retour',
                    changements = Json.tableau(), note = "Réglages remis : " .. nomsDesCles(plan.remis) })
                garder(plan.photo, 'avantClaude', nil)
                garder(plan.photo, 'etapesClaude', nil)
                garder(plan.photo, 'retoucheeParClaude', nil)
                garder(plan.photo, 'apresClaude', nil)
                garder(plan.photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
            end
        end)
        local remarques = verifierProfilsRemis(plans)
        for _, plan in ipairs(plans) do
            local description = decrire(plan.photo, false)
            resultats[#resultats + 1] = { photo = description, remise = true, reglages_remis = resumer(plan.remis),
                remarque = remarque(plan, remarques) }
            Liaison.noter("Remise à l'état d'avant Claude : " .. description.fichier)
        end
    end
    return { resultats = resultats }
end

return Annulation
