-- essais-lecon.lua : la leçon de la photo dans la fenêtre Claude (1.3, lot 13), hors de Lightroom
-- (LuaJIT, Lightroom simulé par Simulation.lua) : l'élément `lecon` du fil, de l'entrée de
-- photo_lesson à la réponse du connecteur (Conversation : points dans l'ordre Lumière, Couleur,
-- Composition, fichier, rangement, refus, interruption, read_facts sans carte), la carte en lignes
-- de genres existants (Fil : 16 lignes au plus, largeur, cache), son stockage (points en tableau,
-- leçon restée en cours relue en erreur), le clic sur la carte (détail de l'appel), la recherche,
-- la section « Leçon de la photo » des consignes, la case Leçon (« [Sans leçon] » joint sans
-- relancer Claude Code), et le cas LECON de bout en bout par relais.sh avec faux-claude.sh. Ni
-- Claude, ni quota ; les fichiers vont dans un dossier personnel temporaire.
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

-- La largeur du texte du fil (Fenetre.largeurTexte), et celle qu'une ligne ne dépasse jamais.
local D = Dispositions.dimensions()
local LARGEUR = D.fil - 20
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

-- Chaque ligne tient dans la largeur, avec un genre et une icône que la fenêtre connaît.
local function verifierLignes(lignes)
    local genres, icones = {}, {}
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
        vrai(Fil.largeur(l.texte, Fil.polices[l.genre]) <= LARGEUR_LIGNE,
            string.format('hors de la largeur (%.0f pour %d) : %s', Fil.largeur(l.texte, Fil.polices[l.genre]), LARGEUR_LIGNE, l.texte))
    end
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

essai("Fil : lignes d'une leçon (titre, axes, deux moitiés retirées ; Rien ne manquait ; À refaire), genres et icônes connus", function()
    local c = Conversation.nouvelle()
    local carte = appelLecon(c, 'l1', entreeLecon())
    -- Pendant l'appel : le titre sans fichier, ● (en cours).
    local lignes = lignesDe(c, carte)
    egal('proposition', lignes[1].genre)
    egal('Leçon de la photo', lignes[1].texte)
    egal('cours', lignes[1].icone)
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'l1', images = {}, erreur = false, textes = { reponseLecon() } } } })
    lignes = lignesDe(c, carte)
    verifierLignes(lignes)
    egal(table.concat({
        "proposition|note|Leçon de la photo · DSCF4961.RAF",
        "titre||Lumière",
        "claude||    Ce qui manquait : Ciel brûlé à 3 % : hautes lumières -40.",
        "claude||    À la prise de vue : Compenser de −2/3 IL face au ciel clair.",
        "titre||Couleur",
        "claude||    Ce qui manquait : Dominante bleue à l'ombre : +400 K.",
        "claude||    À la prise de vue : Balance des blancs Ombre plutôt qu'Auto.",
        "titre||Composition",
        "claude||    Rien ne manquait.",
        "claude||    À refaire : Le flamant au tiers gauche, regard vers le cadre : à refaire.",
    }, '\n'), textes(lignes))
    -- Le texte de Claude reste une phrase : une moitié qui commence par « - » ou « 1. » n'en fait
    -- pas une puce.
    c.elements[carte].points[2].manque = '- Dominante **bleue**'
    c.elements[carte].points[3].prise_de_vue = '1. Le flamant'
    lignes = lignesDe(c, carte)
    egal('    Ce qui manquait : - Dominante **bleue**', lignes[6].texte)
    egal('    À refaire : 1. Le flamant', lignes[10].texte)
    for _, l in ipairs(lignes) do
        vrai(not l.texte:find('•', 1, true), 'pas de puce')
    end
end)

