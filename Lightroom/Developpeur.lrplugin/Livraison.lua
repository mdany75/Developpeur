-- Livraison.lua : les fichiers que l'utilisateur livre (commande exporter), la fenêtre
-- d'exportation de Lightroom en dernier recours (fenetreExport), ce qu'il faut pour choisir
-- (options : modèles de noms de fichiers, paramètres prédéfinis de métadonnées, services de
-- publication et réglages des services Disque dur), et ce qui l'entoure : le dossier choisi dans
-- une fenêtre (choisirDossier), les noms que Lightroom calculera (nomsFichiers) et les aperçus
-- dynamiques (apercusDynamiques). Depuis la retouche générative (Fibo 2, 29 octobre 2026) : la
-- photo que le connecteur a fait faire par Fibo 2, importée dans le catalogue et empilée au-dessus
-- de son original (importerGeneree).
--
-- L'exportation passe par la même LrExportSession que les aperçus, mais vers le dossier choisi par
-- l'utilisateur, et sans jamais écraser un fichier : LR_collisionHandling = 'rename' (Lightroom
-- ajoute « -2 » au nom). Elle ne change rien au catalogue. Le serveur découpe une longue série en
-- lots (progression, annulation entre deux lots) ; `suite` marque les lots qui suivent le premier,
-- dont l'accord est déjà donné. Identifiants des réglages relevés dans le code de Lightroom
-- Classic 15.6 (AgExportSettings, ExportMetadataSection, ExportSessionQueries,
-- ExportFileSettingsSection, ExportLocationSection, AgWatermarkingData).

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrExportSession = import 'LrExportSession'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Bibliotheque = require 'Bibliotheque'
local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Ecriture = require 'Ecriture'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'
local Preferences = require 'Preferences'
local Services = require 'Services'
local Texte = require 'Texte'

local brut, decrire, nomFichier = Photos.brut, Photos.decrire, Photos.nomFichier
local photosVisees = Photos.photosVisees
local accordDansLightroom, calculerAvantRendu = Ecriture.accordDansLightroom, Ecriture.calculerAvantRendu
local verifierProtection = Ecriture.verifierProtection
local modeTexte, verifierPause = Ecriture.modeTexte, Ecriture.verifierPause

local Livraison = {}

local function echouer(message)
    error(message, 0)
end

local FORMATS = { JPEG = true, TIFF = true, PNG = true, DNG = true, ORIGINAL = true, JXL = true, AVIF = true, PSD = true }
local ESPACES = { sRGB = true, AdobeRGB = true, DisplayP3 = true, ProPhotoRGB = true, Rec2020 = true }
-- Sortie HDR (case « Sortie HDR », enableHDRDisplay) : HDR Rec. 709, HDR P3, HDR Rec. 2020, ce
-- dernier pas en JPEG (relevé dans AgExportSettings : chooseAcceptableColorSpaces).
local ESPACES_HDR = { sRGB_hdr = true, p3_hdr = true, Rec2020_hdr = true }
local METADONNEES = { all = true, copyrightOnly = true, copyrightAndContactOnly = true,
    allExceptCameraRawInfo = true, allExceptCameraInfo = true }
local TAILLES = { longEdge = true, shortEdge = true, megapixels = true }
local SUPPORTS = { screen = true, matte = true, glossy = true }
-- Qualité de 0 à 1, comme jpeg_quality (avif_quality vaut 0,7 par défaut dans AgExportSettings).
local CLES_QUALITE = { JPEG = 'LR_jpeg_quality', JXL = 'LR_jxl_quality', AVIF = 'LR_avif_quality' }
-- Grand côté d'un aperçu dynamique (référence du SDK : smartPreviewInfo ; aide d'Adobe).
local COTE_APERCU_DYNAMIQUE = 2560

-- Profondeur que Lightroom garde pour ce format (AgExportSettings, relevé dans Lightroom Classic
-- 15.6) : JPEG 8 bits, AVIF 10 bits ; en HDR, PNG et JPEG XL 16 bits, TIFF et PSD 16 ou 32 bits ;
-- 32 bits seulement en HDR.
local function profondeurExport(format, hdr, voulue)
    if format == 'JPEG' then
        return 8
    elseif format == 'AVIF' then
        return 10
    elseif hdr then
        return ((format == 'TIFF' or format == 'PSD') and voulue == 32) and 32 or 16
    end
    return voulue == 16 and 16 or 8
end

-- « Compatibilité maximale » d'une sortie HDR (image SDR et carte de gain) : toujours en JPEG,
-- jamais en PNG ni PSD, au choix en AVIF, JPEG XL et TIFF (ExportFileSettingsSection ; vrai par
-- défaut dans AgExportSettings).
local function compatibiliteMaximale(format, voulue)
    if format == 'JPEG' then
        return true
    elseif format == 'PNG' or format == 'PSD' then
        return false
    end
    return voulue ~= false
end

-- Mode « Proposer d'abord » : rien ne part sans l'accord de l'utilisateur (confirm = true, et la
-- fenêtre de la liaison si « Confirmer dans Lightroom » est actif). Une fois pour toute la série.
local function verifierAccordLivraison(prefs, params, outil, quoi)
    if params.suite then
        return
    end
    if prefs.mode == 'proposer' and not params.confirme then
        echouer("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été " .. quoi .. ". Dire à l'utilisateur ce qui serait fait "
            .. "(photos, dossier, format, taille, noms), attendre son accord, puis rappeler " .. outil .. " avec confirm = true.")
    end
    accordDansLightroom(prefs, params, outil)
end

