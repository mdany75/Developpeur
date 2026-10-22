-- Notation.lua : le registre des notes que Claude propose (outil propose_ratings, commande
-- notation). Rien n'y est écrit dans le catalogue : Claude propose, « à vérifier », l'utilisateur
-- accepte ou change dans la carte Note de la fenêtre Claude ; seule une note acceptée ou changée
-- s'écrit, par Notation.poser (Bibliotheque.noter, une écriture, une étape par photo que undo_last
-- défait), ou une note que Dany a demandé à Claude de poser (propose_ratings avec apply). Le
-- registre ne voit pas l'annulation : la fenêtre le recale sur la note qu'elle relit
-- (Notation.recaler). La Séance de notation et ses séances sont retirées depuis la 1.1.1 (demandé
-- par Dany le 20 octobre 2026) : un registre plus ancien perd ses séances à la relecture.
--
-- La liaison (commande du serveur) et la fenêtre (carte Note) sont le même
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
-- Une proposition : { photo, uuid, fichier, note (0 à 5, nil pour un rejet), drapeau ('aucun' ou
-- 'rejetee'), criteres = { impact, qualites, plancher, finition }, plafond, raison, a_verifier,
-- passe, note_avant, drapeau_avant, etat, note_choisie, drapeau_choisi, le, decide_le,
-- commentaire }. etat : 'a_verifier' (toute proposition commence ainsi depuis la 1.1.1 : Dany
-- l'accepte ou la change ; a_verifier dit en plus que Claude doute), 'acceptee' (posée telle
-- quelle), 'changee' (posée autrement : note_choisie, drapeau_choisi), 'ecartee' ; 'proposee' :
-- celles d'avant la 1.1.1.

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

-- Claude propose de 0 à 5 étoiles (correctif 1.3.2, demandé par Dany le 22 octobre 2026 : ses
-- coups de cœur sont un libellé de couleur qu'il pose lui-même) ; au-delà, refus (second
-- garde-fou, après le serveur). La passe 4 (monter à 5, après le développement) est à Claude aussi.
Notation.NOTE_MAX_PROPOSEE = 5
Notation.PASSES = 4
-- Taille du registre, réécrit à chaque décision : les propositions les plus anciennes sortent
-- au-delà.
Notation.MAX_PROPOSITIONS = 2000
-- Photos au plus par écriture (comme une commande du serveur) : plus de photos à poser se posent
-- en plusieurs écritures.
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

-- Écritures de Notation.poser en cours. Elles rendent la main (écriture dans le catalogue, relecture
-- des photos) : une fenêtre a pu relever une photo avant que sa note y soit posée, et rien ne se
-- recale tant qu'elles durent (Notation.recaler).
local ecrituresEnCours = 0

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
    return { catalogue = catalogue, propositions = {} }
end

-- Registre relu du fichier : des tables neuves, des clés de photo en texte.
local function normaliser(r)
    r = copie(r)
    local propre = vide(texte(r.catalogue))
    for cle, p in pairs(type(r.propositions) == 'table' and r.propositions or {}) do
        if type(p) == 'table' and ETATS[p.etat] then
            p.photo = tonumber(p.photo) or tonumber(cle)
            p.seance = nil
            propre.propositions[cleDe(p.photo)] = p
        end
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

