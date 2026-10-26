-- Images.lua : les images de la conversation (aperçus que Claude regarde, photos jointes).
-- Le décodage base64 et les réductions passent par les outils du Mac (base64, sips), lancés par
-- LrTasks.execute, qui ne bloque que la tâche en cours et pas l'interface de Lightroom.
-- À appeler depuis une tâche (LrTasks.startAsyncTask).

local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Geometrie = require 'Geometrie'
local Journal = require 'Journal'
local Json = require 'Json'
local Texte = require 'Texte'

local Images = {}

-- Fond des vignettes, proche de celui de Lightroom (l'image est centrée dans un carré).
Images.FOND = '2B2B2B'

local q = Texte.shell

local function executer(commande)
    local code = LrTasks.execute(commande)
    if code ~= 0 then
        Journal.noter("Commande en échec (" .. tostring(code) .. ") :", commande)
    end
    return code == 0
end

local function extension(typeMedia)
    if typeMedia == 'image/png' then
        return 'png'
    elseif typeMedia == 'image/webp' then
        return 'webp'
    elseif typeMedia == 'image/gif' then
        return 'gif'
    end
    return 'jpg'
end

-- Range une image reçue de Claude Code ({ donnees = base64, type }) dans le dossier de la
-- conversation ; rend son nom (chemin relatif), nil en cas d'échec.
function Images.enregistrer(image, dossier)
    Fichiers.creerDossier(dossier)
    local nom = 'image-' .. Conversation.identifiant() .. '.' .. extension(image.type)
    local destination = LrPathUtils.child(dossier, nom)
    local provisoire = destination .. '.b64'
    local f = io.open(provisoire, 'wb')
    if not f then
        return nil
    end
    f:write(image.donnees)
    f:close()
    local ok = executer('/usr/bin/base64 -D -i ' .. q(provisoire) .. ' -o ' .. q(destination))
    Fichiers.supprimer(provisoire)
    return ok and Fichiers.existe(destination) and nom or nil
end

-- Une réduction de `cote` points de côté (ou de `cote` × `hauteur`, un cadre qui n'est pas carré),
-- l'image entière centrée sur le fond (le cadre des vues du SDK ne change pas de taille) ; créée à
-- la première demande dans <dossier>/.vignettes.
function Images.vignette(dossier, nom, cote, hauteur)
    local source = LrPathUtils.child(dossier, nom)
    if not Fichiers.existe(source) then
        return nil
    end
    hauteur = hauteur or cote
    local base = LrPathUtils.removeExtension(LrPathUtils.leafName(nom))
    local fichier = hauteur == cote and (base .. '-' .. cote .. '.jpg') or string.format('%s-cadre-%dx%d.jpg', base, cote, hauteur)
    local destination = LrPathUtils.child(LrPathUtils.child(dossier, '.vignettes'), fichier)
    if Fichiers.existe(destination) then
        return destination
    end
    Fichiers.creerDossier(LrPathUtils.parent(destination))
    local reduction
    if hauteur == cote then
        reduction = string.format('/usr/bin/sips -s format jpeg -Z %d %s --out %s >/dev/null 2>&1', cote, q(source), q(destination))
    else
        -- Un cadre qui n'est pas carré : l'échelle vient des dimensions de l'image.
        local l, h = Images.dimensions(source)
        if not l or not h then
            return nil
        end
        local echelle = math.min(cote / l, hauteur / h)
        reduction = string.format('/usr/bin/sips -s format jpeg -z %d %d %s --out %s >/dev/null 2>&1',
            math.max(1, math.floor(h * echelle + 0.5)), math.max(1, math.floor(l * echelle + 0.5)), q(source), q(destination))
    end
    local ok = executer(reduction .. string.format(' && /usr/bin/sips -p %d %d --padColor %s %s --out %s >/dev/null 2>&1',
        hauteur, cote, Images.FOND, q(destination), q(destination)))
    if not ok then
        return nil
    end
    return destination
end

-- Largeur et hauteur en pixels (nil si illisible).
function Images.dimensions(chemin)
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'dimensions-' .. Conversation.identifiant() .. '.txt')
    Fichiers.creerDossier(Chemins.temporaire())
    executer('/usr/bin/sips -g pixelWidth -g pixelHeight ' .. q(chemin) .. ' > ' .. q(sortie) .. ' 2>/dev/null')
    local texte = Fichiers.lire(sortie) or ''
    Fichiers.supprimer(sortie)
    local l, h = tonumber(texte:match('pixelWidth:%s*(%d+)')), tonumber(texte:match('pixelHeight:%s*(%d+)'))
    return l, h
end

-- Une vignette toujours à l'endroit (correctif 1.3.6, retour de Dany du 25 octobre 2026). Juste
-- après une retouche, Lightroom refuse les vignettes de 512 px et plus et rend encore celle de 256
-- (Fenetre.TAILLE_SECOURS_FOCUS) ; pour une photo verticale (XH2S0407.RAF (Copie 1), 4160 × 6240),
-- elle était couchée : 320 × 213, le fichier avant le quart de tour de Lightroom, l'image de Focus et
-- d'Agrandir couchées. Les autres vignettes sont tournées (1 146 × 1 720, 573 × 860), et aucune ne
-- porte de balise d'orientation (relevé le même jour dans Temporaire/PhotoActive). Une vignette qui
-- n'a pas les proportions de la photo telle que Lightroom l'affiche (Vignettes.decrireVignette :
-- dimensions, orientation et cadre, passés par Geometrie.apercu), mais celles du fichier avant son
-- quart de tour, se tourne de ce quart de tour avant d'être montrée ou marquée (le connecteur dessine
-- ses cadres dans l'image affichée). Un demi-tour (CD) ne se voit pas aux proportions : il reste.
-- La vignette de secours peut dater d'avant la retouche (l'aperçu n'est pas refait) : une photo que
-- la retouche vient de recadrer (en 4:5, par exemple) la rend encore aux proportions de la photo
-- entière, couchée (320 × 213). Elle se compare donc aussi à la photo entière, sans le cadre
-- (dimensions de la géométrie) : couchée à l'une ou à l'autre, elle se tourne.
Images.ECART_PROPORTIONS = 0.08 -- écart toléré entre deux proportions, en logarithme (environ 8 %)

-- La rotation qui manque à une vignette de `largeur` × `hauteur` pixels (pur) : 90 ou 270, en degrés
-- dans le sens des aiguilles d'une montre (ceux de sips -r), ou nil (déjà à l'endroit, carrée,
-- proportions qui ne sont ni l'une ni l'autre, géométrie inconnue, pas de quart de tour). BC tourne
-- le fichier d'un quart dans le sens des aiguilles, DA dans l'autre (Recadrage.versAffichage).
-- D'abord le cadre actuel : debout à ce cadre, elle reste (même si elle est aussi couchée à la photo
-- entière : un portrait recadré en paysage) ; couchée à ce cadre, elle se tourne. Puis la photo
-- entière : couchée, et plus près que debout, elle se tourne (une vignette debout d'avant le cadre
-- reste).
function Images.rotationManquante(largeur, hauteur, geometrie)
    largeur, hauteur = tonumber(largeur), tonumber(hauteur)
    if not largeur or not hauteur or largeur <= 0 or hauteur <= 0 or type(geometrie) ~= 'table' then
        return nil
    end
    local quart = ({ BC = 90, DA = 270 })[geometrie.orientation]
    if not quart then
        return nil
    end
    local ok, ctx = pcall(Geometrie.contexte, geometrie.largeur, geometrie.hauteur, geometrie.orientation, geometrie.cadre)
    if not ok then
        return nil
    end
    local la, ha = Geometrie.apercu(ctx)
    if not (la > 0 and ha > 0) then
        return nil
    end
    local ecart, affichee = math.log(largeur / hauteur), math.log(la / ha)
    local droite, couchee = math.abs(ecart - affichee), math.abs(ecart + affichee)
    if droite <= Images.ECART_PROPORTIONS and droite <= couchee then
        return nil
    end
    if couchee < droite and couchee <= Images.ECART_PROPORTIONS then
        return quart
    end
    -- La photo entière (sans le cadre), affichée à `largeur` × `hauteur` de la géométrie.
    local entiere = math.log(tonumber(geometrie.largeur) / tonumber(geometrie.hauteur))
    local droiteEntiere, coucheeEntiere = math.abs(ecart - entiere), math.abs(ecart + entiere)
    if coucheeEntiere < droiteEntiere and coucheeEntiere <= Images.ECART_PROPORTIONS then
        return quart
    end
    return nil
