-- essais-moteur.lua : essais du moteur de conversation pour la notation, hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : consignes des notes et des passes, séance de notation
-- (sa conversation, sans changer celle de la fenêtre Claude), consignes écrites dans le dossier de
-- la session, élément « notation » du fil (entrée de propose_ratings, réponse du connecteur),
-- stockage des notes. Le moteur est éprouvé avec faux-claude.sh (cas NOTE-LES) : ni Claude, ni
-- quota ; les fichiers vont dans un dossier personnel temporaire.
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

local Json = require 'Json'
local Conversation = require 'Conversation'
local Consignes = require 'Consignes'
local Fil = require 'Fil'
local Metriques = require 'Metriques'
local Chemins = require 'Chemins'
local Stockage = require 'Stockage'
local Fichiers = require 'Fichiers'

local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')

-- Une séance du registre des notes (Notation.seance), telle que la fenêtre Séance la donne.
local SEANCE = {
    id = 'seance-essai', titre = 'Sortie aux dunes', source = { portee = 'collection', collection = 900 },
    photos = { 53636309, 53636310, 53636311 }, passe = 2, cree = 1000,
}

-- Les notes d'un appel de propose_ratings (entrée de l'outil, comme Claude Code la rend).
local function entreeNotes()
    return {
        pass = 2, session = 'seance-essai',
        ratings = {
            { photo_id = 53636309, rating = 5, reason = 'Tient seule.', to_check = false,
                criteria = { impact = 'Fort', qualities = 'Lumière douce', technical_floor = 'Nette (44)', finish = 'Rien à reprendre' } },
            { photo_id = 53636310, flag = 'reject', reason = 'Flou de bougé involontaire.', to_check = true,
                criteria = { impact = 'Aucun', qualities = 'Sujet coupé', technical_floor = 'Floue (9)' } },
            { photo_id = 53636311, rating = 2, reason = 'Correcte.',
                criteria = { impact = 'Faible', qualities = 'Fond chargé', technical_floor = 'Douce (28)' } },
        },
    }
end

local REPONSE = '{"seance": "seance-essai", "propositions": [{"photo": 53636309, "fichier": "DSCF4961.RAF", "note_avant": 0, "drapeau_avant": "aucun", "etat": "proposee"}, '
    .. '{"photo": 53636310, "fichier": "DSCF4962.RAF", "note_avant": 2, "drapeau_avant": "aucun", "etat": "proposee"}], '
    .. '"refusees": [{"photo": 53636311, "raison": "photo introuvable"}]}'

