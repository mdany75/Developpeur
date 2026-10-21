-- Fenetre.lua : la fenêtre Claude du module Développeur (« Développeur » dans sa barre de titre ;
-- fenêtre flottante, non bloquante) :
-- une conversation avec Claude Code (le fil avec les appels d'outils, les invites en raccourcis et
-- la demande), ce que Claude regarde, sa proposition à accepter, refuser ou ajuster, la note qu'il
-- propose pour la photo active, et les versions du module et du connecteur MCP-Développeur.
--
-- Une seule disposition, la Conversation claire (l'Atelier, le Panneau et le choix de la
-- disposition sont retirés : demandé par Dany le 20 octobre 2026). Dispositions.lua l'assemble des
-- pièces de Vues.lua ; ce fichier garde l'état, ce qui remplit les propriétés liées
-- (rafraichir…), les actions, la boucle et l'ouverture.
--
-- Le SDK ne sait ni ajouter de vues à une fenêtre ouverte ni la faire défiler par programme, et
-- une vue masquée garde sa place : le fil est une grille de lignes fixes (Fil.lua), remplie à
-- chaque changement et parcourue par les boutons ▲ ▼ ; chaque ligne superpose une variante par
-- genre (police, couleur), dont une seule est visible. Lightroom ne masque que les vues simples
-- (`visible` sur un conteneur reste sans effet, constaté) : les onglets sont une rangée de
-- boutons radio au-dessus de variantes superposées de même largeur, dont chaque vue simple porte
-- la condition de son onglet (Vues.masquable). Une autre photo active ou une autre sélection,
-- choisie par l'utilisateur, commence une nouvelle conversation (Fenetre.suivreSelection).

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
local Fichiers = require 'Fichiers'
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

-- Pastilles des voyants (Claude Code, Lightroom, mode, écran).
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

-- Les conversations des anciennes séances de notation (genre 'notation', fenêtre retirée le
-- 20 octobre 2026) n'y figurent pas.
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

function Fenetre.rafraichirListe()
    local p = Fenetre.p
    if not p then
        return
    end
    local items = Fenetre.elementsListe(p.recherche)
    local morceaux = {}
    for _, item in ipairs(items) do
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
    if Moteur.courante then
        p.selectionListe = { Moteur.courante.id }
    end
    Fenetre.majListe = false
end

-- Choix dans la liste : ouvre la conversation (un en-tête, ou un refus, remet le choix).
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
        -- Les images de la conversation relues : le clic choisit la sienne, sans bascule vers une
        -- image arrivée entre-temps (Fenetre.rafraichirApercu).
        local c = Moteur.courante
        Fenetre.images = c and Conversation.images(c) or {}
        Fenetre.apercuDe, Fenetre.nbImages = c, #Fenetre.images
        for n, image in ipairs(Fenetre.images) do
            if image.chemin == l.image then
                Fenetre.indiceImage = n
                Fenetre.voirActive = false
            end
        end
        Fenetre.rafraichirApercu()
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

-- Montre un onglet sans annuler l'envoi automatique : c'est la fenêtre qui change d'onglet, pas un
-- clic.
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

-- L'aperçu de la photo active (demandé par Dany le 20 octobre 2026) : montré à l'ouverture de la
-- fenêtre et quand une autre photo devient active (Fenetre.majPhoto), tant que Claude ne montre pas
-- d'image nouvelle ; ◀ revient aux images de la conversation, ▶ depuis la dernière y retourne. Sa
-- vignette vient du cache d'aperçus de Lightroom (Vignettes.demander, dans une tâche), réduite au
-- cadre de l'aperçu, et se refait à chaque ouverture (la photo a pu être retouchée).
Fenetre.TAILLE_PHOTO_ACTIVE = 1024

