-- essais-lecon.lua : la leçon de la photo dans la fenêtre Claude (1.3, lot 13), hors de Lightroom
-- (LuaJIT, Lightroom simulé par Simulation.lua) : l'élément `lecon` du fil, de l'entrée de
-- photo_lesson à la réponse du connecteur (Conversation : points dans l'ordre Lumière, Couleur,
-- Composition, fichier, rangement, refus, interruption, read_facts sans leçon), sa ligne du fil
-- (fenêtre B, lot B4 : plus de carte, la ligne d'actions « Leçon de la photo », ● pendant l'appel, ✕
-- refusée ; cache), son texte pour l'onglet Leçon (Fil.texteLecon : axes balisés, entier, page par
-- page), son stockage (points en tableau, leçon restée en cours relue en erreur), l'onglet Leçon
-- (« Leçon de la photo », Détail…, ▲ ▼, leçon choisie, bascule une fois par leçon arrivée, jamais
-- avec une proposition en attente ni un exercice en cours), la recherche, la section « Leçon de la
-- photo » des consignes, la case Leçon (« [Sans leçon] » joint sans relancer Claude Code), et le cas
-- LECON de bout en bout par relais.sh avec faux-claude.sh. Ni Claude, ni quota ; les fichiers vont
-- dans un dossier personnel temporaire.
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

-- Toutes les vues d'un arbre.
local function vues(contenu)
    local liste = {}
    local function parcourir(v)
        liste[#liste + 1] = v
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant)
            end
        end
    end
    parcourir(contenu)
    return liste
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre.
local function lancerTaches(depuis)
    local i = depuis + 1
    while i <= #S.taches do
        vrai(i - depuis <= 100, 'des tâches sans fin')
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Json = require 'Json'
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai), et
-- une petite image JPEG (en base64) pour son résultat d'outil (cas par défaut).
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' '
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = env .. commande
    end
    return executerOriginal(commande)
end

-- La largeur du texte du fil (Fenetre.largeurTexte : D.texteFil dans la fenêtre B, après la colonne
-- auteur), et celle qu'une ligne ne dépasse jamais, son retrait compris (Fil.occupe).
local D = Dispositions.dimensions()
local LARGEUR = D.texteFil
local LARGEUR_LIGNE = LARGEUR - Fil.MARGE

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Ouvre la fenêtre Claude et appelle fn(p, args) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    if erreur then
        error(erreur, 0)
    end
end

-- Trois points tels que Claude les donne à photo_lesson, dans le désordre (composition d'abord),
-- avec du Markdown, un saut de ligne, un axe inconnu et un axe en double, que la carte écarte.
local function entreeLecon()
    return {
        photo_id = 53636309,
        points = {
            { axis = 'composition', at_capture = "Le flamant au tiers gauche, regard vers le cadre : à refaire.", defects = {} },
            { axis = 'light', missing = "Ciel **brûlé** à 3 %\n: hautes lumières `-40`.", at_capture = "Compenser de −2/3 IL face au ciel clair.",
                defects = { 'blown_highlights' } },
            { axis = 'mood', missing = "Rien.", at_capture = "Rien." },
            { axis = 'color', missing = "Dominante bleue à l'ombre : +400 K.", at_capture = "Balance des blancs Ombre plutôt qu'Auto.",
                defects = { 'color_cast' } },
            { axis = 'light', missing = "Un second point Lumière, écarté.", at_capture = "Écarté." },
        },
    }
end

-- La réponse du connecteur à photo_lesson (Tools+Lecon.swift), en JSON indenté comme JSONCoding.pretty :
-- `lecon` remplace les champs de la leçon, `remarques` la liste des remarques.
local function reponseLecon(lecon, remarques)
    local l = { photo = 53636309, fichier = 'DSCF4961.RAF', rangee = true, remplacee = false, mois = '2026-10', prise_le = '2026-10-12 17:40' }
    for cle, valeur in pairs(lecon or {}) do
        l[cle] = valeur
    end
    local texte = Json.encode({ lecon = l, texte = 'Leçon de la photo · DSCF4961.RAF\n- Lumière — …',
        faits = { corrections = Json.tableau(), indices = Json.tableau() }, remarques = Json.tableau(remarques or {}) })
    return (texte:gsub('^{', '{\n  '))
end

-- Un appel de photo_lesson dans le fil (`entree`), puis sa réponse (`reponse` : texte ; nil, l'appel
-- reste en cours). Rend l'indice de l'élément lecon (nil sans carte) et celui de l'outil.
local function appelLecon(c, id, entree, reponse, erreur)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__photo_lesson',
        entree = entree } } })
    local outil, carte
    for i, e in ipairs(c.elements) do
        if e.appel == id then
            if e.genre == 'outil' then
                outil = i
            elseif e.genre == 'lecon' then
                carte = i
            end
        end
    end
    if reponse ~= nil then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id, textes = { reponse }, images = {}, erreur = erreur == true } } })
    end
    return carte, outil
end

-- Un texte de Claude dans le fil.
local function texteClaude(c, texte)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'texte', texte = texte } } })
end

