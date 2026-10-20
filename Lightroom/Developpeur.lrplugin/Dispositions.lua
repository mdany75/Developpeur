-- Dispositions.lua : les trois dispositions de la fenêtre Claude, assemblées des pièces de
-- Vues.lua, et leurs dimensions dans chaque taille de fenêtre (préférences `disposition` et
-- `taille`, Chemins.defauts) :
--   - « Atelier » : la photo d'abord (ce que Claude regarde, en grand, et sa proposition), la
--     carte Note à côté, la conversation en colonne étroite à droite ;
--   - « Conversation claire » (par défaut, la plus proche de la 1.0) : les conversations, le fil au
--     centre, à droite des onglets Aperçu, Proposition et Note ;
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

-- Dans l'ordre des menus (Gestionnaire de modules externes, menu Disposition de la fenêtre).
Dispositions.LISTE = {
    { value = 'atelier', title = "Atelier" },
    { value = 'conversation', title = "Conversation claire" },
    { value = 'panneau', title = "Panneau" },
}

-- Par taille de fenêtre. Atelier : `photo` (colonne de la photo, aperçu 3:2), `note` (colonne de
-- la carte Note), `menu` (menu des conversations). Conversation claire : celles de la 1.0, la
-- colonne de droite (`droite`) à onglets. Panneau : `largeur` du contenu (fenêtre de 24 de plus) ;
-- en grande taille, 20 lignes de fil pour tenir en hauteur sur un écran de 1080 points (environ
-- 1 050 avec la barre de titre, estimé). `propLignes` : lignes de la proposition ; `criteres` :
-- lignes des critères de la carte Note.
Dispositions.TAILLES = {
    atelier = {
        petite = { lignes = 20, fil = 330, photo = 470, apercu = 450, apercuHauteur = 300, note = 250, menu = 150, propLignes = 5, criteres = 9 },
        moyenne = { lignes = 28, fil = 380, photo = 620, apercu = 600, apercuHauteur = 400, note = 270, menu = 200, propLignes = 7, criteres = 12 },
        grande = { lignes = 38, fil = 440, photo = 740, apercu = 720, apercuHauteur = 480, note = 300, menu = 240, propLignes = 9, criteres = 15 },
    },
    conversation = {
        petite = { lignes = 22, fil = 560, liste = 190, droite = 250, apercu = 230, propLignes = 14, criteres = 8, invitesPetites = true },
        moyenne = { lignes = 30, fil = 760, liste = 220, droite = 300, apercu = 270, propLignes = 18, criteres = 11 },
        grande = { lignes = 40, fil = 900, liste = 250, droite = 340, apercu = 320, propLignes = 22, criteres = 14 },
    },
    panneau = {
        petite = { lignes = 12, largeur = 380, apercu = 120, propLignes = 5, criteres = 12 },
        moyenne = { lignes = 18, largeur = 406, apercu = 160, propLignes = 5, criteres = 16 },
        grande = { lignes = 20, largeur = 460, apercu = 200, propLignes = 6, criteres = 20 },
    },
}

-- Largeurs tirées des précédentes (une seule source par disposition).
local COMPLETER = {
    atelier = function(D)
        D.invitesParRangee = 3
        D.activiteDessous = true
        D.titre = D.fil - 40
        D.voyant = D.fil - 20
        D.position = 140
        D.style = 140
        D.bandeau = D.fil - D.style - 52
        D.champ = D.fil - 50
        D.modele = 170
        D.envoyer = 120
        D.legende = D.apercu - 160
    end,
    conversation = function(D)
        D.onglets = {
            { valeur = 'apercu', titre = "Aperçu" },
            { valeur = 'proposition', titre = "Proposition" },
            { valeur = 'notation', titre = "Note" },
        }
        D.ongletProposition, D.ongletNotation = 'proposition', 'notation'
        D.noterDansInvites = true
        D.envoiACote = true
        D.titre = D.fil - 280
        D.info = 210
        D.voyant = 150
        D.position = 150
        D.activite = 300
        D.style = 220
        D.bandeau = D.fil - 300
        D.champ = D.fil - 250
        D.modele = 170
        D.legende = D.apercu - 80
        -- La liste des conversations finit au niveau du champ de demande : la grille, plus ce qui
        -- la suit au centre (▲ ▼, séparateur, invites, Style, demande).
        D.hauteurListe = D.lignes * 17 + 93
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
        D.modele = 170
        D.envoyer = 120
        D.menu = D.largeur - D.apercu - 8
        D.menuDisposition = D.largeur - 205
    end,
}

-- La disposition donnée si elle existe, sinon celle par défaut.
function Dispositions.valider(nom)
    return Dispositions.TAILLES[nom] and nom or Dispositions.DEFAUT
end

