-- essais-carnet.lua : la page Carnet de progrès de la fenêtre Claude (1.3, lot 16), hors de
-- Lightroom (LuaJIT, Lightroom simulé par Simulation.lua) : l'entrée en tête de la liste des
-- conversations, la page dans la grille du fil (Fil.lignesCarnet : genres existants, tableau mono
-- aligné par des espaces, tendances, à travailler, ligne d'action), son ouverture et son retour au
-- fil, les gardes (Renommer…, Supprimer…), la boucle qui suit Carnet.version, la fenêtre des
-- photos d'un défaut (leçons, « Retirer du carnet… » par appel direct), « Demander à Claude ce
-- qu'il en pense » de bout en bout par relais.sh et faux-claude.sh, Accepter et Je le fais qui
-- quittent la page, et la puce Carnet des consignes. Le registre est le vrai (Carnet.lua), rangé
-- dans un dossier personnel temporaire ; ni Claude, ni quota.
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
prefs.propositionAOuverture = false
prefs.nouvelleParPhoto = false

-- Complément de la simulation, pour cet essai : le chemin du catalogue ouvert (le carnet range
-- chaque catalogue sous le sien ; sans lui, il se lit vide).
local CATALOGUE = '/Users/test/Images/Catalogue.lrcat'
S.catalogue.getPath = function() return CATALOGUE end

-- Le faux Claude Code dès le départ (une demande partie par erreur ne lance jamais le vrai), et
-- une petite image JPEG (en base64) pour son résultat d'outil (cas par défaut).
local dossierTests = S.lireCommande('cd ' .. S.q((arg and arg[0] or ''):match('(.*/)') or '.') .. ' && pwd -P'):gsub('%s+$', '')
prefs.cheminClaude = dossierTests .. '/faux-claude.sh'
prefs.cheminConnecteur = '/bin/echo'
local imageB64 = S.home .. '/image.b64'
S.executer('/usr/bin/sips -s format jpeg -z 60 90 ' .. S.q(S.plugin .. '/vide-320.png') .. ' --out ' .. S.q(S.home .. '/image.jpg') .. ' >/dev/null 2>&1')
S.executer('/usr/bin/base64 -i ' .. S.q(S.home .. '/image.jpg') .. ' -o ' .. S.q(imageB64))
local env = 'FAUX_IMAGE_B64=' .. S.q(imageB64) .. ' '
local executerOriginal = S.modules.LrTasks.execute
S.modules.LrTasks.execute = function(commande)
    if commande:find('relais.sh', 1, true) then
        commande = env .. commande
    end
    return executerOriginal(commande)
end

-- La largeur du texte du fil (Fenetre.largeurTexte), et celle qu'une ligne ne dépasse jamais.
local D = Dispositions.dimensions()
local LARGEUR = D.fil - 20
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

-- Une conversation qui a des messages, en tête de la liste.
local function conversation(titre)
    local c = Conversation.nouvelle()
    Conversation.ajouterDemande(c, titre)
    Conversation.renommer(c, titre)
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
        vue = { le = id, photo = id, cherches = cherches, defauts = defauts }, lecons = {} }
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

-- La leçon rangée avec la photo 1024 (axes du module : lumiere, couleur, composition).
local LECON_1024 = { photo = 1024, uuid = 'uuid-1024', fichier = 'DSCF1024.RAF', le = 5, defauts = {}, indices = {}, points = {
    { axe = 'lumiere', manque = "Ciel brûlé à 4 %.", prise_de_vue = "Exposer pour le ciel." },
    { axe = 'couleur', prise_de_vue = "Balance des blancs juste : à refaire." },
    { axe = 'composition', manque = "Horizon un peu bas.", prise_de_vue = "Horizon au tiers haut." },
} }

-- Six mois de prise de vue : le flou recule (4 photos sur 6 avant, aucune sur les 6 récentes : il
-- progresse), le ciel brûlé revient (3 sur 6 récentes, aucune avant : il recule, et il est à
-- travailler) ; une mise au point manquée seule, cinq mois plus tôt ; une ligne penchée (angle)
-- avant et une ce mois-ci (sans tendance) ; la photo 1025 mesurée sur sa copie virtuelle (5025) ;
-- une leçon pour 1024.
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

