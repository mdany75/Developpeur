-- essais-fenetre-b.lua : la fenêtre Claude à l'allure de la fenêtre B (1.3, lot B3 : en-tête et ses
-- voyants, barre du fil, zone de saisie, colonne droite avec ses segments et son panneau ; agrandie
-- à 1 497 × 1 200 puis élargie à 1 948 × 1 200, demandé par Dany le 21 octobre 2026 ; sans le volet
-- des conversations de gauche, 1 623 × 1 200, au correctif 1.3.6), hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : les dimensions (contenu de 1 621 × 1 166, D7, chaque
-- colonne estimée, la fenêtre dans l'écran de Dany, la longueur des lignes du fil), plus de volet
-- (ses boutons, Rechercher, la liste, les versions : au menu, dans l'infobulle du voyant Lightroom),
-- l'inventaire de l'en-tête (ses trois voyants), de la barre, de la saisie et des segments (chaque
-- élément trouvé par son titre, son infobulle ou son image, son action éprouvée par un clic simulé,
-- S.cliquer), les briques (Fenetre.bouton carré ou à icône, Fenetre.calque, Vues.boutonBleu,
-- Vues.inactif, les aplats), le Mode (plus de radios, correctif 1.3.6), la légende de la photo
-- active (Lightroom.legende) et l'apparence (couleurs et images reprises à l'ouverture). Puis le fil
-- (lot B4) : les polices mesurées (Metriques), le texte riche (largeur, coupe, balises fermées),
-- l'auteur et l'heure de chaque tour (sur des copies), la ligne d'un appel et « Pourquoi ? », la
-- ligne d'actions (« ☆ Voir la note »), leurs clics et le bandeau sur deux lignes ; essais-carnet.lua
-- éprouve la carte de l'onglet Suivi. Enfin les cartes (lot B5) : sur leurs images, leurs hauteurs et ce qui y
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

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
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

-- Les colonnes de la racine : centre, filet, colonne droite (le volet et son filet sont retirés au
-- correctif 1.3.6).
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
-- par pixel, constaté), sans le volet de gauche ni son filet (325 : correctif 1.3.6, décision de
-- Dany du 25 octobre 2026) : la fenêtre entière, le centre et la colonne droite (celle de la
-- maquette), et l'aperçu à la largeur de l'intérieur du panneau. La seule copie de ces chiffres dans
-- les essais ; le reste se tire de Dispositions.
local DEMANDE = { largeur = 1623, hauteur = 1200, centre = 1064, droite = 556, apercu = 498, apercuHauteur = 332 }
local ECRAN_DANY = { largeur = 3440, hauteur = 1440 }
-- La barre des menus de macOS sur un écran sans encoche : 24 points, et son filet.
local BARRE_MENUS = 25
-- La place que la fenêtre laisse à Lightroom à côté d'elle, sur cet écran (environ 1 815 points
-- depuis le retrait du volet, correctif 1.3.6 ; 1 490 avant).
local PLACE_LIGHTROOM = 1815

