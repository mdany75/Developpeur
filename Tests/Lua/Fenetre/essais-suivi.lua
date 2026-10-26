-- essais-suivi.lua : la fenêtre Suivi en graphiques (correctif 1.3.7, FenetreSuivi.lua), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua), d'après le contrat figé
-- (Tests/Contrats/suivi.json) : sa construction (structure fixe : huit images liées, les notes à côté
-- des objectifs, 76 calques posés sur les créneaux du contrat, champs « Du » et « au », menu du défaut
-- suivi, tuiles, aplats aux couleurs de l'apparence ; plus de « Photos d'un défaut… »), l'entrée
-- envoyée à `mcp-developpeur --graphiques` (exactement celle des exemples du contrat), sa sortie
-- montrée (tuiles, titres, notes, images, calques visibles sur les barres qui ont des photos,
-- infobulles), la période (les dates tapées, lues, gardées d'une ouverture à l'autre ; correctif
-- 1.3.8) et le défaut choisis, un clic sur une barre (ses photos
-- dans la Bibliothèque, l'uuid vérifié, Toutes les photographies comme source au besoin, rien
-- d'écrit), un relevé vide (le texte d'accueil), un connecteur absent, muet ou qui refuse (le
-- message, les images d'avant gardées), le relevé ou le carnet changé pendant qu'elle est ouverte,
-- ses dossiers effacés, et les boutons Suivi, Publication… et Consommation… de l'en-tête de la
-- fenêtre Claude. Le connecteur est imité par un faux `mcp-developpeur --graphiques` (un script
-- LuaJIT écrit ici), qui lit le contrat et rend la sortie de l'exemple de la période demandée (les
-- graphiques qu'un exemple partiel omet viennent de celui d'un an, comme le contrat le dit), avec
-- de vraies images PNG. Ni Lightroom, ni Claude, ni vraies photos ; les fichiers vont dans un
-- dossier personnel temporaire.
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

-- Deux valeurs JSON égales (noms, formes, valeurs, ordre des tableaux).
local function memes(attendu, obtenu, chemin)
    chemin = chemin or 'valeur'
    if type(attendu) ~= type(obtenu) then
        error(string.format('%s : attendu %s, obtenu %s', chemin, type(attendu), type(obtenu)), 2)
    end
    if type(attendu) ~= 'table' then
        if attendu ~= obtenu then
            error(string.format('%s : attendu %q, obtenu %q', chemin, tostring(attendu), tostring(obtenu)), 2)
        end
        return
    end
    for cle, v in pairs(attendu) do
        memes(v, obtenu[cle], chemin .. '.' .. tostring(cle))
    end
    for cle in pairs(obtenu) do
        if attendu[cle] == nil then
            error(string.format('%s.%s : en trop (%s)', chemin, tostring(cle), tostring(obtenu[cle])), 2)
        end
    end
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

local function oublierTaches(depuis)
    for i = depuis + 1, #S.taches do
        S.taches[i] = function() end
    end
end

local Carnet = require 'Carnet'
local Chemins = require 'Chemins'
local Dispositions = require 'Dispositions'
local Fichiers = require 'Fichiers'
local Journal = require 'Journal'
local Json = require 'Json'
local Notation = require 'Notation'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
local FenetreSuivi = require 'FenetreSuivi'
local Moteur = require 'Moteur'
local Releve = require 'Releve'

-- La boucle de la fenêtre Claude et ses voyants ne sont pas de cet essai.
Fenetre.boucle = function() end
Fenetre.verifier = function() end

local prefs = Chemins.prefs()
prefs.nouvelleParPhoto = false
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
local CONTRAT_CHEMIN = dossierTests .. '/../../Contrats/suivi.json'

-- Le contrat, sans ses commentaires (_note, _lisez_moi).
local function sansNotes(v)
    if type(v) ~= 'table' then
        return v
    end
    local t = {}
    for cle, element in pairs(v) do
        if cle ~= '_note' and cle ~= '_lisez_moi' then
            t[cle] = sansNotes(element)
        end
    end
    return setmetatable(t, getmetatable(v))
end
local CONTRAT = sansNotes(Json.decode(assert(Fichiers.lire(CONTRAT_CHEMIN), 'contrat suivi.json')))
local EXEMPLES = CONTRAT.exemples
local REGISTRE = EXEMPLES.registre.fichier
local CATALOGUE = next(REGISTRE.catalogues)
local AUJOURDHUI = EXEMPLES.graphiques_un_an.entree.fin

S.catalogue.getPath = function() return CATALOGUE end
FenetreSuivi.aujourdhui = function() return AUJOURDHUI end

-- La sortie que le faux connecteur rend pour un exemple : la sienne, les graphiques qu'un exemple
-- partiel omet pris dans celui d'un an (le contrat : « les graphiques omis suivent les mêmes
-- règles »), leurs fichiers dans `dossier`.
local function sortieAttendue(exemple, dossier)
    local sortie = sansNotes(Json.decode(Json.encode(EXEMPLES[exemple].sortie)))
    for cle, g in pairs(EXEMPLES.graphiques_un_an.sortie.graphiques) do
        if sortie.graphiques[cle] == nil then
            sortie.graphiques[cle] = sansNotes(Json.decode(Json.encode(g)))
        end
    end
    for cle, g in pairs(sortie.graphiques) do
        g.fichier = (dossier or '<dossier>') .. '/' .. cle .. '.png'
    end
    return sortie
end

-- Le journal : une erreur que la fenêtre y note se lit dans l'essai.
local journal = {}
local noterVraiment = Journal.noter
Journal.noter = function(...)
    local t = {}
    for i = 1, select('#', ...) do
        t[i] = tostring((select(i, ...)))
    end
    journal[#journal + 1] = table.concat(t, ' ')
    return noterVraiment(...)
end

-- Le faux connecteur ----------------------------------------------------------------------------

-- `mcp-developpeur --graphiques '<json>' <dossier>` : note l'entrée et le dossier reçus (une ligne
-- par appel), puis répond d'après son mode (fichier faux-mode) : « contrat » (la sortie de l'exemple
-- de la période, ses PNG écrits dans le dossier), « vide » (de même, sans aucune photo), « decale »
-- (les créneaux des focales décalés d'un point), « muet » (rien : l'alarme, ou un vieux connecteur),
-- « refus » (ok faux, code 1).
local CONNECTEUR = S.home .. '/bin/mcp-developpeur'
local RECUS = S.home .. '/graphiques-recus.txt'
local MODE = S.home .. '/faux-mode'
local PNG = S.plugin .. '/' .. Dispositions.imageVide('claire')
do
    local luajit = S.lireCommande('command -v luajit'):gsub('%s+$', '')
    local script = S.home .. '/bin/faux-graphiques.lua'
    Fichiers.ecrire(script, string.format([==[
package.path = %q .. '/?.lua;' .. package.path
local Json = require 'Json'
local function lire(chemin)
    local f = io.open(chemin, 'rb')
    if not f then return nil end
    local t = f:read('*a')
    f:close()
    return t
end
local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
if arg[1] ~= '--graphiques' or #arg ~= 3 then
    io.stderr:write('usage : mcp-developpeur --graphiques <json> <dossier>\n')
    os.exit(2)
end
local recus = io.open(%q, 'ab')
recus:write(Json.encode({ entree = Json.decode(arg[2]), dossier = arg[3] }), '\n')
recus:close()
local mode = (lire(%q) or 'contrat'):gsub('%%s+$', '')
if mode == 'muet' then os.exit(0) end
if mode == 'refus' then
    print(Json.encode({ ok = false, raison = 'defaut_inconnu', texte = "« dominante » n'est pas un défaut que le Suivi compte." }))
    os.exit(1)
end
local entree = Json.decode(arg[2])
local dossier = arg[3]
local contrat = Json.decode(lire(%q))
-- L'exemple de la période demandée : celui qui a ce début (ou aucun) et cette fin ; sinon celui d'un an.
local sortie = contrat.exemples.graphiques_un_an.sortie
for nom, x in pairs(contrat.exemples) do
    if nom:match('^graphiques_') and type(x.entree) == 'table' and x.entree.debut == entree.debut and x.entree.fin == entree.fin then
        sortie = x.sortie
    end
end
for cle, g in pairs(contrat.exemples.graphiques_un_an.sortie.graphiques) do
    if sortie.graphiques[cle] == nil then sortie.graphiques[cle] = g end
end
if mode == 'vide' then
    sortie.photos, sortie.sans_date = 0, 0
    sortie.analyse = { analysees = 0, en_attente = 0, en_echec = 0 }
    for _, t in ipairs(sortie.tuiles) do
        t.valeur, t.texte, t.code = 0, t.cle == 'defaut_frequent' and '—' or '0', nil
        t.detail = t.cle == 'photos_ouvertes' and "aucune photo ouverte dans la période" or t.cle == 'defaut_frequent'
            and "aucune photo analysée" or "—"
    end
    for _, d in ipairs(sortie.defauts) do d.n, d.sur, d.valeur, d.texte = 0, 0, 0, '—' end
    sortie.defaut_suivi = nil
    for _, g in pairs(sortie.graphiques) do
        g.vide, g.echelle, g.sans_valeur = true, 0, 0
        for _, b in ipairs(g.barres) do b.n, b.valeur, b.texte, b.ids = 0, 0, '0', Json.tableau() end
    end
end
if mode == 'decale' then
    for _, c in ipairs(sortie.graphiques.focales.creneaux) do c.x = c.x + 1 end
end
os.execute('mkdir -p ' .. q(dossier))
for cle, g in pairs(sortie.graphiques) do
    g.fichier = dossier .. '/' .. cle .. '.png'
    os.execute('cp ' .. q(%q) .. ' ' .. q(g.fichier))
end
print(Json.encode(sortie))
]==], S.plugin, RECUS, MODE, CONTRAT_CHEMIN, PNG))
    Fichiers.ecrire(CONNECTEUR, string.format('#!/bin/sh\nexec %s %s "$@"\n', S.q(luajit), S.q(script)))
    S.executer('chmod +x ' .. S.q(CONNECTEUR))
