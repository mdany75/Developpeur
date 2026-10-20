-- liens.lua : vérifie les liens entre les fichiers du module Lightroom (LuaJIT). Pour chaque
-- `local X = require 'X'` d'un fichier, chaque champ lu sous la forme X.nom doit exister dans le
-- module X une fois chargé : une fonction déplacée d'un module à l'autre, ou oubliée dans ses
-- exportations, se lirait sinon comme nil, et seulement au moment de s'en servir dans Lightroom.
-- Lancé par scripts/tester-module.sh avec tous les fichiers du module (liaison et fenêtre Claude).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
package.path = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/?.lua;'
    .. dossierTests .. '?.lua;' .. package.path

require 'Simulation'

-- Modules dont les champs changent pendant que Lightroom tourne (état de la liaison, préférences,
-- fenêtre de suivi) : un champ encore vide au chargement n'y est pas une erreur.
local AVEC_ETAT = { Liaison = true, Preferences = true, Suivi = true }

-- Champs d'état d'un module par ailleurs vérifié : posés pendant que Lightroom tourne (la
-- conversation ouverte de la fenêtre Claude, celle où Claude travaille), vides au chargement.
local CHAMPS_ETAT = { Moteur = { courante = true, enCours = true } }

-- Le code seul : commentaires et contenu des chaînes remplacés par des espaces (« Geometrie.lua »
-- dans un commentaire n'est pas un champ lu). Les chaînes gardent leurs guillemets, pour require.
local function codeSeul(texte)
    local sortie, i, n = {}, 1, #texte
    while i <= n do
        local c = texte:sub(i, i)
        local long = texte:match('^%-%-%[(=*)%[', i) or (c == '[' and texte:match('^%[(=*)%[', i))
        if texte:sub(i, i + 1) == '--' and not long then
            local fin = texte:find('\n', i, true) or n + 1
            i = fin
        elseif long then
            local _, fin = texte:find(']' .. long .. ']', i, true)
            fin = fin or n
            sortie[#sortie + 1] = (texte:sub(i, fin):gsub('[^\n]', ' '))
            i = fin + 1
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and texte:sub(j, j) ~= c do
                j = j + (texte:sub(j, j) == '\\' and 2 or 1)
            end
            sortie[#sortie + 1] = c .. (texte:sub(i + 1, j - 1):gsub('[^\n]', ' ')) .. c
            i = j + 1
        else
            sortie[#sortie + 1] = c
            i = i + 1
        end
    end
    return table.concat(sortie)
end

local erreurs = 0
for _, chemin in ipairs(arg) do
    local fichier = assert(io.open(chemin, 'r'))
    local source = fichier:read('*a')
    fichier:close()
    local texte = codeSeul(source)
    local nomFichier = chemin:match('([^/]+)$')
    local modules = {}
    -- Dans la source : le nom du module est une chaîne.
    for variable, module in source:gmatch("local%s+([%a_][%w_]*)%s*=%s*require%s*%(?%s*'([%w_]+)'") do
        if not AVEC_ETAT[module] then
            modules[variable] = module
        end
    end
    local vus = {}
    for variable, champ in texte:gmatch('([%a_][%w_]*)%.([%a_][%w_]*)') do
        local module = modules[variable]
        local cle = variable .. '.' .. champ
        if module and not vus[cle] then
            vus[cle] = true
            if require(module)[champ] == nil and not (CHAMPS_ETAT[module] and CHAMPS_ETAT[module][champ]) then
                erreurs = erreurs + 1
                print(string.format("ÉCHEC  %s : %s.%s n'existe pas dans %s.lua", nomFichier, variable, champ, module))
            end
        end
    end
end

if erreurs > 0 then
    os.exit(1)
end
print(string.format("Liens entre modules : %d fichiers vérifiés", #arg))
