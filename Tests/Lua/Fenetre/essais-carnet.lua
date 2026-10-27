-- essais-carnet.lua : le carnet de progrès, hors de Lightroom (LuaJIT, Lightroom simulé par
-- Simulation.lua) : la fenêtre Suivi (FenetreSuivi.lua, correctif 1.3.6 : d'abord l'onglet Suivi, à
-- la place de Leçon, puis une fenêtre à part le 25 octobre 2026, ouverte par le bouton Suivi de
-- l'en-tête de la fenêtre Claude ; la page Carnet de progrès du fil, son entrée dans la liste des
-- conversations et sa ligne « Demander à Claude ce qu'il en pense › » sont retirées avec le volet ;
-- son texte, Fil.texteSuivi, est remplacé par des graphiques au correctif 1.3.7, éprouvés par
-- essais-suivi.lua) : le bouton Suivi (plus d'onglet, ni de carte), la fenêtre Suivi sans
-- « Photos d'un défaut… » ni sa fenêtre des photos d'un défaut, ni « Retirer du carnet… » (retirés
-- au correctif 1.3.8, demandé par Dany le 26 octobre 2026 : la fenêtre ne lit plus le résumé du
-- carnet), et la puce Carnet des consignes. Le registre est le vrai (Carnet.lua), rangé dans un
-- dossier personnel temporaire ; ni Claude, ni quota.
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

-- La première vue de ce genre dans un arbre.
local function vueDe(contenu, genre)
    for _, v in ipairs(vues(contenu)) do
        if v.genre == genre then
            return v
        end
    end
    return nil
end

-- Lance les tâches parties depuis `depuis` (et celles qu'elles lancent), dans l'ordre.
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

-- Lance la seule tâche `i` : après un envoi à Claude Code, la boucle de lecture du moteur
-- (Moteur.demarrerBoucle) attend dans les tâches et ne doit pas tourner ici (Moteur.tic la remplace).
local function lancerTache(i)
    local t = S.taches[i]
    vrai(t, 'tâche ' .. tostring(i))
    S.taches[i] = function() end
    t()
end

-- Oublie les tâches parties depuis `depuis` sans les lancer.
local function oublierTaches(depuis)
    for i = depuis + 1, #S.taches do
        S.taches[i] = function() end
    end
end

local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Consignes = require 'Consignes'
local Conversation = require 'Conversation'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Fil = require 'Fil'
local Json = require 'Json'
local Notation = require 'Notation'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local FenetreSuivi = require 'FenetreSuivi'
local Moteur = require 'Moteur'
local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false

-- Complément de la simulation, pour cet essai : le chemin du catalogue ouvert (le carnet range
-- chaque catalogue sous le sien ; sans lui, il se lit vide).
local CATALOGUE = '/Users/test/Images/Catalogue.lrcat'
S.catalogue.getPath = function() return CATALOGUE end

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai).
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'

local D = Dispositions.dimensions()

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

-- Un clic sur un segment des onglets (son calque, dont l'infobulle est le titre de l'onglet), comme
-- Dany (S.cliquer, puis Fenetre.choisirSegment).
local function segment(titre)
    for _, v in ipairs(S.vues(S.fenetre.contents)) do
        if v.genre == 'static_text' and v.args.tooltip == titre and Fenetre.parCalque(v.args.mouse_down) then
            return S.cliquer(v)
        end
    end
    error('segment introuvable : ' .. titre, 2)
end

-- Un tour de la boucle de la fenêtre Suivi (FenetreSuivi.boucle), sans attendre : la pause de la fin
-- du tour l'arrête.
local function unTourDeBoucle()
    local LrTasks = S.modules.LrTasks
    local sleep, generation = LrTasks.sleep, FenetreSuivi.generation
    LrTasks.sleep = function() FenetreSuivi.generation = generation + 1000 end
    local ok, erreur = pcall(FenetreSuivi.boucle, generation)
    LrTasks.sleep = sleep
    FenetreSuivi.generation = generation
    vrai(ok, erreur)
end

-- Ouvre la fenêtre Suivi et appelle fn(p, args) pendant qu'elle est ouverte (sa boucle, partie dans
-- une tâche, ne tourne pas : unTourDeBoucle) ; une erreur de fn remonte une fois la fenêtre fermée.
local function ouvrirSuivi(fn)
    local erreur
    local taches = #S.taches
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function() fn(FenetreSuivi.p, args, taches) end, debug.traceback)
        erreur = not ok and e or nil
    end
    FenetreSuivi.afficher()
    S.pendantFenetre = nil
    oublierTaches(taches)
    if erreur then
        error(erreur, 0)
    end
