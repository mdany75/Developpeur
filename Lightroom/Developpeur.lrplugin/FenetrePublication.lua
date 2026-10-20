-- FenetrePublication.lua : la fenêtre « Claude · Publication » : les profils à gauche (un, ou
-- plusieurs formats à la fois), à droite les photos (photo active, sélection ou collection), le
-- dossier, le format, les noms et options, le poids estimé et « Publier ». Sans Claude ni quota :
-- Lightroom exporte directement (Publication.lua).
-- La liste des profils se construit à l'ouverture : après un ajout ou une suppression, la fenêtre
-- se rouvre.

local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrShell = import 'LrShell'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Journal = require 'Journal'
local Publication = require 'Publication'
local Texte = require 'Texte'

local FenetrePublication = { ouverte = false }

FenetrePublication.GAUCHE = 300
FenetrePublication.DROITE = 540
-- Au-delà, le poids est estimé d'après la moyenne des premières photos.
FenetrePublication.PHOTOS_MESUREES = 200

local COULEURS = {
    gris = LrColor(0.45, 0.45, 0.48),
    orange = LrColor(0.88, 0.50, 0.05),
    vert = LrColor(0.18, 0.62, 0.28),
    rouge = LrColor(0.82, 0.18, 0.18),
}
local POLICES = {
    texte = { name = 'Helvetica Neue', size = 13 },
    gras = { name = 'Helvetica Neue Bold', size = 13 },
    petit = { name = 'Helvetica Neue', size = 11 },
}

local bind = LrView.bind

local function nonLie(cle)
    return bind { key = cle, transform = function(v) return not v end }
end

local function enTache(fn, ...)
    local arguments = { ... }
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(fn, unpack(arguments))
        if not ok then
            Journal.noter("Publication :", tostring(erreur))
            if FenetrePublication.p then
                FenetrePublication.p.bilan = tostring(erreur)
            end
        end
    end)
end

