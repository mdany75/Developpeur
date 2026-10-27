-- Moteur.lua : les conversations, celle qui est ouverte dans la fenêtre Claude, et le processus
-- Claude Code qui répond. Indépendant des fenêtres : si on les ferme pendant que Claude travaille,
-- le travail continue et se retrouve à la réouverture. Les fenêtres s'abonnent par Moteur.abonner.
-- Un seul processus et une seule demande à la fois : passer d'une conversation à l'autre relance
-- Claude Code en reprenant la session de la conversation (`--resume`). Les conversations des
-- anciennes séances de notation (genre 'notation', fenêtre retirée le 20 octobre 2026) restent sur
-- le disque mais ne s'ouvrent plus.
-- Une photo, une conversation (correctif 1.3.6, décidé avec Dany le 25 octobre 2026) : chaque photo
-- seule a sa conversation (Moteur.conversationDe : la plus récente gardée pour son localIdentifier,
-- hors des conversations écartées par « Repartir à neuf », Moteur.ecarter), que la fenêtre montre
-- quand Dany la choisit (Fenetre.suivreSelection, Moteur.montrer) ; une conversation neuve n'est
-- gardée qu'à sa première demande (Moteur.envoyer), celle d'un groupe de photos jamais (comme une
-- demande rapide sur plusieurs photos : `enregistrer`, images dans un dossier temporaire,
-- Moteur.dossier). À la fin de
-- chaque tour de Claude, la conversation d'une photo note ce qu'elle en a vu (Moteur.noterVu).
-- La Demande rapide (Moteur.envoyerRapide) écrit dans la conversation de la photo seule, la même que
-- la fenêtre Claude, sans la montrer ; ses éléments y sont marqués (`rapide`).
-- Les fonctions qui attendent (envoyer, boucle, charger) s'appellent depuis une tâche.

local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Consommation = require 'Consommation'
local Conversation = require 'Conversation'
local Evenements = require 'Evenements'
local Fichiers = require 'Fichiers'
local Historique = require 'Historique'
local Images = require 'Images'
local Journal = require 'Journal'
local Lightroom = require 'Lightroom'
local Session = require 'Session'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

local Moteur = {
    conversations = {},
    -- La conversation ouverte dans la fenêtre Claude (jamais une ancienne séance de notation).
    courante = nil,
    -- La conversation de la demande en cours, nil sans demande.
    enCours = nil,
    session = nil,
    travaille = false,
    -- Quand Claude a fini sa dernière demande (os.time, 0 : jamais), fenêtre ouverte ou fermée : ce
    -- qu'il a changé dans la sélection ne change pas de conversation (Fenetre.suivreSelection).
    finTravail = 0,
    limites = nil,
    -- Fenêtres abonnées aux changements (nom → fonction).
    observateurs = {},
    boucle = false,
    charge = false,
    derniereActivite = 0,
}

-- Délai d'une interruption avant d'arrêter le processus.
Moteur.DELAI_INTERRUPTION = 10
-- Écart minimal entre deux enregistrements pendant que Claude écrit.
Moteur.DELAI_ENREGISTREMENT = 3

function Moteur.signaler(quoi)
    for _, fn in pairs(Moteur.observateurs) do
        pcall(fn, quoi)
    end
end

function Moteur.abonner(nom, fn)
    Moteur.observateurs[nom] = fn
end

function Moteur.desabonner(nom)
    Moteur.observateurs[nom] = nil
end

local function trier()
    table.sort(Moteur.conversations, function(a, b) return (a.modifiee or 0) > (b.modifiee or 0) end)
end

local function dansListe(c)
    for _, x in ipairs(Moteur.conversations) do
        if x == c then
            return true
        end
    end
    return false
end

local function enregistrer(c)
    -- Une demande rapide jetable (Moteur.envoyerRapide : plusieurs photos) et la conversation d'un
    -- groupe ne sont jamais gardées.
    if c.rapide or c.groupe then
        return
    end
    local ok, erreur = LrTasks.pcall(Stockage.enregistrer, c)
    if not ok then
        Journal.noter("Enregistrement impossible :", c.id, tostring(erreur))
    end
    Moteur.enregistreLe = os.time()
end

-- Réécrit sur le disque une conversation déjà gardée (rien pour une conversation neuve, d'un
-- groupe ou rapide) : un complément « Depuis la dernière fois », ce qu'elle a vu de sa photo.
function Moteur.reecrire(c)
    if c and dansListe(c) then
        enregistrer(c)
    end
end

-- Le dossier des images d'une conversation : le sien (Conversations/<id>), ou le dossier
-- temporaire d'une conversation jamais gardée (un groupe, une demande rapide).
function Moteur.dossier(c)
    return c.dossier or Stockage.dossier(c.id)
end

-- Une conversation qui se montre : celle d'une photo (correctif 1.3.6), ni une ancienne séance de
-- notation, ni une conversation écartée par « Repartir à neuf ». Celles des groupes d'avant le
-- correctif (sans photo) restent sur le disque, plus montrées.
function Moteur.montrable(c)
    return type(c) == 'table' and not Conversation.estSeance(c) and c.ecartee ~= true and c.photo ~= nil and c.groupe == nil
end

-- La plus récente des conversations qui se montrent.
local function plusRecente()
    for _, c in ipairs(Moteur.conversations) do
        if Moteur.montrable(c) then
            return c
        end
    end
    return nil
end

