-- Init.lua : exécuté au chargement du module (lancement de Lightroom, rechargement ou
-- réactivation dans le Gestionnaire de modules externes). Six choses, chacune à l'abri des
-- autres (une erreur dans l'une n'empêche pas les suivantes) :
--   1. le ménage des paramètres prédéfinis invisibles laissés par la session précédente (Menage.lua) ;
--   2. le démarrage de la liaison avec le serveur, si la préférence le demande ;
--   3. dans une tâche, d'abord les dossiers temporaires des conversations jamais gardées (groupes
--      de photos, demandes rapides sur plusieurs photos ; Menage.temporaires, correctif 1.3.6), ceux
--      du Suivi, les vignettes de la fenêtre Claude (PhotoActive, Pourquoi, Collees) et les fichiers
--      de passage de Temporaire (dimensions-*.txt…) : en premier, avant qu'une fenêtre ait pu
--      s'ouvrir et y écrire (Session.menage attend la fin des processus) ;
--   4. dans la même tâche, à part, la fermeture des processus Claude Code d'une séance précédente de
--      la fenêtre Claude et l'effacement de leurs dossiers (Session.menage) ;
--   5. dans la même tâche, à part, le ménage de l'avant/après des étapes (Etapes.menage, 1.3) :
--      fichiers de plus de 30 jours, puis les plus anciens au-delà de 500 Mo ; puis, à part et en
--      dernier, les mises à jour par le SSD (MisesAJour.auLancement, 1.7 : dossier commun réglé et
--      présent seulement, après une attente) ;
--   6. le Suivi allumé (Releve.allumer, correctif 1.3.7) : les photos que la fenêtre Claude et la
--      Demande rapide voient entrent au relevé, puis à la file d'analyse (aucune tâche ici : la
--      boucle d'une fenêtre la lance). Seulement dans Lightroom : les suites de tests ne chargent
--      pas ce fichier, sauf leurs essais d'Init, qui l'éteignent ensuite.

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
        require('Menage').temporaires()
    end)
    LrTasks.pcall(function()
        require 'Compat'
        require('Session').menage()
    end)
    LrTasks.pcall(function()
        require('Etapes').menage()
    end)
    -- En dernier, à part : les mises à jour par le SSD (MisesAJour.lua, 1.7), seulement avec un
    -- dossier commun réglé et présent (sinon rien, sans attendre).
    LrTasks.pcall(function()
        require('MisesAJour').auLancement()
    end)
end)

pcall(function()
    require('Releve').allumer()
end)
