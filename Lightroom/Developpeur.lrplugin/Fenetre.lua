-- Fenetre.lua : la fenêtre Claude du module Développeur (« Développeur v1.3.6 » dans sa barre de
-- titre, avec la version du module : Fenetre.titreFenetre ; fenêtre flottante, non bloquante) :
-- une conversation avec Claude Code (le fil avec les appels d'outils, les invites en raccourcis et
-- la demande), ce que Claude regarde, sa proposition à accepter, refuser ou ajuster, le cadre qu'il
-- propose (Composition lue, 1.3 : la ligne « Cadre : … » de la carte, son image entière en
-- pointillés dans l'aperçu, ses ajustements dans Ajuster…), la note qu'il propose pour la photo
-- active, le pourquoi de chaque étape (onglet Aperçu, l'ancien Pourquoi ?, 1.3), la mise au point
-- de la photo active comme Focus-Points la montre (onglet Focus, demandé par Dany le 22 octobre
-- 2026), le bouton Suivi qui ouvre le carnet de progrès dans sa fenêtre (FenetreSuivi.lua,
-- correctif 1.3.6), et dans l'infobulle du voyant Lightroom les versions du module et du
-- connecteur MCP-Développeur. La leçon de la photo (onglet
-- Leçon) et « Je le fais » (son bouton, son exercice et le radio du Mode) sont retirés au
-- correctif 1.3.6, comme les radios du Mode : la fenêtre suit la préférence `mode` du Gestionnaire.
--
-- Une seule disposition, la Conversation claire, à l'allure de la fenêtre B (1.3 ; 1 623 × 1 200
-- depuis le correctif 1.3.6 : en-tête, ses deux voyants et le bouton Suivi, fil et saisie au
-- centre, segments et
-- panneau à droite ; le volet des conversations de gauche, sa liste en cases et la page Carnet de
-- progrès du fil sont retirés au correctif 1.3.6 ; l'Atelier, le Panneau et le choix de la
-- disposition le sont depuis le 20 octobre 2026, demandé par Dany).
-- Dispositions.lua l'assemble des pièces de Vues.lua ; ce fichier garde l'état, ce qui remplit les
-- propriétés liées (rafraichir…), les actions, la boucle et l'ouverture. Ses couleurs et ses
-- images suivent l'apparence choisie dans le Gestionnaire, reprise à chaque ouverture
-- (Fenetre.preparerApparence).
--
-- Le SDK ne sait ni ajouter de vues à une fenêtre ouverte ni la faire défiler par programme, et
-- une vue masquée garde sa place : le fil est une grille de lignes fixes (Fil.lua), remplie à
-- chaque changement et parcourue par les boutons ▲ ▼ ; chaque ligne a sa colonne auteur (« Vous », « Claude »,
-- l'heure) et superpose une variante de texte par genre (police, couleur, retrait), dont une seule
-- est visible, et les boutons d'actions (Vues.ligneFil). Lightroom ne
-- masque que les vues simples (`visible` sur une rangée, une colonne ou une boîte reste sans
-- effet, constaté) : les onglets sont des segments en
-- images sous des calques, au-dessus de variantes superposées de même largeur, dont chaque vue
-- simple porte la condition de son onglet (Vues.masquable). Un clic sur une image passe par un
-- calque (Fenetre.calque) ; il n'y a aucun bouton par défaut. Une photo, une conversation
-- (correctif 1.3.6) : la photo seule choisie dans Lightroom montre sa conversation, ou une neuve qui
-- commence par son historique, et plusieurs photos une conversation de groupe jamais gardée
-- (Fenetre.suivreSelection) ; « Repartir à neuf », à droite du titre, en recommence une pour la
-- photo (Fenetre.repartir).
--
-- Structure de la 1.3, posée une fois (les lots suivants remplissent les crochets) : quatre onglets
-- (Focus, Note, Aperçu, Proposition, dans cet ordre depuis le correctif 1.3.6 ; Focus depuis le
-- 22 octobre 2026) ; l'aperçu est commun, mais un onglet peut le remplir (Fenetre.apercuOnglet), un
-- vrai clic sur un onglet a son crochet (Fenetre.surOnglet) ; un clic sur une ligne du fil se
-- répartit dans un ordre fixé (Fenetre.cliquerLigne). La fenêtre s'ouvre sur Focus et y revient
-- quand une autre photo choisie montre sa conversation (Fenetre.revenirAFocus) ; une image de Claude
-- qui arrive montre l'onglet Aperçu, une proposition Proposition, une note Note (décisions de Dany
-- du 25 octobre 2026). Le fil ne montre plus que la conversation : la page Carnet de progrès qu'il
-- montrait (Fenetre.vue) est devenue la fenêtre Suivi (FenetreSuivi.lua), au correctif 1.3.6.

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
local Etapes = require 'Etapes'
local FenetreSuivi = require 'FenetreSuivi'
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

-- Pastilles des voyants (Claude Code, Lightroom), en images par état : plus de pastille bleue, le
-- voyant Mode est retiré, comme le voyant Écran (correctif 1.3.6, décision de Dany du 25 octobre
-- 2026 : plus rien sur l'étalonnage de l'écran).
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

-- La valeur liée du menu Mes demandes (clé `cle` ; faite pour les radios du Mode, retirés au
-- correctif 1.3.6). Un clic de l'utilisateur la pousse de la vue vers la table, et ce clic a validé
-- le champ de demande (constaté le 21 octobre 2026, D3, pour un radio ; supposé pour un menu) :
-- l'envoi automatique s'annule ici, à chaque clic. L'observateur de la clé ne suffit pas : sur le
-- titre du menu rechoisi (comme sur un radio déjà coché), la valeur ne change pas et la table ne
-- prévient pas ses observateurs (supposé, comme la simulation), et la demande tapée partirait
-- 0,3 s plus tard. La fenêtre qui pose la valeur (de la table vers la vue) n'annule rien.
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

-- Conversations ---------------------------------------------------------------------------------
-- (La liste des conversations du volet, sa recherche, Renommer… et Supprimer… sont retirés avec le
-- volet au correctif 1.3.6, comme le choix d'une ancienne conversation et sa photo : chaque photo a
-- sa conversation, que la fenêtre montre quand Dany la choisit, Fenetre.suivreSelection.)

-- Un texte sans balise <EM> (le titre d'une conversation, le nom d'une photo) : posé tel quel
-- dans un texte riche ou dans un texte simple, il ne doit jamais en ouvrir une.
local function sansBalises(texte)
    return (tostring(texte or ''):gsub('</?EM>', ''))
end
Fenetre.sansBalises = sansBalises

-- Le refus d'une action pendant que Claude travaille (le bandeau : deux lignes au plus,
-- Fenetre.texteBandeau, essais-fenetre-b.lua).
Fenetre.CLAUDE_TRAVAILLE = Moteur.CLAUDE_TRAVAILLE

-- Après un changement de conversation (Moteur.montrer, Moteur.nouvelle) : rend vrai si elle est
-- montrée, depuis le bas du fil ; sinon le refus va au bandeau.
local function conversationMontree(ok, raison)
    if not ok then
        if Fenetre.p then
            Fenetre.p.message = raison or ''
        end
        return false
    end
    Fenetre.defilement = 0
    Fenetre.indiceImage = nil
    Fenetre.imageCliquee = nil
    Fenetre.etape = nil
    Fenetre.aRafraichir = true
    -- Les onglets suivent la photo active.
    Fenetre.photoChangee = true
    return true
end

-- Une nouvelle conversation, vide et sans photo (la case Autre photo décochée, les essais).
function Fenetre.nouvelle()
    return conversationMontree(Moteur.nouvelle())
end

-- Montre la conversation `c` (celle d'une photo, neuve ou gardée, ou celle d'un groupe).
function Fenetre.montrerConversation(c)
    return conversationMontree(Moteur.montrer(c))
end

-- Une photo, une conversation (correctif 1.3.6) --------------------------------------------------
-- Décidé avec Dany le 25 octobre 2026. Une photo seule choisie dans Lightroom montre sa conversation
-- (Moteur.conversationDe : la plus récente gardée pour son localIdentifier, une copie virtuelle a la
-- sienne), complétée de « Depuis la dernière fois » si la photo a changé depuis qu'elle l'a vue
-- (Fenetre.completerDepuis) ; sans conversation, une neuve qui commence par « Historique de la
-- photo » (Fenetre.conversationNeuve), gardée seulement à la première demande de Dany (parcourir
-- 300 photos ne crée aucun fichier). Plusieurs photos : une conversation de groupe, jamais gardée,
-- qui commence par un résumé court (Fenetre.conversationDeGroupe) ; changer de photo active sans
-- changer la sélection ne change pas de conversation (la clé du groupe, Lightroom.photos). Le
-- résumé et le complément sont faits sans Claude ni jetons (Moteur.preparerPhoto,
-- Moteur.completerDepuis, Historique.lua : lectures du module par appel direct ; Fenetre.majPhoto
-- tourne dans une tâche), et partent une seule fois avec la demande suivante (Moteur.envoyer). La
-- Demande rapide écrit dans la même conversation de la photo, sans la montrer
-- (Moteur.envoyerRapide) : si la fenêtre la montre, son fil se met à jour (Moteur.signaler), et la
-- demande y porte la mention « Demande rapide » (Fil.MENTION_RAPIDE).

-- Prépare `c` pour la photo `id` : sa photo et sa clé, son titre provisoire, son historique et ce
-- qu'elle en a vu (Moteur.preparerPhoto : la Demande rapide prépare de même la conversation d'une
-- photo qui n'en a pas).
function Fenetre.preparerPhoto(c, id, cle)
    return Moteur.preparerPhoto(c, id, cle)
