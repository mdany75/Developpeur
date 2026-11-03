-- DossierCommun.lua : le réglage « Dossier commun » du Gestionnaire de modules externes (demandé
-- par Dany le 3 novembre 2026 : deux Mac, le SSD « Photos » qui passe de l'un à l'autre, jamais
-- les deux en même temps ; « que je travaille sur l'un ou l'autre, tout est pareil, je reprends le
-- travail où je l'avais arrêté »).
--
-- Seul ce fichier écrit le pointeur local dossier-commun.json (Chemins.pointeur) ; Chemins.lua et
-- le serveur le lisent à chaque accès. Choisir un dossier :
--   - s'il n'a pas encore de données de Développeur (Chemins.estDonnee), celles de la racine des
--     données actuelle (ce Mac, ou l'ancien dossier commun) y sont COPIÉES, avec leur progression,
--     d'abord dans un dossier caché « .copie-en-cours-<date> », puis rangées d'un coup (une copie
--     interrompue n'est jamais prise pour des données) ;
--   - s'il en a déjà (le deuxième Mac), elles sont prises telles quelles ;
--   - dans les deux cas, les données de ce Mac (racine locale) sont déplacées dans « Avant le
--     dossier commun <AAAA-MM-JJ HH-MM> » de la racine locale : rien n'est effacé ;
--   - puis le pointeur est écrit.
-- « Revenir au dossier de ce Mac » retire le pointeur, sans rien copier.
-- Pendant le changement, le Suivi est éteint (aucune écriture de suivi.json entre la copie et le
-- pointeur), puis rallumé ; les registres en mémoire (carnet, notes, consommation, relevé, liste des
-- conversations) se relisent d'eux-mêmes quand la racine change.

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
-- Secondes au plus pour laisser finir la tâche du Suivi avant le changement.
DossierCommun.ATTENTE_SUIVI = 30

local function echouer(message)
    error(message, 0)
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
-- même taille). `avancer()` est appelé après chaque fichier ; il rend faux pour interrompre. Rend le
-- nombre de fichiers copiés ; une erreur dit lequel n'a pas pu l'être. Rien n'est jamais effacé.
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
    if avancer and avancer() == false then
        echouer("Copie interrompue : le dossier commun n'est pas réglé.")
    end
    return 1
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
    return nil
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

local function ecrirePointeur(dossier)
    Fichiers.ecrire(Chemins.pointeur(), Json.encode({ format = DossierCommun.FORMAT, dossier = dossier }))
    local commun = Chemins.dossierCommun()
    if not (commun.regle and commun.chemin == dossier) then
        echouer("Le réglage n'a pas pu être écrit dans " .. Chemins.pointeur() .. ".")
    end
end

-- Choisit `dossier` comme dossier commun (voir l'en-tête). `progression` (facultatif) :
-- { debut(total), avancer(fait, total) → faux pour interrompre }. Rend { dossier, copies (nombre de
-- fichiers copiés), pris (vrai : ses données ont été prises telles quelles), source (d'où viennent
-- les copies), miseDeCote (le dossier où les données de ce Mac sont rangées, ou nil) }. Une erreur
-- laisse le pointeur tel qu'il était.
function DossierCommun.choisir(dossier, progression)
    if type(dossier) == 'string' and #dossier > 1 then
        dossier = dossier:gsub('/+$', '')
    end
    local refus = DossierCommun.refus(dossier)
    if refus then
        echouer(refus)
    end
    return sansLeSuivi(function()
        local locale = Chemins.locale()
        -- Les données à copier : la racine des données actuelle (l'ancien dossier commun s'il est
        -- là, sinon celles de ce Mac).
        local commun = Chemins.dossierCommun()
        local source = (commun.regle and commun.present) and commun.chemin or locale
        local resultat = { dossier = dossier, copies = 0, pris = false, source = source }
        if DossierCommun.aDesDonnees(dossier) then
            resultat.pris = true
        else
            local noms = DossierCommun.donneesDe(source)
            if #noms > 0 then
                local total = 0
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
                        return progression.avancer(fait, total)
                    end
                    return true
                end
                -- D'abord dans un dossier caché (jamais pris pour des données), puis rangé d'un coup.
                local provisoire = nomLibre(LrPathUtils.child(dossier, '.copie-en-cours-' .. os.date('%Y-%m-%d-%H%M%S')))
                LrFileUtils.createAllDirectories(provisoire)
                for _, nom in ipairs(noms) do
                    resultat.copies = resultat.copies + DossierCommun.copierArbre(LrPathUtils.child(source, nom),
                        LrPathUtils.child(provisoire, nom), avancer)
                end
                for _, nom in ipairs(noms) do
                    deplacer(LrPathUtils.child(provisoire, nom), LrPathUtils.child(dossier, nom))
                end
                -- Le dossier provisoire, vide, s'en va (rien d'autre n'est jamais retiré).
                if #toutesLesEntrees(provisoire) == 0 then
                    LrFileUtils.delete(provisoire)
                end
                Journal.noter(string.format("Dossier commun : %d fichier(s) copié(s) de %s vers %s", resultat.copies, source, dossier))
            end
        end
        -- Les données de ce Mac mises de côté (jamais effacées) ; un déplacement manqué remet les
        -- précédents à leur place, et le pointeur n'est pas écrit.
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
            if not ok then
                for _, nom in ipairs(deplaces) do
                    pcall(deplacer, LrPathUtils.child(cote, nom), LrPathUtils.child(locale, nom))
                end
                echouer(tostring(erreur) .. " Le dossier commun n'est pas réglé.")
            end
            resultat.miseDeCote = cote
            Journal.noter("Dossier commun : données de ce Mac mises de côté dans", cote)
        end
        ecrirePointeur(dossier)
        Journal.noter("Dossier commun réglé :", dossier, resultat.pris and "(données déjà là, prises telles quelles)" or "")
        return resultat
    end)
end

-- Revient au dossier de ce Mac : le pointeur est retiré, rien n'est copié. Rend le chemin du dossier
-- commun quitté (nil s'il n'y en avait pas).
function DossierCommun.revenir()
    local commun = Chemins.dossierCommun()
    if not Fichiers.existe(Chemins.pointeur()) then
        return nil
    end
    return sansLeSuivi(function()
        Fichiers.supprimer(Chemins.pointeur())
        if Fichiers.existe(Chemins.pointeur()) then
            echouer("Le réglage " .. Chemins.pointeur() .. " n'a pas pu être retiré.")
        end
        Journal.noter("Dossier commun retiré : retour au dossier de ce Mac ; rien n'est copié depuis", tostring(commun.chemin))
        return commun.chemin
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

-- Ce que dit la fenêtre après un choix réussi.
function DossierCommun.texteChoix(r)
    local lignes = { "Dossier commun : " .. r.dossier .. "." }
    if r.pris then
        lignes[#lignes + 1] = "Ce dossier avait déjà des données de Développeur : elles sont prises telles quelles (rien n'y est copié)."
    elseif r.copies > 0 then
        lignes[#lignes + 1] = string.format("%d fichier%s copié%s depuis %s.", r.copies, r.copies > 1 and "s" or "",
            r.copies > 1 and "s" or "", r.source)
    else
        lignes[#lignes + 1] = "Rien à copier : les données s'y rangeront dès maintenant."
    end
    if r.miseDeCote then
        lignes[#lignes + 1] = "Les données de ce Mac sont mises de côté (rien n'est effacé) dans " .. r.miseDeCote .. "."
    end
    lignes[#lignes + 1] = "Sur l'autre Mac, choisissez le même dossier : vous y reprendrez le travail où vous l'avez laissé."
    return table.concat(lignes, "\n\n")
end

return DossierCommun
