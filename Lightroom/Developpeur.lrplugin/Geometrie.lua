-- Geometrie.lua : passage d'une position de l'image que montre view_photo (recadrée, tournée,
-- orientée) au repère où Lightroom range masques et retouches de taches : le fichier entier,
-- non recadré, avant l'orientation, de 0 à 1. Le cadre suit le modèle constaté pour le
-- recadrage (Recadrage.lua) : ses coins haut gauche et bas droit, tourné de CropAngle.
-- Ce repère est aussi celui d'avant la correction de profil d'objectif, Upright et la
-- perspective (constaté dans Lightroom Classic 15.6 : jusqu'à 26 px au bord d'un RAW de 6240 px) ;
-- le serveur mesure ce déplacement (Recalage.swift) et le donne en grille (recalage), que l'on
-- interpole ici. Pas de dépendance au SDK : testé tel quel.

local Recadrage = require 'Recadrage'

local Geometrie = {}

-- Grille de recalage valide, ou nil : pour chaque nœud d'une grille posée sur l'image affichée
-- non recadrée (colonnes × lignes, ligne par ligne depuis le haut), la position correspondante
-- dans l'image d'avant les corrections géométriques, de 0 à 1.
function Geometrie.grille(r)
    if type(r) ~= 'table' then
        return nil
    end
    local n, m = tonumber(r.colonnes), tonumber(r.lignes)
    if not n or not m or n < 2 or m < 2 or type(r.x) ~= 'table' or type(r.y) ~= 'table'
        or #r.x ~= n * m or #r.y ~= n * m then
        return nil
    end
    for k = 1, n * m do
        if not tonumber(r.x[k]) or not tonumber(r.y[k]) then
            return nil
        end
    end
    return { colonnes = n, lignes = m, x = r.x, y = r.y }
end

-- Interpolation bilinéaire de la grille en (u, v), comme Recalage.Grille.point du serveur.
function Geometrie.interpoler(g, u, v)
    local fu = math.min(math.max(u, 0), 1) * (g.colonnes - 1)
    local fv = math.min(math.max(v, 0), 1) * (g.lignes - 1)
    local i = math.min(math.floor(fu), g.colonnes - 2)
    local j = math.min(math.floor(fv), g.lignes - 2)
    local a, b = fu - i, fv - j
    local k = j * g.colonnes + i + 1
    local function valeur(t)
        return tonumber(t[k]) * (1 - a) * (1 - b) + tonumber(t[k + 1]) * a * (1 - b)
            + tonumber(t[k + g.colonnes]) * (1 - a) * b + tonumber(t[k + g.colonnes + 1]) * a * b
    end
    return valeur(g.x), valeur(g.y)
end

