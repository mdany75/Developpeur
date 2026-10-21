-- essais-pourquoi.lua : « Pourquoi ? » dans la fenêtre Claude (1.3, lot 12), hors de Lightroom
-- (LuaJIT, Lightroom simulé par Simulation.lua) : les étapes lues dans le fil (Conversation :
-- raison, but, etape_id et photo de la réponse, annulées par undo_last, défaites par
-- revert_to_original, conversation de la 1.2 relue sans id), leur repère « · Pourquoi ? » (Fil),
-- leur stockage en tableaux (Stockage), l'onglet Pourquoi ? (clic sur une étape, avant/après dans
-- l'aperçu, carte, ◀ ▶, Détail…, Agrandir à deux images, mode suivre, images arrivées quand
-- Etapes.version change, aucune bascule automatique), Etapes.actifPour posé à l'ouverture, et les
-- consignes de la raison. Les images de l'étape (Etapes.images) et leurs réductions (Images) sont
-- remplacées ici ; essais-integration.lua les éprouve pour de bon (sips). Ni Claude, ni quota.
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

-- Toutes les vues d'un arbre.
local function vues(contenu)
    local liste = {}
    local function parcourir(v)
        liste[#liste + 1] = v
        for _, enfant in ipairs(v.args or {}) do
            if type(enfant) == 'table' and enfant.genre then
                parcourir(enfant)
            end
        end
    end
    parcourir(contenu)
    return liste
end

-- Le bouton de ce titre (titre lié lu dans `p`) ; `cleActif` : celui dont `enabled` suit cette clé.
local function bouton(contenu, p, titre, cleActif)
    for _, v in ipairs(vues(contenu)) do
        local t = v.args.title
        if type(t) == 'table' and t.liaison then
            t = p[t.key]
        end
        if S.BOUTONS[v.genre] and t == titre
            and (not cleActif or (type(v.args.enabled) == 'table' and v.args.enabled.key == cleActif)) then
            return v
        end
    end
    error('bouton introuvable : ' .. tostring(titre), 2)
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre ; une
-- fenêtre qui relancerait sans fin la même lecture fait échouer l'essai.
local function lancerTaches(depuis)
    local i = depuis + 1
    while i <= #S.taches do
        vrai(i - depuis <= 100, 'des tâches sans fin')
        local t = S.taches[i]
        S.taches[i] = function() end
        t()
        i = i + 1
    end
end

local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Etapes = require 'Etapes'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Images = require 'Images'
local Json = require 'Json'
local Notation = require 'Notation'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false

-- Les images des étapes (Etapes.images du module) : `images[id]` donne l'état d'une étape (par
-- défaut, prête : avant et après), ses fichiers rangés comme le module les range (Etapes/<photo>/) ;
-- les demandes reçues sont gardées. Les réductions (Images) : un chemin tiré de la photo et du nom,
-- sans sips, faites sur la copie de la fenêtre, jamais dans le dossier Etapes du module (dont le
-- ménage ne voit pas les réductions, rangées dans .vignettes).
local images, demandes = {}, {}
local imagesVraies, vignetteVraie, grandeVraie = Etapes.images, Images.vignette, Images.grande
Etapes.images = function(photo, id)
    demandes[#demandes + 1] = Conversation.clePhoto(photo) .. '/' .. tostring(id)
    local e = images[id] or { etat = 'pret', avant = true, apres = true }
    local dossier = Chemins.etapes() .. '/' .. Conversation.clePhoto(photo)
    Fichiers.creerDossier(dossier)
    local avant, apres = e.avant and (id .. '-avant.jpg') or nil, e.apres and (id .. '-apres.jpg') or nil
    for _, nom in ipairs({ avant or false, apres or false }) do
        if nom then
            Fichiers.ecrire(dossier .. '/' .. nom, 'jpeg de ' .. nom)
        end
    end
    return { dossier = dossier, etat = e.etat, raison = e.raison, avant = avant, apres = apres }
end
-- La photo de la copie (Temporaire/Pourquoi/<photo>/<lecture>/<nom>), qui doit être là.
local function photoDeLaCopie(dossier, nom)
    vrai(not dossier:find(Chemins.etapes(), 1, true), 'réduction dans le dossier Etapes du module : ' .. dossier)
    vrai(Fichiers.lire(dossier .. '/' .. nom) == 'jpeg de ' .. nom, 'copie absente : ' .. dossier .. '/' .. nom)
    return assert(dossier:match('/Pourquoi/([^/]+)/[^/]+$'), dossier)
end
Images.vignette = function(dossier, nom, cote)
    return '/etapes/' .. photoDeLaCopie(dossier, nom) .. '/.vignettes/' .. nom:gsub('%.jpg$', '') .. '-' .. cote .. '.jpg'
end
Images.grande = function(dossier, nom, largeur, hauteur)
    return '/etapes/' .. photoDeLaCopie(dossier, nom) .. '/.vignettes/' .. nom:gsub('%.jpg$', '') .. '-grande.jpg', 540, 360
end

local function photoActive(id, nom)
    local photo = S.photo(id, nom)
    S.photoActive, S.selection = photo, { photo }
    return photo
end

-- Ouvre la fenêtre Claude et appelle fn(p, args) pendant qu'elle est ouverte ; une erreur de fn
-- remonte une fois la fenêtre fermée.
local function ouvrirFenetre(fn)
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(Fenetre.p, args) end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    if erreur then
        error(erreur, 0)
    end
end

-- Un appel d'outil dans le fil, puis sa réponse (`reponse` : table encodée comme le connecteur la
-- rend, ou texte) ; sans réponse, l'appel reste en cours. Rend l'indice de son élément.
local function appel(c, id, outil, entree, reponse, erreur)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__' .. outil,
        entree = entree or {} } } })
    local indice = #c.elements
    while c.elements[indice].genre ~= 'outil' do
        indice = indice - 1
    end
    if reponse ~= nil then
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id,
            textes = { type(reponse) == 'string' and reponse or Json.encode(reponse) }, images = {}, erreur = erreur == true } } })
    end
    return indice
end

