-- Vues.lua : les pièces de la fenêtre Claude, assemblées par Dispositions.lua (la Conversation
-- claire, seule disposition). Chaque pièce rend une vue du SDK liée aux propriétés de la
-- fenêtre ; elle reçoit la fabrique `f`, la fenêtre `F` (Fenetre.lua : couleurs, polices, `bind`,
-- `egal`, `bouton`, les actions) et ses largeurs. Pas de `require 'Fenetre'` ici (Fenetre requiert
-- ce fichier par Dispositions) ni de couleur créée au chargement (la vérification des liens charge
-- ce fichier sans LrColor).
--
-- Tout bouton passe par F.bouton : son clic valide aussi le champ de demande, qui ne doit pas
-- partir ensuite. Ce qui varie passe par des propriétés liées et des variantes superposées de même
-- largeur (`place = 'overlapping'`) : une fenêtre ouverte ne change pas de structure. Seule une vue
-- simple se masque (`visible` sur un conteneur reste sans effet, constaté), et toujours par une
-- condition de F (F.egal, F.non, F.si, F.condition) : Vues.masquable la combine avec celle d'un
-- onglet.

local Consignes = require 'Consignes'

local Vues = {}

-- Fil -----------------------------------------------------------------------------------------

-- Une ligne du fil : une icône et une variante de texte par genre (police, couleur), superposées ;
-- un clic montre l'image dans l'aperçu ou le détail d'un outil.
function Vues.ligneFil(f, F, i, largeur)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local icones = { place = 'overlapping', width = 16 }
    for _, ic in ipairs(F.ICONES) do
        icones[#icones + 1] = f:static_text { title = ic.glyphe, font = P.texte, text_color = C[ic.couleur],
            visible = F.egal('i' .. i, ic.cle) }
    end
    local textes = { place = 'overlapping' }
    for _, st in ipairs(F.STYLES) do
        local genres = st.genres
        textes[#textes + 1] = f:static_text {
            title = bind('t' .. i),
            width = largeur,
            font = P[st.police],
            text_color = C[st.couleur],
            truncation = 'tail',
            visible = F.condition('g' .. i, function(v) return genres[v] == true end),
            mouse_down = function() F.cliquerLigne(i) end,
        }
    end
    return f:row { spacing = 4, f:column(icones), f:column(textes) }
end

