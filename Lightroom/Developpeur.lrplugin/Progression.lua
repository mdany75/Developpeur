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
-- appelle : la croix arrête toutes les commandes en cours (une seule d'ordinaire, le serveur les
-- envoie une à une), et un point sûr ne s'arrête que si toutes l'ont été.

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

-- Commandes en cours suivies : { nom, debut, arret } ; la barre de l'une d'elles : { barre, suivi }.
local commandes = {}
local barreCommande
local surveillance = false

local function fermerBarreCommande()
    if barreCommande then
        local barre = barreCommande.barre
        barreCommande = nil
        LrTasks.pcall(function() barre:done() end)
    end
end

local function marquerArret()
    for _, suivi in ipairs(commandes) do
        suivi.arret = true
    end
end

-- Un tour de la surveillance : ouvre la barre de la plus ancienne commande passé le délai (sans
-- barre de série ouverte), lit sa croix, la ferme quand sa commande a fini. Faux quand plus rien
-- n'est suivi : la tâche s'arrête.
function Progression.surveiller()
    if barreCommande then
        if barreCommande.barre:isCanceled() == true then
            marquerArret()
        end
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

-- Liaison.traiter, avant la commande : nil pour une commande sans barre.
function Progression.debutCommande(nom)
    if Progression.SANS_BARRE[nom] then
        return nil
    end
    local suivi = { nom = nom, debut = LrDate.currentTime(), arret = false }
    commandes[#commandes + 1] = suivi
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

-- Point sûr d'une commande (jamais dans une écriture au catalogue, ni entre une proposition et sa
-- remise) : lève l'arrêt si la croix a été cliquée pour toutes les commandes en cours. fait : ce
-- que la commande a déjà fait, à dire.
function Progression.pointSur(fait)
    if #commandes == 0 then
        return
    end
    if barreCommande and barreCommande.barre:isCanceled() == true then
        marquerArret()
    end
    for _, suivi in ipairs(commandes) do
        if not suivi.arret then
            return
        end
    end
    error(Progression.messageArret(fait), 0)
end

-- Remise à zéro (essais) : plus rien de suivi, plus de barre.
function Progression.oublier()
    fermerBarreCommande()
    commandes = {}
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
