-- Recadrage.lua : calcul du cadre de recadrage de Lightroom à partir d'une demande simple
-- (ratio, angle, taille, centre), exprimée dans l'image telle qu'elle s'affiche.
--
-- Lightroom range le cadre dans le repère du fichier, avant l'orientation (de 0 à 1) : le cadre
-- est tourné de CropAngle degrés, et (CropLeft, CropTop) et (CropRight, CropBottom) sont ses coins
-- haut gauche et bas droit. Un angle positif tourne le cadre dans le sens horaire sur le fichier :
-- l'image affichée tourne dans le sens antihoraire, son côté droit monte (constaté dans Lightroom
-- Classic 15.6, qui en déduit les dimensions recadrées). Pas de dépendance au SDK : testé tel quel.
--
-- Le cadre se pose sur l'image transformée : Upright, la perspective et la distorsion manuelle y
-- laissent des coins vides, que Lightroom rend en blanc (constaté dans Lightroom Classic 15.6).
-- Avec une zone (Geometrie.zone, tirée de la grille de recalage du serveur), le cadre ne garde
-- que la partie de l'image qui montre la photo, au centre et à la taille demandés ; Lightroom, case
-- « Contraindre le recadrage » cochée, le garde tel quel (constaté).

local Recadrage = {}

-- Passage d'un point de l'image affichée (u, v de 0 à 1, depuis le coin haut gauche) au repère
-- du fichier, selon l'orientation de Lightroom. DA, la plus courante (appareil tenu poignée en
-- haut) : le bord droit du fichier s'affiche en haut (constaté dans Lightroom Classic 15.6) ;
-- BC est le quart de tour inverse.
local versFichier = {
    AB = function(u, v) return u, v end,
    BC = function(u, v) return v, 1 - u end,
    CD = function(u, v) return 1 - u, 1 - v end,
    DA = function(u, v) return 1 - v, u end,
}

-- Et l'inverse : du repère du fichier à l'image affichée.
local versAffichage = {
    AB = function(s, t) return s, t end,
    BC = function(s, t) return 1 - t, s end,
    CD = function(s, t) return 1 - s, 1 - t end,
    DA = function(s, t) return t, 1 - s end,
}

-- Conversion d'un point de l'image affichée au repère du fichier, pour cette orientation.
function Recadrage.versFichier(orientation)
    return versFichier[orientation] or versFichier.AB
end

function Recadrage.versAffichage(orientation)
    return versAffichage[orientation] or versAffichage.AB
end

-- L'orientation transpose-t-elle la largeur et la hauteur ?
function Recadrage.tournee(orientation)
    return orientation == 'BC' or orientation == 'DA'
end

local function borner(valeur, mini, maxi)
    return math.min(math.max(valeur, mini), maxi)
end

local function arrondir(valeur, facteur)
    return math.floor(valeur * facteur + 0.5) / facteur
end

local function decimal(valeur)
    return (string.format('%.2f', valeur):gsub('%.', ','))
end

-- Sans recadrage : le cadre couvre tout le fichier, sans angle.
Recadrage.AUCUN = { CropAngle = 0, CropLeft = 0, CropTop = 0, CropRight = 1, CropBottom = 1 }

-- Cadres dans une zone ---------------------------------------------------------------------
--
-- Un cadre est donné dans l'image affichée, en pixels : centre (x, y), largeur w, ratio, angle
-- (cos, sin). Son axe horizontal suit (cos, sin), l'axe vertical (−sin, cos) : le même sens que
-- dans le fichier, l'orientation n'étant qu'un quart de tour.

-- Points vérifiés sur chaque côté (coins compris) : avec la distorsion, les bords de la zone ne
-- sont pas tout à fait droits.
local POINTS_PAR_COTE = 8

