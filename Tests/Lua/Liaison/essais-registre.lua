-- essais-registre.lua : le registre du carnet de progrès et des leçons (Carnet.lua, 1.3), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : commandes lecon (garder, lire,
-- retirer) et carnet (lire, retirer), format de carnet.json, une table par catalogue, copies
-- neuves, élagage, refus, fichier illisible mis de côté ; rien n'est écrit dans le catalogue, et
-- la pause n'arrête rien. Aussi : préférences et diagnostic, désinstallation, et ce que la
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

-- Une leçon comme le serveur l'envoie (Lecon.pourLeModule) : composition d'abord, pour vérifier
-- l'ordre des axes.
local function lecon()
    return {
        points = Json.tableau({
            { axe = 'composition', manque = "L'horizon penche de 1,8°.", prise_de_vue = "Niveau électronique du viseur.",
                defauts = Json.tableau({ { code = 'horizon_penche', libelle = "Horizon penché" } }) },
            { axe = 'lumiere', manque = "Le ciel est brûlé sur 4 % du haut.", prise_de_vue = "Exposer pour le ciel, −2/3 IL.",
                defauts = Json.tableau({ { code = 'ciel_brule', libelle = "Ciel brûlé" }, 'sous_exposition' }) },
            { axe = 'couleur', prise_de_vue = "Balance des blancs juste : à refaire.", defauts = Json.tableau() },
        }),
        indices = Json.tableau({ { code = 'dominante', axe = 'couleur', libelle = "Dominante", preuve = "Temperature 5600 → 5000" } }),
    }
end

local function garder(photo, contenu)
    return Commandes.executer('lecon', { action = 'garder', photo = photo, lecon = contenu or lecon() })
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

-- Leçons ---------------------------------------------------------------------------------------

test("lecon garder : rangée dans carnet.json, format 1, axes dans l'ordre, mois à l'heure locale ; ni écriture au catalogue ni pause", function()
    local photo = photoRaw()
    photo.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.fuseau = -4 * 3600
    Liaison.pause = true
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local version = Carnet.version
    local r = garder(1)
    egal(r.rangee, true)
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
    egal(contient(Liaison.journal, "Leçon rangée : DSC_0412.NEF"), true)

    egal(Carnet.fichier(), S.home .. '/Library/Application Support/Developpeur/carnet.json')
    local relu = fichierRelu()
    egal(relu.format, 1)
    local entree = relu.catalogues[CATALOGUE].photos['1']
    egal(entree.photo, 1, "clé : l'original, en texte")
    egal(entree.uuid, 'uuid-1')
    egal(entree.fichier, 'DSC_0412.NEF')
    egal(entree.prise, '2026-06')
    egal(entree.prise_le, '2026-06-30 22:30')
    local l = entree.lecons['1']
    egal(l.photo, 1)
    egal(l.uuid, 'uuid-1')
    egal(l.points[1].axe, 'lumiere', "dans l'ordre des axes")
    egal(l.points[2].axe, 'couleur')
    egal(l.points[3].axe, 'composition')
    egal(l.points[1].defauts[1].code, 'ciel_brule')
    egal(l.points[1].defauts[2].code, 'sous_exposition', "un code seul devient { code }")
    egal(l.points[2].manque, nil, "rien ne manquait")
    egal(table.concat(l.defauts, ','), 'ciel_brule,sous_exposition,horizon_penche', "les codes des trois points, une fois chacun")
    egal(l.indices[1].preuve, "Temperature 5600 → 5000")
    egal(S.fichiers[Carnet.fichier()]:find('"defauts":[]', 1, true) ~= nil, true, "une liste vide reste un tableau JSON dans le fichier")
end)

test("lecon : sans date de prise de vue, sans mois ; photo active sans photo donnée", function()
    local photo = photoJpeg()
    S.active = photo
    local r = Commandes.executer('lecon', { action = 'garder', lecon = lecon() })
    egal(r.photo, 2)
    egal(r.mois, nil)
    egal(r.sans_date, true)
    egal(fichierRelu().catalogues[CATALOGUE].photos['2'].sans_date, true)
end)

