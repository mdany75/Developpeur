-- essais-fenetre-b.lua : la fenêtre Claude à l'allure de la fenêtre B (1.3, lot B3 : volet des
-- conversations en cases, en-tête avec le Mode, barre du fil, zone de saisie, colonne droite avec
-- ses segments et son panneau ; agrandie à 1 497 × 1 200 puis élargie à 1 948 × 1 200, demandé par Dany le 21 octobre 2026), hors
-- de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : les dimensions (contenu de
-- 1 495 × 1 166, D7, chaque colonne estimée, la fenêtre dans l'écran de Dany, la longueur des
-- lignes du fil), l'inventaire du volet, de l'en-tête, de la barre, de la saisie et des segments
-- (chaque élément trouvé par son titre, son infobulle ou son image, son action éprouvée par un clic
-- simulé, S.cliquer), les briques (Fenetre.bouton carré ou à icône, Fenetre.calque, Vues.boutonBleu,
-- Vues.inactif, les aplats), le Mode (radios tirés de l'état, D3, D12), la liste en cases (périodes,
-- sous-titres, choix, pagination, recherche, carnet), la légende de la photo active
-- (Lightroom.legende) et l'apparence (couleurs et images reprises à l'ouverture). Puis le fil (lot
-- B4) : les polices mesurées (Metriques), le texte riche (largeur, coupe, balises fermées), l'auteur
-- et l'heure de chaque tour (sur des copies), la ligne d'un appel et « Pourquoi ? », la ligne
-- d'actions (« ☆ Voir la note », « Leçon de la photo »), leurs clics, la bascule vers Leçon, le
-- bandeau sur deux lignes et le tableau du carnet à la largeur du fil ; essais-lecon.lua éprouve la
-- carte de l'onglet Leçon. Enfin les cartes (lot B5) : sur leurs images, leurs hauteurs et ce qui y
-- tient, l'inventaire de la carte Note (maquette) et des cartes Proposition et Aperçu, ni passes ni
-- plafond (correctif 1.3.2), les étoiles, les drapeaux, Laisser, Accepter (jusqu'à « Accepter 5 ★ »,
-- correctif 1.3.2), « Voir à 100 % » (le zoom
-- que Claude a pris pour noter) et la grille des critères. Ni Claude, ni quota, ni vraie photo :
-- les actions qui écriraient ou parleraient à Claude sont remplacées par des témoins le temps d'un
-- essai, et le registre des notes par un registre simulé.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local function refuse(fn, attendu, quoi)
    local ok, erreur = pcall(fn)
    vrai(not ok, (quoi or 'refus attendu') .. ' : accepté')
    vrai(tostring(erreur):find(attendu, 1, true), (quoi or 'refus') .. ' : ' .. tostring(erreur))
end

local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Lightroom = require 'Lightroom'
local Notation = require 'Notation'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local Vues = require 'Vues'
local prefs = Chemins.prefs()
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false
-- Le faux Claude Code (une demande partie par erreur ne lance jamais le vrai).
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'

local D = Dispositions.dimensions()

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Ouvre la fenêtre Claude et appelle fn(p, contenu) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args.contents) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    if erreur then
        error(erreur, 0)
    end
end

-- Remplace un champ d'une table le temps de fn, puis le remet (même en cas d'erreur).
local function avec(t, cle, valeur, fn)
    local avant = t[cle]
    t[cle] = valeur
    local ok, erreur = xpcall(fn, debug.traceback)
    t[cle] = avant
    if not ok then
        error(erreur, 0)
    end
end

-- Les vues -----------------------------------------------------------------------------------

local vues = S.vues

-- La première vue dont la clé `cle` vaut `valeur` (titre, infobulle…), liée ou non (`p` évalue).
local function vuePar(contenu, cle, valeur, genre, p)
    for _, v in ipairs(vues(contenu)) do
        local x = v.args[cle]
        if type(x) == 'table' and x.liaison and p then
            x = S.evaluer(x, p)
        end
        if x == valeur and (genre == nil or v.genre == genre) then
            return v
        end
    end
    error(string.format('vue introuvable : %s = %s', cle, tostring(valeur)), 2)
end

local function parTitre(contenu, titre, genre)
    return vuePar(contenu, 'title', titre, genre)
end

local function parInfobulle(contenu, infobulle, genre)
    return vuePar(contenu, 'tooltip', infobulle, genre)
end

-- La vue simple liée à cette clé (titre ou valeur).
local function liee(contenu, genre, cle)
    for _, v in ipairs(vues(contenu)) do
        local lien = v.args.title or v.args.value
        if v.genre == genre and type(lien) == 'table' and lien.liaison and lien.key == cle then
            return v
        end
    end
    error(genre .. ' lié à ' .. cle .. ' introuvable', 2)
end

-- Le bouton à icône (image_name) de cette image.
local function parIcone(contenu, nom)
    for _, v in ipairs(vues(contenu)) do
        if S.BOUTONS[v.genre] and type(v.args.image_name) == 'string' and v.args.image_name:match('/' .. nom:gsub('%-', '%%-') .. '%.png$') then
            return v
        end
    end
    error('bouton à icône introuvable : ' .. nom, 2)
end

-- Le calque de la case k de la liste (son infobulle est liée à `li..k`).
local function calqueCase(contenu, k)
    for _, v in ipairs(vues(contenu)) do
        local t = v.args.tooltip
        if v.genre == 'static_text' and type(t) == 'table' and t.key == 'li' .. k then
            return v
        end
    end
    error('calque de la case ' .. k .. ' introuvable', 2)
end

-- La valeur évaluée d'un attribut d'une vue (lié ou non).
local function valeur(v, cle, p)
    local x = v.args[cle]
    if type(x) == 'table' and x.liaison then
        return S.evaluer(x, p)
    end
    return x
end

-- Hauteur estimée d'une vue, en points : sa hauteur donnée, sinon d'après son contenu (une ligne de
-- texte : 1,25 × la taille de la police ; un bouton sans hauteur : son bezel naturel et la marge du
-- cadre ; un champ de N lignes : 18 par ligne et 16 de marges) ; une colonne additionne ses vues et
-- leurs écarts, une rangée ou une superposition prend la plus haute, marges comprises. Une vue de
-- hauteur donnée dont le contenu dépasse est refusée.
local function taillePolice(police)
    if type(police) == 'table' then
        return police.size or 13
    end
    return 13
end

