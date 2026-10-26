-- Carnet.lua : le carnet de progrès (1.3), rangé dans carnet.json (à côté de notation.json), à part
-- du catalogue : rien n'y est écrit dans le catalogue, et sa commande n'est pas arrêtée par la pause
-- de la liaison (elle n'arrête que les écritures dans le catalogue). Commande du serveur :
--   carnet : constater (les défauts de la prise de vue que le connecteur a mesurés : vue ou
--            angle), lire (resume = true : avec le résumé, Carnet.resumer), retirer.
-- Elle écrit carnet.json : le serveur ne la rejoue jamais (LightroomBridge.lectures).
--
-- Les leçons des photos (1.3 à 1.3.5, retirées au correctif 1.3.6 avec photo_lesson) restent dans
-- les entrées qui en ont : le registre les garde telles qu'il les a lues (table relue par
-- Json.decode, jamais normalisée ni copiée), les réécrit telles quelles à chaque écriture du
-- fichier, et ne les montre plus nulle part (ni la fenêtre, ni le serveur) : jamais perdues,
-- même par retirer ou l'élagage (une entrée qui n'a plus qu'elles reste, sans compter au carnet).
--
-- Constats (carnet constater { photo, vue ou angle, vocabulaire, essai_recette? }) :
--   vue   = { cherches = { codes }, defauts = { { code, mesure?, texte? } } } : les défauts
--           cherchés sur le premier aperçu entier de view_photo, et ceux trouvés ; refusée
--           (note = false, avec la raison) si la photo a déjà des étapes de Claude, ou si c'est
--           la copie virtuelle d'un original qui en a (elle en a reçu les réglages) ;
--   angle = { inclinaison (degrés), code, source? } : une ligne penchée mesurée (measure_angle,
--           read_composition) ; refusé seulement si la géométrie est touchée (recadrage tourné,
--           Upright, perspective ou distorsion manuelle), pas après une passe de tonalité ;
--   vocabulaire : la liste des défauts du connecteur (PriseDeVue.vocabulaire) ; les codes de la vue
--           et de l'angle doivent y être. Elle est rangée (la fenêtre Suivi en tire libellés et
--           conseils) : aucune liste de défauts n'est écrite dans ce module.
-- Tout constat est refusé si la case Carnet est décochée (préférence carnet), et pour une photo
-- de « Développeur › Essais » (Carnet.estPhotoDEssai), sauf avec essai_recette = true, que seule la
-- recette envoie : la photo d'essai a alors son entrée à elle, jamais celle de son original (une
-- vraie photo), et retirer ne mène jamais d'une photo d'essai à l'entrée de son original. Une
-- nouvelle vue remplace l'ancienne, un nouvel angle aussi ; les leçons d'avant restent.
--
-- Le résumé (Carnet.resumer) compte, pour chaque défaut et par mois de prise de vue (les six
-- derniers qui ont des photos), les photos où il a été trouvé sur celles où il a été cherché ; il
-- dit ce qui progresse ou recule, et quoi travailler à la prochaine sortie. Ses phrases ne sont
-- écrites qu'ici : la fenêtre Suivi (FenetreSuivi.lua ; la page du carnet jusqu'au correctif
-- 1.3.6, puis un onglet Suivi de la fenêtre Claude) et export_journal (serveur) les reprennent.
--
-- Un seul fichier pour tous les catalogues : chacun garde sa table, sous son chemin (un
-- identifiant de photo ne vaut que dans son catalogue) ; changer de catalogue ne fait rien perdre
-- au premier (contrairement à notation.json). Dans un catalogue, une entrée par original
-- (masterPhoto) : une prise de vue ne compte qu'une fois, ses copies virtuelles comprises. Au-delà
-- de Carnet.MAX_PHOTOS originaux qui ont des constats dans un catalogue, les plus anciens (champ
-- le) perdent les leurs (et sortent, sauf leurs leçons d'avant).
--
-- Format 1 :
--   { format = 1, vocabulaire = { { code, cle, axe, domaine, libelle, conseil, mesure } } (le
--     dernier reçu, pour tous les catalogues), catalogues = { [chemin du catalogue] = { photos =
--     { ['<id de l'original>'] = entrée } } } }
--   entrée : { photo (id de l'original ; d'une photo d'essai, pour la recette), uuid, fichier,
--     prise ('AAAA-MM', heure locale), prise_le ('AAAA-MM-JJ HH:MM'), sans_date (vrai sans date de prise de vue : la photo compte alors au
--     mois du constat), le (dernier changement, os.time), vue { le, photo (id de la photo
--     mesurée, copie virtuelle comprise), cherches = { codes }, defauts = { { code, mesure, texte }
--     } }, angle { le, photo, inclinaison, code, source }, lecons? (les leçons d'avant le
--     correctif 1.3.6, { ['<id de la photo>'] = leçon }, gardées telles quelles) }
-- Un fichier illisible (ou d'un autre format) est mis de côté avant la première écriture
-- (carnet-illisible-<date>.json), jamais écrasé.
--
-- Chargeable sans l'interface ni la Bibliothèque (la fenêtre aussi s'en sert) : Preferences et
-- Recalage ne sont requis qu'au moment de constater. Tout ce qui sort vers une vue est une copie
-- neuve, sans métatable (Lightroom bloque sur une table relue par Json.decode) ; vers le serveur,
-- les listes sont des tableaux JSON, même vides.

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
-- Originaux qui ont des constats, au plus, par catalogue ; les plus anciens (champ le) sortent
-- au-delà.
Carnet.MAX_PHOTOS = 3000
-- Bornes de ce que le serveur envoie (il en vérifie de plus strictes) : codes de défauts d'une
-- vue, longueurs en octets (UTF-8).
Carnet.MAX_CODES = 12
Carnet.LONGUEUR_TEXTE = 600
Carnet.LONGUEUR_LIBELLE = 200
-- Constats : défauts du vocabulaire au plus, longueur du texte d'un défaut trouvé (« ciel brûlé :
-- 4,2 % du tiers haut en blanc pur »), en octets.
Carnet.MAX_VOCABULAIRE = 40
Carnet.LONGUEUR_CONSTAT = 200
-- Un recadrage tourné de moins que cela n'est pas tourné : le curseur de Lightroom va par 0,01°, et
-- un cadre calculé peut garder un reste de l'ordre de 1e-12.
Carnet.ANGLE_NUL = 0.005
-- La collection des photos d'essai (Recette.collectionDeRecette du serveur) : ses photos n'entrent
-- pas au carnet, sauf pour la recette.
Carnet.ESSAIS = { ensemble = 'Développeur', collection = 'Essais' }

-- Résumé : mois montrés (les derniers qui ont des photos) ; les deux derniers comparés aux trois
-- d'avant ; écart en points et photos de chaque côté pour une tendance ; taux et photos pour « à
-- travailler » (sur les deux derniers mois), et combien au plus ; photos au-dessous desquelles le
-- carnet le dit.
Carnet.MOIS_RESUME = 6
Carnet.MOIS_RECENTS = 2
Carnet.MOIS_AVANT = 3
Carnet.ECART_TENDANCE = 15
Carnet.BASE_TENDANCE = 5
Carnet.TAUX_A_TRAVAILLER = 20
Carnet.MIN_A_TRAVAILLER = 2
Carnet.MAX_A_TRAVAILLER = 3
Carnet.PHOTOS_SUFFISANTES = 5

-- Les mois en français : nom entier et abrégé (les mois de la fenêtre Suivi, la légende de l'aperçu).
Carnet.MOIS = { 'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre',
    'novembre', 'décembre' }
Carnet.MOIS_COURTS = { 'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.' }

-- Titres du résumé, repris par la fenêtre Suivi et par export_journal.
Carnet.TITRES = {
    carnet = "Carnet de progrès",
    defaut = "Défaut",
    progresse = "Ce qui progresse",
    recule = "Ce qui recule",
    a_travailler = "À travailler à la prochaine sortie",
}

-- Clés des listes : des tableaux JSON, même vides, vers le serveur et dans le fichier (registre et
-- résumé). Jamais `photos`, qui est une table par identifiant dans le registre. Les leçons d'avant
-- gardent, elles, les tableaux que Json.decode y a marqués (versJson).
local LISTES = { defauts = true, cherches = true, mois = true, par_mois = true, progresse = true, recule = true,
    a_travailler = true }

-- La marque des tableaux JSON (Json.tableau), qu'une table relue par Json.decode porte aussi.
local MARQUE_TABLEAU = getmetatable(Json.tableau())

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

-- Copie pour Json.encode : les listes (LISTES), et les tables déjà marquées tableaux (les leçons
-- d'avant, relues par Json.decode), marquées tableaux, même vides.
local function versJson(valeur, cle)
    if type(valeur) ~= 'table' or valeur == Json.null then
        return valeur
    end
    local t = {}
    for k, element in pairs(valeur) do
        t[k] = versJson(element, k)
    end
    if LISTES[cle] or getmetatable(valeur) == MARQUE_TABLEAU then
        return Json.tableau(t)
    end
    return t
end

-- L'entrée a-t-elle des constats (une vue ou un angle) ? Une entrée qui n'a plus que ses leçons
-- d'avant n'est plus au carnet : ni montrée, ni comptée, ni envoyée au serveur.
local function aDesConstats(e)
    return e ~= nil and (e.vue ~= nil or e.angle ~= nil)
end

-- Copie neuve d'une entrée pour une vue, sans ses leçons d'avant (plus montrées).
local function copieEntree(e)
    local r = copie(e)
    r.lecons = nil
    return r
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

-- Une vue relue : des codes en texte, des défauts avec leur code.
local function normaliserVue(v)
    if type(v) ~= 'table' then
        return nil
    end
    local cherches, defauts = {}, {}
    for _, c in ipairs(type(v.cherches) == 'table' and v.cherches or {}) do
        if texte(c) then
            cherches[#cherches + 1] = c
        end
    end
    for _, d in ipairs(type(v.defauts) == 'table' and v.defauts or {}) do
        if type(d) == 'table' and texte(d.code) then
            defauts[#defauts + 1] = { code = d.code, mesure = tonumber(d.mesure), texte = texte(d.texte) }
        end
    end
    return { le = tonumber(v.le) or 0, photo = tonumber(v.photo), cherches = cherches, defauts = defauts }
end

-- Un angle relu : sans inclinaison ni code, il ne compte pas.
local function normaliserAngle(a)
    if type(a) ~= 'table' or not tonumber(a.inclinaison) or not texte(a.code) then
        return nil
    end
    return { le = tonumber(a.le) or 0, photo = tonumber(a.photo), inclinaison = tonumber(a.inclinaison), code = a.code,
        source = texte(a.source) }
end

-- Le vocabulaire relu : les défauts qui ont un code.
local function normaliserVocabulaire(v)
    if type(v) ~= 'table' then
        return nil
    end
    local propre = {}
    for _, d in ipairs(v) do
        if type(d) == 'table' and texte(d.code) then
            propre[#propre + 1] = { code = d.code, cle = texte(d.cle), axe = texte(d.axe), domaine = texte(d.domaine),
                libelle = texte(d.libelle), conseil = texte(d.conseil), mesure = d.mesure == true or nil }
        end
    end
    return #propre > 0 and propre or nil
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
        vue = normaliserVue(e.vue),
        angle = normaliserAngle(e.angle),
        -- Les leçons d'avant, telles que Json.decode les a rendues (tableaux marqués compris) :
        -- rien ne les lit plus, enregistrer les réécrit à l'identique.
        lecons = type(e.lecons) == 'table' and e.lecons ~= Json.null and next(e.lecons) ~= nil and e.lecons or nil,
    }
    if not aDesConstats(propre) and not propre.lecons then
        return nil
    end
    return propre
end

local function vide()
    return { catalogues = {} }
end

-- Registre relu du fichier : des tables neuves, des clés de photo en texte.
local function normaliser(r)
    local propre = vide()
    propre.vocabulaire = normaliserVocabulaire(r.vocabulaire)
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

-- Les entrées les plus anciennes (champ le) d'un catalogue qui ont des constats, au-delà de
-- MAX_PHOTOS : leurs constats sortent, et l'entrée avec eux, sauf ses leçons d'avant.
local function elaguer(c)
    local entrees = {}
    for cle, e in pairs(c.photos) do
        if aDesConstats(e) then
            entrees[#entrees + 1] = { cle = cle, le = tonumber(e.le) or 0, photo = tonumber(cle) or 0 }
        end
    end
    if #entrees > Carnet.MAX_PHOTOS then
        table.sort(entrees, function(a, b)
            if a.le ~= b.le then
                return a.le < b.le
            end
            return a.photo < b.photo
        end)
        for i = 1, #entrees - Carnet.MAX_PHOTOS do
            local e = c.photos[entrees[i].cle]
            e.vue, e.angle = nil, nil
            if not e.lecons then
                c.photos[entrees[i].cle] = nil
            end
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
        vocabulaire = r.vocabulaire and Json.tableau(copie(r.vocabulaire)) or nil,
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

-- quoi : 'constat', 'retrait'.
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

-- Les clés des entrées du catalogue ouvert qui ont des constats, triées par identifiant de
-- l'original.
local function clesAvecConstats(c)
    local cles = {}
    for cle, e in pairs(c.photos) do
        if aDesConstats(e) then
            cles[#cles + 1] = cle
        end
    end
    table.sort(cles, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    return cles
end

-- Les entrées du catalogue ouvert (celles qui ont des constats), triées par identifiant de
-- l'original, sans leurs leçons d'avant.
function Carnet.entrees()
    local c = catalogueOuvert(false)
    local liste = {}
    for _, cle in ipairs(clesAvecConstats(c)) do
        liste[#liste + 1] = copieEntree(c.photos[cle])
    end
    return liste
end

-- L'entrée d'un original (identifiant de l'original), sans ses leçons d'avant ; nil sans constat.
function Carnet.entree(idOriginal)
    if idOriginal == nil then
        return nil
    end
    local e = catalogueOuvert(false).photos[cleDe(idOriginal)]
    return aDesConstats(e) and copieEntree(e) or nil
end

-- Nombre d'originaux au carnet du catalogue ouvert (ceux qui ont des constats ; diagnostic).
function Carnet.nombre()
    return #clesAvecConstats(catalogueOuvert(false))
end

-- Le dernier vocabulaire reçu du connecteur (libellés, domaines, conseils), dans son ordre ; une
-- liste vide avant le premier constat.
function Carnet.vocabulaire()
    return copie(charger().vocabulaire) or {}
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

-- La photo est-elle dans la collection Essais de l'ensemble Développeur ? Une lecture qui échoue
-- vaut non : la recette le verrait (son constat sur une copie d'essai doit être refusé), alors
-- qu'un oui à tort fermerait le carnet à toutes les photos sans bruit.
local function dansLesEssais(photo)
    local ok, oui = LrTasks.pcall(function()
        for _, collection in ipairs(photo:getContainedCollections() or {}) do
            if collection:getName() == Carnet.ESSAIS.collection then
                local parent = collection:getParent()
                if parent and parent:getName() == Carnet.ESSAIS.ensemble then
                    return true
                end
            end
        end
        return false
    end)
    return ok and oui == true
end

-- Les photos de « Développeur › Essais », lues d'un coup (correctif 1.3.8 : pour une grande
-- sélection, le Suivi ne demande plus ses collections à chaque photo, Releve.lua) : l'ensemble des
-- localIdentifier des photos de chaque collection Essais (pas une collection dynamique) d'un ensemble
-- Développeur du catalogue, la même règle que dansLesEssais. Rend { [localIdentifier] = true }, ou
-- nil si les collections ne se lisent pas (chaque photo se juge alors par Carnet.estPhotoDEssai).
function Carnet.photosDesEssais()
    local ok, ids = LrTasks.pcall(function()
        local trouvees = {}
        local function parcourir(parent, nom, profondeur)
            if nom == Carnet.ESSAIS.ensemble then
                for _, collection in ipairs(parent:getChildCollections() or {}) do
                    local dynamique = type(collection.isSmartCollection) == 'function' and collection:isSmartCollection()
                    if not dynamique and collection:getName() == Carnet.ESSAIS.collection then
                        for _, photo in ipairs(collection:getPhotos() or {}) do
                            trouvees[photo.localIdentifier] = true
                        end
                    end
                end
            end
            if profondeur < 20 then
                for _, ensemble in ipairs(parent:getChildCollectionSets() or {}) do
                    parcourir(ensemble, ensemble:getName(), profondeur + 1)
                end
            end
        end
        parcourir(Photos.catalogue(), nil, 0)
        return trouvees
    end)
    return ok and type(ids) == 'table' and ids or nil
end

-- Photo d'essai d'après Carnet.photosDesEssais : elle, ou son original (`original`, sa photo
-- maîtresse déjà lue ; nil pour un original), en est.
function Carnet.estDansLesEssais(essais, photo, original)
    return essais[photo.localIdentifier] == true or (original ~= nil and original ~= photo and essais[original.localIdentifier] == true)
end

-- Photo d'essai : elle, ou son original, est dans « Développeur › Essais ».
function Carnet.estPhotoDEssai(photo)
    if dansLesEssais(photo) then
        return true
    end
    local original = originalDe(photo)
    return original ~= photo and dansLesEssais(original)
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
-- passent par le catalogue (la tâche peut rendre la main), et une autre commande (retirer) ne doit
-- jamais voir une entrée à moitié faite. `original` : la photo dont l'entrée reçoit (par défaut
-- l'original ; une photo d'essai elle-même, voir constater).
local function lirePhoto(photo, original)
    original = original or originalDe(photo)
    local prise, priseLe = datesPrise(original)
    return {
        id = photo.localIdentifier, uuid = texte(Photos.brut(photo, 'uuid')), fichier = Photos.nomFichier(photo),
        original = original.localIdentifier, uuidOriginal = texte(Photos.brut(original, 'uuid')),
        fichierOriginal = Photos.nomFichier(original), prise = prise, prise_le = priseLe,
    }
end

-- L'entrée de l'original (lu par lirePhoto) dans la table d'un catalogue, créée au besoin. Une
-- entrée d'un autre uuid (une autre photo sous ce numéro) est remplacée, ses constats oubliés,
-- jamais ses leçons d'avant, qui restent (elles ne se lisent plus). L'uuid, le fichier et la date de
-- prise de vue sont repris à chaque fois. Sans lecture du catalogue.
local function entreeDe(c, lu)
    local cle = cleDe(lu.original)
    local e = c.photos[cle]
    if not e or (e.uuid and lu.uuidOriginal and e.uuid ~= lu.uuidOriginal) then
        e = { photo = lu.original, le = os.time(), lecons = e and e.lecons or nil }
        c.photos[cle] = e
    end
    e.uuid = lu.uuidOriginal
    e.fichier = lu.fichierOriginal
    e.prise, e.prise_le = lu.prise, lu.prise_le
    e.sans_date = not e.prise or nil
    return e
end

-- Une entrée pour le serveur : ses constats, les listes en tableaux JSON, sans l'uuid ni les
-- leçons d'avant.
local function entreePourServeur(e)
    local r = versJson(e)
    r.uuid = nil
    r.lecons = nil
    return r
end

-- Validation ------------------------------------------------------------------------------------

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

-- Constats : validation -------------------------------------------------------------------------

local function nombreFini(valeur)
    return type(valeur) == 'number' and valeur == valeur and valeur ~= math.huge and valeur ~= -math.huge
end

local function absent(valeur)
    return valeur == nil or valeur == Json.null
end

-- Un identifiant facultatif (axe, domaine, clé anglaise d'un défaut du vocabulaire ; source d'un
-- angle) : lettres minuscules et _.
local function identifiantFacultatif(valeur, quoi)
    if absent(valeur) then
        return nil
    end
    if type(valeur) ~= 'string' or not valeur:match('^[a-z_]+$') or #valeur > 40 then
        echouer(string.format("%s invalide « %s » (lettres minuscules et _).", quoi, tostring(valeur)))
    end
    return valeur
end

-- Le vocabulaire du connecteur (PriseDeVue.vocabulaire), vérifié en entier : la liste propre, et
-- l'ensemble de ses codes.
local function vocabulaireValide(vocabulaire)
    if type(vocabulaire) ~= 'table' or #vocabulaire == 0 then
        echouer("Constat : vocabulaire manquant (la liste des défauts du connecteur).")
    end
    if #vocabulaire > Carnet.MAX_VOCABULAIRE then
        echouer(string.format("Constat : vocabulaire de %d défauts, %d au plus.", #vocabulaire, Carnet.MAX_VOCABULAIRE))
    end
    local propre, connus = {}, {}
    for _, d in ipairs(vocabulaire) do
        if type(d) ~= 'table' then
            echouer("Constat : chaque défaut du vocabulaire est un objet { code, libelle, domaine, conseil }.")
        end
        local c = code(d.code, "Constat, vocabulaire")
        if connus[c] then
            echouer(string.format("Constat, vocabulaire : le code « %s » est donné deux fois.", c))
        end
        connus[c] = true
        local libelle = borne(d.libelle, Carnet.LONGUEUR_LIBELLE, "Constat, vocabulaire, libellé")
        if not libelle then
            echouer(string.format("Constat, vocabulaire : « %s » n'a pas de libellé.", c))
        end
        if not absent(d.mesure) and type(d.mesure) ~= 'boolean' then
            echouer(string.format("Constat, vocabulaire : mesure de « %s » est vrai ou faux.", c))
        end
        propre[#propre + 1] = {
            code = c, libelle = libelle,
            cle = identifiantFacultatif(d.cle, "Constat, vocabulaire : clé"),
            axe = identifiantFacultatif(d.axe, "Constat, vocabulaire : axe"),
            domaine = identifiantFacultatif(d.domaine, "Constat, vocabulaire : domaine"),
            conseil = borne(d.conseil, Carnet.LONGUEUR_TEXTE, "Constat, vocabulaire, conseil"),
            mesure = d.mesure == true or nil,
        }
    end
    return propre, connus
end

-- Un code du vocabulaire.
local function codeConnu(valeur, connus, quoi)
    local c = code(valeur, quoi)
    if not connus[c] then
        echouer(string.format("%s : « %s » n'est pas dans le vocabulaire.", quoi, c))
    end
    return c
end

-- Une liste de codes ou de défauts, de Carnet.MAX_CODES au plus.
local function listeDeCodes(valeur, quoi)
    if absent(valeur) then
        return {}
    end
    if type(valeur) ~= 'table' then
        echouer(quoi .. " est une liste.")
    end
    if #valeur > Carnet.MAX_CODES then
        echouer(string.format("%s : %d codes, %d au plus.", quoi, #valeur, Carnet.MAX_CODES))
    end
    return valeur
end

-- vue = { cherches, defauts } : les codes cherchés (un au moins), et les défauts trouvés parmi eux.
local function vueValide(vue, connus)
    if type(vue) ~= 'table' then
        echouer("Constat : vue est un objet { cherches, defauts }.")
    end
    local cherches, cherche = {}, {}
    for _, c in ipairs(listeDeCodes(vue.cherches, "Constat, cherches")) do
        c = codeConnu(c, connus, "Constat, cherches")
        if not cherche[c] then
            cherche[c] = true
            cherches[#cherches + 1] = c
        end
    end
    if #cherches == 0 then
        echouer("Constat : cherches est vide (les défauts cherchés sur cette vue).")
    end
    local defauts, vus = {}, {}
    for _, d in ipairs(listeDeCodes(vue.defauts, "Constat, defauts")) do
        local propre
        if type(d) == 'table' then
            if not absent(d.mesure) and not nombreFini(d.mesure) then
                echouer("Constat, defauts : mesure est un nombre.")
            end
            propre = { code = codeConnu(d.code, connus, "Constat, defauts"),
                mesure = not absent(d.mesure) and d.mesure or nil,
                texte = borne(d.texte, Carnet.LONGUEUR_CONSTAT, "Constat, defauts, texte") }
        else
            propre = { code = codeConnu(d, connus, "Constat, defauts") }
        end
        if not cherche[propre.code] then
            echouer(string.format("Constat : le défaut « %s » n'est pas dans cherches.", propre.code))
        end
        if not vus[propre.code] then
            vus[propre.code] = true
            defauts[#defauts + 1] = propre
        end
    end
    return { cherches = cherches, defauts = defauts }
end

-- angle = { inclinaison, code, source? } : une ligne penchée, mesurée en degrés.
local function angleValide(angle, connus)
    if type(angle) ~= 'table' then
        echouer("Constat : angle est un objet { inclinaison, code, source }.")
    end
    if not nombreFini(angle.inclinaison) then
        echouer("Constat : inclinaison manquante ou non numérique (en degrés).")
    end
    return { inclinaison = angle.inclinaison, code = codeConnu(angle.code, connus, "Constat, angle"),
        source = identifiantFacultatif(angle.source, "Constat, angle : source") }
end

-- Constats : commande -------------------------------------------------------------------------------

-- La case Carnet du Gestionnaire de modules externes (préférence carnet, cochée par défaut).
local function carnetCoche()
    local Preferences = require 'Preferences'
    return Preferences.lire().carnet ~= false
end

-- La géométrie de la photo est-elle touchée (recadrage tourné, Upright, perspective, distorsion
-- manuelle) ? Une ligne mesurée n'y dit plus l'inclinaison de la prise de vue. Une passe de
-- tonalité, elle, ne la change pas.
local function geometrieTouchee(photo)
    local Recalage = require 'Recalage'
    local actuels = photo:getDevelopSettings()
    return math.abs(tonumber(actuels.CropAngle) or 0) >= Carnet.ANGLE_NUL or Recalage.transformationActive(actuels)
end

local function refus(motif, raison, photo)
    return { note = false, motif = motif, raison = raison, photo = photo }
end

-- Une inclinaison en texte, au dixième de degré, sans passer par la locale (« 1,2° »).
local function degres(x)
    local d = math.floor(math.abs(x) * 10 + 0.5)
    return string.format('%d,%d°', math.floor(d / 10), d % 10)
end

-- constater { photo, vue ou angle, vocabulaire, essai_recette? } : rend { note = true, constat
-- ('vue' ou 'angle'), photo, original, fichier, mois, prise_le, sans_date, remplacee, remarque? },
-- ou { note = false, motif ('preference', 'essai', 'etapes', 'geometrie'), raison, photo }. Tout
-- est vérifié et lu (photo, collections, étapes, géométrie, chemin du catalogue) avant de toucher
-- au registre, qui change ensuite d'un coup : une autre commande passée pendant une lecture ne
-- voit jamais d'entrée à moitié faite. La photo est obligatoire : le constat vaut pour la photo
-- mesurée, jamais pour celle qui est active au moment où il arrive.
local function constater(params)
    if absent(params.photo) then
        echouer("Constat : photo manquante (l'identifiant de la photo mesurée).")
    end
    local vue, angle = params.vue, params.angle
    if absent(vue) then
        vue = nil
    end
    if absent(angle) then
        angle = nil
    end
    if (vue == nil) == (angle == nil) then
        echouer("Constat : donner vue (défauts mesurés sur l'aperçu entier) ou angle (ligne mesurée), l'un ou l'autre.")
    end
    local vocabulaire, connus = vocabulaireValide(params.vocabulaire)
    local constat
    if vue then
        constat = vueValide(vue, connus)
    else
        constat = angleValide(angle, connus)
    end
    if not carnetCoche() then
        return refus('preference', "Carnet de progrès décoché dans le Gestionnaire de modules externes : rien n'est noté.",
            tonumber(params.photo) or params.photo)
    end
    local photo = Photos.photoParId(params.photo)
    local id = photo.localIdentifier
    local essai = Carnet.estPhotoDEssai(photo)
    if essai and params.essai_recette ~= true then
        return refus('essai', "Photo d'essai (Développeur › Essais) : le carnet ne compte que les vraies prises de vue.", id)
    end
    -- L'entrée qui reçoit le constat : celle de l'original (une prise de vue ne compte qu'une
    -- fois). Une photo d'essai (la recette) a la sienne, jamais celle de son original : c'est une
    -- vraie photo de Dany, dont la recette ne doit ni remplacer la vue ni retirer l'entrée.
    local original = essai and photo or originalDe(photo)
    if vue then
        -- La mémoire de la photo elle-même (une copie virtuelle reçoit celle de son original, qui
        -- n'est pas la sienne : lireJson la lit vide).
        if #Photos.lireJson(photo, 'etapesClaude', {}) > 0 then
            return refus('etapes', "Photo déjà retouchée par Claude : sa prise de vue ne se mesure qu'avant la première retouche.",
                id)
        end
        -- Une copie virtuelle reçoit les réglages de son original au moment où elle est faite :
        -- celle d'une photo déjà retouchée par Claude montre ses retouches, pas la prise de vue, et
        -- sa vue remplacerait celle de l'original, prise avant. Refusée, au risque d'écarter une
        -- copie faite avant la retouche.
        if original ~= photo and #Photos.lireJson(original, 'etapesClaude', {}) > 0 then
            return refus('etapes', "Copie virtuelle d'une photo déjà retouchée par Claude : elle en a reçu les réglages ; "
                .. "la prise de vue se mesure sur l'original, avant sa première retouche.", id)
        end
    elseif geometrieTouchee(photo) then
        return refus('geometrie', "Géométrie déjà touchée (recadrage tourné, Upright, perspective ou distorsion) : "
            .. "la ligne mesurée ne dit plus l'inclinaison de la prise de vue.", id)
    end
    local lu = lirePhoto(photo, original)
    local chemin = cheminCatalogue()
    -- Plus aucune lecture du catalogue jusqu'au fichier écrit : le registre change d'un coup.
    local e = entreeDe(tableDu(chemin, true), lu)
    local maintenant = os.time()
    constat.le, constat.photo = maintenant, lu.id
    local remplacee
    if vue then
        remplacee = e.vue ~= nil
        e.vue = constat
    else
        remplacee = e.angle ~= nil
        e.angle = constat
    end
    e.le = maintenant
    charger().vocabulaire = vocabulaire
    if vue then
        Liaison.noter(string.format("Carnet : prise de vue notée pour %s (%d défaut%s sur %d cherché%s)", lu.fichier,
            #constat.defauts, #constat.defauts > 1 and "s" or "", #constat.cherches, #constat.cherches > 1 and "s" or ""), lu.id)
    else
        Liaison.noter("Carnet : ligne penchée de " .. degres(constat.inclinaison) .. " notée pour " .. lu.fichier, lu.id)
    end
    local ok, raison = changer('constat')
    return {
        note = true, constat = vue and 'vue' or 'angle', photo = lu.id, original = lu.original, fichier = lu.fichier,
        mois = e.prise, prise_le = e.prise_le, sans_date = e.sans_date, remplacee = remplacee,
        remarque = not ok and ("Constat gardé pour cette session, carnet.json non écrit : " .. tostring(raison)) or nil,
    }
end

-- Résumé -------------------------------------------------------------------------------------------

-- 'AAAA-MM' d'un mois, ou nil.
local function cleMois(valeur)
    if type(valeur) ~= 'string' then
        return nil
    end
    local annee, numero = valeur:match('^(%d%d%d%d)%-(%d%d)$')
    numero = tonumber(numero)
    if not annee or not numero or numero < 1 or numero > 12 then
        return nil
    end
    return valeur
end

local function decrireMois(cle)
    local annee, numero = cle:match('^(%d%d%d%d)%-(%d%d)$')
    annee, numero = tonumber(annee), tonumber(numero)
    return { cle = cle, annee = annee, numero = numero, nom = Carnet.MOIS[numero], court = Carnet.MOIS_COURTS[numero],
        libelle = Carnet.MOIS[numero] .. ' ' .. annee }
end

-- Le mois où une entrée compte : celui de sa prise de vue ; sans date, celui de son constat.
local function moisDe(e)
    if e.prise then
        return cleMois(e.prise)
    end
    local t = (e.vue and e.vue.le) or (e.angle and e.angle.le) or e.le
    t = tonumber(t)
    if not t or t <= 0 then
        return nil
    end
    local ok, m = pcall(os.date, '%Y-%m', t)
    return ok and cleMois(m) or nil
end

-- Les défauts cherchés et trouvés sur une entrée (code → vrai ; code → { mesure, texte, photo }).
-- Un défaut trouvé est aussi cherché ; l'angle compte pour son code.
local function constatsDe(e)
    local cherches, trouves = {}, {}
    if e.vue then
        for _, c in ipairs(e.vue.cherches) do
            cherches[c] = true
        end
        for _, d in ipairs(e.vue.defauts) do
            cherches[d.code] = true
            trouves[d.code] = trouves[d.code] or { mesure = d.mesure, texte = d.texte, photo = e.vue.photo }
        end
    end
    if e.angle then
        cherches[e.angle.code] = true
        trouves[e.angle.code] = { mesure = e.angle.inclinaison, photo = e.angle.photo }
    end
    return cherches, trouves
end

-- Les entrées du catalogue ouvert rangées par mois (les MOIS_RESUME derniers qui en ont, jusqu'au
-- mois de `maintenant`) : { mois = { clés, du plus ancien au plus récent }, parMois = { [clé] =
-- { { entree, cherches, trouves } } }, apres (photos datées après ce mois, pas comptées) }.
local function selection(maintenant)
    local actuel = cleMois(os.date('%Y-%m', maintenant))
    local parMois, apres = {}, 0
    for _, e in pairs(catalogueOuvert(false).photos) do
        local cherches, trouves = constatsDe(e)
        local m = next(cherches) ~= nil and moisDe(e) or nil
        if m and actuel and m > actuel then
            apres = apres + 1
        elseif m then
            parMois[m] = parMois[m] or {}
            table.insert(parMois[m], { entree = e, cherches = cherches, trouves = trouves })
        end
    end
    local cles = {}
    for m in pairs(parMois) do
        cles[#cles + 1] = m
    end
    table.sort(cles)
    local mois = {}
    for i = math.max(1, #cles - Carnet.MOIS_RESUME + 1), #cles do
        mois[#mois + 1] = cles[i]
    end
    return { mois = mois, parMois = parMois, apres = apres }
end

local function taux(n, sur)
    return math.floor(100 * n / sur + 0.5)
end

local function photosTexte(n)
    return string.format(n > 1 and "%d photos" or "%d photo", n)
end

-- « de » devant un mois : « d'avril », « d'août », « d'octobre ».
local function de(mot)
    return (mot:match('^[aeiou]') and "d'" or "de ") .. mot
end

-- La période d'une suite de mois : « en mai 2026 », « en septembre et octobre 2026 », « de mai à
-- juillet 2026 », « de décembre 2025 à février 2026 ».
local function periode(mois)
    local n = #mois
    if n == 0 then
        return nil
    end
    local premier, dernier = mois[1], mois[n]
    if n == 1 then
        return "en " .. premier.libelle
    end
    local debut = premier.annee == dernier.annee and premier.nom or premier.libelle
    if n == 2 then
        return string.format("en %s et %s", debut, dernier.libelle)
    end
    return string.format("%s à %s", de(debut), dernier.libelle)
end

-- Somme de n et sur sur les mois i à j d'un défaut.
local function somme(d, i, j)
    local n, sur = 0, 0
    for k = i, j do
        n, sur = n + d.par_mois[k].n, sur + d.par_mois[k].sur
    end
    return { n = n, sur = sur }
end

-- « progresse » si le taux baisse d'au moins ECART_TENDANCE points des mois d'avant aux mois
-- récents, « recule » s'il monte d'autant ; rien sans BASE_TENDANCE photos de chaque côté. En
-- nombres entiers : 100 × (nA × sR − nR × sA) comparé à l'écart × sA × sR.
local function tendance(avant, recent)
    if avant.sur < Carnet.BASE_TENDANCE or recent.sur < Carnet.BASE_TENDANCE then
        return nil
    end
    local difference = 100 * (avant.n * recent.sur - recent.n * avant.sur)
    local seuil = Carnet.ECART_TENDANCE * avant.sur * recent.sur
    if difference >= seuil then
        return 'progresse'
    elseif -difference >= seuil then
        return 'recule'
    end
    return nil
end

-- Le résumé du carnet du catalogue ouvert, au moment `maintenant` (os.time ; par défaut,
-- maintenant) : des tables neuves, sans métatable.
--   { le, vide, photos (comptées), mois = { { cle, annee, numero, nom, court, libelle, photos,
--     recent } }, periode, defauts = { { code, libelle, domaine, conseil, par_mois = { { n, sur } }
--     (un par mois), n, sur, taux, avant = { n, sur }, recent = { n, sur }, tendance } },
--     progresse = { { code, libelle, texte } }, recule (de même), a_travailler = { { code,
--     libelle, n, sur, taux, texte, conseil, prise_de_vue } }, titres, note, remarque?,
--     aucune_tendance?, rien_a_travailler? }
-- Un défaut est montré s'il a été cherché sur une photo des mois montrés ; dans l'ordre du
-- vocabulaire, puis des codes.
function Carnet.resumer(maintenant)
    maintenant = tonumber(maintenant) or os.time()
    local sel = selection(maintenant)
    local vocabulaire = charger().vocabulaire or {}
    local parCode, rang = {}, {}
    for i, d in ipairs(vocabulaire) do
        parCode[d.code], rang[d.code] = d, i
    end

    local mois, total, codes, vus = {}, 0, {}, {}
    for _, cle in ipairs(sel.mois) do
        local m = decrireMois(cle)
        m.photos = #sel.parMois[cle]
        total = total + m.photos
        mois[#mois + 1] = m
        for _, x in ipairs(sel.parMois[cle]) do
            for c in pairs(x.cherches) do
                if not vus[c] then
                    vus[c] = true
                    codes[#codes + 1] = c
                end
            end
        end
    end
    table.sort(codes, function(a, b)
        local ra, rb = rang[a] or math.huge, rang[b] or math.huge
        if ra ~= rb then
            return ra < rb
        end
        return a < b
    end)

    local nb = #mois
    local debutRecent = math.max(1, nb - Carnet.MOIS_RECENTS + 1)
    local debutAvant = math.max(1, debutRecent - Carnet.MOIS_AVANT)
    local recents, avants = {}, {}
    for i = debutRecent, nb do
        mois[i].recent = true
        recents[#recents + 1] = mois[i]
    end
    for i = debutAvant, debutRecent - 1 do
        avants[#avants + 1] = mois[i]
    end
    local periodeRecente, periodeAvant = periode(recents), periode(avants)

    local defauts, progresse, recule, aTravailler = {}, {}, {}, {}
    for _, c in ipairs(codes) do
        local v = parCode[c] or {}
        local d = { code = c, libelle = v.libelle or c, domaine = v.domaine, conseil = v.conseil, par_mois = {}, n = 0, sur = 0 }
        for i, m in ipairs(mois) do
            local n, sur = 0, 0
            for _, x in ipairs(sel.parMois[m.cle]) do
                if x.cherches[c] then
                    sur = sur + 1
                    if x.trouves[c] then
                        n = n + 1
                    end
                end
            end
            d.par_mois[i] = { n = n, sur = sur }
            d.n, d.sur = d.n + n, d.sur + sur
        end
        d.taux = d.sur > 0 and taux(d.n, d.sur) or nil
        d.recent = somme(d, debutRecent, nb)
        d.avant = somme(d, debutAvant, debutRecent - 1)
        d.tendance = tendance(d.avant, d.recent)
        defauts[#defauts + 1] = d
        if d.tendance then
            local item = { code = c, libelle = d.libelle, texte = string.format("%s : %d %% des photos %s, %d %% %s.", d.libelle,
                taux(d.avant.n, d.avant.sur), periodeAvant, taux(d.recent.n, d.recent.sur), periodeRecente) }
            table.insert(d.tendance == 'progresse' and progresse or recule, item)
        end
        if d.recent.n >= Carnet.MIN_A_TRAVAILLER and 100 * d.recent.n >= Carnet.TAUX_A_TRAVAILLER * d.recent.sur then
            aTravailler[#aTravailler + 1] = { code = c, libelle = d.libelle, n = d.recent.n, sur = d.recent.sur,
                taux = taux(d.recent.n, d.recent.sur), conseil = d.conseil, rang = #defauts,
                texte = string.format("%s : %s sur %d (%d %%) %s.", d.libelle, photosTexte(d.recent.n), d.recent.sur,
                    taux(d.recent.n, d.recent.sur), periodeRecente),
                prise_de_vue = d.conseil and ("À la prise de vue : " .. d.conseil) or nil }
        end
    end
    -- Le plus fréquent d'abord (taux, puis nombre de photos, puis l'ordre du vocabulaire).
    table.sort(aTravailler, function(a, b)
        if a.n * b.sur ~= b.n * a.sur then
            return a.n * b.sur > b.n * a.sur
        end
        if a.n ~= b.n then
            return a.n > b.n
        end
        return a.rang < b.rang
    end)
    for i = #aTravailler, 1, -1 do
        aTravailler[i].rang = nil
        if i > Carnet.MAX_A_TRAVAILLER then
            table.remove(aTravailler, i)
        end
    end

    local titres = {}
    for cle, titre in pairs(Carnet.TITRES) do
        titres[cle] = titre
    end
    local resume = {
        le = maintenant, vide = total == 0, photos = total, mois = mois, periode = periode(mois),
        defauts = defauts, progresse = progresse, recule = recule, a_travailler = aTravailler, titres = titres,
    }
    if total == 0 then
        resume.note = "Le carnet se remplit tout seul : quand Claude regarde une photo pas encore retouchée, "
            .. "les défauts mesurés de sa prise de vue y sont notés, par mois de prise de vue."
    else
        resume.note = string.format("Défauts de la prise de vue mesurés par Claude sur %s, par mois de prise de vue (%s). "
            .. "Seules les photos montrées à Claude comptent, pas toute la sortie.", photosTexte(total), resume.periode)
        if #progresse == 0 and #recule == 0 then
            resume.aucune_tendance = string.format("Pas encore de tendance : il faut %d photos au moins sur les %d derniers mois, "
                .. "et %d sur les %d d'avant.", Carnet.BASE_TENDANCE, Carnet.MOIS_RECENTS, Carnet.BASE_TENDANCE, Carnet.MOIS_AVANT)
        end
        if #aTravailler == 0 then
            resume.rien_a_travailler = string.format("Aucun défaut ne revient sur %d %% des photos ou plus %s.",
                Carnet.TAUX_A_TRAVAILLER, periodeRecente)
        end
    end
    local remarques = {}
    if total > 0 and total < Carnet.PHOTOS_SUFFISANTES then
        remarques[#remarques + 1] = string.format("Seulement %s : le carnet dira plus après quelques sorties.", photosTexte(total))
    end
    if sel.apres == 1 then
        remarques[#remarques + 1] = "1 photo datée après aujourd'hui n'est pas comptée (horloge de l'appareil ?)."
    elseif sel.apres > 1 then
        remarques[#remarques + 1] = string.format(
            "%d photos datées après aujourd'hui ne sont pas comptées (horloge de l'appareil ?).", sel.apres)
    end
    resume.remarque = #remarques > 0 and table.concat(remarques, ' ') or nil
    return resume
end

-- Les photos où un défaut a été trouvé, dans les mois du résumé (au même moment) : le plus récent
-- d'abord. { { original, photo (la photo mesurée), fichier, mois, mois_libelle, mesure, texte } },
-- des tables neuves (la fenêtre de ce défaut).
function Carnet.photosDuDefaut(codeDefaut, maintenant)
    local sel = selection(tonumber(maintenant) or os.time())
    local trouvees = {}
    for _, cle in ipairs(sel.mois) do
        for _, x in ipairs(sel.parMois[cle]) do
            local t = x.trouves[codeDefaut]
            if t then
                local e = x.entree
                trouvees[#trouvees + 1] = { original = e.photo, photo = t.photo or e.photo, fichier = e.fichier, mois = cle,
                    mois_libelle = decrireMois(cle).libelle, mesure = t.mesure, texte = t.texte }
            end
        end
    end
    table.sort(trouvees, function(a, b)
        if a.mois ~= b.mois then
            return a.mois > b.mois
        end
        if (a.fichier or '') ~= (b.fichier or '') then
            return (a.fichier or '') < (b.fichier or '')
        end
        return a.original < b.original
    end)
    return trouvees
end

-- Commande carnet -------------------------------------------------------------------------------

-- lire { resume? } : { catalogue (son nom), nombre, photos, resume? } : les entrées du catalogue
-- ouvert qui ont des constats (sans les leçons d'avant), sans vérifier chaque photo ; avec
-- resume = true, le résumé (Carnet.resumer), ses listes en tableaux JSON.
local function lireCarnet(params)
    local c, chemin = catalogueOuvert(false)
    local photos = {}
    for _, cle in ipairs(clesAvecConstats(c)) do
        photos[#photos + 1] = entreePourServeur(c.photos[cle])
    end
    -- Le nom du catalogue, comme la commande etat : jamais son chemin (la réponse va à Claude).
    return { catalogue = chemin and LrPathUtils.leafName(chemin) or nil, nombre = #photos, photos = Json.tableau(photos),
        resume = params.resume == true and versJson(Carnet.resumer(os.time())) or nil }
end

-- retirer { photos } : les constats de ces photos (l'identifiant d'un original, ou d'une copie
-- virtuelle : l'entrée de son original) ; l'entrée part avec eux, sauf ses leçons d'avant, qui
-- restent (jamais perdues). Une photo d'essai sans entrée à elle ne mène jamais à celle de son
-- original (une vraie photo) : la recette retire ce qu'elle a constaté, et rien d'autre, même après
-- un constat refusé. Les photos sont lues d'abord (la tâche peut rendre la main), puis le registre
-- change d'un coup.
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
    local chemin = cheminCatalogue()
    local cles = {}
    for i, id in ipairs(ids) do
        local cle = cleDe(id)
        if not aDesConstats(tableDu(chemin, false).photos[cle]) then
            local ok, photo = LrTasks.pcall(Photos.photoParId, id)
            if ok and not Carnet.estPhotoDEssai(photo) then
                cle = cleDe(originalDe(photo).localIdentifier)
            end
        end
        cles[i] = cle
    end
    local c = tableDu(chemin, false)
    local retirees, absentes = 0, Json.tableau()
    for i, id in ipairs(ids) do
        local cle = cles[i]
        local e = c.photos[cle]
        if aDesConstats(e) then
            e.vue, e.angle = nil, nil
            if not e.lecons then
                c.photos[cle] = nil
            end
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

-- Commande carnet du serveur : constater, lire ou retirer. Rien n'est écrit dans le catalogue.
function Carnet.commande(params)
    local action = params.action
    if action == 'constater' then
        return constater(params)
    elseif action == 'lire' then
        return lireCarnet(params)
    elseif action == 'retirer' then
        return retirerDuCarnet(params)
    end
    echouer("Action du carnet inconnue : " .. tostring(action) .. " (constater, lire ou retirer).")
end

return Carnet
