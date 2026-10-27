-- essais-releve.lua : le relevé du Suivi et son analyse d'office (correctif 1.3.7, Releve.lua),
-- hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua), d'après le contrat figé
-- (Tests/Contrats/suivi.json) : une photo seule, un groupe, une copie virtuelle comptée par son
-- original une seule fois, les photos de « Développeur › Essais » et les vidéos refusées, la pause
-- de l'analyse pendant que Claude travaille ou que la liaison sert (les vues se rangent quand même),
-- les vues en attente fondues sans en perdre une, les écritures espacées, un fichier illisible mis
-- de côté (jamais écrasé), les bornes, la file (essais, abandon, jamais refaite après une édition,
-- règles plus récentes), le connecteur muet, qui refuse ou absent, le Suivi éteint par Arret.lua
-- (la tâche s'arrête après son attente, sans plus rien écrire), les branchements sur la fenêtre
-- Claude et la Demande rapide, rien d'écrit au catalogue, et uninstall.sh. Le connecteur est imité par un faux
-- `mcp-developpeur --analyser` (un script LuaJIT écrit ici), qui lit le contrat et répond sa sortie
-- pour les photos qu'il donne, comme le vrai : une vignette absente le dit, une autre photo a les
-- défauts cherchés des règles du contrat. Ni Lightroom, ni Claude, ni vraies photos ; les fichiers
-- vont dans un dossier personnel temporaire.
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

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

-- Deux valeurs JSON égales (noms, formes, valeurs, ordre des tableaux), la marque des tableaux
-- comprise (Json.tableau, que Json.decode pose) : un tableau JSON vide ([]) n'est pas un objet vide
-- ({}).
local MARQUE = getmetatable(require('Json').tableau())
local function memes(attendu, obtenu, chemin)
    chemin = chemin or 'valeur'
    if type(attendu) ~= type(obtenu) then
        error(string.format('%s : attendu %s, obtenu %s', chemin, type(attendu), type(obtenu)), 2)
    end
    if type(attendu) == 'table' and (getmetatable(attendu) == MARQUE) ~= (getmetatable(obtenu) == MARQUE) then
        error(string.format('%s : attendu %s, obtenu %s', chemin, getmetatable(attendu) == MARQUE and 'un tableau' or 'un objet',
            getmetatable(obtenu) == MARQUE and 'un tableau' or 'un objet'), 2)
    end
    if type(attendu) ~= 'table' then
        if attendu ~= obtenu then
            error(string.format('%s : attendu %q, obtenu %q', chemin, tostring(attendu), tostring(obtenu)), 2)
        end
        return
    end
    for cle, v in pairs(attendu) do
        memes(v, obtenu[cle], chemin .. '.' .. tostring(cle))
    end
    for cle in pairs(obtenu) do
        if attendu[cle] == nil then
            error(string.format('%s.%s : en trop (%s)', chemin, tostring(cle), tostring(obtenu[cle])), 2)
        end
    end
end

-- Aucune métatable, à aucun niveau (une table donnée à une vue).
local function neuve(valeur, chemin)
    if type(valeur) ~= 'table' then
        return
    end
    vrai(getmetatable(valeur) == nil, (chemin or 'valeur') .. ' : métatable')
    for cle, v in pairs(valeur) do
        neuve(v, (chemin or 'valeur') .. '.' .. tostring(cle))
    end
end

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Lightroom = require 'Lightroom'
local Notation = require 'Notation'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local FenetreRapide = require 'FenetreRapide'
local Moteur = require 'Moteur'
local Releve = require 'Releve'

local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false

-- L'écart entre deux écritures du relevé dans Lightroom ; les essais écrivent à chaque fois (0),
-- sauf ceux des écritures espacées.
local DELAI_ECRITURE = Releve.DELAI_ECRITURE
-- Les bornes du module, avant que les essais ne les changent (depart les remet à celles du contrat).
local BORNES_DU_MODULE = { max_originaux = Releve.MAX_ORIGINAUX, max_vues = Releve.MAX_VUES, max_selection = Releve.MAX_SELECTION,
    lot_analyse = Releve.LOT_ANALYSE, essais_analyse = Releve.ESSAIS_ANALYSE }

local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
local CONTRAT_CHEMIN = dossierTests .. '/../../Contrats/suivi.json'

-- Le contrat, sans ses commentaires (_note, _lisez_moi).
local function sansNotes(v)
    if type(v) ~= 'table' then
        return v
    end
    local t = {}
    for cle, element in pairs(v) do
        if cle ~= '_note' and cle ~= '_lisez_moi' then
            t[cle] = sansNotes(element)
        end
    end
    return setmetatable(t, getmetatable(v))
end
local CONTRAT = sansNotes(Json.decode(assert(Fichiers.lire(CONTRAT_CHEMIN), 'contrat suivi.json')))
local REGISTRE = CONTRAT.exemples.registre.fichier
local CATALOGUE = next(REGISTRE.catalogues)
local ANALYSER = CONTRAT.exemples.analyser
local BORNES = CONTRAT.regles.registre.bornes

-- Les journaux : ce que le Suivi dit.
local journal = {}
local noterVraiment = Journal.noter
Journal.noter = function(...)
    journal[#journal + 1] = table.concat((function(...)
        local t = {}
        for i = 1, select('#', ...) do
            t[i] = tostring((select(i, ...)))
        end
        return t
    end)(...), ' ')
    return noterVraiment(...)
end
local function journalContient(morceau)
    for _, ligne in ipairs(journal) do
        if ligne:find(morceau, 1, true) then
            return true
        end
    end
    return false
end

-- Une vraie image JPEG, que Lightroom rendrait comme vignette (paysage 3:2).
local JPEG
do
    local chemin = S.home .. '/source.jpg'
    S.executer('/usr/bin/sips -s format jpeg -z 200 300 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out '
        .. S.q(chemin) .. ' >/dev/null 2>&1')
    JPEG = assert(Fichiers.lire(chemin), 'JPEG source')
end

-- Le faux connecteur --------------------------------------------------------------------------------