-- Un view_photo et son image (rangée sous « <id>.jpg ») : sa ligne d'outil et une ligne d'image.
local function vuePhoto(c, id)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = id, nom = 'mcp__developpeur__view_photo',
        entree = { size = 1568 } } } })
    local indice = #c.elements
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = id, textes = { '{}' }, images = { { donnees = 'x' } },
        erreur = false } } }, nil, function() return id .. '.jpg' end)
    return indice
end

local function changement(cle, avant, apres, libelle)
    return { cle = cle, avant = avant, apres = apres, libelle = libelle }
end

-- La réponse d'une commande d'écriture telle que le connecteur la rend (resultatsPlans du module,
-- libellés ajoutés) : une étape par photo, etape_id null sans étape.
local function ecriture(etape, liste)
    local resultats = Json.tableau()
    for _, x in ipairs(liste) do
        resultats[#resultats + 1] = { photo = { id = x[1], fichier = x[2] }, etape = 'Claude · ' .. etape, etape_id = x[3] or Json.null,
            changements = Json.tableau(x[4] or {}), remarques = Json.tableau() }
    end
    return { mode = 'appliquer directement', resultats = resultats }
end

local function balance(c, id, etapeId, photo)
    return appel(c, id, 'apply_settings', { step_name = 'passe 1 : balance', reason = 'La photo tirait vers le bleu : des blancs neutres.',
        settings = { Temperature = 5600 } }, ecriture('passe 1 : balance', { { photo or 4961, 'DSCF4961.RAF', etapeId,
        { changement('Temperature', 5200, 5600, 'Température') } } }))
end

local function ciel(c, id, etapeId)
    return appel(c, id, 'add_mask', { step_name = 'passe 2 : ciel', reason = 'Ciel brûlé à 3 % : hautes lumières baissées.', kind = 'sky' },
        ecriture('passe 2 : ciel', { { 4961, 'DSCF4961.RAF', etapeId, { changement('Highlights2012', 0, -40, 'Hautes lumières') } } }))
end

