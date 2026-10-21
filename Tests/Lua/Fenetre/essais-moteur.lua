-- essais-moteur.lua : essais du moteur de conversation pour la notation, hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : consignes des notes et des passes, consignes de la 1.2
-- (peau dosée, section Écran, invites Portrait, Paysage et Noir et blanc du tireur), séance de notation
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

-- Les notes d'un appel de propose_ratings (entrée de l'outil, comme Claude Code la rend).
local function entreeNotes()
    return {
        pass = 2,
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

local REPONSE = '{"propositions": [{"photo": 53636309, "fichier": "DSCF4961.RAF", "note_avant": 0, "drapeau_avant": "aucun", "etat": "proposee"}, '
    .. '{"photo": 53636310, "fichier": "DSCF4962.RAF", "note_avant": 2, "drapeau_avant": "aucun", "etat": "proposee"}], '
    .. '"refusees": [{"photo": 53636311, "raison": "photo introuvable"}]}'

-- Une conversation avec un appel de propose_ratings (sans sa réponse).
local function avecNotation(entree)
    local c = Conversation.nouvelle(1000)
    c.titre, c.titreChoisi = 'Sortie aux dunes', true
    Conversation.ajouterDemande(c, 'Note-les', 1000)
    Conversation.appliquer(c, { genre = 'assistant', blocs = {
        { genre = 'outil', id = 'n1', nom = 'mcp__developpeur__propose_ratings', entree = entree or entreeNotes() },
    } }, 1001)
    return c, c.elements[#c.elements]
end

-- Consignes ------------------------------------------------------------------------------------

essai('Consignes : puce Notes des garde-fous, chaque photo traitée notée d\'abord', function()
    local debut = Consignes.texte:find('## Garde-fous', 1, true)
    local fin = Consignes.texte:find('## Titre de la conversation', 1, true)
    vrai(debut and fin, 'sections des garde-fous et du titre')
    local gardeFous = Consignes.texte:sub(debut, fin)
    contient(gardeFous, '- Notes (étoiles et drapeau Rejeter) : par propose_ratings', 'puce Notes')
    -- « Note ces photos » : Claude pose les notes (demandé par Dany le 20 octobre 2026) ; ce que
    -- Dany demande en mots clairs, Claude le fait.
    contient(gardeFous, 'Quand Dany demande que tu notes (« note ces photos », « pose les notes »), apply = true', 'puce Notes')
    contient(gardeFous, "Jamais 5 ★ de toi-même ; s'il en demande, set_metadata", 'puce Notes')
    contient(gardeFous, "- Ce que Dany demande en mots clairs, fais-le", 'demande explicite')
    vrai(not Consignes.texte:find('\\\n', 1, true), 'lignes recollées')
    -- Plus de bouton Évaluer : Claude note d'abord chaque photo qu'il traite, à vérifier (demandé
    -- par Dany le 20 octobre 2026).
    contient(gardeFous, "Toute photo que tu traites, note-la d'abord, avant d'y toucher", 'puce Notes')
    contient(gardeFous, "ta note arrive « à vérifier » dans la carte Note", 'puce Notes')
    egal(nil, Consignes.noterPhoto)
end)

-- Une section des consignes, de son titre (« ## … ») au titre suivant.
local function section(titre)
    local debut = Consignes.texte:find('\n## ' .. titre .. '\n', 1, true)
    vrai(debut, 'section ' .. titre)
    local fin = Consignes.texte:find('\n## ', debut + 1, true) or (#Consignes.texte + 1)
    return Consignes.texte:sub(debut, fin - 1)
end

essai('Consignes : peau dosée comme le dit add_mask, plus lisse seulement sur demande (1.2)', function()
    local gardeFous = section('Garde-fous')
    contient(gardeFous, '- Peau : dosée comme le dit add_mask (effect « Peau du visage lisse » par défaut)', 'puce Peau')
    contient(gardeFous, 'smoothing_requested = true', 'puce Peau')
    contient(gardeFous, 'si son guide de style le dit', 'puce Peau')
    local style = section('Style')
    contient(style, '« Peau adoucie » : la dose « Adoucir la peau (Lite) » d\'add_mask', 'style Peau adoucie')
    contient(style, 'rien pour un enfant', 'style Peau adoucie')
    contient(style, 'la moitié de la dose (amount) pour un homme ou une personne âgée', 'style Peau adoucie')
    -- Les chiffres restent au connecteur (Peau.dosage) : la fenêtre y renvoie sans les répéter.
    vrai(not style:find('−35', 1, true) and not style:find('−15', 1, true) and not style:find('amount 50', 1, true),
        'aucune dose chiffrée dans la fenêtre')
    vrai(not Consignes.texte:find('texture et clarté réduites', 1, true), 'ancienne phrase retirée')
    vrai(not Consignes.texte:find('\\\n', 1, true), 'lignes recollées')
    -- La définition du style « Or et peau douce » ne change pas (tests.lua la vérifie mot pour mot).
    egal('tons dorés chaleureux, peau adoucie (texture et clarté réduites sur la peau seulement), contraste doux',
        Consignes.style('or_peau_douce').definition)
end)

essai('Consignes : invites Portrait, Paysage et Noir et blanc, éclaircir et assombrir avec leur avant/après (1.2)', function()
    local vues = {}
    for _, invite in ipairs(Consignes.invites) do
        vues[invite.id] = invite
    end
    for _, id in ipairs({ 'portrait', 'paysage', 'noir_et_blanc' }) do
        vrai(vues[id], 'invite ' .. id)
        contient(vues[id].message, 'éclaircis et assombris comme un tireur', id)
        contient(vues[id].message, "doses d'add_mask", id)
        contient(vues[id].message, 'avant/après de cette étape', id)
        -- Aucune dose chiffrée : elles arrivent par la description d'add_mask.
        vrai(not vues[id].message:find('IL', 1, true) and not vues[id].message:find('%d'), id .. ' sans chiffres')
    end
    contient(vues.portrait.message, "mener l'œil au visage", 'portrait')
    contient(vues.portrait.message, 'Reste naturel.', 'portrait')
    egal('Portrait', vues.portrait.titre)
    vrai(not vues.retouche_pro.message:find('tireur', 1, true), 'retouche pro inchangée')
    -- La méthode reste au connecteur (en-tête de Consignes.lua) : rien dans les consignes.
    vrai(not Consignes.texte:find('tireur', 1, true), 'consignes sans la méthode du tireur')
    egal(6, #Consignes.invites)
end)

essai('Consignes : section Écran, dite une fois par conversation (1.2)', function()
    local ecran = section('Écran')
    contient(ecran, 'sans passer par l\'écran', 'section Écran')
    contient(ecran, 'une fois par conversation', 'section Écran')
    contient(ecran, 'get_status : ecran', 'section Écran')
    contient(ecran, 'la peau ou les couleurs', 'section Écran')
    -- Après le contexte, avant les garde-fous.
    local contexte = Consignes.texte:find('\n## Contexte\n', 1, true)
    local position = Consignes.texte:find('\n## Écran\n', 1, true)
    local gardeFous = Consignes.texte:find('\n## Garde-fous\n', 1, true)
    vrai(contexte < position and position < gardeFous, 'ordre des sections')
    vrai(not Consignes.texte:find('\\\n', 1, true), 'lignes recollées')
end)

essai('Consignes : plus de Séance de notation (retirée le 20 octobre 2026)', function()
    egal(nil, Consignes.passes)
    egal(nil, Consignes.pour)
    egal(nil, Consignes.texteNotation)
    vrai(not Consignes.texte:find('Séance de notation', 1, true), 'consignes sans la Séance')
end)

-- Conversation ---------------------------------------------------------------------------------

essai('Conversation : une ancienne séance de notation se reconnaît (genre notation)', function()
    local c = Conversation.nouvelle(1000)
    c.genre = 'notation'
    vrai(Conversation.estSeance(c))
    vrai(not Conversation.estSeance(Conversation.nouvelle()))
    vrai(not Conversation.estSeance(nil))
    egal(nil, Conversation.nouvelleSeance)
end)

essai("Conversation : notes proposées, de l'entrée de l'outil à la réponse du connecteur", function()
    local c, e = avecNotation()
    egal('outil', c.elements[2].genre)
    egal('propose_ratings · 3 photos', c.elements[2].texte)
    egal('notation', e.genre)
    egal('enCours', e.etat)
    egal('n1', e.appel)
    egal(2, e.passe)
    egal(nil, e.seance)
    egal(nil, e.pose, 'sans apply : proposées')
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

essai('Stockage : notes relues, liste vide en tableau', function()
    local c, e = avecNotation()
    c.elements[#c.elements + 1] = { id = 'vide', genre = 'notation', texte = '', date = 1002, etat = 'fait', images = {}, changements = {}, notes = {} }
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    contient(texte, '"notes":[]', 'liste vide écrite en tableau')
    local brut = Json.decode(texte)
    egal(nil, brut.elements[1].notes, 'pas de notes pour une demande')
    local relue = Stockage.lire(c.id)
    egal(nil, relue.genre)
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
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
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

local principale

essai('Moteur : propose_ratings dans la conversation ouverte, notes dans le fil, consignes de la fenêtre', function()
    Moteur.charger()
    Moteur.nouvelle()
    vrai(Moteur.envoyer('Bonjour', { modele = 'haiku' }))
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    principale = Moteur.courante
    egal(nil, Moteur.enCours, 'plus rien en cours')
    local ok, raison = Moteur.envoyer('Note ces photos NOTE-LES', { modele = 'haiku' })
    vrai(ok, raison)
    egal(principale, Moteur.enCours)
    vrai(attendre(function() return not Moteur.travaille end), 'la notation se termine')
    egal(principale, Moteur.courante)
    local n
    for _, e in ipairs(principale.elements) do
        if e.genre == 'notation' then
            n = e
        end
    end
    vrai(n, 'notes dans le fil de la conversation ouverte')
    egal('fait', n.etat)
    egal(2, n.passe)
    egal(3, #n.notes)
    egal('DSCF4961.RAF', n.notes[1].fichier)
    egal(3, n.notes[1].note)
    egal('rejetee', n.notes[2].drapeau)
    egal(true, n.notes[2].a_verifier)
    egal('refusee', n.notes[3].etat)
    egal('photo introuvable', n.notes[3].refus)
    -- Les consignes de la fenêtre, dans le dossier de la session ; plus celles d'une séance.
    local consignes = Moteur.session.dossier .. '/consignes.md'
    contient(arguments(), '--append-system-prompt-file\n' .. consignes, 'consignes de la session')
    contient(Fichiers.lire(consignes), '# Fenêtre Claude dans Lightroom', 'consignes de la fenêtre')
    vrai(not Fichiers.lire(consignes):find('# Séance de notation', 1, true), 'pas de consignes de séance')
end)

essai("Moteur : refus pendant que Claude travaille", function()
    vrai(Moteur.envoyer('Une demande LENT'))
    egal(principale, Moteur.enCours)
    vrai(attendre(function()
        local d = principale.elements[#principale.elements]
        return d.genre == 'claude' and d.partiel
    end), 'Claude écrit')
    local ok, raison = Moteur.envoyer('Une autre demande')
    vrai(not ok, 'refusée')
    contient(raison, 'Claude travaille encore', 'refus')
    vrai(not Moteur.nouvelle(), 'nouvelle conversation refusée')
    ok, raison = Moteur.supprimer(principale.id)
    vrai(not ok)
    contient(raison, 'travaille dans cette conversation')
    vrai(not Moteur.texteTravail(0):find('dans une autre', 1, true), 'vu de la conversation qui travaille')
    contient(Moteur.texteTravail(0, false), 'dans une autre conversation', 'vu sans conversation')
    Moteur.interrompre()
    vrai(attendre(function() return not Moteur.travaille end, 15), 'interruption')
    egal('Interrompu à votre demande.', principale.elements[#principale.elements].texte)
    egal(nil, Moteur.enCours)
    egal('', Moteur.texteTravail(0))
end)

essai("Moteur : une ancienne séance de notation ne s'ouvre pas, ni au chargement", function()
    if Moteur.session then
        local s = Moteur.session
        Moteur.arreterSession()
        vrai(attendre(function() return Fichiers.existe(s.dossier .. '/fin.code') end, 8), 'Claude Code fermé')
    end
    -- Une conversation de séance d'avant la 1.1.1, plus récente que la conversation ouverte.
    local ancienne = Conversation.nouvelle()
    ancienne.genre, ancienne.titre, ancienne.titreChoisi = 'notation', 'Séance du lac', true
    Conversation.ajouterDemande(ancienne, 'Passe 1 : rejeter ou non ?')
    ancienne.modifiee = os.time() + 100
    Stockage.enregistrer(ancienne)
    Moteur.charge = false
    Moteur.conversations = {}
    Moteur.courante = nil
    Moteur.charger()
    egal('notation', Moteur.conversations[1].genre, "l'ancienne séance est la plus récente")
    egal(principale.id, Moteur.courante.id, "la conversation de retouche s'ouvre")
    local ok, raison = Moteur.ouvrir(ancienne.id)
    vrai(not ok, "une ancienne séance ne s'ouvre pas")
    contient(raison, 'ancienne séance de notation')
    -- Supprimer la conversation ouverte n'ouvre pas l'ancienne séance.
    principale = Moteur.courante
    for _, c in ipairs(Moteur.conversations) do
        if c ~= principale and c.id ~= ancienne.id then
            Moteur.supprimer(c.id)
        end
    end
    vrai(Moteur.supprimer(principale.id))
    vrai(not Conversation.estSeance(Moteur.courante), 'pas de séance ouverte')
    egal(0, #Moteur.courante.elements, 'une nouvelle conversation')
    vrai(Moteur.supprimer(ancienne.id))
    egal(nil, Moteur.trouver(ancienne.id))
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
