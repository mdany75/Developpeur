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
--   « Pourquoi ? » à droite d'une étape (`q..i`), un carré small dans une rangée poussée à droite
--   par margin_left (constaté le 21 octobre 2026, D6 : il répond, et la rangée ne prend pas les
--   clics du texte) ; la rangée d'actions selon `x..i` (« ☆ Voir la note », « Leçon de la photo »,
--   ou les deux), en variantes superposées.
-- Un clic sur le texte est réparti par Fenetre.cliquerLigne (image dans l'aperçu, ligne du carnet,
-- leçon, étape, sinon détail d'un outil) ; les boutons appellent F.pourquoi, F.voirNote et
-- F.voirLecon, qui relisent la ligne.
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
    -- « Pourquoi ? » : l'étape de cette ligne dans l'onglet Aperçu (F.pourquoi).
    texte[#texte + 1] = f:row {
        margin_left = largeur - D.pourquoi,
        F.bouton(f, { carre = true, size = 'small', title = "Pourquoi ?", font = P.petit, width = D.pourquoi,
            tooltip = "Pourquoi cette étape : son avant/après et sa raison (onglet Aperçu)", visible = F.si('q' .. i),
            action = function() F.pourquoi(i) end }),
    }
    -- Les actions d'une notation et d'une leçon : « ☆ Voir la note » (onglet Note), « Leçon de la
    -- photo » (onglet Leçon), ou les deux, à la place des icônes de la maquette (un glyphe dans le
    -- titre : une icône d'image_name chevaucherait le titre, constaté B3).
    local actions = 'x' .. i
    local function voirNote(visible)
        return F.bouton(f, { carre = true, size = 'small', title = "☆ Voir la note", font = P.petit, width = D.voirNote,
            tooltip = "La note proposée de la photo active, dans l'onglet Note", visible = visible, action = function() F.voirNote(i) end })
    end
    local function voirLecon(visible)
        return F.bouton(f, { carre = true, size = 'small', title = "Leçon de la photo", font = P.petit, width = D.voirLecon,
            tooltip = "La leçon de la photo : ce qui manquait, et ce qui se fait à la prise de vue (onglet Leçon)", visible = visible,
            action = function() F.voirLecon(i) end })
    end
    texte[#texte + 1] = f:column {
        place = 'overlapping',
        f:row { spacing = D.ecartActions, voirNote(F.condition(actions, function(v) return v == 'note' or v == 'les deux' end)),
            voirLecon(F.egal(actions, 'les deux')) },
        f:row { voirLecon(F.egal(actions, 'lecon')) },
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

-- Le voyant de Claude Code (sans clic) et celui de la liaison (un clic la démarre), en tête du
-- centre.
function Vues.voyantClaude(f, F, D)
    return Vues.voyant(f, F, { etat = 'etatClaude', texte = 'texteClaude', largeur = D.voyantClaude, police = F.POLICES.systeme12,
        couleur = F.COULEURS.texte, infobulle = "Claude Code, avec votre forfait claude.ai (pas de clé d'API)" })
end

function Vues.voyantLightroom(f, F, D)
    return Vues.voyant(f, F, { etat = 'etatLightroom', texte = 'texteLightroom', largeur = D.voyantLightroom,
        police = F.POLICES.systeme12, couleur = F.COULEURS.texte,
        infobulle = "Liaison de ce module avec le connecteur MCP-Développeur ; arrêtée, un clic la démarre",
        action = function()
            F.annulerEnvoiAuto()
            F.demarrerLiaison()
        end })
end

-- L'écran principal du Mac (de la 1.2, en bas du volet) : un clic le relit et donne son détail.
function Vues.voyantEcran(f, F, D)
    return Vues.voyant(f, F, { etat = 'etatEcran', texte = 'texteEcran', largeur = D.liste - 14, police = F.POLICES.systeme11,
        couleur = F.COULEURS.gris, infobulle = "Écran principal du Mac et son profil de couleur ; un clic donne le détail",
        action = function()
            F.annulerEnvoiAuto()
            F.enTache(F.montrerEcran)
        end })
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

-- Versions -------------------------------------------------------------------------------------

-- Ce module et le connecteur MCP-Développeur, une ligne chacun (« Développeur 1.3 »), en gris des
-- en-têtes, en orange en cas d'alerte (Composants.lignes).
function Vues.versions(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local function ligne(i)
        return f:column {
            place = 'overlapping',
            f:static_text { title = bind('versionTexte' .. i), font = P.systeme11, text_color = C.grisEntete, width = D.liste,
                height = D.ligneVersion, truncation = 'middle', visible = F.non('versionAlerte' .. i) },
            f:static_text { title = bind('versionTexte' .. i), font = P.systeme11, text_color = C.orange, width = D.liste,
                height = D.ligneVersion, truncation = 'middle', visible = F.si('versionAlerte' .. i) },
        }
    end
    return f:column { spacing = 0, ligne(1), ligne(2) }
end

-- En-tête --------------------------------------------------------------------------------------

-- Le Mode, trois boutons radio liés à la clé `mode` (Fenetre.rafraichirMode la tire de l'état ;
-- Fenetre.changerMode suit un vrai clic) : Appliquer et Proposer d'abord (le mode de la liaison),
-- Je le fais (l'exercice, 1.3). Grisés pendant que Claude travaille ; Je le fais suit
-- `peutJeLeFais`. Leur valeur passe par F.lierRadio : un clic, même sur le radio déjà coché, annule
-- l'envoi de la demande que ce clic a validée.
function Vues.mode(f, F)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:row {
        spacing = 10,
        place_vertical = 0.5,
        f:static_text { title = "Mode :", font = P.systeme12, text_color = C.gris, place_vertical = 0.5 },
        f:radio_button { title = "Appliquer", value = F.lierRadio 'mode', checked_value = 'appliquer', size = 'small', enabled = bind 'libre',
            tooltip = "Claude applique ses retouches directement" },
        f:radio_button { title = "Proposer d'abord", value = F.lierRadio 'mode', checked_value = 'proposer', size = 'small', enabled = bind 'libre',
            tooltip = "Claude montre d'abord ce qu'il compte changer, et attend votre accord (carte Proposition)" },
        f:radio_button { title = "Je le fais", value = F.lierRadio 'mode', checked_value = 'jelefais', size = 'small', enabled = bind 'peutJeLeFais',
            tooltip = "Faire la retouche vous-même : Claude donne les réglages dans l'ordre du panneau Développement, "
                .. "puis compare votre version à la sienne (J'ai fini dans la carte Proposition)" },
    }
end

-- L'en-tête du centre : le titre de la conversation (gras 16, sans ✎ : Renommer… est dans le
-- volet) et le Mode ; dessous, les voyants Claude Code et Lightroom, et la photo active
-- (`infoPhoto`, texte riche : nom et sélection en <EM>).
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
            Vues.mode(f, F),
        },
        f:row {
            spacing = 0,
            Vues.voyantClaude(f, F, D),
            f:spacer { width = 14 },
            Vues.voyantLightroom(f, F, D),
            f:spacer { fill_horizontal = 1 },
            f:static_text { title = bind 'infoPhoto', font = P.systeme12, text_color = C.gris, emphasis_font = P.systeme12,
                emphasis_color = C.texte, alignment = 'right', width = D.info, truncation = 'middle' },
        },
    }
end

-- Volet des conversations ------------------------------------------------------------------------

-- Une case de la liste (k, de D.hauteurCase) : ses variantes superposées, selon son genre (`lg..k` :
-- 'jour', 'conversation', 'carnet', 'plus', 'vide', Fenetre.casesListe) et son choix (`lc..k`) — le
-- fond de sélection, l'en-tête de jour, le titre en gras ou non, le sous-titre (`ls..k`),
-- « Plus anciennes… » ou « Plus récentes… » —, puis le calque qui reçoit le clic
-- (Fenetre.cliquerListe : il refuse lui-même pendant que Claude travaille). L'infobulle (`li..k`)
-- donne le titre entier.
function Vues.caseListe(f, F, k, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local genre, choisie = 'lg' .. k, 'lc' .. k
    local largeur = D.liste - 16
    local entree = function() return F.condition(genre, function(v) return v == 'conversation' or v == 'carnet' end) end
    return f:column {
        place = 'overlapping',
        width = D.liste,
        height = D.hauteurCase,
        Vues.image(f, F, 'selection', { visible = F.si(choisie) }),
        f:column {
            margin_left = 8,
            margin_top = 22,
            f:static_text { title = bind('lt' .. k), font = P.systemeGras11, text_color = C.grisEntete, width = largeur, truncation = 'tail',
                visible = F.egal(genre, 'jour') },
        },
        f:column {
            margin_left = 8,
            margin_top = 5,
            spacing = 0,
            f:column {
                place = 'overlapping',
                f:static_text { title = bind('lt' .. k), font = P.systemeGras12, text_color = C.texte, width = largeur, truncation = 'tail',
                    visible = F.et(entree(), F.si(choisie)) },
                f:static_text { title = bind('lt' .. k), font = P.systeme12, text_color = C.texte, width = largeur, truncation = 'tail',
                    visible = F.et(entree(), F.non(choisie)) },
            },
            f:column {
                place = 'overlapping',
                f:static_text { title = bind('ls' .. k), font = P.systeme11, text_color = C.sousTitreChoisi, width = largeur,
                    truncation = 'tail', visible = F.et(entree(), F.si(choisie)) },
                f:static_text { title = bind('ls' .. k), font = P.systeme11, text_color = C.grisEntete, width = largeur,
                    truncation = 'tail', visible = F.et(entree(), F.non(choisie)) },
            },
        },
        f:column {
            margin_left = 8,
            margin_top = 12,
            f:static_text { title = bind('lt' .. k), font = P.systeme12, text_color = C.bleu, width = largeur, truncation = 'tail',
                visible = F.egal(genre, 'plus') },
        },
        F.calque(f, { width = D.liste, height = D.hauteurCase, tooltip = bind('li' .. k), mouse_down = function() F.cliquerListe(k) end }),
    }
end

-- La liste des conversations : D.cases cases (Fenetre.rafraichirListe les remplit), dans la place
-- que le haut et le bas du volet laissent (D.hauteurListe).
function Vues.listeConversations(f, F, D)
    local cases = { spacing = 0, height = D.hauteurListe }
    for k = 1, D.cases do
        cases[#cases + 1] = Vues.caseListe(f, F, k, D)
    end
    return f:column(cases)
end

-- Publication et Consommation (venus de la colonne droite ; le menu Fichier est réduit quand une
-- fenêtre du module est devant).
function Vues.autresFenetres(f, F, D)
    local P = F.POLICES
    return f:column {
        spacing = 6,
        F.bouton(f, { carre = true, bezel = 22, title = "Publication…", font = P.systeme12, width = D.liste,
            tooltip = "Publier des photos en fichiers, sans Claude ni quota", action = function() F.publication() end }),
        F.bouton(f, { carre = true, bezel = 22, title = "Consommation…", font = P.systeme12, width = D.liste,
            tooltip = "Jetons de la semaine, budget, relevé du forfait", action = function() F.consommation() end }),
    }
end

-- Le volet (183, marges de 10) : « ＋ Nouvelle conversation », la loupe devant « Rechercher », la
-- liste en cases ; en bas, Renommer… et Supprimer…, un filet, Publication… et Consommation…, les
-- versions et le voyant Écran.
function Vues.volet(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        margin_left = D.margeVolet,
        margin_top = D.margeVolet,
        spacing = 0,
        F.bouton(f, { carre = true, bezel = 26, title = "＋ Nouvelle conversation", font = P.systeme12, width = D.liste,
            tooltip = "Commencer une nouvelle conversation", enabled = bind 'libre', action = function() F.nouvelle() end }),
        f:spacer { height = 8 },
        f:row {
            spacing = 0,
            Vues.image(f, F, 'loupe', { place_vertical = 0.5 }),
            f:spacer { width = 8 },
            f:edit_field { value = bind 'recherche', immediate = true, width = D.recherche, height = 24, font = P.systeme12,
                placeholder_string = "Rechercher", tooltip = "Rechercher dans les titres et les messages des conversations" },
        },
        f:spacer { height = 14 },
        Vues.listeConversations(f, F, D),
        f:row {
            spacing = 6,
            F.bouton(f, { carre = true, bezel = 22, title = "Renommer…", font = P.systeme12, width = D.renommer,
                tooltip = "Renommer la conversation", action = function() F.enTache(F.renommer) end }),
            F.bouton(f, { carre = true, bezel = 22, title = "Supprimer…", font = P.systeme12, width = D.renommer, enabled = bind 'libre',
                tooltip = "Mettre la conversation à la corbeille", action = function() F.enTache(F.supprimer) end }),
        },
        f:spacer { height = 12 },
        Vues.aplat(f, D.liste, D.filet, C.filetVolet),
        f:spacer { height = 12 },
        Vues.autresFenetres(f, F, D),
        f:spacer { height = 4 },
        Vues.versions(f, F, D),
        f:spacer { height = 6 },
        Vues.voyantEcran(f, F, D),
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
-- repli du lot B0 : Retour dans « Rechercher » déclencherait Envoyer, constaté D1) : Retour dans
-- le champ de demande passe par son observateur et l'envoi automatique (Fenetre.saisieValidee).
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
-- (`immediate = false` : Retour le valide, Fenetre.saisieValidee), puis 📎 et 📋 (carrés à icône
-- seule), « Style » et son menu, le bandeau, Envoyer.
function Vues.saisie(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    return f:column {
        margin_left = D.margeCentre,
        margin_top = 12,
        spacing = 8,
        Vues.invites(f, F, D),
        f:edit_field { value = bind 'saisie', immediate = false, height_in_lines = 2, width = D.champ, enabled = bind 'libre',
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
            Vues.bandeau(f, F, D.bandeau),
            f:spacer { width = 8 },
            Vues.envoi(f, F, D),
        },
    }
end

-- Colonne droite ---------------------------------------------------------------------------------

-- Les segments Aperçu | Proposition | Note | Leçon, centrés en tête du panneau : chacun son image
-- et sa variante bleue (-actif, montrée quand `onglet` vaut sa valeur), sous un calque dont le
-- clic choisit l'onglet (F.choisirSegment : un vrai clic, son crochet suit). Ni survol, ni focus.
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

-- La proposition de Claude en mode « Proposer d'abord » (fenêtre B, lot B5), sur son image
-- (carte-proposition, à la largeur intérieure du panneau) : « Proposition de Claude » en gras 12,
-- ce qu'il compte changer page par page (`propositionTexte`, D.propLignes lignes en 12, coupées par
-- Fenetre.montrerPage ; la ligne « Cadre : … » de Composition lue comprise), l'état d'un exercice
-- Je le fais (`exerciceEtat`, « À vous · 3 réglages faits sur 7 ») avec ▲ ▼ à sa droite, puis
-- Refuser, Ajuster… et « Je le fais » (titre lié `titreJeLeFais` : « J'ai fini » pendant
-- l'exercice, jamais deux boutons superposés) en carrés, et Accepter, un bouton bleu en image
-- (Vues.boutonBleu : son calque ne fait rien quand aucune proposition n'attend, `enAttente`).
-- Refuser, Ajuster… et Accepter sont actifs quand une proposition attend et que Claude ne
-- travaille pas.
function Vues.proposition(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local t = F.tailleImage('carte-proposition')
    return f:column {
        place = 'overlapping',
        width = largeur,
        height = t.hauteur,
        Vues.image(f, F, 'carte-proposition'),
        f:column {
            margin_left = D.margeCarte,
            margin_top = 12,
            spacing = 6,
            f:static_text { title = "Proposition de Claude", font = P.gras12, text_color = C.texte, width = D.largeurProposition },
            f:static_text { title = bind 'propositionTexte', font = P.texte12, text_color = C.texte, width = D.largeurProposition,
                height_in_lines = D.propLignes },
            f:row {
                spacing = 0,
                f:static_text { title = bind 'exerciceEtat', font = P.petit, text_color = C.gris, width = D.largeurProposition - 60,
                    truncation = 'tail', place_vertical = 0.5 },
                f:spacer { fill_horizontal = 1 },
                Vues.fleches(f, F, 'proposition'),
            },
            f:row {
                spacing = 0,
                F.bouton(f, { carre = true, bezel = 24, title = "Refuser", font = P.systeme12, width = D.refuser, enabled = bind 'enAttente',
                    tooltip = "Refuser la proposition : rien ne change", action = function() F.repondreProposition(false) end }),
                f:spacer { width = 6 },
                F.bouton(f, { carre = true, bezel = 24, title = "Ajuster…", font = P.systeme12, width = D.ajuster, enabled = bind 'enAttente',
                    tooltip = "Dire à Claude ce qu'il faut changer avant d'appliquer", action = function() F.enTache(F.ajuster) end }),
                f:spacer { width = 6 },
                F.bouton(f, { carre = true, bezel = 24, title = bind 'titreJeLeFais', font = P.systeme12, width = D.jeLeFais,
                    enabled = bind 'peutJeLeFais',
                    tooltip = "Faire la retouche vous-même : Claude donne les réglages dans l'ordre du panneau Développement, "
                        .. "puis compare votre version à la sienne",
                    action = function() F.enTache(F.jeLeFais) end }),
                f:spacer { fill_horizontal = 1 },
                Vues.boutonBleu(f, F, { nom = 'AccepterProposition', titre = "Accepter", cle = 'enAttente',
                    infobulle = "Appliquer la proposition : la photo ne change qu'à ce clic",
                    action = function() F.repondreProposition(true) end }),
            },
        },
    }
end

-- La carte de l'étape (1.3, l'ancienne carte « Pourquoi ? ») dans l'onglet Aperçu, sur son image
-- (carte-etape, fenêtre B, lot B5) : son titre en gras 12 (« Étape 2 sur 4 · passe 1 : balance » ;
-- « Pourquoi ? » sans étape, Fenetre.TITRE_ETAPE), son sous-titre en gris (fichier, outil,
-- « annulée ensuite »), sa raison et ses réglages changés page par page (`etapeTexte`,
-- D.etapeLignes lignes en 12, coupées par Fenetre.montrerPage), puis ◀ ▶ (étape précédente ou
-- suivante de la même photo), Voir l'avant / Voir l'après (titre lié `titreBascule` : un seul
-- bouton), Détail… (l'appel de l'outil et sa réponse) en carrés, et ▲ ▼.
function Vues.etape(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local t = F.tailleImage('carte-etape')
    return f:column {
        place = 'overlapping',
        width = largeur,
        height = t.hauteur,
        Vues.image(f, F, 'carte-etape'),
        f:column {
            margin_left = D.margeCarte,
            margin_top = 12,
            spacing = 6,
            f:static_text { title = bind 'etapeTitre', font = P.gras12, text_color = C.texte, width = D.largeurEtape, truncation = 'tail' },
            f:static_text { title = bind 'etapeSousTitre', font = P.petit, text_color = C.gris, width = D.largeurEtape,
                truncation = 'middle' },
            f:static_text { title = bind 'etapeTexte', font = P.texte12, text_color = C.texte, width = D.largeurEtape,
                height_in_lines = D.etapeLignes },
            f:row {
                spacing = 0,
                F.bouton(f, { carre = true, bezel = 22, title = "◀", width = D.fleche, tooltip = "Étape précédente",
                    enabled = bind 'etapePrecedente', action = function() F.etapeVoisine(-1) end }),
                f:spacer { width = 4 },
                F.bouton(f, { carre = true, bezel = 22, title = "▶", width = D.fleche, tooltip = "Étape suivante",
                    enabled = bind 'etapeSuivante', action = function() F.etapeVoisine(1) end }),
                f:spacer { width = 8 },
                F.bouton(f, { carre = true, bezel = 22, title = bind 'titreBascule', font = P.systeme12, width = D.bascule,
                    tooltip = "Montrer l'avant ou l'après de cette étape dans l'aperçu", enabled = bind 'etapeAImages',
                    action = function() F.basculerEtape() end }),
                f:spacer { width = 6 },
                F.bouton(f, { carre = true, bezel = 22, title = "Détail…", font = P.systeme12, width = D.detail,
                    tooltip = "Ce que Claude a demandé au connecteur pour cette étape, puis sa réponse", enabled = bind 'etapeADetail',
                    action = function() F.enTache(F.detailEtape) end }),
                f:spacer { fill_horizontal = 1 },
                Vues.fleches(f, F, 'etape'),
            },
        },
    }
end

-- La carte de l'onglet Leçon (1.3, lot B4), sur son image (carte-lecon, à la largeur intérieure
-- du panneau) : son titre en gras 12 (`leconTitre`, « Leçon de la photo · DSCF4961.RAF »), puis la
-- leçon page par page (`leconTexte`, D.leconLignes lignes en 12, coupées par Fenetre.montrerPage :
-- le nom de chaque axe en <EM>, gras de même taille, constaté le 21 octobre 2026, D4), puis
-- « Détail… » (l'appel de photo_lesson et sa réponse) et ▲ ▼ (Fenetre.defilerTexte('lecon')). Sans
-- leçon, l'aide (Fenetre.AUCUNE_LECON).
function Vues.lecon(f, F, largeur, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local t = F.tailleImage('carte-lecon')
    return f:column {
        place = 'overlapping',
        width = largeur,
        height = t.hauteur,
        Vues.image(f, F, 'carte-lecon'),
        f:column {
            margin_left = D.margeCarte,
            margin_top = 12,
            spacing = 6,
            f:static_text { title = bind 'leconTitre', font = P.gras12, text_color = C.texte, width = D.largeurLecon,
                truncation = 'middle' },
            f:static_text { title = bind 'leconTexte', font = P.texte12, text_color = C.texte, emphasis_font = P.gras12,
                emphasis_color = C.texte, width = D.largeurLecon, height_in_lines = D.leconLignes },
            f:row {
                spacing = 0,
                F.bouton(f, { carre = true, bezel = 22, title = "Détail…", font = P.systeme12, width = D.detail,
                    enabled = bind 'leconADetail', tooltip = "Ce que Claude a donné au connecteur pour cette leçon, puis sa réponse",
                    action = function() F.enTache(F.detailLecon) end }),
                f:spacer { fill_horizontal = 1 },
                Vues.fleches(f, F, 'lecon'),
            },
        },
    }
end

-- Note -------------------------------------------------------------------------------------------
-- La carte Note de la photo active (fenêtre B, lot B5 : la maquette « B · Conversation claire »,
-- onglet Note). Claude note d'abord chaque photo qu'il traite, et sa note arrive « à vérifier » :
-- Dany l'accepte, la laisse ou la change (pas de bouton Noter ni Évaluer : décision de Dany). Ses
-- étoiles et ses drapeaux écrivent dans le catalogue sans Claude ni quota (Fenetre.poserEtoile,
-- Fenetre.poserDrapeau) ; Dany peut poser 5 ★, Claude jamais. Les couleurs d'état sont des clés de
-- la palette (Fenetre.COULEURS_NOTE, Fenetre.TEINTES_NOTE).

-- Une étiquette de la grille de la carte (« Passes : »…), alignée à droite, en gris 12.
local function etiquetteNote(f, F, D, titre)
    return f:static_text { title = titre, font = F.POLICES.systeme12, text_color = F.COULEURS.gris, alignment = 'right',
        width = D.etiquetteNote, place_vertical = 0.5 }
end

-- « Passes : » : les quatre passes du standard (F.PASSES), d'après `notePasse` (F.etatPasse) : la
-- coche verte devant une passe faite (seules celles avant la dernière passe de Claude peuvent
-- l'être), le libellé en gras noir pour la passe en cours, en gris 11 sinon ; un chevron entre
-- deux. Chaque passe a la largeur de sa variante la plus large, mesurée (une vue masquée garde sa
-- place) ; sans clic.
function Vues.passes(f, F, D)
    local C, P = F.COULEURS, F.POLICES
    local coche = F.tailleImage('coche-10').largeur
    local rangee = { spacing = 0, height = D.lignePasses }
    for j, libelle in ipairs(F.PASSES) do
        if j > 1 then
            rangee[#rangee + 1] = f:spacer { width = 3 }
            rangee[#rangee + 1] = Vues.image(f, F, 'chevron-passe', { place_vertical = 0.5 })
            rangee[#rangee + 1] = f:spacer { width = 3 }
        end
        local faisable, enCours = j < F.PASSE_MAX_CLAUDE, j <= F.PASSE_MAX_CLAUDE
        local function etat(test)
            return F.condition('notePasse', function(v) return test(F.etatPasse(j, v)) end)
        end
        local gris = F.largeurLibelle(libelle, 'petit')
        local largeur = math.max(faisable and (coche + 3 + gris) or gris, enCours and F.largeurLibelle(libelle, 'gras11') or 0)
        local variantes = { place = 'overlapping', place_vertical = 0.5 }
        variantes[#variantes + 1] = f:static_text { title = libelle, font = P.systeme11, text_color = C.gris, width = largeur,
            visible = etat(function(e) return e == 'a_venir' or (e == 'faite' and not faisable) or (e == 'en_cours' and not enCours) end) }
        if enCours then
            variantes[#variantes + 1] = f:static_text { title = libelle, font = P.systemeGras11, text_color = C.texte, width = largeur,
                visible = etat(function(e) return e == 'en_cours' end) }
        end
        if faisable then
            local function faite()
                return etat(function(e) return e == 'faite' end)
            end
            variantes[#variantes + 1] = f:row {
                spacing = 0,
                Vues.image(f, F, 'coche-10', { visible = faite(), place_vertical = 0.5 }),
                f:spacer { width = 3 },
                f:static_text { title = libelle, font = P.systeme11, text_color = C.gris, width = largeur - coche - 3, visible = faite() },
            }
        end
        rangee[#rangee + 1] = f:column(variantes)
    end
    return f:row(rangee)
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

-- « Claude propose » : cinq petites étoiles (etoile12) d'après `noteClaude` (0 à 4), « rejeter »
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

-- La ligne du plafond, sous son filet : l'avertissement, « <EM>Plafond 3 ★</EM> : … » (gras ambre,
-- `plafondTexte`), et « Voir à 100 % » (décision de Dany du 21 octobre 2026) : le zoom que Claude
-- a pris pour noter la photo, montré dans l'aperçu (F.voirZoom, sans Claude ni Lightroom ; Agrandir
-- le montre en grand) ; sans un tel zoom, le même bouton grisé, avec une infobulle qui dit pourquoi
-- (deux boutons superposés : une infobulle liée n'est pas constatée). Toute la ligne suit
-- `aPlafond`.
function Vues.lignePlafond(f, F, D)
    local bind, C, P = F.bind, F.COULEURS, F.POLICES
    local function plafond()
        return F.si 'aPlafond'
    end
    return f:row {
        spacing = 0,
        Vues.image(f, F, 'avertissement', { visible = plafond(), place_vertical = 0.5 }),
        f:spacer { width = 8 },
        f:static_text { title = bind 'plafondTexte', font = P.texte12, text_color = C.texte, emphasis_font = P.gras12, emphasis_color = C.ambre,
            width = D.plafond, truncation = 'tail', place_vertical = 0.5, visible = plafond() },
        f:spacer { width = 8 },
        f:column {
            place = 'overlapping',
            F.bouton(f, { carre = true, bezel = 22, title = "Voir à 100 %", font = P.systeme11, width = D.zoom, tooltip = F.INFOBULLE_ZOOM,
                visible = F.et(plafond(), F.si 'peutVoirZoom'), action = function() F.voirZoom() end }),
            F.bouton(f, { carre = true, bezel = 22, title = "Voir à 100 %", font = P.systeme11, width = D.zoom, tooltip = F.SANS_ZOOM,
                enabled = false, visible = F.et(plafond(), F.non 'peutVoirZoom'), action = function() end }),
        },
    }
end

-- La carte des critères, sur son image (carte-note, à la largeur intérieure du panneau) : la grille
-- de D.criteres + 1 lignes (Vues.ligneCritere), lue page par page (▲ ▼ de la rangée du bas), puis
-- le filet (un aplat) et la ligne du plafond.
function Vues.carteCriteres(f, F, D)
    local C = F.COULEURS
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
            f:spacer { height = 6 },
            f:picture { width = D.carte, height = D.filet, background_color = C.filetPlafond, visible = F.si 'aPlafond' },
            f:spacer { height = 6 },
            Vues.lignePlafond(f, F, D),
        },
    }
end

-- La carte Note : la grille des étiquettes et des valeurs (« Passes : », « Votre note : » et la
-- note posée, `notePoseeTitre` et `notePoseeSous`, « Drapeau : » avec « ⚑ Retenir », « ⊗ Rejeter »
-- et « ? À vérifier », grisé : Vues.inactif) ; « Claude propose » ; la carte des critères ; puis
-- ▲ ▼ et, à droite, « Laisser à N ★ » (`titreLaisser` : la proposition écartée, rien dans le
-- catalogue), « Changer… » (de 0 à 5 ★ et le drapeau) et « Accepter N ★ » (`titreAccepterNote`),
-- un bouton bleu en image dont le calque ne fait rien quand `peutAccepterNote` est faux.
function Vues.notation(f, F, largeur, D)
    local bind, P = F.bind, F.POLICES
    return f:column {
        spacing = 0,
        width = largeur,
        f:row {
            spacing = 0,
            height = D.lignePasses,
            etiquetteNote(f, F, D, "Passes :"),
            f:spacer { width = D.ecartEtiquette },
            Vues.passes(f, F, D),
        },
        f:spacer { height = D.ecartGrille },
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