local function textesDe(liste)
    local morceaux = {}
    for _, x in ipairs(liste) do
        morceaux[#morceaux + 1] = tostring(x.id) .. (x.annulee and (':' .. x.annulee) or '')
    end
    return table.concat(morceaux, ' ')
end

-- La ligne du fil d'un élément (indice dans la fenêtre de lecture) et la ligne elle-même.
local function ligneDe(element)
    for i = 1, Fenetre.T.lignes do
        local l = Fenetre.lignes[Fenetre.premiere + i - 1]
        if l and l.element == element and not l.image then
            return i, l
        end
    end
    error('ligne introuvable : élément ' .. tostring(element), 2)
end

-- Conversation ---------------------------------------------------------------------------------

essai("Conversation : étapes lues de la réponse (etape_id, photo), raison et step_name de l'entrée ; ni aperçu, ni erreur, ni rien d'écrit", function()
    local c = Conversation.nouvelle()
    local i = balance(c, 'b1', 'E1')
    local e = c.elements[i]
    egal('La photo tirait vers le bleu : des blancs neutres.', e.raison)
    egal('passe 1 : balance', e.etape)
    egal(1, #e.etapes)
    egal('E1', e.etapes[1].id)
    egal(4961, e.etapes[1].photo)
    egal('DSCF4961.RAF', e.etapes[1].fichier)
    egal('Claude · passe 1 : balance', e.etapes[1].nom)
    -- Les changements gardent leur clé (1.3), à l'étape comme à l'élément.
    egal('Temperature', e.etapes[1].changements[1].cle)
    egal('Température', e.changements[1].libelle)
    egal('Temperature', e.changements[1].cle)
    egal(Texte.nombre(5600), e.changements[1].apres)
    vrai(Conversation.estEtape(e), 'une étape')
    -- choose_variant : la réponse du module à plat.
    i = appel(c, 'v1', 'choose_variant', { name = 'chaude', step_name = 'variante chaude', reason = 'Plus chaleureuse.' },
        { photo = { id = 4961, fichier = 'DSCF4961.RAF' }, etape = 'Claude · variante chaude', etape_id = 'E9', instantane = 'Claude · chaude',
            changements = Json.tableau() })
    egal('E9', c.elements[i].etapes[1].id)
    vrai(Conversation.estEtape(c.elements[i]))
    -- Une proposition seulement (preview) : rien de gardé, pas une étape.
    i = appel(c, 'm1', 'add_mask', { preview = true, step_name = 'essai', reason = 'Voir.' }, { chemin = '/tmp/x.jpg' })
    egal(nil, c.elements[i].raison)
    egal(nil, c.elements[i].etapes)
    egal(false, Conversation.estEtape(c.elements[i]))
    -- Un appel en erreur, ou qui n'écrit rien (etape_id null) : pas une étape.
    i = balance(c, 'b2', 'E2')
    c.elements[i].etat = 'erreur'
    egal(false, Conversation.estEtape(c.elements[i]), 'en erreur')
    i = appel(c, 'b3', 'apply_settings', { step_name = 'rien', reason = 'Déjà juste.' }, ecriture('rien', { { 4961, 'DSCF4961.RAF', nil } }))
    egal(0, #c.elements[i].etapes)
    egal(false, Conversation.estEtape(c.elements[i]), 'rien écrit')
    -- En cours, avec son but : une étape dès l'appel (sa ligne a déjà son repère) ; pas match_series,
    -- dont la réponse ne porte pas d'etape_id.
    i = appel(c, 'b4', 'apply_settings', { step_name = 'passe 3 : peau', reason = 'Peau rougie.' })
    vrai(Conversation.estEtape(c.elements[i]), 'en cours')
    i = appel(c, 's1', 'match_series', { step_name = 'série', reason = 'Même rendu.' })
    egal(false, Conversation.estEtape(c.elements[i]), 'match_series en cours')
    -- Un outil qui n'écrit pas d'étape.
    i = appel(c, 'w1', 'view_photo', { size = 1568 }, { etape_id = 'X', photo = { id = 4961 } })
    egal(false, Conversation.estEtape(c.elements[i]), 'view_photo')
end)

essai('Conversation : copy_settings sur deux photos, une étape par photo avec ses changements ; Conversation.etapes par photo', function()
    local c = Conversation.nouvelle()
    balance(c, 'b1', 'E1')
    local i = appel(c, 'k1', 'copy_settings', { step_name = 'série', reason = 'Même balance.', target_ids = { 4961, 4962 } },
        ecriture('série', { { 4961, 'DSCF4961.RAF', 'E2', { changement('Exposure2012', 0, 0.3, 'Exposition') } },
            { 4962, 'DSCF4962.RAF', 'E3', { changement('Exposure2012', 0, 0.5, 'Exposition') } } }))
    egal(2, #Conversation.photosEtape(c.elements[i]))
    local premiere = Conversation.etapes(c, 4961)
    egal('E1 E2', textesDe(premiere))
    local seconde = Conversation.etapes(c, '4962')
    egal('E3', textesDe(seconde), 'photo en texte ou en nombre')
    egal(Texte.nombre(0.5), seconde[1].changements[1].apres, 'les changements de sa photo')
    egal(Texte.nombre(0.3), premiere[2].changements[1].apres)
    egal('Même balance.', seconde[1].raison)
    egal('série', seconde[1].etape)
    egal('copy_settings', seconde[1].outil)
    egal(i, seconde[1].element)
    egal(c.elements[i].id, seconde[1].elementId)
    -- Un appel en cours compte pour toute photo, en dernier.
    appel(c, 'b9', 'apply_settings', { step_name = 'passe 3', reason = 'x' })
    local liste = Conversation.etapes(c, 4962)
    egal(2, #liste)
    egal(true, liste[2].enCours)
end)

essai('Conversation : annulée par un undo_last suivant (par son id ; par son nom, seulement sans id), défaite par revert_to_original', function()
    local c = Conversation.nouvelle()
    balance(c, 'b1', 'E1')
    ciel(c, 'c1', 'E2')
    balance(c, 'x1', 'E7', 4962)
    -- undo_last : l'étape défaite, par son id.
    appel(c, 'u1', 'undo_last', {}, { resultats = { { photo = { id = 4961, fichier = 'DSCF4961.RAF' }, annulee = true,
        etape = 'Claude · passe 2 : ciel', etape_id = 'E2' } } })
    egal('E1 E2:undo_last', textesDe(Conversation.etapes(c, 4961)))
    egal('E7', textesDe(Conversation.etapes(c, 4962)), "l'autre photo ne bouge pas")
    -- Une étape d'avant la 1.3 défaite (etape_id null), absente de ce fil : rien de marqué, pas
    -- même une étape du même nom qui a un id (elle l'aurait rendu à son annulation).
    appel(c, 'u2', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 1 : balance',
        etape_id = Json.null } } })
    egal('E1 E2:undo_last', textesDe(Conversation.etapes(c, 4961)), "sans id : pas une étape qui en a un")
    -- Une étape du même nom faite ailleurs (Claude Desktop) défaite : son id n'est pas dans ce fil.
    appel(c, 'u2b', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 1 : balance',
        etape_id = 'D5' } } })
    egal('E1 E2:undo_last', textesDe(Conversation.etapes(c, 4961)), "un id d'ailleurs : rien de marqué")
    appel(c, 'u2c', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 1 : balance',
        etape_id = 'E1' } } })
    egal('E1:undo_last E2:undo_last', textesDe(Conversation.etapes(c, 4961)))
    -- Un undo_last qui n'a rien défait ne marque rien.
    ciel(c, 'c2', 'E3')
    appel(c, 'u3', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = false } } })
    egal('E1:undo_last E2:undo_last E3', textesDe(Conversation.etapes(c, 4961)))
    -- revert_to_original : toutes les étapes d'avant de la photo remise, pas celles d'après.
    appel(c, 'r1', 'revert_to_original', {}, { resultats = { { photo = { id = 4961 }, remise = true } } })
    ciel(c, 'c3', 'E4')
    egal('E1:undo_last E2:undo_last E3:revert E4', textesDe(Conversation.etapes(c, 4961)))
    egal('E7', textesDe(Conversation.etapes(c, 4962)))
    -- Deux étapes du même nom, la dernière déjà défaite ailleurs (undo_last de Claude Desktop, que
    -- ce fil ne voit pas) : l'id retrouve la bonne, le nom aurait pris la dernière.
    local d = Conversation.nouvelle()
    balance(d, 'b1', 'F1')
    balance(d, 'b2', 'F2')
    appel(d, 'u1', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 1 : balance', etape_id = 'F1' } } })
    egal('F1:undo_last F2', textesDe(Conversation.etapes(d, 4961)), 'par son id')
end)

-- Une conversation telle que la 1.2 l'a rangée : ni raison, ni etape, ni etapes ; le détail garde
-- l'entrée et la réponse (JSON indenté, suivi d'une remarque du connecteur).
local function conversationDeLa12()
    local c = Conversation.nouvelle()
    local entree = Json.encode({ step_name = 'passe 1 : lumière', reason = 'Ombres bouchées : ombres relevées.', settings = { Shadows2012 = 30 } })
    local reponse = '{\n  "mode": "appliquer directement",\n  "resultats": [\n    {\n      "changements": [\n        {\n'
        .. '          "apres": 30,\n          "avant": 0,\n          "cle": "Shadows2012",\n          "libelle": "Ombres"\n        }\n'
        .. '      ],\n      "etape": "Claude · passe 1 : lumière",\n      "photo": {\n        "fichier": "DSCF4961.RAF",\n'
        .. '        "id": 4961\n      }\n    }\n  ]\n}\nUne version plus récente du connecteur est publiée.'
    c.elements = {
        { id = 'a', genre = 'outil', outil = 'apply_settings', etat = 'fait', texte = 'apply_settings · passe 1 : lumière', images = {},
            changements = {}, detail = entree .. '\n\n— Réponse —\n' .. reponse },
        { id = 'b', genre = 'outil', outil = 'add_mask', etat = 'fait', texte = 'add_mask · essai', images = {}, changements = {},
            detail = Json.encode({ preview = true, step_name = 'essai' }) .. '\n\n— Réponse —\n' .. '{"chemin": "/tmp/x.jpg"}' },
        { id = 'c', genre = 'outil', outil = 'undo_last', etat = 'fait', texte = 'undo_last', images = {}, changements = {},
            detail = '{}\n\n— Réponse —\n{\n  "resultats": [\n    {\n      "annulee": true,\n      "etape": "Claude · passe 1 : lumière",\n'
                .. '      "photo": {\n        "id": 4961\n      }\n    }\n  ]\n}' },
    }
    return c