end

-- Remet à l'endroit, sur place (sips -r), une vignette couchée de la photo de géométrie `geometrie`
-- (Images.rotationManquante). Rend son chemin, et les degrés tournés (nil : rien à tourner, ou
-- illisible).
function Images.redresser(chemin, geometrie)
    if type(chemin) ~= 'string' or not Fichiers.existe(chemin) then
        return chemin
    end
    local l, h = Images.dimensions(chemin)
    local degres = Images.rotationManquante(l, h, geometrie)
    if degres and executer(string.format('/usr/bin/sips -r %d %s --out %s >/dev/null 2>&1', degres, q(chemin), q(chemin))) then
        return chemin, degres
    end
    return chemin
end

-- Le point de mise au point d'un fichier Fujifilm dessiné sur sa vignette (l'aperçu de la photo
-- active) par le connecteur, qui lit l'original (`mcp-developpeur --marquer-af`, temps borné) :
-- `geometrie` comme la décrit Vignettes.decrireVignette. Rend le chemin de la vignette marquée
-- (`<nom>-af.jpg` à côté), ou nil : autre marque, original introuvable, point hors du cadre,
-- connecteur absent. Un échec n'est pas journalisé : sans point, l'aperçu reste sans carré.
function Images.marquerMiseAuPoint(connecteur, original, geometrie, source)
    if type(connecteur) ~= 'string' or connecteur == '' or not Fichiers.existe(connecteur)
        or type(original) ~= 'string' or type(geometrie) ~= 'table' then
        return nil
    end
    local sortie = LrPathUtils.child(LrPathUtils.parent(source), LrPathUtils.removeExtension(LrPathUtils.leafName(source)) .. '-af.jpg')
    local commande = string.format('%s --marquer-af %s %s %s %s >/dev/null 2>&1', q(connecteur), q(original), q(Json.encode(geometrie)),
        q(source), q(sortie))
    if LrTasks.execute(commande) == 0 and Fichiers.existe(sortie) then
        return sortie
    end
    return nil
