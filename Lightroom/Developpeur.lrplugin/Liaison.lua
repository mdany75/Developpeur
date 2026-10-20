-- Liaison.lua : les deux prises réseau qui relient le module au serveur MCP « mcp-developpeur ».
--
-- LrSocket ne fonctionne que dans un sens par prise : Lightroom écoute sur 127.0.0.1, reçoit
-- les commandes sur PORT_COMMANDES et renvoie les réponses sur PORT_REPONSES. Chaque message
-- est une ligne JSON :
--   commande → {"id": 7, "command": "apercu", "params": {…}}
--   réponse  ← {"id": 7, "result": {…}}  ou  {"id": 7, "error": "message"}
-- Le serveur ouvre une connexion par commande puis la ferme : plusieurs sessions de Claude
-- (Claude Desktop, Claude Code) peuvent ainsi se succéder.
--
-- La prise des réponses ne lit jamais : elle ne voit pas le serveur partir et resterait
-- accrochée à une connexion morte. Quand la prise des commandes se ferme, on la ferme donc et
-- on en ouvre une nouvelle (reconnect() sur une prise d'envoi bloque Lightroom, comme l'a
-- constaté le module MIDI2LR).
-- Les commandes elles-mêmes sont réparties par Commandes.lua ; l'état est affiché par Suivi.lua.

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrSocket = import 'LrSocket'
local LrTasks = import 'LrTasks'

local Json = require 'Json'

local Liaison = {
    VERSION = '1.1',
    PORT_COMMANDES = 54770,
    PORT_REPONSES = 54771,

    actif = false,
    pause = false,
    reponsesConnectee = false,
    erreur = nil,
    generation = 0,
    dernierEchange = nil,

    journal = {},
    -- Photo de chaque ligne du journal (ou false), pour la sélectionner d'un clic dans la fenêtre de suivi.
    journalPhotos = {},
    -- Dernière retouche, affichée dans la fenêtre de suivi.
    dernierePhotoId = nil,
    dernierePhoto = nil,
    derniersReglages = nil,

    -- Fonction appelée à chaque changement d'état (fenêtre de suivi ouverte).
    observateur = nil,

    -- Accord véritable (préférence « Confirmer dans Lightroom ») : la proposition qui attend la
    -- réponse de l'utilisateur ({outil, etape, detail, le}), et sa réponse ({accepte, le}).
    propositionEnAttente = nil,
    accord = nil,
    -- Début du refus d'une écriture qui attend l'accord dans la fenêtre de suivi : la proposition
    -- y est déjà notée, le journal ne la redit pas comme un refus.
    EN_ATTENTE = "« Confirmer dans Lightroom » est actif",

    -- Photo active signalée au serveur avec la dernière réponse (identifiant), pour ne signaler que
    -- les vrais changements : un aperçu ou un débruitage qui affiche une autre photo puis remet la
    -- vue n'en est pas un.
    derniereActive = nil,
}

local MAX_JOURNAL = 12
local ESSAIS_MAX = 5
local ATTENTE_REPONSES = 3

local function heure(temps)
    return LrDate.timeToUserFormat(temps, '%H:%M:%S')
end

function Liaison.texteEtat()
    if not Liaison.actif then
        return "Liaison arrêtée"
    end
    if Liaison.erreur then
        return "Liaison en erreur : " .. Liaison.erreur
    end
    local texte = "Liaison active, prête pour Claude"
    if Liaison.dernierEchange then
        texte = texte .. " (dernier échange à " .. heure(Liaison.dernierEchange) .. ")"
    end
    if Liaison.pause then
        texte = texte .. " — en pause : Claude peut regarder, pas retoucher"
    end
    return texte
end

function Liaison.signaler()
    if Liaison.observateur then
        pcall(Liaison.observateur)
    end
end

