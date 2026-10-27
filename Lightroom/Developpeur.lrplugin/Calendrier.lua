-- Calendrier.lua : le calendrier des champs « Du » et « au » de la fenêtre Suivi (correctif 1.3.8,
-- demandé par Dany le 26 octobre 2026 : « un calendrier fait dans le module » ; pas celui de macOS,
-- qui s'ouvrirait derrière Lightroom, ni trois menus Jour, Mois et Année). Lightroom ne prête pas son
-- calendrier aux modules (date_picker existe dans sa fabrique interne, AgViewCocoaFactory, mais la
-- liste des contrôles de LrView.osFactory ne l'a pas : relevé en lecture seule dans LrView.lua de
-- Lightroom Classic 15.6) : il est fait ici, de vues simples, dans une petite fenêtre modale.
--
--   - en haut : ◀, le mois et l'année (deux menus), ▶ ;
--   - la grille du mois : les jours de la semaine, du lundi au dimanche, puis six semaines de sept
--     cases ; aujourd'hui en orange, le jour choisi sur un aplat bleu, en blanc ;
--   - un clic sur un jour le choisit et ferme le calendrier (LrDialogs.stopModalWithResult, à
--     constater dans Lightroom ; s'il ne la fermait pas, le jour reste choisi et « Choisir » le
--     prend) ;
--   - les boutons : « Choisir », « Annuler », et un troisième selon le champ : « Première photo »
--     pour « Du » (depuis la première photo), « Aujourd'hui » pour « au » (la fin qui avance chaque
--     jour ; un clic sur le jour d'aujourd'hui, lui, garde cette date).
--
-- Taper la date dans le champ reste possible. Le calendrier ne garde rien : FenetreSuivi reçoit le
-- choix (Calendrier.ouvrir) et le garde comme une date tapée (FenetreSuivi.changerDate). Ses calculs
-- (jours d'un mois, premier jour de la semaine, grille, mois voisins, années du menu) sont purs ; la
-- fenêtre suit les règles de la fenêtre B : structure fixe à la création, ce qui varie par des
-- propriétés liées, fonds en aplats (f:picture sans image), clics par des calques (un static_text
-- vide : un f:picture ne reçoit aucun clic, constaté C1), tables neuves vers Lightroom.

local Carnet = require 'Carnet'
local Dispositions = require 'Dispositions'
local Metriques = require 'Metriques'

local Calendrier = {}

-- Les jours de la semaine, du lundi au dimanche (la semaine commence le lundi, comme au Canada
-- français et en France), et les six semaines de la grille (un mois en touche au plus six).
Calendrier.JOURS = { "lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim." }
Calendrier.SEMAINES = 6
Calendrier.CASES = 7 * Calendrier.SEMAINES

-- La première année du menu (une photo plus ancienne se tape dans le champ) ; la dernière est
-- l'année prochaine. Les bornes des dates, comme FenetreSuivi.lireDate et le connecteur : ◀ et ▶
-- ne vont pas au-delà (un jour hors d'elles serait refusé comme une date qui ne se lit pas).
Calendrier.ANNEE_MIN = 1950
Calendrier.ANNEE_PREMIERE, Calendrier.ANNEE_DERNIERE = 1900, 9999

-- Les textes.
Calendrier.TITRE_DEBUT = "Début de la période"
Calendrier.TITRE_FIN = "Fin de la période"
Calendrier.CHOISIR = "Choisir"
Calendrier.PREMIERE_PHOTO = "Première photo"
Calendrier.AUJOURDHUI = "Aujourd'hui"
Calendrier.AIDE_DEBUT = "Un clic sur un jour le choisit. « Première photo » : depuis votre première photo."
Calendrier.AIDE_FIN = "Un clic sur un jour le choisit. « Aujourd'hui » : la fin avance chaque jour."
Calendrier.AUCUN = "Aucun jour choisi."
Calendrier.CHOISI = "Choisi : %s"
Calendrier.INFOBULLE_PRECEDENT = "Le mois précédent"
Calendrier.INFOBULLE_SUIVANT = "Le mois suivant"

-- Les tailles, en points : une case, l'écart entre les rangées, les menus, les flèches.
-- La rangée du haut tient dans la grille (◀ 34, mois 104, 6, année 80, ▶ 34 : 258 pour 266).
Calendrier.TAILLES = { case = 38, hauteurCase = 26, entete = 18, marge = 16, ecart = 8, mois = 104, annee = 80, fleche = 34,
    texte = 18, aide = 30 }

-- Calculs (purs) ---------------------------------------------------------------------------------

-- Le nombre de jours d'un mois (la seule copie : FenetreSuivi s'en sert aussi).
function Calendrier.joursDuMois(annee, mois)
    if mois == 2 then
        return (annee % 4 == 0 and (annee % 100 ~= 0 or annee % 400 == 0)) and 29 or 28
    end
    return (mois == 4 or mois == 6 or mois == 9 or mois == 11) and 30 or 31
end

-- Le jour de la semaine d'une date : 1 le lundi … 7 le dimanche (méthode de Sakamoto, calendrier
-- grégorien).
function Calendrier.jourDeLaSemaine(annee, mois, jour)
    local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
    local a = mois < 3 and annee - 1 or annee
    local d = (a + math.floor(a / 4) - math.floor(a / 100) + math.floor(a / 400) + t[mois] + jour) % 7
    return d == 0 and 7 or d
