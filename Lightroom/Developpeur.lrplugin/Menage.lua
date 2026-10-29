-- Menage.lua : efface les paramètres prédéfinis invisibles que le module a créés (un fichier par
-- masque IA, flou d'objectif ou mode automatique, dans Plugin Develop Presets/<id du module>) :
-- Lightroom les charge tous à son lancement, et le module recrée par leur nom ceux dont il a
-- besoin. Appelé au chargement du module (Init.lua) et à son arrêt (Arret.lua). Constaté le
-- 17 octobre 2026 : à la fermeture de Lightroom, Arret.lua (LrShutdownPlugin) ne s'exécute pas ;
-- le chargement suivant fait donc le ménage. Effacer des fichiers déjà chargés ne change rien à
-- la session en cours (Lightroom les garde en mémoire). Depuis le correctif 1.3.6, aussi les
-- dossiers temporaires des conversations jamais gardées (Menage.temporaires, au chargement seul).

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

-- Les dossiers temporaires des conversations jamais gardées (correctif 1.3.6) : celles des groupes
-- de photos de la fenêtre Claude (Temporaire/Groupes/<id>, Fenetre.conversationDeGroupe) et des
-- demandes rapides sur plusieurs photos (Temporaire/Rapide/<id>, Moteur.envoyerRapide). Ils ne
-- s'effacent que quand leur conversation est quittée ou oubliée (Moteur.montrer,
-- Moteur.oublierRapide) : une séance qui finit sur l'une d'elles (Lightroom quitté, module
-- rechargé) les laisserait pour toujours. Au chargement, aucune n'est en mémoire : ils s'effacent en
-- entier. Depuis le correctif 1.3.7, aussi ceux du Suivi (Temporaire/Suivi : les vignettes d'un lot
-- d'analyse, Releve.lua, qu'une séance finie pendant le lot laisserait), et depuis la retouche
-- générative (29 octobre 2026) ceux de Fibo 2 (Temporaire/Fibo : l'exportation, l'entrée et la sortie
-- de Fibo d'un appel de generative_edit que Lightroom a quitté en cours). Rien d'autre de
-- Temporaire, ni les conversations gardées. Rend le nombre de dossiers effacés. Dans une tâche
-- (Init.lua).
Menage.TEMPORAIRES = { 'Groupes', 'Rapide', 'Suivi', 'Fibo' }

function Menage.temporaires()
    local Chemins = require 'Chemins'
    local effaces = 0
    for _, nom in ipairs(Menage.TEMPORAIRES) do
        local dossier = LrPathUtils.child(Chemins.temporaire(), nom)
        if LrFileUtils.exists(dossier) then
            LrFileUtils.delete(dossier)
            effaces = effaces + 1
        end
    end
    return effaces
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
