-- Progression.lua : barre de progression de Lightroom (en haut à gauche de la fenêtre) pendant une
-- longue série de Claude (tri, harmonisation, livraison), avec la croix qui l'arrête.
--
-- Le serveur envoie la commande « progression » à chaque avancée de la série ({ id, titre, fait,
-- total, message }), puis { id, fin = true } quand l'appel d'outil se termine. La réponse dit si
-- l'utilisateur a cliqué la croix (annulee) : le serveur arrête la série entre deux lots. Une barre
-- sans nouvelle depuis PERIMEE secondes (serveur relancé, Claude parti) se ferme à la commande
-- suivante. LrProgressScope (SDK 1.3) : setPortionComplete, setCaption, setCancelable, isCanceled,
-- done.
--
-- Commande seule longue (un rendu, une lecture, hors d'une série) : Liaison.traiter l'annonce
-- (debutCommande, finCommande) ; passé DELAI_COMMANDE secondes, une barre « Claude : <nom lisible> »
-- s'ouvre, avec sa croix, tenue par une seule tâche de surveillance (surveiller, tous les quarts de
-- seconde). Jamais deux barres : rien pendant une barre de série, rien pour les commandes de
-- SANS_BARRE (celles qui attendent l'utilisateur, l'exportation qui a sa propre barre, les calculs de
-- Lightroom qui ne s'arrêtent pas en chemin). La croix ne coupe rien d'elle-même : la commande
-- s'arrête à son prochain point sûr (pointSur : avant et après un rendu, pendant l'attente des
-- vignettes, avant la commande elle-même), jamais au milieu d'une écriture au catalogue, et une
-- proposition remet la photo comme avant ; la réponse est l'erreur ARRET (code 'arret'), que le
-- serveur rend à Claude telle quelle sans la rejouer. Arrivée après le dernier point sûr, la croix
-- laisse finir la commande : sa réponse porte arret_demande. Lightroom ne dit pas quelle tâche
-- appelle : le point sûr reçoit donc le suivi de sa commande (Progression.suiviDe(params), que
-- Liaison.traiter lie aux paramètres reçus), et un appel sans suivi (la fenêtre Claude, le Suivi,
-- l'après d'une étape) n'est jamais arrêté. La croix ne marque que la commande de sa barre, une
-- seule fois, au premier clic vu : une commande venue ensuite (d'une autre session) n'est pas
-- arrêtée à sa place, même si la barre annulée reste ouverte jusqu'à la fin de la sienne.

local LrDate = import 'LrDate'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Progression = {}

Progression.PERIMEE = 300

-- La barre en cours : { id, barre, derniere }.
local courante

Progression.DELAI_COMMANDE = 3
Progression.TACHE_SURVEILLANCE = "Claude · barre de la commande"
Progression.ARRET = "Arrêtée par l'utilisateur"
Progression.ARRET_TARDIF = "Arrêt demandé par la croix de la barre « Claude » quand la commande ne pouvait plus "
    .. "s'arrêter : elle a été faite en entier. L'utilisateur veut arrêter : ne rien lancer d'autre sans sa demande."

-- Commandes sans barre à elles : le ping et la progression (instantanés), celles qui attendent
-- l'utilisateur (choisirDossier, fenetreExport), l'exportation (Lightroom montre la sienne), et les
-- calculs de Lightroom (débruitage, reflets) qu'une croix ne peut pas couper en chemin.
Progression.SANS_BARRE = {
    ping = true, progression = true, etat = true, choisirDossier = true, fenetreExport = true,
    exporter = true, ameliorer = true, supprimer = true,
}

-- Nom lisible de chaque commande, dans le titre de sa barre.
Progression.NOMS = {
    selection = "lecture de la sélection", reglages = "lecture des réglages", apercu = "rendu de la photo",
    geometrie = "rendu de la géométrie", appliquer = "retouche", recadrer = "recadrage", masquer = "masques",
    retoucher = "taches", copier = "copie des réglages", essayer = "essai d'une retouche",
    presets = "paramètres prédéfinis", creerPreset = "paramètre prédéfini", diagnostic = "diagnostic",
    journal = "journal des retouches", annuler = "annulation", revenir = "retour à l'origine",
    metadonnees = "classement", motsCles = "mots-clés", collections = "collections",
    chercher = "recherche dans le catalogue", copieVirtuelle = "copies virtuelles", montrer = "affichage des photos",
    vignettes = "vignettes des photos", livraison = "options de livraison", nomsFichiers = "noms des fichiers",
    apercusDynamiques = "aperçus dynamiques", retirerReimportees = "photos réimportées",
    importerGeneree = "import de la retouche générative", variantes = "variantes", masques = "masques",
    notation = "notes", carnet = "carnet de progrès", etapes = "étapes",
}

function Progression.nomLisible(nom)
    return Progression.NOMS[nom] or ("commande « " .. tostring(nom) .. " »")
end

-- Commandes en cours suivies : { nom, debut, arret } ; la barre de l'une d'elles : { barre, suivi,
-- arretVu } ; le suivi de chaque commande par ses paramètres (Progression.suiviDe), tant qu'elle
-- est en cours.
local commandes = {}
local barreCommande
local surveillance = false
local parParams = setmetatable({}, { __mode = 'k' })

local function fermerBarreCommande()
    if barreCommande then
        local barre = barreCommande.barre
        barreCommande = nil
        LrTasks.pcall(function() barre:done() end)
    end
end

-- La croix de la barre d'une commande, lue : au premier clic vu, cette commande seule est marquée
-- arrêtée, une fois (arretVu) ; les tours suivants, barre toujours annulée, ne marquent plus rien.
local function lireCroix()
    if barreCommande and not barreCommande.arretVu and barreCommande.barre:isCanceled() == true then
        barreCommande.arretVu = true
        barreCommande.suivi.arret = true
    end
end

-- Un tour de la surveillance : ouvre la barre de la plus ancienne commande passé le délai (sans
-- barre de série ouverte), lit sa croix, la ferme quand sa commande a fini. Faux quand plus rien
-- n'est suivi : la tâche s'arrête.
function Progression.surveiller()
    if barreCommande then
        lireCroix()
        local suivie = false
        for _, suivi in ipairs(commandes) do
            if suivi == barreCommande.suivi then suivie = true end
        end
        if not suivie then
            fermerBarreCommande()
        end
    end
    if #commandes == 0 then
        fermerBarreCommande()
        surveillance = false
        return false
    end
    local premiere = commandes[1]
    if not barreCommande and not courante and not premiere.arret
        and LrDate.currentTime() - premiere.debut >= Progression.DELAI_COMMANDE then
        local barre = LrProgressScope { title = "Claude : " .. Progression.nomLisible(premiere.nom) }
        barre:setCancelable(true)
        barre:setCaption("La croix l'arrête au prochain point sûr.")
        barreCommande = { barre = barre, suivi = premiere }
    end
    return true
end

-- Liaison.traiter, avant la commande : nil pour une commande sans barre. params : les paramètres
-- reçus, auxquels le suivi est lié jusqu'à finCommande (Progression.suiviDe).
function Progression.debutCommande(nom, params)
    if Progression.SANS_BARRE[nom] then
        return nil
    end
    local suivi = { nom = nom, debut = LrDate.currentTime(), arret = false }
    commandes[#commandes + 1] = suivi
    if type(params) == 'table' then
        suivi.params = params
        parParams[params] = suivi
    end
    if not surveillance then
        surveillance = true
        LrTasks.startAsyncTask(function()
            local tourne = true
            while tourne do
                LrTasks.sleep(0.25)
                local ok, encore = LrTasks.pcall(Progression.surveiller)
                tourne = ok and encore
            end
            surveillance = false
        end, Progression.TACHE_SURVEILLANCE)
    end
    return suivi
end

-- Liaison.traiter, la commande finie (réussie ou non) : sa barre se ferme tout de suite.
function Progression.finCommande(suivi)
    if not suivi then
        return
    end
    if suivi.params and parParams[suivi.params] == suivi then
        parParams[suivi.params] = nil
    end
    for i = #commandes, 1, -1 do
        if commandes[i] == suivi then
            table.remove(commandes, i)
        end
    end
    if barreCommande and barreCommande.suivi == suivi then
        fermerBarreCommande()
    end
end

-- Texte de l'arrêt : ce qui a été fait (fait), sinon rien.
function Progression.messageArret(fait)
    local debut = Progression.ARRET .. " (croix de la barre « Claude » de Lightroom)"
    if fait and fait ~= '' then
        return debut .. " : " .. fait .. " ; rien d'autre n'a été fait."
    end
    return debut .. " : rien d'autre n'a été fait."
end

-- Vrai si l'erreur est un arrêt demandé par la croix.
function Progression.estArret(texte)
    return type(texte) == 'string' and texte:find(Progression.ARRET, 1, true) ~= nil
end

-- Le suivi de la commande en cours à qui appartiennent ces paramètres (ceux que Commandes.executer
-- passe à la commande), nil hors d'une commande suivie (appel direct de la fenêtre Claude, du
-- Suivi, de l'après d'une étape, ou commande sans barre).
function Progression.suiviDe(params)
    if type(params) ~= 'table' then
        return nil
    end
    return parParams[params]
end

-- Point sûr d'une commande (jamais dans une écriture au catalogue, ni entre une proposition et sa
-- remise) : lève l'arrêt si la croix de sa barre a été cliquée. suivi : celui de la commande
-- (Progression.suiviDe) ; sans suivi, rien (l'appel ne vient pas d'une commande). fait : ce que la
-- commande a déjà fait, à dire.
function Progression.pointSur(suivi, fait)
    if type(suivi) ~= 'table' then
        return
    end
    lireCroix()
    if suivi.arret == true then
        error(Progression.messageArret(fait), 0)
    end