-- Partie de l'image affichée entière qui montre la photo : Upright, la perspective et la
-- distorsion manuelle laissent ailleurs des coins vides, rendus en blanc (constaté dans Lightroom
-- Classic 15.6). Un point montre la photo si la grille le ramène dans l'image d'avant les
-- corrections ; la marge (en part de l'image) couvre l'interpolation de la grille et le bord
-- adouci du rendu. Renvoie une fonction (u, v) → vrai, pour Recadrage.calculer, ou nil.
Geometrie.MARGE_ZONE = 0.002

function Geometrie.zone(recalage)
    local g = Geometrie.grille(recalage)
    if not g then
        return nil
    end
    local m = Geometrie.MARGE_ZONE
    return function(u, v)
        local x, y = Geometrie.interpoler(g, u, v)
        return x >= m and x <= 1 - m and y >= m and y <= 1 - m
    end
end

-- largeur, hauteur : dimensions de la photo affichée, non recadrée, en pixels
-- orientation : 'AB', 'BC', 'CD' ou 'DA'
-- cadre : réglages Crop* actuels (absents : pas de recadrage)
-- recalage : grille venue du serveur (absente : pas de correction géométrique à suivre)
function Geometrie.contexte(largeur, hauteur, orientation, cadre, recalage)
    largeur, hauteur = tonumber(largeur), tonumber(hauteur)
    if not largeur or not hauteur or largeur <= 0 or hauteur <= 0 then
        error("Dimensions de la photo inconnues : position impossible à calculer.", 0)
    end
    cadre = cadre or {}
    local tournee = Recadrage.tournee(orientation)
    local lf, hf = largeur, hauteur
    if tournee then
        lf, hf = hauteur, largeur
    end
    local gauche, haut = tonumber(cadre.CropLeft) or 0, tonumber(cadre.CropTop) or 0
    local droite, bas = tonumber(cadre.CropRight) or 1, tonumber(cadre.CropBottom) or 1
    local angle = tonumber(cadre.CropAngle) or 0
    local r = math.rad(angle)
    local dx, dy = (droite - gauche) * lf, (bas - haut) * hf
    return {
        orientation = orientation,
        convertir = Recadrage.versFichier(orientation),
        tournee = tournee,
        lf = lf, hf = hf,
        x0 = gauche * lf, y0 = haut * hf,
        -- Largeur et hauteur du cadre dans son propre repère, en pixels du fichier.
        w = dx * math.cos(r) + dy * math.sin(r),
        h = -dx * math.sin(r) + dy * math.cos(r),
        cos = math.cos(r), sin = math.sin(r),
        angle = angle,
        largeurAffichee = largeur, hauteurAffichee = hauteur,
        recalage = Geometrie.grille(recalage),
        versAffichage = Recadrage.versAffichage(orientation),
        versFichierEntier = Recadrage.versFichier(orientation),
    }
end

-- Point de l'aperçu (p, q de 0 à 1 depuis le coin haut gauche) → point du fichier (0 à 1).
function Geometrie.point(ctx, p, q)
    local s, t = ctx.convertir(p, q)
    local x = ctx.x0 + s * ctx.w * ctx.cos - t * ctx.h * ctx.sin
    local y = ctx.y0 + s * ctx.w * ctx.sin + t * ctx.h * ctx.cos
    if not ctx.recalage then
        return x / ctx.lf, y / ctx.hf
    end
    -- La grille est posée sur l'image affichée entière : on y passe, puis on revient au fichier.
    local u, v = ctx.versAffichage(x / ctx.lf, y / ctx.hf)
    u, v = Geometrie.interpoler(ctx.recalage, u, v)
    return ctx.versFichierEntier(u, v)
end

-- Plus grand déplacement de la grille de recalage, en pixels de la photo affichée.
function Geometrie.ecart(ctx)
    local g = ctx.recalage
    if not g then
        return 0
    end
    local plus = 0
    for j = 0, g.lignes - 1 do
        for i = 0, g.colonnes - 1 do
            local k = j * g.colonnes + i + 1
            local dx = (tonumber(g.x[k]) - i / (g.colonnes - 1)) * ctx.largeurAffichee
            local dy = (tonumber(g.y[k]) - j / (g.lignes - 1)) * ctx.hauteurAffichee
            plus = math.max(plus, math.sqrt(dx * dx + dy * dy))
        end
    end
    return plus
end

-- Largeur et hauteur de l'aperçu, en pixels du fichier.
function Geometrie.apercu(ctx)
    if ctx.tournee then
        return ctx.h, ctx.w
    end
    return ctx.w, ctx.h
end

-- Une longueur donnée en part de la largeur de l'aperçu, en pixels du fichier.
function Geometrie.pixels(ctx, partDeLaLargeur)
    local largeur = Geometrie.apercu(ctx)
    return partDeLaLargeur * largeur
end

-- Demi-axes d'une ellipse de l'aperçu (en pixels) dans le repère du fichier : l'axe horizontal
-- de l'aperçu est vertical dans le fichier pour un quart de tour.
function Geometrie.axes(ctx, rx, ry)
    if ctx.tournee then
        return ry, rx
    end
    return rx, ry
end

return Geometrie