-- Les profils cochés (ou le profil choisi).
function FenetrePublication.profilsChoisis()
    local p = FenetrePublication.p
    local choisis = {}
    for _, profil in ipairs(FenetrePublication.profils or {}) do
        if (p.plusieurs and p['choisi_' .. profil.id]) or (not p.plusieurs and p.profil == profil.id) then
            choisis[#choisis + 1] = profil
        end
    end
    return choisis
end

function FenetrePublication.modele()
    local nom = FenetrePublication.p and FenetrePublication.p.modeleNoms
    for _, m in ipairs(FenetrePublication.modeles or {}) do
        if m.nom == nom then
            return m
        end
    end
    return nil
end

-- Format et taille, poids, bouton : d'après les profils et les photos (dans une tâche).
function FenetrePublication.recalculer()
    local p = FenetrePublication.p
    if not p then
        return
    end
    local choisis = FenetrePublication.profilsChoisis()
    local lignes = {}
    for _, profil in ipairs(choisis) do
        lignes[#lignes + 1] = profil.nom .. " : " .. Publication.resume(profil)
        if profil.remarque then
            lignes[#lignes + 1] = "   " .. profil.remarque
        end
    end
    p.texteFormats = #lignes > 0 and table.concat(lignes, '\n') or "Choisissez un profil."
    local photos = Publication.photos(p.portee, p.collection)
    FenetrePublication.photosVisees = photos
    local n = #photos
    if p.portee == 'active' then
        p.textePhotos = n > 0 and (photos[1]:getFormattedMetadata('fileName') or "1 photo") or "Aucune photo active."
    elseif p.portee == 'collection' then
        p.textePhotos = p.collection and string.format("%d photo(s) dans la collection.", n) or "Choisissez une collection."
    else
        p.textePhotos = string.format("%d photo(s) sélectionnée(s) dans Lightroom.", n)
    end
    local total, mesurees, mpx = 0, 0, 0
    for i, photo in ipairs(photos) do
        if i > FenetrePublication.PHOTOS_MESUREES then
            break
        end
        mpx = mpx + Publication.megapixels(photo)
        mesurees = mesurees + 1
    end
    local moyenne = mesurees > 0 and mpx / mesurees or 26
    for _, profil in ipairs(choisis) do
        total = total + Publication.poidsEstime(profil, moyenne) * n
    end
    p.poids = (n > 0 and #choisis > 0) and Publication.texteOctets(total) or "—"
    local titre = "Publier " .. (n == 1 and "1 photo" or (n .. " photos"))
    if #choisis > 1 then
        titre = titre .. " × " .. #choisis
    end
    p.titrePublier = titre
    p.peutPublier = n > 0 and #choisis > 0 and not p.enCours
    local m = FenetrePublication.modele()
    p.besoinTexte = m ~= nil and m.texte
    p.peutVoirNoms = m ~= nil and n > 0
    -- Le profil choisi est-il un profil de l'utilisateur (supprimable) ?
    p.profilPerso = (not p.plusieurs) and choisis[1] ~= nil and choisis[1].perso == true
end

function FenetrePublication.choisirDossier()
    local p = FenetrePublication.p
    local choix = LrDialogs.runOpenPanel {
        title = "Dossier de publication",
        prompt = "Choisir",
        canChooseFiles = false,
        canChooseDirectories = true,
        canCreateDirectories = true,
        allowsMultipleSelection = false,
        initialDirectory = p.dossier,
    }
    if choix and choix[1] then
        p.dossier = choix[1]
    end
end

function FenetrePublication.voirNoms()
    local p = FenetrePublication.p
    local m = FenetrePublication.modele()
    if not m then
        return
    end
    local noms, erreur = Publication.noms(FenetrePublication.photosVisees or {}, m, p.textePerso)
    local lignes = {}
    for _, n in ipairs(noms or {}) do
        lignes[#lignes + 1] = n.origine .. "  →  " .. tostring(n.nom)
    end
    if #(FenetrePublication.photosVisees or {}) > 20 then
        lignes[#lignes + 1] = "…"
    end
    local f = LrView.osFactory()
    LrDialogs.presentModalDialog {
        title = "Noms que Lightroom donnera · " .. m.nom,
        contents = f:column {
            spacing = f:control_spacing(),
            f:static_text { title = erreur or "Sans l'extension ; un nom déjà pris dans le dossier reçoit « -2 »." },
            f:edit_field { value = table.concat(lignes, '\n'), width_in_chars = 70, height_in_lines = 14 },
        },
        actionVerb = "Fermer",
        cancelVerb = '< exclude >',
    }
end

function FenetrePublication.publier()
    local p = FenetrePublication.p
    local choisis = FenetrePublication.profilsChoisis()
    local photos = Publication.photos(p.portee, p.collection)
    if #choisis == 0 or #photos == 0 then
        return
    end
    local dossier, raison = Publication.preparerDossier(p.dossier)
    if not dossier then
        p.bilan = raison
        return
    end
    local reponse = LrDialogs.confirm(p.titrePublier .. " ?",
        "Dans « " .. dossier .. " »" .. (#choisis > 1 and ", un sous-dossier par format" or "")
        .. ". Un fichier qui existe déjà n'est jamais écrasé (« -2 »). Les photos du catalogue ne changent pas.", "Publier", "Annuler")
    if reponse ~= 'ok' then
        return
    end
    Chemins.prefs().dossierPublication = dossier
    local m = FenetrePublication.modele()
    p.enCours = true
    p.peutPublier = false
    p.bilan = "Publication en cours (progression en haut à gauche de Lightroom)…"
    local bilan = Publication.publier(choisis, photos, dossier, {
        jetons = m and m.jetons or nil, textePerso = p.textePerso, droitsSeulement = p.droitsSeulement,
        retirerLieu = p.retirerLieu, filigrane = p.filigrane,
    })
    local lignes = {}
    for _, b in ipairs(bilan) do
        local texte = string.format("%s : %d fichier(s) dans %s", b.profil, b.fichiers, b.dossier)
        if #b.erreurs > 0 then
            texte = texte .. string.format(" ; %d en échec (%s)", #b.erreurs, b.erreurs[1])
        end
        lignes[#lignes + 1] = texte
    end
    p.enCours = false
    p.bilan = table.concat(lignes, '\n')
    FenetrePublication.dernierDossier = (#bilan == 1 and bilan[1].dossier) or dossier
    p.aDossier = true
    FenetrePublication.recalculer()
end

-- Nouveau profil ------------------------------------------------------------------------------

function FenetrePublication.nouveauProfil()
    local f = LrView.osFactory()
    local profil
    LrFunctionContext.callWithContext('Claude · nouveau profil', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.nom, q.format, q.qualite, q.espace, q.taille, q.valeur, q.profondeur, q.poidsMax, q.filigrane =
            '', 'jpeg', 85, 'srgb', 'pleine', 2048, 8, 0, false
        local share = LrView.share
        local function ligne(etiquette, controle)
            return f:row { f:static_text { title = etiquette, alignment = 'right', width = share 'etiquette' }, controle }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Nouveau profil de publication",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                ligne("Nom :", f:edit_field { value = bind 'nom', width_in_chars = 28, immediate = true }),
                ligne("Format :", f:popup_menu { value = bind 'format', items = {
                    { title = "JPEG", value = 'jpeg' }, { title = "TIFF", value = 'tiff' }, { title = "PNG", value = 'png' } } }),
                ligne("Qualité (JPEG) :", f:edit_field { value = bind 'qualite', precision = 0, min = 1, max = 100, width_in_digits = 4 }),
                ligne("Espace colorimétrique :", f:popup_menu { value = bind 'espace', items = {
                    { title = "sRGB", value = 'srgb' }, { title = "Adobe RVB", value = 'adobe_rgb' }, { title = "Display P3", value = 'display_p3' } } }),
                ligne("Taille :", f:row {
                    f:popup_menu { value = bind 'taille', items = {
                        { title = "Pleine taille", value = 'pleine' }, { title = "Grand côté (px)", value = 'grand' },
                        { title = "Petit côté (px)", value = 'petit' }, { title = "Mégapixels", value = 'mpx' } } },
                    f:edit_field { value = bind 'valeur', precision = 1, min = 0.1, max = 100000, width_in_digits = 7,
                        enabled = bind { key = 'taille', transform = function(v) return v ~= 'pleine' end } },
                }),
                ligne("Profondeur (TIFF, PNG) :", f:popup_menu { value = bind 'profondeur', items = {
                    { title = "8 bits", value = 8 }, { title = "16 bits", value = 16 } } }),
                ligne("Poids max. (Ko, JPEG ; 0 : sans) :", f:edit_field { value = bind 'poidsMax', precision = 0, min = 0, max = 1000000, width_in_digits = 8 }),
                ligne("", f:checkbox { title = "Filigrane des droits d'auteur", value = bind 'filigrane' }),
            },
            actionVerb = "Ajouter",
        }
        if reponse == 'ok' and Texte.nettoyer(q.nom) ~= '' then
            profil = { nom = Texte.nettoyer(q.nom), format = q.format, espace = q.espace }
            if q.format == 'jpeg' then
                profil.qualite = math.floor(tonumber(q.qualite) or 85)
                if (tonumber(q.poidsMax) or 0) > 0 then
                    profil.poidsMaxKo = math.floor(q.poidsMax)
                end
            else
                profil.profondeur = q.profondeur
            end
            local valeur = tonumber(q.valeur)
            if q.taille == 'grand' and valeur then
                profil.grandCote = math.floor(valeur)
            elseif q.taille == 'petit' and valeur then
                profil.petitCote = math.floor(valeur)
            elseif q.taille == 'mpx' and valeur then
                profil.megapixels = valeur
            end
            if q.filigrane then
                profil.filigrane = 'copyright'
            end
        end
    end)
    if profil then
        Publication.ajouterProfil(profil)
        FenetrePublication.profilAChoisir = profil.id
        FenetrePublication.rouvrir()
    end
end

function FenetrePublication.supprimerProfil()
    local choisis = FenetrePublication.profilsChoisis()
    local profil = choisis[1]
    if not profil or not profil.perso then
        return
    end
    if LrDialogs.confirm("Supprimer le profil « " .. profil.nom .. " » ?", nil, "Supprimer", "Annuler") == 'ok' then
        Publication.supprimerProfil(profil.id)
        FenetrePublication.rouvrir()
    end
end

function FenetrePublication.rouvrir()
    FenetrePublication.aRouvrir = true
    if FenetrePublication.controle and FenetrePublication.controle.close then
        FenetrePublication.controle.close()
    end
end

-- Construction --------------------------------------------------------------------------------

local function groupe(f, titre, contenu)
    contenu.title = titre
    contenu.width = FenetrePublication.DROITE
    contenu.spacing = contenu.spacing or 6
    return f:group_box(contenu)
end

function FenetrePublication.construire(f, p)
    local G, D = FenetrePublication.GAUCHE, FenetrePublication.DROITE
    local profils = { spacing = 6 }
    for _, profil in ipairs(FenetrePublication.profils) do
        profils[#profils + 1] = f:column {
            spacing = 0,
            f:column {
                place = 'overlapping',
                f:radio_button { title = profil.nom, value = bind 'profil', checked_value = profil.id, visible = nonLie 'plusieurs' },
                f:checkbox { title = profil.nom, value = bind('choisi_' .. profil.id), visible = bind 'plusieurs' },
            },
            f:row {
                f:spacer { width = 18 },
                f:static_text { title = Publication.resume(profil), font = POLICES.petit, text_color = COULEURS.gris, width = G - 30, truncation = 'tail' },
            },
        }
    end

    local modeles = { { title = "Nom d'origine", value = '' } }
    for _, m in ipairs(FenetrePublication.modeles) do
        modeles[#modeles + 1] = { title = m.nom, value = m.nom }
    end

    local gauche = f:column {
        spacing = 10,
        width = G,
        f:row {
            f:static_text { title = "Profils", font = POLICES.gras },
            f:spacer { fill_horizontal = 1 },
            f:checkbox { title = "Plusieurs formats à la fois", value = bind 'plusieurs' },
        },
        f:column(profils),
        f:spacer { height = 6 },
        f:row {
            f:push_button { title = "Nouveau profil…", action = function() enTache(FenetrePublication.nouveauProfil) end },
            f:push_button { title = "Supprimer…", enabled = bind 'profilPerso', action = function() enTache(FenetrePublication.supprimerProfil) end },
        },
    }

    local droite = f:column {
        spacing = 10,
        width = D,
        groupe(f, "Photos", {
            f:row {
                f:radio_button { title = "Photo active", value = bind 'portee', checked_value = 'active' },
                f:radio_button { title = "Sélection", value = bind 'portee', checked_value = 'selection' },
                f:radio_button { title = "Collection", value = bind 'portee', checked_value = 'collection' },
                f:popup_menu { value = bind 'collection', items = bind 'collections', width = 220,
                    enabled = bind { key = 'portee', transform = function(v) return v == 'collection' end } },
            },
            f:static_text { title = bind 'textePhotos', text_color = COULEURS.gris, width = D - 30 },
        }),
        groupe(f, "Dossier", {
            f:row {
                f:static_text { title = "Dossier de publication" },
                f:edit_field { value = bind 'dossier', width = D - 250, immediate = true },
                f:push_button { title = "Choisir…", action = function() enTache(FenetrePublication.choisirDossier) end },
            },
        }),
        groupe(f, "Format et taille", {
            f:static_text { title = bind 'texteFormats', width = D - 30, height_in_lines = 4 },
        }),
        groupe(f, "Noms et options", {
            f:row {
                f:static_text { title = "Modèle de noms" },
                f:popup_menu { value = bind 'modeleNoms', items = modeles, width = 280 },
            },
            f:row {
                f:static_text { title = "Texte personnalisé" },
                f:edit_field { value = bind 'textePerso', width = 280, immediate = true, enabled = bind 'besoinTexte' },
            },
            f:checkbox { title = "Droits d'auteur seulement dans les métadonnées", value = bind 'droitsSeulement' },
            f:checkbox { title = "Retirer le lieu (GPS)", value = bind 'retirerLieu' },
            f:checkbox { title = "Filigrane des droits d'auteur", value = bind 'filigrane' },
            f:push_button { title = "Voir les noms que Lightroom donnera", enabled = bind 'peutVoirNoms',
                action = function() enTache(FenetrePublication.voirNoms) end },
        }),
        groupe(f, "Publication", {
            f:row {
                f:static_text { title = "Poids estimé" },
                f:static_text { title = bind 'poids', text_color = COULEURS.gris, width = 120 },
                f:spacer { fill_horizontal = 1 },
                f:push_button { title = bind 'titrePublier', enabled = bind 'peutPublier', width = 180,
                    action = function() enTache(FenetrePublication.publier) end },
            },
            f:static_text { title = bind 'bilan', width = D - 30, height_in_lines = 3 },
            f:push_button { title = "Afficher dans le Finder", enabled = bind 'aDossier', action = function()
                if FenetrePublication.dernierDossier then
                    LrShell.revealInShell(FenetrePublication.dernierDossier)
                end
            end },
        }),
    }

    return f:row {
        bind_to_object = p,
        margin = 14,
        spacing = 14,
        gauche,
        f:separator { fill_vertical = 1 },
        droite,
    }
end

function FenetrePublication.afficher()
    if FenetrePublication.ouverte then
        if FenetrePublication.controle and FenetrePublication.controle.toFront then
            FenetrePublication.controle.toFront()
        end
        return
    end
    FenetrePublication.ouverte = true
    FenetrePublication.aRouvrir = false
    LrFunctionContext.postAsyncTaskWithContext('Claude · publication', function(context)
        context:addFailureHandler(function(_, erreur)
            FenetrePublication.ouverte = false
            FenetrePublication.p = nil
            Journal.noter("Fenêtre Publication :", tostring(erreur))
            LrDialogs.message("La fenêtre Publication n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local prefs = Chemins.prefs()
        FenetrePublication.profils = Publication.profils()
        FenetrePublication.modeles = Publication.modelesNoms()
        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        p.plusieurs = false
        p.profil = FenetrePublication.profilAChoisir or prefs.profilPublication or 'jpeg-5mpx'
        FenetrePublication.profilAChoisir = nil
        for _, profil in ipairs(FenetrePublication.profils) do
            p['choisi_' .. profil.id] = profil.id == p.profil
        end
        p.portee = 'selection'
        p.collections = Publication.collections()
        p.collection = p.collections[1] and p.collections[1].value or nil
        p.dossier = prefs.dossierPublication or LrPathUtils.child(LrPathUtils.child(Chemins.home(), 'Pictures'), 'Publications')
        p.modeleNoms = ''
        p.textePerso = ''
        p.besoinTexte = false
        p.droitsSeulement = false
        p.retirerLieu = true
        p.filigrane = false
        p.textePhotos, p.texteFormats, p.poids, p.titrePublier, p.bilan = '', '', '—', "Publier", ''
        p.peutPublier, p.peutVoirNoms, p.profilPerso, p.enCours, p.aDossier = false, false, false, false, false
        FenetrePublication.p = p

        local function changement()
            FenetrePublication.aRecalculer = true
        end
        -- Le filigrane suit le profil choisi (un profil de l'utilisateur peut en porter un) tant
        -- qu'on ne le change pas.
        local function filigraneDuProfil()
            local avec = false
            for _, profil in ipairs(FenetrePublication.profilsChoisis()) do
                avec = avec or profil.filigrane ~= nil
            end
            p.filigrane = avec
        end
        p:addObserver('plusieurs', function(_, _, plusieurs)
            if plusieurs then
                p['choisi_' .. tostring(p.profil)] = true
            else
                local premier = FenetrePublication.profilsChoisis()
                for _, profil in ipairs(FenetrePublication.profils) do
                    if p['choisi_' .. profil.id] and not premier[1] then
                        p.profil = profil.id
                    end
                end
            end
            filigraneDuProfil()
            changement()
        end)
        p:addObserver('profil', function(_, _, valeur)
            prefs.profilPublication = valeur
            filigraneDuProfil()
            changement()
        end)
        for _, profil in ipairs(FenetrePublication.profils) do
            p:addObserver('choisi_' .. profil.id, function()
                filigraneDuProfil()
                changement()
            end)
        end
        for _, cle in ipairs({ 'portee', 'collection', 'modeleNoms' }) do
            p:addObserver(cle, changement)
        end
        -- Le dossier choisi est gardé pour la prochaine fois.
        p:addObserver('dossier', function(_, _, valeur)
            if type(valeur) == 'string' and valeur:sub(1, 1) == '/' then
                prefs.dossierPublication = valeur
            end
        end)
        filigraneDuProfil()

        local contenu = FenetrePublication.construire(f, p)
        FenetrePublication.recalculer()
        LrTasks.startAsyncTask(function()
            while FenetrePublication.ouverte do
                if FenetrePublication.aRecalculer then
                    FenetrePublication.aRecalculer = false
                    local ok, erreur = LrTasks.pcall(FenetrePublication.recalculer)
                    if not ok then
                        Journal.noter("Publication :", tostring(erreur))
                    end
                end
                LrTasks.sleep(0.3)
            end
        end)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude · Publication",
            contents = contenu,
            save_frame = 'DeveloppeurPublication',
            blockTask = true,
            onShow = function(controle) FenetrePublication.controle = controle end,
            selectionChangeObserver = function() FenetrePublication.aRecalculer = true end,
            windowWillClose = function()
                FenetrePublication.ouverte = false
                FenetrePublication.controle = nil
            end,
        })
        while FenetrePublication.ouverte do
            LrTasks.sleep(0.3)
        end
        FenetrePublication.p = nil
        if FenetrePublication.aRouvrir then
            FenetrePublication.aRouvrir = false
            LrTasks.startAsyncTask(FenetrePublication.afficher)
        end
    end)
end

return FenetrePublication