end

essai('Conversation de la 1.2 (sans etape_id) : raison et changements relus dans le détail, sans id ; annulée par son nom', function()
    local c = conversationDeLa12()
    Stockage.enregistrer(c)
    local lue = Stockage.lire(c.id)
    egal(nil, lue.elements[1].etapes, 'rien de la 1.3 dans le fichier')
    vrai(Conversation.estEtape(lue.elements[1]), 'une étape relue')
    egal(false, Conversation.estEtape(lue.elements[2]), 'une proposition seulement')
    local liste = Conversation.etapes(lue, 4961)
    egal(1, #liste)
    local x = liste[1]
    egal(nil, x.id, 'sans id, donc sans images')
    egal(true, x.ancienne)
    egal('Ombres bouchées : ombres relevées.', x.raison)
    egal('passe 1 : lumière', x.etape)
    egal('DSCF4961.RAF', x.fichier)
    egal('Ombres', x.changements[1].libelle)
    egal(Texte.nombre(30), x.changements[1].apres)
    egal('undo_last', x.annulee, 'annulée par son nom')
    -- Le fil la montre comme une étape.
    local _, ligne = nil, nil
    for _, l in ipairs(Fil.lignesElement(lue.elements[1], 1, 600)) do
        ligne = l
    end
    vrai(ligne.texte:sub(-#Fil.SUFFIXE_ETAPE) == Fil.SUFFIXE_ETAPE, ligne.texte)
end)

essai("Conversation de la 1.2 : une réponse illisible (coupée) se relit en peu d'essais, sans étape", function()
    local lignes = {}
    for k = 1, 400 do
        lignes[#lignes + 1] = '        { "cle": "Exposure2012", "avant": 0, "apres": ' .. k .. ' },'
    end
    local e = { id = 'z', genre = 'outil', outil = 'apply_settings', etat = 'fait', texte = 'apply_settings · x', images = {},
        changements = {}, detail = Json.encode({ step_name = 'x', reason = 'y' }) .. '\n\n— Réponse —\n{\n  "resultats": [\n'
            .. table.concat(lignes, '\n') }
    local decode, lectures = Json.decode, 0
    Json.decode = function(texte)
        lectures = lectures + 1
        return decode(texte)
    end
    local ok, etape = pcall(Conversation.estEtape, e)
    Json.decode = decode
    vrai(ok, tostring(etape))
    egal(false, etape, 'rien de lisible')
    -- L'entrée, la réponse entière, LIGNES_REMARQUES têtes au plus (et non une par ligne), puis la
    -- réponse lue pour ses étapes.
    vrai(lectures <= Conversation.LIGNES_REMARQUES + 3, lectures .. ' lectures du JSON')
end)

-- Fil -------------------------------------------------------------------------------------------

essai('Fil : une étape porte « · Pourquoi ? », pas un appel en erreur, un aperçu ni une proposition (preview) ; un long but le garde', function()
    local c = Conversation.nouvelle()
    local etape = balance(c, 'b1', 'E1')
    local erreur = balance(c, 'b2', 'E2')
    c.elements[erreur].etat = 'erreur'
    local apercu = appel(c, 'w1', 'view_photo', { size = 1568 }, '{}')
    local preview = appel(c, 'm1', 'add_mask', { preview = true, step_name = 'essai' }, '{}')
    local proposition = appel(c, 'p1', 'preview_settings', { reason = 'Plus chaud', settings = { Temperature = 5600 } }, '{}')
    local longue = appel(c, 'b3', 'apply_settings', { step_name = string.rep('passe très longue, ', 12), reason = 'x' },
        ecriture('longue', { { 4961, 'DSCF4961.RAF', 'E3' } }))
    local cache = {}
    local lignes = Fil.lignes(c, 610, cache)
    local function texteDe(element)
        for _, l in ipairs(lignes) do
            if l.element == element and l.genre == 'outil' then
                return l.texte
            end
        end
    end
    local function marquee(element)
        local t = texteDe(element) or ''
        return t:sub(-#Fil.SUFFIXE_ETAPE) == Fil.SUFFIXE_ETAPE
    end
    vrai(marquee(etape), "l'étape : " .. tostring(texteDe(etape)))
    vrai(not marquee(erreur), 'un appel en erreur')
    vrai(not marquee(apercu), 'un aperçu')
    vrai(not marquee(preview), 'une proposition (add_mask preview)')
    vrai(not marquee(proposition), 'preview_settings')
    for _, l in ipairs(lignes) do
        vrai(l.genre ~= 'etape', 'pas de genre de ligne de plus')
    end
    -- Le but long est coupé avant le repère, qui reste, dans la largeur.
    vrai(marquee(longue), 'repère gardé : ' .. tostring(texteDe(longue)))
    contient(texteDe(longue), '…  · Pourquoi ?')
    vrai(Fil.largeur(texteDe(longue), 'mono') <= 610 - Fil.MARGE, 'dans la largeur')
    egal('ok', lignes[1].icone or 'ok', "l'icône d'une ligne d'outil")
    -- Signature du cache : un appel en cours marqué, puis sans étape écrite, perd son repère.
    local enCours = appel(c, 'b4', 'apply_settings', { step_name = 'passe 4', reason = 'y' })
    lignes = Fil.lignes(c, 610, cache)
    vrai(marquee(enCours), 'en cours : marqué')
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'b4',
        textes = { Json.encode(ecriture('passe 4', { { 4961, 'DSCF4961.RAF', nil } })) }, images = {}, erreur = false } } })
    lignes = Fil.lignes(c, 610, cache)
    vrai(not marquee(enCours), 'rien écrit : plus de repère')
end)

-- Stockage --------------------------------------------------------------------------------------

essai('Stockage : etapes, annule et revenu écrits en tableaux (même vides), relus tels quels', function()
    local c = Conversation.nouvelle()
    balance(c, 'b1', 'E1')
    appel(c, 'b2', 'apply_settings', { step_name = 'rien', reason = 'x' }, ecriture('rien', { { 4961, 'DSCF4961.RAF', nil } }))
    appel(c, 'b3', 'apply_settings', { step_name = 'sans changement', reason = 'x' }, ecriture('sans', { { 4961, 'DSCF4961.RAF', 'E5' } }))
    appel(c, 'u1', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 1 : balance', etape_id = 'E1' } } })
    appel(c, 'r1', 'revert_to_original', {}, { resultats = Json.tableau() })
    Stockage.enregistrer(c)
    local texte = Fichiers.lire(Stockage.fichier(c.id))
    contient(texte, '"etapes":[]', 'une liste vide reste un tableau')
    contient(texte, '"revenu":[]')
    contient(texte, '"changements":[],"fichier":"DSCF4961.RAF","id":"E5"', "les changements d'une étape aussi")
    local lue = Stockage.lire(c.id)
    egal('E1', lue.elements[1].etapes[1].id)
    egal('Temperature', lue.elements[1].etapes[1].changements[1].cle)
    egal(0, #lue.elements[2].etapes)
    egal('E1', lue.elements[4].annule[1].id)
    egal(0, #lue.elements[5].revenu)
    egal('E1:undo_last E5', textesDe(Conversation.etapes(lue, 4961)), 'les étapes relues')
end)

-- Fenêtre ---------------------------------------------------------------------------------------

essai("Fenêtre : Etapes.actifPour posé à l'ouverture (fenêtre ouverte, puis le travail de son Claude)", function()
    Etapes.oublier()
    egal(false, Etapes.actif({}), 'jamais ouverte : aucune capture')
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    ouvrirFenetre(function()
        egal(true, Etapes.actif({}), 'fenêtre ouverte')
        prefs.avantApresEtapes = false
        egal(false, Etapes.actif({}), 'case décochée')
        prefs.avantApresEtapes = true
    end)
    egal(false, Etapes.actif({}), 'fenêtre fermée, Claude au repos')
    Moteur.travaille = true
    egal(true, Etapes.actif({}), 'fenêtre fermée, son Claude au travail')
    Moteur.travaille = false
end)

essai("Fenêtre : un clic sur une étape ouvre l'onglet Pourquoi ? ; l'après, puis l'avant ; Étape n sur N ; ◀ ▶ ; Détail… ; Note rend l'aperçu d'avant", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local apercu = vuePhoto(c, 'w1')
    local premiere = balance(c, 'b1', 'E1')
    local seconde = ciel(c, 'c1', 'E2')
    balance(c, 'x1', 'E7', 4962)
    demandes = {}
    ouvrirFenetre(function(p, args)
        Fenetre.rafraichir()
        egal('notation', p.onglet)
        -- L'aperçu de l'onglet Note : la photo active (une image de Claude existe, ◀ y mène).
        local defaut = p.legendeApercu
        egal('<EM>DSCF4961.RAF</EM>', defaut)
        egal(true, p.peutPrecedente)
        local n, l = ligneDe(premiere)
        vrai(l.texte:sub(-#Fil.SUFFIXE_ETAPE) == Fil.SUFFIXE_ETAPE, l.texte)
        -- Le clic : l'onglet Pourquoi ?, l'après de l'étape (lu dans une tâche), sa carte.
        local taches = #S.taches
        p.saisie = 'Texte validé par le clic'
        Fenetre.cliquerLigne(n)
        egal(nil, Fenetre.envoiAuto, 'le clic n\'envoie pas la demande')
        p.saisie = ''
        egal('apercu', p.onglet, "l'onglet Aperçu (l'ancien Pourquoi ?)")
        egal('Étape 1 sur 2 · avant/après en préparation…', p.legendeApercu, 'pendant la lecture')
        lancerTaches(taches)
        egal('4961/E1', demandes[#demandes], 'les images de cette étape')
        egal('/etapes/4961/.vignettes/E1-apres-660.jpg', p.imageApercu, "l'après, au cadre de l'aperçu")
        egal('Étape 1 sur 2 · après', p.legendeApercu)
        egal(true, p.aImage)
        egal(false, p.peutPrecedente, "les ◀ ▶ de l'aperçu sont coupés")
        egal(false, p.peutSuivante)
        egal('Étape 1 sur 2 · passe 1 : balance', p.etapeTitre)
        egal('DSCF4961.RAF · apply_settings', p.etapeSousTitre)
        local texte = p.etapeTexte:gsub('\n', ' ')
        contient(texte, 'Pourquoi : La photo tirait vers le bleu : des blancs neutres.')
        contient(texte, 'Ce qui a changé')
        contient(texte, 'Température : ' .. Texte.nombre(5200) .. ' → ' .. Texte.nombre(5600))
        vrai(not texte:find("Pas d'avant/après", 1, true), 'les images sont là')
        egal(false, p.etapePrecedente)
        egal(true, p.etapeSuivante)
        egal(true, p.etapeAImages)
        egal(true, p.etapeADetail)
        egal("Voir l'avant", p.titreBascule)
        -- ◀ ▶ de l'aperçu : rien dans l'onglet Pourquoi ? (ni ici, ni pour l'onglet Note ensuite).
        Fenetre.changerImage(-1)
        egal('Étape 1 sur 2 · après', p.legendeApercu)
        egal(true, Fenetre.voirActive, "◀ : l'aperçu de l'onglet Note n'a pas bougé")
        Fenetre.changerImage(1)
        egal(true, Fenetre.voirActive, "▶ : l'aperçu de l'onglet Note n'a pas bougé")
        egal(nil, Fenetre.indiceImage)
        -- Voir l'avant, puis Voir l'après.
        bouton(args.contents, p, "Voir l'avant", 'etapeAImages').args.action()
        egal('/etapes/4961/.vignettes/E1-avant-660.jpg', p.imageApercu, "l'avant")
        egal('Étape 1 sur 2 · avant', p.legendeApercu)
        egal("Voir l'après", p.titreBascule)
        bouton(args.contents, p, "Voir l'après", 'etapeAImages').args.action()
        egal('Étape 1 sur 2 · après', p.legendeApercu)
        -- ▶ : l'étape suivante de la même photo (pas celle de 4962).
        taches = #S.taches
        bouton(args.contents, p, '▶', 'etapeSuivante').args.action()
        lancerTaches(taches)
        egal('Étape 2 sur 2 · passe 2 : ciel', p.etapeTitre)
        egal('/etapes/4961/.vignettes/E2-apres-660.jpg', p.imageApercu)
        contient(p.etapeTexte:gsub('\n', ' '), 'Hautes lumières : 0 → -40')
        egal(true, p.etapePrecedente)
        egal(false, p.etapeSuivante)
        egal(seconde, Conversation.etapes(c, 4961)[2].element)
        bouton(args.contents, p, '◀', 'etapePrecedente').args.action()
        egal('Étape 1 sur 2 · passe 1 : balance', p.etapeTitre)
        -- Détail… : l'appel et sa réponse, dans une tâche.
        local dialogues = #S.dialogues
        taches = #S.taches
        bouton(args.contents, p, 'Détail…', 'etapeADetail').args.action()
        lancerTaches(taches)
        egal(dialogues + 1, #S.dialogues)
        egal('Claude · apply_settings · passe 1 : balance', S.dialogues[#S.dialogues].title)
        -- Un clic sur un autre outil ouvre toujours son détail ; l'étape montrée ne change pas.
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(apercu)))
        lancerTaches(taches)
        egal('Claude · view_photo', S.dialogues[#S.dialogues].title)
        egal('apercu', p.onglet)
        egal('Étape 1 sur 2 · passe 1 : balance', p.etapeTitre)
        -- Note : l'aperçu d'avant ; Pourquoi ? : la même étape.
        p.onglet = 'notation'
        egal(defaut, p.legendeApercu, "Note : l'aperçu d'avant")
        p.onglet = 'apercu'
        egal('Étape 1 sur 2 · après', p.legendeApercu, 'la même étape')
        -- Un clic sur l'étape de la seconde : la sienne (3e ligne, autre photo).
        Fenetre.cliquerLigne((ligneDe(seconde)))
        egal('Étape 2 sur 2 · passe 2 : ciel', p.etapeTitre)
        -- Une nouvelle conversation : plus d'étape, l'aide.
        Fenetre.nouvelle()
        Fenetre.rafraichir()
        egal(nil, Fenetre.etape)
        egal('', p.etapeTitre)
        egal(Fenetre.AIDE_ETAPE, (p.etapeTexte:gsub('\n', ' ')))
        egal(false, p.etapeADetail)
        vrai(not p.legendeApercu:find('Étape', 1, true), "l'aperçu d'avant : " .. p.legendeApercu)
        p.onglet = 'notation'
    end)
end)

essai("Fenêtre : l'étape d'une autre photo ; page par page ; sans images (classement, 1.2, rien de gardé, raison du module) ; annulée", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local autre = balance(c, 'x1', 'E7', 4962)
    local longue = appel(c, 'l1', 'apply_settings', { step_name = 'passe 2', reason = string.rep('Une raison longue. ', 60) },
        ecriture('passe 2', { { 4961, 'DSCF4961.RAF', 'E8' } }))
    local classement = appel(c, 'm1', 'set_metadata', { step_name = 'mots-clés', reason = 'Pour retrouver la photo.' },
        ecriture('mots-clés', { { 4961, 'DSCF4961.RAF', 'E9' } }))
    local rien = balance(c, 'b5', 'E10')
    local ia = ciel(c, 'c5', 'E11')
    images.E10 = { etat = 'inconnu' }
    images.E11 = { etat = 'manque', raison = 'calculs_ia' }
    appel(c, 'u1', 'undo_last', {}, { resultats = { { photo = { id = 4961 }, annulee = true, etape = 'Claude · passe 2 : ciel', etape_id = 'E11' } } })
    ouvrirFenetre(function(p, args)
        Fenetre.rafraichir()
        -- L'étape de 4962 (la photo active n'en fait pas partie) : sa photo.
        local taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(autre)))
        lancerTaches(taches)
        egal('Étape 1 sur 1 · passe 1 : balance', p.etapeTitre)
        egal('/etapes/4962/.vignettes/E7-apres-660.jpg', p.imageApercu)
        -- Une longue raison : page par page.
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(longue)))
        lancerTaches(taches)
        egal(true, p.etapeDescend, 'une page de plus')
        bouton(args.contents, p, '▼', 'etapeDescend').args.action()
        egal(true, p.etapeMonte)
        -- Un classement : pas d'avant/après, sans le demander au module.
        local avant = #demandes
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(classement)))
        lancerTaches(taches)
        egal(avant, #demandes, 'aucune lecture pour un classement')
        contient(p.etapeTexte:gsub('\n', ' '), "Pas d'avant/après : un classement ne change pas l'image.")
        egal('Étape 2 sur 4 · pas d\'avant/après', p.legendeApercu)
        egal(false, p.aImage)
        egal(false, p.etapeAImages)
        -- Rien de gardé (fenêtre fermée…), puis une raison du module.
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(rien)))
        lancerTaches(taches)
        contient(p.etapeTexte:gsub('\n', ' '), "Pas d'avant/après : " .. Fenetre.SANS_IMAGES.inconnu)
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(ia)))
        lancerTaches(taches)
        contient(p.etapeTexte:gsub('\n', ' '):gsub('  +', ' '), "Pas d'avant/après : " .. Etapes.RAISONS.calculs_ia)
        egal('DSCF4961.RAF · add_mask · annulée ensuite (undo_last)', p.etapeSousTitre)
        -- Une étape de la 1.2 (sans id) : sa raison et ses changements, sans images.
        local ancienne = conversationDeLa12()
        Moteur.courante = ancienne
        Fenetre.rafraichir()
        avant = #demandes
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(1)))
        lancerTaches(taches)
        egal(avant, #demandes, "pas d'images à lire sans id")
        egal('Étape 1 sur 1 · passe 1 : lumière', p.etapeTitre)
        contient(p.etapeTexte:gsub('\n', ' '), 'Pourquoi : Ombres bouchées : ombres relevées.')
        contient(p.etapeTexte:gsub('\n', ' '), 'Ombres : 0 → 30')
        contient(p.etapeTexte:gsub('\n', ' '), "Pas d'avant/après : " .. Fenetre.SANS_IMAGES.ancienne)
        egal('DSCF4961.RAF · apply_settings · annulée ensuite (undo_last)', p.etapeSousTitre)
        Moteur.courante = c
        p.onglet = 'notation'
    end)
    images.E10, images.E11 = nil, nil
end)

essai("Fenêtre : l'étape d'un appel sur plusieurs photos montre celle de la photo active, sinon la première", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local copie = appel(c, 'k1', 'copy_settings', { step_name = 'série', reason = 'Même balance.' },
        ecriture('série', { { 4962, 'DSCF4962.RAF', 'E2', { changement('Exposure2012', 0, 0.5, 'Exposition') } },
            { 4961, 'DSCF4961.RAF', 'E1', { changement('Exposure2012', 0, 0.3, 'Exposition') } } }))
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        local taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(copie)))
        lancerTaches(taches)
        egal('DSCF4961.RAF · copy_settings', p.etapeSousTitre, 'la photo active')
        egal('/etapes/4961/.vignettes/E1-apres-660.jpg', p.imageApercu)
        contient(p.etapeTexte, 'Exposition : 0 → ' .. Texte.nombre(0.3), 'ses changements')
        -- Une autre photo active, qui n'en fait pas partie : la première de la réponse.
        photoActive(4963, 'DSCF4963.RAF')
        Fenetre.majPhoto()
        Fenetre.cliquerLigne((ligneDe(copie)))
        egal('DSCF4962.RAF · copy_settings', p.etapeSousTitre, 'la première')
        p.onglet = 'notation'
    end)
