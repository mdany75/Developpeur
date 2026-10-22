-- Lightroom.lua : ce que la fenêtre lit de Lightroom et de son entourage : photo active (avec sa
-- note posée, et sa légende quand elle change) et sélection, état de la liaison et mode « Proposer
-- d'abord » (lus directement : la liaison est dans ce même module), connexion de Claude Code,
-- écran principal du Mac (lu par le connecteur : `mcp-developpeur --ecran`), réglages d'une photo
-- pendant un exercice « Je le fais » (1.3, lus sans rien écrire), ce que l'onglet Focus montre de
-- Lightroom (Lightroom.infosFocus). À appeler depuis une tâche.

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Preferences = require 'Preferences'
local Texte = require 'Texte'

local Lightroom = {}

-- Drapeau (pickStatus : 1, 0 ou −1), en mots.
local DRAPEAUX = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetee' }

-- Photo active ({ id, nom, note, drapeau }) et nombre de photos sélectionnées. La note (0 à 5) et
-- le drapeau ('retenue', 'aucun', 'rejetee') posés, pour la carte Note de la fenêtre ; nil si la
-- photo ne les donne pas.
function Lightroom.photos()
    local info = { selection = 0 }
    local ok = LrTasks.pcall(function()
        local catalogue = LrApplication.activeCatalog()
        local active = catalogue:getTargetPhoto()
        if active then
            info.active = { id = active.localIdentifier, nom = active:getFormattedMetadata('fileName') or '' }
            local photos = catalogue:getTargetPhotos()
            info.selection = #photos
            -- La photo active et la sélection en un texte (Fenetre.suivreSelection) : la photo
            -- active, puis les 500 premières photos de la sélection et leur nombre.
            local ids = { tostring(active.localIdentifier), tostring(#photos) }
            for i = 1, math.min(#photos, 500) do
                ids[#ids + 1] = tostring(photos[i].localIdentifier)
            end
            info.cle = table.concat(ids, ':')
            local okNote, note, drapeau = LrTasks.pcall(function()
                return active:getRawMetadata('rating'), active:getRawMetadata('pickStatus')
            end)
            if okNote then
                info.active.note = math.floor(tonumber(note) or 0)
                info.active.drapeau = DRAPEAUX[tonumber(drapeau) or 0] or 'aucun'
            end
        end
    end)
    if not ok then
        info.active = nil
    end
    return info
end

-- La légende d'une photo, pour l'aperçu de la photo active et l'en-tête de la fenêtre (fenêtre B,
-- 1.3) : { nom (son nom de fichier), copie (le nom de sa copie virtuelle), appareil (le modèle du
-- boîtier), date (de prise de vue : « 10 juil. 2020 ») }, une table neuve de textes, chacun absent
-- s'il ne se lit pas. La date se lit à l'heure locale (timeToUserFormat : timeToW3CDate donne
-- l'UTC, constaté), les mois par Carnet.MOIS_COURTS, leur seule copie. Lue seulement quand la photo
-- active change (Fenetre.majPhoto) : Lightroom.photos, toutes les 2 s, n'en lit rien. À appeler
-- depuis une tâche.
function Lightroom.legende(id)
    local l = {}
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if not photo then
            return
        end
        local function texte(cle)
            local ok, v = LrTasks.pcall(function() return photo:getFormattedMetadata(cle) end)
            v = ok and type(v) == 'string' and Texte.nettoyer(v) or ''
            return v ~= '' and v or nil
        end
        l.nom, l.copie, l.appareil = texte('fileName'), texte('copyName'), texte('cameraModel')
        local ok, prise = LrTasks.pcall(function() return photo:getRawMetadata('dateTimeOriginal') end)
        if ok and type(prise) == 'number' then
            local jour = tonumber(LrDate.timeToUserFormat(prise, '%d'))
            local mois = require('Carnet').MOIS_COURTS[tonumber(LrDate.timeToUserFormat(prise, '%m')) or 0]
            local annee = LrDate.timeToUserFormat(prise, '%Y')
            if jour and mois and annee then
                l.date = string.format('%d %s %s', jour, mois, annee)
            end
        end
    end)
    return l
end

-- Ce que l'onglet Focus montre de Lightroom (demandé par Dany le 22 octobre 2026 : les sections
-- Image Information et Shooting Information de Focus-Points), en textes déjà traduits par
-- Lightroom (getFormattedMetadata, clé par clé sous LrTasks.pcall comme Photos.meta : une clé
-- refusée ne gêne pas les autres ; jamais une lecture groupée), sous les clés de
-- Lightroom.CLES_FOCUS, plus `date` (date et heure de la prise de vue, à l'heure locale :
-- « 13 janv. 2026 à 09:13:04 »). Une table neuve de textes, chacun absent s'il ne se lit pas. Une
-- copie virtuelle donne le nom de son original. Le boîtier (stabilisation, mode d'entraînement,
-- mise au point) vient du connecteur (Images.lireFocus). À appeler depuis une tâche.
Lightroom.CLES_FOCUS = {
    nom = 'fileName', copie = 'copyName', origine = 'dimensions', actuelle = 'croppedDimensions',
    marque = 'cameraMake', modele = 'cameraModel', objectif = 'lens', focale = 'focalLength', vitesse = 'shutterSpeed',
    ouverture = 'aperture', iso = 'isoSpeedRating', correction = 'exposureBias', programme = 'exposureProgram',
    mesure = 'meteringMode',
}

function Lightroom.infosFocus(id)
    local l = {}
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        if not photo then
            return
        end
        for cle, nom in pairs(Lightroom.CLES_FOCUS) do
            local ok, v = LrTasks.pcall(function() return photo:getFormattedMetadata(nom) end)
            v = ok and (type(v) == 'string' or type(v) == 'number') and Texte.nettoyer(tostring(v)) or ''
            l[cle] = v ~= '' and v or nil
        end
        local ok, prise = LrTasks.pcall(function() return photo:getRawMetadata('dateTimeOriginal') end)
        if ok and type(prise) == 'number' then
            local jour = tonumber(LrDate.timeToUserFormat(prise, '%d'))
            local mois = require('Carnet').MOIS_COURTS[tonumber(LrDate.timeToUserFormat(prise, '%m')) or 0]
            if jour and mois then
                l.date = string.format('%d %s %s à %s', jour, mois, LrDate.timeToUserFormat(prise, '%Y'),
                    LrDate.timeToUserFormat(prise, '%H:%M:%S'))
            end
        end
    end)
    return l
end

-- « DSCF4961 » pour DSCF4961.RAF.
function Lightroom.nomCourt(nom)
    return (tostring(nom or ''):gsub('%.[^.]*$', ''))
end

-- « ★★★☆☆ » pour 3 (de 0 à 5 étoiles).
function Lightroom.etoiles(note)
    local n = math.max(0, math.min(5, math.floor(tonumber(note) or 0)))
    return string.rep('★', n) .. string.rep('☆', 5 - n)
end

-- La ligne de contexte jointe à chaque demande.
function Lightroom.contexte(info)
    if not info.active then
        return "[Lightroom : aucune photo active ni sélectionnée]"
    end
    local selection = info.selection == 1 and "1 photo" or (tostring(info.selection) .. " photos")
    return string.format("[Lightroom : photo active %s (%s) ; sélection : %s]", tostring(info.active.id), info.active.nom, selection)
end

-- État de la liaison avec le serveur : 'active', 'erreur' (ports tenus par un autre Lightroom,
-- par exemple) ou 'arretee', et l'erreur s'il y en a une.
function Lightroom.liaison()
    if not Liaison.actif then
        return 'arretee'
    elseif Liaison.erreur then
        return 'erreur', Liaison.erreur
    end
    return 'active'
end

-- Démarre la liaison si elle est arrêtée, ou la relance après une erreur (clic sur le voyant de
-- la fenêtre).
function Lightroom.demarrerLiaison()
    if Liaison.actif and Liaison.erreur then
        Liaison.arreter()
    end
    if not Liaison.actif then
        Liaison.demarrer()
    end
end

-- Mode de la liaison : 'proposer' (Proposer d'abord) ou 'appliquer'.
function Lightroom.mode()
    local ok, prefs = pcall(Preferences.lire)
    if ok and prefs and prefs.mode == 'proposer' then
        return 'proposer'
    end
    return 'appliquer'
end

function Lightroom.basculerMode()
    Preferences.lire().mode = Lightroom.mode() == 'proposer' and 'appliquer' or 'proposer'
    return Lightroom.mode()
end

-- Connexion de Claude Code (`claude auth status`) : { installe, connecte, forfait, texte }.
function Lightroom.etatClaude(claude)
    if not Fichiers.existe(claude) then
        return { installe = false, connecte = false, texte = "Claude Code introuvable" }
    end
    Fichiers.creerDossier(Chemins.temporaire())
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'auth-' .. Conversation.identifiant() .. '.json')
    LrTasks.execute('/usr/bin/env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_BASE_URL ' .. Texte.shell(claude)
        .. ' auth status > ' .. Texte.shell(sortie) .. ' 2>/dev/null')
    local texte = Fichiers.lire(sortie) or ''
    Fichiers.supprimer(sortie)
    local ok, json = pcall(Json.decode, texte)
    if not ok or type(json) ~= 'table' then
        return { installe = true, connecte = nil, texte = "Claude Code" }
    end
    if json.loggedIn ~= true then
        return { installe = true, connecte = false, texte = "Claude Code · non connecté" }
    end
    local forfait = json.authMethod == 'claude.ai'
    return { installe = true, connecte = true, forfait = forfait, texte = forfait and "Claude Code · forfait" or "Claude Code · " .. tostring(json.authMethod) }
end

-- Détail du voyant Écran quand le connecteur ne l'a pas dit : absent ; présent, mais sans réponse
-- lisible (coupé par l'alarme de 5 s, ou d'avant la 1.2 : il répond à --ecran par son aide, qui
-- n'est pas du JSON) ; ou sans écran lu.
Lightroom.ECRAN_INTROUVABLE = "L'écran n'a pas pu être lu : le connecteur MCP-Développeur est introuvable "
    .. "(réinstaller Développeur, ou régler son chemin dans le Gestionnaire de modules externes)."
Lightroom.ECRAN_ILLISIBLE = "L'écran n'a pas pu être lu : le connecteur MCP-Développeur n'a pas répondu dans les 5 s, "
    .. "ou il est plus ancien que la 1.2 (réinstaller Développeur)."
Lightroom.ECRAN_AUCUN = "Le connecteur MCP-Développeur n'a lu aucun écran (session sans écran ?)."

-- L'écran principal du Mac et son profil de couleur, lus par le connecteur (`mcp-developpeur
-- --ecran`, une ligne JSON, cinq secondes au plus) : macOS seul connaît l'écran. Rend
-- { lu, texte, etat, detail } (Lightroom.decrireEcran). Un connecteur absent ou plus ancien, ou une
-- commande en échec, laisse le voyant gris, sans erreur (la suite de Fenetre.verifier passe).
function Lightroom.etatEcran(connecteur)
    if not Fichiers.existe(connecteur) then
        local ecran = Lightroom.decrireEcran(nil)
        ecran.detail = Lightroom.ECRAN_INTROUVABLE
        return ecran
    end
    local lu, texte = LrTasks.pcall(function()
        Fichiers.creerDossier(Chemins.temporaire())
        local sortie = LrPathUtils.child(Chemins.temporaire(), 'ecran-' .. Conversation.identifiant() .. '.json')
        LrTasks.execute("/usr/bin/perl -e 'alarm 5; exec @ARGV' " .. Texte.shell(connecteur) .. ' --ecran > ' .. Texte.shell(sortie) .. ' 2>/dev/null')
        local reponse = Fichiers.lire(sortie) or ''
        Fichiers.supprimer(sortie)
        return reponse
    end)
    local ok, json = pcall(Json.decode, lu and texte or '')
    return Lightroom.decrireEcran(ok and json or nil)
end

-- Le voyant Écran d'après la réponse du connecteur : { lu, texte, etat, detail }, une table neuve
-- de textes seulement (rien de relu par Json.decode n'est posé dans Lightroom). `mesure` vrai :
-- étalonné (vert) ; faux : non étalonné (orange) ; absente (null efface la clé) : « étalonné ? »
-- (gris). Sans réponse lisible : « Écran », gris, et pourquoi dans le détail.
function Lightroom.decrireEcran(json)
    local principal = type(json) == 'table' and json.principal or nil
    if type(principal) ~= 'table' then
        local aucun = type(json) == 'table' and json.lu == false
        return { lu = false, texte = "Écran", etat = 'neutre', detail = aucun and Lightroom.ECRAN_AUCUN or Lightroom.ECRAN_ILLISIBLE }
    end
    local ecran = { lu = true }
    if principal.mesure == true then
        ecran.texte, ecran.etat = "Écran · étalonné", 'ok'
    elseif principal.mesure == false then
        ecran.texte, ecran.etat = "Écran · non étalonné", 'attention'
    else
        ecran.texte, ecran.etat = "Écran · étalonné ?", 'neutre'
    end
    if type(json.detail) == 'string' and json.detail ~= '' then
        ecran.detail = json.detail
    elseif type(principal.texte) == 'string' and principal.texte ~= '' then
        ecran.detail = principal.texte
    else
        ecran.detail = ecran.texte
    end
    return ecran
end

-- Je le fais (1.3) ---------------------------------------------------------------------------

-- Les réglages de la liste « à faire » dont la valeur de départ (`avant` du connecteur) n'est pas
-- une valeur relue de la photo : un nom de version, de paramètre prédéfini ou d'objectif, « non »
-- pour un calcul automatique, des repères comptés. Ils ne se cochent pas.
Lightroom.NON_SUIVIS = {
    ProcessVersion = true, Preset = true, AutoTone = true, AutoGrayscaleMix = true, LensProfileName = true,
    UprightFourSegments = true, UprightTransform = true,
}

-- Les valeurs des réglages `cles` (noms du connecteur) dans `reglages` (getDevelopSettings),
-- lues comme le module les décrit dans ses changements, pour les comparer à `avant` : la balance
-- d'un JPEG sous IncrementalTemperature et IncrementalTint (Reglages.cleReelle), le profil par son
-- nom (Reglages.nomProfil : la Look s'il y en a une), un nombre absent par sa valeur par défaut
-- et un booléen (ConvertToGrayscale) en 0 ou 1 (Reglages.valeurActuelle, comme `avant`), une table
-- (courbe, couleurs ponctuelles, flou d'objectif) par son résumé (Reglages.resume), avec sa
-- signature (son JSON, clés triées) pour voir un changement que le résumé ne montre pas. Rend
-- valeurs et signatures, deux tables neuves ; un réglage de Lightroom.NON_SUIVIS n'y est pas.
function Lightroom.lireValeurs(reglages, cles, raw)
    local Reglages = require 'Reglages'
    local valeurs, signatures = {}, {}
    for _, cle in ipairs(cles or {}) do
        if not Lightroom.NON_SUIVIS[cle] then
            local reelle = Reglages.cleReelle(cle, raw)
            local brute = reglages[reelle]
            if cle == 'CameraProfile' then
                valeurs[cle] = Reglages.nomProfil(reglages)
            elseif type(brute) == 'table' then
                valeurs[cle] = Reglages.resume(cle, brute)
                local ok, json = pcall(Json.encode, brute)
                signatures[cle] = ok and json or nil
            elseif type(brute) == 'string' then
                valeurs[cle] = brute
            elseif brute == nil and type(Reglages.resume(cle, nil)) == 'string' then
                -- Une table absente (courbe linéaire, aucune couleur ponctuelle) : son résumé, sans
                -- signature (une courbe linéaire écrite ensuite n'a pas changé).
                valeurs[cle] = Reglages.resume(cle, nil)
            else
                valeurs[cle] = Reglages.valeurActuelle(reglages, reelle)
            end
        end
    end
    return valeurs, signatures
end

-- Les valeurs actuelles des réglages `cles` de la photo `id` (Lightroom.lireValeurs, d'après
-- getDevelopSettings) : ce que Dany a déjà fait d'un exercice « Je le fais », relu toutes les 2 s
-- par la fenêtre. Deux tables vides si la photo ne se lit pas. À appeler depuis une tâche.
function Lightroom.valeurs(id, cles)
    local valeurs, signatures = {}, {}
    LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getPhotoByLocalId(tonumber(id))
        local reglages = photo and photo:getDevelopSettings()
        if type(reglages) == 'table' then
            valeurs, signatures = Lightroom.lireValeurs(reglages, cles, require('Reglages').estRaw(photo, reglages))
        end
    end)
    return valeurs, signatures
end

-- Sélectionne une photo du catalogue par son identifiant (numéros cités par Claude).
function Lightroom.selectionner(id)
    LrTasks.pcall(function()
        local catalogue = LrApplication.activeCatalog()
        local photo = catalogue:getPhotoByLocalId(tonumber(id))
        if photo then
            catalogue:setSelectedPhotos(photo, {})
        end
    end)
end

return Lightroom
