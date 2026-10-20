-- Publication.lua : publier ses photos en fichiers, sans Claude ni quota : profils (JPEG 5 Mpx,
-- JPEG pleine qualité, Web, Instagram, Impression) et ceux de l'utilisateur, un ou plusieurs à la
-- fois (un sous-dossier par profil), modèle de noms de Lightroom, droits d'auteur, lieu, filigrane.
-- L'exportation passe par LrExportSession, le moteur d'exportation de Lightroom, et n'écrase
-- jamais un fichier (LR_collisionHandling = 'rename' : « -2 »). Identifiants des réglages repris
-- de la livraison du module (Livraison.lua), relevés dans Lightroom Classic 15.6.

local LrApplication = import 'LrApplication'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Ecriture = require 'Ecriture'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Texte = require 'Texte'

local Publication = {}

-- Les profils proposés ; ceux de l'utilisateur (publication.json) s'y ajoutent.
Publication.STANDARDS = {
    { id = 'jpeg-5mpx', nom = "JPEG 5 Mpx", format = 'jpeg', qualite = 85, espace = 'srgb', megapixels = 5 },
    { id = 'jpeg-pleine', nom = "JPEG pleine qualité", format = 'jpeg', qualite = 100, espace = 'srgb' },
    { id = 'web', nom = "Web", format = 'jpeg', qualite = 80, espace = 'srgb', grandCote = 2048 },
    { id = 'instagram', nom = "Instagram", format = 'jpeg', qualite = 85, espace = 'srgb', petitCote = 1080,
        remarque = "Recadrer en 4:5 avant : la publication ne recadre pas." },
    { id = 'impression', nom = "Impression", format = 'tiff', espace = 'adobe_rgb', profondeur = 16 },
}

local ESPACES = { srgb = 'sRGB', adobe_rgb = 'AdobeRGB', display_p3 = 'DisplayP3' }
local NOMS_ESPACES = { srgb = 'sRGB', adobe_rgb = 'Adobe RVB', display_p3 = 'Display P3' }
local FORMATS = { jpeg = 'JPEG', tiff = 'TIFF', png = 'PNG' }
-- Filigrane simple des droits d'auteur de la photo (AgExportSettings).
local FILIGRANE_DROITS = '<simpleCopyrightWatermark>'

local function chiffre(x)
    return Texte.nombre(x)
end

