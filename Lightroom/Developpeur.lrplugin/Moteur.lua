-- Moteur.lua : les conversations, celle qui est ouverte dans la fenêtre Claude, et le processus
-- Claude Code qui répond. Indépendant des fenêtres : si on les ferme pendant que Claude travaille,
-- le travail continue et se retrouve à la réouverture. Les fenêtres s'abonnent par Moteur.abonner.
-- Une séance de notation (fenêtre « Claude · Séance de notation ») a sa propre conversation
-- (genre 'notation', Moteur.nouvelleSeance), jamais ouverte comme courante. Un seul processus et
-- une seule demande à la fois : passer d'une conversation à l'autre relance Claude Code en
-- reprenant la session de la conversation visée (`--resume`).
-- Les fonctions qui attendent (envoyer, boucle, charger) s'appellent depuis une tâche.

local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Consommation = require 'Consommation'
local Conversation = require 'Conversation'
local Evenements = require 'Evenements'
local Images = require 'Images'
local Journal = require 'Journal'
local Lightroom = require 'Lightroom'
local Session = require 'Session'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

local Moteur = {
    conversations = {},
    -- La conversation ouverte dans la fenêtre Claude (jamais une séance de notation).
    courante = nil,
    -- La conversation de la demande en cours (la courante ou une séance), nil sans demande.
    enCours = nil,
    session = nil,
    travaille = false,
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
    local ok, erreur = LrTasks.pcall(Stockage.enregistrer, c)
    if not ok then
        Journal.noter("Enregistrement impossible :", c.id, tostring(erreur))
    end
    Moteur.enregistreLe = os.time()
end

-- La plus récente des conversations de retouche (les séances de notation ne s'ouvrent pas dans
-- la fenêtre Claude).
local function plusRecente()
    for _, c in ipairs(Moteur.conversations) do
        if not Conversation.estSeance(c) then
            return c
        end
    end
    return nil
end

-- Charge les conversations (une seule fois). La plus récente s'ouvre.
function Moteur.charger()
    if Moteur.charge then
        return
    end
    Moteur.charge = true
    local ok, liste = LrTasks.pcall(Stockage.charger)
    Moteur.conversations = ok and liste or {}
    Moteur.courante = plusRecente() or Conversation.nouvelle()
end

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

-- Une conversation par son identifiant (séances de notation comprises), nil sinon.
function Moteur.conversation(id)
    return Moteur.trouver(id)
end

-- La conversation d'une séance de notation, sans changer la conversation ouverte de la fenêtre
-- Claude. options : titre, seance (identifiant de la séance dans Notation.lua : la conversation
-- déjà faite pour elle est reprise, après une relance de Lightroom par exemple). Elle est rangée
-- avec les autres, et sur le disque à sa première demande. Rend la conversation.
function Moteur.nouvelleSeance(options)
    options = options or {}
    Moteur.charger()
    if options.seance ~= nil then
        for _, c in ipairs(Moteur.conversations) do
            if Conversation.estSeance(c) and tostring(c.seance) == tostring(options.seance) then
                return c
            end
        end
    end
    local c = Conversation.nouvelleSeance(options.titre, options.seance)
    table.insert(Moteur.conversations, 1, c)
    return c
end

-- La raison d'un refus pendant que Claude travaille, et où, si c'est ailleurs que dans la
-- conversation visée.
local function raisonOccupe(visee)
    local ailleurs = Moteur.enCours ~= nil and Moteur.enCours ~= visee
    if ailleurs and Conversation.estSeance(Moteur.enCours) then
        return "Claude travaille dans la séance de notation : attendez la fin, ou cliquez Arrêter."
    elseif ailleurs then
        return "Claude travaille dans la fenêtre Claude : attendez la fin, ou cliquez Arrêter."
    end
    return "Claude travaille encore : attendez la fin, ou cliquez Arrêter."
end

function Moteur.arreterSession()
    if Moteur.session then
        Moteur.session:arreter()
        Moteur.session = nil
    end
end

-- Ouvre une autre conversation (refusé pendant que Claude travaille, et pour une séance de
-- notation, qui se montre dans sa propre fenêtre).
function Moteur.ouvrir(id)
    if Moteur.travaille then
        return false, "Claude travaille : attendez la fin, ou cliquez Arrêter."
    end
    local c = Moteur.trouver(id)
    if Conversation.estSeance(c) then
        return false, "Cette conversation est celle d'une séance de notation : elle se montre dans la fenêtre Séance de notation."
    end
    if not c or c == Moteur.courante then
        return c ~= nil
    end
    Moteur.arreterSession()
    Moteur.courante = c
    Moteur.signaler('conversation')
    return true
end

function Moteur.nouvelle()
    if Moteur.travaille then
        return false, "Claude travaille : attendez la fin, ou cliquez Arrêter."
    end
    if Moteur.courante and #Moteur.courante.elements == 0 then
        return true
    end
    Moteur.arreterSession()
    Moteur.courante = Conversation.nouvelle()
    Moteur.signaler('conversation')
    return true
end

function Moteur.renommer(id, titre)
    local c = Moteur.trouver(id)
    if c and Conversation.renommer(c, titre) then
        if #c.elements > 0 then
            enregistrer(c)
        end
        Moteur.signaler('liste')
        return true
    end
    return false
end

-- À la corbeille du Finder.
function Moteur.supprimer(id)
    local c = Moteur.trouver(id)
    if not c then
        return false
    end
    if Moteur.travaille and c == (Moteur.enCours or Moteur.courante) then
        return false, "Claude travaille dans cette conversation."
    end
    -- Supprimer la conversation ouverte ferme Claude Code : pas pendant une demande ailleurs.
    if Moteur.travaille and c == Moteur.courante then
        return false, raisonOccupe(c)
    end
    for i, x in ipairs(Moteur.conversations) do
        if x == c then
            table.remove(Moteur.conversations, i)
            break
        end
    end
    if Moteur.session and Moteur.session.conversation == c then
        Moteur.arreterSession()
    end
    if c == Moteur.courante then
        Moteur.arreterSession()
        Moteur.courante = plusRecente() or Conversation.nouvelle()
    end
    LrTasks.pcall(Stockage.supprimer, id)
    Moteur.signaler('conversation')
    return true
end

-- Le modèle choisi vaut pour la demande suivante (Claude Code est relancé avec, en reprenant la
-- session).
function Moteur.changerModele(modele)
    local prefs = Chemins.prefs()
    prefs.modele = modele
    if Moteur.session and not Moteur.travaille and Moteur.session.modele ~= modele then
        Moteur.arreterSession()
    end
end

-- Envoie une demande dans la conversation ouverte. options : modele, jointes (chemins d'images
-- sur le disque), style (valeur d'un style de Consignes.styles), conversation (une autre
-- conversation, ou son identifiant : celle d'une séance de notation ; la conversation ouverte ne
-- change pas), contexte (texte qui remplace la ligne « [Lightroom : …] » de la photo active).
-- Rend true, ou false et la raison.
function Moteur.envoyer(texte, options)
    options = options or {}
    texte = Texte.nettoyer(texte)
    local jointes = options.jointes or {}
    if texte == '' and #jointes == 0 then
        return false, "Écrivez une demande avant d'envoyer."
    end
    local visee = options.conversation
    if visee ~= nil and type(visee) ~= 'table' then
        visee = Moteur.trouver(visee)
        if not visee then
            return false, "Cette conversation est introuvable."
        end
    end
    if Moteur.travaille then
        return false, raisonOccupe(visee or Moteur.courante)
    end
    local okBudget, niveau = pcall(Consommation.niveau)
    if okBudget and niveau == 'arret' then
        return false, string.format("Budget de la semaine atteint (%s jetons) : augmentez-le dans la fenêtre Consommation pour continuer.",
            Consommation.format(Consommation.charger().budgetSemaine))
    end
    Moteur.travaille = true
    Moteur.interruptionLe = nil
    local c = visee
    if not c then
        c = Moteur.courante or Conversation.nouvelle()
        Moteur.courante = c
    end
    Moteur.enCours = c

    local ok, erreur = LrTasks.pcall(function()
        local prefs = Chemins.prefs()
        local chemins, images = {}, {}
        for _, chemin in ipairs(jointes) do
            local nom, image = Images.joindre(chemin, Stockage.dossier(c.id))
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
        local contexte = options.contexte
        if contexte == nil then
            contexte = Lightroom.contexte(Lightroom.photos())
        end
        local message = Conversation.messagePourClaude(c, texte, contexte, Consignes.ligneStyle(options.style))
        Conversation.ajouterDemande(c, texte, os.time(), chemins, style and style.definition and style.title or nil)
        if not dansListe(c) then
            table.insert(Moteur.conversations, 1, c)
        end
        trier()

        local modele = options.modele or prefs.modele
        if Moteur.session and (Moteur.session.conversation ~= c or Moteur.session.modele ~= modele) then
            Moteur.arreterSession()
        end
        if not Moteur.session then
            Moteur.session = Session.nouvelle({
                idConversation = c.id, claude = prefs.cheminClaude, connecteur = prefs.cheminConnecteur,
                modele = modele, reprise = c.sessionID, travail = Chemins.atelier(), consignes = Consignes.pour(c),
            })
            Moteur.session.conversation = c
        end
        Moteur.debutTravail = os.time()
        Moteur.derniereActivite = os.time()
        enregistrer(c)
        Moteur.signaler('fil')
        Moteur.session:envoyer(message, images)
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
        return Images.enregistrer(image, Stockage.dossier(c.id))
    end)
    if ev.genre == 'fin' then
        Moteur.compter(c, ev)
        if Moteur.session and Moteur.session.conversation == c then
            Moteur.travaille = false
            Moteur.enCours = nil
            Moteur.interruptionLe = nil
        end
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

-- Le processus s'est arrêté : si une demande était en cours, le dire dans le fil.
function Moteur.processusFini(s, code, erreurs)
    local c = s.conversation
    if Moteur.session == s then
        Moteur.session = nil
    end
    if Moteur.travaille and c then
        Moteur.travaille = false
        Moteur.enCours = nil
        Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = '' }, os.time())
        if Moteur.interruptionLe then
            Conversation.ajouterNote(c, "Interrompu à votre demande.")
        elseif s.reprise and erreurs and erreurs:find('No conversation found', 1, true) then
            -- La session reprise n'existe plus (dossier de travail effacé) : la suite repart à neuf.
            c.sessionID = nil
            Conversation.ajouterNote(c, "La session Claude Code de cette conversation est introuvable : renvoyez la demande, elle partira d'une nouvelle session (Claude ne se souviendra pas du début).")
        else
            local detail = erreurs ~= '' and erreurs or ("code " .. tostring(code))
            Conversation.ajouterNote(c, "Claude Code s'est arrêté avant de répondre : " .. detail)
        end
        Moteur.interruptionLe = nil
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
-- texte (la conversation ouverte par défaut) ; si Claude travaille ailleurs, le texte dit où.
function Moteur.texteTravail(tic, vue)
    if not Moteur.travaille then
        return ''
    end
    local morceaux = { "Claude travaille" .. string.rep('.', (tic or 0) % 4) }
    if Moteur.interruptionLe then
        morceaux[1] = "Arrêt demandé" .. string.rep('.', (tic or 0) % 4)
    end
    vue = vue or Moteur.courante
    if Moteur.enCours and Moteur.enCours ~= vue then
        morceaux[#morceaux + 1] = Conversation.estSeance(Moteur.enCours) and "dans la séance de notation" or "dans la fenêtre Claude"
    end
    local c = Moteur.enCours or Moteur.courante
    local n = c and Conversation.outilsFaits(c) or 0
    if n > 0 then
        morceaux[#morceaux + 1] = n == 1 and "1 outil fait" or (n .. " outils faits")
    end
    local duree = os.time() - (Moteur.debutTravail or os.time())
    morceaux[#morceaux + 1] = duree >= 60 and string.format("%d min %02d", math.floor(duree / 60), duree % 60) or (duree .. " s")
    return table.concat(morceaux, " · ")
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
