-- essais-registre.lua : le registre du carnet de progrès (Carnet.lua, 1.3), hors de Lightroom
-- (LuaJIT, Lightroom simulé par Simulation.lua) : commande carnet (constater, lire, retirer),
-- format de carnet.json, une table par catalogue, copies neuves, élagage, refus, fichier illisible
-- mis de côté ; rien n'est écrit dans le catalogue, et la pause n'arrête rien. Les leçons des photos
-- (commande lecon, retirée au correctif 1.3.6) déjà rangées restent dans le fichier telles quelles,
-- sans plus jamais être montrées. Aussi : préférences et diagnostic, désinstallation, et ce que la
-- simulation offre aux lots suivants (LrFileUtils.copy, dates des fichiers).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue, contient, ligne = A.test, A.egal, A.echoue, A.contient, A.ligne
local photoRaw, photoJpeg = A.photoRaw, A.photoJpeg

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Preferences = require 'Preferences'

-- Complément de la simulation, pour cet essai : l'heure locale de LrDate.timeToUserFormat pour
-- tout format (l'UTC décalé de S.fuseau secondes, comme le jour que la simulation rend déjà).
local LrDate = import 'LrDate'
LrDate.timeToUserFormat = function(t, format)
    return os.date('!' .. format, 978307200 + math.floor(t) + S.fuseau)
end

local CATALOGUE = '/Users/test/Images/Catalogue.lrcat'
local AUTRE = '/Users/test/Images/Autre.lrcat'

-- Le 1er juillet 2026 à 2 h 30 UTC (secondes depuis 2001) : le 30 juin à 22 h 30 à l'heure avancée
-- de l'Est.
local PRISE_JUILLET_UTC = 804565800

-- Le vocabulaire du connecteur (PriseDeVue.vocabulaire), réduit à deux défauts.
local VOCABULAIRE = {
    { code = 'flou', cle = 'blur', axe = 'lumiere', domaine = 'nettete', libelle = "Photo floue ou bougée",
        conseil = "Une vitesse d'au moins 1/(2 × focale).", mesure = true },
    { code = 'horizon_penche', cle = 'tilted_horizon', axe = 'composition', domaine = 'composition',
        libelle = "Horizon ou ligne penchée", conseil = "Afficher le niveau électronique du viseur.", mesure = true },
}

-- carnet constater d'une vue sur une photo (le flou cherché ; trouvé si `flou`).
local function constater(photo, flou)
    return Commandes.executer('carnet', { action = 'constater', photo = photo, vocabulaire = VOCABULAIRE,
        vue = { cherches = { 'flou', 'horizon_penche' }, defauts = flou and { { code = 'flou', mesure = 9, texte = "flou : 9" } } or {} } })
end

local function fichierRelu()
    return Json.decode(S.fichiers[Carnet.fichier()])
end

-- Aucune table de cette valeur ne porte de métatable (tableau relu par Json.decode).
local function sansMetatable(valeur, chemin)
    if type(valeur) ~= 'table' then
        return
    end
    egal(getmetatable(valeur), nil, "métatable : " .. chemin)
    for cle, element in pairs(valeur) do
        sansMetatable(element, chemin .. '.' .. tostring(cle))
    end
end

-- Une leçon d'avant le correctif 1.3.6, telle que la commande lecon (1.3 à 1.3.5) l'écrivait dans
-- carnet.json, avec une liste vide, un point sans manque, et un champ que rien ne connaît : le
-- registre doit la réécrire à l'identique. En texte canonique (clés triées, comme Json.encode).
local LECON_DAVANT = Json.encode(Json.decode([[{"photo":1,"uuid":"uuid-1","fichier":"DSC_0412.NEF","le":800000000,
"points":[{"axe":"lumiere","manque":"Le ciel est brûlé sur 4 % du haut.","prise_de_vue":"Exposer pour le ciel, −2/3 IL.",
"defauts":[{"code":"ciel_brule","libelle":"Ciel brûlé"}]},{"axe":"couleur","prise_de_vue":"Balance des blancs juste : à refaire.",
"defauts":[]},{"axe":"composition","manque":"L'horizon penche de 1,8°.","prise_de_vue":"Niveau électronique du viseur.",
"defauts":[{"code":"horizon_penche","libelle":"Horizon penché"}]}],"defauts":["ciel_brule","horizon_penche"],"indices":[],
"champ_inconnu":{"vide":[],"liste":[1,2]}}]]))

-- carnet.json d'avant, écrit puis relu : une entrée par photo { id = { lecons = { [id] = texte }, vue? } }
-- (sans vue, une entrée qui n'a que ses leçons).
local function carnetDAvant(entrees)
    local morceaux = {}
    for _, e in ipairs(entrees) do
        local lecons = {}
        for id, texte in pairs(e.lecons or {}) do
            lecons[#lecons + 1] = string.format('"%s":%s', id, texte)
        end
        local vue = e.vue and (',"vue":' .. Json.encode(e.vue)) or ''
        morceaux[#morceaux + 1] = string.format('"%d":{"photo":%d,"uuid":"uuid-%d","fichier":"%s","le":%d,"lecons":{%s}%s}', e.photo,
            e.photo, e.photo, e.fichier or 'DSC_0412.NEF', e.le or 800000000, table.concat(lecons, ','), vue)
    end
    S.fichiers[Carnet.fichier()] = string.format('{"format":1,"catalogues":{"%s":{"photos":{%s}}}}', CATALOGUE,
        table.concat(morceaux, ','))
    Carnet.oublier()
end

-- Constats -------------------------------------------------------------------------------------

test("carnet constater : rangé dans carnet.json, format 1, mois à l'heure locale ; ni écriture au catalogue ni pause", function()
    local photo = photoRaw()
    photo.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.fuseau = -4 * 3600
    Liaison.pause = true
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local version = Carnet.version
    local r = constater(1)
    egal(r.note, true)
    egal(r.photo, 1)
    egal(r.original, 1)
    egal(r.fichier, 'DSC_0412.NEF')
    egal(r.remplacee, false)
    egal(r.mois, '2026-06', "mois de prise de vue à l'heure locale, pas l'UTC")
    egal(r.prise_le, '2026-06-30 22:30')
    egal(r.sans_date, nil)
    egal(r.remarque, nil)
    egal(#S.ecritures, ecritures, "rien dans le catalogue")
    egal(S.ecrituresPrivees, privees, "pas même une écriture privée")
    egal(Carnet.version, version + 1)

    egal(Carnet.fichier(), S.home .. '/Library/Application Support/Developpeur/carnet.json')
    local relu = fichierRelu()
    egal(relu.format, 1)
    local entree = relu.catalogues[CATALOGUE].photos['1']
    egal(entree.photo, 1, "clé : l'original, en texte")
    egal(entree.uuid, 'uuid-1')
    egal(entree.fichier, 'DSC_0412.NEF')
    egal(entree.prise, '2026-06')
    egal(entree.prise_le, '2026-06-30 22:30')
    egal(entree.lecons, nil, "une entrée neuve n'a pas de leçons")
    egal(S.fichiers[Carnet.fichier()]:find('"defauts":[]', 1, true) ~= nil, true, "une liste vide reste un tableau JSON dans le fichier")
end)

-- Correctif 1.3.6 : la leçon de la photo est retirée ; celles déjà rangées restent dans carnet.json,
-- et le registre, qui le réécrit en entier à chaque changement, les garde à l'identique.
test("leçons d'avant : un constat ajouté réécrit carnet.json, la leçon y reste telle quelle ; jamais montrée ni envoyée", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    carnetDAvant({ { photo = 1, lecons = { ['1'] = LECON_DAVANT, ['7'] = LECON_DAVANT } } })
    egal(Carnet.nombre(), 0, "une entrée qui n'a que ses leçons n'est pas au carnet")
    egal(Carnet.entree(1), nil)
    egal(#Carnet.entrees(), 0)
    egal(Commandes.executer('carnet', { action = 'lire' }).nombre, 0)

    -- Un constat ajouté à la même entrée : le fichier est réécrit, les deux leçons y restent mot pour mot.
    egal(constater(7).note, true)
    local texte = S.fichiers[Carnet.fichier()]
    egal(select(2, texte:gsub(LECON_DAVANT:gsub('%p', '%%%0'), '')), 2, "les deux leçons, à l'identique, listes vides comprises")
    local entree = fichierRelu().catalogues[CATALOGUE].photos['1']
    egal(Json.encode(entree.lecons['1']), LECON_DAVANT)
    egal(entree.vue.photo, 7, "le constat de la copie, sous l'original")
    -- Ni la fenêtre, ni le serveur ne les voient.
    egal(Carnet.nombre(), 1)
    egal(Carnet.entree(1).lecons, nil)
    egal(Carnet.entrees()[1].lecons, nil)
    local lu = Commandes.executer('carnet', { action = 'lire', resume = true })
    egal(lu.photos[1].lecons, nil)
    egal(Json.encode(lu):find('lecon', 1, true), nil, "rien d'une leçon dans la réponse")
    -- Relu du fichier, puis un autre changement : toujours là.
    Carnet.oublier()
    egal(constater(1, true).remplacee, true)
    egal(Json.encode(fichierRelu().catalogues[CATALOGUE].photos['1'].lecons['7']), LECON_DAVANT)
    -- La commande lecon n'existe plus.
    echoue(function() Commandes.executer('lecon', { action = 'lire' }) end, "Commande inconnue : lecon")
end)

test("leçons d'avant : retirer ôte les constats, jamais les leçons ; une entrée d'un autre uuid les garde aussi", function()
    local photo = photoRaw()
    photoJpeg()
    carnetDAvant({ { photo = 1, lecons = { ['1'] = LECON_DAVANT } } })
    constater(1)
    constater(2)
    local r = Commandes.executer('carnet', { action = 'retirer', photos = { 1, 2 } })
    egal(r.retirees, 2)
    egal(Carnet.nombre(), 0)
    local photos = fichierRelu().catalogues[CATALOGUE].photos
    egal(photos['2'], nil, "sans leçon, l'entrée part")
    egal(photos['1'].vue, nil, "le constat part")
    egal(Json.encode(photos['1'].lecons['1']), LECON_DAVANT, "la leçon reste")
    egal(Commandes.executer('carnet', { action = 'retirer', photos = { 1 } }).retirees, 0, "plus rien à retirer")

    -- Une autre photo sous ce numéro (un autre uuid) : l'entrée est refaite, ses leçons restent.
    photo.brut.uuid = 'uuid-nouvelle'
    egal(constater(1).remplacee, false)
    local entree = fichierRelu().catalogues[CATALOGUE].photos['1']
    egal(entree.uuid, 'uuid-nouvelle')
    egal(Json.encode(entree.lecons['1']), LECON_DAVANT)
end)

test("carnet : refus avant toute écriture (action, photos) ; la commande lecon n'existe plus", function()
    photoRaw()
    local version = Carnet.version
    echoue(function() Commandes.executer('carnet', { action = 'vider' }) end, "Action du carnet inconnue : vider (constater, lire ou retirer).")
    echoue(function() Commandes.executer('carnet', { action = 'retirer' }) end, "donner photos")
    echoue(function() Commandes.executer('lecon', { action = 'garder', photo = 1 }) end, "Commande inconnue : lecon")
    egal(S.fichiers[Carnet.fichier()], nil, "rien n'est rangé")
    egal(Carnet.version, version)
end)

-- La lecture de la photo passe par le catalogue : dans Lightroom, la tâche peut y rendre la main,
-- et une autre commande passer (ici, carnet retirer, au moment où constater lit le nom du fichier).
-- constater lit tout avant de toucher au registre : l'autre commande ne voit jamais d'entrée à
-- moitié faite, et le constat rangé reste au carnet.
test("carnet constater : une autre commande pendant la lecture de la photo ne fait pas perdre le constat", function()
    local photo = photoRaw()
    local lire = photo.getFormattedMetadata
    local pendant
    photo.getFormattedMetadata = function(self, cle)
        if cle == 'fileName' and not pendant then
            pendant = Commandes.executer('carnet', { action = 'retirer', photos = { 1 } })
        end
        return lire(self, cle)
    end
    local r = constater(1)
    photo.getFormattedMetadata = lire
    egal(pendant ~= nil, true, "l'autre commande est passée pendant la lecture")
    egal(pendant.retirees, 0, "elle n'a vu aucune entrée à moitié faite")
    egal(r.note, true)
    egal(Carnet.nombre(), 1, "l'entrée de l'original est au carnet")
    egal(fichierRelu().catalogues[CATALOGUE].photos['1'].fichier, 'DSC_0412.NEF', "et dans carnet.json")
end)

test("carnet : par la prise de la liaison, pendant la pause", function()
    photoRaw()
    Liaison.pause = true
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 9, command = 'carnet', params = { action = 'constater', photo = 1, vocabulaire = VOCABULAIRE,
        vue = { cherches = { 'flou' } } } }))
    Liaison.recevoir(ligne({ id = 10, command = 'carnet', params = { action = 'lire' } }))
    Liaison.prise = nil
    local reponse = Json.decode(S.envois[1])
    egal(reponse.error, nil)
    egal(reponse.result.note, true)
    egal(Json.decode(S.envois[2]).result.nombre, 1)
end)

-- Carnet ---------------------------------------------------------------------------------------

test("carnet lire : tableaux JSON vers le serveur ; copies neuves sans métatable pour la fenêtre ; relu du fichier", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    carnetDAvant({ { photo = 1, lecons = { ['7'] = LECON_DAVANT } } })
    constater(7)
    local ecritures = #S.ecritures
    local lu = Commandes.executer('carnet', { action = 'lire' })
    egal(lu.catalogue, 'Catalogue.lrcat', "le nom du catalogue, jamais son chemin")
    egal(lu.nombre, 1)
    egal(getmetatable(lu.photos), getmetatable(Json.tableau()), "photos : un tableau JSON")
    local entree = lu.photos[1]
    egal(entree.uuid, nil, "pas d'uuid vers le serveur")
    egal(entree.lecons, nil, "ni les leçons d'avant")
    egal(entree.vue.photo, 7)
    local texte = Json.encode(lu)
    egal(texte:find('"defauts":[]', 1, true) ~= nil, true, "liste vide : []")
    egal(#S.ecritures, ecritures, "lire n'écrit rien")

    local entrees = Carnet.entrees()
    egal(#entrees, 1)
    sansMetatable(entrees, 'entrees')
    sansMetatable(Carnet.entree(1), 'entree')
    entrees[1].vue.cherches[1] = 'changé'
    egal(Carnet.entree(1).vue.cherches[1], 'flou', "une copie : le registre ne change pas")

    Carnet.oublier()
    local relue = Carnet.entree(1)
    egal(relue.fichier, 'DSC_0412.NEF', "relue du fichier")
    egal(relue.vue.photo, 7)
    sansMetatable(relue, 'relue')
    sansMetatable(Carnet.entrees(), 'entrees relues')
end)

test("carnet : chaque catalogue garde sa table ; un autre catalogue ne fait rien perdre au premier", function()
    photoRaw()
    photoJpeg()
    constater(1)
    S.cheminCatalogue = AUTRE
    egal(Carnet.nombre(), 0, "l'autre catalogue a son carnet, vide")
    egal(Commandes.executer('carnet', { action = 'lire' }).nombre, 0)
    egal(Carnet.entree(1), nil)
    constater(2)
    local relu = fichierRelu()
    egal(relu.catalogues[CATALOGUE].photos['1'].photo, 1, "le premier catalogue garde sa table")
    egal(relu.catalogues[AUTRE].photos['2'].photo, 2)
    egal(relu.catalogues[AUTRE].photos['1'], nil)
    Carnet.oublier()
    S.cheminCatalogue = CATALOGUE
    egal(Carnet.nombre(), 1, "relu, le premier retrouve son carnet")
    egal(Carnet.entree(2), nil)
    egal(Carnet.entree(1).photo, 1)
    -- Un catalogue dont le chemin ne se lit pas : rien ne s'y range, il se lit vide.
    S.cheminCatalogue = nil
    egal(Carnet.nombre(), 0)
    echoue(function() constater(1) end, "Chemin du catalogue ouvert illisible")
end)

test("carnet : élagage au-delà de MAX_PHOTOS, les constats les plus anciens sortent ; jamais les leçons d'avant", function()
    photoRaw()
    local vue = { le = 1, cherches = { 'flou' }, defauts = {} }
    -- 11 à 13 : des constats (le 300, 100, 200) ; 12, le plus ancien, a aussi une leçon d'avant ; 14,
    -- plus ancien encore, n'a qu'une leçon : il ne compte pas.
    carnetDAvant({ { photo = 11, le = 300, fichier = 'IMG_11.JPG', vue = vue }, { photo = 12, le = 100, fichier = 'IMG_12.JPG',
        vue = vue, lecons = { ['12'] = LECON_DAVANT } }, { photo = 13, le = 200, fichier = 'IMG_13.JPG', vue = vue },
        { photo = 14, le = 50, fichier = 'IMG_14.JPG', lecons = { ['14'] = LECON_DAVANT } } })
    egal(Carnet.nombre(), 3)
    local max = Carnet.MAX_PHOTOS
    Carnet.MAX_PHOTOS = 3
    constater(1)
    Carnet.MAX_PHOTOS = max
    egal(Carnet.nombre(), 3)
    egal(Carnet.entree(12), nil, "le plus ancien constat sort")
    egal(Carnet.entree(11).fichier, 'IMG_11.JPG')
    egal(Carnet.entree(13).fichier, 'IMG_13.JPG')
    egal(Carnet.entree(1).fichier, 'DSC_0412.NEF')
    local photos = fichierRelu().catalogues[CATALOGUE].photos
    egal(photos['12'].vue, nil)
    egal(Json.encode(photos['12'].lecons['12']), LECON_DAVANT, "sa leçon reste")
    egal(Json.encode(photos['14'].lecons['14']), LECON_DAVANT, "une entrée de leçons seules ne compte pas et reste")
end)

test("carnet retirer : par l'original ou par une copie virtuelle ; absentes dites ; rien dans le catalogue", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    constater(7)
    local ecritures = #S.ecritures
    local r = Commandes.executer('carnet', { action = 'retirer', photos = { 7 } })
    egal(r.retirees, 1, "la copie désigne l'entrée de son original")
    egal(r.absentes, nil)
    egal(Carnet.nombre(), 0)
    egal(contient(Liaison.journal, "Carnet : 1 photo retirée"), true)
    constater(1)
    r = Commandes.executer('carnet', { action = 'retirer', photos = { 1, 999 } })
    egal(r.retirees, 1)
    egal(#r.absentes, 1)
    egal(r.absentes[1], 999)
    egal(#S.ecritures, ecritures)
    egal(next(fichierRelu().catalogues[CATALOGUE].photos), nil)
end)

test("carnet : abonnés prévenus à chaque changement ; un abonné qui échoue ne gêne pas", function()
    photoRaw()
    local vus = {}
    Carnet.abonner('casse', function() error("fenêtre fermée") end)
    Carnet.abonner('essai', function(quoi) vus[#vus + 1] = quoi end)
    local version = Carnet.version
    constater(1)
    egal(Carnet.version, version + 1)
    egal(vus[1], 'constat')
    Commandes.executer('carnet', { action = 'retirer', photos = { 1 } })
    egal(vus[2], 'retrait')
    Carnet.desabonner('essai')
    constater(1)
    egal(#vus, 2)
end)

test("carnet : un fichier illisible ou d'un autre format est mis de côté avant la première écriture, jamais écrasé", function()
    photoRaw()
    local fichier = Carnet.fichier()
    S.fichiers[fichier] = '{ pas du JSON'
    Carnet.oublier()
    egal(Carnet.nombre(), 0, "illisible : se lit vide")
    egal(S.fichiers[fichier], '{ pas du JSON', "la lecture ne touche pas au fichier")
    constater(1)
    local aCote
    for chemin, contenu in pairs(S.fichiers) do
        if chemin:find('/carnet%-illisible%-%d+%.json$') then
            aCote = contenu
        end
    end
    egal(aCote, '{ pas du JSON', "l'ancien fichier est gardé à côté")
    egal(fichierRelu().format, 1)
    egal(contient(Liaison.journal, "Carnet illisible mis de côté"), true)

    -- Un autre format (une version plus récente) : de même.
    S.fichiers = {}
    S.fichiers[fichier] = Json.encode({ format = 2, catalogues = {} })
    Carnet.oublier()
    constater(1)
    local garde = 0
    for chemin in pairs(S.fichiers) do
        if chemin:find('/carnet%-illisible%-%d+%.json$') then
            garde = garde + 1
        end
    end
    egal(garde, 1)
    egal(fichierRelu().format, 1)
end)

test("carnet : fichier non écrit, le constat reste pour la session avec une remarque ; un illisible qui ne se met pas de côté n'est jamais écrasé", function()
    photoRaw()
    local ecrire = Fichiers.ecrire
    Fichiers.ecrire = function() error("Écriture impossible : disque plein", 0) end
    local ok, r = pcall(constater, 1)
    Fichiers.ecrire = ecrire
    assert(ok, r)
    egal(r.note, true)
    egal(r.remarque, "Constat gardé pour cette session, carnet.json non écrit : Écriture impossible : disque plein")
    egal(Carnet.entree(1) ~= nil, true, "gardé pour la session")
    egal(S.fichiers[Carnet.fichier()], nil)
    egal(contient(Liaison.journal, "Carnet non enregistré : Écriture impossible : disque plein"), true)

    local fichier = Carnet.fichier()
    S.fichiers[fichier] = '{ pas du JSON'
    Carnet.oublier()
    local LrFileUtils = import 'LrFileUtils'
    local deplacer = LrFileUtils.move
    LrFileUtils.move = function() return false end
    ok, r = pcall(constater, 1)
    LrFileUtils.move = deplacer
    assert(ok, r)
    egal(r.remarque, "Constat gardé pour cette session, carnet.json non écrit : carnet.json illisible, laissé tel quel")
    egal(S.fichiers[fichier], '{ pas du JSON', "jamais écrasé")
    egal(contient(Liaison.journal, "Carnet illisible non mis de côté"), true)
end)

test("carnet : Carnet se charge sans l'interface ni la Bibliothèque (la fenêtre s'en sert)", function()
    local f = assert(io.open(dossierModule .. 'Carnet.lua', 'r'))
    local source = f:read('*a')
    f:close()
    local requis = {}
    for l in source:gmatch('[^\n]+') do
        local module = l:match("^local%s+[%w_]+%s*=%s*require%s*%(?%s*'([%w_]+)'") or l:match("^local%s+[%w_]+%s*=%s*import%s*'([%w_]+)'")
            or l:match("^require%s*%(?%s*'([%w_]+)'")
        if module then
            requis[#requis + 1] = module
            egal(module == 'Bibliotheque' or module == 'LrApplicationView' or module == 'LrView' or module == 'LrDialogs'
                or module == 'LrBinding' or module == 'Fenetre' or module == 'Moteur', false, l)
        end
    end
    table.sort(requis)
    egal(table.concat(requis, ' '), 'Chemins Compat Fichiers Json Liaison LrDate LrFileUtils LrPathUtils LrTasks Photos')
end)

-- Préférences, diagnostic, désinstallation ------------------------------------------------------

test("préférences : carnet coché par défaut (liaison) ; avant/après (fenêtre), plus de leçon ; diagnostic", function()
    egal(Preferences.defauts.carnet, true)
    egal(Preferences.lire().carnet, true)
    local prefs = Chemins.prefs()
    egal(prefs.avantApresEtapes, true)
    egal(Chemins.defauts.leconFinRetouche, nil, "la leçon de fin de retouche est retirée (1.3.6)")
    egal(Preferences.defauts.avantApresEtapes, nil, "une clé ne sert pas aux deux")
    egal(Chemins.defauts.carnet, nil)
    photoRaw()
    photoJpeg()
    constater(1)
    local PluginInfoProvider = require 'PluginInfoProvider'
    local diagnostic = PluginInfoProvider.diagnostic()
    egal(diagnostic:find("point de mise au point en tout temps : false ; carnet de progrès : true (1 photo)", 1, true) ~= nil, true, diagnostic)
    egal(diagnostic:find("sinon une nouvelle : true ; avant/après des étapes : true", 1, true) ~= nil, true, diagnostic)
    egal(diagnostic:find("proposition à l'ouverture", 1, true), nil, diagnostic)
    egal(diagnostic:find("leçon", 1, true), nil, diagnostic)
    constater(2)
    S.prefs.carnet = false
    egal(PluginInfoProvider.diagnostic():find("carnet de progrès : false (2 photos)", 1, true) ~= nil, true)
end)

test("désinstallation : --tout retire carnet.json et Etapes/ ; sans --tout, ils sont gardés et dits", function()
    local f = assert(io.open(dossierTests .. '../../../uninstall.sh', 'r'))
    local script = f:read('*a')
    f:close()
    local entete = script:match('^(.-)\nset %-euo pipefail')
    egal(entete:find('(carnet.json)', 1, true) ~= nil, true, "en-tête : carnet.json")
    egal(entete:find('(Etapes/)', 1, true) ~= nil, true, "en-tête : Etapes/")
    local travail = script:match('TRAVAIL=%((.-)\n%)')
    egal(travail:find('carnet', 1, true), nil, "carnet.json n'est pas un fichier de travail")
    egal(travail:find('Etapes', 1, true), nil, "Etapes/ non plus")
    egal(script:find('retirer "${DEST_DIR}"', 1, true) ~= nil, true, "--tout retire tout le dossier")
    local gardes = script:match('GARDES%+=%("%${DEST_DIR} %((.-)%)"%)')
    egal(gardes:find('carnet de progrès', 1, true) ~= nil, true, gardes)
    egal(gardes:find('avant/après des étapes', 1, true) ~= nil, true, gardes)
end)

-- Aides : remise à zéro par module -------------------------------------------------------------

test("aides : un crochet par module à registre, appelé avant chaque test s'il est chargé", function()
    local oublis = 0
    package.loaded.FauxRegistre = { oublier = function() oublis = oublis + 1 end, observateurs = { fenetre = print } }
    A.remiseAZero('FauxRegistre')
    A.remettre()
    egal(oublis, 1, "oublier appelé")
    egal(next(package.loaded.FauxRegistre.observateurs), nil, "plus d'abonnés")
    local appels = 0
    A.remiseAZero('FauxRegistre', function(module) appels = appels + 1 end)
    A.remettre()
    egal(appels, 1, "un crochet donné remplace celui par défaut")
    egal(oublis, 1)
    package.loaded.FauxRegistre = nil
    A.remettre()
    egal(appels, 1, "un module qui n'est pas chargé est sauté")
    -- Le registre du carnet repart de zéro : relu du fichier (vide après S.reinitialiser).
    photoRaw()
    constater(1)
    A.remettre()
    egal(Carnet.nombre(), 0)
    egal(next(Carnet.observateurs), nil)
    -- Le journal de la liaison et les photos de ses lignes repartent ensemble (même rang).
    Liaison.noter("ligne d'un test précédent", 1)
    A.remettre()
    egal(#Liaison.journal, 0)
    egal(#Liaison.journalPhotos, 0, "photos du journal vidées avec lui")
end)

-- Simulation : ce qu'elle offre aux lots suivants -----------------------------------------------

test("simulation : LrFileUtils.copy garde la date, n'écrase pas ; fileModificationDate ; directoryEntries", function()
    local racine = Chemins.racine()
    S.horloge = 1000
    Fichiers.ecrire(racine .. '/Etapes/u1/a-avant.jpg', 'JPEG')
    egal(Fichiers.date(racine .. '/Etapes/u1/a-avant.jpg'), 1000, "date de l'écriture (heure de la simulation)")
    S.horloge = 5000
    egal(Fichiers.copier(racine .. '/Etapes/u1/a-avant.jpg', racine .. '/Etapes/u1/b-avant.jpg'), true)
    egal(S.fichiers[racine .. '/Etapes/u1/b-avant.jpg'], 'JPEG')
    egal(Fichiers.date(racine .. '/Etapes/u1/b-avant.jpg'), 1000, "une copie garde la date de sa source")
    S.fichiers[racine .. '/Etapes/u1/c.jpg'] = 'autre'
    egal(import('LrFileUtils').copy(racine .. '/Etapes/u1/a-avant.jpg', racine .. '/Etapes/u1/c.jpg'), false, "pas d'écrasement")
    egal(S.fichiers[racine .. '/Etapes/u1/c.jpg'], 'autre')
    S.datesFichiers[racine .. '/Etapes/u1/c.jpg'] = 42
    egal(Fichiers.date(racine .. '/Etapes/u1/c.jpg'), 42, "un essai vieillit un fichier")
    egal(table.concat(Fichiers.entrees(racine .. '/Etapes'), ','), 'u1', "les dossiers d'un dossier")
    egal(table.concat(Fichiers.entrees(racine .. '/Etapes/u1'), ','), 'a-avant.jpg,b-avant.jpg,c.jpg')
    -- LrFileUtils.files ne donne que les fichiers : pas le dossier u1, créé avec son parent.
    Fichiers.ecrire(racine .. '/Etapes/vue.jpg', 'JPEG')
    local fichiers = {}
    for chemin in import('LrFileUtils').files(racine .. '/Etapes') do
        fichiers[#fichiers + 1] = chemin:match('[^/]+$')
    end
    egal(table.concat(fichiers, ','), 'vue.jpg', "files : les fichiers seuls")
    Fichiers.supprimer(racine .. '/Etapes/u1/c.jpg')
    egal(S.datesFichiers[racine .. '/Etapes/u1/c.jpg'], nil)
end)

A.bilan()