-- Une conversation avec un appel de propose_ratings (sans sa réponse).
local function avecNotation(entree)
    local c = Conversation.nouvelleSeance('Sortie aux dunes', 'seance-essai', 1000)
    Conversation.ajouterDemande(c, 'Passe 2', 1000)
    Conversation.appliquer(c, { genre = 'assistant', blocs = {
        { genre = 'outil', id = 'n1', nom = 'mcp__developpeur__propose_ratings', entree = entree or entreeNotes() },
    } }, 1001)
    return c, c.elements[#c.elements]
end

-- Consignes ------------------------------------------------------------------------------------

essai('Consignes : puce Notes des garde-fous et message du bouton Noter', function()
    local debut = Consignes.texte:find('## Garde-fous', 1, true)
    local fin = Consignes.texte:find('## Titre de la conversation', 1, true)
    vrai(debut and fin, 'sections des garde-fous et du titre')
    local gardeFous = Consignes.texte:sub(debut, fin)
    contient(gardeFous, '- Notes (étoiles et drapeau Rejeter) : propose-les par propose_ratings', 'puce Notes')
    contient(gardeFous, 'jamais set_metadata pour une note', 'puce Notes')
    contient(gardeFous, 'Jamais 5 ★', 'puce Notes')
    vrai(not Consignes.texte:find('\\\n', 1, true), 'lignes recollées')
    contient(Consignes.noterPhoto, 'propose_ratings', 'bouton Noter')
    contient(Consignes.noterPhoto, 'photo active', 'bouton Noter')
    contient(Consignes.noterPhoto, 'jamais 5 ★', 'bouton Noter')
end)

essai('Consignes : les quatre passes, une question chacune', function()
    egal(4, #Consignes.passes)
    local titres = { '1 · Rejets', '2 · Trois étoiles', '3 · Quatre étoiles', '4 · Cinq étoiles' }
    for n, passe in ipairs(Consignes.passes) do
        egal(titres[n], passe.titre)
        vrai(type(passe.question) == 'string' and passe.question ~= '', 'question de la passe ' .. n)
        if n < 4 then
            local m = passe.message(SEANCE)
            contient(m, 'Passe ' .. n .. ' de la séance de notation', 'passe ' .. n)
            contient(m, 'Séance « Sortie aux dunes » (collection 900), 3 photos : 53636309, 53636310, 53636311.', 'passe ' .. n)
            contient(m, 'propose_ratings avec pass = ' .. n .. ' et session = "seance-essai".', 'passe ' .. n)
            egal(nil, passe.seul)
        else
            -- 5 ★ : l'utilisateur seul ; la passe ne se lance pas (aucun message pour Claude).
            egal(nil, passe.message, 'passe 4 : rien à envoyer à Claude')
            egal('À vous seul : revoyez vos 4 ★ après le développement.', passe.seul)
        end
    end
    contient(Consignes.passes[1].message(SEANCE), 'to_check = true', 'passe 1 : les douteux')
    -- Une sélection (sans collection), une seule photo, puis une séance sans identifiant ni photo.
    local m = Consignes.passes[2].message({ id = 'S2', titre = 'Sélection', source = { portee = 'selection' }, photos = { 42 } })
    contient(m, 'Séance « Sélection », 1 photo : 42.')
    vrai(not m:find('collection', 1, true), 'pas de collection pour une sélection')
    m = Consignes.passes[1].message({})
    contient(m, 'Séance, 0 photos : aucune photo.')
    contient(m, 'propose_ratings avec pass = 1.')
end)

essai("Consignes : celles d'une séance de notation, en plus de celles de la fenêtre", function()
    egal(Consignes.texte, Consignes.pour(Conversation.nouvelle()), 'retouche : celles de la fenêtre seules')
    egal(Consignes.texte, Consignes.pour(nil))
    local s = Consignes.pour(Conversation.nouvelleSeance('Sortie aux dunes', 'S'))
    egal(1, (s:find(Consignes.texte, 1, true)), 'celles de la fenêtre en tête')
    contient(s, '# Séance de notation')
    contient(Consignes.texteNotation, 'propose_ratings', 'consignes de séance')
    contient(Consignes.texteNotation, 'Jamais set_metadata', 'consignes de séance')
    contient(Consignes.texteNotation, 'Jamais 5 ★', 'consignes de séance')
    contient(Consignes.texteNotation, 'Pas de ligne [titre : …]', 'consignes de séance')
    vrai(not Consignes.texteNotation:find('\\\n', 1, true), 'lignes recollées')
end)

-- Conversation ---------------------------------------------------------------------------------

essai('Conversation : séance de notation, titre choisi dès sa création', function()
    local c = Conversation.nouvelleSeance('  Sortie aux dunes ', 'seance-essai', 1000)
    egal('notation', c.genre)
    egal('Sortie aux dunes', c.titre)
    egal(true, c.titreChoisi)
    egal('seance-essai', c.seance)
    vrai(Conversation.estSeance(c))
    vrai(not Conversation.estSeance(Conversation.nouvelle()))
    vrai(not Conversation.estSeance(nil))
    egal('Séance de notation', Conversation.nouvelleSeance(nil).titre, 'titre par défaut')
    local m = Conversation.messagePourClaude(c, 'Passe 1', '[Lightroom : séance de notation « Sortie aux dunes », 3 photos ; passe 1]')
    vrai(m:find('^%[Lightroom : séance de notation'), m)
    vrai(not m:find('[titre', 1, true), 'pas de rappel du titre')
    Conversation.ajouterDemande(c, 'Passe 1 : rejeter ou non ?', 1001)
    egal('Sortie aux dunes', c.titre, 'la première demande ne change pas le titre')
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'texte', texte = '[titre : Dunes]\nPasse faite.' } } })
    egal('Sortie aux dunes', c.titre, 'un marqueur ne change pas le titre')
    egal('Passe faite.', c.elements[#c.elements].texte, 'marqueur retiré')
end)

essai("Conversation : notes proposées, de l'entrée de l'outil à la réponse du connecteur", function()
    local c, e = avecNotation()
    egal('outil', c.elements[2].genre)
    egal('propose_ratings · 3 photos', c.elements[2].texte)
    egal('notation', e.genre)
    egal('enCours', e.etat)
    egal('n1', e.appel)
    egal(2, e.passe)
    egal('seance-essai', e.seance)
    egal(3, #e.notes)
    local a, b, d = e.notes[1], e.notes[2], e.notes[3]
    egal(4, a.note, '5 étoiles ramenées à 4')
    egal(nil, a.drapeau)
    egal('Fort', a.criteres.impact)
    egal('Lumière douce', a.criteres.qualites)
    egal('Nette (44)', a.criteres.plancher)
    egal('Rien à reprendre', a.criteres.finition)
    egal('Tient seule.', a.raison)
    egal(false, a.a_verifier)
    egal('demandee', a.etat)
    egal('rejetee', b.drapeau)
    egal(nil, b.note)
    egal(true, b.a_verifier)
    egal(nil, b.criteres.finition, 'finition facultative')
    egal(2, d.note)
    -- Le fil montre 4 étoiles, jamais 5.
    local lignes = Fil.lignesElement(e, 3, 600)
    contient(lignes[2].texte, '★★★★☆ photo 53636309', 'note ramenée à 4 à l\'affichage')
    -- La réponse du connecteur : fichiers, notes d'avant, photo refusée.
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'n1', textes = { REPONSE }, images = {}, erreur = false } } })
    egal('fait', e.etat)
    egal('fait', c.elements[2].etat, "l'outil aussi")
    egal('DSCF4961.RAF', a.fichier)
    egal(0, a.note_avant)
    egal('aucun', a.drapeau_avant)
    egal('proposee', a.etat)
    egal('DSCF4962.RAF', b.fichier)
    egal(2, b.note_avant)
    egal('refusee', d.etat)
    egal('photo introuvable', d.refus)
    egal(nil, d.fichier)
    egal(3, #c.elements, 'pas d\'aperçu sans image')
end)

