-- MenuCopie.lua : Fichier (ou Bibliothèque) › Module externe - Extras › Créer une copie virtuelle pour Claude
-- Crée une copie virtuelle « Claude » de chaque photo sélectionnée et la sélectionne, prête pour la
-- conversation : Claude retouche la copie, l'original reste tel quel.

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local Liaison = require 'Liaison'

LrTasks.startAsyncTask(function()
    if #LrApplication.activeCatalog():getTargetPhotos() == 0 then
        LrDialogs.message("Aucune photo sélectionnée.")
        return
    end
    local Bibliotheque = require 'Bibliotheque'
    -- Demandé dans Lightroom : ni la pause ni le mode « Proposer d'abord » ne s'y appliquent.
    local ok, resultat = LrTasks.pcall(Bibliotheque.copieVirtuelle, { selection = true, afficher = true, depuisLightroom = true, confirme = true })
    if not ok then
        LrDialogs.message("Copie virtuelle impossible", Liaison.messageErreur(resultat), 'warning')
        return
    end
    local ids = {}
    for _, copie in ipairs(resultat.copies) do
        ids[#ids + 1] = tostring(copie.id)
    end
    Liaison.noter("Copie virtuelle pour Claude : " .. (#ids > 0 and table.concat(ids, ", ") or "aucune"))
    if #ids > 0 then
        LrDialogs.showBezel(#ids > 1 and string.format("%d copies virtuelles « Claude »", #ids) or "Copie virtuelle « Claude » créée")
    end
end)