-- Charge les conversations (une seule fois). La plus récente qui se montre s'ouvre (la fenêtre
-- montre ensuite celle de la photo choisie, Fenetre.suivreSelection). Une conversation d'avant le
-- correctif 1.3.6 dont la dernière demande portait sur une photo seule (clé « id:1:id ») devient
-- celle de cette photo, seulement si aucune plus récente ne l'a déjà (gardée avec sa photo, écartée
-- par « Repartir à neuf » comprise, ou rattachée juste avant) : avant le correctif, chaque retour sur
-- une photo en commençait une, et une plus ancienne reviendrait après « Repartir à neuf ». Les
-- autres restent sans photo, sur le disque, plus montrées (rien n'est effacé). La liste est rangée
-- de la plus récente à la plus ancienne (Stockage.charger).
function Moteur.charger()
    if Moteur.charge then
        return
    end
    Moteur.charge = true
    local ok, liste = LrTasks.pcall(Stockage.charger)
    Moteur.conversations = ok and liste or {}
    local prises = {}
    for _, c in ipairs(Moteur.conversations) do
        if c.groupe == nil and not Conversation.estSeance(c) then
            if c.photo == nil then
                local id = Conversation.photoDeLaCle(c.cle)
                if id ~= nil and not prises[Conversation.clePhoto(id)] then
                    c.photo = id
                end
            end
            if c.photo ~= nil then
                prises[Conversation.clePhoto(c.photo)] = true
            end
        end
    end
    Moteur.courante = plusRecente() or Conversation.nouvelle()
end

-- La conversation de la photo `id` (localIdentifier) : la plus récente qui se montre, nil sans
-- elle (la liste est rangée de la plus récente à la plus ancienne, trier).
function Moteur.conversationDe(id)
    for _, c in ipairs(Moteur.conversations) do
        if Moteur.montrable(c) and Conversation.dePhoto(c, id) then
            return c
        end
    end
    return nil
end

-- Une conversation par son identifiant (anciennes séances de notation comprises), nil sinon.
function Moteur.trouver(id)
    for _, c in ipairs(Moteur.conversations) do
        if c.id == id then
            return c
        end
    end
    if Moteur.courante and Moteur.courante.id == id then
        return Moteur.courante
    end
    return nil
end


function Moteur.arreterSession()
    if Moteur.session then
        Moteur.session:arreter()
        Moteur.session = nil
    end
end

Moteur.CLAUDE_TRAVAILLE = "Claude travaille : attendez la fin, ou cliquez Arrêter."

-- Montre une conversation dans la fenêtre (celle d'une photo, neuve ou gardée, ou celle d'un
-- groupe) : refusé pendant que Claude travaille, et pour une ancienne séance de notation. Le
-- processus de Claude Code reste ouvert : la demande suivante le relance au besoin, en reprenant la
-- session de la conversation (Moteur.envoyer) ; revenir à la photo d'avant sans rien demander n'a
-- rien relancé. La conversation d'un groupe quittée n'est jamais reprise : son dossier temporaire
-- s'efface.
function Moteur.montrer(c)
    if Moteur.travaille then
        return false, Moteur.CLAUDE_TRAVAILLE
    end
    if Conversation.estSeance(c) then
        return false, "Une ancienne séance de notation ne s'ouvre plus."
    end
    if not c or c == Moteur.courante then
        return c ~= nil
    end
    local avant = Moteur.courante
    Moteur.courante = c
    if avant and avant.groupe ~= nil and avant.dossier then
        if Moteur.session and Moteur.session.conversation == avant then
            Moteur.arreterSession()
        end
        LrTasks.pcall(Fichiers.supprimer, avant.dossier)
    end
    Moteur.signaler('conversation')
    return true
end

-- Ouvre une conversation par son identifiant (Moteur.montrer).
function Moteur.ouvrir(id)
    if Moteur.travaille then
        return false, Moteur.CLAUDE_TRAVAILLE
    end
    local c = Moteur.trouver(id)
    if not c then
        return false
    end
    return Moteur.montrer(c)
end

-- Une conversation neuve, vide (sans photo : la fenêtre fait celle d'une photo, Fenetre.suivrePhotos).
function Moteur.nouvelle()
    if Moteur.travaille then
        return false, Moteur.CLAUDE_TRAVAILLE
    end
    if Moteur.courante and #Moteur.courante.elements == 0 and Moteur.courante.photo == nil and Moteur.courante.groupe == nil then
        return true
    end
    return Moteur.montrer(Conversation.nouvelle())
end

-- « Repartir à neuf » (correctif 1.3.6) : la conversation est mise de côté, gardée sur le disque,
-- jamais effacée ; elle ne se montre plus (Moteur.montrable) ni ne se reprend.
function Moteur.ecarter(c)
    if not c then
        return
    end
    c.ecartee = true
    c.ecarteeLe = os.time()
    if Moteur.session and Moteur.session.conversation == c and not Moteur.travaille then
        Moteur.arreterSession()
    end
    Moteur.reecrire(c)
end

-- Ce que la conversation d'une photo en a vu (Historique.vu), relu à la fin d'un tour de Claude :
-- les étapes qu'il vient d'y faire ne feront pas de complément « Depuis la dernière fois ». Les
-- reprises à la main ne se lisent pas ici (seulement editCount et lastEditTime). À appeler depuis
-- une tâche.
function Moteur.noterVu(c)
    if not (c and c.photo ~= nil and c.groupe == nil) then
        return
    end
    local etat = Historique.lire(c.photo, true)
    if etat then
        c.vu = Historique.vu(etat)
    end
end

-- Ce que la fenêtre Claude et la Demande rapide disent d'une photo ou d'un groupe, sans Claude ni
-- jetons (Historique.lua, lectures du module par appel direct) : à appeler depuis une tâche.

-- Prépare `c` pour la photo `id` : sa photo et sa clé, son titre provisoire (le nom de la photo,
-- jusqu'à celui que Claude donne), son historique (rien sans étape de Claude ni retouche à la main)
-- et ce qu'elle en a vu. Rend `c`.
function Moteur.preparerPhoto(c, id, cle)
    c.photo = tonumber(id) or id
    c.cle = cle or c.cle
    local etat = Historique.lire(id)
    if not etat then
        return c
    end
    if etat.nom ~= '' and c.titre == Conversation.TITRE_PAR_DEFAUT then
        c.titre = etat.nom
    end
    local h = Historique.historique(etat)
    if h then
        Conversation.ajouterHistorique(c, 'historique', h.texte, h.pourClaude)
    end
    c.vu = Historique.vu(etat)
    return c
end

-- La conversation gardée d'une photo, reprise : si la photo a changé depuis qu'elle l'a vue (des
-- étapes de Claude faites ailleurs : l'autre fenêtre, Claude Desktop ; des reprises à la main),
-- l'élément « Depuis la dernière fois » ; rien de changé, rien d'ajouté. Ce qu'elle a vu se met à
-- jour, et se réécrit sur le disque s'il change. Une conversation d'avant le correctif, sans `vu`,
-- a vu la photo à sa dernière modification. Rend vrai si un complément est ajouté.
function Moteur.completerDepuis(c)
    if not (c and c.photo ~= nil and c.groupe == nil) then
        return false
    end
    local etat = Historique.lire(c.photo)
    if not etat then
        return false
    end
    local depuisLe = c.vu == nil and type(c.modifiee) == 'number' and os.date('%Y-%m-%d %H:%M', c.modifiee) or nil
    local d = Historique.depuis(etat, c.vu, depuisLe)
    local vu = Historique.vu(etat)
    local change = d ~= nil or not Historique.memeVu(c.vu, vu)
    c.vu = vu
    if d then
        Conversation.ajouterHistorique(c, 'depuis', d.texte, d.pourClaude)
    end
    if change then
        Moteur.reecrire(c)
    end
    return d ~= nil
end

-- Le résumé court du groupe de la sélection (Historique.groupe), en tête de la conversation `c`.
function Moteur.resumerGroupe(c)
    local g = Historique.lireGroupe()
    if g then
        local r = Historique.groupe(g)
        Conversation.ajouterHistorique(c, 'groupe', r.texte, r.pourClaude)
    end
end

-- La conversation de la photo `id` pour une demande qui ne la montre pas (la Demande rapide) : celle
-- que la fenêtre Claude montre si elle est à cette photo (gardée, ou neuve après « Repartir à
-- neuf »), sinon la plus récente gardée (Moteur.conversationDe), sinon une neuve avec son historique
-- (pas encore gardée). Rend la conversation, et vrai si elle vient d'être faite.
function Moteur.conversationPour(id, cle)
    local c = Moteur.courante
    if Conversation.dePhoto(c, id) and c.ecartee ~= true and not Conversation.estSeance(c) then
        return c, false
    end
    local gardee = Moteur.conversationDe(id)
    if gardee then
        return gardee, false
    end
    return Moteur.preparerPhoto(Conversation.nouvelle(), id, cle), true
end

-- (Renommer… et Supprimer…, Moteur.renommer et Moteur.supprimer, sont retirés au correctif 1.3.6 :
-- le titre est celui que Claude donne, et une conversation n'est jamais effacée.)

-- Le modèle et l'effort d'une demande : ceux donnés, sinon ceux des préférences (Gestionnaire de
-- modules externes) ; une valeur inconnue (préférences d'une autre version, faute de frappe)
-- retombe sur celle par défaut. Un autre modèle ou un autre effort que ceux du processus ouvert le
-- relance à la demande suivante, en reprenant la session (Moteur.envoyer).
function Moteur.modeleEtEffort(options)
    local prefs = Chemins.prefs()
    local modele = options and options.modele or prefs.modele
    local effort = options and options.effort or prefs.effort
    if not Consignes.modele(modele) then
        modele = Chemins.defauts.modele
    end
    if not Consignes.effort(effort) then
        effort = Chemins.defauts.effort
    end
    return modele, effort
end

-- Le processus de Claude Code d'une demande dans `c` (la fenêtre Claude et la Demande rapide : un
-- seul à la fois) : celui qui est ouvert s'il sert la même conversation, avec le même modèle, le
-- même effort et les mêmes consignes ; sinon il s'arrête, et un nouveau reprend la session de la
-- conversation (`--resume`, c.sessionID ; aucune pour une conversation neuve). Les deux fenêtres
-- donnent les mêmes consignes (Consignes.texte : les règles de la Demande rapide partent avec son
-- message) : une demande rapide puis une demande de la fenêtre Claude sur la même photo ne
-- relancent rien.
local function sessionPour(c, modele, effort, consignes)
    local s = Moteur.session
    if s and (s.conversation ~= c or s.modele ~= modele or s.effort ~= effort or s.consignes ~= consignes) then
        Moteur.arreterSession()
    end
    if not Moteur.session then
        local prefs = Chemins.prefs()
        Moteur.session = Session.nouvelle({
            idConversation = c.id, claude = prefs.cheminClaude, connecteur = prefs.cheminConnecteur,
            modele = modele, effort = effort, reprise = c.sessionID, travail = Chemins.atelier(),
            consignes = consignes,
        })
        Moteur.session.conversation = c
    end
    return Moteur.session
end

-- L'historique, le complément et le résumé joints à la demande en cours
-- (Conversation.historiquesAEnvoyer), marqués envoyés une fois la demande partie (session:envoyer
-- réussi), et vrai dès que Claude y répond (Moteur.traiter : GENRES_CLAUDE). Si la reprise de la
-- session échoue, ou si Claude Code s'arrête avant d'y répondre, ils redeviennent à envoyer
-- (Moteur.processusFini) : la demande suivante les rejoint.
Moteur.historiquesEnCours = nil
Moteur.reponduEnCours = false

-- Les événements de Claude lui-même (pas ceux de Claude Code : init, statut, limites, contrôle).
Moteur.GENRES_CLAUDE = { partiel = true, assistant = true, resultats = true, fin = true }

-- Marque envoyés les éléments joints à la demande qui vient de partir.
local function marquerEnvoyes(historiques)
    for _, e in ipairs(historiques) do
        e.envoye = true
    end
    Moteur.historiquesEnCours = #historiques > 0 and historiques or nil
    Moteur.reponduEnCours = false
end

-- La session de la conversation est perdue (Moteur.processusFini : la reprise a échoué) : Claude
-- repart de zéro, sans ce qui s'est dit ni fait avant. L'historique actuel de sa photo (ses étapes de
-- Claude, ses reprises à la main) s'ajoute alors à la conversation (sans ligne dans le fil depuis le
-- correctif 1.3.8 : Fil.HISTORIQUES_CACHES), et part avec la demande renvoyée. À appeler depuis une
-- tâche.
local function rejoindreHistorique(c)
    if not c.sessionPerdue then
        return
    end
    c.sessionPerdue = nil
    if c.photo == nil or c.groupe ~= nil then
        return
    end
    local etat = Historique.lire(c.photo)
    if not etat then
        return
    end
    local h = Historique.historique(etat)
    if h then
        Conversation.ajouterHistorique(c, 'historique', h.texte, h.pourClaude)
    end
    c.vu = Historique.vu(etat)
end

-- Envoie une demande dans la conversation ouverte. options : modele, effort (sinon ceux des
-- préférences), jointes (chemins d'images sur le disque), style (valeur d'un style de
-- Consignes.styles), affiche (ce que le fil montre de la demande, quand Claude en reçoit une plus
-- longue : « Obtenir », Consignes.obtenir). Rend true, ou false et la raison.
function Moteur.envoyer(texte, options)
    options = options or {}
    texte = Texte.nettoyer(texte)
    local jointes = options.jointes or {}
    if texte == '' and #jointes == 0 then
        return false, "Écrivez une demande avant d'envoyer."
    end
    if Moteur.travaille then
        return false, Moteur.CLAUDE_TRAVAILLE
    end
    local okBudget, niveau = pcall(Consommation.niveau)
    if okBudget and niveau == 'arret' then
        return false, string.format("Budget de la semaine atteint (%s jetons) : augmentez-le dans la fenêtre Consommation pour continuer.",
            Consommation.format(Consommation.charger().budgetSemaine))
    end
    Moteur.travaille = true
    Moteur.interruptionLe = nil
    Moteur.tourRapide, Moteur.selectionRapide = nil, nil
    -- La ligne d'état ne redit pas les photos du tour d'avant (posée avec la demande).
    Moteur.selectionTravail = nil
    local c = Moteur.courante or Conversation.nouvelle()
    Moteur.courante = c
    Moteur.enCours = c
    Moteur.historiquesEnCours, Moteur.reponduEnCours = nil, false

    local ok, erreur = LrTasks.pcall(function()
        local chemins, images = {}, {}
        for _, chemin in ipairs(jointes) do
            local nom, image = Images.joindre(chemin, Moteur.dossier(c))
            if not nom then
                error(image, 0)
            end
            chemins[#chemins + 1] = nom
            images[#images + 1] = image
        end
        if texte == '' then
            texte = #jointes > 1 and "Regarde les photos jointes." or "Regarde la photo jointe."
        end
        local style = Consignes.style(options.style)
        local info = Lightroom.photos()
        local contexte = Lightroom.contexte(info)
        rejoindreHistorique(c)
        -- L'historique de la photo et ce qui a changé depuis (ou le résumé du groupe), faits par la
        -- fenêtre : joints une seule fois, à la demande qui les suit (marqués envoyés une fois la
        -- demande partie).
        local historiques = Conversation.historiquesAEnvoyer(c)
        local message = Conversation.messagePourClaude(c, texte, contexte, Consignes.ligneStyle(options.style), historiques)
        local affiche = type(options.affiche) == 'string' and Texte.nettoyer(options.affiche) or ''
        Conversation.ajouterDemande(c, affiche ~= '' and affiche or texte, os.time(), chemins, style and style.definition and style.title or nil)
        Moteur.selectionTravail = info.selection
        -- Une conversation neuve est gardée à sa première demande ; celle d'un groupe, jamais.
        if c.groupe == nil and not dansListe(c) then
            table.insert(Moteur.conversations, 1, c)
        end
        trier()

        local modele, effort = Moteur.modeleEtEffort(options)
        local session = sessionPour(c, modele, effort, Consignes.texte)
        Moteur.debutTravail = os.time()
        Moteur.derniereActivite = os.time()
        enregistrer(c)
        Moteur.signaler('fil')
        -- Claude Code ou le connecteur introuvables : Session:lancer lève une erreur ici, et
        -- l'historique reste à envoyer.
        session:envoyer(message, images)
        marquerEnvoyes(historiques)
    end)
    if not ok then
        Moteur.travaille = false
        Moteur.enCours = nil
        Moteur.session = nil
        Conversation.ajouterNote(c, tostring(erreur))
        Journal.noter("Envoi impossible :", tostring(erreur))
        Moteur.signaler('fil')
        return false, tostring(erreur)
    end
    Moteur.demarrerBoucle()
    return true
end

-- La fenêtre Demande rapide (FenetreRapide.lua, demandée par Dany le 22 octobre 2026), depuis le
-- correctif 1.3.6 (« une photo, une conversation », décidé avec Dany le 25 octobre 2026) :
-- - une photo seule (case Autre photo cochée) : la demande part dans la conversation de la photo, la
--   même que la fenêtre Claude (Moteur.conversationPour), sans la montrer ; une photo sans
--   conversation en reçoit une, avec son historique, gardée sur le disque dès cette demande ; ce qui
--   a changé depuis que la conversation a vu la photo part aussi (Moteur.completerDepuis). Claude
--   reprend la session de la conversation (sessionPour). La demande et ce qui y répond sont marqués
--   `rapide` (le fil de la fenêtre Claude le dit : Fil.MENTION_RAPIDE) ; le titre reste le
--   provisoire, Claude en donne un à la première demande faite dans la fenêtre Claude
--   (Conversation.messagePourClaude) ;
-- - plusieurs photos, ou la case décochée : comme avant, une conversation neuve (`rapide`), jamais
--   gardée (ni sur le disque, `enregistrer`, ni parmi les conversations), avec le résumé court du
--   groupe ; ses images vont dans un dossier temporaire, effacé à la demande rapide suivante.
-- Les règles courtes de la Demande rapide partent avec le message (Consignes.rapide,
-- Consignes.rapidePhoto). Un seul Claude Code à la fois : refusé pendant que la fenêtre Claude
-- travaille (et Moteur.envoyer pendant une demande rapide, dès avant ses lectures du catalogue :
-- Moteur.RESERVE_RAPIDE). La fenêtre Demande rapide ne montre que
-- la réponse à sa demande (Moteur.reponseRapide). Rend la conversation, ou nil et la raison. À
-- appeler depuis une tâche.
Moteur.rapide = nil
-- L'élément de la dernière demande rapide (genre 'dany', dans Moteur.rapide), et la conversation
-- de la demande rapide en cours (nil hors d'elle) : ce qui y arrive est marqué `rapide`.
Moteur.demandeRapide = nil
Moteur.tourRapide = nil
-- La sélection (clé de Lightroom.photos) et la conversation de la dernière demande rapide, jusqu'à
-- la demande suivante de la fenêtre Claude : la fenêtre Claude, qui montre peut-être une autre
-- conversation, suit cette sélection après le travail, comme un choix de Dany
-- (Fenetre.suivreSelection).
Moteur.selectionRapide = nil

Moteur.RAPIDE_TRAVAILLE = "Claude travaille déjà : attendez la fin, ou arrêtez-le dans la fenêtre Claude."

-- Claude Code réservé pour une demande rapide pendant ses lectures du catalogue (la conversation de la
-- photo, son historique, le résumé du groupe), qui peuvent attendre : Moteur.travaille est posé
-- avant elles, et Moteur.tourRapide vaut ce repère jusqu'à ce que la conversation soit connue. La
-- fenêtre Claude n'envoie rien pendant ce temps (Moteur.envoyer, Moteur.montrer), ni ne prend la
-- sélection pour celle de sa conversation (Fenetre.suivreSelection) ; un processus au repos qui
-- s'arrête alors ne finit pas ce travail (Moteur.processusFini : Moteur.enCours).
Moteur.RESERVE_RAPIDE = { reserve = 'rapide' }

-- Rend Claude Code après une demande rapide qui n'est pas partie (refus, erreur de lecture).
local function libererRapide()
    Moteur.travaille = false
    Moteur.enCours = nil
    Moteur.tourRapide = nil
    Moteur.interruptionLe = nil
end

-- Marque `rapide` ce qui suit la demande rapide dans `c`, jusqu'à la demande suivante.
local function marquerRapide(c)
    local d = Moteur.demandeRapide
    local elements = c and c.elements or {}
    for i = #elements, 1, -1 do
        if elements[i] == d then
            for k = i + 1, #elements do
                if elements[k].genre == 'dany' then
                    break
                end
                elements[k].rapide = true
            end
            return
        end
    end
end

function Moteur.envoyerRapide(texte)
    texte = Texte.nettoyer(texte)
    if texte == '' then
        return nil, "Écrivez une demande avant d'envoyer."
    end
    if Moteur.travaille then
        return nil, Moteur.RAPIDE_TRAVAILLE
    end
    local okBudget, niveau = pcall(Consommation.niveau)
    if okBudget and niveau == 'arret' then
        return nil, "Budget de la semaine atteint : augmentez-le dans la fenêtre Consommation pour continuer."
    end
    -- Claude Code réservé avant les lectures (Moteur.RESERVE_RAPIDE).
    Moteur.travaille = true
    Moteur.interruptionLe = nil
    Moteur.enCours = nil
    Moteur.tourRapide = Moteur.RESERVE_RAPIDE
    Moteur.debutTravail = os.time()
    Moteur.selectionTravail = nil
    local info, photoSeule, c
    local okLu, erreurLue = LrTasks.pcall(function()
        -- Les conversations gardées, même si la fenêtre Claude ne s'est pas encore ouverte : celle
        -- de la photo s'y trouve.
        Moteur.charger()
        local avant = Moteur.rapide
        if avant and avant.rapide and avant.dossier then
            LrTasks.pcall(Fichiers.supprimer, avant.dossier)
        end
        info = Lightroom.photos()
        photoSeule = info.active ~= nil and (info.selection or 0) <= 1 and Chemins.prefs().nouvelleParPhoto == true
        if photoSeule then
            local neuve
            c, neuve = Moteur.conversationPour(info.active.id, info.cle)
            if not neuve then
                LrTasks.pcall(Moteur.completerDepuis, c)
            end
            c.cle = info.cle or c.cle
            rejoindreHistorique(c)
        else
            c = Conversation.nouvelle()
            c.rapide = true
            c.titreAuto = true
            c.dossier = LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'Rapide'), c.id)
            if info.groupe then
                LrTasks.pcall(Moteur.resumerGroupe, c)
            end
        end
    end)
    if not okLu then
        libererRapide()
        Journal.noter("Demande rapide impossible :", tostring(erreurLue))
        Moteur.signaler('rapide')
        return nil, tostring(erreurLue)
    end
    Moteur.rapide, Moteur.demandeRapide = c, nil
    Moteur.interruptionLe = nil
    Moteur.enCours = c
    Moteur.tourRapide = c
    Moteur.historiquesEnCours, Moteur.reponduEnCours = nil, false
    Moteur.selectionRapide = { cle = info.cle, conversation = c }
    local ok, erreur = LrTasks.pcall(function()
        local morceaux = {}
        local contexte = Lightroom.contexte(info)
        if contexte and contexte ~= '' then
            morceaux[#morceaux + 1] = contexte
        end
        morceaux[#morceaux + 1] = photoSeule and Consignes.rapidePhoto or Consignes.rapide
        -- L'historique de la photo et ce qui a changé depuis (ou le résumé du groupe) : joints une
        -- seule fois, comme dans la fenêtre Claude (Moteur.envoyer).
        local historiques = Conversation.historiquesAEnvoyer(c)
        for _, e in ipairs(historiques) do
            if type(e.pourClaude) == 'string' and e.pourClaude ~= '' then
                morceaux[#morceaux + 1] = e.pourClaude
            end
        end
        morceaux[#morceaux + 1] = texte
        Conversation.ajouterDemande(c, texte, os.time(), {})
        Moteur.selectionTravail = info.selection
        local demande = c.elements[#c.elements]
        demande.rapide = true
        Moteur.demandeRapide = demande
        -- La conversation de la photo est gardée dès cette demande ; une demande rapide jetable,
        -- jamais.
        if not c.rapide and not dansListe(c) then
            table.insert(Moteur.conversations, 1, c)
        end
        trier()
        local modele, effort = Moteur.modeleEtEffort()
        local session = sessionPour(c, modele, effort, Consignes.texte)
        Moteur.debutTravail = os.time()
        Moteur.derniereActivite = os.time()
        enregistrer(c)
        Moteur.signaler('rapide')
        -- Claude Code ou le connecteur introuvables : l'historique reste à envoyer (Moteur.envoyer).
        session:envoyer(table.concat(morceaux, '\n\n'), {})
        marquerEnvoyes(historiques)
    end)
    if not ok then
        Moteur.travaille = false
        Moteur.enCours = nil
        Moteur.session = nil
        if Moteur.demandeRapide then
            Conversation.ajouterNote(c, tostring(erreur))
            marquerRapide(c)
            Moteur.reecrire(c)
        end
        Moteur.tourRapide = nil
        Moteur.interruptionLe = nil
        Journal.noter("Demande rapide impossible :", tostring(erreur))
        Moteur.signaler('rapide')
        return nil, tostring(erreur)
    end
    Moteur.demarrerBoucle()
    return c
end

-- La réponse à la dernière demande rapide dans `c` : ses éléments (après la demande, jusqu'à la
-- demande suivante, faite dans la fenêtre Claude), et vrai si Claude y travaille encore. Sans
-- demande rapide connue, ceux d'après la dernière demande.
function Moteur.reponseRapide(c)
    local elements = type(c) == 'table' and c.elements or {}
    local d = Moteur.demandeRapide
    local debut = d == nil and 0 or nil
    for i = #elements, 1, -1 do
        if (d ~= nil and elements[i] == d) or (d == nil and elements[i].genre == 'dany') then
            debut = i
            break
        end
    end
    if not debut then
        return {}, false
    end
    local liste, derniere = {}, true
    for k = debut + 1, #elements do
        if elements[k].genre == 'dany' then
            derniere = false
            break
        end
        liste[#liste + 1] = elements[k]
    end
    return liste, Moteur.travaille and Moteur.enCours == c and derniere
end

-- Oublie la dernière demande rapide (une autre photo ou une autre sélection dans Lightroom,
-- FenetreRapide.suivreSelection ; d'abord le bouton ♻, du 22 au 24 octobre 2026). Une demande
-- jetable (plusieurs photos) : sa session de Claude Code s'arrête, son dossier temporaire s'efface.
-- La conversation d'une photo reste telle quelle, gardée, avec son processus (la fenêtre Claude la
-- montre peut-être) ; la fenêtre Demande rapide n'en montre plus rien. Refusé pendant que Claude y
-- travaille. Rend vrai, ou nil et la raison. À appeler depuis une tâche.
function Moteur.oublierRapide()
    local c = Moteur.rapide
    if not c then
        return true
    end
    if Moteur.travaille and Moteur.enCours == c then
        return nil, "Claude travaille sur la demande : attendez la fin."
    end
    if c.rapide then
        if Moteur.session and Moteur.session.conversation == c then
            Moteur.arreterSession()
        end
        if c.dossier then
            LrTasks.pcall(Fichiers.supprimer, c.dossier)
        end
    end
    Moteur.rapide, Moteur.demandeRapide = nil, nil
    return true
end

-- Demande à Claude d'arrêter ; sans réponse après quelques secondes, le processus est arrêté.
function Moteur.interrompre()
    if Moteur.travaille and Moteur.session then
        Moteur.interruptionLe = os.time()
        Moteur.session:interrompre()
        Moteur.signaler('fil')
    end
end

-- Réponses à la proposition en attente.
function Moteur.repondre(acceptee)
    local c = Moteur.courante
    local p = c and Conversation.propositionEnAttente(c)
    if not p or Moteur.travaille then
        return false
    end
    Conversation.decider(c, p.id, acceptee)
    return Moteur.envoyer(acceptee and Consignes.accepter or Consignes.refuser)
end

function Moteur.ajuster(texte)
    local c = Moteur.courante
    local p = c and Conversation.propositionEnAttente(c)
    texte = Texte.nettoyer(texte)
    if not p or Moteur.travaille or texte == '' then
        return false
    end
    p.etat = 'ajustee'
    return Moteur.envoyer(Consignes.ajuster(texte))
end

-- Lecture de la sortie de Claude Code ---------------------------------------------------------

-- Applique un événement à la conversation de la session.
function Moteur.traiter(c, ev)
    Moteur.derniereActivite = os.time()
    if ev.genre == 'limites' then
        Moteur.limites = ev
        LrTasks.pcall(Consommation.releve, ev)
        return
    elseif ev.genre == 'statut' then
        Moteur.statut = ev.statut
        return
    elseif ev.genre == 'init' then
        Moteur.serveurs = ev.serveurs
        local etat = ev.serveurs and ev.serveurs[Session.SERVEUR]
        if etat and etat ~= 'connected' then
            Conversation.ajouterNote(c, "Le connecteur MCP-Développeur n'a pas démarré (" .. etat .. ") : Claude ne verra pas Lightroom. Vérifiez son chemin dans le Gestionnaire de modules externes.")
        end
    end
    Conversation.appliquer(c, ev, os.time(), function(image)
        return Images.enregistrer(image, Moteur.dossier(c))
    end)
    -- Ce qui répond à une demande rapide est marqué (le fil de la fenêtre Claude le dit).
    if Moteur.tourRapide == c then
        marquerRapide(c)
    end
    -- Claude répond à la demande en cours : il a reçu ce qui y était joint.
    if Moteur.enCours == c and Moteur.GENRES_CLAUDE[ev.genre] then
        Moteur.reponduEnCours = true
    end
    if ev.genre == 'fin' then
        Moteur.compter(c, ev)
        if Moteur.session and Moteur.session.conversation == c then
            Moteur.travaille = false
            Moteur.finTravail = os.time()
            Moteur.enCours = nil
            Moteur.interruptionLe = nil
            Moteur.tourRapide = nil
            Moteur.historiquesEnCours = nil
        end
        LrTasks.pcall(Moteur.noterVu, c)
        trier()
        enregistrer(c)
    end
end

-- Compte les jetons d'une demande terminée (fenêtre Consommation).
function Moteur.compter(c, ev)
    local apercu = ''
    for i = #c.elements, 1, -1 do
        if c.elements[i].genre == 'dany' then
            apercu = Texte.raccourcir(Texte.lignes(Texte.nettoyer(c.elements[i].texte))[1] or '', 80)
            break
        end
    end
    local modele = ev.modele or (Moteur.session and Moteur.session.modele) or ''
    LrTasks.pcall(Consommation.ajouter, { date = os.time(), modele = modele, usage = ev.usage or {}, apercu = apercu, dureeMs = ev.dureeMs })
end

-- Le processus s'est arrêté : si une demande était en cours dans sa conversation, le dire dans le
-- fil. Un processus au repos qui s'arrête pendant qu'une demande rapide réserve Claude Code
-- (Moteur.RESERVE_RAPIDE, Moteur.enCours encore vide) ne finit pas ce travail. L'historique joint à
-- la demande redevient à envoyer si la reprise de la session a échoué ou si Claude n'y a pas répondu ;
-- une session perdue fera joindre l'historique actuel de la photo à la demande renvoyée
-- (rejoindreHistorique).
function Moteur.processusFini(s, code, erreurs)
    local c = s.conversation
    if Moteur.session == s then
        Moteur.session = nil
    end
    if Moteur.travaille and c and c == Moteur.enCours then
        Moteur.travaille = false
        Moteur.finTravail = os.time()
        Moteur.enCours = nil
        Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = '' }, os.time())
        local repriseEchouee = not Moteur.interruptionLe and s.reprise and erreurs and erreurs:find('No conversation found', 1, true) ~= nil
        if Moteur.historiquesEnCours and (repriseEchouee or not Moteur.reponduEnCours) then
            for _, e in ipairs(Moteur.historiquesEnCours) do
                e.envoye = false
            end
        end
        Moteur.historiquesEnCours = nil
        if Moteur.interruptionLe then
            Conversation.ajouterNote(c, "Interrompu à votre demande.")
        elseif repriseEchouee then
            -- La session reprise n'existe plus (dossier de travail effacé) : la suite repart à neuf,
            -- avec l'historique actuel de la photo.
            c.sessionID = nil
            c.sessionPerdue = true
            Conversation.ajouterNote(c, "La session Claude Code de cette conversation est introuvable : renvoyez la demande, elle partira d'une nouvelle session (Claude ne se souviendra pas du début).")
        else
            local detail = erreurs ~= '' and erreurs or ("code " .. tostring(code))
            Conversation.ajouterNote(c, "Claude Code s'est arrêté avant de répondre : " .. detail)
        end
        if Moteur.tourRapide == c then
            marquerRapide(c)
        end
        Moteur.tourRapide = nil
        Moteur.interruptionLe = nil
        LrTasks.pcall(Moteur.noterVu, c)
        enregistrer(c)
    end
end

-- Un tour de la boucle : lit ce qui est arrivé et le range.
function Moteur.tic()
    local s = Moteur.session
    if not s then
        return
    end
    local c = s.conversation
    local lignes, fini, code, erreurs = s:lire()
    local change = false
    for _, ligne in ipairs(lignes) do
        local ev = Evenements.lire(ligne)
        if ev and ev.genre ~= 'ignore' then
            Moteur.traiter(c, ev)
            change = true
        end
    end
    if fini then
        Moteur.processusFini(s, code, erreurs or '')
        change = true
    end
    local maintenant = os.time()
    if Moteur.travaille and Moteur.interruptionLe and maintenant - Moteur.interruptionLe > Moteur.DELAI_INTERRUPTION and Moteur.session then
        Moteur.session:arreter()
    end
    local prefs = Chemins.prefs()
    if Moteur.session and not Moteur.travaille and not Moteur.session.arretDemande
        and maintenant - Moteur.derniereActivite > (tonumber(prefs.inactivite) or 15) * 60 then
        Journal.noter("Claude Code fermé après inactivité")
        Moteur.session:arreter()
    end
    if change then
        if Moteur.travaille and c and maintenant - (Moteur.enregistreLe or 0) >= Moteur.DELAI_ENREGISTREMENT then
            enregistrer(c)
        end
        Moteur.signaler('fil')
    end
end

-- La boucle de lecture tourne tant qu'un processus est ouvert.
function Moteur.demarrerBoucle()
    if Moteur.boucle then
        return
    end
    Moteur.boucle = true
    LrTasks.startAsyncTask(function()
        while Moteur.boucle do
            local ok, erreur = LrTasks.pcall(Moteur.tic)
            if not ok then
                Journal.noter("Erreur de lecture :", tostring(erreur))
            end
            if not Moteur.session and not Moteur.travaille then
                Moteur.boucle = false
            else
                LrTasks.sleep(Moteur.travaille and 0.25 or 1)
            end
        end
    end)
end

-- « Claude travaille… · 3 outils faits · 1 min 05 » (vide s'il ne travaille pas), compté dans
-- la conversation qui travaille. `vue` : la conversation montrée par la fenêtre qui affiche ce
-- texte (nil : la conversation ouverte ; false : aucune, une séance sans conversation) ; si
-- Claude travaille ailleurs, le texte dit où (une autre conversation, ou la Demande rapide).
function Moteur.texteTravail(tic, vue)
    if not Moteur.travaille then
        return ''
    end
    local morceaux = { "Claude travaille" .. string.rep('.', (tic or 0) % 4) }
    if Moteur.interruptionLe then
        morceaux[1] = "Arrêt demandé" .. string.rep('.', (tic or 0) % 4)
    end
    if vue == nil then
        vue = Moteur.courante
    end
    if Moteur.enCours and Moteur.enCours ~= vue then
        morceaux[#morceaux + 1] = Moteur.tourRapide == Moteur.enCours and "pour la Demande rapide" or "dans une autre conversation"
    end
    local c = Moteur.enCours or Moteur.courante
    local n = c and Conversation.outilsFaits(c) or 0
    if n > 0 then
        morceaux[#morceaux + 1] = n == 1 and "1 outil fait" or (n .. " outils faits")
    end
    local duree = os.time() - (Moteur.debutTravail or os.time())
    morceaux[#morceaux + 1] = duree >= 60 and string.format("%d min %02d", math.floor(duree / 60), duree % 60) or (duree .. " s")
    local cible = c and Moteur.texteCible(Conversation.photosEnCours(c), Moteur.selectionTravail)
    if cible then
        morceaux[#morceaux + 1] = cible
    end
    return table.concat(morceaux, " · ")
end

-- Sur quelle photo de la sélection Claude travaille (demandé par Dany le 26 octobre 2026) : « photo 2
-- de 3 : XH2S8390.RAF », « photos 31 à 60 de 951 », « 4 photos de 12 » (rangs qui ne se suivent
-- pas), d'après `cible` (Conversation.photosEnCours) et `total`, la sélection de la demande (nil
-- tant que la demande n'est pas partie : rien) ; une planche contact donne son propre total. Rien
-- pour une photo seule ; sans « de N » au-delà (une copie que Claude a faite). Le nom du fichier se
-- lit dans le catalogue (Lightroom.nomDePhoto).
function Moteur.texteCible(cible, total)
    if not cible or not total then
        return nil
    end
    total = cible.total or total
    if total <= 1 then
        return nil
    end
    local de = cible.dernier <= total and (" de " .. Texte.nombre(total)) or ''
    if cible.id then
        local nom = Lightroom.nomDePhoto(cible.id)
        return "photo " .. Texte.nombre(cible.premier) .. de .. (nom and (" : " .. nom) or '')
    end
    if cible.dernier - cible.premier + 1 == cible.nombre then
        return "photos " .. Texte.nombre(cible.premier) .. " à " .. Texte.nombre(cible.dernier) .. de
    end
    return Texte.nombre(cible.nombre) .. " photos" .. de
end

-- « Forfait : 5 h 23 % · semaine 41 % » d'après le dernier relevé de Claude Code.
function Moteur.texteForfait()
    local ok, registre = pcall(Consommation.charger)
    local l = Moteur.limites or (ok and registre.limites) or nil
    -- À 80 % du budget de la semaine, la part utilisée s'ajoute au relevé.
    local part
    if ok and (registre.budgetSemaine or 0) > 0 and Consommation.niveau() ~= 'normal' then
        part = math.floor(Consommation.part() * 100 + 0.5)
    end
    local budget = part and string.format(" · budget %d %%", part) or ''
    if not l or (not l.cinqHeures and not l.semaine) then
        return part and string.format("Budget de la semaine : %d %%", part) or ''
    end
    local morceaux = {}
    if l.cinqHeures then
        morceaux[#morceaux + 1] = string.format("5 h %d %%", math.floor(l.cinqHeures * 100 + 0.5))
    end
    if l.semaine then
        morceaux[#morceaux + 1] = string.format("semaine %d %%", math.floor(l.semaine * 100 + 0.5))
    end
    return "Forfait : " .. table.concat(morceaux, " · ") .. budget
end

return Moteur