essai('Cadre : la fenêtre demandée par Dany, sans son volet (1 623 × 1 200), son contenu (D7) ; les colonnes, le fil et les images concordent', function()
    local largeur, haut = S.contenuPourFenetre(DEMANDE.largeur, DEMANDE.hauteur)
    egal(DEMANDE.largeur, D.largeurFenetre)
    egal(DEMANDE.hauteur, D.hauteurFenetre)
    egal(largeur, D.largeurContenu, 'contenu : largeur (D7)')
    egal(haut, D.hauteurContenu, 'contenu : hauteur (D7 : barre de 33, marge de 1 en bas, aucune en haut)')
    egal(nil, D.volet, 'plus de volet (correctif 1.3.6)')
    egal(nil, D.liste)
    egal(nil, D.cases)
    egal(DEMANDE.centre, D.centre)
    egal(DEMANDE.droite, D.droite, 'la colonne droite de la maquette, inchangée')
    egal(D.largeurContenu, D.centre + D.filet + D.droite, 'centre, filet, colonne droite')
    egal(D.centre - 2 * D.margeCentre, D.fil, 'centre : sa largeur utile')
    -- Le fil garde sa largeur (des lignes d'environ 150 caractères : choix de Dany).
    egal(952, D.texteFil, 'le texte du fil, inchangé')
    egal(D.panneau, D.droite - 2 * D.margeDroite, 'colonne droite : le panneau entre ses marges')
    -- Le centre : en-tête et son filet, fil, barre, saisie, exactement ; le fil a autant de lignes
    -- que sa hauteur en tient entre ses marges (une de plus n'y tiendrait pas), le reste va à sa
    -- marge du bas.
    egal(D.hauteurContenu, D.entete + D.filet + D.hauteurFil + D.barre + D.saisie, 'le centre de haut en bas')
    egal(D.lignes * D.hauteurLigne, D.grille, 'la grille du fil : ses lignes de ' .. D.hauteurLigne)
    local bas = D.hauteurFil - D.margeHautFil - D.grille
    vrai(bas >= D.margeBasFil, string.format('marge du bas du fil : %d (au moins %d)', bas, D.margeBasFil))
    vrai(bas - D.hauteurLigne < D.margeBasFil, string.format('une ligne de plus tiendrait (%d lignes, marge du bas de %d)', D.lignes, bas))
    -- Le titre de l'en-tête prend ce que le Mode laisse ; la photo active, ce que les trois voyants
    -- laissent.
    egal(D.fil, D.titre + D.placeRepartir, 'le titre et la place de « Repartir à neuf » (celle du Mode)')
    egal(nil, D.placeMode)
    vrai(D.repartir <= D.placeRepartir, 'Repartir à neuf tient dans sa place')
    vrai(require('Fil').largeur('Repartir à neuf', 'texte12') + 2 * 12 <= D.repartir, 'son titre tient dans le bouton')
    egal(D.fil, (8 + 6 + D.voyantClaude) + D.ecartVoyants + (8 + 6 + D.voyantLightroom) + D.ecartVoyants + (8 + 6 + D.voyantEcran) + D.info,
        'les voyants et la photo active')
    vrai(D.info >= 400, 'la photo active garde sa place : ' .. D.info)
    -- Les images de Dispositions.IMAGES concordent avec les tailles (plus de fond de sélection ni de
    -- loupe : le volet est retiré).
    local I = Dispositions.IMAGES
    egal(nil, I.selection)
    egal(nil, I.loupe)
    egal(D.panneau, I.panneau.largeur, 'panneau')
    egal(D.hauteurContenu, D.margeHautDroite + I.panneau.hauteur + D.margeBasDroite, 'le panneau sur toute la colonne, entre ses marges')
    for _, nom in ipairs({ 'carte-note', 'carte-proposition', 'carte-etape', 'carte-focus', 'carte-suivi' }) do
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
    -- Le cadre enregistré change de nom : Lightroom rend à une fenêtre rouverte sa taille
    -- enregistrée, et la fenêtre sans volet ne doit pas reprendre la largeur de 1 948 (FORME 4).
    egal(5, Fenetre.FORME)
    egal('DeveloppeurClaude-conversation-grande-5', Fenetre.cadre())
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

essai("Cadre : à une autre hauteur de fenêtre, le fil, le panneau et les cartes suivent (rien n'est écrit pour une seule hauteur)", function()
    local I = Dispositions.IMAGES
    -- À la hauteur de la fenêtre : les cartes se tirent de la place sous l'aperçu.
    egal(D.placeCartes - D.autourNote, I['carte-note'].hauteur, 'carte Note : la place des cartes, moins sa grille')
    for _, nom in ipairs({ 'carte-proposition', 'carte-etape', 'carte-focus', 'carte-suivi' }) do
        egal(D.placeCartes - D.sousCarte, I[nom].hauteur, nom .. ' : la place des cartes, moins ce qu\'elle laisse sous elle')
    end
    -- Deux cents points de moins, puis de plus : chaque zone suit, autant de lignes que sa place en
    -- tient.
    for _, ecart in ipairs({ -200, 200 }) do
        local Autre = dispositionsAHauteur(D.hauteurFenetre + ecart)
        local A, J = Autre.dimensions(), Autre.IMAGES
        local quoi = string.format(' (fenêtre de %d de haut)', A.hauteurFenetre)
        egal(D.hauteurContenu + ecart, A.hauteurContenu, 'contenu' .. quoi)
        egal(D.hauteurFil + ecart, A.hauteurFil, 'fil' .. quoi)
        egal(math.floor((A.hauteurFil - A.margeHautFil - A.margeBasFil) / A.hauteurLigne), A.lignes, 'lignes du fil' .. quoi)
        vrai(ecart < 0 and A.lignes < D.lignes or A.lignes > D.lignes, 'les lignes du fil suivent' .. quoi)
        egal(I.panneau.hauteur + ecart, J.panneau.hauteur, 'panneau' .. quoi)
        egal(A.hauteurContenu, A.margeHautDroite + J.panneau.hauteur + A.margeBasDroite, 'panneau entre ses marges' .. quoi)
        egal(D.placeCartes + ecart, A.placeCartes, 'place des cartes' .. quoi)
        egal(A.placeCartes - A.autourNote, J['carte-note'].hauteur, 'carte Note' .. quoi)
        for _, nom in ipairs({ 'carte-proposition', 'carte-etape', 'carte-focus', 'carte-suivi' }) do
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
        egal(3, #cols, 'centre, filet, colonne droite (plus de volet)')
        egal(0, contenu.args.spacing, 'sans écart')
        egal(0, contenu.args.margin, 'sans marge')
        local total = 0
        for _, c in ipairs(cols) do
            vrai(type(c.args.width) == 'number', c.genre .. ' sans largeur')
            total = total + c.args.width
            local h = hauteur(c)
            vrai(h <= D.hauteurContenu, string.format('colonne de %d de haut (au plus %d)', h, D.hauteurContenu))
            -- Ce que porte la colonne sur son aplat (le centre, la colonne droite) : son
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
        -- Le filet de la colonne droite, sous l'en-tête, au-dessus de la barre, au-dessus de la saisie
        -- (ceux du volet sont retirés avec lui au correctif 1.3.6 ; celui du plafond de la carte Note
        -- avec sa ligne, correctif 1.3.2).
        egal(4, filets, 'filets de 1 point')
        -- Le premier aplat de chaque colonne est à sa taille : centre, droite, sur la hauteur du contenu.
        for _, k in ipairs({ 1, 3 }) do
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

essai("Plus de volet (correctif 1.3.6) : ni Nouvelle conversation, Rechercher, cases, Renommer…, Supprimer…, ni versions ; Publication… et Consommation… au menu", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        for _, titre in ipairs({ '＋ Nouvelle conversation', 'Renommer…', 'Supprimer…', 'Publication…', 'Consommation…' }) do
            refuse(function() parTitre(contenu, titre) end, 'introuvable', 'plus de « ' .. titre .. ' »')
        end
        refuse(function() liee(contenu, 'edit_field', 'recherche') end, 'introuvable', 'plus de Rechercher')
        refuse(function() calqueCase(contenu, 1) end, 'introuvable', 'plus de cases')
        for _, cle in ipairs({ 'versionTexte1', 'versionTexte2' }) do
            refuse(function() liee(contenu, 'static_text', cle) end, 'introuvable', 'plus de ligne de version')
        end
        for _, v in ipairs(vues(contenu)) do
            vrai(not (v.genre == 'picture' and type(v.args.value) == 'string'
                and (v.args.value:match('/loupe%.png$') or v.args.value:match('/selection%.png$'))), 'image du volet : ' .. tostring(v.args.value))
        end
        egal(nil, p.recherche)
        egal(nil, p.lg1)
        for _, nom in ipairs({ 'publication', 'consommation', 'nouvelle', 'renommer', 'supprimer', 'cliquerListe', 'rafraichirVersions',
            'photoDeLaConversation' }) do
            vrai(nom == 'nouvelle' or Fenetre[nom] == nil, 'Fenetre.' .. nom .. ' retiré')
        end
        -- Fenetre.nouvelle reste (une conversation vide, sans photo) ; une photo choisie dans Lightroom
        -- montre la sienne (Fenetre.suivreSelection, essais-une-photo.lua).
        egal('function', type(Fenetre.nouvelle))
        -- Publication… et Consommation… restent au menu Module externe - Extras, dans les deux.
        local info = dofile(S.plugin .. '/Info.lua')
        for _, menu in ipairs({ info.LrExportMenuItems, info.LrLibraryMenuItems }) do
            local titres = {}
            for _, item in ipairs(menu) do
                titres[item.title] = item.file
            end
            egal('MenuPublication.lua', titres['Publication…'])
            egal('MenuConsommation.lua', titres['Consommation…'])
        end
        -- Le voyant Écran (en bas du volet jusque-là) est dans l'en-tête ; un clic le relit dans une
        -- tâche (essai de l'en-tête, et tests.lua).
        local ecran = liee(contenu, 'static_text', 'texteEcran')
        local appels = 0
        avec(Fenetre, 'montrerEcran', function() appels = appels + 1 end, function()
            local taches = #S.taches
            S.cliquer(ecran)
            S.taches[taches + 1]()
        end)
        egal(1, appels, 'le voyant Écran se relit au clic')
    end)
end)

essai('Inventaire de l\'en-tête : titre en gras 16 sans ✎, « Repartir à neuf » à la place du Mode, voyants Claude Code, Lightroom (versions et mode dans son infobulle) et Écran, photo active en texte riche', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local titre = liee(contenu, 'static_text', 'titre')
        egal('<system/bold>', titre.args.font.name)
        egal(16, titre.args.font.size)
        egal(D.titre, titre.args.width, 'le titre garde sa largeur : « Repartir à neuf » à sa droite')
        refuse(function() parTitre(contenu, '✎') end, 'introuvable', 'plus de ✎')
        -- Le Mode est retiré (correctif 1.3.6) : ni « Mode : », ni radios ; « Repartir à neuf » prend
        -- sa place, à droite du titre (essais-une-photo.lua : ce qu'il fait).
        refuse(function() parTitre(contenu, 'Mode :', 'static_text') end, 'introuvable', 'plus de « Mode : »')
        for _, v in ipairs(vues(contenu)) do
            vrai(v.genre ~= 'radio_button', 'plus de radio')
        end
        local rangeeTitre = rangeeDe(contenu, titre)
        egal(3, #rangeeTitre.args, 'le titre, un espace, puis « Repartir à neuf »')
        local repartir = rangeeTitre.args[3]
        egal('square_button', repartir.genre)
        egal('Repartir à neuf', repartir.args.title)
        egal(D.repartir, repartir.args.width)
        egal('peutRepartir', repartir.args.enabled.key, 'grisé selon peutRepartir')
        vrai(Fenetre.parBouton(repartir.args.action), 'par Fenetre.bouton (annule l\'envoi automatique)')
        -- Trois voyants, dans la rangée de la photo active : Claude Code sans clic, Lightroom qui
        -- démarre la liaison (son infobulle, liée : les versions et le mode de la liaison), Écran qui
        -- se relit (venu du bas du volet, correctif 1.3.6).
        local claude, liaison = liee(contenu, 'static_text', 'texteClaude'), liee(contenu, 'static_text', 'texteLightroom')
        local ecran = liee(contenu, 'static_text', 'texteEcran')
        egal(nil, claude.args.mouse_down, 'Claude Code : sans clic')
        local demarree = false
        avec(Fenetre, 'demarrerLiaison', function() demarree = true end, function() S.cliquer(liaison) end)
        vrai(demarree, 'le voyant Lightroom démarre la liaison')
        egal('infobulleLightroom', liaison.args.tooltip.key, "l'infobulle du voyant Lightroom, liée")
        local Composants = require 'Composants'
        egal(Fenetre.infobulleLightroom(require('Lightroom').liaison(), Composants.lignes(Composants.module(), '…'), 'appliquer'),
            valeur(liaison, 'tooltip', p), "l'infobulle avant la lecture du connecteur")
        contient(valeur(liaison, 'tooltip', p), 'Versions : Développeur ' .. Composants.module() .. ' ; MCP-Développeur …')
        contient(valeur(liaison, 'tooltip', p), 'Mode de la liaison : Appliquer')
        vrai(ecran.args.mouse_down, 'le voyant Écran se relit au clic')
        egal(D.voyantEcran, ecran.args.width)
        -- Les trois voyants (chacun sa rangée : sa pastille et son texte) dans la rangée de la photo
        -- active, dans cet ordre.
        local rangee, ordre = rangeeDe(contenu, liee(contenu, 'static_text', 'infoPhoto')), {}
        for _, e in ipairs(rangee.args) do
            if type(e) == 'table' and e.genre == 'row' then
                for _, v in ipairs({ claude, liaison, ecran }) do
                    if e.args[2] == v then
                        ordre[#ordre + 1] = v.args.title.key
                    end
                end
            end
        end
        egal('texteClaude texteLightroom texteEcran', table.concat(ordre, ' '), 'les trois voyants dans la rangée de la photo active')
        -- Les versions et le mode, dans les mots de l'infobulle.
        egal("Liaison avec le connecteur MCP-Développeur : active. Versions : Développeur 1.3.6 ; MCP-Développeur 1.3.5 · à mettre à jour. "
            .. "Mode de la liaison : Proposer d'abord (Gestionnaire de modules externes).",
            Fenetre.infobulleLightroom('active', Composants.lignes('1.3.6', '1.3.5'), 'proposer'))
        egal(true, Fenetre.alerteVersions(Composants.lignes('1.3.6', '1.3.5')))
        egal(false, Fenetre.alerteVersions(Composants.lignes('1.3.6', '1.3.6')))
        egal(false, Fenetre.alerteVersions(Composants.lignes('1.3.6', '…')), "« … » pas encore lu : pas d'alerte")
        contient(Fenetre.infobulleLightroom('erreur', {}, nil), 'en erreur, un clic la relance. Versions : ?. Mode de la liaison : Appliquer')
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
        p.message = Fenetre.NOTE_AUTRE_PHOTO
        egal(Fenetre.NOTE_AUTRE_PHOTO, valeur(message, 'tooltip', p), "l'infobulle du message, en entier")
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

essai('Segments : Aperçu | Focus | Proposition | Note | Suivi en images sous calques ; un clic choisit l\'onglet, son crochet suit, sans envoyer la demande', function()
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
        egal('apercu focus proposition notation suivi', table.concat(recus, ' '), 'un vrai clic : le crochet de chaque onglet')
        -- La rangée ◀ légende ▶ · ⤢ Agrandir est commune aux cinq onglets.
        for _, titre in ipairs({ '◀', '▶', '⤢ Agrandir' }) do
            local b = parTitre(contenu, titre)
            egal(nil, b.args.visible, titre .. ' : hors des onglets')
            egal(22, S.bezelVisible(b))
        end
        egal(nil, liee(contenu, 'static_text', 'legendeApercu').args.visible)
        -- Plus de segment ni de carte Leçon (correctif 1.3.6) : Suivi, le dernier, à sa place.
        egal(0, #segment('lecon'), 'plus de segment Leçon')
        egal(2, #segment('suivi'), 'le segment Suivi et sa variante bleue')
        egal('suivi', D.onglets[#D.onglets].valeur, 'Suivi, le dernier')
        egal(nil, Fenetre.AUCUNE_LECON)
        egal(nil, Vues.lecon)
    end)
end)

-- Mode -----------------------------------------------------------------------------------------------

-- Correctif 1.3.6 : la rangée Mode de l'en-tête (Appliquer, Proposer d'abord, Je le fais) est
-- retirée, avec ce qui la tirait de l'état et la reposait (D12) ; la fenêtre suit la préférence
-- `mode`, que le Gestionnaire de modules externes règle. Fenetre.lierRadio reste : Mes demandes s'en
-- sert.
essai("Mode : plus de radios ni de valeur reposée ; la préférence du Gestionnaire reste telle quelle, la fenêtre n'y touche pas", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local prefs = require('Preferences').lire()
    prefs.mode = 'proposer'
    ouvrirFenetre(function(p, contenu)
        for _, v in ipairs(vues(contenu)) do
            vrai(v.genre ~= 'radio_button', 'plus de radio')
        end
        egal(nil, p.mode, 'plus de clé mode dans la fenêtre')
        for _, nom in ipairs({ 'modeMontre', 'rafraichirMode', 'reposerMode', 'changerMode', 'TOUR_REPOSER_MODE', 'LIBELLES_MODE',
            'EXERCICE_CONTINUE', 'jeLeFais', 'suivreExercice' }) do
            egal(nil, Fenetre[nom], 'Fenetre.' .. nom .. ' retiré')
        end
        egal('function', type(Fenetre.lierRadio), 'gardé pour Mes demandes')
        Fenetre.rafraichir()
        -- La boucle tourne quelques tours sans rien reposer.
        local LrTasks = S.modules.LrTasks
        local dormir, tours = LrTasks.sleep, 0
        LrTasks.sleep = function()
            tours = tours + 1
            if tours >= 3 then
                error('arrêt de la boucle', 0)
            end
        end
        local ok, e = pcall(Fenetre.boucle, Fenetre.generation)
        LrTasks.sleep = dormir
        vrai(not ok and e == 'arrêt de la boucle', tostring(e))
        egal(nil, p.mode)
        egal('proposer', prefs.mode, 'la fenêtre ne change pas le mode de la liaison')
        egal('proposer', require('Lightroom').mode())
    end)
    prefs.mode = 'appliquer'
end)

-- Liste des conversations -----------------------------------------------------------------------------
-- (Retirée avec le volet au correctif 1.3.6 : ses périodes, ses cases et ses pages ; essai « Plus de
-- volet », plus haut.)

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
-- note (19 h 46) ; Claude note la photo active et une autre, et l'explique (plus de leçon de la
-- photo depuis le correctif 1.3.6).
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

essai("Fil : le tour de Claude qui a noté finit par une ligne d'actions, après son texte (maquette) ; un tour chacun, une ligne chacun", function()
    local c = conversationMaquette()
    local n = elementDe(c, 'notation')
    local lignes = Fil.lignes(c, D.texteFil)
    local actions = {}
    for k, x in ipairs(lignes) do
        if x.genre == 'actions' then
            actions[#actions + 1] = x.actions .. ':' .. tostring(x.notation) .. ':' .. tostring(x.lecon) .. '@' .. k
        end
    end
    egal('note:' .. n .. ':nil@' .. #lignes, table.concat(actions, ' '), 'une ligne, à la fin du tour ; plus de leçon (correctif 1.3.6)')
    contient(lignes[#lignes - 1].texte, 'feuillage', 'après le texte de Claude')
    egal(nil, Fil.valeurActions(nil, nil))
    egal('note', Fil.valeurActions(n, nil))
    egal('note+demande', Fil.valeurActions(n, 9))
    egal('demande', Fil.valeurActions(nil, 9))
    -- Une demande entre les notes et le texte de Claude : la ligne d'actions finit le tour des notes.
    local d = conversationMaquette()
    local m = elementDe(d, 'notation')
    table.insert(d.elements, m + 1, { id = 'entre', genre = 'dany', texte = 'Et pourquoi 3 ?', date = T0 + 242, images = {}, changements = {} })
    actions = {}
    local dLignes = Fil.lignes(d, D.texteFil)
    for k, x in ipairs(dLignes) do
        if x.genre == 'actions' then
            actions[#actions + 1] = x.actions
            egal('dany', dLignes[k + 2] and dLignes[k + 2].genre, 'avant la demande suivante')
        end
    end
    egal('note', table.concat(actions, ' '))
    -- Une notation refusée, ou en cours : pas de « Voir la note ».
    d.elements[m].etat = 'erreur'
    for _, x in ipairs(Fil.lignes(d, D.texteFil)) do
        vrai(x.actions ~= 'note', 'notation refusée : ' .. tostring(x.actions))
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
            elseif S.BOUTONS[v.genre] and v.args.title == '☆ Voir la note' then
                egal('square_button', v.genre)
                vrai(S.bezelVisible(v) + S.MARGE_BEZEL <= D.hauteurLigne, 'dans sa ligne')
                actions = actions + (S.montreeDansFenetre(v) and 1 or 0)
            end
        end
        egal(1, pourquoi, 'un seul « Pourquoi ? » montré')
        egal(1, actions, '« ☆ Voir la note » sur une ligne')
        refuse(function() parTitre(contenu, 'Leçon de la photo') end, 'introuvable', 'plus de « Leçon de la photo »')
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

essai("Fil dans la fenêtre : « Pourquoi ? » (clic) ouvre l'onglet Aperçu sur son étape ; « ☆ Voir la note » l'onglet Note, sans changer la sélection, le bandeau dit de choisir la photo", function()
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
        egal('note', p['x' .. i])
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
        p.onglet = 'notation'
        photoActive(4961, 'DSCF4961.RAF')
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
    -- et les refus du moteur, provoqués ici : Claude au travail, une ancienne séance de notation
    -- (raccourcis au lot B5 : ils finissaient par « … » ; Je le fais sans photo active est retiré au
    -- correctif 1.3.6).
    local refus = {}
    local travaille, courante, conversations = Moteur.travaille, Moteur.courante, Moteur.conversations
    local ok, erreur = pcall(function()
        Moteur.travaille = true
        refus[#refus + 1] = select(2, Moteur.envoyer('Bonjour'))
        Moteur.travaille = false
        local seance = Conversation.nouvelle()
        seance.genre = 'notation'
        Moteur.conversations = { seance }
        refus[#refus + 1] = select(2, Moteur.ouvrir(seance.id))
    end)
    Moteur.travaille, Moteur.courante, Moteur.conversations = travaille, courante, conversations
    assert(ok, erreur)
    -- Le refus d'un envoi pendant le travail est celui des autres refus du moteur (Arrêter compris).
    egal(Fenetre.CLAUDE_TRAVAILLE, refus[1], "le refus d'un envoi, comme les autres")
    egal("Claude travaille : attendez la fin, ou cliquez Arrêter. | Une ancienne séance de notation ne s'ouvre plus.",
        table.concat(refus, ' | '), 'les refus du moteur, raccourcis')
    egal(nil, Fenetre.CHOISIR_CONVERSATION, 'retiré avec la page du carnet (correctif 1.3.6)')
    -- « Repartir à neuf » (correctif 1.3.6) : sans photo seule, une conversation montrée qui n'est pas
    -- celle de la photo active, et ce qui est fait ; « Obtenir » (onglet Proposition) : sans photo
    -- seule, une proposition qui attend déjà.
    local messages = { Fenetre.CLAUDE_TRAVAILLE, Fenetre.NOTE_AUTRE_PHOTO, Fenetre.PAS_D_IMAGE,
        "Écrivez une demande avant d'envoyer.", Fenetre.NOTE_EN_COURS, Fenetre.AUCUNE_PHOTO, refus[1], refus[2],
        Fenetre.REPARTIR_SANS_PHOTO, Fenetre.REPARTIR_AUTRE, Fenetre.REPARTIE, Fenetre.OBTENIR_SANS_PHOTO,
        Fenetre.OBTENIR_EN_ATTENTE }
    egal(13, #messages, 'chaque message, aucun nil')
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

-- (Le tableau du carnet en Menlo, à la largeur du fil, est retiré avec la page du carnet au
-- correctif 1.3.6 : essais-carnet.lua éprouve la carte de l'onglet Suivi.)
-- Cartes (lot B5) ------------------------------------------------------------------------------------

local Images = require 'Images'
local Stockage = require 'Stockage'

local INFOBULLE_ACCEPTER_NOTE = "Poser la note proposée dans Lightroom (sans Claude ni quota)"
local INFOBULLE_ACCEPTER_PROPOSITION = "Appliquer la proposition : la photo ne change qu'à ce clic"

-- La colonne superposée des variantes des onglets (Aperçu, Focus, Proposition, Note, Suivi), et chacune.
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

-- La colonne superposée posée sur cette image de carte (Vues.focus, Vues.proposition…).
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
    for _, cle in ipairs({ 'largeurNote', 'largeurProposition', 'largeurEtape', 'largeurFocus', 'largeurSuivi' }) do
        egal(D.carte, D[cle], cle)
    end
    egal(nil, D.largeurLecon, "plus de carte de la leçon (correctif 1.3.6)")
    -- Les cartes en 12 points ; la note, Focus et Suivi gardent leurs passages balisés (gras 12).
    for cle, carte in pairs(Fenetre.CARTES) do
        egal('texte12', carte.police, 'CARTES.' .. cle)
    end
    egal('gras12', Fenetre.CARTES.note.emphase)
    egal('gras12', Fenetre.CARTES.focus.emphase)
    egal('gras12', Fenetre.CARTES.suivi.emphase)
    egal(nil, Fenetre.CARTES.lecon)
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
        -- son contenu à 13 du bord et 12 du haut (comme Vues.focus).
        for _, nom in ipairs({ 'carte-note', 'carte-proposition', 'carte-etape', 'carte-focus', 'carte-suivi' }) do
            local carte = carteSur(contenu, nom)
            egal(Dispositions.IMAGES[nom].hauteur, carte.args.height, nom .. ' : la hauteur de son image')
            egal(D.interieur, carte.args.width, nom)
            local dedans = carte.args[2]
            egal(D.margeCarte, dedans.args.margin_left, nom .. ' : marge de gauche')
            egal(12, dedans.args.margin_top, nom .. ' : marge du haut')
            vrai(hauteur(carte) <= carte.args.height, nom .. ' : son contenu y tient')
            -- Ses lignes la remplissent (Dispositions.TAILLES : criteres, propLignes, etapeLignes,
            -- focusLignes, suiviLignes) : au moins la marge du haut sous le contenu, et une ligne de plus (16 dans
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
        for _, cle in ipairs({ 'propositionTexte', 'etapeTexte', 'focusTexte', 'suiviTexte' }) do
            local t = liee(contenu, 'static_text', cle)
            egal(D.carte, t.args.width, cle)
            egal(Fenetre.POLICES.texte12, t.args.font, cle)
        end
        egal(D.propLignes, liee(contenu, 'static_text', 'propositionTexte').args.height_in_lines)
        egal(D.etapeLignes, liee(contenu, 'static_text', 'etapeTexte').args.height_in_lines)
        egal(D.suiviLignes, liee(contenu, 'static_text', 'suiviTexte').args.height_in_lines)
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

essai('Inventaire des cartes Proposition et Aperçu (étape) : titres, textes, carrés (Obtenir compris), Accepter en bleu ; chaque bouton à sa clé ; la rangée tient dans le panneau', function()
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
        egal('▲=propositionMonte ▼=propositionDescend Obtenir=peutObtenir Refuser=enAttente Ajuster…=enAttente', table.concat(cles, ' '),
            'Obtenir, puis Refuser et Ajuster… ; plus de Je le fais (correctif 1.3.6)')
        -- Obtenir, Refuser et Ajuster… : des carrés de bezel 26, titres en 13, comme sous la carte
        -- Note ; la largeur d'Obtenir vient de Dispositions.TAILLES et tient son titre.
        local obtenir = parTitre(proposition, 'Obtenir')
        for _, titre in ipairs({ 'Obtenir', 'Refuser', 'Ajuster…' }) do
            local b = parTitre(proposition, titre)
            egal('square_button', b.genre, titre .. ' : un carré')
            egal(26, S.bezelVisible(b), titre .. ' : bezel de 26')
            egal(Fenetre.POLICES.systeme13, b.args.font, titre .. ' : titre en 13')
        end
        egal(Dispositions.TAILLES.obtenir, obtenir.args.width, 'Obtenir : sa largeur de TAILLES')
        egal(D.obtenir, obtenir.args.width)
        vrai(Fil.largeur('Obtenir', 'texte') + 12 <= D.obtenir, 'son titre tient')
        -- La rangée (▲ ▼, l'espace, Obtenir, Refuser, Ajuster…, Accepter en bleu) tient dans
        -- l'intérieur du panneau, en comptant 30 points par flèche mini (▲ ▼).
        local rangee = rangeeDe(proposition, obtenir)
        egal(rangee, rangeeDe(proposition, parTitre(proposition, 'Refuser')), 'Obtenir et Refuser, dans la même rangée')
        local bleu = Dispositions.IMAGES['bouton-bleu'].largeur
        local total = 2 * 30 + 2 + D.obtenir + 8 + D.refuser + 8 + D.ajuster + 8 + bleu
        vrai(total <= D.interieur, string.format('rangée de la carte Proposition : %d points pour %d', total, D.interieur))
        local ordre = {}
        for _, x in ipairs(rangee.args) do
            if type(x) == 'table' and S.BOUTONS[x.genre] and x.args.title ~= nil then
                ordre[#ordre + 1] = x.args.title
            elseif type(x) == 'table' and x.genre == 'spacer' then
                vrai(x.args.fill_horizontal or x.args.width == 8, 'entre les boutons : 8')
            end
        end
        egal('Obtenir Refuser Ajuster…', table.concat(ordre, ' '), "l'ordre de la rangée, Accepter en bleu au bout")
        local accepter = parInfobulle(proposition, INFOBULLE_ACCEPTER_PROPOSITION)
        vrai(Fenetre.parCalque(accepter.args.mouse_down), 'Accepter de la proposition : un calque')
        refuse(function() liee(proposition, 'static_text', 'exerciceEtat') end, 'introuvable', "plus d'état de l'exercice")
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
