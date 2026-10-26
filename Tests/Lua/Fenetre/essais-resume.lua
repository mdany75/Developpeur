-- essais-resume.lua : le résumé que la fenêtre Claude montre en haut du fil (correctif 1.3.6,
-- deuxième retour de Dany du 25 octobre 2026), hors de Lightroom (LuaJIT, Lightroom simulé par
-- Simulation.lua) : ses textes pour une photo (prise de vue, note et drapeau, état, reprises à la
-- main, réglages hors de leur valeur par défaut) et pour un groupe (nombre, dates, appareils,
-- retouchées par Claude, notées, rejetées) ; leurs lectures, groupées, sinon une à une (les
-- premières d'un grand groupe) ; dans la fenêtre : à l'ouverture, en haut du fil, sous l'historique
-- de la photo ou le résumé court du groupe et au-dessus de la première demande de Dany (demandé par
-- Dany le 25 octobre 2026, d'abord en bas du fil), en tête du fil sans eux (au-dessus de l'aide
-- d'une conversation vide), d'aucun élément ; « Depuis la dernière fois » à sa place, sous lui ;
-- jamais en double, au retour sur la même photo non plus ; la page montrée à l'ouverture, le bas
-- du fil, et ce que lit un lecteur remonté, qu'il ne déplace pas (lu tout en haut, le fil y
-- reste) ; refait quand une autre photo ou un autre groupe change la conversation montrée, pas
-- quand la photo active change dans le même groupe ; jamais gardé dans la conversation, ni sur le disque, ni envoyé à Claude ; refait à la fin
-- d'un tour de Claude, jamais pendant son travail ; la note et le drapeau suivis sans relire le
-- catalogue ; rien pour une conversation sans photo ; refait quand le menu rappelle la fenêtre ;
-- aucun caractère non mesuré.
-- Le catalogue est complété ici, sans toucher Simulation.lua : des photos par identifiant, avec
-- leur prise de vue (textes de Lightroom), leur date, leur note et leur drapeau, leur journal de
-- Claude, editCount, lastEditTime et leurs réglages, et les trois lectures groupées du catalogue
-- (à brancher ou non). Claude Code est remplacé par une fausse session qui garde les messages
-- reçus : ni Claude, ni quota.
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
    if not tostring(texte or ''):find(morceau, 1, true) then
        error(string.format('%s : %q ne contient pas %q', quoi or 'texte', tostring(texte), morceau), 2)
    end
end

local function absent(texte, morceau, quoi)
    if tostring(texte or ''):find(morceau, 1, true) then
        error(string.format('%s : %q contient %q', quoi or 'texte', tostring(texte), morceau), 2)
    end
end

local Chemins = require 'Chemins'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Historique = require 'Historique'
local Json = require 'Json'
local Metriques = require 'Metriques'
local Notation = require 'Notation'
local Session = require 'Session'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = true

-- Le catalogue ------------------------------------------------------------------------------------

-- Les lectures une à une de la prise de vue (getFormattedMetadata hors d'une lecture groupée) :
-- comptées, pour dire quel chemin le résumé a pris.
local unesAUnes = 0
local dansLot = false
local PRISE = {}
for _, cle in ipairs(Historique.CLES_PRISE) do
    PRISE[cle] = true
end

-- Des photos par identifiant (getPhotoByLocalId) : leur prise de vue (`formatees`, textes de
-- Lightroom ; l'appareil par `appareil`), leur date (`prise`, en secondes comme le LrDate simulé),
-- leur note et leur drapeau (`note`, `pickStatus`), leur uuid, editCount, lastEditTime, leurs réglages
-- de développement, et leurs champs du module posés directement.
local photos = {}
local function photo(id, champs)
    local p = S.photo(id, string.format('DSCF%04d.RAF', id))
    p.editCount, p.lastEditTime, p.reglages, p.formatees = 0, 0, { Exposure2012 = 0, Shadows2012 = 0 }, {}
    p.uuid, p.note, p.pickStatus = 'uuid-' .. id, 0, 0
    local formatee, brut = p.getFormattedMetadata, p.getRawMetadata
    p.getFormattedMetadata = function(self, cle)
        if PRISE[cle] and not dansLot then
            unesAUnes = unesAUnes + 1
        end
        if self.formatees[cle] ~= nil then
            return self.formatees[cle]
        end
        return formatee(self, cle)
    end
    p.getRawMetadata = function(self, cle)
        if cle == 'editCount' then
            return self.editCount
        elseif cle == 'lastEditTime' then
            return self.lastEditTime
        elseif cle == 'uuid' then
            return self.uuid
        end
        return brut(self, cle)
    end
    p.getDevelopSettings = function(self)
        local t = {}
        for k, v in pairs(self.reglages) do
            t[k] = v
        end
        return t
    end
    for k, v in pairs(champs or {}) do
        p[k] = v
    end
    photos[id] = p
    return p
end
S.catalogue.getPhotoByLocalId = function(_, id) return photos[tonumber(id)] end

-- Les trois lectures groupées du catalogue (SDK 3.0), branchées ou non : sans elles, chaque photo
-- se lit une à une.
local function lecturesGroupees(oui)
    if not oui then
        S.catalogue.batchGetFormattedMetadata, S.catalogue.batchGetRawMetadata, S.catalogue.batchGetPropertyForPlugin = nil, nil, nil
        return
    end
    local function lot(lire)
        return function(_, liste, ...)
            local r = {}
            dansLot = true
            for _, p in ipairs(liste) do
                r[p] = lire(p, ...)
            end
            dansLot = false
            return r
        end
    end
    S.catalogue.batchGetFormattedMetadata = lot(function(p, cles)
        local t = {}
        for _, cle in ipairs(cles) do
            t[cle] = p:getFormattedMetadata(cle)
        end
        return t
    end)
    S.catalogue.batchGetRawMetadata = lot(function(p, cles)
        local t = {}
        for _, cle in ipairs(cles) do
            t[cle] = p:getRawMetadata(cle)
        end
        return t
    end)
    -- Une photo sans champ du module n'y est pas (supposé : le résultat de Lightroom n'est pas relevé).
    S.catalogue.batchGetPropertyForPlugin = lot(function(p, plugin, cles)
        assert(plugin == _PLUGIN, 'batchGetPropertyForPlugin : _PLUGIN attendu')
        if next(p.proprietes) == nil then
            return nil
        end
        local t = {}
        for _, cle in ipairs(cles) do
            t[cle] = p.proprietes[cle]
        end
        return t
    end)
end

-- Une date de prise de vue (heure locale), en secondes comme le LrDate simulé.
local function le(annee, mois, j, h, mn)
    return os.time({ year = annee, month = mois, day = j, hour = h or 12, min = mn or 0 })
end

-- Une entrée du journal de Claude (Ecriture.ajouterJournal), datée « AAAA-MM-JJ HH:MM ».
local function etape(date, nom, raison, id)
    return { date = date, etape = 'Claude · ' .. nom, etape_id = id or nom, type = 'retouche', raison = raison, changements = {} }
end

local function journal(p, entrees)
    p.proprietes.journalClaude = Json.encode(Json.tableau(entrees))
end

-- Retouchée par Claude (Photos.decrireTout) : son champ, et la mémoire à elle (proprietaireMemoire).
local function retoucheeParClaude(p)
    p.proprietes.retoucheeParClaude, p.proprietes.proprietaireMemoire = 'oui', p.uuid
end

-- L'état où Claude a laissé la photo (Ecriture.noterEtatFinal), puis une reprise à la main.
local function apresClaude(p, nom, reglages)
    p.proprietes.apresClaude = Json.encode({ etape = 'Claude · ' .. nom, editCount = p.editCount, lastEditTime = p.lastEditTime,
        reglages = reglages })
end

local function retoucherALaMain(p, cle, valeur)
    p.editCount, p.lastEditTime = p.editCount + 1, p.lastEditTime + 10
    p.reglages[cle] = valeur
end

-- La sélection de Lightroom : la photo active, puis les autres.
local function choisir(active, ...)
    S.photoActive = photos[active]
    local liste = { photos[active] }
    for _, id in ipairs({ ... }) do
        liste[#liste + 1] = photos[id]
    end
    S.selection = liste
end

-- Une fausse session de Claude Code : les messages reçus.
local recus = {}
Session.nouvelle = function(options)
    local s = {}
    for k, v in pairs(options) do
        s[k] = v
    end
    function s.envoyer(_, message)
        recus[#recus + 1] = { message = message, reprise = options.reprise, conversation = options.idConversation }
    end
    function s.lire() return {}, false end
    function s.arreter(this) this.arrete = true end
    function s.interrompre() end
    return s
end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'

-- Les lectures du résumé, comptées (Fenetre les appelle par la table du module).
local lectures = { photo = 0, groupe = 0 }
local lirePhoto, lireGroupe = Historique.lireResumePhoto, Historique.lireResumeGroupe
Historique.lireResumePhoto = function(...)
    lectures.photo = lectures.photo + 1
    return lirePhoto(...)
end
Historique.lireResumeGroupe = function(...)
    lectures.groupe = lectures.groupe + 1
    return lireGroupe(...)
end

-- Le moteur au départ d'un essai : `conversations` gardées (sur le disque aussi, seules), la
-- courante.
local function depart(conversations, courante)
    Fichiers.supprimer(Chemins.conversations())
    Moteur.charge = true
    Moteur.travaille, Moteur.finTravail, Moteur.enCours, Moteur.session = false, 0, nil, nil
    Moteur.conversations = conversations or {}
    for _, c in ipairs(Moteur.conversations) do
        Stockage.enregistrer(c)
    end
    Moteur.courante = courante or Conversation.nouvelle()
    Fenetre.cleVue, Fenetre.cleVueLe = nil, nil
    lectures.photo, lectures.groupe = 0, 0
end

local function ouvrir(fn)
    local vu = false
    S.pendantFenetre = function(args)
        vu = true
        fn(Fenetre.p, args.contents)
    end
    local ok, erreur = pcall(Fenetre.afficher)
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    assert(ok, erreur)
    vrai(vu, 'fenêtre ouverte')
end

-- La photo choisie relue (Fenetre.majPhoto), puis ce que la boucle de la fenêtre fait : le résumé
-- suivi (Fenetre.suivreResume), le fil rafraîchi.
local function voir()
    Fenetre.majPhoto()
    Fenetre.suivreResume()
    if Fenetre.aRafraichir then
        Fenetre.aRafraichir = false
        Fenetre.rafraichir()
    end
end

-- La demande envoyée (Fenetre.envoyer, dans une tâche), puis la fin du tour de Claude.
local function demander(texte)
    local taches = #S.taches
    Fenetre.envoyer(texte)
    vrai(#S.taches > taches, 'la demande part dans une tâche')
    S.taches[#S.taches]()
    vrai(Moteur.travaille, 'Claude travaille')
    local c = Moteur.enCours
    Moteur.traiter(c, { genre = 'fin', reussie = true, interrompue = false, session = 'session-' .. c.id })
    vrai(not Moteur.travaille, 'tour fini')
    return recus[#recus].message
end

-- Vrai pour l'en-tête du résumé (« Résumé de la photo : … », « Résumé de la sélection : … »).
local function enTeteDuResume(l)
    return l.texte ~= nil and (l.texte:find(Historique.TITRE_RESUME .. ' : ', 1, true) ~= nil
        or l.texte:find(Historique.TITRE_RESUME_GROUPE .. ' : ', 1, true) ~= nil)
end

-- Les lignes du résumé dans le fil montré (Fenetre.lignes) : son en-tête, puis ses puces, jusqu'à
-- la ligne vide ou la ligne d'un élément qui le suit ; et le rang de son en-tête dans le fil.
local function lignesDuResume()
    local liste, debut = {}, nil
    for k, l in ipairs(Fenetre.lignes or {}) do
        if not debut and enTeteDuResume(l) then
            debut = k
        end
        if debut then
            if l.genre == 'vide' or l.element ~= nil then
                break
            end
            liste[#liste + 1] = l
        end
    end
    return liste, debut
end

-- Combien de résumés le fil montré porte (un au plus).
local function nombreDeResumes()
    local n = 0
    for _, l in ipairs(Fenetre.lignes or {}) do
        if enTeteDuResume(l) then
            n = n + 1
        end
    end
    return n
end

-- Le rang dans le fil montré de la première et de la dernière ligne du premier élément de `c` de ce
-- genre (et de cette sorte, pour un élément de la fenêtre) ; nil sans lui ou sans ligne.
local function rangs(c, genre, sorte)
    local indice
    for i, e in ipairs(c.elements) do
        if e.genre == genre and (sorte == nil or e.sorte == sorte) then
            indice = i
            break
        end
    end
    local premier, dernier
    for k, l in ipairs(Fenetre.lignes or {}) do
        if indice and l.element == indice then
            premier, dernier = premier or k, k
        end
    end
    return premier, dernier
end

-- Le rang dans le fil montré de la ligne de ce texte (la première) ; nil sans elle.
local function rangDuTexte(texte)
    for k, l in ipairs(Fenetre.lignes or {}) do
        if l.texte == texte then
            return k
        end
    end
    return nil
end

-- Les textes de la grille du fil (p.t1 à p.tN).
local function grille(p)
    local t = {}
    for i = 1, Fenetre.T.lignes do
        t[i] = p['t' .. i]
    end
    return table.concat(t, '\n')
end

-- Une conversation gardée de la photo `id` : son historique en tête (Moteur.preparerPhoto : s'il y
-- en a un, et `avecHistorique`), puis `n` échanges (« Demande k », « Réponse k. ») ; ce qu'elle a vu
-- de la photo (son état d'à présent).
local function gardee(id, n, avecHistorique)
    local c = Conversation.nouvelle()
    if avecHistorique then
        Moteur.preparerPhoto(c, id)
    end
    c.photo = id
    for k = 1, n do
        Conversation.ajouterDemande(c, 'Demande ' .. k)
        c.elements[#c.elements + 1] = { id = 'claude-' .. id .. '-' .. k, genre = 'claude', texte = 'Réponse ' .. k .. '.', date = os.time(),
            images = {}, changements = {} }
    end
    c.titre, c.titreAuto, c.modifiee = 'Photo ' .. id, true, os.time()
    local etat = Historique.lire(id)
    c.vu = etat and Historique.vu(etat) or nil
    return c
end

local function texteDu(liste)
    local t = {}
    for _, l in ipairs(liste) do
        t[#t + 1] = l.texte
    end
    return table.concat(t, '\n')
end

-- La photo 301 : un X-H2S, deux étapes de Claude, puis une reprise à la main.
local function photo301()
    local p = photo(301, { appareil = 'X-H2S', prise = le(2026, 10, 25, 14, 30), note = 3, pickStatus = 1 })
    p.formatees = { lens = 'XF16-80mmF4 R OIS WR', focalLength = '35 mm', aperture = 'f/5,6', shutterSpeed = '1/250 s',
        isoSpeedRating = 'ISO 400' }
    journal(p, { etape('2026-10-24 10:02', 'passe 1 : lumière', 'Sous-exposée.'), etape('2026-10-24 10:05', 'passe 2 : finitions', 'Peau rouge.') })
    p.editCount, p.lastEditTime, p.reglages.Exposure2012 = 3, 100, 0.45
    apresClaude(p, 'passe 2 : finitions', { Exposure2012 = 0.45, Shadows2012 = 0 })
    retoucherALaMain(p, 'Exposure2012', 0.6)
    retoucheeParClaude(p)
    return p
end

-- Textes (purs) -----------------------------------------------------------------------------------

essai("Textes d'une photo : la prise de vue (textes de Lightroom, puis la date), la note et le drapeau, l'état, les reprises et les réglages", function()
    local etat = { nom = 'DSCF0301.RAF', journal = { { date = '2026-10-24 10:02', etape = 'Claude · passe 1 : lumière' },
        { date = '2026-10-24 10:05', etape = 'Claude · passe 2 : finitions' } }, editCount = 3,
        reprises = { etape = 'Claude · passe 2 : finitions', changements = { { cle = 'Exposure2012', claude = '0,45', maintenant = '0,6' } } },
        reglages = { 'Exposition +0,6' } }
    local d = { id = 301, nom = 'DSCF0301.RAF', appareil = 'X-H2S', objectif = 'XF16-80mmF4 R OIS WR', focale = '35 mm', ouverture = 'f/5,6',
        vitesse = '1/250 s', iso = 'ISO 400', prise = '2026-10-25 14:30', note = 3, drapeau = 'retenue', etat = etat }
    egal("Résumé de la photo : DSCF0301.RAF\n"
        .. "•  Prise de vue : X-H2S · XF16-80mmF4 R OIS WR · 35 mm · f/5,6 · 1/250 s · ISO 400 · 25 oct. 2026, 14 h 30\n"
        .. "•  Note et drapeau : 3 ★ · retenue\n"
        .. "•  État : 2 étapes de Claude, la dernière le 24 oct. 2026, 10 h 05 (« passe 2 : finitions »), puis des reprises à la main\n"
        .. "•  Repris à la main depuis « passe 2 : finitions » : Exposition 0,45 → 0,6\n"
        .. "•  Réglages hors des valeurs par défaut : Exposition +0,6", Historique.resumePhoto(d))
    -- Rien de lu de la prise de vue ; ni étape de Claude ni retouche ; à la main seulement.
    local vide = Historique.resumePhoto({ id = 302, note = 0, drapeau = 'aucun', etat = { nom = '', journal = {}, editCount = 0 } })
    egal("Résumé de la photo : photo 302\n•  Prise de vue : rien de lu\n•  Note et drapeau : pas encore notée · sans drapeau\n"
        .. "•  État : sans étape de Claude ni retouche", vide)
    contient(Historique.resumePhoto({ nom = 'X', etat = { journal = {}, editCount = 2 } }), "État : retouchée à la main, sans étape de Claude")
    -- La note et le drapeau.
    egal("pas encore notée · sans drapeau", Historique.texteNote(0, 'aucun'))
    egal("5 ★ · sans drapeau", Historique.texteNote(5, 'aucun'))
    egal("pas encore notée · rejetée", Historique.texteNote(0, 'rejetee'))
    egal("2 ★ · retenue", Historique.texteNote(2, 'retenue'))
    egal("pas encore notée · sans drapeau", Historique.texteNote(nil, nil))
end)

essai("Textes d'un groupe : le nombre, les dates (de … à …, un seul jour, inconnues), les appareils (les plus fréquents, « … », inconnus) et les comptes", function()
    local g = { m = 12, lues = 12, debut = '3 oct. 2026', fin = '25 oct. 2026', sansDate = 0,
        appareils = { { nom = 'X-H2S', n = 10 }, { nom = 'X-T20', n = 2 } }, sansAppareil = 0, retouchees = 3, notees = 5, rejetees = 1 }
    egal("Résumé de la sélection : 12 photos\n•  Prises du 3 oct. 2026 au 25 oct. 2026\n•  Appareils : X-H2S (10), X-T20 (2)\n"
        .. "•  Retouchées par Claude : 3 · notées : 5 · rejetées : 1", Historique.resumeGroupe(g))
    -- Un seul jour, un seul appareil, des photos sans date.
    local un = { m = 3, lues = 3, debut = '25 oct. 2026', fin = '25 oct. 2026', sansDate = 1, appareils = { { nom = 'X-H2S', n = 3 } },
        sansAppareil = 0, retouchees = 0, notees = 0, rejetees = 0 }
    egal("Résumé de la sélection : 3 photos\n•  Prises le 25 oct. 2026 (1 sans date)\n•  Appareil : X-H2S\n"
        .. "•  Retouchées par Claude : 0 · notées : 0 · rejetées : 0", Historique.resumeGroupe(un))
    -- Aucune date, aucun appareil connu.
    local rien = { m = 2, lues = 2, sansDate = 2, appareils = {}, sansAppareil = 2, retouchees = 0, notees = 0, rejetees = 0 }
    egal("Résumé de la sélection : 2 photos\n•  Dates de prise de vue inconnues\n•  Appareil : inconnu (2)\n"
        .. "•  Retouchées par Claude : 0 · notées : 0 · rejetées : 0", Historique.resumeGroupe(rien))
    -- Plus de quatre appareils : les quatre premiers, puis « … » ; des inconnus à la fin.
    local beaucoup = { m = 9, lues = 9, debut = '1 oct. 2026', fin = '2 oct. 2026', sansDate = 0, sansAppareil = 1,
        appareils = { { nom = 'A', n = 3 }, { nom = 'B', n = 2 }, { nom = 'C', n = 1 }, { nom = 'D', n = 1 }, { nom = 'E', n = 1 } },
        retouchees = 0, notees = 0, rejetees = 0 }
    contient(Historique.resumeGroupe(beaucoup), "•  Appareils : A (3), B (2), C (1), D (1), …, inconnu (1)\n")
    -- Seules les premières lues (lectures groupées en échec) : l'en-tête le dit.
    local premieres = { m = 600, lues = 500, sansDate = 500, appareils = {}, sansAppareil = 0, retouchees = 0, notees = 0, rejetees = 0 }
    egal("Résumé de la sélection : 600 photos (les 500 premières lues)", Texte.lignes(Historique.resumeGroupe(premieres))[1])
end)

essai("Caractères : tout ce que le résumé écrit lui-même est mesuré (Metriques), dans la police des notes du fil", function()
    local d = { id = 1, nom = 'A', appareil = 'A', prise = '2026-10-25 14:30', note = 4, drapeau = 'rejetee',
        etat = { journal = { { date = '2026-10-24 10:05', etape = 'Claude · a' } }, editCount = 1,
            reprises = { etape = 'Claude · a', changements = { { cle = 'Exposure2012', claude = '1', maintenant = '2' } } }, reglages = { 'a' } } }
    local g = { m = 600, lues = 500, debut = '3 févr. 2026', fin = '25 août 2026', sansDate = 1, sansAppareil = 1,
        appareils = { { nom = 'A', n = 3 }, { nom = 'B', n = 2 }, { nom = 'C', n = 1 }, { nom = 'D', n = 1 }, { nom = 'E', n = 1 } },
        retouchees = 1, notees = 1, rejetees = 1 }
    local textes = Historique.resumePhoto(d) .. Historique.resumeGroupe(g) .. Historique.resumeGroupe({ m = 2, lues = 2, appareils = {} })
        .. Historique.resumePhoto({ etat = { journal = {}, editCount = 0 } }) .. Historique.resumePhoto({ etat = { journal = {}, editCount = 1 } })
        .. Historique.texteNote(0, 'retenue') .. Historique.texteNote(3, 'aucun')
    local police = Metriques[Fil.polices.note].chasse
    for car in Texte.caracteres(textes) do
        vrai(car == '\n' or police[car], 'caractère non mesuré : ' .. car)
    end
end)

-- Lectures ----------------------------------------------------------------------------------------

essai("Lecture d'une photo : par les lectures groupées du catalogue ; sa prise de vue, sa date à l'heure locale, sa note, son drapeau, son état et ses réglages même après des étapes de Claude", function()
    photo301()
    lecturesGroupees(true)
    unesAUnes = 0
    local d = lirePhoto(301)
    vrai(d, 'lue')
    egal(0, unesAUnes, 'aucune lecture une à une de la prise de vue')
    egal('X-H2S', d.appareil)
    egal('XF16-80mmF4 R OIS WR', d.objectif)
    egal('35 mm', d.focale)
    egal('f/5,6', d.ouverture)
    egal('1/250 s', d.vitesse)
    egal('ISO 400', d.iso)
    egal('2026-10-25 14:30', d.prise, "à l'heure locale")
    egal(3, d.note)
    egal('retenue', d.drapeau)
    egal(true, d.retouchee)
    egal('DSCF0301.RAF', d.nom)
    egal(2, #d.etat.journal)
    vrai(d.etat.reprises, 'les reprises à la main')
    egal('Exposition +0,6', d.etat.reglages and d.etat.reglages[1], 'ses réglages, malgré ses étapes de Claude')
    -- Une photo qui n'est plus au catalogue : rien.
    egal(nil, lirePhoto(999))
    lecturesGroupees(false)
end)

essai("Lecture d'une photo sans les lectures groupées : une à une, les mêmes valeurs", function()
    photo301()
    lecturesGroupees(false)
    unesAUnes = 0
    local d = lirePhoto(301)
    vrai(unesAUnes > 0, 'lue une à une')
    egal('X-H2S', d.appareil)
    egal('ISO 400', d.iso)
    egal('2026-10-25 14:30', d.prise)
    egal(3, d.note)
    egal('retenue', d.drapeau)
    egal(true, d.retouchee)
end)

essai("Lecture d'un groupe : groupée ; les dates de la plus ancienne à la plus récente, les appareils par fréquence, retouchées (mémoire à elles seulement), notées, rejetées", function()
    photo301()
    photo(302, { appareil = 'X-T20', prise = le(2026, 10, 3), note = 0, pickStatus = -1 })
    photo(303, { appareil = 'X-H2S', prise = le(2026, 10, 12), note = 2 })
    -- Une copie qui a reçu la mémoire de son original (proprietaireMemoire d'un autre) : pas retouchée.
    local p304 = photo(304, { prise = nil, note = 0 })
    p304.proprietes.retoucheeParClaude, p304.proprietes.proprietaireMemoire = 'oui', 'uuid-301'
    choisir(302, 301, 303, 304)
    lecturesGroupees(true)
    unesAUnes = 0
    local g = lireGroupe()
    egal(0, unesAUnes, 'aucune lecture une à une')
    egal(4, g.m)
    egal(4, g.lues)
    egal('3 oct. 2026', g.debut)
    egal('25 oct. 2026', g.fin)
    egal(1, g.sansDate)
    egal('X-H2S:2 X-T20:1', g.appareils[1].nom .. ':' .. g.appareils[1].n .. ' ' .. g.appareils[2].nom .. ':' .. g.appareils[2].n)
    egal(1, g.sansAppareil)
    egal(1, g.retouchees, "la 301 seulement : la mémoire de la 304 est celle d'une autre photo")
    egal(2, g.notees)
    egal(1, g.rejetees)
    lecturesGroupees(false)
end)

essai("Lecture d'un grand groupe sans les lectures groupées : les MAX_GROUPE premières seulement, une à une, et l'en-tête le dit", function()
    for id = 401, 405 do
        photo(id, { appareil = 'X-H2S', prise = le(2026, 10, id - 400) })
    end
    choisir(401, 402, 403, 404, 405)
    lecturesGroupees(false)
    local max = Historique.MAX_GROUPE
    Historique.MAX_GROUPE = 3
    local ok, g = pcall(lireGroupe)
    Historique.MAX_GROUPE = max
    assert(ok, g)
    egal(5, g.m)
    egal(3, g.lues)
    egal('1 oct. 2026', g.debut)
    egal('3 oct. 2026', g.fin)
    egal("Résumé de la sélection : 5 photos (les 3 premières lues)", Texte.lignes(Historique.resumeGroupe(g))[1])
end)

-- Dans la fenêtre ---------------------------------------------------------------------------------

essai("Photo neuve, à l'ouverture : le résumé de la photo en haut du fil, sous son historique, en gris (l'icône sur l'en-tête, les puces en retrait), d'aucun élément ni tour ; un clic n'y fait rien", function()
    photo301()
    lecturesGroupees(true)
    depart({})
    choisir(301)
    ouvrir(function(p)
        local c = Moteur.courante
        egal(301, c.photo)
        egal(1, lectures.photo, "lu une fois à l'ouverture")
        local resume, debut = lignesDuResume()
        vrai(#resume >= 6, "l'en-tête et ses puces : " .. #resume)
        local _, finHistorique = rangs(c, 'historique', 'historique')
        egal(finHistorique + 2, debut, "sous l'historique, après une ligne vide")
        egal(Fenetre.lignes[#Fenetre.lignes], resume[#resume], 'rien encore sous lui (aucune demande)')
        egal(1, nombreDeResumes(), 'une seule fois')
        contient(resume[1].texte, 'Résumé de la photo : DSCF0301.RAF')
        egal('note', resume[1].icone, "l'icône sur l'en-tête")
        for k, l in ipairs(resume) do
            egal('note', l.genre, 'en gris')
            egal(nil, l.element, "d'aucun élément")
            egal(nil, l.auteur, "d'aucun tour")
            vrai(k == 1 or l.icone == nil, 'une seule icône')
            vrai(Fil.occupe(l) <= Fenetre.largeurTexte(), 'coupé à la largeur : ' .. l.texte)
        end
        contient(texteDu(resume), 'Note et drapeau : 3 ★ · retenue')
        contient(texteDu(resume), 'État : 2 étapes de Claude')
        -- L'historique de la conversation neuve reste en tête, le résumé après une ligne vide.
        contient(p.t1, 'Historique de la photo')
        local avant
        for k, l in ipairs(Fenetre.lignes) do
            if l == resume[1] then
                avant = Fenetre.lignes[k - 1]
            end
        end
        egal('vide', avant and avant.genre, 'une ligne vide avant le résumé')
        -- Montré dans la grille : la dernière ligne montrée est sa dernière puce.
        local derniere
        for i = 1, Fenetre.T.lignes do
            if p['t' .. i] ~= '' then
                derniere = i
            end
        end
        egal(resume[#resume].texte, p['t' .. derniere])
        -- Un clic sur une de ses lignes : rien (ni détail, ni étape, ni image).
        local taches = #S.taches
        Fenetre.cliquerLigne(derniere)
        egal(taches, #S.taches, 'aucune tâche')
        -- La première demande de Dany (« Vous ») vient sous lui, pas au-dessus (capture de Dany du
        -- 25 octobre 2026 : le résumé restait en bas, sous « Vous : ajuste la balance des blanc »).
        demander('ajuste la balance des blanc')
        voir()
        Fenetre.rafraichir()
        resume, debut = lignesDuResume()
        egal(finHistorique + 2, debut, "toujours sous l'historique")
        egal(debut + #resume + 1, rangs(c, 'dany'), 'au-dessus de « Vous »')
        egal('dany', Fenetre.lignes[debut + #resume + 1].auteur, "« Vous » sur la ligne de la demande")
        egal(1, nombreDeResumes())
    end)
    lecturesGroupees(false)
end)

essai("Jamais gardé ni envoyé : ni dans les éléments de la conversation, ni sur le disque, ni dans le message à Claude ; toujours entre l'historique et la première demande", function()
    photo301()
    depart({})
    choisir(301)
    ouvrir(function()
        local c = Moteur.courante
        for _, e in ipairs(c.elements) do
            absent(e.texte, Historique.TITRE_RESUME, 'un élément de la conversation')
        end
        local message = demander('Retouche-la')
        absent(message, Historique.TITRE_RESUME, 'le message à Claude')
        absent(message, 'Note et drapeau', 'le message à Claude')
        vrai(Fichiers.existe(Stockage.fichier(c.id)), 'gardée à sa première demande')
        absent(Fichiers.lire(Stockage.fichier(c.id)), Historique.TITRE_RESUME, 'le fichier de la conversation')
        -- La réponse de Claude arrive : le résumé reste en haut, entre l'historique et la demande ;
        -- la réponse est en bas du fil.
        c.elements[#c.elements + 1] = { id = 'claude-1', genre = 'claude', texte = 'Voilà qui est fait.', date = os.time(), images = {}, changements = {} }
        voir()
        Fenetre.rafraichir()
        local resume, debut = lignesDuResume()
        vrai(#resume > 0, 'le résumé')
        local _, finHistorique = rangs(c, 'historique', 'historique')
        local demande = rangs(c, 'dany')
        local reponse = rangDuTexte('Voilà qui est fait.')
        vrai(finHistorique and demande and reponse, "l'historique, la demande et la réponse dans le fil")
        egal(finHistorique + 2, debut, "sous l'historique")
        egal('vide', Fenetre.lignes[debut + #resume].genre, 'une ligne vide sous le résumé')
        egal(debut + #resume + 1, demande, 'au-dessus de la demande de Dany')
        vrai(demande < reponse, 'la réponse sous la demande')
        for k = reponse + 1, #Fenetre.lignes do
            egal('', Fenetre.lignes[k].texte, 'la réponse en bas du fil (puis la ligne de son heure)')
        end
        egal(1, nombreDeResumes(), 'une seule fois')
    end)
end)

essai("Une autre photo, puis un groupe : le résumé de la conversation montrée ; la photo active changée dans le même groupe ne le refait pas", function()
    photo301()
    photo(302, { appareil = 'X-T20', prise = le(2026, 10, 3), pickStatus = -1 })
    photo(303, { appareil = 'X-H2S', prise = le(2026, 10, 12), note = 2 })
    lecturesGroupees(true)
    depart({})
    choisir(301)
    ouvrir(function()
        contient(texteDu(lignesDuResume()), 'DSCF0301.RAF')
        -- Une autre photo : sa conversation, son résumé, aussitôt (Fenetre.majPhoto, sans attendre le
        -- tour suivant de la boucle).
        choisir(302)
        Fenetre.majPhoto()
        egal(302, Moteur.courante.photo)
        egal(Moteur.courante, Fenetre.resume and Fenetre.resume.conversation, 'le résumé de la conversation montrée, aussitôt')
        voir()
        egal(2, lectures.photo)
        local r302 = texteDu(lignesDuResume())
        contient(r302, 'Résumé de la photo : DSCF0302.RAF')
        contient(r302, 'Note et drapeau : pas encore notée · rejetée')
        absent(r302, 'DSCF0301')
        -- La même photo relue : rien de refait.
        voir()
        egal(2, lectures.photo, 'la même conversation : rien de relu')
        -- Trois photos : la conversation du groupe et son résumé.
        choisir(301, 302, 303)
        voir()
        vrai(Moteur.courante.groupe ~= nil, 'la conversation du groupe')
        egal(1, lectures.groupe)
        local rg = texteDu(lignesDuResume())
        egal("Résumé de la sélection : 3 photos\n•  Prises du 3 oct. 2026 au 25 oct. 2026\n•  Appareils : X-H2S (2), X-T20 (1)\n"
            .. "•  Retouchées par Claude : 1 · notées : 2 · rejetées : 1", rg)
        -- Une autre photo active dans le même groupe : la même conversation, le même résumé.
        local c = Moteur.courante
        choisir(303, 301, 302)
        voir()
        egal(c, Moteur.courante, 'le même groupe')
        egal(1, lectures.groupe, 'rien de relu')
        egal(rg, texteDu(lignesDuResume()))
    end)
    lecturesGroupees(false)
end)

essai("Fin d'un tour de Claude : le résumé se refait (la photo a changé) ; pendant son travail, rien ; le registre des notes changé, de même", function()
    local p = photo301()
    depart({})
    choisir(301)
    ouvrir(function()
        demander('Retouche-la')
        -- Claude a écrit une troisième étape pendant le tour : à la fin, le résumé la dit.
        journal(p, { etape('2026-10-24 10:02', 'passe 1 : lumière', 'a'), etape('2026-10-24 10:05', 'passe 2 : finitions', 'b'),
            etape('2026-10-25 15:00', 'passe 3 : ciel', 'c') })
        local avant = lectures.photo
        voir()
        egal(avant + 1, lectures.photo, 'relu après le tour')
        contient(texteDu(lignesDuResume()), "État : 3 étapes de Claude, la dernière le 25 oct. 2026, 15 h 00 (« passe 3 : ciel »)")
        voir()
        egal(avant + 1, lectures.photo, 'une seule fois')
        -- Pendant le travail de Claude : rien ne se refait, ni pour une fin d'un autre tour, ni pour
        -- le registre des notes ; après, si.
        Moteur.travaille = true
        Moteur.finTravail = Moteur.finTravail + 5
        Notation.version = Notation.version + 1
        egal(false, Fenetre.suivreResume(), 'Claude travaille')
        vrai(#lignesDuResume() > 0, 'le résumé reste montré')
        Moteur.travaille = false
        egal(true, Fenetre.suivreResume(), 'Claude libre')
        egal(false, Fenetre.suivreResume())
        Notation.version = Notation.version + 1
        egal(true, Fenetre.suivreResume(), 'le registre des notes a changé')
    end)
end)

essai("La note et le drapeau posés sur la photo active : le résumé les suit (Fenetre.majPhoto), sans relire le catalogue", function()
    local p = photo301()
    depart({})
    choisir(301)
    ouvrir(function()
        local avant = lectures.photo
        p.note, p.pickStatus = 5, 0
        voir()
        egal(avant, lectures.photo, 'rien de relu')
        contient(texteDu(lignesDuResume()), 'Note et drapeau : 5 ★ · sans drapeau')
        p.pickStatus = -1
        voir()
        contient(texteDu(lignesDuResume()), 'Note et drapeau : 5 ★ · rejetée')
    end)
end)

essai("Une photo sans historique (conversation vide) : le résumé en tête du fil, puis l'aide ; une conversation sans photo (case Autre photo décochée) : l'aide seule", function()
    photo(310, { appareil = 'X-T20', prise = le(2026, 9, 1) })
    depart({})
    choisir(310)
    ouvrir(function(p)
        egal(0, #Moteur.courante.elements, 'sans étape de Claude ni retouche : pas d\'historique')
        local resume, debut = lignesDuResume()
        egal(1, debut, 'en tête du fil')
        contient(p.t1, 'Résumé de la photo : DSCF0310.RAF')
        contient(texteDu(resume), 'État : sans étape de Claude ni retouche')
        egal('vide', Fenetre.lignes[#resume + 1].genre, 'une ligne vide sous le résumé')
        egal(#resume + 2, rangDuTexte(Fenetre.FIL_VIDE_TITRE), "puis le titre de l'aide")
        egal(Fenetre.FIL_VIDE_TITRE, p['t' .. (#resume + 2)])
        egal(1, nombreDeResumes())
    end)
    -- La case décochée : la conversation montrée (vide, sans photo) reste ; aucun résumé.
    prefs.nouvelleParPhoto = false
    depart({})
    choisir(310)
    ouvrir(function(p)
        egal(nil, Moteur.courante.photo)
        egal(0, #lignesDuResume(), 'aucun résumé')
        egal(0, lectures.photo + lectures.groupe, 'rien de lu')
        egal(Fenetre.FIL_VIDE_TITRE, p.t2)
    end)
    prefs.nouvelleParPhoto = true
end)

essai("Le menu (ou ⌃⌥C) rappelle la fenêtre ouverte : le résumé se refait ; une nouvelle ouverture aussi", function()
    local p = photo301()
    depart({})
    choisir(301)
    ouvrir(function()
        egal(1, lectures.photo)
        -- Changé hors de la fenêtre (Claude Desktop, la main) : le menu la rappelle.
        p.formatees.lens = 'XF56mmF1.2 R'
        local taches = #S.taches
        Fenetre.afficher()
        vrai(Fenetre.resume.perime, 'périmé, mais gardé')
        vrai(#lignesDuResume() > 0, 'encore montré')
        vrai(#S.taches > taches, 'la photo relue dans une tâche')
        S.taches[#S.taches]()
        egal(2, lectures.photo, 'refait')
        Fenetre.rafraichir()
        contient(texteDu(lignesDuResume()), 'XF56mmF1.2 R')
    end)
    -- Une nouvelle ouverture : refait.
    ouvrir(function()
        egal(3, lectures.photo, "refait à l'ouverture")
    end)
end)

-- La place du résumé (demandé par Dany le 25 octobre 2026 : « en haut des réponses, entre
-- historique et vous », d'abord en bas du fil) ------------------------------------------------------

-- Les éléments de la fenêtre de `c`, de cette sorte ('historique', 'depuis', 'groupe').
local function sortes(c, sorte)
    local n = 0
    for _, e in ipairs(c.elements) do
        if e.genre == 'historique' and e.sorte == sorte then
            n = n + 1
        end
    end
    return n
end

essai("Place du résumé (pur) : sous les éléments de tête (historique de la photo, résumé court du groupe), jamais sous « Depuis la dernière fois » ; en tête sans eux ; une ligne vide de chaque côté ; les lignes du fil inchangées", function()
    local function element(genre, sorte)
        return { genre = genre, sorte = sorte }
    end
    egal(1, Fil.tete({ elements = { element('historique', 'historique'), element('dany'), element('claude') } }))
    egal(1, Fil.tete({ elements = { element('historique', 'groupe'), element('dany') } }))
    egal(1, Fil.tete({ elements = { element('historique', 'historique'), element('historique', 'depuis'), element('dany') } }),
        '« Depuis » ajouté plus tard : sous le résumé')
    egal(0, Fil.tete({ elements = { element('historique', 'depuis'), element('dany') } }))
    egal(0, Fil.tete({ elements = { element('dany'), element('claude'), element('historique', 'historique') } }),
        "l'historique rejoint après une session perdue (Moteur.envoyer) : à sa place, dans le fil")
    egal(0, Fil.tete({ elements = {} }))
    egal(0, Fil.tete(nil))
    -- Les lignes : l'historique (élément 1), une ligne vide, la demande (élément 2).
    local h1 = { genre = 'note', texte = 'Historique de la photo : …', element = 1, icone = 'note' }
    local h2 = { genre = 'note', texte = '•  une étape', element = 1 }
    local vide = { genre = 'vide', texte = '' }
    local dany = { genre = 'dany', texte = 'Retouche-la', element = 2, auteur = 'dany' }
    local heure = { genre = 'vide', texte = '', heure = '19 h 42' }
    local r1, r2 = { genre = 'note', texte = 'Résumé de la photo : A', icone = 'note' }, { genre = 'note', texte = '•  Note' }
    local c = { elements = { element('historique', 'historique'), element('dany') } }
    local lignes = { h1, h2, vide, dany, heure }
    local avec = Fil.avecResume(lignes, { r1, r2 }, c)
    egal(8, #avec)
    egal(h1, avec[1])
    egal(h2, avec[2])
    egal('vide', avec[3].genre)
    egal(r1, avec[4], 'sous l\'historique, après une ligne vide')
    egal(r2, avec[5])
    egal(vide, avec[6], 'la ligne vide qui suivait l\'historique')
    egal(dany, avec[7], 'au-dessus de la demande, ses lignes telles quelles')
    egal(heure, avec[8])
    egal(5, #lignes, 'les lignes du fil inchangées')
    -- Sans élément de tête : en tête, puis une ligne vide avant la demande.
    avec = Fil.avecResume({ dany, heure }, { r1, r2 }, { elements = { element('dany') } })
    egal(r1, avec[1])
    egal('vide', avec[3].genre)
    egal(dany, avec[4])
    egal(5, #avec)
    -- L'aide d'une conversation vide commence par une ligne vide : aucune autre.
    local aide = { vide, { genre = 'titre', texte = 'Demandez à Claude.' } }
    avec = Fil.avecResume(aide, { r1 }, { elements = {} })
    egal(3, #avec)
    egal(r1, avec[1])
    egal(vide, avec[2])
    egal('titre', avec[3].genre)
    -- Seul l'historique : le résumé sous lui, rien après.
    avec = Fil.avecResume({ h1, h2 }, { r1 }, { elements = { element('historique', 'historique') } })
    egal(4, #avec)
    egal(r1, avec[4])
    -- Sans résumé : les mêmes lignes.
    egal(lignes, Fil.avecResume(lignes, {}, c))
end)

essai("Photo reprise, avec ses échanges puis « Depuis la dernière fois » : le résumé entre l'historique et la première demande ; le complément à sa place, sous la dernière réponse ; une seule fois", function()
    local p = photo301()
    photo(302, { appareil = 'X-T20', prise = le(2026, 10, 3) })
    depart({})
    choisir(301)
    ouvrir(function(grilleFil)
        local c = Moteur.courante
        demander('Retouche-la')
        c.elements[#c.elements + 1] = { id = 'claude-r1', genre = 'claude', texte = 'Lumière remontée.', date = os.time(), images = {}, changements = {} }
        demander('Et le ciel ?')
        c.elements[#c.elements + 1] = { id = 'claude-r2', genre = 'claude', texte = 'Ciel assombri.', date = os.time(), images = {}, changements = {} }
        -- Plus tard : une autre photo ; la 301 reprise à la main ; puis de retour sur elle.
        Moteur.finTravail = os.time() - 60
        choisir(302)
        voir()
        egal(302, Moteur.courante.photo, 'une autre photo')
        retoucherALaMain(p, 'Shadows2012', 15)
        choisir(301)
        voir()
        egal(c, Moteur.courante, 'sa conversation reprise')
        egal(1, sortes(c, 'historique'))
        egal(1, sortes(c, 'depuis'), 'le complément, ajouté à la fin')
        local resume, debut = lignesDuResume()
        contient(resume[1] and resume[1].texte, 'Résumé de la photo : DSCF0301.RAF')
        contient(texteDu(resume), 'Ombres 0 → 15', 'refait pour la photo reprise')
        local _, finHistorique = rangs(c, 'historique', 'historique')
        local demande = rangs(c, 'dany')
        local reponse1, reponse2 = rangDuTexte('Lumière remontée.'), rangDuTexte('Ciel assombri.')
        local depuis = rangs(c, 'historique', 'depuis')
        vrai(finHistorique and demande and reponse1 and reponse2 and depuis, 'tout est dans le fil')
        egal(finHistorique + 2, debut, "sous l'historique")
        egal(debut + #resume + 1, demande, 'au-dessus de la première demande')
        vrai(demande < reponse1 and reponse1 < reponse2 and reponse2 < depuis, 'les échanges, puis le complément')
        egal(1, nombreDeResumes(), 'une seule fois')
        contient(grilleFil.t1, 'Historique de la photo', "l'historique en tête de la grille")
        -- Rafraîchi, puis de nouveau une autre photo et de retour : jamais en double, toujours à sa
        -- place ; rien de changé, aucun complément de plus.
        Fenetre.rafraichir()
        Fenetre.rafraichir()
        egal(1, nombreDeResumes())
        choisir(302)
        voir()
        choisir(301)
        voir()
        egal(c, Moteur.courante)
        egal(1, sortes(c, 'depuis'), 'rien de changé : rien ajouté')
        egal(1, nombreDeResumes(), 'au retour sur la photo, une seule fois')
        resume, debut = lignesDuResume()
        egal(finHistorique + 2, debut, 'à la même place')
        egal(debut + #resume + 1, rangs(c, 'dany'))
    end)
end)

essai("Groupe : le résumé de la sélection sous le résumé court du groupe, au-dessus de la première demande", function()
    photo301()
    photo(302, { appareil = 'X-T20', prise = le(2026, 10, 3), pickStatus = -1 })
    photo(303, { appareil = 'X-H2S', prise = le(2026, 10, 12), note = 2 })
    depart({})
    choisir(301, 302, 303)
    ouvrir(function(grilleFil)
        local c = Moteur.courante
        vrai(c.groupe ~= nil, 'la conversation du groupe')
        egal(1, sortes(c, 'groupe'))
        contient(grilleFil.t1, 'de ces 3 photos', 'le résumé court en tête')
        local resume, debut = lignesDuResume()
        contient(resume[1] and resume[1].texte, 'Résumé de la sélection : 3 photos')
        local _, finGroupe = rangs(c, 'historique', 'groupe')
        egal(finGroupe + 2, debut, 'sous le résumé court du groupe')
        demander('Harmonise-les')
        voir()
        Fenetre.rafraichir()
        egal(c, Moteur.courante, 'le même groupe')
        resume, debut = lignesDuResume()
        egal(finGroupe + 2, debut)
        egal(debut + #resume + 1, rangs(c, 'dany'), 'au-dessus de la demande')
        egal(1, nombreDeResumes())
    end)
end)

essai("Conversation sans historique (une photo sans étape ni retouche, une conversation d'avant le correctif) : le résumé en tête du fil, au-dessus de la première demande", function()
    -- Sans étape de Claude ni retouche : Moteur.preparerPhoto n'y met pas d'historique.
    photo(320, { appareil = 'X-T20', prise = le(2026, 9, 2) })
    local c320 = gardee(320, 2, true)
    egal(0, sortes(c320, 'historique'), "pas d'historique")
    depart({ c320 })
    choisir(320)
    ouvrir(function(grilleFil)
        egal(c320, Moteur.courante)
        egal('dany', c320.elements[1].genre, "aucun élément de la fenêtre en tête")
        local resume, debut = lignesDuResume()
        egal(1, debut, 'en tête du fil')
        contient(grilleFil.t1, 'Résumé de la photo : DSCF0320.RAF')
        egal('vide', Fenetre.lignes[#resume + 1].genre)
        egal(#resume + 2, rangs(c320, 'dany'), 'au-dessus de la première demande')
        egal(1, nombreDeResumes())
    end)
    -- Une conversation d'avant le correctif : sa photo a des étapes de Claude, mais elle n'a pas
    -- d'élément « Historique de la photo ».
    local p321 = photo(321, { appareil = 'X-H2S', prise = le(2026, 9, 3) })
    journal(p321, { etape('2026-10-20 09:00', 'passe 1 : lumière', 'Sombre.') })
    retoucheeParClaude(p321)
    local c321 = gardee(321, 1, false)
    depart({ c321 })
    choisir(321)
    ouvrir(function(grilleFil)
        egal(c321, Moteur.courante)
        egal(0, sortes(c321, 'historique'))
        local resume, debut = lignesDuResume()
        egal(1, debut, 'en tête du fil')
        contient(grilleFil.t1, 'Résumé de la photo : DSCF0321.RAF')
        contient(texteDu(resume), 'État : 1 étape de Claude')
        egal(#resume + 2, rangs(c321, 'dany'))
    end)
end)

essai("Retour sur la même photo (sa conversation neuve, pas encore gardée) : un seul historique, un seul résumé, à sa place ; rafraîchi, rappelé par le menu, rouvert : jamais en double", function()
    photo301()
    photo(302, { appareil = 'X-T20', prise = le(2026, 10, 3) })
    depart({})
    choisir(301)
    ouvrir(function()
        choisir(302)
        voir()
        choisir(301)
        voir()
        local c = Moteur.courante
        egal(301, c.photo)
        egal(1, sortes(c, 'historique'), 'un seul historique')
        egal(1, nombreDeResumes(), 'un seul résumé')
        local _, finHistorique = rangs(c, 'historique', 'historique')
        local _, debut = lignesDuResume()
        egal(finHistorique + 2, debut)
        Fenetre.rafraichir()
        Fenetre.rafraichir()
        egal(1, nombreDeResumes(), 'rafraîchi')
        -- Le menu (ou ⌃⌥C) rappelle la fenêtre : le résumé se refait, une seule fois.
        Fenetre.afficher()
        S.taches[#S.taches]()
        Fenetre.rafraichir()
        egal(1, nombreDeResumes(), 'rappelée par le menu')
        egal(1, sortes(c, 'historique'))
        -- Une demande la garde ; une autre photo, puis de retour : sa conversation, son historique et
        -- son résumé une seule fois chacun, le résumé entre eux et la demande.
        demander('Retouche-la')
        Moteur.finTravail = os.time() - 60
        choisir(302)
        voir()
        choisir(301)
        voir()
        egal(c, Moteur.courante, 'sa conversation gardée, reprise')
        egal(1, sortes(c, 'historique'))
        egal(1, nombreDeResumes(), 'au retour, une seule fois')
        local resume
        resume, debut = lignesDuResume()
        egal(finHistorique + 2, debut)
        egal(debut + #resume + 1, rangs(c, 'dany'), 'au-dessus de la demande')
    end)
    ouvrir(function()
        egal(301, Moteur.courante.photo)
        egal(1, sortes(Moteur.courante, 'historique'))
        egal(1, nombreDeResumes(), 'rouverte')
        local resume, debut = lignesDuResume()
        egal(debut + #resume + 1, rangs(Moteur.courante, 'dany'), 'rouverte : au-dessus de la demande')
    end)
end)

essai("Longue conversation : la page montrée à l'ouverture est le bas du fil (la dernière réponse), le résumé plus haut ; un lecteur remonté ne bouge pas quand le résumé se refait plus long en haut et qu'un « Depuis » arrive en bas", function()
    local p = photo(330, { appareil = 'X-H2S', prise = le(2026, 10, 20) })
    journal(p, { etape('2026-10-24 10:02', 'passe 1 : lumière', 'Sous-exposée.') })
    p.editCount, p.lastEditTime, p.reglages.Exposure2012 = 1, 50, 0.3
    apresClaude(p, 'passe 1 : lumière', { Exposure2012 = 0.3, Shadows2012 = 0 })
    retoucheeParClaude(p)
    local c = gardee(330, 30, true)
    egal(1, sortes(c, 'historique'), "l'historique en tête")
    depart({ c })
    choisir(330)
    ouvrir(function(grilleFil)
        egal(c, Moteur.courante)
        egal(0, Fenetre.defilement, 'depuis le bas')
        local _, debut = lignesDuResume()
        vrai(debut and debut < Fenetre.premiere, 'le résumé plus haut, hors de la page montrée')
        egal(#Fenetre.lignes, Fenetre.premiere + Fenetre.T.lignes - 1, 'la page du bas')
        vrai(rangDuTexte('Réponse 30.') >= Fenetre.premiere, 'la dernière réponse montrée')
        absent(grille(grilleFil), Historique.TITRE_RESUME, 'le résumé hors de la page')
        egal(false, grilleFil.peutDescendre)
        egal(true, grilleFil.peutMonter)
        -- Remonté de 5 lignes, Dany lit ; la photo reprise à la main, la fenêtre rappelée par le menu :
        -- le résumé se refait plus long (en haut), « Depuis la dernière fois » arrive (en bas).
        Fenetre.defiler(5)
        local lue = grille(grilleFil)
        local avant = #lignesDuResume()
        retoucherALaMain(p, 'Shadows2012', 15)
        Fenetre.afficher()
        S.taches[#S.taches]()
        Fenetre.rafraichir()
        vrai(#lignesDuResume() > avant, string.format('le résumé refait plus long : %d puis %d lignes', avant, #lignesDuResume()))
        egal(1, sortes(c, 'depuis'), 'le complément, en bas')
        egal(lue, grille(grilleFil), 'ce que le lecteur lit ne bouge pas')
        vrai(Fenetre.defilement > 5, 'les lignes arrivées en bas comptent, pas celles du résumé')
        -- En bas du fil : le complément.
        Fenetre.defiler('fin')
        contient(grille(grilleFil), 'Depuis la dernière fois : des reprises à la main.')
    end)
end)

essai("Longue conversation lue tout en haut : le fil y reste quand le résumé se refait plus long (l'historique toujours en première ligne), puis un pas vers le bas le fait quitter", function()
    local p = photo(331, { appareil = 'X-H2S', prise = le(2026, 10, 20) })
    journal(p, { etape('2026-10-24 10:02', 'passe 1 : lumière', 'Sous-exposée.') })
    p.editCount, p.lastEditTime, p.reglages.Exposure2012 = 1, 50, 0.3
    apresClaude(p, 'passe 1 : lumière', { Exposure2012 = 0.3, Shadows2012 = 0 })
    retoucheeParClaude(p)
    local c = gardee(331, 30, true)
    depart({ c })
    choisir(331)
    ouvrir(function(grilleFil)
        egal(c, Moteur.courante)
        vrai(#Fenetre.lignes > Fenetre.T.lignes, 'plus long que la page')
        -- Tout en haut : l'historique en première ligne, le résumé dans la page.
        Fenetre.defiler(1000)
        egal(1, Fenetre.premiere, 'tout en haut')
        local premiere = rangs(c, 'historique')
        egal(1, premiere, "l'historique en première ligne")
        local _, debut = lignesDuResume()
        vrai(debut and debut <= Fenetre.T.lignes, 'le résumé dans la page du haut')
        egal(false, grilleFil.peutMonter)
        -- Ce que la page montre au-dessus du résumé, son en-tête compris : l'historique de la photo.
        local function hautDeLaPage()
            local t = {}
            for i = 1, debut do
                t[i] = grilleFil['t' .. i]
            end
            return table.concat(t, '\n')
        end
        local lue = hautDeLaPage()
        local avant = #lignesDuResume()
        -- La photo reprise à la main, la fenêtre rappelée par le menu : le résumé se refait plus long
        -- (en haut), « Depuis la dernière fois » arrive (en bas) ; le lecteur reste en haut.
        retoucherALaMain(p, 'Shadows2012', 15)
        Fenetre.afficher()
        S.taches[#S.taches]()
        Fenetre.rafraichir()
        vrai(#lignesDuResume() > avant, string.format('le résumé refait plus long : %d puis %d lignes', avant, #lignesDuResume()))
        egal(1, sortes(c, 'depuis'), 'le complément, en bas')
        egal(1, Fenetre.premiere, 'toujours tout en haut')
        egal(1, (rangs(c, 'historique')), "l'historique toujours en première ligne")
        egal(false, grilleFil.peutMonter)
        egal(debut, select(2, lignesDuResume()), 'le résumé à la même place')
        egal(lue, hautDeLaPage(), "l'historique et l'en-tête du résumé ne bougent pas")
        contient(grille(grilleFil), Historique.TITRE_RESUME .. ' : ', 'le résumé refait, dans la page du haut')
        -- Un pas vers le bas (▼) quitte le haut : le fil descend de ce pas, il n'y est pas ramené.
        Fenetre.defiler(-5)
        egal(6, Fenetre.premiere, 'cinq lignes plus bas')
        egal(true, grilleFil.peutMonter)
        Fenetre.rafraichir()
        egal(6, Fenetre.premiere, 'pas ramené en haut au rafraîchissement suivant')
    end)
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if echecs > 0 then
    os.exit(1)
end
