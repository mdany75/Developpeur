-- Chemins.lua : dossiers et réglages de la fenêtre Claude.
--
--   ~/Library/Application Support/Developpeur/
--       mcp-developpeur                        le connecteur MCP-Développeur (installé par install.sh)
--       Conversations/<id>/conversation.json   le fil, et les images que Claude a regardées
--       Sessions/<id>-<date>-<n>/              échanges avec un processus Claude Code (relais.sh), et
--                                              ses consignes (consignes.md, écrites à son lancement)
--       Atelier/                               dossier de travail de Claude Code (vide)
--       Temporaire/                            fichiers de passage (images collées, sorties de
--                                              commandes, vignettes du Suivi)
--       connecteur.json                        configuration MCP, écrite à chaque lancement
--       consommation.json, publication.json    jetons comptés, profils de publication de l'utilisateur
--       notation.json                          notes proposées par Claude
--       carnet.json                            carnet de progrès (Carnet.lua, 1.3), une table par
--                                              catalogue ; les leçons d'avant la 1.3.6 y restent
--       suivi.json                             relevé du Suivi (Releve.lua, 1.3.7) : les photos
--                                              ouvertes, par original, et leur analyse ; une table
--                                              par catalogue (suivi-illisible-<date>.json : un
--                                              relevé illisible mis de côté)
--       mes-demandes.json                      les demandes du menu Mes demandes de la fenêtre
--                                              (Stockage.lua)
--       Etapes/                                avant/après de chaque étape de Claude (1.3)
--   ~/Library/Logs/Developpeur/conversation.log   (à côté de module.log, le journal de la liaison)

local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'

local Preferences = require 'Preferences'

local Chemins = {}

function Chemins.home()
    return LrPathUtils.getStandardFilePath('home')
end

local function sous(...)
    local chemin = Chemins.home()
    for _, morceau in ipairs({ ... }) do
        chemin = LrPathUtils.child(chemin, morceau)
    end
    return chemin
end

function Chemins.racine() return sous('Library', 'Application Support', 'Developpeur') end
function Chemins.conversations() return LrPathUtils.child(Chemins.racine(), 'Conversations') end
function Chemins.sessions() return LrPathUtils.child(Chemins.racine(), 'Sessions') end
function Chemins.atelier() return LrPathUtils.child(Chemins.racine(), 'Atelier') end
function Chemins.configMCP() return LrPathUtils.child(Chemins.racine(), 'connecteur.json') end
function Chemins.temporaire() return LrPathUtils.child(Chemins.racine(), 'Temporaire') end
function Chemins.etapes() return LrPathUtils.child(Chemins.racine(), 'Etapes') end
function Chemins.journaux() return sous('Library', 'Logs', 'Developpeur') end
function Chemins.journal() return LrPathUtils.child(Chemins.journaux(), 'conversation.log') end

function Chemins.relais()
    return LrPathUtils.child(_PLUGIN.path, 'relais.sh')
end

function Chemins.ressource(nom)
    return LrPathUtils.child(_PLUGIN.path, nom)
end

-- Premier chemin existant d'une liste, sinon le premier.
local function premierExistant(liste)
    for _, chemin in ipairs(liste) do
        if LrFileUtils.exists(chemin) then
            return chemin
        end
    end
    return liste[1]
end

-- Où Claude Code s'installe : son installateur, Homebrew (Apple ou Intel).
function Chemins.claudesConnus()
    return { sous('.local', 'bin', 'claude'), '/opt/homebrew/bin/claude', '/usr/local/bin/claude' }
end

function Chemins.claudeParDefaut()
    return premierExistant(Chemins.claudesConnus())
end

-- Un chemin rangé par défaut (un des chemins connus) qui n'existe plus, ou pas encore : Claude
-- Code installé après le module, ailleurs que le premier chemin essayé. Un chemin choisi par
-- l'utilisateur ne se change pas.
local function claudeARecalculer(chemin)
    if chemin == nil or chemin == '' then
        return true
    end
    if LrFileUtils.exists(chemin) then
        return false
    end
    for _, connu in ipairs(Chemins.claudesConnus()) do
        if chemin == connu then
            return true
        end
    end
    return false
end

function Chemins.connecteurParDefaut()
    return sous('Library', 'Application Support', 'Developpeur', 'mcp-developpeur')
end

-- Réglages ------------------------------------------------------------------------------------

-- Les réglages de la fenêtre vont dans les préférences du module, avec ceux de la liaison
-- (Preferences.lua) : une seule table, sans clé commune. La fenêtre lit et bascule le mode
-- « Proposer d'abord » de la liaison (clé `mode`) dans cette même table. Autres clés de la
-- fenêtre : cheminClaude, cheminConnecteur, et pour la fenêtre Publication dossierPublication et
-- profilPublication.
Chemins.defauts = {
    -- Modèle et effort de Claude Code (Consignes.modeles, Consignes.efforts), choisis dans le
    -- Gestionnaire de modules externes ; l'effort vaut pour les quatre modèles.
    modele = 'opus',
    effort = 'max',
    -- Apparence de la fenêtre Claude (fenêtre B, 1.3 ; décision de Dany du 21 octobre 2026),
    -- choisie dans le Gestionnaire comme le modèle et l'effort : 'claire' (la maquette) ou
    -- 'sombre' (Dispositions.APPARENCES). Elle règle les aplats, les couleurs des textes et les
    -- images (Dispositions.couleurs, Dispositions.image) ; les contrôles natifs (boutons, champs,
    -- menus) suivent l'apparence de macOS. Une valeur inconnue retombe sur 'claire'
    -- (Dispositions.apparence).
    apparence = 'claire',
    -- Une autre photo active ou une autre sélection reprend sa conversation, sinon en commence une
    -- (case « Autre photo : reprendre sa conversation, sinon une nouvelle », Fenetre.suivreSelection ;
    -- une photo, une conversation depuis le correctif 1.3.6) ; la Demande rapide sur une photo seule
    -- écrit dans sa conversation (Moteur.envoyerRapide). Décochée : la conversation montrée reste,
    -- quelle que soit la sélection, et chaque demande rapide part dans une conversation jamais
    -- gardée. La clé garde son nom.
    nouvelleParPhoto = true,
    -- (La proposition préparée à l'ouverture de la fenêtre, `propositionAOuverture`, est retirée au
    -- correctif 1.3.6, décision de Dany du 25 octobre 2026 : « Obtenir » de l'onglet Proposition la
    -- demande. Une valeur restée dans les réglages de Lightroom n'est plus lue.)
    -- Style du menu Style (valeur de Consignes.styles), joint à chaque demande ; « standard »
    -- n'ajoute rien.
    styleChoisi = 'standard',
    -- Minutes sans demande avant de fermer Claude Code (il reprend la session à la demande suivante).
    inactivite = 15,
    -- Avant/après de chaque étape de Claude (1.3, Pourquoi ?) : un rendu de plus par étape, photo
    -- active seulement, gardé dans Etapes/.
    avantApresEtapes = true,
}

-- Préférences du module (liaison comprise), complétées par les réglages par défaut de la fenêtre.
function Chemins.prefs()
    local prefs = Preferences.lire()
    for cle, valeur in pairs(Chemins.defauts) do
        if prefs[cle] == nil then
            prefs[cle] = valeur
        end
    end
    if claudeARecalculer(prefs.cheminClaude) then
        prefs.cheminClaude = Chemins.claudeParDefaut()
    end
    if prefs.cheminConnecteur == nil or prefs.cheminConnecteur == '' then
        prefs.cheminConnecteur = Chemins.connecteurParDefaut()
    end
    return prefs
end

return Chemins
