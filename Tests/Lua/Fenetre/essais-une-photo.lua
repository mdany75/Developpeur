-- essais-une-photo.lua : « une photo, une conversation » dans la fenêtre Claude (correctif 1.3.6,
-- décidé avec Dany le 25 octobre 2026), hors de Lightroom (LuaJIT, Lightroom simulé par
-- Simulation.lua) : la conversation d'une photo reprise, une photo neuve qui commence par son
-- historique sans rien garder avant la première demande, le complément « Depuis la dernière fois »
-- (une étape de Claude faite ailleurs, une reprise à la main), l'historique et le complément joints
-- une seule fois à la demande suivante, la conversation d'un groupe jamais gardée et sa clé sans
-- l'ordre, rien qui change pendant que Claude travaille, « Repartir à neuf », les conversations
-- d'avant le correctif (adaptés des essais de la nouvelle conversation par photo
-- d'essais-dispositions.lua), « Obtenir » de l'onglet Proposition, qui remplace la proposition
-- préparée à l'ouverture (décision de Dany du 25 octobre 2026), le Gestionnaire et les consignes.
-- Le catalogue est complété ici, sans toucher Simulation.lua : des photos par identifiant, avec leur
-- journal de Claude, editCount, lastEditTime et leurs réglages. Claude Code est remplacé par une
-- fausse session qui garde les messages reçus : ni Claude, ni quota.
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
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Historique = require 'Historique'
local Json = require 'Json'
local Lightroom = require 'Lightroom'
local Metriques = require 'Metriques'
local Session = require 'Session'
local Stockage = require 'Stockage'
local Texte = require 'Texte'

local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = true

-- Le catalogue : des photos par identifiant (getPhotoByLocalId), avec editCount, lastEditTime et
-- leurs réglages de développement (getDevelopSettings), et leurs champs du module posés directement.
local photos = {}
local function photo(id, champs)
    local p = S.photo(id, string.format('DSCF%04d.RAF', id))
    p.editCount, p.lastEditTime, p.reglages = 0, 0, { Exposure2012 = 0, Shadows2012 = 0 }
    local brut = p.getRawMetadata
    p.getRawMetadata = function(self, cle)
        if cle == 'editCount' then
            return self.editCount
        elseif cle == 'lastEditTime' then
            return self.lastEditTime
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

-- Une entrée du journal de Claude (Ecriture.ajouterJournal), datée « AAAA-MM-JJ HH:MM ».
local function etape(date, nom, raison, id)
    return { date = date, etape = 'Claude · ' .. nom, etape_id = id or nom, type = 'retouche', raison = raison,
        changements = {} }
end

local function journal(p, entrees)
    p.proprietes.journalClaude = Json.encode(Json.tableau(entrees))
end

-- L'état où Claude a laissé la photo (Ecriture.noterEtatFinal), puis une reprise à la main : editCount
-- et lastEditTime changent, un réglage aussi.
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