-- Chaque ligne tient dans la largeur, avec un genre et une icône que la fenêtre connaît, et sans
-- élément de conversation.
local function verifierLignes(lignes)
    local genres, icones = {}, {}
    for _, s in ipairs(Fenetre.STYLES) do
        for g in pairs(s.genres) do
            genres[g] = true
        end
    end
    for _, ic in ipairs(Fenetre.ICONES) do
        icones[ic.cle] = true
    end
    for _, l in ipairs(lignes) do
        vrai(genres[l.genre] and Fil.polices[l.genre], 'genre inconnu de la fenêtre : ' .. tostring(l.genre))
        vrai(l.icone == nil or icones[l.icone], 'icône inconnue de la fenêtre : ' .. tostring(l.icone))
        vrai(Fil.largeur(l.texte, Fil.polices[l.genre]) <= LARGEUR_LIGNE,
            string.format('hors de la largeur (%.0f pour %d) : %s', Fil.largeur(l.texte, Fil.polices[l.genre]), LARGEUR_LIGNE, l.texte))
        egal(nil, l.element, "une ligne de la page n'est pas d'une conversation")
        -- Pas de barres ▁…█ (U+2581 à U+2588) : il faudrait remesurer les polices.
        for c in Texte.caracteres(l.texte) do
            vrai(not (c >= '\226\150\129' and c <= '\226\150\136' and #c == 3), 'barre dans la page : ' .. l.texte)
        end
    end
end

-- Les rangées du tableau (lignes `outil`) : même largeur mesurée dans la police mono, chaque
-- caractère mesuré (Metriques.mono), l'en-tête sans défaut, les autres avec le leur.
local function rangees(lignes)
    local liste = {}
    for _, l in ipairs(lignes) do
        if l.genre == 'outil' then
            liste[#liste + 1] = l
        end
    end
    vrai(#liste >= 2, 'un en-tête et des rangées')
    local largeur = Fil.largeur(liste[1].texte, 'mono')
    for i, l in ipairs(liste) do
        egal(largeur, Fil.largeur(l.texte, 'mono'), 'rangée alignée : ' .. l.texte)
        egal(Texte.longueur(liste[1].texte), Texte.longueur(l.texte), 'même nombre de caractères : ' .. l.texte)
        for c in Texte.caracteres(l.texte) do
            vrai(Metriques.mono.chasse[c], 'caractère non mesuré dans la police mono : ' .. c)
        end
        if i == 1 then
            egal(nil, l.defaut, "l'en-tête ne s'ouvre pas")
        else
            vrai(type(l.defaut) == 'string', 'rangée sans défaut : ' .. l.texte)
        end
    end
    return liste
end

local function rangeeDe(liste, code)
    for _, l in ipairs(liste) do
        if l.defaut == code then
            return l
        end
    end
    error('rangée introuvable : ' .. code, 2)
end

-- Les cellules d'une rangée, sans le libellé (colonnes séparées par Fil.ECART_COLONNES espaces).
local function cellules(texte)
    local reste = texte:match('^.-%s%s%s+(.*)$') or ''
    local liste = {}
    for c in reste:gmatch('%S+') do
        liste[#liste + 1] = c
    end
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

Moteur.charger()

-- Liste des conversations --------------------------------------------------------------------------

essai("Liste : l'entrée « Carnet de progrès » en tête (table neuve) ; la recherche la trouve ou l'écarte", function()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    local items = Fenetre.elementsListe('')
    S.neuve(items, 'liste')
    egal(Fenetre.CARNET, items[1].value)
    egal('Carnet de progrès', items[1].title)
    egal(Carnet.TITRES.carnet, Fenetre.TITRE_CARNET, 'le titre du registre, seule copie')
    vrai(Fenetre.CARNET:sub(1, #'§') ~= '§', "pas la marque d'un en-tête")
    egal(lac.id, items[3].value, 'puis les en-têtes et les conversations')
    egal(1, #(function()
        local n = {}
        for _, x in ipairs(items) do
            if x.value == Fenetre.CARNET then
                n[#n + 1] = x
            end
        end
        return n
    end)(), 'une seule fois')
    egal(Fenetre.CARNET, Fenetre.elementsListe('carnet')[1].value)
    egal(Fenetre.CARNET, Fenetre.elementsListe('PROGRES')[1].value, 'sans casse ni accent')
    local surLac = Fenetre.elementsListe('lac')
    vrai(surLac[1].value ~= Fenetre.CARNET, 'une recherche sans rapport l\'écarte')
    egal(0, #Fenetre.elementsListe('zzzz'))
end)

-- Fil.lignesCarnet --------------------------------------------------------------------------------

essai('Fil.lignesCarnet : titre, note, tableau mono aligné, tendances, à travailler, ligne d\'action ; genres existants', function()
    fabriquerType()
    local page = Carnet.resumer(os.time())
    egal(6, #page.mois)
    local lignes = Fil.lignesCarnet(page, LARGEUR, Fenetre.TITRE_CARNET)
    verifierLignes(lignes)
    egal('titre', lignes[1].genre)
    egal('Carnet de progrès', lignes[1].texte)
    egal('note', lignes[2].genre)
    egal('note', lignes[2].icone)
    contient(lignes[2].texte, 'Défauts de la prise de vue mesurés par Claude sur 13 photos')
    -- Le tableau : l'en-tête, puis une rangée par défaut cherché, dans l'ordre du vocabulaire.
    local tableau = rangees(lignes)
    egal(1 + #page.defauts, #tableau)
    local codes = {}
    for i = 2, #tableau do
        codes[#codes + 1] = tableau[i].defaut
    end
    egal('horizon_penche sous_exposition ciel_brule bruit flou mise_au_point', table.concat(codes, ' '))
    vrai(tableau[1].texte:sub(1, #'Défaut') == 'Défaut', tableau[1].texte)
    for _, m in ipairs(page.mois) do
        contient(tableau[1].texte, m.court, 'en-tête des mois')
    end
    -- « n/sur » par mois, « — » quand le défaut n'y a pas été cherché.
    egal('0/1 2/2 1/2 1/2 0/3 0/3', cellules(rangeeDe(tableau, 'flou').texte), 'flou')
    egal('1/1 — — — — —', cellules(rangeeDe(tableau, 'mise_au_point').texte), 'mise au point')
    egal('0/1 0/2 1/2 0/2 0/3 1/3', cellules(rangeeDe(tableau, 'horizon_penche').texte), 'ligne penchée (angle)')
    egal(1, #page.progresse)
    egal(1, #page.recule)
    egal('0/1 0/2 0/2 0/2 1/3 2/3', cellules(rangeeDe(tableau, 'ciel_brule').texte), 'ciel brûlé')
    contient(rangeeDe(tableau, 'ciel_brule').texte, "Ciel ou haut de l'image brûlé")
    local aide = indiceDe(lignes, function(l) return l.texte == Fil.AIDE_TABLEAU_CARNET end)
    vrai(aide and lignes[aide - 1].genre == 'outil', "l'aide du tableau juste dessous")
    -- Ce qui progresse, ce qui recule, à travailler : titres et puces du résumé, phrases reprises.
    local progresse = indiceDe(lignes, function(l) return l.genre == 'titre' and l.texte == 'Ce qui progresse' end)
    vrai(progresse, 'Ce qui progresse')
    egal('claude', lignes[progresse + 1].genre)
    egal('•  ' .. page.progresse[1].texte:sub(1, 12), lignes[progresse + 1].texte:sub(1, #'•  ' + 12))
    local recule = indiceDe(lignes, function(l) return l.genre == 'titre' and l.texte == 'Ce qui recule' end)
    vrai(recule and recule > progresse, 'Ce qui recule, après')
    contient(lignes[recule + 1].texte, "Ciel ou haut de l'image brûlé")
    local travailler = indiceDe(lignes, function(l) return l.genre == 'titre' and l.texte == 'À travailler à la prochaine sortie' end)
    vrai(travailler and travailler > recule, 'À travailler, ensuite')
    contient(lignes[travailler + 1].texte, '•  ' .. "Ciel ou haut de l'image brûlé : 3 photos sur 6 (50 %)")
    local conseil = indiceDe(lignes, function(l) return l.texte:find('À la prise de vue : Exposer pour le ciel', 1, true) ~= nil end)
    vrai(conseil and conseil > travailler, 'le conseil sous le défaut')
    egal('    À la prise', lignes[conseil].texte:sub(1, #'    À la prise'), 'retiré sous sa puce')
    -- La ligne d'action, en dernier : bleue (aperçu), cliquable.
    local derniere = lignes[#lignes]
    egal('apercu', derniere.genre)
    egal('demander', derniere.action)
    egal("Demander à Claude ce qu'il en pense ›", derniere.texte)
    egal('vide', lignes[#lignes - 1].genre)
    -- Aucune autre ligne ne s'ouvre.
    for _, l in ipairs(lignes) do
        vrai(l.genre == 'outil' or l.defaut == nil, 'seules les rangées portent un défaut')
        vrai(l == derniere or l.action == nil, "seule la ligne d'action en porte une")
    end
    vrai(#lignes <= D.lignes, string.format('la page tient dans la grille (%d lignes pour %d)', #lignes, D.lignes))
end)

essai('Fil.lignesCarnet : page vide, en lecture, en erreur ; sans tendance ; années dans l\'en-tête ; libellé trop long', function()
    -- Vide : la note qui explique, ni tableau ni action.
    fabriquer({})
    local vide = Fil.lignesCarnet(Carnet.resumer(os.time()), LARGEUR, Fenetre.TITRE_CARNET)
    verifierLignes(vide)
    egal('Carnet de progrès', vide[1].texte)
    contient(vide[2].texte, 'Le carnet se remplit tout seul')
    for _, l in ipairs(vide) do
        vrai(l.genre ~= 'outil' and l.action == nil, 'ni tableau ni action : ' .. l.texte)
    end
    -- En lecture (nil), puis en erreur.
    local lecture = Fil.lignesCarnet(nil, LARGEUR, Fenetre.TITRE_CARNET)
    egal(2, #lecture)
    egal('Carnet de progrès', lecture[1].texte)
    egal(Fil.LECTURE_CARNET, lecture[2].texte)
    egal('cours', lecture[2].icone)
    local erreur = Fil.lignesCarnet({ erreur = 'carnet.json illisible' }, LARGEUR, Fenetre.TITRE_CARNET)
    egal("Le carnet de progrès ne s'est pas lu : carnet.json illisible", erreur[2].texte)
    egal('erreur', erreur[2].icone)
    verifierLignes(erreur)
    -- Fait main : deux années (l'en-tête les dit), un libellé trop long, ni tendance ni défaut à
    -- travailler (leurs phrases du résumé), une remarque.
    local long = string.rep('Défaut au libellé très long ', 3)
    local page = {
        vide = false, photos = 3, note = 'Note du résumé.', remarque = 'Seulement 3 photos.',
        titres = Carnet.TITRES,
        mois = { { cle = '2025-12', annee = 2025, numero = 12, court = 'déc.' }, { cle = '2026-01', annee = 2026, numero = 1, court = 'janv.' } },
        defauts = {
            { code = 'flou', libelle = 'Photo floue ou bougée', par_mois = { { n = 1, sur = 2 }, { n = 0, sur = 1 } } },
            { code = 'long', libelle = long, par_mois = { { n = 0, sur = 0 }, { n = 12, sur = 13 } } },
        },
        progresse = {}, recule = {}, a_travailler = {},
        aucune_tendance = 'Pas encore de tendance.', rien_a_travailler = 'Rien ne revient.',
    }
    local lignes = Fil.lignesCarnet(page, LARGEUR, Fenetre.TITRE_CARNET)
    verifierLignes(lignes)
    egal('Seulement 3 photos.', lignes[3].texte)
    local tableau = rangees(lignes)
    contient(tableau[1].texte, 'déc. 2025')
    contient(tableau[1].texte, 'janv. 2026')
    local rangeeLongue = rangeeDe(tableau, 'long')
    egal(Fil.LIBELLE_CARNET_MAX, Texte.longueur(rangeeLongue.texte:match('^(.-…)')), 'libellé coupé à la colonne')
    egal('— 12/13', cellules(rangeeLongue.texte))
    local progresse = indiceDe(lignes, function(l) return l.texte == 'Ce qui progresse' end)
    egal('Pas encore de tendance.', lignes[progresse + 1].texte)
    egal('note', lignes[progresse + 1].genre)
    vrai(not indiceDe(lignes, function(l) return l.texte == 'Ce qui recule' end), 'pas de « Ce qui recule » vide')
    local travailler = indiceDe(lignes, function(l) return l.texte == 'À travailler à la prochaine sortie' end)
    egal('Rien ne revient.', lignes[travailler + 1].texte)
    -- Ce qui recule seul : sans « Ce qui progresse » vide au-dessus.
    page.recule = { { code = 'flou', texte = 'Photo floue ou bougée : 0 % puis 40 %.' } }
    local seul = Fil.lignesCarnet(page, LARGEUR, Fenetre.TITRE_CARNET)
    vrai(not indiceDe(seul, function(l) return l.texte == 'Ce qui progresse' end), 'pas de « Ce qui progresse » vide')
    local recule = indiceDe(seul, function(l) return l.texte == 'Ce qui recule' end)
    egal('•  Photo floue ou bougée : 0 % puis 40 %.', seul[recule + 1].texte)
end)

-- La page dans la fenêtre --------------------------------------------------------------------------

essai('Page : choisie dans la liste, titre « Carnet de progrès », lue dans une tâche, lignes du résumé ; ▲ ▼ ; la conversation courante ramène au fil', function()
    fabriquerType()
    photoActive(53636309, 'DSCF4961.RAF')
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        Fenetre.rafraichir()
        egal('Lac au matin', p.titre)
        local montree = Fenetre.conversationAffichee
        egal(lac, montree)
        egal(lac.id, p.selectionListe[1])
        local taches = #S.taches
        -- Dany choisit l'entrée (l'observateur de la liste).
        p.selectionListe = { Fenetre.CARNET }
        egal('carnet', Fenetre.vue)
        egal(taches + 1, #S.taches, 'le résumé se lit dans une tâche')
        Fenetre.rafraichir()
        egal('Carnet de progrès', p.titre)
        egal('Carnet de progrès', p.t1)
        egal(Fil.LECTURE_CARNET, p.t2, 'en lecture')
        egal(Fenetre.CARNET, p.selectionListe[1], "l'entrée reste choisie")
        lancerTaches(taches)
        local page = Fenetre.pageCarnet
        vrai(type(page) == 'table' and #page.mois == 6, 'le résumé lu')
        egal(Carnet.version, Fenetre.versionCarnet)
        local attendues = Fil.lignesCarnet(page, Fenetre.largeurTexte(), Fenetre.TITRE_CARNET)
        egal(#attendues, #Fenetre.lignes)
        for i, l in ipairs(attendues) do
            egal(l.texte, p['t' .. i], 'ligne ' .. i)
            egal(l.genre, p['g' .. i], 'genre ' .. i)
        end
        egal(montree, Fenetre.conversationAffichee, 'la conversation montrée ne change pas')
        egal(1, Fenetre.premiere, 'la page se lit depuis son début')
        -- ▲ ▼ : une grille plus courte que la page.
        local T = Fenetre.T
        local lignesGrille = T.lignes
        T.lignes = 10
        Fenetre.rafraichirFil()
        egal(1, Fenetre.premiere)
        egal(false, p.peutMonter)
        egal(true, p.peutDescendre)
        egal(string.format('Lignes 1 à 10 sur %d', #attendues), p.positionFil)
        Fenetre.defiler(-5)
        egal(6, Fenetre.premiere, '▼')
        egal(attendues[6].texte, p.t1)
        Fenetre.defiler(5)
        egal(1, Fenetre.premiere, '▲')
        T.lignes = lignesGrille
        Fenetre.rafraichirFil()
        -- Quittée ou ouverte sans clic dans la liste (une demande, Claude qui travaille, la grille de
        -- la fenêtre B) : le choix de la liste suit la vue, même conversation courante.
        egal(true, Fenetre.quitterCarnet())
        Fenetre.rafraichir()
        egal(lac.id, p.selectionListe[1], 'la conversation choisie au retour')
        local avantOuverture = #S.taches
        egal(true, Fenetre.ouvrirCarnet())
        Fenetre.rafraichir()
        egal(Fenetre.CARNET, p.selectionListe[1], "l'entrée choisie à l'ouverture")
        lancerTaches(avantOuverture)
        -- La conversation déjà ouverte, choisie dans la liste : retour au fil, la même.
        p.selectionListe = { lac.id }
        egal('conversation', Fenetre.vue)
        egal(nil, Fenetre.pageCarnet)
        Fenetre.rafraichir()
        egal('Lac au matin', p.titre)
        egal(lac.id, p.selectionListe[1])
        egal(lac, Fenetre.conversationAffichee)
        egal('Lac au matin', p.t1, 'le fil de la conversation')
        oublierTaches(taches)
    end)
end)

essai('Liste depuis la page : un en-tête ou une conversation refusée la gardent ; une autre conversation ramène au fil', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    local pont = conversation('Pont en automne')
    local seance = conversation('Ancienne séance')
    seance.genre = 'notation'
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        local ouvrir, ouvertes = Moteur.ouvrir, {}
        Moteur.ouvrir = function(id)
            ouvertes[#ouvertes + 1] = id
            return ouvrir(id)
        end
        -- Un en-tête choisi hors de la page : la liste se remet, aucune conversation n'est cherchée.
        p.selectionListe = { "§Aujourd'hui" }
        egal(0, #ouvertes, 'un en-tête n\'est pas une conversation')
        egal(lac.id, p.selectionListe[1])
        p.selectionListe = { Fenetre.CARNET }
        Fenetre.rafraichir()
        p.selectionListe = { "§Aujourd'hui" }
        egal('carnet', Fenetre.vue, 'un en-tête garde la page')
        egal(Fenetre.CARNET, p.selectionListe[1])
        egal(0, #ouvertes)
        -- Refusée (ancienne séance de notation) : la page reste, le bandeau dit pourquoi.
        p.selectionListe = { seance.id }
        egal('carnet', Fenetre.vue, 'un refus garde la page')
        contient(p.message, 'ancienne séance de notation')
        egal(Fenetre.CARNET, p.selectionListe[1])
        egal(lac, Moteur.courante)
        -- Une autre conversation : elle s'ouvre, le fil revient.
        p.selectionListe = { pont.id }
        egal(pont, Moteur.courante)
        egal('conversation', Fenetre.vue)
        egal('', p.message)
        Fenetre.rafraichir()
        egal('Pont en automne', p.titre)
        egal(pont.id, p.selectionListe[1])
        -- Pendant que Claude travaille (la liste est alors inactive) : pas de page, le choix revient
        -- à la conversation.
        Moteur.travaille = true
        local avant = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        Moteur.travaille = false
        egal('conversation', Fenetre.vue, 'pas de page pendant le travail')
        egal(avant, #S.taches, 'rien à lire')
        contient(p.message, 'Claude travaille')
        egal(pont.id, p.selectionListe[1])
        Moteur.ouvrir = ouvrir
        oublierTaches(taches)
    end)
end)

essai('Gardes : Renommer…, ✎ et Supprimer… ne font rien sur la page ; Nouvelle conversation, Envoyer et une invite ramènent au fil', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        local dialogues = #S.dialogues
        S.confirmation, S.reponseModal, S.reponseConfirm = nil, 'ok', 'ok'
        Fenetre.renommer()
        egal(dialogues, #S.dialogues, 'Renommer… : aucune fenêtre')
        egal(Fenetre.CHOISIR_CONVERSATION, p.message)
        egal('Lac au matin', lac.titre)
        p.message = ''
        Fenetre.supprimer()
        egal(nil, S.confirmation, 'Supprimer… : rien à confirmer')
        egal(Fenetre.CHOISIR_CONVERSATION, p.message)
        egal(lac, Moteur.courante)
        egal(lac, Moteur.trouver(lac.id), 'la conversation reste')
        egal('carnet', Fenetre.vue)
        -- Sur le fil, les mêmes boutons agissent (ce n'est que la page qui les arrête) ; le bandeau qui
        -- disait de choisir une conversation s'efface au retour.
        S.reponseModal, S.reponseConfirm = 'cancel', 'cancel'
        p.selectionListe = { lac.id }
        egal('', p.message, 'le bandeau de la page effacé au retour')
        -- Claude qui travaille ramène au fil : le même bandeau s'efface aussi.
        p.selectionListe = { Fenetre.CARNET }
        Fenetre.renommer()
        egal(Fenetre.CHOISIR_CONVERSATION, p.message)
        Moteur.travaille = true
        Fenetre.rafraichir()
        Moteur.travaille = false
        egal('conversation', Fenetre.vue)
        egal('', p.message, 'bandeau effacé quand Claude travaille')
        p.libre = true
        -- Un autre message reste (seul celui de la page s'efface).
        p.message = 'Autre message.'
        p.selectionListe = { Fenetre.CARNET }
        egal('', p.message, "l'ouverture de la page efface le bandeau")
        p.message = 'Autre message.'
        p.selectionListe = { lac.id }
        egal('Autre message.', p.message)
        p.message = ''
        Fenetre.renommer()
        egal(dialogues + 1, #S.dialogues, 'Renommer… sur le fil')
        Fenetre.supprimer()
        vrai(S.confirmation, 'Supprimer… sur le fil')
        -- Nouvelle conversation : elle se montre.
        p.selectionListe = { Fenetre.CARNET }
        egal(true, Fenetre.nouvelle())
        egal('conversation', Fenetre.vue)
        vrai(Moteur.courante ~= lac, 'une nouvelle conversation')
        -- Refusée (Claude travaille) : faux, la page reste ; sans fenêtre (Fenetre.p) de même.
        local nouvelle = Moteur.courante
        p.selectionListe = { Fenetre.CARNET }
        Moteur.travaille = true
        egal(false, Fenetre.nouvelle())
        contient(p.message, 'Claude travaille')
        Fenetre.p = nil
        egal(false, Fenetre.nouvelle(), 'sans fenêtre')
        Fenetre.p = p
        Moteur.travaille = false
        egal('carnet', Fenetre.vue, 'la page reste')
        egal(nouvelle, Moteur.courante)
        p.message = ''
        -- Envoyer : vide, la page reste ; sinon la demande se suit dans le fil.
        p.selectionListe = { Fenetre.CARNET }
        Fenetre.envoyer('   ')
        egal('carnet', Fenetre.vue, 'rien à envoyer')
        contient(p.message, 'Écrivez une demande')
        local avant = #S.taches
        Fenetre.envoyer('Bonjour')
        egal('conversation', Fenetre.vue, 'Envoyer')
        egal(avant + 1, #S.taches, 'la demande part')
        oublierTaches(avant)
        p.libre = true
        -- La liste revient à la conversation (la même : seule la vue a changé).
        Fenetre.rafraichir()
        egal(Moteur.courante.id, p.selectionListe[1], 'la conversation choisie dans la liste')
        egal(Moteur.courante.titre, p.titre)
        -- Une invite passe par la même demande.
        p.selectionListe = { Fenetre.CARNET }
        Fenetre.envoyer(Consignes.invites[1].message)
        egal('conversation', Fenetre.vue, 'une invite')
        oublierTaches(taches)
        p.libre = true
        S.confirmation, S.reponseModal, S.reponseConfirm = nil, nil, nil
    end)
end)

essai('Une autre photo choisie dans Lightroom prépare une nouvelle conversation sans quitter la page', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    prefs.nouvelleParPhoto = true
    ouvrirFenetre(function(p)
        local taches = #S.taches
        lac.cle = 'photo-A'
        Fenetre.cleVue, Fenetre.cleVueLe = 'photo-A', os.time()
        local fin = Moteur.finTravail
        Moteur.finTravail = 0
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
        Fenetre.hautCarnet = 2
        Fenetre.suivreSelection({ cle = 'photo-B' })
        vrai(Moteur.courante ~= lac, 'la nouvelle conversation est prête')
        egal('carnet', Fenetre.vue, 'la page reste')
        egal(2, Fenetre.hautCarnet, 'à la même place')
        Fenetre.rafraichir()
        egal('Carnet de progrès', p.titre)
        egal(Fenetre.CARNET, p.selectionListe[1])
        egal(lac, Fenetre.conversationAffichee, 'pas encore montrée')
        -- Au retour, c'est elle qui se montre.
        p.selectionListe = { Moteur.courante.id }
        Fenetre.rafraichir()
        egal('conversation', Fenetre.vue)
        egal(Moteur.courante, Fenetre.conversationAffichee)
        Moteur.finTravail = fin
        oublierTaches(taches)
    end)
    prefs.nouvelleParPhoto = false
end)

essai('Boucle : le registre change (abonnement, Carnet.version), la page se relit ; hors de la page, rien ; désabonné à la fermeture', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        egal('function', type(Carnet.observateurs.fenetre), 'abonnée')
        -- Hors de la page : un changement du registre ne fait rien lire.
        Carnet.signaler('constat')
        unTourDeBoucle()
        egal(nil, Fenetre.pageCarnet, 'rien lu hors de la page')
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
        egal(13, Fenetre.pageCarnet.photos)
        -- Un retrait (d'un autre client du connecteur, ici le registre lui-même) : la page se relit
        -- au tour suivant.
        local version = Carnet.version
        Carnet.commande({ action = 'retirer', photos = { 1001 } })
        vrai(Carnet.version > version, 'nouvelle version')
        egal(true, Fenetre.aRafraichirCarnet, "l'abonnement l'a dit")
        unTourDeBoucle()
        egal(12, Fenetre.pageCarnet.photos, 'page relue')
        egal(false, Fenetre.aRafraichirCarnet)
        egal(Carnet.version, Fenetre.versionCarnet)
        contient(p.t2, 'sur 12 photos')
        -- La version seule suffit aussi (un changement sans abonnement).
        Carnet.oublier()
        Fenetre.versionCarnet = Carnet.version - 1
        local lue = Fenetre.pageCarnet
        unTourDeBoucle()
        vrai(Fenetre.pageCarnet ~= lue, 'relue par la version')
        -- Un résumé qui ne se lit pas : la page le dit, la boucle ne la relit pas sans fin.
        local resumer = Carnet.resumer
        Carnet.resumer = function() error('carnet.json illisible', 0) end
        Fenetre.versionCarnet = -1
        unTourDeBoucle()
        Carnet.resumer = resumer
        egal('carnet.json illisible', Fenetre.pageCarnet.erreur)
        egal(Carnet.version, Fenetre.versionCarnet)
        egal("Le carnet de progrès ne s'est pas lu : carnet.json illisible", p.t2)
        oublierTaches(taches)
    end)
    egal(nil, Carnet.observateurs.fenetre, 'désabonnée à la fermeture')
end)

-- Fenêtre des photos d'un défaut -----------------------------------------------------------------

essai('Clic sur une rangée : la fenêtre de ses photos (dans une tâche), éléments neufs, leçon de la photo choisie ; rien hors de la page', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
        local i = indiceDe(Fenetre.lignes, function(l) return l.defaut == 'ciel_brule' end)
        vrai(i, 'rangée du ciel brûlé')
        local dialogues = #S.dialogues
        local avant = #S.taches
        Fenetre.cliquerLigne(i)
        egal(avant + 1, #S.taches, 'la fenêtre des photos part d\'une tâche')
        egal(dialogues, #S.dialogues)
        lancerTaches(avant)
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
        contient(liste.args.items[1].title, 'DSCF1024.RAF · ciel brûlé : 4,2 % du tiers haut en blanc pur · leçon')
        contient(liste.args.items[3].title, Carnet.MOIS[tonumber(moisIl(1):sub(6, 7))])
        local textes = {}
        for _, v in ipairs(vues(d.contents)) do
            if v.genre == 'static_text' then
                textes[#textes + 1] = v.args.title
            end
        end
        contient(table.concat(textes, '\n'), "3 photos dans les mois du carnet, la plus récente d'abord.")
        contient(table.concat(textes, '\n'), 'À la prise de vue : Exposer pour le ciel')
        -- La leçon de la photo choisie : 1024 d'abord, puis une autre choisie.
        local q = d.contents.args.bind_to_object
        egal(1024, q.choix[1])
        local lecon = q.lecon
        contient(lecon, 'Leçon de la photo · DSCF1024.RAF')
        contient(lecon, 'Lumière\n    Ce qui manquait : Ciel brûlé à 4 %.\n    À la prise de vue : Exposer pour le ciel.')
        contient(lecon, 'Couleur\n    Rien ne manquait.\n    À refaire : Balance des blancs juste : à refaire.')
        contient(lecon, 'Composition\n    Ce qui manquait : Horizon un peu bas.')
        q.choix = { 1021 }
        contient(q.lecon, 'Pas de leçon rangée pour cette photo')
        egal('lecon', vueDe(d.contents, 'edit_field').args.value.key)
        -- Un défaut cherché mais jamais trouvé : la fenêtre le dit, sans liste ni retrait.
        local bruit = indiceDe(Fenetre.lignes, function(l) return l.defaut == 'bruit' end)
        avant = #S.taches
        Fenetre.cliquerLigne(bruit)
        lancerTaches(avant)
        local vide = S.dialogues[#S.dialogues]
        egal(nil, vide.otherVerb)
        egal(nil, vueDe(vide.contents, 'simple_list'))
        contient(vueDe(vide.contents, 'static_text').args.title, "Aucune photo n'a ce défaut")
        -- Une ligne penchée (l'angle rangé dans l'entrée, sans texte) : son inclinaison en degrés.
        local penchee = indiceDe(Fenetre.lignes, function(l) return l.defaut == 'horizon_penche' end)
        avant = #S.taches
        Fenetre.cliquerLigne(penchee)
        lancerTaches(avant)
        local angles = vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items
        egal(2, #angles)
        contient(angles[1].title, 'DSCF1026.RAF · ligne penchée de 1,2°')
        contient(angles[2].title, 'DSCF1014.RAF · ligne penchée de 0,8°')
        egal('mars 2026 · DSCF0001.RAF · ligne penchée de 1,3°', Fenetre.textePhotoDuDefaut({ mois_libelle = 'mars 2026',
            fichier = 'DSCF0001.RAF', mesure = -1.26, angle = true }))
        -- Une seule photo : pas de « la plus récente d'abord ».
        local mise = indiceDe(Fenetre.lignes, function(l) return l.defaut == 'mise_au_point' end)
        avant = #S.taches
        Fenetre.cliquerLigne(mise)
        lancerTaches(avant)
        egal('1 photo dans les mois du carnet.', vueDe(S.dialogues[#S.dialogues].contents, 'static_text').args.title)
        -- Une autre mesure sans texte se dit telle quelle (mise au point, 8,5).
        contient(vueDe(S.dialogues[#S.dialogues].contents, 'simple_list').args.items[1].title, 'DSCF1001.RAF · mesure : 8,5')
        egal('mars 2026 · DSCF1001.RAF · mesure : 8,5', Fenetre.textePhotoDuDefaut({ mois_libelle = 'mars 2026', fichier = 'DSCF1001.RAF',
            mesure = 8.5, lecons = {} }))
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
        -- Hors de la page, une ligne qui porterait un défaut ne fait rien.
        p.selectionListe = { lac.id }
        Fenetre.rafraichir()
        local ancienne = Fenetre.lignes
        Fenetre.lignes, Fenetre.premiere = { { genre = 'outil', texte = 'x', defaut = 'flou' }, { genre = 'apercu', texte = 'y', action = 'demander' } }, 1
        avant = #S.taches
        local courante = Moteur.courante
        Fenetre.cliquerLigne(1)
        Fenetre.cliquerLigne(2)
        egal(avant, #S.taches, 'rien hors de la page')
        egal(courante, Moteur.courante)
        Fenetre.lignes = ancienne
        oublierTaches(taches)
    end)
end)

essai('« Retirer du carnet… » : la photo choisie, après confirmation, par appel direct au registre avec l\'id de l\'original', function()
    fabriquerType()
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
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
        vrai(Carnet.version > version, 'la page se relira')
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
        -- Les noms des axes du carnet sont ceux de la carte du fil.
        egal('Lumière', Fenetre.nomAxeCarnet('lumiere'))
        egal('Couleur', Fenetre.nomAxeCarnet('couleur'))
        egal('Composition', Fenetre.nomAxeCarnet('composition'))
        oublierTaches(taches)
    end)
end)

-- Avec le faux Claude Code -------------------------------------------------------------------------

local function attendre(condition, secondes)
    for _ = 1, (secondes or 10) * 10 do
        Moteur.tic()
        if condition() then
            return true
        end
        S.executer('sleep 0.1')
    end
    return false
end

-- Le texte du dernier message écrit pour Claude Code (entree.jsonl de la session).
local function dernierMessage()
    local entree = Fichiers.lire(Moteur.session.dossier .. '/entree.jsonl') or ''
    local derniere
    for ligne in entree:gmatch('[^\n]+') do
        derniere = ligne
    end
    local json = Json.decode(derniere)
    local contenu = json.message.content
    return contenu[#contenu].text
end

essai('« Demander à Claude ce qu\'il en pense » : nouvelle conversation avec Consignes.carnet (relais.sh, faux-claude.sh) ; la page se quitte', function()
    fabriquerType()
    photoActive(53636309, 'DSCF4961.RAF')
    local lac = conversation('Lac au matin')
    Moteur.courante = lac
    ouvrirFenetre(function(p)
        local taches = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
        -- Claude travaille ailleurs : rien.
        Moteur.travaille = true
        egal(false, Fenetre.demanderCarnet())
        contient(p.message, 'Claude travaille')
        egal('carnet', Fenetre.vue)
        egal(lac, Moteur.courante)
        Moteur.travaille = false
        p.message = ''
        local i = indiceDe(Fenetre.lignes, function(l) return l.action == 'demander' end)
        vrai(i, "la ligne d'action")
        local avant = #S.taches
        Fenetre.cliquerLigne(i)
        egal('conversation', Fenetre.vue, 'la page se quitte')
        local c = Moteur.courante
        vrai(c ~= lac, 'une nouvelle conversation')
        egal(avant + 1, #S.taches, 'la demande part dans une tâche')
        lancerTache(avant + 1)
        vrai(Moteur.travaille, 'Claude Code reçoit la demande')
        egal(c, Moteur.courante)
        egal('dany', c.elements[1].genre)
        egal(Consignes.carnet, c.elements[1].texte)
        contient(dernierMessage(), Consignes.carnet)
        -- Son titre à elle (Claude ne regarde aucune photo pour la nommer), sans le rappel du titre.
        egal(Fenetre.TITRE_DEMANDE_CARNET, c.titre)
        egal(true, c.titreChoisi)
        vrai(not dernierMessage():find(Consignes.rappelTitre, 1, true), 'pas de rappel du titre')
        vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
        Fenetre.rafraichir()
        egal(c, Fenetre.conversationAffichee)
        vrai(#lac.elements == 1, "l'ancienne conversation n'a rien reçu")
        oublierTaches(taches)
    end)
end)

essai('Accepter et Je le fais quittent la page : Claude qui travaille ramène au fil', function()
    fabriquerType()
    photoActive(53636309, 'DSCF4961.RAF')
    local c = conversation('Flamant au zoo')
    Moteur.courante = c
    -- Une proposition ordinaire en attente.
    Conversation.appliquer(c, { genre = 'assistant', blocs = { { genre = 'outil', id = 'carnet-prop', nom = 'mcp__developpeur__preview_settings',
        entree = { reason = 'Plus de lumière', settings = { Exposure2012 = 0.35 }, compare = true } } } })
    Conversation.appliquer(c, { genre = 'resultats', resultats = { { idOutil = 'carnet-prop',
        textes = { '{"changements": [{"cle": "Exposure2012", "avant": 0, "apres": 0.35}]}' }, images = {}, erreur = false } } })
    vrai(Conversation.propositionEnAttente(c), 'proposition en attente')
    ouvrirFenetre(function(p)
        local taches = #S.taches
        Fenetre.rafraichir()
        local montree = Fenetre.conversationAffichee
        -- Accepter (la carte Proposition) pendant que la page est montrée.
        p.selectionListe = { Fenetre.CARNET }
        lancerTaches(taches)
        local avant = #S.taches
        Fenetre.repondreProposition(true)
        lancerTache(avant + 1)
        vrai(Moteur.travaille, 'Claude applique la proposition')
        Fenetre.rafraichir()
        egal('conversation', Fenetre.vue, 'Accepter ramène au fil')
        egal(montree, Fenetre.conversationAffichee)
        egal(c.titre, p.titre)
        contient(dernierMessage(), Consignes.accepter)
        vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
        -- Je le fais (sans proposition : sur la photo active), depuis la page.
        avant = #S.taches
        p.selectionListe = { Fenetre.CARNET }
        lancerTache(avant + 1)
        egal('carnet', Fenetre.vue)
        vrai(type(Fenetre.pageCarnet) == 'table', 'la page lue')
        Fenetre.jeLeFais()
        vrai(Moteur.travaille, 'Claude range sa version')
        Fenetre.rafraichir()
        egal('conversation', Fenetre.vue, 'Je le fais ramène au fil')
        contient(dernierMessage(), 'Je le fais moi-même')
        vrai(attendre(function() return not Moteur.travaille end), 'la demande se termine')
        oublierTaches(taches)
    end)
end)

-- Consignes ----------------------------------------------------------------------------------------

essai('Consignes : puce Carnet des garde-fous (250 caractères au plus) ; Consignes.carnet ; le texte reste sous 7 500', function()
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
    -- La demande de la ligne d'action : le résumé du connecteur, trois puces, rien de retouché, sans
    -- chiffre écrit dans la fenêtre.
    for _, morceau in ipairs({ 'carnet de progrès', 'export_journal avec notebook = true', 'trois puces', 'ce qui progresse',
        'ce qui revient le plus', 'prochaine sortie', 'réglages du boîtier', 'Ne retouche rien.' }) do
        contient(Consignes.carnet, morceau, 'Consignes.carnet')
    end
    vrai(not Consignes.carnet:find('%d'), 'Consignes.carnet sans chiffre')
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
