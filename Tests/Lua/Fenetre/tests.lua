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
    c.elements[2].date, c.elements[3].date, c.elements[4].date = c.elements[1].date + 60, c.elements[1].date + 61, c.elements[1].date + 62
    local cache = {}
    local lignes = Fil.lignes(c, 500, cache)
    egal('dany', lignes[1].genre)
    -- Plus de › devant Dany : la colonne auteur dit « Vous », l'heure dessous (fenêtre B).
    egal(nil, lignes[1].icone)
    egal('dany', lignes[1].auteur)
    egal('vide', lignes[2].genre)
    egal(Fil.heure(c.elements[1].date), lignes[2].heure, "l'heure sur la ligne suivante, vide comprise")
    -- La ligne d'un appel : le nom de l'outil en texte riche (Menlo), l'icône, le tour de Claude.
    egal('appel', lignes[3].genre)
    egal('<EM>view_photo</EM>', lignes[3].texte)
    egal('ok', lignes[3].icone)
    egal('claude', lignes[3].auteur)
    egal('apercu', lignes[4].genre, 'outil et aperçu collés')
    egal('image-1.jpg', lignes[4].image)
    egal(Fil.heure(c.elements[2].date), lignes[4].heure, "l'heure du premier élément du tour")
    egal('vide', lignes[5].genre)
    egal('Passe 1 vérifiée.', lignes[6].texte)
    egal(nil, lignes[6].auteur, 'le même tour : pas de nouvel auteur')
    egal('titre', lignes[8].genre)
    -- Le cache rend les mêmes lignes ; auteur et heure ne sont que sur des copies.
    egal(#lignes, #Fil.lignes(c, 500, cache))
    for _, garde in pairs(cache) do
        for _, l in ipairs(garde.lignes) do
            vrai(l.auteur == nil and l.heure == nil, 'ni auteur ni heure dans le cache : ' .. tostring(l.texte))
        end
    end
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
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out '
    .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
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
-- Non documentés, constatés le 21 octobre 2026 dans Lightroom Classic 15.6 (module d'essai de la
-- fenêtre B) : texte riche d'une static_text (B1, D4), bouton par défaut (B3, D1), icône d'un
-- bouton (B3, D5).
for _, nom in ipairs({ 'emphasis_font', 'emphasis_color', 'default', 'image_name' }) do
    PROPRIETES[nom] = true
end

-- La première vue de l'arbre dont l'infobulle est `infobulle` (un bouton à icône seule, un calque).
local function parInfobulle(contenu, infobulle)
    for _, v in ipairs(S.vues(contenu)) do
        if v.args.tooltip == infobulle then
            return v
        end
    end
    error('vue introuvable par son infobulle : ' .. tostring(infobulle), 2)
end

-- Le calque d'Envoyer (Vues.boutonBleu) : la seule vue qui en prend le clic.
local INFOBULLE_ENVOYER = "Envoyer la demande à Claude (Retour dans le champ aussi)"
local INFOBULLE_COLLER = "Coller l'image du presse-papiers (capture d'écran, image copiée, photo copiée dans le Finder)"

-- Les cases de la liste des conversations qui en montrent une (genre 'conversation').
local function casesConversations()
    local n = 0
    for _, case in ipairs(Fenetre.cases or {}) do
        if case.genre == 'conversation' then
            n = n + 1
        end
    end
    return n
end

essai('Fenêtre : construction, liaisons et rafraîchissement', function()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.photoActive.copie = 'Essai'
    S.selection = { S.photoActive }
    local vues = 0
    S.pendantFenetre = function(args)
        egal('Développeur', args.title)
        -- La Conversation claire, seule disposition, toujours en grande taille (fenêtre B agrandie :
        -- FORME 3).
        egal('DeveloppeurClaude-conversation-grande-3', args.save_frame)
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
            if S.BOUTONS[v.genre] then
                vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
            end
        end)
        egal('Flamant rose au zoo', p.titre)
        -- La photo active, nom de sa copie compris (Lightroom.legende), en texte riche.
        egal('Active : <EM>DSCF4961.RAF (Essai)</EM> · Sélection : <EM>1</EM>', p.infoPhoto)
        egal(nil, p.titreEnvoyer, "plus de titre lié d'Envoyer (Arrêter est superposé)")
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
        -- Le voyant Écran : gris tant que le connecteur ne l'a pas dit (Fenetre.verifier(true), dans
        -- la tâche de l'ouverture, pas encore lancée ici).
        egal('Écran', p.texteEcran)
        egal('neutre', p.etatEcran)
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
        -- Le mode « Proposer d'abord » est la préférence de la liaison, dans la même table ; le
        -- Mode de l'en-tête la montre (plus de voyant Mode).
        egal('appliquer', p.mode)
        egal(nil, p.texteMode, 'plus de voyant Mode')
        Lightroom.basculerMode()
        Fenetre.rafraichirMode()
        egal('proposer', p.mode)
        egal('proposer', require('Preferences').lire().mode)
        egal('proposer', Chemins.prefs().mode, 'une seule table de préférences')
        Lightroom.basculerMode()
        Fenetre.rafraichirMode()
        egal('appliquer', require('Preferences').lire().mode)
        egal('appliquer', p.mode)
        -- Liaison active pour la suite (le bandeau ne montre pas d'aide).
        Liaison.actif = true
        Fenetre.verifier(false)
        -- Plus de bouton Retirer : le bandeau de la ligne du Style dit les photos jointes (un clic
        -- les retire), un message ou l'aide d'un voyant rouge.
        local retirer = false
        parcourir(args.contents, function(v)
            if S.BOUTONS[v.genre] and v.args.title == 'Retirer' then
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
        -- La liste en cases : l'entrée du carnet, l'en-tête du jour, la conversation, choisie.
        egal('carnet', p.lg1)
        egal('jour', p.lg2)
        egal("Aujourd'hui", p.lt2)
        vrai(casesConversations() >= 1, 'une conversation dans la liste')
        egal(Moteur.courante.id, Fenetre.choixListe())
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
        -- Un clic sur 📋 valide aussi le champ : le texte reste, rien ne part (sa tâche ne tourne
        -- pas : elle lirait le presse-papiers).
        avant = #S.taches
        p.saisie = 'Avec une photo'
        parInfobulle(args.contents, INFOBULLE_COLLER).args.action()
        S.taches[avant + 1]()
        egal('Avec une photo', p.saisie, 'le texte reste dans le champ')
        egal(true, p.libre)
        -- Envoyer (un bouton bleu en image, son calque) : une seule demande, même si le clic a aussi
        -- validé le champ.
        avant = #S.taches
        p.saisie = 'Encore une'
        local envoyer = parInfobulle(args.contents, INFOBULLE_ENVOYER)
        egal('static_text', envoyer.genre, 'Envoyer : un calque')
        envoyer.args.mouse_down()
        egal('', p.saisie)
        egal(true, p.bleuEnfonceEnvoyer, "l'image enfoncée")
        S.taches[avant + 1]()
        egal('', p.message, "pas de second envoi (« Écrivez une demande »)")
        S.taches[#S.taches]()
        vrai(attendre(function() return not Moteur.travaille end), 'demande envoyée par Envoyer')
        -- Recherche sans résultat.
        p.recherche = 'zzzz'
        egal(0, casesConversations(), 'aucune conversation trouvée')
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
-- Helvetica Neue mesurée, Metriques.lua, ramenée à la taille de la police ; marges des boutons du
-- Mac approchées) ; une rangée additionne ses vues, une colonne prend la plus large, ses marges
-- comprises.
local function largeurEstimee(v, p)
    local a = v.args
    local marges = (a.margin_left or a.margin or 0) + (a.margin_right or a.margin or 0)
    if type(a.width) == 'number' then
        return a.width
    end
    local taille = (type(a.font) == 'table' and a.font.size) or ((a.size == 'small' or a.size == 'mini') and 11) or 13
    local petit = taille < 13
    local function texte(t)
        return Fil.largeur(tostring(t or ''):gsub('</?EM>', ''), 'texte') * taille / 13
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
    if S.BOUTONS[g] then
        if a.image_name then
            return 28
        end
        return texte(titre()) + (petit and 18 or 26)
    elseif g == 'radio_button' or g == 'checkbox' then
        return texte(titre()) + 22
    elseif g == 'static_text' then
        return texte(titre())
    elseif g == 'spacer' then
        return 0
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
    elseif g == 'row' and a.place ~= 'overlapping' then
        local total = 0
        for _, e in ipairs(enfants) do
            total = total + largeurEstimee(e, p)
        end
        return total + (a.spacing or 8) * math.max(0, #enfants - 1) + marges
    elseif g == 'row' or g == 'column' or g == 'group_box' then
        local max = 0
        for _, e in ipairs(enfants) do
            max = math.max(max, largeurEstimee(e, p))
        end
        return max + marges + (g == 'group_box' and 24 or 0)
    end
    return 0
end

-- Les textes cliquables de la fenêtre qui ne sont pas des calques (Fenetre.calque) : les lignes du
-- fil, les voyants et le bandeau, chacun avec son propre mouse_down, qui annule l'envoi
-- automatique.
local function texteCliquable(v)
    local t = v.args.title
    local cle = type(t) == 'table' and t.liaison and (t.key or '') or ''
    return cle:match('^t%d+$') or cle == 'texteLightroom' or cle == 'texteEcran' or cle == 'aide'
        or (cle == 'jointes')
end

essai('Fenêtre : la Conversation claire, seule disposition', function()
    local Dispositions = require 'Dispositions'
    local prefs = Chemins.prefs()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.photoActive.note, S.photoActive.pickStatus = 2, 0
    S.selection = { S.photoActive }
    local vues = {}
    local nom = 'conversation'
    local D = Dispositions.dimensions()
    local construite = false
    S.pendantFenetre = function(args)
        construite = true
        local p = Fenetre.p
        egal('Développeur', args.title)
        -- Le cadre enregistré garde son nom (Lightroom ne rapetisse pas une fenêtre rouverte,
        -- constaté) : celui de la Conversation claire en grande taille, FORME 3 (fenêtre B agrandie).
        egal('DeveloppeurClaude-conversation-grande-' .. Fenetre.FORME, args.save_frame)
        egal(3, Fenetre.FORME)
        Fenetre.rafraichir()
        local n, boutons, textes, radios, menus, lignes, calques = 0, {}, {}, {}, {}, 0, 0
        local apercu
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
            if S.BOUTONS[v.genre] then
                vrai(type(v.args.action) == 'function', nom .. ' : bouton sans action : ' .. tostring(titre))
                -- Le clic d'un bouton valide aussi le champ de demande : tous passent par
                -- Fenetre.bouton, qui annule l'envoi automatique.
                vrai(Fenetre.parBouton(v.args.action), nom .. ' : bouton hors de Fenetre.bouton : ' .. tostring(titre))
                boutons[tostring(titre or v.args.tooltip)] = v
            elseif v.genre == 'static_text' and type(v.args.mouse_down) == 'function' then
                -- Un clic sur un texte : un calque (Fenetre.calque), ou un texte cliquable connu.
                if Fenetre.parCalque(v.args.mouse_down) then
                    calques = calques + 1
                    egal('', v.args.title, nom .. ' : un calque est un texte vide')
                    vrai(type(v.args.width) == 'number' and type(v.args.height) == 'number', nom .. ' : un calque de taille fixe')
                else
                    vrai(texteCliquable(v), nom .. ' : clic sur un texte hors de Fenetre.calque')
                end
            end
            if v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.liaison then
                textes[v.args.title.key] = textes[v.args.title.key] or v
                if v.args.title.key:match('^t%d+$') then
                    lignes = lignes + 1
                    -- Le texte de la ligne (fenêtre B : la largeur utile du centre, après la colonne
                    -- auteur et son écart), moins le retrait d'un genre à icône (Fil.RETRAITS).
                    local largeurs = { [D.texteFil] = true, [D.texteFil - Fil.RETRAIT_ICONE] = true }
                    egal(D.fil - D.auteur - D.ecartAuteur, D.texteFil, nom .. ' : texte du fil (D.fil − auteur − écart)')
                    vrai(largeurs[v.args.width], nom .. ' : largeur des lignes du fil : ' .. tostring(v.args.width))
                end
            elseif v.genre == 'radio_button' then
                radios[#radios + 1] = v.args.checked_value
                egal('mode', v.args.value.key, nom .. ' : les seuls radios sont ceux du Mode')
            elseif v.genre == 'popup_menu' and type(v.args.value) == 'table' then
                menus[v.args.value.key] = v
            elseif v.genre == 'picture' and type(v.args.value) == 'table' and v.args.value.key == 'imageApercu' then
                apercu = v
            end
            -- Aucun bouton par défaut (repli du lot B0) ; aucun séparateur (des aplats).
            egal(nil, v.args.default, nom .. ' : bouton par défaut')
            vrai(v.genre ~= 'separator' or v.args.fill_horizontal, nom .. ' : séparateur hors des cartes')
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
        egal(nil, S.boutonParDefaut(), nom .. ' : aucun bouton par défaut')
        -- Envoyer (calque d'un bouton bleu), 📋 et 📎 (carrés à icône seule), le voyant de la liaison
        -- cliquable, le bandeau, les deux versions.
        vrai(parInfobulle(args.contents, INFOBULLE_ENVOYER) and boutons[INFOBULLE_COLLER]
            and boutons["Joindre une photo du disque à la demande"], nom .. ' : Envoyer, 📋 et 📎')
        egal('square_button', boutons[INFOBULLE_COLLER].genre)
        vrai(boutons[INFOBULLE_COLLER].args.image_name:find('/images/presse%-papiers%.png$'), nom .. " : l'icône de 📋")
        vrai(textes.texteLightroom and textes.texteLightroom.args.mouse_down, nom .. ' : voyant de la liaison cliquable')
        vrai(calques >= D.cases + #D.onglets + 1, nom .. ' : calques des cases, des segments et d\'Envoyer (' .. calques .. ')')
        local bandeau = 0
        parcourir(args.contents, function(v)
            if v.genre == 'static_text' and type(v.args.visible) == 'table' then
                for _, k in ipairs(S.cles(v.args.visible)) do
                    bandeau = bandeau + (k == 'bandeau' and 1 or 0)
                end
            end
        end)
        egal(3, bandeau, nom .. ' : les trois états du bandeau')
        -- Le menu Style, sous le champ, précédé de son étiquette « Style » (maquette), et plus au
        -- bout de la rangée des invites.
        local style, rangeeStyle, rangeeSports
        parcourir(args.contents, function(v)
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.key == 'style' then
                style = v
            elseif v.genre == 'row' then
                for _, enfant in ipairs(v.args) do
                    if type(enfant) == 'table' and enfant.genre == 'popup_menu' and type(enfant.args.value) == 'table'
                        and enfant.args.value.key == 'style' then
                        rangeeStyle = v
                    elseif type(enfant) == 'table' and S.BOUTONS[enfant.genre] and enfant.args.title == 'Sports' then
                        rangeeSports = v
                    end
                end
            end
        end)
        vrai(style, nom .. ' : menu Style')
        vrai(rangeeStyle and rangeeStyle ~= rangeeSports, nom .. ' : Style sous le champ, plus avec les invites')
        local etiquette
        for _, enfant in ipairs(rangeeStyle.args) do
            if type(enfant) == 'table' and enfant.genre == 'static_text' and enfant.args.title == 'Style' then
                etiquette = enfant
            end
        end
        vrai(etiquette, nom .. ' : étiquette « Style » devant le menu')
        -- ▲ ▼ de la carte Note, de la proposition, de la carte de l'étape (1.3) et de la carte de la
        -- leçon (lot B4), en petit : huit.
        local fleches = {}
        parcourir(args.contents, function(v)
            if S.BOUTONS[v.genre] and (v.args.title == '▲' or v.args.title == '▼') and v.args.size == 'mini' then
                fleches[#fleches + 1] = v.args.enabled.key
            end
        end)
        table.sort(fleches)
        egal('etapeDescend etapeMonte leconDescend leconMonte noteDescend noteMonte propositionDescend propositionMonte',
            table.concat(fleches, ' '), nom .. ' : flèches des cartes')
        -- Les sept invites (1.3 : Composition ajoutée avant Sports), en carrés de 24 de bezel, tiennent
        -- dans le centre.
        local largeurInvites = largeurEstimee(rangeeSports, p)
        vrai(largeurInvites <= D.fil, string.format('%s : invites de %d points dans %d', nom, largeurInvites, D.fil))
        local invites = {}
        for _, enfant in ipairs(rangeeSports.args) do
            if type(enfant) == 'table' and S.BOUTONS[enfant.genre] then
                invites[#invites + 1] = enfant.args.title
                egal('square_button', enfant.genre, nom .. ' : invite en carré')
                egal(24, S.bezelVisible(enfant), nom .. ' : bezel de 24 (maquette)')
            end
        end
        egal('Retouche pro Portrait Paysage Noir et blanc ISO élevé Composition Sports', table.concat(invites, ' '), nom .. ' : invites')
        -- La carte Proposition (fenêtre B, lot B5), sur son image : Accepter, un bouton bleu en image
        -- dont le calque dit que la photo ne change qu'à son clic ; sur sa rangée, Refuser, Ajuster… et
        -- « Je le fais » (titre lié, actif selon peutJeLeFais : ici une photo active et Claude libre,
        -- lot 14) en carrés ; au-dessus, l'état de l'exercice et ▲ ▼.
        local calqueAccepter = parInfobulle(args.contents, "Appliquer la proposition : la photo ne change qu'à ce clic")
        egal('static_text', calqueAccepter.genre, nom .. ' : Accepter, un calque')
        vrai(Fenetre.parCalque(calqueAccepter.args.mouse_down), nom .. ' : Accepter passe par Fenetre.calque')
        local rangeeBoutons, rangeeEtat
        parcourir(args.contents, function(v)
            if v.genre == 'row' then
                for _, b in ipairs(v.args) do
                    if type(b) == 'table' and S.BOUTONS[b.genre] and b.args.title == 'Refuser' then
                        rangeeBoutons = v
                    elseif type(b) == 'table' and b.genre == 'static_text' and type(b.args.title) == 'table' and b.args.title.key == 'exerciceEtat' then
                        rangeeEtat = v
                    end
                end
            end
        end)
        vrai(rangeeBoutons and rangeeEtat, nom .. ' : rangées de la carte Proposition')
        local surLaRangee = {}
        for _, b in ipairs(rangeeBoutons.args) do
            if type(b) == 'table' and S.BOUTONS[b.genre] then
                local t = b.args.title
                surLaRangee[#surLaRangee + 1] = (type(t) == 'table' and ('[' .. t.key .. ']') or t) .. '/' .. b.genre .. '/' .. b.args.enabled.key
            elseif type(b) == 'table' and b.genre == 'column' then
                for _, x in ipairs(b.args) do
                    if x == calqueAccepter then
                        surLaRangee[#surLaRangee + 1] = 'Accepter (bleu)'
                    end
                end
            end
        end
        egal('Refuser/square_button/enAttente Ajuster…/square_button/enAttente [titreJeLeFais]/square_button/peutJeLeFais Accepter (bleu)',
            table.concat(surLaRangee, ' '), nom .. ' : la rangée des boutons de la carte Proposition')
        egal('Je le fais', p.titreJeLeFais)
        egal(true, p.peutJeLeFais, nom .. ' : Je le fais actif, une photo active et Claude libre')
        vrai(boutons['Je le fais'] and Fenetre.parBouton(boutons['Je le fais'].args.action), nom .. ' : Je le fais passe par Fenetre.bouton')
        egal('', p.exerciceEtat)
        -- La carte de l'étape (1.3, onglet Aperçu), sur son image : titre (« Pourquoi ? » sans étape),
        -- sous-titre, texte de D.etapeLignes lignes en 12, puis ◀ ▶, Voir l'avant (titre lié) et
        -- Détail… en carrés, et ▲ ▼, inactifs à l'ouverture.
        local carteEtape
        parcourir(args.contents, function(v)
            for _, enfant in ipairs(v.args) do
                if type(enfant) == 'table' and enfant.genre == 'static_text' and type(enfant.args.title) == 'table'
                    and enfant.args.title.key == 'etapeTexte' then
                    carteEtape = v
                end
            end
        end)
        vrai(carteEtape, nom .. " : carte de l'étape")
        local champs, boutonsEtape = {}, {}
        parcourir(carteEtape, function(v)
            local t = v.args.title
            if v.genre == 'static_text' and type(t) == 'table' then
                champs[#champs + 1] = t.key
                if t.key == 'etapeTexte' then
                    egal(D.etapeLignes, v.args.height_in_lines, nom .. ' : lignes du texte de l\'étape')
                    egal(D.largeurEtape, v.args.width, nom .. ' : largeur du texte de l\'étape')
                    egal(Fenetre.POLICES.texte12, v.args.font, nom .. ' : texte de l\'étape en 12')
                end
            elseif v.genre == 'static_text' then
                champs[#champs + 1] = t
            elseif S.BOUTONS[v.genre] then
                boutonsEtape[#boutonsEtape + 1] = (type(t) == 'table' and p[t.key] or t) .. '/' .. (v.args.size or v.genre) .. '/' .. v.args.enabled.key
                vrai(Fenetre.parBouton(v.args.action), nom .. ' : bouton de l\'étape hors de Fenetre.bouton')
                egal(false, p[v.args.enabled.key], nom .. ' : ' .. v.args.enabled.key .. ' inactif à l\'ouverture')
            end
        end)
        egal('etapeTitre etapeSousTitre etapeTexte', table.concat(champs, ' '), nom .. " : textes de la carte de l'étape")
        egal(Fenetre.TITRE_ETAPE, p.etapeTitre, nom .. " : sans étape, le titre « Pourquoi ? »")
        egal("◀/square_button/etapePrecedente ▶/square_button/etapeSuivante Voir l'avant/square_button/etapeAImages "
            .. 'Détail…/square_button/etapeADetail ▲/mini/etapeMonte ▼/mini/etapeDescend', table.concat(boutonsEtape, ' '),
            nom .. " : boutons de la carte de l'étape")
        -- Les rangées de boutons de la carte de l'étape et de la carte Proposition tiennent dans leur
        -- carte, avec l'un et l'autre titre lié (Voir l'avant ou Voir l'après ; Je le fais ou J'ai fini).
        local rangeeEtape
        for _, enfant in ipairs(carteEtape.args) do
            if type(enfant) == 'table' and enfant.genre == 'row' then
                rangeeEtape = enfant
            end
        end
        vrai(rangeeEtape, nom .. " : rangée des boutons de la carte de l'étape")
        for _, titres in ipairs({ { "Voir l'avant", 'Je le fais' }, { "Voir l'après", "J'ai fini" } }) do
            p.titreBascule, p.titreJeLeFais = titres[1], titres[2]
            local largeurEtape, largeurBoutons = largeurEstimee(rangeeEtape, p), largeurEstimee(rangeeBoutons, p)
            vrai(largeurEtape <= D.largeurEtape, string.format('%s : boutons de l\'étape de %d points dans %d (%s)', nom, largeurEtape,
                D.largeurEtape, titres[1]))
            vrai(largeurBoutons <= D.largeurProposition, string.format('%s : boutons de la proposition de %d points dans %d (%s)', nom,
                largeurBoutons, D.largeurProposition, titres[2]))
        end
        p.titreBascule, p.titreJeLeFais = "Voir l'avant", 'Je le fais'
        -- Les deux versions, une ligne chacune, en bas du volet.
        vrai(textes.versionTexte1 and textes.versionTexte2 and not textes.versionTexte3, nom .. ' : deux versions')
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
        -- L'aperçu : un cadre 3:2 fixe, commun aux onglets, et son image « aucun aperçu » existe à
        -- ce format, dans le jeu de l'apparence.
        vrai(apercu, nom .. ' : un aperçu')
        egal(D.apercu, apercu.args.width)
        egal(D.apercuHauteur, apercu.args.height)
        egal(nil, apercu.args.visible, nom .. ' : aperçu toujours montré')
        vrai(Fichiers.existe(Fenetre.imageVide()), nom .. ' : ' .. Fenetre.imageVide())
        vrai(Fenetre.imageVide():find('/images/vide-' .. D.apercu .. 'x' .. D.apercuHauteur .. '.png', 1, true), Fenetre.imageVide())
        -- Ni modèle, ni effort, ni disposition dans la fenêtre : ils se choisissent dans le
        -- Gestionnaire de modules externes (demandé par Dany le 20 octobre 2026).
        vrai(not menus.modele and not menus.effort and not menus.disposition, nom .. ' : ni modèle, ni effort, ni disposition')
        egal(nil, p.modele)
        egal(nil, p.disposition)
        -- Dans le volet, de haut en bas : Nouvelle conversation, Renommer… et Supprimer…,
        -- Publication… et Consommation…, les versions, le voyant Écran.
        local ordre = {}
        parcourir(args.contents, function(v)
            local t = v.args.title
            if S.BOUTONS[v.genre] and (t == '＋ Nouvelle conversation' or t == 'Renommer…' or t == 'Supprimer…'
                or t == 'Publication…' or t == 'Consommation…') then
                ordre[#ordre + 1] = t
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'versionTexte1' and ordre[#ordre] ~= 'versions' then
                ordre[#ordre + 1] = 'versions'
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'texteEcran' then
                ordre[#ordre + 1] = 'écran'
            end
        end)
        egal('＋ Nouvelle conversation Renommer… Supprimer… Publication… Consommation… versions écran', table.concat(ordre, ' '),
            nom .. ' : le volet')
        -- La carte Note (fenêtre B, lot B5), avec la note posée de la photo active : Laisser,
        -- Changer… et Accepter (un bouton bleu en image, cliqué par son calque).
        vrai(textes.notePoseeTitre and textes.nt1, nom .. ' : carte Note')
        vrai(boutons[p.titreLaisser] and boutons['Changer…'], nom .. ' : boutons de la note')
        vrai(Fenetre.parCalque(parInfobulle(args.contents, "Poser la note proposée dans Lightroom (sans Claude ni quota)").args.mouse_down),
            nom .. ' : Accepter de la note, un calque')
        -- Claude note d'abord chaque photo qu'il traite, à vérifier : plus de bouton Évaluer ni
        -- À vérifier (demandé par Dany le 20 octobre 2026).
        egal(nil, boutons['Évaluer'], nom .. ' : plus de bouton Évaluer')
        egal(nil, boutons['Noter'], nom .. ' : plus de bouton Noter')
        -- Ni sous un autre titre (« ★ Noter » de la maquette), en push_button comme en
        -- square_button : pas de bouton Noter (décision de Dany).
        for titre in pairs(boutons) do
            vrai(not titre:find('Noter', 1, true) and not titre:find('Évaluer', 1, true), nom .. ' : bouton « ' .. titre .. ' »')
        end
        -- « ? À vérifier » de la maquette : posé, inactif dans tous les états (Vues.inactif : le
        -- bouton avait été retiré en 1.1.1, question posée à Dany), jamais un bouton actif « À
        -- vérifier ».
        egal(nil, boutons['À vérifier'], nom .. ' : pas de bouton « À vérifier » actif')
        local aVerifier = boutons['? À vérifier']
        vrai(aVerifier, nom .. ' : « ? À vérifier » posé')
        egal(false, aVerifier.args.enabled, nom .. ' : « ? À vérifier » inactif, dans tous les états')
        egal(Fenetre.A_VENIR, aVerifier.args.tooltip)
        egal(nil, Fenetre.verifierNote, nom .. ' : pas de fonction À vérifier')
        egal(nil, boutons['Séance…'], nom .. ' : plus de Séance de notation (1.1.1)')
        egal(2, p.noteCatalogue)
        egal('Correcte', p.notePoseeTitre)
        egal('2 ★ dans le catalogue', p.notePoseeSous)
        -- Le titre de la conversation, sans ✎ (Renommer… est dans le volet), et la photo active.
        vrai(textes.titre and textes.infoPhoto, nom .. ' : titre et photo active')
        egal(nil, boutons['✎'], nom .. ' : plus de ✎')
        -- Le Mode : trois radios ; les onglets sont des segments en images (plus de radios).
        egal('appliquer proposer jelefais', table.concat(radios, ' '), nom .. ' : les radios du Mode')
        egal('notation', p.onglet, nom .. " : la carte Note sous l'aperçu par défaut")
        -- À droite, de haut en bas : les segments, l'aperçu, Agrandir, puis les cartes superposées
        -- (étape, proposition, note) ; plus de « Ce que Claude voit », ni Publication… à droite.
        local suite = {}
        parcourir(args.contents, function(v)
            local t = v.args.title
            if v == apercu then
                suite[#suite + 1] = 'apercu'
            elseif S.BOUTONS[v.genre] and t == '⤢ Agrandir' then
                suite[#suite + 1] = 'agrandir'
            elseif v.genre == 'static_text' and v.args.tooltip == 'Aperçu' and Fenetre.parCalque(v.args.mouse_down) then
                suite[#suite + 1] = 'onglets'
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'notePoseeTitre' then
                suite[#suite + 1] = 'note'
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'propositionTexte' then
                suite[#suite + 1] = 'proposition'
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'etapeTexte' then
                suite[#suite + 1] = 'etape'
            end
        end)
        egal('onglets apercu agrandir etape proposition note', table.concat(suite, ' '), nom .. ' : colonne de droite')
        parcourir(args.contents, function(v)
            vrai(v.args.title ~= "Ce que Claude voit", nom .. ' : plus de « Ce que Claude voit »')
        end)
        vrai(casesConversations() >= 1, nom .. ' : liste des conversations')
    end
    Fenetre.afficher()
    vrai(construite, nom .. ' : fenêtre construite')
    egal(false, Fenetre.ouverte)
    egal(nil, Moteur.observateurs.fenetre)
    S.pendantFenetre = nil
    egal(nil, Chemins.defauts.disposition, 'plus de préférence de disposition')
    egal(nil, Dispositions.LISTE, "ni Atelier ni Panneau")
    vrai(vues.conversation > 300, 'grille du fil construite')
end)

essai('Fenêtre : texte JSON rendu lisible', function()
    egal('{\n  "a": 1,\n  "b": [\n    2\n  ]\n}', Fenetre.lisible('{"b":[2],"a":1}'))
    egal('pas du json', Fenetre.lisible('pas du json'))
end)

-- Écran (1.2) ----------------------------------------------------------------------------------

-- Un faux connecteur qui ne répond qu'à --ecran, par la ligne JSON rangée dans S.home/ecran.json
-- (celle de `mcp-developpeur --ecran`) ; tout autre argument est refusé. Un connecteur d'avant la
-- 1.2 répond à une option inconnue par son aide, sur stdout, et le code 2.
local reponseEcran = S.home .. '/ecran.json'

local function script(nom, contenu)
    local chemin = S.home .. '/' .. nom
    Fichiers.ecrire(chemin, contenu)
    S.executer('chmod +x ' .. S.q(chemin))
    return chemin
end

local function fauxConnecteurEcran(reponse)
    Fichiers.ecrire(reponseEcran, reponse)
    return script('connecteur-ecran', '#!/bin/sh\n[ "$#" -eq 1 ] && [ "$1" = "--ecran" ] || { echo "option refusée : $*" >&2; exit 2; }\n'
        .. 'cat ' .. S.q(reponseEcran) .. '\n')
end

local function connecteurAncien()
    return script('connecteur-1.1.1', '#!/bin/sh\necho "option inconnue : $1" >&2\n'
        .. "printf 'mcp-developpeur 1.1.1 — MCP-Développeur\\n\\nUsage : mcp-developpeur --status\\n'\nexit 2\n")
end

-- Les réponses de --ecran : un écran d'usine (relevé sur le Mac de Dany), un écran mesuré par une
-- sonde, un profil personnalisé (mesure null), aucun écran.
local ECRAN_USINE = [[{"autres":[],"detail":"Écran principal : Odyssey G85SD (gamut large).\nProfil de couleur : « Odyssey G85SD », le profil d'usine de l'écran, non mesuré sur ce Mac.","principal":{"chemin":"/Library/ColorSync/Profiles/Displays/Odyssey G85SD-60EC80AD.icc","etalonnage":"usine","gamut_large":true,"integre":false,"mesure":false,"nom":"Odyssey G85SD","profil":"Odyssey G85SD","texte":"Odyssey G85SD · profil d'usine, non mesuré sur ce Mac"}}
]]
local ECRAN_SONDE = [[{"autres":[],"detail":"Écran principal : ColorEdge CS2400S.\nProfil de couleur : « CS2400S D65 », mesuré par une sonde (DisplayCAL), profil du 3 mars 2026.","principal":{"etalonnage":"sonde","mesure":true,"logiciel":"DisplayCAL","nom":"ColorEdge CS2400S","texte":"ColorEdge CS2400S · profil mesuré par une sonde (DisplayCAL), du 3 mars 2026"}}
]]
local ECRAN_DOUTE = [[{"autres":[],"principal":{"etalonnage":"personnalise","mesure":null,"nom":"DELL U2723QE","texte":"DELL U2723QE · profil personnalisé « Mon profil », sans trace d'une sonde"}}
]]

-- Un faux Claude Code connecté (`claude auth status`), qui ne lit rien sur son entrée.
local function claudeConnecte()
    return script('claude-connecte', '#!/bin/sh\n[ "$1" = auth ] && [ "$2" = status ] && echo \'{"loggedIn":true,"authMethod":"claude.ai"}\'\n')
end

-- Ce que rend Lightroom.etatEcran : une table neuve de textes, sans le chemin du profil.
local function verifierEcran(ecran, texte, etat, quoi)
    S.neuve(ecran, quoi)
    egal(texte, ecran.texte, quoi .. ' : texte')
    egal(etat, ecran.etat, quoi .. ' : état')
    vrai(type(ecran.detail) == 'string' and ecran.detail ~= '', quoi .. ' : détail')
    for cle, valeur in pairs(ecran) do
        vrai(type(valeur) == 'string' or type(valeur) == 'boolean', quoi .. ' : ' .. cle .. ' de type ' .. type(valeur))
    end
end

essai('Écran : lu par le connecteur (--ecran, 5 s au plus) ; absent ou ancien, voyant gris sans erreur', function()
    local Lightroom = require 'Lightroom'
    local faux = fauxConnecteurEcran(ECRAN_USINE)
    local avant = #(S.dernieresCommandes or {})
    local ecran = Lightroom.etatEcran(faux)
    verifierEcran(ecran, 'Écran · non étalonné', 'attention', 'usine')
    egal(true, ecran.lu)
    vrai(ecran.detail:find("le profil d'usine de l'écran, non mesuré sur ce Mac", 1, true), ecran.detail)
    egal(avant + 1, #S.dernieresCommandes, 'une commande du système')
    local commande = S.dernieresCommandes[#S.dernieresCommandes]
    vrai(commande:find("alarm 5", 1, true) and commande:find(S.q(faux) .. ' --ecran >', 1, true), commande)
    -- Le fichier de sortie est retiré.
    local restes = S.lireCommande('ls ' .. S.q(Chemins.temporaire()) .. ' 2>/dev/null')
    vrai(not restes:find('ecran%-'), 'sortie de --ecran laissée : ' .. restes)

    Fichiers.ecrire(reponseEcran, ECRAN_SONDE)
    ecran = Lightroom.etatEcran(faux)
    verifierEcran(ecran, 'Écran · étalonné', 'ok', 'sonde')
    vrai(ecran.detail:find('mesuré par une sonde (DisplayCAL)', 1, true), ecran.detail)

    -- mesure null (Json.decode efface la clé) : « étalonné ? », et le texte de l'écran pour détail.
    Fichiers.ecrire(reponseEcran, ECRAN_DOUTE)
    ecran = Lightroom.etatEcran(faux)
    verifierEcran(ecran, 'Écran · étalonné ?', 'neutre', 'personnalisé')
    vrai(ecran.detail:find('sans trace d\'une sonde', 1, true), ecran.detail)

    -- Aucun écran lu (session sans écran) : gris, et dit tel quel.
    Fichiers.ecrire(reponseEcran, '{"lu":false}\n')
    ecran = Lightroom.etatEcran(faux)
    verifierEcran(ecran, 'Écran', 'neutre', 'aucun écran')
    egal(false, ecran.lu)
    egal(Lightroom.ECRAN_AUCUN, ecran.detail)

    -- Réponse vide ou coupée (alarme de 5 s) : gris, « pas répondu dans les 5 s », jamais
    -- « introuvable » (le connecteur est là).
    Fichiers.ecrire(reponseEcran, '{"principal":{"mesure":fa')
    ecran = Lightroom.etatEcran(faux)
    verifierEcran(ecran, 'Écran', 'neutre', 'réponse coupée')
    egal(Lightroom.ECRAN_ILLISIBLE, ecran.detail, 'réponse coupée : détail')
    vrai(not ecran.detail:find('introuvable', 1, true), ecran.detail)
    -- Une commande du système en échec : gris, sans erreur.
    local executer = S.modules.LrTasks.execute
    S.modules.LrTasks.execute = function() error('commande impossible') end
    local okPanne, enPanne = pcall(Lightroom.etatEcran, faux)
    S.modules.LrTasks.execute = executer
    vrai(okPanne, tostring(enPanne))
    verifierEcran(enPanne, 'Écran', 'neutre', 'commande en échec')
    egal(Lightroom.ECRAN_ILLISIBLE, enPanne.detail, 'commande en échec : détail')

    -- Connecteur 1.1.1 (son aide sur stdout) : gris, « plus ancien que la 1.2 ».
    ecran = Lightroom.etatEcran(connecteurAncien())
    verifierEcran(ecran, 'Écran', 'neutre', 'connecteur 1.1.1')
    egal(Lightroom.ECRAN_ILLISIBLE, ecran.detail, 'connecteur 1.1.1 : détail')
    vrai(ecran.detail:find('plus ancien que la 1.2', 1, true), ecran.detail)
    -- Connecteur introuvable : gris, « introuvable », et rien n'est lancé.
    avant = #S.dernieresCommandes
    ecran = Lightroom.etatEcran(S.home .. '/introuvable/mcp-developpeur')
    verifierEcran(ecran, 'Écran', 'neutre', 'connecteur introuvable')
    egal(false, ecran.lu)
    egal(Lightroom.ECRAN_INTROUVABLE, ecran.detail)
    vrai(not ecran.detail:find('plus ancien', 1, true), ecran.detail)
    egal(avant, #S.dernieresCommandes, 'rien lancé sans connecteur')
    ecran = Lightroom.etatEcran(nil)
    verifierEcran(ecran, 'Écran', 'neutre', 'sans chemin')
    egal(Lightroom.ECRAN_INTROUVABLE, ecran.detail, 'sans chemin : détail')
    verifierEcran(Lightroom.decrireEcran({ principal = 'texte' }), 'Écran', 'neutre', 'principal illisible')
end)

essai("Fenêtre : le voyant Écran, lu à l'ouverture ; un clic le relit et donne son détail, sans envoyer la demande", function()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.selection = { S.photoActive }
    local prefs = Chemins.prefs()
    local connecteur, claude = prefs.cheminConnecteur, prefs.cheminClaude
    local construite = false
    S.pendantFenetre = function(args)
        construite = true
        local p = Fenetre.p
        egal('Écran', p.texteEcran)
        egal('neutre', p.etatEcran)
        -- Trois voyants (plus de voyant Mode : le Mode est dans l'en-tête) : l'écran en bas du volet
        -- (de la 1.2, sous les versions), Claude Code et Lightroom dans l'en-tête ; chacun avec sa
        -- pastille en images, une par état, à côté de son texte.
        local voyants, voyant = {}, nil
        local largeurs = { texteClaude = Fenetre.T.voyantClaude, texteLightroom = Fenetre.T.voyantLightroom,
            texteEcran = Fenetre.T.liste - 14 }
        parcourir(args.contents, function(v)
            local t = v.args.title
            if v.genre == 'row' and type(v.args[2]) == 'table' and v.args[2].genre == 'static_text'
                and type(v.args[2].args.title) == 'table' and largeurs[v.args[2].args.title.key] then
                local cle = v.args[2].args.title.key
                voyants[#voyants + 1] = cle
                egal(largeurs[cle], v.args[2].args.width, cle)
                local pastilles = {}
                for _, image in ipairs(v.args[1].args) do
                    egal('picture', image.genre, cle .. ' : pastille en image')
                    pastilles[#pastilles + 1] = image.args.value:match('([^/]+)%.png$')
                end
                egal('pastille-vert pastille-orange pastille-rouge pastille-gris', table.concat(pastilles, ' '), cle .. ' : pastilles')
                if cle == 'texteEcran' then
                    voyant = v.args[2]
                end
            end
        end)
        egal('texteEcran texteClaude texteLightroom', table.concat(voyants, ' '))
        egal(nil, p.texteMode, 'plus de voyant Mode')
        vrai(voyant and voyant.args.mouse_down and voyant.args.tooltip:find('profil de couleur', 1, true), "voyant de l'écran cliquable")
        -- À l'ouverture (Fenetre.verifier(true)) : l'écran d'usine du Mac de Dany, non étalonné.
        prefs.cheminConnecteur = fauxConnecteurEcran(ECRAN_USINE)
        prefs.cheminClaude = claudeConnecte()
        Fenetre.verifier(true)
        egal('ok', p.etatClaude, 'faux Claude Code connecté')
        egal('Écran · non étalonné', p.texteEcran)
        egal('attention', p.etatEcran)
        vrai(not p.aide:find('cran', 1, true), "l'écran n'est pas une aide du bandeau : " .. p.aide)
        -- Toutes les 2 s, l'écran ne se relit pas.
        local commandes = #S.dernieresCommandes
        Fenetre.periodique()
        for i = commandes + 1, #S.dernieresCommandes do
            vrai(not S.dernieresCommandes[i]:find('--ecran', 1, true), "l'écran relu toutes les 2 s")
        end
        -- Un clic : la demande validée par ce clic ne part pas ; l'écran se relit dans une tâche (un
        -- autre a pu être branché), puis la boîte « Claude · écran » donne son détail.
        Fichiers.ecrire(reponseEcran, ECRAN_SONDE)
        p.saisie = 'Texte validé par le clic'
        vrai(Fenetre.envoiAuto, 'envoi prévu')
        local taches, messages = #S.taches, #S.messages
        voyant.args.mouse_down()
        egal(nil, Fenetre.envoiAuto, "le clic du voyant annule l'envoi automatique")
        egal(taches + 1, #S.taches, 'relu dans une tâche')
        S.taches[#S.taches]()
        egal(messages + 1, #S.messages, 'une boîte')
        egal('Claude · écran', S.messages[#S.messages][1])
        vrai(S.messages[#S.messages][2]:find('mesuré par une sonde (DisplayCAL)', 1, true), S.messages[#S.messages][2])
        egal('Écran · étalonné', p.texteEcran)
        egal('ok', p.etatEcran)
        -- Un connecteur d'avant la 1.2 : gris, sans erreur ; le clic dit pourquoi.
        prefs.cheminConnecteur = connecteurAncien()
        Fenetre.verifier(true)
        egal('Écran', p.texteEcran)
        egal('neutre', p.etatEcran)
        voyant.args.mouse_down()
        S.taches[#S.taches]()
        vrai(S.messages[#S.messages][2]:find('plus ancien que la 1.2', 1, true), S.messages[#S.messages][2])
        p.saisie = ''
    end
    local ok, erreur = pcall(Fenetre.afficher)
    prefs.cheminConnecteur, prefs.cheminClaude = connecteur, claude
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(construite, 'fenêtre construite')
end)

-- Jeton de la liaison (1.2) --------------------------------------------------------------------

essai("Fenêtre : voyant Lightroom, une erreur du jeton privé de la liaison a sa propre aide", function()
    local Liaison = require 'Liaison'
    local construite = false
    S.pendantFenetre = function()
        construite = true
        local p = Fenetre.p
        Liaison.actif, Liaison.erreur = true, 'jeton de la liaison : aléa du système illisible (/dev/urandom)'
        Fenetre.verifier(false)
        egal('Lightroom · liaison en erreur', p.texteLightroom)
        egal('erreur', p.etatLightroom)
        vrai(Fenetre.aideLiaison:find('jeton privé', 1, true) and Fenetre.aideLiaison:find('/dev/urandom', 1, true), Fenetre.aideLiaison)
        vrai(Fenetre.aideLiaison:find('module.log', 1, true), Fenetre.aideLiaison)
        vrai(not Fenetre.aideLiaison:find('un autre Lightroom', 1, true), Fenetre.aideLiaison)
        vrai(p.aide:find('jeton privé', 1, true), p.aide)
        -- Une autre erreur garde l'aide des ports tenus par un autre Lightroom.
        Liaison.erreur = 'adresse déjà utilisée'
        Fenetre.verifier(false)
        vrai(Fenetre.aideLiaison:find('un autre Lightroom', 1, true) and not Fenetre.aideLiaison:find('jeton', 1, true), Fenetre.aideLiaison)
        Liaison.actif, Liaison.erreur = false, nil
    end
    local ok, erreur = pcall(Fenetre.afficher)
    Liaison.actif, Liaison.erreur = false, nil
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(construite, 'fenêtre construite')
end)

essai('Relais : connecteur.json et relais.sh ne portent jamais le jeton de la liaison', function()
    local config = Session.configMCP('/x/mcp-developpeur')
    vrai(not config:find('jeton', 1, true) and not config:find('env', 1, true), config)
    egal('/x/mcp-developpeur', Json.decode(config).mcpServers[Session.SERVEUR].command)
    local relais = Fichiers.lire(S.plugin .. '/relais.sh')
    vrai(relais and relais ~= '' and not relais:find('jeton', 1, true), 'relais.sh ne passe aucun jeton')
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
        if S.BOUTONS[v.genre] then
            vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
        end
    end)
    return vues
end

-- Simulation : règles tirées des constats du 21 octobre 2026 (fenêtre B) -------------------------
-- Constats du module d'essai de la fenêtre B dans Lightroom Classic 15.6 : blocs A à C le matin,
-- blocs D (lot B0) l'après-midi. Chaque règle de Simulation.lua a ici l'essai qui échoue sans elle.

local fabriqueVues = S.modules.LrView.osFactory()
local lier = S.modules.LrView.bind

-- La fonction échoue, et son message contient `attendu`.
local function refuse(fn, attendu, quoi)
    local ok, erreur = pcall(fn)
    vrai(not ok, (quoi or 'refus attendu') .. ' : accepté')
    vrai(tostring(erreur):find(attendu, 1, true), (quoi or 'refus') .. ' : ' .. tostring(erreur))
end

-- Ouvre une fenêtre flottante de ce contenu (arguments en plus : `extra`) et appelle
-- pendant(contenu) tant qu'elle est ouverte ; rend ok et l'erreur.
local function ouvrirEssai(contenu, pendant, extra)
    local args = { title = 'Essai', contents = contenu }
    for cle, valeur in pairs(extra or {}) do
        args[cle] = valeur
    end
    S.pendantFenetre = pendant and function() pendant(contenu) end
    local ok, erreur = pcall(S.modules.LrDialogs.presentFloatingDialog, _PLUGIN, args)
    S.pendantFenetre = nil
    return ok, erreur
end

local function rien() end

essai('Simulation : square_button accepté (B3, D5), compté parmi les boutons et trouvé par son titre', function()
    local f = fabriqueVues
    local p = S.modules.LrBinding.makePropertyTable()
    p.titreCarre = 'Renommer…'
    local carre = f:square_button { title = lier 'titreCarre', size = 'small', action = rien }
    local contenu = f:column { bind_to_object = p, f:push_button { title = 'Envoyer', action = rien }, carre }
    vrai(S.BOUTONS.push_button and S.BOUTONS.square_button, 'les deux genres de boutons')
    egal(2, #S.boutons(contenu), 'push_button et square_button')
    egal(carre, S.trouverBouton(contenu, 'Renommer…', p), 'trouvé par son titre lié')
    local ok, erreur = ouvrirEssai(contenu, function()
        egal(carre, S.trouverBouton(contenu, 'Renommer…'), 'titre lu dans la table de la fenêtre ouverte')
        egal(3, verifierVues(contenu, p), 'square_button vérifié comme un bouton')
    end)
    assert(ok, erreur)
    refuse(function() verifierVues(f:column { f:square_button { title = 'Sans action' } }, p) end, 'bouton sans action', 'square_button sans action')
end)

essai("Simulation : f:picture sans clic (C1), avec width et height (AgPictureView), sans image seulement en aplat (A4)", function()
    local f = fabriqueVues
    local fond = S.modules.LrColor(0.85, 0.85, 0.85)
    refuse(function() f:picture { value = 'a.png', width = 24, height = 24, mouse_down = rien } end, 'C1', 'mouse_down sur une image')
    refuse(function() f:picture { value = 'a.png', width = 24 } end, 'sans width ou sans height', 'sans height')
    refuse(function() f:picture { value = 'a.png', height = 24 } end, 'sans width ou sans height', 'sans width')
    refuse(function() f:picture { width = 24, height = 24 } end, 'A4', 'ni image ni fond')
    f:picture { width = 630, height = 1, background_color = fond }
    f:picture { value = lier 'image', width = 24, height = 24 }
    -- Un clic simulé sur l'image est refusé ; le calque posé dessus le reçoit.
    local recus = 0
    local image = f:picture { value = 'a.png', width = 24, height = 24 }
    local calque = f:static_text { title = '', width = 24, height = 24, mouse_down = function() recus = recus + 1 end }
    local ok, erreur = ouvrirEssai(f:column { place = 'overlapping', image, calque }, function()
        refuse(function() S.cliquer(image) end, 'C1', "clic sur l'image")
        S.cliquer(calque)
    end)
    assert(ok, erreur)
    egal(1, recus, 'le calque reçoit le clic')
end)

essai("Simulation : background_color sans effet sur row et view (A5), column et group_box (relevé dans AgUI) et sur la "
    .. "fenêtre (A1) ; permis sur scrolled_view et picture", function()
    local f = fabriqueVues
    local rose = S.modules.LrColor(1, 0.8, 0.8)
    -- Chaque refus dit sa source : constaté pour row et view, relevé seulement pour les deux autres.
    local sources = { row = 'constaté le 21 octobre 2026, A5', view = 'constaté le 21 octobre 2026, A5', column = 'relevé dans AgUI',
        group_box = 'relevé dans AgUI' }
    for genre, source in pairs(sources) do
        refuse(function() f[genre](f, { background_color = rose, f:static_text { title = 'x' } }) end, '(' .. source .. ')', genre)
    end
    f:scrolled_view { background_color = rose, horizontal_scroller = false, f:static_text { title = 'x' } }
    f:picture { width = 10, height = 10, background_color = rose }
    local ouvertes = #S.fenetresOuvertes
    local ok, erreur = ouvrirEssai(f:column { f:static_text { title = 'x' } }, rien, { background_color = rose })
    vrai(not ok and tostring(erreur):find('A1', 1, true), 'fond de la fenêtre : ' .. tostring(erreur))
    egal(ouvertes, #S.fenetresOuvertes, 'rien ne reste ouvert')
    ok, erreur = ouvrirEssai(f:column { f:static_text { title = 'x' } }, rien)
    assert(ok, erreur)
end)

essai('Simulation : primary_line_color refusé partout (A6 : séparateur resté #DBDBDB)', function()
    local f = fabriqueVues
    local bleu = S.modules.LrColor(0.04, 0.39, 0.85)
    refuse(function() f:separator { fill_horizontal = 1, primary_line_color = bleu } end, 'A6', 'séparateur')
    refuse(function() f:column { primary_line_color = bleu } end, 'A6', 'colonne')
    f:separator { fill_horizontal = 1 }
end)

essai("Simulation : image_name sans titre (D5) ; avec un titre, refusé (B3), titre lié compris", function()
    local f = fabriqueVues
    refuse(function() f:push_button { title = 'Joindre', image_name = 'trombone.png', action = rien } end, 'B3', 'titre écrit')
    f:square_button { title = '', image_name = 'trombone.png', width = 26, action = rien }
    f:square_button { image_name = 'plus.png', width = 26, action = rien }
    f:push_button { title = 'Joindre', action = rien }
    -- Un titre lié se lit à l'ouverture, puis à chaque nouvelle valeur.
    local p = S.modules.LrBinding.makePropertyTable()
    p.titreIcone = 'Joindre'
    local bouton = f:square_button { title = lier 'titreIcone', image_name = 'trombone.png', width = 26, action = rien }
    local ok, erreur = ouvrirEssai(f:column { bind_to_object = p, bouton })
    vrai(not ok and tostring(erreur):find('B3', 1, true), "titre lié non vide à l'ouverture : " .. tostring(erreur))
    p.titreIcone = ''
    ok, erreur = ouvrirEssai(f:column { bind_to_object = p, bouton }, function()
        refuse(function() p.titreIcone = 'Joindre' end, 'B3', 'titre lié qui change')
        egal(1, #S.refusDeLaFenetre(), 'le refus est gardé pour la fermeture')
        p.titreIcone = ''
    end)
    assert(ok, erreur)
    -- Un refus avalé (une tâche du module, LrTasks.pcall) fait échouer la fermeture.
    ok, erreur = ouvrirEssai(f:column { bind_to_object = p, bouton }, function()
        pcall(function() p.titreIcone = 'Joindre' end)
        p.titreIcone = ''
    end)
    vrai(not ok and tostring(erreur):find('refusée pendant que la fenêtre était ouverte', 1, true), tostring(erreur))
    -- Fermée, la fenêtre ne vérifie plus rien.
    p.titreIcone = 'Joindre'
end)

essai('Simulation : un seul bouton par défaut par fenêtre (relevé dans AgUI : setDefaultButtonCell), liaison comprise', function()
    local f = fabriqueVues
    local function defaut(titre)
        return f:push_button { title = titre, default = true, action = rien }
    end
    local ok, erreur = ouvrirEssai(f:row { defaut('Envoyer'), defaut('Accepter') })
    vrai(not ok and tostring(erreur):find('setDefaultButtonCell', 1, true), tostring(erreur))
    local p = S.modules.LrBinding.makePropertyTable()
    p.parDefaut = true
    local function contenu()
        return f:row { bind_to_object = p, defaut('Envoyer'), f:push_button { title = 'Accepter', default = lier 'parDefaut', action = rien } }
    end
    ok, erreur = ouvrirEssai(contenu())
    vrai(not ok and tostring(erreur):find('setDefaultButtonCell', 1, true), "le second par liaison : " .. tostring(erreur))
    p.parDefaut = false
    ok, erreur = ouvrirEssai(contenu(), function()
        egal('Envoyer', S.titreDe(S.boutonParDefaut()), 'le bouton par défaut de la fenêtre')
        -- Le second qui le devient, fenêtre ouverte : refusé aussi.
        refuse(function() p.parDefaut = true end, 'setDefaultButtonCell', 'le second par une nouvelle valeur')
        egal(1, #S.refusDeLaFenetre(), 'refus gardé')
        p.parDefaut = false
    end)
    assert(ok, erreur)
    refuse(function()
        S.modules.LrDialogs.presentModalDialog { title = 'Essai', contents = f:row { defaut('Un'), defaut('Deux') } }
    end, 'setDefaultButtonCell', 'fenêtre modale')
    -- Un default lié se relit à chaque Retour, comme toute liaison : faux à l'ouverture, puis vrai.
    local q = S.modules.LrBinding.makePropertyTable()
    q.saisie, q.envoiParDefaut = '', false
    local recus = 0
    local champ = f:edit_field { value = lier 'saisie' }
    local envoyer = f:push_button { title = 'Envoyer', default = lier 'envoiParDefaut', action = function() recus = recus + 1 end }
    ok, erreur = ouvrirEssai(f:column { bind_to_object = q, champ, envoyer }, function()
        egal(nil, S.boutonParDefaut(), "aucun à l'ouverture")
        vrai(not S.retour(champ), "Retour sans bouton par défaut")
        q.envoiParDefaut = true
        egal(envoyer, S.boutonParDefaut(), 'devenu le bouton par défaut')
        vrai(S.retour(champ), 'il prend Retour')
        q.envoiParDefaut = false
        vrai(not S.retour(champ), 'il ne le prend plus')
    end)
    assert(ok, erreur)
    egal(1, recus)
end)

essai("Simulation : une fenêtre se ferme même quand l'essai qui la manipule échoue", function()
    local f = fabriqueVues
    local ouvertes = #S.fenetresOuvertes
    local ok, erreur = ouvrirEssai(f:column { f:push_button { title = 'Envoyer', default = true, action = rien } }, function()
        egal(ouvertes + 1, #S.fenetresOuvertes, 'ouverte pendant l\'essai')
        error('échec exprès')
    end)
    vrai(not ok and tostring(erreur):find('échec exprès', 1, true), tostring(erreur))
    egal(ouvertes, #S.fenetresOuvertes, 'fermée après l\'échec')
    egal(nil, S.boutonParDefaut(), 'son bouton par défaut ne compte plus')
end)

essai('Simulation : texte riche <EM> — balises fermées, emphasis_font, ni entité, ni dernière ligne coupée (B1, D4)', function()
    local f = fabriqueVues
    local gras12 = { name = '<system/bold>', size = 12 }
    local texte12 = { name = '<system>', size = 12 }
    local texte11 = { name = '<system>', size = 11 }
    local ambre = S.modules.LrColor(0.66, 0.38, 0)
    local gris = S.modules.LrColor(0.42, 0.42, 0.42)
    -- Acceptés : emphase grasse et ambre sur un texte gris (text_color n'efface pas emphasis_color,
    -- constaté D4 : le relevé dans AgUI est démenti) ; « < » et « & » bruts ; une balise fermée sur
    -- la ligne suivante.
    f:static_text { title = '<EM>Plafond 3 ★</EM> : feuillage bougé.', font = texte12, emphasis_font = gras12, emphasis_color = ambre,
        text_color = gris }
    f:static_text { title = '<EM>Note</EM> : 2 < 3 & 4', font = texte12, emphasis_font = gras12 }
    f:static_text { title = '<EM>Passe 1\nPasse 2</EM> : oui', font = texte12, emphasis_font = gras12, height_in_lines = 2 }
    f:static_text { title = 'Sans balise : < et &amp; tels quels' }
    -- Refusés.
    refuse(function() f:static_text { title = 'Texte riche <EM>', emphasis_font = gras12 } end, 'B1', 'balise non fermée')
    refuse(function() f:static_text { title = 'Texte riche <EM>' } end, 'B1', 'balise seule, sans police')
    refuse(function() f:static_text { title = 'fin</EM>', emphasis_font = gras12 } end, '</EM> sans <EM>', 'fermeture seule')
    refuse(function() f:static_text { title = '<EM>a<EM>b</EM>', emphasis_font = gras12 } end, 'ouverte deux fois', 'balises imbriquées')
    refuse(function() f:static_text { title = '<EM>Moyen.</EM> Le ciel' } end, 'sans emphasis_font', "sans police d'emphase")
    refuse(function() f:static_text { title = '<EM>Moyen.</EM> Le ciel', emphasis_color = ambre } end, 'emphasis_color sans emphasis_font',
        'couleur seule')
    refuse(function() f:static_text { title = 'Sans balise', emphasis_color = ambre } end, 'D4', 'couleur seule, sans balise')
    refuse(function() f:static_text { title = '<EM>2 &lt; 3</EM>', emphasis_font = gras12 } end, 'D4', '&lt;')
    refuse(function() f:static_text { title = '<EM>A</EM> &amp; B', emphasis_font = gras12 } end, 'D4', '&amp;')
    -- Police 11, emphase grasse 12 : la dernière ligne de height_in_lines = 4 est coupée ; une ligne
    -- de plus, ou une emphase de la même taille, passent.
    local quatre = '<EM>Axe 1</EM> net\nb\nc\n<EM>Axe 2</EM> doux'
    refuse(function() f:static_text { title = quatre, font = texte11, emphasis_font = gras12, height_in_lines = 4 } end, 'coupée',
        'emphase de 12 sur 11')
    refuse(function() f:static_text { title = quatre, font = '<system/small>', emphasis_font = gras12, height_in_lines = 4 } end, 'coupée',
        "emphase de 12 sur '<system/small>'")
    f:static_text { title = quatre, font = texte11, emphasis_font = gras12, height_in_lines = 5 }
    -- Tailles connues : '<system>' 13, '<system/small>' 11 (D9) ; « mini » ni documenté ni constaté.
    egal(13, S.taillePolice('<system/bold>'))
    egal(11, S.taillePolice('<system/small/bold>'))
    egal(nil, S.taillePolice('<system/mini>'), 'mini : taille inconnue')
    f:static_text { title = quatre, font = '<system/small>', emphasis_font = '<system/mini/bold>', height_in_lines = 4 }
    f:static_text { title = quatre, font = texte11, emphasis_font = { name = '<system/bold>', size = 11 }, height_in_lines = 4 }
    f:static_text { title = quatre, font = texte12, emphasis_font = gras12, height_in_lines = 4 }
    -- Un titre lié : sa valeur à l'ouverture, puis chaque nouvelle valeur, qui garde son balisage
    -- (constaté D4).
    local p = S.modules.LrBinding.makePropertyTable()
    p.critere = '<EM>Plafond 3 ★</EM>'
    local critere = f:static_text { title = lier 'critere', font = texte12, emphasis_font = gras12, emphasis_color = ambre }
    local ok, erreur = ouvrirEssai(f:column { bind_to_object = p, critere }, function()
        p.critere = '<EM>Plafond 2 ★</EM> · <EM>À vérifier</EM>'
        refuse(function() p.critere = '<EM>Plafond 2 ★' end, 'B1', 'nouvelle valeur non fermée')
        refuse(function() p.critere = '<EM>2 &lt; 3</EM>' end, 'D4', 'nouvelle valeur avec une entité')
        egal(2, #S.refusDeLaFenetre(), 'refus gardés')
        p.critere = ''
    end)
    assert(ok, erreur)
    p.critere = 'Sans balise <EM>'
    ok, erreur = ouvrirEssai(f:column { bind_to_object = p, critere })
    vrai(not ok and tostring(erreur):find('B1', 1, true), "valeur liée refusée à l'ouverture : " .. tostring(erreur))
    -- Hauteur et police liées : lues aussi.
    p.critere, p.lignes = quatre, 4
    local lie = f:static_text { title = lier 'critere', font = texte11, emphasis_font = gras12, height_in_lines = lier 'lignes' }
    ok, erreur = ouvrirEssai(f:column { bind_to_object = p, lie })
    vrai(not ok and tostring(erreur):find('coupée', 1, true), 'hauteur liée : ' .. tostring(erreur))
    p.lignes = 5
    ok, erreur = ouvrirEssai(f:column { bind_to_object = p, lie }, function()
        refuse(function() p.lignes = 4 end, 'coupée', 'hauteur liée qui change')
        S.refusDeLaFenetre()
        p.lignes = 5
    end)
    assert(ok, erreur)
end)

essai('Simulation : emphasis_font, emphasis_color, default et image_name connus du SDK et évalués, liaisons comprises', function()
    local f = fabriqueVues
    local p = S.modules.LrBinding.makePropertyTable()
    p.critere, p.police, p.couleur = '<EM>Moyen.</EM> Le ciel', { name = '<system/bold>', size = 12 }, S.modules.LrColor(0.66, 0.38, 0)
    p.parDefaut, p.icone = true, 'trombone.png'
    local contenu = f:column {
        bind_to_object = p,
        f:static_text { title = lier 'critere', emphasis_font = lier 'police', emphasis_color = lier 'couleur' },
        f:push_button { title = 'Envoyer', default = lier 'parDefaut', action = rien },
        f:square_button { image_name = lier 'icone', width = 26, action = rien },
    }
    local ok, erreur = ouvrirEssai(contenu, function()
        egal(4, verifierVues(contenu, p), 'attributs connus, liaisons avec une valeur')
        egal('Envoyer', S.titreDe(S.boutonParDefaut()))
        -- Une police d'emphase liée se relit quand elle change.
        refuse(function() p.police = nil end, 'sans emphasis_font', "police d'emphase retirée")
        S.refusDeLaFenetre()
        p.police = { name = '<system/bold>', size = 12 }
    end)
    assert(ok, erreur)
end)

essai("Simulation : Retour valide le champ, puis le bouton par défaut s'il est actif et montré, même depuis « Rechercher » ; "
    .. "jamais un autre bouton (D1, D2)", function()
    local f = fabriqueVues
    local p = S.modules.LrBinding.makePropertyTable()
    p.saisie, p.recherche, p.peutEnvoyer, p.travaille = '', '', true, false
    local journal = {}
    local function note(texte)
        journal[#journal + 1] = texte
    end
    local function lu()
        local t = table.concat(journal, ' | ')
        journal = {}
        return t
    end
    p:addObserver('saisie', function(_, _, v) note('observateur ' .. v) end)
    p:addObserver('recherche', function(_, _, v) note('recherche ' .. v) end)
    local champ = f:edit_field { value = lier 'saisie', immediate = false, height_in_lines = 2 }
    local recherche = f:edit_field { value = lier 'recherche', immediate = true }
    local envoyer = f:push_button { title = 'Envoyer', default = true, enabled = lier 'peutEnvoyer',
        visible = lier { key = 'travaille', transform = function(v) return not v end }, action = function() note('Envoyer lit ' .. p.saisie) end }
    local arreter = f:push_button { title = 'Arrêter', visible = lier 'travaille', action = function() note('Arrêter') end }
    local contenu = f:column { bind_to_object = p, champ, recherche, f:column { place = 'overlapping', envoyer, arreter } }
    local ok, erreur = ouvrirEssai(contenu, function()
        -- D1 : l'observateur du champ, puis l'action d'Envoyer, qui lit la valeur validée.
        S.taper(champ, 'bonjour')
        egal('', lu(), 'rien avant Retour')
        egal('bonjour', S.texteChamp(champ), 'le texte tapé est dans le champ')
        vrai(S.retour(champ), 'Envoyer prend Retour')
        egal('observateur bonjour | Envoyer lit bonjour', lu())
        -- D1 : « Rechercher » suit chaque frappe ; Retour y déclenche aussi Envoyer.
        S.taper(recherche, 'abc')
        egal('recherche a | recherche ab | recherche abc', lu())
        vrai(S.retour(recherche), 'Retour dans « Rechercher » déclenche le bouton par défaut')
        egal('Envoyer lit bonjour', lu())
        -- D2 : Envoyer inactif : l'observateur seul.
        p.peutEnvoyer = false
        S.taper(champ, ' encore')
        vrai(not S.retour(champ), 'Envoyer inactif ne prend pas Retour')
        egal('observateur bonjour encore', lu())
        -- D2 : Envoyer masqué, Arrêter montré à sa place : ni l'un ni l'autre.
        p.peutEnvoyer, p.travaille = true, true
        S.taper(champ, ' !')
        vrai(not S.retour(champ), 'Envoyer masqué ne prend pas Retour')
        egal('observateur bonjour encore !', lu())
        -- Envoyer de retour : il reprend Retour.
        p.travaille = false
        vrai(S.retour(champ), 'Envoyer réactivé reprend Retour')
        egal('Envoyer lit bonjour encore !', lu())
        -- Le champ quitté pour un autre est validé (D1).
        S.taper(champ, '?')
        S.taper(recherche, 'd')
        egal('observateur bonjour encore !? | recherche abcd', lu())
    end)
    assert(ok, erreur)
    -- Sans bouton par défaut (D1) : Retour valide le champ, rien d'autre, et rien dans « Rechercher ».
    p.saisie, p.recherche = '', ''
    lu()
    local sans = f:column { bind_to_object = p, f:edit_field { value = lier 'saisie' }, f:edit_field { value = lier 'recherche', immediate = true },
        f:push_button { title = 'Envoyer', action = function() note('Envoyer') end } }
    ok, erreur = ouvrirEssai(sans, function(c)
        egal(nil, S.boutonParDefaut())
        S.taper(c.args[1], 'salut')
        vrai(not S.retour(c.args[1]))
        egal('observateur salut', lu())
        S.taper(c.args[2], 'x')
        lu()
        vrai(not S.retour(c.args[2]))
        egal('', lu(), 'Retour dans « Rechercher » ne déclenche rien')
    end)
    assert(ok, erreur)
end)

essai("Simulation : un clic valide d'abord le champ tapé sans Retour, puis se fait et lit la valeur validée (D3)", function()
    local f = fabriqueVues
    local p = S.modules.LrBinding.makePropertyTable()
    p.saisie, p.choix, p.coche = '', 'un', false
    local journal = {}
    local function note(texte)
        journal[#journal + 1] = texte
    end
    p:addObserver('saisie', function(_, _, v) note('observateur ' .. v) end)
    p:addObserver('choix', function(_, _, v) note('radio ' .. v .. ' lit ' .. p.saisie) end)
    p:addObserver('coche', function(_, _, v) note('case ' .. tostring(v) .. ' lit ' .. p.saisie) end)
    local champ = f:edit_field { value = lier 'saisie', immediate = false }
    local calque = f:static_text { title = '', width = 72, height = 22, mouse_down = function() note('calque lit ' .. p.saisie) end }
    local radio = f:radio_button { title = 'Deux', value = lier 'choix', checked_value = 'deux' }
    local case = f:checkbox { title = 'Case', value = lier 'coche' }
    local temoin = f:push_button { title = 'Témoin', action = function() note('bouton lit ' .. p.saisie) end }
    local carre = f:square_button { title = '?', action = function() note('carré lit ' .. p.saisie) end }
    local ok, erreur = ouvrirEssai(f:column { bind_to_object = p, champ, calque, radio, case, temoin, carre }, function()
        local cas = {
            { calque, 'a', 'calque lit a' },
            { radio, 'b', 'radio deux lit ab' },
            { case, 'c', 'case true lit abc' },
            { temoin, 'd', 'bouton lit abcd' },
            { carre, 'e', 'carré lit abcde' },
        }
        for _, c in ipairs(cas) do
            journal = {}
            S.taper(champ, c[2])
            S.cliquer(c[1])
            egal('observateur ' .. p.saisie .. ' | ' .. c[3], table.concat(journal, ' | '))
            egal(p.saisie, S.texteChamp(champ), 'le texte reste dans le champ')
        end
        -- Sans frappe, rien à valider ; la case se décoche.
        journal = {}
        S.cliquer(case)
        egal('case false lit abcde', table.concat(journal, ' | '))
    end)
    assert(ok, erreur)
end)

essai('Simulation : visible lié sur un f:view, qui se cache avec ses vues (D10) ; refusé sur row, column, group_box, tab_view '
    .. 'et scrolled_view (20 octobre 2026)', function()
    local f = fabriqueVues
    local p = S.modules.LrBinding.makePropertyTable()
    p.montrer = true
    for _, genre in ipairs({ 'row', 'column', 'group_box', 'tab_view', 'scrolled_view' }) do
        refuse(function() f[genre](f, { visible = lier 'montrer' }) end, 'visible sur un conteneur', genre)
    end
    local recus = 0
    local bouton = f:push_button { title = 'Clic', size = 'mini', action = function() recus = recus + 1 end }
    local vue = f:view { visible = lier 'montrer', f:row { f:static_text { title = 'Dans un f:view' }, bouton } }
    local ok, erreur = ouvrirEssai(f:column { bind_to_object = p, vue, f:static_text { title = 'après la vue' } }, function()
        S.cliquer(bouton)
        p.montrer = false
        vrai(not S.montreeDansFenetre(bouton), 'caché avec son f:view')
        refuse(function() S.cliquer(bouton) end, 'masquée', 'clic dans un f:view caché')
        p.montrer = true
        vrai(S.montreeDansFenetre(bouton), 'montré de nouveau')
        S.cliquer(bouton)
    end)
    assert(ok, erreur)
    egal(2, recus)
end)

essai('Simulation : seule la variante montrée prend les clics, à toute place de la superposition (D11)', function()
    local f = fabriqueVues
    local Vues = require 'Vues'
    local p = S.modules.LrBinding.makePropertyTable()
    p.onglet = 'note'
    local recus, boutons, calques = {}, {}, {}
    local variantes = { place = 'overlapping' }
    local noms = { 'apercu', 'proposition', 'note', 'lecon' }
    for _, nom in ipairs(noms) do
        local fm = Vues.masquable(f, Fenetre, Fenetre.egal('onglet', nom))
        boutons[nom] = fm:push_button { title = 'Bouton ' .. nom, action = function() recus[#recus + 1] = 'bouton ' .. nom end }
        calques[nom] = fm:static_text { title = '', width = 72, height = 22, mouse_down = function() recus[#recus + 1] = 'calque ' .. nom end }
        variantes[#variantes + 1] = f:column { width = 300, boutons[nom], calques[nom] }
    end
    local ok, erreur = ouvrirEssai(f:column { bind_to_object = p, f:column(variantes) }, function()
        -- Dessous (Aperçu), au milieu (Note) et au-dessus (Leçon), comme D11.
        for _, montre in ipairs({ 'apercu', 'note', 'lecon' }) do
            p.onglet = montre
            for _, nom in ipairs(noms) do
                if nom == montre then
                    S.cliquer(boutons[nom])
                    S.cliquer(calques[nom])
                else
                    refuse(function() S.cliquer(boutons[nom]) end, 'D11', 'bouton ' .. nom .. ' sous ' .. montre)
                    refuse(function() S.cliquer(calques[nom]) end, 'D11', 'calque ' .. nom .. ' sous ' .. montre)
                end
            end
        end
    end)
    assert(ok, erreur)
    egal('bouton apercu calque apercu bouton note calque note bouton lecon calque lecon', table.concat(recus, ' '))
end)

essai('Simulation : mesures sans règle — cadre de la fenêtre (D7), bezel des square_button (D5), encre (D9), radio inactif (D12)', function()
    local largeur, hauteur = S.contenuPourFenetre(1280, 800)
    egal(1278, largeur, 'contenu d\'une fenêtre de 1 280 de large')
    egal(766, hauteur, 'contenu d\'une fenêtre de 800 de haut')
    largeur, hauteur = S.fenetrePourContenu(1278, 765)
    egal(1280, largeur, 'fenêtre mesurée (D7)')
    egal(799, hauteur, 'fenêtre mesurée (D7)')
    local f = fabriqueVues
    local function carre(args)
        args.title, args.action = '☆', rien
        return f:square_button(args)
    end
    egal(17, S.bezelVisible(carre({})), 'regular')
    egal(15, S.bezelVisible(carre({ size = 'small' })), 'small')
    egal(11, S.bezelVisible(carre({ size = 'mini' })), 'mini')
    egal(20, S.bezelVisible(carre({ height = 22 })), 'height 22')
    egal(22, S.bezelVisible(carre({ size = 'small', height = 24 })), 'height 24, small')
    egal(1, S.ENCRE_SOUS_CHASSE.min)
    egal(2, S.ENCRE_SOUS_CHASSE.max)
    egal(true, S.RADIO_INACTIF_A_REPOSER)
end)

essai("Fenêtre : sans bouton par défaut, Retour dans « Rechercher » n'envoie rien ; Retour dans la demande part par l'envoi "
    .. "automatique (D1, décision de repli)", function()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.selection = { S.photoActive }
    local envoyer, envoyees = Fenetre.envoyer, {}
    local construite = false
    S.pendantFenetre = function(args)
        construite = true
        local p = Fenetre.p
        egal(nil, S.boutonParDefaut(), 'aucun bouton par défaut')
        local champ, recherche
        for _, v in ipairs(S.vues(args.contents)) do
            if v.genre == 'edit_field' and type(v.args.value) == 'table' and v.args.value.key == 'saisie' then
                champ = v
            elseif v.genre == 'edit_field' and type(v.args.value) == 'table' and v.args.value.key == 'recherche' then
                recherche = v
            end
        end
        vrai(champ and recherche, 'champ de demande et « Rechercher »')
        egal(false, champ.args.immediate)
        egal(true, recherche.args.immediate)
        Fenetre.envoyer = function(texte) envoyees[#envoyees + 1] = texte end
        S.taper(recherche, 'zz')
        egal('zz', p.recherche, 'la recherche suit la frappe')
        local taches = #S.taches
        vrai(not S.retour(recherche), 'Retour dans « Rechercher » ne déclenche rien')
        egal(taches, #S.taches, 'aucune tâche')
        egal(nil, Fenetre.envoiAuto, 'aucun envoi prévu')
        p.recherche = ''
        -- Retour dans la demande : le champ validé, puis l'envoi automatique, qui vide le champ.
        S.taper(champ, 'Bonjour')
        egal('', p.saisie, 'pas encore validée')
        egal(taches, #S.taches, 'rien avant Retour')
        vrai(not S.retour(champ), 'aucun bouton ne prend Retour')
        egal('Bonjour', p.saisie, 'validée par Retour')
        egal(taches + 1, #S.taches, 'envoi automatique prévu')
        S.taches[#S.taches]()
        egal('Bonjour', table.concat(envoyees, ' | '), 'envoyée une fois')
        egal('', p.saisie, 'le champ se vide')
        egal('', S.texteChamp(champ))
        Fenetre.envoyer = envoyer
    end
    local ok, erreur = pcall(Fenetre.afficher)
    Fenetre.envoyer = envoyer
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(construite, 'fenêtre construite')
end)

essai("Fenêtre : un clic sur 📋 ou sur un segment (calque) valide la demande tapée sans l'envoyer (D3) ; une carte cachée ne prend aucun clic (D11)", function()
    S.photoActive = S.photo(53636309, 'DSCF4961.RAF')
    S.selection = { S.photoActive }
    local envoyer, envoyees = Fenetre.envoyer, {}
    -- La tâche de 📋 lirait le vrai presse-papiers (jamais dans un essai) : elle ne colle rien ici,
    -- et seule la tâche de l'envoi automatique tourne.
    local coller, collages = Fenetre.coller, 0
    local construite = false
    S.pendantFenetre = function(args)
        construite = true
        local p = Fenetre.p
        Fenetre.coller = function() collages = collages + 1 end
        local champ
        for _, v in ipairs(S.vues(args.contents)) do
            if v.genre == 'edit_field' and type(v.args.value) == 'table' and v.args.value.key == 'saisie' then
                champ = v
            end
        end
        Fenetre.envoyer = function(texte) envoyees[#envoyees + 1] = texte end
        -- 📋 : la demande validée par le clic reste dans le champ, rien ne part.
        local taches = #S.taches
        S.taper(champ, 'Avec une photo')
        S.cliquer(parInfobulle(args.contents, INFOBULLE_COLLER))
        egal('Avec une photo', p.saisie, 'validée par le clic')
        egal(nil, Fenetre.envoiAuto, "le bouton annule l'envoi automatique")
        egal(taches + 2, #S.taches, "l'envoi automatique prévu par la validation, puis la tâche de 📋")
        S.taches[taches + 1]()
        egal(0, #envoyees, 'rien envoyé')
        egal('Avec une photo', S.texteChamp(champ), 'le texte reste dans le champ')
        -- Un segment (son calque) : de même (Fenetre.calque annule l'envoi automatique).
        S.taper(champ, ', Proposition')
        egal('notation', p.onglet)
        local refuser, changer = S.trouverBouton(args.contents, 'Refuser'), S.trouverBouton(args.contents, 'Changer…')
        refuse(function() S.cliquer(refuser) end, 'D11', 'Refuser, carte Proposition cachée')
        taches = #S.taches
        S.cliquer(parInfobulle(args.contents, 'Proposition'))
        egal('proposition', p.onglet)
        egal('Avec une photo, Proposition', p.saisie, "validée par le clic de l'onglet")
        egal(nil, Fenetre.envoiAuto, "l'onglet annule l'envoi automatique")
        vrai(#S.taches > taches, "l'envoi automatique prévu par la validation")
        S.taches[taches + 1]()
        egal(0, #envoyees, 'rien envoyé')
        -- La carte Note est cachée ; Refuser est montré, inactif sans proposition.
        refuse(function() S.cliquer(changer) end, 'D11', 'Changer…, carte Note cachée')
        refuse(function() S.cliquer(refuser) end, 'inactive', 'Refuser sans proposition')
        S.cliquer(parInfobulle(args.contents, 'Note'))
        p.saisie = ''
        Fenetre.envoyer, Fenetre.coller = envoyer, coller
    end
    local ok, erreur = pcall(Fenetre.afficher)
    Fenetre.envoyer, Fenetre.coller = envoyer, coller
    egal(0, collages, 'la tâche de 📋 ne tourne pas')
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(construite, 'fenêtre construite')
end)

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

-- La garde de la simulation, éprouvée par /usr/bin/true : même sans elle, rien ne lirait le vrai
-- presse-papiers.
essai('Simulation : presse-papiers.js ne part qu\'avec un presse-papiers nommé (jamais le vrai)', function()
    local execute = S.modules.LrTasks.execute
    refuse(function() execute("/usr/bin/true '/m/presse-papiers.js' '/t/Collees'  > /dev/null") end, 'presse-papiers nommé',
        'sans nom')
    egal(0, execute("/usr/bin/true '/m/presse-papiers.js' '/t/Collees' 'DeveloppeurEssai' > /dev/null"), 'avec un nom')
end)

essai('Coller : image et fichier du presse-papiers (presse-papiers nommé, jamais le vrai)', function()
    local nom = 'DeveloppeurEssai'
    local function osa(code)
        return S.executer("/usr/bin/osascript -l JavaScript -e " .. S.q("ObjC.import('AppKit'); var pp = $.NSPasteboard.pasteboardWithName('" .. nom .. "'); pp.clearContents; " .. code .. "; 'ok'") .. " >/dev/null")
    end
    local png = S.plugin .. '/' .. require('Dispositions').imageVide('claire')
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
    egal('1.2', Composants.module(), 'la version de Info.lua')
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
