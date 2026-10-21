-- essais-images.lua : les images de la fenêtre B, hors de Lightroom (LuaJIT) : Dispositions.IMAGES,
-- seule source de leurs tailles en points, aux tailles de la maquette « B · Conversation claire » ;
-- chaque image dans images/, un seul PNG en 2x (2 × la taille en points, en-tête IHDR lu en Lua pur)
-- à 144 ppp (bloc pHYs : 5 669 pixels par mètre), sans image de trop ni paire @2x, et ce contrôle
-- lui-même, sur des PNG fabriqués ; l'image « aucun aperçu » du cadre 3:2 (vide-330x220.png,
-- 660 × 440) ; scripts/gabarits.lua, qui écrit Dispositions.IMAGES en JSON pour
-- scripts/images-fenetre.swift ; et ce script lui-même, lancé sur un module d'essai d'un dossier
-- temporaire (jamais sur celui du dépôt) : ce qu'il produit, et ses refus. Ni Lightroom, ni Claude.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local Dispositions = require 'Dispositions'
local Json = require 'Json'

local IMAGES = Dispositions.IMAGES
local DOSSIER = S.plugin .. '/images'
local RACINE = S.plugin:match('^(.*)/Lightroom/Developpeur%.lrplugin/?$')

-- 144 ppp en pixels par mètre (144 / 0,0254, arrondi comme l'écrit ImageIO).
local PPM_144 = 5669

-- Les images de la fenêtre B et leurs tailles en points, d'après la maquette : { largeur, hauteur }.
-- Les hauteurs du panneau et des cartes, recalées au lot 18, ne sont pas fixées ici : la largeur
-- seule (colonne droite de 435, intérieur du panneau de 405).
local ATTENDUES = {
    panneau = { 435 },
    ['carte-note'] = { 405 },
    ['carte-proposition'] = { 405 },
    ['carte-etape'] = { 405 },
    ['carte-lecon'] = { 405 },
    ['seg-apercu'] = { 72, 22 },
    ['seg-proposition'] = { 98, 22 },
    ['seg-note'] = { 57, 22 },
    ['seg-lecon'] = { 65, 22 },
    ['seg-apercu-actif'] = { 72, 22 },
    ['seg-proposition-actif'] = { 98, 22 },
    ['seg-note-actif'] = { 57, 22 },
    ['seg-lecon-actif'] = { 65, 22 },
    selection = { 163, 40 },
    ['pastille-vert'] = { 8, 8 },
    ['pastille-orange'] = { 8, 8 },
    ['pastille-rouge'] = { 8, 8 },
    ['pastille-gris'] = { 8, 8 },
    ['bouton-bleu'] = { 120, 26 },
    ['bouton-bleu-presse'] = { 120, 26 },
    ['bouton-bleu-inactif'] = { 120, 26 },
    ['etoile24-pleine'] = { 24, 24 },
    ['etoile24-vide'] = { 24, 24 },
    ['etoile12-pleine'] = { 12, 12 },
    ['etoile12-vide'] = { 12, 12 },
    ['coche-10'] = { 10, 10 },
    ['chevron-passe'] = { 7, 8 },
    avertissement = { 14, 14 },
    loupe = { 12, 12 },
    trombone = { 14, 14 },
    ['presse-papiers'] = { 14, 14 },
    ['chevron-haut'] = { 12, 12 },
    ['chevron-bas'] = { 12, 12 },
}

-- Les images qui vont par groupe (variantes d'un même contrôle) ont la même taille.
local GROUPES = {
    { 'seg-apercu', 'seg-apercu-actif' },
    { 'seg-proposition', 'seg-proposition-actif' },
    { 'seg-note', 'seg-note-actif' },
    { 'seg-lecon', 'seg-lecon-actif' },
    { 'bouton-bleu', 'bouton-bleu-presse', 'bouton-bleu-inactif' },
    { 'etoile24-pleine', 'etoile24-vide' },
    { 'etoile12-pleine', 'etoile12-vide' },
    { 'pastille-vert', 'pastille-orange', 'pastille-rouge', 'pastille-gris' },
    { 'carte-proposition', 'carte-etape', 'carte-lecon' },
    { 'trombone', 'presse-papiers' },
    { 'chevron-haut', 'chevron-bas' },
}

-- Lecture d'un PNG en Lua pur : sa signature, puis ses blocs. Rend { blocs, largeur, hauteur,
-- profondeur, couleur, ppmX, ppmY, unite }, ou nil et la raison.
local function lirePng(chemin)
    local f = io.open(chemin, 'rb')
    if not f then
        return nil, 'introuvable : ' .. chemin
    end
    local donnees = f:read('*a')
    f:close()
    if donnees:sub(1, 8) ~= '\137PNG\r\n\26\n' then
        return nil, "pas un PNG (signature) : " .. chemin
    end
    local function entier(i)
        local a, b, c, d = donnees:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    local png, i = { blocs = {} }, 9
    while i + 7 <= #donnees do
        local longueur, genre = entier(i), donnees:sub(i + 4, i + 7)
        local debut = i + 8
        png.blocs[#png.blocs + 1] = genre
        if genre == 'IHDR' then
            png.largeur, png.hauteur = entier(debut), entier(debut + 4)
            png.profondeur, png.couleur = donnees:byte(debut + 8), donnees:byte(debut + 9)
        elseif genre == 'pHYs' then
            png.ppmX, png.ppmY, png.unite = entier(debut), entier(debut + 4), donnees:byte(debut + 8)
        end
        i = debut + longueur + 4
        if genre == 'IEND' then
            break
        end
    end
    return png
end

-- Le contrôle d'une image de la fenêtre : un PNG en 2x de `largeur` × `hauteur` points, à 144 ppp,
-- en RGBA sur 8 bits (la bande du panneau et le tour des icônes sont transparents). Rend nil, ou
-- la raison du refus.
local function controler(chemin, largeur, hauteur)
    local png, raison = lirePng(chemin)
    if not png then
        return raison
    end
    if png.blocs[1] ~= 'IHDR' then
        return 'IHDR n\'est pas le premier bloc : ' .. chemin
    end
    if png.largeur ~= 2 * largeur or png.hauteur ~= 2 * hauteur then
        return string.format('%s : %d × %d px, attendu %d × %d (2 × %d × %d points)', chemin, png.largeur, png.hauteur,
            2 * largeur, 2 * hauteur, largeur, hauteur)
    end
    if png.profondeur ~= 8 or png.couleur ~= 6 then
        return string.format('%s : profondeur %d, couleur %d (RGBA 8 bits attendu)', chemin, png.profondeur, png.couleur)
    end
    if not png.ppmX then
        return 'sans bloc pHYs (144 ppp attendus) : ' .. chemin
    end
    if png.unite ~= 1 or png.ppmX ~= PPM_144 or png.ppmY ~= PPM_144 then
        return string.format('%s : pHYs %d × %d (unité %d), attendu %d pixels par mètre (144 ppp)', chemin, png.ppmX,
            png.ppmY, png.unite, PPM_144)
    end
    return nil
end

essai('Dispositions.IMAGES : les images de la fenêtre B, aux tailles de la maquette', function()
    vrai(type(IMAGES) == 'table' and getmetatable(IMAGES) == nil, 'une table simple')
    for nom, attendue in pairs(ATTENDUES) do
        local t = IMAGES[nom]
        vrai(t, 'image absente de Dispositions.IMAGES : ' .. nom)
        egal(attendue[1], t.largeur, nom .. ' : largeur')
        if attendue[2] then
            egal(attendue[2], t.hauteur, nom .. ' : hauteur')
        end
    end
    -- Rien de plus : ni fond ni filet (des aplats), ni pastille bleue (le voyant Mode est retiré).
    local deja = {}
    for nom, t in pairs(IMAGES) do
        vrai(ATTENDUES[nom], 'image en trop dans Dispositions.IMAGES : ' .. tostring(nom))
        vrai(type(t) == 'table' and getmetatable(t) == nil, nom .. ' : une table simple')
        vrai(not deja[t], nom .. ' : une table neuve, à elle seule')
        deja[t] = true
        for _, cote in ipairs({ 'largeur', 'hauteur' }) do
            local v = t[cote]
            vrai(type(v) == 'number' and v > 0 and v == math.floor(v), nom .. ' : ' .. cote .. ' entière et positive')
        end
    end
    -- Le panneau garde sa bande transparente de 12 au-dessus de son bord ; les cartes y tiennent.
    vrai(IMAGES.panneau.hauteur > 12 + IMAGES['carte-proposition'].hauteur, 'le panneau plus haut que ses cartes')
    vrai(IMAGES['carte-note'].hauteur > 0 and IMAGES['carte-note'].hauteur < IMAGES.panneau.hauteur, 'la carte Note')
    for _, groupe in ipairs(GROUPES) do
        local premiere = IMAGES[groupe[1]]
        for k = 2, #groupe do
            egal(premiere.largeur, IMAGES[groupe[k]].largeur, groupe[k] .. ' : largeur de ' .. groupe[1])
            egal(premiere.hauteur, IMAGES[groupe[k]].hauteur, groupe[k] .. ' : hauteur de ' .. groupe[1])
        end
    end
end)

essai('images/ : chaque image de Dispositions.IMAGES, un PNG en 2x à 144 ppp', function()
    local nombre = 0
    for nom, t in pairs(IMAGES) do
        local raison = controler(DOSSIER .. '/' .. nom .. '.png', t.largeur, t.hauteur)
        vrai(raison == nil, raison)
        nombre = nombre + 1
    end
    vrai(nombre >= 33, 'les 33 images au moins')
end)

-- Un PNG fabriqué pour éprouver le contrôle : signature, IHDR (RGBA 8 bits), pHYs si `ppm` est
-- donné, IEND ; les sommes de contrôle sont nulles (lirePng ne les lit pas).
local function fabriquerPng(chemin, largeur, hauteur, ppm)
    local function entier(n)
        return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
    end
    local function bloc(genre, donnees)
        return entier(#donnees) .. genre .. donnees .. '\0\0\0\0'
    end
    local octets = '\137PNG\r\n\26\n' .. bloc('IHDR', entier(largeur) .. entier(hauteur) .. '\8\6\0\0\0')
    if ppm then
        octets = octets .. bloc('pHYs', entier(ppm) .. entier(ppm) .. '\1')
    end
    local f = assert(io.open(chemin, 'wb'))
    f:write(octets .. bloc('IEND', ''))
    f:close()
    return chemin
end

essai('Le contrôle des images refuse un fichier qui n\'est pas un PNG, un PNG en 1x ou d\'une autre taille', function()
    vrai(controler(S.plugin .. '/Dispositions.lua', 10, 10):find('pas un PNG', 1, true), 'un fichier Lua')
    vrai(controler(DOSSIER .. '/absente.png', 10, 10):find('introuvable', 1, true), 'une image absente')
    -- Le bon nombre de pixels pour 10 × 10 points, mais en 1x : à 72 ppp, ou sans bloc pHYs.
    egal(nil, controler(fabriquerPng(S.home .. '/2x.png', 20, 20, PPM_144), 10, 10), 'le PNG fabriqué en 2x')
    vrai(controler(fabriquerPng(S.home .. '/72ppp.png', 20, 20, 2835), 10, 10):find('144 ppp', 1, true), 'un PNG à 72 ppp')
    vrai(controler(fabriquerPng(S.home .. '/sans-phys.png', 20, 20), 10, 10):find('pHYs', 1, true), 'un PNG sans pHYs')
    -- Une image en 1x de 20 × 20 points : la moitié des pixels attendus.
    vrai(controler(S.home .. '/2x.png', 20, 20):find('attendu 40', 1, true), 'un PNG en 1x de cette taille')
    vrai(controler(DOSSIER .. '/loupe.png', IMAGES.loupe.largeur * 2, IMAGES.loupe.hauteur * 2):find('attendu', 1, true),
        'une autre taille')
end)

essai('images/ : aucune image hors de Dispositions.IMAGES, ni paire @2x', function()
    local fichiers = 0
    for fichier in S.lireCommande('ls -1 ' .. S.q(DOSSIER)):gmatch('[^\n]+') do
        fichiers = fichiers + 1
        vrai(not fichier:find('@', 1, true), 'pas de paire 1x et @2x : ' .. fichier)
        local nom = fichier:match('^(.+)%.png$')
        vrai(nom, 'seulement des PNG dans images/ : ' .. fichier)
        vrai(IMAGES[nom], 'image absente de Dispositions.IMAGES : images/' .. fichier)
    end
    local nombre = 0
    for _ in pairs(IMAGES) do
        nombre = nombre + 1
    end
    egal(nombre, fichiers, 'une image par nom de Dispositions.IMAGES')
end)

essai('vide-330x220.png : l\'image « aucun aperçu » du cadre 3:2, 660 × 440 à 144 ppp', function()
    local raison = controler(S.plugin .. '/vide-330x220.png', 330, 220)
    vrai(raison == nil, raison)
    local png = lirePng(S.plugin .. '/vide-330x220.png')
    egal(660, png.largeur, 'largeur en pixels')
    egal(440, png.hauteur, 'hauteur en pixels')
end)

essai('scripts/gabarits.lua : Dispositions.IMAGES en JSON, lancé depuis un autre dossier', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    -- Lancé ici (Tests/Lua/Fenetre), pas depuis la racine : il trouve le module par son propre chemin.
    local sortie = S.lireCommande('luajit ' .. S.q(RACINE .. '/scripts/gabarits.lua') .. ' 2>&1')
    local ok, lu = pcall(Json.decode, sortie)
    vrai(ok and type(lu) == 'table', 'JSON lisible : ' .. sortie)
    for nom, t in pairs(IMAGES) do
        vrai(type(lu[nom]) == 'table', 'absente du JSON : ' .. nom)
        egal(t.largeur, lu[nom].largeur, nom .. ' : largeur')
        egal(t.hauteur, lu[nom].hauteur, nom .. ' : hauteur')
    end
    for nom in pairs(lu) do
        vrai(IMAGES[nom], 'en trop dans le JSON : ' .. tostring(nom))
    end
end)

-- scripts/images-fenetre.swift lancé par l'usage documenté (gabarits.lua sur son entrée), mais vers
-- un module d'essai du dossier temporaire, jamais vers celui du dépôt. Rend son code de sortie et ce
-- qu'il a écrit (sortie et erreurs mêlées).
local function produire(entree, module)
    local sortie = S.lireCommande(entree .. ' | swift ' .. S.q(RACINE .. '/scripts/images-fenetre.swift') .. ' '
        .. S.q(module) .. ' 2>&1; echo "code $?"')
    return tonumber(sortie:match('code (%d+)%s*$')), sortie
end

essai('scripts/images-fenetre.swift : chaque image en 2x à 144 ppp, une image de trop gardée', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    local gabarits = 'luajit ' .. S.q(RACINE .. '/scripts/gabarits.lua')
    local module = S.home .. '/module-images'
    local code, sortie = produire(gabarits, module)
    egal(0, code, 'production entière : ' .. sortie)
    -- Chaque image produite passe le contrôle des images du module : 2 × la taille en points, RGBA
    -- 8 bits, 144 ppp.
    for nom, t in pairs(IMAGES) do
        local raison = controler(module .. '/images/' .. nom .. '.png', t.largeur, t.hauteur)
        vrai(raison == nil, raison)
    end
    -- Une image de images/ absente de Dispositions.IMAGES est signalée, jamais effacée.
    local orpheline = fabriquerPng(module .. '/images/orpheline.png', 2, 2, PPM_144)
    code, sortie = produire(gabarits, module)
    egal(0, code, 'production avec une image de trop : ' .. sortie)
    vrai(sortie:find('à retirer : images/orpheline.png', 1, true), 'image de trop signalée : ' .. sortie)
    vrai(lirePng(orpheline), 'image de trop gardée')
end)

essai('scripts/images-fenetre.swift : refuse sans rien écrire un nom sans dessin, une taille invalide, une entrée vide', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    local function json(texte)
        return "printf '%s' " .. S.q(texte)
    end
    -- Chaque refus vient avant toute écriture : la loupe, connue et bien taillée, n'est pas écrite
    -- non plus, et le dossier du module n'est pas créé.
    local cas = {
        { json('{"loupe":{"largeur":12,"hauteur":12},"inconnue":{"largeur":12,"hauteur":12}}'),
            'aucun dessin pour : inconnue' },
        { json('{"loupe":{"largeur":12,"hauteur":12},"trombone":{"largeur":0,"hauteur":14}}'),
            'taille invalide pour trombone' },
        { "printf ''", "rien sur l'entrée standard" },
        { json('pas du JSON'), 'tailles illisibles' },
    }
    for k, c in ipairs(cas) do
        local module = S.home .. '/module-refus-' .. k
        local code, sortie = produire(c[1], module)
        egal(1, code, c[2] .. ' : code de sortie (' .. sortie .. ')')
        vrai(sortie:find(c[2], 1, true), c[2] .. ' : ' .. sortie)
        vrai(not S.executer('test -e ' .. S.q(module)), c[2] .. ' : rien d\'écrit')
    end
end)

-- Fin -------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