end)

-- Fait tourner la boucle de la fenêtre une fois (son attente arrête la boucle).
local function unTour()
    local taches = S.modules.LrTasks
    local dormir, generation = taches.sleep, Fenetre.generation
    -- Rien d'autre à rafraîchir : seul ce que la boucle suit d'elle-même.
    Fenetre.aRafraichir, Fenetre.photoChangee, Fenetre.aRafraichirNotation = false, false, false
    taches.sleep = function() Fenetre.generation = generation + 1000 end
    Fenetre.boucle(generation)
    Fenetre.generation = generation
    taches.sleep = dormir
end

essai("Fenêtre : images en préparation, montrées quand Etapes.version change ; mode suivre, pas après un ◀ ; aucune bascule vers Pourquoi ?", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local premiere = balance(c, 'b1', 'E1')
    ciel(c, 'c1', 'E2')
    images.E2 = { etat = 'en_cours', avant = true }
    ouvrirFenetre(function(p, args)
        Fenetre.rafraichir()
        -- La dernière étape : en préparation.
        local taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(premiere)))
        bouton(args.contents, p, '▶', 'etapeSuivante').args.action()
        lancerTaches(taches)
        egal(true, Fenetre.etape.suivre, 'la dernière : mode suivre')
        egal('Étape 2 sur 2 · avant', p.legendeApercu, "l'avant déjà gardé, en attendant l'après")
        contient(p.etapeTexte:gsub('\n', ' '), 'Avant/après en préparation…')
        egal(false, p.etapeAImages)
        -- Les copies de la fenêtre : dans son dossier, hors du dossier Etapes du module.
        local copies = Fenetre.imagesEtapes['4961/E2'].dossier
        vrai(copies:find(Fenetre.dossierPourquoi() .. '/4961/', 1, true) == 1, copies)
        vrai(Fichiers.existe(copies .. '/E2-avant.jpg'), "la copie de l'avant")
        -- La capture finit : Etapes.version change, la boucle relit les images.
        images.E2 = nil
        Etapes.version = Etapes.version + 1
        taches = #S.taches
        unTour()
        lancerTaches(taches)
        egal('Étape 2 sur 2 · après', p.legendeApercu)
        egal('/etapes/4961/.vignettes/E2-apres-660.jpg', p.imageApercu)
        vrai(not p.etapeTexte:find('préparation', 1, true), p.etapeTexte)
        egal(true, p.etapeAImages)
        vrai(not Fichiers.existe(copies), 'les copies de la lecture remplacée s\'effacent')
        vrai(Fichiers.existe(Fenetre.imagesEtapes['4961/E2'].dossier .. '/E2-apres.jpg'), "la copie de l'après")
        -- Prête, elle ne se relit plus quand une autre capture finit.
        local lues = #demandes
        Etapes.version = Etapes.version + 1
        taches = #S.taches
        unTour()
        lancerTaches(taches)
        egal(lues, #demandes, 'une étape prête ne se relit pas')
        egal('/etapes/4961/.vignettes/E2-apres-660.jpg', p.imageApercu)
        -- Une nouvelle étape de la même photo, appel en cours puis réponse : elle devient l'étape
        -- montrée (mode suivre).
        appel(c, 'b3', 'apply_settings', { step_name = 'passe 3 : peau', reason = 'Peau rougie.' })
        Fenetre.rafraichir()
        egal('Étape 3 sur 3 · passe 3 : peau', p.etapeTitre)
        egal('Étape 3 sur 3 · avant/après en préparation…', p.legendeApercu)
        egal('apply_settings · en cours', p.etapeSousTitre)
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'b3', images = {}, erreur = false,
            textes = { Json.encode(ecriture('passe 3 : peau', { { 4961, 'DSCF4961.RAF', 'E3' } })) } } } })
        taches = #S.taches
        Fenetre.rafraichir()
        lancerTaches(taches)
        egal('E3', Fenetre.etape.id)
        egal('/etapes/4961/.vignettes/E3-apres-660.jpg', p.imageApercu)
        -- ◀ : l'étape 2, le mode suivre quitté ; une nouvelle étape ne la remplace pas.
        bouton(args.contents, p, '◀', 'etapePrecedente').args.action()
        egal(false, Fenetre.etape.suivre)
        ciel(c, 'c4', 'E4')
        Fenetre.rafraichir()
        egal('Étape 2 sur 4 · passe 2 : ciel', p.etapeTitre, 'pas après un ◀')
        -- ▶ jusqu'à la dernière : de nouveau en mode suivre.
        bouton(args.contents, p, '▶', 'etapeSuivante').args.action()
        bouton(args.contents, p, '▶', 'etapeSuivante').args.action()
        egal(true, Fenetre.etape.suivre)
        balance(c, 'b5', 'E5')
        Fenetre.rafraichir()
        egal('Étape 5 sur 5 · passe 1 : balance', p.etapeTitre)
        -- Aucune bascule automatique vers Pourquoi ? : une étape qui arrive laisse l'onglet Note.
        p.onglet = 'notation'
        balance(c, 'b6', 'E6')
        Fenetre.rafraichir()
        Etapes.version = Etapes.version + 1
        unTour()
        egal('notation', p.onglet, 'pas de bascule')
    end)
