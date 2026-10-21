-- Liaison.lua : les deux prises réseau qui relient le module au serveur MCP « mcp-developpeur ».
--
-- LrSocket ne fonctionne que dans un sens par prise : Lightroom écoute sur 127.0.0.1, reçoit
-- les commandes sur PORT_COMMANDES et renvoie les réponses sur PORT_REPONSES. Chaque message
-- est une ligne JSON :
--   commande → {"id": 7, "jeton": "<64 chiffres hexadécimaux>", "command": "apercu", "params": {…}}
--   réponse  ← {"id": 7, "result": {…}}  ou  {"id": 7, "error": "message"}
--   refus    ← {"id": 7, "error": "Liaison fermée : …", "code": "jeton"}
-- Le serveur ouvre une connexion par commande puis la ferme : plusieurs sessions de Claude
-- (Claude Desktop, Claude Code) peuvent ainsi se succéder.
--
-- Liaison fermée (1.2) : à chaque démarrage, le module tire un jeton privé (32 octets de
-- /dev/urandom), le garde en mémoire et l'écrit d'un coup dans liaison.jeton (droits 600, dans
-- ~/Library/Application Support/Developpeur/), que le serveur relit à chaque connexion. Toute
-- ligne, ping compris, doit le porter : sinon elle est refusée avant Commandes.executer, donc
-- avant la pause et « Proposer d'abord ». Une page web (POST vers 127.0.0.1) ou un autre compte
-- du Mac ne peut plus rien faire faire au module ; un programme de l'utilisateur lui-même, qui
-- peut lire le fichier, le pourrait encore. Le jeton n'est jamais journalisé ni renvoyé.
-- `depuisLightroom` (pause et accord dans Lightroom levés) ne vient jamais du réseau : seuls les
-- menus, la fenêtre de suivi et la carte Note le posent, par appel direct.
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
local Texte = require 'Texte'

local Liaison = {
    VERSION = '1.1.1',
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

    -- Liaison fermée (1.2). Le jeton de ce démarrage (nil : liaison arrêtée, ou jeton impossible
    -- à écrire, et alors tout est refusé) ; jamais journalisé, ni dans une réponse ni dans l'état.
    jeton = nil,
    -- Lignes refusées depuis le démarrage (sans jeton, mauvais jeton, illisibles), pour le diagnostic.
    refus = 0,
    -- Genre → heure de la dernière ligne notée au journal pour ce genre de refus.
    derniersRefus = {},
    FICHIER_JETON = 'liaison.jeton',
    -- Un refus du même genre n'est noté qu'une fois par DELAI_REFUS secondes.
    DELAI_REFUS = 10,
    -- Le fichier du jeton est vérifié tous les VERIFIER_JETON_TOUTES tours de la boucle de la
    -- liaison (0,5 s chacun : 5 s), et réécrit s'il a été effacé ou remplacé.
    VERIFIER_JETON_TOUTES = 10,
}

-- Réponses à une ligne refusée (code 'jeton'), selon le genre du refus. Le serveur les montre
-- telles quelles à Claude.
Liaison.REFUS_JETON = {
    sans = "Liaison fermée : cette commande ne porte pas le jeton de la liaison ; rien n'a été fait. "
        .. "Le connecteur MCP-Développeur qui l'envoie date d'avant la 1.2 : quitter puis rouvrir Claude Desktop, "
        .. "ou ouvrir une nouvelle session de Claude Code, pour lancer celui qui est installé.",
    faux = "Liaison fermée : le jeton de cette commande n'est pas celui de la liaison ; rien n'a été fait. "
        .. "Il change à chaque démarrage de la liaison : réessayer ; si le refus se répète, relancer la liaison dans Lightroom.",
    aucun = "Liaison fermée : le module n'a pas de jeton (il n'a pas pu l'écrire au démarrage de la liaison) ; "
        .. "rien n'a été fait. Relancer la liaison dans Lightroom (Fichier › Module externe - Extras › "
        .. "Démarrer la liaison avec Claude).",
}

