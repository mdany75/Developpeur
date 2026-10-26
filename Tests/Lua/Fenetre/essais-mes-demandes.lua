-- essais-mes-demandes.lua : le menu Mes demandes de la fenêtre Claude (demandé par Dany le
-- 22 octobre 2026), hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : le menu à
-- droite de Style sous le champ, sa largeur (Dispositions.TAILLES) et ses éléments (« Nom —
-- description » coupés par « … », séparateurs, Ajouter…, Renommer…, Supprimer… ; « Aucune demande
-- gardée » grisé) ; un choix remplit le champ sans envoi ni bascule (S.choisir, le champ validé
-- d'abord comme par un clic), le menu revient à son titre, Retour l'envoie ; les fenêtres Ajouter…,
-- Renommer… et Supprimer… (refus d'un nom vide ou pris, d'un texte vide) ; mes-demandes.json écrit
-- d'un coup, relu à chaque ouverture, illisible mis de côté ; « ＋ Garder la demande » et la ligne
-- « Demande à garder : « … » » de Claude retirés (correctif 1.3.6, deuxième retour de Dany du
-- 25 octobre 2026) : ni fonction, ni bouton, ni section des consignes ; les consignes sous leur
-- plafond ; uninstall.sh. Ni Claude, ni quota ; les fichiers vont dans un dossier personnel
-- temporaire.
-- Lancé par scripts/tester-module.sh dans Tests/Lua/Fenetre, avec PLUGIN_DIR.

local S = require 'Simulation'

local reussis, echecs = 0, 0
local function essai(nom, fn)
    local ok, erreur = xpcall(fn, debug.traceback)
    if ok then
        reussis = reussis + 1
        print('ok     ' .. nom)
    else
        echecs = echecs + 1
        print('ÉCHEC  ' .. nom .. '\n' .. tostring(erreur))
    end
end

local function egal(attendu, obtenu, quoi)
    if attendu ~= obtenu then
        error(string.format('%s : attendu %q, obtenu %q', quoi or 'valeur', tostring(attendu), tostring(obtenu)), 2)
    end
end

local function vrai(condition, quoi)
    if not condition then
        error(quoi or 'condition fausse', 2)
    end
end

local function contient(texte, morceau, quoi)
    if type(texte) ~= 'string' or not texte:find(morceau, 1, true) then
        error(string.format('%s : %q introuvable dans %q', quoi or 'texte', morceau, tostring(texte)), 2)
    end
end

local function refuse(fn, attendu, quoi)
    local ok, erreur = pcall(fn)
    vrai(not ok, (quoi or 'refus attendu') .. ' : accepté')
    vrai(tostring(erreur):find(attendu, 1, true), (quoi or 'refus') .. ' : ' .. tostring(erreur))
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre.
local function lancerTaches(depuis)
    local i = (depuis or 0) + 1
    while i <= #S.taches do
        vrai(i - (depuis or 0) <= 100, 'des tâches sans fin')
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Journal = require 'Journal'
local Json = require 'Json'
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
-- La boucle de la fenêtre et les voyants (lus dans une tâche à l'ouverture) ne sont pas de cet
-- essai : les tâches se lancent ici à la main (lancerTaches).
Fenetre.boucle = function() end
Fenetre.verifier = function() end
local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'

local D = Dispositions.dimensions()

-- Le journal de la fenêtre, gardé pour les essais (un fichier illisible s'y dit).
local journal = {}
local noterVraiment = Journal.noter
Journal.noter = function(...)
    journal[#journal + 1] = table.concat({ ... }, ' ')
    return noterVraiment(...)
end

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Ouvre la fenêtre Claude et appelle fn(p, contenu) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.taches = {}
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args.contents) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    if erreur then
        error(erreur, 0)
    end
end

-- Remplace un champ d'une table le temps de fn, puis le remet (même en cas d'erreur).
local function avec(t, cle, valeur, fn)
    local avant = t[cle]
    t[cle] = valeur
    local ok, erreur = xpcall(fn, debug.traceback)
    t[cle] = avant
    if not ok then
        error(erreur, 0)
    end
end

local vues = S.vues

-- La vue simple liée à `cle` (titre ou valeur).
local function liee(contenu, genre, cle)
    for _, v in ipairs(vues(contenu)) do
        local lien = v.args.title or v.args.value
        if v.genre == genre and type(lien) == 'table' and lien.liaison and lien.key == cle then
            return v
        end
    end
    error(genre .. ' lié à ' .. cle .. ' introuvable', 2)
end

-- La rangée qui contient directement cette vue.
local function rangeeDe(contenu, vue)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == 'row' then
            for _, e in ipairs(v.args) do
                if e == vue then
                    return v
                end
            end
        end
    end
    error('rangée introuvable', 2)
end

-- La largeur donnée d'une vue : la sienne, ou celle de ses vues (une rangée les additionne, ses
-- espaces compris ; une colonne ou une superposition prend la plus large).
local function largeurDonnee(v)
    local a = v.args
    if type(a.width) == 'number' then
        return a.width
    end
    local enLigne = v.genre == 'row' and a.place ~= 'overlapping'
    local total = 0
    for _, e in ipairs(a) do
        if type(e) == 'table' and e.genre then
            local l = largeurDonnee(e)
            total = enLigne and (total + l) or math.max(total, l)
        end
    end
    return total
end

-- Le fichier des demandes ------------------------------------------------------------------------

local FICHIER = Stockage.fichierDemandes()

local function ecrireFichier(texte)
    if texte == nil then
        Fichiers.supprimer(FICHIER)
    else
        Fichiers.ecrire(FICHIER, texte)
    end
end

local function demandesDuFichier()
    local lu = Json.decode(assert(Fichiers.lire(FICHIER), 'mes-demandes.json'))
    local noms = {}
    for _, d in ipairs(lu.demandes) do
        noms[#noms + 1] = d.nom
    end
    return lu, table.concat(noms, ' | ')
end

local PORTRAIT = { nom = 'Portrait intérieur', description = 'PROVIA, peau douce',
    texte = "Retouche ce portrait en intérieur : simulation PROVIA, balance plus neutre, ombres relevées, rendu naturel." }
local PAYSAGE = { nom = 'Paysage du soir', description = "ciel retenu, premier plan éclairci comme un tireur, couleurs chaudes et naturelles",
    texte = "Retouche ce paysage du soir : ciel retenu, premier plan éclairci, couleurs chaudes mais naturelles." }

-- Range ces demandes dans mes-demandes.json (par Stockage, comme la fenêtre).
local function ranger(...)
    ecrireFichier(nil)
    for _, d in ipairs({ ... }) do
        local ok, r = Stockage.garderDemande(d)
        vrai(ok, tostring(r))
    end
end

-- Les fenêtres modales jouées : chaque appel de presentModalDialog prend la fonction suivante de
-- `script`, qui reçoit ses arguments et la table liée (q) et rend la réponse ; au-delà, 'cancel'.
local function jouer(script, fn)
    local presenter = S.modules.LrDialogs.presentModalDialog
    local n = 0
    S.modules.LrDialogs.presentModalDialog = function(args)
        S.dialogues[#S.dialogues + 1] = args
        n = n + 1
        local etape = script[n]
        if not etape then
            return 'cancel'
        end
        return etape(args, args.contents.args.bind_to_object)
    end
    local ok, erreur = xpcall(fn, debug.traceback)
    S.modules.LrDialogs.presentModalDialog = presenter
    if not ok then
        error(erreur, 0)
    end
    return n
end

-- Une conversation faite à la main ---------------------------------------------------------------

local compteur = 0
local function element(genre, champs)
    compteur = compteur + 1
    local e = { id = 'E' .. compteur, genre = genre, texte = '', date = 1792000000 + compteur, images = {}, changements = {} }
    for cle, valeur in pairs(champs or {}) do
        e[cle] = valeur
    end
    return e
end

local LIGNE = "Demande à garder : « " .. PORTRAIT.texte .. " »"

-- Un outil qui a écrit une étape sur la photo 4961.
local function retouche(outil)
    return element('outil', { outil = outil or 'apply_settings', etat = 'fait', texte = 'tons', raison = 'ombres bouchées',
        etape = 'tons', etapes = { { photo = 4961, id = '12', nom = 'Claude · tons', changements = {} } } })
end

local function conversation(...)
    local c = Conversation.nouvelle()
    c.elements = { element('dany', { texte = 'Retouche la photo active' }) }
    for _, e in ipairs({ ... }) do
        c.elements[#c.elements + 1] = e
    end
    return c
end

-- La ligne d'actions d'un fil (la dernière), nil sans elle.
local function ligneActions(c)
    local actions
    for _, l in ipairs(Fil.lignes(c, D.texteFil)) do
        if l.genre == 'actions' then
            actions = l
        end
    end
    return actions
end

-- Les essais -------------------------------------------------------------------------------------

essai('Menu : à droite de Style sous le champ, à sa largeur (Dispositions.TAILLES), le bandeau garde le reste ; « Mes demandes » quand rien n\'est choisi ; grisé pendant que Claude travaille', function()
    egal(280, Dispositions.TAILLES.mesDemandes)
    egal(Dispositions.TAILLES.mesDemandes, D.mesDemandes)
    egal(324, D.bandeau, 'le bandeau : ce que laissent 📎 📋, Style, Mes demandes et Envoyer')
    ranger(PORTRAIT)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local menu = liee(contenu, 'popup_menu', 'mesDemandes')
        local style = liee(contenu, 'popup_menu', 'style')
        egal(D.mesDemandes, menu.args.width)
        egal('libre', menu.args.enabled.key, 'grisé avec le Mode, pendant que Claude travaille')
        -- Dans la rangée du Style, juste après lui (un espace de 8 entre les deux), avant le bandeau.
        local rangee = rangeeDe(contenu, menu)
        egal(rangee, rangeeDe(contenu, style), 'la rangée du Style, sous le champ')
        local ordre = {}
        for k, e in ipairs(rangee.args) do
            if e == style then
                ordre.style = k
            elseif e == menu then
                ordre.menu = k
            end
        end
        egal(ordre.style + 2, ordre.menu, 'à droite de Style')
        egal('spacer', rangee.args[ordre.style + 1].genre)
        egal(8, rangee.args[ordre.style + 1].args.width)
        egal(D.fil, largeurDonnee(rangee), 'la rangée fait la largeur utile du centre')
        egal(D.bandeau, liee(contenu, 'static_text', 'message').args.width)
        -- Son titre : la valeur montrée quand rien n'est choisi.
        egal(Fenetre.MENU_TITRE, p.mesDemandes)
        local items = S.elementsDe(menu)
        egal(Fenetre.MES_DEMANDES, items[1].title)
        egal(Fenetre.MENU_TITRE, items[1].value)
        egal('Mes demandes', Fenetre.MES_DEMANDES)
        -- « Nom — petite description » y tient en entier.
        egal('Portrait intérieur — PROVIA, peau douce', items[3].title)
        vrai(Fil.largeur(items[3].title, 'texte') <= D.mesDemandes - Fenetre.FLECHES_MENU, 'dans la largeur du menu')
        -- Claude travaille : le menu est grisé, un choix est refusé.
        p.libre = false
        refuse(function() S.choisir(menu, 1) end, 'inactive', 'menu grisé')
        p.libre = true
    end)
end)

essai('Éléments : titre, séparateur, « Nom — description » coupés par « … », séparateur, Ajouter…, Renommer…, Supprimer… ; vide : « Aucune demande gardée » grisé et Ajouter… ; tables neuves', function()
    local vide = Fenetre.elementsMesDemandes({}, D.mesDemandes)
    local function resume(items)
        local t = {}
        for _, it in ipairs(items) do
            t[#t + 1] = it.separator and '—' or (it.title .. (it.enabled == false and ' (grisé)' or ''))
        end
        return table.concat(t, ' | ')
    end
    egal('Mes demandes | — | Aucune demande gardée (grisé) | — | Ajouter…', resume(vide))
    egal(nil, S.refusElements(vide))
    local liste = { { nom = PAYSAGE.nom, description = PAYSAGE.description, texte = PAYSAGE.texte },
        { nom = PORTRAIT.nom, description = '', texte = PORTRAIT.texte },
        { nom = string.rep('Très long nom de demande ', 4), description = 'jamais vue', texte = 'x' } }
    local items = Fenetre.elementsMesDemandes(liste, D.mesDemandes)
    egal(9, #items)
    egal('ajouter renommer supprimer', table.concat({ items[7].value, items[8].value, items[9].value }, ' '))
    egal('Ajouter… Renommer… Supprimer…', table.concat({ items[7].title, items[8].title, items[9].title }, ' '))
    vrai(items[2].separator and items[6].separator, 'séparateurs')
    egal(1, items[3].value, 'une demande : son indice')
    -- La description longue, coupée par « … » à la largeur du menu.
    vrai(items[3].title:find('^Paysage du soir — ciel retenu'), items[3].title)
    egal('…', items[3].title:sub(-#'…'), 'coupée')
    vrai(Fil.largeur(items[3].title, 'texte') <= D.mesDemandes - Fenetre.FLECHES_MENU, 'dans le menu')
    egal(PORTRAIT.nom, items[4].title, 'sans description : le nom seul')
    -- Un nom trop long : le nom coupé seul.
    egal('…', items[5].title:sub(-#'…'))
    vrai(not items[5].title:find('—', 1, true), 'sans description')
    for _, it in ipairs(items) do
        egal(nil, getmetatable(it), 'table neuve')
    end
    egal(nil, S.refusElements(items))
end)

essai('Choix : la demande remplit le champ, à la place du texte tapé, sans envoi ni bascule ; le menu revient à son titre ; rechoisie, la même ; le titre rechoisi n\'envoie rien', function()
    ranger(PORTRAIT, PAYSAGE)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local envoyees = {}
    avec(Fenetre, 'envoyer', function(texte) envoyees[#envoyees + 1] = texte end, function()
        ouvrirFenetre(function(p, contenu)
            local menu = liee(contenu, 'popup_menu', 'mesDemandes')
            local champ = liee(contenu, 'edit_field', 'saisie')
            local onglet = p.onglet
            -- Un texte tapé, puis un choix : le champ est validé (supposé, comme un clic), son envoi
            -- automatique annulé, et la demande prend sa place.
            S.taper(champ, 'texte tapé')
            S.choisir(menu, 2)
            egal(PORTRAIT.texte, p.saisie, 'la demande dans le champ')
            egal(PORTRAIT.texte, S.texteChamp(champ))
            egal(nil, Fenetre.envoiAuto, "pas d'envoi automatique")
            egal(Fenetre.MENU_TITRE, p.mesDemandes, 'le menu revient à son titre')
            egal(onglet, p.onglet, 'aucune bascule')
            egal(Fenetre.DEMANDE_DANS_LE_CHAMP, p.message)
            egal(nil, S.boutonParDefaut(), 'aucun bouton par défaut')
            lancerTaches()
            egal(0, #envoyees, 'rien ne part')
            -- Rechoisie : la même demande (le menu était revenu à son titre), puis l'autre.
            S.choisir(menu, 1)
            egal(PAYSAGE.texte, p.saisie)
            S.choisir(menu, 2)
            egal(PORTRAIT.texte, p.saisie)
            egal(Fenetre.MENU_TITRE, p.mesDemandes)
            -- Le titre rechoisi après une frappe : la valeur ne change pas, mais l'envoi que ce clic
            -- a validé s'annule (F.lierRadio).
            S.taper(champ, ' et plus')
            S.choisir(menu, Fenetre.MENU_TITRE)
            egal(nil, Fenetre.envoiAuto, 'titre rechoisi : rien ne part')
            lancerTaches()
            egal(0, #envoyees, 'toujours rien')
        end)
    end)
end)

-- Retour dans le champ sans frappe : Lightroom pousse la valeur du champ vers la table (supposé,
-- à constater) ; la clé ne change pas, seul le transform de sa liaison le voit (Fenetre.lierSaisie).
local function retourSansFrappe(champ, p)
    local lien = champ.args.value
    local valeur = lien.transform(S.texteChamp(champ), false)
    p[lien.key] = valeur
end

essai('Retour : la demande mise part telle quelle (Fenetre.lierSaisie), ou changée (l\'observateur) ; Envoyer aussi ; une demande tapée part comme avant', function()
    ranger(PORTRAIT)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local envoyees = {}
    avec(Fenetre, 'envoyer', function(texte) envoyees[#envoyees + 1] = texte end, function()
        ouvrirFenetre(function(p, contenu)
            local menu = liee(contenu, 'popup_menu', 'mesDemandes')
            local champ = liee(contenu, 'edit_field', 'saisie')
            -- Telle quelle.
            S.choisir(menu, 1)
            retourSansFrappe(champ, p)
            vrai(Fenetre.envoiAuto ~= nil, 'Retour : envoi automatique')
            lancerTaches()
            egal(PORTRAIT.texte, envoyees[1], 'partie telle quelle')
            egal('', p.saisie, 'le champ vidé')
            egal(nil, Fenetre.demandeMise)
            -- Sans demande mise, un Retour sans frappe n'envoie rien (comme avant).
            retourSansFrappe(champ, p)
            egal(nil, Fenetre.envoiAuto)
            -- Changée dans le champ, puis Retour : l'observateur, comme une demande tapée.
            S.choisir(menu, 1)
            S.taper(champ, ' Garde le ciel.')
            S.retour(champ)
            egal(nil, Fenetre.demandeMise, 'changée : plus la demande mise')
            lancerTaches()
            egal(PORTRAIT.texte .. ' Garde le ciel.', envoyees[2])
            -- Envoyer, après un choix.
            S.choisir(menu, 1)
            Fenetre.boutonPrincipal()
            egal(PORTRAIT.texte, envoyees[3])
            -- Une demande tapée.
            S.taper(champ, 'Bonjour')
            S.retour(champ)
            lancerTaches()
            egal('Bonjour', envoyees[4])
            egal(4, #envoyees)
        end)
    end)
end)

essai('Ajouter… : depuis le menu, la fenêtre pré-remplie du texte du champ ; nom vide, nom pris (majuscules et accents comptent pour rien), texte vide : refusés avec une phrase claire, la fenêtre rouverte, les champs gardés ; puis gardée', function()
    ranger(PORTRAIT)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local menu = liee(contenu, 'popup_menu', 'mesDemandes')
        local champ = liee(contenu, 'edit_field', 'saisie')
        S.taper(champ, 'Éclaircis le sujet, assombris les bords.')
        local taches, dialogues = #S.taches, #S.dialogues
        S.choisir(menu, 'ajouter')
        egal(nil, Fenetre.envoiAuto, "le texte validé par le clic ne part pas")
        egal(Fenetre.MENU_TITRE, p.mesDemandes)
        vrai(#S.taches > taches, 'dans une tâche')
        egal(dialogues, #S.dialogues, 'aucune fenêtre avant la tâche')
        local vus = {}
        local n = jouer({
            function(args, q)
                egal('Ajouter une demande', args.title)
                egal('Garder', args.actionVerb)
                egal(q, args.actionBinding.enabled.bind_to_object, 'le bouton suit la validité')
                egal('valide', args.actionBinding.enabled.key)
                egal('Éclaircis le sujet, assombris les bords.', q.texte, 'le texte du champ')
                egal('', q.nom)
                egal(Stockage.NOM_VIDE, q.erreur, 'nom vide : dit tout de suite')
                egal(false, q.valide)
                -- Les champs de la fenêtre : Nom, Description, Texte (plusieurs lignes), le refus.
                local champs = {}
                for _, v in ipairs(vues(args.contents)) do
                    if v.genre == 'edit_field' then
                        champs[#champs + 1] = v.args.value.key .. ':' .. tostring(v.args.height_in_lines or 1)
                    end
                end
                egal('nom:1 description:1 texte:6', table.concat(champs, ' '))
                liee(args.contents, 'static_text', 'erreur')
                -- Un nom pris, autrement écrit : refusé en direct.
                q.nom = 'portrait INTERIEUR'
                egal(Stockage.NOM_PRIS, q.erreur)
                egal(false, q.valide)
                -- Le bouton cliqué quand même (actionBinding ignoré) : refusé, la fenêtre rouverte.
                vus[#vus + 1] = q.nom
                return 'ok'
            end,
            function(_, q)
                egal('portrait INTERIEUR', q.nom, 'les champs gardés')
                egal(Stockage.NOM_PRIS, q.erreur, 'la raison dite')
                q.nom = 'Tireur doux'
                q.texte = '   '
                egal(Stockage.TEXTE_VIDE, q.erreur)
                q.texte = 'Éclaircis le sujet, assombris les bords.'
                q.description = 'radial inversé léger'
                egal('', q.erreur)
                egal(true, q.valide)
                return 'ok'
            end,
        }, function() lancerTaches(taches) end)
        egal(2, n, 'deux fenêtres : refusée, puis gardée')
        local lu, noms = demandesDuFichier()
        egal('Portrait intérieur | Tireur doux', noms)
        egal('radial inversé léger', lu.demandes[2].description)
        egal(Fenetre.DEMANDE_GARDEE, p.message)
        local items = p.mesDemandesItems
        egal('Tireur doux — radial inversé léger', items[4].title, 'le menu refait')
        egal('Éclaircis le sujet, assombris les bords.', p.saisie, 'le champ garde son texte')
        -- Annuler ne garde rien.
        jouer({ function(_, q) q.nom = 'Autre' return 'cancel' end }, function() Fenetre.ajouterDemande({ texte = 'x' }) end)
        egal('Portrait intérieur | Tireur doux', select(2, demandesDuFichier()))
    end)
end)

essai('Renommer… : choisir une demande, puis changer son nom, sa description et son texte ; un nom pris refusé ; le sien, autrement écrit, gardé', function()
    ranger(PORTRAIT, PAYSAGE)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local menu = liee(contenu, 'popup_menu', 'mesDemandes')
        local taches = #S.taches
        S.choisir(menu, 'renommer')
        jouer({
            function(args, q)
                egal('Renommer une demande', args.title)
                egal('Enregistrer', args.actionVerb)
                local choix = liee(args.contents, 'popup_menu', 'choix')
                local noms = {}
                for _, it in ipairs(choix.args.items) do
                    noms[#noms + 1] = it.title
                end
                egal('Paysage du soir | Portrait intérieur', table.concat(noms, ' | '), 'triées par nom')
                egal(1, q.choix)
                egal(PAYSAGE.nom, q.nom)
                egal(PAYSAGE.texte, q.texte)
                egal('', q.erreur)
                -- L'autre demande choisie : ses champs.
                q.choix = 2
                egal(PORTRAIT.nom, q.nom)
                egal(PORTRAIT.description, q.description)
                egal(PORTRAIT.texte, q.texte)
                -- Le nom de l'autre : refusé ; le sien autrement écrit : gardé.
                q.nom = 'paysage du soir'
                egal(Stockage.NOM_PRIS, q.erreur)
                q.nom = 'PORTRAIT intérieur'
                egal('', q.erreur)
                q.nom = 'Portrait au studio'
                q.description = 'lumière douce'
                q.texte = 'Retouche ce portrait au studio : peau douce, fond neutre.'
                return 'ok'
            end,
        }, function() lancerTaches(taches) end)
        local lu, noms = demandesDuFichier()
        egal('Paysage du soir | Portrait au studio', noms)
        egal('lumière douce', lu.demandes[2].description)
        egal('Retouche ce portrait au studio : peau douce, fond neutre.', lu.demandes[2].texte)
        egal(Fenetre.DEMANDE_CHANGEE, p.message)
        egal('Portrait au studio — lumière douce', p.mesDemandesItems[4].title)
    end)
end)

essai('Supprimer… : choisir une demande (son texte montré), puis confirmer ; Annuler ne retire rien ; la dernière retirée, le menu redevient vide', function()
    ranger(PORTRAIT, PAYSAGE)
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p, contenu)
        local menu = liee(contenu, 'popup_menu', 'mesDemandes')
        local function supprimer(choix, confirmation)
            local taches = #S.taches
            S.choisir(menu, 'supprimer')
            S.reponseConfirm, S.confirmation = confirmation, nil
            jouer({ function(args, q)
                egal('Supprimer une demande', args.title)
                q.choix = choix
                egal(Stockage.lireDemandes()[choix].texte, q.apercu, 'son texte montré')
                return 'ok'
            end }, function() lancerTaches(taches) end)
            S.reponseConfirm = nil
        end
        supprimer(2, 'cancel')
        contient(S.confirmation[1], '« ' .. PORTRAIT.nom .. ' »', 'la confirmation nomme la demande')
        egal('Paysage du soir | Portrait intérieur', select(2, demandesDuFichier()), 'Annuler : rien de retiré')
        supprimer(2, 'ok')
        egal('Paysage du soir', select(2, demandesDuFichier()))
        egal(Fenetre.DEMANDE_RETIREE, p.message)
        supprimer(1, 'ok')
        egal('', select(2, demandesDuFichier()))
        egal(Fenetre.AUCUNE_DEMANDE_GARDEE, p.mesDemandesItems[3].title, 'le menu vide')
        egal(false, p.mesDemandesItems[3].enabled)
        -- Plus de demande : Renommer… et Supprimer… le disent, sans fenêtre.
        local dialogues = #S.dialogues
        egal(false, Fenetre.renommerDemande())
        egal(false, Fenetre.supprimerDemande())
        egal(dialogues, #S.dialogues)
        egal(Fenetre.AUCUNE_DEMANDE, p.message)
    end)
end)

essai('Fichier : mes-demandes.json écrit d\'un coup (provisoire, puis renommé), format 1, trié ; relu à chaque ouverture ; ses tables neuves', function()
    ranger(PAYSAGE, PORTRAIT)
    vrai(not Fichiers.existe(FICHIER .. '.provisoire'), 'aucun fichier provisoire laissé')
    local lu = Json.decode(Fichiers.lire(FICHIER))
    egal(1, lu.format)
    egal(Stockage.FORMAT_DEMANDES, lu.format)
    egal(2, #lu.demandes)
    local suffixe = '/Library/Application Support/Developpeur/mes-demandes.json'
    egal(suffixe, FICHIER:sub(-#suffixe))
    egal(Chemins.racine() .. '/mes-demandes.json', FICHIER)
    local liste = Stockage.lireDemandes()
    for _, d in ipairs(liste) do
        egal(nil, getmetatable(d), 'une demande relue : table neuve')
    end
    egal(nil, getmetatable(liste))
    -- Le fichier changé hors de la fenêtre : relu à l'ouverture suivante.
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p)
        egal(PAYSAGE.nom .. ' — ', p.mesDemandesItems[3].title:sub(1, #PAYSAGE.nom + #' — '))
    end)
    Fichiers.ecrire(FICHIER, Json.encode({ format = 1, demandes = { { nom = 'Nuit', description = '', texte = 'Débruite, puis les ombres.' } } }))
    ouvrirFenetre(function(p)
        egal('Nuit', p.mesDemandesItems[3].title, 'relu à l\'ouverture')
        egal('Ajouter…', p.mesDemandesItems[5].title)
    end)
    -- Une entrée sans nom ou sans texte, ou en double, n'est pas lue.
    Fichiers.ecrire(FICHIER, Json.encode({ format = 1, demandes = { { nom = '', texte = 'x' }, { nom = 'A', texte = '' },
        { nom = 'B', texte = 'b' }, { nom = 'b', texte = 'autre' } } }))
    local propres = Stockage.lireDemandes()
    egal(1, #propres)
    egal('b', propres[1].texte)
end)

essai('Fichier illisible : rien n\'est perdu en silence ; dit au journal et au bandeau, mis de côté avant la première écriture, son contenu gardé', function()
    ecrireFichier('{ pas du JSON')
    for _, f in ipairs(Fichiers.entrees(Chemins.racine())) do
        if f:find('^mes%-demandes%-illisible') then
            Fichiers.supprimer(Chemins.racine() .. '/' .. f)
        end
    end
    journal = {}
    local liste, illisible = Stockage.lireDemandes()
    egal(0, #liste)
    egal(true, illisible)
    contient(table.concat(journal, ' | '), 'mes-demandes.json illisible')
    egal('{ pas du JSON', Fichiers.lire(FICHIER), 'la lecture ne touche à rien')
    -- Un autre format n'est pas lu non plus.
    ecrireFichier(Json.encode({ format = 2, demandes = {} }))
    egal(true, select(2, Stockage.lireDemandes()))
    ecrireFichier('{ pas du JSON')
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function(p)
        egal(Fenetre.DEMANDES_ILLISIBLES, p.message, 'dit au bandeau')
        egal(Fenetre.AUCUNE_DEMANDE_GARDEE, p.mesDemandesItems[3].title)
    end)
    local ok = Stockage.garderDemande(PORTRAIT)
    vrai(ok, 'gardée')
    local aCote
    for _, f in ipairs(Fichiers.entrees(Chemins.racine())) do
        if f:find('^mes%-demandes%-illisible%-%d+%.json$') then
            aCote = Chemins.racine() .. '/' .. f
        end
    end
    vrai(aCote, 'mis de côté')
    egal('{ pas du JSON', Fichiers.lire(aCote), 'son contenu gardé')
    egal(PORTRAIT.nom, select(2, demandesDuFichier()))
    contient(table.concat(journal, ' | '), 'mis de côté')
    -- Un fichier vide n'est pas illisible : rien à perdre.
    ecrireFichier('')
    egal(false, select(2, Stockage.lireDemandes()))
end)

essai('« ＋ Garder la demande » retiré (correctif 1.3.6) : plus de fonction ; un tour qui a retouché et écrit la ligne « Demande à garder » n\'a pas de ligne d\'actions ; avec une notation, « ☆ Voir la note » seul', function()
    for nom, module in pairs({ demandeAGarder = Conversation, preparerDemande = Conversation, estRetouche = Conversation,
        LIGNE_DEMANDE = Conversation, nomLibre = Stockage, garderDemande = Fenetre, lireActions = Fenetre,
        valeurActions = Fil }) do
        egal(nil, module[nom], nom .. ' retiré')
    end
    egal(nil, Fil.lireActions, 'Fil.lireActions retiré')
    egal(nil, D.garderDemande, 'sa largeur retirée')
    egal(nil, D.ecartActions, "l'écart entre deux boutons d'actions retiré")
    local texte = element('claude', { texte = "C'est fait.\n" .. LIGNE })
    egal(nil, ligneActions(conversation(retouche(), texte)), "une retouche et la ligne : pas de ligne d'actions")
    egal(nil, ligneActions(conversation(retouche('match_series'), texte)), 'match_series non plus')
    local notation = element('notation', { etat = 'fait', notes = { { photo = 4961, note = 3 } } })
    local l = ligneActions(conversation(notation, retouche(), texte))
    egal('note', l.actions, 'avec une notation : la note seule')
    egal(nil, l.demande, 'sans indice de demande')
    -- La ligne de Claude reste un texte comme un autre, dans le fil.
    local montre = {}
    for _, x in ipairs(Fil.lignes(conversation(retouche(), texte), D.texteFil)) do
        montre[#montre + 1] = x.texte
    end
    contient(table.concat(montre, '\n'), 'Demande à garder', 'le texte de Claude montré tel quel')
end)

-- Les boutons de la ligne i de la grille (`x..i`), par titre.
local function boutonsMontres(contenu, i)
    local montres = {}
    for _, v in ipairs(vues(contenu)) do
        if S.BOUTONS[v.genre] and type(v.args.visible) == 'table' and table.concat(S.cles(v.args.visible), ' ') == 'x' .. i
            and S.montreeDansFenetre(v) then
            montres[#montres + 1] = v.args.title
        end
    end
    table.sort(montres)
    return table.concat(montres, ' ')
end

essai('Fenêtre : plus de bouton « ＋ Garder la demande » (ni montré, ni caché) ; la ligne d\'actions d\'une notation montre « ☆ Voir la note » seul', function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.charger()
    Moteur.nouvelle()
    local notation = element('notation', { etat = 'fait', notes = { { photo = 4961, note = 3 } } })
    Moteur.courante = conversation(notation, retouche(), element('claude', { texte = "C'est fait.\n" .. LIGNE }))
    ouvrirFenetre(function(p, contenu)
        Fenetre.rafraichir()
        for _, v in ipairs(vues(contenu)) do
            vrai(not (S.BOUTONS[v.genre] and tostring(v.args.title):find('Garder la demande', 1, true)), 'aucun bouton Garder la demande')
        end
        local i
        for k = 1, D.lignes do
            if p['x' .. k] ~= '' then
                i = k
            end
        end
        vrai(i, "une ligne d'actions dans la grille")
        egal('note', p['x' .. i])
        egal('☆ Voir la note', boutonsMontres(contenu, i))
    end)
    Moteur.courante = nil
end)

essai('Consignes : plus de section « Demande à garder », ni de ligne à écrire, ni dans la Demande rapide ; plus de section Leçon ; le texte sous 7 500', function()
    local texte = Consignes.texte
    egal(nil, texte:find('Demande à garder', 1, true), 'plus de section Demande à garder')
    egal(nil, texte:find('<ta demande>', 1, true), 'plus de gabarit')
    for _, quoi in ipairs({ 'rapide', 'rapidePhoto' }) do
        egal(nil, Consignes[quoi]:find('Demande à garder', 1, true), quoi)
        contient(Consignes[quoi], 'Pas de titre.', quoi)
    end
    egal(nil, texte:find('\n## Leçon de la photo\n', 1, true), 'plus de section Leçon')
    vrai(Texte.longueur(texte) <= 7500, string.format('plafond des consignes : %d', Texte.longueur(texte)))
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
end)

essai('Bandeau : chaque message de Mes demandes y tient en entier, sur ses deux lignes ; les refus des fenêtres sont des phrases', function()
    local place = D.bandeau - Fil.MARGE
    for _, m in ipairs({ Fenetre.DEMANDE_DANS_LE_CHAMP, Fenetre.DEMANDE_GARDEE, Fenetre.DEMANDE_CHANGEE, Fenetre.DEMANDE_RETIREE,
        Fenetre.AUCUNE_DEMANDE, Fenetre.DEMANDES_ILLISIBLES, Fenetre.CLAUDE_TRAVAILLE }) do
        local montre = Fenetre.texteBandeau(m, D.bandeau)
        egal(m, (montre:gsub('\n', ' ')), 'en entier : ' .. m)
        vrai(select(2, montre:gsub('\n', '')) <= 1, m .. ' : deux lignes au plus')
        for ligne in (montre .. '\n'):gmatch('([^\n]*)\n') do
            vrai(Fil.largeur(ligne, 'petit') <= place, ligne)
        end
    end
    for _, m in ipairs({ Stockage.NOM_VIDE, Stockage.NOM_PRIS, Stockage.TEXTE_VIDE, Stockage.DEMANDE_INTROUVABLE }) do
        vrai(not m:find('^%l') and m:sub(-1) == '.', 'une phrase : ' .. m)
    end
end)

essai('uninstall.sh : --tout retire mes-demandes.json (tout le dossier) ; sans --tout, il reste et le script le dit', function()
    local script = assert(Fichiers.lire(dossierTests .. '/../../../uninstall.sh'), 'uninstall.sh')
    local entete = script:match('^(.-)\nset %-euo pipefail')
    contient(entete, '(mes-demandes.json)', 'en-tête')
    local travail = script:match('TRAVAIL=%((.-)\n%)')
    vrai(not travail:find('demandes', 1, true), "mes-demandes.json n'est pas un fichier de travail")
    contient(script, 'retirer "${DEST_DIR}"', '--tout retire tout le dossier')
    local gardes = script:match('GARDES%+=%("%${DEST_DIR} %((.-)%)"%)')
    contient(gardes, 'mes demandes', 'gardé et dit')
end)

essai('Simulation : un élément de menu sans titre refusé à la création ; S.choisir refuse un élément grisé, un séparateur, une valeur absente', function()
    local f = S.modules.LrView.osFactory()
    refuse(function() f:popup_menu { items = { { value = 1 } } } end, 'sans title ni separator')
    f:popup_menu { items = { { separator = true }, 'texte', { title = 'a', value = 1, enabled = false } } }
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ranger()
    ouvrirFenetre(function(p, contenu)
        local menu = liee(contenu, 'popup_menu', 'mesDemandes')
        refuse(function() S.choisir(menu, 'aucune') end, 'grisé', 'Aucune demande gardée ne se choisit pas')
        refuse(function() S.choisir(menu, 'renommer') end, 'aucun élément', 'pas de Renommer… sans demande')
        refuse(function() S.choisir(menu, nil) end, 'aucun élément', 'un séparateur ne se choisit pas')
        -- Une liste refaite sans titre à un élément : refusée à la nouvelle valeur.
        refuse(function() p.mesDemandesItems = { { value = 'x' } } end, 'sans title ni separator')
        S.refusDeLaFenetre()
    end)
end)

-- Fin -------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
