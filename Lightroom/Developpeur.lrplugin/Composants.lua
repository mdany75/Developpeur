-- Composants.lua (pas « Versions » : Lightroom refuse de charger un module de ce nom, constaté
-- dans Lightroom Classic 15.6) : les deux versions affichées en bas de la fenêtre Claude, celle de
-- ce module, « Développeur » (son Info.lua), et celle du connecteur « MCP-Développeur »
-- (`mcp-developpeur --version`). Les deux viennent de la même installation (build.sh --install),
-- au même numéro : la plus ancienne des deux est à mettre à jour (réinstaller Développeur).
-- Composants.lire s'appelle depuis une tâche.

local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Texte = require 'Texte'

local Composants = {}

-- « 1.0 » pour 1.0.0, « 1.3.1 » pour 1.3.1.
function Composants.formater(majeur, mineur, revision)
    if not majeur then
        return nil
    end
    local texte = tostring(majeur) .. '.' .. tostring(mineur or 0)
    if revision and tonumber(revision) and tonumber(revision) > 0 then
        texte = texte .. '.' .. tostring(revision)
    end
    return texte
end

-- La version écrite au début d'une sortie (« 1.0 »), nil s'il n'y en a pas.
function Composants.depuisSortie(texte)
    return tostring(texte or ''):match('^%s*v?(%d+%.%d+[%.%d]*)')
end

-- Compare deux versions : -1, 0 ou 1.
function Composants.comparer(a, b)
    local function parties(v)
        local t = {}
        for n in tostring(v):gmatch('%d+') do
            t[#t + 1] = tonumber(n)
        end
        return t
    end
    local pa, pb = parties(a), parties(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

-- Ce module.
function Composants.module()
    local ok, info = pcall(require, 'Info')
    local v = ok and type(info) == 'table' and info.VERSION or nil
    return v and Composants.formater(v.major, v.minor, v.revision) or '?'
end

-- Le connecteur : sa réponse à --version (cinq secondes au plus).
function Composants.connecteur(chemin)
    if not Fichiers.existe(chemin) then
        return nil
    end
    Fichiers.creerDossier(Chemins.temporaire())
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'version-' .. Conversation.identifiant() .. '.txt')
    LrTasks.execute("/usr/bin/perl -e 'alarm 5; exec @ARGV' " .. Texte.shell(chemin) .. ' --version > ' .. Texte.shell(sortie) .. ' 2>/dev/null')
    local texte = Fichiers.lire(sortie)
    Fichiers.supprimer(sortie)
    return Composants.depuisSortie(texte)
end

-- Les deux lignes : { nom, version, alerte (vrai : en orange) }. Un connecteur absent est
-- « introuvable » ; si les deux numéros diffèrent, le plus ancien est « à mettre à jour ». Une
-- version sans chiffre (« … », pas encore lue) ne se compare pas.
function Composants.lignes(module, connecteur)
    local lignes = {
        { nom = "Développeur", version = module or '?' },
        { nom = "MCP-Développeur", version = connecteur or '' },
    }
    local l1, l2 = lignes[1], lignes[2]
    if l2.version == '' then
        l2.nom, l2.alerte = "MCP-Développeur · introuvable", true
    elseif l1.version:match('%d') and l2.version:match('%d') then
        local ecart = Composants.comparer(l1.version, l2.version)
        if ecart < 0 then
            l1.nom, l1.alerte = "Développeur · à mettre à jour", true
        elseif ecart > 0 then
            l2.nom, l2.alerte = "MCP-Développeur · à mettre à jour", true
        end
    end
    return lignes
end

-- Lit les deux versions (dans une tâche).
function Composants.lire()
    return Composants.lignes(Composants.module(), Composants.connecteur(Chemins.prefs().cheminConnecteur))
end

return Composants
