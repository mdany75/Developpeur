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

-- Ce que le serveur doit savoir de la photo, en plus de la vignette ou de l'aperçu (Rendu.apercu) :
-- sa description, le chemin du fichier (point de mise au point lu par le serveur), et de quoi
-- passer du repère du fichier à l'image affichée (dimensions affichées, orientation, cadre).
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
Vignettes.decrireVignette = decrireVignette

-- Demande la vignette de chaque photo (photo de Lightroom, ou identifiant), toutes à la fois, puis
-- attend les rappels (Vignettes.DELAI au plus). Une photo introuvable ou une requête refusée finit
-- aussitôt, avec son erreur, sans bloquer les autres.
local function demanderTout(liste, taille)
    local demandes = {}
    for _, element in ipairs(liste) do
        local demande = { id = type(element) == 'table' and element.localIdentifier or tonumber(element) }
        local ok, photo
        if type(element) == 'table' then
            ok, photo = true, element
        else
            ok, photo = LrTasks.pcall(photoParId, element)
        end
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
    return demandes
end

-- Écrit le JPEG d'une demande dans le dossier (<id>.jpg) : rend son chemin, ou nil et la raison.
local function ecrireJpeg(demande, dossier)
    local chemin, erreur
    if type(demande.jpeg) == 'string' and #demande.jpeg > 0 then
        chemin = LrPathUtils.child(dossier, string.format('%d.jpg', demande.id))
        local fichier = io.open(chemin, 'wb')
        if fichier then
            fichier:write(demande.jpeg)
            fichier:close()
        else
            chemin, erreur = nil, "Vignette impossible à écrire dans " .. dossier
        end
    elseif demande.erreur then
        erreur = demande.erreur
    elseif demande.fini then
        erreur = "Lightroom n'a pas rendu de vignette" .. (demande.raison and (" : " .. tostring(demande.raison)) or "")
    else
        erreur = string.format("Pas de vignette après %d s", Vignettes.DELAI)
    end
    demande.requete = nil
    return chemin, erreur
end

local function tailleDemandee(taille)
    return math.floor(math.min(math.max(tonumber(taille) or 1024, TAILLE_MIN), TAILLE_MAX))
end

-- Dossier temporaire propre à une demande (le serveur lit puis efface).
local function dossierTemporaire()
    local racine = LrPathUtils.child(LrPathUtils.getStandardFilePath('temp'), 'Developpeur')
    return LrPathUtils.child(racine, string.format('vignettes-%d', math.floor(LrDate.currentTime() * 1000) % 1000000000))
end

-- Vignettes de ces photos (photos de Lightroom, ou identifiants) écrites dans `dossier` (créé au
-- besoin ; sans dossier, un dossier temporaire), pour l'aperçu de la photo active de la fenêtre
-- Claude. Rend deux tables par identifiant : { [id] = chemin du JPEG }, et les erreurs
-- { [id] = raison }. À appeler dans une tâche (les rappels s'attendent par LrTasks.sleep). Le JPEG
-- peut être plus grand que la taille demandée (un minimum) : le réduire avant de l'afficher dans un
-- cadre fixe.
function Vignettes.demander(photos, taille, dossier)
    dossier = dossier or dossierTemporaire()
    LrFileUtils.createAllDirectories(dossier)
    local chemins, erreurs = {}, {}
    for _, demande in ipairs(demanderTout(type(photos) == 'table' and photos or {}, tailleDemandee(taille))) do
        local chemin, erreur = ecrireJpeg(demande, dossier)
        if demande.id then
            chemins[demande.id], erreurs[demande.id] = chemin, erreur
        end
    end
    return chemins, erreurs
end

function Vignettes.vignettes(params)
    local ids = type(params.photos) == 'table' and params.photos or {}
    if #ids == 0 then
        echouer("Aucune photo : donner photos.")
    end
    if #ids > Vignettes.MAX_PAR_COMMANDE then
        echouer(string.format("Au plus %d photos par commande vignettes.", Vignettes.MAX_PAR_COMMANDE))
    end
    local taille = tailleDemandee(params.taille)
    local dossier = dossierTemporaire()
    LrFileUtils.createAllDirectories(dossier)

    local demandes = demanderTout(ids, taille)

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
        local chemin, erreur = ecrireJpeg(demande, dossier)
        item.vignette, item.erreur = chemin, erreur
        liste[#liste + 1] = item
    end
    return { taille = taille, dossier = dossier, photos = liste }
end

return Vignettes
