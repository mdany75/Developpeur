-- essais-carnet.lua : le carnet de progrès (Carnet.lua, 1.3), hors de Lightroom (LuaJIT, Lightroom
-- simulé par Simulation.lua) : la commande carnet constater (vue, angle, refus, validation), lire
-- avec le résumé, retirer, et Carnet.resumer (mois de prise de vue en français, base propre à
-- chaque défaut, tendances aux bornes, à travailler, remarques). Rien n'est écrit dans le
-- catalogue, et la pause n'arrête rien.
-- Lancé par scripts/tester-module.sh (essais à part de la liaison).

local dossierTests = (arg and arg[0] or ''):match('(.*/)') or './'
local dossierModule = dossierTests .. '../../../Lightroom/Developpeur.lrplugin/'
package.path = dossierModule .. '?.lua;' .. dossierTests .. '?.lua;' .. package.path

local A = require 'Aides'
local S = A.S
local test, egal, proche, echoue, contient, ligne = A.test, A.egal, A.proche, A.echoue, A.contient, A.ligne
local photoRaw, photoJpeg, photoFuji, appliquer = A.photoRaw, A.photoJpeg, A.photoFuji, A.appliquer

local Json = require 'Json'
local Liaison = require 'Liaison'
local Commandes = require 'Commandes'
local Carnet = require 'Carnet'

