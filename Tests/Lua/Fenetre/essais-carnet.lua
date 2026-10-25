-- essais-carnet.lua : le carnet de progrès dans la fenêtre Claude, hors de Lightroom (LuaJIT,
-- Lightroom simulé par Simulation.lua) : l'onglet Suivi (correctif 1.3.6, à la place de Leçon ; la
-- page Carnet de progrès du fil, son entrée dans la liste des conversations et sa ligne « Demander
-- à Claude ce qu'il en pense › » sont retirées avec le volet) : le texte de sa carte
-- (Fil.texteSuivi : note, défauts mois par mois, tendances, à travailler ; coupé à la largeur de la
-- carte en 12, chaque caractère mesuré), l'onglet ouvert seulement par un clic (jamais une bascule,
-- source comprise), le résumé lu dans une tâche, la boucle qui suit Carnet.version tant que
-- l'onglet est montré, « Photos d'un défaut… » et la fenêtre des photos d'un défaut (leurs
-- constats seulement, plus les leçons d'avant le correctif 1.3.6 ; « Retirer du carnet… » par appel
-- direct), et la puce Carnet des consignes. Le registre est le vrai (Carnet.lua), rangé dans un
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
local Metriques = require 'Metriques'
local Notation = require 'Notation'
local Texte = require 'Texte'

-- Le registre des notes n'a pas de catalogue ici : aucune proposition.
local propositionVraie = Notation.proposition
Notation.proposition = function() return nil end

local Fenetre = require 'Fenetre'
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