essai('Fil : 16 lignes au plus pour des moitiés de 140 caractères, coupées en deux lignes, « … » au-delà', function()
    local c = Conversation.nouvelle()
    local longue = phrase("Le ciel brûlé à 3 % au départ ; hautes lumières baissées de 40 et blancs de 20. ", 140)
    local entree = { photo_id = 53636309, points = {} }
    for _, axe in ipairs({ 'light', 'color', 'composition' }) do
        entree.points[#entree.points + 1] = { axis = axe, missing = longue, at_capture = longue }
    end
    local carte = appelLecon(c, 'l1', entree, reponseLecon())
    local lignes = lignesDe(c, carte)
    verifierLignes(lignes)
    egal(16, #lignes, '1 + 3 × (1 + 2 + 2)')
    -- Chaque moitié tient en deux lignes, la seconde retirée elle aussi, sans « … ».
    egal('claude', lignes[3].genre)
    vrai(lignes[3].texte:sub(1, #'    Ce qui manquait : ') == '    Ce qui manquait : ', lignes[3].texte)
    vrai(lignes[4].texte:sub(1, 4) == '    ' and lignes[4].texte:sub(5, 5) ~= ' ', 'ligne de suite retirée : ' .. lignes[4].texte)
    for _, l in ipairs(lignes) do
        vrai(not l.texte:find('…', 1, true), 'rien de coupé : ' .. l.texte)
    end
    -- Des caractères larges (140 « W ») ou un mot sans espace : toujours deux lignes par moitié,
    -- la seconde finie par « … », dans la largeur.
    for _, motif in ipairs({ 'W', 'é' }) do
        local large = phrase(motif, 140)
        for _, p in ipairs(c.elements[carte].points) do
            p.manque, p.prise_de_vue = large, large
        end
        lignes = lignesDe(c, carte)
        verifierLignes(lignes)
        egal(16, #lignes, 'motif ' .. motif)
        vrai(lignes[4].texte:sub(-#'…') == '…', 'coupée par « … » : ' .. lignes[4].texte)
        vrai(Fil.couper('    Ce qui manquait : ' .. large, LARGEUR_LIGNE, 'texte', '    ')[3] ~= nil, 'il fallait bien plus de deux lignes')
    end
    -- Un point sans défaut, à la prise de vue courte : deux lignes de moins.
    c.elements[carte].points[3].manque = nil
    c.elements[carte].points[3].prise_de_vue = 'Le cadre.'
    egal(14, #lignesDe(c, carte))
end)

essai("Fil : leçon refusée, interrompue ou non rangée ; un long refus borné", function()
    local c = Conversation.nouvelle()
    local refusee = appelLecon(c, 'l1', entreeLecon(), "Le point « light » : at_capture vide. Rien n'a été rangé.", true)
    local lignes = lignesDe(c, refusee)
    egal("note|erreur|Leçon non rangée : Le point « light » : at_capture vide. Rien n'a été rangé.", textes(lignes))
    -- Interrompue (ou relue en cours) : sans raison donnée.
    c.elements[refusee].texte = ''
    egal("note|erreur|Leçon non rangée : l'appel n'a pas abouti.", textes(lignesDe(c, refusee)))
    -- Un refus très long : trois lignes au plus, la dernière finie par « … ».
    c.elements[refusee].texte = phrase("photo_lesson : donner les trois points de la leçon, un par axe. ", 900)
    lignes = lignesDe(c, refusee)
    egal(Fil.LIGNES_ERREUR_LECON, #lignes)
    vrai(lignes[#lignes].texte:sub(-#'…') == '…', lignes[#lignes].texte)
    verifierLignes(lignes)
    -- Faite mais non rangée : la carte, puis la remarque (✕), en deux lignes au plus.
    local remarque = "Leçon non rangée : le module de Lightroom chargé ne connaît pas encore la commande lecon (module d'avant la 1.3). "
        .. "Quitter puis relancer Lightroom après l'installation ; la leçon de cette réponse reste valable."
    local nonRangee = appelLecon(c, 'l2', entreeLecon(), reponseLecon({ rangee = false }, { remarque }))
    lignes = lignesDe(c, nonRangee)
    verifierLignes(lignes)
    egal('Leçon de la photo · DSCF4961.RAF', lignes[1].texte)
    vrai(#lignes <= 16 + Fil.LIGNES_REMARQUE_LECON, #lignes .. ' lignes')
    egal('note', lignes[11].genre)
    egal('erreur', lignes[11].icone)
    contient(lignes[11].texte, 'Leçon non rangée : le module')
    -- Rangée pour la session seulement (carnet.json non écrit) : ⓘ.
    local gardee = appelLecon(c, 'l3', entreeLecon(), reponseLecon(nil, { "Leçon gardée pour cette session, carnet.json non écrit : disque plein" }))
    lignes = lignesDe(c, gardee)
    egal('note', lignes[#lignes].icone)
    contient(lignes[#lignes].texte, 'carnet.json non écrit')
end)

essai('Fil : le cache suit la leçon (fichier, rangement, textes des points) et garde les lignes sinon', function()
    local c = Conversation.nouvelle()
    local carte = appelLecon(c, 'l1', entreeLecon(), reponseLecon())
    local cache = {}
    local avant = lignesDe(c, carte, cache)
    local e = c.elements[carte]
    vrai(cache[e.id] and cache[e.id].lignes[1] == avant[1], 'gardées')
    egal(avant[1], lignesDe(c, carte, cache)[1], 'rien de changé : les mêmes lignes')
    e.fichier = 'DSCF0002.RAF'
    egal('Leçon de la photo · DSCF0002.RAF', lignesDe(c, carte, cache)[1].texte, 'autre fichier')
    e.points[1].prise_de_vue = 'Une autre prise de vue.'
    egal('    À la prise de vue : Une autre prise de vue.', lignesDe(c, carte, cache)[4].texte, 'autre texte')
    e.points[3].manque = 'Horizon penché de 1,8°.'
    egal('    Ce qui manquait : Horizon penché de 1,8°.', lignesDe(c, carte, cache)[9].texte, 'manque ajouté')
    e.rangee, e.remarque = false, 'Leçon non rangée : x.'
    local lignes = lignesDe(c, carte, cache)
    egal('Leçon non rangée : x.', lignes[#lignes].texte, 'rangement')
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
    -- Le fil de la conversation relue est celui d'avant.
    egal(textes(lignesDe(c, faite)), textes(lignesDe(lue, faite)))
    egal("note|erreur|Leçon non rangée : l'appel n'a pas abouti.", textes(lignesDe(lue, enCours)))
    Stockage.supprimer(c.id)
end)

-- Fenêtre ---------------------------------------------------------------------------------------

essai("Fenêtre : un clic sur la carte montre le détail de son appel, sans envoyer la demande tapée ni changer d'onglet", function()
    photoActive(53636309, 'DSCF4961.RAF')
    -- Les conversations chargées d'abord : la fenêtre ne remplace pas celle-ci en s'ouvrant.
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    local carte, outil = appelLecon(c, 'l1', entreeLecon(), reponseLecon())
    ouvrirFenetre(function(p)
        egal(c, Moteur.courante, 'la conversation de la carte')
        Fenetre.rafraichir()
        local onglet = p.onglet
        -- Une ligne de la carte (celle d'un axe) dans la fenêtre de lecture.
        local n
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.element == carte and l.texte == 'Couleur' then
                n = i
            end
        end
        vrai(n, "la ligne de l'axe Couleur est montrée")
        egal('lecon', Fenetre.sorteDeClic(Fenetre.lignes[Fenetre.premiere + n - 1], c.elements[carte]))
        -- Le texte du champ, validé par le clic (son envoi automatique attend dans une tâche).
        local avantSaisie = #S.taches
        p.saisie = 'Texte validé par le clic'
        local taches, dialogues = #S.taches, #S.dialogues
        Fenetre.cliquerLigne(n)
        egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande")
        egal(taches + 1, #S.taches, 'le détail dans une tâche')
        p.saisie = ''
        local demandes = #Moteur.courante.elements
        lancerTaches(avantSaisie)
        egal(demandes, #Moteur.courante.elements, 'rien envoyé')
        egal(false, Moteur.travaille)
        egal(dialogues + 1, #S.dialogues)
        local d = S.dialogues[#S.dialogues]
        egal('Claude · ' .. c.elements[outil].texte, d.title)
        egal('Claude · photo_lesson · photo 53636309', d.title)
        local champ
        for _, v in ipairs(vues(d.contents)) do
            if v.genre == 'edit_field' then
                champ = v.args.value
            end
        end
        contient(champ, 'at_capture', 'ce que Claude a donné')
        contient(champ, '— Réponse —')
        contient(champ, 'DSCF4961.RAF', 'la réponse du connecteur')
        egal(onglet, p.onglet, "l'onglet ne change pas")
        egal(nil, Fenetre.etape, "pas d'étape choisie")
        -- Le titre de la carte aussi.
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.element == carte and l.genre == 'proposition' then
                n = i
            end
        end
        dialogues = #S.dialogues
        taches = #S.taches
        Fenetre.cliquerLigne(n)
        lancerTaches(taches)
        egal(dialogues + 1, #S.dialogues, 'le titre ouvre le même détail')
        -- Sans la ligne de son appel (conversation abîmée) : rien.
        c.elements[outil].appel = 'autre'
        Fenetre.rafraichir()
        dialogues, taches = #S.dialogues, #S.taches
        Fenetre.cliquerLigne(n)
        lancerTaches(taches)
        egal(dialogues, #S.dialogues, "rien sans l'appel")
        c.elements[outil].appel = 'l1'
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
        'ce qui manquait', 'chiffres', 'à la prise de vue', "réglage du boîtier seulement s'il est lu", 'en carte', 'rien après',
        'Une seule leçon par photo et par conversation', "« J'ai fini »", 'proposition seule', "Proposer d'abord", 'ouverture',
        'notation', 'classement', 'série', Consignes.sansLecon }) do
        contient(section, morceau, 'section Leçon')
    end
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
    egal('[Lightroom : x]\n\n[Style demandé : Neutre — balance neutre, couleurs fidèles, aucune dominante]\n\n[Sans leçon]\n\nRetouche',
        Conversation.messagePourClaude(c, 'Retouche', '[Lightroom : x]', Consignes.ligneStyle('neutre'), Consignes.sansLecon))
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
