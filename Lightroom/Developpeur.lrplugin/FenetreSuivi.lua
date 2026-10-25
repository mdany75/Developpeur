-- FenetreSuivi.lua : la fenêtre « Claude · Suivi », le carnet de progrès du catalogue ouvert, à part
-- de la fenêtre Claude (décision de Dany du 25 octobre 2026, correctif 1.3.6 : d'abord l'onglet
-- Suivi, à la place de Leçon), comme Publication et Consommation. Le bouton Suivi de l'en-tête de la
-- fenêtre Claude l'ouvre (Fenetre.ouvrirSuivi) ; ouverte, il la remet devant. Elle montre le
-- résumé du carnet, ses constats seulement (les leçons d'avant restent dans carnet.json sans être
-- montrées), page par page avec ▲ ▼ : son texte fait par Fil.texteSuivi d'après Carnet.resumer
-- (seule source des phrases), coupé à sa largeur en 12, intertitres et défauts en gras de même
-- taille (Fil.lignesCarte) ; « Photos d'un défaut… » ouvre la liste des défauts du résumé, puis la
-- fenêtre des photos du défaut choisi (leurs constats, « Retirer du carnet… », par appel direct au
-- registre : FenetreSuivi.choisirDefaut, montrerDefaut, retirerDuCarnet), comme sous la carte de
-- l'onglet d'avant. Seul l'onglet est devenu une fenêtre : le carnet, sa case du Gestionnaire et
-- carnet.json gardent leur nom. (Les graphiques et l'ajout de chaque photo au carnet viendront
-- plus tard, au correctif 1.3.7.)
--
-- Le résumé se lit dans une tâche (le chemin du catalogue se lit par LrTasks.pcall) : à l'ouverture,
-- puis chaque fois que le registre change (Carnet.version, abonnement 'suivi' : un constat, un
-- retrait, d'ici ou d'un autre client du connecteur), par la boucle de la fenêtre ; un résumé qui ne
-- se lit pas fait un texte qui le dit (Fil.texteSuivi), jamais une lecture sans fin. Rien n'est
-- écrit dans le catalogue, ni demandé à Claude. Ses contrôles sont ceux du système (pas d'aplat ni
-- d'image : elle suit l'apparence de macOS, comme Publication et Consommation) ; toute table
-- donnée à Lightroom est neuve.

local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Carnet = require 'Carnet'
local Conversation = require 'Conversation'
local Fil = require 'Fil'
local Journal = require 'Journal'
local Metriques = require 'Metriques'
local Texte = require 'Texte'

local FenetreSuivi = { ouverte = false }

-- Le titre de la fenêtre (les fenêtres du module gardent « Claude · … »), et celui du résumé, que
-- le registre donne (seule copie).
FenetreSuivi.TITRE = "Claude · Suivi"
FenetreSuivi.TITRE_CARNET = Carnet.TITRES.carnet
FenetreSuivi.TITRE_DEFAUTS = "Photos d'un défaut"

