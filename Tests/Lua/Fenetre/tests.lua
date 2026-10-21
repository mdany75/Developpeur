-- tests.lua : essais de la fenêtre Claude du module Développeur hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua). Lancés par scripts/tester-module.sh, depuis ce dossier.
-- Le relais et le moteur sont éprouvés avec faux-claude.sh : ni Claude, ni quota, ni Lightroom ;
-- les fichiers vont dans un dossier personnel temporaire.

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

local Json = require 'Json'
local Texte = require 'Texte'
local Evenements = require 'Evenements'
local Conversation = require 'Conversation'
local Fil = require 'Fil'
local Metriques = require 'Metriques'
local Chemins = require 'Chemins'
local Stockage = require 'Stockage'
local Fichiers = require 'Fichiers'
local Session = require 'Session'

local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')

-- Texte ---------------------------------------------------------------------------------------

essai('Texte : longueur, début et raccourci en UTF-8', function()
    egal(5, Texte.longueur('été à'))
    egal('ét', Texte.debut('été', 2))
    egal('Bonj…', Texte.raccourcir('Bonjour', 5))
    egal('Bonjour', Texte.raccourcir('Bonjour', 7))
end)

essai('Texte : recherche sans accents ni majuscules', function()
    egal('pont de quebec en ete', Texte.plier('Pont de Québec en ÉTÉ'))
    egal("l'oeil", Texte.plier('L’Œil'))
end)

essai('Texte : nombres à la française', function()
    egal('0,35', Texte.nombre(0.35))
    egal('-12', Texte.nombre(-12))
    egal('1,5', Texte.nombre(1.5))
end)

essai('Texte : guillemets du shell', function()
    egal("'l'\\''eau'", Texte.shell("l'eau"))
end)

-- Événements ----------------------------------------------------------------------------------

essai('Événements : init, partiel, outil, résultat avec image, fin, forfait', function()
    local init = Evenements.lire('{"type":"system","subtype":"init","session_id":"abc","model":"claude-opus","mcp_servers":[{"name":"developpeur","status":"connected"}]}')
    egal('init', init.genre)
    egal('abc', init.session)
    egal('connected', init.serveurs.developpeur)

    local partiel = Evenements.lire('{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Bon"}}}')
    egal('partiel', partiel.genre)
    egal('Bon', partiel.texte)

    local a = Evenements.lire('{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"Je regarde."},{"type":"tool_use","id":"t1","name":"mcp__developpeur__view_photo","input":{"photo_id":3}}]}}')
    egal('assistant', a.genre)
    egal(3, #a.blocs)
    egal('reflexion', a.blocs[1].genre)
    egal('outil', a.blocs[3].genre)
    egal(3, a.blocs[3].entree.photo_id)

    local r = Evenements.lire('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":false,"content":[{"type":"text","text":"mesures"},{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"QUJD"}},{"type":"text","text":"[Image: source: /tmp/a.jpg]"}]}]}}')
    egal('resultats', r.genre)
    egal(1, #r.resultats[1].textes, 'le rappel « [Image: source: …] » est retiré')
    egal('QUJD', r.resultats[1].images[1].donnees)

    local fin = Evenements.lire('{"type":"result","subtype":"success","is_error":false,"result":"ok","session_id":"abc","duration_ms":10,"num_turns":3,"usage":{"input_tokens":5,"output_tokens":7}}')
    egal('fin', fin.genre)
    vrai(fin.reussie and not fin.interrompue)
    egal(7, fin.usage.sortie)

    local stop = Evenements.lire('{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"abc"}')
    vrai(stop.interrompue and not stop.reussie)

    local l = Evenements.lire('{"type":"rate_limit_event","rate_limit_info":{"unifiedWindows":{"five_hour":{"utilization":0.5},"seven_day":{"utilization":0.25}}}}')
    egal(0.5, l.cinqHeures)
    egal(0.25, l.semaine)

    egal(nil, Evenements.lire('error: unknown option'))
    egal('ignore', Evenements.lire('{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}').genre)
end)

essai('Événements : lignes envoyées à Claude Code', function()
    local m = Json.decode(Evenements.messageUtilisateur('Bonjour', { { donnees = 'QUJD', type = 'image/png' } }))
    egal('user', m.type)
    egal('image', m.message.content[1].type)
    egal('image/png', m.message.content[1].source.media_type)
    egal('Bonjour', m.message.content[2].text)
    local i = Json.decode(Evenements.interruption('interruption-1'))
    egal('interrupt', i.request.subtype)
end)

-- Conversation --------------------------------------------------------------------------------

essai('Conversation : marqueur du titre', function()
    egal('Pont de Québec en automne', Conversation.lireTitre('[titre : Pont de Québec en automne]\nBonjour'))
    egal('Flamant rose', Conversation.lireTitre('**[Titre : « Flamant rose ».]**'))
    egal(nil, Conversation.lireTitre('[titre : <ce que montre la photo>]'))
    egal('Bonjour', Conversation.retirerMarqueur('[titre : Pont]\nBonjour'))
    egal('Bonjour', Conversation.retirerMarqueur('Bonjour\n[tit', true))
    vrai(Conversation.debutMarqueur('[titre : Pont de'))
    vrai(not Conversation.debutMarqueur('[note]'))
end)

essai('Conversation : un tour complet de Claude', function()
    local c = Conversation.nouvelle(1000)
    Conversation.ajouterDemande(c, 'Retouche la photo active comme un professionnel : diagnostic chiffré, deux passes.', 1000)
    egal('Retouche la photo active comme un professionnel…', c.titre)
    Conversation.appliquer(c, { genre = 'init', session = 's1' })
    egal('s1', c.sessionID)
    Conversation.appliquer(c, { genre = 'partiel', texte = '[titre : Flamant' })
    egal('', Conversation.texteAffiche(c.elements[2]), 'marqueur pas fini caché')
    Conversation.appliquer(c, { genre = 'partiel', texte = ' rose]\nJe regarde' })
    egal('Flamant rose', c.titre)
    egal('Je regarde', Conversation.texteAffiche(c.elements[2]))
    Conversation.appliquer(c, { genre = 'assistant', blocs = {
        { genre = 'texte', texte = '[titre : Flamant rose]\nJe regarde la photo.' },
        { genre = 'outil', id = 't1', nom = 'mcp__developpeur__view_photo', entree = {} },
    } })
    egal('Je regarde la photo.', c.elements[2].texte)
    egal('outil', c.elements[3].genre)
    egal('enCours', c.elements[3].etat)
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 't1', textes = { 'ok' }, images = { { donnees = 'x' } }, erreur = false } } },
        nil, function() return 'image-1.jpg' end)
    egal('fait', c.elements[3].etat)
    egal('apercu', c.elements[4].genre)
    egal('image-1.jpg', c.elements[4].images[1])
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 't2', nom = 'mcp__developpeur__preview_settings',
        entree = { step_name = 'passe 1', reason = 'Balance', settings = { Exposure2012 = 0.35, Temperature = 5200 } } } } })
    local p = Conversation.propositionEnAttente(c)
    vrai(p, 'proposition en attente')
    egal('Balance', p.texte)
    egal('Exposition', p.changements[1].libelle)
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 't2', textes = { '{"changements":[{"cle":"Exposure2012","avant":0,"apres":0.35}]}' }, images = {}, erreur = false } } })
    egal('0', p.changements[1].avant)
    egal('0,35', p.changements[1].apres)
    Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = 's1' }, 2000)
    egal('Je regarde la photo.', c.resume)
    egal(2000, c.modifiee)
    Conversation.decider(c, p.id, true)
    egal(nil, Conversation.propositionEnAttente(c))
    egal(2, Conversation.outilsFaits(c))
    egal(1, #Conversation.images(c))
end)

essai('Conversation : interruption et erreur', function()
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, 'x')
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 't', nom = 'view_photo', entree = {} } } })
    Conversation.appliquer(c, { genre = 'fin', reussie = false, interrompue = true, session = '' })
    egal('erreur', c.elements[2].etat)
    egal('Interrompu à votre demande.', c.elements[3].texte)
end)

essai('Conversation : recherche dans les titres et les messages', function()
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, 'Retouche le pont de Québec')
    vrai(Conversation.correspond(c, 'quebec pont'))
    vrai(not Conversation.correspond(c, 'flamant'))
    vrai(Conversation.correspond(c, ''))
end)

essai('Conversation : message pour Claude avec contexte et rappel du titre', function()
    local c = Conversation.nouvelle()
    local m = Conversation.messagePourClaude(c, 'Bonjour', '[Lightroom : photo active 1 (A.RAF) ; sélection : 1 photo]')
    vrai(m:find('^%[Lightroom'), 'contexte en tête')
    vrai(m:find('%[titre :'), 'rappel du titre')
    c.titreAuto = true
    vrai(not Conversation.messagePourClaude(c, 'Bonjour'):find('titre'), 'plus de rappel')
end)

-- Fil -----------------------------------------------------------------------------------------

