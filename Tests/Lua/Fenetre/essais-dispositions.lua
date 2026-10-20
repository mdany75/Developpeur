-- essais-dispositions.lua : la fenêtre Claude dans ses trois dispositions (Atelier, Conversation
-- claire, Panneau) hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : réouverture
-- dans une autre disposition (demande tapée rendue sans partir, une seule boucle), menu
-- Disposition, onglets, carte Note, bouton Noter, conversations de séance absentes de la liste,
-- Gestionnaire de modules externes, vignettes dans un cadre 3:2, images « aucun aperçu ».
-- Le registre des notes (Notation) et la fenêtre de séance (FenetreNotation) gardent ici les
-- appels reçus : la simulation de la fenêtre n'écrit pas dans un catalogue. Ni Claude, ni quota.
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

-- La fenêtre de séance : les ouvertures demandées.
local seances = {}
local FenetreNotation = require 'FenetreNotation'
local afficherSeance = FenetreNotation.afficher
FenetreNotation.afficher = function(options)
    seances[#seances + 1] = options or {}
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

essai('Contrats : registre des notes, fenêtre de séance, message du bouton Noter', function()
    for nom, fn in pairs(contratNotation) do
        vrai(type(fn) == 'function', 'Notation.' .. nom .. ' manque')
    end
    vrai(type(afficherSeance) == 'function', 'FenetreNotation.afficher manque')
    vrai(type(Consignes.noterPhoto) == 'string' and Consignes.noterPhoto ~= '', 'Consignes.noterPhoto : un texte')
end)

-- Réouverture ---------------------------------------------------------------------------------

essai('Rouvrir dans une autre disposition : la demande tapée revient sans partir, une seule boucle', function()
    prefs.disposition, prefs.taille = 'conversation', 'moyenne'
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
            -- … mais il choisit le Panneau dans le menu Disposition.
            p.disposition = 'panneau'
            egal(nil, Fenetre.envoiAuto, "le choix d'une disposition annule l'envoi automatique")
            egal('panneau', Chemins.prefs().disposition, 'préférence écrite')
            -- La fenêtre se ferme depuis une tâche, pour se rouvrir.
            fermetures = S.fermetures or 0
            S.taches[#S.taches]()
            egal(true, Fenetre.aRouvrir)
            egal(fermetures + 1, S.fermetures, 'fenêtre fermée')
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
    egal('DeveloppeurClaude-conversation-moyenne-1', ouvertures[1].cadre)
    egal('DeveloppeurClaude-panneau-moyenne-1', ouvertures[2].cadre)
    egal(ouvertures[1].generation + 1, ouvertures[2].generation)
    egal(false, Fenetre.ouverte)
    egal(nil, Fenetre.p)
    egal(nil, Moteur.observateurs.fenetre)
    egal(nil, Fenetre.brouillon)
    S.pendantFenetre = nil
end)

essai('Ouvrir une fenêtre déjà ouverte : devant, ou rouverte si la disposition ou la taille a changé', function()
    prefs.disposition, prefs.taille = 'atelier', 'moyenne'
    local etapes = 0
    S.pendantFenetre = function()
        etapes = etapes + 1
        if etapes == 1 then
            local devant = S.devant or 0
            Fenetre.afficher()
            egal(devant + 1, S.devant, 'même disposition : la fenêtre passe devant')
            egal(false, Fenetre.aRouvrir)
            -- Taille changée dans le Gestionnaire, puis ⌃⌥C ou « Ouvrir la fenêtre Claude ».
            prefs.taille = 'grande'
            local fermetures = S.fermetures or 0
            Fenetre.afficher()
            egal(true, Fenetre.aRouvrir)
            egal(fermetures + 1, S.fermetures)
        else
            egal('atelier', Fenetre.T.nom)
            egal('grande', Fenetre.T.taille)
        end
    end
    Fenetre.afficher()
    S.taches[#S.taches]()
    egal(2, etapes)
    prefs.taille = 'moyenne'
    S.pendantFenetre = nil
end)

essai('Menu Disposition : une valeur inconnue ou la même ne rouvre pas', function()
    prefs.disposition = 'conversation'
    S.pendantFenetre = function()
        local p = Fenetre.p
        local avant = #S.taches
        p.disposition = 'inconnue'
        p.disposition = 'conversation'
        egal(avant, #S.taches, 'rien à rouvrir')
        egal('conversation', Chemins.prefs().disposition)
        p.disposition = 'atelier'
        egal(avant + 1, #S.taches, 'réouverture demandée')
        egal('atelier', Chemins.prefs().disposition)
    end
    Fenetre.afficher()
    egal(false, Fenetre.aRouvrir, 'la tâche de réouverture ne tourne pas ici')
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
    -- Une disposition inconnue dans les préférences retombe sur celle par défaut.
    egal('conversation', Dispositions.dimensions('inconnue', 'enorme').nom)
    egal('moyenne', Dispositions.dimensions('atelier', 'enorme').taille)
    egal('DeveloppeurClaude-panneau-petite-1', Fenetre.cadre('panneau', 'petite'))
end)

-- Onglets -------------------------------------------------------------------------------------

essai('Onglets : une proposition ou une note qui arrive se montre, une seule fois', function()
    prefs.disposition = 'conversation'
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        egal('apercu', p.onglet)
        local c = Moteur.courante
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'onglet-1', nom = 'mcp__developpeur__preview_settings',
            entree = { reason = 'Balance', settings = { Exposure2012 = 0.35 } } } } })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'une proposition qui arrive se montre')
        egal(true, p.aProposition)
        -- Dany revient à l'aperçu : la fenêtre ne reprend pas la main.
        p.onglet = 'apercu'
        Fenetre.rafraichir()
        egal('apercu', p.onglet)
        -- Une note proposée pour la photo active : l'onglet Note.
        proposer(4961, { note = 3, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Tient seule.', le = 100 })
        Fenetre.rafraichirNotation()
        egal('notation', p.onglet)
        p.onglet = 'apercu'
        Fenetre.rafraichirNotation()
        egal('apercu', p.onglet, 'une seule fois')
        -- Une autre photo choisie, qui a déjà sa proposition : l'onglet ne change pas.
        proposer(4962, { note = 2, drapeau = 'aucun', criteres = {}, raison = '', le = 101 })
        photoActive(4962, 'DSCF4962.RAF', 0, 0)
        Fenetre.majPhoto()
        egal('apercu', p.onglet)
        -- Un clic sur un onglet n'envoie pas la demande validée par ce clic.
        p.saisie = 'Texte validé par le clic'
        vrai(Fenetre.envoiAuto, 'envoi prévu')
        p.onglet = 'proposition'
        egal(nil, Fenetre.envoiAuto, "le clic d'un onglet annule l'envoi automatique")
        -- Un clic sur une ligne d'image montre l'aperçu.
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
        egal('apercu', p.onglet, "un clic sur une image montre l'aperçu")
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
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
end)

-- Carte Note ------------------------------------------------------------------------------------

essai('Carte Note : proposition, Accepter, Changer… jusqu\'à 5 ★, À vérifier, rejet', function()
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
        egal("Impact : Le ciel d'orage arrête l'œil.\nQualités : Sujet clair, horizon droit.\nPlancher technique : Netteté 41 : nette.\nPlafond mesuré : 3 ★",
            p.notationCriteres)
        egal('Tient seule devant qui ne connaît pas le lieu.', p.notationRaison)
        vrai(p.peutAccepterNote and p.peutChangerNote and p.peutVerifierNote, 'boutons actifs')
        -- Claude travaille : ni Accepter ni Changer (les écritures de la fenêtre échappent à la file
        -- du connecteur) ; À vérifier n'écrit rien dans le catalogue.
        Moteur.travaille = true
        Fenetre.rafraichir()
        vrai(not p.peutAccepterNote and not p.peutChangerNote, 'désactivés pendant que Claude travaille')
        egal(true, p.peutVerifierNote)
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
        -- Une nouvelle proposition, mise à vérifier : rien n'est écrit.
        proposer(4961, { note = 4, drapeau = 'aucun', criteres = { impact = 'Fort.' }, raison = 'Peut-être 4.', le = 2000 })
        Fenetre.rafraichirNotation()
        bouton(args.contents, p, 'À vérifier').args.action()
        S.taches[#S.taches]()
        egal(1, #registre.decisions)
        egal('a_verifier', registre.decisions[1].etat)
        egal(4961, registre.decisions[1].photo)
        egal(2, #registre.poses, 'rien de posé')
        Fenetre.rafraichirNotation()
        egal('rouge', p.notationCouleur)
        egal('à vérifier', p.notationEtat)
        egal(true, p.peutAccepterNote, 'une note à vérifier peut encore être acceptée')
        egal(false, p.peutVerifierNote)
        -- Un rejet proposé.
        proposer(4961, { drapeau = 'rejetee', criteres = { plancher = 'Floue : netteté 9.' }, plafond = 0, raison = 'Mise au point manquée.', le = 3000 })
        Fenetre.rafraichirNotation()
        egal('Claude propose : rejeter', p.notationProposee)
        vrai(p.notationCriteres:find('Plafond mesuré : 0 ★', 1, true), p.notationCriteres)
        -- Une autre photo, sans proposition : l'aide, Changer… seulement.
        photoActive(4970, 'DSCF4970.RAF', 0, 0)
        Fenetre.majPhoto()
        egal('DSCF4970', p.notationNom)
        egal('Note posée : aucune, pas encore jugée', p.notationPosee)
        egal('Aucune note proposée', p.notationProposee)
        egal(Fenetre.AIDE_NOTATION, p.notationCriteres)
        vrai(not p.peutAccepterNote and p.peutChangerNote and not p.peutVerifierNote)
        egal(abonnes, registre.abonnes, 'abonnée une fois')
    end
    Fenetre.afficher()
    egal(nil, registre.abonne, 'désabonnée à la fermeture')
    S.pendantFenetre = nil
end)

essai('Noter : la photo active à Claude, plusieurs photos en séance ; Séance…', function()
    prefs.disposition = 'atelier'
    photoActive(4961, 'DSCF4961.RAF', 0, 0)
    S.pendantFenetre = function(args)
        local p = Fenetre.p
        local envoyes = {}
        local envoyer = Fenetre.envoyer
        Fenetre.envoyer = function(texte) envoyes[#envoyes + 1] = texte end
        bouton(args.contents, p, 'Noter').args.action()
        S.taches[#S.taches]()
        egal(1, #envoyes)
        egal(Consignes.noterPhoto, envoyes[1], 'le message Noter de la photo active')
        -- Plusieurs photos sélectionnées : la séance de notation, sur la sélection.
        S.selection = { S.photoActive, S.photo(4962, 'DSCF4962.RAF'), S.photo(4963, 'DSCF4963.RAF') }
        local n = #seances
        bouton(args.contents, p, 'Noter').args.action()
        S.taches[#S.taches]()
        egal(1, #envoyes, 'rien envoyé à Claude')
        egal(n + 1, #seances)
        egal('selection', seances[#seances].portee)
        bouton(args.contents, p, 'Séance…').args.action()
        egal(n + 2, #seances)
        -- Aucune photo active.
        S.photoActive, S.selection = nil, {}
        bouton(args.contents, p, 'Noter').args.action()
        S.taches[#S.taches]()
        vrai(p.message:find('Aucune photo active', 1, true), p.message)
        Fenetre.envoyer = envoyer
    end
    Fenetre.afficher()
    prefs.disposition = 'conversation'
    S.pendantFenetre = nil
end)

-- Liste des conversations -----------------------------------------------------------------------

essai('Conversations : les séances de notation ne sont ni dans la liste ni dans le menu', function()
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

essai('Gestionnaire de modules externes : les sections se construisent, menu Disposition à trois valeurs', function()
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
    for _, enfant in ipairs(section) do
        for _, v in ipairs(vues(enfant)) do
            for cle, valeur in pairs(v.args) do
                if type(cle) == 'string' then
                    vrai(PROPRIETES[cle], 'propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                    if type(valeur) == 'table' and valeur.liaison then
                        local objet = valeur.bind_to_object or section.bind_to_object
                        vrai(objet[valeur.key] ~= nil, 'liaison sans valeur : ' .. valeur.key)
                    end
                end
            end
            if v.genre == 'push_button' then
                vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
            end
            if v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.key == 'disposition' then
                menu = v
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
    vrai(PluginInfoProvider.diagnostic():find('disposition conversation, taille moyenne', 1, true), 'diagnostic')
end)

-- Images ----------------------------------------------------------------------------------------

essai('Vignettes : un cadre 3:2 garde toute l\'image, centrée sur le fond', function()
    local dossier = S.home .. '/vignettes-essai'
    Fichiers.creerDossier(dossier)
    S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-230.png') .. ' --out ' .. S.q(dossier .. '/paysage.jpg') .. ' >/dev/null 2>&1')
    S.executer('/usr/bin/sips -s format jpeg -z 90 60 ' .. S.q(S.plugin .. '/vide-230.png') .. ' --out ' .. S.q(dossier .. '/portrait.jpg') .. ' >/dev/null 2>&1')
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
        for _, taille in ipairs({ 'petite', 'moyenne', 'grande' }) do
            local D = Dispositions.dimensions(disposition.value, taille)
            local nom = Dispositions.imageVide(D)
            if not vus[nom] then
                vus[nom] = true
                local l, h = Images.dimensions(Chemins.ressource(nom))
                egal(D.apercu, l, nom)
                egal(D.apercuHauteur or D.apercu, h, nom)
            end
        end
    end
    vrai(vus['vide-270.png'] and vus['vide-600x400.png'], 'carrés et cadres')
    vrai(Fichiers.existe(Chemins.ressource('vide-230.png')), "vide-230.png reste (l'essai Coller s'en sert)")
end)

-- Fin -------------------------------------------------------------------------------------------

FenetreNotation.afficher = afficherSeance
for nom, fn in pairs(contratNotation) do
    Notation[nom] = fn
end
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
