-- Profils.lua : le profil relu après l'écriture. Lightroom remplace un nom qu'il ne trouve pas
-- pour l'appareil une fraction de seconde après coup : le module relit le profil, essaie ses
-- autres orthographes, et le défait s'il ne tient pas (voir docs/SPEC.md, Profil).

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Plans = require 'Plans'
local Reglages = require 'Reglages'

local garder = Photos.garder
local libererProfil, lookVide = Reglages.libererProfil, Reglages.lookVide
local memeProfil, nomProfil = Reglages.memeProfil, Reglages.nomProfil
local pourLightroom = Reglages.pourLightroom
local aDesChangements, noter = Plans.aDesChangements, Plans.noter
local ecrire = Ecriture.ecrire

local Profils = {}

local ATTENTE_PROFIL = 1.5   -- secondes de relecture après la pose d'un profil
local PAS_PROFIL = 0.25

-- Le profil relu est-il celui voulu ? voulu = { CameraProfile?, Look? } : Look vaut le nom de la
-- Look, false pour « sans Look », nil pour ne pas la regarder. Renvoie aussi les réglages relus.
local function profilGarde(photo, voulu)
    local relus = photo:getDevelopSettings()
    if voulu.CameraProfile ~= nil and not memeProfil(relus.CameraProfile, voulu.CameraProfile) then
        return false, relus
    end
    if voulu.Look == false then
        return lookVide(relus.Look), relus
    elseif voulu.Look ~= nil then
        return not lookVide(relus.Look) and relus.Look.Name == voulu.Look, relus
    end
    return true, relus
end

-- Relit le profil des photos suivies ({ photo, voulu }) pendant ATTENTE_PROFIL secondes, une
-- seule attente pour toutes ; chacune reçoit garde et relus. Constaté dans Lightroom Classic
-- 15.6 : juste après l'écriture, la relecture montre le profil posé ; Lightroom le remplace par
-- Adobe Standard moins d'une demi-seconde plus tard s'il ne le trouve pas pour l'appareil.
local function attendreProfils(suivis)
    if #suivis == 0 then
        return
    end
    local debut, restants = LrDate.currentTime(), 0
    repeat
        LrTasks.sleep(PAS_PROFIL)
        restants = 0
        for _, suivi in ipairs(suivis) do
            if suivi.garde ~= false then
                suivi.garde, suivi.relus = profilGarde(suivi.photo, suivi.voulu)
                if suivi.garde then
                    restants = restants + 1
                end
            end
        end
    until restants == 0 or LrDate.currentTime() - debut >= ATTENTE_PROFIL
end