-- Journal du module sur disque : ~/Library/Logs/Developpeur/
-- module.log, gardé sous 1 Mo (l'ancien devient module.log.1). Pour comprendre après coup un échec
-- (fenêtre de suivi fermée, Lightroom relancé). Un journal qui ne s'écrit pas ne bloque rien.
Liaison.TAILLE_JOURNAL = 1048576

function Liaison.cheminJournal()
    local dossier = LrPathUtils.getStandardFilePath('home')
    for _, nom in ipairs({ 'Library', 'Logs', 'Developpeur' }) do
        dossier = LrPathUtils.child(dossier, nom)
    end
    return dossier, LrPathUtils.child(dossier, 'module.log')
end

local function ecrireJournal(ligne)
    pcall(function()
        local dossier, chemin = Liaison.cheminJournal()
        LrFileUtils.createAllDirectories(dossier)
        local attributs = LrFileUtils.fileAttributes and LrFileUtils.fileAttributes(chemin)
        if type(attributs) == 'table' and (tonumber(attributs.fileSize) or 0) > Liaison.TAILLE_JOURNAL then
            local ancien = chemin .. '.1'
            if LrFileUtils.exists(ancien) then
                LrFileUtils.delete(ancien)
            end
            LrFileUtils.move(chemin, ancien)
        end
        local fichier = io.open(chemin, 'a')
        if fichier then
            fichier:write(LrDate.timeToUserFormat(LrDate.currentTime(), '%Y-%m-%d %H:%M:%S') .. "  " .. ligne .. "\n")
            fichier:close()
        end
    end)
end

-- Une ligne du journal (fenêtre de suivi et fichier) ; photo : l'identifiant de la photo qu'elle
-- concerne, pour la sélectionner d'un clic.
function Liaison.noter(texte, photo)
    table.insert(Liaison.journal, heure(LrDate.currentTime()) .. "  " .. texte)
    table.insert(Liaison.journalPhotos, photo or false)
    while #Liaison.journal > MAX_JOURNAL do
        table.remove(Liaison.journal, 1)
        table.remove(Liaison.journalPhotos, 1)
    end
    ecrireJournal(texte)
    Liaison.signaler()
end

-- Une proposition attend l'accord de l'utilisateur dans la fenêtre de suivi (ouverte pour lui).
function Liaison.demanderAccord(outil, etape, detail)
    Liaison.propositionEnAttente = { outil = outil, etape = etape, detail = detail, le = LrDate.currentTime() }
    Liaison.accord = nil
    Liaison.noter("Proposition en attente de votre accord : " .. tostring(etape or outil))
    local ok, Suivi = pcall(require, 'Suivi')
    if ok and type(Suivi) == 'table' and Suivi.afficher then
        pcall(Suivi.afficher)
    end
end

-- Réponse de l'utilisateur à la proposition en attente (boutons de la fenêtre de suivi).
function Liaison.repondreProposition(accepte)
    Liaison.accord = { accepte = accepte == true, le = LrDate.currentTime() }
    local etape = Liaison.propositionEnAttente and Liaison.propositionEnAttente.etape
    Liaison.propositionEnAttente = nil
    Liaison.noter((accepte and "Proposition acceptée" or "Proposition refusée") .. (etape and (" : " .. tostring(etape)) or ""))
end

-- Retour visuel d'une écriture de Claude (préférence retourVisuel) : un message bref au centre de
-- l'écran, même fenêtre de suivi fermée.
function Liaison.retourVisuel(texte)
    local ok, Preferences = pcall(require, 'Preferences')
    if ok and Preferences.lire().retourVisuel then
        pcall(LrDialogs.showBezel, texte, 1.5)
    end
end

-- Message d'erreur lisible : sans le « Fichier.lua:123: » des erreurs de Lua.
function Liaison.messageErreur(erreur)
    local texte = tostring(erreur)
    return (texte:gsub('^[^\n]-%.lua:%d+: ', ''))
end

-- Appelée depuis une tâche asynchrone. Le serveur se connecte à la prise des réponses juste
-- avant d'envoyer sa commande : on laisse à Lightroom le temps de l'accepter.
function Liaison.repondre(objet)
    local attente = 0
    while not Liaison.reponsesConnectee and attente < ATTENTE_REPONSES do
        LrTasks.sleep(0.1)
        attente = attente + 0.1
    end
    local prise = Liaison.prise
    if prise and Liaison.reponsesConnectee then
        if Liaison.photoActiveChangee then
            Liaison.photoActiveChangee = false
            local id, fichier = Liaison.photoActive()
            if id ~= Liaison.derniereActive then
                Liaison.derniereActive = id
                objet.evenements = { photo_active = true, id = id or Json.null, fichier = fichier or Json.null }
            end
        end
        prise:send(Json.encode(objet) .. "\n")
    end
end

-- Identifiant et nom de la photo active (nil sans photo active).
function Liaison.photoActive()
    local ok, id, fichier = LrTasks.pcall(function()
        local photo = LrApplication.activeCatalog():getTargetPhoto()
        if not photo then
            return nil, nil
        end
        local nom = photo:getFormattedMetadata('fileName') or ''
        local copie = photo:getFormattedMetadata('copyName')
        if type(copie) == 'string' and copie ~= '' then
            nom = nom .. " (" .. copie .. ")"
        end
        return photo.localIdentifier, nom
    end)
    if not ok then
        return nil, nil
    end
    return id, fichier
end

-- Une commande reçue : traitée dans sa propre tâche (elle peut attendre un rendu ou
-- l'accès en écriture au catalogue), puis la réponse part avec le même identifiant.
function Liaison.recevoir(message)
    LrTasks.startAsyncTask(function()
        local lu, requete = pcall(Json.decode, message)
        if not lu or type(requete) ~= 'table' or type(requete.command) ~= 'string' then
            Liaison.noter("Message illisible ignoré")
            return
        end
        Liaison.dernierEchange = LrDate.currentTime()
        local Commandes = require 'Commandes'
        local params = type(requete.params) == 'table' and requete.params or {}
        local ok, resultat = LrTasks.pcall(Commandes.executer, requete.command, params)
        if ok then
            Liaison.repondre({ id = requete.id, result = resultat })
        else
            local texte = Liaison.messageErreur(resultat)
            if requete.command ~= 'ping' and texte:sub(1, #Liaison.EN_ATTENTE) ~= Liaison.EN_ATTENTE then
                Liaison.noter("Refusé : " .. texte)
            end
            Liaison.repondre({ id = requete.id, error = texte })
        end
        Liaison.signaler()
    end)
end

function Liaison.demarrer()
    if Liaison.actif then
        return
    end
    Liaison.actif = true
    Liaison.erreur = nil
    Liaison.generation = Liaison.generation + 1
    local generation = Liaison.generation

    LrFunctionContext.postAsyncTaskWithContext('Développeur : liaison', function(context)
        local function encore()
            return Liaison.actif and Liaison.generation == generation
        end

        local essais = 0
        local function surErreur(socket, erreur)
            if not encore() then
                return
            end
            if erreur == 'timeout' then
                -- Personne ne s'est connecté pendant le délai d'attente : on continue d'écouter.
                socket:reconnect()
                return
            end
            -- Port encore tenu (liaison relancée trop vite, autre Lightroom ouvert…) :
            -- quelques nouvelles tentatives, puis l'erreur reste affichée.
            essais = essais + 1
            if essais <= ESSAIS_MAX then
                LrTasks.startAsyncTask(function()
                    LrTasks.sleep(1)
                    if encore() then
                        socket:reconnect()
                    end
                end)
            else
                Liaison.erreur = tostring(erreur)
                Liaison.noter("Erreur de la liaison : " .. tostring(erreur))
            end
        end

        -- Chaque prise des réponses a son numéro : les événements d'une prise remplacée sont ignorés.
        local numeroReponses = 0
        local priseReponses = nil
        local function ouvrirReponses()
            numeroReponses = numeroReponses + 1
            local numero = numeroReponses
            local function courante()
                return encore() and numero == numeroReponses
            end
            Liaison.reponsesConnectee = false
            priseReponses = LrSocket.bind {
                functionContext = context,
                plugin = _PLUGIN,
                port = Liaison.PORT_REPONSES,
                mode = 'send',
                onConnecting = function(socket, port) end,
                onConnected = function(socket, port)
                    if courante() then
                        Liaison.reponsesConnectee = true
                        Liaison.erreur = nil
                        essais = 0
                    end
                end,
                onClosed = function(socket)
                    if courante() then
                        Liaison.reponsesConnectee = false
                    end
                end,
                onError = function(socket, erreur)
                    if courante() then
                        surErreur(socket, erreur)
                    end
                end,
            }
            Liaison.prise = priseReponses
        end

        local function renouvelerReponses()
            local ancienne = priseReponses
            numeroReponses = numeroReponses + 1
            priseReponses = nil
            Liaison.prise = nil
            Liaison.reponsesConnectee = false
            if ancienne then
                ancienne:close()
            end
            if encore() then
                ouvrirReponses()
            end
        end

        ouvrirReponses()

        local commandes = LrSocket.bind {
            functionContext = context,
            plugin = _PLUGIN,
            port = Liaison.PORT_COMMANDES,
            mode = 'receive',
            onConnecting = function(socket, port) end,
            onConnected = function(socket, port)
                Liaison.erreur = nil
                essais = 0
            end,
            onMessage = function(socket, message)
                if type(message) == 'string' then
                    Liaison.recevoir(message)
                end
            end,
            onClosed = function(socket)
                -- Le serveur a fini : on écoute de nouveau, et la prise des réponses repart à neuf.
                if encore() then
                    socket:reconnect()
                    renouvelerReponses()
                end
            end,
            onError = surErreur,
        }

        -- Photo active suivie (SDK : un contexte de fonction, celui de la liaison, qui retire
        -- l'observateur quand elle s'arrête) : la réponse suivante le dit au serveur
        -- (`evenements`, avec la nouvelle photo), qui le signale aux clients abonnés à la ressource
        -- de la photo active, ou le dit avec le résultat d'outil suivant (Claude Desktop ne s'abonne
        -- pas : constaté en 2.3).
        Liaison.derniereActive = Liaison.photoActive()
        LrTasks.pcall(LrApplication.addActivePhotoChangeObserver, context, function()
            Liaison.photoActiveChangee = true
        end)

        Liaison.noter(string.format("Liaison démarrée (ports %d et %d)", Liaison.PORT_COMMANDES, Liaison.PORT_REPONSES))

        while encore() do
            LrTasks.sleep(0.5)
        end

        if Liaison.generation == generation then
            Liaison.prise = nil
            Liaison.reponsesConnectee = false
        end
        numeroReponses = numeroReponses + 1
        commandes:close()
        if priseReponses then
            priseReponses:close()
        end
        Liaison.noter("Liaison arrêtée")
    end)
    Liaison.signaler()
end

function Liaison.arreter()
    if not Liaison.actif then
        return
    end
    Liaison.actif = false
    Liaison.signaler()
end

return Liaison
