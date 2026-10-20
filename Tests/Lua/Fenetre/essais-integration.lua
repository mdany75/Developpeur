-- essais-integration.lua : la notation de la 1.1 de bout en bout hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua), avec les vrais modules de chaque pièce : la commande
-- notation telle que le serveur l'envoie pour propose_ratings (relue par Json.decode), le
-- registre (Notation), la Séance de notation (FenetreNotation) et ses vraies vignettes
-- (Vignettes.demander, Images.vignette), les passes (Consignes), le moteur (Moteur.nouvelleSeance),
-- le fil (Conversation, Fil) et la carte Note de la fenêtre Claude (Fenetre). Seuls l'écriture dans
-- le catalogue (Bibliotheque.noter, éprouvée par la suite de la liaison) et l'envoi à Claude Code
-- (Moteur.envoyer, éprouvé par essais-moteur avec faux-claude) sont remplacés : ils gardent les
-- appels reçus. Ni Claude, ni quota.
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

local function copie(valeur)
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
end

-- Catalogue simulé ------------------------------------------------------------------------------

-- Une vraie image JPEG, que Lightroom rendrait comme vignette (paysage 3:2).
local JPEG
do
    local chemin = S.home .. '/source.jpg'
    S.executer('/usr/bin/sips -s format jpeg -z 200 300 ' .. S.q(S.plugin .. '/vide-230.png') .. ' --out ' .. S.q(chemin) .. ' >/dev/null 2>&1')
    local f = assert(io.open(chemin, 'rb'), 'JPEG source')
    JPEG = f:read('*a')
    f:close()
end