test("lecon : une copie virtuelle va sous son original ; la nouvelle remplace l'ancienne ; lire ; retirer", function()
    local original = photoRaw()
    original.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.copieVirtuelle(original, 7, 'Copie 1')
    local r = garder(7)
    egal(r.photo, 7)
    egal(r.original, 1, "rangée sous l'original")
    egal(r.fichier, 'DSC_0412.NEF (Copie 1)')
    egal(Carnet.nombre(), 1, "une prise de vue compte une fois")
    egal(garder(1).remplacee, false, "l'original a sa propre leçon")
    egal(Carnet.nombre(), 1)
    local nouvelle = lecon()
    nouvelle.points[3].prise_de_vue = "Garder ce réglage."
    egal(garder(1, nouvelle).remplacee, true, "la nouvelle remplace l'ancienne")
    egal(Carnet.lecon(1).points[2].prise_de_vue, "Garder ce réglage.")

    local lues = Commandes.executer('lecon', { action = 'lire', photos = { 7 } })
    egal(#lues.lecons, 1)
    egal(lues.lecons[1].photo, 7)
    egal(lues.lecons[1].original, 1)
    egal(lues.lecons[1].mois, '2026-07')
    egal(lues.lecons[1].uuid, nil, "pas d'uuid vers le serveur")
    egal(lues.perdues, nil)
    egal(#Commandes.executer('lecon', { action = 'lire' }).lecons, 2, "toutes celles du catalogue ouvert")

    egal(Commandes.executer('lecon', { action = 'retirer', photo = 7 }).retirees, 1)
    egal(Carnet.lecon(7), nil)
    egal(Carnet.nombre(), 1, "l'entrée garde la leçon de l'original")
    egal(Commandes.executer('lecon', { action = 'retirer', photos = { 1 } }).retirees, 1)
    egal(Carnet.nombre(), 0, "l'entrée vide part avec sa dernière leçon")
    egal(next(fichierRelu().catalogues[CATALOGUE].photos), nil)
    egal(Commandes.executer('lecon', { action = 'retirer', photo = 1 }).retirees, 0)
end)

test("lecon : une photo d'un autre uuid ou disparue perd sa leçon à la lecture ; une entrée d'un autre uuid est remplacée", function()
    local photo = photoRaw()
    photoJpeg()
    garder(1)
    garder(2)
    photo.brut.uuid = 'uuid-autre'
    local lues = Commandes.executer('lecon', { action = 'lire', photos = { 1, 2 } })
    egal(#lues.lecons, 1)
    egal(lues.lecons[1].photo, 2)
    egal(lues.perdues, 1)
    egal(Carnet.entree(1), nil, "l'entrée vide part")
    S.photos[2] = nil
    egal(Commandes.executer('lecon', { action = 'lire', photos = { 2 } }).perdues, 1, "photo disparue du catalogue")

    -- Une entrée rangée pour une autre photo sous ce numéro : remplacée, ses leçons oubliées.
    photo.brut.uuid = 'uuid-1'
    garder(1)
    S.copieVirtuelle(photo, 8, 'Copie 2')
    garder(8)
    photo.brut.uuid = 'uuid-nouvelle'
    egal(garder(1).remplacee, false)
    local entree = Carnet.entree(1)
    egal(entree.uuid, 'uuid-nouvelle')
    egal(entree.lecons['8'], nil, "les leçons de l'ancienne entrée sont oubliées")
end)

test("lecon : refus avant toute écriture (trois points, un par axe ; textes ; codes ; photo ; action)", function()
    photoRaw()
    local version = Carnet.version
    local function points(modifier)
        local l = lecon()
        modifier(l)
        return l
    end
    echoue(function() garder(1, points(function(l) table.remove(l.points) end)) end, "trois points, un par axe")
    echoue(function() garder(1, points(function(l) l.points[3].axe = 'lumiere' end)) end, "l'axe « lumiere » est donné deux fois")
    echoue(function() garder(1, points(function(l) l.points[1].axe = 'lumière' end)) end, "axe inconnu « lumière »")
    echoue(function() garder(1, points(function(l) l.points[2].prise_de_vue = '' end)) end, "prise_de_vue manque")
    echoue(function() garder(1, points(function(l) l.points[2].manque = string.rep('x', 601) end)) end, "600 octets au plus")
    echoue(function() garder(1, points(function(l) l.points[1].defauts = Json.tableau({ 'Horizon' }) end)) end, "code de défaut invalide « Horizon »")
    echoue(function() garder(1, points(function(l) l.points[1].defauts = 'flou' end)) end, "defauts est une liste")
    local treize = {}
    for i = 1, 13 do treize[i] = 'flou' end
    echoue(function() garder(1, points(function(l) l.points[2].defauts = Json.tableau(treize) end)) end, "13 défauts, 12 au plus")
    echoue(function() garder(1, points(function(l) l.indices[1].axe = 'cadre' end)) end, "axe inconnu « cadre »")
    echoue(function() Commandes.executer('lecon', { action = 'garder', photo = 1 }) end, "Leçon manquante")
    echoue(function() garder(999) end, "Aucune photo n'a l'identifiant 999")
    echoue(function() Commandes.executer('lecon', { action = 'retirer' }) end, "donner photo ou photos")
    echoue(function() Commandes.executer('lecon', { action = 'effacer' }) end, "Action de la leçon inconnue : effacer (garder, lire ou retirer).")
    echoue(function() Commandes.executer('carnet', { action = 'vider' }) end, "Action du carnet inconnue : vider (lire ou retirer).")
    echoue(function() Commandes.executer('carnet', { action = 'retirer' }) end, "donner photos")
    egal(S.fichiers[Carnet.fichier()], nil, "rien n'est rangé")
    egal(Carnet.version, version)
end)

-- La lecture de la photo passe par le catalogue : dans Lightroom, la tâche peut y rendre la main,
-- et une autre commande passer (ici, carnet retirer, au moment où garder lit le nom du fichier).
-- garder lit tout avant de toucher au registre : l'autre commande ne voit jamais d'entrée à moitié
-- faite, et la leçon rangée reste au carnet.
test("lecon garder : une autre commande pendant la lecture de la photo ne fait pas perdre la leçon", function()
    local photo = photoRaw()
    local lire = photo.getFormattedMetadata
    local pendant
    photo.getFormattedMetadata = function(self, cle)
        if cle == 'fileName' and not pendant then
            pendant = Commandes.executer('carnet', { action = 'retirer', photos = { 1 } })
        end
        return lire(self, cle)
    end
    local r = garder(1)
    photo.getFormattedMetadata = lire
    egal(pendant ~= nil, true, "l'autre commande est passée pendant la lecture")
    egal(pendant.retirees, 0, "elle n'a vu aucune entrée à moitié faite")
    egal(r.rangee, true)
    egal(Carnet.nombre(), 1, "l'entrée de l'original est au carnet")
    egal(Carnet.lecon(1) ~= nil, true, "la leçon dite rangée l'est")
    egal(fichierRelu().catalogues[CATALOGUE].photos['1'].lecons['1'].fichier, 'DSC_0412.NEF', "et dans carnet.json")
end)

test("lecon : par la prise de la liaison, pendant la pause", function()
    photoRaw()
    Liaison.pause = true
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 9, command = 'lecon', params = { action = 'garder', photo = 1, lecon = lecon() } }))
    Liaison.recevoir(ligne({ id = 10, command = 'carnet', params = { action = 'lire' } }))
    Liaison.prise = nil
    local reponse = Json.decode(S.envois[1])
    egal(reponse.error, nil)
    egal(reponse.result.rangee, true)
    egal(Json.decode(S.envois[2]).result.nombre, 1)
end)

