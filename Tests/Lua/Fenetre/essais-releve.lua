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
-- donne, sinon les défauts cherchés de ses règles, aucun trouvé), « regles2 » (de même, règles 2),
-- « muet » (rien : l'alarme, ou un vieux connecteur), « refus » (ok faux). Une vignette absente le
-- dit, comme le vrai.
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
        photos[#photos + 1] = s
    else
        local cherches = Json.tableau()
        if not p.retouchee then
            cherches[1], cherches[2], cherches[3] = 'sous_exposition', 'surexposition', 'ciel_brule'
            if (p.iso or 0) >= 1600 then cherches[#cherches + 1] = 'bruit' end
        end
        cherches[#cherches + 1] = 'flou'
        photos[#photos + 1] = { id = p.id, cherches = cherches, defauts = Json.tableau(), mesures = { cote = 1024 } }
    end
end
print(Json.encode({ ok = true, regles = mode == 'regles2' and 2 or 1, photos = photos }))
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
-- Les lectures groupées du catalogue.
local GROUPEES = 0

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

-- Aides ------------------------------------------------------------------------------------------

local function supprimerSuivi()
    S.executer('rm -f ' .. S.q(Chemins.racine()) .. '/suivi*.json ' .. S.q(RECUS))
    S.executer('rm -rf ' .. S.q(Chemins.temporaire() .. '/Suivi'))
end

-- Un départ neuf : aucun relevé, aucune photo, le Suivi allumé, le connecteur au mode du contrat.
local function depart()
    PHOTOS, ACTIVE, SELECTION, VIGNETTES, pendantVignette, GROUPEES = {}, nil, {}, {}, nil, 0
    supprimerSuivi()
    Releve.oublier()
    Releve.allume = true
    Releve.MAX_ORIGINAUX, Releve.MAX_VUES, Releve.MAX_SELECTION = BORNES.max_originaux, BORNES.max_vues, BORNES.max_selection
    Releve.DELAI_ECRITURE, Releve.MAX_EN_ATTENTE = 0, 20
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

essai("Un groupe de six photos : l'entrée de --analyser est celle du contrat (ordre, iso, cache, retouchee), le relevé ensuite comme dans_le_registre", function()
    depart()
    photoDuContrat(4302)
    photo(4303, { iso = 5000 })
    photo(4304, { format = 'RAW' })
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

essai("Écritures espacées, vues comprises : la première tout de suite, puis au plus une toutes les DELAI_ECRITURE secondes ; à la fin de la file, la tâche attend son tour en rangeant les vues qui arrivent ; au début d'une pause tout de suite", function()
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
        -- Claude se met au travail : ce qui est rangé s'écrit au début de la pause, puis à son tour
        -- (les vues rangées pendant la pause) ; l'analyse attend.
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
        egal(1, pendant[1].ecritures, 'au début de la pause, tout de suite (1307, 0 s après la dernière)')
        egal(1, pendant[5].ecritures, 'pas à chaque vue pendant la pause (1308 à 1311)')
        egal(2, pendant[6].ecritures, '10 s après : à son tour (1312)')
        for i = 1, 8 do
            egal(analyses, pendant[i].analyses, 'rien analysé pendant la pause ' .. i)
        end
        egal(3, Releve.version - version, 'la troisième à la fin de la file, 10 s après')
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
    egal(20000, Releve.MAX_ORIGINAUX, 'max_originaux du contrat')
    egal(20, Releve.MAX_VUES, 'max_vues du contrat')
    egal(1000, Releve.MAX_SELECTION, 'max_selection du contrat')
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
    egal(1, Releve.version - version, 'une écriture, au début de la pause ; aucune après l\'arrêt')
    vrai(entree(1603) ~= nil, '1603, écrite au début de la pause')
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

-- Fin -----------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
