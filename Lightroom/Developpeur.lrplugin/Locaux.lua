-- Locaux.lua : tables de Lightroom pour les retouches locales, telles que le catalogue les range
-- (relevées dans des photos et dans les paramètres prédéfinis adaptatifs d'Adobe) :
--   MaskGroupBasedCorrections : une « Correction » par masque, avec ses réglages Local* (de −1 à
--     +1) et ses CorrectionMasks ; un masque IA ne porte que son sous-type et sa catégorie, et
--     Lightroom le calcule pour la photo, comme pour un paramètre prédéfini adaptatif ;
--   RetouchAreas : une entrée par tache (ellipse, source, mode) ;
--   RedEyeInfo : une entrée par œil.
-- Toutes les positions sont déjà dans le repère du fichier (Geometrie.lua). Pas de dépendance au
-- SDK : testé tel quel.

local Locaux = {}

local HEXA = '0123456789ABCDEF'

local function hexa(n)
    local caracteres = {}
    for i = 1, n do
        local k = math.random(1, 16)
        caracteres[i] = HEXA:sub(k, k)
    end
    return table.concat(caracteres)
end

function Locaux.uuid()
    return hexa(8) .. '-' .. hexa(4) .. '-' .. hexa(4) .. '-' .. hexa(4) .. '-' .. hexa(12)
end

function Locaux.syncId()
    return hexa(32)
end

-- Nombre à six décimales (ou chiffres) avec un point, quelle que soit la locale (string.format('%f')
-- écrirait « 0,500000 » en français).
function Locaux.decimal(x, chiffres)
    chiffres = chiffres or 6
    local echelle = 10 ^ chiffres
    local negatif = x < 0
    local n = math.floor(math.abs(x) * echelle + 0.5)
    return string.format('%s%d.%0' .. chiffres .. 'd', negatif and '-' or '', math.floor(n / echelle), n % echelle)
end

local function borner(x, mini, maxi)
    return math.min(math.max(x, mini), maxi)
end

-- Réglages locaux à zéro, comme dans les corrections que crée Lightroom (LocalGrain = 0 comme dans
-- les paramètres prédéfinis adaptatifs d'Adobe). Une courbe locale (MainCurve, RedCurve…, un
-- tableau de textes « x,y ») ne s'ajoute que si elle est demandée.
Locaux.NEUTRES = {
    LocalExposure2012 = 0, LocalContrast2012 = 0, LocalHighlights2012 = 0, LocalShadows2012 = 0,
    LocalWhites2012 = 0, LocalBlacks2012 = 0, LocalClarity2012 = 0, LocalDehaze = 0, LocalTexture = 0,
    LocalTemperature = 0, LocalTint = 0, LocalSaturation = 0, LocalSharpness = 0, LocalLuminanceNoise = 0,
    LocalMoire = 0, LocalDefringe = 0, LocalHue = 0, LocalToningHue = 0, LocalToningSaturation = 0,
    LocalCurveRefineSaturation = 100, LocalExposure = 0, LocalContrast = 0, LocalClarity = 0,
    LocalBrightness = 0, LocalGrain = 0,
}

function Locaux.correction(nom, quantite, locaux, masques)
    local correction = {
        What = 'Correction',
        CorrectionActive = true,
        CorrectionAmount = quantite or 1,
        CorrectionID = Locaux.uuid(),
        CorrectionName = nom,
        CorrectionSyncID = Locaux.syncId(),
        CorrectionMasks = masques,
    }
    for cle, valeur in pairs(Locaux.NEUTRES) do
        correction[cle] = valeur
    end
    for cle, valeur in pairs(locaux or {}) do
        correction[cle] = valeur
    end
    return correction
end

local function masque(quoi, nom, inverse)
    return {
        What = quoi,
        MaskActive = true,
        MaskBlendMode = 0,
        MaskID = Locaux.uuid(),
        MaskInverted = inverse == true,
        MaskName = nom,
        MaskSyncID = Locaux.syncId(),
        MaskValue = 1,
    }
end

-- Composant d'un masque combiné. Lightroom range le mode de chaque composant dans MaskBlendMode
-- (0 ajouter, 1 soustraire), et une intersection comme la soustraction du composant inversé :
-- A ∩ B = A − (non B) (relevé dans le module Développement de Lightroom Classic 15.6). Le premier
-- composant d'un masque est toujours ajouté.
function Locaux.combiner(m, mode, inverse)
    if mode == 'soustraire' then
        m.MaskBlendMode = 1
        m.MaskInverted = inverse == true
    elseif mode == 'intersecter' then
        m.MaskBlendMode = 1
        m.MaskInverted = inverse ~= true
    else
        m.MaskBlendMode = 0
        m.MaskInverted = inverse == true
    end
    return m
end

-- Empreinte d'un texte (deux hachages de 32 bits, en hexadécimal) : le nom d'un paramètre
-- prédéfini du module suit son contenu. Lightroom range un fichier par nom ; un contenu identique
-- réécrit donc le même fichier au lieu d'en ajouter un.
function Locaux.empreinte(texte)
    local a, b = 5381, 0
    for i = 1, #texte do
        local c = texte:byte(i)
        a = (a * 33 + c) % 4294967296
        b = (b * 65599 + c) % 4294967296
    end
    return string.format('%08X%08X', a, b)
end

-- Masque IA : Lightroom le calcule (sujet 1, ciel 2 ; arrière-plan 0 / catégorie 22 ; parties
-- d'une personne 3 / catégorie ; éléments de paysage 0 / catégorie 5000x).
function Locaux.masqueIA(soustype, categorie, nom, inverse)
    local m = masque('Mask/Image', nom, inverse)
    m.MaskVersion = 1
    m.MaskSubType = soustype
    m.MaskSubCategoryID = categorie
    m.ReferencePoint = '0.500000 0.500000'
    m.ErrorReason = 0
    return m
end

-- Une personne précise, ou une partie de cette personne. Relevé le 17 octobre 2026 dans Lightroom
-- Classic 15.6 sur des masques Personnes faits à la main (photo de groupe de six personnes) : un
-- Mask/Image de sous-type 0, de catégorie 20036 pour la personne entière ou celle de la partie (5
-- les cheveux, comme pour les parties de toutes les personnes), InstanceIDs = {{InstanceID = n}}
-- (Personne 2 → 1 : à partir de 0, dans l'ordre de Lightroom, de gauche à droite), ReferencePoint
-- sur la personne ; Lightroom y range aussi les cadres de toutes les personnes détectées
-- (InstanceBounds) et son calcul. numero : à partir de 1, comme « Personne 2 » dans Lightroom.
-- Sur une photo d'une seule personne (relevé le 20 octobre 2026, portrait d'essai) : fait à la main,
-- le masque n'a ni InstanceIDs ni InstanceBounds, seulement le sous-type 0 et la catégorie ; envoyé
-- ainsi, il donne le même masque (même MaskDigest). `seule` : la photo n'a qu'une personne.
Locaux.PERSONNE_ENTIERE = 20036

-- Catégories d'une personne précise (sous-type 0) : la personne entière et ses parties, celles des
-- parties de toutes les personnes (sous-type 3). Le sous-type 0 sert aussi à l'arrière-plan (22) et
-- au paysage (5000x).
Locaux.CATEGORIES_PERSONNE = { [20036] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true,
    [7] = true, [8] = true, [9] = true, [11] = true, [12] = true }

function Locaux.personne(numero, categorie, x, y, nom, inverse, seule)
    local m = Locaux.masqueIA(0, tonumber(categorie) or Locaux.PERSONNE_ENTIERE, nom, inverse)
    if not seule then
        m.InstanceIDs = { { InstanceID = math.max(math.floor(tonumber(numero) or 1), 1) - 1 } }
    end
    if tonumber(x) and tonumber(y) then
        m.ReferencePoint = Locaux.decimal(x) .. ' ' .. Locaux.decimal(y)
    end
    return m
end

-- Personne d'un masque (InstanceID + 1), ou nil ; 1 pour celui de la personne seule d'une photo
-- (sous-type 0 et catégorie d'une personne, sans InstanceIDs).
function Locaux.numeroPersonne(m)
    local liste = type(m) == 'table' and m.InstanceIDs
    local premier = type(liste) == 'table' and liste[1]
    local id = type(premier) == 'table' and tonumber(premier.InstanceID)
    if id then
        return id + 1
    end
    if type(m) == 'table' and m.What == 'Mask/Image' and liste == nil and tonumber(m.MaskSubType) == 0
        and Locaux.CATEGORIES_PERSONNE[tonumber(m.MaskSubCategoryID)] then
        return 1
    end
    return nil
end

-- Contour d'un masque IA (affinage du masque, Lightroom Classic 15.5). Relevé le 17 octobre 2026 :
-- les curseurs Contour progressif (0 à 100) et Contour (−50 à +50) se rangent dans le Mask/Image
-- même, Feather (100 → 10, 50 → 1,92, 25 → 0,35) et EdgeShift (le curseur divisé par 10). Le
-- serveur convertit ; ici, les valeurs rangées.
function Locaux.affiner(m, contour, decalage)
    if type(m) ~= 'table' or m.What ~= 'Mask/Image' then
        return false
    end
    if tonumber(contour) then
        m.Feather = tonumber(contour)
    end
    if tonumber(decalage) then
        m.EdgeShift = tonumber(decalage)
    end
    return true
end

-- Touches d'un trait de pinceau (Dabs), relevées dans Lightroom Classic 15.6 sur des masques Pinceau
-- faits à la main : une liste de textes, « r <rayon> », « f <flux> », « h <dureté> » (comme
-- CenterWeight), puis une touche « d x y » par point (« M x y » avec le masquage automatique). Les
-- positions sont dans le repère du fichier (0 à 1) ; le rayon se rapporte au grand côté du fichier
-- (supposé, comme celui des taches). Les touches sont espacées d'un cinquième du rayon (relevé : 0,2
-- sur deux traits de rayons différents). points : {{x, y}…} ; lf, hf : dimensions du fichier.
function Locaux.touches(points, rayon, lf, hf, reglages)
    reglages = reglages or {}
    local liste = { 'r ' .. Locaux.decimal(rayon) }
    if reglages.flux then
        liste[#liste + 1] = 'f ' .. Locaux.decimal(reglages.flux, 4)
    end
    if reglages.durete then
        liste[#liste + 1] = 'h ' .. Locaux.decimal(reglages.durete, 4)
    end
    local lettre = reglages.auto and 'M ' or 'd '
    local function poser(x, y)
        liste[#liste + 1] = lettre .. Locaux.decimal(x) .. ' ' .. Locaux.decimal(y)
    end
    local pas = math.max(0.2 * rayon * math.max(lf, hf), 0.5)
    for i, p in ipairs(points) do
        if i == 1 then
            poser(p[1], p[2])
        else
            local a = points[i - 1]
            local n = math.max(1, math.ceil(math.sqrt(((p[1] - a[1]) * lf) ^ 2 + ((p[2] - a[2]) * hf) ^ 2) / pas))
            for k = 1, n do
                poser(a[1] + (p[1] - a[1]) * k / n, a[2] + (p[2] - a[2]) * k / n)
            end
        end
    end
    return liste
end

-- Masque Pinceau : un Mask/Aggregate qui porte un Mask/Paint par trait, comme Lightroom les range
-- (relevé). traits : { { dabs, rayon, flux, durete } }.
function Locaux.pinceau(traits, nom, inverse)
    local agregat = masque('Mask/Aggregate', nom, inverse)
    agregat.Masks = {}
    for _, t in ipairs(traits) do
        local m = masque('Mask/Paint', nil, false)
        m.MaskName = nil
        m.Radius, m.Flow, m.CenterWeight, m.Dabs = t.rayon, t.flux or 1, t.durete or 0, t.dabs
        agregat.Masks[#agregat.Masks + 1] = m
    end
    return agregat
end

-- Sélection d'objet : un masque IA de sous-type 0, sans catégorie, que Lightroom calcule d'après un
-- geste au pinceau passé sur l'objet (relevé sur un masque Objets fait à la main : Gesture = un
-- Mask/Paint de rayon 0, ses touches « r », puis « d x y » ; ReferencePoint, le centre).
function Locaux.objet(dabs, cx, cy, nom, inverse)
    local m = Locaux.masqueIA(0, nil, nom, inverse)
    local geste = masque('Mask/Paint', nil, false)
    geste.MaskName = nil
    geste.BrushGestureInterpretation, geste.CenterWeight, geste.Flow, geste.Radius = 0, 0, 1, 0
    geste.Dabs = dabs
    m.Gesture = { geste }
    m.ReferencePoint = Locaux.decimal(cx) .. ' ' .. Locaux.decimal(cy)
    return m
end

-- Dégradé linéaire : effet entier en (fx, fy), nul en (zx, zy).
function Locaux.lineaire(zx, zy, fx, fy, nom, inverse)
    local m = masque('Mask/Gradient', nom, inverse)
    m.ZeroX, m.ZeroY, m.FullX, m.FullY = zx, zy, fx, fy
    return m
end

-- Dégradé radial : ellipse inscrite dans (gauche, haut, droite, bas), tournée de angle degrés.
function Locaux.radial(gauche, haut, droite, bas, angle, fondu, nom, inverse)
    local m = masque('Mask/CircularGradient', nom, inverse)
    m.Left, m.Top, m.Right, m.Bottom = gauche, haut, droite, bas
    m.Angle = angle or 0
    m.Feather = fondu or 50
    m.Midpoint = 50
    m.Roundness = 0
    m.Flipped = true
    m.Version = 2
    return m
end

-- Plage de luminance de mini à maxi (0 à 1), avec un fondu de part et d'autre.
function Locaux.luminance(mini, maxi, fondu, nom, inverse)
    local m = masque('Mask/RangeMask', nom, inverse)
    local valeurs = {
        borner(mini - fondu, 0, 1), borner(mini, 0, 1), borner(maxi, 0, 1), borner(maxi + fondu, 0, 1),
    }
    for i, v in ipairs(valeurs) do
        valeurs[i] = Locaux.decimal(v)
    end
    m.CorrectionRangeMask = {
        Type = 2,
        LumRange = table.concat(valeurs, ' '),
        Invert = false,
        SampleType = 0,
        Version = 3,
    }
    return m
end

-- Plage de couleurs : un masque RangeMask de Type 1, comme Lightroom le range (relevé dans Lightroom
-- Classic 15.6 sur un masque fait à la main, et dans cr_range_mask de Camera Raw) : PointModels, un
-- texte par couleur prélevée, « c1 c2 c3 x y 0 » (le modèle de la couleur, que le serveur calcule
-- sur l'aperçu, puis la position du prélèvement dans le repère du fichier) ; ColorAmount, l'étendue
-- (0 à 1) ; CorrectionReferenceX et Y reprennent le premier prélèvement. points : {{c1, c2, c3, x, y}}.
function Locaux.couleur(points, etendue, nom, inverse)
    local m = masque('Mask/RangeMask', nom, inverse)
    local modeles = {}
    for _, p in ipairs(points) do
        modeles[#modeles + 1] = table.concat({ Locaux.decimal(p[1]), Locaux.decimal(p[2]), Locaux.decimal(p[3]),
            Locaux.decimal(p[4]), Locaux.decimal(p[5]), '0' }, ' ')
    end
    m.CorrectionRangeMask = {
        Type = 1,
        ColorAmount = borner(etendue or 0.5, 0, 1),
        Invert = false,
        SampleType = 0,
        Version = 3,
        PointModels = modeles,
    }
    if points[1] then
        m.CorrectionReferenceX, m.CorrectionReferenceY = points[1][4], points[1][5]
    end
    return m
end

-- Plage de profondeur de mini à maxi (0 à 1, du plus proche au plus loin), avec un fondu : comme la
-- plage de luminance, Type 3 et DepthRange, quatre valeurs de 0 à 1. Constaté le 17 octobre 2026
-- sur une photo Portrait d'iPhone (HEIC) : 0 à 0,35 n'assombrit que le bras tendu au premier plan,
-- 0,6 à 1 tout le reste ; DepthMin, DepthMax et DepthFeather (forme « M2 ») à la place de
-- DepthRange, ou des valeurs de 0 à 100, font prendre l'image entière. Seulement sur une photo qui
-- porte une carte de profondeur (negative:hasDepthMap()) ; au premier rendu, Lightroom peut ne pas
-- l'avoir encore chargée.
function Locaux.profondeur(mini, maxi, fondu, nom, inverse)
    local m = Locaux.luminance(mini, maxi, fondu, nom, inverse)
    m.CorrectionRangeMask.Type = 3
    m.CorrectionRangeMask.DepthRange = m.CorrectionRangeMask.LumRange
    m.CorrectionRangeMask.LumRange = nil
    return m
end

-- Sélection d'objet par un rectangle : le geste est un Mask/Polygon (mode rectangle de l'outil Objets,
-- relevé dans le code de Lightroom Classic 15.6 : objectRectSelect quand Gesture[1].What vaut
-- Mask/Polygon) dont Points porte les coins dans le repère du fichier, chacun une table {X, Y}.
-- Constaté le 17 octobre 2026 : ainsi, Lightroom calcule l'objet (un érable désigné par son cadre,
-- sélectionné seul) ; des points en textes « x y », en paires ou en un seul texte font rejeter le
-- geste (ErrorReason 1, Gesture retiré).
function Locaux.objetRectangle(coins, nom, inverse)
    local m = Locaux.masqueIA(0, nil, nom, inverse)
    local geste = masque('Mask/Polygon', nil, false)
    geste.MaskName = nil
    geste.Points = {}
    local sx, sy = 0, 0
    for _, c in ipairs(coins) do
        geste.Points[#geste.Points + 1] = { X = c[1], Y = c[2] }
        sx, sy = sx + c[1], sy + c[2]
    end
    m.Gesture = { geste }
    m.ReferencePoint = Locaux.decimal(sx / #coins) .. ' ' .. Locaux.decimal(sy / #coins)
    return m
end

-- Tache : centre (x, y), rayon (taille), source (sx, sy), mode 'heal', 'clone' ou 'remove', fondu 0 à 1.
-- Mode 'remove' : l'outil Supprimer sans IA générative. Relevé dans Lightroom Classic 15.6 (code et
-- taches faites à la main) : SpotType = 'heal_patchmatch', Method = 'poisson', et fill_method =
-- 'patchmatch' (une autre valeur pour la suppression générative, jamais posée) ; Lightroom range
-- aussi le résultat de son calcul (pm_patch, pm_version…), qu'un module ne peut pas fabriquer :
-- supposé calculé par updateAISettings (« Update Remove »).
function Locaux.tache(x, y, taille, sx, sy, mode, fondu)
    if mode == 'remove' then
        local t = Locaux.tache(x, y, taille, sx, sy, 'heal', fondu)
        t.SpotType, t.spotType, t.Method, t.fill_method = 'heal_patchmatch', 'heal_patchmatch', 'poisson', 'patchmatch'
        return t
    end
    local cercle = masque('Mask/Ellipse', nil, false)
    cercle.MaskName = nil
    cercle.X, cercle.Y = x, y
    cercle.SizeX, cercle.SizeY = taille, taille
    cercle.Alpha = 0
    cercle.CenterValue = 1
    cercle.PerimeterValue = 0
    return {
        Feather = fondu or 0.43,
        HealVersion = 2,
        Masks = { cercle },
        Method = 'gaussian',
        Opacity = 1,
        Seed = 2,
        SourceState = 'sourceAutoComputed',
        SpotType = mode == 'clone' and 'clone' or 'heal',
        SourceX = sx,
        OffsetY = sy,
        centerX = x, centerY = y,
        radius = taille,
        opacity = 1,
        seed = 2,
        sourceState = 'sourceAutoComputed',
        sourceX = sx, sourceY = sy,
        spotType = mode == 'clone' and 'clone' or 'heal',
    }
end

-- Œil rouge : pupille en (x, y), demi-axes (rx, ry), taille corrigée et assombrissement (0 à 1).
-- Lightroom range aussi ce qu'il a détecté (densité, force) : des valeurs moyennes relevées
-- dans le catalogue en tiennent lieu.
function Locaux.oeilRouge(x, y, rx, ry, pupille, assombrir)
    return {
        adaptivePupilColor = 0,
        gammaEncodeCorrection = 1,
        highlightX = 0.591,
        highlightY = 0.424,
        pupil = {
            density = 0.8,
            ellipse = { alpha = 0, centerX = x, centerY = y, sizeX = rx, sizeY = ry },
            redBias = 0.2,
            strength = 0.15,
        },
        pupilDarkenAmount = assombrir or 0.5,
        pupilSize = pupille or 0.5,
        showPetEyeHighlight = 1,
    }
end

-- Couleurs ponctuelles d'un masque (LocalPointColors), relevées dans le code de Lightroom Classic
-- 15.6 (DevelopPointColorUtils.serializePointColors, DevelopLocalizedCommon) : un texte de 19
-- nombres par couleur, « %f, %f, … », dans l'ordre SrcHue, SrcSat, SrcLum, HueShift, SatScale,
-- LumScale, RangeAmount, puis HueRange, SatRange et LumRange (LowerNone, LowerFull, UpperFull,
-- UpperNone) : les champs des tables de PointColors, que le serveur construit. La variance de
-- chaque couleur va à part, dans LocalColorVariance, un texte « %f » par couleur (relevé dans
-- serializePointColors) : renvoyée en second.
function Locaux.couleursPonctuelles(liste)
    local textes, variances = {}, {}
    for _, c in ipairs(liste or {}) do
        variances[#variances + 1] = Locaux.decimal(tonumber(c.Variance) or 0)
        local valeurs = {
            c.SrcHue, c.SrcSat, c.SrcLum, c.HueShift, c.SatScale, c.LumScale, c.RangeAmount,
        }
        for _, plage in ipairs({ 'HueRange', 'SatRange', 'LumRange' }) do
            local p = type(c[plage]) == 'table' and c[plage] or {}
            for _, bord in ipairs({ 'LowerNone', 'LowerFull', 'UpperFull', 'UpperNone' }) do
                valeurs[#valeurs + 1] = p[bord]
            end
        end
        for i = 1, 19 do
            valeurs[i] = Locaux.decimal(tonumber(valeurs[i]) or 0)
        end
        textes[#textes + 1] = table.concat(valeurs, ', ')
    end
    return textes, variances
end

-- Masques IA copiés d'une photo à l'autre : sans ce que Lightroom a calculé pour la photo
-- d'origine, pour qu'il les recalcule.
local CALCULES = {
    InputDigest = true, InputDigestVersion = true, LocalInputDigest = true, LocalInputDigestVersion = true,
    MaskDigest = true, FullMaskSize = true, Origin = true, WholeImageArea = true, ModelVersion = true,
    -- Pas les cadres des personnes (InstanceBounds) : sans eux, Lightroom ne reconnaît plus la
    -- personne d'un masque (constaté le 18 octobre 2026, voir Locaux.personne).
}

-- Masques de personnes précises que Lightroom n'a plus reconnues après un calcul : ceux qui avaient
-- InstanceIDs avant, et n'en ont plus une fois calculés (il les retire, voir Locaux.personne), ou
-- celui d'une personne seule qui n'est plus de sous-type 0. Renvoie leurs noms.
function Locaux.personnesPerdues(avant, apres)
    local personnes = {}
    for _, correction in ipairs(avant or {}) do
        for k, m in ipairs(correction.CorrectionMasks or {}) do
            if type(m) == 'table' and Locaux.numeroPersonne(m) then
                personnes[tostring(correction.CorrectionID) .. '/' .. k] = m.InstanceIDs and 'numero' or 'seule'
            end
        end
    end
    local noms = {}
    for _, correction in ipairs(apres or {}) do
        for k, m in ipairs(correction.CorrectionMasks or {}) do
            local genre = type(m) == 'table' and personnes[tostring(correction.CorrectionID) .. '/' .. k]
            if genre and m.MaskDigest ~= nil and (tonumber(m.MaskSubType) ~= 0 or (genre == 'numero' and not m.InstanceIDs)) then
                noms[#noms + 1] = tostring(correction.CorrectionName or m.MaskName or '?')
            end
        end
    end
    return noms
end

function Locaux.aDesMasquesIA(corrections)
    for _, correction in ipairs(corrections or {}) do
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            if m.What == 'Mask/Image' then
                return true
            end
        end
    end
    return false
end

-- Flou d'objectif, comme le range Lightroom Classic 15.6 (relevé dans le catalogue) : Lightroom
-- calcule la carte de profondeur (DepthMapInfo). FocalRange = « début du fondu, début de la zone
-- nette, fin de la zone nette, fin du fondu » sur une profondeur de 0 (près) à 100 (loin), avec
-- des fondus de 80 ; FocalRangeSource = 1 : mise au point sur le sujet, que Lightroom détecte.
local function tableFlou(actif, intensite, proche, loin, sujet, eclat)
    return {
        Active = actif, BlurAmount = intensite,
        BokehAspect = 0, BokehRotation = 0, BokehShape = 0, BokehShapeDetail = 0,
        CatEyeAmount = 0, CatEyeScale = 100,
        FocalRange = string.format('%d %d %d %d', proche - 80, proche, loin, loin + 80),
        FocalRangeSource = sujet and 1 or 0,
        HighlightsBoost = eclat, HighlightsThreshold = 50, ImageOrientation = 0,
        SampledArea = '0.500000 0.500000 0.500000 0.500000', SampledRange = '0 0',
        SphericalAberration = 0, SubjectRange = string.format('%d %d', proche, loin), Version = 1,
    }
end

local function copie(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local resultat = {}
    for cle, element in pairs(valeur) do
        resultat[cle] = copie(element)
    end
    return resultat
end

-- params : intensite (0 à 100), proche et loin (zone nette, 0 à 100 ; absents = sur le sujet),
-- eclat (hautes lumières du bokeh, 0 à 100), bokeh (forme : les champs Bokeh*, SphericalAberration
-- et CatEyeScale que le serveur tire de son catalogue), oeil_de_chat (CatEyeAmount, 0 à 100).
-- actuel : le flou de la photo ; s'il est actif, ce que params ne donne pas en reste.
function Locaux.flouObjectif(params, actuel)
    local function entier(valeur, defaut, mini, maxi)
        return math.floor(borner(tonumber(valeur) or defaut, mini, maxi) + 0.5)
    end
    local base = type(actuel) == 'table' and actuel.Active == true and actuel or nil
    local sujet = tonumber(params.proche) == nil or tonumber(params.loin) == nil
    local proche = entier(params.proche, 0, 0, 100)
    local loin = math.max(entier(params.loin, 55, 0, 100), proche)
    local flou = tableFlou(true, entier(params.intensite, base and base.BlurAmount or 50, 0, 100), proche, loin, sujet,
        entier(params.eclat, base and base.HighlightsBoost or 50, 0, 100))
    if base then
        local nouveau = flou
        flou = copie(base)
        flou.Active, flou.BlurAmount, flou.HighlightsBoost = true, nouveau.BlurAmount, nouveau.HighlightsBoost
        if not sujet then
            flou.FocalRange, flou.SubjectRange, flou.FocalRangeSource = nouveau.FocalRange, nouveau.SubjectRange, 0
        end
    end
    for cle, valeur in pairs(type(params.bokeh) == 'table' and type(params.bokeh.champs) == 'table' and params.bokeh.champs or {}) do
        flou[cle] = tonumber(valeur)
    end
    if tonumber(params.oeil_de_chat) then
        flou.CatEyeAmount = entier(params.oeil_de_chat, 0, 0, 100)
    end
    if params.sujet == true then
        -- Retour à la mise au point sur le sujet, sur un flou qui en avait une autre.
        flou.FocalRangeSource = 1
    end
    return flou
end

-- Pinceau d'affinage du flou d'objectif. Relevé le 17 octobre 2026 dans Lightroom Classic 15.6 : un
-- trait du pinceau Affiner range une correction dans DepthBasedCorrections, comme un masque pinceau
-- (un Mask/Aggregate de Mask/Paint, touches dans le repère du fichier), avec LocalCorrectedDepth = −1
-- en mode Net (rapproché de la zone nette) et 1 en mode Flou, CorrectionReferenceX et Y sur le trait.
-- traits : comme pour Locaux.pinceau ; net : vrai pour le mode Net.
function Locaux.affinageProfondeur(traits, net, cx, cy)
    local agregat = Locaux.pinceau(traits, nil, false)
    agregat.MaskName = nil
    return {
        What = 'Correction',
        CorrectionActive = true,
        CorrectionAmount = 1,
        CorrectionID = Locaux.uuid(),
        CorrectionSyncID = Locaux.syncId(),
        CorrectionMasks = { agregat },
        CorrectionReferenceX = cx,
        CorrectionReferenceY = cy,
        LocalCorrectedDepth = net and -1 or 1,
        LocalCurveRefineSaturation = 100,
    }
end

-- Suppression de la poussière du capteur (outil Supprimer › Poussière, Lightroom Classic 15.x).
-- Relevé le 17 octobre 2026 dans Lightroom Classic 15.6 : appliquée à la main, elle range un filtre
-- de FilterList, Name = 'Dust Removal', FilterID = 6, Title =
-- '$$$/CRaw/Filter/DustRemoval/FilterPanelTitle=Dust Removal', avec le résultat de la détection
-- (CompressedSettings, sa table, Images : une par tache trouvée), calculée sur ce Mac ; sans
-- poussière trouvée, rien n'est rangé. La mise à jour des réglages IA (updateAISettings,
-- AgCameraRawBatchPixelMaskUpdate) traite ce filtre (« Update Removal: Dust »).
Locaux.NOM_POUSSIERE = 'Dust Removal'

function Locaux.filtrePoussiere(reglages)
    local liste = type(reglages) == 'table' and type(reglages.FilterList) == 'table' and reglages.FilterList.Filters
    for _, filtre in ipairs(type(liste) == 'table' and liste or {}) do
        if type(filtre) == 'table' and (filtre.Name == Locaux.NOM_POUSSIERE or tonumber(filtre.FilterID) == 6) then
            return filtre
        end
    end
    return nil
end

-- FilterList d'une photo dont le filtre de la poussière est remplacé par `filtre` (nil : retiré),
-- les autres filtres (débruitage, reflets…) gardés tels quels.
function Locaux.avecFiltrePoussiere(filterList, filtre)
    local filtres = {}
    local liste = type(filterList) == 'table' and filterList.Filters
    for _, autre in ipairs(type(liste) == 'table' and liste or {}) do
        if not (type(autre) == 'table' and (autre.Name == Locaux.NOM_POUSSIERE or tonumber(autre.FilterID) == 6)) then
            filtres[#filtres + 1] = copie(autre)
        end
    end
    if filtre then
        filtres[#filtres + 1] = copie(filtre)
    end
    if #filtres == 0 then
        return {}
    end
    return { Filters = filtres }
end

function Locaux.flouInactif()
    return tableFlou(false, 50, 0, 55, true, 50)
end

-- Vrai si un masque IA attend encore son calcul par Lightroom (pas encore d'empreinte MaskDigest).
-- Un masque que Lightroom n'a pas su calculer porte ErrorReason ≠ 0 (constaté dans Lightroom Classic
-- 15.6 : 1, pour un objet désigné par un trait trop large) : il n'attend plus rien.
function Locaux.masquesIAACalculer(corrections)
    for _, correction in ipairs(corrections or {}) do
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            if m.What == 'Mask/Image' and m.MaskDigest == nil and (tonumber(m.ErrorReason) or 0) == 0 then
                return true
            end
        end
    end
    return false
end

-- Noms des masques IA que Lightroom n'a pas su calculer (ErrorReason ≠ 0, sans MaskDigest).
function Locaux.masquesIAEnEchec(corrections)
    local noms = {}
    for _, correction in ipairs(corrections or {}) do
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            if m.What == 'Mask/Image' and m.MaskDigest == nil and (tonumber(m.ErrorReason) or 0) ~= 0 then
                noms[#noms + 1] = tostring(correction.CorrectionName or m.MaskName or "masque")
            end
        end
    end
    return noms
end

-- Profil adaptatif (Look que Lightroom marque isAdobeAdaptive) à calculer : AILook actif sans
-- AILookData (relevé dans le catalogue après Adaptive Color posé à la main : AILookData,
-- InputDigest, InputDigestVersion, ModelVersion, Version, Active). Lightroom ne le calcule pas
-- de lui-même (rien en 75 s), contrairement aux masques IA de la photo affichée.
function Locaux.lookACalculer(reglages)
    local look, calcul = reglages.Look, reglages.AILook
    return type(look) == 'table' and look.isAdobeAdaptive == true
        and type(calcul) == 'table' and calcul.Active == true and calcul.AILookData == nil
end

-- Taches de l'outil Supprimer pas encore calculées par Lightroom (sans pm_patch).
function Locaux.suppressionsACalculer(reglages)
    for _, cle in ipairs({ 'RemoveAreas', 'RetouchAreas' }) do
        for _, tache in ipairs(type(reglages[cle]) == 'table' and reglages[cle] or {}) do
            if type(tache) == 'table' and tache.SpotType == 'heal_patchmatch' and tache.pm_patch == nil then
                return true
            end
        end
    end
    return false
end

-- Calculs que Lightroom fait de lui-même, peu après, sur la photo affichée : masques IA et
-- carte de profondeur.
function Locaux.calculsSpontanes(reglages)
    if Locaux.masquesIAACalculer(reglages.MaskGroupBasedCorrections) then
        return true
    end
    local flou = reglages.LensBlur
    if type(flou) == 'table' and flou.Active == true then
        local profondeur = reglages.DepthMapInfo
        return type(profondeur) ~= 'table' or profondeur.BaseRawDepthInputDigest == nil
    end
    return false
end

-- Vrai si Lightroom doit encore calculer quelque chose pour rendre la photo : un masque IA, la
-- carte de profondeur d'un flou d'objectif actif, un profil adaptatif, ou une tache Supprimer.
function Locaux.calculsEnAttente(reglages)
    return Locaux.calculsSpontanes(reglages) or Locaux.lookACalculer(reglages) or Locaux.suppressionsACalculer(reglages)
end

function Locaux.sansCalculsIA(corrections)
    for _, correction in ipairs(corrections or {}) do
        for _, m in ipairs(correction.CorrectionMasks or {}) do
            if m.What == 'Mask/Image' then
                for cle in pairs(CALCULES) do
                    m[cle] = nil
                end
                m.ReferencePoint = m.ReferencePoint or '0.500000 0.500000'
                m.ErrorReason = 0
            end
        end
    end
    return corrections
end

return Locaux
