-- essais-images.lua : les images de la fenêtre B, hors de Lightroom (LuaJIT) : Dispositions.IMAGES,
-- seule source de leurs tailles en points, aux tailles de la maquette « B · Conversation claire » ;
-- ses deux apparences, claire et sombre (Dispositions.APPARENCES, Dispositions.PALETTES : mêmes
-- clés, la claire de la maquette, la sombre au moins aussi lisible), Dispositions.apparence (une
-- valeur inconnue retombe sur la claire), Dispositions.image et Dispositions.couleurs ; chaque
-- image dans les deux jeux (images/ et images/sombre/), un seul PNG en 2x (2 × la taille en points,
-- en-tête IHDR lu en Lua pur) à 144 ppp (bloc pHYs : 5 669 pixels par mètre), aux mêmes tailles,
-- la sombre autre que la claire, sans image de trop ni paire @2x, et ce contrôle lui-même, sur des
-- PNG fabriqués ; l'image « aucun aperçu » du cadre 3:2 (vide-330x220.png, 660 × 440), dans le jeu
-- de chaque apparence ; scripts/gabarits.lua, qui écrit Dispositions.gabarits en JSON pour
-- scripts/images-fenetre.swift et scripts/images-vides.swift ; et ces scripts eux-mêmes, lancés sur
-- un module d'essai d'un dossier temporaire (jamais sur celui du dépôt) : ce qu'ils produisent, et
-- leurs refus. Ni Lightroom, ni Claude.
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

-- Les dossiers des deux jeux, depuis le dossier du module : la claire là où étaient les images de
-- la 1.3 avant les apparences, la sombre à côté.
local JEUX = { claire = 'images', sombre = 'images/sombre' }

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

-- Apparences ------------------------------------------------------------------------------------