end

local function mode(m)
    Fichiers.ecrire(MODE, m)
end

-- Les appels reçus par le faux connecteur, décodés : { entree, dossier }.
local function recus()
    local liste = {}
    for ligne in (Fichiers.lire(RECUS) or ''):gmatch('[^\n]+') do
        liste[#liste + 1] = Json.decode(ligne)
    end
    return liste
end

-- L'entrée d'un exemple du contrat, ses textes à remplacer posés.
local function entreeAttendue(exemple)
    local e = sansNotes(Json.decode(Json.encode(EXEMPLES[exemple].entree)))
    e.suivi, e.carnet = Releve.fichier(), Carnet.fichier()
    return e
end

-- Le relevé de l'exemple du contrat, rangé dans suivi.json (Releve.lua le relit).
local function ecrireReleve()
    Fichiers.ecrire(Releve.fichier(), Json.encode(REGISTRE))
    Releve.oublier()
end

-- Releve.reclasser, compté (la note, le drapeau et « retouchée par Claude » se relisent à
-- l'ouverture, avant --graphiques) : il n'écrit rien ici.
local reclassements = {}
Releve.reclasser = function()
    reclassements[#reclassements + 1] = #recus()
    return 0
end

-- Un départ neuf : le relevé du contrat, le faux connecteur au mode du contrat, l'apparence claire.
local function depart(apparence)
    Fichiers.supprimer(RECUS)
    ecrireReleve()
    mode('contrat')
    prefs.cheminConnecteur = CONNECTEUR
    prefs.apparence = apparence or 'claire'
    -- Aucune période gardée : les douze derniers mois, du 1er du mois onze mois plus tôt à aujourd'hui.
    prefs.suiviDebut, prefs.suiviFin = nil, nil
    Releve.allume = false
    reclassements = {}
    journal = {}
    FenetreSuivi.DELAI_REDESSIN = 10
end

-- Un tour de la boucle de la fenêtre Suivi (FenetreSuivi.boucle), sans attendre : la pause de la fin
-- du tour l'arrête.
local function unTour()
    local LrTasks = S.modules.LrTasks
    local sleep, generation = LrTasks.sleep, FenetreSuivi.generation
    LrTasks.sleep = function() FenetreSuivi.generation = generation + 1000 end
    local ok, erreur = pcall(FenetreSuivi.boucle, generation)
    LrTasks.sleep = sleep
    FenetreSuivi.generation = generation
    vrai(ok, erreur)
end

-- Une date validée dans « Du » ('debut') ou « au » ('fin') : Lightroom pose le texte du champ dans
-- la table (Retour, ou le champ quitté), et son observateur le lit.
local function taperDate(p, borne, texte)
    p[borne == 'debut' and 'debutTexte' or 'finTexte'] = texte
end

-- Ouvre la fenêtre Suivi et appelle fn(p, args, taches) pendant qu'elle est ouverte ; une erreur de
-- fn remonte une fois la fenêtre fermée.
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

-- Les vues de la fenêtre, et leurs parents.
local function parents(contenu)
    local liste, parent = {}, {}
    local function parcourir(v, p)
        liste[#liste + 1] = v
        parent[v] = p
        for _, e in ipairs(v.args or {}) do
            if type(e) == 'table' and e.genre then
                parcourir(e, v)
            end
        end
    end
    parcourir(contenu, nil)
    return liste, parent
end

-- Les calques de la fenêtre, par graphique : calques[cle][i] = { vue, colonne }.
local function calquesDe(contenu)
    local liste, parent = parents(contenu)
    local calques, n = {}, 0
    for _, v in ipairs(liste) do
        if v.genre == 'static_text' and FenetreSuivi.parCalque(v.args.mouse_down) then
            n = n + 1
            local cle, i = v.args.visible.key:match('^c_(.+)_(%d+)$')
            vrai(cle, 'calque sans clé de visibilité : ' .. tostring(v.args.visible.key))
            calques[cle] = calques[cle] or {}
            calques[cle][tonumber(i)] = { vue = v, colonne = parent[v] }
        end
    end
    return calques, n
end

-- La première vue de ce genre liée à cette clé (title, value ou items).
local function liee(contenu, genre, cle)
    for _, v in ipairs((parents(contenu))) do
        if v.genre == genre then
            for _, attribut in ipairs({ 'title', 'value', 'items' }) do
                local x = v.args[attribut]
                if type(x) == 'table' and x.liaison and x.key == cle then
                    return v
                end
            end
        end
    end
    error('vue introuvable : ' .. genre .. ' liée à ' .. cle, 2)
end

local function bouton(contenu, titre)
    for _, v in ipairs((parents(contenu))) do
        if S.BOUTONS[v.genre] and v.args.title == titre then
            return v
        end
    end
    return nil
end

-- Chaque calque d'après la sortie : visible sur une barre qui a des photos, son infobulle le détail
-- de la barre.
local function verifierCalques(p, sortie)
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        local rendu = sortie.graphiques[g.cle]
        for i = 1, g.max_barres do
            local visible, infobulle = FenetreSuivi.cleCalque(g.cle, i)
            local rang = rendu.creneaux[i].barre
            local barre = rang > 0 and rendu.barres[rang] or nil
            local actif = barre ~= nil and #barre.ids > 0
            egal(actif, p[visible], g.cle .. ' ' .. i .. ' : visible')
            egal(actif and (barre.detail .. '\n' .. FenetreSuivi.INFOBULLE_BARRE) or '', p[infobulle], g.cle .. ' ' .. i .. ' : infobulle')
        end
    end
end

-- Construction ------------------------------------------------------------------------------------

local EXEMPLES_GRAPHIQUES = { 'graphiques_un_an', 'graphiques_treize_mois', 'graphiques_trois_mois', 'graphiques_depuis_le_debut',
    'graphiques_trimestres' }

essai("Contrat : tailles, créneaux (rectangles et nombre : 76), couleurs des deux apparences, ceux du contrat ; les notes à côté des objectifs", function()
    local entree = EXEMPLES.graphiques_un_an.entree
    local total = 0
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        local liste = CONTRAT.regles.graphiques.liste[g.cle]
        vrai(liste, 'graphique du contrat : ' .. g.cle)
        egal(liste.max_barres, g.max_barres, g.cle .. ' : créneaux')
        egal(liste.orientation, g.orientation, g.cle .. ' : sens')
        egal(entree.tailles[g.cle].largeur, g.largeur, g.cle .. ' : largeur')
        egal(entree.tailles[g.cle].hauteur, g.hauteur, g.cle .. ' : hauteur')
        total = total + g.max_barres
        -- Les rectangles ne dépendent que de la taille : ceux de chaque exemple.
        for _, exemple in ipairs(EXEMPLES_GRAPHIQUES) do
            local rendu = EXEMPLES[exemple].sortie.graphiques[g.cle]
            if rendu then
                local creneaux = FenetreSuivi.creneaux(g)
                egal(#rendu.creneaux, #creneaux, g.cle .. ' ' .. exemple)
                for i, c in ipairs(creneaux) do
                    local r = rendu.creneaux[i]
                    egal(string.format('%d %d %d %d', r.x, r.y, r.largeur, r.hauteur), string.format('%d %d %d %d', c.x, c.y, c.largeur, c.hauteur),
                        g.cle .. ' ' .. exemple .. ' créneau ' .. i)
                    egal(nil, getmetatable(c), 'table neuve')
                end
            end
        end
    end
    egal(8, #FenetreSuivi.GRAPHIQUES)
    egal(76, total, 'les 76 calques du contrat')
    egal(6, FenetreSuivi.graphique('notes').max_barres, 'les notes : de 0 à 5 ★')
    egal(13, FenetreSuivi.graphique('photos_par_mois').max_barres, 'treize mois au plus')
    egal(FenetreSuivi.graphique('objectifs').hauteur, FenetreSuivi.graphique('notes').hauteur, 'les notes de la taille des objectifs')
    for cle in pairs(CONTRAT.regles.graphiques.liste) do
        vrai(FenetreSuivi.graphique(cle), 'graphique de la fenêtre : ' .. cle)
    end
    -- Les couleurs : seule table, Dispositions.PALETTES, par les clés du contrat.
    memes(CONTRAT.regles.couleurs.cles, FenetreSuivi.COULEURS_CONNECTEUR)
    memes(CONTRAT.regles.couleurs.claire, FenetreSuivi.couleursConnecteur('claire'))
    memes(CONTRAT.regles.couleurs.sombre, FenetreSuivi.couleursConnecteur('sombre'))
    memes(CONTRAT.regles.couleurs.claire, FenetreSuivi.couleursConnecteur('inconnue'), 'une apparence inconnue : la claire')
    -- Plus de menu Période (correctif 1.3.8).
    egal(nil, FenetreSuivi.PERIODES)
    egal(nil, FenetreSuivi.PERIODE)
    egal(nil, FenetreSuivi.elementsPeriode)
    -- Les tuiles, dans l'ordre du contrat.
    for k, t in ipairs(EXEMPLES.graphiques_un_an.sortie.tuiles) do
        egal(t.cle, FenetreSuivi.TUILES[k].cle)
        egal(t.titre, FenetreSuivi.TUILES[k].titre)
    end
end)

essai("Construction : « Claude · Suivi », son cadre neuf, sa taille (écran de Dany), l'aplat du fond, huit images liées à leur taille, 76 calques sur les créneaux, les champs « Du » et « au », le menu du défaut, les tuiles ; rien avant la première réponse", function()
    depart()
    local D = FenetreSuivi.dimensions()
    vrai(D.hauteurFenetre <= 1440 - 100, "la fenêtre tient dans la hauteur de l'écran de Dany : " .. D.hauteurFenetre)
    vrai(D.largeurFenetre <= 3440, "et dans sa largeur : " .. D.largeurFenetre)
    egal(2 * D.colonne + D.ecartColonnes, D.interieur)
    egal(D.interieur, 4 * D.tuile + 3 * D.ecartTuile, 'les quatre tuiles sur la largeur')
    egal(D.colonne, 2 * FenetreSuivi.graphique('focales').largeur + D.ecartPetits, 'focales et ISO côte à côte')
    for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
        vrai(g.largeur <= D.colonne, g.cle .. ' dans sa colonne')
    end
    ouvrirSuivi(function(p, args)
        egal('Claude · Suivi', args.title)
        egal(FenetreSuivi.CADRE, args.save_frame)
        vrai(args.save_frame ~= 'DeveloppeurCarnet' and args.save_frame ~= 'DeveloppeurSuivi', "un nom neuf : " .. args.save_frame)
        egal(nil, S.boutonParDefaut(), 'aucun bouton par défaut')
        local liste = parents(args.contents)
        -- Le fond : un aplat de la taille du contenu, à la couleur des fenêtres (fondDroite).
        local fond = liste[2]
        egal('picture', fond.genre)
        egal(D.largeurContenu, fond.args.width)
        egal(D.hauteurContenu, fond.args.height)
        local c = Dispositions.couleurs('claire').fondDroite
        egal(c[1], fond.args.background_color.r)
        egal(c[3], fond.args.background_color.b)
        -- Huit images liées, à la taille demandée au connecteur, cachées avant la première réponse.
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            local image = liee(args.contents, 'picture', 'image_' .. g.cle)
            egal(g.largeur, image.args.width, g.cle)
            egal(g.hauteur, image.args.height, g.cle)
            egal('pret_' .. g.cle, image.args.visible.key)
            egal(false, p['pret_' .. g.cle])
            vrai(Fichiers.existe(p['image_' .. g.cle]), "une image existante avant la première (cachée)")
        end
        -- 76 calques, chacun sur son créneau (sa colonne poussée par ses marges), à sa taille,
        -- visibilité et infobulle liées, cachés avant la première réponse.
        local calques, n = calquesDe(args.contents)
        egal(76, n, 'les calques')
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            local attendus = EXEMPLES.graphiques_un_an.sortie.graphiques[g.cle].creneaux
            for i, cr in ipairs(attendus) do
                local calque = calques[g.cle][i]
                vrai(calque, g.cle .. ' : calque ' .. i)
                egal('column', calque.colonne.genre)
                egal(cr.x, calque.colonne.args.margin_left, g.cle .. ' ' .. i .. ' x')
                egal(cr.y, calque.colonne.args.margin_top, g.cle .. ' ' .. i .. ' y')
                egal(cr.largeur, calque.vue.args.width, g.cle .. ' ' .. i .. ' largeur')
                egal(cr.hauteur, calque.vue.args.height, g.cle .. ' ' .. i .. ' hauteur')
                egal('', calque.vue.args.title)
                local visible, infobulle = FenetreSuivi.cleCalque(g.cle, i)
                egal(infobulle, calque.vue.args.tooltip.key)
                egal(false, p[visible])
                egal(false, S.montreeDansFenetre(calque.vue), 'caché')
            end
        end
        -- « Du » et « au » : deux champs validés par Retour (immediate faux), sans rien de gardé les
        -- douze derniers mois (du 1er du mois onze mois plus tôt à aujourd'hui) ; plus de menu Période.
        -- Le menu du défaut suivi (le plus fréquent).
        local du, au = liee(args.contents, 'edit_field', 'debutTexte'), liee(args.contents, 'edit_field', 'finTexte')
        egal(false, du.args.immediate)
        egal(false, au.args.immediate)
        egal(FenetreSuivi.INFOBULLE_DEBUT, du.args.tooltip)
        egal('1er décembre 2025', p.debutTexte)
        egal("aujourd'hui", p.finTexte)
        egal(nil, p.periode)
        for _, v in ipairs(liste) do
            vrai(not (v.genre == 'popup_menu' and type(v.args.value) == 'table' and v.args.value.key == 'periode'), 'plus de menu Période')
        end
        local defaut = liee(args.contents, 'popup_menu', 'elementsDefaut')
        egal('defaut', defaut.args.value.key)
        egal(FenetreSuivi.LE_PLUS_FREQUENT, p.defaut)
        egal(1, #p.elementsDefaut)
        egal(FenetreSuivi.TITRE_PLUS_FREQUENT, p.elementsDefaut[1].title)
        -- Les tuiles : leurs titres, « — » avant la première réponse.
        for k, t in ipairs(FenetreSuivi.TUILES) do
            egal(t.titre, p['tuileTitre' .. k])
            egal('—', p['tuileTexte' .. k])
        end
        egal(FenetreSuivi.LECTURE, p.etat)
        egal(FenetreSuivi.ATTENTE, p.attente)
        -- Les sections ; plus de « Photos d'un défaut… » (correctif 1.3.8).
        local textes = {}
        for _, v in ipairs(liste) do
            if v.genre == 'static_text' and type(v.args.title) == 'string' then
                textes[v.args.title] = true
            end
        end
        vrai(textes[FenetreSuivi.PRISES_DE_VUE] and textes[FenetreSuivi.CARNET], 'Mes prises de vue, Mon carnet de progrès')
        vrai(textes[FenetreSuivi.AIDE], "l'aide des clics")
        egal(nil, bouton(args.contents, "Photos d'un défaut…"), "plus de « Photos d'un défaut… »")
        egal(nil, p.aDefauts)
        -- Les notes à côté des objectifs, dans la même rangée.
        local objectifs, notes = liee(args.contents, 'picture', 'image_objectifs'), liee(args.contents, 'picture', 'image_notes')
        local _, parent = parents(args.contents)
        local function rangee(v)
            while v and v.genre ~= 'row' do
                v = parent[v]
            end
            return v
        end
        vrai(rangee(objectifs) and rangee(objectifs) == rangee(notes), 'les notes et les objectifs dans la même rangée')
        -- Rien n'est demandé au connecteur avant le premier tour de la boucle.
        egal(0, #recus())
    end)
end)

-- L'entrée et la sortie ---------------------------------------------------------------------------

essai("Premier tour : --graphiques sous perl (alarme de 60 s) avec exactement l'entrée de l'exemple des 12 mois, puis Releve.reclasser dans sa propre tâche ; sa sortie montrée (tuiles, titres, notes, images, calques, menu du défaut)", function()
    depart()
    ouvrirSuivi(function(p)
        local commandes = #(S.dernieresCommandes or {})
        local taches = #S.taches
        unTour()
        local r = recus()
        egal(1, #r, 'un appel')
        -- La note, le drapeau et « retouchée par Claude » relus après le premier dessin, dans une
        -- tâche à part (à toute la bibliothèque, il dure : la boucle suit la période pendant ce temps).
        egal(0, #reclassements, 'pas dans la boucle')
        egal(taches + 1, #S.taches, 'la tâche du reclassement')
        S.taches[#S.taches]()
        egal(1, #reclassements, 'la note, le drapeau et « retouchée par Claude » relus')
        egal(1, reclassements[1], 'après le premier --graphiques')
        egal(false, FenetreSuivi.aRedessiner, 'rien de relu (0) : pas de second dessin')
        memes(entreeAttendue('graphiques_un_an'), r[1].entree)
        -- La commande : perl et son alarme, le connecteur, l'entrée et un dossier neuf.
        local commande
        for i = commandes + 1, #S.dernieresCommandes do
            if S.dernieresCommandes[i]:find('--graphiques', 1, true) then
                commande = S.dernieresCommandes[i]
            end
        end
        vrai(commande, 'la commande')
        egal(1, select(2, commande:gsub("/usr/bin/perl %-e 'alarm 60; exec @ARGV' ", '')), commande)
        contient(CONTRAT.regles.graphiques.commande, "alarm 60", "l'alarme du contrat")
        contient(commande, S.q(CONNECTEUR) .. ' --graphiques ')
        contient(r[1].dossier, Chemins.temporaire() .. '/Suivi/Graphiques-')
        -- La sortie : tuiles, titres, notes, images et calques.
        local sortie = sortieAttendue('graphiques_un_an', r[1].dossier)
        for k, t in ipairs(sortie.tuiles) do
            egal(t.titre, p['tuileTitre' .. k])
            egal(t.texte, p['tuileTexte' .. k])
            egal(t.detail, p['tuileDetail' .. k])
        end
        egal('12', p.tuileTexte1)
        egal("1 en cours d'analyse · 1 non analysée", p.tuileDetail1)
        egal('30 %', p.tuileTexte4)
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            local rendu = sortie.graphiques[g.cle]
            egal(rendu.titre, p['titre_' .. g.cle])
            egal(rendu.note or '', p['note_' .. g.cle])
            egal(rendu.fichier, p['image_' .. g.cle])
            vrai(Fichiers.existe(p['image_' .. g.cle]), 'image écrite : ' .. g.cle)
            egal(true, p['pret_' .. g.cle])
        end
        egal('Photo floue ou bougée, mois par mois', p.titre_evolution_defaut)
        verifierCalques(p, sortie)
        -- Par exemple : focales ≤ 23 (créneau 2, 4 photos) se clique ; décembre 2025 (0 photo), non.
        egal(true, p.c_focales_2)
        egal("16 à 23 mm · 4 photos\n" .. FenetreSuivi.INFOBULLE_BARRE, p.i_focales_2)
        egal(false, p.c_photos_par_mois_1)
        -- La ligne d'état : la période et ses photos.
        egal("Du 1er décembre 2025 au 20 novembre 2026 · 12 photos ouvertes, dont 1 sans date de prise de vue (à leur "
            .. "date d'ajout).", p.etat)
        -- L'année au premier mois et à janvier ; le dernier mois, jusqu'au jour de fin.
        contient(p.i_photos_par_mois_2, 'janvier 2026 · 1 photo')
        contient(p.i_photos_par_mois_12, "novembre 2026, jusqu'au 20 · 4 photos")
        egal(false, p.c_photos_par_mois_13, 'douze mois : le treizième créneau vide')
        -- Les notes : 0 ★ (cinq photos) se clique, sa note dit la photo rejetée.
        egal(true, p.c_notes_1)
        egal("0 ★, pas encore notée · 5 photos\n" .. FenetreSuivi.INFOBULLE_BARRE, p.i_notes_1)
        egal('Dont 1 rejetée (drapeau), comptée à sa note.', p.note_notes)
        -- Le menu du défaut suivi : le plus fréquent (dit), puis les huit défauts du contrat, dans leur
        -- ordre, avec leur pourcentage ; des tables neuves.
        local items = p.elementsDefaut
        S.neuve(items, 'défauts')
        egal('Le plus fréquent : Photo floue ou bougée', items[1].title)
        egal(FenetreSuivi.LE_PLUS_FREQUENT, items[1].value)
        egal(true, items[2].separator)
        egal(2 + #sortie.defauts, #items)
        for i, d in ipairs(sortie.defauts) do
            egal(d.code, items[2 + i].value)
            egal(d.libelle .. ' · ' .. d.texte, items[2 + i].title)
        end
        egal(0, #journal, 'journal : ' .. table.concat(journal, ' | '))
        -- Rien de changé : pas de nouveau dessin.
        unTour()
        egal(1, #recus(), 'rien de refait')
    end)
end)

essai("Période et défaut choisis (apparence sombre) : du 1er septembre 2026, puis « Yeux fermés » : exactement l'entrée de l'exemple des trois mois ; quatre créneaux par mois ; la période gardée ; le plus fréquent rechoisi, sans défaut", function()
    depart('sombre')
    ouvrirSuivi(function(p, args)
        unTour()
        -- Le fond dans l'apparence sombre.
        local fond = parents(args.contents)[2]
        egal(Dispositions.couleurs('sombre').fondDroite[1], fond.args.background_color.r)
        taperDate(p, 'debut', '1er sept. 2026')
        egal(true, FenetreSuivi.aRedessiner, 'une autre période : à refaire')
        egal('1er septembre 2026', p.debutTexte, 'le champ réécrit au propre')
        egal('2026-09-01', prefs.suiviDebut, 'gardée')
        egal(FenetreSuivi.AUJOURDHUI, prefs.suiviFin, "la fin telle qu'elle est montrée")
        unTour()
        local r = recus()
        egal(2, #r)
        egal('2026-09-01', r[2].entree.debut)
        egal(AUJOURDHUI, r[2].entree.fin)
        egal(nil, r[2].entree.defaut)
        local menu = liee(args.contents, 'popup_menu', 'elementsDefaut')
        S.choisir(menu, 'yeux_fermes')
        unTour()
        r = recus()
        egal(3, #r)
        memes(entreeAttendue('graphiques_trois_mois'), r[3].entree)
        local sortie = sortieAttendue('graphiques_trois_mois', r[3].dossier)
        verifierCalques(p, sortie)
        -- Trois mois de quatre créneaux : septembre sur les quatre premiers ; le treizième, vide.
        for i = 1, 4 do
            egal(true, p['c_photos_par_mois_' .. i], 'septembre, créneau ' .. i)
            contient(p['i_photos_par_mois_' .. i], 'septembre 2026')
        end
        contient(p.i_photos_par_mois_9, 'novembre 2026')
        egal(false, p.c_photos_par_mois_13)
        egal('Yeux fermés ou plissés, mois par mois', p.titre_evolution_defaut)
        contient(p.etat, 'Du 1er septembre 2026 au 20 novembre 2026 · 9 photos ouvertes')
        -- Le plus fréquent rechoisi : sans défaut dans l'entrée.
        S.choisir(menu, FenetreSuivi.LE_PLUS_FREQUENT)
        unTour()
        r = recus()
        egal(4, #r)
        egal(nil, r[4].entree.defaut)
        egal('2026-09-01', r[4].entree.debut)
    end)
    -- Rouverte : la période gardée revient, dans les champs et dans l'entrée.
    ouvrirSuivi(function(p)
        egal('1er septembre 2026', p.debutTexte)
        egal("aujourd'hui", p.finTexte)
        unTour()
        local r = recus()
        egal('2026-09-01', r[#r].entree.debut)
        egal(AUJOURDHUI, r[#r].entree.fin)
    end)
end)

essai("Depuis la première photo, avec « Photo floue » : exactement l'entrée de l'exemple sans début ; une colonne par année, les années d'avant 2015 d'abord ; les objectifs, « Autres » en dernier", function()
    depart()
    ouvrirSuivi(function(p, args)
        unTour()
        taperDate(p, 'debut', '')
        egal(FenetreSuivi.PREMIERE_PHOTO, p.debutTexte)
        egal('', prefs.suiviDebut, 'gardée : depuis la première photo')
        S.choisir(liee(args.contents, 'popup_menu', 'elementsDefaut'), 'flou')
        unTour()
        local r = recus()
        egal(2, #r, 'un seul dessin pour les deux choix du même tour')
        memes(entreeAttendue('graphiques_depuis_le_debut'), r[2].entree)
        verifierCalques(p, sortieAttendue('graphiques_depuis_le_debut', r[2].dossier))
        contient(p.i_photos_par_mois_1, 'avant 2015 · 2 photos')
        egal('Photos par année', p.titre_photos_par_mois)
        contient(p.i_objectifs_8, '2 autres objectifs · 2 photos')
        egal("Depuis la première photo, le 25 décembre 2009, jusqu'au 20 novembre 2026 · 17 photos ouvertes, dont 1 sans date de prise de vue "
            .. "(à leur date d'ajout).", p.etat)
        -- « première photo », tapée telle quelle, se lit aussi ; rien ne change.
        taperDate(p, 'debut', 'Première photo ')
        egal(FenetreSuivi.PREMIERE_PHOTO, p.debutTexte)
        egal(false, FenetreSuivi.aRedessiner)
    end)
end)

essai("Plus de treize mois : par trimestre (l'entrée de l'exemple des trimestres) ; une fin fixe gardée ; une date qui ne se lit pas, ou un début après la fin : la ligne d'état le dit, les champs reprennent la période gardée, rien n'est refait", function()
    depart()
    ouvrirSuivi(function(p)
        unTour()
        taperDate(p, 'debut', '01/01/2024')
        unTour()
        local r = recus()
        egal(2, #r)
        memes(entreeAttendue('graphiques_trimestres'), r[2].entree)
        egal('Photos par trimestre', p.titre_photos_par_mois)
        contient(p.i_photos_par_mois_7, 'juillet à septembre 2025 · 1 photo')
        egal(false, p.c_photos_par_mois_13)
        -- Une fin fixe : gardée telle quelle, elle n'avance plus.
        taperDate(p, 'fin', '25 janvier 2026')
        egal('25 janvier 2026', p.finTexte)
        egal('2026-01-25', prefs.suiviFin)
        unTour()
        r = recus()
        egal('2026-01-25', r[3].entree.fin)
        egal('2024-01-01', r[3].entree.debut)
        -- Une date qui ne se lit pas : dite, la période gardée revient dans le champ.
        taperDate(p, 'fin', '31 février 2026')
        egal(string.format(FenetreSuivi.FIN_ILLISIBLE, '31 février 2026'), p.etat)
        egal('25 janvier 2026', p.finTexte)
        egal('2026-01-25', prefs.suiviFin)
        egal(false, FenetreSuivi.aRedessiner)
        taperDate(p, 'debut', 'hier')
        egal(string.format(FenetreSuivi.DEBUT_ILLISIBLE, 'hier'), p.etat)
        egal('1er janvier 2024', p.debutTexte)
        -- Un début après la fin : refusé.
        taperDate(p, 'debut', '2026-02-01')
        egal(string.format(FenetreSuivi.DEBUT_APRES_FIN, '1er février 2026', '25 janvier 2026'), p.etat)
        contient(p.etat, "changez d'abord « au »")
        egal('1er janvier 2024', p.debutTexte)
        egal('2024-01-01', prefs.suiviDebut)
        -- Une fin avant le début : refusée aussi, avec le champ à changer d'abord.
        taperDate(p, 'fin', '2023')
        egal(string.format(FenetreSuivi.FIN_AVANT_DEBUT, '31 décembre 2023', '1er janvier 2024'), p.etat)
        contient(p.etat, "changez d'abord « Du »")
        egal('25 janvier 2026', p.finTexte)
        egal('2026-01-25', prefs.suiviFin)
        -- La même date retapée, autrement écrite : rien de gardé ni de refait.
        taperDate(p, 'debut', '01/01/2024')
        egal('1er janvier 2024', p.debutTexte)
        egal(false, FenetreSuivi.aRedessiner)
        unTour()
        egal(3, #recus(), 'rien de refait')
        -- « aujourd'hui » : la fin avance de nouveau.
        taperDate(p, 'fin', "Aujourd'hui")
        egal("aujourd'hui", p.finTexte)
        egal(FenetreSuivi.AUJOURDHUI, prefs.suiviFin)
    end)
end)

essai("Sans période gardée : l'écho de ce que la fenêtre écrit ne garde rien ; la date affichée retapée autrement se garde ; l'autre borne est celle que montre le champ, même un mois plus tard sans dessin ; chaque dessin recale les champs sur le jour", function()
    depart()
    local aujourdhui = FenetreSuivi.aujourdhui
    local ok, erreur = pcall(ouvrirSuivi, function(p)
        unTour()
        egal('1er décembre 2025', p.debutTexte)
        -- L'écho (un observateur appelé plus tard, avec le texte que la fenêtre a écrit) : rien.
        egal(false, FenetreSuivi.changerDate('debut', '1er décembre 2025'))
        egal(false, FenetreSuivi.changerDate('fin', "aujourd'hui"))
        egal(nil, prefs.suiviDebut, "l'écho ne garde rien")
        egal(nil, prefs.suiviFin)
        -- La date affichée, retapée autrement : Dany l'a choisie, elle se garde (« Du » ne suit plus
        -- le mois) ; la période dessinée ne change pas.
        taperDate(p, 'debut', '2025-12-01')
        egal('1er décembre 2025', p.debutTexte)
        egal('2025-12-01', prefs.suiviDebut)
        egal(FenetreSuivi.AUJOURDHUI, prefs.suiviFin)
        FenetreSuivi.aujourdhui = function() return '2027-01-05' end
        egal('2025-12-01', FenetreSuivi.iso(FenetreSuivi.periode().debut), 'gardée : le mois passé, elle reste')
        FenetreSuivi.aujourdhui = aujourdhui
        -- Rien de gardé de nouveau ; un mois passe sans dessin (relevé et carnet inchangés) : « au »
        -- tapé garde le début que « Du » montre, pas celui du nouveau mois.
        prefs.suiviDebut, prefs.suiviFin = nil, nil
        FenetreSuivi.poserChamps(FenetreSuivi.periode())
        egal('1er décembre 2025', p.debutTexte)
        FenetreSuivi.aujourdhui = function() return '2026-12-02' end
        taperDate(p, 'fin', '15 novembre 2026')
        egal('2025-12-01', prefs.suiviDebut, 'le début montré, pas le 1er janvier 2026')
        egal('2026-11-15', prefs.suiviFin)
        egal('1er décembre 2025', p.debutTexte)
        egal('15 novembre 2026', p.finTexte)
        -- Chaque dessin recale les champs : rien de gardé, la fenêtre restée ouverte d'un mois à
        -- l'autre montre la période qu'elle dessine.
        prefs.suiviDebut, prefs.suiviFin = nil, nil
        FenetreSuivi.aujourdhui = function() return '2027-01-05' end
        FenetreSuivi.aRedessiner = true
        unTour()
        egal('1er février 2026', p.debutTexte, 'recalé au dessin')
        egal("aujourd'hui", p.finTexte)
        local r = recus()
        egal('2026-02-01', r[#r].entree.debut)
        egal('2027-01-05', r[#r].entree.fin)
    end)
    FenetreSuivi.aujourdhui = aujourdhui
    prefs.suiviDebut, prefs.suiviFin = nil, nil
    assert(ok, erreur)
end)

essai("Les dates tapées (FenetreSuivi.lireDate) : jour, mois et année en mots ou en chiffres, sans tenir compte des accents ni des majuscules ; un mois ou une année seuls ; vide, première photo, aujourd'hui ; ce qui ne se lit pas", function()
    local function lue(texte, borne)
        local d = FenetreSuivi.lireDate(texte, borne or 'debut', '2026-11-20')
        if d == nil then
            return 'nil'
        end
        if d.premiere then
            return 'premiere'
        end
        if d.aujourdhui then
            return 'aujourdhui'
        end
        return FenetreSuivi.iso(d)
    end
    egal('2025-01-25', lue('25 janvier 2025'))
    egal('2025-01-25', lue('  25  Janvier  2025 '))
    egal('2025-01-01', lue('1er janvier 2025'))
    egal('2025-02-25', lue('25 fevrier 2025'))
    egal('2025-02-25', lue('25 FÉVR. 2025'))
    egal('2025-08-15', lue('15 août 2025'))
    egal('2025-08-15', lue('15 aou 2025'))
    egal('2025-12-01', lue('1 déc 2025'))
    egal('2025-01-25', lue('25/01/2025'))
    egal('2025-01-05', lue('5-1-2025'))
    egal('2025-01-05', lue('5.1.2025'))
    egal('2025-01-25', lue('2025-01-25'))
    egal('2025-03-01', lue('mars 2025'))
    egal('2025-03-31', lue('mars 2025', 'fin'))
    egal('2024-02-29', lue('février 2024', 'fin'), 'bissextile')
    egal('2025-02-28', lue('février 2025', 'fin'))
    egal('2025-01-01', lue('2025'))
    egal('2025-12-31', lue('2025', 'fin'))
    egal('premiere', lue(''))
    egal('premiere', lue('la première photo'))
    egal('aujourdhui', lue('', 'fin'))
    egal('aujourdhui', lue("AUJOURD'HUI", 'fin'))
    egal('aujourdhui', lue('aujourd’hui', 'fin'), "l'apostrophe typographique")
    egal('2026-11-20', lue("aujourd'hui"), 'au début : le jour même')
    egal('nil', lue('31 avril 2025'))
    egal('nil', lue('29 février 2025'))
    egal('nil', lue('25 jui 2025'), 'juin ou juillet ?')
    egal('nil', lue('2e janvier 2025'))
    egal('nil', lue('25/13/2025'))
    egal('nil', lue('1899'))
    egal('nil', lue('hier'))
    egal('nil', lue('première photo', 'fin'))
    -- En français : « 1er » le premier du mois.
    egal('1er mars 2026', FenetreSuivi.texteDate({ annee = 2026, mois = 3, jour = 1 }))
    egal('25 janvier 2025', FenetreSuivi.texteDate({ annee = 2025, mois = 1, jour = 25 }))
    -- La période sans rien de gardé : les douze derniers mois, du 1er du mois onze mois plus tôt à
    -- aujourd'hui (d'une année à l'autre).
    local aujourdhui = FenetreSuivi.aujourdhui
    FenetreSuivi.aujourdhui = function() return '2028-02-29' end
    prefs.suiviDebut, prefs.suiviFin = nil, nil
    local periode = FenetreSuivi.periode()
    egal('2027-03-01', FenetreSuivi.iso(periode.debut))
    egal('2028-02-29', FenetreSuivi.iso(periode.fin))
    egal(true, periode.finAujourdhui)
    FenetreSuivi.aujourdhui = function() return '2026-12-31' end
    egal('2026-01-01', FenetreSuivi.iso(FenetreSuivi.periode().debut), 'en décembre : depuis janvier')
    FenetreSuivi.aujourdhui = function() return '2026-11-30' end
    egal('2025-12-01', FenetreSuivi.iso(FenetreSuivi.periode().debut))
    FenetreSuivi.aujourdhui = function() return '2028-02-29' end
    -- Une préférence éditée à la main, ou un début gardé après la fin : la période par défaut.
    prefs.suiviDebut, prefs.suiviFin = 'pas une date', '2026-13-01'
    periode = FenetreSuivi.periode()
    egal('2027-03-01', FenetreSuivi.iso(periode.debut))
    egal(true, periode.finAujourdhui)
    prefs.suiviDebut, prefs.suiviFin = '2026-06-01', '2026-01-25'
    egal('2025-02-01', FenetreSuivi.iso(FenetreSuivi.periode().debut))
    FenetreSuivi.aujourdhui = aujourdhui
    prefs.suiviDebut, prefs.suiviFin = nil, nil
end)

-- Un clic sur une barre ---------------------------------------------------------------------------

-- La Bibliothèque simulée pour les clics : les originaux du relevé (sauf 4231, devenu une autre
-- photo : un autre uuid), et `autres` photos hors du relevé (9001…) ; la source affichée (« dossier »,
-- qui montre les photos de b.visibles, ou Toutes les photographies) ; un filtre de la Bibliothèque
-- qui cache les photos de b.filtrees, même dans Toutes les photographies. Les règles de Lightroom,
-- relevées en lecture seule dans le LrCatalog.lua compilé de Lightroom 15.6 : setSelectedPhotos ne
-- sélectionne que les photos qui ont une case dans la grille (aucune : la sélection vide, ou telle
-- quelle avec b.garder) ; la photo active est la première sélectionnée ; sans sélection,
-- getTargetPhotos rend tout le film fixe (getMultipleSelectedOrAllPhotos). Rend l'état et la
-- fonction qui remet le catalogue simulé.
local function bibliotheque(autres)
    local b = { source = 'dossier', selection = {}, sources = {}, visibles = {}, filtrees = {}, garder = false, photos = {} }
    local function photoDe(id, uuid)
        return { localIdentifier = id, uuid = uuid, getRawMetadata = function(self, k) return k == 'uuid' and self.uuid or nil end,
            getFormattedMetadata = function(self, k) return k == 'fileName' and ('DSCF' .. self.localIdentifier .. '.RAF') or nil end,
            setPropertyForPlugin = function() error("le Suivi n'écrit rien dans le catalogue", 2) end }
    end
    for cle, e in pairs(REGISTRE.catalogues[CATALOGUE].photos) do
        local id = tonumber(cle)
        b.photos[id] = photoDe(id, id == 4231 and 'AUTRE-UUID' or e.uuid)
    end
    for i = 1, autres or 0 do
        b.photos[9000 + i] = photoDe(9000 + i, 'HORS-DU-RELEVE-' .. i)
    end
    local function dansLaGrille(ph)
        return not b.filtrees[ph.localIdentifier] and (b.source == 'kAllPhotos' or b.visibles[ph.localIdentifier] == true)
    end
    function b.filmFixe()
        local ids = {}
        for id, ph in pairs(b.photos) do
            if dansLaGrille(ph) then
                ids[#ids + 1] = id
            end
        end
        table.sort(ids)
        local liste = {}
        for _, id in ipairs(ids) do
            liste[#liste + 1] = b.photos[id]
        end
        return liste
    end
    function b.ids()
        local ids = {}
        for _, ph in ipairs(b.selection) do
            ids[#ids + 1] = ph.localIdentifier
        end
        return table.concat(ids, ' ')
    end
    local avant = {}
    for k, v in pairs(S.catalogue) do
        avant[k] = v
    end
    S.catalogue.getPhotoByLocalId = function(_, id) return b.photos[tonumber(id)] end
    S.catalogue.kAllPhotos = 'kAllPhotos'
    S.catalogue.setActiveSources = function(_, source)
        b.source = source
        b.sources[#b.sources + 1] = source
    end
    S.catalogue.setSelectedPhotos = function(_, active, suivantes)
        local selection = {}
        for _, ph in ipairs({ active, unpack(suivantes) }) do
            if dansLaGrille(ph) then
                selection[#selection + 1] = ph
            end
        end
        if #selection > 0 or not b.garder then
            b.selection = selection
        end
    end
    S.catalogue.getTargetPhoto = function() return b.selection[1] end
    S.catalogue.getTargetPhotos = function() return #b.selection > 0 and b.selection or b.filmFixe() end
    S.catalogue.withWriteAccessDo = function() error("le Suivi n'écrit rien dans le catalogue", 2) end
    local function remettre()
        for k in pairs(S.catalogue) do
            S.catalogue[k] = nil
        end
        for k, v in pairs(avant) do
            S.catalogue[k] = v
        end
        S.moduleLightroom = 'library'
    end
    return b, remettre
end

essai("Clic sur une barre : ses photos dans la Bibliothèque (grille), retrouvées par leur id et vérifiées par l'uuid du relevé ; Toutes les photographies quand la source ne les a pas ; rien d'écrit", function()
    depart()
    -- La source affichée ne montre que 3502 ; Toutes les photographies les montre tous.
    local b, remettre = bibliotheque()
    b.visibles = { [3502] = true }
    local ecritures = S.ecrituresPrivees or 0
    S.moduleLightroom, S.vuesLightroom = 'develop', {}
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        local calques = calquesDe(args.contents)
        -- Focales de 16 à 23 mm : 3502, 3640, 4211 et 4231.
        local avant = #S.taches
        S.cliquer(calques.focales[2].vue)
        egal(avant + 1, #S.taches, 'dans une tâche')
        lancerTaches(avant)
        egal('3502 3640 4211', b.ids(), "les photos de la barre, sans celle d'un autre uuid")
        egal('library', S.moduleLightroom, 'la Bibliothèque')
        egal('grid', S.vuesLightroom[#S.vuesLightroom], 'en grille')
        egal('kAllPhotos', b.sources[1], 'Toutes les photographies : la source ne les avait pas')
        egal("16 à 23 mm · 4 photos : dans la Bibliothèque (source : Toutes les photographies). 1 photo n'est plus au catalogue.",
            p.message)
        -- Une barre que la source affichée montre toute : la source ne change pas.
        b.visibles = { [4105] = true, [4106] = true }
        b.source, b.sources = 'dossier', {}
        local barre = 0
        for i = 1, 8 do
            local b = FenetreSuivi.barreDu('objectifs', i)
            if b and b.libelle == 'XF70-300mmF4-5.6 R LM OIS WR' then
                barre = i
            end
        end
        vrai(barre > 0, 'la barre du XF70-300')
        avant = #S.taches
        S.cliquer(calques.objectifs[barre].vue)
        lancerTaches(avant)
        egal(0, #b.sources, 'la source gardée')
        egal(2, #b.selection)
        egal('XF70-300mmF4-5.6 R LM OIS WR · 2 photos : dans la Bibliothèque.', p.message)
        -- Un créneau vide : son calque caché, rien ne part.
        egal(false, p.c_photos_par_mois_1)
        egal(false, FenetreSuivi.cliquer('photos_par_mois', 1))
        vrai(not pcall(S.cliquer, calques.photos_par_mois[1].vue), 'un calque caché ne prend pas le clic')
        -- Le défaut le plus fréquent (Défauts les plus fréquents, en %), le défaut suivi en accent.
        avant = #S.taches
        egal(true, FenetreSuivi.cliquer('defauts_frequents', 1))
        lancerTaches(avant)
        contient(p.message, 'Horizon ou ligne penchée · 1 photo sur 2 (50 %)')
        -- Plus aucune photo au catalogue : rien de sélectionné, le message le dit.
        b.photos = {}
        avant = #S.taches
        S.cliquer(calques.focales[2].vue)
        lancerTaches(avant)
        egal("16 à 23 mm · 4 photos : aucune n'est plus au catalogue.", p.message)
    end)
    remettre()
    assert(ok, erreur)
    egal(ecritures, S.ecrituresPrivees or 0, "aucune écriture, même privée")
end)

essai("Clic sur une barre de toute la bibliothèque : le relevé lu sans être copié (Releve.uuidsDe, jamais Releve.entrees), les photos retrouvées et leurs uuid lus par tranches, la main rendue entre deux", function()
    depart()
    local b, remettre = bibliotheque()
    b.visibles = { [3502] = true, [3640] = true, [4211] = true }
    local LrTasks = S.modules.LrTasks
    local entrees, yield, pas, lot = Releve.entrees, LrTasks.yield, FenetreSuivi.PAS_UNE_A_UNE, Releve.LOT_LECTURE
    local n = 0
    Releve.entrees = function() error('Releve.entrees copie tout le relevé', 2) end
    LrTasks.yield = function() n = n + 1 end
    FenetreSuivi.PAS_UNE_A_UNE, Releve.LOT_LECTURE = 1, 1
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        local calques = calquesDe(args.contents)
        local avant = #S.taches
        n = 0
        S.cliquer(calques.focales[2].vue)
        lancerTaches(avant)
        egal('3502 3640 4211', b.ids(), "les photos de la barre, sans celle d'un autre uuid")
        vrai(n >= 4 + 3, 'la main rendue : ' .. n)
        contient(p.message, 'dans la Bibliothèque')
    end)
    Releve.entrees, LrTasks.yield, FenetreSuivi.PAS_UNE_A_UNE, Releve.LOT_LECTURE = entrees, yield, pas, lot
    remettre()
    assert(ok, erreur)
end)

essai("Clic sur une barre : la sélection posée ne se range pas au relevé (ses photos y sont déjà : Releve.poserSelection) ; pendant qu'elle se pose, aucune sélection vue par la fenêtre Claude ne compte ; une autre ensuite, si", function()
    depart()
    local b, remettre = bibliotheque()
    b.visibles = { [3502] = true, [3640] = true, [4211] = true }
    local Lightroom = require 'Lightroom'
    local vues = {}
    Releve.allume = true
    local selectionner = S.catalogue.setSelectedPhotos
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        local calques = calquesDe(args.contents)
        S.catalogue.setSelectedPhotos = function(...)
            selectionner(...)
            -- La boucle de la fenêtre Claude regarde la sélection pendant qu'elle se pose.
            vues[#vues + 1] = tostring(Releve.voirSelection(Lightroom.photos()))
        end
        local avant = #S.taches
        S.cliquer(calques.focales[2].vue)
        lancerTaches(avant)
        S.catalogue.setSelectedPhotos = selectionner
        egal('3502 3640 4211', b.ids())
        vrai(#vues > 0, 'la sélection regardée pendant la pose')
        egal('false', table.concat(vues, ' '), 'pendant la pose : pas une vue')
        egal(false, Releve.voirSelection(Lightroom.photos()), 'posée : déjà vue')
        egal(0, #Releve.aVoir, 'rien à ranger')
        -- Dany choisit une autre photo : elle compte.
        b.selection = { b.photos[4105] }
        egal(true, Releve.voirSelection(Lightroom.photos()), 'une autre sélection')
    end)
    S.catalogue.setSelectedPhotos = selectionner
    Releve.allume = false
    Releve.oublier()
    remettre()
    assert(ok, erreur)
end)

essai("Clic sur une barre, sélection vérifiée par les photos et non leur nombre : aucune de la barre dans la grille (le film fixe en a autant, ou une autre photo reste sélectionnée), puis un filtre qui les cache toutes ou une seule ; jamais le nombre de photos du film fixe", function()
    depart()
    local b, remettre = bibliotheque(30)
    local delai = FenetreSuivi.DELAI_SOURCE
    S.moduleLightroom, S.vuesLightroom = 'develop', {}
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        local calques = calquesDe(args.contents)
        local function cliquer(cle, i)
            local avant = #S.taches
            S.cliquer(calques[cle][i].vue)
            lancerTaches(avant)
        end
        -- Le dossier affiché : trois photos hors du relevé, autant que la barre en a de retrouvées
        -- (3502, 3640, 4211) ; aucune de la barre. Rien de sélectionné, getTargetPhotos rend les trois
        -- du dossier : ce n'est pas un succès, Toutes les photographies devient la source.
        b.visibles = { [9001] = true, [9002] = true, [9003] = true }
        egal(3, #b.filmFixe(), 'le film fixe : autant que la barre')
        cliquer('focales', 2)
        egal('kAllPhotos', b.sources[1], "la source change : aucune photo de la barre n'était dans la grille")
        egal('3502 3640 4211', b.ids())
        egal("16 à 23 mm · 4 photos : dans la Bibliothèque (source : Toutes les photographies). 1 photo n'est plus au catalogue.",
            p.message)
        -- Une barre d'une photo, une autre photo sélectionnée que Lightroom garde : pas un succès non
        -- plus (la photo active n'est pas de la barre).
        local cle, rang, barre
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            for i = 1, g.max_barres do
                local x = FenetreSuivi.barreDu(g.cle, i)
                if not cle and x and #x.ids == 1 and x.ids[1] ~= 4231 and b.photos[x.ids[1]] then
                    cle, rang, barre = g.cle, i, x
                end
            end
        end
        vrai(cle, "une barre d'une seule photo")
        b.source, b.sources, b.garder = 'dossier', {}, true
        b.selection = { b.photos[9001] }
        cliquer(cle, rang)
        egal('kAllPhotos', b.sources[1], "une autre photo sélectionnée : la source change")
        egal(tostring(barre.ids[1]), b.ids())
        contient(p.message, ' : dans la Bibliothèque (source : Toutes les photographies).')
        -- Un filtre de la Bibliothèque qui les cache toutes, même dans Toutes les photographies (le
        -- film fixe en a des dizaines) : Lightroom ne les a pas montrées, sans compte absurde.
        FenetreSuivi.DELAI_SOURCE = 0
        b.source, b.sources, b.garder, b.selection = 'dossier', {}, false, {}
        b.filtrees = { [3502] = true, [3640] = true, [4211] = true }
        b.visibles = {}
        for i = 1, 30 do
            b.visibles[9000 + i] = true
        end
        egal(30, #b.filmFixe(), 'le film fixe du dossier : trente photos hors de la barre')
        cliquer('focales', 2)
        egal('kAllPhotos', b.sources[1])
        egal("16 à 23 mm · 4 photos : Lightroom ne les a pas montrées (le filtre de la Bibliothèque les cache ?). 1 photo n'est plus "
            .. "au catalogue.", p.message)
        -- Un filtre qui en cache une : deux sur trois, le compte des photos de la barre.
        b.source, b.sources, b.selection = 'dossier', {}, {}
        b.filtrees = { [4211] = true }
        cliquer('focales', 2)
        egal('3502 3640', b.ids())
        egal("16 à 23 mm · 4 photos : 2 sur 3 dans la Bibliothèque (source : Toutes les photographies) ; le filtre de la Bibliothèque "
            .. "cache les autres. 1 photo n'est plus au catalogue.", p.message)
    end)
    FenetreSuivi.DELAI_SOURCE = delai
    remettre()
    assert(ok, erreur)
end)

essai("Avant chaque dessin demandé (l'ouverture, une autre période), ce que le Suivi a rangé sans l'écrire encore s'écrit (Releve.ecrire), puis --graphiques lit le fichier", function()
    depart()
    local ecrire = Releve.ecrire
    local appels = {}
    Releve.ecrire = function()
        appels[#appels + 1] = #recus()
        return false
    end
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        taperDate(p, 'debut', '1er septembre 2026')
        unTour()
    end)
    Releve.ecrire = ecrire
    assert(ok, erreur)
    egal(2, #recus(), 'deux dessins')
    egal('0 1', table.concat(appels, ' '), 'Releve.ecrire avant chaque --graphiques demandé')
end)

-- Relevé vide, connecteur absent, muet, qui refuse -------------------------------------------------------

essai("Relevé vide : le texte d'accueil ; les graphiques « Aucune photo » du connecteur, aucun calque", function()
    depart()
    Fichiers.supprimer(Releve.fichier())
    Releve.oublier()
    mode('vide')
    ouvrirSuivi(function(p)
        unTour()
        egal(1, #recus(), 'dessinés quand même')
        egal(FenetreSuivi.ACCUEIL, p.etat)
        contient(p.etat, 'Le Suivi part de zéro')
        contient(p.etat, 'sans Claude ni forfait')
        egal('0', p.tuileTexte1)
        egal('aucune photo ouverte dans la période', p.tuileDetail1)
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            egal(true, p['pret_' .. g.cle], g.cle .. ' : image du connecteur')
            for i = 1, g.max_barres do
                egal(false, p[FenetreSuivi.cleCalque(g.cle, i)], g.cle .. ' ' .. i)
            end
        end
    end)
    -- Un relevé qui a des photos, mais pas dans la période : ce qu'il faut choisir.
    egal(FenetreSuivi.SANS_PHOTO_PERIODE .. FenetreSuivi.VOIR_TOUT, FenetreSuivi.texteEtat({ photos = 0, periode = { depuis_le_debut = false,
        fin = AUJOURDHUI } }, false))
    egal(FenetreSuivi.SANS_PHOTO_PERIODE .. FenetreSuivi.VOIR_TOUT, FenetreSuivi.texteEtat({ photos = 0, periode = { depuis_le_debut = true,
        fin = '2026-01-25' } }, false), "depuis la première photo, mais jusqu'à une fin passée : il y en a peut-être d'autres")
    egal(FenetreSuivi.SANS_PHOTO_PERIODE, FenetreSuivi.texteEtat({ photos = 0, periode = { depuis_le_debut = true, fin = AUJOURDHUI } }, false))
end)

essai("Connecteur absent, puis muet, puis qui refuse : le message dit pourquoi ; sans réponse, les images d'avant restent", function()
    depart()
    prefs.cheminConnecteur = S.home .. '/absent/mcp-developpeur'
    ouvrirSuivi(function(p, args)
        local commandes = #(S.dernieresCommandes or {})
        unTour()
        egal(FenetreSuivi.CONNECTEUR_ABSENT, p.etat)
        egal(FenetreSuivi.SANS_GRAPHIQUE, p.attente)
        egal(0, #recus())
        for i = commandes + 1, #(S.dernieresCommandes or {}) do
            vrai(not S.dernieresCommandes[i]:find('--graphiques', 1, true), 'rien lancé : ' .. S.dernieresCommandes[i])
        end
        for _, g in ipairs(FenetreSuivi.GRAPHIQUES) do
            egal(false, p['pret_' .. g.cle])
        end
        -- Rien de changé : la boucle ne réessaie pas sans fin.
        unTour()
        egal(FenetreSuivi.CONNECTEUR_ABSENT, p.etat)
        -- Le connecteur retrouvé (une autre période choisie) : dessinés.
        prefs.cheminConnecteur = CONNECTEUR
        taperDate(p, 'debut', '1er septembre 2026')
        unTour()
        egal(1, #recus())
        egal(true, p.pret_focales)
        local image = p.image_focales
        -- Muet (l'alarme, un vieux connecteur) : le message, les images d'avant gardées, le dossier du
        -- dessin manqué effacé.
        mode('muet')
        taperDate(p, 'debut', '20 novembre 2025')
        unTour()
        local r = recus()
        egal(2, #r)
        egal(FenetreSuivi.PAS_DE_REPONSE, p.etat)
        egal(true, p.pret_focales)
        egal(image, p.image_focales, "l'image d'avant")
        vrai(Fichiers.existe(image), "l'image d'avant gardée")
        vrai(not Fichiers.existe(r[2].dossier), 'le dossier du dessin manqué effacé')
        -- Qui refuse (ok faux, code 1) : son texte, au journal aussi.
        mode('refus')
        taperDate(p, 'debut', '')
        unTour()
        egal(FenetreSuivi.REFUS .. "« dominante » n'est pas un défaut que le Suivi compte.", p.etat)
        vrai(journal[#journal]:find('--graphiques refusé', 1, true), 'au journal')
        egal(image, p.image_focales)
    end)
end)

essai("Des créneaux autres que ceux de la fenêtre : les barres de ce graphique ne se cliquent pas, le journal le dit ; les autres, si", function()
    depart()
    mode('decale')
    ouvrirSuivi(function(p)
        unTour()
        for i = 1, 8 do
            egal(false, p['c_focales_' .. i], 'focales ' .. i)
        end
        egal(nil, FenetreSuivi.barreDu('focales', 2))
        egal(false, FenetreSuivi.cliquer('focales', 2))
        egal(true, p.c_iso_1, 'ISO : ses créneaux concordent')
        vrai(journal[1] and journal[1]:find('créneaux de focales', 1, true), 'au journal : ' .. tostring(journal[1]))
    end)
end)

-- Le relevé change, les dossiers ---------------------------------------------------------------------

essai("Le reclassement fini en arrière-plan : la fenêtre se redessine (un dessin demandé, Releve.ecrire avant) ; fermée entre-temps, ou rien de relu, non", function()
    depart()
    local reclasser = Releve.reclasser
    local relues = 3
    Releve.reclasser = function()
        reclassements[#reclassements + 1] = #recus()
        return relues
    end
    local ok, erreur = pcall(ouvrirSuivi, function()
        local taches = #S.taches
        unTour()
        egal(1, #recus(), 'le premier dessin, sans attendre le reclassement')
        egal(taches + 1, #S.taches, 'la tâche du reclassement')
        S.taches[#S.taches]()
        egal(true, FenetreSuivi.aRedessiner, 'trois familles relues : à redessiner')
        unTour()
        egal(2, #recus(), 'redessinée')
        unTour()
        egal(2, #recus(), 'une fois')
        -- Une fenêtre rouverte (une autre génération) : le reclassement de la précédente ne la touche pas.
        taches = #S.taches
        FenetreSuivi.reclasserEnFond()
        egal(taches + 1, #S.taches)
        local tache = S.taches[#S.taches]
        FenetreSuivi.generation = FenetreSuivi.generation + 1
        tache()
        FenetreSuivi.generation = FenetreSuivi.generation - 1
        egal(false, FenetreSuivi.aRedessiner, "pas pour une autre fenêtre")
    end)
    Releve.reclasser = reclasser
    assert(ok, erreur)
end)

essai("Un dessin fait de lui-même (le relevé vient d'être écrit) ne force pas l'écriture ; un grand relevé (SEUIL_GRAND originaux) ne se redessine de lui-même qu'au plus toutes les DELAI_REDESSIN_GRAND secondes ; la réponse se décode en rendant la main", function()
    depart()
    local ecrire, nombre = Releve.ecrire, Releve.nombre
    local LrTasks = S.modules.LrTasks
    local yield, pas = LrTasks.yield, FenetreSuivi.PAS_JSON
    local appels, yields = {}, 0
    Releve.ecrire = function()
        appels[#appels + 1] = #recus()
        return false
    end
    LrTasks.yield = function() yields = yields + 1 end
    FenetreSuivi.PAS_JSON = 50
    local ok, erreur = pcall(ouvrirSuivi, function(p, args)
        unTour()
        egal(1, #appels, "l'ouverture : écrit avant")
        vrai(yields >= 10, 'la réponse décodée en rendant la main : ' .. yields)
        egal('12', p.tuileTexte1, 'décodée entière')
        -- Le relevé écrit : redessiné après DELAI_REDESSIN, sans forcer l'écriture.
        Releve.version = Releve.version + 1
        FenetreSuivi.dessineLe = os.time() - FenetreSuivi.DELAI_REDESSIN
        unTour()
        egal(2, #recus(), 'redessinée')
        egal(1, #appels, "rien de forcé : elle suit une écriture")
        -- Un grand relevé (le nombre d'originaux du dernier dessin) : DELAI_REDESSIN_GRAND.
        egal(FenetreSuivi.DELAI_REDESSIN, FenetreSuivi.delaiRedessin())
        Releve.nombre = function() return FenetreSuivi.SEUIL_GRAND, 0 end
        taperDate(p, 'debut', '1er septembre 2026')
        unTour()
        egal(3, #recus(), 'une autre période')
        egal(2, #appels, 'un dessin demandé : écrit avant')
        egal(FenetreSuivi.DELAI_REDESSIN_GRAND, FenetreSuivi.delaiRedessin())
        Releve.version = Releve.version + 1
        FenetreSuivi.dessineLe = os.time() - FenetreSuivi.DELAI_REDESSIN
        unTour()
        egal(3, #recus(), 'trop tôt pour un grand relevé')
        FenetreSuivi.dessineLe = os.time() - FenetreSuivi.DELAI_REDESSIN_GRAND
        unTour()
        egal(4, #recus(), 'après DELAI_REDESSIN_GRAND')
    end)
    Releve.ecrire, LrTasks.yield, FenetreSuivi.PAS_JSON = ecrire, yield, pas
    Releve.nombre = nombre
    assert(ok, erreur)
end)

essai("Le relevé ou le carnet change pendant qu'elle est ouverte : les graphiques se refont (au plus toutes les DELAI_REDESSIN secondes) ; un dossier neuf par dessin, l'avant-dernier effacé, tous à la fermeture", function()
    depart()
    local dossiers
    ouvrirSuivi(function(p)
        unTour()
        egal(1, #recus())
        -- Le relevé écrit (une vue, une analyse) : pas avant DELAI_REDESSIN.
        Releve.version = Releve.version + 1
        unTour()
        egal(1, #recus(), 'trop tôt')
        FenetreSuivi.dessineLe = os.time() - FenetreSuivi.DELAI_REDESSIN
        unTour()
        egal(2, #recus(), 'refait')
        unTour()
        egal(2, #recus(), 'rien de plus')
        -- Le carnet changé (l'horizon et la mise au point vus par Claude) : refait aussi.
        Carnet.version = Carnet.version + 1
        FenetreSuivi.dessineLe = 0
        unTour()
        local r = recus()
        egal(3, #r)
        vrai(r[1].dossier ~= r[2].dossier and r[2].dossier ~= r[3].dossier, 'un dossier neuf par dessin')
        vrai(not Fichiers.existe(r[1].dossier), "l'avant-dernier dessin effacé")
        vrai(Fichiers.existe(r[2].dossier) and Fichiers.existe(r[3].dossier), 'les deux derniers gardés')
        egal(r[3].dossier .. '/focales.png', p.image_focales)
        dossiers = r
    end)
    for _, x in ipairs(dossiers) do
        vrai(not Fichiers.existe(x.dossier), 'effacé à la fermeture : ' .. x.dossier)
    end
    egal(0, #FenetreSuivi.dossiers)
end)

-- Les boutons de l'en-tête de la fenêtre Claude ------------------------------------------------------

essai("En-tête de la fenêtre Claude : Suivi, Publication… et Consommation… côte à côte au bout de la rangée sous « Repartir à neuf » ; chacun ouvre sa fenêtre, sans envoyer la demande tapée", function()
    local Dispo = Dispositions.dimensions()
    S.photoActive = S.photo(4961, 'DSCF4961.RAF')
    S.selection = { S.photoActive }
    local publication, consommation = require 'FenetrePublication', require 'FenetreConsommation'
    local afficher = { suivi = FenetreSuivi.afficher, publication = publication.afficher, consommation = consommation.afficher }
    local ouvertes = {}
    FenetreSuivi.afficher = function() ouvertes[#ouvertes + 1] = 'suivi' end
    publication.afficher = function() ouvertes[#ouvertes + 1] = 'publication' end
    consommation.afficher = function() ouvertes[#ouvertes + 1] = 'consommation' end
    local erreur
    S.pendantFenetre = function(args)
        local ok, e = xpcall(function()
            local _, parent = parents(args.contents)
            local suivi, pub, conso = bouton(args.contents, 'Suivi'), bouton(args.contents, 'Publication…'), bouton(args.contents, 'Consommation…')
            vrai(suivi and pub and conso, 'les trois boutons')
            local rangee = parent[suivi]
            egal(rangee, parent[pub])
            egal(rangee, parent[conso])
            local rang = {}
            for k, e2 in ipairs(rangee.args) do
                rang[e2] = k
            end
            egal(rang[suivi] + 2, rang[pub], 'Publication… à droite de Suivi')
            egal(rang[pub] + 2, rang[conso], 'Consommation… à droite de Publication…')
            egal(#rangee.args, rang[conso], 'au bout de la rangée')
            -- La rangée sous « Repartir à neuf » : la colonne de l'en-tête la porte après celle du titre.
            local colonne = parent[rangee]
            local repartir = bouton(args.contents, 'Repartir à neuf')
            egal(colonne, parent[parent[repartir]], "sous la rangée de « Repartir à neuf »")
            for _, x in ipairs({ { suivi, Dispo.boutonSuivi }, { pub, Dispo.boutonPublication }, { conso, Dispo.boutonConsommation } }) do
                local b, largeur = x[1], x[2]
                egal('square_button', b.genre)
                egal('small', b.args.size)
                egal(Fenetre.POLICES.petit, b.args.font)
                egal(largeur, b.args.width)
                vrai(Fenetre.parBouton(b.args.action), 'passe par Fenetre.bouton')
                vrai(S.montreeDansFenetre(b), 'montré')
                vrai(type(b.args.tooltip) == 'string' and b.args.tooltip ~= '', 'son infobulle')
            end
            -- Chaque clic, après une frappe sans Retour : sa fenêtre, la demande tapée ne part pas.
            local champ
            for _, v in ipairs((parents(args.contents))) do
                if v.genre == 'edit_field' and type(v.args.value) == 'table' and v.args.value.key == 'saisie' then
                    champ = v
                end
            end
            for _, b in ipairs({ suivi, pub, conso }) do
                S.taper(champ, 'Texte validé par le clic')
                S.cliquer(b)
                egal(nil, Fenetre.envoiAuto, "le clic n'envoie pas la demande")
            end
            egal('suivi publication consommation', table.concat(ouvertes, ' '))
            Fenetre.p.saisie = ''
        end, debug.traceback)
        erreur = not ok and e or nil
    end
    local ok, e = pcall(Fenetre.afficher)
    S.pendantFenetre = nil
    Fenetre.ouverte = false
    FenetreSuivi.afficher, publication.afficher, consommation.afficher = afficher.suivi, afficher.publication, afficher.consommation
    assert(ok, e)
    if erreur then
        error(erreur, 0)
    end
end)

-- Fin ----------------------------------------------------------------------------------------------

if Moteur.session then
    Moteur.session:arreter()
end
print(string.format('\n%d essais réussis, %d en échec', reussis, echecs))
if os.getenv('GARDER_ESSAI') == nil then
    S.executer('rm -rf ' .. S.q(S.home))
end
os.exit(echecs == 0 and 0 or 1)
