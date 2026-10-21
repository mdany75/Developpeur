-- Carnet.lua : le carnet de progrès et les leçons des photos (1.3), rangés dans carnet.json (à côté
-- de notation.json), à part du catalogue : rien n'y est écrit dans le catalogue, et aucune de ses
-- commandes n'est arrêtée par la pause de la liaison (elle n'arrête que les écritures dans le
-- catalogue). Commandes du serveur :
--   lecon  : garder (la leçon d'une photo : trois points, un par axe), lire, retirer ;
--   carnet : lire, retirer (constater, les défauts mesurés à la prise de vue, vient ensuite).
-- Elles écrivent carnet.json : le serveur ne les rejoue jamais (LightroomBridge.lectures).
--
-- Un seul fichier pour tous les catalogues : chacun garde sa table, sous son chemin (un
-- identifiant de photo ne vaut que dans son catalogue) ; changer de catalogue ne fait rien perdre
-- au premier (contrairement à notation.json). Dans un catalogue, une entrée par original
-- (masterPhoto) : une prise de vue ne compte qu'une fois, ses copies virtuelles comprises ; les
-- leçons de l'original et de ses copies y sont rangées, chacune sous l'identifiant de sa photo,
-- avec son uuid (une photo qui n'a plus cet uuid perd sa leçon). Au-delà de Carnet.MAX_PHOTOS
-- originaux dans un catalogue, les entrées les plus anciennes (champ le) sortent.
--
-- Format 1 :
--   { format = 1, catalogues = { [chemin du catalogue] = { photos = { ['<id de l'original>'] =
--     entrée } } } }
--   entrée : { photo (id de l'original), uuid, fichier, prise ('AAAA-MM', heure locale), prise_le
--     ('AAAA-MM-JJ HH:MM'), sans_date (vrai sans date de prise de vue), le (dernier changement,
--     os.time), vue { le, cherches, defauts }, angle { le, inclinaison, source }, lecons =
--     { ['<id de la photo>'] = leçon } }
--   leçon : { photo, uuid, fichier, le, points = { { axe ('lumiere', 'couleur', 'composition'),
--     manque (rien ne manquait s'il est absent), prise_de_vue, defauts = { { code, libelle } } } }
--     (dans l'ordre des axes), defauts (les codes des trois points), indices = { { code, axe,
--     libelle, preuve } } }
-- Un fichier illisible (ou d'un autre format) est mis de côté avant la première écriture
-- (carnet-illisible-<date>.json), jamais écrasé.
--
-- Chargeable sans l'interface ni la Bibliothèque (la fenêtre aussi s'en sert). Tout ce qui sort
-- vers une vue est une copie neuve, sans métatable (Lightroom bloque sur une table relue par
-- Json.decode) ; vers le serveur, les listes sont des tableaux JSON, même vides.

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

require 'Compat'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'

local Carnet = {
    -- +1 à chaque changement du registre : une fenêtre compare pour savoir s'il faut redessiner.
    version = 0,
    -- Fenêtres abonnées (nom → fonction), comme Notation.abonner.
    observateurs = {},
}

Carnet.FORMAT = 1
-- Originaux au plus par catalogue ; les plus anciens (champ le) sortent au-delà.
Carnet.MAX_PHOTOS = 3000
-- Les trois axes d'une leçon, dans leur ordre (codes de PriseDeVue.swift, côté serveur).
Carnet.AXES = { 'lumiere', 'couleur', 'composition' }
-- Bornes de ce que le serveur envoie (il en vérifie de plus strictes) : codes de défauts par
-- point, indices par leçon, longueurs en octets (UTF-8).
Carnet.MAX_CODES = 12
Carnet.MAX_INDICES = 20
Carnet.LONGUEUR_TEXTE = 600
Carnet.LONGUEUR_LIBELLE = 200
Carnet.LONGUEUR_PREUVE = 400

local AXE_CONNU = {}
for i, axe in ipairs(Carnet.AXES) do
    AXE_CONNU[axe] = i
end

-- Clés des listes : des tableaux JSON, même vides, vers le serveur et dans le fichier.
local LISTES = { points = true, defauts = true, indices = true, cherches = true }

local function echouer(message)
    error(message, 0)
end

local registre

function Carnet.fichier()
    return LrPathUtils.child(Chemins.racine(), 'carnet.json')
end

-- Copie neuve, sans métatable ni Json.null.
local function copie(valeur)
    if valeur == Json.null then
        return nil
    end
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
end

-- Copie pour Json.encode : les listes (LISTES) marquées tableaux, même vides.
local function versJson(valeur, cle)
    if type(valeur) ~= 'table' or valeur == Json.null then
        return valeur
    end
    local t = {}
    for k, element in pairs(valeur) do
        t[k] = versJson(element, k)
    end
    if LISTES[cle] then
        return Json.tableau(t)
    end
    return t
end

-- Clé d'une photo : un texte (Json.decode rend des clés texte).
local function cleDe(id)
    return tostring(tonumber(id) or id)
end

local function texte(valeur)
    if type(valeur) == 'string' and valeur ~= '' then
        return valeur
    end
    return nil
end

local function cheminCatalogue()
    local ok, chemin = LrTasks.pcall(function()
        local cat = Photos.catalogue()
        return cat and cat:getPath()
    end)
    return ok and texte(chemin) or nil
end

-- Relecture ----------------------------------------------------------------------------

local function normaliserLecon(l, cle)
    if type(l) ~= 'table' then
        return nil
    end
    local photo = tonumber(l.photo) or tonumber(cle)
    if not photo or type(l.points) ~= 'table' then
        return nil
    end
    local propre = copie(l)
    propre.photo = photo
    propre.le = tonumber(l.le) or 0
    propre.defauts = type(propre.defauts) == 'table' and propre.defauts or {}
    propre.indices = type(propre.indices) == 'table' and propre.indices or {}
    return propre
end

local function normaliserEntree(e, cle)
    if type(e) ~= 'table' then
        return nil
    end
    local photo = tonumber(e.photo) or tonumber(cle)
    if not photo then
        return nil
    end
    local propre = {
        photo = photo, uuid = texte(e.uuid), fichier = texte(e.fichier), prise = texte(e.prise),
        prise_le = texte(e.prise_le), sans_date = e.sans_date == true or nil, le = tonumber(e.le) or 0,
        vue = type(e.vue) == 'table' and copie(e.vue) or nil,
        angle = type(e.angle) == 'table' and copie(e.angle) or nil,
        lecons = {},
    }
    for cleLecon, l in pairs(type(e.lecons) == 'table' and e.lecons or {}) do
        local lecon = normaliserLecon(l, cleLecon)
        if lecon then
            propre.lecons[cleDe(lecon.photo)] = lecon
        end
    end
    return propre
end

local function vide()
    return { catalogues = {} }
end

-- Registre relu du fichier : des tables neuves, des clés de photo en texte.
local function normaliser(r)
    local propre = vide()
    for chemin, c in pairs(type(r.catalogues) == 'table' and r.catalogues or {}) do
        if texte(chemin) and type(c) == 'table' then
            local photos = {}
            for cle, e in pairs(type(c.photos) == 'table' and c.photos or {}) do
                local entree = normaliserEntree(e, cle)
                if entree then
                    photos[cleDe(entree.photo)] = entree
                end
            end
            propre.catalogues[chemin] = { photos = photos }
        end
    end
    return propre
end

local function charger()
    if registre then
        return registre
    end
    local contenu = Fichiers.lire(Carnet.fichier())
    local ok, r = pcall(function() return contenu and Json.decode(contenu) end)
    if ok and type(r) == 'table' and tonumber(r.format) == Carnet.FORMAT then
        registre = normaliser(r)
    else
        registre = vide()
        -- Un fichier présent mais illisible, ou d'un autre format : mis de côté avant d'écrire.
        registre.illisible = contenu ~= nil and contenu ~= ''
    end
    return registre
end

-- Pour les essais : oublie le registre chargé (relu du fichier à la prochaine lecture).
function Carnet.oublier()
    registre = nil
end

-- La table (photos) du catalogue de ce chemin, déjà lu (cheminCatalogue) : rien n'y lit le
-- catalogue, la tâche ne rend pas la main. `creer` : pour y écrire ; un catalogue dont le chemin ne
-- se lit pas refuse alors l'écriture (un identifiant ne vaut que dans son catalogue), et se lit
-- vide.
local function tableDu(chemin, creer)
    local r = charger()
    if not chemin then
        if creer then
            echouer("Chemin du catalogue ouvert illisible : rien n'est rangé au carnet.")
        end
        return { photos = {} }
    end
    local c = r.catalogues[chemin]
    if not c then
        c = { photos = {} }
        if creer then
            r.catalogues[chemin] = c
        end
    end
    return c
end

-- La table du catalogue ouvert, et son chemin.
local function catalogueOuvert(creer)
    local chemin = cheminCatalogue()
    return tableDu(chemin, creer), chemin
end

-- Les entrées les plus anciennes (champ le) d'un catalogue, au-delà de MAX_PHOTOS.
local function elaguer(c)
    local entrees = {}
    for cle, e in pairs(c.photos) do
        entrees[#entrees + 1] = { cle = cle, le = tonumber(e.le) or 0, photo = tonumber(cle) or 0 }
    end
    if #entrees > Carnet.MAX_PHOTOS then
        table.sort(entrees, function(a, b)
            if a.le ~= b.le then
                return a.le < b.le
            end
            return a.photo < b.photo
        end)
        for i = 1, #entrees - Carnet.MAX_PHOTOS do
            c.photos[entrees[i].cle] = nil
        end
    end
end

-- Écrit le registre entier (tous les catalogues). Rend vrai, ou faux et la raison.
local function enregistrer()
    local r = charger()
    local fichier = Carnet.fichier()
    if r.illisible and Fichiers.existe(fichier) then
        local aCote = LrPathUtils.child(Chemins.racine(), 'carnet-illisible-' .. tostring(os.time()) .. '.json')
        LrTasks.pcall(LrFileUtils.move, fichier, aCote)
        if Fichiers.existe(fichier) or not Fichiers.existe(aCote) then
            Liaison.noter("Carnet illisible non mis de côté : rien n'est écrit dans " .. fichier)
            return false, "carnet.json illisible, laissé tel quel"
        end
        Liaison.noter("Carnet illisible mis de côté : " .. aCote)
    end
    r.illisible = nil
    for _, c in pairs(r.catalogues) do
        elaguer(c)
    end
    local ok, erreur = pcall(Fichiers.ecrire, fichier, Json.encode({ format = Carnet.FORMAT,
        catalogues = versJson(r.catalogues) }))
    if not ok then
        local raison = Liaison.messageErreur(erreur)
        Liaison.noter("Carnet non enregistré : " .. raison)
        return false, raison
    end
    return true
end

-- Abonnements -------------------------------------------------------------------------

function Carnet.abonner(nom, fn)
    Carnet.observateurs[nom] = fn
end

function Carnet.desabonner(nom)
    Carnet.observateurs[nom] = nil
end

-- quoi : 'lecon', 'retrait' (et 'constat' ensuite).
function Carnet.signaler(quoi)
    for _, fn in pairs(Carnet.observateurs) do
        pcall(fn, quoi)
    end
end

-- Rend vrai, ou faux et la raison d'un fichier non écrit.
local function changer(quoi)
    Carnet.version = Carnet.version + 1
    local ok, raison = enregistrer()
    Carnet.signaler(quoi)
    return ok, raison
end

-- Lectures pour la fenêtre (copies neuves) ----------------------------------------------------

-- Les entrées du catalogue ouvert, triées par identifiant de l'original.
function Carnet.entrees()
    local c = catalogueOuvert(false)
    local cles = {}
    for cle in pairs(c.photos) do
        cles[#cles + 1] = cle
    end
    table.sort(cles, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local liste = {}
    for _, cle in ipairs(cles) do
        liste[#liste + 1] = copie(c.photos[cle])
    end
    return liste
end

-- L'entrée d'un original (identifiant de l'original), ou nil.
function Carnet.entree(idOriginal)
    if idOriginal == nil then
        return nil
    end
    return copie(catalogueOuvert(false).photos[cleDe(idOriginal)])
end

-- La leçon d'une photo (original ou copie virtuelle), ou nil.
function Carnet.lecon(idPhoto)
    if idPhoto == nil then
        return nil
    end
    local cle = cleDe(idPhoto)
    for _, e in pairs(catalogueOuvert(false).photos) do
        if e.lecons[cle] then
            return copie(e.lecons[cle])
        end
    end
    return nil
end

-- Nombre d'originaux au carnet du catalogue ouvert (diagnostic).
function Carnet.nombre()
    local n = 0
    for _ in pairs(catalogueOuvert(false).photos) do
        n = n + 1
    end
    return n
end

-- Entrées --------------------------------------------------------------------------------------

-- L'original d'une photo (elle-même si ce n'est pas une copie virtuelle).
local function originalDe(photo)
    if Photos.brut(photo, 'isVirtualCopy') == true then
        local maitre = Photos.brut(photo, 'masterPhoto')
        if type(maitre) == 'table' then
            return maitre
        end
    end
    return photo
end

-- Mois et date de la prise de vue, à l'heure locale (timeToUserFormat : timeToW3CDate donne
-- l'UTC, constaté pour le jour de Bibliotheque ; l'heure et la minute de ce format sont à
-- constater, mesure 3 de la 1.3).
local function datesPrise(photo)
    local t = tonumber(Photos.brut(photo, 'dateTimeOriginal'))
    if not t then
        return nil, nil
    end
    local ok, le = pcall(LrDate.timeToUserFormat, t, '%Y-%m-%d %H:%M')
    local mois = ok and type(le) == 'string' and le:match('^(%d%d%d%d%-%d%d)%-%d%d') or nil
    if not mois then
        return nil, nil
    end
    return mois, le
end

-- Ce que le registre garde d'une photo et de son original, lu avant d'y toucher : ces lectures
-- passent par le catalogue (la tâche peut rendre la main), et une autre commande (retirer, une
-- lecture qui perd une leçon) ne doit jamais voir une entrée à moitié faite.
local function lirePhoto(photo)
    local original = originalDe(photo)
    local prise, priseLe = datesPrise(original)
    return {
        id = photo.localIdentifier, uuid = texte(Photos.brut(photo, 'uuid')), fichier = Photos.nomFichier(photo),
        original = original.localIdentifier, uuidOriginal = texte(Photos.brut(original, 'uuid')),
        fichierOriginal = Photos.nomFichier(original), prise = prise, prise_le = priseLe,
    }
end

-- L'entrée de l'original (lu par lirePhoto) dans la table d'un catalogue, créée au besoin. Une
-- entrée d'un autre uuid (une autre photo sous ce numéro) est remplacée. L'uuid, le fichier et la
-- date de prise de vue sont repris à chaque fois. Sans lecture du catalogue.
local function entreeDe(c, lu)
    local cle = cleDe(lu.original)
    local e = c.photos[cle]
    if not e or (e.uuid and lu.uuidOriginal and e.uuid ~= lu.uuidOriginal) then
        e = { photo = lu.original, lecons = {}, le = os.time() }
        c.photos[cle] = e
    end
    e.uuid = lu.uuidOriginal
    e.fichier = lu.fichierOriginal
    e.prise, e.prise_le = lu.prise, lu.prise_le
    e.sans_date = not e.prise or nil
    return e
end

-- Retire l'entrée qui n'a plus rien (ni vue, ni angle, ni leçon).
local function retirerSiVide(c, cle)
    local e = c.photos[cle]
    if e and not e.vue and not e.angle and next(e.lecons) == nil then
        c.photos[cle] = nil
    end
end

-- Une entrée pour le serveur : les leçons en liste (par photo), les listes en tableaux JSON, sans
-- les uuid.
local function entreePourServeur(e)
    local r = versJson(e)
    r.uuid = nil
    local lecons = {}
    for _, l in pairs(e.lecons) do
        local lecon = versJson(l)
        lecon.uuid = nil
        lecons[#lecons + 1] = lecon
    end
    table.sort(lecons, function(a, b) return a.photo < b.photo end)
    r.lecons = Json.tableau(lecons)
    return r
end

-- Une leçon pour le serveur, avec l'original et la prise de vue de son entrée.
local function leconPourServeur(l, e)
    local r = versJson(l)
    r.uuid = nil
    r.original = e.photo
    r.mois = e.prise
    r.prise_le = e.prise_le
    return r
end

-- Leçons : validation ---------------------------------------------------------------------------

local function borne(valeur, max, quoi)
    if valeur == nil or valeur == Json.null then
        return nil
    end
    if type(valeur) ~= 'string' then
        echouer(quoi .. " : un texte attendu.")
    end
    if #valeur > max then
        echouer(string.format("%s : %d octets au plus.", quoi, max))
    end
    return texte(valeur)
end

local function code(valeur, quoi)
    if type(valeur) ~= 'string' or not valeur:match('^[a-z_]+$') or #valeur > 40 then
        echouer(string.format("%s : code de défaut invalide « %s » (lettres minuscules et _).", quoi, tostring(valeur)))
    end
    return valeur
end

local function axe(valeur, quoi)
    if not AXE_CONNU[valeur] then
        echouer(string.format("%s : axe inconnu « %s » (lumiere, couleur ou composition).", quoi, tostring(valeur)))
    end
    return valeur
end

-- Les trois points d'une leçon, vérifiés et rangés dans l'ordre des axes.
local function pointsValides(points)
    if type(points) ~= 'table' or #points ~= #Carnet.AXES then
        echouer("Leçon : trois points, un par axe (lumiere, couleur, composition).")
    end
    local parAxe = {}
    for _, p in ipairs(points) do
        if type(p) ~= 'table' then
            echouer("Leçon : chaque point est un objet { axe, manque, prise_de_vue, defauts }.")
        end
        local a = axe(p.axe, "Leçon")
        if parAxe[a] then
            echouer(string.format("Leçon : l'axe « %s » est donné deux fois (un point par axe).", a))
        end
        local quoi = "Leçon, axe " .. a
        local priseDeVue = borne(p.prise_de_vue, Carnet.LONGUEUR_TEXTE, quoi .. ", prise_de_vue")
        if not priseDeVue then
            echouer(quoi .. " : prise_de_vue manque (ce qui l'aurait évité, ou ce qui a marché, à la prise de vue).")
        end
        local defauts = p.defauts
        if defauts == nil or defauts == Json.null then
            defauts = {}
        elseif type(defauts) ~= 'table' then
            echouer(quoi .. " : defauts est une liste.")
        end
        if #defauts > Carnet.MAX_CODES then
            echouer(string.format("%s : %d défauts, %d au plus.", quoi, #defauts, Carnet.MAX_CODES))
        end
        local propres = {}
        for _, d in ipairs(defauts) do
            if type(d) == 'table' then
                propres[#propres + 1] = { code = code(d.code, quoi),
                    libelle = borne(d.libelle, Carnet.LONGUEUR_LIBELLE, quoi .. ", libellé") }
            else
                propres[#propres + 1] = { code = code(d, quoi) }
            end
        end
        parAxe[a] = { axe = a, manque = borne(p.manque, Carnet.LONGUEUR_TEXTE, quoi .. ", manque"),
            prise_de_vue = priseDeVue, defauts = propres }
    end
    local ranges = {}
    for i, a in ipairs(Carnet.AXES) do
        ranges[i] = parAxe[a]
    end
    return ranges
end

local function indicesValides(indices)
    if indices == nil or indices == Json.null then
        return {}
    end
    if type(indices) ~= 'table' then
        echouer("Leçon : indices est une liste.")
    end
    if #indices > Carnet.MAX_INDICES then
        echouer(string.format("Leçon : %d indices, %d au plus.", #indices, Carnet.MAX_INDICES))
    end
    local propres = {}
    for _, d in ipairs(indices) do
        if type(d) ~= 'table' then
            echouer("Leçon : chaque indice est un objet { code, axe, libelle, preuve }.")
        end
        propres[#propres + 1] = {
            code = code(d.code, "Leçon, indice"),
            axe = (d.axe ~= nil and d.axe ~= Json.null) and axe(d.axe, "Leçon, indice") or nil,
            libelle = borne(d.libelle, Carnet.LONGUEUR_LIBELLE, "Leçon, indice, libellé"),
            preuve = borne(d.preuve, Carnet.LONGUEUR_PREUVE, "Leçon, indice, preuve"),
        }
    end
    return propres
end

-- Commande lecon --------------------------------------------------------------------------------

-- garder { photo?, lecon = { points, indices? } } : la leçon de la photo (la photo active sans
-- photo), rangée sous l'entrée de son original ; la nouvelle remplace l'ancienne. Tout est vérifié
-- avant de toucher au registre.
local function garder(params)
    local lecon = params.lecon
    if type(lecon) ~= 'table' then
        echouer("Leçon manquante : donner lecon = { points, indices? }.")
    end
    local points = pointsValides(lecon.points)
    local indices = indicesValides(lecon.indices)
    local lu = lirePhoto(Photos.photoVisee(params))
    local chemin = cheminCatalogue()
    -- Plus aucune lecture du catalogue jusqu'au fichier écrit : le registre change d'un coup.
    local e = entreeDe(tableDu(chemin, true), lu)
    local cle = cleDe(lu.id)
    local ancienne = e.lecons[cle]
    local remplacee = ancienne ~= nil and (ancienne.uuid == nil or lu.uuid == nil or ancienne.uuid == lu.uuid)
    local codes, vus = {}, {}
    for _, p in ipairs(points) do
        for _, d in ipairs(p.defauts) do
            if not vus[d.code] then
                vus[d.code] = true
                codes[#codes + 1] = d.code
            end
        end
    end
    local maintenant = os.time()
    e.lecons[cle] = { photo = lu.id, uuid = lu.uuid, fichier = lu.fichier, le = maintenant,
        points = points, defauts = codes, indices = indices }
    e.le = maintenant
    Liaison.noter("Leçon rangée : " .. lu.fichier, lu.id)
    local ok, raison = changer('lecon')
    return {
        photo = lu.id, original = lu.original, fichier = lu.fichier,
        rangee = true, remplacee = remplacee, mois = e.prise, prise_le = e.prise_le, sans_date = e.sans_date,
        remarque = not ok and ("Leçon gardée pour cette session, carnet.json non écrit : " .. tostring(raison)) or nil,
    }
end

-- Identifiants donnés (photo ou photos), en clés.
local function clesDonnees(params)
    local cles = {}
    if type(params.photos) == 'table' then
        for _, id in ipairs(params.photos) do
            cles[#cles + 1] = cleDe(id)
        end
    end
    if params.photo ~= nil then
        cles[#cles + 1] = cleDe(params.photo)
    end
    return cles
end

-- La photo d'une leçon est-elle encore celle-là (même uuid) ?
local function encoreLaPhoto(l)
    local ok, photo = LrTasks.pcall(Photos.photoParId, l.photo)
    return ok and (l.uuid == nil or Photos.brut(photo, 'uuid') == l.uuid)
end

-- lire { photos? } : les leçons de ces photos (vérifiées : une photo disparue, ou d'un autre uuid,
-- perd la sienne), ou toutes celles du catalogue ouvert, sans vérifier chaque photo.
local function lireLecons(params)
    local c = catalogueOuvert(false)
    local voulues
    local cles = clesDonnees(params)
    if #cles > 0 then
        voulues = {}
        for _, cle in ipairs(cles) do
            voulues[cle] = true
        end
    end
    -- Relevées d'abord : la vérification lit le catalogue (la tâche peut rendre la main), jamais
    -- pendant un parcours du registre.
    local candidates = {}
    for cleEntree, e in pairs(c.photos) do
        for cle, l in pairs(e.lecons) do
            if not voulues or voulues[cle] then
                candidates[#candidates + 1] = { cleEntree = cleEntree, cle = cle, entree = e, lecon = l }
            end
        end
    end
    local trouvees, perdues = {}, 0
    for _, x in ipairs(candidates) do
        if voulues and not encoreLaPhoto(x.lecon) then
            if x.entree.lecons[x.cle] == x.lecon then
                x.entree.lecons[x.cle] = nil
                retirerSiVide(c, x.cleEntree)
            end
            perdues = perdues + 1
        else
            trouvees[#trouvees + 1] = leconPourServeur(x.lecon, x.entree)
        end
    end
    if perdues > 0 then
        changer('retrait')
    end
    table.sort(trouvees, function(a, b) return a.photo < b.photo end)
    return { lecons = Json.tableau(trouvees), perdues = perdues > 0 and perdues or nil }
end

-- retirer { photo? | photos } : les leçons de ces photos (l'entrée de l'original part avec la
-- dernière, si elle n'a ni vue ni angle). Pour la recette, qui ne laisse rien au carnet.
local function retirerLecons(params)
    local cles = clesDonnees(params)
    if #cles == 0 then
        echouer("Leçon à retirer : donner photo ou photos.")
    end
    local c = catalogueOuvert(false)
    local retirees = 0
    for _, cle in ipairs(cles) do
        for cleEntree, e in pairs(c.photos) do
            if e.lecons[cle] then
                e.lecons[cle] = nil
                retirerSiVide(c, cleEntree)
                retirees = retirees + 1
            end
        end
    end
    if retirees > 0 then
        Liaison.noter(string.format("Leçon%s retirée%s du carnet : %d", retirees > 1 and "s" or "", retirees > 1 and "s" or "", retirees))
        changer('retrait')
    end
    return { retirees = retirees }
end

-- Commande lecon du serveur : garder, lire ou retirer. Rien n'est écrit dans le catalogue.
function Carnet.commandeLecon(params)
    local action = params.action
    if action == 'garder' then
        return garder(params)
    elseif action == 'lire' then
        return lireLecons(params)
    elseif action == 'retirer' then
        return retirerLecons(params)
    end
    echouer("Action de la leçon inconnue : " .. tostring(action) .. " (garder, lire ou retirer).")
end

-- Commande carnet -------------------------------------------------------------------------------

-- lire {} : { catalogue (son nom), nombre, photos } : les entrées du catalogue ouvert, leçons
-- comprises (en liste), sans vérifier chaque photo.
local function lireCarnet()
    local c, chemin = catalogueOuvert(false)
    local cles = {}
    for cle in pairs(c.photos) do
        cles[#cles + 1] = cle
    end
    table.sort(cles, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local photos = {}
    for _, cle in ipairs(cles) do
        photos[#photos + 1] = entreePourServeur(c.photos[cle])
    end
    -- Le nom du catalogue, comme la commande etat : jamais son chemin (la réponse va à Claude).
    return { catalogue = chemin and LrPathUtils.leafName(chemin) or nil, nombre = #photos, photos = Json.tableau(photos) }
end

-- retirer { photos } : les entrées de ces photos (l'identifiant d'un original, ou d'une copie
-- virtuelle : l'entrée de son original), leçons comprises.
local function retirerDuCarnet(params)
    local ids = {}
    for _, id in ipairs(type(params.photos) == 'table' and params.photos or {}) do
        ids[#ids + 1] = id
    end
    if params.photo ~= nil then
        ids[#ids + 1] = params.photo
    end
    if #ids == 0 then
        echouer("Photos à retirer du carnet : donner photos.")
    end
    local c = catalogueOuvert(false)
    local retirees, absentes = 0, Json.tableau()
    for _, id in ipairs(ids) do
        local cle = cleDe(id)
        if not c.photos[cle] then
            local ok, photo = LrTasks.pcall(Photos.photoParId, id)
            if ok then
                cle = cleDe(originalDe(photo).localIdentifier)
            end
        end
        if c.photos[cle] then
            c.photos[cle] = nil
            retirees = retirees + 1
        else
            absentes[#absentes + 1] = tonumber(id) or id
        end
    end
    if retirees > 0 then
        Liaison.noter(string.format("Carnet : %d photo%s retirée%s", retirees, retirees > 1 and "s" or "", retirees > 1 and "s" or ""))
        changer('retrait')
    end
    return { retirees = retirees, absentes = #absentes > 0 and absentes or nil }
end

-- Commande carnet du serveur : lire ou retirer. Rien n'est écrit dans le catalogue.
function Carnet.commande(params)
    local action = params.action
    if action == 'lire' then
        return lireCarnet()
    elseif action == 'retirer' then
        return retirerDuCarnet(params)
    end
    echouer("Action du carnet inconnue : " .. tostring(action) .. " (lire ou retirer).")
end

return Carnet