essai('Fil : chasse mesurée et coupe à la largeur', function()
    vrai(Fil.largeur('MMMM', 'texte') > Fil.largeur('iiii', 'texte'))
    egal(4 * Metriques.mono.chasse['a'], Fil.largeur('abcd', 'mono'))
    local texte = string.rep('Une phrase assez longue pour plusieurs lignes. ', 12)
    local lignes = Fil.couper(texte, 300, 'texte')
    vrai(#lignes > 3, 'plusieurs lignes')
    for _, l in ipairs(lignes) do
        vrai(Fil.largeur(l, 'texte') <= 300, 'ligne trop large : ' .. l)
    end
    -- Un mot plus long que la ligne est coupé au caractère.
    for _, l in ipairs(Fil.couper(string.rep('é', 200), 120, 'texte')) do
        vrai(Fil.largeur(l, 'texte') <= 120)
    end
    -- Retrait des lignes de suite d'une puce.
    local puce = Fil.couper('•  ' .. string.rep('mot ', 60), 200, 'texte', '    ')
    vrai(puce[2]:sub(1, 4) == '    ', 'retrait')
end)

essai('Fil : Markdown léger', function()
    egal('titre', (Fil.ligneMarkdown('## Diagnostic')))
    local g, t = Fil.ligneMarkdown('**Diagnostic** :')
    egal('titre', g)
    egal('Diagnostic :', t)
    g, t = Fil.ligneMarkdown('- **Exposition** : juste')
    egal('claude', g)
    egal('•  Exposition : juste', t)
    egal(nil, (Fil.ligneMarkdown('|---|---|')))
    g, t = Fil.ligneMarkdown('| Photo | Avant |')
    egal('Photo · Avant', t)
end)

essai('Fil : lignes d\'une conversation et fenêtre de lecture', function()
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, 'Bonjour')
    c.elements[#c.elements + 1] = { id = 'o1', genre = 'outil', texte = 'view_photo', etat = 'fait', images = {}, changements = {} }
    c.elements[#c.elements + 1] = { id = 'a1', genre = 'apercu', texte = '', images = { 'image-1.jpg' }, changements = {} }
    c.elements[#c.elements + 1] = { id = 'c1', genre = 'claude', texte = 'Passe 1 vérifiée.\n\n## Résumé\n- un', images = {}, changements = {} }
    local cache = {}
    local lignes = Fil.lignes(c, 500, cache)
    egal('dany', lignes[1].genre)
    egal('dany', lignes[1].icone)
    egal('vide', lignes[2].genre)
    egal('outil', lignes[3].genre)
    egal('ok', lignes[3].icone)
    egal('apercu', lignes[4].genre, 'outil et aperçu collés')
    egal('image-1.jpg', lignes[4].image)
    egal('vide', lignes[5].genre)
    egal('Passe 1 vérifiée.', lignes[6].texte)
    egal('titre', lignes[8].genre)
    -- Le cache rend les mêmes lignes.
    egal(#lignes, #Fil.lignes(c, 500, cache))
    local premiere, defilement = Fil.fenetre(100, 30, 0)
    egal(71, premiere)
    premiere, defilement = Fil.fenetre(100, 30, 500)
    egal(1, premiere)
    egal(70, defilement)
    egal(1, (Fil.fenetre(10, 30, 0)))
end)

-- Stockage ------------------------------------------------------------------------------------

essai('Stockage : enregistrer, relire, supprimer', function()
    local c = Conversation.nouvelle(1000)
    Conversation.ajouterDemande(c, 'Bonjour « été »', 1000)
    c.elements[1].images = {}
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    vrai(texte:find('"images":%[%]'), 'liste vide écrite en tableau')
    egal('developpeur/1', Json.decode(texte).format, 'format du module')
    local relue = Stockage.lire(c.id)
    egal('Bonjour « été »', relue.elements[1].texte)
    local liste = Stockage.charger()
    egal(c.id, liste[1].id)
    Stockage.supprimer(c.id)
    egal(false, Fichiers.existe(Stockage.dossier(c.id)))
end)

-- Relais et moteur, avec le faux Claude Code -------------------------------------------------

local faux = dossierTests .. '/faux-claude.sh'
local prefs = Chemins.prefs()
prefs.cheminClaude = faux
prefs.cheminConnecteur = '/bin/echo'

-- Une petite image JPEG (en base64) pour le résultat d'outil du faux Claude Code.
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))
-- Hérité par relais.sh puis par le faux Claude Code. Une clé d'API ne doit jamais arriver jusqu'à lui.
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' ANTHROPIC_API_KEY=cle-essai '
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = env .. commande
    end
    return executerOriginal(commande)
end

local Moteur = require 'Moteur'

local function attendre(condition, secondes)
    for _ = 1, (secondes or 10) * 10 do
        Moteur.tic()
        if condition() then
            return true
        end
        S.executer('sleep 0.1')
    end
    return false
end

local function arguments()
    return Fichiers.lire(Chemins.atelier() .. '/arguments.txt') or ''
end

essai('Moteur : une demande, de bout en bout par relais.sh', function()
    Moteur.charger()
    Moteur.nouvelle()
    local ok, raison = Moteur.envoyer('Retouche la photo', { modele = 'haiku' })
    vrai(ok, raison)
    vrai(Moteur.travaille)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    local c = Moteur.courante
    egal('Flamant rose au zoo', c.titre)
    egal('session-essai', c.sessionID)
    egal('dany', c.elements[1].genre)
    egal('Bonjour, je regarde la photo.', c.elements[2].texte)
    egal('outil', c.elements[3].genre)
    egal('fait', c.elements[3].etat)
    egal('view_photo · photo 53636309', c.elements[3].texte)
    egal('apercu', c.elements[4].genre)
    local image = Stockage.image(c.id, c.elements[4].images[1])
    vrai(Fichiers.existe(image), 'image décodée')
    egal('  pixelWidth: 90', (S.lireCommande('sips -g pixelWidth ' .. S.q(image)):match('\n([^\n]*pixelWidth[^\n]*)')))
    egal('Forfait : 5 h 23 % · semaine 41 %', Moteur.texteForfait())
    local a = arguments()
    vrai(a:find('--model\nhaiku', 1, true), 'modèle passé')
    vrai(a:find('--effort\nmax', 1, true), 'effort maximal par défaut, quel que soit le modèle')
    vrai(a:find('--strict-mcp-config', 1, true) and a:find('--permission-prompts\nnone', 1, true), 'options de Claude Code')
    vrai(not a:find('--resume', 1, true), 'nouvelle session')
    vrai(not a:find('cle-api-presente', 1, true), "aucune clé d'API ne passe")
    vrai(Fichiers.existe(Stockage.fichier(c.id)), 'conversation enregistrée')
    vrai(Moteur.session and Moteur.session:actif(), 'Claude Code reste ouvert')
    -- Le connecteur seul, nommé developpeur : ses outils sont mcp__developpeur__* (relais.sh).
    local config = Json.decode(Fichiers.lire(Chemins.configMCP()))
    egal('/bin/echo', config.mcpServers.developpeur.command)
    vrai(Chemins.configMCP():find('/Library/Application Support/Developpeur/connecteur.json$'), Chemins.configMCP())
    vrai(a:find('--allowedTools\nmcp__developpeur__*', 1, true), 'outils du connecteur autorisés')
    egal(Chemins.atelier(), Moteur.session.travail, "dossier de travail : l'Atelier")
    -- Aucune note : le faux Claude Code dit le connecteur developpeur « connected ».
    for _, e in ipairs(c.elements) do
        vrai(e.genre ~= 'note', 'note inattendue : ' .. tostring(e.texte))
    end
end)

essai("Moteur : connecteur MCP-Développeur qui n'a pas démarré", function()
    local c = Conversation.nouvelle()
    Moteur.traiter(c, { genre = 'init', session = 's', serveurs = { [Session.SERVEUR] = 'failed' } })
    local d = c.elements[#c.elements]
    vrai(d and d.genre == 'note' and d.texte:find("MCP-Développeur n'a pas démarré (failed)", 1, true), d and d.texte)
    local autre = Conversation.nouvelle()
    Moteur.traiter(autre, { genre = 'init', session = 's', serveurs = { [Session.SERVEUR] = 'connected' } })
    egal(0, #autre.elements, 'connecté : pas de note')
end)

essai('Moteur : la demande suivante va au même processus', function()
    local dossier = Moteur.session.dossier
    local ok = Moteur.envoyer('Encore', { modele = 'haiku' })
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    egal(dossier, Moteur.session.dossier)
    local entree = Fichiers.lire(dossier .. '/entree.jsonl')
    local _, n = entree:gsub('\n', '')
    egal(2, n, 'deux messages')
end)

-- Le modèle et l'effort se choisissent dans le Gestionnaire de modules externes (préférences
-- `modele` et `effort`) : la demande suivante relance Claude Code s'ils ont changé.
essai('Moteur : un autre modèle dans les préférences relance Claude Code en reprenant la session', function()
    local prefs = Chemins.prefs()
    local ancien = Moteur.session
    prefs.modele = 'sonnet'
    local ok = Moteur.envoyer('Avec Sonnet')
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    vrai(ancien ~= Moteur.session, 'relancé')
    vrai(attendre(function() return Fichiers.existe(ancien.dossier .. '/fin.code') end, 8), 'ancien processus fermé')
    local a = arguments()
    vrai(a:find('--resume\nsession-essai', 1, true), 'session reprise')
    vrai(a:find('--model\nsonnet', 1, true), 'nouveau modèle')
    vrai(a:find('--effort\nmax', 1, true), "l'effort ne change pas avec le modèle")
end)

essai("Moteur : un autre effort dans les préférences relance Claude Code, même modèle ; une valeur inconnue retombe sur celle par défaut", function()
    local prefs = Chemins.prefs()
    local ancien = Moteur.session
    prefs.effort = 'high'
    local ok = Moteur.envoyer('Avec un effort élevé')
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    vrai(ancien ~= Moteur.session, 'relancé')
    local a = arguments()
    vrai(a:find('--resume\nsession-essai', 1, true), 'session reprise')
    vrai(a:find('--model\nsonnet', 1, true), 'même modèle')
    vrai(a:find('--effort\nhigh', 1, true), 'nouvel effort')
    -- Le même effort ne relance rien ; un effort donné à la demande relance Claude Code avec lui.
    local session = Moteur.session
    vrai(Moteur.envoyer('Encore'))
    vrai(attendre(function() return not Moteur.travaille end))
    egal(session, Moteur.session, 'même processus')
    vrai(Moteur.envoyer('Au plus soigné', { effort = 'max' }))
    vrai(attendre(function() return not Moteur.travaille end))
    vrai(session ~= Moteur.session, 'relancé pour un autre effort')
    vrai(arguments():find('--effort\nmax', 1, true), 'effort de la demande')
    -- Préférences d'une autre version : modèle et effort par défaut.
    prefs.modele, prefs.effort = 'claude-ancien', 'enorme'
    local modele, effort = Moteur.modeleEtEffort()
    egal('opus', modele)
    egal('max', effort)
    prefs.modele, prefs.effort = 'opus', 'max'
end)

essai('Moteur : interrompre', function()
    local ok = Moteur.envoyer('Une demande LENT')
    vrai(ok)
    vrai(attendre(function()
        local d = Moteur.courante.elements[#Moteur.courante.elements]
        return d.genre == 'claude' and d.partiel
    end), 'Claude écrit')
    Moteur.interrompre()
    vrai(attendre(function() return not Moteur.travaille end, 15), 'interruption')
    local d = Moteur.courante.elements[#Moteur.courante.elements]
    egal('Interrompu à votre demande.', d.texte)
end)

essai('Moteur : Claude Code qui s\'arrête en pleine demande', function()
    local ok = Moteur.envoyer('ARRETE-TOI')
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end), 'fin constatée')
    local d = Moteur.courante.elements[#Moteur.courante.elements]
    egal('note', d.genre)
    vrai(d.texte:find("s'est arrêté avant de répondre", 1, true) and d.texte:find('panne simulée', 1, true), d.texte)
    egal(nil, Moteur.session)
end)

essai('Moteur : refus pendant le travail, chemins introuvables', function()
    Moteur.travaille = true
    local ok, raison = Moteur.envoyer('x')
    vrai(not ok and raison:find('travaille'))
    vrai(not Moteur.ouvrir('autre'))
    Moteur.travaille = false
    prefs.cheminClaude = '/introuvable/claude'
    ok, raison = Moteur.envoyer('x')
    vrai(not ok and raison:find('introuvable'), raison)
    prefs.cheminClaude = faux
    egal(false, Moteur.travaille)
end)

-- Fenêtre -------------------------------------------------------------------------------------

local Fenetre = require 'Fenetre'
local Lightroom = require 'Lightroom'

-- Toutes les vues de l'arbre.
local function parcourir(vue, fn)
    fn(vue)
    for _, enfant in ipairs(vue.args or {}) do
        if type(enfant) == 'table' and enfant.genre then
            parcourir(enfant, fn)
        end
    end
end

local PROPRIETES = {}
for nom in ([[bind_to_object tooltip visible enabled font size title value items action width height fill fill_horizontal
    fill_vertical place_horizontal place_vertical margin margin_horizontal margin_vertical margin_left margin_right margin_top
    margin_bottom place spacing width_in_chars height_in_lines width_in_digits truncation selectable alignment text_color
    mouse_down immediate validate placeholder_string wraps allows_multiple_selection value_equal frame_width frame_color
    background_color horizontal_scroller vertical_scroller show_title min max precision checked_value unchecked_value
    string_to_value value_to_string photo]]):gmatch('%S+') do
    PROPRIETES[nom] = true
end

essai('Fenêtre : construction, liaisons et rafraîchissement', function()
    S.photoActive = { localIdentifier = 53636309, getFormattedMetadata = function() return 'DSCF4961.RAF' end }
    S.selection = { S.photoActive }
    local vues = 0
    S.pendantFenetre = function(args)
        egal('Développeur', args.title)
        -- Par défaut, la Conversation claire (la plus proche de la 1.0), toujours en grande taille.
        egal('conversation', Fenetre.disposition)
        egal('DeveloppeurClaude-conversation-grande-1', args.save_frame)
        local p = Fenetre.p
        vrai(p, 'table de propriétés')
        Fenetre.rafraichir()
        parcourir(args.contents, function(v)
            vues = vues + 1
            for cle, valeur in pairs(v.args) do
                if type(cle) == 'string' then
                    vrai(PROPRIETES[cle], 'propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                    if type(valeur) == 'table' and valeur.liaison then
                        S.verifierLiaison(valeur, p, v.genre .. '.' .. cle)
                    end
                    if cle == 'font' and type(valeur) == 'table' then
                        vrai(valeur.name and valeur.size, 'police incomplète')
                    end
                end
            end
            if v.genre == 'push_button' then
                vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
            end
        end)
        egal('Flamant rose au zoo', p.titre)
        egal('Active : DSCF4961     Sélection : 1', p.infoPhoto)
        egal('Envoyer', p.titreEnvoyer)
        -- Deux versions en bas à droite : ce module et le connecteur.
        egal('Développeur', p.versionNom1)
        egal('MCP-Développeur', p.versionNom2)
        egal(nil, p.versionNom3, 'deux lignes seulement')
        Fenetre.rafraichirVersions(require('Composants').lignes('1.0', '0.9'))
        egal('MCP-Développeur · à mettre à jour', p.versionNom2)
        egal(true, p.versionAlerte2)
        -- La liaison est lue dans ce module : arrêtée, le voyant est rouge et un clic la démarre.
        local Liaison = require 'Liaison'
        Fenetre.verifier(false)
        egal('Lightroom · liaison arrêtée', p.texteLightroom)
        egal('erreur', p.etatLightroom)
        vrai(p.aide:find('arrêtée', 1, true), p.aide)
        local voyantLiaison
        parcourir(args.contents, function(v)
            if v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.key == 'texteLightroom' then
                voyantLiaison = v
            end
        end)
        vrai(voyantLiaison and voyantLiaison.args.mouse_down, 'voyant de la liaison cliquable')
        local demarrer, demarree = Liaison.demarrer, false
        Liaison.demarrer = function() demarree = true; Liaison.actif = true end
        voyantLiaison.args.mouse_down()
        Liaison.demarrer = demarrer
        vrai(demarree, 'le clic démarre la liaison')
        egal('Lightroom', p.texteLightroom)
        egal('ok', p.etatLightroom)
        egal('', p.aide)
        Liaison.erreur = 'adresse déjà utilisée'
        Fenetre.verifier(false)
        egal('Lightroom · liaison en erreur', p.texteLightroom)
        vrai(p.aide:find('adresse déjà utilisée', 1, true), p.aide)
        -- En erreur, le clic la relance : arrêtée, puis démarrée de nouveau.
        local arreter, relancee = Liaison.arreter, false
        Liaison.arreter = function() Liaison.actif = false end
        Liaison.demarrer = function() relancee = true; Liaison.actif, Liaison.erreur = true, nil end
        voyantLiaison.args.mouse_down()
        Liaison.arreter, Liaison.demarrer = arreter, demarrer
        vrai(relancee, 'le clic relance la liaison en erreur')
        egal('Lightroom', p.texteLightroom)
        Liaison.actif, Liaison.erreur = false, nil
        -- Le mode « Proposer d'abord » est la préférence de la liaison, dans la même table.
        egal('Appliquer directement', p.texteMode)
        Lightroom.basculerMode()
        Fenetre.rafraichirMode()
        egal("Proposer d'abord", p.texteMode)
        egal('proposer', require('Preferences').lire().mode)
        egal('proposer', Chemins.prefs().mode, 'une seule table de préférences')
        Lightroom.basculerMode()
        egal('appliquer', require('Preferences').lire().mode)
        -- Liaison active pour la suite (le bandeau ne montre pas d'aide).
        Liaison.actif = true
        Fenetre.verifier(false)
        -- Plus de bouton Retirer : le bandeau de la ligne du Style dit les photos jointes (un clic
        -- les retire), un message ou l'aide d'un voyant rouge.
        local retirer = false
        parcourir(args.contents, function(v)
            if v.genre == 'push_button' and v.args.title == 'Retirer' then
                retirer = true
            end
        end)
        vrai(not retirer, 'plus de bouton Retirer')
        egal('vide', p.bandeau, 'plus de rappel du style')
        p.jointes = '1 photo jointe : a.png'
        egal('jointes', p.bandeau)
        p.aide = 'La liaison avec Claude est arrêtée.'
        egal('aide', p.bandeau)
        p.message = "Écrivez une demande avant d'envoyer."
        egal('message', p.bandeau)
        p.message, p.aide, p.jointes = '', '', ''
        egal('vide', p.bandeau)
        vrai(#p.listeConversations >= 2, 'en-tête et conversation')
        egal(Moteur.courante.id, p.selectionListe[1])
        local remplies = 0
        for i = 1, Fenetre.T.lignes do
            if p['t' .. i] ~= '' then
                remplies = remplies + 1
            end
        end
        vrai(remplies > 10, 'le fil est rempli (' .. remplies .. ' lignes)')
        -- Défilement.
        local avant = Fenetre.premiere
        Fenetre.defiler(5)
        vrai(Fenetre.premiere <= avant)
        Fenetre.defiler('fin')
        egal(0, Fenetre.defilement)
        -- Retour : Lightroom reprend le texte du champ, qui part tout seul après un court délai.
        local function bouton(titre)
            local trouve
            parcourir(args.contents, function(v)
                local t = v.args.title
                if type(t) == 'table' and t.liaison then
                    t = p[t.key]
                end
                if v.genre == 'push_button' and t == titre then
                    trouve = v
                end
            end)
            return trouve
        end
        local avant = #S.taches
        p.saisie = 'Bonjour'
        egal(avant + 1, #S.taches, 'envoi automatique prévu')
        S.taches[#S.taches]()
        egal('', p.saisie, 'le champ se vide')
        egal(false, p.libre, 'la demande part')
        S.taches[#S.taches]()
        vrai(Moteur.travaille, 'Claude Code reçoit la demande')
        vrai(attendre(function() return not Moteur.travaille end), 'demande envoyée par Retour')
        Fenetre.rafraichir()
        -- Un clic sur 📋 valide aussi le champ : le texte reste, rien ne part.
        avant = #S.taches
        p.saisie = 'Avec une photo'
        bouton('📋').args.action()
        S.taches[avant + 1]()
        egal('Avec une photo', p.saisie, 'le texte reste dans le champ')
        egal(true, p.libre)
        -- Envoyer : une seule demande, même si le clic a aussi validé le champ.
        avant = #S.taches
        p.saisie = 'Encore une'
        bouton('Envoyer').args.action()
        egal('', p.saisie)
        S.taches[avant + 1]()
        egal('', p.message, "pas de second envoi (« Écrivez une demande »)")
        S.taches[#S.taches]()
        vrai(attendre(function() return not Moteur.travaille end), 'demande envoyée par Envoyer')
        -- Recherche sans résultat.
        p.recherche = 'zzzz'
        egal(0, #p.listeConversations, 'aucune conversation trouvée')
        p.recherche = ''
        -- Clic sur une ligne d'aperçu.
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.image then
                Fenetre.cliquerLigne(i)
                break
            end
        end
        vrai(Fenetre.indiceImage ~= nil, "l'aperçu choisi s'affiche")
        vrai(p.legendeApercu:find('sur'), p.legendeApercu)
    end
    Fenetre.afficher()
    require('Liaison').actif = false
    vrai(vues > 300, 'grille du fil construite (' .. vues .. ' vues)')
    egal(false, Fenetre.ouverte)
    egal(nil, Moteur.observateurs.fenetre)
    local c = Moteur.courante
    local demandes = {}
    for _, e in ipairs(c.elements) do
        if e.genre == 'dany' then
            demandes[#demandes + 1] = e.texte
        end
    end
    egal('Encore une', demandes[#demandes])
    egal('Bonjour', demandes[#demandes - 1])
end)

-- Largeur estimée d'une vue, en points : sa largeur donnée, sinon d'après son texte (chasse de
-- Helvetica Neue mesurée, Metriques.lua ; marges des boutons du Mac approchées) ; une rangée
-- additionne ses vues, une colonne prend la plus large.
local function largeurEstimee(v, p)
    local a = v.args
    if type(a.width) == 'number' then
        return a.width
    end
    local petit = a.size == 'small' or (type(a.font) == 'table' and (a.font.size or 13) < 13)
    local function texte(t)
        return Fil.largeur(tostring(t or ''), 'texte') * (petit and 11 / 13 or 1)
    end
    local function titre()
        local t = a.title
        if type(t) == 'table' and t.liaison then
            t = p[t.key]
        end
        return t
    end
    local enfants = {}
    for _, e in ipairs(a) do
        if type(e) == 'table' and e.genre then
            enfants[#enfants + 1] = e
        end
    end
    local g = v.genre
    if g == 'push_button' then
        return texte(titre()) + (petit and 18 or 26)
    elseif g == 'radio_button' or g == 'checkbox' then
        return texte(titre()) + 22
    elseif g == 'static_text' then
        return texte(titre())
    elseif g == 'popup_menu' then
        local items = a.items
        if type(items) == 'table' and items.liaison then
            items = p[items.key]
        end
        local max = 0
        for _, item in ipairs(items or {}) do
            max = math.max(max, texte(item.title))
        end
        return max + 40
    elseif g == 'row' then
        local total = 0
        for _, e in ipairs(enfants) do
            total = total + largeurEstimee(e, p)
        end
        return total + (a.spacing or 8) * math.max(0, #enfants - 1) + 2 * (a.margin or 0)
    elseif g == 'column' or g == 'group_box' then
        local max = 0
        for _, e in ipairs(enfants) do
            max = math.max(max, largeurEstimee(e, p))
        end
        return max + 2 * (a.margin or 0) + (g == 'group_box' and 24 or 0)
    end
    return 0
end

essai('Fenêtre : les trois dispositions', function()
    local Dispositions = require 'Dispositions'
    local prefs = Chemins.prefs()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.photoActive.note, S.photoActive.pickStatus = 2, 0
    S.selection = { S.photoActive }
    local vues = {}
    for _, disposition in ipairs(Dispositions.LISTE) do
        local nom = disposition.value
        prefs.disposition = disposition.value
        local D = Dispositions.dimensions(disposition.value)
        local construite = false
        S.pendantFenetre = function(args)
            construite = true
            local p = Fenetre.p
            egal('Développeur', args.title)
            egal(disposition.value, Fenetre.disposition, nom)
            -- Un cadre enregistré par disposition : Lightroom ne rapetisse pas une fenêtre
            -- rouverte (constaté).
            egal('DeveloppeurClaude-' .. disposition.value .. '-grande-' .. Fenetre.FORME, args.save_frame)
            Fenetre.rafraichir()
            local n, boutons, textes, radios, menus, images, lignes = 0, {}, {}, {}, {}, {}, 0
            parcourir(args.contents, function(v)
                n = n + 1
                for cle, valeur in pairs(v.args) do
                    if type(cle) == 'string' then
                        vrai(PROPRIETES[cle], nom .. ' : propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                        if type(valeur) == 'table' and valeur.liaison then
                            S.verifierLiaison(valeur, p, nom .. ' : ' .. v.genre .. '.' .. cle)
                        end
                        if cle == 'font' and type(valeur) == 'table' then
                            vrai(valeur.name and valeur.size, 'police incomplète')
                        end
                    end
                end
                local titre = v.args.title
                if type(titre) == 'table' and titre.liaison then
                    titre = p[titre.key]
                end
                if v.genre == 'push_button' then
                    vrai(type(v.args.action) == 'function', nom .. ' : bouton sans action : ' .. tostring(titre))
                    -- Le clic d'un bouton valide aussi le champ de demande : tous passent par
                    -- Fenetre.bouton, qui annule l'envoi automatique.
                    vrai(Fenetre.parBouton(v.args.action), nom .. ' : bouton hors de Fenetre.bouton : ' .. tostring(titre))
                    boutons[tostring(titre)] = v
                elseif v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.liaison then
                    textes[v.args.title.key] = textes[v.args.title.key] or v
                    if v.args.title.key:match('^t%d+$') then
                        lignes = lignes + 1
                        egal(D.fil - 20, v.args.width, nom .. ' : largeur des lignes du fil')
                    end
                elseif v.genre == 'radio_button' then
                    radios[#radios + 1] = v.args.checked_value
                    egal('onglet', v.args.value.key)
                elseif v.genre == 'popup_menu' and type(v.args.value) == 'table' then
                    menus[v.args.value.key] = v
                elseif v.genre == 'picture' then
                    images[#images + 1] = v
                end
                -- Les variantes superposées ont la même largeur (une vue masquée garde sa place).
                if v.args.place == 'overlapping' then
                    local largeur
                    for _, e in ipairs(v.args) do
                        if type(e) == 'table' and e.genre and e.args.width then
                            largeur = largeur or e.args.width
                            egal(largeur, e.args.width, nom .. ' : variantes superposées de largeurs différentes')
                        end
                    end
                end
                -- Ce que contient une colonne de largeur donnée y tient (estimation).
                if (v.genre == 'column' or v.genre == 'group_box') and type(v.args.width) == 'number' then
                    local place = v.args.width - (v.genre == 'group_box' and 24 or 0)
                    for _, e in ipairs(v.args) do
                        if type(e) == 'table' and e.genre then
                            local l = largeurEstimee(e, p)
                            vrai(l <= place + 8, string.format('%s : %s de %d points dans une colonne de %d', nom, e.genre, l, place))
                        end
                    end
                end
            end)
            vues[nom] = n
            -- Envoyer et 📋, le voyant de la liaison cliquable, le bandeau, les deux versions.
            vrai(boutons['Envoyer'] and boutons['📋'] and boutons['📎'], nom .. ' : Envoyer, 📋 et 📎')
            vrai(textes.texteLightroom and textes.texteLightroom.args.mouse_down, nom .. ' : voyant de la liaison cliquable')
            local bandeau = 0
            parcourir(args.contents, function(v)
                if v.genre == 'static_text' and type(v.args.visible) == 'table' then
                    for _, k in ipairs(S.cles(v.args.visible)) do
                        bandeau = bandeau + (k == 'bandeau' and 1 or 0)
                    end
                end
            end)
            -- Le Panneau en a un sous les invites et un sous la proposition, l'un ou l'autre montré.
            egal(disposition.value == 'panneau' and 6 or 3, bandeau, nom .. ' : les trois états du bandeau')
            -- Le menu Style, sans étiquette ni rappel : au bout de la rangée des invites quand il y
            -- tient (Sports en est la dernière), sinon sur une rangée à lui.
            local style, rangeeStyle, rangeeSports
            parcourir(args.contents, function(v)
                if v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.key == 'style' then
                    style = v
                elseif v.genre == 'static_text' and (v.args.title == 'Style' or v.args.title == 'Style :') then
                    vrai(false, nom .. ' : étiquette Style')
                elseif v.genre == 'row' then
                    for _, enfant in ipairs(v.args) do
                        if type(enfant) == 'table' and enfant.genre == 'popup_menu' and type(enfant.args.value) == 'table'
                            and enfant.args.value.key == 'style' then
                            rangeeStyle = v
                        elseif type(enfant) == 'table' and enfant.genre == 'push_button' and enfant.args.title == 'Sports' then
                            rangeeSports = v
                        end
                    end
                end
            end)
            vrai(style, nom .. ' : menu Style')
            vrai(rangeeStyle and rangeeStyle == rangeeSports, nom .. ' : Style à droite des invites')
            -- ▲ ▼ de la carte Note et de la proposition, en petit.
            local fleches = {}
            parcourir(args.contents, function(v)
                if v.genre == 'push_button' and (v.args.title == '▲' or v.args.title == '▼') and v.args.size == 'mini' then
                    fleches[#fleches + 1] = v.args.enabled.key
                end
            end)
            table.sort(fleches)
            egal('noteDescend noteMonte propositionDescend propositionMonte', table.concat(fleches, ' '), nom .. ' : flèches des cartes')
            vrai(textes.versionNom1 and textes.versionNom2 and not textes.versionNom3, nom .. ' : deux versions')
            vrai(textes.message and textes.aide, nom .. ' : message et aide')
            -- Le fil : D.lignes lignes, une variante par style.
            egal(D.lignes * #Fenetre.STYLES, lignes, nom .. ' : lignes du fil')
            local remplies = 0
            for i = 1, D.lignes do
                if p['t' .. i] ~= '' then
                    remplies = remplies + 1
                end
            end
            vrai(remplies > 5, nom .. ' : le fil est rempli (' .. remplies .. ' lignes)')
            -- L'aperçu : un cadre fixe, et son image « aucun aperçu » existe à ce format.
            egal(1, #images, nom .. ' : un aperçu')
            egal(D.apercu, images[1].args.width)
            egal(D.apercuHauteur or D.apercu, images[1].args.height)
            vrai(Fichiers.existe(Fenetre.imageVide()), nom .. ' : ' .. Fenetre.imageVide())
            -- Ni modèle, ni effort, ni disposition dans la fenêtre : ils se choisissent dans le
            -- Gestionnaire de modules externes (demandé par Dany le 20 octobre 2026).
            vrai(not menus.modele and not menus.effort and not menus.disposition, nom .. ' : ni modèle, ni effort, ni disposition')
            egal(nil, p.modele)
            egal(nil, p.disposition)
            -- Publication et Consommation, juste au-dessus des versions.
            local ordre = {}
            parcourir(args.contents, function(v)
                local t = v.args.title
                if v.genre == 'push_button' and (t == 'Publication…' or t == 'Consommation…') then
                    ordre[#ordre + 1] = t
                elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'versionNom1' and ordre[#ordre] ~= 'versions' then
                    ordre[#ordre + 1] = 'versions'
                end
            end)
            egal('Publication… Consommation… versions', table.concat(ordre, ' '), nom .. ' : Publication et Consommation au-dessus des versions')
            -- … en bas de leur colonne : l'espace qui grandit au-dessus (Atelier, Conversation
            -- claire) ou le séparateur (Panneau), puis le séparateur et les versions au-dessous.
            local voisins
            parcourir(args.contents, function(v)
                for k, enfant in ipairs(v.args) do
                    if type(enfant) == 'table' and enfant.genre == 'row' and type(enfant.args[1]) == 'table'
                        and enfant.args[1].args.title == 'Publication…' then
                        local function genre(e)
                            if type(e) ~= 'table' or not e.genre then
                                return 'rien'
                            end
                            return e.genre == 'spacer' and e.args.fill_vertical and 'espace' or e.genre
                        end
                        voisins = genre(v.args[k - 1]) .. ' ' .. genre(v.args[k + 1])
                    end
                end
            end)
            egal(disposition.value == 'panneau' and 'separator column' or 'espace separator', voisins, nom .. ' : en bas de la colonne')
            -- La carte Note, avec la note posée de la photo active.
            vrai(textes.notationProposee and textes.notationTexte, nom .. ' : carte Note')
            vrai(boutons['Accepter'] and boutons['Changer…'], nom .. ' : boutons de la note')
            -- Claude note d'abord chaque photo qu'il traite, à vérifier : plus de bouton Évaluer ni
            -- À vérifier (demandé par Dany le 20 octobre 2026).
            egal(nil, boutons['Évaluer'], nom .. ' : plus de bouton Évaluer')
            egal(nil, boutons['Noter'], nom .. ' : plus de bouton Noter')
            egal(nil, boutons['À vérifier'], nom .. ' : plus de bouton À vérifier')
            egal(nil, boutons['Séance…'], nom .. ' : plus de Séance de notation (1.1.1)')
            egal('Note posée : ★★☆☆☆', p.notationPosee)
            egal('DSCF4961', p.notationNom)
            -- Conversations : la liste (Conversation claire), le menu ailleurs.
            if disposition.value == 'conversation' then
                vrai(textes.titre and textes.infoPhoto, nom .. ' : titre et photo active')
                -- Les onglets Note (par défaut) et Proposition en tête, puis l'aperçu, toujours montré,
                -- et la carte choisie sous Agrandir ; plus de « Ce que Claude voit ».
                egal('notation proposition', table.concat(radios, ' '))
                egal('notation', p.onglet, nom .. " : la carte Note sous l'aperçu par défaut")
                egal(nil, images[1].args.visible, nom .. ' : aperçu toujours montré')
                local suite = {}
                parcourir(args.contents, function(v)
                    local t = v.args.title
                    if v.genre == 'picture' then
                        suite[#suite + 1] = 'apercu'
                    elseif v.genre == 'push_button' and t == 'Agrandir' then
                        suite[#suite + 1] = 'agrandir'
                    elseif v.genre == 'radio_button' and v.args.checked_value == 'notation' then
                        suite[#suite + 1] = 'onglets'
                    elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'notationNom' then
                        suite[#suite + 1] = 'note'
                    elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'propositionTexte' then
                        suite[#suite + 1] = 'proposition'
                    elseif v.genre == 'push_button' and t == 'Publication…' then
                        suite[#suite + 1] = 'publication'
                    end
                end)
                egal('onglets apercu agrandir note proposition publication', table.concat(suite, ' '), nom .. ' : colonne de droite')
                parcourir(args.contents, function(v)
                    vrai(v.args.title ~= "Ce que Claude voit", nom .. ' : plus de « Ce que Claude voit »')
                end)
                vrai(#p.listeConversations >= 2, nom .. ' : liste des conversations')
            else
                vrai(menus.conversationChoisie, nom .. ' : menu des conversations')
                vrai(#p.menuConversations >= 1, nom .. ' : conversations du menu')
                egal(Moteur.courante.id, p.conversationChoisie)
                egal(disposition.value == 'panneau' and 'retoucher notation' or '', table.concat(radios, ' '))
            end
            if disposition.value == 'panneau' then
                vrai(largeurEstimee(args.contents, p) <= D.largeur + 24 + 8, nom .. ' : fenêtre étroite')
            end
        end
        Fenetre.afficher()
        vrai(construite, nom .. ' : fenêtre construite')
        egal(false, Fenetre.ouverte)
        egal(nil, Moteur.observateurs.fenetre)
    end
    S.pendantFenetre = nil
    prefs.disposition = nil
    egal('conversation', Chemins.prefs().disposition, 'disposition par défaut')
    vrai(vues.conversation > 300 and vues.atelier > 300 and vues.panneau > 200, 'grilles du fil construites')
end)

essai('Fenêtre : texte JSON rendu lisible', function()
    egal('{\n  "a": 1,\n  "b": [\n    2\n  ]\n}', Fenetre.lisible('{"b":[2],"a":1}'))
    egal('pas du json', Fenetre.lisible('pas du json'))
end)

-- Vérifie l'arbre d'une fenêtre : vues et propriétés connues du SDK, liaisons avec une valeur,
-- boutons avec une action. Rend le nombre de vues.
local function verifierVues(contenu, p)
    local vues = 0
    parcourir(contenu, function(v)
        vues = vues + 1
        for cle, valeur in pairs(v.args) do
            if type(cle) == 'string' then
                vrai(PROPRIETES[cle] or cle == 'checked_value', 'propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                if type(valeur) == 'table' and valeur.liaison then
                    S.verifierLiaison(valeur, p, v.genre .. '.' .. cle)
                end
            end
        end
        if v.genre == 'push_button' then
            vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
        end
    end)
    return vues
end

-- Consommation --------------------------------------------------------------------------------

local Consommation = require 'Consommation'

essai('Consommation : jetons comptés, semaine, budget, jours', function()
    egal(10 + 20 + 30 + 10, Consommation.total({ entree = 10, sortie = 20, cacheCreation = 30, cacheLecture = 100 }))
    egal('1,2 M', Consommation.format(1234567))
    egal('48 k', Consommation.format(48900))
    egal('512', Consommation.format(512))
    local r = Consommation.charger()
    vrai(#r.demandes >= 1, 'les demandes du moteur sont comptées')
    egal(30, Consommation.total(r.demandes[1].usage), 'jetons du faux Claude Code')
    egal('Retouche la photo', r.demandes[1].apercu)
    -- Lundi : le début de la semaine sans relevé du forfait.
    r.limites = nil
    local mercredi = os.time({ year = 2026, month = 10, day = 21, hour = 15 })
    egal(os.time({ year = 2026, month = 10, day = 19, hour = 0 }), Consommation.debutSemaine(mercredi))
    -- Avec le relevé : sept jours avant la reprise.
    r.limites = { repriseSemaine = os.time({ year = 2026, month = 10, day = 25, hour = 10 }) }
    egal(os.time({ year = 2026, month = 10, day = 18, hour = 10 }), Consommation.debutSemaine(mercredi))
    r.limites = nil
    r.demandes = { { date = mercredi - 3600, usage = { sortie = 900000 } }, { date = mercredi - 86400, usage = { sortie = 300000 } },
        { date = mercredi - 10 * 86400, usage = { sortie = 5000000 } } }
    r.budgetSemaine = 2000000
    egal(1200000, Consommation.jetonsSemaine(mercredi))
    egal('normal', Consommation.niveau(mercredi))
    r.budgetSemaine = 1400000
    egal('alerte', Consommation.niveau(mercredi))
    r.budgetSemaine = 1000000
    egal('arret', Consommation.niveau(mercredi))
    local jours = Consommation.parJour(mercredi)
    egal(7, #jours)
    egal(900000, jours[7].jetons)
    egal(300000, jours[6].jetons)
    egal(3, #Consommation.dernieres(12))
    Consommation.releve({ cinqHeures = 0.07, semaine = 0.28 }, mercredi)
    vrai(Consommation.texteReleve():find('^semaine 28 %% · 5 h 7 %%'), Consommation.texteReleve())
    -- Relu du disque.
    Consommation.oublier()
    egal(1000000, Consommation.charger().budgetSemaine)
    egal(3, #Consommation.charger().demandes)
end)

essai('Consommation : budget atteint, la demande est refusée', function()
    local r = Consommation.charger()
    r.budgetSemaine = 10
    r.demandes = { { date = os.time(), usage = { sortie = 50 } } }
    local ok, raison = Moteur.envoyer('Encore une')
    vrai(not ok and raison:find('Budget de la semaine atteint', 1, true), raison)
    egal(false, Moteur.travaille)
    r.budgetSemaine = 0
    vrai(Moteur.texteForfait():find('Forfait', 1, true), Moteur.texteForfait())
end)

essai('Fenêtre Consommation : construction et rafraîchissement', function()
    local FenetreConsommation = require 'FenetreConsommation'
    local r = Consommation.charger()
    r.budgetSemaine = 2000000
    r.demandes = { { date = os.time() - 60, modele = 'claude-opus-5-5', apercu = 'Retouche pro', usage = { sortie = 161000 } } }
    S.pendantFenetre = function(args)
        egal('Claude · Consommation', args.title)
        local p = FenetreConsommation.p
        local vues = verifierVues(args.contents, p)
        vrai(vues > 80, vues .. ' vues')
        egal('161 k sur 2 M', p.semaine)
        egal('Retouche pro', p.apercu1)
        egal('161 k', p.total1)
        vrai(#p.barreSemaine > 0, 'barre de la semaine')
        egal('', p.apercu2)
        p.budget = 5000000
        egal(5000000, Consommation.charger().budgetSemaine)
    end
    FenetreConsommation.afficher()
    egal(false, FenetreConsommation.ouverte)
    egal(nil, Moteur.observateurs.consommation)
    egal('█', FenetreConsommation.barre(0.001, 10), 'une part non nulle se voit')
    egal(string.rep('█', 5), FenetreConsommation.barre(0.5, 10))
    Consommation.changerBudget(0)
end)

-- Publication -----------------------------------------------------------------------------------

local Publication = require 'Publication'

-- Des profils de l'utilisateur, avec filigrane ou poids maximal (les profils proposés n'en ont pas).
local PARTAGE = { nom = 'Partage', format = 'jpeg', qualite = 85, espace = 'srgb', megapixels = 5, filigrane = 'copyright' }
local LEGER = { nom = 'Léger', format = 'jpeg', qualite = 100, espace = 'srgb', poidsMaxKo = 2000 }

essai('Publication : profils proposés, résumés et poids', function()
    local p = Publication.STANDARDS
    local ids = {}
    for _, profil in ipairs(p) do
        ids[#ids + 1] = profil.id
    end
    egal('jpeg-5mpx jpeg-pleine web instagram impression', table.concat(ids, ' '), 'les profils proposés')
    egal('JPEG · qualité 85 · sRGB · 5 Mpx', Publication.resume(p[1]))
    egal('JPEG · qualité 100 · sRGB · pleine taille', Publication.resume(p[2]))
    egal('JPEG · qualité 80 · sRGB · 2048 px', Publication.resume(p[3]))
    egal('JPEG · qualité 85 · sRGB · 4:5, 1080 px', Publication.resume(p[4]))
    egal('TIFF 16 bits · Adobe RVB · pleine taille', Publication.resume(p[5]))
    egal('JPEG · qualité 85 · sRGB · 5 Mpx · filigrane', Publication.resume(PARTAGE))
    egal('JPEG · qualité 100 · sRGB · pleine taille · 2 Mo au plus', Publication.resume(LEGER))
    egal('1,6 Mo', Publication.texteOctets(Publication.poidsEstime(p[1], 26)), 'JPEG 5 Mpx à 85')
    egal(1900000, Publication.poidsEstime(LEGER, 26), 'plafonné à 95 % du poids maximal')
    egal('850 Ko', Publication.texteOctets(850000))
    egal('1,2 Go', Publication.texteOctets(1200000000))
end)

essai('Publication : réglages de LrExportSession', function()
    local r = Publication.reglages(Publication.STANDARDS[1], '/Publications', nil, { retirerLieu = true })
    egal('specificFolder', r.LR_export_destinationType)
    egal('rename', r.LR_collisionHandling, "jamais d'écrasement")
    egal('JPEG', r.LR_format)
    egal(0.85, r.LR_jpeg_quality)
    egal('megapixels', r.LR_size_resizeType)
    egal(5, r.LR_size_megapixels)
    egal(true, r.LR_removeLocationMetadata)
    egal('all', r.LR_embeddedMetadataOption)
    egal(false, r.LR_useWatermark)
    vrai(getmetatable(r) == nil, 'table neuve pour Lightroom')
    r = Publication.reglages(Publication.STANDARDS[5], '/L', 'Impression', { droitsSeulement = true, retirerLieu = false })
    egal('TIFF', r.LR_format)
    egal('AdobeRGB', r.LR_export_colorSpace)
    egal(16, r.LR_export_bitDepth)
    egal(true, r.LR_export_useSubfolder)
    egal('Impression', r.LR_export_destinationPathSuffix)
    egal('copyrightOnly', r.LR_embeddedMetadataOption)
    egal(false, r.LR_removeLocationMetadata)
    r = Publication.reglages(PARTAGE, '/L', nil, {})
    egal(true, r.LR_useWatermark, 'filigrane du profil')
    egal('<simpleCopyrightWatermark>', r.LR_watermarking_id)
    r = Publication.reglages(PARTAGE, '/L', nil, { filigrane = false })
    egal(false, r.LR_useWatermark, 'filigrane retiré')
    local dateNom = Publication.jeton('date_YYYYMMDD') .. '-' .. Publication.jeton('image_name')
    r = Publication.reglages(LEGER, '/L', nil, { jetons = dateNom })
    egal(true, r.LR_jpeg_useLimitSize)
    egal(2000, r.LR_jpeg_limitSize)
    egal(true, r.LR_renamingTokensOn)
    egal(dateNom, r.LR_tokens)
    r = Publication.reglages(Publication.STANDARDS[3], '/L')
    egal('longEdge', r.LR_size_resizeType)
    egal(2048, r.LR_size_maxWidth)
end)

essai('Publication : modèles de noms de Lightroom', function()
    local modele = [[s = {
	deflated = {
		{
			{
				value = "date_YYYYMMDD",
			},
			"-",
			{
				value = "image_name",
			},
			name = "Date - Filename",
			presetType = "Naming",
		},
		"AgTokenPresets",
	},
	title = ZSTR "$$$/TokenPresets/Naming/Title/DateFilename=Date - Filename",
}]]
    egal(string.rep('{', 2) .. 'date_YYYYMMDD' .. string.rep('}', 2) .. '-' .. string.rep('{', 2) .. 'image_name' .. string.rep('}', 2),
        Publication.jetons(modele))
    local dossier = S.home .. '/Filename Templates'
    Fichiers.ecrire(dossier .. '/Date - Nom du fichier.lrtemplate', modele)
    Fichiers.ecrire(dossier .. '/Nom personnalisé - Séquence.lrtemplate',
        (modele:gsub('date_YYYYMMDD', 'custom_token'):gsub('image_name', 'naming_sequenceNumber_1Digit')))
    Fichiers.ecrire(dossier .. '/Nom de la prise de vue.lrtemplate', (modele:gsub('date_YYYYMMDD', 'shoot_custom_token')))
    local modeles = Publication.modelesNoms(dossier)
    egal(2, #modeles, 'sans celui de la prise de vue')
    egal('Date - Nom du fichier', modeles[1].nom)
    vrai(not modeles[1].texte and modeles[2].texte and modeles[2].sequence)
    local noms = Publication.noms({ S.photo(1, 'DSCF4961.RAF') }, modeles[1], '')
    egal('DSCF4961.RAF', noms[1].origine)
    egal('ID-DATE-DSCF4961-1', noms[1].nom)
    local _, erreur = Publication.noms({}, { nom = 'Inconnu' }, '')
    vrai(erreur and erreur:find('Inconnu', 1, true))
end)

essai('Publication : profils de l\'utilisateur', function()
    local p = Publication.ajouterProfil({ nom = 'Agence', format = 'jpeg', qualite = 90, espace = 'srgb', grandCote = 3000 })
    local profils = Publication.profils()
    egal(#Publication.STANDARDS + 1, #profils)
    egal('Agence', profils[#profils].nom)
    vrai(profils[#profils].perso)
    Publication.supprimerProfil(p.id)
    egal(#Publication.STANDARDS, #Publication.profils())
end)

essai('Publication : dossier et exportation (simulée)', function()
    egal(nil, (Publication.preparerDossier('Publications')))
    egal(nil, (Publication.preparerDossier('/introuvable/disque/Publications')))
    Fichiers.creerDossier(S.home .. '/Pictures')
    local dossier = Publication.preparerDossier(S.home .. '/Pictures/Publications')
    vrai(Fichiers.existe(dossier), 'dossier créé')
    local photos = { S.photo(1, 'A.RAF'), S.photo(2, 'B.RAF') }
    -- A n'a été exportée que par un aperçu de Claude (Rendu.lua) : publiée, elle l'est pour de bon.
    photos[1].proprietes.apercuSeulement = 'oui'
    S.calculsIA = 0
    S.ecrituresPrivees = 0
    local bilan = Publication.publier({ Publication.STANDARDS[1], Publication.STANDARDS[3] }, photos, dossier, { retirerLieu = true })
    egal(2, #bilan)
    egal(2, bilan[1].fichiers)
    egal(dossier .. '/JPEG 5 Mpx', bilan[1].dossier, 'un sous-dossier par format')
    vrai(Fichiers.existe(dossier .. '/Web/B.jpg'))
    egal(2, S.calculsIA, 'réglages IA calculés avant le rendu')
    egal(nil, photos[1].proprietes.apercuSeulement, 'publiée : plus « exportée en aperçu seulement »')
    egal(1, S.ecrituresPrivees, 'une seule écriture, privée (hors de Édition › Annuler), pour les deux profils')
    -- Sans fichier publié, le champ reste, et rien ne s'écrit.
    photos[2].proprietes.apercuSeulement = 'oui'
    S.echecRendu = 'original introuvable'
    bilan = Publication.publier({ Publication.STANDARDS[1] }, photos, dossier, {})
    egal(0, bilan[1].fichiers)
    egal('original introuvable', bilan[1].erreurs[1])
    egal('oui', photos[2].proprietes.apercuSeulement, 'pas publiée : le champ reste')
    egal(1, S.ecrituresPrivees)
    S.echecRendu = nil
end)

essai('Fenêtre Publication : construction, choix et publication', function()
    local FenetrePublication = require 'FenetrePublication'
    S.photoActive = S.photo(53636013, 'DSCF4961.RAF')
    S.selection = { S.photoActive }
    prefs.dossierPublication = S.home .. '/Pictures/Publications'
    S.reponseConfirm = 'ok'
    S.exports = {}
    local partage = Publication.ajouterProfil({ nom = 'Partage', format = 'jpeg', qualite = 85, espace = 'srgb', megapixels = 5, filigrane = 'copyright' })
    S.pendantFenetre = function(args)
        egal('Claude · Publication', args.title)
        local p = FenetrePublication.p
        local vues = verifierVues(args.contents, p)
        vrai(vues > 50, vues .. ' vues')
        egal('1 photo(s) sélectionnée(s) dans Lightroom.', p.textePhotos)
        egal('Publier 1 photo', p.titrePublier)
        egal('1,6 Mo', p.poids)
        vrai(p.peutPublier)
        egal(900, p.collection, "collection d'essai proposée")
        egal('Développeur › Essais', p.collections[1].title)
        -- Plusieurs formats.
        p.plusieurs = true
        p['choisi_web'] = true
        FenetrePublication.recalculer()
        egal('Publier 1 photo × 2', p.titrePublier)
        -- Un profil de l'utilisateur avec filigrane : le filigrane suit.
        p.plusieurs = false
        p.profil = partage.id
        egal(true, p.filigrane)
        FenetrePublication.recalculer()
        egal(true, p.profilPerso, "un profil de l'utilisateur se supprime")
        p.profil = 'jpeg-5mpx'
        egal(false, p.filigrane)
        -- Photo active.
        p.portee = 'active'
        FenetrePublication.recalculer()
        egal('DSCF4961.RAF', p.textePhotos)
        FenetrePublication.publier()
        vrai(p.bilan:find('JPEG 5 Mpx : 1 fichier', 1, true), p.bilan)
        egal(true, p.aDossier)
        egal(1, #S.exports)
        egal('rename', S.exports[1].args.exportSettings.LR_collisionHandling)
    end
    FenetrePublication.afficher()
    egal(false, FenetrePublication.ouverte)
    S.reponseConfirm = nil
    Publication.supprimerProfil(partage.id)
end)

-- Presse-papiers ------------------------------------------------------------------------------

local Images = require 'Images'

essai('Coller : image et fichier du presse-papiers (presse-papiers nommé, jamais le vrai)', function()
    local nom = 'DeveloppeurEssai'
    local function osa(code)
        return S.executer("/usr/bin/osascript -l JavaScript -e " .. S.q("ObjC.import('AppKit'); var pp = $.NSPasteboard.pasteboardWithName('" .. nom .. "'); pp.clearContents; " .. code .. "; 'ok'") .. " >/dev/null")
    end
    local png = S.plugin .. '/vide-320.png'
    vrai(osa("pp.setDataForType($.NSData.dataWithContentsOfFile('" .. png .. "'), 'public.png')"))
    local chemins = Images.coller(nom)
    egal(1, #chemins)
    vrai(chemins[1]:find('/Collees/collee%-%d+%.png$'), chemins[1])
    vrai(osa("pp.writeObjects($.NSArray.arrayWithObject($.NSURL.fileURLWithPath('" .. png .. "')))"))
    chemins = Images.coller(nom)
    egal(png, chemins[1])
    vrai(osa("pp.setStringForType('du texte', 'public.utf8-plain-text')"))
    egal(0, #Images.coller(nom))
    osa("pp.releaseGlobally")
end)

-- Raccourcis ----------------------------------------------------------------------------------

essai('Raccourcis : posés dans un fichier d\'essai, jamais dans les préférences de Lightroom', function()
    local Raccourcis = require 'Raccourcis'
    -- defaults accepte un chemin complet : le fichier raccourcis-essai.plist du dossier d'essai.
    local domaine = S.home .. '/raccourcis-essai'
    vrai(Raccourcis.poser(domaine))
    local lu = S.lireCommande('/usr/bin/defaults read ' .. domaine .. ' NSUserKeyEquivalents')
    -- Le titre tel que Lightroom l'écrit dans son menu : trois espaces devant.
    vrai(lu:find('"   Ouvrir la fen', 1, true) and lu:find('"^~c"', 1, true), lu)
    vrai(not lu:find('"^~p"', 1, true) and not lu:find('"^~u"', 1, true), 'seulement la fenêtre Claude')
    -- Un raccourci déjà là reste.
    S.executer('/usr/bin/defaults write ' .. domaine .. ' NSUserKeyEquivalents -dict-add Autre "@~x"')
    vrai(Raccourcis.poser(domaine))
    vrai(S.lireCommande('/usr/bin/defaults read ' .. domaine .. ' NSUserKeyEquivalents'):find('Autre', 1, true))
    egal('⌃⌥C fenêtre Claude', Raccourcis.texte())
    egal('Ouvrir la fenêtre Claude', Raccourcis.LISTE[1].titre, "le titre de l'entrée de menu")
    local titres = {}
    for _, entree in ipairs(require('Info').LrExportMenuItems) do
        titres[entree.title] = true
    end
    vrai(titres[Raccourcis.LISTE[1].titre], 'le raccourci vise une entrée du menu')
end)

-- Versions ------------------------------------------------------------------------------------

essai('Versions : lecture, comparaison et alerte', function()
    local Composants = require 'Composants'
    egal('1.0', Composants.formater(1, 0, 0))
    egal('1.3.1', Composants.formater(1, 3, 1))
    egal('1.0', Composants.depuisSortie('1.0\n'))
    egal(nil, Composants.depuisSortie('--version\n'))
    egal(-1, Composants.comparer('1.0', '1.1'))
    egal(0, Composants.comparer('1.0', '1.0.0'))
    egal(1, Composants.comparer('1.10', '1.9'))
    egal('1.1.1', Composants.module(), 'la version de Info.lua')
    -- Deux lignes : ce module et le connecteur, installés ensemble au même numéro.
    local l = Composants.lignes('1.0', '1.0')
    egal(2, #l)
    egal('Développeur', l[1].nom)
    egal('MCP-Développeur', l[2].nom)
    vrai(not l[1].alerte and not l[2].alerte, "mêmes versions : pas d'alerte")
    l = Composants.lignes('1.0', '0.9')
    egal('MCP-Développeur · à mettre à jour', l[2].nom)
    vrai(l[2].alerte and not l[1].alerte)
    l = Composants.lignes('1.0', '1.1')
    egal('Développeur · à mettre à jour', l[1].nom)
    vrai(l[1].alerte and not l[2].alerte)
    l = Composants.lignes('1.0', nil)
    egal('MCP-Développeur · introuvable', l[2].nom)
    vrai(l[2].alerte)
    l = Composants.lignes('1.0', '…')
    vrai(not l[1].alerte and not l[2].alerte, 'version pas encore lue : pas comparée')
    -- Le connecteur : un faux qui répond à --version.
    local faux = S.home .. '/mcp-developpeur'
    Fichiers.ecrire(faux, '#!/bin/sh\necho 1.0\n')
    S.executer('chmod +x ' .. S.q(faux))
    egal('1.0', Composants.connecteur(faux))
    egal(nil, Composants.connecteur(S.home .. '/introuvable'))
    -- Chemin par défaut : à côté des données du module.
    vrai(Chemins.connecteurParDefaut():find('/Library/Application Support/Developpeur/mcp%-developpeur$'), Chemins.connecteurParDefaut())
    vrai(Chemins.journal():find('/Library/Logs/Developpeur/conversation%.log$'), Chemins.journal())
    vrai(Chemins.claudeParDefaut():find('/%.local/bin/claude$') or Chemins.claudeParDefaut():find('/claude$'), Chemins.claudeParDefaut())
end)

essai('Chemins : Claude Code installé après le module', function()
    local connus = Chemins.claudesConnus()
    egal(S.home .. '/.local/bin/claude', connus[1])
    -- Le chemin rangé au premier lancement, quand Claude Code n'était pas encore installé : un
    -- chemin connu, absent (Homebrew ici, s'il n'est pas sur ce Mac).
    local absent
    for i = 2, #connus do
        if not absent and not Fichiers.existe(connus[i]) then
            absent = connus[i]
        end
    end
    Fichiers.creerDossier(S.home .. '/.local/bin')
    Fichiers.ecrire(connus[1], '#!/bin/sh\n')
    if absent then
        prefs.cheminClaude = absent
        egal(connus[1], Chemins.prefs().cheminClaude, 'Claude Code installé ensuite ailleurs : trouvé')
    end
    -- Un chemin connu qui existe reste, comme un chemin choisi par l'utilisateur, même absent.
    egal(connus[1], Chemins.prefs().cheminClaude)
    prefs.cheminClaude = S.home .. '/ailleurs/claude'
    egal(S.home .. '/ailleurs/claude', Chemins.prefs().cheminClaude, 'choisi par l\'utilisateur : gardé')
    os.remove(connus[1])
    prefs.cheminClaude = faux
end)

-- Styles --------------------------------------------------------------------------------------

essai('Styles : ligne jointe à la demande et rappel dans le fil', function()
    local Consignes = require 'Consignes'
    egal(7, #Consignes.styles)
    egal('Standard', Consignes.styles[1].title)
    egal(nil, Consignes.ligneStyle('standard'), 'Standard n\'ajoute rien')
    egal(nil, Consignes.ligneStyle('aucun'), 'plus de style « Aucun »')
    egal(nil, Consignes.ligneStyle('inconnu'))
    egal('[Style demandé : Or et peau douce — tons dorés chaleureux, peau adoucie (texture et clarté réduites sur la peau seulement), contraste doux]',
        Consignes.ligneStyle('or_peau_douce'))
    local c = Conversation.nouvelle()
    local m = Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', Consignes.ligneStyle('neutre'))
    vrai(m:find('^%[Lightroom : x%]\n\n%[Style demandé : Neutre'), m)
    Conversation.ajouterDemande(c, 'Retouche', nil, nil, 'Neutre')
    local lignes = Fil.lignes(c, 500)
    egal('Style : Neutre', lignes[2].texte)
    egal('note', lignes[2].genre)
    vrai(Consignes.texte:find('## Style', 1, true), 'consigne du style')
end)

essai('Styles : le moteur joint le style choisi', function()
    local ok = Moteur.envoyer('Avec un style', { style = 'ambre_eclat' })
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    local entree = Fichiers.lire(Moteur.session.dossier .. '/entree.jsonl')
    vrai(entree:find('Style demandé : Ambre et éclat', 1, true), 'ligne de style envoyée')
    local d
    for _, e in ipairs(Moteur.courante.elements) do
        if e.genre == 'dany' then d = e end
    end
    egal('Ambre et éclat', d.style)
    ok = Moteur.envoyer('Sans style', { style = 'standard' })
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    for _, e in ipairs(Moteur.courante.elements) do
        if e.genre == 'dany' then d = e end
    end
    egal(nil, d.style)
end)

-- Chargement et arrêt du module -------------------------------------------------------------

essai('Arret.lua : Claude Code est fermé avec le module (la liaison aussi)', function()
    local ok = Moteur.envoyer('Avant l\'arrêt')
    vrai(ok)
    vrai(attendre(function() return not Moteur.travaille end))
    local s = Moteur.session
    vrai(s and s:actif(), 'Claude Code ouvert')
    dofile(S.plugin .. '/Arret.lua')
    egal(nil, Moteur.session, 'session fermée')
    egal(false, Moteur.boucle)
    vrai(Fichiers.existe(s.dossier .. '/arreter'), 'relais.sh prié de fermer Claude Code')
    vrai(attendre(function() return Fichiers.existe(s.dossier .. '/fin.code') end, 8), 'Claude Code fermé')
    egal(false, require('Liaison').actif)
end)

essai("Init.lua : les sessions d'une séance précédente sont fermées ou effacées", function()
    local finie = Chemins.sessions() .. '/ancienne-1-1'
    local ouverte = Chemins.sessions() .. '/ancienne-2-1'
    Fichiers.ecrire(finie .. '/fin.code', '0')
    Fichiers.ecrire(ouverte .. '/entree.jsonl', '')
    -- La liaison ne démarre pas ici (ses prises ne sont pas simulées).
    prefs.demarrerAuLancement = false
    local avant = #S.taches
    dofile(S.plugin .. '/Init.lua')
    egal(avant + 1, #S.taches, 'le ménage des sessions dans une tâche')
    S.taches[#S.taches]()
    egal(false, Fichiers.existe(finie), 'session finie effacée')
    vrai(Fichiers.existe(ouverte .. '/arreter'), 'session encore ouverte priée de fermer')
    egal(false, require('Liaison').actif)
end)

-- Fin -----------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