-- Le texte du résumé : sa largeur en points et ses lignes par page, en 12 (la carte de l'onglet
-- d'avant en avait 42 de 472).
FenetreSuivi.LARGEUR = 600
FenetreSuivi.LIGNES = 36

local function police(cle)
    local m = Metriques[cle]
    return { name = m.nom, size = m.taille }
end

-- Les polices mesurées (Metriques.lua) : le texte en 12 et ses passages balisés en gras 12, le
-- titre en gras 13, le message en petit.
FenetreSuivi.POLICES = { texte12 = police('texte12'), gras12 = police('gras12'), gras = police('gras'), petit = police('petit') }

local bind = LrView.bind

local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

local function texteOuNil(valeur)
    if type(valeur) == 'string' and Texte.nettoyer(valeur) ~= '' then
        return Texte.nettoyer(valeur)
    end
    return nil
end

-- Le résumé et ses pages -------------------------------------------------------------------------

-- Le résumé lu (Carnet.resumer ; nil pendant la première lecture, { erreur } s'il ne s'est pas
-- lu), la version du registre qu'il a lue, et la première ligne montrée.
FenetreSuivi.resume, FenetreSuivi.versionLue, FenetreSuivi.debut = nil, nil, 1

-- Les lignes du texte du résumé, coupées à la largeur de la fenêtre (Fil.lignesCarte).
function FenetreSuivi.lignes()
    return Fil.lignesCarte(Fil.texteSuivi(FenetreSuivi.resume), FenetreSuivi.LARGEUR, 'texte12', 'gras12')
end

-- Vrai quand le résumé lu a des défauts : « Photos d'un défaut… » actif.
function FenetreSuivi.aDefauts()
    local page = FenetreSuivi.resume
    return type(page) == 'table' and page.vide ~= true and type(page.defauts) == 'table' and #page.defauts > 0
end

-- La fenêtre : son titre, la page du résumé (la place gardée quand il se relit : la dernière page
-- est pleine), ▲ ▼ et « Photos d'un défaut… ».
function FenetreSuivi.rafraichir()
    local p = FenetreSuivi.p
    if not p then
        return
    end
    local page = FenetreSuivi.resume
    local titres = type(page) == 'table' and type(page.titres) == 'table' and page.titres or {}
    poser(p, 'titre', Fil.sansBalises(texteOuNil(titres.carnet) or FenetreSuivi.TITRE_CARNET))
    local toutes, hauteur = FenetreSuivi.lignes(), FenetreSuivi.LIGNES
    FenetreSuivi.debut = math.max(1, math.min(FenetreSuivi.debut, #toutes - hauteur + 1))
    local montre = {}
    for i = FenetreSuivi.debut, math.min(#toutes, FenetreSuivi.debut + hauteur - 1) do
        montre[#montre + 1] = toutes[i]
    end
    poser(p, 'texte', table.concat(montre, '\n'))
    poser(p, 'monte', FenetreSuivi.debut > 1)
    poser(p, 'descend', FenetreSuivi.debut + hauteur - 1 < #toutes)
    poser(p, 'aDefauts', FenetreSuivi.aDefauts())
end

-- ▲ (sens -1) ou ▼ (sens 1) : une page plus haut ou plus bas, la dernière ligne vue gardée.
function FenetreSuivi.defiler(sens)
    FenetreSuivi.debut = math.max(1, FenetreSuivi.debut + sens * math.max(1, FenetreSuivi.LIGNES - 1))
    FenetreSuivi.rafraichir()
end

-- Relit le résumé du carnet (depuis une tâche), puis la fenêtre.
function FenetreSuivi.lire()
    FenetreSuivi.versionLue, FenetreSuivi.aRelire = Carnet.version, false
    local ok, page = LrTasks.pcall(Carnet.resumer, os.time())
    if not ok then
        Journal.noter("Carnet de progrès :", tostring(page))
        page = { erreur = tostring(page) }
    end
    FenetreSuivi.resume = page
    FenetreSuivi.rafraichir()
    return page
end

-- Depuis la boucle : le registre a changé (ou n'a pas encore été lu) : le résumé se relit.
function FenetreSuivi.suivre()
    if FenetreSuivi.aRelire or Carnet.version ~= FenetreSuivi.versionLue then
        FenetreSuivi.lire()
    end
end

-- Les photos d'un défaut ---------------------------------------------------------------------------

-- Le nom d'une photo du carnet (Carnet.photosDuDefaut) : son fichier, sinon son identifiant.
function FenetreSuivi.nomPhotoCarnet(x)
    return texteOuNil(x.fichier) or ("photo " .. Conversation.clePhoto(x.original or x.photo))
end

-- Une inclinaison en degrés, au dixième, sans signe (« 1,2° »), comme le carnet la note.
local function degres(x)
    local d = math.floor(math.abs(x) * 10 + 0.5)
    return string.format('%d,%d°', math.floor(d / 10), d % 10)
end

-- Une photo d'un défaut, sur une ligne : « octobre 2026 · DSCF4961.RAF · ciel brûlé : 4,2 % … »
-- (le constat, sinon sa mesure ; `angle` : une ligne penchée, dite en degrés).
function FenetreSuivi.textePhotoDuDefaut(x)
    local morceaux = { texteOuNil(x.mois_libelle) or tostring(x.mois or '?'), FenetreSuivi.nomPhotoCarnet(x) }
    local mesure = type(x.mesure) == 'number' and (x.angle and ("ligne penchée de " .. degres(x.mesure))
        or ("mesure : " .. Texte.nombre(x.mesure))) or nil
    local constat = texteOuNil(x.texte) or mesure
    if constat then
        morceaux[#morceaux + 1] = constat
    end
    return table.concat(morceaux, " · ")
end

-- Le défaut `code` du résumé lu (libellé, conseil), sinon du vocabulaire rangé au carnet.
local function defautDuCarnet(code)
    local page = FenetreSuivi.resume
    for _, d in ipairs(type(page) == 'table' and type(page.defauts) == 'table' and page.defauts or {}) do
        if d.code == code then
            return d
        end
    end
    for _, d in ipairs(Carnet.vocabulaire()) do
        if d.code == code then
            return d
        end
    end
    return { code = code }
end

-- La fenêtre des photos d'un défaut (depuis une tâche) : bâtie au clic, des tables neuves
-- (Carnet.photosDuDefaut, dans les mois du résumé), la plus récente d'abord, leurs constats
-- seulement (la leçon de la photo choisie, dessous, est retirée au correctif 1.3.6) ; « Retirer du
-- carnet… » retire la photo choisie (FenetreSuivi.retirerDuCarnet).
function FenetreSuivi.montrerDefaut(code)
    local photos = Carnet.photosDuDefaut(code, os.time())
    -- Une ligne penchée (measure_angle, read_composition) n'a que son inclinaison, sans texte :
    -- celle de l'angle rangé dans l'entrée de l'original sous ce code.
    for _, x in ipairs(photos) do
        if texteOuNil(x.texte) == nil and type(x.mesure) == 'number' then
            local e = Carnet.entree(x.original)
            x.angle = type(e) == 'table' and type(e.angle) == 'table' and e.angle.code == code or nil
        end
    end
    local d = defautDuCarnet(code)
    local libelle = texteOuNil(d.libelle) or tostring(code)
    local f = LrView.osFactory()
    local aRetirer
    LrFunctionContext.callWithContext('Claude · carnet', function(context)
        local q = LrBinding.makePropertyTable(context)
        local items, parId = {}, {}
        for _, x in ipairs(photos) do
            items[#items + 1] = { title = FenetreSuivi.textePhotoDuDefaut(x), value = x.original }
            parId[x.original] = x
        end
        local function choisie(valeur)
            local id = type(valeur) == 'table' and valeur[1] or valeur
            return id ~= nil and parId[id] or nil
        end
        q.choix = #photos > 0 and { photos[1].original } or {}
        local entete = #photos == 0 and "Aucune photo n'a ce défaut dans les mois du carnet."
            or #photos == 1 and "1 photo dans les mois du carnet."
            or string.format("%d photos dans les mois du carnet, la plus récente d'abord.", #photos)
        local contenu = {
            bind_to_object = q,
            spacing = f:control_spacing(),
            f:static_text { title = entete, width = 640 },
        }
        if texteOuNil(d.conseil) then
            contenu[#contenu + 1] = f:static_text { title = "À la prise de vue : " .. texteOuNil(d.conseil), width = 640, height_in_lines = 2 }
        end
        if #photos > 0 then
            contenu[#contenu + 1] = f:simple_list { items = items, value = bind 'choix', allows_multiple_selection = false, width = 640, height = 160 }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = FenetreSuivi.TITRE_CARNET .. " · " .. libelle,
            contents = f:column(contenu),
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
            otherVerb = #photos > 0 and "Retirer du carnet…" or nil,
        }
        if reponse == 'other' then
            aRetirer = choisie(q.choix)
        end
    end)
    if aRetirer then
        return FenetreSuivi.retirerDuCarnet(aRetirer)
    end
    return false
end

-- Retire une photo du carnet, après confirmation : par appel direct au registre du module
-- (Carnet.commande, jamais une ligne de la liaison), avec l'identifiant de l'original (la clé de
-- son entrée). Le résumé se relit ensuite (Carnet.version). Rend vrai si elle est retirée ; ce qui
-- s'est passé se dit en bas de la fenêtre.
function FenetreSuivi.retirerDuCarnet(x)
    local nom = FenetreSuivi.nomPhotoCarnet(x)
    local reponse = LrDialogs.confirm("Retirer " .. nom .. " du carnet de progrès ?",
        "Ses constats sortent du carnet et ne comptent plus dans la fenêtre Suivi. La photo et ses retouches ne changent pas.",
        "Retirer", "Annuler")
    if reponse ~= 'ok' then
        return false
    end
    local ok, r = LrTasks.pcall(Carnet.commande, { action = 'retirer', photos = { x.original } })
    local retiree = ok and type(r) == 'table' and (tonumber(r.retirees) or 0) > 0
    FenetreSuivi.message = retiree and (nom .. " est retirée du carnet de progrès.")
        or ("Le carnet n'a pas retiré " .. nom .. (ok and " : elle n'y est plus." or (" : " .. tostring(r))))
    if FenetreSuivi.p then
        FenetreSuivi.p.message = FenetreSuivi.message
    end
    return retiree
end

-- « Photos d'un défaut… » (depuis une tâche) : la liste des défauts du résumé lu (tables neuves :
-- libellé, photos où il est vu et sur combien il a été cherché), puis, le défaut choisi, la fenêtre
-- de ses photos (FenetreSuivi.montrerDefaut). Rend ce qu'elle rend, faux sans défaut ou sans choix.
function FenetreSuivi.choisirDefaut()
    if not FenetreSuivi.aDefauts() then
        return false
    end
    local defauts = FenetreSuivi.resume.defauts
    local f = LrView.osFactory()
    local code
    LrFunctionContext.callWithContext('Claude · défauts du carnet', function(context)
        local q = LrBinding.makePropertyTable(context)
        local items = {}
        for _, d in ipairs(defauts) do
            local n, sur = tonumber(d.n) or 0, tonumber(d.sur) or 0
            items[#items + 1] = { title = string.format("%s · %d photo%s sur %d", texteOuNil(d.libelle) or tostring(d.code),
                n, n > 1 and "s" or "", sur), value = d.code }
        end
        q.choix = { defauts[1].code }
        local reponse = LrDialogs.presentModalDialog {
            title = FenetreSuivi.TITRE_CARNET .. " · " .. FenetreSuivi.TITRE_DEFAUTS,
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = "Choisissez un défaut : ses photos, dans les mois du carnet.", width = 480 },
                f:simple_list { items = items, value = bind 'choix', allows_multiple_selection = false, width = 480, height = 200 },
            },
            actionVerb = "Voir ses photos",
        }
        if reponse == 'ok' then
            local v = q.choix
            code = type(v) == 'table' and v[1] or v
        end
    end)
    if code == nil then
        return false
    end
    return FenetreSuivi.montrerDefaut(code)
end

-- La fenêtre ---------------------------------------------------------------------------------------

-- Son contenu : le titre du résumé (gras 13), sa page (en 12, ses passages balisés en gras 12),
-- puis ▲ ▼, le message (une photo retirée) et « Photos d'un défaut… ».
function FenetreSuivi.construire(f, p)
    local P, L = FenetreSuivi.POLICES, FenetreSuivi.LARGEUR
    return f:column {
        bind_to_object = p,
        margin = 14,
        spacing = 8,
        f:static_text { title = bind 'titre', font = P.gras, width = L, truncation = 'tail' },
        f:static_text { title = bind 'texte', font = P.texte12, emphasis_font = P.gras12, width = L,
            height_in_lines = FenetreSuivi.LIGNES },
        f:row {
            spacing = 2,
            f:push_button { title = "▲", size = 'mini', tooltip = "Remonter le texte", enabled = bind 'monte',
                action = function() FenetreSuivi.defiler(-1) end },
            f:push_button { title = "▼", size = 'mini', tooltip = "Descendre le texte", enabled = bind 'descend',
                action = function() FenetreSuivi.defiler(1) end },
            f:spacer { width = 8 },
            f:static_text { title = bind 'message', font = P.petit, width = L - 240, truncation = 'tail', place_vertical = 0.5 },
            f:spacer { fill_horizontal = 1 },
            f:push_button { title = "Photos d'un défaut…", enabled = bind 'aDefauts',
                tooltip = "Les photos où un défaut du carnet a été vu, et « Retirer du carnet… »",
                action = function()
                    LrTasks.startAsyncTask(function()
                        local ok, erreur = LrTasks.pcall(FenetreSuivi.choisirDefaut)
                        if not ok then
                            Journal.noter("Fenêtre Suivi :", tostring(erreur))
                        end
                    end)
                end },
        },
    }
end

-- La boucle de la fenêtre ouverte (sa génération : une fenêtre rouverte a la sienne) : le résumé
-- se relit quand le registre change, deux fois par seconde au plus.
function FenetreSuivi.boucle(generation)
    while FenetreSuivi.ouverte and FenetreSuivi.generation == generation do
        local ok, erreur = LrTasks.pcall(FenetreSuivi.suivre)
        if not ok then
            FenetreSuivi.versionLue, FenetreSuivi.aRelire = Carnet.version, false
            Journal.noter("Carnet de progrès :", tostring(erreur))
        end
        LrTasks.sleep(0.5)
    end
end

FenetreSuivi.generation = 0

-- Ouvre la fenêtre (le bouton Suivi de la fenêtre Claude) ; déjà ouverte, elle passe devant. Le
-- résumé se lit à chaque ouverture (« Lecture… » d'abord), puis la boucle le suit.
function FenetreSuivi.afficher()
    if FenetreSuivi.ouverte then
        if FenetreSuivi.controle and FenetreSuivi.controle.toFront then
            FenetreSuivi.controle.toFront()
        end
        return
    end
    FenetreSuivi.ouverte = true
    FenetreSuivi.generation = FenetreSuivi.generation + 1
    local generation = FenetreSuivi.generation
    LrFunctionContext.postAsyncTaskWithContext('Claude · suivi', function(context)
        context:addFailureHandler(function(_, erreur)
            if FenetreSuivi.generation == generation then
                FenetreSuivi.ouverte = false
                FenetreSuivi.p = nil
                Carnet.desabonner('suivi')
            end
            Journal.noter("Fenêtre Suivi :", tostring(erreur))
            LrDialogs.message("La fenêtre Suivi n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)
        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        FenetreSuivi.resume, FenetreSuivi.versionLue, FenetreSuivi.aRelire, FenetreSuivi.debut = nil, nil, false, 1
        FenetreSuivi.message = nil
        p.titre = FenetreSuivi.TITRE_CARNET
        p.texte = ''
        p.monte, p.descend, p.aDefauts = false, false, false
        p.message = ''
        FenetreSuivi.p = p
        local contenu = FenetreSuivi.construire(f, p)
        FenetreSuivi.rafraichir()
        Carnet.abonner('suivi', function() FenetreSuivi.aRelire = true end)
        LrTasks.startAsyncTask(function() FenetreSuivi.boucle(generation) end)
        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = FenetreSuivi.TITRE,
            contents = contenu,
            save_frame = 'DeveloppeurCarnet',
            blockTask = true,
            onShow = function(controle)
                if FenetreSuivi.generation == generation then
                    FenetreSuivi.controle = controle
                end
            end,
            windowWillClose = function()
                if FenetreSuivi.generation ~= generation then
                    return
                end
                FenetreSuivi.ouverte = false
                FenetreSuivi.controle = nil
                Carnet.desabonner('suivi')
            end,
        })
        -- Au cas où blockTask ne bloquerait pas : garder le contexte (et la table) en vie.
        while FenetreSuivi.ouverte and FenetreSuivi.generation == generation do
            LrTasks.sleep(0.5)
        end
        if FenetreSuivi.generation == generation then
            FenetreSuivi.p = nil
        end
    end)
end

return FenetreSuivi
