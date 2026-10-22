-- essais-dispositions.lua : la fenêtre Claude (la Conversation claire, seule disposition depuis
-- que l'Atelier et le Panneau sont retirés) hors de Lightroom (LuaJIT, Lightroom simulé par
-- Simulation.lua) : fenêtre déjà ouverte, boucle, onglets, carte Note et ses flèches, nouvelle
-- conversation par photo, proposition préparée à l'ouverture, anciennes conversations de séance
-- absentes de la liste, Gestionnaire de modules externes (modèle, effort, cases), vignettes dans un
-- cadre 3:2, image « aucun aperçu » ; structure de la 1.3 (carte de l'étape, rangée Je le fais,
-- crochets de l'aperçu et des onglets, clics sur le fil, vue du fil, agrandissement à deux
-- images). Le registre des notes (Notation) garde ici les appels reçus :
-- la simulation de la fenêtre n'écrit pas dans un catalogue. Ni Claude, ni quota.
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

local function copie(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
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

-- Le bouton de ce titre (titre lié lu dans `p`) ; `cleActif` : celui dont `enabled` suit cette clé.
local function bouton(contenu, p, titre, cleActif)
    for _, v in ipairs(vues(contenu)) do
        local t = v.args.title
        if type(t) == 'table' and t.liaison then
            t = p[t.key]
        end
        if S.BOUTONS[v.genre] and t == titre
            and (not cleActif or (type(v.args.enabled) == 'table' and v.args.enabled.key == cleActif)) then
            return v
        end
    end
    error('bouton introuvable : ' .. tostring(titre), 2)
end

-- Le calque (ou le bouton) de cette infobulle : Accepter de la carte Note et de la Proposition sont
-- des boutons bleus en image, cliqués par leur calque (fenêtre B, lot B5).
local function parInfobulle(contenu, infobulle)
    for _, v in ipairs(vues(contenu)) do
        if v.args.tooltip == infobulle then
            return v
        end
    end
    error('vue introuvable par son infobulle : ' .. tostring(infobulle), 2)
end

local ACCEPTER_NOTE = "Poser la note proposée dans Lightroom (sans Claude ni quota)"

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Images = require 'Images'
local Stockage = require 'Stockage'

-- Registre des notes : le vrai (Notation.lua), ses lectures et écritures remplacées ici (la
-- simulation de la fenêtre n'a pas de catalogue où écrire), remises à la fin.
local registre = { propositions = {}, poses = {}, decisions = {} }
local Notation = require 'Notation'
local contratNotation = {}
for _, nom in ipairs({ 'abonner', 'desabonner', 'proposition', 'poser', 'decider' }) do
    contratNotation[nom] = Notation[nom]
end
local function changer(quoi)
    Notation.version = Notation.version + 1
    if registre.abonne then
        registre.abonne(quoi)
    end
end
function Notation.abonner(nom, fn)
    registre.abonnes = (registre.abonnes or 0) + 1
    registre.abonne = fn
end
function Notation.desabonner()
    registre.abonne = nil
end
function Notation.proposition(id)
    return copie(registre.propositions[tostring(id)])
end
-- Comme le vrai : sans note ni drapeau, la proposition telle quelle ; sinon une note changée.
function Notation.poser(liste)
    registre.poses[#registre.poses + 1] = copie(liste)
    for _, item in ipairs(liste) do
        local p = registre.propositions[tostring(item.photo)]
        if p then
            if item.note == nil and item.drapeau == nil then
                p.etat = 'acceptee'
            else
                p.etat, p.note_choisie, p.drapeau_choisi = 'changee', item.note, item.drapeau
            end
        end
    end
    changer('pose')
    return { ok = true, resultats = {} }
end
function Notation.decider(id, etat)
    registre.decisions[#registre.decisions + 1] = { photo = id, etat = etat }
    local p = registre.propositions[tostring(id)]
    if p then
        p.etat = etat
    end
    changer('decision')
    return true
end
local function proposer(id, champs)
    champs.photo = id
    champs.etat = champs.etat or 'proposee'
    registre.propositions[tostring(id)] = champs
    changer('propositions')
end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
-- La proposition préparée à l'ouverture a son propre essai (plus bas) : ailleurs, Claude reste libre.
prefs.propositionAOuverture = false

local function photoActive(id, nom, note, pickStatus)
    local photo = S.photo(id, nom)
    photo.note, photo.pickStatus = note, pickStatus
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Contrats ------------------------------------------------------------------------------------

essai('Contrats : registre des notes ; plus de bouton Évaluer ni de Séance de notation', function()
    for nom, fn in pairs(contratNotation) do
        vrai(type(fn) == 'function', 'Notation.' .. nom .. ' manque')
    end
    -- Claude note d'abord chaque photo qu'il traite (demandé par Dany le 20 octobre 2026) : plus
    -- de messages du bouton Évaluer.
    egal(nil, Consignes.noterPhoto)
    egal(nil, Consignes.noterSelection)
    egal(nil, Fenetre.noter)
    egal(nil, Fenetre.verifierNote)
    -- La Séance de notation est retirée (demandé par Dany le 20 octobre 2026).
    vrai(not pcall(require, 'FenetreNotation'), 'FenetreNotation retirée')
    egal(nil, Fenetre.seance)
    egal(nil, Consignes.passes)
end)

-- Réouverture ---------------------------------------------------------------------------------

essai('Ouvrir une fenêtre déjà ouverte : elle passe devant, et l\'aperçu remontre la photo active', function()
    photoActive(53636309, 'DSCF4961.RAF', 0, 0)
    local vu = false
    S.pendantFenetre = function()
        vu = true
        local devant, taches = S.devant or 0, #S.taches
        Fenetre.voirActive = false
        Fenetre.afficher()
        egal(devant + 1, S.devant, 'la fenêtre passe devant')
        -- … et l'aperçu remontre la photo active, relue dans une tâche.
        egal(taches + 1, #S.taches, 'photo active relue')
        S.taches[#S.taches]()
        egal(true, Fenetre.voirActive, "l'aperçu remontre la photo active")
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    S.pendantFenetre = nil
end)

essai('Une seule disposition : ni taille ni disposition dans les préférences, le cadre de la Conversation claire', function()
    -- L'Atelier, le Panneau et le choix de la disposition sont retirés, comme celui de la taille
    -- (demandés par Dany le 20 octobre 2026) ; le cadre enregistré garde son nom.
    egal(nil, Chemins.defauts.disposition, 'plus de préférence de disposition')
    egal(nil, Chemins.defauts.taille, 'plus de préférence de taille')
    egal(nil, Dispositions.atelier)
    egal(nil, Dispositions.panneau)
    egal('conversation', Dispositions.dimensions().nom)
    egal('DeveloppeurClaude-conversation-grande-4', Fenetre.cadre(), 'FORME 4 : la fenêtre B élargie')
    egal(nil, Fenetre.rouvrir)
    egal(nil, Fenetre.elementsMenu)
end)

essai('Boucle de la fenêtre : toutes les 2 s, les voyants et la photo active relus', function()
    local sommeils, verifies, ok, erreur = 0, 0, nil, nil
    S.pendantFenetre = function()
        local dormir, verifier = S.modules.LrTasks.sleep, Fenetre.verifier
        Fenetre.verifier = function(...)
            verifies = verifies + 1
            return verifier(...)
        end
        S.modules.LrTasks.sleep = function()
            sommeils = sommeils + 1
            if sommeils >= 12 then
                error('boucle arrêtée par l\'essai', 0)
            end
        end
        ok, erreur = pcall(Fenetre.boucle, Fenetre.generation)
        S.modules.LrTasks.sleep, Fenetre.verifier = dormir, verifier
        egal(1, verifies, 'voyants relus au huitième tour (2 s)')
    end
    Fenetre.afficher()
    vrai(not ok and erreur == 'boucle arrêtée par l\'essai', tostring(erreur))
    S.pendantFenetre = nil
end)

essai('Modèle et effort : quatre modèles, cinq efforts, maximal par défaut', function()
    egal('opus', Chemins.defauts.modele)
    egal('max', Chemins.defauts.effort)
    egal(true, Chemins.defauts.nouvelleParPhoto)
    egal('Effort maximal', Consignes.effort('max').title)
    egal(nil, Consignes.effort('enorme'))
    vrai(Consignes.modele('fable'), 'Fable proposé')
    local valeurs = {}
    for _, item in ipairs(Consignes.itemsModeles()) do valeurs[#valeurs + 1] = item.value end
    egal('fable opus sonnet haiku', table.concat(valeurs, ' '))
    valeurs = {}
    for _, item in ipairs(Consignes.itemsEfforts()) do valeurs[#valeurs + 1] = item.value end
    egal('max xhigh high medium low', table.concat(valeurs, ' '))
    vrai(Consignes.itemsModeles() ~= Consignes.itemsModeles() and getmetatable(Consignes.itemsModeles()) == nil, 'tables neuves')
end)

-- Onglets -------------------------------------------------------------------------------------

essai('Onglets : une proposition ou une note qui arrive se montre, une seule fois', function()
    -- Ici, une autre photo choisie ne doit pas commencer de nouvelle conversation (essai à part).
    prefs.nouvelleParPhoto = false
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        -- Conversation claire : l'aperçu toujours montré, la carte Note dessous par défaut.
        egal('notation', p.onglet)
        local c = Moteur.courante
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'onglet-1', nom = 'mcp__developpeur__preview_settings',
            entree = { reason = 'Balance', settings = { Exposure2012 = 0.35 } } } } })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'une proposition qui arrive se montre')
        egal(true, p.aProposition)
        -- Dany revient à la note : la fenêtre ne reprend pas la main.
        p.onglet = 'notation'
        Fenetre.rafraichir()
        egal('notation', p.onglet)
        -- Une note proposée pour la photo active : l'onglet Note.
        p.onglet = 'proposition'
        proposer(4961, { note = 3, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Tient seule.', le = 100 })
        Fenetre.rafraichirNotation()
        egal('notation', p.onglet)
        p.onglet = 'proposition'
        Fenetre.rafraichirNotation()
        egal('proposition', p.onglet, 'une seule fois')
        -- Une nouvelle proposition « à vérifier » se montre aussi (constaté : la plus fréquente
        -- dans Lightroom, et celle qu'il faut regarder).
        proposer(4961, { note = 3, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Tient seule.', le = 102, etat = 'a_verifier' })
        Fenetre.rafraichirNotation()
        egal('notation', p.onglet, 'une proposition à vérifier se montre')
        p.onglet = 'proposition'
        Fenetre.rafraichirNotation()
        egal('proposition', p.onglet, 'une seule fois, à vérifier comprise')
        -- Une autre photo choisie, qui a déjà sa proposition : l'onglet ne change pas.
        proposer(4962, { note = 2, drapeau = 'aucun', criteres = {}, raison = '', le = 101 })
        photoActive(4962, 'DSCF4962.RAF', 0, 0)
        Fenetre.majPhoto()
        egal('proposition', p.onglet)
        -- Un clic sur un onglet n'envoie pas la demande validée par ce clic.
        p.saisie = 'Texte validé par le clic'
        vrai(Fenetre.envoiAuto, 'envoi prévu')
        p.onglet = 'notation'
        egal(nil, Fenetre.envoiAuto, "le clic d'un onglet annule l'envoi automatique")
        -- Un clic sur une ligne d'image la montre dans l'aperçu, toujours visible : l'onglet ne
        -- change pas.
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'onglet-1', textes = { '{}' }, images = { { donnees = 'x' } }, erreur = false } } },
            nil, function() return 'image-essai.jpg' end)
        Fenetre.rafraichir()
        for i = 1, Fenetre.T.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l and l.image then
                Fenetre.cliquerLigne(i)
                break
            end
        end
        egal('notation', p.onglet, "un clic sur une image ne change pas d'onglet")
        vrai(Fenetre.indiceImage, "l'image choisie dans l'aperçu")
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end
    Fenetre.afficher()
    prefs.nouvelleParPhoto = true
    S.pendantFenetre = nil
end)

-- Nouvelle conversation par photo -------------------------------------------------------------

essai('Autre photo choisie : une nouvelle conversation, pas pendant que Claude travaille ni pour une conversation vide', function()
    prefs.nouvelleParPhoto = true
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    Fenetre.cleVue, Fenetre.cleVueLe, Moteur.finTravail = nil, nil, 0
    S.pendantFenetre = function()
        Fenetre.majPhoto()
        -- Une conversation neuve, puis un premier message, sur la photo 4961.
        Moteur.nouvelle()
        local premiere = Moteur.courante
        -- Une conversation avec un message, sur la photo 4961.
        Conversation.ajouterDemande(premiere, 'Retouche-la')
        premiere.cle = Fenetre.cleVue
        vrai(premiere.cle and premiere.cle:find('4961', 1, true), 'clé de la sélection : ' .. tostring(premiere.cle))
        -- La même photo relue : rien.
        Fenetre.majPhoto()
        egal(premiere, Moteur.courante, 'même photo : même conversation')
        -- Dany choisit une autre photo : une nouvelle conversation, vide.
        photoActive(4962, 'DSCF4962.RAF', 0, 0)
        Fenetre.majPhoto()
        local deuxieme = Moteur.courante
        vrai(deuxieme ~= premiere, 'nouvelle conversation')
        egal(0, #deuxieme.elements)
        -- Une conversation vide ne se remplace pas par une autre vide.
        photoActive(4963, 'DSCF4963.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(deuxieme, Moteur.courante, 'conversation vide gardée')
        -- Pendant que Claude travaille (show_photo, tri), la sélection qu'il change devient celle de
        -- la conversation, et aussi juste après la fin de son travail.
        Conversation.ajouterDemande(deuxieme, 'Montre-moi la 4964')
        deuxieme.cle = Fenetre.cleVue
        Moteur.travaille = true
        photoActive(4964, 'DSCF4964.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(deuxieme, Moteur.courante, 'Claude travaille : même conversation')
        vrai(deuxieme.cle:find('4964', 1, true), 'la sélection de Claude devient celle de la conversation')
        Moteur.travaille = false
        Moteur.finTravail = os.time()
        photoActive(4965, 'DSCF4965.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(deuxieme, Moteur.courante, 'juste après le travail : même conversation')
        -- Plus tard, une autre photo de Dany : nouvelle conversation, sauf si la préférence est
        -- décochée.
        Moteur.finTravail = os.time() - Fenetre.DELAI_APRES_TRAVAIL - 1
        prefs.nouvelleParPhoto = false
        photoActive(4966, 'DSCF4966.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(deuxieme, Moteur.courante, 'préférence décochée : même conversation')
        prefs.nouvelleParPhoto = true
        photoActive(4967, 'DSCF4967.RAF', 0, 0)
        Fenetre.majPhoto()
        vrai(Moteur.courante ~= deuxieme, 'autre photo : nouvelle conversation')
        -- Revenir à une photo déjà vue d'une ancienne conversation ne la rouvre pas : la
        -- conversation montrée, vide, reste.
        local troisieme = Moteur.courante
        photoActive(4961, 'DSCF4961.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(troisieme, Moteur.courante)
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
end)

essai('Autre photo : la clé posée par Envoyer, une ancienne conversation continuée, une fenêtre fermée pendant le travail', function()
    prefs.nouvelleParPhoto = true
    photoActive(5001, 'DSCF5001.RAF', 0, 0)
    Fenetre.cleVue, Fenetre.cleVueLe, Moteur.finTravail = nil, nil, 0
    local envoyer = Moteur.envoyer
    -- Le moteur remplacé : la demande s'ajoute à la conversation, Claude « travaille ».
    Moteur.envoyer = function(texte)
        Conversation.ajouterDemande(Moteur.courante, texte)
        Moteur.travaille = true
        return true
    end
    local conversation
    S.pendantFenetre = function()
        Fenetre.majPhoto()
        Moteur.nouvelle()
        conversation = Moteur.courante
        -- Envoyer pose la sélection de la demande sur la conversation.
        Fenetre.envoyer('Retouche la 5001')
        S.taches[#S.taches]()
        vrai(conversation.cle and conversation.cle:find('5001', 1, true), 'clé posée par Envoyer : ' .. tostring(conversation.cle))
        egal(conversation.cle, Fenetre.cleVue)
        -- Dany ferme la fenêtre pendant que Claude travaille.
    end
    Fenetre.afficher()
    -- Fenêtre fermée : Claude montre la 5002 (show_photo), puis finit son travail.
    photoActive(5002, 'DSCF5002.RAF', 0, 0)
    Moteur.travaille = false
    Moteur.finTravail = os.time()
    -- Réouverture : la sélection changée est celle de Claude, la conversation reste.
    Fenetre.cleVueLe = os.time() - 60
    S.pendantFenetre = function()
        egal(conversation, Moteur.courante, 'même conversation à la réouverture')
        vrai(#conversation.elements > 0, 'avec sa demande')
        vrai(conversation.cle:find('5002', 1, true), 'la sélection de Claude devient la sienne')
        -- Une ancienne conversation rouverte depuis la liste, dont la sélection est la 5003 : la
        -- choisir dans Lightroom la continue, sans en ouvrir une autre.
        Moteur.finTravail = os.time() - 60
        Moteur.nouvelle()
        local ancienne = Moteur.courante
        Conversation.ajouterDemande(ancienne, 'Recadre la 5003')
        photoActive(5003, 'DSCF5003.RAF', 0, 0)
        local cle = require('Lightroom').photos().cle
        photoActive(5002, 'DSCF5002.RAF', 0, 0)
        ancienne.cle = cle
        photoActive(5003, 'DSCF5003.RAF', 0, 0)
        Fenetre.majPhoto()
        egal(ancienne, Moteur.courante, 'la sélection de la conversation : elle continue')
    end
    Fenetre.afficher()
    Moteur.envoyer = envoyer
    S.pendantFenetre = nil
end)

essai('Ouverture : Claude prépare une proposition sur une conversation vide, sans basculer vers elle', function()
    prefs.propositionAOuverture = true
    photoActive(5101, 'DSCF5101.RAF', 0, 0)
    local envoyer, envois = Moteur.envoyer, {}
    Moteur.envoyer = function(texte)
        envois[#envois + 1] = texte
        Conversation.ajouterDemande(Moteur.courante, texte)
        return true
    end
    Moteur.nouvelle()
    S.pendantFenetre = function()
        local p = Fenetre.p
        -- La demande part dans une tâche, à l'ouverture, sur la conversation vide.
        S.taches[#S.taches - 2]()
        egal(1, #envois, "une demande à l'ouverture")
        egal(Consignes.proposerOuverture, envois[1])
        egal(true, Fenetre.propositionAuto)
        -- La proposition arrive : elle attend dans l'onglet Proposition, la carte Note reste devant.
        local c = Moteur.courante
        c.elements[#c.elements + 1] = { genre = 'proposition', id = 'auto-1', etat = 'enAttente', texte = 'Ciel', changements = {} }
        Fenetre.rafraichirProposition()
        egal('notation', p.onglet, 'pas de bascule vers la proposition préparée')
        egal(true, p.aProposition)
        -- Une demande de Dany ensuite : les propositions suivantes se montrent de nouveau.
        Fenetre.envoyer('Plus chaud')
        egal(false, Fenetre.propositionAuto)
        c.elements[#c.elements + 1] = { genre = 'proposition', id = 'auto-2', etat = 'enAttente', texte = 'Plus chaud', changements = {} }
        c.elements[#c.elements - 1].etat = 'refusee'
        Fenetre.rafraichirProposition()
        egal('proposition', p.onglet)
        -- Une conversation qui a déjà des messages : rien de plus à l'ouverture, ni sans la case.
        local avant = #envois
        egal(false, Fenetre.proposerAOuverture(), 'conversation non vide')
        Moteur.nouvelle()
        prefs.propositionAOuverture = false
        egal(false, Fenetre.proposerAOuverture(), 'case décochée')
        egal(avant, #envois)
    end
    Fenetre.afficher()
    Moteur.envoyer = envoyer
    prefs.propositionAOuverture = false
    S.pendantFenetre = nil
end)

-- Les vues simples d'un arbre (ni conteneur ni espace) : celles que Lightroom sait masquer.
local function simples(contenu)
    local liste = {}
    for _, v in ipairs(vues(contenu)) do
        if not S.CONTENEURS[v.genre] and v.genre ~= 'spacer' then
            liste[#liste + 1] = v
        end
    end
    return liste
end

-- Les variantes des onglets : la colonne superposée de colonnes à la largeur intérieure du
-- panneau, sous l'aperçu et sa rangée (les segments sont au-dessus, sur le bord du panneau) ; nil
-- sans onglets.
local function variantesOnglets(contenu)
    local interieur = Dispositions.dimensions().interieur
    for _, v in ipairs(vues(contenu)) do
        if v.args.place == 'overlapping' then
            local colonnes = 0
            for _, e in ipairs(v.args) do
                if type(e) == 'table' and e.genre == 'column' and e.args.width == interieur then
                    colonnes = colonnes + 1
                end
            end
            if colonnes >= 2 then
                return v
            end
        end
    end
end

local function aCle(vue, cle)
    if type(vue.args.visible) ~= 'table' then
        return false
    end
    for _, k in ipairs(S.cles(vue.args.visible)) do
        if k == cle then
            return true
        end
    end
    return false
end

-- La première vue simple de ce genre dont le titre (ou la valeur) suit cette clé.
local function vueLiee(contenu, genre, cle)
    for _, v in ipairs(vues(contenu)) do
        local lien = v.args.title or v.args.value
        if v.genre == genre and type(lien) == 'table' and lien.liaison and lien.key == cle then
            return v
        end
    end
    error(genre .. ' lié à ' .. cle .. ' introuvable', 2)
end

essai('Onglets : chaque vue simple porte la condition de son onglet, aucun conteneur ne se masque (constaté)', function()
    local C = Fenetre.COULEURS
    photoActive(4961, 'DSCF4961.RAF', 2, 0)
    local nom = 'conversation'
    local D = Dispositions.dimensions()
    local construite = false
    S.pendantFenetre = function(args)
        construite = true
        local p = Fenetre.p
        Fenetre.rafraichir()
        -- Lightroom ignore `visible` sur un conteneur (la simulation le refuse aussi).
        for _, v in ipairs(vues(args.contents)) do
            vrai(not (S.CONTENEURS[v.genre] and v.args.visible ~= nil), nom .. ' : visible sur un ' .. v.genre)
        end
        local variantes = variantesOnglets(args.contents)
        if not D.onglets then
            egal(nil, variantes, nom .. ' : pas d\'onglets')
            return
        end
        vrai(variantes and variantes.args.place == 'overlapping', nom .. ' : variantes superposées sous les onglets')
        egal(#D.onglets, #variantes.args, nom .. ' : une variante par onglet')
        -- Quatre onglets (fenêtre B) : Aperçu (l'ancien Pourquoi ?), Proposition, Note (montré à
        -- l'ouverture) et Leçon, dans l'ordre des segments ; une variante chacun, dans cet ordre.
        local valeurs = {}
        for _, onglet in ipairs(D.onglets) do
            valeurs[#valeurs + 1] = onglet.valeur .. '=' .. onglet.titre
        end
        egal('apercu=Aperçu proposition=Proposition notation=Note lecon=Leçon', table.concat(valeurs, ' '), nom .. ' : quatre onglets')
        egal(4, #variantes.args, nom .. ' : quatre variantes')
        egal('apercu', D.ongletEtape)
        egal('lecon', D.ongletLecon)
        egal('notation', D.ongletParDefaut)
        egal('notation', p.onglet, nom .. ' : Note par défaut')
        vrai(vueLiee(variantes.args[1], 'static_text', 'etapeTexte'), nom .. " : la carte de l'étape dans Aperçu")
        vrai(vueLiee(variantes.args[3], 'static_text', 'notePoseeTitre'), nom .. ' : la carte Note')
        vrai(vueLiee(variantes.args[3], 'static_text', 'nt1'), nom .. ' : la grille des critères dans la carte Note')
        vrai(vueLiee(variantes.args[2], 'static_text', 'propositionTexte'), nom .. ' : la proposition au milieu')
        -- Chaque vue simple d'un onglet est masquée quand un autre onglet est choisi ; pas de
        -- boîte de groupe dans un onglet (son cadre et son titre resteraient montrés), ni de
        -- vue défilante ou de tab_view (leur cadre aussi).
        for i, onglet in ipairs(D.onglets) do
            p.onglet = onglet.valeur
            for j, variante in ipairs(variantes.args) do
                local quoi = nom .. ' : onglet ' .. D.onglets[j].valeur
                local montrees = 0
                for _, v in ipairs(vues(variante)) do
                    vrai(v.genre ~= 'group_box' and v.genre ~= 'scrolled_view' and v.genre ~= 'tab_view',
                        quoi .. ' : ' .. v.genre .. ' dans un onglet')
                end
                for _, v in ipairs(simples(variante)) do
                    vrai(aCle(v, 'onglet'), quoi .. ' : ' .. v.genre .. ' sans la condition de son onglet')
                    if S.montree(v, p) then
                        vrai(i == j, quoi .. ' : ' .. v.genre .. ' montré dans l\'onglet ' .. onglet.valeur)
                        montrees = montrees + 1
                    end
                end
                vrai(i ~= j or montrees > 0, quoi .. ' : rien de montré')
            end
        end
        -- Un onglet autre que Note (Aperçu, Proposition, Leçon) : l'aperçu montré (commun, hors
        -- des onglets), la carte Note masquée ; la proposition seulement dans Proposition.
        local autre = D.onglets[1].valeur == D.ongletNotation and D.onglets[2].valeur or D.onglets[1].valeur
        p.onglet, p.aProposition = autre, false
        local apercu = vueLiee(args.contents, 'picture', 'imageApercu')
        egal(true, S.montree(apercu, p), nom .. ' : aperçu montré')
        egal(false, S.montree(vueLiee(args.contents, 'static_text', 'notePoseeTitre'), p), nom .. ' : la note posée masquée')
        egal(autre == 'proposition', S.montree(vueLiee(args.contents, 'static_text', 'propositionTexte'), p), nom .. ' : proposition')
        egal(false, S.montree(parInfobulle(args.contents, ACCEPTER_NOTE), p), nom .. ' : Accepter de la note masqué')
        egal(true, S.montree(vueLiee(args.contents, 'static_text', 'infoPhoto'), p), nom .. ' : hors des onglets, toujours montré')
        -- Une variante de couleur dans un onglet : sa couleur et l'onglet, combinés (la première
        -- ligne de la grille des critères, l'état en gras de sa couleur).
        local titres = {}
        for _, v in ipairs(vues(args.contents)) do
            if v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.key == 'nt1' and aCle(v, 'notationCouleur') then
                titres[#titres + 1] = v
            end
        end
        egal(4, #titres, nom .. ' : quatre couleurs de l\'état de la note')
        p.notationCouleur, p.ng1 = 'coche', 'etat'
        for _, v in ipairs(titres) do
            vrai(aCle(v, 'notationCouleur') and aCle(v, 'onglet'), nom .. ' : couleur et onglet dans la même condition')
            egal(false, S.montree(v, p), nom .. ' : couleur masquée hors de l\'onglet Note')
            -- `visible` ne va que de la table vers la vue.
            egal(S.modules.LrBinding.kUnsupportedDirection, v.args.visible.operation({}, {}, false), nom .. ' : sens inverse')
        end
        p.onglet = D.ongletNotation
        local montrees = {}
        for _, v in ipairs(titres) do
            if S.montree(v, p) then
                montrees[#montrees + 1] = v
            end
        end
        egal(1, #montrees, nom .. ' : une seule couleur montrée')
        egal(C.coche, montrees[1].args.emphasis_color, nom .. ' : la couleur de l\'état')
        egal(C.texte, montrees[1].args.text_color, nom .. ' : le reste en couleur du texte')
        egal(true, S.montree(vueLiee(args.contents, 'static_text', 'notePoseeTitre'), p), nom .. ' : la note posée montrée')
        egal(true, S.montree(apercu, p), nom .. " : l'aperçu reste montré avec la carte Note")
    end
    Fenetre.afficher()
    vrai(construite, nom .. ' : fenêtre construite')
    S.pendantFenetre = nil
end)

-- Carte Note ------------------------------------------------------------------------------------

essai('Carte Note : proposition, Accepter, Changer… jusqu\'à 5 ★, à vérifier, « Accepter 5 ★ », rejet ; ni passes ni plafond', function()
    photoActive(4961, 'DSCF4961.RAF', 2, 1)
    registre.poses, registre.decisions = {}, {}
    proposer(4961, { fichier = 'DSCF4961.RAF', note = 3, drapeau = 'aucun',
        criteres = { impact = "Moyen. Le ciel arrête l'œil.", qualites = "Sujet clair.", plancher = "Netteté 41 : nette." },
        plafond = 3, raison = "Tient seule.", passe = 2, le = 1000 })
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        local abonnes = registre.abonnes
        vrai(registre.abonne, 'la fenêtre suit le registre')
        -- La note posée (2 ★, retenue) et ce que Claude propose ; plus de rangée des passes
        -- (correctif 1.3.2) : la passe reste dans l'en-tête de la grille.
        egal(2, p.noteCatalogue)
        egal('Correcte', p.notePoseeTitre)
        egal('2 ★ · drapeau Retenue', p.notePoseeSous)
        egal(nil, p.notePasse, 'plus de passes dans la carte')
        egal(3, p.noteClaude)
        egal('orange', p.notationCouleur)
        egal('Accepter 3 ★', p.titreAccepterNote)
        egal('Laisser à 2 ★', p.titreLaisser)
        -- La grille : l'état et la raison, puis les critères du plus lourd au plus léger, chacun son
        -- étiquette, le verdict en gras ; plus de ligne du plafond (correctif 1.3.2), même mesuré.
        local grille = {}
        for k = 1, Fenetre.T.criteres + 1 do
            if p['ng' .. k] ~= 'vide' then
                grille[#grille + 1] = p['ng' .. k] .. '|' .. p['ne' .. k] .. '|' .. p['nt' .. k]
            end
        end
        egal("etat||<EM>Passe 2 · proposée.</EM> Tient seule.\ncritere|Impact|<EM>Moyen.</EM> Le ciel arrête l'œil.\n"
            .. "critere|Qualités|<EM>Sujet clair.</EM>\ncritere|Plancher technique|Netteté 41 : nette.", table.concat(grille, '\n'))
        egal(nil, p.aPlafond, 'plus de ligne du plafond')
        egal(nil, p.plafondTexte)
        egal(false, p.noteMonte)
        egal(false, p.noteDescend, 'tout tient dans la carte')
        vrai(p.peutAccepterNote and p.peutChangerNote, 'boutons actifs')
        -- Claude travaille : ni Accepter ni Changer (les écritures de la fenêtre échappent à la file
        -- du connecteur).
        Moteur.travaille = true
        Fenetre.rafraichir()
        vrai(not p.peutAccepterNote and not p.peutChangerNote, 'désactivés pendant que Claude travaille')
        Moteur.travaille = false
        Fenetre.rafraichir()
        -- Accepter (le calque de son bouton bleu) : la proposition telle quelle, écrite dans une
        -- tâche (le registre et le catalogue ne se lisent pas dans le clic), une écriture à la fois.
        local avant = #S.taches
        local poserVraiment, pendant = Notation.poser, nil
        Notation.poser = function(liste)
            pendant = { accepter = p.peutAccepterNote, changer = p.peutChangerNote }
            return poserVraiment(liste)
        end
        local accepter = parInfobulle(args.contents, ACCEPTER_NOTE)
        egal('static_text', accepter.genre, 'un calque')
        accepter.args.mouse_down()
        egal(avant + 2, #S.taches, "l'écriture dans une tâche (et l'image enfoncée 0,15 s)")
        egal(0, #registre.poses, 'rien posé dans le clic')
        S.taches[avant + 2]()
        Notation.poser = poserVraiment
        vrai(pendant and not pendant.accepter and not pendant.changer, 'pas deux écritures à la fois')
        egal(1, #registre.poses)
        egal(1, #registre.poses[1])
        egal(4961, registre.poses[1][1].photo)
        vrai(registre.poses[1][1].note == nil and registre.poses[1][1].drapeau == nil, 'sans note ni drapeau : la proposition telle quelle')
        egal(true, Fenetre.aRafraichirNotation, 'la carte se relit')
        Fenetre.rafraichirNotation()
        egal('coche', p.notationCouleur)
        egal('<EM>Passe 2 · acceptée.</EM> Tient seule.', p.nt1)
        egal(false, p.peutAccepterNote, 'déjà acceptée')
        -- Accepter inactif : son calque ne fait rien.
        avant = #S.taches
        accepter.args.mouse_down()
        egal(avant, #S.taches, 'inactif : rien')
        -- Changer… : Dany peut poser 5 ★ (fenêtre modale, depuis une tâche).
        local presenter = S.modules.LrDialogs.presentModalDialog
        local vue
        S.modules.LrDialogs.presentModalDialog = function(d)
            local q = d.contents.args.bind_to_object
            vue = { note = q.note, drapeau = q.drapeau }
            q.note = 5
            return 'ok'
        end
        bouton(args.contents, p, 'Changer…', 'peutChangerNote').args.action()
        S.taches[#S.taches]()
        S.modules.LrDialogs.presentModalDialog = presenter
        egal(3, vue.note, 'la note proposée d\'abord')
        egal('inchange', vue.drapeau, 'le drapeau reste tel quel')
        egal(2, #registre.poses)
        egal(5, registre.poses[2][1].note)
        egal(nil, registre.poses[2][1].drapeau)
        Fenetre.rafraichirNotation()
        egal('<EM>Passe 2 · changée : 5 ★.</EM> Tient seule.', p.nt1)
        -- Une nouvelle proposition de Claude, comme toutes depuis la 1.1.1 : à vérifier.
        proposer(4961, { note = 4, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Peut-être 4.', le = 2000, etat = 'a_verifier' })
        Fenetre.rafraichirNotation()
        egal(2, #registre.poses, 'rien de posé')
        egal('rouge', p.notationCouleur)
        egal('<EM>À vérifier.</EM> Peut-être 4.', p.nt1, 'sans passe connue')
        egal(true, p.peutAccepterNote, 'une note à vérifier s\'accepte')
        egal('Accepter 4 ★', p.titreAccepterNote)
        -- 5 ★ de Claude, à la passe 4 (correctif 1.3.2, demandé par Dany) : « Accepter 5 ★ », qui
        -- pose la proposition telle quelle.
        proposer(4961, { note = 5, drapeau = 'aucun', criteres = { impact = 'Exceptionnel.' }, raison = 'Parmi vos meilleures.', passe = 4,
            le = 2500, etat = 'a_verifier' })
        Fenetre.rafraichirNotation()
        egal(5, p.noteClaude)
        egal('Accepter 5 ★', p.titreAccepterNote)
        egal(true, p.peutAccepterNote, '« Accepter 5 ★ » offert')
        egal('<EM>Passe 4 · à vérifier.</EM> Parmi vos meilleures.', p.nt1)
        local avantCinq = #S.taches
        accepter.args.mouse_down()
        S.taches[avantCinq + 2]()
        egal(3, #registre.poses, 'la proposition de 5 ★ posée')
        vrai(registre.poses[3][1].note == nil and registre.poses[3][1].drapeau == nil, 'telle quelle')
        egal('', p.message or '', 'aucun refus au bandeau')
        -- Un rejet proposé.
        proposer(4961, { drapeau = 'rejetee', criteres = { plancher = 'Floue : netteté 9.' }, plafond = 0, raison = 'Mise au point manquée.', le = 3000 })
        Fenetre.rafraichirNotation()
        egal('rejet', p.noteClaude)
        egal('Accepter le rejet', p.titreAccepterNote)
        egal(nil, p.plafondTexte, 'le plafond ne se montre plus')
        -- Une autre photo, sans proposition : l'aide, Changer… seulement.
        photoActive(4970, 'DSCF4970.RAF', 0, 0)
        Fenetre.majPhoto()
        egal('Pas encore jugée', p.notePoseeTitre)
        egal('0 ★ dans le catalogue', p.notePoseeSous)
        egal('aucune', p.noteClaude)
        local aide = {}
        for k = 1, Fenetre.T.criteres + 1 do
            if p['ng' .. k] == 'plein' then
                aide[#aide + 1] = p['nt' .. k]
            else
                egal('vide', p['ng' .. k], 'ligne ' .. k)
            end
        end
        egal(Fenetre.AIDE_NOTATION, table.concat(aide, ' '), "l'aide, coupée en lignes pleine largeur")
        vrai(not p.peutAccepterNote and p.peutChangerNote)
        egal('Accepter', p.titreAccepterNote)
        egal('Laisser à 0 ★', p.titreLaisser)
        egal(abonnes, registre.abonnes, 'abonnée une fois')
    end
    Fenetre.afficher()
    egal(nil, registre.abonne, 'désabonnée à la fermeture')
    S.pendantFenetre = nil
end)

essai('Cartes : ▲ ▼ font défiler le texte de la note et de la proposition, page par page', function()
    local Fil = require 'Fil'
    prefs.disposition = 'conversation'
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    local vu = false
    S.pendantFenetre = function(args)
        vu = true
        local p, T = Fenetre.p, Fenetre.T
        -- Trois pages de la carte (T.propLignes lignes chacune).
        local lignes, total = {}, 3 * T.propLignes
        for i = 1, total do
            lignes[i] = 'Ligne ' .. i
        end
        local long = table.concat(lignes, '\n')
        -- Première page : T.propLignes lignes, ▲ inactif, ▼ actif.
        Fenetre.montrerPage('proposition', long)
        local page = {}
        for l in (p.propositionTexte .. '\n'):gmatch('([^\n]*)\n') do
            page[#page + 1] = l
        end
        egal(T.propLignes, #page, 'une page pleine')
        egal('Ligne 1', page[1])
        egal(false, p.propositionMonte)
        egal(true, p.propositionDescend)
        -- ▼ (le bouton de la carte) : une page plus bas, la dernière ligne vue gardée en tête.
        local descendre = bouton(args.contents, p, '▼', 'propositionDescend')
        egal('mini', descendre.args.size)
        descendre.args.action(descendre)
        egal('Ligne ' .. T.propLignes, p.propositionTexte:match('^[^\n]*'))
        egal(true, p.propositionMonte)
        -- Jusqu'au bout : la dernière page finit sur la dernière ligne, ▼ inactif.
        for _ = 1, 10 do
            Fenetre.defilerTexte('proposition', 1)
        end
        egal('Ligne ' .. total, p.propositionTexte:match('[^\n]*$'))
        egal(false, p.propositionDescend)
        local monter = bouton(args.contents, p, '▲', 'propositionMonte')
        monter.args.action(monter)
        egal(true, p.propositionDescend)
        -- Le même texte relu garde sa page ; un autre revient à la première.
        local avant = p.propositionTexte
        Fenetre.montrerPage('proposition', long)
        egal(avant, p.propositionTexte, 'page gardée au rafraîchissement')
        Fenetre.montrerPage('proposition', long .. '\nLigne ' .. (total + 1))
        egal('Ligne 1', p.propositionTexte:match('^[^\n]*'), 'un autre texte : première page')
        -- Une balise venue de Claude ne passe pas dans la proposition (sans emphasis_font, Lightroom
        -- ne la montrerait pas, constaté D4).
        Fenetre.montrerPage('proposition', 'Un <EM>ciel</EM> plus dense.')
        egal('Un ciel plus dense.', p.propositionTexte)
        -- La carte Note est une grille : un long paragraphe s'y coupe en lignes pleine largeur, à la
        -- largeur de l'intérieur de la carte, en 12 points.
        -- (Assez long pour deux pages pleines à toute largeur de carte : la dernière page finit sur la
        -- dernière ligne.)
        Fenetre.montrerPage('note', string.rep('Le ciel orageux tient la photo. ', 8 * (T.criteres + 1)))
        for k = 1, T.criteres + 1 do
            egal('plein', p['ng' .. k], 'ligne ' .. k)
            vrai(Fil.largeur(p['nt' .. k], 'texte12') <= T.largeurNote - Fil.MARGE, 'ligne trop large : ' .. p['nt' .. k])
        end
        egal(T.carte, T.largeurNote)
        egal(true, p.noteDescend, 'le paragraphe dépasse la carte')
        egal(false, p.noteMonte)
        local derniere = p['nt' .. (T.criteres + 1)]
        Fenetre.defilerTexte('note', 1)
        egal(true, p.noteMonte)
        egal(derniere, p.nt1, 'une page plus bas, la dernière ligne vue en tête')
        -- Une ligne ne commence jamais par une ponctuation haute (« ; mais » vu sur la carte Note),
        -- et les espaces restent ordinaires.
        local phrase = "Qualités : Sommet de l'action, espace devant l'auto ; mais lumière plate et terne ! « Auto » petite ?"
        for largeur = 90, 400, 7 do
            for _, l in ipairs(Fil.couper(phrase, largeur, 'texte12')) do
                vrai(not l:find('^[;:!?]') and not l:find('^»') and not l:find('«$'), largeur .. ' : « ' .. l .. ' »')
                vrai(not l:find('\194\160', 1, true), 'espace insécable rendue')
            end
        end
        -- Un texte court tient : ni ▲ ni ▼, les autres lignes vides.
        Fenetre.montrerPage('note', 'Court.')
        egal('Court.', p.nt1)
        egal('plein', p.ng1)
        egal('vide', p.ng2)
        egal('', p.nt2)
        egal(false, p.noteMonte)
        egal(false, p.noteDescend)
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    S.pendantFenetre = nil
end)

-- Structure de la 1.3 ------------------------------------------------------------------------------
-- Posée une fois (lot 11) : la carte Pourquoi ?, la seconde rangée de la carte Proposition, les
-- crochets de l'aperçu et des onglets, la répartition des clics sur le fil, la vue du fil et
-- l'agrandissement à deux images. Les lots suivants remplissent les crochets ; ici, ils sont vides
-- (ou, pour Pourquoi ?, rempli au lot 12 et éprouvé par essais-pourquoi.lua : sans étape dans le
-- fil, sa carte montre l'aide et ses actions ne font rien) et la fenêtre se comporte comme avant.
-- Les crochets de Pourquoi ?, que des essais remplacent : remis à la fin de chacun.
local crochetsPourquoi = { apercu = Fenetre.apercuOnglet.apercu, sur = Fenetre.surOnglet.apercu }

-- Une conversation neuve avec un aperçu de Claude (view_photo) : sa ligne d'outil et sa ligne
-- d'image dans le fil (indices dans la fenêtre de lecture).
local function avecApercu(c, id)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__view_photo',
        entree = { size = 1568 } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id, textes = { '{}' }, images = { { donnees = 'x' } },
        erreur = false } } }, nil, function() return id .. '.jpg' end)
    Fenetre.rafraichir()
    local ligneImage, ligneOutil
    for i = 1, Fenetre.T.lignes do
        local l = Fenetre.lignes[Fenetre.premiere + i - 1]
        if l and l.image then
            ligneImage = ligneImage or i
        elseif l and l.element and c.elements[l.element].genre == 'outil' then
            ligneOutil = ligneOutil or i
        end
    end
    vrai(ligneImage and ligneOutil, "lignes d'outil et d'image dans le fil")
    return ligneImage, ligneOutil
end

essai('Pourquoi ? et Je le fais : propriétés posées avant l\'ouverture, carte sans étape (l\'aide), actions sans effet sans étape', function()
    -- Sans photo active, ni proposition, ni exercice : Je le fais reste inactif (lot 14 : une photo
    -- active suffit à l'activer), et son action ne demande rien à Claude.
    S.photoActive, S.selection = nil, {}
    Moteur.nouvelle()
    local vu = false
    S.pendantFenetre = function(args)
        vu = true
        local p, T = Fenetre.p, Fenetre.T
        for cle, valeur in pairs({ etapeTitre = Fenetre.TITRE_ETAPE, etapeSousTitre = '', etapePrecedente = false, etapeSuivante = false,
            etapeAImages = false, etapeADetail = false, titreBascule = "Voir l'avant", titreJeLeFais = "Je le fais", peutJeLeFais = false,
            exerciceEtat = '', etapeMonte = false, etapeDescend = false }) do
            egal(valeur, p[cle], cle .. ' avant l\'ouverture')
        end
        -- Sans étape dans le fil, la carte de l'étape montre l'aide (lot 12), coupée à sa largeur.
        egal(Fenetre.AIDE_ETAPE, (p.etapeTexte:gsub('\n', ' ')), "l'aide de la carte de l'étape")
        vrai(Fenetre.AIDE_ETAPE:find('« Pourquoi ? »', 1, true), "l'aide dit le bouton Pourquoi ? du fil")
        -- Fenêtre B (lot B5, provisoire jusqu'au lot 18) : les cartes sur leurs images, à la largeur
        -- de leur intérieur, aux lignes de Dispositions.TAILLES (essais-fenetre-b.lua vérifie qu'elles
        -- remplissent leur carte).
        egal('Pourquoi ?', Fenetre.TITRE_ETAPE, 'sans étape, le titre de la carte')
        egal(Dispositions.TAILLES.propLignes, T.propLignes, 'la proposition (fenêtre B)')
        egal(Dispositions.TAILLES.etapeLignes, T.etapeLignes, "texte de la carte de l'étape")
        egal(T.carte, T.largeurEtape)
        egal(T.carte, T.largeurProposition)
        -- Les actions des boutons : sans effet pour l'instant (un lot suivant les remplit), sans
        -- erreur ni demande envoyée, et l'onglet ne change pas.
        p.onglet = 'apercu'
        p.saisie = 'Texte validé par le clic'
        local taches, dialogues, messages = #S.taches, #S.dialogues, #S.messages
        bouton(args.contents, p, '◀', 'etapePrecedente').args.action()
        egal(nil, Fenetre.envoiAuto, 'un clic de la carte annule l\'envoi automatique')
        bouton(args.contents, p, '▶', 'etapeSuivante').args.action()
        bouton(args.contents, p, "Voir l'avant", 'etapeAImages').args.action()
        bouton(args.contents, p, 'Détail…', 'etapeADetail').args.action()
        bouton(args.contents, p, 'Je le fais', 'peutJeLeFais').args.action()
        egal(taches + 2, #S.taches, 'Détail… et Je le fais passent par une tâche')
        S.taches[#S.taches]()
        S.taches[#S.taches - 1]()
        egal(dialogues, #S.dialogues, 'aucune fenêtre ouverte')
        egal(messages, #S.messages, 'aucun message')
        egal(false, Moteur.travaille, 'rien envoyé à Claude')
        egal(0, #Moteur.courante.elements, 'aucune demande')
        egal('apercu', p.onglet)
        egal(Fenetre.AIDE_ETAPE, (p.etapeTexte:gsub('\n', ' ')), "toujours l'aide")
        p.saisie, p.onglet, p.message = '', 'notation', ''
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    S.pendantFenetre = nil
end)

essai('Carte Pourquoi ? : ▲ ▼ font défiler son texte, page par page, comme les deux autres cartes', function()
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    local vu = false
    S.pendantFenetre = function(args)
        vu = true
        local p, T = Fenetre.p, Fenetre.T
        -- Trois pages de la carte (T.etapeLignes lignes chacune).
        local lignes = {}
        for i = 1, 3 * T.etapeLignes do
            lignes[i] = 'Raison ' .. i
        end
        Fenetre.montrerPage('etape', table.concat(lignes, '\n'))
        local page = {}
        for l in (p.etapeTexte .. '\n'):gmatch('([^\n]*)\n') do
            page[#page + 1] = l
        end
        egal(T.etapeLignes, #page, 'une page pleine')
        egal(false, p.etapeMonte)
        egal(true, p.etapeDescend)
        local descendre = bouton(args.contents, p, '▼', 'etapeDescend')
        egal('mini', descendre.args.size)
        descendre.args.action()
        egal('Raison ' .. T.etapeLignes, p.etapeTexte:match('^[^\n]*'))
        egal(true, p.etapeMonte)
        bouton(args.contents, p, '▲', 'etapeMonte').args.action()
        egal('Raison 1', p.etapeTexte:match('^[^\n]*'))
        -- Un long paragraphe est coupé à la largeur de la carte.
        Fenetre.montrerPage('etape', string.rep('La balance tirait vers le bleu. ', 30))
        for l in (p.etapeTexte .. '\n'):gmatch('([^\n]*)\n') do
            vrai(require('Fil').largeur(l, 'texte12') <= T.largeurEtape - require('Fil').MARGE, 'ligne trop large : ' .. l)
        end
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    S.pendantFenetre = nil
end)

essai("Aperçu de l'onglet : son crochet d'abord, nil pour l'aperçu d'avant ; une image cliquée dans le fil reste prioritaire", function()
    prefs.nouvelleParPhoto = false
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    local appels, rendre, vu = 0, true, false
    S.pendantFenetre = function()
        vu = true
        local p = Fenetre.p
        local c = Moteur.courante
        local ligneImage, ligneOutil = avecApercu(c, 'crochet-1')
        local defaut = p.legendeApercu
        vrai(defaut:find('1 sur 1', 1, true), defaut)
        -- Sans crochet, l'onglet Aperçu garde l'aperçu d'avant.
        p.onglet = 'apercu'
        egal(defaut, p.legendeApercu, "sans crochet : l'aperçu d'avant")
        p.onglet = 'notation'
        -- Le crochet de l'onglet : demandé d'abord, au changement d'onglet et à chaque
        -- rafraîchissement, avec la table de la fenêtre, ses dimensions et la conversation.
        Fenetre.apercuOnglet.apercu = function(q, T, conversation)
            appels = appels + 1
            vrai(q == p and T == Fenetre.T and conversation == c, 'arguments du crochet')
            if not rendre then
                return nil
            end
            q.legendeApercu = 'Étape 1 sur 1 · après'
            return true
        end
        p.onglet = 'apercu'
        egal(1, appels, "demandé au changement d'onglet")
        egal('Étape 1 sur 1 · après', p.legendeApercu, "l'aperçu de l'onglet")
        Fenetre.rafraichir()
        egal(2, appels, 'demandé à chaque rafraîchissement')
        egal('Étape 1 sur 1 · après', p.legendeApercu)
        -- nil : l'aperçu d'avant.
        rendre = false
        Fenetre.rafraichirApercu()
        egal(defaut, p.legendeApercu, "nil : l'aperçu d'avant")
        rendre = true
        Fenetre.rafraichirApercu()
        -- Un crochet en erreur : journalisé, l'aperçu d'avant.
        Fenetre.apercuOnglet.proposition = function() error('crochet cassé') end
        p.onglet = 'proposition'
        egal(defaut, p.legendeApercu, "crochet en erreur : l'aperçu d'avant")
        Fenetre.apercuOnglet.proposition = nil
        p.onglet = 'apercu'
        -- Un clic sur une ligne d'image : elle se montre, même dans l'onglet Aperçu, et le
        -- reste aux rafraîchissements ; le détail d'un outil ne la remplace pas.
        Fenetre.cliquerLigne(ligneImage)
        egal(defaut, p.legendeApercu, "l'image cliquée")
        local avant = appels
        Fenetre.rafraichir()
        Fenetre.cliquerLigne(ligneOutil)
        Fenetre.rafraichirApercu()
        egal(avant, appels, "crochet pas demandé après un clic sur une image")
        egal(defaut, p.legendeApercu, "l'image cliquée reste")
        -- Un autre onglet rend l'aperçu à l'onglet.
        p.onglet = 'notation'
        p.onglet = 'apercu'
        egal('Étape 1 sur 1 · après', p.legendeApercu, "un autre onglet : l'aperçu de l'onglet")
        -- Une image nouvelle aussi.
        Fenetre.cliquerLigne(ligneImage)
        egal(defaut, p.legendeApercu)
        avecApercu(c, 'crochet-2')
        egal('Étape 1 sur 1 · après', p.legendeApercu, "une image nouvelle : l'aperçu de l'onglet")
        -- Et un clic sur une étape (Fenetre.estEtape : Conversation.estEtape depuis le lot 12).
        Fenetre.cliquerLigne(ligneImage)
        vrai(p.legendeApercu:find('sur 2', 1, true), p.legendeApercu)
        local estEtape, etape = Fenetre.estEtape, Fenetre.clics.etape
        Fenetre.estEtape = function(e) return e.genre == 'outil' end
        Fenetre.clics.etape = function() Fenetre.rafraichirApercu() end
        Fenetre.cliquerLigne(ligneOutil)
        Fenetre.estEtape, Fenetre.clics.etape = estEtape, etape
        egal('Étape 1 sur 1 · après', p.legendeApercu, "un clic sur une étape : l'aperçu de l'onglet")
        -- Dans l'onglet Note, sans crochet : l'aperçu d'avant.
        p.onglet = 'notation'
        vrai(p.legendeApercu:find('sur 2', 1, true), p.legendeApercu)
        Fenetre.apercuOnglet.apercu = nil
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    Fenetre.apercuOnglet.apercu, Fenetre.apercuOnglet.proposition = crochetsPourquoi.apercu, nil
    prefs.nouvelleParPhoto = true
    S.pendantFenetre = nil
end)

essai("Aperçu de l'onglet : une image cliquée cède aussi la place à une autre conversation, d'où qu'elle vienne, et à une autre photo active", function()
    prefs.nouvelleParPhoto = false
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    local vu = false
    S.pendantFenetre = function()
        vu = true
        local p = Fenetre.p
        Fenetre.apercuOnglet.apercu = function(q)
            q.legendeApercu = "Aperçu de l'onglet"
            return true
        end
        p.onglet = 'apercu'
        egal("Aperçu de l'onglet", p.legendeApercu)
        local ligneImage = avecApercu(Moteur.courante, 'autre-1')
        Fenetre.cliquerLigne(ligneImage)
        vrai(p.legendeApercu:find('1 sur 1', 1, true), p.legendeApercu)
        -- Une autre conversation sans passer par la liste ni par Nouvelle (conversation supprimée,
        -- demande partie d'une autre page) : l'image cliquée n'est plus de celle-ci.
        Moteur.nouvelle()
        Fenetre.rafraichir()
        egal("Aperçu de l'onglet", p.legendeApercu, "une autre conversation : l'aperçu de l'onglet")
        -- Une autre photo active (Autre photo décochée : même conversation) : l'aperçu ne montre
        -- plus l'image cliquée.
        ligneImage = avecApercu(Moteur.courante, 'autre-2')
        Fenetre.cliquerLigne(ligneImage)
        vrai(p.legendeApercu:find('1 sur 1', 1, true), p.legendeApercu)
        photoActive(4962, 'DSCF4962.RAF', 0, 0)
        Fenetre.majPhoto()
        egal("Aperçu de l'onglet", p.legendeApercu, "une autre photo active : l'aperçu de l'onglet")
        Fenetre.apercuOnglet.apercu = nil
        p.onglet = 'notation'
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    Fenetre.apercuOnglet.apercu = crochetsPourquoi.apercu
    prefs.nouvelleParPhoto = true
    S.pendantFenetre = nil
end)

essai("Clic sur un onglet : son crochet suit un vrai clic, jamais une bascule de la fenêtre", function()
    prefs.nouvelleParPhoto = false
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    local recus, vu = {}, false
    S.pendantFenetre = function()
        vu = true
        local p = Fenetre.p
        Fenetre.surOnglet.proposition = function(valeur) recus[#recus + 1] = valeur end
        Fenetre.surOnglet.apercu = function(valeur) recus[#recus + 1] = valeur end
        -- Un vrai clic : le crochet, et la demande validée par le clic ne part pas.
        p.saisie = 'Texte validé par le clic'
        vrai(Fenetre.envoiAuto, 'envoi prévu')
        p.onglet = 'proposition'
        egal('proposition', table.concat(recus, ' '))
        egal(nil, Fenetre.envoiAuto, "le clic d'un onglet annule l'envoi automatique")
        p.saisie = ''
        p.onglet = 'apercu'
        egal('proposition apercu', table.concat(recus, ' '))
        -- Une bascule de la fenêtre (une proposition qui arrive) : pas de crochet.
        p.onglet = 'notation'
        local c = Moteur.courante
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'bascule-1', nom = 'mcp__developpeur__preview_settings',
            entree = { reason = 'Balance', settings = { Exposure2012 = 0.35 } } } } })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'la proposition se montre')
        egal('proposition apercu', table.concat(recus, ' '), 'pas de crochet pour une bascule')
        Fenetre.choisirOnglet('apercu')
        egal('apercu', p.onglet)
        egal('proposition apercu', table.concat(recus, ' '), 'pas de crochet pour Fenetre.choisirOnglet')
        -- Un crochet en erreur n'empêche pas l'onglet de changer.
        Fenetre.surOnglet.notation = function() error('crochet cassé') end
        p.onglet = 'notation'
        egal('notation', p.onglet)
        -- Hors d'une tâche (l'observateur d'un clic), le crochet passe par pcall, pas par
        -- LrTasks.pcall (réservé au code qui peut attendre).
        local taches = S.modules.LrTasks
        local peutAttendre, pcallTache = taches.canYield, taches.pcall
        taches.canYield = function() return false end
        taches.pcall = function() error("LrTasks.pcall hors d'une tâche", 0) end
        p.onglet = 'proposition'
        egal('proposition apercu proposition', table.concat(recus, ' '), "crochet appelé hors d'une tâche")
        -- Sans LrTasks.canYield (s'il manquait au SDK), pcall aussi : le crochet est appelé.
        taches.canYield = nil
        p.onglet = 'notation'
        p.onglet = 'proposition'
        taches.canYield, taches.pcall = peutAttendre, pcallTache
        egal('proposition apercu proposition proposition', table.concat(recus, ' '), 'crochet appelé sans LrTasks.canYield')
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    Fenetre.surOnglet.proposition, Fenetre.surOnglet.apercu, Fenetre.surOnglet.notation = nil, crochetsPourquoi.sur, nil
    prefs.nouvelleParPhoto = true
    S.pendantFenetre = nil
end)

essai('Clic sur une ligne du fil : image, ligne du carnet, leçon, étape, sinon détail de l\'outil (ordre fixé)', function()
    local outil, lecon, claude = { genre = 'outil', texte = 'apply_settings · passe 1', detail = '{}' }, { genre = 'lecon' }, { genre = 'claude' }
    local sorte = Fenetre.sorteDeClic
    -- Un outil sans étape (ni outil d'étape ni réponse qui en porte) : sa ligne reste un outil.
    egal(false, Fenetre.estEtape(outil))
    egal('image', sorte({ image = 'a.jpg', defaut = 'horizon', action = 'demander' }, lecon))
    egal('carnet', sorte({ defaut = 'horizon' }, lecon))
    egal('carnet', sorte({ action = 'demander' }, outil))
    egal('lecon', sorte({}, lecon))
    egal('outil', sorte({}, outil))
    egal(nil, sorte({}, claude))
    egal(nil, sorte({}, nil))
    -- Une étape (Fenetre.estEtape, Conversation.estEtape) passe avant le détail de l'outil,
    -- après une image, une ligne du carnet et une leçon.
    local estEtape = Fenetre.estEtape
    Fenetre.estEtape = function() return true end
    egal('etape', sorte({}, outil))
    egal('lecon', sorte({}, lecon))
    egal('carnet', sorte({ defaut = 'bruit' }, outil))
    egal('image', sorte({ image = 'b.jpg' }, outil))
    Fenetre.estEtape = estEtape
    -- Fenetre.cliquerLigne appelle Fenetre.clics[sorte](ligne, élément).
    for _, nom in ipairs({ 'image', 'carnet', 'lecon', 'etape', 'outil' }) do
        egal('function', type(Fenetre.clics[nom]), 'Fenetre.clics.' .. nom)
    end
    local courante, lignes, premiere = Moteur.courante, Fenetre.lignes, Fenetre.premiere
    local clics, recus = {}, {}
    for nom, fn in pairs(Fenetre.clics) do
        clics[nom] = fn
        Fenetre.clics[nom] = function(l, e) recus[#recus + 1] = nom .. ':' .. tostring(l.n) .. ':' .. tostring(e and e.genre) end
    end
    Moteur.courante = { elements = { outil, lecon, claude } }
    Fenetre.lignes, Fenetre.premiere = {
        { n = 1, image = 'a.jpg', element = 1 },
        { n = 2, defaut = 'horizon' },
        { n = 3, element = 2 },
        { n = 4, element = 1 },
        { n = 5, element = 3 },
    }, 1
    for i = 1, 6 do
        Fenetre.cliquerLigne(i)
    end
    egal('image:1:outil carnet:2:nil lecon:3:lecon outil:4:outil', table.concat(recus, ' '))
    for nom, fn in pairs(clics) do
        Fenetre.clics[nom] = fn
    end
    -- Par défaut, hors de la page du carnet : le carnet et la leçon ne font rien, ni l'étape d'un
    -- élément qui n'en est pas une (essais-pourquoi.lua éprouve une vraie étape) ; un outil ouvre
    -- son détail, dans une tâche.
    local taches, dialogues = #S.taches, #S.dialogues
    Fenetre.cliquerLigne(2)
    Fenetre.cliquerLigne(3)
    Fenetre.clics.etape({ n = 4, element = 1 }, outil)
    egal(taches, #S.taches, 'rien sans étape')
    Fenetre.cliquerLigne(4)
    egal(taches + 1, #S.taches, "le détail de l'outil dans une tâche")
    S.taches[#S.taches]()
    egal(dialogues + 1, #S.dialogues)
    egal('Claude · apply_settings · passe 1', S.dialogues[#S.dialogues].title)
    Moteur.courante, Fenetre.lignes, Fenetre.premiere = courante, lignes, premiere
end)

essai('Vue du fil : la conversation à l\'ouverture ; Claude qui travaille y ramène', function()
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    Fenetre.vue = 'carnet'
    local vu = false
    S.pendantFenetre = function()
        vu = true
        egal('conversation', Fenetre.vue, "la conversation à l'ouverture")
        egal(false, Fenetre.revenirAuFil(), 'déjà la conversation')
        -- Le retour relit le fil depuis la fin sans changer la conversation montrée : ce qui la
        -- suit (l'étape choisie de l'onglet Aperçu) n'est pas remis.
        Fenetre.rafraichir()
        local montree = Fenetre.conversationAffichee
        vrai(montree, 'une conversation montrée')
        Fenetre.vue, Fenetre.defilement, Fenetre.total = 'carnet', 3, 99
        Fenetre.cache.marque = true
        egal(true, Fenetre.revenirAuFil(), 'retour au fil')
        egal(montree, Fenetre.conversationAffichee, 'la conversation montrée reste')
        egal(0, Fenetre.defilement)
        egal(nil, Fenetre.total)
        egal(nil, Fenetre.cache.marque)
        -- Une autre page (le carnet, lot 16) reste montrée tant que Claude ne travaille pas.
        Fenetre.vue = 'carnet'
        Fenetre.rafraichir()
        egal('carnet', Fenetre.vue)
        -- Claude travaille (Accepter, Je le fais, J'ai fini… envoyés sans passer par le champ) : le
        -- fil revient, relu depuis la fin.
        Fenetre.defilement = 5
        Fenetre.cache.marque = true
        Moteur.travaille = true
        Fenetre.rafraichir()
        Moteur.travaille = false
        egal('conversation', Fenetre.vue, 'Claude travaille : retour au fil')
        egal(nil, Fenetre.cache.marque, 'le fil relu')
        egal(0, Fenetre.defilement, 'depuis la fin')
        egal(Moteur.courante, Fenetre.conversationAffichee)
        Fenetre.vue = 'carnet'
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    Fenetre.vue = 'conversation'
    S.pendantFenetre = nil
end)

essai('Agrandir à deux images : avant et après côte à côte, titres au-dessus, légende dessous', function()
    local grande, demandes = Images.grande, {}
    Images.grande = function(dossier, nom, largeur, hauteur)
        demandes[#demandes + 1] = string.format('%s/%s %dx%d', dossier, nom, largeur, hauteur)
        if nom == 'illisible.jpg' then
            return nil
        end
        return dossier .. '/.vignettes/' .. nom, 540, 360
    end
    local dialogues, messages = #S.dialogues, #S.messages
    local raison = "Pourquoi : la photo tirait vers le bleu ; des blancs neutres.\n\nCe qui a changé\nTempérature : 5 200 → 5 600"
    egal(true, Fenetre.agrandirDeux('Étape 2 sur 4 · passe 1 : balance', { dossier = '/etapes', nom = 'e2-avant.jpg', titre = 'Avant' },
        { dossier = '/etapes', nom = 'e2-apres.jpg', titre = 'Après' }, raison))
    egal('/etapes/e2-avant.jpg 540x700 /etapes/e2-apres.jpg 540x700', table.concat(demandes, ' '), 'chaque image dans 540 × 700')
    egal(dialogues + 1, #S.dialogues)
    local d = S.dialogues[#S.dialogues]
    egal('Claude · Étape 2 sur 4 · passe 1 : balance', d.title)
    egal('Fermer', d.actionVerb)
    local rangee, legende = d.contents.args[1], d.contents.args[2]
    egal('row', rangee.genre)
    local cotes = {}
    for _, colonne in ipairs(rangee.args) do
        local titre, image = colonne.args[1], colonne.args[2]
        cotes[#cotes + 1] = titre.args.title .. ' ' .. image.genre .. ' ' .. image.args.value .. ' ' .. image.args.width .. 'x' .. image.args.height
    end
    egal('Avant picture /etapes/.vignettes/e2-avant.jpg 540x360 | Après picture /etapes/.vignettes/e2-apres.jpg 540x360', table.concat(cotes, ' | '))
    egal('static_text', legende.genre)
    egal(raison, legende.args.title, 'la légende, ses paragraphes gardés')
    egal(1080, legende.args.width, 'à la largeur des deux images')
    egal(4, legende.args.height_in_lines, 'une ligne par ligne de texte')
    -- Une image illisible est dite à sa place ; sans légende, rien dessous.
    egal(true, Fenetre.agrandirDeux('Je le fais', { dossier = '/x', nom = 'claude.jpg', titre = 'Claude' },
        { dossier = '/x', nom = 'illisible.jpg', titre = 'Vous' }))
    d = S.dialogues[#S.dialogues]
    egal(1, #d.contents.args, 'sans légende')
    egal('Vous : image illisible', d.contents.args[1].args[2].args[1].args.title)
    -- Aucune image lisible : un message, pas de fenêtre.
    local avant = #S.dialogues
    egal(false, Fenetre.agrandirDeux('Étape 3', { dossier = '/x', nom = 'illisible.jpg', titre = 'Avant' }, nil, raison))
    egal(avant, #S.dialogues)
    egal(messages + 1, #S.messages)
    egal('Aperçu illisible', S.messages[#S.messages][1])
    Images.grande = grande
end)

essai('Consignes : chaque photo traitée notée d\'abord, à vérifier, avec le carré de la mise au point', function()
    for _, morceau in ipairs({ "note-la d'abord", 'af_point = true', 'view_photo : evaluation', '« à vérifier »', 'apply = true' }) do
        vrai(Consignes.texte:find(morceau, 1, true), 'consignes : ' .. morceau)
    end
end)

essai('Consignes : le résumé d\'une retouche donne les chiffres du bilan, et dit une régression restée (1.2)', function()
    local debut = Consignes.texte:find('\n## Fin d\'une tâche\n', 1, true)
    vrai(debut, 'section Fin d\'une tâche')
    local fin = Consignes.texte:find('\n## ', debut + 1, true) or (#Consignes.texte + 1)
    local section = Consignes.texte:sub(debut, fin - 1)
    for _, morceau in ipairs({ 'chiffres du bilan de view_photo à l\'appui', '« hautes lumières écrêtées : 2,1 → 0,3 % »',
        'une « regression » restée au bilan se dit', 'Après une tâche sur plusieurs photos', 'sous « Claude · … »' }) do
        vrai(section:find(morceau, 1, true), 'fin d\'une tâche : ' .. morceau)
    end
    vrai(not Consignes.texte:find('\\\n', 1, true), 'lignes recollées')
end)

-- Liste des conversations -----------------------------------------------------------------------

essai('Conversations : les anciennes séances de notation ne sont pas dans la liste', function()
    Moteur.charger()
    local conversations, courante = Moteur.conversations, Moteur.courante
    local seance = Conversation.nouvelle()
    seance.genre, seance.titre, seance.titreChoisi = 'notation', 'Séance du lac', true
    Conversation.ajouterDemande(seance, 'Passe 1 : rejeter ou non ?')
    local ordinaire = Conversation.nouvelle()
    Conversation.ajouterDemande(ordinaire, 'Retouche le lac au matin')
    Stockage.enregistrer(seance)
    Stockage.enregistrer(ordinaire)
    -- Relues du disque (Json.decode) : les éléments donnés à Lightroom sont des tables neuves.
    Moteur.conversations = Stockage.charger()
    for _, c in ipairs(Moteur.conversations) do
        if c.id == ordinaire.id then
            Moteur.courante = c
        end
    end
    local function ids(items)
        local t = {}
        for _, item in ipairs(items) do
            t[item.value] = true
        end
        return t
    end
    local liste = Fenetre.elementsListe('')
    S.neuve(liste, 'liste')
    vrai(ids(liste)[ordinaire.id] and not ids(liste)[seance.id], 'liste sans la séance')
    vrai(not ids(Fenetre.elementsListe('lac'))[seance.id], 'recherche sans la séance')
    -- Une séance n'est jamais montrée comme conversation ouverte.
    Moteur.courante = seance
    vrai(not ids(Fenetre.elementsListe(''))[seance.id])
    Moteur.conversations, Moteur.courante = conversations, courante
end)

-- Gestionnaire de modules externes ---------------------------------------------------------------

local PROPRIETES = {}
for nom in ([[bind_to_object tooltip visible enabled font size title value items action width height fill fill_horizontal
    fill_vertical place_horizontal place_vertical margin margin_horizontal margin_vertical margin_left margin_right margin_top
    margin_bottom place spacing width_in_chars height_in_lines width_in_digits truncation selectable alignment text_color
    mouse_down immediate validate placeholder_string wraps allows_multiple_selection value_equal frame_width frame_color
    background_color horizontal_scroller vertical_scroller show_title min max precision checked_value unchecked_value
    string_to_value value_to_string photo]]):gmatch('%S+') do
    PROPRIETES[nom] = true
end

essai('Gestionnaire de modules externes : les sections se construisent, menus Modèle et Effort, cases Autre photo et À l\'ouverture', function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    local sections = PluginInfoProvider.sectionsForTopOfDialog(f, proprietes)
    egal(2, #sections)
    egal('Liaison avec Claude', sections[1].title)
    local section = sections[2]
    egal('Fenêtre Claude', section.title)
    local prefsModule = Chemins.prefs()
    egal(prefsModule, section.bind_to_object, 'la section lit les préférences du module')
    local menu
    local menus, cases = {}, {}
    for _, enfant in ipairs(section) do
        for _, v in ipairs(vues(enfant)) do
            for cle, valeur in pairs(v.args) do
                if type(cle) == 'string' then
                    vrai(PROPRIETES[cle], 'propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                    if type(valeur) == 'table' and valeur.liaison then
                        S.verifierLiaison(valeur, section.bind_to_object, v.genre .. '.' .. cle)
                    end
                end
            end
            if S.BOUTONS[v.genre] then
                vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
            end
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' then
                menus[v.args.value.key] = v
            elseif v.genre == 'checkbox' and type(v.args.value) == 'table' then
                cases[v.args.value.key] = v
            end
        end
    end
    -- Une seule disposition, la Conversation claire, une seule taille : ni menu Disposition ni menu
    -- Taille (demandés par Dany le 20 octobre 2026).
    egal(nil, menus.disposition, 'plus de menu Disposition')
    egal(nil, menus.taille, 'plus de menu Taille (toujours grande)')
    vrai(PluginInfoProvider.diagnostic():find('effort max ; nouvelle conversation par photo', 1, true), 'diagnostic')
    vrai(cases.propositionAOuverture, 'case À l\'ouverture')
    vrai(PluginInfoProvider.diagnostic():find('modèle opus, effort max', 1, true), 'diagnostic : modèle et effort')
    -- Le modèle et l'effort se choisissent ici, plus dans la fenêtre (demandé par Dany le
    -- 20 octobre 2026), comme la nouvelle conversation à chaque autre photo.
    vrai(menus.modele and menus.effort, 'menus Modèle et Effort')
    egal(4, #menus.modele.args.items)
    egal(5, #menus.effort.args.items)
    egal('max', prefsModule.effort, 'effort maximal par défaut')
    vrai(cases.nouvelleParPhoto, 'case Autre photo')
    egal(true, prefsModule.nouvelleParPhoto)
end)

-- Images ----------------------------------------------------------------------------------------

essai('Vignettes : un cadre 3:2 garde toute l\'image, centrée sur le fond', function()
    local dossier = S.home .. '/vignettes-essai'
    Fichiers.creerDossier(dossier)
    S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(dossier .. '/paysage.jpg') .. ' >/dev/null 2>&1')
    S.executer('/usr/bin/sips -s format jpeg -z 90 60 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(dossier .. '/portrait.jpg') .. ' >/dev/null 2>&1')
    local function dimensions(chemin)
        local l, h = Images.dimensions(chemin)
        return tostring(l) .. 'x' .. tostring(h)
    end
    local cadre = Images.vignette(dossier, 'paysage.jpg', 600, 400)
    vrai(cadre, 'cadre du paysage')
    egal('600x400', dimensions(cadre))
    egal('600x400', dimensions(Images.vignette(dossier, 'portrait.jpg', 600, 400)), 'portrait centré dans le cadre')
    local carre = Images.vignette(dossier, 'paysage.jpg', 270)
    egal('270x270', dimensions(carre))
    vrai(carre ~= cadre, 'le carré et le cadre ne se confondent pas')
    egal(cadre, Images.vignette(dossier, 'paysage.jpg', 600, 400), 'faite une fois')
    egal(nil, Images.vignette(dossier, 'absente.jpg', 600, 400))
end)

essai('Image « aucun aperçu » : au cadre 3:2 de l\'aperçu, en 2x, dans le jeu de chaque apparence', function()
    local D = Dispositions.dimensions()
    -- Son nom suit le cadre de l'aperçu (« vide-498x332 ») : un autre cadre, une autre image.
    local nom = 'vide-' .. D.apercu .. 'x' .. D.apercuHauteur .. '.png'
    egal('images/' .. nom, Dispositions.imageVide('claire'))
    egal('images/sombre/' .. nom, Dispositions.imageVide('sombre'))
    egal('images/' .. nom, Dispositions.imageVide('inconnue'), 'une apparence inconnue : la claire')
    for _, apparence in ipairs({ 'claire', 'sombre' }) do
        local chemin = Dispositions.imageVide(apparence)
        local l, h = Images.dimensions(Chemins.ressource(chemin))
        egal(D.pixelsApercu, l, chemin)
        egal(D.pixelsApercuHauteur, h, chemin)
    end
    egal(2 * D.apercu, D.pixelsApercu)
    egal(2 * D.apercuHauteur, D.pixelsApercuHauteur)
    -- La fenêtre prend celle de son apparence.
    local apparence = Fenetre.apparence
    Fenetre.preparerApparence('sombre')
    vrai(Fenetre.imageVide():find('/images/sombre/' .. nom, 1, true), Fenetre.imageVide())
    Fenetre.preparerApparence(apparence)
    -- Plus d'image carrée (Conversation claire de la 1.2), ni pour l'Atelier et le Panneau, ni à la
    -- racine du module, ni celle du cadre de 330 × 220 de la fenêtre B à 1 280 × 800 (lot B3), dans
    -- l'un ou l'autre jeu.
    for _, ancienne in ipairs({ 'vide-320.png', 'vide-200.png', 'vide-720x480.png', 'vide-330x220.png', 'images/vide-330x220.png',
        'images/sombre/vide-330x220.png' }) do
        vrai(not Fichiers.existe(Chemins.ressource(ancienne)), 'image retirée : ' .. ancienne)
    end
end)

-- Fin -------------------------------------------------------------------------------------------

for nom, fn in pairs(contratNotation) do
    Notation[nom] = fn
end
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
