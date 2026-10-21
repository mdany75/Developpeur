-- essais-lecon.lua : la leçon de la photo (1.3) côté liaison, hors de Lightroom (LuaJIT, Lightroom
-- simulé par Simulation.lua) : le journal détaillé que lit photo_lesson (commande journal avec
-- detaille : la photo décrite en entier, prise_de_vue_plus lu clé par clé), la forme des entrées
-- du journal que lisent les corrections nettes du serveur (Lecon.correctionsNettes), et la leçon
-- telle que le serveur l'envoie (Lecon.pourLeModule, même texte JSON que LeconTests.swift), rangée
-- par la commande lecon. Rien n'est écrit dans le catalogue.
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, echoue, contient, ligne = A.test, A.egal, A.echoue, A.contient, A.ligne
local photoRaw, photoFuji, appliquer = A.photoRaw, A.photoFuji, A.appliquer

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Carnet = require 'Carnet'

-- Complément de la simulation, pour cet essai : l'heure locale de LrDate.timeToUserFormat pour
-- tout format (comme dans essais-registre.lua).
local LrDate = import 'LrDate'
LrDate.timeToUserFormat = function(t, format)
    return os.date('!' .. format, 978307200 + math.floor(t) + S.fuseau)
end

-- Une photo prise avec un X-H2S, décrite comme Lightroom le ferait (métadonnées formatées), avec
-- les quatre données de prise de vue de plus. Leur forme dans Lightroom Classic 15.6 reste à
-- constater (mesure 3) : la simulation les rend telles quelles.
local function photoDecrite()
    local photo = photoFuji()
    photo.meta.copyName = nil
    photo.meta.lens = 'XF16-55mmF2.8 R LM WR'
    photo.meta.isoSpeedRating = 'ISO 400'
    photo.meta.shutterSpeed = '1/250 s'
    photo.meta.aperture = 'ƒ/8,0'
    photo.meta.focalLength = '23 mm'
    photo.meta.dateTimeOriginal = '2026-06-30 18:42:10'
    photo.meta.exposureBias = '-0,7 IL'
    photo.meta.flash = "Le flash ne s'est pas déclenché"
    photo.meta.exposureProgram = 'Priorité ouverture'
    photo.meta.meteringMode = 'Multizone'
    S.active = photo
    return photo
end

local function journal(params)
    return Commandes.executer('journal', params).photos[1]
end

-- Journal détaillé ------------------------------------------------------------------------------