end

-- Une conversation neuve pour la photo `id`, pas encore gardée.
function Fenetre.conversationNeuve(id, cle)
    return Fenetre.preparerPhoto(Conversation.nouvelle(), id, cle)
end

-- La conversation d'un groupe de photos (`info` : Lightroom.photos), jamais gardée : son dossier
-- d'images est temporaire, effacé quand elle est quittée (Moteur.montrer) ; son titre provisoire,
-- le nombre de photos ; son résumé court (Moteur.resumerGroupe, Historique.groupe).
function Fenetre.conversationDeGroupe(info)
    local c = Conversation.nouvelle()
    c.groupe = info.groupe
    c.cle = info.cle
    c.titre = string.format("%d photos", info.selection or 0)
    c.dossier = LrPathUtils.child(LrPathUtils.child(Chemins.temporaire(), 'Groupes'), c.id)
    Moteur.resumerGroupe(c)
    return c
end

-- La conversation gardée d'une photo, reprise : « Depuis la dernière fois » si la photo a changé
-- depuis qu'elle l'a vue (des étapes de Claude faites ailleurs : la Demande rapide hors de sa
-- conversation, Claude Desktop ; des reprises à la main), rien sinon (Moteur.completerDepuis). Rend
-- vrai si un complément est ajouté.
function Fenetre.completerDepuis(c)
    local ajoute = Moteur.completerDepuis(c)
    if ajoute then
        Fenetre.aRafraichir = true
    end
    return ajoute
end

-- À l'ouverture de la fenêtre (et quand le menu ou ⌃⌥C la rappelle) : la conversation montrée est
-- celle de la photo active, choisie avant de fermer la fenêtre ; ce qui a changé depuis (Claude
-- Desktop, la Demande rapide, la main) se dit aussi. Rien pendant que Claude travaille.
function Fenetre.revoirPhoto()
    local info = Fenetre.info
    local c = Moteur.courante
    if Moteur.travaille or not (info and info.active and (info.selection or 0) <= 1) or not Conversation.dePhoto(c, info.active.id) then
        return false
    end
    return Fenetre.completerDepuis(c)
end

-- La conversation que la sélection montre (case Autre photo cochée) : celle de la photo seule
-- (reprise, ou neuve avec son historique), ou celle du groupe. Rend faux si elle n'a pas pu se
-- montrer : Claude s'est mis au travail pendant que la fenêtre la préparait (une demande rapide,
-- Moteur.RESERVE_RAPIDE ; ses lectures du catalogue attendent), Moteur.montrer refuse. (Quand Dany
-- choisit ainsi une autre photo, Fenetre.suivreSelection ramène l'onglet Focus ; pas Obtenir, qui
-- passe aussi par ici.)
function Fenetre.suivrePhotos(info)
    local c = Moteur.courante
    if info.active and (info.selection or 0) <= 1 then
        local id = info.active.id
        if Conversation.dePhoto(c, id) then
            Fenetre.completerDepuis(c)
            return true
        end
        local gardee = Moteur.conversationDe(id)
        if gardee then
            Journal.noter("Photo choisie : sa conversation")
            if not Fenetre.montrerConversation(gardee) then
                return false
            end
            Fenetre.completerDepuis(gardee)
        else
            return Fenetre.montrerConversation(Fenetre.conversationNeuve(id, info.cle))
        end
    elseif info.groupe and not (c and c.groupe == info.groupe) then
        Journal.noter("Plusieurs photos choisies : conversation du groupe")
        return Fenetre.montrerConversation(Fenetre.conversationDeGroupe(info))
    end
    return true
end

-- « Repartir à neuf » (à droite du titre, à la place du Mode) : une conversation neuve pour la photo
-- seule, avec son historique ; toutes les autres conversations de la photo qui se montrent restent
-- sur le disque, mises de côté (Moteur.ecarter : plus jamais reprises ni montrées), jamais effacées.
-- Grisé pendant que Claude travaille, sans photo seule, et tant que la conversation montrée n'est pas
-- celle de la photo seule active (une conversation neuve de cette photo comprise) : la case Autre
-- photo décochée, une photo choisie pendant le travail de Claude ; Dany mettrait sinon de côté une
-- conversation qu'il ne voit pas (`peutRepartir`). À appeler depuis une tâche.
Fenetre.REPARTIR_SANS_PHOTO = "Repartir à neuf : choisissez une seule photo dans Lightroom."
Fenetre.REPARTIR_AUTRE = "Repartir à neuf : la conversation montrée n'est pas celle de la photo active."
Fenetre.REPARTIE = "Conversation neuve pour cette photo : l'ancienne reste sur le disque, mise de côté."

function Fenetre.peutRepartir(info)
    return not Moteur.travaille and type(info) == 'table' and info.active ~= nil and (info.selection or 0) <= 1
        and Conversation.dePhoto(Moteur.courante, info.active.id)
end

function Fenetre.poserRepartir()
    if Fenetre.p then
        poser(Fenetre.p, 'peutRepartir', Fenetre.peutRepartir(Fenetre.info))
    end
end

