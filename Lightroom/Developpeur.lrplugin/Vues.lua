-- Vues.lua : les pièces de la fenêtre Claude, assemblées par Dispositions.lua (Atelier,
-- Conversation claire, Panneau). Chaque pièce rend une vue du SDK liée aux propriétés de la
-- fenêtre ; elle reçoit la fabrique `f`, la fenêtre `F` (Fenetre.lua : couleurs, polices, `bind`,
-- `egal`, `bouton`, les actions) et ses largeurs. Pas de `require 'Fenetre'` ici (Fenetre requiert
-- ce fichier par Dispositions) ni de couleur créée au chargement (la vérification des liens charge
-- ce fichier sans LrColor).
--
-- Tout bouton passe par F.bouton : son clic valide aussi le champ de demande, qui ne doit pas
-- partir ensuite. Ce qui varie passe par des propriétés liées et des variantes superposées de même
-- largeur (`place = 'overlapping'`) : une fenêtre ouverte ne change pas de structure.

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
            visible = bind { key = 'g' .. i, transform = function(v) return genres[v] == true end },
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

-- ▲ ▼ Fin, la position dans le fil, et ce que fait Claude (sinon le forfait). Colonne étroite
-- (D.activiteDessous) : l'activité sur sa propre ligne, de toute la largeur.
function Vues.defilement(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local pas = math.floor(D.lignes * 0.8)
    local largeurActivite = D.activiteDessous and D.fil or D.activite
    local activite = f:column {
        place = 'overlapping',
        f:static_text { title = bind 'activite', text_color = C.orange, alignment = 'right', width = largeurActivite, truncation = 'tail',
            visible = bind 'travaille' },
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
        not D.activiteDessous and activite or nil,
    }
    if D.activiteDessous then
        return f:column { spacing = 2, rangee, activite }
    end
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

-- Claude Code, la liaison (un clic la démarre) et le mode (un clic le bascule), en rangée ou en
-- colonne (`sens`), chaque texte à `largeur`.
function Vues.voyants(f, F, sens, largeur, ecart)
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
    }
    if sens == 'colonne' then
        liste.spacing = 2
        return f:column(liste)
    end
    liste.spacing = ecart or 12
    return f:row(liste)
end

