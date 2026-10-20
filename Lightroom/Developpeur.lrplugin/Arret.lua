-- Arret.lua : exécuté quand le module est désactivé, rechargé ou déchargé. Chaque étape est à
-- l'abri des autres : ferme les prises réseau de la liaison pour libérer les ports, ferme la barre
-- de progression d'une série, ferme Claude Code s'il répond encore à la fenêtre Claude (relais.sh
-- le ferme aussi de lui-même quand Lightroom quitte), puis efface les paramètres prédéfinis
-- invisibles du module (Menage.lua).
-- À la fermeture de Lightroom, il ne s'exécute pas (constaté) : le ménage se fait au chargement.

pcall(function() require('Liaison').arreter() end)
pcall(function() require('Progression').fermer() end)

pcall(function()
    local Moteur = require 'Moteur'
    Moteur.boucle = false
    Moteur.arreterSession()
end)

pcall(function()
    local effaces = require('Menage').presetsInvisibles()
    if effaces > 0 then
        require('Liaison').noter(string.format("%d paramètre(s) prédéfini(s) invisible(s) du module effacé(s)", effaces))
    end
end)