end

-- Le bouton de ce titre dans un arbre.
local function boutonDe(contenu, titre)
    for _, v in ipairs(vues(contenu)) do
        if S.BOUTONS[v.genre] and v.args.title == titre then
            return v
        end
    end
    return nil
end

-- Une conversation qui a des messages, en tête de la liste (son titre posé comme un titre choisi
-- d'avant le correctif 1.3.6 : plus de Renommer…).
local function conversation(titre)
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, titre)
    c.titre, c.titreChoisi = titre, true
    table.insert(Moteur.conversations, 1, c)
    return c
end

-- Le registre ---------------------------------------------------------------------------------------

-- Le vocabulaire comme le connecteur l'envoie (PriseDeVue.vocabulaire) : les six défauts mesurés
-- et un autre, dans l'ordre de PriseDeVue.defauts.
local VOCABULAIRE = {
    { code = 'horizon_penche', cle = 'tilted_horizon', axe = 'composition', domaine = 'composition',
        libelle = "Horizon ou ligne penchée",
        conseil = "Afficher le niveau électronique ou la grille du viseur, et caler l'horizon dessus avant de déclencher.",
        mesure = true },
    { code = 'sous_exposition', cle = 'underexposed', axe = 'lumiere', domaine = 'lumiere', libelle = "Photo sous-exposée",
        conseil = "Monter la compensation d'exposition (+1/3 à +1 IL) en suivant l'histogramme, sans brûler les hautes lumières.",
        mesure = true },
    { code = 'ciel_brule', cle = 'blown_highlights', axe = 'lumiere', domaine = 'lumiere', libelle = "Ciel ou haut de l'image brûlé",
        conseil = "Exposer pour le ciel (compensation négative, alerte de surexposition du viseur) ; sur un Fujifilm, DR200 ou DR400 aide.",
        mesure = true },
    { code = 'bruit', cle = 'noise', axe = 'lumiere', domaine = 'nettete', libelle = "Bruit fort (ISO élevé)",
        conseil = "Garder l'ISO plus bas : un appui ou la stabilisation pour une vitesse plus lente, une ouverture plus grande.",
        mesure = true },
    { code = 'flou', cle = 'blur', axe = 'lumiere', domaine = 'nettete', libelle = "Photo floue ou bougée",
        conseil = "Une vitesse d'au moins 1/(2 × focale), la stabilisation et l'appareil tenu ferme ; plus vite pour un sujet qui bouge.",
        mesure = true },
    { code = 'mise_au_point', cle = 'missed_focus', axe = 'lumiere', domaine = 'nettete', libelle = "Mise au point à côté",
        conseil = "Un seul collimateur, posé sur le sujet (les yeux d'un portrait), et l'AF continu (AF-C) s'il bouge.",
        mesure = true },
    { code = 'dominante', cle = 'color_cast', axe = 'couleur', domaine = 'couleur', libelle = "Dominante de couleur",
        conseil = "Régler la balance des blancs selon la lumière, ou la mesurer sur un gris ; en RAW, elle se rattrape sans perte.",
        mesure = false },
}