-- Un profil qui n'a pas tenu : les autres orthographes du nom (voulu.variantes, du catalogue du
-- serveur), une à une, chacune une étape de plus dans l'Historique. Renvoie si l'une tient, son
-- nom, les réglages relus et les noms essayés.
local function essayerVariantes(photo, voulu, etape, relus)
    local essayes = {}
    for _, variante in ipairs(voulu.CameraProfile and voulu.variantes or {}) do
        variante = tostring(variante)
        essayes[#essayes + 1] = variante
        ecrire(etape, function()
            photo:applyDevelopSettings(libererProfil({ CameraProfile = variante }), etape)
        end)
        local suivi = { photo = photo, voulu = { CameraProfile = variante, Look = voulu.Look } }
        attendreProfils({ suivi })
        relus = suivi.relus
        Liaison.noter(string.format("Profil « %s » essayé sous « %s » : %s", voulu.CameraProfile, variante,
            suivi.garde and "gardé" or "pas gardé"))
        if suivi.garde then
            return true, relus.CameraProfile, relus, essayes
        end
    end
    return false, nil, relus, essayes
end

-- Le profil voulu après des réglages remis (annulation, retour, fin d'un essai), ou nil.
local function profilRemis(reglages)
    if reglages.CameraProfile == nil and reglages.Look == nil then
        return nil
    end
    local voulu = { CameraProfile = reglages.CameraProfile }
    if type(reglages.Look) == 'table' then
        voulu.Look = false
        if not lookVide(reglages.Look) then
            voulu.Look = tostring(reglages.Look.Name)
        end
    end
    return voulu
end

-- Après des réglages remis ({ photo, reglages } par photo) : remarque, par id de photo, pour
-- chaque profil que Lightroom n'a pas gardé.
local function verifierProfilsRemis(remises)
    local suivis = {}
    for _, remise in ipairs(remises) do
        local voulu = profilRemis(remise.reglages)
        if voulu then
            suivis[#suivis + 1] = { photo = remise.photo, voulu = voulu, reglages = remise.reglages }
        end
    end
    attendreProfils(suivis)
    local remarques = {}
    for _, suivi in ipairs(suivis) do
        if not suivi.garde then
            remarques[suivi.photo.localIdentifier] = string.format(
                "Profil d'avant « %s » non remis : Lightroom ne l'a pas gardé (relu : « %s »).",
                nomProfil(suivi.reglages) or "?", nomProfil(suivi.relus) or "?")
        end
    end
    return remarques
end

-- Noms entre guillemets, séparés par des virgules.
local function citer(noms)
    local liste = {}
    for _, nom in ipairs(noms) do
        liste[#liste + 1] = "« " .. nom .. " »"
    end
    return table.concat(liste, ", ")
end

-- Ce qui est dit d'un profil qui n'a pas tenu.
local function texteProfilRefuse(voulu, relus, essayes)
    local texte = string.format("Profil « %s » non appliqué : Lightroom ne l'a pas gardé (relu : « %s »)",
        voulu.nom, nomProfil(relus) or "?")
    local baseRefusee = voulu.CameraProfile ~= nil and not memeProfil(relus.CameraProfile, voulu.CameraProfile)
    if baseRefusee and voulu.Look ~= false then
        texte = texte .. string.format(" : il ne trouve pas son profil de base « %s » pour cet appareil", voulu.CameraProfile)
    elseif baseRefusee then
        texte = texte .. " : il ne le trouve pas sous ce nom pour cet appareil"
    end
    if #essayes > 0 then
        texte = texte .. ", ni sous " .. citer(essayes)
    end
    return texte
end

-- Le profil d'un plan qui n'a pas tenu : le profil d'avant est remis (une Look comme Adobe Color
-- aussi, que le profil d'appareil retirait), le changement sort de la réponse et du journal, et
-- une remarque dit pourquoi.
local function remettreProfil(plan, etape, texte)
    local photo, avant = plan.photo, nil
    for i = #plan.changements, 1, -1 do
        local changement = plan.changements[i]
        if changement.cle == 'CameraProfile' or changement.cle == 'Look' then
            if changement.cle == 'CameraProfile' and changement.avant ~= Json.null then
                avant = changement.avant
            end
            table.remove(plan.changements, i)
        end
    end
    local remise = {}
    for _, cle in ipairs({ 'CameraProfile', 'Look', 'ConvertToGrayscale', 'AILook' }) do
        if plan.avant[cle] ~= nil then
            remise[cle] = pourLightroom(plan.avant[cle])
        end
    end
    if next(remise) then
        ecrire(etape, function()
            photo:applyDevelopSettings(libererProfil(remise), etape)
        end)
        local probleme = verifierProfilsRemis({ { photo = photo, reglages = remise } })[photo.localIdentifier]
        texte = texte .. ". " .. (probleme or string.format("Profil d'avant remis : « %s ».",
            tostring(nomProfil(remise) or avant or "?")))
    else
        texte = texte .. "."
    end
    noter(plan, texte)
    if plan.entreeJournal then
        plan.entreeJournal.note = texte
        Ecriture.ecrireMemoire(etape, function()
            garder(photo, 'journalClaude', Json.encode(Json.tableau(plan.journal)))
        end)
    end
end

-- Profil adaptatif posé par un paramètre prédéfini du module : Lightroom le range « à mettre à
-- jour » (AILook actif sans AILookData), et ne le calcule qu'au rendu suivant, par la fenêtre
-- « Mises à jour IA recommandées » (réponse de l'utilisateur), ou par « Mettre à jour » dans le
-- module Développement (constaté dans Lightroom Classic 15.6 : rien en 75 s sur la photo
-- affichée). S'il ne l'a pas marqué ainsi, le profil ne serait jamais calculé : il est défait.
local function verifierCalculAdaptatif(plan, voulu, etape)
    local relus = plan.photo:getDevelopSettings()
    local calcul = type(relus.AILook) == 'table' and relus.AILook or {}
    if calcul.Active ~= true then
        remettreProfil(plan, etape, string.format("Profil adaptatif « %s » non appliqué : Lightroom ne l'a pas marqué à calculer", voulu.nom))
    elseif calcul.AILookData == nil then
        noter(plan, string.format("Profil adaptatif « %s » posé : Lightroom le calcule au prochain rendu (view_photo, preview_settings, exportation) "
            .. "ou par « Mettre à jour » dans le module Développement ; d'ici là, son effet n'est que partiel.", voulu.nom))
    end
end

-- Après l'écriture des plans (appliquer, copier) : relit le profil de chaque photo ; un profil
-- qui ne tient pas, même sous une autre orthographe, est défait et dit : jamais un faux succès.
local function verifierProfils(plans, etape)
    local suivis = {}
    for _, plan in ipairs(plans) do
        if plan.profilVoulu and aDesChangements(plan) then
            suivis[#suivis + 1] = { photo = plan.photo, voulu = plan.profilVoulu, plan = plan }
        end
    end
    attendreProfils(suivis)
    for _, suivi in ipairs(suivis) do
        local plan, voulu = suivi.plan, suivi.voulu
        local garde, relus = suivi.garde, suivi.relus
        if not garde then
            local pose, essayes
            garde, pose, relus, essayes = essayerVariantes(plan.photo, voulu, etape, relus)
            if garde then
                noter(plan, string.format("Profil « %s » posé sous le nom que Lightroom lui donne pour cet appareil : « %s ».", voulu.nom, pose))
            else
                remettreProfil(plan, etape, texteProfilRefuse(voulu, relus, essayes))
            end
        end
        if garde and voulu.adaptatif then
            verifierCalculAdaptatif(plan, voulu, etape)
        end
        -- La réponse et le journal donnent le nom que Lightroom a rangé (sa casse, ou une variante).
        if garde and voulu.Look == false and relus.CameraProfile ~= voulu.CameraProfile then
            for _, changement in ipairs(plan.changements) do
                if changement.cle == 'CameraProfile' then
                    changement.apres = relus.CameraProfile
                end
            end
        end
    end
end

Profils.attendreProfils = attendreProfils
Profils.essayerVariantes = essayerVariantes
Profils.texteProfilRefuse = texteProfilRefuse
Profils.verifierProfils = verifierProfils
Profils.verifierProfilsRemis = verifierProfilsRemis

return Profils