-- « JPEG · qualité 85 · sRGB · 5 Mpx ».
function Publication.resume(p)
    local parties = { p.format == 'tiff' and string.format("TIFF %d bits", p.profondeur or 8)
        or (p.format == 'png' and string.format("PNG %d bits", p.profondeur or 8)) or 'JPEG' }
    if p.format == 'jpeg' and p.qualite then
        parties[#parties + 1] = "qualité " .. p.qualite
    end
    parties[#parties + 1] = NOMS_ESPACES[p.espace or 'srgb'] or tostring(p.espace)
    if p.megapixels then
        parties[#parties + 1] = chiffre(p.megapixels) .. " Mpx"
    end
    if p.grandCote then
        parties[#parties + 1] = p.grandCote .. " px"
    end
    if p.petitCote then
        parties[#parties + 1] = "4:5, " .. p.petitCote .. " px"
    end
    if not p.grandCote and not p.petitCote and not p.megapixels then
        parties[#parties + 1] = "pleine taille"
    end
    if p.poidsMaxKo then
        parties[#parties + 1] = chiffre(p.poidsMaxKo / 1000) .. " Mo au plus"
    end
    if p.filigrane then
        parties[#parties + 1] = "filigrane"
    end
    return table.concat(parties, " · ")
end

-- Poids estimé d'une photo publiée, en octets, pour une photo de `mpxSource` mégapixels (JPEG
-- environ 0,25 octet par pixel à la qualité 80, 0,55 à 100).
function Publication.poidsEstime(p, mpxSource)
    local mpx = mpxSource or 26
    if p.megapixels then
        mpx = math.min(mpx, p.megapixels)
    end
    if p.grandCote then
        mpx = math.min(mpx, p.grandCote * p.grandCote * 2 / 3 / 1000000)
    end
    if p.petitCote then
        mpx = math.min(mpx, p.petitCote * p.petitCote * 5 / 4 / 1000000)
    end
    local octetsParPixel
    if p.format == 'tiff' or p.format == 'png' then
        octetsParPixel = (p.profondeur or 8) / 8 * 3 * (p.format == 'png' and 0.6 or 1)
    else
        local q = p.qualite or 80
        octetsParPixel = 0.25 + math.max(0, q - 80) / 20 * 0.30
    end
    local octets = mpx * 1000000 * octetsParPixel
    if p.poidsMaxKo then
        octets = math.min(octets, p.poidsMaxKo * 1000 * 0.95)
    end
    return math.floor(octets)
end

-- « 850 Ko », « 1,6 Mo », « 1,2 Go ».
function Publication.texteOctets(o)
    local function v(x)
        return x >= 100 and string.format('%d', math.floor(x + 0.5)) or chiffre(math.floor(x * 10 + 0.5) / 10)
    end
    if o >= 1e9 then
        return v(o / 1e9) .. " Go"
    elseif o >= 1e6 then
        return v(o / 1e6) .. " Mo"
    end
    return string.format('%d Ko', math.max(1, math.floor(o / 1e3 + 0.5)))
end

-- Profils de l'utilisateur (publication.json) --------------------------------------------------

function Publication.fichierProfils()
    return LrPathUtils.child(Chemins.racine(), 'publication.json')
end

function Publication.profilsPerso()
    local texte = Fichiers.lire(Publication.fichierProfils())
    local ok, liste = pcall(function() return texte and Json.decode(texte) end)
    local profils = {}
    for _, p in ipairs(ok and type(liste) == 'table' and liste or {}) do
        if type(p) == 'table' and type(p.id) == 'string' and type(p.nom) == 'string' then
            local copie = {}
            for k, v in pairs(p) do
                copie[k] = v
            end
            copie.perso = true
            profils[#profils + 1] = copie
        end
    end
    return profils
end

function Publication.profils()
    local liste = {}
    for _, p in ipairs(Publication.STANDARDS) do
        liste[#liste + 1] = p
    end
    for _, p in ipairs(Publication.profilsPerso()) do
        liste[#liste + 1] = p
    end
    return liste
end

local function enregistrerPerso(profils)
    local liste = Json.tableau()
    for _, p in ipairs(profils) do
        local copie = {}
        for k, v in pairs(p) do
            if k ~= 'perso' then
                copie[k] = v
            end
        end
        liste[#liste + 1] = copie
    end
    Fichiers.ecrire(Publication.fichierProfils(), Json.encode(liste))
end

function Publication.ajouterProfil(p)
    local profils = Publication.profilsPerso()
    p.id = p.id or ('perso-' .. os.time() .. '-' .. math.random(1000, 9999))
    profils[#profils + 1] = p
    enregistrerPerso(profils)
    return p
end

function Publication.supprimerProfil(id)
    local gardes = {}
    for _, p in ipairs(Publication.profilsPerso()) do
        if p.id ~= id then
            gardes[#gardes + 1] = p
        end
    end
    enregistrerPerso(gardes)
end

-- Modèles de noms de Lightroom ---------------------------------------------------------------

-- Un jeton d'exportation : son nom entre doubles accolades (écrites ainsi pour que le vérificateur
-- du standard ne les prenne pas pour un gabarit à remplir).
function Publication.jeton(nom)
    return string.rep('{', 2) .. nom .. string.rep('}', 2)
end

-- Les jetons d'un fichier .lrtemplate (« deflated = { { { value = "date_YYYYMMDD" }, "-", … »)
-- rendus en jetons d'exportation (« date_YYYYMMDD » et « image_name » entre doubles accolades,
-- séparés par « - ») ; nil si illisible.
function Publication.jetons(texte)
    local debut = texte:find('deflated', 1, true)
    if not debut then
        return nil
    end
    local fin = texte:find('name%s*=', debut)
    if not fin then
        return nil
    end
    local morceau = texte:sub(debut + 8, fin - 1)
    local resultat = {}
    local i = 1
    while i <= #morceau do
        local d1, f1, jeton = morceau:find('^{%s*value%s*=%s*"([^"]*)"%s*,?%s*}', i)
        if d1 then
            resultat[#resultat + 1] = Publication.jeton(jeton)
            i = f1 + 1
        else
            local d2, f2, litteral = morceau:find('^"([^"]*)"%s*,', i)
            if d2 then
                resultat[#resultat + 1] = litteral
                i = f2 + 1
            else
                i = i + 1
            end
        end
    end
    local texteJetons = table.concat(resultat)
    return texteJetons ~= '' and texteJetons or nil
end

-- Les modèles de noms de l'utilisateur (Bibliothèque › Modifier les noms de fichiers), par nom :
-- { nom, jetons, texte (demande un texte personnalisé), sequence }. Ceux de la prise de vue
-- (capture en mode connecté) n'en sont pas.
function Publication.modelesNoms(dossier)
    dossier = dossier or LrPathUtils.child(Chemins.home(), 'Library/Application Support/Adobe/Lightroom/Filename Templates')
    local modeles = {}
    for _, nom in ipairs(Fichiers.entrees(dossier)) do
        if nom:match('%.lrtemplate$') then
            local jetons = Publication.jetons(Fichiers.lire(LrPathUtils.child(dossier, nom)) or '')
            if jetons and not jetons:find('shoot_custom_token', 1, true) then
                modeles[#modeles + 1] = { nom = nom:gsub('%.lrtemplate$', ''), jetons = jetons,
                    texte = jetons:find(Publication.jeton('custom_token'), 1, true) ~= nil,
                    sequence = jetons:find('naming_sequence', 1, true) ~= nil }
            end
        end
    end
    table.sort(modeles, function(a, b) return a.nom < b.nom end)
    return modeles
end

-- Réglages d'exportation ---------------------------------------------------------------------

-- Les réglages de LrExportSession pour un profil (table neuve, sans métatable). options :
-- jetons, textePerso, droitsSeulement, retirerLieu, filigrane (true, false ou nil = celui du profil).
function Publication.reglages(p, dossier, sousDossier, options)
    options = options or {}
    local format = FORMATS[p.format or 'jpeg'] or 'JPEG'
    local r = {
        LR_export_destinationType = 'specificFolder',
        LR_export_destinationPathPrefix = dossier,
        LR_export_useSubfolder = false,
        LR_collisionHandling = 'rename',
        LR_format = format,
        LR_export_colorSpace = ESPACES[p.espace or 'srgb'] or 'sRGB',
        LR_export_bitDepth = format == 'JPEG' and 8 or ((p.profondeur == 16) and 16 or 8),
        LR_jpeg_quality = math.max(0, math.min(100, p.qualite or 80)) / 100,
        LR_jpeg_useLimitSize = false,
        LR_tiff_compressionMethod = 'compressionMethod_ZIP',
        LR_size_doConstrain = false,
        LR_size_doNotEnlarge = true,
        LR_size_units = 'pixels',
        LR_size_resolution = 300,
        LR_size_resolutionUnits = 'inch',
        LR_outputSharpeningOn = false,
        LR_embeddedMetadataOption = options.droitsSeulement and 'copyrightOnly' or 'all',
        LR_removeLocationMetadata = options.retirerLieu ~= false,
        LR_removeFaceMetadata = true,
        LR_metadata_keywordOptions = 'flat',
        LR_renamingTokensOn = false,
        LR_extensionCase = 'lowercase',
        LR_useWatermark = false,
        LR_reimportExportedPhoto = false,
        LR_includeVideoFiles = false,
        LR_export_postProcessing = 'doNothing',
    }
    if format == 'JPEG' and p.poidsMaxKo then
        r.LR_jpeg_useLimitSize = true
        r.LR_jpeg_limitSize = math.floor(p.poidsMaxKo)
    end
    if p.megapixels then
        r.LR_size_doConstrain = true
        r.LR_size_resizeType = 'megapixels'
        r.LR_size_megapixels = p.megapixels
    elseif p.grandCote or p.petitCote then
        r.LR_size_doConstrain = true
        r.LR_size_resizeType = p.grandCote and 'longEdge' or 'shortEdge'
        r.LR_size_maxWidth = math.floor(p.grandCote or p.petitCote)
        r.LR_size_maxHeight = math.floor(p.grandCote or p.petitCote)
    end
    local filigrane = options.filigrane
    if filigrane == nil then
        filigrane = p.filigrane ~= nil
    end
    if filigrane then
        r.LR_useWatermark = true
        r.LR_watermarking_id = FILIGRANE_DROITS
    end
    if sousDossier and sousDossier ~= '' then
        r.LR_export_useSubfolder = true
        r.LR_export_destinationPathSuffix = sousDossier
    end
    if options.jetons and options.jetons ~= '' then
        r.LR_renamingTokensOn = true
        r.LR_tokens = options.jetons
        r.LR_tokenCustomString = options.textePerso or ''
        r.LR_initialSequenceNumber = 1
    end
    return r
end

-- Photos ---------------------------------------------------------------------------------------

-- Les photos visées : 'active', 'selection' ou 'collection' (identifiant de la collection).
function Publication.photos(portee, idCollection)
    local catalogue = LrApplication.activeCatalog()
    if portee == 'active' then
        local p = catalogue:getTargetPhoto()
        return p and { p } or {}
    elseif portee == 'collection' then
        local c = idCollection and catalogue:getCollectionByLocalIdentifier(idCollection)
        return c and c:getPhotos() or {}
    end
    if not catalogue:getTargetPhoto() then
        return {}
    end
    return catalogue:getTargetPhotos()
end

-- Les collections du catalogue (ensembles compris), pour un menu : { title = "Ensemble › Nom", value = id }.
function Publication.collections()
    local items = {}
    local function parcourir(parent, chemin)
        for _, c in ipairs(parent:getChildCollections() or {}) do
            if not c:isSmartCollection() then
                items[#items + 1] = { title = chemin .. c:getName(), value = c.localIdentifier }
            end
        end
        for _, ensemble in ipairs(parent:getChildCollectionSets() or {}) do
            parcourir(ensemble, chemin .. ensemble:getName() .. " › ")
        end
    end
    LrTasks.pcall(parcourir, LrApplication.activeCatalog(), '')
    table.sort(items, function(a, b) return a.title < b.title end)
    return items
end

-- Mégapixels d'une photo (recadrée), 26 si inconnu.
function Publication.megapixels(photo)
    local ok, d = LrTasks.pcall(photo.getRawMetadata, photo, 'croppedDimensions')
    if ok and type(d) == 'table' and tonumber(d.width) and tonumber(d.height) then
        return d.width * d.height / 1000000
    end
    return 26
end

-- Les noms que Lightroom donnera (photo:getNameViaPreset, sans l'extension), pour les 20
-- premières photos : { { origine, nom } }.
function Publication.noms(photos, modele, textePerso)
    local ok, presets = LrTasks.pcall(LrApplication.filenamePresets)
    local id
    for nom, identifiant in pairs(ok and type(presets) == 'table' and presets or {}) do
        if tostring(nom):lower() == tostring(modele.nom):lower() then
            id = identifiant
        end
    end
    if not id then
        return nil, "Lightroom ne connaît pas le modèle « " .. tostring(modele.nom) .. " »."
    end
    local noms = {}
    for i, photo in ipairs(photos) do
        if i > 20 then
            break
        end
        local okNom, nom = LrTasks.pcall(photo.getNameViaPreset, photo, id, textePerso or '', i)
        noms[#noms + 1] = { origine = photo:getFormattedMetadata('fileName') or '?', nom = okNom and nom or ("(" .. tostring(nom) .. ")") }
    end
    return noms
end

-- Exportation ----------------------------------------------------------------------------------

-- Le dossier de publication : un chemin complet, créé au besoin (pas sur un disque absent).
function Publication.preparerDossier(chemin)
    chemin = Texte.nettoyer(chemin)
    if chemin:sub(1, 1) == '~' then
        chemin = Chemins.home() .. chemin:sub(2)
    end
    if chemin:sub(1, 1) ~= '/' then
        return nil, "Le dossier de publication doit être un chemin complet (/Users/…, /Volumes/…)."
    end
    local nature = LrFileUtils.exists(chemin)
    if nature == 'file' then
        return nil, "« " .. chemin .. " » est un fichier, pas un dossier."
    end
    if not nature then
        local parent = LrPathUtils.parent(chemin)
        if not parent or not LrFileUtils.exists(parent) then
            return nil, "Le dossier parent de « " .. chemin .. " » n'existe pas (disque débranché ?)."
        end
        LrFileUtils.createAllDirectories(chemin)
    end
    return chemin
end

-- Un aperçu de Claude fait passer isExported à vrai (constaté en 2.4) : la liaison note alors la
-- photo `apercuSeulement` (Rendu.lua), pour que la recherche des photos jamais exportées la trouve
-- encore. Publiée pour de bon, elle ne l'est plus : le champ s'efface, en écriture privée (hors
-- de Édition › Annuler), comme après une livraison de Claude (Livraison.exporter).
local function oublierApercus(publiees)
    local aEffacer = {}
    for _, photo in ipairs(publiees) do
        if photo:getPropertyForPlugin(_PLUGIN, 'apercuSeulement') == 'oui' then
            aEffacer[#aEffacer + 1] = photo
        end
    end
    if #aEffacer > 0 then
        Ecriture.ecrireMemoire("Claude · publication", function()
            for _, photo in ipairs(aEffacer) do
                photo:setPropertyForPlugin(_PLUGIN, 'apercuSeulement', nil)
            end
        end)
    end
end

-- Publie les photos dans chaque profil (un sous-dossier par profil s'il y en a plusieurs). Rend le
-- bilan : { { profil, fichiers, erreurs, dossier } }. Lightroom montre la progression de chaque
-- exportation dans sa barre d'activité (en haut à gauche), où elle s'annule. À appeler depuis une
-- tâche.
function Publication.publier(profils, photos, dossier, options)
    local bilan = {}
    local plusieurs = #profils > 1
    -- Les photos rendues au moins une fois (une seule fois chacune, quel que soit le nombre de profils).
    local publiees, dejaVues = {}, {}
    -- Réglages IA calculés avant le rendu (masques, profils adaptatifs) : sans la fenêtre « Mises
    -- à jour IA recommandées » (photo:updateAISettings, SDK 13.3, hors écriture).
    for _, photo in ipairs(photos) do
        if photo.updateAISettings then
            LrTasks.pcall(photo.updateAISettings, photo)
        end
    end
    for _, p in ipairs(profils) do
        local sous = plusieurs and p.nom or nil
        local reglages = Publication.reglages(p, dossier, sous, options)
        local ligne = { profil = p.nom, fichiers = 0, erreurs = {}, dossier = sous and LrPathUtils.child(dossier, sous) or dossier }
        local export = LrExportSession { photosToExport = photos, exportSettings = reglages }
        local ok, erreur = LrTasks.pcall(function()
            for _, rendu in export:renditions { stopIfCanceled = true } do
                local fait, cheminOuMessage = rendu:waitForRender()
                if fait then
                    ligne.fichiers = ligne.fichiers + 1
                    if rendu.photo and not dejaVues[rendu.photo] then
                        dejaVues[rendu.photo] = true
                        publiees[#publiees + 1] = rendu.photo
                    end
                else
                    ligne.erreurs[#ligne.erreurs + 1] = tostring(cheminOuMessage or "raison inconnue")
                end
            end
        end)
        if not ok then
            ligne.erreurs[#ligne.erreurs + 1] = tostring(erreur)
        end
        Journal.noter(string.format("Publication %s : %d fichier(s) dans %s", p.nom, ligne.fichiers, ligne.dossier))
        bilan[#bilan + 1] = ligne
    end
    -- Les fichiers sont faits : un échec ici ne change pas le bilan.
    local ok, erreur = LrTasks.pcall(oublierApercus, publiees)
    if not ok then
        Journal.noter("Publication : champ « aperçu seulement » non effacé (" .. tostring(erreur) .. ")")
    end
    return bilan
end

return Publication