-- La palette claire est celle de la maquette (et, pour l'orange, le rouge et Menlo, celle de la
-- fenêtre de la 1.2) : les images claires n'ont pas changé en recevant une palette.
local MAQUETTE = {
    texte = '1D1D1F', gris = '6B6B6B', grisEntete = '5F5F5F', sousTitreChoisi = '505050', bleu = '0A64D8',
    mono = '3D3D45', coche = '1F7A35', orange = 'E0800D', rouge = 'D12E2E', ambre = 'A86200', blanc = 'FFFFFF',
    fondContenu = 'FFFFFF', fondVolet = 'F2F2F2', fondDroite = 'ECECEC',
    filetVolet = 'D2D2D2', filetDroite = 'C9C9C9', filetEntete = 'E2E2E2', filetBarre = 'EBEBEB', filetPlafond = 'E3E3E3',
    fondPanneau = 'FFFFFF', bordPanneau = 'C9C9C9', fondCarte = 'FAFAFA', bordCarte = 'D9D9D9',
    fondSegment = 'FFFFFF', bordSegment = 'B5B5B5', filetSegment = 'D0D0D0', selection = 'DADADA',
    pastille = '2DA44E', contour = '8A8A8A', bleuBouton = '0A64D8', bordBleu = '0A5BC4', bleuPresse = '084A9E',
    bleuInactif = '9DBDEB', bordBleuInactif = '88AEE2',
    -- Lot B3 : le fond de l'aperçu (#2B2B2B de la maquette, celui des vignettes), le texte de
    -- l'image « aucun aperçu » (celui de la 1.2, blanc à 62 %) et le titre d'un bouton bleu inactif
    -- (blanc, sur l'image pâlie).
    fondApercu = '2B2B2B', texteApercu = '9E9E9E', titreInactif = 'FFFFFF',
}

local function cles(t)
    local r = {}
    for k in pairs(t) do
        r[#r + 1] = k
    end
    table.sort(r)
    return table.concat(r, ' ')
end

essai('Apparences : claire puis sombre, une palette chacune, aux mêmes clés, en RRGGBB', function()
    local A = Dispositions.APPARENCES
    egal(2, #A, 'deux apparences')
    egal('claire', A[1].value, 'la claire en premier : celle par défaut')
    egal('sombre', A[2].value)
    for _, a in ipairs(A) do
        egal(JEUX[a.value], a.dossier, a.value .. ' : dossier de ses images')
        vrai(type(a.title) == 'string' and a.title ~= '', a.value .. ' : titre du menu')
        vrai(type(Dispositions.PALETTES[a.value]) == 'table', a.value .. ' : sa palette')
    end
    egal(cles(MAQUETTE), cles(Dispositions.PALETTES.claire), 'clés de la palette claire')
    egal(cles(MAQUETTE), cles(Dispositions.PALETTES.sombre), 'clés de la palette sombre')
    for nom, palette in pairs(Dispositions.PALETTES) do
        vrai(JEUX[nom], 'palette sans apparence : ' .. tostring(nom))
        for cle, hex in pairs(palette) do
            vrai(type(hex) == 'string' and hex:match('^%x%x%x%x%x%x$'), nom .. '.' .. cle .. ' : RRGGBB, obtenu ' .. tostring(hex))
        end
    end
    for cle, hex in pairs(MAQUETTE) do
        egal(hex, Dispositions.PALETTES.claire[cle], 'claire.' .. cle .. ' (maquette)')
    end
end)

essai('Dispositions.apparence : la valeur connue, sinon la claire ; le menu Apparence en tables neuves', function()
    egal('claire', Dispositions.apparence('claire'))
    egal('sombre', Dispositions.apparence('sombre'))
    -- Une préférence absente, d'une autre version ou abîmée retombe sur la claire.
    for _, inconnue in ipairs({ 'bleue', 'Sombre', 'auto', '', 0, true }) do
        egal('claire', Dispositions.apparence(inconnue), 'valeur inconnue : ' .. tostring(inconnue))
    end
    egal('claire', Dispositions.apparence(nil), 'sans préférence')
    local items = Dispositions.itemsApparences()
    egal(2, #items)
    egal('Claire', items[1].title)
    egal('claire', items[1].value)
    egal('Sombre', items[2].title)
    egal('sombre', items[2].value)
    egal(nil, items[1].dossier, 'le menu ne porte que titre et valeur')
    vrai(items ~= Dispositions.itemsApparences() and items[1] ~= Dispositions.itemsApparences()[1], 'tables neuves')
    vrai(getmetatable(items) == nil and items[1] ~= Dispositions.APPARENCES[1], 'pas les tables de Dispositions')
end)

essai('Dispositions.image : le chemin du jeu de l\'apparence, la claire pour une valeur inconnue', function()
    egal('images/loupe.png', Dispositions.image('loupe', 'claire'))
    egal('images/sombre/loupe.png', Dispositions.image('loupe', 'sombre'))
    egal('images/seg-note-actif.png', Dispositions.image('seg-note-actif', 'bleue'), 'valeur inconnue')
    egal('images/panneau.png', Dispositions.image('panneau'), 'sans apparence')
    -- Chaque chemin rendu existe dans le module, pour chaque image et chaque apparence.
    for nom in pairs(IMAGES) do
        for apparence in pairs(JEUX) do
            local chemin = Dispositions.image(nom, apparence)
            egal(JEUX[apparence] .. '/' .. nom .. '.png', chemin)
            vrai(S.executer('test -f ' .. S.q(S.plugin .. '/' .. chemin)), 'introuvable dans le module : ' .. chemin)
        end
    end
    -- Une image inconnue est une erreur, qui nomme l'image.
    local ok, erreur = pcall(Dispositions.image, 'pastille-bleu', 'sombre')
    vrai(not ok and tostring(erreur):find('pastille-bleu', 1, true), 'image inconnue refusée : ' .. tostring(erreur))
end)

essai('Dispositions.couleurs : des triplets neufs de 0 à 1, sans LrColor, la claire pour une valeur inconnue', function()
    -- Hors de toute simulation (ni import ni LrColor), comme scripts/gabarits.lua : Dispositions se
    -- charge et rend ses couleurs sans rien du SDK.
    local code = 'package.path = ' .. string.format('%q', S.plugin .. '/?.lua;') .. ' .. package.path; '
        .. "local D = require 'Dispositions'; local c = D.couleurs('sombre'); "
        .. "io.write(type(import), ' ', type(LrColor), ' ', #c.texte, ' ', c.fondContenu[1] * 255)"
    egal('nil nil 3 30', S.lireCommande('luajit -e ' .. S.q(code) .. ' 2>&1'), 'Dispositions hors du SDK')
    for apparence, palette in pairs(Dispositions.PALETTES) do
        local c = Dispositions.couleurs(apparence)
        egal(cles(palette), cles(c), apparence .. ' : toutes les clés')
        for cle, hex in pairs(palette) do
            local t = c[cle]
            vrai(type(t) == 'table' and #t == 3 and getmetatable(t) == nil, apparence .. '.' .. cle .. ' : un triplet')
            for k = 1, 3 do
                vrai(type(t[k]) == 'number' and t[k] >= 0 and t[k] <= 1, apparence .. '.' .. cle .. ' : de 0 à 1')
                egal(tonumber(hex:sub(2 * k - 1, 2 * k), 16), math.floor(t[k] * 255 + 0.5), apparence .. '.' .. cle .. ' : composante ' .. k)
            end
        end
    end
    local claire = Dispositions.couleurs('claire')
    egal(0, claire.blanc[1] - 1, 'blanc')
    egal(0x1D / 255, claire.texte[1], 'texte')
    -- Tables neuves à chaque appel : la fenêtre peut les garder sans toucher la palette.
    vrai(claire ~= Dispositions.couleurs('claire') and claire.texte ~= Dispositions.couleurs('claire').texte, 'tables neuves')
    local inconnue = Dispositions.couleurs('bleue')
    for cle, t in pairs(claire) do
        for k = 1, 3 do
            egal(t[k], inconnue[cle][k], 'valeur inconnue : la claire (' .. cle .. ')')
        end
    end
    vrai(Dispositions.couleurs('sombre').fondContenu[1] < 0.2, 'la sombre est sombre')
end)

-- Contraste de deux couleurs RRGGBB (WCAG 2 : luminance relative en sRGB).
local function luminance(hex)
    local function lin(c)
        c = c / 255
        return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    end
    return 0.2126 * lin(tonumber(hex:sub(1, 2), 16)) + 0.7152 * lin(tonumber(hex:sub(3, 4), 16))
        + 0.0722 * lin(tonumber(hex:sub(5, 6), 16))
end

local function contraste(a, b)
    local la, lb = luminance(a), luminance(b)
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- Les textes et ce qu'ils couvrent, dans la fenêtre B : { encre, { fonds } }.
local PAIRES = {
    { 'texte', { 'fondContenu', 'fondVolet', 'fondDroite', 'fondPanneau', 'fondCarte', 'selection', 'fondSegment' } },
    { 'gris', { 'fondContenu', 'fondVolet', 'fondDroite', 'fondPanneau', 'fondCarte' } },
    { 'grisEntete', { 'fondVolet', 'fondDroite', 'fondContenu' } },
    { 'sousTitreChoisi', { 'selection' } },
    { 'bleu', { 'fondContenu', 'fondVolet', 'fondDroite', 'fondPanneau', 'fondCarte' } },
    { 'mono', { 'fondContenu', 'fondPanneau', 'fondCarte' } },
    { 'coche', { 'fondContenu', 'fondPanneau', 'fondCarte' } },
    { 'orange', { 'fondContenu', 'fondVolet', 'fondDroite' } },
    { 'rouge', { 'fondContenu', 'fondVolet', 'fondDroite', 'fondPanneau', 'fondCarte' } },
    { 'ambre', { 'fondPanneau', 'fondCarte' } },
    { 'blanc', { 'bleuBouton', 'bleuPresse' } },
    { 'contour', { 'fondPanneau', 'fondCarte' } },
    { 'texteApercu', { 'fondApercu' } },
    { 'titreInactif', { 'bleuInactif' } },
}

essai('Palette sombre : chaque texte se lit au moins aussi bien qu\'en claire, à 4,5:1 au moins là où la claire y est', function()
    local claire, sombre = Dispositions.PALETTES.claire, Dispositions.PALETTES.sombre
    -- Le calcul lui-même : noir sur blanc 21:1, une couleur sur elle-même 1:1.
    egal(21, math.floor(contraste('000000', 'FFFFFF') + 0.5))
    egal(1, contraste('3A3A3A', '3A3A3A'))
    local nombre = 0
    for _, paire in ipairs(PAIRES) do
        local encre = paire[1]
        for _, fond in ipairs(paire[2]) do
            local c, s = contraste(claire[encre], claire[fond]), contraste(sombre[encre], sombre[fond])
            vrai(s >= math.min(4.5, c), string.format('%s sur %s : %.2f:1 en sombre, %.2f:1 en claire', encre, fond, s, c))
            nombre = nombre + 1
        end
    end
    vrai(nombre >= 40, 'les paires vérifiées')
    -- Les fonds suivent ceux de macOS en sombre : le contenu le plus foncé, puis le volet, puis la
    -- colonne droite, dans l'ordre inverse de la claire (blanc, puis #F2F2F2, puis #ECECEC).
    vrai(luminance(claire.fondContenu) > luminance(claire.fondVolet)
        and luminance(claire.fondVolet) > luminance(claire.fondDroite), 'fonds clairs')
    vrai(luminance(sombre.fondContenu) < luminance(sombre.fondVolet)
        and luminance(sombre.fondVolet) < luminance(sombre.fondDroite), 'fonds sombres du plus foncé au plus clair')
    -- Le texte courant, le gris et le bleu à 4,5:1 au moins sur chaque fond, en sombre.
    for _, encre in ipairs({ 'texte', 'gris', 'grisEntete', 'bleu', 'mono' }) do
        for _, fond in ipairs({ 'fondContenu', 'fondVolet', 'fondDroite', 'fondPanneau', 'fondCarte' }) do
            vrai(contraste(sombre[encre], sombre[fond]) >= 4.5, encre .. ' sur ' .. fond .. ' en sombre')
        end
    end
    -- Le contrôle refuserait une palette sombre moins lisible : le bleu de la maquette sur le
    -- fond de la colonne droite sombre.
    vrai(contraste(claire.bleu, sombre.fondDroite) < math.min(4.5, contraste(claire.bleu, claire.fondDroite)),
        'un bleu illisible en sombre serait refusé')
end)

essai('Bouton bleu inactif : son titre paraît éteint dans les deux apparences, et se lit encore ; l\'aperçu sur le fond des vignettes', function()
    for nom, palette in pairs(Dispositions.PALETTES) do
        local eteint, allume = contraste(palette.titreInactif, palette.bleuInactif), contraste(palette.blanc, palette.bleuBouton)
        vrai(eteint < allume, string.format('%s : titre inactif à %.2f:1, actif à %.2f:1', nom, eteint, allume))
        vrai(eteint >= 1.8, string.format('%s : titre inactif encore lisible (%.2f:1)', nom, eteint))
    end
    -- En sombre, le blanc sur le bleu inactif (#2B3F5C) ferait 10:1, plus que le bouton actif : le
    -- titre inactif ne peut pas y rester blanc.
    local sombre = Dispositions.PALETTES.sombre
    vrai(contraste(sombre.blanc, sombre.bleuInactif) > contraste(sombre.blanc, sombre.bleuBouton), 'le blanc y paraîtrait allumé')
    vrai(sombre.titreInactif ~= sombre.blanc, 'un autre titre en sombre')
    -- Le fond de l'aperçu est celui des vignettes (Images.FOND, sous la photo réduite au cadre) dans
    -- les deux apparences : l'image « aucun aperçu » et une photo tombent sur le même gris.
    local Images = require 'Images'
    for nom, palette in pairs(Dispositions.PALETTES) do
        egal(Images.FOND, palette.fondApercu, nom .. ' : fond de l\'aperçu')
    end
end)

essai('images/ et images/sombre/ : chaque image de Dispositions.IMAGES dans les deux jeux, en 2x à 144 ppp, aux mêmes tailles', function()
    local nombre = 0
    for nom, t in pairs(IMAGES) do
        local octets = {}
        for apparence, dossier in pairs(JEUX) do
            local chemin = S.plugin .. '/' .. dossier .. '/' .. nom .. '.png'
            local raison = controler(chemin, t.largeur, t.hauteur)
            vrai(raison == nil, raison)
            local f = assert(io.open(chemin, 'rb'))
            octets[apparence] = f:read('*a')
            f:close()
        end
        -- Le jeu sombre est dessiné de sa palette, pas copié du clair : chaque image y emploie au
        -- moins une couleur qui change avec l'apparence.
        vrai(octets.claire ~= octets.sombre, 'images/sombre/' .. nom .. '.png : la même que la claire')
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

-- Les fichiers d'un dossier de jeu : chaque PNG est une image de Dispositions.IMAGES, ou l'image
-- « aucun aperçu » (Dispositions.nomImageVide, à part : elle n'est pas comptée), sans paire @2x ;
-- seuls les dossiers des autres jeux s'y ajoutent (images/sombre dans images/). Rend le nombre
-- d'images.
local VIDE = Dispositions.nomImageVide()

local function controlerJeu(racine, dossier)
    local images = 0
    for fichier in S.lireCommande('ls -1 ' .. S.q(racine .. '/' .. dossier)):gmatch('[^\n]+') do
        vrai(not fichier:find('@', 1, true), 'pas de paire 1x et @2x : ' .. dossier .. '/' .. fichier)
        local nom = fichier:match('^(.+)%.png$')
        if nom == VIDE then
            -- scripts/images-vides.swift, contrôlée à part.
        elseif nom then
            vrai(IMAGES[nom], 'image absente de Dispositions.IMAGES : ' .. dossier .. '/' .. fichier)
            images = images + 1
        else
            local sous = dossier .. '/' .. fichier
            vrai(JEUX.sombre == sous or JEUX.claire == sous, 'seulement des PNG et les dossiers des jeux dans '
                .. dossier .. '/ : ' .. fichier)
        end
    end
    return images
end

essai('images/ et images/sombre/ : aucune image hors de Dispositions.IMAGES, ni paire @2x', function()
    local nombre = 0
    for _ in pairs(IMAGES) do
        nombre = nombre + 1
    end
    for apparence, dossier in pairs(JEUX) do
        egal(nombre, controlerJeu(S.plugin, dossier), apparence .. ' : une image par nom de Dispositions.IMAGES')
    end
    -- Le contrôle lui-même : un dossier en trop dans images/, une image en trop dans images/sombre/.
    local racine = S.home .. '/module-jeux'
    S.executer('mkdir -p ' .. S.q(racine .. '/images/sombre') .. ' ' .. S.q(racine .. '/images/autre'))
    local ok, erreur = pcall(controlerJeu, racine, 'images')
    vrai(not ok and tostring(erreur):find('autre', 1, true), 'dossier en trop refusé : ' .. tostring(erreur))
    fabriquerPng(racine .. '/images/sombre/orpheline.png', 2, 2, PPM_144)
    ok, erreur = pcall(controlerJeu, racine, 'images/sombre')
    vrai(not ok and tostring(erreur):find('images/sombre/orpheline.png', 1, true), 'image en trop refusée : ' .. tostring(erreur))
end)

essai('vide-330x220.png : l\'image « aucun aperçu » du cadre 3:2, 660 × 440 à 144 ppp, dans le jeu de chaque apparence', function()
    egal('vide-330x220', VIDE, 'son nom tiré du cadre de l\'aperçu')
    local T = Dispositions.TAILLES
    local octets = {}
    for apparence, dossier in pairs(JEUX) do
        local chemin = S.plugin .. '/' .. dossier .. '/' .. VIDE .. '.png'
        egal(dossier .. '/' .. VIDE .. '.png', Dispositions.imageVide(apparence), apparence .. ' : Dispositions.imageVide')
        local raison = controler(chemin, T.apercu, T.apercuHauteur)
        vrai(raison == nil, raison)
        local png = lirePng(chemin)
        egal(660, png.largeur, apparence .. ' : largeur en pixels')
        egal(440, png.hauteur, apparence .. ' : hauteur en pixels')
        local f = assert(io.open(chemin, 'rb'))
        octets[apparence] = f:read('*a')
        f:close()
    end
    vrai(octets.claire ~= octets.sombre, 'la sombre est la claire')
    -- Plus à la racine du module (lot B1), ni l'ancien carré de 320.
    vrai(not S.executer('test -e ' .. S.q(S.plugin .. '/' .. VIDE .. '.png')), 'plus à la racine du module')
    vrai(not S.executer('test -e ' .. S.q(S.plugin .. '/vide-320.png')), 'plus de vide-320.png')
end)

essai('scripts/gabarits.lua : les images, les deux apparences et l\'image « aucun aperçu » en JSON, lancé depuis un autre dossier', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    -- Lancé ici (Tests/Lua/Fenetre), pas depuis la racine : il trouve le module par son propre chemin.
    local sortie = S.lireCommande('luajit ' .. S.q(RACINE .. '/scripts/gabarits.lua') .. ' 2>&1')
    local ok, lu = pcall(Json.decode, sortie)
    vrai(ok and type(lu) == 'table', 'JSON lisible : ' .. sortie)
    egal('apparences images vide', cles(lu), 'les trois parties')
    -- Le cadre de l'image « aucun aperçu », celui de l'aperçu (Dispositions.TAILLES).
    egal(VIDE, lu.vide.nom)
    egal(Dispositions.TAILLES.apercu, lu.vide.largeur)
    egal(Dispositions.TAILLES.apercuHauteur, lu.vide.hauteur)
    for nom, t in pairs(IMAGES) do
        vrai(type(lu.images[nom]) == 'table', 'absente du JSON : ' .. nom)
        egal(t.largeur, lu.images[nom].largeur, nom .. ' : largeur')
        egal(t.hauteur, lu.images[nom].hauteur, nom .. ' : hauteur')
    end
    for nom in pairs(lu.images) do
        vrai(IMAGES[nom], 'en trop dans le JSON : ' .. tostring(nom))
    end
    egal('claire sombre', cles(lu.apparences), 'les deux apparences')
    for apparence, dossier in pairs(JEUX) do
        local a = lu.apparences[apparence]
        egal(dossier, a.dossier, apparence .. ' : dossier')
        egal(cles(Dispositions.PALETTES[apparence]), cles(a.couleurs), apparence .. ' : clés de la palette')
        for cle, hex in pairs(Dispositions.PALETTES[apparence]) do
            egal(hex, a.couleurs[cle], apparence .. '.' .. cle)
        end
    end
    -- Dispositions.gabarits rend des tables neuves : le JSON ne touche pas les tables du module.
    local g = Dispositions.gabarits()
    vrai(g.images.loupe ~= IMAGES.loupe and g.apparences.sombre.couleurs ~= Dispositions.PALETTES.sombre, 'tables neuves')
end)

-- scripts/images-fenetre.swift lancé par l'usage documenté (gabarits.lua sur son entrée), mais vers
-- un module d'essai du dossier temporaire, jamais vers celui du dépôt. Rend son code de sortie et ce
-- qu'il a écrit (sortie et erreurs mêlées).
local function produire(entree, module)
    local sortie = S.lireCommande(entree .. ' | swift ' .. S.q(RACINE .. '/scripts/images-fenetre.swift') .. ' '
        .. S.q(module) .. ' 2>&1; echo "code $?"')
    return tonumber(sortie:match('code (%d+)%s*$')), sortie
end

local function lireOctets(chemin)
    local f = assert(io.open(chemin, 'rb'))
    local octets = f:read('*a')
    f:close()
    return octets
end

essai('scripts/images-fenetre.swift : les deux jeux en 2x à 144 ppp, chacun de sa palette, une image de trop gardée', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    local gabarits = 'luajit ' .. S.q(RACINE .. '/scripts/gabarits.lua')
    local module = S.home .. '/module-images'
    local code, sortie = produire(gabarits, module)
    egal(0, code, 'production entière : ' .. sortie)
    vrai(sortie:find('images (claire), images/sombre (sombre)', 1, true), 'les deux jeux dits : ' .. sortie)
    -- Chaque image produite passe le contrôle des images du module (2 × la taille en points, RGBA
    -- 8 bits, 144 ppp), dans chaque jeu, et la sombre n'est pas la claire. (Pas de comparaison
    -- octet à octet avec les images du dépôt : le rendu du texte et des tracés peut changer d'une
    -- version de macOS à l'autre, celle des tests sur GitHub comprise.)
    for nom, t in pairs(IMAGES) do
        for _, dossier in pairs(JEUX) do
            local raison = controler(module .. '/' .. dossier .. '/' .. nom .. '.png', t.largeur, t.hauteur)
            vrai(raison == nil, raison)
        end
        vrai(lireOctets(module .. '/images/' .. nom .. '.png') ~= lireOctets(module .. '/images/sombre/' .. nom .. '.png'),
            nom .. ' : la sombre est la claire')
    end
    -- Une image d'un des deux dossiers absente de Dispositions.IMAGES est signalée, jamais effacée.
    local orphelines = { fabriquerPng(module .. '/images/orpheline.png', 2, 2, PPM_144),
        fabriquerPng(module .. '/images/sombre/orpheline.png', 2, 2, PPM_144) }
    code, sortie = produire(gabarits, module)
    egal(0, code, 'production avec une image de trop : ' .. sortie)
    vrai(sortie:find('à retirer : images/orpheline.png', 1, true), 'image de trop signalée (claire) : ' .. sortie)
    vrai(sortie:find('à retirer : images/sombre/orpheline.png', 1, true), 'image de trop signalée (sombre) : ' .. sortie)
    for _, orpheline in ipairs(orphelines) do
        vrai(lirePng(orpheline), 'image de trop gardée : ' .. orpheline)
    end
    -- L'image « aucun aperçu », rangée là par scripts/images-vides.swift, n'est pas une image de trop.
    fabriquerPng(module .. '/images/' .. VIDE .. '.png', 660, 440, PPM_144)
    fabriquerPng(module .. '/images/sombre/' .. VIDE .. '.png', 660, 440, PPM_144)
    code, sortie = produire(gabarits, module)
    egal(0, code, 'production avec l\'image « aucun aperçu » : ' .. sortie)
    vrai(not sortie:find(VIDE, 1, true), "l'image « aucun aperçu » n'est pas signalée : " .. sortie)
end)

-- scripts/images-vides.swift, lancé de même vers un module d'essai : son code et sa sortie.
local function produireVides(entree, module)
    local sortie = S.lireCommande(entree .. ' | swift ' .. S.q(RACINE .. '/scripts/images-vides.swift') .. ' '
        .. S.q(module) .. ' 2>&1; echo "code $?"')
    return tonumber(sortie:match('code (%d+)%s*$')), sortie
end

essai('scripts/images-vides.swift : l\'image « aucun aperçu » dans chaque jeu, du fond et du texte de sa palette ; ses refus avant d\'écrire', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    local gabarits = 'luajit ' .. S.q(RACINE .. '/scripts/gabarits.lua')
    local module = S.home .. '/module-vides'
    local code, sortie = produireVides(gabarits, module)
    egal(0, code, 'production : ' .. sortie)
    local T = Dispositions.TAILLES
    for _, dossier in pairs(JEUX) do
        local raison = controler(module .. '/' .. dossier .. '/' .. VIDE .. '.png', T.apercu, T.apercuHauteur)
        vrai(raison == nil, raison)
    end
    vrai(lireOctets(module .. '/images/' .. VIDE .. '.png') ~= lireOctets(module .. '/images/sombre/' .. VIDE .. '.png'),
        'la sombre est la claire')
    -- Rien d'autre d'écrit : une image par jeu, et le dossier du jeu sombre.
    egal('sombre ' .. VIDE .. '.png', (S.lireCommande('ls -1 ' .. S.q(module .. '/images')):gsub('\n', ' '):gsub(' $', '')))
    -- Une couleur absente ou invalide, un dossier hors du module, un cadre nul : refusés, rien d'écrit.
    local function vides(changer)
        local g = Dispositions.gabarits()
        changer(g)
        return "printf '%s' " .. S.q(Json.encode(g))
    end
    local cas = {
        { vides(function(g) g.apparences.sombre.couleurs.fondApercu = nil end), 'couleur absente de la palette sombre : fondApercu' },
        { vides(function(g) g.apparences.claire.couleurs.texteApercu = '9E9E9' end), 'couleur invalide dans la palette claire : texteApercu' },
        { vides(function(g) g.apparences.sombre.dossier = '../ailleurs' end), 'dossier invalide pour l\'apparence sombre' },
        { vides(function(g) g.vide.largeur = 0 end), 'cadre invalide pour ' .. VIDE },
        { vides(function(g) g.vide.nom = '../vide' end), 'nom invalide' },
        { vides(function(g) g.vide = nil end), 'gabarits illisibles' },
        { "printf ''", "rien sur l'entrée standard" },
    }
    for k, c in ipairs(cas) do
        local refus = S.home .. '/module-vides-refus-' .. k
        local codeRefus, sortieRefus = produireVides(c[1], refus)
        egal(1, codeRefus, c[2] .. ' : code de sortie (' .. sortieRefus .. ')')
        vrai(sortieRefus:find(c[2], 1, true), c[2] .. ' : ' .. sortieRefus)
        vrai(not S.executer('test -e ' .. S.q(refus)), c[2] .. ' : rien d\'écrit')
    end
end)

-- Des gabarits d'essai en JSON, tirés de ceux du module (Dispositions.gabarits) réduits à la seule
-- loupe, puis changés par `changer(g)`, sur l'entrée du script.
local function gabaritsEssai(changer)
    local g = Dispositions.gabarits()
    g.images = { loupe = { largeur = 12, hauteur = 12 } }
    if changer then
        changer(g)
    end
    return "printf '%s' " .. S.q(Json.encode(g))
end

essai('scripts/images-fenetre.swift : refuse sans rien écrire un nom sans dessin, une taille, une couleur ou un dossier invalides, une entrée vide', function()
    vrai(RACINE, 'racine du dépôt tirée de PLUGIN_DIR : ' .. tostring(S.plugin))
    local function json(texte)
        return "printf '%s' " .. S.q(texte)
    end
    -- Chaque refus vient avant toute écriture : la loupe, connue et bien taillée, n'est écrite dans
    -- aucun jeu, et le dossier du module n'est pas créé.
    local cas = {
        { gabaritsEssai(function(g) g.images.inconnue = { largeur = 12, hauteur = 12 } end),
            'aucun dessin pour : inconnue' },
        { gabaritsEssai(function(g) g.images.trombone = { largeur = 0, hauteur = 14 } end),
            'taille invalide pour trombone' },
        { gabaritsEssai(function(g) g.apparences.sombre.couleurs.ambre = nil end),
            'couleur absente de la palette sombre : ambre' },
        { gabaritsEssai(function(g) g.apparences.sombre.couleurs.texte = '#E8E8E8' end),
            'couleur invalide dans la palette sombre : texte' },
        { gabaritsEssai(function(g) g.apparences.sombre.couleurs.gris = 'GGGGGG' end),
            'couleur invalide dans la palette sombre : gris' },
        -- Un chiffre pleine chasse (U+FF11) passe Character.isHexDigit, mais ni UInt32(_:radix:)
        -- ni le dessin : refusé avant d'écrire le jeu clair, valide et dessiné en premier.
        { gabaritsEssai(function(g) g.apparences.sombre.couleurs.contour = '\239\188\1458E8E8' end),
            'couleur invalide dans la palette sombre : contour' },
        { gabaritsEssai(function(g) g.apparences.sombre.dossier = '../ailleurs' end),
            'dossier invalide pour l\'apparence sombre' },
        { gabaritsEssai(function(g) g.apparences.sombre.dossier = '/tmp/ailleurs' end),
            'dossier invalide pour l\'apparence sombre' },
        { gabaritsEssai(function(g) g.apparences.sombre.dossier = 'images' end),
            'dossier « images » commun aux apparences claire et sombre' },
        { gabaritsEssai(function(g) g.apparences = { vide = true } end), 'gabarits illisibles' },
        { json('{"images":{"loupe":{"largeur":12,"hauteur":12}},"apparences":{}}'), 'aucune apparence' },
        -- L'ancien format (les tailles seules) n'est plus lu.
        { json('{"loupe":{"largeur":12,"hauteur":12}}'), 'gabarits illisibles' },
        { "printf ''", "rien sur l'entrée standard" },
        { json('pas du JSON'), 'gabarits illisibles' },
    }
    for k, c in ipairs(cas) do
        local module = S.home .. '/module-refus-' .. k
        local code, sortie = produire(c[1], module)
        egal(1, code, c[2] .. ' : code de sortie (' .. sortie .. ')')
        vrai(sortie:find(c[2], 1, true), c[2] .. ' : ' .. sortie)
        vrai(not S.executer('test -e ' .. S.q(module)), c[2] .. ' : rien d\'écrit')
    end
    -- Les gabarits d'essai, sans changement, se dessinent : les refus viennent bien des changements.
    local module = S.home .. '/module-loupe'
    local code, sortie = produire(gabaritsEssai(), module)
    egal(0, code, 'gabarits d\'essai : ' .. sortie)
    for apparence, dossier in pairs(JEUX) do
        vrai(controler(module .. '/' .. dossier .. '/loupe.png', 12, 12) == nil, apparence .. ' : loupe écrite')
    end
end)

-- Fin -------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