-- Réglages de l'exportation, d'après ce que le serveur a vérifié. Réimportée et empilée, une
-- livraison va dans le dossier de l'original (« Même dossier que la photo originale ») :
-- Lightroom n'offre l'empilement que là (ExportLocationSection : canStackWithOriginal).
local function reglagesExport(params, dossier)
    local r = type(params.reglages) == 'table' and params.reglages or {}
    local format = FORMATS[r.format] and r.format or 'JPEG'
    local hdr = r.hdr == true and format ~= 'DNG' and format ~= 'ORIGINAL'
    local espace = (hdr and ESPACES_HDR[r.espace] or (not hdr and ESPACES[r.espace])) and r.espace or (hdr and 'p3_hdr' or 'sRGB')
    if hdr and format == 'JPEG' and espace == 'Rec2020_hdr' then
        espace = 'p3_hdr'
    end
    local empiler = r.reimporter == 'pile'
    local reglages = {
        LR_export_destinationType = empiler and 'sourceFolder' or 'specificFolder',
        LR_export_destinationPathPrefix = dossier,
        LR_export_useSubfolder = false,
        LR_collisionHandling = 'rename',
        LR_format = format,
        LR_export_colorSpace = espace,
        LR_export_bitDepth = profondeurExport(format, hdr, tonumber(r.profondeur)),
        LR_enableHDRDisplay = hdr,
        LR_maximumCompatibility = hdr and compatibiliteMaximale(format, r.compatibilite) or false,
        LR_jpeg_quality = 0.8,
        LR_jpeg_useLimitSize = false,
        LR_jxl_losslessQuality = format == 'JXL' and r.sans_perte == true,
        LR_tiff_compressionMethod = 'compressionMethod_ZIP',
        LR_size_doConstrain = false,
        LR_size_doNotEnlarge = true,
        LR_size_units = 'pixels',
        LR_size_resolution = tonumber(r.resolution) or 300,
        LR_size_resolutionUnits = 'inch',
        LR_outputSharpeningOn = false,
        LR_embeddedMetadataOption = METADONNEES[r.metadonnees] and r.metadonnees or 'all',
        LR_removeLocationMetadata = r.sans_lieu ~= false,
        LR_removeFaceMetadata = true,
        LR_metadata_keywordOptions = 'flat',
        LR_renamingTokensOn = false,
        LR_extensionCase = 'lowercase',
        LR_useWatermark = false,
        LR_reimportExportedPhoto = r.reimporter == 'catalogue' or empiler,
        LR_reimport_stackWithOriginal = empiler,
        LR_reimport_stackWithOriginal_position = r.position_pile == 'above' and 'above' or 'below',
        LR_includeVideoFiles = false,
        LR_export_postProcessing = 'doNothing',
        LR_DNG_compatibility = 268435456,
        LR_DNG_previewSize = 'medium',
        LR_DNG_embedCache = true,
    }
    local qualite = math.max(0, math.min(100, tonumber(r.qualite) or 80)) / 100
    if CLES_QUALITE[format] then
        reglages[CLES_QUALITE[format]] = qualite
    end
    -- Poids maximal (« Limiter la taille du fichier à », en Ko) : JPEG seulement.
    if format == 'JPEG' and tonumber(r.poids_max_ko) and tonumber(r.poids_max_ko) > 0 then
        reglages.LR_jpeg_useLimitSize = true
        reglages.LR_jpeg_limitSize = math.floor(tonumber(r.poids_max_ko))
    end
    -- Filigrane : celui des droits d'auteur (« <simpleCopyrightWatermark> », donné par le serveur),
    -- ou un filigrane de l'utilisateur par son identifiant (fichier de Watermarks) ; ni l'original
    -- ni le DNG n'en portent (AgExportSettings).
    if type(r.filigrane) == 'string' and r.filigrane ~= '' and format ~= 'DNG' and format ~= 'ORIGINAL' then
        reglages.LR_useWatermark = true
        reglages.LR_watermarking_id = r.filigrane
    end
    if not empiler and type(params.sous_dossier) == 'string' and params.sous_dossier ~= '' then
        reglages.LR_export_useSubfolder = true
        reglages.LR_export_destinationPathSuffix = params.sous_dossier
    end
    local taille = type(r.taille) == 'table' and r.taille or nil
    if taille and TAILLES[taille.type] and tonumber(taille.valeur) then
        reglages.LR_size_doConstrain = true
        reglages.LR_size_resizeType = taille.type
        if taille.type == 'megapixels' then
            reglages.LR_size_megapixels = tonumber(taille.valeur)
        else
            reglages.LR_size_maxWidth = math.floor(tonumber(taille.valeur))
            reglages.LR_size_maxHeight = math.floor(tonumber(taille.valeur))
        end
    end
    local nettete = type(r.nettete) == 'table' and r.nettete or nil
    if nettete and SUPPORTS[nettete.support] then
        reglages.LR_outputSharpeningOn = true
        reglages.LR_outputSharpeningMedia = nettete.support
        reglages.LR_outputSharpeningLevel = math.max(1, math.min(3, math.floor(tonumber(nettete.niveau) or 2)))
    end
    if type(params.jetons) == 'string' and params.jetons ~= '' then
        reglages.LR_renamingTokensOn = true
        reglages.LR_tokens = params.jetons
        reglages.LR_tokenCustomString = type(params.texte_perso) == 'string' and params.texte_perso or ''
        reglages.LR_initialSequenceNumber = math.max(1, math.floor(tonumber(params.sequence) or 1))
    end
    return reglages, format, hdr
end

-- Une photo dont l'original manque se livre depuis son aperçu dynamique si la taille demandée y
-- tient (2560 px de grand côté au plus) ; sinon, la raison du refus.
local function depuisApercu(photo, r)
    if not Photos.apercuDynamique(photo) then
        return false, "Pas livrée."
    end
    local taille = type(r.taille) == 'table' and r.taille or nil
    local format = r.format
    if format ~= 'ORIGINAL' and format ~= 'DNG' and taille and tonumber(taille.valeur) then
        local largeur, hauteur = Photos.dimensionsAffichees(photo)
        local rapport = (largeur and hauteur and math.min(largeur, hauteur) > 0) and math.max(largeur, hauteur) / math.min(largeur, hauteur) or 1.5
        local valeur, grandCote = tonumber(taille.valeur), nil
        if taille.type == 'longEdge' then
            grandCote = valeur
        elseif taille.type == 'shortEdge' then
            grandCote = valeur * rapport
        elseif taille.type == 'megapixels' then
            grandCote = math.sqrt(valeur * 1000000 * rapport)
        end
        if grandCote and grandCote <= COTE_APERCU_DYNAMIQUE + 0.5 then
            return true
        end
    end
    return false, string.format("Pas livrée : son aperçu dynamique ne donne que %d px de grand côté ; demander %d px au plus "
        .. "(long_edge), ou rebrancher le disque des originaux.", COTE_APERCU_DYNAMIQUE, COTE_APERCU_DYNAMIQUE)
