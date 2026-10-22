-- Fenetre.lua : la fenêtre Claude du module Développeur (« Développeur » dans sa barre de titre ;
-- fenêtre flottante, non bloquante) :
-- une conversation avec Claude Code (le fil avec les appels d'outils, les invites en raccourcis et
-- la demande), ce que Claude regarde, sa proposition à accepter, refuser, ajuster ou faire soi-même
-- (Je le fais, 1.3), le cadre qu'il propose (Composition lue, 1.3 : la ligne « Cadre : … » de la
-- carte, son image entière en pointillés dans l'aperçu, ses ajustements dans Ajuster…), la note
-- qu'il propose pour la photo active, le pourquoi de chaque étape (onglet Aperçu, l'ancien
-- Pourquoi ?, 1.3), la mise au point de la photo active comme Focus-Points la montre (onglet Focus,
-- demandé par Dany le 22 octobre 2026), la leçon de la photo (onglet Leçon, 1.3), et les versions
-- du module et du connecteur MCP-Développeur.
--
-- Une seule disposition, la Conversation claire, à l'allure de la fenêtre B (1.3 : 1 948 × 1 200,
-- volet des conversations en cases, en-tête avec le Mode, segments et panneau à droite ; l'Atelier,
-- le Panneau et le choix de la disposition sont retirés : demandé par Dany le 20 octobre 2026).
-- Dispositions.lua l'assemble des pièces de Vues.lua ; ce fichier garde l'état, ce qui remplit les
-- propriétés liées (rafraichir…), les actions, la boucle et l'ouverture. Ses couleurs et ses
-- images suivent l'apparence choisie dans le Gestionnaire, reprise à chaque ouverture
-- (Fenetre.preparerApparence).
--
-- Le SDK ne sait ni ajouter de vues à une fenêtre ouverte ni la faire défiler par programme, et
-- une vue masquée garde sa place : le fil est une grille de lignes fixes (Fil.lua), remplie à
-- chaque changement et parcourue par les boutons ▲ ▼, comme la liste des conversations, une
-- grille de cases (Fenetre.casesListe) ; chaque ligne a sa colonne auteur (« Vous », « Claude »,
-- l'heure) et superpose une variante de texte par genre (police, couleur, retrait), dont une seule
-- est visible, « Pourquoi ? » sur une étape et les boutons d'actions (Vues.ligneFil). Lightroom ne
-- masque que les vues simples (`visible` sur une rangée, une colonne ou une boîte reste sans
-- effet, constaté) : les onglets sont des segments en
-- images sous des calques, au-dessus de variantes superposées de même largeur, dont chaque vue
-- simple porte la condition de son onglet (Vues.masquable). Un clic sur une image passe par un
-- calque (Fenetre.calque) ; il n'y a aucun bouton par défaut. Une autre photo active ou une autre
-- sélection, choisie par l'utilisateur, commence une nouvelle conversation (Fenetre.suivreSelection).
--
-- Structure de la 1.3, posée une fois (les lots suivants remplissent les crochets) : cinq onglets
-- (Aperçu, Focus, Proposition, Note, Leçon ; Focus depuis le 22 octobre 2026) ; l'aperçu est
-- commun, mais un onglet peut le remplir
-- (Fenetre.apercuOnglet), un vrai clic sur un onglet a son crochet (Fenetre.surOnglet) ; un clic
-- sur une ligne du fil se répartit dans un ordre fixé (Fenetre.cliquerLigne) ; le fil montre la
-- conversation ou une autre page (Fenetre.vue), et Claude qui travaille ramène à la conversation.
-- L'autre page est celle du Carnet de progrès (1.3, section « Carnet de progrès » : son entrée en
-- tête de la liste des conversations, ses lignes faites par Fil.lignesCarnet), sans pièce de mise
-- en page à elle.

local LrBinding = import 'LrBinding'
local LrColor = import 'LrColor'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'

local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Composants = require 'Composants'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Etapes = require 'Etapes'
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

local Fenetre = { ouverte = false, defilement = 0, jointes = {}, cache = {}, vignettes = {}, generation = 0, vue = 'conversation' }

-- Couleurs, polices, images, icônes et variantes des lignes, pour les pièces (Vues.lua).

-- Les couleurs : celles de la palette de l'apparence (Dispositions.PALETTES, aux mêmes clés : texte,
-- gris, grisEntete, sousTitreChoisi, bleu, mono, coche, orange, rouge, ambre, blanc, titreInactif,
-- les fonds, les filets…), en LrColor. La table est la même d'une ouverture à l'autre ; ses
-- couleurs se refont à chaque ouverture (Fenetre.preparerApparence), pour qu'une apparence choisie
-- dans le Gestionnaire vaille à l'ouverture suivante. Au chargement : la claire.
local COULEURS = {}
Fenetre.COULEURS = COULEURS

-- L'apparence de la fenêtre ouverte ('claire' ou 'sombre', Dispositions.APPARENCES) : ses couleurs
-- et le jeu de ses images (Fenetre.image).
function Fenetre.preparerApparence(valeur)
    Fenetre.apparence = Dispositions.apparence(valeur)
    for cle in pairs(COULEURS) do
        COULEURS[cle] = nil
    end
    for cle, t in pairs(Dispositions.couleurs(Fenetre.apparence)) do
        COULEURS[cle] = LrColor(t[1], t[2], t[3])
    end
    return Fenetre.apparence
end
Fenetre.preparerApparence(nil)

-- Le chemin d'une image de Dispositions.IMAGES dans le jeu de l'apparence (jamais
-- 'images/<nom>.png' écrit en dur), et sa taille en points.
function Fenetre.image(nom)
    return Chemins.ressource(Dispositions.image(nom, Fenetre.apparence))
end

function Fenetre.tailleImage(nom)
    local t = Dispositions.IMAGES[nom]
    if not t then
        error("image inconnue de Dispositions.IMAGES : " .. tostring(nom), 2)
    end
    return t
end

local function police(cle)
    local m = Metriques[cle]
    return { name = m.nom, size = m.taille }
end

-- Les polices de la fenêtre, toutes mesurées dans Metriques.lua (scripts/metriques.swift) : celle
-- du système de la maquette, '<system>' et '<system/bold>' en 16, 13, 12 et 11 (constatées le
-- 21 octobre 2026, B1 et D9 : tailles appliquées, l'encre à 1 ou 2 points sous la chasse mesurée),
-- et Menlo 11. Le fil et les cartes les emploient par leurs clés de Metriques (texte, texte12,
-- petit, gras, gras12, gras11, titre, mono) ; les pièces de la fenêtre B, aussi par leurs noms
-- systeme13…
local POLICES = {
    texte = police('texte'),
    texte12 = police('texte12'),
    petit = police('petit'),
    gras = police('gras'),
    gras12 = police('gras12'),
    gras11 = police('gras11'),
    titre = police('titre'),
    mono = police('mono'),
    systeme13 = police('texte'),
    systeme12 = police('texte12'),
    systeme11 = police('petit'),
    systemeGras12 = police('gras12'),
    systemeGras11 = police('gras11'),
}
Fenetre.POLICES = POLICES

-- La largeur d'un libellé fixe (une étiquette, une passe de la carte Note) dans une police de
-- Metriques, en points entiers : sa chasse mesurée, et 2 points de jeu (l'encre fait 1 à 2 points
-- de moins que la chasse, constaté D9).
function Fenetre.largeurLibelle(texte, cle)
    return math.ceil(Fil.largeur(texte, cle)) + 2
end

-- Icônes du fil, au bord gauche de la colonne du texte (couleurs de la palette). Plus de › devant
-- Dany : la colonne auteur dit « Vous » (fenêtre B).
Fenetre.ICONES = {
    { cle = 'ok', glyphe = '✓', couleur = 'coche' },
    { cle = 'cours', glyphe = '●', couleur = 'orange' },
    { cle = 'erreur', glyphe = '✕', couleur = 'rouge' },
    { cle = 'apercu', glyphe = '▣', couleur = 'bleu' },
    { cle = 'proposition', glyphe = '●', couleur = 'orange' },
    { cle = 'note', glyphe = 'ⓘ', couleur = 'gris' },
}

-- Variantes de texte d'une ligne, selon son genre : police et couleur, retrait (celui des genres
-- qui portent une icône, Fil.RETRAITS), et pour la ligne d'un appel d'outil, l'emphase (le nom de
-- l'outil en Menlo 11, sur une description en petit gris, Fil.emphases). Les genres d'une variante
-- ont le même retrait. Le genre 'actions' n'a pas de texte : ses boutons (Vues.ligneFil).
local function style(genres, policeDuTexte, couleur, plus)
    local premier = next(genres)
    local s = { genres = genres, police = policeDuTexte, couleur = couleur, retrait = Fil.retrait(premier) }
    for cle, valeur in pairs(plus or {}) do
        s[cle] = valeur
    end
    return s
end

Fenetre.STYLES = {
    style({ claude = true, vide = true }, 'texte', 'texte'),
    style({ titre = true }, 'gras', 'texte'),
    style({ dany = true }, 'texte', 'bleu'),
    style({ outil = true }, 'mono', 'mono'),
    style({ appel = true }, 'texte12', 'gris', { emphase = Fil.emphases.appel, couleurEmphase = 'texte' }),
    style({ apercu = true }, 'texte', 'bleu'),
    style({ proposition = true }, 'gras', 'orange'),
    style({ note = true }, 'texte', 'gris'),
}

