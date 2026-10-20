-- Recalage.lua : la géométrie d'une photo (profil d'objectif, Upright, perspective), son
-- empreinte, et la grille de recalage que le serveur calcule pour elle (Recalage.swift).
--
-- Constaté dans Lightroom Classic 15.6 : Lightroom range les positions des masques, des taches et
-- des yeux rouges dans l'image d'avant la correction de profil d'objectif, Upright et la
-- perspective (jusqu'à 26 px au bord d'un RAW de 6240 px, XF16-55 à 20 mm ; 0 px une fois le
-- profil coupé), alors que Claude les donne dans l'image corrigée. Le serveur compare deux rendus
-- non recadrés de la photo (commande « geometrie ») : l'un tel quel, l'autre sans ces
-- corrections ; il en tire une grille (Recalage.swift) que les commandes de masques et de taches
-- reçoivent dans `recalages`, par photo, avec l'empreinte de la géométrie qu'elle suppose.

local Geometrie = require 'Geometrie'
local Json = require 'Json'
local Photos = require 'Photos'
local Reglages = require 'Reglages'

local brut, dimensionsAffichees = Photos.brut, Photos.dimensionsAffichees
local orientationAffichage = Photos.orientationAffichage
local pourLightroom, valeurNumerique = Reglages.pourLightroom, Reglages.valeurNumerique

local Recalage = {}

-- Une transformation (Upright, perspective, distorsion) déforme l'image après coup : les
-- positions calculées sur l'image non transformée peuvent être décalées.
local function transformationActive(actuels)
    for _, cle in ipairs({ 'PerspectiveUpright', 'PerspectiveVertical', 'PerspectiveHorizontal', 'PerspectiveRotate',
        'PerspectiveAspect', 'PerspectiveX', 'PerspectiveY', 'LensManualDistortionAmount' }) do
        if (valeurNumerique(actuels[cle]) or 0) ~= 0 then
            return true
        end
    end
    return (valeurNumerique(actuels.PerspectiveScale) or 100) ~= 100
end

-- Ce qui ramène l'image à celle d'avant les corrections géométriques.
local NEUTRE_GEOMETRIE = {
    LensProfileEnable = 0, LensManualDistortionAmount = 0, PerspectiveUpright = 0, PerspectiveVertical = 0,
    PerspectiveHorizontal = 0, PerspectiveRotate = 0, PerspectiveAspect = 0, PerspectiveScale = 100,
    PerspectiveX = 0, PerspectiveY = 0,
}

-- Une correction géométrique déplace-t-elle l'image ? Le profil d'objectif, actif sur la plupart
-- des RAW, corrige la distorsion sauf si son intensité est à zéro.
local function geometrieActive(actuels)
    if (valeurNumerique(actuels.LensProfileEnable) or 0) ~= 0
        and (valeurNumerique(actuels.LensProfileDistortionScale) or 100) ~= 0 then
        return true
    end
    return transformationActive(actuels)
end

-- Empreinte de ce qui décide du recalage : dimensions, orientation, réglages du profil d'objectif,
-- d'Upright et de la perspective (le recadrage n'y est pas : la grille porte sur l'image entière).
-- Les matrices UprightTransform_* n'y sont pas non plus : Lightroom les calcule après coup, d'après
-- les autres réglages, et elles changeraient l'empreinte entre l'écriture et le rendu. Une valeur
-- neutre compte comme absente : les rendus du recalage la posent en remettant la photo.
local function empreinteGeometrie(photo, actuels)
    local largeur, hauteur = dimensionsAffichees(photo)
    local morceaux = { tostring(largeur), tostring(hauteur), tostring(brut(photo, 'orientation')) }
    local cles = {}
    for cle, valeur in pairs(actuels) do
        if (cle:match('^LensProfile') or cle:match('^LensManual') or cle:match('^Perspective') or cle:match('^Upright'))
            and not cle:match('^UprightTransform')
            and (NEUTRE_GEOMETRIE[cle] == nil or valeurNumerique(valeur) ~= NEUTRE_GEOMETRIE[cle]) then
            cles[#cles + 1] = cle
        end
    end
    table.sort(cles)
    for _, cle in ipairs(cles) do
        local valeur = actuels[cle]
        morceaux[#morceaux + 1] = cle .. '=' .. (type(valeur) == 'table' and Json.encode(pourLightroom(valeur)) or tostring(valeur))
    end
    local texte = table.concat(morceaux, ';')
    -- Deux hachages de 32 bits (exacts en nombres flottants) : de quoi distinguer deux géométries.
    local a, b = 5381, 52711
    for i = 1, #texte do
        local octet = texte:byte(i)
        a = (a * 33 + octet) % 4294967296
        b = (b * 31 + octet * 7) % 4294967296
    end
    return string.format('%08x%08x', a, b)
end

-- Grille du serveur pour la géométrie actuelle de la photo, ou nil.
local function grilleValide(photo, actuels, params)
    if not geometrieActive(actuels) or type(params.recalages) ~= 'table' then
        return nil
    end
    local r = params.recalages[tostring(photo.localIdentifier)]
    if type(r) == 'table' and r.empreinte == empreinteGeometrie(photo, actuels) then
        return r
    end
    return nil
end

-- Repère des positions de l'aperçu pour cette photo (voir Geometrie.lua), recalé sur la
-- géométrie quand le serveur en a donné la grille pour cette géométrie-là.
local function contexteGeometrie(photo, plan, params)
    local largeur, hauteur = dimensionsAffichees(photo)
    local orientation = orientationAffichage(photo, plan.raw, largeur, hauteur)
    return Geometrie.contexte(largeur, hauteur, orientation, plan.actuels, grilleValide(photo, plan.actuels, params))
end

-- Partie de l'image qui montre la photo quand Upright, la perspective ou la distorsion manuelle
-- sont actifs, d'après la grille de recalage du serveur. Seuls ceux-là laissent des coins vides :
-- le profil d'objectif redimensionne l'image pour les éviter.
local function zoneImage(photo, actuels, params)
    if not transformationActive(actuels) then
        return nil
    end
    return Geometrie.zone(grilleValide(photo, actuels, params))
end

Recalage.contexteGeometrie = contexteGeometrie
Recalage.empreinteGeometrie = empreinteGeometrie
Recalage.geometrieActive = geometrieActive
Recalage.NEUTRE_GEOMETRIE = NEUTRE_GEOMETRIE
Recalage.transformationActive = transformationActive
Recalage.zoneImage = zoneImage

return Recalage