end

-- Mode HDR de la photo (HDREditMode, relu comme le nombre 1 : constaté le 17 octobre 2026).
local function enModeHdr(photo)
    local ok, reglages = LrTasks.pcall(photo.getDevelopSettings, photo)
    local mode = ok and type(reglages) == 'table' and reglages.HDREditMode
    return mode == true or tonumber(mode) == 1
end

-- Fichiers que le module a réimportés pendant cette session de Lightroom (chemin → heure) : seuls
-- ceux-là peuvent être retirés du catalogue par retirerReimportees (recette).
local reimporteesSession = {}
local DUREE_RETRAIT = 30 * 60

-- Les fichiers réimportés : Lightroom les ajoute au catalogue après le rendu (AgExportRendition :
-- post), un peu plus tard. Renvoie l'identifiant de chacun, trouvé par son chemin.
local function photosReimportees(entrees)
    local cat = Photos.catalogue()
    local fin = LrDate.currentTime() + 10
    repeat
        local manquantes = 0
        for _, entree in ipairs(entrees) do
            if entree.chemin and not entree.reimportee then
                local ok, photo = LrTasks.pcall(cat.findPhotoByPath, cat, entree.chemin)
                if ok and photo then
                    entree.reimportee = photo.localIdentifier
                    reimporteesSession[entree.chemin] = LrDate.currentTime()
                else
                    manquantes = manquantes + 1
                end
            end
        end
        if manquantes == 0 then
            return
        end
        LrTasks.sleep(0.5)
    until LrDate.currentTime() > fin
end

-- Retouche générative (Fibo 2) : le dossier de passage des fichiers, <racine>/Temporaire/Fibo, que
-- le connecteur emploie pour l'exportation, l'entrée et la sortie de Fibo 2 (un dossier neuf par
-- appel), et que Menage.temporaires vide au chargement.
function Livraison.dossierFibo()
    return LrPathUtils.child(Chemins.temporaire(), 'Fibo')
end