end

-- Remise à zéro (essais) : plus rien de suivi, plus de barre.
function Progression.oublier()
    fermerBarreCommande()
    commandes = {}
    parParams = setmetatable({}, { __mode = 'k' })
    surveillance = false
    if courante then
        LrTasks.pcall(function() courante.barre:done() end)
        courante = nil
    end
end

local function fermer()
    if courante then
        LrTasks.pcall(function() courante.barre:done() end)
        courante = nil
    end
end

-- À chaque commande reçue : une barre restée sans nouvelle se ferme.
function Progression.verifierPerimee()
    if courante and LrDate.currentTime() - courante.derniere > Progression.PERIMEE then
        fermer()
    end
end

-- Arrêt du module : les barres ne survivent pas.
function Progression.fermer()
    fermer()
    fermerBarreCommande()
    commandes = {}
    parParams = setmetatable({}, { __mode = 'k' })
end

function Progression.progression(params)
    local id = tostring(params.id or '')
    if id == '' then
        error("Progression sans identifiant.", 0)
    end
    if params.fin then
        local annulee = courante ~= nil and courante.id == id and courante.barre:isCanceled() == true
        if courante and courante.id == id then
            fermer()
        end
        return { fermee = true, annulee = annulee }
    end
    if not courante or courante.id ~= id then
        fermer()
        -- La barre de la série remplace celle d'une commande seule : jamais deux.
        fermerBarreCommande()
        local barre = LrProgressScope { title = "Claude : " .. tostring(params.titre or "série en cours") }
        barre:setCancelable(true)
        courante = { id = id, barre = barre }
    end
    courante.derniere = LrDate.currentTime()
    local total, fait = tonumber(params.total) or 0, tonumber(params.fait) or 0
    if total > 0 then
        courante.barre:setPortionComplete(math.max(0, math.min(fait, total)), total)
    end
    if params.message then
        courante.barre:setCaption(tostring(params.message))
    end
    return { annulee = courante.barre:isCanceled() == true }
end

return Progression