essai('Conversation : standard demandé, entrée sans notes, réponse illisible', function()
    local c = avecNotation({ read_standard = true })
    egal('outil', c.elements[#c.elements].genre, 'read_standard : pas de notation')
    -- Le standard demandé avec des notes : le connecteur les range, le fil les montre.
    local entree = entreeNotes()
    entree.read_standard = true
    local _, avecStandard = avecNotation(entree)
    egal('notation', avecStandard.genre, 'read_standard avec ratings : notation')
    egal(#entreeNotes().ratings, #avecStandard.notes)
    c = avecNotation({ pass = 1 })
    egal('outil', c.elements[#c.elements].genre, 'sans ratings : pas de notation')
    local _, e = avecNotation()
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'autre', textes = { REPONSE }, images = {}, erreur = false } } })
    egal('enCours', e.etat, "la réponse d'un autre appel ne la touche pas")
    local c2, e2 = avecNotation()
    Conversation.appliquer(c2, { genre = 'resultats', resultats = { { idOutil = 'n1', textes = { 'rangé' }, images = {}, erreur = false } } })
    egal('fait', e2.etat)
    egal('proposee', e2.notes[1].etat, 'réponse illisible : notes rangées')
    egal(nil, Conversation.notesLues({ 'pas du JSON', '{"x": 1}' }))
    local lues = Conversation.notesLues({ '{"seance": null, "propositions": [{"photo": "53636309", "note_avant": null}]}' })
    egal(nil, lues.seance, 'seance nulle')
    egal(nil, lues.propositions['53636309'].note_avant, 'note nulle')
    egal('53636309', Conversation.clePhoto(53636309))
    egal('53636309', Conversation.clePhoto('53636309'))
end)

essai('Conversation : notes refusées par le connecteur, notes interrompues', function()
    local c, e = avecNotation()
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'n1', erreur = true, images = {},
        textes = { "Claude ne propose jamais 5 étoiles : c'est à l'utilisateur." } } } })
    egal('erreur', e.etat)
    egal("Claude ne propose jamais 5 étoiles : c'est à l'utilisateur.", e.texte)
    for _, x in ipairs(e.notes) do
        egal('refusee', x.etat)
    end
    egal('erreur', c.elements[2].etat)
    local lignes = Fil.lignesElement(e, 3, 600)
    egal('erreur', lignes[1].icone)
    contient(lignes[1].texte, 'Notes non rangées · passe 2 · 3 photos : Claude ne propose jamais 5 étoiles', 'titre')
    local c2, e2 = avecNotation()
    Conversation.appliquer(c2, { genre = 'fin', reussie = false, interrompue = true, session = '' })
    egal('erreur', e2.etat, 'interrompue avant la réponse')
