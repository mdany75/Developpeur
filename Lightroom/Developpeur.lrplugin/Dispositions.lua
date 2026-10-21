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
-- module d'essai), pourvu que f:picture reçoive width et height (sans eux, il prend la taille en
-- pixels). Tailles de la maquette « B · Conversation claire » ; les hauteurs du panneau et des
-- cartes sont recalées au lot 18. Aucune image pour les fonds ni pour les filets : ce sont des
-- aplats (f:picture sans value, à background_color). Après un changement :
-- luajit scripts/gabarits.lua | swift scripts/images-fenetre.swift Lightroom/Developpeur.lrplugin
-- (Tests/Lua/Fenetre/essais-images.lua vérifie chaque fichier).
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