-- Le carré de mise au point sur la vignette de la photo active, pour un fichier Fujifilm (demandé
-- par Dany le 20 octobre 2026) : le connecteur le lit dans l'original et le dessine
-- (Images.marquerMiseAuPoint) ; rien pour une autre marque (son original n'est pas ouvert).
function Fenetre.marquerMiseAuPoint(id, source)
    local ok, d = LrTasks.pcall(function()
        return require('Vignettes').decrireVignette(require('Photos').photoParId(id))
    end)
    if not ok or type(d) ~= 'table' then
        return nil
    end
    local original = type(d.chemin_original) == 'string' and d.chemin_original or ''
    local fujifilm = tostring(d.marque or ''):upper():find('FUJIFILM', 1, true) or original:lower():match('%.raf$')
    if not fujifilm then
        return nil
    end
    return Images.marquerMiseAuPoint(Chemins.prefs().cheminConnecteur, original, d.geometrie, source)
end

local function montrerActive(p, T, active, n)
    poser(p, 'peutPrecedente', n > 0)
    poser(p, 'peutSuivante', false)
    poser(p, 'legendeApercu', "Photo active · " .. Lightroom.nomCourt(active.nom))
    local a = Fenetre.apercuActif
    if a and a.id == active.id and a.T == T then
        poser(p, 'imageApercu', a.chemin)
        poser(p, 'aImage', true)
        return
    end
    poser(p, 'imageApercu', Fenetre.imageVide())
    poser(p, 'aImage', false)
    if Fenetre.demandeActive == active.id then
        return
    end
    Fenetre.demandeActive = active.id
    LrTasks.startAsyncTask(function()
        local ok, chemin, dossier, fichier = LrTasks.pcall(function()
            -- Un dossier par vignette (Images.vignette garde ses réductions par nom de fichier).
            local d = LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'PhotoActive'), Conversation.identifiant())
            local Vignettes = require 'Vignettes'
            local chemins, erreurs = Vignettes.demander({ active.id }, Fenetre.TAILLE_PHOTO_ACTIVE, d)
            local source = chemins[active.id]
            if not source then
                Journal.noter("Aperçu de la photo active :", tostring(erreurs[active.id]))
                return nil
            end
            source = Fenetre.marquerMiseAuPoint(active.id, source) or source
            local d, f = LrPathUtils.parent(source), LrPathUtils.leafName(source)
            return Images.vignette(d, f, T.apercu), d, f
        end)
        if Fenetre.demandeActive == active.id then
            Fenetre.demandeActive = nil
        end
        if ok and chemin then
            -- La vignette d'avant n'est plus montrée : son dossier s'efface.
            local avant = Fenetre.apercuActif
            if avant and avant.dossier ~= dossier then
                Fichiers.supprimer(avant.dossier)
            end
            Fenetre.apercuActif = { id = active.id, T = T, chemin = chemin, dossier = dossier, fichier = fichier }
            if Fenetre.p and Fenetre.T == T then
                Fenetre.rafraichirApercu()
            end
        elseif not ok then
            Journal.noter("Aperçu de la photo active :", tostring(chemin))
        end
    end)
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
    -- Une image de plus dans la conversation montrée (Claude regarde, une photo jointe) : elle se
    -- montre, à la place de la photo active.
    if Fenetre.apercuDe == c and Fenetre.nbImages and n > Fenetre.nbImages then
        Fenetre.voirActive = false
        Fenetre.indiceImage = nil
    end
    Fenetre.apercuDe, Fenetre.nbImages = c, n
    local active = Fenetre.info and Fenetre.info.active
    if Fenetre.voirActive and active then
        montrerActive(p, T, active, n)
        return
    end
    local indice = Fenetre.indiceImage or n
    poser(p, 'aImage', n > 0)
    poser(p, 'peutPrecedente', indice > 1)
    poser(p, 'peutSuivante', indice < n or (n > 0 and active ~= nil))
    if n == 0 then
        poser(p, 'legendeApercu', "Aucun aperçu pour l'instant")
        poser(p, 'imageApercu', Fenetre.imageVide())
        return
    end
    local image = Fenetre.images[indice]
    local nature = image.outil == 'jointe' and "photo jointe" or (image.outil or "aperçu")
    poser(p, 'legendeApercu', string.format("%d sur %d · %s", indice, n, nature))
    local hauteur = T.apercu
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
    local active = Fenetre.info and Fenetre.info.active
    if Fenetre.voirActive and active then
        -- ◀ depuis la photo active : la dernière image de la conversation.
        if pas < 0 and n > 0 then
            Fenetre.voirActive, Fenetre.indiceImage = false, nil
            Fenetre.rafraichirApercu()
        end
        return
    end
    if n == 0 then
        return
    end
    -- ▶ depuis la dernière image : la photo active.
    if pas > 0 and (Fenetre.indiceImage or n) >= n and active then
        Fenetre.voirActive = true
        Fenetre.rafraichirApercu()
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
    local a, active = Fenetre.apercuActif, Fenetre.info and Fenetre.info.active
    if Fenetre.voirActive and active and a and a.id == active.id then
        LrTasks.startAsyncTask(function()
            local chemin, l, h = Images.grande(a.dossier, a.fichier, 1100, 740)
            if chemin then
                LrDialogs.presentModalDialog {
                    title = "Claude · " .. (Fenetre.p and Fenetre.p.legendeApercu or "photo active"),
                    contents = LrView.osFactory():picture { value = chemin, width = l, height = h },
                    actionVerb = "Fermer",
                    cancelVerb = '< exclude >',
                }
            end
        end)
        return
    end
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