-- Les lignes d'un élément dans le fil entier (Fil.lignes, à la largeur de la fenêtre).
local function lignesDe(c, element, cache)
    local siennes = {}
    for _, l in ipairs(Fil.lignes(c, LARGEUR, cache)) do
        if l.element == element then
            siennes[#siennes + 1] = l
        end
    end
    return siennes
end

-- Chaque ligne tient dans la largeur (son retrait compris), avec un genre et une icône que la
-- fenêtre connaît ; une ligne d'actions n'a pas de texte.
local function verifierLignes(lignes)
    local genres, icones = { actions = true }, {}
    for _, s in ipairs(Fenetre.STYLES) do
        for g in pairs(s.genres) do
            genres[g] = true
        end
    end
    for _, ic in ipairs(Fenetre.ICONES) do
        icones[ic.cle] = true
    end
    for _, l in ipairs(lignes) do
        vrai(genres[l.genre], 'genre inconnu de la fenêtre : ' .. tostring(l.genre))
        vrai(l.icone == nil or icones[l.icone], 'icône inconnue de la fenêtre : ' .. tostring(l.icone))
        vrai(Fil.occupe(l) <= LARGEUR_LIGNE, string.format('hors de la largeur (%.0f pour %d) : %s', Fil.occupe(l), LARGEUR_LIGNE, l.texte))
        vrai(l.genre ~= 'actions' or l.texte == '', 'une ligne d\'actions sans texte')
    end
end

-- Les balises d'une ligne : fermées sur la ligne même (une page de carte en commence une).
local function balisesFermees(ligne)
    local ouverte = false
    for fin in ligne:gmatch('<(/?)EM>') do
        vrai(ouverte == (fin == '/'), 'balise mal fermée : ' .. ligne)
        ouverte = fin == ''
    end
    vrai(not ouverte, 'balise ouverte en fin de ligne : ' .. ligne)
end

local function textes(lignes)
    local liste = {}
    for _, l in ipairs(lignes) do
        liste[#liste + 1] = l.genre .. '|' .. (l.icone or '') .. '|' .. l.texte
    end
    return table.concat(liste, '\n')
end

-- Une phrase de `n` caractères, faite de `motif` répété.
local function phrase(motif, n)
    local t = ''
    while Texte.longueur(t) < n do
        t = t .. motif
    end
    return Texte.debut(t, n)
end

-- Conversation ---------------------------------------------------------------------------------

essai("Conversation : leçon de l'entrée de l'outil à la réponse (ordre des axes, fait et fichier, refus, rangement, interruption)", function()
    local c = Conversation.nouvelle()
    local entree = entreeLecon()
    local carte, outil = appelLecon(c, 'l1', entree)
    vrai(carte, "une carte pour l'appel")
    egal(carte, outil + 1, "la carte suit la ligne de l'outil")
    local e = c.elements[carte]
    egal('lecon', e.genre)
    egal('enCours', e.etat)
    egal('photo_lesson', e.outil)
    egal(53636309, e.photo)
    egal(nil, e.fichier, 'le fichier vient de la réponse')
    -- Points remis dans l'ordre Lumière, Couleur, Composition ; l'axe inconnu et le doublon écartés.
    egal(3, #e.points)
    egal('light color composition', e.points[1].axe .. ' ' .. e.points[2].axe .. ' ' .. e.points[3].axe)
    egal('Lumière', e.points[1].nom)
    egal('Couleur', e.points[2].nom)
    egal('Composition', e.points[3].nom)
    -- Textes nettoyés : ni gras ni code Markdown, sur une ligne.
    egal('Ciel brûlé à 3 % : hautes lumières -40.', e.points[1].manque)
    egal('Compenser de −2/3 IL face au ciel clair.', e.points[1].prise_de_vue)
    egal(nil, e.points[3].manque, 'rien ne manquait')
    egal('blown_highlights', e.points[1].defauts[1])
    egal(0, #e.points[3].defauts)
    -- Des tables neuves, sans métatable (rien de l'entrée de Claude Code).
    vrai(getmetatable(e.points) == nil and getmetatable(e.points[1]) == nil and getmetatable(e.points[1].defauts) == nil, 'tables neuves')
    vrai(e.points[1].defauts ~= entree.points[2].defects, 'défauts copiés')
    -- La réponse : fait, le fichier, rangée ; les remarques des défauts mesurés restent pour Claude.
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'l1', images = {}, erreur = false,
        textes = { reponseLecon(nil, { "Mesuré : Exposition +1,10 IL ; la leçon ne nomme pas « sous-exposition » : à revoir." }) } } } })
    egal('fait', e.etat)
    egal('DSCF4961.RAF', e.fichier)
    egal(true, e.rangee)
    egal(false, e.remplacee)
    egal('2026-10', e.mois)
    egal(nil, e.remarque, 'pas une remarque de défaut')
    egal('fait', c.elements[outil].etat)
    contient(c.elements[outil].detail, '— Réponse —', "la réponse dans le détail de l'appel")
    -- Rangée à la place d'une autre ; photo active résolue par le connecteur (appel sans photo_id).
    local sans = entreeLecon()
    sans.photo_id = nil
    local carte2 = appelLecon(c, 'l2', sans, reponseLecon({ remplacee = true, photo = 4961, fichier = 'DSCF0001.RAF' }))
    egal(true, c.elements[carte2].remplacee)
    egal(4961, c.elements[carte2].photo)
    egal('DSCF0001.RAF', c.elements[carte2].fichier)
    -- Non rangée (module d'avant la 1.3) : faite, avec la remarque du connecteur.
    local remarque = "Leçon non rangée : le module de Lightroom chargé ne connaît pas encore la commande lecon (module d'avant la 1.3)."
    local carte3 = appelLecon(c, 'l3', entreeLecon(), reponseLecon({ rangee = false, mois = Json.null }, { "Mesuré : x.", remarque }))
    egal('fait', c.elements[carte3].etat)
    egal(false, c.elements[carte3].rangee)
    egal(remarque, c.elements[carte3].remarque)
    egal(nil, c.elements[carte3].mois)
    -- Refusée par le connecteur : en erreur, la raison sur une ligne.
    local carte4 = appelLecon(c, 'l4', entreeLecon(), "Le point « light » : at_capture vide.\nRien n'a été rangé.", true)
    egal('erreur', c.elements[carte4].etat)
    egal("Le point « light » : at_capture vide. Rien n'a été rangé.", c.elements[carte4].texte)
    -- Une réponse illisible : faite, le rangement inconnu.
    local carte5 = appelLecon(c, 'l5', entreeLecon(), 'pas du JSON')
    egal('fait', c.elements[carte5].etat)
    egal(nil, c.elements[carte5].rangee)
    -- Interrompue : en erreur ; finie sans réponse : faite (comme une notation).
    local carte6 = appelLecon(c, 'l6', entreeLecon())
    Conversation.appliquer(c, { genre = 'fin', interrompue = true, reussie = false, session = '' })
    egal('erreur', c.elements[carte6].etat, 'interrompue')
    local d = Conversation.nouvelle()
    local carte7 = appelLecon(d, 'l7', entreeLecon())
    Conversation.appliquer(d, { genre = 'fin', interrompue = false, reussie = true, session = '' })
    egal('fait', d.elements[carte7].etat, 'finie')
end)

essai("Conversation : read_facts seul, ou des points sans axe connu, ne font pas de carte", function()
    local c = Conversation.nouvelle()
    local carte, outil = appelLecon(c, 'f1', { photo_id = 53636309, read_facts = true }, '{"photo": {"id": 53636309}, "faits": {}, "rangee": false}')
    egal(nil, carte, 'read_facts seul')
    vrai(outil, "la ligne de l'outil reste")
    local avecFaits = entreeLecon()
    avecFaits.read_facts = true
    egal(nil, (appelLecon(c, 'f2', avecFaits)), 'read_facts avec des points : refusé par le connecteur, pas de carte')
    egal(nil, (appelLecon(c, 'f3', { points = { { axis = 'mood', at_capture = 'x' } } })), 'aucun axe connu')
    egal(nil, (appelLecon(c, 'f4', {})), 'ni points ni read_facts')
    for _, e in ipairs(c.elements) do
        vrai(e.genre ~= 'lecon', 'aucune carte')
    end
    -- Conversation.leconDemandee tient une entrée vide ou fausse.
    egal(0, #Conversation.leconDemandee(nil))
    egal(0, #Conversation.leconDemandee({ points = 'trois' }))
    egal(0, #Conversation.leconDemandee({ points = { 'a', { axis = 3 } } }))
end)

essai("Conversation : outilDeLAppel trouve la ligne de l'appel d'une carte, jamais sans appel", function()
    local c = Conversation.nouvelle()
    local carte, outil = appelLecon(c, 'o1', entreeLecon())
    egal(c.elements[outil], Conversation.outilDeLAppel(c, c.elements[carte].appel))
    egal(nil, Conversation.outilDeLAppel(c, nil))
    egal(nil, Conversation.outilDeLAppel(c, 'autre'))
    c.elements[#c.elements + 1] = { genre = 'outil', texte = 'sans appel' }
    egal(nil, Conversation.outilDeLAppel(c, nil), "un outil sans appel n'est celui d'aucune carte")
end)

essai('Conversation : la recherche trouve les mots d\'une leçon (sans accents ni majuscules)', function()
    local c = Conversation.nouvelle()
    c.titre = 'Flamant'
    appelLecon(c, 'r1', entreeLecon(), reponseLecon())
    vrai(Conversation.correspond(c, 'compenser ciel'), 'prise de vue et manque')
    vrai(Conversation.correspond(c, 'DOMINANTE bleue'), 'axe Couleur')
    vrai(Conversation.correspond(c, 'regard tiers'), 'axe Composition')
    vrai(Conversation.correspond(c, 'COULEUR composition'), "le nom des axes (absent des textes)")
    vrai(not Conversation.correspond(c, 'neige'), 'un mot absent')
    -- Sans carte, la même entrée ne se trouve pas (le détail de l'appel n'est pas cherché).
    local d = Conversation.nouvelle()
    appelLecon(d, 'r2', { photo_id = 1, read_facts = true })
    vrai(not Conversation.correspond(d, 'compenser'), 'rien à trouver')
end)

-- Fil -------------------------------------------------------------------------------------------

essai("Fil : la leçon n'a plus de carte dans le fil : ● pendant l'appel, puis « Leçon de la photo » sur la ligne d'actions qui finit le tour ; genres connus", function()
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, 'Retouche, puis la leçon')
    local carte = appelLecon(c, 'l1', entreeLecon())
    -- Pendant l'appel : une ligne ● (en cours), le titre sans fichier ; pas encore d'actions.
    local lignes = lignesDe(c, carte)
    verifierLignes(lignes)
    egal("note|cours|Leçon de la photo · en préparation…", textes(lignes))
    for _, l in ipairs(Fil.lignes(c, LARGEUR)) do
        vrai(l.genre ~= 'actions', "pas d'actions pendant l'appel")
    end
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'l1', images = {}, erreur = false, textes = { reponseLecon() } } } })
    egal(0, #Fil.lignesElement(c.elements[carte], carte, LARGEUR_LIGNE), 'faite : pas de ligne à elle')
    texteClaude(c, 'Le résumé, après la leçon.')
    lignes = lignesDe(c, carte)
    verifierLignes(lignes)
    -- Faite : la ligne d'actions, sans texte ni axe (la leçon est dans l'onglet Leçon), à la fin du
    -- tour de Claude, après son texte (maquette).
    egal(1, #lignes)
    egal('actions', lignes[1].genre)
    egal('lecon', lignes[1].actions)
    egal(carte, lignes[1].lecon, "l'élément de la leçon")
    egal('', lignes[1].texte)
    local fil = Fil.lignes(c, LARGEUR)
    egal('actions', fil[#fil].genre, 'la dernière ligne du tour')
    egal('Le résumé, après la leçon.', fil[#fil - 1].texte)
    for _, l in ipairs(fil) do
        vrai(not l.texte:find('Ce qui manquait', 1, true), 'aucun axe dans le fil : ' .. l.texte)
    end
    -- Une demande suivante : les actions restent à la fin du tour d'avant.
    Conversation.ajouterDemande(c, 'Merci')
    fil = Fil.lignes(c, LARGEUR)
    egal('dany', fil[#fil - 1].genre)
    egal('vide', fil[#fil - 2].genre)
    egal('actions', fil[#fil - 3].genre)
end)

essai("Fil.texteLecon : le texte de l'onglet (axes en gras balisés, deux moitiés entières, Rien ne manquait, À refaire), sans Markdown ni balise de Claude", function()
    local c = Conversation.nouvelle()
    local carte = appelLecon(c, 'l1', entreeLecon(), reponseLecon())
    local e = c.elements[carte]
    egal('Leçon de la photo · DSCF4961.RAF', Fil.titreLecon(e))
    egal(table.concat({
        "<EM>Lumière</EM>",
        "Ce qui manquait : Ciel brûlé à 3 % : hautes lumières -40.",
        "À la prise de vue : Compenser de −2/3 IL face au ciel clair.",
        "",
        "<EM>Couleur</EM>",
        "Ce qui manquait : Dominante bleue à l'ombre : +400 K.",
        "À la prise de vue : Balance des blancs Ombre plutôt qu'Auto.",
        "",
        "<EM>Composition</EM>",
        "Rien ne manquait.",
        "À refaire : Le flamant au tiers gauche, regard vers le cadre : à refaire.",
    }, '\n'), Fil.texteLecon(e))
    -- Le texte de Claude reste une phrase (ni puce ni Markdown du fil), sans balise à lui.
    e.points[2].manque = '- Dominante <EM>bleue'
    e.points[3].prise_de_vue = '1. Le flamant'
    local texte = Fil.texteLecon(e)
    contient(texte, 'Ce qui manquait : - Dominante bleue')
    contient(texte, 'À refaire : 1. Le flamant')
    vrai(not texte:find('•', 1, true), 'pas de puce')
    local _, balises = texte:gsub('<EM>', '')
    egal(3, balises, 'seulement les trois axes balisés')
end)

essai("Onglet Leçon : des moitiés de 140 caractères entières, sur une page de la carte ; chaque ligne dans la carte, ses balises fermées", function()
    local c = Conversation.nouvelle()
    local longue = phrase("Le ciel brûlé à 3 % au départ ; hautes lumières baissées de 40 et blancs de 20. ", 140)
    local entree = { photo_id = 53636309, points = {} }
    for _, axe in ipairs({ 'light', 'color', 'composition' }) do
        entree.points[#entree.points + 1] = { axis = axe, missing = longue, at_capture = longue }
    end
    local carte = appelLecon(c, 'l1', entree, reponseLecon())
    local texte = Fil.texteLecon(c.elements[carte])
    vrai(not texte:find('…', 1, true), 'la leçon entière, sans « … »')
    -- Coupée comme la carte la montre (12 points, axes en gras 12) : chaque ligne tient dans le texte
    -- de la carte, ses balises fermées sur la ligne.
    local lignes = Fenetre.lignesCarte(texte, D.largeurLecon, Fenetre.CARTES.lecon.police, Fenetre.CARTES.lecon.emphase)
    -- La carte de la fenêtre agrandie (D.leconLignes) tient une leçon aux moitiés les plus longues
    -- (Lecon.longueurPoint, 140 caractères) sur une seule page ; ▲ ▼ restent pour un texte plus
    -- long (la remarque d'une leçon non rangée), éprouvés dans la fenêtre plus bas.
    vrai(#lignes <= D.leconLignes, 'sur une page : ' .. #lignes .. ' lignes pour ' .. D.leconLignes)
    for _, l in ipairs(lignes) do
        balisesFermees(l)
        vrai(Fil.largeur(l, 'texte12', 'gras12') <= D.largeurLecon - Fil.MARGE, 'dans la carte : ' .. l)
    end
    -- Des caractères larges (140 « W ») : coupés au caractère, dans la carte aussi.
    for _, p in ipairs(c.elements[carte].points) do
        p.manque, p.prise_de_vue = phrase('W', 140), phrase('W', 140)
    end
    for _, l in ipairs(Fenetre.lignesCarte(Fil.texteLecon(c.elements[carte]), D.largeurLecon, 'texte12', 'gras12')) do
        balisesFermees(l)
        vrai(Fil.largeur(l, 'texte12', 'gras12') <= D.largeurLecon - Fil.MARGE, 'dans la carte : ' .. l)
    end
    -- Un axe au nom trop long pour une ligne : coupé, chaque morceau rebalisé.
    c.elements[carte].points[1].nom = phrase('Lumière ', 120)
    local coupees = Fenetre.lignesCarte(Fil.texteLecon(c.elements[carte]), D.largeurLecon, 'texte12', 'gras12')
    egal('<EM>', coupees[1]:sub(1, 4), 'le nom en gras')
    egal('<EM>', coupees[2]:sub(1, 4), 'sa suite rouverte en gras')
    for _, l in ipairs(coupees) do
        balisesFermees(l)
    end
end)

essai("Fil : leçon refusée ou interrompue (✕, bornée) ; non rangée ou gardée pour la session : la ligne d'actions, la remarque dans l'onglet", function()
    local c = Conversation.nouvelle()
    local refusee = appelLecon(c, 'l1', entreeLecon(), "Le point « light » : at_capture vide. Rien n'a été rangé.", true)
    local lignes = lignesDe(c, refusee)
    egal("note|erreur|Leçon non rangée : Le point « light » : at_capture vide. Rien n'a été rangé.", textes(lignes))
    egal("Leçon non rangée : Le point « light » : at_capture vide. Rien n'a été rangé.", Fil.texteLecon(c.elements[refusee]))
    -- Interrompue (ou relue en cours) : sans raison donnée.
    c.elements[refusee].texte = ''
    egal("note|erreur|Leçon non rangée : l'appel n'a pas abouti.", textes(lignesDe(c, refusee)))
    -- Un refus très long : trois lignes au plus, la dernière finie par « … ».
    c.elements[refusee].texte = phrase("photo_lesson : donner les trois points de la leçon, un par axe. ", 900)
    lignes = lignesDe(c, refusee)
    egal(Fil.LIGNES_ERREUR_LECON, #lignes)
    vrai(lignes[#lignes].texte:sub(-#'…') == '…', lignes[#lignes].texte)
    verifierLignes(lignes)
    -- Faite mais non rangée : la ligne d'actions dans le fil ; la remarque à la fin du texte.
    local remarque = "Leçon non rangée : le module de Lightroom chargé ne connaît pas encore la commande lecon (module d'avant la 1.3). "
        .. "Quitter puis relancer Lightroom après l'installation ; la leçon de cette réponse reste valable."
    local nonRangee = appelLecon(c, 'l2', entreeLecon(), reponseLecon({ rangee = false }, { remarque }))
    egal(0, #Fil.lignesElement(c.elements[nonRangee], nonRangee, LARGEUR_LIGNE), 'faite : pas de ligne à elle')
    local texte = Fil.texteLecon(c.elements[nonRangee])
    vrai(texte:sub(-#remarque) == remarque, 'la remarque en dernier : ' .. texte)
    -- Rangée pour la session seulement (carnet.json non écrit).
    local gardee = appelLecon(c, 'l3', entreeLecon(), reponseLecon(nil, { "Leçon gardée pour cette session, carnet.json non écrit : disque plein" }))
    contient(Fil.texteLecon(c.elements[gardee]), 'carnet.json non écrit')
    -- Photo d'essai (1.3.1) : le refus voulu du module (Carnet.lua, garder) est dit tel quel, jamais
    -- le texte générique d'une leçon non rangée.
    local essai = "Leçon non rangée : photo d'essai (Développeur › Essais) ; le carnet de progrès ne compte que les vraies "
        .. "prises de vue. La leçon de cette réponse reste valable."
    local dEssai = appelLecon(c, 'l6', entreeLecon(), reponseLecon({ rangee = false, motif = 'essai' }, { "Mesuré : x.", essai }))
    egal(essai, c.elements[dEssai].remarque)
    local texteEssai = Fil.texteLecon(c.elements[dEssai])
    vrai(texteEssai:sub(-#essai) == essai, 'le refus de la photo d\'essai en dernier : ' .. texteEssai)
    vrai(not texteEssai:find('dans le carnet de progrès%.'), 'pas le texte générique : ' .. texteEssai)
    -- Non rangée sans remarque du connecteur : le texte le dit quand même ; rangée sans remarque,
    -- rien après la composition.
    local muette = appelLecon(c, 'l4', entreeLecon(), reponseLecon({ rangee = false }, { "Mesuré : x." }))
    contient(Fil.texteLecon(c.elements[muette]), "\n\nLeçon non rangée dans le carnet de progrès.")
    local rangee = appelLecon(c, 'l5', entreeLecon(), reponseLecon(nil, { "Mesuré : x." }))
    vrai(Fil.texteLecon(c.elements[rangee]):sub(-#'à refaire.') == 'à refaire.', 'rien après la composition')
end)

essai('Fil : le cache suit la leçon (en cours, faite, refusée) et garde les lignes sinon', function()
    local c = Conversation.nouvelle()
    local carte = appelLecon(c, 'l1', entreeLecon())
    local cache = {}
    egal('note', lignesDe(c, carte, cache)[1].genre, 'en cours')
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'l1', images = {}, erreur = false, textes = { reponseLecon() } } } })
    local avant = lignesDe(c, carte, cache)
    local e = c.elements[carte]
    egal('actions', avant[1].genre, 'faite : la ligne d\'actions du tour')
    vrai(cache[e.id] and #cache[e.id].lignes == 0, 'gardée : aucune ligne à elle')
    local garde = cache[e.id].lignes
    lignesDe(c, carte, cache)
    egal(garde, cache[e.id].lignes, 'rien de changé : les mêmes lignes gardées')
    e.etat, e.texte = 'erreur', 'refusée'
    egal('Leçon non rangée : refusée', lignesDe(c, carte, cache)[1].texte, 'état')
end)

-- Stockage --------------------------------------------------------------------------------------

essai('Stockage : leçon relue, points et défauts en tableaux (même vides), leçon restée en cours relue en erreur', function()
    local c = Conversation.nouvelle()
    local faite = appelLecon(c, 'l1', entreeLecon(), reponseLecon())
    local enCours = appelLecon(c, 'l2', entreeLecon())
    -- Une carte sans point (conversation abîmée) : la liste reste un tableau.
    c.elements[#c.elements + 1] = { id = 'vide', genre = 'lecon', etat = 'fait', texte = '', images = {}, changements = {}, points = {} }
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    contient(texte, '"defauts":[]', 'défauts vides en tableau')
    contient(texte, '"points":[]', 'points vides en tableau')
    contient(texte, '"defauts":["blown_highlights"]')
    local lue = Stockage.lire(c.id)
    local e = lue.elements[faite]
    egal('lecon', e.genre)
    egal('fait', e.etat)
    egal('DSCF4961.RAF', e.fichier)
    egal(true, e.rangee)
    egal(3, #e.points)
    egal('Couleur', e.points[2].nom)
    egal(nil, e.points[3].manque)
    egal('erreur', lue.elements[enCours].etat, 'restée en cours : relue en erreur')
    egal(0, #lue.elements[#lue.elements].points)
    -- Une leçon écrite sans points relue avec une liste vide.
    local brut = Json.decode(texte)
    brut.elements[faite].points = nil
    Fichiers.ecrire(Stockage.fichier(c.id), Json.encode(brut))
    egal(0, #Stockage.lire(c.id).elements[faite].points)
    -- Un fichier abîmé (points en texte, points qui ne sont pas des tables, défauts en texte) : relu
    -- sans bloquer le fil ni l'enregistrement suivant.
    brut.elements[faite].points = 'abîmé'
    brut.elements[enCours].points = { 3, 'x', { axe = 'color', nom = 'Couleur', manque = 'Dominante.', prise_de_vue = 'Ombre.', defauts = 'color_cast' } }
    Fichiers.ecrire(Stockage.fichier(c.id), Json.encode(brut))
    local abimee = Stockage.lire(c.id)
    egal(0, #abimee.elements[faite].points, 'points en texte : aucun')
    egal(1, #abimee.elements[enCours].points, 'seulement les points en table')
    egal(0, #abimee.elements[enCours].points[1].defauts, 'défauts en texte : aucun')
    egal(0, #Fil.lignesElement(abimee.elements[faite], faite, LARGEUR_LIGNE), 'faite : pas de ligne à elle')
    egal('', Fil.texteLecon(abimee.elements[faite]), 'points en texte : aucun axe dans l\'onglet')
    egal("note|erreur|Leçon non rangée : l'appel n'a pas abouti.", textes(lignesDe(abimee, enCours)))
    Stockage.enregistrer(abimee)
    contient(Fichiers.lire(Stockage.fichier(c.id)), '"defauts":[]', 'réenregistrée')
    -- Le fil de la conversation relue est celui d'avant.
    egal(textes(lignesDe(c, faite)), textes(lignesDe(lue, faite)))
    egal("note|erreur|Leçon non rangée : l'appel n'a pas abouti.", textes(lignesDe(lue, enCours)))
    Stockage.supprimer(c.id)
end)

-- Fenêtre ---------------------------------------------------------------------------------------

-- Le bouton montré de ce titre sur la ligne i de la grille du fil (`x..i`, la rangée d'actions).
local function boutonDeLigne(contenu, titre, i)
    for _, v in ipairs(vues(contenu)) do
        if S.BOUTONS[v.genre] and v.args.title == titre and type(v.args.visible) == 'table'
            and table.concat(S.cles(v.args.visible), ' ') == 'x' .. i and S.montreeDansFenetre(v) then
            return v
        end
    end
    error('bouton « ' .. titre .. ' » introuvable sur la ligne ' .. i, 2)
end

-- La vue simple liée à cette clé (titre, valeur, ou `enabled` d'un bouton).
local function liee(contenu, genre, cle)
    for _, v in ipairs(vues(contenu)) do
        local lien = v.args.title or v.args.value
        if S.BOUTONS[v.genre] then
            lien = v.args.enabled
        end
        if v.genre == genre and type(lien) == 'table' and lien.liaison and lien.key == cle then
            return v
        end
    end
    error(genre .. ' lié à ' .. cle .. ' introuvable', 2)
end

-- La ligne de la grille qui montre cette ligne du fil (test), et la ligne elle-même.
local function ligneMontree(test)
    for i = 1, Fenetre.T.lignes do
        local l = Fenetre.lignes[Fenetre.premiere + i - 1]
        if l and test(l) then
            return i, l
        end
    end
    error('ligne introuvable dans la grille', 2)
end

essai("Fenêtre : « Leçon de la photo » ouvre l'onglet Leçon sur sa leçon (vrai clic, sans envoyer la demande) ; carte, axes en gras, ▲ ▼, Détail… ; remise quand la conversation change", function()
    photoActive(53636309, 'DSCF4961.RAF')
    -- Les conversations chargées d'abord : la fenêtre ne remplace pas celle-ci en s'ouvrant.
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    -- Une première leçon de la photo active, aux moitiés longues (plus d'une page), puis une autre
    -- (la dernière : celle que l'onglet montre sans choix).
    local longue = phrase("Le ciel brûlé à 3 % au départ ; hautes lumières baissées de 40 et blancs de 20. ", 140)
    local entree = entreeLecon()
    for _, x in ipairs(entree.points) do
        x.missing, x.at_capture = x.missing and longue or nil, longue
    end
    local premiere, outil = appelLecon(c, 'l1', entree, reponseLecon())
    Conversation.ajouterDemande(c, 'Et la leçon de la photo ?')
    local seconde = appelLecon(c, 'l2', entreeLecon(), reponseLecon({ remplacee = true }))
    ouvrirFenetre(function(p, args)
        egal(c, Moteur.courante, 'la conversation des leçons')
        Fenetre.rafraichir()
        egal('notation', p.onglet, "des leçons déjà là ne font pas basculer à l'ouverture")
        -- Sans choix : la dernière leçon de la photo active.
        egal(c.elements[seconde].id, (Fenetre.leconMontree()).id)
        contient(p.leconTexte, '<EM>Lumière</EM>')
        -- La carte (sur son image), le texte en 12, les axes en gras 12 (emphase de même taille).
        local texte = liee(args.contents, 'static_text', 'leconTexte')
        egal(Fenetre.POLICES.texte12, texte.args.font)
        egal(Fenetre.POLICES.gras12, texte.args.emphasis_font)
        vrai(texte.args.emphasis_color, "la couleur d'emphase avec la police (D4)")
        egal(D.leconLignes, texte.args.height_in_lines)
        egal(D.largeurLecon, texte.args.width)
        -- La première leçon tient sur une page de la carte (D.leconLignes) : pour éprouver ▲ ▼, la
        -- carte n'en montre ici que la moitié, le temps de l'essai (Fenetre.T.leconLignes, que
        -- Fenetre.montrerPage lit ; Fenetre.T est refait à chaque ouverture).
        local attendues = Fenetre.lignesCarte(Fil.texteLecon(c.elements[premiere]), D.largeurLecon, 'texte12', 'gras12')
        vrai(#attendues <= D.leconLignes, 'la leçon sur une page de la carte : ' .. #attendues .. ' lignes')
        local page = math.floor(#attendues / 2)
        Fenetre.T.leconLignes = page
        local image
        for _, v in ipairs(vues(args.contents)) do
            if v.genre == 'picture' and type(v.args.value) == 'string' and v.args.value:match('/carte%-lecon%.png$') then
                image = v
            end
        end
        vrai(image, 'la carte en image')
        vrai(not S.montreeDansFenetre(image), 'cachée sous Note')
        -- « Leçon de la photo » de la première leçon, après une frappe sans Retour.
        local i = ligneMontree(function(l) return l.genre == 'actions' and l.lecon == premiere end)
        egal('lecon', p['x' .. i])
        local champ = liee(args.contents, 'edit_field', 'saisie')
        S.taper(champ, 'Texte validé par le clic')
        S.cliquer(boutonDeLigne(args.contents, 'Leçon de la photo', i))
        egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande")
        p.saisie = ''
        egal('lecon', p.onglet, "l'onglet Leçon")
        vrai(S.montreeDansFenetre(image) and S.montreeDansFenetre(texte), 'la carte montrée')
        egal(c.elements[premiere].id, Fenetre.leconChoisie)
        egal('Leçon de la photo · DSCF4961.RAF', p.leconTitre)
        egal(1, (p.leconTexte:find('<EM>Lumière</EM>\nCe qui manquait : Le ciel brûlé', 1, true)), p.leconTexte)
        -- Coupée dans la police de la carte (12 points, les axes en gras 12), comme elle s'affiche.
        egal(table.concat(attendues, '\n', 1, page), p.leconTexte, 'la première page, en 12 points')
        -- Page par page : ▼ puis ▲ (Fenetre.defilerTexte), la page suivante aux balises fermées.
        egal(false, p.leconMonte)
        egal(true, p.leconDescend, "plus d'une page")
        local premierePage = p.leconTexte
        S.cliquer(liee(args.contents, 'push_button', 'leconDescend'))
        vrai(p.leconTexte ~= premierePage and p.leconMonte, 'page suivante')
        for ligne in (p.leconTexte .. '\n'):gmatch('([^\n]*)\n') do
            balisesFermees(ligne)
        end
        S.cliquer(liee(args.contents, 'push_button', 'leconMonte'))
        egal(premierePage, p.leconTexte, 'retour à la première page')
        Fenetre.T.leconLignes = D.leconLignes
        -- Détail… : l'appel de photo_lesson et sa réponse, dans une tâche.
        egal(true, p.leconADetail)
        local taches, dialogues = #S.taches, #S.dialogues
        S.cliquer(liee(args.contents, 'square_button', 'leconADetail'))
        egal(taches + 1, #S.taches, 'le détail dans une tâche')
        lancerTaches(taches)
        egal(dialogues + 1, #S.dialogues)
        egal('Claude · ' .. c.elements[outil].texte, S.dialogues[#S.dialogues].title)
        -- Une autre conversation : plus de leçon choisie, l'aide, rien à détailler.
        Fenetre.nouvelle()
        Fenetre.rafraichir()
        egal(nil, Fenetre.leconChoisie, 'remise à nil')
        egal(Fenetre.AUCUNE_LECON, (p.leconTexte:gsub('\n', ' ')))
        egal('Leçon de la photo', p.leconTitre)
        egal(false, p.leconADetail)
        p.onglet = 'notation'
    end)
end)

essai("Fenêtre : une leçon qui arrive bascule une fois vers Leçon ; jamais avec une proposition en attente ni un exercice en cours (seulement vue)", function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('notation', p.onglet)
        -- Une leçon en cours ne fait pas basculer ; faite, une fois.
        local l1 = appelLecon(c, 'l1', entreeLecon())
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'en cours : pas encore')
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'l1', images = {}, erreur = false, textes = { reponseLecon() } } } })
        Fenetre.rafraichir()
        egal('lecon', p.onglet, 'la leçon arrivée')
        egal(c.elements[l1].id, Fenetre.leconVue)
        p.onglet = 'notation'
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'une seule fois')
        -- Une proposition en attente : la leçon qui arrive est vue, sans bascule (Accepter reste
        -- devant) ; la proposition décidée, toujours pas.
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'p1', nom = 'mcp__developpeur__preview_settings',
            entree = { photo_id = 53636309, settings = { Exposure2012 = 0.3 }, reason = 'Plus clair' } } } })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la proposition arrivée')
        local l2 = appelLecon(c, 'l2', entreeLecon(), reponseLecon())
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'pas de bascule : une proposition attend')
        egal(c.elements[l2].id, Fenetre.leconVue, 'vue')
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'déjà vue : rien de plus')
        -- Un exercice « Je le fais » à faire : pas de bascule non plus.
        c.elements[#c.elements + 1] = { id = 'exo', genre = 'exercice', etat = 'aFaire', photo = 53636309, texte = '', images = {},
            changements = {}, aFaire = { { n = 1, cle = 'Exposure2012', texte = 'Exposition : 0 → +0,3' } }, ecarts = {} }
        Fenetre.rafraichir()
        p.onglet = 'notation'
        local l3 = appelLecon(c, 'l3', entreeLecon(), reponseLecon())
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'pas de bascule : un exercice en cours')
        egal(c.elements[l3].id, Fenetre.leconVue, 'vue')
    end)
end)

-- Une proposition dépassée par Claude (1.3.2) -----------------------------------------------------

-- La réponse du connecteur à une proposition (preview_settings) : sa photo et ses changements.
local function reponseProposition(photo, fichier, changements)
    return Json.encode({ mode = 'proposer', photo = { id = photo, fichier = fichier }, etape = 'proposition', changements = changements })
end

-- La réponse du connecteur à une écriture (apply_settings…) : une étape par photo, avec son id.
local function reponseEcriture(nom, photo, fichier, changements, id)
    return Json.encode({ mode = 'appliquer', resultats = { { photo = { id = photo, fichier = fichier }, etape = 'Claude · ' .. nom,
        etape_id = id or 7001, changements = changements } } })
end

-- Un appel d'outil dans le fil, puis sa réponse (nil : en cours) ; rend l'indice de son élément.
local function appelOutil(c, id, nom, entree, reponse, erreur)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__' .. nom, entree = entree } } })
    local indice = #c.elements
    for i, e in ipairs(c.elements) do
        if e.genre == 'outil' and e.appel == id then
            indice = i
        end
    end
    if reponse ~= nil then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id, textes = { reponse }, images = {}, erreur = erreur == true } } })
    end
    return indice
end

-- La dernière proposition du fil.
local function derniereProposition(c)
    for i = #c.elements, 1, -1 do
        if c.elements[i].genre == 'proposition' then
            return c.elements[i]
        end
    end
    return nil
end

local EXPOSITION = { { cle = 'Exposure2012', libelle = 'Exposition', avant = 0, apres = 0.3 } }

essai("Proposition dépassée (constaté le 22 octobre 2026) : préparée à l'ouverture, puis les mêmes réglages appliqués par Claude ; la carte le dit, Accepter, Refuser et Ajuster… grisés, la leçon s'ouvre", function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('notation', p.onglet)
        -- La proposition préparée à l'ouverture (sans photo_id : la photo active), qui attend.
        Fenetre.propositionAuto = true
        appelOutil(c, 'p1', 'preview_settings', { settings = { Exposure2012 = 0.3 }, reason = 'Plus lumineuse' },
            reponseProposition(53636309, 'DSCF4961.RAF', EXPOSITION))
        local prop = derniereProposition(c)
        egal(53636309, prop.photo, 'sa photo lue dans la réponse')
        Fenetre.rafraichir()
        egal('notation', p.onglet, "préparée à l'ouverture : pas de bascule")
        egal(true, p.enAttente)
        -- « Applique ta proposition, puis termine par la leçon de la photo. »
        Conversation.ajouterDemande(c, 'Applique ta proposition, puis termine par la leçon de la photo.')
        Fenetre.propositionAuto = false
        appelOutil(c, 'a1', 'apply_settings', { settings = { Exposure2012 = 0.3 }, step_name = 'passe 1 : lumière et couleur',
            reason = 'Plus lumineuse' })
        egal('enAttente', prop.etat, "l'étape pas encore écrite : la proposition attend")
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'a1', images = {}, erreur = false,
            textes = { reponseEcriture('passe 1 : lumière et couleur', 53636309, 'DSCF4961.RAF', EXPOSITION) } } } })
        egal('appliquee', prop.etat, 'les mêmes réglages : appliquée par Claude')
        egal('passe 1 : lumière et couleur', prop.etapeClaude)
        egal(nil, Conversation.propositionEnAttente(c), "plus rien n'attend")
        egal(prop, Conversation.propositionClose(c))
        Fenetre.rafraichir()
        egal(false, p.enAttente, 'Accepter, Refuser et Ajuster… grisés')
        local phrase = "Appliquée par Claude (étape « passe 1 : lumière et couleur ») : elle n'attend plus votre accord."
        egal(phrase, Fenetre.phraseClose(prop))
        local carte = p.propositionTexte:gsub('\n', ' ')
        contient(carte, phrase, 'la carte le dit')
        contient(carte, 'Exposition : 0 → 0,3', 'puis ce qui était proposé')
        egal(phrase, (Fenetre.texteProposition(prop):match('^[^\n]*')), 'en tête')
        -- Un clic sur Accepter (le calque ne vérifie pas enabled) ne réapplique rien.
        egal(false, Moteur.repondre(true), 'Accepter : rien à accepter')
        egal('appliquee', prop.etat)
        -- La leçon qui arrive ouvre l'onglet Leçon : plus de proposition qui attend.
        appelLecon(c, 'l1', entreeLecon(), reponseLecon())
        Fenetre.rafraichir()
        egal('lecon', p.onglet, 'la leçon arrivée, la fenêtre bascule')
        -- Le fil le dit aussi.
        local texte = ''
        for _, l in ipairs(Fil.lignes(c, LARGEUR)) do
            if c.elements[l.element] == prop then
                texte = texte .. l.texte .. '\n'
            end
        end
        contient(texte, 'Proposition appliquée par Claude', 'la ligne du fil')
    end)
end)

essai("Proposition dépassée : d'autres réglages la disent remplacée ; une autre photo, un classement, un aperçu, une erreur ou une décision de Dany la laissent", function()
    local c = Conversation.nouvelle(1000)
    -- D'autres réglages sur sa photo (photo_id dans l'entrée) : remplacée.
    appelOutil(c, 'p1', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local p1 = derniereProposition(c)
    egal(4961, p1.photo)
    -- Une étape sur une autre photo : rien.
    appelOutil(c, 'a0', 'apply_settings', { photo_id = 4962, settings = { Exposure2012 = 0.3 }, step_name = 'autre' },
        reponseEcriture('autre', 4962, 'DSCF4962.RAF', EXPOSITION, 7000))
    egal('enAttente', p1.etat, 'une autre photo')
    -- Un classement sur sa photo (ne change pas l'image) : rien.
    appelOutil(c, 'm1', 'set_metadata', { photo_ids = { 4961 }, add_keywords = { 'Lac' }, step_name = 'mots-clés' },
        reponseEcriture('mots-clés', 4961, 'DSCF4961.RAF', { { cle = 'motsCles', avant = '', apres = 'Lac' } }, 7002))
    egal('enAttente', p1.etat, 'un classement')
    -- Un masque en proposition seulement (preview) : rien d'écrit.
    appelOutil(c, 'k1', 'add_mask', { photo_ids = { 4961 }, preview = true, masks = {} },
        reponseProposition(4961, 'DSCF4961.RAF', {}))
    egal('enAttente', p1.etat, 'un aperçu')
    -- Une écriture refusée : rien.
    appelOutil(c, 'a1', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.5 } }, 'Proposer d\'abord : confirm = true.', true)
    egal('enAttente', p1.etat, 'une erreur')
    -- D'autres réglages : remplacée par une retouche de Claude.
    appelOutil(c, 'a2', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.5 }, step_name = 'passe 1 : lumière' },
        reponseEcriture('passe 1 : lumière', 4961, 'DSCF4961.RAF', { { cle = 'Exposure2012', avant = 0, apres = 0.5 } }, 7003))
    egal('remplacee', p1.etat)
    egal('passe 1 : lumière', p1.etapeClaude)
    egal("Remplacée par une retouche de Claude (étape « passe 1 : lumière ») : elle n'attend plus votre accord.", Fenetre.phraseClose(p1))
    -- Une partie seulement des réglages proposés : remplacée aussi.
    appelOutil(c, 'p2', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3, Vibrance = 10 } },
        reponseProposition(4961, 'DSCF4961.RAF', { EXPOSITION[1], { cle = 'Vibrance', avant = 0, apres = 10 } }))
    local p2 = derniereProposition(c)
    appelOutil(c, 'a3', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 }, step_name = 'lumière' },
        reponseEcriture('lumière', 4961, 'DSCF4961.RAF', EXPOSITION, 7004))
    egal('remplacee', p2.etat, 'la vibrance manque')
    -- Une proposition décidée par Dany garde son état ; la suivante, sans réglage lu, est remplacée.
    appelOutil(c, 'p3', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local p3 = derniereProposition(c)
    Conversation.decider(c, p3.id, true)
    appelOutil(c, 'p4', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } }, '{ "texte": "sans réglages lus" }')
    local p4 = derniereProposition(c)
    appelOutil(c, 'a4', 'copy_settings', { from_photo_id = 4961, photo_ids = { 4961 }, step_name = 'copie' },
        reponseEcriture('copie', 4961, 'DSCF4961.RAF', EXPOSITION, 7005))
    egal('acceptee', p3.etat, 'acceptée par Dany : son chemin')
    egal('remplacee', p4.etat, 'aucun réglage lu : rien ne dit les mêmes')
    -- La carte : la dernière proposition, si Claude l'a close ; nil après une décision de Dany.
    egal(p4, Conversation.propositionClose(c))
    appelOutil(c, 'p5', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    Conversation.decider(c, derniereProposition(c).id, false)
    egal(nil, Conversation.propositionClose(c), 'refusée par Dany')
    egal(nil, Fenetre.phraseClose(derniereProposition(c)))
    -- Relue du disque, une proposition close le reste.
    local relue = Json.decode(Json.encode(p1))
    egal('remplacee', relue.etat)
    egal(Fenetre.phraseClose(p1), Fenetre.phraseClose(relue))
end)

essai("Proposition dépassée : une proposition sans photo connue (d'avant le correctif) attend encore après une étape, sur quelque photo que ce soit", function()
    local c = Conversation.nouvelle(1000)
    -- Une proposition enregistrée avant le correctif 1.3.2 : sans champ photo.
    appelOutil(c, 'p0', 'preview_settings', { settings = { Exposure2012 = 0.3 } }, reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local ancienne = derniereProposition(c)
    ancienne.photo = nil
    ancienne = Json.decode(Json.encode(ancienne))
    c.elements[#c.elements] = ancienne
    egal(nil, ancienne.photo)
    -- Claude retouche une autre photo : la proposition (sur la photo active d'alors) attend encore.
    appelOutil(c, 'a0', 'apply_settings', { photo_id = 4962, settings = { Exposure2012 = 0.5 }, step_name = 'autre photo' },
        reponseEcriture('autre photo', 4962, 'DSCF4962.RAF', { { cle = 'Exposure2012', avant = 0, apres = 0.5 } }, 7100))
    egal('enAttente', ancienne.etat, 'une étape sur une autre photo ne la clôt pas')
    egal(nil, ancienne.etapeClaude)
    egal(ancienne, Conversation.propositionEnAttente(c), 'Accepter reste offert')
    -- Même les mêmes réglages sur une photo : sa photo n'est pas connue, elle attend.
    appelOutil(c, 'a1', 'apply_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 }, step_name = 'mêmes réglages' },
        reponseEcriture('mêmes réglages', 4961, 'DSCF4961.RAF', EXPOSITION, 7101))
    egal('enAttente', ancienne.etat, 'photo inconnue : comme avant le correctif')
    -- Une réponse qui ne dit pas la photo de la proposition (sans photo_id dans l'entrée) : de même.
    appelOutil(c, 'p1', 'preview_settings', { settings = { Exposure2012 = 0.3 } }, '{ "texte": "sans photo dite" }')
    local sansPhoto = derniereProposition(c)
    egal(nil, sansPhoto.photo)
    appelOutil(c, 'a2', 'apply_settings', { photo_id = 4963, settings = { Exposure2012 = 0.3 }, step_name = 'troisième' },
        reponseEcriture('troisième', 4963, 'DSCF4963.RAF', EXPOSITION, 7102))
    egal('enAttente', sansPhoto.etat)
end)

essai("Proposition dépassée : match_series clôt la proposition d'une photo qu'il harmonise ; ni celle de la référence, ni un plan", function()
    local c = Conversation.nouvelle(1000)
    local REFERENCE = { id = 4961, fichier = 'DSCF4961.RAF' }
    appelOutil(c, 'p1', 'preview_settings', { photo_id = 4962, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4962, 'DSCF4962.RAF', EXPOSITION))
    local surSerie = derniereProposition(c)
    appelOutil(c, 'p2', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4961, 'DSCF4961.RAF', EXPOSITION))
    local surReference = derniereProposition(c)
    -- Un plan (sans confirm) : rien d'écrit, toutes attendent.
    appelOutil(c, 's0', 'match_series', { reference_id = 4961, photo_ids = { 4962 } }, Json.encode({ reference = REFERENCE,
        photos = { { id = 4962, fichier = 'DSCF4962.RAF', correction_proposee = { Exposure2012 = 0.2 } } }, rien_n_est_applique = 'Plan seulement.' }))
    egal('enAttente', surSerie.etat, 'un plan')
    egal('enAttente', surReference.etat)
    -- Une photo déjà proche de la référence : rien d'écrit.
    appelOutil(c, 's1', 'match_series', { reference_id = 4961, photo_ids = { 4962 }, confirm = true }, Json.encode({ reference = REFERENCE,
        photos = { { id = 4962, fichier = 'DSCF4962.RAF', correction = 'aucune : déjà proche de la référence' } } }))
    egal('enAttente', surSerie.etat, 'rien à corriger')
    -- Harmonisée par la mesure (deux passes, sans etape_id) : la proposition de la photo est
    -- remplacée ; celle de la référence, que match_series ne touche pas, attend.
    appelOutil(c, 's2', 'match_series', { reference_id = 4961, photo_ids = { 4962 }, confirm = true, step_name = 'harmonisation' },
        Json.encode({ reference = REFERENCE, photos = { { id = 4962, fichier = 'DSCF4962.RAF',
            correction_proposee = { Exposure2012 = 0.2 }, etapes = { 'Claude · harmonisation : passe 1', 'Claude · harmonisation : passe 2' } } } }))
    egal('remplacee', surSerie.etat, "harmonisée : Accepter poserait l'ancienne proposition par-dessus")
    egal('harmonisation : passe 1', surSerie.etapeClaude)
    egal('enAttente', surReference.etat, 'la référence ne change pas')
    egal(surReference, Conversation.propositionEnAttente(c))
    -- Par la prise de vue (by = exif) : `etape`.
    appelOutil(c, 'p3', 'preview_settings', { photo_id = 4963, settings = { Exposure2012 = 0.3 } },
        reponseProposition(4963, 'DSCF4963.RAF', EXPOSITION))
    local exif = derniereProposition(c)
    appelOutil(c, 's3', 'match_series', { reference_id = 4961, photo_ids = { 4963 }, by = 'exif', confirm = true },
        Json.encode({ reference = REFERENCE, photos = { { id = 4963, fichier = 'DSCF4963.RAF', etape = 'Claude · expositions reproduites' } } }))
    egal('remplacee', exif.etat)
    egal('expositions reproduites', exif.etapeClaude)
    egal("Remplacée par une retouche de Claude (étape « expositions reproduites ») : elle n'attend plus votre accord.", Fenetre.phraseClose(exif))
    -- Une réponse en erreur : rien.
    appelOutil(c, 's4', 'match_series', { reference_id = 4962, photo_ids = { 4961 }, confirm = true }, 'Aucune photo à harmoniser.', true)
    egal('enAttente', surReference.etat, 'une erreur')
end)

essai("Fenêtre : une leçon qui arrive remplace la leçon choisie avant ; d'une autre photo que l'active, elle se montre aussi", function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    local l1 = appelLecon(c, 'l1', entreeLecon(), reponseLecon())
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('notation', p.onglet, "déjà là à l'ouverture : pas de bascule")
        -- « Leçon de la photo » de la première leçon : elle est choisie.
        vrai(Fenetre.montrerLecon(l1))
        egal(c.elements[l1].id, Fenetre.leconChoisie)
        p.onglet = 'notation'
        -- Une autre leçon de la photo active arrive : l'onglet la montre, plus la leçon choisie avant.
        Conversation.ajouterDemande(c, 'Refais la retouche, plus contrastée.')
        local l2 = appelLecon(c, 'l2', entreeLecon(), reponseLecon({ fichier = 'DSCF4961-2.RAF' }))
        Fenetre.rafraichir()
        egal('lecon', p.onglet, 'la leçon arrivée')
        egal(c.elements[l2].id, (Fenetre.leconMontree()).id, 'la leçon arrivée, pas celle choisie avant')
        egal('Leçon de la photo · DSCF4961-2.RAF', p.leconTitre)
        -- La leçon d'une autre photo que l'active : la bascule la montre, elle aussi.
        p.onglet = 'notation'
        local autre = entreeLecon()
        autre.photo_id = 53636310
        local l3 = appelLecon(c, 'l3', autre, reponseLecon({ photo = 53636310, fichier = 'DSCF4962.RAF' }))
        Fenetre.rafraichir()
        egal('lecon', p.onglet)
        egal(c.elements[l3].id, (Fenetre.leconMontree()).id, "la leçon de l'autre photo")
        egal('Leçon de la photo · DSCF4962.RAF', p.leconTitre)
        -- Vue : un rafraîchissement de plus ne change rien.
        p.onglet = 'notation'
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'une seule bascule')
        egal('Leçon de la photo · DSCF4962.RAF', p.leconTitre)
    end)
end)

essai("Fenêtre : la ligne d'une leçon refusée ouvre le détail de son appel ; la ligne d'actions n'a pas de clic de texte", function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    local refusee, outil = appelLecon(c, 'l1', entreeLecon(), "Le point « light » : at_capture vide.", true)
    local faite = appelLecon(c, 'l2', entreeLecon(), reponseLecon())
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        local onglet = p.onglet
        local n = ligneMontree(function(l) return l.element == refusee and l.genre == 'note' end)
        egal('lecon', Fenetre.sorteDeClic(Fenetre.lignes[Fenetre.premiere + n - 1], c.elements[refusee]))
        local taches, dialogues = #S.taches, #S.dialogues
        p.saisie = 'Texte validé par le clic'
        Fenetre.cliquerLigne(n)
        egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande")
        p.saisie = ''
        lancerTaches(taches)
        egal(dialogues + 1, #S.dialogues, 'le détail de son appel')
        egal('Claude · ' .. c.elements[outil].texte, S.dialogues[#S.dialogues].title)
        egal(onglet, p.onglet, "l'onglet ne change pas")
        -- La ligne d'actions : ses boutons seulement.
        local m, l = ligneMontree(function(x) return x.genre == 'actions' and x.lecon == faite end)
        egal(nil, Fenetre.sorteDeClic(l, c.elements[faite]))
        dialogues, taches = #S.dialogues, #S.taches
        Fenetre.cliquerLigne(m)
        lancerTaches(taches)
        egal(dialogues, #S.dialogues, 'rien')
    end)
end)

-- Consignes -------------------------------------------------------------------------------------

essai('Consignes : section Leçon de la photo (600 caractères au plus), après Fin d\'une tâche, qui y renvoie', function()
    local texte = Consignes.texte
    local debut = texte:find('\n## Leçon de la photo\n', 1, true)
    vrai(debut, 'section Leçon de la photo')
    local fin = texte:find('\n## ', debut + 1, true) or (#texte + 1)
    local section = texte:sub(debut + 1, fin - 1):gsub('\n$', '')
    vrai(Texte.longueur(section) <= 600, string.format('section : %d caractères pour 600', Texte.longueur(section)))
    for _, morceau in ipairs({ 'photo_lesson en dernier', 'résumé court', 'proposition de cadre', 'lumière, couleur, composition',
        'ce qui manquait', 'chiffres', 'à la prise de vue', "réglage du boîtier seulement s'il est lu", "dans l'onglet Leçon", 'rien après',
        'Une seule leçon par photo et par conversation', "« J'ai fini »", 'proposition seule', "Proposer d'abord", 'ouverture',
        'notation', 'classement', 'série', Consignes.sansLecon }) do
        contient(section, morceau, 'section Leçon')
    end
    -- « J'ai fini » amène la leçon (synthèse : elle vient après, une par photo et par conversation),
    -- dans le même ordre qu'après une retouche ; ce n'est pas seulement une borne.
    contient(section, "Après la retouche d'une photo, ou après « J'ai fini » : résumé court", 'la leçon après « J\'ai fini »')
    vrai(not section:find('y compris après', 1, true), "« J'ai fini » ne se lit pas comme une seule restriction")
    -- Après Fin d'une tâche, qui finit par la leçon.
    local finTache = texte:find("\n## Fin d'une tâche\n", 1, true)
    vrai(finTache and finTache < debut, "après Fin d'une tâche")
    local sectionFin = texte:sub(finTache + 1, debut - 1):gsub('%s+$', '')
    vrai(sectionFin:sub(-#'Puis la leçon (voir Leçon de la photo).') == 'Puis la leçon (voir Leçon de la photo).', sectionFin)
    vrai(not sectionFin:find('termine par un résumé', 1, true), "le résumé n'est plus le dernier mot")
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
    vrai(Texte.longueur(texte) <= 7500, 'plafond des consignes')
    -- La proposition préparée à l'ouverture ne demande pas de leçon.
    vrai(not Consignes.proposerOuverture:find('photo_lesson', 1, true) and not Consignes.proposerOuverture:find('leçon', 1, true),
        "pas de leçon à l'ouverture")
    egal('[Sans leçon]', Consignes.sansLecon)
end)

essai('Conversation.messagePourClaude : la ligne « [Sans leçon] » après le contexte et le style, avant la demande', function()
    local c = Conversation.nouvelle()
    c.titreChoisi = true
    egal('[Lightroom : x]\n\n' .. Consignes.ligneStyle('neutre') .. '\n\n[Sans leçon]\n\nRetouche',
        Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', Consignes.ligneStyle('neutre'), Consignes.sansLecon))
    vrai(Consignes.ligneStyle('neutre'):find('^%[Style demandé : Neutre — balance neutre, couleurs fidèles, aucune dominante%. recette fixe'),
        'le style, puis sa recette fixe (1.3.5)')
    egal('[Lightroom : x]\n\n[Sans leçon]\n\nRetouche', Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', nil, Consignes.sansLecon))
    egal('[Lightroom : x]\n\nRetouche', Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', nil, nil))
    egal('[Lightroom : x]\n\nRetouche', Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', '', ''))
end)

-- Moteur, avec le faux Claude Code --------------------------------------------------------------

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

-- Le texte du dernier message écrit pour Claude Code (entree.jsonl de la session).
local function dernierMessage()
    local entree = Fichiers.lire(Moteur.session.dossier .. '/entree.jsonl') or ''
    local derniere
    for ligne in entree:gmatch('[^\n]+') do
        derniere = ligne
    end
    local json = Json.decode(derniere)
    local contenu = json.message.content
    return contenu[#contenu].text
end

essai('Moteur : LECON de bout en bout par relais.sh, carte faite dans la conversation ouverte ; consignes de la session', function()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    vrai(Moteur.envoyer('Retouche, puis la leçon LECON', { modele = 'haiku' }))
    local c = Moteur.courante
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    egal(c, Moteur.courante)
    local carte, outil
    for _, e in ipairs(c.elements) do
        if e.genre == 'lecon' then
            carte = e
        elseif e.genre == 'outil' and e.outil == 'photo_lesson' then
            outil = e
        end
    end
    vrai(carte, 'la carte dans le fil de la conversation ouverte')
    egal('fait', carte.etat)
    egal('DSCF4961.RAF', carte.fichier)
    egal(true, carte.rangee)
    egal(53636309, carte.photo)
    egal('Lumière', carte.points[1].nom)
    egal('Ciel brûlé à 3 % : hautes lumières baissées de 40.', carte.points[1].manque)
    egal('Composition', carte.points[3].nom)
    egal(nil, carte.points[3].manque)
    egal(outil.appel, carte.appel)
    egal('fait', outil.etat)
    -- Les consignes de la session portent la section ; la carte est rangée avec la conversation.
    local consignes = Fichiers.lire(Moteur.session.dossier .. '/consignes.md')
    contient(consignes, '## Leçon de la photo')
    contient(consignes, 'photo_lesson en dernier')
    local lue = Stockage.lire(c.id)
    local relue
    for _, e in ipairs(lue.elements) do
        if e.genre == 'lecon' then
            relue = e
        end
    end
    vrai(relue, 'carte rangée sur le disque')
    egal('DSCF4961.RAF', relue.fichier)
    egal(3, #relue.points)
    -- La case Leçon cochée (par défaut) : rien n'est joint.
    vrai(not dernierMessage():find(Consignes.sansLecon, 1, true), 'rien de joint, case cochée')
end)

essai('Préférence Leçon : cochée par défaut ; décochée, « [Sans leçon] » part après la ligne de style, sans relancer Claude Code', function()
    egal(true, Chemins.defauts.leconFinRetouche)
    egal(true, Chemins.prefs().leconFinRetouche)
    vrai(Moteur.session and Moteur.session:actif(), 'Claude Code ouvert')
    local session, dossier = Moteur.session, Moteur.session.dossier
    local consignes = Fichiers.lire(dossier .. '/consignes.md')
    prefs.leconFinRetouche = false
    local ok, raison = Moteur.envoyer('Retouche sans leçon', { modele = 'haiku', style = 'neutre' })
    vrai(ok, raison)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    egal(session, Moteur.session, 'le même processus Claude Code')
    egal(dossier, Moteur.session.dossier)
    egal(consignes, Fichiers.lire(dossier .. '/consignes.md'), 'consignes inchangées')
    local message = dernierMessage()
    local style = message:find('[Style demandé : Neutre', 1, true)
    local sans = message:find('\n\n' .. Consignes.sansLecon .. '\n\n', 1, true)
    local demande = message:find('Retouche sans leçon', 1, true)
    vrai(style and sans and demande, message)
    vrai(style < sans and sans < demande, 'après la ligne de style, avant la demande : ' .. message)
    -- Recochée : plus rien de joint.
    prefs.leconFinRetouche = nil
    vrai(Moteur.envoyer('Retouche avec leçon', { modele = 'haiku' }))
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    vrai(not dernierMessage():find(Consignes.sansLecon, 1, true), 'rien de joint, case recochée')
    egal(session, Moteur.session)
end)

-- Fin ------------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
