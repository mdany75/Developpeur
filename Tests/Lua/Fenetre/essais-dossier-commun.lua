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

-- Le ~/.claude simulé (CLAUDE_CONFIG_DIR), jamais le vrai.
local configClaude = S.home .. '/.claude'
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
    vrai(not Fichiers.existe(ssdRelais .. '/.claude.json'))
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
