-- essais-menage.lua : le ménage de Temporaire au chargement du module (Menage.temporaires,
-- chantier « ménage » après la 1.6.3), hors de Lightroom (LuaJIT, Lightroom simulé par
-- Simulation.lua, dossier personnel temporaire). Les vignettes de la photo active et de Focus
-- (Temporaire/PhotoActive) et les fichiers dimensions-*.txt s'accumulaient sans fin chez Dany
-- (137 Mo). Un essai parcourt aussi le code du module et du connecteur : chaque dossier ou fichier
-- écrit sous Temporaire doit être vidé par Menage, ou porter sa raison dans Menage.GARDES.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Menage = require 'Menage'

local function dans(liste, nom)
    for _, x in ipairs(liste) do
        if x == nom then
            return true
        end
    end
    return false
end

local function lireTout(chemin)
    local f = assert(io.open(chemin, 'r'), chemin)
    local texte = f:read('*a')
    f:close()
    return texte
end

local function fichiersDe(dossier, motif)
    local liste = {}
    local p = io.popen('find ' .. S.q(dossier) .. ' -name ' .. S.q(motif) .. ' -type f | sort')
    for ligne in p:lines() do
        liste[#liste + 1] = ligne
    end
    p:close()
    return liste
end

-- Ce que le code écrit sous Temporaire : { dossiers = { [nom] = fichier source }, prefixes =
-- { [début de nom] = fichier source }, fichiers = { [nom] = fichier source } }.
local function releverTemporaire()
    local releve = { dossiers = {}, prefixes = {}, fichiers = {} }
    for _, chemin in ipairs(fichiersDe(S.plugin, '*.lua')) do
        local source = chemin:match('[^/]+$')
        if source ~= 'Menage.lua' then
            local code = lireTout(chemin)
            -- LrPathUtils.child(Chemins.temporaire(), 'Nom') : un dossier ; 'nom-' .. : un fichier de
            -- passage dont le nom commence ainsi.
            for nom, suite in code:gmatch("Chemins%.temporaire%(%)%s*,%s*'([^']+)'%s*(%S?%S?)") do
                if suite == '..' then
                    releve.prefixes[nom] = source
                else
                    releve.dossiers[nom] = source
                end
            end
            -- Les autres emplois de Chemins.temporaire() : créer le dossier lui-même, sa définition,
            -- ou le dossier par défaut d'Images.lireFocus (« focus-<id>-focus.jpg » à la racine).
            -- Tout autre emploi fait échouer l'essai : il faut l'ajouter ici, et au ménage.
            for ligne in code:gmatch('[^\n]+') do
                local avant, apres = ligne:match('^(.-)Chemins%.temporaire%(%)(.*)$')
                if avant and not apres:match("^%s*,%s*'") then
                    if avant:match('Fichiers%.creerDossier%($') or avant:match('function $') then
                        -- le dossier Temporaire lui-même
                    elseif avant:match('or $') and code:find("'focus-' ..", 1, true) then
                        releve.prefixes['focus-'] = source
                    else
                        error(string.format("%s : Chemins.temporaire() employé sans nom relevable : %s", source, ligne))
                    end
                end
            end
        end
    end
    -- Le connecteur (Swift) écrit aussi sous Temporaire : "Temporaire/<nom>".
    for _, chemin in ipairs(fichiersDe(S.plugin .. '/../../Sources', '*.swift')) do
        local code = lireTout(chemin)
        for nom in code:gmatch('"Temporaire/([^"/]+)') do
            if nom:find('.', 1, true) then
                releve.fichiers[nom] = chemin:match('[^/]+$')
            else
                releve.dossiers[nom] = chemin:match('[^/]+$')
            end
        end
    end
    return releve
end

essai("Le code relevé : chaque dossier ou fichier écrit sous Temporaire est vidé par Menage, ou gardé avec sa raison (Menage.GARDES)", function()
    local releve = releverTemporaire()
    -- Le relevé trouve bien ce qu'on sait déjà (sinon le motif ne lit plus le code).
    for _, nom in ipairs({ 'Groupes', 'Rapide', 'Suivi', 'Fibo', 'PhotoActive', 'Pourquoi', 'Collees' }) do
        vrai(releve.dossiers[nom], 'relevé : ' .. nom)
    end
    for _, debut in ipairs({ 'dimensions-', 'version-', 'auth-', 'presse-papiers-', 'focus-' }) do
        vrai(releve.prefixes[debut], 'relevé : ' .. debut)
    end
    vrai(releve.fichiers['fibo-en-cours.verrou'], 'relevé : le verrou de Fibo')
    for nom, source in pairs(releve.dossiers) do
        vrai(dans(Menage.TEMPORAIRES, nom) or Menage.GARDES[nom],
            string.format("Temporaire/%s (%s) : ni dans Menage.TEMPORAIRES, ni dans Menage.GARDES avec sa raison", nom, source))
    end
    for debut, source in pairs(releve.prefixes) do
        vrai(dans(Menage.FICHIERS, debut) or Menage.GARDES[debut],
            string.format("Temporaire/%s* (%s) : ni dans Menage.FICHIERS, ni dans Menage.GARDES avec sa raison", debut, source))
    end
    for nom, source in pairs(releve.fichiers) do
        local efface = false
        for _, debut in ipairs(Menage.FICHIERS) do
            efface = efface or nom:sub(1, #debut) == debut
        end
        vrai(efface or Menage.GARDES[nom], string.format("Temporaire/%s (%s) : ni effacé, ni gardé avec sa raison", nom, source))
    end
    for nom, raison in pairs(Menage.GARDES) do
        vrai(type(raison) == 'string' and #raison > 20, 'une vraie raison pour ' .. nom)
        vrai(not dans(Menage.TEMPORAIRES, nom), nom .. ' à la fois gardé et effacé')
    end
end)

essai("Chargement : PhotoActive (photo active, grande image, Focus), Pourquoi, Collees et les fichiers dimensions-*.txt laissés s'effacent ; le verrou de Fibo, les conversations et le reste restent", function()
    local t = Chemins.temporaire()
    Fichiers.ecrire(t .. '/PhotoActive/1234-5/vignette.jpg', 'jpeg')
    Fichiers.ecrire(t .. '/PhotoActive/Grande-1234-5/grande.jpg', 'jpeg')
    Fichiers.ecrire(t .. '/PhotoActive/Focus-1234-5/focus.jpg', 'jpeg')
    Fichiers.ecrire(t .. '/Pourquoi/991/avant.jpg', 'jpeg')
    Fichiers.ecrire(t .. '/Collees/capture.png', 'png')
    Fichiers.ecrire(t .. '/dimensions-1234-5.txt', 'pixelWidth: 10')
    Fichiers.ecrire(t .. '/dimensions-6789-1.txt', 'pixelWidth: 10')
    Fichiers.ecrire(t .. '/version-1234-5.txt', '1.6.3')
    Fichiers.ecrire(t .. '/fibo-en-cours.verrou', '')
    Fichiers.ecrire(t .. '/autre.txt', 'garde')
    Fichiers.ecrire(Chemins.conversations() .. '/c1/conversation.json', '{}')
    egal(6, Menage.temporaires(), 'trois dossiers et trois fichiers')
    for _, nom in ipairs({ 'PhotoActive', 'Pourquoi', 'Collees', 'dimensions-1234-5.txt', 'dimensions-6789-1.txt', 'version-1234-5.txt' }) do
        egal(false, Fichiers.existe(t .. '/' .. nom), nom .. ' effacé')
    end
    vrai(Fichiers.existe(t .. '/fibo-en-cours.verrou'), 'le verrou de Fibo reste')
    vrai(Fichiers.existe(t .. '/autre.txt'), "un fichier qu'on ne connaît pas reste")
    vrai(Fichiers.existe(Chemins.conversations() .. '/c1/conversation.json'), 'les conversations restent')
    egal(0, Menage.temporaires(), 'rien de plus')
end)

essai("Une fenêtre ouverte ou Claude au travail : rien ne s'efface (ses vignettes sont peut-être en usage)", function()
    local t = Chemins.temporaire()
    Fichiers.ecrire(t .. '/PhotoActive/1234-5/vignette.jpg', 'jpeg')
    Fichiers.ecrire(t .. '/dimensions-1234-5.txt', 'pixelWidth: 10')
    local Fenetre = require 'Fenetre'
    local Moteur = require 'Moteur'
    local ouverte, travaille = Fenetre.ouverte, Moteur.travaille
    Fenetre.ouverte = true
    egal(0, Menage.temporaires(), 'fenêtre ouverte')
    Fenetre.ouverte = false
    Moteur.travaille = true
    egal(0, Menage.temporaires(), 'Claude au travail')
    vrai(Fichiers.existe(t .. '/PhotoActive/1234-5/vignette.jpg'), 'la vignette reste')
    Fenetre.ouverte, Moteur.travaille = ouverte, travaille
    egal(2, Menage.temporaires(), 'fermée : effacés')
end)

essai("Init.lua : le ménage de Temporaire passe en premier dans la tâche, avant Session.menage (qui attend la fin des processus)", function()
    local code = lireTout(S.plugin .. '/Init.lua')
    local tache = code:match('LrTasks%.startAsyncTask%(function%(%)(.-)\nend%)')
    vrai(tache, 'la tâche de ménage')
    local menage, session = tache:find('Menage', 1, true), tache:find('Session', 1, true)
    vrai(menage and session and menage < session, 'Menage.temporaires avant Session.menage')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
