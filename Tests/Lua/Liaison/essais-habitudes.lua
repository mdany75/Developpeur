-- essais-habitudes.lua : la lecture des habitudes (1.6, Lecture.habitudes, commande habitudes),
-- hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : liste (cible exigée, note,
-- 5000 au plus, dates refusées au-delà de 5000), lire (250 au plus, rien d'écrit, une lecture des
-- réglages par photo, clés de Claude dans l'espace de etatSimple, reprises de Dany, copie virtuelle
-- avec la mémoire de son original ou retouchée ensuite par Claude, redressement de Claude, Essais,
-- vidéos).
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue, contient = A.test, A.egal, A.echoue, A.contient
local photoRaw, photoFuji, appliquer = A.photoRaw, A.photoFuji, A.appliquer

local Json = require 'Json'
local Commandes = require 'Commandes'

local CLES = { 'Exposure2012', 'Highlights2012', 'Vibrance', 'Shadows2012', '#MaskGroupBasedCorrections', 'Look.Name',
    'CameraProfile', 'ProcessVersion', 'CleInconnue' }

local function lire(ids)
    return Commandes.executer('habitudes', { mode = 'lire', photos = ids, cles = CLES })
end

local function ensemble(liste)
    local e = {}
    for _, v in ipairs(liste or {}) do e[v] = true end
    return e
end

-- Une photo notée, de Dany seul (aucune mémoire de Claude).
local function photoNotee(id, note, reglages, meta, brut)
    local m = meta or {}
    m.cameraModel = m.cameraModel or 'X-H2S'
    local b = brut or {}
    b.rating = note
    b.fileFormat = b.fileFormat or 'RAW'
    b.isoSpeedRating = b.isoSpeedRating or 640
    b.dateTimeOriginal = b.dateTimeOriginal or 804565800
    return S.Photo(id, reglages or { Highlights2012 = -30, ProcessVersion = '15.4' }, m, b)
end

test("habitudes lire : les valeurs demandées d'une photo de Dany, sans rien écrire, une seule lecture des réglages", function()
    local photo = photoNotee(11, 5, { Highlights2012 = -30, Vibrance = 12, ProcessVersion = '15.4', Temperature = 5200 })
    local r = lire({ 11 })
    egal(#r.photos, 1)
    local p = r.photos[1]
    egal(p.id, 11)
    egal(p.appareil, 'X-H2S')
    egal(p.iso, 640)
    egal(p.jour, '2026-07-01')
    egal(p.format, 'RAW')
    egal(p.valeurs.Highlights2012, -30)
    egal(p.valeurs.Vibrance, 12)
    egal(p.valeurs.ProcessVersion, '15.4')
    egal(p.valeurs.Temperature, nil, "seulement les clés demandées")
    egal(p.valeurs.CleInconnue, nil, "une clé inconnue est ignorée")
    egal(p.valeurs['#MaskGroupBasedCorrections'], 0)
    egal(#p.claude, 0)
    egal(#p.reprises, 0)
    egal(p.essai, false)
    egal(p.memoire_autre, false)
    egal(#S.ecritures, 0, "aucune écriture")
    egal(S.ecrituresPrivees, 0, "aucune écriture privée")
    egal(photo.lecturesReglages, 1, "un seul getDevelopSettings")
    egal(#r.introuvables, 0)
    egal(#lire({ 999 }).introuvables, 1)
end)

test("habitudes lire : les masques et le Look posés par Claude sont à Claude (clés de etatSimple), pas Amelioration", function()
    local photo = photoFuji()
    photo.brut.rating = 4
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.3 } })
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'radial', centre_x = 0.5, centre_y = 0.5, rayon_x = 0.4,
        nom = 'Claude · r', locaux = { Exposure = 0.2 } } }) })
    -- Une clé de la mémoire qui n'est pas un réglage.
    local avant = Json.decode(photo.proprietes.avantClaude)
    avant.Amelioration = { denoise = 0 }
    avant.Look = A.ADOBE_COLOR
    photo.proprietes.avantClaude = Json.encode(avant)
    local ecritures = #S.ecritures
    local p = lire({ 4 }).photos[1]
    local claude = ensemble(p.claude)
    egal(claude['#MaskGroupBasedCorrections'], true, "les masques de Claude, sous la clé que lit etatSimple")
    egal(claude.MaskGroupBasedCorrections, nil)
    egal(claude['Look.Name'], true)
    egal(claude.Look, nil)
    egal(claude.Exposure2012, true)
    egal(claude.Amelioration, nil, "pas un réglage")
    egal(p.valeurs['#MaskGroupBasedCorrections'], 1)
    egal(#S.ecritures, ecritures, "la lecture n'écrit rien")
end)

test("habitudes lire : une reprise de Dany depuis la dernière retouche de Claude est rendue", function()
    local photo = photoRaw()
    photo.brut.rating = 4
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.5, Vibrance = 10 } })
    S.ecritureEnCours = true
    photo:applyDevelopSettings({ Vibrance = 4 })
    S.ecritureEnCours = false
    local avant = photo.lecturesReglages
    local p = lire({ 1 }).photos[1]
    local reprises = ensemble(p.reprises)
    egal(reprises.Vibrance, true)
    egal(reprises.Exposure2012, nil)
    egal(ensemble(p.claude).Vibrance, true)
    egal(photo.lecturesReglages - avant, 1, "les corrections se lisent sur les réglages déjà lus")
end)

