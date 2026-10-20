-- Services.lua : les services de publication du catalogue, et les réglages des services Disque
-- dur, qui font les livraisons types (lus clé par clé ; commande livraison).
--
-- Rien n'y est créé, changé ni publié : le module ne fait que les lire. Le serveur tire des
-- services Disque dur ses livraisons types (format, taille, netteté, dossier habituel).

local LrTasks = import 'LrTasks'

local Json = require 'Json'
local Photos = require 'Photos'

local catalogue = Photos.catalogue

local Services = {}

-- Module des services « Disque dur » de Lightroom (constaté en 2.3 dans le catalogue de Dany).
Services.DISQUE_DUR = 'com.adobe.ag.export.file'

-- Réglages d'exportation d'un service, lus clé par clé : getPublishSettings rend une table
-- observable, que pairs ne parcourt pas (constaté en 2.3).
local CLES_SERVICE = {
    'LR_format', 'LR_jpeg_quality', 'LR_jxl_quality', 'LR_jxl_losslessQuality', 'LR_avif_quality',
    'LR_export_colorSpace', 'LR_export_bitDepth', 'LR_enableHDRDisplay', 'LR_maximumCompatibility',
    'LR_size_doConstrain', 'LR_size_resizeType', 'LR_size_maxWidth', 'LR_size_maxHeight', 'LR_size_megapixels',
    'LR_size_percentage', 'LR_size_doNotEnlarge', 'LR_outputSharpeningOn', 'LR_outputSharpeningMedia',
    'LR_outputSharpeningLevel', 'LR_embeddedMetadataOption', 'LR_removeLocationMetadata', 'LR_removeFaceMetadata',
    'LR_jpeg_useLimitSize', 'LR_jpeg_limitSize', 'LR_useWatermark', 'LR_watermarking_id',
    'LR_export_destinationPathPrefix', 'LR_export_destinationType', 'LR_renamingTokensOn', 'LR_tokens',
}

local function reglagesService(service)
    local ok, reglages = LrTasks.pcall(service.getPublishSettings, service)
    if not ok or reglages == nil then
        return nil
    end
    local lus = {}
    for _, cle in ipairs(CLES_SERVICE) do
        local okCle, valeur = LrTasks.pcall(function() return reglages[cle] end)
        local genre = type(valeur)
        if okCle and (genre == 'string' or genre == 'number' or genre == 'boolean') then
            lus[cle] = valeur
        end
    end
    return lus
end

-- Les services de publication (Disque dur, Flickr, Adobe Stock…), avec les réglages de ceux du
-- Disque dur. Lecture dans une tâche (SDK).
function Services.decrire()
    local resultat = Json.tableau()
    local cat = catalogue()
    local ok, services = LrTasks.pcall(cat.getPublishServices, cat)
    for _, service in ipairs(ok and services or {}) do
        local _, nom = LrTasks.pcall(service.getName, service)
        local _, module = LrTasks.pcall(service.getPluginId, service)
        resultat[#resultat + 1] = { id = service.localIdentifier, nom = tostring(nom), module = tostring(module),
            reglages = module == Services.DISQUE_DUR and reglagesService(service) or nil }
    end
    return resultat
end

return Services