-- Vrai pour un chemin complet sous le dossier de Fibo, sans « . » ni « .. » qui en sortirait.
local function dansFibo(chemin)
    if type(chemin) ~= 'string' or chemin:sub(1, 1) ~= '/' then
        return false
    end
    local prefixe = Livraison.dossierFibo() .. '/'
    if chemin:sub(1, #prefixe) ~= prefixe or #chemin == #prefixe then
        return false
    end
    for morceau in (chemin:sub(#prefixe + 1) .. '/'):gmatch('([^/]*)/') do
        if morceau == '' or morceau == '.' or morceau == '..' then
            return false
        end
    end
    return true
end
Livraison.dansFibo = dansFibo

-- L'étape que la fenêtre de la liaison montre pour une retouche générative.
local ETAPE_FIBO = "Claude · Fibo 2"

-- L'exportation de passage d'une retouche générative (vers Temporaire/Fibo) : l'accord se demande au
-- nom de generative_edit, jamais d'export_photos (Claude rappellerait export_photos, une vraie
-- livraison, et l'accord y partirait), avec l'étape et la raison que le connecteur envoie (la
-- consigne de Fibo 2), pour que la fenêtre de la liaison dise ce qu'elle fait approuver. Les
-- garde-fous des photos (copies virtuelles seulement, libellé protégé, rejetées) s'appliquent
-- avant tout calcul : la retouche générative est une écriture.
local function verifierFibo(prefs, params, photos)
    if prefs.mode == 'proposer' and not params.confirme then
        echouer("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été fait. Dire à l'utilisateur ce que Fibo 2 "
            .. "changerait, attendre son accord, puis rappeler generative_edit avec confirm = true.")
    end
    verifierProtection(photos, prefs, params, 'generative_edit')
    local demande = {}
    for cle, valeur in pairs(params) do
        demande[cle] = valeur
    end
    demande.etape = type(params.etape) == 'string' and params.etape ~= '' and params.etape or ETAPE_FIBO
    accordDansLightroom(prefs, demande, 'generative_edit')
end

-- Photos exportées vers le dossier de Fibo dans cette session (localIdentifier → heure) : l'accord
-- donné à cette exportation (mode « Proposer d'abord », accord dans Lightroom) vaut pour
-- l'importation de la même retouche générative, qui suit dans le même appel de generative_edit,
-- après les calculs : jusqu'à 4 modifications, chacune Fibo 2 puis SeedVR2, 15 min au plus chacun
-- (2 h en tout), d'où DUREE_GENEREE de 3 h. L'accord ne vaut qu'une fois. Les essais le vident.
Livraison.exportsFibo = {}
local DUREE_GENEREE = 3 * 3600

-- Le dossier de livraison : un chemin complet, créé au besoin (celui d'une retouche générative avec
-- ses parents : Temporaire/Fibo est vidé au chargement du module).
local function dossierDeLivraison(chemin)
    if type(chemin) ~= 'string' or chemin:sub(1, 1) ~= '/' then
        echouer("« folder » : le chemin complet du dossier de livraison (/Users/…, /Volumes/…).")
    end
    local nature = LrFileUtils.exists(chemin)
    if nature == 'file' then
        echouer("« " .. chemin .. " » est un fichier, pas un dossier.")
    end
    if not nature and dansFibo(chemin) then
        LrFileUtils.createAllDirectories(chemin)
    elseif not nature then
        local parent = LrPathUtils.parent(chemin)
        if not parent or not LrFileUtils.exists(parent) then
            echouer("Le dossier parent de « " .. chemin .. " » n'existe pas (disque débranché ?) : rien n'a été exporté.")
        end
        LrFileUtils.createAllDirectories(chemin)
    end
    return chemin
end

-- Exporte les photos (un lot) : un fichier par photo, ou la raison de l'échec.
function Livraison.exporter(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    -- Exportation de passage d'une retouche générative (generative_edit) : son propre accord.
    local pourFibo = dansFibo(params.dossier)
    if not pourFibo then
        verifierAccordLivraison(prefs, params, 'export_photos', "exporté")
    end
    -- Les vidéos (1.3.5) : sautées et comptées ; une livraison de photos ne les prend pas.
    local visees, videos = {}, 0
    for _, photo in ipairs(photosVisees(params)) do
        if Photos.brut(photo, 'fileFormat') == 'VIDEO' then
            videos = videos + 1
        else
            visees[#visees + 1] = photo
        end
    end
    if pourFibo then
        verifierFibo(prefs, params, visees)
    end
    if #visees == 0 then
        echouer(videos > 0 and string.format("Aucune photo à exporter : %d vidéo(s), qu'une livraison de photos ne prend pas.", videos)
            or "Aucune photo à exporter.")
    end
    local r = type(params.reglages) == 'table' and params.reglages or {}
    local hdrVoulu = r.hdr == true and r.format ~= 'DNG' and r.format ~= 'ORIGINAL'
    -- Une photo dont l'original manque n'est livrée que depuis son aperçu dynamique, à une taille
    -- qui y tient ; une sortie HDR ne vaut que pour une photo en mode HDR : sinon, sa raison va dans
    -- son entrée.
    local photos, refusees, apercus = {}, {}, {}
    for _, photo in ipairs(visees) do
        local apercuOk, raison = true, nil
        if Photos.originalAbsent(photo) then
            apercuOk, raison = depuisApercu(photo, r)
            if apercuOk then
                apercus[photo] = true
            else
                raison = Photos.raisonOriginalAbsent(photo, raison)
            end
        end
        if apercuOk and hdrVoulu and not enModeHdr(photo) then
            apercuOk, raison = false, nomFichier(photo) .. " : pas en mode HDR (HDREditMode) ; une sortie HDR n'y ajouterait rien. "
                .. "La passer en HDR (apply_settings, HDREditMode = 1) ou la livrer en SDR (hdr = false)."
        end
        if apercuOk then
            photos[#photos + 1] = photo
        else
            refusees[photo] = raison
        end
    end
    if #photos == 0 then
        echouer(refusees[visees[1]])
    end
    -- Empilée avec l'original, la livraison va dans son dossier : pas de dossier choisi.
    local dossier = r.reimporter == 'pile' and (LrPathUtils.parent(tostring(brut(photos[1], 'path') or '')) or '')
        or dossierDeLivraison(params.dossier)
    local reglages, format = reglagesExport(params, dossier)
    -- Réglages IA calculés avant le rendu (masques, profil adaptatif) : la fenêtre « Mises à jour IA
    -- recommandées » ne s'ouvre pas ; sinon (modèles IA absents), elle attend la réponse de l'utilisateur.
    if format ~= 'ORIGINAL' and format ~= 'DNG' then
        for _, photo in ipairs(photos) do
            calculerAvantRendu(photo)
        end
    end
    local parId, fichiers = {}, Json.tableau()
    -- Exportées avant (isExported lu avant l'exportation) : celle de passage vers Fibo 2 ne compte pas
    -- comme une livraison (comme un aperçu de Claude : apercuSeulement).
    local dejaExportees = {}
    for _, photo in ipairs(photos) do
        parId[photo.localIdentifier] = { photo = decrire(photo, false), depuis_apercu_dynamique = apercus[photo] or nil }
        dejaExportees[photo] = Photos.brut(photo, 'isExported') == true
    end
    local export = LrExportSession { photosToExport = photos, exportSettings = reglages }
    local fini, erreur = LrTasks.pcall(function()
        for _, rendu in export:renditions() do
            local photo = rendu.photo
            local ok, cheminOuMessage = rendu:waitForRender()
            local entree = photo and parId[photo.localIdentifier]
            if entree then
                if ok then
                    entree.chemin = cheminOuMessage
                    local attributs = LrFileUtils.fileAttributes(cheminOuMessage)
                    entree.octets = attributs and attributs.fileSize or Json.null
                else
                    entree.erreur = tostring(cheminOuMessage or "raison inconnue")
                end
            end
        end
    end)
    if not fini then
        error(erreur, 0)
    end
    local reussies, livrees = 0, {}
    for _, photo in ipairs(visees) do
        local entree = parId[photo.localIdentifier]
        if refusees[photo] then
            entree = { photo = decrire(photo, false), erreur = refusees[photo] }
        end
        if not entree.chemin and not entree.erreur then
            entree.erreur = "Lightroom n'a pas rendu cette photo."
        end
        if entree.chemin then
            reussies = reussies + 1
            livrees[#livrees + 1] = entree
        end
        fichiers[#fichiers + 1] = entree
    end
    if reglages.LR_reimportExportedPhoto then
        photosReimportees(livrees)
    end
    if pourFibo then
        -- Exportée pour Fibo 2 : l'accord de cette exportation vaudra pour son importation. Ce n'est
        -- pas une livraison : une photo qui n'était pas exportée est notée apercuSeulement (Lightroom
        -- vient de faire passer isExported à vrai), comme après un aperçu de Claude (Rendu.lua).
        local apercues = {}
        for _, photo in ipairs(photos) do
            local entree = parId[photo.localIdentifier]
            if entree and entree.chemin then
                Livraison.exportsFibo[photo.localIdentifier] = LrDate.currentTime()
                if not dejaExportees[photo] and Photos.brut(photo, 'isExported') == true
                    and photo:getPropertyForPlugin(_PLUGIN, 'apercuSeulement') ~= 'oui' then
                    apercues[#apercues + 1] = photo
                end
            end
        end
        if #apercues > 0 then
            LrTasks.pcall(Ecriture.ecrireMemoire, ETAPE_FIBO, function()
                for _, photo in ipairs(apercues) do
                    photo:setPropertyForPlugin(_PLUGIN, 'apercuSeulement', 'oui')
                end
            end)
        end
    else
        -- Livrées pour de bon : elles ne sont plus « exportées seulement en aperçu ».
        local exportees = {}
        for _, photo in ipairs(photos) do
            local entree = parId[photo.localIdentifier]
            if entree and entree.chemin and photo:getPropertyForPlugin(_PLUGIN, 'apercuSeulement') == 'oui' then
                exportees[#exportees + 1] = photo
            end
        end
        if #exportees > 0 then
            LrTasks.pcall(Ecriture.ecrireMemoire, "Claude · livraison", function()
                for _, photo in ipairs(exportees) do
                    photo:setPropertyForPlugin(_PLUGIN, 'apercuSeulement', nil)
                end
            end)
        end
    end
    Liaison.noter(string.format("Livraison : %d fichier(s) exporté(s) vers %s", reussies, dossier))
    return { mode = modeTexte(prefs), dossier = dossier, format = format, fichiers = fichiers,
        reimportees = reglages.LR_reimportExportedPhoto or nil, empilees = reglages.LR_reimport_stackWithOriginal or nil,
        videos_ecartees = videos > 0 and videos or nil }
end

-- Retouche générative (Fibo 2, commande importerGeneree ; outil generative_edit du connecteur,
-- demandé par Dany le 29 octobre 2026) : ce que Lightroom ne sait pas faire (changer un vêtement,
-- ajouter ou retirer un objet), le connecteur le fait faire par Fibo 2, en local, d'après un TIFF
-- exporté (commande exporter, vers Temporaire/Fibo) ; il en tire un TIFF final en pleine
-- résolution, que cette commande range à côté de l'original et ajoute au catalogue, empilé
-- au-dessus de lui (catalog:addPhoto, dans une écriture), puis montre comme photo active : les
-- finitions se font sur elle. L'original n'est jamais touché. undo_last ne la retire pas (aucune
-- étape « Claude · » : Photo › Retirer du catalogue, à la main). Reste à constater dans Lightroom :
-- addPhoto avec la pile ('above') et la photo ajoutée relue après l'écriture.
-- Les garde-fous des photos (verifierProtection) valent comme pour toute écriture ; sous « Copies
-- virtuelles seulement », les finitions se font sur une copie virtuelle de la nouvelle photo, qui
-- devient la photo active (son id dans la réponse). Une photo d'essai (« Développeur › Essais »,
-- elle ou son original) : la nouvelle photo n'est pas empilée avec le vrai original, elle va dans
-- les mêmes collections Essais, et la recette peut la retirer (retirerReimportees).
--
-- params : photo (id de la photo d'origine ; sans lui, la photo active), chemin (le TIFF final,
-- sous Temporaire/Fibo), nom (nom de base proposé, sans extension), consigne (l'instruction donnée
-- à Fibo 2, pour le journal et la demande d'accord), confirme. Réponse : { id, fichier, chemin,
-- empilee, active } ; essai = true pour une photo d'essai ; sous « Copies virtuelles seulement »,
-- copie_virtuelle (id = la copie) et photo_fibo (le TIFF importé).

-- Le nom de base du fichier : sans dossier, ni caractère que le Finder refuse, ni point en tête ;
-- sinon celui de l'original suivi de « -Fibo ».
local function nomDeBase(nom, origine)
    local base = type(nom) == 'string' and nom or ''
    base = base:gsub('%.[Tt][Ii][Ff][Ff]?$', ''):gsub('[%c/:\\]', '-'):gsub('^[%s%.]+', ''):gsub('%s+$', '')
    if base == '' then
        local fichier = tostring(Photos.meta(origine, 'fileName') or LrPathUtils.leafName(tostring(brut(origine, 'path') or '')) or 'photo')
        base = fichier:gsub('%.[^.]*$', '') .. '-Fibo'
    end
    return Texte.debut(base, 100)
end

-- « <nom>.tif », sinon « <nom>-2.tif », « <nom>-3.tif »… dans le dossier : jamais d'écrasement.
local function cheminLibre(dossier, base)
    local chemin = LrPathUtils.child(dossier, base .. '.tif')
    local n = 1
    while LrFileUtils.exists(chemin) do
        n = n + 1
        if n > 999 then
            echouer("Aucun nom libre pour « " .. base .. ".tif » dans « " .. dossier .. " » : rien n'a été importé.")
        end
        chemin = LrPathUtils.child(dossier, base .. '-' .. n .. '.tif')
    end
    return chemin
end

-- Les collections « Développeur › Essais » de la photo et de son original (une photo d'essai).
local function collectionsEssais(photo)
    local trouvees, vues = {}, {}
    local ok = LrTasks.pcall(function()
        local original = brut(photo, 'isVirtualCopy') == true and brut(photo, 'masterPhoto') or photo
        for _, p in ipairs({ photo, original }) do
            for _, collection in ipairs(p:getContainedCollections() or {}) do
                local parent = collection:getParent()
                if not vues[collection] and collection:getName() == Carnet.ESSAIS.collection
                    and parent and parent:getName() == Carnet.ESSAIS.ensemble then
                    vues[collection] = true
                    trouvees[#trouvees + 1] = collection
                end
            end
        end
    end)
    return ok and trouvees or {}
end

-- Sous « Copies virtuelles seulement » (Gestionnaire de modules externes) : une copie virtuelle de
-- la photo importée, sur laquelle se font les finitions (l'original TIFF les refuserait). La photo
-- doit être seule sélectionnée (createVirtualCopies agit sur la sélection) ; rend la copie, ou nil.
local function copiePourLesFinitions(cat, nouvelle)
    local copies
    local ok = LrTasks.pcall(Ecriture.ecrire, "Claude · copie virtuelle", function()
        copies = cat:createVirtualCopies("Claude")
    end)
    if not ok then
        return nil
    end
    local copie = type(copies) == 'table' and copies[1] or nil
    if not copie then
        local lues, liste = LrTasks.pcall(brut, nouvelle, 'virtualCopies')
        copie = lues and type(liste) == 'table' and liste[1] or nil
    end
    return copie
end

function Livraison.importerGeneree(params)
    verifierPause(params)
    local prefs = Preferences.lire()
    if prefs.mode == 'proposer' and not params.confirme then
        echouer("Mode « Proposer d'abord » actif dans Lightroom : rien n'a été importé. Dire à l'utilisateur ce que Fibo 2 "
            .. "changerait, attendre son accord, puis rappeler generative_edit avec confirm = true.")
    end
    local chemin = params.chemin
    if not dansFibo(chemin) then
        echouer("« " .. tostring(chemin) .. " » n'est pas dans le dossier de passage de Fibo 2 (" .. Livraison.dossierFibo()
            .. ") : rien n'a été importé.")
    end
    if not tostring(chemin):lower():match('%.tiff?$') then
        echouer("« " .. LrPathUtils.leafName(chemin) .. " » n'est pas un TIFF : rien n'a été importé.")
    end
    if LrFileUtils.exists(chemin) ~= 'file' then
        echouer("Fichier de Fibo 2 introuvable : « " .. chemin .. " » ; rien n'a été importé. Recommencer generative_edit.")
    end
    local photo = Photos.photoVisee(params)
    -- Les garde-fous des photos, comme toute écriture (déjà vus à l'exportation ; la photo peut avoir
    -- changé pendant le calcul de Fibo 2).
    verifierProtection({ photo }, prefs, params, 'generative_edit')
    -- Une copie virtuelle : la nouvelle photo va à côté de son original, empilée avec lui.
    local origine = brut(photo, 'isVirtualCopy') == true and brut(photo, 'masterPhoto') or photo
    local cheminOriginal = brut(origine, 'path')
    local dossier = type(cheminOriginal) == 'string' and LrPathUtils.parent(cheminOriginal) or nil
    if Photos.originalAbsent(origine) or not dossier or LrFileUtils.exists(dossier) ~= 'directory' then
        echouer(Photos.raisonOriginalAbsent(origine, "La photo de Fibo 2 se range dans son dossier : rien n'a été importé."))
    end
    -- L'accord de l'exportation vaut pour l'importation qui la suit (Livraison.exportsFibo) ;
    -- sinon, celui de la fenêtre de la liaison, comme les autres écritures, avec la consigne.
    local exportee = Livraison.exportsFibo[photo.localIdentifier]
    if not (exportee and LrDate.currentTime() - exportee <= DUREE_GENEREE) then
        local demande = {}
        for cle, valeur in pairs(params) do
            demande[cle] = valeur
        end
        demande.etape = ETAPE_FIBO
        demande.raison = type(params.consigne) == 'string' and params.consigne ~= '' and params.consigne or nil
        accordDansLightroom(prefs, demande, 'generative_edit')
    end
    -- Une photo d'essai (« Développeur › Essais ») : la nouvelle photo va dans les mêmes collections
    -- Essais, sans pile avec le vrai original (une photo de Dany, à ne pas toucher), et la recette peut
    -- la retirer (retirerReimportees).
    local essais = collectionsEssais(photo)
    local essai = #essais > 0
    local destination = cheminLibre(dossier, nomDeBase(params.nom, origine))
    if not LrFileUtils.copy(chemin, destination) or LrFileUtils.exists(destination) ~= 'file' then
        echouer("Lightroom n'a pas copié la photo de Fibo 2 dans « " .. dossier .. " » (disque plein ou protégé ?) : rien n'a été importé.")
    end
    local cat = Photos.catalogue()
    local nouvelle
    local ajoutee, erreur = LrTasks.pcall(Ecriture.ecrire, ETAPE_FIBO, function()
        if essai then
            nouvelle = cat:addPhoto(destination)
        else
            nouvelle = cat:addPhoto(destination, origine, 'above')
        end
    end)
    if not ajoutee then
        -- Le fichier copié n'est pas au catalogue : à la corbeille du Finder, jamais laissé seul.
        Fichiers.corbeille(destination)
        echouer("Lightroom n'a pas importé la photo de Fibo 2 : " .. Liaison.messageErreur(erreur) .. " Rien n'a été ajouté au catalogue.")
    end
    -- La photo ajoutée ne se lit qu'après l'écriture : rendue par addPhoto, sinon par son chemin.
    if not nouvelle then
        local trouvee, parChemin = LrTasks.pcall(cat.findPhotoByPath, cat, destination)
        nouvelle = trouvee and parChemin or nil
    end
    if not nouvelle then
        echouer("Lightroom ne retrouve pas la photo de Fibo 2 importée (« " .. destination .. " ») : la chercher dans son dossier.")
    end
    Livraison.exportsFibo[photo.localIdentifier] = nil
    -- La recette seule retire une photo importée par le module dans la session (retirerReimportees).
    reimporteesSession[destination] = LrDate.currentTime()
    -- Le journal de Claude de la nouvelle photo : ce que Fibo 2 y a fait (sans étape à défaire), et
    -- « retouchée par Claude ». Écriture de la mémoire seule (privée) ; un échec ne défait rien.
    local consigne = Texte.nettoyer(type(params.consigne) == 'string' and params.consigne or '')
    local notee, erreurJournal = LrTasks.pcall(Ecriture.ecrireMemoire, ETAPE_FIBO, function()
        local journal = {}
        Ecriture.ajouterJournal(journal, { etape = ETAPE_FIBO .. " : " .. Texte.raccourcir(consigne ~= '' and consigne or "retouche générative", 120),
            type = 'retouche', raison = consigne ~= '' and consigne or nil, origine = photo.localIdentifier })
        Photos.garder(nouvelle, 'journalClaude', Json.encode(journal))
        Photos.garder(nouvelle, 'retoucheeParClaude', 'oui')
    end)
    if not notee then
        Liaison.noter("Journal de la photo de Fibo 2 non écrit : " .. Liaison.messageErreur(erreurJournal))
    end
    -- Elle devient la photo active, seule sélectionnée (son dossier affiché au besoin).
    local okSelection, active = LrTasks.pcall(Bibliotheque.selectionnerAvecSource, { nouvelle })
    active = okSelection and active == true
    -- Copies virtuelles seulement : les finitions se font sur une copie virtuelle de la nouvelle photo.
    local copie
    if prefs.copiesSeulement and active then
        copie = copiePourLesFinitions(cat, nouvelle)
        if copie then
            local okCopie, copieActive = LrTasks.pcall(Bibliotheque.selectionnerAvecSource, { copie })
            active = okCopie and copieActive == true
        end
    end
    -- Dans les collections Essais, dans une écriture suivante (une photo ajoutée ne se lit pas dans
    -- l'écriture qui l'a créée).
    if essai then
        local rangee, erreurEssais = LrTasks.pcall(Ecriture.ecrire, ETAPE_FIBO, function()
            for _, collection in ipairs(essais) do
                collection:addPhotos(copie and { nouvelle, copie } or { nouvelle })
            end
        end)
        if not rangee then
            Liaison.noter("Photo de Fibo 2 non rangée dans Développeur › Essais : " .. Liaison.messageErreur(erreurEssais))
        end
    end
    Fichiers.supprimer(chemin)
    local fichier = LrPathUtils.leafName(destination)
    Liaison.noter("Fibo 2 : « " .. fichier .. " » importée" .. (essai and ", rangée dans Développeur › Essais (sans pile)"
        or (", empilée au-dessus de « " .. nomFichier(origine) .. " »")), nouvelle.localIdentifier)
    local reponse = { id = (copie or nouvelle).localIdentifier, fichier = fichier, chemin = destination, empilee = not essai,
        active = active, essai = essai or nil }
    if prefs.copiesSeulement then
        reponse.copie_virtuelle = copie ~= nil
        reponse.photo_fibo = nouvelle.localIdentifier
    end
    return reponse
end

-- Recette seulement (pas d'outil) : retire du catalogue les fichiers que le module vient d'y
-- réimporter, par leur chemin exact, dans la même session et dans les 30 minutes
-- (LrSelection.removeFromCatalog, SDK 14.3, sur la photo seule sélectionnée). Le fichier reste sur
-- le disque : la recette l'efface ensuite.
function Livraison.retirerReimportees(params)
    local cat = Photos.catalogue()
    local LrSelection = import 'LrSelection'
    local retires = Json.tableau()
    -- La vue d'avant, remise à la fin (même après un échec) : sans elle, la photo active restait une
    -- photo du dossier de la photo retirée (constaté le 21 octobre 2026 après la recette).
    local vue = { active = cat:getTargetPhoto(), selection = cat:getTargetPhotos() }
    local sourcesLues, sourcesAvant = LrTasks.pcall(cat.getActiveSources, cat)
    if not sourcesLues then
        sourcesAvant = nil
    end
    local selectionChangee, sourceChangee = false, false
    local ok, erreur = LrTasks.pcall(function()
        for _, chemin in ipairs(type(params.chemins) == 'table' and params.chemins or {}) do
            local quand = reimporteesSession[chemin]
            if not quand or LrDate.currentTime() - quand > DUREE_RETRAIT then
                echouer("« " .. tostring(chemin) .. " » n'a pas été réimporté par Claude dans cette session : rien n'est retiré.")
            end
            local trouvee, photo = LrTasks.pcall(cat.findPhotoByPath, cat, chemin)
            if trouvee and photo then
                selectionChangee = true
                local fait, changee = Bibliotheque.selectionnerAvecSource({ photo })
                sourceChangee = sourceChangee or changee
                if not fait then
                    echouer("Lightroom n'a pas sélectionné « " .. chemin .. " » : rien n'est retiré.")
                end
                LrSelection.removeFromCatalog()
                local fin = LrDate.currentTime() + 5
                repeat
                    LrTasks.sleep(0.25)
                    local _, encore = LrTasks.pcall(cat.findPhotoByPath, cat, chemin)
                    if not encore then
                        break
                    end
                until LrDate.currentTime() > fin
                local _, encore = LrTasks.pcall(cat.findPhotoByPath, cat, chemin)
                if encore then
                    echouer("Lightroom n'a pas retiré « " .. chemin .. " » du catalogue.")
                end
            end
            reimporteesSession[chemin] = nil
            retires[#retires + 1] = chemin
        end
    end)
    if selectionChangee then
        Bibliotheque.remettreSelection(vue.active, vue.selection, sourceChangee and sourcesAvant or nil)
    end
    if not ok then
        error(erreur, 0)
    end
    return { retires = retires }
end

-- Dernier recours : la fenêtre d'exportation de Lightroom, photos sélectionnées ; l'utilisateur
-- choisit et termine. La fenêtre est modale : elle s'ouvre dans sa propre tâche, pour que la
-- réponse parte tout de suite.
function Livraison.fenetreExport(params)
    local photos = photosVisees(params)
    if #photos == 0 then
        echouer("Aucune photo à exporter.")
    end
    local fait = Bibliotheque.selectionnerAvecSource(photos)
    if not fait then
        echouer("Lightroom n'a pas sélectionné ces photos : les afficher (show_photo), puis réessayer.")
    end
    local cible = Photos.catalogue():getTargetPhoto() or photos[1]
    LrTasks.startAsyncTask(function()
        LrTasks.pcall(cible.openExportDialog, cible)
    end)
    Liaison.noter(string.format("Fenêtre d'exportation ouverte pour %d photo(s)", #photos))
    return { ouverte = true, photos = #photos }
end

-- Ce qu'il faut pour choisir une livraison : modèles de noms de fichiers, paramètres prédéfinis de
-- métadonnées, services de publication et réglages des services Disque dur.
function Livraison.options(params)
    local function triee(table_noms)
        local liste = Json.tableau()
        local ok, presets = LrTasks.pcall(table_noms)
        for nom, id in pairs(ok and type(presets) == 'table' and presets or {}) do
            liste[#liste + 1] = { nom = tostring(nom), id = tostring(id) }
        end
        table.sort(liste, function(a, b) return a.nom < b.nom end)
        return liste
    end
    return {
        modeles_noms = triee(LrApplication.filenamePresets),
        presets_metadonnees = triee(LrApplication.metadataPresets),
        services_publication = Services.decrire(),
    }
end

-- Dossier choisi dans une fenêtre du Mac (LrDialogs.runOpenPanel) plutôt que par son chemin. La
-- fenêtre attend l'utilisateur : elle s'ouvre dans sa propre tâche, et la commande attend son
-- choix quelques dizaines de secondes au plus ; passé ce délai, elle répond « en attente », et la
-- commande suivante relit le choix, gardé jusque-là.
local fenetreDossier = { ouverte = false, choix = nil }
local ATTENTE_CHOIX = 40

function Livraison.choisirDossier(params)
    if not fenetreDossier.ouverte and fenetreDossier.choix == nil then
        local depart = type(params.depart) == 'string' and LrFileUtils.exists(params.depart) == 'directory' and params.depart or nil
        fenetreDossier.ouverte = true
        LrTasks.startAsyncTask(function()
            local ok, chemins = LrTasks.pcall(LrDialogs.runOpenPanel, {
                title = type(params.titre) == 'string' and params.titre or "Dossier de livraison (Claude)",
                prompt = "Choisir",
                canChooseFiles = false,
                canChooseDirectories = true,
                canCreateDirectories = true,
                allowsMultipleSelection = false,
                initialDirectory = depart,
            })
            if not ok then
                fenetreDossier.choix = { erreur = Liaison.messageErreur(chemins) }
            elseif type(chemins) == 'table' and type(chemins[1]) == 'string' then
                fenetreDossier.choix = { dossier = chemins[1] }
            else
                fenetreDossier.choix = { annule = true }
            end
            fenetreDossier.ouverte = false
        end)
        Liaison.noter("Fenêtre « Dossier de livraison » ouverte : l'utilisateur choisit")
    end
    local fin = LrDate.currentTime() + (tonumber(params.attente) or ATTENTE_CHOIX)
    while fenetreDossier.choix == nil and LrDate.currentTime() < fin do
        LrTasks.sleep(0.5)
    end
    local choix = fenetreDossier.choix
    if choix == nil then
        return { en_attente = true }
    end
    fenetreDossier.choix = nil
    if choix.erreur then
        echouer("Lightroom n'a pas ouvert la fenêtre de choix du dossier : " .. tostring(choix.erreur))
    end
    return choix
end

-- Les noms que Lightroom donnera aux fichiers avec un modèle de noms (photo:getNameViaPreset, sans
-- l'extension), pour les premières photos de la série.
function Livraison.nomsFichiers(params)
    local ok, presets = LrTasks.pcall(LrApplication.filenamePresets)
    local voulu = tostring(params.modele or ''):lower()
    local id, nomModele
    for nom, identifiant in pairs(ok and type(presets) == 'table' and presets or {}) do
        if tostring(nom):lower() == voulu then
            id, nomModele = identifiant, tostring(nom)
        end
    end
    if not id then
        echouer("Modèle de noms introuvable dans Lightroom : « " .. tostring(params.modele) .. " ».")
    end
    local depart = math.max(1, math.floor(tonumber(params.sequence) or 1))
    local noms = Json.tableau()
    for i, photo in ipairs(photosVisees(params)) do
        if i > 20 then
            break
        end
        local okNom, nom = LrTasks.pcall(photo.getNameViaPreset, photo, id, type(params.texte_perso) == 'string' and params.texte_perso or '', depart + i - 1)
        noms[#noms + 1] = { photo = decrire(photo, false), nom = okNom and nom or Json.null,
            erreur = (not okNom) and Liaison.messageErreur(nom) or nil }
    end
    return { modele = nomModele, noms = noms }
end

-- Aperçus dynamiques (catalog:buildSmartPreviews, SDK 5.0) : pour regarder, trier et livrer pour
-- le web le disque des originaux débranché. Lightroom montre sa propre barre de progression.
-- Retirer (photo:deleteSmartPreview) libère la place au retour ; jamais pour une photo dont
-- l'original manque : son aperçu est alors tout ce qui reste pour la travailler.
function Livraison.apercusDynamiques(params)
    verifierPause(params)
    local photos = photosVisees(params)
    local cat = Photos.catalogue()
    local resultat = { crees = Json.tableau(), existants = Json.tableau(), echecs = Json.tableau(), sans_original = Json.tableau(),
        retires = Json.tableau(), absents = Json.tableau() }
    if params.retirer then
        for _, photo in ipairs(photos) do
            if not Photos.apercuDynamique(photo) then
                resultat.absents[#resultat.absents + 1] = nomFichier(photo)
            elseif Photos.originalAbsent(photo) then
                resultat.sans_original[#resultat.sans_original + 1] = nomFichier(photo)
            else
                local ok, bilan = LrTasks.pcall(photo.deleteSmartPreview, photo)
                local liste = (ok and bilan == 'deleted') and resultat.retires or resultat.echecs
                liste[#liste + 1] = nomFichier(photo)
            end
        end
        Liaison.noter(string.format("Aperçus dynamiques : %d retiré(s)", #resultat.retires))
        return resultat
    end
    local aConstruire = {}
    for _, photo in ipairs(photos) do
        if Photos.apercuDynamique(photo) then
            resultat.existants[#resultat.existants + 1] = nomFichier(photo)
        elseif Photos.originalAbsent(photo) then
            resultat.sans_original[#resultat.sans_original + 1] = nomFichier(photo)
        else
            aConstruire[#aConstruire + 1] = photo
        end
    end
    if #aConstruire > 0 then
        local ok, bilan = LrTasks.pcall(cat.buildSmartPreviews, cat, aConstruire)
        if not ok then
            echouer("Lightroom n'a pas créé les aperçus dynamiques : " .. Liaison.messageErreur(bilan))
        end
        local vus = {}
        for _, cle in ipairs({ 'created', 'existed', 'failed' }) do
            for _, photo in ipairs(type(bilan) == 'table' and type(bilan[cle]) == 'table' and bilan[cle] or {}) do
                vus[photo.localIdentifier] = true
                local liste = cle == 'created' and resultat.crees or (cle == 'existed' and resultat.existants or resultat.echecs)
                liste[#liste + 1] = nomFichier(photo)
            end
        end
        -- Lightroom s'arrête au premier échec ou si l'utilisateur annule (référence du SDK).
        for _, photo in ipairs(aConstruire) do
            if not vus[photo.localIdentifier] then
                resultat.echecs[#resultat.echecs + 1] = nomFichier(photo)
            end
        end
    end
    local octets = 0
    for _, photo in ipairs(photos) do
        local info = brut(photo, 'smartPreviewInfo')
        octets = octets + (type(info) == 'table' and tonumber(info.smartPreviewSize) or 0)
    end
    resultat.taille_mo = math.floor(octets / 104857.6 + 0.5) / 10
    Liaison.noter(string.format("Aperçus dynamiques : %d créé(s), %d déjà là", #resultat.crees, #resultat.existants))
    return resultat
end

return Livraison
