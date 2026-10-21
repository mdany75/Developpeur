-- essais-etapes.lua : « Pourquoi ? » côté liaison (1.3), hors de Lightroom (LuaJIT, Lightroom
-- simulé par Simulation.lua) : l'identité des étapes (etape_id dans la mémoire, le journal et les
-- réponses ; recadrer, annuler, revenir, mémoire de la 1.2) et l'avant/après gardé par Etapes.lua
-- autour des commandes (Liaison.recevoir), sans aucune écriture dans le catalogue : la vue de
-- view_photo, l'avant rendu quand aucune vue ne correspond, les conditions (photo active, une
-- photo, fenêtre, case, refus, classement, série), l'attente d'une capture, une photo changée
-- pendant le rendu, les calculs IA en attente, l'empreinte, la commande etapes, le ménage et
-- Init.lua.
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).
--
-- Compléments de la simulation, ici seulement (Simulation.lua n'est pas touché) :
--   - chaque rendu d'aperçu écrit son fichier (« JPEG n°k (Exposure2012 v) ») et appelle le
--     crochet pendantRendu ;
--   - enTaches(f) fait tourner les tâches de Lightroom (LrTasks.startAsyncTask) comme des
--     coroutines, LrTasks.sleep rendant la main : deux commandes s'y croisent comme dans Lightroom.

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local S = require 'Simulation'

-- Rendus d'aperçu : le fichier rendu existe (contenu lisible), et un crochet peut agir pendant le
-- rendu. Posé avant le chargement des modules (Rendu garde LrExportSession à son chargement).
local importer = import
local exporter = importer('LrExportSession')
local numeroRendu = 0
local pendantRendu = nil
local function exportEssai(args)
    local session = exporter(args)
    local renditions = session.renditions
    session.renditions = function(self)
        local suivant = renditions(self)
        return function()
            local i, rendu = suivant()
            if not i then
                return nil
            end
            local attendre = rendu.waitForRender
            rendu.waitForRender = function(r)
                if pendantRendu then
                    pendantRendu(args)
                end
                local ok, chemin = attendre(r)
                if ok and args.exportSettings.LR_collisionHandling ~= 'rename' then
                    numeroRendu = numeroRendu + 1
                    S.fichiers[chemin] = string.format('JPEG n°%d (Exposure2012 %s)', numeroRendu, tostring(args.reglagesRendus.Exposure2012))
                    S.datesFichiers[chemin] = S.horloge
                end
                return ok, chemin
            end
            return i, rendu
        end
    end
    return session
end
import = function(nom)
    if nom == 'LrExportSession' then
        return exportEssai
    end
    return importer(nom)
end

local A = require 'Aides'
local test, egal, echoue, contient, ligne = A.test, A.egal, A.echoue, A.contient, A.ligne
local photoRaw, photoFuji, appliquer = A.photoRaw, A.photoFuji, A.appliquer

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Etapes = require 'Etapes'
local Ecriture = require 'Ecriture'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Geometrie = require 'Geometrie'
local Recadrage = require 'Recadrage'
local LrTasks = import 'LrTasks'

-- Chaque essai repart sans prise des réponses ni crochet de rendu (A.test remet la simulation, la
-- liaison et Etapes à zéro).
local function essai(nom, fonction)
    test(nom, function()
        numeroRendu = 0
        pendantRendu = nil
        local ok, erreur = pcall(fonction)
        pendantRendu = nil
        Liaison.prise, Liaison.reponsesConnectee = nil, false
        if not ok then
            error(erreur, 0)
        end
    end)
end

-- Aides ------------------------------------------------------------------------------------------

local function priseDesReponses()
    Liaison.prise = { send = function(_, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
end

local function reponse(i)
    return Json.decode(S.envois[i or #S.envois])
end

local function envoyer(id, commande, params)
    Liaison.recevoir(ligne({ id = id, command = commande, params = params or {} }))
end

local function exposer(valeur, extra)
    local params = { reglages = { Exposure2012 = valeur }, plages = { Exposure2012 = { -5, 5 } }, confirme = true, etape = 'passe 1',
        raison = "Ciel trop sombre." }
    for cle, v in pairs(extra or {}) do
        params[cle] = v
    end
    return params
end

-- La fenêtre Claude ouverte (Etapes.actifPour), la photo active, la prise des réponses.
local function enFenetre(photo)
    S.active, S.selection = photo, { photo }
    Etapes.actifPour = function() return true end
    priseDesReponses()
    return photo
end

local function dossierDe(photo)
    return Chemins.etapes() .. '/' .. photo.brut.uuid
end

local function fichier(photo, nom)
    return S.fichiers[dossierDe(photo) .. '/' .. nom]
end

local function etatDe(photo, id)
    local texte = fichier(photo, id .. '.json')
    return texte and Json.decode(texte) or nil
end

-- Fichiers rangés sous Etapes/, en nombre.
local function fichiersEtapes()
    local n, racine = 0, Chemins.etapes() .. '/'
    for chemin, contenu in pairs(S.fichiers) do
        if chemin:sub(1, #racine) == racine and contenu ~= 'dossier' then
            n = n + 1
        end
    end
    return n
end

local function nomsAppliques(photo)
    local noms = {}
    for _, a in ipairs(photo.appliques) do
        noms[#noms + 1] = tostring(a.nom or a.preset)
    end
    return table.concat(noms, ' | ')
end

-- Les tâches de Lightroom en coroutines : LrTasks.startAsyncTask lance la tâche jusqu'à sa
-- première attente ; LrTasks.sleep rend la main. Après `fonction`, les tâches suspendues tournent
-- chacune à son tour jusqu'à la fin.
local function enTaches(fonction)
    local demarrer, dormir = LrTasks.startAsyncTask, LrTasks.sleep
    local taches, estTache = {}, {}
    local function reprendre(co)
        local ok, erreur = coroutine.resume(co)
        if not ok then
            error(erreur, 0)
        end
    end
    LrTasks.startAsyncTask = function(f)
        local co = coroutine.create(f)
        taches[#taches + 1] = co
        estTache[co] = true
        reprendre(co)
    end
    LrTasks.sleep = function(secondes)
        dormir(secondes)
        local co = coroutine.running()
        if co and estTache[co] then
            coroutine.yield()
        end
    end
    local ok, erreur = pcall(fonction)
    local tours = 0
    while ok and tours < 10000 do
        tours = tours + 1
        local vivantes = false
        for _, co in ipairs(taches) do
            if coroutine.status(co) == 'suspended' then
                vivantes = true
                local bon, err = coroutine.resume(co)
                if not bon then
                    ok, erreur = false, err
                end
            end
        end
        if not vivantes then
            break
        end
    end
    LrTasks.startAsyncTask, LrTasks.sleep = demarrer, dormir
    if not ok then
        error(erreur, 0)
    end
end

-- Identité des étapes ------------------------------------------------------------------------------

essai("étapes : un id unique par étape (appliquer, masquer, retoucher, metadonnees), au journal et dans la réponse ; sans étape, null", function()
    local photo = photoFuji()
    S.active = photo
    local ids, vus = {}, {}
    local function noter(resultat, quoi, genre)
        local id = resultat.resultats[1].etape_id
        egal(type(id), 'string', quoi .. " : etape_id")
        egal(id:match('^[%x]+%-[%x]+%-%d+$') ~= nil, true, quoi .. " : un id fait pour un nom de fichier (" .. id .. ")")
        egal(vus[id], nil, quoi .. " : id unique")
        vus[id] = true
        ids[#ids + 1] = id
        local etapes = Json.decode(photo.proprietes.etapesClaude)
        egal(etapes[#etapes].id, id, quoi .. " : dans la mémoire")
        egal(type(etapes[#etapes].le), 'number', quoi .. " : heure de l'étape")
        local journal = Json.decode(photo.proprietes.journalClaude)
        egal(journal[#journal].etape_id, id, quoi .. " : au journal")
        egal(journal[#journal].type, genre, quoi .. " : type de l'entrée")
    end
    noter(appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } }, raison = "Ciel trop sombre." }), "appliquer", 'retouche')
    local rien = appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } } })
    egal(rien.resultats[1].etape_id, Json.null, "rien n'a changé : pas d'étape, etape_id null")
    egal(#Json.decode(photo.proprietes.etapesClaude), 1)
    noter(Commandes.executer('masquer', { masques = Json.tableau({ { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4,
        nom = 'Claude · Dégradé', locaux = { LocalExposure2012 = -0.2 } } }), etape = 'ciel' }), "masquer", 'retouche')
    noter(Commandes.executer('retoucher', { taches = { { x = 0.5, y = 0.5, rayon = 0.01 } }, yeux = {}, etape = 'tache' }), "retoucher", 'retouche')
    noter(Commandes.executer('metadonnees', { note = 3, etape = 'note' }), "metadonnees", 'classement')
    egal(#ids, 4)
    -- etape_id n'est pas un réglage : il ne part jamais dans applyDevelopSettings.
    for _, a in ipairs(photo.appliques) do
        egal(type(a.reglages) == 'table' and (a.reglages.etape_id or a.reglages.id) or nil, nil, "réglages écrits sans id d'étape")
    end
end)

essai("étapes : ameliorer, supprimer (reflets) et variantes choisir passent par nouvelleEtape ; rien de lancé, pas d'étape", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    local function verifier(id, quoi)
        egal(type(id), 'string', quoi .. " : etape_id")
        local etapes = Json.decode(photo.proprietes.etapesClaude)
        egal(etapes[#etapes].id, id, quoi .. " : dans la mémoire")
        local journal = Json.decode(photo.proprietes.journalClaude)
        egal(journal[#journal].etape_id, id, quoi .. " : au journal")
    end
    local debruite = Commandes.executer('ameliorer', { ameliorations = Json.tableau({ { nom = 'denoise', actif = true, intensite = 40 } }),
        etape = 'débruitage' })
    verifier(debruite.resultats[1].etape_id, "ameliorer")
    local reflets = Commandes.executer('supprimer', { reflets = { actif = true, intensite = 80, qualite = 'standard' }, etape = 'reflets' })
    verifier(reflets.resultats[1].etape_id, "supprimer")
    egal(reflets.resultats[1].etape_id ~= debruite.resultats[1].etape_id, true)
    local deja = Commandes.executer('supprimer', { reflets = { actif = true, intensite = 80 }, etape = 'encore' })
    egal(deja.resultats[1].etape_id, Json.null, "déjà l'état de la photo : pas d'étape")

    local brute = photoRaw()
    S.active, S.selection = brute, { brute }
    photo = brute
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.3, Temperature = 6200 }, libelles = {},
        etape = 'variante chaude', instantane = 'chaude', taille = 800 })
    local choix = Commandes.executer('variantes', { action = 'choisir', nom = 'chaude', etape = 'variante chaude' })
    verifier(choix.etape_id, "variantes choisir (réponse à plat)")
    egal(choix.photo.id, 1)
end)

essai("étapes : ameliorer et supprimer sans rien de lancé par Lightroom : mémoire remise, pas d'etape_id", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    -- Débruitage refusé par Lightroom, détails bruts imposés par la super résolution : rien ne part.
    photo.amelioration = { denoise = false, rawDetails = true, superRes = true, denoiseAmount = 50 }
    photo.ameliorationsRefusees = { denoise = true }
    local r = Commandes.executer('ameliorer', { ameliorations = Json.tableau({ { nom = 'denoise', actif = true, intensite = 30 },
        { nom = 'rawDetails', actif = false } }), etape = 'rien' })
    egal(#S.appelsAmelioration, 0, "rien de lancé")
    egal(r.resultats[1].etape_id, Json.null, "plus d'étape : pas d'etape_id")
    egal(photo.proprietes.etapesClaude, nil, "mémoire remise")
    -- Reflets : Lightroom refuse de lancer le calcul.
    local dc = import 'LrDevelopController'
    local basculer = dc.toggleReflectionRemoval
    dc.toggleReflectionRemoval = function() error("refusé", 0) end
    local ok, reflets = pcall(Commandes.executer, 'supprimer', { reflets = { actif = true, intensite = 80 }, etape = 'reflets' })
    dc.toggleReflectionRemoval = basculer
    egal(ok, true, tostring(reflets))
    egal(reflets.resultats[1].etape_id, Json.null)
    egal(photo.proprietes.etapesClaude, nil)
end)

local function grilleDe(deformation, empreinte)
    local n, m = 17, 12
    local x, y = Json.tableau(), Json.tableau()
    for j = 0, m - 1 do
        for i = 0, n - 1 do
            local a, b = deformation(i / (n - 1), j / (m - 1))
            x[#x + 1], y[#y + 1] = a, b
        end
    end
    return { colonnes = n, lignes = m, x = x, y = y, empreinte = empreinte }
end

essai("étapes : recadrer complète l'étape d'appliquer sous le même id ; annuler rend l'etape_id défait, au journal aussi", function()
    local photo = photoFuji()
    S.active = photo
    local r = appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie' }).resultats[1]
    egal(r.a_recadrer, true)
    local id = r.etape_id
    egal(type(id), 'string')
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    local recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) }
    local recadre = Commandes.executer('recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, recalages = recalages,
        completer = { 4 }, etape = r.etape, confirme = true })
    egal(recadre.resultats[1].etape_id, id, "l'étape complétée garde son id")
    local etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(#etapes, 1)
    egal(etapes[1].id, id)
    local journal = Json.decode(photo.proprietes.journalClaude)
    egal(#journal, 1, "une seule entrée")
    egal(journal[1].etape_id, id)

    local annulation = Commandes.executer('annuler', {})
    egal(annulation.resultats[1].annulee, true)
    egal(annulation.resultats[1].etape_id, id, "l'étape défaite, par son id")
    journal = Json.decode(photo.proprietes.journalClaude)
    egal(journal[#journal].type, 'annulation')
    egal(journal[#journal].etape_id, id, "l'annulation nomme l'étape défaite par son id")
end)

essai("étapes : une mémoire de la 1.2, sans id, s'annule toujours (etape_id null) ; recadrer lui donne un id ; revenir garde les ids défaits", function()
    local photo = photoRaw()
    S.active = photo
    photo.reglages.Exposure2012 = 0.5
    photo.proprietes.proprietaireMemoire = photo.brut.uuid
    photo.proprietes.avantClaude = Json.encode({ Exposure2012 = 0 })
    photo.proprietes.etapesClaude = Json.encode(Json.tableau({ { nom = 'Claude · ancienne', avant = { Exposure2012 = 0 } } }))
    photo.proprietes.journalClaude = Json.encode(Json.tableau({ { etape = 'Claude · ancienne', type = 'retouche', changements = Json.tableau() } }))
    local annulation = Commandes.executer('annuler', {})
    egal(annulation.resultats[1].annulee, true, "annulée comme avant")
    egal(annulation.resultats[1].etape_id, Json.null, "sans id")
    egal(photo.reglages.Exposure2012, 0)

    -- Une étape d'avant la 1.3, complétée par recadrer : elle reçoit un id.
    local journal = Json.tableau({ { etape = 'Claude · passe 1', type = 'retouche', changements = Json.tableau() } })
    photo.proprietes.etapesClaude = Json.encode(Json.tableau({ { nom = 'Claude · passe 1', avant = { Exposure2012 = 0 } } }))
    photo.proprietes.journalClaude = Json.encode(journal)
    local etapes = {}
    local plan = { photo = photo, avant = { Exposure2012 = 0 }, nouveaux = { Exposure2012 = 0.4 }, changements = Json.tableau({ { cle = 'Exposure2012', avant = 0, apres = 0.4 } }),
        notes = Json.tableau(), presets = {}, presetsApres = {} }
    Ecriture.completerEtapes({ plan }, 'Claude · passe 1', {}, {})
    etapes = Json.decode(photo.proprietes.etapesClaude)
    egal(#etapes, 1, "complétée, pas ajoutée")
    egal(type(etapes[1].id), 'string', "l'étape complétée reçoit un id")
    egal(plan.etapeId, etapes[1].id)
    egal(Json.decode(photo.proprietes.journalClaude)[1].etape_id, etapes[1].id, "son entrée du journal aussi")

    -- revenir : l'entrée « retour » garde les ids des étapes défaites (celles de la 1.3).
    local autre = A.photoJpeg()
    S.active = autre
    local a = appliquer({ reglages = { Exposure2012 = 0.3 }, plages = { Exposure2012 = { -5, 5 } } }).resultats[1].etape_id
    local b = appliquer({ reglages = { Exposure2012 = 0.6 }, plages = { Exposure2012 = { -5, 5 } }, etape = 'passe 2' }).resultats[1].etape_id
    Commandes.executer('revenir', {})
    local retour = Json.decode(autre.proprietes.journalClaude)
    retour = retour[#retour]
    egal(retour.type, 'retour')
    egal(table.concat(retour.etape_ids, ','), a .. ',' .. b, "les ids défaits, dans l'ordre")
end)

-- Avant/après d'une étape ----------------------------------------------------------------------

essai("Etapes : capture après une étape sur la photo active, sans écriture ; l'avant est la vue, l'après rendu après la réponse", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°1 (Exposure2012 0)', "la vue de view_photo est gardée (copie)")
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local envoisAuRendu, pendant
    pendantRendu = function()
        envoisAuRendu = #S.envois
        pendant = Etapes.captureId and Etapes.images(1, Etapes.captureId)
    end
    local versionAvant = Etapes.version
    envoyer(2, 'appliquer', exposer(0.5))
    local r = reponse()
    egal(r.id, 2)
    local id = r.result.resultats[1].etape_id
    egal(type(id), 'string', "etape_id dans la réponse")
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)', "l'avant est la copie de la vue")
    egal(fichier(photo, id .. '-apres.jpg'), 'JPEG n°2 (Exposure2012 0.5)', "l'après est rendu après l'écriture")
    egal(#S.rendus, 2, "un seul rendu pour l'étape : l'avant vient de la vue")
    egal(envoisAuRendu, 2, "l'après est rendu une fois la réponse partie")
    egal(pendant and pendant.etat, 'en_cours', "pendant la capture, la fenêtre lit « en préparation »")
    egal(pendant.avant, id .. '-avant.jpg', "l'avant déjà rangé")
    egal(#S.ecritures, ecritures + 1, "une seule écriture : l'étape de Claude")
    egal(S.ecritures[#S.ecritures], 'Claude · passe 1')
    egal(nomsAppliques(photo):find('comparaison', 1, true), nil, "pas d'étape « Claude · comparaison »")
    egal(S.ecrituresPrivees, privees + 1, "et l'état après Claude, comme avant (écriture privée)")
    egal(Etapes.version, versionAvant + 1, "la fenêtre voit la nouvelle image")
    local etat = etatDe(photo, id)
    egal(etat.etat, 'pret')
    egal(etat.etape, 'Claude · passe 1')
    egal(fichier(photo, 'prepare-1.jpg'), nil, "l'avant préparé est rangé sous l'id de l'étape")
    egal(contient(Liaison.journal, "Avant/après de « Claude · passe 1 » gardé en"), true, "noté dans module.log")
    -- L'étape suivante : son avant est l'après de la précédente, sans autre rendu.
    envoyer(3, 'appliquer', exposer(0.8, { etape = 'passe 2' }))
    local id2 = reponse().result.resultats[1].etape_id
    egal(fichier(photo, id2 .. '-avant.jpg'), 'JPEG n°2 (Exposure2012 0.5)', "l'avant de la suivante est l'après de la précédente")
    egal(fichier(photo, id2 .. '-apres.jpg'), 'JPEG n°3 (Exposure2012 0.8)')
    egal(#S.rendus, 3)
end)

essai("Etapes : avant rendu juste avant l'écriture quand aucune vue ne correspond (retouche à la main, ou pas de view_photo)", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    -- Une retouche à la main de l'utilisateur après view_photo.
    photo.reglages.Exposure2012 = 0.2
    photo:modifiee()
    local ecrituresAuRendu = {}
    pendantRendu = function() ecrituresAuRendu[#ecrituresAuRendu + 1] = #photo.appliques end
    local appliques = #photo.appliques
    envoyer(2, 'appliquer', exposer(0.7))
    local id = reponse().result.resultats[1].etape_id
    egal(#S.rendus, 3, "la vue, l'avant rendu, puis l'après")
    egal(S.rendus[2].reglagesRendus.Exposure2012, 0.2, "l'avant : les réglages d'avant l'écriture")
    egal(ecrituresAuRendu[1], appliques, "rendu avant l'écriture")
    egal(ecrituresAuRendu[2], appliques + 1, "l'après, une fois l'étape écrite")
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°2 (Exposure2012 0.2)')
    egal(fichier(photo, id .. '-apres.jpg'), 'JPEG n°3 (Exposure2012 0.7)')
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°2 (Exposure2012 0.2)', "l'avant rendu devient la vue")
    egal(contient(Liaison.journal, "état d'avant rendu avant l'écriture"), true)

    -- Sans view_photo du tout : de même.
    local autre = A.photoJpeg()
    enFenetre(autre)
    envoyer(3, 'appliquer', exposer(0.4))
    local id2 = reponse().result.resultats[1].etape_id
    egal(fichier(autre, id2 .. '-avant.jpg'), 'JPEG n°4 (Exposure2012 0)')
    egal(fichier(autre, id2 .. '-apres.jpg'), 'JPEG n°5 (Exposure2012 0.4)')
    egal(etatDe(autre, id2).etat, 'pret')
end)

essai("Etapes : rien pour plusieurs photos, une autre que l'active, fenêtre fermée, case décochée, refus (Proposer d'abord, pause), classement, série", function()
    local photo = enFenetre(photoRaw())
    local deuxieme = A.photoJpeg()
    -- apercus : les rendus de view_photo demandés dans le cas (les seuls permis).
    local function rien(quoi, fonction, apercus)
        local rendus, fichiers = #S.rendus, fichiersEtapes()
        fonction()
        egal(#S.rendus, rendus + (apercus or 0), quoi .. " : aucun rendu de plus")
        egal(fichiersEtapes(), fichiers, quoi .. " : aucun fichier sous Etapes/ (ni vue)")
    end
    -- Aucune vue : une capture rendrait l'avant, puis l'après.
    rien("deux photos", function() envoyer(1, 'appliquer', exposer(0.3, { photos = { 1, 2 } })) end)
    egal(reponse().result ~= nil, true, "la commande, elle, se fait")
    rien("une autre photo que l'active", function() envoyer(2, 'appliquer', exposer(0.4, { photos = { 2 } })) end)
    local fuji = photoFuji()
    rien("une autre photo que l'active, désignée par photo", function()
        envoyer(20, 'retoucher', { photo = 4, taches = { { x = 0.5, y = 0.5, rayon = 0.01 } }, yeux = {}, etape = 'tache', confirme = true })
    end)
    egal(type(reponse().result.resultats[1].etape_id), 'string', "la tache est posée sur la photo 4")
    egal(fuji.proprietes.etapesClaude ~= nil, true)
    rien("match_series (sans_avant_apres)", function() envoyer(3, 'appliquer', exposer(0.5, { sans_avant_apres = true })) end)
    rien("un classement", function() envoyer(4, 'metadonnees', { note = 2, etape = 'note', confirme = true }) end)
    S.prefs.mode = 'proposer'
    rien("Proposer d'abord sans accord", function() envoyer(5, 'appliquer', exposer(0.6, { confirme = false })) end)
    egal(reponse().error ~= nil, true, "refusée")
    S.prefs.accordDansLightroom = true
    rien("accord attendu dans Lightroom", function() envoyer(6, 'appliquer', exposer(0.6)) end)
    S.prefs.mode, S.prefs.accordDansLightroom = 'appliquer', false
    Liaison.pause = true
    rien("pause", function() envoyer(7, 'appliquer', exposer(0.6)) end)
    Liaison.pause = false
    S.prefs.avantApresEtapes = false
    rien("case Avant/après décochée", function()
        envoyer(8, 'apercu', { taille = 1568, cles = {} })
        envoyer(9, 'appliquer', exposer(0.7))
    end, 1)
    S.prefs.avantApresEtapes = nil
    Etapes.actifPour = function() return false end
    rien("fenêtre fermée et son Claude au repos (Claude Desktop seul)", function()
        envoyer(10, 'apercu', { taille = 1568, cles = {} })
        envoyer(11, 'appliquer', exposer(0.8))
    end, 1)
    Etapes.actifPour = function() error("fenêtre en erreur") end
    rien("crochet de la fenêtre en erreur", function() envoyer(12, 'appliquer', exposer(0.9)) end)
    egal(photo.reglages.Exposure2012, 0.9, "les commandes se sont faites")
    egal(deuxieme.reglages.Exposure2012, 0.4)
    -- Par défaut (case cochée, fenêtre ouverte), la même commande garde l'avant/après.
    Etapes.actifPour = function() return true end
    envoyer(13, 'appliquer', exposer(1))
    egal(etatDe(photo, reponse().result.resultats[1].etape_id).etat, 'pret', "case cochée par défaut")
    -- Rien d'écrit pour la photo (déjà ces valeurs) : l'avant préparé (copie de la vue) s'efface.
    rien("rien d'écrit", function() envoyer(14, 'appliquer', exposer(1)) end)
    egal(S.envois[#S.envois]:find('"etape_id":null', 1, true) ~= nil, true, "etape_id null dans la réponse")
    egal(next(Etapes.prepares), nil)
end)

essai("Etapes : la commande suivante attend la capture (etat non) ; l'avant de la suivante est l'après de la précédente", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    -- Chaque rendu prend une demi-seconde : la tâche rend la main pendant ce temps.
    pendantRendu = function() LrTasks.sleep(0.5) end
    local appliques = #photo.appliques
    local premier
    enTaches(function()
        envoyer(2, 'appliquer', exposer(0.5))
        egal(Etapes.enCours, true, "la capture de l'étape 2 est en cours")
        premier = reponse(2).result.resultats[1].etape_id
        envoyer(3, 'etat', {})
        egal(#S.envois, 3, "etat n'attend pas la capture")
        egal(reponse(3).id, 3)
        envoyer(4, 'appliquer', exposer(0.8, { etape = 'passe 2' }))
        egal(#S.envois, 3, "la commande 4 attend la fin de la capture")
        egal(#photo.appliques, appliques + 1, "et n'a rien écrit")
    end)
    egal(reponse(4).id, 4)
    local second = reponse(4).result.resultats[1].etape_id
    egal(etatDe(photo, premier).etat, 'pret', "la capture de l'étape 2 n'a pas vu l'écriture de la 4")
    egal(fichier(photo, premier .. '-apres.jpg'), 'JPEG n°2 (Exposure2012 0.5)')
    egal(fichier(photo, second .. '-avant.jpg'), 'JPEG n°2 (Exposure2012 0.5)', "l'avant de la 4 : l'après de la 2, sans autre rendu")
    egal(fichier(photo, second .. '-apres.jpg'), 'JPEG n°3 (Exposure2012 0.8)')
    egal(#S.rendus, 3)
    egal(Etapes.enCours, false)
end)

essai("Etapes : une écriture pendant le rendu jette l'après (changee) ; une capture trop longue n'arrête la suivante que 8 s", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    -- L'utilisateur retouche à la main pendant le rendu de l'après.
    pendantRendu = function()
        photo.reglages.Exposure2012 = 1.5
        photo:modifiee()
    end
    envoyer(2, 'appliquer', exposer(0.5))
    local id = reponse().result.resultats[1].etape_id
    local etat = etatDe(photo, id)
    egal(etat.etat, 'manque')
    egal(etat.raison, 'changee')
    egal(fichier(photo, id .. '-apres.jpg'), nil, "pas d'après douteux")
    egal(fichier(photo, id .. '-avant.jpg') ~= nil, true, "l'avant reste")
    egal(contient(Liaison.journal, "non gardé : la photo a changé pendant le rendu"), true)
    egal(Etapes.images(1, id).etat, 'manque')
    pendantRendu = nil

    -- Une capture qui ne finit pas : la commande suivante part après Etapes.ATTENTE secondes.
    Etapes.enCours, Etapes.enCoursDepuis = true, S.horloge
    local debut = S.horloge
    envoyer(3, 'etat', {})
    egal(S.horloge, debut, "etat n'attend pas")
    envoyer(4, 'appliquer', exposer(0.2, { photos = { 1, 1 } }))
    egal(S.horloge - debut >= Etapes.ATTENTE and S.horloge - debut < Etapes.ATTENTE + 1, true, "attendue 8 s : " .. (S.horloge - debut))
    egal(reponse().id, 4, "puis la commande se fait")
    egal(contient(Liaison.journal, "capture encore en cours après 8 s"), true)
    -- Tenue pour interrompue au-delà de PERIMEE secondes : plus d'attente.
    Etapes.enCours, Etapes.enCoursDepuis = true, S.horloge - Etapes.PERIMEE - 1
    debut = S.horloge
    envoyer(5, 'appliquer', exposer(0.3, { photos = { 1, 1 } }))
    egal(S.horloge, debut, "une capture périmée ne fait plus attendre")
    egal(Etapes.enCours, false)
end)

essai("Etapes : calculs IA en attente, pas de rendu (jamais la fenêtre « Mises à jour IA recommandées » pour une capture)", function()
    local photo = enFenetre(photoFuji())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    -- Modèles IA absents : Lightroom ne calcule pas le masque ; un rendu ouvrirait la fenêtre.
    S.modelesIAAbsents, S.calculDiffere, S.jamaisCalcule, S.clicUtilisateur = true, true, true, false
    envoyer(2, 'masquer', { masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } } }),
        etape = 'ciel', confirme = true })
    local r = reponse()
    egal(r.error, nil, tostring(r.error))
    local id = r.result.resultats[1].etape_id
    egal(#S.fenetresIA, 0, "aucune fenêtre ouverte par une capture")
    egal(#S.rendus, 1, "seule la vue a été rendue")
    local etat = etatDe(photo, id)
    egal(etat.etat, 'manque')
    egal(etat.raison, 'calculs_ia')
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)', "l'avant, lui, est gardé")
    egal(Etapes.images(4, id).raison, 'calculs_ia')
    -- Sans vue (une retouche à la main entre-temps), l'avant non plus n'est pas rendu.
    photo.reglages.Exposure2012 = 0.1
    envoyer(3, 'appliquer', exposer(0.4))
    local id2 = reponse().result.resultats[1].etape_id
    egal(#S.rendus, 1)
    egal(#S.fenetresIA, 0)
    egal(etatDe(photo, id2).raison, 'calculs_ia')
end)

essai("Etapes : empreinte stable après view_photo compare et preview_settings ; différente après une retouche à la main, une rotation et un débruitage", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } } })
    local e = Etapes.empreinte(photo)
    egal(Etapes.empreinte(photo), e, "deux lectures sans retouche")
    Commandes.executer('apercu', { comparer = 'etapePrecedente', taille = 800, cles = {} })
    egal(Etapes.empreinte(photo), e, "après l'aller-retour de view_photo compare")
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 1 }, libelles = {}, etape = 'essai', taille = 800 })
    egal(Etapes.empreinte(photo), e, "après preview_settings")
    -- Des clés que Lightroom calcule lui-même (…Digest, profil d'objectif résolu) ne comptent pas.
    photo.reglages.CameraProfileDigest = 'autre empreinte'
    photo.reglages.LensProfileName = 'Adobe (Fujifilm XF18-55mm)'
    egal(Etapes.empreinte(photo), e, "clés volatiles retirées")
    photo.reglages.Exposure2012 = 0.5
    egal(Etapes.empreinte(photo) ~= e, true, "une retouche à la main")
    photo.reglages.Exposure2012 = 0.4
    egal(Etapes.empreinte(photo), e, "même état, même empreinte")
    photo:rotateRight()
    local tournee = Etapes.empreinte(photo)
    egal(tournee ~= e, true, "une rotation d'un quart de tour (orientation)")
    Commandes.executer('ameliorer', { ameliorations = Json.tableau({ { nom = 'denoise', actif = true, intensite = 40 } }), etape = 'débruitage' })
    egal(Etapes.empreinte(photo) ~= tournee, true, "un débruitage")
end)

-- Constaté le 21 octobre 2026 (--dump, Lightroom Classic 15.6) : MaskGroupBasedCorrections passait
-- d'absente à {} (l'annulation d'une étape de masques, le retour de view_photo compare) puis de {}
-- à absente (rendus du recalage), sans rien changer à l'image : l'empreinte n'en dépend plus.
essai("Etapes : une liste vide vaut une clé absente dans l'empreinte (masques posés puis annulés, comparaison, recalage)", function()
    local photo = photoFuji()
    -- Les réglages de la géométrie à leur valeur neutre, comme getDevelopSettings les rend dans
    -- Lightroom (les rendus du recalage les remettent), et le profil d'objectif actif, comme la dune
    -- du relevé : le recalage rend ses deux images.
    for cle, valeur in pairs(require('Recalage').NEUTRE_GEOMETRIE) do
        photo.reglages[cle] = valeur
    end
    photo.reglages.LensProfileEnable = 1
    S.active, S.selection = photo, { photo }
    egal(photo.reglages.MaskGroupBasedCorrections, nil)
    local e = Etapes.empreinte(photo)
    for _, cle in ipairs({ 'MaskGroupBasedCorrections', 'RetouchInfo', 'RetouchAreas', 'RedEyeInfo', 'DepthBasedCorrections' }) do
        photo.reglages[cle] = {}
        egal(Etapes.empreinte(photo), e, cle .. " = {} vaut une clé absente")
        photo.reglages[cle] = nil
    end
    -- Le chemin constaté : une étape de masques, son annulation (la liste vide reste), une
    -- comparaison, puis les rendus du recalage (la liste vide tombe, règle de la simulation).
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'lineaire', de_x = 0.5, de_y = 0, a_x = 0.5, a_y = 0.4,
        locaux = { LocalExposure2012 = -0.3 } } }), etape = 'ciel' })
    egal(#photo.reglages.MaskGroupBasedCorrections, 1)
    egal(Etapes.empreinte(photo) ~= e, true, "un masque compte")
    Commandes.executer('annuler', {})
    egal(type(photo.reglages.MaskGroupBasedCorrections), 'table', "l'annulation remet une liste vide")
    egal(next(photo.reglages.MaskGroupBasedCorrections), nil)
    egal(Etapes.empreinte(photo), e, "après l'annulation des masques")
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } } })
    local e2 = Etapes.empreinte(photo)
    Commandes.executer('apercu', { comparer = 'avantClaude', taille = 800, cles = {} })
    egal(Etapes.empreinte(photo), e2, "après view_photo compare = before_claude")
    Commandes.executer('geometrie', { photos = { photo.localIdentifier }, rendre = true })
    egal(photo.reglages.MaskGroupBasedCorrections, nil, "les rendus du recalage la retirent (constaté)")
    egal(Etapes.empreinte(photo), e2, "après les rendus du recalage")
    -- Un élément vide d'une liste garde sa place ; une liste qui a quelque chose compte.
    photo.reglages.MaskGroupBasedCorrections = { {} }
    egal(Etapes.empreinte(photo) ~= e2, true, "une liste avec un élément, même vide, compte")
end)

essai("Etapes : l'avant d'une étape après view_photo compare est la vue de cette comparaison (l'état actuel, pas l'image d'avant)", function()
    local photo = enFenetre(photoRaw())
    appliquer({ reglages = { Exposure2012 = 0.4 }, plages = { Exposure2012 = { -5, 5 } } })
    envoyer(1, 'apercu', { taille = 1568, cles = {}, comparer = 'etapePrecedente' })
    egal(#S.rendus, 2, "l'image d'avant, puis l'état actuel")
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°2 (Exposure2012 0.4)', "la vue : l'état actuel")
    envoyer(2, 'appliquer', exposer(0.6, { etape = 'passe 2' }))
    local id = reponse().result.resultats[1].etape_id
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°2 (Exposure2012 0.4)')
    egal(#S.rendus, 3, "sans rendu de l'avant")
end)

essai("Rendu.apercu : la vue n'est gardée que pour l'image entière de l'état actuel de la photo active (ni zoom, ni entier, ni essayer)", function()
    local photo = enFenetre(photoRaw())
    local autre = A.photoJpeg()
    Commandes.executer('apercu', { taille = 0, cles = {} })
    egal(fichier(photo, 'vue.jpg'), nil, "un zoom (pleine résolution) n'est pas une vue")
    Commandes.executer('apercu', { taille = 1568, cles = {}, entier = true })
    egal(fichier(photo, 'vue.jpg'), nil, "l'image entière sans cadre (Composition) n'est pas l'état actuel")
    Commandes.executer('apercu', { photo = 2, taille = 1568, cles = {} })
    egal(fichier(autre, 'vue.jpg'), nil, "une autre photo que l'active")
    Commandes.executer('apercu', { taille = 1568, cles = {} })
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°4 (Exposure2012 0)')
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 1 }, libelles = {}, etape = 'essai', taille = 800 })
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°4 (Exposure2012 0)', "l'image d'une proposition ne remplace pas la vue")
    -- avant_apres (la recette) lève la condition de la photo active.
    Commandes.executer('apercu', { photo = 2, taille = 1568, cles = {}, avant_apres = true })
    egal(fichier(autre, 'vue.jpg') ~= nil, true, "avant_apres : la vue d'une autre photo")
    -- Une photo changée pendant le rendu : pas de vue (l'ancienne reste, pour son état à elle).
    pendantRendu = function() photo.reglages.Exposure2012 = 0.3 end
    Commandes.executer('apercu', { taille = 1568, cles = {} })
    pendantRendu = nil
    egal(fichier(photo, 'vue.jpg'), 'JPEG n°4 (Exposure2012 0)', "la vue d'un état changé pendant le rendu n'est pas gardée")
    egal(Etapes.vues[photo.brut.uuid].chemin, dossierDe(photo) .. '/vue.jpg')
end)

essai("Etapes : avant_apres (recette) garde l'avant/après hors de la photo active et fenêtre fermée ; jamais d'un outil", function()
    priseDesReponses()
    local photo = photoRaw()
    S.active = A.photoJpeg()
    envoyer(1, 'apercu', { photo = 1, taille = 1568, cles = {}, avant_apres = true })
    envoyer(2, 'appliquer', exposer(0.5, { photos = { 1 }, avant_apres = true }))
    local id = reponse().result.resultats[1].etape_id
    egal(etatDe(photo, id).etat, 'pret')
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)')
    egal(fichier(photo, id .. '-apres.jpg'), 'JPEG n°2 (Exposure2012 0.5)')
    egal(Etapes.actif({}), false, "sans avant_apres, fenêtre fermée : rien")
end)

essai("Etapes : recadrer complète la capture d'appliquer (a_recadrer) ; variantes choisir et ameliorer aussi", function()
    local photo = enFenetre(photoFuji())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    envoyer(2, 'appliquer', { reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie', confirme = true })
    local r = reponse().result.resultats[1]
    egal(r.a_recadrer, true)
    local id = r.etape_id
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)', "l'avant est gardé tout de suite")
    egal(fichier(photo, id .. '-apres.jpg'), nil, "l'après attend le cadre placé")
    egal(etatDe(photo, id).etat, 'en_cours')
    egal(Etapes.images(4, id).etat, 'en_cours', "la fenêtre dit « en préparation »")
    egal(#S.rendus, 1)
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    local recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) }
    envoyer(3, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, recalages = recalages, completer = { 4 },
        etape = r.etape, confirme = true })
    egal(reponse().result.resultats[1].etape_id, id)
    egal(fichier(photo, id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)', "l'avant de l'étape complétée ne change pas")
    egal(#S.rendus, 4, "la vue, les deux rendus du recalage, puis l'après seul : pas de rendu de l'avant")
    egal(fichier(photo, id .. '-apres.jpg') ~= nil, true, "l'après, cadre placé")
    egal(etatDe(photo, id).etat, 'pret')

    -- Une vue à jour entre appliquer et recadrer : l'avant de l'étape reste celui d'avant appliquer.
    appliquer({ reglages = { PerspectiveUpright = 0 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'sans upright' })
    envoyer(30, 'apercu', { taille = 1568, cles = {} })
    local vue = fichier(photo, 'vue.jpg')
    envoyer(31, 'appliquer', { reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie 2', confirme = true })
    local r2 = reponse().result.resultats[1]
    egal(r2.a_recadrer, true)
    egal(fichier(photo, r2.etape_id .. '-avant.jpg'), vue)
    envoyer(32, 'apercu', { taille = 1568, cles = {} })
    rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) }
    envoyer(33, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, recalages = recalages, completer = { 4 },
        etape = r2.etape, confirme = true })
    egal(fichier(photo, r2.etape_id .. '-avant.jpg'), vue, "l'avant d'avant appliquer, pas la vue d'entre-temps")
    egal(etatDe(photo, r2.etape_id).etat, 'pret')

    -- ameliorer : la photo passe par le module Développement, puis la vue revient.
    envoyer(4, 'ameliorer', { ameliorations = Json.tableau({ { nom = 'denoise', actif = true, intensite = 40 } }), etape = 'débruitage', confirme = true })
    local debruite = reponse().result.resultats[1].etape_id
    egal(etatDe(photo, debruite).etat, 'pret', "ameliorer")

    -- variantes choisir : la réponse porte etape_id à plat.
    local brute = enFenetre(photoRaw())
    envoyer(5, 'apercu', { taille = 1568, cles = {} })
    Commandes.executer('essayer', { action = 'appliquer', reglages = { Exposure2012 = 0.3, Temperature = 6200 }, libelles = {},
        etape = 'variante chaude', instantane = 'chaude', taille = 800 })
    envoyer(6, 'variantes', { action = 'choisir', nom = 'chaude', etape = 'variante chaude', confirme = true })
    local choisie = reponse().result.etape_id
    egal(type(choisie), 'string')
    egal(etatDe(brute, choisie).etat, 'pret', "variantes choisir")
    egal(fichier(brute, choisie .. '-avant.jpg'):find('Exposure2012 0)', 1, true) ~= nil, true, "l'avant : la vue d'avant la variante")
    egal(fichier(brute, choisie .. '-apres.jpg'):find('Exposure2012 0.3', 1, true) ~= nil, true)
end)

essai("Etapes : recadrer qui complète une étape sans avant gardé (fenêtre fermée à l'écriture) : l'après seul, manque sans_avant", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    priseDesReponses()
    envoyer(1, 'appliquer', { reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie', confirme = true })
    local r = reponse().result.resultats[1]
    egal(#S.rendus, 0, "fenêtre fermée : rien")
    Etapes.actifPour = function() return true end
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    local rendus = #S.rendus
    envoyer(2, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, completer = { 4 }, etape = r.etape, confirme = true,
        recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) } })
    egal(reponse().result.resultats[1].etape_id, r.etape_id)
    egal(#S.rendus, rendus + 1, "compléter : pas de rendu de l'avant, l'après seul")
    local etat = etatDe(photo, r.etape_id)
    egal(etat.etat, 'manque')
    egal(etat.raison, 'sans_avant')
    egal(fichier(photo, r.etape_id .. '-apres.jpg') ~= nil, true)
    egal(Etapes.images(4, r.etape_id).etat, 'manque', "la fenêtre : pas d'avant/après")
end)

essai("Etapes : recadrer sans completer pour la photo écrit une étape nouvelle, dont l'avant se rend au besoin", function()
    local photo = enFenetre(photoFuji())
    appliquer({ reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } } })
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    local rendus = #S.rendus
    envoyer(1, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.4 }, etape = 'cadre', confirme = true,
        recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) } })
    local id = reponse().result.resultats[1].etape_id
    egal(type(id), 'string')
    egal(#Json.decode(photo.proprietes.etapesClaude), 2, "une étape à part")
    egal(#S.rendus, rendus + 2, "l'avant (aucune vue de cet état), puis l'après")
    egal(etatDe(photo, id).etat, 'pret')
end)

-- appliquer avec Upright et un cadre demandé : l'étape attend recadrer pour son après.
local function appliquerARecadrer(photo, id, mode)
    envoyer(id, 'appliquer', { reglages = { PerspectiveUpright = mode }, plages = { PerspectiveUpright = { 0, 5 } },
        recadrage = { ratio = 1, centre_x = 0.6 }, etape = 'géométrie ' .. id, confirme = true })
    local r = reponse().result.resultats[1]
    egal(r.a_recadrer, true)
    egal(type(r.etape_id), 'string')
    return r
end

essai("Etapes : recadrer qui n'écrit rien pour la photo (pas de recalage) ou qui échoue finit l'étape d'appliquer : son après se rend", function()
    local photo = enFenetre(photoFuji())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    -- Sans grille de recalage (image trop uniforme pour le serveur), recadrer ne place rien.
    local r = appliquerARecadrer(photo, 2, 2)
    egal(etatDe(photo, r.etape_id).etat, 'en_cours')
    envoyer(3, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, completer = { 4 }, etape = r.etape, confirme = true })
    egal(S.envois[#S.envois]:find('"etape_id":null', 1, true) ~= nil, true, "recadrer n'a rien écrit")
    local etat = etatDe(photo, r.etape_id)
    egal(etat.etat, 'pret', "l'étape d'appliquer a son après, tel quel")
    egal(etat.etape, r.etape)
    egal(fichier(photo, r.etape_id .. '-avant.jpg'), 'JPEG n°1 (Exposure2012 0)')
    egal(fichier(photo, r.etape_id .. '-apres.jpg') ~= nil, true)
    egal(Etapes.images(4, r.etape_id).etat, 'pret')

    -- recadrer en erreur : l'après se rend une fois l'erreur répondue.
    local r2 = appliquerARecadrer(photo, 4, 3)
    local executer = Commandes.executer
    Commandes.executer = function(nom, params)
        if nom == 'recadrer' then
            error("Lightroom est occupé.", 0)
        end
        return executer(nom, params)
    end
    local envoisAuRendu
    pendantRendu = function() envoisAuRendu = #S.envois end
    local ok, erreur = pcall(envoyer, 5, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, completer = { 4 },
        etape = r2.etape, confirme = true })
    Commandes.executer = executer
    pendantRendu = nil
    egal(ok, true, tostring(erreur))
    egal(reponse().error, "Lightroom est occupé.")
    egal(envoisAuRendu, #S.envois, "l'après est rendu une fois l'erreur répondue")
    egal(etatDe(photo, r2.etape_id).etat, 'pret')
    egal(next(Etapes.prepares), nil)
end)

essai("Etapes : recadrer qui complète une étape faite fenêtre fermée ne prend pas la vue d'entre les deux pour avant ; une étape à part, si", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    priseDesReponses()
    local r = appliquerARecadrer(photo, 1, 2)
    egal(#S.rendus, 0, "fenêtre fermée : rien")
    -- La fenêtre s'ouvre ; view_photo montre l'état d'entre appliquer et recadrer.
    Etapes.actifPour = function() return true end
    local rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    envoyer(2, 'apercu', { taille = 1568, cles = {} })
    egal(fichier(photo, 'vue.jpg') ~= nil, true)
    envoyer(3, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.6 }, completer = { 4 }, etape = r.etape, confirme = true,
        recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) } })
    egal(reponse().result.resultats[1].etape_id, r.etape_id, "l'étape d'appliquer, complétée")
    egal(fichier(photo, r.etape_id .. '-avant.jpg'), nil, "pas d'avant : la vue montre l'état d'après appliquer")
    local etat = etatDe(photo, r.etape_id)
    egal(etat.etat, 'manque')
    egal(etat.raison, 'sans_avant')

    -- La dernière étape n'a pas ce nom : recadrer écrit une étape à part, dont l'avant est la vue.
    envoyer(4, 'apercu', { taille = 1568, cles = {} })
    local vue = fichier(photo, 'vue.jpg')
    rendu = Commandes.executer('geometrie', { photos = { 4 }, rendre = true }).photos[1]
    envoyer(5, 'recadrer', { photos = { 4 }, recadrage = { ratio = 1, centre_x = 0.4 }, completer = { 4 }, etape = 'autre cadre', confirme = true,
        recalages = { ['4'] = grilleDe(S.deformation(photo), rendu.empreinte) } })
    local id = reponse().result.resultats[1].etape_id
    egal(type(id), 'string')
    egal(id ~= r.etape_id, true, "une étape à part")
    egal(fichier(photo, id .. '-avant.jpg'), vue, "son avant : la vue, l'état d'avant recadrer")
    egal(etatDe(photo, id).etat, 'pret')
end)

essai("Etapes : rien de rendu pour une commande qu'une photo protégée ou un accord trop vieux feront refuser", function()
    local photo = enFenetre(photoRaw())
    local function refusee(quoi, id, params)
        local rendus, fichiers = #S.rendus, fichiersEtapes()
        envoyer(id, 'appliquer', params)
        egal(reponse().error ~= nil, true, quoi .. " : refusée")
        egal(#S.rendus, rendus, quoi .. " : pas d'avant rendu en vain")
        egal(fichiersEtapes(), fichiers, quoi .. " : aucun fichier sous Etapes/")
    end
    -- Aucune vue : sans ces refus prévus, l'avant se rendrait avant l'écriture.
    S.prefs.copiesSeulement = true
    refusee("pas une copie virtuelle (copies virtuelles seulement)", 1, exposer(0.3))
    S.prefs.copiesSeulement = false
    S.prefs.rejeteesProtegees, photo.brut.pickStatus = true, -1
    refusee("photo rejetée, protégée", 2, exposer(0.3))
    S.prefs.rejeteesProtegees, photo.brut.pickStatus = false, 0
    S.prefs.mode, S.prefs.accordDansLightroom = 'proposer', true
    Liaison.accord = { accepte = true, le = S.horloge - Ecriture.DUREE_ACCORD - 1 }
    refusee("accord donné dans Lightroom il y a plus de 10 minutes", 3, exposer(0.4))
    -- Un accord récent : l'avant se rend, l'écriture se fait, puis l'après.
    Liaison.accord = { accepte = true, le = S.horloge }
    envoyer(4, 'appliquer', exposer(0.5))
    local id = reponse().result.resultats[1].etape_id
    egal(type(id), 'string', "accord récent : écrite")
    egal(etatDe(photo, id).etat, 'pret', "et son avant/après gardé")
    egal(photo.reglages.Exposure2012, 0.5)
end)

essai("Etapes : ce que Lightroom calcule au rendu ne fait pas jeter l'image (calculs IA avant la vue, matrices d'Upright de l'après)", function()
    local photo = enFenetre(photoFuji())
    -- Un profil adaptatif à calculer : Lightroom le calcule juste avant le rendu de view_photo.
    photo.reglages.AILook = { Active = true }
    photo.lookAMettreAJour = true
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    egal(photo.reglages.AILook.AILookData ~= nil, true, "calculé avant le rendu")
    egal(fichier(photo, 'vue.jpg') ~= nil, true, "la vue est gardée : son empreinte se lit après les calculs")
    -- Upright sans cadre demandé : Lightroom calcule ses matrices au rendu de l'après.
    envoyer(2, 'appliquer', { reglages = { PerspectiveUpright = 2 }, plages = { PerspectiveUpright = { 0, 5 } }, etape = 'upright', confirme = true })
    local r = reponse().result.resultats[1]
    egal(r.a_recadrer, nil, "pas de cadre à placer")
    egal(photo.reglages.UprightTransform_0 ~= nil, true, "matrices calculées au rendu de l'après")
    local etat = etatDe(photo, r.etape_id)
    egal(etat.etat, 'pret', "l'après n'est pas jeté (" .. tostring(etat.raison) .. ")")
    egal(#S.rendus, 2, "la vue, puis l'après")
    -- L'après devient la vue : l'avant de l'étape suivante, sans autre rendu.
    envoyer(3, 'appliquer', exposer(0.3, { etape = 'passe 2' }))
    local id = reponse().result.resultats[1].etape_id
    egal(fichier(photo, id .. '-avant.jpg'), fichier(photo, r.etape_id .. '-apres.jpg'))
    egal(#S.rendus, 3)
end)

essai("Rendu.apercu : une vue rendue avant la fin des calculs IA (aperçu incomplet, a_savoir) n'est pas gardée", function()
    local photo = photoFuji()
    S.active, S.selection = photo, { photo }
    S.modelesIAAbsents, S.calculDiffere, S.jamaisCalcule = true, true, true
    Commandes.executer('masquer', { masques = Json.tableau({ { type = 'ia', soustype = 2, nom = 'Claude · Ciel', locaux = { LocalExposure2012 = -0.1 } } }),
        etape = 'ciel', confirme = true })
    -- Une autre photo active : son rendu n'ouvre pas la fenêtre, et le calcul reste à faire.
    S.active = A.photoJpeg()
    local r = Commandes.executer('apercu', { photo = 4, taille = 1568, cles = {}, avant_apres = true })
    egal(r.a_savoir ~= nil, true, "l'aperçu se dit incomplet")
    egal(fichier(photo, 'vue.jpg'), nil, "il n'est pas gardé comme vue")
    egal(Etapes.vues[photo.brut.uuid], nil)
    -- Les calculs faits, la vue se garde.
    photo:calculerMasquesIA()
    r = Commandes.executer('apercu', { photo = 4, taille = 1568, cles = {}, avant_apres = true })
    egal(r.a_savoir, nil)
    egal(fichier(photo, 'vue.jpg') ~= nil, true)
end)

essai("Liaison : une commande en erreur efface son avant préparé ; une erreur des crochets n'atteint pas la commande", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    local fichiers = fichiersEtapes()
    envoyer(2, 'appliquer', { reglages = {}, plages = {}, confirme = true, etape = 'vide' })
    egal(reponse().error, "Aucun réglage à appliquer.")
    egal(fichiersEtapes(), fichiers, "l'avant préparé (copie de la vue) est effacé")
    egal(next(Etapes.prepares), nil, "plus de préparation")

    local avant, apres = Etapes.avantCommande, Etapes.apresCommande
    Etapes.avantCommande = function() error("crochet en panne") end
    envoyer(3, 'appliquer', exposer(0.5))
    egal(reponse().id, 3)
    egal(photo.reglages.Exposure2012, 0.5, "la commande se fait")
    Etapes.avantCommande = avant
    Etapes.apresCommande = function() error("crochet en panne") end
    envoyer(4, 'appliquer', exposer(0.6))
    Etapes.apresCommande = apres
    egal(reponse().id, 4)
    egal(photo.reglages.Exposure2012, 0.6)
end)

-- Lecture et ménage -------------------------------------------------------------------------------

essai("commande etapes : lecture seule (aucune écriture), images et état par étape ; une étape défaite reste sur le disque, hors mémoire", function()
    local photo = enFenetre(photoRaw())
    envoyer(1, 'apercu', { taille = 1568, cles = {} })
    envoyer(2, 'appliquer', exposer(0.5))
    local id1 = reponse().result.resultats[1].etape_id
    envoyer(3, 'appliquer', exposer(0.7, { etape = 'passe 2' }))
    local id2 = reponse().result.resultats[1].etape_id
    Commandes.executer('annuler', {})
    local ecritures, privees, appliques = #S.ecritures, S.ecrituresPrivees, #photo.appliques
    local liste = Commandes.executer('etapes', {})
    egal(#S.ecritures, ecritures, "aucune écriture")
    egal(S.ecrituresPrivees, privees, "même privée")
    egal(#photo.appliques, appliques)
    egal(liste.photo.id, 1)
    egal(#liste.etapes, 2)
    local e1, e2 = liste.etapes[1], liste.etapes[2]
    egal(e1.id, id1)
    egal(e1.nom, 'Claude · passe 1')
    egal(e1.en_memoire, true)
    egal(e1.etat, 'pret')
    egal(e1.avant, dossierDe(photo) .. '/' .. id1 .. '-avant.jpg')
    egal(e1.apres, dossierDe(photo) .. '/' .. id1 .. '-apres.jpg')
    egal(e1.raison, Json.null)
    egal(e2.id, id2, "l'étape défaite par undo_last")
    egal(e2.en_memoire, false)
    egal(e2.nom, 'Claude · passe 2')
    egal(e2.etat, 'pret')
    -- Rejouée par le serveur (LightroomBridge.lectures) : sa réponse se relit en JSON.
    egal(Json.decode(Json.encode(liste)).etapes[2].id, id2)

    -- Pour la fenêtre : une table neuve, sans métatable.
    local images = Etapes.images(1, id1)
    egal(getmetatable(images), nil)
    egal(images.dossier, dossierDe(photo))
    egal(images.avant, id1 .. '-avant.jpg')
    egal(images.apres, id1 .. '-apres.jpg')
    egal(images.etat, 'pret')
    egal(Etapes.images(1, 'inconnue').etat, 'inconnu')
    egal(Etapes.images(777, id1).etat, 'inconnu', "une photo absente du catalogue")

    -- Une étape d'avant la 1.3 (sans id) est listée, sans images.
    photo.proprietes.etapesClaude = Json.encode(Json.tableau({ { nom = 'Claude · ancienne', avant = { Exposure2012 = 0 } } }))
    liste = Commandes.executer('etapes', {})
    egal(liste.etapes[1].id, Json.null)
    egal(liste.etapes[1].etat, 'inconnu')
    egal(liste.etapes[1].avant, Json.null)
end)

essai("Etapes.menage : vue et préparations effacées, fichiers de plus de 30 jours, puis les plus anciens au-delà du plafond ; dossiers vidés", function()
    local racine = Chemins.etapes()
    local jour = 86400
    egal(Etapes.menage(), 0, "sans dossier Etapes : rien à faire")
    S.horloge = 100 * jour
    local function poser(chemin, contenu, age)
        Fichiers.ecrire(racine .. '/' .. chemin, contenu)
        S.datesFichiers[racine .. '/' .. chemin] = S.horloge - age
    end
    poser('u1/a-avant.jpg', 'vieux', 31 * jour)
    poser('u1/a.json', '{}', 31 * jour)
    poser('u1/b-avant.jpg', 'récent', jour)
    poser('u2/vue.jpg', 'vue', 0)
    poser('u2/prepare-3.jpg', 'préparé', 0)
    poser('u3/c-avant.jpg', 'très vieux', 60 * jour)
    local effaces = Etapes.menage()
    egal(effaces, 5)
    egal(S.fichiers[racine .. '/u1/a-avant.jpg'], nil, "plus de 30 jours")
    egal(S.fichiers[racine .. '/u1/a.json'], nil)
    egal(S.fichiers[racine .. '/u1/b-avant.jpg'], 'récent', "gardé")
    egal(S.fichiers[racine .. '/u2/vue.jpg'], nil, "la vue d'une session passée")
    egal(S.fichiers[racine .. '/u2/prepare-3.jpg'], nil, "une préparation interrompue")
    egal(S.fichiers[racine .. '/u2'], nil, "dossier vidé : effacé")
    egal(S.fichiers[racine .. '/u3'], nil)
    egal(S.fichiers[racine .. '/u1'], 'dossier', "un dossier qui garde un fichier reste")
    egal(contient(Liaison.journal, "5 fichier(s) ancien(s) effacé(s)"), true)

    -- Au-delà du plafond : les plus anciens d'abord, tant qu'il le faut. 37 octets en tout
    -- (« récent » en fait 7), pour un plafond de 30 : le plus ancien seul s'en va.
    local plafond = Etapes.MAX_OCTETS
    Etapes.MAX_OCTETS = 30
    poser('u4/d-avant.jpg', '0123456789', 3 * jour)
    poser('u4/d-apres.jpg', '0123456789', 2 * jour)
    poser('u4/e-avant.jpg', '0123456789', 0)
    local ok, erreur = pcall(Etapes.menage)
    egal(ok, true, tostring(erreur))
    egal(erreur, 1)
    egal(S.fichiers[racine .. '/u4/d-avant.jpg'], nil, "le plus ancien")
    egal(S.fichiers[racine .. '/u4/d-apres.jpg'], '0123456789', "le reste tient sous le plafond")
    egal(S.fichiers[racine .. '/u1/b-avant.jpg'], 'récent')
    egal(S.fichiers[racine .. '/u4/e-avant.jpg'], '0123456789')
    -- Un plafond plus bas : les suivants, toujours les plus anciens d'abord.
    Etapes.MAX_OCTETS = 12
    ok, erreur = pcall(Etapes.menage)
    Etapes.MAX_OCTETS = plafond
    egal(ok, true, tostring(erreur))
    egal(S.fichiers[racine .. '/u4/d-apres.jpg'], nil, "deux jours")
    egal(S.fichiers[racine .. '/u1/b-avant.jpg'], nil, "un jour")
    egal(S.fichiers[racine .. '/u4/e-avant.jpg'], '0123456789', "le plus récent reste")
    egal(S.fichiers[racine .. '/u1'], nil, "dossier vidé par le plafond : effacé")
    egal(Etapes.menage(), 0, "rien de plus")
end)

essai("Init.lua : Etapes.menage dans sa propre protection, même si le ménage de la fenêtre échoue", function()
    local racine = Chemins.etapes()
    S.horloge = 100 * 86400
    Fichiers.ecrire(racine .. '/u1/a-avant.jpg', 'vieux')
    S.datesFichiers[racine .. '/u1/a-avant.jpg'] = 0
    S.prefs.demarrerAuLancement = false
    local session, menage = package.loaded.Session, package.loaded.Menage
    package.loaded.Session = { menage = function() error("ménage de la fenêtre en échec") end }
    package.loaded.Menage = { presetsInvisibles = function() return 0 end }
    local ok, erreur = pcall(function() assert(loadfile(dossierModule .. 'Init.lua'))() end)
    package.loaded.Session, package.loaded.Menage = session, menage
    egal(ok, true, tostring(erreur))
    egal(S.fichiers[racine .. '/u1/a-avant.jpg'], nil, "le ménage des étapes s'est fait")
end)

A.bilan()
