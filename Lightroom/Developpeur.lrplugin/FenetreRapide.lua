-- FenetreRapide.lua : la fenêtre Demande rapide (Fichier ou Bibliothèque › Module externe - Extras
-- › Demande rapide, ⌘⌃⌥C ; demandée par Dany le 22 octobre 2026) : le résultat page par page, une
-- demande de 3 lignes, à sa gauche trois boutons à icône (noter, Retouche pro, Portrait ; 24 octobre
-- 2026), à sa droite ▲, ▼ et Envoyer, dans une fenêtre d'environ 1 000 × 250 points ; Retour envoie,
-- comme dans la fenêtre Claude (champ à `immediate = false` : Retour le valide). Chaque demande part
-- dans une nouvelle conversation, jamais gardée (Moteur.envoyerRapide) ; la fenêtre Claude n'en voit
-- rien dans sa liste. Une autre photo ou une autre sélection efface la réponse
-- (FenetreRapide.suivreSelection) : plus de bouton ♻ (24 octobre 2026).

local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Dispositions = require 'Dispositions'
local Fil = require 'Fil'
local Journal = require 'Journal'
local Lightroom = require 'Lightroom'
local Moteur = require 'Moteur'
local Texte = require 'Texte'

local FenetreRapide = { ouverte = false }

-- Lignes du résultat montrées à la fois (13 points, 16,25 de haut chacune, relevé le 22 octobre
-- 2026 : 130 pour 8 ; dans les 155 de la zone) ; ▲ et ▼ les font défiler.
FenetreRapide.LIGNES_RESULTAT = 9
FenetreRapide.LIGNES_DEMANDE = 3
-- Largeur et hauteur du contenu, en points, pour une fenêtre d'environ 1 000 × 250 (barre de titre
-- et marges de la fenêtre en plus ; relevé à 735 × 202 pour 64 caractères de large).
FenetreRapide.LARGEUR = 998
FenetreRapide.HAUTEUR = 218
-- Le champ de demande de 3 lignes, une boîte de 55 points ; la colonne de droite prend sa hauteur et
-- sa place. Écart entre le résultat et la boîte.
FenetreRapide.HAUTEUR_DEMANDE = 55
FenetreRapide.ECART = 8
-- Largeur de la colonne de droite : ▲ et ▼ côte à côte, en petits boutons comme ceux des cartes de
-- la fenêtre Claude (Vues.fleches), puis Envoyer dessous, ensemble de la hauteur de la boîte de la
-- demande (demandé par Dany le 22 octobre 2026) ; FLECHE : la place d'un bouton « mini » dans la
-- colonne (14 points, relevé le 22 octobre 2026 ; son cadre en a 17).
FenetreRapide.BOUTON = 90
FenetreRapide.FLECHE = 14
-- Les boutons à gauche de la demande, carrés de la hauteur de sa boîte, chacun une demande toute
-- faite pour toutes les photos sélectionnées (demandés par Dany le 24 octobre 2026, à droite de ♻,
-- puis à sa place quand il est retiré le même soir) : noter et poser les notes de Claude, Retouche
-- pro et Portrait (les messages des invites de la fenêtre Claude, pour chaque photo). Icônes de
-- Dispositions.IMAGES ; ESPACE : l'écart entre deux carrés (un carré de 55 a un cadre de 57).
FenetreRapide.CARRE = FenetreRapide.HAUTEUR_DEMANDE
FenetreRapide.ESPACE = 6
local retouchePro, portrait = Consignes.invite('retouche_pro'), Consignes.invite('portrait')
FenetreRapide.ACTIONS = {
    { icone = 'rapide-noter', message = Consignes.noterRapide,
        tooltip = "Noter les photos sélectionnées : Claude pose ses notes (0 à 5 ★, ou rejet)" },
    { icone = 'rapide-retouche', message = Consignes.surLaSelection(retouchePro.message),
        tooltip = retouchePro.titre .. ", pour chaque photo sélectionnée : " .. retouchePro.message },
    { icone = 'rapide-portrait', message = Consignes.surLaSelection(portrait.message),
        tooltip = portrait.titre .. ", pour chaque photo sélectionnée : " .. portrait.message },
}
-- La zone du résultat : toute la hauteur au-dessus de la demande (relevé le 22 octobre 2026 : 988 ×
-- 248 pour 984 × 214, d'où 996 × 216 pour 1 000 × 250), sans barre de défilement : ▲ et ▼ y
-- changent de page. Le texte se coupe à la largeur du texte, moins la marge de Fil.couper.
FenetreRapide.HAUTEUR_RESULTAT = FenetreRapide.HAUTEUR - FenetreRapide.ECART - FenetreRapide.HAUTEUR_DEMANDE
FenetreRapide.LARGEUR_TEXTE = FenetreRapide.LARGEUR - 8
FenetreRapide.POLICE = { name = '<system>', size = 13 }
-- Délai de l'envoi par Retour : un clic sur ▲ ou ▼ valide aussi le champ (constaté dans la fenêtre
-- Claude, D3 : l'observateur part avant l'action du bouton) et annule cet envoi.
FenetreRapide.DELAI_ENVOI = 0.3

