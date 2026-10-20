-- Consommation.lua : les jetons que la fenêtre compte à chaque demande (champ `usage` du `result`
-- de Claude Code), le budget de la semaine (alerte à 80 %, arrêt à 100 %) et le dernier relevé du
-- forfait transmis par Claude Code. Rangé dans consommation.json (dates Unix).

local LrPathUtils = import 'LrPathUtils'

require 'Compat'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Texte = require 'Texte'

local Consommation = {}

Consommation.SEUIL_ALERTE = 0.8
Consommation.BUDGET_PAR_DEFAUT = 2000000
-- Trois mois gardés.
Consommation.DUREE_GARDEE = 92 * 86400

local registre

function Consommation.fichier()
    return LrPathUtils.child(Chemins.racine(), 'consommation.json')
end

-- Jetons comptés : la lecture du cache coûte un dixième d'un jeton d'entrée.
function Consommation.total(usage)
    usage = usage or {}
    return (usage.entree or 0) + (usage.sortie or 0) + (usage.cacheCreation or 0) + math.floor((usage.cacheLecture or 0) / 10)
end

local function vide()
    return { demandes = {}, budgetSemaine = Consommation.BUDGET_PAR_DEFAUT }
end

function Consommation.charger()
    if registre then
        return registre
    end
    local texte = Fichiers.lire(Consommation.fichier())
    local ok, r = pcall(function() return texte and Json.decode(texte) end)
    if ok and type(r) == 'table' then
        registre = r
        registre.demandes = type(r.demandes) == 'table' and r.demandes or {}
        registre.budgetSemaine = tonumber(r.budgetSemaine) or Consommation.BUDGET_PAR_DEFAUT
    else
        registre = vide()
        Consommation.enregistrer()
    end
    return registre
end

-- Pour les essais : oublie le registre chargé.
function Consommation.oublier()
    registre = nil
end

function Consommation.enregistrer()
    local r = registre or vide()
    local demandes = Json.tableau()
    for i, d in ipairs(r.demandes) do
        demandes[i] = d
    end
    local ok, erreur = pcall(Fichiers.ecrire, Consommation.fichier(),
        Json.encode({ demandes = demandes, budgetSemaine = r.budgetSemaine, limites = r.limites }))
    if not ok then
        Journal.noter("Consommation non enregistrée :", tostring(erreur))
    end
end

-- Une demande terminée : { date, modele, usage, apercu, dureeMs }.
function Consommation.ajouter(demande)
    local r = Consommation.charger()
    r.demandes[#r.demandes + 1] = demande
    local limite = (demande.date or os.time()) - Consommation.DUREE_GARDEE
    local gardees = {}
    for _, d in ipairs(r.demandes) do
        if (d.date or 0) >= limite then
            gardees[#gardees + 1] = d
        end
    end
    r.demandes = gardees
    Consommation.enregistrer()
end

-- Dernier relevé du forfait (événement « limites »).
function Consommation.releve(ev, maintenant)
    local r = Consommation.charger()
    r.limites = { cinqHeures = ev.cinqHeures, semaine = ev.semaine, repriseSemaine = ev.repriseSemaine, releveLe = maintenant or os.time() }
    Consommation.enregistrer()
end

function Consommation.changerBudget(jetons)
    local r = Consommation.charger()
    r.budgetSemaine = math.max(0, math.floor(tonumber(jetons) or 0))
    Consommation.enregistrer()
end

-- Début de la semaine du forfait : sept jours avant sa reprise si Claude Code l'a dite, sinon
-- lundi à minuit.
function Consommation.debutSemaine(maintenant)
    maintenant = maintenant or os.time()
    local r = Consommation.charger()
    local reprise = r.limites and r.limites.repriseSemaine
    if type(reprise) == 'number' and reprise > 0 then
        while reprise <= maintenant do
            reprise = reprise + 7 * 86400
        end
        return reprise - 7 * 86400
    end
    local t = os.date('*t', maintenant)
    t.hour, t.min, t.sec = 0, 0, 0
    local minuit = os.time(t)
    -- wday : 1 dimanche, 2 lundi…
    local recul = (t.wday + 5) % 7
    return minuit - recul * 86400
end

function Consommation.jetonsSemaine(maintenant)
    maintenant = maintenant or os.time()
    local debut = Consommation.debutSemaine(maintenant)
    local total = 0
    for _, d in ipairs(Consommation.charger().demandes) do
        if (d.date or 0) >= debut and (d.date or 0) <= maintenant then
            total = total + Consommation.total(d.usage)
        end
    end
    return total
end

-- Part du budget utilisée (0 sans budget).
function Consommation.part(maintenant)
    local budget = Consommation.charger().budgetSemaine or 0
    if budget <= 0 then
        return 0
    end
    return Consommation.jetonsSemaine(maintenant) / budget
end

-- 'normal', 'alerte' (80 %) ou 'arret' (100 %).
function Consommation.niveau(maintenant)
    local p = Consommation.part(maintenant)
    if p >= 1 then
        return 'arret'
    elseif p >= Consommation.SEUIL_ALERTE then
        return 'alerte'
    end
    return 'normal'
end

-- Jetons des sept derniers jours, le plus ancien d'abord : { debut, jetons }.
function Consommation.parJour(maintenant)
    maintenant = maintenant or os.time()
    local t = os.date('*t', maintenant)
    t.hour, t.min, t.sec = 0, 0, 0
    local aujourdhui = os.time(t)
    local jours = {}
    for recul = 6, 0, -1 do
        local debut = aujourdhui - recul * 86400
        jours[#jours + 1] = { debut = debut, jetons = 0 }
    end
    for _, d in ipairs(Consommation.charger().demandes) do
        for _, j in ipairs(jours) do
            if (d.date or 0) >= j.debut and (d.date or 0) < j.debut + 86400 then
                j.jetons = j.jetons + Consommation.total(d.usage)
            end
        end
    end
    return jours
end

-- Les n dernières demandes, la plus récente en premier.
function Consommation.dernieres(n)
    local liste = {}
    for _, d in ipairs(Consommation.charger().demandes) do
        liste[#liste + 1] = d
    end
    table.sort(liste, function(a, b) return (a.date or 0) > (b.date or 0) end)
    local premieres = {}
    for i = 1, math.min(n or 12, #liste) do
        premieres[i] = liste[i]
    end
    return premieres
end

-- « 1,2 M », « 48 k », « 512 ».
function Consommation.format(jetons)
    jetons = math.floor(jetons or 0)
    if jetons >= 1000000 then
        return Texte.nombre(math.floor(jetons / 100000 + 0.5) / 10) .. ' M'
    elseif jetons >= 1000 then
        return math.floor(jetons / 1000) .. ' k'
    end
    return tostring(jetons)
end

-- « semaine 27 % · 5 h 1 % (7:36) », d'après le dernier relevé.
function Consommation.texteReleve()
    local l = Consommation.charger().limites
    if not l or (not l.cinqHeures and not l.semaine) then
        return "pas encore de relevé"
    end
    local morceaux = {}
    if l.semaine then
        morceaux[#morceaux + 1] = string.format("semaine %d %%", math.floor(l.semaine * 100 + 0.5))
    end
    if l.cinqHeures then
        morceaux[#morceaux + 1] = string.format("5 h %d %%", math.floor(l.cinqHeures * 100 + 0.5))
    end
    local texte = table.concat(morceaux, " · ")
    if l.releveLe then
        texte = texte .. " (" .. os.date('%H:%M', l.releveLe) .. ")"
    end
    return texte
end

return Consommation
