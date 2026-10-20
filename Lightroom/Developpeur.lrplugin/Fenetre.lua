-- Fenetre.lua : la fenêtre « Claude » du module Développeur (fenêtre flottante, non bloquante) :
-- une conversation avec Claude Code (le fil avec les appels d'outils, les invites en raccourcis et
-- la demande), ce que Claude regarde, sa proposition à accepter, refuser ou ajuster, la note qu'il
-- propose pour la photo active, et les versions du module et du connecteur MCP-Développeur.
--
-- Trois dispositions au choix (préférence `disposition`, dans le Gestionnaire de modules externes
-- ou le menu Disposition de la fenêtre) : Atelier, Conversation claire, Panneau. Dispositions.lua
-- les assemble des pièces de Vues.lua ; ce fichier garde l'état, ce qui remplit les propriétés
-- liées (rafraichir…), les actions, la boucle, l'ouverture et la réouverture. Les pièces ne
-- connaissent que les propriétés : une clé sans vue dans une disposition ne gêne pas.
--
-- Le SDK ne sait ni ajouter de vues à une fenêtre ouverte ni la faire défiler par programme, et
-- une vue masquée garde sa place : le fil est une grille de lignes fixes (Fil.lua), remplie à
-- chaque changement et parcourue par les boutons ▲ ▼ ; chaque ligne superpose une variante par
-- genre (police, couleur), dont une seule est visible. Lightroom ne masque que les vues simples
-- (`visible` sur un conteneur reste sans effet, constaté) : les onglets sont une rangée de
-- boutons radio au-dessus de variantes superposées de même largeur, dont chaque vue simple porte
-- la condition de son onglet (Vues.masquable). Changer de disposition ferme la fenêtre et la
-- rouvre (Fenetre.rouvrir).

local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Chemins = require 'Chemins'
local Composants = require 'Composants'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fil = require 'Fil'
local Images = require 'Images'
local Journal = require 'Journal'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Metriques = require 'Metriques'
local Moteur = require 'Moteur'
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

local Fenetre = { ouverte = false, defilement = 0, jointes = {}, cache = {}, vignettes = {}, generation = 0 }

-- Couleurs, polices, icônes et variantes des lignes, pour les pièces (Vues.lua).
local COULEURS = {
    texte = LrColor(0.11, 0.11, 0.12),
    dany = LrColor(0.04, 0.32, 0.72),
    gris = LrColor(0.45, 0.45, 0.48),
    mono = LrColor(0.24, 0.24, 0.27),
    vert = LrColor(0.18, 0.62, 0.28),
    orange = LrColor(0.88, 0.50, 0.05),
    rouge = LrColor(0.82, 0.18, 0.18),
    bleu = LrColor(0.10, 0.42, 0.85),
}
Fenetre.COULEURS = COULEURS

local function police(cle, taille)
    local m = Metriques[cle]
    return { name = m.nom, size = taille or m.taille }
end

local POLICES = {
    texte = police('texte'),
    gras = police('gras'),
    mono = police('mono'),
    titre = police('gras', 15),
    petit = police('texte', 11),
}
Fenetre.POLICES = POLICES

-- Icônes de la colonne de gauche du fil.
Fenetre.ICONES = {
    { cle = 'dany', glyphe = '›', couleur = 'dany' },
    { cle = 'ok', glyphe = '✓', couleur = 'vert' },
    { cle = 'cours', glyphe = '●', couleur = 'orange' },
    { cle = 'erreur', glyphe = '✕', couleur = 'rouge' },
    { cle = 'apercu', glyphe = '▣', couleur = 'bleu' },
    { cle = 'proposition', glyphe = '●', couleur = 'orange' },
    { cle = 'note', glyphe = 'ⓘ', couleur = 'gris' },
}

-- Variantes de texte d'une ligne, selon son genre.
Fenetre.STYLES = {
    { genres = { claude = true, vide = true }, police = 'texte', couleur = 'texte' },
    { genres = { titre = true }, police = 'gras', couleur = 'texte' },
    { genres = { dany = true }, police = 'texte', couleur = 'dany' },
    { genres = { outil = true }, police = 'mono', couleur = 'mono' },
    { genres = { apercu = true }, police = 'texte', couleur = 'bleu' },
    { genres = { proposition = true }, police = 'gras', couleur = 'orange' },
    { genres = { note = true }, police = 'texte', couleur = 'gris' },
}

-- Pastilles des voyants (Claude Code, Lightroom, mode).
Fenetre.PASTILLES = { ok = 'vert', attention = 'orange', erreur = 'rouge', neutre = 'gris', bleu = 'bleu' }

local bind = LrView.bind
Fenetre.bind = bind

-- Conditions de visibilité. Lightroom ne masque que les vues simples : `visible` lié sur un
-- conteneur reste sans effet (constaté). Toute liaison `visible` des pièces se fait ici et garde
-- ses conditions (clé et test), pour que Vues.masquable la combine avec celle d'un onglet en une
-- liaison à plusieurs clés (Fenetre.et).
local conditions = setmetatable({}, { __mode = 'k' })