-- Le bandeau, une ligne en petit : un message (orange), sinon l'aide d'un voyant rouge (un clic
-- l'affiche en entier), sinon les photos jointes (un clic les retire), sinon le rappel du style.
function Vues.bandeau(f, F, largeur)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        place = 'overlapping',
        f:static_text { title = "ajouté à chaque demande, invites comprises", font = P.petit, text_color = C.gris,
            width = largeur, visible = F.egal('bandeau', 'rappel') },
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
    local alerte = bind('versionAlerte' .. i)
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

-- Le menu des conversations (Atelier, Panneau) : les plus récentes, la conversation montrée choisie.
function Vues.menuConversations(f, F, largeur)
    local bind = F.bind
    return f:popup_menu { items = bind 'menuConversations', value = bind 'conversationChoisie', width = largeur, enabled = bind 'libre',
        tooltip = "Conversation montrée (les plus récentes)" }
end

-- Nouvelle, Renommer (✎, si `renommer`) et Supprimer…, en petit.
function Vues.boutonsConversation(f, F, renommer)
    local bind = F.bind
    local r = {
        spacing = 4,
        F.bouton(f, { title = "Nouvelle", size = 'small', tooltip = "Nouvelle conversation", enabled = bind 'libre', action = function() F.nouvelle() end }),
    }
    if renommer then
        r[#r + 1] = F.bouton(f, { title = "✎", size = 'small', tooltip = "Renommer la conversation", action = function() F.enTache(F.renommer) end })
    end
    r[#r + 1] = F.bouton(f, { title = "Supprimer…", size = 'small', tooltip = "Supprimer la conversation (corbeille du Finder)", enabled = bind 'libre',
        action = function() F.enTache(F.supprimer) end })
    return f:row(r)
end

-- Demandes -------------------------------------------------------------------------------------

-- Noter : la photo active (une photo) ou la séance de notation (plusieurs photos sélectionnées).
function Vues.boutonNoter(f, F, petit)
    return F.bouton(f, { title = "Noter", size = petit and 'small' or nil, enabled = F.bind 'libre',
        tooltip = "Claude propose une note pour la photo active ; plusieurs photos sélectionnées : la séance de notation",
        action = function() F.enTache(F.noter) end })
end

function Vues.boutonSeance(f, F, petit)
    return F.bouton(f, { title = "Séance…", size = petit and 'small' or nil,
        tooltip = "Séance de notation : une sélection ou une collection, passe par passe",
        action = function() F.seance() end })
end

-- Les invites en raccourcis, D.invitesParRangee par rangée (toutes sur une sans elle) ; le bouton
-- Noter en tête si D.noterDansInvites ; en petit si D.invitesPetites.
function Vues.invites(f, F, D)
    local taille = D.invitesPetites and 'small' or nil
    local boutons = {}
    if D.noterDansInvites then
        boutons[#boutons + 1] = Vues.boutonNoter(f, F, D.invitesPetites)
    end
    for _, invite in ipairs(Consignes.invites) do
        boutons[#boutons + 1] = F.bouton(f, {
            title = invite.titre,
            tooltip = invite.message,
            size = taille,
            enabled = F.bind 'libre',
            action = function() F.envoyer(invite.message, invite.modele) end,
        })
    end
    local parRangee = D.invitesParRangee or #boutons
    local rangees = { spacing = 4 }
    for debut = 1, #boutons, parRangee do
        local rangee = { spacing = 6 }
        for k = debut, math.min(#boutons, debut + parRangee - 1) do
            rangee[#rangee + 1] = boutons[k]
        end
        rangees[#rangees + 1] = f:row(rangee)
    end
    if #rangees == 1 then
        return rangees[1]
    end
    return f:column(rangees)
end

-- « Style » et son menu ; le bandeau à droite si D.bandeau (sa largeur).
function Vues.style(f, F, D)
    local styles = {}
    for _, st in ipairs(Consignes.styles) do
        styles[#styles + 1] = { title = st.title, value = st.value }
    end
    return f:row {
        spacing = 8,
        f:static_text { title = "Style" },
        f:popup_menu { items = styles, value = F.bind 'style', width = D.style, enabled = F.bind 'libre',
            tooltip = "Style de retouche joint à chaque demande (Standard : rien d'ajouté)" },
        D.bandeau and Vues.bandeau(f, F, D.bandeau) or nil,
    }
end

function Vues.menuModele(f, F, largeur)
    local modeles = {}
    for _, m in ipairs(Consignes.modeles) do
        modeles[#modeles + 1] = { title = m.title, value = m.value }
    end
    return f:popup_menu { items = modeles, value = F.bind 'modele', width = largeur, enabled = F.bind 'libre' }
end

function Vues.boutonEnvoyer(f, F, largeur)
    return F.bouton(f, { title = F.bind 'titreEnvoyer', width = largeur, action = function() F.boutonPrincipal() end })
end

-- 📎 et 📋, puis le champ de demande (D.champ) ; le modèle et Envoyer à droite si D.envoiACote.
-- Le champ est `immediate = false` : Retour le valide (Fenetre.saisieValidee).
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
        D.envoiACote and f:column { spacing = 6, Vues.menuModele(f, F, D.modele), Vues.boutonEnvoyer(f, F, D.modele) } or nil,
    }
end

-- Le modèle et Envoyer sous le champ (Atelier, Panneau).
function Vues.envoi(f, F, D)
    return f:row { spacing = 6, Vues.menuModele(f, F, D.modele), f:spacer { fill_horizontal = 1 }, Vues.boutonEnvoyer(f, F, D.envoyer) }
end

-- Aperçu et proposition --------------------------------------------------------------------------

-- Ce que Claude regarde : un cadre fixe de D.apercu × D.apercuHauteur (carré sans elle), rempli
-- par une réduction centrée sur le fond (Images.vignette) ou l'image « aucun aperçu ».
function Vues.apercu(f, F, D)
    return f:picture { value = F.bind 'imageApercu', width = D.apercu, height = D.apercuHauteur or D.apercu }
end

-- ◀ légende ▶ (légende de `largeur`, sans légende si nil), en petit.
function Vues.navigationApercu(f, F, largeur)
    local bind, P = F.bind, F.POLICES
    local r = {
        spacing = 4,
        F.bouton(f, { title = "◀", size = 'small', tooltip = "Image précédente", enabled = bind 'peutPrecedente', action = function() F.changerImage(-1) end }),
    }
    if largeur then
        r[#r + 1] = f:static_text { title = bind 'legendeApercu', font = P.petit, alignment = 'center', width = largeur, truncation = 'middle' }
    end
    r[#r + 1] = F.bouton(f, { title = "▶", size = 'small', tooltip = "Image suivante", enabled = bind 'peutSuivante', action = function() F.changerImage(1) end })
    return f:row(r)
end

function Vues.agrandir(f, F, petit)
    return F.bouton(f, { title = "Agrandir", size = petit and 'small' or nil, enabled = F.bind 'aImage', action = function() F.agrandir() end })
end

-- La proposition de Claude en mode « Proposer d'abord » : ce qu'il compte changer, Accepter,
-- Refuser, Ajuster… (actifs quand une proposition attend et que Claude ne travaille pas).
function Vues.proposition(f, F, largeur, lignes)
    local bind = F.bind
    local petit = largeur - 24 < 260 and 'small' or nil
    return f:group_box {
        title = "Proposition de Claude",
        width = largeur,
        f:static_text { title = bind 'propositionTexte', width = largeur - 24, height_in_lines = lignes },
        f:row {
            spacing = 4,
            F.bouton(f, { title = "Accepter", size = petit, enabled = bind 'enAttente', action = function() F.repondreProposition(true) end }),
            F.bouton(f, { title = "Refuser", size = petit, enabled = bind 'enAttente', action = function() F.repondreProposition(false) end }),
            F.bouton(f, { title = "Ajuster…", size = petit, enabled = bind 'enAttente', action = function() F.enTache(F.ajuster) end }),
        },
    }
end

-- Note -------------------------------------------------------------------------------------------

-- La carte « Note » de la photo active : sa note posée, la note que Claude propose (couleur selon
-- l'état), ses critères du plus lourd au plus léger, le plafond mesuré et la raison. Accepter et
-- Changer… écrivent dans le catalogue sans Claude ni quota (désactivés pendant que Claude
-- travaille) ; Dany peut poser 5 ★, Claude jamais. `sansNoter` : Noter et Séance… sont ailleurs
-- (barre de l'Atelier).
function Vues.notation(f, F, largeur, D, sansNoter)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local interieur = largeur - 24
    local petit = interieur < 260 and 'small' or nil
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
        f:static_text { title = bind 'notationCriteres', width = interieur, height_in_lines = D.criteres },
        f:static_text { title = bind 'notationRaison', text_color = C.mono, width = interieur, height_in_lines = D.raisonLignes or 3 },
        f:row {
            spacing = 4,
            F.bouton(f, { title = "Accepter", size = petit, enabled = bind 'peutAccepterNote',
                tooltip = "Poser la note proposée dans Lightroom (sans Claude ni quota)", action = function() F.enTache(F.accepterNote) end }),
            F.bouton(f, { title = "Changer…", size = petit, enabled = bind 'peutChangerNote',
                tooltip = "Poser une autre note, de 0 à 5 ★, ou le drapeau Rejeter", action = function() F.enTache(F.changerNote) end }),
            F.bouton(f, { title = "À vérifier", size = petit, enabled = bind 'peutVerifierNote',
                tooltip = "Garder la proposition à revoir, sans rien poser", action = function() F.enTache(F.verifierNote) end }),
        },
    }
    if not sansNoter then
        carte[#carte + 1] = f:row { spacing = 4, Vues.boutonNoter(f, F, petit ~= nil), Vues.boutonSeance(f, F, petit ~= nil) }
    end
    return f:group_box(carte)
end

-- Fenêtres et disposition ----------------------------------------------------------------------

-- Publication et Consommation (le menu Fichier est réduit quand une fenêtre du module est devant).
function Vues.autresFenetres(f, F, petit)
    local taille = petit and 'small' or nil
    return f:row {
        spacing = 6,
        F.bouton(f, { title = "Publication…", size = taille, tooltip = "Publier des photos en fichiers, sans Claude ni quota",
            action = function() F.publication() end }),
        F.bouton(f, { title = "Consommation…", size = taille, tooltip = "Jetons de la semaine, budget, relevé du forfait",
            action = function() F.consommation() end }),
    }
end

-- Le menu Disposition : la fenêtre se ferme et se rouvre dans la disposition choisie
-- (`items` : Dispositions.items, tables neuves).
function Vues.disposition(f, F, largeur, items)
    return f:popup_menu { items = items, value = F.bind 'disposition', width = largeur,
        tooltip = "Disposition de la fenêtre Claude : elle se rouvre aussitôt, la demande tapée gardée" }
end

-- Les onglets : une rangée de boutons radio (clé `onglet`) au-dessus de variantes superposées.
function Vues.onglets(f, F, liste)
    local r = { spacing = 12 }
    for _, onglet in ipairs(liste) do
        r[#r + 1] = f:radio_button { title = onglet.titre, value = F.bind 'onglet', checked_value = onglet.valeur }
    end
    return f:row(r)
end

return Vues
