-- Reglages.lua : les réglages de développement tels que Lightroom les range : valeurs par
-- défaut, clés d'un JPEG, comparaison, résumé lisible, lecture pour Claude.

local Json = require 'Json'
local Photos = require 'Photos'
local Recadrage = require 'Recadrage'

local brut, dimensionsAffichees, meta = Photos.brut, Photos.dimensionsAffichees, Photos.meta
local orientationAffichage = Photos.orientationAffichage

local Reglages = {}

-- Valeur d'un réglage de transformation, de recadrage ou de la courbe absent : Lightroom n'écrit pas
-- toujours ceux qui sont à leur valeur neutre (défauts de la courbe relevés dans Camera Raw,
-- Lightroom Classic 15.6).
local DEFAUTS = {
    PerspectiveUpright = 0, PerspectiveVertical = 0, PerspectiveHorizontal = 0, PerspectiveRotate = 0,
    PerspectiveAspect = 0, PerspectiveScale = 100, PerspectiveX = 0, PerspectiveY = 0, CropConstrainToWarp = 0,
    ParametricShadowSplit = 25, ParametricMidtoneSplit = 50, ParametricHighlightSplit = 75, CurveRefineSaturation = 100,
}
for cle, valeur in pairs(Recadrage.AUCUN) do
    DEFAUTS[cle] = valeur
end

local CLES_CADRE = { 'CropAngle', 'CropLeft', 'CropTop', 'CropRight', 'CropBottom' }

local CLES_COURBES = { 'ToneCurvePV2012', 'ToneCurvePV2012Red', 'ToneCurvePV2012Green', 'ToneCurvePV2012Blue' }
local COURBE_LINEAIRE = { 0, 0, 255, 255 }

local function estRaw(photo, actuels)
    local temperature = tonumber(actuels.Temperature)
    if temperature and temperature > 1000 then
        return true
    end
    if actuels.IncrementalTemperature ~= nil then
        return false
    end
    local format = brut(photo, 'fileFormat')
    return format == 'RAW' or format == 'DNG'
end

-- Pour un JPEG, un TIFF ou un HEIC, Lightroom range la balance des blancs dans
-- IncrementalTemperature et IncrementalTint (−100 à +100) ; Claude les voit sous les noms
-- Temperature et Tint, comme pour un RAW.
local function cleReelle(cle, raw)
    if not raw then
        if cle == 'Temperature' then
            return 'IncrementalTemperature'
        elseif cle == 'Tint' then
            return 'IncrementalTint'
        end
    end
    return cle
end

local function clesBalance(raw)
    return raw and { 'Temperature', 'Tint' } or { 'IncrementalTemperature', 'IncrementalTint' }
end

local function valeurNumerique(valeur)
    if type(valeur) == 'number' then
        return valeur
    elseif type(valeur) == 'boolean' then
        return valeur and 1 or 0
    end
    return tonumber(valeur)
end

local function valeurActuelle(actuels, cle)
    local valeur = valeurNumerique(actuels[cle])
    if valeur == nil then
        return DEFAUTS[cle]
    end
    return valeur
end

local function lookVide(look)
    return type(look) ~= 'table' or next(look) == nil
end