end

-- La grille d'un mois : Calendrier.CASES cases, du lundi de la première semaine au dimanche de la
-- sixième ; le numéro du jour dans les cases du mois, nil dans les autres. Une table neuve.
function Calendrier.grille(annee, mois)
    local cases = {}
    local decalage = Calendrier.jourDeLaSemaine(annee, mois, 1) - 1
    for j = 1, Calendrier.joursDuMois(annee, mois) do
        cases[decalage + j] = j
    end
    return cases, decalage
end

-- Le mois `n` mois plus loin (négatif : plus tôt) : l'année et le mois.
function Calendrier.decaler(annee, mois, n)
    local rang = annee * 12 + (mois - 1) + n
    return math.floor(rang / 12), rang % 12 + 1
end

-- Les années du menu, de la plus récente à la plus ancienne : de l'année prochaine à
-- Calendrier.ANNEE_MIN, et l'année `montree` si elle en sort (une date tapée plus ancienne), entre
-- ANNEE_PREMIERE et ANNEE_DERNIERE. Une table neuve d'éléments { title, value }.
function Calendrier.annees(anneeCourante, montree)
    local haut = math.min(Calendrier.ANNEE_DERNIERE, math.max(anneeCourante + 1, montree or anneeCourante))
    local bas = math.max(Calendrier.ANNEE_PREMIERE, math.min(Calendrier.ANNEE_MIN, montree or Calendrier.ANNEE_MIN))
    local items = {}
    for a = haut, bas, -1 do
        items[#items + 1] = { title = tostring(a), value = a }
    end
    return items
end

-- Les mois du menu (Carnet.MOIS, seule copie des noms des mois). Une table neuve.
function Calendrier.mois()
    local items = {}
    for m, nom in ipairs(Carnet.MOIS) do
        items[m] = { title = nom, value = m }
    end
    return items
end

-- Une date { annee, mois, jour } en français (« 25 janvier 2025 », « 1er mars 2026 »).
function Calendrier.texte(d)
    return (d.jour == 1 and '1er' or tostring(d.jour)) .. ' ' .. Carnet.MOIS[d.mois] .. ' ' .. d.annee
end

local function memeJour(a, b)
    return a ~= nil and b ~= nil and a.annee == b.annee and a.mois == b.mois and a.jour == b.jour
end

-- Ce que montre chaque case du mois `annee`, `mois` : { jour (texte, '' hors du mois), etat ('vide',
-- 'jour', 'aujourdhui', 'choisi') } ; `choisi` et `aujourdhui` : des dates, ou nil. Une table neuve.
function Calendrier.cases(annee, mois, choisi, aujourdhui)
    local grille = Calendrier.grille(annee, mois)
    local r = {}
    for i = 1, Calendrier.CASES do
        local j = grille[i]
        local etat = 'vide'
        if j then
            local d = { annee = annee, mois = mois, jour = j }
            etat = memeJour(d, choisi) and 'choisi' or memeJour(d, aujourdhui) and 'aujourdhui' or 'jour'
        end
        r[i] = { jour = j and tostring(j) or '', etat = etat }
    end
    return r
end

-- La fenêtre ------------------------------------------------------------------------------------

-- Les clés liées d'une case : son jour (texte) et son état.
function Calendrier.cles(i)
    return 'j' .. i, 'e' .. i
end

-- Les mouse_down des calques (les essais vérifient que les cases y passent).
local parCalque = setmetatable({}, { __mode = 'k' })

function Calendrier.parCalque(fn)
    return parCalque[fn] == true
end

-- Pose dans `q` le mois montré (q.annee, q.mois) : chaque case, le texte du choix et « Choisir ».
function Calendrier.poserMois(q)
    local annee, mois = tonumber(q.annee), tonumber(q.mois)
    if not annee or not mois then
        return
    end
    local choisi = q.choisiAnnee and { annee = q.choisiAnnee, mois = q.choisiMois, jour = q.choisiJour } or nil
    for i, c in ipairs(Calendrier.cases(annee, mois, choisi, Calendrier.aujourdhuiDe(q))) do
        local cleJour, cleEtat = Calendrier.cles(i)
        if q[cleJour] ~= c.jour then
            q[cleJour] = c.jour
        end
        if q[cleEtat] ~= c.etat then
            q[cleEtat] = c.etat
        end
    end
    q.texteChoisi = choisi and string.format(Calendrier.CHOISI, Calendrier.texte(choisi)) or Calendrier.AUCUN
    q.peutChoisir = choisi ~= nil
end

-- Le jour d'aujourd'hui gardé dans `q` (une table neuve), nil sans lui.
function Calendrier.aujourdhuiDe(q)
    if not q.aujourdhuiAnnee then
        return nil
    end
    return { annee = q.aujourdhuiAnnee, mois = q.aujourdhuiMois, jour = q.aujourdhuiJour }
end

-- ◀ ou ▶ : le mois voisin (le menu des années s'étend si besoin), jamais hors de ANNEE_PREMIERE à
-- ANNEE_DERNIERE. Rend vrai si le mois change.
function Calendrier.changerMois(q, n)
    local a, m = Calendrier.decaler(tonumber(q.annee), tonumber(q.mois), n)
    if a < Calendrier.ANNEE_PREMIERE or a > Calendrier.ANNEE_DERNIERE then
        return false
    end
    q.elementsAnnees = Calendrier.annees(q.aujourdhuiAnnee or a, a)
    q.annee, q.mois = a, m
    Calendrier.poserMois(q)
    return true
end

-- Un clic sur la case `i` : son jour devient le choix, et la fenêtre se ferme sur lui (`fermer`,
-- LrDialogs.stopModalWithResult ; s'il ne la ferme pas, « Choisir » le prend). Rend vrai si un jour
-- est choisi (une case hors du mois ne fait rien).
function Calendrier.cliquer(q, i, fermer)
    local j = Calendrier.grille(tonumber(q.annee), tonumber(q.mois))[i]
    if not j then
        return false
    end
    q.choisiAnnee, q.choisiMois, q.choisiJour = tonumber(q.annee), tonumber(q.mois), j
    Calendrier.poserMois(q)
    if fermer then
        pcall(fermer)
    end
    return true
end

-- Le contenu de la fenêtre, pour la table liée `q` (Calendrier.preparer). `C` : les couleurs de
-- l'apparence (LrColor), `P` : les polices ; `fermer` : ce qu'un clic sur un jour appelle pour
-- fermer la fenêtre.
function Calendrier.construire(f, q, C, P, aide, fermer)
    local T = Calendrier.TAILLES
    local bind = (import 'LrView').bind
    local largeur = 7 * T.case
    local function egal(cle, valeur)
        return bind { key = cle, transform = function(v) return v == valeur end }
    end
    local function texte(args)
        return f:static_text(args)
    end
    local enteteSemaine = { spacing = 0 }
    for _, nom in ipairs(Calendrier.JOURS) do
        enteteSemaine[#enteteSemaine + 1] = texte { title = nom, font = P.petit, text_color = C.gris, alignment = 'center', width = T.case,
            height = T.entete }
    end
    local semaines = { spacing = 0, f:row(enteteSemaine) }
    for s = 1, Calendrier.SEMAINES do
        local rangee = { spacing = 0 }
        for d = 1, 7 do
            local i = (s - 1) * 7 + d
            local cleJour, cleEtat = Calendrier.cles(i)
            local clic = function() Calendrier.cliquer(q, i, fermer) end
            parCalque[clic] = true
            rangee[#rangee + 1] = f:view {
                place = 'overlapping',
                width = T.case,
                height = T.hauteurCase,
                f:column { margin_left = 3, margin_top = 1,
                    f:picture { width = T.case - 6, height = T.hauteurCase - 2, background_color = C.bleuBouton, visible = egal(cleEtat, 'choisi') } },
                texte { title = bind(cleJour), font = P.texte12, text_color = C.texte, alignment = 'center', width = T.case, place_vertical = 0.5,
                    visible = egal(cleEtat, 'jour') },
                texte { title = bind(cleJour), font = P.gras12, text_color = C.orange, alignment = 'center', width = T.case,
                    place_vertical = 0.5, visible = egal(cleEtat, 'aujourdhui') },
                texte { title = bind(cleJour), font = P.gras12, text_color = C.blanc, alignment = 'center', width = T.case, place_vertical = 0.5,
                    visible = egal(cleEtat, 'choisi') },
                texte { title = '', width = T.case, height = T.hauteurCase, mouse_down = clic,
                    visible = bind { key = cleEtat, transform = function(v) return v ~= 'vide' end } },
            }
        end
        semaines[#semaines + 1] = f:row(rangee)
    end
    local hauteur = T.marge + T.hauteurCase + T.ecart + T.entete + Calendrier.SEMAINES * T.hauteurCase + T.ecart + T.texte + T.aide + T.marge
    local largeurContenu = largeur + 2 * T.marge
    return f:view {
        bind_to_object = q,
        place = 'overlapping',
        width = largeurContenu,
        height = hauteur,
        f:picture { width = largeurContenu, height = hauteur, background_color = C.fondDroite },
        f:column {
            margin_left = T.marge,
            margin_top = T.marge,
            spacing = 0,
            f:row {
                spacing = 0,
                width = largeur,
                f:push_button { title = "◀", width = T.fleche, place_vertical = 0.5, tooltip = Calendrier.INFOBULLE_PRECEDENT,
                    action = function() Calendrier.changerMois(q, -1) end },
                f:spacer { fill_horizontal = 1 },
                f:popup_menu { items = Calendrier.mois(), value = bind 'mois', width = T.mois, place_vertical = 0.5 },
                f:spacer { width = 6 },
                f:popup_menu { items = bind 'elementsAnnees', value = bind 'annee', width = T.annee, place_vertical = 0.5 },
                f:spacer { fill_horizontal = 1 },
                f:push_button { title = "▶", width = T.fleche, place_vertical = 0.5, tooltip = Calendrier.INFOBULLE_SUIVANT,
                    action = function() Calendrier.changerMois(q, 1) end },
            },
            f:spacer { height = T.ecart },
            f:column(semaines),
            f:spacer { height = T.ecart },
            texte { title = bind 'texteChoisi', font = P.gras12, text_color = C.texte, width = largeur, height = T.texte },
            texte { title = aide, font = P.petit, text_color = C.gris, width = largeur, height = T.aide, height_in_lines = 2 },
        },
    }
end

-- Prépare la table liée : le mois montré (celui de `choisi`, sinon `montre`), le jour choisi (nil :
-- aucun), aujourd'hui, les menus.
function Calendrier.preparer(q, choisi, montre, aujourdhui)
    montre = choisi or montre or aujourdhui
    q.aujourdhuiAnnee, q.aujourdhuiMois, q.aujourdhuiJour = aujourdhui.annee, aujourdhui.mois, aujourdhui.jour
    q.choisiAnnee = choisi and choisi.annee or nil
    q.choisiMois = choisi and choisi.mois or nil
    q.choisiJour = choisi and choisi.jour or nil
    q.elementsAnnees = Calendrier.annees(aujourdhui.annee, montre.annee)
    q.annee, q.mois = montre.annee, montre.mois
    for i = 1, Calendrier.CASES do
        local cleJour, cleEtat = Calendrier.cles(i)
        q[cleJour], q[cleEtat] = '', 'vide'
    end
    q.texteChoisi, q.peutChoisir = Calendrier.AUCUN, false
    Calendrier.poserMois(q)
end

-- Les polices mesurées (Metriques.lua).
local function police(cle)
    local m = Metriques[cle]
    return { name = m.nom, size = m.taille }
end

-- Ouvre le calendrier (depuis une tâche) pour la borne 'debut' ou 'fin' : `choisi`, le jour déjà
-- choisi (nil : aucun) ; `montre`, le mois à montrer sans lui ; `aujourdhui`, le jour présent ;
-- `apparence`, celle du module. Rend { date = { annee, mois, jour } } (un jour choisi), { autre =
-- true } (« Première photo » ou « Aujourd'hui »), ou nil (annulé).
function Calendrier.ouvrir(borne, choisi, montre, aujourdhui, apparence)
    local LrBinding = import 'LrBinding'
    local LrColor = import 'LrColor'
    local LrDialogs = import 'LrDialogs'
    local LrFunctionContext = import 'LrFunctionContext'
    local LrView = import 'LrView'
    local C = {}
    for cle, t in pairs(Dispositions.couleurs(apparence)) do
        C[cle] = LrColor(t[1], t[2], t[3])
    end
    local P = { texte12 = police('texte12'), gras12 = police('gras12'), petit = police('petit') }
    local resultat
    LrFunctionContext.callWithContext('Claude · calendrier', function(context)
        local f = LrView.osFactory()
        local q = LrBinding.makePropertyTable(context)
        Calendrier.preparer(q, choisi, montre, aujourdhui)
        local contenu
        local function fermer()
            LrDialogs.stopModalWithResult(contenu, 'ok')
        end
        contenu = Calendrier.construire(f, q, C, P, borne == 'debut' and Calendrier.AIDE_DEBUT or Calendrier.AIDE_FIN, fermer)
        q:addObserver('mois', function() Calendrier.poserMois(q) end)
        q:addObserver('annee', function() Calendrier.poserMois(q) end)
        Calendrier.q = q
        local reponse = LrDialogs.presentModalDialog {
            title = borne == 'debut' and Calendrier.TITRE_DEBUT or Calendrier.TITRE_FIN,
            contents = contenu,
            actionVerb = Calendrier.CHOISIR,
            otherVerb = borne == 'debut' and Calendrier.PREMIERE_PHOTO or Calendrier.AUJOURDHUI,
            actionBinding = { enabled = { bind_to_object = q, key = 'peutChoisir' } },
        }
        Calendrier.q = nil
        if reponse == 'ok' and q.choisiAnnee then
            resultat = { date = { annee = q.choisiAnnee, mois = q.choisiMois, jour = q.choisiJour } }
        elseif reponse == 'other' then
            resultat = { autre = true }
        end
    end)
    return resultat
end

return Calendrier