-- Ligne du journal de chaque genre de refus.
local NOTES_REFUS = {
    sans = "Commande refusée sans jeton (connecteur d'avant la 1.2, ou autre programme)",
    faux = "Commande refusée : mauvais jeton",
    aucun = "Commande refusée : la liaison n'a pas de jeton",
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

-- Jeton de la liaison (1.2) -------------------------------------------------------------------

-- Dossier et chemin du fichier du jeton : ~/Library/Application Support/Developpeur/liaison.jeton,
-- là où le serveur le cherche (JetonLiaison.fichierParDefaut).
function Liaison.cheminJeton()
    local dossier = LrPathUtils.getStandardFilePath('home')
    for _, nom in ipairs({ 'Library', 'Application Support', 'Developpeur' }) do
        dossier = LrPathUtils.child(dossier, nom)
    end
    return dossier, LrPathUtils.child(dossier, Liaison.FICHIER_JETON)
end

-- 32 octets de l'aléa du système en 64 chiffres hexadécimaux ; nil si la lecture échoue.
function Liaison.tirerJeton()
    local alea = io.open('/dev/urandom', 'rb')
    if not alea then
        return nil
    end
    local octets = alea:read(32)
    alea:close()
    if type(octets) ~= 'string' or #octets ~= 32 then
        return nil
    end
    local chiffres = {}
    for i = 1, #octets do
        chiffres[i] = string.format('%02x', octets:byte(i))
    end
    return table.concat(chiffres)
end

-- Le jeton rangé dans le fichier, ou nil (fichier absent, ou autre chose que 64 chiffres
-- hexadécimaux en minuscules).
function Liaison.lireFichierJeton()
    local _, chemin = Liaison.cheminJeton()
    local fichier = io.open(chemin, 'r')
    if not fichier then
        return nil
    end
    local contenu = fichier:read('*a')
    fichier:close()
    if type(contenu) ~= 'string' then
        return nil
    end
    contenu = contenu:gsub('\n$', '')
    if #contenu ~= 64 or contenu:find('[^0-9a-f]') then
        return nil
    end
    return contenu
end

-- Écrit le jeton d'un seul coup : un fichier provisoire créé vide en droits 600 (umask 077), le
-- jeton écrit dedans par io.open (jamais sur une ligne de commande), puis rangé à sa place par
-- mv, et relu. Rend true, ou nil et la raison.
function Liaison.ecrireJeton(jeton)
    local dossier, chemin = Liaison.cheminJeton()
    LrFileUtils.createAllDirectories(dossier)
    local provisoire = chemin .. '.nouveau'
    if LrTasks.execute('umask 077 && /bin/rm -f ' .. Texte.shell(provisoire) .. ' && /usr/bin/touch ' .. Texte.shell(provisoire)) ~= 0 then
        return nil, "fichier du jeton impossible à créer"
    end
    local fichier = io.open(provisoire, 'w')
    if not fichier then
        return nil, "fichier du jeton impossible à créer"
    end
    fichier:write(jeton .. '\n')
    fichier:close()
    if LrTasks.execute('/bin/mv -f ' .. Texte.shell(provisoire) .. ' ' .. Texte.shell(chemin)) ~= 0 then
        return nil, "fichier du jeton impossible à ranger"
    end
    if Liaison.lireFichierJeton() ~= jeton then
        return nil, "jeton relu différent"
    end
    return true
end

-- Un nouveau jeton, écrit dans son fichier ; nil et la raison si l'un ou l'autre échoue.
function Liaison.preparerJeton()
    local jeton = Liaison.tirerJeton()
    if not jeton then
        return nil, "aléa du système illisible (/dev/urandom)"
    end
    local ecrit, raison = Liaison.ecrireJeton(jeton)
    if not ecrit then
        return nil, raison
    end
    return jeton
end

-- Le fichier du jeton, vérifié pendant que la liaison tourne : effacé, remplacé ou réécrit par
-- un démarrage plus ancien, il reprend le jeton de la liaison. Un échec n'est noté qu'au premier
-- tour qui échoue. Rend true si le fichier a été réécrit.
local fichierJetonEnEchec = false
function Liaison.garderFichierJeton()
    local jeton = Liaison.jeton
    if not jeton or Liaison.lireFichierJeton() == jeton then
        fichierJetonEnEchec = false
        return false
    end
    local ecrit, raison = Liaison.ecrireJeton(jeton)
    if ecrit then
        fichierJetonEnEchec = false
        Liaison.noter("Fichier du jeton réécrit")
        return true
    end
    if not fichierJetonEnEchec then
        fichierJetonEnEchec = true
        Liaison.noter("Fichier du jeton impossible à réécrire : " .. tostring(raison))
    end
    return false
end

-- Vrai si les deux jetons sont des textes égaux. La comparaison parcourt toute la longueur, sans
-- s'arrêter au premier écart (le Lua de Lightroom n'a pas la bibliothèque bit).
function Liaison.memeJeton(a, b)
    if type(a) ~= 'string' or type(b) ~= 'string' or #a ~= #b then
        return false
    end
    local ecarts = 0
    for i = 1, #a do
        if a:byte(i) ~= b:byte(i) then
            ecarts = ecarts + 1
        end
    end
    return ecarts == 0
