-- Chemins.lua : dossiers et réglages de la fenêtre Claude.
--
-- Deux racines (dossier commun, demandé par Dany le 3 novembre 2026 : deux Mac, un SSD « Photos »
-- qui passe de l'un à l'autre, jamais les deux en même temps ; « que je travaille sur l'un ou
-- l'autre, tout est pareil ») :
--   - la racine LOCALE, ~/Library/Application Support/Developpeur/ (Chemins.locale, Chemins.racine) ;
--   - la racine DES DONNÉES (Chemins.donnees) : le dossier commun s'il est réglé, sinon la racine
--     locale. Le pointeur local dossier-commun.json ({"format":1,"dossier":"<chemin absolu>"}),
--     écrit seulement par le réglage du Gestionnaire de modules externes (DossierCommun.lua), est
--     relu à chaque accès : rien n'en est gardé en mémoire. Réglé mais absent (SSD débranché) : tout
--     accès aux données est refusé (Chemins.messageAbsent), jamais de repli sur la racine locale
--     (deux versions divergeraient).
--
--   Racine locale (toujours sur ce Mac) :
--       mcp-developpeur                        le connecteur MCP-Développeur (installé par install.sh)
--       liaison.jeton, liaison.jeton.nouveau   le jeton privé de la liaison
--       dossier-commun.json                    le pointeur vers le dossier commun (absent : aucun)
--       Sessions/<id>-<date>-<n>/              échanges avec un processus Claude Code (relais.sh), et
--                                              ses consignes (consignes.md, écrites à son lancement)
--       Atelier/                               dossier de travail de Claude Code (vide)
--       Temporaire/                            fichiers de passage (images collées, sorties de
--                                              commandes, vignettes du Suivi)
--       connecteur.json                        configuration MCP, écrite à chaque lancement
--       Avant le dossier commun <date>/        les données de ce Mac mises de côté quand le dossier
--                                              commun a été choisi (jamais effacées)
--   Racine des données (Chemins.NOMS_DONNEES ; le dossier commun quand il est réglé) :
--       Conversations/<id>/conversation.json   le fil, et les images que Claude a regardées
--       Claude Code/<session>.jsonl            les échanges des sessions Claude Code de la fenêtre,
--                                              copiés par relais.sh (reprise sur l'autre Mac)
--       guide-de-style.md, rendus.json, Index/, Modeles/   tenus par le serveur
--       consommation.json, publication.json    jetons comptés, profils de publication de l'utilisateur
--       notation.json                          notes proposées par Claude
--       carnet.json                            carnet de progrès (Carnet.lua, 1.3), une table par
--                                              catalogue ; les leçons d'avant la 1.3.6 y restent
--       suivi.json                             relevé du Suivi (Releve.lua, 1.3.7) : les photos
--                                              ouvertes, par original, et leur analyse ; une table
--                                              par catalogue (suivi-illisible-<date>.json : un
--                                              relevé illisible mis de côté ; suivi.journal : les
--                                              entrées changées depuis, rejouées à la relecture)
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

-- La racine locale (ce Mac) ; Chemins.racine en garde le nom d'avant le dossier commun.
function Chemins.locale() return sous('Library', 'Application Support', 'Developpeur') end
function Chemins.racine() return Chemins.locale() end
function Chemins.sessions() return LrPathUtils.child(Chemins.locale(), 'Sessions') end
function Chemins.atelier() return LrPathUtils.child(Chemins.locale(), 'Atelier') end
function Chemins.configMCP() return LrPathUtils.child(Chemins.locale(), 'connecteur.json') end
function Chemins.temporaire() return LrPathUtils.child(Chemins.locale(), 'Temporaire') end

-- Dossier commun -------------------------------------------------------------------------------

-- Ce qui va dans la racine des données (le dossier commun quand il est réglé) ; tout le reste de la
-- racine locale y reste. Le serveur tient la même liste (guide de style, rendus, Index, Modeles).
Chemins.NOMS_DONNEES = {
    'guide-de-style.md', 'Conversations', 'suivi.json', 'suivi.journal', 'carnet.json', 'notation.json',
    'mes-demandes.json', 'publication.json', 'consommation.json', 'rendus.json', 'Etapes', 'Index', 'Modeles',
    'Claude Code',
}
-- Les copies illisibles mises de côté, rangées avec leur fichier.
Chemins.MOTIFS_DONNEES = { '^suivi%-illisible%-.+%.json$', '^carnet%-illisible%-', '^mes%-demandes%-illisible%-' }

local nomsDonnees = {}
for _, nom in ipairs(Chemins.NOMS_DONNEES) do
    nomsDonnees[nom] = true
end

-- Vrai si `nom` (un nom de fichier ou de dossier de la racine) est une donnée du dossier commun.
function Chemins.estDonnee(nom)
    if type(nom) ~= 'string' or nom == '' then
        return false
    end
    if nomsDonnees[nom] then
        return true
    end
    for _, motif in ipairs(Chemins.MOTIFS_DONNEES) do
        if nom:find(motif) then
            return true
        end
    end
    return false
end

-- Le pointeur, toujours local ; seul DossierCommun.lua l'écrit.
function Chemins.pointeur() return LrPathUtils.child(Chemins.locale(), 'dossier-commun.json') end

-- L'état du dossier commun, relu à chaque appel : { regle, chemin, present }. Pointeur absent,
-- illisible ou sans « dossier » non vide : regle = false (la racine locale sert).
function Chemins.dossierCommun()
    local f = io.open(Chemins.pointeur(), 'rb')
    if not f then
        return { regle = false, present = false }
    end
    local texte = f:read('*a')
    f:close()
    local ok, t = pcall(function() return require('Json').decode(texte or '') end)
    local dossier = ok and type(t) == 'table' and t.dossier or nil
    if type(dossier) ~= 'string' or not dossier:find('%S') then
        return { regle = false, present = false }
    end
    if #dossier > 1 then
        dossier = dossier:gsub('/+$', '')
    end
    return { regle = true, chemin = dossier, present = LrFileUtils.exists(dossier) == 'directory' }
end

-- Le refus quand le dossier commun réglé est introuvable.
function Chemins.messageAbsent(chemin)
    return string.format("Le dossier commun (%s) est introuvable : branchez le SSD qui le contient, ou réglez un autre dossier "
        .. "dans Fichier › Gestionnaire de modules externes › Développeur IA pour Lightroom.", tostring(chemin))
end

-- Le refus (texte) si les données ne sont pas accessibles, sinon nil.
function Chemins.refusDonnees()
    local commun = Chemins.dossierCommun()
    if commun.regle and not commun.present then
        return Chemins.messageAbsent(commun.chemin)
    end
    return nil
end

-- La racine des données : le dossier commun s'il est réglé, sinon la racine locale. Réglé mais
-- introuvable : une erreur (Chemins.messageAbsent), jamais la racine locale à sa place.
function Chemins.donnees()
    local commun = Chemins.dossierCommun()
    if not commun.regle then
        return Chemins.locale()
    end
    if not commun.present then
        error(Chemins.messageAbsent(commun.chemin), 0)
    end
    return commun.chemin
end

-- Un fichier ou un dossier de la racine des données.
function Chemins.donnee(nom) return LrPathUtils.child(Chemins.donnees(), nom) end
function Chemins.conversations() return Chemins.donnee('Conversations') end
function Chemins.etapes() return Chemins.donnee('Etapes') end
function Chemins.claudeCode() return Chemins.donnee('Claude Code') end

-- Un chemin absolu rangé dans un fichier de données (écrit sur ce Mac ou sur l'autre, avant ou après
-- le dossier commun) : « …/Library/Application Support/Developpeur/<donnée>/… » se lit dans la racine
-- des données actuelle (le nom d'utilisateur peut différer d'un Mac à l'autre). Tout autre chemin,
-- ou des données inaccessibles : rendu tel quel. La seule fonction de rebasage.
local MARQUE = '/Library/Application Support/Developpeur/'
function Chemins.rebaser(chemin)
    if type(chemin) ~= 'string' then
        return chemin
    end
    local debut, fin = chemin:find(MARQUE, 1, true)
    if not debut then
        return chemin
    end
    local reste = chemin:sub(fin + 1)
    if not Chemins.estDonnee(reste:match('^[^/]+')) then
        return chemin
    end
    local ok, racine = pcall(Chemins.donnees)
    if not ok then
        return chemin
    end
    return LrPathUtils.child(racine, reste)
end

-- Avant d'ouvrir une fenêtre qui lit ou écrit les données : si elles ne sont pas accessibles, le
-- refus est montré et la fonction rend faux ; sinon vrai.
function Chemins.verifierDonnees(titre)
    local refus = Chemins.refusDonnees()
    if not refus then
        return true
    end
    import('LrDialogs').message(titre or "Dossier commun introuvable", refus, 'warning')
    return false
end
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
