-- Conversions.lua : ce que Lightroom fait par ses propres commandes, hors d'une écriture, et que la
-- mémoire de Claude sait défaire : la rotation d'un quart de tour (photo:rotateLeft et rotateRight,
-- SDK 7.4). Relevé dans le code de Lightroom Classic 15.6 (LrPhoto) : la commande ag.library.rotate
-- de la Bibliothèque, qui change l'orientation de la photo (getRawMetadata('orientation')), pas ses
-- réglages. La mémoire la garde sous la clé Rotation (quarts de tour à refaire pour revenir, dans
-- le sens horaire), qui n'est pas un réglage.
--
-- Une photo en version de processus 1 ou 2 (2003, 2010) ne se met pas à jour par un module
-- (constaté dans Lightroom Classic 15.6) : LrDevelopController.setProcessVersion n'y fait rien (il
-- compare le nom demandé, « Version 6 », aux noms de kProcessVersionHistoryNames, des textes à
-- traduire (ZSTR) qui ne lui sont jamais égaux), et ProcessVersion posé par applyDevelopSettings ou
-- par un paramètre prédéfini ne convertit pas les curseurs, comme le fait le menu Paramètres ›
-- Mettre à jour vers la version de processus actuelle (Luminosité +15 de 2010 : Exposition 2012
-- +0,3 par le menu, 0 par un paramètre prédéfini). Plans.preparerVersion le dit.

local LrDate = import 'LrDate'
local LrTasks = import 'LrTasks'

local Photos = require 'Photos'

local brut = Photos.brut

local Conversions = {}

local function echouer(message)
    error(message, 0)
end

-- Rotation -------------------------------------------------------------------------

-- Orientation après un quart de tour dans le sens horaire (rotateRight) : AB → BC → CD → DA. « DA »
-- montre le bord droit du fichier en haut (constaté, voir Recadrage) : c'est un quart de tour dans le
-- sens antihoraire depuis AB.
local SUIVANTE = { AB = 'BC', BC = 'CD', CD = 'DA', DA = 'AB' }
local DUREE_ROTATION = 5

local function apresQuarts(orientation, quarts)
    for _ = 1, quarts % 4 do
        orientation = SUIVANTE[orientation] or orientation
    end
    return orientation
end

-- Tourne la photo de `quarts` quarts de tour dans le sens horaire (3 = un quart vers la gauche) et
-- attend que Lightroom l'ait rangé. Renvoie vrai, ou faux et la raison.
local function tourner(photo, quarts)
    quarts = math.floor(tonumber(quarts) or 0) % 4
    if quarts == 0 then
        return true
    end
    local depart = brut(photo, 'orientation')
    local voulue = apresQuarts(depart, quarts)
    local fonction, fois = 'rotateRight', quarts
    if quarts == 3 then
        fonction, fois = 'rotateLeft', 1
    end
    local ok, methode = pcall(function() return photo[fonction] end)
    if not ok or type(methode) ~= 'function' then
        return false, "cette version de Lightroom n'offre pas la rotation aux modules (SDK 7.4)"
    end
    for _ = 1, fois do
        local fait, erreur = LrTasks.pcall(methode, photo)
        if not fait then
            return false, tostring(erreur)
        end
    end
    local debut = LrDate.currentTime()
    while brut(photo, 'orientation') ~= voulue and LrDate.currentTime() - debut < DUREE_ROTATION do
        LrTasks.sleep(0.2)
    end
    if brut(photo, 'orientation') ~= voulue then
        return false, string.format("Lightroom n'a pas tourné la photo (orientation %s, %s attendue)", tostring(brut(photo, 'orientation')), tostring(voulue))
    end
    return true
end

-- quarts demandés par la commande : 'droite' 1, 'demi' 2, 'gauche' 3.
local QUARTS = { droite = 1, demi = 2, gauche = 3 }

-- Tourne une photo avant sa retouche (le plan se prépare ensuite sur la nouvelle orientation).
-- Renvoie {quarts, avant, apres}. Erreur si Lightroom ne tourne pas la photo.
function Conversions.tournerPhoto(photo, sens)
    local quarts = QUARTS[tostring(sens)]
    if not quarts then
        echouer("Rotation inconnue : " .. tostring(sens) .. " (gauche, droite ou demi).")
    end
    local avant = brut(photo, 'orientation')
    local ok, raison = tourner(photo, quarts)
    if not ok then
        echouer("Rotation impossible : " .. tostring(raison) .. ".")
    end
    return { quarts = quarts, avant = avant, apres = brut(photo, 'orientation') }
end

-- Note sur le plan ce qu'il faut pour revenir (clé Rotation de l'étape) et le changement.
function Conversions.noterRotation(plan, rotation)
    plan.avant.Rotation = { quarts = (4 - rotation.quarts) % 4 }
    plan.horsEcriture = true
    plan.changements[#plan.changements + 1] = { cle = 'Rotation', avant = tostring(rotation.avant), apres = tostring(rotation.apres) }
end

-- Remet la rotation d'une étape (annulation, retour à l'origine).
function Conversions.remettreRotation(photo, voulue)
    local quarts = type(voulue) == 'table' and tonumber(voulue.quarts) or 0
    local ok, raison = tourner(photo, quarts)
    if not ok then
        echouer("Lightroom n'a pas remis l'orientation de la photo : " .. tostring(raison) .. ".")
    end
end

return Conversions
