-- essais-dossier-commun.lua : le dossier commun (demandé par Dany le 3 novembre 2026 : deux Mac, le
-- SSD « Photos » qui passe de l'un à l'autre ; « je reprends le travail où je l'avais arrêté »),
-- hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : la racine locale par défaut, le
-- pointeur relu à chaque accès, le dossier commun introuvable (refus partout, rien d'écrit ailleurs,
-- le Suivi en pause), le rebasage des chemins rangés, le réglage (copie avec progression, mise de
-- côté, deuxième Mac, retour au dossier de ce Mac, refus), la section du Gestionnaire, relais.sh
-- (l'échange de la session Claude Code copié du dossier commun avant --resume, puis vers lui après
-- la fin) avec faux-claude.sh, et uninstall.sh --tout. Tout se passe dans un dossier personnel
-- temporaire (S.home) : jamais les vrais dossiers de Dany, ni son vrai ~/.claude, ni son pointeur.
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

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

-- Garde-fou : tout ici se passe dans le dossier personnel temporaire.
assert(S.home:match('^/tmp/') or S.home:match('^/private/') or S.home:match('^/var/folders/'),
    'dossier personnel simulé inattendu : ' .. S.home)

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'

local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')

local locale = Chemins.locale()
-- Le SSD simulé, avec espaces et accents (« Développeur ») comme sur le vrai.
local ssd = S.home .. '/Volumes/Photos'
local commun = ssd .. '/Développeur partagé'

local function ecrire(chemin, texte)
    Fichiers.ecrire(chemin, texte)
end

local function poserPointeur(dossier)
    ecrire(Chemins.pointeur(), Json.encode({ format = 1, dossier = dossier }))
end

local function retirerPointeur()
    Fichiers.supprimer(Chemins.pointeur())
end

local function vider(chemin)
    S.executer('rm -rf ' .. S.q(chemin))
end

local function sous(chemin, racine)
    return type(chemin) == 'string' and chemin:sub(1, #racine + 1) == racine .. '/'
end

-- Les chemins des fichiers de données (point 3) et des fichiers locaux (point 4), tels que les
-- modules les donnent.
local function cheminsDonnees()
    return {
        carnet = require('Carnet').fichier(),
        notation = require('Notation').fichier(),
        consommation = require('Consommation').fichier(),
        publication = require('Publication').fichierProfils(),
        suivi = require('Releve').fichier(),
        journal = require('Releve').fichierJournal(),
        demandes = require('Stockage').fichierDemandes(),
        conversations = Chemins.conversations(),
        conversation = require('Stockage').fichier('abc'),
        etapes = Chemins.etapes(),
        claudeCode = Chemins.claudeCode(),
    }
end

local function cheminsLocaux()
    return {
        sessions = Chemins.sessions(), atelier = Chemins.atelier(), configMCP = Chemins.configMCP(),
        temporaire = Chemins.temporaire(), pointeur = Chemins.pointeur(),
    }
end

-- Racine des données --------------------------------------------------------------------------

essai('Sans pointeur : tout reste dans la racine locale, comme avant', function()
    retirerPointeur()
    egal(false, Chemins.dossierCommun().regle)
    egal(locale, Chemins.donnees())
    egal(nil, Chemins.refusDonnees())
    for nom, chemin in pairs(cheminsDonnees()) do
        vrai(sous(chemin, locale), nom .. ' : ' .. chemin)
    end
    egal(locale .. '/carnet.json', require('Carnet').fichier())
    egal(locale .. '/Conversations', Chemins.conversations())
    egal(locale .. '/Claude Code', Chemins.claudeCode())
    egal(locale .. '/dossier-commun.json', Chemins.pointeur())
end)

essai('Pointeur illisible, sans « dossier » ou avec un dossier vide : pas de dossier commun', function()
    for _, texte in ipairs({ '', 'pas du json', '{"format":1}', '{"format":1,"dossier":""}', '{"format":1,"dossier":"   "}', '[]' }) do
        ecrire(Chemins.pointeur(), texte)
        egal(false, Chemins.dossierCommun().regle, texte)
        egal(locale, Chemins.donnees(), texte)
    end
    retirerPointeur()
end)

essai('Dossier commun réglé : les données du point 3 y vont, le reste reste local ; le pointeur est relu à chaque accès', function()
    S.executer('mkdir -p ' .. S.q(commun))
    poserPointeur(commun .. '/')
    local etat = Chemins.dossierCommun()
    egal(true, etat.regle)
    egal(commun, etat.chemin, 'sans la barre finale')
    egal(true, etat.present)
    egal(commun, Chemins.donnees())
    for nom, chemin in pairs(cheminsDonnees()) do
        vrai(sous(chemin, commun), nom .. ' : ' .. chemin)
    end
    for nom, chemin in pairs(cheminsLocaux()) do
        vrai(sous(chemin, locale), nom .. ' reste local : ' .. chemin)
    end
    egal(commun .. '/Claude Code', Chemins.claudeCode())
    -- Changé pendant que le module tourne : suivi tout de suite, sans rien recharger.
    local autre = S.home .. '/Autre dossier'
    S.executer('mkdir -p ' .. S.q(autre))
    poserPointeur(autre)
    egal(autre .. '/carnet.json', require('Carnet').fichier())
    retirerPointeur()
    egal(locale .. '/carnet.json', require('Carnet').fichier())
end)

essai('Registres en mémoire : relus quand la racine des données change (jamais écrits dans l’autre)', function()
    local Consommation = require 'Consommation'
    retirerPointeur()
    Consommation.oublier()
    ecrire(locale .. '/consommation.json', Json.encode({ demandes = {}, budgetSemaine = 111 }))
    egal(111, Consommation.charger().budgetSemaine)
    ecrire(commun .. '/consommation.json', Json.encode({ demandes = {}, budgetSemaine = 222 }))
    poserPointeur(commun)
    egal(222, Consommation.charger().budgetSemaine, 'relu du dossier commun')
    retirerPointeur()
    egal(111, Consommation.charger().budgetSemaine, 'relu du dossier de ce Mac')
    Consommation.oublier()
    Fichiers.supprimer(locale .. '/consommation.json')
    Fichiers.supprimer(commun .. '/consommation.json')
end)

-- Dossier commun introuvable ------------------------------------------------------------------

local absent = S.home .. '/Volumes/Photos débranché/Développeur'
local MESSAGE = "Le dossier commun (" .. absent .. ") est introuvable : branchez le SSD qui le contient, ou réglez un autre dossier dans Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom."

-- Aucun fichier de données écrit dans la racine locale (aucun repli), ni le dossier absent créé.
local function rienEcrit()
    for _, nom in ipairs(Chemins.NOMS_DONNEES) do
        vrai(not Fichiers.existe(locale .. '/' .. nom), 'écrit localement : ' .. nom)
    end
    vrai(not Fichiers.existe(absent), 'dossier absent créé')
end

essai('Introuvable : Chemins.donnees refuse avec le message, jamais la racine locale', function()
    vider(locale)
    poserPointeur(absent)
    local etat = Chemins.dossierCommun()
    egal(true, etat.regle)
    egal(false, etat.present)
    egal(MESSAGE, Chemins.refusDonnees())
    egal(MESSAGE, Chemins.messageAbsent(absent))
    local ok, erreur = pcall(Chemins.donnees)
    egal(false, ok)
    egal(MESSAGE, erreur)
    for _, f in ipairs({ function() return require('Carnet').fichier() end, function() return require('Notation').fichier() end,
        function() return require('Consommation').fichier() end, function() return require('Publication').fichierProfils() end,
        function() return require('Releve').fichier() end, function() return require('Releve').fichierJournal() end,
        function() return require('Stockage').fichierDemandes() end, Chemins.conversations, Chemins.etapes, Chemins.claudeCode }) do
        local okF, e = pcall(f)
        egal(false, okF, 'chemin rendu : ' .. tostring(e))
        egal(MESSAGE, e)
    end
    -- Les chemins locaux restent.
    egal(locale .. '/Sessions', Chemins.sessions())
    egal(locale .. '/Temporaire', Chemins.temporaire())
    rienEcrit()
end)

essai('Introuvable : écritures refusées (Mes demandes, consommation, carnet, notes, conversation), rien d’écrit ailleurs', function()
    poserPointeur(absent)
    local Stockage = require 'Stockage'
    local ok, raison = Stockage.garderDemande({ nom = 'Ciel', texte = 'Assombris le ciel' })
    egal(false, ok)
    egal(MESSAGE, raison)
    local Consommation = require 'Consommation'
    Consommation.oublier()
    egal(false, (pcall(Consommation.charger)))
    egal(false, (pcall(Consommation.ajouter, { date = os.time(), usage = {} })))
    egal(false, (pcall(Stockage.enregistrer, { id = 'abc', elements = {} })))
    local okC = pcall(function() return require('Carnet').nombre() end)
    egal(false, okC, 'carnet refusé')
    rienEcrit()
end)

essai('Introuvable : la demande (fenêtre Claude, Demande rapide) est refusée avec le message, Claude Code ne part pas', function()
    poserPointeur(absent)
    local Moteur = require 'Moteur'
    Moteur.travaille = false
    S.dernieresCommandes = {}
    local ok, raison = Moteur.envoyer('Retouche la photo')
    egal(false, ok)
    egal(MESSAGE, raison)
    local c, r = Moteur.envoyerRapide('Retouche la photo')
    egal(nil, c)
    egal(MESSAGE, r)
    egal(false, Moteur.travaille == true, 'Claude ne travaille pas')
    for _, commande in ipairs(S.dernieresCommandes) do
        vrai(not commande:find('relais.sh', 1, true), 'relais lancé : ' .. commande)
    end
    -- Session:lancer refuse aussi (aucune autre voie).
    local Session = require 'Session'
    local s = Session.nouvelle({ idConversation = 'x', claude = '/bin/echo', connecteur = '/bin/echo', modele = 'haiku',
        travail = Chemins.atelier(), consignes = '' })
    local okL, e = pcall(function() s:lancer('{}') end)
    egal(false, okL)
    egal(MESSAGE, e)
    rienEcrit()
end)

essai('Introuvable : les fenêtres Claude, Demande rapide, Suivi, Publication et Consommation le disent au lieu de s’ouvrir', function()
    poserPointeur(absent)
    for _, nom in ipairs({ 'Fenetre', 'FenetreRapide', 'FenetreSuivi', 'FenetrePublication', 'FenetreConsommation' }) do
        local m = require(nom)
        local avant = #S.messages
        m.afficher()
        egal(avant + 1, #S.messages, nom .. ' : un message')
        egal(MESSAGE, S.messages[#S.messages][2], nom)
        vrai(not m.ouverte, nom .. ' ne s’ouvre pas')
    end
    rienEcrit()
end)

essai('Introuvable : le Suivi se met en pause sans rien écrire, et reprend quand le dossier revient', function()
    local Releve = require 'Releve'
    Releve.oublier()
    Releve.allumer()
    poserPointeur(absent)
    Releve.prochaineVerification = 0
    Releve.aVoir = { { photos = {}, le = os.time() } }
    local taches = #S.taches
    egal(false, Releve.relancer(), 'aucune tâche')
    egal(taches, #S.taches)
    egal(MESSAGE, Releve.enPause)
    egal(false, Releve.ecrire(), 'rien à écrire ni écrit')
    rienEcrit()
    -- Le SSD rebranché : la tâche repart (dans le dossier commun).
    S.executer('mkdir -p ' .. S.q(absent))
    egal(true, Releve.relancer(), 'le relevé reprend')
    egal(nil, Releve.enPause)
    Releve.enCours = false
    S.taches[#S.taches] = nil
    Releve.aVoir = {}
    Releve.eteindre()
    Releve.oublier()
    vider(S.home .. '/Volumes/Photos débranché')
    retirerPointeur()
end)

-- Rebasage ------------------------------------------------------------------------------------

essai('Rebasage : un chemin rangé sur l’autre Mac ou avant le dossier commun se lit dans la racine actuelle', function()
    retirerPointeur()
    local ancien = '/Users/autre-nom/Library/Application Support/Developpeur/Conversations/abc/image-1.jpg'
    egal(locale .. '/Conversations/abc/image-1.jpg', Chemins.rebaser(ancien))
    poserPointeur(commun)
    egal(commun .. '/Conversations/abc/image-1.jpg', Chemins.rebaser(ancien))
    egal(commun .. '/Etapes/u/1-avant.jpg', Chemins.rebaser('/Users/danymenard/Library/Application Support/Developpeur/Etapes/u/1-avant.jpg'))
    egal(commun .. '/Claude Code/s.jsonl', Chemins.rebaser('/Users/x/Library/Application Support/Developpeur/Claude Code/s.jsonl'))
    egal(commun .. '/suivi-illisible-12.json', Chemins.rebaser('/Users/x/Library/Application Support/Developpeur/suivi-illisible-12.json'))
    -- Ce qui reste local, un autre chemin, une image relative : tels quels.
    local session = '/Users/x/Library/Application Support/Developpeur/Sessions/abc/sortie.jsonl'
    egal(session, Chemins.rebaser(session))
    egal('/Volumes/Photos/2026/DSCF1.RAF', Chemins.rebaser('/Volumes/Photos/2026/DSCF1.RAF'))
    egal('image-1.jpg', Chemins.rebaser('image-1.jpg'))
    egal(nil, Chemins.rebaser(nil))
    -- Introuvable : tel quel (la lecture sera refusée ailleurs), jamais la racine locale.
    poserPointeur(absent)
    egal(ancien, Chemins.rebaser(ancien))
    retirerPointeur()
end)

essai('Rebasage : une conversation relue (Stockage.lire) a son dossier et ses images absolues rebasés', function()
    poserPointeur(commun)
    local Stockage = require 'Stockage'
    ecrire(Stockage.fichier('rebase'), Json.encode({ id = 'rebase', format = Stockage.FORMAT,
        dossier = '/Users/autre/Library/Application Support/Developpeur/Conversations/rebase',
        elements = { { genre = 'apercu', images = { 'image-1.jpg', '/Users/autre/Library/Application Support/Developpeur/Conversations/rebase/image-2.jpg' } } } }))
    local c = Stockage.lire('rebase')
    egal(commun .. '/Conversations/rebase', c.dossier)
    egal('image-1.jpg', c.elements[1].images[1])
    egal(commun .. '/Conversations/rebase/image-2.jpg', c.elements[1].images[2])
    vider(commun .. '/Conversations')
    retirerPointeur()
end)

-- Réglage : copie, mise de côté, deuxième Mac, retour -------------------------------------------

local DossierCommun = require 'DossierCommun'
local Texte = require 'Texte'

-- Les volumes simulés (le choix s'ouvre sur le SSD Photos) : jamais le vrai /Volumes/Photos.
DossierCommun.VOLUMES = S.home .. '/Volumes'
DossierCommun.VOLUME_PHOTOS = S.home .. '/Volumes/Photos'

-- Le dossier de projet de Claude Code : le chemin physique du dossier de travail, chaque caractère
-- (UTF-8) qui n'est ni lettre ASCII ni chiffre remplacé par « - ».
local function encoder(chemin)
    return (chemin:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c)
        if c:match('^[A-Za-z0-9]$') then
            return c
        end
        return '-'
    end))
end

-- Le ~/.claude simulé (CLAUDE_CONFIG_DIR), jamais le vrai : posé sur toute commande de relais.sh
-- (relais.sh --projet du réglage, et le relais lui-même).
local configClaude = S.home .. '/.claude'
local executerSansClaude = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = 'CLAUDE_CONFIG_DIR=' .. S.q(configClaude) .. ' ' .. commande
    end
    return executerSansClaude(commande)
end

-- Les données d'un Mac : fichiers, dossiers imbriqués, copie illisible, et ce qui reste local.
local function donneesDuMac(racine, marque)
    ecrire(racine .. '/carnet.json', '{"carnet":"' .. marque .. '"}')
    ecrire(racine .. '/suivi.json', '{"suivi":"' .. marque .. '"}')
    ecrire(racine .. '/suivi.journal', 'ligne ' .. marque .. '\n')
    ecrire(racine .. '/suivi-illisible-1.json', 'illisible')
    ecrire(racine .. '/mes-demandes.json', '{"format":1,"demandes":[]}')
    ecrire(racine .. '/guide-de-style.md', '# Style ' .. marque)
    ecrire(racine .. '/Conversations/c1/conversation.json', '{"id":"c1"}')
    ecrire(racine .. '/Conversations/c1/image 1.jpg', string.rep('x', 3000))
    ecrire(racine .. '/Etapes/uuid/1-avant.jpg', 'avant')
    ecrire(racine .. '/Index/Sous dossier/index.bin', 'index')
    ecrire(racine .. '/Claude Code/s1.jsonl', '{"l":1}')
end

local function localSeulement()
    ecrire(locale .. '/connecteur.json', '{}')
    ecrire(locale .. '/liaison.jeton', 'jeton-essai')
    ecrire(locale .. '/Sessions/s/sortie.jsonl', '')
    ecrire(locale .. '/mcp-developpeur', 'binaire')
end

essai('Copie récursive : dossiers imbriqués, fichiers vérifiés, progression, jamais par-dessus un fichier', function()
    local source = S.home .. '/arbre source'
    vider(source)
    ecrire(source .. '/a.txt', 'a')
    ecrire(source .. '/d/b.txt', 'bb')
    ecrire(source .. '/d/é e/c.txt', 'ccc')
    ecrire(source .. '/.cache', 'caché')
    local dest = S.home .. '/arbre copié'
    vider(dest)
    egal(4, DossierCommun.compter(source))
    local pas = 0
    egal(4, DossierCommun.copierArbre(source, dest, function() pas = pas + 1 return true end))
    egal(4, pas)
    egal('ccc', Fichiers.lire(dest .. '/d/é e/c.txt'))
    egal('caché', Fichiers.lire(dest .. '/.cache'))
    egal('a', Fichiers.lire(source .. '/a.txt'), 'la source reste')
    local ok, e = pcall(DossierCommun.copierArbre, source, dest)
    egal(false, ok)
    contient(e, 'existe déjà')
    -- Interrompue : une erreur.
    vider(dest)
    local okI, eI = pcall(DossierCommun.copierArbre, source, dest, function() return false end)
    egal(false, okI)
    contient(eI, 'interrompue')
    vider(source)
    vider(dest)
end)

essai('Choisir un dossier vide : les données de ce Mac y sont copiées avec progression, puis mises de côté ; le pointeur est écrit', function()
    retirerPointeur()
    vider(locale)
    vider(ssd)
    S.executer('mkdir -p ' .. S.q(commun))
    donneesDuMac(locale, 'mac-a')
    localSeulement()
    local total, appels = nil, 0
    local r = DossierCommun.choisir(commun, {
        debut = function(n) total = n end,
        avancer = function(fait, n) appels = appels + 1; egal(total, n) return true end,
    })
    egal(11, total, 'fichiers à copier')
    egal(11, appels)
    egal(11, r.copies)
    egal(false, r.pris)
    egal(locale, r.source)
    -- Dans le dossier commun, tel quel.
    egal('{"carnet":"mac-a"}', Fichiers.lire(commun .. '/carnet.json'))
    egal(string.rep('x', 3000), Fichiers.lire(commun .. '/Conversations/c1/image 1.jpg'))
    egal('index', Fichiers.lire(commun .. '/Index/Sous dossier/index.bin'))
    egal('illisible', Fichiers.lire(commun .. '/suivi-illisible-1.json'))
    egal('{"l":1}', Fichiers.lire(commun .. '/Claude Code/s1.jsonl'))
    -- Rien de local n'y va ; aucun dossier provisoire ne reste.
    for _, nom in ipairs({ 'connecteur.json', 'liaison.jeton', 'Sessions', 'mcp-developpeur', 'dossier-commun.json' }) do
        vrai(not Fichiers.existe(commun .. '/' .. nom), 'copié à tort : ' .. nom)
    end
    egal('', S.lireCommande('ls -A ' .. S.q(commun) .. ' | grep copie-en-cours || true'):gsub('%s+$', ''), 'dossier provisoire resté')
    -- Les données de ce Mac mises de côté, jamais effacées ; le local reste.
    vrai(r.miseDeCote and r.miseDeCote:find(locale .. '/Avant le dossier commun ', 1, true) == 1, tostring(r.miseDeCote))
    vrai(r.miseDeCote:match('Avant le dossier commun %d%d%d%d%-%d%d%-%d%d %d%d%-%d%d$'), r.miseDeCote)
    egal('{"carnet":"mac-a"}', Fichiers.lire(r.miseDeCote .. '/carnet.json'))
    egal(string.rep('x', 3000), Fichiers.lire(r.miseDeCote .. '/Conversations/c1/image 1.jpg'))
    for _, nom in ipairs(Chemins.NOMS_DONNEES) do
        vrai(not Fichiers.existe(locale .. '/' .. nom), 'resté dans la racine locale : ' .. nom)
    end
    egal('jeton-essai', Fichiers.lire(locale .. '/liaison.jeton'))
    egal('binaire', Fichiers.lire(locale .. '/mcp-developpeur'))
    vrai(Fichiers.existe(locale .. '/Sessions/s/sortie.jsonl'))
    -- Le pointeur.
    local p = Json.decode(Fichiers.lire(Chemins.pointeur()))
    egal(1, p.format)
    egal(commun, p.dossier)
    egal(commun, Chemins.donnees())
    egal(commun .. '/carnet.json', require('Carnet').fichier())
    -- Le texte montré.
    local texte = DossierCommun.texteChoix(r)
    contient(texte, '11 fichiers copiés depuis ' .. locale)
    contient(texte, 'mises de côté')
    egal(commun, DossierCommun.texteEtat())
end)

essai('Deuxième Mac : un dossier qui a déjà des données est pris tel quel, celles de ce Mac mises de côté', function()
    retirerPointeur()
    -- Le dossier commun garde les données du Mac A ; ce Mac (B) a les siennes.
    vider(locale)
    donneesDuMac(locale, 'mac-b')
    localSeulement()
    local r = DossierCommun.choisir(commun)
    egal(true, r.pris)
    egal(0, r.copies)
    egal('{"carnet":"mac-a"}', Fichiers.lire(commun .. '/carnet.json'), 'rien n’est écrasé')
    egal('# Style mac-a', Fichiers.lire(commun .. '/guide-de-style.md'))
    egal('{"carnet":"mac-b"}', Fichiers.lire(r.miseDeCote .. '/carnet.json'), 'les données de B mises de côté')
    vrai(not Fichiers.existe(locale .. '/carnet.json'))
    egal(commun, Chemins.donnees())
    contient(DossierCommun.texteChoix(r), 'prises telles quelles')
end)

essai('Revenir au dossier de ce Mac : le pointeur est retiré, rien n’est copié ni effacé', function()
    poserPointeur(commun)
    local avant = S.lireCommande('cd ' .. S.q(commun) .. ' && find . | sort')
    local quitte = DossierCommun.revenir()
    egal(commun, quitte)
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur retiré')
    egal(locale, Chemins.donnees())
    egal(avant, S.lireCommande('cd ' .. S.q(commun) .. ' && find . | sort'), 'dossier commun inchangé')
    vrai(not Fichiers.existe(locale .. '/carnet.json'), 'rien copié vers ce Mac')
    egal(nil, DossierCommun.revenir(), 'déjà revenu')
end)

essai('Choisir : refus (dossier introuvable, dans ou autour du dossier de ce Mac, déjà réglé) ; interruption sans rien changer', function()
    retirerPointeur()
    contient(DossierCommun.refus(S.home .. '/nulle part'), 'introuvable')
    S.executer('mkdir -p ' .. S.q(locale .. '/Dedans'))
    contient(DossierCommun.refus(locale), 'hors de')
    contient(DossierCommun.refus(locale .. '/Dedans'), 'hors de')
    contient(DossierCommun.refus(S.home .. '/Library'), 'hors de')
    contient(DossierCommun.refus('relatif'), 'chemin complet')
    poserPointeur(commun)
    contient(DossierCommun.refus(commun), 'déjà le dossier commun')
    local ok = pcall(DossierCommun.choisir, commun)
    egal(false, ok)
    retirerPointeur()
    -- Interrompu pendant la copie : ni pointeur, ni mise de côté, données de ce Mac intactes.
    vider(locale)
    donneesDuMac(locale, 'mac-c')
    local vide = S.home .. '/SSD vide'
    vider(vide)
    S.executer('mkdir -p ' .. S.q(vide))
    local okI, e = pcall(DossierCommun.choisir, vide, { avancer = function(fait) return fait < 3 end })
    egal(false, okI)
    contient(e, 'interrompue')
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur non écrit')
    egal('{"carnet":"mac-c"}', Fichiers.lire(locale .. '/carnet.json'), 'données de ce Mac intactes')
    egal(false, DossierCommun.aDesDonnees(vide), 'une copie interrompue n’est jamais prise pour des données')
    -- Un nouvel essai réussit (la copie interrompue reste à part, cachée, jamais effacée).
    local r = DossierCommun.choisir(vide)
    egal(false, r.pris)
    egal('{"carnet":"mac-c"}', Fichiers.lire(vide .. '/carnet.json'))
    retirerPointeur()
end)

essai('Choisir pendant que le Suivi tourne : il est éteint le temps du changement, puis rallumé', function()
    local Releve = require 'Releve'
    Releve.allumer()
    local vu
    local eteindre = Releve.eteindre
    Releve.eteindre = function() vu = true; eteindre() end
    vider(locale)
    local autre = S.home .. '/SSD suivi'
    vider(autre)
    S.executer('mkdir -p ' .. S.q(autre))
    DossierCommun.choisir(autre)
    Releve.eteindre = eteindre
    egal(true, vu, 'éteint pendant le changement')
    egal(true, Releve.allume, 'rallumé')
    Releve.eteindre()
    retirerPointeur()
end)

-- Réglage : défauts relevés à la revue du 3 novembre 2026 -------------------------------------------

-- Toutes les données du Mac (donneesDuMac) dans un dossier.
local function toutesLesDonnees(racine, marque)
    egal('{"carnet":"' .. marque .. '"}', Fichiers.lire(racine .. '/carnet.json'), 'carnet')
    egal('{"suivi":"' .. marque .. '"}', Fichiers.lire(racine .. '/suivi.json'), 'suivi')
    egal('# Style ' .. marque, Fichiers.lire(racine .. '/guide-de-style.md'), 'guide')
    egal('avant', Fichiers.lire(racine .. '/Etapes/uuid/1-avant.jpg'), 'étapes')
    egal('index', Fichiers.lire(racine .. '/Index/Sous dossier/index.bin'), 'index')
    egal('{"id":"c1"}', Fichiers.lire(racine .. '/Conversations/c1/conversation.json'), 'conversation')
end

-- Un dossier vide, prêt à être choisi.
local function dossierVide(nom)
    local d = S.home .. '/' .. nom
    vider(d)
    S.executer('mkdir -p ' .. S.q(d))
    return d
end

essai('Pendant le changement, la liaison est fermée (Chemins.changement), puis rouverte ; même après une erreur', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-l')
    local vus = {}
    local r = DossierCommun.choisir(dossierVide('SSD liaison'), { avancer = function() vus[#vus + 1] = Chemins.changement return true end })
    vrai(#vus > 0 and vus[1] == true, 'liaison fermée pendant la copie')
    egal(false, Chemins.changement, 'rouverte après')
    egal(false, DossierCommun.enCours)
    egal(false, r.pris)
    -- Interrompue : rouverte aussi.
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-l')
    egal(false, (pcall(DossierCommun.choisir, dossierVide('SSD liaison 2'), { avancer = function() return false end })))
    egal(false, Chemins.changement, 'rouverte après une erreur')
    egal(false, DossierCommun.enCours, 'plus en cours après une erreur')
    retirerPointeur()
end)

essai('Une commande de la liaison déjà commencée : attendue, sinon refus sans rien changer', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-e')
    local Liaison = require 'Liaison'
    local attente = DossierCommun.ATTENTE_LIAISON
    DossierCommun.ATTENTE_LIAISON = 0.2
    Liaison.enCours = 1
    local cible = dossierVide('SSD occupé')
    local ok, e = pcall(DossierCommun.choisir, cible)
    Liaison.enCours = 0
    DossierCommun.ATTENTE_LIAISON = attente
    egal(false, ok)
    contient(e, 'par la liaison')
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur non écrit')
    egal(false, DossierCommun.aDesDonnees(cible), 'rien copié')
    egal('{"carnet":"mac-e"}', Fichiers.lire(locale .. '/carnet.json'), 'données de ce Mac en place')
    egal(false, Chemins.changement)
end)

essai('Un fichier changé pendant la copie (après la sienne) est recopié : le dossier commun a sa dernière version', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-r')
    local cible = dossierVide('SSD recopie')
    local r = DossierCommun.choisir(cible, { avancer = function(fait)
        -- « Claude Code/s1.jsonl » est copié le premier ; le serveur (ou l'autre) le change après.
        if fait == 1 then
            ecrire(locale .. '/Claude Code/s1.jsonl', '{"l":1}\n{"l":2}\n')
        end
        return true
    end })
    egal('{"l":1}\n{"l":2}\n', Fichiers.lire(cible .. '/Claude Code/s1.jsonl'), 'recopié')
    toutesLesDonnees(cible, 'mac-r')
    egal(nil, r.changesApres)
    retirerPointeur()
end)

essai('Choisir pendant un autre changement : refusé (choisir, revenir, et le bouton du Gestionnaire)', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-d')
    local autre = dossierVide('SSD deuxième')
    local refusChoisir, refusRevenir
    local r = DossierCommun.choisir(dossierVide('SSD premier'), { avancer = function(fait)
        if fait == 1 then
            local ok, e = pcall(DossierCommun.choisir, autre)
            refusChoisir = not ok and e
            local okR, eR = pcall(DossierCommun.revenir)
            refusRevenir = not okR and eR
        end
        return true
    end })
    egal(DossierCommun.EN_COURS, refusChoisir, 'deuxième choix refusé')
    egal(DossierCommun.EN_COURS, refusRevenir, 'retour refusé')
    egal(false, DossierCommun.aDesDonnees(autre), 'rien copié dans le deuxième')
    egal(S.home .. '/SSD premier', Chemins.dossierCommun().chemin, 'le premier seul est réglé')
    egal(false, r.pris)
    -- Le bouton Choisir… du Gestionnaire, pendant un changement : dit, sans ouvrir le choix.
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local section = PluginInfoProvider.sectionsForTopOfDialog(f, S.modules.LrBinding.makePropertyTable())[3]
    local bouton
    local function parcourir(v)
        if type(v) ~= 'table' then return end
        if v.genre and S.BOUTONS[v.genre] and v.args.title == 'Choisir…' then bouton = v end
        for _, enfant in ipairs(v.args or v) do parcourir(enfant) end
    end
    parcourir(section)
    local ouvert = false
    local runOpenPanel = S.modules.LrDialogs.runOpenPanel
    S.modules.LrDialogs.runOpenPanel = function() ouvert = true return nil end
    DossierCommun.enCours = true
    bouton.args.action()
    DossierCommun.enCours = false
    S.modules.LrDialogs.runOpenPanel = runOpenPanel
    egal(false, ouvert, 'choix non ouvert')
    egal(DossierCommun.EN_COURS, S.messages[#S.messages][2])
    retirerPointeur()
end)

essai('Ancien dossier commun introuvable : un dossier vide est refusé (jamais les restes de ce Mac copiés) ; un dossier qui a des données est pris', function()
    vider(locale)
    -- Ce qui traîne dans la racine locale (Modeles recréé par install.sh) n'est pas les données.
    ecrire(locale .. '/Modeles/especes.tsv', 'reste')
    poserPointeur(absent)
    local vide = dossierVide('SSD dépannage')
    local refus = DossierCommun.refus(vide)
    contient(refus, MESSAGE, 'le message du dossier introuvable')
    contient(refus, 'Revenir au dossier de ce Mac')
    local ok, e = pcall(DossierCommun.choisir, vide)
    egal(false, ok)
    contient(e, MESSAGE)
    egal(absent, Chemins.dossierCommun().chemin, 'pointeur inchangé')
    egal(false, DossierCommun.aDesDonnees(vide), 'rien copié')
    egal('reste', Fichiers.lire(locale .. '/Modeles/especes.tsv'))
    -- Un dossier dont le rangement s'est arrêté (la copie y est entière) : accepté, rangement terminé.
    local marque = dossierVide('SSD rangement arrêté')
    ecrire(marque .. '/.copie-en-cours-1/carnet.json', '{"carnet":"copie"}')
    ecrire(marque .. '/' .. DossierCommun.MARQUE_RANGEMENT, Json.encode({ format = 1, provisoire = '.copie-en-cours-1', noms = { 'carnet.json' } }))
    egal(nil, DossierCommun.refus(marque), 'rangement à terminer : accepté')
    -- Un dossier qui a déjà des données (l'autre Mac, le SSD monté ailleurs) : pris.
    local plein = dossierVide('SSD monté ailleurs')
    donneesDuMac(plein, 'ssd')
    local r = DossierCommun.choisir(plein)
    egal(true, r.pris)
    egal(plein, Chemins.dossierCommun().chemin)
    toutesLesDonnees(plein, 'ssd')
    retirerPointeur()
end)

essai('Rangement interrompu (déplacement manqué au milieu) : le choix suivant le termine, rien n’est pris à moitié', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-i')
    local cible = dossierVide('SSD rangement')
    local move = S.modules.LrFileUtils.move
    local ranges = 0
    S.modules.LrFileUtils.move = function(a, b)
        if a:find('/.copie-en-cours-', 1, true) then
            ranges = ranges + 1
            if ranges > 2 then
                error('panne simulée pendant le rangement', 0)
            end
        end
        return move(a, b)
    end
    local ok = pcall(DossierCommun.choisir, cible)
    S.modules.LrFileUtils.move = move
    egal(false, ok)
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur non écrit')
    vrai(DossierCommun.rangementInterrompu(cible), 'marque du rangement restée')
    vrai(DossierCommun.aDesDonnees(cible), 'une partie déjà rangée')
    vrai(not Fichiers.existe(cible .. '/suivi.json'), 'le reste dans le dossier provisoire')
    -- Le choix suivant termine le rangement : tout est là, rien ne reste caché.
    local r = DossierCommun.choisir(cible)
    egal(true, r.rangementTermine)
    egal(true, r.pris)
    toutesLesDonnees(cible, 'mac-i')
    vrai(not DossierCommun.rangementInterrompu(cible), 'marque retirée')
    egal('', S.lireCommande('ls -A ' .. S.q(cible) .. ' | grep copie-en-cours || true'):gsub('%s+$', ''), 'dossier provisoire resté')
    contient(DossierCommun.texteChoix(r), "s'était arrêté pendant le rangement")
    toutesLesDonnees(r.miseDeCote, 'mac-i')
    retirerPointeur()
end)

essai('Le pointeur est écrit avant la mise de côté ; une mise de côté manquée laisse le réglage fait et les données en place', function()
    retirerPointeur()
    vider(locale)
    donneesDuMac(locale, 'mac-p')
    local cible = dossierVide('SSD pointeur')
    local move = S.modules.LrFileUtils.move
    local pointeurAvant, deplaces = nil, 0
    S.modules.LrFileUtils.move = function(a, b)
        if b:find('/Avant le dossier commun ', 1, true) then
            if pointeurAvant == nil then
                pointeurAvant = Fichiers.existe(Chemins.pointeur())
            end
            deplaces = deplaces + 1
            if deplaces > 2 then
                error('panne simulée pendant la mise de côté', 0)
            end
        end
        return move(a, b)
    end
    local ok, r = pcall(DossierCommun.choisir, cible)
    S.modules.LrFileUtils.move = move
    vrai(ok, tostring(r))
    egal(true, pointeurAvant, 'pointeur déjà écrit à la mise de côté')
    egal(cible, Chemins.dossierCommun().chemin, 'réglage fait')
    vrai(r.miseDeCoteRatee, 'mise de côté manquée, dite')
    egal(nil, r.miseDeCote)
    toutesLesDonnees(locale, 'mac-p')
    toutesLesDonnees(cible, 'mac-p')
    egal('', S.lireCommande('ls -A ' .. S.q(locale) .. ' | grep "Avant le dossier commun" || true'):gsub('%s+$', ''), 'aucun dossier vide laissé')
    contient(DossierCommun.texteChoix(r), "n'ont pas pu être mises de côté")
    retirerPointeur()
end)

essai('La copie rend la main à Lightroom (Photos.rendreLaMain) pendant copierArbre', function()
    local source = S.home .. '/arbre rendu'
    vider(source)
    for i = 1, 6 do
        ecrire(source .. '/d/f' .. i .. '.txt', tostring(i))
    end
    local dest = S.home .. '/arbre rendu copié'
    vider(dest)
    local yield = S.modules.LrTasks.yield
    local rendus = 0
    S.modules.LrTasks.yield = function() rendus = rendus + 1 end
    local pas = DossierCommun.PAS_RENDRE
    DossierCommun.PAS_RENDRE = 2
    local n = DossierCommun.copierArbre(source, dest)
    DossierCommun.PAS_RENDRE = pas
    S.modules.LrTasks.yield = yield
    egal(6, n)
    egal(3, rendus, 'une fois tous les 2 fichiers')
    vider(source)
    vider(dest)
end)

essai('Les échanges de Claude Code des conversations de ce Mac sont copiés dans « Claude Code/ » (seulement leurs .jsonl)', function()
    retirerPointeur()
    vider(locale)
    vider(configClaude)
    Fichiers.creerDossier(Chemins.atelier())
    local projetMigration = configClaude .. '/projects/' .. encoder(S.lireCommande('cd ' .. S.q(Chemins.atelier()) .. ' && pwd -P'):gsub('%s+$', ''))
    ecrire(locale .. '/Conversations/ca/conversation.json', Json.encode({ id = 'ca', sessionID = 'sess-a', elements = {} }))
    ecrire(locale .. '/Conversations/cb/conversation.json', Json.encode({ id = 'cb', sessionID = 'sess-b', elements = {} }))
    ecrire(locale .. '/Conversations/cc/conversation.json', Json.encode({ id = 'cc', sessionID = 'sess-c', elements = {} }))
    ecrire(locale .. '/Conversations/cd/conversation.json', Json.encode({ id = 'cd', sessionID = '../dehors', elements = {} }))
    ecrire(locale .. '/Conversations/ce/conversation.json', Json.encode({ id = 'ce', elements = {} }))
    -- sess-c est déjà rangé (repris une fois) : gardé tel quel.
    ecrire(locale .. '/Claude Code/sess-c.jsonl', 'deja-range\n')
    ecrire(projetMigration .. '/sess-a.jsonl', 'echange-a\n')
    ecrire(projetMigration .. '/sess-c.jsonl', 'echange-c-local\n')
    -- Ce qui ne doit jamais partir : une autre session, les fichiers de connexion et réglages.
    ecrire(projetMigration .. '/autre.jsonl', 'autre\n')
    ecrire(configClaude .. '/projects/dehors.jsonl', 'dehors\n')
    ecrire(configClaude .. '/.credentials.json', '{"secret":1}')
    ecrire(configClaude .. '/.claude.json', '{}')
    ecrire(configClaude .. '/settings.json', '{}')
    local cible = dossierVide('SSD échanges')
    local r = DossierCommun.choisir(cible)
    egal(1, r.echanges, 'un échange pris dans ~/.claude')
    egal('echange-a\n', Fichiers.lire(cible .. '/Claude Code/sess-a.jsonl'))
    egal('deja-range\n', Fichiers.lire(cible .. '/Claude Code/sess-c.jsonl'), 'déjà rangé : gardé')
    egal('echange-a\n', Fichiers.lire(projetMigration .. '/sess-a.jsonl'), 'la source reste')
    local tout = S.lireCommande('cd ' .. S.q(cible) .. ' && find . -type f | sort'):gsub('%s+$', '')
    egal('./Claude Code/sess-a.jsonl\n./Claude Code/sess-c.jsonl\n./Conversations/ca/conversation.json\n./Conversations/cb/conversation.json\n'
        .. './Conversations/cc/conversation.json\n./Conversations/cd/conversation.json\n./Conversations/ce/conversation.json', tout,
        'rien d’autre de ~/.claude')
    contient(DossierCommun.texteChoix(r), "1 échange de Claude Code")
    -- Depuis l'ancien dossier commun : rien n'est pris dans ~/.claude.
    local suivant = dossierVide('SSD échanges suivant')
    local r2 = DossierCommun.choisir(suivant)
    egal(0, r2.echanges)
    retirerPointeur()
    vider(configClaude)
end)

essai('Dossier « Développeur IA » : la racine d’un volume donne son dossier, créé ; le choix s’ouvre sur le SSD Photos', function()
    egal('Développeur IA', DossierCommun.NOM)
    local photos = DossierCommun.VOLUME_PHOTOS
    vrai(sous(photos, S.home), 'SSD simulé : ' .. photos)
    vider(photos .. '/Développeur IA')
    S.executer('mkdir -p ' .. S.q(photos))
    egal(true, DossierCommun.racineDeVolume(photos))
    egal(false, DossierCommun.racineDeVolume(photos .. '/Rangement'))
    egal(false, DossierCommun.racineDeVolume(DossierCommun.VOLUMES))
    egal(photos .. '/Développeur IA', DossierCommun.preparer(photos .. '/'))
    egal('directory', S.modules.LrFileUtils.exists(photos .. '/Développeur IA'), 'créé')
    egal(photos .. '/Rangement', DossierCommun.preparer(photos .. '/Rangement/'), 'un autre dossier : tel quel')
    egal(photos, DossierCommun.dossierInitial())
    DossierCommun.VOLUME_PHOTOS = S.home .. '/Volumes/Absent'
    egal(nil, DossierCommun.dossierInitial(), 'SSD débranché : le défaut de macOS')
    DossierCommun.VOLUME_PHOTOS = photos
    -- Le Gestionnaire : le choix s'ouvre sur le SSD ; Dany choisit le SSD lui-même.
    retirerPointeur()
    vider(locale)
    ecrire(locale .. '/carnet.json', '{"carnet":"volume"}')
    vider(photos .. '/Développeur IA')
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    local section = PluginInfoProvider.sectionsForTopOfDialog(f, proprietes)[3]
    local bouton, textes = nil, {}
    local function parcourir(v)
        if type(v) ~= 'table' then return end
        if v.genre and S.BOUTONS[v.genre] and v.args.title == 'Choisir…' then bouton = v end
        if v.args and type(v.args.title) == 'string' then textes[#textes + 1] = v.args.title end
        for _, enfant in ipairs(v.args or v) do parcourir(enfant) end
    end
    parcourir(section)
    contient(table.concat(textes, '\n'), '« Développeur IA »', 'le texte du réglage le dit')
    local panneau
    local runOpenPanel = S.modules.LrDialogs.runOpenPanel
    S.modules.LrDialogs.runOpenPanel = function(args) panneau = args return { photos } end
    bouton.args.action()
    S.modules.LrDialogs.runOpenPanel = runOpenPanel
    egal(photos, panneau.initialDirectory, 'ouvert sur le SSD Photos')
    contient(panneau.title, 'Développeur IA')
    egal(photos .. '/Développeur IA', Chemins.dossierCommun().chemin, 'réglé sur son dossier')
    egal('{"carnet":"volume"}', Fichiers.lire(photos .. '/Développeur IA/carnet.json'))
    vrai(not Fichiers.existe(photos .. '/carnet.json'), 'rien à la racine du SSD')
    egal(photos .. '/Développeur IA', proprietes.dossierCommun)
    retirerPointeur()
end)

essai('Gestionnaire : la copie se suit dans une progression au premier plan (modale), sinon dans la barre d’activité', function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local function choisirPar(cible)
        local f = S.modules.LrView.osFactory()
        local section = PluginInfoProvider.sectionsForTopOfDialog(f, S.modules.LrBinding.makePropertyTable())[3]
        local bouton
        local function parcourir(v)
            if type(v) ~= 'table' then return end
            if v.genre and S.BOUTONS[v.genre] and v.args.title == 'Choisir…' then bouton = v end
            for _, enfant in ipairs(v.args or v) do parcourir(enfant) end
        end
        parcourir(section)
        S.fichiersChoisis = { cible }
        bouton.args.action()
        S.fichiersChoisis = nil
    end
    retirerPointeur()
    vider(locale)
    ecrire(locale .. '/carnet.json', '{"carnet":"modale"}')
    S.barres = {}
    choisirPar(dossierVide('SSD modale'))
    egal(1, #S.barres)
    egal(true, S.barres[1].modale, 'au premier plan')
    egal(true, S.barres[1].annulable, 'annulable')
    egal(true, S.barres[1].finie)
    retirerPointeur()
    -- Sans showModalProgressDialog : la barre d'activité, annulable.
    vider(locale)
    ecrire(locale .. '/carnet.json', '{"carnet":"barre"}')
    local modale = S.modules.LrDialogs.showModalProgressDialog
    S.modules.LrDialogs.showModalProgressDialog = nil
    S.barres = {}
    choisirPar(dossierVide('SSD barre'))
    S.modules.LrDialogs.showModalProgressDialog = modale
    egal(1, #S.barres)
    egal(nil, S.barres[1].modale)
    egal(true, S.barres[1].annulable)
    egal('{"carnet":"barre"}', Fichiers.lire(S.home .. '/SSD barre/carnet.json'))
    retirerPointeur()
end)

essai('Gestionnaire : DossierCommun.lua qui ne se charge pas (module rechargé sans relancer Lightroom) : les autres sections restent', function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local garde = package.loaded.DossierCommun
    package.loaded.DossierCommun = nil
    package.preload.DossierCommun = function() error('Could not load toolkit script: DossierCommun.lua', 0) end
    local ok, sections = pcall(PluginInfoProvider.sectionsForTopOfDialog, S.modules.LrView.osFactory(), S.modules.LrBinding.makePropertyTable())
    local okD, diag = pcall(PluginInfoProvider.diagnostic)
    package.preload.DossierCommun = nil
    package.loaded.DossierCommun = garde
    vrai(ok, tostring(sections))
    egal(3, #sections)
    egal('Liaison avec Claude', sections[1].title)
    egal('Fenêtre Claude', sections[2].title)
    egal('Dossier commun', sections[3].title)
    local textes = {}
    local function parcourir(v)
        if type(v) ~= 'table' then return end
        if v.args and type(v.args.title) == 'string' then textes[#textes + 1] = v.args.title end
        for _, enfant in ipairs(v.args or v) do parcourir(enfant) end
    end
    parcourir(sections[3])
    contient(table.concat(textes, '\n'), 'relancez Lightroom')
    vrai(not table.concat(textes, '\n'):find('Choisir…', 1, true), 'pas de bouton sans le module')
    vrai(okD, tostring(diag))
    contient(diag, '\nDossier commun : réglage indisponible')
end)

-- Gestionnaire de modules externes -----------------------------------------------------------

essai('Gestionnaire : section Dossier commun (chemin, Choisir…, Revenir au dossier de ce Mac) ; diagnostic', function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local proprietes = S.modules.LrBinding.makePropertyTable()
    retirerPointeur()
    local sections = PluginInfoProvider.sectionsForTopOfDialog(f, proprietes)
    local section = sections[3]
    egal('Dossier commun', section.title)
    contient(proprietes.dossierCommun, 'aucun')
    local boutons = {}
    local function parcourir(v)
        if type(v) ~= 'table' then
            return
        end
        if v.genre and S.BOUTONS[v.genre] then
            boutons[v.args.title] = v
        end
        for _, enfant in ipairs(v.args or v) do
            parcourir(enfant)
        end
    end
    parcourir(section)
    vrai(boutons['Choisir…'], 'bouton Choisir…')
    vrai(boutons['Revenir au dossier de ce Mac'], 'bouton Revenir')
    -- Choisir… ouvre un choix de dossier (création permise) ; annulé, rien ne change.
    S.fichiersChoisis = nil
    local panneau
    local runOpenPanel = S.modules.LrDialogs.runOpenPanel
    S.modules.LrDialogs.runOpenPanel = function(args) panneau = args return nil end
    boutons['Choisir…'].args.action()
    S.modules.LrDialogs.runOpenPanel = runOpenPanel
    vrai(panneau and panneau.canChooseDirectories == true and panneau.canChooseFiles == false and panneau.canCreateDirectories == true,
        'choix de dossiers, création permise')
    vrai(not Fichiers.existe(Chemins.pointeur()))
    -- Choisi : copié, réglé, l'état suit.
    vider(locale)
    ecrire(locale .. '/carnet.json', '{"carnet":"gestionnaire"}')
    local cible = S.home .. '/SSD gestionnaire'
    vider(cible)
    S.executer('mkdir -p ' .. S.q(cible))
    S.fichiersChoisis = { cible }
    local messages = #S.messages
    boutons['Choisir…'].args.action()
    S.fichiersChoisis = nil
    egal('{"carnet":"gestionnaire"}', Fichiers.lire(cible .. '/carnet.json'))
    egal(cible, proprietes.dossierCommun)
    egal(messages + 1, #S.messages)
    egal('Dossier commun réglé', S.messages[#S.messages][1])
    vrai(PluginInfoProvider.diagnostic():find('\nDossier commun : ' .. cible, 1, true), 'diagnostic')
    -- Une fenêtre ouverte : le changement attend qu'elle soit fermée.
    local Fenetre = require 'Fenetre'
    Fenetre.ouverte = true
    boutons['Revenir au dossier de ce Mac'].args.action()
    Fenetre.ouverte = false
    contient(S.messages[#S.messages][2], "Fermez d'abord la fenêtre Claude")
    vrai(Fichiers.existe(Chemins.pointeur()), 'pointeur gardé')
    -- Revenir : dit que rien n'est copié.
    boutons['Revenir au dossier de ce Mac'].args.action()
    for i = #S.taches, 1, -1 do
        local t = table.remove(S.taches, i)
        t()
    end
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur retiré')
    contient(S.messages[#S.messages][2], "Rien n'a été copié")
    contient(proprietes.dossierCommun, 'aucun')
    vrai(PluginInfoProvider.diagnostic():find('\nDossier commun : aucun', 1, true), 'diagnostic sans dossier commun')
end)

-- relais.sh : l'échange de la session Claude Code ----------------------------------------------

essai('Encodage du dossier de projet : comme ~/.claude/projects (un caractère accentué, un tiret)', function()
    egal('-Users-danymenard-Library-Application-Support-Developpeur-Atelier', encoder('/Users/danymenard/Library/Application Support/Developpeur/Atelier'))
    egal('-Users-danymenard-Library-Application-Support-Le-D-veloppeur-Atelier', encoder('/Users/danymenard/Library/Application Support/Le Développeur/Atelier'))
end)

local faux = dossierTests .. '/faux-claude.sh'
local prefs = Chemins.prefs()
prefs.cheminClaude = faux
prefs.cheminConnecteur = '/bin/echo'
prefs.nouvelleParPhoto = false

local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out '
    .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))

Fichiers.creerDossier(Chemins.atelier())
local physique = S.lireCommande('cd ' .. S.q(Chemins.atelier()) .. ' && pwd -P'):gsub('%s+$', '')
local projet = configClaude .. '/projects/' .. encoder(physique)
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' CLAUDE_CONFIG_DIR=' .. S.q(configClaude) .. ' FAUX_PROJET=' .. S.q(projet) .. ' '
local commandes = {}
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commandes[#commandes + 1] = commande
        commande = env .. commande
    end
    return executerOriginal(commande)
end

local Moteur = require 'Moteur'

local function attendre(condition, secondes)
    for _ = 1, (secondes or 10) * 10 do
        Moteur.tic()
        if condition() then
            return true
        end
        S.executer('sleep 0.1')
    end
    return false
end

local function arguments()
    return Fichiers.lire(Chemins.atelier() .. '/arguments.txt') or ''
end

local function lignes(chemin)
    local n = 0
    for _ in (Fichiers.lire(chemin) or ''):gmatch('[^\n]+') do
        n = n + 1
    end
    return n
end

-- Ferme Claude Code et attend la fin du relais (copie de retour comprise).
local function fermer()
    local s = Moteur.session
    if s then
        s:arreter()
        vrai(attendre(function() return Fichiers.existe(s.dossier .. '/fin.code') end, 10), 'relais terminé')
        return s.dossier
    end
end

essai('Relais avec dossier commun : l’échange repris est copié du dossier commun avant --resume, puis rangé dedans après la fin', function()
    vider(locale)
    vider(configClaude)
    -- Ce qui ne doit jamais partir : fichiers de connexion, réglages, une autre session.
    ecrire(configClaude .. '/.credentials.json', '{"secret":1}')
    ecrire(configClaude .. '/.claude.json', '{"oauth":1}')
    ecrire(configClaude .. '/settings.json', '{}')
    ecrire(projet .. '/autre-session.jsonl', 'autre\n')
    local ssdRelais = S.home .. '/Volumes/Photos/Développeur relais'
    vider(ssdRelais)
    S.executer('mkdir -p ' .. S.q(ssdRelais))
    poserPointeur(ssdRelais)
    -- L'échange laissé par l'autre Mac.
    ecrire(ssdRelais .. '/Claude Code/session-essai.jsonl', 'ligne-de-l-autre-mac\n')
    Moteur.charge = false
    Moteur.charger()
    Moteur.nouvelle()
    Moteur.courante.sessionID = 'session-essai'
    local ok, raison = Moteur.envoyer('Bonjour', { modele = 'haiku' })
    vrai(ok, raison)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    contient(commandes[#commandes], 'DEVELOPPEUR_DONNEES=' .. S.q(ssdRelais), 'racine passée au relais')
    local a = arguments()
    contient(a, '--resume\nsession-essai', 'session reprise')
    contient(a, 'echange-repris=ligne-de-l-autre-mac', 'échange copié avant le lancement')
    local dossier = fermer()
    -- Après la fin : l'échange (la ligne reprise et le message) rangé dans le dossier commun.
    local range = ssdRelais .. '/Claude Code/session-essai.jsonl'
    egal(2, lignes(range), Fichiers.lire(range))
    contient(Fichiers.lire(range), 'Bonjour')
    contient(Fichiers.lire(dossier .. '/dossier-commun.log'), 'copié : ')
    -- Seulement ce .jsonl : rien d'autre de ~/.claude n'est copié.
    egal('session-essai.jsonl', S.lireCommande('ls -A ' .. S.q(ssdRelais .. '/Claude Code')):gsub('%s+$', ''))
    -- Sur le SSD, à part les données de la fenêtre (Conversations/, consommation.json) : ce seul échange.
    egal('./Claude Code/session-essai.jsonl', S.lireCommande('cd ' .. S.q(ssdRelais) .. ' && find . -type f | grep -v "^./Conversations/"'
        .. ' | grep -v "^./consommation.json$" | sort'):gsub('%s+$', ''), 'rien d’autre de ~/.claude sur le SSD')
end)

essai('Relais avec dossier commun : une session neuve (sans --resume) est rangée dans le dossier commun sous l’id que Claude Code donne', function()
    local ssdRelais = S.home .. '/Volumes/Photos/Développeur relais'
    vider(ssdRelais .. '/Claude Code')
    vider(configClaude)
    Moteur.nouvelle()
    Moteur.courante.sessionID = nil
    local ok, raison = Moteur.envoyer('Une nouvelle', { modele = 'haiku' })
    vrai(ok, raison)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    vrai(not arguments():find('--resume', 1, true), 'nouvelle session')
    vrai(not arguments():find('echange-', 1, true))
    local dossier = fermer()
    egal(1, lignes(ssdRelais .. '/Claude Code/session-essai.jsonl'), 'rangée sous session_id')
    retirerPointeur()
end)

essai('Relais sans dossier commun : rien ne change (ni DEVELOPPEUR_DONNEES ni copie)', function()
    retirerPointeur()
    vider(configClaude)
    ecrire(projet .. '/session-essai.jsonl', 'local\n')
    Moteur.nouvelle()
    Moteur.courante.sessionID = 'session-essai'
    local ok, raison = Moteur.envoyer('Sans dossier commun', { modele = 'haiku' })
    vrai(ok, raison)
    vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
    vrai(not commandes[#commandes]:find('DEVELOPPEUR_DONNEES', 1, true), commandes[#commandes])
    local dossier = fermer()
    vrai(not Fichiers.existe(locale .. '/Claude Code'), 'aucune copie dans la racine locale')
    vrai(not Fichiers.existe(dossier .. '/dossier-commun.log'), 'aucune copie')
end)

-- relais.sh lancé seul (sans le moteur) : la règle du début, la fin anormale, le signal, le dossier
-- commun disparu, un id dangereux, un dossier de travail accentué. Tout sous S.home ; le ~/.claude
-- simulé (CLAUDE_CONFIG_DIR) a de faux fichiers de connexion, qui ne doivent jamais partir.

local numeroRelais = 0

-- Lance relais.sh avec faux-claude.sh, lui envoie `o.messages`, puis l'arrête (« arreter », ou
-- `o.signal` envoyé au relais, ou `o.avantFin()` d'abord) et attend fin.code. Rend le dossier de la
-- session.
local function lancerRelais(o)
    numeroRelais = numeroRelais + 1
    local dossier = S.home .. '/Relais seul/' .. numeroRelais
    vider(dossier)
    S.executer('mkdir -p ' .. S.q(dossier) .. ' ' .. S.q(o.travail))
    local commande = 'cd ' .. S.q(dossier) .. ' && ' .. (o.env or '') .. ' CLAUDE_CONFIG_DIR=' .. S.q(configClaude)
        .. ' FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' FAUX_PROJET=' .. S.q(o.projet)
        .. (o.donnees and (' DEVELOPPEUR_DONNEES=' .. S.q(o.donnees)) or '')
        .. ' /bin/sh ' .. S.q(S.plugin .. '/relais.sh') .. ' ' .. S.q(dossier) .. ' ' .. S.q(faux) .. " haiku '' "
        .. S.q(o.reprise or '') .. ' ' .. S.q(o.travail) .. ' /dev/null /dev/null 0 > /dev/null 2>&1 &'
    S.executer(commande)
    local function attendreQue(condition, secondes)
        for _ = 1, (secondes or 10) * 10 do
            if condition() then return true end
            S.executer('sleep 0.1')
        end
        return false
    end
    vrai(attendreQue(function() return Fichiers.existe(dossier .. '/claude.pid') end), 'relais lancé')
    for _, m in ipairs(o.messages or {}) do
        Fichiers.ajouterLigne(dossier .. '/entree.jsonl', Json.encode({ type = 'user', message = { content = m } }))
    end
    if not o.panne then
        vrai(attendreQue(function()
            local _, n = (Fichiers.lire(dossier .. '/sortie.jsonl') or ''):gsub('"type":"result"', '')
            return n >= #(o.messages or {})
        end), 'réponses reçues')
    end
    if o.avantFin then
        o.avantFin(dossier)
    end
    if o.signal then
        S.executer('kill -' .. o.signal .. ' "$(cat ' .. S.q(dossier .. '/relais.pid') .. ')"')
    elseif not o.panne then
        ecrire(dossier .. '/arreter', '')
    end
    vrai(attendreQue(function() return Fichiers.existe(dossier .. '/fin.code') end, 12), 'fin.code écrit')
    return dossier
end

-- Le ~/.claude simulé, avec ce qui ne doit jamais partir vers le SSD.
local function configAvecSecrets(projetEssai)
    vider(configClaude)
    ecrire(configClaude .. '/.credentials.json', '{"secret":1}')
    ecrire(configClaude .. '/.claude.json', '{"oauth":1}')
    ecrire(configClaude .. '/settings.json', '{}')
    ecrire(projetEssai .. '/autre-session.jsonl', 'autre\n')
end

local travailSeul = S.home .. '/Atelier seul'
local function projetDe(travail)
    S.executer('mkdir -p ' .. S.q(travail))
    return configClaude .. '/projects/' .. encoder(S.lireCommande('cd ' .. S.q(travail) .. ' && pwd -P'):gsub('%s+$', ''))
end

local ssdSeul = S.home .. '/Volumes/Photos/Développeur relais seul'

local function ssdVide()
    vider(ssdSeul)
    S.executer('mkdir -p ' .. S.q(ssdSeul))
end

-- Rien sur le SSD simulé que ces fichiers (chemins relatifs, triés).
local function seulementSurLeSsd(attendus)
    local tout = S.lireCommande('cd ' .. S.q(ssdSeul) .. ' && find . -type f | sort'):gsub('%s+$', '')
    egal(table.concat(attendus, '\n'), tout, 'fichiers du SSD')
end

essai('Relais seul : un échange local qui a des tours de plus que celui du SSD (même plus ancien) n’est jamais remplacé', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    ecrire(projetEssai .. '/session-essai.jsonl', 'l1\nl2-local\n')
    ecrire(ssdSeul .. '/Claude Code/session-essai.jsonl', 'l1\n')
    -- Le SSD daté après l'échange local : l'ancienne règle « plus récent » l'aurait copié.
    S.executer('touch -t 203001010000 ' .. S.q(ssdSeul .. '/Claude Code/session-essai.jsonl'))
    local dossier = lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, reprise = 'session-essai',
        messages = { 'Bonjour' } })
    local local_ = Fichiers.lire(projetEssai .. '/session-essai.jsonl')
    vrai(local_:sub(1, #'l1\nl2-local\n') == 'l1\nl2-local\n', 'échange local intact : ' .. local_)
    contient(Fichiers.lire(dossier .. '/dossier-commun.log'), 'gardé : ')
    -- Après la fin : le SSD (début de l'échange local) est remplacé, sans copie à côté.
    egal(local_, Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl'))
    seulementSurLeSsd({ './Claude Code/session-essai.jsonl' })
    vrai(not Fichiers.existe(dossier .. '/dossier-commun.erreur'))
end)

essai('Relais seul : l’autre Mac a ajouté des tours (l’échange local en est le début) : le SSD est repris avant --resume', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    ecrire(projetEssai .. '/session-essai.jsonl', 'l1\n')
    ecrire(ssdSeul .. '/Claude Code/session-essai.jsonl', 'l1\nl2-autre-mac\n')
    S.executer('touch -t 202001010000 ' .. S.q(ssdSeul .. '/Claude Code/session-essai.jsonl'))
    lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, reprise = 'session-essai', messages = { 'Suite' } })
    contient(Fichiers.lire(projetEssai .. '/session-essai.jsonl'), 'l2-autre-mac', 'repris du SSD')
    contient(Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl'), 'Suite')
    seulementSurLeSsd({ './Claude Code/session-essai.jsonl' })
end)

essai('Relais seul : deux échanges qui divergent : le local est gardé, celui du SSD mis à côté (.avant-<date>) avant d’être remplacé', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    ecrire(projetEssai .. '/session-essai.jsonl', 'l1\nA-sur-ce-mac\n')
    ecrire(ssdSeul .. '/Claude Code/session-essai.jsonl', 'l1\nB-sur-l-autre\n')
    S.executer('touch -t 203001010000 ' .. S.q(ssdSeul .. '/Claude Code/session-essai.jsonl'))
    lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, reprise = 'session-essai', messages = { 'Encore' } })
    contient(Fichiers.lire(projetEssai .. '/session-essai.jsonl'), 'A-sur-ce-mac', 'échange local gardé')
    contient(Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl'), 'A-sur-ce-mac')
    local gardes = S.lireCommande('ls ' .. S.q(ssdSeul .. '/Claude Code') .. ' | grep "session-essai.jsonl.avant-" || true'):gsub('%s+$', '')
    vrai(gardes ~= '' and not gardes:find('\n'), 'une copie à côté : ' .. gardes)
    egal('l1\nB-sur-l-autre\n', Fichiers.lire(ssdSeul .. '/Claude Code/' .. gardes), 'les tours de l’autre Mac gardés')
end)

essai('Relais seul : Claude Code sorti en erreur (code 3) : l’échange est rangé quand même', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    vider(projetEssai .. '/session-essai.jsonl')
    local dossier = lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, messages = { 'ARRETE-TOI' }, panne = true })
    egal('3', Texte.nettoyer(Fichiers.lire(dossier .. '/fin.code')))
    contient(Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl') or '', 'ARRETE-TOI')
    seulementSurLeSsd({ './Claude Code/session-essai.jsonl' })
end)

essai('Relais seul : arrêté par un signal (TERM, HUP) : Claude Code fermé, l’échange rangé, fin.code écrit', function()
    for _, signal in ipairs({ 'TERM', 'HUP' }) do
        local projetEssai = projetDe(travailSeul)
        configAvecSecrets(projetEssai)
        ssdVide()
        vider(projetEssai .. '/session-essai.jsonl')
        local dossier = lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, messages = { 'Signal ' .. signal },
            signal = signal })
        contient(Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl') or '', 'Signal ' .. signal, signal)
        vrai(Texte.nettoyer(Fichiers.lire(dossier .. '/fin.code')) ~= '', signal)
        local pid = Texte.nettoyer(Fichiers.lire(dossier .. '/claude.pid'))
        egal('', S.lireCommande('kill -0 ' .. pid .. ' 2>/dev/null && echo vivant || true'):gsub('%s+$', ''), 'Claude Code fermé')
        seulementSurLeSsd({ './Claude Code/session-essai.jsonl' })
    end
end)

essai('Relais seul : le dossier commun disparu avant la fin : rien n’est copié nulle part, et c’est écrit (dossier-commun.erreur)', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    vider(projetEssai .. '/session-essai.jsonl')
    local dossier = lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, messages = { 'Éjecté' },
        avantFin = function() vider(ssdSeul) end })
    vrai(not Fichiers.existe(ssdSeul), 'le dossier commun n’est pas recréé')
    vrai(not Fichiers.existe(locale .. '/Claude Code'), 'rien dans la racine locale')
    vrai(not Fichiers.existe(dossier .. '/Claude Code'), 'rien dans le dossier de la session')
    contient(Fichiers.lire(dossier .. '/dossier-commun.erreur') or '', 'introuvable')
    contient(Fichiers.lire(projetEssai .. '/session-essai.jsonl'), 'Éjecté', 'l’échange local reste')
end)

essai('Relais seul : un id de session dangereux (« ../x ») : rien copié avant --resume, rien hors de « Claude Code/ »', function()
    local projetEssai = projetDe(travailSeul)
    configAvecSecrets(projetEssai)
    ssdVide()
    vider(projetEssai .. '/session-essai.jsonl')
    -- « Claude Code/../x.jsonl » serait le x.jsonl du SSD, copié vers « <projet>/../x.jsonl ».
    ecrire(ssdSeul .. '/x.jsonl', 'piege\n')
    S.executer('mkdir -p ' .. S.q(ssdSeul .. '/Claude Code'))
    lancerRelais({ travail = travailSeul, projet = projetEssai, donnees = ssdSeul, reprise = '../x', messages = { 'Bonjour' } })
    vrai(not Fichiers.existe(configClaude .. '/projects/x.jsonl'), 'rien copié hors du dossier du projet')
    vrai(not Fichiers.existe(projetEssai .. '/../x.jsonl'))
    seulementSurLeSsd({ './Claude Code/session-essai.jsonl', './x.jsonl' })
end)

essai('Relais seul : dossier de travail accentué, locale C : un caractère accentué donne un seul « - » (LC_ALL de relais.sh)', function()
    local travailAccent = S.home .. '/Le Développeur/Atelier'
    local projetEssai = projetDe(travailAccent)
    egal('-Le-D-veloppeur-Atelier', projetEssai:sub(-#'-Le-D-veloppeur-Atelier'), projetEssai)
    configAvecSecrets(projetEssai)
    ssdVide()
    ecrire(ssdSeul .. '/Claude Code/session-essai.jsonl', 'ligne-du-ssd\n')
    -- relais.sh --projet, tel que le réglage du dossier commun l'appelle.
    egal(projetEssai, S.lireCommande('LC_ALL=C LANG=C CLAUDE_CONFIG_DIR=' .. S.q(configClaude) .. ' /bin/sh '
        .. S.q(S.plugin .. '/relais.sh') .. ' --projet ' .. S.q(travailAccent)):gsub('%s+$', ''))
    lancerRelais({ env = 'LC_ALL=C LANG=C', travail = travailAccent, projet = projetEssai, donnees = ssdSeul, reprise = 'session-essai',
        messages = { 'Accents' } })
    contient(Fichiers.lire(travailAccent .. '/arguments.txt'), 'echange-repris=ligne-du-ssd', 'copié dans le bon dossier de projet')
    contient(Fichiers.lire(ssdSeul .. '/Claude Code/session-essai.jsonl'), 'Accents')
    seulementSurLeSsd({ './Claude Code/session-essai.jsonl' })
end)

essai('Échange non copié (dossier-commun.erreur) : dit au Journal et dans une note de la conversation', function()
    local Session = require 'Session'
    local s = Session.nouvelle({ idConversation = 'note-commun', claude = '/bin/echo', connecteur = '/bin/echo', modele = 'haiku',
        travail = Chemins.atelier(), consignes = '' })
    s.dossier = S.home .. '/Relais seul/note'
    vider(s.dossier)
    ecrire(s.dossier .. '/fin.code', '0\n')
    ecrire(s.dossier .. '/dossier-commun.erreur', 'non copié : le dossier commun /Volumes/Photos/Développeur IA est introuvable\n')
    local lignes, fini, code, erreurs, erreurCommun = s:lire()
    egal(true, fini)
    egal(0, code)
    contient(erreurCommun, 'introuvable')
    contient(Fichiers.lire(Chemins.journal()) or '', 'Dossier commun : échange de Claude Code non copié')
    s.conversation = { id = 'note-commun', elements = {}, rapide = true }
    local avant = #s.conversation.elements
    Moteur.processusFini(s, code, erreurs, erreurCommun)
    egal(avant + 1, #s.conversation.elements)
    contient(s.conversation.elements[#s.conversation.elements].texte, "n'a pas été copié dans le dossier commun")
end)

-- uninstall.sh --tout -----------------------------------------------------------------------------

essai('uninstall.sh --tout : retire le pointeur, ne touche jamais le dossier commun, et le dit', function()
    local racine = S.lireCommande('cd ' .. S.q(dossierTests .. '/../../..') .. ' && pwd -P'):gsub('%s+$', '')
    local ssdU = S.home .. '/Volumes/Photos/Développeur désinstallé'
    vider(ssdU)
    donneesDuMac(ssdU, 'ssd')
    poserPointeur(ssdU)
    local avant = S.lireCommande('cd ' .. S.q(ssdU) .. ' && find . -type f | sort')
    -- HOME simulé : uninstall.sh ne vise que des chemins sous HOME (garde-fou en tête de ce fichier).
    -- Une copie du script, seule dans un dossier du HOME simulé : aucun exécutable mcp-developpeur à
    -- côté d'elle, rien n'est retiré des inscriptions de Claude (le vrai Claude Desktop jamais touché).
    local copie = S.home .. '/Script/uninstall.sh'
    S.executer('mkdir -p ' .. S.q(S.home .. '/Script') .. ' && cp ' .. S.q(racine .. '/uninstall.sh') .. ' ' .. S.q(copie))
    local sortie = S.lireCommande('HOME=' .. S.q(S.home) .. ' PATH=/usr/bin:/bin:/usr/sbin:/sbin bash ' .. S.q(copie) .. ' --tout 2>&1')
    contient(sortie, 'Aucun exécutable trouvé', 'aucune inscription touchée')
    vrai(not Fichiers.existe(Chemins.pointeur()), 'pointeur retiré : ' .. sortie)
    egal(avant, S.lireCommande('cd ' .. S.q(ssdU) .. ' && find . -type f | sort'), 'dossier commun intact')
    contient(sortie, 'Retiré : le réglage du dossier commun')
    contient(sortie, 'Gardé, jamais touché : le dossier commun ' .. ssdU)
end)

-- Fin ------------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
