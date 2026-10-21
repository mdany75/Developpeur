-- essais-fenetre-b.lua : la fenêtre Claude à l'allure de la fenêtre B (1.3, lot B3 : cadre de
-- 1 280 × 800, volet des conversations en cases, en-tête avec le Mode, barre du fil, zone de
-- saisie, colonne droite avec ses segments et son panneau), hors de Lightroom (LuaJIT, Lightroom
-- simulé par Simulation.lua) : les dimensions (contenu de 1 278 × 766, D7, et chaque colonne
-- estimée), l'inventaire du volet, de l'en-tête, de la barre, de la saisie et des segments (chaque
-- élément trouvé par son titre, son infobulle ou son image, son action éprouvée par un clic simulé,
-- S.cliquer), les briques (Fenetre.bouton carré ou à icône, Fenetre.calque, Vues.boutonBleu,
-- Vues.inactif, les aplats), le Mode (radios tirés de l'état, D3, D12), la liste en cases (périodes,
-- sous-titres, choix, pagination, recherche, carnet), la légende de la photo active
-- (Lightroom.legende) et l'apparence (couleurs et images reprises à l'ouverture). Puis le fil (lot
-- B4) : les polices mesurées (Metriques), le texte riche (largeur, coupe, balises fermées), l'auteur
-- et l'heure de chaque tour (sur des copies), la ligne d'un appel et « Pourquoi ? », la ligne
-- d'actions (« ☆ Voir la note », « Leçon de la photo »), leurs clics, la bascule vers Leçon, le
-- bandeau sur deux lignes et le tableau du carnet à 518 points ; essais-lecon.lua éprouve la carte
-- de l'onglet Leçon. Les cartes (lot B5) ont leurs propres essais. Ni Claude, ni quota, ni vraie
-- photo : les actions qui écriraient ou parleraient à Claude sont remplacées par des témoins le
-- temps d'un essai.
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

essai('Cadre : une fenêtre de 1 280 × 800, son contenu de 1 278 × 766 (D7) ; les colonnes et les images concordent', function()
    local largeur, haut = S.contenuPourFenetre(1280, 800)
    egal(1280, D.largeurFenetre)
    egal(800, D.hauteurFenetre)
    egal(largeur, D.largeurContenu, 'contenu : largeur (D7)')
    egal(haut, D.hauteurContenu, 'contenu : hauteur (D7 : barre de 33, marge de 1 en bas, aucune en haut)')
    egal(D.largeurContenu, D.volet + D.filet + D.centre + D.filet + D.droite, 'volet, filet, centre, filet, colonne droite')
    egal(163, D.liste, 'volet : 163 utiles')
    egal(590, D.fil, 'centre : 590 utiles')
    egal(D.panneau, D.droite - 2 * D.margeDroite, 'colonne droite : le panneau entre ses marges')
    egal(405, D.interieur)
    -- Le centre : en-tête et son filet, fil, barre, saisie, exactement ; le point de plus de D7 va à
    -- la marge du bas du fil (17 au lieu de 16).
    egal(D.hauteurContenu, D.entete + D.filet + D.hauteurFil + D.barre + D.saisie, 'le centre de haut en bas')
    egal(17, D.hauteurFil - D.margeHautFil - D.grille, 'marge du bas du fil')
    egal(23 * 21, D.grille, 'la grille du fil : 23 lignes de 21')
    -- Les images de Dispositions.IMAGES concordent avec les tailles.
    local I = Dispositions.IMAGES
    egal(D.liste, I.selection.largeur, 'fond de sélection : la largeur du volet')
    egal(D.hauteurCase, I.selection.hauteur, 'fond de sélection : une case')
    egal(D.panneau, I.panneau.largeur, 'panneau')
    vrai(D.margeHautDroite + I.panneau.hauteur <= D.hauteurContenu, 'le panneau tient dans la colonne')
    for _, nom in ipairs({ 'carte-note', 'carte-proposition', 'carte-etape', 'carte-lecon' }) do
        egal(D.interieur, I[nom].largeur, nom)
    end
    egal(D.envoyer, I['bouton-bleu'].largeur, 'Envoyer : le bouton bleu')
    vrai(D.segments <= D.panneau and D.margeSegments >= 0, 'les segments tiennent dans le panneau')
    egal(D.hauteurSegments, I['seg-apercu'].hauteur)
    egal(35, D.hauteurSegments + D.margeHautPanneau, 'contenu du panneau à 35 du haut des segments (12 + 1 + 22)')
    egal(D.interieur, D.panneau - D.margeGauchePanneau - 15, 'contenu du panneau : 15 de chaque côté')
    -- L'aperçu : 330 × 220, sa vignette en 2x ; la rangée sous lui tient dans le panneau.
    egal(330, D.apercu)
    egal(220, D.apercuHauteur)
    egal(D.interieur, 2 * D.fleche + 4 + D.legende + 4 + 8 + D.agrandir, '◀ légende ▶ · Agrandir')
    -- Le volet : son haut, ses cases et son bas dans sa hauteur.
    vrai(D.cases * D.hauteurCase <= D.hauteurListe, 'les cases dans la place de la liste')
    egal(D.hauteurContenu, 2 * D.margeVolet + D.hautVolet + D.hauteurListe + D.basVolet, 'le volet de haut en bas')
    -- Le cadre enregistré change de nom : Lightroom ne rapetisse pas un cadre enregistré.
    egal(2, Fenetre.FORME)
    egal('DeveloppeurClaude-conversation-grande-2', Fenetre.cadre())
    egal(2, Dispositions.cadreBouton(0), 'cadre d\'un carré : bezel + 2 (D5)')
    egal(S.MARGE_BEZEL, Dispositions.TAILLES.margeBezel)
end)

