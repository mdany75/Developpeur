-- Suivi.lua : fenêtre flottante « Claude · liaison », non bloquante (la fenêtre de la liaison :
-- « Afficher la fenêtre de la liaison » du menu, « fenêtre de suivi » jusqu'au correctif 1.3.6,
-- quand le carnet de progrès de la fenêtre Claude a pris ce mot : l'onglet Suivi, puis la fenêtre
-- « Claude · Suivi », FenetreSuivi.lua). Elle montre l'état de la
-- liaison (version, mode, pause), la proposition qui attend l'accord de l'utilisateur
-- (préférence « Confirmer dans Lightroom » : boutons Accepter et Refuser), la dernière retouche
-- et le journal (un clic sur une ligne sélectionne sa photo), et permet d'annuler la dernière
-- retouche ou de mettre la liaison en pause (Claude peut alors regarder, pas retoucher).

local LrApplication = import 'LrApplication'
local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Liaison = require 'Liaison'
local Preferences = require 'Preferences'

local Suivi = { ouverte = false }

-- Version, mode et pause, sur une ligne.
function Suivi.ligneEtat()
    local prefs = Preferences.lire()
    local mode = prefs.mode == 'proposer' and "proposer d'abord" or "appliquer directement"
    if prefs.mode == 'proposer' and prefs.accordDansLightroom then
        mode = mode .. ", accord donné ici"
    end
    return string.format("Module %s · %s%s", Liaison.VERSION, mode, Liaison.pause and " · en pause" or "")
end

-- La proposition en attente, en mots (vide sans proposition).
function Suivi.textePropositon()
    local p = Liaison.propositionEnAttente
    if not p then
        return "Aucune proposition en attente."
    end
    return "« " .. tostring(p.etape or p.outil or "proposition") .. " » attend votre accord" .. (p.detail and (" :\n" .. tostring(p.detail)) or ".")
end

-- Lignes du journal pour la liste, du plus récent au plus ancien : {title, value = indice}.
function Suivi.lignesJournal(journal)
    local items = {}
    for i = #journal, 1, -1 do
        items[#items + 1] = { title = journal[i], value = i }
    end
    return items
end

-- Sélectionne dans Lightroom la photo d'une ligne du journal, si elle en a une.
function Suivi.selectionnerLigne(indice)
    local id = Liaison.journalPhotos[tonumber(indice) or 0]
    if not id then
        return
    end
    LrTasks.startAsyncTask(function()
        local cat = LrApplication.activeCatalog()
        local ok, photo = LrTasks.pcall(cat.getPhotoByLocalId, cat, id)
        if ok and photo then
            LrTasks.pcall(cat.setSelectedPhotos, cat, photo, {})
        end
    end)
end

-- Le journal, du plus récent au plus ancien : la zone n'affiche que ses premières lignes.
function Suivi.journalRecentEnTete(journal)
    local lignes = {}
    for i = #journal, 1, -1 do
        lignes[#lignes + 1] = journal[i]
    end
    return table.concat(lignes, "\n")
end

function Suivi.annulerDerniere()
    LrTasks.startAsyncTask(function()
        if not Liaison.dernierePhotoId then
            LrDialogs.message("Aucune retouche de Claude à annuler pour l'instant.")
            return
        end
        local Annulation = require 'Annulation'
        local ok, erreur = LrTasks.pcall(Annulation.annuler, { photos = { Liaison.dernierePhotoId }, depuisLightroom = true })
        if ok then
            Liaison.derniersReglages = "(annulée)"
            Liaison.signaler()
        else
            LrDialogs.message("Annulation impossible", Liaison.messageErreur(erreur), 'warning')
        end
    end)
end

function Suivi.basculerPause()
    Liaison.pause = not Liaison.pause
    Liaison.noter(Liaison.pause and "Liaison mise en pause" or "Liaison reprise")
end

function Suivi.afficher()
    if Suivi.ouverte then
        return
    end
    Suivi.ouverte = true

    LrFunctionContext.postAsyncTaskWithContext('Développeur : suivi', function(context)
        local f = LrView.osFactory()
        local bind = LrView.bind
        local props = LrBinding.makePropertyTable(context)

        local function rafraichir()
            props.etat = Liaison.texteEtat()
            props.version = Suivi.ligneEtat()
            props.photo = Liaison.dernierePhoto or "Aucune retouche pour l'instant"
            props.reglages = Liaison.derniersReglages or ""
            props.journal = Suivi.lignesJournal(Liaison.journal)
            props.titrePause = Liaison.pause and "Reprendre" or "Mettre en pause"
            props.proposition = Suivi.textePropositon()
            props.enAttente = Liaison.propositionEnAttente ~= nil
        end
        rafraichir()
        Liaison.observateur = rafraichir
        props:addObserver('ligne', function(_, _, valeur)
            local indice = type(valeur) == 'table' and valeur[1] or valeur
            Suivi.selectionnerLigne(indice)
        end)

        local contenu = f:column {
            bind_to_object = props,
            spacing = f:control_spacing(),
            fill_horizontal = 1,

            f:static_text { title = bind 'etat', font = '<system/bold>', fill_horizontal = 1 },
            f:static_text { title = bind 'version', fill_horizontal = 1, width_in_chars = 60 },
            f:static_text { title = bind 'photo', fill_horizontal = 1, width_in_chars = 60 },

            f:group_box {
                title = "Proposition de Claude",
                fill_horizontal = 1,
                f:static_text { title = bind 'proposition', height_in_lines = 3, width_in_chars = 60 },
                f:row {
                    f:push_button { title = "Accepter", enabled = bind 'enAttente', action = function() Liaison.repondreProposition(true) end },
                    f:push_button { title = "Refuser", enabled = bind 'enAttente', action = function() Liaison.repondreProposition(false) end },
                },
            },
            f:group_box {
                title = "Derniers réglages appliqués",
                fill_horizontal = 1,
                f:static_text { title = bind 'reglages', height_in_lines = 8, width_in_chars = 60 },
            },
            f:group_box {
                title = "Journal (le plus récent en haut ; un clic sélectionne la photo)",
                fill_horizontal = 1,
                f:simple_list { items = bind 'journal', value = bind 'ligne', allows_multiple_selection = false,
                    height_in_lines = 8, width_in_chars = 60 },
            },
            f:row {
                f:push_button { title = "Annuler la dernière retouche", action = function() Suivi.annulerDerniere() end },
                f:push_button { title = bind 'titrePause', action = function() Suivi.basculerPause() end },
            },
            -- Une marge sous les boutons (sur la capture du 16 octobre, ils touchaient le bord bas).
            f:spacer { height = 8 },
        }

        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude · liaison",
            contents = contenu,
            save_frame = 'DeveloppeurSuivi',
            -- Bloque cette tâche tant que la fenêtre est ouverte : sinon le contexte, et avec lui
            -- les observateurs de la table de propriétés, peut expirer.
            blockTask = true,
            windowWillClose = function()
                Suivi.ouverte = false
            end,
        })

        -- Au cas où blockTask ne bloquerait pas (anciennes versions).
        while Suivi.ouverte do
            LrTasks.sleep(0.5)
        end
        if Liaison.observateur == rafraichir then
            Liaison.observateur = nil
        end
    end)
end

return Suivi
