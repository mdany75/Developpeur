-- Dispositions.lua : la fenêtre Claude, assemblée des pièces de Vues.lua, et ses dimensions. Une
-- seule disposition, la « Conversation claire » (la plus proche de la 1.0) : les conversations à
-- gauche, le fil au centre, à droite les onglets Note et Proposition, l'aperçu, puis la carte
-- choisie ; en grande taille. L'Atelier, le Panneau et le choix de la disposition sont retirés, comme
-- le choix de la taille (demandés par Dany le 20 octobre 2026). Son cadre enregistré (Fenetre.cadre) :
-- Lightroom rend sa taille enregistrée à une fenêtre rouverte, sans la rapetisser (constaté).
--
-- Dimensions (D), lues aussi par Fenetre.lua : `lignes` (lignes du fil), `fil` (largeur de la
-- colonne du fil), `liste` (la liste des conversations), `droite` (la colonne de droite), `apercu`
-- (cadre carré de l'aperçu, et son image « aucun aperçu », scripts/images-vides.swift), `onglets`,
-- `ongletProposition` et `ongletNotation` (onglet montré quand une proposition ou une note
-- arrive), `propLignes` (lignes de la proposition), `criteres` (lignes des critères de la carte
-- Note) ; les autres sont des largeurs de pièces et des nombres de lignes.

local Vues = require 'Vues'

local Dispositions = {}

-- Le nom de la disposition, gardé dans celui du cadre enregistré (Fenetre.cadre).
Dispositions.NOM = 'conversation'

Dispositions.TAILLES = { lignes = 42, fil = 900, liste = 250, droite = 340, apercu = 320, propLignes = 21, criteres = 12 }

-- Les dimensions : une table neuve, avec `nom`, et les largeurs tirées des précédentes.
function Dispositions.dimensions()
    local D = { nom = Dispositions.NOM }
    for cle, valeur in pairs(Dispositions.TAILLES) do
        D[cle] = valeur
    end
    -- L'aperçu est toujours montré ; dessous, la carte Note ou la proposition (demandé par Dany le
    -- 20 octobre 2026 : l'aperçu et la note ensemble).
    D.onglets = {
        { valeur = 'notation', titre = "Note" },
        { valeur = 'proposition', titre = "Proposition" },
    }
    D.ongletProposition, D.ongletNotation = 'proposition', 'notation'
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
    -- Largeur du texte de la carte Note et de la proposition (Vues.notation, Vues.proposition),
    -- pour les couper en pages (Fenetre.montrerPage).
    D.largeurNote = D.droite - 24
    D.largeurProposition = D.droite - 24
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
    -- À droite : les onglets Note et Proposition en tête, puis l'aperçu, toujours montré ;
    -- après une ligne vide sous Agrandir, la carte Note ou la proposition ; en bas, Publication et
    -- Consommation, puis les versions, au niveau du champ de demande (demandé par Dany le
    -- 20 octobre 2026).
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
