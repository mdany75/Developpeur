-- essais-seance.lua : essais de la fenêtre « Claude · Séance de notation » (FenetreNotation.lua)
-- hors de Lightroom (LuaJIT, Lightroom simulé par Simulation.lua). La fenêtre est éprouvée seule :
-- le registre des notes (Notation), le moteur (Moteur), les passes (Consignes.passes), le fil
-- (Fil), les photos et collections (Publication), les vignettes (Vignettes, Images) sont des
-- doubles locaux qui gardent les appels reçus. Ni Claude, ni quota, ni écriture dans un catalogue.
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

-- Photos 1001 à 1014 : nom, note (rating), drapeau (pickStatus), nombre de modifications, date de
-- prise de vue (dans l'ordre des identifiants).
local PHOTOS = {}
for id = 1001, 1014 do
    local ph = { localIdentifier = id, nom = 'DSCF' .. id .. '.RAF', note = nil, drapeau = 0, edition = 1, date = 600000000 + id }
    function ph:getFormattedMetadata(cle)
        return cle == 'fileName' and self.nom or nil
    end
    -- Sans valeur pour une clé inconnue (pas même nil), comme une fonction qui ne rend rien.
    function ph:getRawMetadata(cle)
        if cle == 'rating' then
            if self.note == nil then
                return
            end
            return self.note
        elseif cle == 'pickStatus' then
            return self.drapeau
        elseif cle == 'editCount' then
            return self.edition
        elseif cle == 'dateTimeOriginal' then
            return self.date
        end
    end
    PHOTOS[id] = ph
end
S.catalogue.getPhotoByLocalId = function(_, id) return PHOTOS[tonumber(id)] end
S.catalogue.batchGetRawMetadata = function(_, liste, cles)
    egal('dateTimeOriginal', cles[1])
    local r = {}
    for _, ph in ipairs(liste) do
        r[ph] = { dateTimeOriginal = ph.date }
    end
    return r
end

-- Doubles ---------------------------------------------------------------------------------------

-- Registre des notes (Notation.lua) : séances, propositions par photo (clé texte), appels gardés.
local Notation = { version = 0, observateurs = {} }
local function changerRegistre(quoi)
    Notation.version = Notation.version + 1
    for _, fn in pairs(Notation.observateurs) do
        fn(quoi)
    end
end
function Notation.reinitialiser()
    Notation.seances, Notation.props, Notation.active = {}, {}, nil
    Notation.appels = { ouvrirSeance = {}, choisirPasse = {}, poser = {}, decider = {} }
    Notation.version = Notation.version + 1
end
function Notation.abonner(nom, fn) Notation.observateurs[nom] = fn end
function Notation.desabonner(nom) Notation.observateurs[nom] = nil end
function Notation.ouvrirSeance(args)
    table.insert(Notation.appels.ouvrirSeance, copie(args))
    local id = 'seance-' .. #Notation.appels.ouvrirSeance
    Notation.seances[id] = { id = id, titre = args.titre, source = copie(args.source), photos = copie(args.photos), passe = 1, cree = os.time() }
    Notation.active = id
    changerRegistre('seance')
    return id
end
function Notation.seanceActive() return Notation.active end
function Notation.seance(id) return copie(Notation.seances[id or Notation.active]) end
function Notation.choisirPasse(id, n)
    table.insert(Notation.appels.choisirPasse, { id, n })
    Notation.seances[id].passe = n
    changerRegistre('seance')
end
function Notation.propositions(id)
    local s = Notation.seances[id or Notation.active]
    local liste = {}
    for _, photo in ipairs(s and s.photos or {}) do
        local p = Notation.props[tostring(photo)]
        if p and p.seance == s.id then
            liste[#liste + 1] = copie(p)
        end
    end
    return liste
end
function Notation.compter(id)
    local function zero() return { proposees = 0, acceptees = 0, changees = 0, a_verifier = 0, ecartees = 0, total = 0 } end
    local c = zero()
    c.par_passe = { zero(), zero(), zero(), zero() }
    for _, p in ipairs(Notation.propositions(id)) do
        for _, x in ipairs({ c, c.par_passe[p.passe] }) do
            x.total = x.total + 1
            if p.etat == 'proposee' then
                x.proposees = x.proposees + 1
            elseif p.etat == 'acceptee' or p.etat == 'changee' then
                x.acceptees = x.acceptees + 1
            elseif p.etat == 'a_verifier' then
                x.a_verifier = x.a_verifier + 1
            elseif p.etat == 'ecartee' then
                x.ecartees = x.ecartees + 1
            end
        end
    end
    return c
end
function Notation.decider(idPhoto, etat, details)
    table.insert(Notation.appels.decider, { idPhoto, etat, copie(details) })
    local p = Notation.props[tostring(idPhoto)]
    if not p then
        return nil, "Aucune proposition de Claude pour cette photo."
    end
    p.etat = etat
    changerRegistre('decision')
    return true
end
-- Pose comme le registre : sans note ni drapeau, la proposition telle quelle.
function Notation.poser(liste)
    table.insert(Notation.appels.poser, copie(liste))
    local resultats = {}
    for _, item in ipairs(liste) do
        local p = Notation.props[tostring(item.photo)]
        if item.note == nil and item.drapeau == nil then
            p.etat = 'acceptee'
            PHOTOS[item.photo].note = p.note
        else
            if p then
                p.etat, p.note_choisie, p.drapeau_choisi = 'changee', item.note, item.drapeau
            end
            PHOTOS[item.photo].note = item.note
        end
        resultats[#resultats + 1] = { photo = item.photo, etat = p and p.etat }
    end
    changerRegistre('pose')
    return { ok = true, resultats = resultats }
end
-- Pour les essais : une proposition de Claude dans la séance active.
function Notation.proposer(photo, champs)
    local p = { photo = photo, fichier = PHOTOS[photo].nom, note = 3, drapeau = 'aucun', passe = 1, etat = 'proposee',
        seance = Notation.active, criteres = {}, raison = '' }
    for cle, valeur in pairs(champs or {}) do
        p[cle] = valeur
    end
    Notation.props[tostring(photo)] = p
    changerRegistre('propositions')
    return p
end

-- Moteur : une conversation ouverte (la fenêtre Claude), celles des séances, les demandes reçues.
local Moteur = { observateurs = {} }
function Moteur.reinitialiser()
    Moteur.travaille, Moteur.enCours, Moteur.refus, Moteur.interrompu = false, nil, nil, 0
    Moteur.courante = { id = 'courante', titre = 'Retouche', elements = {} }
    Moteur.conversations = { Moteur.courante }
    Moteur.envois, Moteur.seancesCreees = {}, 0
end
function Moteur.abonner(nom, fn) Moteur.observateurs[nom] = fn end
function Moteur.desabonner(nom) Moteur.observateurs[nom] = nil end
function Moteur.charger() end
function Moteur.nouvelleSeance(options)
    for _, c in ipairs(Moteur.conversations) do
        if c.genre == 'notation' and tostring(c.seance) == tostring(options.seance) then
            return c
        end
    end
    Moteur.seancesCreees = Moteur.seancesCreees + 1
    local c = { id = 'conversation-seance-' .. Moteur.seancesCreees, genre = 'notation', titre = options.titre, titreChoisi = true,
        seance = options.seance, elements = {} }
    table.insert(Moteur.conversations, 1, c)
    return c
end
function Moteur.envoyer(texte, options)
    table.insert(Moteur.envois, { texte = texte, options = options })
    if Moteur.refus then
        return false, Moteur.refus
    end
    if Moteur.travaille then
        return false, "Claude travaille encore."
    end
    Moteur.travaille = true
    Moteur.enCours = options and options.conversation or Moteur.courante
    return true
end
function Moteur.interrompre() Moteur.interrompu = Moteur.interrompu + 1 end
function Moteur.texteTravail(_, vue)
    if not Moteur.travaille then
        return ''
    end
    return Moteur.enCours ~= vue and "Claude travaille · dans la fenêtre Claude" or "Claude travaille · 2 outils faits"
end

-- Les passes : un message qui donne la séance, ses photos et la passe.
local Consignes = { passes = {} }
for n = 1, 4 do
    Consignes.passes[n] = { titre = n .. ' · Passe ' .. n, question = "Question de la passe " .. n .. " ?",
        message = function(seance)
            return string.format("Passe %d de la séance %s (passe enregistrée %s) : %s", n, seance.id, tostring(seance.passe), table.concat(seance.photos, ', '))
        end }
end

-- Le fil : une ligne par élément.
local Fil = { appels = 0 }
function Fil.lignes(c, largeur, cache)
    Fil.appels, Fil.largeurDemandee = Fil.appels + 1, largeur
    local lignes = {}
    for i, e in ipairs(c.elements) do
        lignes[#lignes + 1] = { genre = e.genre, texte = e.texte, element = i, icone = e.genre == 'dany' and 'dany' or nil }
    end
    return lignes
end
function Fil.fenetre(total, nombre, defilement)
    local maxi = math.max(0, total - nombre)
    defilement = math.max(0, math.min(defilement or 0, maxi))
    return math.max(1, total - nombre - defilement + 1), defilement
end

-- Photos visées et collections (comme Publication.lua).
local Publication = {}
function Publication.photos(portee, idCollection)
    if portee == 'collection' then
        return idCollection == 900 and (S.photosCollection or {}) or {}
    end
    if not S.photoActive then
        return {}
    end
    return S.selection or {}
end
function Publication.collections() return { { title = 'Développeur › Essais', value = 900 } } end

-- Vignettes de Lightroom : un chemin par photo, sauf celles de Vignettes.sans.
local Vignettes = {}
function Vignettes.demander(photos, taille, dossier)
    table.insert(Vignettes.demandes, { photos = copie(photos), taille = taille, dossier = dossier })
    local chemins, erreurs = {}, {}
    for _, id in ipairs(photos) do
        if Vignettes.sans[id] then
            erreurs[id] = "aperçu manquant"
        else
            chemins[id] = dossier .. '/' .. id .. '.jpg'
        end
    end
    return chemins, erreurs
end
local Images = {}
function Images.vignette(dossier, nom, cote)
    table.insert(Images.reductions, { dossier = dossier, nom = nom, cote = cote })
    return dossier .. '/.vignettes/' .. nom:gsub('%.jpg$', '') .. '-' .. cote .. '.jpg'
end

package.loaded.Notation = Notation
package.loaded.Moteur = Moteur
package.loaded.Consignes = Consignes
package.loaded.Fil = Fil
package.loaded.Publication = Publication
package.loaded.Vignettes = Vignettes
package.loaded.Images = Images

-- Les erreurs que la fenêtre note dans son journal font échouer l'essai.
local Journal = require 'Journal'
local noterVraiment = Journal.noter
local journal = {}
Journal.noter = function(...)
    journal[#journal + 1] = table.concat({ ... }, ' ')
    return noterVraiment(...)
end

local Chemins = require 'Chemins'
local Fichiers = require 'Fichiers'
local FenetreNotation = require 'FenetreNotation'

-- Aides ------------------------------------------------------------------------------------------

local function parcourir(vue, fn)
    fn(vue)
    for _, enfant in ipairs(vue.args or {}) do
        if type(enfant) == 'table' and enfant.genre then
            parcourir(enfant, fn)
        end
    end
end

-- Les propriétés que le SDK connaît (comme Tests/Lua/Fenetre/tests.lua).
local PROPRIETES = {}
for nom in ([[bind_to_object tooltip visible enabled font size title value items action width height fill fill_horizontal
    fill_vertical place_horizontal place_vertical margin margin_horizontal margin_vertical margin_left margin_right margin_top
    margin_bottom place spacing width_in_chars height_in_lines width_in_digits truncation selectable alignment text_color
    mouse_down immediate validate placeholder_string wraps allows_multiple_selection value_equal frame_width frame_color
    background_color horizontal_scroller vertical_scroller show_title min max precision checked_value unchecked_value
    string_to_value value_to_string photo]]):gmatch('%S+') do
    PROPRIETES[nom] = true
end

-- Vues et propriétés connues du SDK, liaisons avec une valeur, boutons avec une action, polices
-- complètes. Rend le nombre de vues.
local function verifierVues(contenu, p)
    local vues = 0
    parcourir(contenu, function(v)
        vues = vues + 1
        for cle, valeur in pairs(v.args) do
            if type(cle) == 'string' then
                vrai(PROPRIETES[cle], 'propriété inconnue du SDK : ' .. cle .. ' (' .. v.genre .. ')')
                if type(valeur) == 'table' and valeur.liaison then
                    vrai(p[valeur.key] ~= nil, 'liaison sans valeur : ' .. valeur.key .. ' (' .. v.genre .. '.' .. cle .. ')')
                    if valeur.transform then
                        valeur.transform(p[valeur.key], true)
                    end
                end
                if cle == 'font' then
                    vrai(type(valeur) == 'table' and valeur.name and valeur.size, 'police incomplète (' .. v.genre .. ')')
                end
            end
        end
        if v.genre == 'push_button' then
            vrai(type(v.args.action) == 'function', 'bouton sans action : ' .. tostring(v.args.title))
        end
    end)
    return vues
end

-- La première vue qui répond à `test`.
local function trouver(contenu, test)
    local trouvee
    parcourir(contenu, function(v)
        if not trouvee and test(v) then
            trouvee = v
        end
    end)
    vrai(trouvee, 'vue introuvable')
    return trouvee
end

-- Un bouton par son titre (texte, ou clé de son titre lié).
local function bouton(contenu, titre)
    return trouver(contenu, function(v)
        local t = v.args.title
        return v.genre == 'push_button' and (t == titre or (type(t) == 'table' and t.key == titre))
    end)
end

local function cliquer(contenu, titre)
    bouton(contenu, titre).args.action()
end

-- Les tâches en attente, dans l'ordre (la boucle de la fenêtre ne tourne pas : FenetreNotation.tour
-- la remplace ; une réouverture attend l'essai qui la veut).
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

-- Quelques tours de boucle, jusqu'à ce que plus rien n'attende.
local function tourner()
    for _ = 1, 6 do
        FenetreNotation.tour(1)
        lancerTaches()
    end
end

local function sansErreur()
    vrai(#journal == 0, 'journal de la fenêtre : ' .. table.concat(journal, ' | '))
end

local function reinitialiser()
    Notation.reinitialiser()
    Moteur.reinitialiser()
    Vignettes.demandes, Vignettes.sans = {}, {}
    Images.reductions = {}
    Fil.appels = 0
    for _, ph in pairs(PHOTOS) do
        ph.note, ph.drapeau, ph.edition = nil, 0, 1
    end
    journal = {}
    S.taches = {}
    S.reponseConfirm = nil
    S.photoActive, S.selection, S.photosCollection = nil, nil, nil
    FenetreNotation.choisie = nil
    FenetreNotation.page = 1
end

-- Une séance de `n` photos (1001…) ouverte dans le registre, active.
local function seance(n)
    local ids = {}
    for i = 1, n do
        ids[i] = 1000 + i
    end
    return Notation.ouvrirSeance { titre = 'Essai', source = { portee = 'selection' }, photos = ids }
end

-- Ouvre la fenêtre et appelle fn(p, args) pendant qu'elle est ouverte. Une erreur de l'essai
-- attend la fermeture de la fenêtre (sinon elle resterait « ouverte » pour les essais suivants).
local function ouvrir(fn, options)
    vrai(not FenetreNotation.ouverte, 'une fenêtre est restée ouverte')
    local ouverte, erreur = false, nil
    S.pendantFenetre = function(args)
        ouverte = true
        local ok, e = xpcall(function()
            lancerTaches()
            tourner()
            fn(FenetreNotation.p, args)
        end, debug.traceback)
        erreur = not ok and e or nil
    end
    FenetreNotation.afficher(options)
    S.pendantFenetre = nil
    vrai(ouverte, "la fenêtre ne s'est pas ouverte")
    egal(false, FenetreNotation.ouverte, 'fenêtre fermée')
    if erreur then
        error(erreur, 0)
    end
end

-- Essais ----------------------------------------------------------------------------------------

essai('Menus : « Séance de notation… » dans les deux listes, après « Consommation… »', function()
    local Info = dofile(S.plugin .. '/Info.lua')
    for _, liste in ipairs({ Info.LrExportMenuItems, Info.LrLibraryMenuItems }) do
        local rang
        for i, item in ipairs(liste) do
            if item.file == 'MenuNotation.lua' then
                rang = i
                egal('Séance de notation…', item.title)
            end
        end
        vrai(rang, 'entrée MenuNotation.lua absente')
        egal('Consommation…', liste[rang - 1].title)
    end
    -- Le menu ouvre la fenêtre, sans options.
    local appels = {}
    package.loaded.FenetreNotation = { afficher = function(...) appels[#appels + 1] = select('#', ...) end }
    dofile(S.plugin .. '/MenuNotation.lua')
    package.loaded.FenetreNotation = FenetreNotation
    egal(1, #appels)
    egal(0, appels[1], 'sans options')
end)

essai('Séance : construction (liaisons, boutons, titre, cadre gardé)', function()
    reinitialiser()
    S.photoActive = PHOTOS[1003]
    S.selection = { PHOTOS[1003], PHOTOS[1001] }
    ouvrir(function(p, args)
        egal('Claude · Séance de notation', args.title)
        egal('DeveloppeurNotation', args.save_frame)
        vrai(args.blockTask, 'blockTask')
        vrai(type(args.selectionChangeObserver) == 'function', 'selectionChangeObserver')
        local vues = verifierVues(args.contents, p)
        vrai(vues > 300, vues .. ' vues')
        egal('Aucune séance ouverte', p.titreSeance)
        egal('2 photos sélectionnées.', p.textePhotos)
        egal(true, p.peutOuvrir)
        egal(false, p.peutLancer, 'pas de passe sans séance')
        egal(false, p.peutEnvoyer)
        egal(false, p.aSeance)
        egal(900, p.collection, 'première collection proposée')
        egal('Développeur › Essais', p.collections[1].title)
        contient(p.t1, "Ouvrez une séance")
        -- Le changement de sélection de Lightroom recompte la source.
        S.selection = { PHOTOS[1003] }
        args.selectionChangeObserver()
        tourner()
        egal('1 photo sélectionnée.', p.textePhotos)
        -- Chaque bouton annule l'envoi automatique de la demande tapée (le clic valide le champ).
        local boutons = 0
        parcourir(args.contents, function(v)
            if v.genre == 'push_button' then
                boutons = boutons + 1
                FenetreNotation.envoiAuto = {}
                v.args.action()
                egal(nil, FenetreNotation.envoiAuto, 'envoi automatique après ' .. tostring(type(v.args.title) == 'table' and v.args.title.key or v.args.title))
            end
        end)
        vrai(boutons >= 16, boutons .. ' boutons')
        -- ↻ a demandé une réouverture, et les autres boutons leurs tâches : on n'en veut pas ici.
        FenetreNotation.aRouvrir = false
        S.taches = {}
    end)
    sansErreur()
end)

essai("Séance : ouvrir une séance fige ses photos, dans l'ordre de la prise de vue", function()
    reinitialiser()
    S.photoActive = PHOTOS[1007]
    S.selection = {}
    for _, id in ipairs({ 1007, 1003, 1014, 1001, 1002, 1004, 1005, 1006, 1008, 1009, 1010, 1011, 1012, 1013 }) do
        S.selection[#S.selection + 1] = PHOTOS[id]
    end
    ouvrir(function(p, args)
        egal('14 photos sélectionnées.', p.textePhotos)
        cliquer(args.contents, 'Ouvrir la séance')
        lancerTaches()
        tourner()
        egal(1, #Notation.appels.ouvrirSeance)
        local a = Notation.appels.ouvrirSeance[1]
        egal(14, #a.photos)
        for i = 1, 14 do
            egal(1000 + i, a.photos[i], 'ordre de la prise de vue, rang ' .. i)
        end
        egal('selection', a.source.portee)
        egal(nil, a.source.collection)
        vrai(a.titre:find('^Sélection du %d+ '), a.titre)
        -- La sélection change dans Lightroom : la séance garde ses photos.
        S.selection = { PHOTOS[1001] }
        FenetreNotation.aRecalculer = true
        tourner()
        egal('1 photo sélectionnée.', p.textePhotos)
        egal(14, #FenetreNotation.seance.photos)
        contient(p.titreSeance, 'Sélection du')
        contient(p.resumeSeance, '14 photos')
        egal(true, p.peutLancer)
        egal(true, p.aSeance)
        egal(1001, FenetreNotation.choisie, 'la première photo dans la fiche')
        contient(p.t1, "Lancez une passe")
        -- Une autre séance : confirmation ; refusée, rien ne change.
        S.reponseConfirm = 'cancel'
        FenetreNotation.ouvrirSeance()
        egal(1, #Notation.appels.ouvrirSeance)
        -- Une collection.
        S.photosCollection = { PHOTOS[1005], PHOTOS[1002] }
        p.portee = 'collection'
        tourner()
        egal('2 photos dans la collection.', p.textePhotos)
        S.reponseConfirm = 'ok'
        FenetreNotation.ouvrirSeance()
        egal(2, #Notation.appels.ouvrirSeance)
        local b = Notation.appels.ouvrirSeance[2]
        egal('collection', b.source.portee)
        egal(900, b.source.collection)
        egal('Développeur › Essais', b.titre)
        egal(1002, b.photos[1])
        tourner()
        egal('Séance « Développeur › Essais »', p.titreSeance)
        egal(1002, FenetreNotation.choisie)
        -- Sans photo : refusée.
        S.photosCollection = {}
        FenetreNotation.ouvrirSeance()
        egal(2, #Notation.appels.ouvrirSeance)
        contient(p.message, 'Aucune photo')
    end)
    S.reponseConfirm = nil
    sansErreur()
end)

essai('Séance : planche par pages de 12, vignettes demandées une fois par retouche', function()
    reinitialiser()
    seance(14)
    PHOTOS[1004].note = 2
    ouvrir(function(p, args)
        egal('Page 1 sur 2 · 14 photos', p.pageTexte)
        egal('▸ 1 · DSCF1001', p.nom1, 'la photo choisie est marquée')
        egal('12 · DSCF1012', p.nom12)
        egal('★★☆☆☆', p.etoiles4, 'note posée sans proposition')
        egal('posée dans Lightroom', p.etatTexte4)
        egal('☆☆☆☆☆', p.etoiles5)
        egal('pas encore jugée', p.etatTexte5)
        egal(false, p.peutPagePrecedente)
        egal(true, p.peutPageSuivante)
        -- Vignettes : une demande pour la page, dans le dossier de la séance.
        egal(1, #Vignettes.demandes)
        local d = Vignettes.demandes[1]
        egal(12, #d.photos)
        egal(320, d.taille)
        contient(d.dossier, Chemins.temporaire() .. '/Notation/seance-1/')
        egal(true, p.aVignette1)
        egal(d.dossier .. '/.vignettes/1001-120.jpg', p.vignette1)
        egal(true, p.aFicheImage, 'vignette de la fiche')
        egal(d.dossier .. '/.vignettes/1001-300.jpg', p.ficheImage)
        -- Page suivante : deux photos, les autres cases vides.
        cliquer(args.contents, '▶')
        tourner()
        egal('Page 2 sur 2 · 14 photos', p.pageTexte)
        egal('13 · DSCF1013', p.nom1)
        egal('14 · DSCF1014', p.nom2)
        egal('', p.nom3)
        egal(false, p.aVignette3)
        egal('', p.attente3)
        egal(true, p.peutPagePrecedente)
        egal(false, p.peutPageSuivante)
        egal(2, #Vignettes.demandes)
        cliquer(args.contents, '◀')
        tourner()
        egal('▸ 1 · DSCF1001', p.nom1)
        egal(2, #Vignettes.demandes, 'les vignettes de la page 1 sont gardées')
        -- Une retouche (nombre de modifications) : seule cette vignette est redemandée.
        PHOTOS[1003].edition = 2
        FenetreNotation.aRafraichir = true
        tourner()
        egal(3, #Vignettes.demandes)
        egal(1, #Vignettes.demandes[3].photos)
        egal(1003, Vignettes.demandes[3].photos[1])
        contient(p.vignette3, '/.vignettes/1003-120.jpg')
        vrai(Vignettes.demandes[3].dossier ~= d.dossier, 'un dossier par lot')
        -- Sans aperçu dans Lightroom : la case le dit, sans redemander à chaque tour.
        Vignettes.sans[1005] = true
        PHOTOS[1005].edition = 3
        FenetreNotation.aRafraichir = true
        tourner()
        egal(false, p.aVignette5)
        egal('Pas de vignette', p.attente5)
        local demandes = #Vignettes.demandes
        FenetreNotation.tour(8)
        lancerTaches()
        egal(demandes, #Vignettes.demandes)
    end)
    sansErreur()
    egal(false, Fichiers.existe(FenetreNotation.dossier()), 'vignettes effacées à la fermeture')
end)

essai('Séance : choisir une case montre sa fiche', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1003, { note = 4, passe = 3, plafond = 4, raison = "Le panache se voit avant tout le reste.",
        criteres = { impact = "Fort : le panache", qualites = "Lumière douce", plancher = "Netteté 44 · nette" } })
    ouvrir(function(p, args)
        egal('★★★★☆', p.etoiles3)
        egal('orange', p.couleur3)
        egal('proposée · passe 3', p.etatTexte3)
        local nom = trouver(args.contents, function(v) return v.genre == 'static_text' and type(v.args.title) == 'table' and v.args.title.key == 'nom3' end)
        vrai(type(nom.args.mouse_down) == 'function', 'le nom se clique')
        FenetreNotation.envoiAuto = {}
        nom.args.mouse_down()
        egal(nil, FenetreNotation.envoiAuto, 'le clic n\'envoie pas la demande')
        tourner()
        egal(1003, FenetreNotation.choisie)
        egal('▸ 3 · DSCF1003', p.nom3)
        egal('1 · DSCF1001', p.nom1)
        egal('3 · DSCF1003.RAF', p.ficheNom)
        egal('3 sur 14', p.ficheRang)
        egal('Claude propose : ★★★★☆ (4 ★)', p.ficheProposee)
        egal('orange', p.ficheCouleur)
        egal('proposée · passe 3', p.ficheDecision)
        egal("Impact : Fort : le panache\nQualités : Lumière douce\nPlancher technique : Netteté 44 · nette", p.ficheCriteres)
        egal('Plafond mesuré : 4 ★', p.fichePlafond)
        egal("Le panache se voit avant tout le reste.", p.ficheRaison)
        egal('Accepter ★★★★☆', p.titreAccepter)
        egal(true, p.peutAccepter)
        egal(true, p.peutChanger)
        egal(true, p.peutVerifier)
        egal(true, p.peutEcarter)
        contient(p.fichePosee, '☆☆☆☆☆')
    end)
    sansErreur()
end)

essai('Séance : la fiche passe à la photo suivante, et la page suit', function()
    reinitialiser()
    seance(14)
    FenetreNotation.choisie = 1012
    ouvrir(function(p, args)
        egal('▸ 12 · DSCF1012', p.nom12)
        local suivante = trouver(args.contents, function(v)
            return v.genre == 'push_button' and type(v.args.enabled) == 'table' and v.args.enabled.key == 'peutPhotoSuivante'
        end)
        suivante.args.action()
        tourner()
        egal(1013, FenetreNotation.choisie)
        egal('Page 2 sur 2 · 14 photos', p.pageTexte)
        egal('▸ 13 · DSCF1013', p.nom1)
        egal('Aucune proposition de Claude pour cette photo.', p.ficheProposee)
        egal('', p.fichePlafond)
        egal(false, p.peutAccepter)
        egal(true, p.peutChanger, 'une note sans proposition se pose par Changer…')
        egal(false, p.peutVerifier)
        -- Un plafond de 0 (flou, yeux fermés) se dit en mots.
        Notation.proposer(1013, { note = nil, drapeau = 'rejetee', plafond = 0 })
        tourner()
        egal('Claude propose : ⚑ Rejeter', p.ficheProposee)
        egal('Plafond mesuré : 0 ★, défaut majeur', p.fichePlafond)
        egal('Accepter ⚑ Rejeter', p.titreAccepter)
        egal(true, p.peutAccepter)
    end)
    sansErreur()
end)

essai('Séance : Accepter pose la proposition telle quelle, dans une tâche', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 3, passe = 2 })
    ouvrir(function(p, args)
        egal(1001, FenetreNotation.choisie)
        cliquer(args.contents, 'titreAccepter')
        egal(0, #Notation.appels.poser, 'pas depuis l\'action du bouton')
        lancerTaches()
        egal(1, #Notation.appels.poser)
        local liste = Notation.appels.poser[1]
        egal(1, #liste)
        egal(1001, liste[1].photo)
        egal(nil, liste[1].note, 'la proposition telle quelle')
        egal(nil, liste[1].drapeau)
        tourner()
        egal('vert', p.couleur1)
        egal('acceptée · passe 2', p.etatTexte1)
        egal(false, p.peutAccepter)
        egal('1 note posée dans Lightroom.', p.message)
        egal('info', p.bandeau)
    end)
    sansErreur()
end)

essai('Séance : Tout accepter pose les propositions de la passe en un seul appel', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 2, passe = 1 })
    Notation.proposer(1002, { note = nil, drapeau = 'rejetee', passe = 1 })
    Notation.proposer(1004, { note = 3, passe = 1 })
    Notation.proposer(1005, { note = 3, passe = 1, etat = 'a_verifier', a_verifier = true })
    Notation.proposer(1006, { note = 3, passe = 2 })
    Notation.proposer(1007, { note = 2, passe = 1, etat = 'acceptee' })
    ouvrir(function(p, args)
        egal('Tout accepter · passe 1 (3)', p.titreToutAccepter)
        egal(true, p.peutToutAccepter)
        egal('3 proposées · 1 acceptée · 1 à vérifier', p.comptes1)
        egal('1 proposée', p.comptes2)
        egal('Claude ne propose aucune note ici.', p.comptes4)
        egal('⚑ Rejeter', p.etoiles2)
        -- Refusé à la confirmation : rien.
        S.reponseConfirm = 'cancel'
        cliquer(args.contents, 'titreToutAccepter')
        lancerTaches()
        egal(0, #Notation.appels.poser)
        S.reponseConfirm = 'ok'
        cliquer(args.contents, 'titreToutAccepter')
        lancerTaches()
        egal(1, #Notation.appels.poser, 'un seul appel')
        local liste = Notation.appels.poser[1]
        egal(3, #liste)
        egal(1001, liste[1].photo)
        egal(1002, liste[2].photo)
        egal(1004, liste[3].photo)
        for _, item in ipairs(liste) do
            egal(nil, item.note, 'proposition telle quelle')
        end
        tourner()
        egal('Tout accepter', p.titreToutAccepter)
        egal(false, p.peutToutAccepter)
        egal('3 notes posées dans Lightroom.', p.message)
        -- Passe 2 : la passe est rangée dans le registre, Tout accepter la suit.
        p.passe = 2
        lancerTaches()
        tourner()
        egal(1, #Notation.appels.choisirPasse)
        egal('seance-1', Notation.appels.choisirPasse[1][1])
        egal(2, Notation.appels.choisirPasse[1][2])
        egal('Tout accepter · passe 2 (1)', p.titreToutAccepter)
        egal('Lancer la passe 2', p.titreLancer)
    end)
    S.reponseConfirm = nil
    sansErreur()
end)

essai('Séance : Changer… pose la note choisie (5 ★ permis à l\'utilisateur)', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 4, passe = 3 })
    PHOTOS[1002].drapeau = -1
    local LrDialogs = S.modules.LrDialogs
    local modale = LrDialogs.presentModalDialog
    local choix
    LrDialogs.presentModalDialog = function(args)
        local q = args.contents.args.bind_to_object
        choix(q, args)
        return 'ok'
    end
    ouvrir(function(p, args)
        choix = function(q)
            egal(4, q.note, 'la note proposée par défaut')
            egal(false, q.rejeter)
            q.note = 5
        end
        cliquer(args.contents, 'Changer…')
        lancerTaches()
        egal(1, #Notation.appels.poser)
        local item = Notation.appels.poser[1][1]
        egal(1001, item.photo)
        egal(5, item.note)
        egal(nil, item.drapeau, 'un drapeau Retenue resterait')
        tourner()
        egal('vert', p.couleur1)
        egal('★★★★★', p.etoiles1)
        egal('changée · passe 3', p.etatTexte1)
        -- Une photo rejetée sans proposition : Changer… sans Rejeter retire le rejet.
        FenetreNotation.choisir(1002)
        tourner()
        egal('Posée dans Lightroom : ⚑ rejetée', p.fichePosee)
        choix = function(q)
            egal(true, q.rejeter)
            q.rejeter = false
            q.note = 2
        end
        cliquer(args.contents, 'Changer…')
        lancerTaches()
        egal(2, #Notation.appels.poser)
        item = Notation.appels.poser[2][1]
        egal(1002, item.photo)
        egal(2, item.note)
        egal('aucun', item.drapeau)
    end)
    LrDialogs.presentModalDialog = modale
    sansErreur()
end)

essai('Séance : À vérifier et Écarter ne touchent que le registre', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 3, passe = 2 })
    ouvrir(function(p, args)
        cliquer(args.contents, 'À vérifier')
        lancerTaches()
        egal(1, #Notation.appels.decider)
        egal(1001, Notation.appels.decider[1][1])
        egal('a_verifier', Notation.appels.decider[1][2])
        tourner()
        egal('rouge', p.couleur1)
        egal(false, p.peutVerifier)
        egal(true, p.peutEcarter)
        egal(true, p.peutAccepter, 'une photo à vérifier peut être acceptée')
        -- Pendant que Claude travaille : la décision reste permise (rien dans le catalogue).
        Moteur.travaille = true
        tourner()
        egal(true, p.peutEcarter)
        cliquer(args.contents, 'Écarter')
        lancerTaches()
        egal('ecartee', Notation.appels.decider[2][2])
        tourner()
        egal('gris', p.couleur1)
        egal(0, #Notation.appels.poser)
    end)
    sansErreur()
end)

essai('Séance : rien ne s\'écrit pendant que Claude travaille', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 3, passe = 1 })
    Notation.proposer(1002, { note = 3, passe = 1 })
    S.photoActive = PHOTOS[1001]
    S.selection = { PHOTOS[1001] }
    local LrDialogs = S.modules.LrDialogs
    local modale = LrDialogs.presentModalDialog
    local modales = 0
    LrDialogs.presentModalDialog = function() modales = modales + 1 return 'ok' end
    ouvrir(function(p, args)
        egal(true, p.peutAccepter)
        egal(true, p.peutToutAccepter)
        -- Claude travaille dans la fenêtre Claude.
        Moteur.travaille = true
        Moteur.enCours = Moteur.courante
        tourner()
        egal(false, p.libre)
        for _, cle in ipairs({ 'peutAccepter', 'peutToutAccepter', 'peutChanger', 'peutLancer', 'peutOuvrir', 'peutEnvoyer', 'peutChoisirPasse' }) do
            egal(false, p[cle], cle)
        end
        egal(false, p.peutArreter, 'la demande de la fenêtre Claude s\'arrête là-bas')
        egal('activite', p.bandeau)
        egal('Claude travaille · dans la fenêtre Claude', p.activite)
        -- Même appelées directement, les actions refusent.
        S.reponseConfirm = 'ok'
        egal(false, FenetreNotation.accepter())
        egal(false, FenetreNotation.toutAccepter())
        egal(false, FenetreNotation.changer())
        egal(false, FenetreNotation.lancerPasse())
        FenetreNotation.ouvrirSeance()
        p.saisie = 'Pourquoi ?'
        lancerTaches()
        egal(0, #Notation.appels.poser)
        egal(0, modales)
        egal(0, #Moteur.envois)
        egal(1, #Notation.appels.ouvrirSeance, 'seulement celle de l\'essai')
        contient(p.message, 'Claude travaille')
        -- Claude travaille dans la séance : Arrêter l'interrompt.
        Moteur.travaille = false
        p.saisie = ''
        FenetreNotation.lancerPasse()
        lancerTaches()
        egal(1, #Moteur.envois)
        egal(true, Moteur.travaille)
        tourner()
        egal(true, p.peutArreter)
        egal('Claude travaille · 2 outils faits', p.activite)
        cliquer(args.contents, 'Arrêter')
        egal(1, Moteur.interrompu)
        egal(false, p.peutAccepter)
    end)
    LrDialogs.presentModalDialog = modale
    S.reponseConfirm = nil
    sansErreur()
end)

essai('Séance : lancer une passe envoie son message dans la conversation de la séance', function()
    reinitialiser()
    seance(14)
    ouvrir(function(p, args)
        egal('Lancer la passe 1', p.titreLancer)
        p.passe = 3
        lancerTaches()
        tourner()
        egal('Lancer la passe 3', p.titreLancer)
        cliquer(args.contents, 'titreLancer')
        egal(0, #Moteur.envois, 'pas depuis l\'action du bouton')
        lancerTaches()
        egal(1, #Moteur.envois)
        local envoi = Moteur.envois[1]
        egal(Consignes.passes[3].message(Notation.seance('seance-1')), envoi.texte)
        contient(envoi.texte, 'passe enregistrée 3')
        local c = envoi.options.conversation
        egal('notation', c.genre)
        egal('seance-1', c.seance)
        egal('Séance · Essai', c.titre)
        egal('[Lightroom : séance de notation « Essai », 14 photos ; passe 3]', envoi.options.contexte)
        egal('courante', Moteur.courante.id, 'la conversation de la fenêtre Claude ne change pas')
        egal(1, Moteur.seancesCreees)
        egal(false, p.libre)
        -- La passe suivante reprend la même conversation. Partie, la demande désactive les boutons
        -- avant même que le moteur travaille (pas de second envoi par un double clic).
        Moteur.travaille = false
        p.passe = 4
        lancerTaches()
        tourner()
        egal(true, p.peutLancer)
        FenetreNotation.lancerPasse()
        egal(false, p.peutLancer)
        egal(false, p.peutEnvoyer)
        egal(false, p.peutToutAccepter)
        lancerTaches()
        egal(2, #Moteur.envois)
        egal(c, Moteur.envois[2].options.conversation)
        egal(1, Moteur.seancesCreees)
        contient(Moteur.envois[2].options.contexte, 'passe 4]')
    end)
    sansErreur()
end)

essai('Séance : une demande tapée part par Retour, avec la photo choisie', function()
    reinitialiser()
    seance(14)
    FenetreNotation.choisie = 1003
    ouvrir(function(p, args)
        p.saisie = 'Pourquoi la 3 est-elle à vérifier ?'
        vrai(FenetreNotation.envoiAuto, 'envoi automatique prévu')
        lancerTaches()
        egal(1, #Moteur.envois)
        egal('Pourquoi la 3 est-elle à vérifier ?', Moteur.envois[1].texte)
        egal('[Lightroom : séance de notation « Essai », 14 photos ; passe 1 ; photo choisie 1003 (DSCF1003.RAF)]', Moteur.envois[1].options.contexte)
        egal('', p.saisie)
        -- Un clic de bouton après la frappe : le texte reste dans le champ.
        Moteur.travaille = false
        p.saisie = 'Autre question'
        cliquer(args.contents, '▶')
        lancerTaches()
        egal(1, #Moteur.envois)
        egal('Autre question', p.saisie)
        -- Envoyer l'envoie.
        cliquer(args.contents, 'Envoyer')
        lancerTaches()
        egal(2, #Moteur.envois)
        -- Refusée par le moteur : le texte revient dans le champ, la raison s'affiche.
        Moteur.travaille = false
        Moteur.refus = "Budget de la semaine atteint."
        p.saisie = 'Et la 7 ?'
        lancerTaches()
        egal(3, #Moteur.envois)
        egal('Et la 7 ?', p.saisie)
        egal('Budget de la semaine atteint.', p.message)
        egal('erreur', p.bandeau)
        egal(nil, FenetreNotation.envoiAuto, 'le texte rendu ne repart pas')
        egal(0, #S.taches)
    end)
    sansErreur()
end)

essai('Séance : le filtre montre les proposées, les à vérifier ou les acceptées', function()
    reinitialiser()
    seance(14)
    Notation.proposer(1001, { note = 3 })
    Notation.proposer(1002, { note = 3, etat = 'a_verifier', a_verifier = true })
    Notation.proposer(1003, { note = 2, etat = 'acceptee' })
    Notation.proposer(1004, { note = 4, etat = 'changee', note_choisie = 3 })
    Notation.proposer(1005, { note = 1, etat = 'ecartee' })
    ouvrir(function(p, args)
        FenetreNotation.page = 2
        p.filtre = 'a_verifier'
        tourner()
        egal(1, FenetreNotation.page, 'retour à la première page')
        egal('2 · DSCF1002', p.nom1)
        egal('', p.nom2)
        egal('Page 1 sur 1 · 1 sur 14 photos', p.pageTexte)
        p.filtre = 'acceptees'
        tourner()
        egal('3 · DSCF1003', p.nom1)
        egal('4 · DSCF1004', p.nom2)
        egal('★★★☆☆', p.etoiles2, 'la note choisie')
        egal('', p.nom3)
        p.filtre = 'proposees'
        tourner()
        egal('▸ 1 · DSCF1001', p.nom1)
        egal('', p.nom2)
        p.filtre = 'toutes'
        tourner()
        egal('Page 1 sur 2 · 14 photos', p.pageTexte)
        egal('écartée · passe 1', p.etatTexte5)
        -- Rien pour ce filtre.
        Notation.props['1001'].etat = 'ecartee'
        p.filtre = 'proposees'
        tourner()
        egal('Aucune photo pour ce filtre.', p.pageTexte)
        egal('', p.nom1)
        egal('hors filtre', p.ficheRang)
    end)
    sansErreur()
end)

essai('Séance : changer de filtre ramène à la première page', function()
    reinitialiser()
    seance(14)
    for id = 1001, 1013 do
        Notation.proposer(id, { note = 3 })
    end
    Notation.proposer(1014, { note = 2, etat = 'acceptee' })
    ouvrir(function(p, args)
        cliquer(args.contents, '▶')
        tourner()
        egal('Page 2 sur 2 · 14 photos', p.pageTexte)
        p.filtre = 'proposees'
        tourner()
        egal('Page 1 sur 2 · 13 sur 14 photos', p.pageTexte)
        egal('▸ 1 · DSCF1001', p.nom1)
    end)
    sansErreur()
end)

essai('Séance : le fil montre la fin de la conversation de la séance', function()
    reinitialiser()
    seance(14)
    local c = Moteur.nouvelleSeance { titre = 'Séance · Essai', seance = 'seance-1' }
    for i = 1, 11 do
        c.elements[i] = { genre = i % 2 == 1 and 'dany' or 'claude', texte = 'ligne ' .. i }
    end
    ouvrir(function(p, args)
        egal(FenetreNotation.CENTRE - 20, Fil.largeurDemandee)
        egal('ligne 4', p.t1)
        egal('ligne 11', p.t8)
        egal('dany', p.i8)
        egal('claude', p.g7)
        egal(true, p.peutMonter)
        egal(false, p.peutDescendre)
        cliquer(args.contents, '▲')
        egal('ligne 1', p.t1)
        egal(true, p.peutDescendre)
        -- Une nouvelle ligne pendant la lecture ne déplace pas ce qu'on lit.
        c.elements[12] = { genre = 'claude', texte = 'ligne 12' }
        Moteur.observateurs.seance('fil')
        tourner()
        egal('ligne 1', p.t1)
        cliquer(args.contents, '▼')
        egal('ligne 12', p.t8)
    end)
    sansErreur()
end)

essai('Séance : une seule fenêtre, désabonnements à la fermeture', function()
    reinitialiser()
    seance(3)
    local LrDialogs = S.modules.LrDialogs
    local presenter = LrDialogs.presentFloatingDialog
    local fenetres, devant = 0, 0
    LrDialogs.presentFloatingDialog = function(plugin, args)
        fenetres = fenetres + 1
        args.onShow({ toFront = function() devant = devant + 1 end, close = function() end })
        S.pendantFenetre(args)
        args.windowWillClose()
    end
    local generation = FenetreNotation.generation
    ouvrir(function(p)
        vrai(Moteur.observateurs.seance, 'abonné au moteur')
        vrai(Notation.observateurs.seance, 'abonné au registre')
        egal(generation + 1, FenetreNotation.generation)
        egal('selection', p.portee)
        -- Le bouton Noter de la fenêtre Claude (plusieurs photos sélectionnées), ou Séance… : la
        -- fenêtre ouverte passe devant, la source changée.
        FenetreNotation.afficher { portee = 'collection', collection = 900 }
        egal(1, fenetres)
        egal(1, devant)
        egal('collection', p.portee)
        -- Un changement du registre la rafraîchit.
        FenetreNotation.aRafraichir = false
        Notation.observateurs.seance('propositions')
        egal(true, FenetreNotation.aRafraichir)
        Moteur.observateurs.seance('fil')
        egal(true, FenetreNotation.aRafraichirFil)
    end)
    LrDialogs.presentFloatingDialog = presenter
    egal(1, fenetres)
    egal(false, FenetreNotation.ouverte)
    egal(nil, FenetreNotation.p)
    egal(nil, Moteur.observateurs.seance)
    egal(nil, Notation.observateurs.seance)
    egal(0, #S.taches, 'aucune réouverture')
    sansErreur()
end)

essai('Séance : ↻ rouvre la fenêtre, brouillon et source gardés, sans envoi', function()
    reinitialiser()
    seance(3)
    S.photosCollection = { PHOTOS[1001] }
    ouvrir(function(p, args)
        p.portee = 'collection'
        p.saisie = 'Brouillon de question'
        cliquer(args.contents, '↻')
        egal(true, FenetreNotation.aRouvrir)
    end)
    -- La réouverture attend dans une tâche ; l'envoi automatique annulé ne part pas.
    local reouverture
    for i, tache in ipairs(S.taches) do
        if tache == FenetreNotation.afficher then
            reouverture = table.remove(S.taches, i)
        end
    end
    vrai(reouverture, 'réouverture prévue')
    lancerTaches()
    egal(0, #Moteur.envois)
    local generation = FenetreNotation.generation
    S.pendantFenetre = function()
        local p = FenetreNotation.p
        egal('Brouillon de question', p.saisie)
        egal('collection', p.portee)
        egal(nil, FenetreNotation.envoiAuto, 'le brouillon rendu ne part pas')
        egal(generation + 1, FenetreNotation.generation, 'une boucle par ouverture')
        lancerTaches()
        egal(0, #Moteur.envois)
    end
    reouverture()
    S.pendantFenetre = nil
    egal(false, FenetreNotation.aRouvrir)
    sansErreur()
end)

-- Fin ------------------------------------------------------------------------------------------

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
