-- PluginInfoProvider.lua : le module « Développeur » dans le Gestionnaire de modules externes,
-- une section par sujet :
--   - la liaison avec Claude : état, boutons, mode « Proposer d'abord », réglages, garde-fous et
--     diagnostic ;
--   - la fenêtre Claude : chemins de Claude Code et du connecteur MCP-Développeur, taille et
--     disposition de la fenêtre, fermeture de Claude Code après inactivité, raccourci clavier,
--     dossiers.
-- Les deux sections lisent et écrivent les mêmes préférences du module (Preferences.lua,
-- Chemins.prefs).

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrPathUtils = import 'LrPathUtils'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Liaison = require 'Liaison'

-- Le diagnostic à coller dans la conversation : versions, ports, liaison, dernier échange, dernière
-- erreur, réglages, chemins de la fenêtre Claude, journal.
local function diagnostic()
    local prefs = Chemins.prefs()
    local lignes = {
        "Développeur " .. Liaison.VERSION .. " · Lightroom Classic " .. tostring(LrApplication.versionString()),
        string.format("Ports : %d (commandes) et %d (réponses)", Liaison.PORT_COMMANDES, Liaison.PORT_REPONSES),
        "État : " .. Liaison.texteEtat(),
        "Dernier échange : " .. (Liaison.dernierEchange and LrDate.timeToUserFormat(Liaison.dernierEchange, '%Y-%m-%d %H:%M:%S') or "aucun"),
        "Dernière erreur : " .. tostring(Liaison.erreur or "aucune"),
        string.format("Mode : %s ; accord dans Lightroom : %s ; copies virtuelles seulement : %s ; libellé protégé : %s ; rejetées protégées : %s ; plafond : %s photos ; retour visuel : %s",
            tostring(prefs.mode), tostring(prefs.accordDansLightroom), tostring(prefs.copiesSeulement), tostring(prefs.libelleProtege),
            tostring(prefs.rejeteesProtegees), tostring(prefs.plafondPhotos), tostring(prefs.retourVisuel)),
        string.format("Fenêtre Claude : Claude Code %s ; connecteur %s ; modèle %s ; disposition %s, taille %s",
            tostring(prefs.cheminClaude), tostring(prefs.cheminConnecteur), tostring(prefs.modele),
            tostring(prefs.disposition), tostring(prefs.taille)),
        "Journaux : " .. select(2, Liaison.cheminJournal()) .. " et " .. Chemins.journal(),
        "",
        "Derniers événements :",
    }
    for i = math.max(1, #Liaison.journal - 11), #Liaison.journal do
        lignes[#lignes + 1] = Liaison.journal[i]
    end
    return table.concat(lignes, "\n")
end

-- Montre le diagnostic dans un champ que l'on peut sélectionner et copier (le SDK n'écrit pas dans
-- le presse-papiers).
local function afficherDiagnostic()
    local f = LrView.osFactory()
    LrDialogs.presentModalDialog {
        title = "Diagnostic de Développeur",
        contents = f:column {
            f:static_text { title = "Sélectionner le texte (⌘A), le copier (⌘C), puis le coller dans la conversation avec Claude." },
            f:edit_field { value = diagnostic(), height_in_lines = 18, width_in_chars = 90 },
        },
        cancelVerb = '< exclude >',
        actionVerb = "Fermer",
    }
end

local function choisirFichier(prefs, cle, titre)
    local choix = LrDialogs.runOpenPanel {
        title = titre,
        canChooseFiles = true,
        canChooseDirectories = false,
        allowsMultipleSelection = false,
        initialDirectory = LrPathUtils.parent(prefs[cle] or Chemins.home()),
    }
    if choix and choix[1] then
        prefs[cle] = choix[1]
    end
end

-- Section de la liaison avec le serveur ----------------------------------------------------------

local function sectionLiaison(f, propertyTable, prefs, ligne)
    local bind = LrView.bind

    propertyTable.etat = Liaison.texteEtat()
    local function rafraichir()
        propertyTable.etat = Liaison.texteEtat()
    end

    return {
        title = "Liaison avec Claude",
        synopsis = bind { key = 'etat', bind_to_object = propertyTable },

        ligne("État :", f:static_text {
            title = bind { key = 'etat', bind_to_object = propertyTable },
            fill_horizontal = 1,
        }),
        ligne("Ports :", f:static_text {
            title = string.format("%d (commandes) et %d (réponses), sur cet ordinateur seulement",
                Liaison.PORT_COMMANDES, Liaison.PORT_REPONSES),
        }),
        ligne("", f:row {
            f:push_button { title = "Démarrer la liaison", action = function() Liaison.demarrer(); rafraichir() end },
            f:push_button { title = "Arrêter la liaison", action = function() Liaison.arreter(); rafraichir() end },
            f:push_button { title = "Fenêtre de suivi", action = function() require('Suivi').afficher() end },
        }),

        f:separator { fill_horizontal = 1 },

        ligne("Au lancement :", f:checkbox {
            title = "Démarrer la liaison avec Lightroom",
            value = bind { key = 'demarrerAuLancement', bind_to_object = prefs },
        }),
        ligne("Avant d'appliquer :", f:popup_menu {
            items = {
                { title = "Appliquer directement", value = 'appliquer' },
                { title = "Proposer d'abord (Claude attend votre accord)", value = 'proposer' },
            },
            value = bind { key = 'mode', bind_to_object = prefs },
        }),
        ligne("Instantané :", f:checkbox {
            title = "Créer l'instantané « Avant Claude » à la première retouche",
            value = bind { key = 'instantane', bind_to_object = prefs },
        }),
        ligne("Exposition :", f:row {
            f:edit_field {
                value = bind { key = 'variationExpositionMax', bind_to_object = prefs },
                min = 0.1, max = 5, precision = 1, width_in_digits = 4,
            },
            f:static_text { title = "IL de variation au plus, par retouche" },
        }),
        ligne("Saturation :", f:row {
            f:edit_field {
                value = bind { key = 'saturationMax', bind_to_object = prefs },
                min = 0, max = 100, precision = 0, width_in_digits = 4,
            },
            f:static_text { title = "au plus, en plus ou en moins" },
        }),
        ligne("Accord :", f:checkbox {
            title = "En mode « Proposer d'abord », l'accord se donne ici (fenêtre de suivi, bouton Accepter)",
            value = bind { key = 'accordDansLightroom', bind_to_object = prefs },
        }),
        ligne("Retour visuel :", f:checkbox {
            title = "Afficher un message bref à chaque retouche de Claude",
            value = bind { key = 'retourVisuel', bind_to_object = prefs },
        }),

        f:separator { fill_horizontal = 1 },

        ligne("Garde-fous :", f:checkbox {
            title = "Copies virtuelles seulement : Claude ne retouche aucun original",
            value = bind { key = 'copiesSeulement', bind_to_object = prefs },
        }),
        ligne("Libellé protégé :", f:popup_menu {
            items = {
                { title = "Aucun", value = 'aucun' }, { title = "Rouge", value = 'rouge' }, { title = "Jaune", value = 'jaune' },
                { title = "Vert", value = 'vert' }, { title = "Bleu", value = 'bleu' }, { title = "Violet", value = 'violet' },
            },
            value = bind { key = 'libelleProtege', bind_to_object = prefs },
        }),
        ligne("", f:checkbox {
            title = "Protéger aussi les photos rejetées",
            value = bind { key = 'rejeteesProtegees', bind_to_object = prefs },
        }),
        ligne("Plafond :", f:row {
            f:edit_field {
                value = bind { key = 'plafondPhotos', bind_to_object = prefs },
                min = 0, max = 500, precision = 0, width_in_digits = 4,
            },
            f:static_text { title = "photos au plus par retouche sans accord explicite (0 : sans plafond)" },
        }),

        f:separator { fill_horizontal = 1 },

        ligne("Diagnostic :", f:row {
            f:push_button { title = "Afficher le diagnostic", action = function() afficherDiagnostic() end },
            f:push_button { title = "Ouvrir le journal", action = function()
                local _, chemin = Liaison.cheminJournal()
                LrShell.revealInShell(chemin)
            end },
        }),
        ligne("", f:static_text {
            title = "Le connecteur MCP-Développeur (mcp-developpeur) doit être installé et inscrit dans Claude Desktop et Claude Code (voir le dépôt Developpeur).",
            fill_horizontal = 1,
        }),
    }
end

-- Section de la fenêtre Claude -------------------------------------------------------------------

local function sectionFenetre(f, prefs, ligne)
    local bind = LrView.bind

    return {
        title = "Fenêtre Claude",
        synopsis = "Version " .. require('Composants').module(),
        bind_to_object = prefs,

        f:static_text {
            title = "La fenêtre « Claude » : Fichier › Module externe - Extras › Ouvrir la fenêtre Claude. Claude Code travaille avec votre forfait claude.ai (jamais de clé d'API) et le connecteur MCP-Développeur.",
            width_in_chars = 80, height_in_lines = 2,
        },
        ligne("Claude Code :",
            f:edit_field { value = bind 'cheminClaude', width_in_chars = 48 },
            f:push_button { title = "Choisir…", action = function() choisirFichier(prefs, 'cheminClaude', "Choisir l'exécutable claude") end }),
        ligne("Connecteur MCP :",
            f:edit_field { value = bind 'cheminConnecteur', width_in_chars = 48 },
            f:push_button { title = "Choisir…", action = function() choisirFichier(prefs, 'cheminConnecteur', "Choisir l'exécutable mcp-developpeur") end }),
        ligne("Taille de la fenêtre :",
            f:popup_menu { value = bind 'taille', items = {
                { title = "Petite (portable 13 pouces)", value = 'petite' },
                { title = "Moyenne", value = 'moyenne' },
                { title = "Grande (grand écran)", value = 'grande' },
            } },
            f:static_text { title = "prise en compte à la prochaine ouverture de la fenêtre" }),
        ligne("Disposition :",
            f:popup_menu { value = bind 'disposition', items = Dispositions.items() },
            f:static_text { title = "aussi par le menu Disposition de la fenêtre Claude" }),
        ligne("Fermer Claude Code après :",
            f:popup_menu { value = bind 'inactivite', items = {
                { title = "5 minutes sans demande", value = 5 },
                { title = "15 minutes sans demande", value = 15 },
                { title = "1 heure sans demande", value = 60 },
            } },
            f:static_text { title = "la conversation reprend à la demande suivante" }),
        ligne("",
            f:push_button { title = "Ouvrir la fenêtre Claude", action = function() require('Fenetre').afficher() end }),
        ligne("Raccourci clavier :",
            f:push_button { title = "Poser le raccourci", action = function()
                LrTasks.startAsyncTask(function()
                    local Raccourcis = require 'Raccourcis'
                    if Raccourcis.poser() then
                        LrDialogs.message("Raccourci clavier posé", Raccourcis.texte()
                            .. ".\n\nIl s'affiche à côté de Fichier › Module externe - Extras › Ouvrir la fenêtre Claude ; sinon, relancez Lightroom. Il sert quand la fenêtre principale de Lightroom est devant.", 'info')
                    else
                        LrDialogs.message("Raccourci non posé", "macOS n'a pas enregistré le raccourci.", 'warning')
                    end
                end)
            end },
            f:static_text { title = require('Raccourcis').texte() }),
        ligne("",
            f:push_button { title = "Afficher les conversations dans le Finder", action = function()
                Fichiers.creerDossier(Chemins.conversations())
                LrShell.revealInShell(Chemins.conversations())
            end },
            f:push_button { title = "Afficher le journal", action = function()
                if Fichiers.existe(Chemins.journal()) then
                    LrShell.revealInShell(Chemins.journal())
                else
                    LrDialogs.message("Journal", "Pas encore de journal (" .. Chemins.journal() .. ").", 'info')
                end
            end }),
    }
end

local function sectionsForTopOfDialog(f, propertyTable)
    local prefs = Chemins.prefs()
    local share = LrView.share

    local function ligne(etiquette, ...)
        local r = { f:static_text { title = etiquette, alignment = 'right', width = share 'etiquette' } }
        for _, v in ipairs({ ... }) do
            r[#r + 1] = v
        end
        return f:row(r)
    end

    return {
        sectionLiaison(f, propertyTable, prefs, ligne),
        sectionFenetre(f, prefs, ligne),
    }
end

return {
    sectionsForTopOfDialog = sectionsForTopOfDialog,
    diagnostic = diagnostic,
}