end)

-- Fil ------------------------------------------------------------------------------------------

essai("Fil : lignes d'une notation", function()
    egal('☆☆☆☆☆', Fil.etoiles(0))
    egal('★★★☆☆', Fil.etoiles(3))
    egal('★★★★★', Fil.etoiles(5))
    egal('★★★★★', Fil.etoiles(9))
    egal('☆☆☆☆☆', Fil.etoiles(nil))
    local c, e = avecNotation()
    local lignes = Fil.lignesElement(e, 3, 600)
    egal(4, #lignes)
    egal('proposition', lignes[1].genre)
    egal('cours', lignes[1].icone, 'en cours')
    egal('Notes proposées · passe 2 · 3 photos', lignes[1].texte)
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'n1', textes = { REPONSE }, images = {}, erreur = false } } })
    lignes = Fil.lignesElement(e, 3, 600)
    egal('proposition', lignes[1].icone, 'rangées')
    for k = 2, 4 do
        egal('outil', lignes[k].genre)
        egal(3, lignes[k].element)
        egal(nil, lignes[k].icone)
    end
    egal('  ★★★★☆ DSCF4961.RAF · Tient seule.', lignes[2].texte)
    egal('  ⚑ Rejeter DSCF4962.RAF · à vérifier · Flou de bougé involontaire.', lignes[3].texte)
    egal('  ✕ ★★☆☆☆ photo 53636311 · photo introuvable', lignes[4].texte)
    -- Une ligne par photo, coupée à la largeur.
    e.notes[1].raison = string.rep('Une raison bien trop longue pour la colonne. ', 10)
    lignes = Fil.lignesElement(e, 3, 300)
    egal(4, #lignes, 'une ligne par photo')
    vrai(Fil.largeur(lignes[2].texte, 'mono') <= 300, 'ligne coupée')
    egal('…', lignes[2].texte:sub(-3), 'coupée par « … »')
    -- Au plus 12 photos, puis « … et N autres ».
    local beaucoup = { pass = 3, ratings = {} }
    for k = 1, 14 do
        beaucoup.ratings[k] = { photo_id = k, rating = 3, reason = 'R', criteria = { impact = 'i', qualities = 'q', technical_floor = 't' } }
    end
    local _, f = avecNotation(beaucoup)
    lignes = Fil.lignesElement(f, 3, 600)
    egal(1 + 12 + 1, #lignes)
    egal('Notes proposées · passe 3 · 14 photos', lignes[1].texte)
    egal('  … et 2 autres', lignes[#lignes].texte)
    beaucoup.ratings[14] = nil
    _, f = avecNotation(beaucoup)
    lignes = Fil.lignesElement(f, 3, 600)
    egal('  … et 1 autre', lignes[#lignes].texte)
    beaucoup.ratings[13] = nil
    _, f = avecNotation(beaucoup)
    egal(13, #Fil.lignesElement(f, 3, 600), '12 photos : toutes montrées')
    -- Dans le fil entier : séparée de l'outil par une ligne vide.
    lignes = Fil.lignes(c, 610)
    local titre
    for k, l in ipairs(lignes) do
        if l.genre == 'proposition' then
            titre = k
            break
        end
    end
    vrai(titre and lignes[titre - 1].genre == 'vide', 'ligne vide avant les notes')
end)

essai('Fil : le cache suit les notes', function()
    local c, e = avecNotation()
    local cache = {}
    local avant = Fil.lignes(c, 610, cache)
    local function texteDe(lignes)
        local t = {}
        for _, l in ipairs(lignes) do
            t[#t + 1] = (l.icone or '') .. '|' .. l.texte
        end
        return table.concat(t, '\n')
    end
    egal(texteDe(avant), texteDe(Fil.lignes(c, 610, cache)), 'mêmes lignes tant que rien ne change')
    -- La réponse : l'état et les fichiers changent l'affichage.
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'n1', textes = { REPONSE }, images = {}, erreur = false } } })
    local apres = texteDe(Fil.lignes(c, 610, cache))
    contient(apres, 'DSCF4961.RAF', 'fichier montré après la réponse')
    -- Une note seule qui change (sans changer l'état de l'élément) : recoupée aussi.
    e.notes[1].etat = 'refusee'
    e.notes[1].refus = 'déjà notée'
    contient(texteDe(Fil.lignes(c, 610, cache)), '✕ ★★★★☆ DSCF4961.RAF · déjà notée', 'note changée')
    e.notes[2].a_verifier = false
    vrai(not texteDe(Fil.lignes(c, 610, cache)):find('à vérifier', 1, true), '« à vérifier » retiré')
end)

essai('Metriques : étoiles et drapeau mesurés dans les trois polices', function()
    for _, police in ipairs({ 'texte', 'gras', 'mono' }) do
        for _, c in ipairs({ '★', '☆', '⚑' }) do
            vrai(type(Metriques[police].chasse[c]) == 'number', police .. ' : ' .. c .. ' non mesuré')
        end
    end
    egal(5 * Metriques.texte.chasse['★'], Fil.largeur('★★★★★', 'texte'))
    vrai(Fil.largeur('★☆⚑', 'texte') ~= 3 * Metriques.texte.chasse['M'], 'pas compté comme « M »')
end)

-- Stockage -------------------------------------------------------------------------------------

essai('Stockage : séance et notes relues, liste vide en tableau', function()
    local c, e = avecNotation()
    c.elements[#c.elements + 1] = { id = 'vide', genre = 'notation', texte = '', date = 1002, etat = 'fait', images = {}, changements = {}, notes = {} }
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    contient(texte, '"notes":[]', 'liste vide écrite en tableau')
    local brut = Json.decode(texte)
    egal(nil, brut.elements[1].notes, 'pas de notes pour une demande')
    local relue = Stockage.lire(c.id)
    egal('notation', relue.genre)
    egal('seance-essai', relue.seance)
    egal(true, relue.titreChoisi)
    egal('Sortie aux dunes', relue.titre)
    local n = relue.elements[3]
    egal('notation', n.genre)
    egal('erreur', n.etat, 'en cours quand Lightroom s\'est fermé')
    egal(3, #n.notes)
    egal(4, n.notes[1].note)
    egal('Nette (44)', n.notes[1].criteres.plancher)
    egal('rejetee', n.notes[2].drapeau)
    egal(0, #relue.elements[4].notes)
    egal(e.id, n.id)
    -- Relue, elle se montre encore dans le fil.
    local lignes = Fil.lignesElement(n, 3, 600)
    egal('Notes non rangées · passe 2 · 3 photos', lignes[1].texte)
    Stockage.supprimer(c.id)
end)

-- Moteur, avec le faux Claude Code --------------------------------------------------------------

local faux = dossierTests .. '/faux-claude.sh'
local prefs = Chemins.prefs()
prefs.cheminClaude = faux
prefs.cheminConnecteur = '/bin/echo'

-- Une petite image JPEG (en base64) pour le résultat d'outil du faux Claude Code (cas par défaut).
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-230.png') .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' '
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

local CONTEXTE = '[Lightroom : séance de notation « Sortie aux dunes », 3 photos ; passe 2]'
local principale, seance

essai('Moteur : une séance de notation ne change pas la conversation ouverte', function()
    Moteur.charger()
    Moteur.nouvelle()
    vrai(Moteur.envoyer('Bonjour', { modele = 'haiku' }))
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    principale = Moteur.courante
    egal(nil, Moteur.enCours, 'plus rien en cours')
    seance = Moteur.nouvelleSeance({ titre = 'Sortie aux dunes', seance = 'seance-essai' })
    egal(principale, Moteur.courante, 'conversation ouverte inchangée')
    egal('notation', seance.genre)
    egal('Sortie aux dunes', seance.titre)
    egal(seance, Moteur.trouver(seance.id))
    egal(principale, Moteur.trouver(principale.id))
    egal(nil, Moteur.trouver('inconnue'))
    egal(seance, Moteur.nouvelleSeance({ seance = 'seance-essai' }), 'la conversation de la séance est reprise')
    vrai(Moteur.nouvelleSeance({ seance = 'autre-seance' }) ~= seance, 'une autre séance, une autre conversation')
    local ancienne = Moteur.session
    local ok, raison = Moteur.envoyer(Consignes.passes[2].message(SEANCE) .. ' NOTE-LES', { conversation = seance, contexte = CONTEXTE, modele = 'haiku' })
    vrai(ok, raison)
    egal(seance, Moteur.enCours, 'la séance travaille')
    egal(principale, Moteur.courante, 'toujours la même conversation ouverte')
    vrai(ancienne ~= Moteur.session, 'Claude Code relancé pour la séance')
    vrai(attendre(function() return not Moteur.travaille end), 'la passe se termine')
    egal(nil, Moteur.enCours)
    egal(principale, Moteur.courante)
    -- Le fil de la séance : la demande, le texte, l'outil, les notes, la réponse.
    local genres = {}
    for _, e in ipairs(seance.elements) do
        genres[#genres + 1] = e.genre
    end
    egal('dany claude outil notation claude', table.concat(genres, ' '))
    egal('Sortie aux dunes', seance.titre, 'titre gardé')
    local n = seance.elements[4]
    egal('fait', n.etat)
    egal(2, n.passe)
    egal('seance-essai', n.seance)
    egal(3, #n.notes)
    egal('DSCF4961.RAF', n.notes[1].fichier)
    egal(3, n.notes[1].note)
    egal('rejetee', n.notes[2].drapeau)
    egal(true, n.notes[2].a_verifier)
    egal('refusee', n.notes[3].etat)
    egal('photo introuvable', n.notes[3].refus)
    -- Le message envoyé : le contexte de la séance à la place de la photo active, pas de rappel du titre.
    local entree = Fichiers.lire(Moteur.session.dossier .. '/entree.jsonl')
    local message = Json.decode((entree:match('[^\n]+'))).message.content[1].text
    egal(1, (message:find(CONTEXTE, 1, true)), 'contexte de la séance en tête')
    vrai(not message:find('aucune photo active', 1, true), 'pas de ligne de la photo active')
    vrai(not message:find('[titre', 1, true), 'pas de rappel du titre')
    contient(message, 'pass = 2 et session = "seance-essai"', 'message de la passe')
    -- Les consignes de la séance, dans le dossier de la session.
    local consignes = Moteur.session.dossier .. '/consignes.md'
    contient(arguments(), '--append-system-prompt-file\n' .. consignes, 'consignes de la session')
    contient(Fichiers.lire(consignes), '# Séance de notation', 'consignes de séance')
    contient(Fichiers.lire(consignes), '# Fenêtre Claude dans Lightroom', 'consignes de la fenêtre')
    -- Rangée sur le disque avec son genre.
    local relue = Stockage.lire(seance.id)
    egal('notation', relue.genre)
    egal('seance-essai', relue.seance)
    egal('notation', relue.elements[4].genre)
end)

essai('Moteur : retour à la conversation ouverte, sans les consignes de la séance', function()
    local dossierSeance = Moteur.session.dossier
    local avant = #seance.elements
    vrai(Moteur.envoyer('Encore', { modele = 'haiku' }))
    egal(principale, Moteur.enCours)
    vrai(attendre(function() return not Moteur.travaille end))
    vrai(Moteur.session.dossier ~= dossierSeance, 'Claude Code relancé pour la conversation ouverte')
    contient(arguments(), '--resume\nsession-essai', 'session de la conversation reprise')
    local consignes = Fichiers.lire(Moteur.session.dossier .. '/consignes.md')
    contient(consignes, '# Fenêtre Claude dans Lightroom')
    vrai(not consignes:find('# Séance de notation', 1, true), 'pas les consignes de séance')
    egal(avant, #seance.elements, 'rien dans la séance')
    local derniere
    for _, e in ipairs(principale.elements) do
        if e.genre == 'dany' then
            derniere = e
        end
    end
    egal('Encore', derniere.texte, 'la demande va à la conversation ouverte')
    vrai(Fichiers.existe(dossierSeance .. '/consignes.md'), 'chaque session garde les siennes')
end)

essai("Moteur : refus pendant que Claude travaille dans l'autre conversation", function()
    vrai(Moteur.envoyer('Passe 2 LENT', { conversation = seance.id, contexte = CONTEXTE }), 'séance visée par son identifiant')
    egal(seance, Moteur.enCours)
    vrai(attendre(function()
        local d = seance.elements[#seance.elements]
        return d.genre == 'claude' and d.partiel
    end), 'Claude écrit dans la séance')
    local ok, raison = Moteur.envoyer('Une autre demande')
    vrai(not ok, 'refusée')
    contient(raison, 'Claude travaille dans la séance de notation', 'refus')
    ok, raison = Moteur.envoyer('Et dans la séance', { conversation = seance })
    vrai(not ok)
    contient(raison, 'Claude travaille encore', 'refus dans la même conversation')
    vrai(not Moteur.ouvrir(principale.id), 'ouvrir refusé')
    vrai(not Moteur.nouvelle(), 'nouvelle conversation refusée')
    ok, raison = Moteur.supprimer(seance.id)
    vrai(not ok)
    contient(raison, 'travaille dans cette conversation')
    ok, raison = Moteur.supprimer(principale.id)
    vrai(not ok, 'la conversation ouverte ne se supprime pas pendant le travail de la séance')
    contient(raison, 'séance de notation')
    contient(Moteur.texteTravail(0), 'Claude travaille · dans la séance de notation', 'vu de la fenêtre Claude')
    vrai(not Moteur.texteTravail(0, seance):find('dans la', 1, true), 'vu de la séance')
    egal(principale, Moteur.courante)
    Moteur.interrompre()
    vrai(attendre(function() return not Moteur.travaille end, 15), 'interruption')
    egal('Interrompu à votre demande.', seance.elements[#seance.elements].texte)
    egal(nil, Moteur.enCours)
    egal(principale, Moteur.courante)
    egal('', Moteur.texteTravail(0))
end)

essai("Moteur : vue d'une séance sans conversation, un travail de la fenêtre Claude se dit ailleurs", function()
    local travaille, enCours = Moteur.travaille, Moteur.enCours
    Moteur.travaille, Moteur.enCours = true, Moteur.courante
    local ok, erreur = pcall(function()
        contient(Moteur.texteTravail(0, false), 'Claude travaille · dans la fenêtre Claude', 'séance sans conversation')
        vrai(not Moteur.texteTravail(0):find('dans la', 1, true), 'vu de la fenêtre Claude')
    end)
    Moteur.travaille, Moteur.enCours = travaille, enCours
    vrai(ok, tostring(erreur))
end)

essai('Moteur : séance introuvable ou ouverte comme conversation', function()
    local ok, raison = Moteur.envoyer('x', { conversation = 'inconnue' })
    vrai(not ok)
    contient(raison, 'introuvable')
    ok, raison = Moteur.ouvrir(seance.id)
    vrai(not ok, 'une séance ne devient pas la conversation ouverte')
    contient(raison, 'séance de notation')
    egal(principale, Moteur.courante)
    egal(false, Moteur.travaille)
end)

essai("Moteur : au chargement, une séance n'est jamais la conversation ouverte", function()
    if Moteur.session then
        local s = Moteur.session
        Moteur.arreterSession()
        vrai(attendre(function() return Fichiers.existe(s.dossier .. '/fin.code') end, 8), 'Claude Code fermé')
    end
    seance.modifiee = os.time() + 100
    Stockage.enregistrer(seance)
    Moteur.charge = false
    Moteur.conversations = {}
    Moteur.courante = nil
    Moteur.charger()
    egal('notation', Moteur.conversations[1].genre, 'la séance est la plus récente')
    egal(principale.id, Moteur.courante.id, 'la conversation de retouche s\'ouvre')
    local relue = Moteur.trouver(seance.id)
    vrai(relue and relue.genre == 'notation', 'séance rechargée')
    egal(relue, Moteur.nouvelleSeance({ seance = 'seance-essai' }), 'reprise après une relance')
    principale, seance = Moteur.courante, relue
end)

essai('Moteur : supprimer la conversation ouverte ne rouvre pas une séance', function()
    -- Seules restent la séance et la conversation ouverte : une nouvelle conversation s'ouvre.
    for _, c in ipairs(Moteur.conversations) do
        if c ~= principale and c ~= seance then
            Moteur.supprimer(c.id)
        end
    end
    vrai(Moteur.supprimer(principale.id))
    vrai(not Conversation.estSeance(Moteur.courante), 'pas de séance ouverte')
    egal(0, #Moteur.courante.elements, 'une nouvelle conversation')
    vrai(Moteur.supprimer(seance.id))
    egal(nil, Moteur.trouver(seance.id))
    egal(false, Fichiers.existe(Stockage.dossier(seance.id)), 'à la corbeille')
end)

-- Fin ------------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