FenetreRapide.VIDE = "Écrivez une demande, puis Envoyer : elle part dans une nouvelle conversation, qui n'est pas gardée. "
    .. "Une autre photo ou une autre sélection efface la réponse."

-- Le texte de Claude sans la mise en forme Markdown, en une suite de lignes.
local function sansMarkdown(texte)
    texte = texte:gsub('%*%*', ''):gsub('`', ''):gsub('\n#+%s*', '\n'):gsub('^#+%s*', '')
    texte = texte:gsub('\n%s*\n', '\n')
    return Texte.nettoyer(texte)
end

-- Le résultat de la dernière demande rapide : l'état du travail pendant qu'elle se fait, puis ce
-- que Claude a écrit en dernier, avec les notes qui le suivent (un arrêt, une erreur).
function FenetreRapide.texte(tic)
    if FenetreRapide.message then
        return FenetreRapide.message
    end
    local c = Moteur.rapide
    if not c then
        return FenetreRapide.VIDE
    end
    if Moteur.travaille and Moteur.enCours == c then
        return Moteur.texteTravail(tic, c)
    end
    local morceaux = {}
    for i = #c.elements, 1, -1 do
        local e = c.elements[i]
        if e.genre == 'claude' and (e.texte or '') ~= '' then
            table.insert(morceaux, 1, sansMarkdown(e.texte))
            break
        elseif e.genre == 'note' and (e.texte or '') ~= '' then
            table.insert(morceaux, 1, e.texte)
        elseif e.genre == 'dany' then
            break
        end
    end
    if #morceaux == 0 then
        return "Claude n'a rien écrit."
    end
    return table.concat(morceaux, '\n')
end