local function lier(liste)
    local liaison
    if #liste == 1 then
        local c = liste[1]
        liaison = bind { key = c.cle, transform = function(v) return c.test(v) end }
    else
        local cles, vues = {}, {}
        for _, c in ipairs(liste) do
            if not vues[c.cle] then
                vues[c.cle] = true
                cles[#cles + 1] = c.cle
            end
        end
        liaison = bind {
            keys = cles,
            operation = function(_, valeurs, depuisTable)
                if not depuisTable then
                    return LrBinding.kUnsupportedDirection
                end
                for _, c in ipairs(liste) do
                    if not c.test(valeurs[c.cle]) then
                        return false
                    end
                end
                return true
            end,
        }
    end
    conditions[liaison] = liste
    return liaison
end

-- Vrai quand test(valeur de la clé) l'est.
function Fenetre.condition(cle, test)
    return lier({ { cle = cle, test = function(v) return test(v) == true end } })
end

function Fenetre.egal(cle, valeur)
    return Fenetre.condition(cle, function(v) return v == valeur end)
end

function Fenetre.non(cle)
    return Fenetre.condition(cle, function(v) return not v end)
end

function Fenetre.si(cle)
    return Fenetre.condition(cle, function(v) return v ~= nil and v ~= false end)
end

-- Une liaison neuve, vraie quand toutes les conditions de ces liaisons le sont (faites par
-- Fenetre.condition, egal, non, si ou et).
function Fenetre.et(...)
    local liste = {}
    for i = 1, select('#', ...) do
        local sienne = conditions[select(i, ...)]
        if not sienne then
            error("Condition de visibilité inconnue : passer par Fenetre.condition, egal, non ou si.", 2)
        end
        for _, c in ipairs(sienne) do
            liste[#liste + 1] = c
        end
    end
    return lier(liste)
end

-- Les fenêtres modales et le choix de fichiers s'ouvrent depuis une tâche, pas depuis l'action
-- d'un bouton.
function Fenetre.enTache(fn, ...)
    local arguments = { ... }
    LrTasks.startAsyncTask(function()
        local ok, erreur = LrTasks.pcall(fn, unpack(arguments))
        if not ok then
            Journal.noter("Fenêtre :", tostring(erreur))
        end
    end)
end
local enTache = Fenetre.enTache

-- Les actions des boutons passés par Fenetre.bouton (les essais vérifient que tous y passent).
local parBouton = setmetatable({}, { __mode = 'k' })

-- Tout bouton de la fenêtre passe par ici : son clic valide aussi le champ de demande (constaté),
-- qui ne doit pas partir ensuite ; le bouton décide.
function Fenetre.bouton(f, args)
    local action = args.action
    args.action = function(...)
        Fenetre.annulerEnvoiAuto()
        return action(...)
    end
    parBouton[args.action] = true
    return f:push_button(args)
end

function Fenetre.parBouton(action)
    return parBouton[action] == true
end

-- Change une propriété seulement si sa valeur change (moins de travail pour Lightroom).
local function poser(p, cle, valeur)
    if p[cle] ~= valeur then
        p[cle] = valeur
    end
end

-- Texte JSON rendu lisible (indenté), ou tel quel s'il n'est pas du JSON.
function Fenetre.lisible(texte)
    local ok, valeur = pcall(Json.decode, texte)
    if not ok or type(valeur) ~= 'table' then
        return texte
    end
    local function ecrire(v, retrait)
        if type(v) ~= 'table' or v == Json.null then
            return Json.encode(v)
        end
        local suivant = retrait .. '  '
        local morceaux = {}
        if #v > 0 or getmetatable(v) ~= nil then
            for _, x in ipairs(v) do
                morceaux[#morceaux + 1] = suivant .. ecrire(x, suivant)
            end
            return #morceaux == 0 and '[]' or ('[\n' .. table.concat(morceaux, ',\n') .. '\n' .. retrait .. ']')
        end
        local cles = {}
        for k in pairs(v) do
            cles[#cles + 1] = tostring(k)
        end
        table.sort(cles)
        for _, k in ipairs(cles) do
            morceaux[#morceaux + 1] = suivant .. Json.encode(k) .. ': ' .. ecrire(v[k], suivant)
        end
        return #morceaux == 0 and '{}' or ('{\n' .. table.concat(morceaux, ',\n') .. '\n' .. retrait .. '}')
    end
    return ecrire(valeur, '')
end

-- Liste des conversations ---------------------------------------------------------------------

-- Les conversations d'une séance de notation (FenetreNotation.lua) n'y figurent pas : elles ont
-- leur fenêtre.
local function estSeance(c)
    return c ~= nil and c.genre == 'notation'
end

local function periode(t, maintenant)
    maintenant = maintenant or os.time()
    if os.date('%Y%m%d', t) == os.date('%Y%m%d', maintenant) then
        return "Aujourd'hui"
    end
    local debut = os.date('*t', maintenant)
    debut.hour, debut.min, debut.sec = 0, 0, 0
    if t >= os.time(debut) - 7 * 86400 then
        return "Cette semaine"
    end
    return "Plus ancien"
end

-- Éléments de la liste : en-têtes de période et conversations trouvées (tables neuves, sans
-- métatable : Lightroom bloque sur une table relue par Json.decode).
function Fenetre.elementsListe(recherche)
    local items = {}
    local courante = Moteur.courante
    local dejaVue = false
    local derniere
    for _, c in ipairs(Moteur.conversations) do
        if c == courante then
            dejaVue = true
        end
        if not estSeance(c) and Conversation.correspond(c, recherche or '') then
            local p = periode(c.modifiee or c.creee or os.time())
            if p ~= derniere then
                items[#items + 1] = { title = p, value = '§' .. p }
                derniere = p
            end
            items[#items + 1] = { title = "   " .. tostring(c.titre or ''), value = c.id }
        end
    end
    if courante and not dejaVue and not estSeance(courante) then
        table.insert(items, 1, { title = "   " .. tostring(courante.titre or Conversation.TITRE_PAR_DEFAUT), value = courante.id })
    end
    return items
end

-- Conversations du menu (Atelier, Panneau) : les plus récentes.
Fenetre.MAX_MENU = 40

-- Éléments du menu des conversations : sans en-têtes (un menu n'a pas d'élément inactif), la
-- conversation montrée toujours dedans ; tables neuves.
function Fenetre.elementsMenu()
    local items = {}
    local courante = Moteur.courante
    local dejaVue = false
    for _, c in ipairs(Moteur.conversations) do
        if not estSeance(c) and #items < Fenetre.MAX_MENU then
            items[#items + 1] = { title = tostring(c.titre or ''), value = c.id }
            dejaVue = dejaVue or c == courante
        end
    end
    if courante and not dejaVue and not estSeance(courante) then
        table.insert(items, 1, { title = tostring(courante.titre or Conversation.TITRE_PAR_DEFAUT), value = courante.id })
    end
    return items
end

function Fenetre.rafraichirListe()
    local p = Fenetre.p
    if not p then
        return
    end
    local items = Fenetre.elementsListe(p.recherche)
    local menu = Fenetre.elementsMenu()
    local morceaux = {}
    for _, item in ipairs(items) do
        morceaux[#morceaux + 1] = tostring(item.value) .. '\1' .. item.title
    end
    morceaux[#morceaux + 1] = '\3'
    for _, item in ipairs(menu) do
        morceaux[#morceaux + 1] = tostring(item.value) .. '\1' .. item.title
    end
    morceaux[#morceaux + 1] = Moteur.courante and Moteur.courante.id or ''
    local signature = table.concat(morceaux, '\2')
    -- Remplacer la liste à chaque rafraîchissement la ferait sauter : seulement si elle change.
    if signature == Fenetre.signatureListe then
        return
    end
    Fenetre.signatureListe = signature
    Fenetre.majListe = true
    p.listeConversations = items
    p.menuConversations = menu
    if Moteur.courante then
        p.selectionListe = { Moteur.courante.id }
        p.conversationChoisie = Moteur.courante.id
    end
    Fenetre.majListe = false
end

-- Choix dans la liste ou le menu : ouvre la conversation (un en-tête, ou un refus, remet le choix).
function Fenetre.choisirDansListe(valeur)
    if Fenetre.majListe then
        return
    end
    local id = type(valeur) == 'table' and valeur[1] or valeur
    if id == nil or (Moteur.courante and id == Moteur.courante.id) then
        return
    end
    if type(id) == 'string' and id:sub(1, 1) == '§' then
        Fenetre.signatureListe = nil
        Fenetre.rafraichirListe()
        return
    end
    local ok, raison = Moteur.ouvrir(id)
    if not ok then
        Fenetre.p.message = raison or ''
        Fenetre.signatureListe = nil
        Fenetre.rafraichirListe()
        return
    end
    Fenetre.defilement = 0
    Fenetre.indiceImage = nil
    Fenetre.p.message = ''
end

function Fenetre.nouvelle()
    local ok, raison = Moteur.nouvelle()
    if not ok and Fenetre.p then
        Fenetre.p.message = raison or ''
        return
    end
    Fenetre.defilement = 0
    Fenetre.indiceImage = nil
    Fenetre.aRafraichir = true
end

-- Fil -----------------------------------------------------------------------------------------

function Fenetre.largeurTexte()
    return Fenetre.T.fil - 20
end

function Fenetre.rafraichirFil()
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    local c = Moteur.courante
    if Fenetre.conversationAffichee ~= c then
        Fenetre.defilement = 0
        Fenetre.cache = {}
        Fenetre.total = nil
    end
    local lignes = c and Fil.lignes(c, Fenetre.largeurTexte(), Fenetre.cache) or {}
    -- Lecteur remonté dans le fil : ce qui arrive ne déplace pas ce qu'il lit.
    if Fenetre.defilement > 0 and Fenetre.total and #lignes > Fenetre.total then
        Fenetre.defilement = Fenetre.defilement + (#lignes - Fenetre.total)
    end
    Fenetre.conversationAffichee = c
    Fenetre.total = #lignes
    Fenetre.lignes = lignes
    local premiere, defilement = Fil.fenetre(#lignes, T.lignes, Fenetre.defilement)
    Fenetre.defilement = defilement
    Fenetre.premiere = premiere
    for i = 1, T.lignes do
        local l = lignes[premiere + i - 1]
        poser(p, 't' .. i, l and l.texte or '')
        poser(p, 'g' .. i, l and l.genre or 'vide')
        poser(p, 'i' .. i, l and l.icone or '')
    end
    if #lignes == 0 then
        poser(p, 't2', "Demandez à Claude.")
        poser(p, 'g2', 'titre')
        poser(p, 't3', "Claude voit la photo active et la sélection de Lightroom, et retouche avec le connecteur MCP-Développeur.")
        poser(p, 'g3', 'note')
    end
    local derniere = math.min(premiere + T.lignes - 1, #lignes)
    poser(p, 'positionFil', #lignes > T.lignes and string.format("Lignes %d à %d sur %d", premiere, derniere, #lignes) or '')
    poser(p, 'peutMonter', premiere > 1)
    poser(p, 'peutDescendre', defilement > 0)
end

function Fenetre.defiler(pas)
    if pas == 'fin' then
        Fenetre.defilement = 0
    else
        Fenetre.defilement = math.max(0, Fenetre.defilement + pas)
    end
    Fenetre.rafraichirFil()
end

-- Clic sur une ligne : une image s'affiche dans l'aperçu, un outil montre son détail.
function Fenetre.cliquerLigne(i)
    Fenetre.annulerEnvoiAuto()
    local l = Fenetre.lignes and Fenetre.lignes[(Fenetre.premiere or 1) + i - 1]
    if not l then
        return
    end
    if l.image then
        for n, image in ipairs(Fenetre.images or {}) do
            if image.chemin == l.image then
                Fenetre.indiceImage = n
            end
        end
        Fenetre.rafraichirApercu()
        Fenetre.choisirOnglet('apercu')
        return
    end
    local c = Moteur.courante
    local e = c and l.element and c.elements[l.element]
    if e and e.genre == 'outil' then
        enTache(Fenetre.montrerDetail, e)
    end
end

function Fenetre.montrerDetail(e)
    local detail = e.detail or ''
    local entree, reponse = detail:match('^(.-)\n\n— Réponse —\n(.*)$')
    local texte = entree and (Fenetre.lisible(entree) .. "\n\n— Réponse —\n" .. Fenetre.lisible(reponse)) or Fenetre.lisible(detail)
    local f = LrView.osFactory()
    LrDialogs.presentModalDialog {
        title = "Claude · " .. tostring(e.texte or e.outil or 'outil'),
        contents = f:column {
            spacing = f:control_spacing(),
            f:static_text { title = "Ce que Claude a demandé au connecteur, puis sa réponse (sélectionnable, ⌘A puis ⌘C pour copier)." },
            f:edit_field { value = texte, width_in_chars = 90, height_in_lines = 24, font = POLICES.mono },
        },
        actionVerb = "Fermer",
        cancelVerb = '< exclude >',
    }
end

-- Onglets -------------------------------------------------------------------------------------

-- Montre un onglet de la disposition (s'il y est) sans annuler l'envoi automatique : c'est la
-- fenêtre qui change d'onglet, pas un clic.
function Fenetre.choisirOnglet(valeur)
    local p, T = Fenetre.p, Fenetre.T
    if not p or not valeur or not T or not T.onglets then
        return
    end
    for _, onglet in ipairs(T.onglets) do
        if onglet.valeur == valeur and p.onglet ~= valeur then
            Fenetre.ongletAuto = true
            p.onglet = valeur
            Fenetre.ongletAuto = false
        end
    end
end

-- Aperçus -------------------------------------------------------------------------------------

function Fenetre.imageVide()
    return Chemins.ressource(Dispositions.imageVide(Fenetre.T))
end

function Fenetre.rafraichirApercu()
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    local c = Moteur.courante
    Fenetre.images = c and Conversation.images(c) or {}
    local n = #Fenetre.images
    if Fenetre.indiceImage and Fenetre.indiceImage > n then
        Fenetre.indiceImage = nil
    end
    local indice = Fenetre.indiceImage or n
    poser(p, 'aImage', n > 0)
    poser(p, 'peutPrecedente', indice > 1)
    poser(p, 'peutSuivante', indice < n)
    if n == 0 then
        poser(p, 'legendeApercu', "Aucun aperçu pour l'instant")
        poser(p, 'imageApercu', Fenetre.imageVide())
        return
    end
    local image = Fenetre.images[indice]
    local nature = image.outil == 'jointe' and "photo jointe" or (image.outil or "aperçu")
    poser(p, 'legendeApercu', string.format("%d sur %d · %s", indice, n, nature))
    local hauteur = T.apercuHauteur or T.apercu
    local cle = c.id .. '/' .. image.chemin .. '/' .. T.apercu .. 'x' .. hauteur
    local deja = Fenetre.vignettes[cle]
    if deja then
        poser(p, 'imageApercu', deja)
        return
    end
    LrTasks.startAsyncTask(function()
        local chemin = Images.vignette(Stockage.dossier(c.id), image.chemin, T.apercu, hauteur)
        if chemin then
            Fenetre.vignettes[cle] = chemin
            if Fenetre.p and Fenetre.T == T and Moteur.courante == c then
                Fenetre.p.imageApercu = chemin
            end
        end
    end)
end

function Fenetre.changerImage(pas)
    local n = #(Fenetre.images or {})
    if n == 0 then
        return
    end
    Fenetre.indiceImage = math.max(1, math.min(n, (Fenetre.indiceImage or n) + pas))
    if Fenetre.indiceImage == n then
        Fenetre.indiceImage = nil
    end
    Fenetre.rafraichirApercu()
end

-- L'aperçu en grand, dans une fenêtre à part.
function Fenetre.agrandir()
    local c = Moteur.courante
    local n = #(Fenetre.images or {})
    if not c or n == 0 then
        return
    end
    local image = Fenetre.images[Fenetre.indiceImage or n]
    LrTasks.startAsyncTask(function()
        local chemin, l, h = Images.grande(Stockage.dossier(c.id), image.chemin, 1100, 740)
        if not chemin then
            LrDialogs.message("Aperçu illisible", image.chemin, 'warning')
            return
        end
        local f = LrView.osFactory()
        LrDialogs.presentModalDialog {
            title = "Claude · " .. (Fenetre.p and Fenetre.p.legendeApercu or "aperçu"),
            contents = f:picture { value = chemin, width = l, height = h },
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
        }
    end)
end

-- Proposition ---------------------------------------------------------------------------------

function Fenetre.rafraichirProposition()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    poser(p, 'enAttente', prop ~= nil and not Moteur.travaille)
    poser(p, 'aProposition', prop ~= nil)
    -- Une proposition qui arrive se montre (onglet Proposition, ou Retoucher du Panneau) ; une
    -- seule fois, pour ne pas reprendre la main à chaque rafraîchissement.
    if prop and prop.id ~= Fenetre.propositionVue then
        Fenetre.propositionVue = prop.id
        Fenetre.choisirOnglet(Fenetre.T.ongletProposition)
    end
    if not prop then
        poser(p, 'propositionTexte', "Aucune proposition en attente.\n\nEn mode « Proposer d'abord », Claude montre ici ce qu'il compte changer et attend votre accord.")
        return
    end
    local lignes = { Texte.nettoyer(prop.texte) ~= '' and prop.texte or "Claude propose :" , '' }
    for _, ch in ipairs(prop.changements or {}) do
        lignes[#lignes + 1] = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
    end
    poser(p, 'propositionTexte', table.concat(lignes, '\n'))
end

function Fenetre.repondreProposition(acceptee)
    LrTasks.startAsyncTask(function() Moteur.repondre(acceptee) end)
end

function Fenetre.ajuster()
    local f = LrView.osFactory()
    local texte = ''
    LrFunctionContext.callWithContext('Claude · ajuster', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.texte = ''
        local rapides = { spacing = 6 }
        for _, a in ipairs(Consignes.ajustementsRapides) do
            rapides[#rapides + 1] = f:push_button { title = a, action = function()
                q.texte = Texte.nettoyer(q.texte) == '' and a or (Texte.nettoyer(q.texte) .. ", " .. a:lower())
            end }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Ajuster la proposition",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = "Ce qu'il faut changer avant d'appliquer :" },
                f:edit_field { value = bind 'texte', width_in_chars = 60, height_in_lines = 3, immediate = true },
                f:row(rapides),
            },
            actionVerb = "Envoyer à Claude",
        }
        if reponse == 'ok' then
            texte = q.texte
        end
    end)
    if Texte.nettoyer(texte) ~= '' then
        LrTasks.startAsyncTask(function()
            Moteur.ajuster(texte)
        end)
    end
end

-- Note de la photo active ----------------------------------------------------------------------
-- La carte « Note » lit le registre des notes proposées (Notation.lua, rempli par la commande
-- `notation` de la liaison quand Claude appelle propose_ratings) et la note posée de la photo
-- active. Accepter et Changer… écrivent par Notation.poser, sans Claude ni quota ; Dany peut poser
-- 5 ★, Claude ne le propose jamais.

local ETATS_NOTE = {
    proposee = "proposée",
    acceptee = "acceptée",
    changee = "changée",
    a_verifier = "à vérifier",
    ecartee = "écartée",
}

local COULEURS_NOTE = { proposee = 'orange', acceptee = 'vert', changee = 'vert', a_verifier = 'rouge', ecartee = 'gris' }

local CRITERES = {
    { cle = 'impact', titre = "Impact" },
    { cle = 'qualites', titre = "Qualités" },
    { cle = 'plancher', titre = "Plancher technique" },
    { cle = 'finition', titre = "Finition" },
}

Fenetre.AIDE_NOTATION = "Noter : Claude propose une note selon le standard, critère par critère (impact, qualités, "
    .. "plancher technique, finition). Vous l'acceptez, la changez ou la gardez à vérifier ; 5 ★ reste à vous seul."

local function texteChamp(v)
    return type(v) == 'string' and Texte.nettoyer(v) or ''
end

-- « Note posée : ★★☆☆☆ · rejetée ».
function Fenetre.texteNotePosee(active)
    if not active then
        return "Aucune photo active"
    end
    if active.note == nil then
        return "Note posée : —"
    end
    local texte = active.note > 0 and ("Note posée : " .. Lightroom.etoiles(active.note)) or "Note posée : aucune, pas encore jugée"
    if active.drapeau == 'rejetee' then
        texte = texte .. " · rejetée"
    elseif active.drapeau == 'retenue' then
        texte = texte .. " · retenue"
    end
    return texte
end

-- « Claude propose : ★★★☆☆ » (ou de la rejeter).
function Fenetre.texteNoteProposee(prop)
    if prop.drapeau == 'rejetee' then
        return "Claude propose : rejeter"
    end
    local n = tonumber(prop.note) or 0
    return "Claude propose : " .. (n > 0 and Lightroom.etoiles(n) or "0 ★, pas encore jugée")
end

-- « proposée · passe 2 », « changée : ★★★★★ ».
function Fenetre.texteEtatNote(prop)
    local texte = ETATS_NOTE[prop.etat] or tostring(prop.etat or '')
    if prop.etat == 'changee' then
        if prop.drapeau_choisi == 'rejetee' then
            texte = texte .. " : rejetée"
        elseif tonumber(prop.note_choisie) then
            texte = texte .. " : " .. Lightroom.etoiles(prop.note_choisie)
        end
    elseif prop.etat == 'proposee' and prop.a_verifier == true then
        texte = texte .. " · à vérifier"
    end
    if tonumber(prop.passe) then
        texte = texte .. " · passe " .. tostring(math.floor(tonumber(prop.passe)))
    end
    return texte
end

-- Les critères, du plus lourd au plus léger, puis le plafond mesuré par cull_photos.
function Fenetre.texteCriteres(prop)
    local criteres = type(prop.criteres) == 'table' and prop.criteres or {}
    local lignes = {}
    for _, critere in ipairs(CRITERES) do
        local texte = texteChamp(criteres[critere.cle])
        if texte ~= '' then
            lignes[#lignes + 1] = critere.titre .. " : " .. texte
        end
    end
    if tonumber(prop.plafond) then
        lignes[#lignes + 1] = "Plafond mesuré : " .. tostring(math.floor(tonumber(prop.plafond))) .. " ★"
    end
    return table.concat(lignes, '\n')
end

function Fenetre.rafraichirNotation()
    local p = Fenetre.p
    if not p then
        return
    end
    Fenetre.versionNotation = Notation.version
    local active = Fenetre.info and Fenetre.info.active
    local prop
    if active then
        local ok, r = LrTasks.pcall(Notation.proposition, active.id)
        prop = ok and r or nil
    end
    Fenetre.propositionNote = prop
    poser(p, 'notationNom', active and Lightroom.nomCourt(active.nom) or "Aucune photo active")
    poser(p, 'notationPosee', Fenetre.texteNotePosee(active))
    if prop then
        poser(p, 'notationProposee', Fenetre.texteNoteProposee(prop))
        poser(p, 'notationCouleur', COULEURS_NOTE[prop.etat] or 'gris')
        poser(p, 'notationEtat', Fenetre.texteEtatNote(prop))
        poser(p, 'notationCriteres', Fenetre.texteCriteres(prop))
        poser(p, 'notationRaison', texteChamp(prop.raison))
    else
        poser(p, 'notationProposee', "Aucune note proposée")
        poser(p, 'notationCouleur', 'gris')
        poser(p, 'notationEtat', '')
        poser(p, 'notationCriteres', Fenetre.AIDE_NOTATION)
        poser(p, 'notationRaison', '')
    end
    -- Les écritures de la fenêtre échappent à la file du connecteur : pas pendant que Claude
    -- travaille, ni pendant une écriture déjà demandée.
    local libre = not Moteur.travaille and not Fenetre.noteEnCours
    poser(p, 'peutAccepterNote', libre and prop ~= nil and (prop.etat == 'proposee' or prop.etat == 'a_verifier'))
    poser(p, 'peutChangerNote', libre and active ~= nil)
    poser(p, 'peutVerifierNote', prop ~= nil and prop.etat == 'proposee')
    -- Une proposition qui arrive pour la photo montrée se montre (onglet Note), une seule fois, « à
    -- vérifier » comprise (la plus fréquente, constaté) ; une autre photo choisie ne change pas
    -- d'onglet.
    local cle = prop and (tostring(prop.photo) .. '/' .. tostring(prop.le) .. '/' .. tostring(prop.seance)) or nil
    local photo = active and active.id
    local nouvelle = prop and (prop.etat == 'proposee' or prop.etat == 'a_verifier')
    if nouvelle and cle ~= Fenetre.noteVue and Fenetre.notePhoto == photo then
        Fenetre.choisirOnglet(Fenetre.T.ongletNotation)
    end
    Fenetre.noteVue, Fenetre.notePhoto = cle, photo
end

-- Écrit une note dans le catalogue (Notation.poser), depuis une tâche, puis relit la photo : une
-- écriture à la fois, jamais pendant que Claude travaille.
function Fenetre.poserNote(choix)
    if Moteur.travaille or Fenetre.noteEnCours then
        return
    end
    Fenetre.noteEnCours = true
    Fenetre.rafraichirNotation()
    local ok, r = LrTasks.pcall(Notation.poser, { choix })
    Fenetre.noteEnCours = false
    if Fenetre.p then
        if not ok then
            Fenetre.p.message = "La note n'a pas été posée : " .. tostring(r)
        elseif not r.ok then
            Fenetre.p.message = "La note n'a pas été posée : " .. tostring(r.erreur or "raison inconnue")
        end
    end
    Fenetre.photoChangee = true
    Fenetre.aRafraichirNotation = true
end

-- Accepter : la proposition de Claude telle quelle (Notation.poser sans note ni drapeau : sa
-- note, ou le drapeau Rejeter pour un rejet ; un drapeau Retenue de Dany reste). Depuis une tâche.
function Fenetre.accepterNote()
    local prop = Fenetre.propositionNote
    if not prop then
        return
    end
    Fenetre.poserNote({ photo = prop.photo })
end

-- Changer… : de 0 à 5 ★ et le drapeau, dans une fenêtre modale (depuis une tâche). Le drapeau
-- reste tel quel sauf choix contraire.
function Fenetre.changerNote()
    local active = Fenetre.info and Fenetre.info.active
    if not active or Moteur.travaille then
        return
    end
    local prop = Fenetre.propositionNote
    local f = LrView.osFactory()
    local choix
    LrFunctionContext.callWithContext('Claude · changer la note', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.note = tonumber(prop and prop.note) or active.note or 0
        q.drapeau = prop and prop.drapeau == 'rejetee' and 'rejetee' or 'inchange'
        local notes = { { title = "0 ★, pas encore jugée", value = 0 } }
        for n = 1, 5 do
            notes[#notes + 1] = { title = Lightroom.etoiles(n), value = n }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Changer la note",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = "Note de " .. Lightroom.nomCourt(active.nom) .. " (5 ★ : vous seul la posez) :" },
                f:popup_menu { value = bind 'note', items = notes, width = 220 },
                f:popup_menu { value = bind 'drapeau', width = 220, items = {
                    { title = "Drapeau inchangé", value = 'inchange' },
                    { title = "Sans drapeau", value = 'aucun' },
                    { title = "Retenue", value = 'retenue' },
                    { title = "Rejetée", value = 'rejetee' },
                } },
            },
            actionVerb = "Poser",
        }
        if reponse == 'ok' then
            choix = { photo = active.id, note = tonumber(q.note) or 0, raison = "Note choisie dans la fenêtre Claude",
                drapeau = q.drapeau ~= 'inchange' and q.drapeau or nil }
        end
    end)
    if choix then
        Fenetre.poserNote(choix)
    end
end

-- À vérifier : la proposition reste à revoir ; rien n'est écrit dans le catalogue.
function Fenetre.verifierNote()
    local prop = Fenetre.propositionNote
    if not prop then
        return
    end
    local ok, fait, raison = LrTasks.pcall(Notation.decider, prop.photo, 'a_verifier')
    if (not ok or not fait) and Fenetre.p then
        Fenetre.p.message = "Pas mise à vérifier : " .. tostring(ok and raison or fait)
    end
    Fenetre.aRafraichirNotation = true
end

-- La séance de notation (FenetreNotation.lua), dans sa fenêtre.
function Fenetre.seance(options)
    require('FenetreNotation').afficher(options)
end

-- Noter : Claude propose une note pour la photo active ; plusieurs photos sélectionnées, c'est
-- une séance de notation (depuis une tâche : lecture du catalogue).
function Fenetre.noter()
    local info = Lightroom.photos()
    Fenetre.info = info
    if (info.selection or 0) > 1 then
        Fenetre.seance({ portee = 'selection' })
    elseif info.active then
        Fenetre.envoyer(Consignes.noterPhoto)
    elseif Fenetre.p then
        Fenetre.p.message = "Aucune photo active : choisissez une photo dans Lightroom, puis cliquez Noter."
    end
end

-- Voyants -------------------------------------------------------------------------------------

function Fenetre.rafraichirMode()
    local p = Fenetre.p
    if not p then
        return
    end
    local mode = Lightroom.mode()
    poser(p, 'texteMode', mode == 'proposer' and "Proposer d'abord" or "Appliquer directement")
    poser(p, 'etatMode', mode == 'proposer' and 'bleu' or 'neutre')
end

function Fenetre.basculerMode()
    Lightroom.basculerMode()
    Fenetre.rafraichirMode()
end

-- Claude Code (commandes du système : dans une tâche) et la liaison avec le serveur, lue
-- directement dans ce module.
function Fenetre.verifier(avecClaude)
    local p = Fenetre.p
    if not p then
        return
    end
    local prefs = Chemins.prefs()
    if avecClaude then
        local etat = Lightroom.etatClaude(prefs.cheminClaude)
        p.texteClaude = etat.texte
        p.etatClaude = etat.connecte == true and (etat.forfait and 'ok' or 'attention') or (etat.connecte == nil and 'neutre' or 'erreur')
        Fenetre.aideClaude = etat.connecte == false and (etat.installe and
            "Claude Code n'est pas connecté : ouvrez le Terminal et lancez « claude », puis /login avec votre compte claude.ai."
            or "Claude Code est introuvable : installez-le, ou réglez son chemin dans le Gestionnaire de modules externes.") or nil
    end
    if avecClaude then
        Fenetre.rafraichirVersions(Composants.lire())
    end
    local liaison, erreur = Lightroom.liaison()
    poser(p, 'texteLightroom', liaison == 'active' and "Lightroom"
        or (liaison == 'erreur' and "Lightroom · liaison en erreur" or "Lightroom · liaison arrêtée"))
    poser(p, 'etatLightroom', liaison == 'active' and 'ok' or 'erreur')
    if liaison == 'erreur' then
        Fenetre.aideLiaison = "La liaison avec Claude est en erreur (" .. tostring(erreur)
            .. ") : un autre Lightroom ouvert tient peut-être ses ports. Fermez-le, puis cliquez le voyant Lightroom."
    elseif liaison == 'arretee' then
        Fenetre.aideLiaison = "La liaison avec Claude est arrêtée : cliquez le voyant Lightroom pour la démarrer "
            .. "(ou Fichier › Module externe - Extras › Démarrer la liaison avec Claude)."
    else
        Fenetre.aideLiaison = nil
    end
    Fenetre.rafraichirMode()
    Fenetre.rafraichirAide()
end

-- Clic sur le voyant Lightroom : démarre la liaison si elle est arrêtée (ou la relance après une
-- erreur), puis le voyant se relit.
function Fenetre.demarrerLiaison()
    Lightroom.demarrerLiaison()
    Fenetre.verifier(false)
end

-- Les deux versions en bas (Composants.lignes).
function Fenetre.rafraichirVersions(lignes)
    local p = Fenetre.p
    if not p then
        return
    end
    for i, l in ipairs(lignes) do
        poser(p, 'versionNom' .. i, l.nom)
        poser(p, 'version' .. i, l.version)
        poser(p, 'versionAlerte' .. i, l.alerte == true)
    end
end

function Fenetre.rafraichirAide()
    local p = Fenetre.p
    if not p then
        return
    end
    local aides = {}
    if Fenetre.aideClaude then
        aides[#aides + 1] = Fenetre.aideClaude
    end
    if Fenetre.aideLiaison then
        aides[#aides + 1] = Fenetre.aideLiaison
    end
    Fenetre.aides = aides
    poser(p, 'aide', table.concat(aides, "  ·  "))
end

-- Clic sur l'aide du bandeau : le texte entier.
function Fenetre.montrerAide()
    if Fenetre.aides and #Fenetre.aides > 0 then
        LrDialogs.message("Claude · aide", table.concat(Fenetre.aides, "\n\n"), 'info')
    end
end

-- Ce que montre le bandeau : un message, sinon l'aide d'un voyant rouge, sinon les photos
-- jointes, sinon le rappel du style.
function Fenetre.etatBandeau(p)
    if (p.message or '') ~= '' then
        return 'message'
    elseif (p.aide or '') ~= '' then
        return 'aide'
    elseif (p.jointes or '') ~= '' then
        return 'jointes'
    end
    return 'rappel'
end

-- La photo active et la sélection (gardées pour la carte Note).
function Fenetre.majPhoto()
    local p = Fenetre.p
    if not p then
        return
    end
    -- La version du registre avant de lire la photo : une note posée entre-temps n'est pas défaite.
    local version = Notation.version
    local info = Lightroom.photos()
    Fenetre.info = info
    if info.active then
        p.infoPhoto = string.format("Active : %s     Sélection : %d", Lightroom.nomCourt(info.active.nom), info.selection)
        -- Une note acceptée ou changée qui n'est plus sur la photo (undo_last, ⌘Z) : la proposition
        -- redevient à décider.
        local active = info.active
        LrTasks.pcall(Notation.recaler, { { photo = active.id, note = active.note, drapeau = active.drapeau } }, version)
    else
        p.infoPhoto = "Aucune photo active"
    end
    Fenetre.rafraichirNotation()
end

-- Tout ce qui dépend du moteur.
function Fenetre.rafraichir()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    poser(p, 'titre', c and c.titre or Conversation.TITRE_PAR_DEFAUT)
    poser(p, 'libre', not Moteur.travaille)
    poser(p, 'travaille', Moteur.travaille)
    poser(p, 'titreEnvoyer', Moteur.travaille and "Arrêter" or "Envoyer")
    poser(p, 'forfait', Moteur.texteForfait())
    Fenetre.rafraichirFil()
    Fenetre.rafraichirApercu()
    Fenetre.rafraichirProposition()
    Fenetre.rafraichirListe()
    Fenetre.rafraichirNotation()
end

-- Demandes ------------------------------------------------------------------------------------

function Fenetre.texteJointes()
    local n = #Fenetre.jointes
    if n == 0 then
        return ''
    end
    local noms = {}
    for _, chemin in ipairs(Fenetre.jointes) do
        local nom = LrPathUtils.leafName(chemin)
        noms[#noms + 1] = nom:sub(1, 7) == 'collee-' and "image collée" or nom
    end
    return (n == 1 and "1 photo jointe : " or (n .. " photos jointes : ")) .. table.concat(noms, ", ")
end

function Fenetre.envoyer(texte, modele)
    local p = Fenetre.p
    if Moteur.travaille then
        return
    end
    local jointes = Fenetre.jointes
    texte = Texte.nettoyer(texte)
    if texte == '' and #jointes == 0 then
        p.message = "Écrivez une demande avant d'envoyer."
        return
    end
    Fenetre.jointes = {}
    p.jointes = ''
    p.message = ''
    p.libre = false
    Fenetre.defilement = 0
    LrTasks.startAsyncTask(function()
        local ok, raison = Moteur.envoyer(texte, { modele = modele or p.modele, jointes = jointes, style = p.style })
        if not ok and Fenetre.p then
            Fenetre.p.message = raison or ''
            if not Moteur.travaille then
                Fenetre.jointes = jointes
                Fenetre.p.jointes = Fenetre.texteJointes()
            end
        end
        Fenetre.aRafraichir = true
    end)
end

-- Champ de demande. Sur Mac, Lightroom ne reprend le texte d'un champ (immediate = false) qu'à
-- Retour, et au clic d'un bouton, juste avant l'action du bouton (constaté dans Lightroom 15.6 ;
-- avec immediate = true, Retour ne se voit pas du tout). Un texte reçu part donc tout seul après un
-- court délai, sauf si un clic de bouton le suit : le bouton décide (Envoyer l'envoie, les autres
-- le laissent dans le champ, pour une photo jointe par exemple). Une fenêtre rouverte entre-temps
-- (autre disposition) ne l'envoie pas.
Fenetre.DELAI_RETOUR = 0.3

function Fenetre.saisieValidee(valeur)
    if Fenetre.ignorerSaisie or type(valeur) ~= 'string' or Texte.nettoyer(valeur) == '' then
        return
    end
    local jeton, generation = {}, Fenetre.generation
    Fenetre.envoiAuto = jeton
    LrTasks.startAsyncTask(function()
        LrTasks.sleep(Fenetre.DELAI_RETOUR)
        if Fenetre.envoiAuto ~= jeton or Fenetre.generation ~= generation or not Fenetre.ouverte or not Fenetre.p then
            return
        end
        Fenetre.envoiAuto = nil
        Fenetre.envoyerSaisie()
    end)
end

-- Un clic de bouton, un choix dans la liste ou un menu : pas d'envoi automatique.
function Fenetre.annulerEnvoiAuto()
    Fenetre.envoiAuto = nil
end

-- Envoie la demande du champ et le vide.
function Fenetre.envoyerSaisie()
    local p = Fenetre.p
    if Moteur.travaille then
        p.message = "Claude travaille : attendez la fin, ou cliquez Arrêter."
        return
    end
    local texte = p.saisie
    Fenetre.ignorerSaisie = true
    p.saisie = ''
    Fenetre.ignorerSaisie = false
    Fenetre.envoyer(texte)
end

-- Bouton Envoyer / Arrêter.
function Fenetre.boutonPrincipal()
    Fenetre.annulerEnvoiAuto()
    if Moteur.travaille then
        Moteur.interrompre()
        return
    end
    Fenetre.envoyerSaisie()
end

function Fenetre.joindre()
    local chemins = LrDialogs.runOpenPanel {
        title = "Joindre une photo à la demande",
        prompt = "Joindre",
        canChooseFiles = true,
        canChooseDirectories = false,
        allowsMultipleSelection = true,
        fileTypes = { 'jpg', 'jpeg', 'png', 'heic', 'tif', 'tiff', 'webp' },
    }
    if chemins then
        for _, chemin in ipairs(chemins) do
            Fenetre.jointes[#Fenetre.jointes + 1] = chemin
        end
        Fenetre.p.jointes = Fenetre.texteJointes()
    end
end

-- Bouton 📋 : l'image du presse-papiers (capture d'écran, image copiée, fichier copié dans le
-- Finder) jointe à la demande. Le SDK ne lit pas le presse-papiers, et ⌘V dans le champ n'y colle
-- que du texte.
function Fenetre.coller()
    local chemins = Images.coller()
    if #chemins == 0 then
        Fenetre.p.message = "Pas d'image dans le presse-papiers : copiez une image (⌘C), une capture d'écran (⌃⇧⌘4) ou une photo dans le Finder, puis cliquez 📋."
        return
    end
    for _, chemin in ipairs(chemins) do
        Fenetre.jointes[#Fenetre.jointes + 1] = chemin
    end
    Fenetre.p.message = ''
    Fenetre.p.jointes = Fenetre.texteJointes()
end

function Fenetre.retirerJointes()
    Fenetre.jointes = {}
    Fenetre.p.jointes = ''
end

function Fenetre.renommer()
    local c = Moteur.courante
    if not c then
        return
    end
    local f = LrView.osFactory()
    LrFunctionContext.callWithContext('Claude · renommer', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.titre = c.titre or ''
        local reponse = LrDialogs.presentModalDialog {
            title = "Renommer la conversation",
            contents = f:column {
                bind_to_object = q,
                f:edit_field { value = bind 'titre', width_in_chars = 40, immediate = true },
            },
            actionVerb = "Renommer",
        }
        if reponse == 'ok' then
            Moteur.renommer(c.id, q.titre)
            Fenetre.aRafraichir = true
        end
    end)
end

function Fenetre.supprimer()
    local c = Moteur.courante
    if not c or #c.elements == 0 then
        return
    end
    local reponse = LrDialogs.confirm("Supprimer la conversation « " .. tostring(c.titre) .. " » ?",
        "Elle va à la corbeille du Finder, avec ses images. Les retouches faites dans Lightroom restent.", "Supprimer", "Annuler")
    if reponse == 'ok' then
        local ok, raison = Moteur.supprimer(c.id)
        if not ok and raison then
            Fenetre.p.message = raison
        end
        Fenetre.aRafraichir = true
    end
end

-- Les autres fenêtres du module (le menu Fichier est réduit quand une fenêtre du module est devant).
function Fenetre.publication()
    require('FenetrePublication').afficher()
end

function Fenetre.consommation()
    require('FenetreConsommation').afficher()
end

-- Disposition ---------------------------------------------------------------------------------

-- Menu Disposition : la préférence change, puis la fenêtre se rouvre (depuis une tâche).
function Fenetre.changerDisposition(valeur)
    if not Dispositions.TAILLES[valeur] or valeur == Fenetre.disposition then
        return
    end
    Chemins.prefs().disposition = valeur
    enTache(Fenetre.rouvrir)
end

-- Ferme la fenêtre pour la rouvrir dans la disposition et la taille des préférences (une fenêtre
-- ouverte ne change pas de structure) : la demande tapée revient dans le champ, sans partir.
function Fenetre.rouvrir()
    if not Fenetre.ouverte then
        Fenetre.afficher()
        return
    end
    Fenetre.annulerEnvoiAuto()
    if Fenetre.p and not Fenetre.aRouvrir then
        Fenetre.brouillon = Fenetre.p.saisie
    end
    Fenetre.aRouvrir = true
    if Fenetre.controle and Fenetre.controle.close then
        Fenetre.controle.close()
    end
end

-- Construction ---------------------------------------------------------------------------------

function Fenetre.construire(f, p, D)
    Fenetre.p = p
    return Dispositions.construire(f, Fenetre, D)
end

-- Ouverture -----------------------------------------------------------------------------------

-- Le nom du cadre enregistré de la fenêtre. Lightroom rend sa taille enregistrée à la fenêtre et
-- ne la rapetisse pas quand le contenu devient plus petit (bande vide en bas, constaté) : une
-- disposition dans une taille a son propre cadre, et FORME augmente quand le contenu rapetisse.
Fenetre.FORME = 1

function Fenetre.cadre(disposition, taille)
    return 'DeveloppeurClaude-' .. tostring(disposition or Dispositions.DEFAUT) .. '-' .. tostring(taille or 'moyenne') .. '-' .. Fenetre.FORME
end

function Fenetre.desabonner()
    Moteur.desabonner('fenetre')
    Notation.desabonner('fenetre')
end

-- Boucle d'une fenêtre (sa génération : une fenêtre rouverte a la sienne, l'ancienne boucle
-- s'arrête) : rafraîchit ce que le moteur a changé, la note, l'activité, et les voyants.
function Fenetre.boucle(generation)
    local tic = 0
    while Fenetre.ouverte and Fenetre.generation == generation do
        tic = tic + 1
        local p = Fenetre.p
        if p then
            if Fenetre.aRafraichir then
                Fenetre.aRafraichir = false
                local ok, erreur = LrTasks.pcall(Fenetre.rafraichir)
                if not ok then
                    Journal.noter("Rafraîchissement :", tostring(erreur))
                end
            end
            if Fenetre.photoChangee then
                Fenetre.photoChangee = false
                LrTasks.pcall(Fenetre.majPhoto)
            end
            if Fenetre.aRafraichirNotation or Notation.version ~= Fenetre.versionNotation then
                Fenetre.aRafraichirNotation = false
                local ok, erreur = LrTasks.pcall(Fenetre.rafraichirNotation)
                if not ok then
                    Journal.noter("Note :", tostring(erreur))
                end
            end
            poser(p, 'activite', Moteur.texteTravail(math.floor(tic / 2)))
            poser(p, 'travaille', Moteur.travaille)
            -- Voyants et photo active toutes les 2 s (la liaison, lue dans ce module sans commande
            -- du système, peut démarrer ou s'arrêter par le menu).
            if tic % 8 == 0 then
                LrTasks.pcall(Fenetre.verifier, false)
                LrTasks.pcall(Fenetre.majPhoto)
            end
        end
        LrTasks.sleep(0.25)
    end
end

-- Valeurs des propriétés de la carte Note avant l'ouverture (rafraichirNotation les remplit).
local function initialiserNotation(p)
    p.notationNom = ''
    p.notationPosee = ''
    p.notationProposee = ''
    p.notationCouleur = 'gris'
    p.notationEtat = ''
    p.notationCriteres = ''
    p.notationRaison = ''
    p.peutAccepterNote = false
    p.peutChangerNote = false
    p.peutVerifierNote = false
end

function Fenetre.afficher()
    if Fenetre.ouverte then
        -- Disposition ou taille changée dans le Gestionnaire de modules externes : rouverte.
        local prefs = Chemins.prefs()
        local voulue = Dispositions.dimensions(prefs.disposition, prefs.taille)
        if Fenetre.T and (voulue.nom ~= Fenetre.T.nom or voulue.taille ~= Fenetre.T.taille) then
            Fenetre.rouvrir()
        elseif Fenetre.controle and Fenetre.controle.toFront then
            Fenetre.controle.toFront()
        end
        return
    end
    Fenetre.ouverte = true
    Fenetre.generation = Fenetre.generation + 1
    local generation = Fenetre.generation

    LrFunctionContext.postAsyncTaskWithContext('Claude · fenêtre', function(context)
        context:addFailureHandler(function(_, erreur)
            if Fenetre.generation == generation then
                Fenetre.ouverte = false
                Fenetre.aRouvrir = false
                Fenetre.p = nil
                Fenetre.desabonner()
            end
            Journal.noter("Fenêtre :", tostring(erreur))
            LrDialogs.message("La fenêtre Claude n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)

        Moteur.charger()
        local prefs = Chemins.prefs()
        local D = Dispositions.dimensions(prefs.disposition, prefs.taille)
        Fenetre.T = D
        Fenetre.disposition = D.nom
        Fenetre.aRouvrir = false
        Fenetre.cache = {}
        Fenetre.vignettes = {}
        Fenetre.conversationAffichee = nil
        Fenetre.signatureListe = nil
        Fenetre.defilement = 0
        Fenetre.indiceImage = nil
        Fenetre.propositionVue = nil
        Fenetre.info = nil
        Fenetre.noteVue, Fenetre.notePhoto = nil, nil
        Fenetre.noteEnCours = false

        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        p.recherche = ''
        p.saisie = ''
        p.message = ''
        p.jointes = Fenetre.texteJointes()
        p.modele = prefs.modele
        p.style = Consignes.style(prefs.styleChoisi) and prefs.styleChoisi or 'standard'
        p.disposition = D.nom
        p.onglet = D.onglets and D.onglets[1].valeur or 'aucun'
        p.libre = not Moteur.travaille
        p.travaille = Moteur.travaille
        p.forfait = Moteur.texteForfait()
        p.texteClaude = "Claude Code"
        p.etatClaude = 'neutre'
        p.texteLightroom = "Lightroom"
        p.etatLightroom = 'neutre'
        p.texteMode = ''
        p.etatMode = 'neutre'
        p.infoPhoto = ''
        p.imageApercu = Fenetre.imageVide()
        p.legendeApercu = ''
        p.aProposition = false
        p.aide = ''
        p.bandeau = Fenetre.etatBandeau(p)
        for i, l in ipairs(Composants.lignes(Composants.module(), '…')) do
            p['versionNom' .. i], p['version' .. i], p['versionAlerte' .. i] = l.nom, l.version, false
        end
        p.activite = Moteur.texteTravail(0)
        p.listeConversations = {}
        p.selectionListe = {}
        p.menuConversations = {}
        p.conversationChoisie = ''
        for i = 1, D.lignes do
            p['t' .. i] = ''
            p['g' .. i] = 'vide'
            p['i' .. i] = ''
        end
        initialiserNotation(p)
        Fenetre.p = p

        p:addObserver('selectionListe', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Fenetre.choisirDansListe(valeur)
        end)
        p:addObserver('conversationChoisie', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Fenetre.choisirDansListe(valeur)
        end)
        p:addObserver('recherche', function()
            Fenetre.annulerEnvoiAuto()
            Fenetre.rafraichirListe()
        end)
        p:addObserver('modele', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Moteur.changerModele(valeur)
        end)
        p:addObserver('style', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Chemins.prefs().styleChoisi = valeur
        end)
        -- Un clic sur un onglet ou le menu Disposition n'envoie pas la demande validée par le clic.
        p:addObserver('onglet', function()
            if not Fenetre.ongletAuto then
                Fenetre.annulerEnvoiAuto()
            end
        end)
        p:addObserver('disposition', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Fenetre.changerDisposition(valeur)
        end)
        p:addObserver('saisie', function(_, _, valeur) Fenetre.saisieValidee(valeur) end)
        for _, cle in ipairs({ 'message', 'aide', 'jointes' }) do
            p:addObserver(cle, function(proprietes) poser(proprietes, 'bandeau', Fenetre.etatBandeau(proprietes)) end)
        end

        local contenu = Fenetre.construire(f, p, D)
        -- La demande tapée avant une réouverture revient dans le champ, sans partir.
        local brouillon = Fenetre.brouillon
        Fenetre.brouillon = nil
        if type(brouillon) == 'string' and brouillon ~= '' then
            Fenetre.ignorerSaisie = true
            p.saisie = brouillon
            Fenetre.ignorerSaisie = false
        end
        Fenetre.rafraichir()
        Fenetre.majPhoto()
        Fenetre.rafraichirMode()
        Moteur.abonner('fenetre', function() Fenetre.aRafraichir = true end)
        Notation.abonner('fenetre', function() Fenetre.aRafraichirNotation = true end)

        LrTasks.startAsyncTask(function() Fenetre.boucle(generation) end)
        LrTasks.startAsyncTask(function() LrTasks.pcall(Fenetre.verifier, true) end)

        LrDialogs.presentFloatingDialog(_PLUGIN, {
            title = "Claude",
            contents = contenu,
            save_frame = Fenetre.cadre(D.nom, D.taille),
            blockTask = true,
            onShow = function(controle)
                if Fenetre.generation == generation then
                    Fenetre.controle = controle
                end
            end,
            selectionChangeObserver = function() Fenetre.photoChangee = true end,
            windowWillClose = function()
                if Fenetre.generation ~= generation then
                    return
                end
                Fenetre.ouverte = false
                Fenetre.annulerEnvoiAuto()
                Fenetre.controle = nil
                Fenetre.desabonner()
            end,
        })

        -- Au cas où blockTask ne bloquerait pas : garder le contexte (et la table) en vie.
        while Fenetre.ouverte and Fenetre.generation == generation do
            LrTasks.sleep(0.5)
        end
        if Fenetre.generation == generation then
            Fenetre.p = nil
            if Fenetre.aRouvrir then
                Fenetre.aRouvrir = false
                LrTasks.startAsyncTask(Fenetre.afficher)
            end
        end
    end)
end

return Fenetre
