-- Raccourcis.lua : raccourcis clavier des entrées de menu du module. Le SDK ne permet pas à un
-- module d'en déclarer : ce sont des raccourcis d'app de macOS (NSUserKeyEquivalents de
-- Lightroom, les mêmes que Réglages Système › Clavier › Raccourcis › Raccourcis des apps, où ils
-- se modifient ou se retirent). Lightroom les lit à son lancement.
--
-- Lightroom met trois espaces devant chaque entrée d'un module dans Module externe - Extras
-- (« Développeur », puis «    Ouvrir la fenêtre Claude » : lu par l'accessibilité,
-- Lightroom Classic 15.6). macOS cherche le titre exact : sans ces espaces, le raccourci n'est
-- jamais appliqué (constaté).

local LrTasks = import 'LrTasks'

local Texte = require 'Texte'

local Raccourcis = {}

Raccourcis.DOMAINE = 'com.adobe.LightroomClassicCC7'

-- Devant le titre de chaque entrée de module dans le menu de Lightroom.
Raccourcis.RETRAIT = '   '

-- Titre de l'entrée de menu (sans le retrait) → touches (^ Contrôle, ~ Option, @ Commande, $ Majuscule).
-- Seulement la fenêtre de conversation (Publication et Consommation s'ouvrent par ses boutons).
Raccourcis.LISTE = {
    { titre = "Ouvrir la fenêtre Claude", touches = '^~c', affichage = '⌃⌥C' },
}

-- « ⌃⌥C fenêtre Claude ».
function Raccourcis.texte()
    local morceaux = {}
    for _, r in ipairs(Raccourcis.LISTE) do
        morceaux[#morceaux + 1] = r.affichage .. ' ' .. r.titre:gsub('…$', ''):gsub('^Ouvrir la ', '')
    end
    return table.concat(morceaux, ', ')
end

-- Ajoute les raccourcis à ceux de Lightroom (sans toucher aux autres). Rend true si macOS les a
-- enregistrés. À appeler depuis une tâche.
function Raccourcis.poser(domaine)
    local arguments = {}
    for _, r in ipairs(Raccourcis.LISTE) do
        arguments[#arguments + 1] = Texte.shell(Raccourcis.RETRAIT .. r.titre)
        arguments[#arguments + 1] = Texte.shell(r.touches)
    end
    local commande = '/usr/bin/defaults write ' .. Texte.shell(domaine or Raccourcis.DOMAINE)
        .. ' NSUserKeyEquivalents -dict-add ' .. table.concat(arguments, ' ') .. ' >/dev/null 2>&1'
    return LrTasks.execute(commande) == 0
end

return Raccourcis
