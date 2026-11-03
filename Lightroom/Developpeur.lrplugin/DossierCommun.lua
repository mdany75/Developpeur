-- DossierCommun.lua : le réglage « Dossier commun » du Gestionnaire de modules externes (demandé
-- par Dany le 3 novembre 2026 : deux Mac, le SSD « Photos » qui passe de l'un à l'autre, jamais
-- les deux en même temps ; « que je travaille sur l'un ou l'autre, tout est pareil, je reprends le
-- travail où je l'avais arrêté »).
--
-- Seul ce fichier écrit le pointeur local dossier-commun.json (Chemins.pointeur) ; Chemins.lua et
-- le serveur le lisent à chaque accès. Le dossier commun s'appelle « Développeur IA »
-- (DossierCommun.NOM) : choisir la racine d'un volume (/Volumes/Photos) règle
-- /Volumes/Photos/Développeur IA, créé au besoin ; le choix s'ouvre sur /Volumes/Photos s'il est
-- branché (DossierCommun.dossierInitial). Choisir un dossier :
--   - un seul changement à la fois (DossierCommun.enCours) ; pendant le changement, la liaison
--     refuse toute commande sauf ping (Chemins.changement), le Suivi est éteint, et une commande de
--     la liaison déjà en cours est attendue : rien ne s'écrit dans l'ancienne racine pendant la
--     copie ;
--   - l'ancien dossier commun réglé mais introuvable : refus (jamais la racine locale copiée à sa
--     place), sauf vers un dossier qui a déjà des données (le deuxième Mac) ;
--   - s'il n'a pas encore de données de Développeur (Chemins.estDonnee), celles de la racine des
--     données actuelle (ce Mac, ou l'ancien dossier commun) y sont COPIÉES, avec leur progression,
--     d'abord dans un dossier caché « .copie-en-cours-<date> » ; venant de ce Mac, les échanges de
--     Claude Code des conversations (~/.claude/projects/<Atelier encodé>/<sessionID>.jsonl, rien
--     d'autre de ~/.claude) vont dans « Claude Code/ » ; un fichier changé pendant la copie est
--     recopié ; puis tout est rangé, sous la marque « .rangement-en-cours.json » (un rangement
--     interrompu se termine au prochain choix, jamais pris pour des données complètes) ;
--   - s'il en a déjà (le deuxième Mac), elles sont prises telles quelles ;
--   - puis le pointeur est écrit (avant la mise de côté : une interruption ne laisse jamais ce Mac
--     sans pointeur et sans données) ;
--   - enfin les données de ce Mac (racine locale) sont déplacées dans « Avant le dossier commun
--     <AAAA-MM-JJ HH-MM> » de la racine locale : rien n'est effacé ; une mise de côté manquée laisse
--     le réglage fait (les données locales ne sont plus lues) et le dit.
-- « Revenir au dossier de ce Mac » retire le pointeur, sans rien copier.
-- La copie rend la main à Lightroom tous les DossierCommun.PAS_RENDRE fichiers (Photos.rendreLaMain :
-- la barre se redessine, son annulation se lit). Les registres en mémoire (carnet, notes,
-- consommation, relevé, liste des conversations) se relisent d'eux-mêmes quand la racine change.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

require 'Compat'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'

local DossierCommun = {}

DossierCommun.FORMAT = 1
-- Le nom du dossier commun (décision de Dany du 3 novembre 2026), créé à la racine d'un volume.
DossierCommun.NOM = 'Développeur IA'
-- Où sont les volumes, et le SSD de Dany (injectables : les essais ne lisent jamais les vrais).
DossierCommun.VOLUMES = '/Volumes'
DossierCommun.VOLUME_PHOTOS = '/Volumes/Photos'
-- Secondes au plus pour laisser finir la tâche du Suivi, puis une commande de la liaison.
DossierCommun.ATTENTE_SUIVI = 30
DossierCommun.ATTENTE_LIAISON = 30
-- Tous les combien de fichiers la copie rend la main à Lightroom.
DossierCommun.PAS_RENDRE = 10
-- Passes de recopie des fichiers changés pendant la copie, au plus.
DossierCommun.PASSES_RECOPIE = 3
-- La marque d'un rangement en cours, dans le dossier choisi.
DossierCommun.MARQUE_RANGEMENT = '.rangement-en-cours.json'

DossierCommun.EN_COURS = "Un changement de dossier commun est déjà en cours : attendez qu'il soit fini."
-- Vrai du début à la fin d'un choix ou d'un retour (remis à faux même après une erreur).
DossierCommun.enCours = false

local function echouer(message)
    error(message, 0)
end

-- Rend la main à Lightroom (la seule copie : Photos.rendreLaMain), tous les PAS_RENDRE appels.
local pas = 0
local function rendreLaMain()
    pas = pas + 1
    if pas % math.max(1, DossierCommun.PAS_RENDRE) ~= 0 then
        return
    end
    local ok, Photos = pcall(require, 'Photos')
    if ok and type(Photos) == 'table' and Photos.rendreLaMain then
        Photos.rendreLaMain()
    end
end

-- Les entrées d'un dossier, fichiers cachés compris (sauf .DS_Store), triées.
local function toutesLesEntrees(dossier)
    local noms = {}
    for chemin in LrFileUtils.directoryEntries(dossier) do
        local nom = LrPathUtils.leafName(chemin)
        if nom ~= '.DS_Store' then
            noms[#noms + 1] = nom
        end
    end
    table.sort(noms)
    return noms
end

-- Les données de Développeur (noms de Chemins.NOMS_DONNEES et copies illisibles) d'un dossier.
function DossierCommun.donneesDe(dossier)
    local noms = {}
    for _, nom in ipairs(Fichiers.entrees(dossier)) do
        if Chemins.estDonnee(nom) then
            noms[#noms + 1] = nom
        end
    end
    return noms
end

-- Vrai si le dossier a déjà des données de Développeur (le deuxième Mac).
function DossierCommun.aDesDonnees(dossier)
    return #DossierCommun.donneesDe(dossier) > 0
end

-- Vrai si un rangement s'est arrêté au milieu dans ce dossier.
function DossierCommun.rangementInterrompu(dossier)
    return LrFileUtils.exists(LrPathUtils.child(dossier, DossierCommun.MARQUE_RANGEMENT)) == 'file'
end

-- Le nombre de fichiers d'un fichier ou d'un dossier (pour la progression).
function DossierCommun.compter(chemin)
    local genre = LrFileUtils.exists(chemin)
    if genre == 'file' then
        return 1
    elseif genre ~= 'directory' then
        return 0
    end
    local n = 0
    for _, nom in ipairs(toutesLesEntrees(chemin)) do
        n = n + DossierCommun.compter(LrPathUtils.child(chemin, nom))
    end
    return n
end

local function taille(chemin)
    local a = LrFileUtils.fileAttributes(chemin)
    return a and a.fileSize
end

-- Copie récursive (LrFileUtils.copy ne copie qu'un fichier) : `source` (fichier ou dossier) vers
-- `destination`, qui ne doit pas exister (jamais rien d'écrasé). Chaque fichier est vérifié (présent,
-- même taille). `avancer()` est appelé après chaque fichier ; il rend faux pour interrompre. La main
-- est rendue à Lightroom tous les PAS_RENDRE fichiers. Rend le nombre de fichiers copiés ; une
-- erreur dit lequel n'a pas pu l'être. Rien n'est jamais effacé.
function DossierCommun.copierArbre(source, destination, avancer)
    local genre = LrFileUtils.exists(source)
    if not genre then
        echouer("Copie impossible : " .. source .. " est introuvable.")
    end
    if LrFileUtils.exists(destination) then
        echouer("Copie refusée : " .. destination .. " existe déjà (rien n'est écrasé).")
    end
    if genre == 'directory' then
        LrFileUtils.createAllDirectories(destination)
        if LrFileUtils.exists(destination) ~= 'directory' then
            echouer("Copie impossible : le dossier " .. destination .. " n'a pas pu être créé.")
        end
        local n = 0
        for _, nom in ipairs(toutesLesEntrees(source)) do
            n = n + DossierCommun.copierArbre(LrPathUtils.child(source, nom), LrPathUtils.child(destination, nom), avancer)
        end
        return n
    end
    LrFileUtils.copy(source, destination)
    if LrFileUtils.exists(destination) ~= 'file' or taille(destination) ~= taille(source) then
        echouer("Copie impossible : " .. source .. " vers " .. destination .. ".")
    end
    rendreLaMain()
    if avancer and avancer() == false then
        echouer("Copie interrompue : le dossier commun n'est pas réglé.")
    end
    return 1
end

-- L'état des fichiers de `noms` sous `racine` : { [chemin relatif] = "taille:date" }.
local function releve(racine, noms)
    local etat = {}
    local function parcourir(chemin, relatif)
        local genre = LrFileUtils.exists(chemin)
        if genre == 'file' then
            local a = LrFileUtils.fileAttributes(chemin) or {}
            etat[relatif] = tostring(a.fileSize) .. ':' .. tostring(a.fileModificationDate)
            rendreLaMain()
        elseif genre == 'directory' then
            for _, nom in ipairs(toutesLesEntrees(chemin)) do
                parcourir(LrPathUtils.child(chemin, nom), relatif .. '/' .. nom)
            end
        end
    end
    for _, nom in ipairs(noms) do
        parcourir(LrPathUtils.child(racine, nom), nom)
    end
    return etat
end

-- Les chemins relatifs changés ou ajoutés de `avant` à `apres`, triés.
local function changes(avant, apres)
    local liste = {}
    for relatif, etat in pairs(apres) do
        if avant[relatif] ~= etat then
            liste[#liste + 1] = relatif
        end
    end
    table.sort(liste)
    return liste
end

-- Déplace `source` vers `destination` (jamais par-dessus un fichier qui existe) et le vérifie.
local function deplacer(source, destination)
    if LrFileUtils.exists(destination) then
        echouer("Déplacement refusé : " .. destination .. " existe déjà.")
    end
    LrFileUtils.move(source, destination)
    if LrFileUtils.exists(source) or not LrFileUtils.exists(destination) then
        echouer("Déplacement impossible : " .. source .. " vers " .. destination .. ".")
    end
end

-- Un nom libre : `base`, sinon « base 2 », « base 3 »…
local function nomLibre(base)
    local chemin, n = base, 1
    while LrFileUtils.exists(chemin) do
        n = n + 1
        chemin = base .. ' ' .. n
    end
    return chemin
end

-- Choix du dossier ------------------------------------------------------------------------------

-- Vrai si `dossier` est la racine d'un volume (/Volumes/<nom>).
function DossierCommun.racineDeVolume(dossier)
    local volumes = DossierCommun.VOLUMES
    if type(dossier) ~= 'string' or dossier:sub(1, #volumes + 1) ~= volumes .. '/' then
        return false
    end
    local reste = dossier:sub(#volumes + 2)
    return reste ~= '' and not reste:find('/', 1, true)
end

-- Le dossier à régler pour un choix : sans barre finale ; la racine d'un volume (Dany choisit
-- /Volumes/Photos) donne son dossier « Développeur IA », créé s'il manque.
function DossierCommun.preparer(dossier)
    if type(dossier) ~= 'string' then
        return dossier
    end
    if #dossier > 1 then
        dossier = dossier:gsub('/+$', '')
    end
    if DossierCommun.racineDeVolume(dossier) and LrFileUtils.exists(dossier) == 'directory' then
        local sien = LrPathUtils.child(dossier, DossierCommun.NOM)
        if not LrFileUtils.exists(sien) then
            LrFileUtils.createAllDirectories(sien)
        end
        return sien
    end
    return dossier
end

-- Où s'ouvre le choix du dossier : le SSD Photos s'il est branché, sinon nil (le défaut de macOS).
function DossierCommun.dossierInitial()
    if LrFileUtils.exists(DossierCommun.VOLUME_PHOTOS) == 'directory' then
        return DossierCommun.VOLUME_PHOTOS
    end
    return nil
end

-- Le refus d'un dossier choisi (texte), nil s'il convient.
function DossierCommun.refus(dossier)
    if type(dossier) ~= 'string' or dossier:sub(1, 1) ~= '/' then
        return "Choisissez un dossier (chemin complet)."
    end
    if LrFileUtils.exists(dossier) ~= 'directory' then
        return "Le dossier " .. dossier .. " est introuvable."
    end
    local locale = Chemins.locale()
    if dossier == locale or dossier:sub(1, #locale + 1) == locale .. '/' or locale:sub(1, #dossier + 1) == dossier .. '/' then
        return "Choisissez un dossier hors de " .. locale .. " (le dossier de ce Mac), par exemple sur le SSD Photos."
    end
    local commun = Chemins.dossierCommun()
    if commun.regle and commun.chemin == dossier then
        return "Ce dossier est déjà le dossier commun."
    end
    -- L'ancien dossier commun introuvable : ses données ne peuvent pas être copiées, et celles de ce
    -- Mac ne le remplacent jamais (deux versions divergeraient). Seul un dossier qui a déjà des
    -- données (l'autre Mac) peut être pris.
    if commun.regle and not commun.present and not DossierCommun.aDesDonnees(dossier)
        and not DossierCommun.rangementInterrompu(dossier) then
        return Chemins.messageAbsent(commun.chemin) .. "\n\nUn dossier sans données de Développeur ne peut pas le remplacer : "
            .. "ses données y seraient copiées. Pour repartir des données de ce Mac, choisissez d'abord « Revenir au dossier de ce Mac »."
    end
    return nil
end

-- Pendant le changement ---------------------------------------------------------------------------

-- Un seul changement à la fois ; la liaison refuse les commandes pendant ce temps.
local function seul(fn)
    if DossierCommun.enCours then
        echouer(DossierCommun.EN_COURS)
    end
    DossierCommun.enCours = true
    Chemins.changement = true
    local ok, resultat = LrTasks.pcall(fn)
    DossierCommun.enCours = false
    Chemins.changement = false
    if not ok then
        error(resultat, 0)
    end
    return resultat
end

-- Le Suivi éteint le temps du changement (sa tâche attendue), puis rallumé s'il tournait.
local function sansLeSuivi(fn)
    local okR, Releve = pcall(require, 'Releve')
    local allume = okR and Releve.allume
    if allume then
        Releve.eteindre()
        local attente = 0
        while Releve.enCours and attente < DossierCommun.ATTENTE_SUIVI and LrTasks.canYield() do
            LrTasks.sleep(0.1)
            attente = attente + 0.1
        end
    end
    local ok, resultat = LrTasks.pcall(fn)
    if allume then
        Releve.allumer()
    end
    if not ok then
        error(resultat, 0)
    end
    return resultat
end

-- Une commande de la liaison (Claude Desktop, Claude Code) déjà commencée : attendue, sinon refus.
-- Les suivantes sont refusées par la liaison (Chemins.changement).
local function attendreLaLiaison()
    local ok, Liaison = pcall(require, 'Liaison')
    if not ok or type(Liaison) ~= 'table' then
        return
    end
    local attente = 0
    while (tonumber(Liaison.enCours) or 0) > 0 and attente < DossierCommun.ATTENTE_LIAISON and LrTasks.canYield() do
        LrTasks.sleep(0.1)
        attente = attente + 0.1
    end
    if (tonumber(Liaison.enCours) or 0) > 0 then
        echouer("Claude Desktop ou Claude Code fait une retouche par la liaison : réessayez quand elle est finie.")
    end
end

local function ecrirePointeur(dossier)
    Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = DossierCommun.FORMAT, dossier = dossier }))
    local commun = Chemins.dossierCommun()
    if not (commun.regle and commun.chemin == dossier) then
        echouer("Le réglage n'a pas pu être écrit dans " .. Chemins.pointeur() .. ".")
    end
end

-- Échanges de Claude Code ---------------------------------------------------------------------------

-- Le dossier du projet de Claude Code du dossier de travail de la fenêtre (Chemins.atelier), donné
-- par relais.sh --projet (le même encodage), nil s'il ne se trouve pas.
function DossierCommun.projetClaude()
    Fichiers.creerDossier(Chemins.temporaire())
    local sortie = LrPathUtils.child(Chemins.temporaire(), 'projet-claude-' .. tostring(os.time()) .. '.txt')
    local q = require('Texte').shell
    LrTasks.execute('/bin/sh ' .. q(Chemins.relais()) .. ' --projet ' .. q(Chemins.atelier()) .. ' > ' .. q(sortie) .. ' 2>/dev/null')
    local texte = Fichiers.lire(sortie)
    Fichiers.supprimer(sortie)
    texte = texte and texte:gsub('%s+$', '') or ''
    if texte:sub(1, 1) ~= '/' then
        return nil
    end
    return texte
end

-- Les échanges de Claude Code des conversations de `racine` (leur sessionID), absents de son
-- « Claude Code/ » : { { id, source } }. Seulement des <id>.jsonl du dossier du projet.
function DossierCommun.echangesAPrendre(racine)
    local liste = {}
    local conversations = LrPathUtils.child(racine, 'Conversations')
    if LrFileUtils.exists(conversations) ~= 'directory' then
        return liste
    end
    local projet = DossierCommun.projetClaude()
    if not projet then
        return liste
    end
    local vus = {}
    for _, nom in ipairs(Fichiers.entrees(conversations)) do
        local texte = Fichiers.lire(LrPathUtils.child(LrPathUtils.child(conversations, nom), 'conversation.json'))
        local ok, c = pcall(Json.decode, texte or '')
        local id = ok and type(c) == 'table' and c.sessionID or nil
        if type(id) == 'string' and id:match('^[A-Za-z0-9_-]+$') and not vus[id] then
            vus[id] = true
            local source = LrPathUtils.child(projet, id .. '.jsonl')
            local deja = LrPathUtils.child(LrPathUtils.child(racine, 'Claude Code'), id .. '.jsonl')
            if LrFileUtils.exists(source) == 'file' and not LrFileUtils.exists(deja) then
                liste[#liste + 1] = { id = id, source = source }
            end
        end
    end
    table.sort(liste, function(a, b) return a.id < b.id end)
    return liste
end

-- Rangement -------------------------------------------------------------------------------------

-- Range d'un coup les `noms` du dossier provisoire dans `dossier`, sous la marque du rangement.
local function ranger(dossier, provisoire, noms)
    local marque = LrPathUtils.child(dossier, DossierCommun.MARQUE_RANGEMENT)
    Fichiers.ecrire(marque, Json.encode({ format = DossierCommun.FORMAT, provisoire = LrPathUtils.leafName(provisoire),
        noms = Json.tableau(noms) }))
    for _, nom in ipairs(noms) do
        deplacer(LrPathUtils.child(provisoire, nom), LrPathUtils.child(dossier, nom))
    end
    Fichiers.supprimer(marque)
    -- Le dossier provisoire, vide, s'en va (rien d'autre n'est jamais retiré).
    if LrFileUtils.exists(provisoire) and #toutesLesEntrees(provisoire) == 0 then
        LrFileUtils.delete(provisoire)
    end
end

-- Termine un rangement interrompu (Lightroom quitté au milieu) : ce qui reste dans le dossier
-- provisoire, dont la copie était finie, est rangé. Rend vrai s'il y en avait un.
function DossierCommun.terminerRangement(dossier)
    local marque = LrPathUtils.child(dossier, DossierCommun.MARQUE_RANGEMENT)
    if LrFileUtils.exists(marque) ~= 'file' then
        return false
    end
    local ok, t = pcall(Json.decode, Fichiers.lire(marque) or '')
    local nomProvisoire = ok and type(t) == 'table' and t.provisoire
    if type(nomProvisoire) ~= 'string' or not nomProvisoire:match('^%.copie%-en%-cours%-[^/]+$') or type(t.noms) ~= 'table' then
        echouer("Un rangement précédent s'est arrêté dans " .. dossier .. " et sa marque " .. DossierCommun.MARQUE_RANGEMENT
            .. " ne se lit pas : vérifiez ce dossier (rien n'y est changé).")
    end
    local provisoire = LrPathUtils.child(dossier, nomProvisoire)
    for _, nom in ipairs(t.noms) do
        if not Chemins.estDonnee(nom) then
            echouer("Un rangement précédent s'est arrêté dans " .. dossier .. " : sa marque nomme « " .. tostring(nom)
                .. " », qui n'est pas une donnée de Développeur (rien n'y est changé).")
        end
        local source, destination = LrPathUtils.child(provisoire, nom), LrPathUtils.child(dossier, nom)
        if LrFileUtils.exists(source) then
            deplacer(source, destination)
        elseif not LrFileUtils.exists(destination) then
            echouer("Un rangement précédent s'est arrêté dans " .. dossier .. " : « " .. nom .. " » ne se trouve ni dans "
                .. provisoire .. " ni à sa place (rien n'y est changé).")
        end
    end
    Fichiers.supprimer(marque)
    if LrFileUtils.exists(provisoire) and #toutesLesEntrees(provisoire) == 0 then
        LrFileUtils.delete(provisoire)
    end
    Journal.noter("Dossier commun : rangement interrompu terminé dans", dossier)
    return true
end

-- Copie les données de `source` (et, venant de ce Mac, les échanges de Claude Code) dans `dossier`.
-- Rend { copies, echanges, releve (l'état des fichiers copiés), noms }.
local function copierLesDonnees(source, dossier, progression, depuisCeMac)
    local noms = DossierCommun.donneesDe(source)
    local echanges = depuisCeMac and DossierCommun.echangesAPrendre(source) or {}
    local r = { copies = 0, echanges = 0, noms = noms, releve = {} }
    if #noms == 0 and #echanges == 0 then
        return r
    end
    local total = #echanges
    for _, nom in ipairs(noms) do
        total = total + DossierCommun.compter(LrPathUtils.child(source, nom))
    end
    if progression and progression.debut then
        progression.debut(total)
    end
    local fait = 0
    local function avancer()
        fait = fait + 1
        if progression and progression.avancer then
            return progression.avancer(fait, math.max(total, fait))
        end
        return true
    end
    -- D'abord dans un dossier caché (jamais pris pour des données), puis rangé d'un coup.
    local provisoire = nomLibre(LrPathUtils.child(dossier, '.copie-en-cours-' .. os.date('%Y-%m-%d-%H%M%S')))
    LrFileUtils.createAllDirectories(provisoire)
    local avant = releve(source, noms)
    for _, nom in ipairs(noms) do
        r.copies = r.copies + DossierCommun.copierArbre(LrPathUtils.child(source, nom), LrPathUtils.child(provisoire, nom), avancer)
    end
    -- Les échanges de Claude Code des conversations (seulement ces .jsonl).
    if #echanges > 0 then
        local dossierEchanges = LrPathUtils.child(provisoire, 'Claude Code')
        LrFileUtils.createAllDirectories(dossierEchanges)
        for _, e in ipairs(echanges) do
            r.echanges = r.echanges + DossierCommun.copierArbre(e.source, LrPathUtils.child(dossierEchanges, e.id .. '.jsonl'), avancer)
        end
        local ranges = {}
        for _, nom in ipairs(noms) do
            ranges[nom] = true
        end
        if not ranges['Claude Code'] then
            noms[#noms + 1] = 'Claude Code'
        end
    end
    -- Un fichier changé pendant la copie (le serveur écrit le guide de style, les rendus) : recopié.
    for _ = 1, DossierCommun.PASSES_RECOPIE do
        local apres = releve(source, r.noms)
        local liste = changes(avant, apres)
        if #liste == 0 then
            break
        end
        for _, relatif in ipairs(liste) do
            local copie = provisoire .. '/' .. relatif
            if LrFileUtils.exists(copie) == 'file' then
                LrFileUtils.delete(copie)
            end
            LrFileUtils.createAllDirectories(LrPathUtils.parent(copie))
            DossierCommun.copierArbre(source .. '/' .. relatif, copie)
        end
        Journal.noter(string.format("Dossier commun : %d fichier(s) changé(s) pendant la copie, recopié(s)", #liste))
        avant = apres
    end
    r.releve = avant
    ranger(dossier, provisoire, noms)
    Journal.noter(string.format("Dossier commun : %d fichier(s) copié(s) de %s vers %s, %d échange(s) de Claude Code",
        r.copies, source, dossier, r.echanges))
    return r
end

-- Choisit `dossier` comme dossier commun (voir l'en-tête). `progression` (facultatif) :
-- { debut(total), avancer(fait, total) → faux pour interrompre }. Rend { dossier, copies (nombre de
-- fichiers copiés), echanges (échanges de Claude Code copiés), pris (vrai : ses données ont été
-- prises telles quelles), rangementTermine, source (d'où viennent les copies), miseDeCote (le
-- dossier où les données de ce Mac sont rangées, ou nil), miseDeCoteRatee (pourquoi elles sont
-- restées en place), changesApres (fichiers changés après leur copie, gardés dans la source) }.
-- Une erreur avant le pointeur laisse le pointeur tel qu'il était.
function DossierCommun.choisir(dossier, progression)
    return seul(function()
        dossier = DossierCommun.preparer(dossier)
        local refus = DossierCommun.refus(dossier)
        if refus then
            echouer(refus)
        end
        return sansLeSuivi(function()
            attendreLaLiaison()
            local locale = Chemins.locale()
            -- Les données à copier : l'ancien dossier commun s'il est là, sinon celles de ce Mac
            -- (l'ancien réglé mais absent est refusé par DossierCommun.refus).
            local commun = Chemins.dossierCommun()
            local source = (commun.regle and commun.present) and commun.chemin or locale
            local resultat = { dossier = dossier, copies = 0, echanges = 0, pris = false, source = source }
            local copie
            resultat.rangementTermine = DossierCommun.terminerRangement(dossier)
            if resultat.rangementTermine or DossierCommun.aDesDonnees(dossier) then
                resultat.pris = true
            else
                copie = copierLesDonnees(source, dossier, progression, source == locale)
                resultat.copies, resultat.echanges = copie.copies, copie.echanges
            end
            -- Le pointeur d'abord : la copie est faite et rangée.
            ecrirePointeur(dossier)
            Journal.noter("Dossier commun réglé :", dossier, resultat.pris and "(données déjà là, prises telles quelles)" or "")
            -- Changé après sa copie (entre la dernière vérification et le pointeur) : la version
            -- récente reste dans la source (mise de côté avec les données de ce Mac), et c'est dit.
            if copie and #copie.noms > 0 then
                local liste = changes(copie.releve, releve(source, copie.noms))
                if #liste > 0 then
                    resultat.changesApres = liste
                    Journal.noter("Dossier commun : changé(s) après la copie, gardé(s) dans " .. source .. " :", table.concat(liste, ", "))
                end
            end
            -- Puis les données de ce Mac mises de côté (jamais effacées) ; un déplacement manqué remet
            -- les précédents à leur place, et le réglage reste fait (elles ne sont plus lues).
            local locales = DossierCommun.donneesDe(locale)
            if #locales > 0 then
                local cote = nomLibre(LrPathUtils.child(locale, 'Avant le dossier commun ' .. os.date('%Y-%m-%d %H-%M')))
                LrFileUtils.createAllDirectories(cote)
                local deplaces = {}
                local ok, erreur = pcall(function()
                    for _, nom in ipairs(locales) do
                        deplacer(LrPathUtils.child(locale, nom), LrPathUtils.child(cote, nom))
                        deplaces[#deplaces + 1] = nom
                    end
                end)
                if ok then
                    resultat.miseDeCote = cote
                    Journal.noter("Dossier commun : données de ce Mac mises de côté dans", cote)
                else
                    for _, nom in ipairs(deplaces) do
                        pcall(deplacer, LrPathUtils.child(cote, nom), LrPathUtils.child(locale, nom))
                    end
                    if #toutesLesEntrees(cote) == 0 then
                        LrFileUtils.delete(cote)
                    end
                    resultat.miseDeCoteRatee = tostring(erreur)
                    Journal.noter("Dossier commun : mise de côté manquée, données de ce Mac laissées en place ·", tostring(erreur))
                end
            end
            return resultat
        end)
    end)
end

-- Revient au dossier de ce Mac : le pointeur est retiré, rien n'est copié. Rend le chemin du dossier
-- commun quitté (nil s'il n'y en avait pas).
function DossierCommun.revenir()
    return seul(function()
        local commun = Chemins.dossierCommun()
        if not Fichiers.existe(Chemins.pointeur()) then
            return nil
        end
        return sansLeSuivi(function()
            attendreLaLiaison()
            Fichiers.supprimer(Chemins.pointeur())
            if Fichiers.existe(Chemins.pointeur()) then
                echouer("Le réglage " .. Chemins.pointeur() .. " n'a pas pu être retiré.")
            end
            Journal.noter("Dossier commun retiré : retour au dossier de ce Mac ; rien n'est copié depuis", tostring(commun.chemin))
            return commun.chemin
        end)
    end)
end

-- L'état en mots, pour le Gestionnaire et le diagnostic.
function DossierCommun.texteEtat()
    local commun = Chemins.dossierCommun()
    if not commun.regle then
        return "aucun : les données restent sur ce Mac (" .. Chemins.locale() .. ")"
    elseif commun.present then
        return commun.chemin
    end
    return commun.chemin .. " — introuvable (SSD débranché ?)"
end

local function pluriel(n, mot)
    return string.format("%d %s%s", n, mot, n > 1 and "s" or "")
end

-- Ce que dit la fenêtre après un choix réussi.
function DossierCommun.texteChoix(r)
    local lignes = { "Dossier commun : " .. r.dossier .. "." }
    if r.rangementTermine then
        lignes[#lignes + 1] = "Un réglage précédent s'était arrêté pendant le rangement des données copiées : il est terminé, et ces données sont prises."
    elseif r.pris then
        lignes[#lignes + 1] = "Ce dossier avait déjà des données de Développeur : elles sont prises telles quelles (rien n'y est copié)."
    elseif r.copies > 0 or (r.echanges or 0) > 0 then
        local copies = string.format("%s copié%s depuis %s", pluriel(r.copies, "fichier"), r.copies > 1 and "s" or "", r.source)
        if (r.echanges or 0) > 0 then
            copies = copies .. string.format(", et %s de Claude Code (pour reprendre les conversations sur l'autre Mac)",
                pluriel(r.echanges, "échange"))
        end
        lignes[#lignes + 1] = copies .. "."
    else
        lignes[#lignes + 1] = "Rien à copier : les données s'y rangeront dès maintenant."
    end
    if r.changesApres and #r.changesApres > 0 then
        local n = #r.changesApres
        lignes[#lignes + 1] = string.format("%s pendant le réglage, après sa copie (%s) : la version récente est gardée dans %s.",
            n > 1 and (n .. " fichiers ont changé") or "1 fichier a changé", table.concat(r.changesApres, ", "),
            r.miseDeCote or r.source)
    end
    if r.miseDeCote then
        lignes[#lignes + 1] = "Les données de ce Mac sont mises de côté (rien n'est effacé) dans " .. r.miseDeCote .. "."
    elseif r.miseDeCoteRatee then
        lignes[#lignes + 1] = "Les données de ce Mac n'ont pas pu être mises de côté : elles restent dans " .. Chemins.locale()
            .. ", où Développeur ne les lit plus (rien n'est effacé). " .. r.miseDeCoteRatee
    end
    lignes[#lignes + 1] = "Sur l'autre Mac, choisissez le même dossier : vous y reprendrez le travail où vous l'avez laissé."
    return table.concat(lignes, "\n\n")
end

return DossierCommun
