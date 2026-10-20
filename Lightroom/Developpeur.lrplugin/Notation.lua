-- Notation.lua : le registre des notes que Claude propose (outil propose_ratings, commande
-- notation), et des séances de notation de la fenêtre Claude. Rien n'y est écrit dans le
-- catalogue : Claude propose, l'utilisateur accepte, change, met à vérifier ou écarte dans la
-- fenêtre ; seule une note acceptée ou changée s'écrit, par Notation.poser (Bibliotheque.noter,
-- une écriture, une étape par photo que undo_last défait).
--
-- La liaison (commande du serveur) et la fenêtre (cartes Note, Séance de notation) sont le même
-- module : elles voient la même table. Le registre est aussi rangé dans notation.json (à côté de
-- consommation.json), propre au catalogue ouvert : un identifiant de photo ne vaut que dans son
-- catalogue, et un autre catalogue trouve un registre vide (le fichier ne change qu'à sa première
-- proposition). Chaque proposition garde l'uuid de sa photo : une photo qui n'a plus cet
-- identifiant ne reçoit jamais la note d'une autre.
--
-- Chargeable sans l'interface ni la Bibliothèque (la fenêtre aussi s'en sert) : Bibliotheque
-- n'est requise qu'au moment d'écrire. Tout ce qui sort vers une vue est une copie neuve, sans
-- métatable (Lightroom bloque sur une table relue par Json.decode).
--
-- Une proposition : { photo, uuid, fichier, note (0 à 4, nil pour un rejet), drapeau ('aucun' ou
-- 'rejetee'), criteres = { impact, qualites, plancher, finition }, plafond, raison, a_verifier,
-- passe, seance, note_avant, drapeau_avant, etat, note_choisie, drapeau_choisi, le, decide_le,
-- commentaire }. etat : 'proposee', 'acceptee' (posée telle quelle), 'changee' (posée autrement :
-- note_choisie, drapeau_choisi), 'a_verifier' (Claude ou l'utilisateur doute), 'ecartee'.
-- Une séance : { id, titre, source = { portee, collection }, photos (identifiants figés à
-- l'ouverture), passe (1 à 4), cree, numero (ordre d'ouverture) }.

local LrPathUtils = import 'LrPathUtils'
local LrTasks = import 'LrTasks'

require 'Compat'
local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local Json = require 'Json'
local Liaison = require 'Liaison'
local Photos = require 'Photos'

local Notation = {
    -- +1 à chaque changement du registre : une fenêtre compare pour savoir s'il faut redessiner.
    version = 0,
    -- Fenêtres abonnées (nom → fonction), comme Moteur.abonner ; Liaison.observateur est à Suivi.
    observateurs = {},
}

-- Claude ne propose jamais 5 étoiles : c'est à l'utilisateur (second garde-fou, après le serveur).
Notation.NOTE_MAX_PROPOSEE = 4
Notation.PASSES = 4
-- Taille du registre, réécrit à chaque décision : les séances les plus anciennes, puis les
-- propositions les plus anciennes, sortent au-delà.
Notation.MAX_SEANCES = 50
Notation.MAX_PROPOSITIONS = 2000
-- Photos au plus par écriture (comme une commande du serveur) : Tout accepter sur une plus grande
-- séance se fait en plusieurs écritures.
Notation.LOT = 500

local ETATS = { proposee = true, acceptee = true, changee = true, a_verifier = true, ecartee = true }
local DECISIONS = { a_verifier = true, ecartee = true, proposee = true }
local CRITERES = { 'impact', 'qualites', 'plancher', 'finition' }
-- pickStatus de Lightroom (1, 0, −1) en mots, sans accent comme dans les commandes.
local DRAPEAUX = { [1] = 'retenue', [0] = 'aucun', [-1] = 'rejetee' }

local function echouer(message)
    error(message, 0)
end

local registre

function Notation.fichier()
    return LrPathUtils.child(Chemins.racine(), 'notation.json')
end

-- Copie neuve, sans métatable ni Json.null.
local function copie(valeur)
    if valeur == Json.null then
        return nil
    end
    if type(valeur) ~= 'table' then
        return valeur
    end
    local t = {}
    for cle, element in pairs(valeur) do
        t[cle] = copie(element)
    end
    return t
end

-- Clé d'une photo dans le registre : un texte (Json.decode rend des clés texte).
local function cleDe(id)
    return tostring(tonumber(id) or id)
end

local function entier(valeur)
    local n = tonumber(valeur)
    if n and n == math.floor(n) then
        return n
    end
    return nil
end

local function texte(valeur)
    if type(valeur) == 'string' and valeur ~= '' then
        return valeur
    end
    return nil
end

local function cheminCatalogue()
    local ok, chemin = LrTasks.pcall(function()
        local cat = Photos.catalogue()
        return cat and cat:getPath()
    end)
    return ok and texte(chemin) or nil
end

local function vide(catalogue)
    return { catalogue = catalogue, seances = {}, propositions = {}, prochain = 0 }
end

-- Registre relu du fichier : des tables neuves, des clés de photo en texte.
local function normaliser(r)
    r = copie(r)
    local propre = vide(texte(r.catalogue))
    propre.prochain = entier(r.prochain) or 0
    for id, s in pairs(type(r.seances) == 'table' and r.seances or {}) do
        if type(s) == 'table' then
            local photos = {}
            for _, p in ipairs(type(s.photos) == 'table' and s.photos or {}) do
                photos[#photos + 1] = tonumber(p)
            end
            propre.seances[tostring(id)] = {
                id = tostring(id), titre = texte(s.titre) or "Séance de notation",
                source = type(s.source) == 'table' and s.source or { portee = 'photos' },
                photos = photos, passe = entier(s.passe) or 1, cree = tonumber(s.cree), numero = entier(s.numero) or 0,
            }
        end
    end
    for cle, p in pairs(type(r.propositions) == 'table' and r.propositions or {}) do
        if type(p) == 'table' and ETATS[p.etat] then
            p.photo = tonumber(p.photo) or tonumber(cle)
            propre.propositions[cleDe(p.photo)] = p
        end
    end
    if texte(r.seanceActive) and propre.seances[r.seanceActive] then
        propre.seanceActive = r.seanceActive
    end
    return propre
end

local function charger()
    local courant = cheminCatalogue()
    if registre and courant and registre.catalogue and courant ~= registre.catalogue then
        -- Un autre catalogue (Lightroom relancé sur lui) : le fichier dit s'il a déjà un registre.
        registre = nil
    end
    if registre then
        registre.catalogue = registre.catalogue or courant
        return registre
    end
    local contenu = Fichiers.lire(Notation.fichier())
    local ok, r = pcall(function() return contenu and Json.decode(contenu) end)
    if ok and type(r) == 'table' then
        registre = normaliser(r)
        if courant and registre.catalogue and courant ~= registre.catalogue then
            registre = vide(courant)
        end
        registre.catalogue = registre.catalogue or courant
    else
        registre = vide(courant)
    end
    return registre
end

-- Pour les essais : oublie le registre chargé (relu du fichier à la prochaine lecture).
function Notation.oublier()
    registre = nil
end

-- Les séances les plus anciennes (sauf l'active), puis les propositions les plus anciennes.
local function elaguer(r)
    local seances = {}
    for id, s in pairs(r.seances) do
        if id ~= r.seanceActive then
            seances[#seances + 1] = s
        end
    end
    table.sort(seances, function(a, b) return a.numero < b.numero end)
    local total = #seances + (r.seanceActive and 1 or 0)
    for i = 1, total - Notation.MAX_SEANCES do
        r.seances[seances[i].id] = nil
    end
    local propositions = {}
    for cle, p in pairs(r.propositions) do
        propositions[#propositions + 1] = { cle = cle, le = p.le or 0, photo = tonumber(cle) or 0 }
    end
    if #propositions > Notation.MAX_PROPOSITIONS then
        table.sort(propositions, function(a, b)
            if a.le ~= b.le then
                return a.le < b.le
            end
            return a.photo < b.photo
        end)
        for i = 1, #propositions - Notation.MAX_PROPOSITIONS do
            r.propositions[propositions[i].cle] = nil
        end
    end
end

local function enregistrer()
    local r = charger()
    elaguer(r)
    local seances = {}
    for id, s in pairs(r.seances) do
        local photos = Json.tableau()
        for i, p in ipairs(s.photos) do
            photos[i] = p
        end
        seances[id] = { id = s.id, titre = s.titre, source = s.source, photos = photos, passe = s.passe, cree = s.cree, numero = s.numero }
    end
    local ok, erreur = pcall(Fichiers.ecrire, Notation.fichier(), Json.encode({
        format = 1, catalogue = r.catalogue, seanceActive = r.seanceActive, prochain = r.prochain,
        seances = seances, propositions = r.propositions,
    }))
    if not ok then
        Liaison.noter("Notation non enregistrée : " .. Liaison.messageErreur(erreur))
    end
end

-- Abonnements -------------------------------------------------------------------------

function Notation.abonner(nom, fn)
    Notation.observateurs[nom] = fn
end

function Notation.desabonner(nom)
    Notation.observateurs[nom] = nil
end

-- quoi : 'propositions', 'seance', 'decision' ou 'pose'.
function Notation.signaler(quoi)
    for _, fn in pairs(Notation.observateurs) do
        pcall(fn, quoi)
    end
end

local function changer(quoi)
    Notation.version = Notation.version + 1
    enregistrer()
    Notation.signaler(quoi)
end

-- Séances -------------------------------------------------------------------------------

local function seanceDe(r, id)
    if id == nil then
        id = r.seanceActive
    end
    return id and r.seances[tostring(id)] or nil
end

local function membres(s)
    local ensemble = {}
    for _, id in ipairs(s and s.photos or {}) do
        ensemble[cleDe(id)] = true
    end
    return ensemble
end

-- Crée une séance sur ces photos (identifiants, ou photos de Lightroom), figées à l'ouverture : un
-- rejet accepté peut cacher une photo sous le filtre de la Bibliothèque, et la sélection change.
-- Elle devient la séance active ; les propositions encore à décider de ses photos s'y rattachent.
-- Rend son identifiant (un texte).
function Notation.ouvrirSeance(args)
    args = args or {}
    local photos, vues = {}, {}
    for _, p in ipairs(type(args.photos) == 'table' and args.photos or {}) do
        local id = type(p) == 'table' and p.localIdentifier or tonumber(p)
        if id and not vues[cleDe(id)] then
            vues[cleDe(id)] = true
            photos[#photos + 1] = id
        end
    end
    if #photos == 0 then
        echouer("Aucune photo pour la séance de notation : sélectionner des photos ou choisir une collection.")
    end
    local r = charger()
    r.prochain = r.prochain + 1
    local id = os.date('%Y%m%d-%H%M%S') .. '-' .. r.prochain
    local source = type(args.source) == 'table' and args.source or {}
    r.seances[id] = {
        id = id,
        titre = texte(args.titre) or ("Séance du " .. os.date('%Y-%m-%d %H:%M')),
        source = { portee = texte(source.portee) or 'photos', collection = tonumber(source.collection) },
        photos = photos, passe = 1, cree = os.time(), numero = r.prochain,
    }
    r.seanceActive = id
    for cle in pairs(vues) do
        local p = r.propositions[cle]
        if p and (p.etat == 'proposee' or p.etat == 'a_verifier') then
            p.seance = id
        end
    end
    changer('seance')
    return id
end

function Notation.seanceActive()
    local r = charger()
    return r.seanceActive and r.seances[r.seanceActive] and r.seanceActive or nil
end

-- Une séance (la séance active sans identifiant), copie neuve.
function Notation.seance(id)
    return copie(seanceDe(charger(), id))
end

-- Passe en cours de la séance (1 à 4).
function Notation.choisirPasse(id, n)
    local s = seanceDe(charger(), id)
    n = entier(n)
    if not s then
        echouer("Séance de notation inconnue : " .. tostring(id))
    end
    if not n or n < 1 or n > Notation.PASSES then
        echouer(string.format("Passe invalide : de 1 à %d.", Notation.PASSES))
    end
    if s.passe ~= n then
        s.passe = n
        changer('seance')
    end
end

-- Propositions -------------------------------------------------------------------------

function Notation.proposition(idPhoto)
    if idPhoto == nil then
        return nil
    end
    return copie(charger().propositions[cleDe(idPhoto)])
end

-- Les propositions d'une séance (la séance active sans identifiant), dans l'ordre de ses photos.
function Notation.propositions(id)
    local r = charger()
    local s = seanceDe(r, id)
    local liste = {}
    if not s then
        return liste
    end
    for _, photo in ipairs(s.photos) do
        local p = r.propositions[cleDe(photo)]
        if p and p.seance == s.id then
            liste[#liste + 1] = copie(p)
        end
    end
    return liste
end

local function comptes()
    return { proposees = 0, acceptees = 0, changees = 0, a_verifier = 0, ecartees = 0, total = 0 }
end

local function compterUne(c, p)
    c.total = c.total + 1
    if p.etat == 'proposee' then
        c.proposees = c.proposees + 1
    elseif p.etat == 'acceptee' or p.etat == 'changee' then
        c.acceptees = c.acceptees + 1
        if p.etat == 'changee' then
            c.changees = c.changees + 1
        end
    elseif p.etat == 'a_verifier' then
        c.a_verifier = c.a_verifier + 1
    elseif p.etat == 'ecartee' then
        c.ecartees = c.ecartees + 1
    end
end

-- Comptes d'une séance : proposees (à décider), acceptees (posées, changées comprises), changees,
-- a_verifier, ecartees, total ; photos, sans_proposition ; par_passe[n] (mêmes comptes).
function Notation.compter(id)
    local c = comptes()
    c.par_passe = {}
    for n = 1, Notation.PASSES do
        c.par_passe[n] = comptes()
    end
    local s = seanceDe(charger(), id)
    if not s then
        c.photos, c.sans_proposition = 0, 0
        return c
    end
    c.photos = #s.photos
    for _, p in ipairs(Notation.propositions(s.id)) do
        compterUne(c, p)
        if c.par_passe[p.passe] then
            compterUne(c.par_passe[p.passe], p)
        end
    end
    c.sans_proposition = c.photos - c.total
    return c
end

-- Décision de l'utilisateur sans rien écrire dans le catalogue : 'a_verifier', 'ecartee' (ou
-- 'proposee' pour revenir sur la décision). details.commentaire (ou raison) : son mot, gardé
-- pour apprendre de ses choix. Rend vrai, ou nil et la raison.
function Notation.decider(idPhoto, etat, details)
    if not DECISIONS[etat] then
        return nil, "Décision inconnue : " .. tostring(etat)
    end
    local p = charger().propositions[cleDe(idPhoto)]
    if not p then
        return nil, "Aucune proposition de Claude pour cette photo."
    end
    p.etat = etat
    p.decide_le = os.time()
    if type(details) == 'table' then
        p.commentaire = texte(details.commentaire) or texte(details.raison) or p.commentaire
    end
    changer('decision')
    return true
end

-- Commande « proposer » : propositions de Claude, rangées sans rien écrire dans le catalogue. Une
-- photo introuvable va dans refusees sans bloquer les autres ; une note de 5 ou plus refuse tout.
-- Une proposition pour une photo de la séance (donnée, sinon active) s'y rattache ; une nouvelle
-- proposition pour la même photo remplace l'ancienne. Une proposition « à vérifier » (cas
-- douteux) attend dans cet état : Tout accepter ne la pose pas.
function Notation.proposer(params)
    local demandes = type(params.propositions) == 'table' and params.propositions or {}
    if #demandes == 0 then
        echouer("Aucune proposition : donner propositions.")
    end
    local valides = {}
    for _, d in ipairs(demandes) do
        if type(d) ~= 'table' or d.photo == nil then
            echouer("Proposition sans photo.")
        end
        local drapeau = d.drapeau == nil and 'aucun' or tostring(d.drapeau)
        if drapeau ~= 'aucun' and drapeau ~= 'rejetee' then
            echouer("Drapeau invalide : « aucun » ou « rejetee ».")
        end
        local note = d.note ~= nil and tonumber(d.note) or nil
        if note and note >= 5 then
            echouer("Claude ne propose jamais 5 étoiles : c'est à l'utilisateur.")
        end
        if d.note ~= nil and (not note or note < 0 or note ~= math.floor(note)) then
            echouer(string.format("Note invalide pour la photo %s : un entier de 0 à %d.", tostring(d.photo), Notation.NOTE_MAX_PROPOSEE))
        end
        if note == nil and drapeau ~= 'rejetee' then
            echouer(string.format("Photo %s : une note de 0 à %d, ou le drapeau « rejetee ».", tostring(d.photo), Notation.NOTE_MAX_PROPOSEE))
        end
        -- Un rejet est un drapeau, sans note (le serveur envoie 0) : l'accepter laisse les étoiles
        -- de la photo.
        if drapeau == 'rejetee' then
            note = nil
        end
        valides[#valides + 1] = { demande = d, note = note, drapeau = drapeau }
    end
    local r = charger()
    local s
    if params.seance ~= nil then
        s = r.seances[tostring(params.seance)]
            or echouer("Séance de notation inconnue : " .. tostring(params.seance) .. ". propose_ratings avec read_session = true donne la séance ouverte.")
    else
        s = seanceDe(r, nil)
    end
    local passe = entier(params.passe)
    if passe and (passe < 1 or passe > Notation.PASSES) then
        echouer(string.format("Passe invalide : de 1 à %d.", Notation.PASSES))
    end
    -- La dernière passe (5 étoiles) est à l'utilisateur seul : rien à y proposer.
    if passe == Notation.PASSES then
        echouer(string.format("Passe %d : 5 étoiles, l'utilisateur seul ; rien à proposer.", Notation.PASSES))
    end
    local dansSeance = membres(s)

    local refusees, trouvees, photos = Json.tableau(), {}, {}
    for _, v in ipairs(valides) do
        local ok, photo = LrTasks.pcall(Photos.photoParId, v.demande.photo)
        if ok then
            v.photo = photo
            trouvees[#trouvees + 1] = v
            photos[#photos + 1] = photo
        else
            refusees[#refusees + 1] = { photo = tonumber(v.demande.photo) or v.demande.photo, raison = Liaison.messageErreur(photo) }
        end
    end
    local okD, descriptions = LrTasks.pcall(Photos.decrireTout, photos)
    local maintenant = os.time()
    local reponses = Json.tableau()
    for i, v in ipairs(trouvees) do
        local photo, d = v.photo, v.demande
        local description = okD and descriptions[i] or Photos.decrire(photo, true)
        local id = photo.localIdentifier
        local criteres = {}
        for _, nom in ipairs(CRITERES) do
            criteres[nom] = type(d.criteres) == 'table' and texte(d.criteres[nom]) or nil
        end
        local rattachee = s and dansSeance[cleDe(id)] or false
        local p = {
            photo = id, uuid = texte(Photos.brut(photo, 'uuid')), fichier = description.fichier,
            note = v.note, drapeau = v.drapeau, criteres = criteres, plafond = entier(d.plafond),
            raison = texte(d.raison), a_verifier = d.a_verifier == true,
            passe = passe or (rattachee and s.passe) or nil, seance = rattachee and s.id or nil,
            note_avant = tonumber(description.note) or 0,
            drapeau_avant = description.drapeau == 'rejetée' and 'rejetee' or (description.drapeau or 'aucun'),
            etat = d.a_verifier == true and 'a_verifier' or 'proposee', le = maintenant,
        }
        r.propositions[cleDe(id)] = p
        reponses[#reponses + 1] = { photo = id, fichier = p.fichier, note_avant = p.note_avant, drapeau_avant = p.drapeau_avant,
            etat = p.etat, hors_seance = (s and not rattachee) or nil }
    end
    if #reponses > 0 then
        Liaison.noter(string.format("Notation : %d proposition%s%s", #reponses, #reponses > 1 and "s" or "",
            s and (" (séance « " .. s.titre .. " »)") or ""))
        changer('propositions')
    end
    return { seance = s and s.id or Json.null, propositions = reponses, refusees = refusees }
end

-- Une proposition pour la réponse de la commande (sans l'uuid).
local function pourReponse(p)
    local q = copie(p)
    q.uuid = nil
    return q
end

-- Les photos des propositions sont-elles encore celles-là ? Une photo disparue du catalogue, ou
-- dont l'identifiant désigne une autre photo (autre uuid), perd sa proposition. Rend le nombre
-- de propositions perdues.
local function verifierPhotos(r, cles)
    local perdues = 0
    for _, cle in ipairs(cles) do
        local p = r.propositions[cle]
        local ok, photo = LrTasks.pcall(Photos.photoParId, p.photo)
        if not ok or (p.uuid and Photos.brut(photo, 'uuid') ~= p.uuid) then
            r.propositions[cle] = nil
            perdues = perdues + 1
        end
    end
    return perdues
end

-- Commande « lire » : la séance active, les séances, et les propositions (d'une séance, ou de
-- ces photos, ou toutes) avec leur état et les écarts de l'utilisateur.
local function lire(params)
    local r = charger()
    local s
    if params.seance ~= nil then
        s = r.seances[tostring(params.seance)] or echouer("Séance de notation inconnue : " .. tostring(params.seance))
    end
    local voulues
    if type(params.photos) == 'table' and #params.photos > 0 then
        voulues = {}
        for _, id in ipairs(params.photos) do
            voulues[cleDe(id)] = true
        end
    end
    local cles = {}
    for cle, p in pairs(r.propositions) do
        if (not s or p.seance == s.id) and (not voulues or voulues[cle]) then
            cles[#cles + 1] = cle
        end
    end
    table.sort(cles, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    local perdues = verifierPhotos(r, cles)
    if perdues > 0 then
        changer('propositions')
    end
    local propositions = Json.tableau()
    for _, cle in ipairs(cles) do
        if r.propositions[cle] then
            propositions[#propositions + 1] = pourReponse(r.propositions[cle])
        end
    end
    local seances = Json.tableau()
    for _, x in pairs(r.seances) do
        seances[#seances + 1] = { id = x.id, titre = x.titre, photos = #x.photos, passe = x.passe, cree = x.cree, numero = x.numero,
            comptes = Notation.compter(x.id) }
        seances[#seances].comptes.par_passe = nil
    end
    table.sort(seances, function(a, b) return a.numero > b.numero end)
    for _, x in ipairs(seances) do
        x.numero = nil
    end
    return { seance_active = r.seanceActive or Json.null, seances = seances, propositions = propositions,
        perdues = perdues > 0 and perdues or nil }
end

-- Commande « seance » (propose_ratings avec read_session) : la séance active (ou donnée), pour que
-- Claude sache quelles photos noter.
local function seanceCommande(params)
    local s = seanceDe(charger(), params.seance)
    if not s then
        return { id = Json.null, message = params.seance ~= nil and ("Séance de notation inconnue : " .. tostring(params.seance) .. ".")
            or "Aucune séance de notation ouverte dans Lightroom (fenêtre Claude › Séance…)." }
    end
    local photos = Json.tableau()
    for i, id in ipairs(s.photos) do
        photos[i] = id
    end
    local c = Notation.compter(s.id)
    c.par_passe = nil
    return { id = s.id, titre = s.titre, source = copie(s.source), photos = photos, passe = s.passe, cree = s.cree, comptes = c }
end

-- Commande notation du serveur : action proposer, lire ou seance. Rien n'est écrit dans le
-- catalogue (ni pause, ni accord, ni garde-fous, comme vignettes).
function Notation.commande(params)
    local action = params.action
    if action == 'proposer' then
        return Notation.proposer(params)
    elseif action == 'lire' then
        return lire(params)
    elseif action == 'seance' then
        return seanceCommande(params)
    end
    echouer("Action de notation inconnue : " .. tostring(action) .. " (proposer, lire ou seance).")
end

-- Poser ------------------------------------------------------------------------------

local function drapeauDe(photo)
    return DRAPEAUX[tonumber(Photos.brut(photo, 'pickStatus')) or 0] or 'aucun'
end

-- Écrit des notes dans le catalogue (dans une tâche), depuis la fenêtre : liste = { { photo = id,
-- note = 0 à 5 ou nil, drapeau = 'aucun', 'rejetee', 'retenue' ou nil, raison } }. Sans note ni
-- drapeau, la proposition de Claude telle quelle (Accepter) : sa note, et le drapeau Rejeter pour
-- un rejet ; une note proposée sans rejet retire seulement un rejet déjà posé (« aucun » d'une
-- proposition veut dire « pas rejetée » : un drapeau Retenue de l'utilisateur reste). Sinon les
-- valeurs données (Changer… : l'utilisateur peut mettre 5 étoiles ; nil laisse le champ). Une
-- écriture par lot de Notation.LOT photos, une étape par photo ; garde-fous maintenus. Puis la
-- proposition passe à 'acceptee' (la photo porte ce que Claude proposait) ou 'changee'
-- (note_choisie, drapeau_choisi). Rend { ok, erreur, resultats = { { photo, etat, note, drapeau,
-- changements, remarques, erreur } } }.
function Notation.poser(liste)
    local r = charger()
    local resultats, aPoser, change = {}, {}, false
    for _, item in ipairs(type(liste) == 'table' and liste or {}) do
        local cle = cleDe(item.photo)
        local p = r.propositions[cle]
        local res = { photo = tonumber(item.photo) or item.photo }
        resultats[#resultats + 1] = res
        local ok, photo = LrTasks.pcall(Photos.photoParId, item.photo)
        if not ok then
            res.erreur = Liaison.messageErreur(photo)
        elseif p and p.uuid and Photos.brut(photo, 'uuid') ~= p.uuid then
            res.erreur = "Cette photo n'est plus celle que Claude a notée : proposition retirée."
            r.propositions[cle] = nil
            change = true
        elseif item.note == nil and item.drapeau == nil then
            if not p then
                res.erreur = "Aucune proposition de Claude pour cette photo."
            else
                local drapeau = p.drapeau == 'rejetee' and 'rejetee' or (drapeauDe(photo) == 'rejetee' and 'aucun' or nil)
                aPoser[#aPoser + 1] = { res = res, photo = photo, proposition = p,
                    note = { photo = photo.localIdentifier, note = p.note, drapeau = drapeau, raison = p.raison } }
            end
        else
            aPoser[#aPoser + 1] = { res = res, photo = photo, proposition = p,
                note = { photo = photo.localIdentifier, note = item.note, drapeau = item.drapeau, raison = texte(item.raison) or (p and p.raison) } }
        end
    end
    if #aPoser == 0 then
        if change then
            changer('propositions')
        end
        local premiere = resultats[1] and resultats[1].erreur or "Aucune note à poser."
        return { ok = false, erreur = premiere, resultats = resultats }
    end

    local Bibliotheque = require 'Bibliotheque'
    local erreur
    for debut = 1, #aPoser, Notation.LOT do
        local lot, notes = {}, {}
        for i = debut, math.min(debut + Notation.LOT - 1, #aPoser) do
            lot[#lot + 1] = aPoser[i]
            notes[#notes + 1] = aPoser[i].note
        end
        local ok, reponse = LrTasks.pcall(Bibliotheque.noter, { notes = notes, etape = 'notation', depuisLightroom = true, confirme = true })
        if not ok then
            -- Rien de ce lot ni des suivants n'est écrit.
            erreur = Liaison.messageErreur(reponse)
            for i = debut, #aPoser do
                aPoser[i].res.erreur = erreur
            end
            break
        end
        change = true
        local parId = {}
        for _, resultat in ipairs(reponse.resultats or {}) do
            parId[cleDe(resultat.photo and resultat.photo.id)] = resultat
        end
        for _, a in ipairs(lot) do
            local res, photo, p = a.res, a.photo, a.proposition
            local ecrit = parId[cleDe(photo.localIdentifier)] or {}
            res.changements, res.remarques = ecrit.changements, ecrit.remarques
            res.note, res.drapeau = tonumber(Photos.brut(photo, 'rating')) or 0, drapeauDe(photo)
            -- Une proposition remplacée pendant l'écriture n'est pas celle que l'utilisateur a vue.
            if p and r.propositions[cleDe(photo.localIdentifier)] == p then
                local telleQuelle
                if p.drapeau == 'rejetee' then
                    telleQuelle = res.drapeau == 'rejetee'
                else
                    telleQuelle = res.note == p.note and res.drapeau ~= 'rejetee'
                end
                p.etat = telleQuelle and 'acceptee' or 'changee'
                p.note_choisie = not telleQuelle and res.note or nil
                p.drapeau_choisi = not telleQuelle and res.drapeau or nil
                p.decide_le = os.time()
                res.etat = p.etat
            end
        end
    end
    if change then
        changer('pose')
    end
    return { ok = erreur == nil, erreur = erreur, resultats = resultats }
end

return Notation