-- Une fausse session de Claude Code : les messages reçus, et la session reprise (`reprise`).
-- `echecEnvoi` : l'erreur de Session:lancer (Claude Code ou le connecteur introuvables), levée à
-- l'envoi.
local recus = {}
local echecEnvoi = nil
Session.nouvelle = function(options)
    local s = {}
    for k, v in pairs(options) do
        s[k] = v
    end
    function s.envoyer(_, message)
        if echecEnvoi then
            error(echecEnvoi, 0)
        end
        recus[#recus + 1] = { message = message, reprise = options.reprise, conversation = options.idConversation }
    end
    function s.lire() return {}, false end
    function s.arreter(this) this.arrete = true end
    function s.interrompre() end
    return s
end

local Fenetre = require 'Fenetre'
local Moteur = require 'Moteur'

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
end

-- Une conversation gardée pour une photo : une demande et la réponse de Claude ; ce qu'elle a vu de
-- la photo (son état d'à présent).
local function gardee(id, titre, modifiee)
    local c = Conversation.nouvelle(modifiee)
    c.photo = id
    Conversation.ajouterDemande(c, 'Retouche-la', modifiee)
    c.elements[#c.elements + 1] = { id = 'claude-' .. id, genre = 'claude', texte = 'Fait.', date = modifiee or os.time(), images = {}, changements = {} }
    c.titre, c.titreAuto = titre or ('Photo ' .. id), true
    c.modifiee = modifiee or os.time()
    local etat = Historique.lire(id)
    c.vu = etat and Historique.vu(etat) or nil
    return c
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

-- Les éléments de la fenêtre d'une conversation (genre 'historique'), de cette sorte.
local function historiques(c, sorte)
    local liste = {}
    for _, e in ipairs(c.elements) do
        if e.genre == 'historique' and (sorte == nil or e.sorte == sorte) then
            liste[#liste + 1] = e
        end
    end
    return liste
end

local function dossiersGardes()
    return #Fichiers.entrees(Chemins.conversations())
end

-- La dernière demande envoyée (Fenetre.envoyer, dans une tâche), puis la fin du tour de Claude, une
-- minute avant la suite (une photo choisie juste après son travail resterait la sienne).
local function demander(texte)
    local taches = #S.taches
    Fenetre.envoyer(texte)
    vrai(#S.taches > taches, 'la demande part dans une tâche')
    S.taches[#S.taches]()
    vrai(Moteur.travaille, 'Claude travaille')
    local c = Moteur.enCours
    Moteur.traiter(c, { genre = 'fin', reussie = true, interrompue = false, session = 'session-' .. c.id })
    vrai(not Moteur.travaille, 'tour fini')
    Moteur.finTravail = os.time() - 60
    return recus[#recus].message
end

-- La photo choisie relue (Fenetre.majPhoto), puis ce que la boucle de la fenêtre rafraîchit.
local function voir()
    Fenetre.majPhoto()
    if Fenetre.aRafraichir then
        Fenetre.aRafraichir = false
        Fenetre.rafraichir()
    end
end

local AUJOURDHUI = os.date('%Y-%m-%d')

-- Photo seule ---------------------------------------------------------------------------------

essai("Photo seule : sa conversation revient ; sinon une neuve (son nom en titre), gardée seulement à la première demande", function()
    photo(101)
    photo(102)
    photo(103, { editCount = 5 })
    journal(photos[101], { etape('2026-10-24 10:02', 'passe 1 : lumière', 'Ciel brûlé.') })
    local c101 = gardee(101, 'Lac au matin')
    depart({ c101 })
    egal(1, dossiersGardes(), 'une conversation sur le disque')
    choisir(102)
    ouvrir(function(p)
        local c = Moteur.courante
        egal(102, c.photo, "la photo active montre sa conversation à l'ouverture")
        for _, x in ipairs(Moteur.conversations) do
            vrai(x ~= c, 'neuve : pas dans la liste')
        end
        vrai(not Moteur.conversationDe(102), 'pas encore gardée')
        egal(0, #c.elements, "sans étape de Claude ni retouche à la main : pas d'historique")
        egal('DSCF0102.RAF', p.titre, 'son titre provisoire : le nom de la photo')
        -- Une photo retouchée à la main seulement : « retouchée à la main ».
        choisir(103)
        voir()
        local c103 = Moteur.courante
        egal(103, c103.photo)
        egal(1, #historiques(c103, 'historique'))
        egal("Historique de la photo : retouchée à la main, sans étape de Claude.", historiques(c103)[1].texte)
        egal(false, Conversation.commencee(c103), "l'historique ne commence pas la conversation")
        -- La photo qui a sa conversation : elle revient, telle quelle (rien de changé : rien d'ajouté).
        choisir(101)
        voir()
        egal(c101, Moteur.courante, 'sa conversation revient')
        egal(0, #historiques(c101), 'rien de changé, rien ajouté')
        egal('Lac au matin', p.titre)
        -- Revenir à la 102 : une autre conversation neuve ; parcourir ne crée aucun fichier.
        choisir(102)
        voir()
        vrai(Moteur.courante ~= c and Moteur.courante.photo == 102, 'neuve de nouveau')
        egal(1, dossiersGardes(), 'parcourir les photos ne crée aucun fichier')
        -- La première demande la garde : elle devient la conversation de la photo.
        local message = demander('Retouche la 102')
        local c102 = Moteur.courante
        egal(c102, Moteur.conversationDe(102), 'gardée à sa première demande')
        vrai(Fichiers.existe(Stockage.fichier(c102.id)), 'écrite sur le disque')
        egal(102, Stockage.lire(c102.id).photo, 'avec sa photo')
        egal('DSCF0102.RAF', c102.titre, "le titre reste le nom de la photo jusqu'à celui de Claude")
        contient(message, Consignes.rappelTitre, 'Claude donne son titre')
        egal('session-' .. c102.id, c102.sessionID)
        -- Une autre photo, puis la 102 : sans rien demander entre-temps, le même Claude Code ; après
        -- une demande dans la conversation de la 101, il reprend la session de la 102 (--resume).
        local session = Moteur.session
        choisir(101)
        voir()
        egal(c101, Moteur.courante)
        choisir(102)
        voir()
        egal(c102, Moteur.courante, 'reprise')
        demander('Encore un peu')
        egal(session, Moteur.session, 'rien de relancé pour un aller-retour sans demande')
        choisir(101)
        voir()
        demander('Et la 101 ?')
        egal('session-' .. c101.id, Moteur.courante.sessionID)
        choisir(102)
        voir()
        demander('Encore un peu plus')
        egal('session-' .. c102.id, recus[#recus].reprise, 'Claude reprend la session de la conversation')
        egal(c102.id, recus[#recus].conversation)
    end)
end)

essai("Historique de la photo : ses étapes (raison, date), ses reprises à la main ; dans le fil sans auteur, joint une seule fois à la demande", function()
    local p201 = photo(201)
    local entrees = {}
    for k = 1, 10 do
        entrees[k] = etape(string.format('2026-10-%02d 09:%02d', k + 10, k), 'passe ' .. k, 'raison ' .. k)
    end
    entrees[10] = etape('2026-10-25 14:30', 'passe 2 : finitions', 'Peau trop rouge : teinte baissée.', 'E10')
    journal(p201, entrees)
    p201.editCount, p201.lastEditTime, p201.reglages.Exposure2012 = 3, 100, 0.45
    apresClaude(p201, 'passe 2 : finitions', { Exposure2012 = 0.45, Shadows2012 = 0 })
    retoucherALaMain(p201, 'Exposure2012', 0.6)
    depart({})
    choisir(201)
    ouvrir(function(p)
        local c = Moteur.courante
        local h = historiques(c, 'historique')
        egal(1, #h, "l'historique en tête de la conversation neuve")
        local lignes = Texte.lignes(h[1].texte)
        egal("Historique de la photo : 10 étapes de Claude (les 8 dernières ci-dessous), la dernière le 25 oct. 2026, 14 h 30, "
            .. "puis des reprises à la main.", lignes[1])
        egal(1 + 8 + 1, #lignes, "l'en-tête, les 8 dernières étapes, les reprises")
        egal("•  13 oct. 2026, 9 h 03 · passe 3 — raison 3", lignes[2], 'les plus anciennes montrées, dans l\'ordre')
        egal("•  25 oct. 2026, 14 h 30 · passe 2 : finitions — Peau trop rouge : teinte baissée.", lignes[9])
        egal("•  Repris à la main depuis « passe 2 : finitions » : Exposition 0,45 → 0,6", lignes[10])
        -- Dans le fil : le genre note, l'icône sur la première ligne, ni « Vous » ni « Claude » ni heure.
        Fenetre.rafraichir()
        local fil = Fil.lignes(c, Fenetre.largeurTexte())
        egal('note', fil[1].genre)
        egal('note', fil[1].icone)
        for _, l in ipairs(fil) do
            egal(nil, l.auteur, "l'historique n'est d'aucun tour")
            egal(nil, l.heure)
            vrai(Fil.occupe(l) <= Fenetre.largeurTexte(), 'coupée à la largeur')
        end
        contient(p.t1, 'Historique de la photo')
        -- Chaque caractère est mesuré (Metriques) : aucun nouveau.
        for car in Texte.caracteres(h[1].texte .. h[1].pourClaude) do
            vrai(car == '\n' or Metriques.texte.chasse[car], 'caractère non mesuré : ' .. car)
        end
        -- La demande suivante l'emporte, après la ligne de contexte, une seule fois.
        local message = demander('Continue la retouche')
        local debut = message:find('[Lightroom : ', 1, true)
        local hist = message:find('[Historique de la photo : 10 étapes de Claude', 1, true)
        local demande = message:find('Continue la retouche', 1, true)
        vrai(debut and hist and demande and debut < hist and hist < demande, message)
        contient(message, 'Repris à la main depuis « passe 2 : finitions » : Exposure2012 0,45 → 0,6', 'les clés de Lightroom pour Claude')
        egal(true, h[1].envoye)
        absent(demander('Et le ciel ?'), 'Historique de la photo', 'une seule fois')
        -- Relue du disque : l'élément garde ce qu'il est.
        local relue = Stockage.lire(c.id)
        egal('historique', relue.elements[1].genre)
        egal(true, relue.elements[1].envoye)
    end)
end)

-- Les réglages d'un RAW tels que Lightroom les rend, à leurs valeurs par défaut d'Adobe (Adobe Color,
-- Telle quelle, netteté 40 et bruit de couleur 25, le reste à 0, sans cadre ni masque), puis ceux-là.
local function reglagesRaw(changes)
    local r = { CameraProfile = 'Adobe Standard', Look = { Name = 'Adobe Color', Amount = 1 }, WhiteBalance = 'As Shot',
        Temperature = 5150, Tint = 12, Exposure2012 = 0, Contrast2012 = 0, Highlights2012 = 0, Shadows2012 = 0, Whites2012 = 0,
        Blacks2012 = 0, Texture = 0, Clarity2012 = 0, Dehaze = 0, Vibrance = 0, Saturation = 0, ConvertToGrayscale = false,
        ToneCurvePV2012 = { 0, 0, 255, 255 }, ToneCurvePV2012Red = { 0, 0, 255, 255 }, ParametricShadows = 0, ParametricDarks = 0,
        ParametricLights = 0, ParametricHighlights = 0, ParametricShadowSplit = 25, ParametricMidtoneSplit = 50,
        ParametricHighlightSplit = 75, HueAdjustmentRed = 0, SaturationAdjustmentBlue = 0, LuminanceAdjustmentAqua = 0,
        SplitToningShadowHue = 0, SplitToningShadowSaturation = 0, ColorGradeMidtoneSat = 0, ColorGradeBlending = 50,
        SplitToningBalance = 0, Sharpness = 40, SharpenRadius = 1, SharpenDetail = 25, LuminanceSmoothing = 0, ColorNoiseReduction = 25,
        LensProfileEnable = 0, AutoLateralCA = 0, LensManualDistortionAmount = 0, VignetteAmount = 0, DefringePurpleAmount = 0,
        PerspectiveUpright = 0, PerspectiveVertical = 0, PerspectiveScale = 100, PostCropVignetteAmount = 0, GrainAmount = 0,
        ShadowTint = 0, RedHue = 0, CropLeft = 0, CropTop = 0, CropRight = 1, CropBottom = 1, CropAngle = 0,
        MaskGroupBasedCorrections = {}, RetouchAreas = {}, RedEyeInfo = {}, LensBlur = { Active = false } }
    for k, v in pairs(changes or {}) do
        r[k] = v
    end
    return r
end

essai("Historique d'une photo sans étape de Claude : ses réglages hors de leur valeur par défaut, dans le fil et joints à la première demande ; aux valeurs d'Adobe, rien ; avec des étapes, pas de résumé", function()
    -- Retouchée à la main : profil de l'appareil, balance, exposition, ombres, recadrée, deux masques.
    local p205 = photo(205, { editCount = 3 })
    p205.reglages = reglagesRaw({ CameraProfile = 'Camera CLASSIC CHROME', Look = {}, WhiteBalance = 'Custom', Temperature = 5600, Tint = 8,
        Exposure2012 = 0.45, Shadows2012 = 30, CropLeft = 0.05, CropRight = 0.95, MaskGroupBasedCorrections = { {}, {} } })
    -- Un paramètre prédéfini posé à l'importation (rien de retouché à la main, editCount 0).
    local p206 = photo(206)
    p206.reglages = reglagesRaw({ Vibrance = 15 })
    -- Aux valeurs d'Adobe : pas d'historique ; avec des étapes de Claude : ses étapes, pas de résumé.
    local p207 = photo(207, { editCount = 0 })
    p207.reglages = reglagesRaw()
    local p208 = photo(208, { editCount = 2 })
    p208.reglages = reglagesRaw({ Exposure2012 = 0.3 })
    journal(p208, { etape('2026-10-24 10:02', 'passe 1 : lumière', 'Sous-exposée.') })
    depart({})
    choisir(205)
    ouvrir(function()
        local c = Moteur.courante
        local h = historiques(c, 'historique')
        egal(1, #h, "l'historique en tête de la conversation neuve")
        local fine = '\226\128\175'
        local reglages = "Réglages hors des valeurs par défaut : Profil Camera CLASSIC CHROME · Balance 5" .. fine .. "600" .. fine
            .. "K / +8 · Exposition +0,45 · Ombres +30 · Recadrée · 2 masques"
        egal("Historique de la photo : retouchée à la main, sans étape de Claude.\n•  " .. reglages, h[1].texte)
        egal("[Historique de la photo : retouchée à la main, sans étape de Claude ; " .. reglages .. "]", h[1].pourClaude)
        egal(false, Conversation.commencee(c), "l'historique ne commence pas la conversation")
        -- Chaque caractère est mesuré (Metriques) : aucun nouveau ; dans le fil, coupé à sa largeur.
        for car in Texte.caracteres(h[1].texte .. h[1].pourClaude) do
            vrai(car == '\n' or Metriques.texte.chasse[car], 'caractère non mesuré : ' .. car)
        end
        Fenetre.rafraichir()
        for _, l in ipairs(Fil.lignes(c, Fenetre.largeurTexte())) do
            vrai(Fil.occupe(l) <= Fenetre.largeurTexte(), 'coupée à la largeur : ' .. tostring(l.texte))
        end
        -- Claude le reçoit avec la première demande, comme le reste de l'historique, une seule fois.
        local message = demander('Retouche-la')
        contient(message, h[1].pourClaude, "les réglages joints à la demande")
        absent(demander('Et le ciel ?'), 'Réglages hors des valeurs par défaut', 'une seule fois')
        -- Sans retouche à la main : « sans étape de Claude », avec ses réglages.
        choisir(206)
        voir()
        egal("Historique de la photo : sans étape de Claude.\n•  Réglages hors des valeurs par défaut : Vibrance +15",
            historiques(Moteur.courante, 'historique')[1].texte)
        -- Aux valeurs d'Adobe, sans retouche : rien.
        choisir(207)
        voir()
        egal(207, Moteur.courante.photo)
        egal(0, #historiques(Moteur.courante), 'aux valeurs par défaut : pas d\'historique')
        -- Des étapes de Claude : son journal, sans résumé des réglages.
        choisir(208)
        voir()
        local h208 = historiques(Moteur.courante, 'historique')
        egal(1, #h208)
        contient(h208[1].texte, '1 étape de Claude')
        absent(h208[1].texte, 'Réglages hors des valeurs par défaut', 'pas de résumé avec des étapes de Claude')
    end)
    -- Des réglages illisibles (getDevelopSettings en échec) : rien d'inventé, l'historique reste.
    local p209 = photo(209, { editCount = 1 })
    p209.getDevelopSettings = function() error('illisible') end
    local etat = Historique.lire(209)
    egal(nil, etat.reglages)
    egal("Historique de la photo : retouchée à la main, sans étape de Claude.", Historique.historique(etat).texte)
    -- Ce qu'une conversation a vu ne lit pas les réglages.
    egal(nil, Historique.lire(205, true).reglages, 'sans les réglages')
end)

essai("Depuis la dernière fois : une étape de Claude faite ailleurs, une reprise à la main ; rien de changé, rien d'ajouté ; ses propres étapes non", function()
    local p301 = photo(301)
    photo(302)
    journal(p301, { etape('2026-10-24 10:00', 'passe 1 : lumière', 'Sous-exposée.', 'A1') })
    p301.editCount, p301.lastEditTime = 2, 50
    apresClaude(p301, 'passe 1 : lumière', { Exposure2012 = 0 })
    local c301 = gardee(301, 'Pont')
    depart({ c301 })
    choisir(302)
    ouvrir(function()
        -- Une étape faite ailleurs (la Demande rapide, Claude Desktop) : le complément, avec elle seule.
        journal(p301, { etape('2026-10-24 10:00', 'passe 1 : lumière', 'Sous-exposée.', 'A1'),
            etape('2026-10-25 08:15', 'balance', 'Dominante bleue.', 'A2') })
        p301.editCount, p301.lastEditTime = 3, 60
        apresClaude(p301, 'balance', { Exposure2012 = 0 })
        choisir(301)
        voir()
        egal(c301, Moteur.courante)
        local d = historiques(c301, 'depuis')
        egal(1, #d, 'le complément')
        egal("Depuis la dernière fois : 1 étape de Claude.\n•  25 oct. 2026, 8 h 15 · balance — Dominante bleue.", d[1].texte)
        vrai(Fichiers.lire(Stockage.fichier(c301.id)):find('Dominante bleue', 1, true), 'réécrite sur le disque')
        -- Rien de changé : rien d'ajouté.
        choisir(302)
        voir()
        choisir(301)
        voir()
        egal(1, #historiques(c301, 'depuis'), 'rien de changé, rien ajouté')
        -- Une reprise à la main.
        choisir(302)
        voir()
        retoucherALaMain(p301, 'Exposure2012', 0.3)
        choisir(301)
        voir()
        d = historiques(c301, 'depuis')
        egal(2, #d)
        egal("Depuis la dernière fois : des reprises à la main.\n•  Repris à la main depuis « balance » : Exposition 0 → 0,3", d[2].texte)
        -- Une reprise faite pendant que la conversation est montrée : jointe à la demande qui suit.
        retoucherALaMain(p301, 'Shadows2012', 20)
        apresClaude(p301, 'balance', { Exposure2012 = 0, Shadows2012 = 0 })
        p301.editCount = p301.editCount + 1
        local message = demander('Et maintenant ?')
        egal(3, #historiques(c301, 'depuis'), 'complétée avant la demande')
        contient(message, '[Depuis la dernière fois : 1 étape de Claude ; 25 oct. 2026, 8 h 15 · balance — Dominante bleue.]')
        contient(message, 'Exposure2012 0 → 0,3')
        contient(message, 'Shadows2012 0 → 20')
        for _, e in ipairs(historiques(c301)) do
            egal(true, e.envoye, 'chacun envoyé')
        end
        absent(demander('Merci'), 'Depuis la dernière fois', 'une seule fois chacun')
        -- Les étapes de Claude dans cette conversation (à la fin de son tour, Moteur.noterVu) : pas de
        -- complément pour elles.
        local avant = #historiques(c301)
        local taches = #S.taches
        Fenetre.envoyer('Une passe de plus')
        S.taches[#S.taches]()
        vrai(#S.taches > taches)
        journal(p301, { etape('2026-10-24 10:00', 'passe 1 : lumière', 'Sous-exposée.', 'A1'),
            etape('2026-10-25 08:15', 'balance', 'Dominante bleue.', 'A2'), etape(AUJOURDHUI .. ' 23:59', 'passe 3', 'Ciel.', 'A3') })
        p301.editCount, p301.lastEditTime = p301.editCount + 1, p301.lastEditTime + 1
        apresClaude(p301, 'passe 3', { Exposure2012 = 0.3 })
        Moteur.traiter(c301, { genre = 'fin', reussie = true, interrompue = false, session = 's' })
        choisir(302)
        voir()
        choisir(301)
        voir()
        egal(avant, #historiques(c301), 'ses propres étapes ne font pas de complément')
    end)
end)

essai("Fenêtre rouverte sur la même photo : ce qui a changé fenêtre fermée se dit (Claude Desktop), et au rappel par le menu", function()
    local p351 = photo(351)
    journal(p351, { etape('2026-10-24 10:00', 'passe 1', 'Sous-exposée.', 'F1') })
    local c351 = gardee(351, 'Trois cent cinquante et un')
    depart({ c351 })
    choisir(351)
    ouvrir(function()
        egal(c351, Moteur.courante)
        egal(0, #historiques(c351))
    end)
    -- Fenêtre fermée : une étape faite par Claude Desktop sur la même photo.
    journal(p351, { etape('2026-10-24 10:00', 'passe 1', 'Sous-exposée.', 'F1'), etape('2026-10-25 16:40', 'recadrage', 'Horizon penché.', 'F2') })
    ouvrir(function()
        egal(c351, Moteur.courante, 'la même conversation')
        local d = historiques(c351, 'depuis')
        egal(1, #d, "dite à l'ouverture")
        contient(d[1].texte, 'recadrage — Horizon penché.')
        -- Rappelée par le menu (fenêtre déjà ouverte), après une reprise à la main.
        p351.editCount, p351.lastEditTime = 1, 1
        apresClaude(p351, 'recadrage', { Exposure2012 = 0 })
        p351.editCount = 2
        p351.reglages.Exposure2012 = 0.2
        local taches = #S.taches
        Fenetre.afficher()
        egal(taches + 1, #S.taches)
        S.taches[#S.taches]()
        egal(2, #historiques(c351, 'depuis'), 'au rappel aussi')
        -- Pendant que Claude travaille : rien.
        p351.editCount = 3
        p351.reglages.Exposure2012 = 0.4
        Moteur.travaille = true
        egal(false, Fenetre.revoirPhoto())
        Moteur.travaille = false
    end)
end)

essai("Historique joint : envoyé seulement une fois la demande partie ; Claude Code introuvable, reprise échouée, arrêt avant toute réponse : il rejoint la demande suivante, avec l'historique actuel si la session est perdue", function()
    local p851 = photo(851)
    local entrees = { etape('2026-10-20 10:00', 'passe 1', 'Lumière.', 'H1'), etape('2026-10-20 10:05', 'passe 2', 'Couleurs.', 'H2') }
    journal(p851, entrees)
    depart({})
    choisir(851)
    local c = Fenetre.conversationNeuve(851, '851:1:851')
    Moteur.courante = c
    local h = historiques(c, 'historique')[1]
    vrai(h, "l'historique de la photo")
    local function fin(session)
        Moteur.traiter(c, { genre = 'fin', reussie = true, interrompue = false, session = session or '' })
        vrai(not Moteur.travaille, 'tour fini')
    end
    -- Claude Code introuvable : Session:lancer lève une erreur à l'envoi.
    echecEnvoi = "Claude Code est introuvable (/nulle/part/claude)."
    local ok, raison = Moteur.envoyer('Retouche-la')
    echecEnvoi = nil
    egal(false, ok)
    contient(raison, 'introuvable')
    egal(false, h.envoye, "pas arrivé à Claude : encore à envoyer")
    egal(false, Moteur.travaille)
    local relue = Stockage.lire(c.id)
    egal(false, relue.elements[1].envoye, 'sur le disque aussi')
    vrai(Moteur.envoyer('Retouche-la'))
    contient(recus[#recus].message, '[Historique de la photo : 2 étapes de Claude', 'joint à la demande suivante')
    egal(true, h.envoye)
    fin('s-851')
    egal('s-851', c.sessionID)
    -- La reprise échoue (Claude Code a effacé la session) : le complément redevient à envoyer, et
    -- la demande renvoyée part d'une session neuve avec l'historique actuel de la photo.
    Moteur.arreterSession()
    entrees[3] = etape('2026-10-24 09:00', 'recadrage', 'Horizon penché.', 'H3')
    journal(p851, entrees)
    vrai(Moteur.completerDepuis(c), 'le complément')
    local d = historiques(c, 'depuis')[1]
    vrai(Moteur.envoyer('Et le ciel ?'))
    egal('s-851', recus[#recus].reprise, 'la session reprise')
    contient(recus[#recus].message, '[Depuis la dernière fois : 1 étape de Claude')
    egal(true, d.envoye)
    Moteur.processusFini(Moteur.session, 1, "No conversation found with session ID: s-851")
    egal(false, Moteur.travaille)
    egal(nil, c.sessionID, 'session perdue')
    egal(false, d.envoye, 'le complément redevient à envoyer')
    egal(true, h.envoye, "l'historique de la première demande reste envoyé")
    vrai(Moteur.envoyer('Et le ciel ?'))
    local message = recus[#recus].message
    egal(nil, recus[#recus].reprise, 'une session neuve')
    contient(message, '[Depuis la dernière fois : 1 étape de Claude', 'le complément rejoint la demande renvoyée')
    contient(message, '[Historique de la photo : 3 étapes de Claude', "l'historique actuel de la photo aussi")
    local tous = historiques(c, 'historique')
    egal(2, #tous, "l'historique actuel dans le fil")
    egal(true, tous[2].envoye)
    egal(nil, c.sessionPerdue)
    fin('s-851b')
    vrai(Moteur.envoyer('Merci'))
    absent(recus[#recus].message, 'Historique de la photo', 'une seule fois')
    absent(recus[#recus].message, 'Depuis la dernière fois', 'une seule fois')
    fin('s-851b')
    -- Claude Code s'arrête avant toute réponse de Claude : le complément redevient à envoyer ;
    -- après une réponse, non.
    entrees[4] = etape('2026-10-24 09:30', 'balance', 'Dominante bleue.', 'H4')
    journal(p851, entrees)
    vrai(Moteur.completerDepuis(c))
    local d2 = historiques(c, 'depuis')[2]
    vrai(Moteur.envoyer('Encore'))
    egal(true, d2.envoye)
    Moteur.processusFini(Moteur.session, 1, 'erreur')
    egal(false, d2.envoye, 'arrêt avant toute réponse : à envoyer')
    egal('s-851b', c.sessionID, 'la session reste')
    vrai(Moteur.envoyer('Encore'))
    contient(recus[#recus].message, 'balance — Dominante bleue.')
    Moteur.traiter(c, { genre = 'assistant', blocs = { { genre = 'texte', texte = 'Je regarde.' } } })
    Moteur.processusFini(Moteur.session, 1, 'erreur')
    egal(true, d2.envoye, 'après une réponse de Claude : reçu')
end)

-- Groupe --------------------------------------------------------------------------------------

essai("Groupe : jamais gardé, sa clé sans l'ordre ni la photo active, son résumé court ; quitté, son dossier s'efface", function()
    photo(401)
    photo(402)
    photo(403)
    journal(photos[401], { etape('2026-10-24 10:00', 'passe 1', 'raison', 'G1') })
    depart({})
    choisir(401, 402, 403)
    local cle = Lightroom.photos().groupe
    choisir(403, 401, 402)
    egal(cle, Lightroom.photos().groupe, "la clé du groupe : sans l'ordre ni la photo active")
    egal('3:401:402:403', cle)
    choisir(401)
    egal(nil, Lightroom.photos().groupe, "pas de groupe pour une photo seule")
    choisir(401, 402, 403)
    ouvrir(function(p)
        local g = Moteur.courante
        egal(cle, g.groupe, 'la conversation du groupe')
        egal(nil, g.photo)
        egal('3 photos', p.titre)
        egal("1 de ces 3 photos a déjà des étapes de Claude : DSCF0401.RAF.", historiques(g, 'groupe')[1].texte)
        -- Une autre photo active, la même sélection : la même conversation.
        choisir(402, 403, 401)
        voir()
        egal(g, Moteur.courante, 'changer de photo active ne change pas de conversation')
        egal(false, p.peutRepartir, 'Repartir à neuf grisé sans photo seule')
        -- Une demande : jamais gardée, images dans un dossier temporaire.
        local message = demander('Harmonise-les')
        contient(message, '[1 de ces 3 photos a déjà des étapes de Claude : DSCF0401.RAF]')
        for _, c in ipairs(Moteur.conversations) do
            vrai(c ~= g, 'pas dans la liste')
        end
        egal(false, Fichiers.existe(Stockage.fichier(g.id)), 'jamais écrite')
        egal(0, dossiersGardes())
        contient(Moteur.dossier(g), '/Groupes/', 'ses images en temporaire')
        Fichiers.creerDossier(Moteur.dossier(g))
        -- Cinq photos sans étape : « Aucune ».
        photo(404)
        photo(405)
        choisir(404, 405)
        voir()
        vrai(Moteur.courante ~= g, 'un autre groupe')
        egal("Aucune de ces 2 photos n'a encore d'étape de Claude.", historiques(Moteur.courante, 'groupe')[1].texte)
        egal(false, Fichiers.existe(Moteur.dossier(g)), 'le dossier du groupe quitté est effacé')
        -- Plus de noms que NOMS_GROUPE : « … ».
        local r = Historique.groupe({ m = 9, n = 7, noms = { 'a', 'b', 'c', 'd', 'e' } })
        egal("7 de ces 9 photos ont déjà des étapes de Claude : a, b, c, d, e, ….", r.texte)
    end)
end)

essai("Groupe : les photos qui ont des étapes de Claude, par les lectures groupées du catalogue (journal, propriétaire, uuid)", function()
    local a, b, c, d = photo(451), photo(452), photo(453), photo(454)
    journal(a, { etape('2026-10-24 10:00', 'passe 1', 'r', 'B1') })
    journal(b, { etape('2026-10-24 10:00', 'passe 1', 'r', 'B2') })
    journal(c, { etape('2026-10-24 10:00', 'passe 1', 'r', 'B3') })
    -- a : son journal à elle ; b : celui d'une autre photo (copie virtuelle) ; c : sans propriétaire
    -- (relu par Photos.lireJson) ; d : sans journal.
    local champs = { [a] = { journalClaude = a.proprietes.journalClaude, proprietaireMemoire = 'uuid-a' },
        [b] = { journalClaude = b.proprietes.journalClaude, proprietaireMemoire = 'uuid-autre' },
        [c] = { journalClaude = c.proprietes.journalClaude }, [d] = {} }
    local lus = {}
    S.catalogue.batchGetPropertyForPlugin = function(_, liste, plugin, cles)
        egal(_PLUGIN, plugin)
        egal('journalClaude proprietaireMemoire', table.concat(cles, ' '))
        lus[#lus + 1] = #liste
        return champs
    end
    S.catalogue.batchGetRawMetadata = function(_, _, cles)
        egal('uuid', table.concat(cles, ' '))
        return { [a] = { uuid = 'uuid-a' }, [b] = { uuid = 'uuid-b' }, [c] = { uuid = 'uuid-c' }, [d] = { uuid = 'uuid-d' } }
    end
    choisir(451, 452, 453, 454)
    local ok, g = pcall(Historique.lireGroupe)
    S.catalogue.batchGetPropertyForPlugin, S.catalogue.batchGetRawMetadata = nil, nil
    assert(ok, g)
    egal('4', table.concat(lus, ' '), 'une lecture groupée')
    egal(4, g.m)
    egal(2, g.n, 'la sienne et celle sans propriétaire')
    egal('DSCF0451.RAF DSCF0453.RAF', table.concat(g.noms, ' '))
end)

essai("Groupe de plus de 500 photos : compté sur toute la sélection par les lectures groupées ; si elles échouent, les 500 premières, et le texte le dit", function()
    -- 600 photos, dont seules les 100 dernières ont des étapes de Claude.
    local ids, champs, brutes = {}, {}, {}
    for k = 1, 600 do
        local id = 3000 + k
        local p = photo(id)
        ids[k] = id
        if k > 500 then
            journal(p, { etape('2026-10-24 10:00', 'passe 1', 'r', 'M' .. k) })
        end
        champs[p] = { journalClaude = p.proprietes.journalClaude, proprietaireMemoire = p.proprietes.journalClaude and ('uuid-' .. id) or nil }
        brutes[p] = { uuid = 'uuid-' .. id }
    end
    local lus = {}
    S.catalogue.batchGetPropertyForPlugin = function(_, liste)
        lus[#lus + 1] = #liste
        return champs
    end
    S.catalogue.batchGetRawMetadata = function() return brutes end
    choisir((table.unpack or unpack)(ids))
    local ok, g = pcall(Historique.lireGroupe)
    S.catalogue.batchGetPropertyForPlugin, S.catalogue.batchGetRawMetadata = nil, nil
    assert(ok, g)
    egal('600', table.concat(lus, ' '), 'une lecture groupée de toute la sélection')
    egal(600, g.m)
    egal(600, g.lues)
    egal(100, g.n, 'les 100 au-delà de la 500e comptées')
    local r = Historique.groupe(g)
    egal("100 de ces 600 photos ont déjà des étapes de Claude : DSCF3501.RAF, DSCF3502.RAF, DSCF3503.RAF, DSCF3504.RAF, DSCF3505.RAF, ….", r.texte)
    -- Les lectures groupées en échec : les 500 premières, une à une, et le texte dit la borne.
    local ok2, g2 = pcall(Historique.lireGroupe)
    assert(ok2, g2)
    egal(500, g2.lues)
    egal(0, g2.n)
    local r2 = Historique.groupe(g2)
    egal("Aucune des 500 premières de ces 600 photos n'a encore d'étape de Claude.", r2.texte)
    egal("2 des 500 premières de ces 600 photos ont déjà des étapes de Claude : a, b.",
        Historique.groupe({ m = 600, lues = 500, n = 2, noms = { 'a', 'b' } }).texte)
    for car in Texte.caracteres(r.texte .. r2.texte .. r2.pourClaude) do
        vrai(car == '\n' or Metriques.texte.chasse[car], 'caractère non mesuré : ' .. car)
    end
end)

essai("Chargement du module : les dossiers temporaires des groupes et des demandes rapides s'effacent ; rien d'autre de Temporaire ni des conversations", function()
    depart({})
    photo(991)
    local c = gardee(991, 'Gardée')
    Stockage.enregistrer(c)
    local temporaire = Chemins.temporaire()
    Fichiers.ecrire(temporaire .. '/Groupes/g1/planche.jpg', 'jpeg')
    Fichiers.ecrire(temporaire .. '/Groupes/g2/apercu.jpg', 'jpeg')
    Fichiers.ecrire(temporaire .. '/Rapide/r1/apercu.jpg', 'jpeg')
    Fichiers.ecrire(temporaire .. '/PhotoActive/x/vignette.jpg', 'jpeg')
    Fichiers.ecrire(temporaire .. '/Pourquoi/991/avant.jpg', 'jpeg')
    local demarrer = prefs.demarrerAuLancement
    prefs.demarrerAuLancement = false
    local taches = #S.taches
    local ok, erreur = pcall(dofile, S.plugin .. '/Init.lua')
    prefs.demarrerAuLancement = demarrer
    -- Init.lua allume le Suivi (Releve.allumer) : il ne tourne pas dans les essais.
    require('Releve').allume = false
    assert(ok, erreur)
    egal(taches + 1, #S.taches, 'le ménage dans une tâche')
    S.taches[#S.taches]()
    egal(false, Fichiers.existe(temporaire .. '/Groupes'), 'les images des groupes effacées')
    egal(false, Fichiers.existe(temporaire .. '/Rapide'), 'celles des demandes rapides aussi')
    vrai(Fichiers.existe(temporaire .. '/PhotoActive/x/vignette.jpg'), "l'aperçu de la photo active reste")
    vrai(Fichiers.existe(temporaire .. '/Pourquoi/991/avant.jpg'), 'Pourquoi ? reste')
    vrai(Fichiers.existe(Stockage.fichier(c.id)), 'les conversations restent')
    egal(0, require('Menage').temporaires(), 'rien de plus')
end)

-- Claude au travail ----------------------------------------------------------------------------

essai("Claude au travail : rien ne change, ni juste après s'il a changé la sélection ; case décochée : rien ne change", function()
    photo(501)
    photo(502)
    photo(503)
    photo(504)
    local c501 = gardee(501, 'Cinq cent un')
    depart({ c501 })
    choisir(501)
    ouvrir(function(p)
        egal(c501, Moteur.courante)
        egal(true, p.peutRepartir)
        Moteur.travaille = true
        Fenetre.rafraichir()
        egal(false, p.peutRepartir, 'grisé pendant que Claude travaille')
        choisir(502)
        voir()
        egal(c501, Moteur.courante, 'Claude travaille : même conversation')
        contient(c501.cle, '502', 'la sélection de Claude devient la clé de la conversation')
        Moteur.travaille = false
        Moteur.finTravail = os.time()
        choisir(503)
        voir()
        egal(c501, Moteur.courante, 'juste après son travail : même conversation')
        Moteur.finTravail = os.time() - Fenetre.DELAI_APRES_TRAVAIL - 60
        Fenetre.cleVueLe = os.time()
        prefs.nouvelleParPhoto = false
        choisir(504)
        voir()
        egal(c501, Moteur.courante, 'case décochée : la conversation montrée reste')
        prefs.nouvelleParPhoto = true
        choisir(502)
        voir()
        egal(502, Moteur.courante.photo, 'plus tard, la photo choisie par Dany : la sienne')
    end)
    -- Une fenêtre fermée pendant le travail de Claude retrouve sa conversation à la réouverture.
    choisir(501)
    Moteur.courante = c501
    Moteur.travaille = true
    choisir(503)
    ouvrir(function()
        egal(c501, Moteur.courante, 'Claude travaille à la réouverture : sa conversation')
    end)
    Moteur.travaille = false
end)

-- Repartir à neuf ------------------------------------------------------------------------------

essai("Repartir à neuf : une conversation neuve avec son historique ; l'ancienne mise de côté sur le disque, jamais effacée ; grisé sans photo seule", function()
    local p601 = photo(601)
    photo(602)
    journal(p601, { etape('2026-10-25 11:00', 'passe 1', 'Contraste.', 'R1') })
    local c601 = gardee(601, 'Six cent un')
    depart({ c601 })
    choisir(601)
    ouvrir(function(p, contenu)
        egal(c601, Moteur.courante)
        egal(true, p.peutRepartir)
        local bouton
        for _, v in ipairs(S.vues(contenu)) do
            if S.BOUTONS[v.genre] and v.args.title == 'Repartir à neuf' then
                bouton = v
            end
        end
        vrai(bouton, 'le bouton, à droite du titre')
        local taches = #S.taches
        S.cliquer(bouton)
        egal(taches + 1, #S.taches, 'dans une tâche')
        S.taches[#S.taches]()
        local neuve = Moteur.courante
        vrai(neuve ~= c601 and neuve.photo == 601, 'une conversation neuve pour la photo')
        egal(1, #historiques(neuve, 'historique'), 'avec son historique')
        egal(Fenetre.REPARTIE, p.message)
        egal(true, c601.ecartee, "l'ancienne mise de côté")
        egal(true, Stockage.lire(c601.id).ecartee, 'sur le disque')
        vrai(Fichiers.existe(Stockage.fichier(c601.id)), 'jamais effacée')
        egal(false, Moteur.montrable(c601), 'plus montrée')
        egal(nil, Moteur.conversationDe(601), 'plus reprise')
        -- Revenir à la photo : pas l'ancienne.
        choisir(602)
        voir()
        choisir(601)
        voir()
        vrai(Moteur.courante ~= c601, "l'ancienne ne revient pas")
        -- Pendant que Claude travaille, et sans photo seule : refusé.
        Moteur.travaille = true
        egal(false, Fenetre.repartir())
        egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
        Moteur.travaille = false
        choisir(601, 602)
        egal(false, Fenetre.repartir())
        egal(Fenetre.REPARTIR_SANS_PHOTO, p.message)
        voir()
        egal(false, p.peutRepartir)
    end)
end)

essai("Repartir à neuf : grisé et refusé tant que la conversation montrée n'est pas celle de la photo active ; toutes ses conversations mises de côté, aucune ne revient", function()
    local p611 = photo(611)
    photo(612)
    journal(p611, { etape('2026-10-25 11:00', 'passe 1', 'Contraste.', 'Q1') })
    local maintenant = os.time()
    -- Deux conversations gardées pour la 611 (avant le correctif, chaque retour sur une photo en
    -- commençait une), et celle de la 612.
    local vieille = gardee(611, 'Vieille', maintenant - 3600)
    local recente = gardee(611, 'Récente', maintenant - 60)
    local c612 = gardee(612, 'Six cent douze', maintenant - 120)
    depart({ recente, c612, vieille })
    choisir(612)
    ouvrir(function(p)
        egal(c612, Moteur.courante)
        -- La case Autre photo décochée : la 611 choisie, la conversation de la 612 reste montrée.
        prefs.nouvelleParPhoto = false
        choisir(611)
        voir()
        egal(c612, Moteur.courante, 'case décochée : la conversation montrée reste')
        egal(false, p.peutRepartir, "grisé : la conversation montrée n'est pas celle de la photo active")
        egal(false, Fenetre.repartir(), 'refusé')
        egal(Fenetre.REPARTIR_AUTRE, p.message)
        egal(c612, Moteur.courante)
        for _, c in ipairs({ vieille, recente, c612 }) do
            egal(nil, c.ecartee, 'rien mis de côté : ' .. c.titre)
        end
        prefs.nouvelleParPhoto = true
        -- Une conversation neuve de la photo active compte : actif.
        Moteur.courante = Fenetre.conversationNeuve(611, '611:1:611')
        Fenetre.rafraichir()
        egal(true, p.peutRepartir, 'conversation neuve de la photo : actif')
        Moteur.courante = c612
        choisir(612)
        voir()
        choisir(611)
        voir()
        egal(recente, Moteur.courante, 'la plus récente de la photo')
        egal(true, p.peutRepartir)
        vrai(Fenetre.repartir())
        local neuve = Moteur.courante
        egal(611, neuve.photo)
        egal(true, recente.ecartee, 'la montrée mise de côté')
        egal(true, vieille.ecartee, 'la plus ancienne aussi')
        egal(true, Stockage.lire(vieille.id).ecartee, 'sur le disque')
        vrai(Fichiers.existe(Stockage.fichier(vieille.id)), 'jamais effacée')
        egal(nil, c612.ecartee, "celle d'une autre photo, non")
        egal(nil, Moteur.conversationDe(611), 'plus aucune reprise')
        -- Une autre photo, puis la 611 sans rien demander : ni l'une ni l'autre ne revient, ni pour
        -- la Demande rapide (Moteur.conversationPour).
        choisir(612)
        voir()
        egal(c612, Moteur.courante)
        local pour = Moteur.conversationPour(611, '611:1:611')
        vrai(pour ~= vieille and pour ~= recente, 'la Demande rapide en ferait une neuve')
        choisir(611)
        voir()
        vrai(Moteur.courante ~= vieille and Moteur.courante ~= recente, "aucune ancienne ne revient")
        egal(611, Moteur.courante.photo)
    end)
    prefs.nouvelleParPhoto = true
end)

-- Conversations d'avant le correctif -------------------------------------------------------------

essai("Conversations d'avant le correctif : la clé d'une photo seule en fait sa conversation, la plus récente seule ; un groupe ni une séance ne se montrent", function()
    local p701 = photo(701)
    photo(702)
    photo(703)
    local maintenant = os.time()
    local function ancienne(cle, modifiee, genre)
        local c = Conversation.nouvelle(modifiee)
        Conversation.ajouterDemande(c, 'Demande ' .. cle, modifiee)
        c.cle, c.modifiee, c.genre = cle, modifiee, genre
        Stockage.enregistrer(c)
        return c
    end
    Fichiers.supprimer(Chemins.conversations())
    local vieille = ancienne('701:1:701', maintenant - 7200)
    local recente = ancienne('701:1:701', maintenant - 3600)
    local groupe = ancienne('701:2:701:702', maintenant - 1800)
    local seance = ancienne('701:1:701', maintenant - 600, 'notation')
    -- La 703 : une conversation d'avant le correctif, et une plus récente gardée avec sa photo puis
    -- mise de côté par « Repartir à neuf » : l'ancienne ne revient pas.
    local avant703 = ancienne('703:1:703', maintenant - 9000)
    local ecartee703 = ancienne('703:1:703', maintenant - 900)
    ecartee703.photo, ecartee703.ecartee = 703, true
    Stockage.enregistrer(ecartee703)
    -- Une étape d'avant sa dernière modification, une d'après (faite ailleurs).
    journal(p701, { etape(os.date('%Y-%m-%d %H:%M', maintenant - 5400), 'avant', 'déjà vue', 'V1'),
        etape(os.date('%Y-%m-%d %H:%M', maintenant + 60), 'après', 'faite ailleurs', 'V2') })
    Moteur.charge = false
    Moteur.conversations, Moteur.courante = {}, nil
    Moteur.charger()
    egal(recente.id, Moteur.courante.id, 'la plus récente qui se montre')
    egal(recente.id, Moteur.conversationDe(701).id, 'la plus récente des deux est celle de la photo')
    -- La plus ancienne reste sans photo, plus montrée : après « Repartir à neuf » sur la plus récente,
    -- elle ne reviendrait pas.
    egal(nil, Moteur.trouver(vieille.id).photo, 'la plus ancienne : sans photo')
    egal(false, Moteur.montrable(Moteur.trouver(vieille.id)))
    egal(nil, Moteur.trouver(avant703.id).photo, "une plus récente, mise de côté, a déjà la photo")
    egal(nil, Moteur.conversationDe(703), 'rien ne revient pour la 703')
    egal(nil, Moteur.trouver(groupe.id).photo, "un groupe n'a pas de photo")
    egal(false, Moteur.montrable(Moteur.trouver(groupe.id)))
    egal(false, Moteur.montrable(Moteur.trouver(seance.id)))
    egal(false, (Moteur.ouvrir(seance.id)), "une séance reste refusée")
    Fenetre.cleVue, Fenetre.cleVueLe = nil, nil
    choisir(702)
    ouvrir(function()
        choisir(701)
        voir()
        local c = Moteur.courante
        egal(recente.id, c.id, 'la conversation de la photo revient')
        local d = historiques(c, 'depuis')
        egal(1, #d, "sans « vu » : ce qui est d'après sa dernière modification")
        contient(d[1].texte, 'après — faite ailleurs')
        absent(d[1].texte, 'déjà vue')
        vrai(c.vu, 'ce qu’elle a vu, noté')
    end)
    for _, c in ipairs({ vieille, recente, groupe, seance, avant703, ecartee703 }) do
        vrai(Fichiers.existe(Stockage.fichier(c.id)), 'rien effacé')
    end
end)

-- Obtenir (onglet Proposition) ------------------------------------------------------------------
-- Décision de Dany du 25 octobre 2026 : plus de proposition préparée à l'ouverture de la fenêtre ;
-- « Obtenir », sous la carte de l'onglet Proposition, la demande pour la photo seule active, dans sa
-- conversation.

-- Le bouton Obtenir de la fenêtre construite.
local function boutonObtenir(contenu)
    for _, v in ipairs(S.vues(contenu)) do
        if S.BOUTONS[v.genre] and v.args.title == 'Obtenir' then
            return v
        end
    end
    error('Obtenir introuvable', 2)
end

-- Une proposition de Claude dans `c` (preview_settings et sa réponse, sur la photo `id`) ; rend
-- l'élément.
local function proposer(c, appel, id)
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = appel, nom = 'mcp__developpeur__preview_settings',
        entree = { settings = { Exposure2012 = 0.3 }, reason = 'Plus lumineuse' } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = appel, images = {}, erreur = false,
        textes = { Json.encode({ mode = 'proposer', photo = { id = id, fichier = string.format('DSCF%04d.RAF', id) }, etape = 'proposition',
            changements = { { cle = 'Exposure2012', libelle = 'Exposition', avant = 0, apres = 0.3 } } }) } } } })
    local prop = Conversation.propositionEnAttente(c)
    vrai(prop, 'une proposition en attente')
    return prop
end

-- Un clic sur Obtenir (dans une tâche), puis la demande partie (Fenetre.envoyer, dans une autre).
local function cliquerObtenir(bouton)
    local taches = #S.taches
    S.cliquer(bouton)
    egal(taches + 1, #S.taches, 'Obtenir : dans une tâche')
    S.taches[#S.taches]()
    egal(taches + 2, #S.taches, 'la demande part dans une tâche')
    S.taches[#S.taches]()
    vrai(Moteur.travaille, 'Claude travaille')
    return recus[#recus]
end

-- La fin du tour de Claude, une minute avant la suite.
local function finirTour()
    local c = Moteur.enCours
    Moteur.traiter(c, { genre = 'fin', reussie = true, interrompue = false, session = 'session-' .. c.id })
    vrai(not Moteur.travaille, 'tour fini')
    Moteur.finTravail = os.time() - 60
end

essai("Plus de proposition à l'ouverture : ni fenêtre ouverte, ni rappelée par le menu, ni photo changée ; la préférence restée dans Lightroom est ignorée", function()
    local p801 = photo(801)
    photo(802)
    photo(803)
    journal(p801, { etape('2026-10-25 09:00', 'passe 1', 'Lumière.', 'P1') })
    local c802 = gardee(802, 'Huit cent deux')
    depart({ c802 })
    -- Une préférence d'avant le correctif, restée dans les réglages de Lightroom : sans effet.
    prefs.propositionAOuverture = true
    choisir(801)
    local envoyer, envois, avant = Fenetre.envoyer, {}, #recus
    Fenetre.envoyer = function(texte) envois[#envois + 1] = texte end
    local ok, erreur = pcall(ouvrir, function(p)
        egal(801, Moteur.courante.photo, 'une photo sans conversation : une neuve')
        egal('historique', Moteur.courante.elements[1].genre, 'son historique')
        egal(false, Conversation.commencee(Moteur.courante))
        egal(0, #envois, "rien à l'ouverture")
        -- Rappelée par le menu (fenêtre déjà ouverte).
        local taches = #S.taches
        Fenetre.afficher()
        egal(taches + 1, #S.taches)
        S.taches[#S.taches]()
        egal(0, #envois, 'rien au rappel par le menu')
        -- Une autre photo sans conversation, une photo qui a la sienne, un groupe.
        choisir(803)
        voir()
        egal(803, Moteur.courante.photo)
        choisir(802)
        voir()
        egal(c802, Moteur.courante)
        choisir(801, 803)
        voir()
        egal(0, #envois, 'rien quand la photo change')
        egal('focus', p.onglet, "l'onglet Focus, que chaque autre photo ramène (correctif 1.3.6) ; pas de bascule vers Proposition")
    end)
    Fenetre.envoyer = envoyer
    prefs.propositionAOuverture = nil
    assert(ok, erreur)
    egal(avant, #recus, "rien n'est parti à Claude")
    egal(nil, Chemins.defauts.propositionAOuverture, 'plus de valeur par défaut')
    egal(nil, Fenetre.proposerAOuverture)
    egal(nil, Fenetre.propositionAuto)
    egal(nil, Consignes.proposerOuverture)
end)

essai("Obtenir : actif pour une photo seule, Claude libre et rien en attente ; grisé pendant le travail (fenêtre ou Demande rapide), pour plusieurs photos ou aucune, quand une proposition attend ; refusé alors au bandeau", function()
    photo(811)
    photo(812)
    local c812 = gardee(812, 'Huit cent douze')
    depart({ c812 })
    choisir(811)
    ouvrir(function(p, contenu)
        local bouton = boutonObtenir(contenu)
        egal('peutObtenir', bouton.args.enabled.key, 'lié à peutObtenir')
        egal(true, p.peutObtenir, 'une photo seule sans conversation, Claude libre : actif')
        -- Claude travaille dans la fenêtre, puis pour la Demande rapide.
        Moteur.travaille = true
        Fenetre.rafraichir()
        egal(false, p.peutObtenir, 'Claude travaille dans la fenêtre')
        egal(false, Fenetre.obtenir())
        egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
        Moteur.travaille = false
        Fenetre.rafraichir()
        egal(true, p.peutObtenir)
        Moteur.travaille, Moteur.tourRapide = true, Moteur.RESERVE_RAPIDE
        Fenetre.majPhoto()
        egal(false, p.peutObtenir, 'Claude travaille pour la Demande rapide')
        egal(false, Fenetre.obtenir())
        egal(Fenetre.CLAUDE_TRAVAILLE, p.message)
        Moteur.travaille, Moteur.tourRapide = false, nil
        Fenetre.rafraichir()
        egal(true, p.peutObtenir, 'Claude libre')
        -- Plusieurs photos, puis aucune.
        choisir(811, 812)
        voir()
        egal(false, p.peutObtenir, 'plusieurs photos')
        p.onglet = 'proposition'
        local ok, erreur = pcall(S.cliquer, bouton)
        vrai(not ok and tostring(erreur):find('inactive', 1, true), 'grisé : clic refusé (' .. tostring(erreur) .. ')')
        egal(false, Fenetre.obtenir())
        egal(Fenetre.OBTENIR_SANS_PHOTO, p.message)
        S.photoActive, S.selection = nil, {}
        voir()
        egal(false, p.peutObtenir, 'aucune photo')
        egal(false, Fenetre.obtenir())
        egal(Fenetre.OBTENIR_SANS_PHOTO, p.message)
        -- Une proposition attend dans la conversation montrée.
        choisir(812)
        voir()
        egal(c812, Moteur.courante)
        egal(true, p.peutObtenir, 'sa conversation, rien en attente')
        local prop = proposer(c812, 'o812', 812)
        Fenetre.rafraichir()
        egal(false, p.peutObtenir, 'une proposition attend')
        egal(true, p.enAttente, 'Refuser, Ajuster… et Accepter actifs')
        egal(false, Fenetre.obtenir())
        egal(Fenetre.OBTENIR_EN_ATTENTE, p.message)
        -- Montrée ailleurs (la case Autre photo décochée), elle attend encore dans la conversation de
        -- la photo : Obtenir reste grisé.
        prefs.nouvelleParPhoto = false
        Fenetre.nouvelle()
        Fenetre.rafraichir()
        vrai(Moteur.courante ~= c812, 'une autre conversation montrée')
        egal(false, p.peutObtenir, 'une proposition attend dans la conversation de la photo')
        prefs.nouvelleParPhoto = true
        -- Décidée : Obtenir de nouveau actif.
        Conversation.decider(c812, prop.id, false)
        Fenetre.rafraichir()
        egal(true, p.peutObtenir, 'plus rien en attente')
        p.onglet = 'notation'
    end)
end)

essai("Obtenir : la demande part dans la conversation de la photo (neuve gardée dès cette demande, ou reprise) ; le fil n'en montre qu'une phrase, Claude reçoit la demande entière ; la proposition se montre dans l'onglet Proposition", function()
    local p821 = photo(821)
    photo(822)
    journal(p821, { etape('2026-10-25 08:00', 'passe 1', 'Ciel brûlé.', 'O1') })
    local c822 = gardee(822, 'Huit cent vingt-deux')
    depart({ c822 })
    choisir(821)
    ouvrir(function(p, contenu)
        local bouton = boutonObtenir(contenu)
        local c = Moteur.courante
        egal(821, c.photo)
        vrai(not Moteur.conversationDe(821), 'pas encore gardée')
        p.onglet = 'proposition'
        egal(true, p.peutObtenir)
        local recu = cliquerObtenir(bouton)
        egal(c, Moteur.courante, 'dans la conversation de la photo')
        egal(c.id, recu.conversation)
        egal(c, Moteur.conversationDe(821), 'gardée dès cette demande')
        vrai(Fichiers.existe(Stockage.fichier(c.id)), 'écrite sur le disque')
        -- Claude reçoit la demande entière (et l'historique de la photo, joint une fois) ; le fil n'en
        -- montre qu'une phrase.
        contient(recu.message, Consignes.obtenir.demande, 'la demande entière')
        contient(recu.message, 'preview_settings')
        contient(recu.message, '[Historique de la photo', "l'historique joint")
        local demande = c.elements[#c.elements]
        egal('dany', demande.genre)
        egal(Consignes.obtenir.fil, demande.texte, 'le fil montre la phrase courte')
        vrai(Texte.longueur(Consignes.obtenir.fil) < Texte.longueur(Consignes.obtenir.demande) / 2, 'courte')
        absent(demande.texte, 'preview_settings', 'sans le détail de la demande')
        Fenetre.rafraichir()
        egal(false, p.peutObtenir, 'pendant le travail : grisé')
        local vuDansLeFil = false
        for i = 1, Fenetre.T.lignes do
            if p['t' .. i] == Consignes.obtenir.fil then
                vuDansLeFil = true
            end
        end
        vrai(vuDansLeFil, 'la phrase courte dans le fil')
        -- Dany regarde la note entre-temps ; la proposition qui arrive montre l'onglet Proposition.
        p.onglet = 'notation'
        proposer(c, 'o821', 821)
        finirTour()
        Fenetre.rafraichir()
        egal('proposition', p.onglet, "la proposition se montre dans l'onglet Proposition")
        egal(true, p.enAttente)
        contient(p.propositionTexte, 'Exposition : 0 → 0,3')
        egal(false, p.peutObtenir, 'elle attend : grisé')
        Conversation.decider(c, Conversation.propositionEnAttente(c).id, false)
        -- Une photo qui a sa conversation : reprise, sa session reprise.
        c822.sessionID = 'session-822'
        choisir(822)
        voir()
        egal(c822, Moteur.courante)
        -- Une autre photo ramène Focus (correctif 1.3.6) : Dany revient à l'onglet Proposition.
        egal('focus', p.onglet, 'une autre photo : Focus')
        p.onglet = 'proposition'
        Fenetre.rafraichir()
        egal(true, p.peutObtenir)
        recu = cliquerObtenir(bouton)
        egal(c822.id, recu.conversation, 'dans sa conversation')
        egal('session-822', recu.reprise, 'Claude reprend sa session')
        egal(Consignes.obtenir.fil, c822.elements[#c822.elements].texte)
        finirTour()
        -- La case Autre photo décochée, une autre conversation montrée : Obtenir prend celle de la
        -- photo active, et la montre.
        prefs.nouvelleParPhoto = false
        choisir(821)
        voir()
        egal(c822, Moteur.courante, 'case décochée : la conversation montrée reste')
        Fenetre.rafraichir()
        egal(true, p.peutObtenir)
        recu = cliquerObtenir(bouton)
        egal(c, Moteur.courante, 'Obtenir montre la conversation de la photo active')
        egal(c.id, recu.conversation)
        egal('session-' .. c.id, recu.reprise)
        finirTour()
        prefs.nouvelleParPhoto = true
        p.onglet = 'notation'
    end)
end)

-- Pièces pures ----------------------------------------------------------------------------------

essai("Historique (pur) : nouvelles entrées après la dernière vue, par date quand elle n'y est plus ; clé d'une photo seule", function()
    local etat = { journal = { { date = '2026-10-20 10:00', etape = 'Claude · a', etape_id = '1', type = 'retouche', raison = '' },
        { date = '2026-10-21 10:00', etape = 'Claude · b', etape_id = '2', type = 'retouche', raison = '' },
        { date = '2026-10-22 10:00', etape = 'Claude · c', etape_id = '3', type = 'retouche', raison = '' } }, editCount = 4, lastEditTime = 9 }
    local vu = Historique.vu({ journal = { etat.journal[1], etat.journal[2] }, editCount = 4, lastEditTime = 9 })
    egal(1, #Historique.nouvelles(etat, vu))
    egal('Claude · c', Historique.nouvelles(etat, vu)[1].etape)
    -- La dernière vue n'y est plus (journal raccourci) : par sa date.
    vu.derniere.etape_id = 'perdu'
    egal(1, #Historique.nouvelles(etat, vu), 'par la date')
    egal(3, #Historique.nouvelles(etat, { n = 0 }), 'journal vu vide : toutes')
    egal(0, #Historique.nouvelles(etat, nil, nil), 'sans rien de vu ni de date : aucune')
    egal(false, Historique.retouchee(etat, { editCount = 4, lastEditTime = 9 }))
    egal(true, Historique.retouchee(etat, { editCount = 3, lastEditTime = 9 }))
    egal(nil, Historique.depuis(etat, Historique.vu(etat)), 'rien de changé : rien')
    egal(4961, Conversation.photoDeLaCle('4961:1:4961'))
    egal(nil, Conversation.photoDeLaCle('4961:2:4961:4962'))
    egal(nil, Conversation.photoDeLaCle('4961:1:4962'))
    egal(nil, Conversation.photoDeLaCle(nil))
    egal('25 oct. 2026, 14 h 30', Historique.date('2026-10-25 14:30'))
    vrai(getmetatable(Historique.vu(etat)) == nil, 'table neuve')
end)

essai("Réglages hors de leur valeur par défaut (pur) : chaque panneau, les défauts d'Adobe d'un RAW et d'un autre fichier, rien d'inventé, nombres à la française, dans l'ordre des panneaux", function()
    local fine, moins = '\226\128\175', '\226\136\146'
    local function texte(r, raw)
        local liste = Historique.ecarts(r, raw)
        vrai(getmetatable(liste) == nil, 'table neuve')
        return table.concat(liste, ' · ')
    end
    -- Aux valeurs d'Adobe : rien. Un RAW (netteté 40, bruit de couleur 25) ; un JPEG (Incorporé, 0).
    egal('', texte(reglagesRaw(), true), 'RAW aux valeurs d\'Adobe')
    local jpeg = { CameraProfile = 'Embedded', WhiteBalance = 'As Shot', IncrementalTemperature = 0, IncrementalTint = 0, Sharpness = 0,
        ColorNoiseReduction = 0, LuminanceSmoothing = 0, Exposure2012 = 0 }
    egal('', texte(jpeg, false), 'JPEG aux valeurs d\'Adobe')
    egal('Netteté 40 · Bruit de couleur 25', texte({ Sharpness = 40, ColorNoiseReduction = 25 }, false), 'les défauts d\'un RAW, pour un JPEG')
    egal('Netteté 0', texte(reglagesRaw({ Sharpness = 0 }), true))
    -- Rien d'inventé : ce que Lightroom n'a pas rendu se tait.
    egal('', texte({}, true), 'aucun réglage lu')
    egal('', texte(nil, true))
    -- Le profil : un autre, ou Adobe Color à une autre intensité.
    egal('Profil Camera PROVIA/Standard', texte(reglagesRaw({ CameraProfile = 'Camera PROVIA/Standard', Look = {} }), true))
    egal('Profil Adobe Color (intensité 80)', texte(reglagesRaw({ Look = { Name = 'Adobe Color', Amount = 0.8 } }), true))
    egal('Profil Adobe Standard', texte(reglagesRaw({ Look = {} }), true))
    egal('', texte({ CameraProfile = 'embedded' }, false), 'à la casse près')
    -- La balance : en kelvins pour un RAW, relative pour un autre fichier ; ses noms en français.
    egal('Balance 12' .. fine .. '000' .. fine .. 'K / ' .. moins .. '3', texte(reglagesRaw({ WhiteBalance = 'Custom', Temperature = 12000, Tint = -3 }), true))
    egal('Balance auto : 5' .. fine .. '600' .. fine .. 'K / +8', texte(reglagesRaw({ WhiteBalance = 'Auto', Temperature = 5600, Tint = 8 }), true))
    egal('Balance Lumière du jour : 5' .. fine .. '500' .. fine .. 'K / +10',
        texte(reglagesRaw({ WhiteBalance = 'Daylight', Temperature = 5500, Tint = 10 }), true))
    egal('Balance +12 / ' .. moins .. '4', texte({ WhiteBalance = 'Custom', IncrementalTemperature = 12, IncrementalTint = -4 }, false))
    egal('Balance personnalisée', texte({ WhiteBalance = 'Custom' }, true), 'sans ses valeurs')
    egal('Balance Ma lampe', texte({ WhiteBalance = 'Ma lampe' }, true), 'un nom inconnu, tel quel')
    -- Tonalité et présence : signées, l'exposition au centième ; sous le centième, rien.
    egal('Exposition ' .. moins .. '1,23 · Noirs ' .. moins .. '12 · Texture +5 · Correction du voile +8',
        texte(reglagesRaw({ Exposure2012 = -1.234, Blacks2012 = -12, Texture = 5, Dehaze = 8 }), true))
    egal('', texte(reglagesRaw({ Exposure2012 = 0.004 }), true), 'arrondie à 0')
    egal('Exposition +4', texte(reglagesRaw({ Exposure2012 = 4 }), true))
    -- Courbe, TSL (pas en noir et blanc), étalonnage (sa saturation ou sa luminance), calibrage.
    egal('Courbe des tonalités', texte(reglagesRaw({ ToneCurvePV2012 = { 0, 0, 64, 50, 255, 255 } }), true))
    egal('Courbe des tonalités', texte(reglagesRaw({ ParametricDarks = 10 }), true))
    egal('', texte(reglagesRaw({ ToneCurvePV2012 = {} }), true), 'une courbe vide')
    egal('TSL touchée', texte(reglagesRaw({ HueAdjustmentOrange = 5, LuminanceAdjustmentBlue = -10 }), true))
    egal('Noir et blanc', texte(reglagesRaw({ ConvertToGrayscale = true, HueAdjustmentOrange = 5 }), true), 'la TSL ne compte pas en noir et blanc')
    egal('Étalonnage touché', texte(reglagesRaw({ ColorGradeMidtoneSat = 10 }), true))
    egal('', texte(reglagesRaw({ SplitToningShadowHue = 200, ColorGradeBlending = 60, SplitToningBalance = 10 }), true),
        'une teinte sans saturation, le fondu, l\'équilibre : sans effet')
    egal('Calibrage touché', texte(reglagesRaw({ ShadowTint = 5 }), true))
    -- Détail, objectif, transformation, effets.
    egal('Netteté 60 · Réduction du bruit 20 · Bruit de couleur 30',
        texte(reglagesRaw({ Sharpness = 60, LuminanceSmoothing = 20, ColorNoiseReduction = 30 }), true))
    egal('Objectif : profil, aberrations chromatiques, réglages manuels',
        texte(reglagesRaw({ LensProfileEnable = 1, AutoLateralCA = 1, LensManualDistortionAmount = 5 }), true))
    egal('Transformation (Upright)', texte(reglagesRaw({ PerspectiveUpright = 1 }), true))
    egal('Transformation', texte(reglagesRaw({ PerspectiveVertical = -10 }), true))
    egal('Transformation (Upright et réglages manuels)', texte(reglagesRaw({ PerspectiveUpright = 2, PerspectiveScale = 90 }), true))
    egal('Vignetage ' .. moins .. '15 · Grain 25', texte(reglagesRaw({ PostCropVignetteAmount = -15, GrainAmount = 25 }), true))
    -- Recadrage, redressement (au dixième), masques, taches, yeux rouges, flou de l'objectif.
    egal('Recadrée · Redressée de 1,4°', texte(reglagesRaw({ CropTop = 0.1, CropAngle = -1.43 }), true))
    egal('', texte(reglagesRaw({ CropAngle = 0.02, CropRight = 0.9999 }), true), 'sous le dixième et la marge : rien')
    egal('1 masque · 5 taches · 2 yeux rouges corrigés · Flou de l\'objectif', texte(reglagesRaw({ MaskGroupBasedCorrections = { {} },
        RetouchAreas = { {}, {}, {}, {}, {} }, RedEyeInfo = { {}, {} }, LensBlur = { Active = true } }), true))
    egal('2 taches', texte({ RetouchInfo = { {}, {} } }, true), "l'ancienne forme des taches")
    -- Tout ensemble, dans l'ordre des panneaux.
    egal('Profil Camera CLASSIC CHROME · Balance 5' .. fine .. '600' .. fine .. 'K / +8 · Noir et blanc · Exposition +0,45 · Ombres +30'
        .. ' · Courbe des tonalités · Étalonnage touché · Netteté 50 · Objectif : profil · Transformation (Upright) · Vignetage '
        .. moins .. '10 · Calibrage touché · Recadrée · Redressée de 2° · 2 masques · 1 tache',
        texte(reglagesRaw({ CameraProfile = 'Camera CLASSIC CHROME', Look = {}, WhiteBalance = 'Custom', Temperature = 5600, Tint = 8,
            ConvertToGrayscale = true, Exposure2012 = 0.45, Shadows2012 = 30, ParametricLights = 5, ColorGradeGlobalSat = 4,
            Sharpness = 50, LensProfileEnable = 1, PerspectiveUpright = 1, PostCropVignetteAmount = -10, RedHue = 3, CropLeft = 0.1,
            CropAngle = 2, MaskGroupBasedCorrections = { {}, {} }, RetouchAreas = { {} } }), true))
    -- La puce.
    egal('Réglages hors des valeurs par défaut : Ombres +30 · Recadrée', Historique.texteReglages({ 'Ombres +30', 'Recadrée' }))
end)

essai("Gestionnaire : la case « Autre photo : reprendre sa conversation, sinon une nouvelle » (même clé), dite par le diagnostic ; consignes", function()
    local PluginInfoProvider = require 'PluginInfoProvider'
    local f = S.modules.LrView.osFactory()
    local sections = PluginInfoProvider.sectionsForTopOfDialog(f, S.modules.LrBinding.makePropertyTable())
    local case, etiquette
    local function parcourir(v, rangee)
        if v.genre == 'checkbox' and type(v.args.value) == 'table' and v.args.value.key == 'nouvelleParPhoto' then
            case = v
            for _, x in ipairs(rangee and rangee.args or {}) do
                if type(x) == 'table' and x.genre == 'static_text' then
                    etiquette = x.args.title
                end
            end
        end
        for _, e in ipairs(v.args or {}) do
            if type(e) == 'table' and e.genre then
                parcourir(e, v.genre == 'row' and v or rangee)
            end
        end
    end
    for _, section in ipairs(sections) do
        for _, e in ipairs(section) do
            if type(e) == 'table' and e.genre then
                parcourir(e, nil)
            end
        end
    end
    vrai(case, 'la case')
    egal('Reprendre sa conversation, sinon une nouvelle', case.args.title)
    egal('Autre photo :', etiquette)
    contient(PluginInfoProvider.diagnostic(), 'autre photo, reprendre sa conversation, sinon une nouvelle : true')
    -- La consigne dit à Claude ce que sont ces lignes ; le texte reste sous son plafond.
    contient(Consignes.texte, '« [Historique de la photo : …] », « [Depuis la dernière fois : …] »')
    vrai(Texte.longueur(Consignes.texte) <= 7500, 'plafond des consignes : ' .. Texte.longueur(Consignes.texte))
    -- Plus de Renommer ni de Supprimer : une conversation n'est jamais effacée.
    egal(nil, Conversation.renommer)
    egal(nil, Moteur.renommer)
    egal(nil, Moteur.supprimer)
    egal(nil, Stockage.supprimer)
    egal(nil, Lightroom.photo)
end)

print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
