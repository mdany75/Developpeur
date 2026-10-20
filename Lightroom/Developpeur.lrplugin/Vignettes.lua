-- Vignettes.lua : vignettes tirées du cache d'aperçus de Lightroom (commande vignettes), pour
-- trier une séance ou montrer une planche contact sans exporter chaque photo.
--
-- photo:requestJpegThumbnail(largeur, hauteur, rappel) (SDK 5.0, dans une tâche) rend un aperçu
-- que Lightroom a déjà, ou qu'il rend s'il lui manque à cette taille ; la taille demandée est un
-- minimum, l'aperçu rendu peut être plus grand. Le rappel reçoit le JPEG (un texte), ou nil et la
-- raison. La requête doit rester référencée jusqu'au rappel. Le module les demande toutes à la
-- fois, attend les rappels, puis écrit chaque JPEG dans un dossier temporaire propre à la
-- commande (le serveur lit puis efface, comme pour un aperçu).

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Reglages = require 'Reglages'

local brut, decrire, photoParId = Photos.brut, Photos.decrire, Photos.photoParId
local dimensionsAffichees, orientationAffichage = Photos.dimensionsAffichees, Photos.orientationAffichage
local estRaw = Reglages.estRaw

local Vignettes = {}

local function echouer(message)
    error(message, 0)
end

Vignettes.MAX_PAR_COMMANDE = 50
-- Secondes pour toutes les vignettes d'une commande : un aperçu manquant se rend (une seconde ou
-- deux par photo, supposé).
Vignettes.DELAI = 60
local TAILLE_MIN, TAILLE_MAX = 128, 2048
local CLES_CADRE = { 'CropLeft', 'CropTop', 'CropRight', 'CropBottom', 'CropAngle' }

-- Le cadre de la photo, s'il n'est pas le fichier entier (pour situer le point de mise au point
-- dans la vignette, qui montre la photo recadrée).
local function cadre(reglages)
    local valeurs, recadree = {}, false
    for _, cle in ipairs(CLES_CADRE) do
        local valeur = tonumber(reglages[cle])
        if valeur then
            valeurs[cle] = valeur
            local neutre = (cle == 'CropRight' or cle == 'CropBottom') and 1 or 0
            recadree = recadree or math.abs(valeur - neutre) > 1e-6
        end
    end
    return recadree and valeurs or nil
end

-- Ce que le serveur doit savoir de la photo, en plus de la vignette : sa description, le chemin du
-- fichier (point de mise au point lu par le serveur), et de quoi passer du repère du fichier à la
-- vignette (dimensions affichées, orientation, cadre).
local function decrireVignette(photo, d)
    d = d or decrire(photo, true)
    local reglages = photo:getDevelopSettings()
    local largeur, hauteur = dimensionsAffichees(photo)
    local raw = estRaw(photo, reglages)
    d.chemin_original = brut(photo, 'path')
    -- Le serveur ne lit le point AF que dans les fichiers Fujifilm (PointAF).
    d.marque = Photos.meta(photo, 'cameraMake')
    d.geometrie = {
        largeur = largeur, hauteur = hauteur,
        orientation = (orientationAffichage(photo, raw, largeur, hauteur)),
        cadre = cadre(reglages),
    }
    return d
end

function Vignettes.vignettes(params)
    local ids = type(params.photos) == 'table' and params.photos or {}
    if #ids == 0 then
        echouer("Aucune photo : donner photos.")
    end
    if #ids > Vignettes.MAX_PAR_COMMANDE then
        echouer(string.format("Au plus %d photos par commande vignettes.", Vignettes.MAX_PAR_COMMANDE))
    end
    local taille = math.floor(math.min(math.max(tonumber(params.taille) or 1024, TAILLE_MIN), TAILLE_MAX))
    local racine = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'Developpeur')
    local dossier = LrPathUtils.child(racine, string.format('vignettes-%d', math.floor(LrDate.currentTime() * 1000) % 1000000000))
    LrFileUtils.createAllDirectories(dossier)

    local demandes = {}
    for _, id in ipairs(ids) do
        local demande = { id = tonumber(id) }
        local ok, photo = LrTasks.pcall(photoParId, id)
        if not ok then
            demande.fini, demande.erreur = true, Liaison.messageErreur(photo)
        else
            demande.photo = photo
            local lance, requete = LrTasks.pcall(photo.requestJpegThumbnail, photo, taille, taille, function(jpeg, raison)
                if not demande.fini then
                    demande.jpeg, demande.raison, demande.fini = jpeg, raison, true
                end
            end)
            if lance then
                -- Gardée jusqu'au rappel : sinon la requête peut être abandonnée.
                demande.requete = requete
            else
                demande.fini, demande.erreur = true, Liaison.messageErreur(requete)
            end
        end
        demandes[#demandes + 1] = demande
    end

    local debut = LrDate.currentTime()
    local function restantes()
        local n = 0
        for _, demande in ipairs(demandes) do
            if not demande.fini then
                n = n + 1
            end
        end
        return n
    end
    while restantes() > 0 and LrDate.currentTime() - debut < Vignettes.DELAI do
        LrTasks.sleep(0.05)
    end

    -- Les descriptions d'abord, par lectures groupées (Photos.decrireTout).
    local trouvees = {}
    for _, demande in ipairs(demandes) do
        if demande.photo then
            trouvees[#trouvees + 1] = demande.photo
        end
    end
    local okD, descriptions = LrTasks.pcall(Photos.decrireTout, trouvees)
    local parPhoto = {}
    for i, photo in ipairs(trouvees) do
        parPhoto[photo] = okD and descriptions[i] or nil
    end
    local liste = Json.tableau()
    for _, demande in ipairs(demandes) do
        local item = { id = demande.id }
        if demande.photo then
            local ok, description = LrTasks.pcall(decrireVignette, demande.photo, parPhoto[demande.photo])
            if ok then
                item = description
            end
        end
        if type(demande.jpeg) == 'string' and #demande.jpeg > 0 then
            local chemin = LrPathUtils.child(dossier, string.format('%d.jpg', demande.id))
            local fichier = io.open(chemin, 'wb')
            if fichier then
                fichier:write(demande.jpeg)
                fichier:close()
                item.vignette = chemin
            else
                item.erreur = "Vignette impossible à écrire dans " .. dossier
            end
        elseif demande.erreur then
            item.erreur = demande.erreur
        elseif demande.fini then
            item.erreur = "Lightroom n'a pas rendu de vignette" .. (demande.raison and (" : " .. tostring(demande.raison)) or "")
        else
            item.erreur = string.format("Pas de vignette après %d s", Vignettes.DELAI)
        end
        demande.requete = nil
        liste[#liste + 1] = item
    end
    return { taille = taille, dossier = dossier, photos = liste }
end

return Vignettes