local function cadreDansZone(z, x, y, w)
    local h = w / z.ratio
    for k = 0, 4 * POINTS_PAR_COTE - 1 do
        local cote, f = math.floor(k / POINTS_PAR_COTE), (k % POINTS_PAR_COTE) / POINTS_PAR_COTE - 0.5
        local a, b
        if cote == 0 then
            a, b = f, -0.5
        elseif cote == 1 then
            a, b = 0.5, f
        elseif cote == 2 then
            a, b = -f, 0.5
        else
            a, b = -0.5, -f
        end
        local px = x + a * w * z.cos - b * h * z.sin
        local py = y + a * w * z.sin + b * h * z.cos
        if px < -1e-6 or py < -1e-6 or px > z.largeur + 1e-6 or py > z.hauteur + 1e-6
            or not z.zone(px / z.largeur, py / z.hauteur) then
            return false
        end
    end
    return true
end

-- Plus grande largeur d'un cadre centré en (x, y) qui tient dans l'image et dans la zone ; la
-- zone étant (presque) convexe, un cadre qui tient tient encore réduit autour du même centre.
local function largeurMax(z, x, y)
    local borne = math.min(2 * math.min(x, z.largeur - x) / z.bx, 2 * math.min(y, z.hauteur - y) / z.by)
    if borne <= 0 then
        return 0
    end
    if cadreDansZone(z, x, y, borne) then
        return borne
    end
    local bas, haut = 0, borne
    for _ = 1, 20 do
        local milieu = (bas + haut) / 2
        if cadreDansZone(z, x, y, milieu) then
            bas = milieu
        else
            haut = milieu
        end
    end
    return bas
end