test("journal detaille : la photo décrite en entier, avec prise_de_vue_plus, et ses entrées ; rien n'est écrit", function()
    local photo = photoDecrite()
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } }, raison = "Un peu sombre." })
    local ecritures, privees, groupees = #S.ecritures, S.ecrituresPrivees, S.lecturesGroupees
    local j = journal({ photos = { photo.localIdentifier }, detaille = true })
    egal(#S.ecritures, ecritures, "aucune écriture au catalogue")
    egal(S.ecrituresPrivees, privees, "pas même une écriture privée")
    egal(S.lecturesGroupees, groupees, "lues une à une, jamais par une lecture groupée")
    local d = j.photo
    egal(d.id, 4)
    egal(d.fichier, 'XH2S0320.RAF')
    egal(d.appareil, 'X-H2S')
    egal(d.objectif, 'XF16-55mmF2.8 R LM WR')
    egal(d.iso, 'ISO 400')
    egal(d.vitesse, '1/250 s')
    egal(d.ouverture, 'ƒ/8,0')
    egal(d.focale, '23 mm')
    egal(d.date, '2026-06-30 18:42:10')
    egal(d.format, 'RAW')
    egal(d.retouchee_par_claude, true)
    egal(d.prise_de_vue_plus.compensation, '-0,7 IL')
    egal(d.prise_de_vue_plus.flash, "Le flash ne s'est pas déclenché")
    egal(d.prise_de_vue_plus.programme, 'Priorité ouverture')
    egal(d.prise_de_vue_plus.mesure, 'Multizone')
    egal(#j.entrees, 1)
    egal(j.entrees[1].raison, "Un peu sombre.")
    -- Par la prise de la liaison : detaille arrive en booléen JSON.
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 5, command = 'journal', params = { detaille = true } }))
    Liaison.prise = nil
    local reponse = Json.decode(S.envois[#S.envois])
    egal(reponse.error, nil)
    egal(reponse.result.photos[1].photo.appareil, 'X-H2S', "la photo active, décrite en entier")
    egal(reponse.result.photos[1].photo.prise_de_vue_plus.mesure, 'Multizone')
end)

test("journal sans detaille : la description courte d'avant, sans prise de vue", function()
    local photo = photoDecrite()
    local d = journal({ photos = { photo.localIdentifier } }).photo
    local cles = {}
    for cle in pairs(d) do
        cles[#cles + 1] = cle
    end
    table.sort(cles)
    egal(table.concat(cles, ','), 'copie_virtuelle,fichier,id')
    egal(journal({ detaille = false }).photo.appareil, nil, "detaille = false : courte aussi")
    egal(journal({ detaille = 'oui' }).photo.prise_de_vue_plus, nil, "seul le booléen vrai compte")
end)

test("journal detaille : une clé que Lightroom refuse, vide ou d'un autre type ne gêne pas les autres", function()
    local photo = photoDecrite()
    local lire = photo.getFormattedMetadata
    photo.meta.exposureProgram = ''
    photo.meta.meteringMode = { 'pas un texte' }
    photo.getFormattedMetadata = function(self, cle)
        if cle == 'flash' then
            error("getFormattedMetadata : clé inconnue flash", 2)
        end
        return lire(self, cle)
    end
    local d = journal({ detaille = true }).photo
    egal(d.appareil, 'X-H2S')
    egal(d.prise_de_vue_plus.compensation, '-0,7 IL')
    egal(d.prise_de_vue_plus.flash, nil, "refusée : nil")
    egal(d.prise_de_vue_plus.programme, nil, "vide : nil")
    egal(d.prise_de_vue_plus.mesure, nil, "une table n'est pas gardée")
    -- Toutes refusées ou absentes : pas de prise_de_vue_plus du tout.
    photo.meta.exposureBias = nil
    egal(journal({ detaille = true }).photo.prise_de_vue_plus, nil)
    egal(Json.encode(journal({ detaille = true }).photo):find('prise_de_vue_plus', 1, true), nil)
end)

-- Ce que lisent les corrections nettes ----------------------------------------------------------

test("journal : la forme des entrées que lit Lecon.correctionsNettes (retouche, annulation de son nom, retour)", function()
    photoDecrite()
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } }, etape = 'passe 1' })
    appliquer({ reglages = { Exposure2012 = 0.9, Vibrance = 12 }, plages = { Exposure2012 = { -5, 5 }, Vibrance = { -100, 100 } },
        etape = 'passe 2' })
    Commandes.executer('annuler', {})
    Commandes.executer('revenir', {})
    local e = journal({ detaille = true }).entrees
    egal(#e, 4)
    egal(e[1].type, 'retouche')
    egal(e[1].etape, 'Claude · passe 1')
    egal(e[1].changements[1].cle, 'Exposure2012')
    egal(e[1].changements[1].avant, 0)
    egal(e[1].changements[1].apres, 0.4)
    egal(e[2].etape, 'Claude · passe 2')
    egal(e[3].type, 'annulation')
    egal(e[3].etape, 'Annulation de « ' .. e[2].etape .. ' »', "le nom de l'étape défaite, entre « »")
    egal(#e[3].changements, 0)
    egal(e[4].type, 'retour')
    egal(#e[4].changements, 0)
end)

-- La leçon du serveur, rangée ------------------------------------------------------------------

-- Lecon.pourLeModule, mot pour mot (LeconTests.contratModule) : les deux suites vérifient la même
-- forme, l'une la produit, l'autre la range.
local CONTRAT = [[{"points":[{"axe":"lumiere","manque":"Le ciel était brûlé : 3 % des pixels écrêtés au départ.","prise_de_vue":"Exposer pour le ciel : −2/3 IL de compensation.","defauts":[{"code":"ciel_brule","libelle":"Ciel ou haut de l'image brûlé"}]},{"axe":"couleur","prise_de_vue":"Balance des blancs juste à la prise de vue : à refaire.","defauts":[]},{"axe":"composition","manque":"L'horizon penchait de 1,8°.","prise_de_vue":"Afficher le niveau électronique du viseur.","defauts":[{"code":"horizon_penche","libelle":"Horizon ou ligne penchée"}]}],"indices":[{"code":"horizon_penche","axe":"composition","libelle":"Horizon ou ligne penchée","preuve":"Recadrage : angle −1,8° (0,0 → −1,8)"}]}]]

test("lecon garder : la leçon telle que le serveur l'envoie est rangée, sans écriture au catalogue, même en pause", function()
    local photo = photoRaw()
    photo.brut.dateTimeOriginal = 804565800
    S.fuseau = -4 * 3600
    Liaison.pause = true
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    -- Comme le serveur : la ligne JSON entière, décodée par la liaison.
    Liaison.recevoir('{"id":12,"command":"lecon","jeton":"' .. A.JETON .. '","params":{"action":"garder","photo":1,"lecon":' .. CONTRAT .. '}}')
    Liaison.prise = nil
    local reponse = Json.decode(S.envois[#S.envois])
    egal(reponse.error, nil)
    egal(reponse.result.rangee, true)
    egal(reponse.result.fichier, 'DSC_0412.NEF')
    egal(reponse.result.mois, '2026-06', "le mois que le serveur rend à Claude")
    egal(#S.ecritures, ecritures, "rien dans le catalogue")
    egal(S.ecrituresPrivees, privees)
    local l = Carnet.lecon(1)
    egal(l.points[1].axe, 'lumiere')
    egal(l.points[1].defauts[1].code, 'ciel_brule')
    egal(l.points[2].manque, nil, "rien ne manquait")
    egal(#l.points[2].defauts, 0)
    egal(l.points[3].prise_de_vue, "Afficher le niveau électronique du viseur.")
    egal(table.concat(l.defauts, ','), 'ciel_brule,horizon_penche')
    egal(l.indices[1].preuve, "Recadrage : angle −1,8° (0,0 → −1,8)")
    egal(l.indices[1].axe, 'composition')
    egal(contient(Liaison.journal, "Leçon rangée : DSC_0412.NEF"), true)
end)

test("journal detaille (read_facts) ne range rien au carnet ; une leçon sans ses trois points est refusée", function()
    local photo = photoDecrite()
    local version = Carnet.version
    journal({ photos = { photo.localIdentifier }, detaille = true })
    egal(Carnet.version, version, "read_facts (journal seul) ne range rien")
    egal(Carnet.nombre(), 0)
    local deux = Json.decode(CONTRAT)
    table.remove(deux.points)
    echoue(function() Commandes.executer('lecon', { action = 'garder', photo = 4, lecon = deux }) end, "trois points")
    egal(Carnet.nombre(), 0)
end)

A.bilan()