end)

essai("Fenêtre : l'onglet Pourquoi ? choisi sans étape : la dernière de la photo active ; sans aucune, l'aide et l'aperçu d'avant", function()
    photoActive(4962, 'DSCF4962.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        local defaut = p.legendeApercu
        p.onglet = 'apercu'
        egal(nil, Fenetre.etape, 'aucune étape')
        egal(Fenetre.AIDE_ETAPE, (p.etapeTexte:gsub('\n', ' ')))
        egal(defaut, p.legendeApercu, "l'aperçu d'avant")
        p.onglet = 'notation'
        balance(c, 'b1', 'E1')
        balance(c, 'x1', 'E7', 4962)
        balance(c, 'b2', 'E2')
        Fenetre.rafraichir()
        egal('notation', p.onglet, 'pas de bascule')
        -- Un vrai clic sur l'onglet : la dernière étape de la photo active (4962).
        p.onglet = 'apercu'
        egal('E7', Fenetre.etape.id)
        egal(true, Fenetre.etape.suivre)
        egal('Étape 1 sur 1 · passe 1 : balance', p.etapeTitre)
        -- Une photo active sans étape : la dernière de la conversation.
        Fenetre.etape = nil
        photoActive(4963, 'DSCF4963.RAF')
        Fenetre.majPhoto()
        p.onglet = 'notation'
        p.onglet = 'apercu'
        egal('E2', Fenetre.etape.id)
        egal('Étape 2 sur 2 · passe 1 : balance', p.etapeTitre)
        p.onglet = 'notation'
    end)
end)

