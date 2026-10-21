-- Dispositions.lua : la fenêtre Claude, assemblée des pièces de Vues.lua, et ses dimensions. Une
-- seule disposition, la « Conversation claire », à l'allure de la fenêtre B (1.3, maquette
-- « B · Conversation claire ») : trois colonnes sur des aplats, le volet des conversations à
-- gauche, au centre l'en-tête, le fil, sa barre et la zone de saisie, à droite les segments
-- Aperçu | Proposition | Note | Leçon sur le panneau, l'aperçu commun et la carte de l'onglet.
-- L'Atelier, le Panneau et le choix de la disposition sont retirés, comme le choix de la taille
-- (demandés par Dany le 20 octobre 2026). Son cadre enregistré (Fenetre.cadre) : Lightroom rend sa
-- taille enregistrée à une fenêtre rouverte, sans la rapetisser (constaté).
--
-- Dimensions (D, Dispositions.dimensions), lues aussi par Fenetre.lua : la fenêtre entière, de
-- 1 497 × 1 200 (demandé par Dany le 21 octobre 2026, pour son écran de 3 440 × 1 440 ; la maquette
-- est à 1 280 × 800), et son contenu de 1 495 × 1 166 (D7, constaté le 21 octobre 2026 : barre de
-- titre de 33, marge de 1 à gauche, à droite et en bas, aucune en haut) ; les colonnes (volet de
-- 270 et son filet, centre de 760, filet et colonne droite de 463) ; `lignes` et `hauteurLigne` (la
-- grille du fil : autant de lignes que sa hauteur en tient), `fil` (sa largeur utile), `auteur`,
-- `ecartAuteur` et `texteFil` (la colonne auteur, son écart et le texte d'une ligne du fil), `cases`
-- et `hauteurCase` (la grille de la liste des conversations : autant de cases que sa place en
-- tient), `apercu` et `apercuHauteur` (le cadre 3:2 de l'aperçu, et son
-- image « aucun aperçu », scripts/images-vides.swift), `onglets` (les segments, dans leur ordre),
-- `ongletParDefaut` (Note, montré à l'ouverture), `ongletProposition` et `ongletNotation` (onglet
-- montré quand une proposition ou une note arrive), `ongletEtape` (l'onglet Aperçu, l'ancien
-- Pourquoi ? : ouvert par un clic sur une étape du fil, jamais par une bascule automatique),
-- `ongletLecon`, `propLignes`, `etapeLignes`, `leconLignes` et `criteres` (lignes des cartes) ;
-- les autres sont des largeurs et des hauteurs de pièces, tirées des précédentes.
--
-- Ses images (Dispositions.IMAGES) et ses deux apparences, claire et sombre
-- (Dispositions.APPARENCES, Dispositions.PALETTES), avec Dispositions.image et
-- Dispositions.couleurs : la fenêtre les reprend à chaque ouverture (Fenetre.preparerApparence).

local Vues = require 'Vues'

local Dispositions = {}

-- Le nom de la disposition, gardé dans celui du cadre enregistré (Fenetre.cadre).
Dispositions.NOM = 'conversation'

-- Les tailles de base, en points, d'après la maquette (box-sizing compris) ; le lot 18 recale sur
-- la vraie fenêtre celles dites « à recaler ».
Dispositions.TAILLES = {
    -- La fenêtre entière (demandée par Dany le 21 octobre 2026 : plus grande que la maquette de
    -- 1 280 × 800, elle laisse environ 1 940 points à Lightroom sur son écran de 3 440 × 1 440) et
    -- son cadre (constaté le 21 octobre 2026, D7 : barre de titre de 33, 32 blancs et un filet ;
    -- 1 point de marge à gauche, à droite et en bas, aucun en haut).
    largeurFenetre = 1497, hauteurFenetre = 1200, barreTitre = 33, margeDialogue = 1,
    -- Les colonnes, sans leurs filets de 1 (270 + 1 + 760 + 1 + 463 = 1 495 : demandées par Dany, la
    -- colonne droite de la maquette), et leurs marges : 10 dans le volet, 20 à gauche et à droite du
    -- centre, 14 sur les côtés, 10 en haut et en bas de la colonne droite.
    volet = 270, centre = 760, droite = 463, filet = 1,
    margeVolet = 10, margeCentre = 20, margeDroite = 14, margeHautDroite = 10, margeBasDroite = 10,
    -- Le centre, de haut en bas (à recaler) : l'en-tête (12 + 22 + 6 + 18 + 10, son filet en plus), la
    -- barre ▲ ▼ Fin (son filet compris) et la zone de saisie (son filet compris : 1 + 12 + 26 + 8 + 52
    -- + 8 + 26 + 14, chaque rangée de boutons à la hauteur de leur cadre, D5) ; le fil prend le reste.
    entete = 68, barre = 30, saisie = 147,
    -- Le fil (à recaler) : des lignes de 21 points, sous une marge de 20 et au-dessus d'une marge
    -- d'au moins 16 ; leur nombre (D.lignes, 42) est celui que la hauteur du fil tient, le reste va à
    -- la marge du bas, où il ne gêne rien.
    -- Chaque ligne : la colonne auteur (« Vous », « Claude », l'heure) de 60, un écart de 12, puis
    -- le texte (maquette) ; « Pourquoi ? » à droite d'une étape, un carré small de 80 (constaté le
    -- 21 octobre 2026, D6 : bezel de 15 dans une case de 21), comme les boutons d'actions (« ☆ Voir
    -- la note », « Leçon de la photo »), aux largeurs de leurs titres en petit.
    hauteurLigne = 21, margeHautFil = 20, margeBasFil = 16,
    auteur = 60, ecartAuteur = 12, pourquoi = 80, voirNote = 96, voirLecon = 116, ecartActions = 8,
    -- La liste des conversations (à recaler) : des cases de 40 points, autant que sa place en tient
    -- (D.cases, 22).
    hauteurCase = 40,
    -- L'aperçu commun aux quatre onglets : un cadre 3:2 de 405 × 270, à la largeur de l'intérieur du
    -- panneau (demandé par Dany le 21 octobre 2026), sa vignette en 2x (810 × 540 pixels,
    -- Images.vignette).
    apercu = 405, apercuHauteur = 270, echelleApercu = 2,
    -- Le panneau de la colonne droite (435), son intérieur (405) et celui des cartes (379).
    panneau = 435, interieur = 405, carte = 379,
    -- Les lignes des cartes, en 12 points (provisoires jusqu'au lot 18) : sur chaque image de carte
    -- (Dispositions.IMAGES), le plus grand nombre de lignes qui laisse au moins 12 sous le contenu,
    -- comme la marge du haut (essais-fenetre-b.lua) : la grille des critères de la carte Note
    -- (`criteres` + 1 lignes de 16 sur carte-note de 621 : 12 + 35 × 16 + 6 + filet + 6 + le
    -- plafond, et le bas de la carte), le texte de la proposition (sur carte-proposition de 701 :
    -- 12 + titre + 6 + 40 lignes + 6 + l'état et ▲ ▼ + 6 + boutons), de l'étape (onglet Aperçu, sur
    -- carte-etape de 701 : 12 + titre + 6 + sous-titre + 6 + 40 lignes + 6 + boutons) et de la leçon
    -- (sur carte-lecon de 701 : 12 + titre + 6 + 41 lignes + 6 + boutons).
    criteres = 34, propLignes = 40, etapeLignes = 40, leconLignes = 41,
    -- Le cadre d'un square_button dépasse son bezel visible de 2 points (constaté le 21 octobre 2026,
    -- D5 : height = bezel + 2 ; Fenetre.bouton, clé `bezel`).
    margeBezel = 2,
}

-- Les images de la fenêtre B (images/<nom>.png), seule source de leurs tailles, en points :
-- { largeur = …, hauteur = … }, une table neuve par image. Chacune est un seul PNG en 2x (2 × la
-- taille en points, 144 ppp), icônes d'image_name comprises, sans paire 1x et @2x : Lightroom
-- l'affiche à sa taille en points (constaté le 21 octobre 2026 avec plus.png et trombone.png du
-- module d'essai). Un f:picture reçoit toujours width et height : sans eux, il prendrait la taille
-- en pixels (relevé dans le code de Lightroom, AgPictureView, sans avoir été vu). Tailles de la
-- maquette « B · Conversation claire » ; les hauteurs du panneau et des
-- cartes sont recalées au lot 18. Aucune image pour les fonds ni pour les filets : ce sont des
-- aplats (f:picture sans value, à background_color). Chaque image existe en deux jeux, un par
-- apparence (Dispositions.APPARENCES : images/ en claire, images/sombre/ en sombre), aux mêmes
-- tailles ; Dispositions.image donne le chemin du bon jeu. Après un changement des tailles ou des
-- palettes : luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin
-- (Tests/Lua/Fenetre/essais-images.lua vérifie chaque fichier des deux jeux). L'image « aucun
-- aperçu » n'en est pas : elle a son cadre (Dispositions.imageVide) et son script.
local function taille(largeur, hauteur)
    return { largeur = largeur, hauteur = hauteur }
end

-- La hauteur du contenu de la fenêtre (D7 : sans la barre de titre ni la marge du bas).
local function hauteurContenu(T)
    return T.hauteurFenetre - T.barreTitre - T.margeDialogue
end

local T = Dispositions.TAILLES

Dispositions.IMAGES = {
    -- Le panneau de la colonne droite, à cheval sur les segments : une bande transparente de 12 en
    -- haut, puis le panneau blanc (bord #C9C9C9, coins de 7), sur toute la hauteur de la colonne
    -- entre ses marges du haut et du bas (1 146, dont 1 134 de panneau, pour un contenu de 1 166).
    panneau = taille(T.panneau, hauteurContenu(T) - T.margeHautDroite - T.margeBasDroite),
    -- Les fonds des cartes (#FAFAFA, bord #D9D9D9, coins de 6), à la largeur intérieure du panneau :
    -- Note (critères, filet et plafond), Proposition, Aperçu (étape) et Leçon. Sous l'aperçu de
    -- 405 × 270, la place des cartes fait 782 (D.placeCartes) : chaque carte a 351 de plus qu'à
    -- 1 280 × 800 (270 et 350, place de 431), l'onglet Note la remplit (781), les autres laissent
    -- 81 sous leur carte, comme avant.
    ['carte-note'] = taille(T.interieur, 621),
    ['carte-proposition'] = taille(T.interieur, 701),
    ['carte-etape'] = taille(T.interieur, 701),
    ['carte-lecon'] = taille(T.interieur, 701),
    -- Les onglets Aperçu | Proposition | Note | Leçon, libellés dessinés, et le segment choisi en bleu.
    ['seg-apercu'] = taille(72, 22),
    ['seg-apercu-actif'] = taille(72, 22),
    ['seg-proposition'] = taille(98, 22),
    ['seg-proposition-actif'] = taille(98, 22),
    ['seg-note'] = taille(57, 22),
    ['seg-note-actif'] = taille(57, 22),
    ['seg-lecon'] = taille(65, 22),
    ['seg-lecon-actif'] = taille(65, 22),
    -- Le fond de la conversation choisie dans la liste (et de l'entrée Carnet de progrès montrée) :
    -- une case, à la largeur utile du volet.
    selection = taille(T.volet - 2 * T.margeVolet, T.hauteurCase),
    -- Les voyants Claude Code, Lightroom et Écran (plus de pastille bleue : le voyant Mode est retiré).
    ['pastille-vert'] = taille(8, 8),
    ['pastille-orange'] = taille(8, 8),
    ['pastille-rouge'] = taille(8, 8),
    ['pastille-gris'] = taille(8, 8),
    -- « Accepter N ★ » (Note) et « Accepter » (Proposition), et Envoyer : normal, enfoncé et
    -- inactif ; Lightroom pose le titre blanc par-dessus (Vues.boutonBleu).
    ['bouton-bleu'] = taille(120, 26),
    ['bouton-bleu-presse'] = taille(120, 26),
    ['bouton-bleu-inactif'] = taille(120, 26),
    -- Les étoiles cliquables de « Votre note », puis celles de « Claude propose ».
    ['etoile24-pleine'] = taille(24, 24),
    ['etoile24-vide'] = taille(24, 24),
    ['etoile12-pleine'] = taille(12, 12),
    ['etoile12-vide'] = taille(12, 12),
    -- La rangée des passes, la ligne du plafond et le champ Rechercher.
    ['coche-10'] = taille(10, 10),
    ['chevron-passe'] = taille(7, 8),
    avertissement = taille(14, 14),
    loupe = taille(12, 12),
    -- Icônes de boutons sans titre, par image_name : 📎 et 📋 de la saisie, ▲ ▼ de la barre du fil.
    trombone = taille(14, 14),
    ['presse-papiers'] = taille(14, 14),
    ['chevron-haut'] = taille(12, 12),
    ['chevron-bas'] = taille(12, 12),
}

-- Apparences ------------------------------------------------------------------------------------

-- L'apparence de la fenêtre B, claire (la maquette) ou sombre, se choisit dans le Gestionnaire de
-- modules externes, comme le modèle et l'effort (préférence `apparence` de Chemins.defauts, menu
-- Apparence de PluginInfoProvider.lua ; décision de Dany du 21 octobre 2026), et vaut à
-- l'ouverture suivante de la fenêtre (Fenetre.preparerApparence). Elle ne règle que ce que le
-- module dessine : les aplats (fonds et filets), les couleurs des textes et les images, l'image
-- « aucun aperçu » comprise. Les contrôles natifs (boutons, champs, menus, cases, barre de titre)
-- suivent l'apparence de macOS, quelle que soit celle choisie ici. Quand les deux diffèrent, deux
-- choses restent à constater dans Lightroom (lot 18) : les icônes posées sur un bouton natif
-- (image_name : trombone, presse-papiers, chevron-haut, chevron-bas, à l'encre `texte` de
-- l'apparence choisie, sur un fond de bouton qui suit macOS), et le titre d'une case ou d'un
-- bouton radio posé sur un aplat (couleur du système, sauf si text_color y prend).
--
-- Les apparences, dans l'ordre du menu ; la première est celle par défaut, et toute valeur inconnue
-- y retombe (Dispositions.apparence). `dossier` : où sont ses images, depuis le dossier du module.
Dispositions.APPARENCES = {
    { value = 'claire', title = "Claire", dossier = 'images' },
    { value = 'sombre', title = "Sombre", dossier = 'images/sombre' },
}

-- Les couleurs de chaque apparence, en hexadécimal (RRGGBB), aux mêmes clés : la seule table de
-- chaque palette. Les images (scripts/gabarits.lua puis scripts/images-fenetre.swift et
-- scripts/images-vides.swift) et Fenetre.COULEURS (Dispositions.couleurs, à chaque ouverture) en
-- viennent. La claire est la maquette « B · Conversation claire » (l'orange et le rouge, gardés de
-- la 1.2). La sombre est à juger à l'œil (lot 18, si Dany bascule son Mac en sombre) : chacun de
-- ses textes se lit au moins aussi bien que dans la claire sur les mêmes fonds, et à 4,5:1 au
-- moins là où la claire y est (essais-images.lua) ; les fonds suivent ceux de macOS en sombre, le
-- contenu plus foncé que le reste.
Dispositions.PALETTES = {
    claire = {
        -- Textes : le texte, les gris (secondaire, en-têtes, sous-titre de la conversation
        -- choisie), le bleu (Vous, liens), Menlo (outils), la coche des passes, l'orange
        -- (activité, alertes), le rouge (erreurs), l'ambre (plafond, étoiles pleines), le blanc
        -- (sur le bleu) et le titre d'un bouton bleu inactif (Vues.boutonBleu).
        texte = '1D1D1F', gris = '6B6B6B', grisEntete = '5F5F5F', sousTitreChoisi = '505050', bleu = '0A64D8',
        mono = '3D3D45', coche = '1F7A35', orange = 'E0800D', rouge = 'D12E2E', ambre = 'A86200', blanc = 'FFFFFF',
        titreInactif = 'FFFFFF',
        -- Aplats : le contenu (en-tête, fil, barre), le volet et la zone de saisie, la colonne droite.
        fondContenu = 'FFFFFF', fondVolet = 'F2F2F2', fondDroite = 'ECECEC',
        -- Filets en aplats de 1 pt : bord du volet et dessus de la saisie, bord de la colonne
        -- droite, dessous de l'en-tête, dessus de la barre, dessus du plafond de la carte Note.
        filetVolet = 'D2D2D2', filetDroite = 'C9C9C9', filetEntete = 'E2E2E2', filetBarre = 'EBEBEB',
        filetPlafond = 'E3E3E3',
        -- L'aperçu : son fond (celui des vignettes, Images.FOND, sous la photo et l'image « aucun
        -- aperçu ») et le texte de l'image « aucun aperçu ».
        fondApercu = '2B2B2B', texteApercu = '9E9E9E',
        -- Images : le panneau, les cartes, les segments, la conversation choisie, la pastille
        -- verte, le contour (étoile vide, chevron des passes, pastille grise) et le bouton bleu
        -- (normal, enfoncé, inactif).
        fondPanneau = 'FFFFFF', bordPanneau = 'C9C9C9', fondCarte = 'FAFAFA', bordCarte = 'D9D9D9',
        fondSegment = 'FFFFFF', bordSegment = 'B5B5B5', filetSegment = 'D0D0D0', selection = 'DADADA',
        pastille = '2DA44E', contour = '8A8A8A', bleuBouton = '0A64D8', bordBleu = '0A5BC4', bleuPresse = '084A9E',
        bleuInactif = '9DBDEB', bordBleuInactif = '88AEE2',
    },
    sombre = {
        texte = 'E8E8E8', gris = '9A9A9A', grisEntete = 'A6A6A6', sousTitreChoisi = 'C2C2C2', bleu = '5AA2F6',
        mono = 'C8C8D0', coche = '3FB950', orange = 'E8963A', rouge = 'F27A72', ambre = 'E0A040', blanc = 'FFFFFF',
        -- Sur le bleu inactif sombre (#2B3F5C), le blanc ferait 10:1 et paraîtrait allumé : un gris
        -- bleuté à 3,2:1 le dit éteint (le blanc actif sur #1F6FDB est à 4,8:1).
        titreInactif = '7F8EA3',
        fondContenu = '1E1E1E', fondVolet = '2A2A2A', fondDroite = '323232',
        filetVolet = '454545', filetDroite = '4A4A4A', filetEntete = '343434', filetBarre = '2E2E2E',
        filetPlafond = '3A3A3A',
        -- Le fond de l'aperçu reste le gris des vignettes (Images.FOND, le même dans les deux
        -- apparences : une photo se juge sur ce gris) ; seul le texte de l'image « aucun aperçu »
        -- change.
        fondApercu = '2B2B2B', texteApercu = 'A3A3A3',
        fondPanneau = '1E1E1E', bordPanneau = '4A4A4A', fondCarte = '262626', bordCarte = '404040',
        fondSegment = '3C3C3C', bordSegment = '5A5A5A', filetSegment = '4E4E4E', selection = '3A3A3A',
        pastille = '3FB950', contour = '8E8E8E', bleuBouton = '1F6FDB', bordBleu = '1A62C4', bleuPresse = '17559F',
        bleuInactif = '2B3F5C', bordBleuInactif = '34496A',
    },
}

local function parValeur(valeur)
    for _, a in ipairs(Dispositions.APPARENCES) do
        if a.value == valeur then
            return a
        end
    end
    return nil
end

-- L'apparence à employer pour une valeur de la préférence : elle-même si elle est connue, sinon
-- la première (claire), comme Moteur.modeleEtEffort pour le modèle et l'effort.
function Dispositions.apparence(valeur)
    local a = parValeur(valeur) or Dispositions.APPARENCES[1]
    return a.value
end

-- Éléments du menu Apparence du Gestionnaire de modules externes (tables neuves).
function Dispositions.itemsApparences()
    local r = {}
    for _, a in ipairs(Dispositions.APPARENCES) do
        r[#r + 1] = { title = a.title, value = a.value }
    end
    return r
end

-- Le chemin d'une image de Dispositions.IMAGES dans le jeu de l'apparence, depuis le dossier du
-- module (« images/loupe.png », « images/sombre/loupe.png ») : à passer à Chemins.ressource
-- (Fenetre.image), comme Dispositions.imageVide. Une image inconnue est une erreur.
function Dispositions.image(nom, apparence)
    if not Dispositions.IMAGES[nom] then
        error("image inconnue de Dispositions.IMAGES : " .. tostring(nom), 2)
    end
    return parValeur(Dispositions.apparence(apparence)).dossier .. '/' .. nom .. '.png'
end

-- Le nom de l'image « aucun aperçu », sans extension : celui de son cadre (« vide-405x270 »).
function Dispositions.nomImageVide()
    local T = Dispositions.TAILLES
    return 'vide-' .. T.apercu .. 'x' .. T.apercuHauteur
end

-- Le chemin de l'image « aucun aperçu » dans le jeu de l'apparence, depuis le dossier du module
-- (« images/vide-405x270.png », « images/sombre/vide-405x270.png »), au cadre 3:2 de l'aperçu, en
-- 2x : scripts/images-vides.swift la dessine, du fond et du texte de chaque palette.
function Dispositions.imageVide(apparence)
    return parValeur(Dispositions.apparence(apparence)).dossier .. '/' .. Dispositions.nomImageVide() .. '.png'
end

-- Les couleurs de l'apparence, en triplets { r, g, b } de 0 à 1 (une table neuve, des triplets
-- neufs), pour LrColor(r, g, b) : Fenetre.COULEURS les reprend à chaque ouverture. Aucune couleur
-- n'est créée ici (Dispositions se charge sans SDK, liens.lua et scripts/gabarits.lua compris).
function Dispositions.couleurs(apparence)
    local r = {}
    for cle, hex in pairs(Dispositions.PALETTES[Dispositions.apparence(apparence)]) do
        r[cle] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    end
    return r
end

-- Ce que lisent scripts/images-fenetre.swift et scripts/images-vides.swift (par
-- scripts/gabarits.lua, en JSON) : les tailles des images, puis, pour chaque apparence, le dossier
-- de ses images et sa palette, et le cadre de l'image « aucun aperçu ». Tables neuves.
function Dispositions.gabarits()
    local images, apparences = {}, {}
    for nom, t in pairs(Dispositions.IMAGES) do
        images[nom] = { largeur = t.largeur, hauteur = t.hauteur }
    end
    for _, a in ipairs(Dispositions.APPARENCES) do
        local couleurs = {}
        for cle, hex in pairs(Dispositions.PALETTES[a.value]) do
            couleurs[cle] = hex
        end
        apparences[a.value] = { dossier = a.dossier, couleurs = couleurs }
    end
    local T = Dispositions.TAILLES
    return { images = images, apparences = apparences,
        vide = { nom = Dispositions.nomImageVide(), largeur = T.apercu, hauteur = T.apercuHauteur } }
end

-- Dimensions ------------------------------------------------------------------------------------

-- Le cadre d'un square_button dont le bezel visible fait `bezel` points (D5).
function Dispositions.cadreBouton(bezel)
    return bezel + Dispositions.TAILLES.margeBezel
end

-- Les dimensions : une table neuve, avec `nom`, et les tailles tirées des précédentes.
function Dispositions.dimensions()
    local D = { nom = Dispositions.NOM }
    for cle, valeur in pairs(Dispositions.TAILLES) do
        D[cle] = valeur
    end
    local cadre = Dispositions.cadreBouton
    -- Le contenu de la fenêtre (D7) : 1 495 × 1 166 pour 1 497 × 1 200.
    D.largeurContenu = D.largeurFenetre - 2 * D.margeDialogue
    D.hauteurContenu = hauteurContenu(D)
    -- Volet : 250 utiles. En haut, Nouvelle conversation (bezel 26), 8, Rechercher (24), 14 ; en bas,
    -- Renommer… et Supprimer… (bezel 22), 6, le filet entre deux marges de 6, 6, Publication… et
    -- Consommation… (bezel 22, 6 entre eux), 4, les deux versions (14 chacune), 6, le voyant Écran
    -- (16). Les cases de la liste remplissent le milieu : autant que sa place en tient (22 de 40
    -- dans 915), la place restante sous elles.
    D.liste = D.volet - 2 * D.margeVolet
    D.loupe = Dispositions.IMAGES.loupe.largeur
    D.recherche = D.liste - D.loupe - 8
    D.renommer = math.floor((D.liste - 6) / 2)
    D.ligneVersion = 14
    D.ecran = 16
    D.hautVolet = cadre(26) + 8 + 24 + 14
    D.basVolet = cadre(22) + 6 + (6 + D.filet + 6) + 6 + cadre(22) + 6 + cadre(22) + 4 + 2 * D.ligneVersion + 6 + D.ecran
    D.hauteurListe = D.hauteurContenu - 2 * D.margeVolet - D.hautVolet - D.basVolet
    D.cases = math.floor(D.hauteurListe / D.hauteurCase)
    -- Centre : 720 utiles. L'en-tête : le titre (gras 16) et le Mode, puis les voyants Claude Code et
    -- Lightroom et la photo active, alignée à droite sur la marge (la rangée fait les 720 : un texte
    -- de taille fixe ne s'étire pas) ; le fil ; la barre, dont l'activité (ou le forfait) finit de
    -- même sur la marge de droite, comme dans la maquette ; la saisie (Style, bandeau, Envoyer). Le
    -- titre prend ce que le Mode laisse (D.placeMode, sa place à 1 280 × 800 : 590 − 270).
    D.fil = D.centre - 2 * D.margeCentre
    D.placeMode = 320
    D.titre = D.fil - D.placeMode
    D.voyantClaude = 125
    D.voyantLightroom = 150
    D.info = D.fil - (8 + 6 + D.voyantClaude) - 14 - (8 + 6 + D.voyantLightroom)
    -- Le fil : autant de lignes que sa hauteur en tient entre ses marges (42 dans 920), le reste à
    -- la marge du bas.
    D.hauteurFil = D.hauteurContenu - (D.entete + D.filet) - D.barre - D.saisie
    D.lignes = math.floor((D.hauteurFil - D.margeHautFil - D.margeBasFil) / D.hauteurLigne)
    D.grille = D.lignes * D.hauteurLigne
    -- Le texte d'une ligne du fil (648 : Fenetre.largeurTexte), après la colonne auteur et son écart.
    D.texteFil = D.fil - D.auteur - D.ecartAuteur
    -- ▲ ▼ de la barre et ◀ ▶ de l'aperçu (bezel de 22), puis Fin.
    D.fleche = 26
    D.fin = 36
    D.position = 150
    D.activite = D.fil - (2 * D.fleche + 4 + 4 + D.fin + 8 + D.position)
    D.champ = D.fil
    D.joindre = 28
    D.style = 170
    D.etiquetteStyle = 30
    D.envoyer = Dispositions.IMAGES['bouton-bleu'].largeur
    D.bandeau = D.fil - (D.joindre + 4 + D.joindre + 10 + D.etiquetteStyle + 6 + D.style + 8 + 8 + D.envoyer)
    -- Colonne droite : le panneau de 435, à 14 du bord ; les segments centrés en tête, à cheval sur
    -- son bord (bande transparente de 12) ; son contenu de 405 sous une marge de 13 (12 + 1 + 22 =
    -- 35 depuis le haut des segments, comme la maquette) et à 15 du bord (14 + 1).
    D.segments = 0
    D.onglets = {
        { valeur = 'apercu', titre = "Aperçu", image = 'seg-apercu' },
        { valeur = 'proposition', titre = "Proposition", image = 'seg-proposition' },
        { valeur = 'notation', titre = "Note", image = 'seg-note' },
        { valeur = 'lecon', titre = "Leçon", image = 'seg-lecon' },
    }
    for _, onglet in ipairs(D.onglets) do
        D.segments = D.segments + Dispositions.IMAGES[onglet.image].largeur
    end
    D.hauteurSegments = Dispositions.IMAGES['seg-note'].hauteur
    D.margeSegments = math.floor((D.panneau - D.segments) / 2)
    D.margeHautPanneau = 12 + 1 + 22 - D.hauteurSegments
    D.margeGauchePanneau = D.panneau - D.interieur - 15
    -- Note par défaut, donc montrée à l'ouverture ; une proposition qui arrive montre Proposition,
    -- une note Note ; Aperçu (l'ancien Pourquoi ?) s'ouvre sur un clic, jamais tout seul.
    D.ongletParDefaut, D.ongletProposition, D.ongletNotation, D.ongletEtape, D.ongletLecon =
        'notation', 'proposition', 'notation', 'apercu', 'lecon'
    -- L'aperçu, sa vignette en pixels, et la rangée ◀ légende ▶ · ⤢ Agrandir sous lui.
    D.pixelsApercu = D.apercu * D.echelleApercu
    D.pixelsApercuHauteur = D.apercuHauteur * D.echelleApercu
    D.agrandir = 90
    D.legende = D.interieur - 2 * D.fleche - 2 * 4 - 8 - D.agrandir
    -- La place des cartes sous l'aperçu et sa rangée, jusqu'au bas du contenu du panneau (son bord
    -- de 1 et sa marge de 14) : 782 points. Chaque carte y tient (essais-fenetre-b.lua).
    D.placeCartes = Dispositions.IMAGES.panneau.hauteur - 1 - 14
        - (D.hauteurSegments + D.margeHautPanneau + D.apercuHauteur + 8 + cadre(22) + 12)
    -- Les cartes sur leurs images (Vues.lecon, Vues.proposition, Vues.etape, la grille des critères
    -- de Vues.notation) : leur texte à l'intérieur de la carte (379), à 13 du bord (12 de marge et
    -- le bord de 1), coupé en pages à cette largeur (Fenetre.montrerPage) ; « Détail… » en carré.
    D.largeurNote = D.carte
    D.largeurProposition = D.carte
    D.largeurEtape = D.carte
    D.largeurLecon = D.carte
    D.margeCarte = math.floor((D.interieur - D.carte) / 2)
    D.detail = 70
    -- La carte Note (Vues.notation, maquette « B · Conversation claire », onglet Note) : la grille
    -- des étiquettes (« Passes : », « Votre note : », « Drapeau : », alignées à droite en 12 :
    -- « Votre note : » mesure 66,6, et 2 de jeu) et de leurs valeurs, 8 entre ses rangées ; les cinq
    -- étoiles de « Votre note » (calques de 30, 2 entre eux) et la note posée à leur droite ;
    -- Retenir, Rejeter et « ? À vérifier » (bezel de 24) ; « Claude propose », puis la carte des
    -- critères (une ligne de 16 par ligne de la grille : l'étiquette d'un critère en gras 12,
    -- « Plancher technique » mesure 116,7, et 2 de jeu, puis son texte), le filet et la ligne du
    -- plafond avec « Voir à 100 % » ; la rangée du bas (▲ ▼, Laisser, Changer…, Accepter en bleu :
    -- bezel de 26). La rangée des passes (Vues.passes, largeurs mesurées) prend juste la place que
    -- laisse la colonne des étiquettes (327 points).
    D.etiquetteNote = 70
    D.ecartEtiquette = 8
    D.ecartGrille = 8
    D.lignePasses = 16
    D.etoile = 30
    D.ecartEtoiles = 2
    D.posee = D.interieur - D.etiquetteNote - D.ecartEtiquette - (5 * D.etoile + 4 * D.ecartEtoiles) - 12
    D.retenir, D.rejeter, D.aVerifier = 80, 80, 92
    D.ligneClaude = 16
    D.ligneCritere = 16
    D.etiquetteCritere = 120
    D.ecartCritere = 8
    D.texteCritere = D.carte - D.etiquetteCritere - D.ecartCritere
    D.avertissement = Dispositions.IMAGES.avertissement.largeur
    D.zoom = 84
    D.plafond = D.carte - D.avertissement - 8 - 8 - D.zoom
    D.laisser, D.changer = 104, 84
    -- La carte Proposition (Vues.proposition) : Refuser, Ajuster… et Je le fais (ou J'ai fini) en
    -- carrés, Accepter en bleu ; la carte de l'étape (Vues.etape) : ◀ ▶, Voir l'avant (ou l'après)
    -- et Détail… en carrés.
    D.refuser, D.ajuster, D.jeLeFais = 72, 78, 84
    D.bascule = 96
    return D
end

-- Assemblage ------------------------------------------------------------------------------------

-- Une variante superposée, de largeur `largeur`, montrée quand l'onglet vaut `valeur` :
-- `pieces(fm)` rend la table de sa colonne, ses vues créées par la fabrique masquable `fm`, qui
-- pose la condition de l'onglet sur chaque vue simple. La colonne ne porte pas `visible` :
-- Lightroom l'ignore sur un conteneur (constaté, voir Vues.masquable).
local function variante(f, F, largeur, valeur, pieces)
    local contenu = pieces(Vues.masquable(f, F, F.egal('onglet', valeur)))
    contenu.width = largeur
    return f:column(contenu)
end

-- Une colonne de taille fixe sur son aplat (un f:picture à background_color, posé dessous) : le
-- fond de la colonne (background_color est sans effet sur un conteneur, constaté A5).
local function surAplat(f, largeur, hauteur, couleur, contenu)
    return f:column {
        place = 'overlapping',
        width = largeur,
        height = hauteur,
        Vues.aplat(f, largeur, hauteur, couleur),
        contenu,
    }
end

-- Le centre : l'en-tête et son filet, le fil, le filet et la barre, puis la zone de saisie sur son
-- aplat, sous son filet ; le tout sur le blanc du contenu.
local function centre(f, F, D)
    local C = F.COULEURS
    return surAplat(f, D.centre, D.hauteurContenu, C.fondContenu, f:column {
        spacing = 0,
        Vues.entete(f, F, D),
        Vues.aplat(f, D.centre, D.filet, C.filetEntete),
        f:column {
            height = D.hauteurFil,
            margin_left = D.margeCentre,
            margin_top = D.margeHautFil,
            Vues.grille(f, F, D),
        },
        Vues.aplat(f, D.centre, D.filet, C.filetBarre),
        Vues.defilement(f, F, D),
        Vues.aplat(f, D.centre, D.filet, C.filetVolet),
        surAplat(f, D.centre, D.saisie - D.filet, C.fondVolet, Vues.saisie(f, F, D)),
    })
end

-- La colonne droite : sur son aplat, le panneau en image, les segments à cheval sur son bord ;
-- dedans, l'aperçu commun, la rangée ◀ légende ▶ · ⤢ Agrandir, puis les quatre variantes
-- superposées des onglets, chacune sur sa carte en image (lots B4 et B5) : la carte de l'étape dans
-- Aperçu, la proposition, la carte Note (sa grille, puis la carte des critères) et la carte de la
-- leçon dans Leçon.
local function droite(f, F, D)
    local C = F.COULEURS
    local largeur = D.interieur
    return surAplat(f, D.droite, D.hauteurContenu, C.fondDroite, f:column {
        margin_left = D.margeDroite,
        margin_top = D.margeHautDroite,
        f:column {
            place = 'overlapping',
            width = D.panneau,
            height = Dispositions.IMAGES.panneau.hauteur,
            Vues.image(f, F, 'panneau'),
            f:column {
                spacing = 0,
                Vues.segments(f, F, D),
                f:column {
                    spacing = 0,
                    margin_left = D.margeGauchePanneau,
                    margin_top = D.margeHautPanneau,
                    Vues.apercu(f, F, D),
                    f:spacer { height = 8 },
                    Vues.navigationApercu(f, F, D),
                    f:spacer { height = 12 },
                    f:column {
                        place = 'overlapping',
                        variante(f, F, largeur, 'apercu', function(fm) return { Vues.etape(fm, F, largeur, D) } end),
                        variante(f, F, largeur, 'proposition', function(fm) return { Vues.proposition(fm, F, largeur, D) } end),
                        variante(f, F, largeur, 'notation', function(fm) return { Vues.notation(fm, F, largeur, D) } end),
                        variante(f, F, largeur, 'lecon', function(fm) return { Vues.lecon(fm, F, largeur, D) } end),
                    },
                },
            },
        },
    })
end

-- L'arbre de la fenêtre (sa racine liée à F.p) : le volet, son filet, le centre, le filet de la
-- colonne droite, la colonne droite, côte à côte sans écart ni marge (1 495 points).
function Dispositions.construire(f, F, D)
    local C = F.COULEURS
    return f:row {
        bind_to_object = F.p,
        spacing = 0,
        margin = 0,
        surAplat(f, D.volet, D.hauteurContenu, C.fondVolet, Vues.volet(f, F, D)),
        Vues.aplat(f, D.filet, D.hauteurContenu, C.filetVolet),
        centre(f, F, D),
        Vues.aplat(f, D.filet, D.hauteurContenu, C.filetDroite),
        droite(f, F, D),
    }
end

return Dispositions
