-- MenuRevenir.lua : Fichier (ou Bibliothèque) › Module externe - Extras › Revenir à « Avant Claude »
-- Remet les photos sélectionnées dans leur état d'avant la première retouche de Claude
-- (seulement les réglages que Claude a changés). S'annule avec ⌘Z.

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local Liaison = require 'Liaison'

LrTasks.startAsyncTask(function()
    local nombre = #LrApplication.activeCatalog():getTargetPhotos()
    if nombre == 0 then
        LrDialogs.message("Aucune photo sélectionnée.")
        return
    end
    local question = nombre == 1
        and "Revenir à l'état d'avant Claude pour cette photo ?"
        or string.format("Revenir à l'état d'avant Claude pour ces %d photos ?", nombre)
    local reponse = LrDialogs.confirm(question,
        "Seuls les réglages que Claude a modifiés sont remis. Les autres retouches sont gardées, et ⌘Z annule l'opération.",
        "Revenir", "Annuler")
    if reponse ~= 'ok' then
        return
    end

    local Annulation = require 'Annulation'
    local ok, resultat = LrTasks.pcall(Annulation.revenir, { selection = true, depuisLightroom = true })
    if not ok then
        LrDialogs.message("Retour impossible", Liaison.messageErreur(resultat), 'warning')
        return
    end
    local remises, echecs = 0, {}
    for _, element in ipairs(resultat.resultats) do
        if element.remise then
            remises = remises + 1
        elseif not element.sans_retouche then
            -- Par exemple un débruitage que Lightroom n'a pas pu retirer : la photo reste telle quelle.
            echecs[#echecs + 1] = (element.photo and element.photo.fichier or "?") .. " : " .. tostring(element.raison)
        end
    end
    if #echecs > 0 then
        LrDialogs.message(string.format("%d photo(s) remise(s) à l'état d'avant Claude ; %d non remise(s)", remises, #echecs),
            table.concat(echecs, "\n"), 'warning')
    elseif remises == 0 then
        LrDialogs.message("Aucune de ces photos n'a été retouchée par Claude.")
    else
        LrDialogs.showBezel(string.format("%d photo(s) remise(s) à l'état d'avant Claude", remises))
    end
end)
