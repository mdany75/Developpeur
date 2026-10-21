-- Dispositions.lua : la fenêtre Claude, assemblée des pièces de Vues.lua, et ses dimensions. Une
-- seule disposition, la « Conversation claire » (la plus proche de la 1.0) : les conversations à
-- gauche, le fil au centre, à droite les onglets Note, Proposition et Pourquoi ? (1.3), l'aperçu,
-- puis la carte choisie ; en grande taille. L'Atelier, le Panneau et le choix de la disposition sont
-- retirés, comme le choix de la taille (demandés par Dany le 20 octobre 2026). Son cadre enregistré
-- (Fenetre.cadre) : Lightroom rend sa taille enregistrée à une fenêtre rouverte, sans la rapetisser
-- (constaté).
--
-- Dimensions (D), lues aussi par Fenetre.lua : `lignes` (lignes du fil), `fil` (largeur de la
-- colonne du fil), `liste` (la liste des conversations), `droite` (la colonne de droite), `apercu`
-- (cadre carré de l'aperçu, et son image « aucun aperçu », scripts/images-vides.swift), `onglets`,
-- `ongletProposition` et `ongletNotation` (onglet montré quand une proposition ou une note
-- arrive), `ongletEtape` (l'onglet Pourquoi ?, ouvert par un clic sur une étape du fil, jamais par
-- une bascule automatique), `propLignes` (lignes de la proposition), `etapeLignes` (lignes du texte
-- de la carte Pourquoi ?), `criteres` (lignes des critères de la carte Note) ; les autres sont des
-- largeurs de pièces et des nombres de lignes.
--
-- Pour la fenêtre B (1.3, lots B3 à B5) : ses images (Dispositions.IMAGES) et ses deux apparences,
-- claire et sombre (Dispositions.APPARENCES, Dispositions.PALETTES), avec Dispositions.image et
-- Dispositions.couleurs ; la fenêtre actuelle ne s'en sert pas encore.

local Vues = require 'Vues'

local Dispositions = {}

-- Le nom de la disposition, gardé dans celui du cadre enregistré (Fenetre.cadre).
Dispositions.NOM = 'conversation'

-- `propLignes` passe de 21 à 19 (1.3) : la carte Proposition gagne une seconde rangée (Je le fais),
-- et garde la hauteur de la carte Note. `etapeLignes` (carte Pourquoi ?) : 19, provisoire, à caler
-- sur la capture de la fenêtre (Proposition à 19 lignes plus sa seconde rangée).
Dispositions.TAILLES = { lignes = 42, fil = 900, liste = 250, droite = 340, apercu = 320, propLignes = 19, etapeLignes = 19,
    criteres = 12 }

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
-- (Tests/Lua/Fenetre/essais-images.lua vérifie chaque fichier des deux jeux).
local function taille(largeur, hauteur)
    return { largeur = largeur, hauteur = hauteur }
end

Dispositions.IMAGES = {
    -- Le panneau de la colonne droite, à cheval sur les segments : une bande transparente de 12 en
    -- haut, puis le panneau blanc (bord #C9C9C9, coins de 7), 733 pour un contenu de 765.
    panneau = taille(435, 745),
    -- Les fonds des cartes (#FAFAFA, bord #D9D9D9, coins de 6), à la largeur intérieure du panneau :
    -- Note (critères, filet et plafond), Proposition, Aperçu (étape) et Leçon.
    ['carte-note'] = taille(405, 270),
    ['carte-proposition'] = taille(405, 350),
    ['carte-etape'] = taille(405, 350),
    ['carte-lecon'] = taille(405, 350),
    -- Les onglets Aperçu | Proposition | Note | Leçon, libellés dessinés, et le segment choisi en bleu.
    ['seg-apercu'] = taille(72, 22),
    ['seg-apercu-actif'] = taille(72, 22),
    ['seg-proposition'] = taille(98, 22),
    ['seg-proposition-actif'] = taille(98, 22),
    ['seg-note'] = taille(57, 22),
    ['seg-note-actif'] = taille(57, 22),
    ['seg-lecon'] = taille(65, 22),
    ['seg-lecon-actif'] = taille(65, 22),
    -- Le fond de la conversation choisie dans la liste (et de l'entrée Carnet de progrès montrée).
    selection = taille(163, 40),
    -- Les voyants Claude Code, Lightroom et Écran (plus de pastille bleue : le voyant Mode est retiré).
    ['pastille-vert'] = taille(8, 8),
    ['pastille-orange'] = taille(8, 8),
    ['pastille-rouge'] = taille(8, 8),
    ['pastille-gris'] = taille(8, 8),
    -- « Accepter N ★ » (Note) et « Accepter » (Proposition) : normal, enfoncé et inactif ; Lightroom
    -- pose le titre blanc par-dessus.
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
-- Apparence de PluginInfoProvider.lua ; décision de Dany du 21 octobre 2026). Elle ne règle que ce
-- que le module dessine : les aplats (fonds et filets), les couleurs des textes et les images. Les
-- contrôles natifs (boutons, champs, menus, cases, barre de titre) suivent l'apparence de macOS,
-- quelle que soit celle choisie ici : rien à faire pour eux. Quand les deux diffèrent, deux choses
-- restent à constater dans Lightroom (lots B3 et 18) : les icônes posées sur un bouton natif
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
-- chaque palette. Les images (scripts/gabarits.lua puis scripts/images-fenetre.swift) et, au lot
-- B3, Fenetre.COULEURS (Dispositions.couleurs) en viennent. La claire est la maquette « B ·
-- Conversation claire » (l'orange et le rouge, gardés de la 1.2). La sombre est à juger à l'œil
-- (lot 18, si Dany bascule son Mac en sombre) : chacun de ses textes se lit au moins aussi bien
-- que dans la claire sur les mêmes fonds, et à 4,5:1 au moins là où la claire y est
-- (essais-images.lua) ; les fonds suivent ceux de macOS en sombre, le contenu plus foncé que le
-- reste.
Dispositions.PALETTES = {
    claire = {
        -- Textes : le texte, les gris (secondaire, en-têtes, sous-titre de la conversation
        -- choisie), le bleu (Vous, liens), Menlo (outils), la coche des passes, l'orange
        -- (activité, alertes), le rouge (erreurs), l'ambre (plafond, étoiles pleines) et le blanc
        -- (sur le bleu).
        texte = '1D1D1F', gris = '6B6B6B', grisEntete = '5F5F5F', sousTitreChoisi = '505050', bleu = '0A64D8',
        mono = '3D3D45', coche = '1F7A35', orange = 'E0800D', rouge = 'D12E2E', ambre = 'A86200', blanc = 'FFFFFF',
        -- Aplats : le contenu (en-tête, fil, barre), le volet et la zone de saisie, la colonne droite.
        fondContenu = 'FFFFFF', fondVolet = 'F2F2F2', fondDroite = 'ECECEC',
        -- Filets en aplats de 1 pt : bord du volet et dessus de la saisie, bord de la colonne
        -- droite, dessous de l'en-tête, dessus de la barre, dessus du plafond de la carte Note.
        filetVolet = 'D2D2D2', filetDroite = 'C9C9C9', filetEntete = 'E2E2E2', filetBarre = 'EBEBEB',
        filetPlafond = 'E3E3E3',
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
        fondContenu = '1E1E1E', fondVolet = '2A2A2A', fondDroite = '323232',
        filetVolet = '454545', filetDroite = '4A4A4A', filetEntete = '343434', filetBarre = '2E2E2E',
        filetPlafond = '3A3A3A',
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
-- module (« images/loupe.png », « images/sombre/loupe.png ») : à passer à Chemins.ressource, comme
-- Dispositions.imageVide. Une image inconnue est une erreur.
function Dispositions.image(nom, apparence)
    if not Dispositions.IMAGES[nom] then
        error("image inconnue de Dispositions.IMAGES : " .. tostring(nom), 2)
    end
    return parValeur(Dispositions.apparence(apparence)).dossier .. '/' .. nom .. '.png'
end

-- Les couleurs de l'apparence, en triplets { r, g, b } de 0 à 1 (une table neuve, des triplets
-- neufs), pour LrColor(r, g, b) : Fenetre.COULEURS les reprendra au lot B3. Aucune couleur n'est
-- créée ici (Dispositions se charge sans SDK, liens.lua et scripts/gabarits.lua compris).
function Dispositions.couleurs(apparence)
    local r = {}
    for cle, hex in pairs(Dispositions.PALETTES[Dispositions.apparence(apparence)]) do
        r[cle] = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
    end
    return r
end

-- Ce que lit scripts/images-fenetre.swift (par scripts/gabarits.lua, en JSON) : les tailles des
-- images, puis, pour chaque apparence, le dossier de ses images et sa palette. Tables neuves.
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
    return { images = images, apparences = apparences }
end

-- Les dimensions : une table neuve, avec `nom`, et les largeurs tirées des précédentes.
function Dispositions.dimensions()
    local D = { nom = Dispositions.NOM }
    for cle, valeur in pairs(Dispositions.TAILLES) do
        D[cle] = valeur
    end
    -- L'aperçu est toujours montré ; dessous, la carte Note, la proposition ou la carte Pourquoi ?
    -- (demandé par Dany le 20 octobre 2026 : l'aperçu et la note ensemble). Note reste le premier
    -- onglet, donc celui montré à l'ouverture ; Pourquoi ? vient en dernier (1.3).
    D.onglets = {
        { valeur = 'notation', titre = "Note" },
        { valeur = 'proposition', titre = "Proposition" },
        { valeur = 'etape', titre = "Pourquoi ?" },
    }
    D.ongletProposition, D.ongletNotation, D.ongletEtape = 'proposition', 'notation', 'etape'
    D.titre = D.fil - 280
    D.info = 210
    D.voyant = 150
    D.position = 150
    D.activite = 300
    D.style = 180
    D.bandeau = D.fil
    D.envoyer = 110
    D.champ = D.fil - 170
    D.legende = D.apercu - 80
    -- Largeur du texte de la carte Note, de la proposition et de la carte Pourquoi ? (Vues.notation,
    -- Vues.proposition, Vues.etape), pour les couper en pages (Fenetre.montrerPage).
    D.largeurNote = D.droite - 24
    D.largeurProposition = D.droite - 24
    D.largeurEtape = D.droite - 24
    -- La liste des conversations finit au niveau du champ de demande : la grille, plus ce qui la
    -- suit au centre (▲ ▼, séparateur, invites et Style, bandeau, demande). Le nombre de lignes du
    -- fil donne au centre la hauteur de la colonne de droite (aperçu, carte Note).
    D.hauteurListe = D.lignes * 17 + 85
    return D
end

-- Le nom de l'image « aucun aperçu » du cadre : vide-320.png.
function Dispositions.imageVide(D)
    return 'vide-' .. D.apercu .. '.png'
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

-- L'arbre de la fenêtre (sa racine liée à F.p).
function Dispositions.construire(f, F, D)
    local centre = f:column {
        spacing = 6,
        width = D.fil,
        fill_vertical = 1,
        Vues.titre(f, F, D.titre, D.info),
        Vues.voyants(f, F, D.voyant),
        f:separator { fill_horizontal = 1 },
        Vues.grille(f, F, D),
        Vues.defilement(f, F, D),
        -- Ne grandit que si une autre colonne est plus haute. La liste des conversations
        -- (D.hauteurListe) finit au niveau du champ de demande.
        f:spacer { fill_vertical = 1 },
        f:separator { fill_horizontal = 1 },
        Vues.invites(f, F, D),
        Vues.bandeau(f, F, D.bandeau),
        Vues.saisie(f, F, D),
    }
    -- À droite : les onglets Note, Proposition et Pourquoi ? en tête, puis l'aperçu, toujours
    -- montré ; après une ligne vide sous Agrandir, la carte de l'onglet choisi ; en bas, Publication
    -- et Consommation, puis les versions, au niveau du champ de demande (demandé par Dany le
    -- 20 octobre 2026). La carte Pourquoi ? est superposée en dernier (1.3) : sous elle, les boutons
    -- des cartes Note et Proposition doivent répondre (à constater ; sinon, repli sur un tab_view).
    local droite = f:column {
        spacing = 8,
        width = D.droite,
        fill_vertical = 1,
        Vues.onglets(f, F, D.onglets),
        Vues.apercu(f, F, D),
        Vues.navigationApercu(f, F, D.legende),
        Vues.agrandir(f, F),
        f:spacer { height = 8 },
        f:column {
            place = 'overlapping',
            variante(f, F, D.droite, 'notation', function(fm) return { Vues.notation(fm, F, D.droite, D) } end),
            variante(f, F, D.droite, 'proposition', function(fm) return { Vues.proposition(fm, F, D.droite, D.propLignes) } end),
            variante(f, F, D.droite, 'etape', function(fm) return { Vues.etape(fm, F, D.droite, D) } end),
        },
        f:spacer { fill_vertical = 1 },
        Vues.autresFenetres(f, F),
        f:separator { fill_horizontal = 1 },
        Vues.versions(f, F, D.droite),
    }
    return f:row {
        bind_to_object = F.p,
        margin = 12,
        spacing = 12,
        Vues.listeConversations(f, F, D.liste, D.hauteurListe),
        f:separator { fill_vertical = 1 },
        centre,
        f:separator { fill_vertical = 1 },
        droite,
    }
end

return Dispositions
