-- Dispositions.lua : les trois dispositions de la fenêtre Claude, assemblées des pièces de
-- Vues.lua, et leurs dimensions (préférence `disposition`, Chemins.defauts ; une seule taille, la
-- grande, depuis la 1.1.1 : demandé par Dany le 20 octobre 2026) :
--   - « Atelier » : la photo d'abord (ce que Claude regarde, en grand, et sa proposition), la
--     carte Note à côté, la conversation en colonne étroite à droite ;
--   - « Conversation claire » (par défaut, la plus proche de la 1.0) : les conversations, le fil au
--     centre, à droite les onglets Note et Proposition, l'aperçu, puis la carte choisie ;
--   - « Panneau » : une fenêtre étroite et haute, à côté de Lightroom, onglets Retoucher et Noter.
-- Chacune a son cadre enregistré (Fenetre.cadre) : Lightroom rend sa taille enregistrée à une
-- fenêtre rouverte, sans la rapetisser (constaté).
--
-- Dimensions (D), lues aussi par Fenetre.lua : `lignes` (lignes du fil), `fil` (largeur de la
-- colonne du fil), `apercu` et `apercuHauteur` (cadre de l'aperçu, carré sans hauteur, et son
-- image « aucun aperçu », scripts/images-vides.swift), `onglets`, `ongletProposition` et
-- `ongletNotation` (onglet montré quand une proposition ou une note arrive) ; les autres sont des
-- largeurs de pièces et des nombres de lignes.

local Vues = require 'Vues'

local Dispositions = {}

Dispositions.DEFAUT = 'conversation'

-- Dans l'ordre du menu Disposition du Gestionnaire de modules externes.
Dispositions.LISTE = {
    { value = 'atelier', title = "Atelier" },
    { value = 'conversation', title = "Conversation claire" },
    { value = 'panneau', title = "Panneau" },
}

-- Les dimensions de chaque disposition, en grande taille. Atelier : `photo` (colonne de la
-- photo, aperçu 3:2), `note` (colonne de la carte Note), `menu` (menu des conversations).
-- Conversation claire : celles de la 1.0, la colonne de droite (`droite`) à onglets. Panneau :
-- `largeur` du contenu (fenêtre de 24 de plus) ; 20 lignes de fil pour tenir en hauteur sur un
-- écran de 1080 points (environ 1 050 avec la barre de titre, estimé). `propLignes` : lignes de
-- la proposition ; `criteres` : lignes des critères de la carte Note.
Dispositions.TAILLES = {
    atelier = { lignes = 38, fil = 440, photo = 740, apercu = 720, apercuHauteur = 480, note = 300, menu = 240, propLignes = 9, criteres = 15 },
    conversation = { lignes = 42, fil = 900, liste = 250, droite = 340, apercu = 320, propLignes = 21, criteres = 12 },
    panneau = { lignes = 20, largeur = 460, apercu = 200, propLignes = 6, criteres = 20 },
}

-- Largeurs tirées des précédentes (une seule source par disposition).
local COMPLETER = {
    atelier = function(D)
        D.invitesParRangee = 3
        D.activiteDessous = true
        D.titre = D.fil - 40
        D.voyant = D.fil - 20
        D.position = 140
        D.style = 150
        D.bandeau = D.fil
        D.champ = D.fil - 50
        D.envoyer = 120
        D.legende = D.apercu - 160
        -- Largeur du texte de la carte Note et de la proposition (Vues.notation, Vues.proposition),
        -- pour les couper en pages (Fenetre.montrerPage).
        D.largeurNote = D.note - 24
        D.largeurProposition = D.photo - 24
    end,
    conversation = function(D)
        -- L'aperçu est toujours montré ; dessous, la carte Note ou la proposition (demandé par Dany
        -- le 20 octobre 2026 : l'aperçu et la note ensemble).
        D.onglets = {
            { valeur = 'notation', titre = "Note" },
            { valeur = 'proposition', titre = "Proposition" },
        }
        D.ongletProposition, D.ongletNotation = 'proposition', 'notation'
        D.envoiACote = true
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
        D.largeurNote = D.droite - 24
        D.largeurProposition = D.droite - 24
        -- La liste des conversations finit au niveau du champ de demande : la grille, plus ce qui
        -- la suit au centre (▲ ▼, séparateur, invites et Style, bandeau, demande). Le nombre de
        -- lignes du fil donne au centre la hauteur de la colonne de droite (aperçu, carte Note).
        D.hauteurListe = D.lignes * 17 + 85
    end,
    panneau = function(D)
        D.onglets = {
            { valeur = 'retoucher', titre = "Retoucher" },
            { valeur = 'notation', titre = "Noter" },
        }
        D.ongletProposition, D.ongletNotation = 'retoucher', 'notation'
        D.fil = D.largeur
        D.invitesParRangee = 3
        D.activiteDessous = true
        D.voyant = math.floor((D.largeur - 2 * 6) / 3) - 16
        D.position = 150
        D.style = 150
        D.champ = D.largeur - 50
        D.envoyer = 120
        D.menu = D.largeur - D.apercu - 8
        D.largeurNote = D.largeur - 24
        D.largeurProposition = D.largeur - 24
    end,
}