function Fenetre.repartir()
    local p = Fenetre.p
    if not p then
        return false
    end
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        return false
    end
    local info = Lightroom.photos()
    Fenetre.info = info
    if not Fenetre.peutRepartir(info) then
        local seule = type(info) == 'table' and info.active ~= nil and (info.selection or 0) <= 1
        p.message = seule and Fenetre.REPARTIR_AUTRE or Fenetre.REPARTIR_SANS_PHOTO
        Fenetre.poserRepartir()
        return false
    end
    local id = info.active.id
    local c = Moteur.courante
    local neuve = Fenetre.conversationNeuve(id, info.cle)
    if not Fenetre.montrerConversation(neuve) then
        return false
    end
    -- Toutes les conversations de la photo qui se montrent (les gardées, d'avant le correctif
    -- comprises, et la montrée si elle est commencée), sauf la neuve.
    local aEcarter = {}
    for _, x in ipairs(Moteur.conversations) do
        aEcarter[#aEcarter + 1] = x
    end
    aEcarter[#aEcarter + 1] = c
    for _, x in ipairs(aEcarter) do
        if x ~= neuve and Moteur.montrable(x) and Conversation.dePhoto(x, id) and Conversation.commencee(x) then
            Moteur.ecarter(x)
        end
    end
    Fenetre.voirSelection(info.cle)
    Journal.noter("Repartir à neuf : conversation neuve pour la photo", tostring(id))
    p.message = Fenetre.REPARTIE
    Fenetre.poserRepartir()
    return true
end

-- Fil -----------------------------------------------------------------------------------------
-- La grille du fil montre la conversation, toujours (la page Carnet de progrès qu'elle montrait
-- aussi, Fenetre.vue, est devenue la fenêtre Suivi au correctif 1.3.6, FenetreSuivi.lua).

-- La largeur du texte d'une ligne du fil (952) : la largeur utile du centre, sans la colonne auteur
-- et son écart (Vues.ligneFil, D.texteFil). L'icône et le retrait des genres qui en portent une
-- sont dans cette largeur (Fil.RETRAITS).
function Fenetre.largeurTexte()
    return Fenetre.T.texteFil
end

-- Le fil d'une conversation vide : un titre, puis l'aide, coupée comme une ligne de note (dans les
-- 952 points du texte, le retrait d'une note ôté).
Fenetre.FIL_VIDE_TITRE = "Demandez à Claude."
Fenetre.FIL_VIDE = "Claude voit la photo active et la sélection de Lightroom, et retouche avec le connecteur MCP-Développeur."

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
        -- L'étape choisie (onglet Aperçu) était de l'autre conversation.
        Fenetre.etape = nil
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
    -- Chaque ligne : son texte, son genre et son icône ; sa colonne auteur (`a..i` : 'dany',
    -- 'claude', 'heure' ou rien ; l'heure dans `h..i`) ; ses actions (`x..i` : 'note', 'demande',
    -- 'note+demande' ou rien). (« Pourquoi ? », `q..i`, est retiré au correctif 1.3.6 : un clic sur
    -- la ligne d'une étape en tient lieu.)
    for i = 1, T.lignes do
        local l = lignes[premiere + i - 1]
        poser(p, 't' .. i, l and l.texte or '')
        poser(p, 'g' .. i, l and l.genre or 'vide')
        poser(p, 'i' .. i, l and l.icone or '')
        poser(p, 'a' .. i, l and (l.auteur or (l.heure and 'heure')) or '')
        poser(p, 'h' .. i, l and l.heure or '')
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
    Fenetre.rafraichirFil()
end

-- Clic sur une ligne du fil, réparti dans un ordre fixé (1.3) : une image, une étape de Claude,
-- sinon le détail d'un outil (les lignes de la page Carnet de progrès sont retirées avec elle au
-- correctif 1.3.6). Fenetre.sorteDeClic dit laquelle, Fenetre.clics[sorte](l, e) la traite. Un
-- clic tient lieu de « Pourquoi ? », retiré au correctif 1.3.6 (décision de Dany du 25 octobre
-- 2026) : une étape (la ligne d'un appel, Conversation.estEtape) s'ouvre dans l'onglet Aperçu, son
-- avant/après dans l'aperçu et sa raison dans la carte (Fenetre.montrerEtape) ; une image aussi,
-- montrée dans l'aperçu, avec dans la carte le pourquoi de l'étape qui la précède dans le fil s'il
-- y en a une (Fenetre.voirImageDuFil). La ligne d'actions d'une notation n'a pas de texte : ses
-- boutons (Fenetre.voirNote, Fenetre.garderDemande).
function Fenetre.estEtape(e)
    return Conversation.estEtape(e)
end

function Fenetre.sorteDeClic(l, e)
    if l.image then
        return 'image'
    elseif l.genre == 'actions' then
        return nil
    elseif e and Fenetre.estEtape(e) then
        return 'etape'
    elseif e and e.genre == 'outil' then
        return 'outil'
    end
    return nil
end

Fenetre.clics = {
    -- L'image dans l'onglet Aperçu, avec le pourquoi de l'étape qui la précède : les images de la
    -- conversation relues, le clic choisit la sienne, sans bascule vers une image arrivée
    -- entre-temps (Fenetre.voirImageDuFil) ; celle de la proposition qui attend, dans l'onglet
    -- Proposition (Fenetre.voirPropositionDuFil).
    image = function(l)
        if not Fenetre.voirPropositionDuFil(l.image) then
            Fenetre.voirImageDuFil(l.image)
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
    -- détail d'un outil s'ouvre à part, l'aperçu reste tel quel.
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

-- « ☆ Voir la note » de la ligne i : la notation de cette ligne dans l'onglet Note.
function Fenetre.voirNote(i)
    Fenetre.annulerEnvoiAuto()
    local l = ligneMontree(i)
    return l ~= nil and l.notation ~= nil and Fenetre.montrerNote(l.notation)
end


-- Le bandeau quand la photo active n'est pas parmi celles d'une notation (« ☆ Voir la note ») : la
-- carte Note montre la photo active, et la fenêtre ne change jamais la sélection (une autre photo
-- montrerait sa conversation, Fenetre.suivreSelection).
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

-- L'aperçu est commun aux quatre onglets (Focus, Note, Aperçu, Proposition), mais un onglet peut le
-- remplir (1.3) : Note montre la photo active et les images de la conversation, comme avant ;
-- Proposition, l'image de la proposition ; Aperçu (l'ancien Pourquoi ?), l'avant ou l'après de
-- l'étape choisie ; Focus, la photo active et ses cadres de mise au point.
-- Fenetre.apercuOnglet[valeur](p, T, c), s'il existe, est
-- demandé d'abord par Fenetre.rafraichirApercu : vrai s'il a rempli l'aperçu lui-même
-- (imageApercu, legendeApercu, aImage, peutPrecedente, peutSuivante), nil ou faux pour l'aperçu
-- d'avant. Une image du fil montrée (cliquée, ou de Claude à son arrivée) reste prioritaire.
-- Fenetre.surOnglet[valeur](valeur) suit un vrai clic sur cet onglet (son segment,
-- Fenetre.choisirSegment, ou une étape et une image du fil ; jamais une bascule de la fenêtre,
-- Fenetre.choisirOnglet). Ni l'un ni l'autre n'attend : une lecture du catalogue ou un
-- rendu passe par sa propre tâche. Ceux d'Aperçu, de Focus et de Proposition (l'image de la
-- proposition demandée par un clic : Composition lue) sont dans leur section ; Note n'en a pas.
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

-- L'onglet change (clic ou bascule) : une image du fil montrée cède la place à l'aperçu de
-- l'onglet (Fenetre.voirImageDuFil montre la sienne une fois l'onglet changé) ; un vrai clic
-- n'envoie pas la demande validée par ce clic, et appelle son crochet.
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
    local nature = image.outil == 'jointe' and "photo jointe" or (image.outil or "aperçu")
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
    -- Une autre conversation (une autre photo choisie dans Lightroom) : l'image cliquée était d'une
    -- autre conversation, l'aperçu revient à l'onglet ; l'image de proposition demandée aussi
    -- (Fenetre.montrerImageProposition).
    if Fenetre.apercuDe ~= c then
        Fenetre.imageCliquee = nil
        Fenetre.imageProposition = nil
    end
    -- Une image de plus dans la conversation montrée (Claude regarde, une photo jointe) : elle se
    -- montre, à la place de la photo active ; une image cliquée avant rend la main à l'onglet, et
    -- l'image de proposition demandée par un clic cède aussi la place.
    local nouvelle
    if Fenetre.apercuDe == c and Fenetre.nbImages and n > Fenetre.nbImages then
        Fenetre.voirActive = false
        Fenetre.indiceImage = nil
        Fenetre.imageCliquee = nil
        Fenetre.imageProposition = nil
        nouvelle = Fenetre.images[n]
    end
    Fenetre.apercuDe, Fenetre.nbImages = c, n
    -- Une image de Claude qui arrive (view_photo, une comparaison) montre l'onglet Aperçu, avec le
    -- pourquoi de l'étape qui la précède (décision de Dany du 25 octobre 2026, correctif 1.3.6) ;
    -- celle d'une proposition va dans l'onglet Proposition (Fenetre.rafraichirProposition), une
    -- photo jointe par Dany reste dans l'onglet montré.
    if nouvelle and Fenetre.imageDeClaude(c, nouvelle) and Fenetre.voirImageDuFil(nouvelle.chemin, true) then
        return
    end
    -- L'aperçu de l'onglet (Fenetre.apercuOnglet), sauf quand une image du fil est montrée.
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
        local reduite = vignetteApercu(T, Moteur.dossier(c), chemin)
        if reduite then
            Fenetre.vignettes[cle] = reduite
            if Fenetre.p and Fenetre.T == T and Moteur.courante == c then
                Fenetre.p.imageApercu = reduite
            end
        end
    end)
end

-- Dans l'onglet Aperçu, quand une image du fil est montrée (cliquée, ou de Claude à son arrivée) :
-- après ◀ ▶, la carte suit l'image montrée, le pourquoi de l'étape qui la précède
-- (Fenetre.choisirEtapeDeLImage) ; la photo active montrée ne change pas la carte.
local function carteSuitImage()
    local p, T = Fenetre.p, Fenetre.T
    if p and T and p.onglet == T.ongletEtape and Fenetre.imageCliquee and not Fenetre.voirActive then
        Fenetre.choisirEtapeDeLImage(Moteur.courante, Fenetre.indiceImage or #(Fenetre.images or {}))
        Fenetre.rafraichirEtape(true)
    end
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
            carteSuitImage()
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
    carteSuitImage()
end

-- Le titre de la fenêtre de l'aperçu en grand : la légende de l'aperçu, sans ses balises.
local function titreAgrandi(defaut)
    local legende = Fenetre.p and sansBalises(Fenetre.p.legendeApercu) or ''
    return "Claude · " .. (legende ~= '' and legende or defaut)
end

-- Agrandir (décision de Dany du 25 octobre 2026, correctif 1.3.6 ; 1 100 × 740 jusque-là) : l'image
-- en grand tient dans GRANDE, sous chacune de ses formes (l'aperçu, Focus, la photo active, une
-- image du fil, et l'avant et l'après d'une étape côte à côte : les deux ensemble, Fenetre.cadreDeux) ;
-- elle laisse à la fenêtre modale sa barre de titre et son bouton Fermer sur l'écran de Dany, de
-- 3 440 × 1 440. Une image plus petite est montrée à sa vraie taille, jamais étirée (Images.grande) :
-- la vignette de la photo active est celle que Lightroom a en cache, plus grande que
-- TAILLE_PHOTO_ACTIVE (1 720 pixels de grand côté pour un RAW, constaté le 17 octobre 2026), celles
-- des étapes ont 1 024 pixels (Etapes.COTE).
Fenetre.GRANDE = { largeur = 2000, hauteur = 1250 }

-- Une image en grand (`dossier`, `nom`) dans une fenêtre à part, titrée `titre`, depuis une tâche
-- (Images.grande, sips) ; illisible, elle est dite (« Aperçu illisible ») et rend faux.
function Fenetre.agrandirUne(titre, dossier, nom)
    local G = Fenetre.GRANDE
    local chemin, l, h
    if dossier and nom then
        chemin, l, h = Images.grande(dossier, nom, G.largeur, G.hauteur)
    end
    if not chemin then
        LrDialogs.message("Aperçu illisible", tostring(nom or ''), 'warning')
        return false
    end
    LrDialogs.presentModalDialog {
        title = titre,
        contents = LrView.osFactory():picture { value = chemin, width = l, height = h },
        actionVerb = "Fermer",
        cancelVerb = '< exclude >',
    }
    return true
end

-- L'aperçu en grand, dans une fenêtre à part ; pour une étape (onglet Aperçu), son avant et son
-- après côte à côte (Fenetre.agrandirEtape).
function Fenetre.agrandir()
    if Fenetre.modeEtape() then
        Fenetre.agrandirEtape()
        return
    end
    -- L'onglet Focus : la vignette de la photo active avec ses cadres de mise au point ; sauf après
    -- un clic sur une ligne d'image du fil, que l'aperçu montre alors (comme Fenetre.modeEtape) :
    -- c'est elle qu'Agrandir montre.
    local r = Fenetre.focusMontre() and not Fenetre.imageCliquee and Fenetre.focusActif()
    if r and r.fichier then
        enTache(Fenetre.agrandirUne, titreAgrandi("Focus"), r.dossier, r.fichier)
        return
    end
    -- L'image de la proposition montrée par l'onglet Proposition (le cadre proposé en pointillés,
    -- Composition lue, 1.3) : celle-là, même si la photo active a changé entre-temps.
    local _, indiceProposition = Fenetre.imagePropositionMontree()
    local a, active = Fenetre.apercuActif, Fenetre.info and Fenetre.info.active
    if not indiceProposition and Fenetre.voirActive and active and a and a.id == active.id then
        enTache(Fenetre.agrandirUne, titreAgrandi("photo active"), a.dossier, a.fichier)
        return
    end
    local c = Moteur.courante
    local n = #(Fenetre.images or {})
    if not c or n == 0 then
        return
    end
    local image = Fenetre.images[indiceProposition or Fenetre.indiceImage or n]
    enTache(Fenetre.agrandirUne, titreAgrandi("aperçu"), Moteur.dossier(c), image.chemin)
end

-- Deux images côte à côte en grand, dans une fenêtre à part (1.3) : l'avant et l'après d'une étape
-- (onglet Aperçu). `gauche` et `droite` :
-- { dossier, nom, titre } (le titre au-dessus de l'image, « Avant », « Après ») ; `legende`
-- (facultative) dessous, coupée à la largeur des deux images ; le titre de la fenêtre est
-- « Claude · <titre> ». Les deux ensemble, titres et légende compris, tiennent dans GRANDE
-- (Fenetre.cadreDeux, puis Images.grande, sips : depuis une tâche). Une image illisible est dite à
-- sa place, sur LARGEUR_ILLISIBLE ; rend faux si aucune ne se lit.
Fenetre.ECART_DEUX = 12
Fenetre.ECART_TITRE = 4
Fenetre.ECART_LEGENDE = 8
Fenetre.LARGEUR_ILLISIBLE = 200

-- La place de chaque image de deux montrées côte à côte (pur) : la largeur et la hauteur au plus à
-- donner à Images.grande pour que les deux, chacune sous son titre (une ligne de gras) et au-dessus
-- de la légende (coupée à leur largeur ensemble, Fenetre.lignesCarte), tiennent dans GRANDE.
-- `dimensions` : une entrée par image, { largeur, hauteur } en pixels, ou false (illisible : la
-- place de son texte). La légende prend sa hauteur aux images ; des images plus petites
-- l'allongent : la place se refait tant que ses lignes changent (quatre fois au plus). Rend la
-- largeur, la hauteur et les lignes de la légende à cette place.
function Fenetre.cadreDeux(dimensions, legende)
    local G = Fenetre.GRANDE
    local ligne = math.ceil(Metriques.texte.hauteur)
    local titre = math.ceil(Metriques.gras.hauteur) + Fenetre.ECART_TITRE
    local demi = math.floor((G.largeur - Fenetre.ECART_DEUX) / 2)
    local avecLegende = Texte.nettoyer(legende or '') ~= ''
    local function largeurEnsemble(hauteur)
        local total = Fenetre.ECART_DEUX
        for _, d in ipairs(dimensions or {}) do
            if type(d) == 'table' and tonumber(d[1]) and tonumber(d[2]) then
                total = total + math.floor(d[1] * math.min(demi / d[1], hauteur / d[2], 1))
            else
                total = total + Fenetre.LARGEUR_ILLISIBLE
            end
        end
        return total
    end
    local hauteur, lignes = G.hauteur - titre, {}
    for _ = 1, 4 do
        lignes = avecLegende and Fenetre.lignesCarte(legende, largeurEnsemble(hauteur)) or {}
        local reste = G.hauteur - titre - (#lignes > 0 and (Fenetre.ECART_LEGENDE + #lignes * ligne) or 0)
        if reste >= hauteur then
            break
        end
        hauteur = reste
    end
    return demi, math.max(1, hauteur), lignes
end

function Fenetre.agrandirDeux(titre, gauche, droite, legende)
    local f = LrView.osFactory()
    local images, dimensions = {}, {}
    for i, image in ipairs({ gauche or false, droite or false }) do
        images[i] = type(image) == 'table' and image.dossier and image.nom and image or false
        local l, h
        if images[i] then
            l, h = Images.dimensions(LrPathUtils.child(image.dossier, image.nom))
        end
        dimensions[i] = (l and h) and { l, h } or false
    end
    local largeurMax, hauteurMax = Fenetre.cadreDeux(dimensions, legende)
    local colonnes, largeur, lues = { spacing = Fenetre.ECART_DEUX }, Fenetre.ECART_DEUX, 0
    for i, image in ipairs({ gauche or false, droite or false }) do
        local chemin, l, h
        if images[i] then
            chemin, l, h = Images.grande(image.dossier, image.nom, largeurMax, hauteurMax)
        end
        local nom = type(image) == 'table' and tostring(image.titre or '') or ''
        if chemin then
            lues = lues + 1
            colonnes[#colonnes + 1] = f:column {
                spacing = Fenetre.ECART_TITRE,
                f:static_text { title = nom, font = POLICES.gras, width = l },
                f:picture { value = chemin, width = l, height = h },
            }
            largeur = largeur + l
        else
            colonnes[#colonnes + 1] = f:column {
                f:static_text { title = (nom ~= '' and (nom .. " : ") or '') .. "image illisible", font = POLICES.texte,
                    width = Fenetre.LARGEUR_ILLISIBLE },
            }
            largeur = largeur + Fenetre.LARGEUR_ILLISIBLE
        end
    end
    if lues == 0 then
        LrDialogs.message("Aperçu illisible", tostring(titre or ''), 'warning')
        return false
    end
    local contenu = { spacing = Fenetre.ECART_LEGENDE, f:row(colonnes) }
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
-- la carte de l'étape (onglet Aperçu, clé 'etape', 1.3) et celui de l'onglet Focus (clé 'focus') :
-- coupés en lignes comme le fil, à la largeur de l'intérieur des cartes, dans la police de leur
-- carte (`police` de CARTES : P.texte12 pour les quatre, lot B5), montrés page par page avec ▲ ▼
-- (Vues.fleches). (La carte de l'onglet Suivi, clé 'suivi', est retirée avec l'onglet au correctif
-- 1.3.6 : la fenêtre Suivi a ses pages, FenetreSuivi.lua.) Une carte à `emphase` (Focus, ses
-- blocs ; la note, ses verdicts) garde ses passages balisés, en gras de même taille ; les autres
-- textes perdent leurs balises (sans emphasis_font, Lightroom ne les montrerait pas, constaté D4). La carte Note est une
-- grille (`grille`) : ses lignes sont des tables (Fenetre.lignesCriteres : genre, étiquette,
-- texte), posées ligne par ligne dans `ng..k`, `ne..k` et `nt..k`. Un texte qui change revient à
-- sa première page.
Fenetre.pages = {}


local CARTES = {
    note = { grille = { genre = 'ng', etiquette = 'ne', texte = 'nt' }, largeur = 'largeurNote',
        lignes = function(T) return (T.criteres or 8) + 1 end, police = 'texte12', emphase = 'gras12' },
    proposition = { texte = 'propositionTexte', largeur = 'largeurProposition', lignes = function(T) return T.propLignes or 5 end,
        police = 'texte12' },
    etape = { texte = 'etapeTexte', largeur = 'largeurEtape', lignes = function(T) return T.etapeLignes or 8 end, police = 'texte12' },
    focus = { texte = 'focusTexte', largeur = 'largeurFocus', lignes = function(T) return T.focusLignes or 8 end, police = 'texte12',
        emphase = 'gras12' },
}
Fenetre.CARTES = CARTES

-- Les lignes d'un texte dans `largeur` points (paragraphes gardés, lignes vides comprises), dans
-- `police` (une clé de Metriques ; P.texte sans elle) ; `emphase` : la police de ses passages
-- balisés (<EM>), chaque ligne aux balises fermées, un passage coupé rouvert à la suivante
-- (Fil.lignesCarte, que la fenêtre Suivi emploie aussi).
Fenetre.lignesCarte = Fil.lignesCarte

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
-- texte qui change reste à la même page.
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

-- Focus (demandé par Dany le 22 octobre 2026) ------------------------------------------------
-- L'onglet Focus, le premier des segments, montre la photo active comme le module Focus-Points
-- la montre : dans l'aperçu, sa vignette avec, pour un fichier Fujifilm, le point ou la zone de
-- mise au point à sa taille (rouge) et les visages et éléments du sujet que le boîtier a détectés
-- (coins jaunes), dessinés par le connecteur (`mcp-developpeur --focus`, Images.lireFocus) ;
-- dessous, la carte Image, Prise de vue et Mise au point (Fil.texteFocus), les valeurs de Lightroom
-- (Lightroom.infosFocus) et celles du boîtier, lues dans l'original. Autre marque : la photo sans
-- cadre, Image et Prise de vue, et « Mise au point : non lue (seulement les fichiers Fujifilm pour
-- l'instant) ». Copie virtuelle : l'original de la copie (Vignettes.decrireVignette).
-- La fenêtre s'ouvre sur Focus et y revient chaque fois qu'une autre photo choisie dans Lightroom
-- montre sa conversation (Fenetre.revenirAFocus ; décision de Dany du 25 octobre 2026, correctif
-- 1.3.6 : jusque-là, seulement un vrai clic sur son segment). L'onglet suit la photo active
-- (Fenetre.majPhoto) ; un onglet caché ne lit rien ; tout se lit dans une tâche (Fenetre.lireFocus :
-- la vignette par Vignettes.demander, le boîtier par LrTasks.execute, cinq secondes au plus), une
-- lecture à la fois, jamais de calcul en Lua ; le résultat est gardé pour la photo (Fenetre.focus)
-- tant qu'elle ne change pas : un vrai clic sur le segment relit seulement si sa géométrie (cadre, orientation)
-- ou son édition (editCount, lastEditTime : une retouche) a changé, et la fin d'un tour de Claude
-- aussi quand l'onglet est montré (Fenetre.suivreFocus ; constaté le 22 octobre 2026 : après
-- « Retouche pro », l'onglet montrait encore la photo d'avant, et Dany a dû demander « reload
-- l'image »). L'aperçu des autres onglets, avec le carré de --marquer-af, ne change pas.

-- Après une retouche, tant que Lightroom n'a pas refait l'aperçu de la photo, il répond « error
-- loading thumb » à une vignette de 512 px ou plus, mais rend encore celle de 256 (constaté le
-- 22 octobre 2026, par la commande vignettes, plus d'une minute après une retouche faite photo
-- affichée dans le module Développement : l'onglet relu restait sans image). La vignette se
-- redemande une fois par seconde, ESSAIS_VIGNETTE_FOCUS fois au plus, puis à TAILLE_SECOURS_FOCUS :
-- moins nette, mais à jour ; la grande se relit au clic suivant ou à la fin d'un tour de Claude.
Fenetre.ESSAIS_VIGNETTE_FOCUS = 3
Fenetre.TAILLE_SECOURS_FOCUS = 256

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
        -- Sans la grande vignette : la petite, et pas de signature (le prochain vrai clic, ou la
        -- fin d'un tour de Claude, relit la grande).
        source = Vignettes.demander({ active.id }, Fenetre.TAILLE_SECOURS_FOCUS, dossier)[active.id]
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

-- Focus revient quand une autre photo choisie dans Lightroom montre sa conversation (ou un groupe la
-- sienne : Fenetre.suivreSelection) : une bascule de la fenêtre (Fenetre.choisirOnglet, sans le
-- crochet d'un vrai clic), qui lit la photo active (Fenetre.apercuOnglet.focus). Une proposition qui
-- attend déjà dans cette conversation n'est pas une arrivée : elle ne reprend pas la main
-- (Fenetre.propositionVue) ; l'onglet Proposition la montre.
function Fenetre.revenirAFocus()
    local T, c = Fenetre.T, Moteur.courante
    if not T then
        return
    end
    local prop = c and Conversation.propositionEnAttente(c)
    if prop then
        Fenetre.propositionVue = prop.id
    end
    Fenetre.choisirOnglet(T.ongletFocus)
end

-- Suivi : le carnet de progrès (correctif 1.3.6) -------------------------------------------------
-- Le bouton Suivi de l'en-tête (Vues.boutonSuivi) ouvre le carnet de progrès dans sa fenêtre à part
-- (FenetreSuivi.lua ; décision de Dany du 25 octobre 2026), comme Publication et Consommation : le
-- résumé du carnet, ses constats et « Photos d'un défaut… », que montrait l'onglet Suivi (sa carte,
-- Vues.suivi, son segment et leurs images sont retirés). Ouverte, elle passe devant.
function Fenetre.ouvrirSuivi()
    FenetreSuivi.afficher()
end

-- Proposition ---------------------------------------------------------------------------------
-- La carte Proposition montre la proposition en attente ; sans elle, la dernière proposition si
-- une étape de Claude sur sa photo l'a close (1.3.2, Conversation.propositionClose) : sa phrase en
-- tête (Fenetre.phraseClose), Accepter, Refuser et Ajuster… grisés. (L'exercice « Je le fais » qui
-- y prenait place est retiré au correctif 1.3.6.)

Fenetre.AUCUNE_PROPOSITION = "Aucune proposition en attente.\n\nCliquez Obtenir : Claude propose une retouche de la photo "
    .. "active, sans rien appliquer, et attend ici votre accord. En mode « Proposer d'abord », ses autres retouches "
    .. "attendent aussi ici."

function Fenetre.rafraichirProposition()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    poser(p, 'enAttente', prop ~= nil and not Moteur.travaille)
    poser(p, 'aProposition', prop ~= nil)
    Fenetre.poserObtenir()
    -- Une proposition qui arrive se montre (onglet Proposition), celle d'Obtenir comprise ; une
    -- seule fois, pour ne pas reprendre la main à chaque rafraîchissement.
    if prop and prop.id ~= Fenetre.propositionVue then
        Fenetre.propositionVue = prop.id
        Fenetre.choisirOnglet(Fenetre.T.ongletProposition)
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
-- et son rang dans les images (Fenetre.images) tant que la demande vaut (onglet Proposition, pas
-- d'image cliquée dans le fil, même conversation, la même proposition toujours en attente, son
-- image toujours là) ; nil sinon.
function Fenetre.imagePropositionMontree()
    local im, p, T, c = Fenetre.imageProposition, Fenetre.p, Fenetre.T, Moteur.courante
    if not (im and p and T and c) or im.conversation ~= c or p.onglet ~= T.ongletProposition or Fenetre.imageCliquee then
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

-- L'aperçu de l'onglet Proposition (Fenetre.apercuOnglet) : l'image de proposition demandée par un
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
    return Fenetre.apercuProposition(p, T)
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
-- Un clic sur une étape du fil (la ligne de son appel, Conversation.estEtape ; le bouton
-- « Pourquoi ? » à son bout est retiré au correctif 1.3.6, décision de Dany du 25 octobre 2026)
-- l'ouvre dans l'onglet Aperçu (l'ancien onglet Pourquoi ?, D.ongletEtape) : dans l'aperçu, son
-- après (ou son avant : Voir l'avant / Voir l'après), que
-- le module a gardé au moment de l'étape sans rien écrire au catalogue (Etapes.lua) ; dans la
-- carte (Vues.etape), « Étape 2 sur 4 · <but> », la raison donnée par Claude et les réglages
-- changés, page par page ; ◀ ▶ d'une étape à l'autre de la même photo ; Détail… (l'appel et sa
-- réponse) ; Agrandir, l'avant et l'après côte à côte (Fenetre.agrandirDeux).
-- Fenetre.etape = { conversation, photo, id (etape_id du module, nil sans), element (id de
-- l'élément du fil), vue ('apres' ou 'avant'), suivre } : l'étape montrée, remise à nil quand la
-- conversation montrée change. En mode suivre (la dernière étape de sa photo, ou l'onglet ouvert
-- sans étape choisie), une nouvelle étape de la même photo devient l'étape montrée ; ◀ le quitte,
-- ▶ jusqu'à la dernière le reprend. Un clic sur une image du fil (une ligne « … · cliquer pour le
-- voir ») ouvre aussi l'onglet, et une image de Claude qui arrive (view_photo, une comparaison ;
-- pas une proposition) y bascule (correctif 1.3.6) : l'aperçu montre l'image, la carte le pourquoi
-- de l'étape qui la précède dans le fil (un classement sauté : il ne change pas l'image), sans la
-- suivre ; sans étape avant elle, la carte le dit (Fenetre.voirImageDuFil). L'image d'une
-- proposition et une photo jointe par Dany ne sont faites par aucune étape : pas de pourquoi, la
-- carte dit ce qu'elles sont (Fenetre.texteSansEtape) ; un clic sur l'image d'une proposition qui
-- attend ouvre l'onglet Proposition, où sont sa raison et Accepter (Fenetre.voirPropositionDuFil).
-- La boucle suit Etapes.version : les images arrivées se montrent. Les ◀ ▶ de l'aperçu sont coupés
-- quand il montre une étape (Fenetre.changerImage) ; devant une image du fil, ils vont d'une image
-- à l'autre, et la carte suit.

Fenetre.AIDE_ETAPE = "Cliquez une étape de Claude dans le fil : son avant/après s'affiche au-dessus, et sa raison ici."
-- La carte devant une image du fil qu'aucune étape de Claude ne précède ; devant l'image d'une
-- proposition (rien n'est appliqué par elle) ; devant une photo jointe par Dany.
Fenetre.SANS_ETAPE_IMAGE = "Aucune étape de Claude avant cette image dans le fil."
Fenetre.SANS_ETAPE_PROPOSITION = "Aperçu d'une proposition de Claude, pas d'une étape : rien n'est appliqué par elle. Sa raison est dans l'onglet Proposition tant qu'elle attend votre accord."
Fenetre.SANS_ETAPE_JOINTE = "Photo jointe par vous : aucune étape de Claude ne l'a faite."
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

-- L'indice de l'étape de Claude qui précède l'élément `element` dans le fil de `c` (la plus proche
-- avant lui, Conversation.estEtape), nil sans étape avant lui. Un classement (set_metadata,
-- manage_collections : Conversation.CLASSEMENTS) ne change pas l'image : il est sauté, pour garder
-- la retouche qui l'a faite.
function Fenetre.etapeAvant(c, element)
    local elements = c and c.elements or {}
    for i = math.min(tonumber(element) or 0, #elements), 1, -1 do
        local e = elements[i]
        if Conversation.estEtape(e) and not Conversation.CLASSEMENTS[e.outil] then
            return i
        end
    end
    return nil
end

-- Ce que dit la carte devant l'image `image` (de Conversation.images) sans étape choisie : une
-- proposition (Fenetre.SANS_ETAPE_PROPOSITION), une photo jointe par Dany
-- (Fenetre.SANS_ETAPE_JOINTE), sinon une image de Claude qu'aucune étape ne précède
-- (Fenetre.SANS_ETAPE_IMAGE).
function Fenetre.texteSansEtape(c, image)
    local e = c and image and c.elements[image.element]
    local genre = type(e) == 'table' and e.genre or nil
    if genre == 'proposition' then
        return Fenetre.SANS_ETAPE_PROPOSITION
    elseif genre == 'dany' then
        return Fenetre.SANS_ETAPE_JOINTE
    end
    return Fenetre.SANS_ETAPE_IMAGE
end

-- La carte de l'onglet Aperçu devant l'image `indice` (Fenetre.images) : l'étape qui la précède dans
-- le fil (Fenetre.etapeAvant), sans la suivre (une étape nouvelle ne la remplace pas : la carte suit
-- les images) ; sans étape avant elle, aucune (la carte le dit, Fenetre.SANS_ETAPE_IMAGE). L'image
-- d'une proposition ou une photo jointe n'est faite par aucune étape (Fenetre.imageDeClaude) :
-- aucune non plus, jamais celle du tour d'avant (la carte dit ce qu'elle est,
-- Fenetre.texteSansEtape). Rend vrai si une étape est choisie.
function Fenetre.choisirEtapeDeLImage(c, indice)
    Fenetre.etape = nil
    local image = Fenetre.images and Fenetre.images[indice]
    if not Fenetre.imageDeClaude(c, image) then
        return false
    end
    local i = Fenetre.etapeAvant(c, image.element)
    if not i then
        return false
    end
    local e = c.elements[i]
    local photo = Fenetre.photoDeLEtape(e)
    local liste = Conversation.etapes(c, photo)
    local n = rangEtape(liste, e.id)
    if not n then
        return false
    end
    Fenetre.etape = { conversation = c, photo = photo, id = liste[n].id, element = e.id, vue = 'apres', suivre = false }
    return true
end

-- Vrai pour une image de Claude (view_photo, une comparaison, un rendu) : ni celle d'une proposition
-- (l'onglet Proposition la montre), ni une photo jointe par Dany.
function Fenetre.imageDeClaude(c, image)
    local e = c and image and c.elements[image.element]
    return type(e) == 'table' and e.genre ~= 'proposition' and e.genre ~= 'dany'
end

-- L'image `chemin` de la conversation montrée dans l'aperçu, quel que soit l'onglet (les images
-- relues : la sienne, sans bascule vers une image arrivée entre-temps) : elle y reste
-- (Fenetre.imageCliquee) jusqu'à un autre onglet, une image nouvelle, une autre conversation, une
-- autre photo active ou un clic sur une étape. Pour « Voir à 100 % » de la carte Note
-- (Fenetre.voirZoom), qui garde l'onglet Note. Rend l'indice de l'image, nil si elle n'est plus dans
-- la conversation (l'aperçu d'avant).
function Fenetre.montrerImageDuFil(chemin)
    local c = Moteur.courante
    Fenetre.images = c and Conversation.images(c) or {}
    Fenetre.apercuDe, Fenetre.nbImages = c, #Fenetre.images
    local indice
    for n, image in ipairs(Fenetre.images) do
        if image.chemin == chemin then
            indice = n
        end
    end
    if indice then
        Fenetre.indiceImage = indice
        Fenetre.voirActive = false
        Fenetre.imageCliquee = true
    end
    Fenetre.rafraichirApercu()
    return indice
end

-- Une image du fil dans l'onglet Aperçu (correctif 1.3.6, décisions de Dany du 25 octobre 2026) : un
-- clic sur sa ligne (un vrai clic : le crochet de l'onglet suit), ou une image de Claude qui arrive
-- (`auto` : une bascule de la fenêtre, Fenetre.rafraichirApercu). L'onglet change d'abord (il rend la
-- main à l'aperçu de l'onglet, Fenetre.ongletChange), puis l'aperçu montre l'image et la carte le
-- pourquoi de l'étape qui la précède (Fenetre.choisirEtapeDeLImage). Rend l'indice de l'image, nil
-- si elle n'est plus dans la conversation (rien ne change).
function Fenetre.voirImageDuFil(chemin, auto)
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    if not (p and T and c) then
        return nil
    end
    local images = Conversation.images(c)
    local indice
    for n, image in ipairs(images) do
        if image.chemin == chemin then
            indice = n
        end
    end
    if not indice then
        return nil
    end
    -- Les images à jour avant le changement d'onglet : son aperçu n'y voit pas une image nouvelle.
    Fenetre.images, Fenetre.apercuDe, Fenetre.nbImages = images, c, #images
    if auto then
        Fenetre.choisirOnglet(T.ongletEtape)
    elseif p.onglet ~= T.ongletEtape then
        p.onglet = T.ongletEtape
    end
    -- L'image de Claude arrivée est la dernière : l'aperçu suit les suivantes (indiceImage nil) ;
    -- une image cliquée est choisie.
    Fenetre.indiceImage = indice
    if auto and indice == #images then
        Fenetre.indiceImage = nil
    end
    Fenetre.voirActive, Fenetre.imageCliquee, Fenetre.imageProposition = false, true, nil
    Fenetre.choisirEtapeDeLImage(c, indice)
    Fenetre.rafraichirEtape()
    return indice
end

-- Un clic sur la ligne de l'image `chemin` quand c'est celle de la proposition qui attend l'accord
-- de Dany (Obtenir, preview_settings) : l'onglet Proposition, comme une proposition qui arrive, où
-- sont sa raison, Accepter, Refuser et Ajuster… ; son crochet (un vrai clic) remontre son image
-- (Fenetre.montrerImageProposition). Rend vrai si c'est elle ; faux sinon (une image de Claude, une
-- photo jointe, une proposition décidée ou close : Fenetre.voirImageDuFil).
function Fenetre.voirPropositionDuFil(chemin)
    local p, T, c = Fenetre.p, Fenetre.T, Moteur.courante
    local prop = c and Conversation.propositionEnAttente(c)
    if not (p and T and prop) then
        return false
    end
    for _, image in ipairs(Conversation.images(c)) do
        if image.chemin == chemin and c.elements[image.element] == prop then
            if p.onglet ~= T.ongletProposition then
                p.onglet = T.ongletProposition
            else
                Fenetre.montrerImageProposition()
            end
            return true
        end
    end
    return false
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

-- Vrai quand l'aperçu montre une étape : onglet Aperçu, une étape choisie, pas d'image du fil
-- montrée (prioritaire : cliquée, ou de Claude à son arrivée).
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
-- étape, l'aide. L'onglet ouvert sans étape choisie prend la dernière (mode suivre), sauf devant une
-- image du fil sans étape avant elle, l'image d'une proposition ou une photo jointe (la carte dit ce
-- qu'elle est : Fenetre.texteSansEtape).
function Fenetre.rafraichirEtape(sansApercu)
    local p, T = Fenetre.p, Fenetre.T
    if not p then
        return
    end
    Fenetre.versionEtapes = Etapes.version
    local devantImage = T ~= nil and p.onglet == T.ongletEtape and Fenetre.imageCliquee == true
    if not Fenetre.etape and T and p.onglet == T.ongletEtape and not devantImage then
        Fenetre.choisirDerniereEtape()
    end
    local x, n, liste = Fenetre.etapeCourante()
    if not x then
        poser(p, 'etapeTitre', Fenetre.TITRE_ETAPE)
        poser(p, 'etapeSousTitre', '')
        local images = Fenetre.images or {}
        Fenetre.montrerPage('etape', devantImage and Fenetre.texteSansEtape(Moteur.courante, images[Fenetre.indiceImage or #images])
            or Fenetre.AIDE_ETAPE)
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
    -- L'aperçu montre l'étape, plus l'image du fil devant laquelle la carte était.
    Fenetre.imageCliquee = nil
    Fenetre.rafraichirEtape()
end

-- Voir l'avant / Voir l'après : l'aperçu passe de l'un à l'autre (et montre l'étape, plus l'image du
-- fil devant laquelle la carte était).
function Fenetre.basculerEtape()
    local et = Fenetre.etape
    if not et then
        return
    end
    Fenetre.imageCliquee = nil
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
        Fenetre.agrandirUne("Claude · " .. titre .. " · " .. (noms.apres and "après" or "avant"), dossier, noms.apres or noms.avant)
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
-- d'image dans le fil d'avant le correctif 1.3.6, sans quitter l'onglet Note
-- (Fenetre.montrerImageDuFil) : il y reste jusqu'à un autre onglet, une image
-- nouvelle, une autre conversation ou une autre photo active, et Agrandir le montre en grand. Sans
-- nouvel appel à Claude, sans rien demander à Lightroom. Rend faux sans zoom (le bouton est alors
-- grisé).
function Fenetre.voirZoom()
    local zoom = Moteur.courante and Fenetre.zoomDeLaNote()
    if not zoom then
        return false
    end
    Fenetre.montrerImageDuFil(zoom.chemin)
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

-- Voyants -------------------------------------------------------------------------------------

-- Claude Code (commandes du système : dans une tâche) et la liaison avec le serveur, lue
-- directement dans ce module. Les deux voyants sont dans l'en-tête depuis le correctif 1.3.6 ; le
-- voyant Écran (l'étalonnage de l'écran, lu par `mcp-developpeur --ecran`) est retiré au même
-- correctif (décision de Dany du 25 octobre 2026 : il n'achètera pas de sonde), et la fenêtre ne
-- lance plus --ecran. Les versions du module et du connecteur, qui étaient en bas du volet, et le
-- mode de la liaison (la rangée Mode étant retirée) sont dans l'infobulle du voyant Lightroom
-- (Fenetre.infobulleLightroom), orange quand l'un des deux est à mettre à jour ou que le connecteur
-- est introuvable (ces lignes étaient en orange dans le volet).
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
        -- Les versions (celle du connecteur par sa réponse à --version, cinq secondes au plus) : à
        -- l'ouverture seulement, jamais toutes les 2 s.
        Fenetre.versions = Composants.lire()
    end
    local liaison, erreur = Lightroom.liaison()
    poser(p, 'texteLightroom', liaison == 'active' and "Lightroom"
        or (liaison == 'erreur' and "Lightroom · liaison en erreur" or "Lightroom · liaison arrêtée"))
    poser(p, 'etatLightroom', liaison == 'active' and (Fenetre.alerteVersions(Fenetre.versions) and 'attention' or 'ok') or 'erreur')
    -- Le mode se relit à chaque tour (la préférence du Gestionnaire, sans commande du système).
    poser(p, 'infobulleLightroom', Fenetre.infobulleLightroom(liaison, Fenetre.versions, Lightroom.mode()))
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
    Fenetre.rafraichirAide()
end

-- Clic sur le voyant Lightroom : démarre la liaison si elle est arrêtée (ou la relance après une
-- erreur), puis le voyant se relit.
function Fenetre.demarrerLiaison()
    Lightroom.demarrerLiaison()
    Fenetre.verifier(false)
end

-- Une ligne de version en un texte (Composants.lignes) : « Développeur 1.3 », « MCP-Développeur 1.2 ·
-- à mettre à jour » (l'alerte après le numéro), « MCP-Développeur · introuvable ».
function Fenetre.texteVersion(l)
    local nom, version = tostring(l.nom or ''), tostring(l.version or '')
    local base, suite = nom:match('^(.-)( · .*)$')
    base, suite = base or nom, suite or ''
    return base .. (version ~= '' and (' ' .. version) or '') .. suite
end

-- Vrai quand une des versions (Composants.lignes) est en alerte : à mettre à jour, introuvable.
function Fenetre.alerteVersions(lignes)
    for _, l in ipairs(type(lignes) == 'table' and lignes or {}) do
        if l.alerte == true then
            return true
        end
    end
    return false
end

-- Le mode de la liaison (Lightroom.mode).
Fenetre.MODES = { appliquer = "Appliquer", proposer = "Proposer d'abord" }

-- L'infobulle du voyant Lightroom : la liaison (et ce que fait un clic), les deux versions
-- (Composants.lignes : « … » tant que le connecteur n'a pas répondu), puis le mode de la liaison,
-- qui se règle dans le Gestionnaire de modules externes. Une seule ligne de texte : une infobulle
-- sur plusieurs lignes n'est pas constatée.
function Fenetre.infobulleLightroom(liaison, lignes, mode)
    local etat = liaison == 'active' and "active"
        or (liaison == 'erreur' and "en erreur, un clic la relance" or "arrêtée, un clic la démarre")
    local versions = {}
    for _, l in ipairs(type(lignes) == 'table' and lignes or {}) do
        versions[#versions + 1] = Fenetre.texteVersion(l)
    end
    return string.format("Liaison avec le connecteur MCP-Développeur : %s. Versions : %s. Mode de la liaison : %s "
        .. "(Gestionnaire de modules externes).", etat, #versions > 0 and table.concat(versions, " ; ") or "?",
        Fenetre.MODES[mode] or Fenetre.MODES.appliquer)
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

-- La photo active et la sélection (gardées pour la carte Note). (La photo d'une ancienne
-- conversation choisie dans la liste, Fenetre.photoDeLaConversation, est retirée avec la liste au
-- correctif 1.3.6 : les onglets montrent toujours la photo active de Lightroom.)
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
        -- L'onglet Focus montre la mise au point de la photo active.
        Fenetre.rafraichirFocus()
    end
    if info.active then
        p.infoPhoto = string.format("Active : <EM>%s</EM> · Sélection : <EM>%d</EM>", Fenetre.nomPhoto(legendeActive(info.active)),
            info.selection)
        -- Une note acceptée ou changée qui n'est plus sur la photo (undo_last, ⌘Z) : la proposition
        -- redevient à décider.
        local active = info.active
        LrTasks.pcall(Notation.recaler, { { photo = active.id, note = active.note, drapeau = active.drapeau } }, version)
    else
        p.infoPhoto = "Aucune photo active"
    end
    Fenetre.suivreSelection(info)
    Fenetre.poserRepartir()
    Fenetre.poserObtenir()
    Fenetre.rafraichirNotation()
end

-- Une autre photo active ou une autre sélection, choisie par l'utilisateur, montre sa conversation
-- (préférence `nouvelleParPhoto`, case « Autre photo : reprendre sa conversation, sinon une
-- nouvelle » du Gestionnaire ; d'abord une nouvelle conversation à chaque photo, demandé par Dany le
-- 20 octobre 2026 ; une photo, une conversation depuis le correctif 1.3.6, Fenetre.suivrePhotos) ;
-- décochée, la conversation montrée reste, quelle que soit la sélection. La première sélection vue
-- (à la première ouverture de la fenêtre) montre aussi la sienne. Une sélection changée pendant que
-- Claude travaille (show_photo, tri), ou qui l'était encore DELAI_APRES_TRAVAIL secondes avant la
-- fin de son travail, peut être la sienne : rien ne change, elle devient la clé de la conversation
-- montrée. `Fenetre.cleVue` et l'heure où elle a été vue (`cleVueLe`) restent d'une ouverture de la
-- fenêtre à l'autre : une photo choisie fenêtre fermée compte aussi, et une fenêtre fermée pendant le
-- travail de Claude retrouve sa conversation à la réouverture. Une demande rapide faite hors de la
-- conversation montrée (Moteur.selectionRapide) ne compte pas comme un travail de Claude dans
-- celle-ci : sa sélection se suit après son travail, même juste après (une photo choisie puis un
-- bouton de la Demande rapide cliqué avant que la fenêtre l'ait vue).
Fenetre.DELAI_APRES_TRAVAIL = 4

function Fenetre.voirSelection(cle)
    Fenetre.cleVue, Fenetre.cleVueLe = cle, os.time()
end

function Fenetre.suivreSelection(info)
    local cle = info and info.cle
    if not cle then
        return
    end
    local c = Moteur.courante
    -- La Demande rapide travaille hors de la conversation montrée (Moteur.envoyerRapide) : la
    -- sélection n'est pas celle de cette conversation ; la fenêtre la regarde après le travail.
    if Moteur.travaille and Moteur.tourRapide ~= nil and Moteur.tourRapide ~= c then
        return
    end
    local avant, vueLe = Fenetre.cleVue, Fenetre.cleVueLe
    Fenetre.voirSelection(cle)
    if avant == cle then
        return
    end
    -- Après une demande rapide hors de la conversation montrée (une photo choisie juste avant de
    -- l'envoyer, ou montrée par Claude pendant qu'il y travaillait), la sélection se suit comme un
    -- choix de Dany : elle ne vient pas d'un travail dans cette conversation.
    local rapide = Moteur.selectionRapide
    local apresRapide = not Moteur.travaille and rapide ~= nil and rapide.conversation ~= c
    if apresRapide then
        Moteur.selectionRapide = nil
    end
    -- Claude travaille, ou a travaillé depuis que la sélection d'avant a été vue (la première vue
    -- n'en a pas d'avant : seul son travail en cours compte).
    local fin = Moteur.finTravail or 0
    if Moteur.travaille or (not apresRapide and avant ~= nil and fin > 0 and (not vueLe or fin + Fenetre.DELAI_APRES_TRAVAIL > vueLe)) then
        if c then
            c.cle = cle
        end
        return
    end
    if not Chemins.prefs().nouvelleParPhoto then
        return
    end
    -- Claude s'est mis au travail pendant que la fenêtre préparait la conversation (une demande
    -- rapide réservée pendant les lectures du catalogue) : la sélection n'est pas encore suivie, elle
    -- le sera après son travail. Une autre conversation montrée (Dany a choisi une autre photo, ou
    -- d'autres photos) ramène l'onglet Focus (décision de Dany du 25 octobre 2026).
    if not Fenetre.suivrePhotos(info) then
        Fenetre.cleVue, Fenetre.cleVueLe = avant, vueLe
    elseif Moteur.courante ~= c then
        Fenetre.revenirAFocus()
    end
end

-- Tout ce qui dépend du moteur.
function Fenetre.rafraichir()
    local p = Fenetre.p
    if not p then
        return
    end
    local c = Moteur.courante
    poser(p, 'titre', sansBalises(c and c.titre or Conversation.TITRE_PAR_DEFAUT))
    poser(p, 'libre', not Moteur.travaille)
    poser(p, 'travaille', Moteur.travaille)
    Fenetre.poserRepartir()
    poser(p, 'forfait', Moteur.texteForfait())
    Fenetre.rafraichirFil()
    -- La carte de l'étape (une nouvelle étape en mode suivre, une autre conversation), avant
    -- l'aperçu, qui en dépend dans son onglet.
    Fenetre.rafraichirEtape(true)
    Fenetre.rafraichirApercu()
    Fenetre.rafraichirProposition()
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

-- « Obtenir », sous la carte de l'onglet Proposition (décision de Dany du 25 octobre 2026 : plus de
-- proposition préparée à l'ouverture de la fenêtre, ni de préférence `propositionAOuverture`, qui
-- reste ignorée dans les réglages de Lightroom) : Claude prépare une proposition de retouche de la
-- photo seule active, dans sa conversation (celle d'« une photo, une conversation » : la montrée si
-- c'est la sienne, sinon la gardée, sinon une neuve avec son historique, gardée dès cette demande,
-- Fenetre.suivrePhotos), sans rien appliquer (Consignes.obtenir : la demande complète part à Claude,
-- le fil n'en montre qu'une phrase courte). La proposition qui arrive se montre dans l'onglet
-- Proposition, comme les autres. Grisé pendant que Claude travaille (fenêtre ou Demande rapide :
-- Moteur.travaille), sans photo seule (plusieurs photos sélectionnées, ou aucune) et quand une
-- proposition attend déjà, dans la conversation montrée ou dans celle de la photo (`peutObtenir`).
-- À appeler depuis une tâche.
Fenetre.OBTENIR_SANS_PHOTO = "Obtenir : choisissez une seule photo dans Lightroom."
Fenetre.OBTENIR_EN_ATTENTE = "Une proposition attend déjà : acceptez-la, refusez-la ou ajustez-la."

function Fenetre.peutObtenir(info)
    if Moteur.travaille or type(info) ~= 'table' or info.active == nil or (info.selection or 0) > 1 then
        return false
    end
    local c = Moteur.courante
    if c and Conversation.propositionEnAttente(c) then
        return false
    end
    local gardee = Moteur.conversationDe(info.active.id)
    return not (gardee and Conversation.propositionEnAttente(gardee))
end

function Fenetre.poserObtenir()
    if Fenetre.p then
        poser(Fenetre.p, 'peutObtenir', Fenetre.peutObtenir(Fenetre.info))
    end
end

function Fenetre.obtenir()
    local p = Fenetre.p
    if not p then
        return false
    end
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        return false
    end
    local info = Lightroom.photos()
    Fenetre.info = info
    if not Fenetre.peutObtenir(info) then
        local seule = info.active ~= nil and (info.selection or 0) <= 1
        p.message = Moteur.travaille and Fenetre.CLAUDE_TRAVAILLE or (seule and Fenetre.OBTENIR_EN_ATTENTE or Fenetre.OBTENIR_SANS_PHOTO)
        Fenetre.poserObtenir()
        return false
    end
    -- La conversation de la photo ; Claude s'est peut-être mis au travail entre-temps (une demande
    -- rapide : Moteur.montrer refuse, et le dit au bandeau).
    if not Fenetre.suivrePhotos(info) then
        Fenetre.poserObtenir()
        return false
    end
    if Moteur.travaille then
        p.message = Fenetre.CLAUDE_TRAVAILLE
        Fenetre.poserObtenir()
        return false
    end
    Fenetre.voirSelection(info.cle)
    -- Grisé dès le clic : un second clic avant le départ de la demande n'en envoie pas une autre.
    poser(p, 'peutObtenir', false)
    Fenetre.envoyer(Consignes.obtenir.demande, nil, Consignes.obtenir.fil)
    return true
end

-- `affiche` : ce que le fil montre de la demande, si Claude en reçoit une plus longue (Obtenir).
function Fenetre.envoyer(texte, modele, affiche)
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
    -- Une demande se suit dans le fil, depuis son bas.
    Fenetre.defilement = 0
    LrTasks.startAsyncTask(function()
        -- La photo active et la sélection de la demande : la conversation est la leur.
        local info = Lightroom.photos()
        local c = Moteur.courante
        if c and not Moteur.travaille then
            -- Une conversation neuve sans photo (case Autre photo décochée) devient celle de la photo
            -- seule de sa première demande, avec son historique.
            if c.photo == nil and c.groupe == nil and not Conversation.commencee(c) and info.active and (info.selection or 0) <= 1 then
                LrTasks.pcall(Fenetre.preparerPhoto, c, info.active.id, info.cle)
            end
            -- La photo retouchée depuis que la conversation l'a vue (à la main, entre deux demandes) :
            -- le complément part avec cette demande.
            LrTasks.pcall(Fenetre.completerDepuis, c)
        end
        -- Le modèle et l'effort des préférences (Gestionnaire de modules externes), sauf le modèle
        -- d'une invite qui en impose un.
        local ok, raison = Moteur.envoyer(texte, { modele = modele, jointes = jointes, style = p.style, affiche = affiche })
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

-- (Renommer… et Supprimer… de la conversation montrée sont retirés avec le volet au correctif
-- 1.3.6, comme Moteur.renommer et Moteur.supprimer : le titre est celui que Claude donne.)

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

-- (Publication… et Consommation…, dans le volet, sont retirés avec lui au correctif 1.3.6 : elles
-- restent au menu Module externe - Extras, MenuPublication.lua et MenuConsommation.lua.)

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
-- sous 3 ; 5 : 1 623 × 1 200, sans le volet de gauche (correctif 1.3.6), qui ne doit pas garder la
-- largeur enregistrée sous 4.
Fenetre.FORME = 5

function Fenetre.cadre()
    return 'DeveloppeurClaude-' .. Dispositions.NOM .. '-grande-' .. Fenetre.FORME
end

-- Le titre de la fenêtre : « Développeur v1.3.6 », avec la version de ce module (Composants.module,
-- son Info.lua ; décision de Dany du 25 octobre 2026, correctif 1.3.6 : « Développeur » seul depuis
-- le 20 octobre 2026) ; « Développeur » seul si la version ne se lit pas.
function Fenetre.titreFenetre()
    local version = Composants.module()
    if type(version) ~= 'string' or not version:match('^%d') then
        return "Développeur"
    end
    return "Développeur v" .. version
end

function Fenetre.desabonner()
    Moteur.desabonner('fenetre')
    Notation.desabonner('fenetre')
end

-- Boucle d'une fenêtre (sa génération : une fenêtre rouverte a la sienne, l'ancienne boucle
-- s'arrête) : rafraîchit ce que le moteur a changé, la note, l'activité, et les voyants.
-- Toutes les 2 s : les voyants et la photo active (la liaison, lue dans ce module sans commande
-- du système, peut démarrer ou s'arrêter par le menu). Claude Code et les versions, lus par des
-- commandes du système, ne se relisent qu'à l'ouverture.
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
-- carte de l'étape, vide et ses boutons inactifs.
local function initialiserEtape(p)
    p.etapeTitre = Fenetre.TITRE_ETAPE
    p.etapeSousTitre = ''
    p.etapeTexte = ''
    p.etapePrecedente = false
    p.etapeSuivante = false
    p.etapeAImages = false
    p.etapeADetail = false
    p.titreBascule = "Voir l'avant"
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
                LrTasks.pcall(Fenetre.revoirPhoto)
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
        Fenetre.defilement = 0
        Fenetre.indiceImage = nil
        Fenetre.imageCliquee = nil
        -- Les images comptées à la fermeture : celles arrivées fenêtre fermée ne sont pas des images
        -- nouvelles (la fenêtre s'ouvre sur Focus, l'aperçu sur la photo active).
        Fenetre.apercuDe, Fenetre.nbImages = nil, nil
        -- L'image de proposition demandée par un clic sur l'onglet (Composition lue) : à redemander.
        Fenetre.imageProposition = nil
        -- À l'ouverture, l'aperçu montre la photo active, refait (Fenetre.majPhoto) ; l'onglet Focus
        -- se relira (la vignette d'une ouverture passée s'efface).
        Fenetre.idActif, Fenetre.apercuActif, Fenetre.demandeActive, Fenetre.voirActive = nil, nil, nil, true
        if Fenetre.focus and Fenetre.focus.dossier then
            Fichiers.supprimer(Fenetre.focus.dossier)
        end
        Fenetre.focus, Fenetre.lectureFocus = nil, nil
        -- La fenêtre s'ouvre sur Focus (décision de Dany du 25 octobre 2026) : une proposition qui
        -- attendait déjà n'est pas une arrivée, l'onglet Proposition la montre au clic.
        local attend = Moteur.courante and Conversation.propositionEnAttente(Moteur.courante)
        Fenetre.propositionVue = attend and attend.id or nil
        Fenetre.info = nil
        Fenetre.noteVue, Fenetre.notePhoto = nil, nil
        Fenetre.noteEnCours = false
        -- Aucune étape choisie (onglet Aperçu) ; ses images se relisent, les copies d'avant
        -- s'effacent.
        Fenetre.etape, Fenetre.imagesEtapes, Fenetre.demandesEtapes, Fenetre.versionEtapes = nil, {}, {}, nil
        Fichiers.supprimer(Fenetre.dossierPourquoi())

        local f = LrView.osFactory()
        local p = LrBinding.makePropertyTable(context)
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
        -- Focus à l'ouverture (D.ongletParDefaut), le premier segment (décision de Dany du 25 octobre
        -- 2026) : la photo active s'y lit (Fenetre.majPhoto).
        p.onglet = D.ongletParDefaut
        p.libre = not Moteur.travaille
        p.travaille = Moteur.travaille
        -- « Repartir à neuf » et « Obtenir » (onglet Proposition) : actifs une fois la photo active
        -- lue (Fenetre.majPhoto).
        p.peutRepartir = false
        p.peutObtenir = false
        p.forfait = Moteur.texteForfait()
        p.texteClaude = "Claude Code"
        p.etatClaude = 'neutre'
        p.texteLightroom = "Lightroom"
        p.etatLightroom = 'neutre'
        -- Les versions et le mode de la liaison, dans l'infobulle du voyant Lightroom ; celle du
        -- connecteur se lit à l'ouverture (Fenetre.verifier).
        Fenetre.versions = Composants.lignes(Composants.module(), '…')
        p.infobulleLightroom = Fenetre.infobulleLightroom(Lightroom.liaison(), Fenetre.versions, Lightroom.mode())
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
        p.activite = Moteur.texteTravail(0)
        for i = 1, D.lignes do
            p['t' .. i] = ''
            p['g' .. i] = 'vide'
            p['i' .. i] = ''
            p['a' .. i] = ''
            p['h' .. i] = ''
            p['x' .. i] = ''
        end
        -- La carte de l'onglet Focus (Fenetre.rafraichirFocus la remplit).
        p.focusTitre = "Focus"
        p.focusTexte = ''
        initialiserNotation(p, D)
        initialiserEtape(p)
        Fenetre.p = p

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
        LrTasks.pcall(Fenetre.revoirPhoto)
        -- La conversation de la photo choisie (Fenetre.suivreSelection) se montre dès l'ouverture.
        if Fenetre.aRafraichir then
            Fenetre.aRafraichir = false
            Fenetre.rafraichir()
        end
        Moteur.abonner('fenetre', function() Fenetre.aRafraichir = true end)
        Notation.abonner('fenetre', function() Fenetre.aRafraichirNotation = true end)

        LrTasks.startAsyncTask(function() Fenetre.boucle(generation) end)
        LrTasks.startAsyncTask(function() LrTasks.pcall(Fenetre.verifier, true) end)

        LrDialogs.presentFloatingDialog(_PLUGIN, {
            -- « Développeur v1.3.6 » (Fenetre.titreFenetre) ; les autres fenêtres du module gardent
            -- « Claude · … », la Demande rapide le sien.
            title = Fenetre.titreFenetre(),
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