-- Les propositions les plus anciennes, au-delà de MAX_PROPOSITIONS.
local function elaguer(r)
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
    local ok, erreur = pcall(Fichiers.ecrire, Notation.fichier(), Json.encode({
        format = 2, catalogue = r.catalogue, propositions = r.propositions,
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

-- quoi : 'propositions', 'decision', 'pose' ou 'recalage'.
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

-- Propositions -------------------------------------------------------------------------

function Notation.proposition(idPhoto)
    if idPhoto == nil then
        return nil
    end
    return copie(charger().propositions[cleDe(idPhoto)])
end

-- L'évaluation d'une photo en une phrase, pour view_photo (Rendu.apercu) : « pas encore évaluée »,
-- « 3 ★ proposée par Claude, à vérifier », « acceptée par l'utilisateur : 3 ★ »…
function Notation.resume(idPhoto)
    local p = Notation.proposition(idPhoto)
    if not p then
        return "pas encore évaluée"
    end
    local function note(n, drapeau)
        return drapeau == 'rejetee' and "rejet" or (tostring(entier(n) or 0) .. " ★")
    end
    local proposee = note(p.note, p.drapeau)
    if p.etat == 'acceptee' then
        return "acceptée par l'utilisateur : " .. proposee
    elseif p.etat == 'changee' then
        return "changée par l'utilisateur : " .. note(p.note_choisie, p.drapeau_choisi) .. " (proposée : " .. proposee .. ")"
    elseif p.etat == 'ecartee' then
        return "proposition écartée par l'utilisateur (" .. proposee .. ")"
    end
    return proposee .. " proposée par Claude, à vérifier"
end

-- Décision sans rien écrire dans le catalogue : 'a_verifier', 'ecartee' (ou 'proposee' pour
-- revenir sur la décision ; plus appelée par la fenêtre depuis le retrait du bouton À vérifier). details.commentaire (ou raison) : son mot, gardé
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
-- photo introuvable va dans refusees sans bloquer les autres ; une note de plus de 5 refuse tout.
-- Une nouvelle proposition pour la même photo remplace l'ancienne. Une proposition « à vérifier »
-- (cas douteux) attend dans cet état. Avec `poser`, les notes sont aussi posées (plus bas).
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
        if d.note ~= nil and (not note or note < 0 or note > Notation.NOTE_MAX_PROPOSEE or note ~= math.floor(note)) then
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
    local passe = entier(params.passe)
    if passe and (passe < 1 or passe > Notation.PASSES) then
        echouer(string.format("Passe invalide : de 1 à %d.", Notation.PASSES))
    end

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
        local p = {
            photo = id, uuid = texte(Photos.brut(photo, 'uuid')), fichier = description.fichier,
            note = v.note, drapeau = v.drapeau, criteres = criteres, plafond = entier(d.plafond),
            raison = texte(d.raison), a_verifier = d.a_verifier == true,
            passe = passe,
            note_avant = tonumber(description.note) or 0,
            drapeau_avant = description.drapeau == 'rejetée' and 'rejetee' or (description.drapeau or 'aucun'),
            etat = 'a_verifier', le = maintenant,
        }
        r.propositions[cleDe(id)] = p
        reponses[#reponses + 1] = { photo = id, fichier = p.fichier, note_avant = p.note_avant, drapeau_avant = p.drapeau_avant,
            etat = p.etat }
    end
    if #reponses > 0 then
        Liaison.noter(string.format("Notation : %d proposition%s", #reponses, #reponses > 1 and "s" or ""))
        changer('propositions')
    end
    local reponse = { propositions = reponses, refusees = refusees }
    -- « Note ces photos » (propose_ratings avec apply, demandé par Dany le 20 octobre 2026) : les
    -- notes sont aussi posées, comme Accepter, « à vérifier » comprises ; la demande explicite vaut
    -- accord (confirme), la pause de la liaison et les garde-fous des photos restent.
    if params.poser == true and #reponses > 0 then
        local liste = {}
        for _, rep in ipairs(reponses) do
            liste[#liste + 1] = { photo = rep.photo }
        end
        local pose = Notation.poser(liste, { depuisLightroom = false, confirme = true })
        local posees = Json.tableau()
        for _, res in ipairs(pose.resultats or {}) do
            posees[#posees + 1] = { photo = res.photo, etat = res.etat, note = res.note, drapeau = res.drapeau,
                erreur = res.erreur, remarques = res.remarques }
        end
        reponse.posees = posees
        if pose.erreur then
            reponse.erreur_pose = pose.erreur
        end
    end
    return reponse
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

-- Commande « lire » : les propositions (de ces photos, ou toutes) avec leur état et les écarts
-- de l'utilisateur.
local function lire(params)
    local r = charger()
    local voulues
    if type(params.photos) == 'table' and #params.photos > 0 then
        voulues = {}
        for _, id in ipairs(params.photos) do
            voulues[cleDe(id)] = true
        end
    end
    local cles = {}
    for cle in pairs(r.propositions) do
        if not voulues or voulues[cle] then
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
    return { propositions = propositions, perdues = perdues > 0 and perdues or nil }
end

-- Commande « remettre » (la recette seulement, jamais un outil) : la proposition d'une photo telle
-- que la commande lire l'a rendue avant l'étape de la recette, ou aucune (proposition absente ou
-- null). Rien n'est écrit dans le catalogue. Le registre ne voit pas une annulation : la note que la
-- recette pose avec apply puis défait par undo_last y restait « acceptee », comme si Dany l'avait
-- acceptée, et Notation.recaler n'y voyait rien à reprendre, la photo ayant déjà cette note
-- (constaté le 21 octobre 2026, 53709912 à 2 ★). La proposition remise garde ses champs (état,
-- dates, critères), avec l'uuid de la photo ; une note de plus de NOTE_MAX_PROPOSEE, un état inconnu
-- ou une autre photo sont refusés sans rien changer.
local function remettre(params)
    local id = entier(params.photo)
    if not id then
        echouer("Photo manquante : rien n'est remis.")
    end
    local ok, photo = LrTasks.pcall(Photos.photoParId, id)
    if not ok then
        echouer(Liaison.messageErreur(photo))
    end
    local p = params.proposition
    local cle = cleDe(id)
    local r = charger()
    if p == nil or p == Json.null then
        r.propositions[cle] = nil
    else
        if type(p) ~= 'table' or entier(p.photo) ~= id or not ETATS[p.etat] then
            echouer(string.format("Proposition à remettre invalide pour la photo %d : rien n'est remis.", id))
        end
        local note = p.note ~= Json.null and tonumber(p.note) or nil
        if note and note > Notation.NOTE_MAX_PROPOSEE then
            echouer(string.format("Note au-delà de %d : rien n'est remis.", Notation.NOTE_MAX_PROPOSEE))
        end
        local q = copie(p)
        q.photo = id
        q.uuid = texte(Photos.brut(photo, 'uuid'))
        r.propositions[cle] = q
    end
    changer('propositions')
    Liaison.noter(string.format("Notation : proposition de la photo %d %s (recette)", id, r.propositions[cle] and "remise" or "retirée"))
    return { photo = id, proposition = r.propositions[cle] and pourReponse(r.propositions[cle]) or Json.null }
end

-- Commande notation du serveur : action proposer, lire ou remettre (la recette). Rien n'est écrit
-- dans le catalogue, sauf les notes de proposer avec poser (Notation.poser : pause et garde-fous des
-- photos).
function Notation.commande(params)
    local action = params.action
    if action == 'proposer' then
        return Notation.proposer(params)
    elseif action == 'lire' then
        return lire(params)
    elseif action == 'remettre' then
        return remettre(params)
    end
    echouer("Action de notation inconnue : " .. tostring(action) .. " (proposer, lire ou remettre).")
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
-- changements, remarques, erreur } } }. `options` (depuisLightroom, confirme ; vrais par défaut :
-- un clic dans la fenêtre) : faux pour une pose demandée à Claude (Notation.proposer avec poser),
-- que la pause de la liaison arrête.
function Notation.poser(liste, options)
    options = options or {}
    local depuisLightroom = options.depuisLightroom ~= false
    local confirme = options.confirme ~= false
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
    local function ecrireLots()
        for debut = 1, #aPoser, Notation.LOT do
            local lot, notes = {}, {}
            for i = debut, math.min(debut + Notation.LOT - 1, #aPoser) do
                lot[#lot + 1] = aPoser[i]
                notes[#notes + 1] = aPoser[i].note
            end
            local ok, reponse = LrTasks.pcall(Bibliotheque.noter, { notes = notes, etape = 'notation', depuisLightroom = depuisLightroom,
                confirme = confirme, outil = not depuisLightroom and 'propose_ratings' or nil })
            if not ok then
                -- Rien de ce lot ni des suivants n'est écrit.
                erreur = Liaison.messageErreur(reponse)
                for i = debut, #aPoser do
                    aPoser[i].res.erreur = erreur
                end
                return
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
    end
    ecrituresEnCours = ecrituresEnCours + 1
    local ok, echec = LrTasks.pcall(ecrireLots)
    ecrituresEnCours = ecrituresEnCours - 1
    if not ok then
        error(echec, 0)
    end
    -- La version change aussitôt (avant que changer ne rende la main) : un relevé fait avant
    -- l'écriture ne recale rien.
    if change then
        changer('pose')
    end
    return { ok = erreur == nil, erreur = erreur, resultats = resultats }
end

-- Recaler ----------------------------------------------------------------------------

local MOTS_DRAPEAU = { retenue = true, aucun = true, rejetee = true }

-- La photo porte-t-elle encore ce que la proposition acceptée ou changée y a posé ?
local function encorePosee(p, note, drapeau)
    if p.etat == 'acceptee' then
        if p.drapeau == 'rejetee' then
            return drapeau == 'rejetee'
        end
        return note == (tonumber(p.note) or 0) and drapeau ~= 'rejetee'
    end
    return (tonumber(p.note_choisie) == nil or note == tonumber(p.note_choisie))
        and (p.drapeau_choisi == nil or drapeau == p.drapeau_choisi)
end

-- Recale le registre sur ce que portent les photos, lu dans Lightroom par la fenêtre (carte Note) :
-- releves = { { photo = id, note = 0 à 5, drapeau = 'retenue',
-- 'aucun', 'rejetee' (ou pickStatus 1, 0, −1) } }. Le registre ne voit pas une annulation
-- (undo_last, ⌘Z) : la note quitte le catalogue, la proposition restait « acceptée » (constaté le
-- 20 octobre 2026). Une proposition acceptée ou changée dont la note ou le drapeau posés ne sont
-- plus là repasse donc « à vérifier » ('a_verifier', note et drapeau choisis effacés). `version` :
-- Notation.version lue avant les relevés ; si le registre a changé depuis (une note posée
-- entre-temps par une autre tâche), ou pendant une écriture de Notation.poser, rien n'est recalé :
-- la lecture suivante le fera. Une seule écriture du registre pour tous les relevés (une page de
-- la planche). Rend le nombre de propositions recalées.
function Notation.recaler(releves, version)
    -- Vérifié après le chargement, qui peut rendre la main ; la suite ne la rend pas.
    local r = charger()
    if ecrituresEnCours > 0 or (version ~= nil and version ~= Notation.version) then
        return 0
    end
    local n = 0
    for _, x in ipairs(type(releves) == 'table' and releves or {}) do
        local p = r.propositions[cleDe(x.photo)]
        local note = entier(x.note)
        local drapeau = DRAPEAUX[tonumber(x.drapeau)] or x.drapeau
        if p and (p.etat == 'acceptee' or p.etat == 'changee') and note and MOTS_DRAPEAU[drapeau]
            and not encorePosee(p, note, drapeau) then
            p.etat, p.note_choisie, p.drapeau_choisi, p.decide_le = 'a_verifier', nil, nil, nil
            n = n + 1
        end
    end
    if n > 0 then
        local s = n > 1 and "s" or ""
        Liaison.noter(string.format("Notation : %d note%s retirée%s dans Lightroom, de nouveau à décider", n, s, s))
        changer('recalage')
    end
    return n
end

return Notation
