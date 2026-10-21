-- essais-dispositions.lua : la fenêtre Claude dans ses trois dispositions (Atelier, Conversation
-- claire, Panneau) hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : réouverture
-- dans une autre disposition (demande tapée rendue sans partir, une seule boucle), onglets, carte
-- Note, bouton Noter, nouvelle conversation par photo, anciennes conversations de séance absentes
-- de la liste, Gestionnaire de modules externes (modèle, effort, disposition), vignettes dans un
-- cadre 3:2, images « aucun aperçu ». Le registre des notes (Notation) garde ici les appels reçus :
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
        if v.genre == 'push_button' and t == titre
            and (not cleActif or (type(v.args.enabled) == 'table' and v.args.enabled.key == cleActif)) then
            return v
        end
    end
    error('bouton introuvable : ' .. tostring(titre), 2)
end

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

essai('Disposition changée dans le Gestionnaire : la fenêtre se rouvre, la demande tapée revient sans partir, une seule boucle', function()
    prefs.disposition = 'conversation'
    photoActive(53636309, 'DSCF4961.RAF', 0, 0)
    local ouvertures, envoiPrevu, fermetures = {}, nil, nil
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        ouvertures[#ouvertures + 1] = { cadre = args.save_frame, disposition = Fenetre.disposition, generation = Fenetre.generation }
        if #ouvertures == 1 then
            -- Dany a tapé une demande et Retour l'a validée : elle partira dans 0,3 s…
            local avant = #S.taches
            p.saisie = 'Assombris un peu moins le ciel'
            egal(avant + 1, #S.taches, 'envoi automatique prévu')
            envoiPrevu = S.taches[#S.taches]
            -- … mais il choisit le Panneau dans le Gestionnaire de modules externes : la boucle de
            -- la fenêtre le voit (toutes les 2 s) et la ferme, pour la rouvrir.
            prefs.disposition = 'panneau'
            fermetures = S.fermetures or 0
            Fenetre.periodique()
            egal(nil, Fenetre.envoiAuto, "la réouverture annule l'envoi automatique")
            egal(true, Fenetre.aRouvrir)
            egal(fermetures + 1, S.fermetures, 'fenêtre fermée')
            Fenetre.periodique()
            egal(fermetures + 1, S.fermetures, 'une seule fermeture')
        else
            egal('panneau', Fenetre.disposition)
            egal('Assombris un peu moins le ciel', p.saisie, 'la demande tapée revient dans le champ')
            egal(nil, Fenetre.envoiAuto, 'sans partir')
            -- L'envoi prévu avant la réouverture ne part pas non plus.
            envoiPrevu()
            egal('Assombris un peu moins le ciel', p.saisie)
            egal(true, p.libre)
            egal(false, Moteur.travaille)
            -- Une seule boucle : celle de la première fenêtre s'arrête aussitôt, celle-ci tourne.
            local dormir, sommeils = S.modules.LrTasks.sleep, 0
            S.modules.LrTasks.sleep = function()
                sommeils = sommeils + 1
                if sommeils >= 2 then
                    error('boucle arrêtée par l\'essai', 0)
                end
            end
            Fenetre.boucle(ouvertures[1].generation)
            local premiere = sommeils
            local ok, erreur = pcall(Fenetre.boucle, Fenetre.generation)
            S.modules.LrTasks.sleep = dormir
            egal(0, premiere, "l'ancienne boucle s'arrête sans tourner")
            vrai(not ok and erreur == 'boucle arrêtée par l\'essai', 'la nouvelle boucle tourne : ' .. tostring(erreur))
        end
    end
    Fenetre.afficher()
    egal(1, #ouvertures)
    egal(false, Fenetre.ouverte)
    -- La réouverture attend dans une tâche que la première fenêtre soit fermée. Le champ rempli
    -- par la fenêtre (le brouillon) n'est pas une demande validée par Dany.
    egal(Fenetre.afficher, S.taches[#S.taches], 'réouverture prévue')
    local saisieValidee, validees = Fenetre.saisieValidee, 0
    Fenetre.saisieValidee = function(valeur)
        if not Fenetre.ignorerSaisie then
            validees = validees + 1
        end
        return saisieValidee(valeur)
    end
    S.taches[#S.taches]()
    Fenetre.saisieValidee = saisieValidee
    egal(0, validees, 'le brouillon rendu ne compte pas comme une demande validée')
    egal(2, #ouvertures)
    egal('DeveloppeurClaude-conversation-grande-1', ouvertures[1].cadre)
    egal('DeveloppeurClaude-panneau-grande-1', ouvertures[2].cadre)
    egal(ouvertures[1].generation + 1, ouvertures[2].generation)
    egal(false, Fenetre.ouverte)
    egal(nil, Fenetre.p)
    egal(nil, Moteur.observateurs.fenetre)
    egal(nil, Fenetre.brouillon)
    S.pendantFenetre = nil
end)

essai('Ouvrir une fenêtre déjà ouverte : devant, ou rouverte si la disposition a changé', function()
    prefs.disposition = 'atelier'
    local etapes = 0
    S.pendantFenetre = function()
        etapes = etapes + 1
        if etapes == 1 then
            local devant, taches = S.devant or 0, #S.taches
            Fenetre.voirActive = false
            Fenetre.afficher()
            egal(devant + 1, S.devant, 'même disposition : la fenêtre passe devant')
            egal(false, Fenetre.aRouvrir)
            -- … et l'aperçu remontre la photo active, relue dans une tâche.
            egal(taches + 1, #S.taches, 'photo active relue')
            S.taches[#S.taches]()
            egal(true, Fenetre.voirActive, "l'aperçu remontre la photo active")
            -- Disposition changée dans le Gestionnaire, puis ⌃⌥C ou « Ouvrir la fenêtre Claude ».
            prefs.disposition = 'panneau'
            local fermetures = S.fermetures or 0
            Fenetre.afficher()
            egal(true, Fenetre.aRouvrir)
            egal(fermetures + 1, S.fermetures)
        else
            egal('panneau', Fenetre.T.nom)
        end
    end
    Fenetre.afficher()
    S.taches[#S.taches]()
    egal(2, etapes)
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
end)

essai('Disposition : une valeur inconnue ou la même ne rouvre pas', function()
    prefs.disposition = 'conversation'
    S.pendantFenetre = function()
        local fermetures = S.fermetures or 0
        prefs.disposition = 'inconnue'
        Fenetre.periodique()
        prefs.disposition = 'conversation'
        Fenetre.periodique()
        egal(fermetures, S.fermetures or 0, 'rien à rouvrir')
        egal(false, Fenetre.aRouvrir)
    end
    Fenetre.afficher()
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
    -- Une disposition inconnue dans les préférences retombe sur celle par défaut.
    egal('conversation', Dispositions.dimensions('inconnue').nom)
    egal('DeveloppeurClaude-panneau-grande-1', Fenetre.cadre('panneau'))
    -- Une seule taille, la grande (demandé par Dany le 20 octobre 2026).
    egal(nil, Chemins.defauts.taille, 'plus de préférence de taille')
end)

essai('Boucle de la fenêtre : toutes les 2 s, une disposition changée la ferme pour la rouvrir', function()
    prefs.disposition = 'conversation'
    local sommeils, fermetures, ok, erreur = 0, nil, nil, nil
    S.pendantFenetre = function()
        local dormir = S.modules.LrTasks.sleep
        fermetures = S.fermetures or 0
        S.modules.LrTasks.sleep = function()
            sommeils = sommeils + 1
            if sommeils == 2 then
                -- Panneau choisi dans le Gestionnaire de modules externes.
                prefs.disposition = 'panneau'
            elseif sommeils >= 12 then
                error('boucle arrêtée par l\'essai', 0)
            end
        end
        ok, erreur = pcall(Fenetre.boucle, Fenetre.generation)
        S.modules.LrTasks.sleep = dormir
        egal(fermetures + 1, S.fermetures, 'fermée une fois, au huitième tour (2 s)')
        egal(true, Fenetre.aRouvrir)
    end
    Fenetre.afficher()
    vrai(not ok and erreur == 'boucle arrêtée par l\'essai', tostring(erreur))
    egal(Fenetre.afficher, S.taches[#S.taches], 'réouverture prévue')
    S.pendantFenetre = nil
    S.taches[#S.taches]()
    egal('panneau', Fenetre.disposition, 'rouverte en Panneau')
    prefs.disposition = 'conversation'
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
    prefs.disposition = 'conversation'
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
    -- Panneau : la proposition se montre dans Retoucher, à la place des invites.
    prefs.disposition = 'panneau'
    S.pendantFenetre = function()
        local p = Fenetre.p
        egal('retoucher', p.onglet)
        egal(false, p.aProposition)
        p.onglet = 'notation'
        Conversation.appliquer(Moteur.courante, { genre = 'assistant', blocs = { { genre = 'outil', id = 'onglet-2',
            nom = 'mcp__developpeur__preview_settings', entree = { settings = { Exposure2012 = 0.2 } } } } })
        Fenetre.rafraichir()
        egal('retoucher', p.onglet)
        egal(true, p.aProposition)
        Conversation.decider(Moteur.courante, Conversation.propositionEnAttente(Moteur.courante).id, false)
        Fenetre.rafraichir()
        egal(false, p.aProposition)
    end
    Fenetre.afficher()
    prefs.disposition, prefs.nouvelleParPhoto = 'conversation', true
    S.pendantFenetre = nil
end)

-- Nouvelle conversation par photo -------------------------------------------------------------

essai('Autre photo choisie : une nouvelle conversation, pas pendant que Claude travaille ni pour une conversation vide', function()
    prefs.disposition, prefs.nouvelleParPhoto = 'conversation', true
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
    prefs.disposition, prefs.nouvelleParPhoto = 'conversation', true
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

-- Les variantes des onglets : la colonne superposée qui suit la rangée des boutons radio (clé
-- `onglet`) ; nil sans onglets (Atelier).
-- Les variantes superposées qui suivent la rangée des onglets dans la même colonne (la Conversation
-- claire met l'aperçu entre les deux).
local function variantesOnglets(contenu)
    for _, v in ipairs(vues(contenu)) do
        for i, e in ipairs(v.args) do
            if type(e) == 'table' and e.genre == 'row' and type(e.args[1]) == 'table' and e.args[1].genre == 'radio_button'
                and e.args[1].args.value.key == 'onglet' then
                for k = i + 1, #v.args do
                    if type(v.args[k]) == 'table' and v.args[k].args and v.args[k].args.place == 'overlapping' then
                        return v.args[k]
                    end
                end
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
    for _, disposition in ipairs(Dispositions.LISTE) do
        local nom = disposition.value
        prefs.disposition = disposition.value
        local D = Dispositions.dimensions(disposition.value)
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
            -- Un onglet autre que Note (Proposition, Retoucher) : l'aperçu montré (hors des
            -- onglets), la carte Note masquée ; la proposition seulement dans Proposition.
            local autre = D.onglets[1].valeur == D.ongletNotation and D.onglets[2].valeur or D.onglets[1].valeur
            p.onglet, p.aProposition = autre, false
            local apercu
            for _, v in ipairs(vues(args.contents)) do
                apercu = apercu or (v.genre == 'picture' and v)
            end
            egal(true, S.montree(apercu, p), nom .. ' : aperçu montré')
            egal(false, S.montree(vueLiee(args.contents, 'static_text', 'notationTexte'), p), nom .. ' : texte de la note masqué')
            egal(autre == 'proposition', S.montree(vueLiee(args.contents, 'static_text', 'propositionTexte'), p), nom .. ' : proposition')
            egal(false, S.montree(bouton(args.contents, p, 'Accepter', 'peutAccepterNote'), p), nom .. ' : Accepter de la note masqué')
            egal(true, S.montree(vueLiee(args.contents, 'static_text', 'infoPhoto'), p), nom .. ' : hors des onglets, toujours montré')
            -- Une variante de couleur dans un onglet : sa couleur et l'onglet, combinés.
            local titres = {}
            for _, v in ipairs(vues(args.contents)) do
                if v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.key == 'notationProposee' then
                    titres[#titres + 1] = v
                end
            end
            egal(4, #titres, nom .. ' : quatre couleurs de la note proposée')
            p.notationCouleur = 'vert'
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
            egal(C.vert, montrees[1].args.text_color, nom .. ' : la couleur de l\'état')
            egal(true, S.montree(vueLiee(args.contents, 'static_text', 'notationTexte'), p), nom .. ' : texte de la note montré')
            egal(true, S.montree(apercu, p), nom .. " : l'aperçu reste montré avec la carte Note")
            if disposition.value == 'panneau' then
                -- Onglets imbriqués : dans Retoucher, la proposition prend la place des invites.
                local invite = bouton(args.contents, p, Consignes.invites[1].titre)
                local saisie = vueLiee(args.contents, 'edit_field', 'saisie')
                egal(false, S.montree(saisie, p), nom .. ' : demande masquée dans Noter')
                p.onglet = 'retoucher'
                egal(true, S.montree(saisie, p), nom .. ' : demande montrée')
                egal(true, S.montree(invite, p), nom .. ' : invites montrées sans proposition')
                p.aProposition = true
                egal(false, S.montree(invite, p), nom .. ' : invites masquées par la proposition')
                egal(true, S.montree(vueLiee(args.contents, 'static_text', 'propositionTexte'), p), nom .. ' : proposition montrée')
                p.onglet = 'notation'
                egal(false, S.montree(vueLiee(args.contents, 'static_text', 'propositionTexte'), p), nom .. ' : proposition masquée dans Noter')
                p.aProposition = false
            end
        end
        Fenetre.afficher()
        vrai(construite, nom .. ' : fenêtre construite')
    end
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
end)

-- Carte Note ------------------------------------------------------------------------------------

essai('Carte Note : proposition, Accepter, Changer… jusqu\'à 5 ★, à vérifier, rejet', function()
    prefs.disposition = 'conversation'
    photoActive(4961, 'DSCF4961.RAF', 2, 1)
    registre.poses, registre.decisions = {}, {}
    proposer(4961, { fichier = 'DSCF4961.RAF', note = 3, drapeau = 'aucun',
        criteres = { impact = "Le ciel d'orage arrête l'œil.", qualites = "Sujet clair, horizon droit.", plancher = "Netteté 41 : nette." },
        plafond = 3, raison = "Tient seule devant qui ne connaît pas le lieu.", passe = 2, le = 1000 })
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        local abonnes = registre.abonnes
        vrai(registre.abonne, 'la fenêtre suit le registre')
        egal('DSCF4961', p.notationNom)
        egal('Note posée : ★★☆☆☆ · retenue', p.notationPosee)
        egal('Claude propose : ★★★☆☆', p.notationProposee)
        egal('orange', p.notationCouleur)
        egal('proposée · passe 2', p.notationEtat)
        -- Les critères, le plafond, puis la raison, dans un seul texte coupé en lignes.
        egal("Impact : Le ciel d'orage arrête l'œil.\nQualités : Sujet clair, horizon droit.\nPlancher technique : Netteté 41 : nette.\nPlafond mesuré : 3 ★"
            .. "\n\nTient seule devant qui ne connaît pas le lieu.", p.notationTexte)
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
        -- Accepter : la proposition telle quelle, écrite dans une tâche (le registre et le
        -- catalogue ne se lisent pas dans le clic), une écriture à la fois.
        local avant = #S.taches
        local poserVraiment, pendant = Notation.poser, nil
        Notation.poser = function(liste)
            pendant = { accepter = p.peutAccepterNote, changer = p.peutChangerNote }
            return poserVraiment(liste)
        end
        bouton(args.contents, p, 'Accepter', 'peutAccepterNote').args.action()
        egal(avant + 1, #S.taches, 'écriture dans une tâche')
        egal(0, #registre.poses, 'rien posé dans le clic')
        S.taches[#S.taches]()
        Notation.poser = poserVraiment
        vrai(pendant and not pendant.accepter and not pendant.changer, 'pas deux écritures à la fois')
        egal(1, #registre.poses)
        egal(1, #registre.poses[1])
        egal(4961, registre.poses[1][1].photo)
        vrai(registre.poses[1][1].note == nil and registre.poses[1][1].drapeau == nil, 'sans note ni drapeau : la proposition telle quelle')
        egal(true, Fenetre.aRafraichirNotation, 'la carte se relit')
        Fenetre.rafraichirNotation()
        egal('vert', p.notationCouleur)
        egal('acceptée · passe 2', p.notationEtat)
        egal(false, p.peutAccepterNote, 'déjà acceptée')
        -- Changer… : Dany peut poser 5 ★ (fenêtre modale, depuis une tâche).
        local presenter = S.modules.LrDialogs.presentModalDialog
        local vue
        S.modules.LrDialogs.presentModalDialog = function(d)
            local q = d.contents.args.bind_to_object
            vue = { note = q.note, drapeau = q.drapeau }
            q.note = 5
            return 'ok'
        end
        bouton(args.contents, p, 'Changer…').args.action()
        S.taches[#S.taches]()
        S.modules.LrDialogs.presentModalDialog = presenter
        egal(3, vue.note, 'la note proposée d\'abord')
        egal('inchange', vue.drapeau, 'le drapeau reste tel quel')
        egal(2, #registre.poses)
        egal(5, registre.poses[2][1].note)
        egal(nil, registre.poses[2][1].drapeau)
        Fenetre.rafraichirNotation()
        egal('changée : ★★★★★ · passe 2', p.notationEtat)
        -- Une nouvelle proposition de Claude, comme toutes depuis la 1.1.1 : à vérifier.
        proposer(4961, { note = 4, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Peut-être 4.', le = 2000, etat = 'a_verifier' })
        Fenetre.rafraichirNotation()
        egal(2, #registre.poses, 'rien de posé')
        egal('rouge', p.notationCouleur)
        egal('à vérifier', p.notationEtat)
        egal(true, p.peutAccepterNote, 'une note à vérifier s\'accepte')
        -- Un rejet proposé.
        proposer(4961, { drapeau = 'rejetee', criteres = { plancher = 'Floue : netteté 9.' }, plafond = 0, raison = 'Mise au point manquée.', le = 3000 })
        Fenetre.rafraichirNotation()
        egal('Claude propose : rejeter', p.notationProposee)
        vrai(p.notationTexte:find('Plafond mesuré : 0 ★', 1, true), p.notationTexte)
        -- Une autre photo, sans proposition : l'aide, Changer… seulement.
        photoActive(4970, 'DSCF4970.RAF', 0, 0)
        Fenetre.majPhoto()
        egal('DSCF4970', p.notationNom)
        egal('Note posée : aucune, pas encore jugée', p.notationPosee)
        egal('Aucune note proposée', p.notationProposee)
        egal(Fenetre.AIDE_NOTATION, (p.notationTexte:gsub('\n', ' ')), "l'aide, coupée en lignes")
        vrai(not p.peutAccepterNote and p.peutChangerNote)
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
        local lignes = {}
        for i = 1, 60 do
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
        egal('Ligne 60', p.propositionTexte:match('[^\n]*$'))
        egal(false, p.propositionDescend)
        local monter = bouton(args.contents, p, '▲', 'propositionMonte')
        monter.args.action(monter)
        egal(true, p.propositionDescend)
        -- Le même texte relu garde sa page ; un autre revient à la première.
        local avant = p.propositionTexte
        Fenetre.montrerPage('proposition', long)
        egal(avant, p.propositionTexte, 'page gardée au rafraîchissement')
        Fenetre.montrerPage('proposition', long .. '\nLigne 61')
        egal('Ligne 1', p.propositionTexte:match('^[^\n]*'), 'un autre texte : première page')
        -- Un long paragraphe est coupé à la largeur de la carte, comme le fil.
        Fenetre.montrerPage('note', string.rep('Le ciel orageux tient la photo. ', 40))
        for l in (p.notationTexte .. '\n'):gmatch('([^\n]*)\n') do
            vrai(Fil.largeur(l, 'texte') <= T.largeurNote - Fil.MARGE, 'ligne trop large : ' .. l)
        end
        egal(true, p.noteDescend, 'le paragraphe dépasse la carte')
        egal(false, p.noteMonte)
        Fenetre.defilerTexte('note', 1)
        egal(true, p.noteMonte)
        -- Une ligne ne commence jamais par une ponctuation haute (« ; mais » vu sur la carte Note),
        -- et les espaces restent ordinaires.
        local phrase = "Qualités : Sommet de l'action, espace devant l'auto ; mais lumière plate et terne ! « Auto » petite ?"
        for largeur = 90, 400, 7 do
            for _, l in ipairs(Fil.couper(phrase, largeur, 'texte')) do
                vrai(not l:find('^[;:!?]') and not l:find('^»') and not l:find('«$'), largeur .. ' : « ' .. l .. ' »')
                vrai(not l:find('\194\160', 1, true), 'espace insécable rendue')
            end
        end
        -- Un texte court tient : ni ▲ ni ▼.
        Fenetre.montrerPage('note', 'Court.')
        egal('Court.', p.notationTexte)
        egal(false, p.noteMonte)
        egal(false, p.noteDescend)
    end
    Fenetre.afficher()
    vrai(vu, 'fenêtre ouverte')
    S.pendantFenetre = nil
end)

essai('Consignes : chaque photo traitée notée d\'abord, à vérifier, avec le carré de la mise au point', function()
    for _, morceau in ipairs({ "note-la d'abord", 'af_point = true', 'view_photo : evaluation', '« à vérifier »', 'apply = true' }) do
        vrai(Consignes.texte:find(morceau, 1, true), 'consignes : ' .. morceau)
    end
end)

-- Liste des conversations -----------------------------------------------------------------------

essai('Conversations : les anciennes séances de notation ne sont ni dans la liste ni dans le menu', function()
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
    local menu = Fenetre.elementsMenu()
    S.neuve(menu, 'menu')
    vrai(ids(menu)[ordinaire.id] and not ids(menu)[seance.id], 'menu sans la séance')
    for _, item in ipairs(menu) do
        vrai(item.value:sub(1, 1) ~= '§', 'pas d\'en-tête dans un menu')
    end
    -- Une séance n'est jamais montrée comme conversation ouverte.
    Moteur.courante = seance
    vrai(not ids(Fenetre.elementsListe(''))[seance.id] and not ids(Fenetre.elementsMenu())[seance.id])
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

essai('Gestionnaire de modules externes : les sections se construisent, menus Modèle, Effort et Disposition, case Autre photo', function()
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
            if v.genre == 'push_button' then
                vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
            end
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.key == 'disposition' then
                menu = v
            end
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' then
                menus[v.args.value.key] = v
            elseif v.genre == 'checkbox' and type(v.args.value) == 'table' then
                cases[v.args.value.key] = v
            end
        end
    end
    vrai(menu, 'menu Disposition')
    local valeurs, titres = {}, {}
    for _, item in ipairs(menu.args.items) do
        valeurs[#valeurs + 1] = item.value
        titres[#titres + 1] = item.title
    end
    egal('atelier conversation panneau', table.concat(valeurs, ' '))
    egal('Atelier · Conversation claire · Panneau', table.concat(titres, ' · '))
    for _, valeur in ipairs(valeurs) do
        vrai(Dispositions.TAILLES[valeur], 'disposition connue : ' .. valeur)
    end
    egal('conversation', prefsModule.disposition, 'Conversation claire par défaut')
    vrai(PluginInfoProvider.diagnostic():find('disposition conversation ; nouvelle conversation', 1, true), 'diagnostic')
    egal(nil, menus.taille, 'plus de menu Taille (toujours grande)')
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
    S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(dossier .. '/paysage.jpg') .. ' >/dev/null 2>&1')
    S.executer('/usr/bin/sips -s format jpeg -z 90 60 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(dossier .. '/portrait.jpg') .. ' >/dev/null 2>&1')
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

essai('Images « aucun aperçu » : une par cadre, à ses dimensions', function()
    local vus = {}
    for _, disposition in ipairs(Dispositions.LISTE) do
        local D = Dispositions.dimensions(disposition.value)
        local nom = Dispositions.imageVide(D)
        if not vus[nom] then
            vus[nom] = true
            local l, h = Images.dimensions(Chemins.ressource(nom))
            egal(D.apercu, l, nom)
            egal(D.apercuHauteur or D.apercu, h, nom)
        end
    end
    vrai(vus['vide-320.png'] and vus['vide-200.png'] and vus['vide-720x480.png'], 'carrés et cadre')
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
