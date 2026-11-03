-- Fichiers.lua : lecture et écriture de fichiers, par LrFileUtils et io.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

local Fichiers = {}

-- LrFileUtils.exists rend false, 'file' ou 'directory'.
function Fichiers.existe(chemin)
    return chemin ~= nil and chemin ~= '' and LrFileUtils.exists(chemin) and true or false
end

function Fichiers.creerDossier(chemin)
    if not LrFileUtils.exists(chemin) then
        LrFileUtils.createAllDirectories(chemin)
    end
    return chemin
end

function Fichiers.lire(chemin)
    local f = io.open(chemin, 'rb')
    if not f then
        return nil
    end
    local contenu = f:read('*a')
    f:close()
    return contenu
end

-- Écrit un fichier entier : d'abord à côté, puis remplacé d'un coup, pour ne jamais laisser un
-- fichier à moitié écrit si Lightroom se ferme pendant l'écriture.
function Fichiers.ecrire(chemin, contenu)
    Fichiers.creerDossier(LrPathUtils.parent(chemin))
    local provisoire = chemin .. '.provisoire'
    local f, erreur = io.open(provisoire, 'wb')
    if not f then
        error("Écriture impossible : " .. tostring(erreur), 0)
    end
    f:write(contenu)
    f:close()
    if not (type(os.rename) == 'function' and os.rename(provisoire, chemin)) then
        LrFileUtils.delete(chemin)
        LrFileUtils.move(provisoire, chemin)
    end
end

-- Écrit un fichier entier par morceaux, comme Fichiers.ecrire (d'abord à côté, puis remplacé d'un
-- coup : jamais à moitié écrit) : `produire(ecrire)` appelle ecrire(texte) pour chaque morceau, et
-- peut rendre la main à Lightroom entre deux (correctif 1.3.8 : le relevé du Suivi, plus de 100 Mo à
-- 250 000 originaux, ne se fait plus en un seul texte). `produire` rend faux pour abandonner : le
-- fichier provisoire s'efface, le fichier d'avant reste tel quel (comme après une erreur, qui
-- remonte). Rend vrai si le fichier est remplacé. `avantDeRemplacer` (facultatif) est appelé une
-- fois tout écrit, juste avant de remplacer le fichier (le relevé du Suivi y efface son journal,
-- demandé par Dany le 2 novembre 2026) : une erreur y abandonne l'écriture comme une autre.
function Fichiers.ecrireParMorceaux(chemin, produire, avantDeRemplacer)
    Fichiers.creerDossier(LrPathUtils.parent(chemin))
    local provisoire = chemin .. '.provisoire'
    local f, erreur = io.open(provisoire, 'wb')
    if not f then
        error("Écriture impossible : " .. tostring(erreur), 0)
    end
    local function ecrire(texte)
        local ok, raison = f:write(texte)
        if not ok then
            error("Écriture impossible : " .. tostring(raison), 0)
        end
    end
    -- LrTasks.pcall : `produire` rend la main (un pcall simple l'en empêcherait, Lua 5.1).
    local ok, suite = LrTasks.pcall(produire, ecrire)
    f:close()
    if not ok or suite == false then
        LrFileUtils.delete(provisoire)
        if not ok then
            error(suite, 0)
        end
        return false
    end
    if avantDeRemplacer then
        local okAvant, erreurAvant = LrTasks.pcall(avantDeRemplacer)
        if not okAvant then
            LrFileUtils.delete(provisoire)
            error(erreurAvant, 0)
        end
    end
    if not (type(os.rename) == 'function' and os.rename(provisoire, chemin)) then
        LrFileUtils.delete(chemin)
        LrFileUtils.move(provisoire, chemin)
    end
    return true
end

-- Ajoute à la fin d'un fichier (créé s'il manque) par morceaux : `produire(ecrire)` appelle
-- ecrire(texte) pour chaque morceau, et peut rendre la main entre deux ; il rend faux pour s'arrêter
-- (ce qui est déjà ajouté reste). Une erreur remonte, le fichier fermé. Rend vrai si tout est ajouté.
-- Pour le journal du relevé du Suivi (demandé par Dany le 2 novembre 2026 : ne plus réécrire tout
-- suivi.json pendant l'analyse).
function Fichiers.ajouterParMorceaux(chemin, produire)
    Fichiers.creerDossier(LrPathUtils.parent(chemin))
    local f, erreur = io.open(chemin, 'ab')
    if not f then
        error("Écriture impossible : " .. tostring(erreur), 0)
    end
    local function ecrire(texte)
        local ok, raison = f:write(texte)
        if not ok then
            error("Écriture impossible : " .. tostring(raison), 0)
        end
        f:flush()
    end
    local ok, suite = LrTasks.pcall(produire, ecrire)
    f:close()
    if not ok then
        error(suite, 0)
    end
    return suite ~= false
end

-- Ajoute une ligne à la fin d'un fichier.
function Fichiers.ajouterLigne(chemin, ligne)
    local f, erreur = io.open(chemin, 'ab')
    if not f then
        error("Écriture impossible : " .. tostring(erreur), 0)
    end
    f:write(ligne, '\n')
    f:close()
end

-- Noms des fichiers et dossiers d'un dossier (sans les fichiers cachés).
function Fichiers.entrees(dossier)
    local noms = {}
    if not LrFileUtils.exists(dossier) then
        return noms
    end
    for chemin in LrFileUtils.directoryEntries(dossier) do
        local nom = LrPathUtils.leafName(chemin)
        if nom:sub(1, 1) ~= '.' then
            noms[#noms + 1] = nom
        end
    end
    table.sort(noms)
    return noms
end

function Fichiers.copier(source, destination)
    if LrFileUtils.exists(destination) then
        return true
    end
    return LrFileUtils.copy(source, destination)
end

-- À la corbeille du Finder (récupérable), ou effacé si la corbeille refuse.
function Fichiers.corbeille(chemin)
    if not LrFileUtils.exists(chemin) then
        return true
    end
    local ok = LrFileUtils.moveToTrash(chemin)
    if not ok then
        ok = LrFileUtils.delete(chemin)
    end
    return ok
end

function Fichiers.supprimer(chemin)
    if LrFileUtils.exists(chemin) then
        return LrFileUtils.delete(chemin)
    end
    return true
end

-- Date de modification (secondes), nil si absent.
function Fichiers.date(chemin)
    local attributs = LrFileUtils.fileAttributes(chemin)
    return attributs and attributs.fileModificationDate
end

return Fichiers