-- Les lignes d'un texte à la largeur du résultat (paragraphes gardés), comme Fenetre.lignesCarte.
local function couper(texte)
    local lignes = {}
    for paragraphe in (Fil.sansBalises(texte) .. '\n'):gmatch('([^\n]*)\n') do
        if paragraphe == '' then
            lignes[#lignes + 1] = ''
        else
            for _, l in ipairs((Fil.couper(paragraphe, FenetreRapide.LARGEUR_TEXTE - Fil.MARGE, 'texte'))) do
                lignes[#lignes + 1] = l
            end
        end
    end
    while #lignes > 0 and lignes[#lignes] == '' do
        lignes[#lignes] = nil
    end
    return lignes
end

local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

-- Montre la page courante du résultat ; `texte` nil : le texte gardé. Un texte nouveau revient à sa
-- première ligne, coupé une seule fois (la boucle le redonne toutes les 0,25 s).
function FenetreRapide.montrer(texte)
    local p = FenetreRapide.p
    if not p then
        return
    end
    local page = FenetreRapide.page
    if texte ~= nil and (not page or page.texte ~= texte) then
        page = { texte = texte, lignes = couper(texte), debut = 1 }
        FenetreRapide.page = page
    end
    if not page then
        return
    end
    local n = FenetreRapide.LIGNES_RESULTAT
    -- La dernière page est pleine : on ne descend pas plus bas que la dernière ligne.
    page.debut = math.max(1, math.min(page.debut, #page.lignes - n + 1))
    local montre = {}
    for i = page.debut, math.min(#page.lignes, page.debut + n - 1) do
        montre[#montre + 1] = page.lignes[i]
    end
    poser(p, 'resultat', table.concat(montre, '\n'))
    poser(p, 'monte', page.debut > 1)
    poser(p, 'descend', page.debut + n - 1 < #page.lignes)
end

-- ▲ (sens -1) ou ▼ (sens 1) : une page plus haut ou plus bas, la dernière ligne vue gardée, comme
-- Fenetre.defilerTexte.
function FenetreRapide.defiler(sens)
    FenetreRapide.attente = nil
    local page = FenetreRapide.page
    if not page then
        return
    end
    page.debut = math.max(1, page.debut + sens * math.max(1, FenetreRapide.LIGNES_RESULTAT - 1))
    FenetreRapide.montrer()
end

-- Envoie la demande du champ : par Retour (l'observateur du champ validé) ou par Envoyer (un clic
-- valide d'abord le champ, constaté dans la fenêtre Claude : l'observateur part avant l'action du
-- bouton) ; `FenetreRapide.envoi` empêche le double envoi. `message` : la demande toute faite d'un
-- bouton à icône, qui laisse le champ tel quel.
function FenetreRapide.envoyer(message)
    local p = FenetreRapide.p
    if not p or Moteur.travaille or FenetreRapide.envoi then
        return
    end
    local texte = message or p.demande or ''
    if Texte.nettoyer(texte) == '' then
        return
    end
    FenetreRapide.envoi = true
    FenetreRapide.message = nil
    LrTasks.startAsyncTask(function()
        local ok, c, raison = LrTasks.pcall(Moteur.envoyerRapide, texte)
        if ok and c then
            if FenetreRapide.p and not message then
                -- Le champ vidé par la fenêtre n'est pas une demande (observateur).
                FenetreRapide.vidage = true
                FenetreRapide.p.demande = ''
                FenetreRapide.vidage = false
            end
        else
            FenetreRapide.message = ok and raison or tostring(c)
        end
        FenetreRapide.envoi = false
    end)
end

-- Un bouton à icône : sa demande toute faite part comme une demande tapée. Comme ▲ ▼, le clic
-- valide le champ et annule l'envoi par Retour.
function FenetreRapide.demander(message)
    FenetreRapide.attente = nil
    FenetreRapide.envoyer(message)
end

-- Une autre photo active ou une autre sélection, choisie par Dany, efface la réponse et oublie la
-- demande d'avant (Moteur.oublierRapide : session arrêtée, dossier effacé) : la réponse parlait
-- d'autres photos (demandé par Dany le 24 octobre 2026, à la place du bouton ♻). Ce qu'il a tapé
-- reste, pour le renvoyer sur les nouvelles. Comme Fenetre.suivreSelection : une sélection changée
-- pendant que Claude travaille, ou vue moins de DELAI_APRES_TRAVAIL secondes après la fin de son
-- travail, peut être la sienne (show_photo, une copie virtuelle montrée) : elle devient celle de la
-- réponse. La sélection vue reste d'une ouverture à l'autre : une photo choisie fenêtre fermée
-- compte aussi. `info` : Lightroom.photos(). À appeler depuis une tâche.
FenetreRapide.DELAI_APRES_TRAVAIL = 4

function FenetreRapide.suivreSelection(info)
    local cle = info and info.cle
    if not cle then
        return
    end
    local avant, vueLe = FenetreRapide.cleVue, FenetreRapide.cleVueLe
    FenetreRapide.cleVue, FenetreRapide.cleVueLe = cle, os.time()
    if avant == nil or avant == cle then
        return
    end
    local fin = Moteur.finTravail or 0
    if Moteur.travaille or (fin > 0 and (not vueLe or fin + FenetreRapide.DELAI_APRES_TRAVAIL > vueLe)) then
        return
    end
    if not Moteur.rapide and not FenetreRapide.message then
        return
    end
    local ok, fait = LrTasks.pcall(Moteur.oublierRapide)
    if ok and fait then
        FenetreRapide.message = nil
        Journal.noter("Demande rapide : autre photo choisie, réponse effacée")
    end
end

local function boucle()
    local tic = 0
    while FenetreRapide.ouverte do
        local p = FenetreRapide.p
        if p then
            local ok, erreur = LrTasks.pcall(function()
                -- La sélection de Lightroom toutes les 2 s, comme la fenêtre Claude.
                if tic % 8 == 0 then
                    FenetreRapide.suivreSelection(Lightroom.photos())
                end
                FenetreRapide.montrer(FenetreRapide.texte(tic))
                poser(p, 'libre', not Moteur.travaille)
            end)
            if not ok then
                Journal.noter("Demande rapide :", tostring(erreur))
            end
        end
        tic = tic + 1
        LrTasks.sleep(0.25)
    end
end

function FenetreRapide.afficher()
    if FenetreRapide.ouverte then
        if FenetreRapide.controle and FenetreRapide.controle.toFront then
            FenetreRapide.controle.toFront()
        end
        return
    end
    FenetreRapide.ouverte = true
    LrFunctionContext.postAsyncTaskWithContext('Claude · demande rapide', function(context)
        context:addFailureHandler(function(_, erreur)
            FenetreRapide.ouverte = false
            FenetreRapide.p = nil
            Journal.noter("Fenêtre Demande rapide :", tostring(erreur))
            LrDialogs.message("La fenêtre Demande rapide n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local f = LrView.osFactory()
        local bind = LrView.bind
        local p = LrBinding.makePropertyTable(context)
        p.resultat, p.monte, p.descend = '', false, false
        p.demande = ''
        p.libre = not Moteur.travaille
        FenetreRapide.p, FenetreRapide.page = p, nil
        FenetreRapide.envoi, FenetreRapide.vidage, FenetreRapide.attente = false, false, nil
        FenetreRapide.montrer(FenetreRapide.texte(0))
        -- Retour valide le champ (immediate = false) : la demande part, après DELAI_ENVOI, sauf si
        -- ce sont ▲ ou ▼ qui l'ont validé (FenetreRapide.defiler retire l'attente).
        p:addObserver('demande', function(_, _, valeur)
            if FenetreRapide.vidage or Texte.nettoyer(valeur or '') == '' then
                return
            end
            local attente = {}
            FenetreRapide.attente = attente
            LrTasks.startAsyncTask(function()
                LrTasks.sleep(FenetreRapide.DELAI_ENVOI)
                if FenetreRapide.attente == attente then
                    FenetreRapide.attente = nil
                    FenetreRapide.envoyer()
                end
            end)
        end)
        -- Pièces superposées, placées par leurs marges (place = 'overlapping') : le résultat en
        -- haut ; la demande en bas ; à sa gauche les boutons à icône, à sa droite ▲, ▼ et Envoyer, de la hauteur de sa
        -- boîte, à la même marge du haut (relevé le 22 octobre 2026 : la boîte du champ et la colonne commencent
        -- à leur margin_top). Dans une f:row, Lightroom alignait les lignes de texte (champ 15 points
        -- plus bas que le bouton), et une f:column ajoutait une zone grise sous le résultat (demandé
        -- par Dany le 22 octobre 2026 : résultat en haut, demande et boutons en bas, à la même
        -- hauteur).
        local boite = FenetreRapide.HAUTEUR_RESULTAT + FenetreRapide.ECART
        local gauche = FenetreRapide.LARGEUR - FenetreRapide.BOUTON
        -- Les boutons à icône, carrés de la hauteur de la boîte, chacun dans sa colonne à sa marge ;
        -- le champ commence après eux.
        local pas = FenetreRapide.CARRE + FenetreRapide.ESPACE
        local champ = #FenetreRapide.ACTIONS * pas - FenetreRapide.ESPACE + FenetreRapide.ECART
        local fleche = FenetreRapide.FLECHE
        local moitie = (FenetreRapide.BOUTON - 2) / 2
        local apparence = Chemins.prefs().apparence
        local pieces = {
            bind_to_object = p,
            place = 'overlapping',
            width = FenetreRapide.LARGEUR,
            -- La vue garde son fond blanc et son cadre ; son texte tient dans sa hauteur, rien n'y
            -- défile : ▲ et ▼ changent de page (la réponse entière, sans limite de lignes, demandé
            -- par Dany).
            f:scrolled_view {
                width = FenetreRapide.LARGEUR,
                height = FenetreRapide.HAUTEUR_RESULTAT,
                horizontal_scroller = false,
                vertical_scroller = false,
                f:static_text {
                    title = bind 'resultat',
                    font = FenetreRapide.POLICE,
                    width = FenetreRapide.LARGEUR_TEXTE,
                    height_in_lines = FenetreRapide.LIGNES_RESULTAT,
                },
            },
            f:row {
                margin_top = boite,
                margin_left = champ,
                f:edit_field {
                    value = bind 'demande',
                    width = gauche - FenetreRapide.ECART - champ,
                    height_in_lines = FenetreRapide.LIGNES_DEMANDE,
                    immediate = false,
                },
            },
            -- ▲ ▼ comme dans la fenêtre Claude (Vues.fleches : push_button « mini », une page par clic),
            -- puis Envoyer, un bouton carré (un push_button garde la hauteur fixe de macOS).
            f:column {
                margin_top = boite,
                margin_left = gauche,
                spacing = 1,
                f:row {
                    spacing = 2,
                    f:push_button { title = "▲", size = 'mini', width = moitie, tooltip = "Remonter le texte",
                        enabled = bind 'monte', action = function() FenetreRapide.defiler(-1) end },
                    f:push_button { title = "▼", size = 'mini', width = moitie, tooltip = "Descendre le texte",
                        enabled = bind 'descend', action = function() FenetreRapide.defiler(1) end },
                },
                f:square_button {
                    title = "Envoyer",
                    width = FenetreRapide.BOUTON,
                    height = FenetreRapide.HAUTEUR_DEMANDE - fleche - 1,
                    enabled = bind 'libre',
                    action = function()
                        FenetreRapide.attente = nil
                        FenetreRapide.envoyer()
                    end,
                },
            },
        }
        -- Les boutons à icône : image_name sans titre, comme les icônes de la fenêtre Claude (B3),
        -- dans le jeu d'images de l'apparence choisie au Gestionnaire de modules externes.
        for i, a in ipairs(FenetreRapide.ACTIONS) do
            pieces[#pieces + 1] = f:column {
                margin_top = boite,
                margin_left = (i - 1) * pas,
                f:square_button {
                    image_name = Chemins.ressource(Dispositions.image(a.icone, apparence)),
                    width = FenetreRapide.CARRE,
                    height = FenetreRapide.HAUTEUR_DEMANDE,
                    enabled = bind 'libre',
                    tooltip = a.tooltip,
                    action = function() FenetreRapide.demander(a.message) end,
                },
            }
        end
        local contenu = f:view(pieces)
        LrTasks.startAsyncTask(boucle)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude · Demande rapide",
            contents = contenu,
            -- Le nom change avec la taille du contenu : une taille gardée d'avant ne revient pas.
            save_frame = 'DeveloppeurRapide-14',
            blockTask = true,
            onShow = function(controle) FenetreRapide.controle = controle end,
            windowWillClose = function()
                FenetreRapide.ouverte = false
                FenetreRapide.controle = nil
            end,
        })
        while FenetreRapide.ouverte do
            LrTasks.sleep(0.5)
        end
        FenetreRapide.p = nil
    end)
end

return FenetreRapide
