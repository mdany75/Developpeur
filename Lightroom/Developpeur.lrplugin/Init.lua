-- Init.lua : exécuté au chargement du module (lancement de Lightroom, rechargement ou
-- réactivation dans le Gestionnaire de modules externes). Quatre choses, chacune à l'abri des
-- autres (une erreur dans l'une n'empêche pas les suivantes) :
--   1. le ménage des paramètres prédéfinis invisibles laissés par la session précédente (Menage.lua) ;
--   2. le démarrage de la liaison avec le serveur, si la préférence le demande ;
--   3. dans une tâche, la fermeture des processus Claude Code d'une séance précédente de la fenêtre
--      Claude et l'effacement de leurs dossiers (Session.menage) ;
--   4. dans la même tâche, à part, le ménage de l'avant/après des étapes (Etapes.menage, 1.3) :
--      fichiers de plus de 30 jours, puis les plus anciens au-delà de 500 Mo.

local LrTasks = import 'LrTasks'

pcall(function()
    local effaces = require('Menage').presetsInvisibles()
    if effaces > 0 then
        require('Liaison').noter(string.format("%d paramètre(s) prédéfini(s) invisible(s) de la session précédente effacé(s)", effaces))
    end
end)

pcall(function()
    if require('Preferences').lire().demarrerAuLancement then
        require('Liaison').demarrer()
    end
end)

LrTasks.startAsyncTask(function()
    LrTasks.pcall(function()
        require 'Compat'
        require('Session').menage()
    end)
    LrTasks.pcall(function()
        require('Etapes').menage()
    end)
end)