-- `mcp-developpeur --analyser '<json>'` : note ce qu'il reçoit (une ligne par appel), puis répond
-- d'après son mode (fichier faux-mode) : « contrat » (la sortie du contrat pour les photos qu'il
-- donne, sinon les défauts cherchés de ses règles, aucun trouvé, et le genre « paysage » ; un objectif
-- macro donne « macro »), « regles2 » (de même, règles 2), « genre2 » (de même, règles du genre 2, le
-- genre « ville »), « sansgenre » (un connecteur d'avant le correctif 1.3.8 : ni genre ni
-- regles_genre), « muet » (rien : l'alarme, ou un vieux connecteur), « refus » (ok faux). Une vignette
-- absente le dit, comme le vrai.
local CONNECTEUR = S.home .. '/bin/mcp-developpeur'
local RECUS = S.home .. '/analyser-recus.txt'
local MODE = S.home .. '/faux-mode'
do
    local luajit = S.lireCommande('command -v luajit'):gsub('%s+$', '')
    local script = S.home .. '/bin/faux-analyser.lua'
    Fichiers.ecrire(script, string.format([==[
package.path = %q .. '/?.lua;' .. package.path
local Json = require 'Json'
local function lire(chemin)
    local f = io.open(chemin, 'rb')
    if not f then return nil end
    local t = f:read('*a')
    f:close()
    return t
end
if arg[1] ~= '--analyser' or #arg ~= 2 then
    io.stderr:write('usage : mcp-developpeur --analyser <json>\n')
    os.exit(2)
end
local recus = io.open(%q, 'ab')
recus:write(arg[2], '\n')
recus:close()
local mode = (lire(%q) or 'contrat'):gsub('%%s+$', '')
if mode == 'muet' then os.exit(0) end
if mode == 'refus' then
    print(Json.encode({ ok = false, raison = 'arguments', texte = "Arguments de --analyser : refusés par l'essai." }))
    os.exit(1)
end
local contrat = Json.decode(lire(%q))
local sorties = {}
for _, p in ipairs(contrat.exemples.analyser.sortie.photos) do sorties[p.id] = p end
local entree = Json.decode(arg[2])
local photos = Json.tableau()
for _, p in ipairs(entree.photos) do
    local lot = p.vignette:match('(.*)/[^/]*$')
    if not lire(p.vignette) then
        photos[#photos + 1] = { id = p.id, raison = 'vignette_absente', texte = 'Vignette introuvable : ' .. p.vignette .. '.' }
    elseif sorties[p.id] then
        local s = sorties[p.id]
        if s.texte then s.texte = s.texte:gsub('<lot>', lot) end
        if mode == 'sansgenre' then s.genre = nil end
        photos[#photos + 1] = s
    else
        local cherches = Json.tableau()
        if not p.retouchee then
            cherches[1], cherches[2], cherches[3] = 'sous_exposition', 'surexposition', 'ciel_brule'
            if (p.iso or 0) >= 1600 then cherches[#cherches + 1] = 'bruit' end
        end
        cherches[#cherches + 1] = 'flou'
        local genre = mode == 'genre2' and 'ville' or (p.objectif and p.objectif:lower():find('macro', 1, true)) and 'macro' or 'paysage'
        photos[#photos + 1] = { id = p.id, cherches = cherches, defauts = Json.tableau(), genre = mode ~= 'sansgenre' and genre or nil,
            mesures = { cote = 1024 } }
    end
end
print(Json.encode({ ok = true, regles = mode == 'regles2' and 2 or 1, regles_genre = mode == 'genre2' and 2 or mode ~= 'sansgenre' and 1 or nil,
    photos = photos }))
]==], S.plugin, RECUS, MODE, CONTRAT_CHEMIN))
    Fichiers.ecrire(CONNECTEUR, string.format('#!/bin/sh\nexec %s %s "$@"\n', S.q(luajit), S.q(script)))
    S.executer('chmod +x ' .. S.q(CONNECTEUR))
end
prefs.cheminConnecteur = CONNECTEUR

-- Les appels reçus par le faux connecteur, décodés.
local function recus()
    local liste = {}
    for ligne in (Fichiers.lire(RECUS) or ''):gmatch('[^\n]+') do
        liste[#liste + 1] = Json.decode(ligne)
    end
    return liste
end

local function mode(m)
    Fichiers.ecrire(MODE, m)
end

-- Catalogue simulé ------------------------------------------------------------------------------------

local PHOTOS, ACTIVE, SELECTION = {}, nil, {}
-- Les vignettes demandées à Lightroom ({ id, taille }), et ce qui se passe à chaque demande.
local VIGNETTES, pendantVignette = {}, nil
-- Les lectures groupées du catalogue, et les collections demandées photo par photo
-- (getContainedCollections : Carnet.estPhotoDEssai).
local GROUPEES = 0
local COLLECTIONS_DEMANDEES = 0

local COLLECTION_ESSAIS = {
    getName = function() return 'Essais' end,
    getParent = function() return { getName = function() return 'Développeur' end } end,
}
local AUTRE_COLLECTION = { getName = function() return 'Essais' end, getParent = function() return { getName = function() return 'Voyages' end } end }

-- « 2026-11-19 15:30 » en date de Lightroom (ici des secondes Unix, comme le LrDate simulé).
local function dateDe(texte)
    local a, mo, j, h, mi = tostring(texte or ''):match('^(%d+)%-(%d+)%-(%d+) (%d+):(%d+)$')
    if not a then
        return nil
    end
    return os.time { year = tonumber(a), month = tonumber(mo), day = tonumber(j), hour = tonumber(h), min = tonumber(mi), sec = 0 }
end

-- Une photo simulée : `v` donne uuid, fichier, copie (nom de la copie virtuelle), copieDe (l'id de
-- son original), format, prise (« AAAA-MM-JJ HH:MM »), appareil, objectif, focale, ouverture,
-- vitesse, iso, note, drapeau (pickStatus), essai (dans « Développeur › Essais »), autre (dans une
-- autre collection Essais), retouchee (la mémoire de Claude, la sienne), sansVignette.
local function photo(id, v)
    v = v or {}
    local ph = { localIdentifier = id, brut = {}, formate = {}, proprietes = {}, v = v }
    ph.brut.uuid = v.uuid or string.format('UUID-%d', id)
    ph.brut.virtualCopies = {}
    ph.brut.isVirtualCopy = v.copieDe ~= nil
    if v.copieDe then
        ph.brut.masterPhoto = PHOTOS[v.copieDe]
        table.insert(PHOTOS[v.copieDe].brut.virtualCopies, ph)
    end
    ph.brut.fileFormat = v.format or 'RAW'
    ph.brut.dateTimeOriginal = dateDe(v.prise)
    ph.brut.focalLength = v.focale
    ph.brut.isoSpeedRating = v.iso
    ph.brut.rating = v.note or 0
    ph.brut.pickStatus = v.drapeau or 0
    ph.brut.dimensions = { width = 300, height = 200 }
    ph.formate.fileName = v.fichier or string.format('DSCF%d.RAF', id)
    ph.formate.copyName = v.copie
    ph.formate.cameraModel = v.appareil
    ph.formate.lens = v.objectif
    ph.formate.aperture = v.ouverture
    ph.formate.shutterSpeed = v.vitesse
    if v.retouchee then
        ph.proprietes.retoucheeParClaude = 'oui'
        ph.proprietes.proprietaireMemoire = ph.brut.uuid
    end
    function ph:getRawMetadata(cle) return self.brut[cle] end
    function ph:getFormattedMetadata(cle) return self.formate[cle] end
    function ph:getPropertyForPlugin(plugin, cle)
        assert(plugin == _PLUGIN, 'getPropertyForPlugin : _PLUGIN attendu')
        return self.proprietes[cle]
    end
    function ph:setPropertyForPlugin()
        error("setPropertyForPlugin : le Suivi n'écrit rien dans le catalogue", 2)
    end
    function ph:getDevelopSettings() return {} end
    function ph:getContainedCollections()
        COLLECTIONS_DEMANDEES = COLLECTIONS_DEMANDEES + 1
        return (self.v.essai and { COLLECTION_ESSAIS }) or (self.v.autre and { AUTRE_COLLECTION }) or {}
    end
    function ph:requestJpegThumbnail(largeur, hauteur, rappel)
        VIGNETTES[#VIGNETTES + 1] = { id = self.localIdentifier, taille = largeur }
        if pendantVignette then
            pendantVignette(self)
        end
        if self.v.sansVignette then
            rappel(nil, "pas d'aperçu")
        else
            rappel(JPEG)
        end
        return {}
    end
    PHOTOS[id] = ph
    return ph
end

-- Une photo du relevé du contrat (exemples.registre), telle que Lightroom la donnerait.
local function photoDuContrat(id, plus)
    local e = REGISTRE.catalogues[CATALOGUE].photos[tostring(id)]
    local p = e.prise_de_vue
    local v = { uuid = e.uuid, fichier = e.fichier, prise = p.le, appareil = p.appareil, objectif = p.objectif, focale = p.focale,
        ouverture = p.ouverture, vitesse = p.vitesse, iso = p.iso, note = e.note,
        drapeau = ({ retenue = 1, aucun = 0, rejetee = -1 })[e.drapeau] }
    for cle, valeur in pairs(plus or {}) do
        v[cle] = valeur
    end
    return photo(id, v)
end

local function lectureGroupee(lire)
    return function(_, photos, cles)
        GROUPEES = GROUPEES + 1
        local r = {}
        for _, ph in ipairs(photos) do
            local t = {}
            for _, cle in ipairs(cles) do
                t[cle] = lire(ph, cle)
            end
            r[ph] = t
        end
        return r
    end
end
S.catalogue.getPath = function() return CATALOGUE end
S.catalogue.getTargetPhoto = function() return ACTIVE end
S.catalogue.getTargetPhotos = function() return SELECTION end
S.catalogue.getPhotoByLocalId = function(_, id) return PHOTOS[tonumber(id)] end
S.catalogue.batchGetRawMetadata = lectureGroupee(function(ph, cle) return ph.brut[cle] end)
S.catalogue.batchGetFormattedMetadata = lectureGroupee(function(ph, cle) return ph.formate[cle] end)
S.catalogue.batchGetPropertyForPlugin = function(_, photos, plugin, cles)
    assert(plugin == _PLUGIN, 'batchGetPropertyForPlugin : _PLUGIN attendu')
    return lectureGroupee(function(ph, cle) return ph.proprietes[cle] end)(nil, photos, cles)
end
-- Les collections du catalogue (Carnet.photosDesEssais, une grande vue) : l'ensemble Développeur et
-- sa collection Essais (les photos `essai`), et un ensemble Voyages qui a lui aussi une collection
-- Essais (les photos `autre` : pas celle du Suivi).
S.collectionEssais.getPhotos = function()
    local liste = {}
    for _, ph in pairs(PHOTOS) do
        if ph.v.essai then
            liste[#liste + 1] = ph
        end
    end
    return liste
end
local ENSEMBLE_VOYAGES = { getName = function() return 'Voyages' end, getChildCollectionSets = function() return {} end,
    getChildCollections = function()
        return { { getName = function() return 'Essais' end, isSmartCollection = function() return false end, getPhotos = function()
            local liste = {}
            for _, ph in pairs(PHOTOS) do
                if ph.v.autre then
                    liste[#liste + 1] = ph
                end
            end
            return liste
        end } }
    end }
S.catalogue.getChildCollectionSets = function() return { S.ensembleDeveloppeur, ENSEMBLE_VOYAGES } end

-- Aides ------------------------------------------------------------------------------------------

local function supprimerSuivi()
    S.executer('rm -f ' .. S.q(Chemins.racine()) .. '/suivi*.json ' .. S.q(RECUS))
    S.executer('rm -rf ' .. S.q(Chemins.temporaire() .. '/Suivi'))
end

-- Un départ neuf : aucun relevé, aucune photo, le Suivi allumé, le connecteur au mode du contrat.
-- Les pas du module (correctif 1.3.8), remis à chaque départ.
local PAS = {}
for _, cle in ipairs({ 'PAS', 'PAS_UNE_A_UNE', 'PAS_ECRITURE', 'PAS_JSON', 'LOT_LECTURE', 'SEUIL_ESSAIS', 'SEUIL_REVOIR', 'REVOIR_APRES',
    'FACTEUR_ECRITURE', 'SECONDES_PAR_MO', 'DELAI_ECRITURE_MAX', 'MAX_REESSAIS', 'LOT_ANALYSE', 'DELAI_REESSAI' }) do
    PAS[cle] = Releve[cle]
end
local PAS_REESSAIS = PAS.MAX_REESSAIS

local function depart()
    PHOTOS, ACTIVE, SELECTION, VIGNETTES, pendantVignette, GROUPEES, COLLECTIONS_DEMANDEES = {}, nil, {}, {}, nil, 0, 0
    supprimerSuivi()
    Releve.oublier()
    Releve.allume = true
    Releve.MAX_ORIGINAUX, Releve.MAX_VUES, Releve.MAX_SELECTION = BORNES.max_originaux, BORNES.max_vues, BORNES.max_selection
    Releve.DELAI_ECRITURE, Releve.MAX_EN_ATTENTE = 0, 20
    for cle, valeur in pairs(PAS) do
        Releve[cle] = valeur
    end
    -- L'écart d'après la durée de la dernière écriture : hors des essais qui le vérifient (ici, une
    -- écriture qui passe d'une seconde à la suivante durerait 1 s : LrDate.currentTime de la
    -- simulation est os.time).
    Releve.FACTEUR_ECRITURE = 0
    prefs.cheminConnecteur = CONNECTEUR
    Moteur.travaille = false
    Liaison.enCours, Liaison.finCommande = nil, nil
    mode('contrat')
    journal = {}
end

-- La sélection de Lightroom : la photo active, puis les autres (identifiants).
local function choisir(active, ...)
    ACTIVE = PHOTOS[active]
    SELECTION = { ACTIVE }
    for _, id in ipairs({ ... }) do
        if id ~= active then
            SELECTION[#SELECTION + 1] = PHOTOS[id]
        end
    end
    return Lightroom.photos()
end

-- La sélection vue par la fenêtre Claude (Fenetre.suivreSelection), puis la file vidée par la tâche
-- du Suivi, d'un coup (son attente ne sert pas ici).
local function voir(active, ...)
    return Releve.voirSelection(choisir(active, ...))
end

local function vider()
    Releve.derniereErreur = nil
    egal(true, Releve.relancer(), 'la tâche du Suivi part')
    local tache = S.taches[#S.taches]
    S.taches[#S.taches] = function() end
    tache()
    egal(false, Releve.enCours, 'la tâche du Suivi finie')
    -- Une erreur de la tâche (ou d'un essai, dans une attente simulée) ne se perd pas dans ses
    -- protections.
    egal(nil, Releve.derniereErreur, 'erreur de la tâche du Suivi')
end

-- Le fichier tel que --graphiques le lirait.
local function fichier()
    return Json.decode(assert(Fichiers.lire(Releve.fichier()), 'suivi.json'))
end

local function entree(id)
    return fichier().catalogues[CATALOGUE].photos[tostring(id)]
end

-- Ce que le contrat fige d'une entrée, sans les heures (celles de l'essai).
local HEURES = { ajout = true, ajout_le = true, vu = true, classement_le = true }
local function sansHeures(e)
    local t = {}
    for cle, v in pairs(e) do
        if not HEURES[cle] and cle ~= 'vues' and cle ~= 'analyse' then
            t[cle] = v
        end
    end
    return t
end

-- Une heure de l'essai : entre `avant` et maintenant.
local function pendant(avant, t, quoi)
    vrai(type(t) == 'number' and t >= avant and t <= os.time(), (quoi or 'heure') .. ' : ' .. tostring(t))
end

local function dossiersDeLots()
    return Fichiers.entrees(Chemins.temporaire() .. '/Suivi')
end

-- Les fois où le module rend la main pendant fn() (LrTasks.yield, que le module n'appelle que par
-- Releve.rendreLaMain) : leur nombre, celles à travers un pcall simple (Lua 5.1, celui de Lightroom,
-- refuse un yield à travers un pcall : ici, le global pcall est compté ; LrTasks.pcall de la
-- simulation est le vrai pcall, qui ne compte pas), et le plus long morceau entre deux (os.clock).
-- `options` : canYield (la réponse de LrTasks.canYield, vrai par défaut), pendant(n) (appelé à chaque
-- yield, son temps hors du compte).
local function rendreLaMainPendant(fn, options)
    options = options or {}
    local LrTasks = S.modules.LrTasks
    local yield, canYield, vraiPcall = LrTasks.yield, LrTasks.canYield, pcall
    local profondeur, r = 0, { n = 0, traversees = 0, plusLong = 0 }
    local function emballer(...)
        return select('#', ...), { ... }
    end
    _G.pcall = function(...)
        profondeur = profondeur + 1
        local n, resultats = emballer(vraiPcall(...))
        profondeur = profondeur - 1
        return unpack(resultats, 1, n)
    end
    local dernier = os.clock()
    LrTasks.yield = function()
        local t = os.clock()
        r.plusLong = math.max(r.plusLong, t - dernier)
        r.n = r.n + 1
        if profondeur > 0 then
            r.traversees = r.traversees + 1
        end
        if options.pendant then
            options.pendant(r.n)
        end
        dernier = os.clock()
    end
    LrTasks.canYield = function()
        if options.canYield == nil then
            return true
        end
        return options.canYield
    end
    local ok, erreur = xpcall(fn, debug.traceback)
    r.plusLong = math.max(r.plusLong, os.clock() - dernier)
    _G.pcall, LrTasks.yield, LrTasks.canYield = vraiPcall, yield, canYield
    assert(ok, erreur)
    return r
end

-- Essais --------------------------------------------------------------------------------------------

essai("Une photo seule : son entrée au relevé (celle du contrat), puis l'analyse d'office de sa vignette par --analyser, sous l'alarme de perl", function()
    depart()
    photoDuContrat(4302)
    local avant = os.time()
    egal(true, voir(4302), 'la vue en attente')
    egal(false, Fichiers.existe(Releve.fichier()), "rien d'écrit avant la tâche")
    S.dernieresCommandes = {}
    vider()
    local e = entree(4302)
    local attendue = REGISTRE.catalogues[CATALOGUE].photos['4302']
    memes(sansHeures(attendue), sansHeures(e), 'entrée 4302')
    pendant(avant, e.ajout, 'ajout')
    egal(os.date('%Y-%m-%d %H:%M', e.ajout), e.ajout_le, 'ajout_le à l\'heure locale')
    egal(e.ajout, e.vu, 'vu')
    egal(e.ajout, e.classement_le, 'classement_le')
    memes(Json.tableau({ { id = 4302, uuid = attendue.uuid, copie_virtuelle = false, fichier = 'XH2S1340.RAF', le = e.ajout } }), e.vues, 'vues')
    -- L'analyse : un appel, la vignette de l'original à 1 024 px, effacée ensuite.
    local appels = recus()
    egal(1, #appels, 'un appel de --analyser')
    egal(1, #appels[1].photos)
    egal(4302, appels[1].photos[1].id)
    egal(250, appels[1].photos[1].iso)
    egal(true, appels[1].photos[1].cache)
    egal(nil, appels[1].photos[1].retouchee, 'retouchee absent : faux')
    contient(appels[1].photos[1].vignette, '/Temporaire/Suivi/Analyse-', 'un dossier neuf par lot')
    egal(1, #VIGNETTES)
    egal(1024, VIGNETTES[1].taille, 'vignette de 1 024 px')
    egal(0, #dossiersDeLots(), 'le dossier du lot effacé')
    local commande
    for _, c in ipairs(S.dernieresCommandes) do
        if c:find('--analyser', 1, true) then
            commande = c
        end
    end
    contient(commande, "/usr/bin/perl -e 'alarm 60; exec @ARGV' " .. S.q(CONNECTEUR) .. ' --analyser ', 'la commande du contrat')
    contient(commande, '2>/dev/null', 'stderr écarté')
    local analyse = e.analyse
    pendant(avant, analyse.le, 'analyse.le')
    local dansLeRegistre = ANALYSER.dans_le_registre['4302']
    memes(dansLeRegistre.cherches, analyse.cherches, 'cherches')
    memes(dansLeRegistre.defauts, analyse.defauts, 'defauts (un tableau vide)')
    egal(1, analyse.regles)
    vrai(GROUPEES > 0, 'lectures groupées du catalogue')
    -- Plus rien à faire : pas de nouvel appel, la tâche ne repart pas d'elle-même.
    egal(false, Releve.relancer(), 'rien à faire : pas de tâche')
end)

essai("Un groupe de six photos : l'entrée de --analyser est celle du contrat (ordre, iso, cache, retouchee, objectif), le relevé ensuite comme dans_le_registre (le genre compris)", function()
    depart()
    photoDuContrat(4302)
    photo(4303, { iso = 5000 })
    photo(4304, { format = 'RAW', objectif = 'XF80mmF2.8 R LM OIS WR Macro' })
    photo(4306, { iso = 3200, retouchee = true })
    photo(4307, { iso = 2000 })
    photo(4305, { iso = 400, sansVignette = true })
    local avant = os.time()
    voir(4302, 4303, 4304, 4306, 4307, 4305)
    vider()
    local appels = recus()
    egal(1, #appels, 'un seul lot (dix au plus)')
    local lot = appels[1].photos[1].vignette:match('(.*)/[^/]*$')
    local attendue = sansNotes(ANALYSER.entree)
    for _, p in ipairs(attendue.photos) do
        p.vignette = p.vignette:gsub('<lot>', lot)
    end
    memes(attendue, appels[1], "l'entrée de --analyser")
    -- Le relevé : une analyse réussie, une raison qui compte un essai (dans_le_registre).
    local f = fichier().catalogues[CATALOGUE].photos
    for _, id in ipairs({ '4302', '4307' }) do
        local a = sansNotes(f[id].analyse)
        pendant(avant, a.le, id .. ' : le')
        local attendu = sansNotes(ANALYSER.dans_le_registre[id])
        attendu.le = a.le
        memes(attendu, a, 'analyse de ' .. id)
    end
    memes(Json.tableau({ 'bruit' }), f['4303'].analyse.defauts, '4303 : le bruit trouvé')
    memes(Json.tableau({ 'flou' }), f['4306'].analyse.cherches, '4306 retouchée : le flou seul')
    egal('vignette_absente', f['4305'].analyse.erreur, '4305 : pas de vignette')
    egal(1, f['4305'].analyse.essais)
    egal(nil, f['4305'].analyse.abandonnee)
    -- Une autre photo active dans le même groupe ne revoit qu'elle.
    local vuAvant = f['4303'].vu
    egal(true, voir(4304, 4302, 4303, 4306, 4307, 4305), 'la photo active a changé')
    egal(1, #Releve.aVoir[1].photos, 'seule la photo active')
    egal(4304, Releve.aVoir[1].photos[1].localIdentifier)
    vider()
    egal(vuAvant, entree(4303).vu, 'les autres photos du groupe : pas revues')
    egal(1, #recus(), 'aucune analyse refaite')
end)

essai("La photo active nouvellement vue passe en tête de la file, même dans un groupe vu la même seconde", function()
    depart()
    for id = 1201, 1203 do
        photo(id)
    end
    -- Le groupe vu (connecteur absent : tout reste en file), puis une autre photo active du groupe.
    prefs.cheminConnecteur = S.home .. '/absent'
    voir(1201, 1202, 1203)
    vider()
    voir(1203, 1201, 1202)
    vider()
    local f = fichier()
    local photos = f.catalogues[CATALOGUE].photos
    -- Les trois vues à la même heure : seule la tête les départage de l'ordre de la sélection.
    photos['1201'].vu, photos['1202'].vu, photos['1203'].vu = 500, 500, 500
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    Releve.tete, Releve.rangs = '1203', { ['1201'] = 1, ['1202'] = 2, ['1203'] = 1 }
    prefs.cheminConnecteur = CONNECTEUR
    vider()
    local appels = recus()
    egal(1, #appels)
    egal(1203, appels[1].photos[1].id, 'la photo active en tête')
    egal(1201, appels[1].photos[2].id, "puis l'ordre de la sélection")
    egal(1202, appels[1].photos[3].id)
end)

essai("Une copie virtuelle compte pour son original, une seule fois : une entrée, ses vues, la note et la retouche de la famille, l'analyse sur la vignette de l'original", function()
    depart()
    photoDuContrat(4211, { note = 0 })
    photo(4388, { copieDe = 4211, uuid = '3F2A6C1E-8B4D-4E7A-9C11-0A5B7D004388', fichier = 'XH2S1208.RAF', copie = 'Copie 1', note = 4,
        retouchee = true })
    -- L'original seul, puis sa copie seule, puis les deux ensemble.
    voir(4211)
    voir(4388)
    voir(4388, 4211)
    vider()
    local photos = fichier().catalogues[CATALOGUE].photos
    egal(nil, photos['4388'], "pas d'entrée pour la copie")
    local e = photos['4211']
    local attendue = REGISTRE.catalogues[CATALOGUE].photos['4211']
    memes(sansHeures(attendue), sansHeures(e), 'entrée 4211 (note et retouche de la famille)')
    egal(2, #e.vues, 'deux vues, jamais en double')
    for i, v in ipairs(attendue.vues) do
        local vue = e.vues[i]
        egal(v.id, vue.id)
        egal(v.uuid, vue.uuid)
        egal(v.copie_virtuelle, vue.copie_virtuelle)
        egal(v.fichier, vue.fichier)
    end
    local appels = recus()
    egal(1, #appels, "une analyse, pour l'original")
    egal(1, #appels[1].photos, 'une fois')
    egal(4211, appels[1].photos[1].id)
    egal(160, appels[1].photos[1].iso, "l'ISO de l'original, une fois")
    egal(nil, appels[1].photos[1].retouchee, "la mémoire de Claude est sur la copie, pas sur l'original")
    egal(1, #VIGNETTES)
    egal(4211, VIGNETTES[1].id, "la vignette de l'original")
    -- Une copie seule, dont l'original n'est jamais vu : l'entrée est celle de l'original.
    photoDuContrat(4106, { note = 0, drapeau = 0 })
    photo(4410, { copieDe = 4106, uuid = '3F2A6C1E-8B4D-4E7A-9C11-0A5B7D004410', fichier = 'XH2S1051.RAF', copie = 'Copie 2', note = 5,
        drapeau = 1, retouchee = true })
    voir(4410)
    vider()
    local e2 = entree(4106)
    memes(sansHeures(REGISTRE.catalogues[CATALOGUE].photos['4106']), sansHeures(e2), 'entrée 4106')
    egal(1, #e2.vues)
    egal(4410, e2.vues[1].id)
    egal(true, e2.vues[1].copie_virtuelle)
    egal('XH2S1051.RAF (Copie 2)', e2.vues[1].fichier)
    egal(4106, VIGNETTES[#VIGNETTES].id, "l'analyse sur la vignette de l'original")
    egal(nil, entree(4410), "pas d'entrée pour la copie")
end)

essai("Les photos de « Développeur › Essais » n'entrent pas (elle ou son original), ni une copie des Essais dans la famille, ni une vidéo", function()
    depart()
    photo(500, { essai = true })
    photo(501, { autre = true }) -- une collection « Essais » d'un autre ensemble : une vraie photo
    photo(510, { essai = true })
    photo(511, { copieDe = 510 }) -- la copie d'un original des Essais
    photo(520, { note = 1, drapeau = 0 })
    photo(521, { copieDe = 520, essai = true, note = 5, drapeau = 1, retouchee = true }) -- une copie des Essais
    photo(530, { format = 'VIDEO' })
    voir(500, 501, 511, 521, 530)
    vider()
    local photos = fichier().catalogues[CATALOGUE].photos
    egal(nil, photos['500'], 'une photo des Essais')
    egal(nil, photos['510'], "l'original des Essais")
    egal(nil, photos['511'], 'sa copie')
    egal(nil, photos['521'], 'une copie des Essais')
    egal(nil, photos['520'], "l'original d'une copie des Essais, vu par elle seule : pas vu")
    egal(nil, photos['530'], 'une vidéo')
    vrai(photos['501'] ~= nil, "une autre collection « Essais » n'est pas celle du Suivi")
    -- L'original vu par lui-même : la copie des Essais ne compte pas dans sa famille.
    voir(520)
    vider()
    local e = entree(520)
    egal(1, e.note, 'la note de la copie des Essais ne compte pas')
    egal('aucun', e.drapeau)
    egal(false, e.retouchee_par_claude)
    for _, appel in ipairs(recus()) do
        for _, p in ipairs(appel.photos) do
            vrai(p.id == 501 or p.id == 520, 'analysée : ' .. tostring(p.id))
        end
    end
end)

essai("Pendant que Claude travaille, et pendant que la liaison sert (Claude Desktop, la recette) : l'analyse attend, les vues se rangent quand même (une photo parcourue pendant une Retouche pro compte) ; ensuite, tout s'analyse", function()
    depart()
    photo(601, { iso = 200 })
    photo(602, { iso = 200 })
    photo(603, { iso = 200 })
    local LrTasks = S.modules.LrTasks
    local dormir = LrTasks.sleep
    for _, occupation in ipairs({ 'claude', 'liaison' }) do
        supprimerSuivi()
        Releve.oublier()
        if occupation == 'claude' then
            Moteur.travaille = true
        else
            Liaison.enCours = 1
        end
        voir(601, 602)
        -- Ce que chaque attente voit, vérifié après (une erreur dans l'attente se perdrait dans les
        -- protections de la tâche) ; une autre photo vue pendant la première attente.
        local sommeils, vus = 0, {}
        LrTasks.sleep = function(s)
            sommeils = sommeils + 1
            local f = Fichiers.existe(Releve.fichier()) and fichier().catalogues[CATALOGUE].photos or {}
            vus[sommeils] = { duree = s, ranges = (f['601'] and 1 or 0) + (f['602'] and 1 or 0) + (f['603'] and 1 or 0), analyses = #recus() }
            if sommeils == 1 then
                voir(603)
            elseif sommeils == 3 then
                Moteur.travaille = false
                Liaison.enCours = nil
            end
        end
        local ok, erreur = pcall(vider)
        LrTasks.sleep = dormir
        assert(ok, erreur)
        egal(3, sommeils, occupation .. ' : trois pauses')
        for i, v in ipairs(vus) do
            egal(Releve.PAUSE, v.duree, 'attente de la pause')
            egal(0, v.analyses, occupation .. ' : rien analysé pendant la pause ' .. i)
        end
        egal(2, vus[1].ranges, occupation .. ' : la sélection rangée avant la première pause')
        egal(3, vus[2].ranges, occupation .. ' : la photo vue pendant la pause rangée tout de suite')
        for _, id in ipairs({ 601, 602, 603 }) do
            vrai(entree(id).analyse ~= nil, occupation .. ' : ' .. id .. ' analysée après')
        end
    end
    -- Claude se met au travail pendant les vignettes : le lot est remis, sans essai compté.
    supprimerSuivi()
    Releve.oublier()
    voir(601, 602)
    pendantVignette = function() Moteur.travaille = true end
    local sommeils, analysesPendant = 0, nil
    LrTasks.sleep = function()
        sommeils = sommeils + 1
        analysesPendant = analysesPendant or #recus()
        pendantVignette = nil
        Moteur.travaille = false
    end
    local ok, erreur = pcall(vider)
    LrTasks.sleep = dormir
    assert(ok, erreur)
    egal(1, sommeils)
    egal(0, analysesPendant, "le connecteur n'est pas lancé pendant que Claude travaille")
    egal(1, #recus(), 'un seul appel, après la pause')
    egal(nil, entree(601).analyse.erreur, 'aucun essai compté pour le lot remis')
    egal(0, #dossiersDeLots(), 'le dossier du lot remis effacé')
end)

essai("Trop de vues en attente (un lot qui dure, la tâche pas encore partie) : elles se fondent en une seule, sans perdre une photo, la dernière photo active en tête ; au-delà de max_selection, le reste dit au journal", function()
    depart()
    for i = 1, 25 do
        photo(1400 + i)
    end
    for i = 1, 25 do
        egal(true, voir(1400 + i), 'vue ' .. i)
    end
    vrai(#Releve.aVoir <= Releve.MAX_EN_ATTENTE, 'vues en attente : ' .. #Releve.aVoir)
    egal(1421, Releve.aVoir[1].photos[1].localIdentifier, 'la photo active de la plus récente fondue, en tête')
    local enAttente = {}
    for _, vue in ipairs(Releve.aVoir) do
        for _, ph in ipairs(vue.photos) do
            enAttente[ph.localIdentifier] = true
        end
    end
    for i = 1, 25 do
        vrai(enAttente[1400 + i], 'en attente : ' .. (1400 + i))
    end
    vider()
    local photos = fichier().catalogues[CATALOGUE].photos
    for i = 1, 25 do
        vrai(photos[tostring(1400 + i)] ~= nil, 'rangée : ' .. (1400 + i))
    end
    -- La fusion bornée : au plus max_selection photos, la plus récente d'abord.
    Releve.MAX_SELECTION, Releve.MAX_EN_ATTENTE = 3, 2
    journal = {}
    for _, id in ipairs({ 1401, 1402, 1403, 1404, 1405 }) do
        voir(id)
    end
    egal(1, #Releve.aVoir, 'deux fois fondues')
    local ids = {}
    for _, ph in ipairs(Releve.aVoir[1].photos) do
        ids[#ids + 1] = ph.localIdentifier
    end
    egal('1405 1404 1403', table.concat(ids, ' '), 'la plus récente en tête, puis les autres, trois au plus')
    vrai(journalContient('2 photo(s) au-delà de 3 ne sont pas rangées'), 'le reste dit au journal')
end)

-- L'heure du module (os.time), arrêtée, n'avance qu'à la demande (les attentes de la tâche), pour
-- les écritures espacées : le temps réel de l'essai ne compte pas.
local vraiTemps = os.time
local depuis, decalage = 0, 0
local function avancerLeTemps(secondes)
    decalage = decalage + secondes
end
local function avecLeTemps(fn)
    depuis, decalage = vraiTemps(), 0
    os.time = function(t)
        if t then
            return vraiTemps(t)
        end
        return depuis + decalage
    end
    local ok, erreur = pcall(fn)
    os.time = vraiTemps
    assert(ok, erreur)
end

essai("Écritures espacées, vues comprises : la première tout de suite, puis au plus une toutes les DELAI_ECRITURE secondes ; à la fin de la file, la tâche attend son tour en rangeant les vues qui arrivent ; pendant une pause aussi, à son tour (plus au début de chaque pause : une liaison qui sert par moments n'écrit pas tout le relevé à chaque fois)", function()
    depart()
    egal(20, DELAI_ECRITURE, 'dans Lightroom : 20 s')
    local LrTasks = S.modules.LrTasks
    local dormir = LrTasks.sleep
    for i = 1, 12 do
        photo(1300 + i)
    end
    avecLeTemps(function()
        Releve.DELAI_ECRITURE = 10
        -- Dany parcourt ses photos aux flèches : une nouvelle toutes les 2 s (le rythme du relevé de
        -- la sélection), chacune analysée aussitôt.
        local sommeils, suivante = 0, 2
        LrTasks.sleep = function(s)
            sommeils = sommeils + 1
            avancerLeTemps(s)
            if suivante <= 6 then
                voir(1300 + suivante)
                suivante = suivante + 1
            end
        end
        local version = Releve.version
        voir(1301)
        local ok, erreur = pcall(vider)
        LrTasks.sleep = dormir
        assert(ok, erreur)
        egal(6, #recus(), 'six photos analysées')
        for i = 1, 6 do
            vrai(entree(1300 + i).analyse and entree(1300 + i).analyse.cherches, (1300 + i) .. ' : analysée et écrite')
        end
        -- À 0 s (la première), à 10 s (la sixième vue), et à 20 s (la fin de la file) : pas une par
        -- photo (douze vues et analyses).
        egal(3, Releve.version - version, 'écritures')
        egal(10, sommeils, 'la tâche a attendu la dernière (20 s)')
        -- Claude se met au travail : ce qui est rangé s'écrit à son tour, pendant la pause comme
        -- hors d'elle (pas au début de la pause : la dernière écriture date de 0 s) ; l'analyse
        -- attend.
        version = Releve.version
        local analyses = #recus()
        Moteur.travaille = true
        sommeils, suivante = 0, 8
        local pendant = {}
        LrTasks.sleep = function(s)
            sommeils = sommeils + 1
            avancerLeTemps(s)
            pendant[sommeils] = { ecritures = Releve.version - version, analyses = #recus() }
            if suivante <= 12 then
                voir(1300 + suivante)
                suivante = suivante + 1
            elseif sommeils == 8 then
                Moteur.travaille = false
            end
        end
        voir(1307)
        ok, erreur = pcall(vider)
        LrTasks.sleep = dormir
        Moteur.travaille = false
        assert(ok, erreur)
        egal(10, sommeils, 'huit attentes de la pause, puis deux pour la dernière écriture')
        egal(0, pendant[1].ecritures, "pas au début de la pause (1307, 0 s après la dernière) : à son tour")
        egal(0, pendant[5].ecritures, 'pas à chaque vue pendant la pause (1308 à 1311)')
        egal(1, pendant[6].ecritures, '10 s après la dernière : à son tour, pendant la pause (1307 à 1312)')
        for i = 1, 8 do
            egal(analyses, pendant[i].analyses, 'rien analysé pendant la pause ' .. i)
        end
        egal(2, Releve.version - version, 'la deuxième à la fin de la file, 10 s après')
        for i = 7, 12 do
            vrai(entree(1300 + i).analyse and entree(1300 + i).analyse.cherches, (1300 + i) .. ' : rangée pendant la pause, analysée après')
        end
    end)
    -- Le délai à 0 : une écriture par vue et par lot (25 photos : une vue, trois lots).
    supprimerSuivi()
    Releve.oublier()
    Releve.DELAI_ECRITURE = 0
    local ids = {}
    for i = 1, 25 do
        ids[i] = 1500 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    local version = Releve.version
    vider()
    egal(3, #recus(), 'trois lots de dix au plus')
    egal(4, Releve.version - version, 'écritures (délai 0 s)')
end)

essai("La fenêtre Suivi va dessiner : Releve.ecrire écrit tout de suite ce qui attend son tour ; rien ne reste à écrire ensuite", function()
    depart()
    photo(1320)
    photo(1321)
    voir(1320)
    vider()
    local LrTasks = S.modules.LrTasks
    local dormir = LrTasks.sleep
    egal(false, Releve.ecrire(), 'rien à écrire')
    Releve.DELAI_ECRITURE = 1000
    voir(1321)
    local sommeils, vu = 0, {}
    LrTasks.sleep = function()
        sommeils = sommeils + 1
        vu.attend = Releve.aEcrire
        vu.avant = entree(1321) ~= nil
        vu.ecrit = Releve.ecrire()
        vu.apres = entree(1321) and entree(1321).analyse and entree(1321).analyse.cherches ~= nil
    end
    local version = Releve.version
    local ok, erreur = pcall(vider)
    LrTasks.sleep = dormir
    assert(ok, erreur)
    egal(1, sommeils, 'la tâche attendait son tour')
    egal(true, vu.attend, 'une écriture attendait')
    egal(false, vu.avant, "1321 pas encore dans le fichier")
    egal(true, vu.ecrit, 'Releve.ecrire écrit')
    egal(true, vu.apres, '1321 rangée et analysée, dans le fichier')
    egal(1, Releve.version - version, 'une seule écriture : rien ne restait')
    -- La fenêtre Suivi l'appelle avant --graphiques.
    local source = assert(Fichiers.lire(S.plugin .. '/FenetreSuivi.lua'))
    local dessiner = source:match('function FenetreSuivi%.dessiner%(%)(.-)\nend\n')
    local ecrire, lancer = dessiner:find('LrTasks.pcall(Releve.ecrire)', 1, true), dessiner:find('LrTasks.execute(', 1, true)
    vrai(ecrire and lancer and ecrire < lancer, 'Releve.ecrire avant --graphiques')
end)

essai("Un fichier illisible (ou d'un autre format) est mis de côté avant la première écriture, jamais écrasé", function()
    depart()
    photo(701)
    Fichiers.ecrire(Releve.fichier(), 'pas du JSON')
    Releve.oublier()
    egal(0, #Releve.entrees(), 'illisible : un relevé vide')
    voir(701)
    vider()
    local cotes = {}
    for _, nom in ipairs(Fichiers.entrees(Chemins.racine())) do
        if nom:match('^suivi%-illisible%-') then
            cotes[#cotes + 1] = nom
        end
    end
    egal(1, #cotes, 'mis de côté')
    egal('pas du JSON', Fichiers.lire(Chemins.racine() .. '/' .. cotes[1]), 'tel quel')
    egal(1, fichier().format)
    vrai(entree(701) ~= nil, 'le nouveau relevé')
    vrai(journalContient('Suivi illisible mis de côté'), 'dit au journal')
    -- Un autre format, la même seconde : une autre copie, la première gardée.
    Fichiers.ecrire(Releve.fichier(), '{"format": 2, "catalogues": {}}')
    Releve.oublier()
    voir(701)
    Releve.revoir()
    voir(701)
    vider()
    local n = 0
    for _, nom in ipairs(Fichiers.entrees(Chemins.racine())) do
        if nom:match('^suivi%-illisible%-') then
            n = n + 1
        end
    end
    egal(2, n, 'deux copies mises de côté, aucune écrasée')
    egal('pas du JSON', Fichiers.lire(Chemins.racine() .. '/' .. cotes[1]), 'la première intacte')
end)

essai("Bornes : les originaux vus le moins récemment sortent au-delà de max_originaux ; une vue de plus au-delà de max_vues ne change que vu ; une sélection au-delà de max_selection, le reste dit au journal", function()
    depart()
    -- 250 000 depuis le correctif 1.3.8 (toute la bibliothèque de Dany d'un coup), dans le module
    -- comme dans le contrat.
    egal(250000, BORNES.max_originaux, 'max_originaux du contrat')
    egal(250000, BORNES.max_selection, 'max_selection du contrat')
    for cle, valeur in pairs(BORNES_DU_MODULE) do
        egal(BORNES[cle], valeur, cle .. ' du module : celle du contrat')
    end
    egal(250000, Releve.MAX_ORIGINAUX, 'max_originaux du contrat')
    egal(20, Releve.MAX_VUES, 'max_vues du contrat')
    egal(250000, Releve.MAX_SELECTION, 'max_selection du contrat')
    egal(10, Releve.LOT_ANALYSE, 'lot_analyse du contrat')
    egal(3, Releve.ESSAIS_ANALYSE, 'essais_analyse du contrat')
    -- Trois originaux au relevé, vus à des heures différentes.
    prefs.cheminConnecteur = S.home .. '/absent'
    for _, id in ipairs({ 801, 802, 803, 804 }) do
        photo(id)
    end
    voir(801, 802, 803)
    vider()
    local f = fichier()
    local photos = f.catalogues[CATALOGUE].photos
    photos['801'].vu, photos['802'].vu, photos['803'].vu = 300, 100, 200
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    Releve.MAX_ORIGINAUX = 3
    voir(804)
    vider()
    photos = fichier().catalogues[CATALOGUE].photos
    egal(nil, photos['802'], 'le moins récemment vu sort')
    vrai(photos['801'] and photos['803'] and photos['804'], 'les trois autres restent')
    vrai(journalContient('vu(s) le moins récemment retiré(s)'), 'dit au journal')
    -- max_vues : la troisième copie vue ne s'ajoute pas, vu change.
    Releve.MAX_ORIGINAUX = BORNES.max_originaux
    Releve.MAX_VUES = 2
    photo(810)
    photo(811, { copieDe = 810, copie = 'Copie 1' })
    photo(812, { copieDe = 810, copie = 'Copie 2' })
    voir(810, 811)
    vider()
    local vuAvant = entree(810).vu
    photos = fichier()
    photos.catalogues[CATALOGUE].photos['810'].vu = vuAvant - 50
    Fichiers.ecrire(Releve.fichier(), Json.encode(photos))
    Releve.oublier()
    voir(812)
    vider()
    local e = entree(810)
    egal(2, #e.vues, 'max_vues')
    egal(811, e.vues[2].id)
    vrai(e.vu >= vuAvant, 'vu changé : ' .. tostring(e.vu))
    -- max_selection : les premières seulement, la photo active d'abord.
    Releve.MAX_VUES = BORNES.max_vues
    Releve.MAX_SELECTION = 3
    for id = 820, 824 do
        photo(id)
    end
    journal = {}
    voir(823, 820, 821, 822, 823, 824)
    egal(3, #Releve.aVoir[1].photos)
    egal(823, Releve.aVoir[1].photos[1].localIdentifier, "la photo active d'abord")
    egal(820, Releve.aVoir[1].photos[2].localIdentifier)
    vrai(journalContient('sélection de 5 photos, seules les 3 premières comptent'), 'le reste dit au journal')
    vider()
    egal(nil, entree(822), 'au-delà de la borne : pas vue')
end)

essai("Le relevé du contrat se relit tel quel (les _note oubliées) et se réécrit sans rien perdre, listes en tableaux et prise de vue vide en objet", function()
    depart()
    -- Le relevé d'exemple tel quel, ses commentaires compris.
    Fichiers.ecrire(Releve.fichier(), Json.encode(Json.decode(assert(Fichiers.lire(CONTRAT_CHEMIN))).exemples.registre.fichier))
    Releve.oublier()
    local entrees = Releve.entrees()
    local attendues = REGISTRE.catalogues[CATALOGUE].photos
    local n = 0
    for _ in pairs(attendues) do
        n = n + 1
    end
    egal(17, n, 'le relevé du contrat a 17 originaux')
    egal(n, #entrees, 'tous relus')
    for _, e in ipairs(entrees) do
        neuve(e, 'entrée ' .. e.original)
        local attendue = sansNotes(attendues[tostring(e.original)])
        -- Une comparaison sans les marques des tableaux (une copie neuve n'en a pas).
        local function sansMarques(v)
            if type(v) ~= 'table' then
                return v
            end
            local t = {}
            for cle, x in pairs(v) do
                t[cle] = sansMarques(x)
            end
            return t
        end
        memes(sansMarques(attendue), e, 'entrée ' .. e.original)
    end
    -- Réécrit (une vue d'une autre photo) : les 17 restent identiques, en JSON.
    photo(9001)
    prefs.cheminConnecteur = S.home .. '/absent'
    voir(9001)
    vider()
    local relu = fichier().catalogues[CATALOGUE].photos
    for cle, attendue in pairs(attendues) do
        memes(sansNotes(attendue), relu[cle], 'réécrit : ' .. cle)
    end
    local texte = Fichiers.lire(Releve.fichier())
    contient(texte, '"defauts":[]', 'une liste vide en tableau')
    contient(texte, '"prise_de_vue":{}', 'une prise de vue vide en objet')
    vrai(not texte:find('_note', 1, true), 'aucun commentaire écrit')
    -- La file du relevé : seule 4302 (sans analyse) ; 3990, abandonnée, jamais.
    local n2, enFile = Releve.nombre()
    egal(18, n2)
    egal(2, enFile, '4302 et la nouvelle')
end)

essai("La file : une analyse manquée se réessaie après son délai, abandonnée au troisième essai ; jamais refaite après une édition ; refaite pour des règles plus récentes", function()
    depart()
    photo(901, { iso = 2000 })
    voir(901)
    -- Une vignette trop petite deux fois déjà, la dernière il y a plus que le délai.
    prefs.cheminConnecteur = S.home .. '/absent'
    vider()
    local f = fichier()
    f.catalogues[CATALOGUE].photos['901'].analyse = { le = os.time() - Releve.DELAI_REESSAI - 1, erreur = 'vignette_petite', essais = 2 }
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    prefs.cheminConnecteur = CONNECTEUR
    PHOTOS[901].v.sansVignette = true
    vider()
    local a = entree(901).analyse
    egal('vignette_absente', a.erreur)
    egal(3, a.essais, 'troisième essai')
    egal(true, a.abandonnee, 'abandonnée')
    -- Abandonnée : elle ne revient plus, même revue.
    PHOTOS[901].v.sansVignette = nil
    Releve.revoir()
    voir(901)
    vider()
    egal(1, #recus(), 'jamais réessayée')
    egal(true, entree(901).analyse.abandonnee)
    -- Une analyse manquée récente attend son délai.
    photo(902)
    voir(902)
    PHOTOS[902].v.sansVignette = true
    vider()
    egal(1, entree(902).analyse.essais)
    PHOTOS[902].v.sansVignette = nil
    egal(false, Releve.relancer(), 'rien avant le délai')
    vrai(Releve.prochaineVerification > os.time() + Releve.DELAI_REESSAI - 5, 'regardée de nouveau après le délai')
    -- Une photo analysée, puis éditée (une retouche), puis revue : l'analyse reste.
    photo(903)
    voir(903)
    vider()
    local appels = #recus()
    PHOTOS[903].proprietes.retoucheeParClaude = 'oui'
    PHOTOS[903].proprietes.proprietaireMemoire = PHOTOS[903].brut.uuid
    PHOTOS[903].brut.rating = 3
    Releve.revoir()
    voir(903)
    vider()
    egal(appels, #recus(), 'jamais refaite après une édition')
    egal(3, entree(903).note, 'le classement relu')
    egal(true, entree(903).retouchee_par_claude)
    -- Des règles plus récentes (2) : les analyses de règles 1 se refont, une fois.
    mode('regles2')
    photo(904)
    voir(904)
    vider()
    egal(2, entree(904).analyse.regles)
    egal(2, entree(903).analyse.regles, 'refaite pour des règles plus récentes')
    local refaits = #recus()
    Releve.revoir()
    voir(904)
    vider()
    egal(refaits, #recus(), 'pas deux fois')
end)

essai("Le connecteur muet (l'alarme) ou qui refuse : un essai à chaque photo du lot ; absent : rien ne change, la file attend", function()
    depart()
    photo(951)
    photo(952)
    mode('muet')
    voir(951, 952)
    vider()
    for _, id in ipairs({ 951, 952 }) do
        local a = entree(id).analyse
        egal('pas_de_reponse', a.erreur, id .. ' : sans réponse')
        egal(1, a.essais)
    end
    vrai(journalContient(Releve.PAS_DE_REPONSE), 'dit au journal')
    -- Qui refuse (ok faux) : sa raison.
    mode('refus')
    photo(953)
    voir(953)
    vider()
    egal('arguments', entree(953).analyse.erreur)
    vrai(journalContient("refusés par l'essai"), 'son texte au journal')
    -- Absent : la photo reste en file, sans essai ; dit une fois.
    prefs.cheminConnecteur = S.home .. '/absent'
    photo(954)
    journal = {}
    voir(954)
    vider()
    egal(nil, entree(954).analyse, 'en file')
    vrai(journalContient('connecteur introuvable'), 'dit au journal')
    vrai(Releve.prochaineVerification > os.time(), 'regardée de nouveau plus tard')
    egal(false, Releve.relancer(), 'pas tout de suite')
    -- Le connecteur revient : la file reprend d'elle-même (relevé relu après une fermeture).
    prefs.cheminConnecteur = CONNECTEUR
    mode('contrat')
    Releve.oublier()
    Releve.prochaineVerification = 0
    vider()
    vrai(entree(954).analyse and entree(954).analyse.cherches ~= nil, 'analysée à la reprise')
end)

essai("Éteint par Arret.lua (Releve.eteindre : un rechargement, une désactivation) : la tâche s'arrête après son attente (vignettes, --analyser, une pause sans fin), sans lancer le connecteur ni plus rien écrire ; ni vue ni tâche ensuite ; rallumé, tout reprend", function()
    depart()
    local LrTasks = S.modules.LrTasks
    local dormir, executer = LrTasks.sleep, LrTasks.execute
    -- Arret.lua l'éteint (essai d'Arret.lua dans tests.lua).
    contient(assert(Fichiers.lire(S.plugin .. '/Arret.lua')), "require('Releve').eteindre()", 'Arret.lua')
    -- Pendant les vignettes : le connecteur n'est pas lancé, rien n'est écrit ensuite.
    photo(1601)
    photo(1602)
    voir(1601, 1602)
    pendantVignette = function() Releve.eteindre() end
    local version = Releve.version
    vider()
    pendantVignette = nil
    egal(0, #recus(), "le connecteur n'est pas lancé après l'arrêt")
    egal(1, Releve.version - version, 'la vue, écrite avant ; rien après')
    egal(nil, entree(1601).analyse, 'pas analysée : elle se refera')
    egal(0, #dossiersDeLots(), 'le dossier du lot effacé')
    egal(false, Releve.relancer(), 'éteint : aucune tâche')
    egal(false, voir(1602), 'éteint : aucune vue')
    -- Pendant --analyser : sa réponse n'est ni gardée ni écrite.
    Releve.allumer()
    egal(false, Releve.arrete, 'rallumé')
    LrTasks.execute = function(commande)
        local code = executer(commande)
        if commande:find('--analyser', 1, true) then
            Releve.eteindre()
        end
        return code
    end
    version = Releve.version
    local ok, erreur = pcall(vider)
    LrTasks.execute = executer
    assert(ok, erreur)
    egal(1, #recus(), 'le connecteur lancé une fois')
    egal(0, Releve.version - version, "sa réponse n'est pas écrite")
    egal(nil, Releve.entree(1601).analyse, 'ni gardée')
    -- Une pause sans fin (Moteur.travaille resté vrai dans l'ancienne instance : sa boucle est
    -- arrêtée) : la tâche s'arrête après son attente ; une vue rangée pendant la pause n'est jamais
    -- écrite, même à la fin de la tâche.
    Releve.allumer()
    Releve.DELAI_ECRITURE = 1000
    -- La dernière écriture loin derrière : 1603 s'écrit à son tour, tout de suite.
    Releve.ecritLe = nil
    photo(1603)
    photo(1604)
    Moteur.travaille = true
    voir(1603)
    local sommeils, rangee = 0, nil
    LrTasks.sleep = function()
        sommeils = sommeils + 1
        if sommeils == 1 then
            voir(1604)
        elseif sommeils == 2 then
            rangee = Releve.entree(1604) ~= nil
            Releve.eteindre()
        end
    end
    version = Releve.version
    ok, erreur = pcall(vider)
    LrTasks.sleep = dormir
    Moteur.travaille = false
    assert(ok, erreur)
    egal(2, sommeils, "la tâche s'arrête après son attente, Claude toujours au travail")
    egal(true, rangee, '1604 rangée pendant la pause (en mémoire)')
    egal(1, Releve.version - version, 'une écriture, à son tour ; aucune après l\'arrêt')
    vrai(entree(1603) ~= nil, '1603, écrite à son tour')
    egal(nil, entree(1604), "1604, jamais écrite : le fichier est à la nouvelle instance")
    -- Rallumé (une réactivation dans le Gestionnaire de modules externes) : tout reprend.
    Releve.allumer()
    Releve.DELAI_ECRITURE = 0
    vider()
    vrai(entree(1604) ~= nil, '1604 écrite')
    for _, id in ipairs({ 1601, 1602, 1603, 1604 }) do
        vrai(entree(id).analyse and entree(id).analyse.cherches, id .. ' : analysée, la file reprise')
    end
end)

essai("Branchements : la fenêtre Claude et la Demande rapide ajoutent la vue d'une sélection une fois, l'ouverture la revoit, leurs boucles relancent la tâche ; éteint, rien", function()
    depart()
    photo(1001)
    photo(1002)
    choisir(1001)
    Fenetre.suivreSelection(Lightroom.photos())
    egal(1, #Releve.aVoir, 'la fenêtre Claude : une vue')
    Fenetre.suivreSelection(Lightroom.photos())
    egal(1, #Releve.aVoir, 'la même sélection : rien de plus')
    choisir(1002, 1001)
    FenetreRapide.suivreSelection(Lightroom.photos())
    egal(2, #Releve.aVoir, 'la Demande rapide : une vue')
    egal(2, #Releve.aVoir[2].photos)
    Fenetre.suivreSelection(Lightroom.photos())
    egal(2, #Releve.aVoir, 'vue par la Demande rapide, pas deux fois')
    Releve.revoir()
    Fenetre.suivreSelection(Lightroom.photos())
    egal(3, #Releve.aVoir, "l'ouverture : revue, même inchangée")
    -- Les ouvertures appellent Releve.revoir, les boucles Releve.relancer.
    local source = assert(Fichiers.lire(S.plugin .. '/Fenetre.lua'))
    local afficher = source:match('function Fenetre%.afficher%(%)(.-)\nend\n')
    vrai(select(2, afficher:gsub('Releve%.revoir%(%)', '')) == 2, "Fenetre.afficher : à l'ouverture et au rappel")
    contient(source:match('function Fenetre%.boucle%(generation%)(.-)\nend\n'), 'Releve.relancer', 'Fenetre.boucle')
    local rapide = assert(Fichiers.lire(S.plugin .. '/FenetreRapide.lua'))
    contient(rapide:match('local function boucle%(%)(.-)\nend\n'), 'Releve.relancer()', 'la boucle de la Demande rapide')
    contient(rapide:match('function FenetreRapide%.afficher%(%)(.-)\nend\n'), 'Releve.revoir()', 'FenetreRapide.afficher')
    -- Une seule tâche à la fois.
    local taches = #S.taches
    egal(true, Releve.relancer())
    egal(false, Releve.relancer(), 'déjà une tâche')
    egal(taches + 1, #S.taches)
    S.taches[#S.taches]()
    egal(false, Releve.enCours)
    -- Éteint (hors de Lightroom, dans les essais) : rien.
    Releve.allume = false
    Releve.revoir()
    choisir(1001)
    Fenetre.suivreSelection(Lightroom.photos())
    egal(0, #Releve.aVoir, 'éteint : aucune vue')
    egal(false, Releve.relancer(), 'éteint : aucune tâche')
    egal(taches + 1, #S.taches)
    Releve.allume = true
end)

essai("Rien n'est écrit au catalogue ; la famille se relit à l'ouverture de la fenêtre Suivi (Releve.reclasser) ; ce qui sort est une copie neuve", function()
    depart()
    local ecritures = S.ecrituresPrivees or 0
    photo(1101, { note = 2 })
    photo(1102, { copieDe = 1101, copie = 'Copie 1' })
    voir(1101)
    vider()
    egal(ecritures, S.ecrituresPrivees or 0, 'aucune écriture privée')
    egal(2, entree(1101).note)
    -- La copie notée 5 ★ et retenue dans Lightroom, sans être revue : relue par reclasser.
    PHOTOS[1102].brut.rating, PHOTOS[1102].brut.pickStatus = 5, 1
    egal(1, Releve.reclasser())
    local e = entree(1101)
    egal(5, e.note, 'la note la plus haute de la famille')
    egal('retenue', e.drapeau)
    -- Toutes rejetées : rejetée.
    PHOTOS[1101].brut.pickStatus, PHOTOS[1102].brut.pickStatus = -1, -1
    Releve.reclasser()
    egal('rejetee', entree(1101).drapeau)
    -- Les lectures groupées refusées : une à une.
    S.catalogue.batchGetRawMetadata = function() error('lecture groupée refusée') end
    PHOTOS[1102].brut.pickStatus = 0
    Releve.reclasser()
    egal('aucun', entree(1101).drapeau, 'relu une à une')
    S.catalogue.batchGetRawMetadata = lectureGroupee(function(ph, cle) return ph.brut[cle] end)
    -- Des copies neuves vers l'extérieur.
    local liste = Releve.entrees()
    neuve(liste, 'Releve.entrees')
    neuve(Releve.entree(1101), 'Releve.entree')
    liste[1].note = 0
    egal(5, Releve.entree(1101).note, 'une copie : le relevé ne change pas')
    egal(ecritures, S.ecrituresPrivees or 0, 'toujours aucune écriture')
end)

essai("uninstall.sh : --tout retire suivi.json et ses copies mises de côté (tout le dossier) ; sans --tout, il reste et le script le dit", function()
    local script = assert(Fichiers.lire(dossierTests .. '/../../../uninstall.sh'), 'uninstall.sh')
    local entete = script:match('^(.-)\nset %-euo pipefail')
    contient(entete, '(suivi.json', 'en-tête')
    contient(entete, 'suivi-illisible-*.json', 'en-tête : les copies mises de côté')
    local travail = script:match('TRAVAIL=%((.-)\n%)')
    vrai(not travail:find('suivi', 1, true), "suivi.json n'est pas un fichier de travail")
    contient(script, 'retirer "${DEST_DIR}"', '--tout retire tout le dossier')
    local gardes = script:match('GARDES%+=%("%${DEST_DIR} %((.-)%)"%)')
    contient(gardes, 'suivi des photos ouvertes', 'gardé et dit')
    -- Les vignettes d'un lot laissées par une séance finie s'effacent au chargement.
    local Menage = require 'Menage'
    Fichiers.ecrire(Chemins.temporaire() .. '/Suivi/Analyse-1-1/42.jpg', 'jpeg')
    vrai(Menage.temporaires() >= 1)
    egal(false, Fichiers.existe(Chemins.temporaire() .. '/Suivi'), 'Temporaire/Suivi effacé au chargement')
end)

-- Toute la bibliothèque (correctif 1.3.8) -----------------------------------------------------------

essai("Toute la bibliothèque, pas réduits : une grande sélection, la relecture, l'écriture, la file et le reclassement rendent la main toutes les PAS (LrTasks.yield, seulement si LrTasks.canYield), jamais à travers un pcall simple ; les photos des Essais lues d'un coup ; rien de perdu", function()
    depart()
    Releve.PAS, Releve.PAS_UNE_A_UNE, Releve.PAS_ECRITURE, Releve.PAS_JSON, Releve.LOT_LECTURE = 50, 10, 50, 200, 100
    Releve.SEUIL_ESSAIS = 100
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 1000 do
        ids[i] = 20000 + i
        photo(ids[i], { iso = 400, note = i % 6, prise = '2026-10-01 12:00' })
    end
    -- Des photos des Essais (une copie et son original, une copie des Essais d'un original vu), une
    -- autre collection Essais, une vidéo.
    photo(21001, { essai = true })
    photo(21002, { copieDe = 21001, copie = 'Copie 1' })
    photo(21003, { copieDe = 20001, copie = 'Copie 1', essai = true, note = 5 })
    photo(21004, { autre = true })
    photo(21005, { format = 'VIDEO' })
    for _, id in ipairs({ 21001, 21002, 21003, 21004, 21005 }) do
        ids[#ids + 1] = id
    end
    -- La vue : lue et rangée par tranches ; les Essais d'un coup, aucune collection photo par photo.
    local r = rendreLaMainPendant(function()
        voir(unpack(ids))
        vider()
    end)
    vrai(r.n >= 1000 / Releve.PAS, 'la vue rend la main : ' .. r.n)
    egal(0, r.traversees, 'jamais à travers un pcall simple')
    egal(0, COLLECTIONS_DEMANDEES, 'aucune collection demandée photo par photo')
    local f = fichier().catalogues[CATALOGUE].photos
    local n = 0
    for _ in pairs(f) do
        n = n + 1
    end
    egal(1001, n, 'les mille photos et l\'autre collection Essais')
    egal(nil, f['21001'], 'une photo des Essais')
    egal(nil, f['21002'], "la copie d'un original des Essais")
    egal(nil, f['21005'], 'une vidéo')
    vrai(f['21004'] ~= nil, "une autre collection « Essais »")
    egal(1, f['20001'].note, 'la copie des Essais ne compte pas dans la famille')
    -- La relecture : par morceaux (Json.decode avec un rythme), puis la même.
    Releve.oublier()
    Releve.PAS_JSON = 200
    r = rendreLaMainPendant(function() egal(1001, (Releve.nombre())) end)
    vrai(r.n >= 20, 'la relecture rend la main : ' .. r.n)
    egal(0, r.traversees)
    -- L'écriture : par morceaux, entrée par entrée ; le fichier relu dit la même chose.
    local avant = Fichiers.lire(Releve.fichier())
    Releve.aEcrire = true
    local version = Releve.version
    r = rendreLaMainPendant(function() egal(true, Releve.ecrire()) end)
    vrai(r.n >= 1000 / Releve.PAS_ECRITURE, "l'écriture rend la main : " .. r.n)
    egal(0, r.traversees)
    egal(version + 1, Releve.version)
    memes(Json.decode(avant), fichier(), 'le même relevé')
    -- Sans pouvoir rendre la main (hors d'une tâche) : jamais de yield, le fichier s'écrit quand même.
    Releve.aEcrire = true
    r = rendreLaMainPendant(function() egal(true, Releve.ecrire()) end, { canYield = false })
    egal(0, r.n, 'aucun yield sans LrTasks.canYield')
    egal(version + 2, Releve.version)
    -- La file refaite entière : par paquets, la main rendue ; tous les originaux sans analyse.
    r = rendreLaMainPendant(function() egal(1001, Releve.refaireFile()) end)
    vrai(r.n >= 1000 / Releve.PAS, 'la file rend la main : ' .. r.n)
    egal(0, r.traversees)
    -- Le reclassement : chaque original retrouvé une à une, la main rendue toutes les PAS_UNE_A_UNE ;
    -- seule l'entrée dont la note a changé change.
    PHOTOS[20500].brut.rating = 5
    r = rendreLaMainPendant(function() egal(1, Releve.reclasser()) end)
    vrai(r.n >= 1000 / Releve.PAS_UNE_A_UNE, 'le reclassement rend la main : ' .. r.n)
    egal(0, r.traversees)
    egal(5, entree(20500).note, 'relu et écrit')
    egal(0, COLLECTIONS_DEMANDEES, 'le reclassement non plus : les Essais lus d\'un coup')
    -- Les collections illisibles : chaque photo jugée comme avant (Carnet.estPhotoDEssai).
    local ensembles = S.catalogue.getChildCollectionSets
    S.catalogue.getChildCollectionSets = function() error('collections illisibles') end
    Releve.revoir()
    voir(unpack(ids))
    vider()
    S.catalogue.getChildCollectionSets = ensembles
    vrai(COLLECTIONS_DEMANDEES > 0, 'photo par photo')
    egal(nil, entree(21001), 'toujours pas les Essais')
end)

essai("Écriture par morceaux : `aEcrire` remis à faux dès le début (ce qui se range pendant s'écrit à la suivante), une seule à la fois (une autre, sans pouvoir attendre, laissée à la suivante) ; le Suivi éteint pendant : abandonnée, le fichier d'avant tel quel, aucun provisoire", function()
    depart()
    Releve.PAS_ECRITURE = 2
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 10 do
        ids[i] = 22000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    local LrTasks = S.modules.LrTasks
    local version = Releve.version
    Releve.aEcrire = true
    local vu = {}
    rendreLaMainPendant(function() egal(true, Releve.ecrire()) end, { pendant = function(n)
        if n == 1 then
            vu.remis = Releve.aEcrire
            -- Une vue rangée par la tâche du Suivi pendant que la fenêtre Suivi écrit.
            Releve.aEcrire = true
            -- Une autre écriture, hors d'une tâche : elle n'attend pas, laissée à la suivante.
            local peut = LrTasks.canYield
            LrTasks.canYield = function() return false end
            vu.autre = Releve.ecrire()
            LrTasks.canYield = peut
        end
    end })
    egal(false, vu.remis, '`aEcrire` remis à faux dès le début')
    egal(false, vu.autre, 'une seule écriture à la fois')
    egal(true, Releve.aEcrire, 'ce qui a changé pendant : à la suivante')
    egal(version + 1, Releve.version)
    egal(true, Releve.ecrire(), 'la suivante')
    egal(false, Releve.aEcrire)
    -- Le Suivi éteint pendant l'écriture (un rechargement du module) : abandonnée.
    local texte = Fichiers.lire(Releve.fichier())
    version = Releve.version
    Releve.aEcrire = true
    rendreLaMainPendant(function() egal(false, Releve.ecrire()) end, { pendant = function(n)
        if n == 2 then
            Releve.eteindre()
        end
    end })
    egal(texte, Fichiers.lire(Releve.fichier()), "le fichier d'avant tel quel")
    egal(false, Fichiers.existe(Releve.fichier() .. '.provisoire'), 'aucun provisoire')
    egal(version, Releve.version, 'rien écrit')
    Releve.allumer()
end)

essai("La file se garde d'une vue à l'autre : les originaux d'une vue passent devant (la photo active d'abord), la suite garde son ordre, sans être refaite ; le même ordre qu'une file refaite (la tête, les plus récemment vues, l'ordre de la sélection, l'identifiant)", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 30 do
        ids[i] = 23000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    -- Vues il y a une minute (la vue suivante est plus récente : la même seconde, l'ordre de la
    -- sélection les départagerait).
    local f = fichier()
    for _, e in pairs(f.catalogues[CATALOGUE].photos) do
        e.vu = e.vu - 60
    end
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    egal(30, Releve.refaireFile())
    local avant = {}
    for i, cle in ipairs(Releve.file.liste) do
        avant[i] = cle
    end
    for i = 1, 30 do
        egal(tostring(23000 + i), avant[i], "relue : par l'identifiant (même heure de vue, ni tête ni rang)")
    end
    -- Une autre sélection : ses originaux devant, la file gardée derrière.
    voir(23026, 23027)
    vider()
    vrai(Releve.file ~= nil, 'la file gardée')
    egal('23026', Releve.file.liste[1], 'la photo active de la vue en tête')
    egal('23027', Releve.file.liste[2])
    local k = 3
    for _, cle in ipairs(avant) do
        if cle ~= '23026' and cle ~= '23027' then
            egal(cle, Releve.file.liste[k], 'la suite dans son ordre')
            k = k + 1
        end
    end
    egal(31, k, 'chacune une fois')
    -- Refaite entière : le même ordre que la file gardée (la tête, puis les plus récemment vues,
    -- puis par identifiant).
    local gardee = {}
    for i, cle in ipairs(Releve.file.liste) do
        gardee[i] = cle
    end
    Releve.refaireFile()
    for i = 1, 30 do
        egal(gardee[i], Releve.file.liste[i], 'refaite : ' .. i)
    end
end)

essai("Une grande sélection revue à l'ouverture (Releve.revoir) moins de REVOIR_APRES secondes après sa vue entière : seule la photo active ; plus tard, ou une petite sélection, entière", function()
    depart()
    Releve.SEUIL_REVOIR = 3
    prefs.cheminConnecteur = S.home .. '/absent'
    for id = 24001, 24005 do
        photo(id)
    end
    voir(24001, 24002, 24003, 24004, 24005)
    egal(5, #Releve.aVoir[1].photos)
    vider()
    Releve.revoir()
    voir(24001, 24002, 24003, 24004, 24005)
    egal(1, #Releve.aVoir, 'une vue')
    egal(1, #Releve.aVoir[1].photos, 'la photo active seule')
    vider()
    Releve.groupeVuLe = os.time() - Releve.REVOIR_APRES
    Releve.revoir()
    voir(24001, 24002, 24003, 24004, 24005)
    egal(5, #Releve.aVoir[1].photos, 'plus tard : entière')
    vider()
    Releve.SEUIL_REVOIR = 10
    Releve.revoir()
    voir(24001, 24002, 24003, 24004, 24005)
    egal(5, #Releve.aVoir[1].photos, 'une petite sélection : entière')
end)

essai("Un grand relevé s'écrit moins souvent : l'écart entre deux écritures est d'au moins FACTEUR_ECRITURE fois la durée propre de la dernière (le temps des autres tâches, quand elle rend la main, n'y compte pas) et SECONDES_PAR_MO par Mo du fichier ; DELAI_ECRITURE au moins, DELAI_ECRITURE_MAX au plus", function()
    depart()
    Releve.FACTEUR_ECRITURE = PAS.FACTEUR_ECRITURE
    egal(10, Releve.FACTEUR_ECRITURE, 'dix fois')
    egal(1, Releve.SECONDES_PAR_MO, 'une seconde par Mo')
    egal(60, Releve.DELAI_ECRITURE_MAX, 'une minute au plus')
    Releve.DELAI_ECRITURE = 20
    Releve.PAS_ECRITURE = 1
    prefs.cheminConnecteur = S.home .. '/absent'
    photo(25001)
    photo(25002)
    voir(25001, 25002)
    vider()
    egal(20, Releve.delaiEcriture(), 'une écriture brève : DELAI_ECRITURE')
    local LrDate = S.modules.LrDate
    local maintenant = LrDate.currentTime
    -- Une horloge figée, qui n'avance que de decalage : celle de la simulation est os.time, et
    -- une écriture qui passerait d'une seconde à la suivante durerait 1 s de plus (constaté le
    -- 27 octobre 2026 sur GitHub : 50 au lieu de 40).
    local base, decalage = maintenant(), 0
    LrDate.currentTime = function() return base + decalage end
    local ecrireParMorceaux = Fichiers.ecrireParMorceaux
    local ok, erreur = pcall(function()
        -- Les autres tâches prennent 30 s chaque fois que l'écriture rend la main : pas compté.
        Releve.aEcrire = true
        rendreLaMainPendant(function() egal(true, Releve.ecrire()) end, { pendant = function() decalage = decalage + 30 end })
        egal(20, Releve.delaiEcriture(), "le temps des autres tâches ne compte pas")
        -- L'écriture elle-même dure 4 s (l'horloge avance pendant qu'elle écrit) : 40 s.
        local function dureePropre(secondes)
            Fichiers.ecrireParMorceaux = function(chemin, produire)
                return ecrireParMorceaux(chemin, function(ecrire)
                    local premier = true
                    return produire(function(texte)
                        if premier then
                            decalage = decalage + secondes
                            premier = false
                        end
                        ecrire(texte)
                    end)
                end)
            end
            Releve.aEcrire = true
            rendreLaMainPendant(function() egal(true, Releve.ecrire()) end, { pendant = function() decalage = decalage + 30 end })
            Fichiers.ecrireParMorceaux = ecrireParMorceaux
        end
        dureePropre(4)
        egal(40, Releve.delaiEcriture(), 'dix fois 4 s')
        -- 9 s : 90 s, ramené à DELAI_ECRITURE_MAX (ce qui attend se perdrait si Lightroom quittait).
        dureePropre(9)
        egal(60, Releve.delaiEcriture(), 'DELAI_ECRITURE_MAX au plus')
    end)
    LrDate.currentTime, Fichiers.ecrireParMorceaux = maintenant, ecrireParMorceaux
    assert(ok, erreur)
    -- La taille du fichier : SECONDES_PAR_MO par Mo, écrit ou relu (ici, une seconde pour un
    -- millième du fichier : 45 s).
    Releve.aEcrire = true
    egal(true, Releve.ecrire())
    egal(20, Releve.delaiEcriture(), 'un petit fichier')
    local taille = #Fichiers.lire(Releve.fichier())
    Releve.SECONDES_PAR_MO = 45.5 * 1000000 / taille
    egal(45, Releve.delaiEcriture(), "d'après la taille écrite")
    Releve.oublier()
    egal(2, (Releve.nombre()))
    egal(45, Releve.delaiEcriture(), "d'après la taille relue")
    Releve.SECONDES_PAR_MO = 1000 * 1000000 / taille
    egal(60, Releve.delaiEcriture(), 'DELAI_ECRITURE_MAX au plus')
    -- Un DELAI_ECRITURE plus grand que DELAI_ECRITURE_MAX l'emporte.
    Releve.DELAI_ECRITURE = 1000
    egal(1000, Releve.delaiEcriture())
    Releve.SECONDES_PAR_MO = PAS.SECONDES_PAR_MO
end)

-- De vraies tâches entremêlées (correctif 1.3.8, revue) : des coroutines, chaque LrTasks.yield et
-- LrTasks.sleep rendant la main à un planificateur qui fait tourner chacune à son tour.
local Planificateur = {}
do
    local LrTasks = S.modules.LrTasks
    local avant
    function Planificateur.brancher()
        Planificateur.taches = {}
        avant = { LrTasks.yield, LrTasks.sleep, LrTasks.canYield, LrTasks.startAsyncTask }
        LrTasks.yield = function() coroutine.yield('yield') end
        LrTasks.sleep = function() coroutine.yield('sleep') end
        LrTasks.canYield = function() return coroutine.running() ~= nil end
        LrTasks.startAsyncTask = function(fn) Planificateur.lancer('tâche', fn) end
    end
    function Planificateur.debrancher()
        LrTasks.yield, LrTasks.sleep, LrTasks.canYield, LrTasks.startAsyncTask = unpack(avant)
    end
    function Planificateur.lancer(nom, fn)
        Planificateur.taches[#Planificateur.taches + 1] = { co = coroutine.create(fn), nom = nom }
    end
    -- Fait tourner les tâches tant que l'une vit ; avantPas(pas) entre deux tours.
    function Planificateur.tourner(avantPas)
        for pas = 1, 1000000 do
            local vivantes = 0
            for _, t in ipairs(Planificateur.taches) do
                if coroutine.status(t.co) ~= 'dead' then
                    local ok, erreur = coroutine.resume(t.co)
                    if not ok then
                        error(t.nom .. ' : ' .. tostring(erreur), 0)
                    end
                    vivantes = vivantes + 1
                end
            end
            if vivantes == 0 then
                return pas
            end
            if avantPas then
                avantPas(pas)
            end
        end
        error('trop de pas')
    end
    -- fn() avec le planificateur branché, débranché même après une erreur.
    function Planificateur.avec(fn)
        Planificateur.brancher()
        local ok, erreur = xpcall(fn, debug.traceback)
        Planificateur.debrancher()
        assert(ok, erreur)
    end
end

local function compter(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

essai("Tâches entremêlées : la durée propre d'une écriture ne compte pas le temps des autres tâches (une autre qui prend 0,3 s à chaque tour) ; l'écart suivant reste DELAI_ECRITURE", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    Releve.FACTEUR_ECRITURE = 10
    Releve.DELAI_ECRITURE = 20
    Releve.PAS_ECRITURE = 10
    local ids = {}
    for i = 1, 2000 do
        ids[i] = 32000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    local LrDate = S.modules.LrDate
    local horloge = os.time()
    local vraiCurrent = LrDate.currentTime
    LrDate.currentTime = function() return horloge end
    local ok, erreur = pcall(Planificateur.avec, function()
        Releve.aEcrire = true
        Planificateur.lancer('écriture', function() egal(true, Releve.ecrire()) end)
        local autre = true
        Planificateur.lancer('autre', function()
            while autre do
                horloge = horloge + 0.3
                coroutine.yield()
            end
        end)
        Planificateur.tourner(function()
            if coroutine.status(Planificateur.taches[1].co) == 'dead' then
                autre = false
            end
        end)
    end)
    LrDate.currentTime = vraiCurrent
    assert(ok, erreur)
    egal(Releve.DELAI_ECRITURE, Releve.delaiEcriture(), "l'écart suivant (200 reprises de 0,3 s : 60 s des autres tâches)")
end)

essai("Tâches entremêlées : une entrée revue pendant le tri de l'élagage (une vue rangée par la tâche du Suivi pendant que la fenêtre Suivi écrit) reste ; une autre sort à sa place", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 300 do
        ids[i] = 30000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    -- La plus ancienne : 30001 (vue il y a 10 min), puis 30002 (5 min), les autres il y a 1 min.
    local f = fichier()
    for cle, e in pairs(f.catalogues[CATALOGUE].photos) do
        e.vu = e.vu - (cle == '30001' and 600 or cle == '30002' and 300 or 60)
    end
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    egal(300, (Releve.nombre()))
    Releve.MAX_ORIGINAUX = 299
    Releve.PAS = 1
    Releve.DELAI_ECRITURE = 0
    local trier = 0
    Planificateur.avec(function()
        Releve.aEcrire = true
        Planificateur.lancer('écriture', function() Releve.ecrire() end)
        Planificateur.tourner(function(pas)
            -- Pendant le tri (l'élagage rend la main à chaque clé) : la fenêtre Claude voit 30001.
            if pas == 260 then
                trier = pas
                voir(30001)
                Releve.relancer()
            end
        end)
    end)
    egal(260, trier, 'la vue pendant le tri')
    local relu = fichier().catalogues[CATALOGUE].photos
    egal(299, compter(relu), 'MAX_ORIGINAUX')
    vrai(relu['30001'] ~= nil, '30001, revue pendant le tri, reste')
    egal(nil, relu['30002'], 'la suivante la moins récemment vue sort à sa place')
end)

essai("Tâches entremêlées : une note changée dans Lightroom et vue (rangerVue) pendant que Releve.reclasser lit le catalogue n'est pas remise à l'ancienne par lui", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 200 do
        ids[i] = 31000 + i
        photo(ids[i], { note = 1 })
    end
    voir(unpack(ids))
    vider()
    egal(1, entree(31100).note)
    Releve.PAS, Releve.PAS_UNE_A_UNE = 1, 1
    Releve.DELAI_ECRITURE = 0
    -- La lecture du classement par le reclassement repérée ; après elle, Dany pose 4 ★ et la fenêtre
    -- Claude voit ces photos.
    local lu, vue = false, false
    local brut = S.catalogue.batchGetRawMetadata
    S.catalogue.batchGetRawMetadata = function(cat, photos, cles)
        for _, c in ipairs(cles) do
            if c == 'rating' and not vue then
                lu = true
            end
        end
        return brut(cat, photos, cles)
    end
    local changees = { 31010, 31050, 31100, 31150, 31190 }
    local n
    local ok, erreur = pcall(Planificateur.avec, function()
        Planificateur.lancer('reclasser', function() n = Releve.reclasser() end)
        Planificateur.tourner(function()
            if lu and not vue then
                vue = true
                for _, id in ipairs(changees) do
                    PHOTOS[id].brut.rating = 4
                end
                Releve.revoir()
                voir(unpack(changees))
                Releve.relancer()
            end
        end)
    end)
    S.catalogue.batchGetRawMetadata = brut
    assert(ok, erreur)
    vrai(vue, 'vues pendant le reclassement')
    egal(0, n, 'rien de changé par le reclassement (les autres notes sont les mêmes)')
    for _, id in ipairs(changees) do
        egal(4, entree(id).note, id .. ' : la note de la vue, plus fraîche')
    end
    egal(nil, Releve.revues, 'plus rien de noté après le reclassement')
end)

essai("Releve.ecrire (avant un dessin demandé) pendant qu'une autre tâche écrit : il attend qu'elle finisse, puis écrit ce qui reste ; --graphiques lit le relevé entier", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    local ids = {}
    for i = 1, 20 do
        ids[i] = 35000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    local ancien = Fichiers.lire(Releve.fichier())
    for i = 21, 50 do
        ids[i] = 35000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    -- Le fichier d'avant remis : les 30 de plus sont rangées en mémoire, pas encore écrites.
    Fichiers.ecrire(Releve.fichier(), ancien)
    egal(20, compter(fichier().catalogues[CATALOGUE].photos), 'pas encore écrites')
    Releve.PAS_ECRITURE = 1
    local dessin
    Planificateur.avec(function()
        -- La tâche du Suivi écrit ; la fenêtre Suivi demande un dessin pendant ce temps.
        Planificateur.lancer('suivi', function()
            Releve.aEcrire = true
            Releve.ecrire()
        end)
        Planificateur.tourner(function(pas)
            if pas == 3 then
                Planificateur.lancer('fenêtre', function()
                    local ecrit = Releve.ecrire()
                    dessin = { ecrit = ecrit, n = compter(fichier().catalogues[CATALOGUE].photos) }
                end)
            elseif pas == 6 then
                -- Une vue de plus rangée pendant l'écriture : la fenêtre l'écrit après elle.
                photo(35051)
                ids[51] = 35051
                Releve.aEcrire = true
            end
        end)
    end)
    egal(true, dessin.ecrit, 'écrit (celle attendue, puis la suivante)')
    egal(50, dessin.n, 'le dessin demandé lit le relevé entier')
end)

-- La tâche du Suivi pour un seul lot : après --analyser, Claude se met au travail, et la pause
-- éteint le Suivi (la tâche s'arrête après son attente) ; puis rallumé. Rend l'entrée du lot reçue
-- par le connecteur.
local function unLot()
    local LrTasks = S.modules.LrTasks
    local executer, dormir = LrTasks.execute, LrTasks.sleep
    local recu
    LrTasks.execute = function(commande)
        local code = executer(commande)
        if commande:find('--analyser', 1, true) then
            Moteur.travaille = true
            recu = recus()[#recus()]
        end
        return code
    end
    LrTasks.sleep = function() Releve.eteindre() end
    Releve.prochaineVerification = 0
    local ok, erreur = pcall(vider)
    LrTasks.execute, LrTasks.sleep = executer, dormir
    Moteur.travaille = false
    Releve.allumer()
    assert(ok, erreur)
    return recu
end

local function idsDuLot(recu)
    local ids = {}
    for _, p in ipairs(recu and recu.photos or {}) do
        ids[#ids + 1] = tostring(p.id)
    end
    return table.concat(ids, ' ')
end

essai("Une analyse manquée passe devant la file gardée à son heure (Releve.reessais), sans attendre que toute la file soit épuisée ; abandonnée, plus de réessai ; au-delà de MAX_REESSAIS, elle attend que la file se refasse", function()
    depart()
    local ids = {}
    for i = 1, 30 do
        ids[i] = 34000 + i
        photo(ids[i])
    end
    prefs.cheminConnecteur = S.home .. '/absent'
    voir(unpack(ids))
    vider()
    prefs.cheminConnecteur = CONNECTEUR
    Releve.LOT_ANALYSE = 2
    -- Les règles du connecteur déjà connues (une réponse plus tôt dans la séance), celles du genre
    -- comprises : la file gardée ne se refait pas pour elles.
    Releve.regles, Releve.reglesGenre = 1, 1
    avecLeTemps(function()
        egal(30, Releve.refaireFile())
        egal('34001', Releve.file.liste[1])
        -- Le connecteur muet pour le premier lot : 34001 et 34002 manquées, à réessayer dans
        -- DELAI_REESSAI ; la suite de la file reste gardée.
        mode('muet')
        egal('34001 34002', idsDuLot(unLot()))
        egal('pas_de_reponse', Releve.entree(34001).analyse.erreur, 'manquée')
        egal(2, #Releve.reessais, 'à réessayer')
        egal('34001', Releve.reessais[1].cle)
        egal(os.time() + Releve.DELAI_REESSAI, Releve.reessais[1].le, 'dans DELAI_REESSAI')
        egal(28, #Releve.file.liste - Releve.file.i + 1, 'la file gardée : les 28 autres')
        -- Avant leur heure, le lot suivant vient de la file ; à leur heure, elles passent devant.
        mode('contrat')
        egal('34003 34004', idsDuLot(unLot()), 'avant leur heure : la file')
        avancerLeTemps(Releve.DELAI_REESSAI)
        egal('34001 34002', idsDuLot(unLot()), 'à leur heure : devant la file gardée')
        vrai(Releve.entree(34001).analyse.cherches ~= nil, 'analysée')
        egal(0, #Releve.reessais)
        egal(26, #Releve.file.liste - Releve.file.i + 1, 'la file gardée, pas refaite')
        egal('34005 34006', idsDuLot(unLot()), 'puis la file reprend')
        -- Au troisième essai, abandonnée : plus de réessai.
        mode('muet')
        Releve.MAX_REESSAIS = 1
        egal('34007 34008', idsDuLot(unLot()))
        egal(1, #Releve.reessais, 'MAX_REESSAIS au plus : 34008 attendra que la file se refasse')
        egal('34007', Releve.reessais[1].cle)
        Releve.MAX_REESSAIS = PAS_REESSAIS
        for _ = 1, 2 do
            avancerLeTemps(Releve.DELAI_REESSAI)
            egal('34007', idsDuLot(unLot()):match('^%d+'), 'réessayée à son heure')
        end
        egal(true, Releve.entree(34007).analyse.abandonnee, 'abandonnée au troisième essai')
        for _, r in ipairs(Releve.reessais) do
            vrai(r.cle ~= '34007', 'abandonnée : plus de réessai')
        end
    end)
end)

essai("Des règles plus récentes (une réponse de --analyser dont regles monte, la première de la séance comprise) : la file gardée se refait au lot suivant, une analyse faite selon les anciennes y entre ; les mêmes règles ensuite, elle se garde", function()
    depart()
    local ids = {}
    for i = 1, 30 do
        ids[i] = 36000 + i
        photo(ids[i])
    end
    prefs.cheminConnecteur = S.home .. '/absent'
    voir(unpack(ids))
    vider()
    prefs.cheminConnecteur = CONNECTEUR
    -- 36030 analysée selon des règles anciennes (0), son genre à jour ; les autres sans analyse.
    local f = fichier()
    f.catalogues[CATALOGUE].photos['36030'].analyse = { le = os.time(), regles = 0, cherches = Json.tableau({ 'flou' }), defauts = Json.tableau({}),
        genre = 'paysage', regles_genre = 1 }
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    egal(29, Releve.refaireFile(), 'la file gardée : les 29 sans analyse (règles encore inconnues)')
    Releve.LOT_ANALYSE = 2
    unLot()
    egal(1, Releve.regles, 'les règles du connecteur')
    egal(nil, Releve.file, 'à refaire au lot suivant')
    unLot()
    vrai(Releve.file ~= nil, 'refaite, puis gardée : les mêmes règles')
    local dedans = false
    for i = 1, #Releve.file.liste do
        dedans = dedans or Releve.file.liste[i] == '36030'
    end
    vrai(dedans, '36030, analysée selon des règles plus anciennes, entre dans la file refaite')
end)

essai("Le genre (correctif 1.3.8) : rangé avec l'analyse ; une analyse d'avant le genre se refait pour lui seul, même avant toute réponse de la séance, ses défauts gardés ; l'objectif part au connecteur (macro)", function()
    depart()
    local ids = {}
    for i = 1, 4 do
        ids[i] = 38000 + i
        photo(ids[i], { objectif = i == 4 and 'XF80mmF2.8 R LM OIS WR Macro' or 'XF23mmF2 R WR' })
    end
    prefs.cheminConnecteur = S.home .. '/absent'
    voir(unpack(ids))
    vider()
    prefs.cheminConnecteur = CONNECTEUR
    -- 38001 et 38002 analysées avant le genre (d'un connecteur 1.3.7), 38001 avec un défaut trouvé
    -- que la vignette d'aujourd'hui (retouchée depuis) ne montrerait plus ; 38003 et 38004 en file.
    local f = fichier()
    local photos = f.catalogues[CATALOGUE].photos
    photos['38001'].analyse = { le = 1000, regles = 1, cherches = Json.tableau({ 'sous_exposition', 'flou' }), defauts = Json.tableau({ 'flou' }) }
    photos['38002'].analyse = { le = 1000, regles = 1, cherches = Json.tableau({ 'flou' }), defauts = Json.tableau({}) }
    Fichiers.ecrire(Releve.fichier(), Json.encode(f))
    Releve.oublier()
    -- Les règles ne sont pas encore connues (aucune réponse de la séance) : les analyses sans genre
    -- entrent quand même dans la file (toute la bibliothèque déjà analysée n'attendrait aucune vue).
    egal(4, Releve.refaireFile(), 'les deux en file et les deux sans genre')
    vider()
    local a1 = entree(38001).analyse
    egal('paysage', a1.genre)
    egal(1, a1.regles_genre)
    egal(1000, a1.le, 'la date de la première analyse, gardée')
    memes(Json.tableau({ 'sous_exposition', 'flou' }), a1.cherches, 'les défauts cherchés, gardés')
    memes(Json.tableau({ 'flou' }), a1.defauts, 'le défaut trouvé, gardé (la vignette retouchée ne le montrerait plus)')
    egal('macro', entree(38004).analyse.genre, "l'objectif macro, parti au connecteur")
    local recu
    for _, r in ipairs(recus()) do
        for _, p in ipairs(r.photos) do
            if p.id == 38004 then
                recu = p
            end
        end
    end
    egal('XF80mmF2.8 R LM OIS WR Macro', recu and recu.objectif, "l'objectif dans l'entrée de --analyser")
    vrai(entree(38003).analyse.le > 1000, 'une analyse neuve : son heure')
    egal(1, Releve.reglesGenre, 'les règles du genre, apprises de la réponse')
    -- Tout a son genre : rien à refaire.
    local appels = #recus()
    Releve.revoir()
    voir(38001)
    vider()
    egal(appels, #recus(), 'rien de refait')
    -- Relu du disque : le genre et ses règles restent.
    Releve.oublier()
    egal(0, Releve.refaireFile())
    egal('paysage', Releve.entree(38001).analyse.genre)
    egal(1, Releve.entree(38001).analyse.regles_genre)
end)

essai("Le genre : des règles du genre plus récentes le font refaire seul (défauts gardés) ; un connecteur sans genre (d'avant le correctif 1.3.8) ne fait rien refaire en boucle ; un genre refait qui échoue garde l'analyse d'avant", function()
    depart()
    local ids = {}
    for i = 1, 3 do
        ids[i] = 39000 + i
        photo(ids[i])
    end
    voir(unpack(ids))
    vider()
    egal('paysage', entree(39001).analyse.genre)
    local le = entree(39001).analyse.le
    -- Les règles du genre montent (2) : refait pour lui seul.
    mode('genre2')
    Releve.revoir()
    photo(39004)
    voir(39004)
    vider()
    egal(2, Releve.reglesGenre)
    egal('ville', entree(39001).analyse.genre, 'refait pour des règles du genre plus récentes')
    egal(2, entree(39001).analyse.regles_genre)
    egal(le, entree(39001).analyse.le, 'les défauts gardés, avec leur heure')
    egal(1, entree(39001).analyse.regles)
    -- Un connecteur sans genre : une analyse sans genre ne se refait pas en boucle.
    depart()
    for i = 1, 3 do
        photo(39100 + i)
    end
    mode('sansgenre')
    voir(39101, 39102, 39103)
    vider()
    egal(nil, entree(39101).analyse.genre, 'sans genre')
    vrai(entree(39101).analyse.cherches ~= nil, 'les défauts, eux, rangés')
    egal(true, Releve.sansGenre, 'le connecteur ne donne pas de genre')
    egal(0, Releve.refaireFile(), 'rien à refaire de la séance')
    egal(false, Releve.relancer(), 'rien à faire : pas de tâche, aucun appel de plus')
    -- La séance suivante, un connecteur à jour : leur genre vient.
    Releve.oublier()
    mode('contrat')
    egal(3, Releve.refaireFile(), 'sans genre : en file')
    -- Le connecteur muet : l'analyse d'avant reste, et ne se refait plus de la séance.
    mode('muet')
    vider()
    vrai(entree(39101).analyse.cherches ~= nil, "l'analyse d'avant, gardée")
    egal(nil, entree(39101).analyse.erreur)
    egal(0, Releve.refaireFile(), 'plus refaite de la séance')
end)

essai("Releve.reclasser sans rien de changé dans le catalogue : aucune entrée changée (ni classement_le ni texte JSON refait), rien écrit ; une note changée : cette entrée seule", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    for i = 1, 20 do
        photo(37000 + i, { note = i % 6 })
    end
    local ids = {}
    for i = 1, 20 do
        ids[i] = 37000 + i
    end
    voir(unpack(ids))
    vider()
    local avant = Fichiers.lire(Releve.fichier())
    local version = Releve.version
    egal(0, Releve.reclasser(), 'rien de changé')
    egal(version, Releve.version, 'rien écrit')
    -- Une écriture forcée ensuite ne refait le texte d'aucune entrée.
    local encode, encodees = Json.encode, 0
    Json.encode = function(v)
        if type(v) == 'table' and v.uuid then
            encodees = encodees + 1
        end
        return encode(v)
    end
    local ok, erreur = pcall(function()
        Releve.aEcrire = true
        egal(true, Releve.ecrire())
        egal(0, encodees, 'aucune entrée réencodée')
        memes(Json.decode(avant), fichier(), 'le même relevé')
        PHOTOS[37005].brut.rating = 3
        egal(1, Releve.reclasser(), 'une note changée')
        egal(1, encodees, 'cette entrée seule réencodée')
        egal(3, entree(37005).note)
    end)
    Json.encode = encode
    assert(ok, erreur)
end)

essai("La fenêtre Suivi pose une sélection (Releve.poserSelection) : pendant qu'elle la pose, aucune sélection vue ne compte ; posée, elle est vue sans être rangée ; une autre photo active du même groupe ne revoit qu'elle ; une autre sélection compte", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    for id = 38001, 38006 do
        photo(id)
    end
    voir(38001)
    vider()
    local pendant
    local r = Releve.poserSelection(function()
        choisir(38002, 38003)
        pendant = Releve.voirSelection(Lightroom.photos())
        choisir(38002, 38003, 38004, 38005)
        return 'posée'
    end)
    egal('posée', r, 'ce que la pose rend')
    egal(false, pendant, 'à moitié posée : pas une vue')
    egal(0, Releve.selectionPosee)
    egal(0, #Releve.aVoir, 'rien à ranger')
    egal(false, voir(38002, 38003, 38004, 38005), 'posée : déjà vue')
    egal(true, voir(38004, 38002, 38003, 38005), 'une autre photo active du même groupe')
    egal(1, #Releve.aVoir[1].photos, 'elle seule')
    egal(true, voir(38006), 'une autre sélection')
    -- Une erreur de la pose remonte, le compte revient à zéro.
    vrai(not pcall(Releve.poserSelection, function() error('refusée') end), "l'erreur remonte")
    egal(0, Releve.selectionPosee)
end)

-- Un relevé de N originaux (de la forme de ceux du contrat), écrit dans suivi.json : la moitié
-- analysés, une copie virtuelle vue sur cent.
local function grandReleve(n)
    local modele = REGISTRE.catalogues[CATALOGUE].photos['4302']
    local analyse = ANALYSER.dans_le_registre['4302']
    local photos = {}
    local vu = os.time() - 86400
    for k = 1, n do
        local id = 1000000 + k * 3
        local uuid = string.format('%08X-0000-4000-8000-%012d', k, k)
        local e = { original = id, uuid = uuid, fichier = 'XH2S' .. k .. '.RAF', ajout = vu, ajout_le = '2026-10-25 10:00',
            vu = vu + math.floor(k / 5000) * 60, prise_de_vue = sansNotes(modele.prise_de_vue), note = k % 6, drapeau = 'aucun',
            retouchee_par_claude = false, classement_le = vu,
            vues = Json.tableau({ { id = id, uuid = uuid, copie_virtuelle = false, fichier = 'XH2S' .. k .. '.RAF', le = vu } }) }
        if k % 100 == 0 then
            e.vues[2] = { id = id + 1, uuid = uuid .. '-c', copie_virtuelle = true, fichier = 'XH2S' .. k .. '.RAF (Copie 1)', le = vu }
        end
        if k % 2 == 0 then
            e.analyse = { le = vu, regles = 1, cherches = Json.tableau({ 'sous_exposition', 'surexposition', 'ciel_brule', 'flou' }),
                defauts = Json.tableau(k % 10 == 0 and { 'flou' } or {}) }
        end
        photos[tostring(id)] = e
    end
    Fichiers.ecrire(Releve.fichier(), Json.encode({ format = 1, catalogues = { [CATALOGUE] = { photos = photos } } }))
    return analyse
end

-- La taille réelle : 85 000 originaux (la bibliothèque de Dany), ou DEVELOPPEUR_SUIVI_ORIGINAUX
-- (250 000, la borne : plus long).
local ORIGINAUX = tonumber(os.getenv('DEVELOPPEUR_SUIVI_ORIGINAUX') or '') or 85000

essai(string.format("Taille réelle, %d originaux : la relecture, l'écriture (la première, puis pendant l'analyse), la file refaite et une vue de mille photos ne gardent jamais la main plus de 0,3 s ; l'écriture pendant l'analyse ne refait que les entrées changées", ORIGINAUX), function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent'
    local t0 = os.clock()
    grandReleve(ORIGINAUX)
    -- Le relevé fabriqué ici n'est pas celui que Lightroom aurait en mémoire : rendu au ramasse-miettes.
    collectgarbage('collect')
    Releve.oublier()
    local morceaux = {}
    local r = rendreLaMainPendant(function() egal(ORIGINAUX, (Releve.nombre())) end)
    morceaux.relecture = r
    Releve.aEcrire = true
    r = rendreLaMainPendant(function() egal(true, Releve.ecrire()) end)
    morceaux.premiere = r
    local premiere = os.clock()
    -- Mille photos du relevé revues (une sélection), rangées : mille entrées changées, écrites
    -- ensuite (une écriture pendant l'analyse).
    local ids = {}
    for k = 1, 1000 do
        local id = 1000000 + k * 3
        ids[k] = id
        photo(id, { uuid = string.format('%08X-0000-4000-8000-%012d', k, k) })
    end
    local version = Releve.version
    r = rendreLaMainPendant(function()
        voir(unpack(ids))
        vider()
    end)
    morceaux.vue = r
    egal(version + 1, Releve.version, 'la vue écrite')
    -- Rien de changé depuis : une écriture de plus ne refait aucune entrée.
    local t1 = os.clock()
    Releve.aEcrire = true
    r = rendreLaMainPendant(function() egal(true, Releve.ecrire()) end)
    morceaux.suivante = r
    local suivante = os.clock() - t1
    r = rendreLaMainPendant(function() vrai(Releve.refaireFile() >= ORIGINAUX / 2) end)
    morceaux.file = r
    for _, nom in ipairs({ 'relecture', 'premiere', 'vue', 'suivante', 'file' }) do
        local m = morceaux[nom]
        print(string.format('       %-10s plus long morceau %.3f s (%d yields)', nom, m.plusLong, m.n))
        vrai(m.plusLong < 0.3, nom .. ' : un morceau de ' .. string.format('%.3f', m.plusLong) .. ' s sans rendre la main')
        egal(0, m.traversees, nom .. ' : à travers un pcall simple')
    end
    vrai(suivante < (premiere - t0) / 4, string.format("l'écriture suivante ne refait que les entrées changées : %.3f s", suivante))
    local relu = fichier().catalogues[CATALOGUE].photos
    egal('DSCF1000003.RAF', relu['1000003'].fichier, 'la vue écrite, relue')
    egal(1, #relu['1000003'].vues)
    print(string.format('       en tout %.1f s', os.clock() - t0))
end)

-- Fin -----------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