end

-- L'onglet Focus (demandé par Dany le 22 octobre 2026) : le connecteur lit la mise au point dans
-- l'original d'un fichier Fujifilm (`mcp-developpeur --focus`, cinq secondes au plus par l'alarme de
-- perl ; il borne lui-même l'ouverture de l'original à 2 s), dessine ses cadres sur la
-- vignette `source` (`<nom>-focus.jpg` à côté) et répond d'une ligne JSON. Rend cette réponse
-- décodée (à lire seulement, jamais à donner à Lightroom : elle porte des métatables) et le chemin
-- de la vignette marquée (nil sans dessin) ; nil : connecteur absent, original inconnu, rien de lu,
-- pas de réponse lisible. Rien de lu, le connecteur dit pourquoi (`{"lue": false, "raison": …}`,
-- code 1) : nil, nil et cette raison, l'une d'Images.RAISONS_FOCUS. `source` nil : les valeurs
-- seules.
Images.RAISONS_FOCUS = {
    delai = true, -- l'original ne s'est pas ouvert à temps (2 s, LecteurBoitier)
    introuvable = true, -- pas de fichier à ce chemin
    illisible = true, -- ouvert à temps, sans rien que la lecture sache lire (HEIF, données de l'appareil absentes)
}

function Images.lireFocus(connecteur, original, geometrie, source)
    if type(connecteur) ~= 'string' or connecteur == '' or not Fichiers.existe(connecteur)
        or type(original) ~= 'string' or original == '' then
        return nil
    end
    local dossier = source and LrPathUtils.parent(source) or Chemins.temporaire()
    local base = source and LrPathUtils.removeExtension(LrPathUtils.leafName(source)) or ('focus-' .. Conversation.identifiant())
    local sortie = LrPathUtils.child(dossier, base .. '-focus.jpg')
    local reponse = LrPathUtils.child(dossier, base .. '-focus.json')
    Fichiers.creerDossier(dossier)
    Fichiers.supprimer(sortie)
    LrTasks.execute(string.format("/usr/bin/perl -e 'alarm 5; exec @ARGV' %s --focus %s %s %s %s > %s 2>/dev/null", q(connecteur), q(original),
        q(Json.encode(type(geometrie) == 'table' and geometrie or {})), q(source or LrPathUtils.child(dossier, base .. '-absente.jpg')),
        q(sortie), q(reponse)))
    local texte = Fichiers.lire(reponse) or ''
    Fichiers.supprimer(reponse)
    local ok, json = pcall(Json.decode, texte)
    if not ok or type(json) ~= 'table' or json.lue ~= true then
        local raison = ok and type(json) == 'table' and json.lue == false and json.raison
        return nil, nil, (type(raison) == 'string' and Images.RAISONS_FOCUS[raison]) and raison or nil
    end
    return json, (json.dessinee == true and Fichiers.existe(sortie)) and sortie or nil
end

-- La version à montrer en grand (Agrandir), qui remplit largeurMax × hauteurMax à ses proportions :
-- chemin, largeur, hauteur. Une image plus grande est réduite, une plus petite agrandie (un peu plus
-- douce, jamais minuscule : retour de Dany du 25 octobre 2026, qui voyait la vignette de secours de
-- 320 × 213 à sa vraie taille), par sips, rangée dans .vignettes à côté ; une image qui a déjà la
-- taille : son propre chemin. nil : illisible.
function Images.grande(dossier, nom, largeurMax, hauteurMax)
    local source = LrPathUtils.child(dossier, nom)
    local l, h = Images.dimensions(source)
    if not l or not h then
        return nil
    end
    local echelle = math.min(largeurMax / l, hauteurMax / h)
    local lf = math.max(1, math.min(largeurMax, math.floor(l * echelle + 0.5)))
    local hf = math.max(1, math.min(hauteurMax, math.floor(h * echelle + 0.5)))
    if lf == l and hf == h then
        return source, l, h
    end
    local base = LrPathUtils.removeExtension(LrPathUtils.leafName(nom))
    local destination = LrPathUtils.child(LrPathUtils.child(dossier, '.vignettes'), string.format('%s-%dx%d.jpg', base, lf, hf))
    if not Fichiers.existe(destination) then
        Fichiers.creerDossier(LrPathUtils.parent(destination))
        if not executer(string.format('/usr/bin/sips -s format jpeg -z %d %d %s --out %s >/dev/null 2>&1', hf, lf, q(source), q(destination))) then
            return nil
        end
    end
    return destination, lf, hf
end

-- Une photo du disque jointe à une demande : réduite à 1568 points au plus (la taille que Claude
-- regarde), copiée dans le dossier de la conversation. Rend son nom et l'image pour Claude
-- ({ donnees = base64, type }), ou nil et la raison.
function Images.joindre(chemin, dossier)
    Fichiers.creerDossier(dossier)
    local nom = 'jointe-' .. Conversation.identifiant() .. '.jpg'
    local destination = LrPathUtils.child(dossier, nom)
    if not executer(string.format('/usr/bin/sips -s format jpeg -s formatOptions 85 -Z 1568 %s --out %s >/dev/null 2>&1', q(chemin), q(destination))) then
        return nil, "Image illisible : " .. LrPathUtils.leafName(chemin)
    end
    local b64 = destination .. '.b64'
    executer('/usr/bin/base64 -i ' .. q(destination) .. ' -o ' .. q(b64))
    local donnees = Fichiers.lire(b64)
    Fichiers.supprimer(b64)
    if not donnees or donnees == '' then
        return nil, "Image illisible : " .. LrPathUtils.leafName(chemin)
    end
    return nom, { donnees = (donnees:gsub('%s', '')), type = 'image/jpeg' }
end

-- Les images du presse-papiers du Mac (presse-papiers.js) : fichiers d'image copiés dans le Finder,
-- ou image copiée (capture d'écran…) écrite dans Temporaire/Collees. Rend la liste des chemins
-- (vide s'il n'y a pas d'image). `nomPressePapiers` : un presse-papiers nommé (essais).
function Images.coller(nomPressePapiers)
    local dossier = Fichiers.creerDossier(LrPathUtils.child(Chemins.temporaire(), 'Collees'))
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'presse-papiers-' .. Conversation.identifiant() .. '.txt')
    executer(string.format('/usr/bin/osascript -l JavaScript %s %s %s > %s 2>/dev/null', q(Chemins.ressource('presse-papiers.js')),
        q(dossier), nomPressePapiers and q(nomPressePapiers) or '', q(sortie)))
    local texte = Fichiers.lire(sortie) or ''
    Fichiers.supprimer(sortie)
    local chemins = {}
    for ligne in texte:gmatch('[^\n]+') do
        local chemin = Texte.nettoyer(ligne)
        if chemin ~= '' and Fichiers.existe(chemin) then
            chemins[#chemins + 1] = chemin
        end
    end
    return chemins
end

return Images