essai('Cadre : la fenêtre construite fait 1 278 de large, chaque colonne au plus 766 de haut (estimation), sur ses aplats', function()
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
        end
        egal(D.largeurContenu, total, 'contenu de 1 278 de large')
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
        -- Le filet du volet, celui de la colonne droite, sous l'en-tête, au-dessus de la barre,
        -- au-dessus de la saisie, et dans le volet sous Renommer… et Supprimer….
        egal(6, filets, 'filets de 1 point')
        -- Le premier aplat de chaque colonne est à sa taille : volet 183, centre 630, droite 463, sur 766.
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
    egal('push_button', poussoir.genre, 'sans `carre` : un push_button (les cartes, jusqu\'au lot B5)')
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
        -- Cette place (178 points) tient deux lignes de petit texte (lot B4, essai du bandeau plus
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

essai('Segments : Aperçu | Proposition | Note | Leçon en images sous calques ; un clic choisit l\'onglet, son crochet suit, sans envoyer la demande', function()
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
        egal('apercu proposition notation lecon', table.concat(recus, ' '), 'un vrai clic : le crochet de chaque onglet')
        -- La rangée ◀ légende ▶ · ⤢ Agrandir est commune aux quatre onglets.
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
    for i = 1, 14 do
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
        -- Pages : 14 conversations, l'entrée du carnet et l'en-tête ne tiennent pas en 12 cases.
        egal('plus', p.lg12)
        egal('Plus anciennes…', p.lt12)
        S.cliquer(calqueCase(contenu, 12))
        egal(2, Fenetre.pageListe)
        egal('plus', p.lg1)
        egal('Plus récentes…', p.lt1)
        egal(avant, #ouvertes, 'changer de page n\'ouvre rien')
        -- La recherche ramène à la première page (ici, encore deux pages de résultats), et filtre.
        local recherche = liee(contenu, 'edit_field', 'recherche')
        S.taper(recherche, 'Conversation')
        egal(1, Fenetre.pageListe, 'la recherche ramène à la première page')
        egal('plus', p.lg12, 'deux pages de résultats')
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
        S.cliquer(calqueCase(contenu, 12))
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
            .. S.q(S.plugin .. '/images/vide-330x220.png') .. ' --out ' .. S.q(dossier .. '/active.jpg') .. ' >/dev/null 2>&1')
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
        gras12 = { '<system/bold>', 12 }, titre = { '<system/bold>', 16 }, mono = { 'Menlo', 11 },
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

essai("Fil dans la fenêtre : une ligne de 21 (auteur 60, écart 12, texte 518) ; auteur et heure aux bonnes lignes ; « Pourquoi ? » et les actions aux seules bonnes lignes ; aucun refus de texte riche", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local c = conversationMaquette()
    Moteur.courante = c
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        egal(518, Fenetre.largeurTexte(), 'D.fil − 60 − 12')
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
        vrai(#morceaux >= 2, 'plus d\'une ligne : ' .. #morceaux)
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
    -- Les messages de la fenêtre (mesurés par Metriques, en petit).
    local messages = { Fenetre.CLAUDE_TRAVAILLE, Fenetre.CHOISIR_CONVERSATION, Fenetre.NOTE_AUTRE_PHOTO, Fenetre.PAS_D_IMAGE,
        Fenetre.EXERCICE_CONTINUE .. Fenetre.LIBELLES_MODE.proposer .. '.', Fenetre.EXERCICE_CONTINUE .. Fenetre.LIBELLES_MODE.appliquer .. '.',
        "Écrivez une demande avant d'envoyer." }
    for _, m in ipairs(messages) do
        local montre = Fenetre.texteBandeau(m, D.bandeau)
        egal(m, (montre:gsub('\n', ' ')), 'en entier : ' .. m)
        local lignes = select(2, montre:gsub('\n', '')) + 1
        vrai(lignes <= 2, m .. ' : ' .. lignes .. ' lignes')
        for ligne in (montre .. '\n'):gmatch('([^\n]*)\n') do
            vrai(Fil.largeur(ligne, 'petit') <= place, string.format('%s : %.0f pour %d', ligne, Fil.largeur(ligne, 'petit'), place))
        end
    end
    -- Plus long (un refus du moteur, une aide) : deux lignes, la seconde finie par « … ».
    local long = "Aucune photo active : choisissez dans Lightroom la photo à retoucher vous-même, puis cliquez « Je le fais »."
    local montre = Fenetre.texteBandeau(long, D.bandeau)
    egal(1, select(2, montre:gsub('\n', '')), 'deux lignes')
    egal('…', montre:sub(-#'…'))
    egal('', Fenetre.texteBandeau('', D.bandeau))
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

essai('Carnet : le tableau, en Menlo, aligné et dans 518 points ; la page dépasse la grille, elle se lit par ▲ ▼', function()
    -- Six mois (dont un changement d'année, les mois avec leur année) et des libellés de 40 caractères :
    -- la colonne Défaut se resserre, le tableau reste aligné et tient dans le fil.
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
    local lignes = Fil.lignesCarnet(page, D.texteFil, Fenetre.TITRE_CARNET)
    local tableau = {}
    for _, l in ipairs(lignes) do
        if l.genre == 'outil' then
            tableau[#tableau + 1] = l
        end
    end
    egal(5, #tableau)
    for _, l in ipairs(tableau) do
        egal(Texte.longueur(tableau[1].texte), Texte.longueur(l.texte), 'aligné : ' .. l.texte)
        vrai(Fil.occupe(l) <= D.texteFil - Fil.MARGE, string.format('dans le fil : %.0f', Fil.occupe(l)))
        contient(l.texte, '  ', 'colonnes séparées')
    end
    contient(tableau[1].texte, 'oct. 2025')
    contient(tableau[1].texte, 'mars 2026')
    vrai(tableau[2].texte:find('…', 1, true), 'libellé resserré : ' .. tableau[2].texte)
    -- Sans resserrement possible de plus : au moins LIBELLE_CARNET_MIN caractères pour le libellé.
    local _, coupe = tableau[2].texte:find('…', 1, true)
    vrai(Texte.longueur(tableau[2].texte:sub(1, coupe)) >= Fil.LIBELLE_CARNET_MIN, 'libellé lisible')
end)
-- Fin -------------------------------------------------------------------------------------------------

Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
