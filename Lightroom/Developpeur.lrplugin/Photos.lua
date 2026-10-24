-- Photos.lua : les photos que vise une commande, leur description, et la mémoire que le module
-- garde de ce que Claude y a changé.
--
-- Sans « photo » ni « photos » ni « selection », une commande vise la photo active.
--
-- Ce que Claude a changé est gardé dans des métadonnées privées du module (Metadonnees.lua) :
--   avantClaude   : valeur d'origine de chaque réglage touché (JSON objet) ; la clé Amelioration
--                   y garde l'état du débruitage, des détails bruts et de la super résolution
--   etapesClaude  : les 20 dernières retouches, avec les valeurs qu'elles ont remplacées (JSON
--                   tableau de { id, nom, avant, le } ; id et le depuis la 1.3, par
--                   Ecriture.nouvelleEtape : une étape plus ancienne n'a que nom et avant)
--   journalClaude : les 200 dernières entrées du journal (date, étape, etape_id depuis la 1.3,
--                   type, raison, changements ; une annulation porte l'etape_id de l'étape
--                   défaite, un retour à l'origine les etape_ids de toutes)
--   proprietaireMemoire : uuid de la photo à qui appartiennent ces champs (voir « Propriétaire
--                   de la mémoire »)

local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local Json = require 'Json'

local Photos = {}

local function echouer(message)
    error(message, 0)
end

local MAX_PHOTOS = 500

local function catalogue()
    return LrApplication.activeCatalog()
end

-- Photos visées -----------------------------------------------------------------

local function photoParId(id)
    local numero = tonumber(id)
    local cat = catalogue()
    local photo
    if numero then
        local ok, trouvee = LrTasks.pcall(cat.getPhotoByLocalId, cat, numero)
        if ok and trouvee then
            -- Avec l'identifiant d'une copie virtuelle supprimée, la suite échouait sur « attempt
            -- to index a nil value » : on vérifie que la photo répond avant de s'en servir.
            local lu, uuid = LrTasks.pcall(function() return trouvee:getRawMetadata('uuid') end)
            if lu and type(uuid) == 'string' and uuid ~= '' then
                photo = trouvee
            end
        end
        if not photo then
            -- getPhotoByLocalId n'est pas documentée : on cherche aussi parmi les photos visées.
            for _, candidate in ipairs(cat:getTargetPhotos()) do
                if candidate.localIdentifier == numero then
                    photo = candidate
                    break
                end
            end
        end
    end
    if not photo then
        echouer("Aucune photo n'a l'identifiant " .. tostring(id) .. " dans le catalogue ouvert.")
    end
    return photo
end

local function photoActive()
    local photo = catalogue():getTargetPhoto()
    if not photo then
        echouer("Aucune photo active dans Lightroom : sélectionner une photo dans la Bibliothèque ou le Développement.")
    end
    return photo
end

local function photoVisee(params)
    if params.photo then
        return photoParId(params.photo)
    end
    return photoActive()
end

local function photosVisees(params)
    if type(params.photos) == 'table' and #params.photos > 0 then
        local liste = {}
        for _, id in ipairs(params.photos) do
            liste[#liste + 1] = photoParId(id)
        end
        return liste
    end
    if params.selection then
        local liste = catalogue():getTargetPhotos()
        if #liste == 0 then
            echouer("Aucune photo sélectionnée dans Lightroom.")
        end
        if #liste > MAX_PHOTOS then
            echouer(string.format("%d photos visées : c'est plus que la limite de %d par commande. Réduire la sélection.", #liste, MAX_PHOTOS))
        end
        return liste
    end
    return { photoActive() }
end

local function meta(photo, cle)
    local ok, valeur = LrTasks.pcall(photo.getFormattedMetadata, photo, cle)
    if ok and valeur ~= nil and valeur ~= '' then
        return valeur
    end
    return nil
end

local function brut(photo, cle)
    local ok, valeur = LrTasks.pcall(photo.getRawMetadata, photo, cle)
    if ok then
        return valeur
    end
    return nil
end

-- Mémoire de Claude ---------------------------------------------------------------

-- Propriétaire de la mémoire. Constaté dans Lightroom Classic 15.6 : une copie virtuelle reçoit
-- les champs du module de son original, et croyait avoir ses retouches (« Retouchée par Claude »
-- avant toute retouche, comparaison avec l'état d'avant Claude de l'original). La mémoire porte
-- donc l'uuid de sa photo (proprietaireMemoire) ; celle d'une autre photo vaut une mémoire vide,
-- et la prochaine écriture la remplace.
local CHAMPS_MEMOIRE = { 'avantClaude', 'etapesClaude', 'journalClaude', 'retoucheeParClaude', 'variantesClaude', 'apresClaude' }

local function premiereEntree(photo)
    local texte = photo:getPropertyForPlugin(_PLUGIN, 'journalClaude')
    local ok, journal = pcall(Json.decode, texte or '')
    if ok and type(journal) == 'table' and type(journal[1]) == 'table' then
        return Json.encode(journal[1])
    end
    return nil
end

local function memoireEtrangere(photo)
    local uuid = brut(photo, 'uuid')
    if type(uuid) ~= 'string' or uuid == '' then
        return false
    end
    local proprietaire = photo:getPropertyForPlugin(_PLUGIN, 'proprietaireMemoire')
    if type(proprietaire) == 'string' and proprietaire ~= '' then
        return proprietaire ~= uuid
    end
    -- Mémoire sans propriétaire, écrite avant ce champ. Sur un original, c'est la sienne : elle
    -- est lue comme avant, et rattachée à lui à la prochaine écriture. Une copie virtuelle a pu
    -- la recevoir de son original : c'est le cas si son journal commence par la même entrée que
    -- celui de l'original (un journal ne fait que s'allonger, jusqu'à 200 entrées ; pour s'y
    -- tromper, il faudrait que Claude ait retouché la copie et l'original dans la même minute,
    -- avec les mêmes valeurs et la même raison).
    if brut(photo, 'isVirtualCopy') ~= true then
        return false
    end
    local original = brut(photo, 'masterPhoto')
    local entree = premiereEntree(photo)
    return entree ~= nil and original ~= nil and entree == premiereEntree(original)
end

local function lireChamp(photo, champ)
    if memoireEtrangere(photo) then
        return nil
    end
    return photo:getPropertyForPlugin(_PLUGIN, champ)
end

-- Photos déjà rattachées à leur mémoire dans l'écriture en cours. Dans une écriture, Lightroom
-- relit un champ du module avec sa valeur d'avant l'écriture (constaté par ses effets dans
-- Lightroom Classic 15.6, 20 octobre 2026) : sans cela, chaque champ gardé sur une copie qui avait
-- reçu la mémoire de son original relisait l'ancien propriétaire et effaçait les champs déjà
-- écrits, et seul le dernier restait. Ecriture la vide au début de chaque écriture.
local rattachees = {}

local function nouvelleEcriture()
    rattachees = {}
end

-- Écrit un champ de la mémoire (dans ecrire) et la rattache à la photo. La mémoire d'une autre
-- photo est d'abord effacée : les champs que l'écriture ne touche pas ne deviennent pas les siens.
local function garder(photo, champ, valeur)
    local uuid = brut(photo, 'uuid')
    if type(uuid) == 'string' and uuid ~= '' and rattachees[photo] ~= uuid
            and photo:getPropertyForPlugin(_PLUGIN, 'proprietaireMemoire') ~= uuid then
        if memoireEtrangere(photo) then
            for _, autre in ipairs(CHAMPS_MEMOIRE) do
                photo:setPropertyForPlugin(_PLUGIN, autre, nil)
            end
        end
        photo:setPropertyForPlugin(_PLUGIN, 'proprietaireMemoire', uuid)
        rattachees[photo] = uuid
    end
    photo:setPropertyForPlugin(_PLUGIN, champ, valeur)
end

local function lireJson(photo, champ, defaut)
    local texte = lireChamp(photo, champ)
    if type(texte) ~= 'string' or texte == '' then
        return defaut
    end
    local ok, valeur = pcall(Json.decode, texte)
    if ok and type(valeur) == 'table' then
        return valeur
    end
    return defaut
end

-- Description ---------------------------------------------------------------------

-- Drapeau (pickStatus : 1, 0 ou −1) et couleur du libellé, en mots. Un libellé hors du jeu de
-- libellés actif (colorNameForLabel ne lui donne pas de couleur) est rendu tel quel.
local NOMS_DRAPEAU = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetée' }
local NOMS_COULEUR = { red = 'rouge', yellow = 'jaune', green = 'vert', blue = 'bleu', purple = 'violet' }

local function drapeau(photo)
    return NOMS_DRAPEAU[tonumber(brut(photo, 'pickStatus')) or 0] or 'aucun'
end

local function libelle(photo)
    local couleur = NOMS_COULEUR[brut(photo, 'colorNameForLabel')]
    if couleur then
        return couleur
    end
    local texte = meta(photo, 'label')
    return texte and ("« " .. texte .. " »") or 'aucun'
end

local function nomFichier(photo)
    local nom = meta(photo, 'fileName') or ('photo ' .. tostring(photo.localIdentifier))
    local copie = meta(photo, 'copyName')
    if copie then
        nom = nom .. ' (' .. copie .. ')'
    end
    return nom
end

-- Description d'une photo. `f` lit une métadonnée formatée (nil si vide), `b` une métadonnée
-- brute, `retouchee` dit si Claude l'a retouchée : lues une à une (decrire), ou d'un coup pour
-- toute une liste (decrireTout).
local function decrireAvec(photo, detaille, f, b, retouchee)
    local nom = f('fileName') or ('photo ' .. tostring(photo.localIdentifier))
    local copie = f('copyName')
    if copie then
        nom = nom .. ' (' .. copie .. ')'
    end
    local d = { id = photo.localIdentifier, fichier = nom, copie_virtuelle = b('isVirtualCopy') == true }
    if detaille then
        d.appareil = f('cameraModel')
        d.objectif = f('lens')
        d.iso = f('isoSpeedRating')
        d.vitesse = f('shutterSpeed')
        d.ouverture = f('aperture')
        d.focale = f('focalLength')
        d.date = f('dateTimeOriginal')
        d.dimensions = f('dimensions')
        d.format = b('fileFormat')
        -- Une vidéo (1.3.5) : le tri, la série et la livraison la sautent et disent combien.
        if d.format == 'VIDEO' then d.video = true end
        d.note = b('rating')
        d.drapeau = NOMS_DRAPEAU[tonumber(b('pickStatus')) or 0] or 'aucun'
        local couleur = NOMS_COULEUR[b('colorNameForLabel')]
        local texte = f('label')
        d.libelle = couleur or (texte and ("« " .. texte .. " »")) or 'aucun'
        d.retouchee_par_claude = retouchee()
        -- Pile de Lightroom (empilage à la main, ou automatique par heure de prise de vue).
        if b('isInStackInFolder') == true then
            local dessus = b('topOfStackInFolderContainingPhoto')
            d.pile = {
                dessus = type(dessus) == 'table' and dessus.localIdentifier or photo.localIdentifier,
                position = tonumber(b('stackPositionInFolder')),
                photos = tonumber(b('countStackInFolderMembers')),
            }
        end
    end
    return d
end

-- La sensibilité ISO de la photo, en nombre (isoSpeedRating brut ; la description détaillée n'en
-- a que le texte formaté, « ISO 160 ») : nil si Lightroom ne la connaît pas. Relevé le 21 octobre
-- 2026 (Lightroom Classic 15.6, commande reglages : prise_de_vue.iso, tonumber de la valeur brute,
-- de 160 à 12 800 sur des RAF de X-H2S et de X-T20 et un JPEG de X-T20) ; la valeur brute elle-même,
-- un nombre dans le journal détaillé d'un RAF (160), constatée le 22 octobre 2026 par l'étape de la
-- leçon de la recette (1.3.1). La simulation la tient pour un nombre. Le carnet de progrès et la leçon
-- ne cherchent le bruit fort de la prise de vue qu'à un ISO élevé (Carnet.isoEleve du serveur).
local function sensibilite(photo)
    local iso = tonumber(brut(photo, 'isoSpeedRating'))
    if iso and iso > 0 and iso == iso and iso ~= math.huge then
        return iso
    end
    return nil
end

local function decrire(photo, detaille)
    return decrireAvec(photo, detaille,
        function(cle) return meta(photo, cle) end,
        function(cle) return brut(photo, cle) end,
        function() return lireChamp(photo, 'retoucheeParClaude') == 'oui' end)
end

local CLES_FORMATEES = { 'fileName', 'copyName', 'cameraModel', 'lens', 'isoSpeedRating', 'shutterSpeed', 'aperture',
    'focalLength', 'dateTimeOriginal', 'dimensions', 'label' }
local CLES_BRUTES = { 'isVirtualCopy', 'fileFormat', 'rating', 'pickStatus', 'colorNameForLabel', 'uuid', 'isInStackInFolder',
    'topOfStackInFolderContainingPhoto', 'stackPositionInFolder', 'countStackInFolderMembers' }

-- Descriptions détaillées d'une liste de photos, par trois lectures groupées du catalogue
-- (batchGetFormattedMetadata, batchGetRawMetadata, batchGetPropertyForPlugin, SDK 3.0) plutôt
-- qu'une vingtaine par photo. « Retouchée par Claude » ne compte que si la mémoire est celle de la
-- photo (proprietaireMemoire) ; une mémoire sans propriétaire se vérifie une à une (lireChamp).
-- Si une lecture groupée échoue, chaque photo se décrit une à une.
local function decrireTout(photos)
    local cat = catalogue()
    local ok1, formatees = LrTasks.pcall(cat.batchGetFormattedMetadata, cat, photos, CLES_FORMATEES)
    local ok2, brutes = LrTasks.pcall(cat.batchGetRawMetadata, cat, photos, CLES_BRUTES)
    local ok3, champs = LrTasks.pcall(cat.batchGetPropertyForPlugin, cat, photos, _PLUGIN, { 'retoucheeParClaude', 'proprietaireMemoire' })
    local liste = {}
    for i, photo in ipairs(photos) do
        local fp = ok1 and type(formatees) == 'table' and formatees[photo]
        local bp = ok2 and type(brutes) == 'table' and brutes[photo]
        local mp = ok3 and type(champs) == 'table' and champs[photo]
        if type(fp) == 'table' and type(bp) == 'table' and type(mp) == 'table' then
            liste[i] = decrireAvec(photo, true,
                function(cle)
                    local valeur = fp[cle]
                    if valeur == nil or valeur == '' then
                        return nil
                    end
                    return valeur
                end,
                function(cle) return bp[cle] end,
                function()
                    if mp.retoucheeParClaude ~= 'oui' then
                        return false
                    end
                    if type(mp.proprietaireMemoire) == 'string' and mp.proprietaireMemoire ~= '' then
                        return mp.proprietaireMemoire == bp.uuid
                    end
                    return lireChamp(photo, 'retoucheeParClaude') == 'oui'
                end)
        else
            liste[i] = decrire(photo, true)
        end
    end
    return liste
end

-- Exportée ------------------------------------------------------------------------

-- Exportée pour de bon : isExported (SDK 13.3), sauf si seuls les aperçus de Claude l'ont fait
-- passer à vrai (apercuSeulement). `champ` : la valeur du champ, si elle est déjà lue.
local function exportee(photo, isExported, champ)
    if isExported == nil then
        isExported = brut(photo, 'isExported')
    end
    if isExported ~= true then
        return false
    end
    if champ == nil then
        champ = photo:getPropertyForPlugin(_PLUGIN, 'apercuSeulement')
    end
    return champ ~= 'oui'
end

-- Original ------------------------------------------------------------------------

-- Constaté par la référence du SDK (2.0) : checkPhotoAvailability dit si Lightroom croit le fichier
-- original présent sur le disque. Faux : disque débranché, fichier déplacé ou renommé hors de
-- Lightroom (le point d'exclamation de la vignette).
local function originalAbsent(photo)
    local ok, present = LrTasks.pcall(photo.checkPhotoAvailability, photo)
    return ok and present == false
end

-- Aperçu dynamique de la photo (smartPreviewInfo) : Lightroom en rend et en exporte une photo dont
-- l'original manque, à 2560 px au plus de grand côté.
local function apercuDynamique(photo)
    local info = brut(photo, 'smartPreviewInfo')
    if type(info) ~= 'table' then
        return false
    end
    for _, valeur in pairs(info) do
        if valeur ~= nil and valeur ~= false and valeur ~= '' and valeur ~= 0 then
            return true
        end
    end
    return false
end

-- La raison d'un refus, en mots : quel fichier manque et ce qu'il faut faire.
local function raisonOriginalAbsent(photo, quoi)
    return string.format("%s : original introuvable (%s) ; disque débranché, ou fichier déplacé ou renommé hors de "
        .. "Lightroom (point d'exclamation sur la vignette). %s Rebrancher le disque, ou retrouver le fichier dans "
        .. "Lightroom (clic sur le point d'exclamation), puis recommencer.",
        nomFichier(photo), tostring(brut(photo, 'path') or '?'), quoi)
end

-- Refuse une commande qui a besoin de l'original (débruitage, reflets) s'il manque.
local function exigerOriginal(photo, quoi)
    if originalAbsent(photo) then
        echouer(raisonOriginalAbsent(photo, quoi))
    end
end

-- Dimensions de la photo telle qu'elle s'affiche, en pixels.
local function dimensionsAffichees(photo)
    local d = brut(photo, 'dimensions')
    if type(d) == 'table' and tonumber(d.width) and tonumber(d.height) then
        return tonumber(d.width), tonumber(d.height)
    end
    local largeur, hauteur = tostring(meta(photo, 'dimensions') or ''):match('(%d+)%D+(%d+)')
    return tonumber(largeur), tonumber(hauteur)
end

-- Orientation de la photo dans Lightroom ('AB', 'BC', 'CD' ou 'DA'), et si le SDK l'a donnée.
-- Sinon : un capteur est horizontal, donc un RAW qui s'affiche en hauteur a été tourné, le plus
-- souvent appareil tenu poignée en haut (DA).
local function orientationAffichage(photo, raw, largeur, hauteur)
    local orientation = brut(photo, 'orientation')
    if orientation == 'AB' or orientation == 'BC' or orientation == 'CD' or orientation == 'DA' then
        return orientation, true
    end
    if raw and largeur and hauteur and hauteur > largeur then
        return 'DA', false
    end
    return 'AB', false
end

Photos.brut = brut
Photos.catalogue = catalogue
Photos.apercuDynamique = apercuDynamique
Photos.decrire = decrire
Photos.decrireTout = decrireTout
Photos.exigerOriginal = exigerOriginal
Photos.exportee = exportee
Photos.originalAbsent = originalAbsent
Photos.raisonOriginalAbsent = raisonOriginalAbsent
Photos.dimensionsAffichees = dimensionsAffichees
Photos.garder = garder
Photos.nouvelleEcriture = nouvelleEcriture
Photos.libelle = libelle
Photos.lireJson = lireJson
Photos.meta = meta
Photos.nomFichier = nomFichier
Photos.orientationAffichage = orientationAffichage
Photos.photoParId = photoParId
Photos.photosVisees = photosVisees
Photos.photoVisee = photoVisee
Photos.sensibilite = sensibilite

return Photos
