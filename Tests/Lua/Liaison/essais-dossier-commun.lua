-- essais-dossier-commun.lua : le dossier commun (3 novembre 2026 : deux Mac, le SSD « Photos »)
-- côté liaison, hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua, fichiers en mémoire
-- sous S.home) : les commandes du serveur qui rangent des données (carnet, notation, étapes) les
-- écrivent dans le dossier commun quand il est réglé, et sont refusées sans rien écrire quand il est
-- introuvable (jamais de repli sur la racine locale) ; ce qui reste local (le jeton de la liaison)
-- ne bouge pas. Jamais le vrai pointeur : il est dans le dossier personnel simulé.
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue = A.test, A.egal, A.echoue
local photoRaw, photoJpeg = A.photoRaw, A.photoJpeg

local Json = require 'Json'
local Commandes = require 'Commandes'
local Carnet = require 'Carnet'
local Notation = require 'Notation'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Liaison = require 'Liaison'

local LOCALE = S.home .. '/Library/Application Support/Developpeur'
local COMMUN = S.home .. '/Volumes/Photos/Développeur partagé'
local ABSENT = S.home .. '/Volumes/Photos débranché/Développeur'
local MESSAGE = "Le dossier commun (" .. ABSENT .. ") est introuvable : branchez le SSD qui le contient, ou réglez un autre dossier dans Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom."

local VOCABULAIRE = {
    { code = 'flou', cle = 'blur', axe = 'lumiere', domaine = 'nettete', libelle = "Photo floue ou bougée",
        conseil = "Une vitesse d'au moins 1/(2 × focale).", mesure = true },
}

local function constater(photo)
    return Commandes.executer('carnet', { action = 'constater', photo = photo, vocabulaire = VOCABULAIRE,
        vue = { cherches = { 'flou' }, defauts = { { code = 'flou', mesure = 9, texte = "flou : 9" } } } })
end

local function proposer()
    return Commandes.executer('notation', { action = 'proposer', propositions = Json.tableau({
        { photo = 1, note = 3, drapeau = 'aucun', criteres = { impact = "Arrête l'œil", qualites = "Lumière", plancher = "Nette" },
            raison = "Sujet clair." } }) })
end

local function poserPointeur(dossier)
    S.fichiers[LOCALE .. '/dossier-commun.json'] = Json.encode({ format = 1, dossier = dossier })
end

-- Aucun fichier de données sous la racine locale ni sous le dossier absent.
local function rienEcrit()
    for chemin in pairs(S.fichiers) do
        local nom = chemin:sub(1, #LOCALE + 1) == LOCALE .. '/' and chemin:sub(#LOCALE + 2):match('^[^/]+')
        if nom and Chemins.estDonnee(nom) then
            error("écrit dans la racine locale : " .. chemin, 2)
        end
        if chemin:sub(1, #ABSENT) == ABSENT then
            error("écrit sous le dossier absent : " .. chemin, 2)
        end
    end
end

test("sans dossier commun : carnet et notation dans la racine locale, comme avant", function()
    photoRaw()
    constater(1)
    egal(Carnet.fichier(), LOCALE .. '/carnet.json')
    egal(S.fichiers[LOCALE .. '/carnet.json'] ~= nil, true)
    proposer()
    egal(S.fichiers[LOCALE .. '/notation.json'] ~= nil, true)
end)

test("dossier commun réglé : carnet et notation y vont, rien dans la racine locale ; le jeton reste local", function()
    import('LrFileUtils').createAllDirectories(COMMUN)
    poserPointeur(COMMUN)
    photoRaw()
    constater(1)
    proposer()
    egal(S.fichiers[COMMUN .. '/carnet.json'] ~= nil, true, "carnet.json dans le dossier commun")
    egal(S.fichiers[COMMUN .. '/notation.json'] ~= nil, true, "notation.json dans le dossier commun")
    egal(S.fichiers[LOCALE .. '/carnet.json'], nil)
    egal(S.fichiers[LOCALE .. '/notation.json'], nil)
    egal(Carnet.nombre(), 1)
    egal(select(2, Liaison.cheminJeton()):sub(1, #LOCALE), LOCALE, "jeton local")
    egal(Chemins.etapes(), COMMUN .. '/Etapes')
end)

test("dossier commun réglé après coup : le carnet chargé de la racine locale n'y est jamais écrit, il se relit du dossier commun", function()
    photoRaw()
    constater(1)
    egal(Carnet.nombre(), 1)
    import('LrFileUtils').createAllDirectories(COMMUN)
    poserPointeur(COMMUN)
    egal(Carnet.nombre(), 0, "relu du dossier commun (vide)")
    photoJpeg()
    constater(2)
    local relu = Json.decode(S.fichiers[COMMUN .. '/carnet.json'])
    local n = 0
    for _, c in pairs(relu.catalogues) do
        for _ in pairs(c.photos) do n = n + 1 end
    end
    egal(n, 1, "seulement la photo constatée avec le dossier commun")
end)

test("dossier commun introuvable : carnet, notation et étapes refusés avec le message, rien d'écrit nulle part", function()
    poserPointeur(ABSENT)
    photoRaw()
    echoue(function() constater(1) end, MESSAGE)
    echoue(proposer, MESSAGE)
    echoue(function() Commandes.executer('carnet', { action = 'lire' }) end, MESSAGE)
    echoue(Chemins.etapes, MESSAGE)
    rienEcrit()
end)

test("dossier commun introuvable : une notation chargée avant reste refusée en écriture (jamais la racine locale)", function()
    photoRaw()
    proposer()
    S.fichiers[LOCALE .. '/notation.json'] = nil
    poserPointeur(ABSENT)
    echoue(proposer, MESSAGE)
    rienEcrit()
end)

test("pendant le changement du dossier commun (Chemins.changement) : toute commande sauf ping est refusée, rien n'est écrit ; puis tout reprend", function()
    S.fichiers[LOCALE .. '/dossier-commun.json'] = nil
    S.fichiers[LOCALE .. '/carnet.json'] = nil
    photoRaw()
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    S.envois = {}
    Chemins.changement = true
    Liaison.recevoir(A.ligne({ id = 21, command = 'carnet', params = { action = 'constater', photo = 1, vocabulaire = VOCABULAIRE,
        vue = { cherches = { 'flou' }, defauts = { { code = 'flou', mesure = 9, texte = "flou : 9" } } } } }))
    Liaison.recevoir(A.ligne({ id = 22, command = 'ping', params = {} }))
    Chemins.changement = false
    local refus = Json.decode(S.envois[1])
    egal(refus.id, 21)
    egal(refus.error, Liaison.CHANGEMENT_DOSSIER)
    egal(S.fichiers[LOCALE .. '/carnet.json'], nil, "rien d'écrit pendant le changement")
    egal(Json.decode(S.envois[2]).error, nil, "ping répond")
    -- Le changement fini : la même commande passe.
    Liaison.recevoir(A.ligne({ id = 23, command = 'carnet', params = { action = 'constater', photo = 1, vocabulaire = VOCABULAIRE,
        vue = { cherches = { 'flou' }, defauts = { { code = 'flou', mesure = 9, texte = "flou : 9" } } } } }))
    Liaison.prise = nil
    egal(Json.decode(S.envois[3]).error, nil)
    egal(S.fichiers[LOCALE .. '/carnet.json'] ~= nil, true)
end)

A.bilan()
