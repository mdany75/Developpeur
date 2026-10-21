-- essais-integration.lua : la notation de bout en bout hors de Lightroom (LuaJIT, Lightroom simulé
-- par Simulation.lua), avec les vrais modules de chaque pièce : la commande notation telle que le
-- serveur l'envoie pour propose_ratings (relue par Json.decode), avec ou sans poser (« note ces
-- photos »), le registre (Notation), le fil (Conversation, Fil) et la carte Note de la fenêtre
-- Claude (Fenetre). Seuls l'écriture dans le catalogue (Bibliotheque.noter, éprouvée par la suite
-- de la liaison) et l'envoi à Claude Code (Moteur.envoyer, éprouvé par essais-moteur avec
-- faux-claude) sont remplacés : ils gardent les appels reçus. Ni Claude, ni quota.
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
    S.executer('/usr/bin/sips -s format jpeg -z 200 300 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(chemin) .. ' >/dev/null 2>&1')
    local f = assert(io.open(chemin, 'rb'), 'JPEG source')
    JPEG = f:read('*a')
    f:close()
end

-- Photos 2001 à 2006 : nom, uuid, note et drapeau posés, modifications, date de prise de vue.
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
local Journal = require 'Journal'
local Json = require 'Json'
local Moteur = require 'Moteur'
local Notation = require 'Notation'
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

-- Arbre de vues -------------------------------------------------------------------------------

local function parcourir(vue, fn)
    fn(vue)
    for _, enfant in ipairs(vue.args or {}) do
        if type(enfant) == 'table' and enfant.genre then
            parcourir(enfant, fn)
        end
    end
end

-- Ouvre la fenêtre Claude et appelle fn(p, args) pendant qu'elle est ouverte.
local function ouvrirFenetre(fn)
    S.taches = {}
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

-- La commande notation que le connecteur envoie pour propose_ratings (Tools+Notation.swift :
-- note 0 et drapeau « rejetee » pour un rejet, critères aux noms du module, plafond du dernier tri ;
-- poser avec apply), passée par JSON comme sur la liaison.
local function commandeDuConnecteur(poser)
    return Json.decode(Json.encode({
        action = 'proposer', passe = 1, poser = poser,
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

-- L'entrée de propose_ratings telle que Claude l'écrit (pour le fil de la conversation).
local function entreePropose(apply)
    local function critere(impact) return { impact = impact, qualities = "Lumière", technical_floor = "Nette" } end
    return { pass = 1, apply = apply, ratings = {
        { photo_id = 2001, rating = 3, criteria = critere("Fort"), reason = "Tient seule.", to_check = false },
        { photo_id = 2002, flag = 'reject', criteria = critere("Aucun"), reason = "Floue.", to_check = false },
        { photo_id = 2003, rating = 2, criteria = critere("Moyen"), reason = "Presque noire.", to_check = true },
        { photo_id = 9999, rating = 2, criteria = critere("-"), reason = "Inconnue.", to_check = false },
    } }
end

-- L'élément notation du fil, après l'appel et sa réponse.
local function elementNotation(c, apply, reponse)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'pr-' .. tostring(apply),
        nom = 'mcp__developpeur__propose_ratings', entree = entreePropose(apply) } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'pr-' .. tostring(apply),
        textes = { Json.encode(reponse) }, images = {}, erreur = false } } })
    local e
    for _, x in ipairs(c.elements) do
        if x.genre == 'notation' then
            e = x
        end
    end
    return e
end

local function titreDuFil(c)
    for _, l in ipairs(Fil.lignes(c, 480, {})) do
        if l.texte:find('^Notes ') then
            return l.texte
        end
    end
end

-- Essais ----------------------------------------------------------------------------------------