-- Textes des cartes, page par page --------------------------------------------------------------

-- Le texte de la carte Note (clé 'note') et celui de la proposition (clé 'proposition') : coupés
-- en lignes comme le fil (police P.texte), montrés page par page avec ▲ ▼ (Vues.fleches). Un
-- texte qui change revient à sa première page.
Fenetre.pages = {}

local CARTES = {
    note = { texte = 'notationTexte', largeur = 'largeurNote', lignes = function(T) return (T.criteres or 8) + 3 end },
    proposition = { texte = 'propositionTexte', largeur = 'largeurProposition', lignes = function(T) return T.propLignes or 5 end },
}

-- Les lignes d'un texte dans `largeur` points (paragraphes gardés, lignes vides comprises).
function Fenetre.lignesCarte(texte, largeur)
    local lignes = {}
    for paragraphe in (tostring(texte or '') .. '\n'):gmatch('([^\n]*)\n') do
        if paragraphe == '' then
            lignes[#lignes + 1] = ''
        else
            for _, l in ipairs(Fil.couper(paragraphe, largeur - Fil.MARGE, 'texte')) do
                lignes[#lignes + 1] = l
            end
        end
    end
    while #lignes > 0 and lignes[#lignes] == '' do
        lignes[#lignes] = nil
    end
    return lignes
end

-- Montre la page courante du texte de la carte `cle` ; `texte` nil : le texte gardé.
function Fenetre.montrerPage(cle, texte)
    local p, T, carte = Fenetre.p, Fenetre.T, CARTES[cle]
    if not (p and carte) then
        return
    end
    local page = Fenetre.pages[cle]
    if texte ~= nil and (not page or page.texte ~= texte) then
        page = { texte = texte, debut = 1 }
        Fenetre.pages[cle] = page
    end
    if not page then
        return
    end
    local hauteur = T and carte.lignes(T) or 8
    local lignes = Fenetre.lignesCarte(page.texte, T and T[carte.largeur] or 226)
    -- La dernière page est pleine : on ne descend pas plus bas que la dernière ligne.
    page.debut = math.max(1, math.min(page.debut, #lignes - hauteur + 1))
    local montre = {}
    for i = page.debut, math.min(#lignes, page.debut + hauteur - 1) do
        montre[#montre + 1] = lignes[i]
    end
    poser(p, carte.texte, table.concat(montre, '\n'))
    poser(p, cle .. 'Monte', page.debut > 1)
    poser(p, cle .. 'Descend', page.debut + hauteur - 1 < #lignes)
end

-- ▲ (sens -1) ou ▼ (sens 1) : une page plus haut ou plus bas, la dernière ligne vue gardée.
function Fenetre.defilerTexte(cle, sens)
    Fenetre.annulerEnvoiAuto()
    local page, carte = Fenetre.pages[cle], CARTES[cle]
    if not (page and carte) then
        return
    end
    local hauteur = Fenetre.T and carte.lignes(Fenetre.T) or 8
    page.debut = math.max(1, page.debut + sens * math.max(1, hauteur - 1))
    Fenetre.montrerPage(cle)
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
    -- Une proposition qui arrive se montre (onglet Proposition) ; une
    -- seule fois, pour ne pas reprendre la main à chaque rafraîchissement.
    if prop and prop.id ~= Fenetre.propositionVue then
        Fenetre.propositionVue = prop.id
        -- Celle préparée à l'ouverture attend que Dany clique Proposition.
        if not Fenetre.propositionAuto then
            Fenetre.choisirOnglet(Fenetre.T.ongletProposition)
        end
    end
    if not prop then
        Fenetre.montrerPage('proposition', "Aucune proposition en attente.\n\nEn mode « Proposer d'abord », Claude montre ici ce qu'il compte changer et attend votre accord.")
        return
    end
    local lignes = { Texte.nettoyer(prop.texte) ~= '' and prop.texte or "Claude propose :" , '' }
    for _, ch in ipairs(prop.changements or {}) do
        lignes[#lignes + 1] = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
    end
    Fenetre.montrerPage('proposition', table.concat(lignes, '\n'))
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

Fenetre.AIDE_NOTATION = "Claude note d'abord chaque photo qu'il traite, selon le standard, critère par critère (impact, "
    .. "qualités, plancher technique, finition) : sa note arrive à vérifier, vous l'acceptez ou la changez ; 5 ★ reste à vous seul."

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

-- Le texte de la carte Note : les critères et le plafond, puis la raison.
function Fenetre.texteNote(prop)
    local criteres, raison = Fenetre.texteCriteres(prop), texteChamp(prop.raison)
    if criteres ~= '' and raison ~= '' then
        return criteres .. '\n\n' .. raison
    end
    return criteres .. raison
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
        Fenetre.montrerPage('note', Fenetre.texteNote(prop))
    else
        poser(p, 'notationProposee', "Aucune note proposée")
        poser(p, 'notationCouleur', 'gris')
        poser(p, 'notationEtat', '')
        Fenetre.montrerPage('note', Fenetre.AIDE_NOTATION)
    end
    -- Les écritures de la fenêtre échappent à la file du connecteur : pas pendant que Claude
    -- travaille, ni pendant une écriture déjà demandée.
    local libre = not Moteur.travaille and not Fenetre.noteEnCours
    poser(p, 'peutAccepterNote', libre and prop ~= nil and (prop.etat == 'proposee' or prop.etat == 'a_verifier'))
    poser(p, 'peutChangerNote', libre and active ~= nil)
    -- Une proposition qui arrive pour la photo montrée se montre (onglet Note), une seule fois, « à
    -- vérifier » comprise (la plus fréquente, constaté) ; une autre photo choisie ne change pas
    -- d'onglet.
    local cle = prop and (tostring(prop.photo) .. '/' .. tostring(prop.le)) or nil
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
        -- L'écran principal du Mac, lu par le connecteur (une commande du système, 5 s au plus) : à
        -- l'ouverture et au clic sur son voyant seulement, jamais toutes les 2 s.
        Fenetre.poserEcran(Lightroom.etatEcran(prefs.cheminConnecteur))
    end
    local liaison, erreur = Lightroom.liaison()
    poser(p, 'texteLightroom', liaison == 'active' and "Lightroom"
        or (liaison == 'erreur' and "Lightroom · liaison en erreur" or "Lightroom · liaison arrêtée"))
    poser(p, 'etatLightroom', liaison == 'active' and 'ok' or 'erreur')
    if liaison == 'erreur' and tostring(erreur):find('jeton', 1, true) then
        -- Le jeton privé de la liaison (1.2) n'a pas pu être préparé : la liaison refuse tout.
        Fenetre.aideLiaison = "La liaison avec Claude n'a pas pu préparer son jeton privé (" .. tostring(erreur)
            .. ") : cliquez le voyant Lightroom pour la relancer ; le détail est dans ~/Library/Logs/Developpeur/module.log."
    elseif liaison == 'erreur' then
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

-- Le voyant Écran (Lightroom.etatEcran) ; son détail est gardé pour la boîte du clic.
function Fenetre.poserEcran(ecran)
    Fenetre.detailEcran = ecran.detail
    local p = Fenetre.p
    if not p then
        return
    end
    poser(p, 'texteEcran', ecran.texte)
    poser(p, 'etatEcran', ecran.etat)
end

-- Clic sur le voyant Écran (dans une tâche) : l'écran se relit (un autre a pu être branché), puis
-- son détail : profil de couleur, et comment juger les couleurs.
function Fenetre.montrerEcran()
    Fenetre.poserEcran(Lightroom.etatEcran(Chemins.prefs().cheminConnecteur))
    LrDialogs.message("Claude · écran", Fenetre.detailEcran or "Écran pas encore lu.", 'info')
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
-- jointes, sinon rien (le rappel du style est retiré : demandé par Dany le 20 octobre 2026).
function Fenetre.etatBandeau(p)
    if (p.message or '') ~= '' then
        return 'message'
    elseif (p.aide or '') ~= '' then
        return 'aide'
    elseif (p.jointes or '') ~= '' then
        return 'jointes'
    end
    return 'vide'
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
    -- Une autre photo active (ou la première vue à l'ouverture) : son aperçu se montre.
    local id = info.active and info.active.id
    if id ~= Fenetre.idActif then
        Fenetre.idActif = id
        Fenetre.voirActive = true
        Fenetre.rafraichirApercu()
    end
    if info.active then
        p.infoPhoto = string.format("Active : %s     Sélection : %d", Lightroom.nomCourt(info.active.nom), info.selection)
        -- Une note acceptée ou changée qui n'est plus sur la photo (undo_last, ⌘Z) : la proposition
        -- redevient à décider.
        local active = info.active
        LrTasks.pcall(Notation.recaler, { { photo = active.id, note = active.note, drapeau = active.drapeau } }, version)
    else
        p.infoPhoto = "Aucune photo active"
    end
    Fenetre.suivreSelection(info)
    Fenetre.rafraichirNotation()
end

-- Une autre photo active ou une autre sélection, choisie par l'utilisateur, commence une nouvelle
-- conversation (préférence `nouvelleParPhoto`, demandé par Dany le 20 octobre 2026), si celle
-- montrée a déjà des messages et parlait d'autres photos (`c.cle`, posée à chaque demande). Une
-- sélection changée pendant que Claude travaille (show_photo, tri), ou qui l'était encore
-- DELAI_APRES_TRAVAIL secondes avant la fin de son travail, peut être la sienne : elle devient
-- celle de la conversation. `Fenetre.cleVue` et l'heure où elle a été vue (`cleVueLe`) restent
-- d'une ouverture de la fenêtre à l'autre : une photo choisie fenêtre fermée compte aussi, et une
-- fenêtre fermée pendant le travail de Claude retrouve sa conversation à la réouverture.
Fenetre.DELAI_APRES_TRAVAIL = 4

function Fenetre.voirSelection(cle)
    Fenetre.cleVue, Fenetre.cleVueLe = cle, os.time()
end

function Fenetre.suivreSelection(info)
    local cle = info and info.cle
    if not cle then
        return
    end
    local avant, vueLe = Fenetre.cleVue, Fenetre.cleVueLe
    Fenetre.voirSelection(cle)
    if avant == nil or avant == cle then
        return
    end
    local c = Moteur.courante
    -- Claude a travaillé depuis que la sélection d'avant a été vue.
    local fin = Moteur.finTravail or 0
    if Moteur.travaille or (fin > 0 and (not vueLe or fin + Fenetre.DELAI_APRES_TRAVAIL > vueLe)) then
        if c then
            c.cle = cle
        end
        return
    end
    if not Chemins.prefs().nouvelleParPhoto or not c or #(c.elements or {}) == 0 or c.cle == cle then
        return
    end
    Journal.noter("Autre photo choisie : nouvelle conversation")
    Fenetre.nouvelle()
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

-- À l'ouverture de la fenêtre (et quand le menu ou ⌃⌥C la rappelle), Claude prépare une proposition
-- de retouche de la photo active, prête dans l'onglet Proposition (préférence
-- `propositionAOuverture`, demandé par Dany le 20 octobre 2026) : seulement sur une conversation
-- vide (une autre photo en commence une), Claude libre ; l'onglet ne bascule pas vers elle
-- (Fenetre.propositionAuto, effacé par la demande suivante de Dany).
function Fenetre.proposerAOuverture()
    local c = Moteur.courante
    local active = Fenetre.info and Fenetre.info.active
    if not Fenetre.p or not active or Moteur.travaille or not Chemins.prefs().propositionAOuverture
        or (c and #(c.elements or {}) > 0) then
        return false
    end
    Fenetre.envoyer(Consignes.proposerOuverture)
    Fenetre.propositionAuto = true
    return true
end

function Fenetre.envoyer(texte, modele)
    local p = Fenetre.p
    if Moteur.travaille then
        return
    end
    Fenetre.propositionAuto = false
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
        -- La photo active et la sélection de la demande : la conversation est la leur.
        local info = Lightroom.photos()
        -- Le modèle et l'effort des préférences (Gestionnaire de modules externes), sauf le modèle
        -- d'une invite qui en impose un.
        local ok, raison = Moteur.envoyer(texte, { modele = modele, jointes = jointes, style = p.style })
        if ok and Moteur.courante and info.cle then
            Moteur.courante.cle = info.cle
            Fenetre.voirSelection(info.cle)
        end
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
-- le laissent dans le champ, pour une photo jointe par exemple). Une fenêtre fermée entre-temps ne
-- l'envoie pas.
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

-- Construction ---------------------------------------------------------------------------------

function Fenetre.construire(f, p, D)
    Fenetre.p = p
    return Dispositions.construire(f, Fenetre, D)
end

-- Ouverture -----------------------------------------------------------------------------------

-- Le nom du cadre enregistré de la fenêtre. Lightroom rend sa taille enregistrée à la fenêtre et
-- ne la rapetisse pas quand le contenu devient plus petit (bande vide en bas, constaté) : FORME
-- augmente quand le contenu rapetisse. Le nom garde « conversation » et « grande » (la seule
-- disposition, la seule taille) : le cadre déjà enregistré sert encore.
Fenetre.FORME = 1

function Fenetre.cadre()
    return 'DeveloppeurClaude-' .. Dispositions.NOM .. '-grande-' .. Fenetre.FORME
end

function Fenetre.desabonner()
    Moteur.desabonner('fenetre')
    Notation.desabonner('fenetre')
end

-- Boucle d'une fenêtre (sa génération : une fenêtre rouverte a la sienne, l'ancienne boucle
-- s'arrête) : rafraîchit ce que le moteur a changé, la note, l'activité, et les voyants.
-- Toutes les 2 s : les voyants et la photo active (la liaison, lue dans ce module sans commande
-- du système, peut démarrer ou s'arrêter par le menu). Claude Code et l'écran, lus par des
-- commandes du système, ne se relisent qu'à l'ouverture (et l'écran au clic sur son voyant).
function Fenetre.periodique()
    LrTasks.pcall(Fenetre.verifier, false)
    LrTasks.pcall(Fenetre.majPhoto)
end

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
            if tic % 8 == 0 then
                Fenetre.periodique()
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
    p.notationTexte = ''
    p.peutAccepterNote = false
    p.peutChangerNote = false
end

function Fenetre.afficher()
    if Fenetre.ouverte then
        if Fenetre.controle and Fenetre.controle.toFront then
            Fenetre.controle.toFront()
            -- Rouverte par le menu ou ⌃⌥C : l'aperçu remontre la photo active, refait.
            Fenetre.idActif, Fenetre.apercuActif = nil, nil
            LrTasks.startAsyncTask(function()
                LrTasks.pcall(Fenetre.majPhoto)
                LrTasks.pcall(Fenetre.proposerAOuverture)
            end)
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
                Fenetre.p = nil
                Fenetre.desabonner()
            end
            Journal.noter("Fenêtre :", tostring(erreur))
            LrDialogs.message("La fenêtre Claude n'a pas pu s'ouvrir", tostring(erreur), 'critical')
        end)

        Moteur.charger()
        local prefs = Chemins.prefs()
        local D = Dispositions.dimensions()
        Fenetre.T = D
        Fenetre.cache = {}
        Fenetre.vignettes = {}
        Fenetre.conversationAffichee = nil
        Fenetre.signatureListe = nil
        Fenetre.defilement = 0
        Fenetre.indiceImage = nil
        -- À l'ouverture, l'aperçu montre la photo active, refait (Fenetre.majPhoto).
        Fenetre.idActif, Fenetre.apercuActif, Fenetre.demandeActive, Fenetre.voirActive = nil, nil, nil, true
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
        p.style = Consignes.style(prefs.styleChoisi) and prefs.styleChoisi or 'standard'
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
        -- Gris tant que le connecteur ne l'a pas dit (Fenetre.verifier, à l'ouverture).
        p.texteEcran = "Écran"
        p.etatEcran = 'neutre'
        p.infoPhoto = ''
        p.imageApercu = Fenetre.imageVide()
        p.legendeApercu = ''
        p.aProposition = false
        p.enAttente = false
        p.propositionTexte = ''
        for _, cle in ipairs({ 'note', 'proposition' }) do
            p[cle .. 'Monte'], p[cle .. 'Descend'] = false, false
        end
        p.aide = ''
        p.bandeau = Fenetre.etatBandeau(p)
        for i, l in ipairs(Composants.lignes(Composants.module(), '…')) do
            p['versionNom' .. i], p['version' .. i], p['versionAlerte' .. i] = l.nom, l.version, false
        end
        p.activite = Moteur.texteTravail(0)
        p.listeConversations = {}
        p.selectionListe = {}
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
        p:addObserver('recherche', function()
            Fenetre.annulerEnvoiAuto()
            Fenetre.rafraichirListe()
        end)
        p:addObserver('style', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Chemins.prefs().styleChoisi = valeur
        end)
        -- Un clic sur un onglet n'envoie pas la demande validée par le clic.
        p:addObserver('onglet', function()
            if not Fenetre.ongletAuto then
                Fenetre.annulerEnvoiAuto()
            end
        end)
        p:addObserver('saisie', function(_, _, valeur) Fenetre.saisieValidee(valeur) end)
        for _, cle in ipairs({ 'message', 'aide', 'jointes' }) do
            p:addObserver(cle, function(proprietes) poser(proprietes, 'bandeau', Fenetre.etatBandeau(proprietes)) end)
        end

        local contenu = Fenetre.construire(f, p, D)
        Fenetre.rafraichir()
        Fenetre.majPhoto()
        Fenetre.proposerAOuverture()
        Fenetre.rafraichirMode()
        Moteur.abonner('fenetre', function() Fenetre.aRafraichir = true end)
        Notation.abonner('fenetre', function() Fenetre.aRafraichirNotation = true end)

        LrTasks.startAsyncTask(function() Fenetre.boucle(generation) end)
        LrTasks.startAsyncTask(function() LrTasks.pcall(Fenetre.verifier, true) end)

        LrDialogs.presentFloatingDialog(_PLUGIN, {
            -- « Développeur » (demandé par Dany le 20 octobre 2026) ; les autres fenêtres du module
            -- gardent « Claude · … ».
            title = "Développeur",
            contents = contenu,
            save_frame = Fenetre.cadre(),
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
        end
    end)
end

return Fenetre