test("habitudes lire : une copie virtuelle qui porte la mémoire de son original garde les clés de Claude, sans reprises", function()
    local original = photoRaw()
    S.active = original
    appliquer({ reglages = { Exposure2012 = 0.5 } })
    S.ecritureEnCours = true
    original:applyDevelopSettings({ Exposure2012 = 0.9 })
    S.ecritureEnCours = false
    local copie = S.copieVirtuelle(original, 7, 'Copie 1')
    copie.brut.rating = 4
    local p = lire({ 7 }).photos[1]
    egal(p.memoire_autre, true)
    egal(p.virtuelle, true)
    egal(p.copie, 'Copie 1')
    egal(ensemble(p.claude).Exposure2012, true, "ses réglages viennent de l'original retouché par Claude")
    egal(#p.reprises, 0, "pas de reprise lue dans la mémoire d'une autre photo")
    -- L'original, lui, a sa reprise.
    egal(ensemble(lire({ 1 }).photos[1].reprises).Exposure2012, true)
end)

test("habitudes lire : une copie virtuelle retouchée ensuite par Claude garde aussi les clés de Claude de son original", function()
    local original = photoRaw()
    S.active = original
    appliquer({ reglages = { Highlights2012 = -40 } })
    local copie = S.copieVirtuelle(original, 8, 'Copie 1')
    copie.brut.rating = 4
    S.active = copie
    appliquer({ photos = { 8 }, reglages = { Exposure2012 = 0.3 } })
    local avantCopie = Json.decode(copie.proprietes.avantClaude)
    egal(avantCopie.Highlights2012, nil, "la mémoire de la copie ne garde que sa propre retouche")
    local p = lire({ 8 }).photos[1]
    egal(p.memoire_autre, false, "la copie a sa propre mémoire")
    local claude = ensemble(p.claude)
    egal(claude.Exposure2012, true)
    egal(claude.Highlights2012, true, "le −40 hérité de l'original est de Claude")
    -- Une copie sans aucune mémoire, d'un original retouché par Claude : les clés de l'original.
    local nue = S.copieVirtuelle(original, 9, 'Copie 2')
    nue.proprietes = {}
    egal(ensemble(lire({ 9 }).photos[1].claude).Highlights2012, true)
    -- Une copie d'une photo jamais retouchée par Claude n'a aucune clé de Claude.
    local autre = photoNotee(30, 4)
    S.copieVirtuelle(autre, 31, 'Copie 1')
    egal(#lire({ 31 }).photos[1].claude, 0)
end)

test("habitudes lire : un redressement de Claude est à Claude sous les clés du recadrage, valeurs lues", function()
    local photo = photoFuji()
    photo.brut.rating = 4
    S.active = photo
    appliquer({ recadrage = { angle = 1.2 } })
    local p = Commandes.executer('habitudes', { mode = 'lire', photos = { photo.localIdentifier },
        cles = { 'CropAngle', 'CropLeft', 'CropTop', 'CropRight', 'CropBottom' } }).photos[1]
    egal(ensemble(p.claude).CropAngle, true, "le redressement de Claude")
    egal(type(p.valeurs.CropAngle), 'number', "la valeur se lit (le serveur en tire « recadrée »)")
end)

test("habitudes lire : une photo d'Essais (ou dont l'original y est) est marquée ; une vidéo n'est pas lue", function()
    local original = photoNotee(20, 4)
    local copie = S.copieVirtuelle(original, 21, 'Essai')
    local essais = S.Collection('Essais', S.Ensemble('Développeur'))
    essais.membres[original] = true
    local video = photoNotee(22, 4, {}, nil, { fileFormat = 'VIDEO' })
    local r = lire({ 20, 21, 22 })
    egal(r.photos[1].essai, true)
    egal(r.photos[2].essai, true, "son original est dans Essais")
    egal(r.photos[3].video, true)
    egal(r.photos[3].valeurs, nil)
    egal(video.lecturesReglages, nil, "aucune lecture des réglages d'une vidéo")
end)

test("habitudes lire : 250 photos au plus, mode inconnu refusé", function()
    local ids = {}
    for i = 1, 251 do ids[i] = i end
    echoue(function() lire(ids) end, "250 photos au plus")
    echoue(function() Commandes.executer('habitudes', { mode = 'tout' }) end, "mode « liste » ou « lire »")
end)

test("habitudes liste : une cible exigée, la note minimale, 5000 au plus, les dates refusées au-delà de 5000", function()
    echoue(function() Commandes.executer('habitudes', { mode = 'liste', note_min = 4 }) end, "une collection, un dossier ou un appareil")
    photoNotee(1, 5)
    photoNotee(2, 3)
    photoNotee(3, 4, nil, { cameraModel = 'X-T20' })
    local r = Commandes.executer('habitudes', { mode = 'liste', note_min = 4, appareil = 'X-H2S' })
    egal(r.total, 1)
    egal(r.photos[1], 1)
    egal(Commandes.executer('habitudes', { mode = 'liste', appareil = 'X-T20' }).total, 1, "4 ★ par défaut")
    for i = 10, 5010 do
        photoNotee(i, 4)
    end
    r = Commandes.executer('habitudes', { mode = 'liste', note_min = 4, appareil = 'X-H2S', limite = 9000 })
    egal(r.total, 5002)
    egal(#r.photos, 5000, "5000 au plus")
    echoue(function()
        Commandes.executer('habitudes', { mode = 'liste', note_min = 4, appareil = 'X-H2S', date_debut = '2026-01-01' })
    end, "plus que 5000")
    egal(#S.ecritures, 0)
end)

A.bilan()