essai("Fenêtre : Agrandir dans l'onglet Pourquoi ? : l'avant et l'après côte à côte, la raison dessous ; une seule image si l'autre manque", function()
    photoActive(4961, 'DSCF4961.RAF')
    Moteur.nouvelle()
    local c = Moteur.courante
    local premiere = balance(c, 'b1', 'E1')
    local seule = ciel(c, 'c1', 'E2')
    images.E2 = { etat = 'manque', raison = 'sans_avant', apres = true }
    ouvrirFenetre(function(p, args)
        Fenetre.rafraichir()
        local taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(premiere)))
        lancerTaches(taches)
        local dialogues = #S.dialogues
        taches = #S.taches
        bouton(args.contents, p, '⤢ Agrandir').args.action()
        lancerTaches(taches)
        egal(dialogues + 1, #S.dialogues)
        local d = S.dialogues[#S.dialogues]
        egal('Claude · Étape 1 sur 2 · passe 1 : balance', d.title)
        local rangee = d.contents.args[1]
        egal('row', rangee.genre)
        local cotes = {}
        for _, colonne in ipairs(rangee.args) do
            local titre, image = colonne.args[1], colonne.args[2]
            cotes[#cotes + 1] = titre.args.title .. ' ' .. image.genre .. ' ' .. image.args.value
        end
        egal('Avant picture /etapes/4961/.vignettes/E1-avant-grande.jpg | Après picture /etapes/4961/.vignettes/E1-apres-grande.jpg',
            table.concat(cotes, ' | '))
        contient(d.contents.args[2].args.title:gsub('\n', ' '), 'Pourquoi : La photo tirait vers le bleu')
        -- L'après seul (l'avant manque) : une image, et la carte le dit.
        taches = #S.taches
        Fenetre.cliquerLigne((ligneDe(seule)))
        lancerTaches(taches)
        contient(p.etapeTexte:gsub('\n', ' '), 'Avant/après incomplet : ' .. Etapes.RAISONS.sans_avant)
        egal(false, p.etapeAImages, 'Voir l\'avant inactif')
        egal('Étape 2 sur 2 · après', p.legendeApercu)
        taches = #S.taches
        Fenetre.agrandir()
        lancerTaches(taches)
        d = S.dialogues[#S.dialogues]
        egal('Claude · Étape 2 sur 2 · passe 2 : ciel · après', d.title)
        egal('picture', d.contents.genre)
        p.onglet = 'notation'
    end)
    images.E2 = nil
end)

-- Consignes -------------------------------------------------------------------------------------

essai('Consignes : la raison de chaque étape, une phrase simple pour Dany, 160 caractères, avec l\'avant/après ; le résumé ne la répète pas', function()
    local texte = Consignes.texte
    local debut = texte:find('\n## Raison de chaque étape\n', 1, true)
    vrai(debut, 'section Raison de chaque étape')
    local fin = texte:find('\n## ', debut + 1, true)
    local section = texte:sub(debut + 1, fin - 1)
    vrai(Texte.longueur(section) <= 400, string.format('section : %d caractères pour 400', Texte.longueur(section)))
    for _, morceau in ipairs({ 'reason', 'une phrase simple pour Dany', '160 caractères au plus', 'défaut vu', 'view_photo',
        'noms français des réglages', "l'avant/après de l'étape", 'onglet Aperçu, bouton Pourquoi ? du fil', 'step_name' }) do
        contient(section, morceau, 'raison de chaque étape')
    end
    -- Entre Style et Fin d'une tâche.
    vrai(texte:find('\n## Style\n', 1, true) < debut, 'après Style')
    egal(fin, texte:find("\n## Fin d'une tâche\n", 1, true), "avant Fin d'une tâche")
    local phrase = "Dany revoit chaque étape (avant/après et raison) en la cliquant dans le fil : ton résumé ne répète pas chaque raison."
    contient(texte, phrase, "fin d'une tâche")
    vrai(Texte.longueur(phrase) <= 120, 'la phrase de fin : 120 caractères au plus')
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
    vrai(Texte.longueur(texte) <= 7500, 'plafond des consignes')
end)

-- Fin -------------------------------------------------------------------------------------------

Etapes.images, Images.vignette, Images.grande = imagesVraies, vignetteVraie, grandeVraie
Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