-- Complément de la simulation, pour cet essai : l'heure locale de LrDate.timeToUserFormat pour
-- tout format (l'UTC décalé de S.fuseau secondes, comme le jour que la simulation rend déjà).
local LrDate = import 'LrDate'
LrDate.timeToUserFormat = function(t, format)
    return os.date('!' .. format, 978307200 + math.floor(t) + S.fuseau)
end

local CATALOGUE = '/Users/test/Images/Catalogue.lrcat'
local AUTRE = '/Users/test/Images/Autre.lrcat'

-- Le 1er juillet 2026 à 2 h 30 UTC (secondes depuis 2001) : le 30 juin à 22 h 30 à l'heure avancée
-- de l'Est.
local PRISE_JUILLET_UTC = 804565800

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

-- Une vue comme view_photo la constate : les six défauts cherchés (point AF lu), le ciel brûlé
-- trouvé.
local function vueType()
    return {
        cherches = { 'horizon_penche', 'sous_exposition', 'ciel_brule', 'flou', 'mise_au_point', 'bruit' },
        defauts = { { code = 'ciel_brule', mesure = 4.2, texte = "ciel brûlé : 4,2 % du tiers haut en blanc pur" } },
    }
end

local function vue(cherches, defauts)
    return { cherches = cherches, defauts = defauts or {} }
end

local function angle(inclinaison, source)
    return { inclinaison = inclinaison, code = 'horizon_penche', source = source }
end

-- carnet constater sur une photo : `constat` porte vue ou angle ; `plus`, d'autres paramètres.
local function constater(photo, constat, plus)
    local params = { action = 'constater', photo = photo, vocabulaire = VOCABULAIRE }
    for cle, valeur in pairs(constat) do
        params[cle] = valeur
    end
    for cle, valeur in pairs(plus or {}) do
        params[cle] = valeur
    end
    return Commandes.executer('carnet', params)
end

-- Une leçon valide (trois points, un par axe), pour vérifier qu'un constat la garde.
local function lecon()
    return { points = {
        { axe = 'lumiere', prise_de_vue = "Exposer pour le ciel." },
        { axe = 'couleur', prise_de_vue = "Balance des blancs juste : à refaire." },
        { axe = 'composition', prise_de_vue = "Niveau électronique du viseur.", defauts = { 'horizon_penche' } },
    } }
end

local function fichierRelu()
    return Json.decode(S.fichiers[Carnet.fichier()])
end

-- Aucune table de cette valeur ne porte de métatable (tableau relu par Json.decode, ou marqué par
-- Json.tableau) : Lightroom bloque sur une telle table dans une vue.
local function sansMetatable(valeur, chemin)
    if type(valeur) ~= 'table' then
        return
    end
    egal(getmetatable(valeur), nil, "métatable : " .. chemin)
    for cle, element in pairs(valeur) do
        sansMetatable(element, chemin .. '.' .. tostring(cle))
    end
end

-- Midi, le jour donné (heure locale de la machine, comme os.date) : le « maintenant » du résumé.
local function le(annee, mois, jour)
    return os.time({ year = annee, month = mois, day = jour or 15, hour = 12 })
end

-- Un registre fabriqué, écrit dans carnet.json puis relu : des entrées { prise, vue?, angle? }.
local function fabriquer(entrees, vocabulaire)
    local photos = {}
    for i, e in ipairs(entrees) do
        e.photo = e.photo or (1000 + i)
        e.uuid = e.uuid or ('uuid-' .. e.photo)
        e.fichier = e.fichier or string.format('IMG_%04d.JPG', e.photo)
        e.le = e.le or 1
        e.lecons = e.lecons or {}
        photos[tostring(e.photo)] = e
    end
    S.fichiers[Carnet.fichier()] = Json.encode({ format = 1, vocabulaire = vocabulaire or VOCABULAIRE,
        catalogues = { [CATALOGUE] = { photos = photos } } })
    Carnet.oublier()
end

-- Ajoute n photos du mois `prise` (vue qui cherche `cherches`) ; la i-e trouve les codes que
-- trouve(i) rend.
local function serie(entrees, prise, n, cherches, trouve)
    for i = 1, n do
        local defauts, propres = {}, {}
        for _, c in ipairs(trouve and trouve(i) or {}) do
            defauts[#defauts + 1] = { code = c, mesure = i }
        end
        -- Une liste à elle par photo : un essai en retire des codes, photo par photo.
        for k, c in ipairs(cherches) do
            propres[k] = c
        end
        entrees[#entrees + 1] = { prise = prise, vue = { le = 1, cherches = propres, defauts = defauts } }
    end
end

-- Le défaut d'un code dans un résumé.
local function defautDe(resume, code)
    for _, d in ipairs(resume.defauts) do
        if d.code == code then
            return d
        end
    end
    return nil
end

local function codes(liste)
    local t = {}
    for _, element in ipairs(liste) do
        t[#t + 1] = element.code
    end
    return table.concat(t, ',')
end

-- Constater ---------------------------------------------------------------------------------------

test("carnet constater, vue : rangée sous l'original au mois de prise de vue (heure locale), vocabulaire rangé ; ni écriture au catalogue ni pause", function()
    local photo = photoRaw()
    photo.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.fuseau = -4 * 3600
    Liaison.pause = true
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local version = Carnet.version
    local vus = {}
    Carnet.abonner('essai', function(quoi) vus[#vus + 1] = quoi end)
    local r = constater(1, { vue = vueType() })
    egal(r.note, true)
    egal(r.constat, 'vue')
    egal(r.photo, 1)
    egal(r.original, 1)
    egal(r.fichier, 'DSC_0412.NEF')
    egal(r.mois, '2026-06', "mois de prise de vue à l'heure locale, pas l'UTC")
    egal(r.prise_le, '2026-06-30 22:30')
    egal(r.sans_date, nil)
    egal(r.remplacee, false)
    egal(r.remarque, nil)
    egal(#S.ecritures, ecritures, "rien dans le catalogue")
    egal(S.ecrituresPrivees, privees, "pas même une écriture privée")
    egal(Carnet.version, version + 1)
    egal(vus[1], 'constat')
    egal(contient(Liaison.journal, "Carnet : prise de vue notée pour DSC_0412.NEF (1 défaut sur 6 cherchés)"), true)

    local relu = fichierRelu()
    local e = relu.catalogues[CATALOGUE].photos['1']
    egal(e.prise, '2026-06')
    egal(e.vue.photo, 1, "la photo mesurée")
    egal(type(e.vue.le), 'number')
    egal(table.concat(e.vue.cherches, ','), 'horizon_penche,sous_exposition,ciel_brule,flou,mise_au_point,bruit')
    egal(#e.vue.defauts, 1)
    egal(e.vue.defauts[1].code, 'ciel_brule')
    proche(e.vue.defauts[1].mesure, 4.2)
    egal(e.vue.defauts[1].texte, "ciel brûlé : 4,2 % du tiers haut en blanc pur")
    egal(e.angle, nil)
    egal(#relu.vocabulaire, #VOCABULAIRE, "le vocabulaire, pour tous les catalogues")
    egal(relu.vocabulaire[1].code, 'horizon_penche')
    egal(relu.vocabulaire[3].conseil, VOCABULAIRE[3].conseil)
    egal(relu.vocabulaire[7].mesure, nil, "mesure = false n'est pas gardé")
    egal(Carnet.vocabulaire()[2].libelle, "Photo sous-exposée")
    egal(Carnet.vocabulaire()[4].domaine, 'nettete')
end)

test("carnet constater : une copie virtuelle va sous son original (une prise de vue compte une fois) ; la photo mesurée est gardée", function()
    local original = photoRaw()
    original.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.copieVirtuelle(original, 7, 'Copie 1')
    local r = constater(7, { vue = vueType() })
    egal(r.photo, 7)
    egal(r.original, 1)
    egal(r.fichier, 'DSC_0412.NEF (Copie 1)')
    egal(r.mois, '2026-07')
    egal(Carnet.nombre(), 1)
    local e = Carnet.entree(1)
    egal(e.vue.photo, 7, "la vue vient de la copie")
    egal(e.fichier, 'DSC_0412.NEF', "l'entrée est celle de l'original")
    -- L'original vu à part : la même entrée, la dernière vue l'emporte.
    r = constater(1, { vue = vue({ 'flou' }) })
    egal(r.remplacee, true)
    egal(Carnet.nombre(), 1)
    egal(Carnet.entree(1).vue.photo, 1)
    egal(#Carnet.entree(1).vue.defauts, 0)
end)

test("carnet constater : une vue remplace la vue, un angle l'angle ; l'autre et les leçons restent", function()
    photoRaw()
    Commandes.executer('lecon', { action = 'garder', photo = 1, lecon = lecon() })
    local r = constater(1, { angle = angle(1.8, 'measure_angle') })
    egal(r.note, true)
    egal(r.constat, 'angle')
    egal(r.remplacee, false)
    egal(r.sans_date, true, "photo sans date de prise de vue")
    egal(constater(1, { vue = vue({ 'flou', 'bruit' }, { 'flou' }) }).remplacee, false, "première vue")
    local e = Carnet.entree(1)
    proche(e.angle.inclinaison, 1.8)
    egal(e.angle.code, 'horizon_penche')
    egal(e.angle.source, 'measure_angle')
    egal(e.angle.photo, 1)
    egal(e.vue.defauts[1].code, 'flou', "un code seul devient { code }")
    egal(e.vue.defauts[1].mesure, nil)
    egal(e.lecons['1'] ~= nil, true, "la leçon reste")

    r = constater(1, { vue = vue({ 'bruit' }) })
    egal(r.remplacee, true)
    e = Carnet.entree(1)
    egal(table.concat(e.vue.cherches, ','), 'bruit', "la nouvelle vue remplace l'ancienne")
    egal(#e.vue.defauts, 0)
    proche(e.angle.inclinaison, 1.8, "l'angle reste")

    r = constater(1, { angle = angle(-0.7) })
    egal(r.remplacee, true)
    e = Carnet.entree(1)
    proche(e.angle.inclinaison, -0.7, "le nouvel angle remplace l'ancien")
    egal(e.angle.source, nil)
    egal(table.concat(e.vue.cherches, ','), 'bruit', "la vue reste")
    egal(e.lecons['1'] ~= nil, true, "la leçon reste")
    egal(contient(Liaison.journal, "Carnet : ligne penchée de 0,7° notée pour DSC_0412.NEF"), true)
    local texte = S.fichiers[Carnet.fichier()]
    egal(texte:find('"defauts":[]', 1, true) ~= nil, true, "une liste vide reste un tableau JSON dans le fichier")
    egal(texte:find('"cherches":["bruit"]', 1, true) ~= nil, true)
end)

test("carnet constater : vue refusée après une retouche de Claude ; angle gardé après une passe de tonalité, refusé si la géométrie est touchée", function()
    local photo = photoFuji()
    S.active = photo
    appliquer({ reglages = { Exposure2012 = 0.3 } })
    egal(#Json.decode(photo.proprietes.etapesClaude), 1, "une étape de Claude")
    local version = Carnet.version
    local r = constater(4, { vue = vueType() })
    egal(r.note, false)
    egal(r.motif, 'etapes')
    egal(r.photo, 4)
    egal(r.raison, "Photo déjà retouchée par Claude : sa prise de vue ne se mesure qu'avant la première retouche.")
    egal(Carnet.version, version, "rien n'est rangé")
    egal(S.fichiers[Carnet.fichier()], nil)

    r = constater(4, { angle = angle(1.2, 'measure_angle') })
    egal(r.note, true, "une passe de tonalité ne touche pas la géométrie")

    appliquer({ recadrage = { angle = -1.5, taille = 1, centre_x = 0.5, centre_y = 0.5 }, etape = 'passe 2' })
    egal(photo.reglages.CropAngle, -1.5)
    r = constater(4, { angle = angle(0.3) })
    egal(r.note, false)
    egal(r.motif, 'geometrie')
    egal(r.raison, "Géométrie déjà touchée (recadrage tourné, Upright, perspective ou distorsion) : "
        .. "la ligne mesurée ne dit plus l'inclinaison de la prise de vue.")
    proche(Carnet.entree(4).angle.inclinaison, 1.2, "l'angle d'avant reste")

    Commandes.executer('annuler', {})
    proche(photo.reglages.CropAngle or 0, 0)
    egal(constater(4, { angle = angle(0.6) }).note, true, "recadrage tourné défait")
    photo.reglages.CropAngle = 1e-12
    egal(constater(4, { angle = angle(0.6) }).note, true, "un reste de calcul n'est pas un recadrage tourné")
    photo.reglages.CropAngle = 0.01
    egal(constater(4, { angle = angle(0.6) }).motif, 'geometrie', "0,01° : tourné")
    photo.reglages.CropAngle = 0
    photo.reglages.PerspectiveUpright = 1
    egal(constater(4, { angle = angle(0.6) }).motif, 'geometrie', "Upright")
    photo.reglages.PerspectiveUpright = 0
    photo.reglages.PerspectiveVertical = -12
    egal(constater(4, { angle = angle(0.6) }).motif, 'geometrie', "perspective")
    photo.reglages.PerspectiveVertical = 0
    egal(constater(4, { angle = angle(0.9) }).note, true)
    proche(Carnet.entree(4).angle.inclinaison, 0.9)

    -- Une copie virtuelle de la photo retouchée : elle en a reçu les réglages, sa vue est refusée
    -- (essai suivant) ; sa géométrie, la sienne, est intacte : son angle se mesure.
    S.copieVirtuelle(photo, 9, 'Copie 2')
    egal(constater(9, { vue = vueType() }).motif, 'etapes')
    egal(constater(9, { angle = angle(1.1) }).note, true)
    egal(Carnet.entree(4).angle.photo, 9)
end)

test("carnet constater : la vue d'une copie virtuelle d'une photo retouchée par Claude est refusée ; celle de l'original, prise avant, reste", function()
    local Photos = require 'Photos'
    local photo = photoFuji()
    S.active = photo
    egal(constater(4, { vue = vueType() }).note, true, "l'original, avant sa première retouche")
    appliquer({ reglages = { Exposure2012 = 0.3 } })
    local copie = S.copieVirtuelle(photo, 9, 'Copie 2')
    proche(copie.reglages.Exposure2012, 0.3, "la copie a reçu les réglages de Claude")
    egal(#Photos.lireJson(copie, 'etapesClaude', {}), 0, "sa mémoire est celle de l'original : elle se lit vide")
    local version = Carnet.version
    local r = constater(9, { vue = vue({ 'flou' }) })
    egal(r.note, false)
    egal(r.motif, 'etapes')
    egal(r.photo, 9)
    egal(r.raison, "Copie virtuelle d'une photo déjà retouchée par Claude : elle en a reçu les réglages ; "
        .. "la prise de vue se mesure sur l'original, avant sa première retouche.")
    egal(Carnet.version, version, "rien n'est rangé")
    local e = Carnet.entree(4)
    egal(e.vue.photo, 4, "la vue de l'original n'est pas remplacée")
    egal(#e.vue.cherches, 6)
    egal(e.vue.defauts[1].code, 'ciel_brule')

    -- Les étapes de Claude défaites sur l'original : la copie faite ensuite se mesure.
    Commandes.executer('annuler', {})
    egal(#Photos.lireJson(photo, 'etapesClaude', {}), 0)
    S.copieVirtuelle(photo, 10, 'Copie 3')
    egal(constater(10, { vue = vue({ 'flou' }) }).note, true)
    egal(Carnet.entree(4).vue.photo, 10)
end)

test("carnet constater : une photo de Développeur › Essais (ou dont l'original y est) est refusée, sauf pour la recette", function()
    local original = photoRaw()
    local copie = S.copieVirtuelle(original, 7, 'Essai')
    local developpeur = S.Ensemble('Développeur')
    local essais = S.Collection('Essais', developpeur)
    essais.membres[copie] = true
    local r = constater(7, { vue = vueType() })
    egal(r.note, false)
    egal(r.motif, 'essai')
    egal(r.photo, 7)
    egal(r.raison, "Photo d'essai (Développeur › Essais) : le carnet ne compte que les vraies prises de vue.")
    egal(constater(7, { angle = angle(1) }).motif, 'essai', "l'angle aussi")
    egal(Carnet.nombre(), 0)
    egal(S.fichiers[Carnet.fichier()], nil)
    egal(Carnet.estPhotoDEssai(copie), true)
    egal(Carnet.estPhotoDEssai(original), false)

    -- L'original, une vraie photo, a son entrée (vue et leçon) : la recette n'y touche jamais.
    egal(constater(1, { vue = vue({ 'flou' }, { 'flou' }) }).note, true, "l'original n'est pas une photo d'essai")
    Commandes.executer('lecon', { action = 'garder', photo = 1, lecon = lecon() })
    r = constater(7, { vue = vueType() }, { essai_recette = true })
    egal(r.note, true, "la recette seule fait entrer une copie d'essai")
    egal(r.photo, 7)
    egal(r.original, 7, "une entrée à elle, jamais celle de son original")
    egal(r.fichier, 'DSC_0412.NEF (Essai)')
    egal(r.remplacee, false)
    egal(Carnet.nombre(), 2)
    egal(Carnet.entree(7).vue.photo, 7)
    egal(table.concat(Carnet.entree(1).vue.cherches, ','), 'flou', "la vue de l'original n'est pas remplacée")
    egal(constater(7, { angle = angle(1) }, { essai_recette = true }).original, 7, "l'angle aussi")
    egal(Carnet.entree(1).angle, nil)
    egal(Commandes.executer('carnet', { action = 'retirer', photos = { 7 } }).retirees, 1)
    -- Retirée (ou jamais constatée) : retirer la photo d'essai ne mène pas à l'entrée de son original.
    local encore = Commandes.executer('carnet', { action = 'retirer', photos = { 7 } })
    egal(encore.retirees, 0)
    egal(encore.absentes[1], 7)
    local e = Carnet.entree(1)
    egal(table.concat(e.vue.cherches, ','), 'flou', "l'entrée de l'original reste")
    egal(e.lecons['1'] ~= nil, true, "et sa leçon")
    egal(Carnet.nombre(), 1)

    -- L'original est dans les Essais : sa copie aussi est une photo d'essai.
    essais.membres[copie] = nil
    essais.membres[original] = true
    S.copieVirtuelle(original, 8, 'Copie 2')
    egal(constater(8, { vue = vueType() }).motif, 'essai', "son original est une photo d'essai")

    -- Une collection Essais d'un autre ensemble, ou à la racine, ou une autre collection de
    -- Développeur : la photo compte.
    essais.membres[original] = nil
    S.Collection('Essais', S.Ensemble('Voyage')).membres[original] = true
    S.Collection('Essais', nil).membres[original] = true
    S.Collection('Favoris', developpeur).membres[original] = true
    egal(Carnet.estPhotoDEssai(original), false)
    egal(constater(1, { vue = vueType() }).note, true)

    -- Des collections illisibles : pas une photo d'essai (la recette le verrait).
    original.getContainedCollections = function() error("illisible") end
    egal(Carnet.estPhotoDEssai(original), false)
end)

-- 1.3.1 : constaté le 21 octobre 2026 dans le carnet de Dany, la leçon de l'essai réel sur la dune
-- d'essai (une copie de « Développeur › Essais ») rangée sous son original, une vraie photo.
test("lecon garder : la leçon d'une photo de Développeur › Essais n'est pas rangée, sauf pour la recette, sous son entrée à elle", function()
    local original = photoRaw()
    original.brut.dateTimeOriginal = PRISE_JUILLET_UTC
    S.fuseau = -4 * 3600
    local copie = S.copieVirtuelle(original, 7, 'Essai')
    S.Collection('Essais', S.Ensemble('Développeur')).membres[copie] = true
    -- L'original, une vraie photo, a sa vue.
    egal(constater(1, { vue = vue({ 'flou' }) }).note, true)
    local version, fichier = Carnet.version, S.fichiers[Carnet.fichier()]
    local ecritures, privees = #S.ecritures, S.ecrituresPrivees
    local r = Commandes.executer('lecon', { action = 'garder', photo = 7, lecon = lecon() })
    egal(r.rangee, false)
    egal(r.remplacee, false)
    egal(r.motif, 'essai')
    egal(r.photo, 7)
    egal(r.fichier, 'DSC_0412.NEF (Essai)')
    egal(r.original, nil, "aucune entrée visée")
    egal(r.remarque, "Photo d'essai (Développeur › Essais) : sa leçon n'entre pas au carnet de progrès, qui ne compte que les "
        .. "vraies prises de vue. La leçon de cette réponse reste valable.")
    egal(Carnet.version, version, "rien n'est rangé")
    egal(S.fichiers[Carnet.fichier()], fichier, "carnet.json inchangé")
    egal(next(Carnet.entree(1).lecons), nil, "rien sous l'original")
    egal(Carnet.lecon(7), nil)
    egal(Carnet.nombre(), 1)
    egal(#S.ecritures, ecritures, "rien dans le catalogue")
    egal(S.ecrituresPrivees, privees)
    -- La photo active, sans photo donnée ; et par la prise de la liaison : une réponse, jamais une
    -- erreur (photo_lesson le dit sans échouer).
    S.active = copie
    egal(Commandes.executer('lecon', { action = 'garder', lecon = lecon() }).rangee, false, "la photo active aussi")
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 21, command = 'lecon', params = { action = 'garder', photo = 7, lecon = lecon() } }))
    Liaison.prise = nil
    local reponse = Json.decode(S.envois[#S.envois])
    egal(reponse.error, nil)
    egal(reponse.result.rangee, false)
    egal(reponse.result.motif, 'essai')
    egal(Carnet.version, version)
    -- Une leçon invalide reste refusée d'abord, photo d'essai ou pas.
    echoue(function() Commandes.executer('lecon', { action = 'garder', photo = 7, lecon = { points = {} } }) end, "trois points")

    -- Pour la recette (essai_recette) : rangée, sous l'entrée de la photo d'essai elle-même.
    r = Commandes.executer('lecon', { action = 'garder', photo = 7, lecon = lecon(), essai_recette = true })
    egal(r.rangee, true)
    egal(r.photo, 7)
    egal(r.original, 7, "une entrée à elle, jamais celle de son original")
    egal(r.mois, '2026-06', "au mois de sa prise de vue")
    egal(Carnet.nombre(), 2)
    egal(Carnet.entree(7).lecons['7'] ~= nil, true)
    egal(next(Carnet.entree(1).lecons), nil, "toujours rien sous l'original")
    -- Retirée par la recette : l'entrée de la photo d'essai part avec elle ; celle de l'original reste.
    egal(Commandes.executer('lecon', { action = 'retirer', photo = 7 }).retirees, 1)
    egal(Carnet.entree(7), nil)
    egal(table.concat(Carnet.entree(1).vue.cherches, ','), 'flou')
    -- Une vraie photo se range comme avant, sans essai_recette.
    egal(Commandes.executer('lecon', { action = 'garder', photo = 1, lecon = lecon() }).rangee, true)
end)

test("carnet constater : case Carnet décochée, tout constat est refusé sans rien lire ; lire et retirer marchent toujours", function()
    photoRaw()
    S.prefs.carnet = false
    local r = constater(1, { vue = vueType() })
    egal(r.note, false)
    egal(r.motif, 'preference')
    egal(r.photo, 1)
    egal(r.raison, "Carnet de progrès décoché dans le Gestionnaire de modules externes : rien n'est noté.")
    egal(constater(1, { angle = angle(1) }).motif, 'preference')
    egal(constater(999, { vue = vueType() }).motif, 'preference', "la photo n'est même pas cherchée")
    egal(S.fichiers[Carnet.fichier()], nil)
    egal(Commandes.executer('carnet', { action = 'lire' }).nombre, 0)
    S.prefs.carnet = true
    egal(constater(1, { vue = vueType() }).note, true)
    S.prefs.carnet = false
    egal(Commandes.executer('carnet', { action = 'retirer', photos = { 1 } }).retirees, 1)
end)

test("carnet constater : refus avant toute écriture (photo, vue ou angle, vocabulaire, codes, défaut non cherché, mesure, texte, inclinaison)", function()
    S.active = photoRaw()
    local version = Carnet.version
    -- Sans photo, jamais la photo active : le constat vaut pour la photo mesurée.
    echoue(function() Commandes.executer('carnet', { action = 'constater', vue = vueType(), vocabulaire = VOCABULAIRE }) end,
        "Constat : photo manquante (l'identifiant de la photo mesurée).")
    echoue(function() constater(Json.null, { vue = vueType() }) end, "photo manquante")
    local function avecVocabulaire(vocabulaire)
        return function()
            Commandes.executer('carnet', { action = 'constater', photo = 1, vue = vueType(), vocabulaire = vocabulaire })
        end
    end
    echoue(function() constater(1, {}) end,
        "Constat : donner vue (défauts mesurés sur l'aperçu entier) ou angle (ligne mesurée), l'un ou l'autre.")
    echoue(function() constater(1, { vue = vueType(), angle = angle(1) }) end, "l'un ou l'autre")
    echoue(avecVocabulaire(nil), "Constat : vocabulaire manquant (la liste des défauts du connecteur).")
    echoue(avecVocabulaire({}), "vocabulaire manquant")
    echoue(avecVocabulaire({ { code = 'flou' } }), "Constat, vocabulaire : « flou » n'a pas de libellé.")
    echoue(avecVocabulaire({ { code = 'flou', libelle = "Flou" }, { code = 'flou', libelle = "Flou" } }),
        "Constat, vocabulaire : le code « flou » est donné deux fois.")
    echoue(avecVocabulaire({ { code = 'Flou', libelle = "Flou" } }), "code de défaut invalide « Flou »")
    echoue(avecVocabulaire({ { code = 'flou', libelle = "Flou", domaine = 'Netteté' } }),
        "Constat, vocabulaire : domaine invalide « Netteté » (lettres minuscules et _).")
    echoue(avecVocabulaire({ { code = 'flou', libelle = "Flou", mesure = 'oui' } }), "mesure de « flou » est vrai ou faux")
    local quarante = {}
    for i = 1, 41 do
        quarante[i] = { code = 'defaut_' .. string.rep('a', i), libelle = "Défaut" }
    end
    echoue(avecVocabulaire(quarante), "Constat : vocabulaire de 41 défauts, 40 au plus.")

    echoue(function() constater(1, { vue = 'flou' }) end, "Constat : vue est un objet { cherches, defauts }.")
    echoue(function() constater(1, { vue = vue('flou') }) end, "Constat, cherches est une liste.")
    echoue(function() constater(1, { vue = vue({ 'Flou' }) }) end,
        "Constat, cherches : code de défaut invalide « Flou » (lettres minuscules et _).")
    echoue(function() constater(1, { vue = vue({ 'yeux_fermes' }) }) end,
        "Constat, cherches : « yeux_fermes » n'est pas dans le vocabulaire.")
    local treize = {}
    for i = 1, 13 do
        treize[i] = 'flou'
    end
    echoue(function() constater(1, { vue = vue(treize) }) end, "Constat, cherches : 13 codes, 12 au plus.")
    echoue(function() constater(1, { vue = vue({ 'flou' }, treize) }) end, "Constat, defauts : 13 codes, 12 au plus.")
    echoue(function() constater(1, { vue = vue({}) }) end, "Constat : cherches est vide (les défauts cherchés sur cette vue).")
    echoue(function() constater(1, { vue = vue({ 'flou' }, { 'bruit' }) }) end, "Constat : le défaut « bruit » n'est pas dans cherches.")
    echoue(function() constater(1, { vue = vue({ 'flou' }, { { code = 'flou', mesure = 'beaucoup' } }) }) end,
        "Constat, defauts : mesure est un nombre.")
    echoue(function() constater(1, { vue = vue({ 'flou' }, { { code = 'flou', mesure = 0 / 0 } }) }) end, "mesure est un nombre")
    echoue(function() constater(1, { vue = vue({ 'flou' }, { { code = 'flou', texte = string.rep('x', 201) } }) }) end,
        "Constat, defauts, texte : 200 octets au plus.")
    echoue(function() constater(1, { vue = vue({ 'flou' }, { { code = 'dominante' } }) }) end, "« dominante » n'est pas dans cherches")

    echoue(function() constater(1, { angle = 1.5 }) end, "Constat : angle est un objet { inclinaison, code, source }.")
    echoue(function() constater(1, { angle = { code = 'horizon_penche' } }) end,
        "Constat : inclinaison manquante ou non numérique (en degrés).")
    echoue(function() constater(1, { angle = { inclinaison = '1,2', code = 'horizon_penche' } }) end, "inclinaison manquante")
    echoue(function() constater(1, { angle = { inclinaison = math.huge, code = 'horizon_penche' } }) end, "inclinaison manquante")
    echoue(function() constater(1, { angle = { inclinaison = 1.2 } }) end, "Constat, angle : code de défaut invalide « nil »")
    echoue(function() constater(1, { angle = { inclinaison = 1.2, code = 'verticales' } }) end,
        "Constat, angle : « verticales » n'est pas dans le vocabulaire.")
    echoue(function() constater(1, { angle = { inclinaison = 1.2, code = 'horizon_penche', source = 'measure angle' } }) end,
        "Constat, angle : source invalide « measure angle » (lettres minuscules et _).")

    echoue(function() constater(999, { vue = vueType() }) end, "Aucune photo n'a l'identifiant 999")
    echoue(function() Commandes.executer('carnet', { action = 'noter' }) end,
        "Action du carnet inconnue : noter (constater, lire ou retirer).")
    egal(S.fichiers[Carnet.fichier()], nil, "rien n'est rangé")
    egal(Carnet.version, version)
end)

-- La lecture de la photo passe par le catalogue : dans Lightroom, la tâche peut y rendre la main,
-- et une autre commande passer (ici, au moment où constater lit le nom du fichier). constater lit
-- tout avant de toucher au registre : l'autre commande ne voit jamais d'entrée à moitié faite, et
-- le constat dit noté l'est.
test("carnet constater : une autre commande pendant la lecture de la photo ne voit jamais d'entrée à moitié faite", function()
    local photo = photoRaw()
    local lire = photo.getFormattedMetadata
    local pendant
    photo.getFormattedMetadata = function(self, cle)
        if cle == 'fileName' and not pendant then
            pendant = Commandes.executer('carnet', { action = 'lire' })
        end
        return lire(self, cle)
    end
    local r = constater(1, { vue = vueType() })
    egal(pendant ~= nil, true, "l'autre commande est passée pendant la lecture")
    egal(pendant.nombre, 0, "elle n'a vu aucune entrée à moitié faite")
    egal(r.note, true)
    egal(Carnet.entree(1).vue ~= nil, true)

    -- Une entrée retirée pendant la lecture : le constat qui suit range une entrée neuve, au carnet.
    pendant = nil
    photo.getFormattedMetadata = function(self, cle)
        if cle == 'fileName' and not pendant then
            pendant = Commandes.executer('carnet', { action = 'retirer', photos = { 1 } })
        end
        return lire(self, cle)
    end
    r = constater(1, { angle = angle(2.1) })
    photo.getFormattedMetadata = lire
    egal(pendant.retirees, 1)
    egal(r.note, true)
    local e = Carnet.entree(1)
    egal(e ~= nil, true, "le constat dit noté est au carnet")
    proche(e.angle.inclinaison, 2.1)
    egal(e.vue, nil, "la vue retirée ne revient pas")
    egal(fichierRelu().catalogues[CATALOGUE].photos['1'].angle.code, 'horizon_penche', "et dans carnet.json")
end)

test("carnet constater : fichier non écrit, le constat reste pour la session avec une remarque", function()
    photoRaw()
    local Fichiers = require 'Fichiers'
    local ecrire = Fichiers.ecrire
    Fichiers.ecrire = function() error("Écriture impossible : disque plein", 0) end
    local ok, r = pcall(constater, 1, { vue = vueType() })
    Fichiers.ecrire = ecrire
    assert(ok, r)
    egal(r.note, true)
    egal(r.remarque, "Constat gardé pour cette session, carnet.json non écrit : Écriture impossible : disque plein")
    egal(Carnet.entree(1).vue ~= nil, true)
    egal(S.fichiers[Carnet.fichier()], nil)
end)

-- Lire, retirer, registre ------------------------------------------------------------------------

test("carnet lire : constats et leçons de chaque photo vers le serveur ; copies neuves sans métatable pour la fenêtre", function()
    local original = photoRaw()
    S.copieVirtuelle(original, 7, 'Copie 1')
    constater(7, { vue = vueType() })
    constater(1, { angle = angle(1.4, 'read_composition') })
    Commandes.executer('lecon', { action = 'garder', photo = 7, lecon = lecon() })
    local ecritures = #S.ecritures
    local lu = Commandes.executer('carnet', { action = 'lire' })
    egal(lu.nombre, 1)
    egal(lu.resume, nil, "le résumé seulement sur demande")
    local entree = lu.photos[1]
    egal(entree.vue.photo, 7)
    egal(entree.vue.defauts[1].code, 'ciel_brule')
    egal(entree.angle.source, 'read_composition')
    egal(#entree.lecons, 1, "les leçons de chaque photo")
    egal(entree.lecons[1].photo, 7)
    egal(entree.uuid, nil)
    egal(#S.ecritures, ecritures, "lire n'écrit rien")

    local maintenant = os.time()
    sansMetatable(Carnet.entrees(), 'entrees')
    sansMetatable(Carnet.vocabulaire(), 'vocabulaire')
    sansMetatable(Carnet.resumer(maintenant), 'resume')
    sansMetatable(Carnet.photosDuDefaut('ciel_brule', maintenant), 'photosDuDefaut')
    local copie = Carnet.entree(1)
    copie.vue.defauts[1].code = 'change'
    Carnet.vocabulaire()[1].libelle = 'change'
    egal(Carnet.entree(1).vue.defauts[1].code, 'ciel_brule', "une copie : le registre ne change pas")
    egal(Carnet.vocabulaire()[1].libelle, "Horizon ou ligne penchée")

    Carnet.oublier()
    sansMetatable(Carnet.entrees(), 'entrees relues')
    sansMetatable(Carnet.resumer(maintenant), 'resume relu')
    egal(Carnet.entree(1).vue.defauts[1].texte, "ciel brûlé : 4,2 % du tiers haut en blanc pur", "relu du fichier")
    proche(Carnet.entree(1).angle.inclinaison, 1.4)
    egal(Carnet.vocabulaire()[6].code, 'mise_au_point', "le vocabulaire relu, dans son ordre")
end)

test("carnet : par la prise de la liaison, pendant la pause : constater, puis lire avec le résumé en tableaux JSON", function()
    photoJpeg()
    Liaison.pause = true
    Liaison.prise = { send = function(self, texte) S.envois[#S.envois + 1] = texte end }
    Liaison.reponsesConnectee = true
    Liaison.recevoir(ligne({ id = 9, command = 'carnet', params = { action = 'constater', photo = 2, vue = vueType(),
        vocabulaire = VOCABULAIRE } }))
    Liaison.recevoir(ligne({ id = 10, command = 'carnet', params = { action = 'lire', resume = true } }))
    Liaison.prise = nil
    local constat = Json.decode(S.envois[1])
    egal(constat.error, nil)
    egal(constat.result.note, true)
    egal(constat.result.sans_date, true)
    local texte = S.envois[2]
    local lu = Json.decode(texte).result
    egal(lu.nombre, 1)
    local resume = lu.resume
    egal(#resume.mois, 1, "sans date : au mois du constat")
    egal(resume.mois[1].cle, os.date('%Y-%m'))
    egal(resume.photos, 1)
    egal(resume.titres.a_travailler, "À travailler à la prochaine sortie")
    egal(codes(resume.defauts), 'horizon_penche,sous_exposition,ciel_brule,bruit,flou,mise_au_point', "l'ordre du vocabulaire")
    egal(resume.defauts[3].par_mois[1].n, 1)
    egal(resume.remarque, "Seulement 1 photo : le carnet dira plus après quelques sorties.")
    for _, liste in ipairs({ '"progresse":[]', '"recule":[]', '"a_travailler":[]', '"par_mois":[{', '"mois":[{', '"defauts":[{' }) do
        egal(texte:find(liste, 1, true) ~= nil, true, liste)
    end
end)

test("carnet : un autre catalogue a son carnet ; le premier garde le sien ; le vocabulaire vaut pour tous", function()
    photoRaw()
    photoJpeg()
    constater(1, { vue = vueType() })
    S.cheminCatalogue = AUTRE
    egal(Carnet.nombre(), 0, "l'autre catalogue a son carnet, vide")
    egal(Carnet.resumer(os.time()).vide, true)
    egal(constater(2, { angle = angle(0.8) }).note, true)
    egal(Carnet.nombre(), 1)
    egal(Carnet.vocabulaire()[1].code, 'horizon_penche')
    local relu = fichierRelu()
    egal(relu.catalogues[AUTRE].photos['2'].angle.code, 'horizon_penche')
    egal(relu.catalogues[CATALOGUE].photos['1'].vue.defauts[1].code, 'ciel_brule', "le premier catalogue garde sa table")
    Carnet.oublier()
    S.cheminCatalogue = CATALOGUE
    egal(Carnet.nombre(), 1)
    egal(Carnet.entree(1).vue.defauts[1].code, 'ciel_brule')
    egal(Carnet.entree(2), nil)
    -- Un catalogue dont le chemin ne se lit pas : rien ne s'y constate, son résumé est vide.
    S.cheminCatalogue = nil
    echoue(function() constater(1, { vue = vueType() }) end, "Chemin du catalogue ouvert illisible")
    egal(Carnet.resumer(os.time()).vide, true)
end)

test("carnet : une vue ou un angle illisible dans le fichier est ignoré à la relecture", function()
    fabriquer({
        { photo = 1, prise = '2026-09', vue = { le = 1, cherches = 'flou', defauts = { 'flou', { mesure = 2 } } },
            angle = { inclinaison = 1.5 } },
        { photo = 2, prise = '2026-09', vue = { le = 1, cherches = { 3 }, defauts = { { code = 'flou', mesure = 'x' } } },
            angle = { inclinaison = 'penché', code = 'horizon_penche' } },
    })
    local e1, e2 = Carnet.entree(1), Carnet.entree(2)
    egal(#e1.vue.cherches, 0)
    egal(#e1.vue.defauts, 0)
    egal(e1.angle, nil, "un angle sans code ne compte pas")
    egal(#e2.vue.cherches, 0)
    egal(e2.vue.defauts[1].mesure, nil)
    egal(e2.angle, nil)
    local resume = Carnet.resumer(le(2026, 10))
    egal(resume.photos, 1, "seule la photo où un défaut a été cherché compte")
    egal(defautDe(resume, 'flou').n, 1, "un défaut trouvé est aussi cherché")
end)

test("carnet : élagage au-delà de MAX_PHOTOS par un constat ; retirer une entrée et ses constats", function()
    photoRaw()
    fabriquer({
        { photo = 11, le = 300, vue = { le = 300, cherches = { 'flou' }, defauts = {} } },
        { photo = 12, le = 100, vue = { le = 100, cherches = { 'flou' }, defauts = {} } },
        { photo = 13, le = 200, angle = { le = 200, inclinaison = 1, code = 'horizon_penche' } },
    })
    egal(Carnet.nombre(), 3)
    local max = Carnet.MAX_PHOTOS
    Carnet.MAX_PHOTOS = 3
    constater(1, { vue = vueType() })
    Carnet.MAX_PHOTOS = max
    egal(Carnet.nombre(), 3)
    egal(Carnet.entree(12), nil, "la plus ancienne sort")
    egal(Carnet.entree(13).angle.code, 'horizon_penche')
    egal(Carnet.entree(1).vue.photo, 1)
    egal(Commandes.executer('carnet', { action = 'retirer', photos = { 1, 13 } }).retirees, 2)
    egal(Carnet.nombre(), 1)
    egal(fichierRelu().catalogues[CATALOGUE].photos['1'], nil)
end)

-- Résumé ------------------------------------------------------------------------------------------

test("résumé : les six derniers mois de prise de vue qui ont des photos, en français, dans l'ordre ; sans date au mois du constat ; après aujourd'hui pas compté", function()
    egal(table.concat(Carnet.MOIS, ' '), "janvier février mars avril mai juin juillet août septembre octobre novembre décembre")
    egal(table.concat(Carnet.MOIS_COURTS, ' '), "janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.")
    local entrees = {}
    serie(entrees, '2025-09', 1, { 'flou' })
    serie(entrees, '2025-10', 1, { 'flou' })
    serie(entrees, '2025-12', 2, { 'flou' })
    serie(entrees, '2026-01', 1, { 'flou' })
    serie(entrees, '2026-02', 1, { 'flou' })
    serie(entrees, '2026-03', 1, { 'flou' })
    serie(entrees, '2026-05', 1, { 'flou' })
    -- Sans date de prise de vue : au mois de son constat (mai 2026).
    entrees[#entrees + 1] = { sans_date = true, vue = { le = le(2026, 5, 10), cherches = { 'flou' }, defauts = { { code = 'flou' } } } }
    -- Datée après aujourd'hui (juin 2026) : pas comptée.
    serie(entrees, '2026-07', 1, { 'flou' }, function() return { 'flou' } end)
    -- Une leçon seule, sans constat : pas comptée, et avril n'est pas un mois du carnet.
    entrees[#entrees + 1] = { prise = '2026-04', lecons = { ['77'] = { photo = 77, points = {}, defauts = { 'flou' } } } }
    fabriquer(entrees)

    local resume = Carnet.resumer(le(2026, 6))
    egal(resume.vide, false)
    local cles, noms, courts, photos, recents = {}, {}, {}, {}, {}
    for _, m in ipairs(resume.mois) do
        cles[#cles + 1] = m.cle
        noms[#noms + 1] = m.libelle
        courts[#courts + 1] = m.court
        photos[#photos + 1] = m.photos
        recents[#recents + 1] = m.recent and 'r' or '-'
    end
    egal(table.concat(cles, ' '), '2025-10 2025-12 2026-01 2026-02 2026-03 2026-05', "les six derniers qui ont des photos")
    egal(table.concat(noms, ', '), "octobre 2025, décembre 2025, janvier 2026, février 2026, mars 2026, mai 2026")
    egal(table.concat(courts, ' '), "oct. déc. janv. févr. mars mai")
    egal(table.concat(photos, ' '), '1 2 1 1 1 2', "mai : la photo datée et celle sans date")
    egal(table.concat(recents, ''), '----rr', "les deux derniers mois sont les récents")
    egal(resume.mois[6].nom, 'mai')
    egal(resume.mois[6].annee, 2026)
    egal(resume.mois[6].numero, 5)
    egal(resume.photos, 8)
    egal(resume.periode, "d'octobre 2025 à mai 2026")
    egal(resume.note, "Défauts de la prise de vue mesurés par Claude sur 8 photos, par mois de prise de vue (d'octobre 2025 à mai 2026). "
        .. "Seules les photos montrées à Claude comptent, pas toute la sortie.")
    egal(resume.remarque, "1 photo datée après aujourd'hui n'est pas comptée (horloge de l'appareil ?).")
    egal(resume.le, le(2026, 6))
    local flou = defautDe(resume, 'flou')
    egal(flou.par_mois[6].n, 1, "la photo sans date a son défaut en mai")
    egal(flou.par_mois[6].sur, 2)
    egal(flou.sur, 8)

    -- Deux photos datées après aujourd'hui.
    serie(entrees, '2026-08', 1, { 'flou' })
    fabriquer(entrees)
    egal(Carnet.resumer(le(2026, 6)).remarque, "2 photos datées après aujourd'hui ne sont pas comptées (horloge de l'appareil ?).")
    -- Plus tard, elles comptent : les six derniers mois glissent.
    resume = Carnet.resumer(le(2026, 9))
    egal(resume.mois[1].cle, '2026-01')
    egal(resume.mois[6].cle, '2026-08')
    egal(resume.periode, "de janvier à août 2026")
    egal(resume.remarque, nil)
end)

test("résumé : chaque défaut sur sa propre base (mise au point si le point AF est lu, horizon par l'angle) ; ordre du vocabulaire, puis les codes inconnus", function()
    local entrees = {}
    serie(entrees, '2026-09', 3, { 'flou', 'mise_au_point', 'bruit' }, function(i)
        return ({ { 'mise_au_point' }, { 'flou' }, {} })[i]
    end)
    serie(entrees, '2026-09', 2, { 'flou', 'bruit', 'yeux_fermes' }, function(i) return i == 1 and { 'bruit' } or {} end)
    entrees[#entrees + 1] = { prise = '2026-09', fichier = 'DSCF0001.RAF', angle = { le = 1, photo = 501, inclinaison = 1.4,
        code = 'horizon_penche', source = 'measure_angle' } }
    serie(entrees, '2026-09', 1, { 'horizon_penche', 'flou' })
    fabriquer(entrees)
    local resume = Carnet.resumer(le(2026, 10))
    egal(resume.photos, 7)
    egal(codes(resume.defauts), 'horizon_penche,bruit,flou,mise_au_point,yeux_fermes')
    local function base(code)
        local d = defautDe(resume, code)
        return d.n .. '/' .. d.sur
    end
    egal(base('horizon_penche'), '1/2', "l'angle compte dans la base et comme défaut")
    egal(base('bruit'), '1/5')
    egal(base('flou'), '1/6')
    egal(base('mise_au_point'), '1/3', "seulement les photos au point AF lu")
    egal(base('yeux_fermes'), '0/2')
    egal(defautDe(resume, 'yeux_fermes').libelle, 'yeux_fermes', "un code hors du vocabulaire garde son code")
    egal(defautDe(resume, 'flou').libelle, "Photo floue ou bougée")
    egal(defautDe(resume, 'flou').domaine, 'nettete')
    egal(defautDe(resume, 'mise_au_point').taux, 33)
    egal(defautDe(resume, 'yeux_fermes').taux, 0)

    local horizon = Carnet.photosDuDefaut('horizon_penche', le(2026, 10))
    egal(#horizon, 1)
    egal(horizon[1].fichier, 'DSCF0001.RAF')
    egal(horizon[1].photo, 501, "la photo mesurée")
    proche(horizon[1].mesure, 1.4)
    egal(horizon[1].mois, '2026-09')
    egal(horizon[1].mois_libelle, 'septembre 2026')
    local map = Carnet.photosDuDefaut('mise_au_point', le(2026, 10))
    egal(#map, 1)
    egal(map[1].mesure, 1)
    egal(#Carnet.photosDuDefaut('dominante', le(2026, 10)), 0)
end)

test("résumé : progresse et recule à 15 points (pas 14), avec 5 photos de chaque côté (pas 4) ; le mois le plus ancien hors tendance", function()
    local entrees = {}
    -- Mai : hors tendance (les deux derniers mois contre les trois d'avant). Compté, le ciel brûlé
    -- d'avant passerait de 10 % à 22 % et ne reculerait plus.
    serie(entrees, '2026-05', 3, { 'ciel_brule' }, function() return { 'ciel_brule' } end)
    -- Juin à août : 20 photos ; sous-exposées 5 (25 %), ciel brûlé 2 (10 %), bruit 4 ; puis 5
    -- photos où seul le bruit est cherché, 2 bruitées (bruit : 6 sur 25, 24 %).
    local n = 0
    for _, m in ipairs({ { '2026-06', 7 }, { '2026-07', 7 }, { '2026-08', 6 } }) do
        serie(entrees, m[1], m[2], { 'sous_exposition', 'ciel_brule', 'bruit' }, function()
            n = n + 1
            local t = {}
            if n <= 5 then t[#t + 1] = 'sous_exposition' end
            if n == 6 or n == 7 then t[#t + 1] = 'ciel_brule' end
            if n >= 8 and n <= 11 then t[#t + 1] = 'bruit' end
            return t
        end)
    end
    serie(entrees, '2026-06', 5, { 'bruit' }, function(i) return i <= 2 and { 'bruit' } or {} end)
    -- Septembre et octobre : 20 photos ; sous-exposées 2 (10 %), ciel brûlé 5 (25 %), bruit 2 (10 %).
    n = 0
    for _, m in ipairs({ { '2026-09', 10 }, { '2026-10', 10 } }) do
        serie(entrees, m[1], m[2], { 'sous_exposition', 'ciel_brule', 'bruit' }, function()
            n = n + 1
            local t = {}
            if n <= 2 then t[#t + 1] = 'sous_exposition' end
            if n >= 3 and n <= 7 then t[#t + 1] = 'ciel_brule' end
            if n == 8 or n == 9 then t[#t + 1] = 'bruit' end
            return t
        end)
    end
    -- Flou : 5 photos avant, toutes floues ; 4 récentes, aucune (base de 4 : pas de tendance).
    serie(entrees, '2026-07', 5, { 'flou' }, function() return { 'flou' } end)
    serie(entrees, '2026-10', 4, { 'flou' })
    -- Mise au point : 5 avant, toutes manquées ; 5 récentes, aucune (base de 5 : tendance).
    serie(entrees, '2026-08', 5, { 'mise_au_point' }, function() return { 'mise_au_point' } end)
    serie(entrees, '2026-09', 5, { 'mise_au_point' })
    fabriquer(entrees)

    local resume = Carnet.resumer(le(2026, 10, 20))
    egal(#resume.mois, 6)
    egal(resume.mois[1].cle, '2026-05')
    local sous = defautDe(resume, 'sous_exposition')
    egal(sous.avant.n .. '/' .. sous.avant.sur, '5/20')
    egal(sous.recent.n .. '/' .. sous.recent.sur, '2/20')
    egal(sous.tendance, 'progresse', "25 % → 10 % : 15 points")
    egal(defautDe(resume, 'ciel_brule').tendance, 'recule', "10 % → 25 % : 15 points, mai hors du calcul")
    egal(defautDe(resume, 'ciel_brule').avant.sur, 20)
    local bruit = defautDe(resume, 'bruit')
    egal(bruit.avant.n .. '/' .. bruit.avant.sur, '6/25')
    egal(bruit.tendance, nil, "24 % → 10 % : 14 points, pas de tendance")
    egal(defautDe(resume, 'flou').tendance, nil, "4 photos récentes : pas de tendance")
    egal(defautDe(resume, 'mise_au_point').tendance, 'progresse', "5 photos de chaque côté")
    egal(codes(resume.progresse), 'sous_exposition,mise_au_point')
    egal(codes(resume.recule), 'ciel_brule')
    egal(resume.progresse[1].texte, "Photo sous-exposée : 25 % des photos de juin à août 2026, 10 % en septembre et octobre 2026.")
    egal(resume.progresse[2].texte, "Mise au point à côté : 100 % des photos de juin à août 2026, 0 % en septembre et octobre 2026.")
    egal(resume.recule[1].texte, "Ciel ou haut de l'image brûlé : 10 % des photos de juin à août 2026, 25 % en septembre et octobre 2026.")
    egal(resume.aucune_tendance, nil)
    -- À travailler : seul le ciel brûlé revient sur 20 % des photos récentes (5 sur 20).
    egal(codes(resume.a_travailler), 'ciel_brule')
    local ciel = resume.a_travailler[1]
    egal(ciel.texte, "Ciel ou haut de l'image brûlé : 5 photos sur 20 (25 %) en septembre et octobre 2026.")
    egal(ciel.conseil, VOCABULAIRE[3].conseil)
    egal(ciel.prise_de_vue, "À la prise de vue : " .. VOCABULAIRE[3].conseil)
    egal(ciel.taux, 25)
    egal(resume.rien_a_travailler, nil)
    egal(resume.titres.progresse, "Ce qui progresse")
    egal(resume.titres.recule, "Ce qui recule")

    -- Les seuils viennent des constantes : à 16 points, le bruit non plus, la mise au point oui.
    local ecart = Carnet.ECART_TENDANCE
    Carnet.ECART_TENDANCE = 16
    resume = Carnet.resumer(le(2026, 10, 20))
    Carnet.ECART_TENDANCE = ecart
    egal(codes(resume.progresse), 'mise_au_point')
    egal(codes(resume.recule), '')
end)

test("résumé : à travailler à 20 % et 2 photos au moins sur les mois récents, le plus fréquent d'abord, trois au plus, avec son conseil", function()
    local entrees = {}
    serie(entrees, '2026-10', 10, { 'sous_exposition', 'horizon_penche', 'ciel_brule', 'mise_au_point', 'flou', 'bruit' }, function(i)
        local t = {}
        if i <= 5 then t[#t + 1] = 'sous_exposition' end
        if i <= 4 then t[#t + 1] = 'horizon_penche' end
        if i <= 3 then t[#t + 1] = 'mise_au_point' end
        if i <= 2 then t[#t + 1] = 'ciel_brule' end
        if i <= 2 then t[#t + 1] = 'flou' end
        if i == 1 then t[#t + 1] = 'bruit' end
        return t
    end)
    -- Le flou est cherché sur une photo de plus (2 sur 11 : 18 %) ; le bruit sur 5 seulement
    -- (1 sur 5 : 20 %, mais une seule photo).
    serie(entrees, '2026-10', 1, { 'flou' })
    for i = 6, 10 do
        local e = entrees[i]
        for k = #e.vue.cherches, 1, -1 do
            if e.vue.cherches[k] == 'bruit' then
                table.remove(e.vue.cherches, k)
            end
        end
    end
    fabriquer(entrees)
    local resume = Carnet.resumer(le(2026, 10, 20))
    egal(defautDe(resume, 'bruit').sur, 5)
    egal(defautDe(resume, 'flou').sur, 11)
    egal(codes(resume.a_travailler), 'sous_exposition,horizon_penche,mise_au_point', "50, 40 et 30 % ; le ciel brûlé (20 %) au-delà de trois")
    egal(resume.a_travailler[1].texte, "Photo sous-exposée : 5 photos sur 10 (50 %) en octobre 2026.")
    egal(resume.a_travailler[2].prise_de_vue, "À la prise de vue : " .. VOCABULAIRE[1].conseil)
    egal(resume.a_travailler[3].n, 3)
    egal(resume.a_travailler[3].sur, 10)
    egal(resume.aucune_tendance, "Pas encore de tendance : il faut 5 photos au moins sur les 2 derniers mois, et 5 sur les 3 d'avant.")

    local max = Carnet.MAX_A_TRAVAILLER
    Carnet.MAX_A_TRAVAILLER = 10
    resume = Carnet.resumer(le(2026, 10, 20))
    Carnet.MAX_A_TRAVAILLER = max
    egal(codes(resume.a_travailler), 'sous_exposition,horizon_penche,mise_au_point,ciel_brule',
        "20 % et 2 photos : oui ; 18 % (flou) et une seule photo (bruit) : non")

    -- À taux égal, le plus de photos d'abord, puis l'ordre du vocabulaire.
    entrees = {}
    serie(entrees, '2026-10', 10, { 'ciel_brule', 'sous_exposition' }, function(i) return i <= 3 and { 'ciel_brule', 'sous_exposition' } or {} end)
    serie(entrees, '2026-10', 5, { 'flou' }, function(i) return i <= 2 and { 'flou' } or {} end)
    serie(entrees, '2026-10', 20, { 'bruit' }, function(i) return i <= 8 and { 'bruit' } or {} end)
    fabriquer(entrees)
    egal(codes(Carnet.resumer(le(2026, 10, 20)).a_travailler), 'bruit,flou,sous_exposition', "40 % (8), 40 % (2), puis 30 %")
end)

test("résumé : remarque sous 5 photos, aucune à 5 ; rien à travailler ; carnet vide", function()
    local resume = Carnet.resumer(le(2026, 10))
    egal(resume.vide, true)
    egal(resume.photos, 0)
    egal(#resume.mois, 0)
    egal(#resume.defauts, 0)
    egal(resume.periode, nil)
    egal(resume.note, "Le carnet se remplit tout seul : quand Claude regarde une photo pas encore retouchée, "
        .. "les défauts mesurés de sa prise de vue y sont notés, par mois de prise de vue.")
    egal(resume.remarque, nil)
    egal(resume.aucune_tendance, nil)
    egal(resume.rien_a_travailler, nil)
    egal(resume.titres.carnet, "Carnet de progrès")
    egal(resume.titres.defaut, "Défaut")

    local entrees = {}
    serie(entrees, '2026-10', 4, { 'flou' }, function(i) return i == 1 and { 'flou' } or {} end)
    fabriquer(entrees)
    resume = Carnet.resumer(le(2026, 10))
    egal(resume.remarque, "Seulement 4 photos : le carnet dira plus après quelques sorties.")
    egal(resume.periode, "en octobre 2026")
    egal(#resume.a_travailler, 0)
    egal(resume.rien_a_travailler, "Aucun défaut ne revient sur 20 % des photos ou plus en octobre 2026.")
    serie(entrees, '2026-09', 1, { 'flou' })
    fabriquer(entrees)
    resume = Carnet.resumer(le(2026, 10))
    egal(resume.remarque, nil, "5 photos")
    egal(resume.periode, "en septembre et octobre 2026")
    egal(resume.rien_a_travailler, "Aucun défaut ne revient sur 20 % des photos ou plus en septembre et octobre 2026.")

    entrees = {}
    serie(entrees, '2025-12', 1, { 'flou' })
    serie(entrees, '2026-01', 1, { 'flou' })
    fabriquer(entrees)
    resume = Carnet.resumer(le(2026, 2))
    egal(resume.remarque, "Seulement 2 photos : le carnet dira plus après quelques sorties.")
    egal(resume.periode, "en décembre 2025 et janvier 2026")
    entrees = {}
    serie(entrees, '2026-04', 1, { 'flou' })
    fabriquer(entrees)
    resume = Carnet.resumer(le(2026, 4))
    egal(resume.remarque, "Seulement 1 photo : le carnet dira plus après quelques sorties.")
    egal(resume.periode, "en avril 2026")
    egal(resume.note, "Défauts de la prise de vue mesurés par Claude sur 1 photo, par mois de prise de vue (en avril 2026). "
        .. "Seules les photos montrées à Claude comptent, pas toute la sortie.")
end)

A.bilan()