-- La grille du fil : D.lignes lignes, à la largeur de la colonne du fil (D.fil).
function Vues.grille(f, F, D)
    local grille = { spacing = 0 }
    for i = 1, D.lignes do
        grille[#grille + 1] = Vues.ligneFil(f, F, i, F.largeurTexte())
    end
    return f:column(grille)
end

-- ▲ ▼ Fin, la position dans le fil, et ce que fait Claude (sinon le forfait).
function Vues.defilement(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local pas = math.floor(D.lignes * 0.8)
    local largeurActivite = D.activite
    local activite = f:column {
        place = 'overlapping',
        f:static_text { title = bind 'activite', text_color = C.orange, alignment = 'right', width = largeurActivite, truncation = 'tail',
            visible = F.si 'travaille' },
        f:static_text { title = bind 'forfait', font = P.petit, text_color = C.gris, alignment = 'right', width = largeurActivite,
            truncation = 'tail', visible = F.non 'travaille' },
    }
    local rangee = f:row {
        spacing = 4,
        F.bouton(f, { title = "▲", size = 'small', tooltip = "Remonter dans le fil", enabled = bind 'peutMonter',
            action = function() F.defiler(pas) end }),
        F.bouton(f, { title = "▼", size = 'small', tooltip = "Redescendre", enabled = bind 'peutDescendre',
            action = function() F.defiler(-pas) end }),
        F.bouton(f, { title = "Fin", size = 'small', tooltip = "Aller au dernier message", enabled = bind 'peutDescendre',
            action = function() F.defiler('fin') end }),
        f:static_text { title = bind 'positionFil', font = P.petit, text_color = C.gris, width = D.position, truncation = 'tail' },
        f:spacer { fill_horizontal = 1 },
        activite,
    }
    return rangee
end

-- Voyants --------------------------------------------------------------------------------------

function Vues.voyant(f, F, cleEtat, cleTexte, action, infobulle, largeur)
    local C, P = F.COULEURS, F.POLICES
    local pastilles = { place = 'overlapping' }
    for etat, couleur in pairs(F.PASTILLES) do
        pastilles[#pastilles + 1] = f:static_text { title = '●', font = P.petit, text_color = C[couleur], visible = F.egal(cleEtat, etat) }
    end
    return f:row {
        spacing = 3,
        f:column(pastilles),
        f:static_text { title = F.bind(cleTexte), font = P.petit, mouse_down = action, tooltip = infobulle, width = largeur, truncation = 'tail' },
    }
end

-- Claude Code, la liaison (un clic la démarre), le mode (un clic le bascule) et l'écran principal
-- du Mac (un clic le relit et donne son détail), en rangée, chaque texte à `largeur`.
function Vues.voyants(f, F, largeur)
    local liste = {
        Vues.voyant(f, F, 'etatClaude', 'texteClaude', nil, "Claude Code, avec votre forfait claude.ai (pas de clé d'API)", largeur),
        Vues.voyant(f, F, 'etatLightroom', 'texteLightroom', function()
            F.annulerEnvoiAuto()
            F.demarrerLiaison()
        end, "Liaison de ce module avec le connecteur MCP-Développeur ; arrêtée, un clic la démarre", largeur),
        Vues.voyant(f, F, 'etatMode', 'texteMode', function()
            F.annulerEnvoiAuto()
            F.basculerMode()
        end, "Mode du connecteur ; un clic bascule entre « Proposer d'abord » et « Appliquer directement »", largeur),
        Vues.voyant(f, F, 'etatEcran', 'texteEcran', function()
            F.annulerEnvoiAuto()
            F.enTache(F.montrerEcran)
        end, "Écran principal du Mac et son profil de couleur ; un clic donne le détail", largeur),
    }
    liste.spacing = 12
    return f:row(liste)
end

-- Le bandeau, une ligne en petit : un message (orange), sinon l'aide d'un voyant rouge (un clic
-- l'affiche en entier), sinon les photos jointes (un clic les retire), sinon rien (état 'vide' :
-- le rappel du style est retiré, demandé par Dany le 20 octobre 2026).
function Vues.bandeau(f, F, largeur)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        place = 'overlapping',
        f:static_text { title = bind { key = 'jointes', transform = function(v) return tostring(v or '') .. "  ·  cliquer pour retirer" end },
            font = P.petit, text_color = C.gris, width = largeur, truncation = 'middle', visible = F.egal('bandeau', 'jointes'),
            tooltip = "Cliquer pour retirer les photos jointes",
            mouse_down = function()
                F.annulerEnvoiAuto()
                F.retirerJointes()
            end },
        f:static_text { title = bind 'message', font = P.petit, text_color = C.orange, width = largeur, truncation = 'tail',
            visible = F.egal('bandeau', 'message') },
        f:static_text { title = bind 'aide', font = P.petit, text_color = C.rouge, width = largeur, truncation = 'tail',
            visible = F.egal('bandeau', 'aide'), tooltip = "Cliquer pour lire l'aide en entier",
            mouse_down = function()
                F.annulerEnvoiAuto()
                F.enTache(F.montrerAide)
            end },
    }
end

-- Versions -------------------------------------------------------------------------------------

-- Une ligne de version : le nom à gauche, le numéro à droite, en gris ou en orange (alerte).
function Vues.ligneVersion(f, F, i, largeur)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local alerte = F.si('versionAlerte' .. i)
    local normal = F.non('versionAlerte' .. i)
    return f:row {
        spacing = 0,
        f:column {
            place = 'overlapping',
            f:static_text { title = bind('versionNom' .. i), font = P.petit, text_color = C.gris, width = largeur - 46, truncation = 'tail', visible = normal },
            f:static_text { title = bind('versionNom' .. i), font = P.petit, text_color = C.orange, width = largeur - 46, truncation = 'tail', visible = alerte },
        },
        f:column {
            place = 'overlapping',
            f:static_text { title = bind('version' .. i), font = P.petit, text_color = C.gris, alignment = 'right', width = 46, visible = normal },
            f:static_text { title = bind('version' .. i), font = P.petit, text_color = C.orange, alignment = 'right', width = 46, visible = alerte },
        },
    }
end

-- Ce module et le connecteur MCP-Développeur.
function Vues.versions(f, F, largeur)
    return f:column { spacing = 2, Vues.ligneVersion(f, F, 1, largeur), Vues.ligneVersion(f, F, 2, largeur) }
end

-- Conversations --------------------------------------------------------------------------------

-- Le titre de la conversation et ✎ ; `info` : largeur de la photo active à droite (sinon rien).
function Vues.titre(f, F, largeur, info)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local r = {
        f:static_text { title = bind 'titre', font = P.titre, width = largeur, truncation = 'tail' },
        F.bouton(f, { title = "✎", size = 'small', tooltip = "Renommer la conversation", action = function() F.enTache(F.renommer) end }),
    }
    if info then
        r[#r + 1] = f:spacer { fill_horizontal = 1 }
        r[#r + 1] = f:static_text { title = bind 'infoPhoto', text_color = C.gris, alignment = 'right', width = info, truncation = 'middle' }
    end
    return f:row(r)
end

-- La colonne des conversations (Conversation claire) : Nouvelle, recherche, liste, Renommer et
-- Supprimer. La liste a une hauteur fixe (fill_vertical y reste sans effet, constaté) : `hauteur`
-- la fait finir au niveau du champ de demande.
function Vues.listeConversations(f, F, largeur, hauteur)
    local bind = F.bind
    return f:column {
        spacing = 8,
        width = largeur,
        fill_vertical = 1,
        F.bouton(f, { title = "Nouvelle conversation", width = largeur, enabled = bind 'libre', action = function() F.nouvelle() end }),
        f:edit_field { value = bind 'recherche', immediate = true, width = largeur, placeholder_string = "Rechercher" },
        f:simple_list { items = bind 'listeConversations', value = bind 'selectionListe', allows_multiple_selection = false,
            width = largeur, height = hauteur, enabled = bind 'libre' },
        f:row {
            F.bouton(f, { title = "Renommer…", size = 'small', action = function() F.enTache(F.renommer) end }),
            F.bouton(f, { title = "Supprimer…", size = 'small', enabled = bind 'libre', action = function() F.enTache(F.supprimer) end }),
        },
    }
end

-- Demandes -------------------------------------------------------------------------------------

-- Les invites en raccourcis, sur une rangée, et le menu Style au bout, sans étiquette (demandé par
-- Dany le 20 octobre 2026).
function Vues.invites(f, F, D)
    local rangee = { spacing = 6 }
    for _, invite in ipairs(Consignes.invites) do
        rangee[#rangee + 1] = F.bouton(f, {
            title = invite.titre,
            tooltip = invite.message,
            enabled = F.bind 'libre',
            action = function() F.envoyer(invite.message, invite.modele) end,
        })
    end
    rangee[#rangee + 1] = Vues.style(f, F, D)
    return f:row(rangee)
end

-- Le menu Style seul (D.style de large) : joint à chaque demande, invites comprises.
function Vues.style(f, F, D)
    local styles = {}
    for _, st in ipairs(Consignes.styles) do
        styles[#styles + 1] = { title = st.title, value = st.value }
    end
    return f:popup_menu { items = styles, value = F.bind 'style', width = D.style, enabled = F.bind 'libre',
        tooltip = "Style de retouche joint à chaque demande, invites comprises (Standard : rien d'ajouté)" }
end

-- ▲ et ▼ en petit, pour faire défiler un texte trop long d'une carte (clés `cle .. 'Monte'` et
-- `cle .. 'Descend'`, action F.defilerTexte(cle, sens)).
function Vues.fleches(f, F, cle)
    return f:row {
        spacing = 2,
        F.bouton(f, { title = "▲", size = 'mini', tooltip = "Remonter le texte", enabled = F.bind(cle .. 'Monte'),
            action = function() F.defilerTexte(cle, -1) end }),
        F.bouton(f, { title = "▼", size = 'mini', tooltip = "Descendre le texte", enabled = F.bind(cle .. 'Descend'),
            action = function() F.defilerTexte(cle, 1) end }),
    }
end

-- Le modèle et l'effort se choisissent dans le Gestionnaire de modules externes
-- (PluginInfoProvider.lua), pas dans la fenêtre (demandé par Dany le 20 octobre 2026 : un écran
-- plus léger).
function Vues.boutonEnvoyer(f, F, largeur)
    return F.bouton(f, { title = F.bind 'titreEnvoyer', width = largeur, action = function() F.boutonPrincipal() end })
end

-- 📎 et 📋, puis le champ de demande (D.champ), Envoyer à droite. Le champ est
-- `immediate = false` : Retour le valide (Fenetre.saisieValidee).
function Vues.saisie(f, F, D)
    local bind = F.bind
    return f:row {
        spacing = 6,
        f:column {
            spacing = 2,
            F.bouton(f, { title = "📎", tooltip = "Joindre une photo du disque à la demande", enabled = bind 'libre', action = function() F.enTache(F.joindre) end }),
            F.bouton(f, { title = "📋", tooltip = "Coller l'image du presse-papiers (capture d'écran, image copiée, photo copiée dans le Finder)", enabled = bind 'libre',
                action = function() F.enTache(F.coller) end }),
        },
        f:edit_field { value = bind 'saisie', immediate = false, height_in_lines = 3, width = D.champ, enabled = bind 'libre',
            placeholder_string = "Demander à Claude… (par exemple : « Retouche la photo active, rendu naturel »)",
            tooltip = "Retour envoie la demande. Dictée : touche 🌐 deux fois." },
        Vues.boutonEnvoyer(f, F, D.envoyer),
    }
end

-- Aperçu et proposition --------------------------------------------------------------------------

-- Ce que Claude regarde, ou la photo active : un cadre carré fixe de D.apercu, rempli par une
-- réduction centrée sur le fond (Images.vignette) ou l'image « aucun aperçu ».
function Vues.apercu(f, F, D)
    return f:picture { value = F.bind 'imageApercu', width = D.apercu, height = D.apercu }
end

-- ◀ légende ▶ (légende de `largeur`), en petit.
function Vues.navigationApercu(f, F, largeur)
    local bind, P = F.bind, F.POLICES
    return f:row {
        spacing = 4,
        F.bouton(f, { title = "◀", size = 'small', tooltip = "Image précédente", enabled = bind 'peutPrecedente', action = function() F.changerImage(-1) end }),
        f:static_text { title = bind 'legendeApercu', font = P.petit, alignment = 'center', width = largeur, truncation = 'middle' },
        F.bouton(f, { title = "▶", size = 'small', tooltip = "Image suivante", enabled = bind 'peutSuivante', action = function() F.changerImage(1) end }),
    }
end

function Vues.agrandir(f, F)
    return F.bouton(f, { title = "Agrandir", enabled = F.bind 'aImage', action = function() F.agrandir() end })
end

-- La proposition de Claude en mode « Proposer d'abord » : ce qu'il compte changer, Accepter,
-- Refuser, Ajuster… (actifs quand une proposition attend et que Claude ne travaille pas), et ▲ ▼
-- à leur droite pour faire défiler un texte plus long que la carte (F.defilerTexte, page tirée par
-- Fenetre.rafraichirProposition, coupée comme le fil : police P.texte).
function Vues.proposition(f, F, largeur, lignes)
    local bind, P = F.bind, F.POLICES
    local petit = largeur - 24 < 300 and 'small' or nil
    return f:group_box {
        title = "Proposition de Claude",
        width = largeur,
        f:static_text { title = bind 'propositionTexte', font = P.texte, width = largeur - 24, height_in_lines = lignes },
        f:row {
            spacing = 4,
            fill_horizontal = 1,
            F.bouton(f, { title = "Accepter", size = petit, enabled = bind 'enAttente', action = function() F.repondreProposition(true) end }),
            F.bouton(f, { title = "Refuser", size = petit, enabled = bind 'enAttente', action = function() F.repondreProposition(false) end }),
            F.bouton(f, { title = "Ajuster…", size = petit, enabled = bind 'enAttente', action = function() F.enTache(F.ajuster) end }),
            f:spacer { fill_horizontal = 1 },
            Vues.fleches(f, F, 'proposition'),
        },
    }
end

-- Note -------------------------------------------------------------------------------------------

-- La carte « Note » de la photo active : sa note posée, la note que Claude propose (couleur selon
-- l'état), puis son texte (critères du plus lourd au plus léger, plafond mesuré, raison), page par
-- page avec ▲ ▼ (Fenetre.rafraichirNotation, coupé comme le fil : police P.texte). Claude note
-- d'abord chaque photo qu'il traite, et sa note arrive « à vérifier » : Dany l'accepte ou la change
-- (demandé le 20 octobre 2026, plus de bouton Évaluer ni À vérifier). Accepter et Changer…
-- écrivent dans le catalogue sans Claude ni quota (désactivés pendant que Claude travaille) ; Dany
-- peut poser 5 ★, Claude jamais.
function Vues.notation(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local interieur = largeur - 24
    local petit = interieur < 300 and 'small' or nil
    local titres = { place = 'overlapping' }
    for _, couleur in ipairs({ 'gris', 'orange', 'vert', 'rouge' }) do
        titres[#titres + 1] = f:static_text { title = bind 'notationProposee', font = P.gras, text_color = C[couleur], width = interieur,
            truncation = 'tail', visible = F.egal('notationCouleur', couleur) }
    end
    local carte = {
        title = "Note",
        width = largeur,
        spacing = 4,
        f:static_text { title = bind 'notationNom', font = P.gras, width = interieur, truncation = 'middle' },
        f:static_text { title = bind 'notationPosee', width = interieur, truncation = 'tail' },
        f:separator { fill_horizontal = 1 },
        f:column(titres),
        f:static_text { title = bind 'notationEtat', font = P.petit, text_color = C.gris, width = interieur, truncation = 'tail' },
        f:static_text { title = bind 'notationTexte', font = P.texte, width = interieur, height_in_lines = D.criteres + 3 },
        f:row {
            spacing = 4,
            fill_horizontal = 1,
            F.bouton(f, { title = "Accepter", size = petit, enabled = bind 'peutAccepterNote',
                tooltip = "Poser la note proposée dans Lightroom (sans Claude ni quota)", action = function() F.enTache(F.accepterNote) end }),
            F.bouton(f, { title = "Changer…", size = petit, enabled = bind 'peutChangerNote',
                tooltip = "Poser une autre note, de 0 à 5 ★, ou le drapeau Rejeter", action = function() F.enTache(F.changerNote) end }),
            f:spacer { fill_horizontal = 1 },
            Vues.fleches(f, F, 'note'),
        },
    }
    return f:group_box(carte)
end

-- Autres fenêtres et onglets -------------------------------------------------------------------

-- Publication et Consommation (le menu Fichier est réduit quand une fenêtre du module est devant).
function Vues.autresFenetres(f, F)
    return f:row {
        spacing = 6,
        F.bouton(f, { title = "Publication…", tooltip = "Publier des photos en fichiers, sans Claude ni quota",
            action = function() F.publication() end }),
        F.bouton(f, { title = "Consommation…", tooltip = "Jetons de la semaine, budget, relevé du forfait",
            action = function() F.consommation() end }),
    }
end

-- Les onglets : une rangée de boutons radio (clé `onglet`) au-dessus de variantes superposées, dont
-- le contenu se crée par Vues.masquable.
function Vues.onglets(f, F, liste)
    local r = { spacing = 12 }
    for _, onglet in ipairs(liste) do
        r[#r + 1] = f:radio_button { title = onglet.titre, value = F.bind 'onglet', checked_value = onglet.valeur }
    end
    return f:row(r)
end

-- Ce qui passe tel quel par une fabrique masquable : conteneurs, espaces, écarts.
local SANS_CONDITION = { row = true, column = true, view = true, scrolled_view = true, tab_view = true, tab_view_item = true,
    spacer = true, control_spacing = true, dialog_spacing = true, label_spacing = true }

-- Une fabrique qui masque tout ce qu'elle crée quand `condition` (une condition de F) est fausse.
-- Lightroom ignore `visible` lié sur un conteneur : la colonne d'un onglet restait montrée, et les
-- trois onglets de la Conversation claire s'affichaient superposés (constaté le 20 octobre 2026) ;
-- sur une vue simple, il marche. La fabrique pose donc la condition sur chaque vue simple créée par
-- les pièces (texte, bouton, image, menu, champ, case, liste, séparateur…), combinée à son propre
-- `visible` (couleurs de la carte Note, pastilles, lignes du fil) en une liaison à plusieurs clés
-- (F.et) ; une boîte de groupe, dont le cadre et le titre resteraient montrés, y devient une
-- colonne à titre gras. Les conteneurs restent sans `visible`. Une fabrique masquable peut
-- s'envelopper dans une autre (les conditions se combinent).
function Vues.masquable(f, F, condition)
    local fm = {}
    return setmetatable(fm, {
        __index = function(_, genre)
            if genre == 'group_box' then
                return function(_, args)
                    local colonne = { spacing = 4, fm:static_text { title = args.title, font = F.POLICES.gras } }
                    for cle, valeur in pairs(args) do
                        if type(cle) == 'string' and cle ~= 'title' then
                            colonne[cle] = valeur
                        end
                    end
                    for _, vue in ipairs(args) do
                        colonne[#colonne + 1] = vue
                    end
                    return f:column(colonne)
                end
            elseif SANS_CONDITION[genre] then
                return function(_, ...) return f[genre](f, ...) end
            end
            return function(_, args)
                args = args or {}
                args.visible = args.visible ~= nil and F.et(args.visible, condition) or F.et(condition)
                return f[genre](f, args)
            end
        end,
    })
end

return Vues