-- Centre qui donne le plus grand cadre, en ne bougeant que les axes libres (recherche par motifs,
-- du pas d'un dixième de l'image au pas d'un demi-millième).
local function meilleurCentre(z, x, y, libreX, libreY)
    local directions = {}
    if libreX then
        directions[#directions + 1] = { 1, 0 }
        directions[#directions + 1] = { -1, 0 }
    end
    if libreY then
        directions[#directions + 1] = { 0, 1 }
        directions[#directions + 1] = { 0, -1 }
    end
    if libreX and libreY then
        for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
            directions[#directions + 1] = d
        end
    end
    local meilleur = largeurMax(z, x, y)
    local pas = 0.1
    while #directions > 0 and pas >= 0.0005 do
        local mx, my
        for _, d in ipairs(directions) do
            local cx = borner(x + d[1] * pas * z.largeur, 0, z.largeur)
            local cy = borner(y + d[2] * pas * z.hauteur, 0, z.hauteur)
            local w = largeurMax(z, cx, cy)
            if w > meilleur * (1 + 1e-9) then
                meilleur, mx, my = w, cx, cy
            end
        end
        if mx then
            x, y = mx, my
        else
            pas = pas / 2
        end
    end
    return x, y, meilleur
end

-- Largeur et centre du cadre dans la zone (pixels de l'image affichée), et la remarque pour Claude.
-- Le plus grand cadre sans coin vide sert de référence à la taille ; un centre non donné se place
-- au plus près du milieu de l'image où ce cadre-là tient.
local function dansZone(z, demande, taille, cx, cy, maximumImage)
    local gx, gy, maximum = meilleurCentre(z, z.largeur / 2, z.hauteur / 2, true, true)
    if maximum < 0.05 * maximumImage then
        error("Upright ou la perspective ne laissent presque rien de l'image sans coin vide : recadrage impossible.", 0)
    end
    local voulu = maximum * taille
    local libreX, libreY = demande.centre_x == nil, demande.centre_y == nil
    local x = libreX and z.largeur / 2 or cx * z.largeur
    local y = libreY and z.hauteur / 2 or cy * z.hauteur
    local w = largeurMax(z, x, y)
    if w < voulu and (libreX or libreY) then
        -- Vers le centre du plus grand cadre (les axes donnés restent), jusqu'où le cadre voulu tient.
        local bx, by = gx, gy
        if not (libreX and libreY) then
            bx, by = meilleurCentre(z, x, y, libreX, libreY)
        end
        if largeurMax(z, bx, by) >= voulu then
            local bas, haut = 0, 1
            for _ = 1, 20 do
                local s = (bas + haut) / 2
                if largeurMax(z, x + s * (bx - x), y + s * (by - y)) >= voulu then
                    haut = s
                else
                    bas = s
                end
            end
            x, y = x + haut * (bx - x), y + haut * (by - y)
        else
            x, y = bx, by
        end
        w = largeurMax(z, x, y)
    end
    if w < 0.05 * maximum then
        error("Cadre trop petit à cet endroit : rapprocher le centre (center_x, center_y) du milieu de l'image.", 0)
    end
    local remarques = {}
    if maximum < maximumImage * 0.999 then
        local texte = string.format("Cadre resserré sur l'image redressée (Upright, perspective) pour n'y laisser aucun coin vide : %d %% de la largeur de l'image",
            math.floor(math.min(w, voulu) / z.largeur * 100 + 0.5))
        local u, v = x / z.largeur, y / z.hauteur
        if (libreX and math.abs(u - 0.5) > 0.005) or (libreY and math.abs(v - 0.5) > 0.005) then
            texte = texte .. string.format(", centré en (%s ; %s)", decimal(u), decimal(v))
        end
        remarques[#remarques + 1] = texte .. "."
    end
    if w < voulu * 0.999 then
        remarques[#remarques + 1] = string.format("Cadre réduit à %d %% de la taille demandée pour tenir dans l'image, sans coin vide, autour de ce centre.",
            math.floor(w / voulu * 100 + 0.5))
    end
    return math.min(w, voulu), x / z.largeur, y / z.hauteur, #remarques > 0 and table.concat(remarques, " ") or nil
end

local function preparerZone(zone, largeur, hauteur, ratio, angle)
    local t = math.rad(math.abs(angle))
    return {
        zone = zone, largeur = largeur, hauteur = hauteur, ratio = ratio,
        cos = math.cos(math.rad(angle)), sin = math.sin(math.rad(angle)),
        bx = math.cos(t) + math.sin(t) / ratio, by = math.sin(t) + math.cos(t) / ratio,
    }
end

-- demande : {ratio?, angle, taille, centre_x?, centre_y?} ou {retirer = true} ; un centre absent vaut
-- le milieu de l'image (sans zone)
-- largeur, hauteur : dimensions de l'image affichée, en pixels
-- orientation : 'AB' (par défaut), 'BC', 'CD' ou 'DA'
-- zone : facultative, fonction (u, v) → vrai si ce point de l'image affichée entière (de 0 à 1)
-- montre la photo (voir Geometrie.zone)
-- Renvoie les cinq réglages Crop* et, si le cadre a dû rétrécir pour tenir, une remarque.
function Recadrage.calculer(demande, largeur, hauteur, orientation, zone)
    if demande.retirer then
        local cadre = {}
        for cle, valeur in pairs(Recadrage.AUCUN) do
            cadre[cle] = valeur
        end
        return cadre
    end
    largeur, hauteur = tonumber(largeur), tonumber(hauteur)
    if not largeur or not hauteur or largeur <= 0 or hauteur <= 0 then
        error("Dimensions de la photo inconnues : recadrage impossible.", 0)
    end

    local angle = arrondir(borner(tonumber(demande.angle) or 0, -45, 45), 100)
    local ratio = tonumber(demande.ratio) or (largeur / hauteur)
    local taille = borner(tonumber(demande.taille) or 1, 0.05, 1)
    local cx = borner(tonumber(demande.centre_x) or 0.5, 0, 1)
    local cy = borner(tonumber(demande.centre_y) or 0.5, 0, 1)

    -- Boîte englobante d'un cadre de largeur 1 et de hauteur 1 / ratio, tourné de l'angle :
    -- le cadre tient dans l'image si sa boîte englobante y tient.
    local t = math.rad(math.abs(angle))
    local bx = math.cos(t) + math.sin(t) / ratio
    local by = math.sin(t) + math.cos(t) / ratio

    local maximum = math.min(largeur / bx, hauteur / by)
    local w, remarque
    if zone then
        w, cx, cy, remarque = dansZone(preparerZone(zone, largeur, hauteur, ratio, angle), demande, taille, cx, cy, maximum)
    else
        local voulu = maximum * taille
        w = math.min(voulu, 2 * math.min(cx, 1 - cx) * largeur / bx, 2 * math.min(cy, 1 - cy) * hauteur / by)
        if w < 0.05 * maximum then
            error("Cadre trop petit à cet endroit : rapprocher le centre (center_x, center_y) du milieu de l'image.", 0)
        end
        if w < voulu * 0.999 then
            remarque = string.format("Cadre réduit à %d %% de la taille demandée pour tenir dans l'image autour de ce centre.",
                math.floor(w / voulu * 100 + 0.5))
        end
    end
    local h = w / ratio

    -- Passage au repère du fichier : le centre se convertit, la largeur et la hauteur s'échangent
    -- pour un quart de tour ; l'angle ne change pas (deux rotations commutent).
    local fx, fy = (versFichier[orientation] or versFichier.AB)(cx, cy)
    local largeurFichier, hauteurFichier, wf, hf = largeur, hauteur, w, h
    if Recadrage.tournee(orientation) then
        largeurFichier, hauteurFichier, wf, hf = hauteur, largeur, h, w
    end

    -- Diagonale du cadre tourné, de son coin haut gauche à son coin bas droit, en pixels.
    local r = math.rad(angle)
    local dx = wf * math.cos(r) - hf * math.sin(r)
    local dy = wf * math.sin(r) + hf * math.cos(r)

    local function coord(valeur)
        return arrondir(borner(valeur, 0, 1), 1e6)
    end
    return {
        CropAngle = angle,
        CropLeft = coord(fx - dx / (2 * largeurFichier)),
        CropTop = coord(fy - dy / (2 * hauteurFichier)),
        CropRight = coord(fx + dx / (2 * largeurFichier)),
        CropBottom = coord(fy + dy / (2 * hauteurFichier)),
    }, remarque
end

-- Le cadre actuel (réglages Crop*) vu dans l'image affichée : {ratio, angle, centre_x, centre_y,
-- largeur} (centre de 0 à 1, largeur en pixels de l'image affichée) ; nil sans recadrage.
function Recadrage.lire(cadre, largeur, hauteur, orientation)
    largeur, hauteur = tonumber(largeur), tonumber(hauteur)
    if not largeur or not hauteur or largeur <= 0 or hauteur <= 0 then
        error("Dimensions de la photo inconnues : recadrage impossible.", 0)
    end
    cadre = cadre or {}
    local gauche, haut = tonumber(cadre.CropLeft) or 0, tonumber(cadre.CropTop) or 0
    local droite, bas = tonumber(cadre.CropRight) or 1, tonumber(cadre.CropBottom) or 1
    local angle = tonumber(cadre.CropAngle) or 0
    if math.abs(angle) < 1e-6 and math.abs(gauche) < 1e-6 and math.abs(haut) < 1e-6
        and math.abs(droite - 1) < 1e-6 and math.abs(bas - 1) < 1e-6 then
        return nil
    end
    local tournee = Recadrage.tournee(orientation)
    local lf, hf = largeur, hauteur
    if tournee then
        lf, hf = hauteur, largeur
    end
    local r = math.rad(angle)
    local dx, dy = (droite - gauche) * lf, (bas - haut) * hf
    local w, h = dx * math.cos(r) + dy * math.sin(r), -dx * math.sin(r) + dy * math.cos(r)
    if tournee then
        w, h = h, w
    end
    if w <= 0 or h <= 0 then
        return nil
    end
    -- Le centre d'un cadre tourné est le milieu de sa diagonale.
    local u, v = Recadrage.versAffichage(orientation)((gauche + droite) / 2, (haut + bas) / 2)
    return { ratio = w / h, angle = angle, centre_x = u, centre_y = v, largeur = w }
end

return Recadrage
