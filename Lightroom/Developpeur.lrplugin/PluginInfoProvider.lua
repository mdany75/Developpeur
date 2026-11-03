-- PluginInfoProvider.lua : le module « Développeur » dans le Gestionnaire de modules externes,
-- une section par sujet :
--   - la liaison avec Claude : état, boutons, mode « Proposer d'abord », réglages (dont le carnet de
--     progrès, 1.3), garde-fous et diagnostic ;
--   - la fenêtre Claude : chemins de Claude Code et du connecteur MCP-Développeur, modèle, effort,
--     apparence (claire ou sombre, 1.3), la conversation de chaque photo (Autre photo : reprendre
--     sa conversation, sinon une nouvelle, correctif 1.3.6), avant/après de chaque étape (1.3),
--     fermeture de Claude Code après inactivité, raccourci clavier, dossiers. (Les cases Leçon et
--     « À l'ouverture » sont retirées au correctif 1.3.6, avec la leçon et la proposition préparée à
--     l'ouverture de la fenêtre.)
--   - le dossier commun (3 novembre 2026) : chemin, Choisir…, Revenir au dossier de ce Mac
--     (DossierCommun.lua, qui seul écrit le pointeur dossier-commun.json) ;
--   - les mises à jour par le SSD (1.7) : état, Vérifier, Installer depuis le SSD, Déposer sur le
--     SSD (MisesAJour.lua ; le travail est fait par le connecteur, --mises-a-jour).
-- Les deux premières sections lisent et écrivent les mêmes préférences du module (Preferences.lua,
-- Chemins.prefs).

local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Liaison = require 'Liaison'

-- Photos au carnet de progrès du catalogue ouvert, en mots (« ? » s'il ne se lit pas). pcall
-- simple : le diagnostic s'ouvre depuis l'action d'un bouton, peut-être hors d'une tâche (à
-- constater), et la lecture (carnet.json, chemin du catalogue) n'a pas à attendre ; au pire, « ? ».
local function photosAuCarnet()
    local ok, n = pcall(function() return require('Carnet').nombre() end)
    if not ok or type(n) ~= 'number' then
        return "?"
    end
    return string.format("%d photo%s", n, n > 1 and "s" or "")
end

-- L'apparence de la fenêtre Claude, telle qu'elle sert (Dispositions.apparence) ; une préférence
-- inconnue est dite à côté de la valeur sur laquelle elle retombe.
local function apparence(valeur)
    local retenue = Dispositions.apparence(valeur)
    if valeur == nil or valeur == retenue then
        return retenue
    end
    return string.format("%s (préférence « %s » inconnue)", retenue, tostring(valeur))
end

-- DossierCommun.lua, nouveau avec le dossier commun : après « Charger de nouveau le module ext. »
-- sans relancer Lightroom, il ne se charge pas (« Could not load toolkit script », piège de
-- CLAUDE.md). Pris par pcall : les autres sections et le diagnostic restent, la section du dossier
-- commun le dit.
local RELANCER = "Quittez et relancez Lightroom pour régler le dossier commun (un fichier nouveau du module ne se charge qu'au lancement)."

local function moduleDossierCommun()
    local ok, m = pcall(require, 'DossierCommun')
    if ok and type(m) == 'table' then
        return m
    end
    return nil
end

local function texteEtatDossierCommun()
    local DossierCommun = moduleDossierCommun()
    if not DossierCommun then
        return "réglage indisponible : " .. RELANCER
    end
    local ok, texte = pcall(DossierCommun.texteEtat)
    return ok and texte or tostring(texte)
end

-- Le diagnostic à coller dans la conversation : versions, ports, liaison, dernier échange, dernière
-- erreur, réglages, chemins de la fenêtre Claude, journal. Les réglages de la 1.3 sont au bout de
-- leur ligne : les débuts de ligne lus par les essais ne changent pas.
local function diagnostic()
    local prefs = Chemins.prefs()
    local lignes = {
        "Développeur IA pour Lightroom " .. Liaison.VERSION .. " · Lightroom Classic " .. tostring(LrApplication.versionString()),
        string.format("Ports : %d (commandes) et %d (réponses)", Liaison.PORT_COMMANDES, Liaison.PORT_REPONSES),
        -- L'état du jeton, jamais sa valeur.
        string.format("Jeton : %s (%s) ; commandes refusées : %d", Liaison.jeton and "présent" or "absent",
            select(2, Liaison.cheminJeton()), Liaison.refus or 0),
        "État : " .. Liaison.texteEtat(),
        "Dernier échange : " .. (Liaison.dernierEchange and LrDate.timeToUserFormat(Liaison.dernierEchange, '%Y-%m-%d %H:%M:%S') or "aucun"),
        "Dernière erreur : " .. tostring(Liaison.erreur or "aucune"),
        string.format("Mode : %s ; accord dans Lightroom : %s ; copies virtuelles seulement : %s ; libellé protégé : %s ; rejetées protégées : %s ; plafond : %s photos ; retour visuel : %s",
            tostring(prefs.mode), tostring(prefs.accordDansLightroom), tostring(prefs.copiesSeulement), tostring(prefs.libelleProtege),
            tostring(prefs.rejeteesProtegees), tostring(prefs.plafondPhotos), tostring(prefs.retourVisuel)) .. " ; point de mise au point en tout temps : " .. tostring(prefs.pointMiseAuPoint)
            .. " ; carnet de progrès : " .. tostring(prefs.carnet) .. " (" .. photosAuCarnet() .. ")",
        string.format("Fenêtre Claude : Claude Code %s ; connecteur %s ; modèle %s, effort %s ; autre photo, reprendre sa conversation, sinon une nouvelle : %s",
            tostring(prefs.cheminClaude), tostring(prefs.cheminConnecteur), tostring(prefs.modele), tostring(prefs.effort),
            tostring(prefs.nouvelleParPhoto)) .. " ; avant/après des étapes : " .. tostring(prefs.avantApresEtapes)
            .. " ; apparence : " .. apparence(prefs.apparence),
        "Journaux : " .. select(2, Liaison.cheminJournal()) .. " et " .. Chemins.journal(),
        "Dossier commun : " .. texteEtatDossierCommun(),
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
        title = "Diagnostic de Développeur IA pour Lightroom",
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
            f:push_button { title = "Fenêtre de la liaison", action = function() require('Suivi').afficher() end },
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
            title = "En mode « Proposer d'abord », l'accord se donne ici (fenêtre de la liaison, bouton Accepter)",
            value = bind { key = 'accordDansLightroom', bind_to_object = prefs },
        }),
        ligne("Retour visuel :", f:checkbox {
            title = "Afficher un message bref à chaque retouche de Claude",
            value = bind { key = 'retourVisuel', bind_to_object = prefs },
        }),
        ligne("Mise au point :", f:checkbox {
            title = "Montrer le carré de mise au point (Fujifilm) sur chaque aperçu",
            value = bind { key = 'pointMiseAuPoint', bind_to_object = prefs },
        }),
        ligne("Carnet :", f:checkbox {
            title = "Carnet de progrès : noter les défauts vus à la prise de vue, avant la première retouche de Claude",
            value = bind { key = 'carnet', bind_to_object = prefs },
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
            title = "La fenêtre Claude (« Développeur IA » dans sa barre de titre) : Fichier › Module externe - Extras › Ouvrir la fenêtre Claude. Claude Code travaille avec votre forfait claude.ai (jamais de clé d'API) et le connecteur MCP-Développeur.",
            width_in_chars = 66, height_in_lines = 3,
        },
        ligne("Claude Code :",
            f:edit_field { value = bind 'cheminClaude', width_in_chars = 48 },
            f:push_button { title = "Choisir…", action = function() choisirFichier(prefs, 'cheminClaude', "Choisir l'exécutable claude") end }),
        ligne("Connecteur MCP :",
            f:edit_field { value = bind 'cheminConnecteur', width_in_chars = 48 },
            f:push_button { title = "Choisir…", action = function() choisirFichier(prefs, 'cheminConnecteur', "Choisir l'exécutable mcp-developpeur") end }),
        ligne("Modèle :",
            f:popup_menu { value = bind 'modele', items = Consignes.itemsModeles() },
            f:static_text { title = "pour la demande suivante" }),
        ligne("Effort :",
            f:popup_menu { value = bind 'effort', items = Consignes.itemsEfforts() },
            f:static_text { title = "le même pour les quatre modèles" }),
        -- Les fonds, les textes et les images de la fenêtre ; les boutons, les champs et les menus
        -- suivent l'apparence de macOS (Dispositions.APPARENCES).
        ligne("Apparence :",
            f:popup_menu { value = bind 'apparence', items = Dispositions.itemsApparences() },
            f:static_text { title = "de la fenêtre Claude, à sa prochaine ouverture ; boutons et champs suivent macOS" }),
        -- Une photo, une conversation (correctif 1.3.6) : la photo choisie montre la sienne, ou une
        -- neuve, et la Demande rapide sur une photo seule écrit dans la sienne ; décochée, la
        -- conversation montrée reste, quelle que soit la sélection, et chaque demande rapide part
        -- dans une conversation jamais gardée.
        ligne("Autre photo :",
            f:checkbox { value = bind 'nouvelleParPhoto',
                title = "Reprendre sa conversation, sinon une nouvelle" }),
        ligne("Avant/après :",
            f:checkbox { value = bind 'avantApresEtapes',
                title = "Garder l'avant/après de chaque étape de Claude (un rendu de plus par étape, photo active seulement)" }),

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
                -- Dossier commun introuvable : dit, rien n'est créé ailleurs.
                if not Chemins.verifierDonnees("Conversations") then
                    return
                end
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

-- Section du dossier commun ------------------------------------------------------------------------

-- Les fenêtres qui lisent ou écrivent les données, ouvertes : le dossier ne change pas sous elles.
local function fenetresOuvertes()
    local ouvertes = {}
    for _, f in ipairs({ { 'Fenetre', "la fenêtre Claude" }, { 'FenetreRapide', "la Demande rapide" },
        { 'FenetreSuivi', "la fenêtre Suivi" }, { 'FenetrePublication', "la fenêtre Publication" },
        { 'FenetreConsommation', "la fenêtre Consommation" } }) do
        local ok, m = pcall(require, f[1])
        if ok and type(m) == 'table' and m.ouverte then
            ouvertes[#ouvertes + 1] = f[2]
        end
    end
    return ouvertes
end

-- Le refus d'un changement de dossier pendant qu'un autre est en cours, que Claude travaille ou
-- qu'une fenêtre est ouverte.
local function refusChangement(DossierCommun)
    if DossierCommun.enCours then
        return DossierCommun.EN_COURS
    end
    local okM, Moteur = pcall(require, 'Moteur')
    if okM and Moteur.travaille then
        return "Claude travaille : réessayez quand il a fini."
    end
    local ouvertes = fenetresOuvertes()
    if #ouvertes > 0 then
        return "Fermez d'abord " .. table.concat(ouvertes, ", ") .. "."
    end
    return nil
end

-- La progression de la copie, au premier plan (le Gestionnaire, modal, cacherait la barre de la
-- fenêtre principale et sa croix) : LrDialogs.showModalProgressDialog, sinon la barre d'activité
-- (LrProgressScope). Les deux ont setPortionComplete, setCaption, isCanceled et done.
local function progressionDeLaCopie(context)
    local titre = "Dossier commun : copie des données"
    if type(LrDialogs.showModalProgressDialog) == 'function' then
        local ok, d = pcall(LrDialogs.showModalProgressDialog, { title = titre, caption = "Préparation de la copie…",
            cannotCancel = false, functionContext = context })
        if ok and d then
            return d
        end
    end
    local barre = LrProgressScope { title = titre, functionContext = context }
    barre:setCancelable(true)
    return barre
end

-- Choisir… : le dossier (le choix s'ouvre sur le SSD Photos ; sa racine donne son dossier
-- « Développeur IA »), puis la copie avec sa progression (une tâche à part, comme choisirDossier).
local function choisirDossierCommun(propertyTable)
    local DossierCommun = moduleDossierCommun()
    if not DossierCommun then
        LrDialogs.message("Dossier commun", RELANCER, 'info')
        return
    end
    local refus = refusChangement(DossierCommun)
    if refus then
        LrDialogs.message("Dossier commun", refus, 'info')
        return
    end
    local choix = LrDialogs.runOpenPanel {
        title = "Choisir le dossier commun : le SSD Photos (« " .. DossierCommun.NOM .. " » y sera créé), ou un dossier",
        prompt = "Choisir",
        canChooseFiles = false,
        canChooseDirectories = true,
        canCreateDirectories = true,
        allowsMultipleSelection = false,
        initialDirectory = DossierCommun.dossierInitial(),
    }
    local dossier = choix and choix[1]
    if not dossier then
        return
    end
    dossier = DossierCommun.preparer(dossier)
    local invalide = DossierCommun.refus(dossier)
    if invalide then
        LrDialogs.message("Dossier commun", invalide, 'warning')
        return
    end
    LrFunctionContext.postAsyncTaskWithContext('Développeur · dossier commun', function(context)
        local barre = progressionDeLaCopie(context)
        local ok, r = LrTasks.pcall(DossierCommun.choisir, dossier, {
            debut = function(total) barre:setCaption(string.format("%d fichier%s à copier", total, total > 1 and "s" or "")) end,
            avancer = function(fait, total)
                barre:setPortionComplete(fait, math.max(total, 1))
                return not barre:isCanceled()
            end,
        })
        barre:done()
        propertyTable.dossierCommun = DossierCommun.texteEtat()
        if ok then
            LrDialogs.message("Dossier commun réglé", DossierCommun.texteChoix(r), 'info')
        else
            LrDialogs.message("Dossier commun non réglé", tostring(r), 'critical')
        end
    end)
end

local function revenirAuDossierDuMac(propertyTable)
    local DossierCommun = moduleDossierCommun()
    if not DossierCommun then
        LrDialogs.message("Dossier commun", RELANCER, 'info')
        return
    end
    local refus = refusChangement(DossierCommun)
    if refus then
        LrDialogs.message("Dossier commun", refus, 'info')
        return
    end
    LrTasks.startAsyncTask(function()
        local ok, quitte = LrTasks.pcall(DossierCommun.revenir)
        propertyTable.dossierCommun = DossierCommun.texteEtat()
        if not ok then
            LrDialogs.message("Dossier commun", tostring(quitte), 'critical')
        elseif not quitte then
            LrDialogs.message("Dossier commun", "Aucun dossier commun n'est réglé : Développeur utilise déjà le dossier de ce Mac.", 'info')
        else
            LrDialogs.message("Retour au dossier de ce Mac",
                "Développeur utilise de nouveau le dossier de ce Mac (" .. Chemins.locale() .. ").\n\n"
                .. "Rien n'a été copié : les conversations, le carnet, le Suivi et les autres données restent dans le dossier commun ("
                .. quitte .. "). Celles que ce Mac avait avant le dossier commun sont dans « Avant le dossier commun … », à côté.", 'info')
        end
    end)
end

local function sectionDossierCommun(f, propertyTable, ligne)
    local bind = LrView.bind
    propertyTable.dossierCommun = texteEtatDossierCommun()
    local DossierCommun = moduleDossierCommun()
    local section = {
        title = "Dossier commun",
        synopsis = bind { key = 'dossierCommun', bind_to_object = propertyTable },

        f:static_text {
            title = "Deux Mac, un même SSD : conversations, carnet, Suivi, notes, mes demandes, publication, consommation, guide de style et avant/après dans un dossier commun. Sur l'un ou l'autre Mac, vous reprenez le travail où vous l'avez laissé (jamais les deux en même temps).",
            width_in_chars = 66, height_in_lines = 3,
        },
        ligne("Dossier commun :", f:static_text {
            title = bind { key = 'dossierCommun', bind_to_object = propertyTable },
            fill_horizontal = 1,
        }),
    }
    if not DossierCommun then
        -- DossierCommun.lua ajouté depuis le lancement de Lightroom (« Charger de nouveau » ne le
        -- charge pas) : les autres sections restent, celle-ci le dit.
        section[#section + 1] = ligne("", f:static_text { title = RELANCER, width_in_chars = 60, height_in_lines = 2 })
        return section
    end
    section[#section + 1] = ligne("",
        f:push_button { title = "Choisir…", action = function() choisirDossierCommun(propertyTable) end },
        f:push_button { title = "Revenir au dossier de ce Mac", action = function() revenirAuDossierDuMac(propertyTable) end })
    section[#section + 1] = ligne("", f:static_text {
        title = "Choisissez le SSD Photos : le dossier « " .. DossierCommun.NOM .. " » y est créé. Vide, les données de ce Mac y sont copiées ; s'il en a déjà (l'autre Mac), il est pris tel quel. Les données de ce Mac sont ensuite mises de côté, jamais effacées. La copie se suit dans une fenêtre de progression, qui permet de l'annuler (à défaut, dans la barre d'activité de la fenêtre principale).",
        width_in_chars = 60, height_in_lines = 6,
    })
    return section
end

-- Mises à jour par le SSD (1.7) : l'état, et les trois boutons, chacun dans sa propre tâche.
local function actionMisesAJour(propertyTable, quoi)
    LrTasks.startAsyncTask(function()
        local MisesAJour = require 'MisesAJour'
        local refus = MisesAJour.refus()
        if refus then
            propertyTable.misesAJour = refus
            LrDialogs.message("Mises à jour par le SSD", refus, 'info')
            return
        end
        if MisesAJour.enCours then
            LrDialogs.message("Mises à jour par le SSD", "Une mise à jour par le SSD est déjà en cours.", 'info')
            return
        end
        MisesAJour.enCours = true
        local ok, erreur = LrTasks.pcall(function()
            propertyTable.misesAJour = "vérification…"
            local r, raison = MisesAJour.verifier()
            if not r then
                propertyTable.misesAJour = raison
                LrDialogs.message("Mises à jour par le SSD", tostring(raison), 'warning')
                return
            end
            if quoi == 'installer' then
                local liste = MisesAJour.aInstaller(r)
                if #liste == 0 then
                    LrDialogs.message("Mises à jour par le SSD", "Le SSD n'a rien de plus récent que ce Mac.", 'info')
                else
                    MisesAJour.installer(liste)
                end
            elseif quoi == 'deposer' then
                local liste = MisesAJour.aDeposer(r)
                if #liste == 0 then
                    LrDialogs.message("Mises à jour par le SSD", "Ce Mac n'a rien de plus récent que le SSD.", 'info')
                else
                    MisesAJour.deposer(liste, true)
                end
            else
                local lignes = {}
                for _, e in ipairs(r.elements or {}) do
                    lignes[#lignes + 1] = string.format("• %s : %s", tostring(e.nom), tostring(e.etat_texte))
                end
                LrDialogs.message("Mises à jour par le SSD", table.concat(lignes, "\n"), 'info')
            end
            if quoi ~= 'verifier' then
                r = MisesAJour.verifier() or r
            end
            propertyTable.misesAJour = MisesAJour.texteEtat(r)
        end)
        MisesAJour.enCours = false
        if not ok then
            LrDialogs.message("Mises à jour par le SSD", tostring(erreur), 'critical')
        end
    end)
end

local function sectionMisesAJour(f, propertyTable, ligne)
    local bind = LrView.bind
    -- MisesAJour.lua est nouveau en 1.7 : pris par pcall, comme DossierCommun.lua.
    local okM, MisesAJour = pcall(require, 'MisesAJour')
    if not okM or type(MisesAJour) ~= 'table' then
        return {
            title = "Mises à jour par le SSD",
            synopsis = "indisponible",
            f:static_text { title = "Quittez et relancez Lightroom pour les mises à jour par le SSD (un fichier nouveau du module ne se charge qu'au lancement).", width_in_chars = 66, height_in_lines = 2 },
        }
    end
    propertyTable.misesAJour = MisesAJour.refus() or MisesAJour.texteEtat(MisesAJour.derniere)
    return {
        title = "Mises à jour par le SSD",
        synopsis = bind { key = 'misesAJour', bind_to_object = propertyTable },

        f:static_text {
            title = "Le dossier commun garde aussi, dans Installation, la dernière version de Développeur IA, de Fibo 2 Studio, de mflux, des modèles de Fibo et de Claude Code : l'autre Mac s'installe depuis le SSD, sans téléchargement. Au lancement de Lightroom, ce Mac dépose ce qu'il a de plus récent et propose ce que le SSD a de plus récent.",
            width_in_chars = 66, height_in_lines = 4,
        },
        ligne("État :", f:static_text {
            title = bind { key = 'misesAJour', bind_to_object = propertyTable },
            fill_horizontal = 1,
        }),
        ligne("",
            f:push_button { title = "Vérifier", action = function() actionMisesAJour(propertyTable, 'verifier') end },
            f:push_button { title = "Installer depuis le SSD", action = function() actionMisesAJour(propertyTable, 'installer') end },
            f:push_button { title = "Déposer sur le SSD", action = function() actionMisesAJour(propertyTable, 'deposer') end }),
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
        sectionDossierCommun(f, propertyTable, ligne),
        sectionMisesAJour(f, propertyTable, ligne),
    }
end

return {
    sectionsForTopOfDialog = sectionsForTopOfDialog,
    diagnostic = diagnostic,
}
