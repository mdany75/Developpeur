-- Fichiers.lua : lecture et écriture de fichiers, par LrFileUtils et io.

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

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