local CHERCHES = { 'horizon_penche', 'sous_exposition', 'ciel_brule', 'flou', 'bruit' }
local CONSTATS = {
    ciel_brule = { mesure = 4.2, texte = "ciel brûlé : 4,2 % du tiers haut en blanc pur" },
    flou = { mesure = 9, texte = "netteté maximale 9 (floue sous 15)" },
    -- Une mesure sans texte : la fenêtre la dit telle quelle.
    mise_au_point = { mesure = 8.5 },
}

-- 'AAAA-MM', `k` mois avant le mois courant (le résumé ne compte pas les mois à venir).
local function moisIl(k)
    local t = os.date('*t')
    local a, m = t.year, t.month - k
    while m < 1 do
        m, a = m + 12, a - 1
    end
    return string.format('%04d-%02d', a, m)
end

-- Une entrée du carnet : une vue au mois `prise`, qui cherche `cherches` et trouve `trouves`.
local function entree(id, prise, cherches, trouves, plus)
    local defauts = {}
    for _, code in ipairs(trouves or {}) do
        local c = CONSTATS[code] or {}
        defauts[#defauts + 1] = { code = code, mesure = c.mesure, texte = c.texte }
    end
    local e = { photo = id, uuid = 'uuid-' .. id, fichier = string.format('DSCF%04d.RAF', id), prise = prise, le = id,
        vue = { le = id, photo = id, cherches = cherches, defauts = defauts } }
    for cle, valeur in pairs(plus or {}) do
        e[cle] = valeur
    end
    return e
end

-- Écrit carnet.json (le vrai registre le relit) : les entrées de ce catalogue.
local function fabriquer(entrees)
    local photos = {}
    for _, e in ipairs(entrees) do
        photos[tostring(e.photo)] = e
    end
    Fichiers.ecrire(Carnet.fichier(), Json.encode({ format = 1, vocabulaire = VOCABULAIRE,
        catalogues = { [CATALOGUE] = { photos = photos } } }))
    Carnet.oublier()
end

-- La leçon rangée avec la photo 1024 avant le correctif 1.3.6 (axes du module : lumiere, couleur,
-- composition), qui reste dans carnet.json sans plus être montrée.
local LECON_1024 = { photo = 1024, uuid = 'uuid-1024', fichier = 'DSCF1024.RAF', le = 5, defauts = {}, indices = {}, points = {
    { axe = 'lumiere', manque = "Ciel brûlé à 4 %.", prise_de_vue = "Exposer pour le ciel." },
    { axe = 'couleur', prise_de_vue = "Balance des blancs juste : à refaire." },
    { axe = 'composition', manque = "Horizon un peu bas.", prise_de_vue = "Horizon au tiers haut." },
} }

-- Six mois de prise de vue : le flou recule (4 photos sur 6 avant, aucune sur les 6 récentes : il
-- progresse), le ciel brûlé revient (3 sur 6 récentes, aucune avant : il recule, et il est à
-- travailler) ; une mise au point manquée seule, cinq mois plus tôt ; une ligne penchée (angle)
-- avant et une ce mois-ci (sans tendance) ; la photo 1025 mesurée sur sa copie virtuelle (5025) ;
-- une leçon d'avant pour 1024.
local function fabriquerType()
    local entrees = {
        entree(1001, moisIl(5), { 'horizon_penche', 'sous_exposition', 'ciel_brule', 'flou', 'bruit', 'mise_au_point' }, { 'mise_au_point' }),
        entree(1011, moisIl(4), CHERCHES, { 'flou' }),
        entree(1012, moisIl(4), CHERCHES, { 'flou' }),
        entree(1013, moisIl(3), CHERCHES, { 'flou' }),
        entree(1014, moisIl(3), CHERCHES, {}, { angle = { le = 1014, photo = 1014, inclinaison = 0.8, code = 'horizon_penche',
            source = 'read_composition' } }),
        entree(1015, moisIl(2), CHERCHES, { 'flou' }),
        entree(1016, moisIl(2), CHERCHES, {}),
        entree(1021, moisIl(1), CHERCHES, { 'ciel_brule' }),
        entree(1022, moisIl(1), CHERCHES, {}),
        entree(1023, moisIl(1), CHERCHES, {}),
        entree(1024, moisIl(0), CHERCHES, { 'ciel_brule' }, { lecons = { ['1024'] = LECON_1024 } }),
        entree(1025, moisIl(0), CHERCHES, { 'ciel_brule' }),
        entree(1026, moisIl(0), CHERCHES, {}, { angle = { le = 1026, photo = 1026, inclinaison = 1.2, code = 'horizon_penche',
            source = 'measure_angle' } }),
    }
    entrees[12].vue.photo = 5025
    fabriquer(entrees)
end

Moteur.charger()

-- Plus de page du carnet dans le fil ------------------------------------------------------------

essai("Plus de page Carnet de progrès dans le fil, ni d'entrée dans une liste, ni « Demander à Claude ce qu'il en pense › » (correctif 1.3.6)", function()
    for _, nom in ipairs({ 'vue', 'CARNET', 'SOUS_TITRE_CARNET', 'CHOISIR_CONVERSATION', 'ouvrirCarnet', 'quitterCarnet', 'lireCarnet',
        'revenirAuFil', 'demanderCarnet', 'TITRE_DEMANDE_CARNET', 'elementsListe', 'casesListe', 'rafraichirListe', 'choixListe',
        'cliquerListe', 'choisirDansListe', 'renommer', 'supprimer', 'pageCarnet' }) do
        egal(nil, Fenetre[nom], 'Fenetre.' .. nom .. ' retiré')
    end
    for _, nom in ipairs({ 'lignesCarnet', 'lignesCarnetBrutes', 'tableauCarnet', 'DEMANDER_CARNET', 'AIDE_TABLEAU_CARNET' }) do
        egal(nil, Fil[nom], 'Fil.' .. nom .. ' retiré')
    end
    egal(nil, Consignes.carnet, 'la demande de sa ligne d\'action, retirée avec elle')
    egal(nil, Fenetre.clics.carnet, 'plus de clic du carnet dans le fil')
    -- Une ligne qui porterait un défaut ou une action (comme celles de la page) n'est qu'une ligne.
    egal(nil, Fenetre.sorteDeClic({ genre = 'outil', texte = 'x', defaut = 'flou' }, nil))
    egal(nil, Fenetre.sorteDeClic({ genre = 'apercu', texte = 'y', action = 'demander' }, nil))
    egal(nil, FenetreSuivi.TITRE_CARNET, "le titre du carnet partait avec « Photos d'un défaut… » (correctif 1.3.8)")
end)

-- Le bouton Suivi et la fenêtre Suivi ---------------------------------------------------------------

essai("Bouton Suivi : en haut à droite, sur la rangée du titre après « Repartir à neuf » (correctif 1.3.8), il ouvre la fenêtre Suivi sans envoyer la demande ; plus d'onglet Suivi, ni sa carte, ni sa lecture dans la fenêtre Claude", function()
    -- Plus d'onglet Suivi (décision de Dany du 25 octobre 2026) : ni segment, ni carte, ni crochet.
    for _, o in ipairs(D.onglets) do
        vrai(o.valeur ~= 'suivi' and o.image ~= 'seg-suivi', "plus d'onglet Suivi")
    end
    egal(nil, D.ongletSuivi)
    egal(nil, D.suiviLignes)
    egal(nil, Dispositions.IMAGES['carte-suivi'])
    egal(nil, Fenetre.CARTES.suivi)
    egal(nil, Fenetre.surOnglet.suivi)
    for _, nom in ipairs({ 'suiviMontre', 'rafraichirSuivi', 'lireSuivi', 'suivreSuivi', 'choisirDefaut', 'montrerDefaut',
        'retirerDuCarnet', 'TITRE_CARNET', 'pageSuivi' }) do
        egal(nil, Fenetre[nom], 'Fenetre.' .. nom .. ' : dans la fenêtre Suivi')
    end
    fabriquerType()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.courante = conversation('Lac au matin')
    local afficher, ouvertures = FenetreSuivi.afficher, 0
    FenetreSuivi.afficher = function() ouvertures = ouvertures + 1 end
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        for _, v in ipairs(vues(args.contents)) do
            local t = v.args.title
            vrai(not (v.genre == 'static_text' and type(t) == 'table' and (t.key == 'suiviTexte' or t.key == 'suiviTitre')),
                'plus de carte Suivi')
        end
        egal(nil, p.suiviTexte)
        egal(nil, Carnet.observateurs.fenetre, "la fenêtre Claude ne suit plus le carnet")
        -- Le bouton : un carré small, en haut à droite, sur la rangée du titre (correctif 1.3.8 ; dans
        -- la rangée des voyants, après la photo active, avant lui).
        local bouton = boutonDe(args.contents, 'Suivi')
        vrai(bouton, 'le bouton Suivi')
        egal('square_button', bouton.genre)
        egal('small', bouton.args.size)
        egal(Fenetre.POLICES.petit, bouton.args.font)
        egal(D.boutonSuivi, bouton.args.width)
        vrai(D.boutonSuivi >= Fenetre.largeurLibelle('Suivi', 'petit') + 20, 'son titre et le jeu du carré')
        vrai(Fenetre.parBouton(bouton.args.action), 'passe par Fenetre.bouton')
        vrai(S.montreeDansFenetre(bouton), 'montré')
        local rangee
        for _, v in ipairs(vues(args.contents)) do
            if v.genre == 'row' then
                for _, enfant in ipairs(v.args) do
                    if enfant == bouton then
                        rangee = v
                    end
                end
            end
        end
        vrai(rangee, 'la rangée du bouton')
        local voyant, info, indiceBouton
        for k, enfant in ipairs(rangee.args) do
            if enfant == bouton then
                indiceBouton = k
            elseif type(enfant) == 'table' and enfant.genre == 'row' and type(enfant.args[2]) == 'table'
                and type(enfant.args[2].args.title) == 'table' and enfant.args[2].args.title.key == 'texteLightroom' then
                voyant = k
            elseif type(enfant) == 'table' and enfant.genre == 'static_text' and type(enfant.args.title) == 'table'
                and enfant.args.title.key == 'infoPhoto' then
                info = k
            end
        end
        -- Sur la rangée du titre depuis le correctif 1.3.8 (demandé par Dany le 26 octobre 2026) : après
        -- « Repartir à neuf » et son écart, avant Publication… et Consommation… (essais-fenetre-b.lua).
        egal(nil, voyant, 'plus dans la rangée des voyants')
        egal(nil, info)
        egal('Repartir à neuf', rangee.args[indiceBouton - 2].args.title, 'après « Repartir à neuf »')
        vrai(indiceBouton == #rangee.args - 4, 'avant Publication… et Consommation…')
        -- Un clic après une frappe sans Retour : la fenêtre Suivi s'ouvre, la demande tapée ne part pas.
        local champ
        for _, v in ipairs(vues(args.contents)) do
            if v.genre == 'edit_field' and type(v.args.value) == 'table' and v.args.value.key == 'saisie' then
                champ = v
            end
        end
        S.taper(champ, 'Texte validé par le clic')
        S.cliquer(bouton)
        egal(1, ouvertures, 'la fenêtre Suivi')
        egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande")
        p.saisie = ''
    end)
    FenetreSuivi.afficher = afficher
    assert(ok, erreur)
end)

essai("Fenêtre Suivi : « Claude · Suivi » ; plus de « Photos d'un défaut… », ni sa liste, ni la fenêtre des photos d'un défaut, ni « Retirer du carnet… » (correctif 1.3.8) : elle ne lit plus le résumé du carnet et ne s'abonne pas au registre ; déjà ouverte, elle passe devant", function()
    fabriquerType()
    local devant = S.devant or 0
    local resumer, lus = Carnet.resumer, 0
    Carnet.resumer = function(...)
        lus = lus + 1
        return resumer(...)
    end
    local ok, erreur = pcall(ouvrirSuivi, function(p, args, taches)
        egal(FenetreSuivi.TITRE, args.title)
        egal('Claude · Suivi', args.title)
        egal(FenetreSuivi.CADRE, args.save_frame, "son cadre, ni celui de la fenêtre de la liaison (DeveloppeurSuivi) ni celui de la 1.3.6")
        vrai(args.save_frame ~= 'DeveloppeurCarnet' and args.save_frame ~= 'DeveloppeurSuivi', args.save_frame)
        -- Plus de page du résumé en texte (correctif 1.3.7 : des graphiques), ni ▲ ▼.
        egal(nil, p.texte)
        egal(nil, p.monte)
        egal(nil, FenetreSuivi.LIGNES)
        egal(nil, Fil.texteSuivi, 'le texte du carnet retiré de Fil')
        egal(nil, Fil.LECTURE_CARNET)
        egal(nil, boutonDe(args.contents, '▼'))
        -- Ni le bouton, ni ce qui le servait (correctif 1.3.8).
        egal(nil, boutonDe(args.contents, "Photos d'un défaut…"), "plus de « Photos d'un défaut… »")
        egal(nil, p.aDefauts)
        for _, nom in ipairs({ 'choisirDefaut', 'montrerDefaut', 'retirerDuCarnet', 'textePhotoDuDefaut', 'nomPhotoCarnet', 'aDefauts',
            'lire', 'resume', 'versionLue', 'TITRE_DEFAUTS' }) do
            egal(nil, FenetreSuivi[nom], 'FenetreSuivi.' .. nom .. ' retiré')
        end
        egal(nil, Carnet.photosDuDefaut, 'Carnet.photosDuDefaut retiré avec elle')
        vrai(#S.taches > taches, 'la boucle dans une tâche')
        egal(nil, Carnet.observateurs.suivi, "pas d'abonnement au registre : les graphiques suivent Carnet.version")
        local dialogues = #S.dialogues
        unTourDeBoucle()
        Carnet.commande({ action = 'retirer', photos = { 1001 } })
        unTourDeBoucle()
        egal(0, lus, 'le résumé du carnet ne se lit plus')
        egal(dialogues, #S.dialogues, 'aucune fenêtre ouverte')
        -- Déjà ouverte : le bouton Suivi la remet devant, sans en ouvrir une autre.
        FenetreSuivi.afficher()
        egal(devant + 1, S.devant, 'devant')
    end)
    Carnet.resumer = resumer
    assert(ok, erreur)
    egal(false, FenetreSuivi.ouverte)
end)

-- Consignes ----------------------------------------------------------------------------------------

essai('Consignes : puce Carnet des garde-fous (250 caractères au plus) ; le texte reste sous 7 500', function()
    local texte = Consignes.texte
    local debut = texte:find('\n## Garde-fous\n', 1, true)
    local fin = texte:find('\n## ', debut + 1, true)
    local gardeFous = texte:sub(debut, fin)
    local puce = gardeFous:match('\n(%- Carnet de progrès : [^\n]*)\n')
    vrai(puce, 'puce Carnet dans les garde-fous')
    vrai(Texte.longueur(puce) <= 250, string.format('puce : %d caractères pour 250', Texte.longueur(puce)))
    for _, morceau in ipairs({ "s'y notent seuls", 'constats_prise_de_vue', 'Si Dany demande ses progrès', 'export_journal avec notebook = true',
        'trois puces', 'ce qui progresse', 'ce qui revient', 'prochaine sortie' }) do
        contient(puce, morceau, 'puce Carnet')
    end
    vrai(not texte:find('\\\n', 1, true), 'lignes recollées')
    vrai(Texte.longueur(texte) <= 7500, string.format('plafond des consignes : %d', Texte.longueur(texte)))
end)

-- Fin ----------------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
S.executer('sleep 1.5')
Notation.proposition = propositionVraie
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