end

-- nil si le jeton fourni est celui de la liaison ; sinon le genre du refus : 'aucun' (la liaison
-- n'a pas de jeton : tout est refusé), 'sans' (la ligne n'en porte pas), 'faux'.
function Liaison.refusJeton(fourni)
    if not Liaison.jeton then
        return 'aucun'
    end
    if fourni == nil then
        return 'sans'
    end
    if Liaison.memeJeton(fourni, Liaison.jeton) then
        return nil
    end
    return 'faux'
end

-- Une ligne refusée : comptée, et notée au journal au plus une fois par DELAI_REFUS secondes et
-- par genre (une inondation de lignes ne remplit pas le journal).
function Liaison.noterRefus(genre, texte)
    Liaison.refus = (Liaison.refus or 0) + 1
    Liaison.derniersRefus = Liaison.derniersRefus or {}
    local maintenant = LrDate.currentTime()
    local dernier = Liaison.derniersRefus[genre]
    if dernier == nil or maintenant - dernier > Liaison.DELAI_REFUS then
        Liaison.derniersRefus[genre] = maintenant
        Liaison.noter(texte)
    end
end

-- Appelée depuis une tâche asynchrone. Le serveur se connecte à la prise des réponses juste
-- avant d'envoyer sa commande : on laisse à Lightroom le temps de l'accepter. sansEvenements :
-- réponse à une ligne refusée, qui ne doit pas emporter l'événement de la photo active destiné au
-- vrai serveur.
function Liaison.repondre(objet, sansEvenements)
    local attente = 0
    while not Liaison.reponsesConnectee and attente < ATTENTE_REPONSES do
        LrTasks.sleep(0.1)
        attente = attente + 0.1
    end
    local prise = Liaison.prise
    if prise and Liaison.reponsesConnectee then
        if Liaison.photoActiveChangee and not sansEvenements then
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
-- l'accès en écriture au catalogue), puis la réponse part avec le même identifiant. Le jeton se
-- vérifie avant tout le reste, ping compris : une ligne refusée ne compte pas comme un échange,
-- n'atteint pas Commandes.executer (ni la pause, ni « Proposer d'abord ») et n'emporte pas
-- l'événement de la photo active.
function Liaison.recevoir(message)
    LrTasks.startAsyncTask(function()
        local lu, requete = pcall(Json.decode, message)
        if not lu or type(requete) ~= 'table' or type(requete.command) ~= 'string' then
            Liaison.noterRefus('illisible', "Message illisible ignoré")
            return
        end
        local genre = Liaison.refusJeton(requete.jeton)
        if genre then
            Liaison.noterRefus(genre, NOTES_REFUS[genre])
            Liaison.repondre({ id = requete.id, error = Liaison.REFUS_JETON[genre], code = 'jeton' }, true)
            return
        end
        Liaison.dernierEchange = LrDate.currentTime()
        local Commandes = require 'Commandes'
        local params = type(requete.params) == 'table' and requete.params or {}
        -- Seuls les menus, la fenêtre de suivi et la carte Note lèvent la pause et l'accord dans
        -- Lightroom, par appel direct : une ligne du réseau ne le peut pas.
        params.depuisLightroom = nil
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

        -- Le jeton naît avant les prises : sans lui, aucune ne s'ouvre et la liaison reste en
        -- erreur (voyant rouge ; un clic la relance). Un démarrage remplacé pendant ce temps ne
        -- touche pas au jeton du suivant.
        local tire, jeton, raison = LrTasks.pcall(Liaison.preparerJeton)
        if not encore() then
            return
        end
        if not tire or not jeton then
            Liaison.jeton = nil
            Liaison.erreur = 'jeton de la liaison : ' .. (tire and tostring(raison) or Liaison.messageErreur(jeton))
            Liaison.noter('Erreur de la liaison : ' .. Liaison.erreur)
            Liaison.signaler()
            return
        end
        Liaison.jeton, Liaison.refus, Liaison.derniersRefus = jeton, 0, {}

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

        Liaison.noter(string.format("Liaison démarrée (ports %d et %d, jeton privé)", Liaison.PORT_COMMANDES, Liaison.PORT_REPONSES))

        local tours = 0
        while encore() do
            LrTasks.sleep(0.5)
            tours = tours + 1
            if tours % Liaison.VERIFIER_JETON_TOUTES == 0 and encore() then
                LrTasks.pcall(Liaison.garderFichierJeton)
            end
        end

        if Liaison.generation == generation then
            Liaison.prise = nil
            Liaison.reponsesConnectee = false
            Liaison.jeton = nil
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
