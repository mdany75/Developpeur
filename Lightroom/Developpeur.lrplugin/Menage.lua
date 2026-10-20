-- Menage.lua : efface les paramètres prédéfinis invisibles que le module a créés (un fichier par
-- masque IA, flou d'objectif ou mode automatique, dans Plugin Develop Presets/<id du module>) :
-- Lightroom les charge tous à son lancement, et le module recrée par leur nom ceux dont il a
-- besoin. Appelé au chargement du module (Init.lua) et à son arrêt (Arret.lua). Constaté le
-- 17 octobre 2026 : à la fermeture de Lightroom, Arret.lua (LrShutdownPlugin) ne s'exécute pas ;
-- le chargement suivant fait donc le ménage. Effacer des fichiers déjà chargés ne change rien à
-- la session en cours (Lightroom les garde en mémoire).

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local Menage = {}

function Menage.dossierPresets()
    local dossier = LrPathUtils.getStandardFilePath('home')
    for _, nom in ipairs({ 'Library', 'Application Support', 'Adobe', 'Lightroom', 'Plugin Develop Presets', _PLUGIN.id }) do
        dossier = LrPathUtils.child(dossier, nom)
    end
    return dossier
end

-- Nombre de fichiers effacés.
function Menage.presetsInvisibles()
    local dossier = Menage.dossierPresets()
    if not LrFileUtils.exists(dossier) then
        return 0
    end
    local effaces = 0
    for chemin in LrFileUtils.files(dossier) do
        if tostring(chemin):match('%.lrtemplate$') then
            LrFileUtils.delete(chemin)
            effaces = effaces + 1
        end
    end
    return effaces
end

return Menage