essai('Propositions du connecteur : rangées sans rien écrire, lues par le fil', function()
    local reponse = Notation.commande(commandeDuConnecteur())
    egal(nil, reponse.seance, 'plus de séance de notation')
    egal(nil, reponse.posees, 'sans poser : rien de posé')
    egal(3, #reponse.propositions)
    egal(1, #reponse.refusees)
    egal(9999, reponse.refusees[1].photo)
    egal('a_verifier', reponse.propositions[3].etat)
    egal(0, #ecritures, "rien d'écrit dans le catalogue")
    local c = Conversation.nouvelle()
    local e = elementNotation(c, nil, reponse)
    vrai(e, 'élément notation')
    egal('fait', e.etat)
    egal(nil, e.pose)
    egal('proposee', e.notes[1].etat)
    egal('DSCF2001.RAF', e.notes[1].fichier, 'le fichier lu dans la réponse du module')
    egal('refusee', e.notes[4].etat, 'la photo inconnue refusée')
    contient(titreDuFil(c), 'Notes proposées · passe 1 · 4 photos')
    sansErreur()
end)

essai('« Note ces photos » : poser pose les notes, à vérifier comprises ; le fil dit « Notes posées »', function()
    local reponse = Notation.commande(commandeDuConnecteur(true))
    egal(1, #ecritures, 'une écriture pour les trois photos')
    local params = ecritures[1]
    egal('notation', params.etape)
    egal(false, params.depuisLightroom, 'une demande à Claude, pas un clic : la pause de la liaison compte')
    egal(true, params.confirme, 'la demande explicite vaut accord')
    egal(3, #params.notes)
    egal(3, PHOTOS[2001].note)
    egal(-1, PHOTOS[2002].drapeau)
    egal(2, PHOTOS[2003].note, 'à vérifier comprise')
    egal(3, #reponse.posees)
    egal('acceptee', Notation.proposition(2003).etat)
    local c = Conversation.nouvelle()
    local e = elementNotation(c, true, reponse)
    egal(true, e.pose)
    egal('posee', e.notes[1].etat)
    egal('posee', e.notes[3].etat)
    egal('refusee', e.notes[4].etat)
    contient(titreDuFil(c), 'Notes posées · passe 1 · 4 photos')
    contient(Fil.texteNote(e.notes[1]), 'posée')
    sansErreur()
end)

essai('Carte Note de la fenêtre Claude : la proposition, Accepter par le registre', function()
    -- Une nouvelle proposition, à décider, pour 2003 (remet aussi sa note à zéro).
    PHOTOS[2003].note = 0
    Notation.commande(Json.decode(Json.encode({ action = 'proposer', passe = 1, propositions = {
        { photo = 2003, note = 2, drapeau = 'aucun', a_verifier = true, plafond = 2, raison = "Presque noire.",
            criteres = { impact = "Moyen.", qualites = "Ciel de nuit.", plancher = "Presque noire : plafond 2." } } } })))
    S.photoActive = PHOTOS[2003]
    S.selection = { PHOTOS[2003] }
    local avant = #ecritures
    ouvrirFenetre(function(p, args)
        Fenetre.majPhoto()
        Fenetre.rafraichirNotation()
        egal('Claude propose : ★★☆☆☆', p.notationProposee)
        egal('rouge', p.notationCouleur)
        egal('à vérifier · passe 1', p.notationEtat)
        contient(p.notationTexte, 'Plafond mesuré : 2 ★')
        egal(true, p.peutAccepterNote)
        -- Claude travaille : rien ne s'écrit depuis la carte.
        Moteur.travaille = true
        Fenetre.rafraichirNotation()
        egal(false, p.peutAccepterNote)
        Fenetre.poserNote({ photo = 2003 })
        egal(avant, #ecritures, 'rien posé pendant que Claude travaille')
        Moteur.travaille = false
        Fenetre.rafraichirNotation()
        -- Accepter : dans une tâche, la proposition telle quelle.
        local accepter
        parcourir(args.contents, function(v)
            -- Celui de la carte Note (la proposition de retouche a aussi le sien).
            if v.genre == 'push_button' and v.args.title == 'Accepter' and type(v.args.enabled) == 'table'
                and v.args.enabled.key == 'peutAccepterNote' then
                accepter = v
            end
        end)
        accepter.args.action()
        S.taches[#S.taches]()
        egal(avant + 1, #ecritures)
        local params = ecritures[#ecritures]
        egal(true, params.depuisLightroom, 'un clic dans la fenêtre')
        egal(2003, params.notes[1].photo)
        egal(2, params.notes[1].note)
        egal(2, PHOTOS[2003].note)
        egal('acceptee', Notation.proposition(2003).etat)
        Fenetre.majPhoto()
        Fenetre.rafraichirNotation()
        egal('vert', p.notationCouleur)
        egal('Note posée : ★★☆☆☆', p.notationPosee)
    end)
    sansErreur()
end)

essai('Registre relu du disque : décisions gardées ; jamais 5 étoiles ; consignes', function()
    Notation.oublier()
    egal('acceptee', Notation.proposition(2001).etat)
    egal('acceptee', Notation.proposition(2003).etat)
    local reponse = Notation.commande(Json.decode(Json.encode({ action = 'proposer', propositions = {
        { photo = 2005, note = 4, drapeau = 'aucun', a_verifier = false, raison = "De l'impact.",
            criteres = { impact = "Fort.", qualites = "Belle lumière.", plancher = "Nette (52)." } } } })))
    egal(nil, reponse.propositions[1].hors_seance)
    egal('a_verifier', Notation.proposition(2005).etat)
    -- Claude ne propose jamais 5 étoiles, même si le connecteur était contourné.
    local ok, refus = pcall(Notation.commande, { action = 'proposer', propositions = {
        { photo = 2006, note = 5, drapeau = 'aucun', raison = 'x', criteres = {} } } })
    vrai(not ok, '5 ★ refusées')
    contient(refus, 'jamais 5 étoiles')
    -- Les consignes parlent du même outil que le connecteur.
    contient(Consignes.texte, 'propose_ratings')
    contient(Consignes.texte, 'apply = true')
end)

essai('Après undo_last : la carte Note relit la note réelle (constaté), une écriture du registre', function()
    egal('acceptee', Notation.proposition(2003).etat)
    local Fichiers = require 'Fichiers'
    local ecrire, ecrits = Fichiers.ecrire, 0
    Fichiers.ecrire = function(chemin, ...)
        if chemin == Notation.fichier() then
            ecrits = ecrits + 1
        end
        return ecrire(chemin, ...)
    end
    -- undo_last retire la note de 2003 (acceptée par la carte) : Lightroom n'a plus de note, la
    -- carte la relit et la proposition est de nouveau à décider.
    PHOTOS[2003].note = 0
    S.photoActive = PHOTOS[2003]
    S.selection = { PHOTOS[2003] }
    local ok, e = pcall(ouvrirFenetre, function(p)
        Fenetre.majPhoto()
        egal('a_verifier', Notation.proposition(2003).etat, 'la carte recale le registre')
        egal(nil, Notation.proposition(2003).note_choisie)
        egal('Note posée : aucune, pas encore jugée', p.notationPosee)
        egal('rouge', p.notationCouleur, 'de nouveau à vérifier')
        egal('à vérifier · passe 1', p.notationEtat)
        egal(true, p.peutAccepterNote, 'de nouveau à accepter')
        Fenetre.majPhoto()
    end)
    Fichiers.ecrire = ecrire
    vrai(ok, e)
    egal(1, ecrits, 'une écriture pour la carte')
    sansErreur()
end)

-- 1.1.1 : à l'ouverture, l'aperçu montre la photo sélectionnée (demandé par Dany le 20 octobre
-- 2026), sa vignette du cache de Lightroom réduite au cadre par sips.
essai('Ouverture : l\'aperçu montre la photo active ; une image de Claude la remplace ; ◀ ▶ entre elles', function()
    local Fichiers = require 'Fichiers'
    local Images = require 'Images'
    local Stockage = require 'Stockage'
    S.photoActive = PHOTOS[2004]
    S.selection = { PHOTOS[2004] }
    Moteur.courante = Conversation.nouvelle()
    ouvrirFenetre(function(p)
        egal('Photo active · DSCF2004', p.legendeApercu)
        -- La vignette se prépare dans une tâche (rappel de Lightroom, puis sips). Fichier Fujifilm :
        -- le connecteur (ici un faux, qui recopie la vignette) y dessine le point de mise au point.
        local Vignettes = require 'Vignettes'
        local decrire = Vignettes.decrireVignette
        Vignettes.decrireVignette = function(photo)
            return { marque = 'FUJIFILM', chemin_original = '/Volumes/Photos/' .. photo.nom, geometrie = { largeur = 300, hauteur = 200 } }
        end
        local faux = S.home .. '/faux-connecteur.sh'
        local fs = assert(io.open(faux, 'w'))
        fs:write('#!/bin/sh\n[ "$1" = "--marquer-af" ] || exit 2\ncase "$2" in *.RAF) cp "$4" "$5" ;; *) exit 1 ;; esac\n')
        fs:close()
        S.executer('/bin/chmod +x ' .. S.q(faux))
        local prefs = require('Chemins').prefs()
        local connecteur = prefs.cheminConnecteur
        prefs.cheminConnecteur = faux
        local avant = #S.taches
        Fenetre.idActif, Fenetre.demandeActive = nil, nil
        Fenetre.majPhoto()
        egal(avant + 1, #S.taches, 'vignette demandée dans une tâche')
        egal(false, p.aImage, 'pas encore de vignette')
        S.taches[#S.taches]()
        Vignettes.decrireVignette = decrire
        prefs.cheminConnecteur = connecteur
        egal(true, p.aImage, 'Agrandir actif')
        vrai(Fenetre.apercuActif.fichier:find('%-af%.jpg$'), 'la vignette marquée par le connecteur : ' .. Fenetre.apercuActif.fichier)
        local l, h = Images.dimensions(p.imageApercu)
        egal(Fenetre.T.apercu, l, 'au cadre de l\'aperçu')
        egal(Fenetre.T.apercuHauteur or Fenetre.T.apercu, h)
        egal('Photo active · DSCF2004', p.legendeApercu)
        egal(false, p.peutPrecedente, 'aucune image dans la conversation')
        egal(false, p.peutSuivante)
        -- Claude regarde une photo : son image se montre à la place.
        local c = Moteur.courante
        Fichiers.creerDossier(Stockage.dossier(c.id))
        local f = assert(io.open(Stockage.dossier(c.id) .. '/apercu-1.jpg', 'wb'))
        f:write(JPEG)
        f:close()
        c.elements[#c.elements + 1] = { genre = 'resultat', images = { 'apercu-1.jpg' } }
        Fenetre.rafraichirApercu()
        egal(false, Fenetre.voirActive)
        vrai(p.legendeApercu:find('1 sur 1', 1, true), p.legendeApercu)
        egal(true, p.peutSuivante, '▶ : vers la photo active')
        -- ▶ : la photo active (vignette gardée) ; ◀ : de nouveau l'image de Claude.
        Fenetre.changerImage(1)
        egal('Photo active · DSCF2004', p.legendeApercu)
        egal(true, p.aImage)
        egal(true, p.peutPrecedente)
        Fenetre.changerImage(-1)
        vrai(p.legendeApercu:find('1 sur 1', 1, true), p.legendeApercu)
        -- Une autre photo choisie dans Lightroom : son aperçu se montre (nouvelle vignette), même
        -- sans nouvelle conversation.
        local prefs = require('Chemins').prefs()
        prefs.nouvelleParPhoto = false
        S.photoActive = PHOTOS[2005]
        S.selection = { PHOTOS[2005] }
        avant = #S.taches
        Fenetre.majPhoto()
        prefs.nouvelleParPhoto = true
        egal(c, Moteur.courante)
        egal('Photo active · DSCF2005', p.legendeApercu)
        egal(avant + 1, #S.taches, 'vignette de la nouvelle photo demandée')
        S.taches[#S.taches]()
        egal(true, p.aImage)
        vrai(p.imageApercu:find('DSCF2005', 1, true) or p.imageApercu:find('2005', 1, true), p.imageApercu)
    end)
    sansErreur()
end)

-- En dernier : il remet les photos 2001 à 2003 à « proposée ».
essai('« Note ces photos » refusé (pause) : le fil dit « Notes non posées », avec la raison sur chaque ligne', function()
    local Bibliotheque = package.loaded.Bibliotheque
    local noter = Bibliotheque.noter
    Bibliotheque.noter = function()
        error("La liaison est en pause dans Lightroom : rien n'a été écrit.", 0)
    end
    local avant = #ecritures
    local reponse = Notation.commande(commandeDuConnecteur(true))
    Bibliotheque.noter = noter
    egal(avant, #ecritures, 'rien posé')
    contient(reponse.erreur_pose, 'pause')
    -- Pendant l'appel : « Notes à poser », rien n'est encore posé.
    local c = Conversation.nouvelle()
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'pr-pause',
        nom = 'mcp__developpeur__propose_ratings', entree = entreePropose(true) } } })
    contient(titreDuFil(c), 'Notes à poser · passe 1 · 4 photos')
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'pr-pause',
        textes = { Json.encode(reponse) }, images = {}, erreur = false } } })
    local e
    for _, x in ipairs(c.elements) do
        e = x.genre == 'notation' and x or e
    end
    egal('proposee', e.notes[1].etat)
    contient(e.notes[1].refus, 'non posée : La liaison est en pause')
    contient(titreDuFil(c), 'Notes non posées · passe 1 · 4 photos')
    contient(Fil.texteNote(e.notes[1]), 'non posée')
    sansErreur()
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
