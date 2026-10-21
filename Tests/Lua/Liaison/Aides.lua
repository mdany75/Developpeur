-- Aides.lua : les aides communes des essais de la liaison (tests.lua et chaque essais-*.lua de
-- Tests/Lua/Liaison) : test, egal, proche, echoue, contient, ligne, les photos d'essai (photoRaw,
-- photoJpeg, photoFuji), appliquer, le jeton JETON et le bilan. Chaque fichier règle d'abord
-- package.path (le module, puis ce dossier), puis :
--
--   local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
--   package.path = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/?.lua;' .. dossierTests .. '?.lua;' .. package.path
--   local A = require 'Aides'
--
-- Avant chaque test, la simulation repart de zéro (S.reinitialiser), la liaison aussi, et chaque
-- module à registre chargé est remis à zéro par son crochet (A.remiseAZero) : Notation, Carnet et
-- Etapes (oublier, plus d'abonnés), et tout module nommé ensuite par un essai. Un module pas
-- encore chargé, ou qui n'existe pas encore, est sauté.

local A = {}

local S = require 'Simulation'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'

A.S = S
A.reussis, A.echecs = 0, 0

-- Jeton de la liaison pendant les essais (liaison fermée, 1.2) : jamais celui du vrai fichier.
A.JETON = string.rep('ab', 32)

-- Crochets de remise à zéro --------------------------------------------------------------------

local ordre, crochets = {}, {}

-- Remise à zéro par défaut d'un module à registre : oublier (relu du fichier ensuite), et plus
-- d'abonnés.
local function parDefaut(module)
    if type(module.oublier) == 'function' then
        module.oublier()
    end
    if type(module.observateurs) == 'table' then
        module.observateurs = {}
    end
end

-- Pose (ou remplace) le crochet du module `nom`, appelé avant chaque test avec le module chargé
-- (package.loaded) ; sans fonction, la remise par défaut.
function A.remiseAZero(nom, fonction)
    if not crochets[nom] then
        ordre[#ordre + 1] = nom
    end
    crochets[nom] = fonction or parDefaut
end

A.remiseAZero('Notation')
A.remiseAZero('Carnet')
-- Etapes (avant/après de chaque étape, 1.3) : remis à zéro dès qu'il existe et qu'il est chargé,
-- par son oublier.
A.remiseAZero('Etapes')

-- Remet tout à zéro : la simulation, la liaison, puis chaque module à registre chargé.
function A.remettre()
    S.reinitialiser()
    Liaison.pause = false
    Liaison.journal = {}
    Liaison.jeton = A.JETON
    Liaison.derniersRefus = {}
    Liaison.refus = 0
    for _, nom in ipairs(ordre) do
        local module = package.loaded[nom]
        if type(module) == 'table' then
            crochets[nom](module)
        end
    end
end

-- Tests -----------------------------------------------------------------------------------------

function A.test(nom, fonction)
    A.remettre()
    local ok, erreur = pcall(fonction)
    if ok then
        A.reussis = A.reussis + 1
    else
        A.echecs = A.echecs + 1
        print("ÉCHEC  " .. nom .. " : " .. tostring(erreur))
    end
end

-- Le bilan, puis la sortie (en échec s'il y en a un).
function A.bilan()
    print(string.format("%d tests réussis, %d en échec", A.reussis, A.echecs))
    os.exit(A.echecs == 0 and 0 or 1)
end

function A.egal(obtenu, attendu, message)
    if obtenu ~= attendu then
        error(string.format("%s : attendu %s, obtenu %s", message or "valeur", tostring(attendu), tostring(obtenu)), 2)
    end
end

function A.proche(obtenu, attendu, message)
    if type(obtenu) ~= 'number' or math.abs(obtenu - attendu) > 1e-9 then
        error(string.format("%s : attendu %s, obtenu %s", message or "nombre", tostring(attendu), tostring(obtenu)), 2)
    end
end

function A.echoue(fonction, morceau)
    local ok, erreur = pcall(fonction)
    if ok then
        error("une erreur était attendue", 2)
    end
    if morceau and not tostring(erreur):find(morceau, 1, true) then
        error("erreur inattendue : " .. tostring(erreur), 2)
    end
end

function A.contient(liste, morceau)
    for _, texte in ipairs(liste) do
        if tostring(texte):find(morceau, 1, true) then
            return true
        end
    end
    return false
end

-- Une ligne du serveur pour Liaison.recevoir : l'objet en JSON, avec le jeton de la liaison (JETON
-- par défaut, un autre texte, ou false pour l'omettre).
function A.ligne(objet, jeton)
    if jeton == nil then
        objet.jeton = A.JETON
    elseif jeton then
        objet.jeton = jeton
    end
    return Json.encode(objet)
end

-- Photos d'essai ------------------------------------------------------------------

function A.photoRaw()
    return S.Photo(1, {
        Temperature = 5200, Tint = 5, WhiteBalance = 'As Shot',
        Exposure2012 = 0, Highlights2012 = 0, Shadows2012 = 0, Saturation = 0, Vibrance = 0,
        SharpenRadius = 1, ProcessVersion = '15.4',
    }, { fileName = 'DSC_0412.NEF', fileFormat = 'RAW', cameraModel = 'NIKON Z 6' })
end

function A.photoJpeg()
    return S.Photo(2, { IncrementalTemperature = 0, IncrementalTint = 0, WhiteBalance = 'As Shot', Exposure2012 = 0 },
        { fileName = 'IMG_0001.JPG', fileFormat = 'JPG' })
end

-- RAW Fujifilm avec le profil Adobe Color (une « Look » posée sur Adobe Standard), comme à l'import.
A.ADOBE_COLOR = {
    Name = 'Adobe Color', Amount = 1, UUID = 'B952C231111CD8E0ECCF14B86BAA7077',
    Group = { ['x-default'] = 'Profiles' },
    Parameters = { CameraProfile = 'Adobe Standard', ToneCurvePV2012 = { 0, 0, 22, 16, 255, 255 } },
}

function A.photoFuji()
    return S.Photo(4, {
        Temperature = 5350, Tint = 19, WhiteBalance = 'As Shot', Exposure2012 = 0, Vibrance = 0,
        ConvertToGrayscale = false, CameraProfile = 'Adobe Standard', Look = A.ADOBE_COLOR, PerspectiveScale = 100,
        ProcessVersion = '15.4',
    }, { fileName = 'XH2S0320.RAF', copyName = 'Copie 1', fileFormat = 'RAW', cameraMake = 'FUJIFILM',
        cameraModel = 'X-H2S', croppedDimensions = '6240 x 4160' },
    { dimensions = { width = 6240, height = 4160 } })
end

function A.appliquer(params)
    params.etape = params.etape or 'passe 1'
    return Commandes.executer('appliquer', params)
end

return A
