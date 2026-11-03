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
-- de Fibo d'un appel de generative_edit que Lightroom a quitté en cours). Jamais les
-- conversations gardées (Conversations/, hors de Temporaire). Dans une tâche (Init.lua).
-- Depuis le chantier « ménage » (après la 1.6.3) : aussi les vignettes de la fenêtre Claude
-- (Temporaire/PhotoActive : la photo active, sa grande image et celle de Focus, un dossier par
-- séance, Fenetre.lua, qui s'accumulaient sans fin : 137 Mo chez Dany), les copies des étapes de
-- l'onglet Aperçu (Temporaire/Pourquoi, vidé aussi à chaque ouverture de la fenêtre), les images
-- collées par 📋 (Temporaire/Collees : Moteur.envoyer les copie dans la conversation) et les
-- fichiers de passage laissés à la racine de Temporaire (Menage.FICHIERS) par une commande
-- interrompue. Au chargement, aucune fenêtre n'est ouverte ; par prudence, rien ne s'efface si
-- l'une l'est déjà ou que Claude travaille (Menage.occupe). Tout dossier créé sous Temporaire est
-- dans Menage.TEMPORAIRES, ou dans Menage.GARDES avec sa raison (essais-menage.lua le vérifie en
-- parcourant le code du module).
Menage.TEMPORAIRES = { 'Groupes', 'Rapide', 'Suivi', 'Fibo', 'PhotoActive', 'Pourquoi', 'Collees' }

-- Ce que le ménage laisse dans Temporaire, chaque nom avec sa raison (dossiers et fichiers écrits
-- par le module ou par le connecteur MCP-Développeur).
Menage.GARDES = {
    ['fibo-en-cours.verrou'] = "verrou de generative_edit (Tools+Generatif.swift, flock) : un serveur peut le tenir "
        .. "pendant que le module se charge ; vide, il ne grossit pas",
    ['Mises a jour'] = "dossier de travail des mises à jour par le SSD (Installation.swift, MisesAJour.lua) : un dépôt lancé "
        .. "avant le rechargement peut encore tourner (le connecteur survit à Lightroom) ; chacun vide ce qu'il y met",
    ['mises-a-jour.verrou'] = "verrou des mises à jour par le SSD (Installation.swift, flock) : un connecteur peut le tenir ; "
        .. "vide, il ne grossit pas",
}

-- Les débuts de nom des fichiers de passage écrits à la racine de Temporaire, chacun effacé juste
-- après sa lecture : sortie de sips (Images.dimensions), de --version (Composants.connecteur), de
-- `claude auth status` (Lightroom.etatClaude), du presse-papiers (Images.coller) et de --focus sans
-- vignette (Images.lireFocus). Une commande interrompue (Lightroom quitté, module rechargé) les
-- laisse : ils s'effacent au chargement.
Menage.FICHIERS = { 'dimensions-', 'version-', 'auth-', 'presse-papiers-', 'focus-' }

-- Les fenêtres du module se signalent ici à leur premier chargement (Fenetre.lua, FenetreRapide.lua) :
-- chacune donne une fonction, vraie tant qu'elle est ouverte ou que son Claude travaille. Au
-- chargement du module, aucune n'est encore chargée : la liste est vide.
Menage.occupants = {}

function Menage.signaler(occupe)
    Menage.occupants[#Menage.occupants + 1] = occupe
end

-- Vrai si une fenêtre du module est ouverte ou que Claude travaille : ses fichiers de passage sont
-- peut-être en usage.
function Menage.occupe()
    for _, occupe in ipairs(Menage.occupants) do
        local ok, oui = pcall(occupe)
        if ok and oui then
            return true
        end
    end
    return false
end

local function fichierDePassage(nom)
    for _, debut in ipairs(Menage.FICHIERS) do
        if nom:sub(1, #debut) == debut then
            return true
        end
    end
    return false
end

-- Rend le nombre de dossiers et de fichiers effacés.
function Menage.temporaires()
    if Menage.occupe() then
        return 0
    end
    local Chemins = require 'Chemins'
    local temporaire = Chemins.temporaire()
    local effaces = 0
    for _, nom in ipairs(Menage.TEMPORAIRES) do
        local dossier = LrPathUtils.child(temporaire, nom)
        if LrFileUtils.exists(dossier) then
            LrFileUtils.delete(dossier)
            effaces = effaces + 1
        end
    end
    if LrFileUtils.exists(temporaire) == 'directory' then
        local aEffacer = {}
        for chemin in LrFileUtils.directoryEntries(temporaire) do
            local nom = LrPathUtils.leafName(chemin)
            if LrFileUtils.exists(chemin) == 'file' and not Menage.GARDES[nom] and fichierDePassage(nom) then
                aEffacer[#aEffacer + 1] = chemin
            end
        end
        for _, chemin in ipairs(aEffacer) do
            LrFileUtils.delete(chemin)
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