-- La disposition donnée si elle existe, sinon celle par défaut.
function Dispositions.valider(nom)
    return Dispositions.TAILLES[nom] and nom or Dispositions.DEFAUT
end

-- Les dimensions d'une disposition (une valeur inconnue retombe sur la disposition par défaut) :
-- une table neuve, avec `nom`.
function Dispositions.dimensions(nom)
    nom = Dispositions.valider(nom)
    local D = { nom = nom }
    for cle, valeur in pairs(Dispositions.TAILLES[nom]) do
        D[cle] = valeur
    end
    COMPLETER[nom](D)
    return D
end

-- Le nom de l'image « aucun aperçu » du cadre : vide-320.png, vide-720x480.png.
function Dispositions.imageVide(D)
    local hauteur = D.apercuHauteur or D.apercu
    if hauteur == D.apercu then
        return 'vide-' .. D.apercu .. '.png'
    end
    return 'vide-' .. D.apercu .. 'x' .. hauteur .. '.png'
end

-- Éléments d'un menu de disposition (tables neuves), titres précédés de `prefixe`.
function Dispositions.items(prefixe)
    local items = {}
    for _, d in ipairs(Dispositions.LISTE) do
        items[#items + 1] = { title = (prefixe or '') .. d.title, value = d.value }
    end
    return items
end

-- Assemblages -----------------------------------------------------------------------------------

-- Une variante superposée, de largeur `largeur`, montrée quand l'onglet vaut `valeur` :
-- `pieces(fm)` rend la table de sa colonne, ses vues créées par la fabrique masquable `fm`, qui
-- pose la condition de l'onglet sur chaque vue simple. La colonne ne porte pas `visible` :
-- Lightroom l'ignore sur un conteneur (constaté, voir Vues.masquable).
local function variante(f, F, largeur, valeur, pieces)
    local contenu = pieces(Vues.masquable(f, F, F.egal('onglet', valeur)))
    contenu.width = largeur
    return f:column(contenu)
end

function Dispositions.atelier(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local photo = f:column {
        spacing = 8,
        width = D.photo,
        fill_vertical = 1,
        f:row {
            spacing = 4,
            Vues.menuConversations(f, F, D.menu),
            Vues.boutonsConversation(f, F, false),
        },
        Vues.apercu(f, F, D),
        f:row { Vues.navigationApercu(f, F, D.legende), f:spacer { fill_horizontal = 1 }, Vues.agrandir(f, F, true) },
        Vues.proposition(f, F, D.photo, D.propLignes),
        f:spacer { fill_vertical = 1 },
    }
    local note = f:column {
        spacing = 8,
        width = D.note,
        fill_vertical = 1,
        f:static_text { title = bind 'infoPhoto', font = P.petit, text_color = C.gris, width = D.note, truncation = 'middle' },
        Vues.notation(f, F, D.note, D),
        f:spacer { fill_vertical = 1 },
        -- Publication et Consommation juste au-dessus des versions, en bas.
        Vues.autresFenetres(f, F, true),
        f:separator { fill_horizontal = 1 },
        Vues.versions(f, F, D.note),
    }
    local conversation = f:column {
        spacing = 6,
        width = D.fil,
        fill_vertical = 1,
        Vues.titre(f, F, D.titre),
        Vues.voyants(f, F, 'colonne', D.voyant),
        f:separator { fill_horizontal = 1 },
        Vues.grille(f, F, D),
        Vues.defilement(f, F, D),
        -- Ne grandit que si une autre colonne est plus haute.
        f:spacer { fill_vertical = 1 },
        f:separator { fill_horizontal = 1 },
        Vues.invites(f, F, D),
        Vues.bandeau(f, F, D.bandeau),
        Vues.saisie(f, F, D),
        Vues.envoi(f, F, D),
    }
    return f:row {
        bind_to_object = F.p,
        margin = 12,
        spacing = 12,
        photo,
        f:separator { fill_vertical = 1 },
        note,
        f:separator { fill_vertical = 1 },
        conversation,
    }
end

function Dispositions.conversation(f, F, D)
    local centre = f:column {
        spacing = 6,
        width = D.fil,
        fill_vertical = 1,
        Vues.titre(f, F, D.titre, D.info),
        Vues.voyants(f, F, 'rangee', D.voyant),
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

function Dispositions.panneau(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local L = D.largeur
    local entete = f:row {
        spacing = 8,
        Vues.apercu(f, F, D),
        f:column {
            spacing = 4,
            width = D.menu,
            Vues.menuConversations(f, F, D.menu),
            Vues.boutonsConversation(f, F, true),
            f:static_text { title = bind 'infoPhoto', font = P.petit, text_color = C.gris, width = D.menu, truncation = 'middle' },
            f:static_text { title = bind 'notationPosee', font = P.petit, width = D.menu, truncation = 'tail' },
            f:static_text { title = bind 'legendeApercu', font = P.petit, text_color = C.gris, width = D.menu, truncation = 'middle' },
            f:row { spacing = 4, Vues.navigationApercu(f, F), Vues.agrandir(f, F, true) },
        },
    }
    local retoucher = variante(f, F, L, 'retoucher', function(fm)
        -- La proposition, compacte, prend la place des invites (et du menu Style) le temps d'y
        -- répondre : deux fabriques masquables dans celle de l'onglet. Le bandeau suit chacune
        -- (sous les invites, il ne flotte pas sous la place laissée à la proposition, plus haute).
        local sansProposition = Vues.masquable(fm, F, F.non 'aProposition')
        local avecProposition = Vues.masquable(fm, F, F.si 'aProposition')
        return {
            spacing = 6,
            Vues.voyants(fm, F, 'rangee', D.voyant, 6),
            fm:separator { fill_horizontal = 1 },
            Vues.grille(fm, F, D),
            Vues.defilement(fm, F, D),
            fm:separator { fill_horizontal = 1 },
            f:column {
                place = 'overlapping',
                f:column { width = L, spacing = 6, Vues.invites(sansProposition, F, D), Vues.bandeau(sansProposition, F, L) },
                f:column { width = L, spacing = 6, Vues.proposition(avecProposition, F, L, D.propLignes),
                    Vues.bandeau(avecProposition, F, L) },
            },
            Vues.saisie(fm, F, D),
            Vues.envoi(fm, F, D),
        }
    end)
    local noter = variante(f, F, L, 'notation', function(fm) return { Vues.notation(fm, F, L, D) } end)
    return f:column {
        bind_to_object = F.p,
        margin = 12,
        spacing = 8,
        entete,
        Vues.onglets(f, F, D.onglets),
        f:column { place = 'overlapping', retoucher, noter },
        f:separator { fill_horizontal = 1 },
        Vues.autresFenetres(f, F, true),
        Vues.versions(f, F, L),
    }
end

-- L'arbre de la fenêtre dans la disposition D (sa racine liée à F.p).
function Dispositions.construire(f, F, D)
    return Dispositions[D.nom](f, F, D)
end

return Dispositions