local function hauteur(v)
    local a = v.args
    local g = v.genre
    local enfants = {}
    for _, e in ipairs(a) do
        if type(e) == 'table' and e.genre then
            enfants[#enfants + 1] = e
        end
    end
    local contenu
    if g == 'column' or g == 'group_box' or g == 'view' or g == 'row' then
        local superposes = a.place == 'overlapping' or g == 'row'
        contenu = 0
        for _, e in ipairs(enfants) do
            if superposes then
                contenu = math.max(contenu, hauteur(e))
            else
                contenu = contenu + hauteur(e)
            end
        end
        if not superposes then
            contenu = contenu + (a.spacing or 8) * math.max(0, #enfants - 1)
        end
        contenu = contenu + (a.margin_top or a.margin or 0) + (a.margin_bottom or a.margin or 0)
    elseif g == 'picture' then
        contenu = a.height
    elseif g == 'static_text' then
        contenu = (type(a.height_in_lines) == 'number' and a.height_in_lines or 1) * taillePolice(a.font) * 1.25
    elseif S.BOUTONS[g] then
        contenu = g == 'square_button' and (S.bezelVisible(v) + S.MARGE_BEZEL)
            or ({ small = 19, mini = 16 })[a.size or ''] or 22
    elseif g == 'edit_field' then
        contenu = type(a.height_in_lines) == 'number' and (a.height_in_lines * 18 + 16) or 22
    elseif g == 'popup_menu' then
        contenu = 24
    elseif g == 'radio_button' or g == 'checkbox' then
        contenu = 18
    elseif g == 'separator' then
        contenu = 1
    else
        contenu = 0
    end
    if type(a.height) == 'number' then
        vrai(contenu <= a.height + 0.5, string.format('%s de hauteur %d : contenu de %.1f', g, a.height, contenu))
        return a.height
    end
    return contenu
end

-- Largeur d'une vue faite de largeurs données, sans estimer de texte : sa largeur, sinon une rangée
-- additionne ses vues et leurs écarts, une superposition ou une colonne prend la plus large ; un
-- espace extensible (fill_horizontal, sans largeur) compte 0 ; les marges ne comptent pas. Une vue
-- sans largeur donnée, hors de ces cas, est refusée : sa largeur dépendrait de son texte.
local function largeurDonnee(v)
    local a = v.args
    if type(a.width) == 'number' then
        return a.width
    end
    if v.genre == 'spacer' then
        vrai(a.fill_horizontal, 'espace sans largeur ni fill_horizontal')
        return 0
    end
    local enfants = {}
    for _, e in ipairs(a) do
        if type(e) == 'table' and e.genre then
            enfants[#enfants + 1] = e
        end
    end
    vrai((v.genre == 'row' or v.genre == 'column') and #enfants > 0, v.genre .. ' sans largeur donnée')
    local enLigne = v.genre == 'row' and a.place ~= 'overlapping'
    local total = 0
    for _, e in ipairs(enfants) do
        local l = largeurDonnee(e)
        total = enLigne and (total + l) or math.max(total, l)
    end
    if enLigne then
        total = total + (a.spacing or 8) * (#enfants - 1)
    end
    return total
end

-- La rangée qui porte directement cette vue.
local function rangeeDe(contenu, vue)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == 'row' then
            for _, e in ipairs(v.args) do
                if e == vue then
                    return v
                end
                -- Une vue dans une superposition ou une rangée de voyant posée dans la rangée.
                if type(e) == 'table' and e.genre and e.genre ~= 'row' then
                    for _, x in ipairs(e.args) do
                        if x == vue then
                            return v
                        end
                    end
                end
            end
        end
    end
    error('rangée introuvable', 2)
end

-- Les colonnes de la racine : volet, filet, centre, filet, colonne droite.
local function colonnes(contenu)
    local r = {}
    for _, e in ipairs(contenu.args) do
        if type(e) == 'table' and e.genre then
            r[#r + 1] = e
        end
    end
    return r
end

-- Dimensions ---------------------------------------------------------------------------------------

-- La taille demandée par Dany le 21 octobre 2026, sur son écran de 3 440 × 1 440 (à 1x : un point
-- par pixel, constaté) : la fenêtre entière, le volet, le centre et la colonne droite (celle de la
-- maquette), et l'aperçu à la largeur de l'intérieur du panneau. La seule copie de ces chiffres dans
-- les essais ; le reste se tire de Dispositions.
local DEMANDE = { largeur = 1948, hauteur = 1200, volet = 324, centre = 1064, droite = 556, apercu = 498, apercuHauteur = 332 }
local ECRAN_DANY = { largeur = 3440, hauteur = 1440 }
-- La barre des menus de macOS sur un écran sans encoche : 24 points, et son filet.
local BARRE_MENUS = 25
-- La place que la fenêtre laisse à Lightroom à côté d'elle, sur cet écran (environ 1 490 points,
-- depuis l'élargissement demandé par Dany le 21 octobre 2026).
local PLACE_LIGHTROOM = 1490

essai('Cadre : la fenêtre demandée par Dany (1 948 × 1 200), son contenu (D7) ; les colonnes, le fil, la liste et les images concordent', function()
    local largeur, haut = S.contenuPourFenetre(DEMANDE.largeur, DEMANDE.hauteur)
    egal(DEMANDE.largeur, D.largeurFenetre)
    egal(DEMANDE.hauteur, D.hauteurFenetre)
    egal(largeur, D.largeurContenu, 'contenu : largeur (D7)')
    egal(haut, D.hauteurContenu, 'contenu : hauteur (D7 : barre de 33, marge de 1 en bas, aucune en haut)')
    egal(DEMANDE.volet, D.volet)
    egal(DEMANDE.centre, D.centre)
    egal(DEMANDE.droite, D.droite, 'la colonne droite de la maquette, inchangée')
    egal(D.largeurContenu, D.volet + D.filet + D.centre + D.filet + D.droite, 'volet, filet, centre, filet, colonne droite')
    egal(D.volet - 2 * D.margeVolet, D.liste, 'volet : sa largeur utile')
    egal(D.centre - 2 * D.margeCentre, D.fil, 'centre : sa largeur utile')
    egal(D.panneau, D.droite - 2 * D.margeDroite, 'colonne droite : le panneau entre ses marges')
    -- Le centre : en-tête et son filet, fil, barre, saisie, exactement ; le fil a autant de lignes
    -- que sa hauteur en tient entre ses marges (une de plus n'y tiendrait pas), le reste va à sa
    -- marge du bas.
    egal(D.hauteurContenu, D.entete + D.filet + D.hauteurFil + D.barre + D.saisie, 'le centre de haut en bas')
    egal(D.lignes * D.hauteurLigne, D.grille, 'la grille du fil : ses lignes de ' .. D.hauteurLigne)
    local bas = D.hauteurFil - D.margeHautFil - D.grille
    vrai(bas >= D.margeBasFil, string.format('marge du bas du fil : %d (au moins %d)', bas, D.margeBasFil))
    vrai(bas - D.hauteurLigne < D.margeBasFil, string.format('une ligne de plus tiendrait (%d lignes, marge du bas de %d)', D.lignes, bas))
    -- Le titre de l'en-tête prend ce que le Mode laisse ; la photo active, ce que les voyants laissent.
    egal(D.fil, D.titre + D.placeMode, 'le titre et la place du Mode')
    egal(D.fil, (8 + 6 + D.voyantClaude) + 14 + (8 + 6 + D.voyantLightroom) + D.info, 'les voyants et la photo active')
    -- Les images de Dispositions.IMAGES concordent avec les tailles.
    local I = Dispositions.IMAGES
    egal(D.liste, I.selection.largeur, 'fond de sélection : la largeur du volet')
    egal(D.hauteurCase, I.selection.hauteur, 'fond de sélection : une case')
    egal(D.panneau, I.panneau.largeur, 'panneau')
    egal(D.hauteurContenu, D.margeHautDroite + I.panneau.hauteur + D.margeBasDroite, 'le panneau sur toute la colonne, entre ses marges')
    for _, nom in ipairs({ 'carte-note', 'carte-proposition', 'carte-etape', 'carte-lecon', 'carte-focus' }) do
        egal(D.interieur, I[nom].largeur, nom)
    end
    egal(D.envoyer, I['bouton-bleu'].largeur, 'Envoyer : le bouton bleu')
    vrai(D.segments <= D.panneau and D.margeSegments >= 0, 'les segments tiennent dans le panneau')
    egal(D.hauteurSegments, I['seg-apercu'].hauteur)
    egal(35, D.hauteurSegments + D.margeHautPanneau, 'contenu du panneau à 35 du haut des segments (12 + 1 + 22)')
    egal(D.interieur, D.panneau - D.margeGauchePanneau - 15, 'contenu du panneau : 15 de chaque côté')
    -- L'aperçu : 3:2, à la largeur de l'intérieur du panneau (sans élargir la colonne), sa vignette
    -- en 2x ; la rangée sous lui tient dans le panneau.
    egal(DEMANDE.apercu, D.apercu)
    egal(DEMANDE.apercuHauteur, D.apercuHauteur)
    egal(D.apercu * 2, D.apercuHauteur * 3, 'un cadre 3:2')
    vrai(D.apercu <= D.interieur, "l'aperçu dans l'intérieur du panneau")
    egal(2 * D.apercu, D.pixelsApercu, 'vignette en 2x')
    egal(2 * D.apercuHauteur, D.pixelsApercuHauteur, 'vignette en 2x')
    egal(D.interieur, 2 * D.fleche + 4 + D.legende + 4 + 8 + D.agrandir, '◀ légende ▶ · Agrandir')
    -- Le volet : son haut, ses cases et son bas dans sa hauteur ; autant de cases que la place en
    -- tient (une de plus n'y tiendrait pas).
    vrai(D.cases * D.hauteurCase <= D.hauteurListe, 'les cases dans la place de la liste')
    vrai((D.cases + 1) * D.hauteurCase > D.hauteurListe, 'une case de plus tiendrait : ' .. D.cases)
    egal(D.hauteurContenu, 2 * D.margeVolet + D.hautVolet + D.hauteurListe + D.basVolet, 'le volet de haut en bas')
    -- Le cadre enregistré change de nom : Lightroom ne rapetisse pas un cadre enregistré, et la
    -- fenêtre élargie ne doit pas reprendre celui de 1 497 × 1 200 (FORME 3).
    egal(4, Fenetre.FORME)
    egal('DeveloppeurClaude-conversation-grande-4', Fenetre.cadre())
    egal(2, Dispositions.cadreBouton(0), 'cadre d\'un carré : bezel + 2 (D5)')
    egal(S.MARGE_BEZEL, Dispositions.TAILLES.margeBezel)
end)

-- Dispositions relu depuis sa source, la hauteur de la fenêtre changée (TAILLES.hauteurFenetre,
-- une seule fois dans le fichier) : une table neuve, hors de package.loaded.
local function dispositionsAHauteur(hauteur)
    local f = assert(io.open(S.plugin .. '/Dispositions.lua', 'r'))
    local source = f:read('*a')
    f:close()
    local autre, n = source:gsub('hauteurFenetre = %d+', 'hauteurFenetre = ' .. hauteur)
    egal(1, n, 'la hauteur de la fenêtre, une fois dans Dispositions.TAILLES')
    return assert(loadstring(autre, '=Dispositions.lua (hauteur ' .. hauteur .. ')'))()
end

essai("Cadre : à une autre hauteur de fenêtre, le fil, la liste, le panneau et les cartes suivent (rien n'est écrit pour une seule hauteur)", function()
    local I = Dispositions.IMAGES
    -- À la hauteur de la fenêtre : les cartes se tirent de la place sous l'aperçu.
    egal(D.placeCartes - D.autourNote, I['carte-note'].hauteur, 'carte Note : la place des cartes, moins sa grille')
    for _, nom in ipairs({ 'carte-proposition', 'carte-etape', 'carte-lecon', 'carte-focus' }) do
        egal(D.placeCartes - D.sousCarte, I[nom].hauteur, nom .. ' : la place des cartes, moins ce qu\'elle laisse sous elle')
    end
    -- Deux cents points de moins, puis de plus : chaque zone suit, autant de lignes et de cases que
    -- sa place en tient.
    for _, ecart in ipairs({ -200, 200 }) do
        local Autre = dispositionsAHauteur(D.hauteurFenetre + ecart)
        local A, J = Autre.dimensions(), Autre.IMAGES
        local quoi = string.format(' (fenêtre de %d de haut)', A.hauteurFenetre)
        egal(D.hauteurContenu + ecart, A.hauteurContenu, 'contenu' .. quoi)
        egal(D.hauteurFil + ecart, A.hauteurFil, 'fil' .. quoi)
        egal(math.floor((A.hauteurFil - A.margeHautFil - A.margeBasFil) / A.hauteurLigne), A.lignes, 'lignes du fil' .. quoi)
        vrai(ecart < 0 and A.lignes < D.lignes or A.lignes > D.lignes, 'les lignes du fil suivent' .. quoi)
        egal(D.hauteurListe + ecart, A.hauteurListe, 'liste' .. quoi)
        egal(math.floor(A.hauteurListe / A.hauteurCase), A.cases, 'cases de la liste' .. quoi)
        vrai(ecart < 0 and A.cases < D.cases or A.cases > D.cases, 'les cases suivent' .. quoi)
        egal(I.panneau.hauteur + ecart, J.panneau.hauteur, 'panneau' .. quoi)
        egal(A.hauteurContenu, A.margeHautDroite + J.panneau.hauteur + A.margeBasDroite, 'panneau entre ses marges' .. quoi)
        egal(D.placeCartes + ecart, A.placeCartes, 'place des cartes' .. quoi)
        egal(A.placeCartes - A.autourNote, J['carte-note'].hauteur, 'carte Note' .. quoi)
        for _, nom in ipairs({ 'carte-proposition', 'carte-etape', 'carte-lecon', 'carte-focus' }) do
            egal(A.placeCartes - A.sousCarte, J[nom].hauteur, nom .. quoi)
        end
    end
end)

essai("Cadre : la fenêtre entière tient dans l'écran de Dany (3 440 × 1 440), sous la barre des menus, et laisse sa place à Lightroom", function()
    local largeur, hauteur = S.fenetrePourContenu(D.largeurContenu, D.hauteurContenu)
    egal(D.largeurFenetre, largeur, 'la fenêtre de ce contenu (D7)')
    egal(D.hauteurFenetre, hauteur, 'la fenêtre de ce contenu (D7)')
    vrai(hauteur <= ECRAN_DANY.hauteur - BARRE_MENUS,
        string.format('fenêtre de %d de haut pour %d sous la barre des menus', hauteur, ECRAN_DANY.hauteur - BARRE_MENUS))
    vrai(ECRAN_DANY.largeur - largeur >= PLACE_LIGHTROOM, string.format('il reste %d à Lightroom', ECRAN_DANY.largeur - largeur))
end)

essai('Fil : sa ligne la plus longue reste sous environ 155 caractères moyens (lisibilité) ; une phrase de la fenêtre coupée de même', function()
    local Fil, Texte = require 'Fil', require 'Texte'
    -- Le « caractère moyen » : la chasse moyenne d'un caractère d'une phrase de la fenêtre
    -- (Fenetre.FIL_VIDE), espaces et ponctuation compris, dans la police des lignes de Dany et de
    -- Claude (Metriques). Une réponse ordinaire de Claude, aux mots plus courts et sans capitales,
    -- est plus étroite (5,9 points par caractère au lieu de 6,2) : environ 108 caractères par ligne
    -- dans la fenêtre de 1 497 (mesuré le 21 octobre 2026, hors de l'essai) ; le centre élargi de
    -- 40 % à la demande de Dany (même jour) en tient environ 150 : un choix de Dany, que cet essai
    -- borne.
    local police = Fil.polices.claude
    egal(police, Fil.polices.dany, 'Vous et Claude dans la même police')
    local moyen = Fil.largeur(Fenetre.FIL_VIDE, police) / Texte.longueur(Fenetre.FIL_VIDE)
    -- La ligne la plus large du fil : une ligne de Dany ou de Claude, sans retrait (Fil.RETRAITS).
    egal(0, Fil.retrait('claude'))
    egal(0, Fil.retrait('dany'))
    local place = D.texteFil - Fil.MARGE
    local caracteres = place / moyen
    vrai(caracteres <= 155, string.format('%.1f caractères moyens (%.2f points chacun) dans %d points', caracteres, moyen, place))
    -- La même phrase, répétée et coupée comme le fil la coupe : chaque ligne dans sa place, aucune
    -- au-delà de 155 caractères.
    local lignes = Fil.couper(string.rep(Fenetre.FIL_VIDE .. ' ', 8), place, police)
    vrai(#lignes > 3, 'plusieurs lignes')
    local plusLongue = 0
    for _, l in ipairs(lignes) do
        plusLongue = math.max(plusLongue, Texte.longueur(l))
        vrai(Fil.largeur(l, police) <= place, 'ligne trop large : ' .. l)
    end
    vrai(plusLongue <= 155, 'ligne de ' .. plusLongue .. ' caractères')
end)

essai('Cadre : la fenêtre construite fait la largeur du contenu, chaque colonne tient dans sa hauteur (estimation), sur ses aplats', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        local cols = colonnes(contenu)
        egal(5, #cols, 'volet, filet, centre, filet, colonne droite')
        egal(0, contenu.args.spacing, 'sans écart')
        egal(0, contenu.args.margin, 'sans marge')
        local total = 0
        for _, c in ipairs(cols) do
            vrai(type(c.args.width) == 'number', c.genre .. ' sans largeur')
            total = total + c.args.width
            local h = hauteur(c)
            vrai(h <= D.hauteurContenu, string.format('colonne de %d de haut (au plus %d)', h, D.hauteurContenu))
            -- Ce que porte la colonne sur son aplat (le volet, le centre, la colonne droite) : son
            -- contenu estimé tient dans la hauteur du contenu de la fenêtre.
            local dedans = c.args[2]
            if c.genre == 'column' and type(dedans) == 'table' and dedans.genre then
                local hd = hauteur(dedans)
                vrai(hd <= D.hauteurContenu, string.format('contenu de colonne de %.1f de haut (au plus %d)', hd, D.hauteurContenu))
            end
        end
        egal(D.largeurContenu, total, 'contenu de toute la largeur')
        -- Les fonds : un aplat (f:picture sans image, à background_color) sous chaque colonne, et les
        -- filets de 1 point aussi (jamais un séparateur ni primary_line_color, A6).
        local C = Fenetre.COULEURS
        local aplats, filets = {}, 0
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'picture' and v.args.value == nil then
                vrai(v.args.background_color, 'aplat sans fond')
                aplats[v.args.background_color] = true
                if v.args.width == 1 or v.args.height == 1 then
                    filets = filets + 1
                end
            end
            vrai(v.args.background_color == nil or v.genre == 'picture', 'fond hors d\'un aplat : ' .. v.genre)
        end
        for _, cle in ipairs({ 'fondVolet', 'fondContenu', 'fondDroite', 'filetVolet', 'filetDroite', 'filetEntete', 'filetBarre', 'fondApercu' }) do
            vrai(aplats[C[cle]], 'aplat ' .. cle)
        end
        egal(nil, C.filetPlafond, 'plus de filet du plafond (correctif 1.3.2)')
        -- Le filet du volet, celui de la colonne droite, sous l'en-tête, au-dessus de la barre,
        -- au-dessus de la saisie, dans le volet sous Renommer… et Supprimer… (celui du plafond de la
        -- carte Note est retiré avec sa ligne, correctif 1.3.2).
        egal(6, filets, 'filets de 1 point')
        -- Le premier aplat de chaque colonne est à sa taille : volet, centre, droite, sur la hauteur du contenu.
        for _, k in ipairs({ 1, 3, 5 }) do
            local aplat = cols[k].args[1]
            egal('picture', aplat.genre)
            egal(cols[k].args.width, aplat.args.width)
            egal(D.hauteurContenu, aplat.args.height)
        end
    end)
end)

-- Briques ------------------------------------------------------------------------------------------

essai('Briques : Fenetre.bouton carré (square_button), à icône (image_name, sans titre) et au bezel voulu ; tout clic passe par lui', function()
    local f = S.modules.LrView.osFactory()
    local appels = 0
    Fenetre.envoiAuto = {}
    local carre = Fenetre.bouton(f, { carre = true, bezel = 24, title = 'Portrait', action = function() appels = appels + 1 end })
    egal('square_button', carre.genre)
    egal(26, carre.args.height, 'bezel 24 : cadre de 26 (D5)')
    egal(24, S.bezelVisible(carre))
    egal(nil, carre.args.carre)
    egal(nil, carre.args.bezel)
    carre.args.action()
    egal(1, appels)
    egal(nil, Fenetre.envoiAuto, 'le clic annule l\'envoi automatique')
    vrai(Fenetre.parBouton(carre.args.action), 'compté par Fenetre.parBouton')
    local icone = Fenetre.bouton(f, { carre = true, icone = 'trombone', title = 'ignoré', bezel = 24, width = 28, action = function() end })
    egal(nil, icone.args.title, "un bouton à icône n'a pas de titre (B3)")
    egal(nil, icone.args.icone)
    egal(Chemins.ressource(Dispositions.image('trombone', Fenetre.apparence)), icone.args.image_name)
    local poussoir = Fenetre.bouton(f, { title = 'Accepter', action = function() end })
    egal('push_button', poussoir.genre, 'sans `carre` : un push_button (les ▲ ▼ des cartes)')
end)

essai('Briques : Fenetre.calque, un texte vide de taille fixe qui annule l\'envoi automatique ; Vues.inactif, grisé, « À venir » ; Vues.aplat', function()
    local f = S.modules.LrView.osFactory()
    local clics = 0
    Fenetre.envoiAuto = {}
    local calque = Fenetre.calque(f, { width = 30, height = 30, mouse_down = function() clics = clics + 1 end })
    egal('static_text', calque.genre)
    egal('', calque.args.title)
    egal(30, calque.args.width)
    calque.args.mouse_down()
    egal(1, clics)
    egal(nil, Fenetre.envoiAuto, "le clic d'un calque annule l'envoi automatique (D3)")
    vrai(Fenetre.parCalque(calque.args.mouse_down), 'compté par Fenetre.parCalque')
    vrai(not Fenetre.parCalque(function() end), 'un autre mouse_down ne l\'est pas')
    -- Vues.inactif : un carré grisé, sans action, « À venir », dans tous les états.
    local F = setmetatable({}, { __index = Fenetre })
    local inactif = Vues.inactif(f, F, { title = '? À vérifier', bezel = 24 })
    egal('square_button', inactif.genre)
    egal(false, inactif.args.enabled, 'grisé')
    egal('À venir', inactif.args.tooltip)
    egal(26, inactif.args.height)
    vrai(Fenetre.parBouton(inactif.args.action), 'passe par Fenetre.bouton')
    egal(nil, inactif.args.action(), 'action vide')
    -- Vues.aplat : un f:picture sans image, à son fond, à sa taille (A4).
    local aplat = Vues.aplat(f, 12, 1, Fenetre.COULEURS.filetVolet)
    egal('picture', aplat.genre)
    egal(nil, aplat.args.value)
    egal(Fenetre.COULEURS.filetVolet, aplat.args.background_color)
end)

-- Inventaire ---------------------------------------------------------------------------------------

essai('Inventaire du volet : Nouvelle conversation, Rechercher et sa loupe, les cases, Renommer…, Supprimer…, Publication…, Consommation…, versions, Écran', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local appels = {}
        local function temoin(nom)
            return function(...) appels[#appels + 1] = nom .. (select('#', ...) > 0 and (':' .. tostring((...))) or '') end
        end
        local nouvelle = parTitre(contenu, '＋ Nouvelle conversation')
        egal('square_button', nouvelle.genre)
        egal(26, S.bezelVisible(nouvelle), 'bezel de 26 (maquette)')
        egal(D.liste, nouvelle.args.width)
        egal('libre', nouvelle.args.enabled.key)
        avec(Fenetre, 'nouvelle', temoin('nouvelle'), function() S.cliquer(nouvelle) end)
        -- Rechercher : champ immédiat de 143, la loupe devant (une image, sans clic).
        local recherche = liee(contenu, 'edit_field', 'recherche')
        egal(true, recherche.args.immediate)
        egal('Rechercher', recherche.args.placeholder_string)
        egal(D.recherche, recherche.args.width)
        local rangee
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'row' and v.args[3] == recherche then
                rangee = v
            end
        end
        vrai(rangee and rangee.args[1].genre == 'picture' and rangee.args[1].args.value:match('/loupe%.png$'), 'la loupe devant le champ')
        egal(nil, rangee.args[1].args.mouse_down)
        -- Les cases : un calque chacune, qui appelle Fenetre.cliquerListe(k).
        avec(Fenetre, 'cliquerListe', temoin('case'), function()
            for k = 1, D.cases do
                S.cliquer(calqueCase(contenu, k))
            end
        end)
        -- Renommer… et Supprimer… : dans une tâche.
        local renommer, supprimer = parTitre(contenu, 'Renommer…'), parTitre(contenu, 'Supprimer…')
        egal(22, S.bezelVisible(renommer))
        egal(D.renommer, renommer.args.width)
        egal('libre', supprimer.args.enabled.key)
        avec(Fenetre, 'renommer', temoin('renommer'), function()
            avec(Fenetre, 'supprimer', temoin('supprimer'), function()
                local taches = #S.taches
                S.cliquer(renommer)
                S.cliquer(supprimer)
                egal(taches + 2, #S.taches, 'dans des tâches')
                S.taches[taches + 1]()
                S.taches[taches + 2]()
            end)
        end)
        avec(Fenetre, 'publication', temoin('publication'), function()
            avec(Fenetre, 'consommation', temoin('consommation'), function()
                S.cliquer(parTitre(contenu, 'Publication…'))
                S.cliquer(parTitre(contenu, 'Consommation…'))
            end)
        end)
        local attendus = { 'nouvelle' }
        for k = 1, D.cases do
            attendus[#attendus + 1] = 'case:' .. k
        end
        for _, nom in ipairs({ 'renommer', 'supprimer', 'publication', 'consommation' }) do
            attendus[#attendus + 1] = nom
        end
        egal(table.concat(attendus, ' '), table.concat(appels, ' '), 'les actions du volet')
        -- Les versions, une ligne chacune ; le voyant Écran en dessous, cliquable.
        egal('Développeur ' .. require('Composants').module(), p.versionTexte1)
        vrai(liee(contenu, 'static_text', 'versionTexte2'), 'MCP-Développeur')
        egal('MCP-Développeur 1.2 · à mettre à jour', Fenetre.texteVersion({ nom = 'MCP-Développeur · à mettre à jour', version = '1.2' }))
        egal('MCP-Développeur · introuvable', Fenetre.texteVersion({ nom = 'MCP-Développeur · introuvable', version = '' }))
        local ecran = liee(contenu, 'static_text', 'texteEcran')
        avec(Fenetre, 'montrerEcran', temoin('ecran'), function()
            local taches = #S.taches
            S.cliquer(ecran)
            S.taches[taches + 1]()
        end)
        egal('ecran', appels[#appels])
    end)
end)

essai('Inventaire de l\'en-tête : titre en gras 16 sans ✎, Mode en trois radios, voyants Claude Code et Lightroom, photo active en texte riche', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local titre = liee(contenu, 'static_text', 'titre')
        egal('<system/bold>', titre.args.font.name)
        egal(16, titre.args.font.size)
        refuse(function() parTitre(contenu, '✎') end, 'introuvable', 'plus de ✎')
        local mode = parTitre(contenu, 'Mode :', 'static_text')
        egal(Fenetre.COULEURS.gris, mode.args.text_color)
        local radios = {}
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'radio_button' then
                radios[#radios + 1] = v.args.title .. '=' .. v.args.checked_value .. '/' .. v.args.enabled.key
                egal('mode', v.args.value.key)
                egal('small', v.args.size)
            end
        end
        egal("Appliquer=appliquer/libre Proposer d'abord=proposer/libre Je le fais=jelefais/peutJeLeFais", table.concat(radios, ' '))
        -- Deux voyants : Claude Code sans clic, Lightroom qui démarre la liaison.
        local claude, liaison = liee(contenu, 'static_text', 'texteClaude'), liee(contenu, 'static_text', 'texteLightroom')
        egal(nil, claude.args.mouse_down, 'Claude Code : sans clic')
        local demarree = false
        avec(Fenetre, 'demarrerLiaison', function() demarree = true end, function() S.cliquer(liaison) end)
        vrai(demarree, 'le voyant Lightroom démarre la liaison')
        -- La photo active : texte riche, emphase de même taille, en couleur du texte.
        local info = liee(contenu, 'static_text', 'infoPhoto')
        egal(Fenetre.COULEURS.gris, info.args.text_color)
        egal(12, info.args.font.size)
        egal(12, info.args.emphasis_font.size)
        egal(Fenetre.COULEURS.texte, info.args.emphasis_color)
        egal('Active : <EM>DSCF4961.RAF</EM> · Sélection : <EM>1</EM>', p.infoPhoto)
        egal(nil, S.refusEmphase({ title = p.infoPhoto, font = info.args.font, emphasis_font = info.args.emphasis_font,
            emphasis_color = info.args.emphasis_color }), 'texte riche accepté (D4)')
        -- La rangée des voyants et de la photo active fait la largeur utile du centre : la photo
        -- active, alignée à droite, finit sur la marge de droite, comme dans la maquette.
        egal(D.fil, largeurDonnee(rangeeDe(contenu, info)), 'rangée des voyants et de la photo active')
    end)
end)

essai('Inventaire de la barre et de la saisie : ▲ ▼ à icône, Fin, position ; sept invites en carrés, champ de 2 lignes, 📎 📋, Style, bandeau, Envoyer et Arrêter', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local pas = {}
        avec(Fenetre, 'defiler', function(x) pas[#pas + 1] = tostring(x) end, function()
            p.peutMonter, p.peutDescendre = true, true
            for _, nom in ipairs({ 'chevron-haut', 'chevron-bas' }) do
                local b = parIcone(contenu, nom)
                egal('square_button', b.genre)
                egal(22, S.bezelVisible(b))
                egal(26, b.args.width)
                egal(nil, b.args.title)
                S.cliquer(b)
            end
            S.cliquer(parTitre(contenu, 'Fin'))
        end)
        local saut = math.floor(D.lignes * 0.8)
        egal(saut .. ' ' .. -saut .. ' fin', table.concat(pas, ' '), '▲ ▼ Fin')
        local position = liee(contenu, 'static_text', 'positionFil')
        -- La barre fait la largeur utile du centre : l'activité (ou le forfait), alignée à droite,
        -- finit sur la marge de droite, comme dans la maquette.
        egal(D.fil, largeurDonnee(rangeeDe(contenu, position)), 'la barre : ▲ ▼ Fin, position, activité')
        egal(D.fin, parTitre(contenu, 'Fin').args.width)
        -- Les invites, dans l'ordre de Consignes.invites, envoient leur message.
        local envois = {}
        avec(Fenetre, 'envoyer', function(message) envois[#envois + 1] = message end, function()
            for _, invite in ipairs(Consignes.invites) do
                local b = parTitre(contenu, invite.titre)
                egal('square_button', b.genre, invite.titre)
                egal(24, S.bezelVisible(b), invite.titre .. ' : bezel de 24 (maquette)')
                egal(12, b.args.font.size)
                S.cliquer(b)
            end
        end)
        egal(7, #envois, 'sept invites')
        egal(Consignes.invites[6].message, envois[6], 'Composition')
        -- Le champ : deux lignes, à la largeur du centre, Retour le valide.
        local champ = liee(contenu, 'edit_field', 'saisie')
        egal(2, champ.args.height_in_lines)
        egal(D.fil, champ.args.width)
        egal(false, champ.args.immediate)
        -- 📎 et 📋 : carrés à icône seule, dans une tâche (celle de 📋 ne tourne jamais ici).
        local joindre, coller = parIcone(contenu, 'trombone'), parIcone(contenu, 'presse-papiers')
        for _, b in ipairs({ joindre, coller }) do
            egal(24, S.bezelVisible(b))
            egal(D.joindre, b.args.width)
        end
        local taches = #S.taches
        S.cliquer(coller)
        egal(taches + 1, #S.taches, '📋 : dans une tâche')
        table.remove(S.taches)
        -- Style : son étiquette grise, puis le menu ; ni Modèle ni Effort.
        local style = liee(contenu, 'popup_menu', 'style')
        egal(D.style, style.args.width)
        egal(Fenetre.COULEURS.grisEntete, parTitre(contenu, 'Style', 'static_text').args.text_color)
        refuse(function() liee(contenu, 'popup_menu', 'modele') end, 'introuvable', 'pas de menu Modèle')
        refuse(function() parTitre(contenu, 'Modèle') end, 'introuvable', 'pas d\'étiquette Modèle')
        -- Pas de bouton Noter, sous aucun titre ni aucune forme (décision de Dany).
        for _, b in ipairs(S.boutons(contenu)) do
            local t = tostring(valeur(b, 'title', p) or '')
            vrai(not t:find('Noter', 1, true) and not t:find('Évaluer', 1, true), 'bouton « ' .. t .. ' »')
        end
        -- Le bandeau, dans la rangée du bas, qui fait la largeur utile du centre (Envoyer sur la
        -- marge de droite).
        local message = liee(contenu, 'static_text', 'message')
        egal(D.bandeau, message.args.width)
        egal(D.fil, largeurDonnee(rangeeDe(contenu, message)), 'la rangée du bas de la saisie')
        -- Cette place (D.bandeau) tient deux lignes de petit texte (lot B4, essai du bandeau plus
        -- bas) ; son infobulle donne le message en entier.
        p.message = Fenetre.CHOISIR_CONVERSATION
        egal(Fenetre.CHOISIR_CONVERSATION, valeur(message, 'tooltip', p), "l'infobulle du message, en entier")
        p.message = ''
        -- Envoyer et Arrêter : superposés ; aucun bouton par défaut (repli du lot B0).
        egal(nil, S.boutonParDefaut())
        local envoyer = parInfobulle(contenu, "Envoyer la demande à Claude (Retour dans le champ aussi)")
        local arreter = parTitre(contenu, 'Arrêter')
        egal('square_button', arreter.genre)
        egal(D.envoyer, arreter.args.width)
        p.travaille, p.libre = false, true
        vrai(S.montreeDansFenetre(envoyer) and not S.montreeDansFenetre(arreter), 'Claude libre : Envoyer')
        p.travaille, p.libre = true, false
        vrai(not S.montreeDansFenetre(envoyer) and S.montreeDansFenetre(arreter), 'Claude travaille : Arrêter')
        local principal = 0
        avec(Fenetre, 'boutonPrincipal', function() principal = principal + 1 end, function()
            S.cliquer(arreter)
            refuse(function() S.cliquer(envoyer) end, 'masquée', 'Envoyer caché pendant le travail')
            p.travaille, p.libre = false, true
            S.cliquer(envoyer)
        end)
        egal(2, principal, 'Arrêter puis Envoyer : F.boutonPrincipal')
    end)
end)

essai('Bouton bleu (Envoyer) : images normale, enfoncée et inactive ; titre blanc, ou éteint quand il est inactif ; le calque ne fait rien inactif', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local C = Fenetre.COULEURS
        local envoyer = parInfobulle(contenu, "Envoyer la demande à Claude (Retour dans le champ aussi)")
        local bouton
        for _, v in ipairs(vues(contenu)) do
            for _, e in ipairs(v.args) do
                if e == envoyer then
                    bouton = v
                end
            end
        end
        local images, titres = {}, {}
        for _, e in ipairs(bouton.args) do
            if e.genre == 'picture' then
                images[e.args.value:match('([^/]+)%.png$')] = e
            elseif e.genre == 'static_text' and e.args.title == 'Envoyer' then
                titres[#titres + 1] = e
            end
        end
        local function montrees()
            local r = {}
            for _, nom in ipairs({ 'bouton-bleu', 'bouton-bleu-presse', 'bouton-bleu-inactif' }) do
                if S.montreeDansFenetre(images[nom]) then
                    r[#r + 1] = nom
                end
            end
            for _, t in ipairs(titres) do
                if S.montreeDansFenetre(t) then
                    r[#r + 1] = t.args.text_color == C.blanc and 'blanc' or (t.args.text_color == C.titreInactif and 'éteint' or '?')
                end
            end
            return table.concat(r, ' ')
        end
        egal(false, p.bleuEnfonceEnvoyer, "sa clé d'enfoncement a une valeur avant l'ouverture")
        p.libre, p.travaille = true, false
        egal('bouton-bleu blanc', montrees())
        local appels = 0
        avec(Fenetre, 'boutonPrincipal', function() appels = appels + 1 end, function()
            local taches = #S.taches
            S.cliquer(envoyer)
            egal(1, appels)
            egal('bouton-bleu-presse blanc', montrees(), 'enfoncé')
            S.taches[taches + 1]()
            egal('bouton-bleu blanc', montrees(), 'relevé après 0,15 s')
            -- Inactif (une demande part, Claude n'a pas encore commencé) : l'image pâlie, le titre
            -- éteint, et le calque ne fait rien.
            p.libre = false
            egal('bouton-bleu-inactif éteint', montrees())
            S.cliquer(envoyer)
            egal(1, appels, 'inactif : rien')
            egal(false, p.bleuEnfonceEnvoyer)
            p.libre = true
        end)
    end)
end)

-- Segments -------------------------------------------------------------------------------------------

essai('Segments : Aperçu | Focus | Proposition | Note | Leçon en images sous calques ; un clic choisit l\'onglet, son crochet suit, sans envoyer la demande', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local champ = liee(contenu, 'edit_field', 'saisie')
        local function segment(valeur)
            local images = {}
            for _, v in ipairs(vues(contenu)) do
                if v.genre == 'picture' and type(v.args.value) == 'string' and v.args.value:match('/seg%-' .. valeur .. '%-?a?c?t?i?f?%.png$') then
                    images[#images + 1] = v
                end
            end
            return images
        end
        egal('notation', p.onglet, 'Note à l\'ouverture')
        local recus = {}
        local envoyer = Fenetre.envoyer
        Fenetre.envoyer = function() error('envoi pendant un clic de segment') end
        for _, o in ipairs(D.onglets) do
            avec(Fenetre.surOnglet, o.valeur, function(v) recus[#recus + 1] = v end, function()
                S.taper(champ, 'texte')
                S.cliquer(parInfobulle(contenu, o.titre))
                egal(o.valeur, p.onglet, o.titre)
                egal(nil, Fenetre.envoiAuto, o.titre .. " : l'envoi automatique annulé")
            end)
            -- Le segment choisi en bleu, les autres en blanc.
            for _, autre in ipairs(D.onglets) do
                local normal, actif
                for _, v in ipairs(vues(contenu)) do
                    if v.genre == 'picture' and v.args.value == Fenetre.image(autre.image) then
                        normal = v
                    elseif v.genre == 'picture' and v.args.value == Fenetre.image(autre.image .. '-actif') then
                        actif = v
                    end
                end
                egal(autre.valeur == o.valeur, S.montree(actif, p), autre.titre .. ' en bleu')
                egal(autre.valeur ~= o.valeur, S.montree(normal, p), autre.titre .. ' en blanc')
            end
        end
        Fenetre.envoyer = envoyer
        p.saisie = ''
        egal('apercu focus proposition notation lecon', table.concat(recus, ' '), 'un vrai clic : le crochet de chaque onglet')
        -- La rangée ◀ légende ▶ · ⤢ Agrandir est commune aux cinq onglets.
        for _, titre in ipairs({ '◀', '▶', '⤢ Agrandir' }) do
            local b = parTitre(contenu, titre)
            egal(nil, b.args.visible, titre .. ' : hors des onglets')
            egal(22, S.bezelVisible(b))
        end
        egal(nil, liee(contenu, 'static_text', 'legendeApercu').args.visible)
        -- L'onglet Leçon montre sa carte (lot B4) : sans leçon, son aide, coupée à la largeur de la
        -- carte.
        p.onglet = 'lecon'
        local titre = liee(contenu, 'static_text', 'leconTitre')
        vrai(S.montreeDansFenetre(titre), "l'onglet Leçon montré")
        egal('Leçon de la photo', p.leconTitre)
        egal(Fenetre.AUCUNE_LECON, (p.leconTexte:gsub('\n', ' ')), "l'aide, coupée à la largeur de la carte")
        egal(nil, Fenetre.AIDE_LECON, "plus d'aide provisoire")
        egal(nil, Vues.leconProvisoire, 'plus de carte provisoire')
        p.onglet = 'notation'
        vrai(not S.montreeDansFenetre(titre), 'cachée hors de son onglet')
    end)
end)

-- Mode -----------------------------------------------------------------------------------------------

-- Une réponse de preview_settings avec my_turn (Je le fais), réduite à un réglage.
local TOUR = [=[{"a_faire":[{"a":"+0,35","apres":0.35,"avant":0,"cle":"Exposure2012","de":"0","n":1,"panneau":"Réglages de base",
"reglage":"Exposition","section":"Tonalité","texte":"Réglages de base › Tonalité › Exposition : 0 → +0,35"}],
"etape":"Claude · essai : ma version (je le fais)","instantane":"Claude · ma version","mode":"appliquer directement",
"photo":{"copie_virtuelle":true,"fichier":"DSCF4961.RAF","id":4961}}]=]

-- Ajoute à la conversation un exercice « Je le fais » à faire (sa liste arrivée).
local function exerciceAFaire(c, appel)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__preview_settings',
        entree = { photo_id = 4961, settings = { Exposure2012 = 0.35 }, my_turn = true, step_name = 'lumière' } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, textes = { TOUR }, images = {}, erreur = false } } })
    local exo = Conversation.exerciceEnCours(c)
    vrai(exo, 'exercice à faire')
    return exo
end

essai('Mode : trois radios tirés de l\'état ; un clic annule l\'envoi automatique ; Appliquer et Proposer d\'abord changent la liaison ; grisés pendant le travail', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    require('Preferences').lire().mode = 'appliquer'
    ouvrirFenetre(function(p, contenu)
        local champ = liee(contenu, 'edit_field', 'saisie')
        local radios = {}
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'radio_button' then
                radios[v.args.checked_value] = v
            end
        end
        egal('appliquer', p.mode, 'le mode de la liaison à l\'ouverture')
        egal(nil, p.texteMode, 'plus de voyant Mode')
        -- Proposer d'abord : la préférence de la liaison change ; la demande tapée n'est pas envoyée.
        S.taper(champ, 'Bonjour')
        S.cliquer(radios.proposer)
        egal('proposer', Lightroom.mode())
        egal('proposer', p.mode)
        egal(nil, Fenetre.envoiAuto, "le clic d'un radio annule l'envoi automatique (D3)")
        egal('Bonjour', p.saisie, 'validée par le clic, laissée dans le champ')
        p.saisie = ''
        S.cliquer(radios.appliquer)
        egal('appliquer', Lightroom.mode())
        -- Le radio déjà coché : la valeur ne change pas (aucun observateur), mais le clic a validé
        -- le champ ; la demande tapée ne part pas pour autant (F.lierRadio), et rien ne change.
        local envoyer, envoyees = Fenetre.envoyer, 0
        Fenetre.envoyer = function() envoyees = envoyees + 1 end
        local taches = #S.taches
        S.taper(champ, 'Encore')
        S.cliquer(radios.appliquer)
        egal(nil, Fenetre.envoiAuto, "un clic sur le radio déjà coché annule aussi l'envoi automatique")
        egal('Encore', p.saisie, 'validée par le clic, laissée dans le champ')
        for i = taches + 1, #S.taches do
            S.taches[i]()
        end
        Fenetre.envoyer = envoyer
        egal(0, envoyees, 'rien envoyé')
        egal('appliquer', Lightroom.mode(), 'la liaison inchangée')
        egal('appliquer', p.mode)
        -- La fenêtre qui pose la valeur (de la table vers la vue : Lightroom relit la valeur de
        -- chaque radio pour le redessiner) n'annule rien.
        Fenetre.envoiAuto = {}
        Fenetre.rafraichirMode()
        Lightroom.basculerMode()
        Fenetre.rafraichirMode()
        for nom, r in pairs(radios) do
            egal('proposer', valeur(r, 'value', p), nom .. ' : la valeur relue')
        end
        vrai(Fenetre.envoiAuto, "la fenêtre qui change le radio n'annule pas l'envoi automatique")
        Fenetre.envoiAuto = nil
        Lightroom.basculerMode()
        Fenetre.rafraichirMode()
        p.saisie = ''
        -- Un mode changé ailleurs (le menu de la liaison) : le radio suit au rafraîchissement.
        Lightroom.basculerMode()
        Fenetre.rafraichir()
        egal('proposer', p.mode)
        Lightroom.basculerMode()
        Fenetre.rafraichir()
        -- Pendant que Claude travaille : les trois grisés.
        Moteur.travaille = true
        Fenetre.rafraichir()
        for nom, r in pairs(radios) do
            egal(false, valeur(r, 'enabled', p), nom .. ' grisé pendant le travail')
        end
        refuse(function() S.cliquer(radios.proposer) end, 'inactive', 'un radio grisé ne se clique pas')
        Moteur.travaille = false
        Fenetre.rafraichir()
        egal(true, valeur(radios.appliquer, 'enabled', p))
        egal(true, valeur(radios.jelefais, 'enabled', p), 'Je le fais : une photo active, Claude libre')
    end)
end)

essai('Mode : Je le fais lance l\'exercice (jamais J\'ai fini depuis un radio) ; coché pendant l\'exercice, réouverture comprise ; revenu au mode après la comparaison ou un refus', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    require('Preferences').lire().mode = 'proposer'
    local c = Moteur.courante
    local jeLeFais, jaiFini = Moteur.jeLeFais, Moteur.jaiFini
    local demandes, finis = 0, 0
    Moteur.jeLeFais = function()
        demandes = demandes + 1
        Moteur.travaille = true
        return true
    end
    Moteur.jaiFini = function() finis = finis + 1; return true end
    local ok, erreur = pcall(function()
        ouvrirFenetre(function(p, contenu)
            local radio = vuePar(contenu, 'checked_value', 'jelefais', 'radio_button')
            egal('proposer', p.mode)
            local taches = #S.taches
            S.cliquer(radio)
            egal('jelefais', p.mode, 'coché au clic')
            egal(taches + 1, #S.taches, 'la demande part dans une tâche')
            S.taches[taches + 1]()
            egal(1, demandes, 'Moteur.jeLeFais')
            egal('jelefais', p.mode, 'Claude prépare la liste : toujours Je le fais')
            -- La liste arrive : l'exercice est à faire.
            Moteur.travaille = false
            exerciceAFaire(c, 'tour-1')
            Fenetre.rafraichir()
            egal('jelefais', p.mode, 'exercice à faire')
            -- Je le fais pendant l'exercice : rien (ni nouvelle demande, ni J'ai fini), pas même une
            -- tâche.
            local avant = #S.taches
            Fenetre.changerMode('jelefais')
            egal(avant, #S.taches, 'aucune tâche')
            for i = avant + 1, #S.taches do
                S.taches[i]()
            end
            egal(1, demandes)
            egal(0, finis, "jamais J'ai fini depuis un radio")
            -- Appliquer pendant l'exercice : la liaison change, le radio revient, le bandeau le dit.
            S.cliquer(vuePar(contenu, 'checked_value', 'appliquer', 'radio_button'))
            egal('appliquer', Lightroom.mode(), 'la liaison change')
            egal('jelefais', p.mode, 'le radio revient à Je le fais')
            -- Un message court, qui tient dans les deux lignes du bandeau (lot B4).
            egal(Fenetre.EXERCICE_CONTINUE .. 'Appliquer.', p.message)
            egal(1, (p.message:find("L'exercice continue", 1, true)), p.message)
            p.message = ''
        end)
        -- Rouverte : toujours Je le fais (tiré de l'état, pas d'un drapeau).
        ouvrirFenetre(function(p)
            egal('jelefais', p.mode, "réouverte pendant l'exercice")
            -- Comparée : le mode de la liaison.
            Conversation.exerciceEnCours(c).etat = 'comparee'
            Fenetre.rafraichir()
            egal('appliquer', p.mode, 'après la comparaison')
            -- Un refus (aucune photo active ni proposition) : le radio revient aussi.
            Moteur.jeLeFais = function() return false, 'Aucune photo active' end
            local taches = #S.taches
            Fenetre.changerMode('jelefais')
            S.taches[taches + 1]()
            egal('appliquer', p.mode, 'après un refus')
            egal('Aucune photo active', p.message)
            p.message = ''
        end)
    end)
    Moteur.jeLeFais, Moteur.jaiFini, Moteur.travaille = jeLeFais, jaiFini, false
    require('Preferences').lire().mode = 'appliquer'
    assert(ok, erreur)
end)

essai('Mode (D12) : la valeur se repose une fois dans la première tâche de la fenêtre, par une autre, sans que l\'observateur la prenne pour un clic', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p)
        local vus, changes = {}, 0
        p:addObserver('mode', function(_, _, v) vus[#vus + 1] = tostring(v) end)
        local LrTasks = S.modules.LrTasks
        local dormir, tours = LrTasks.sleep, 0
        LrTasks.sleep = function()
            tours = tours + 1
            if tours >= Fenetre.TOUR_REPOSER_MODE + 1 then
                error('arrêt de la boucle', 0)
            end
        end
        avec(Fenetre, 'changerMode', function() changes = changes + 1 end, function()
            local ok, e = pcall(Fenetre.boucle, Fenetre.generation)
            vrai(not ok and e == 'arrêt de la boucle', tostring(e))
        end)
        LrTasks.sleep = dormir
        egal(2, Fenetre.TOUR_REPOSER_MODE, 'au deuxième tour')
        egal('aucun ' .. p.mode, table.concat(vus, ' '), 'une autre valeur, puis la même')
        egal(0, changes, "l'observateur ne la prend pas pour un clic")
        egal(false, Fenetre.modeAuto)
    end)
end)

-- Liste des conversations -----------------------------------------------------------------------------

local function date(annee, mois, jour, heure, minute)
    return os.time({ year = annee, month = mois, day = jour, hour = heure or 12, min = minute or 0, sec = 0 })
end

essai('Liste : périodes Aujourd\'hui, Hier, Plus tôt en <mois>, <Mois année> ; sous-titres à l\'heure ou à la date courte, avec les photos', function()
    local maintenant = date(2026, 10, 21, 20, 0)
    egal("Aujourd'hui", Fenetre.periodeListe(date(2026, 10, 21, 0, 5), maintenant))
    egal('Hier', Fenetre.periodeListe(date(2026, 10, 20, 21, 5), maintenant))
    egal('Plus tôt en octobre', Fenetre.periodeListe(date(2026, 10, 12), maintenant))
    egal('Septembre 2026', Fenetre.periodeListe(date(2026, 9, 30), maintenant))
    egal('Octobre 2025', Fenetre.periodeListe(date(2025, 10, 8), maintenant))
    egal('Décembre 2025', Fenetre.periodeListe(date(2025, 12, 31), maintenant))
    -- Hier par-dessus un changement de mois.
    egal('Hier', Fenetre.periodeListe(date(2026, 10, 31, 23, 0), date(2026, 11, 1, 9, 0)))
    egal('Octobre 2026', Fenetre.periodeListe(date(2026, 10, 30), date(2026, 11, 1, 9, 0)))
    -- Sous-titres.
    egal('19 h 46 · 1 photo', Fenetre.sousTitreListe({ modifiee = date(2026, 10, 21, 19, 46), cle = '53:1:53' }, maintenant))
    egal('21 h 05 · 3 photos', Fenetre.sousTitreListe({ modifiee = date(2026, 10, 20, 21, 5), cle = '7:3:7:8:9' }, maintenant))
    egal('12 oct. · 48 photos', Fenetre.sousTitreListe({ modifiee = date(2026, 10, 12), cle = '1:48:1' }, maintenant))
    egal('8 oct.', Fenetre.sousTitreListe({ modifiee = date(2025, 10, 8) }, maintenant), 'sans clé : la date seule')
    egal('9 h 00', Fenetre.sousTitreListe({ creee = date(2026, 10, 21, 9, 0) }, maintenant), 'sans modifiee : creee')
end)

essai('Liste : cases d\'une page (Fenetre.casesListe) ; Plus anciennes… et Plus récentes… ; un en-tête de jour ne finit jamais une page', function()
    local elements = {}
    for i = 1, 30 do
        if i % 6 == 1 then
            elements[#elements + 1] = { genre = 'jour', title = 'Jour ' .. i, value = '§' .. i }
        else
            elements[#elements + 1] = { genre = 'conversation', title = 'C' .. i, value = 'c' .. i, sousTitre = 's' }
        end
    end
    local function decrire(cases)
        local r = {}
        for _, c in ipairs(cases) do
            r[#r + 1] = c.genre == 'plus' and (c.title .. '>' .. c.vers) or (c.value or c.genre)
        end
        return table.concat(r, ' ')
    end
    local cases, page = Fenetre.casesListe(elements, 1, 12)
    egal(1, page)
    egal(12, #cases)
    egal('§1 c2 c3 c4 c5 c6 §7 c8 c9 c10 c11 Plus anciennes…>2', decrire(cases))
    cases, page = Fenetre.casesListe(elements, 2, 12)
    egal('Plus récentes…>1 c12 §13 c14 c15 c16 c17 c18 §19 c20 c21 Plus anciennes…>3', decrire(cases))
    cases, page = Fenetre.casesListe(elements, 99, 12)
    egal(3, page, 'au-delà : la dernière page')
    egal('Plus récentes…>2 c22 c23 c24 §25 c26 c27 c28 c29 c30 vide vide', decrire(cases), 'cases vides au bout')
    -- Un en-tête de jour ne finit jamais une page : il passe à la suivante, une case vide à sa place,
    -- et « Plus anciennes… » reste dans la dernière case.
    local jours = {}
    for i = 1, 20 do
        jours[i] = (i == 1 or i == 11) and { genre = 'jour', title = 'J' .. i, value = '§' .. i }
            or { genre = 'conversation', title = 'C' .. i, value = 'c' .. i }
    end
    egal('§1 c2 c3 c4 c5 c6 c7 c8 c9 c10 vide Plus anciennes…>2', decrire(Fenetre.casesListe(jours, 1, 12)))
    egal('Plus récentes…>1 §11 c12 c13 c14 c15 c16 c17 c18 c19 c20 vide', decrire(Fenetre.casesListe(jours, 2, 12)))
    -- Une liste courte : une page, sans pagination, des cases vides.
    cases = Fenetre.casesListe({ elements[1], elements[2] }, 1, 12)
    egal('§1 c2 vide vide vide vide vide vide vide vide vide vide', decrire(cases))
    egal('§1 c2 vide', decrire(Fenetre.casesListe({ elements[1], elements[2] }, 0, 3)), 'une page 0 : la première')
    -- Des tables neuves.
    vrai(cases[2] ~= elements[2], 'tables neuves')
end)

essai('Liste dans la fenêtre : le carnet en tête, la case choisie (fond et gras) suit la vue ; un clic ouvre, refusé pendant le travail ; pages, recherche', function()
    photoActive(4961, 'DSCF4961.RAF')
    local conversations, courante = Moteur.conversations, Moteur.courante
    Moteur.conversations = {}
    local maintenant = os.time()
    -- Deux conversations de plus que la liste n'a de cases : avec l'entrée du carnet et l'en-tête du
    -- jour, elles ne tiennent pas sur une page.
    local nombre = D.cases + 2
    for i = 1, nombre do
        local c = Conversation.nouvelle()
        Conversation.ajouterDemande(c, 'Demande ' .. i)
        -- La 4e porte une balise <EM> dans son titre : Lightroom la lirait comme du texte riche
        -- (une balise seule disparaît, constaté) ; la case et l'en-tête montrent le titre sans elle.
        Conversation.renommer(c, (i == 3 and 'Lac au matin') or (i == 4 and 'Pont <EM>en</EM> automne') or ('Conversation ' .. i))
        c.modifiee = maintenant - (i - 1) * 60
        c.cle = '4961:' .. i .. ':4961'
        Moteur.conversations[#Moteur.conversations + 1] = c
    end
    Moteur.courante = Moteur.conversations[1]
    local ouvrir, ouvertes = Moteur.ouvrir, {}
    Moteur.ouvrir = function(id)
        ouvertes[#ouvertes + 1] = id
        return ouvrir(id)
    end
    local ok, erreur = pcall(ouvrirFenetre, function(p, contenu)
        Fenetre.rafraichir()
        egal('carnet', p.lg1, 'le carnet en première case')
        egal(Carnet.TITRES.carnet, p.lt1)
        egal(Fenetre.SOUS_TITRE_CARNET, p.ls1)
        egal('jour', p.lg2)
        egal("Aujourd'hui", p.lt2)
        egal('conversation', p.lg3)
        egal('Conversation 1', p.lt3)
        vrai(p.ls3:match('^%d+ h %d%d · 1 photo$'), p.ls3)
        egal('Conversation 1', p.li3, "l'infobulle : le titre entier")
        -- La case choisie : la conversation montrée ; son fond, son titre en gras.
        egal(true, p.lc3)
        egal(Moteur.courante.id, Fenetre.choixListe())
        local fond, gras, normal
        for _, v in ipairs(vues(contenu)) do
            local vis = v.args.visible
            if v.genre == 'picture' and type(v.args.value) == 'string' and v.args.value:match('/selection%.png$') and S.cles(vis)[1] == 'lc3' then
                fond = v
            elseif v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.key == 'lt3' and type(vis) == 'table' then
                if v.args.font.name == '<system/bold>' and v.args.font.size == 12 then
                    gras = v
                elseif v.args.font.name == '<system>' and v.args.font.size == 12 then
                    normal = normal or v
                end
            end
        end
        vrai(S.montree(fond, p) and S.montree(gras, p) and not S.montree(normal, p), 'choisie : fond et gras')
        -- Un titre à balise : sans elle dans la case, son infobulle et l'en-tête, une fois ouverte.
        local pont = Moteur.conversations[4]
        egal(pont.id, Fenetre.cases[6].value)
        egal('Pont en automne', p.lt6, 'la case, sans balise')
        egal('Pont en automne', p.li6, "l'infobulle, sans balise")
        S.cliquer(calqueCase(contenu, 6))
        egal(pont, Moteur.courante)
        Fenetre.rafraichir()
        egal('Pont en automne', p.titre, "l'en-tête, sans balise")
        -- Un clic sur une autre conversation : Moteur.ouvrir, elle devient la choisie.
        local lac = Moteur.conversations[3]
        S.cliquer(calqueCase(contenu, 5))
        egal(lac.id, ouvertes[#ouvertes], 'Moteur.ouvrir')
        egal(lac, Moteur.courante)
        egal(lac.id, Fenetre.choixListe())
        vrai(not S.montree(fond, p), 'l\'ancienne case n\'est plus choisie')
        -- Pendant que Claude travaille : refusé, le bandeau le dit.
        Moteur.travaille = true
        local avant = #ouvertes
        S.cliquer(calqueCase(contenu, 3))
        Moteur.travaille = false
        egal(avant, #ouvertes, 'refusé pendant le travail')
        egal(lac, Moteur.courante)
        egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
        p.message = ''
        -- Un en-tête ou une case vide : rien.
        S.cliquer(calqueCase(contenu, 2))
        egal(avant, #ouvertes)
        -- Pages : les conversations, l'entrée du carnet et l'en-tête ne tiennent pas dans les cases
        -- de la liste ; « Plus anciennes… » dans la dernière.
        local derniere = D.cases
        egal('plus', p['lg' .. derniere])
        egal('Plus anciennes…', p['lt' .. derniere])
        S.cliquer(calqueCase(contenu, derniere))
        egal(2, Fenetre.pageListe)
        egal('plus', p.lg1)
        egal('Plus récentes…', p.lt1)
        egal(avant, #ouvertes, 'changer de page n\'ouvre rien')
        -- La recherche ramène à la première page (ici, encore deux pages de résultats), et filtre.
        local recherche = liee(contenu, 'edit_field', 'recherche')
        S.taper(recherche, 'Conversation')
        egal(1, Fenetre.pageListe, 'la recherche ramène à la première page')
        egal('plus', p['lg' .. derniere], 'deux pages de résultats')
        p.recherche = ''
        S.taper(recherche, 'lac')
        egal(1, Fenetre.pageListe)
        local trouvees = {}
        for k = 1, D.cases do
            if p['lg' .. k] == 'conversation' then
                trouvees[#trouvees + 1] = p['lt' .. k]
            end
        end
        egal('Lac au matin', table.concat(trouvees, ' '))
        p.recherche = ''
        -- Sur la page du carnet, c'est son entrée qui est choisie (Fenetre.vue).
        avec(Fenetre, 'lireCarnet', function() end, function()
            S.cliquer(calqueCase(contenu, 1))
            S.taches[#S.taches]()
        end)
        egal('carnet', Fenetre.vue)
        egal(true, p.lc1)
        egal(Fenetre.CARNET, Fenetre.choixListe())
        Fenetre.quitterCarnet()
        Fenetre.rafraichirListe()
        egal(false, p.lc1)
        egal(lac.id, Fenetre.choixListe())
        -- Nouvelle conversation depuis la 2e page : elle est en tête de la liste, la première page
        -- revient, et c'est elle qui est choisie.
        S.cliquer(calqueCase(contenu, derniere))
        egal(2, Fenetre.pageListe)
        S.cliquer(parTitre(contenu, '＋ Nouvelle conversation'))
        egal(1, Fenetre.pageListe, 'Nouvelle conversation : la première page')
        vrai(Moteur.courante ~= lac, 'une nouvelle conversation')
        Fenetre.rafraichir()
        egal(Moteur.courante.id, Fenetre.choixListe(), 'la nouvelle, choisie')
    end)
    Moteur.ouvrir, Moteur.conversations, Moteur.courante, Moteur.travaille = ouvrir, conversations, courante, false
    Fenetre.vue = 'conversation'
    assert(ok, erreur)
end)

-- Légende de la photo active ---------------------------------------------------------------------------

essai('Légende : nom de la copie, appareil et date de prise de vue (heure locale, mois courts), lus seulement quand la photo active change', function()
    local photo = photoActive(4961, '20200710_193347.jpg')
    photo.copie, photo.appareil, photo.prise = 'Essai', 'X-T20', os.time({ year = 2020, month = 7, day = 10, hour = 19, min = 33, sec = 47 })
    local l = Lightroom.legende(4961)
    egal('20200710_193347.jpg', l.nom)
    egal('Essai', l.copie)
    egal('X-T20', l.appareil)
    egal('10 juil. 2020', l.date)
    egal('<EM>20200710_193347.jpg (Essai)</EM> · X-T20 · 10 juil. 2020', Fenetre.texteLegende(l))
    egal('20200710_193347.jpg (Essai)', Fenetre.nomPhoto(l))
    -- Ce qui manque ne se dit pas ; une balise dans un nom est retirée.
    egal('<EM>a.jpg</EM>', Fenetre.texteLegende({ nom = 'a.jpg' }))
    egal('<EM>b.jpg</EM> · X100', Fenetre.texteLegende({ nom = '<EM>b.jpg', appareil = 'X100' }))
    S.photoActive = nil
    egal(nil, next(Lightroom.legende(1)), 'aucune photo : une table vide')
    -- Dans la fenêtre : lue une fois par photo active, jamais par Lightroom.photos (toutes les 2 s).
    photoActive(4961, '20200710_193347.jpg')
    S.photoActive.copie, S.photoActive.appareil, S.photoActive.prise = 'Essai', 'X-T20', photo.prise
    local lues, cles = 0, {}
    local legende = Lightroom.legende
    Lightroom.legende = function(id)
        lues = lues + 1
        return legende(id)
    end
    local lire = S.photoActive.getFormattedMetadata
    S.photoActive.getFormattedMetadata = function(self, cle)
        cles[#cles + 1] = cle
        return lire(self, cle)
    end
    Moteur.nouvelle()
    local ok, erreur = pcall(ouvrirFenetre, function(p)
        egal(1, lues, 'lue à l\'ouverture')
        egal('<EM>20200710_193347.jpg (Essai)</EM> · X-T20 · 10 juil. 2020', p.legendeApercu)
        egal('Active : <EM>20200710_193347.jpg (Essai)</EM> · Sélection : <EM>1</EM>', p.infoPhoto)
        cles = {}
        Fenetre.majPhoto()
        Fenetre.majPhoto()
        egal(1, lues, 'la même photo : pas relue')
        egal('fileName fileName', table.concat(cles, ' '), 'Lightroom.photos ne lit que le nom, une fois par relecture')
        -- Agrandir la photo active : le titre de sa fenêtre est la légende sans ses balises (un
        -- titre de fenêtre n'est pas un texte riche).
        local dossier = S.home .. '/agrandir-legende'
        S.executer('mkdir -p ' .. S.q(dossier) .. ' && /usr/bin/sips -s format jpeg -z 60 90 '
            .. S.q(S.plugin .. '/' .. require('Dispositions').imageVide('claire')) .. ' --out ' .. S.q(dossier .. '/active.jpg') .. ' >/dev/null 2>&1')
        Fenetre.apercuActif = { id = 4961, dossier = dossier, fichier = 'active.jpg', chemin = dossier .. '/active.jpg', T = Fenetre.T }
        Fenetre.voirActive = true
        local taches, dialogues = #S.taches, #S.dialogues
        Fenetre.agrandir()
        egal(taches + 1, #S.taches, 'dans une tâche')
        S.taches[taches + 1]()
        egal(dialogues + 1, #S.dialogues, 'la fenêtre de la photo en grand')
        egal('Claude · 20200710_193347.jpg (Essai) · X-T20 · 10 juil. 2020', S.dialogues[#S.dialogues].title)
        photoActive(4962, 'DSCF4962.RAF')
        Fenetre.majPhoto()
        egal(2, lues, 'une autre photo : lue')
        egal('<EM>DSCF4962.RAF</EM>', p.legendeApercu)
    end)
    Lightroom.legende = legende
    assert(ok, erreur)
end)

-- Apparence -------------------------------------------------------------------------------------------

essai('Apparence : couleurs et images reprises à chaque ouverture, de la préférence ; jamais une image écrite en dur', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local function controler(apparence, contenu)
        local attendu = Chemins.ressource(Dispositions.APPARENCES[apparence == 'sombre' and 2 or 1].dossier) .. '/'
        local images = 0
        for _, v in ipairs(vues(contenu)) do
            for _, cle in ipairs({ 'value', 'image_name' }) do
                local x = v.args[cle]
                if (v.genre == 'picture' or cle == 'image_name') and type(x) == 'string' then
                    egal(attendu, x:sub(1, #attendu), apparence .. ' : ' .. x)
                    vrai(not x:sub(#attendu + 1):find('/', 1, true), apparence .. ' : dans le jeu même : ' .. x)
                    images = images + 1
                end
            end
        end
        vrai(images > 40, apparence .. ' : images posées (' .. images .. ')')
    end
    for _, apparence in ipairs({ 'sombre', 'claire' }) do
        prefs.apparence = apparence
        ouvrirFenetre(function(p, contenu)
            egal(apparence, Fenetre.apparence)
            local hex = Dispositions.PALETTES[apparence].fondContenu
            local c = Fenetre.COULEURS.fondContenu
            egal(tonumber(hex:sub(1, 2), 16), math.floor(c.r * 255 + 0.5), apparence .. ' : fond du contenu')
            egal(Dispositions.PALETTES[apparence].titreInactif:lower(), string.format('%02x%02x%02x', math.floor(Fenetre.COULEURS.titreInactif.r * 255 + 0.5),
                math.floor(Fenetre.COULEURS.titreInactif.g * 255 + 0.5), math.floor(Fenetre.COULEURS.titreInactif.b * 255 + 0.5)))
            controler(apparence, contenu)
            vrai(p.imageApercu:find(Dispositions.imageVide(apparence), 1, true), apparence .. ' : ' .. p.imageApercu)
        end)
    end
    -- Une valeur inconnue : la claire.
    prefs.apparence = 'violette'
    ouvrirFenetre(function()
        egal('claire', Fenetre.apparence)
    end)
    prefs.apparence = 'claire'
    -- Les anciennes clés de couleur ont leurs noms de palette (dany → bleu, vert → coche).
    egal(nil, Fenetre.COULEURS.dany)
    egal(nil, Fenetre.COULEURS.vert)
    for _, ic in ipairs(Fenetre.ICONES) do
        vrai(Fenetre.COULEURS[ic.couleur], 'icône ' .. ic.cle .. ' : ' .. ic.couleur)
    end
    for _, st in ipairs(Fenetre.STYLES) do
        vrai(Fenetre.COULEURS[st.couleur], 'style : ' .. st.couleur)
    end
    for _, teinte in ipairs(Fenetre.TEINTES_NOTE) do
        vrai(Fenetre.COULEURS[teinte], 'note : ' .. teinte)
    end
    for etat, teinte in pairs(Fenetre.COULEURS_NOTE) do
        vrai(Fenetre.COULEURS[teinte], 'état ' .. etat .. ' : ' .. teinte)
    end
end)

essai('Ouverture : chaque clé liée a sa valeur avant l\'ouverture ; tout clic sur un texte passe par un calque ou un texte cliquable connu', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        -- Rien n'est rafraîchi ici : les valeurs posées avant presentFloatingDialog.
        for _, v in ipairs(vues(contenu)) do
            for cle, x in pairs(v.args) do
                if type(cle) == 'string' and type(x) == 'table' and x.liaison then
                    for _, k in ipairs(S.cles(x)) do
                        vrai((x.bind_to_object or p)[k] ~= nil, v.genre .. '.' .. cle .. ' : ' .. k .. ' sans valeur')
                    end
                end
            end
            if v.genre == 'static_text' and v.args.mouse_down then
                local t = v.args.title
                local cle = type(t) == 'table' and t.key or ''
                vrai(Fenetre.parCalque(v.args.mouse_down) or cle:match('^t%d+$') or cle == 'texteLightroom' or cle == 'texteEcran'
                    or cle == 'aide' or cle == 'jointes', 'clic hors d\'un calque : ' .. tostring(cle))
            end
            vrai(v.genre ~= 'picture' or v.args.mouse_down == nil, 'clic sur une image')
        end
    end)
end)

-- Fil (lot B4) ---------------------------------------------------------------------------------------

local Fil = require 'Fil'
local Json = require 'Json'
local Metriques = require 'Metriques'
local Texte = require 'Texte'

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

-- 19 h 42, le 21 octobre 2026, à l'heure locale.
local T0 = os.time({ year = 2026, month = 10, day = 21, hour = 19, min = 42, sec = 0 })

local function outil(c, id, nom, entree, date)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__' .. nom,
        entree = entree or {} } } }, date)
end

local function reponse(c, id, valeur, date)
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id,
        textes = { type(valeur) == 'string' and valeur or Json.encode(valeur) }, images = {}, erreur = false } } }, date)
end

local function texteClaude(c, texte, date)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'texte', texte = texte } } }, date)
end

-- Une conversation comme celle de la maquette : Dany demande la retouche (19 h 42) ; Claude regarde,
-- écrit l'étape « tons et balance » (deux réglages, son etape_id) et le dit (19 h 43) ; Dany demande la
-- note (19 h 46) ; Claude note la photo active et une autre, puis donne la leçon, et l'explique.
local function conversationMaquette()
    local c = Conversation.nouvelle(T0)
    c.titre, c.titreChoisi = 'Orage sur le camping', true
    Conversation.ajouterDemande(c, "Retouche la photo active, rendu naturel. Garde l'orage menaçant.", T0)
    outil(c, 'v1', 'view_photo', { size = 1568, photo_id = 4961 }, T0 + 60)
    reponse(c, 'v1', '{}', T0 + 61)
    outil(c, 'a1', 'apply_settings', { photo_id = 4961, step_name = 'tons et balance', reason = 'Dominante chaude : des blancs neutres.',
        settings = { Temperature = 5600, Highlights2012 = -38 } }, T0 + 62)
    reponse(c, 'a1', { mode = 'appliquer directement', resultats = Json.tableau({ { photo = { id = 4961, fichier = 'DSCF4961.RAF' },
        etape = 'Claude · tons et balance', etape_id = 'E1', remarques = Json.tableau(), changements = Json.tableau({
            { cle = 'Temperature', avant = 5200, apres = 5600, libelle = 'Température' },
            { cle = 'Highlights2012', avant = 0, apres = -38, libelle = 'Hautes lumières' } }) } }) }, T0 + 63)
    texteClaude(c, "La dominante était nettement chaude : Température −9 et Teinte +3 rendent le bleu de l'orage. "
        .. "Les hautes lumières à −38 rendent leur texture aux nuages.", T0 + 64)
    Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = '' }, T0 + 65)
    Conversation.ajouterDemande(c, 'Noter la photo active', T0 + 240)
    outil(c, 'n1', 'propose_ratings', { pass = 2, ratings = {
        { photo_id = 4961, rating = 3, reason = 'Tient seule.', criteria = { impact = 'Moyen', qualities = 'Lumière', technical_floor = 'Nette' } },
        { photo_id = 4962, rating = 2, reason = 'Correcte.', criteria = { impact = 'Faible', qualities = 'Fond', technical_floor = 'Douce' } },
    } }, T0 + 241)
    reponse(c, 'n1', { propositions = Json.tableau({ { photo = 4961, fichier = 'DSCF4961.RAF', note_avant = 0, drapeau_avant = 'aucun', etat = 'proposee' },
        { photo = 4962, fichier = 'DSCF4962.RAF', note_avant = 0, drapeau_avant = 'aucun', etat = 'proposee' } }), refusees = Json.tableau() }, T0 + 242)
    outil(c, 'l1', 'photo_lesson', { photo_id = 4961, points = {
        { axis = 'light', missing = 'Ciel brûlé à 3 %.', at_capture = 'Compenser de −2/3 IL.' },
        { axis = 'color', missing = 'Dominante chaude.', at_capture = 'Balance des blancs Lumière du jour.' },
        { axis = 'composition', at_capture = 'Les tentes au tiers bas.' },
    } }, T0 + 243)
    reponse(c, 'l1', { lecon = { photo = 4961, fichier = 'DSCF4961.RAF', rangee = true, remplacee = false, mois = '2026-10' },
        remarques = Json.tableau() }, T0 + 244)
    texteClaude(c, "Je propose 3 ★ : la photo tient seule. Pas 4 ★ : le feuillage bougé se voit à 100 %.", T0 + 245)
    Conversation.appliquer(c, { genre = 'fin', reussie = true, interrompue = false, session = '' }, T0 + 246)
    return c
end

-- L'indice de l'élément de ce genre (et de cet appel) dans le fil.
local function elementDe(c, genre, appel)
    for i, e in ipairs(c.elements) do
        if e.genre == genre and (appel == nil or e.appel == appel) then
            return i
        end
    end
    error('élément introuvable : ' .. genre, 2)
end

-- Les balises d'un texte, fermées sur sa ligne.
local function balisesFermees(texte)
    local ouverte = false
    for fin in texte:gmatch('<(/?)EM>') do
        vrai(ouverte == (fin == '/'), 'balise mal fermée : ' .. texte)
        ouverte = fin == ''
    end
    vrai(not ouverte, 'balise ouverte en fin de ligne : ' .. texte)
end

essai('Polices : Metriques mesure la police du système (13, 12, 11, gras 13 et 12, titre 16) et Menlo 11 ; Fenetre.POLICES les suit', function()
    local attendues = {
        texte = { '<system>', 13 }, texte12 = { '<system>', 12 }, petit = { '<system>', 11 }, gras = { '<system/bold>', 13 },
        gras12 = { '<system/bold>', 12 }, gras11 = { '<system/bold>', 11 }, titre = { '<system/bold>', 16 }, mono = { 'Menlo', 11 },
    }
    for cle, a in pairs(attendues) do
        local m = Metriques[cle]
        vrai(m, 'Metriques.' .. cle)
        egal(a[1], m.nom, cle)
        egal(a[2], m.taille, cle)
        -- La police de la fenêtre est celle mesurée (D9 : tailles appliquées, l'encre à 1 ou 2 points sous
        -- la chasse, S.ENCRE_SOUS_CHASSE).
        egal(m.nom, Fenetre.POLICES[cle].name, 'POLICES.' .. cle)
        egal(m.taille, Fenetre.POLICES[cle].size, 'POLICES.' .. cle)
        -- Les caractères des boutons de la fenêtre B, mesurés (pas comptés comme « M »).
        for _, c in ipairs({ '＋', '⊗', '⤢', '☆', '★', '⚑' }) do
            vrai(type(m.chasse[c]) == 'number', cle .. ' : ' .. c .. ' non mesuré')
        end
    end
    egal(Fenetre.POLICES.systeme12.name, Fenetre.POLICES.texte12.name)
    egal(Fenetre.POLICES.systeme12.size, Fenetre.POLICES.texte12.size)
    -- Le gras 11 (en-têtes de jour, passe en cours de la carte Note) est mesuré depuis le lot B5.
    egal(Fenetre.POLICES.gras11.name, Fenetre.POLICES.systemeGras11.name)
    egal(11, Fenetre.POLICES.systemeGras11.size)
    vrai(Fil.largeur('Monter à 4 ?', 'gras11') < Fil.largeur('Monter à 4 ?', 'gras12'), 'gras 11 sous gras 12')
    vrai(Fil.largeur('Monter à 4 ?', 'gras11') > Fil.largeur('Monter à 4 ?', 'petit'), 'gras 11 plus large que le petit')
    egal(1, S.ENCRE_SOUS_CHASSE.min)
    -- La chasse du système en 12 est plus étroite qu'en 13, le gras plus large.
    vrai(Fil.largeur('Leçon de la photo', 'texte12') < Fil.largeur('Leçon de la photo', 'texte'), '12 sous 13')
    vrai(Fil.largeur('Leçon de la photo', 'gras') > Fil.largeur('Leçon de la photo', 'texte'), 'gras plus large')
end)

essai('Texte riche : Fil.largeur ignore les balises et mesure la partie balisée dans son emphase ; Fil.couper ne coupe jamais une balise, la ferme et la rouvre', function()
    egal(Fil.largeur('apply_settings', 'mono') + Fil.largeur('  étape', 'texte12'),
        Fil.largeur('<EM>apply_settings</EM>  étape', 'texte12', 'mono'), 'nom en Menlo, description en 12')
    egal(Fil.largeur('Lumière', 'texte12'), Fil.largeur('<EM>Lumière</EM>', 'texte12'), 'sans emphase : la police du texte')
    egal('Lumière', Fil.sansBalises('<EM>Lumière</EM>'))
    -- Un passage balisé plus long qu'une ligne : chaque ligne aux balises fermées, la suite rouverte.
    local texte = '<EM>' .. string.rep('Lumière du soir sur le lac ', 8) .. '</EM> et la suite du texte ordinaire.'
    local lignes, ouvert = Fil.couper(texte, 200, 'texte12', nil, 'gras12')
    vrai(#lignes >= 3, #lignes .. ' lignes')
    egal(false, ouvert, 'fermé à la fin')
    for k, l in ipairs(lignes) do
        balisesFermees(l)
        vrai(Fil.largeur(l, 'texte12', 'gras12') <= 200, 'dans la largeur : ' .. l)
        if k < #lignes then
            egal('<EM>', l:sub(1, 4), 'rouverte : ' .. l)
        end
    end
    vrai(lignes[#lignes]:find('</EM> et', 1, true) or lignes[#lignes]:find('ordinaire', 1, true), lignes[#lignes])
    -- Un mot balisé coupé au caractère : jamais au milieu d'une balise.
    for _, l in ipairs((Fil.couper('<EM>' .. string.rep('W', 60) .. '</EM>', 120, 'texte12', nil, 'gras12'))) do
        balisesFermees(l)
        vrai(not l:find('<E[^M]') and not l:find('</?E?$'), 'balise coupée : ' .. l)
    end
    -- Un paragraphe laissé ouvert (fin de paragraphe d'une carte) : le suivant commence rouvert.
    local suite = Fil.couper('suite en gras</EM> puis normal', 400, 'texte12', nil, 'gras12', true)
    egal('<EM>suite en gras</EM> puis normal', suite[1])
    local carte = Fenetre.lignesCarte('<EM>Axe\nsur deux lignes</EM>\nnormal', 300, 'texte12', 'gras12')
    egal('<EM>Axe</EM>', carte[1])
    egal('<EM>sur deux lignes</EM>', carte[2])
    egal('normal', carte[3])
end)

essai('Fil : auteur sur la première ligne de chaque tour, heure sur la suivante (vide comprise), sur des copies ; le cache ne bouge pas', function()
    local c = conversationMaquette()
    local cache = {}
    local lignes = Fil.lignes(c, D.texteFil, cache)
    local tours = {}
    for k, l in ipairs(lignes) do
        if l.auteur then
            tours[#tours + 1] = l.auteur .. '@' .. k .. ':' .. tostring(lignes[k + 1] and lignes[k + 1].heure)
        end
        vrai(not (l.auteur and l.heure), 'auteur et heure sur deux lignes')
    end
    egal(4, #tours, 'deux demandes, deux tours de Claude : ' .. table.concat(tours, ' '))
    egal('dany', lignes[1].auteur)
    egal('19 h 42', lignes[2].heure)
    vrai(tours[2]:match('^claude@%d+:19 h 43$'), tours[2])
    vrai(tours[3]:match('^dany@%d+:19 h 46$'), tours[3])
    vrai(tours[4]:match('^claude@%d+:19 h 46$'), tours[4])
    -- Les outils, l'aperçu et le texte de Claude sont un seul tour : un seul « Claude » entre deux demandes.
    local claude = 0
    for _, l in ipairs(lignes) do
        claude = claude + (l.auteur == 'claude' and 1 or 0)
    end
    egal(2, claude)
    -- Deux rafraîchissements de suite, cache compris : mêmes auteurs, mêmes heures, mêmes lignes ;
    -- les lignes gardées n'en portent jamais.
    local encore = Fil.lignes(c, D.texteFil, cache)
    egal(#lignes, #encore)
    for k, l in ipairs(lignes) do
        egal(tostring(l.auteur) .. tostring(l.heure) .. l.texte, tostring(encore[k].auteur) .. tostring(encore[k].heure) .. encore[k].texte, 'ligne ' .. k)
    end
    for _, garde in pairs(cache) do
        for _, l in ipairs(garde.lignes) do
            vrai(l.auteur == nil and l.heure == nil, 'le cache garde une ligne sans auteur ni heure : ' .. l.texte)
        end
    end
    -- Le dernier tour d'une seule ligne : une ligne vide de plus, pour son heure.
    local d = Conversation.nouvelle(T0)
    Conversation.ajouterDemande(d, 'Bonjour', T0)
    local seules = Fil.lignes(d, D.texteFil)
    egal(2, #seules)
    egal('vide', seules[2].genre)
    egal('19 h 42', seules[2].heure)
    -- Deux demandes de suite (sans réponse) : deux tours.
    Conversation.ajouterDemande(d, 'Encore', T0 + 60)
    local deux = Fil.lignes(d, D.texteFil)
    egal('dany', deux[1].auteur)
    egal('dany', deux[3].auteur)
    egal('19 h 43', deux[4].heure)
end)

essai("Fil : la ligne d'un appel (texte riche, nom en Menlo) ; une étape porte `etape` et laisse la place de « Pourquoi ? » ; aucune ligne au-delà de sa largeur, balises fermées ; outils en Menlo", function()
    local c = conversationMaquette()
    local lignes = Fil.lignes(c, D.texteFil)
    local appels, etapes = {}, {}
    for _, l in ipairs(lignes) do
        balisesFermees(l.texte)
        vrai(Fil.occupe(l) <= D.texteFil - Fil.MARGE, string.format('hors de la largeur (%.0f) : %s', Fil.occupe(l), l.texte))
        if l.genre == 'appel' then
            appels[#appels + 1] = l.texte
            if l.etape then
                etapes[#etapes + 1] = l.texte
                vrai(Fil.occupe(l) <= D.texteFil - Fil.MARGE - Fil.PLACE_POURQUOI, 'la place du bouton : ' .. l.texte)
            end
        else
            vrai(not l.texte:find('<EM>', 1, true), 'balise hors d\'une ligne d\'appel : ' .. l.texte)
            vrai(not l.etape, 'Pourquoi ? hors d\'une ligne d\'appel')
        end
    end
    egal('<EM>view_photo</EM>  photo ' .. Texte.nombre(4961), appels[1])
    egal('<EM>apply_settings</EM>  étape « Claude · tons et balance » · 2 réglages', etapes[1])
    egal(1, #etapes, 'une seule étape')
    -- Les lignes des notes restent en Menlo, sans retrait d'icône ; le titre de la notation en a un.
    local notes = 0
    for _, l in ipairs(lignes) do
        if l.genre == 'outil' then
            notes = notes + 1
            egal('mono', Fil.polices.outil)
            egal(0, Fil.retrait('outil'))
        end
    end
    egal(2, notes, 'une ligne Menlo par photo notée')
    egal(Fil.RETRAIT_ICONE, Fil.retrait('appel'))
    egal(Fil.RETRAIT_ICONE, Fil.retrait('proposition'))
    -- Une description trop longue : coupée par « … », le nom gardé ; un nom seul trop long aussi.
    local long = { genre = 'outil', outil = 'apply_settings', etat = 'fait', texte = 'apply_settings · ' .. string.rep('très long ', 40) }
    local l = Fil.lignesElement(long, 1, 300)[1]
    egal(1, (l.texte:find('<EM>apply_settings</EM>  ', 1, true)), l.texte)
    vrai(l.texte:sub(-#'…') == '…', l.texte)
    vrai(Fil.occupe(l) <= 300, 'dans 300 points')
    egal('<EM>' .. string.rep('x', 3) .. '…</EM>', Fil.uneLigneOutil(string.rep('x', 200), 'description', Fil.largeur('xxx…', 'mono')))
    -- Une balise venue de Claude ne passe pas : texte, step_name, description.
    local balise = { genre = 'outil', outil = 'apply_settings', etat = 'fait', texte = 'apply_settings · <EM>essai' }
    egal('<EM>apply_settings</EM>  essai', Fil.lignesElement(balise, 1, 500)[1].texte)
    local claude = Fil.lignesElement({ genre = 'claude', texte = 'Un <EM>mot</EM> en gras ?' }, 1, 500)
    egal('Un mot en gras ?', claude[1].texte)
end)

essai("Fil : le tour de Claude qui a noté et donné la leçon finit par une ligne d'actions, les deux boutons, après son texte (maquette) ; un tour chacun, une ligne chacun", function()
    local c = conversationMaquette()
    local n, l = elementDe(c, 'notation'), elementDe(c, 'lecon')
    local lignes = Fil.lignes(c, D.texteFil)
    local actions = {}
    for k, x in ipairs(lignes) do
        if x.genre == 'actions' then
            actions[#actions + 1] = x.actions .. ':' .. tostring(x.notation) .. ':' .. tostring(x.lecon) .. '@' .. k
        end
    end
    egal('les deux:' .. n .. ':' .. l .. '@' .. #lignes, table.concat(actions, ' '), 'une ligne, à la fin du tour')
    contient(lignes[#lignes - 1].texte, 'feuillage', 'après le texte de Claude')
    -- Une demande entre les notes et la leçon : deux tours, une ligne d'actions chacun.
    local d = conversationMaquette()
    local m = elementDe(d, 'notation')
    table.insert(d.elements, m + 1, { id = 'entre', genre = 'dany', texte = 'Et la leçon ?', date = T0 + 242, images = {}, changements = {} })
    actions = {}
    for _, x in ipairs(Fil.lignes(d, D.texteFil)) do
        if x.genre == 'actions' then
            actions[#actions + 1] = x.actions
        end
    end
    egal('note lecon', table.concat(actions, ' '))
    -- Une notation refusée, ou en cours : pas de « Voir la note ».
    d.elements[m].etat = 'erreur'
    for _, x in ipairs(Fil.lignes(d, D.texteFil)) do
        vrai(x.actions ~= 'note' and x.actions ~= 'les deux', 'notation refusée : ' .. tostring(x.actions))
    end
end)

-- La ligne i de la grille qui montre ce test, et la ligne.
local function ligneDeLaGrille(test)
    for i = 1, Fenetre.T.lignes do
        local l = Fenetre.lignes[Fenetre.premiere + i - 1]
        if l and test(l) then
            return i, l
        end
    end
    error('ligne introuvable dans la grille', 2)
end

-- Le bouton de ce titre posé sur la ligne i (sa condition porte sur `cle..i`), montré.
local function boutonDeLigne(contenu, titre, cle, i)
    for _, v in ipairs(vues(contenu)) do
        if S.BOUTONS[v.genre] and v.args.title == titre and type(v.args.visible) == 'table'
            and table.concat(S.cles(v.args.visible), ' ') == cle .. i and S.montreeDansFenetre(v) then
            return v
        end
    end
    error('« ' .. titre .. ' » montré introuvable sur la ligne ' .. i, 2)
end

essai("Fil dans la fenêtre : une ligne de 21 (auteur 60, écart 12, puis le texte) ; auteur et heure aux bonnes lignes ; « Pourquoi ? » et les actions aux seules bonnes lignes ; aucun refus de texte riche", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = conversationMaquette()
    Moteur.courante = c
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        egal(D.texteFil, Fenetre.largeurTexte(), 'D.fil − 60 − 12')
        egal(D.fil - D.auteur - D.ecartAuteur, D.texteFil)
        -- La grille : D.lignes rangées de D.hauteurLigne dans la colonne de D.grille, sous la marge.
        local grille
        for _, v in ipairs(vues(contenu)) do
            if v.genre == 'column' and v.args.height == D.grille then
                grille = v
            end
        end
        vrai(grille, 'la grille')
        local rangees = 0
        for _, r in ipairs(grille.args) do
            if type(r) == 'table' and r.genre == 'row' then
                rangees = rangees + 1
                egal(D.hauteurLigne, r.args.height, 'une ligne de 21')
                egal(D.fil, largeurDonnee(r), 'auteur, écart et texte : la largeur du fil')
                vrai(hauteur(r) <= D.hauteurLigne, 'son contenu y tient')
            end
        end
        egal(D.lignes, rangees)
        -- Les colonnes : « Vous », « Claude », l'heure ; chaque variante de texte à sa largeur.
        local vous = parTitre(contenu, 'Vous', 'static_text')
        egal(Fenetre.COULEURS.bleu, vous.args.text_color)
        egal(Fenetre.POLICES.gras12, vous.args.font)
        egal(D.auteur, vous.args.width)
        -- Ce que montre la grille, ligne par ligne.
        local montres = {}
        for i = 1, D.lignes do
            local l = Fenetre.lignes[Fenetre.premiere + i - 1]
            if l then
                local auteur = l.auteur or (l.heure and 'heure') or ''
                egal(auteur, p['a' .. i], 'auteur de la ligne ' .. i)
                egal(l.heure or '', p['h' .. i])
                egal(l.etape == true, p['q' .. i], 'Pourquoi ? de la ligne ' .. i)
                egal(l.actions or '', p['x' .. i], 'actions de la ligne ' .. i)
                if auteur ~= '' then
                    montres[#montres + 1] = auteur .. (auteur == 'heure' and ('=' .. p['h' .. i]) or '')
                end
            end
        end
        egal('dany heure=19 h 42 claude heure=19 h 43 dany heure=19 h 46 claude heure=19 h 46', table.concat(montres, ' '))
        -- « Pourquoi ? » montré sur la seule ligne d'étape ; les actions sur la seule ligne d'actions.
        local pourquoi, actions = 0, 0
        for _, v in ipairs(vues(contenu)) do
            if S.BOUTONS[v.genre] and v.args.title == 'Pourquoi ?' then
                egal('square_button', v.genre)
                egal('small', v.args.size)
                egal(15, S.bezelVisible(v), 'bezel de 15 dans une case de 21 (D6)')
                egal(D.pourquoi, v.args.width)
                vrai(D.pourquoi <= Fil.PLACE_POURQUOI, 'la place gardée à droite')
                pourquoi = pourquoi + (S.montreeDansFenetre(v) and 1 or 0)
                local rangee = rangeeDe(contenu, v)
                egal(D.texteFil - D.pourquoi, rangee.args.margin_left, 'poussé à droite dans sa rangée (D6)')
            elseif S.BOUTONS[v.genre] and (v.args.title == '☆ Voir la note' or v.args.title == 'Leçon de la photo') then
                egal('square_button', v.genre)
                vrai(S.bezelVisible(v) + S.MARGE_BEZEL <= D.hauteurLigne, 'dans sa ligne')
                actions = actions + (S.montreeDansFenetre(v) and 1 or 0)
            end
        end
        egal(1, pourquoi, 'un seul « Pourquoi ? » montré')
        egal(2, actions, '« ☆ Voir la note » et « Leçon de la photo » sur une ligne')
        -- Les textes : celui d'un appel garde ses balises (Menlo en emphase) ; les autres variantes de la
        -- même ligne le reçoivent sans balise (la simulation refuserait <EM> sans emphasis_font).
        local i = ligneDeLaGrille(function(l) return l.etape end)
        egal('appel', p['g' .. i])
        local balise, sansBalise = 0, 0
        for _, v in ipairs(vues(contenu)) do
            local t = v.args.title
            if v.genre == 'static_text' and type(t) == 'table' and t.key == 't' .. i then
                local montre = S.evaluer(t, p)
                if v.args.emphasis_font then
                    balise = balise + 1
                    egal(p['t' .. i], montre)
                    egal(Fenetre.POLICES.mono, v.args.emphasis_font)
                    egal(Fenetre.POLICES.texte12, v.args.font)
                    egal(D.texteFil - Fil.RETRAIT_ICONE, v.args.width)
                    vrai(S.montreeDansFenetre(v), 'la variante de l\'appel montrée')
                else
                    sansBalise = sansBalise + 1
                    egal(Fil.sansBalises(p['t' .. i]), montre)
                end
            end
        end
        egal(1, balise)
        egal(#Fenetre.STYLES - 1, sansBalise)
        egal(0, #S.refusDeLaFenetre(), 'aucun refus de texte riche')
        -- Deux rafraîchissements : rien ne bouge.
        local avant = {}
        for k = 1, D.lignes do
            avant[k] = p['a' .. k] .. '|' .. p['h' .. k] .. '|' .. p['t' .. k]
        end
        Fenetre.rafraichir()
        for k = 1, D.lignes do
            egal(avant[k], p['a' .. k] .. '|' .. p['h' .. k] .. '|' .. p['t' .. k], 'ligne ' .. k .. ' après un rafraîchissement')
        end
    end)
end)

essai("Fil dans la fenêtre : « Pourquoi ? » (clic) ouvre l'onglet Aperçu sur son étape ; « ☆ Voir la note » l'onglet Note, sans changer la sélection, le bandeau dit de choisir la photo ; « Leçon de la photo » l'onglet Leçon", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = conversationMaquette()
    Moteur.courante = c
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        local champ = liee(contenu, 'edit_field', 'saisie')
        local montrees = {}
        avec(Fenetre, 'montrerEtape', function(element) montrees[#montrees + 1] = element; return true end, function()
            local i, l = ligneDeLaGrille(function(x) return x.etape end)
            S.taper(champ, 'texte tapé')
            S.cliquer(boutonDeLigne(contenu, 'Pourquoi ?', 'q', i))
            egal(nil, Fenetre.envoiAuto, "« Pourquoi ? » n'envoie pas la demande")
            egal(l.element, montrees[1], "l'élément de l'étape")
            egal(elementDe(c, 'outil', 'a1'), montrees[1])
            -- Sur une ligne qui n'est plus une étape (la grille a défilé) : rien.
            egal(false, Fenetre.pourquoi(ligneDeLaGrille(function(x) return x.genre == 'dany' end)))
            egal(1, #montrees)
        end)
        p.saisie = ''
        -- « ☆ Voir la note » : l'onglet Note, comme un vrai clic (son crochet suit), la sélection
        -- inchangée ; la photo active (4961) est parmi les notes : pas de message.
        local selection = S.selection
        local recus = {}
        local i = ligneDeLaGrille(function(x) return x.genre == 'actions' end)
        egal('les deux', p['x' .. i])
        avec(Fenetre.surOnglet, 'notation', function(v) recus[#recus + 1] = v end, function()
            p.onglet = 'apercu'
            S.cliquer(boutonDeLigne(contenu, '☆ Voir la note', 'x', i))
        end)
        egal('notation', p.onglet)
        egal('notation', recus[1], 'un vrai clic : son crochet')
        egal(selection, S.selection, 'la sélection ne change pas')
        egal('', p.message)
        -- La photo active n'est pas notée là : le bandeau le dit, la sélection reste.
        photoActive(4963, 'DSCF4963.RAF')
        local avant = S.selection
        Fenetre.majPhoto()
        p.onglet = 'apercu'
        S.cliquer(boutonDeLigne(contenu, '☆ Voir la note', 'x', i))
        egal('notation', p.onglet)
        egal(Fenetre.NOTE_AUTRE_PHOTO, p.message)
        egal(avant, S.selection, 'jamais de sélection changée par la fenêtre')
        p.message = ''
        -- L'onglet Leçon suit la photo active : 4963 n'a pas de leçon ici.
        egal(Fenetre.AUCUNE_LECON, (p.leconTexte:gsub('\n', ' ')), 'pas de leçon pour la photo active')
        -- « Leçon de la photo » : l'onglet Leçon, sur cette leçon (même d'une autre photo).
        S.cliquer(boutonDeLigne(contenu, 'Leçon de la photo', 'x', i))
        egal('lecon', p.onglet)
        egal(c.elements[elementDe(c, 'lecon')].id, Fenetre.leconChoisie)
        egal('Leçon de la photo · DSCF4961.RAF', p.leconTitre)
        egal(1, (p.leconTexte:find('<EM>Lumière</EM>', 1, true)), p.leconTexte)
        p.onglet = 'notation'
        photoActive(4961, 'DSCF4961.RAF')
    end)
end)

essai('Fil dans la fenêtre : pas de bascule vers Leçon quand une proposition attend ; une fois sinon', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        outil(c, 'p1', 'preview_settings', { photo_id = 4961, settings = { Exposure2012 = 0.3 }, reason = 'Plus clair' })
        Fenetre.rafraichir()
        egal('proposition', p.onglet)
        outil(c, 'l1', 'photo_lesson', { photo_id = 4961, points = { { axis = 'light', missing = 'Sombre.', at_capture = 'Exposer plus.' } } })
        reponse(c, 'l1', { lecon = { photo = 4961, fichier = 'DSCF4961.RAF', rangee = true }, remarques = Json.tableau() })
        Fenetre.rafraichir()
        egal('proposition', p.onglet, 'Accepter reste devant')
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, true)
        outil(c, 'l2', 'photo_lesson', { photo_id = 4961, points = { { axis = 'light', missing = 'Sombre.', at_capture = 'Exposer plus.' } } })
        reponse(c, 'l2', { lecon = { photo = 4961, fichier = 'DSCF4961.RAF', rangee = true }, remarques = Json.tableau() })
        Fenetre.rafraichir()
        egal('lecon', p.onglet, 'sans proposition en attente : la leçon se montre')
        p.onglet = 'notation'
    end)
end)

essai("Fil dans la fenêtre : une conversation vide montre son titre, puis l'aide entière, coupée dans la largeur d'une ligne de note", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal(0, #Fenetre.lignes)
        egal(Fenetre.FIL_VIDE_TITRE, p.t2)
        egal('titre', p.g2)
        local morceaux = {}
        for i = 3, D.lignes do
            if p['t' .. i] ~= '' then
                egal('note', p['g' .. i], 'ligne ' .. i)
                local l = { genre = 'note', texte = p['t' .. i] }
                vrai(Fil.occupe(l) <= D.texteFil - Fil.MARGE, string.format('dans la largeur (%.0f) : %s', Fil.occupe(l), l.texte))
                vrai(not l.texte:find('…', 1, true), 'sans « … » : ' .. l.texte)
                morceaux[#morceaux + 1] = l.texte
            end
        end
        vrai(#morceaux >= 1, 'au moins une ligne : ' .. #morceaux)
        egal(Fenetre.FIL_VIDE, table.concat(morceaux, ' '), "l'aide entière")
        -- Une demande : le fil la montre, l'aide s'en va.
        Conversation.ajouterDemande(Moteur.courante, 'Bonjour')
        Fenetre.rafraichir()
        egal('Bonjour', p.t1)
        for i = 3, D.lignes do
            vrai(p['t' .. i] == '' or p['g' .. i] ~= 'note', "plus d'aide : ligne " .. i)
        end
    end)
end)

essai("Bandeau : deux lignes de petit texte dans la place du menu Modèle ; chaque message de la fenêtre y tient en entier, les autres finissent par « … », l'infobulle les donne", function()
    egal(2, Fenetre.LIGNES_BANDEAU)
    local place = D.bandeau - Fil.MARGE
    -- Les messages de la fenêtre (mesurés par Metriques, en petit), ceux de la carte Note (lot B5),
    -- et les refus du moteur, provoqués ici : Claude au travail, Je le fais sans photo active, une
    -- ancienne séance de notation (raccourcis au lot B5 : ils finissaient par « … »).
    local refus = {}
    local travaille, courante, conversations = Moteur.travaille, Moteur.courante, Moteur.conversations
    local ok, erreur = pcall(function()
        Moteur.travaille = true
        refus[#refus + 1] = select(2, Moteur.envoyer('Bonjour'))
        Moteur.travaille = false
        S.photoActive, S.selection = nil, {}
        Moteur.nouvelle()
        refus[#refus + 1] = select(2, Moteur.jeLeFais())
        local seance = Conversation.nouvelle()
        seance.genre = 'notation'
        Moteur.conversations = { seance }
        refus[#refus + 1] = select(2, Moteur.ouvrir(seance.id))
    end)
    Moteur.travaille, Moteur.courante, Moteur.conversations = travaille, courante, conversations
    assert(ok, erreur)
    -- Le refus d'un envoi pendant le travail est celui des autres refus du moteur (Arrêter compris).
    egal(Fenetre.CLAUDE_TRAVAILLE, refus[1], "le refus d'un envoi, comme les autres")
    egal("Claude travaille : attendez la fin, ou cliquez Arrêter. | Aucune photo active : choisissez-la dans Lightroom. | "
        .. "Une ancienne séance de notation ne s'ouvre plus.", table.concat(refus, ' | '), 'les refus du moteur, raccourcis')
    local messages = { Fenetre.CLAUDE_TRAVAILLE, Fenetre.CHOISIR_CONVERSATION, Fenetre.NOTE_AUTRE_PHOTO, Fenetre.PAS_D_IMAGE,
        Fenetre.EXERCICE_CONTINUE .. Fenetre.LIBELLES_MODE.proposer .. '.', Fenetre.EXERCICE_CONTINUE .. Fenetre.LIBELLES_MODE.appliquer .. '.',
        "Écrivez une demande avant d'envoyer.", Fenetre.NOTE_EN_COURS, Fenetre.AUCUNE_PHOTO, refus[1], refus[2], refus[3] }
    egal(12, #messages, 'chaque message, aucun nil')
    for _, m in ipairs(messages) do
        local montre = Fenetre.texteBandeau(m, D.bandeau)
        egal(m, (montre:gsub('\n', ' ')), 'en entier : ' .. m)
        local lignes = select(2, montre:gsub('\n', '')) + 1
        vrai(lignes <= 2, m .. ' : ' .. lignes .. ' lignes')
        for ligne in (montre .. '\n'):gmatch('([^\n]*)\n') do
            vrai(Fil.largeur(ligne, 'petit') <= place, string.format('%s : %.0f pour %d', ligne, Fil.largeur(ligne, 'petit'), place))
        end
    end
    -- Plus long (une erreur venue d'ailleurs, une aide) : deux lignes, la seconde finie par « … ».
    local long = string.rep("La note n'a pas été posée : la photo DSCF4961.RAF n'est plus celle que Claude a notée, sa proposition est retirée. ", 3)
    local montre = Fenetre.texteBandeau(long, D.bandeau)
    egal(1, select(2, montre:gsub('\n', '')), 'deux lignes')
    egal('…', montre:sub(-#'…'))
    egal('', Fenetre.texteBandeau('', D.bandeau))
    -- Sans largeur donnée, fenêtre fermée (Fenetre.T vide) : la place du bandeau de Dispositions,
    -- celle de la fenêtre agrandie.
    avec(Fenetre, 'T', nil, function()
        egal(montre, Fenetre.texteBandeau(long), 'sans largeur : D.bandeau')
        for _, m in ipairs(messages) do
            egal(m, (Fenetre.texteBandeau(m):gsub('\n', ' ')), 'sans largeur, en entier : ' .. m)
        end
    end)
    -- Les photos jointes : « cliquer pour retirer » reste au bout, les noms se coupent avant (comme
    -- la troncature au milieu d'avant le lot B4).
    local suite = '  ·  cliquer pour retirer'
    egal('1 photo jointe : a.jpg · cliquer pour retirer', (Fenetre.texteBandeau('1 photo jointe : a.jpg', D.bandeau, suite):gsub('\n', ' ')))
    local noms = {}
    for k = 1, 12 do
        noms[k] = 'DSCF49' .. (60 + k) .. '.RAF'
    end
    local jointes = '12 photos jointes : ' .. table.concat(noms, ', ')
    local coupe = Fenetre.texteBandeau(jointes, D.bandeau, suite)
    egal(1, select(2, coupe:gsub('\n', '')), 'deux lignes : ' .. coupe)
    local joint = (coupe:gsub('\n', ' '))
    egal('… · cliquer pour retirer', joint:sub(-#'… · cliquer pour retirer'), coupe)
    egal(1, (joint:find('12 photos jointes : DSCF49', 1, true)), coupe)
    for ligne in (coupe .. '\n'):gmatch('([^\n]*)\n') do
        vrai(Fil.largeur(ligne, 'petit') <= place, ligne)
    end
    -- Dans la fenêtre : trois variantes de deux lignes, petites, à la largeur du bandeau.
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local message = liee(contenu, 'static_text', 'message')
        egal(2, message.args.height_in_lines)
        egal(Fenetre.POLICES.petit, message.args.font)
        egal(nil, message.args.truncation, 'pas de troncature sur deux lignes : la coupe est faite')
        p.message = long
        egal(montre, S.evaluer(message.args.title, p))
        egal(long, valeur(message, 'tooltip', p), "l'infobulle, en entier")
        vrai(S.montreeDansFenetre(message))
        p.message = ''
        -- Les photos jointes, dans leur variante : la suite au bout.
        local variante = liee(contenu, 'static_text', 'jointes')
        egal(2, variante.args.height_in_lines)
        p.jointes = jointes
        egal(coupe, S.evaluer(variante.args.title, p))
        p.jointes = ''
        -- Le bandeau dans la rangée du bas : sa hauteur tient dans la zone de saisie.
        vrai(hauteur(rangeeDe(contenu, message)) <= D.saisie - D.filet - (12 + 26 + 8 + 52 + 8), 'la rangée du bas dans la saisie')
    end)
end)

essai('Carnet : le tableau, en Menlo, aligné et dans la largeur du fil', function()
    -- Six mois (dont un changement d'année, les mois avec leur année) et des libellés de 40 caractères,
    -- dans un fil de 648 points (celui de la fenêtre de 1 497 × 1 200, plus étroit que celui de
    -- D.texteFil) : la colonne Défaut se resserre, le tableau reste aligné et tient dans le fil.
    local mois, defauts = {}, {}
    for k = 1, 6 do
        mois[k] = { cle = 'm' .. k, annee = k < 4 and 2025 or 2026, court = ({ 'oct.', 'nov.', 'déc.', 'janv.', 'févr.', 'mars' })[k] }
    end
    for k = 1, 4 do
        local par = {}
        for m = 1, 6 do
            par[m] = { n = k, sur = 12 }
        end
        defauts[k] = { code = 'd' .. k, libelle = string.rep('Libellé très long ', 3):sub(1, 40), par_mois = par }
    end
    local page = { photos = 30, mois = mois, defauts = defauts, progresse = {}, recule = {}, a_travailler = {}, titres = Carnet.TITRES }
    local largeur = 648
    vrai(largeur <= D.texteFil, 'un fil plus étroit que celui de la fenêtre')
    local lignes = Fil.lignesCarnet(page, largeur, Fenetre.TITRE_CARNET)
    local tableau = {}
    for _, l in ipairs(lignes) do
        if l.genre == 'outil' then
            tableau[#tableau + 1] = l
        end
    end
    egal(5, #tableau)
    for _, l in ipairs(tableau) do
        egal(Texte.longueur(tableau[1].texte), Texte.longueur(l.texte), 'aligné : ' .. l.texte)
        vrai(Fil.occupe(l) <= largeur - Fil.MARGE, string.format('dans le fil : %.0f', Fil.occupe(l)))
        contient(l.texte, '  ', 'colonnes séparées')
    end
    contient(tableau[1].texte, 'oct. 2025')
    contient(tableau[1].texte, 'mars 2026')
    vrai(tableau[2].texte:find('…', 1, true), 'libellé resserré : ' .. tableau[2].texte)
    -- Sans resserrement possible de plus : au moins LIBELLE_CARNET_MIN caractères pour le libellé.
    local _, coupe = tableau[2].texte:find('…', 1, true)
    vrai(Texte.longueur(tableau[2].texte:sub(1, coupe)) >= Fil.LIBELLE_CARNET_MIN, 'libellé lisible')
end)
-- Cartes (lot B5) ------------------------------------------------------------------------------------

local Images = require 'Images'
local Stockage = require 'Stockage'

local INFOBULLE_ACCEPTER_NOTE = "Poser la note proposée dans Lightroom (sans Claude ni quota)"
local INFOBULLE_ACCEPTER_PROPOSITION = "Appliquer la proposition : la photo ne change qu'à ce clic"

-- La colonne superposée des variantes des onglets (Aperçu, Proposition, Note, Leçon), et chacune.
local function variantes(contenu)
    for _, v in ipairs(vues(contenu)) do
        if v.args.place == 'overlapping' and #v.args == #D.onglets then
            local toutes = true
            for _, e in ipairs(v.args) do
                toutes = toutes and type(e) == 'table' and e.genre == 'column' and e.args.width == D.interieur
            end
            if toutes then
                local r = {}
                for i, onglet in ipairs(D.onglets) do
                    r[onglet.valeur] = v.args[i]
                end
                return r
            end
        end
    end
    error('variantes des onglets introuvables', 2)
end

-- La colonne superposée posée sur cette image de carte (Vues.lecon, Vues.proposition…).
local function carteSur(contenu, nom)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == 'column' and v.args.place == 'overlapping' then
            local premier = v.args[1]
            if type(premier) == 'table' and premier.genre == 'picture' and premier.args.value == Fenetre.image(nom) then
                return v
            end
        end
    end
    error('carte introuvable : ' .. nom, 2)
end

-- Le registre des notes, simulé le temps de fn : une proposition (ou nil) pour la photo active, et
-- les appels reçus par Notation.poser et Notation.decider.
local function avecRegistre(proposition, fn)
    local recus = { poses = {}, decisions = {} }
    local prop = proposition
    avec(Notation, 'proposition', function(id)
        if prop and tostring(prop.photo) == tostring(id) then
            local copie = {}
            for k, v in pairs(prop) do
                copie[k] = v
            end
            return copie
        end
        return nil
    end, function()
        avec(Notation, 'poser', function(liste)
            recus.poses[#recus.poses + 1] = liste
            return { ok = true, resultats = {} }
        end, function()
            avec(Notation, 'decider', function(id, etat)
                recus.decisions[#recus.decisions + 1] = { photo = id, etat = etat }
                if prop then
                    prop.etat = etat
                end
                return true
            end, function()
                fn(recus, function(nouvelle) prop = nouvelle end)
            end)
        end)
    end)
end

-- Lance les tâches parties depuis `depuis`, dans l'ordre (l'image enfoncée d'un bouton bleu
-- comprise).
local function lancerDepuis(depuis)
    local i = depuis + 1
    while i <= #S.taches do
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

-- Une photo active notée dans Lightroom (note, pickStatus : 1 retenue, −1 rejetée).
local function photoNotee(id, nom, note, pick)
    local photo = photoActive(id, nom)
    photo.note, photo.pickStatus = note, pick
    return photo
end

local PROPOSITION = { photo = 4961, fichier = 'DSCF4961.RAF', note = 3, drapeau = 'aucun', etat = 'a_verifier', passe = 2, plafond = 3,
    raison = "Tient seule devant quelqu'un qui ne connaît ni les gens ni le lieu.", le = 1000,
    criteres = { impact = "Moyen. Le ciel d'orage arrête l'œil ; rien au premier plan ne le retient.",
        qualites = "Bonnes. Sujet clair, lumière d'orage, horizon droit ; arbres lourds à droite.",
        plancher = "Netteté 41 · nette ; bruit 0,4 · faible ; ombres bouchées 1,9 % ; aucun visage.",
        finition = "Pour 5 ★ seulement : rien à reprendre." } }

local function copieProposition(plus)
    local p = {}
    for k, v in pairs(PROPOSITION) do
        p[k] = v
    end
    for k, v in pairs(plus or {}) do
        p[k] = v
    end
    return p
end

essai('Cartes (lot B5) : chacune sur son image, à la hauteur de son image ; leur contenu tient, chaque onglet sous l\'aperçu (D.placeCartes) ; textes à 472 en 12 points', function()
    -- La place sous l\'aperçu et sa rangée, jusqu\'au bas du contenu du panneau (son bord et sa marge
    -- de 14) : chaque carte y tient (plus bas).
    egal(Dispositions.IMAGES.panneau.hauteur - 1 - 14, D.hauteurSegments + D.margeHautPanneau + D.apercuHauteur + 8
        + Dispositions.cadreBouton(22) + 12 + D.placeCartes, 'la place des cartes, du haut des segments au bas du panneau')
    egal(472, D.carte)
    egal(13, D.margeCarte)
    for _, cle in ipairs({ 'largeurNote', 'largeurProposition', 'largeurEtape', 'largeurLecon' }) do
        egal(D.carte, D[cle], cle)
    end
    -- Les cartes en 12 points ; la note et la leçon gardent leurs passages balisés (gras 12).
    for cle, carte in pairs(Fenetre.CARTES) do
        egal('texte12', carte.police, 'CARTES.' .. cle)
    end
    egal('gras12', Fenetre.CARTES.note.emphase)
    egal('gras12', Fenetre.CARTES.lecon.emphase)
    egal(nil, Fenetre.CARTES.proposition.emphase)
    egal(D.criteres + 1, Fenetre.CARTES.note.lignes(D), 'la grille des critères : criteres + 1 lignes')
    -- L'étiquette la plus large d'un critère tient dans sa colonne ; la grille, dans la carte.
    for _, critere in ipairs(Fenetre.CRITERES) do
        vrai(Fenetre.largeurLibelle(critere.titre, 'gras12') <= D.etiquetteCritere, critere.titre)
    end
    egal(D.carte, D.etiquetteCritere + D.ecartCritere + D.texteCritere)
    vrai(Fenetre.largeurLibelle('Votre note :', 'texte12') <= D.etiquetteNote, 'Votre note :')
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        local v = variantes(contenu)
        for valeur, colonne in pairs(v) do
            vrai(hauteur(colonne) <= D.placeCartes, string.format('onglet %s : %.1f points pour %d', valeur, hauteur(colonne), D.placeCartes))
        end
        -- Chaque carte : une colonne superposée de la largeur intérieure, à la hauteur de son image,
        -- son contenu à 13 du bord et 12 du haut (comme Vues.lecon).
        for _, nom in ipairs({ 'carte-note', 'carte-proposition', 'carte-etape', 'carte-lecon', 'carte-focus' }) do
            local carte = carteSur(contenu, nom)
            egal(Dispositions.IMAGES[nom].hauteur, carte.args.height, nom .. ' : la hauteur de son image')
            egal(D.interieur, carte.args.width, nom)
            local dedans = carte.args[2]
            egal(D.margeCarte, dedans.args.margin_left, nom .. ' : marge de gauche')
            egal(12, dedans.args.margin_top, nom .. ' : marge du haut')
            vrai(hauteur(carte) <= carte.args.height, nom .. ' : son contenu y tient')
            -- Ses lignes la remplissent (Dispositions.TAILLES : criteres, propLignes, etapeLignes,
            -- leconLignes, focusLignes) : au moins la marge du haut sous le contenu, et une ligne de plus (16 dans
            -- la grille de la carte Note, une ligne de texte en 12 ailleurs) ne laisserait plus cette
            -- marge.
            local estime = hauteur(dedans)
            local ligne = nom == 'carte-note' and D.ligneCritere or 1.25 * 12
            local bas = carte.args.height - dedans.args.margin_top
            vrai(estime <= bas, string.format('%s : contenu de %.1f, %.1f sous lui (au moins %d)', nom, estime, carte.args.height - estime,
                dedans.args.margin_top))
            vrai(estime + ligne > bas, string.format('%s : une ligne de plus y tiendrait (contenu de %.1f pour %d)', nom, estime, carte.args.height))
        end
        -- L'onglet Note remplit la place des cartes : une ligne de critère de plus n'y tiendrait pas.
        vrai(hauteur(v.notation) + D.ligneCritere > D.placeCartes, string.format('onglet Note : %.1f pour %d', hauteur(v.notation), D.placeCartes))
        -- Les textes des cartes, à la largeur de leur intérieur, en 12 points.
        for _, cle in ipairs({ 'propositionTexte', 'etapeTexte', 'leconTexte', 'focusTexte' }) do
            local t = liee(contenu, 'static_text', cle)
            egal(D.carte, t.args.width, cle)
            egal(Fenetre.POLICES.texte12, t.args.font, cle)
        end
        egal(D.propLignes, liee(contenu, 'static_text', 'propositionTexte').args.height_in_lines)
        egal(D.etapeLignes, liee(contenu, 'static_text', 'etapeTexte').args.height_in_lines)
        -- La grille de la carte Note : chaque texte en 12, le verdict en gras 12 de même taille (D4).
        local textes = 0
        for _, x in ipairs(vues(contenu)) do
            local t = x.args.title
            if x.genre == 'static_text' and type(t) == 'table' and type(t.key) == 'string' and t.key:match('^nt%d+$') then
                textes = textes + 1
                egal(Fenetre.POLICES.texte12, x.args.font)
                egal(Fenetre.POLICES.gras12, x.args.emphasis_font)
                vrai(x.args.width == D.carte or x.args.width == D.texteCritere, 'largeur : ' .. tostring(x.args.width))
            end
        end
        egal((D.criteres + 1) * (2 + #Fenetre.TEINTES_NOTE), textes, 'pleine largeur, une par teinte de l\'état, et à côté d\'une étiquette')
        -- L'estimateur refuse un contenu qui dépasse la hauteur donnée.
        local f = S.modules.LrView.osFactory()
        refuse(function() hauteur(f:column { height = 20, f:static_text { title = 'a', height_in_lines = 3 } }) end, 'column de hauteur 20')
    end)
end)

essai('Inventaire de la carte Note (maquette) : chaque élément, son genre, sa clé et son état ; « ? À vérifier » grisé dans tous les états ; ni Noter, ni Évaluer, ni Modèle', function()
    local photo = photoNotee(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    avecRegistre(copieProposition(), function()
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            local C = Fenetre.COULEURS
            -- Les étiquettes de la grille, en gris 12, alignées à droite sur leur colonne ; plus de
            -- « Passes : » (correctif 1.3.2, demandé par Dany le 22 octobre 2026).
            for _, titre in ipairs({ 'Votre note :', 'Drapeau :' }) do
                local e = parTitre(note, titre, 'static_text')
                egal('right', e.args.alignment, titre)
                egal(D.etiquetteNote, e.args.width, titre)
                egal(C.gris, e.args.text_color, titre)
                egal(12, e.args.font.size, titre)
                vrai(S.montreeDansFenetre(e), titre)
            end
            -- Les cinq étoiles de « Votre note » : des calques de 30 sur etoile24.
            local calques = 0
            for _, x in ipairs(vues(note)) do
                if x.genre == 'static_text' and Fenetre.parCalque(x.args.mouse_down) and type(x.args.tooltip) == 'string'
                    and x.args.tooltip:find('★ dans Lightroom', 1, true) then
                    calques = calques + 1
                    egal(D.etoile, x.args.width)
                    egal(D.etoile, x.args.height)
                end
            end
            egal(5, calques, 'cinq étoiles cliquables')
            -- La note posée, à droite des étoiles.
            egal('Pas encore jugée', p.notePoseeTitre)
            egal('0 ★ dans le catalogue', p.notePoseeSous)
            egal(Fenetre.POLICES.gras12, liee(note, 'static_text', 'notePoseeTitre').args.font)
            -- Les drapeaux : deux carrés actifs, « ? À vérifier » posé grisé.
            local retenir, rejeter, aVerifier = parTitre(note, '⚑ Retenir'), parTitre(note, '⊗ Rejeter'), parTitre(note, '? À vérifier')
            for _, b in ipairs({ retenir, rejeter, aVerifier }) do
                egal('square_button', b.genre, b.args.title)
                egal(24, S.bezelVisible(b), b.args.title .. ' : bezel de 24 (maquette)')
            end
            egal('peutChangerNote', retenir.args.enabled.key)
            egal('peutChangerNote', rejeter.args.enabled.key)
            -- « Claude propose », ses étoiles en images et l'ordre des critères.
            vrai(parTitre(note, 'Claude propose', 'static_text'), 'Claude propose')
            vrai(parTitre(note, 'critères du plus lourd au plus léger', 'static_text'), "l'ordre des critères")
            egal(3, p.noteClaude)
            -- La carte des critères, sans filet ni ligne du plafond (correctif 1.3.2), même avec un
            -- plafond mesuré au tri dans la proposition.
            vrai(carteSur(contenu, 'carte-note'), 'carte-note')
            egal(3, copieProposition().plafond, 'un plafond est dans la proposition')
            -- La rangée du bas : ▲ ▼, « Voir à 100 % », Laisser, Changer…, Accepter (bleu).
            local laisser = liee(note, 'square_button', 'titreLaisser')
            egal('peutAccepterNote', laisser.args.enabled.key)
            egal(26, S.bezelVisible(laisser))
            egal('Laisser à 0 ★', p.titreLaisser)
            local changer = parTitre(note, 'Changer…')
            egal('peutChangerNote', changer.args.enabled.key)
            local accepter = parInfobulle(note, INFOBULLE_ACCEPTER_NOTE)
            vrai(Fenetre.parCalque(accepter.args.mouse_down), 'Accepter : un calque sur le bouton bleu')
            egal('Accepter 3 ★', p.titreAccepterNote)
            local titreBlanc = liee(note, 'static_text', 'titreAccepterNote')
            egal(C.blanc, titreBlanc.args.text_color)
            egal(false, p.bleuEnfonceAccepterNote, "sa clé d'enfoncement a une valeur avant l'ouverture")
            for _, cle in ipairs({ 'noteMonte', 'noteDescend' }) do
                local b
                for _, x in ipairs(vues(note)) do
                    if S.BOUTONS[x.genre] and type(x.args.enabled) == 'table' and x.args.enabled.key == cle then
                        b = x
                    end
                end
                vrai(b, cle)
            end
            -- « ? À vérifier » grisé dans tous les états : Claude libre ou au travail, une proposition
            -- à décider, décidée, ou aucune ; son clic est refusé.
            local etats = {
                function() Moteur.travaille = false end,
                function() Moteur.travaille = true end,
                function() Moteur.travaille = false; photo.note = 3 end,
                function() photoActive(4970, 'DSCF4970.RAF') end,
            }
            for k, poserEtat in ipairs(etats) do
                poserEtat()
                Fenetre.majPhoto()
                Fenetre.rafraichir()
                egal(false, valeur(aVerifier, 'enabled', p), 'état ' .. k .. ' : grisé')
                egal(Fenetre.A_VENIR, aVerifier.args.tooltip)
                refuse(function() S.cliquer(aVerifier) end, 'inactive', 'état ' .. k .. ' : clic refusé')
            end
            Moteur.travaille = false
            -- Ni Noter, ni Évaluer, ni Modèle, sous aucun titre (décisions de Dany).
            for _, x in ipairs(vues(contenu)) do
                local t = tostring(valeur(x, 'title', p) or '')
                vrai(not t:find('Noter', 1, true) and not t:find('Évaluer', 1, true) and not t:find('Modèle', 1, true), x.genre .. ' « ' .. t .. ' »')
            end
            egal(nil, Fenetre.noter)
            egal(nil, Fenetre.verifierNote)
            egal(0, #S.refusDeLaFenetre(), 'aucun refus de texte riche')
        end)
    end)
end)

essai('Inventaire des cartes Proposition et Aperçu (étape) : titres, textes, carrés, Accepter en bleu ; chaque bouton à sa clé', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        local v = variantes(contenu)
        local proposition, apercu = v.proposition, v.apercu
        vrai(parTitre(proposition, 'Proposition de Claude', 'static_text'), 'titre de la proposition')
        local cles = {}
        for _, x in ipairs(vues(proposition)) do
            if S.BOUTONS[x.genre] then
                local t = x.args.title
                cles[#cles + 1] = (type(t) == 'table' and ('[' .. t.key .. ']') or t) .. '=' .. x.args.enabled.key
            end
        end
        egal('▲=propositionMonte ▼=propositionDescend Refuser=enAttente Ajuster…=enAttente [titreJeLeFais]=peutJeLeFais', table.concat(cles, ' '))
        local accepter = parInfobulle(proposition, INFOBULLE_ACCEPTER_PROPOSITION)
        vrai(Fenetre.parCalque(accepter.args.mouse_down), 'Accepter de la proposition : un calque')
        vrai(liee(proposition, 'static_text', 'exerciceEtat'), "l'état de l'exercice")
        -- Accepter inactif (aucune proposition) : son calque ne fait rien.
        egal(false, p.enAttente)
        local reponses = {}
        avec(Fenetre, 'repondreProposition', function(a) reponses[#reponses + 1] = a end, function()
            p.onglet = 'proposition'
            S.cliquer(accepter)
            egal(0, #reponses, 'inactif : rien')
            p.enAttente = true
            local taches = #S.taches
            S.cliquer(accepter)
            S.cliquer(parTitre(proposition, 'Refuser'))
            egal('true false', tostring(reponses[1]) .. ' ' .. tostring(reponses[2]), 'Accepter, puis Refuser')
            lancerDepuis(taches)
            p.enAttente = false
        end)
        -- La carte de l'étape : titre (« Pourquoi ? » sans étape), sous-titre, texte ; sous elle,
        -- comme sous la carte Note, ▲ ▼, puis ◀ ▶, Voir l'avant et Détail… en carrés de 26.
        egal('Pourquoi ?', p.etapeTitre)
        cles = {}
        for _, x in ipairs(vues(apercu)) do
            if S.BOUTONS[x.genre] then
                local t = x.args.title
                cles[#cles + 1] = (type(t) == 'table' and ('[' .. t.key .. ']') or t) .. '=' .. x.args.enabled.key
                if x.genre == 'square_button' then
                    egal(26, S.bezelVisible(x))
                end
            end
        end
        egal('▲=etapeMonte ▼=etapeDescend ◀=etapePrecedente ▶=etapeSuivante [titreBascule]=etapeAImages Détail…=etapeADetail', table.concat(cles, ' '))
        p.onglet = 'notation'
    end)
end)

essai('Ni passes ni plafond dans la carte Note (correctif 1.3.2, demandé par Dany) : leurs vues, leurs clés et leurs images retirées ; la grille des critères prend la place ; « Voir à 100 % » dans la rangée du bas', function()
    photoNotee(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    -- Plus rien des passes ni du plafond dans la fenêtre, ses dimensions ni ses images.
    for _, nom in ipairs({ 'PASSES', 'PASSE_MAX_CLAUDE', 'etatPasse', 'textePlafond', 'noteDeCinq', 'PAS_CINQ' }) do
        egal(nil, Fenetre[nom], 'Fenetre.' .. nom)
    end
    egal(nil, Vues.passes, 'Vues.passes')
    egal(nil, Vues.lignePlafond, 'Vues.lignePlafond')
    for _, image in ipairs({ 'coche-10', 'chevron-passe', 'avertissement' }) do
        egal(nil, Dispositions.IMAGES[image], 'image ' .. image)
    end
    for _, cle in ipairs({ 'lignePasses', 'plafond', 'avertissement' }) do
        egal(nil, D[cle], 'D.' .. cle)
    end
    -- La place libérée va à la grille des critères : 34 lignes de 16 sur une carte de 583.
    egal(33, D.criteres)
    egal(583, Dispositions.IMAGES['carte-note'].hauteur)
    egal(D.placeCartes - D.autourNote, Dispositions.IMAGES['carte-note'].hauteur)
    local prop = copieProposition()
    prop.passe, prop.plafond = 3, 2
    avecRegistre(prop, function()
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            -- Aucune vue liée aux passes ou au plafond, aucun libellé des passes, aucune étiquette
            -- « Passes : », aucun « Plafond » même mesuré.
            for _, x in ipairs(vues(note)) do
                for _, cle in ipairs({ 'title', 'visible', 'enabled' }) do
                    local v = x.args[cle]
                    local cles = type(v) == 'table' and (v.keys or { v.key }) or {}
                    for _, k in ipairs(cles) do
                        vrai(k ~= 'notePasse' and k ~= 'aPlafond' and k ~= 'plafondTexte', x.genre .. ' lié à ' .. tostring(k))
                    end
                end
                local t = tostring(valeur(x, 'title', p) or '')
                for _, mot in ipairs({ 'Passes :', 'Rejeter ?', '3 ★ ou non ?', 'Monter à 4 ?', '(vous)', 'Plafond', 'mesuré au tri' }) do
                    vrai(not t:find(mot, 1, true), x.genre .. ' « ' .. t .. ' »')
                end
                egal(nil, x.args.value and tostring(x.args.value):find('avertissement', 1, true), 'image avertissement')
            end
            for k = 1, D.criteres + 1 do
                vrai(not tostring(p['nt' .. k]):find('Plafond', 1, true), 'ligne ' .. k)
            end
            -- La passe de Claude reste dans l'en-tête de la grille.
            vrai(p.nt1:find('<EM>Passe 3 · à vérifier.</EM>', 1, true) == 1, p.nt1)
            -- « Voir à 100 % » : dans la rangée du bas, avec Laisser, Changer… et Accepter, en
            -- carrés de 26 ; sa largeur tient son titre en 13.
            local laisser = liee(note, 'square_button', 'titreLaisser')
            local rangee = rangeeDe(note, laisser)
            local zooms = 0
            for _, x in ipairs(vues(rangee)) do
                if S.BOUTONS[x.genre] and x.args.title == 'Voir à 100 %' then
                    zooms = zooms + 1
                    egal(26, S.bezelVisible(x))
                    egal(D.zoom, x.args.width)
                    egal(Fenetre.POLICES.systeme13, x.args.font)
                end
            end
            egal(2, zooms, 'les deux variantes de « Voir à 100 % », dans la rangée de Laisser')
            vrai(Fil.largeur('Voir à 100 %', 'texte') + 12 <= D.zoom, 'son titre tient')
            -- La rangée tient dans le panneau, en comptant 30 points par flèche mini (▲ ▼).
            local bleu = Dispositions.IMAGES['bouton-bleu'].largeur
            local total = 2 * 30 + 2 + 8 + D.zoom + D.laisser + 8 + D.changer + 8 + bleu
            vrai(total <= D.interieur, string.format('rangée du bas : %d points pour %d', total, D.interieur))
            -- La rangée « Votre note » : la largeur du panneau.
            local votre = rangeeDe(note, parTitre(note, 'Votre note :', 'static_text'))
            egal(D.interieur, largeurDonnee(votre), 'Votre note : la largeur du panneau')
        end)
    end)
end)

essai('Étoiles de « Votre note » : la k-e pose k ★ (5 comprises) par Notation.poser, sur la note posée la retire ; refusées pendant le travail, pendant une note en cours, sans photo active', function()
    local photo = photoNotee(4961, 'DSCF4961.RAF', 3, 0)
    Moteur.nouvelle()
    avecRegistre(copieProposition(), function(recus)
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            egal(3, p.noteCatalogue)
            egal('Tient seule', p.notePoseeTitre)
            egal('3 ★ dans le catalogue', p.notePoseeSous)
            local note = variantes(contenu).notation
            -- Les étoiles pleines jusqu'à la note posée.
            local pleines = 0
            for _, x in ipairs(vues(note)) do
                if x.genre == 'picture' and x.args.value == Fenetre.image('etoile24-pleine') and S.montreeDansFenetre(x) then
                    pleines = pleines + 1
                end
            end
            egal(3, pleines, 'trois étoiles pleines')
            local function etoile(k)
                for _, x in ipairs(vues(note)) do
                    if x.genre == 'static_text' and x.args.tooltip and x.args.tooltip:find('^Poser ' .. k .. ' ★') then
                        return x
                    end
                end
                error('étoile ' .. k .. ' introuvable', 2)
            end
            local champ = liee(contenu, 'edit_field', 'saisie')
            local function cliquer(k)
                local taches = #S.taches
                S.taper(champ, 'texte tapé')
                S.cliquer(etoile(k))
                egal(nil, Fenetre.envoiAuto, "le clic d'une étoile n'envoie pas la demande")
                p.saisie = ''
                lancerDepuis(taches)
            end
            cliquer(5)
            cliquer(1)
            cliquer(3)
            local poses = {}
            for _, liste in ipairs(recus.poses) do
                egal(1, #liste)
                egal(4961, liste[1].photo)
                egal(nil, liste[1].drapeau, 'les étoiles ne touchent pas le drapeau')
                egal(Fenetre.RAISON_NOTE, liste[1].raison)
                poses[#poses + 1] = tostring(liste[1].note)
            end
            egal('5 1 0', table.concat(poses, ' '), '5 ★ par Dany ; 1 ★ ; la 3e sur 3 ★ posées : 0')
            egal(0, #recus.decisions)
            -- Refusées pendant le travail (le calque n'a pas d'enabled : le gestionnaire refuse), et
            -- le bandeau le dit.
            local avant = #recus.poses
            Moteur.travaille = true
            local taches = #S.taches
            S.cliquer(etoile(2))
            egal(taches, #S.taches, 'aucune tâche')
            egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
            Moteur.travaille = false
            p.message = ''
            -- Pendant une note en cours.
            Fenetre.noteEnCours = true
            S.cliquer(etoile(2))
            egal(Fenetre.NOTE_EN_COURS, p.message)
            Fenetre.noteEnCours = false
            p.message = ''
            -- Une note demandée juste avant que Claude se mette au travail : la tâche la refuse.
            S.cliquer(etoile(2))
            Moteur.travaille = true
            lancerDepuis(taches)
            Moteur.travaille = false
            egal(avant, #recus.poses, 'rien posé')
            egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
            p.message = ''
            -- Sans photo active.
            S.photoActive, S.selection = nil, {}
            Fenetre.majPhoto()
            egal(false, Fenetre.poserEtoile(2))
            egal(Fenetre.AUCUNE_PHOTO, p.message)
            p.message = ''
            photo = photoNotee(4961, 'DSCF4961.RAF', 3, 0)
            Fenetre.majPhoto()
        end)
    end)
end)

essai('Drapeaux : Retenir et Rejeter posent leur drapeau (ou le retirent) par Notation.poser, sans toucher les étoiles ; Retenir ne décide rien de la proposition ; grisés et refusés pendant le travail', function()
    local photo = photoNotee(4961, 'DSCF4961.RAF', 2, 0)
    Moteur.nouvelle()
    avecRegistre(copieProposition(), function(recus, changer)
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            local retenir, rejeter = parTitre(note, '⚑ Retenir'), parTitre(note, '⊗ Rejeter')
            local function drapeaux()
                local r = {}
                for _, liste in ipairs(recus.poses) do
                    egal(nil, liste[1].note, 'un drapeau ne touche pas les étoiles')
                    egal(Fenetre.RAISON_DRAPEAU, liste[1].raison)
                    r[#r + 1] = liste[1].drapeau
                end
                return table.concat(r, ' ')
            end
            local taches = #S.taches
            S.cliquer(retenir)
            S.cliquer(rejeter)
            lancerDepuis(taches)
            egal('retenue rejetee', drapeaux())
            -- Déjà retenue : Retenir retire le drapeau ; déjà rejetée : Rejeter aussi.
            photo.pickStatus = 1
            Fenetre.majPhoto()
            egal('2 ★ · drapeau Retenue', p.notePoseeSous)
            S.cliquer(retenir)
            photo.pickStatus = -1
            Fenetre.majPhoto()
            egal('Rejetée', p.notePoseeTitre)
            egal('2 ★ · drapeau Rejeter', p.notePoseeSous)
            egal('Laisser rejetée', p.titreLaisser)
            S.cliquer(rejeter)
            lancerDepuis(taches)
            egal('retenue rejetee aucun aucun', drapeaux())
            -- Retenir et les drapeaux retirés laissent la proposition à décider (Notation.decider la
            -- remet « à vérifier » après la pose) ; Rejeter la décide (aucun retour).
            local function decisions()
                local r = {}
                for _, d in ipairs(recus.decisions) do
                    egal(4961, d.photo)
                    r[#r + 1] = d.etat
                end
                return table.concat(r, ' ')
            end
            egal('a_verifier a_verifier a_verifier', decisions(), 'Retenir, puis deux drapeaux retirés')
            -- Un rejet proposé : tout drapeau le décide, Retenir compris.
            changer(copieProposition({ drapeau = 'rejetee', note = 0 }))
            photo.pickStatus = 0
            Fenetre.majPhoto()
            S.cliquer(retenir)
            lancerDepuis(taches)
            egal('a_verifier a_verifier a_verifier', decisions(), 'Retenir sur un rejet proposé : une décision')
            egal(5, #recus.poses)
            changer(copieProposition())
            -- Pendant le travail : grisés, le clic refusé ; appelé quand même, refusé et dit.
            Moteur.travaille = true
            Fenetre.rafraichirNotation()
            egal(false, valeur(retenir, 'enabled', p))
            refuse(function() S.cliquer(rejeter) end, 'inactive', 'grisé pendant le travail')
            egal(false, Fenetre.poserDrapeau('retenue'))
            egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
            Moteur.travaille = false
            p.message = ''
            Fenetre.noteEnCours = true
            egal(false, Fenetre.poserDrapeau('retenue'))
            egal(Fenetre.NOTE_EN_COURS, p.message)
            Fenetre.noteEnCours = false
            p.message = ''
            egal(5, #recus.poses)
            Fenetre.rafraichirNotation()
        end)
    end)
end)

essai('Laisser à N ★ : Notation.decider(photo, « ecartee »), rien dans le catalogue ; grisé quand rien n\'est à décider ; refusé pendant le travail', function()
    photoNotee(4961, 'DSCF4961.RAF', 2, 0)
    Moteur.nouvelle()
    avecRegistre(copieProposition(), function(recus)
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            local laisser = liee(note, 'square_button', 'titreLaisser')
            egal('Laisser à 2 ★', p.titreLaisser)
            egal(true, p.peutAccepterNote)
            -- Refusé pendant le travail (grisé, et la fonction le dit).
            Moteur.travaille = true
            Fenetre.rafraichirNotation()
            refuse(function() S.cliquer(laisser) end, 'inactive', 'grisé pendant le travail')
            egal(false, Fenetre.laisserNote())
            egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
            Moteur.travaille = false
            p.message = ''
            Fenetre.rafraichirNotation()
            local taches = #S.taches
            S.cliquer(laisser)
            lancerDepuis(taches)
            egal(1, #recus.decisions)
            egal(4961, recus.decisions[1].photo)
            egal('ecartee', recus.decisions[1].etat)
            egal(0, #recus.poses, 'rien dans le catalogue')
            -- Écartée : plus rien à décider, Laisser et Accepter grisés.
            Fenetre.rafraichirNotation()
            egal(false, p.peutAccepterNote)
            egal('gris', p.notationCouleur)
            vrai(p.nt1:find('<EM>Passe 2 · écartée.</EM>', 1, true), p.nt1)
            refuse(function() S.cliquer(laisser) end, 'inactive', 'plus rien à laisser')
            -- Une note en cours, ou Claude au travail depuis le clic : la tâche ne décide rien, et le
            -- bandeau le dit.
            Fenetre.noteEnCours = true
            Fenetre.ecarterNote(4961)
            Fenetre.noteEnCours = false
            egal(Fenetre.NOTE_EN_COURS, p.message)
            p.message = ''
            Moteur.travaille = true
            Fenetre.ecarterNote(4961)
            Moteur.travaille = false
            egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
            p.message = ''
            egal(1, #recus.decisions)
        end)
    end)
end)

essai('Accepter N ★ : son calque pose la proposition telle quelle ; inactif, il ne fait rien ; « Accepter le rejet » ; « Accepter 5 ★ » (correctif 1.3.2)', function()
    photoNotee(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    avecRegistre(copieProposition(), function(recus, changer)
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            local accepter = parInfobulle(note, INFOBULLE_ACCEPTER_NOTE)
            egal('Accepter 3 ★', p.titreAccepterNote)
            local taches = #S.taches
            S.cliquer(accepter)
            lancerDepuis(taches)
            egal(1, #recus.poses)
            egal(4961, recus.poses[1][1].photo)
            vrai(recus.poses[1][1].note == nil and recus.poses[1][1].drapeau == nil, 'telle quelle : ni note ni drapeau')
            -- Inactif (Claude au travail) : le calque ne fait rien, ni tâche ni pose.
            Moteur.travaille = true
            Fenetre.rafraichirNotation()
            egal(false, p.peutAccepterNote)
            taches = #S.taches
            S.cliquer(accepter)
            egal(taches, #S.taches, 'inactif : aucune tâche')
            egal(false, p.bleuEnfonceAccepterNote, 'inactif : pas enfoncé')
            Moteur.travaille = false
            -- Un rejet proposé.
            changer(copieProposition({ drapeau = 'rejetee', note = nil }))
            Fenetre.rafraichirNotation()
            egal('Accepter le rejet', p.titreAccepterNote)
            egal('rejet', p.noteClaude)
            -- Claude propose de 0 à 5 ★ (correctif 1.3.2, demandé par Dany le 22 octobre 2026) :
            -- « Accepter 5 ★ » s'offre et pose la proposition telle quelle.
            changer(copieProposition({ note = 5, passe = 4 }))
            Fenetre.rafraichirNotation()
            egal('Accepter 5 ★', p.titreAccepterNote)
            egal(true, p.peutAccepterNote)
            egal(5, p.noteClaude)
            local cinq = 0
            for _, x in ipairs(vues(contenu)) do
                if tostring(valeur(x, 'title', p) or '') == 'Accepter 5 ★' then
                    cinq = cinq + 1
                end
            end
            vrai(cinq > 0, '« Accepter 5 ★ » montré sur le bouton bleu')
            taches = #S.taches
            S.cliquer(accepter)
            lancerDepuis(taches)
            egal(2, #recus.poses, '5 ★ posées')
            vrai(recus.poses[2][1].note == nil and recus.poses[2][1].drapeau == nil, 'telle quelle')
            egal('', p.message or '', 'aucun refus')
            for n = 0, 5 do
                vrai(Fenetre.titreAccepter({ note = n, drapeau = 'aucun' }) == 'Accepter ' .. n .. ' ★', n .. ' ★')
            end
            -- Une note en cours : la pose est refusée et dite.
            changer(copieProposition())
            Fenetre.noteEnCours = true
            Fenetre.poserNote({ photo = 4961 })
            Fenetre.noteEnCours = false
            egal(Fenetre.NOTE_EN_COURS, p.message)
            egal(2, #recus.poses)
            p.message = ''
        end)
    end)
end)

-- Une conversation où Claude regarde la photo 4961 : un aperçu entier, puis (si `zooms`) des zooms
-- (view_photo avec region), chacun son image.
local function avecVues(c, appels)
    for _, a in ipairs(appels) do
        outil(c, a.id, 'view_photo', a.entree)
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = a.id, textes = { a.reponse or '{}' },
            images = { { donnees = 'x' } }, erreur = a.erreur == true } } }, nil, function() return a.id .. '.jpg' end)
    end
end

local ZONE = { x = 0.1, y = 0.2, width = 0.25, height = 0.25 }

essai('Voir à 100 % : Conversation.dernierZoom rend le dernier zoom d\'une photo (view_photo avec region), ni un aperçu entier, ni une autre photo, ni une erreur', function()
    local c = Conversation.nouvelle()
    egal(nil, Conversation.dernierZoom(c, 4961), 'conversation vide')
    -- Un aperçu entier de la photo : pas un zoom.
    avecVues(c, { { id = 'e1', entree = { photo_id = 4961, size = 1568 } } })
    egal(nil, Conversation.dernierZoom(c, 4961), 'un aperçu entier')
    -- Un zoom d'une autre photo.
    avecVues(c, { { id = 'z2', entree = { photo_id = 4962, region = ZONE } } })
    egal(nil, Conversation.dernierZoom(c, 4961), "le zoom d'une autre photo")
    egal('z2.jpg', Conversation.dernierZoom(c, 4962).chemin)
    -- Deux zooms de la photo : le plus récent ; la photo en texte ou en nombre.
    avecVues(c, { { id = 'z3', entree = { photo_id = 4961, region = ZONE } }, { id = 'z4', entree = { photo_id = 4961, region = { x = 0.5, y = 0.5, width = 0.2, height = 0.2 } } } })
    local z = Conversation.dernierZoom(c, 4961)
    egal('z4.jpg', z.chemin)
    egal('z4', z.appel)
    egal(0.5, z.zone.x)
    egal('z4.jpg', Conversation.dernierZoom(c, '4961').chemin)
    vrai(c.elements[z.element].genre == 'apercu', "l'élément de l'image")
    -- Sans photo_id : la photo que dit la réponse.
    avecVues(c, { { id = 'z5', entree = { region = ZONE }, reponse = '{"photo":{"id":4961,"fichier":"DSCF4961.RAF"},"zoom":{"pourcentage":100}}' } })
    egal('z5.jpg', Conversation.dernierZoom(c, 4961).chemin, 'sans photo_id')
    -- Un appel en erreur, une comparaison : rien.
    local d = Conversation.nouvelle()
    avecVues(d, { { id = 'x1', entree = { photo_id = 4961, region = ZONE }, erreur = true },
        { id = 'x2', entree = { photo_id = 4961, compare = 'previous_step' } } })
    egal(nil, Conversation.dernierZoom(d, 4961))
    egal(nil, Conversation.dernierZoom(nil, 4961))
    egal(nil, Conversation.dernierZoom(c, nil))
end)

essai('Voir à 100 % dans la carte : le zoom de la photo montré dans l\'aperçu (décision de Dany), Agrandir le montre en grand, sans Claude ni Lightroom ; sans zoom, d\'une autre photo ou un aperçu entier : grisé, l\'infobulle dit pourquoi', function()
    photoNotee(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    local c = Moteur.courante
    avecRegistre(copieProposition(), function()
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            local note = variantes(contenu).notation
            local actif, grise
            for _, x in ipairs(vues(note)) do
                if S.BOUTONS[x.genre] and x.args.title == 'Voir à 100 %' then
                    if x.args.tooltip == Fenetre.INFOBULLE_ZOOM then
                        actif = x
                    elseif x.args.tooltip == Fenetre.SANS_ZOOM then
                        grise = x
                    end
                end
            end
            vrai(actif and grise, 'les deux variantes de « Voir à 100 % »')
            egal(false, grise.args.enabled, 'grisé')
            egal('Claude n\'a pas pris de zoom de cette photo', Fenetre.SANS_ZOOM)
            egal(26, S.bezelVisible(actif), 'dans la rangée du bas, comme Laisser (correctif 1.3.2)')
            local function etat()
                return (S.montreeDansFenetre(actif) and 'actif' or '') .. (S.montreeDansFenetre(grise) and 'grisé' or '')
            end
            -- Sans zoom : grisé, son clic refusé.
            egal(false, p.peutVoirZoom)
            egal('grisé', etat())
            refuse(function() S.cliquer(grise) end, 'inactive', 'sans zoom')
            -- Un aperçu entier, puis le zoom d'une autre photo : toujours grisé.
            avecVues(c, { { id = 'e1', entree = { photo_id = 4961, size = 1568 } }, { id = 'z2', entree = { photo_id = 4962, region = ZONE } } })
            Fenetre.rafraichir()
            egal('grisé', etat(), "un aperçu entier ou le zoom d'une autre photo")
            -- Le zoom de la photo : actif. Puis un aperçu entier, la dernière image, montré dans
            -- l'aperçu : « Voir à 100 % » y remet le zoom, comme un clic sur sa ligne d'image (décision
            -- de Dany du 21 octobre 2026 : « dans l'aperçu »), sans fenêtre à part, sans Claude ni
            -- Lightroom ; Agrandir le montre ensuite en grand.
            avecVues(c, { { id = 'z3', entree = { photo_id = 4961, region = ZONE } }, { id = 'e4', entree = { photo_id = 4961, size = 1568 } } })
            Fenetre.rafraichir()
            egal(true, p.peutVoirZoom)
            egal('actif', etat())
            local function montree()
                local image = Fenetre.images[Fenetre.indiceImage or #Fenetre.images]
                return image and image.chemin
            end
            egal('e4.jpg', montree(), "la dernière image de la conversation dans l'aperçu")
            local vignettes, demandes, envois = {}, {}, 0
            avec(Images, 'vignette', function(dossier, nom)
                vignettes[#vignettes + 1] = nom
                return dossier .. '/petite-' .. nom
            end, function()
                avec(Images, 'grande', function(dossier, nom, l, h)
                    demandes[#demandes + 1] = { dossier = dossier, nom = nom, l = l, h = h }
                    return dossier .. '/' .. nom, 600, 400
                end, function()
                    avec(Moteur, 'envoyer', function() envois = envois + 1 end, function()
                        local photos, lire = 0, Lightroom.photos
                        Lightroom.photos = function(...) photos = photos + 1; return lire(...) end
                        local champ = liee(contenu, 'edit_field', 'saisie')
                        local taches, dialogues = #S.taches, #S.dialogues
                        S.taper(champ, 'texte')
                        S.cliquer(actif)
                        egal(nil, Fenetre.envoiAuto, "« Voir à 100 % » n'envoie pas la demande")
                        p.saisie = ''
                        egal(true, Fenetre.imageCliquee, 'comme un clic sur sa ligne d\'image')
                        egal('z3.jpg', montree(), "le zoom dans l'aperçu")
                        vrai(p.legendeApercu:find('view_photo', 1, true), p.legendeApercu)
                        lancerDepuis(taches)
                        egal('z3.jpg', vignettes[#vignettes], "sa vignette, réduite au cadre de l'aperçu")
                        egal(Stockage.dossier(c.id) .. '/petite-z3.jpg', p.imageApercu)
                        egal(dialogues, #S.dialogues, 'aucune fenêtre à part')
                        egal(0, #demandes)
                        -- Le rafraîchissement de la fenêtre le garde ; Agrandir le montre en grand.
                        Fenetre.rafraichir()
                        egal('z3.jpg', montree(), 'gardé au rafraîchissement')
                        taches = #S.taches
                        Fenetre.agrandir()
                        lancerDepuis(taches)
                        egal(1, #demandes)
                        egal(Stockage.dossier(c.id), demandes[1].dossier)
                        egal('z3.jpg', demandes[1].nom)
                        egal(dialogues + 1, #S.dialogues, 'Agrandir : la fenêtre du zoom')
                        Lightroom.photos = lire
                        egal(0, envois, 'sans Claude')
                        egal(0, photos, 'sans rien demander à Lightroom')
                    end)
                end)
            end)
            egal(true, Fenetre.voirZoom(), 'rend vrai avec un zoom')
            -- Sans plafond mesuré : le bouton reste là (il ne suit plus la ligne du plafond, retirée
            -- au correctif 1.3.2).
            avec(Notation, 'proposition', function()
                local x = copieProposition()
                x.plafond = nil
                return x
            end, function()
                Fenetre.rafraichirNotation()
                egal(nil, p.aPlafond)
                egal('actif', etat())
            end)
            Fenetre.rafraichirNotation()
        end)
    end)
end)

essai('Carte Note : la grille des critères (Fenetre.lignesCriteres) ; état en gras de sa couleur, verdicts en gras ; balises de Claude retirées ; page par page', function()
    local largeurs = { plein = D.largeurNote, critere = D.texteCritere }
    local lignes = Fenetre.lignesCriteres(copieProposition(), largeurs)
    egal('etat', lignes[1].genre)
    egal(1, (lignes[1].texte:find('<EM>Passe 2 · à vérifier.</EM> Tient seule', 1, true)), lignes[1].texte)
    local etiquettes = {}
    for _, l in ipairs(lignes) do
        balisesFermees(l.texte)
        local largeur = l.genre == 'critere' and D.texteCritere or D.carte
        vrai(Fil.largeur(l.texte, 'texte12', 'gras12') <= largeur - Fil.MARGE, string.format('%.0f pour %d : %s', Fil.largeur(l.texte, 'texte12', 'gras12'), largeur, l.texte))
        if l.etiquette ~= '' then
            etiquettes[#etiquettes + 1] = l.etiquette .. '=' .. Texte.debut(l.texte, 10)
        end
    end
    egal('Impact=<EM>Moyen. Qualités=<EM>Bonnes Plancher technique=Netteté 41 Finition=Pour 5 ★ s', table.concat(etiquettes, ' '),
        'du plus lourd au plus léger, verdicts en gras')
    -- Les verdicts : deux mots au plus, jusqu'au premier point ; jamais une phrase.
    egal('Moyen.', (Fenetre.verdict('Moyen. Le ciel.')))
    egal('Fort', (Fenetre.verdict('Fort')))
    egal('Nette (44).', (Fenetre.verdict('Nette (44). Bien.')))
    egal(nil, (Fenetre.verdict('Le ciel arrête l\'œil.')))
    egal(nil, (Fenetre.verdict('Netteté 41 : nette.')))
    -- Une balise venue de Claude ne passe pas.
    local balisee = Fenetre.lignesCriteres(copieProposition({ raison = 'Un <EM>ciel</EM> fort.', criteres = { impact = '<EM>Fort</EM>' } }), largeurs)
    egal('<EM>Passe 2 · à vérifier.</EM> Un ciel fort.', balisee[1].texte)
    egal('<EM>Fort</EM>', balisee[2].texte)
    -- Les états, au besoin sans passe connue.
    egal('Passe 2 · changée : 4 ★', Fenetre.enteteNote(copieProposition({ etat = 'changee', note_choisie = 4 })))
    egal('Passe 2 · changée : rejetée', Fenetre.enteteNote(copieProposition({ etat = 'changee', drapeau_choisi = 'rejetee' })))
    local sansPasse = copieProposition({ etat = 'ecartee' })
    sansPasse.passe = nil
    egal('Écartée', Fenetre.enteteNote(sansPasse))
    sansPasse.etat, sansPasse.a_verifier = 'proposee', true
    egal('Proposée · à vérifier', Fenetre.enteteNote(sansPasse))
    -- Sans proposition : l'aide, en lignes pleine largeur.
    local aide = Fenetre.lignesCriteres(nil, largeurs)
    for _, l in ipairs(aide) do
        egal('plein', l.genre)
    end
    -- Dans la fenêtre : la page, ▲ ▼ ; la même proposition relue garde sa page.
    photoNotee(4961, 'DSCF4961.RAF', 0, 0)
    Moteur.nouvelle()
    -- Chaque critère répété autant de fois que la grille a de lignes : plus de deux pages.
    local longue = copieProposition()
    for _, cle in ipairs({ 'impact', 'qualites', 'plancher' }) do
        longue.criteres[cle] = string.rep(longue.criteres[cle] .. ' ', D.criteres + 1)
    end
    avecRegistre(longue, function()
        ouvrirFenetre(function(p, contenu)
            Fenetre.rafraichir()
            egal(true, p.noteDescend, 'plus long que la grille')
            local note = variantes(contenu).notation
            local descendre
            for _, x in ipairs(vues(note)) do
                if S.BOUTONS[x.genre] and type(x.args.enabled) == 'table' and x.args.enabled.key == 'noteDescend' then
                    descendre = x
                end
            end
            local derniere = p['nt' .. (D.criteres + 1)]
            S.cliquer(descendre)
            egal(derniere, p.nt1, 'une page plus bas')
            egal(true, p.noteMonte)
            Fenetre.rafraichirNotation()
            egal(derniere, p.nt1, 'relue : la même page')
            egal(0, #S.refusDeLaFenetre(), 'aucun refus de texte riche')
            -- La ligne montrée a sa variante, et une seule.
            for k = 1, D.criteres + 1 do
                local montrees = 0
                for _, x in ipairs(vues(note)) do
                    local t = x.args.title
                    if x.genre == 'static_text' and type(t) == 'table' and t.key == 'nt' .. k and S.montreeDansFenetre(x) then
                        montrees = montrees + 1
                    end
                end
                egal(p['ng' .. k] == 'vide' and 0 or 1, montrees, 'ligne ' .. k .. ' (' .. p['ng' .. k] .. ')')
            end
        end)
    end)
end)

-- Fin -------------------------------------------------------------------------------------------------

Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
