-- Progression.lua : barre de progression de Lightroom (en haut à gauche de la fenêtre) pendant une
-- longue série de Claude (tri, harmonisation, livraison), avec la croix qui l'arrête.
--
-- Le serveur envoie la commande « progression » à chaque avancée de la série ({ id, titre, fait,
-- total, message }), puis { id, fin = true } quand l'appel d'outil se termine. La réponse dit si
-- l'utilisateur a cliqué la croix (annulee) : le serveur arrête la série entre deux lots. Une barre
-- sans nouvelle depuis PERIMEE secondes (serveur relancé, Claude parti) se ferme à la commande
-- suivante. LrProgressScope (SDK 1.3) : setPortionComplete, setCaption, setCancelable, isCanceled,
-- done.

local LrDate = import 'LrDate'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Progression = {}

Progression.PERIMEE = 300

-- La barre en cours : { id, barre, derniere }.
local courante

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

-- Arrêt du module : la barre ne survit pas.
function Progression.fermer()
    fermer()
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
