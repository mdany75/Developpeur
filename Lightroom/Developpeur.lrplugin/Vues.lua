-- Vues.lua : les pièces de la fenêtre Claude, assemblées par Dispositions.lua (la Conversation
-- claire, seule disposition, à l'allure de la fenêtre B). Chaque pièce rend une vue du SDK liée
-- aux propriétés de la fenêtre ; elle reçoit la fabrique `f`, la fenêtre `F` (Fenetre.lua :
-- couleurs, polices, images, `bind`, `egal`, `bouton`, `calque`, les actions) et ses dimensions.
-- Pas de `require 'Fenetre'` ni de `require 'Dispositions'` ici (Fenetre requiert ce fichier par
-- Dispositions) ni de couleur créée au chargement (la vérification des liens charge ce fichier
-- sans LrColor).
--
-- Tout bouton passe par F.bouton (push_button, ou square_button avec `carre`) : son clic valide
-- aussi le champ de demande, qui ne doit pas partir ensuite. Un clic sur une image passe par un
-- calque (F.calque : un texte vide de taille fixe posé dessus, constaté le 21 octobre 2026, C1),
-- qui annule de même l'envoi automatique. Ce qui varie passe par des propriétés liées et des
-- variantes superposées de même largeur (`place = 'overlapping'`) : une fenêtre ouverte ne change
-- pas de structure. Seule une vue simple se masque (`visible` sur une rangée, une colonne ou une
-- boîte reste sans effet, constaté), et toujours par une condition de F (F.egal, F.non, F.si,
-- F.condition) : Vues.masquable la combine avec celle d'un onglet. Les fonds et les filets sont
-- des aplats (Vues.aplat) : `background_color` est sans effet sur un conteneur (constaté, A5).

local Consignes = require 'Consignes'

local Vues = {}

-- Briques ---------------------------------------------------------------------------------------

-- Un aplat : un f:picture sans image, à background_color, de la taille donnée (constaté le
-- 21 octobre 2026, A4 : blanc, sans cadre). Sert aux fonds des colonnes et aux filets de 1 point
-- (primary_line_color d'un séparateur est sans effet, A6).
function Vues.aplat(f, largeur, hauteur, couleur)
    return f:picture { width = largeur, height = hauteur, background_color = couleur }
end

-- Une image de la fenêtre (Dispositions.IMAGES), dans le jeu de l'apparence (F.image), à sa taille
-- en points ; `args` (facultatif) : visible, place_vertical, place_horizontal. Jamais de mouse_down
-- (sans effet, constaté C1) : un calque par-dessus.
function Vues.image(f, F, nom, args)
    local t = F.tailleImage(nom)
    local vue = { value = F.image(nom), width = t.largeur, height = t.hauteur }
    for cle, valeur in pairs(args or {}) do
        vue[cle] = valeur
    end
    return f:picture(vue)
end

-- Un élément de la maquette dont la fonction n'existe pas encore (décision de Dany) : posé,
-- grisé, sans action, avec l'infobulle « À venir ». Un carré (square_button), comme les autres
-- boutons blancs de la maquette.
function Vues.inactif(f, F, args)
    local vue = {}
    for cle, valeur in pairs(args or {}) do
        vue[cle] = valeur
    end
    vue.carre = true
    vue.enabled = false
    vue.tooltip = F.A_VENIR
    vue.action = function() end
    return F.bouton(f, vue)
end

-- Un bouton bleu en image (constaté le 21 octobre 2026 : « Bouton bleu en image », clic reçu par
-- son calque) : l'image normale, enfoncée ou inactive en variantes superposées, le titre blanc
-- centré par-dessus (un autre, éteint, quand il est inactif : `titreInactif` de la palette), puis
-- le calque qui reçoit le clic. `args` : nom (sa clé d'enfoncement, `bleuEnfonce<nom>`), titre
-- (texte ou liaison), cle (sa clé d'état : le calque ne fait rien quand elle est fausse, un calque
-- n'a pas d'enabled), action, infobulle, visible (une condition de F, facultative : tout le
-- bouton). L'image enfoncée se montre 0,15 s au clic (F.enfoncer) ; pas de survol, pas de focus.
function Vues.boutonBleu(f, F, args)
    local C, P = F.COULEURS, F.POLICES
    local t = F.tailleImage('bouton-bleu')
    local cle, enfonce = args.cle, 'bleuEnfonce' .. args.nom
    F.preparerCle(enfonce, false)
    local function avec(condition)
        if args.visible then
            return F.et(condition, args.visible)
        end
        return condition
    end
    local actif, inactif = F.si(cle), F.non(cle)
    return f:column {
        place = 'overlapping',
        width = t.largeur,
        height = t.hauteur,
        Vues.image(f, F, 'bouton-bleu', { visible = avec(F.et(actif, F.non(enfonce))) }),
        Vues.image(f, F, 'bouton-bleu-presse', { visible = avec(F.et(actif, F.si(enfonce))) }),
        Vues.image(f, F, 'bouton-bleu-inactif', { visible = avec(inactif) }),
        f:static_text { title = args.titre, font = P.systeme13, text_color = C.blanc, alignment = 'center', width = t.largeur,
            place_vertical = 0.5, visible = avec(actif) },
        f:static_text { title = args.titre, font = P.systeme13, text_color = C.titreInactif, alignment = 'center', width = t.largeur,
            place_vertical = 0.5, visible = avec(inactif) },
        F.calque(f, {
            width = t.largeur,
            height = t.hauteur,
            tooltip = args.infobulle,
            visible = args.visible,
            mouse_down = function()
                local p = F.p
                if not (p and p[cle]) then
                    return
                end
                F.enfoncer(enfonce)
                args.action()
            end,
        }),
    }
end

-- Fil -----------------------------------------------------------------------------------------

-- Une ligne du fil (fenêtre B, lot B4), haute de D.hauteurLigne, à la largeur utile du centre :
-- - la colonne auteur (D.auteur), en variantes superposées selon `a..i` : « Vous » (gras 12, bleu),
--   « Claude » (gras 12), l'heure (`h..i`, petit gris) ou rien ; sans clic ;
-- - un écart, puis la colonne du texte (D.texteFil, F.largeurTexte()), en superposition : l'icône
--   (`i..i`) au bord gauche ; une variante de texte par style (F.STYLES : police, couleur, retrait,
--   selon le genre `g..i`), celles des genres qui portent une icône à F.STYLES[…].retrait du bord ;
--   la ligne d'un appel d'outil est un texte riche (le nom en <EM>, Menlo), et les autres variantes
--   reçoivent le texte sans balise (une variante cachée ne voit jamais une balise qu'elle ne sait
--   pas montrer) ;
--   la rangée d'actions selon `x..i` (« ☆ Voir la note » ; « ＋ Garder la demande » à droite après
--   une retouche : Fil.lireActions), en variantes superposées, des carrés small dans des rangées
--   poussées à droite par margin_left (constaté le 21 octobre 2026, D6 : ils répondent, et la
--   rangée ne prend pas les clics du texte).
-- Un clic sur le texte est réparti par Fenetre.cliquerLigne (une image ou une étape dans l'onglet
-- Aperçu, sinon le détail d'un outil : « Pourquoi ? », au bout d'une étape, est retiré au
-- correctif 1.3.6, décision de Dany du 25 octobre 2026) ; les boutons appellent F.voirNote et
-- F.garderDemande, qui relisent la ligne.
function Vues.ligneFil(f, F, i, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local largeur = D.texteFil
    local auteur = f:column {
        place = 'overlapping',
        width = D.auteur,
        f:static_text { title = "Vous", font = P.gras12, text_color = C.bleu, width = D.auteur, visible = F.egal('a' .. i, 'dany') },
        f:static_text { title = "Claude", font = P.gras12, text_color = C.texte, width = D.auteur, visible = F.egal('a' .. i, 'claude') },
        f:static_text { title = bind('h' .. i), font = P.petit, text_color = C.gris, width = D.auteur, truncation = 'tail',
            visible = F.egal('a' .. i, 'heure') },
    }
    local icones = { place = 'overlapping' }
    for _, ic in ipairs(F.ICONES) do
        icones[#icones + 1] = f:static_text { title = ic.glyphe, font = P.texte, text_color = C[ic.couleur],
            visible = F.egal('i' .. i, ic.cle) }
    end
    local texte = { place = 'overlapping', width = largeur, f:column(icones) }
    local enRetrait = {}
    for _, st in ipairs(F.STYLES) do
        local genres = st.genres
        local vue = f:static_text {
            title = st.emphase and bind('t' .. i) or bind { key = 't' .. i, transform = function(v) return F.sansBalises(v) end },
            width = largeur - st.retrait,
            font = P[st.police],
            text_color = C[st.couleur],
            emphasis_font = st.emphase and P[st.emphase] or nil,
            emphasis_color = st.emphase and C[st.couleurEmphase] or nil,
            truncation = 'tail',
            visible = F.condition('g' .. i, function(v) return genres[v] == true end),
            mouse_down = function() F.cliquerLigne(i) end,
        }
        if st.retrait > 0 then
            enRetrait[st.retrait] = enRetrait[st.retrait] or { place = 'overlapping', margin_left = st.retrait }
            local colonne = enRetrait[st.retrait]
            colonne[#colonne + 1] = vue
        else
            texte[#texte + 1] = vue
        end
    end
    for _, colonne in pairs(enRetrait) do
        texte[#texte + 1] = f:column(colonne)
    end
    -- Les actions d'une notation : « ☆ Voir la note » (onglet Note), à la place des icônes de la
    -- maquette (un glyphe dans le titre : une icône d'image_name chevaucherait le titre, constaté
    -- B3). Après une retouche, « ＋ Garder la demande » (Mes demandes) au bout de la même ligne, à
    -- droite : une rangée poussée par margin_left (D6). (« Leçon de la photo » est retiré avec la
    -- leçon au correctif 1.3.6, comme « Pourquoi ? » au bout d'une étape.)
    local actions = 'x' .. i
    texte[#texte + 1] = f:column {
        place = 'overlapping',
        f:row {
            F.bouton(f, { carre = true, size = 'small', title = "☆ Voir la note", font = P.petit, width = D.voirNote,
                tooltip = "La note proposée de la photo active, dans l'onglet Note",
                visible = F.condition(actions, function(v) return F.lireActions(v) == 'note' end),
                action = function() F.voirNote(i) end }),
        },
        f:row {
            margin_left = largeur - D.garderDemande,
            F.bouton(f, { carre = true, size = 'small', title = "＋ Garder la demande", font = P.petit, width = D.garderDemande,
                tooltip = "Garder la demande de Claude dans Mes demandes (à droite de Style), pour la refaire sur une autre photo",
                visible = F.condition(actions, function(v) return select(2, F.lireActions(v)) end),
                action = function() F.garderDemande(i) end }),
        },
    }
    return f:row {
        spacing = 0,
        height = D.hauteurLigne,
        auteur,
        f:spacer { width = D.ecartAuteur },
        f:column(texte),
    }
end

-- La grille du fil : D.lignes lignes de D.hauteurLigne, à la largeur utile du centre (D.fil : la
-- colonne auteur, son écart et le texte, F.largeurTexte()), dans sa hauteur réservée (D.grille).
function Vues.grille(f, F, D)
    local grille = { spacing = 0, height = D.grille }
    for i = 1, D.lignes do
        grille[#grille + 1] = Vues.ligneFil(f, F, i, D)
    end
    return f:column(grille)
end

-- La barre sous le fil : ▲ ▼ (carrés à icône seule) et Fin, la position dans le fil, et à droite
-- ce que fait Claude (en orange), sinon le forfait, aligné sur la marge de droite (les largeurs de
-- la rangée font D.fil, Dispositions.dimensions).
function Vues.defilement(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local pas = math.floor(D.lignes * 0.8)
    local activite = f:column {
        place = 'overlapping',
        place_vertical = 0.5,
        f:static_text { title = bind 'activite', font = P.systeme11, text_color = C.orange, alignment = 'right', width = D.activite,
            truncation = 'tail', visible = F.si 'travaille' },
        f:static_text { title = bind 'forfait', font = P.systeme11, text_color = C.gris, alignment = 'right', width = D.activite,
            truncation = 'tail', visible = F.non 'travaille' },
    }
    return f:row {
        height = D.barre - D.filet,
        margin_left = D.margeCentre,
        spacing = 0,
        F.bouton(f, { carre = true, icone = 'chevron-haut', bezel = 22, width = D.fleche, place_vertical = 0.5,
            tooltip = "Remonter dans le fil", enabled = bind 'peutMonter', action = function() F.defiler(pas) end }),
        f:spacer { width = 4 },
        F.bouton(f, { carre = true, icone = 'chevron-bas', bezel = 22, width = D.fleche, place_vertical = 0.5,
            tooltip = "Redescendre", enabled = bind 'peutDescendre', action = function() F.defiler(-pas) end }),
        f:spacer { width = 4 },
        F.bouton(f, { carre = true, title = "Fin", bezel = 22, width = D.fin, font = P.systeme11, place_vertical = 0.5,
            tooltip = "Aller au dernier message", enabled = bind 'peutDescendre', action = function() F.defiler('fin') end }),
        f:spacer { width = 8 },
        f:static_text { title = bind 'positionFil', font = P.systeme11, text_color = C.gris, width = D.position, truncation = 'tail',
            place_vertical = 0.5 },
        f:spacer { fill_horizontal = 1 },
        activite,
    }
end

-- Voyants --------------------------------------------------------------------------------------

-- Un voyant : sa pastille (une image par état, superposées, F.PASTILLES) et son texte, à `largeur`.
-- `v` : etat et texte (les clés liées), action (le mouse_down du texte, facultatif : il annule
-- l'envoi automatique lui-même), infobulle, largeur, police et couleur du texte.
function Vues.voyant(f, F, v)
    local pastilles = { place = 'overlapping', width = 8, height = 8, place_vertical = 0.5 }
    for _, etat in ipairs(F.ETATS_VOYANT) do
        pastilles[#pastilles + 1] = Vues.image(f, F, F.PASTILLES[etat], { visible = F.egal(v.etat, etat) })
    end
    return f:row {
        spacing = 6,
        f:column(pastilles),
        f:static_text { title = F.bind(v.texte), font = v.police, text_color = v.couleur, mouse_down = v.action, tooltip = v.infobulle,
            width = v.largeur, truncation = 'tail' },
    }
end

-- Les deux voyants de l'en-tête : Claude Code (sans clic) et la liaison (un clic la démarre), en
-- tête du centre ; dans leur rangée, au bout à droite, le bouton Suivi (Vues.boutonSuivi). Le
-- voyant Écran (de la 1.2) est retiré au correctif 1.3.6 (décision de Dany du 25 octobre 2026 :
-- plus rien sur l'étalonnage de l'écran).
function Vues.voyantClaude(f, F, D)
    return Vues.voyant(f, F, { etat = 'etatClaude', texte = 'texteClaude', largeur = D.voyantClaude, police = F.POLICES.systeme12,
        couleur = F.COULEURS.texte, infobulle = "Claude Code, avec votre forfait claude.ai (pas de clé d'API)" })
end

-- Son infobulle, liée (`infobulleLightroom`, Fenetre.infobulleLightroom) : la liaison, les versions
-- du module et du connecteur (en bas du volet jusqu'au correctif 1.3.6) et le mode de la liaison
-- (« Appliquer » ou « Proposer d'abord », la rangée Mode étant retirée).
function Vues.voyantLightroom(f, F, D)
    return Vues.voyant(f, F, { etat = 'etatLightroom', texte = 'texteLightroom', largeur = D.voyantLightroom,
        police = F.POLICES.systeme12, couleur = F.COULEURS.texte, infobulle = F.bind 'infobulleLightroom',
        action = function()
            F.annulerEnvoiAuto()
            F.demarrerLiaison()
        end })
end

-- Le bouton Suivi, en haut à droite (décision de Dany du 25 octobre 2026, correctif 1.3.6 : au bout
-- de la rangée des voyants, après la photo active, sous « Repartir à neuf ») : le carnet de
-- progrès dans sa fenêtre à part (F.ouvrirSuivi, FenetreSuivi.lua), comme Publication et
-- Consommation, à la place de l'onglet Suivi. Un carré small comme les boutons d'actions du fil
-- (bezel de 15, D6), son titre en petit ; toujours actif : le carnet se lit sans Claude.
function Vues.boutonSuivi(f, F, D)
    return F.bouton(f, { carre = true, size = 'small', title = "Suivi", font = F.POLICES.petit, width = D.boutonSuivi,
        place_vertical = 0.5, tooltip = "Le carnet de progrès (ce que Claude a constaté de vos prises de vue), dans une fenêtre à part",
        action = function() F.ouvrirSuivi() end })
end

-- Le bandeau, dans la place du menu Modèle de la maquette (D.bandeau, retiré : décision de Dany) :
-- deux lignes en petit (F.LIGNES_BANDEAU), coupées d'après la chasse mesurée (F.texteBandeau, « … »
-- au bout de la seconde s'il le faut), à la hauteur des boutons de la rangée. Un message (orange ;
-- son infobulle le donne en entier), sinon l'aide d'un voyant rouge (un clic l'affiche en entier),
-- sinon les photos jointes (un clic les retire ; « cliquer pour retirer » reste au bout, les noms
-- coupés avant), sinon rien (état 'vide' : le rappel du style est
-- retiré, demandé par Dany le 20 octobre 2026).
function Vues.bandeau(f, F, largeur)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local function coupe(cle, suite)
        return bind { key = cle, transform = function(v) return F.texteBandeau(tostring(v or ''), largeur, suite) end }
    end
    return f:column {
        place = 'overlapping',
        place_vertical = 0.5,
        f:static_text { title = coupe('jointes', "  ·  cliquer pour retirer"), font = P.petit, text_color = C.gris, width = largeur,
            height_in_lines = F.LIGNES_BANDEAU, visible = F.egal('bandeau', 'jointes'), tooltip = "Cliquer pour retirer les photos jointes",
            mouse_down = function()
                F.annulerEnvoiAuto()
                F.retirerJointes()
            end },
        f:static_text { title = coupe('message'), font = P.petit, text_color = C.orange, width = largeur, height_in_lines = F.LIGNES_BANDEAU,
            visible = F.egal('bandeau', 'message'), tooltip = bind 'message' },
        f:static_text { title = coupe('aide'), font = P.petit, text_color = C.rouge, width = largeur, height_in_lines = F.LIGNES_BANDEAU,
            visible = F.egal('bandeau', 'aide'), tooltip = "Cliquer pour lire l'aide en entier",
            mouse_down = function()
                F.annulerEnvoiAuto()
                F.enTache(F.montrerAide)
            end },
    }
end

-- En-tête --------------------------------------------------------------------------------------

-- L'en-tête du centre : le titre de la conversation (gras 16, sans ✎ : celui que Claude donne ;
-- Renommer… est retiré avec le volet au correctif 1.3.6), et à sa droite, dans la place du Mode (ses
-- trois radios sont retirés au correctif 1.3.6 : la fenêtre suit la préférence `mode` du
-- Gestionnaire), « Repartir à neuf » (F.repartir : une conversation neuve pour la photo seule,
-- l'ancienne mise de côté ; grisé pendant que Claude travaille et sans photo seule) ; dessous, les
-- voyants Claude Code et Lightroom, la photo active (`infoPhoto`, texte riche : nom et sélection en
-- <EM>), puis le bouton Suivi (Vues.boutonSuivi) au bout de la rangée, en haut à droite, sous
-- « Repartir à neuf ».
function Vues.entete(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        height = D.entete,
        margin_left = D.margeCentre,
        margin_top = 12,
        spacing = 6,
        f:row {
            spacing = 0,
            f:static_text { title = bind 'titre', font = P.titre, text_color = C.texte, width = D.titre, truncation = 'tail',
                place_vertical = 0.5 },
            f:spacer { fill_horizontal = 1 },
            F.bouton(f, { carre = true, bezel = 22, title = "Repartir à neuf", font = P.systeme12, width = D.repartir,
                place_vertical = 0.5, enabled = bind 'peutRepartir',
                tooltip = "Une conversation neuve pour la photo choisie, avec son historique ; l'ancienne reste sur le disque, mise de côté",
                action = function() F.enTache(F.repartir) end }),
        },
        f:row {
            spacing = 0,
            Vues.voyantClaude(f, F, D),
            f:spacer { width = D.ecartVoyants },
            Vues.voyantLightroom(f, F, D),
            f:spacer { width = D.ecartVoyants },
            f:static_text { title = bind 'infoPhoto', font = P.systeme12, text_color = C.gris, emphasis_font = P.systeme12,
                emphasis_color = C.texte, alignment = 'right', width = D.info, truncation = 'middle' },
            f:spacer { width = D.ecartVoyants },
            Vues.boutonSuivi(f, F, D),
        },
    }
end

-- Saisie ---------------------------------------------------------------------------------------

-- Les invites en raccourcis (Consignes.invites, Composition comprise), en carrés de 24 points de
-- bezel (cadre de 26, D5), police 12. Ni « ★ Noter » ni séparateur (décision de Dany), et le menu
-- Style est passé sous le champ.
function Vues.invites(f, F, D)
    local rangee = { spacing = 6 }
    for _, invite in ipairs(Consignes.invites) do
        rangee[#rangee + 1] = F.bouton(f, {
            carre = true,
            bezel = 24,
            font = F.POLICES.systeme12,
            title = invite.titre,
            tooltip = invite.message,
            enabled = F.bind 'libre',
            action = function() F.envoyer(invite.message, invite.modele) end,
        })
    end
    return f:row(rangee)
end

-- Le menu Style seul (D.style de large) : joint à chaque demande, invites comprises. Le modèle et
-- l'effort se choisissent dans le Gestionnaire de modules externes (PluginInfoProvider.lua), pas
-- dans la fenêtre (décision de Dany).
function Vues.style(f, F, D)
    local styles = {}
    for _, st in ipairs(Consignes.styles) do
        styles[#styles + 1] = { title = st.title, value = st.value }
    end
    return f:popup_menu { items = styles, value = F.bind 'style', width = D.style, enabled = F.bind 'libre', place_vertical = 0.5,
        tooltip = "Style de retouche joint à chaque demande, invites comprises (Standard : rien d'ajouté)" }
end

-- Le menu Mes demandes (D.mesDemandes de large, demandé par Dany le 22 octobre 2026), à droite du
-- menu Style : les demandes personnelles de Dany (« Nom — description », `mesDemandesItems`, refaits
-- par Fenetre.rafraichirMesDemandes), un séparateur, puis Ajouter…, Renommer… et Supprimer… ; son
-- titre « Mes demandes » quand rien n'est choisi. Choisir une demande la met dans le champ, sans
-- l'envoyer (Fenetre.choisirMesDemandes) ; le menu revient à son titre. Sa valeur passe par
-- F.lierRadio (faite pour les radios du Mode, retirés au correctif 1.3.6) : un choix, même du
-- titre, annule l'envoi de la demande que ce clic aurait validée. Grisé pendant que Claude
-- travaille.
function Vues.mesDemandes(f, F, D)
    return f:popup_menu { items = F.bind 'mesDemandesItems', value = F.lierRadio 'mesDemandes', width = D.mesDemandes,
        enabled = F.bind 'libre', place_vertical = 0.5,
        tooltip = "Mes demandes : une demande choisie remplit le champ (Retour l'envoie) ; Ajouter…, Renommer… et Supprimer… en bas du menu" }
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

-- Envoyer, un bouton bleu en image, et Arrêter superposé (montré pendant que Claude travaille) ;
-- les deux appellent F.boutonPrincipal. Aucun bouton par défaut dans la fenêtre (décision de
-- repli du lot B0 : Retour dans « Rechercher », le champ du volet d'alors, déclencherait Envoyer,
-- constaté D1) : Retour dans le champ de demande passe par son observateur et l'envoi automatique
-- (Fenetre.saisieValidee).
function Vues.envoi(f, F, D)
    return f:column {
        place = 'overlapping',
        width = D.envoyer,
        place_vertical = 0.5,
        Vues.boutonBleu(f, F, { nom = 'Envoyer', titre = "Envoyer", cle = 'libre', visible = F.non 'travaille',
            infobulle = "Envoyer la demande à Claude (Retour dans le champ aussi)", action = function() F.boutonPrincipal() end }),
        F.bouton(f, { carre = true, bezel = 24, title = "Arrêter", font = F.POLICES.systeme13, width = D.envoyer, visible = F.si 'travaille',
            tooltip = "Arrêter Claude", action = function() F.boutonPrincipal() end }),
    }
end

-- La zone de saisie (marges 12/20/14) : les invites, le champ de demande sur deux lignes
-- (`immediate = false` : Retour le valide, Fenetre.saisieValidee ; sa valeur passe par
-- F.lierSaisie, pour une demande mise par Mes demandes), puis 📎 et 📋 (carrés à icône seule),
-- « Style » et son menu, Mes demandes, le bandeau, Envoyer.
function Vues.saisie(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        margin_left = D.margeCentre,
        margin_top = 12,
        spacing = 8,
        Vues.invites(f, F, D),
        f:edit_field { value = F.lierSaisie(), immediate = false, height_in_lines = 2, width = D.champ, enabled = bind 'libre',
            placeholder_string = "Demander à Claude… (par exemple : « Retouche la photo active, rendu naturel »)",
            tooltip = "Retour envoie la demande. Dictée : touche 🌐 deux fois." },
        f:row {
            spacing = 0,
            F.bouton(f, { carre = true, icone = 'trombone', bezel = 24, width = D.joindre, place_vertical = 0.5,
                tooltip = "Joindre une photo du disque à la demande", enabled = bind 'libre', action = function() F.enTache(F.joindre) end }),
            f:spacer { width = 4 },
            F.bouton(f, { carre = true, icone = 'presse-papiers', bezel = 24, width = D.joindre, place_vertical = 0.5,
                tooltip = "Coller l'image du presse-papiers (capture d'écran, image copiée, photo copiée dans le Finder)",
                enabled = bind 'libre', action = function() F.enTache(F.coller) end }),
            f:spacer { width = 10 },
            f:static_text { title = "Style", font = P.systeme12, text_color = C.grisEntete, width = D.etiquetteStyle, place_vertical = 0.5 },
            f:spacer { width = 6 },
            Vues.style(f, F, D),
            f:spacer { width = 8 },
            Vues.mesDemandes(f, F, D),
            f:spacer { width = 8 },
            Vues.bandeau(f, F, D.bandeau),
            f:spacer { width = 8 },
            Vues.envoi(f, F, D),
        },
    }
end

-- Colonne droite ---------------------------------------------------------------------------------

-- Les segments Focus | Note | Aperçu | Proposition (D.onglets, Dispositions.ONGLETS), centrés en
-- tête du panneau : chacun son image et sa variante bleue (-actif, montrée quand `onglet` vaut sa
-- valeur), sous un calque dont le clic choisit l'onglet (F.choisirSegment : un vrai clic, son
-- crochet suit). Ni survol, ni focus.
function Vues.segments(f, F, D)
    local r = { spacing = 0, margin_left = D.margeSegments, height = D.hauteurSegments }
    for _, onglet in ipairs(D.onglets) do
        local t = F.tailleImage(onglet.image)
        local valeur = onglet.valeur
        r[#r + 1] = f:column {
            place = 'overlapping',
            width = t.largeur,
            height = t.hauteur,
            Vues.image(f, F, onglet.image, { visible = F.condition('onglet', function(v) return v ~= valeur end) }),
            Vues.image(f, F, onglet.image .. '-actif', { visible = F.egal('onglet', valeur) }),
            F.calque(f, { width = t.largeur, height = t.hauteur, tooltip = onglet.titre, mouse_down = function() F.choisirSegment(valeur) end }),
        }
    end
    return f:row(r)
end

-- L'aperçu commun aux quatre onglets : ce que Claude regarde, ou la photo active, dans un cadre 3:2
-- fixe de D.apercu × D.apercuHauteur (une réduction en 2x centrée sur le fond, Images.vignette,
-- ou l'image « aucun aperçu »), au milieu d'une bande du fond de l'aperçu à la largeur du panneau.
function Vues.apercu(f, F, D)
    return f:column {
        place = 'overlapping',
        width = D.interieur,
        height = D.apercuHauteur,
        Vues.aplat(f, D.interieur, D.apercuHauteur, F.COULEURS.fondApercu),
        f:row {
            margin_left = math.floor((D.interieur - D.apercu) / 2),
            f:picture { value = F.bind 'imageApercu', width = D.apercu, height = D.apercuHauteur },
        },
    }
end

-- Sous l'aperçu, dans les quatre onglets : ◀ légende ▶ (les images de la conversation et la photo
-- active, Fenetre.changerImage), puis « ⤢ Agrandir » à droite. La légende est un texte riche (le
-- nom de la photo active en <EM>), à emphase de même taille que le texte (constaté D4 : une
-- emphase plus grande couperait la ligne).
function Vues.navigationApercu(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:row {
        spacing = 0,
        F.bouton(f, { carre = true, title = "◀", bezel = 22, width = D.fleche, tooltip = "Image précédente", enabled = bind 'peutPrecedente',
            action = function() F.changerImage(-1) end }),
        f:spacer { width = 4 },
        f:static_text { title = bind 'legendeApercu', font = P.systeme12, text_color = C.gris, emphasis_font = P.systeme12,
            emphasis_color = C.texte, alignment = 'center', width = D.legende, truncation = 'middle', place_vertical = 0.5 },
        f:spacer { width = 4 },
        F.bouton(f, { carre = true, title = "▶", bezel = 22, width = D.fleche, tooltip = "Image suivante", enabled = bind 'peutSuivante',
            action = function() F.changerImage(1) end }),
        f:spacer { width = 8 },
        F.bouton(f, { carre = true, title = "⤢ Agrandir", bezel = 22, width = D.agrandir, font = P.systeme11, enabled = bind 'aImage',
            tooltip = "L'aperçu en grand (avant et après pour une étape)", action = function() F.agrandir() end }),
    }
end

-- Une carte de la colonne droite telle que la carte Note (demandé par Dany le 21 octobre 2026) :
-- l'image de la carte et son contenu à 13 du bord et 12 du haut, puis, sous elle, 12 et sa rangée
-- de boutons, ▲ ▼ à gauche (Vues.fleches) et les boutons à droite. La carte descend ainsi jusqu'à
-- sa rangée, au bas du panneau, comme celle de la carte Note.
local function carteEtRangee(f, F, largeur, D, image, contenu, fleches, boutons)
    local t = F.tailleImage(image)
    contenu.margin_left = D.margeCarte
    contenu.margin_top = 12
    contenu.spacing = 6
    local rangee = { spacing = 0, Vues.fleches(f, F, fleches), f:spacer { fill_horizontal = 1 } }
    for _, bouton in ipairs(boutons) do
        rangee[#rangee + 1] = bouton
    end
    return f:column {
        spacing = 0,
        width = largeur,
        f:column {
            place = 'overlapping',
            width = largeur,
            height = t.hauteur,
            Vues.image(f, F, image),
            f:column(contenu),
        },
        f:spacer { height = 12 },
        f:row(rangee),
    }
end

-- La proposition de Claude (fenêtre B, lot B5), sur son image (carte-proposition, à la largeur
-- intérieure du panneau) : « Proposition de Claude » en gras 12, ce qu'il compte changer page par
-- page (`propositionTexte`, D.propLignes lignes en 12, coupées par Fenetre.montrerPage ; la ligne
-- « Cadre : … » de Composition lue comprise) ; sous la carte, ▲ ▼, puis Obtenir, Refuser et
-- Ajuster… en carrés, et Accepter, un bouton bleu en image (Vues.boutonBleu : son calque ne fait
-- rien quand aucune proposition n'attend, `enAttente`). Obtenir (décision de Dany du 25 octobre
-- 2026, à la place de la proposition préparée à l'ouverture) demande une proposition pour la photo
-- seule active (Fenetre.obtenir) : actif quand Claude est libre, une seule photo choisie et aucune
-- proposition en attente (`peutObtenir`). Refuser, Ajuster… et Accepter sont actifs quand une
-- proposition attend et que Claude ne travaille pas. (« Je le fais » et l'état de son exercice
-- sont retirés au correctif 1.3.6.)
function Vues.proposition(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return carteEtRangee(f, F, largeur, D, 'carte-proposition', {
        f:static_text { title = "Proposition de Claude", font = P.gras12, text_color = C.texte, width = D.largeurProposition },
        f:static_text { title = bind 'propositionTexte', font = P.texte12, text_color = C.texte, width = D.largeurProposition,
            height_in_lines = D.propLignes },
    }, 'proposition', {
        F.bouton(f, { carre = true, bezel = 26, title = "Obtenir", font = P.systeme13, width = D.obtenir, enabled = bind 'peutObtenir',
            tooltip = "Demander à Claude une proposition de retouche de la photo active, sans rien appliquer",
            action = function() F.enTache(F.obtenir) end }),
        f:spacer { width = 8 },
        F.bouton(f, { carre = true, bezel = 26, title = "Refuser", font = P.systeme13, width = D.refuser, enabled = bind 'enAttente',
            tooltip = "Refuser la proposition : rien ne change", action = function() F.repondreProposition(false) end }),
        f:spacer { width = 8 },
        F.bouton(f, { carre = true, bezel = 26, title = "Ajuster…", font = P.systeme13, width = D.ajuster, enabled = bind 'enAttente',
            tooltip = "Dire à Claude ce qu'il faut changer avant d'appliquer", action = function() F.enTache(F.ajuster) end }),
        f:spacer { width = 8 },
        Vues.boutonBleu(f, F, { nom = 'AccepterProposition', titre = "Accepter", cle = 'enAttente',
            infobulle = "Appliquer la proposition : la photo ne change qu'à ce clic",
            action = function() F.repondreProposition(true) end }),
    })
end

-- La carte de l'étape (1.3, l'ancienne carte « Pourquoi ? ») dans l'onglet Aperçu, sur son image
-- (carte-etape, fenêtre B, lot B5) : son titre en gras 12 (« Étape 2 sur 4 · passe 1 : balance » ;
-- « Pourquoi ? » sans étape, Fenetre.TITRE_ETAPE), son sous-titre en gris (fichier, outil,
-- « annulée ensuite »), sa raison et ses réglages changés page par page (`etapeTexte`,
-- D.etapeLignes lignes en 12, coupées par Fenetre.montrerPage) ; sous la carte, ▲ ▼, puis ◀ ▶
-- (étape précédente ou suivante de la même photo), Voir l'avant / Voir l'après (titre lié
-- `titreBascule` : un seul bouton) et Détail… (l'appel de l'outil et sa réponse) en carrés.
function Vues.etape(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return carteEtRangee(f, F, largeur, D, 'carte-etape', {
        f:static_text { title = bind 'etapeTitre', font = P.gras12, text_color = C.texte, width = D.largeurEtape, truncation = 'tail' },
        f:static_text { title = bind 'etapeSousTitre', font = P.petit, text_color = C.gris, width = D.largeurEtape,
            truncation = 'middle' },
        f:static_text { title = bind 'etapeTexte', font = P.texte12, text_color = C.texte, width = D.largeurEtape,
            height_in_lines = D.etapeLignes },
    }, 'etape', {
        F.bouton(f, { carre = true, bezel = 26, title = "◀", font = P.systeme13, width = D.fleche, tooltip = "Étape précédente",
            enabled = bind 'etapePrecedente', action = function() F.etapeVoisine(-1) end }),
        f:spacer { width = 4 },
        F.bouton(f, { carre = true, bezel = 26, title = "▶", font = P.systeme13, width = D.fleche, tooltip = "Étape suivante",
            enabled = bind 'etapeSuivante', action = function() F.etapeVoisine(1) end }),
        f:spacer { width = 8 },
        F.bouton(f, { carre = true, bezel = 26, title = bind 'titreBascule', font = P.systeme13, width = D.bascule,
            tooltip = "Montrer l'avant ou l'après de cette étape dans l'aperçu", enabled = bind 'etapeAImages',
            action = function() F.basculerEtape() end }),
        f:spacer { width = 8 },
        F.bouton(f, { carre = true, bezel = 26, title = "Détail…", font = P.systeme13, width = D.detail,
            tooltip = "Ce que Claude a demandé au connecteur pour cette étape, puis sa réponse", enabled = bind 'etapeADetail',
            action = function() F.enTache(F.detailEtape) end }),
    })
end

-- La carte de l'onglet Focus (demandé par Dany le 22 octobre 2026), sur son image (carte-focus, à la
-- largeur intérieure du panneau) : son titre en gras 12 (`focusTitre`, « Focus · DSCF2402.RAF »),
-- puis les trois blocs Image, Prise de vue et Mise au point page par page (`focusTexte`,
-- D.focusLignes lignes en 12, coupées par Fenetre.montrerPage : le titre de chaque bloc en <EM>,
-- gras de même taille, Fil.texteFocus) ; sous la carte, ▲ ▼ seulement (Fenetre.defilerTexte('focus')).
-- L'aperçu de l'onglet (la photo active et ses cadres de mise au point) est celui du panneau,
-- rempli par Fenetre.apercuOnglet.focus.
function Vues.focus(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return carteEtRangee(f, F, largeur, D, 'carte-focus', {
        f:static_text { title = bind 'focusTitre', font = P.gras12, text_color = C.texte, width = D.largeurFocus,
            truncation = 'middle' },
        f:static_text { title = bind 'focusTexte', font = P.texte12, text_color = C.texte, emphasis_font = P.gras12,
            emphasis_color = C.texte, width = D.largeurFocus, height_in_lines = D.focusLignes },
    }, 'focus', {})
end

-- (La carte de l'onglet Suivi, Vues.suivi, est retirée au correctif 1.3.6 : le carnet de progrès a
-- sa fenêtre à part, FenetreSuivi.lua, ouverte par le bouton Suivi de l'en-tête.)

-- Note -------------------------------------------------------------------------------------------
-- La carte Note de la photo active (fenêtre B, lot B5 : la maquette « B · Conversation claire »,
-- onglet Note). Claude note d'abord chaque photo qu'il traite, et sa note arrive « à vérifier » :
-- Dany l'accepte, la laisse ou la change (pas de bouton Noter ni Évaluer : décision de Dany). Ses
-- étoiles et ses drapeaux écrivent dans le catalogue sans Claude ni quota (Fenetre.poserEtoile,
-- Fenetre.poserDrapeau). Claude note de 0 à 5 ★ ; les coups de cœur de Dany sont un libellé de
-- couleur qu'il pose lui-même (correctif 1.3.2). Plus de rangée « Passes : » ni de ligne du plafond
-- (demandé par Dany le 22 octobre 2026) : la grille des critères prend leur place. Les couleurs
-- d'état sont des clés de la palette (Fenetre.COULEURS_NOTE, Fenetre.TEINTES_NOTE).

-- Une étiquette de la grille de la carte (« Votre note : », « Drapeau : »), alignée à droite, en
-- gris 12.
local function etiquetteNote(f, F, D, titre)
    return f:static_text { title = titre, font = F.POLICES.systeme12, text_color = F.COULEURS.gris, alignment = 'right',
        width = D.etiquetteNote, place_vertical = 0.5 }
end

-- « Votre note : » : cinq étoiles (etoile24 pleine ou vide selon `noteCatalogue`, la note posée
-- dans Lightroom), chacune sous un calque de D.etoile (constaté le 21 octobre 2026, C4 : le clic
-- sur la 3e pose 3 ★) qui appelle F.poserEtoile(k) ; le calque n'a pas d'enabled, F.poserEtoile
-- refuse pendant que Claude travaille ou qu'une note s'écrit.
function Vues.etoilesNote(f, F, D)
    local rangee = { spacing = D.ecartEtoiles }
    local marge = math.floor((D.etoile - F.tailleImage('etoile24-vide').largeur) / 2)
    for k = 1, 5 do
        rangee[#rangee + 1] = f:column {
            place = 'overlapping',
            width = D.etoile,
            height = D.etoile,
            f:column { margin_left = marge, margin_top = marge,
                Vues.image(f, F, 'etoile24-vide', { visible = F.condition('noteCatalogue', function(v) return (tonumber(v) or 0) < k end) }) },
            f:column { margin_left = marge, margin_top = marge,
                Vues.image(f, F, 'etoile24-pleine', { visible = F.condition('noteCatalogue', function(v) return (tonumber(v) or 0) >= k end) }) },
            F.calque(f, { width = D.etoile, height = D.etoile,
                tooltip = "Poser " .. k .. " ★ dans Lightroom ; sur la note posée, la retirer",
                mouse_down = function() F.poserEtoile(k) end }),
        }
    end
    return f:row(rangee)
end

-- « Claude propose » : cinq petites étoiles (etoile12) d'après `noteClaude` (0 à 5), « rejeter »
-- pour un rejet, « rien pour l'instant » sans proposition ; à droite, l'ordre des critères.
function Vues.noteClaude(f, F, D)
    local C, P = F.COULEURS, F.POLICES
    local etoiles = { spacing = 1 }
    for k = 1, 5 do
        etoiles[#etoiles + 1] = f:column {
            place = 'overlapping',
            Vues.image(f, F, 'etoile12-pleine', { visible = F.condition('noteClaude', function(v) return type(v) == 'number' and v >= k end) }),
            Vues.image(f, F, 'etoile12-vide', { visible = F.condition('noteClaude', function(v) return type(v) == 'number' and v < k end) }),
        }
    end
    local largeur = 100
    local ordre = "critères du plus lourd au plus léger"
    return f:row {
        spacing = 0,
        height = D.ligneClaude,
        f:static_text { title = "Claude propose", font = P.gras12, text_color = C.texte, width = F.largeurLibelle("Claude propose", 'gras12'),
            place_vertical = 0.5 },
        f:spacer { width = 6 },
        f:column {
            place = 'overlapping',
            place_vertical = 0.5,
            f:row(etoiles),
            f:static_text { title = "rejeter", font = P.systeme12, text_color = C.rouge, width = largeur, visible = F.egal('noteClaude', 'rejet') },
            f:static_text { title = "rien pour l'instant", font = P.systeme11, text_color = C.gris, width = largeur,
                visible = F.egal('noteClaude', 'aucune') },
        },
        f:spacer { fill_horizontal = 1 },
        f:static_text { title = ordre, font = P.systeme11, text_color = C.gris, alignment = 'right', width = F.largeurLibelle(ordre, 'petit'),
            place_vertical = 0.5 },
    }
end

-- La ligne k de la grille des critères (D.ligneCritere de haut, à l'intérieur de la carte), en
-- variantes superposées selon `ng..k` (Fenetre.lignesCriteres, Fenetre.montrerPage) : 'plein' (le
-- texte sur toute la largeur), 'etat' (la première ligne, l'état en gras de la couleur de
-- `notationCouleur`, une variante par teinte), 'critere' (l'étiquette en gras, `ne..k`, puis le
-- texte, le verdict en gras), ou rien. Le texte (`nt..k`) est un texte riche (<EM> en gras 12, de
-- même taille, constaté D4) dans chaque variante.
function Vues.ligneCritere(f, F, D, k)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local genre, texte = 'ng' .. k, 'nt' .. k
    local function riche(largeur, couleur, visible)
        return f:static_text { title = bind(texte), font = P.texte12, text_color = C.texte, emphasis_font = P.gras12,
            emphasis_color = couleur, width = largeur, truncation = 'tail', visible = visible }
    end
    local vues = { place = 'overlapping', width = D.carte, height = D.ligneCritere }
    vues[#vues + 1] = riche(D.carte, C.texte, F.egal(genre, 'plein'))
    for _, teinte in ipairs(F.TEINTES_NOTE) do
        vues[#vues + 1] = riche(D.carte, C[teinte], F.et(F.egal(genre, 'etat'), F.egal('notationCouleur', teinte)))
    end
    vues[#vues + 1] = f:row {
        spacing = 0,
        f:static_text { title = bind('ne' .. k), font = P.gras12, text_color = C.texte, width = D.etiquetteCritere, truncation = 'tail',
            visible = F.egal(genre, 'critere') },
        f:spacer { width = D.ecartCritere },
        riche(D.texteCritere, C.texte, F.egal(genre, 'critere')),
    }
    return f:column(vues)
end

-- « Voir à 100 % » (décision de Dany du 21 octobre 2026), dans la rangée du bas de la carte Note
-- depuis que la ligne du plafond est retirée (correctif 1.3.2) : le zoom que Claude a pris pour
-- noter la photo, montré dans l'aperçu (F.voirZoom, sans Claude ni Lightroom ; Agrandir le montre
-- en grand) ; sans un tel zoom, le même bouton grisé, avec une infobulle qui dit pourquoi (deux
-- boutons superposés : une infobulle liée n'est pas constatée). Bezel de 26 et titre en 13, comme
-- les autres boutons de la rangée.
function Vues.voirZoom(f, F, D)
    local P = F.POLICES
    return f:column {
        place = 'overlapping',
        F.bouton(f, { carre = true, bezel = 26, title = "Voir à 100 %", font = P.systeme13, width = D.zoom, tooltip = F.INFOBULLE_ZOOM,
            visible = F.si 'peutVoirZoom', action = function() F.voirZoom() end }),
        F.bouton(f, { carre = true, bezel = 26, title = "Voir à 100 %", font = P.systeme13, width = D.zoom, tooltip = F.SANS_ZOOM,
            enabled = false, visible = F.non 'peutVoirZoom', action = function() end }),
    }
end

-- La carte des critères, sur son image (carte-note, à la largeur intérieure du panneau) : la grille
-- de D.criteres + 1 lignes (Vues.ligneCritere), lue page par page (▲ ▼ de la rangée du bas).
function Vues.carteCriteres(f, F, D)
    local t = F.tailleImage('carte-note')
    local lignes = { spacing = 0 }
    for k = 1, D.criteres + 1 do
        lignes[#lignes + 1] = Vues.ligneCritere(f, F, D, k)
    end
    return f:column {
        place = 'overlapping',
        width = D.interieur,
        height = t.hauteur,
        Vues.image(f, F, 'carte-note'),
        f:column {
            margin_left = D.margeCarte,
            margin_top = 12,
            spacing = 0,
            f:column(lignes),
        },
    }
end

-- La carte Note : la grille des étiquettes et des valeurs (« Votre note : » et la note posée,
-- `notePoseeTitre` et `notePoseeSous`, « Drapeau : » avec « ⚑ Retenir », « ⊗ Rejeter » et « ? À
-- vérifier », grisé : Vues.inactif) ; « Claude propose » ; la carte des critères ; puis ▲ ▼ et
-- « Voir à 100 % » (Vues.voirZoom) et, à droite, « Laisser à N ★ » (`titreLaisser` : la
-- proposition écartée, rien dans le catalogue), « Changer… » (de 0 à 5 ★ et le drapeau) et
-- « Accepter N ★ » (`titreAccepterNote`, jusqu'à 5 ★), un bouton bleu en image dont le calque ne
-- fait rien quand `peutAccepterNote` est faux. Plus de rangée « Passes : » ni de ligne du plafond
-- (correctif 1.3.2).
function Vues.notation(f, F, largeur, D)
    local bind, P = F.bind, F.POLICES
    return f:column {
        spacing = 0,
        width = largeur,
        f:row {
            spacing = 0,
            height = D.etoile,
            etiquetteNote(f, F, D, "Votre note :"),
            f:spacer { width = D.ecartEtiquette },
            Vues.etoilesNote(f, F, D),
            f:spacer { width = 12 },
            f:column {
                spacing = 0,
                place_vertical = 0.5,
                f:static_text { title = bind 'notePoseeTitre', font = P.gras12, text_color = F.COULEURS.texte, width = D.posee,
                    truncation = 'tail' },
                f:static_text { title = bind 'notePoseeSous', font = P.systeme11, text_color = F.COULEURS.gris, width = D.posee,
                    truncation = 'tail' },
            },
        },
        f:spacer { height = D.ecartGrille },
        f:row {
            spacing = 0,
            etiquetteNote(f, F, D, "Drapeau :"),
            f:spacer { width = D.ecartEtiquette },
            F.bouton(f, { carre = true, bezel = 24, title = "⚑ Retenir", font = P.systeme12, width = D.retenir, enabled = bind 'peutChangerNote',
                tooltip = "Drapeau Retenue dans Lightroom ; déjà retenue : retirer le drapeau",
                action = function() F.poserDrapeau('retenue') end }),
            f:spacer { width = 6 },
            F.bouton(f, { carre = true, bezel = 24, title = "⊗ Rejeter", font = P.systeme12, width = D.rejeter, enabled = bind 'peutChangerNote',
                tooltip = "Drapeau Rejeter dans Lightroom ; déjà rejetée : retirer le drapeau",
                action = function() F.poserDrapeau('rejetee') end }),
            f:spacer { width = 6 },
            Vues.inactif(f, F, { bezel = 24, title = "? À vérifier", font = P.systeme12, width = D.aVerifier }),
        },
        f:spacer { height = 10 },
        Vues.noteClaude(f, F, D),
        f:spacer { height = 6 },
        Vues.carteCriteres(f, F, D),
        f:spacer { height = 12 },
        f:row {
            spacing = 0,
            Vues.fleches(f, F, 'note'),
            f:spacer { width = 8 },
            Vues.voirZoom(f, F, D),
            f:spacer { fill_horizontal = 1 },
            F.bouton(f, { carre = true, bezel = 26, title = bind 'titreLaisser', font = P.systeme13, width = D.laisser,
                enabled = bind 'peutAccepterNote',
                tooltip = "Garder la note du catalogue et écarter la proposition de Claude (rien n'est écrit dans Lightroom)",
                action = function() F.laisserNote() end }),
            f:spacer { width = 8 },
            F.bouton(f, { carre = true, bezel = 26, title = "Changer…", font = P.systeme13, width = D.changer, enabled = bind 'peutChangerNote',
                tooltip = "Poser une autre note, de 0 à 5 ★, ou un drapeau", action = function() F.enTache(F.changerNote) end }),
            f:spacer { width = 8 },
            Vues.boutonBleu(f, F, { nom = 'AccepterNote', titre = bind 'titreAccepterNote', cle = 'peutAccepterNote',
                infobulle = "Poser la note proposée dans Lightroom (sans Claude ni quota)",
                action = function() F.enTache(F.accepterNote) end }),
        },
    }
end

-- Onglets -------------------------------------------------------------------------------------

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