-- Même profil d'appareil, à la casse près. Constaté dans Lightroom Classic 15.6 : le nom se
-- cherche sans tenir compte de la casse, et Lightroom range sa propre orthographe (« Camera
-- MONOCHROME » devient « Camera Monochrome » sur un X-H2S) ; la ponctuation compte (« Camera PRO
-- Neg. Hi » n'y est pas, « Camera Pro Neg Hi » oui).
local function memeProfil(a, b)
    return type(a) == 'string' and type(b) == 'string' and a:lower() == b:lower()
end

-- Nom du profil tel que l'affiche Lightroom : celui de la « Look » (Adobe Color…) s'il y en a
-- une, sinon celui du profil d'appareil (Camera Velvia/Vivid…).
local function nomProfil(actuels)
    if not lookVide(actuels.Look) and type(actuels.Look.Name) == 'string' and actuels.Look.Name ~= '' then
        return actuels.Look.Name
    end
    return actuels.CameraProfile
end

-- Copie profonde à remettre à Lightroom : sans les null JSON (impossibles à appliquer) et sans
-- les métatables que Json.decode pose sur les tableaux. Une Look relue du JSON telle quelle a
-- bloqué applyDevelopSettings sans erreur, verrou d'écriture compris (Lightroom Classic 15.6).
local function pourLightroom(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local copie = {}
    for cle, element in pairs(valeur) do
        if element ~= Json.null then
            copie[cle] = pourLightroom(element)
        end
    end
    return copie
end

-- Réglages à donner à applyDevelopSettings quand ils posent un profil d'appareil : le profil
-- « manquant » de la photo est vidé. Constaté dans Lightroom Classic 15.6 : un nom de profil
-- qu'il ne trouve pas pour l'appareil (« Camera PRO Neg. Hi » sur un X-H2S) est remplacé par
-- Adobe Standard et rangé sous MissingCameraProfile (et son empreinte sous
-- MissingCameraProfileDigest), que getDevelopSettings ne montre pas ; tant qu'il y reste, tout
-- profil d'appareil posé ensuite retombe à Adobe Standard, même un nom valide. Renvoie une copie.
local function libererProfil(reglages)
    local copie = {}
    for cle, valeur in pairs(reglages) do
        copie[cle] = valeur
    end
    if copie.CameraProfile ~= nil then
        copie.MissingCameraProfile = ''
        copie.MissingCameraProfileDigest = ''
    end
    return copie
end

-- Égalité de deux valeurs de réglage, tables comprises.
local function egal(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then
        if type(a) == 'number' and type(b) == 'number' then
            return math.abs(a - b) < 1e-9
        end
        return a == b
    end
    for cle, valeur in pairs(a) do
        if not egal(valeur, b[cle]) then
            return false
        end
    end
    for cle in pairs(b) do
        if a[cle] == nil then
            return false
        end
    end
    return true
end

local function compter(liste)
    return type(liste) == 'table' and #liste or 0
end

local function pluriel(n, singulier, plurielTexte)
    return string.format('%d %s', n, n > 1 and plurielTexte or singulier)
end

-- Résumé lisible d'une valeur rangée en table, pour les changements, le suivi et le journal.
local function resume(cle, valeur)
    if cle == 'Look' then
        return lookVide(valeur) and "aucune" or tostring(valeur.Name)
    elseif cle == 'MaskGroupBasedCorrections' then
        return pluriel(compter(valeur), "masque", "masques")
    elseif cle == 'RetouchAreas' or cle == 'RetouchInfo' then
        return pluriel(compter(valeur), "tache", "taches")
    elseif cle == 'RedEyeInfo' then
        return pluriel(compter(valeur), "œil", "yeux")
    elseif cle == 'PointColors' then
        return pluriel(compter(valeur), "couleur", "couleurs")
    elseif cle == 'DepthBasedCorrections' then
        return pluriel(compter(valeur), "trait d'affinage", "traits d'affinage")
    elseif cle == 'FilterList' then
        -- Traitements calculés (débruitage, reflets, poussière…), par leur titre.
        local titres = {}
        local filtres = type(valeur) == 'table' and valeur.Filters
        for _, filtre in ipairs(type(filtres) == 'table' and filtres or {}) do
            local titre = tostring(filtre.Title or filtre.Name or "filtre")
            titres[#titres + 1] = titre:match('=(.+)$') or titre
        end
        return #titres > 0 and table.concat(titres, ", ") or "aucun traitement calculé"
    elseif cle == 'Rotation' then
        return type(valeur) == 'table' and (tostring(valeur.quarts or 0) .. " quart(s) de tour") or "aucune"
    elseif cle == 'LensBlur' then
        if type(valeur) ~= 'table' or valeur.Active ~= true then
            return "inactif"
        end
        return string.format("intensité %d, %s", tonumber(valeur.BlurAmount) or 0,
            valeur.FocalRangeSource == 1 and "mise au point sur le sujet" or ("zone nette " .. tostring(valeur.SubjectRange)))
    elseif cle == 'Bibliotheque' then
        -- Ce qu'un classement avait changé (pas un réglage) : note, drapeau, mots-clés…
        local noms = { note = "note", drapeau = "drapeau", libelle = "libellé", titre = "titre", legende = "légende",
            droits = "droits d'auteur", motsCles = "mots-clés", collections = "collections",
            iptc = "champs IPTC", gps = "position GPS" }
        local parties = {}
        for _, sous in ipairs({ 'note', 'drapeau', 'libelle', 'titre', 'legende', 'droits', 'motsCles', 'collections', 'iptc', 'gps' }) do
            if type(valeur) == 'table' and valeur[sous] ~= nil then
                parties[#parties + 1] = noms[sous]
            end
        end
        return #parties > 0 and table.concat(parties, ", ") or "aucun classement"
    elseif cle == 'Amelioration' then
        -- État du débruitage, des détails bruts et de la super résolution (pas un réglage).
        local parties = {}
        if type(valeur) == 'table' then
            if valeur.denoise == true then
                parties[#parties + 1] = "débruitage" .. (tonumber(valeur.denoiseAmount) and (" " .. valeur.denoiseAmount) or "")
            end
            if valeur.rawDetails == true then
                parties[#parties + 1] = "détails bruts"
            end
            if valeur.superRes == true then
                parties[#parties + 1] = "super résolution"
            end
        end
        return #parties > 0 and table.concat(parties, ", ") or "aucune amélioration"
    elseif cle == 'Suppression' then
        -- État de la suppression des reflets (pas un réglage).
        if type(valeur) == 'table' and valeur.reflets == true then
            return "reflets supprimés" .. (tonumber(valeur.intensite) and (" " .. valeur.intensite) or "")
        end
        return "reflets laissés"
    elseif cle:match('^ToneCurvePV2012') then
        if type(valeur) ~= 'table' or egal(valeur, COURBE_LINEAIRE) then
            return "linéaire"
        end
        return pluriel(math.floor(#valeur / 2), "point", "points")
    end
    if type(valeur) == 'table' then
        return "(table)"
    end
    return valeur
end

-- Traitements calculés par Lightroom que porte une photo, d'après FilterList (constaté dans
-- Lightroom Classic 15.6 : un filtre Name = 'Enhance', Title = '$$$/CRaw/Filter/Title/Denoise=Denoise',
-- un seul pour le débruitage et les détails bruts qui l'accompagnent).
local function filtresCalcules(reglages)
    local liste = Json.tableau()
    local filtres = type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
    for _, filtre in ipairs(type(filtres) == 'table' and filtres or {}) do
        local titre = tostring(filtre.Title or filtre.Name or "filtre")
        liste[#liste + 1] = titre:match('=(.+)$') or titre
    end
    return liste
end

-- Photo agrandie hors de Lightroom (agrandissement génératif de Camera Raw, que faisait l'ancien
-- connecteur) : un cadre qui sort de l'image. Le module n'agrandit pas ; cette garde protège
-- celles qui sont encore au catalogue. Constaté dans Lightroom Classic 15.6 sur un DNG
-- agrandi : CropLeft -0,1997, CropConstrainToUnitSquare 0, et l'agrandissement rangé dans
-- FilterList (FilterID 9). Un recadrage calculé par le module (de 0 à 1) le perd : CropLeft revenu
-- à 0,018 après crop.angle de 1° (constaté).
local function estAgrandie(reglages)
    if type(reglages) ~= 'table' then
        return false
    end
    if (tonumber(reglages.CropLeft) or 0) < 0 or (tonumber(reglages.CropTop) or 0) < 0
        or (tonumber(reglages.CropRight) or 1) > 1 or (tonumber(reglages.CropBottom) or 1) > 1 then
        return true
    end
    local filtres = type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
    for _, filtre in ipairs(type(filtres) == 'table' and filtres or {}) do
        if type(filtre) == 'table' and tonumber(filtre.FilterID) == 9 then
            return true
        end
    end
    return false
end

-- Courbe rangée à plat (x1, y1, x2, y2…) → liste de points [x, y].
local function points(courbe)
    local liste = Json.tableau()
    for i = 1, compter(courbe) - 1, 2 do
        liste[#liste + 1] = Json.tableau({ courbe[i], courbe[i + 1] })
    end
    return liste
end

local function lireReglages(photo, cles, details)
    local actuels = photo:getDevelopSettings()
    local raw = estRaw(photo, actuels)
    local largeur, hauteur = dimensionsAffichees(photo)
    local orientation, connue = orientationAffichage(photo, raw, largeur, hauteur)
    local valeurs = {}
    for _, cle in ipairs(cles or {}) do
        local valeur = valeurActuelle(actuels, cleReelle(cle, raw))
        if valeur ~= nil then
            valeurs[cle] = valeur
        end
    end
    local infos = {
        echelle_temperature = raw and "kelvins (RAW : 2000 à 50000)" or "relative (JPEG, TIFF : −100 à +100)",
        balance_des_blancs = actuels.WhiteBalance,
        version_processus = actuels.ProcessVersion,
        profil = nomProfil(actuels) or Json.null,
        appareil = { marque = meta(photo, 'cameraMake') or Json.null, modele = meta(photo, 'cameraModel') or Json.null },
        recadrage = {
            recadree = brut(photo, 'isCropped') == true,
            angle = valeurActuelle(actuels, 'CropAngle'),
            dimensions = meta(photo, 'croppedDimensions') or Json.null,
            orientation = orientation .. (connue and "" or " (supposée)"),
        },
    }
    if not lookVide(actuels.Look) and tonumber(actuels.Look.Amount) then
        infos.intensite_profil = math.floor(tonumber(actuels.Look.Amount) * 100 + 0.5)
    end
    -- Exposition à la prise de vue, en nombres (match_series par l'EXIF : « Reproduire toutes les
    -- expositions ») : ouverture (nombre f), vitesse (secondes), sensibilité ISO.
    local ouverture, vitesse, iso = tonumber(brut(photo, 'aperture')), tonumber(brut(photo, 'shutterSpeed')), tonumber(brut(photo, 'isoSpeedRating'))
    if ouverture and vitesse and iso then
        infos.prise_de_vue = { ouverture = ouverture, vitesse = vitesse, iso = iso }
    end
    if details then
        local courbes = {}
        for _, cle in ipairs(CLES_COURBES) do
            if type(actuels[cle]) == 'table' and not egal(actuels[cle], COURBE_LINEAIRE) then
                courbes[cle] = points(actuels[cle])
            end
        end
        infos.courbes_par_points = next(courbes) and courbes or "linéaires"
        local masques = Json.tableau()
        for _, correction in ipairs(type(actuels.MaskGroupBasedCorrections) == 'table' and actuels.MaskGroupBasedCorrections or {}) do
            local noms = Json.tableau()
            for _, m in ipairs(correction.CorrectionMasks or {}) do
                -- Mode d'un composant : voir Locaux.combiner.
                local nomComposant = tostring(m.MaskName or m.What)
                if tonumber(m.MaskBlendMode) == 1 then
                    nomComposant = nomComposant .. (m.MaskInverted == true and " (intersection)" or " (soustrait)")
                elseif m.MaskInverted == true then
                    nomComposant = nomComposant .. " (inversé)"
                end
                noms[#noms + 1] = nomComposant
            end
            local locaux = {}
            for cle, valeur in pairs(correction) do
                if type(cle) == 'string' and cle:match('^Local') and type(valeur) == 'number' and valeur ~= 0
                    and not (cle == 'LocalCurveRefineSaturation' and valeur == 100) then
                    locaux[cle] = valeur
                elseif type(cle) == 'string' and cle:match('^%u%l+Curve$') and type(valeur) == 'table'
                    and not (#valeur == 2 and valeur[1] == '0,0' and valeur[2] == '255,255') then
                    -- Courbe locale (MainCurve…), rangée en textes « x,y » ; { '0,0', '255,255' } : linéaire.
                    locaux[cle] = pluriel(#valeur, "point", "points")
                end
            end
            masques[#masques + 1] = {
                nom = correction.CorrectionName or "masque",
                composants = noms,
                actif = correction.CorrectionActive ~= false,
                intensite = correction.CorrectionAmount,
                reglages_locaux = locaux,
            }
        end
        infos.masques = masques
        infos.couleurs_ponctuelles = compter(actuels.PointColors)
        infos.taches = compter(actuels.RetouchAreas)
        infos.yeux_rouges = compter(actuels.RedEyeInfo)
        infos.flou_objectif = resume('LensBlur', actuels.LensBlur)
        infos.flou_objectif_affinage = compter(actuels.DepthBasedCorrections)
        infos.filtres_calcules = filtresCalcules(actuels)
    end
    return valeurs, infos
end

local function bornes(cle, plages, raw)
    if cle == 'Temperature' then
        if raw then return 2000, 50000 end
        return -100, 100
    elseif cle == 'Tint' then
        if raw then return -150, 150 end
        return -100, 100
    end
    local plage = plages[cle]
    if type(plage) == 'table' and tonumber(plage[1]) and tonumber(plage[2]) then
        return tonumber(plage[1]), tonumber(plage[2])
    end
    return -100, 100
end

-- Au centième pour l'exposition, au dixième pour le rayon de netteté et la rotation, à l'unité
-- sinon (diviser par le facteur évite 0.35000000000000003).
local function arrondir(cle, valeur)
    local facteur = 1
    if cle == 'Exposure2012' then
        facteur = 100
    elseif cle == 'SharpenRadius' or cle == 'PerspectiveRotate' then
        facteur = 10
    end
    return math.floor(valeur * facteur + 0.5) / facteur
end

-- Affichage dans la fenêtre de suivi : virgule décimale, sans décimale inutile.
local function afficher(valeur)
    if type(valeur) ~= 'number' then
        return tostring(valeur)
    end
    local texte
    if valeur == math.floor(valeur) then
        texte = string.format('%d', valeur)
    else
        texte = string.format('%.2f', valeur):gsub('0+$', ''):gsub('[.,]$', '')
    end
    return (texte:gsub('%.', ','))
end

-- Minuscules, lettres accentuées comprises (string.lower de Lua 5.1 ne touche pas à « É »).
local MAJUSCULES = {
    ['À'] = 'à', ['Â'] = 'â', ['Ä'] = 'ä', ['Ç'] = 'ç', ['É'] = 'é', ['È'] = 'è', ['Ê'] = 'ê', ['Ë'] = 'ë',
    ['Î'] = 'î', ['Ï'] = 'ï', ['Ô'] = 'ô', ['Ö'] = 'ö', ['Ù'] = 'ù', ['Û'] = 'û', ['Ü'] = 'ü', ['Œ'] = 'œ',
}

local function minuscules(texte)
    local resultat = tostring(texte):lower()
    for majuscule, minuscule in pairs(MAJUSCULES) do
        resultat = resultat:gsub(majuscule, minuscule)
    end
    return resultat
end

-- Réglages à remettre : une liste de taches vide ne suffit pas à les retirer (constaté :
-- RetouchAreas = {} est ignoré) ; Lightroom range aussi l'ancienne forme RetouchInfo.
local function aRemettre(reglages)
    if type(reglages.RetouchAreas) == 'table' and next(reglages.RetouchAreas) == nil then
        reglages.RetouchInfo = {}
    end
    return reglages
end

-- Rotation gardée dans la mémoire (clé Rotation, pas un réglage : voir Conversions.lua) : les quarts
-- de tour à refaire, dans le sens horaire, pour revenir. Dans l'état d'avant Claude, ceux de toutes
-- les étapes s'additionnent (retirer : une étape annulée en sort). nil : rien à refaire.
local function cumulerRotation(original, quarts, retirer)
    local deja = type(original) == 'table' and tonumber(original.quarts) or 0
    local total = (deja + (retirer and -1 or 1) * (tonumber(quarts) or 0)) % 4
    if total == 0 then
        return nil
    end
    return { quarts = total }
end

-- Réglages remis, pour la réponse à Claude : les tables se résument (nom de la Look, nombre de
-- masques, de points…).
local function resumer(reglages)
    local sortie = {}
    for cle, valeur in pairs(reglages) do
        if type(valeur) == 'table' then
            sortie[cle] = resume(cle, valeur)
        else
            sortie[cle] = valeur
        end
    end
    return sortie
end

Reglages.afficher = afficher
Reglages.aRemettre = aRemettre
Reglages.arrondir = arrondir
Reglages.bornes = bornes
Reglages.cleReelle = cleReelle
Reglages.cumulerRotation = cumulerRotation
Reglages.CLES_CADRE = CLES_CADRE
Reglages.CLES_COURBES = CLES_COURBES
Reglages.clesBalance = clesBalance
Reglages.COURBE_LINEAIRE = COURBE_LINEAIRE
Reglages.DEFAUTS = DEFAUTS
Reglages.egal = egal
Reglages.estAgrandie = estAgrandie
Reglages.estRaw = estRaw
Reglages.libererProfil = libererProfil
Reglages.lireReglages = lireReglages
Reglages.lookVide = lookVide
Reglages.memeProfil = memeProfil
Reglages.minuscules = minuscules
Reglages.nomProfil = nomProfil
Reglages.pluriel = pluriel
Reglages.pourLightroom = pourLightroom
Reglages.resume = resume
Reglages.resumer = resumer
Reglages.valeurActuelle = valeurActuelle
Reglages.valeurNumerique = valeurNumerique

return Reglages