-- La largeur du texte de la carte Suivi (D.largeurSuivi, à l'intérieur de la carte), et celle
-- qu'une ligne ne dépasse jamais (Fenetre.lignesCarte la coupe à sa marge près).
local D = Dispositions.dimensions()
local LARGEUR = D.largeurSuivi
local LARGEUR_LIGNE = LARGEUR - Fil.MARGE

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

-- Un tour de la boucle de la fenêtre (Fenetre.boucle), sans attendre : la pause de la fin du tour
-- l'arrête.
local function unTourDeBoucle()
    local LrTasks = S.modules.LrTasks
    local sleep, generation = LrTasks.sleep, Fenetre.generation
    LrTasks.sleep = function() Fenetre.generation = generation + 1000 end
    local ok, erreur = pcall(Fenetre.boucle, generation)
    LrTasks.sleep = sleep
    Fenetre.generation = generation
    vrai(ok, erreur)
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

-- Les lignes de la carte Suivi pour ce texte, coupées comme la fenêtre les coupe (Fenetre.lignesCarte,
-- en 12, l'emphase en gras 12) : chacune dans la largeur de la carte, ses balises fermées, chaque
-- caractère mesuré dans les deux polices (Metriques ; pas de barres ▁…█, U+2581 à U+2588 : il
-- faudrait remesurer les polices).
local function lignesDeLaCarte(texte)
    local lignes = Fenetre.lignesCarte(texte, LARGEUR, 'texte12', 'gras12')
    for _, l in ipairs(lignes) do
        local largeur = Fil.largeur(l, 'texte12', 'gras12')
        vrai(largeur <= LARGEUR_LIGNE, string.format('hors de la carte (%.0f pour %d) : %s', largeur, LARGEUR_LIGNE, l))
        local ouverte = false
        for fin in l:gmatch('<(/?)EM>') do
            vrai(ouverte == (fin == '/'), 'balise mal fermée : ' .. l)
            ouverte = fin == ''
        end
        vrai(not ouverte, 'balise ouverte en fin de ligne : ' .. l)
        for c in Texte.caracteres(Fil.sansBalises(l)) do
            vrai(Metriques.texte12.chasse[c] and Metriques.gras12.chasse[c], 'caractère non mesuré : ' .. c)
            vrai(not (c >= '\226\150\129' and c <= '\226\150\136' and #c == 3), 'barre dans la carte : ' .. l)
        end
    end
    return lignes
end

-- La ligne d'un défaut dans le texte de la carte (« <EM>libellé</EM> · mois n/sur · … »), et ses
-- cellules, sans les mois (« 0/1 2/2 … », « — » sans photo où il a été cherché).
local function ligneDefaut(texte, libelle)
    for ligne in (texte .. '\n'):gmatch('([^\n]*)\n') do
        if ligne:sub(1, #('<EM>' .. libelle .. '</EM>')) == '<EM>' .. libelle .. '</EM>' then
            return ligne
        end
    end
    error('ligne du défaut introuvable : ' .. libelle, 2)
end

local function cellules(ligne)
    ligne = ligne:match('</EM>(.*)$') or ligne
    local liste = {}
    for c in ligne:gmatch(' (%S+) ·') do
        liste[#liste + 1] = c
    end
    liste[#liste + 1] = ligne:match(' (%S+)$')
    return table.concat(liste, ' ')
end

local function indiceDe(lignes, test)
    for i, l in ipairs(lignes) do
        if test(l) then
            return i
        end
    end
    return nil
end

-- Les lignes d'un texte.
local function lignesDe(texte)
    local r = {}
    for ligne in (texte .. '\n'):gmatch('([^\n]*)\n') do
        r[#r + 1] = ligne
    end
    return r
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
    egal(Carnet.TITRES.carnet, Fenetre.TITRE_CARNET, 'le titre du registre, seule copie')
end)

-- Fil.texteSuivi ---------------------------------------------------------------------------------

essai('Fil.texteSuivi : note, défauts mois par mois (libellés en gras), tendances, à travailler ; chaque ligne dans la carte en 12', function()
    fabriquerType()
    local page = Carnet.resumer(os.time())
    egal(6, #page.mois)
    egal(13, page.photos)
    local texte = Fil.texteSuivi(page)
    local lignes = lignesDe(texte)
    contient(lignes[1], 'Défauts de la prise de vue mesurés par Claude sur 13 photos')
    egal('', lignes[2])
    egal('<EM>' .. Fil.MOIS_PAR_MOIS .. '</EM>', lignes[3])
    -- Un défaut par ligne, dans l'ordre du vocabulaire, son libellé en gras, puis ses mois.
    local ordre = {}
    for i = 4, 3 + #page.defauts do
        ordre[#ordre + 1] = lignes[i]:match('^<EM>(.-)</EM>')
    end
    egal("Horizon ou ligne penchée|Photo sous-exposée|Ciel ou haut de l'image brûlé|Bruit fort (ISO élevé)|Photo floue ou bougée|"
        .. "Mise au point à côté", table.concat(ordre, '|'))
    for _, m in ipairs(page.mois) do
        contient(lignes[4], ' · ' .. m.court .. ' ', 'les mois abrégés')
    end
    -- « n/sur » par mois, « — » quand le défaut n'y a pas été cherché.
    egal('0/1 2/2 1/2 1/2 0/3 0/3', cellules(ligneDefaut(texte, 'Photo floue ou bougée')), 'flou')
    egal('1/1 — — — — —', cellules(ligneDefaut(texte, 'Mise au point à côté')), 'mise au point')
    egal('0/1 0/2 1/2 0/2 0/3 1/3', cellules(ligneDefaut(texte, 'Horizon ou ligne penchée')), 'ligne penchée (angle)')
    egal('0/1 0/2 0/2 0/2 1/3 2/3', cellules(ligneDefaut(texte, "Ciel ou haut de l'image brûlé")), 'ciel brûlé')
    egal(Fil.AIDE_DEFAUTS_SUIVI, lignes[4 + #page.defauts], 'l\'aide de « Photos d\'un défaut… », sous les défauts')
    -- Ce qui progresse, ce qui recule, à travailler : intertitres en gras et puces, phrases du résumé.
    egal(1, #page.progresse)
    egal(1, #page.recule)
    local progresse = indiceDe(lignes, function(l) return l == '<EM>Ce qui progresse</EM>' end)
    vrai(progresse, 'Ce qui progresse')
    egal('', lignes[progresse - 1], 'une ligne vide avant chaque intertitre')
    egal('•  ' .. page.progresse[1].texte, lignes[progresse + 1])
    local recule = indiceDe(lignes, function(l) return l == '<EM>Ce qui recule</EM>' end)
    vrai(recule and recule > progresse, 'Ce qui recule, après')
    contient(lignes[recule + 1], "•  Ciel ou haut de l'image brûlé")
    local travailler = indiceDe(lignes, function(l) return l == '<EM>À travailler à la prochaine sortie</EM>' end)
    vrai(travailler and travailler > recule, 'À travailler, ensuite')
    contient(lignes[travailler + 1], '•  ' .. "Ciel ou haut de l'image brûlé : 3 photos sur 6 (50 %)")
    egal('    À la prise de vue : Exposer pour le ciel', lignes[travailler + 2]:sub(1, #'    À la prise de vue : Exposer pour le ciel'),
        'le conseil retiré sous sa puce')
    -- Plus de ligne d'action, ni la leçon d'avant de 1024.
    vrai(not texte:find('Demander à Claude', 1, true), "plus de « Demander à Claude ce qu'il en pense › »")
    vrai(not texte:find('Horizon un peu bas', 1, true) and not texte:find('Leçon', 1, true), "rien de la leçon d'avant")
    -- Dans la carte : chaque ligne tient, ses balises fermées, chaque caractère mesuré ; le résumé se
    -- lit en deux pages au plus.
    local carte = lignesDeLaCarte(texte)
    vrai(#carte >= #lignes, 'les lignes de la carte')
    vrai(#carte <= 2 * D.suiviLignes, string.format('deux pages au plus (%d lignes pour %d)', #carte, D.suiviLignes))
end)

essai('Fil.texteSuivi : vide, en lecture, en erreur ; sans tendance ; années ; libellé long coupé dans la carte ; balises du registre retirées', function()
    -- Vide : la note qui explique, ni défauts ni tendances.
    fabriquer({})
    local vide = Fil.texteSuivi(Carnet.resumer(os.time()))
    contient(vide, 'Le carnet se remplit tout seul')
    vrai(not vide:find('<EM>', 1, true), 'ni mois par mois ni intertitres : ' .. vide)
    lignesDeLaCarte(vide)
    -- En lecture (nil), puis en erreur.
    egal(Fil.LECTURE_CARNET, Fil.texteSuivi(nil))
    egal("Le carnet de progrès ne s'est pas lu : carnet.json illisible", Fil.texteSuivi({ erreur = 'carnet.json illisible' }))
    -- Fait main : deux années (les mois les disent), un libellé trop long, un libellé et une note qui
    -- portent une balise (retirée : seules celles de la carte restent), ni tendance ni défaut à
    -- travailler (leurs phrases du résumé), une remarque.
    local long = string.rep('Défaut au libellé très long ', 3)
    local page = {
        vide = false, photos = 3, note = 'Note du <EM>résumé</EM>.', remarque = 'Seulement 3 photos.',
        titres = Carnet.TITRES,
        mois = { { cle = '2025-12', annee = 2025, numero = 12, court = 'déc.' }, { cle = '2026-01', annee = 2026, numero = 1, court = 'janv.' } },
        defauts = {
            { code = 'flou', libelle = 'Photo <EM>floue</EM> ou bougée', par_mois = { { n = 1, sur = 2 }, { n = 0, sur = 1 } } },
            { code = 'long', libelle = long, par_mois = { { n = 0, sur = 0 }, { n = 12, sur = 13 } } },
        },
        progresse = {}, recule = {}, a_travailler = {},
        aucune_tendance = 'Pas encore de tendance.', rien_a_travailler = 'Rien ne revient.',
    }
    local texte = Fil.texteSuivi(page)
    local lignes = lignesDe(texte)
    egal('Note du résumé.', lignes[1])
    egal('Seulement 3 photos.', lignes[2])
    egal('<EM>Photo floue ou bougée</EM> · déc. 2025 1/2 · janv. 2026 0/1', lignes[5])
    local libelle = Texte.nettoyer(long)
    egal('<EM>' .. libelle .. '</EM> · déc. 2025 — · janv. 2026 12/13', lignes[6])
    -- Le libellé long se coupe dans la carte, sa balise fermée et rouverte d'une ligne à l'autre.
    local carte = lignesDeLaCarte(texte)
    local debut = indiceDe(carte, function(l) return l:find('Défaut au libellé', 1, true) ~= nil end)
    vrai(debut and carte[debut + 1]:sub(1, 4) == '<EM>', 'coupé sur deux lignes, en gras : ' .. tostring(carte[debut + 1]))
    local progresse = indiceDe(lignes, function(l) return l == '<EM>Ce qui progresse</EM>' end)
    egal('Pas encore de tendance.', lignes[progresse + 1])
    vrai(not indiceDe(lignes, function(l) return l == '<EM>Ce qui recule</EM>' end), 'pas de « Ce qui recule » vide')
    local travailler = indiceDe(lignes, function(l) return l == '<EM>À travailler à la prochaine sortie</EM>' end)
    egal('Rien ne revient.', lignes[travailler + 1])
    -- Ce qui recule seul : sans « Ce qui progresse » vide au-dessus.
    page.recule = { { code = 'flou', texte = 'Photo floue ou bougée : 0 % puis 40 %.' } }
    local seul = lignesDe(Fil.texteSuivi(page))
    vrai(not indiceDe(seul, function(l) return l == '<EM>Ce qui progresse</EM>' end), 'pas de « Ce qui progresse » vide')
    local recule = indiceDe(seul, function(l) return l == '<EM>Ce qui recule</EM>' end)
    egal('•  Photo floue ou bougée : 0 % puis 40 %.', seul[recule + 1])
end)

-- L'onglet Suivi dans la fenêtre -----------------------------------------------------------------

essai("Onglet Suivi : le dernier segment, ouvert seulement par un clic (jamais une bascule, source comprise) ; le résumé lu dans une tâche, la carte page par page", function()
    local ordre = {}
    for _, o in ipairs(D.onglets) do
        ordre[#ordre + 1] = o.valeur
    end
    egal('apercu focus proposition notation suivi', table.concat(ordre, ' '), 'Suivi à la place de Leçon, en dernier')
    egal('suivi', D.ongletSuivi)
    egal('Suivi', D.onglets[5].titre)
    egal('seg-suivi', D.onglets[5].image)
    -- Aucun onglet où la fenêtre bascule d'elle-même n'est Suivi.
    for _, cle in ipairs({ 'ongletParDefaut', 'ongletProposition', 'ongletNotation', 'ongletEtape', 'ongletFocus' }) do
        vrai(D[cle] ~= 'suivi', cle .. ' : jamais Suivi')
    end
    -- Ni Fenetre.lua ni aucun autre fichier du module ne le choisissent d'eux-mêmes.
    for _, nom in ipairs({ 'Fenetre.lua', 'Vues.lua', 'Dispositions.lua', 'Moteur.lua', 'Conversation.lua', 'Carnet.lua' }) do
        local source = assert(Fichiers.lire(S.plugin .. '/' .. nom), nom)
        for _, morceau in ipairs({ 'choisirOnglet(T.ongletSuivi', 'choisirOnglet(Fenetre.T.ongletSuivi', "choisirOnglet('suivi'",
            'p.onglet = T.ongletSuivi', "p.onglet = 'suivi'" }) do
            vrai(not source:find(morceau, 1, true), nom .. ' : ' .. morceau)
        end
    end
    fabriquerType()
    photoActive(53636309, 'DSCF4961.RAF')
    Moteur.courante = conversation('Lac au matin')
    local choisis = {}
    local choisir = Fenetre.choisirOnglet
    Fenetre.choisirOnglet = function(valeur)
        choisis[#choisis + 1] = tostring(valeur)
        return choisir(valeur)
    end
    local ok, erreur = pcall(ouvrirFenetre, function(p, args)
        -- La carte : son titre en gras 12, son texte en 12 (l'emphase en gras 12), D.suiviLignes lignes.
        local texte, titre
        for _, v in ipairs(vues(args.contents)) do
            local t = v.args.title
            if v.genre == 'static_text' and type(t) == 'table' and t.key == 'suiviTexte' then
                texte = v
            elseif v.genre == 'static_text' and type(t) == 'table' and t.key == 'suiviTitre' then
                titre = v
            end
        end
        vrai(texte and titre, 'la carte Suivi')
        egal(Fenetre.POLICES.texte12, texte.args.font)
        egal(Fenetre.POLICES.gras12, texte.args.emphasis_font)
        egal(Fenetre.COULEURS.texte, texte.args.emphasis_color)
        egal(D.carte, texte.args.width)
        egal(D.suiviLignes, texte.args.height_in_lines)
        egal(Fenetre.POLICES.gras12, titre.args.font)
        egal('gras12', Fenetre.CARTES.suivi.emphase)
        -- À l'ouverture : Note ; rien de lu, la carte vide.
        egal('notation', p.onglet)
        egal(nil, Fenetre.pageSuivi)
        egal('', p.suiviTexte)
        egal(false, p.suiviADefauts)
        egal('Carnet de progrès', p.suiviTitre)
        -- Un clic sur le segment : l'onglet, « Lecture… », puis le résumé lu dans une tâche.
        local taches = #S.taches
        segment('Suivi')
        egal('suivi', p.onglet)
        egal(taches + 1, #S.taches, 'le résumé se lit dans une tâche')
        egal(Fil.LECTURE_CARNET, p.suiviTexte)
        lancerTaches(taches)
        local page = Fenetre.pageSuivi
        vrai(type(page) == 'table' and page.photos == 13, 'le résumé lu')
        egal(Carnet.version, Fenetre.versionSuivi)
        local attendues = Fenetre.lignesCarte(Fil.texteSuivi(page), D.largeurSuivi, 'texte12', 'gras12')
        local premiere = {}
        for i = 1, math.min(#attendues, D.suiviLignes) do
            premiere[i] = attendues[i]
        end
        egal(table.concat(premiere, '\n'), p.suiviTexte, 'la première page de la carte')
        egal(true, p.suiviADefauts)
        egal(#attendues > D.suiviLignes, p.suiviDescend)
        egal(false, p.suiviMonte)
        -- Page par page (une carte plus courte) : ▼ descend d'une page moins une ligne, la place se
        -- garde quand le résumé se relit pareil, ▲ remonte.
        local T = Fenetre.T
        local hauteur = T.suiviLignes
        T.suiviLignes = 10
        Fenetre.rafraichirSuivi()
        egal(true, p.suiviDescend)
        Fenetre.defilerTexte('suivi', 1)
        egal(attendues[10], lignesDe(p.suiviTexte)[1], '▼')
        egal(true, p.suiviMonte)
        Fenetre.rafraichirSuivi()
        egal(attendues[10], lignesDe(p.suiviTexte)[1], 'la place gardée')
        Fenetre.defilerTexte('suivi', -1)
        egal(attendues[1], lignesDe(p.suiviTexte)[1], '▲')
        T.suiviLignes = hauteur
        Fenetre.rafraichirSuivi()
        -- L'aperçu de l'onglet est celui de la photo active (pas d'aperçu à lui).
        egal(nil, Fenetre.apercuOnglet.suivi)
        -- Un autre onglet, puis Suivi de nouveau : un vrai clic relit.
        segment('Note')
        local avant = #S.taches
        segment('Suivi')
        egal(avant + 1, #S.taches, 'un vrai clic relit')
        lancerTaches(avant)
        -- Ce qui arrive de Claude (une note, une proposition) bascule vers son onglet, jamais vers Suivi.
        segment('Note')
        Fenetre.choisirOnglet(D.ongletProposition)
        Fenetre.choisirOnglet(D.ongletNotation)
        egal('notation', p.onglet)
    end)
    Fenetre.choisirOnglet = choisir
    assert(ok, erreur)
    for _, v in ipairs(choisis) do
        vrai(v ~= 'suivi', 'une bascule vers Suivi : ' .. table.concat(choisis, ', '))
    end
end)

essai("Boucle : le registre change (abonnement, Carnet.version), la carte se relit si l'onglet Suivi est montré ; caché, rien ; désabonnée à la fermeture", function()
    fabriquerType()
    Moteur.courante = conversation('Lac au matin')
    ouvrirFenetre(function(p)
        local taches = #S.taches
        egal('function', type(Carnet.observateurs.fenetre), 'abonnée')
        -- Onglet caché : un changement du registre ne fait rien lire.
        Carnet.signaler('constat')
        egal(true, Fenetre.aRafraichirSuivi, "l'abonnement l'a dit")
        unTourDeBoucle()
        egal(nil, Fenetre.pageSuivi, 'rien lu, onglet caché')
        segment('Suivi')
        lancerTaches(taches)
        egal(13, Fenetre.pageSuivi.photos)
        egal(false, Fenetre.aRafraichirSuivi)
        -- Un retrait (d'un autre client du connecteur, ici le registre lui-même) : la carte se relit au
        -- tour suivant.
        local version = Carnet.version
        Carnet.commande({ action = 'retirer', photos = { 1001 } })
        vrai(Carnet.version > version, 'nouvelle version')
        egal(true, Fenetre.aRafraichirSuivi)
        unTourDeBoucle()
        egal(12, Fenetre.pageSuivi.photos, 'carte relue')
        egal(false, Fenetre.aRafraichirSuivi)
        egal(Carnet.version, Fenetre.versionSuivi)
        contient(p.suiviTexte, 'sur 12 photos')
        -- La version seule suffit aussi (un changement sans abonnement).
        Carnet.oublier()
        Fenetre.versionSuivi = Carnet.version - 1
        local lue = Fenetre.pageSuivi
        unTourDeBoucle()
        vrai(Fenetre.pageSuivi ~= lue, 'relue par la version')
        -- Caché de nouveau : une version nouvelle ne fait rien lire.
        segment('Note')
        Fenetre.versionSuivi = -1
        lue = Fenetre.pageSuivi
        unTourDeBoucle()
        egal(lue, Fenetre.pageSuivi, 'caché : rien')
        -- Un résumé qui ne se lit pas : la carte le dit, la boucle ne le relit pas sans fin.
        local avant = #S.taches
        segment('Suivi')
        lancerTaches(avant)
        local resumer = Carnet.resumer
        Carnet.resumer = function() error('carnet.json illisible', 0) end
        Fenetre.versionSuivi = -1
        unTourDeBoucle()
        Carnet.resumer = resumer
        egal('carnet.json illisible', Fenetre.pageSuivi.erreur)
        egal(Carnet.version, Fenetre.versionSuivi)
        egal("Le carnet de progrès ne s'est pas lu : carnet.json illisible", p.suiviTexte)
        egal(false, p.suiviADefauts)
        oublierTaches(taches)
    end)
    egal(nil, Carnet.observateurs.fenetre, 'désabonnée à la fermeture')
end)

-- Photos d'un défaut -------------------------------------------------------------------------------

essai("« Photos d'un défaut… » : la liste des défauts du résumé (tables neuves), puis la fenêtre des photos du défaut choisi ; sans défaut, grisé et rien", function()
    fabriquerType()
    Moteur.courante = conversation('Lac au matin')
    ouvrirFenetre(function(p, args)
        local taches = #S.taches
        local bouton
        for _, v in ipairs(vues(args.contents)) do
            if S.BOUTONS[v.genre] and v.args.title == "Photos d'un défaut…" then
                bouton = v
            end
        end
        vrai(bouton, "« Photos d'un défaut… » sous la carte Suivi")
        egal('square_button', bouton.genre)
        egal(26, S.bezelVisible(bouton))
        egal('suiviADefauts', bouton.args.enabled.key)
        egal(D.photosDefaut, bouton.args.width)
        vrai(Fenetre.parBouton(bouton.args.action), 'passe par Fenetre.bouton')
        -- Avant la lecture : grisé, et rien sans résumé.
        egal(false, p.suiviADefauts)
        local dialogues = #S.dialogues
        egal(false, Fenetre.choisirDefaut())
        egal(dialogues, #S.dialogues)
        segment('Suivi')
        lancerTaches(taches)
        egal(true, p.suiviADefauts)
        -- Dany choisit le ciel brûlé, puis ferme la fenêtre de ses photos.
        local presenter = S.modules.LrDialogs.presentModalDialog
        local recus = {}
        S.modules.LrDialogs.presentModalDialog = function(d)
            S.dialogues[#S.dialogues + 1] = d
            recus[#recus + 1] = d
            if #recus == 1 then
                d.contents.args.bind_to_object.choix = { 'ciel_brule' }
            end
            return 'ok'
        end
        local avant = #S.taches
        S.cliquer(bouton)
        egal(avant + 1, #S.taches, 'dans une tâche')
        local ok, erreur = pcall(lancerTaches, avant)
        S.modules.LrDialogs.presentModalDialog = presenter
        assert(ok, erreur)
        egal(2, #recus, 'la liste des défauts, puis la fenêtre des photos')
        egal("Carnet de progrès · Photos d'un défaut", recus[1].title)
        egal('Voir ses photos', recus[1].actionVerb)
        local liste = vueDe(recus[1].contents, 'simple_list')
        S.neuve(liste.args.items, 'défauts du carnet')
        egal(#Fenetre.pageSuivi.defauts, #liste.args.items)
        egal('horizon_penche', liste.args.items[1].value, "dans l'ordre du résumé")
        egal("Ciel ou haut de l'image brûlé · 3 photos sur 13", liste.args.items[3].title)
        egal('Mise au point à côté · 1 photo sur 1', liste.args.items[6].title)
        egal("Carnet de progrès · Ciel ou haut de l'image brûlé", recus[2].title)
        -- Annulé : la liste seule.
        S.reponseModal = 'cancel'
        dialogues = #S.dialogues
        egal(false, Fenetre.choisirDefaut())
        egal(dialogues + 1, #S.dialogues, 'la liste seule')
        S.reponseModal = nil
        -- Sans défaut (un carnet vide) : grisé, rien.
        fabriquer({})
        Fenetre.versionSuivi = -1
        unTourDeBoucle()
        egal(false, p.suiviADefauts)
        dialogues = #S.dialogues
        egal(false, Fenetre.choisirDefaut())
        egal(dialogues, #S.dialogues)
        oublierTaches(taches)
    end)
end)

essai("La fenêtre des photos d'un défaut : éléments neufs, la plus récente d'abord, leurs constats sans la leçon d'avant ; une ligne penchée en degrés ; une mesure seule", function()
    fabriquerType()
    Moteur.courante = conversation('Lac au matin')
    ouvrirFenetre(function()
        local taches = #S.taches
        segment('Suivi')
        lancerTaches(taches)
        local dialogues = #S.dialogues
        egal(false, Fenetre.montrerDefaut('ciel_brule'), 'Fermer')
        egal(dialogues + 1, #S.dialogues)
        local d = S.dialogues[#S.dialogues]
        egal("Carnet de progrès · Ciel ou haut de l'image brûlé", d.title)
        egal('Fermer', d.actionVerb)
        egal('Retirer du carnet…', d.otherVerb)
        local liste = vueDe(d.contents, 'simple_list')
        S.neuve(liste.args.items, 'photos du défaut')
        egal(3, #liste.args.items)
        -- La plus récente d'abord, puis par fichier : 1024 et 1025 ce mois-ci, 1021 le mois d'avant.
        egal(1024, liste.args.items[1].value)
        egal(1025, liste.args.items[2].value, "l'original, même mesuré sur sa copie virtuelle")
        egal(1021, liste.args.items[3].value)
        egal('DSCF1024.RAF · ciel brûlé : 4,2 % du tiers haut en blanc pur', liste.args.items[1].title:match('DSCF.*$'),
            "le constat seul, plus « leçon » (correctif 1.3.6)")
        contient(liste.args.items[3].title, Carnet.MOIS[tonumber(moisIl(1):sub(6, 7))])
        local textes = {}
        for _, v in ipairs(vues(d.contents)) do
            if v.genre == 'static_text' then
                textes[#textes + 1] = v.args.title
            end
        end
        contient(table.concat(textes, '\n'), "3 photos dans les mois du carnet, la plus récente d'abord.")
        contient(table.concat(textes, '\n'), 'À la prise de vue : Exposer pour le ciel')
        -- La photo choisie, 1024 d'abord ; sa leçon d'avant ne se montre plus (correctif 1.3.6).
        local q = d.contents.args.bind_to_object
        egal(1024, q.choix[1])
        egal(nil, q.lecon)
        egal(nil, vueDe(d.contents, 'edit_field'), 'plus de champ de la leçon')
        vrai(not table.concat(textes, '\n'):find('Leçon', 1, true), 'rien de la leçon')
        -- Un défaut cherché mais jamais trouvé : la fenêtre le dit, sans liste ni retrait.
        Fenetre.montrerDefaut('bruit')
        local vide = S.dialogues[#S.dialogues]
        egal(nil, vide.otherVerb)
        egal(nil, vueDe(vide.contents, 'simple_list'))
        contient(vueDe(vide.contents, 'static_text').args.title, "Aucune photo n'a ce défaut")
        -- Une ligne penchée (l'angle rangé dans l'entrée, sans texte) : son inclinaison en degrés.
        Fenetre.montrerDefaut('horizon_penche')
        local angles = vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items
        egal(2, #angles)
        contient(angles[1].title, 'DSCF1026.RAF · ligne penchée de 1,2°')
        contient(angles[2].title, 'DSCF1014.RAF · ligne penchée de 0,8°')
        egal('mars 2026 · DSCF0001.RAF · ligne penchée de 1,3°', Fenetre.textePhotoDuDefaut({ mois_libelle = 'mars 2026',
            fichier = 'DSCF0001.RAF', mesure = -1.26, angle = true }))
        -- Une seule photo : pas de « la plus récente d'abord ».
        Fenetre.montrerDefaut('mise_au_point')
        egal('1 photo dans les mois du carnet.', vueDe(S.dialogues[#S.dialogues].contents, 'static_text').args.title)
        -- Une autre mesure sans texte se dit telle quelle (mise au point, 8,5).
        contient(vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items[1].title, 'DSCF1001.RAF · mesure : 8,5')
        egal('mars 2026 · DSCF1001.RAF · mesure : 8,5', Fenetre.textePhotoDuDefaut({ mois_libelle = 'mars 2026', fichier = 'DSCF1001.RAF',
            mesure = 8.5 }))
        -- L'angle d'une entrée ne vaut que pour son code : la mise au point de la même photo reste
        -- une mesure.
        fabriquer({ entree(1101, moisIl(0), CHERCHES, { 'mise_au_point' }, { angle = { le = 1101, photo = 1101, inclinaison = 2,
            code = 'horizon_penche', source = 'measure_angle' } }) })
        Fenetre.montrerDefaut('mise_au_point')
        egal('DSCF1101.RAF · mesure : 8,5', vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items[1].title:match('DSCF.*$'))
        Fenetre.montrerDefaut('horizon_penche')
        egal('DSCF1101.RAF · ligne penchée de 2,0°', vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items[1].title:match('DSCF.*$'))
        fabriquerType()
        egal('mars 2026 · photo 77', Fenetre.textePhotoDuDefaut({ mois_libelle = 'mars 2026', original = 77 }))
        oublierTaches(taches)
    end)
end)

essai('« Retirer du carnet… » : la photo choisie, après confirmation, par appel direct au registre avec l\'id de l\'original ; la carte se relit', function()
    fabriquerType()
    Moteur.courante = conversation('Lac au matin')
    ouvrirFenetre(function(p)
        local taches = #S.taches
        segment('Suivi')
        lancerTaches(taches)
        egal(13, Fenetre.pageSuivi.photos)
        local commande, recues = Carnet.commande, {}
        Carnet.commande = function(params)
            recues[#recues + 1] = params
            return commande(params)
        end
        local presenter = S.modules.LrDialogs.presentModalDialog
        -- Dany choisit la deuxième photo (1025, mesurée sur sa copie 5025), puis Retirer du carnet….
        S.modules.LrDialogs.presentModalDialog = function(args)
            S.dialogues[#S.dialogues + 1] = args
            args.contents.args.bind_to_object.choix = { 1025 }
            return 'other'
        end
        -- Annulé à la confirmation : rien ne sort.
        S.reponseConfirm = 'cancel'
        egal(false, Fenetre.montrerDefaut('ciel_brule'))
        egal(0, #recues)
        vrai(Carnet.entree(1025), 'toujours au carnet')
        contient(S.confirmation[1], 'Retirer DSCF1025.RAF du carnet de progrès ?')
        contient(S.confirmation[2], 'La photo et ses retouches ne changent pas.')
        -- Confirmé : retirée par Carnet.commande, l'identifiant de l'original.
        S.reponseConfirm = 'ok'
        local version = Carnet.version
        egal(true, Fenetre.montrerDefaut('ciel_brule'))
        egal(1, #recues)
        egal('retirer', recues[1].action)
        egal(1025, recues[1].photos[1])
        egal(1, #recues[1].photos)
        egal(nil, Carnet.entree(1025), 'retirée')
        vrai(Carnet.entree(1024), 'les autres restent')
        vrai(Carnet.version > version, 'la carte se relira')
        egal('DSCF1025.RAF est retirée du carnet de progrès.', p.message)
        -- Fermer : rien.
        S.modules.LrDialogs.presentModalDialog = function(args)
            S.dialogues[#S.dialogues + 1] = args
            return 'ok'
        end
        egal(false, Fenetre.montrerDefaut('ciel_brule'))
        egal(1, #recues)
        S.modules.LrDialogs.presentModalDialog = presenter
        Carnet.commande = commande
        S.reponseConfirm = nil
        -- La carte, montrée, se relit au tour suivant de la boucle.
        unTourDeBoucle()
        egal(12, Fenetre.pageSuivi.photos, 'la carte relue')
        oublierTaches(taches)
    end)
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
