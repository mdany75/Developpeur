-- Lecture.lua : les commandes qui ne changent rien : état de la liaison, sélection, réglages,
-- paramètres prédéfinis, diagnostic du SDK, journal.

local LrApplication = import 'LrApplication'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Amelioration = require 'Amelioration'
local Bibliotheque = require 'Bibliotheque'
local Ecriture = require 'Ecriture'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Locaux = require 'Locaux'
local Photos = require 'Photos'
local Preferences = require 'Preferences'
local Reglages = require 'Reglages'

local catalogue, decrire, lireJson = Photos.catalogue, Photos.decrire, Photos.lireJson
local photosVisees, photoVisee = Photos.photosVisees, Photos.photoVisee
local cleReelle, CLES_COURBES, estRaw = Reglages.cleReelle, Reglages.CLES_COURBES, Reglages.estRaw
local lireReglages, minuscules = Reglages.lireReglages, Reglages.minuscules
local pourLightroom = Reglages.pourLightroom
local modeTexte = Ecriture.modeTexte
local ameliorationAffichee = Amelioration.ameliorationAffichee

local Lecture = {}

-- Sauvegarde du catalogue demandée à Lightroom (LrApplication.backupAtNextShutdown, SDK 4.0) : elle
-- se fait à sa prochaine fermeture, par sa fenêtre de sauvegarde (l'utilisateur peut la passer).
local function demanderSauvegarde()
    local ok, erreur = LrTasks.pcall(LrApplication.backupAtNextShutdown, _PLUGIN.id)
    if not ok then
        error("Lightroom refuse la demande de sauvegarde : " .. tostring(erreur), 0)
    end
    return "Sauvegarde du catalogue demandée : Lightroom la fera à sa prochaine fermeture (sa fenêtre de sauvegarde ; "
        .. "l'utilisateur peut la passer). Pour qu'elle garde l'état d'avant une longue série, fermer puis rouvrir Lightroom avant de la commencer."
end

function Lecture.etat(params)
    local prefs = Preferences.lire()
    local cat = catalogue()
    local active = cat:getTargetPhoto()
    local sauvegarde = params.sauvegarde == true and demanderSauvegarde() or nil
    return {
        sauvegarde = sauvegarde,
        module = "Développeur",
        version_module = Liaison.VERSION,
        -- Liaison fermée par le jeton (1.2) : une commande qui arrive ici l'a porté. Un module plus
        -- ancien n'a pas ce champ. Jamais le jeton ni son chemin.
        liaison_fermee = true,
        lightroom = LrApplication.versionString(),
        catalogue = LrPathUtils.leafName(cat:getPath()),
        -- Le chemin complet (1.3.5) : le serveur y lit la dernière sauvegarde du catalogue et le
        -- volume pour Time Machine, puis le retire avant Claude.
        chemin_catalogue = cat:getPath(),
        mode = modeTexte(prefs),
        pause = Liaison.pause,
        instantane_avant_claude = prefs.instantane,
        limites = {
            variation_exposition_max = prefs.variationExpositionMax,
            saturation_max = prefs.saturationMax,
        },
        photo_active = active and decrire(active, true) or Json.null,
        nombre_photos_visees = #cat:getTargetPhotos(),
    }
end

function Lecture.selection(params)
    local limite = tonumber(params.limite) or 50
    local cat = catalogue()
    local photos = cat:getTargetPhotos()
    local active = cat:getTargetPhoto()
    local premieres = {}
    for i = 1, math.min(#photos, limite) do
        premieres[i] = photos[i]
    end
    local liste = Json.tableau()
    for i, d in ipairs(Photos.decrireTout(premieres)) do
        if active and premieres[i].localIdentifier == active.localIdentifier then
            d.active = true
        end
        liste[#liste + 1] = d
    end
    return { total = #photos, renvoyees = #liste, photos = liste }
end

-- Copie de tout ce que range Lightroom, pour le JSON : tables imbriquées, nombres, textes et
-- booléens (le reste est écarté).
local function copieBrute(valeur, profondeur)
    local genre = type(valeur)
    if genre == 'number' or genre == 'string' or genre == 'boolean' then
        return valeur
    end
    if genre ~= 'table' or profondeur > 8 then
        return nil
    end
    local copie = {}
    for cle, element in pairs(valeur) do
        if type(cle) == 'string' or type(cle) == 'number' then
            copie[cle] = copieBrute(element, profondeur + 1)
        end
    end
    return copie
end

function Lecture.reglages(params)
    local photo = photoVisee(params)
    local valeurs, infos = lireReglages(photo, params.cles, params.details)
    infos.photo = decrire(photo, false)
    infos.reglages = valeurs
    -- Tous les réglages bruts, même ceux que le serveur ne connaît pas : pour explorer un outil
    -- de Lightroom fait à la main (flou d'objectif, réduction du bruit…).
    if params.toutes then
        infos.tous = copieBrute(photo:getDevelopSettings(), 0)
    end
    -- Débruitage, détails bruts, super résolution : Lightroom ne les dit que pour la photo affichée
    -- dans le module Développement.
    if params.details then
        infos.classement = Bibliotheque.classement(photo)
        -- Noms des instantanés (panneau Instantanés) : « Avant Claude », variantes « Claude · … ».
        local ok, instantanes = LrTasks.pcall(photo.getDevelopSnapshots, photo)
        if ok and type(instantanes) == 'table' then
            infos.instantanes = Json.tableau()
            for _, e in ipairs(instantanes) do
                infos.instantanes[#infos.instantanes + 1] = tostring(e.name or '')
            end
        end
        infos.amelioration = ameliorationAffichee(photo)
            or "connue seulement pour la photo affichée dans le module Développement"
    end
    -- Ce que l'utilisateur a changé à la main depuis la dernière commande de Claude.
    infos.corrections_utilisateur = Ecriture.correctionsUtilisateur(photo)
    return infos
end

function Lecture.presets(params)
    local filtre = type(params.filtre) == 'string' and minuscules(params.filtre) or nil
    local limite = tonumber(params.limite) or 100
    local liste, total = Json.tableau(), 0
    for _, dossier in ipairs(LrApplication.developPresetFolders()) do
        local nomDossier = dossier:getName()
        for _, preset in ipairs(dossier:getDevelopPresets()) do
            local nom = preset:getName()
            if not filtre or minuscules(nom):find(filtre, 1, true) or minuscules(nomDossier):find(filtre, 1, true) then
                total = total + 1
                if #liste < limite then
                    liste[#liste + 1] = { dossier = nomDossier, nom = nom, uuid = preset:getUuid() }
                end
            end
        end
    end
    return { total = total, renvoyes = #liste, presets = liste }
end

function Lecture.creerPreset(params)
    local photo = photoVisee(params)
    local actuels = photo:getDevelopSettings()
    local raw = estRaw(photo, actuels)
    local inclure = type(params.inclure) == 'table' and params.inclure or {}
    local reglages = { ProcessVersion = actuels.ProcessVersion }
    local function prendre(cle)
        if actuels[cle] ~= nil then
            reglages[cle] = pourLightroom(actuels[cle])
        end
    end
    for _, cle in ipairs(type(params.cles) == 'table' and params.cles or {}) do
        prendre(cleReelle(cle, raw))
        if cle == 'Temperature' then
            prendre('WhiteBalance')
        end
    end
    if inclure.profil then
        prendre('CameraProfile')
        reglages.Look = pourLightroom(actuels.Look or {})
    end
    if inclure.courbes then
        for _, cle in ipairs(CLES_COURBES) do
            prendre(cle)
        end
        prendre('ToneCurveName2012')
    end
    if inclure.couleurs then
        prendre('PointColors')
    end
    if inclure.recadrage then
        for _, cle in ipairs({ 'CropAngle', 'CropLeft', 'CropTop', 'CropRight', 'CropBottom' }) do
            prendre(cle)
        end
    end
    if inclure.masques and actuels.MaskGroupBasedCorrections ~= nil then
        reglages.MaskGroupBasedCorrections = Locaux.sansCalculsIA(pourLightroom(actuels.MaskGroupBasedCorrections))
    end
    if inclure.taches then
        prendre('RetouchAreas')
    end
    -- Le serveur en fait un fichier XMP de paramètre prédéfini : ceux qu'un module externe crée
    -- dans Lightroom restent invisibles dans le panneau Paramètres prédéfinis.
    Liaison.noter("Réglages lus pour un paramètre prédéfini : " .. tostring(params.nom or ""))
    return {
        reglages = reglages,
        raw = raw,
        source = decrire(photo, false),
    }
end

-- Objets du SDK dont le diagnostic cherche les méthodes, pris en lecture : le catalogue, la photo
-- active, le premier mot-clé, la première collection, le premier ensemble de collections et le
-- premier service de publication (ceux du Disque dur font les livraisons types).
local function objetsSondes(cat)
    local function premier(methode)
        local ok, liste = LrTasks.pcall(methode, cat)
        return ok and type(liste) == 'table' and liste[1] or nil
    end
    return {
        catalogue = cat,
        photo = cat:getTargetPhoto(),
        mot_cle = premier(cat.getKeywords),
        collection = premier(cat.getChildCollections),
        ensemble = premier(cat.getChildCollectionSets),
        service_publication = premier(cat.getPublishServices),
    }
end

-- Fonctions offertes par le SDK de cette version de Lightroom, pour le diagnostic : celles des
-- modules (`modules`), et des méthodes cherchées par leur nom (`methodes`, par objet), sans être
-- appelées : Lightroom Classic 15.6 refuse getmetatable sur ses objets (constaté), ce qui empêche
-- de les lister. `cles` : le type de chaque métadonnée brute de la photo active.
function Lecture.diagnostic(params)
    local function fonctions(nom)
        local ok, module = pcall(import, nom)
        if not ok or type(module) ~= 'table' then
            return "indisponible"
        end
        local liste = Json.tableau()
        for cle, valeur in pairs(module) do
            if type(valeur) == 'function' then
                liste[#liste + 1] = cle
            end
        end
        table.sort(liste)
        return liste
    end
    local modules = {}
    for _, nom in ipairs(type(params.modules) == 'table' and params.modules or { 'LrDevelopController', 'LrApplication', 'LrApplicationView' }) do
        modules[nom] = fonctions(nom)
    end
    local resultat = { lightroom = LrApplication.versionString(), modules = modules }
    local cat = catalogue()
    if type(params.methodes) == 'table' then
        local objets = objetsSondes(cat)
        resultat.methodes = {}
        for nomObjet, noms in pairs(params.methodes) do
            local objet = objets[nomObjet]
            if objet == nil then
                resultat.methodes[nomObjet] = "absent"
            else
                local types = {}
                for _, nom in ipairs(type(noms) == 'table' and noms or {}) do
                    local ok, valeur = pcall(function() return objet[nom] end)
                    types[tostring(nom)] = ok and type(valeur) or "refusé"
                end
                resultat.methodes[nomObjet] = types
            end
        end
    end
    local photo = cat:getTargetPhoto()
    -- Valeurs lues (rien n'est écrit) : jeu de libellés actif, filtre de la Bibliothèque et ses
    -- paramètres prédéfinis, original et aperçu dynamique de la photo active.
    if params.valeurs then
        local function lire(fonction, ...)
            local resultats = { LrTasks.pcall(fonction, ...) }
            if not resultats[1] then
                return "refusée : " .. tostring(resultats[2])
            end
            local valeur = copieBrute(resultats[2], 0)
            if valeur == nil then
                valeur = Json.null
            end
            return valeur, resultats[3] ~= nil and copieBrute(resultats[3], 0) or nil
        end
        local filtre, presetFiltre = lire(cat.getCurrentViewFilter, cat)
        resultat.valeurs = {
            libelles = lire(cat.getLabelMapToColorName, cat),
            filtre = filtre,
            preset_filtre = presetFiltre,
            presets_filtre = lire(LrApplication.viewFilterPresets),
            original_present = photo and lire(photo.checkPhotoAvailability, photo) or Json.null,
            apercu_dynamique = photo and lire(photo.getRawMetadata, photo, 'smartPreviewInfo') or Json.null,
        }
    end
    if type(params.cles) == 'table' and photo then
        resultat.cles = {}
        for _, cle in ipairs(params.cles) do
            local ok, valeur = LrTasks.pcall(photo.getRawMetadata, photo, cle)
            resultat.cles[tostring(cle)] = ok and type(valeur) or "refusée"
        end
    end
    return resultat
end

-- Données de prise de vue de plus, pour la leçon de la photo (journal avec detaille, 1.3) :
-- compensation d'exposition, flash, programme et mesure de la lumière. Lues une à une par
-- Photos.meta (getFormattedMetadata sous LrTasks.pcall) : une clé que Lightroom refuse, ou vide,
-- donne nil sans gêner les autres. Jamais dans une lecture groupée (CLES_FORMATEES de Photos.lua,
-- batchGetFormattedMetadata) : une clé refusée y ferait échouer tout le lot. Constaté le
-- 21 octobre 2026 (Lightroom Classic 15.6, mesure 3 de la 1.3, cinq copies d'Essais : RAF de X-H2S
-- et de X-T20, JPEG de X-T20, HEIC d'iPhone) : aucune des quatre n'est refusée, et chacune rend un
-- texte traduit dans la langue de Lightroom, pas un code : « 0 EV », « Non déclenché »,
-- « Priorité d'ouverture », « Priorité d'obturation », « Normal », « Moyenne pondérée », « Motif ».
-- Rien ne les analyse : le texte va tel quel à Claude. Le format d'une compensation non nulle n'est
-- pas relevé (aucune copie d'Essais n'en a).
local CLES_PRISE_DE_VUE_PLUS = {
    { 'compensation', 'exposureBias' },
    { 'flash', 'flash' },
    { 'programme', 'exposureProgram' },
    { 'mesure', 'meteringMode' },
}

local function priseDeVuePlus(photo)
    local plus, lu = {}, false
    for _, c in ipairs(CLES_PRISE_DE_VUE_PLUS) do
        local valeur = Photos.meta(photo, c[2])
        local sorte = type(valeur)
        if sorte == 'string' or sorte == 'number' or sorte == 'boolean' then
            plus[c[1]] = valeur
            lu = true
        end
    end
    return lu and plus or nil
end

-- journal {photos?|selection?, detaille?} : le journal des retouches de Claude de chaque photo.
-- Avec detaille (la leçon de la photo), la photo est décrite en entier (appareil, objectif, ISO,
-- vitesse, ouverture, focale, date…) avec prise_de_vue_plus et la sensibilité ISO en nombre
-- (sensibilite, 1.3.1 : l'indice du bruit de la leçon ne vaut qu'à un ISO élevé) ; sans, la
-- description courte. Rien n'est écrit.
function Lecture.journal(params)
    local detaille = params.detaille == true
    local photos = Json.tableau()
    for _, photo in ipairs(photosVisees(params)) do
        local description = decrire(photo, detaille)
        if detaille then
            description.prise_de_vue_plus = priseDeVuePlus(photo)
            description.sensibilite = Photos.sensibilite(photo)
        end
        photos[#photos + 1] = {
            photo = description,
            entrees = Json.tableau(lireJson(photo, 'journalClaude', {})),
        }
    end
    return { photos = photos }
end

return Lecture