-- Photos 2001 à 2006 : nom, uuid, note et drapeau posés, modifications, date de prise de vue
-- (dans l'ordre inverse des identifiants pour 2001 à 2004 : la séance les range par date).
local PHOTOS = {}
local DRAPEAUX = { retenue = 1, aucun = 0, rejetee = -1 }
for id = 2001, 2006 do
    local ph = { localIdentifier = id, nom = 'DSCF' .. id .. '.RAF', uuid = 'uuid-' .. id, note = 0, drapeau = 0, edition = 1,
        date = 700000000 - id }
    function ph:getFormattedMetadata(cle)
        return cle == 'fileName' and self.nom or nil
    end
    function ph:getRawMetadata(cle)
        local valeurs = { rating = self.note, pickStatus = self.drapeau, editCount = self.edition, dateTimeOriginal = self.date, uuid = self.uuid }
        return valeurs[cle]
    end
    function ph:getPropertyForPlugin()
        return nil
    end
    function ph:requestJpegThumbnail(_, _, rappel)
        rappel(JPEG)
        return {}
    end
    PHOTOS[id] = ph
end
S.catalogue.getPhotoByLocalId = function(_, id) return PHOTOS[tonumber(id)] end
S.catalogue.getPath = function() return '/Users/essai/Images/Catalogue.lrcat' end
S.catalogue.batchGetRawMetadata = function(_, liste, cles)
    local r = {}
    for _, ph in ipairs(liste) do
        r[ph] = {}
        for _, cle in ipairs(cles) do
            r[ph][cle] = ph:getRawMetadata(cle)
        end
    end
    return r
end

-- Écriture dans le catalogue (Bibliotheque.noter) : les appels reçus, la note et le drapeau posés
-- sur la photo, la réponse sous la forme de resultatsPlans.
local ecritures = {}
package.loaded.Bibliotheque = {
    noter = function(params)
        ecritures[#ecritures + 1] = copie(params)
        local resultats = {}
        for _, n in ipairs(params.notes) do
            local ph = PHOTOS[n.photo]
            if n.note ~= nil then
                ph.note = n.note
            end
            if n.drapeau ~= nil then
                ph.drapeau = DRAPEAUX[n.drapeau]
            end
            resultats[#resultats + 1] = { photo = { id = n.photo, fichier = ph.nom }, etape = 'Claude · notation', changements = {}, remarques = {} }
        end
        return { mode = 'appliquer', resultats = resultats }
    end,
}

local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Fil = require 'Fil'
local Images = require 'Images'
local Journal = require 'Journal'
local Json = require 'Json'
local Moteur = require 'Moteur'
local Notation = require 'Notation'
local FenetreNotation = require 'FenetreNotation'
local Fenetre = require 'Fenetre'

-- L'envoi à Claude Code : les demandes reçues.
local envois = {}
Moteur.envoyer = function(texte, options)
    envois[#envois + 1] = { texte = texte, options = options }
    return true
end

-- Les erreurs que les fenêtres notent dans leur journal font échouer l'essai.
local journal = {}
local noterVraiment = Journal.noter
Journal.noter = function(...)
    journal[#journal + 1] = table.concat({ ... }, ' ')
    return noterVraiment(...)
end
local function sansErreur()
    vrai(#journal == 0, 'journal : ' .. table.concat(journal, ' | '))
end

-- Fenêtre de séance ------------------------------------------------------------------------------

local function parcourir(vue, fn)
    fn(vue)
    for _, enfant in ipairs(vue.args or {}) do
        if type(enfant) == 'table' and enfant.genre then
            parcourir(enfant, fn)
        end
    end
end

-- Un bouton par son titre (texte, ou clé de son titre lié).
local function bouton(contenu, titre)
    local trouve
    parcourir(contenu, function(v)
        local t = v.args.title
        if not trouve and v.genre == 'push_button' and (t == titre or (type(t) == 'table' and t.key == titre)) then
            trouve = v
        end
    end)
    vrai(trouve, 'bouton introuvable : ' .. titre)
    return trouve
end

local function lancerTaches()
    local n = 0
    while #S.taches > 0 do
        local tache = table.remove(S.taches, 1)
        if tache ~= FenetreNotation.boucle and tache ~= FenetreNotation.afficher then
            tache()
        end
        n = n + 1
        vrai(n < 200, 'trop de tâches')
    end
end

local function tourner()
    for _ = 1, 6 do
        FenetreNotation.tour(1)
        lancerTaches()
    end
end

-- Ouvre la séance de notation et appelle fn(p, args) pendant qu'elle est ouverte.
local function ouvrirSeance(fn)
    local erreur
    S.taches = {}
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function()
            lancerTaches()
            tourner()
            fn(FenetreNotation.p, args)
        end, debug.traceback)
        erreur = not ok and e or nil
    end
    FenetreNotation.afficher()
    S.pendantFenetre = nil
    egal(false, FenetreNotation.ouverte, 'fenêtre fermée')
    if erreur then
        error(erreur, 0)
    end
end

-- La commande notation que le connecteur envoie pour propose_ratings (Tools+Notation.swift :
-- note 0 et drapeau « rejetee » pour un rejet, critères aux noms du module, plafond du dernier tri),
-- passée par JSON comme sur la liaison.
local function commandeDuConnecteur(seance)
    return Json.decode(Json.encode({
        action = 'proposer', passe = 1, seance = seance,
        propositions = {
            { photo = 2001, note = 3, drapeau = 'aucun', a_verifier = false, raison = "Tient seule devant qui ne connaît pas le lieu.",
                criteres = { impact = "Le regard arrête l'œil.", qualites = "Lumière de côté, fond calme.", plancher = "Nette (41)." } },
            { photo = 2002, note = 0, drapeau = 'rejetee', a_verifier = false, plafond = 0, raison = "Mise au point manquée.",
                criteres = { impact = "Aucun.", qualites = "Sujet flou.", plancher = "Floue (9) : plafond 0." } },
            { photo = 2003, note = 2, drapeau = 'aucun', a_verifier = true, plafond = 2, raison = "Presque noire : à revoir après développement.",
                criteres = { impact = "Moyen.", qualites = "Ciel de nuit.", plancher = "Presque noire : plafond 2, rattrapable (RAW)." } },
            { photo = 9999, note = 2, drapeau = 'aucun', a_verifier = false, raison = "Photo inconnue.",
                criteres = { impact = "-", qualites = "-", plancher = "-" } },
        },
    }))
end

-- L'entrée de propose_ratings telle que Claude l'écrit (pour le fil de la conversation de séance).
local function entreePropose(seance)
    local function critere(impact) return { impact = impact, qualities = "Lumière", technical_floor = "Nette" } end
    return { pass = 1, session = seance, ratings = {
        { photo_id = 2001, rating = 3, criteria = critere("Fort"), reason = "Tient seule.", to_check = false },
        { photo_id = 2002, flag = 'reject', criteria = critere("Aucun"), reason = "Floue.", to_check = false },
        { photo_id = 2003, rating = 2, criteria = critere("Moyen"), reason = "Presque noire.", to_check = true },
        { photo_id = 9999, rating = 2, criteria = critere("-"), reason = "Inconnue.", to_check = false },
    } }
end

-- Essais ----------------------------------------------------------------------------------------

local idSeance

essai('Séance : ouverte sur la sélection, passe 1 envoyée avec le vrai identifiant, propositions du connecteur, Tout accepter', function()
    S.photoActive = PHOTOS[2001]
    S.selection = { PHOTOS[2001], PHOTOS[2002], PHOTOS[2003], PHOTOS[2004] }
    S.reponseConfirm = 'ok'
    ouvrirSeance(function(p, args)
        egal('4 photos sélectionnées.', p.textePhotos)
        -- Avant les vignettes : l'image « aucun aperçu » du côté de la case, qui existe.
        local Chemins = require 'Chemins'
        egal(Chemins.ressource('vide-' .. FenetreNotation.CASE .. '.png'), p.vignette1)
        local l, h = Images.dimensions(p.vignette1)
        egal(FenetreNotation.CASE, l, 'image vide de la case')
        egal(FenetreNotation.CASE, h, 'image vide de la case')
        bouton(args.contents, 'Ouvrir la séance').args.action()
        lancerTaches()
        tourner()
        idSeance = Notation.seanceActive()
        vrai(idSeance, 'séance ouverte dans le registre')
        local s = Notation.seance(idSeance)
        egal('2004 2003 2002 2001', table.concat(s.photos, ' '), 'photos figées dans l\'ordre de la prise de vue')
        contient(p.titreSeance, 'Sélection du ')

        -- Lancer la passe 1 : le message des Consignes, dans la conversation de la séance.
        bouton(args.contents, 'titreLancer').args.action()
        lancerTaches()
        egal(1, #envois)
        local envoi = envois[1]
        contient(envoi.texte, 'Passe 1 de la séance de notation')
        contient(envoi.texte, 'session = "' .. idSeance .. '"', 'Claude reçoit le vrai identifiant de séance')
        contient(envoi.texte, '2004, 2003, 2002, 2001')
        local c = envoi.options.conversation
        egal('notation', c.genre)
        egal(idSeance, c.seance)
        vrai(c ~= Moteur.courante, 'la conversation de la fenêtre Claude ne change pas')
        egal(c, Moteur.trouver(c.id), 'rangée dans le moteur')
        egal('[Lightroom : séance de notation « ' .. s.titre .. ' », 4 photos ; passe 1]', envoi.options.contexte)
        egal(c, Moteur.nouvelleSeance { titre = 'autre', seance = idSeance }, 'reprise à la passe suivante')

        -- Claude appelle propose_ratings : la commande du connecteur, rangée par le registre.
        local reponse = Notation.commande(commandeDuConnecteur(idSeance))
        egal(idSeance, reponse.seance)
        egal(3, #reponse.propositions)
        egal(1, #reponse.refusees)
        egal(9999, reponse.refusees[1].photo)
        egal('a_verifier', reponse.propositions[3].etat, 'à vérifier : pas dans Tout accepter')
        local texte = Json.encode(reponse)

        -- Le fil de la conversation de séance lit la même réponse (texte JSON du connecteur).
        Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'pr-1',
            nom = 'mcp__developpeur__propose_ratings', entree = entreePropose(idSeance) } } })
        Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'pr-1', textes = { texte }, images = {}, erreur = false } } })
        local e
        for _, x in ipairs(c.elements) do
            if x.genre == 'notation' then
                e = x
            end
        end
        vrai(e, 'élément notation')
        egal('fait', e.etat)
        egal(idSeance, e.seance)
        egal('proposee', e.notes[1].etat)
        egal('DSCF2001.RAF', e.notes[1].fichier, 'le fichier lu dans la réponse du module')
        egal('refusee', e.notes[4].etat, 'la photo inconnue refusée')
        local lignes = Fil.lignes(c, 480, {})
        local titre
        for _, l in ipairs(lignes) do
            titre = titre or (l.texte:find('Notes proposées', 1, true) and l.texte)
        end
        contient(titre, 'passe 1', 'titre du fil')

        -- La planche : notes proposées et états, vignettes rendues.
        tourner()
        egal('2004', p.nom1:match('(%d+)$'), 'première case : la photo la plus ancienne')
        egal('★★☆☆☆', p.etoiles2, 'case 2 : 2003')
        egal('rouge', p.couleur2, 'à vérifier')
        egal('⚑ Rejeter', p.etoiles3)
        egal('orange', p.couleur3)
        egal('★★★☆☆', p.etoiles4)
        egal('pas encore jugée', p.etatTexte1)
        for k = 1, 4 do
            vrai(p['aVignette' .. k], 'vignette de la case ' .. k)
            local l, h = Images.dimensions(p['vignette' .. k])
            egal(FenetreNotation.CASE, l, 'largeur de la vignette ' .. k)
            egal(FenetreNotation.CASE, h, 'hauteur de la vignette ' .. k)
        end

        -- Tout accepter : une écriture, les deux propositions « proposées » de la passe.
        egal('Tout accepter · passe 1 (2)', p.titreToutAccepter)
        bouton(args.contents, 'titreToutAccepter').args.action()
        lancerTaches()
        egal(1, #ecritures)
        local params = ecritures[1]
        egal('notation', params.etape)
        egal(true, params.depuisLightroom)
        egal(true, params.confirme)
        egal(2, #params.notes)
        local parPhoto = {}
        for _, n in ipairs(params.notes) do
            parPhoto[n.photo] = n
        end
        egal(3, parPhoto[2001].note)
        egal(nil, parPhoto[2001].drapeau, 'une note sans drapeau ne touche pas le drapeau')
        egal(nil, parPhoto[2002].note, 'un rejet laisse les étoiles')
        egal('rejetee', parPhoto[2002].drapeau)
        egal(3, PHOTOS[2001].note)
        egal(-1, PHOTOS[2002].drapeau)
        egal('acceptee', Notation.proposition(2001).etat)
        egal('acceptee', Notation.proposition(2002).etat)
        egal('a_verifier', Notation.proposition(2003).etat)
        contient(p.message, '2 notes posées dans Lightroom.')
        tourner()
        egal('vert', p.couleur4)
        egal('Tout accepter', p.titreToutAccepter, 'plus rien à accepter')
    end)
    sansErreur()
end)

essai('Carte Note de la fenêtre Claude : la proposition de la séance, Accepter par le registre', function()
    vrai(idSeance, 'essai précédent')
    S.photoActive = PHOTOS[2003]
    S.selection = { PHOTOS[2003] }
    S.taches = {}
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function()
            local p = Fenetre.p
            Fenetre.majPhoto()
            Fenetre.rafraichirNotation()
            egal('Claude propose : ★★☆☆☆', p.notationProposee)
            egal('rouge', p.notationCouleur)
            egal('à vérifier · passe 1', p.notationEtat)
            contient(p.notationCriteres, 'Plafond mesuré : 2 ★')
            egal(true, p.peutAccepterNote)
            -- Claude travaille : rien ne s'écrit depuis la carte.
            Moteur.travaille = true
            Fenetre.rafraichirNotation()
            egal(false, p.peutAccepterNote)
            Fenetre.poserNote({ photo = 2003 })
            egal(1, #ecritures, 'rien posé pendant que Claude travaille')
            Moteur.travaille = false
            Fenetre.rafraichirNotation()
            -- Accepter : dans une tâche, la proposition telle quelle.
            local accepter
            parcourir(args.contents, function(v)
                if v.genre == 'push_button' and v.args.title == 'Accepter' then
                    accepter = v
                end
            end)
            accepter.args.action()
            S.taches[#S.taches]()
            egal(2, #ecritures)
            egal(2003, ecritures[2].notes[1].photo)
            egal(2, ecritures[2].notes[1].note)
            egal(2, PHOTOS[2003].note)
            egal('acceptee', Notation.proposition(2003).etat)
            Fenetre.majPhoto()
            Fenetre.rafraichirNotation()
            egal('vert', p.notationCouleur)
            egal('Note posée : ★★☆☆☆', p.notationPosee)
        end, debug.traceback)
        erreur = not ok and e or nil
    end
    Fenetre.afficher()
    S.pendantFenetre = nil
    if erreur then
        error(erreur, 0)
    end
    sansErreur()
end)

essai('Registre relu du disque : décisions gardées, proposition hors séance pour la carte Note', function()
    Notation.oublier()
    egal(idSeance, Notation.seanceActive(), 'séance active gardée')
    egal('acceptee', Notation.proposition(2001).etat)
    local c = Notation.compter(idSeance)
    egal(3, c.acceptees)
    egal(3, c.par_passe[1].acceptees)
    -- Le bouton Noter de la carte (une photo hors de la séance) : rangée sans la séance.
    local reponse = Notation.commande(Json.decode(Json.encode({ action = 'proposer', propositions = {
        { photo = 2005, note = 4, drapeau = 'aucun', a_verifier = false, raison = "De l'impact.",
            criteres = { impact = "Fort.", qualites = "Belle lumière.", plancher = "Nette (52)." } } } })))
    egal(true, reponse.propositions[1].hors_seance)
    egal(nil, Notation.proposition(2005).seance)
    egal('proposee', Notation.proposition(2005).etat)
    -- Claude ne propose jamais 5 étoiles, même si le connecteur était contourné.
    local ok, refus = pcall(Notation.commande, { action = 'proposer', propositions = {
        { photo = 2006, note = 5, drapeau = 'aucun', raison = 'x', criteres = {} } } })
    vrai(not ok, '5 ★ refusées')
    contient(refus, 'jamais 5 étoiles')
    -- Les consignes et le message Noter parlent du même outil que le connecteur.
    contient(Consignes.noterPhoto, 'propose_ratings')
    contient(Consignes.pour({ genre = 'notation' }), '# Séance de notation')
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