-- Pastilles des voyants (Claude Code, Lightroom, écran), en images par état : plus de pastille
-- bleue, le voyant Mode est retiré (le Mode est dans l'en-tête).
Fenetre.PASTILLES = { ok = 'pastille-vert', attention = 'pastille-orange', erreur = 'pastille-rouge', neutre = 'pastille-gris' }
Fenetre.ETATS_VOYANT = { 'ok', 'attention', 'erreur', 'neutre' }

-- L'infobulle d'un élément de la maquette sans fonction encore (Vues.inactif).
Fenetre.A_VENIR = "À venir"

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
-- qui ne doit pas partir ensuite ; le bouton décide. Trois clés à lui, retirées avant de créer la
-- vue : `carre` (un f:square_button, le rectangle blanc à bord fin des boutons de la maquette,
-- constaté le 21 octobre 2026, B3), `icone` (le nom d'une image de Dispositions.IMAGES, posée par
-- image_name, sans titre : elle chevaucherait le titre, constaté B3) et `bezel` (la hauteur
-- visible voulue : le cadre a 2 points de plus, constaté D5).
function Fenetre.bouton(f, args)
    local carre, icone, bezel = args.carre, args.icone, args.bezel
    args.carre, args.icone, args.bezel = nil, nil, nil
    if icone then
        args.image_name = Fenetre.image(icone)
        args.title = nil
    end
    if bezel then
        args.height = Dispositions.cadreBouton(bezel)
    end
    local action = args.action
    args.action = function(...)
        Fenetre.annulerEnvoiAuto()
        return action(...)
    end
    parBouton[args.action] = true
    if carre then
        return f:square_button(args)
    end
    return f:push_button(args)
end

function Fenetre.parBouton(action)
    return parBouton[action] == true
end

-- Les mouse_down des calques passés par Fenetre.calque (les essais vérifient que tous y passent).
local parCalque = setmetatable({}, { __mode = 'k' })

-- Un calque : un texte vide de taille fixe posé sur une image, qui en reçoit le clic (un f:picture
-- n'en reçoit aucun ; le calque, si : constaté le 21 octobre 2026, C1). Son clic valide aussi le
-- champ de demande (constaté D3) : il annule l'envoi automatique, comme un bouton. Un calque n'a
-- pas d'enabled : chaque gestionnaire vérifie lui-même l'état (Claude au travail…).
function Fenetre.calque(f, args)
    local fn = args.mouse_down
    args.title = ''
    args.mouse_down = function(...)
        Fenetre.annulerEnvoiAuto()
        return fn(...)
    end
    parCalque[args.mouse_down] = true
    return f:static_text(args)
end

function Fenetre.parCalque(fn)
    return parCalque[fn] == true
end

-- La valeur liée d'un bouton radio (clé `cle`), ou du menu Mes demandes. Un clic de l'utilisateur
-- la pousse de la vue vers la table, et ce clic a validé le champ de demande (constaté le
-- 21 octobre 2026, D3, pour un radio ; supposé pour un menu) : l'envoi automatique s'annule ici, à
-- chaque clic. L'observateur de la clé ne suffit pas : sur un radio déjà coché (ou le titre du menu
-- rechoisi), la valeur ne change pas et la table ne prévient pas ses observateurs (supposé, comme
-- la simulation), et la demande tapée partirait 0,3 s plus tard. La fenêtre qui pose la valeur
-- (de la table vers la vue) n'annule rien.
function Fenetre.lierRadio(cle)
    return bind {
        key = cle,
        transform = function(valeur, depuisTable)
            if not depuisTable then
                Fenetre.annulerEnvoiAuto()
            end
            return valeur
        end,
    }
end

-- La valeur liée du champ de demande (Vues.saisie). Une demande que Mes demandes y a mise
-- (Fenetre.demandeMise, Fenetre.mettreDemande) part par Retour comme une demande tapée : validé
-- sans y rien changer, le champ ne change pas la clé, et la table ne prévient pas son observateur
-- (supposé, comme la simulation) ; la valeur poussée du champ vers la table passe ici, et lance
-- l'envoi automatique (Fenetre.saisieValidee). Tapée ou changée, la demande passe par
-- l'observateur de la clé, comme avant.
function Fenetre.lierSaisie()
    return bind {
        key = 'saisie',
        transform = function(valeur, depuisTable)
            local p = Fenetre.p
            if not depuisTable and Fenetre.demandeMise ~= nil and valeur == Fenetre.demandeMise and p and p.saisie == valeur then
                Fenetre.saisieValidee(valeur)
            end
            return valeur
        end,
    }
end

-- Ce que montre la ligne d'actions d'un tour de Claude (Vues.ligneFil) : sa base et « ＋ Garder la
-- demande » (Fil.lireActions).
Fenetre.lireActions = Fil.lireActions

-- Une clé de la fenêtre que pose une pièce elle-même (l'enfoncement d'un bouton bleu) : sa valeur
-- avant l'ouverture, comme toute clé liée.
function Fenetre.preparerCle(cle, valeur)
    if Fenetre.p and Fenetre.p[cle] == nil then
        Fenetre.p[cle] = valeur
    end
end

-- L'image enfoncée d'un bouton bleu, 0,15 s (Vues.boutonBleu).
Fenetre.DUREE_ENFONCE = 0.15

function Fenetre.enfoncer(cle)
    local p = Fenetre.p
    if not p then
        return
    end
    p[cle] = true
    LrTasks.startAsyncTask(function()
        LrTasks.sleep(Fenetre.DUREE_ENFONCE)
        if Fenetre.p == p then
            p[cle] = false
        end
    end)
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

-- Un texte sans balise <EM> (le titre d'une conversation, le nom d'une photo) : posé tel quel
-- dans un texte riche ou dans un texte simple, il ne doit jamais en ouvrir une.
local function sansBalises(texte)
    return (tostring(texte or ''):gsub('</?EM>', ''))
end
Fenetre.sansBalises = sansBalises

local function memeJour(a, b)
    return a.year == b.year and a.month == b.month and a.day == b.day
end

-- La période d'une conversation dans la liste, d'après sa date (heure locale, os.date par
-- Compat) : « Aujourd'hui », « Hier », « Plus tôt en octobre » (le mois en cours), puis le mois et
-- l'année (« Septembre 2026 »). Les mois viennent de Carnet.MOIS, leur seule copie.
function Fenetre.periodeListe(t, maintenant)
    maintenant = maintenant or os.time()
    local d, m = os.date('*t', t), os.date('*t', maintenant)
    if memeJour(d, m) then
        return "Aujourd'hui"
    end
    -- La veille, comptée depuis midi (un changement d'heure ne la fait pas manquer).
    local midi = os.time({ year = m.year, month = m.month, day = m.day, hour = 12, min = 0, sec = 0 })
    if memeJour(d, os.date('*t', midi - 86400)) then
        return "Hier"
    end
    local mois = Carnet.MOIS[d.month] or ''
    if d.year == m.year and d.month == m.month then
        return "Plus tôt en " .. mois
    end
    return mois:sub(1, 1):upper() .. mois:sub(2) .. ' ' .. tostring(d.year)
end

-- Le sous-titre d'une conversation dans la liste : l'heure (« 19 h 46 ») pour aujourd'hui et
-- hier, sinon la date courte (« 12 oct. », Carnet.MOIS_COURTS) ; puis le nombre de photos de sa
-- sélection, tiré du 2e champ de sa clé (c.cle, Lightroom.photos : « 1 photo », « 48 photos » ;
-- rien sans clé).
function Fenetre.sousTitreListe(c, maintenant)
    local morceaux = {}
    local t = c.modifiee or c.creee
    if type(t) == 'number' then
        local d = os.date('*t', t)
        local p = Fenetre.periodeListe(t, maintenant)
        if p == "Aujourd'hui" or p == "Hier" then
            morceaux[#morceaux + 1] = Fil.heure(t)
        else
            morceaux[#morceaux + 1] = tostring(d.day) .. ' ' .. tostring(Carnet.MOIS_COURTS[d.month] or '')
        end
    end
    local n = type(c.cle) == 'string' and tonumber(c.cle:match('^[^:]*:(%d+)')) or nil
    if n then
        morceaux[#morceaux + 1] = n .. (n > 1 and " photos" or " photo")
    end
    return table.concat(morceaux, ' · ')
end

-- La valeur d'un en-tête de période commence par ENTETE ; celle de l'entrée de la page du carnet
-- est Fenetre.CARNET (section « Carnet de progrès »), qui n'en est pas un.
local ENTETE = '§'

-- Éléments de la liste : l'entrée « Carnet de progrès » en tête (1.3 ; montrée aussi quand la
-- recherche la trouve), puis en-têtes de période et conversations trouvées (tables neuves, sans
-- métatable : Lightroom bloque sur une table relue par Json.decode). Chacun : genre ('carnet',
-- 'jour', 'conversation'), title, value (Fenetre.CARNET, ENTETE .. période, ou l'id), sousTitre.
function Fenetre.elementsListe(recherche, maintenant)
    local items = {}
    local courante = Moteur.courante
    local dejaVue = false
    local derniere
    for _, c in ipairs(Moteur.conversations) do
        if c == courante then
            dejaVue = true
        end
        if not estSeance(c) and Conversation.correspond(c, recherche or '') then
            local p = Fenetre.periodeListe(c.modifiee or c.creee or os.time(), maintenant)
            if p ~= derniere then
                items[#items + 1] = { genre = 'jour', title = p, value = ENTETE .. p }
                derniere = p
            end
            items[#items + 1] = { genre = 'conversation', title = sansBalises(c.titre), value = c.id,
                sousTitre = Fenetre.sousTitreListe(c, maintenant) }
        end
    end
    if courante and not dejaVue and not estSeance(courante) then
        table.insert(items, 1, { genre = 'conversation', title = sansBalises(courante.titre or Conversation.TITRE_PAR_DEFAUT),
            value = courante.id, sousTitre = Fenetre.sousTitreListe(courante, maintenant) })
    end
    if Conversation.correspond({ titre = Fenetre.TITRE_CARNET }, recherche or '') then
        table.insert(items, 1, { genre = 'carnet', title = Fenetre.TITRE_CARNET, value = Fenetre.CARNET,
            sousTitre = Fenetre.SOUS_TITRE_CARNET })
    end
    return items
end

-- Les cases d'une page de la liste (une grille fixe : pas de défilement natif) : `n` cases, tables
-- neuves de genre 'carnet', 'jour', 'conversation', 'plus' (« Plus récentes… » en tête d'une page
-- qui en suit une autre, « Plus anciennes… » dans la dernière case d'une page qui en précède une,
-- avec `vers`, la page qu'elle montre) ou 'vide'. Un en-tête de jour ne finit jamais une page : il
-- passe à la suivante, avec ses conversations. Rend les cases et la page montrée (une page
-- au-delà de la dernière montre la dernière). Pure.
function Fenetre.casesListe(elements, page, n)
    local total = #elements
    page = math.max(1, math.floor(tonumber(page) or 1))
    local debut, numero = 1, 1
    while true do
        local avant = numero > 1
        local place = n - (avant and 1 or 0)
        local apres = total - debut + 1 > place
        if apres then
            place = place - 1
            while place > 1 and elements[debut + place - 1].genre == 'jour' do
                place = place - 1
            end
        end
        if numero >= page or not apres then
            local cases = {}
            if avant then
                cases[#cases + 1] = { genre = 'plus', title = "Plus récentes…", vers = numero - 1 }
            end
            for i = debut, math.min(total, debut + place - 1) do
                local e = elements[i]
                cases[#cases + 1] = { genre = e.genre, title = e.title, value = e.value, sousTitre = e.sousTitre }
            end
            -- Les cases vides avant « Plus anciennes… », toujours dans la dernière case.
            while #cases < n - (apres and 1 or 0) do
                cases[#cases + 1] = { genre = 'vide' }
            end
            if apres then
                cases[#cases + 1] = { genre = 'plus', title = "Plus anciennes…", vers = numero + 1 }
            end
            return cases, numero
        end
        debut = debut + place
        numero = numero + 1
    end
end

-- Remplit les cases de la liste (Vues.caseListe) : genre, titre, sous-titre, choix et infobulle de
-- chacune. La case choisie suit la vue (Fenetre.vue) : l'entrée du carnet sur sa page, sinon la
-- conversation montrée. La page de la liste (Fenetre.pageListe) se garde ; la recherche la remet à
-- la première.
function Fenetre.rafraichirListe()
    local p, T = Fenetre.p, Fenetre.T
    if not (p and T) then
        return
    end
    local cases, page = Fenetre.casesListe(Fenetre.elementsListe(p.recherche), Fenetre.pageListe, T.cases)
    Fenetre.pageListe, Fenetre.cases = page, cases
    local courante = Moteur.courante
    for k = 1, T.cases do
        local case = cases[k]
        local choisie = (case.genre == 'carnet' and Fenetre.vue == 'carnet')
            or (case.genre == 'conversation' and Fenetre.vue ~= 'carnet' and courante ~= nil and case.value == courante.id)
        poser(p, 'lg' .. k, case.genre)
        poser(p, 'lt' .. k, case.title or '')
        poser(p, 'ls' .. k, case.sousTitre or '')
        poser(p, 'lc' .. k, choisie == true)
        poser(p, 'li' .. k, case.genre == 'vide' and '' or (case.title or ''))
    end
end

-- La case choisie (sa valeur : l'id de la conversation, ou Fenetre.CARNET), nil sans case choisie.
function Fenetre.choixListe()
    local p = Fenetre.p
    for k, case in ipairs(Fenetre.cases or {}) do
        if p and p['lc' .. k] then
            return case.value
        end
    end
    return nil
end

-- Clic sur la case k (son calque, Vues.caseListe) : l'entrée du carnet ouvre sa page, une
-- conversation s'ouvre (Fenetre.choisirDansListe), « Plus anciennes… » ou « Plus récentes… »
-- changent de page ; un en-tête de jour ou une case vide ne font rien. Un calque n'a pas d'enabled :
-- pendant que Claude travaille, le clic est refusé et le bandeau le dit. Rend vrai si le clic a agi.
function Fenetre.cliquerListe(k)
    Fenetre.annulerEnvoiAuto()
    local p = Fenetre.p
    local case = Fenetre.cases and Fenetre.cases[k]
    if not (p and case) or case.genre == 'vide' or case.genre == 'jour' then
        return false
    end
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        return false
    end
    if case.genre == 'plus' then
        Fenetre.pageListe = case.vers
        Fenetre.rafraichirListe()
        return true
    end
    if case.genre == 'carnet' then
        return Fenetre.ouvrirCarnet()
    end
    return Fenetre.choisirDansListe(case.value)
end

-- Choix d'une valeur de la liste : l'entrée du carnet ouvre sa page ; une conversation s'ouvre et
-- ramène au fil (la conversation déjà ouverte aussi, choisie depuis la page) ; un en-tête, ou un
-- refus (le bandeau dit pourquoi), ne change rien (la page reste). Rend vrai si le choix a agi.
function Fenetre.choisirDansListe(valeur)
    local id = type(valeur) == 'table' and valeur[1] or valeur
    if id == nil then
        return false
    end
    if id == Fenetre.CARNET then
        return Fenetre.ouvrirCarnet()
    end
    if type(id) == 'string' and id:sub(1, #ENTETE) == ENTETE then
        return false
    end
    if Moteur.courante and id == Moteur.courante.id then
        Fenetre.quitterCarnet()
        Fenetre.rafraichirListe()
        return true
    end
    local ok, raison = Moteur.ouvrir(id)
    if not ok then
        Fenetre.p.message = raison or ''
        Fenetre.rafraichirListe()
        return false
    end
    Fenetre.quitterCarnet()
    Fenetre.defilement = 0
    Fenetre.indiceImage = nil
    Fenetre.imageCliquee = nil
    Fenetre.etape = nil
    Fenetre.p.message = ''
    Fenetre.rafraichirListe()
    return true
end

-- Nouvelle conversation (le bouton) : elle se montre, la page du carnet se quitte. `garderPage` :
-- une autre photo choisie dans Lightroom (Fenetre.suivreSelection) la prépare sans quitter la
-- page du carnet, que Dany lit ; elle se montre au retour au fil. Rend vrai si elle est prête.
function Fenetre.nouvelle(garderPage)
    local ok, raison = Moteur.nouvelle()
    if not ok then
        if Fenetre.p then
            Fenetre.p.message = raison or ''
        end
        return false
    end
    if not (garderPage and Fenetre.vue == 'carnet') then
        Fenetre.quitterCarnet()
        Fenetre.defilement = 0
    end
    -- La nouvelle conversation est en tête de la liste : sa première page.
    Fenetre.pageListe = 1
    Fenetre.indiceImage = nil
    Fenetre.imageCliquee = nil
    Fenetre.etape = nil
    Fenetre.aRafraichir = true
    return true
end

-- Fil -----------------------------------------------------------------------------------------

-- Ce que montre la grille du fil : la conversation ('conversation', par défaut et à chaque
-- ouverture) ou une autre page (la page Carnet de progrès, 'carnet'). Claude qui
-- travaille ramène à la conversation (Fenetre.rafraichir) : une demande partie d'ailleurs que le
-- champ (Accepter, Refuser, Ajuster…, Je le fais, J'ai fini) se suit dans le fil.
-- Rend vrai si la vue a changé ; le fil se relit alors depuis la fin. La conversation montrée
-- (Fenetre.conversationAffichee) reste la même : ce qui la suit (l'étape choisie de l'onglet
-- Aperçu, remise quand elle change) n'est pas perdu par un aller-retour vers une autre page.
function Fenetre.revenirAuFil()
    if Fenetre.vue == 'conversation' then
        return false
    end
    Fenetre.vue = 'conversation'
    Fenetre.defilement = 0
    Fenetre.cache = {}
    Fenetre.total = nil
    -- Le bandeau qui disait de choisir une conversation (Renommer…, Supprimer… sur la page du
    -- carnet) ne vaut plus sur le fil.
    if Fenetre.p and Fenetre.p.message == Fenetre.CHOISIR_CONVERSATION then
        Fenetre.p.message = ''
    end
    return true
end

-- La largeur du texte d'une ligne du fil (648) : la largeur utile du centre, sans la colonne auteur
-- et son écart (Vues.ligneFil, D.texteFil). L'icône et le retrait des genres qui en portent une
-- sont dans cette largeur (Fil.RETRAITS).
function Fenetre.largeurTexte()
    return Fenetre.T.texteFil
end

-- Le fil d'une conversation vide : un titre, puis l'aide (sur plus d'une ligne : 648 points, le
-- retrait d'une note ôté, ne la tiennent pas sur une seule).
Fenetre.FIL_VIDE_TITRE = "Demandez à Claude."
Fenetre.FIL_VIDE = "Claude voit la photo active et la sélection de Lightroom, et retouche avec le connecteur MCP-Développeur."

function Fenetre.rafraichirFil()
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    local lignes
    local carnet = Fenetre.vue == 'carnet'
    if carnet then
        -- La page du carnet : la conversation montrée (Fenetre.conversationAffichee) ne change pas,
        -- pour que le retour au fil garde ce qui la suit (l'étape choisie de l'onglet Aperçu).
        -- La page se lit depuis son haut : sa place se compte en lignes au-dessus de la grille
        -- (Fenetre.hautCarnet), gardée quand elle se relit.
        lignes = Fil.lignesCarnet(Fenetre.pageCarnet, Fenetre.largeurTexte(), Fenetre.TITRE_CARNET)
        Fenetre.defilement = math.max(0, #lignes - T.lignes - (Fenetre.hautCarnet or 0))
    else
        local c = Moteur.courante
        if Fenetre.conversationAffichee ~= c then
            Fenetre.defilement = 0
            Fenetre.cache = {}
            Fenetre.total = nil
            -- L'étape choisie (onglet Aperçu) était de l'autre conversation.
            Fenetre.etape = nil
        end
        lignes = c and Fil.lignes(c, Fenetre.largeurTexte(), Fenetre.cache) or {}
        -- Lecteur remonté dans le fil : ce qui arrive ne déplace pas ce qu'il lit.
        if Fenetre.defilement > 0 and Fenetre.total and #lignes > Fenetre.total then
            Fenetre.defilement = Fenetre.defilement + (#lignes - Fenetre.total)
        end
        Fenetre.conversationAffichee = c
        Fenetre.total = #lignes
    end
    Fenetre.lignes = lignes
    local premiere, defilement = Fil.fenetre(#lignes, T.lignes, Fenetre.defilement)
    Fenetre.defilement = defilement
    Fenetre.premiere = premiere
    if carnet then
        Fenetre.hautCarnet = premiere - 1
    end
    -- Chaque ligne : son texte, son genre et son icône ; sa colonne auteur (`a..i` : 'dany',
    -- 'claude', 'heure' ou rien ; l'heure dans `h..i`) ; « Pourquoi ? » (`q..i`, une étape) ; ses
    -- actions (`x..i` : 'note', 'lecon', 'les deux' ou rien).
    for i = 1, T.lignes do
        local l = lignes[premiere + i - 1]
        poser(p, 't' .. i, l and l.texte or '')
        poser(p, 'g' .. i, l and l.genre or 'vide')
        poser(p, 'i' .. i, l and l.icone or '')
        poser(p, 'a' .. i, l and (l.auteur or (l.heure and 'heure')) or '')
        poser(p, 'h' .. i, l and l.heure or '')
        poser(p, 'q' .. i, l ~= nil and l.etape == true)
        poser(p, 'x' .. i, l and l.actions or '')
    end
    if #lignes == 0 then
        poser(p, 't2', Fenetre.FIL_VIDE_TITRE)
        poser(p, 'g2', 'titre')
        -- L'aide coupée comme une ligne du fil (genre note, son retrait compris) : entière, sans « … ».
        local aide = Fil.couper(Fenetre.FIL_VIDE, Fenetre.largeurTexte() - Fil.MARGE - Fil.retrait('note'), Fil.polices.note)
        for k, t in ipairs(aide) do
            if 2 + k <= T.lignes then
                poser(p, 't' .. (2 + k), t)
                poser(p, 'g' .. (2 + k), 'note')
            end
        end
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
    -- Sur la page du carnet, sa place se garde depuis le haut (Fenetre.rafraichirFil).
    if Fenetre.vue == 'carnet' and Fenetre.T then
        Fenetre.hautCarnet = math.max(0, #(Fenetre.lignes or {}) - Fenetre.T.lignes - Fenetre.defilement)
    end
    Fenetre.rafraichirFil()
end

-- Clic sur une ligne du fil, réparti dans un ordre fixé (1.3) : une image (montrée dans l'aperçu,
-- prioritaire sur l'aperçu de l'onglet), une ligne de la page Carnet de progrès (la rangée d'un
-- défaut, `defaut`, ou une action, `action`), une ligne de leçon, une étape de Claude (onglet
-- Aperçu), sinon le détail d'un outil. Fenetre.sorteDeClic dit laquelle,
-- Fenetre.clics[sorte](l, e) la traite. Une rangée du tableau du carnet ouvre la fenêtre de ses
-- photos, sa ligne d'action demande à Claude ce qu'il en pense (section « Carnet de progrès ») ;
-- une ligne d'une leçon (en préparation, ou refusée) ouvre le détail de son appel ; une étape (la
-- ligne d'un appel qui porte « Pourquoi ? », Conversation.estEtape) s'ouvre dans l'onglet Aperçu
-- (Fenetre.montrerEtape), comme par son bouton (Fenetre.pourquoi). La ligne d'actions d'une
-- notation ou d'une leçon n'a pas de texte : ses boutons (Fenetre.voirNote, Fenetre.voirLecon).
function Fenetre.estEtape(e)
    return Conversation.estEtape(e)
end

function Fenetre.sorteDeClic(l, e)
    if l.image then
        return 'image'
    elseif l.defaut ~= nil or l.action ~= nil then
        return 'carnet'
    elseif l.genre == 'actions' then
        return nil
    elseif e and e.genre == 'lecon' then
        return 'lecon'
    elseif e and Fenetre.estEtape(e) then
        return 'etape'
    elseif e and e.genre == 'outil' then
        return 'outil'
    end
    return nil
end

Fenetre.clics = {
    -- Les images de la conversation relues : le clic choisit la sienne, sans bascule vers une image
    -- arrivée entre-temps (Fenetre.rafraichirApercu). Elle reste montrée quel que soit l'onglet
    -- (Fenetre.imageCliquee), jusqu'à un autre onglet, une image nouvelle, une autre conversation,
    -- une autre photo active ou un clic sur une étape.
    image = function(l)
        local c = Moteur.courante
        Fenetre.images = c and Conversation.images(c) or {}
        Fenetre.apercuDe, Fenetre.nbImages = c, #Fenetre.images
        for n, image in ipairs(Fenetre.images) do
            if image.chemin == l.image then
                Fenetre.indiceImage = n
                Fenetre.voirActive = false
                Fenetre.imageCliquee = true
            end
        end
        Fenetre.rafraichirApercu()
    end,
    -- Les lignes de la page du carnet (1.3) : seulement sur la page (Fenetre.vue). Une rangée du
    -- tableau : la fenêtre de ses photos, dans une tâche (le carnet se lit par LrTasks.pcall).
    carnet = function(l)
        if Fenetre.vue ~= 'carnet' then
            return
        end
        if l.defaut ~= nil then
            enTache(Fenetre.montrerDefaut, l.defaut)
        elseif l.action == 'demander' then
            Fenetre.demanderCarnet()
        end
    end,
    -- La ligne d'une leçon (1.3 ; en préparation, ou refusée : la leçon faite a sa ligne d'actions
    -- et son onglet) : le détail de son appel de photo_lesson (les points donnés, puis la réponse :
    -- faits mesurés, indices, remarques), à part, dans une tâche.
    lecon = function(_, e)
        local c = Moteur.courante
        local outil = c and Conversation.outilDeLAppel(c, e.appel)
        if outil then
            enTache(Fenetre.montrerDetail, outil)
        end
    end,
    etape = function(l)
        Fenetre.montrerEtape(l.element)
    end,
    outil = function(_, e)
        enTache(Fenetre.montrerDetail, e)
    end,
}

function Fenetre.cliquerLigne(i)
    Fenetre.annulerEnvoiAuto()
    local l = Fenetre.lignes and Fenetre.lignes[(Fenetre.premiere or 1) + i - 1]
    if not l then
        return
    end
    local c = Moteur.courante
    local e = c and l.element and c.elements[l.element] or nil
    local sorte = Fenetre.sorteDeClic(l, e)
    -- Une étape montre son avant/après dans l'aperçu, à la place d'une image cliquée avant ; le
    -- détail d'un outil ou d'une leçon s'ouvre à part, l'aperçu reste tel quel.
    if sorte == 'etape' then
        Fenetre.imageCliquee = nil
    end
    local traiter = sorte and Fenetre.clics[sorte]
    if traiter then
        traiter(l, e)
    end
end

-- La ligne i de la grille du fil (celle que montre la ligne i), nil sans ligne.
local function ligneMontree(i)
    return Fenetre.lignes and Fenetre.lignes[(Fenetre.premiere or 1) + i - 1] or nil
end

-- « Pourquoi ? » de la ligne i (Vues.ligneFil) : l'étape de cette ligne dans l'onglet Aperçu, son
-- avant/après dans l'aperçu (Fenetre.montrerEtape), comme un clic sur son texte.
function Fenetre.pourquoi(i)
    Fenetre.annulerEnvoiAuto()
    local l = ligneMontree(i)
    if not (l and l.etape and l.element) then
        return false
    end
    return Fenetre.montrerEtape(l.element)
end

-- « ☆ Voir la note » de la ligne i : la notation de cette ligne dans l'onglet Note.
function Fenetre.voirNote(i)
    Fenetre.annulerEnvoiAuto()
    local l = ligneMontree(i)
    return l ~= nil and l.notation ~= nil and Fenetre.montrerNote(l.notation)
end

-- « Leçon de la photo » de la ligne i : la leçon de cette ligne dans l'onglet Leçon.
function Fenetre.voirLecon(i)
    Fenetre.annulerEnvoiAuto()
    local l = ligneMontree(i)
    return l ~= nil and l.lecon ~= nil and Fenetre.montrerLecon(l.lecon)
end

-- Le bandeau quand la photo active n'est pas parmi celles d'une notation (« ☆ Voir la note ») : la
-- carte Note montre la photo active, et la fenêtre ne change jamais la sélection (une autre photo
-- commencerait une nouvelle conversation, Fenetre.suivreSelection).
Fenetre.NOTE_AUTRE_PHOTO = "Note d'une autre photo : choisissez-la dans Lightroom."

-- Montre l'onglet Note pour la notation de l'élément i, comme un vrai clic sur son segment
-- (Fenetre.ongletChange). Rend vrai si l'élément est une notation.
function Fenetre.montrerNote(i)
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    local e = c and i and c.elements[i]
    if not (p and T and e and e.genre == 'notation') then
        return false
    end
    if p.onglet ~= T.ongletNotation then
        p.onglet = T.ongletNotation
    end
    local active = Fenetre.info and Fenetre.info.active
    local cle = active and Conversation.clePhoto(active.id)
    local parmi = false
    for _, x in ipairs(e.notes or {}) do
        if cle ~= nil and Conversation.clePhoto(x.photo) == cle then
            parmi = true
        end
    end
    if not parmi then
        p.message = Fenetre.NOTE_AUTRE_PHOTO
    elseif p.message == Fenetre.NOTE_AUTRE_PHOTO then
        p.message = ''
    end
    return true
end

-- Montre l'onglet Leçon sur la leçon de l'élément i (Fenetre.leconChoisie), comme un vrai clic sur
-- son segment. Rend vrai si l'élément est une leçon.
function Fenetre.montrerLecon(i)
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    local e = c and i and c.elements[i]
    if not (p and T and e and e.genre == 'lecon') then
        return false
    end
    Fenetre.leconChoisie = e.id
    if p.onglet ~= T.ongletLecon then
        p.onglet = T.ongletLecon
    end
    Fenetre.rafraichirLecon()
    return true
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

-- Carnet de progrès (1.3) ---------------------------------------------------------------------
-- La page du carnet dans la grille du fil (Fenetre.vue = 'carnet'), atteinte par l'entrée
-- « Carnet de progrès », la première case de la liste des conversations (genre 'carnet', valeur
-- Fenetre.CARNET, dans une table neuve comme les autres éléments, Fenetre.elementsListe ; son
-- clic : Fenetre.cliquerListe, puis Fenetre.ouvrirCarnet), choisie (fond de sélection) tant que
-- la page est montrée.
-- Le résumé vient du module (Carnet.resumer, seule source des phrases), lu dans une tâche (le
-- chemin du catalogue se lit par LrTasks.pcall), et se met en lignes par Fil.lignesCarnet ; la
-- conversation montrée ne change pas pendant ce temps. Une rangée du tableau ouvre la fenêtre de
-- ses photos (Fenetre.montrerDefaut : leurs constats et leurs leçons, « Retirer du carnet… »), la
-- ligne d'action une nouvelle conversation qui demande à Claude ce qu'il en pense
-- (Fenetre.demanderCarnet, Consignes.carnet). Une conversation choisie dans la liste (celle déjà
-- ouverte comprise), Nouvelle conversation, une demande (Envoyer, une invite) ou Claude qui
-- travaille (Accepter, Je le fais…) ramènent au fil ; Renommer… et Supprimer… ne font rien sur la
-- page (ils viseraient la conversation cachée). La boucle relit la page quand le registre change
-- (Carnet.version, abonnement 'fenetre'). Rien ici ne touche aux pièces de la fenêtre (Vues.lua,
-- Dispositions.lua) : la page ne fait que remplir la grille du fil.
Fenetre.CARNET = '¶carnet'
Fenetre.TITRE_CARNET = Carnet.TITRES.carnet
Fenetre.SOUS_TITRE_CARNET = "défauts de prise de vue, mois par mois"
-- Les messages du bandeau tiennent en deux lignes (Fenetre.texteBandeau, essais-fenetre-b.lua).
Fenetre.CHOISIR_CONVERSATION = "Carnet montré : choisissez d'abord une conversation."
Fenetre.CLAUDE_TRAVAILLE = "Claude travaille : attendez la fin, ou cliquez Arrêter."

-- Montre la page du carnet (depuis la liste ; pas pendant que Claude travaille : la liste le
-- refuse alors, et Claude ramènerait aussitôt au fil). Elle se lit depuis son haut
-- (Fenetre.hautCarnet), son résumé relu dans une tâche. Rend vrai si la page est montrée.
function Fenetre.ouvrirCarnet()
    local p = Fenetre.p
    if not p then
        return false
    end
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        Fenetre.rafraichirListe()
        return false
    end
    p.message = ''
    if Fenetre.vue ~= 'carnet' then
        Fenetre.vue = 'carnet'
        Fenetre.pageCarnet = nil
        Fenetre.hautCarnet = 0
    end
    Fenetre.versionCarnet, Fenetre.aRafraichirCarnet = Carnet.version, false
    enTache(Fenetre.lireCarnet)
    -- Son entrée choisie dans la liste, tout de suite.
    Fenetre.rafraichirListe()
    Fenetre.aRafraichir = true
    return true
end

-- Relit le résumé du carnet (depuis une tâche) et, sur la page, la redessine. Un résumé qui ne se
-- lit pas fait une page qui le dit (Fil.lignesCarnet), jamais une page en lecture sans fin.
function Fenetre.lireCarnet()
    Fenetre.versionCarnet = Carnet.version
    local ok, page = LrTasks.pcall(Carnet.resumer, os.time())
    if not ok then
        Journal.noter("Carnet de progrès :", tostring(page))
        page = { erreur = tostring(page) }
    end
    Fenetre.pageCarnet = page
    if Fenetre.vue == 'carnet' and Fenetre.p then
        Fenetre.rafraichirFil()
    end
    return page
end

-- Revient au fil depuis la page du carnet (rien sur le fil) ; rend vrai si la vue a changé.
function Fenetre.quitterCarnet()
    if not Fenetre.revenirAuFil() then
        return false
    end
    Fenetre.pageCarnet = nil
    Fenetre.aRafraichir = true
    return true
end

-- Vrai sur la page du carnet, où Renommer… et Supprimer… ne font rien : le bandeau dit de choisir
-- une conversation.
local function surLaPageDuCarnet()
    if Fenetre.vue ~= 'carnet' then
        return false
    end
    if Fenetre.p then
        Fenetre.p.message = Fenetre.CHOISIR_CONVERSATION
    end
    return true
end

-- Le nom d'un axe de leçon rangé au carnet (Carnet.AXES : 'lumiere', 'couleur', 'composition'),
-- celui de la carte du fil (Conversation.AXES_LECON, dans le même ordre).
function Fenetre.nomAxeCarnet(axe)
    for i, a in ipairs(Carnet.AXES) do
        if a == axe and Conversation.AXES_LECON[i] then
            return Conversation.AXES_LECON[i].nom
        end
    end
    return tostring(axe or '?')
end

local function texteOuNil(valeur)
    if type(valeur) == 'string' and Texte.nettoyer(valeur) ~= '' then
        return Texte.nettoyer(valeur)
    end
    return nil
end

-- Le nom d'une photo du carnet (Carnet.photosDuDefaut) : son fichier, sinon son identifiant.
function Fenetre.nomPhotoCarnet(x)
    return texteOuNil(x.fichier) or ("photo " .. Conversation.clePhoto(x.original or x.photo))
end

-- Une inclinaison en degrés, au dixième, sans signe (« 1,2° »), comme le carnet la note.
local function degres(x)
    local d = math.floor(math.abs(x) * 10 + 0.5)
    return string.format('%d,%d°', math.floor(d / 10), d % 10)
end

-- Une photo d'un défaut, sur une ligne : « octobre 2026 · DSCF4961.RAF · ciel brûlé : 4,2 % … ·
-- leçon » (le constat, sinon sa mesure ; `angle` : une ligne penchée, dite en degrés).
function Fenetre.textePhotoDuDefaut(x)
    local morceaux = { texteOuNil(x.mois_libelle) or tostring(x.mois or '?'), Fenetre.nomPhotoCarnet(x) }
    local mesure = type(x.mesure) == 'number' and (x.angle and ("ligne penchée de " .. degres(x.mesure))
        or ("mesure : " .. Texte.nombre(x.mesure))) or nil
    local constat = texteOuNil(x.texte) or mesure
    if constat then
        morceaux[#morceaux + 1] = constat
    end
    if type(x.lecons) == 'table' and #x.lecons > 0 then
        morceaux[#morceaux + 1] = "leçon"
    end
    return table.concat(morceaux, " · ")
end

-- Les leçons rangées avec une photo du carnet (l'original et ses copies virtuelles), en lignes,
-- comme la carte du fil : par axe, ce qui manquait puis la prise de vue.
function Fenetre.texteLecons(x)
    local lecons = x and type(x.lecons) == 'table' and x.lecons or {}
    if #lecons == 0 then
        return "Pas de leçon rangée pour cette photo : Claude en fait une après sa retouche."
    end
    local lignes = {}
    for _, l in ipairs(lecons) do
        if #lignes > 0 then
            lignes[#lignes + 1] = ''
        end
        lignes[#lignes + 1] = "Leçon de la photo · " .. (texteOuNil(l.fichier) or Fenetre.nomPhotoCarnet(x))
        for _, pt in ipairs(type(l.points) == 'table' and l.points or {}) do
            lignes[#lignes + 1] = Fenetre.nomAxeCarnet(pt.axe)
            local manque, prise = texteOuNil(pt.manque), texteOuNil(pt.prise_de_vue) or ''
            if manque then
                lignes[#lignes + 1] = "    Ce qui manquait : " .. manque
                lignes[#lignes + 1] = "    À la prise de vue : " .. prise
            else
                lignes[#lignes + 1] = "    Rien ne manquait."
                lignes[#lignes + 1] = "    À refaire : " .. prise
            end
        end
    end
    return table.concat(lignes, '\n')
end

-- Le défaut `code` de la page lue (libellé, conseil), sinon du vocabulaire rangé au carnet.
local function defautDuCarnet(code)
    local page = Fenetre.pageCarnet
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
-- (Carnet.photosDuDefaut, dans les mois de la page), la plus récente d'abord ; la leçon de la
-- photo choisie dessous ; « Retirer du carnet… » retire la photo choisie (Fenetre.retirerDuCarnet).
function Fenetre.montrerDefaut(code)
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
            items[#items + 1] = { title = Fenetre.textePhotoDuDefaut(x), value = x.original }
            parId[x.original] = x
        end
        local function choisie(valeur)
            local id = type(valeur) == 'table' and valeur[1] or valeur
            return id ~= nil and parId[id] or nil
        end
        q.choix = #photos > 0 and { photos[1].original } or {}
        q.lecon = #photos > 0 and Fenetre.texteLecons(photos[1]) or ''
        q:addObserver('choix', function(_, _, valeur)
            q.lecon = Fenetre.texteLecons(choisie(valeur))
        end)
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
            contenu[#contenu + 1] = f:static_text { title = "Leçon de la photo choisie (sélectionnable, ⌘A puis ⌘C pour copier) :" }
            contenu[#contenu + 1] = f:edit_field { value = bind 'lecon', width_in_chars = 90, height_in_lines = 10 }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = Fenetre.TITRE_CARNET .. " · " .. libelle,
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
        return Fenetre.retirerDuCarnet(aRetirer)
    end
    return false
end

-- Retire une photo du carnet, après confirmation : par appel direct au registre du module
-- (Carnet.commande, jamais une ligne de la liaison), avec l'identifiant de l'original (la clé de
-- son entrée). La page se relit ensuite (Carnet.version). Rend vrai si elle est retirée.
function Fenetre.retirerDuCarnet(x)
    local nom = Fenetre.nomPhotoCarnet(x)
    local reponse = LrDialogs.confirm("Retirer " .. nom .. " du carnet de progrès ?",
        "Ses constats et ses leçons sortent du carnet et ne comptent plus dans le tableau. La photo et ses retouches ne changent pas.",
        "Retirer", "Annuler")
    if reponse ~= 'ok' then
        return false
    end
    local ok, r = LrTasks.pcall(Carnet.commande, { action = 'retirer', photos = { x.original } })
    local retiree = ok and type(r) == 'table' and (tonumber(r.retirees) or 0) > 0
    if Fenetre.p then
        Fenetre.p.message = retiree and (nom .. " est retirée du carnet de progrès.")
            or ("Le carnet n'a pas retiré " .. nom .. (ok and " : elle n'y est plus." or (" : " .. tostring(r))))
    end
    return retiree
end

-- « Demander à Claude ce qu'il en pense » : une nouvelle conversation (la page se quitte), avec la
-- demande du carnet (Consignes.carnet). Elle porte un titre à elle : Claude ne regarde aucune photo
-- pour la nommer, et la liste montrerait sinon le début de la demande.
Fenetre.TITRE_DEMANDE_CARNET = "Avis de Claude sur le carnet de progrès"

function Fenetre.demanderCarnet()
    -- Pendant que Claude travaille, Moteur.nouvelle refuse (le bandeau dit pourquoi).
    if not Fenetre.nouvelle() then
        return false
    end
    if Moteur.courante then
        Moteur.renommer(Moteur.courante.id, Fenetre.TITRE_DEMANDE_CARNET)
    end
    Fenetre.envoyer(Consignes.carnet)
    return true
end

-- Onglets -------------------------------------------------------------------------------------

-- L'aperçu est commun aux cinq onglets (Aperçu, Focus, Proposition, Note, Leçon), mais un onglet
-- peut le remplir (1.3) : Note et Leçon montrent la photo active et les images de la conversation,
-- comme avant ; Proposition, l'image de la proposition ou de l'exercice ; Aperçu (l'ancien
-- Pourquoi ?), l'avant ou l'après de l'étape choisie ; Focus, la photo active et ses cadres de mise
-- au point. Fenetre.apercuOnglet[valeur](p, T, c), s'il existe, est
-- demandé d'abord par Fenetre.rafraichirApercu : vrai s'il a rempli l'aperçu lui-même
-- (imageApercu, legendeApercu, aImage, peutPrecedente, peutSuivante), nil ou faux pour l'aperçu
-- d'avant. Un clic sur une ligne d'image reste prioritaire. Fenetre.surOnglet[valeur](valeur) suit
-- un vrai clic sur cet onglet (son segment, Fenetre.choisirSegment ; jamais une bascule de la
-- fenêtre, Fenetre.choisirOnglet). Ni l'un ni l'autre n'attend : une lecture du catalogue ou un
-- rendu passe par sa propre tâche. Ceux d'Aperçu, de Focus et de Proposition (la comparaison de Je
-- le fais, puis l'image de la proposition demandée par un clic : Composition lue) sont dans leur
-- section ; Note et Leçon n'en ont pas.
Fenetre.apercuOnglet = {}
Fenetre.surOnglet = {}

-- Appelle un crochet ; une erreur est journalisée et vaut nil (la fenêtre continue). Hors d'une
-- tâche (observateur d'une propriété, clic), pcall : LrTasks.pcall ne sert qu'à du code qui peut
-- attendre.
local function crochet(fn, ...)
    local protege = LrTasks.canYield and LrTasks.canYield() and LrTasks.pcall or pcall
    local ok, r = protege(fn, ...)
    if not ok then
        Journal.noter("Crochet de la fenêtre :", tostring(r))
        return nil
    end
    return r
end

-- L'onglet change (clic ou bascule) : une image cliquée dans le fil cède la place à l'aperçu de
-- l'onglet ; un vrai clic n'envoie pas la demande validée par ce clic, et appelle son crochet.
function Fenetre.ongletChange(valeur)
    Fenetre.imageCliquee = nil
    if not Fenetre.ongletAuto then
        Fenetre.annulerEnvoiAuto()
        local sur = Fenetre.surOnglet[valeur]
        if sur then
            crochet(sur, valeur)
        end
    end
    Fenetre.rafraichirApercu()
end

-- Le clic sur un segment (son calque, Vues.segments, qui a déjà annulé l'envoi automatique) : un
-- vrai clic, l'onglet change et son crochet suit (Fenetre.ongletChange).
function Fenetre.choisirSegment(valeur)
    local p = Fenetre.p
    if p and p.onglet ~= valeur then
        p.onglet = valeur
    end
end

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

-- L'image « aucun aperçu », dans le jeu de l'apparence de la fenêtre.
function Fenetre.imageVide()
    return Chemins.ressource(Dispositions.imageVide(Fenetre.apparence))
end

-- Le nom d'une photo avec celui de sa copie virtuelle (« 20200710_193347.jpg (Essai) »), d'après
-- sa légende (Lightroom.legende) ou, sans elle, son nom de fichier seul.
function Fenetre.nomPhoto(legende)
    local nom = sansBalises(legende and legende.nom)
    local copie = sansBalises(legende and legende.copie)
    if copie ~= '' then
        return nom .. ' (' .. copie .. ')'
    end
    return nom
end

-- La légende de la photo active sous l'aperçu, en texte riche : « <EM>20200710_193347.jpg
-- (Essai)</EM> · X-T20 · 10 juil. 2020 » (l'appareil et la date s'ils sont connus).
function Fenetre.texteLegende(legende)
    local morceaux = { '<EM>' .. Fenetre.nomPhoto(legende) .. '</EM>' }
    for _, cle in ipairs({ 'appareil', 'date' }) do
        local v = sansBalises(legende and legende[cle])
        if v ~= '' then
            morceaux[#morceaux + 1] = v
        end
    end
    return table.concat(morceaux, ' · ')
end

-- La légende lue de la photo active (Fenetre.majPhoto, quand elle change), ou son seul nom.
local function legendeActive(active)
    local l = Fenetre.legendeActive
    if l and l.id == active.id then
        if sansBalises(l.nom) == '' then
            l.nom = active.nom
        end
        return l
    end
    return { nom = active.nom }
end

-- La vignette de l'aperçu, en pixels : 2 × le cadre (996 × 664), centrée sur le fond.
local function vignetteApercu(T, dossier, nom)
    return Images.vignette(dossier, nom, T.pixelsApercu, T.pixelsApercuHauteur)
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
    if not ok or type(d) ~= 'table' or not Fenetre.estFujifilm(d) then
        return nil
    end
    return Images.marquerMiseAuPoint(Chemins.prefs().cheminConnecteur, d.chemin_original, d.geometrie, source)
end

-- Un fichier Fujifilm, d'après la description de Vignettes.decrireVignette : la marque, ou un
-- original .RAF. Seul un tel original s'ouvre (carré de mise au point, onglet Focus).
function Fenetre.estFujifilm(d)
    local original = type(d) == 'table' and type(d.chemin_original) == 'string' and d.chemin_original or ''
    return original ~= '' and (tostring(d.marque or ''):upper():find('FUJIFILM', 1, true) ~= nil or original:lower():match('%.raf$') ~= nil)
end

local function montrerActive(p, T, active, n)
    poser(p, 'peutPrecedente', n > 0)
    poser(p, 'peutSuivante', false)
    poser(p, 'legendeApercu', Fenetre.texteLegende(legendeActive(active)))
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
            return vignetteApercu(T, d, f), d, f
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

-- Montre l'image `indice` des images de la conversation `c` (Fenetre.images, relues) : sa légende
-- (« 2 sur 5 · view_photo »), ◀ ▶ (▶ depuis la dernière revient à la photo active) et l'image,
-- réduite au cadre de l'aperçu ; sans image, l'image vide.
local function montrerNumero(p, T, c, indice)
    local n = #Fenetre.images
    local active = Fenetre.info and Fenetre.info.active
    poser(p, 'aImage', n > 0)
    poser(p, 'peutPrecedente', indice > 1)
    poser(p, 'peutSuivante', indice < n or (n > 0 and active ~= nil))
    if n == 0 then
        poser(p, 'legendeApercu', "Aucun aperçu pour l'instant")
        poser(p, 'imageApercu', Fenetre.imageVide())
        return
    end
    local image = Fenetre.images[indice]
    -- La comparaison de « Je le fais » (1.3) : la version de Claude à gauche, celle de Dany à droite.
    local nature = image.outil == 'jointe' and "photo jointe" or (image.comparaison and Fenetre.LEGENDE_COMPARAISON)
        or (image.outil or "aperçu")
    poser(p, 'legendeApercu', string.format("%d sur %d · %s", indice, n, nature))
    Fenetre.montrerImage(p, T, c, image.chemin)
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
    -- Une autre conversation (liste, Nouvelle, conversation supprimée, nouvelle demande d'une autre
    -- page) : l'image cliquée était d'une autre conversation, l'aperçu revient à l'onglet ; l'image
    -- de proposition demandée aussi (Fenetre.montrerImageProposition).
    if Fenetre.apercuDe ~= c then
        Fenetre.imageCliquee = nil
        Fenetre.imageProposition = nil
    end
    -- Une image de plus dans la conversation montrée (Claude regarde, une photo jointe) : elle se
    -- montre, à la place de la photo active ; une image cliquée avant rend la main à l'onglet, et
    -- l'image de proposition demandée par un clic cède aussi la place.
    if Fenetre.apercuDe == c and Fenetre.nbImages and n > Fenetre.nbImages then
        Fenetre.voirActive = false
        Fenetre.indiceImage = nil
        Fenetre.imageCliquee = nil
        Fenetre.imageProposition = nil
    end
    Fenetre.apercuDe, Fenetre.nbImages = c, n
    -- L'aperçu de l'onglet (Fenetre.apercuOnglet), sauf après un clic sur une ligne d'image.
    local deLOnglet = not Fenetre.imageCliquee and Fenetre.apercuOnglet[p.onglet]
    if deLOnglet and crochet(deLOnglet, p, T, c) then
        return
    end
    local active = Fenetre.info and Fenetre.info.active
    if Fenetre.voirActive and active then
        montrerActive(p, T, active, n)
        return
    end
    montrerNumero(p, T, c, Fenetre.indiceImage or n)
end

-- La légende de la comparaison « Je le fais » (1.3) : Claude à gauche, Dany à droite.
Fenetre.LEGENDE_COMPARAISON = "Claude | vous"

-- Montre dans l'aperçu une image de la conversation `c` (chemin relatif à son dossier), réduite au
-- cadre de l'aperçu en 2x dans une tâche (Images.vignette, 996 × 664), gardée ensuite
-- (Fenetre.vignettes, par sa taille en pixels).
function Fenetre.montrerImage(p, T, c, chemin)
    local cle = c.id .. '/' .. chemin .. '/' .. T.pixelsApercu .. 'x' .. T.pixelsApercuHauteur
    local deja = Fenetre.vignettes[cle]
    if deja then
        poser(p, 'imageApercu', deja)
        return
    end
    LrTasks.startAsyncTask(function()
        local reduite = vignetteApercu(T, Stockage.dossier(c.id), chemin)
        if reduite then
            Fenetre.vignettes[cle] = reduite
            if Fenetre.p and Fenetre.T == T and Moteur.courante == c then
                Fenetre.p.imageApercu = reduite
            end
        end
    end)
end

function Fenetre.changerImage(pas)
    -- L'aperçu d'une étape (onglet Aperçu) : ses ◀ ▶ sont coupés, Voir l'avant / Voir l'après
    -- et les ◀ ▶ de la carte en tiennent lieu.
    if Fenetre.modeEtape() then
        return
    end
    -- L'image de la proposition montrée par l'onglet Proposition (Fenetre.apercuProposition) : ◀ ▶
    -- partent d'elle, et l'aperçu redevient celui d'avant (la demande du clic est oubliée).
    local _, depuis = Fenetre.imagePropositionMontree()
    if depuis then
        Fenetre.imageProposition = nil
        Fenetre.voirActive = false
        Fenetre.indiceImage = depuis
    end
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

-- Le titre de la fenêtre de l'aperçu en grand : la légende de l'aperçu, sans ses balises.
local function titreAgrandi(defaut)
    local legende = Fenetre.p and sansBalises(Fenetre.p.legendeApercu) or ''
    return "Claude · " .. (legende ~= '' and legende or defaut)
end

-- L'aperçu en grand, dans une fenêtre à part ; pour une étape (onglet Aperçu), son avant et son
-- après côte à côte (Fenetre.agrandirEtape).
function Fenetre.agrandir()
    if Fenetre.modeEtape() then
        Fenetre.agrandirEtape()
        return
    end
    -- L'onglet Focus : la vignette de la photo active avec ses cadres de mise au point ; sauf après
    -- un clic sur une ligne d'image du fil, que l'aperçu montre alors (comme Fenetre.modeEtape et
    -- Fenetre.comparaisonMontree) : c'est elle qu'Agrandir montre.
    local r = Fenetre.focusMontre() and not Fenetre.imageCliquee and Fenetre.focusActif()
    if r and r.fichier then
        LrTasks.startAsyncTask(function()
            local chemin, l, h = Images.grande(r.dossier, r.fichier, 1100, 740)
            if chemin then
                LrDialogs.presentModalDialog {
                    title = titreAgrandi("Focus"),
                    contents = LrView.osFactory():picture { value = chemin, width = l, height = h },
                    actionVerb = "Fermer",
                    cancelVerb = '< exclude >',
                }
            end
        end)
        return
    end
    -- La comparaison « Je le fais » de l'onglet Proposition (1.3) : une seule image, côte à côte
    -- (le connecteur rend les deux versions en une image).
    local cc, comparaison = Fenetre.comparaisonMontree()
    if comparaison then
        LrTasks.startAsyncTask(function()
            local chemin, l, h = Images.grande(Stockage.dossier(cc.id), comparaison, 1100, 740)
            if not chemin then
                LrDialogs.message("Aperçu illisible", comparaison, 'warning')
                return
            end
            LrDialogs.presentModalDialog {
                title = titreAgrandi(Fenetre.LEGENDE_COMPARAISON),
                contents = LrView.osFactory():picture { value = chemin, width = l, height = h },
                actionVerb = "Fermer",
                cancelVerb = '< exclude >',
            }
        end)
        return
    end
    -- L'image de la proposition montrée par l'onglet Proposition (le cadre proposé en pointillés,
    -- Composition lue, 1.3) : celle-là, même si la photo active a changé entre-temps.
    local _, indiceProposition = Fenetre.imagePropositionMontree()
    local a, active = Fenetre.apercuActif, Fenetre.info and Fenetre.info.active
    if not indiceProposition and Fenetre.voirActive and active and a and a.id == active.id then
        LrTasks.startAsyncTask(function()
            local chemin, l, h = Images.grande(a.dossier, a.fichier, 1100, 740)
            if chemin then
                LrDialogs.presentModalDialog {
                    title = titreAgrandi("photo active"),
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
    local image = Fenetre.images[indiceProposition or Fenetre.indiceImage or n]
    LrTasks.startAsyncTask(function()
        local chemin, l, h = Images.grande(Stockage.dossier(c.id), image.chemin, 1100, 740)
        if not chemin then
            LrDialogs.message("Aperçu illisible", image.chemin, 'warning')
            return
        end
        local f = LrView.osFactory()
        LrDialogs.presentModalDialog {
            title = titreAgrandi("aperçu"),
            contents = f:picture { value = chemin, width = l, height = h },
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
        }
    end)
end

-- Deux images côte à côte en grand, dans une fenêtre à part (1.3) : l'avant et l'après d'une étape
-- (onglet Aperçu), la version de Claude et celle de Dany (Je le fais). `gauche` et `droite` :
-- { dossier, nom, titre } (le titre au-dessus de l'image, « Avant », « Après ») ; `legende`
-- (facultative) dessous, coupée à la largeur des deux images ; le titre de la fenêtre est
-- « Claude · <titre> ». Chaque image tient dans GRANDE_DEUX (Images.grande, sips) : depuis une
-- tâche. Une image illisible est dite à sa place ; rend faux si aucune ne se lit.
Fenetre.GRANDE_DEUX = { largeur = 540, hauteur = 700 }

function Fenetre.agrandirDeux(titre, gauche, droite, legende)
    local f = LrView.osFactory()
    local G = Fenetre.GRANDE_DEUX
    local colonnes, largeur, lues = { spacing = f:control_spacing() }, 0, 0
    for _, image in ipairs({ gauche or false, droite or false }) do
        local chemin, l, h
        if type(image) == 'table' and image.dossier and image.nom then
            chemin, l, h = Images.grande(image.dossier, image.nom, G.largeur, G.hauteur)
        end
        local nom = type(image) == 'table' and tostring(image.titre or '') or ''
        if chemin then
            lues = lues + 1
            colonnes[#colonnes + 1] = f:column {
                spacing = 4,
                f:static_text { title = nom, font = POLICES.gras, width = l },
                f:picture { value = chemin, width = l, height = h },
            }
            largeur = largeur + l
        else
            colonnes[#colonnes + 1] = f:column {
                f:static_text { title = (nom ~= '' and (nom .. " : ") or '') .. "image illisible", font = POLICES.texte, width = 200 },
            }
            largeur = largeur + 200
        end
    end
    if lues == 0 then
        LrDialogs.message("Aperçu illisible", tostring(titre or ''), 'warning')
        return false
    end
    local contenu = { spacing = f:control_spacing(), f:row(colonnes) }
    if Texte.nettoyer(legende or '') ~= '' then
        local lignes = Fenetre.lignesCarte(legende, largeur)
        contenu[#contenu + 1] = f:static_text { title = table.concat(lignes, '\n'), font = POLICES.texte, width = largeur,
            height_in_lines = math.max(1, #lignes) }
    end
    LrDialogs.presentModalDialog {
        title = "Claude · " .. tostring(titre or ''),
        contents = f:column(contenu),
        actionVerb = "Fermer",
        cancelVerb = '< exclude >',
    }
    return true
end

-- Textes des cartes, page par page --------------------------------------------------------------

-- Le texte de la carte Note (clé 'note'), celui de la proposition (clé 'proposition'), celui de
-- la carte de l'étape (onglet Aperçu, clé 'etape', 1.3) et celui de la leçon (onglet Leçon, clé
-- 'lecon', lot B4) : coupés en lignes comme le fil, à la largeur de l'intérieur des cartes, dans
-- la police de leur carte (`police` de CARTES : P.texte12 pour les quatre, lot B5), montrés page
-- par page avec ▲ ▼ (Vues.fleches). Une carte à `emphase` (la leçon, ses axes ; la note, ses
-- verdicts) garde ses passages balisés, en gras de même taille ; les autres textes perdent leurs
-- balises (sans emphasis_font, Lightroom ne les montrerait pas, constaté D4). La carte Note est une
-- grille (`grille`) : ses lignes sont des tables (Fenetre.lignesCriteres : genre, étiquette,
-- texte), posées ligne par ligne dans `ng..k`, `ne..k` et `nt..k`. Un texte qui change revient à
-- sa première page.
Fenetre.pages = {}

-- L'onglet Leçon sans leçon de la photo active dans la conversation montrée.
Fenetre.AUCUNE_LECON = "Après une retouche, Claude donne la leçon de la photo : ce qui manquait, et ce qui se fait à la "
    .. "prise de vue. Elle s'affiche ici ; « Leçon de la photo » dans le fil la remontre."

local CARTES = {
    note = { grille = { genre = 'ng', etiquette = 'ne', texte = 'nt' }, largeur = 'largeurNote',
        lignes = function(T) return (T.criteres or 8) + 1 end, police = 'texte12', emphase = 'gras12' },
    proposition = { texte = 'propositionTexte', largeur = 'largeurProposition', lignes = function(T) return T.propLignes or 5 end,
        police = 'texte12' },
    etape = { texte = 'etapeTexte', largeur = 'largeurEtape', lignes = function(T) return T.etapeLignes or 8 end, police = 'texte12' },
    lecon = { texte = 'leconTexte', largeur = 'largeurLecon', lignes = function(T) return T.leconLignes or 8 end, police = 'texte12',
        emphase = 'gras12' },
    focus = { texte = 'focusTexte', largeur = 'largeurFocus', lignes = function(T) return T.focusLignes or 8 end, police = 'texte12',
        emphase = 'gras12' },
}
Fenetre.CARTES = CARTES

-- Les lignes d'un texte dans `largeur` points (paragraphes gardés, lignes vides comprises), dans
-- `police` (une clé de Metriques ; P.texte sans elle) ; `emphase` : la police de ses passages
-- balisés (<EM>), chaque ligne aux balises fermées, un passage coupé rouvert à la suivante.
function Fenetre.lignesCarte(texte, largeur, police, emphase)
    local lignes = {}
    local ouvert = false
    for paragraphe in (tostring(texte or '') .. '\n'):gmatch('([^\n]*)\n') do
        if paragraphe == '' then
            lignes[#lignes + 1] = ''
        else
            local coupees
            coupees, ouvert = Fil.couper(paragraphe, largeur - Fil.MARGE, police or 'texte', nil, emphase, ouvert)
            for _, l in ipairs(coupees) do
                lignes[#lignes + 1] = l
            end
        end
    end
    while #lignes > 0 and lignes[#lignes] == '' do
        lignes[#lignes] = nil
    end
    return lignes
end

-- Les lignes d'une page de la carte `carte` : celles données (une grille), sinon son texte coupé
-- (sans ses balises s'il n'a pas d'emphase), en lignes pleine largeur pour une grille.
local function lignesDeLaPage(carte, page, T)
    if page.lignes then
        return page.lignes
    end
    local source = carte.emphase and page.texte or sansBalises(page.texte)
    local lignes = Fenetre.lignesCarte(source, T and T[carte.largeur] or 226, carte.police, carte.emphase)
    if carte.grille then
        for k, l in ipairs(lignes) do
            lignes[k] = { genre = 'plein', etiquette = '', texte = l }
        end
    end
    return lignes
end

-- Montre la page courante du texte de la carte `cle` ; `texte` nil : le texte gardé. `garder` : un
-- texte qui change reste à la même page (la liste d'un exercice dont un réglage vient d'être coché).
-- `lignes` (une carte en grille, la note) : ses lignes déjà faites ({ genre, etiquette, texte }),
-- dont `texte` est alors la signature.
function Fenetre.montrerPage(cle, texte, garder, lignes)
    local p, T, carte = Fenetre.p, Fenetre.T, CARTES[cle]
    if not (p and carte) then
        return
    end
    local page = Fenetre.pages[cle]
    if texte ~= nil and (not page or page.texte ~= texte) then
        page = { texte = texte, debut = garder and page and page.debut or 1 }
        Fenetre.pages[cle] = page
    end
    if not page then
        return
    end
    if lignes ~= nil then
        page.lignes = lignes
    end
    local hauteur = T and carte.lignes(T) or 8
    local toutes = lignesDeLaPage(carte, page, T)
    -- La dernière page est pleine : on ne descend pas plus bas que la dernière ligne.
    page.debut = math.max(1, math.min(page.debut, #toutes - hauteur + 1))
    if carte.grille then
        local g = carte.grille
        for k = 1, hauteur do
            local l = toutes[page.debut + k - 1]
            poser(p, g.genre .. k, l and l.genre or 'vide')
            poser(p, g.etiquette .. k, l and l.etiquette or '')
            poser(p, g.texte .. k, l and l.texte or '')
        end
    else
        local montre = {}
        for i = page.debut, math.min(#toutes, page.debut + hauteur - 1) do
            montre[#montre + 1] = toutes[i]
        end
        poser(p, carte.texte, table.concat(montre, '\n'))
    end
    poser(p, cle .. 'Monte', page.debut > 1)
    poser(p, cle .. 'Descend', page.debut + hauteur - 1 < #toutes)
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

-- Leçon de la photo (1.3, onglet Leçon, lot B4) --------------------------------------------------
-- La carte de l'onglet Leçon (Vues.lecon) montre la leçon choisie par « Leçon de la photo » dans le
-- fil (Fenetre.leconChoisie, son id, remis à nil quand la conversation montrée change), sinon la
-- dernière leçon de la photo active dans la conversation montrée (une leçon dont la photo n'est pas
-- encore connue, appel sans photo_id en cours, compte pour la photo active), sinon l'aide
-- (Fenetre.AUCUNE_LECON) ; son texte vient de Fil.texteLecon, les axes en gras. Une leçon qui arrive
-- (faite : Fenetre.leconVue garde la dernière vue) devient celle que montre l'onglet, à la place
-- d'une leçon choisie avant, et fait basculer la fenêtre une fois vers Leçon, sauf
-- quand une proposition attend ou qu'un exercice « Je le fais » est en cours (Accepter et « J'ai
-- fini » resteraient cachés derrière l'onglet Leçon) : elle est alors seulement marquée vue. Une
-- proposition qu'une étape de Claude a close n'attend plus (1.3.2, Conversation.clorePropositions) :
-- la leçon qui suit « Applique ta proposition » s'ouvre. Les
-- leçons déjà là quand une conversation se montre (ouverture de la fenêtre, une autre conversation)
-- sont vues, sans bascule.

-- La dernière leçon faite de la conversation.
local function derniereLecon(c)
    for i = #(c and c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'lecon' and e.etat == 'fait' then
            return e
        end
    end
    return nil
end

-- La leçon que montre l'onglet, et son indice dans le fil ; nil sans leçon.
function Fenetre.leconMontree()
    local c = Moteur.courante
    if not c then
        return nil
    end
    if Fenetre.leconChoisie ~= nil then
        for i, e in ipairs(c.elements or {}) do
            if e.genre == 'lecon' and e.id == Fenetre.leconChoisie then
                return e, i
            end
        end
    end
    local active = Fenetre.info and Fenetre.info.active
    local cle = active and Conversation.clePhoto(active.id)
    for i = #(c.elements or {}), 1, -1 do
        local e = c.elements[i]
        if e.genre == 'lecon' and (e.photo == nil or (cle ~= nil and Conversation.clePhoto(e.photo) == cle)) then
            return e, i
        end
    end
    return nil
end

-- Vrai quand la carte Proposition attend Dany : une proposition en attente, ou un exercice « Je le
-- fais » à faire ou en préparation.
local function propositionOuExercice(c)
    local exo = Conversation.dernierExercice(c)
    return Conversation.propositionEnAttente(c) ~= nil or (exo ~= nil and (exo.etat == 'aFaire' or exo.etat == 'enCours'))
end

function Fenetre.rafraichirLecon()
    local p, T = Fenetre.p, Fenetre.T
    if not (p and T) then
        return
    end
    local c = Moteur.courante
    if Fenetre.leconDe ~= c then
        Fenetre.leconDe = c
        Fenetre.leconChoisie = nil
        local vue = derniereLecon(c)
        Fenetre.leconVue = vue and vue.id or nil
    end
    -- Une leçon qui arrive remplace la leçon choisie avant (« Leçon de la photo » d'une leçon plus
    -- ancienne) : l'onglet montre celle qui arrive, même d'une autre photo que l'active.
    local arrivee = derniereLecon(c)
    local nouvelle = arrivee ~= nil and arrivee.id ~= Fenetre.leconVue
    if nouvelle then
        Fenetre.leconVue = arrivee.id
        Fenetre.leconChoisie = nil
        if Fenetre.leconMontree() ~= arrivee then
            Fenetre.leconChoisie = arrivee.id
        end
    end
    local e = Fenetre.leconMontree()
    if e then
        poser(p, 'leconTitre', Fil.titreLecon(e) .. (e.etat == 'enCours' and " · en préparation…" or ''))
        local texte = Fil.texteLecon(e)
        Fenetre.montrerPage('lecon', texte ~= '' and texte or Fenetre.AUCUNE_LECON)
    else
        poser(p, 'leconTitre', "Leçon de la photo")
        Fenetre.montrerPage('lecon', Fenetre.AUCUNE_LECON)
    end
    poser(p, 'leconADetail', e ~= nil and Conversation.outilDeLAppel(c, e.appel) ~= nil)
    if nouvelle and not propositionOuExercice(c) then
        Fenetre.choisirOnglet(T.ongletLecon)
    end
end

-- « Détail… » de la carte (dans une tâche) : l'appel de photo_lesson de la leçon montrée, puis sa
-- réponse.
function Fenetre.detailLecon()
    local c = Moteur.courante
    local e = Fenetre.leconMontree()
    local outil = c and e and Conversation.outilDeLAppel(c, e.appel)
    if outil then
        Fenetre.montrerDetail(outil)
    end
end

-- Focus (demandé par Dany le 22 octobre 2026) ------------------------------------------------
-- L'onglet Focus, entre Aperçu et Proposition, montre la photo active comme le module Focus-Points
-- la montre : dans l'aperçu, sa vignette avec, pour un fichier Fujifilm, le point ou la zone de
-- mise au point à sa taille (rouge) et les visages et éléments du sujet que le boîtier a détectés
-- (coins jaunes), dessinés par le connecteur (`mcp-developpeur --focus`, Images.lireFocus) ;
-- dessous, la carte Image, Prise de vue et Mise au point (Fil.texteFocus), les valeurs de Lightroom
-- (Lightroom.infosFocus) et celles du boîtier, lues dans l'original. Autre marque : la photo sans
-- cadre, Image et Prise de vue, et « Mise au point : non lue (seulement les fichiers Fujifilm pour
-- l'instant) ». Copie virtuelle : l'original de la copie (Vignettes.decrireVignette).
-- Jamais de bascule d'elle-même vers Focus : seulement un vrai clic sur son segment. L'onglet suit
-- la photo active (Fenetre.majPhoto) ; tout se lit dans une tâche (Fenetre.lireFocus : la vignette
-- par Vignettes.demander, le boîtier par LrTasks.execute, cinq secondes au plus), une lecture à la
-- fois, jamais de calcul en Lua ; le résultat est gardé pour la photo (Fenetre.focus) tant qu'elle
-- ne change pas : un vrai clic sur le segment relit seulement si sa géométrie (cadre, orientation)
-- ou son édition (editCount, lastEditTime : une retouche) a changé, et la fin d'un tour de Claude
-- aussi quand l'onglet est montré (Fenetre.suivreFocus ; constaté le 22 octobre 2026 : après
-- « Retouche pro », l'onglet montrait encore la photo d'avant, et Dany a dû demander « reload
-- l'image »). L'aperçu des autres onglets, avec le carré de --marquer-af, ne change pas.

-- Juste après une retouche, Lightroom refait l'aperçu de la photo et répond « error loading thumb »
-- quelques instants (constaté le 22 octobre 2026 : l'onglet relu restait sans image) : la vignette
-- se redemande une fois par seconde, ESSAIS_VIGNETTE_FOCUS fois au plus.
Fenetre.ESSAIS_VIGNETTE_FOCUS = 8

-- La carte sans photo active.
Fenetre.FOCUS_AUCUNE_PHOTO = "Aucune photo active : choisissez une photo dans Lightroom."

-- Vrai quand l'onglet Focus est montré.
function Fenetre.focusMontre()
    local p, T = Fenetre.p, Fenetre.T
    return p ~= nil and T ~= nil and p.onglet == T.ongletFocus
end

-- Le résultat gardé, s'il est celui de la photo active et de cette ouverture de la fenêtre.
function Fenetre.focusActif()
    local r, active = Fenetre.focus, Fenetre.info and Fenetre.info.active
    if r and active and r.id == active.id and r.T == Fenetre.T then
        return r
    end
    return nil
end

-- Ce que l'onglet montre de la photo `active`, lu dans une tâche : sa description
-- (Vignettes.decrireVignette), les valeurs de Lightroom, sa vignette (un dossier à elle sous
-- PhotoActive), puis, pour un fichier Fujifilm, le boîtier et les cadres par le connecteur. Rend
-- { id, signature (la géométrie), T, chemin (la vignette réduite au cadre de l'aperçu), dossier et
-- fichier (la vignette, marquée s'il y a des cadres : Agrandir), titre, texte } ; nil si `garde`
-- est déjà le résultat de cette photo à cette géométrie (rien à relire).
function Fenetre.preparerFocus(active, T, garde)
    local Vignettes = require 'Vignettes'
    local photo = require('Photos').photoParId(active.id)
    local d = photo and Vignettes.decrireVignette(photo) or {}
    -- La géométrie et l'édition : une retouche change editCount et lastEditTime (Ecriture.lua les
    -- suit de même pour apresClaude).
    local edition = {}
    for _, cle in ipairs({ 'editCount', 'lastEditTime' }) do
        local ok, valeur = LrTasks.pcall(function() return photo and photo:getRawMetadata(cle) end)
        edition[#edition + 1] = ok and tostring(valeur) or '?'
    end
    local signature = Json.encode(type(d.geometrie) == 'table' and d.geometrie or {}) .. '|' .. table.concat(edition, '|')
    if garde and garde.id == active.id and garde.T == T and garde.signature == signature then
        return nil
    end
    local infos = Lightroom.infosFocus(active.id)
    local dossier = LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'PhotoActive'), 'Focus-' .. Conversation.identifiant())
    local chemins = Vignettes.demander({ active.id }, Fenetre.TAILLE_PHOTO_ACTIVE, dossier)
    local source = chemins[active.id]
    local essais = 1
    while not source and essais < Fenetre.ESSAIS_VIGNETTE_FOCUS do
        LrTasks.sleep(1)
        essais = essais + 1
        source = Vignettes.demander({ active.id }, Fenetre.TAILLE_PHOTO_ACTIVE, dossier)[active.id]
    end
    if not source then
        -- Toujours sans vignette : pas de signature, le prochain vrai clic (ou la fin d'un tour de
        -- Claude) relit.
        signature = nil
    end
    local etat, boitier, marquee = 'autre_marque', nil, nil
    if Fenetre.estFujifilm(d) then
        local connecteur = Chemins.prefs().cheminConnecteur
        if type(connecteur) ~= 'string' or not Fichiers.existe(connecteur) then
            etat = 'sans_connecteur'
        else
            local raison
            boitier, marquee, raison = Images.lireFocus(connecteur, d.chemin_original, d.geometrie, source)
            -- Rien de lu : la raison que le connecteur a dite ('delai', 'introuvable', 'illisible' :
            -- Fil.texteFocus), sinon 'non_lue'.
            etat = boitier and 'lue' or raison or 'non_lue'
        end
    end
    local r = { id = active.id, signature = signature, T = T, titre = Fil.titreFocus(infos), texte = Fil.texteFocus(infos, boitier, etat),
        dossier = dossier }
    local image = marquee or source
    if image then
        r.fichier = LrPathUtils.leafName(image)
        r.chemin = vignetteApercu(T, LrPathUtils.parent(image), r.fichier)
    end
    return r
end

-- Lit l'onglet de la photo `active` dans une tâche (une lecture à la fois par photo) ; `verifier` :
-- relit seulement si sa géométrie ou son édition a changé depuis le résultat gardé. À la fin, la carte et, si
-- l'onglet est montré, l'aperçu ; rien si la photo n'est plus active (une autre a été choisie
-- pendant la lecture) ; une erreur garde un résultat d'échec pour la photo.
function Fenetre.lireFocus(active, verifier)
    if Fenetre.lectureFocus == active.id then
        return
    end
    Fenetre.lectureFocus = active.id
    local T = Fenetre.T
    local garde = verifier and Fenetre.focus or nil
    LrTasks.startAsyncTask(function()
        local ok, r = LrTasks.pcall(Fenetre.preparerFocus, active, T, garde)
        if Fenetre.lectureFocus == active.id then
            Fenetre.lectureFocus = nil
        end
        if not ok then
            Journal.noter("Onglet Focus :", tostring(r))
            -- Un résultat d'échec pour la photo : la carte dit « non lue », et l'aperçu ne relance
            -- pas la lecture à chaque rafraîchissement. Sans signature, un vrai clic sur le segment
            -- la relance.
            local legende = legendeActive(active)
            local infos = { nom = legende.nom, copie = legende.copie }
            r = { id = active.id, T = T, titre = Fil.titreFocus(infos), texte = Fil.texteFocus(infos, nil, 'non_lue') }
        end
        if not r then
            return
        end
        -- Une autre photo est devenue active pendant la lecture : ce résultat ne sert plus, son
        -- dossier s'efface ; celui de la photo active (lu entre-temps, ou à lire) n'est pas touché.
        local actuelle = Fenetre.info and Fenetre.info.active
        if not actuelle or actuelle.id ~= r.id then
            if r.dossier then
                Fichiers.supprimer(r.dossier)
            end
            return
        end
        -- La vignette d'avant n'est plus montrée : son dossier s'efface.
        local avant = Fenetre.focus
        if avant and avant.dossier and avant.dossier ~= r.dossier then
            Fichiers.supprimer(avant.dossier)
        end
        Fenetre.focus = r
        if Fenetre.p and Fenetre.T == T then
            Fenetre.rafraichirFocus()
            if Fenetre.focusMontre() then
                Fenetre.rafraichirApercu()
            end
        end
    end)
end

-- La carte de l'onglet : le résultat gardé de la photo active, sinon « lecture… » (la lecture part
-- si l'onglet est montré : un onglet caché ne lit rien) ; sans photo active, l'aide. `relire` (un
-- vrai clic sur le segment) : relit si la géométrie de la photo a changé.
function Fenetre.rafraichirFocus(relire)
    local p = Fenetre.p
    if not p then
        return
    end
    local active = Fenetre.info and Fenetre.info.active
    if not active then
        poser(p, 'focusTitre', "Focus")
        Fenetre.montrerPage('focus', Fenetre.FOCUS_AUCUNE_PHOTO)
        return
    end
    local r = Fenetre.focusActif()
    if r then
        poser(p, 'focusTitre', r.titre)
        Fenetre.montrerPage('focus', r.texte)
        if relire then
            Fenetre.lireFocus(active, true)
        end
        return
    end
    local legende = legendeActive(active)
    local infos = { nom = legende.nom, copie = legende.copie }
    poser(p, 'focusTitre', Fil.titreFocus(infos))
    Fenetre.montrerPage('focus', Fil.texteFocus(infos, nil, 'lecture'))
    if Fenetre.focusMontre() then
        Fenetre.lireFocus(active)
    end
end

-- L'aperçu de l'onglet Focus (Fenetre.apercuOnglet) : la vignette de la photo active avec ses
-- cadres (ou sans, autre marque), sa légende ; l'image vide pendant la lecture ; ◀ ▶ coupés.
Fenetre.apercuOnglet.focus = function(p, T)
    poser(p, 'peutPrecedente', false)
    poser(p, 'peutSuivante', false)
    local active = Fenetre.info and Fenetre.info.active
    if not active then
        poser(p, 'imageApercu', Fenetre.imageVide())
        poser(p, 'aImage', false)
        poser(p, 'legendeApercu', "Aucune photo active")
        return true
    end
    poser(p, 'legendeApercu', Fenetre.texteLegende(legendeActive(active)))
    local r = Fenetre.focusActif()
    if r and r.chemin then
        poser(p, 'imageApercu', r.chemin)
        poser(p, 'aImage', true)
        return true
    end
    poser(p, 'imageApercu', Fenetre.imageVide())
    poser(p, 'aImage', false)
    if not r then
        Fenetre.rafraichirFocus()
    end
    return true
end

-- Un vrai clic sur l'onglet Focus : la carte de la photo active, relue si sa géométrie ou son
-- édition a changé.
Fenetre.surOnglet.focus = function()
    Fenetre.rafraichirFocus(true)
end

-- Depuis la boucle : à la fin d'un tour de Claude (Moteur.finTravail change), si l'onglet Focus est
-- montré avec un résultat gardé, la photo active se relit si elle a été retouchée (même règle qu'un
-- vrai clic) ; onglet caché, rien.
function Fenetre.suivreFocus()
    local fin = Moteur.finTravail
    if fin == Fenetre.finTravailFocus then
        return
    end
    Fenetre.finTravailFocus = fin
    local active = Fenetre.info and Fenetre.info.active
    if active and Fenetre.focusMontre() and Fenetre.focusActif() then
        Fenetre.lireFocus(active, true)
    end
end

-- Proposition ---------------------------------------------------------------------------------
-- La carte Proposition montre la proposition en attente, ou l'exercice « Je le fais » (1.3) arrivé
-- après elle (Conversation.dernierExercice : une proposition en attente arrivée après l'exercice
-- reprend la carte, et la lui rend une fois décidée s'il est encore à faire) : sa liste à faire,
-- cochée au fil de ce que Dany change (Fenetre.suivreExercice), puis sa comparaison, jusqu'à la
-- proposition suivante. Sans l'une ni l'autre, la dernière proposition si une étape de Claude sur
-- sa photo l'a close (1.3.2, Conversation.propositionClose) : sa phrase en tête
-- (Fenetre.phraseClose), Accepter, Refuser et Ajuster… grisés.

Fenetre.AUCUNE_PROPOSITION = "Aucune proposition en attente.\n\nEn mode « Proposer d'abord », Claude montre ici ce "
    .. "qu'il compte changer et attend votre accord.\n\n« Je le fais » : vous faites la retouche vous-même ; Claude donne "
    .. "les réglages dans l'ordre du panneau Développement, puis compare votre version à la sienne."

-- `garderPage` : le texte d'un exercice dont un réglage vient d'être coché reste à sa page.
function Fenetre.rafraichirProposition(garderPage)
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    local exo = c and Conversation.dernierExercice(c)
    poser(p, 'enAttente', prop ~= nil and not Moteur.travaille)
    poser(p, 'aProposition', prop ~= nil)
    Fenetre.rafraichirJeLeFais()
    -- Une proposition qui arrive se montre (onglet Proposition) ; une
    -- seule fois, pour ne pas reprendre la main à chaque rafraîchissement.
    if prop and prop.id ~= Fenetre.propositionVue then
        Fenetre.propositionVue = prop.id
        -- Celle préparée à l'ouverture attend que Dany clique Proposition.
        if not Fenetre.propositionAuto then
            Fenetre.choisirOnglet(Fenetre.T.ongletProposition)
        end
    end
    -- De même la liste d'un exercice, puis chacune de ses comparaisons : une bascule chacune.
    local vu = Fenetre.cleExerciceVu(exo)
    if vu and vu ~= Fenetre.exerciceVu then
        Fenetre.exerciceVu = vu
        Fenetre.choisirOnglet(Fenetre.T.ongletProposition)
    end
    if exo then
        Fenetre.montrerPage('proposition', Fenetre.texteExercice(exo, Fenetre.faitsDe(exo)), garderPage)
        return
    end
    if not prop then
        -- Une proposition qu'une étape de Claude a close (1.3.2) : la carte dit pourquoi, sans
        -- Accepter, Refuser ni Ajuster… (enAttente est faux).
        local close = c and Conversation.propositionClose(c)
        Fenetre.montrerPage('proposition', close and Fenetre.texteProposition(close) or Fenetre.AUCUNE_PROPOSITION)
        return
    end
    Fenetre.montrerPage('proposition', Fenetre.texteProposition(prop))
end

-- La phrase en tête d'une proposition close par une étape de Claude (1.3.2,
-- Conversation.clorePropositions) : « Appliquée par Claude (étape « passe 1 : lumière et
-- couleur ») : elle n'attend plus votre accord. » ; nil pour une autre.
function Fenetre.phraseClose(prop)
    local debut = prop and Conversation.ETATS_CLAUDE[prop.etat]
    if not debut then
        return nil
    end
    local etape = type(prop.etapeClaude) == 'string' and Texte.nettoyer(prop.etapeClaude) or ''
    return debut .. (etape ~= '' and (" (étape « " .. etape .. " »)") or '') .. " : elle n'attend plus votre accord."
end

-- Ce que montre l'aperçu d'une proposition de recadrage (Composition lue, 1.3) : l'image entière
-- que le connecteur a dessinée ; sans elle (image entière pas rendue), seulement l'accord attendu.
Fenetre.CADRE_DESSINE = "Son aperçu : l'image entière, le cadre proposé en pointillés, les tiers et le hors-cadre assombri. Rien ne change avant Accepter."
Fenetre.CADRE_SANS_DESSIN = "Rien ne change avant Accepter."

-- Le texte de la carte pour une proposition en attente (pure) : sa raison, puis, pour une
-- proposition de recadrage dont le connecteur a dit le cadre gardé (Conversation.cadreLu), la
-- ligne « Cadre : <résumé> » et ce que montre son aperçu, à la place des bords du recadrage (les
-- changements Crop…, illisibles pour Dany, et de la ligne « Recadrage » demandée, restée si les
-- changements de la réponse ne se sont pas lus) ; puis chaque autre changement, « libellé : avant
-- → après ». Sans résumé du cadre, les changements Crop… restent : ils sont seuls à le dire. Une
-- proposition close par une étape de Claude (1.3.2) commence par sa phrase (Fenetre.phraseClose),
-- sans ce que montrerait son aperçu avant Accepter.
function Fenetre.texteProposition(prop)
    local close = Fenetre.phraseClose(prop)
    local lignes = { Texte.nettoyer(prop.texte) ~= '' and prop.texte or "Claude propose :", '' }
    if close then
        table.insert(lignes, 1, '')
        table.insert(lignes, 1, close)
    end
    local cadre = type(prop.cadre) == 'string' and Texte.nettoyer(prop.cadre) or ''
    if cadre ~= '' then
        lignes[#lignes + 1] = "Cadre : " .. cadre
        if not close then
            lignes[#lignes + 1] = prop.cadreDessine == true and Fenetre.CADRE_DESSINE or Fenetre.CADRE_SANS_DESSIN
        end
    end
    local autres = {}
    for _, ch in ipairs(prop.changements or {}) do
        local duCadre = (type(ch.cle) == 'string' and ch.cle:sub(1, 4) == 'Crop') or (ch.cle == nil and ch.libelle == Conversation.LIBELLE_RECADRAGE)
        if not (cadre ~= '' and duCadre) then
            autres[#autres + 1] = string.format("%s : %s → %s", ch.libelle or '?', ch.avant or '—', ch.apres or '—')
        end
    end
    if cadre ~= '' and #autres > 0 then
        lignes[#lignes + 1] = ''
    end
    for _, ligne in ipairs(autres) do
        lignes[#lignes + 1] = ligne
    end
    return table.concat(lignes, '\n')
end

-- Je le fais (1.3) ------------------------------------------------------------------------------
-- Le bouton de la seconde rangée de la carte Proposition (titre lié : « Je le fais », puis
-- « J'ai fini » pendant un exercice) : Dany fait la retouche lui-même, pour apprendre. Claude ne
-- pose rien : il range sa version (preview_settings avec my_turn) et donne la liste des réglages
-- dans l'ordre du panneau Développement ; la fenêtre les coche au fil de ce que Dany change (lu
-- toutes les 2 s, Fenetre.suivreExercice) ; « J'ai fini » fait comparer les deux versions
-- (view_photo avec compare = claude_version), montrées côte à côte dans l'aperçu de l'onglet
-- Proposition. Actif quand Claude est libre et qu'il y a un exercice en cours, une proposition en
-- attente ou une photo active.

-- Ce qui fait basculer vers l'onglet Proposition, une fois chacun : la liste d'un exercice, puis
-- chacune de ses comparaisons (nil : rien à montrer).
function Fenetre.cleExerciceVu(exo)
    if exo and exo.etat == 'aFaire' then
        return exo.id .. '/aFaire'
    elseif exo and exo.etat == 'comparee' then
        return exo.id .. '/comparee/' .. tostring(exo.appelCompare or exo.appelComparaison)
    end
    return nil
end

-- L'état de l'exercice montré, à droite du bouton (« À vous · 3 réglages faits sur 7 »).
function Fenetre.etatExercice(exo, faits)
    if not exo then
        return ''
    elseif exo.etat == 'enCours' then
        return "Liste en préparation…"
    elseif exo.etat == 'erreur' then
        return "Je le fais n'a pas abouti"
    elseif exo.comparaisonEnCours then
        return "Comparaison en cours…"
    elseif exo.etat == 'comparee' then
        local ecarts, total = Fil.ecartsExercice(exo)
        return "Comparée : " .. (ecarts == 0 and "aucun écart" or (ecarts .. (ecarts > 1 and " écarts" or " écart"))) .. " sur " .. total
    elseif type(exo.comparaisonRefusee) == 'string' then
        -- Un refus qui peut se refaire : la raison est dans la carte, « J'ai fini » se refait.
        return "Comparaison non aboutie : réessayez"
    end
    local total, n = #(exo.aFaire or {}), faits and faits.nombre or 0
    if n == 0 then
        return "À vous · " .. total .. (total > 1 and " réglages à faire" or " réglage à faire")
    end
    return "À vous · " .. n .. (n > 1 and " réglages faits" or " réglage fait") .. " sur " .. total
end

-- Le bouton et l'état de l'exercice (aussi quand la photo active change : sans proposition ni
-- exercice, il faut une photo active).
function Fenetre.rafraichirJeLeFais()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    local enCours = c and Conversation.exerciceEnCours(c)
    local prop = c and Conversation.propositionEnAttente(c)
    local active = Fenetre.info and Fenetre.info.active
    poser(p, 'titreJeLeFais', enCours and "J'ai fini" or "Je le fais")
    poser(p, 'peutJeLeFais', not Moteur.travaille and not Fenetre.jeLeFaisEnCours and (enCours ~= nil or prop ~= nil or active ~= nil))
    local exo = c and Conversation.dernierExercice(c)
    poser(p, 'exerciceEtat', Fenetre.etatExercice(exo, Fenetre.faitsDe(exo)))
end

-- Le texte d'un réglage ou d'un écart sans son panneau (montré en tête de son groupe).
local function sansPanneau(texte, panneau)
    texte = tostring(texte or '')
    local tete = panneau and (panneau .. ' › ')
    if tete and texte:sub(1, #tete) == tete then
        return texte:sub(#tete + 1)
    end
    return texte
end

-- Des lignes groupées par panneau : le nom du panneau quand il change, puis chaque ligne.
local function parPanneau(lignes, elements, ligne)
    local panneau
    for k, x in ipairs(elements) do
        if x.panneau and x.panneau ~= panneau then
            panneau = x.panneau
            lignes[#lignes + 1] = panneau
        end
        lignes[#lignes + 1] = ligne(k, x)
    end
end

-- Le texte de la carte Proposition pour un exercice (pure) : la liste à faire, dans l'ordre du
-- panneau Développement et groupée par panneau, chaque réglage coché ✓ s'il a bougé (`faits`,
-- Fenetre.reglagesFaits), ○ sinon ; comparé, le résumé, l'écart principal et chaque écart (✓ fait
-- comme Claude) ; refusé, pourquoi.
function Fenetre.texteExercice(exo, faits)
    local lignes = {}
    if exo.etat == 'enCours' then
        return "Claude prépare la liste des réglages à faire vous-même. Rien n'est appliqué à la photo."
    elseif exo.etat == 'erreur' then
        local raison = Texte.nettoyer(exo.texte or '')
        return "« Je le fais » n'a pas abouti" .. (raison ~= '' and (" : " .. raison) or ".")
            .. "\n\nCliquez « Je le fais » pour recommencer, ou demandez à Claude."
    end
    -- Une comparaison refusée qui peut se refaire (Conversation.completerExercice) : l'exercice reste
    -- où il en était, et la carte dit pourquoi.
    local refus = type(exo.comparaisonRefusee) == 'string' and Texte.nettoyer(exo.comparaisonRefusee) or ''
    if exo.etat == 'comparee' then
        lignes[#lignes + 1] = "Votre version comparée à celle de Claude" .. (exo.fichier and (" (" .. exo.fichier .. ")") or "") .. "."
        if refus ~= '' then
            lignes[#lignes + 1] = "La comparaison suivante n'a pas abouti (" .. refus .. ") : voici la précédente."
        end
        if Texte.nettoyer(exo.resume or '') ~= '' then
            lignes[#lignes + 1] = exo.resume
        end
        local principal = Fil.textePrincipal(exo)
        if principal ~= '' then
            lignes[#lignes + 1] = ''
            lignes[#lignes + 1] = principal
        end
        lignes[#lignes + 1] = ''
        parPanneau(lignes, exo.ecarts or {}, function(_, x)
            return (x.sorte == 'comme_claude' and '✓ ' or '• ') .. sansPanneau(x.texte or x.reglage, x.panneau)
        end)
        if Texte.nettoyer(exo.aSavoir or '') ~= '' then
            lignes[#lignes + 1] = ''
            lignes[#lignes + 1] = exo.aSavoir
        end
        lignes[#lignes + 1] = ''
        lignes[#lignes + 1] = "La version de Claude reste en instantané « " .. (exo.instantane or "Claude · ma version")
            .. " » : demandez-lui de la poser si vous la préférez."
        return table.concat(lignes, '\n')
    end
    local fait = faits and faits.reglages or {}
    lignes[#lignes + 1] = "À vous : faites ces réglages dans le module Développement, dans cet ordre, puis cliquez « J'ai fini ». "
        .. "Rien n'est appliqué : la version de Claude est rangée en instantané « " .. (exo.instantane or "Claude · ma version") .. " »."
    if exo.comparaisonEnCours then
        lignes[#lignes + 1] = "Claude compare votre version à la sienne…"
    elseif refus ~= '' then
        lignes[#lignes + 1] = "La comparaison n'a pas abouti (" .. refus .. ") : cliquez de nouveau « J'ai fini »."
    end
    lignes[#lignes + 1] = ''
    parPanneau(lignes, exo.aFaire or {}, function(k, x)
        return (fait[k] and '✓ ' or '○ ') .. tostring(tonumber(x.n) or k) .. '. ' .. sansPanneau(x.texte or x.reglage, x.panneau)
    end)
    return table.concat(lignes, '\n')
end

-- Les clés que Lightroom range pour les réglages d'un exercice (les cinq du cadre pour sa ligne).
function Fenetre.clesExercice(exo)
    local cles, vues = {}, {}
    for _, x in ipairs(exo.aFaire or {}) do
        for _, cle in ipairs(type(x.cles) == 'table' and x.cles or { x.cle }) do
            if type(cle) == 'string' and not vues[cle] then
                vues[cle] = true
                cles[#cles + 1] = cle
            end
        end
    end
    return cles
end

-- Vrai si une valeur lue a bougé depuis `avant` (sa valeur au départ, dans la liste) ; faux si non,
-- nil si on ne peut pas le dire (valeur non lue, ou d'une autre nature).
local function abouge(avant, lue)
    if avant == nil or lue == nil then
        return nil
    elseif type(avant) == 'number' and type(lue) == 'number' then
        return math.abs(lue - avant) > 1e-6
    elseif type(avant) == 'boolean' and type(lue) == 'boolean' then
        return avant ~= lue
    elseif type(avant) == 'string' and type(lue) == 'string' then
        return avant ~= lue
    end
    return nil
end

-- Les réglages déjà faits d'un exercice (pure) : { reglages = { [rang dans la liste] = true },
-- nombre }. Un réglage est fait quand sa valeur lue (Lightroom.valeurs) a bougé depuis `avant` ;
-- une table (courbe…) aussi quand sa signature a changé depuis le début du suivi
-- (`exo.signatures`) ; le cadre, quand l'une de ses clés a bougé.
function Fenetre.reglagesFaits(exo, valeurs, signatures)
    local faits = { reglages = {}, nombre = 0 }
    local depart = type(exo.signatures) == 'table' and exo.signatures or {}
    for k, x in ipairs(exo.aFaire or {}) do
        local fait = false
        if type(x.cles) == 'table' then
            for _, cle in ipairs(x.cles) do
                local avant = type(x.avant) == 'table' and x.avant[cle] or nil
                fait = fait or abouge(avant, valeurs[cle]) == true
            end
        else
            fait = abouge(x.avant, valeurs[x.cle]) == true
            local sig = signatures and signatures[x.cle]
            if not fait and sig ~= nil and depart[x.cle] ~= nil and depart[x.cle] ~= sig then
                fait = true
            end
        end
        if fait then
            faits.reglages[k] = true
            faits.nombre = faits.nombre + 1
        end
    end
    return faits
end

-- Le suivi de l'exercice montré, s'il est celui de `exo` (nil sinon).
function Fenetre.faitsDe(exo)
    local s = Fenetre.suivi
    return exo and s and s.id == exo.id and s.faits or nil
end

-- Toutes les 2 s (Fenetre.periodique) : les réglages de la photo de l'exercice en cours, relus
-- dans le catalogue (Lightroom.valeurs, sans rien écrire) ; ce qui a bougé se coche, et l'état dit
-- combien. Les tables lues au premier suivi servent de départ à la signature (gardées dans
-- l'exercice). Depuis une tâche.
function Fenetre.suivreExercice()
    local c = Moteur.courante
    local exo = c and Conversation.exerciceEnCours(c)
    if not Fenetre.p or not exo or exo.photo == nil then
        Fenetre.suivi = nil
        return
    end
    local valeurs, signatures = Lightroom.valeurs(exo.photo, Fenetre.clesExercice(exo))
    if next(valeurs) == nil then
        return
    end
    if type(exo.signatures) ~= 'table' then
        exo.signatures = {}
        for cle, sig in pairs(signatures) do
            exo.signatures[cle] = sig
        end
    end
    Fenetre.suivi = { id = exo.id, faits = Fenetre.reglagesFaits(exo, valeurs, signatures) }
    if Fenetre.p then
        Fenetre.rafraichirProposition(true)
    end
end

-- L'action du bouton (depuis une tâche) : « J'ai fini » pendant un exercice, sinon « Je le fais ».
-- C'est une demande de Dany (une proposition préparée à l'ouverture ne retient plus l'onglet).
-- « Je le fais » sans proposition porte sur la photo active : la conversation devient celle de la
-- sélection, comme Envoyer ; avec une proposition, ou « J'ai fini » (Dany peut regarder une autre
-- photo), elle reste celle de sa photo. Un second clic avant l'envoi du premier (la lecture de la
-- photo active attend) ne fait rien : le bouton est rendu inactif dès le clic.
local function jeLeFais()
    local c = Moteur.courante
    local enCours = c and Conversation.exerciceEnCours(c)
    local prop = c and Conversation.propositionEnAttente(c)
    Fenetre.propositionAuto = false
    local info = Lightroom.photos()
    local ok, raison
    if enCours then
        ok, raison = Moteur.jaiFini()
    else
        ok, raison = Moteur.jeLeFais()
        -- Le Mode reste à « Je le fais » pendant que Claude prépare la liste (Fenetre.modeMontre).
        if ok then
            Fenetre.demandeJeLeFais = Moteur.courante
        end
    end
    local nouvellePhoto = not enCours and not prop
    if ok and Moteur.courante and info.cle and (nouvellePhoto or Moteur.courante.cle == nil) then
        Moteur.courante.cle = info.cle
        Fenetre.voirSelection(info.cle)
    end
    if Fenetre.p then
        Fenetre.p.message = ok and '' or (raison or '')
    end
end

function Fenetre.jeLeFais()
    if Moteur.travaille or Fenetre.jeLeFaisEnCours then
        return
    end
    Fenetre.jeLeFaisEnCours = true
    if Fenetre.p then
        poser(Fenetre.p, 'peutJeLeFais', false)
    end
    local ok, erreur = LrTasks.pcall(jeLeFais)
    Fenetre.jeLeFaisEnCours = false
    Fenetre.aRafraichir = true
    if not ok then
        error(erreur, 0)
    end
end

-- La comparaison montrée par l'onglet Proposition : celle de l'exercice montré, comparé, s'il n'y a
-- pas d'image cliquée dans le fil. Rend la conversation et le chemin de l'image, nil sinon.
function Fenetre.comparaisonMontree()
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    if not (p and T and c) or p.onglet ~= T.ongletProposition or Fenetre.imageCliquee then
        return nil
    end
    local exo = Conversation.dernierExercice(c)
    local chemin = exo and exo.etat == 'comparee' and Conversation.imageComparaison(c, exo) or nil
    if not chemin then
        return nil
    end
    return c, chemin, exo
end

-- L'aperçu de l'onglet Proposition (Fenetre.apercuOnglet) : la comparaison « Claude | vous » d'un
-- exercice comparé (ses ◀ ▶ coupés) ; sinon nil, l'aperçu d'avant. L'image d'une proposition
-- demandée par un clic (Composition lue) se compose avec elle dans le crochet de l'onglet, après
-- elle : un seul crochet par onglet.
function Fenetre.apercuExercice(p, T)
    local c, chemin, exo = Fenetre.comparaisonMontree()
    if not chemin then
        return nil
    end
    poser(p, 'peutPrecedente', false)
    poser(p, 'peutSuivante', false)
    poser(p, 'aImage', true)
    poser(p, 'legendeApercu', Fenetre.LEGENDE_COMPARAISON .. (exo.fichier and (" · " .. exo.fichier) or ""))
    Fenetre.montrerImage(p, T, c, chemin)
    return true
end

-- L'image de la proposition en attente, sur un vrai clic sur l'onglet Proposition (Composition lue,
-- 1.3 ; Fenetre.surOnglet.proposition) : pour un recadrage, l'image entière avec le cadre proposé en
-- pointillés. Dany a pu regarder d'autres images ou la photo active entre-temps : l'aperçu la
-- remontre, et le crochet de l'onglet la garde (Fenetre.apercuProposition) jusqu'à ◀ ▶, une image
-- nouvelle, une autre conversation ou la proposition décidée. Une bascule de la fenêtre ne la
-- demande pas : la proposition qui arrive est déjà la dernière image. Fenetre.imageProposition =
-- { conversation, proposition (son id), chemin } : la demande du clic. Vrai si l'image est montrée.
-- Ce que montre l'onglet Note ne change pas (l'aperçu appartient à l'onglet) : ni la photo active
-- (Fenetre.voirActive) ni l'image choisie (Fenetre.indiceImage) ; seuls ◀ ▶ partis de l'image de
-- la proposition les posent (Fenetre.changerImage).
function Fenetre.montrerImageProposition()
    local p, c = Fenetre.p, Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    Fenetre.imageProposition = nil
    if not (p and prop) then
        return false
    end
    local images = Conversation.images(c)
    local indice
    for n, image in ipairs(images) do
        if c.elements[image.element] == prop then
            indice = n
        end
    end
    if not indice then
        return false
    end
    Fenetre.imageProposition = { conversation = c, proposition = prop.id, chemin = images[indice].chemin }
    Fenetre.images, Fenetre.apercuDe, Fenetre.nbImages = images, c, #images
    Fenetre.imageCliquee = nil
    Fenetre.rafraichirApercu()
    return true
end

-- L'image de proposition demandée par un clic, si l'onglet Proposition la montre : la conversation
-- et son rang dans les images (Fenetre.images) tant que la demande vaut (onglet Proposition, ni
-- image cliquée dans le fil ni comparaison montrée, même conversation, la même proposition
-- toujours en attente, son image toujours là) ; nil sinon.
function Fenetre.imagePropositionMontree()
    local im, p, T, c = Fenetre.imageProposition, Fenetre.p, Fenetre.T, Moteur.courante
    if not (im and p and T and c) or im.conversation ~= c or p.onglet ~= T.ongletProposition or Fenetre.imageCliquee
        or Fenetre.comparaisonMontree() then
        return nil
    end
    local prop = Conversation.propositionEnAttente(c)
    if not prop or prop.id ~= im.proposition then
        return nil
    end
    for n, image in ipairs(Fenetre.images or {}) do
        if image.chemin == im.chemin then
            return c, n
        end
    end
    return nil
end

-- L'aperçu de l'onglet Proposition après la comparaison : l'image de proposition demandée par un
-- clic, avec ses ◀ ▶ (ils partent d'elle, Fenetre.changerImage), même si la photo active a changé
-- entre-temps ; une demande qui ne vaut plus est oubliée (nil : l'aperçu d'avant).
function Fenetre.apercuProposition(p, T)
    if not Fenetre.imageProposition then
        return nil
    end
    local c, indice = Fenetre.imagePropositionMontree()
    if not indice then
        Fenetre.imageProposition = nil
        return nil
    end
    montrerNumero(p, T, c, indice)
    return true
end

Fenetre.apercuOnglet.proposition = function(p, T)
    return Fenetre.apercuExercice(p, T) or Fenetre.apercuProposition(p, T)
end

-- Un vrai clic sur l'onglet Proposition : l'image de la proposition en attente.
Fenetre.surOnglet.proposition = function()
    Fenetre.montrerImageProposition()
end

function Fenetre.repondreProposition(acceptee)
    LrTasks.startAsyncTask(function() Moteur.repondre(acceptee) end)
end

-- Ajuster… : ce qu'il faut changer, tapé ou pris parmi les ajustements d'un clic (ceux du cadre
-- pour une proposition de recadrage, Composition lue, 1.3), envoyé à Claude (Moteur.ajuster). Une
-- boîte modale construite à chaque ouverture, hors de la fenêtre : ses boutons varient.
function Fenetre.ajuster()
    local f = LrView.osFactory()
    local texte = ''
    local c = Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    local cadre = prop ~= nil and prop.recadrage == true
    LrFunctionContext.callWithContext('Claude · ajuster', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.texte = ''
        local rapides = { spacing = 6 }
        for _, a in ipairs(cadre and Consignes.ajustementsCadre or Consignes.ajustementsRapides) do
            rapides[#rapides + 1] = f:push_button { title = a, action = function()
                q.texte = Texte.nettoyer(q.texte) == '' and a or (Texte.nettoyer(q.texte) .. ", " .. a:lower())
            end }
        end
        local reponse = LrDialogs.presentModalDialog {
            title = "Ajuster la proposition",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                f:static_text { title = cadre and "Ce qu'il faut changer au cadre avant de l'appliquer :" or "Ce qu'il faut changer avant d'appliquer :" },
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

-- Pourquoi ? : l'onglet Aperçu (1.3) -----------------------------------------------------------
-- Le bouton « Pourquoi ? » d'une étape du fil (la ligne de son appel, Conversation.estEtape ;
-- Fenetre.pourquoi), ou un clic sur son texte, l'ouvre dans l'onglet Aperçu (l'ancien onglet
-- Pourquoi ?, D.ongletEtape) : dans l'aperçu, son après (ou son avant : Voir l'avant / Voir l'après), que
-- le module a gardé au moment de l'étape sans rien écrire au catalogue (Etapes.lua) ; dans la
-- carte (Vues.etape), « Étape 2 sur 4 · <but> », la raison donnée par Claude et les réglages
-- changés, page par page ; ◀ ▶ d'une étape à l'autre de la même photo ; Détail… (l'appel et sa
-- réponse) ; Agrandir, l'avant et l'après côte à côte (Fenetre.agrandirDeux).
-- Fenetre.etape = { conversation, photo, id (etape_id du module, nil sans), element (id de
-- l'élément du fil), vue ('apres' ou 'avant'), suivre } : l'étape montrée, remise à nil quand la
-- conversation montrée change. En mode suivre (la dernière étape de sa photo, ou l'onglet ouvert
-- sans étape choisie), une nouvelle étape de la même photo devient l'étape montrée ; ◀ le quitte,
-- ▶ jusqu'à la dernière le reprend. Jamais de bascule automatique vers l'onglet Aperçu : un
-- clic seulement (sur l'onglet ou sur une étape du fil). La boucle suit Etapes.version : les
-- images arrivées se montrent. Les ◀ ▶ de l'aperçu sont coupés dans l'onglet (Fenetre.changerImage).

Fenetre.AIDE_ETAPE = "Cliquez « Pourquoi ? » sur une étape du fil : son avant/après s'affiche au-dessus, et sa raison ici."
-- Le titre de la carte sans étape choisie (celui de la boîte de groupe d'avant la fenêtre B).
Fenetre.TITRE_ETAPE = "Pourquoi ?"

-- Pourquoi une étape n'a pas d'avant/après, en mots (les raisons du module : Etapes.RAISONS).
Fenetre.SANS_IMAGES = {
    inconnu = "rien n'a été gardé pour cette étape (fenêtre Claude fermée, case Avant/après décochée, plusieurs photos ou une autre que la photo active)",
    ancienne = "étape d'avant la version 1.3",
    classement = "un classement ne change pas l'image",
}

local function elementParId(c, id)
    for i, e in ipairs(c and c.elements or {}) do
        if e.id == id then
            return i, e
        end
    end
    return nil
end

-- Le rang d'une étape dans la liste de sa photo : son élément du fil, et son id s'il est connu.
local function rangEtape(liste, element, id)
    for n, x in ipairs(liste) do
        if x.elementId == element and (id == nil or x.id == nil or x.id == id) then
            return n
        end
    end
    return nil
end

-- La photo d'une étape du fil : la photo active si l'étape la touche, sinon la première de sa
-- réponse ; la photo active pour un appel en cours (sa photo n'est connue qu'à la réponse).
function Fenetre.photoDeLEtape(e)
    local active = Fenetre.info and Fenetre.info.active and Fenetre.info.active.id
    local photos = Conversation.photosEtape(e)
    for _, photo in ipairs(photos) do
        if active ~= nil and Conversation.clePhoto(photo) == Conversation.clePhoto(active) then
            return photo
        end
    end
    return photos[1] or active
end

-- Vrai quand l'aperçu montre une étape : onglet Aperçu, une étape choisie, pas d'image
-- cliquée dans le fil (prioritaire).
function Fenetre.modeEtape()
    local p, T = Fenetre.p, Fenetre.T
    return p ~= nil and T ~= nil and p.onglet == T.ongletEtape and Fenetre.etape ~= nil and not Fenetre.imageCliquee
end

-- L'étape montrée, relue dans la conversation : son entrée (Conversation.etapes), son rang et la
-- liste des étapes de sa photo ; nil sans étape. En mode suivre, la dernière de la photo ; une
-- étape choisie qui n'est plus dans la liste de sa photo (appel en cours d'une autre photo) suit
-- son élément.
function Fenetre.etapeCourante()
    local et, c = Fenetre.etape, Moteur.courante
    if not et then
        return nil
    end
    if et.conversation ~= c then
        Fenetre.etape = nil
        return nil
    end
    local liste = Conversation.etapes(c, et.photo)
    local n = rangEtape(liste, et.element, et.id)
    if not n and not et.suivre then
        local _, e = elementParId(c, et.element)
        if e and Conversation.estEtape(e) then
            local photo = Fenetre.photoDeLEtape(e)
            local autre = Conversation.etapes(c, photo)
            local m = rangEtape(autre, et.element, et.id)
            if m then
                et.photo, liste, n = photo, autre, m
            end
        end
    end
    if et.suivre and #liste > 0 and n ~= #liste then
        n = #liste
        et.vue = 'apres'
    end
    if not n then
        Fenetre.etape = nil
        return nil
    end
    local x = liste[n]
    et.element, et.id = x.elementId, x.id
    return x, n, liste
end

-- Choisit la dernière étape de la conversation pour la photo active (sinon la dernière étape de la
-- conversation), en mode suivre. Vrai si une étape est choisie.
function Fenetre.choisirDerniereEtape()
    local c = Moteur.courante
    if not c then
        return false
    end
    local active = Fenetre.info and Fenetre.info.active and Fenetre.info.active.id
    local photo, liste = active, Conversation.etapes(c, active)
    if #liste == 0 then
        for i = #(c.elements or {}), 1, -1 do
            local e = c.elements[i]
            if Conversation.estEtape(e) then
                photo = Fenetre.photoDeLEtape(e)
                liste = Conversation.etapes(c, photo)
                break
            end
        end
    end
    local x = liste[#liste]
    if not x then
        return false
    end
    Fenetre.etape = { conversation = c, photo = photo, id = x.id, element = x.elementId, vue = 'apres', suivre = true }
    return true
end

-- Montre l'étape de l'élément i du fil (un clic sur sa ligne) dans l'onglet Aperçu : un vrai
-- clic, l'onglet change sans Fenetre.choisirOnglet (réservé aux bascules de la fenêtre).
function Fenetre.montrerEtape(i)
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    local e = c and i and c.elements[i]
    if not (p and T and e and Conversation.estEtape(e)) then
        return false
    end
    local photo = Fenetre.photoDeLEtape(e)
    local liste = Conversation.etapes(c, photo)
    local n = rangEtape(liste, e.id)
    if not n then
        return false
    end
    Fenetre.etape = { conversation = c, photo = photo, id = liste[n].id, element = e.id, vue = 'apres', suivre = n == #liste }
    Fenetre.imageCliquee = nil
    if p.onglet ~= T.ongletEtape then
        p.onglet = T.ongletEtape
    end
    Fenetre.rafraichirEtape()
    return true
end

-- Quand Dany choisit l'onglet Aperçu sans étape choisie : la dernière, en mode suivre.
function Fenetre.montrerDerniereEtape()
    Fenetre.choisirDerniereEtape()
    Fenetre.rafraichirEtape()
end

-- « Étape 2 sur 4 · passe 1 : balance ».
function Fenetre.titreEtape(x, n, total)
    local but = x.etape or Conversation.nomEtape(x.nom)
    if not but or but == '' then
        but = x.outil or "étape"
    end
    return string.format("Étape %d sur %d · %s", n, total, but)
end

-- « DSCF4961.RAF · apply_settings · annulée ensuite (undo_last) ».
function Fenetre.sousTitreEtape(x)
    local morceaux = {}
    if x.fichier then
        morceaux[#morceaux + 1] = x.fichier
    elseif x.photo ~= nil and not x.enCours then
        morceaux[#morceaux + 1] = "photo " .. Conversation.clePhoto(x.photo)
    end
    morceaux[#morceaux + 1] = x.outil
    if x.annulee == 'undo_last' then
        morceaux[#morceaux + 1] = "annulée ensuite (undo_last)"
    elseif x.annulee == 'revert' then
        morceaux[#morceaux + 1] = "défaite ensuite (revert_to_original)"
    elseif x.enCours then
        morceaux[#morceaux + 1] = "en cours"
    end
    return table.concat(morceaux, " · ")
end

-- Les images lues de chaque étape vue (Fenetre.demanderImagesEtape), par « photo/id » : { cle,
-- version (Etapes.version de la lecture), info (Etapes.images), dossier et noms (les copies de la
-- fenêtre : noms.avant, noms.apres), avant, apres (réductions au cadre de l'aperçu), complete
-- (prête : ses deux images ne changent plus, elle ne se relit pas) }. Revenir à une étape la
-- remontre tout de suite ; une lecture d'une version passée reste montrée jusqu'à la suivante.
-- Vidées à chaque ouverture.
Fenetre.imagesEtapes, Fenetre.demandesEtapes = {}, {}

-- Le dossier des copies des images des étapes et de leurs réductions (Temporaire/Pourquoi/<photo>/
-- <lecture>/), propre à la fenêtre et vidé à chaque ouverture : rien ne s'écrit dans le dossier
-- Etapes du module (Images.vignette et Images.grande rangent leurs réductions à côté de l'image,
-- dans .vignettes, que le ménage d'Etapes.lua ne voit pas : elles y resteraient sans fin).
function Fenetre.dossierPourquoi()
    return LrPathUtils.child(Chemins.temporaire(), 'Pourquoi')
end

local function cleImages(x)
    return Conversation.clePhoto(x.photo) .. '/' .. tostring(x.id)
end

-- Les images lues de l'étape, nil si pas encore lues.
function Fenetre.imagesDe(x)
    if not (x and x.id) then
        return nil
    end
    return Fenetre.imagesEtapes[cleImages(x)]
end

-- Ce qu'il en est de l'avant/après de l'étape : { etat = 'pret' | 'en_cours' | 'attente' |
-- 'manque', texte (la ligne de la carte, nil si tout est là) }.
function Fenetre.etatImages(x)
    if Conversation.CLASSEMENTS[x.outil] then
        return { etat = 'manque', texte = "Pas d'avant/après : " .. Fenetre.SANS_IMAGES.classement .. "." }
    elseif x.enCours then
        return { etat = 'en_cours', texte = "Avant/après en préparation…" }
    elseif not x.id then
        return { etat = 'manque', texte = "Pas d'avant/après : " .. Fenetre.SANS_IMAGES.ancienne .. "." }
    end
    local im = Fenetre.imagesDe(x)
    local info = im and im.info or nil
    if not info then
        return { etat = 'attente' }
    elseif info.etat == 'pret' and im.avant and im.apres then
        return { etat = 'pret' }
    elseif info.etat == 'en_cours' then
        return { etat = 'en_cours', texte = "Avant/après en préparation…" }
    end
    local raison
    if info.etat == 'inconnu' then
        raison = Fenetre.SANS_IMAGES.inconnu
    elseif info.etat == 'pret' then
        raison = "image illisible"
    else
        raison = Etapes.RAISONS[info.raison] or (type(info.raison) == 'string' and info.raison) or "raison inconnue"
    end
    local une = im.avant or im.apres
    return { etat = 'manque', texte = (une and "Avant/après incomplet : " or "Pas d'avant/après : ") .. raison .. "." }
end

-- Le texte de la carte : la raison donnée par Claude, puis ce qui a changé (comme la
-- Proposition), puis, s'il manque, pourquoi l'avant/après n'est pas là.
function Fenetre.texteEtape(x, etat)
    local lignes = {}
    local raison = Texte.nettoyer(x.raison or '')
    lignes[#lignes + 1] = raison ~= '' and ("Pourquoi : " .. raison) or "Claude n'a pas donné de raison pour cette étape."
    lignes[#lignes + 1] = ''
    lignes[#lignes + 1] = "Ce qui a changé"
    local changements = x.changements or {}
    if #changements == 0 then
        lignes[#lignes + 1] = x.enCours and "L'étape est en cours." or "Aucun réglage chiffré dans la réponse."
    end
    for _, ch in ipairs(changements) do
        lignes[#lignes + 1] = string.format("%s : %s → %s", ch.libelle or ch.cle or '?', ch.avant or '—', ch.apres or '—')
    end
    if etat and etat.texte then
        lignes[#lignes + 1] = ''
        lignes[#lignes + 1] = etat.texte
    end
    return table.concat(lignes, '\n')
end

-- Lit dans une tâche les images de l'étape (Etapes.images), les copie dans le dossier de la
-- fenêtre (Fenetre.dossierPourquoi) et les y réduit au cadre de l'aperçu (Images.vignette, sips) ;
-- une fois lues, la carte et l'aperçu se rafraîchissent. Relues quand Etapes.version change (une
-- capture finie), sauf une étape prête.
function Fenetre.demanderImagesEtape(x)
    local T = Fenetre.T
    if not (T and x and x.id) or x.enCours or Conversation.CLASSEMENTS[x.outil] then
        return
    end
    local cle = cleImages(x)
    local version = Etapes.version
    local im = Fenetre.imagesEtapes[cle]
    if im and (im.version == version or im.complete) then
        return
    end
    -- Une lecture à la fois par étape et par version.
    local demande = cle .. '#' .. tostring(version)
    if Fenetre.demandesEtapes[demande] then
        return
    end
    Fenetre.demandesEtapes[demande] = true
    local photo, id, lectures, demandes = x.photo, x.id, Fenetre.imagesEtapes, Fenetre.demandesEtapes
    LrTasks.startAsyncTask(function()
        local ok, lu = LrTasks.pcall(function()
            local info = Etapes.images(photo, id)
            local r = { cle = cle, version = version, info = info, noms = {} }
            if info.dossier and (info.avant or info.apres) then
                -- Un dossier par lecture : une réduction gardée par nom (Images.vignette) ne
                -- montre jamais une image d'avant.
                local dossier = LrPathUtils.child(LrPathUtils.child(Fenetre.dossierPourquoi(), Conversation.clePhoto(photo)),
                    Conversation.identifiant())
                Fichiers.creerDossier(dossier)
                r.dossier = dossier
                for _, vue in ipairs({ 'avant', 'apres' }) do
                    local nom = info[vue]
                    local copie = nom and LrPathUtils.child(dossier, nom)
                    if copie then
                        Fichiers.copier(LrPathUtils.child(info.dossier, nom), copie)
                    end
                    if copie and Fichiers.existe(copie) then
                        r.noms[vue] = nom
                        r[vue] = vignetteApercu(T, dossier, nom)
                    end
                end
            end
            r.complete = info.etat == 'pret' and r.avant ~= nil and r.apres ~= nil
            return r
        end)
        demandes[demande] = nil
        if not ok then
            Journal.noter("Avant/après de l'étape :", tostring(lu))
            lu = { cle = cle, version = version, info = { etat = 'inconnu' }, noms = {} }
        end
        -- Une lecture d'une fenêtre fermée depuis, ou d'une version passée arrivée en retard, ne
        -- remplace rien (ses copies s'effacent) ; celle qu'elle remplace efface les siennes.
        local deja = lectures[cle]
        if lectures == Fenetre.imagesEtapes and not (deja and deja.version > version) then
            lectures[cle] = lu
            if deja and deja.dossier and deja.dossier ~= lu.dossier then
                Fichiers.supprimer(deja.dossier)
            end
        elseif lu.dossier then
            Fichiers.supprimer(lu.dossier)
        end
        if Fenetre.p and Fenetre.T == T then
            Fenetre.rafraichirEtape()
        end
    end)
end

-- Remplit la carte de l'étape (et l'aperçu, sauf `sansApercu`) d'après l'étape montrée ; sans
-- étape, l'aide. L'onglet ouvert sans étape choisie prend la dernière (mode suivre).
function Fenetre.rafraichirEtape(sansApercu)
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    Fenetre.versionEtapes = Etapes.version
    if not Fenetre.etape and T and p.onglet == T.ongletEtape then
        Fenetre.choisirDerniereEtape()
    end
    local x, n, liste = Fenetre.etapeCourante()
    if not x then
        poser(p, 'etapeTitre', Fenetre.TITRE_ETAPE)
        poser(p, 'etapeSousTitre', '')
        Fenetre.montrerPage('etape', Fenetre.AIDE_ETAPE)
        poser(p, 'etapePrecedente', false)
        poser(p, 'etapeSuivante', false)
        poser(p, 'etapeAImages', false)
        poser(p, 'etapeADetail', false)
        poser(p, 'titreBascule', "Voir l'avant")
    else
        local im = Fenetre.imagesDe(x)
        poser(p, 'etapeTitre', Fenetre.titreEtape(x, n, #liste))
        poser(p, 'etapeSousTitre', Fenetre.sousTitreEtape(x))
        Fenetre.montrerPage('etape', Fenetre.texteEtape(x, Fenetre.etatImages(x)))
        poser(p, 'etapePrecedente', n > 1)
        poser(p, 'etapeSuivante', n < #liste)
        poser(p, 'etapeADetail', true)
        poser(p, 'etapeAImages', im ~= nil and im.avant ~= nil and im.apres ~= nil)
        poser(p, 'titreBascule', Fenetre.etape.vue == 'avant' and "Voir l'après" or "Voir l'avant")
        Fenetre.demanderImagesEtape(x)
    end
    if not sansApercu then
        Fenetre.rafraichirApercu()
    end
end

-- L'aperçu de l'onglet Aperçu (Fenetre.apercuOnglet) : l'image de l'étape montrée (après, ou
-- avant), « Étape 2 sur 4 · après » ; sans image, l'image vide et pourquoi. Sans étape choisie,
-- nil : l'aperçu d'avant. Les ◀ ▶ de l'aperçu sont coupés. Sous la clé de l'onglet,
-- D.ongletEtape ('apercu').
Fenetre.apercuOnglet.apercu = function(p)
    local x, n, liste = Fenetre.etapeCourante()
    if not x then
        return nil
    end
    poser(p, 'peutPrecedente', false)
    poser(p, 'peutSuivante', false)
    local debut = string.format("Étape %d sur %d", n, #liste)
    local im = Fenetre.imagesDe(x)
    local vue = Fenetre.etape.vue == 'avant' and 'avant' or 'apres'
    local chemin = im and im[vue]
    if not chemin and im then
        local autre = vue == 'avant' and 'apres' or 'avant'
        if im[autre] then
            vue, chemin = autre, im[autre]
        end
    end
    if chemin then
        poser(p, 'imageApercu', chemin)
        poser(p, 'aImage', true)
        poser(p, 'legendeApercu', debut .. " · " .. (vue == 'avant' and "avant" or "après"))
        return true
    end
    local etat = Fenetre.etatImages(x).etat
    poser(p, 'imageApercu', Fenetre.imageVide())
    poser(p, 'aImage', false)
    poser(p, 'legendeApercu', debut .. " · " .. ((etat == 'en_cours' or etat == 'attente') and "avant/après en préparation…" or "pas d'avant/après"))
    return true
end

-- Un vrai clic sur l'onglet Aperçu : la carte relue ; sans étape choisie, la dernière.
Fenetre.surOnglet.apercu = function()
    Fenetre.rafraichirEtape(true)
end

-- ◀ (pas -1) ou ▶ (pas 1) : l'étape d'avant ou d'après de la même photo ; la dernière reprend le
-- mode suivre.
function Fenetre.etapeVoisine(pas)
    local x, n, liste = Fenetre.etapeCourante()
    if not x then
        return
    end
    local m = math.max(1, math.min(#liste, n + pas))
    if m == n then
        return
    end
    local y = liste[m]
    local et = Fenetre.etape
    et.id, et.element, et.suivre, et.vue = y.id, y.elementId, m == #liste, 'apres'
    Fenetre.rafraichirEtape()
end

-- Voir l'avant / Voir l'après : l'aperçu passe de l'un à l'autre.
function Fenetre.basculerEtape()
    local et = Fenetre.etape
    if not et then
        return
    end
    et.vue = et.vue == 'avant' and 'apres' or 'avant'
    Fenetre.rafraichirEtape()
end

-- Détail… (depuis une tâche) : l'appel de l'outil de l'étape et sa réponse.
function Fenetre.detailEtape()
    local x = Fenetre.etapeCourante()
    local _, e = elementParId(Moteur.courante, x and x.elementId)
    if e then
        Fenetre.montrerDetail(e)
    end
end

-- Agrandir dans l'onglet Aperçu : l'avant et l'après côte à côte (Fenetre.agrandirDeux), la
-- raison et les changements dessous ; une seule image si l'autre manque.
function Fenetre.agrandirEtape()
    local x, n, liste = Fenetre.etapeCourante()
    local im = x and Fenetre.imagesDe(x)
    -- Les copies de la fenêtre (Fenetre.dossierPourquoi), jamais le dossier Etapes du module.
    local dossier, noms = im and im.dossier, im and im.noms or {}
    if not (dossier and (noms.avant or noms.apres)) then
        return
    end
    local titre = Fenetre.titreEtape(x, n, #liste)
    local legende = Fenetre.texteEtape(x)
    enTache(function()
        if noms.avant and noms.apres then
            Fenetre.agrandirDeux(titre, { dossier = dossier, nom = noms.avant, titre = "Avant" },
                { dossier = dossier, nom = noms.apres, titre = "Après" }, legende)
            return
        end
        local nom = noms.apres or noms.avant
        local chemin, l, h = Images.grande(dossier, nom, 1100, 740)
        if not chemin then
            LrDialogs.message("Aperçu illisible", nom, 'warning')
            return
        end
        LrDialogs.presentModalDialog {
            title = "Claude · " .. titre .. " · " .. (noms.apres and "après" or "avant"),
            contents = LrView.osFactory():picture { value = chemin, width = l, height = h },
            actionVerb = "Fermer",
            cancelVerb = '< exclude >',
        }
    end)
end

-- Note de la photo active ----------------------------------------------------------------------
-- La carte Note (Vues.notation, fenêtre B, lot B5 : la maquette « B · Conversation claire ») lit
-- le registre des notes proposées (Notation.lua, rempli par la commande `notation` de la liaison
-- quand Claude appelle propose_ratings) et la note posée de la photo active : la note et le
-- drapeau posés (étoiles et drapeaux cliquables), la note que Claude propose, ses critères page par
-- page (Fenetre.lignesCriteres), puis le zoom que Claude a pris pour noter (« Voir à 100 % », montré
-- dans l'aperçu : Fenetre.voirZoom), Laisser, Changer… et Accepter. Plus de passes ni de plafond
-- dans la carte (correctif 1.3.2, demandé par Dany le 22 octobre 2026 : la passe reste dans l'en-tête
-- de la grille, « Passe 2 · à vérifier » ; le plafond, dans le registre et les critères de Claude).
-- Ce qui écrit passe par une tâche et Notation.poser
-- (Fenetre.poserNote : étoiles, drapeaux, Accepter, Changer…) ou Notation.decider (Laisser : rien
-- dans le catalogue), sans Claude ni quota, jamais pendant que Claude travaille ni pendant une autre
-- écriture de la carte (le bandeau dit pourquoi : un calque n'a pas d'enabled). Retenir, ou retirer
-- un drapeau, ne décide rien de la note que Claude propose (Fenetre.poserDrapeau). Claude propose
-- de 0 à 5 ★ (correctif 1.3.2), et la carte offre « Accepter 5 ★ » ; les coups de cœur de Dany sont
-- un libellé de couleur qu'il pose lui-même. « ? À vérifier » est posé grisé (Vues.inactif :
-- décision de Dany du 21 octobre 2026 ; le bouton avait été retiré en 1.1.1).

local ETATS_NOTE = {
    proposee = "proposée",
    acceptee = "acceptée",
    changee = "changée",
    a_verifier = "à vérifier",
    ecartee = "écartée",
}

-- En tête de phrase (l'état sans passe connue).
local ETATS_NOTE_MAJ = {
    proposee = "Proposée",
    acceptee = "Acceptée",
    changee = "Changée",
    a_verifier = "À vérifier",
    ecartee = "Écartée",
}

-- La couleur de l'état de la proposition : des clés de la palette (Dispositions.PALETTES ;
-- l'ancien « vert » est la coche), une variante chacune de la première ligne de la grille des
-- critères (Vues.ligneCritere), où l'état est en gras de cette couleur.
local COULEURS_NOTE = { proposee = 'orange', acceptee = 'coche', changee = 'coche', a_verifier = 'rouge', ecartee = 'gris' }
Fenetre.COULEURS_NOTE = COULEURS_NOTE
Fenetre.TEINTES_NOTE = { 'gris', 'orange', 'coche', 'rouge' }

-- Les critères du standard, du plus lourd au plus léger, et leur étiquette dans la grille.
local CRITERES = {
    { cle = 'impact', titre = "Impact" },
    { cle = 'qualites', titre = "Qualités" },
    { cle = 'plancher', titre = "Plancher technique" },
    { cle = 'finition', titre = "Finition" },
}
Fenetre.CRITERES = CRITERES

Fenetre.AIDE_NOTATION = "Claude note d'abord chaque photo qu'il traite, de 0 à 5 ★, selon le standard, critère par critère "
    .. "(impact, qualités, plancher technique, finition) : sa note arrive à vérifier, vous l'acceptez, la laissez ou la "
    .. "changez. Vos coups de cœur : un libellé de couleur, que vous posez vous-même. Les étoiles et les drapeaux "
    .. "ci-dessus posent votre note dans Lightroom."

-- Le sens de la note posée, d'après le standard (« Les notes ») : le titre à droite des étoiles.
Fenetre.SENS_NOTES = { [0] = "Pas encore jugée", "Gardée", "Correcte", "Tient seule", "A de l'impact", "Parmi vos meilleures" }

-- La raison gardée d'une note ou d'un drapeau posés depuis la carte (Notation.poser).
Fenetre.RAISON_NOTE = "Note choisie dans la fenêtre Claude"
Fenetre.RAISON_DRAPEAU = "Drapeau choisi dans la fenêtre Claude"

-- Les messages de la carte au bandeau (chacun tient en deux lignes, essais-fenetre-b.lua) : une
-- écriture déjà en cours, pas de photo active.
Fenetre.NOTE_EN_COURS = "Une note s'écrit déjà : un instant."
Fenetre.AUCUNE_PHOTO = "Aucune photo active : choisissez-la dans Lightroom."

-- Les infobulles de « Voir à 100 % » : le zoom de Claude, montré dans l'aperçu, ou pourquoi le
-- bouton est grisé.
Fenetre.INFOBULLE_ZOOM = "Montrer dans l'aperçu le zoom à 100 % que Claude a pris pour noter cette photo (Agrandir : en grand)"
Fenetre.SANS_ZOOM = "Claude n'a pas pris de zoom de cette photo"

local function texteChamp(v)
    return type(v) == 'string' and Texte.nettoyer(sansBalises(v)) or ''
end

local function entre(n, mini, maxi)
    return math.max(mini, math.min(maxi, math.floor(tonumber(n) or 0)))
end

-- La note posée de la photo active, en titre (gras) et sous-titre (gris), à droite des étoiles :
-- « Pas encore jugée » / « 0 ★ dans le catalogue », « Tient seule » / « 3 ★ · drapeau Retenue »,
-- « Rejetée » / « 0 ★ · drapeau Rejeter ».
function Fenetre.notePosee(active)
    if not active then
        return "Aucune photo active", "choisissez-la dans Lightroom"
    end
    if active.note == nil then
        return active.drapeau == 'rejetee' and "Rejetée" or "Note inconnue", ''
    end
    local n = entre(active.note, 0, 5)
    local titre = active.drapeau == 'rejetee' and "Rejetée" or Fenetre.SENS_NOTES[n]
    local sous = n .. " ★ dans le catalogue"
    if active.drapeau == 'retenue' then
        sous = n .. " ★ · drapeau Retenue"
    elseif active.drapeau == 'rejetee' then
        sous = n .. " ★ · drapeau Rejeter"
    end
    return titre, sous
end

-- La note que Claude propose, pour les petites étoiles de « Claude propose » (`noteClaude`) : de 0
-- à 5, 'rejet' pour un rejet, 'aucune' sans proposition.
function Fenetre.noteClaude(prop)
    if not prop then
        return 'aucune'
    elseif prop.drapeau == 'rejetee' then
        return 'rejet'
    end
    return entre(prop.note, 0, 5)
end

-- « Accepter 3 ★ », « Accepter 5 ★ » (correctif 1.3.2), « Accepter le rejet » ; « Accepter » sans
-- proposition (grisé).
function Fenetre.titreAccepter(prop)
    if not prop then
        return "Accepter"
    elseif prop.drapeau == 'rejetee' then
        return "Accepter le rejet"
    end
    return "Accepter " .. entre(prop.note, 0, 5) .. " ★"
end

-- « Laisser à 0 ★ » (la note du catalogue), « Laisser rejetée ».
function Fenetre.titreLaisser(active)
    if not active then
        return "Laisser"
    elseif active.drapeau == 'rejetee' then
        return "Laisser rejetée"
    end
    return "Laisser à " .. entre(active.note, 0, 5) .. " ★"
end

-- « Passe 2 · à vérifier » (« À vérifier » sans passe connue), « Passe 2 · changée : 4 ★ ».
function Fenetre.enteteNote(prop)
    local etat = ETATS_NOTE[prop.etat] or tostring(prop.etat or '')
    if prop.etat == 'changee' then
        if prop.drapeau_choisi == 'rejetee' then
            etat = etat .. " : rejetée"
        elseif tonumber(prop.note_choisie) then
            etat = etat .. " : " .. entre(prop.note_choisie, 0, 5) .. " ★"
        end
    elseif prop.etat == 'proposee' and prop.a_verifier == true then
        etat = etat .. " · à vérifier"
    end
    if tonumber(prop.passe) then
        return "Passe " .. math.floor(tonumber(prop.passe)) .. " · " .. etat
    end
    local maj = ETATS_NOTE_MAJ[prop.etat]
    return maj and (maj .. etat:sub(#(ETATS_NOTE[prop.etat]) + 1)) or etat
end

-- Le verdict en tête du texte d'un critère (« Moyen. Le ciel arrête l'œil. », « Fort », « Nette
-- (44). ») : ses premiers mots jusqu'au premier point, ou le texte entier sans point, s'ils font
-- deux mots au plus, 20 caractères au plus, sans deux-points. Rend le verdict et la suite ; nil et
-- le texte entier sans verdict.
function Fenetre.verdict(texte)
    texte = texteChamp(texte)
    local debut, suite = texte:match('^([^%.]-%.)(.*)$')
    if not debut then
        debut, suite = texte, ''
    end
    local mots = 0
    for _ in debut:gmatch('%S+') do
        mots = mots + 1
    end
    if mots == 0 or mots > 2 or Texte.longueur(debut) > 20 or debut:find(':', 1, true) then
        return nil, texte
    end
    return debut, suite
end

-- Les lignes de la grille de la carte Note (Vues.ligneCritere) pour une proposition (nil : l'aide,
-- Fenetre.AIDE_NOTATION, en lignes pleine largeur), à `largeurs` { plein (379), critere (251) } :
-- d'abord l'état et la raison (« <EM>Passe 2 · à vérifier.</EM> Tient seule… » ; sa première
-- ligne en genre 'etat', son gras de la couleur de l'état, les suivantes 'plein'), puis chaque
-- critère, du plus lourd au plus léger, son étiquette sur sa première ligne et son texte coupé à
-- côté, le verdict en <EM> (gras 12). Coupées en 12 points, chaque ligne aux balises fermées
-- (Fil.couper) ; les balises venues de Claude sont retirées. Tables neuves : { genre = 'etat',
-- 'plein' ou 'critere', etiquette, texte }.
function Fenetre.lignesCriteres(prop, largeurs)
    local lignes = {}
    local function couper(texte, largeur)
        return (Fil.couper(texte, largeur - Fil.MARGE, 'texte12', nil, 'gras12'))
    end
    if not prop then
        for _, l in ipairs(Fenetre.lignesCarte(Fenetre.AIDE_NOTATION, largeurs.plein, 'texte12', 'gras12')) do
            lignes[#lignes + 1] = { genre = 'plein', etiquette = '', texte = l }
        end
        return lignes
    end
    local raison = texteChamp(prop.raison)
    local tete = '<EM>' .. Fenetre.enteteNote(prop) .. '.</EM>' .. (raison ~= '' and (' ' .. raison) or '')
    for k, l in ipairs(couper(tete, largeurs.plein)) do
        lignes[#lignes + 1] = { genre = k == 1 and 'etat' or 'plein', etiquette = '', texte = l }
    end
    local criteres = type(prop.criteres) == 'table' and prop.criteres or {}
    for _, critere in ipairs(CRITERES) do
        local texte = texteChamp(criteres[critere.cle])
        if texte ~= '' then
            local verdict, suite = Fenetre.verdict(texte)
            for k, l in ipairs(couper(verdict and ('<EM>' .. verdict .. '</EM>' .. suite) or suite, largeurs.critere)) do
                lignes[#lignes + 1] = { genre = 'critere', etiquette = k == 1 and critere.titre or '', texte = l }
            end
        end
    end
    return lignes
end

-- La signature des lignes de la grille (le « texte » de sa page : la même revient à la même page).
local function signature(lignes)
    local morceaux = {}
    for _, l in ipairs(lignes) do
        morceaux[#morceaux + 1] = l.genre .. '\1' .. l.etiquette .. '\1' .. l.texte
    end
    return table.concat(morceaux, '\n')
end

-- Le zoom que Claude a pris pour noter la photo de la carte (Conversation.dernierZoom, dans la
-- conversation montrée), gardé tant que la conversation, son nombre d'éléments et la photo ne
-- changent pas (la carte se relit toutes les 2 s) ; nil sans zoom.
function Fenetre.zoomDeLaNote()
    local c = Moteur.courante
    local prop = Fenetre.propositionNote
    local active = Fenetre.info and Fenetre.info.active
    local photo = prop and prop.photo or (active and active.id)
    if not c or photo == nil then
        return nil
    end
    local cle = tostring(c.id) .. '#' .. #(c.elements or {}) .. '#' .. Conversation.clePhoto(photo)
    local garde = Fenetre.zoomGarde
    if garde and garde.cle == cle and garde.conversation == c then
        return garde.zoom
    end
    local zoom = Conversation.dernierZoom(c, photo)
    Fenetre.zoomGarde = { cle = cle, conversation = c, zoom = zoom }
    return zoom
end

-- « Voir à 100 % » : le zoom que Claude a pris pour noter la photo de la carte, montré dans
-- l'aperçu (décision de Dany du 21 octobre 2026 : « Montre dans l'aperçu le zoom que Claude a pris
-- pour noter, s'il y en a un dans la conversation ; grisé sinon »), comme un clic sur sa ligne
-- d'image dans le fil (Fenetre.clics.image) : il y reste jusqu'à un autre onglet, une image
-- nouvelle, une autre conversation ou une autre photo active, et Agrandir le montre en grand. Sans
-- nouvel appel à Claude, sans rien demander à Lightroom. Rend faux sans zoom (le bouton est alors
-- grisé).
function Fenetre.voirZoom()
    local zoom = Moteur.courante and Fenetre.zoomDeLaNote()
    if not zoom then
        return false
    end
    Fenetre.clics.image({ image = zoom.chemin })
    return Fenetre.imageCliquee == true
end

function Fenetre.rafraichirNotation()
    local p, T = Fenetre.p, Fenetre.T
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
    -- La note posée et ses étoiles.
    poser(p, 'noteCatalogue', active and entre(active.note, 0, 5) or 0)
    local titre, sous = Fenetre.notePosee(active)
    poser(p, 'notePoseeTitre', titre)
    poser(p, 'notePoseeSous', sous)
    -- Ce que Claude propose, et la couleur de son état.
    poser(p, 'noteClaude', Fenetre.noteClaude(prop))
    poser(p, 'notationCouleur', prop and COULEURS_NOTE[prop.etat] or 'gris')
    -- La grille des critères, page par page (la même revient à la même page).
    local lignes = Fenetre.lignesCriteres(prop, { plein = T and T.largeurNote or 379, critere = T and T.texteCritere or 251 })
    Fenetre.montrerPage('note', signature(lignes), nil, lignes)
    -- Le zoom que Claude a pris pour noter.
    poser(p, 'peutVoirZoom', Fenetre.zoomDeLaNote() ~= nil)
    -- Les écritures de la fenêtre échappent à la file du connecteur : pas pendant que Claude
    -- travaille, ni pendant une écriture déjà demandée.
    local libre = not Moteur.travaille and not Fenetre.noteEnCours
    local adecider = prop ~= nil and (prop.etat == 'proposee' or prop.etat == 'a_verifier')
    poser(p, 'peutAccepterNote', libre and adecider)
    poser(p, 'peutChangerNote', libre and active ~= nil)
    poser(p, 'titreAccepterNote', Fenetre.titreAccepter(prop))
    poser(p, 'titreLaisser', Fenetre.titreLaisser(active))
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

-- La carte libre pour une écriture : ni Claude au travail, ni une autre écriture de la carte, et
-- une photo active. Rend la photo active, sinon nil (le bandeau dit pourquoi).
local function carteLibre()
    local p = Fenetre.p
    if not p then
        return nil
    end
    local active = Fenetre.info and Fenetre.info.active
    local message
    if Moteur.travaille then
        message = Fenetre.CLAUDE_TRAVAILLE
    elseif Fenetre.noteEnCours then
        message = Fenetre.NOTE_EN_COURS
    elseif not active then
        message = Fenetre.AUCUNE_PHOTO
    end
    if message then
        p.message = message
        return nil
    end
    return active
end

-- Écrit une note dans le catalogue (Notation.poser), depuis une tâche, puis relit la photo : une
-- écriture à la fois, jamais pendant que Claude travaille (le bandeau le dit). `etatGarde` (un
-- drapeau qui ne décide rien, Fenetre.poserDrapeau) : la proposition de Claude revient à cet état
-- une fois le drapeau posé (Notation.poser l'aurait dite acceptée ou changée), dans la même tâche,
-- sans rien écrire de plus dans le catalogue.
function Fenetre.poserNote(choix, etatGarde)
    if Moteur.travaille or Fenetre.noteEnCours then
        if Fenetre.p then
            Fenetre.p.message = Moteur.travaille and Fenetre.CLAUDE_TRAVAILLE or Fenetre.NOTE_EN_COURS
        end
        return
    end
    Fenetre.noteEnCours = true
    Fenetre.rafraichirNotation()
    local ok, r = LrTasks.pcall(Notation.poser, { choix })
    if ok and r.ok and etatGarde then
        LrTasks.pcall(Notation.decider, choix.photo, etatGarde)
    end
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

-- Un clic sur la i-e étoile de « Votre note » (son calque, Vues.notation) : i ★ posées dans
-- Lightroom, 5 comprises (c'est Dany qui les pose), ou 0 si la photo les a déjà (un clic sur
-- l'étoile de la note posée la retire), dans une tâche. Rend vrai si la note part.
function Fenetre.poserEtoile(i)
    local active = carteLibre()
    if not active then
        return false
    end
    local note = entre(i, 0, 5)
    if tonumber(active.note) == note then
        note = 0
    end
    enTache(Fenetre.poserNote, { photo = active.id, note = note, raison = Fenetre.RAISON_NOTE })
    return true
end

-- « ⚑ Retenir » ou « ⊗ Rejeter » : ce drapeau posé dans Lightroom, ou retiré (« aucun ») si la
-- photo l'a déjà ; les étoiles restent. Dans une tâche ; rend vrai si le drapeau part. Retenir, ou
-- retirer un drapeau, ne décide rien de la note que Claude propose : sa proposition à décider le
-- reste (sans quoi Notation.poser la dirait changée, la note du catalogue prise pour celle de Dany).
-- Rejeter décide (la proposition est changée, ou acceptée si Claude proposait le rejet), comme tout
-- drapeau sur un rejet proposé.
function Fenetre.poserDrapeau(drapeau)
    local active = carteLibre()
    if not active then
        return false
    end
    local nouveau = active.drapeau == drapeau and 'aucun' or drapeau
    local prop = Fenetre.propositionNote
    local garder
    if prop and (prop.etat == 'a_verifier' or prop.etat == 'proposee') and prop.drapeau ~= 'rejetee' and nouveau ~= 'rejetee' then
        garder = prop.etat
    end
    enTache(Fenetre.poserNote, { photo = active.id, drapeau = nouveau, raison = Fenetre.RAISON_DRAPEAU }, garder)
    return true
end

-- « Laisser à N ★ » : la note du catalogue reste, la proposition de Claude est écartée
-- (Notation.decider, rien n'est écrit dans Lightroom), dans une tâche. Rend vrai si elle part.
function Fenetre.laisserNote()
    local prop = Fenetre.propositionNote
    if not carteLibre() or not prop then
        return false
    end
    enTache(Fenetre.ecarterNote, prop.photo)
    return true
end

-- La tâche de Laisser : refusée (et dite au bandeau, comme Fenetre.poserNote) si Claude s'est mis au
-- travail ou qu'une note s'écrit depuis le clic.
function Fenetre.ecarterNote(photo)
    if Moteur.travaille or Fenetre.noteEnCours then
        if Fenetre.p then
            Fenetre.p.message = Moteur.travaille and Fenetre.CLAUDE_TRAVAILLE or Fenetre.NOTE_EN_COURS
        end
        return
    end
    local ok, fait, raison = LrTasks.pcall(Notation.decider, photo, 'ecartee')
    if Fenetre.p and not (ok and fait) then
        Fenetre.p.message = "La proposition n'a pas été écartée : " .. tostring(ok and raison or fait)
    end
    Fenetre.aRafraichirNotation = true
end

-- Accepter : la proposition de Claude telle quelle (Notation.poser sans note ni drapeau : sa
-- note, 5 ★ comprises depuis le correctif 1.3.2, ou le drapeau Rejeter pour un rejet ; un drapeau
-- Retenue de Dany reste). Depuis une tâche.
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
                f:static_text { title = "Note de " .. Lightroom.nomCourt(active.nom) .. " :" },
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
            choix = { photo = active.id, note = tonumber(q.note) or 0, raison = Fenetre.RAISON_NOTE,
                drapeau = q.drapeau ~= 'inchange' and q.drapeau or nil }
        end
    end)
    if choix then
        Fenetre.poserNote(choix)
    end
end

-- Mode -------------------------------------------------------------------------------------------
-- Les trois boutons radio de l'en-tête (Vues.mode), liés à la clé `mode` : 'appliquer' et
-- 'proposer' (le mode « Proposer d'abord » de la liaison, sa préférence `mode`), 'jelefais'
-- (l'exercice, 1.3). La valeur montrée se tire de l'état, jamais d'un drapeau perdu à la
-- réouverture (Fenetre.modeMontre) ; la fenêtre la pose sous la garde Fenetre.modeAuto, pour que
-- l'observateur ne la prenne pas pour un clic. Un vrai clic (l'observateur, Fenetre.changerMode)
-- annule d'abord l'envoi automatique : un radio est un bouton, son clic valide le champ (constaté
-- le 21 octobre 2026, D3). « J'ai fini » ne part jamais d'un radio : seulement de la carte
-- Proposition.

Fenetre.LIBELLES_MODE = { appliquer = "Appliquer", proposer = "Proposer d'abord", jelefais = "Je le fais" }

-- Le bandeau quand Appliquer ou Proposer d'abord est cliqué pendant un exercice (suivi du mode).
Fenetre.EXERCICE_CONTINUE = "L'exercice continue ; liaison : "

-- La valeur du Mode d'après l'état : « Je le fais » tant que la conversation montrée a un
-- exercice à faire ou en préparation (Conversation.dernierExercice), que la demande Je le fais
-- part (Fenetre.jeLeFaisEnCours), ou que Claude prépare la liste qu'elle a demandée
-- (Fenetre.demandeJeLeFais) ; sinon le mode de la liaison (Lightroom.mode).
function Fenetre.modeMontre()
    local c = Moteur.courante
    local exo = c and Conversation.dernierExercice(c)
    if Fenetre.jeLeFaisEnCours or (exo and (exo.etat == 'aFaire' or exo.etat == 'enCours')) then
        return 'jelefais'
    end
    if Moteur.travaille and c ~= nil and Fenetre.demandeJeLeFais == c then
        return 'jelefais'
    end
    return Lightroom.mode()
end

-- Pose la valeur du Mode tirée de l'état (sans que l'observateur la prenne pour un clic).
function Fenetre.rafraichirMode()
    local p = Fenetre.p
    if not p then
        return
    end
    if not Moteur.travaille then
        Fenetre.demandeJeLeFais = nil
    end
    local valeur = Fenetre.modeMontre()
    if p.mode ~= valeur then
        Fenetre.modeAuto = true
        p.mode = valeur
        Fenetre.modeAuto = false
    end
end

-- Un radio inactif et coché par sa valeur se dessine sans point à la première ouverture ; sa
-- valeur reposée après l'ouverture le dessine grisé et coché (constaté le 21 octobre 2026, D12).
-- Une seule fois, dans la première tâche de la fenêtre ouverte (Fenetre.boucle) : la valeur
-- repasse par une autre, puis revient, sous la garde Fenetre.modeAuto (une valeur égale reposée
-- pourrait ne rien redessiner : Lightroom ne prévient qu'au changement, supposé).
function Fenetre.reposerMode()
    local p = Fenetre.p
    if not p then
        return
    end
    local valeur = p.mode
    Fenetre.modeAuto = true
    p.mode = 'aucun'
    p.mode = valeur
    Fenetre.modeAuto = false
end

-- Un vrai clic sur un radio du Mode. Appliquer ou Proposer d'abord : le mode de la liaison change
-- s'il diffère ; pendant un exercice, le radio revient à Je le fais, et le bandeau dit que
-- l'exercice continue. Je le fais : la demande part (Fenetre.jeLeFais, dans une tâche), sans
-- exercice en cours seulement ; un refus remet le radio (Fenetre.rafraichirMode).
function Fenetre.changerMode(valeur)
    local p = Fenetre.p
    if not p then
        return
    end
    local exercice = Fenetre.modeMontre() == 'jelefais'
    if valeur == 'appliquer' or valeur == 'proposer' then
        if Lightroom.mode() ~= valeur then
            Lightroom.basculerMode()
        end
        if exercice then
            -- Deux lignes du bandeau : « J'ai fini » est dans la carte Proposition.
            p.message = Fenetre.EXERCICE_CONTINUE .. Fenetre.LIBELLES_MODE[valeur] .. "."
        end
    elseif valeur == 'jelefais' and not exercice and not Moteur.travaille then
        enTache(function()
            Fenetre.jeLeFais()
            Fenetre.rafraichirMode()
        end)
        return
    end
    Fenetre.rafraichirMode()
end

-- Voyants -------------------------------------------------------------------------------------

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
        poser(p, 'versionTexte' .. i, Fenetre.texteVersion(l))
        poser(p, 'versionAlerte' .. i, l.alerte == true)
    end
end

-- Une ligne de version en un texte (Vues.versions) : « Développeur 1.3 », « MCP-Développeur 1.2 ·
-- à mettre à jour » (l'alerte après le numéro), « MCP-Développeur · introuvable ».
function Fenetre.texteVersion(l)
    local nom, version = tostring(l.nom or ''), tostring(l.version or '')
    local base, suite = nom:match('^(.-)( · .*)$')
    base, suite = base or nom, suite or ''
    return base .. (version ~= '' and (' ' .. version) or '') .. suite
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

-- Le bandeau (Vues.bandeau) : deux lignes en petit dans la place du menu Modèle de la maquette
-- (D.bandeau, 308 points ; à 178, une seule en coupait la plupart, « Claude travaille… » en demande
-- 269).
-- Le texte se coupe d'après la chasse mesurée (Fil.coupeBornee, police `petit`), « … » au bout de
-- la seconde ligne s'il dépasse (l'infobulle du message, le clic de l'aide le donnent en entier) ;
-- les messages de la fenêtre tiennent en deux lignes (essais-fenetre-b.lua). `suite` (facultative)
-- reste entière au bout : un texte trop long se coupe avant elle, par « … » (les photos jointes
-- gardent « cliquer pour retirer », comme le faisait la troncature au milieu d'avant).
Fenetre.LIGNES_BANDEAU = 2

function Fenetre.texteBandeau(texte, largeur, suite)
    texte = Texte.nettoyer((sansBalises(texte):gsub('%s+', ' ')))
    if texte == '' then
        return ''
    end
    largeur = (largeur or (Fenetre.T or Dispositions.dimensions()).bandeau) - Fil.MARGE
    suite = (sansBalises(suite):gsub('%s+', ' '))
    local maxi = Fenetre.LIGNES_BANDEAU
    if suite ~= '' then
        local entier = Fil.couper(texte .. suite, largeur, 'petit', '')
        if #entier <= maxi then
            return table.concat(entier, '\n')
        end
        -- Le plus long début du texte qui laisse la suite tenir (par moitiés : un transform de la
        -- vue, à chaque changement).
        local bas, haut, garde = 1, Texte.longueur(texte), nil
        while bas <= haut do
            local n = math.floor((bas + haut) / 2)
            local essai = Fil.couper((Texte.debut(texte, n):gsub('%s+$', '')) .. '…' .. suite, largeur, 'petit', '')
            if #essai <= maxi then
                garde, bas = essai, n + 1
            else
                haut = n - 1
            end
        end
        if garde then
            return table.concat(garde, '\n')
        end
    end
    return table.concat(Fil.coupeBornee(texte .. suite, largeur, 'petit', '', maxi), '\n')
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
    -- Une autre photo active (ou la première vue à l'ouverture) : son aperçu se montre ; une image
    -- cliquée avant n'est plus montrée, l'aperçu revient à l'onglet (1.3).
    local id = info.active and info.active.id
    if id ~= Fenetre.idActif then
        Fenetre.idActif = id
        -- Sa légende (nom de la copie, appareil, date de prise de vue), lue seulement quand elle
        -- change : Lightroom.photos, toutes les 2 s, ne lit rien de plus.
        Fenetre.legendeActive = id ~= nil and Lightroom.legende(id) or nil
        if Fenetre.legendeActive then
            Fenetre.legendeActive.id = id
        end
        Fenetre.voirActive = true
        Fenetre.imageCliquee = nil
        Fenetre.rafraichirApercu()
        -- L'onglet Leçon montre la leçon de la photo active ; l'onglet Focus, sa mise au point.
        Fenetre.rafraichirLecon()
        Fenetre.rafraichirFocus()
    end
    if info.active then
        p.infoPhoto = string.format("Active : <EM>%s</EM> · Sélection : <EM>%d</EM>",
            Fenetre.nomPhoto(legendeActive(info.active)), info.selection)
        -- Une note acceptée ou changée qui n'est plus sur la photo (undo_last, ⌘Z) : la proposition
        -- redevient à décider.
        local active = info.active
        LrTasks.pcall(Notation.recaler, { { photo = active.id, note = active.note, drapeau = active.drapeau } }, version)
    else
        p.infoPhoto = "Aucune photo active"
    end
    Fenetre.suivreSelection(info)
    Fenetre.rafraichirNotation()
    -- Je le fais (1.3) : sans proposition ni exercice, il faut une photo active.
    Fenetre.rafraichirJeLeFais()
end

-- Une autre photo active ou une autre sélection, choisie par l'utilisateur, commence une nouvelle
-- conversation (préférence `nouvelleParPhoto`, demandé par Dany le 20 octobre 2026), si celle
-- montrée a déjà des messages et parlait d'autres photos (`c.cle`, posée à chaque demande). Une
-- sélection changée pendant que Claude travaille (show_photo, tri), ou qui l'était encore
-- DELAI_APRES_TRAVAIL secondes avant la fin de son travail, peut être la sienne : elle devient
-- celle de la conversation. `Fenetre.cleVue` et l'heure où elle a été vue (`cleVueLe`) restent
-- d'une ouverture de la fenêtre à l'autre : une photo choisie fenêtre fermée compte aussi, et une
-- fenêtre fermée pendant le travail de Claude retrouve sa conversation à la réouverture. Pendant un
-- exercice « Je le fais » (1.3), Dany peut regarder d'autres photos : la conversation reste celle
-- de l'exercice, sa liste et « J'ai fini » avec elle.
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
    if Conversation.exerciceEnCours(c) then
        return
    end
    Journal.noter("Autre photo choisie : nouvelle conversation")
    -- La page du carnet reste montrée : la conversation nouvelle attend le retour au fil.
    Fenetre.nouvelle(true)
end

-- Tout ce qui dépend du moteur.
function Fenetre.rafraichir()
    local p = Fenetre.p
    if not p then
        return
    end
    -- Claude qui travaille ramène à la conversation (Fenetre.vue).
    if Moteur.travaille then
        Fenetre.revenirAuFil()
    end
    local c = Moteur.courante
    poser(p, 'titre', sansBalises(Fenetre.vue == 'carnet' and Fenetre.TITRE_CARNET or (c and c.titre or Conversation.TITRE_PAR_DEFAUT)))
    poser(p, 'libre', not Moteur.travaille)
    poser(p, 'travaille', Moteur.travaille)
    poser(p, 'forfait', Moteur.texteForfait())
    Fenetre.rafraichirFil()
    -- La carte de l'étape (une nouvelle étape en mode suivre, une autre conversation), avant
    -- l'aperçu, qui en dépend dans son onglet.
    Fenetre.rafraichirEtape(true)
    Fenetre.rafraichirApercu()
    Fenetre.rafraichirProposition()
    Fenetre.rafraichirListe()
    Fenetre.rafraichirNotation()
    -- La leçon (onglet Leçon) après la note : la leçon vient en dernier (consignes), sa bascule aussi.
    Fenetre.rafraichirLecon()
    -- Le Mode suit l'exercice (Je le fais commencé, fini, refusé).
    Fenetre.rafraichirMode()
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
    -- Une demande se suit dans le fil : la page du carnet se quitte.
    Fenetre.quitterCarnet()
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
        p.message = Fenetre.CLAUDE_TRAVAILLE
        return
    end
    local texte = p.saisie
    Fenetre.demandeMise = nil
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
-- Le bandeau sans image à coller (l'infobulle de 📋 dit d'où elle peut venir).
Fenetre.PAS_D_IMAGE = "Pas d'image à coller : copiez-en une (⌘C), puis cliquez 📋."

function Fenetre.coller()
    local chemins = Images.coller()
    if #chemins == 0 then
        Fenetre.p.message = Fenetre.PAS_D_IMAGE
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
    if not c or surLaPageDuCarnet() then
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
    if not c or surLaPageDuCarnet() or #c.elements == 0 then
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

-- Mes demandes ---------------------------------------------------------------------------------
-- Le menu Mes demandes (demandé par Dany le 22 octobre 2026), à droite du menu Style sous le champ
-- (Vues.mesDemandes) : les demandes personnelles de Dany, rangées dans mes-demandes.json
-- (Stockage.lua, section « Mes demandes »), relues à chaque ouverture de la fenêtre. Ses éléments
-- (Fenetre.elementsMesDemandes, tables neuves) : son titre « Mes demandes » (la valeur montrée quand
-- rien n'est choisi), un séparateur, chaque demande « Nom — description » coupée à la largeur du
-- menu (Fenetre.titreDemande), un séparateur, puis Ajouter…, Renommer… et Supprimer… ; sans demande,
-- « Aucune demande gardée » grisé, puis Ajouter… seul. Séparateur et élément grisé : { separator =
-- true } et enabled = false, relevés dans AgViewUtils.getPopupMenu de Lightroom 15.6.
-- Choisir une demande la met dans le champ, à la place du texte tapé, sans l'envoyer
-- (Fenetre.mettreDemande ; Retour l'envoie, Fenetre.lierSaisie) ; le menu revient à son titre, pour
-- rechoisir la même. Ajouter…, Renommer… et Supprimer… ouvrent chacun une petite fenêtre, dans une
-- tâche. Après une retouche, « ＋ Garder la demande » de la ligne d'actions du tour de Claude
-- (Fenetre.garderDemande) ouvre Ajouter… pré-rempli de la demande que Claude a donnée
-- (Conversation.demandeAGarder, Conversation.preparerDemande).

Fenetre.MES_DEMANDES = "Mes demandes"
-- La valeur du menu quand rien n'est choisi : son titre.
Fenetre.MENU_TITRE = 'titre'
Fenetre.AUCUNE_DEMANDE_GARDEE = "Aucune demande gardée"
-- La place des flèches et des bords d'un menu local, ôtée de sa largeur pour le titre d'une demande.
Fenetre.FLECHES_MENU = 32
-- Les messages du bandeau (deux lignes de petit texte : essais-mes-demandes.lua).
Fenetre.DEMANDE_DANS_LE_CHAMP = "Demande mise dans le champ : changez-la au besoin, Retour l'envoie."
Fenetre.DEMANDE_GARDEE = "Demande gardée dans Mes demandes, à droite de Style."
Fenetre.DEMANDE_CHANGEE = "Demande changée dans Mes demandes."
Fenetre.DEMANDE_RETIREE = "Demande retirée de Mes demandes."
Fenetre.AUCUNE_DEMANDE = "Aucune demande gardée : Ajouter… de Mes demandes en garde une."
Fenetre.DEMANDES_ILLISIBLES = "Mes demandes illisibles : le fichier sera mis de côté à la prochaine écriture."
-- Sous les champs de la fenêtre Ajouter… et Renommer….
Fenetre.AIDE_DEMANDE = "Choisie dans Mes demandes, la demande remplit le champ de demande, sans partir : Retour l'envoie."

-- Le titre d'une demande dans le menu : « Nom — description », coupé par « … » pour tenir dans
-- `largeur` (celle du menu, moins ses flèches), mesuré dans la police du menu ('texte', 13) ; le nom
-- seul s'il ne laisse pas de place à la description, ou sans description.
function Fenetre.titreDemande(d, largeur)
    local place = largeur - Fenetre.FLECHES_MENU
    local nom = Fil.tronquer(d.nom or '', place, 'texte')
    local description = Texte.nettoyer(d.description)
    if nom ~= d.nom or description == '' then
        return nom
    end
    local debut = nom .. ' — '
    local reste = place - Fil.largeur(debut, 'texte')
    local coupe = reste > 0 and Fil.tronquer(description, reste, 'texte') or ''
    if coupe == '' or coupe == '…' then
        return nom
    end
    return debut .. coupe
end

-- Les éléments du menu, en tables neuves (Lightroom bloque sur une table relue par Json.decode).
function Fenetre.elementsMesDemandes(liste, largeur)
    local items = { { title = Fenetre.MES_DEMANDES, value = Fenetre.MENU_TITRE }, { separator = true } }
    if #liste == 0 then
        items[#items + 1] = { title = Fenetre.AUCUNE_DEMANDE_GARDEE, value = 'aucune', enabled = false }
    else
        for k, d in ipairs(liste) do
            items[#items + 1] = { title = Fenetre.titreDemande(d, largeur), value = k }
        end
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { title = "Ajouter…", value = 'ajouter' }
    if #liste > 0 then
        items[#items + 1] = { title = "Renommer…", value = 'renommer' }
        items[#items + 1] = { title = "Supprimer…", value = 'supprimer' }
    end
    return items
end

-- Les demandes dans le menu (la liste lue, Fenetre.mesDemandesLues).
function Fenetre.rafraichirMesDemandes(liste)
    Fenetre.mesDemandesLues = liste
    local p, T = Fenetre.p, Fenetre.T
    if p and T then
        p.mesDemandesItems = Fenetre.elementsMesDemandes(liste, T.mesDemandes)
    end
end

-- Relit mes-demandes.json et refait le menu ; un fichier illisible se dit au bandeau. Rend la liste.
function Fenetre.lireMesDemandes()
    local liste, illisible = Stockage.lireDemandes()
    Fenetre.rafraichirMesDemandes(liste)
    if illisible and Fenetre.p then
        Fenetre.p.message = Fenetre.DEMANDES_ILLISIBLES
    end
    return liste
end

-- Un choix dans le menu (l'observateur de `mesDemandes`) : une demande (son indice), Ajouter…,
-- Renommer… ou Supprimer… ; le titre ne fait rien. Le menu revient à son titre.
function Fenetre.choisirMesDemandes(valeur)
    local p = Fenetre.p
    if not p or valeur == nil or valeur == Fenetre.MENU_TITRE then
        return false
    end
    Fenetre.annulerEnvoiAuto()
    p.mesDemandes = Fenetre.MENU_TITRE
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        return false
    end
    if type(valeur) == 'number' then
        local d = (Fenetre.mesDemandesLues or {})[valeur]
        return d ~= nil and Fenetre.mettreDemande(d)
    elseif valeur == 'ajouter' then
        enTache(Fenetre.ajouterDemande, { texte = p.saisie })
    elseif valeur == 'renommer' then
        enTache(Fenetre.renommerDemande)
    elseif valeur == 'supprimer' then
        enTache(Fenetre.supprimerDemande)
    end
    return true
end

-- Met une demande dans le champ, à la place de ce qui y est, sans l'envoyer : ni envoi automatique
-- (la clé posée sous Fenetre.ignorerSaisie), ni bouton ; Retour l'envoie (Fenetre.lierSaisie).
function Fenetre.mettreDemande(d)
    local p = Fenetre.p
    if not p then
        return false
    end
    Fenetre.annulerEnvoiAuto()
    Fenetre.demandeMise = d.texte
    Fenetre.ignorerSaisie = true
    p.saisie = d.texte
    Fenetre.ignorerSaisie = false
    p.message = Fenetre.DEMANDE_DANS_LE_CHAMP
    return true
end

-- La raison d'un refus d'une demande (Stockage.refusDemande) dite en direct dans sa fenêtre, et
-- le bouton d'action grisé tant qu'elle reste (`valide`).
local function verifierDemande(q, liste)
    local refus = Stockage.refusDemande(liste, { nom = q.nom, texte = q.texte }, q.ancien)
    q.erreur = refus or ''
    q.valide = refus == nil
end

-- Le contenu de la fenêtre d'une demande : `avant` (le choix de Renommer…), puis Nom, Description
-- et Texte, le refus et l'aide.
local function contenuDemande(f, q, avant)
    local function ligne(titre, vue)
        return f:row { f:static_text { title = titre, width = 90, alignment = 'right' }, vue }
    end
    local colonne = { bind_to_object = q, spacing = f:control_spacing() }
    for _, vue in ipairs(avant or {}) do
        colonne[#colonne + 1] = vue
    end
    colonne[#colonne + 1] = ligne("Nom :", f:edit_field { value = bind 'nom', immediate = true, width_in_chars = 36,
        placeholder_string = "Portrait en intérieur" })
    colonne[#colonne + 1] = ligne("Description :", f:edit_field { value = bind 'description', immediate = true, width_in_chars = 48,
        placeholder_string = "courte : montrée dans le menu, après le nom" })
    colonne[#colonne + 1] = ligne("Texte :", f:edit_field { value = bind 'texte', immediate = true, width_in_chars = 60, height_in_lines = 6 })
    colonne[#colonne + 1] = f:static_text { title = bind 'erreur', text_color = COULEURS.rouge, width_in_chars = 60 }
    colonne[#colonne + 1] = f:static_text { title = Fenetre.AIDE_DEMANDE, width_in_chars = 60, height_in_lines = 2 }
    return f:column(colonne)
end

-- Remplit les champs de la fenêtre d'une demande.
local function remplirDemande(q, d)
    q.nom, q.description, q.texte = d.nom or '', d.description or '', d.texte or ''
end

-- La fenêtre d'une demande, jusqu'à ce qu'elle se garde ou s'annule : `ecrire(q)` rend vrai et la
-- liste écrite, ou faux et le refus, dit dans la fenêtre rouverte (les champs gardés). Rend vrai
-- si la demande est écrite.
local function fenetreDemande(q, titre, verbe, contenu, ecrire)
    while true do
        local reponse = LrDialogs.presentModalDialog {
            title = titre,
            contents = contenu(),
            actionVerb = verbe,
            actionBinding = { enabled = { bind_to_object = q, key = 'valide' } },
        }
        if reponse ~= 'ok' then
            return false
        end
        local ok, r = ecrire(q)
        if ok then
            Fenetre.rafraichirMesDemandes(r)
            return true
        end
        q.erreur = r
    end
end

-- Ajouter… : une nouvelle demande, pré-remplie de `preremplie` ({ nom, description, texte } :
-- le texte du champ depuis le menu, la demande de Claude depuis « ＋ Garder la demande »). Un nom
-- proposé déjà pris en reçoit un libre (« … 2 »). Dans une tâche.
function Fenetre.ajouterDemande(preremplie)
    preremplie = preremplie or {}
    local liste = Fenetre.lireMesDemandes()
    local f = LrView.osFactory()
    local gardee = false
    LrFunctionContext.callWithContext('Claude · mes demandes', function(context)
        local q = LrBinding.makePropertyTable(context)
        remplirDemande(q, { nom = Stockage.nomLibre(liste, preremplie.nom or ''), description = preremplie.description,
            texte = Texte.nettoyer(preremplie.texte) })
        verifierDemande(q, liste)
        for _, cle in ipairs({ 'nom', 'texte' }) do
            q:addObserver(cle, function() verifierDemande(q, liste) end)
        end
        gardee = fenetreDemande(q, "Ajouter une demande", "Garder", function() return contenuDemande(f, q) end, function()
            return Stockage.garderDemande({ nom = q.nom, description = q.description, texte = q.texte })
        end)
    end)
    if gardee and Fenetre.p then
        Fenetre.p.message = Fenetre.DEMANDE_GARDEE
    end
    return gardee
end

-- Le menu « Demande » d'une fenêtre de Renommer… ou Supprimer… : les noms, en tables neuves.
local function choixDemandes(f, liste)
    local items = {}
    for k, d in ipairs(liste) do
        items[k] = { title = d.nom, value = k }
    end
    return f:row { f:static_text { title = "Demande :", width = 90, alignment = 'right' },
        f:popup_menu { value = bind 'choix', items = items, width = 300 } }
end

-- Renommer… : choisir une demande, puis changer son nom, sa description et son texte. Dans une
-- tâche.
function Fenetre.renommerDemande()
    local liste = Fenetre.lireMesDemandes()
    if #liste == 0 then
        if Fenetre.p then
            Fenetre.p.message = Fenetre.AUCUNE_DEMANDE
        end
        return false
    end
    local f = LrView.osFactory()
    local changee = false
    LrFunctionContext.callWithContext('Claude · mes demandes', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.choix, q.ancien = 1, liste[1].nom
        remplirDemande(q, liste[1])
        verifierDemande(q, liste)
        q:addObserver('choix', function(_, _, k)
            local d = liste[k]
            if d then
                q.ancien = d.nom
                remplirDemande(q, d)
                verifierDemande(q, liste)
            end
        end)
        for _, cle in ipairs({ 'nom', 'texte' }) do
            q:addObserver(cle, function() verifierDemande(q, liste) end)
        end
        changee = fenetreDemande(q, "Renommer une demande", "Enregistrer", function() return contenuDemande(f, q, { choixDemandes(f, liste) }) end,
            function() return Stockage.changerDemande(q.ancien, { nom = q.nom, description = q.description, texte = q.texte }) end)
    end)
    if changee and Fenetre.p then
        Fenetre.p.message = Fenetre.DEMANDE_CHANGEE
    end
    return changee
end

-- Supprimer… : choisir une demande (son texte montré), puis confirmer. Dans une tâche.
function Fenetre.supprimerDemande()
    local liste = Fenetre.lireMesDemandes()
    if #liste == 0 then
        if Fenetre.p then
            Fenetre.p.message = Fenetre.AUCUNE_DEMANDE
        end
        return false
    end
    local f = LrView.osFactory()
    local choisie
    LrFunctionContext.callWithContext('Claude · mes demandes', function(context)
        local q = LrBinding.makePropertyTable(context)
        q.choix, q.apercu = 1, liste[1].texte
        q:addObserver('choix', function(_, _, k)
            q.apercu = liste[k] and liste[k].texte or ''
        end)
        local reponse = LrDialogs.presentModalDialog {
            title = "Supprimer une demande",
            contents = f:column {
                bind_to_object = q,
                spacing = f:control_spacing(),
                choixDemandes(f, liste),
                f:static_text { title = bind 'apercu', width_in_chars = 60, height_in_lines = 4 },
            },
            actionVerb = "Supprimer…",
        }
        if reponse == 'ok' then
            choisie = liste[q.choix]
        end
    end)
    if not choisie then
        return false
    end
    local confirme = LrDialogs.confirm("Supprimer la demande « " .. choisie.nom .. " » ?",
        "Elle est retirée de Mes demandes ; les conversations et les photos ne changent pas.", "Supprimer", "Annuler")
    if confirme ~= 'ok' then
        return false
    end
    local ok, r = Stockage.retirerDemande(choisie.nom)
    if not ok then
        if Fenetre.p then
            Fenetre.p.message = r
        end
        return false
    end
    Fenetre.rafraichirMesDemandes(r)
    if Fenetre.p then
        Fenetre.p.message = Fenetre.DEMANDE_RETIREE
    end
    return true
end

-- « ＋ Garder la demande » de la ligne i (la ligne d'actions d'un tour qui a retouché) : la fenêtre
-- Ajouter… pré-remplie de la demande que Claude a donnée (nom et description proposés, texte),
-- dans une tâche. Rend vrai si la ligne en porte une.
function Fenetre.garderDemande(i)
    Fenetre.annulerEnvoiAuto()
    local l = ligneMontree(i)
    local c = Moteur.courante
    local e = l and l.demande and c and c.elements[l.demande]
    local demande = e and e.genre == 'claude' and Conversation.demandeAGarder(e.texte)
    if not demande then
        return false
    end
    enTache(Fenetre.ajouterDemande, Conversation.preparerDemande(demande))
    return true
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
-- disposition, la seule taille). 2 : la fenêtre B (1.3), de 1 280 × 800, plus basse que la
-- Conversation claire de la 1.2 ; 3 : la fenêtre B agrandie, de 1 497 × 1 200 (demandée par Dany
-- le 21 octobre 2026), qui ne doit pas reprendre le cadre de 1 280 × 800 enregistré sous 2 ; 4 :
-- élargie à 1 948 × 1 200 (demandée par Dany le même jour), sans reprendre le cadre enregistré
-- sous 3.
Fenetre.FORME = 4

function Fenetre.cadre()
    return 'DeveloppeurClaude-' .. Dispositions.NOM .. '-grande-' .. Fenetre.FORME
end

function Fenetre.desabonner()
    Moteur.desabonner('fenetre')
    Notation.desabonner('fenetre')
    Carnet.desabonner('fenetre')
end

-- Boucle d'une fenêtre (sa génération : une fenêtre rouverte a la sienne, l'ancienne boucle
-- s'arrête) : rafraîchit ce que le moteur a changé, la note, l'activité, et les voyants.
-- Toutes les 2 s : les voyants et la photo active (la liaison, lue dans ce module sans commande
-- du système, peut démarrer ou s'arrêter par le menu). Claude Code et l'écran, lus par des
-- commandes du système, ne se relisent qu'à l'ouverture (et l'écran au clic sur son voyant).
function Fenetre.periodique()
    LrTasks.pcall(Fenetre.verifier, false)
    LrTasks.pcall(Fenetre.majPhoto)
    -- Je le fais (1.3) : ce que Dany a déjà fait de la liste, relu dans le catalogue.
    LrTasks.pcall(Fenetre.suivreExercice)
end

-- Le tour de la boucle où la valeur du Mode se repose (Fenetre.reposerMode) : le deuxième, un
-- quart de seconde après le premier, la fenêtre déjà montrée.
Fenetre.TOUR_REPOSER_MODE = 2

function Fenetre.boucle(generation)
    local tic = 0
    while Fenetre.ouverte and Fenetre.generation == generation do
        tic = tic + 1
        local p = Fenetre.p
        if p then
            if tic == Fenetre.TOUR_REPOSER_MODE then
                LrTasks.pcall(Fenetre.reposerMode)
            end
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
            -- La page du carnet (1.3) : relue quand le registre change (un constat, une leçon, un
            -- retrait), d'ici ou d'un autre client du connecteur.
            if Fenetre.vue == 'carnet' and (Fenetre.aRafraichirCarnet or Carnet.version ~= Fenetre.versionCarnet) then
                Fenetre.aRafraichirCarnet = false
                local ok, erreur = LrTasks.pcall(Fenetre.lireCarnet)
                if not ok then
                    Fenetre.versionCarnet = Carnet.version
                    Journal.noter("Carnet de progrès :", tostring(erreur))
                end
            end
            -- La fin d'un tour de Claude : l'onglet Focus montré relit une photo retouchée.
            local okFocus, erreurFocus = LrTasks.pcall(Fenetre.suivreFocus)
            if not okFocus then
                Journal.noter("Onglet Focus :", tostring(erreurFocus))
            end
            -- Un avant/après rangé (ou manqué) par le module : la carte de l'étape relit ses images.
            if Etapes.version ~= Fenetre.versionEtapes then
                local ok, erreur = LrTasks.pcall(Fenetre.rafraichirEtape)
                if not ok then
                    Fenetre.versionEtapes = Etapes.version
                    Journal.noter("Étape (onglet Aperçu) :", tostring(erreur))
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

-- Valeurs des propriétés de la carte Note avant l'ouverture (rafraichirNotation les remplit) : la
-- note posée, ce que Claude propose, la grille des critères (`ng..k`, `ne..k`, `nt..k`), le zoom,
-- les boutons.
local function initialiserNotation(p, D)
    p.noteCatalogue = 0
    p.notePoseeTitre = ''
    p.notePoseeSous = ''
    p.noteClaude = 'aucune'
    p.notationCouleur = 'gris'
    local g = CARTES.note.grille
    for k = 1, CARTES.note.lignes(D) do
        p[g.genre .. k], p[g.etiquette .. k], p[g.texte .. k] = 'vide', '', ''
    end
    p.peutVoirZoom = false
    p.titreAccepterNote = "Accepter"
    p.titreLaisser = "Laisser"
    p.peutAccepterNote = false
    p.peutChangerNote = false
end

-- Valeurs des propriétés de la 1.3 avant l'ouverture (Lightroom l'exige de toute clé liée) : la
-- carte de l'étape, vide et ses boutons inactifs, et la seconde rangée de la carte Proposition.
local function initialiserEtapeEtExercice(p)
    p.etapeTitre = Fenetre.TITRE_ETAPE
    p.etapeSousTitre = ''
    p.etapeTexte = ''
    p.etapePrecedente = false
    p.etapeSuivante = false
    p.etapeAImages = false
    p.etapeADetail = false
    p.titreBascule = "Voir l'avant"
    p.titreJeLeFais = "Je le fais"
    p.peutJeLeFais = false
    p.exerciceEtat = ''
end

-- Le module garde l'avant/après de chaque étape de Claude (Etapes.lua) quand la fenêtre est
-- ouverte ou que son Claude travaille, fenêtre fermée ou non ; jamais pour Claude Desktop seul.
function Fenetre.etapesActives()
    return Fenetre.ouverte == true or Moteur.travaille == true
end

function Fenetre.afficher()
    Etapes.actifPour = Fenetre.etapesActives
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
        -- L'apparence choisie dans le Gestionnaire : ses couleurs et ses images, à chaque ouverture.
        Fenetre.preparerApparence(prefs.apparence)
        local D = Dispositions.dimensions()
        Fenetre.T = D
        Fenetre.cache = {}
        Fenetre.vignettes = {}
        Fenetre.conversationAffichee = nil
        Fenetre.pageListe, Fenetre.cases = 1, nil
        Fenetre.defilement = 0
        Fenetre.indiceImage = nil
        Fenetre.imageCliquee = nil
        -- L'image de proposition demandée par un clic sur l'onglet (Composition lue) : à redemander.
        Fenetre.imageProposition = nil
        Fenetre.vue = 'conversation'
        -- La page du carnet se relira à sa prochaine ouverture.
        Fenetre.pageCarnet, Fenetre.versionCarnet, Fenetre.aRafraichirCarnet, Fenetre.hautCarnet = nil, nil, false, 0
        -- À l'ouverture, l'aperçu montre la photo active, refait (Fenetre.majPhoto) ; l'onglet Focus
        -- se relira (la vignette d'une ouverture passée s'efface).
        Fenetre.idActif, Fenetre.apercuActif, Fenetre.demandeActive, Fenetre.voirActive = nil, nil, nil, true
        if Fenetre.focus and Fenetre.focus.dossier then
            Fichiers.supprimer(Fenetre.focus.dossier)
        end
        Fenetre.focus, Fenetre.lectureFocus = nil, nil
        Fenetre.propositionVue = nil
        -- Je le fais (1.3) : le suivi se relit ; un exercice déjà comparé ne fait pas basculer
        -- l'onglet à l'ouverture (un exercice en cours, si : sa liste attend Dany).
        Fenetre.suivi = nil
        local derniere = Conversation.dernierExercice(Moteur.courante)
        Fenetre.exerciceVu = derniere and derniere.etat == 'comparee' and Fenetre.cleExerciceVu(derniere) or nil
        Fenetre.info = nil
        Fenetre.noteVue, Fenetre.notePhoto = nil, nil
        -- L'onglet Leçon : les leçons déjà là sont vues (pas de bascule à l'ouverture), aucune
        -- choisie (Fenetre.rafraichirLecon).
        Fenetre.leconDe, Fenetre.leconChoisie, Fenetre.leconVue = nil, nil, nil
        Fenetre.noteEnCours = false
        -- Aucune étape choisie (onglet Aperçu) ; ses images se relisent, les copies d'avant
        -- s'effacent.
        Fenetre.etape, Fenetre.imagesEtapes, Fenetre.demandesEtapes, Fenetre.versionEtapes = nil, {}, {}, nil
        Fichiers.supprimer(Fenetre.dossierPourquoi())

        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
        p.recherche = ''
        p.saisie = ''
        p.message = ''
        p.jointes = Fenetre.texteJointes()
        p.style = Consignes.style(prefs.styleChoisi) and prefs.styleChoisi or 'standard'
        -- Mes demandes (22 octobre 2026) : relues à chaque ouverture, le menu sur son titre ; aucune
        -- demande mise dans le champ.
        local demandes, illisibles = Stockage.lireDemandes()
        Fenetre.mesDemandesLues, Fenetre.demandeMise = demandes, nil
        p.mesDemandes = Fenetre.MENU_TITRE
        p.mesDemandesItems = Fenetre.elementsMesDemandes(demandes, D.mesDemandes)
        if illisibles then
            p.message = Fenetre.DEMANDES_ILLISIBLES
        end
        -- Note à l'ouverture (D.ongletParDefaut), le troisième segment.
        p.onglet = D.ongletParDefaut
        p.libre = not Moteur.travaille
        p.travaille = Moteur.travaille
        p.forfait = Moteur.texteForfait()
        p.texteClaude = "Claude Code"
        p.etatClaude = 'neutre'
        p.texteLightroom = "Lightroom"
        p.etatLightroom = 'neutre'
        -- Le Mode, tiré de l'état (Fenetre.modeMontre), reposé ensuite par Fenetre.rafraichirMode.
        p.mode = Fenetre.modeMontre()
        -- Gris tant que le connecteur ne l'a pas dit (Fenetre.verifier, à l'ouverture).
        p.texteEcran = "Écran"
        p.etatEcran = 'neutre'
        p.infoPhoto = ''
        p.imageApercu = Fenetre.imageVide()
        p.legendeApercu = ''
        p.aProposition = false
        p.enAttente = false
        p.propositionTexte = ''
        for cle in pairs(CARTES) do
            p[cle .. 'Monte'], p[cle .. 'Descend'] = false, false
        end
        p.aide = ''
        p.bandeau = Fenetre.etatBandeau(p)
        for i, l in ipairs(Composants.lignes(Composants.module(), '…')) do
            p['versionNom' .. i], p['version' .. i], p['versionAlerte' .. i] = l.nom, l.version, false
            p['versionTexte' .. i] = Fenetre.texteVersion(l)
        end
        p.activite = Moteur.texteTravail(0)
        -- Les cases de la liste des conversations (Fenetre.rafraichirListe les remplit).
        for k = 1, D.cases do
            p['lg' .. k], p['lt' .. k], p['ls' .. k], p['lc' .. k], p['li' .. k] = 'vide', '', '', false, ''
        end
        for i = 1, D.lignes do
            p['t' .. i] = ''
            p['g' .. i] = 'vide'
            p['i' .. i] = ''
            p['a' .. i] = ''
            p['h' .. i] = ''
            p['q' .. i] = false
            p['x' .. i] = ''
        end
        -- La carte de l'onglet Leçon (Fenetre.rafraichirLecon la remplit).
        p.leconTitre = "Leçon de la photo"
        p.leconTexte = ''
        p.leconADetail = false
        -- La carte de l'onglet Focus (Fenetre.rafraichirFocus la remplit).
        p.focusTitre = "Focus"
        p.focusTexte = ''
        initialiserNotation(p, D)
        initialiserEtapeEtExercice(p)
        Fenetre.p = p

        -- La recherche suit chaque frappe (immediate) : la liste revient à sa première page.
        p:addObserver('recherche', function()
            Fenetre.annulerEnvoiAuto()
            Fenetre.pageListe = 1
            Fenetre.rafraichirListe()
        end)
        -- Un clic sur un radio du Mode (un vrai clic : la fenêtre pose la valeur sous la garde
        -- Fenetre.modeAuto) n'envoie pas la demande validée par ce clic.
        p:addObserver('mode', function(_, _, valeur)
            if Fenetre.modeAuto then
                return
            end
            Fenetre.annulerEnvoiAuto()
            Fenetre.changerMode(valeur)
        end)
        p:addObserver('style', function(_, _, valeur)
            Fenetre.annulerEnvoiAuto()
            Chemins.prefs().styleChoisi = valeur
        end)
        -- Un choix dans Mes demandes : une demande dans le champ, ou une fenêtre (Ajouter…,
        -- Renommer…, Supprimer…) ; jamais d'envoi.
        p:addObserver('mesDemandes', function(_, _, valeur) Fenetre.choisirMesDemandes(valeur) end)
        -- Un clic sur un onglet n'envoie pas la demande validée par le clic ; l'aperçu suit
        -- l'onglet (Fenetre.ongletChange).
        p:addObserver('onglet', function(_, _, valeur) Fenetre.ongletChange(valeur) end)
        p:addObserver('saisie', function(_, _, valeur)
            -- Une demande de Mes demandes changée dans le champ part comme une demande tapée.
            if Fenetre.demandeMise ~= nil and valeur ~= Fenetre.demandeMise then
                Fenetre.demandeMise = nil
            end
            Fenetre.saisieValidee(valeur)
        end)
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
        Carnet.abonner('fenetre', function() Fenetre.aRafraichirCarnet = true end)

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