-- Les dimensions d'une disposition dans une taille (une valeur inconnue retombe sur la
-- disposition par défaut, la taille moyenne) : une table neuve, avec `nom` et `taille`.
function Dispositions.dimensions(nom, taille)
    nom = Dispositions.valider(nom)
    local tailles = Dispositions.TAILLES[nom]
    taille = tailles[taille] and taille or 'moyenne'
    local D = { nom = nom, taille = taille }
    for cle, valeur in pairs(tailles[taille]) do
        D[cle] = valeur
    end
    COMPLETER[nom](D)
    return D
end

-- Le nom de l'image « aucun aperçu » du cadre : vide-270.png, vide-600x400.png.
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

-- Une variante superposée, de largeur `largeur`, montrée quand l'onglet vaut `valeur`.
local function variante(f, F, largeur, valeur, contenu)
    contenu.width = largeur
    contenu.visible = F.egal('onglet', valeur)
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
            f:spacer { fill_horizontal = 1 },
            Vues.boutonNoter(f, F),
            Vues.boutonSeance(f, F),
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
        Vues.notation(f, F, D.note, D, true),
        Vues.autresFenetres(f, F, true),
        Vues.disposition(f, F, D.note, Dispositions.items("Disposition : ")),
        f:spacer { fill_vertical = 1 },
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
        Vues.style(f, F, D),
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
    local P = F.POLICES
    local centre = f:column {
        spacing = 6,
        width = D.fil,
        fill_vertical = 1,
        Vues.titre(f, F, D.titre, D.info),
        Vues.voyants(f, F, 'rangee', D.voyant),
        f:separator { fill_horizontal = 1 },
        Vues.grille(f, F, D),
        Vues.defilement(f, F, D),
        -- Ne grandit que si une autre colonne est plus haute (petite taille). La liste des
        -- conversations (D.hauteurListe) finit au niveau du champ de demande.
        f:spacer { fill_vertical = 1 },
        f:separator { fill_horizontal = 1 },
        Vues.invites(f, F, D),
        Vues.style(f, F, D),
        Vues.saisie(f, F, D),
    }
    local droite = f:column {
        spacing = 8,
        width = D.droite,
        fill_vertical = 1,
        Vues.onglets(f, F, D.onglets),
        f:column {
            place = 'overlapping',
            variante(f, F, D.droite, 'apercu', {
                spacing = 8,
                f:static_text { title = "Ce que Claude voit", font = P.gras },
                Vues.apercu(f, F, D),
                Vues.navigationApercu(f, F, D.legende),
                Vues.agrandir(f, F),
            }),
            variante(f, F, D.droite, 'proposition', { Vues.proposition(f, F, D.droite, D.propLignes) }),
            variante(f, F, D.droite, 'notation', { Vues.notation(f, F, D.droite, D) }),
        },
        Vues.autresFenetres(f, F),
        Vues.disposition(f, F, D.droite, Dispositions.items("Disposition : ")),
        -- Les versions en bas, au niveau du champ de demande.
        f:spacer { fill_vertical = 1 },
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
    local retoucher = variante(f, F, L, 'retoucher', {
        spacing = 6,
        Vues.voyants(f, F, 'rangee', D.voyant, 6),
        f:separator { fill_horizontal = 1 },
        Vues.grille(f, F, D),
        Vues.defilement(f, F, D),
        f:separator { fill_horizontal = 1 },
        -- La proposition, compacte, prend la place des invites et du style le temps d'y répondre.
        f:column {
            place = 'overlapping',
            f:column { width = L, spacing = 6, visible = F.non 'aProposition', Vues.invites(f, F, D), Vues.style(f, F, D) },
            f:column { width = L, visible = bind 'aProposition', Vues.proposition(f, F, L, D.propLignes) },
        },
        Vues.bandeau(f, F, L),
        Vues.saisie(f, F, D),
        Vues.envoi(f, F, D),
    })
    local noter = variante(f, F, L, 'notation', { Vues.notation(f, F, L, D) })
    return f:column {
        bind_to_object = F.p,
        margin = 12,
        spacing = 8,
        entete,
        Vues.onglets(f, F, D.onglets),
        f:column { place = 'overlapping', retoucher, noter },
        f:separator { fill_horizontal = 1 },
        f:row {
            spacing = 6,
            Vues.autresFenetres(f, F, true),
            f:spacer { fill_horizontal = 1 },
            Vues.disposition(f, F, D.menuDisposition, Dispositions.items("Disposition : ")),
        },
        Vues.versions(f, F, L),
    }
end

-- L'arbre de la fenêtre dans la disposition D (sa racine liée à F.p).
function Dispositions.construire(f, F, D)
    return Dispositions[D.nom](f, F, D)
end

return Dispositions
