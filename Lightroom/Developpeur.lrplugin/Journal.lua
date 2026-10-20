-- Journal.lua : ~/Library/Logs/Developpeur/conversation.log, gardé sous 1 Mo (l'ancien
-- devient conversation.log.1). Pour comprendre après coup un lancement de Claude Code raté.

local LrDate = import 'LrDate'
local LrFileUtils = import 'LrFileUtils'

local Chemins = require 'Chemins'

local Journal = {}

local TAILLE_MAX = 1024 * 1024

function Journal.noter(...)
    local morceaux = {}
    for i = 1, select('#', ...) do
        morceaux[#morceaux + 1] = tostring((select(i, ...)))
    end
    pcall(function()
        local dossier = Chemins.journaux()
        if not LrFileUtils.exists(dossier) then
            LrFileUtils.createAllDirectories(dossier)
        end
        local chemin = Chemins.journal()
        local attributs = LrFileUtils.fileAttributes(chemin)
        if attributs and (attributs.fileSize or 0) > TAILLE_MAX then
            LrFileUtils.delete(chemin .. '.1')
            LrFileUtils.move(chemin, chemin .. '.1')
        end
        local f = io.open(chemin, 'a')
        if f then
            f:write(LrDate.timeToUserFormat(LrDate.currentTime(), '%Y-%m-%d %H:%M:%S'), '  ', table.concat(morceaux, ' '), '\n')
            f:close()
        end
    end)
end

return Journal