-- Carnet ---------------------------------------------------------------------------------------

test("carnet lire : tableaux JSON vers le serveur ; copies neuves sans métatable pour la fenêtre ; relu du fichier", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    garder(7)
    garder(1)
    local ecritures = #S.ecritures
    local lu = Commandes.executer('carnet', { action = 'lire' })
    egal(lu.catalogue, 'Catalogue.lrcat', "le nom du catalogue, jamais son chemin")
    egal(lu.nombre, 1)
    egal(getmetatable(lu.photos), getmetatable(Json.tableau()), "photos : un tableau JSON")
    local entree = lu.photos[1]
    egal(entree.uuid, nil, "pas d'uuid vers le serveur")
    egal(#entree.lecons, 2, "les leçons en liste")
    egal(entree.lecons[1].photo, 1)
    egal(entree.lecons[2].photo, 7)
    egal(entree.lecons[1].uuid, nil)
    local texte = Json.encode(lu)
    egal(texte:find('"defauts":[]', 1, true) ~= nil, true, "liste vide : []")
    egal(texte:find('"lecons":[', 1, true) ~= nil, true)
    egal(#S.ecritures, ecritures, "lire n'écrit rien")

    local entrees = Carnet.entrees()
    egal(#entrees, 1)
    sansMetatable(entrees, 'entrees')
    sansMetatable(Carnet.lecon(7), 'lecon')
    sansMetatable(Carnet.entree(1), 'entree')
    entrees[1].lecons['1'].points[1].prise_de_vue = 'changé'
    egal(Carnet.lecon(1).points[1].prise_de_vue, "Exposer pour le ciel, −2/3 IL.", "une copie : le registre ne change pas")

    Carnet.oublier()
    local relue = Carnet.lecon(7)
    egal(relue.points[3].manque, "L'horizon penche de 1,8°.", "relue du fichier")
    egal(relue.fichier, 'DSC_0412.NEF (Copie 1)')
    sansMetatable(relue, 'relue')
    sansMetatable(Carnet.entrees(), 'entrees relues')
end)

test("carnet : chaque catalogue garde sa table ; un autre catalogue ne fait rien perdre au premier", function()
    photoRaw()
    photoJpeg()
    garder(1)
    S.cheminCatalogue = AUTRE
    egal(Carnet.nombre(), 0, "l'autre catalogue a son carnet, vide")
    egal(Commandes.executer('carnet', { action = 'lire' }).nombre, 0)
    egal(Carnet.lecon(1), nil)
    garder(2)
    local relu = fichierRelu()
    egal(relu.catalogues[CATALOGUE].photos['1'].photo, 1, "le premier catalogue garde sa table")
    egal(relu.catalogues[AUTRE].photos['2'].photo, 2)
    egal(relu.catalogues[AUTRE].photos['1'], nil)
    Carnet.oublier()
    S.cheminCatalogue = CATALOGUE
    egal(Carnet.nombre(), 1, "relu, le premier retrouve son carnet")
    egal(Carnet.lecon(2), nil)
    egal(Carnet.lecon(1).photo, 1)
    -- Un catalogue dont le chemin ne se lit pas : rien ne s'y range, il se lit vide.
    S.cheminCatalogue = nil
    egal(Carnet.nombre(), 0)
    echoue(function() garder(1) end, "Chemin du catalogue ouvert illisible")
end)

test("carnet : élagage au-delà de MAX_PHOTOS, les entrées les plus anciennes sortent", function()
    photoRaw()
    local photos = {}
    for i, le in ipairs({ 300, 100, 200 }) do
        local id = 10 + i
        photos[tostring(id)] = { photo = id, uuid = 'uuid-' .. id, fichier = 'IMG_' .. id .. '.JPG', le = le, lecons = {} }
    end
    S.fichiers[Carnet.fichier()] = Json.encode({ format = 1, catalogues = { [CATALOGUE] = { photos = photos } } })
    Carnet.oublier()
    egal(Carnet.nombre(), 3)
    local max = Carnet.MAX_PHOTOS
    Carnet.MAX_PHOTOS = 3
    garder(1)
    Carnet.MAX_PHOTOS = max
    egal(Carnet.nombre(), 3)
    egal(Carnet.entree(12), nil, "la plus ancienne sort")
    egal(Carnet.entree(11).fichier, 'IMG_11.JPG')
    egal(Carnet.entree(13).fichier, 'IMG_13.JPG')
    egal(Carnet.entree(1).fichier, 'DSC_0412.NEF')
end)

test("carnet retirer : par l'original ou par une copie virtuelle ; absentes dites ; rien dans le catalogue", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    garder(7)
    local ecritures = #S.ecritures
    local r = Commandes.executer('carnet', { action = 'retirer', photos = { 7 } })
    egal(r.retirees, 1, "la copie désigne l'entrée de son original")
    egal(r.absentes, nil)
    egal(Carnet.nombre(), 0)
    egal(contient(Liaison.journal, "Carnet : 1 photo retirée"), true)
    garder(1)
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
    garder(1)
    egal(Carnet.version, version + 1)
    egal(vus[1], 'lecon')
    Commandes.executer('lecon', { action = 'retirer', photo = 1 })
    egal(vus[2], 'retrait')
    Carnet.desabonner('essai')
    garder(1)
    egal(#vus, 2)
end)

test("carnet : un fichier illisible ou d'un autre format est mis de côté avant la première écriture, jamais écrasé", function()
    photoRaw()
    local fichier = Carnet.fichier()
    S.fichiers[fichier] = '{ pas du JSON'
    Carnet.oublier()
    egal(Carnet.nombre(), 0, "illisible : se lit vide")
    egal(S.fichiers[fichier], '{ pas du JSON', "la lecture ne touche pas au fichier")
    garder(1)
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
    garder(1)
    local garde = 0
    for chemin in pairs(S.fichiers) do
        if chemin:find('/carnet%-illisible%-%d+%.json$') then
            garde = garde + 1
        end
    end
    egal(garde, 1)
    egal(fichierRelu().format, 1)
end)

test("carnet : fichier non écrit, la leçon reste pour la session avec une remarque ; un illisible qui ne se met pas de côté n'est jamais écrasé", function()
    photoRaw()
    local ecrire = Fichiers.ecrire
    Fichiers.ecrire = function() error("Écriture impossible : disque plein", 0) end
    local ok, r = pcall(garder, 1)
    Fichiers.ecrire = ecrire
    assert(ok, r)
    egal(r.rangee, true)
    egal(r.remarque, "Leçon gardée pour cette session, carnet.json non écrit : Écriture impossible : disque plein")
    egal(Carnet.lecon(1) ~= nil, true, "gardée pour la session")
    egal(S.fichiers[Carnet.fichier()], nil)
    egal(contient(Liaison.journal, "Carnet non enregistré : Écriture impossible : disque plein"), true)

    local fichier = Carnet.fichier()
    S.fichiers[fichier] = '{ pas du JSON'
    Carnet.oublier()
    local LrFileUtils = import 'LrFileUtils'
    local deplacer = LrFileUtils.move
    LrFileUtils.move = function() return false end
    ok, r = pcall(garder, 1)
    LrFileUtils.move = deplacer
    assert(ok, r)
    egal(r.remarque, "Leçon gardée pour cette session, carnet.json non écrit : carnet.json illisible, laissé tel quel")
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

test("préférences : carnet coché par défaut (liaison) ; avant/après et leçon (fenêtre) ; diagnostic", function()
    egal(Preferences.defauts.carnet, true)
    egal(Preferences.lire().carnet, true)
    local prefs = Chemins.prefs()
    egal(prefs.avantApresEtapes, true)
    egal(prefs.leconFinRetouche, true)
    egal(Preferences.defauts.avantApresEtapes, nil, "une clé ne sert pas aux deux")
    egal(Chemins.defauts.carnet, nil)
    photoRaw()
    photoJpeg()
    garder(1)
    local PluginInfoProvider = require 'PluginInfoProvider'
    local diagnostic = PluginInfoProvider.diagnostic()
    egal(diagnostic:find("point de mise au point en tout temps : false ; carnet de progrès : true (1 photo)", 1, true) ~= nil, true, diagnostic)
    egal(diagnostic:find("proposition à l'ouverture : true ; avant/après des étapes : true ; leçon en fin de retouche : true", 1, true) ~= nil, true, diagnostic)
    garder(2)
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
    garder(1)
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
