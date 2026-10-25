-- Preferences.lua : réglages du module, gardés par Lightroom (LrPrefs) et modifiables dans
-- Fichier › Gestionnaire de modules externes › Développeur. Ceux de la liaison sont ici ; ceux de
-- la fenêtre Claude (disposition, modèle, chemins de Claude Code et du connecteur…) sont dans
-- Chemins.defauts, dans la même table : aucune clé ne sert aux deux. Le mode « Proposer d'abord »
-- (`mode`) est celui de la liaison, que la fenêtre montre et bascule.

local LrPrefs = import 'LrPrefs'

local Preferences = {}

Preferences.defauts = {
    demarrerAuLancement = true,
    -- 'appliquer' : Claude applique directement ; 'proposer' : il doit d'abord obtenir l'accord
    -- de l'utilisateur dans la conversation (confirm = true).
    mode = 'appliquer',
    -- Instantané « Avant Claude » à la première retouche d'une photo.
    instantane = true,
    -- Limites de sécurité : variation de l'exposition par retouche (IL), saturation absolue.
    variationExpositionMax = 2,
    saturationMax = 30,
    -- Garde-fous des photos : refuser toute écriture sur une photo qui n'est pas une
    -- copie virtuelle ; sur une photo qui porte ce libellé de couleur ('aucun', 'rouge', 'jaune',
    -- 'vert', 'bleu', 'violet') ; sur une photo rejetée ; plus de photos que le plafond par écriture
    -- sans accord explicite (0 : sans plafond).
    copiesSeulement = false,
    libelleProtege = 'aucun',
    rejeteesProtegees = false,
    plafondPhotos = 20,
    -- En mode « Proposer d'abord », l'accord se donne dans la fenêtre de la liaison (bouton Accepter),
    -- pas par confirm = true seul.
    accordDansLightroom = false,
    -- Message bref au centre de l'écran à chaque écriture de Claude.
    retourVisuel = true,
    -- Le point de mise au point (Fujifilm) dessiné sur chaque aperçu de view_photo, pas seulement
    -- quand Claude note.
    pointMiseAuPoint = false,
    -- Carnet de progrès (1.3) : les défauts de la prise de vue que le connecteur constate avant la
    -- première retouche de Claude sont notés dans carnet.json (Carnet.lua), à part du catalogue.
    carnet = true,
}

-- Préférences du module, complétées par les valeurs par défaut.
function Preferences.lire()
    local prefs = LrPrefs.prefsForPlugin()
    for cle, valeur in pairs(Preferences.defauts) do
        if prefs[cle] == nil then
            prefs[cle] = valeur
        end
    end
    return prefs
end

return Preferences
